unit Shell.Mcp.Services;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), die Dienste hinter den Werkzeugen: Symbolindex der Projektgruppe,
// Index-, Code- und Bearbeitungswerkzeuge, Pfadregeln (#99), Architektur (#1118), Hotspots (#1354) und der
// Uses-Graph für find_path (#1117). Jeder Baustein in eigener Routine, damit die anonymen Methoden nur ihre
// Parameter einfangen.

interface

uses
  System.SysUtils,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.IndexTools,
  Atlas.Common.Mcp.CodeTools,
  Atlas.Common.Mcp.Paths,
  Atlas.Common.Mcp.EditTools,
  Atlas.Common.Architecture.Service,
  Atlas.Common.Architecture.UsesService,
  Atlas.Common.Architecture.UsesLocator,
  Atlas.Common.Hotspots.Service,
  Core.Workspace,
  Core.WorkspaceGroup,
  Atlas.Common.Mcp.Contract.Workspace,
  Core.Mcp.Context;

type
  /// <summary>Alle Dienste eines MCP-Laufs; Free gibt sie in umgekehrter Reihenfolge frei.</summary>
  TMcpServices = record
    Root: string;
    Index: ISymbolIndex;
    Store: IDocumentStore;
    /// <summary>Hauptprojekt und übrige Projekte der Gruppe in einem Index (Plugin-Units hinter dem Testprojekt).
    /// </summary>
    Group: TCoreWorkspaceGroup;
    /// <summary>Group für die MCP-Werkzeuge (Adapters.Mcp.Workspace).</summary>
    McpWorkspace: IMcpWorkspace;
    Tools: TMcpIndexTools;
    Code: TMcpCodeTools;
    Guard: TMcpPathGuard;
    Edit: TMcpEditTools;
    Architecture: TArchitectureService;
    Hotspots: THotspotService;
    PathGraphs: TUsesGraphService;
    PathLocator: TUsesLocator;
    /// <summary>Legt Index, Gruppe und Dienste für den Ordner ARoot an; noch ohne Laden.</summary>
    class function Create(const ARoot: string; const ALogger: ILogger): TMcpServices; static;
    procedure Free;
    function Workspace: TCoreWorkspace;
    /// <summary>Alle Dateien der Gruppe (für Werkzeuge, die erst beim Aufruf lesen).</summary>
    function AllFiles: TFunc<TArray<string>>;
    /// <summary>Kontext der Werkzeuge mit AServer.</summary>
    function ToolContext(AServer: TMcpServer): TMcpToolContext;
    /// <summary>Adapter der Werkzeuge: Prozesse, Versionsverwaltung, Git-Verzeichnis; ohne Prüfung von Texten.
    /// </summary>
    class function HostAdapters: TMcpHostAdapters; static;
    /// <summary>Wie HostAdapters mit der Prüfung von Texten und find_unused_code über Projekt, Symbole und Index
    /// aus AGroup.</summary>
    class function GroupAdapters(AGroup: TCoreWorkspaceGroup): TMcpHostAdapters; static;
  end;

implementation

uses
  System.IOUtils,
  Shell.Composition.Mcp,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Mcp.Contract.DeadCode,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Processes,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.Rationale,
  Atlas.Common.Lsp.Impact,
  Atlas.Common.Lsp.References,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Architecture.UsesGraph,
  Platform.Server,
  Core.Mcp.Ide,
  Core.Mcp.ArchitectureTools,
  Atlas.Common.Compiler.Contract,
  Atlas.VersionControl.Repository.Providers.Git,
  Core.VersionControlChanges,
  Shell.Composition.Platform,
  Core.Bootstrap,
  Shell.Composition.RuleRefactorings,
  Adapters.Mcp.Workspace,
  Adapters.Mcp.Process,
  Adapters.Mcp.Vcs,
  Adapters.Mcp.AffectedTests;

function NewProcess: ICompilerProcess;
begin
  Result := TProcessRunner.Create;
end;

function VcsAccess: TCoreVcsAccess;
begin
  Result := TShellPlatformAdapters.VcsAccess;
end;

function GitDirOf(AFolder: string): string;
begin
  Result := TAtlasGitVersionControl.GitDir(AFolder);
end;

function NewStore: IDocumentStore;
begin
  Result := TDocumentStore.Create(
    function(const APath: string): string
    begin
      Result := TServerPlatform.CanonicalizePath(APath);
    end);
end;

function AllFilesOf(AGroup: TCoreWorkspaceGroup): TFunc<TArray<string>>;
begin
  Result :=
    function: TArray<string>
    begin
      Result := AGroup.AllFiles;
    end;
end;

function EnsureUnitOf(AGroup: TCoreWorkspaceGroup): TFunc<string, Boolean>;
begin
  Result :=
    function(AUnitName: string): Boolean
    begin
      Result := AGroup.EnsureUnit(AUnitName);
    end;
end;

function ReferenceFilesOf(AGroup: TCoreWorkspaceGroup): TReferenceFilesProvider;
begin
  Result :=
    function: TArray<string>
    begin
      Result := AGroup.AllFiles;
    end;
end;

/// <summary>Defines des Projekts, zu dem die Datei gehört (Projektgruppe, #1112).</summary>
function DefinesOf(AGroup: TCoreWorkspaceGroup): TUsesDefinesFunc;
begin
  Result :=
    function(const AFileName: string): TArray<string>
    begin
      if not AGroup.WorkspaceOf(AFileName).State.Defines(Result) then
      begin
        Result := nil;
      end;
    end;
end;

/// <summary>Package einer Unit: .dpk unter ARoot, deren contains sie führt; '' ohne.</summary>
function PackageOfUnit(const ARoot, AUnitName: string): string;
var
  mDpk, mText: string;
begin
  Result := '';
  for mDpk in TDirectory.GetFiles(ARoot, '*.dpk', TSearchOption.soAllDirectories) do
  begin
    if ReadSourceText(mDpk, mText) and TMcpIndexTools.PackageContains(mText, AUnitName) then
    begin
      Exit(ChangeFileExt(ExtractFileName(mDpk), ''));
    end;
  end;
end;

function NewIndexTools(const AIndex: ISymbolIndex; AWorkspace: TCoreWorkspace; const ARoot: string):
  TMcpIndexTools;
var
  mRoot: string;
begin
  mRoot := ARoot;
  Result := TMcpIndexTools.Create(AIndex, ReadSourceText);
  // Begründungen (#1123): Einstellungen und ADR-Ordner des Arbeitsbereichs.
  Result.RationaleOptionsFunc :=
    function: TRationaleOptions
    begin
      Result := TRationaleOptions.FromSettings(AWorkspace.Configuration.Settings, mRoot);
    end;
  Result.PackageOf :=
    function(const AUnitName: string): string
    begin
      Result := PackageOfUnit(mRoot, AUnitName);
    end;
end;

/// <summary>Programmtext des Testprojekts (testUnits.project, sonst das erste DUnitX-Projekt unter ARoot); ''
/// ohne.</summary>
function TestProgramText(const ASettings: TServerSettings; const ARoot: string): string;
var
  mProject, mCandidate: string;
  mInfo: TProjectInfo;
begin
  Result := '';
  mProject := ASettings.TestUnits.Project;
  if (mProject <> '') and not TPath.IsPathRooted(mProject) then
  begin
    mProject := TPath.Combine(ARoot, mProject);
  end;
  if mProject = '' then
  begin
    for mCandidate in ProjectFilesUnder(ARoot) do
    begin
      if IsTestProject(mCandidate) then
      begin
        mProject := mCandidate;
        Break;
      end;
    end;
  end;
  if mProject = '' then
  begin
    Exit;
  end;
  if FileExists(ChangeFileExt(mProject, '.dproj')) and LoadProject(ChangeFileExt(mProject, '.dproj'), '', '', mInfo)
    and (mInfo.MainSource <> '') then
  begin
    mProject := mInfo.MainSource;
  end
  else
  begin
    mProject := ChangeFileExt(mProject, '.dpr');
  end;
  if not ReadSourceText(mProject, Result) then
  begin
    Result := '';
  end;
end;

/// <summary>Auswirkungsanalyse (#1120): Tiefe aus navigation, Testunits aus testUnits und dem Testprogramm.
/// </summary>
function ImpactOptionsOf(AWorkspace: TCoreWorkspace; const ARoot: string): TImpactOptionsProvider;
var
  mRoot: string;
begin
  mRoot := ARoot;
  Result :=
    function(const AUri: string): TImpactOptions
    var
      mSettings: TServerSettings;
    begin
      mSettings := AWorkspace.Configuration.Settings;
      Result := TImpactOptions.Default;
      Result.Depth := mSettings.Navigation.ImpactDepth;
      Result.References := mSettings.References;
      // Kein Watchdog wie im LSP: großzügig, die Antwort meldet das erreichte Limit.
      Result.TimeoutMs := 60000;
      Result.Tests := TImpactTestScope.FromProgram(mSettings.TestUnits.Pattern, TestProgramText(mSettings, mRoot));
    end;
end;

/// <summary>Treffersicherheit wie im Editor (#1119).</summary>
function ReferenceSettingsOf(AWorkspace: TCoreWorkspace): TReferenceSettingsProvider;
begin
  Result :=
    function(const AUri: string): TReferenceSettings
    begin
      Result := AWorkspace.Configuration.Settings.References;
    end;
end;

function NewCodeTools(const AIndex: ISymbolIndex; AGroup: TCoreWorkspaceGroup; const ARoot: string):
  TMcpCodeTools;
begin
  Result := TMcpCodeTools.Create(AIndex, ReadSourceText, ReferenceFilesOf(AGroup), AGroup.UnitLoader());
  // Nicht auflösbare Bezeichner mit den Symbolen und Include-Dateien des Projekts (#860).
  Result.CheckSource := CheckSourceOf(TMcpWorkspaceAdapter.ForGroup(AGroup));
  Result.SettingsFor := ReferenceSettingsOf(AGroup.Main);
  Result.ImpactOptionsFor := ImpactOptionsOf(AGroup.Main, ARoot);
end;

/// <summary>Pfadregeln (#99): Arbeitsordner und Include-Pfade, Verknüpfungen aufgelöst.</summary>
function NewGuard(AWorkspace: TCoreWorkspace; const ARoot: string): TMcpPathGuard;
begin
  Result := TMcpPathGuard.Create(ARoot,
    function: TArray<string>
    begin
      Result := AWorkspace.State.IncludePaths;
    end,
    function(APath: string): string
    begin
      Result := TServerPlatform.CanonicalizePath(APath);
    end);
end;

function AuditOf(const ALogger: ILogger): TMcpAudit;
var
  mLogger: ILogger;
begin
  mLogger := ALogger;
  Result :=
    procedure(const AText: string)
    begin
      mLogger.Info(AText);
    end;
end;

/// <summary>AGroup.RuleProject als Methodenreferenz (#1112): Die Prüfregeln bekommen Symbolindex und
/// Projektdienste wie im Server. In eigener Routine, aus denselben Gründen wie CheckSourceOf.</summary>
function CheckProjectOf(AGroup: TCoreWorkspaceGroup): TCheckProjectFunc;
begin
  Result :=
    function(const AFileName: string): TCheckProject
    begin
      Result := AGroup.RuleProject(AFileName);
    end;
end;

/// <summary>Neuer Lauf von find_unused_code mit Index, Projekten und Namensräumen von AGroup beim Aufruf; in
/// eigener Routine, damit die anonyme Methode nur AGroup einfängt.</summary>
function DeadCodeOf(AGroup: TCoreWorkspaceGroup): TMcpDeadCodeFunc;
begin
  Result :=
    function: IMcpDeadCode
    begin
      Result := TMcpComposition.DeadCode(AGroup.Index, AGroup.RuleProjectFiles, AGroup.Main.State.Namespaces);
    end;
end;

/// <summary>Schreiben über die IDE, wenn die Datei dort offen ist (#397), sonst auf die Platte.</summary>
function WriteTextOf(const AIde: TMcpIde): TMcpWriteText;
begin
  Result :=
    procedure(const AFileName, AText: string)
    begin
      AIde.WriteSourceText(AFileName, AText);
    end;
end;

/// <summary>Im Editor der IDE ungespeichert geänderte Dateien.</summary>
function DirtyFilesOf(const AIde: TMcpIde): TMcpDirtyFiles;
begin
  Result :=
    function: TArray<string>
    begin
      Result := AIde.EditorDirtyFiles;
    end;
end;

/// <summary>Änderung an einer ungespeicherten Datei in der IDE zurückhalten (#2605).</summary>
function HoldTextOf(const AIde: TMcpIde): TMcpHoldText;
begin
  Result :=
    function(const AFileName, AExpected, AText: string; out AReason: string): TMcpHoldResult
    begin
      Result := AIde.HoldSourceText(AFileName, AExpected, AText, AReason);
    end;
end;

function NewEditTools(const AIndex: ISymbolIndex; AGroup: TCoreWorkspaceGroup; ACode: TMcpCodeTools;
  const ALogger: ILogger): TMcpEditTools;
var
  mIde: TMcpIde;
begin
  mIde := TMcpIde.Create(TMcpProcessAdapter.New);
  Result := TMcpEditTools.Create(AIndex, ReadSourceText, WriteTextOf(mIde), AllFilesOf(AGroup),
    AGroup.UnitLoader());
  Result.DirtyFiles := DirtyFilesOf(mIde);
  // Ungespeicherte Dateien hält die IDE zurück, statt abzulehnen (#2605).
  Result.HoldText := HoldTextOf(mIde);
  Result.CheckSource := ACode.CheckSource;
  Result.SettingsFor := ACode.SettingsFor;
  Result.Extract := TMcpComposition.Extract;
  Result.Formatting := TMcpComposition.Formatting;
  Result.BulkFix := TMcpComposition.BulkFix(CheckProjectOf(AGroup), ACode.CheckSource);
  Result.Audit := AuditOf(ALogger);
end;

{ TMcpServices }

class function TMcpServices.Create(const ARoot: string; const ALogger: ILogger): TMcpServices;
var
  mIdentity: TIndexProcessInfo;
  mPathOptions: TUsesGraphOptions;
begin
  Result := Default(TMcpServices);
  Result.Root := ARoot;
  Result.Index := TSymbolIndex.Create;
  Result.Store := NewStore;
  Result.Group := TCoreWorkspaceGroup.Create(ARoot, Result.Store, ALogger, Result.Index, 'atlas-mcp-index',
    TShellPlatformAdapters.WorkspaceFactories, ReadSourceText);
  // Anmeldung am Index-Cache für „Prozesse am Projekt“ (#62); den Namen des MCP-Clients trägt initialize nach (#1883).
  mIdentity := Default(TIndexProcessInfo);
  mIdentity.Pid := TServerPlatform.CurrentProcessId;
  mIdentity.Kind := TIndexProcessInfo.cKindMcp;
  mIdentity.Client := 'MCP-Client';
  Result.Group.ProcessIdentity := mIdentity;
  Result.Group.Refactorings := TShellRuleRefactorings.Create;
  Result.McpWorkspace := TMcpWorkspaceAdapter.ForGroup(Result.Group);
  Result.Tools := NewIndexTools(Result.Index, Result.Group.Main, ARoot);
  Result.Code := NewCodeTools(Result.Index, Result.Group, ARoot);
  Result.Guard := NewGuard(Result.Group.Main, ARoot);
  Result.Edit := NewEditTools(Result.Index, Result.Group, Result.Code, ALogger);
  // Architekturübersicht (#1118) und Hotspots (#1354): dieselben Dienste wie im LSP-Server und auf der
  // Kommandozeile.
  Result.Architecture := TArchitectureService.Create(Result.Index, TCoreBootstrap.SourceReader(),
    DefinesOf(Result.Group));
  Result.Hotspots := THotspotService.Create(Result.Index, TCoreBootstrap.SourceReader());
  // Weg zwischen Symbolen (#1117): eigener Uses-Graph samt Bibliotheks-Units (Start oder Ziel).
  mPathOptions := TUsesGraphOptions.Default;
  mPathOptions.IncludeLibrary := True;
  Result.PathGraphs := TUsesGraphService.Create(Result.Index, mPathOptions);
  Result.PathLocator := TUsesLocator.Create(TCoreBootstrap.SourceReader(), DefinesOf(Result.Group));
end;

procedure TMcpServices.Free;
begin
  Guard.Free;
  Edit.Free;
  Code.Free;
  Tools.Free;
  Architecture.Free;
  Hotspots.Free;
  PathLocator.Free;
  PathGraphs.Free;
  McpWorkspace := nil;
  Group.Free;
end;

function TMcpServices.Workspace: TCoreWorkspace;
begin
  Result := Group.Main;
end;

function TMcpServices.AllFiles: TFunc<TArray<string>>;
begin
  Result := AllFilesOf(Group);
end;

function TMcpServices.ToolContext(AServer: TMcpServer): TMcpToolContext;
begin
  Result := Default(TMcpToolContext);
  Result.Server := AServer;
  Result.Tools := Tools;
  Result.Code := Code;
  Result.Workspace := McpWorkspace;
  Result.UsesGraph := Group.UsesGraph;
  Result.Root := Root;
  Result.Guard := Guard;
  Result.Edit := Edit;
  Result.Architecture := ArchitectureOf(McpWorkspace, Architecture, AllFiles(), Root);
  Result.FindPath := FindPathOf(Index, PathGraphs, PathLocator, McpWorkspace, EnsureUnitOf(Group), Root);
  Result.Index := Index;
  Result.Hotspots := Hotspots;
  Result.ImpactOptionsFor := Code.ImpactOptionsFor;
  Result.Adapters := GroupAdapters(Group);
  Result.Adapters.AffectedTests := TMcpAffectedTestsAdapter.New(McpWorkspace, VcsAccess, Code.ImpactOptionsFor);
  Result.Started := Now;
end;

class function TMcpServices.HostAdapters: TMcpHostAdapters;
begin
  Result := Default(TMcpHostAdapters);
  Result.NewProcess := NewProcess;
  Result.Process := TMcpProcessAdapter.New;
  Result.Vcs := TMcpVcsAdapter.New(VcsAccess);
  Result.GitDir := GitDirOf;
  Result.CompilerFixes := TMcpComposition.CompilerFixes;
  Result.Conventions := TMcpComposition.Conventions;
  Result.FindingPrompts := TMcpComposition.FindingPrompts;
  Result.RuleDocs := TMcpComposition.RuleDocs;
end;

class function TMcpServices.GroupAdapters(AGroup: TCoreWorkspaceGroup): TMcpHostAdapters;
begin
  Result := HostAdapters;
  Result.TextChecks := TMcpComposition.TextChecks(CheckProjectOf(AGroup),
    CheckSourceOf(TMcpWorkspaceAdapter.ForGroup(AGroup)));
  Result.DeadCode := DeadCodeOf(AGroup);
end;

end.
