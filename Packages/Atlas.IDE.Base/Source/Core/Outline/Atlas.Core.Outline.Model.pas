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
    FilterVisibilities: array[0..3] of TAtlasOutlineVisibility = (TAtlasOutlineVisibility.Private,
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
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Core.Completion.Matching;

const
  KindModule = 2;
  KindNamespace = 3;
  KindClass = 5;
  KindMethod = 6;
  KindProperty = 7;
  KindField = 8;
  KindConstructor = 9;
  KindEnum = 10;
  KindInterface = 11;
  KindFunction = 12;
  KindVariable = 13;
  KindConstant = 14;
  KindObject = 19;
  KindEnumMember = 22;
  KindStruct = 23;
  KindTypeParameter = 26;

function IsRoutineKind(AKind: Integer): Boolean;
begin
  Result := (AKind = KindMethod) or (AKind = KindConstructor) or (AKind = KindFunction);
end;

function IsTypeKind(AKind: Integer): Boolean;
begin
  Result := (AKind = KindClass) or (AKind = KindEnum) or (AKind = KindInterface) or (AKind = KindObject) or
    (AKind = KindStruct) or (AKind = KindTypeParameter);
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
  Visibility: TAtlasOutlineVisibility;
begin
  for Visibility in TAtlasOutline.FilterVisibilities do
    if not (Visibility in Visibilities) then
      Exit(False);
  Result := True;
end;

function TAtlasOutlineFilter.AllCategories: Boolean;
begin
  Result := Categories = [Low(TAtlasOutlineCategory)..High(TAtlasOutlineCategory)];
end;

{ TAtlasOutline }

class function TAtlasOutline.VisibilityOf(const AText: string): TAtlasOutlineVisibility;
var
  Text: string;
begin
  Text := LowerCase(Trim(AText));
  if Text = 'strict private' then
    Result := TAtlasOutlineVisibility.StrictPrivate
  else if Text = 'private' then
    Result := TAtlasOutlineVisibility.Private
  else if Text = 'strict protected' then
    Result := TAtlasOutlineVisibility.StrictProtected
  else if Text = 'protected' then
    Result := TAtlasOutlineVisibility.Protected
  else if (Text = 'public') or (Text = 'automated') then
    Result := TAtlasOutlineVisibility.Public
  else if Text = 'published' then
    Result := TAtlasOutlineVisibility.Published
  else
    Result := TAtlasOutlineVisibility.None;
end;

class function TAtlasOutline.CategoryOf(AKind: Integer; AInType: Boolean): TAtlasOutlineCategory;
begin
  case AKind of
    KindModule, KindNamespace:
      Result := TAtlasOutlineCategory.Section;
    KindField:
      Result := TAtlasOutlineCategory.Field;
    KindProperty:
      Result := TAtlasOutlineCategory.PropertyDecl;
    KindConstant:
      Result := TAtlasOutlineCategory.Constant;
    KindVariable:
      Result := TAtlasOutlineCategory.Variable;
    KindEnumMember:
      Result := TAtlasOutlineCategory.EnumMember;
    KindMethod, KindConstructor, KindFunction:
      if AInType then
        Result := TAtlasOutlineCategory.Method
      else
        Result := TAtlasOutlineCategory.Routine;
  else
    if IsTypeKind(AKind) then
      Result := TAtlasOutlineCategory.TypeDecl
    else
      Result := TAtlasOutlineCategory.Variable;
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

type
  TOutlineReader = class
  private
    FNodes: TList<TAtlasOutlineNode>;
    procedure Add(const AItems: TJSONValue; AParent, ADepth: Integer; AInType: Boolean);
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

procedure TOutlineReader.Add(const AItems: TJSONValue; AParent, ADepth: Integer; AInType: Boolean);
var
  Item: TJSONValue;
  Entry, Extras: TJSONObject;
  Node: TAtlasOutlineNode;
  Index: Integer;
begin
  if not (AItems is TJSONArray) then
    Exit;
  for Item in TJSONArray(AItems) do
  begin
    if not (Item is TJSONObject) then
      Continue;
    Entry := TJSONObject(Item);
    Node := Default(TAtlasOutlineNode);
    Node.Name := Entry.GetValue<string>('name', '');
    Node.Detail := Entry.GetValue<string>('detail', '');
    Node.Kind := Entry.GetValue<Integer>('kind', 0);
    // Die Unit selbst ist kein Eintrag; ihre Kinder stehen oben.
    if (Node.Kind = KindModule) and (AParent < 0) then
    begin
      Add(Entry.GetValue('children'), -1, 0, False);
      Continue;
    end;
    Node.Category := TAtlasOutline.CategoryOf(Node.Kind, AInType);
    Node.StartLine := Entry.GetValue<Integer>('range.start.line', 0);
    Node.StartCharacter := Entry.GetValue<Integer>('range.start.character', 0);
    Node.EndLine := Entry.GetValue<Integer>('range.end.line', Node.StartLine);
    Node.EndCharacter := Entry.GetValue<Integer>('range.end.character', Node.StartCharacter);
    Node.NameLine := Entry.GetValue<Integer>('selectionRange.start.line', Node.StartLine);
    Node.NameCharacter := Entry.GetValue<Integer>('selectionRange.start.character', Node.StartCharacter);
    Node.Parent := AParent;
    Node.Depth := ADepth;
    Node.Declaration := -1;
    Node.Body := -1;
    Extras := nil;
    if Entry.GetValue('atlas') is TJSONObject then
      Extras := TJSONObject(Entry.GetValue('atlas'));
    if Extras <> nil then
    begin
      Node.Visibility := TAtlasOutline.VisibilityOf(Extras.GetValue<string>('visibility', ''));
      Node.ClassMember := Extras.GetValue<Boolean>('classMember', False);
      Node.IsOverride := Extras.GetValue<Boolean>('override', False);
      Node.IsVirtual := Extras.GetValue<Boolean>('virtual', False);
      Node.IsAbstract := Extras.GetValue<Boolean>('abstract', False);
      Node.Unimplemented := Extras.GetValue<Boolean>('unimplemented', False);
      Node.Condition := Extras.GetValue<string>('condition', '');
    end;
    // Rümpfe mit Deklaration verbirgt Link; was in Rümpfen steht, ist immer verborgen.
    Node.InBody := (AParent >= 0) and (FNodes[AParent].InBody or (IsRoutineKind(FNodes[AParent].Kind) and
      not AInType));
    if Node.InBody then
      Node.Hidden := True;
    Index := FNodes.Add(Node);
    // Lokale Routinen und Typen in Rümpfen: nur für NodeAt, nie in der Liste.
    Add(Entry.GetValue('children'), Index, ADepth + 1, IsTypeKind(Node.Kind) and (Node.Kind <> KindEnum));
  end;
end;

/// <summary>Name ohne Besitzer und Besitzer: "TFoo.Bar" → Bar, TFoo; nur der letzte Teil des Besitzers zählt.</summary>
procedure SplitName(const AName: string; out AShort, AOwner: string);
var
  Dot: Integer;
begin
  Dot := LastDelimiter('.', AName);
  AShort := Copy(AName, Dot + 1, MaxInt);
  AOwner := '';
  if Dot > 0 then
  begin
    AOwner := Copy(AName, 1, Dot - 1);
    Dot := LastDelimiter('.', AOwner);
    AOwner := Copy(AOwner, Dot + 1, MaxInt);
  end;
end;

procedure TOutlineReader.Link;
var
  Index, Other, Count, Wanted: Integer;
  Short, Owner, Name: string;
  Node: TAtlasOutlineNode;

  function OwnerName(ANode: Integer): string;
  begin
    Result := '';
    if (ANode >= 0) and (FNodes[ANode].Parent >= 0) and (FNodes[FNodes[ANode].Parent].Category =
      TAtlasOutlineCategory.TypeDecl) then
      Result := FNodes[FNodes[ANode].Parent].Name;
  end;

  function IsInterfaceRoutine(ANode: Integer): Boolean;
  begin
    Result := (FNodes[ANode].Category = TAtlasOutlineCategory.Routine) and (FNodes[ANode].Parent >= 0) and
      (FNodes[FNodes[ANode].Parent].Kind = KindNamespace) and SameText(FNodes[FNodes[ANode].Parent].Name, 'interface');
  end;

  // Rumpf: Routine außerhalb von Typen und Rümpfen, die nicht im interface deklariert ist (implementation-
  // Abschnitt oder program).
  function IsBody(ANode: Integer): Boolean;
  begin
    Result := not FNodes[ANode].InBody and (FNodes[ANode].Category = TAtlasOutlineCategory.Routine) and
      not IsInterfaceRoutine(ANode);
  end;

begin
  // Jeden Rumpf der n-ten Deklaration gleichen Namens zuordnen (Überladungen in Reihenfolge).
  for Index := 0 to FNodes.Count - 1 do
  begin
    Node := FNodes[Index];
    if not IsBody(Index) then
      Continue;
    SplitName(Node.Name, Short, Owner);
    // Wievielter Rumpf dieses Namens?
    Wanted := 0;
    for Other := 0 to Index - 1 do
      if IsBody(Other) and SameText(FNodes[Other].Name, Node.Name) then
        Inc(Wanted);
    Count := 0;
    for Other := 0 to FNodes.Count - 1 do
    begin
      if (Other = Index) or FNodes[Other].Hidden or IsBody(Other) or
        not IsRoutineKind(FNodes[Other].Kind) then
        Continue;
      Name := FNodes[Other].Name;
      if Owner <> '' then
      begin
        if not SameText(Name, Short) or not SameText(OwnerName(Other), Owner) then
          Continue;
      end
      else if not IsInterfaceRoutine(Other) or not SameText(Name, Short) then
        Continue;
      if Count = Wanted then
      begin
        Node.Hidden := True;
        Node.Declaration := Other;
        FNodes[Index] := Node;
        Node := FNodes[Other];
        Node.Body := Index;
        // Steht nur der Rumpf in einem Zweig (#845), zeigt die Deklaration dessen Bedingung.
        if Node.Condition = '' then
          Node.Condition := FNodes[Index].Condition;
        FNodes[Other] := Node;
        Break;
      end;
      Inc(Count);
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
  Reader: TOutlineReader;
begin
  Reader := TOutlineReader.Create;
  try
    Result := Reader.Read(AResponse);
  finally
    Reader.Free;
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
    Exit;
  if not (ANode.Category in AFilter.Categories) then
    Exit;
  // Mit Sichtbarkeitsfilter zählen nur Mitglieder von Typen.
  if not AFilter.AllVisibilities and not (SimpleVisibility(ANode.Visibility) in AFilter.Visibilities) then
    Exit;
  Result := (AFilter.Text = '') or (TAtlasCompletionMatcher.Score(AFilter.Text, ANode.Name) <>
    TAtlasCompletionMatcher.NoMatch);
end;

class function TAtlasOutline.Rows(const ANodes: TAtlasOutlineNodes; const AFilter: TAtlasOutlineFilter;
  ASort: TAtlasOutlineSort): TArray<TAtlasOutlineRow>;
var
  Children: TArray<TList<Integer>>;
  Roots: TList<Integer>;
  Keep: TArray<Boolean>;
  Hit: TArray<Boolean>;
  Index, Parent: Integer;
  Output: TList<TAtlasOutlineRow>;
  Comparer: IComparer<Integer>;
  Nodes: TAtlasOutlineNodes;

  procedure Emit(AList: TList<Integer>; ADepth: Integer);
  var
    Ordered: TArray<Integer>;
    Item: Integer;
    Row: TAtlasOutlineRow;
  begin
    Ordered := AList.ToArray;
    // Abschnitte (interface, implementation) bleiben in ihrer Reihenfolge.
    if (ASort = TAtlasOutlineSort.Alphabetical) and (Length(Ordered) > 1) and
      (ANodes[Ordered[0]].Category <> TAtlasOutlineCategory.Section) then
      TArray.Sort<Integer>(Ordered, Comparer);
    for Item in Ordered do
    begin
      if not Keep[Item] then
        Continue;
      Row.Node := Item;
      Row.Depth := ADepth;
      Row.Matched := Hit[Item];
      Output.Add(Row);
      Emit(Children[Item], ADepth + 1);
    end;
  end;

var
  Child: TList<Integer>;
begin
  Result := nil;
  Nodes := ANodes;
  SetLength(Children, Length(ANodes));
  SetLength(Keep, Length(ANodes));
  SetLength(Hit, Length(ANodes));
  Roots := TList<Integer>.Create;
  Output := TList<TAtlasOutlineRow>.Create;
  try
    for Index := 0 to High(ANodes) do
      Children[Index] := TList<Integer>.Create;
    for Index := 0 to High(ANodes) do
      if ANodes[Index].Parent < 0 then
        Roots.Add(Index)
      else
        Children[ANodes[Index].Parent].Add(Index);
    // Treffer und ihre Eltern behalten; Abschnitte nur mit Inhalt.
    for Index := 0 to High(ANodes) do
      if Matches(ANodes[Index], AFilter) then
      begin
        Hit[Index] := True;
        Parent := Index;
        while (Parent >= 0) and not Keep[Parent] do
        begin
          Keep[Parent] := True;
          Parent := ANodes[Parent].Parent;
        end;
      end;
    Comparer := TComparer<Integer>.Construct(
      function(const A, B: Integer): Integer
      begin
        Result := CompareText(Nodes[A].Name, Nodes[B].Name);
        if Result = 0 then
          Result := A - B;
      end);
    Emit(Roots, 0);
    Result := Output.ToArray;
  finally
    for Child in Children do
      Child.Free;
    Roots.Free;
    Output.Free;
  end;
end;

function Contains(const ANode: TAtlasOutlineNode; ALine, ACharacter: Integer): Boolean;
begin
  Result := ((ALine > ANode.StartLine) or ((ALine = ANode.StartLine) and (ACharacter >= ANode.StartCharacter))) and
    ((ALine < ANode.EndLine) or ((ALine = ANode.EndLine) and (ACharacter <= ANode.EndCharacter)));
end;

class function TAtlasOutline.NodeAt(const ANodes: TAtlasOutlineNodes; ALine, ACharacter: Integer): Integer;
var
  Index, Best: Integer;
begin
  // Innerster Knoten: der späteste, der die Stelle enthält (Kinder stehen hinter ihren Eltern).
  Best := -1;
  for Index := 0 to High(ANodes) do
    if (ANodes[Index].Category <> TAtlasOutlineCategory.Section) and Contains(ANodes[Index], ALine, ACharacter) then
      Best := Index;
  // Lokale Routine oder Rumpf: zum äußersten Rumpf, von dort zur Deklaration.
  while (Best >= 0) and ANodes[Best].InBody do
    Best := ANodes[Best].Parent;
  if (Best >= 0) and ANodes[Best].Hidden then
    Best := ANodes[Best].Declaration;
  Result := Best;
end;

end.
