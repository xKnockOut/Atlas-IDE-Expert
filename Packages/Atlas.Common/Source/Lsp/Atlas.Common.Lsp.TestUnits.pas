unit Atlas.Common.Lsp.TestUnits;

// Testunits über das Protokoll (#274, #189):
//   - Code-Aktion „DUnitX-Testunit für TFoo anlegen“ auf einer Klasse: ein
//     WorkspaceEdit mit documentChanges legt <Unit>.Tests.pas an (Muster
//     "testUnits.pattern") und trägt sie in uses der .dpr und als
//     DCCReference in die .dproj des Testprojekts ein; danach öffnet der
//     Client sie (Befehl atlas.openFile).
//   - Code-Aktion „Zur Testunit wechseln“ bzw. „Zur Unit wechseln“, wenn das
//     Gegenstück existiert.
//   - Code-Aktion „Testfall für TFoo.Bar anlegen“ an einer Methode oder Routine
//     (#1226): Entwurf mit Aufruf und Platzhalter-Prüfungen in der Testunit;
//     fehlt sie, entsteht sie wie oben mit dem Entwurf statt Assert.Fail.
//   - Befehl atlas.server.testUnit [uri, zeile?]: Gegenstück der Unit für den
//     Befehl „Zwischen Unit und Testunit wechseln“ und die Code Lens des
//     Plugins, samt Edit zum Anlegen, wenn es fehlt.
// Testprojekt, Index und Dateien liefert TTestUnitContextProvider; die Logik
// der Namen und des Gerüsts liegt in Atlas.Common.Editing.TestUnits.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.TestUnits,
  Atlas.Common.Editing.TestDrafts;

type
  /// <summary>Datei zu einem Unit-Namen (Index, Suchpfad); '' wenn unbekannt.</summary>
  TTestUnitFindFunc = reference to function(const AUnitName: string): string;
  /// <summary>Gibt es die Datei (auf der Platte oder als offenes Dokument)?</summary>
  TTestUnitExistsFunc = reference to function(const AFileName: string): Boolean;

  TTestUnitContext = record
    Settings: TTestUnitSettings;
    /// <summary>Wurzel des Arbeitsbereichs; Bezug für testUnits.folder.</summary>
    Root: string;
    /// <summary>Testprogramm (.dpr); '' wenn keins gefunden.</summary>
    TestProgram: string;
    FindUnit: TTestUnitFindFunc;
    ReadText: TTestUnitReadText;
    Exists: TTestUnitExistsFunc;
  end;

  TTestUnitContextProvider = reference to function(const AUri: string; out AContext: TTestUnitContext): Boolean;

  /// <summary>Gegenstück einer Unit: Testunit zur Unit oder Unit zur Testunit.</summary>
  TTestUnitTarget = record
    /// <summary>Name der Unit; '' wenn die Datei keine Unit ist (Programm, Package).</summary>
    UnitName: string;
    FileName: string;
    /// <summary>Die Unit ist eine Testunit (DUnitX/DUnit und Name nach dem Muster).</summary>
    IsTest: Boolean;
    /// <summary>Name des Gegenstücks.</summary>
    Counterpart: string;
    /// <summary>Datei des Gegenstücks; '' wenn es fehlt.</summary>
    CounterpartFile: string;
    /// <summary>Testunit fehlt und lässt sich anlegen.</summary>
    CanCreate: Boolean;
    /// <summary>Datei der neuen Testunit.</summary>
    NewFile: string;
    /// <summary>Klasse für das Gerüst: an der Zeile, sonst die erste; '' = Routinen der Unit.</summary>
    ClassName: string;
    /// <summary>Die Klasse steht an der abgefragten Zeile (für die Code-Aktion auf einer Klasse).</summary>
    ClassAtLine: Boolean;
    /// <summary>Warum es kein Gegenstück gibt und keins angelegt wird; sonst ''.</summary>
    Reason: string;
    /// <summary>Index der Unit (für das Gerüst).</summary>
    Source: TUnitIndex;
  end;

  /// <summary>Ort eines Testfall-Entwurfs (#1226, #1873): Umfeld, Gegenstück der Unit und Entwurf.</summary>
  TTestDraftPlace = record
    Context: TTestUnitContext;
    Target: TTestUnitTarget;
    Draft: TTestDraft;
  end;

  TLspTestUnits = class
  public const
    cCommand = 'atlas.server.testUnit';
    /// <summary>Befehl des Clients: Datei öffnen (Argument: URI).</summary>
    cOpenFileCommand = 'atlas.openFile';
  private
    FStore: IDocumentStore;
    FContextFor: TTestUnitContextProvider;
    function ResolveUri(const AUri: string; ALine: Integer; const AContext: TTestUnitContext): TTestUnitTarget;
    function SourceOf(const AUri: string; const AContext: TTestUnitContext; out AText: string;
      out ATokens: TArray<TPascalToken>): Boolean;
    function TextOf(const AFileName: string; const AContext: TTestUnitContext): string;
    function PlaceFor(const AUri: string; ALine: Integer; const AContext: TTestUnitContext;
      const ATarget: TTestUnitTarget; out APlace: TTestDraftPlace): Boolean;
    function DraftAction(const AUri: string; ALine: Integer; const AContext: TTestUnitContext;
      const ATarget: TTestUnitTarget): TJSONObject;
  public
    constructor Create(const AStore: IDocumentStore; const AContextFor: TTestUnitContextProvider);
    /// <summary>Gegenstück der Unit AFileName mit Text AText; ALine 0-basiert, -1 = ohne Zeile.</summary>
    class function Resolve(const AFileName, AText: string; ALine: Integer;
      const AContext: TTestUnitContext): TTestUnitTarget; overload; static;
    /// <summary>Wie oben mit fertigen Token und fertigem Index der Unit (aus dem Syntaxbaum des offenen
    /// Dokuments; große Units nicht je Code-Aktion neu zerlegen).</summary>
    class function Resolve(const AFileName: string; const ATokens: TArray<TPascalToken>; const ASource: TUnitIndex;
      ALine: Integer;
      const AContext: TTestUnitContext): TTestUnitTarget; overload; static;
    /// <summary>Ordner für neue Testunits: testUnits.folder unter der Wurzel, sonst der des Testprogramms.</summary>
    class function TestFolder(const AContext: TTestUnitContext): string; static;
    /// <summary>WorkspaceEdit, das die Testunit anlegt und ins Testprojekt einträgt. Der Aufrufer
    /// übernimmt das Objekt; nil, wenn ATarget nichts anzulegen hat.</summary>
    class function CreateEdit(const ATarget: TTestUnitTarget; const AContext: TTestUnitContext): TJSONObject;
      overload; static;
    /// <summary>Wie oben; ADrafts ersetzen gleichnamige Tests des Gerüsts bzw. kommen dazu (#1226).</summary>
    class function CreateEdit(const ATarget: TTestUnitTarget; const AContext: TTestUnitContext;
      const ADrafts: TArray<TTestUnitMethod>): TJSONObject; overload; static;
    /// <summary>Entwurf für die Methode oder Routine an ALine (0-basiert) von AUri samt Umfeld und Testunit;
    /// False ohne testbare Methode, in einer Testunit oder ohne Testunit, die es gibt oder die sich anlegen lässt.
    /// </summary>
    function DraftPlace(const AUri: string; ALine: Integer; out APlace: TTestDraftPlace): Boolean;
    /// <summary>WorkspaceEdit, das APlace.Draft in die Testunit einträgt bzw. sie damit anlegt; nil, wenn das
    /// nicht geht. AFile: die Testunit; AName: der eingetragene Testname. Der Aufrufer übernimmt das Objekt.
    /// </summary>
    function DraftEdit(const APlace: TTestDraftPlace; out AFile, AName: string): TJSONObject;
    /// <summary>Code-Aktionen zu AUri an ALine. Der Aufrufer übernimmt die Objekte.</summary>
    function Actions(const AUri: string; ALine: Integer): TArray<TJSONObject>;
    /// <summary>atlas.server.testUnit [uri, zeile?]: Gegenstück als Objekt (unit, isTest,
    /// counterpart, uri, canCreate, newUri, reason, edit).</summary>
    function Execute(const AArguments: TJSONArray): TJSONValue;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Profiles,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.TreeUnits,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.UnitTemplates,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TLspTestUnitsText = (UnitNotFound, NoTestProjectFoundDUnitX, SwitchToUnit, SwitchToTestUnit, CreateADUnitXTestUnit,
    NeedsTheURIOfThe, FileBelongsToNoWorkspace, HasNeitherClassesNorRoutines, CreateTestCase);

const
  cTexts: array[TLspTestUnitsText] of TAtlasText = (
    (De: 'Unit %s nicht gefunden'; En: 'Unit %s not found'),
    (De: 'Kein Testprojekt gefunden (DUnitX oder DUnit im Arbeitsbereich); „testUnits.project“ in atlas.json ' +
      'festlegen';
     En: 'No test project found (DUnitX or DUnit in the workspace); set “testUnits.project” in atlas.json'),
    (De: 'Zur Unit %s wechseln'; En: 'Switch to unit %s'),
    (De: 'Zur Testunit %s wechseln'; En: 'Switch to test unit %s'),
    (De: 'DUnitX-Testunit für %s anlegen'; En: 'Create a DUnitX test unit for %s'),
    (De: ' braucht die URI der Unit'; En: ' needs the URI of the unit'),
    (De: 'Datei gehört zu keinem Arbeitsbereich'; En: 'File belongs to no workspace'),
    (De: '%s hat weder Klassen noch Routinen im interface';
     En: '%s has neither classes nor routines in the interface'),
    (De: 'Testfall für %s anlegen'; En: 'Create a test case for %s'));

{$SCOPEDENUMS OFF}

const
  cLineBreak = #13#10;

{ TLspTestUnits }

constructor TLspTestUnits.Create(const AStore: IDocumentStore; const AContextFor: TTestUnitContextProvider);
begin
  inherited Create;
  FStore := AStore;
  FContextFor := AContextFor;
end;

class function TLspTestUnits.TestFolder(const AContext: TTestUnitContext): string;
var
  mFolder: string;
begin
  if AContext.Settings.Folder <> '' then
  begin
    mFolder := StringReplace(StringReplace(AContext.Settings.Folder, '/', PathDelim, [rfReplaceAll]), '\', PathDelim,
      [rfReplaceAll]);
    if (Pos(':', mFolder) > 0) or mFolder.StartsWith(PathDelim) then
    begin
      Result := IncludeTrailingPathDelimiter(mFolder);
    end
    else
    begin
      Result := IncludeTrailingPathDelimiter(IncludeTrailingPathDelimiter(AContext.Root) + mFolder);
    end;
  end
  else if AContext.TestProgram <> '' then
  begin
    Result := ExtractFilePath(AContext.TestProgram);
  end
  else
  begin
    Result := '';
  end;
end;

function IsUnitText(const ATokens: TArray<TPascalToken>): Boolean;
var
  mToken: TPascalToken;
begin
  Result := False;
  for mToken in ATokens do
  begin
    if mToken.Kind = TPascalTokenKind.Keyword then
    begin
      Exit(mToken.IsKeyword('unit'));
    end;
  end;
end;

class function TLspTestUnits.Resolve(const AFileName, AText: string; ALine: Integer;
  const AContext: TTestUnitContext): TTestUnitTarget;
begin
  Result := Resolve(AFileName, TPascalLexer.Tokenize(AText), TIndexExtractor.ExtractText(AText, AFileName, nil), ALine,
    AContext);
end;

/// <summary>Zu prüfende Unit ATested einer Testunit eintragen.</summary>
procedure SetTested(var ATarget: TTestUnitTarget; const ATested: string; const AContext: TTestUnitContext);
begin
  ATarget.IsTest := True;
  ATarget.Counterpart := ATested;
  if Assigned(AContext.FindUnit) then
  begin
    ATarget.CounterpartFile := AContext.FindUnit(ATested);
  end;
  if ATarget.CounterpartFile = '' then
  begin
    ATarget.Reason := cTexts[TLspTestUnitsText.UnitNotFound].Fmt([ATested]);
  end;
end;

/// <summary>Datei der Testunit im Projekt oder im Testordner AFolder.</summary>
procedure FindTestFile(var ATarget: TTestUnitTarget; const AContext: TTestUnitContext; const AFolder: string);
begin
  if Assigned(AContext.FindUnit) then
  begin
    ATarget.CounterpartFile := AContext.FindUnit(ATarget.Counterpart);
  end;
  if (ATarget.CounterpartFile = '') and (AFolder <> '') and Assigned(AContext.Exists) and
    AContext.Exists(AFolder + ATarget.Counterpart + '.pas') then
  begin
    ATarget.CounterpartFile := AFolder + ATarget.Counterpart + '.pas';
  end;
end;

/// <summary>Ob und wo eine neue Testunit entstehen kann; sonst der Grund.</summary>
procedure PlanTestUnit(var ATarget: TTestUnitTarget; ALine: Integer; const AContext: TTestUnitContext;
  const AFolder: string);
begin
  if ALine >= 0 then
  begin
    ATarget.ClassName := TTestUnits.ClassAt(ATarget.Source, ALine);
  end;
  ATarget.ClassAtLine := ATarget.ClassName <> '';
  if ATarget.ClassName = '' then
  begin
    ATarget.ClassName := TTestUnits.FirstClass(ATarget.Source);
  end;
  if AContext.TestProgram = '' then
  begin
    ATarget.Reason := cTexts[TLspTestUnitsText.NoTestProjectFoundDUnitX].Text;
  end
  else if (ATarget.ClassName = '') and (Length(TTestUnits.TestMethods(ATarget.Source, '')) = 0) then
  begin
    ATarget.Reason := cTexts[TLspTestUnitsText.HasNeitherClassesNorRoutines].Fmt([ATarget.UnitName]);
  end
  else
  begin
    ATarget.CanCreate := True;
    ATarget.NewFile := AFolder + ATarget.Counterpart + '.pas';
  end;
end;

class function TLspTestUnits.Resolve(const AFileName: string; const ATokens: TArray<TPascalToken>;
  const ASource: TUnitIndex; ALine: Integer; const AContext: TTestUnitContext): TTestUnitTarget;
var
  mTested, mFolder: string;
begin
  Result := Default(TTestUnitTarget);
  Result.FileName := AFileName;
  if not IsUnitText(ATokens) then
  begin
    Exit;
  end;
  Result.Source := ASource;
  Result.UnitName := Result.Source.UnitName;
  if Result.UnitName = '' then
  begin
    Result.UnitName := ChangeFileExt(ExtractFileName(AFileName), '');
  end;
  if TTestUnits.TestedUnitName(Result.UnitName, AContext.Settings.Pattern, mTested) and
    TRuleProfiles.IsTestUnit(ATokens) then
  begin
    SetTested(Result, mTested, AContext);
    Exit;
  end;
  Result.Counterpart := TTestUnits.TestUnitName(Result.UnitName, AContext.Settings.Pattern);
  mFolder := TestFolder(AContext);
  FindTestFile(Result, AContext, mFolder);
  if Result.CounterpartFile = '' then
  begin
    PlanTestUnit(Result, ALine, AContext, mFolder);
  end;
end;

function DocumentEdit(const AUri: string; const AEdits: TArray<TRuleEdit>): TJSONObject;
var
  mDocument, mItem: TJSONObject;
  mEdits: TJSONArray;
  mEdit: TRuleEdit;
begin
  mDocument := TJSONObject.Create;
  mDocument.AddPair('uri', AUri);
  mDocument.AddPair('version', TJSONNull.Create);
  mEdits := TJSONArray.Create;
  for mEdit in AEdits do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('range', TLspPositions.RangeToJson(mEdit.Range));
    mItem.AddPair('newText', mEdit.NewText);
    mEdits.AddElement(mItem);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', mDocument);
  Result.AddPair('edits', mEdits);
end;

class function TLspTestUnits.CreateEdit(const ATarget: TTestUnitTarget;
  const AContext: TTestUnitContext): TJSONObject;
begin
  Result := CreateEdit(ATarget, AContext, nil);
end;

class function TLspTestUnits.CreateEdit(const ATarget: TTestUnitTarget; const AContext: TTestUnitContext;
  const ADrafts: TArray<TTestUnitMethod>): TJSONObject;
var
  mChanges: TJSONArray;
  mCreation, mOptions: TJSONObject;
  mNewUri, mRelative, mProjectFile, mText: string;
  mEdit: TRuleEdit;
begin
  if not ATarget.CanCreate then
  begin
    Exit(nil);
  end;
  mNewUri := TDocumentUris.FromPath(ATarget.NewFile);
  mChanges := TJSONArray.Create;
  mCreation := TJSONObject.Create;
  mCreation.AddPair('kind', 'create');
  mCreation.AddPair('uri', mNewUri);
  mOptions := TJSONObject.Create;
  mOptions.AddPair('ignoreIfExists', TJSONBool.Create(False));
  mCreation.AddPair('options', mOptions);
  mChanges.AddElement(mCreation);
  mChanges.AddElement(DocumentEdit(mNewUri, [TRuleEdit.Create(TTextRange.Create(0, 0, 0, 0),
    TTestUnits.UnitText(ATarget.Counterpart, ATarget.Source, ATarget.ClassName, cLineBreak, ADrafts))]));
  // Ins Testprojekt: uses der .dpr und DCCReference der .dproj, jeweils mit relativem Pfad.
  mRelative := TTestUnits.RelativePath(ExtractFilePath(AContext.TestProgram), ATarget.NewFile);
  mText := AContext.ReadText(AContext.TestProgram);
  if TUnitTemplates.UnitProgramEdit(mText, ATarget.Counterpart, mRelative, mEdit) then
  begin
    mChanges.AddElement(DocumentEdit(TDocumentUris.FromPath(AContext.TestProgram), [mEdit]));
  end;
  mProjectFile := ChangeFileExt(AContext.TestProgram, '.dproj');
  if AContext.Exists(mProjectFile) then
  begin
    mText := AContext.ReadText(mProjectFile);
    if (Pos('"' + mRelative + '"', mText) = 0) and
      TUnitTemplates.ProjectEdit(mText, mRelative, '', TFormKind.Form, False, mEdit) then
    begin
      mChanges.AddElement(DocumentEdit(TDocumentUris.FromPath(mProjectFile), [mEdit]));
    end;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('documentChanges', mChanges);
end;

function TLspTestUnits.ResolveUri(const AUri: string; ALine: Integer;
  const AContext: TTestUnitContext): TTestUnitTarget;
var
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
  mFileName: string;
begin
  mFileName := TDocumentUris.ToPath(AUri);
  // Offenes Dokument: Index aus dem geteilten Syntaxbaum, ohne erneut zu parsen.
  if FStore.TryGet(AUri, mDocument) then
  begin
    mShared := TSyntaxTreeCache.Get(mDocument);
    Result := Resolve(mFileName, mShared.Tree.Tokens, TTreeExtracts.ForTree(mShared.Tree).Extracted(mFileName), ALine,
      AContext);
  end
  else
  begin
    Result := Resolve(mFileName, AContext.ReadText(mFileName), ALine, AContext);
  end;
end;

function TLspTestUnits.SourceOf(const AUri: string; const AContext: TTestUnitContext; out AText: string;
  out ATokens: TArray<TPascalToken>): Boolean;
var
  mDocument: ITextDocument;
begin
  if FStore.TryGet(AUri, mDocument) then
  begin
    AText := mDocument.Text;
    ATokens := TSyntaxTreeCache.Get(mDocument).Tree.Tokens;
  end
  else
  begin
    AText := AContext.ReadText(TDocumentUris.ToPath(AUri));
    ATokens := TPascalLexer.Tokenize(AText);
  end;
  Result := AText <> '';
end;

function TLspTestUnits.TextOf(const AFileName: string; const AContext: TTestUnitContext): string;
var
  mDocument: ITextDocument;
begin
  // Offene Testunit: ungespeicherte Änderungen zählen.
  if FStore.TryGet(TDocumentUris.FromPath(AFileName), mDocument) then
  begin
    Result := mDocument.Text;
  end
  else
  begin
    Result := AContext.ReadText(AFileName);
  end;
end;

/// <summary>WorkspaceEdit mit zeilenweisen Änderungen von AOld nach ANew in AFileName.</summary>
function ChangeEdit(const AFileName, AOld, ANew: string): TJSONObject;
var
  mChanges: TJSONArray;
begin
  mChanges := TJSONArray.Create;
  mChanges.AddElement(DocumentEdit(TDocumentUris.FromPath(AFileName), TTextChanges.Diff(AOld, ANew)));
  Result := TJSONObject.Create;
  Result.AddPair('documentChanges', mChanges);
end;

function CommandJson(const ATitle, ACommand, AArgument: string): TJSONObject;
var
  mArguments: TJSONArray;
begin
  mArguments := TJSONArray.Create;
  mArguments.Add(AArgument);
  Result := TJSONObject.Create;
  Result.AddPair('title', ATitle);
  Result.AddPair('command', ACommand);
  Result.AddPair('arguments', mArguments);
end;

/// <summary>Kann zur Unit ATarget ein Testfall entstehen: keine Testunit, Zeile gegeben, Testunit da oder
/// anlegbar?</summary>
function CanDraft(const ATarget: TTestUnitTarget; ALine: Integer): Boolean;
begin
  Result := not ATarget.IsTest and (ALine >= 0);
  if Result then
  begin
    Result := (ATarget.CounterpartFile <> '') or ATarget.CanCreate;
  end;
end;

/// <summary>Edit, das die fehlende Testunit mit dem Entwurf anlegt; nil, wenn die Methode nicht zur Klasse des
/// Gerüsts gehört.</summary>
function NewUnitDraftEdit(const ATarget: TTestUnitTarget; const AContext: TTestUnitContext;
  const ADraft: TTestDraft): TJSONObject;
var
  mDraft: TTestDraft;
  mMethod: TTestUnitMethod;
begin
  // Gerüst wie #274 mit der Klasse der Methode; der Entwurf steht statt Assert.Fail.
  if (ADraft.ClassName <> '') and not SameText(ADraft.ClassName, ATarget.ClassName) then
  begin
    Exit(nil);
  end;
  mDraft := ADraft;
  if not mDraft.ClassMethod and TTestUnits.HasSubject(ATarget.Source, mDraft.ClassName) then
  begin
    mDraft.Subject := 'FSubject';
  end;
  mMethod.Name := mDraft.TestName;
  mMethod.Target := mDraft.Target;
  mMethod.Draft := TTestDrafts.MethodText(mDraft, cLineBreak);
  Result := TLspTestUnits.CreateEdit(ATarget, AContext, [mMethod]);
end;

function TLspTestUnits.PlaceFor(const AUri: string; ALine: Integer; const AContext: TTestUnitContext;
  const ATarget: TTestUnitTarget; out APlace: TTestDraftPlace): Boolean;
var
  mText: string;
  mTokens: TArray<TPascalToken>;
begin
  APlace := Default(TTestDraftPlace);
  APlace.Context := AContext;
  APlace.Target := ATarget;
  Result := CanDraft(ATarget, ALine) and SourceOf(AUri, AContext, mText, mTokens) and
    TTestDrafts.DraftAt(mText, mTokens, ATarget.Source, ALine, APlace.Draft);
  if not Result then
  begin
    Exit;
  end;
  APlace.Draft.Fixture := TTestUnits.FixtureName(APlace.Draft.ClassName, ATarget.UnitName);
  APlace.Draft.UnitName := ATarget.UnitName;
  if not APlace.Draft.ClassMethod and (APlace.Draft.ClassName <> '') then
  begin
    APlace.Draft.CreateText := TTestUnits.CreateExpression(ATarget.Source, APlace.Draft.ClassName);
  end;
end;

function TLspTestUnits.DraftPlace(const AUri: string; ALine: Integer; out APlace: TTestDraftPlace): Boolean;
var
  mContext: TTestUnitContext;
begin
  APlace := Default(TTestDraftPlace);
  Result := Assigned(FContextFor) and FContextFor(AUri, mContext);
  if Result then
  begin
    Result := PlaceFor(AUri, ALine, mContext, ResolveUri(AUri, ALine, mContext), APlace);
  end;
end;

function TLspTestUnits.DraftEdit(const APlace: TTestDraftPlace; out AFile, AName: string): TJSONObject;
var
  mOld, mNew, mReason: string;
begin
  Result := nil;
  AName := APlace.Draft.TestName;
  if APlace.Target.CounterpartFile <> '' then
  begin
    AFile := APlace.Target.CounterpartFile;
    mOld := TextOf(AFile, APlace.Context);
    if TTestDrafts.AddToTestUnit(mOld, APlace.Draft, False, mNew, AName, mReason) then
    begin
      Result := ChangeEdit(AFile, mOld, mNew);
    end;
  end
  else
  begin
    AFile := APlace.Target.NewFile;
    Result := NewUnitDraftEdit(APlace.Target, APlace.Context, APlace.Draft);
  end;
end;

function TLspTestUnits.DraftAction(const AUri: string; ALine: Integer; const AContext: TTestUnitContext;
  const ATarget: TTestUnitTarget): TJSONObject;
var
  mPlace: TTestDraftPlace;
  mEdit: TJSONObject;
  mFile, mName, mTitle: string;
begin
  Result := nil;
  if not PlaceFor(AUri, ALine, AContext, ATarget, mPlace) then
  begin
    Exit;
  end;
  mEdit := DraftEdit(mPlace, mFile, mName);
  if mEdit = nil then
  begin
    Exit;
  end;
  mTitle := cTexts[TLspTestUnitsText.CreateTestCase].Fmt([mPlace.Draft.Target]);
  Result := TJSONObject.Create;
  Result.AddPair('title', mTitle);
  Result.AddPair('kind', cRewriteKind);
  Result.AddPair('edit', mEdit);
  Result.AddPair('command', CommandJson(mTitle, cOpenFileCommand, TDocumentUris.FromPath(mFile)));
end;

function TLspTestUnits.Actions(const AUri: string; ALine: Integer): TArray<TJSONObject>;
var
  mContext: TTestUnitContext;
  mTarget: TTestUnitTarget;
  mAction, mEdit: TJSONObject;
  mTitle, mSubject: string;
begin
  Result := nil;
  if not Assigned(FContextFor) or not FContextFor(AUri, mContext) then
  begin
    Exit;
  end;
  mTarget := ResolveUri(AUri, ALine, mContext);
  if mTarget.UnitName = '' then
  begin
    Exit;
  end;
  mAction := DraftAction(AUri, ALine, mContext, mTarget);
  if mAction <> nil then
  begin
    Result := [mAction];
  end;
  if mTarget.CounterpartFile <> '' then
  begin
    if mTarget.IsTest then
    begin
      mTitle := cTexts[TLspTestUnitsText.SwitchToUnit].Fmt([mTarget.Counterpart]);
    end
    else
    begin
      mTitle := cTexts[TLspTestUnitsText.SwitchToTestUnit].Fmt([mTarget.Counterpart]);
    end;
    mAction := TJSONObject.Create;
    mAction.AddPair('title', mTitle);
    mAction.AddPair('kind', cRewriteKind);
    mAction.AddPair('command', CommandJson(mTitle, cOpenFileCommand, TDocumentUris.FromPath(mTarget.CounterpartFile)));
    Result := Result + [mAction];
    Exit;
  end;
  // Anlegen nur auf einer Klasse (#274) oder in einer Unit ohne Klassen.
  if not mTarget.CanCreate or not (mTarget.ClassAtLine or (mTarget.ClassName = '')) then
  begin
    Exit;
  end;
  mSubject := mTarget.ClassName;
  if mSubject = '' then
  begin
    mSubject := mTarget.UnitName;
  end;
  mTitle := cTexts[TLspTestUnitsText.CreateADUnitXTestUnit].Fmt([mSubject]);
  mEdit := CreateEdit(mTarget, mContext);
  mAction := TJSONObject.Create;
  mAction.AddPair('title', mTitle);
  mAction.AddPair('kind', cRewriteKind);
  mAction.AddPair('edit', mEdit);
  mAction.AddPair('command', CommandJson(mTitle, cOpenFileCommand, TDocumentUris.FromPath(mTarget.NewFile)));
  Result := Result + [mAction];
end;

function TLspTestUnits.Execute(const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mLine: Integer;
  mContext: TTestUnitContext;
  mTarget: TTestUnitTarget;
  mAnswer: TJSONObject;
begin
  if (AArguments = nil) or (AArguments.Count = 0) then
  begin
    raise EArgumentException.Create(cCommand + cTexts[TLspTestUnitsText.NeedsTheURIOfThe].Text);
  end;
  mUri := AArguments.Items[0].Value;
  mLine := -1;
  if AArguments.Count > 1 then
  begin
    mLine := StrToIntDef(AArguments.Items[1].Value, -1);
  end;
  mAnswer := TJSONObject.Create;
  Result := mAnswer;
  if not Assigned(FContextFor) or not FContextFor(mUri, mContext) then
  begin
    mAnswer.AddPair('unit', '');
    mAnswer.AddPair('reason', cTexts[TLspTestUnitsText.FileBelongsToNoWorkspace].Text);
    Exit;
  end;
  mTarget := ResolveUri(mUri, mLine, mContext);
  mAnswer.AddPair('unit', mTarget.UnitName);
  mAnswer.AddPair('isTest', TJSONBool.Create(mTarget.IsTest));
  mAnswer.AddPair('counterpart', mTarget.Counterpart);
  if mTarget.CounterpartFile <> '' then
  begin
    mAnswer.AddPair('uri', TDocumentUris.FromPath(mTarget.CounterpartFile));
  end
  else
  begin
    mAnswer.AddPair('uri', TJSONNull.Create);
  end;
  mAnswer.AddPair('canCreate', TJSONBool.Create(mTarget.CanCreate));
  if mTarget.CanCreate then
  begin
    mAnswer.AddPair('newUri', TDocumentUris.FromPath(mTarget.NewFile));
    mAnswer.AddPair('edit', CreateEdit(mTarget, mContext));
  end;
  mAnswer.AddPair('reason', mTarget.Reason);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.TestUnits', cTexts);

end.
