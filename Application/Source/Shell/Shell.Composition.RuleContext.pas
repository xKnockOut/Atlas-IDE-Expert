unit Shell.Composition.RuleContext;

// Internals-Rolle Shell: Umfeld der Prüfregeln je Datei für Editor, --check und MCP (#896, #1112). Einstellungen,
// Baseline und Dienste des Arbeitsbereichs, Anwendungsart und Formulare der Projekte, Index und Projekte der
// Gruppe (#1102), Formulardatei neben der Unit und Dateien im Ordner.

interface

uses
  Atlas.Common.Logging.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Query.Contract,
  Atlas.Common.Architecture.UsesService,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Rules.ProjectFiles,
  Atlas.Common.Lsp.FindingsMemo,
  Atlas.Common.Lsp.SyntaxDiagnostics,
  Shell.Workspace,
  Shell.Composition.Workspaces,
  Shell.Composition.Settings;

type
  TShellRuleIndexFunc = reference to function: ISymbolIndex;
  TShellRuleUsesGraphFunc = reference to function: TUsesGraphService;
  TShellRuleQueriesFunc = reference to function: ICodeQueries;

  /// <summary>Was das Umfeld der Prüfregeln von der Komposition braucht; Index, Uses-Graph und Abfragen entstehen
  /// erst nach dem Umfeld und werden je Prüfung gefragt.</summary>
  TShellRuleContextServices = record
    Logger: ILogger;
    Workspaces: TShellWorkspaceRegistry;
    Settings: TShellSettings;
    Index: TShellRuleIndexFunc;
    UsesGraph: TShellRuleUsesGraphFunc;
    Queries: TShellRuleQueriesFunc;
    EnsureUnit: TEnsureUnitFunc;
    /// <summary>Geöffnete Dokumente vor der Platte.</summary>
    ReadText: TRuleProjectReadText;
  end;

  /// <summary>Umfeld der Prüfregeln je Datei.</summary>
  TShellRuleContext = class
  private
    FServices: TShellRuleContextServices;
    /// <summary>Zuletzt gesehener Stand von ruleChecks.enabled (#1454): 1 an, 0 aus; nur über TInterlocked.
    /// </summary>
    FRuleChecksState: Integer;
    /// <summary>Treffer der Diagnose für die Code-Aktionen am selben Text (2.0-stable).</summary>
    FMemo: IRuleFindingsMemo;
    procedure WorkspaceContext(const AFileName: string; var AContext: TRuleCheckContext;
      out AProjects: TArray<TProjectInfo>; out ALibrary: Boolean);
    /// <summary>Projekt des Arbeitsbereichs und weitere Projekte mit der Datei; Aufrufer hält die Sperre.</summary>
    function ProjectsWithFile(AWorkspace: TShellWorkspace; const AFileName: string): TArray<TProjectInfo>;
    procedure ApplyProject(const AProjects: TArray<TProjectInfo>; const AFileName: string;
      var AContext: TRuleCheckContext);
    procedure IndexServices(var AContext: TRuleCheckContext);
    procedure ReadFormFile(const AFileName: string; var AContext: TRuleCheckContext);
    procedure LogRuleChecksState(AState: Integer);
  public
    constructor Create(const AServices: TShellRuleContextServices);
    /// <summary>Umfeld für --check, MCP und die Teile der Komposition.</summary>
    function RuleContextFor(const AUri: string; out AContext: TRuleCheckContext): Boolean;
    /// <summary>Wie RuleContextFor für die Prüfung im Editor: ohne Regeln, solange ruleChecks.enabled aus ist; ein
    /// Wechsel steht im Log.</summary>
    function LiveRuleContextFor(const AUri: string; out AContext: TRuleCheckContext): Boolean;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.Builtin,
  Shell.Workspace.RuleProjects;

/// <summary>Liest Ressourcen neben der Unit, z. B. die .dcr mit den Palettensymbolen (#114).</summary>
function FolderFileReader(const AFolder: string): TRuleFileReader;
begin
  Result :=
    function(const AName: string; out AData: TBytes): Boolean
    begin
      Result := TFile.Exists(TPath.Combine(AFolder, AName));
      if Result then
      try
        AData := TFile.ReadAllBytes(TPath.Combine(AFolder, AName));
      except
        on EInOutError do
          Result := False;
        on EFileStreamError do
          Result := False;
      end;
    end;
end;

/// <summary>Fehlende Dateien aus {$I} und {$R} (#1379) neben der Unit.</summary>
function FolderFileExists(const AFolder: string): TRuleFileExists;
begin
  Result :=
    function(const AName: string): Boolean
    begin
      Result := TFile.Exists(TPath.Combine(AFolder, AName));
    end;
end;

constructor TShellRuleContext.Create(const AServices: TShellRuleContextServices);
begin
  inherited Create;
  FServices := AServices;
  FRuleChecksState := 1;
  FMemo := TRuleFindingsMemo.Create;
end;

function TShellRuleContext.RuleContextFor(const AUri: string; out AContext: TRuleCheckContext): Boolean;
var
  mFileName: string;
  mProjects: TArray<TProjectInfo>;
  mLibrary: Boolean;
begin
  AContext := Default(TRuleCheckContext);
  mFileName := TDocumentUris.ToPath(AUri);
  AContext.FileName := mFileName;
  WorkspaceContext(mFileName, AContext, mProjects, mLibrary);
  // Anwendungsart, Projektname und Formulare der .dpr (#926, #943, #956, #1055), wie bei MCP und Linter.
  if mProjects <> nil then
  begin
    ApplyProject(mProjects, mFileName, AContext);
  end;
  // Neue Instanzen je Prüfung: Regeln dürfen so Zustand halten, ohne Threads zu teilen. Ohne Regeln bleibt die
  // Datei still (TLspSyntaxDiagnostics.RuleFindings).
  AContext.Rules := nil;
  if not mLibrary then
  begin
    AContext.Rules := BuiltinRules;
  end;
  IndexServices(AContext);
  // Editor-Prüfung (#896): Diagnosen, Code-Aktionen, Slash-Befehle und Baseline wie im Editor; uses-cycle folgt
  // dort diagnostics.usesCycleLive.
  AContext.Live := True;
  if SameText(ExtractFileExt(mFileName), '.pas') then
  begin
    ReadFormFile(mFileName, AContext);
  end;
  AContext.ReadFile := FolderFileReader(ExtractFilePath(mFileName));
  AContext.FileExists := FolderFileExists(ExtractFilePath(mFileName));
  AContext.Memo := FMemo;
  Result := True;
end;

procedure TShellRuleContext.LogRuleChecksState(AState: Integer);
begin
  if TInterlocked.Exchange(FRuleChecksState, AState) = AState then
  begin
    Exit;
  end;
  if AState = 0 then
  begin
    FServices.Logger.Info('Prüfregeln aus (ruleChecks.enabled): Die Prüfung im Editor meldet nur Syntaxfehler und ' +
      'Compilermeldungen; --check und MCP prüfen weiter nach atlas.json.');
  end
  else
  begin
    FServices.Logger.Info('Prüfregeln wieder an (ruleChecks.enabled).');
  end;
end;

function TShellRuleContext.LiveRuleContextFor(const AUri: string; out AContext: TRuleCheckContext): Boolean;
var
  mState: Integer;
begin
  Result := RuleContextFor(AUri, AContext);
  if not Result then
  begin
    Exit;
  end;
  mState := Ord(AContext.Settings.RuleChecksEnabled);
  LogRuleChecksState(mState);
  if mState = 0 then
  begin
    AContext.Rules := nil;
  end;
end;

procedure TShellRuleContext.WorkspaceContext(const AFileName: string; var AContext: TRuleCheckContext;
  out AProjects: TArray<TProjectInfo>; out ALibrary: Boolean);
var
  mWorkspace: TShellWorkspace;
begin
  AProjects := nil;
  System.TMonitor.Enter(FServices.Workspaces.Lock);
  try
    mWorkspace := FServices.Workspaces.Pick(AFileName);
    AContext.Settings := FServices.Settings.Loose;
    if mWorkspace <> nil then
    begin
      AContext.Settings := mWorkspace.Configuration.Settings;
      AContext.RelativePath := ExtractRelativePath(IncludeTrailingPathDelimiter(mWorkspace.Configuration.ConfigRoot),
        AFileName);
      AContext.Baseline := mWorkspace.Baseline;
      // Index, Namespaces, Unit-Suche, Packages und Namenskonvention auf demselben Weg wie MCP und Linter
      // (#1112).
      AContext.Services := mWorkspace.RuleServices;
      // Gespeicherte Abfragen mit failIfAny als Regeln query:<name> (#1351).
      AContext.Services.Queries := FServices.Queries();
      AProjects := ProjectsWithFile(mWorkspace, AFileName);
    end;
    // RTL, VCL und Komponenten außerhalb der Projekte (diagnostics.librarySources): Wer mit Strg+Klick in
    // System.Net.HttpClient.pas springt, soll dort keine Befunde zu fremdem Code sehen.
    ALibrary := not AContext.Settings.DiagnosticsLibrarySources and FServices.Workspaces.IsLibrarySource(AFileName);
  finally
    System.TMonitor.Exit(FServices.Workspaces.Lock);
  end;
end;

function TShellRuleContext.ProjectsWithFile(AWorkspace: TShellWorkspace;
  const AFileName: string): TArray<TProjectInfo>;
var
  mOther: TShellWorkspace;
  mProject: TProjectInfo;
begin
  Result := nil;
  if AWorkspace.State.Project(mProject) then
  begin
    Result := Result + [mProject];
  end;
  // Weitere Projekte mit der Datei (#1112): Eine Unit im Testprogramm und im Package hat keine
  // eindeutige Anwendungsart (MergeRuleProjects).
  for mOther in FServices.Workspaces.Items do
  begin
    if (mOther <> AWorkspace) and mOther.State.ContainsFile(AFileName) and mOther.State.Project(mProject) then
    begin
      Result := Result + [mProject];
    end;
  end;
end;

procedure TShellRuleContext.ApplyProject(const AProjects: TArray<TProjectInfo>; const AFileName: string;
  var AContext: TRuleCheckContext);
var
  mRuleProject: TCheckProject;
begin
  mRuleProject := TShellRuleProjects.RuleProjectOf(AProjects, AFileName, FServices.ReadText);
  AContext.Application := mRuleProject.Application;
  AContext.ProjectName := mRuleProject.Name;
  AContext.AutoCreateForms := mRuleProject.AutoCreateForms;
  AContext.ProjectMainSource := mRuleProject.ProjectMainSource;
end;

procedure TShellRuleContext.IndexServices(var AContext: TRuleCheckContext);
var
  mPending: string;
  mWorkspaces: TShellWorkspaceRegistry;
begin
  // Der Server hält alle Ordner: ein Index, Nachladen über alle Ordner (auch für Dateien ohne Ordner) und die
  // Projekte der Gruppe für unused-public-member (#1102); still, solange Projekte laden oder der Index läuft.
  AContext.Services.Index := FServices.Index();
  AContext.Services.EnsureUnit := FServices.EnsureUnit;
  // Solange Projekte laden oder der Index aufgebaut wird, ohne Index prüfen: Ein halber Index kennt Units noch
  // nicht, Regeln wie unresolved-identifier meldeten dann Bezeichner aus ihnen als nicht deklariert. Ohne Index
  // schweigen diese Regeln (wie mit --no-index); IndexFinished prüft danach alle Dateien neu.
  mWorkspaces := FServices.Workspaces;
  if not mWorkspaces.RuleProjectsComplete(mPending) then
  begin
    AContext.Services.Index := nil;
    AContext.Services.EnsureUnit := nil;
  end;
  AContext.Services.ProjectFiles := TRuleProjectFiles.Create(mWorkspaces.RuleProjects, FServices.Index(),
    FServices.ReadText,
    function(out AReason: string): Boolean
    begin
      Result := mWorkspaces.RuleProjectsComplete(AReason);
    end, FServices.UsesGraph());
end;

procedure TShellRuleContext.ReadFormFile(const AFileName: string; var AContext: TRuleCheckContext);
begin
  // Formulardatei neben der Unit für den Abgleich von Feldern und Objekten (#123).
  // Mit Pfad, damit Korrekturen die Formulardatei ändern können (#309).
  if FServices.ReadText(ChangeFileExt(AFileName, '.dfm'), AContext.FormText) then
  begin
    AContext.FormFile := ChangeFileExt(AFileName, '.dfm');
  end
  else if FServices.ReadText(ChangeFileExt(AFileName, '.fmx'), AContext.FormText) then
  begin
    AContext.FormFile := ChangeFileExt(AFileName, '.fmx');
  end
  else
  begin
    AContext.FormText := '';
  end;
end;

end.
