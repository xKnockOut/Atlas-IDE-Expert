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
    /// <summary>Wie oben mit fertigem Index der Unit (aus dem Syntaxbaum des offenen Dokuments).</summary>
    class function Resolve(const AFileName, AText: string; const ASource: TUnitIndex; ALine: Integer;
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
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.UnitTemplates,
  Atlas.Common.Lsp.Positions;

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
      Result := IncludeTrailingPathDelimiter(Folder)
    else
      Result := IncludeTrailingPathDelimiter(IncludeTrailingPathDelimiter(AContext.Root) + Folder);
  end
  else if AContext.TestProgram <> '' then
    Result := ExtractFilePath(AContext.TestProgram)
  else
    Result := '';
end;

function IsUnitText(const ATokens: TArray<TPascalToken>): Boolean;
var
  Token: TPascalToken;
begin
  Result := False;
  for Token in ATokens do
    if Token.Kind = TPascalTokenKind.Keyword then
      Exit(Token.IsKeyword('unit'));
end;

class function TLspTestUnits.Resolve(const AFileName, AText: string; ALine: Integer;
  const AContext: TTestUnitContext): TTestUnitTarget;
begin
  Result := Resolve(AFileName, AText, TIndexExtractor.ExtractText(AText, AFileName, nil), ALine, AContext);
end;

class function TLspTestUnits.Resolve(const AFileName, AText: string; const ASource: TUnitIndex; ALine: Integer;
  const AContext: TTestUnitContext): TTestUnitTarget;
var
  Tokens: TArray<TPascalToken>;
  Tested, Folder: string;
begin
  Result := Default(TTestUnitTarget);
  Result.FileName := AFileName;
  Tokens := TPascalLexer.Tokenize(AText);
  if not IsUnitText(Tokens) then
    Exit;
  Result.Source := ASource;
  Result.UnitName := Result.Source.UnitName;
  if Result.UnitName = '' then
    Result.UnitName := ChangeFileExt(ExtractFileName(AFileName), '');
  if TTestUnits.TestedUnitName(Result.UnitName, AContext.Settings.Pattern, Tested) and
    TRuleProfiles.IsTestUnit(Tokens) then
  begin
    Result.IsTest := True;
    Result.Counterpart := Tested;
    if Assigned(AContext.FindUnit) then
      Result.CounterpartFile := AContext.FindUnit(Tested);
    if Result.CounterpartFile = '' then
      Result.Reason := Format('Unit %s nicht gefunden', [Tested]);
    Exit;
  end;
  Result.Counterpart := TTestUnits.TestUnitName(Result.UnitName, AContext.Settings.Pattern);
  if Assigned(AContext.FindUnit) then
    Result.CounterpartFile := AContext.FindUnit(Result.Counterpart);
  Folder := TestFolder(AContext);
  if (Result.CounterpartFile = '') and (Folder <> '') and Assigned(AContext.Exists) and
    AContext.Exists(Folder + Result.Counterpart + '.pas') then
    Result.CounterpartFile := Folder + Result.Counterpart + '.pas';
  if Result.CounterpartFile <> '' then
    Exit;
  if ALine >= 0 then
    Result.ClassName := TTestUnits.ClassAt(Result.Source, ALine);
  Result.ClassAtLine := Result.ClassName <> '';
  if Result.ClassName = '' then
    Result.ClassName := TTestUnits.FirstClass(Result.Source);
  if AContext.TestProgram = '' then
    Result.Reason := 'Kein Testprojekt gefunden (DUnitX oder DUnit im Arbeitsbereich); ' +
      '„testUnits.project“ in atlas.json festlegen'
  else if (Result.ClassName = '') and (Length(TTestUnits.TestMethods(Result.Source, '')) = 0) then
    Result.Reason := Format('%s hat weder Klassen noch Routinen im interface', [Result.UnitName])
  else
  begin
    Result.CanCreate := True;
    Result.NewFile := Folder + Result.Counterpart + '.pas';
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
    Exit(nil);
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
    Changes.AddElement(DocumentEdit(TDocumentUris.FromPath(AContext.TestProgram), [Edit]));
  ProjectFile := ChangeFileExt(AContext.TestProgram, '.dproj');
  if AContext.Exists(ProjectFile) then
  begin
    Text := AContext.ReadText(ProjectFile);
    if (Pos('"' + Relative + '"', Text) = 0) and
      TUnitTemplates.ProjectEdit(Text, Relative, '', TFormKind.Form, False, Edit) then
      Changes.AddElement(DocumentEdit(TDocumentUris.FromPath(ProjectFile), [Edit]));
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
    Result := Resolve(FileName, Document.Text, TIndexExtractor.Extract(Shared.Tree, FileName), ALine, AContext);
  end
  else
    Result := Resolve(FileName, AContext.ReadText(FileName), ALine, AContext);
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
    Exit;
  Target := ResolveUri(AUri, ALine, Context);
  if Target.UnitName = '' then
    Exit;
  if Target.CounterpartFile <> '' then
  begin
    if Target.IsTest then
      Title := Format('Zur Unit %s wechseln', [Target.Counterpart])
    else
      Title := Format('Zur Testunit %s wechseln', [Target.Counterpart]);
    Action := TJSONObject.Create;
    Action.AddPair('title', Title);
    Action.AddPair('kind', RewriteKind);
    Action.AddPair('command', CommandJson(Title, OpenFileCommand, TDocumentUris.FromPath(Target.CounterpartFile)));
    Result := [Action];
    Exit;
  end;
  // Anlegen nur auf einer Klasse (#274) oder in einer Unit ohne Klassen.
  if not Target.CanCreate or not (Target.ClassAtLine or (Target.ClassName = '')) then
    Exit;
  Subject := Target.ClassName;
  if Subject = '' then
    Subject := Target.UnitName;
  Title := Format('DUnitX-Testunit für %s anlegen', [Subject]);
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
    raise EArgumentException.Create(Command + ' braucht die URI der Unit');
  Uri := AArguments.Items[0].Value;
  Line := -1;
  if AArguments.Count > 1 then
    Line := StrToIntDef(AArguments.Items[1].Value, -1);
  Answer := TJSONObject.Create;
  Result := Answer;
  if not Assigned(FContextFor) or not FContextFor(Uri, Context) then
  begin
    Answer.AddPair('unit', '');
    Answer.AddPair('reason', 'Datei gehört zu keinem Arbeitsbereich');
    Exit;
  end;
  Target := ResolveUri(Uri, Line, Context);
  Answer.AddPair('unit', Target.UnitName);
  Answer.AddPair('isTest', TJSONBool.Create(Target.IsTest));
  Answer.AddPair('counterpart', Target.Counterpart);
  if Target.CounterpartFile <> '' then
    Answer.AddPair('uri', TDocumentUris.FromPath(Target.CounterpartFile))
  else
    Answer.AddPair('uri', TJSONNull.Create);
  Answer.AddPair('canCreate', TJSONBool.Create(Target.CanCreate));
  if Target.CanCreate then
  begin
    Answer.AddPair('newUri', TDocumentUris.FromPath(Target.NewFile));
    Answer.AddPair('edit', CreateEdit(Target, Context));
  end;
  Answer.AddPair('reason', Target.Reason);
end;

end.
