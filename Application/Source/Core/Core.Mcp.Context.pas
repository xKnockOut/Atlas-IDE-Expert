unit Core.Mcp.Context;

// Host-Rolle Core: MCP-Modus (--mcp, #48), gemeinsamer Kontext der Werkzeuge (TMcpToolContext) und
// Hilfen zum Lesen von Quelltext und Projekten.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.IndexTools,
  Atlas.Common.Mcp.CodeTools,
  Atlas.Common.Mcp.Paths,
  Atlas.Common.Mcp.EditTools,
  Atlas.Common.Mcp.Contract.CompilerFixes,
  Atlas.Common.Mcp.Contract.Conventions,
  Atlas.Common.Mcp.Contract.DeadCode,
  Atlas.Common.Mcp.Contract.RuleDocs,
  Atlas.Common.Mcp.Contract.TextChecks,
  Atlas.Common.Mcp.Contract.Workspace,
  Atlas.Common.Mcp.Contract.Process,
  Atlas.Common.Mcp.Contract.Vcs,
  Atlas.Common.Mcp.Contract.AffectedTests,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Architecture.Report,
  Atlas.Common.Semantics.SymbolPath.Search,
  Atlas.Common.Architecture.UsesService,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Hotspots.Service,
  Atlas.Common.Lsp.Impact,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Mcp.RefactorTools,
  Atlas.Common.Compiler.Contract;

type
  /// <summary>Text der Architekturübersicht (#1118) zu Abschnitt bzw. Unit ('' = Abschnitt); mit ACompareWith
  /// (absoluter Pfad eines gespeicherten Stands, #1121) der Text des Vergleichs. AResolution: Feinheit γ für
  /// diesen Aufruf (#1366), 0 = architecture.grouping.resolution.</summary>
  TMcpArchitectureFunc = reference to function(ASection: TArchitectureSection;
    const AUnit, ACompareWith: string; AResolution: Double): string;
  /// <summary>Antwort von find_path (#1117) als Text.</summary>
  TMcpFindPathFunc = reference to function(const ARequest: TSymbolPathRequest): string;

  /// <summary>refactor für ARequest (#2150); ARequest.FileName ist mit seinem Text für den Aufruf geöffnet. Liest
  /// die Datei über AEdit.ReadText; EMcpToolError, wenn sie nicht lesbar ist. Die Shell setzt es aus den
  /// Refactorings des Servers zusammen (TMcpRefactorSources.Attach).</summary>
  TMcpRefactorFunc = reference to function(AEdit: TMcpEditTools; const ARequest: TMcpRefactorRequest): string;

  /// <summary>Was die Werkzeuge an Adaptern brauchen; die Shell erzeugt sie (TMcpServices.HostAdapters).</summary>
  TMcpHostAdapters = record
    /// <summary>Neuer Prozess für Testläufe (run_tests).</summary>
    NewProcess: TFunc<ICompilerProcess>;
    /// <summary>Prozesse und Ordnersignale des Servers (laufende IDEs, Antworten des Plugins, get_server_status).
    /// </summary>
    Process: IMcpProcessHost;
    /// <summary>Änderungen, Hotspots und Verlauf aus Git oder SVN.</summary>
    Vcs: IMcpVcs;
    /// <summary>Betroffene Tests (get_affected_tests); nil, wenn die Adapter ohne Arbeitsbereich entstanden sind.
    /// </summary>
    AffectedTests: IMcpAffectedTests;
    /// <summary>Git-Verzeichnis des Ordners ('' ohne Git).</summary>
    GitDir: TFunc<string, string>;
    /// <summary>Sichere Korrekturen zu Compilermeldungen (explain_compiler_message).</summary>
    CompilerFixes: IMcpCompilerFixes;
    /// <summary>Projektkonventionen (delphi://conventions).</summary>
    Conventions: IMcpConventions;
    /// <summary>Auftrag zu einem Befund (explain_finding).</summary>
    FindingPrompts: IMcpFindingPrompts;
    /// <summary>Prüfung von Texten mit den eingebauten Regeln, dem Projekt und den Symbolen der Gruppe
    /// (get_diagnostics, hook_check, check_code, apply_code_action, explain_finding, Änderungen); nil, wenn die
    /// Adapter ohne Gruppe entstanden sind.</summary>
    TextChecks: IMcpTextChecks;
    /// <summary>Neuer Lauf von find_unused_code mit Index, Projekten und Namensräumen der Gruppe; nil, wenn die
    /// Adapter ohne Gruppe entstanden sind.</summary>
    DeadCode: TMcpDeadCodeFunc;
    /// <summary>Regelkatalog zum Nachschlagen (search_atlas_docs, explain_compiler_message).</summary>
    RuleDocs: IMcpRuleDocs;
  end;

  /// <summary>Was die Werkzeuge des MCP-Modus brauchen; ToolNames füllt nur Server (die Werkzeuge greifen erst
  /// beim Aufruf auf die Dienste zu).</summary>
  TMcpToolContext = record
    Server: TMcpServer;
    Tools: TMcpIndexTools;
    Code: TMcpCodeTools;
    /// <summary>Arbeitsbereich des Servers; nil, wenn nur die Namen der Werkzeuge gebraucht werden.</summary>
    Workspace: IMcpWorkspace;
    /// <summary>Uses-Graph der Gruppe (#64); nil wie Workspace.</summary>
    UsesGraph: TUsesGraphService;
    Root: string;
    Guard: TMcpPathGuard;
    Edit: TMcpEditTools;
    /// <summary>Quelle von refactor (#2150, TMcpRefactorSources.Attach); nil, wenn nur die Namen der Werkzeuge
    /// gebraucht werden.</summary>
    Refactor: TMcpRefactorFunc;
    Architecture: TMcpArchitectureFunc;
    FindPath: TMcpFindPathFunc;
    /// <summary>Symbole und Include-Dateien je Datei (#860) aus Workspace.</summary>
    CheckSource: TPascalSourceFunc;
    Index: ISymbolIndex;
    Hotspots: THotspotService;
    ImpactOptionsFor: TImpactOptionsProvider;
    Adapters: TMcpHostAdapters;
    /// <summary>Start des MCP-Prozesses für get_server_status.</summary>
    Started: TDateTime;
  end;

  /// <summary>Werkzeug mit seinem Kontext; ContextTool macht daraus den Handler für TMcpServer.AddTool.</summary>
  TMcpContextTool = function(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;

/// <summary>Handler, der ATool mit einer Kopie von AContext aufruft.</summary>
function ContextTool(const AContext: TMcpToolContext; ATool: TMcpContextTool): TMcpToolHandler;
/// <summary>dryRun-Argument; Vorgabe true (#61).</summary>
function DryRunOf(const AArguments: TJSONObject): Boolean;
/// <summary>Eingabeschema ASchema mit den Beschreibungen in der Sprache der Texte (#1458): Jedes %s in ASchema steht
/// für eine Beschreibung und wird der Reihe nach durch ADescriptions als JSON-Text ersetzt, so bleibt der Aufbau
/// des Schemas für beide Sprachen derselbe. Weniger Beschreibungen als Platzhalter lassen den Rest stehen
/// (ungültiges JSON, das die Tests der Werkzeuge melden).</summary>
function SchemaWith(const ASchema: string; const ADescriptions: array of string): string;
// Als gewöhnliche Funktion, weil sie als TReadText-Rückruf an mehrere Werkzeuge geht.
function ReadSourceText(const AFileName: string; out AText: string): Boolean;
/// <summary>Projektdatei ohne Ausnahme auswerten; False, wenn sie nicht lesbar ist.</summary>
function LoadProject(const AFileName, AConfiguration, APlatform: string; out AInfo: TProjectInfo): Boolean;
/// <summary>Formatregeln wie im Editor für AFileName: format.* über .editorconfig über den Vorgaben.</summary>
function FormatStyleOf(const AWorkspace: IMcpWorkspace; const AFileName: string): TFormatStyle;
/// <summary>DUnitX-Testprojekt: Die Hauptdatei verwendet DUnitX.TestFramework (#69).</summary>
function IsTestProject(const AFileName: string): Boolean;
/// <summary>Projektdateien unter ARoot ohne Sicherungsordner der IDE.</summary>
function ProjectFilesUnder(const ARoot: string): TArray<string>;
/// <summary>AWorkspace.CheckSource als Methodenreferenz. Als anonyme Methode, weil Free Pascal (Linux-Bau) an
/// der
/// Umwandlung einer Methode eines anderen Objekts intern abbricht; in eigener Routine, weil eine anonyme Methode in
/// einer Variablen, die die anderen anonymen Methoden derselben Routine einfangen, ihren eigenen Rahmen festhält
/// (Leck unter Delphi). AWorkspace erst beim Aufruf: Tests registrieren die Werkzeuge ohne Arbeitsbereich.</summary>
function CheckSourceOf(const AWorkspace: IMcpWorkspace): TPascalSourceFunc;

implementation

uses
  System.IOUtils,
  System.StrUtils,
  Atlas.Common.Projects.DprojReader,
  Atlas.Common.Lsp.Formatting,
  Atlas.Text.Lines,
  Atlas.Text.DUnitX,
  Atlas.Text.Json,
  Atlas.Text.Files,
  Atlas.Common.Documents.FileEncoding;

/// <summary>dryRun-Argument; Vorgabe true (#61).</summary>
function DryRunOf(const AArguments: TJSONObject): Boolean;
begin
  if (AArguments = nil) or not AArguments.TryGetValue<Boolean>('dryRun', Result) then
  begin
    Result := True;
  end;
end;

function SchemaWith(const ASchema: string; const ADescriptions: array of string): string;
var
  mRest: string;
  mIndex, mAt: Integer;
begin
  Result := '';
  mRest := ASchema;
  for mIndex := 0 to High(ADescriptions) do
  begin
    mAt := Pos('%s', mRest);
    if mAt = 0 then
    begin
      Break;
    end;
    Result := Result + Copy(mRest, 1, mAt - 1) + TJsonText.Quote(ADescriptions[mIndex]);
    mRest := Copy(mRest, mAt + 2, MaxInt);
  end;
  Result := Result + mRest;
end;

// Als gewöhnliche Funktion, weil sie als TReadText-Rückruf an mehrere Werkzeuge geht.
function ReadSourceText(const AFileName: string; out AText: string): Boolean;
begin
  Result := TFileEncoding.TryLoadText(AFileName, AText);
end;

function FormatStyleOf(const AWorkspace: IMcpWorkspace; const AFileName: string): TFormatStyle;
begin
  Result := TLspFormatting.Resolve(nil, AFileName, AWorkspace.SettingsOf(AFileName).Formatting,
    function(const AConfigFile: string; out AConfigText: string): Boolean
    begin
      Result := FileExists(AConfigFile) and ReadSourceText(AConfigFile, AConfigText);
    end);
end;

/// <summary>Projektdatei ohne Ausnahme auswerten; False, wenn sie nicht lesbar ist.</summary>
function LoadProject(const AFileName, AConfiguration, APlatform: string; out AInfo: TProjectInfo): Boolean;
var
  mOptions: TDprojOptions;
begin
  mOptions := Default(TDprojOptions);
  mOptions.Config := AConfiguration;
  mOptions.Platform := APlatform;
  mOptions.FileExists :=
    function(APath: string): Boolean
    begin
      Result := FileExists(APath);
    end;
  try
    AInfo := TDprojReader.Load(AFileName, mOptions);
    Result := True;
  except
    on E: Exception do
    begin
      if not (TTextFiles.IsFileError(E) or (E is EFileEncodingError) or (E is EProjectError)) then
      begin
        raise;
      end;
      AInfo := Default(TProjectInfo);
      Result := False;
    end;
  end;
end;

/// <summary>DUnitX-Testprojekt: Die Hauptdatei verwendet DUnitX.TestFramework (#69).</summary>
function IsTestProject(const AFileName: string): Boolean;
var
  mInfo: TProjectInfo;
  mText: string;
begin
  Result := LoadProject(AFileName, '', '', mInfo) and (mInfo.MainSource <> '') and
    ReadSourceText(mInfo.MainSource, mText) and TDUnitXSource.UsesDUnitX(TTextLines.SplitLines(mText));
end;

/// <summary>Projektdateien unter ARoot ohne Sicherungsordner der IDE.</summary>
function ProjectFilesUnder(const ARoot: string): TArray<string>;
var
  mFileName: string;
begin
  Result := nil;
  if (ARoot = '') or not TDirectory.Exists(ARoot) then
  begin
    Exit;
  end;
  for mFileName in TDirectory.GetFiles(ARoot, '*.dproj', TSearchOption.soAllDirectories) do
  begin
    if not ContainsText(mFileName, '\__history\') and not ContainsText(mFileName, '\__recovery\') then
    begin
      Result := Result + [mFileName];
    end;
  end;
end;

/// <summary>AWorkspace.CheckSource als Methodenreferenz. Als anonyme Methode, weil Free Pascal (Linux-Bau) an
/// der
/// Umwandlung einer Methode eines anderen Objekts intern abbricht; in eigener Routine, weil eine anonyme Methode in
/// einer Variablen, die die anderen anonymen Methoden derselben Routine einfangen, ihren eigenen Rahmen festhält
/// (Leck unter Delphi). AWorkspace erst beim Aufruf: Tests registrieren die Werkzeuge ohne Arbeitsbereich.</summary>
function CheckSourceOf(const AWorkspace: IMcpWorkspace): TPascalSourceFunc;
begin
  Result :=
    function(const AFileName: string): TPascalSource
    begin
      Result := AWorkspace.CheckSource(AFileName);
    end;
end;

function ContextTool(const AContext: TMcpToolContext; ATool: TMcpContextTool): TMcpToolHandler;
var
  mContext: TMcpToolContext;
begin
  mContext := AContext;
  Result :=
    function(const AArguments: TJSONObject): string
    begin
      Result := ATool(mContext, AArguments);
    end;
end;

end.
