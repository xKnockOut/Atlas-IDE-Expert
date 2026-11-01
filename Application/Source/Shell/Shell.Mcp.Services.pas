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
  Shell.Workspace,
  Shell.WorkspaceGroup,
  Shell.Mcp.Context;

type
  /// <summary>Alle Dienste eines MCP-Laufs; Free gibt sie in umgekehrter Reihenfolge frei.</summary>
  TMcpServices = record
    Root: string;
    Index: ISymbolIndex;
    Store: IDocumentStore;
    /// <summary>Hauptprojekt und übrige Projekte der Gruppe in einem Index (Plugin-Units hinter dem Testprojekt).
    /// </summary>
    Group: TShellWorkspaceGroup;
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
    function Workspace: TShellWorkspace;
    /// <summary>Alle Dateien der Gruppe (für Werkzeuge, die erst beim Aufruf lesen).</summary>
    function AllFiles: TFunc<TArray<string>>;
    /// <summary>Kontext der Werkzeuge mit AServer.</summary>
    function ToolContext(AServer: TMcpServer): TMcpToolContext;
  end;

implementation

uses
  System.IOUtils,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Processes,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.Rationale,
  Atlas.Common.Lsp.Impact,
  Atlas.Common.Lsp.References,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Metrics.Collector,
  Atlas.Common.Architecture.UsesGraph,
  Shell.Platform,
  Shell.Mcp.Ide,
  Shell.Mcp.ArchitectureTools;

function NewStore: IDocumentStore;
begin
  Result := TDocumentStore.Create(
    function(const APath: string): string
    begin
      Result := TShellPlatform.CanonicalizePath(APath);
    end);
end;

function AllFilesOf(AGroup: TShellWorkspaceGroup): TFunc<TArray<string>>;
begin
  Result :=
    function: TArray<string>
    begin
      Result := AGroup.AllFiles;
    end;
end;

function EnsureUnitOf(AGroup: TShellWorkspaceGroup): TFunc<string, Boolean>;
begin
  Result :=
    function(AUnitName: string): Boolean
    begin
      Result := AGroup.EnsureUnit(AUnitName);
    end;
end;

function ReferenceFilesOf(AGroup: TShellWorkspaceGroup): TReferenceFilesProvider;
begin
  Result :=
    function: TArray<string>
    begin
      Result := AGroup.AllFiles;
    end;
end;

function EnsureReferenceOf(AGroup: TShellWorkspaceGroup): TEnsureUnitFunc;
begin
  Result :=
    function(const AUnitName: string): Boolean
    begin
      Result := AGroup.EnsureUnit(AUnitName);
    end;
end;

function UsesReaderOf: TUsesTextReader;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end;
end;

/// <summary>Defines des Projekts, zu dem die Datei gehört (Projektgruppe, #1112).</summary>
function DefinesOf(AGroup: TShellWorkspaceGroup): TUsesDefinesFunc;
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

function NewIndexTools(const AIndex: ISymbolIndex; AWorkspace: TShellWorkspace; const ARoot: string):
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
function ImpactOptionsOf(AWorkspace: TShellWorkspace; const ARoot: string): TImpactOptionsProvider;
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
function ReferenceSettingsOf(AWorkspace: TShellWorkspace): TReferenceSettingsProvider;
begin
  Result :=
    function(const AUri: string): TReferenceSettings
    begin
      Result := AWorkspace.Configuration.Settings.References;
    end;
end;

function NewCodeTools(const AIndex: ISymbolIndex; AGroup: TShellWorkspaceGroup; const ARoot: string):
  TMcpCodeTools;
begin
  Result := TMcpCodeTools.Create(AIndex, ReadSourceText, ReferenceFilesOf(AGroup), EnsureReferenceOf(AGroup));
  // Regelprüfung mit den Symbolen und Include-Dateien des Projekts (#860), Prüfregeln mit Symbolindex und
  // Projektdiensten wie im Server (#1112).
  Result.CheckSource := CheckSourceOf(AGroup);
  Result.CheckProject := CheckProjectOf(AGroup);
  Result.SettingsFor := ReferenceSettingsOf(AGroup.Main);
  Result.ImpactOptionsFor := ImpactOptionsOf(AGroup.Main, ARoot);
end;

/// <summary>Pfadregeln (#99): Arbeitsordner und Include-Pfade, Verknüpfungen aufgelöst.</summary>
function NewGuard(AWorkspace: TShellWorkspace; const ARoot: string): TMcpPathGuard;
begin
  Result := TMcpPathGuard.Create(ARoot,
    function: TArray<string>
    begin
      Result := AWorkspace.State.IncludePaths;
    end,
    function(APath: string): string
    begin
      Result := TShellPlatform.CanonicalizePath(APath);
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

function NewEditTools(const AIndex: ISymbolIndex; AGroup: TShellWorkspaceGroup; ACode: TMcpCodeTools;
  const ALogger: ILogger): TMcpEditTools;
begin
  Result := TMcpEditTools.Create(AIndex, ReadSourceText, WriteSourceText, AllFilesOf(AGroup),
    EnsureReferenceOf(AGroup));
  Result.DirtyFiles := EditorDirtyFiles;
  Result.CheckSource := ACode.CheckSource;
  Result.CheckProject := ACode.CheckProject;
  Result.SettingsFor := ACode.SettingsFor;
  Result.Audit := AuditOf(ALogger);
end;

function HotspotReaderOf: TMetricsReadText;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end;
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
  Result.Group := TShellWorkspaceGroup.Create(ARoot, Result.Store, ALogger, Result.Index, 'atlas-mcp-index',
    ReadSourceText);
  // Anmeldung am Index-Cache für „Prozesse am Projekt“ (#62); der MCP-Modus läuft für Claude Code.
  mIdentity := Default(TIndexProcessInfo);
  mIdentity.Pid := TShellPlatform.CurrentProcessId;
  mIdentity.Kind := TIndexProcessInfo.KindMcp;
  mIdentity.Client := 'Claude Code';
  Result.Group.ProcessIdentity := mIdentity;
  Result.Tools := NewIndexTools(Result.Index, Result.Group.Main, ARoot);
  Result.Code := NewCodeTools(Result.Index, Result.Group, ARoot);
  Result.Guard := NewGuard(Result.Group.Main, ARoot);
  Result.Edit := NewEditTools(Result.Index, Result.Group, Result.Code, ALogger);
  // Architekturübersicht (#1118) und Hotspots (#1354): dieselben Dienste wie im LSP-Server und auf der
  // Kommandozeile.
  Result.Architecture := TArchitectureService.Create(Result.Index, UsesReaderOf, DefinesOf(Result.Group));
  Result.Hotspots := THotspotService.Create(Result.Index, HotspotReaderOf);
  // Weg zwischen Symbolen (#1117): eigener Uses-Graph samt Bibliotheks-Units (Start oder Ziel).
  mPathOptions := TUsesGraphOptions.Default;
  mPathOptions.IncludeLibrary := True;
  Result.PathGraphs := TUsesGraphService.Create(Result.Index, mPathOptions);
  Result.PathLocator := TUsesLocator.Create(UsesReaderOf, DefinesOf(Result.Group));
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
  Group.Free;
end;

function TMcpServices.Workspace: TShellWorkspace;
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
  Result.Group := Group;
  Result.Root := Root;
  Result.Guard := Guard;
  Result.Edit := Edit;
  Result.Architecture := ArchitectureOf(Group.Main, Architecture, AllFiles, Root);
  Result.FindPath := FindPathOf(Index, PathGraphs, PathLocator, Group.Main, EnsureUnitOf(Group), Root);
  Result.Index := Index;
  Result.Hotspots := Hotspots;
  Result.ImpactOptionsFor := Code.ImpactOptionsFor;
  Result.Started := Now;
end;

end.
