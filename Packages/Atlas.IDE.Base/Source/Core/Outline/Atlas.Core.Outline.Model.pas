unit Atlas.Core.Outline.Model;

// Gliederungsfenster (#537), Kern ohne VCL und OTA:
// - FromJson liest die Antwort von textDocument/documentSymbol samt der
//   Atlas-Angaben ("atlas": Sichtbarkeit, Klassenmitglied, override, virtual,
//   abstract, nicht implementiert) in eine flache Liste mit Eltern und Tiefe.
//   Die Unit selbst entfällt, interface und implementation bleiben Abschnitte.
// - Rümpfe von Methoden (TFoo.Bar) und Rümpfe von Routinen, die im interface
//   deklariert sind, sind verborgen: Sie gehören zu ihrer Deklaration (Body),
//   und der Cursor in ihnen hebt die Deklaration hervor (NodeAt). Lokale
//   Routinen und Typen in Rümpfen erscheinen nicht.
// - Rows filtert unscharf nach Namen, nach Sichtbarkeit und nach Art und
//   sortiert in Quelltextreihenfolge oder alphabetisch. Eltern von Treffern
//   bleiben als Rahmen stehen.

interface

uses
  System.SysUtils,
  System.JSON;

type
{$SCOPEDENUMS ON}
  /// <summary>None: außerhalb von Typen (globale Deklarationen, Typen auf Unit-Ebene).</summary>
  TAtlasOutlineVisibility = (None, StrictPrivate, Private, StrictProtected, Protected, Public, Published);
  TAtlasOutlineCategory = (Section, TypeDecl, Field, Method, PropertyDecl, Constant, Variable, Routine,
    EnumMember);
  TAtlasOutlineSort = (Source, Alphabetical);
{$SCOPEDENUMS OFF}
  TAtlasOutlineVisibilities = set of TAtlasOutlineVisibility;
  TAtlasOutlineCategories = set of TAtlasOutlineCategory;

  TAtlasOutlineNode = record
    Name: string;
    /// <summary>Art des Typs („class“, „record“, „interface“); sonst leer.</summary>
    Detail: string;
    /// <summary>LSP SymbolKind.</summary>
    Kind: Integer;
    Category: TAtlasOutlineCategory;
    /// <summary>Ganze Deklaration, 0-basiert, Ende exklusiv.</summary>
    StartLine: Integer;
    StartCharacter: Integer;
    EndLine: Integer;
    EndCharacter: Integer;
    /// <summary>Anfang des Namens, 0-basiert.</summary>
    NameLine: Integer;
    NameCharacter: Integer;
    Visibility: TAtlasOutlineVisibility;
    ClassMember: Boolean;
    IsOverride: Boolean;
    IsVirtual: Boolean;
    IsAbstract: Boolean;
    /// <summary>Deklariert, aber nicht implementiert (#124).</summary>
    Unimplemented: Boolean;
    /// <summary>Index des Elternknotens, -1 auf oberster Ebene.</summary>
    Parent: Integer;
    Depth: Integer;
    /// <summary>Rumpf einer Deklaration: nicht in der Liste, Declaration zeigt auf sie.</summary>
    Hidden: Boolean;
    /// <summary>Bei verborgenen Rümpfen die Deklaration, sonst -1.</summary>
    Declaration: Integer;
    /// <summary>Bei Deklarationen der Rumpf, sonst -1.</summary>
    Body: Integer;
    /// <summary>Position im Rumpf einer Routine (Kinder verborgen).</summary>
    InBody: Boolean;
    /// <summary>Bedingung des aktiven {$IFDEF}-Zweigs (#845), bei Deklarationen auch die ihres Rumpfs;
    /// sonst leer.</summary>
    Condition: string;
  end;

  TAtlasOutlineNodes = TArray<TAtlasOutlineNode>;

  TAtlasOutlineRow = record
    Node: Integer;
    Depth: Integer;
    /// <summary>Erfüllt den Filter selbst; False bei Eltern, die nur als Rahmen stehen.</summary>
    Matched: Boolean;
  end;

  TAtlasOutlineFilter = record
    Text: string;
    Visibilities: TAtlasOutlineVisibilities;
    Categories: TAtlasOutlineCategories;
    /// <summary>Kein Filter: alle Sichtbarkeiten und Arten, kein Text.</summary>
    class function All: TAtlasOutlineFilter; static;
    function AllVisibilities: Boolean;
    function AllCategories: Boolean;
  end;

  TAtlasOutline = class
  public const
    /// <summary>Sichtbarkeiten, die der Filter anbietet (strict zählt zur einfachen).</summary>
    cFilterVisibilities: array[0..3] of TAtlasOutlineVisibility = (TAtlasOutlineVisibility.Private,
      TAtlasOutlineVisibility.Protected, TAtlasOutlineVisibility.Public, TAtlasOutlineVisibility.Published);
  public
    class function VisibilityOf(const AText: string): TAtlasOutlineVisibility; static;
    class function CategoryOf(AKind: Integer; AInType: Boolean): TAtlasOutlineCategory; static;
    /// <summary>Knoten aus der Antwort von documentSymbol; leer bei nil oder ohne Symbole.</summary>
    class function FromJson(const AResponse: TJSONValue): TAtlasOutlineNodes; static;
    /// <summary>Sichtbare Zeilen in Baumreihenfolge.</summary>
    class function Rows(const ANodes: TAtlasOutlineNodes; const AFilter: TAtlasOutlineFilter;
      ASort: TAtlasOutlineSort): TArray<TAtlasOutlineRow>; static;
    /// <summary>Innerster sichtbarer Knoten an der Stelle (0-basiert); im Rumpf einer Methode deren
    /// Deklaration; -1 außerhalb.</summary>
    class function NodeAt(const ANodes: TAtlasOutlineNodes; ALine, ACharacter: Integer): Integer; static;
    /// <summary>Zeichen vor dem Namen für die Sichtbarkeit (−, #, +, ◆); leer ohne.</summary>
    class function VisibilityMark(AVisibility: TAtlasOutlineVisibility): string; static;
    /// <summary>Abschnitt der Unit (interface, implementation) statt eines Elements?</summary>
    class function IsSection(const ANode: TAtlasOutlineNode): Boolean; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Core.Completion.Matching;

const
  cKindModule = 2;
  cKindNamespace = 3;
  cKindClass = 5;
  cKindMethod = 6;
  cKindProperty = 7;
  cKindField = 8;
  cKindConstructor = 9;
  cKindEnum = 10;
  cKindInterface = 11;
  cKindFunction = 12;
  cKindVariable = 13;
  cKindConstant = 14;
  cKindObject = 19;
  cKindEnumMember = 22;
  cKindStruct = 23;
  cKindTypeParameter = 26;

function IsRoutineKind(AKind: Integer): Boolean;
begin
  Result := (AKind = cKindMethod) or (AKind = cKindConstructor) or (AKind = cKindFunction);
end;

function IsTypeKind(AKind: Integer): Boolean;
begin
  Result := (AKind = cKindClass) or (AKind = cKindEnum) or (AKind = cKindInterface) or (AKind = cKindObject) or
    (AKind = cKindStruct) or (AKind = cKindTypeParameter);
end;

{ TAtlasOutlineFilter }

class function TAtlasOutlineFilter.All: TAtlasOutlineFilter;
begin
  Result.Text := '';
  Result.Visibilities := [Low(TAtlasOutlineVisibility)..High(TAtlasOutlineVisibility)];
  Result.Categories := [Low(TAtlasOutlineCategory)..High(TAtlasOutlineCategory)];
end;

function TAtlasOutlineFilter.AllVisibilities: Boolean;
var
  mVisibility: TAtlasOutlineVisibility;
begin
  for mVisibility in TAtlasOutline.cFilterVisibilities do
  begin
    if not (mVisibility in Visibilities) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

function TAtlasOutlineFilter.AllCategories: Boolean;
begin
  Result := Categories = [Low(TAtlasOutlineCategory)..High(TAtlasOutlineCategory)];
end;

{ TAtlasOutline }

class function TAtlasOutline.VisibilityOf(const AText: string): TAtlasOutlineVisibility;
var
  mText: string;
begin
  mText := LowerCase(Trim(AText));
  if mText = 'strict private' then
  begin
    Result := TAtlasOutlineVisibility.StrictPrivate;
  end
  else if mText = 'private' then
  begin
    Result := TAtlasOutlineVisibility.Private;
  end
  else if mText = 'strict protected' then
  begin
    Result := TAtlasOutlineVisibility.StrictProtected;
  end
  else if mText = 'protected' then
  begin
    Result := TAtlasOutlineVisibility.Protected;
  end
  else if (mText = 'public') or (mText = 'automated') then
  begin
    Result := TAtlasOutlineVisibility.Public;
  end
  else if mText = 'published' then
  begin
    Result := TAtlasOutlineVisibility.Published;
  end
  else
  begin
    Result := TAtlasOutlineVisibility.None;
  end;
end;

class function TAtlasOutline.CategoryOf(AKind: Integer; AInType: Boolean): TAtlasOutlineCategory;
begin
  case AKind of
    cKindModule, cKindNamespace:
      Result := TAtlasOutlineCategory.Section;
    cKindField:
      Result := TAtlasOutlineCategory.Field;
    cKindProperty:
      Result := TAtlasOutlineCategory.PropertyDecl;
    cKindConstant:
      Result := TAtlasOutlineCategory.Constant;
    cKindVariable:
      Result := TAtlasOutlineCategory.Variable;
    cKindEnumMember:
      Result := TAtlasOutlineCategory.EnumMember;
    cKindMethod, cKindConstructor, cKindFunction:
      if AInType then
      begin
        Result := TAtlasOutlineCategory.Method;
      end
      else
      begin
        Result := TAtlasOutlineCategory.Routine;
      end;
  else
    if IsTypeKind(AKind) then
    begin
      Result := TAtlasOutlineCategory.TypeDecl;
    end
    else
    begin
      Result := TAtlasOutlineCategory.Variable;
    end;
  end;
end;

class function TAtlasOutline.VisibilityMark(AVisibility: TAtlasOutlineVisibility): string;
begin
  case AVisibility of
    TAtlasOutlineVisibility.StrictPrivate, TAtlasOutlineVisibility.Private:
      Result := '−';
    TAtlasOutlineVisibility.StrictProtected, TAtlasOutlineVisibility.Protected:
      Result := '#';
    TAtlasOutlineVisibility.Public:
      Result := '+';
    TAtlasOutlineVisibility.Published:
      Result := '◆';
  else
    Result := '';
  end;
end;

class function TAtlasOutline.IsSection(const ANode: TAtlasOutlineNode): Boolean;
begin
  Result := (ANode.Kind = cKindNamespace) or (ANode.Category = TAtlasOutlineCategory.Section);
end;

type
  TOutlineReader = class
  private
    FNodes: TList<TAtlasOutlineNode>;
    procedure Add(const AItems: TJSONValue; AParent, ADepth: Integer; AInType: Boolean);
    function OwnerName(ANode: Integer): string;
    function IsInterfaceRoutine(ANode: Integer): Boolean;
    function IsBody(ANode: Integer): Boolean;
    function BodyOrdinal(AIndex: Integer): Integer;
    function Declares(AOther, AIndex: Integer; const AShort, AOwner: string): Boolean;
    procedure Connect(AIndex, AOther: Integer);
    procedure LinkBody(AIndex: Integer);
    procedure Link;
  public
    constructor Create;
    destructor Destroy; override;
    function Read(const AResponse: TJSONValue): TAtlasOutlineNodes;
  end;

constructor TOutlineReader.Create;
begin
  inherited Create;
  FNodes := TList<TAtlasOutlineNode>.Create;
end;

destructor TOutlineReader.Destroy;
begin
  FNodes.Free;
  inherited Destroy;
end;

/// <summary>Zusätze von Atlas (Sichtbarkeit, Klassenmitglied, Direktiven, Bedingung) aus AEntry.atlas.</summary>
procedure ReadExtras(const AEntry: TJSONObject; var ANode: TAtlasOutlineNode);
var
  mExtras: TJSONObject;
begin
  if not (AEntry.GetValue('atlas') is TJSONObject) then
  begin
    Exit;
  end;
  mExtras := TJSONObject(AEntry.GetValue('atlas'));
  ANode.Visibility := TAtlasOutline.VisibilityOf(mExtras.GetValue<string>('visibility', ''));
  ANode.ClassMember := mExtras.GetValue<Boolean>('classMember', False);
  ANode.IsOverride := mExtras.GetValue<Boolean>('override', False);
  ANode.IsVirtual := mExtras.GetValue<Boolean>('virtual', False);
  ANode.IsAbstract := mExtras.GetValue<Boolean>('abstract', False);
  ANode.Unimplemented := mExtras.GetValue<Boolean>('unimplemented', False);
  ANode.Condition := mExtras.GetValue<string>('condition', '');
end;

/// <summary>Eintrag AEntry als Knoten unter AParent in Tiefe ADepth (ohne InBody und Hidden).</summary>
function NodeOf(const AEntry: TJSONObject; AParent, ADepth: Integer; AInType: Boolean): TAtlasOutlineNode;
begin
  Result := Default(TAtlasOutlineNode);
  Result.Name := AEntry.GetValue<string>('name', '');
  Result.Detail := AEntry.GetValue<string>('detail', '');
  Result.Kind := AEntry.GetValue<Integer>('kind', 0);
  Result.Category := TAtlasOutline.CategoryOf(Result.Kind, AInType);
  Result.StartLine := AEntry.GetValue<Integer>('range.start.line', 0);
  Result.StartCharacter := AEntry.GetValue<Integer>('range.start.character', 0);
  Result.EndLine := AEntry.GetValue<Integer>('range.end.line', Result.StartLine);
  Result.EndCharacter := AEntry.GetValue<Integer>('range.end.character', Result.StartCharacter);
  Result.NameLine := AEntry.GetValue<Integer>('selectionRange.start.line', Result.StartLine);
  Result.NameCharacter := AEntry.GetValue<Integer>('selectionRange.start.character', Result.StartCharacter);
  Result.Parent := AParent;
  Result.Depth := ADepth;
  Result.Declaration := -1;
  Result.Body := -1;
  ReadExtras(AEntry, Result);
end;

procedure TOutlineReader.Add(const AItems: TJSONValue; AParent, ADepth: Integer; AInType: Boolean);
var
  mItem: TJSONValue;
  mEntry: TJSONObject;
  mNode: TAtlasOutlineNode;
  mIndex: Integer;
begin
  if not (AItems is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AItems) do
  begin
    if not (mItem is TJSONObject) then
    begin
      Continue;
    end;
    mEntry := TJSONObject(mItem);
    // Die Unit selbst ist kein Eintrag; ihre Kinder stehen oben.
    if (mEntry.GetValue<Integer>('kind', 0) = cKindModule) and (AParent < 0) then
    begin
      Add(mEntry.GetValue('children'), -1, 0, False);
      Continue;
    end;
    mNode := NodeOf(mEntry, AParent, ADepth, AInType);
    // Rümpfe mit Deklaration verbirgt Link; was in Rümpfen steht, ist immer verborgen.
    mNode.InBody := (AParent >= 0) and (FNodes[AParent].InBody or (IsRoutineKind(FNodes[AParent].Kind) and
      not AInType));
    mNode.Hidden := mNode.InBody;
    mIndex := FNodes.Add(mNode);
    // Lokale Routinen und Typen in Rümpfen: nur für NodeAt, nie in der Liste.
    Add(mEntry.GetValue('children'), mIndex, ADepth + 1, IsTypeKind(mNode.Kind) and (mNode.Kind <> cKindEnum));
  end;
end;

/// <summary>Name ohne Besitzer und Besitzer: "TFoo.Bar" → Bar, TFoo; nur der letzte Teil des Besitzers zählt.</summary>
procedure SplitName(const AName: string; out AShort, AOwner: string);
var
  mDot: Integer;
begin
  mDot := LastDelimiter('.', AName);
  AShort := Copy(AName, mDot + 1, MaxInt);
  AOwner := '';
  if mDot > 0 then
  begin
    AOwner := Copy(AName, 1, mDot - 1);
    mDot := LastDelimiter('.', AOwner);
    AOwner := Copy(AOwner, mDot + 1, MaxInt);
  end;
end;

function TOutlineReader.OwnerName(ANode: Integer): string;
begin
  Result := '';
  if (ANode >= 0) and (FNodes[ANode].Parent >= 0) and (FNodes[FNodes[ANode].Parent].Category =
    TAtlasOutlineCategory.TypeDecl) then
  begin
    Result := FNodes[FNodes[ANode].Parent].Name;
  end;
end;

function TOutlineReader.IsInterfaceRoutine(ANode: Integer): Boolean;
begin
  Result := (FNodes[ANode].Category = TAtlasOutlineCategory.Routine) and (FNodes[ANode].Parent >= 0) and
    (FNodes[FNodes[ANode].Parent].Kind = cKindNamespace) and SameText(FNodes[FNodes[ANode].Parent].Name, 'interface');
end;

/// <summary>Rumpf: Routine außerhalb von Typen und Rümpfen, die nicht im interface deklariert ist
/// (implementation-Abschnitt oder program).</summary>
function TOutlineReader.IsBody(ANode: Integer): Boolean;
begin
  Result := not FNodes[ANode].InBody and (FNodes[ANode].Category = TAtlasOutlineCategory.Routine) and
    not IsInterfaceRoutine(ANode);
end;

/// <summary>Wievielter Rumpf seines Namens AIndex ist (ab 0).</summary>
function TOutlineReader.BodyOrdinal(AIndex: Integer): Integer;
var
  mOther: Integer;
begin
  Result := 0;
  for mOther := 0 to AIndex - 1 do
  begin
    if IsBody(mOther) and SameText(FNodes[mOther].Name, FNodes[AIndex].Name) then
    begin
      Inc(Result);
    end;
  end;
end;

/// <summary>Ob AOther eine Deklaration ist, zu der der Rumpf AIndex (Name AShort, Besitzer AOwner) passen kann.
/// </summary>
function TOutlineReader.Declares(AOther, AIndex: Integer; const AShort, AOwner: string): Boolean;
begin
  Result := False;
  if (AOther = AIndex) or FNodes[AOther].Hidden or IsBody(AOther) or not IsRoutineKind(FNodes[AOther].Kind) or
    not SameText(FNodes[AOther].Name, AShort) then
  begin
    Exit;
  end;
  if AOwner <> '' then
  begin
    Result := SameText(OwnerName(AOther), AOwner);
  end
  else
  begin
    Result := IsInterfaceRoutine(AOther);
  end;
end;

/// <summary>Rumpf AIndex an Deklaration AOther binden.</summary>
procedure TOutlineReader.Connect(AIndex, AOther: Integer);
var
  mNode: TAtlasOutlineNode;
begin
  mNode := FNodes[AIndex];
  mNode.Hidden := True;
  mNode.Declaration := AOther;
  FNodes[AIndex] := mNode;
  mNode := FNodes[AOther];
  mNode.Body := AIndex;
  // Steht nur der Rumpf in einem Zweig (#845), zeigt die Deklaration dessen Bedingung.
  if mNode.Condition = '' then
  begin
    mNode.Condition := FNodes[AIndex].Condition;
  end;
  FNodes[AOther] := mNode;
end;

/// <summary>Rumpf AIndex der n-ten Deklaration gleichen Namens zuordnen (Überladungen in Reihenfolge).</summary>
procedure TOutlineReader.LinkBody(AIndex: Integer);
var
  mOther, mCount, mWanted: Integer;
  mShort, mOwner: string;
begin
  SplitName(FNodes[AIndex].Name, mShort, mOwner);
  mWanted := BodyOrdinal(AIndex);
  mCount := 0;
  for mOther := 0 to FNodes.Count - 1 do
  begin
    if not Declares(mOther, AIndex, mShort, mOwner) then
    begin
      Continue;
    end;
    if mCount = mWanted then
    begin
      Connect(AIndex, mOther);
      Exit;
    end;
    Inc(mCount);
  end;
end;

procedure TOutlineReader.Link;
var
  mIndex: Integer;
begin
  for mIndex := 0 to FNodes.Count - 1 do
  begin
    if IsBody(mIndex) then
    begin
      LinkBody(mIndex);
    end;
  end;
end;

function TOutlineReader.Read(const AResponse: TJSONValue): TAtlasOutlineNodes;
begin
  FNodes.Clear;
  Add(AResponse, -1, 0, False);
  Link;
  Result := FNodes.ToArray;
end;

class function TAtlasOutline.FromJson(const AResponse: TJSONValue): TAtlasOutlineNodes;
var
  mReader: TOutlineReader;
begin
  mReader := TOutlineReader.Create;
  try
    Result := mReader.Read(AResponse);
  finally
    mReader.Free;
  end;
end;

function SimpleVisibility(AVisibility: TAtlasOutlineVisibility): TAtlasOutlineVisibility;
begin
  case AVisibility of
    TAtlasOutlineVisibility.StrictPrivate:
      Result := TAtlasOutlineVisibility.Private;
    TAtlasOutlineVisibility.StrictProtected:
      Result := TAtlasOutlineVisibility.Protected;
  else
    Result := AVisibility;
  end;
end;

function Matches(const ANode: TAtlasOutlineNode; const AFilter: TAtlasOutlineFilter): Boolean;
begin
  Result := False;
  if ANode.Hidden or (ANode.Category = TAtlasOutlineCategory.Section) then
  begin
    Exit;
  end;
  if not (ANode.Category in AFilter.Categories) then
  begin
    Exit;
  end;
  // Mit Sichtbarkeitsfilter zählen nur Mitglieder von Typen.
  if not AFilter.AllVisibilities and not (SimpleVisibility(ANode.Visibility) in AFilter.Visibilities) then
  begin
    Exit;
  end;
  Result := (AFilter.Text = '') or (TAtlasCompletionMatcher.Score(AFilter.Text, ANode.Name) <>
    TAtlasCompletionMatcher.cNoMatch);
end;

/// <summary>Kinder jedes Knotens in AChildren, Knoten ohne Eltern in ARoots.</summary>
procedure LinkChildren(const ANodes: TAtlasOutlineNodes; const AChildren: TArray<TList<Integer>>;
  ARoots: TList<Integer>);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ANodes) do
  begin
    if ANodes[mIndex].Parent < 0 then
    begin
      ARoots.Add(mIndex);
    end
    else
    begin
      AChildren[ANodes[mIndex].Parent].Add(mIndex);
    end;
  end;
end;

/// <summary>Treffer in AHit, Treffer und ihre Eltern in AKeep; Abschnitte so nur mit Inhalt.</summary>
procedure MarkHits(const ANodes: TAtlasOutlineNodes; const AFilter: TAtlasOutlineFilter;
  const AKeep, AHit: TArray<Boolean>);
var
  mIndex, mParent: Integer;
begin
  for mIndex := 0 to High(ANodes) do
  begin
    if not Matches(ANodes[mIndex], AFilter) then
    begin
      Continue;
    end;
    AHit[mIndex] := True;
    mParent := mIndex;
    while (mParent >= 0) and not AKeep[mParent] do
    begin
      AKeep[mParent] := True;
      mParent := ANodes[mParent].Parent;
    end;
  end;
end;

class function TAtlasOutline.Rows(const ANodes: TAtlasOutlineNodes; const AFilter: TAtlasOutlineFilter;
  ASort: TAtlasOutlineSort): TArray<TAtlasOutlineRow>;
var
  mChildren: TArray<TList<Integer>>;
  mRoots: TList<Integer>;
  mKeep: TArray<Boolean>;
  mHit: TArray<Boolean>;
  mIndex: Integer;
  mOutput: TList<TAtlasOutlineRow>;
  mComparer: IComparer<Integer>;
  mNodes: TAtlasOutlineNodes;

  procedure Emit(AList: TList<Integer>; ADepth: Integer);
  var
    mOrdered: TArray<Integer>;
    mItem: Integer;
    mRow: TAtlasOutlineRow;
  begin
    mOrdered := AList.ToArray;
    // Abschnitte (interface, implementation) bleiben in ihrer Reihenfolge.
    if (ASort = TAtlasOutlineSort.Alphabetical) and (Length(mOrdered) > 1) and
      (ANodes[mOrdered[0]].Category <> TAtlasOutlineCategory.Section) then
    begin
      TArray.Sort<Integer>(mOrdered, mComparer);
    end;
    for mItem in mOrdered do
    begin
      if not mKeep[mItem] then
      begin
        Continue;
      end;
      mRow.Node := mItem;
      mRow.Depth := ADepth;
      mRow.Matched := mHit[mItem];
      mOutput.Add(mRow);
      Emit(mChildren[mItem], ADepth + 1);
    end;
  end;

var
  mChild: TList<Integer>;
begin
  Result := nil;
  mNodes := ANodes;
  SetLength(mChildren, Length(ANodes));
  SetLength(mKeep, Length(ANodes));
  SetLength(mHit, Length(ANodes));
  mRoots := TList<Integer>.Create;
  mOutput := TList<TAtlasOutlineRow>.Create;
  try
    for mIndex := 0 to High(ANodes) do
    begin
      mChildren[mIndex] := TList<Integer>.Create;
    end;
    LinkChildren(ANodes, mChildren, mRoots);
    MarkHits(ANodes, AFilter, mKeep, mHit);
    mComparer := TComparer<Integer>.Construct(
      function(const A, B: Integer): Integer
      begin
        Result := CompareText(mNodes[A].Name, mNodes[B].Name);
        if Result = 0 then
        begin
          Result := A - B;
        end;
      end);
    Emit(mRoots, 0);
    Result := mOutput.ToArray;
  finally
    for mChild in mChildren do
    begin
      mChild.Free;
    end;
    mRoots.Free;
    mOutput.Free;
  end;
end;

function Contains(const ANode: TAtlasOutlineNode; ALine, ACharacter: Integer): Boolean;
begin
  Result := ((ALine > ANode.StartLine) or ((ALine = ANode.StartLine) and (ACharacter >= ANode.StartCharacter))) and
    ((ALine < ANode.EndLine) or ((ALine = ANode.EndLine) and (ACharacter <= ANode.EndCharacter)));
end;

class function TAtlasOutline.NodeAt(const ANodes: TAtlasOutlineNodes; ALine, ACharacter: Integer): Integer;
var
  mIndex, mBest: Integer;
begin
  // Innerster Knoten: der späteste, der die Stelle enthält (Kinder stehen hinter ihren Eltern).
  mBest := -1;
  for mIndex := 0 to High(ANodes) do
  begin
    if (ANodes[mIndex].Category <> TAtlasOutlineCategory.Section) and Contains(ANodes[mIndex], ALine, ACharacter) then
    begin
      mBest := mIndex;
    end;
  end;
  // Lokale Routine oder Rumpf: zum äußersten Rumpf, von dort zur Deklaration.
  while (mBest >= 0) and ANodes[mBest].InBody do
  begin
    mBest := ANodes[mBest].Parent;
  end;
  if (mBest >= 0) and ANodes[mBest].Hidden then
  begin
    mBest := ANodes[mBest].Declaration;
  end;
  Result := mBest;
end;

end.
