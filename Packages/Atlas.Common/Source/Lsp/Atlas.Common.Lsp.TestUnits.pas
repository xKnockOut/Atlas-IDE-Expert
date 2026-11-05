unit Atlas.Common.Lsp.TestUnits;

// Testunits über das Protokoll (#274, #189):
//   - Code-Aktion „DUnitX-Testunit für TFoo anlegen“ auf einer Klasse: ein
//     WorkspaceEdit mit documentChanges legt <Unit>.Tests.pas an (Muster
//     "testUnits.pattern") und trägt sie in uses der .dpr und als
//     DCCReference in die .dproj des Testprojekts ein; danach öffnet der
//     Client sie (Befehl atlas.openFile).
//   - Code-Aktion „Zur Testunit wechseln“ bzw. „Zur Unit wechseln“, wenn das
//     Gegenstück existiert.
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
  Atlas.Common.Editing.TestUnits;

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

  TLspTestUnits = class
  public const
    Command = 'atlas.server.testUnit';
    /// <summary>Befehl des Clients: Datei öffnen (Argument: URI).</summary>
    OpenFileCommand = 'atlas.openFile';
  private
    FStore: IDocumentStore;
    FContextFor: TTestUnitContextProvider;
    function ResolveUri(const AUri: string; ALine: Integer; const AContext: TTestUnitContext): TTestUnitTarget;
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
    class function CreateEdit(const ATarget: TTestUnitTarget; const AContext: TTestUnitContext): TJSONObject; static;
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
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TLspTestUnitsText = (UnitNotFound, NoTestProjectFoundDUnitX, SwitchToUnit, SwitchToTestUnit, CreateADUnitXTestUnit,
    NeedsTheURIOfThe, FileBelongsToNoWorkspace, HasNeitherClassesNorRoutines);

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
     En: '%s has neither classes nor routines in the interface'));

{$SCOPEDENUMS OFF}

const
  LineBreak = #13#10;

{ TLspTestUnits }

constructor TLspTestUnits.Create(const AStore: IDocumentStore; const AContextFor: TTestUnitContextProvider);
begin
  inherited Create;
  FStore := AStore;
  FContextFor := AContextFor;
end;

class function TLspTestUnits.TestFolder(const AContext: TTestUnitContext): string;
var
  Folder: string;
begin
  if AContext.Settings.Folder <> '' then
  begin
    Folder := StringReplace(StringReplace(AContext.Settings.Folder, '/', PathDelim, [rfReplaceAll]), '\', PathDelim,
      [rfReplaceAll]);
    if (Pos(':', Folder) > 0) or Folder.StartsWith(PathDelim) then
    begin
      Result := IncludeTrailingPathDelimiter(Folder);
    end
    else
    begin
      Result := IncludeTrailingPathDelimiter(IncludeTrailingPathDelimiter(AContext.Root) + Folder);
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
  Token: TPascalToken;
begin
  Result := False;
  for Token in ATokens do
  begin
    if Token.Kind = TPascalTokenKind.Keyword then
    begin
      Exit(Token.IsKeyword('unit'));
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
  Document, Item: TJSONObject;
  Edits: TJSONArray;
  Edit: TRuleEdit;
begin
  Document := TJSONObject.Create;
  Document.AddPair('uri', AUri);
  Document.AddPair('version', TJSONNull.Create);
  Edits := TJSONArray.Create;
  for Edit in AEdits do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('range', TLspPositions.RangeToJson(Edit.Range));
    Item.AddPair('newText', Edit.NewText);
    Edits.AddElement(Item);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', Document);
  Result.AddPair('edits', Edits);
end;

class function TLspTestUnits.CreateEdit(const ATarget: TTestUnitTarget;
  const AContext: TTestUnitContext): TJSONObject;
var
  Changes: TJSONArray;
  Creation, Options: TJSONObject;
  NewUri, Relative, ProjectFile, Text: string;
  Edit: TRuleEdit;
begin
  if not ATarget.CanCreate then
  begin
    Exit(nil);
  end;
  NewUri := TDocumentUris.FromPath(ATarget.NewFile);
  Changes := TJSONArray.Create;
  Creation := TJSONObject.Create;
  Creation.AddPair('kind', 'create');
  Creation.AddPair('uri', NewUri);
  Options := TJSONObject.Create;
  Options.AddPair('ignoreIfExists', TJSONBool.Create(False));
  Creation.AddPair('options', Options);
  Changes.AddElement(Creation);
  Changes.AddElement(DocumentEdit(NewUri, [TRuleEdit.Create(TTextRange.Create(0, 0, 0, 0),
    TTestUnits.UnitText(ATarget.Counterpart, ATarget.Source, ATarget.ClassName, LineBreak))]));
  // Ins Testprojekt: uses der .dpr und DCCReference der .dproj, jeweils mit relativem Pfad.
  Relative := TTestUnits.RelativePath(ExtractFilePath(AContext.TestProgram), ATarget.NewFile);
  Text := AContext.ReadText(AContext.TestProgram);
  if TUnitTemplates.UnitProgramEdit(Text, ATarget.Counterpart, Relative, Edit) then
  begin
    Changes.AddElement(DocumentEdit(TDocumentUris.FromPath(AContext.TestProgram), [Edit]));
  end;
  ProjectFile := ChangeFileExt(AContext.TestProgram, '.dproj');
  if AContext.Exists(ProjectFile) then
  begin
    Text := AContext.ReadText(ProjectFile);
    if (Pos('"' + Relative + '"', Text) = 0) and
      TUnitTemplates.ProjectEdit(Text, Relative, '', TFormKind.Form, False, Edit) then
    begin
      Changes.AddElement(DocumentEdit(TDocumentUris.FromPath(ProjectFile), [Edit]));
    end;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('documentChanges', Changes);
end;

function TLspTestUnits.ResolveUri(const AUri: string; ALine: Integer;
  const AContext: TTestUnitContext): TTestUnitTarget;
var
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  FileName: string;
begin
  FileName := TDocumentUris.ToPath(AUri);
  // Offenes Dokument: Index aus dem geteilten Syntaxbaum, ohne erneut zu parsen.
  if FStore.TryGet(AUri, Document) then
  begin
    Shared := TSyntaxTreeCache.Get(Document);
    Result := Resolve(FileName, Shared.Tree.Tokens, TTreeExtracts.ForTree(Shared.Tree).Extracted(FileName), ALine,
      AContext);
  end
  else
  begin
    Result := Resolve(FileName, AContext.ReadText(FileName), ALine, AContext);
  end;
end;

function CommandJson(const ATitle, ACommand, AArgument: string): TJSONObject;
var
  Arguments: TJSONArray;
begin
  Arguments := TJSONArray.Create;
  Arguments.Add(AArgument);
  Result := TJSONObject.Create;
  Result.AddPair('title', ATitle);
  Result.AddPair('command', ACommand);
  Result.AddPair('arguments', Arguments);
end;

function TLspTestUnits.Actions(const AUri: string; ALine: Integer): TArray<TJSONObject>;
var
  Context: TTestUnitContext;
  Target: TTestUnitTarget;
  Action, Edit: TJSONObject;
  Title, Subject: string;
begin
  Result := nil;
  if not Assigned(FContextFor) or not FContextFor(AUri, Context) then
  begin
    Exit;
  end;
  Target := ResolveUri(AUri, ALine, Context);
  if Target.UnitName = '' then
  begin
    Exit;
  end;
  if Target.CounterpartFile <> '' then
  begin
    if Target.IsTest then
    begin
      Title := cTexts[TLspTestUnitsText.SwitchToUnit].Fmt([Target.Counterpart]);
    end
    else
    begin
      Title := cTexts[TLspTestUnitsText.SwitchToTestUnit].Fmt([Target.Counterpart]);
    end;
    Action := TJSONObject.Create;
    Action.AddPair('title', Title);
    Action.AddPair('kind', RewriteKind);
    Action.AddPair('command', CommandJson(Title, OpenFileCommand, TDocumentUris.FromPath(Target.CounterpartFile)));
    Result := [Action];
    Exit;
  end;
  // Anlegen nur auf einer Klasse (#274) oder in einer Unit ohne Klassen.
  if not Target.CanCreate or not (Target.ClassAtLine or (Target.ClassName = '')) then
  begin
    Exit;
  end;
  Subject := Target.ClassName;
  if Subject = '' then
  begin
    Subject := Target.UnitName;
  end;
  Title := cTexts[TLspTestUnitsText.CreateADUnitXTestUnit].Fmt([Subject]);
  Edit := CreateEdit(Target, Context);
  Action := TJSONObject.Create;
  Action.AddPair('title', Title);
  Action.AddPair('kind', RewriteKind);
  Action.AddPair('edit', Edit);
  Action.AddPair('command', CommandJson(Title, OpenFileCommand, TDocumentUris.FromPath(Target.NewFile)));
  Result := [Action];
end;

function TLspTestUnits.Execute(const AArguments: TJSONArray): TJSONValue;
var
  Uri: string;
  Line: Integer;
  Context: TTestUnitContext;
  Target: TTestUnitTarget;
  Answer: TJSONObject;
begin
  if (AArguments = nil) or (AArguments.Count = 0) then
  begin
    raise EArgumentException.Create(Command + cTexts[TLspTestUnitsText.NeedsTheURIOfThe].Text);
  end;
  Uri := AArguments.Items[0].Value;
  Line := -1;
  if AArguments.Count > 1 then
  begin
    Line := StrToIntDef(AArguments.Items[1].Value, -1);
  end;
  Answer := TJSONObject.Create;
  Result := Answer;
  if not Assigned(FContextFor) or not FContextFor(Uri, Context) then
  begin
    Answer.AddPair('unit', '');
    Answer.AddPair('reason', cTexts[TLspTestUnitsText.FileBelongsToNoWorkspace].Text);
    Exit;
  end;
  Target := ResolveUri(Uri, Line, Context);
  Answer.AddPair('unit', Target.UnitName);
  Answer.AddPair('isTest', TJSONBool.Create(Target.IsTest));
  Answer.AddPair('counterpart', Target.Counterpart);
  if Target.CounterpartFile <> '' then
  begin
    Answer.AddPair('uri', TDocumentUris.FromPath(Target.CounterpartFile));
  end
  else
  begin
    Answer.AddPair('uri', TJSONNull.Create);
  end;
  Answer.AddPair('canCreate', TJSONBool.Create(Target.CanCreate));
  if Target.CanCreate then
  begin
    Answer.AddPair('newUri', TDocumentUris.FromPath(Target.NewFile));
    Answer.AddPair('edit', CreateEdit(Target, Context));
  end;
  Answer.AddPair('reason', Target.Reason);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.TestUnits', cTexts);

end.
