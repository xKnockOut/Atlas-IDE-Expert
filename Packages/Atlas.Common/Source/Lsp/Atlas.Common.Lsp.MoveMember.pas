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
    cClientCommand = 'atlas.moveMember';
    cPrepareCommand = 'atlas.server.moveMember.prepare';
    cApplyCommand = 'atlas.server.moveMember';
    cAnnotationId = 'moveMember';
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
  Atlas.Common.Lsp.WorkspaceChanges,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TLspMoveMemberText = (DirectionUpOrDownMissing, HasNoAncestorInThe, HasNoDescendantsInThe, CannotBeRead,
    IsOnlyInTheImplementation, ComesFromWhichWouldHave, IsNoLongerReadableAfter, AfterTheChangeNoLonger,
    PleaseChooseATargetThat, RequestWithMembersAndTargets, MoveMember, MoveToAncestor, MoveToDescendants,
    MembersFiles, MoveMember2);

const
  cTexts: array[TLspMoveMemberText] of TAtlasText = (
    (De: 'Richtung "up" oder "down" fehlt'; En: 'Direction "up" or "down" missing'),
    (De: '%s hat keinen Vorfahren im Projekt.'; En: '%s has no ancestor in the project.'),
    (De: '%s hat keine Nachfahren im Projekt.'; En: '%s has no descendants in the project.'),
    (De: '%s lässt sich nicht lesen.'; En: '%s cannot be read.'),
    (De: '%s steht nur im implementation-Teil von %s und ist in %s nicht sichtbar.';
     En: '%s is only in the implementation part of %s and is not visible in %s.'),
    (De: '%s stammt aus %s, die %s im interface einbinden müsste (Kreisverweis).';
     En: '%s comes from %s, which would have to use %s in the interface (circular reference).'),
    (De: '%s ist nach dem Umbau nicht mehr lesbar.'; En: '%s is no longer readable after the change.'),
    (De: 'Nach der Änderung parst %s nicht mehr fehlerfrei (Zeile %d: %s).';
     En: 'After the change %s no longer parses without errors (line %d: %s).'),
    (De: 'Bitte ein Ziel wählen, das im Projekt liegt.'; En: 'Please choose a target that lies in the project.'),
    (De: 'Anfrage mit members und targets fehlt'; En: 'Request with members and targets missing'),
    (De: 'Mitglied verschieben: '; En: 'Move member: '),
    (De: '„%s“ in Vorfahr verschieben …'; En: 'Move “%s” to ancestor …'),
    (De: '„%s“ in Nachfahren verschieben …'; En: 'Move “%s” to descendants …'),
    (De: '%d Mitglieder, %d Dateien'; En: '%d members, %d files'),
    (De: 'Mitglied verschieben'; En: 'Move member'));

{$SCOPEDENUMS OFF}

type
  /// <summary>Klasse des Projekts mit Unit und Vorfahr.</summary>
  TClassHit = record
    Ref: TMemberClassRef;
    UnitName: string;
    Ancestor: string;
  end;

const
  /// <summary>Höchstens so viele Vorfahren nach oben.</summary>
  cMaxDepth = 16;

function Failed(const AMessage: string): EJsonRpcError;
begin
  Result := EJsonRpcError.Create(TLspErrorCode.cRequestFailed, cTexts[TLspMoveMemberText.MoveMember].Text + AMessage);
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
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TLspMoveMemberText.DirectionUpOrDownMissing].Text);
  end;
end;

/// <summary>Liegt die Datei in einer Bibliothek (RTL/VCL, Suchpfade)?</summary>
function IsLibrary(const AIndex: ISymbolIndex; const AFileName: string): Boolean;
var
  mUnitIndex: TUnitIndex;
begin
  Result := not AIndex.FindFile(AFileName, mUnitIndex) or mUnitIndex.Library_;
end;

/// <summary>Klasse AName in ATree (Datei AFileName).</summary>
function DeclHit(ATree: TSyntaxTree; const AText, AFileName, AName: string; out AHit: TClassHit): Boolean;
var
  mDecl: TSyntaxNode;
  mLayout: TClassLayout;
begin
  mDecl := TClassLayout.DeclNamed(ATree, AName);
  Result := mDecl <> nil;
  if not Result then
  begin
    Exit;
  end;
  mLayout := TClassLayout.Read(ATree, AText, mDecl);
  try
    AHit.Ref := TMemberClassRef.Create(AFileName, mLayout.Name);
    AHit.UnitName := TUsesClauses.OwnName(ATree.Tokens);
    if mLayout.Ancestors <> nil then
    begin
      AHit.Ancestor := mLayout.Ancestors[0];
    end;
  finally
    mLayout.Free;
  end;
end;

/// <summary>Klasse AName des Projekts im Index, nicht in AFileName.</summary>
function IndexHit(const AIndex: ISymbolIndex; const AFileName, AName: string; out AHit: TClassHit): Boolean;
var
  mLocation: TSymbolLocation;
begin
  for mLocation in AIndex.FindSymbols(AName) do
  begin
    if (mLocation.Symbol.Kind = TIndexSymbolKind.ClassType) and (mLocation.Symbol.Container = '') and
      not SameText(mLocation.FileName, AFileName) and not IsLibrary(AIndex, mLocation.FileName) then
    begin
      AHit.Ref := TMemberClassRef.Create(mLocation.FileName, mLocation.Symbol.Name);
      AHit.UnitName := mLocation.UnitName;
      if mLocation.Symbol.Ancestors <> nil then
      begin
        AHit.Ancestor := mLocation.Symbol.Ancestors[0];
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
  mName: string;
begin
  AHit := Default(TClassHit);
  mName := PlainName(AName);
  Result := (mName <> '') and not SameText(mName, 'TObject') and (DeclHit(ATree, AText, AFileName, mName, AHit) or
    ((AIndex <> nil) and IndexHit(AIndex, AFileName, mName, AHit)));
end;

/// <summary>Vorfahren des Projekts ab AAncestor, der direkte zuerst.</summary>
function AncestorChain(ATree: TSyntaxTree; const AText, AFileName: string; const AIndex: ISymbolIndex;
  const AAncestor: string): TArray<TClassHit>;
var
  mHit: TClassHit;
  mName: string;
begin
  Result := nil;
  mName := AAncestor;
  while (Length(Result) < cMaxDepth) and FindClass(ATree, AText, AFileName, AIndex, mName, mHit) do
  begin
    Result := Result + [mHit];
    mName := mHit.Ancestor;
  end;
end;

/// <summary>Direkte Nachfahren von AClassName im Projekt: in ATree und im Index.</summary>
function DirectDescendants(ATree: TSyntaxTree; const AText, AFileName: string; const AIndex: ISymbolIndex;
  const AClassName: string): TArray<TClassHit>;
var
  mDecl: TSyntaxNode;
  mLayout: TClassLayout;
  mLocation: TSymbolLocation;
  mHit: TClassHit;
begin
  Result := nil;
  for mDecl in TClassLayout.AllDecls(ATree) do
  begin
    mLayout := TClassLayout.Read(ATree, AText, mDecl);
    try
      if (mLayout.Ancestors <> nil) and SameText(PlainName(mLayout.Ancestors[0]), AClassName) then
      begin
        mHit := Default(TClassHit);
        mHit.Ref := TMemberClassRef.Create(AFileName, mLayout.Name);
        mHit.UnitName := TUsesClauses.OwnName(ATree.Tokens);
        mHit.Ancestor := mLayout.Ancestors[0];
        Result := Result + [mHit];
      end;
    finally
      mLayout.Free;
    end;
  end;
  if AIndex = nil then
  begin
    Exit;
  end;
  for mLocation in AIndex.Descendants(AClassName) do
  begin
    if (mLocation.Symbol.Kind = TIndexSymbolKind.ClassType) and not SameText(mLocation.FileName, AFileName) and
      not IsLibrary(AIndex, mLocation.FileName) and (mLocation.Symbol.Ancestors <> nil) and
      SameText(PlainName(mLocation.Symbol.Ancestors[0]), AClassName) then
    begin
      mHit := Default(TClassHit);
      mHit.Ref := TMemberClassRef.Create(mLocation.FileName, mLocation.Symbol.Name);
      mHit.UnitName := mLocation.UnitName;
      mHit.Ancestor := mLocation.Symbol.Ancestors[0];
      Result := Result + [mHit];
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
  mReason: string;
begin
  if not TMoveMember.Prepare(ATree, AText, APosition.Line, Result, mReason) then
  begin
    raise Failed(mReason);
  end;
end;

function Action(const ATitle, AUri: string; const APosition: TTextPosition; const ADirection: string): TJSONObject;
var
  mArguments: TJSONArray;
  mCommand: TJSONObject;
begin
  mArguments := TJSONArray.Create;
  mArguments.Add(AUri);
  mArguments.AddElement(TLspPositions.PositionToJson(APosition));
  mArguments.Add(ADirection);
  mCommand := TJSONObject.Create;
  mCommand.AddPair('title', ATitle);
  mCommand.AddPair('command', TLspMoveMember.cClientCommand);
  mCommand.AddPair('arguments', mArguments);
  Result := TJSONObject.Create;
  Result.AddPair('title', ATitle);
  Result.AddPair('kind', TMoveMember.cKind);
  Result.AddPair('command', mCommand);
end;

class function TLspMoveMember.Actions(ATree: TSyntaxTree; const AText, AFileName, AUri: string;
  const APosition: TTextPosition; const AIndex: ISymbolIndex): TArray<TJSONObject>;
var
  mFound: TMoveMemberInfo;
  mReason: string;
  mHit: TClassHit;
begin
  Result := nil;
  if (ATree = nil) or not TMoveMember.Prepare(ATree, AText, APosition.Line, mFound, mReason) then
  begin
    Exit;
  end;
  if FindClass(ATree, AText, AFileName, AIndex, mFound.Ancestor, mHit) then
  begin
    Result := Result + [Action(cTexts[TLspMoveMemberText.MoveToAncestor].Fmt([mFound.SelectedName]), AUri, APosition,
      'up')];
  end;
  if DirectDescendants(ATree, AText, AFileName, AIndex, mFound.ClassName) <> nil then
  begin
    Result := Result + [Action(cTexts[TLspMoveMemberText.MoveToDescendants].Fmt([mFound.SelectedName]), AUri, APosition,
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
  mNeeds: TJSONArray;
  mNeed: Integer;
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
  mNeeds := TJSONArray.Create;
  for mNeed in AItem.Needs do
  begin
    mNeeds.AddElement(TJSONNumber.Create(mNeed));
  end;
  Result.AddPair('needs', mNeeds);
end;

function TargetsJson(const AHits: TArray<TClassHit>; AUp: Boolean): TJSONArray;
var
  mHit: TClassHit;
  mEntry: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mHit in AHits do
  begin
    mEntry := TJSONObject.Create;
    mEntry.AddPair('name', mHit.Ref.ClassName);
    mEntry.AddPair('unit', mHit.UnitName);
    mEntry.AddPair('checked', TJSONBool.Create(not AUp or (Result.Count = 0)));
    Result.AddElement(mEntry);
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
  mFound: TMoveMemberInfo;
  mUp: Boolean;
  mHits: TArray<TClassHit>;
  mItem: TTransferCandidate;
  mList: TJSONArray;
begin
  mUp := IsUp(AContext.Direction);
  mFound := Info(ATree, AText, APosition);
  mHits := TargetHits(ATree, AText, AFileName, AContext.Index, mFound, mUp);
  if (mHits = nil) and mUp then
  begin
    raise Failed(cTexts[TLspMoveMemberText.HasNoAncestorInThe].Fmt([mFound.ClassName]));
  end;
  if mHits = nil then
  begin
    raise Failed(cTexts[TLspMoveMemberText.HasNoDescendantsInThe].Fmt([mFound.ClassName]));
  end;
  Result := TJSONObject.Create;
  Result.AddPair('className', mFound.ClassName);
  Result.AddPair('ownUnit', TUsesClauses.OwnName(ATree.Tokens));
  Result.AddPair('member', mFound.SelectedName);
  Result.AddPair('direction', LowerCase(AContext.Direction));
  Result.AddPair('name', '');
  mList := TJSONArray.Create;
  for mItem in mFound.Candidates do
  begin
    mList.AddElement(CandidateJson(mItem, mFound.Selected, mUp));
  end;
  Result.AddPair('candidates', mList);
  Result.AddPair('targets', TargetsJson(mHits, mUp));
  Result.AddPair('multiTarget', TJSONBool.Create(not mUp));
  // Nach unten bleiben benutzte Mitglieder oben (sie werden bei Bedarf sichtbar gemacht).
  Result.AddPair('needsRequired', TJSONBool.Create(mUp));
  Result.AddPair('option', OptionJson(mUp));
  Result.AddPair('notes', TJSONArray.Create);
end;

function Ids(AObject: TJSONObject; const AKey: string): TArray<Integer>;
var
  mValue, mItem: TJSONValue;
begin
  Result := nil;
  mValue := AObject.GetValue(AKey);
  if mValue is TJSONArray then
  begin
    for mItem in TJSONArray(mValue) do
    begin
      if mItem is TJSONNumber then
      begin
        Result := Result + [TJSONNumber(mItem).AsInt];
      end;
    end;
  end;
end;

function Names(AObject: TJSONObject; const AKey: string): TArray<string>;
var
  mValue, mItem: TJSONValue;
begin
  Result := nil;
  mValue := AObject.GetValue(AKey);
  if mValue is TJSONArray then
  begin
    for mItem in TJSONArray(mValue) do
    begin
      Result := Result + [Trim(mItem.Value)];
    end;
  end;
end;

/// <summary>Text der Datei; EJsonRpcError, wenn sie nicht lesbar ist.</summary>
function ReadFile(const AContext: TMoveMemberContext; const AFileName: string): string;
begin
  if not (Assigned(AContext.ReadText) and AContext.ReadText(AFileName, Result)) then
  begin
    raise Failed(cTexts[TLspMoveMemberText.CannotBeRead].Fmt([ExtractFileName(AFileName)]));
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
  mMember: TClassMember;
  mRange: TLineRange;
begin
  mRange.FileName := AFileName;
  mRange.First := ALayout.FirstLine;
  mRange.Last := ALayout.EndLine;
  Result := [mRange];
  for mMember in ALayout.Members do
  begin
    if mMember.Body <> nil then
    begin
      mRange.First := mMember.BodyFirstLine;
      mRange.Last := mMember.BodyLastLine;
      Result := Result + [mRange];
    end;
  end;
end;

function InRanges(const ARanges: TArray<TLineRange>; const AFileName: string; ALine: Integer): Boolean;
var
  mRange: TLineRange;
begin
  for mRange in ARanges do
  begin
    if SameText(mRange.FileName, AFileName) and (ALine >= mRange.First) and (ALine <= mRange.Last) then
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
  mIndex: Integer;
  mName: string;
begin
  if ANode = nil then
  begin
    Exit;
  end;
  if (ANode.Kind = TSyntaxKind.Identifier) and ((ANode.Parent = nil) or
    (ANode.Parent.Kind <> TSyntaxKind.GenericParams)) then
  begin
    mName := ANode.Name;
    if mName.StartsWith('&') then
    begin
      mName := mName.Substring(1);
    end;
    ANames := ANames + [TArray<string>.Create(mName)];
    AOffsets := AOffsets + [ANode.StartOffset];
  end
  else if (ANode.Kind = TSyntaxKind.TypeReference) and (ANode.Name <> '') then
  begin
    ANames := ANames + [ANode.Name.Split(['.'])];
    AOffsets := AOffsets + [ANode.StartOffset];
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    CollectNames(ANode[mIndex], ANames, AOffsets);
  end;
end;

function SectionLine(ATree: TSyntaxTree; AKind: TSyntaxKind): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ATree.Root.ChildCount - 1 do
  begin
    if ATree.Root[mIndex].Kind = AKind then
    begin
      Exit(ATree.Root[mIndex].StartPos.Line);
    end;
  end;
  Result := -1;
end;

function SectionOffset(ATree: TSyntaxTree; AKind: TSyntaxKind): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ATree.Root.ChildCount - 1 do
  begin
    if ATree.Root[mIndex].Kind = AKind then
    begin
      Exit(ATree.Root[mIndex].StartOffset + 1);
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
    raise Failed(cTexts[TLspMoveMemberText.IsOnlyInTheImplementation].Fmt([ADisplay, FSourceUnit, FTargetUnit]));
  end;
  // Nachfahren binden die Quelle ohnehin ein.
  if not FUp then
  begin
    Exit;
  end;
  if ADeclaration and FInInterface then
  begin
    raise Failed(cTexts[TLspMoveMemberText.ComesFromWhichWouldHave].Fmt([ADisplay, FSourceUnit, FTargetUnit]));
  end;
  AddOnce(ImplementationUnits, FSourceUnit);
end;

procedure TUsesScan.Note(const ANames: TArray<string>; AOffset: Integer; ADeclaration: Boolean);
var
  mMeaning: TMoveClassMeaning;
begin
  mMeaning := FLookup(FTree, FFileName, ANames, AOffset);
  if not mMeaning.Found or mMeaning.IsLocal or (mMeaning.UnitName = '') or SameText(mMeaning.UnitName, 'System') or
    SameText(mMeaning.UnitName, FTargetUnit) then
  begin
    Exit;
  end;
  // Mitglieder der Klasse selbst (sie wandern mit oder sind geerbt).
  if SameText(mMeaning.FileName, FFileName) and InRanges(FRanges, FFileName, mMeaning.Position.Line) then
  begin
    Exit;
  end;
  if SameText(mMeaning.UnitName, FSourceUnit) then
  begin
    NoteSourceUnit(string.Join('.', ANames), mMeaning.Position.Line, ADeclaration);
  end
  else if ADeclaration and FInInterface then
  begin
    AddOnce(InterfaceUnits, mMeaning.UnitName);
  end
  else
  begin
    AddOnce(ImplementationUnits, mMeaning.UnitName);
  end;
end;

procedure TUsesScan.NoteNode(ANode: TSyntaxNode; ADeclaration: Boolean);
var
  mNameList: TArray<TArray<string>>;
  mOffsets: TArray<Integer>;
  mIndex: Integer;
begin
  mNameList := nil;
  mOffsets := nil;
  CollectNames(ANode, mNameList, mOffsets);
  for mIndex := 0 to High(mNameList) do
  begin
    Note(mNameList[mIndex], mOffsets[mIndex], ADeclaration);
  end;
end;

procedure TUsesScan.Scan(ASource, ATarget: TClassLayout; const ATargetUnit: string;
  const AIds, ABodyIds: TArray<Integer>);
var
  mId: Integer;
begin
  FTargetUnit := ATargetUnit;
  FInInterface := ATarget.InInterface;
  FRanges := ClassRanges(ASource, FFileName);
  FResolver.PinTree(FTree, FFileName);
  try
    for mId in AIds do
    begin
      // Erst die Deklaration, dann der Rumpf.
      NoteNode(ASource.Members[mId].Node, True);
      if TMemberTransfer.Has(ABodyIds, mId) then
      begin
        NoteNode(ASource.Members[mId].Body, False);
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
  mUsed, mMissing: TArray<string>;
  mName: string;
  mOffset: Integer;
  mEdit: TTextEdit;
begin
  mUsed := TUsesClauses.UsedUnits(ATree.Tokens);
  mMissing := nil;
  for mName in AUnits do
  begin
    if not TUsesClauses.IsUsed(mUsed, mName, nil) and (IndexText(mName, AExcept) < 0) then
    begin
      mMissing := mMissing + [mName];
    end;
  end;
  mOffset := SectionOffset(ATree, AKind);
  if (mMissing <> nil) and (mOffset >= 0) and TUsesClauses.AddUnit(ATree.Tokens, mOffset, string.Join(', ', mMissing),
    ALineBreak, mEdit) then
  begin
    AEdits := AEdits + [mEdit];
  end;
end;

/// <summary>Ergänzt in der Ziel-Unit AFiles[ATarget.FileName] die uses für die Namen, die die Deklarationen der
/// Mitglieder AIds und die Rümpfe von ABodyIds aus ASource benutzen.</summary>
procedure AddUses(AScan: TUsesScan; ASource: TClassLayout; const AIds, ABodyIds: TArray<Integer>;
  AFiles: TMemberFiles; const ATarget: TMemberClassRef);
var
  mText: string;
  mTargetTree: TSyntaxTree;
  mTarget: TClassLayout;
  mEdits: TArray<TTextEdit>;
begin
  mText := AFiles.Text(ATarget.FileName);
  mTarget := TMemberTransfer.ParseLayout(mText, ATarget.ClassName, mTargetTree);
  if mTarget = nil then
  begin
    raise Failed(cTexts[TLspMoveMemberText.IsNoLongerReadableAfter].Fmt([ATarget.ClassName]));
  end;
  try
    AScan.Scan(ASource, mTarget, TUsesClauses.OwnName(mTargetTree.Tokens), AIds, ABodyIds);
    mEdits := nil;
    AddMissing(mTargetTree, TSyntaxKind.InterfaceSection, AScan.InterfaceUnits, nil, TTextLines.LineBreakOf(mText),
      mEdits);
    AddMissing(mTargetTree, TSyntaxKind.ImplementationSection, AScan.ImplementationUnits, AScan.InterfaceUnits,
      TTextLines.LineBreakOf(mText), mEdits);
    if mEdits <> nil then
    begin
      AFiles.Put(ATarget.FileName, TTextChanges.Apply(mText, mEdits));
    end;
  finally
    mTarget.Free;
    mTargetTree.Free;
  end;
end;

/// <summary>Kopfzeile der Klasse AClassName in AText; 0 ohne.</summary>
function ClassLine(const AText, AClassName: string): Integer;
var
  mLayout: TClassLayout;
  mTree: TSyntaxTree;
begin
  Result := 0;
  mLayout := TMemberTransfer.ParseLayout(AText, AClassName, mTree);
  if mLayout = nil then
  begin
    Exit;
  end;
  try
    Result := mLayout.HeaderLine;
  finally
    mLayout.Free;
    mTree.Free;
  end;
end;

/// <summary>Fehlerfrei parsen wie vorher; sonst EJsonRpcError mit der ersten Meldung.</summary>
procedure CheckParses(const AFileName, AOriginal, ANewText: string);
var
  mBefore, mCheck: TSyntaxTree;
begin
  mBefore := TSyntaxTreeCache.Parse(AOriginal);
  mCheck := TSyntaxTreeCache.Parse(ANewText);
  try
    if Length(mCheck.Diagnostics) > Length(mBefore.Diagnostics) then
    begin
      raise Failed(cTexts[TLspMoveMemberText.AfterTheChangeNoLonger].Fmt([ExtractFileName(AFileName),
        mCheck.Diagnostics[0].StartPos.Line + 1, mCheck.Diagnostics[0].Message]));
    end;
  finally
    mCheck.Free;
    mBefore.Free;
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
    raise Failed(cTexts[TLspMoveMemberText.PleaseChooseATargetThat].Text);
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
    for mLocation in TLspReferences.Find(FResolver, FContext.Index, FTree, TReferenceSearch.Create(FFileName,
      NamePosition(FTree, FSource.Members[mId].Node, FSource.Members[mId].Name), False, FContext.Files,
      FContext.ReadText)) do
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
    mDescription := cTexts[TLspMoveMemberText.MembersFiles].Fmt([Length(FPlan.Moved) + Length(FPlan.Abstracts),
      mChanges.FileCount]);
    Result := TJSONObject.Create;
    Result.AddPair('edit', mChanges.ToJson(TLspMoveMember.cAnnotationId, cTexts[TLspMoveMemberText.MoveMember2].Text,
      mDescription));
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
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TLspMoveMemberText.RequestWithMembersAndTargets].Text);
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

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.MoveMember', cTexts);

end.
