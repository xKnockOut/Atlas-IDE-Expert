unit Shell.Mcp;

// Host-Rolle Shell: MCP-Modus (--mcp, #48). Bietet den Symbolindex eines
// Projektordners über das Model Context Protocol an, z. B. für Claude Code:
//
//   claude mcp add delphi -- AtlasServer.exe --mcp --root C:\Projekte\App
//
// stdout gehört dem Protokoll (eine JSON-Nachricht je Zeile); Meldungen gehen
// auf stderr und in die Logdatei.
// Sicherheit (#99): mcp.disabledTools aus atlas.json, --restricted schaltet
// schreibende Werkzeuge ab, schreibende Aufrufe stehen im Log. Ungespeicherte
// Dateien der IDE meldet das Plugin in %LOCALAPPDATA%\Atlas\editor-dirty-<pid>.json.
// Formatieren (format_code, #1358) mit den Formatregeln des Projekts, zu dem die Datei gehört.
// Prüfregeln (get_diagnostics, check_code, explain_finding, apply_code_action, fix_findings)
// bekommen den Symbolindex und die Projektdienste über TShellWorkspaceGroup wie
// im Server (#1112); solange der Index lädt, sagt get_diagnostics das dazu.
// get_server_status (#1356) zeigt den Status des Atlas-Servers der IDE für den
// Ordner (aus dessen Statusdatei), sonst den dieses Prozesses.
// Prompts und Ressourcenvorlagen (#1357) kommen aus TMcpPrompts; hier nur die
// Auflösung von Units und Pfaden (#99) und die Änderungen für prepare_commit.

interface

uses
  Shell.CommandLine;

type
  TMcpShell = class
  public
    /// <summary>Namen aller Werkzeuge, in der Reihenfolge von tools/list (für den Abgleich mit docs/MCP.md).</summary>
    class function ToolNames: TArray<string>; static;
    /// <summary>Läuft, bis der Client die Eingabe schließt; liefert den Exit-Code.</summary>
    class function Run(const AOptions: TCommandLineOptions): Integer; static;
  end;

implementation

uses
{$IFDEF MSWINDOWS}
  // Für das inline-DeleteFile der RTL (H2443); die Plattformadapter kommen aus Shell.Platform.
  Winapi.Windows,
{$ENDIF}
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.IOUtils,
  System.StrUtils,
  System.DateUtils,
  System.JSON,
  Atlas.Common.Product.Version,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Logging.Providers.StreamSink,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.JsonRpc.Connection,
  Atlas.Common.JsonRpc.LineTransport,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.IndexTools,
  Atlas.Common.Lsp.Rationale,
  Atlas.Common.Mcp.CodeTools,
  Atlas.Common.Lsp.Impact,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.AffectedTests,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Todos.Contract,
  Atlas.Common.Mcp.BuildTools,
  Atlas.Common.Mcp.Paths,
  Atlas.Common.Mcp.Freshness,
  Atlas.Common.Mcp.EditTools,
  Atlas.Common.Editing.FormatCheck,
  Atlas.Common.Lsp.Formatting,
  Atlas.Common.Mcp.IdeEdits,
  Atlas.Common.Mcp.IdeBuilds,
  Atlas.Common.Mcp.TestTools,
  Atlas.Common.Mcp.DeadCodeTools,
  Atlas.Common.Mcp.Prompts,
  Atlas.Common.Rules.ChangedFiles,
  Atlas.Core.Vcs.Providers.Git,
  Atlas.Core.Tracker.CommitHook,
  Shell.VcsChanges,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Architecture.UsesService,
  Atlas.Common.Rules.ProjectFiles,
  Atlas.Common.Projects.DprojReader,
  Atlas.Common.Compiler.Contract,
  Atlas.Text.Lines,
  Atlas.Text.DUnitX,
  Atlas.Text.TestResults,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.Scopes,
  Atlas.Common.Rules.Prompt,
  Atlas.Common.Rules.Conventions,
  Atlas.Common.Index.Adapters.DiskFileSystem,
  Atlas.Common.Lsp.IdeBuild,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Atlas.Common.Lsp.Status,
  Atlas.Common.Mcp.StatusTools,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Diagnostics.ShutdownLeaks,
  Atlas.Common.Index.Processes,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Architecture.Overview,
  Atlas.Common.Architecture.Service,
  Atlas.Common.Architecture.Report,
  Atlas.Common.Architecture.Comparison,
  Atlas.Common.Architecture.UsesLocator,
  Atlas.Common.Architecture.SymbolPath,
  Atlas.Common.Lsp.SymbolPath,
  Atlas.Common.Hotspots.Contract,
  Atlas.Common.Hotspots.Analysis,
  Atlas.Common.Hotspots.Service,
  Atlas.Common.Hotspots.Report,
  Atlas.Common.Lsp.Hotspots,
  Atlas.Common.JsonRpc.CurrentRequest,
  Atlas.Common.Projects.Contract,
  Shell.Platform,
  Atlas.Common.Diagnostics.Anonymizer,
  Shell.Workspace,
  Shell.WorkspaceGroup,
  Shell.Bootstrap,
  Shell.AffectedTests,
  Shell.Hotspots,
  Shell.Diagnostics;

/// <summary>Datei des Plugins (editor-dirty-&lt;pid&gt;.json), UTF-8 mit oder ohne BOM. Über TFileEncoding: teilt
/// Löschen, damit das Plugin sie währenddessen atomar ersetzen kann (Bericht M5, N3).</summary>
function ReadPluginFile(const AFileName: string): string;
var
  FileFormat: TFileFormat;
begin
  Result := TFileEncoding.LoadFromFile(AFileName, FileFormat);
end;

/// <summary>Im Editor der IDE ungespeichert geänderte Dateien: editor-dirty-&lt;pid&gt;.json je laufender IDE.</summary>
function EditorDirtyFiles: TArray<string>;
var
  FileName, Text: string;
  Json: TJSONValue;
  Item: TJSONValue;
  Pid: Integer;
begin
  Result := nil;
  if not TDirectory.Exists(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas')) then
    Exit;
  for FileName in TDirectory.GetFiles(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    'editor-dirty-*.json') do
  begin
    try
      Text := ReadPluginFile(FileName);
    except
      on Exception do
        Continue;
    end;
    Json := TJSONObject.ParseJSONValue(Text);
    try
      if not (Json is TJSONObject) or not TJSONObject(Json).TryGetValue<Integer>('pid', Pid) or
        not TProcessInstances.Running(Cardinal(Pid)) then
        Continue;
      if TJSONObject(Json).GetValue('files') is TJSONArray then
        for Item in TJSONArray(TJSONObject(Json).GetValue('files')) do
          Result := Result + [Item.Value];
    finally
      Json.Free;
    end;
  end;
end;

/// <summary>Prozess der IDE, in der AFileName offen ist ("open" in editor-dirty-&lt;pid&gt;.json, #397); 0 ohne.</summary>
function IdeWithOpenFile(const AFileName: string): Cardinal;
var
  FileName, Text: string;
  Json: TJSONValue;
  Item: TJSONValue;
  Pid: Integer;
begin
  Result := 0;
  if not TDirectory.Exists(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas')) then
    Exit;
  for FileName in TDirectory.GetFiles(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    'editor-dirty-*.json') do
  begin
    try
      Text := ReadPluginFile(FileName);
    except
      on Exception do
        Continue;
    end;
    Json := TJSONObject.ParseJSONValue(Text);
    try
      if not (Json is TJSONObject) or not TJSONObject(Json).TryGetValue<Integer>('pid', Pid) or
        not TProcessInstances.Running(Cardinal(Pid)) or not (TJSONObject(Json).GetValue('open') is TJSONArray) then
        Continue;
      for Item in TJSONArray(TJSONObject(Json).GetValue('open')) do
        if SameText(Item.Value, AFileName) then
          Exit(Cardinal(Pid));
    finally
      Json.Free;
    end;
  end;
end;

/// <summary>Laufende IDEs mit Atlas-Plugin samt offenen Projekten (editor-dirty-&lt;pid&gt;.json, #261).</summary>
function RunningIdes: TArray<TMcpIdeEntry>;
var
  FileName, Text: string;
  Entry: TMcpIdeEntry;
begin
  Result := nil;
  if not TDirectory.Exists(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas')) then
    Exit;
  for FileName in TDirectory.GetFiles(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    'editor-dirty-*.json') do
  begin
    try
      Text := ReadPluginFile(FileName);
    except
      on Exception do
        Continue;
    end;
    if TMcpIdeBuilds.ParseEntry(Text, Entry) and TProcessInstances.Running(Entry.Pid) then
      Result := Result + [Entry];
  end;
end;

/// <summary>
/// Schreibt AText mit Kodierung und Zeilenenden der vorhandenen Datei (#121). Ist die Datei in einer IDE
/// mit Atlas-Plugin offen, ändert das Plugin den Puffer und speichert (#397); sonst die Platte.
/// </summary>
procedure WriteSourceText(const AFileName, AText: string);
var
  FileFormat: TFileFormat;
  Expected, Reason: string;
  Pid: Cardinal;
begin
  Expected := TFileEncoding.LoadFromFile(AFileName, FileFormat);
  Pid := IdeWithOpenFile(AFileName);
  if Pid <> 0 then
    case TMcpIdeEdits.Send(TMcpIdeEdits.InboxOf(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), Pid),
      AFileName, Expected, AText,
      procedure
      begin
        Sleep(TMcpIdeEdits.PollMs);
      end,
      function: Int64
      begin
        Result := GetTickCount64;
      end, Reason) of
      TMcpIdeEditOutcome.Applied:
        Exit;
      TMcpIdeEditOutcome.Failed:
        raise EMcpToolError.CreateFmt('IDE: %s', [Reason]);
    end;
  TFileEncoding.SaveToFile(AFileName, AText, FileFormat);
end;

/// <summary>dryRun-Argument; Vorgabe true (#61).</summary>
function DryRunOf(const AArguments: TJSONObject): Boolean;
begin
  if (AArguments = nil) or not AArguments.TryGetValue<Boolean>('dryRun', Result) then
    Result := True;
end;

// Als gewöhnliche Funktion, weil sie als TReadText-Rückruf an mehrere Werkzeuge geht.
function ReadSourceText(const AFileName: string; out AText: string): Boolean;
begin
  Result := TShellBootstrap.ReadSourceText(AFileName, AText);
end;

/// <summary>Baut AProject ('' = aktives Projekt) in der laufenden IDE über das Atlas-Plugin (#261) und wartet
/// auf das Ende. EMcpToolError mit dem Grund, wenn keine IDE mit Atlas-Plugin das Projekt offen hat oder sie
/// den Auftrag nicht annimmt.</summary>
function BuildInIde(const ARoot, AProject, AMode, AConfiguration, APlatform: string): TIdeBuild;
var
  Request: TMcpIdeBuildRequest;
  Pid: Cardinal;
  Wanted, BuildText, Reason: string;
begin
  Request := Default(TMcpIdeBuildRequest);
  Request.Mode := AMode;
  if Request.Mode = '' then
    Request.Mode := 'make';
  if not TMcpIdeBuilds.ModeValid(Request.Mode) then
    raise EMcpToolError.Create('Argument "mode": erlaubt sind "make", "build" und "check"');
  Request.Configuration := AConfiguration;
  Request.Platform := APlatform;
  // Relativer Pfad: relativ zum Arbeitsordner.
  Wanted := AProject;
  if (Wanted <> '') and ((Pos('\', Wanted) > 0) or (Pos('/', Wanted) > 0)) and not TPath.IsPathRooted(Wanted) then
    Wanted := TPath.GetFullPath(TPath.Combine(ARoot, Wanted));
  if not TMcpIdeBuilds.Pick(RunningIdes, ARoot, Wanted, Pid, Request.Project, Reason) then
    raise EMcpToolError.Create(Reason);
  if TMcpIdeBuilds.Send(TMcpIdeBuilds.InboxOf(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    Pid), Request,
    procedure
    begin
      Sleep(TMcpIdeBuilds.PollMs);
    end,
    function: Int64
    begin
      Result := GetTickCount64;
    end, BuildText, Reason) <> TMcpIdeBuildOutcome.Done then
    raise EMcpToolError.Create(Reason);
  if not TMcpBuildTools.FromFileText(BuildText, Result) then
    raise EMcpToolError.Create('Ergebnis der IDE nicht lesbar.');
end;

/// <summary>Projektdatei ohne Ausnahme auswerten; False, wenn sie nicht lesbar ist.</summary>
function LoadProject(const AFileName, AConfiguration, APlatform: string; out AInfo: TProjectInfo): Boolean;
var
  Options: TDprojOptions;
begin
  Options := Default(TDprojOptions);
  Options.Config := AConfiguration;
  Options.Platform := APlatform;
  Options.FileExists :=
    function(APath: string): Boolean
    begin
      Result := FileExists(APath);
    end;
  try
    AInfo := TDprojReader.Load(AFileName, Options);
    Result := True;
  except
    on Exception do
    begin
      AInfo := Default(TProjectInfo);
      Result := False;
    end;
  end;
end;

/// <summary>DUnitX-Testprojekt: Die Hauptdatei verwendet DUnitX.TestFramework (#69).</summary>
function IsTestProject(const AFileName: string): Boolean;
var
  Info: TProjectInfo;
  Text: string;
begin
  Result := LoadProject(AFileName, '', '', Info) and (Info.MainSource <> '') and
    ReadSourceText(Info.MainSource, Text) and TDUnitXSource.UsesDUnitX(TTextLines.SplitLines(Text));
end;

/// <summary>Projektdateien unter ARoot ohne Sicherungsordner der IDE.</summary>
function ProjectFilesUnder(const ARoot: string): TArray<string>;
var
  FileName: string;
begin
  Result := nil;
  if (ARoot = '') or not TDirectory.Exists(ARoot) then
    Exit;
  for FileName in TDirectory.GetFiles(ARoot, '*.dproj', TSearchOption.soAllDirectories) do
    if not ContainsText(FileName, '\__history\') and not ContainsText(FileName, '\__recovery\') then
      Result := Result + [FileName];
end;

function ReadSourceLines(const AFileName: string; out ALines: TArray<string>): Boolean;
var
  Text: string;
begin
  Result := ReadSourceText(AFileName, Text);
  if Result then
    ALines := TTextLines.SplitLines(Text)
  else
    ALines := nil;
end;

/// <summary>Führt die Test-EXE aus (#69): Ergebnis im XML-Bericht AResultFile; AOutput die letzten Zeilen der
/// Ausgabe. Beendet den Prozess nach ATimeoutSeconds; dann ATimedOut.</summary>
function RunTestProcess(const ATarget: TMcpTestTarget; const AArguments: TArray<string>; ATimeoutSeconds: Integer;
  out AOutput: TArray<string>; out ATimedOut: Boolean): Integer;
const
  KeptLines = 40;
var
  Process: ICompilerProcess;
  Request: TCompilerRequest;
  Finished: TEvent;
  Watcher: TThread;
  Output: TArray<string>;
  TimedOut: Boolean;
begin
  Process := TProcessRunner.Create;
  Request := Default(TCompilerRequest);
  Request.Executable := ATarget.Executable;
  Request.Arguments := AArguments;
  Request.WorkingDir := ATarget.WorkingDir;
  Output := nil;
  TimedOut := False;
  Finished := TEvent.Create(nil, True, False, '');
  try
    Watcher := TThread.CreateAnonymousThread(
      procedure
      begin
        if Finished.WaitFor(Cardinal(ATimeoutSeconds) * 1000) = wrTimeout then
        begin
          TimedOut := True;
          Process.Cancel;
        end;
      end);
    Watcher.FreeOnTerminate := False;
    Watcher.Start;
    try
      try
        Result := Process.Run(Request,
          procedure(const ALine: string)
          begin
            Output := Output + [ALine];
            if Length(Output) > KeptLines then
              Delete(Output, 0, Length(Output) - KeptLines);
          end);
      except
        on ECompilerCancelled do
          Result := -1;
      end;
    finally
      Finished.SetEvent;
      Watcher.WaitFor;
      Watcher.Free;
    end;
  finally
    Finished.Free;
  end;
  AOutput := Output;
  ATimedOut := TimedOut;
end;

/// <summary>AGroup.Main.CheckSource als Methodenreferenz. Als anonyme Methode, weil Free Pascal (Linux-Bau) an der
/// Umwandlung einer Methode eines anderen Objekts intern abbricht; in eigener Routine, weil eine anonyme Methode in
/// einer Variablen, die die anderen anonymen Methoden derselben Routine einfangen, ihren eigenen Rahmen festhält
/// (Leck unter Delphi). Main erst beim Aufruf: Tests registrieren die Werkzeuge ohne Gruppe.</summary>
function CheckSourceOf(AGroup: TShellWorkspaceGroup): TCheckSourceFunc;
begin
  Result :=
    function(const AFileName: string): TCheckSource
    begin
      Result := AGroup.Main.CheckSource(AFileName);
    end;
end;

/// <summary>AGroup.RuleProject als Methodenreferenz (#1112), aus denselben Gründen wie CheckSourceOf in eigener
/// Routine.</summary>
function CheckProjectOf(AGroup: TShellWorkspaceGroup): TCheckProjectFunc;
begin
  Result :=
    function(const AFileName: string): TCheckProject
    begin
      Result := AGroup.RuleProject(AFileName);
    end;
end;

type
  /// <summary>Text der Architekturübersicht (#1118) zu Abschnitt bzw. Unit ('' = Abschnitt); mit ACompareWith
  /// (absoluter Pfad eines gespeicherten Stands, #1121) der Text des Vergleichs. AResolution: Feinheit γ für
  /// diesen Aufruf (#1366), 0 = architecture.grouping.resolution.</summary>
  TMcpArchitectureFunc = reference to function(ASection: TArchitectureSection;
    const AUnit, ACompareWith: string; AResolution: Double): string;
  /// <summary>Antwort von find_path (#1117) als Text.</summary>
  TMcpFindPathFunc = reference to function(const ARequest: TSymbolPathRequest): string;

/// <summary>find_path über einen eigenen Uses-Graphen samt Bibliotheks-Units. In eigener Routine, damit die
/// anonyme Methode nicht den Rahmen von Run einfängt (Leck unter Delphi).</summary>
function FindPathOf(const AIndex: ISymbolIndex; AGraphs: TUsesGraphService; ALocator: TUsesLocator;
  AWorkspace: TShellWorkspace; const AEnsure: TFunc<string, Boolean>; const ARoot: string): TMcpFindPathFunc;
begin
  Result :=
    function(const ARequest: TSymbolPathRequest): string
    var
      Request: TSymbolPathRequest;
      Options: TUsesGraphOptions;
      Namespaces: TArray<string>;
      Token: IJsonRpcCancellationToken;
    begin
      Request := ARequest;
      // Grenze requestTimeoutMs; Abbruch über notifications/cancelled des MCP-Clients.
      Request.TimeoutMs := AWorkspace.Configuration.Settings.RequestTimeoutMs;
      Namespaces := AWorkspace.Namespaces;
      if string.Join(',', AGraphs.Options.Namespaces) <> string.Join(',', Namespaces) then
      begin
        Options := AGraphs.Options;
        Options.Namespaces := Namespaces;
        AGraphs.SetOptions(Options);
      end;
      Token := TJsonRpcCurrentRequest.Token;
      Result := TSymbolPathSearch.Text(TSymbolPathSearch.Run(AIndex, AGraphs, ALocator,
        function(const AFileName: string; out AText: string): Boolean
        begin
          Result := ReadSourceText(AFileName, AText);
        end,
        function(const AUnitName: string): Boolean
        begin
          Result := Assigned(AEnsure) and AEnsure(AUnitName);
        end, Namespaces, Request,
        function: Boolean
        begin
          Result := (Token <> nil) and Token.IsCancellationRequested;
        end), ARoot);
    end;
end;

/// <summary>Argumente von find_path; EMcpToolError bei ungültigen Werten.</summary>
function FindPathRequest(const AArguments: TJSONObject): TSymbolPathRequest;
begin
  try
    Result := TLspSymbolPath.ReadRequest(AArguments);
  except
    on E: EJsonRpcError do
      raise EMcpToolError.Create(E.Message);
  end;
end;

procedure RegisterTools(AServer: TMcpServer; ATools: TMcpIndexTools; ACode: TMcpCodeTools;
  AGroup: TShellWorkspaceGroup; const ARoot: string; AGuard: TMcpPathGuard; AEdit: TMcpEditTools;
  const AArchitecture: TMcpArchitectureFunc; const AFindPath: TMcpFindPathFunc);
var
  CheckSource: TCheckSourceFunc;
  CheckProject: TCheckProjectFunc;
begin
  CheckSource := CheckSourceOf(AGroup);
  // Symbolindex und Projektdienste für die Prüfregeln wie im Server (#1112).
  CheckProject := CheckProjectOf(AGroup);
  AServer.AddTool('find_symbol',
    'Sucht Delphi-Symbole (Typen, Methoden, Felder, Konstanten …) im Projekt und in RTL/VCL. ' +
    'Liefert Art, Typ, Unit und Datei:Zeile. Name einfach ("Execute") oder qualifiziert ("TMyForm.Execute"); ' +
    'ohne exakten Treffer wird nach Teilstrings gesucht.',
    TMcpServer.StringSchema(['name'], ['Symbolname, optional mit Typ davor (TFoo.Bar)']),
    function(const AArguments: TJSONObject): string
    begin
      Result := ATools.FindSymbol(TMcpServer.RequiredString(AArguments, 'name'));
    end);
  AServer.AddTool('get_declaration',
    'Vollständiger Quelltext der Deklaration eines Symbols, auch aus RTL/VCL, ohne die ganze Datei zu lesen. ' +
    'Dazu die Begründungen (// WHY:, // HACK:, // NOTE: … über der Deklaration und im Rumpf).',
    TMcpServer.StringSchema(['name'], ['Symbolname, am besten qualifiziert (TFoo.Bar)']),
    function(const AArguments: TJSONObject): string
    begin
      Result := ATools.Declaration(TMcpServer.RequiredString(AArguments, 'name'));
    end);
  AServer.AddTool('get_rationale',
    'Begründungen (#1123): Kommentare wie // WHY:, // HACK:, // NOTE:, // IMPORTANT:, // RATIONALE: (Marken aus ' +
    'hints.rationaleMarkers) einer Unit samt aller Symbole oder eines Symbols, mit Datei und Zeile. Erklärt, ' +
    'warum Code so gebaut ist; Verweise wie ADR-0007 oder #312 stehen im Text.',
    TMcpServer.StringSchema(['unit', 'name'], ['Unit-Name oder Pfad der .pas-Datei',
      'Symbolname, am besten qualifiziert (TFoo.Bar); statt unit'], 0),
    function(const AArguments: TJSONObject): string
    begin
      Result := ATools.Rationale(TMcpServer.OptionalString(AArguments, 'unit'),
        TMcpServer.OptionalString(AArguments, 'name'));
    end);
  AServer.AddTool('get_type_hierarchy',
    'Vorfahren bis zur Wurzel und alle Nachfahren einer Klasse oder eines Interfaces mit Fundstellen.',
    TMcpServer.StringSchema(['name'], ['Typname, z. B. TCustomForm']),
    function(const AArguments: TJSONObject): string
    begin
      Result := ATools.TypeHierarchy(TMcpServer.RequiredString(AArguments, 'name'));
    end);
  AServer.AddTool('get_component_info',
    'published-Properties mit Typ und Default, Ereignisse mit Signatur, Vorfahren, Palettenseite und Package ' +
    'einer Komponentenklasse, auch aus der VCL.',
    TMcpServer.StringSchema(['name'], ['Klassenname, z. B. TButton']),
    function(const AArguments: TJSONObject): string
    begin
      Result := ATools.ComponentInfo(TMcpServer.RequiredString(AArguments, 'name'));
    end);
  AServer.AddTool('get_unit_outline',
    'Gliederung einer Unit ohne Quelltext: uses-Listen, Typen, Methoden, Felder mit Zeilennummern.',
    TMcpServer.StringSchema(['unit'], ['Unit-Name (Vcl.Forms) oder Pfad der .pas-Datei']),
    function(const AArguments: TJSONObject): string
    begin
      Result := ATools.UnitOutline(TMcpServer.RequiredString(AArguments, 'unit'));
    end);
  AServer.AddTool('find_references',
    'Alle Verwendungen eines Symbols im Projekt mit Datei:Zeile und der Quelltextzeile.',
    TMcpServer.StringSchema(['name'], ['Symbolname, am besten qualifiziert (TFoo.Bar)']),
    function(const AArguments: TJSONObject): string
    begin
      ACode.Namespaces := AGroup.Main.Namespaces;
      Result := ACode.References(TMcpServer.RequiredString(AArguments, 'name'));
    end);
  AServer.AddTool('get_call_hierarchy',
    'Aufrufer (incoming) und aufgerufene Routinen (outgoing) einer Methode oder Routine.',
    TMcpServer.StringSchema(['name', 'direction'],
      ['Methode oder Routine, z. B. TFoo.Bar', 'incoming, outgoing oder both (Standard)'], 1),
    function(const AArguments: TJSONObject): string
    begin
      ACode.Namespaces := AGroup.Main.Namespaces;
      Result := ACode.CallHierarchy(TMcpServer.RequiredString(AArguments, 'name'),
        TMcpCodeTools.ParseDirection(TMcpServer.OptionalString(AArguments, 'direction')));
    end);
  AServer.AddTool('get_impact',
    'Auswirkungsanalyse (#1120): Was ist betroffen, wenn sich ein Symbol ändert? Aufrufer und Verweise, ' +
    'Overrides, überschriebene Basismethode, Interface-Methode und Umsetzungen sowie Formularbindungen, nach ' +
    'Ebenen bis zur Tiefe (Vorgabe navigation.impactDepth), dazu die betroffenen DUnitX-Tests mit den Namen ' +
    'für run_tests. Erschlossene Treffer mit Grund (#1119); erreichte Grenzen stehen am Ende.',
    '{"type":"object","properties":{' +
      '"name":{"type":"string","description":"Symbol, am besten qualifiziert (TFoo.Bar)"},' +
      '"depth":{"type":"integer","minimum":1,"maximum":5,"description":"Ebenen; leer = navigation.impactDepth"},' +
      '"format":{"type":"string","enum":["text","json"],"description":"text (Vorgabe) oder json wie atlas/impact"}' +
      '},"required":["name"]}',
    function(const AArguments: TJSONObject): string
    var
      Name, Format: string;
      Depth: Integer;
    begin
      Name := TMcpServer.RequiredString(AArguments, 'name');
      Format := TMcpServer.OptionalString(AArguments, 'format');
      if (Format <> '') and not SameText(Format, 'text') and not SameText(Format, 'json') then
        raise EMcpToolError.Create('"format" ist text oder json');
      ACode.Namespaces := AGroup.Main.Namespaces;
      if AArguments.TryGetValue<Integer>('depth', Depth) then
        Result := ACode.Impact(Name, Depth, SameText(Format, 'json'))
      else
        Result := ACode.Impact(Name, SameText(Format, 'json'));
    end);
  AServer.AddTool('get_last_build',
    'Ergebnis des letzten Builds, den der Benutzer in der IDE gestartet hat: Erfolg, Art, Zeitpunkt, Dauer, ' +
    'Projekt, Konfiguration, Plattform und alle Compilermeldungen mit Datei, Zeile, Spalte, Code und Text.',
    TMcpServer.StringSchema(['project'], ['Projekt (Name oder .dproj) zum Filtern; leer = letzter Build'], 0),
    function(const AArguments: TJSONObject): string
    var
      FileName: string;
      Build: TIdeBuild;
    begin
      FileName := TIndexCacheDirectory.BuildFileFor(TIndexCacheDirectory.DefaultRoot, ARoot);
      if not FileExists(FileName) or
        not TMcpBuildTools.FromFileText(TFile.ReadAllText(FileName, TEncoding.UTF8), Build) then
        Exit(TMcpBuildTools.NoBuild(ARoot));
      Result := TMcpBuildTools.Report(Build, ARoot, TMcpServer.OptionalString(AArguments, 'project'));
    end);
  AServer.AddTool('build_project',
    'Baut ein Projekt in der laufenden RAD-Studio-IDE über das Atlas-Plugin (#261), auch ohne ' +
    'Kommandozeilen-Compiler (Starter Edition), und liefert Ergebnis und alle Compilermeldungen wie ' +
    'get_last_build. Das Projekt muss in der IDE offen sein; ohne project baut es das aktive Projekt, wenn es ' +
    'unter dem Arbeitsordner liegt. Wartet bis zum Ende des Builds.',
    '{"type":"object","properties":{' +
      '"project":{"type":"string","description":"Projekt (.dproj mit Pfad, Dateiname oder Name); ' +
        'leer = aktives Projekt der IDE"},' +
      '"mode":{"type":"string","enum":["make","build","check"],"default":"make",' +
        '"description":"make: geänderte Units, build: alles neu, check: nur Syntax"},' +
      '"configuration":{"type":"string","description":"z. B. Debug oder Release; leer = aktive Konfiguration"},' +
      '"platform":{"type":"string","description":"z. B. Win32 oder Win64; leer = aktive Plattform"}}}',
    function(const AArguments: TJSONObject): string
    begin
      Result := TMcpBuildTools.Report(BuildInIde(ARoot, TMcpServer.OptionalString(AArguments, 'project'),
        TMcpServer.OptionalString(AArguments, 'mode'), TMcpServer.OptionalString(AArguments, 'configuration'),
        TMcpServer.OptionalString(AArguments, 'platform')), ARoot, '');
    end, TMcpToolKind.Process);
  AServer.AddTool('run_tests',
    'Führt die DUnitX-Tests eines Testprojekts aus (#69) und liefert bestandene, fehlgeschlagene und ' +
    'übersprungene Tests; jeder fehlgeschlagene Test mit Meldung, erwartetem und tatsächlichem Wert, Datei und ' +
    'Zeile. Startet die vorhandene Test-EXE ohne Compiler; mit build: true baut es das Projekt vorher in der ' +
    'laufenden IDE wie build_project. Die Plattform kommt aus dem Testprojekt (ein Projekt nur für Win64 läuft ' +
    'als Win64). Das Testprogramm braucht den XML-Logger von DUnitX (Vorlage von RAD Studio).',
    '{"type":"object","properties":{' +
      '"project":{"type":"string","description":"Testprojekt (.dproj mit Pfad, Dateiname oder Name); leer = ' +
        'das einzige DUnitX-Projekt unter dem Arbeitsordner"},' +
      '"tests":{"type":"array","items":{"type":"string"},"description":"Nur diese Tests: Unit.Fixture oder ' +
        'Unit.Fixture.Methode; leer = alle"},' +
      '"build":{"type":"boolean","default":false,"description":"Vorher in der IDE bauen (make)"},' +
      '"configuration":{"type":"string","description":"z. B. Debug; leer = Vorgabe des Projekts"},' +
      '"platform":{"type":"string","description":"z. B. Win64; leer = Vorgabe des Projekts, sonst die erste ' +
        'aktivierte Plattform"},' +
      '"timeoutSeconds":{"type":"integer","default":600,"description":"Zeitlimit des Testlaufs in Sekunden ' +
        '(höchstens 3600)"}}}',
    function(const AArguments: TJSONObject): string
    var
      Wanted, Reason, ResultFile, Xml: string;
      Target: TMcpTestTarget;
      Info: TProjectInfo;
      Tests, Output: TArray<string>;
      BuildFirst, TimedOut: Boolean;
      Timeout, Code: Integer;
      Build: TIdeBuild;
      Run: TTestRunResult;
    begin
      Target := Default(TMcpTestTarget);
      Wanted := TMcpServer.OptionalString(AArguments, 'project');
      if (Wanted <> '') and ((Pos('\', Wanted) > 0) or (Pos('/', Wanted) > 0)) and not TPath.IsPathRooted(Wanted) then
        Wanted := TPath.GetFullPath(TPath.Combine(ARoot, Wanted));
      if (Wanted <> '') and TPath.IsPathRooted(Wanted) and FileExists(Wanted) then
        Target.Project := Wanted
      else if not TMcpTestTools.PickProject(ProjectFilesUnder(ARoot), Wanted,
        function(AFileName: string): Boolean
        begin
          Result := IsTestProject(AFileName);
        end, Target.Project, Reason) then
        raise EMcpToolError.Create(Reason);
      // Plattform aus dem Projekt (#14): erst die Vorgaben der Datei lesen, dann für die Wahl auswerten.
      if not LoadProject(Target.Project, TMcpServer.OptionalString(AArguments, 'configuration'), '', Info) then
        raise EMcpToolError.Create('Projektdatei nicht lesbar: ' + Target.Project);
      if not TMcpTestTools.ChoosePlatform(TMcpServer.OptionalString(AArguments, 'platform'), Info.Platform,
        Info.Platforms, Target.Platform, Reason) then
        raise EMcpToolError.Create(Reason);
      if not LoadProject(Target.Project, TMcpServer.OptionalString(AArguments, 'configuration'), Target.Platform,
        Info) then
        raise EMcpToolError.Create('Projektdatei nicht lesbar: ' + Target.Project);
      Target.Configuration := Info.Config;
      Target.Executable := TMcpTestTools.ExecutableOf(Info);
      Target.WorkingDir := ExtractFileDir(Target.Executable);
      Tests := TMcpTestTools.TestsOf(AArguments);
      if (AArguments = nil) or not AArguments.TryGetValue<Boolean>('build', BuildFirst) then
        BuildFirst := False;
      if (AArguments = nil) or not AArguments.TryGetValue<Integer>('timeoutSeconds', Timeout) or (Timeout <= 0) then
        Timeout := TMcpTestTools.DefaultTimeoutSeconds;
      if Timeout > TMcpTestTools.MaxTimeoutSeconds then
        Timeout := TMcpTestTools.MaxTimeoutSeconds;
      if BuildFirst then
      begin
        Build := BuildInIde(ARoot, Target.Project, 'make', Target.Configuration, Target.Platform);
        if not Build.Success then
          Exit('Build fehlgeschlagen; Tests nicht ausgeführt.' + sLineBreak + TMcpBuildTools.Report(Build, ARoot, ''));
      end;
      if not FileExists(Target.Executable) then
        raise EMcpToolError.CreateFmt('Test-EXE fehlt: %s. Mit "build": true bauen oder das Projekt in der IDE ' +
          'für %s/%s bauen.', [Target.Executable, Target.Configuration, Target.Platform]);
      ResultFile := TPath.Combine(TPath.GetTempPath, Format('atlas-tests-%s.xml',
        [TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '')]));
      try
        Code := RunTestProcess(Target, TDUnitXCommandLine.Arguments(ResultFile, Tests), Timeout, Output, TimedOut);
        if TimedOut then
          raise EMcpToolError.CreateFmt('Testlauf nach %d s abgebrochen (timeoutSeconds).', [Timeout]);
        Xml := '';
        if FileExists(ResultFile) then
          Xml := TFile.ReadAllText(ResultFile, TEncoding.UTF8);
        Run := TTestResults.Parse(Xml);
        Result := TMcpTestTools.Report(Target, Tests, Run, Code, Output, Info.Units, ReadSourceLines);
      finally
        if FileExists(ResultFile) then
          System.SysUtils.DeleteFile(ResultFile);
      end;
    end, TMcpToolKind.Process);
  AServer.AddTool('qualified_name',
    'Voll qualifizierter Name des Symbols an einer Stelle (Unit.TKlasse.Methode), z. B. für Dokumentation.',
    '{"type":"object","properties":{' +
      '"file":{"type":"string","description":"Pfad der Unit (relativ zum Projekt oder absolut)"},' +
      '"line":{"type":"integer","minimum":1,"description":"Zeile ab 1"},' +
      '"column":{"type":"integer","minimum":1,"description":"Spalte ab 1"},' +
      '"withParameters":{"type":"boolean","description":"Bei Routinen die Parametertypen anhängen"}},' +
      '"required":["file","line","column"]}',
    function(const AArguments: TJSONObject): string
    var
      FileName: string;
      Line, Column: Integer;
      WithParameters: Boolean;
    begin
      FileName := AGuard.Resolve(TMcpServer.RequiredString(AArguments, 'file'));
      if not (AArguments.TryGetValue<Integer>('line', Line) and AArguments.TryGetValue<Integer>('column', Column)) then
        raise EMcpToolError.Create('Argumente "line" und "column" fehlen');
      if not AArguments.TryGetValue<Boolean>('withParameters', WithParameters) then
        WithParameters := False;
      ACode.Namespaces := AGroup.Main.Namespaces;
      Result := ACode.QualifiedName(FileName, Line, Column, WithParameters);
    end);
  AServer.AddTool('get_diagnostics',
    'Syntaxfehler und Befunde der Prüfregeln (wie --check) für eine Datei oder das ganze Projekt.',
    TMcpServer.StringSchema(['file'], ['Pfad einer .pas-Datei; leer = alle Projektdateien'], 0),
    function(const AArguments: TJSONObject): string
    var
      FileName, Reason: string;
      Files: TArray<string>;
    begin
      FileName := TMcpServer.OptionalString(AArguments, 'file');
      if FileName <> '' then
        Files := [AGuard.Resolve(FileName)]
      else
        Files := AGroup.Main.ProjectFiles;
      if Length(Files) = 0 then
        raise EMcpToolError.Create('Kein Projekt geladen; Datei angeben');
      Result := TMcpCodeTools.Diagnostics(BuiltinRules, AGroup.Main.Configuration.Settings, ARoot, Files,
        ReadSourceText, CheckSource, CheckProject);
      // Solange der Index lädt, sehen Regeln, die Typen anderer Units brauchen, noch nicht alles (#1112).
      if not AGroup.Ready(Reason) then
        Result := Format('Hinweis: %s; Befunde, die den Symbolindex brauchen, können noch fehlen.',
          [Reason]) + sLineBreak + Result;
    end);
  AServer.AddTool('hook_check',
    'Für Hooks von Claude Code (PostToolUse nach Edit/Write, siehe Plugin atlas): Befunde ab severity ' +
    '(Vorgabe warning) der gerade bearbeiteten Datei als Hook-Ausgabe mit additionalContext. Leer bei Dateien, ' +
    'die kein Pascal-Quelltext sind, außerhalb des Arbeitsbereichs liegen oder keine Befunde haben. Abschalten ' +
    'über mcp.disabledTools.',
    TMcpServer.StringSchema(['file', 'severity'],
      ['Pfad der bearbeiteten Datei (tool_input.file_path)', 'error, warning (Vorgabe), information oder hint'], 1),
    function(const AArguments: TJSONObject): string
    var
      FileName: string;
      Severity: TRuleSeverity;
    begin
      Severity := TMcpCodeTools.ParseHookSeverity(TMcpServer.OptionalString(AArguments, 'severity'));
      try
        FileName := AGuard.Resolve(TMcpServer.RequiredString(AArguments, 'file'));
      except
        // Dateien außerhalb des Projekts gehen Atlas nichts an; eine Fehlermeldung je Bearbeitung wäre Rauschen.
        on EMcpToolError do
          Exit('');
      end;
      Result := TMcpCodeTools.HookDiagnostics(BuiltinRules, AGroup.Main.Configuration.Settings, ARoot, FileName,
        ReadSourceText, CheckSource, CheckProject, Severity);
    end);
  AServer.AddTool('get_metrics',
    'Code-Metriken (#66) je Methode: Länge in Codezeilen, Verschachtelungstiefe, zyklomatische und kognitive ' +
    'Komplexität, Parameteranzahl; Grenzwerte aus atlas.json (Regeln metric-*, Option "max"). Als Markdown-Bericht ' +
    'mit den Methoden über einem Grenzwert oder als JSON-Daten.',
    '{"type":"object","properties":{' +
      '"file":{"type":"string","description":"Pfad einer .pas-Datei; leer = alle Projektdateien"},' +
      '"format":{"type":"string","enum":["markdown","json"],"description":"markdown (Vorgabe) oder json"}}}',
    function(const AArguments: TJSONObject): string
    var
      FileName, Format: string;
      Files: TArray<string>;
    begin
      FileName := TMcpServer.OptionalString(AArguments, 'file');
      Format := TMcpServer.OptionalString(AArguments, 'format');
      if (Format <> '') and not SameText(Format, 'markdown') and not SameText(Format, 'json') then
        raise EMcpToolError.Create('"format" ist markdown oder json');
      if FileName <> '' then
        Files := [AGuard.Resolve(FileName)]
      else
        Files := AGroup.Main.ProjectFiles;
      if Length(Files) = 0 then
        raise EMcpToolError.Create('Kein Projekt geladen; Datei angeben');
      Result := TMcpCodeTools.Metrics(AGroup.Main.Configuration.Settings, ARoot, Files, ReadSourceText,
        SameText(Format, 'json'));
    end);
  AServer.AddTool('get_architecture',
    'Architekturübersicht (#1118) aus dem uses-Graphen: Teilsysteme (Gruppen eng verbundener Units), zentrale ' +
    'Units, Zyklen und Querverbindungen zwischen Teilsystemen, je mit Datei:Zeile der uses-Einträge. Mit "unit" ' +
    'der Steckbrief einer Unit (Teilsystem, Abhängigkeiten, Zyklen, Ausreißer). Mit "compareWith" der Vergleich ' +
    'mit einem gespeicherten Stand (#1121): neue und entfernte Zyklen, Querverbindungen und uses-Kanten zwischen ' +
    'Teilsystemen, Teilsystemwechsel, gewachsene zentrale Units, neue und entfernte Units. Umfang und ' +
    'Bibliotheks-Units aus architecture.* in atlas.json. "resolution" (0,2–5,0) stellt die Feinheit der ' +
    'Teilsysteme für diesen Aufruf ein (#1366): größer = mehr und kleinere Teilsysteme.',
    '{"type":"object","properties":{' +
      '"section":{"type":"string","enum":["overview","central","subsystems","cycles","crossLinks"],' +
        '"description":"Abschnitt; Vorgabe overview"},' +
      '"unit":{"type":"string","description":"Steckbrief dieser Unit statt eines Abschnitts"},' +
      '"compareWith":{"type":"string","description":"Gespeicherter Stand (JSON aus AtlasServer --architecture ' +
        '<Datei.json>), Pfad relativ zum Projekt: liefert die Abschnitte des Vergleichs"},' +
      '"resolution":{"type":"number","minimum":0.2,"maximum":5,"description":"Feinheit der Teilsysteme ' +
        '(Louvain-Auflösung γ); Vorgabe architecture.grouping.resolution, 1 = klassisch"}}}',
    function(const AArguments: TJSONObject): string
    var
      Section: TArchitectureSection;
      CompareWith: string;
      mValue: TJSONValue;
      mResolution: Double;
    begin
      if not TArchitectureReport.ParseSection(TMcpServer.OptionalString(AArguments, 'section'), Section) then
        raise EMcpToolError.Create('"section" ist overview, central, subsystems, cycles oder crossLinks');
      mResolution := 0;
      mValue := nil;
      if AArguments <> nil then
        mValue := AArguments.GetValue('resolution');
      if mValue <> nil then
      begin
        if not (mValue is TJSONNumber) or not TArchitectureGrouping.ValidResolution(TJSONNumber(mValue).AsDouble) then
          raise EMcpToolError.Create('"resolution" ist eine Zahl von 0,2 bis 5,0');
        mResolution := TJSONNumber(mValue).AsDouble;
      end;
      CompareWith := TMcpServer.OptionalString(AArguments, 'compareWith');
      if CompareWith <> '' then
        CompareWith := AGuard.Resolve(CompareWith);
      Result := AArchitecture(Section, TMcpServer.OptionalString(AArguments, 'unit'), CompareWith, mResolution);
    end);
  AServer.AddTool('find_path',
    'Kürzester Weg zwischen zwei Symbolen oder Units (#1117), z. B. „Wie hängt TKundenForm mit TDatenbank ' +
    'zusammen?“, in einem Aufruf statt vieler find_references/get_call_hierarchy. Kanten: uses, inherits, ' +
    'implements (auch Interface → Umsetzung), hasField, parameter, result, calls, contains. Liefert die Kette ' +
    'mit Kantenart und Datei:Zeile je Schritt; erschlossene Kanten (mehrere Umsetzungen) tragen [erschlossen]. ' +
    '„Kein Weg“ ist eine verlässliche Antwort; bei mehrdeutigem Namen kommt die Trefferliste.',
    '{"type":"object","properties":{' +
      '"from":{"type":"string","description":"Start: Typ, Methode (TFoo.Bar), Routine, Feld, Property oder Unit"},' +
      '"to":{"type":"string","description":"Ziel, Angabe wie bei from; ein Typ zählt samt seinen Mitgliedern"},' +
      '"via":{"type":"array","items":{"type":"string","enum":["uses","inherits","implements","hasField",' +
        '"parameter","result","calls","contains","library"]},' +
        '"description":"Erlaubte Kantenarten (Vorgabe alle); library erlaubt RTL/VCL als Durchgang"},' +
      '"maxSteps":{"type":"integer","minimum":1,"maximum":16,"description":"Höchstens so viele Schritte, ' +
        'Vorgabe 8"},' +
      '"all":{"type":"boolean","description":"Alle gleich kurzen Wege (höchstens 5) statt nur des ersten"}},' +
      '"required":["from","to"]}',
    function(const AArguments: TJSONObject): string
    begin
      Result := AFindPath(FindPathRequest(AArguments));
    end);
  AServer.AddTool('get_todos',
    'TODO-Übersicht (#68): Kommentare // TODO, // FIXME und das Format der IDE-To-Do-Liste ' +
    '{ TODO 1 -oPerson -cKategorie : Text } aus allen Dateien des Projekts, mit Priorität, Person und Kategorie. ' +
    'Erledigte Einträge ({ DONE … }) nur mit includeDone. Weitere Marken über die Option "keywords" der Regel ' +
    'todo-comment in atlas.json. Als Markdown-Übersicht oder als JSON-Daten.',
    '{"type":"object","properties":{' +
      '"file":{"type":"string","description":"Pfad einer .pas-Datei; leer = alle Projektdateien"},' +
      '"unit":{"type":"string","description":"Nur diese Unit (Name oder Pfad relativ zum Projekt)"},' +
      '"category":{"type":"string","description":"Nur diese Kategorie (-c)"},' +
      '"owner":{"type":"string","description":"Nur diese Person (-o)"},' +
      '"keyword":{"type":"string","description":"Nur diese Marke, z. B. FIXME"},' +
      '"includeDone":{"type":"boolean","description":"Auch erledigte Einträge (DONE); Vorgabe false"},' +
      '"format":{"type":"string","enum":["markdown","json"],"description":"markdown (Vorgabe) oder json"}}}',
    function(const AArguments: TJSONObject): string
    var
      FileName, Format: string;
      Files: TArray<string>;
      Filter: TTodoFilter;
      IncludeDone: Boolean;
    begin
      FileName := TMcpServer.OptionalString(AArguments, 'file');
      Format := TMcpServer.OptionalString(AArguments, 'format');
      if (Format <> '') and not SameText(Format, 'markdown') and not SameText(Format, 'json') then
        raise EMcpToolError.Create('"format" ist markdown oder json');
      Filter := TTodoFilter.Default;
      Filter.UnitName := TMcpServer.OptionalString(AArguments, 'unit');
      Filter.Category := TMcpServer.OptionalString(AArguments, 'category');
      Filter.Owner := TMcpServer.OptionalString(AArguments, 'owner');
      Filter.Keyword := TMcpServer.OptionalString(AArguments, 'keyword');
      if (AArguments <> nil) and AArguments.TryGetValue<Boolean>('includeDone', IncludeDone) then
        Filter.IncludeDone := IncludeDone;
      // Projektweit heißt: die Dateien, die das Projektmodell (#14) dem Projekt zuordnet.
      if FileName <> '' then
        Files := [AGuard.Resolve(FileName)]
      else
        Files := AGroup.Main.ProjectFiles;
      if Length(Files) = 0 then
        raise EMcpToolError.Create('Kein Projekt geladen; Datei angeben');
      Result := TMcpCodeTools.Todos(AGroup.Main.Configuration.Settings, ARoot, Files, ReadSourceText, Filter,
        SameText(Format, 'json'));
    end);
  AServer.AddTool('check_code',
    'Prüft geplanten Code ohne zu schreiben (#178): Syntaxfehler, Regeltreffer und nicht auflösbare Bezeichner. ' +
    'Entweder den ganzen neuen Text der Unit angeben oder mit startLine/endLine nur einen Zeilenbereich ersetzen.',
    '{"type":"object","properties":{' +
      '"file":{"type":"string","description":"Pfad der Unit (relativ zum Projekt oder absolut)"},' +
      '"text":{"type":"string","description":"Neuer Text: die ganze Unit oder der Ersatz für startLine..endLine"},' +
      '"startLine":{"type":"integer","minimum":1,"description":"Erste ersetzte Zeile (ab 1); ohne Angabe ist text die ganze Unit"},' +
      '"endLine":{"type":"integer","minimum":0,"description":"Letzte ersetzte Zeile; startLine - 1 fügt nur ein"}},' +
      '"required":["file","text"]}',
    function(const AArguments: TJSONObject): string
    var
      FileName, Text: string;
      StartLine, EndLine: Integer;
    begin
      FileName := AGuard.Resolve(TMcpServer.RequiredString(AArguments, 'file'));
      if not AArguments.TryGetValue<string>('text', Text) then
        raise EMcpToolError.Create('Argument "text" fehlt');
      if not AArguments.TryGetValue<Integer>('startLine', StartLine) then
        StartLine := 0;
      if not AArguments.TryGetValue<Integer>('endLine', EndLine) then
        EndLine := StartLine;
      Result := ACode.CheckCode(BuiltinRules, AGroup.Main.Configuration.Settings, ARoot, FileName, Text,
        StartLine, EndLine);
    end);
  AServer.AddTool('get_dfm_info',
    'Komponenten eines Formulars (.dfm/.fmx in Textform) mit Typen, Eigenschaften und Ereignisbehandlern.',
    TMcpServer.StringSchema(['file'], ['Pfad der .dfm/.fmx-Datei oder der zugehörigen .pas-Datei']),
    function(const AArguments: TJSONObject): string
    var
      FileName, Text: string;
    begin
      FileName := AGuard.Resolve(TMcpServer.RequiredString(AArguments, 'file'));
      if SameText(ExtractFileExt(FileName), '.pas') then
      begin
        if FileExists(ChangeFileExt(FileName, '.dfm')) then
          FileName := ChangeFileExt(FileName, '.dfm')
        else
          FileName := ChangeFileExt(FileName, '.fmx');
      end;
      if not TDfmParser.IsFormFile(FileName) or not ReadSourceText(FileName, Text) then
        raise EMcpToolError.CreateFmt('Formulardatei "%s" nicht gefunden', [FileName]);
      Result := TMcpIndexTools.DfmInfo(Text);
    end);
  AServer.AddTool('explain_finding',
    'Erklärt Befunde der Prüfregeln in einer Zeile (#158): Regel, Beschreibung, Codeausschnitt mit markierter Zeile ' +
    'und Vorher/Nachher-Beispiel als Markdown.',
    '{"type":"object","properties":{' +
      '"file":{"type":"string","description":"Pfad der Unit (relativ zum Projekt oder absolut)"},' +
      '"line":{"type":"integer","minimum":1,"description":"Zeile des Befunds (ab 1)"},' +
      '"rule":{"type":"string","description":"Optional: nur diese Regel"}},' +
      '"required":["file","line"]}',
    function(const AArguments: TJSONObject): string
    var
      FileName, Text, RuleId, RelativePath: string;
      Line: Integer;
      Finding: TRuleFinding;
      Catalog: TRuleCatalog;
      Scopes: TFindingScopes;
    begin
      FileName := AGuard.Resolve(TMcpServer.RequiredString(AArguments, 'file'));
      if not AArguments.TryGetValue<Integer>('line', Line) then
        raise EMcpToolError.Create('Argument "line" fehlt');
      RuleId := TMcpServer.OptionalString(AArguments, 'rule');
      if not ReadSourceText(FileName, Text) then
        raise EMcpToolError.CreateFmt('%s ist nicht lesbar', [FileName]);
      RelativePath := FileName;
      if StartsText(IncludeTrailingPathDelimiter(ARoot), FileName) then
        RelativePath := Copy(FileName, Length(IncludeTrailingPathDelimiter(ARoot)) + 1, MaxInt);
      Result := '';
      Catalog := TFindingPrompt.GermanCatalog;
      try
        for Finding in TFileChecker.CheckText(BuiltinRules, AGroup.Main.Configuration.Settings, RelativePath, Text,
          CheckProject(FileName), AGroup.Main.CheckSource(FileName), Scopes) do
          if (Finding.Range.StartPos.Line = Line - 1) and ((RuleId = '') or SameText(RuleId, Finding.RuleId)) then
          begin
            if Result <> '' then
              Result := Result + sLineBreak + sLineBreak;
            Result := Result + TFindingPrompt.Markdown(Finding, FileName, Text, Catalog);
          end;
      finally
        Catalog.Free;
      end;
      if Result = '' then
        raise EMcpToolError.CreateFmt('Kein Befund in Zeile %d von %s.', [Line, ExtractFileName(FileName)]);
    end);
  AServer.AddTool('rename_symbol',
    'Benennt ein Symbol projektweit um, samt .dfm/.fmx und automatisch benannter Ereignis-Handler (#61). ' +
    'dryRun (Vorgabe true) zeigt nur den Diff; dryRun=false schreibt alle Dateien atomar.',
    '{"type":"object","properties":{' +
      '"file":{"type":"string","description":"Datei mit dem Symbol (relativ zum Projekt oder absolut)"},' +
      '"line":{"type":"integer","minimum":1,"description":"Zeile (ab 1)"},' +
      '"column":{"type":"integer","minimum":1,"description":"Spalte (ab 1) im Bezeichner"},' +
      '"newName":{"type":"string","description":"Neuer Name"},' +
      '"dryRun":{"type":"boolean","default":true,"description":"Nur Vorschau, nichts schreiben"}},' +
      '"required":["file","line","column","newName"]}',
    function(const AArguments: TJSONObject): string
    var
      FileName: string;
      Line, Column: Integer;
    begin
      FileName := AGuard.Resolve(TMcpServer.RequiredString(AArguments, 'file'));
      if not AArguments.TryGetValue<Integer>('line', Line) or not AArguments.TryGetValue<Integer>('column', Column) then
        raise EMcpToolError.Create('Argumente "line" und "column" fehlen');
      AEdit.Namespaces := AGroup.Main.Namespaces;
      Result := AEdit.RenameSymbol(FileName, Line, Column, TMcpServer.RequiredString(AArguments, 'newName'),
        DryRunOf(AArguments));
    end, TMcpToolKind.Write);
  AServer.AddTool('apply_code_action',
    'Wendet die Korrektur eines Regeltreffers in einer Zeile an (#61). Ohne title listet es die Korrekturen der Zeile. ' +
    'dryRun (Vorgabe true) zeigt nur den Diff; dryRun=false schreibt.',
    '{"type":"object","properties":{' +
      '"file":{"type":"string","description":"Pfad der Unit (relativ zum Projekt oder absolut)"},' +
      '"line":{"type":"integer","minimum":1,"description":"Zeile des Befunds (ab 1)"},' +
      '"title":{"type":"string","description":"Titel der Korrektur oder Regelkennung; leer = Korrekturen auflisten"},' +
      '"dryRun":{"type":"boolean","default":true,"description":"Nur Vorschau, nichts schreiben"}},' +
      '"required":["file","line"]}',
    function(const AArguments: TJSONObject): string
    var
      FileName: string;
      Line: Integer;
    begin
      FileName := AGuard.Resolve(TMcpServer.RequiredString(AArguments, 'file'));
      if not AArguments.TryGetValue<Integer>('line', Line) then
        raise EMcpToolError.Create('Argument "line" fehlt');
      Result := AEdit.ApplyCodeAction(BuiltinRules, AGroup.Main.Configuration.Settings, ARoot, FileName, Line,
        TMcpServer.OptionalString(AArguments, 'title'), DryRunOf(AArguments));
    end, TMcpToolKind.Write);
  AServer.AddTool('fix_findings',
    'Sammelkorrektur (#1352): wendet die sicheren Korrekturen der genannten Regeln (oder "all") in einer Datei ' +
    'oder im ganzen Projekt an, nur Treffer ab fix.minConfidence (Vorgabe hoch) und nur Regeln mit safeFix im ' +
    'Katalog; bis zu drei Durchgänge, keine neuen Syntaxfehler. dryRun (Vorgabe true) zeigt nur Zusammenfassung ' +
    'und Diff; dryRun=false schreibt alle Dateien oder keine. In der IDE offene Dateien ändert das Plugin als ' +
    'einen Rückgängig-Schritt je Datei, ungespeicherte bleiben unberührt.',
    '{"type":"object","properties":{' +
      '"rules":{"type":"array","items":{"type":"string"},"description":"Regelkennungen, z. B. [\"redundant-cast\"]; [\"all\"] = alle"},' +
      '"file":{"type":"string","description":"Pfad einer Unit; leer = alle Projektdateien"},' +
      '"minConfidence":{"type":"string","enum":["medium","high"],"description":"Untergrenze der Konfidenz; nicht unter fix.minConfidence"},' +
      '"dryRun":{"type":"boolean","default":true,"description":"Nur Vorschau, nichts schreiben"}},' +
      '"required":["rules"]}',
    function(const AArguments: TJSONObject): string
    var
      mFiles, mRules: TArray<string>;
      mItems: TJSONArray;
      mItem: TJSONValue;
      mFile: string;
    begin
      mRules := nil;
      if (AArguments <> nil) and (AArguments.GetValue('rules') is TJSONArray) then
      begin
        mItems := TJSONArray(AArguments.GetValue('rules'));
        for mItem in mItems do
          if (mItem is TJSONString) and (Trim(mItem.Value) <> '') then
            mRules := mRules + [Trim(mItem.Value)];
      end;
      mFile := TMcpServer.OptionalString(AArguments, 'file');
      if mFile <> '' then
        mFiles := TArray<string>.Create(AGuard.Resolve(mFile))
      else
        mFiles := AGroup.Main.ProjectFiles;
      if Length(mFiles) = 0 then
        raise EMcpToolError.Create('Kein Projekt geladen; Datei angeben');
      Result := AEdit.FixFindings(BuiltinRules, AGroup.Main.Configuration.Settings, ARoot, mFiles, mRules,
        TMcpServer.OptionalString(AArguments, 'minConfidence'), DryRunOf(AArguments));
    end, TMcpToolKind.Write);
  AServer.AddTool('format_code',
    'Formatiert eine Unit nach den Formatregeln des Projekts (#1358; format.* in atlas.json, .editorconfig) wie ' +
    '"Dokument formatieren" in der IDE, ganz oder nur startLine..endLine. Mit text wird geplanter Code statt der ' +
    'Datei formatiert und als Text zurückgegeben, ohne zu schreiben. Ohne text zeigt dryRun (Vorgabe true) den ' +
    'Diff; dryRun=false schreibt wie apply_code_action (offene Dateien als ein Rückgängig-Schritt in der IDE). ' +
    'Dateien mit Syntaxfehlern werden nicht formatiert; // atlas-format: off ... on bleibt unverändert.',
    '{"type":"object","properties":{' +
      '"file":{"type":"string","description":"Pfad der Unit (relativ zum Projekt oder absolut)"},' +
      '"text":{"type":"string","description":"Optional: geplanter Inhalt der ganzen Unit statt der Datei"},' +
      '"startLine":{"type":"integer","minimum":1,"description":"Erste zu formatierende Zeile (ab 1); ohne Angabe die ganze Unit"},' +
      '"endLine":{"type":"integer","minimum":1,"description":"Letzte zu formatierende Zeile; Vorgabe startLine"},' +
      '"dryRun":{"type":"boolean","default":true,"description":"Nur Vorschau, nichts schreiben"}},' +
      '"required":["file"]}',
    function(const AArguments: TJSONObject): string
    var
      mFileName, mText: string;
      mStartLine, mEndLine: Integer;
      mScope: TFormatScope;
      mStyle: TFormatStyle;
    begin
      mFileName := AGuard.Resolve(TMcpServer.RequiredString(AArguments, 'file'));
      mScope := TFormatScope.All;
      if AArguments.TryGetValue<Integer>('startLine', mStartLine) then
      begin
        if not AArguments.TryGetValue<Integer>('endLine', mEndLine) then
          mEndLine := mStartLine;
        if (mStartLine < 1) or (mEndLine < mStartLine) then
          raise EMcpToolError.Create('"startLine" ab 1 und "endLine" nicht davor');
        mScope := TFormatScope.Lines([TFormatLineSpan.Create(mStartLine - 1, mEndLine - 1)]);
      end;
      // Formatregeln wie im Editor: format.* über .editorconfig über den Vorgaben (TLspFormatting.Resolve).
      mStyle := TLspFormatting.Resolve(nil, mFileName, AGroup.WorkspaceOf(mFileName).Configuration.Settings.Formatting,
        function(const AConfigFile: string; out AConfigText: string): Boolean
        begin
          Result := FileExists(AConfigFile) and ReadSourceText(AConfigFile, AConfigText);
        end);
      if AArguments.TryGetValue<string>('text', mText) then
        Result := AEdit.FormatCode(mStyle, mFileName, mText, mScope)
      else
        Result := AEdit.FormatCode(mStyle, mFileName, mScope, DryRunOf(AArguments));
    end, TMcpToolKind.Write);
end;

/// <summary>Status dieses MCP-Prozesses für get_server_status, wenn kein Server der IDE läuft (#1356).</summary>
function OwnStatus(const AIndex: ISymbolIndex; AStarted: TDateTime): TServerStatus;
var
  mParts: TIndexMemoryParts;
  mTrees: TSyntaxTreeCacheStats;
begin
  Result := Default(TServerStatus);
  Result.ProcessId := TShellPlatform.CurrentProcessId;
  Result.Version := TProductVersion.Version;
  Result.Started := AStarted;
  Result.UptimeMs := MilliSecondsBetween(Now, AStarted);
  Result.State := TServerStatus.StateReady;
  Result.MemoryBytes := TShutdownLeaks.AllocatedBytes;
  Result.IndexCacheHitPercent := -1;
  mTrees := TSyntaxTreeCache.Stats;
  Result.TreeCacheHitPercent := mTrees.HitPercent;
  Result.TreeCacheTrees := mTrees.Trees;
  Result.Memory.TreeCache := mTrees.Bytes;
  Result.Memory.Total := Result.MemoryBytes;
  if AIndex = nil then
    Exit;
  Result.Units := AIndex.UnitCount;
  Result.Symbols := AIndex.SymbolCount;
  Result.IndexBytes := AIndex.MemoryBytes;
  Result.CompactUnits := AIndex.CompactCount;
  Result.OffloadedUnits := AIndex.OffloadedCount;
  Result.BudgetBytes := AIndex.Budget;
  mParts := AIndex.MemoryParts;
  Result.Memory.Symbols := mParts.ProjectBytes;
  Result.Memory.LibraryUnits := mParts.LibraryBytes;
  Result.Memory.Usages := mParts.UsageBytes;
  Result.Memory.Budget := Result.BudgetBytes;
end;

/// <summary>get_server_status (#1356): Status des Servers der IDE aus der Statusdatei, sonst dieses Prozesses.
/// </summary>
procedure RegisterStatusTools(AServer: TMcpServer; const AIndex: ISymbolIndex; const ARoot: string);
var
  mStarted: TDateTime;
begin
  mStarted := Now;
  AServer.AddTool(TMcpStatusTools.ToolName,
    'Status des Atlas-Servers (#1356) wie im Fenster „Atlas-Server“ der IDE: Speicher je Bereich gegen das ' +
    'Budget, die langsamsten Units und Regeln des letzten Prüflaufs, Warteschlange, Cache-Treffer und die ' +
    'langsamsten Anfragen. Läuft für den Projektordner kein Server der IDE, der Status dieses MCP-Prozesses. ' +
    'Nur lesend; hilfreich, wenn Atlas oder die IDE langsam ist oder viel Speicher braucht.',
    '{"type":"object","properties":{' +
      '"format":{"type":"string","enum":["markdown","json"],"description":"markdown (Vorgabe) oder json"}}}',
    function(const AArguments: TJSONObject): string
    var
      mFormat: string;
    begin
      mFormat := TMcpServer.OptionalString(AArguments, 'format');
      if (mFormat <> '') and not SameText(mFormat, 'markdown') and not SameText(mFormat, 'json') then
        raise EMcpToolError.Create('"format" ist markdown oder json');
      Result := TMcpStatusTools.ServerStatus(TIndexCacheDirectory.DefaultRoot, ARoot, SameText(mFormat, 'json'), Now,
        function: TServerStatus
        begin
          Result := OwnStatus(AIndex, mStarted);
        end);
    end);
end;

/// <summary>Werkzeuge für toten Code und Unit-Abhängigkeiten (#64): Projekte, Index und Uses-Graph der Gruppe wie bei den Prüfregeln (#1112).</summary>
procedure RegisterDeadCodeTools(AServer: TMcpServer; AGroup: TShellWorkspaceGroup; const AIndex: ISymbolIndex;
  const ARoot: string; AGuard: TMcpPathGuard);
begin
  AServer.AddTool('find_unused_code',
    'Ungenutzter Code (#64): private und öffentliche Member, Deklarationen nur im implementation-Teil und Units, ' +
    'die nur das Programm nennt, mit dem Index aller Projekte der Gruppe wie im Editor. Schweregrad, Optionen und ' +
    'deadCode.keepAttributes/keepPatterns aus atlas.json gelten. Als Markdown-Bericht oder als JSON-Daten.',
    '{"type":"object","properties":{' +
      '"file":{"type":"string","description":"Pfad einer .pas-Datei; leer = alle Projektdateien"},' +
      '"format":{"type":"string","enum":["markdown","json"],"description":"markdown (Vorgabe) oder json"}}}',
    function(const AArguments: TJSONObject): string
    var
      FileName, Format: string;
      Files: TArray<string>;
    begin
      FileName := TMcpServer.OptionalString(AArguments, 'file');
      Format := TMcpServer.OptionalString(AArguments, 'format');
      if (Format <> '') and not SameText(Format, 'markdown') and not SameText(Format, 'json') then
        raise EMcpToolError.Create('"format" ist markdown oder json');
      if FileName <> '' then
        Files := [AGuard.Resolve(FileName)]
      else
        Files := AGroup.Main.ProjectFiles;
      if Length(Files) = 0 then
        raise EMcpToolError.Create('Kein Projekt geladen; Datei angeben');
      Result := TMcpDeadCodeTools.FindUnused(BuiltinRules, AGroup.Main.Configuration.Settings, ARoot, Files,
        AIndex, AGroup.RuleProjectFiles, AGroup.Main.Namespaces, SameText(Format, 'json'));
    end);
  AServer.AddTool('get_unit_dependencies',
    'Abhängigkeiten einer Unit (#64): direkte uses und die Units, die sie verwenden, je mit Abschnitt ' +
    '(interface/implementation), auf Wunsch die transitiven Hüllen, dazu die Zyklen durch die Unit mit ' +
    'vollständigem Pfad. Nur Units der Projekte, ohne RTL/VCL. Als Markdown oder als JSON-Daten.',
    '{"type":"object","properties":{' +
      '"unit":{"type":"string","description":"Unit-Name (Ref.Daten) oder Pfad der .pas-Datei"},' +
      '"direction":{"type":"string","enum":["uses","usedBy","both"],"description":"Richtung; Vorgabe both"},' +
      '"transitive":{"type":"boolean","description":"Auch die transitiven Hüllen; Vorgabe false"},' +
      '"format":{"type":"string","enum":["markdown","json"],"description":"markdown (Vorgabe) oder json"}},' +
      '"required":["unit"]}',
    function(const AArguments: TJSONObject): string
    var
      UnitName, Format, Text: string;
      Direction: TMcpUsesDirection;
      Transitive: Boolean;
    begin
      UnitName := TMcpServer.RequiredString(AArguments, 'unit');
      if (Pos('\', UnitName) > 0) or (Pos('/', UnitName) > 0) or SameText(ExtractFileExt(UnitName), '.pas') then
        UnitName := AGuard.Resolve(UnitName);
      if not TMcpDeadCodeTools.ParseDirection(TMcpServer.OptionalString(AArguments, 'direction'), Direction) then
        raise EMcpToolError.Create('"direction" ist uses, usedBy oder both');
      if not AArguments.TryGetValue<Boolean>('transitive', Transitive) then
        Transitive := False;
      Format := TMcpServer.OptionalString(AArguments, 'format');
      if (Format <> '') and not SameText(Format, 'markdown') and not SameText(Format, 'json') then
        raise EMcpToolError.Create('"format" ist markdown oder json');
      Text := '';
      AGroup.UsesGraph.Read(
        procedure(const AUses: TUsesGraph)
        begin
          Text := TMcpDeadCodeTools.UnitDependencies(AUses, UnitName, ARoot, Direction, Transitive,
            SameText(Format, 'json'));
        end);
      Result := Text;
    end);
end;

/// <summary>get_affected_tests (#1353): betroffene Tests der Änderungen gegenüber einer Basis; das Ergebnis im
/// Format json passt mit "run" direkt in run_tests.tests.</summary>
procedure RegisterAffectedTestsTool(AServer: TMcpServer; AGroup: TShellWorkspaceGroup; const ARoot: string;
  const AOptionsFor: TImpactOptionsProvider);
begin
  AServer.AddTool('get_affected_tests',
    'Betroffene Tests einer Änderung (#1353): aus dem Unterschied zur Basis (Git oder SVN wie --changed) die ' +
    'geänderten Routinen, Typen und Konstanten bestimmen, ihre Auswirkungen bis zur Tiefe verfolgen (wie ' +
    'get_impact) und die DUnitX-Testmethoden nennen, die sie erreichen, je mit Grund. Sind mehr als 80 % einer ' +
    'Fixture betroffen, die ganze Fixture. "run" im Format json passt direkt in run_tests.tests; "all" heißt, ' +
    'dass alle Tests nötig sind (Grund in "reason").',
    '{"type":"object","properties":{' +
      '"base":{"type":"string","description":"Git-Ref (Merge-Base mit HEAD) bzw. SVN-Revision; leer = main bzw. ' +
        'BASE"},' +
      '"includeUncommitted":{"type":"boolean","default":true,"description":"Index, Arbeitsverzeichnis und neue ' +
        'Dateien mitzählen"},' +
      '"depth":{"type":"integer","minimum":1,"maximum":5,"description":"Ebenen; leer = tests.affectedDepth"},' +
      '"format":{"type":"string","enum":["text","json","dunitx"],"description":"text (Vorgabe), json oder ' +
        'dunitx (Argument --run:… für die Test-EXE)"}}}',
    function(const AArguments: TJSONObject): string
    var
      mSettings: TServerSettings;
      mFormat: TAffectedFormat;
      mQuery: TShellAffectedQuery;
      mRequest: TAffectedRequest;
      mResolver: TNameResolver;
      mFound: TAffectedResult;
      mProcess: ICompilerProcess;
      mEnsureUnit: TEnsureUnitFunc;
      mReadText: TReferenceReadText;
      mArgument: string;
    begin
      mSettings := AGroup.Main.Configuration.Settings;
      if not mSettings.Tests.Affected then
        raise EMcpToolError.Create(TShellAffectedTests.OffMessage);
      if not TAffectedTests.TryParseFormat(TMcpServer.OptionalString(AArguments, 'format'), mFormat) then
        raise EMcpToolError.Create('"format" ist text, json oder dunitx');
      mQuery := Default(TShellAffectedQuery);
      mQuery.WorkingDir := ARoot;
      mQuery.Base := TMcpServer.OptionalString(AArguments, 'base');
      if (AArguments = nil) or not AArguments.TryGetValue<Boolean>('includeUncommitted', mQuery.IncludeUncommitted)
      then
        mQuery.IncludeUncommitted := True;
      if (AArguments = nil) or not AArguments.TryGetValue<Integer>('depth', mQuery.Depth) then
        mQuery.Depth := 0;
      mReadText :=
        function(const AFileName: string; out AText: string): Boolean
        begin
          Result := TShellBootstrap.ReadSourceText(AFileName, AText);
        end;
      mRequest := Default(TAffectedRequest);
      mRequest.Files := AGroup.AllFiles;
      mRequest.TestPrograms := TShellAffectedTests.TestPrograms(mRequest.Files, mReadText);
      // Treffersicherheit und Zeitlimit wie get_impact; Testunits aus allen Testprogrammen der Gruppe.
      mRequest.Options := AOptionsFor('');
      mRequest.Options.Tests := TShellAffectedTests.TestScope(mSettings.TestUnits.Pattern, mRequest.TestPrograms,
        mReadText);
      mProcess := TProcessRunner.Create;
      // Typisierte Variable: TNameResolver.Create ist überladen.
      mEnsureUnit :=
        function(const AUnitName: string): Boolean
        begin
          Result := AGroup.EnsureUnit(AUnitName);
        end;
      mResolver := TNameResolver.Create(AGroup.Index, mEnsureUnit);
      try
        mResolver.Namespaces := AGroup.Main.Namespaces;
        try
          mFound := TShellAffectedTests.Run(mProcess, mSettings, mQuery, mResolver, AGroup.Index, mRequest, mReadText,
            nil);
        except
          on E: EVcsChanges do
            raise EMcpToolError.Create(E.Message);
        end;
      finally
        mResolver.Free;
      end;
      if mFormat <> TAffectedFormat.DUnitX then
        Exit(TAffectedTests.Render(mFound, mFormat));
      // dunitx: nur das Argument; ohne Argument sagt der Text warum.
      if mFound.All then
        Result := 'Alle Tests nötig: ' + mFound.AllReason
      else if Length(mFound.Tests) = 0 then
        Result := Format('Keine betroffenen Tests gegenüber %s.', [mFound.Base])
      else if TAffectedTests.DUnitXArgument(mFound, mArgument) then
        Result := mArgument
      else
        Result := 'Alle Tests nötig: zu viele Tests für ein --run-Argument';
    end, TMcpToolKind.Process);
end;

/// <summary>get_hotspots (#1354): derselbe Dienst wie atlas/hotspots und --hotspots.</summary>
procedure RegisterHotspotTools(AServer: TMcpServer; AGroup: TShellWorkspaceGroup; AService: THotspotService;
  const ARoot: string);
begin
  AServer.AddTool('get_hotspots',
    'Hotspots (#1354): Units bzw. Methoden, die im Zeitraum oft geändert wurden und zugleich komplex sind ' +
    '(Wert = normierte Änderungen × normierte kognitive Komplexität), mit Änderungen, Autoren, Zeilen, Trend ' +
    'der Komplexität und letzter Änderung aus Git bzw. SVN (vcs.provider). Mit section "coupling" die ' +
    'Änderungskopplung: Dateien, die fast immer zusammen geändert werden, ohne uses-Kante zwischen ihnen. ' +
    'Zeitraum und Mindestzahl gemeinsamer Commits aus hotspots.* in atlas.json. Lesend.',
    '{"type":"object","properties":{' +
      '"level":{"type":"string","enum":["unit","method"],"description":"Ebene; Vorgabe unit"},' +
      '"limit":{"type":"integer","minimum":1,"description":"Länge der Liste; Vorgabe 20"},' +
      '"months":{"type":"integer","minimum":1,"maximum":60,"description":"Zeitraum in Monaten; Vorgabe ' +
        'hotspots.months (12)"},' +
      '"section":{"type":"string","enum":["hotspots","coupling"],"description":"Abschnitt; Vorgabe hotspots"},' +
      '"format":{"type":"string","enum":["text","markdown","json"],"description":"text (Vorgabe), markdown ' +
        'oder json"}}}',
    function(const AArguments: TJSONObject): string
    var
      mSettings: TServerSettings;
      mRequest: THotspotRequest;
      mResult: THotspotResult;
      mSection: THotspotSection;
      mVcs: IHotspotVcs;
      mFormat, mError: string;
      mLimit: Integer;
    begin
      mSettings := AGroup.Main.Configuration.Settings;
      if not mSettings.HotspotsEnabled then
        raise EMcpToolError.Create('Hotspots sind ausgeschaltet (hotspots.enabled)');
      if not THotspotReport.ParseSection(TMcpServer.OptionalString(AArguments, 'section'), mSection) then
        raise EMcpToolError.Create('"section" ist hotspots oder coupling');
      mFormat := TMcpServer.OptionalString(AArguments, 'format');
      if (mFormat <> '') and not SameText(mFormat, 'text') and not SameText(mFormat, 'markdown') and
        not SameText(mFormat, 'json') then
        raise EMcpToolError.Create('"format" ist text, markdown oder json');
      if not AArguments.TryGetValue<Integer>('limit', mLimit) then
        mLimit := THotspotReport.TextLimit;
      if mLimit < 1 then
        raise EMcpToolError.Create('"limit" ist eine ganze Zahl ab 1');
      mRequest := THotspotRequest.FromSettings(mSettings);
      if not TLspHotspots.ApplyOptions(AArguments, mRequest, mError) then
        raise EMcpToolError.Create(mError);
      mRequest.Title := ExtractFileName(ARoot);
      mRequest.Root := ARoot;
      mRequest.Namespaces := AGroup.Main.Namespaces;
      // Umfang wie get_architecture (architecture.scope).
      if mSettings.ArchitectureScope = 'project' then
        mRequest.Files := AGroup.Main.ProjectFiles
      else
        mRequest.Files := AGroup.AllFiles;
      if Length(mRequest.Files) = 0 then
        raise EMcpToolError.Create('Kein Projekt geladen');
      // Ohne Versionsverwaltung ein Hinweis statt einer leeren Liste.
      if not TShellHotspotVcs.Detect(ARoot, mSettings, mVcs, mError) then
        Exit('Keine Hotspots: ' + mError + '. Hotspots brauchen ein Git-Repository oder eine SVN-Arbeitskopie.');
      try
        mResult := AService.Analyze(mRequest, mVcs);
      except
        on E: EHotspots do
          raise EMcpToolError.Create(E.Message);
      end;
      // Der Text kürzt selbst und nennt die Gesamtzahl ("20 von 431").
      if SameText(mFormat, 'json') then
        Result := THotspotReport.Json(TLspHotspots.Limited(mResult, mLimit))
      else if SameText(mFormat, 'markdown') then
        Result := THotspotReport.Markdown(TLspHotspots.Limited(mResult, mLimit))
      else
        Result := THotspotReport.Text(mResult, mSection, mLimit);
    end);
end;

/// <summary>Unit-Name oder Pfad → Datei, geprüft wie Pfadparameter (#99): Units außerhalb des Arbeitsbereichs
/// und seiner Bibliothekspfade ergeben einen Fehler mit Begründung (#1357).</summary>
function UnitFileOf(const AIndex: ISymbolIndex; AGroup: TShellWorkspaceGroup; AGuard: TMcpPathGuard):
  TFunc<string, string>;
begin
  Result :=
    function(AUnit: string): string
    var
      mUnit: TUnitIndex;
    begin
      if (Pos('\', AUnit) > 0) or (Pos('/', AUnit) > 0) or SameText(ExtractFileExt(AUnit), '.pas') then
        Exit(AGuard.Resolve(AUnit));
      // Units anderer Projekte der Gruppe erst bei Bedarf (#1112).
      AGroup.EnsureUnit(AUnit);
      if not AIndex.FindUnit(AUnit, mUnit) then
        raise EMcpToolError.CreateFmt('Unit "%s" ist nicht im Index', [AUnit]);
      Result := AGuard.Resolve(mUnit.FileName);
    end;
end;

/// <summary>Änderungen laut Git oder SVN für prepare_commit (#1357): geänderte Dateien unter ARoot und ihre Befunde
/// in geänderten Zeilen wie --changed-lines, dazu der Commit-Präfix, den das Plugin für das aktuelle Issue in
/// &lt;gitdir&gt;/atlas-commit-prefix schreibt (#765).</summary>
function ChangesOf(AGroup: TShellWorkspaceGroup; const ARoot: string): TMcpChangesFunc;
begin
  Result :=
    function(const ABase: string): TMcpChangeSet
    var
      mSettings: TServerSettings;
      mProcess: ICompilerProcess;
      mVcs: TVcsChanges;
      mFile, mText, mRelative: string;
      mLines: TChangedLines;
      mChanged: TMcpChangedFile;
      mFinding: TRuleFinding;
      mScopes: TFindingScopes;
      mCheckProject: TCheckProjectFunc;
    begin
      Result := Default(TMcpChangeSet);
      Result.Files := nil;
      Result.Base := ABase;
      if Result.Base = '' then
        Result.Base := 'HEAD';
      mSettings := AGroup.Main.Configuration.Settings;
      // Über eine Variable halten: Detect gibt einen Probelauf frei, bevor es den nächsten startet.
      mProcess := TProcessRunner.Create;
      try
        mVcs := TVcsChanges.Detect(mProcess, ARoot, mSettings.VcsProvider, mSettings.VcsGitPath,
          mSettings.VcsSvnPath, mSettings.VcsTimeoutSeconds);
      except
        on E: EVcsChanges do
        begin
          Result.Error := E.Message;
          Exit;
        end;
      end;
      try
        try
          // Ohne Basis: nicht eingecheckte Änderungen gegenüber HEAD (SVN: BASE); mit Basis seit der Abzweigung.
          mVcs.Load(Result.Base, ABase <> '', ABase = '', True, True);
        except
          on E: EVcsChanges do
          begin
            Result.Error := E.Message;
            Exit;
          end;
        end;
        Result.Vcs := mVcs.Name;
        mCheckProject := CheckProjectOf(AGroup);
        for mFile in mVcs.Files do
        begin
          if not TMcpPathGuard.IsInside(ARoot, mFile) then
            Continue;
          mChanged := Default(TMcpChangedFile);
          mRelative := ExtractRelativePath(IncludeTrailingPathDelimiter(ARoot), mFile);
          mChanged.Path := mRelative;
          mChanged.Findings := nil;
          if MatchText(ExtractFileExt(mFile), ['.pas', '.dpr', '.dpk']) and ReadSourceText(mFile, mText) and
            TChangedFiles.LinesOf(mVcs.Lines, mVcs.RepoRoot, mFile, mLines) then
            for mFinding in TFileChecker.CheckText(BuiltinRules, mSettings, mRelative, mText, mCheckProject(mFile),
              AGroup.Main.CheckSource(mFile), mScopes) do
              if mLines.Contains(mFinding.Range.StartPos.Line) then
                mChanged.Findings := mChanged.Findings + [mFinding];
          Result.Files := Result.Files + [mChanged];
        end;
        if mVcs is TGitChanges then
          Result.CommitPrefix := TAtlasCommitHook.ReadPrefix(TAtlasGitVersionControl.GitDir(mVcs.RepoRoot));
      finally
        mVcs.Free;
      end;
    end;
end;

class function TMcpShell.ToolNames: TArray<string>;
var
  Server: TMcpServer;
  Listed: TJSONObject;
  Tool: TJSONValue;
begin
  Result := nil;
  // Nur registrieren, nicht aufrufen: Die Werkzeuge greifen erst beim Aufruf auf ihre Dienste zu.
  Server := TMcpServer.Create('Atlas', '0');
  try
    RegisterTools(Server, nil, nil, nil, '', nil, nil, nil, nil);
    RegisterDeadCodeTools(Server, nil, nil, '', nil);
    RegisterAffectedTestsTool(Server, nil, '', nil);
    RegisterHotspotTools(Server, nil, nil, '');
    RegisterStatusTools(Server, nil, '');
    Listed := Server.ListTools;
    try
      for Tool in Listed.GetValue<TJSONArray>('tools') do
        Result := Result + [Tool.GetValue<string>('name')];
    finally
      Listed.Free;
    end;
  finally
    Server.Free;
  end;
end;

class function TMcpShell.Run(const AOptions: TCommandLineOptions): Integer;
var
  LoggerImpl: TLogger;
  Logger: ILogger;
  Transport: IJsonRpcTransport;
  Dispatcher: TJsonRpcDispatcher;
  Connection: TJsonRpcConnection;
  Server: TMcpServer;
  Tools: TMcpIndexTools;
  Code: TMcpCodeTools;
  Index: ISymbolIndex;
  Store: IDocumentStore;
  Workspace: TShellWorkspace;
  // Hauptprojekt und übrige Projekte der Gruppe in einem Index (Plugin-Units hinter dem Testprojekt).
  Group: TShellWorkspaceGroup;
  Identity: TIndexProcessInfo;
  Guard: TMcpPathGuard;
  Edit: TMcpEditTools;
  Root, Warning: string;
  Anonymizer: ILogAnonymizer;
  AllFiles: TFunc<TArray<string>>;
  Architecture: TArchitectureService;
  Hotspots: THotspotService;
  PathGraphs: TUsesGraphService;
  PathLocator: TUsesLocator;
  PathOptions: TUsesGraphOptions;
  EnsureAny: TFunc<string, Boolean>;
  GlobalSettings: string;
  Prompts: TMcpPrompts;
begin
  LoggerImpl := TLogger.Create;
  Logger := LoggerImpl;
  LoggerImpl.AddSink(TStreamLogSink.Create(TStdStreams.CreateError, True), TLogLevel.Warning);
  TShellDiagnostics.AddLogFile(LoggerImpl, AOptions.LogFile, IntToStr(TParentWatcher.CurrentProcessId),
    AOptions.LogNames, AOptions.LogLevel, Anonymizer);
  for Warning in AOptions.Warnings do
    Logger.Warning(Warning);

  Root := AOptions.McpRoot;
  if Root = '' then
    Root := GetCurrentDir;
  Root := ExcludeTrailingPathDelimiter(TPath.GetFullPath(Root));

  // Ab hier erreichen versehentliche Ausgaben nur noch stderr.
  Transport := TJsonRpcLineTransport.Create(TStdStreams.CreateInput, TStdStreams.ReserveOutputForProtocol, True);
  Index := TSymbolIndex.Create;
  Store := TDocumentStore.Create(
    function(const APath: string): string
    begin
      Result := TShellPlatform.CanonicalizePath(APath);
    end);
  Group := TShellWorkspaceGroup.Create(Root, Store, Logger, Index, 'atlas-mcp-index', ReadSourceText);
  Workspace := Group.Main;
  // Anmeldung am Index-Cache für „Prozesse am Projekt“ (#62); der MCP-Modus läuft für Claude Code.
  Identity := Default(TIndexProcessInfo);
  Identity.Pid := TShellPlatform.CurrentProcessId;
  Identity.Kind := TIndexProcessInfo.KindMcp;
  Identity.Client := 'Claude Code';
  Group.ProcessIdentity := Identity;
  // Globale Einstellungen wie im LSP-Server und im Linter (D-08), abschaltbar mit mcp.globalSettings in
  // atlas.json. Load übernimmt sie, damit der Index nur einmal mit den wirksamen Einstellungen startet.
  GlobalSettings := '';
  if TShellBootstrap.ProjectSettings(Root).McpGlobalSettings then
    GlobalSettings := TShellBootstrap.LoadGlobalSettings(Logger)
  else
    Logger.Info('Globale Einstellungen ausgeschaltet (mcp.globalSettings)');
  AllFiles :=
    function: TArray<string>
    begin
      Result := Group.AllFiles;
    end;
  EnsureAny :=
    function(AUnitName: string): Boolean
    begin
      Result := Group.EnsureUnit(AUnitName);
    end;
  Tools := TMcpIndexTools.Create(Index, ReadSourceText);
  // Begründungen (#1123): Einstellungen und ADR-Ordner des Arbeitsbereichs.
  Tools.RationaleOptionsFunc :=
    function: TRationaleOptions
    begin
      Result := TRationaleOptions.FromSettings(Workspace.Configuration.Settings, Root);
    end;
  // Package einer Unit: .dpk unter dem Projektordner, deren contains sie führt.
  Tools.PackageOf :=
    function(const AUnitName: string): string
    var
      Dpk, Text: string;
    begin
      Result := '';
      for Dpk in TDirectory.GetFiles(Root, '*.dpk', TSearchOption.soAllDirectories) do
        if ReadSourceText(Dpk, Text) and TMcpIndexTools.PackageContains(Text, AUnitName) then
          Exit(ChangeFileExt(ExtractFileName(Dpk), ''));
    end;
  Code := TMcpCodeTools.Create(Index, ReadSourceText,
    function: TArray<string>
    begin
      Result := AllFiles();
    end,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureAny(AUnitName);
    end);
  // Pfadregeln (#99): Arbeitsordner und Include-Pfade, Verknüpfungen aufgelöst.
  Guard := TMcpPathGuard.Create(Root,
    function: TArray<string>
    begin
      Result := Workspace.IncludePaths;
    end,
    function(APath: string): string
    begin
      Result := TShellPlatform.CanonicalizePath(APath);
    end);
  Edit := TMcpEditTools.Create(Index, ReadSourceText, WriteSourceText,
    function: TArray<string>
    begin
      Result := AllFiles();
    end,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureAny(AUnitName);
    end);
  Edit.DirtyFiles := EditorDirtyFiles;
  // Architekturübersicht (#1118): derselbe Dienst wie atlas/architecture und --architecture.
  Architecture := TArchitectureService.Create(Index,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end,
    function(const AFileName: string): TArray<string>
    begin
      // Defines des Projekts, zu dem die Datei gehört (Projektgruppe, #1112).
      if not Group.WorkspaceOf(AFileName).Defines(Result) then
        Result := nil;
    end);
  // Hotspots (#1354): derselbe Dienst wie atlas/hotspots und --hotspots.
  Hotspots := THotspotService.Create(Index,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end);
  // Weg zwischen Symbolen (#1117): eigener Uses-Graph samt Bibliotheks-Units (Start oder Ziel).
  PathOptions := TUsesGraphOptions.Default;
  PathOptions.IncludeLibrary := True;
  PathGraphs := TUsesGraphService.Create(Index, PathOptions);
  PathLocator := TUsesLocator.Create(
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadSourceText(AFileName, AText);
    end,
    function(const AFileName: string): TArray<string>
    begin
      // Defines des Projekts, zu dem die Datei gehört (Projektgruppe, #1112).
      if not Group.WorkspaceOf(AFileName).Defines(Result) then
        Result := nil;
    end);
  // Regelprüfung mit den Symbolen und Include-Dateien des Projekts (#860).
  Edit.CheckSource := CheckSourceOf(Group);
  Code.CheckSource := Edit.CheckSource;
  // Prüfregeln mit Symbolindex und Projektdiensten wie im Server (#1112).
  Edit.CheckProject := CheckProjectOf(Group);
  Code.CheckProject := Edit.CheckProject;
  // Treffersicherheit wie im Editor (#1119).
  Code.SettingsFor :=
    function(const AUri: string): TReferenceSettings
    begin
      Result := Workspace.Configuration.Settings.References;
    end;
  Edit.SettingsFor := Code.SettingsFor;
  // Auswirkungsanalyse (#1120): Tiefe aus navigation, Testunits aus testUnits und dem Testprogramm.
  Code.ImpactOptionsFor :=
    function(const AUri: string): TImpactOptions
    var
      Settings: TServerSettings;
      Project, Candidate, Text: string;
      Info: TProjectInfo;
    begin
      Settings := Workspace.Configuration.Settings;
      Result := TImpactOptions.Default;
      Result.Depth := Settings.Navigation.ImpactDepth;
      Result.References := Settings.References;
      // Kein Watchdog wie im LSP: großzügig, die Antwort meldet das erreichte Limit.
      Result.TimeoutMs := 60000;
      Project := Settings.TestUnits.Project;
      if (Project <> '') and not TPath.IsPathRooted(Project) then
        Project := TPath.Combine(Root, Project);
      if Project = '' then
        for Candidate in ProjectFilesUnder(Root) do
          if IsTestProject(Candidate) then
          begin
            Project := Candidate;
            Break;
          end;
      Text := '';
      if (Project <> '') and FileExists(ChangeFileExt(Project, '.dproj')) and
        LoadProject(ChangeFileExt(Project, '.dproj'), '', '', Info) and (Info.MainSource <> '') then
        Project := Info.MainSource
      else if Project <> '' then
        Project := ChangeFileExt(Project, '.dpr');
      if (Project <> '') and not ReadSourceText(Project, Text) then
        Text := '';
      Result.Tests := TImpactTestScope.FromProgram(Settings.TestUnits.Pattern, Text);
    end;
  Edit.Audit :=
    procedure(const AText: string)
    begin
      Logger.Info(AText);
    end;
  Server := TMcpServer.Create(TProductVersion.Name, TProductVersion.Version);
  Prompts := nil;
  Dispatcher := TJsonRpcDispatcher.Create;
  Connection := TJsonRpcConnection.Create(Transport, Dispatcher);
  try
    Server.Instructions := 'Delphi-Projekt in ' + Root + '. Für Fragen zu Typen, Units und Formularen ' +
      'zuerst diese Werkzeuge nutzen statt Quelldateien vollständig zu lesen.';
    RegisterTools(Server, Tools, Code, Group, Root, Guard, Edit,
      function(ASection: TArchitectureSection; const AUnit, ACompareWith: string; AResolution: Double): string
      var
        Settings: TServerSettings;
        Request: TArchitectureRequest;
        Overview: TArchitectureOverview;
        Comparison: TArchitectureComparison;
        FailOn: TArchitectureFailKinds;
        Error: string;
      begin
        Settings := Workspace.Configuration.Settings;
        if not Settings.ArchitectureEnabled then
          raise EMcpToolError.Create('Architekturübersicht ist ausgeschaltet (architecture.enabled)');
        Request := TArchitectureRequest.FromSettings(Settings);
        // Nur für diesen Aufruf (#1366); die Einstellung bleibt.
        if AResolution > 0 then
          Request.Grouping.Resolution := AResolution;
        Request.Title := ExtractFileName(Root);
        Request.Root := Root;
        Request.Namespaces := Workspace.Namespaces;
        // Projektgruppe (#648): die Dateien aller geladenen Projekte, sonst nur die des Hauptprojekts.
        if Request.Scope = 'project' then
          Request.Files := Workspace.ProjectFiles
        else
          Request.Files := AllFiles();
        if Length(Request.Files) = 0 then
          raise EMcpToolError.Create('Kein Projekt geladen');
        // Derselbe zuletzt berechnete Stand wie im LSP-Prozess (#1367).
        Request.PreviousFile := TIndexCacheDirectory.ArchitectureFileFor(TIndexCacheDirectory.DefaultRoot,
          Request.ScopeKey);
        Overview := Architecture.Overview(Request);
        if ACompareWith <> '' then
        begin
          if not TArchitectureComparer.CompareWithFile(ACompareWith, Overview, Comparison, Error) then
            raise EMcpToolError.Create(Error);
          if not TArchitectureComparer.ParseKinds(Settings.ArchitectureFailOn, FailOn, Error) then
            FailOn := TArchitectureComparer.DefaultFailOn;
          Result := TArchitectureComparer.Text(Comparison, FailOn, TArchitectureReport.TextLimit);
        end
        else if AUnit <> '' then
          Result := TArchitectureReport.UnitText(Overview, AUnit)
        else
          Result := TArchitectureReport.Text(Overview, ASection, TArchitectureReport.TextLimit);
      end, FindPathOf(Index, PathGraphs, PathLocator, Workspace, EnsureAny, Root));
    RegisterDeadCodeTools(Server, Group, Index, Root, Guard);
    RegisterAffectedTestsTool(Server, Group, Root, Code.ImpactOptionsFor);
    RegisterHotspotTools(Server, Group, Hotspots, Root);
    RegisterStatusTools(Server, Index, Root);
    // Sicherheit (#99).
    Server.Restricted := AOptions.Restricted;
    Server.OnDisabledTools :=
      function: TArray<string>
      begin
        Result := Workspace.Configuration.Settings.McpDisabledTools;
        // Abgeschaltete Funktion (#227): Werkzeug gar nicht anbieten.
        if not Workspace.Configuration.Settings.ArchitectureEnabled then
          Result := Result + ['get_architecture'];
        if not Workspace.Configuration.Settings.HotspotsEnabled then
          Result := Result + ['get_hotspots'];
        if not Workspace.Configuration.Settings.Navigation.SymbolPath then
          Result := Result + ['find_path'];
        // Betroffene Tests (#1353).
        if not Workspace.Configuration.Settings.Tests.Affected then
          Result := Result + ['get_affected_tests'];
      end;
    Server.OnAudit :=
      procedure(AText: string)
      begin
        Logger.Info(AText);
      end;
    // Projektkonventionen (#272).
    Server.AddResource('delphi://conventions', 'Projektkonventionen',
      'Regelprofil, Formatstil, Benennungsregeln und aktive Prüfregeln des Projekts als Markdown.', 'text/markdown',
      function: string
      var
        Catalog: TRuleCatalog;
      begin
        Catalog := TFindingPrompt.GermanCatalog;
        try
          Result := TRuleConventions.Markdown(BuiltinRules, Workspace.Configuration.Settings, Catalog);
        finally
          Catalog.Free;
        end;
      end);
    // Prompts und Ressourcenvorlagen (#1357), abschaltbar mit mcp.prompts.
    Prompts := TMcpPrompts.Create(Server,
      function: TServerSettings
      begin
        Result := Workspace.Configuration.Settings;
      end);
    Prompts.ReadText := ReadSourceText;
    Prompts.ResolveFile :=
      function(APath: string): string
      begin
        Result := Guard.Resolve(APath);
      end;
    Prompts.ResolveUnit := UnitFileOf(Index, Group, Guard);
    Prompts.Changes := ChangesOf(Group, Root);
    Prompts.Register;
    // Vor jedem Werkzeugaufruf geänderte Projektdateien nachladen (#48).
    Server.OnBeforeToolCall :=
      procedure
      var
        Changes: TArray<TFileChange>;
      begin
        Changes := TMcpFreshness.Changes(Index, TDiskIndexFileSystem.Create, AllFiles());
        if Length(Changes) > 0 then
        begin
          Logger.Info(Format('%d geänderte Dateien nachgeladen, %d Units aktualisiert',
            [Length(Changes), Workspace.ApplyChanges(Changes)]));
          Group.Invalidate;
        end;
      end;
    Server.Attach(Dispatcher);
    Connection.OnError :=
      procedure(const AError: Exception)
      begin
        Logger.Error(Format('MCP: %s: %s', [AError.ClassName, AError.Message]));
      end;
    Logger.Info(Format('%s %s im MCP-Modus für %s', [TProductVersion.Name, TProductVersion.Version, Root]));
    // Mit index.projectGroup auch die übrigen Projekte der Gruppe.
    Group.Load(GlobalSettings);
    try
      Connection.Run;
      Result := 0;
    except
      on E: Exception do
      begin
        Logger.Error('MCP-Server abgebrochen: ' + E.Message);
        Result := 1;
      end;
    end;
    Group.Stop;
  finally
    Connection.Free;
    Dispatcher.Free;
    Server.Free;
    Prompts.Free;
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
end;

end.
