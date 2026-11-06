unit Shell.Composition.ServerCommands;

// Internals-Rolle Shell: Befehle am Server selbst. Status (#28) und Prozesse (#62), Prüfung und Katalog der
// Einstellungen (#227), Formulare umwandeln, Kompilieren (#261), Index neu aufbauen (#49) oder löschen (#492),
// übersprungene Datei erneut versuchen (#1355), alles neu prüfen (#1231), Build und Projekt wählen (#46). Die
// Komposition reicht Arbeitsbereiche, Compiler, Projektwahl und Logger als Dienste herein.

interface

uses
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Compiler.Backend,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.Processes,
  Shell.Workspace;

type
  TShellServerStatusFunc = reference to function(AAnonymize: Boolean): TJSONObject;
  TShellServerTextFunc = reference to function: string;
  TShellServerFilesFunc = reference to function: TArray<string>;
  TShellServerCompileFunc = reference to function(const AFileName: string;
    out AChoice: TCompilerBackendChoice): Boolean;
  TShellServerWorkspacesFunc = reference to function(const AUri: string): TArray<TShellWorkspace>;
  TShellServerSelectedFunc = reference to function(AWorkspace: TShellWorkspace): Boolean;
  TShellServerSetProjectProc = reference to procedure(const AScope, AProject: string);
  TShellServerRetryFunc = reference to function(const AUri: string): Integer;
  TShellServerRecheckProc = reference to procedure;

  /// <summary>Was die Befehle am Server von der Komposition brauchen.</summary>
  TShellServerCommandServices = record
    Logger: ILogger;
    /// <summary>Status als JSON, auf Wunsch ohne Pfade und Namen.</summary>
    Status: TShellServerStatusFunc;
    /// <summary>Globale Benutzerdatei der Einstellungen ('' ohne).</summary>
    GlobalSettingsFile: TShellServerTextFunc;
    /// <summary>Quelltexte aller Projekte, neben denen Formulare liegen.</summary>
    ProjectSourceFiles: TShellServerFilesFunc;
    /// <summary>Startet einen Compilerlauf von Hand für das Projekt der Datei ('' = aktives Projekt).</summary>
    Compile: TShellServerCompileFunc;
    /// <summary>Der Arbeitsbereich der Datei hinter der URI; mit '' alle. Unter der Sperre der Arbeitsbereiche.</summary>
    Workspaces: TShellServerWorkspacesFunc;
    IsSelectedProject: TShellServerSelectedFunc;
    /// <summary>Aktives Projekt der IDE.</summary>
    ActiveProject: TShellServerTextFunc;
    /// <summary>Merkt das gewählte Projekt je Herkunft über Neustarts ('' hebt die Wahl auf).</summary>
    SetProject: TShellServerSetProjectProc;
    RetryCrashCase: TShellServerRetryFunc;
    /// <summary>Neue Generation der Diagnosen: alle Ergebnis-Ids veralten.</summary>
    Recheck: TShellServerRecheckProc;
  end;

  /// <summary>Befehle am Server selbst.</summary>
  TShellServerCommands = class
  private
    FServices: TShellServerCommandServices;
    function RunStatus(const AArguments: TJSONArray): TJSONValue;
    function RunProcesses(const AArguments: TJSONArray): TJSONValue;
    function RunSettingsCheck(const AArguments: TJSONArray): TJSONValue;
    function RunSettingsCatalog(const AArguments: TJSONArray): TJSONValue;
    function RunConvertForms(const AArguments: TJSONArray): TJSONValue;
    function RunCompile(const AArguments: TJSONArray): TJSONValue;
    function RunRebuildIndex(const AArguments: TJSONArray): TJSONValue;
    function RunClearIndex(const AArguments: TJSONArray): TJSONValue;
    function RunRetryCrashCase(const AArguments: TJSONArray): TJSONValue;
    function RunRecheck(const AArguments: TJSONArray): TJSONValue;
    function RunSelectBuild(const AArguments: TJSONArray): TJSONValue;
    function RunSelectProject(const AArguments: TJSONArray): TJSONValue;
    function ProjectWorkspaces: TArray<TShellWorkspace>;
    /// <summary>Arbeitsbereiche mit Index-Cache und den Prozessen daran (#62).</summary>
    function CollectProcesses: TArray<TLspProcessWorkspace>;
  public const
    CompileCommand = 'atlas.server.compile';
    SelectBuildCommand = 'atlas.server.selectBuild';
    SelectProjectCommand = 'atlas.server.selectProject';
    RebuildIndexCommand = 'atlas.server.rebuildIndex';
  public
    constructor Create(const AServices: TShellServerCommandServices);
    /// <summary>Reine Lesebefehle, nebenläufig (#874): Status, Prozesse, Prüfung und Katalog der Einstellungen.
    /// </summary>
    procedure RegisterReadCommands(ACommands: TLspCommands);
    /// <summary>Befehle, die etwas anstoßen: Kompilieren, Index, Neuprüfen, Build und Projekt wählen.</summary>
    procedure RegisterActionCommands(ACommands: TLspCommands);
    /// <summary>Formulare in Text umwandeln (Logik in Shell.Commands.Build).</summary>
    procedure RegisterConvertCommand(ACommands: TLspCommands);
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Index.Cache,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Atlas.Common.Lsp.Status,
  Atlas.Common.Lsp.SettingsCommands,
  Atlas.Common.Lsp.PullDiagnostics,
  Atlas.Common.Lsp.FormFiles,
  Shell.Platform,
  Shell.CrashCases,
  Shell.Commands.Build,
  Shell.Commands.Index,
  Atlas.Text.LogMarks,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TServerCommandText = (NotLoaded);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TServerCommandText] of TAtlasText = (
    (De: 'Projekt %s ist nicht geladen.'; En: 'Project %s is not loaded.'));

function FirstText(const AArguments: TJSONArray): string;
begin
  Result := '';
  if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
  begin
    Result := AArguments.Items[0].Value;
  end;
end;

function FormFileExists(AFileName: string): Boolean;
begin
  Result := FileExists(AFileName);
end;

constructor TShellServerCommands.Create(const AServices: TShellServerCommandServices);
begin
  inherited Create;
  FServices := AServices;
end;

procedure TShellServerCommands.RegisterReadCommands(ACommands: TLspCommands);
begin
  // Sie warten so nicht hinter einem Neuladen, während das Plugin auf die Antwort wartet.
  // Status (#28); Argument optional {"anonymize": true} (#1356, Fenster „Atlas-Server“ und Diagnosepaket).
  ACommands.RegisterConcurrent(StatusCommand, RunStatus);
  // Prozesse am selben Index-Cache (#62): Sperre, Stand, Prozesse und Ereignisse.
  ACommands.RegisterConcurrent(ProcessesCommand, RunProcesses);
  // Einstellungsdialog des Plugins (#227): Prüfung mit dem Parser des Servers und Regelkatalog.
  ACommands.RegisterConcurrent(TLspSettingsCommands.CheckCommand, RunSettingsCheck);
  ACommands.RegisterConcurrent(TLspSettingsCommands.CatalogCommand, RunSettingsCatalog);
end;

procedure TShellServerCommands.RegisterActionCommands(ACommands: TLspCommands);
begin
  ACommands.Register(CompileCommand, RunCompile);
  ACommands.Register(RebuildIndexCommand, RunRebuildIndex);
  ACommands.Register(ClearIndexCommand, RunClearIndex);
  // „Erneut versuchen“ nach dem Überspringen (#1355): Argument Uri der Datei, ohne alle.
  ACommands.Register(TShellCrashCases.RetryCommand, RunRetryCrashCase);
  ACommands.Register(TLspPullDiagnostics.RecheckCommand, RunRecheck);
  ACommands.Register(SelectBuildCommand, RunSelectBuild);
  ACommands.Register(SelectProjectCommand, RunSelectProject);
end;

procedure TShellServerCommands.RegisterConvertCommand(ACommands: TLspCommands);
begin
  ACommands.Register(TLspFormFiles.ConvertCommand, RunConvertForms);
end;

function TShellServerCommands.RunStatus(const AArguments: TJSONArray): TJSONValue;
var
  mAnonymize: Boolean;
begin
  mAnonymize := (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONObject) and
    (TJSONObject(AArguments.Items[0]).GetValue('anonymize') is TJSONBool) and
    TJSONBool(TJSONObject(AArguments.Items[0]).GetValue('anonymize')).AsBoolean;
  Result := FServices.Status(mAnonymize);
end;

function TShellServerCommands.RunProcesses(const AArguments: TJSONArray): TJSONValue;
var
  mWorkspaces: TArray<TLspProcessWorkspace>;
begin
  mWorkspaces := CollectProcesses;
  Result := TLspProcesses.ToJson(mWorkspaces, TShellPlatform.CurrentProcessId, Now);
  FServices.Logger.Info(TLspProcesses.MarkedMarkdown(mWorkspaces, TShellPlatform.CurrentProcessId, Now));
end;

function TShellServerCommands.CollectProcesses: TArray<TLspProcessWorkspace>;
var
  mWorkspace: TShellWorkspace;
  mItem: TLspProcessWorkspace;
  mStatus: TWorkspaceStatus;
begin
  Result := nil;
  for mWorkspace in FServices.Workspaces('') do
  begin
    mItem := Default(TLspProcessWorkspace);
    if not mWorkspace.Cache.Processes(mItem.CacheFile, mItem.Processes) then
    begin
      Continue;
    end;
    mStatus := mWorkspace.IndexStatus;
    mItem.Name := mWorkspace.Name;
    mItem.Project := mStatus.Project;
    mItem.FormatVersion := TIndexCache.FormatVersion;
    mItem.Units := mStatus.Parsed + mStatus.FromCache;
    if TFile.Exists(mItem.CacheFile) then
    begin
      mItem.Saved := TFile.GetLastWriteTime(mItem.CacheFile);
    end;
    Result := Result + [mItem];
  end;
end;

function TShellServerCommands.RunSettingsCheck(const AArguments: TJSONArray): TJSONValue;
begin
  Result := TLspSettingsCommands.Check(AArguments);
end;

function TShellServerCommands.RunSettingsCatalog(const AArguments: TJSONArray): TJSONValue;
var
  mRule: IRule;
  mExperimental: TArray<string>;
begin
  // Experimentelle Regeln (#834) kennt nur ihr Deskriptor; die Einstellungsseite (#909) markiert sie.
  mExperimental := nil;
  for mRule in BuiltinRules do
  begin
    if mRule.Descriptor.Experimental then
    begin
      mExperimental := mExperimental + [mRule.Descriptor.Id];
    end;
  end;
  Result := TLspSettingsCommands.Catalog(TLspSettingsCommands.CatalogEntries(AArguments),
    FServices.GlobalSettingsFile(), mExperimental);
end;

function TShellServerCommands.RunConvertForms(const AArguments: TJSONArray): TJSONValue;
var
  mConverted, mBackups: Integer;
begin
  // Mit URI eine Datei, sonst alle Formulare neben den Projekt-Units (Logik in Shell.Commands.Build).
  mConverted := TBuildCommands.ConvertForms(TBuildCommands.FormFiles(AArguments, FServices.ProjectSourceFiles(),
    FormFileExists), FServices.Logger, mBackups);
  FServices.Logger.Info(Format('%d binäre Formulare in Text umgewandelt, %d Sicherungskopien (.bak)',
    [mConverted, mBackups]));
  Result := TJSONString.Create(Format('%d Formulare umgewandelt', [mConverted]));
end;

function TShellServerCommands.RunCompile(const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mStarted: Boolean;
  mChoice: TCompilerBackendChoice;
  mAnswer: TJSONObject;
begin
  // Optional die URI einer Datei, deren Projekt kompiliert wird.
  mUri := FirstText(AArguments);
  if mUri = '' then
  begin
    mStarted := FServices.Compile('', mChoice);
  end
  else
  begin
    mStarted := FServices.Compile(TDocumentUris.ToPath(mUri), mChoice);
  end;
  // Ohne nutzbaren Compiler antwortet der Befehl immer mit Grund und Ausweg (#261).
  if not mStarted then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.RequestFailed, mChoice.MessageText);
  end;
  mAnswer := TJSONObject.Create;
  mAnswer.AddPair('started', TJSONBool.Create(True));
  mAnswer.AddPair('backend', TCompilerBackends.BackendText(mChoice.Backend));
  Result := mAnswer;
end;

function TShellServerCommands.RunRebuildIndex(const AArguments: TJSONArray): TJSONValue;
var
  mWorkspace: TShellWorkspace;
  mTargets: TArray<TShellWorkspace>;
begin
  // Alle Ordner ohne Cache neu einlesen (#49), z. B. nach Änderungen außerhalb des Editors.
  mTargets := FServices.Workspaces('');
  for mWorkspace in mTargets do
  begin
    mWorkspace.Rebuild;
  end;
  FServices.Logger.Info(Format('Index wird für %d Ordner neu aufgebaut', [Length(mTargets)]));
  Result := TJSONNull.Create;
end;

function TShellServerCommands.RunClearIndex(const AArguments: TJSONArray): TJSONValue;
var
  mWorkspace: TShellWorkspace;
  mTargets: TArray<TShellWorkspace>;
  mFreed: Int64;
  mRemoved: Integer;
begin
  // „Index löschen“ (#492, Logik in Shell.Commands.Index): Caches freigeben, alle löschen, neu indizieren.
  mTargets := FServices.Workspaces('');
  for mWorkspace in mTargets do
  begin
    mWorkspace.ReleaseCache;
  end;
  mRemoved := TIndexCommands.ClearCaches(TIndexCacheDirectory.DefaultRoot, mFreed);
  FServices.Logger.Info(Format('Index gelöscht: %d Caches, %d KB; %d Ordner werden neu indiziert',
    [mRemoved, mFreed div 1024, Length(mTargets)]));
  for mWorkspace in mTargets do
  begin
    mWorkspace.Rebuild;
  end;
  Result := TIndexCommands.Answer(mRemoved, mFreed);
end;

function TShellServerCommands.RunRetryCrashCase(const AArguments: TJSONArray): TJSONValue;
begin
  Result := TJSONNumber.Create(FServices.RetryCrashCase(FirstText(AArguments)));
end;

function TShellServerCommands.RunRecheck(const AArguments: TJSONArray): TJSONValue;
begin
  // Neue Generation (#1231): Alle Ergebnis-Ids veralten, auch die übersprungener Dateien (#1094); geöffnete
  // Dateien holt der Client nach dem refresh, die übrigen liefert workspace/diagnostic nach.
  FServices.Recheck();
  FServices.Logger.Info('Alle Dateien werden neu geprüft');
  Result := TJSONNull.Create;
end;

function TShellServerCommands.RunSelectBuild(const AArguments: TJSONArray): TJSONValue;
var
  mArgs: TSelectBuildArgs;
  mError: string;
  mWorkspace: TShellWorkspace;
  mTargets: TArray<TShellWorkspace>;
  mProject: TProjectInfo;
  mItems: TJSONArray;
begin
  // Argumente und Antwort in Shell.Commands.Build; ohne Änderung nur die aktuelle Auswahl je Projekt (#46).
  mArgs := TSelectBuildArgs.Parse(AArguments);
  mTargets := FServices.Workspaces(mArgs.Uri);
  if mArgs.Changes then
  begin
    for mWorkspace in mTargets do
    begin
      if mWorkspace.State.Project(mProject) and
        not mWorkspace.SelectBuild(mArgs.Config, mArgs.Platform, mArgs.Defines, mArgs.HasDefines, mError) then
      begin
        raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, mError);
      end;
    end;
  end;
  mItems := TJSONArray.Create;
  for mWorkspace in mTargets do
  begin
    if mWorkspace.State.Project(mProject) then
    begin
      mItems.AddElement(TBuildCommands.ProjectItem(mWorkspace.Name, mProject, mArgs));
    end;
  end;
  Result := TJSONObject.Create(TJSONPair.Create('projects', mItems));
end;

function TShellServerCommands.ProjectWorkspaces: TArray<TShellWorkspace>;
var
  mWorkspace: TShellWorkspace;
begin
  Result := nil;
  for mWorkspace in FServices.Workspaces('') do
  begin
    if mWorkspace.State.ProjectFileName <> '' then
    begin
      Result := Result + [mWorkspace];
    end;
  end;
end;

function TShellServerCommands.RunSelectProject(const AArguments: TJSONArray): TJSONValue;
var
  mArgs: TSelectProjectArgs;
  mTargets: TArray<TShellWorkspace>;
  mItems: TArray<TProjectChoiceItem>;
  mIndex: Integer;
  mActive: string;
begin
  // Projekt für Dateien, die zu mehreren Projekten gehören (#46); gemerkt über Neustarts.
  mArgs := TSelectProjectArgs.Parse(AArguments);
  mTargets := ProjectWorkspaces;
  mActive := FServices.ActiveProject();
  SetLength(mItems, Length(mTargets));
  for mIndex := 0 to High(mTargets) do
  begin
    mItems[mIndex].Name := mTargets[mIndex].Name;
    mItems[mIndex].Project := mTargets[mIndex].State.ProjectFileName;
    mItems[mIndex].Active := SameText(mItems[mIndex].Project, mActive);
  end;
  if mArgs.HasProject and (mArgs.Project = '') then
  begin
    for mIndex := 0 to High(mTargets) do
    begin
      FServices.SetProject(mTargets[mIndex].Setup.Origin, '');
    end;
    FServices.Logger.Info('Projektwahl aufgehoben');
  end
  else if mArgs.HasProject then
  begin
    mIndex := TBuildCommands.FindProject(mItems, mArgs.Project);
    if mIndex < 0 then
    begin
      raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
        cTexts[TServerCommandText.NotLoaded].Fmt([mArgs.Project]));
    end;
    FServices.SetProject(mTargets[mIndex].Setup.Origin, mItems[mIndex].Project);
    FServices.Logger.Info(Format('Projekt %s ausgewählt', [TLogMarks.Name(mItems[mIndex].Name)]));
  end;
  for mIndex := 0 to High(mTargets) do
  begin
    mItems[mIndex].Selected := FServices.IsSelectedProject(mTargets[mIndex]);
  end;
  Result := TBuildCommands.ProjectChoices(mItems);
end;

initialization
  TAtlasTextTables.Add('Shell.Composition.ServerCommands', cTexts);

end.
