unit Atlas.Common.Lsp.ExtractInterface;

// „Interface aus Klasse herauslösen“ über das Protokoll (#664):
//   - Code-Aktion „Interface aus TFoo herauslösen …“ auf der Kopfzeile einer
//     Klasse mit wählbaren Mitgliedern, nur mit refactoring.extractInterface.
//     Sie trägt den Client-Befehl atlas.extractInterface mit [uri, position];
//     das Plugin holt die Kandidaten, zeigt den Dialog und dann die Vorschau.
//   - atlas.server.extractInterface.prepare [uri, position]: Klasse,
//     vorgeschlagener Name, Kandidaten (id, name, kind, display, visibility,
//     checked, enabled, reason), Hinweise und die Units des Projekts als Ziele.
//   - atlas.server.extractInterface [uri, position, {name, unit, members}]:
//     WorkspaceEdit mit Änderungsanmerkung für die Vorschau. unit leer oder
//     der eigene Name: dieselbe Unit. Eine Unit des Projekts bzw. des Index
//     erhält das Interface vor ihrer implementation und die Units der Typen
//     in den Signaturen in ihr uses; sonst entsteht eine neue Unit neben der
//     Klasse (und kommt ins Projekt). Die Unit der Klasse erhält die Ziel-Unit
//     in ihr uses. Braucht das Interface einen Typ aus der Unit der Klasse,
//     die es selbst im interface einbindet, bricht Atlas ab (Kreisverweis).
// Die Logik liegt in Atlas.Common.Editing.ExtractInterface.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.ExtractInterface,
  Atlas.Common.Lsp.References;

type
  /// <summary>Gibt es die Datei (auf der Platte oder als offenes Dokument)?</summary>
  TExtractExists = reference to function(const AFileName: string): Boolean;

  TExtractInterfaceContext = record
    Index: ISymbolIndex;
    HasProject: Boolean;
    Project: TProjectInfo;
    ReadText: TReferenceReadText;
    Exists: TExtractExists;
    /// <summary>GUID für das Interface; leer = neue GUID.</summary>
    Guid: string;
    /// <summary>Auflöser für Execute; gehört dem Aufrufer. Prepare braucht ihn nicht.</summary>
    Resolver: TNameResolver;
  end;

  TLspExtractInterface = class
  public const
    ClientCommand = 'atlas.extractInterface';
    PrepareCommand = 'atlas.server.extractInterface.prepare';
    ApplyCommand = 'atlas.server.extractInterface';
    AnnotationId = 'extractInterface';
  public
    /// <summary>Die Code-Aktion an APosition, wenn eingeschaltet und die Klasse dort wählbare Mitglieder hat;
    /// sonst nil. Der Aufrufer übernimmt die Objekte.</summary>
    class function Actions(AEnabled: Boolean; ATree: TSyntaxTree; const AText, AUri: string;
      const APosition: TTextPosition): TArray<TJSONObject>; static;
    /// <summary>Vorfahren über Baum und Index (für TExtractInterface.Supports).</summary>
    class function AncestorsLookup(ATree: TSyntaxTree; const AIndex: ISymbolIndex): TClassAncestorsLookup; static;
    /// <summary>Antwort auf prepare; EJsonRpcError ohne Klasse oder Kandidaten. Der Aufrufer übernimmt das
    /// Objekt.</summary>
    class function Prepare(ATree: TSyntaxTree; const AText: string; const APosition: TTextPosition;
      const AContext: TExtractInterfaceContext): TJSONObject; static;
    /// <summary>{"edit": WorkspaceEdit, "warnings": [...], "file": URI der Ziel-Unit, "name": Interface};
    /// EJsonRpcError bei ungültiger Anfrage. Der Aufrufer übernimmt das Objekt.</summary>
    class function Execute(ATree: TSyntaxTree; const AFileName, AText: string; const APosition: TTextPosition;
      ARequest: TJSONValue; const AContext: TExtractInterfaceContext): TJSONObject; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Projects.Paths,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.ClassLayout,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Editing.MoveClass,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.MoveClass,
  Atlas.Common.Lsp.PropertyFromAccessors,
  Atlas.Common.Lsp.WorkspaceChanges,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TLspExtractInterfaceText = (ExtractInterface, ExtractInterfaceFrom, RequestWithNameUnitAnd, AfterTheChangeNoLonger,
    IsNotAValidUnit, ComesFromWhichWouldHave, CannotBeRead, TheNameIsAlreadyTaken, HasNoInterfacePart,
    AlreadyExistsButDoesNot, WithMethodsFiles, ExtractInterface2);

const
  cTexts: array[TLspExtractInterfaceText] of TAtlasText = (
    (De: 'Interface herauslösen: '; En: 'Extract interface: '),
    (De: 'Interface aus %s herauslösen …'; En: 'Extract interface from %s …'),
    (De: 'Anfrage mit name, unit und members fehlt'; En: 'Request with name, unit and members missing'),
    (De: 'Nach der Änderung parst %s nicht mehr fehlerfrei (Zeile %d: %s).';
     En: 'After the change %s no longer parses without errors (line %d: %s).'),
    (De: '"%s" ist kein gültiger Unit-Name.'; En: '"%s" is not a valid unit name.'),
    (De: '%s stammt aus %s, die %s im interface einbinden müsste (Kreisverweis). Das Interface bitte in derselben ' +
      'Unit anlegen.';
     En: '%s comes from %s, which would have to use %s in the interface (circular reference). Please create the ' +
      'interface in the same unit.'),
    (De: '%s lässt sich nicht lesen.'; En: '%s cannot be read.'),
    (De: 'Der Name %s ist in %s schon vergeben.'; En: 'The name %s is already taken in %s.'),
    (De: '%s hat keinen interface-Teil.'; En: '%s has no interface part.'),
    (De: '%s gibt es schon, gehört aber nicht zum Projekt.';
     En: '%s already exists but does not belong to the project.'),
    (De: '%s mit %d Methoden, %d Dateien'; En: '%s with %d methods, %d files'),
    (De: 'Interface herauslösen'; En: 'Extract interface'));

{$SCOPEDENUMS OFF}

function Failed(const AMessage: string): EJsonRpcError;
begin
  Result := EJsonRpcError.Create(TLspErrorCode.RequestFailed, cTexts[TLspExtractInterfaceText.ExtractInterface].Text +
    AMessage);
end;

function VisibilityText(AVisibility: TClassVisibility): string;
begin
  Result := TClassEdits.VisibilityName(AVisibility);
end;

function MethodPointer(const AIndex: ISymbolIndex): TIsMethodPointer;
begin
  Result :=
    function(const ATypeName: string): Boolean
    begin
      Result := TLspPropertyFromAccessors.IsProcedural(ATypeName, AIndex);
    end;
end;

/// <summary>Vorfahren aus dem Kopf der Klassendeklaration ADecl (TypeReference vor dem ersten Mitglied).</summary>
function TreeAncestors(ADecl: TSyntaxNode): TArray<string>;
var
  mBody: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  mBody := ADecl.FindChild(TSyntaxKind.ClassType);
  mIndex := 0;
  while (mIndex < mBody.ChildCount) and (mBody[mIndex].Kind = TSyntaxKind.TypeReference) do
  begin
    Result := Result + [mBody[mIndex].Name];
    Inc(mIndex);
  end;
end;

/// <summary>Vorfahren der Klasse AClassName laut Index; False ohne Index oder Klasse.</summary>
function IndexAncestors(const AIndex: ISymbolIndex; const AClassName: string;
  out AAncestors: TArray<string>): Boolean;
var
  mLocation: TSymbolLocation;
begin
  AAncestors := nil;
  Result := False;
  if AIndex = nil then
  begin
    Exit;
  end;
  for mLocation in AIndex.FindSymbols(AClassName) do
  begin
    if (mLocation.Symbol.Kind = TIndexSymbolKind.ClassType) and (mLocation.Symbol.Container = '') then
    begin
      AAncestors := mLocation.Symbol.Ancestors;
      Exit(True);
    end;
  end;
end;

class function TLspExtractInterface.AncestorsLookup(ATree: TSyntaxTree;
  const AIndex: ISymbolIndex): TClassAncestorsLookup;
begin
  Result :=
    function(const AClassName: string; out AAncestors: TArray<string>): Boolean
    var
      mDecl: TSyntaxNode;
    begin
      mDecl := TClassLayout.DeclNamed(ATree, AClassName);
      if mDecl <> nil then
      begin
        AAncestors := TreeAncestors(mDecl);
        Exit(True);
      end;
      Result := IndexAncestors(AIndex, AClassName, AAncestors);
    end;
end;

class function TLspExtractInterface.Actions(AEnabled: Boolean; ATree: TSyntaxTree; const AText, AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  Info: TExtractInterfaceInfo;
  Reason, Title: string;
  Arguments: TJSONArray;
  Command, Action: TJSONObject;
begin
  Result := nil;
  if not AEnabled or (ATree = nil) or (TExtractInterface.ClassAt(ATree, APosition.Line) = nil) then
  begin
    Exit;
  end;
  if not TExtractInterface.Prepare(TClassSource.Create(ATree, AText, APosition.Line),
    TExtractInterfaceLookups.Create(nil, nil, nil), Info, Reason) then
  begin
    Exit;
  end;
  Title := cTexts[TLspExtractInterfaceText.ExtractInterfaceFrom].Fmt([Info.ClassName]);
  Arguments := TJSONArray.Create;
  Arguments.Add(AUri);
  Arguments.AddElement(TLspPositions.PositionToJson(APosition));
  Command := TJSONObject.Create;
  Command.AddPair('title', Title);
  Command.AddPair('command', ClientCommand);
  Command.AddPair('arguments', Arguments);
  Action := TJSONObject.Create;
  Action.AddPair('title', Title);
  Action.AddPair('kind', TExtractInterface.Kind);
  Action.AddPair('command', Command);
  Result := [Action];
end;

class function TLspExtractInterface.Prepare(ATree: TSyntaxTree; const AText: string;
  const APosition: TTextPosition; const AContext: TExtractInterfaceContext): TJSONObject;
var
  Info: TExtractInterfaceInfo;
  Reason, Note: string;
  Item: TExtractCandidate;
  List, Notes, Units: TJSONArray;
  Entry: TJSONObject;
  ProjectUnit: TProjectUnit;
begin
  if not TExtractInterface.Prepare(TClassSource.Create(ATree, AText, APosition.Line),
    TExtractInterfaceLookups.Create(AncestorsLookup(ATree, AContext.Index), nil, MethodPointer(AContext.Index)), Info,
    Reason) then
  begin
    raise Failed(Reason);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('className', Info.ClassName);
  Result.AddPair('name', Info.SuggestedName);
  Result.AddPair('ownUnit', TUsesClauses.OwnName(ATree.Tokens));
  List := TJSONArray.Create;
  for Item in Info.Candidates do
  begin
    Entry := TJSONObject.Create;
    Entry.AddPair('id', TJSONNumber.Create(Item.Id));
    Entry.AddPair('name', Item.Name);
    if Item.Kind = TExtractCandidateKind.Property_ then
    begin
      Entry.AddPair('kind', 'property');
    end
    else
    begin
      Entry.AddPair('kind', 'method');
    end;
    Entry.AddPair('display', Item.Display);
    Entry.AddPair('visibility', VisibilityText(Item.Visibility));
    Entry.AddPair('checked', TJSONBool.Create(Item.Checked));
    Entry.AddPair('enabled', TJSONBool.Create(Item.Enabled));
    Entry.AddPair('reason', Item.Reason);
    List.AddElement(Entry);
  end;
  Result.AddPair('candidates', List);
  Notes := TJSONArray.Create;
  for Note in Info.Notes do
  begin
    Notes.Add(Note);
  end;
  Result.AddPair('notes', Notes);
  Units := TJSONArray.Create;
  if AContext.HasProject then
  begin
    for ProjectUnit in AContext.Project.Units do
    begin
      Units.Add(ProjectUnit.Name);
    end;
  end;
  Result.AddPair('units', Units);
end;

function ReadRequestJson(ARequest: TJSONValue; out AName, AUnit: string): TArray<Integer>;
var
  Item: TJSONValue;
  Members: TJSONValue;
begin
  if not (ARequest is TJSONObject) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      cTexts[TLspExtractInterfaceText.RequestWithNameUnitAnd].Text);
  end;
  AName := '';
  AUnit := '';
  if TJSONObject(ARequest).GetValue('name') <> nil then
  begin
    AName := Trim(TJSONObject(ARequest).GetValue('name').Value);
  end;
  if TJSONObject(ARequest).GetValue('unit') <> nil then
  begin
    AUnit := Trim(TJSONObject(ARequest).GetValue('unit').Value);
  end;
  Result := nil;
  Members := TJSONObject(ARequest).GetValue('members');
  if Members is TJSONArray then
  begin
    for Item in TJSONArray(Members) do
    begin
      if Item is TJSONNumber then
      begin
        Result := Result + [TJSONNumber(Item).AsInt];
      end;
    end;
  end;
end;

/// <summary>Datei der Unit AUnitName aus Projekt oder Index; '' ohne.</summary>
function UnitFile(const AContext: TExtractInterfaceContext; const AUnitName: string): string;
var
  ProjectUnit: TProjectUnit;
  UnitIndex: TUnitIndex;
begin
  if AContext.HasProject then
  begin
    for ProjectUnit in AContext.Project.Units do
    begin
      if SameText(ProjectUnit.Name, AUnitName) and (ProjectUnit.FileName <> '') then
      begin
        Exit(ProjectUnit.FileName);
      end;
    end;
  end;
  if (AContext.Index <> nil) and AContext.Index.FindUnit(AUnitName, UnitIndex) and (UnitIndex.FileName <> '') then
  begin
    Exit(UnitIndex.FileName);
  end;
  Result := '';
end;

/// <summary>Fehlerfrei parsen wie vorher (ABefore Meldungen); sonst EJsonRpcError mit der ersten Meldung.</summary>
procedure CheckParses(const AFileName, ANewText: string; ABefore: Integer);
var
  mCheck: TSyntaxTree;
begin
  mCheck := TSyntaxTreeCache.Parse(ANewText);
  try
    if Length(mCheck.Diagnostics) > ABefore then
    begin
      raise Failed(cTexts[TLspExtractInterfaceText.AfterTheChangeNoLonger].Fmt([ExtractFileName(AFileName),
        mCheck.Diagnostics[0].StartPos.Line + 1, mCheck.Diagnostics[0].Message]));
    end;
  finally
    mCheck.Free;
  end;
end;

/// <summary>Units aus AUnits, die ATree noch nicht einbindet.</summary>
function MissingUses(ATree: TSyntaxTree; const AUnits: TArray<string>): TArray<string>;
var
  mUnit: string;
begin
  Result := nil;
  for mUnit in AUnits do
  begin
    if not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(ATree.Tokens), mUnit, nil) then
    begin
      Result := Result + [mUnit];
    end;
  end;
end;

type
  /// <summary>Ein Lauf von atlas.server.extractInterface: Plan, Units der Signaturen, Änderungen je Datei.</summary>
  TInterfaceExtraction = class
  private
    FTree: TSyntaxTree;
    FFileName: string;
    FText: string;
    FPosition: TTextPosition;
    FContext: TExtractInterfaceContext;
    FRequest: TExtractInterfaceRequest;
    FUnitName: string;
    FOwnUnit: string;
    FLineBreak: string;
    FPlan: TExtractInterfacePlan;
    FNeeded: TArray<string>;
    FChanges: TWorkspaceChanges;
    FClassEdits: TArray<TTextEdit>;
    FTargetFile: string;
    FIsNew: Boolean;
    function Resolves(const AName: string): Boolean;
    procedure MakePlan;
    procedure AddNeeded(const ATypeName: string; const AMeaning: TMoveClassMeaning; var ANeedsOwn: Boolean);
    procedure CollectNeeded;
    procedure InsertIntoTarget;
    procedure PlaceInterface;
    function Answer: TJSONObject;
  public
    constructor Create(ATree: TSyntaxTree; const AFileName, AText: string; const APosition: TTextPosition;
      const AContext: TExtractInterfaceContext);
    destructor Destroy; override;
    procedure ReadRequest(ARequest: TJSONValue);
    function Run: TJSONObject;
  end;

constructor TInterfaceExtraction.Create(ATree: TSyntaxTree; const AFileName, AText: string;
  const APosition: TTextPosition; const AContext: TExtractInterfaceContext);
begin
  inherited Create;
  FTree := ATree;
  FFileName := AFileName;
  FText := AText;
  FPosition := APosition;
  FContext := AContext;
  FOwnUnit := TUsesClauses.OwnName(ATree.Tokens);
  FLineBreak := TTextLines.LineBreakOf(AText);
  FChanges := TWorkspaceChanges.Create;
end;

destructor TInterfaceExtraction.Destroy;
begin
  FChanges.Free;
  inherited;
end;

procedure TInterfaceExtraction.ReadRequest(ARequest: TJSONValue);
var
  mName: string;
begin
  FRequest := Default(TExtractInterfaceRequest);
  FRequest.Members := ReadRequestJson(ARequest, mName, FUnitName);
  FRequest.Name := mName;
  FRequest.Guid := FContext.Guid;
  if FRequest.Guid = '' then
  begin
    FRequest.Guid := TGUID.NewGuid.ToString;
  end;
  FRequest.SameUnit := (FUnitName = '') or SameText(FUnitName, FOwnUnit);
  if not FRequest.SameUnit and not IsIdentifier(StringReplace(FUnitName, '.', '_', [rfReplaceAll])) then
  begin
    raise Failed(cTexts[TLspExtractInterfaceText.IsNotAValidUnit].Fmt([FUnitName]));
  end;
end;

function TInterfaceExtraction.Resolves(const AName: string): Boolean;
var
  mResolved: TResolvedSymbol;
begin
  mResolved := FContext.Resolver.ResolveChain(FTree, FFileName, [AName],
    TExtractInterface.ClassAt(FTree, FPosition.Line).StartOffset);
  Result := mResolved.Kind in [TResolvedKind.Symbol, TResolvedKind.UnitName];
end;

procedure TInterfaceExtraction.MakePlan;
var
  mSelf: TInterfaceExtraction;
  mReason: string;
begin
  mSelf := Self;
  if not TExtractInterface.Plan(TClassSource.Create(FTree, FText, FPosition.Line), FRequest,
    TExtractInterfaceLookups.Create(TLspExtractInterface.AncestorsLookup(FTree, FContext.Index),
    function(const AName: string): Boolean
    begin
      Result := mSelf.Resolves(AName);
    end, MethodPointer(FContext.Index)), FPlan, mReason) then
  begin
    raise Failed(mReason);
  end;
end;

procedure TInterfaceExtraction.AddNeeded(const ATypeName: string; const AMeaning: TMoveClassMeaning;
  var ANeedsOwn: Boolean);
begin
  if not AMeaning.Found or AMeaning.IsLocal or (AMeaning.UnitName = '') or SameText(AMeaning.UnitName, 'System') or
    SameText(AMeaning.UnitName, FUnitName) then
  begin
    Exit;
  end;
  if not SameText(AMeaning.UnitName, FOwnUnit) then
  begin
    if IndexText(AMeaning.UnitName, FNeeded) < 0 then
    begin
      FNeeded := FNeeded + [AMeaning.UnitName];
    end;
    Exit;
  end;
  if FPlan.InInterface then
  begin
    raise Failed(cTexts[TLspExtractInterfaceText.ComesFromWhichWouldHave].Fmt([ATypeName, FOwnUnit, FUnitName]));
  end;
  ANeedsOwn := True;
end;

procedure TInterfaceExtraction.CollectNeeded;
var
  mLookup: TMoveClassLookup;
  mTypeName: string;
  mNeedsOwn: Boolean;
begin
  // Units der Typen in den Signaturen (nur für eine andere Ziel-Unit).
  FNeeded := nil;
  if FRequest.SameUnit then
  begin
    Exit;
  end;
  mNeedsOwn := False;
  mLookup := TLspMoveClass.Lookup(FContext.Resolver);
  for mTypeName in FPlan.TypeNames do
  begin
    AddNeeded(mTypeName, mLookup(FTree, FFileName, [mTypeName], FPlan.ClassOffset), mNeedsOwn);
  end;
  if mNeedsOwn then
  begin
    FNeeded := FNeeded + [FOwnUnit];
  end;
end;

procedure TInterfaceExtraction.InsertIntoTarget;
var
  mTargetText, mNewText: string;
  mTargetTree: TSyntaxTree;
  mEdit: TTextEdit;
  mEdits: TArray<TTextEdit>;
  mTargetUses: TArray<string>;
begin
  if not (Assigned(FContext.ReadText) and FContext.ReadText(FTargetFile, mTargetText)) then
  begin
    raise Failed(cTexts[TLspExtractInterfaceText.CannotBeRead].Fmt([ExtractFileName(FTargetFile)]));
  end;
  mTargetTree := TSyntaxTreeCache.Parse(mTargetText);
  try
    if TClassLayout.DeclNamed(mTargetTree, FRequest.Name) <> nil then
    begin
      raise Failed(cTexts[TLspExtractInterfaceText.TheNameIsAlreadyTaken].Fmt([FRequest.Name, FUnitName]));
    end;
    if not TExtractInterface.InsertIntoUnit(mTargetTree, mTargetText, FPlan.Declaration, mEdit) then
    begin
      raise Failed(cTexts[TLspExtractInterfaceText.HasNoInterfacePart].Fmt([FUnitName]));
    end;
    // Fehlende uses der Ziel-Unit in einem Schritt (eine Einfügung), dann das Interface.
    mTargetUses := MissingUses(mTargetTree, FNeeded);
    mEdits := [mEdit];
    if (mTargetUses <> nil) and TUsesClauses.AddUnit(mTargetTree.Tokens, 0, string.Join(', ', mTargetUses),
      TTextLines.LineBreakOf(mTargetText), mEdit) then
    begin
      mEdits := mEdits + [mEdit];
    end;
    mNewText := TTextChanges.Apply(mTargetText, mEdits);
    CheckParses(FTargetFile, mNewText, Length(mTargetTree.Diagnostics));
    FChanges.Add(FTargetFile, TTextChanges.Diff(mTargetText, mNewText));
  finally
    mTargetTree.Free;
  end;
end;

procedure TInterfaceExtraction.PlaceInterface;
var
  mEdit: TTextEdit;
begin
  FClassEdits := FPlan.Edits;
  FTargetFile := FFileName;
  FIsNew := False;
  if FRequest.SameUnit then
  begin
    Exit;
  end;
  // Die Unit der Klasse bindet die Ziel-Unit ein (im Abschnitt der Klasse).
  if not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(FTree.Tokens), FUnitName, nil) and
    TUsesClauses.AddUnit(FTree.Tokens, FPlan.ClassOffset, FUnitName, FLineBreak, mEdit) then
  begin
    FClassEdits := FClassEdits + [mEdit];
  end;
  FTargetFile := UnitFile(FContext, FUnitName);
  FIsNew := FTargetFile = '';
  if not FIsNew then
  begin
    InsertIntoTarget;
    Exit;
  end;
  FTargetFile := TProjectPaths.Combine(TProjectPaths.DirectoryOf(FFileName), FUnitName + '.pas');
  if Assigned(FContext.Exists) and FContext.Exists(FTargetFile) then
  begin
    raise Failed(cTexts[TLspExtractInterfaceText.AlreadyExistsButDoesNot].Fmt([ExtractFileName(FTargetFile)]));
  end;
  FChanges.CreateFile(FTargetFile, TExtractInterface.NewUnitText(FUnitName, FPlan.Declaration, FNeeded, FLineBreak));
end;

function TInterfaceExtraction.Answer: TJSONObject;
var
  mCount: Integer;
  mDescription: string;
begin
  mCount := Length(FPlan.Methods);
  mDescription := cTexts[TLspExtractInterfaceText.WithMethodsFiles].Fmt([FRequest.Name, mCount, FChanges.FileCount]);
  Result := TJSONObject.Create;
  Result.AddPair('edit', FChanges.ToJson(TLspExtractInterface.AnnotationId,
    cTexts[TLspExtractInterfaceText.ExtractInterface2].Text, mDescription));
  Result.AddPair('warnings', FChanges.WarningsJson);
  Result.AddPair('file', TDocumentUris.FromPath(FTargetFile));
  Result.AddPair('name', FRequest.Name);
  Result.AddPair('methods', TJSONNumber.Create(mCount));
end;

function TInterfaceExtraction.Run: TJSONObject;
var
  mWarning: string;
begin
  FContext.Resolver.PinTree(FTree, FFileName);
  try
    MakePlan;
    CollectNeeded;
  finally
    FContext.Resolver.UnpinTree;
  end;
  for mWarning in FPlan.Warnings do
  begin
    FChanges.Warn(mWarning);
  end;
  PlaceInterface;
  // Die Unit der Klasse muss weiter fehlerfrei parsen.
  CheckParses(FFileName, TTextChanges.Apply(FText, FClassEdits), Length(FTree.Diagnostics));
  FChanges.Add(FFileName, FClassEdits);
  if FIsNew then
  begin
    FChanges.RegisterUnit(FContext.HasProject, FContext.Project, FContext.ReadText, FTargetFile, FUnitName);
  end;
  Result := Answer;
end;

class function TLspExtractInterface.Execute(ATree: TSyntaxTree; const AFileName, AText: string;
  const APosition: TTextPosition; ARequest: TJSONValue; const AContext: TExtractInterfaceContext): TJSONObject;
var
  mExtraction: TInterfaceExtraction;
begin
  mExtraction := TInterfaceExtraction.Create(ATree, AFileName, AText, APosition, AContext);
  try
    mExtraction.ReadRequest(ARequest);
    Result := mExtraction.Run;
  finally
    mExtraction.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.ExtractInterface', cTexts);

end.
