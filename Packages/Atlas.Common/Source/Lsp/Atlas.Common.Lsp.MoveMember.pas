unit Atlas.Common.Lsp.MoveMember;

// „Mitglied in Vorfahr oder Nachfahr verschieben“ über das Protokoll (#675):
//   - Code-Aktionen „„Run“ in Vorfahr verschieben …“ (der Vorfahr liegt im
//     Projekt, nicht in RTL/VCL) und „„Run“ in Nachfahren verschieben …“ (es
//     gibt direkte Nachfahren im Projekt) auf einem Feld, einer Methode oder
//     einer Property der Klassendeklaration, nur mit refactoring.moveMember.
//     Sie tragen den Client-Befehl atlas.moveMember mit [uri, position,
//     "up"|"down"].
//   - atlas.server.moveMember.prepare [uri, position, richtung]: Klasse,
//     Mitglied, Kandidaten (das Mitglied an der Stelle angehakt), Ziele
//     (nach oben die Vorfahren des Projekts, der direkte vorgewählt; nach
//     unten die direkten Nachfahren, alle vorgewählt) und die Wahl „andere
//     Nachfahren überschreiben“ bzw. „abstrakte Deklaration im Vorfahr
//     lassen“.
//   - atlas.server.moveMember [uri, position, richtung, {members, abstract,
//     targets, option}]: WorkspaceEdit mit Änderungsanmerkung über alle
//     betroffenen Dateien. Nach unten sucht es vorher die Verweise auf die
//     Mitglieder (#29): Stellen außerhalb der Klasse und der gewählten
//     Nachfahren verbieten das Verschieben. Liegt das Ziel in einer anderen
//     Unit, ergänzt es dort die uses für die benutzten Namen (interface für
//     Deklarationen, implementation für Rümpfe); Kreisverweise und Namen, die
//     nur im implementation-Teil der Quelle stehen, brechen ab.
// Die Logik liegt in Atlas.Common.Editing.MoveMember.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.References;

type
  TMoveMemberContext = record
    Index: ISymbolIndex;
    ReadText: TReferenceReadText;
    /// <summary>Dateien des Projekts für die Referenzsuche.</summary>
    Files: TArray<string>;
    /// <summary>"up" oder "down".</summary>
    Direction: string;
    /// <summary>Beim Ausführen: {members, abstract, targets, option}; gehört dem Aufrufer.</summary>
    Request: TJSONValue;
  end;

  TLspMoveMember = class
  public const
    ClientCommand = 'atlas.moveMember';
    PrepareCommand = 'atlas.server.moveMember.prepare';
    ApplyCommand = 'atlas.server.moveMember';
    AnnotationId = 'moveMember';
  public
    /// <summary>Die Code-Aktionen an APosition, wenn es dort ein Ziel gibt; sonst nil. Ob die Funktion
    /// eingeschaltet ist, prüft der Aufrufer. Der Aufrufer übernimmt die Objekte.</summary>
    class function Actions(ATree: TSyntaxTree; const AText, AFileName, AUri: string;
      const APosition: TTextPosition; const AIndex: ISymbolIndex): TArray<TJSONObject>; static;
    /// <summary>Antwort auf prepare; EJsonRpcError ohne Mitglied oder Ziel. Der Aufrufer übernimmt das Objekt.
    /// </summary>
    class function Prepare(ATree: TSyntaxTree; const AText, AFileName: string; const APosition: TTextPosition;
      const AContext: TMoveMemberContext): TJSONObject; static;
    /// <summary>{"edit": WorkspaceEdit, "warnings": [...], "file": URI des (ersten) Ziels, "line": Kopfzeile der
    /// Zielklasse dort, "moved": Zahl};
    /// EJsonRpcError bei ungültiger Anfrage. Der Aufrufer übernimmt das Objekt.</summary>
    class function Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const APosition: TTextPosition; const AContext: TMoveMemberContext): TJSONObject; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.ClassLayout,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Editing.MemberTransfer,
  Atlas.Common.Editing.MoveMember,
  Atlas.Common.Editing.MoveClass,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.MoveClass,
  Atlas.Common.Lsp.WorkspaceChanges;

type
  /// <summary>Klasse des Projekts mit Unit und Vorfahr.</summary>
  TClassHit = record
    Ref: TMemberClassRef;
    UnitName: string;
    Ancestor: string;
  end;

const
  /// <summary>Höchstens so viele Vorfahren nach oben.</summary>
  MaxDepth = 16;

function Failed(const AMessage: string): EJsonRpcError;
begin
  Result := EJsonRpcError.Create(TLspErrorCode.RequestFailed, 'Mitglied verschieben: ' + AMessage);
end;

function PlainName(const AName: string): string;
begin
  Result := Trim(AName);
  if Pos('<', Result) > 0 then
  begin
    Result := Trim(Copy(Result, 1, Pos('<', Result) - 1));
  end;
end;

function IsUp(const ADirection: string): Boolean;
begin
  if SameText(ADirection, 'up') then
  begin
    Result := True;
  end
  else if SameText(ADirection, 'down') then
  begin
    Result := False;
  end
  else
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Richtung "up" oder "down" fehlt');
  end;
end;

/// <summary>Liegt die Datei in einer Bibliothek (RTL/VCL, Suchpfade)?</summary>
function IsLibrary(const AIndex: ISymbolIndex; const AFileName: string): Boolean;
var
  UnitIndex: TUnitIndex;
begin
  Result := not AIndex.FindFile(AFileName, UnitIndex) or UnitIndex.Library_;
end;

/// <summary>Klasse AName in ATree (Datei AFileName).</summary>
function DeclHit(ATree: TSyntaxTree; const AText, AFileName, AName: string; out AHit: TClassHit): Boolean;
var
  Decl: TSyntaxNode;
  Layout: TClassLayout;
begin
  Decl := TClassLayout.DeclNamed(ATree, AName);
  Result := Decl <> nil;
  if not Result then
  begin
    Exit;
  end;
  Layout := TClassLayout.Read(ATree, AText, Decl);
  try
    AHit.Ref := TMemberClassRef.Create(AFileName, Layout.Name);
    AHit.UnitName := TUsesClauses.OwnName(ATree.Tokens);
    if Layout.Ancestors <> nil then
    begin
      AHit.Ancestor := Layout.Ancestors[0];
    end;
  finally
    Layout.Free;
  end;
end;

/// <summary>Klasse AName des Projekts im Index, nicht in AFileName.</summary>
function IndexHit(const AIndex: ISymbolIndex; const AFileName, AName: string; out AHit: TClassHit): Boolean;
var
  Location: TSymbolLocation;
begin
  for Location in AIndex.FindSymbols(AName) do
  begin
    if (Location.Symbol.Kind = TIndexSymbolKind.ClassType) and (Location.Symbol.Container = '') and
      not SameText(Location.FileName, AFileName) and not IsLibrary(AIndex, Location.FileName) then
    begin
      AHit.Ref := TMemberClassRef.Create(Location.FileName, Location.Symbol.Name);
      AHit.UnitName := Location.UnitName;
      if Location.Symbol.Ancestors <> nil then
      begin
        AHit.Ancestor := Location.Symbol.Ancestors[0];
      end;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Klasse AName des Projekts: in ATree (Datei AFileName) oder im Index.</summary>
function FindClass(ATree: TSyntaxTree; const AText, AFileName: string; const AIndex: ISymbolIndex;
  const AName: string; out AHit: TClassHit): Boolean;
var
  Name: string;
begin
  AHit := Default(TClassHit);
  Name := PlainName(AName);
  Result := (Name <> '') and not SameText(Name, 'TObject') and (DeclHit(ATree, AText, AFileName, Name, AHit) or
    ((AIndex <> nil) and IndexHit(AIndex, AFileName, Name, AHit)));
end;

/// <summary>Vorfahren des Projekts ab AAncestor, der direkte zuerst.</summary>
function AncestorChain(ATree: TSyntaxTree; const AText, AFileName: string; const AIndex: ISymbolIndex;
  const AAncestor: string): TArray<TClassHit>;
var
  Hit: TClassHit;
  Name: string;
begin
  Result := nil;
  Name := AAncestor;
  while (Length(Result) < MaxDepth) and FindClass(ATree, AText, AFileName, AIndex, Name, Hit) do
  begin
    Result := Result + [Hit];
    Name := Hit.Ancestor;
  end;
end;

/// <summary>Direkte Nachfahren von AClassName im Projekt: in ATree und im Index.</summary>
function DirectDescendants(ATree: TSyntaxTree; const AText, AFileName: string; const AIndex: ISymbolIndex;
  const AClassName: string): TArray<TClassHit>;
var
  Decl: TSyntaxNode;
  Layout: TClassLayout;
  Location: TSymbolLocation;
  Hit: TClassHit;
begin
  Result := nil;
  for Decl in TClassLayout.AllDecls(ATree) do
  begin
    Layout := TClassLayout.Read(ATree, AText, Decl);
    try
      if (Layout.Ancestors <> nil) and SameText(PlainName(Layout.Ancestors[0]), AClassName) then
      begin
        Hit := Default(TClassHit);
        Hit.Ref := TMemberClassRef.Create(AFileName, Layout.Name);
        Hit.UnitName := TUsesClauses.OwnName(ATree.Tokens);
        Hit.Ancestor := Layout.Ancestors[0];
        Result := Result + [Hit];
      end;
    finally
      Layout.Free;
    end;
  end;
  if AIndex = nil then
  begin
    Exit;
  end;
  for Location in AIndex.Descendants(AClassName) do
  begin
    if (Location.Symbol.Kind = TIndexSymbolKind.ClassType) and not SameText(Location.FileName, AFileName) and
      not IsLibrary(AIndex, Location.FileName) and (Location.Symbol.Ancestors <> nil) and
      SameText(PlainName(Location.Symbol.Ancestors[0]), AClassName) then
    begin
      Hit := Default(TClassHit);
      Hit.Ref := TMemberClassRef.Create(Location.FileName, Location.Symbol.Name);
      Hit.UnitName := Location.UnitName;
      Hit.Ancestor := Location.Symbol.Ancestors[0];
      Result := Result + [Hit];
    end;
  end;
end;

function KindText(AKind: TTransferKind): string;
begin
  case AKind of
    TTransferKind.Field:
      Result := 'field';
    TTransferKind.Property_:
      Result := 'property';
  else
    Result := 'method';
  end;
end;

function Info(ATree: TSyntaxTree; const AText: string; const APosition: TTextPosition): TMoveMemberInfo;
var
  Reason: string;
begin
  if not TMoveMember.Prepare(ATree, AText, APosition.Line, Result, Reason) then
  begin
    raise Failed(Reason);
  end;
end;

function Action(const ATitle, AUri: string; const APosition: TTextPosition; const ADirection: string): TJSONObject;
var
  Arguments: TJSONArray;
  Command: TJSONObject;
begin
  Arguments := TJSONArray.Create;
  Arguments.Add(AUri);
  Arguments.AddElement(TLspPositions.PositionToJson(APosition));
  Arguments.Add(ADirection);
  Command := TJSONObject.Create;
  Command.AddPair('title', ATitle);
  Command.AddPair('command', TLspMoveMember.ClientCommand);
  Command.AddPair('arguments', Arguments);
  Result := TJSONObject.Create;
  Result.AddPair('title', ATitle);
  Result.AddPair('kind', TMoveMember.Kind);
  Result.AddPair('command', Command);
end;

class function TLspMoveMember.Actions(ATree: TSyntaxTree; const AText, AFileName, AUri: string;
  const APosition: TTextPosition; const AIndex: ISymbolIndex): TArray<TJSONObject>;
var
  Found: TMoveMemberInfo;
  Reason: string;
  Hit: TClassHit;
begin
  Result := nil;
  if (ATree = nil) or not TMoveMember.Prepare(ATree, AText, APosition.Line, Found, Reason) then
  begin
    Exit;
  end;
  if FindClass(ATree, AText, AFileName, AIndex, Found.Ancestor, Hit) then
  begin
    Result := Result + [Action(Format('„%s“ in Vorfahr verschieben …', [Found.SelectedName]), AUri, APosition,
      'up')];
  end;
  if DirectDescendants(ATree, AText, AFileName, AIndex, Found.ClassName) <> nil then
  begin
    Result := Result + [Action(Format('„%s“ in Nachfahren verschieben …', [Found.SelectedName]), AUri, APosition,
      'down')];
  end;
end;

/// <summary>Ziele nach oben (Vorfahren) bzw. unten (direkte Nachfahren) der Klasse AFound.</summary>
function TargetHits(ATree: TSyntaxTree; const AText, AFileName: string; const AIndex: ISymbolIndex;
  const AFound: TMoveMemberInfo; AUp: Boolean): TArray<TClassHit>;
begin
  if AUp then
  begin
    Result := AncestorChain(ATree, AText, AFileName, AIndex, AFound.Ancestor);
  end
  else
  begin
    Result := DirectDescendants(ATree, AText, AFileName, AIndex, AFound.ClassName);
  end;
end;

function CandidateJson(const AItem: TTransferCandidate; ASelected: Integer; AUp: Boolean): TJSONObject;
var
  Needs: TJSONArray;
  Need: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', TJSONNumber.Create(AItem.Id));
  Result.AddPair('name', AItem.Name);
  Result.AddPair('kind', KindText(AItem.Kind));
  Result.AddPair('display', AItem.Display);
  Result.AddPair('visibility', TClassEdits.VisibilityName(AItem.Visibility));
  Result.AddPair('checked', TJSONBool.Create(AItem.Id = ASelected));
  Result.AddPair('enabled', TJSONBool.Create(AItem.Enabled));
  Result.AddPair('reason', AItem.Reason);
  // Abstrakt wählen gibt es nur nach oben; nach unten gilt die Wahl für alle Methoden.
  Result.AddPair('canAbstract', TJSONBool.Create(AUp and AItem.CanAbstract));
  Result.AddPair('abstract', TJSONBool.Create(False));
  Needs := TJSONArray.Create;
  for Need in AItem.Needs do
  begin
    Needs.AddElement(TJSONNumber.Create(Need));
  end;
  Result.AddPair('needs', Needs);
end;

function TargetsJson(const AHits: TArray<TClassHit>; AUp: Boolean): TJSONArray;
var
  Hit: TClassHit;
  Entry: TJSONObject;
begin
  Result := TJSONArray.Create;
  for Hit in AHits do
  begin
    Entry := TJSONObject.Create;
    Entry.AddPair('name', Hit.Ref.ClassName);
    Entry.AddPair('unit', Hit.UnitName);
    Entry.AddPair('checked', TJSONBool.Create(not AUp or (Result.Count = 0)));
    Result.AddElement(Entry);
  end;
end;

function OptionJson(AUp: Boolean): TJSONObject;
begin
  Result := TJSONObject.Create;
  if AUp then
  begin
    Result.AddPair('kind', 'overrideSiblings');
  end
  else
  begin
    Result.AddPair('kind', 'keepAbstract');
  end;
  Result.AddPair('value', TJSONBool.Create(AUp));
end;

class function TLspMoveMember.Prepare(ATree: TSyntaxTree; const AText, AFileName: string;
  const APosition: TTextPosition; const AContext: TMoveMemberContext): TJSONObject;
var
  Found: TMoveMemberInfo;
  Up: Boolean;
  Hits: TArray<TClassHit>;
  Item: TTransferCandidate;
  List: TJSONArray;
begin
  Up := IsUp(AContext.Direction);
  Found := Info(ATree, AText, APosition);
  Hits := TargetHits(ATree, AText, AFileName, AContext.Index, Found, Up);
  if (Hits = nil) and Up then
  begin
    raise Failed(Format('%s hat keinen Vorfahren im Projekt.', [Found.ClassName]));
  end;
  if Hits = nil then
  begin
    raise Failed(Format('%s hat keine Nachfahren im Projekt.', [Found.ClassName]));
  end;
  Result := TJSONObject.Create;
  Result.AddPair('className', Found.ClassName);
  Result.AddPair('ownUnit', TUsesClauses.OwnName(ATree.Tokens));
  Result.AddPair('member', Found.SelectedName);
  Result.AddPair('direction', LowerCase(AContext.Direction));
  Result.AddPair('name', '');
  List := TJSONArray.Create;
  for Item in Found.Candidates do
  begin
    List.AddElement(CandidateJson(Item, Found.Selected, Up));
  end;
  Result.AddPair('candidates', List);
  Result.AddPair('targets', TargetsJson(Hits, Up));
  Result.AddPair('multiTarget', TJSONBool.Create(not Up));
  // Nach unten bleiben benutzte Mitglieder oben (sie werden bei Bedarf sichtbar gemacht).
  Result.AddPair('needsRequired', TJSONBool.Create(Up));
  Result.AddPair('option', OptionJson(Up));
  Result.AddPair('notes', TJSONArray.Create);
end;

function Ids(AObject: TJSONObject; const AKey: string): TArray<Integer>;
var
  Value, Item: TJSONValue;
begin
  Result := nil;
  Value := AObject.GetValue(AKey);
  if Value is TJSONArray then
  begin
    for Item in TJSONArray(Value) do
    begin
      if Item is TJSONNumber then
      begin
        Result := Result + [TJSONNumber(Item).AsInt];
      end;
    end;
  end;
end;

function Names(AObject: TJSONObject; const AKey: string): TArray<string>;
var
  Value, Item: TJSONValue;
begin
  Result := nil;
  Value := AObject.GetValue(AKey);
  if Value is TJSONArray then
  begin
    for Item in TJSONArray(Value) do
    begin
      Result := Result + [Trim(Item.Value)];
    end;
  end;
end;

/// <summary>Text der Datei; EJsonRpcError, wenn sie nicht lesbar ist.</summary>
function ReadFile(const AContext: TMoveMemberContext; const AFileName: string): string;
begin
  if not (Assigned(AContext.ReadText) and AContext.ReadText(AFileName, Result)) then
  begin
    raise Failed(Format('%s lässt sich nicht lesen.', [ExtractFileName(AFileName)]));
  end;
end;

type
  TLineRange = record
    FileName: string;
    First: Integer;
    Last: Integer;
  end;

/// <summary>Zeilen der Klasse und ihrer Rümpfe.</summary>
function ClassRanges(ALayout: TClassLayout; const AFileName: string): TArray<TLineRange>;
var
  Member: TClassMember;
  Range: TLineRange;
begin
  Range.FileName := AFileName;
  Range.First := ALayout.FirstLine;
  Range.Last := ALayout.EndLine;
  Result := [Range];
  for Member in ALayout.Members do
  begin
    if Member.Body <> nil then
    begin
      Range.First := Member.BodyFirstLine;
      Range.Last := Member.BodyLastLine;
      Result := Result + [Range];
    end;
  end;
end;

function InRanges(const ARanges: TArray<TLineRange>; const AFileName: string; ALine: Integer): Boolean;
var
  Range: TLineRange;
begin
  for Range in ARanges do
  begin
    if SameText(Range.FileName, AFileName) and (ALine >= Range.First) and (ALine <= Range.Last) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Position des Namens AName im Knoten ANode.</summary>
function NamePosition(ATree: TSyntaxTree; ANode: TSyntaxNode; const AName: string): TTextPosition;
var
  mIndex: Integer;
begin
  // Binär zum ersten Token des Knotens statt ab Dateianfang (#1323).
  mIndex := ATree.FirstTokenFrom(ANode.StartOffset);
  while (mIndex <= High(ATree.Tokens)) and (ATree.Tokens[mIndex].Offset < ANode.EndOffset) do
  begin
    if (ATree.Tokens[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(ATree.Tokens[mIndex].Text, AName) then
    begin
      Exit(ATree.Tokens[mIndex].StartPos);
    end;
    Inc(mIndex);
  end;
  Result := ANode.StartPos;
end;

/// <summary>Namen, die ANode benutzt, mit ihrer Stelle (Bezeichner und Typverweise).</summary>
procedure CollectNames(ANode: TSyntaxNode; var ANames: TArray<TArray<string>>; var AOffsets: TArray<Integer>);
var
  Index: Integer;
  Name: string;
begin
  if ANode = nil then
  begin
    Exit;
  end;
  if (ANode.Kind = TSyntaxKind.Identifier) and ((ANode.Parent = nil) or
    (ANode.Parent.Kind <> TSyntaxKind.GenericParams)) then
  begin
    Name := ANode.Name;
    if Name.StartsWith('&') then
    begin
      Name := Name.Substring(1);
    end;
    ANames := ANames + [TArray<string>.Create(Name)];
    AOffsets := AOffsets + [ANode.StartOffset];
  end
  else if (ANode.Kind = TSyntaxKind.TypeReference) and (ANode.Name <> '') then
  begin
    ANames := ANames + [ANode.Name.Split(['.'])];
    AOffsets := AOffsets + [ANode.StartOffset];
  end;
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    CollectNames(ANode[Index], ANames, AOffsets);
  end;
end;

function SectionLine(ATree: TSyntaxTree; AKind: TSyntaxKind): Integer;
var
  Index: Integer;
begin
  for Index := 0 to ATree.Root.ChildCount - 1 do
  begin
    if ATree.Root[Index].Kind = AKind then
    begin
      Exit(ATree.Root[Index].StartPos.Line);
    end;
  end;
  Result := -1;
end;

function SectionOffset(ATree: TSyntaxTree; AKind: TSyntaxKind): Integer;
var
  Index: Integer;
begin
  for Index := 0 to ATree.Root.ChildCount - 1 do
  begin
    if ATree.Root[Index].Kind = AKind then
    begin
      Exit(ATree.Root[Index].StartOffset + 1);
    end;
  end;
  Result := -1;
end;

procedure AddOnce(var AList: TArray<string>; const AName: string);
begin
  if IndexText(AName, AList) < 0 then
  begin
    AList := AList + [AName];
  end;
end;

type
  /// <summary>Units, die die Ziel-Unit für die Namen der verschobenen Mitglieder braucht.</summary>
  TUsesScan = class
  private
    FResolver: TNameResolver;
    FTree: TSyntaxTree;
    FFileName: string;
    FUp: Boolean;
    FLookup: TMoveClassLookup;
    FSourceUnit: string;
    FTargetUnit: string;
    FRanges: TArray<TLineRange>;
    FImplementationLine: Integer;
    FInInterface: Boolean;
    /// <summary>Ein Name aus der Quelle selbst: im implementation-Teil unsichtbar, nach oben ein Kreisverweis im
    /// interface.</summary>
    procedure NoteSourceUnit(const ADisplay: string; ALine: Integer; ADeclaration: Boolean);
    procedure Note(const ANames: TArray<string>; AOffset: Integer; ADeclaration: Boolean);
    procedure NoteNode(ANode: TSyntaxNode; ADeclaration: Boolean);
  public
    InterfaceUnits: TArray<string>;
    ImplementationUnits: TArray<string>;
    /// <summary>AUp: Die Ziel-Unit ist Vorfahr (darf die Quelle nicht im interface einbinden).</summary>
    constructor Create(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string; AUp: Boolean);
    /// <summary>Namen der Deklarationen der Mitglieder AIds und der Rümpfe von ABodyIds aus ASource für die
    /// Zielklasse ATarget in der Unit ATargetUnit.</summary>
    procedure Scan(ASource, ATarget: TClassLayout; const ATargetUnit: string; const AIds, ABodyIds: TArray<Integer>);
  end;

constructor TUsesScan.Create(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string; AUp: Boolean);
begin
  inherited Create;
  FResolver := AResolver;
  FTree := ATree;
  FFileName := AFileName;
  FUp := AUp;
  FLookup := TLspMoveClass.Lookup(AResolver);
  FSourceUnit := TUsesClauses.OwnName(ATree.Tokens);
  FImplementationLine := SectionLine(ATree, TSyntaxKind.ImplementationSection);
end;

procedure TUsesScan.NoteSourceUnit(const ADisplay: string; ALine: Integer; ADeclaration: Boolean);
begin
  if (FImplementationLine >= 0) and (ALine > FImplementationLine) then
  begin
    raise Failed(Format('%s steht nur im implementation-Teil von %s und ist in %s nicht sichtbar.',
      [ADisplay, FSourceUnit, FTargetUnit]));
  end;
  // Nachfahren binden die Quelle ohnehin ein.
  if not FUp then
  begin
    Exit;
  end;
  if ADeclaration and FInInterface then
  begin
    raise Failed(Format('%s stammt aus %s, die %s im interface einbinden müsste (Kreisverweis).',
      [ADisplay, FSourceUnit, FTargetUnit]));
  end;
  AddOnce(ImplementationUnits, FSourceUnit);
end;

procedure TUsesScan.Note(const ANames: TArray<string>; AOffset: Integer; ADeclaration: Boolean);
var
  Meaning: TMoveClassMeaning;
begin
  Meaning := FLookup(FTree, FFileName, ANames, AOffset);
  if not Meaning.Found or Meaning.IsLocal or (Meaning.UnitName = '') or SameText(Meaning.UnitName, 'System') or
    SameText(Meaning.UnitName, FTargetUnit) then
  begin
    Exit;
  end;
  // Mitglieder der Klasse selbst (sie wandern mit oder sind geerbt).
  if SameText(Meaning.FileName, FFileName) and InRanges(FRanges, FFileName, Meaning.Position.Line) then
  begin
    Exit;
  end;
  if SameText(Meaning.UnitName, FSourceUnit) then
  begin
    NoteSourceUnit(string.Join('.', ANames), Meaning.Position.Line, ADeclaration);
  end
  else if ADeclaration and FInInterface then
  begin
    AddOnce(InterfaceUnits, Meaning.UnitName);
  end
  else
  begin
    AddOnce(ImplementationUnits, Meaning.UnitName);
  end;
end;

procedure TUsesScan.NoteNode(ANode: TSyntaxNode; ADeclaration: Boolean);
var
  NameList: TArray<TArray<string>>;
  Offsets: TArray<Integer>;
  Index: Integer;
begin
  NameList := nil;
  Offsets := nil;
  CollectNames(ANode, NameList, Offsets);
  for Index := 0 to High(NameList) do
  begin
    Note(NameList[Index], Offsets[Index], ADeclaration);
  end;
end;

procedure TUsesScan.Scan(ASource, ATarget: TClassLayout; const ATargetUnit: string;
  const AIds, ABodyIds: TArray<Integer>);
var
  Id: Integer;
begin
  FTargetUnit := ATargetUnit;
  FInInterface := ATarget.InInterface;
  FRanges := ClassRanges(ASource, FFileName);
  FResolver.PinTree(FTree, FFileName);
  try
    for Id in AIds do
    begin
      // Erst die Deklaration, dann der Rumpf.
      NoteNode(ASource.Members[Id].Node, True);
      if TMemberTransfer.Has(ABodyIds, Id) then
      begin
        NoteNode(ASource.Members[Id].Body, False);
      end;
    end;
  finally
    FResolver.UnpinTree;
  end;
end;

/// <summary>Fehlende Units aus AUnits (ohne AExcept) als uses-Ergänzung im Abschnitt AKind von ATree.</summary>
procedure AddMissing(ATree: TSyntaxTree; AKind: TSyntaxKind; const AUnits, AExcept: TArray<string>;
  const ALineBreak: string; var AEdits: TArray<TTextEdit>);
var
  Used, Missing: TArray<string>;
  Name: string;
  Offset: Integer;
  Edit: TTextEdit;
begin
  Used := TUsesClauses.UsedUnits(ATree.Tokens);
  Missing := nil;
  for Name in AUnits do
  begin
    if not TUsesClauses.IsUsed(Used, Name, nil) and (IndexText(Name, AExcept) < 0) then
    begin
      Missing := Missing + [Name];
    end;
  end;
  Offset := SectionOffset(ATree, AKind);
  if (Missing <> nil) and (Offset >= 0) and TUsesClauses.AddUnit(ATree.Tokens, Offset, string.Join(', ', Missing),
    ALineBreak, Edit) then
  begin
    AEdits := AEdits + [Edit];
  end;
end;

/// <summary>Ergänzt in der Ziel-Unit AFiles[ATarget.FileName] die uses für die Namen, die die Deklarationen der
/// Mitglieder AIds und die Rümpfe von ABodyIds aus ASource benutzen.</summary>
procedure AddUses(AScan: TUsesScan; ASource: TClassLayout; const AIds, ABodyIds: TArray<Integer>;
  AFiles: TMemberFiles; const ATarget: TMemberClassRef);
var
  Text: string;
  TargetTree: TSyntaxTree;
  Target: TClassLayout;
  Edits: TArray<TTextEdit>;
begin
  Text := AFiles.Text(ATarget.FileName);
  Target := TMemberTransfer.ParseLayout(Text, ATarget.ClassName, TargetTree);
  if Target = nil then
  begin
    raise Failed(Format('%s ist nach dem Umbau nicht mehr lesbar.', [ATarget.ClassName]));
  end;
  try
    AScan.Scan(ASource, Target, TUsesClauses.OwnName(TargetTree.Tokens), AIds, ABodyIds);
    Edits := nil;
    AddMissing(TargetTree, TSyntaxKind.InterfaceSection, AScan.InterfaceUnits, nil, TTextLines.LineBreakOf(Text),
      Edits);
    AddMissing(TargetTree, TSyntaxKind.ImplementationSection, AScan.ImplementationUnits, AScan.InterfaceUnits,
      TTextLines.LineBreakOf(Text), Edits);
    if Edits <> nil then
    begin
      AFiles.Put(ATarget.FileName, TTextChanges.Apply(Text, Edits));
    end;
  finally
    Target.Free;
    TargetTree.Free;
  end;
end;

/// <summary>Kopfzeile der Klasse AClassName in AText; 0 ohne.</summary>
function ClassLine(const AText, AClassName: string): Integer;
var
  Layout: TClassLayout;
  Tree: TSyntaxTree;
begin
  Result := 0;
  Layout := TMemberTransfer.ParseLayout(AText, AClassName, Tree);
  if Layout = nil then
  begin
    Exit;
  end;
  try
    Result := Layout.HeaderLine;
  finally
    Layout.Free;
    Tree.Free;
  end;
end;

/// <summary>Fehlerfrei parsen wie vorher; sonst EJsonRpcError mit der ersten Meldung.</summary>
procedure CheckParses(const AFileName, AOriginal, ANewText: string);
var
  Before, Check: TSyntaxTree;
begin
  Before := TSyntaxTreeCache.Parse(AOriginal);
  Check := TSyntaxTreeCache.Parse(ANewText);
  try
    if Length(Check.Diagnostics) > Length(Before.Diagnostics) then
    begin
      raise Failed(Format('Nach der Änderung parst %s nicht mehr fehlerfrei (Zeile %d: %s).',
        [ExtractFileName(AFileName), Check.Diagnostics[0].StartPos.Line + 1, Check.Diagnostics[0].Message]));
    end;
  finally
    Check.Free;
    Before.Free;
  end;
end;

type
  /// <summary>Ein Verschieben: Anfrage, Ziele, gelesene Dateien und Ergebnis.</summary>
  TMemberMoveRun = class
  private
    FResolver: TNameResolver;
    FTree: TSyntaxTree;
    FFileName: string;
    FText: string;
    FContext: TMoveMemberContext;
    FUp: Boolean;
    FFound: TMoveMemberInfo;
    FRequest: TMoveMemberRequest;
    FHits: TArray<TClassHit>;
    FTargets: TArray<TMemberClassRef>;
    FFiles: TMemberFiles;
    FSource: TClassLayout;
    FPlan: TMoveMemberPlan;
    procedure ReadRequest(ABody: TJSONObject);
    procedure ChooseTargets(const AWanted: TArray<string>);
    procedure Load(const AFileName: string);
    procedure PullUp;
    /// <summary>Zeilen der Klasse, der gewählten Nachfahren und ihrer Rümpfe.</summary>
    function OwnRanges: TArray<TLineRange>;
    /// <summary>Verweise auf die Mitglieder außerhalb der Klasse und der gewählten Nachfahren.</summary>
    procedure CollectUsages;
    procedure PushDown;
    /// <summary>Mitglieder, deren Rumpf wandert; abstrakt nach oben wandert nur die Deklaration.</summary>
    function BodyIds: TArray<Integer>;
    procedure AddAllUses;
    function Answer: TJSONObject;
  public
    constructor Create(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const AContext: TMoveMemberContext);
    destructor Destroy; override;
    function Run(const APosition: TTextPosition): TJSONObject;
  end;

constructor TMemberMoveRun.Create(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
  const AContext: TMoveMemberContext);
begin
  inherited Create;
  FResolver := AResolver;
  FTree := ATree;
  FFileName := AFileName;
  FText := AText;
  FContext := AContext;
  FFiles := TMemberFiles.Create;
end;

destructor TMemberMoveRun.Destroy;
begin
  FSource.Free;
  FFiles.Free;
  inherited;
end;

procedure TMemberMoveRun.ReadRequest(ABody: TJSONObject);
begin
  FRequest := Default(TMoveMemberRequest);
  FRequest.Members := Ids(ABody, 'members');
  FRequest.Abstract := Ids(ABody, 'abstract');
  FRequest.RaiseVisibility := TClassVisibility.Protected_;
  if (ABody.GetValue('option') is TJSONBool) and FUp then
  begin
    FRequest.OverrideSiblings := TJSONBool(ABody.GetValue('option')).AsBoolean;
  end
  else if ABody.GetValue('option') is TJSONBool then
  begin
    FRequest.KeepAbstract := TJSONBool(ABody.GetValue('option')).AsBoolean;
  end;
end;

procedure TMemberMoveRun.ChooseTargets(const AWanted: TArray<string>);
var
  mHit: TClassHit;
begin
  FHits := TargetHits(FTree, FText, FFileName, FContext.Index, FFound, FUp);
  FTargets := nil;
  for mHit in FHits do
  begin
    if (IndexText(mHit.Ref.ClassName, AWanted) >= 0) and ((FTargets = nil) or not FUp) then
    begin
      FTargets := FTargets + [mHit.Ref];
    end;
  end;
  if FTargets = nil then
  begin
    raise Failed('Bitte ein Ziel wählen, das im Projekt liegt.');
  end;
end;

procedure TMemberMoveRun.Load(const AFileName: string);
begin
  if not FFiles.Has(AFileName) then
  begin
    FFiles.Add(AFileName, ReadFile(FContext, AFileName));
  end;
end;

procedure TMemberMoveRun.PullUp;
var
  mHit: TClassHit;
  mReason: string;
begin
  // Andere Nachfahren des Ziels (für override).
  for mHit in DirectDescendants(FTree, FText, FFileName, FContext.Index, FTargets[0].ClassName) do
  begin
    Load(mHit.Ref.FileName);
    FRequest.Siblings := FRequest.Siblings + [mHit.Ref];
  end;
  if not TMoveMember.PullUp(FFiles, TMemberClassRef.Create(FFileName, FFound.ClassName), FTargets[0], FRequest,
    FPlan, mReason) then
  begin
    raise Failed(mReason);
  end;
end;

function TMemberMoveRun.OwnRanges: TArray<TLineRange>;
var
  mRef: TMemberClassRef;
  mLayout: TClassLayout;
  mTree: TSyntaxTree;
begin
  Result := ClassRanges(FSource, FFileName);
  for mRef in FTargets do
  begin
    mLayout := TMemberTransfer.ParseLayout(FFiles.Text(mRef.FileName), mRef.ClassName, mTree);
    if mLayout <> nil then
    begin
      try
        Result := Result + ClassRanges(mLayout, mRef.FileName);
      finally
        mLayout.Free;
        mTree.Free;
      end;
    end;
  end;
end;

procedure TMemberMoveRun.CollectUsages;
var
  mRanges: TArray<TLineRange>;
  mId: Integer;
  mLocation: TReferenceLocation;
begin
  mRanges := OwnRanges;
  for mId in FRequest.Members do
  begin
    if (mId < 0) or (mId > High(FSource.Members)) then
    begin
      Continue;
    end;
    for mLocation in TLspReferences.Find(FResolver, FContext.Index, FTree, FFileName,
      NamePosition(FTree, FSource.Members[mId].Node, FSource.Members[mId].Name), False, FContext.Files,
      FContext.ReadText) do
    begin
      if not InRanges(mRanges, mLocation.FileName, mLocation.Range.StartPos.Line) then
      begin
        FRequest.Usages := FRequest.Usages + [TMemberUsage.Create(mId, Format('%s:%d',
          [ExtractFileName(mLocation.FileName), mLocation.Range.StartPos.Line + 1]))];
      end;
    end;
  end;
end;

procedure TMemberMoveRun.PushDown;
var
  mReason: string;
begin
  FRequest.AllTargets := Length(FHits);
  CollectUsages;
  if not TMoveMember.PushDown(FFiles, TMemberClassRef.Create(FFileName, FFound.ClassName), FTargets, FRequest,
    FPlan, mReason) then
  begin
    raise Failed(mReason);
  end;
end;

function TMemberMoveRun.BodyIds: TArray<Integer>;
var
  mId: Integer;
begin
  Result := nil;
  for mId in FRequest.Members do
  begin
    if not (FUp and TMemberTransfer.Has(FRequest.Abstract, mId)) then
    begin
      Result := Result + [mId];
    end;
  end;
end;

procedure TMemberMoveRun.AddAllUses;
var
  mRef: TMemberClassRef;
  mScan: TUsesScan;
begin
  for mRef in FTargets do
  begin
    if SameText(mRef.FileName, FFileName) then
    begin
      Continue;
    end;
    mScan := TUsesScan.Create(FResolver, FTree, FFileName, FUp);
    try
      AddUses(mScan, FSource, FRequest.Members, BodyIds, FFiles, mRef);
    finally
      mScan.Free;
    end;
  end;
end;

function TMemberMoveRun.Answer: TJSONObject;
var
  mChanges: TWorkspaceChanges;
  mWarning, mFileName, mDescription: string;
begin
  mChanges := TWorkspaceChanges.Create;
  try
    for mWarning in FPlan.Warnings do
    begin
      mChanges.Warn(mWarning);
    end;
    for mFileName in FFiles.Files do
    begin
      if FFiles.Changed(mFileName) then
      begin
        CheckParses(mFileName, FFiles.Original(mFileName), FFiles.Text(mFileName));
        mChanges.Add(mFileName, TTextChanges.Diff(FFiles.Original(mFileName), FFiles.Text(mFileName)));
      end;
    end;
    mDescription := Format('%d Mitglieder, %d Dateien', [Length(FPlan.Moved) + Length(FPlan.Abstracts),
      mChanges.FileCount]);
    Result := TJSONObject.Create;
    Result.AddPair('edit', mChanges.ToJson(TLspMoveMember.AnnotationId, 'Mitglied verschieben', mDescription));
    Result.AddPair('warnings', mChanges.WarningsJson);
    Result.AddPair('file', TDocumentUris.FromPath(FTargets[0].FileName));
    Result.AddPair('line', TJSONNumber.Create(ClassLine(FFiles.Text(FTargets[0].FileName), FTargets[0].ClassName)));
    Result.AddPair('moved', TJSONNumber.Create(Length(FPlan.Moved) + Length(FPlan.Abstracts)));
  finally
    mChanges.Free;
  end;
end;

function TMemberMoveRun.Run(const APosition: TTextPosition): TJSONObject;
var
  mBody: TJSONObject;
  mRef: TMemberClassRef;
begin
  if not (FContext.Request is TJSONObject) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Anfrage mit members und targets fehlt');
  end;
  mBody := TJSONObject(FContext.Request);
  FUp := IsUp(FContext.Direction);
  FFound := Info(FTree, FText, APosition);
  ReadRequest(mBody);
  ChooseTargets(Names(mBody, 'targets'));
  FSource := TClassLayout.Read(FTree, FText, TClassLayout.DeclNamed(FTree, FFound.ClassName));
  FFiles.Add(FFileName, FText);
  for mRef in FTargets do
  begin
    Load(mRef.FileName);
  end;
  if FUp then
  begin
    PullUp;
  end
  else
  begin
    PushDown;
  end;
  AddAllUses;
  Result := Answer;
end;

class function TLspMoveMember.Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName,
  AText: string; const APosition: TTextPosition; const AContext: TMoveMemberContext): TJSONObject;
var
  mRun: TMemberMoveRun;
begin
  mRun := TMemberMoveRun.Create(AResolver, ATree, AFileName, AText, AContext);
  try
    Result := mRun.Run(APosition);
  finally
    mRun.Free;
  end;
end;

end.
