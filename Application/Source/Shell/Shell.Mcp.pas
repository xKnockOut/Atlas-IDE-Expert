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
  Winapi.Windows,
  System.SysUtils,
  System.IOUtils,
  System.StrUtils,
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
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.IndexTools,
  Atlas.Common.Mcp.CodeTools,
  Atlas.Common.Mcp.BuildTools,
  Atlas.Common.Mcp.Paths,
  Atlas.Common.Mcp.Freshness,
  Atlas.Common.Mcp.EditTools,
  Atlas.Common.Mcp.IdeEdits,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.Prompt,
  Atlas.Common.Rules.Conventions,
  Atlas.Common.Index.Adapters.DiskFileSystem,
  Atlas.Common.Lsp.IdeBuild,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Projects.GroupReader,
  System.Generics.Collections,
  Atlas.Windows.Console.StdStreams,
  Atlas.Windows.Process.ParentWatcher,
  Atlas.Windows.Documents.PathCanonicalizer,
  Atlas.Common.Diagnostics.Anonymizer,
  Shell.Workspace,
  Shell.Diagnostics;

type
  /// <summary>Nimmt die LSP-Benachrichtigungen des Arbeitsbereichs (Fortschritt,
  /// logMessage) auf und verwirft sie; im MCP-Modus gibt es keinen LSP-Client.</summary>
  TSilentTransport = class(TInterfacedObject, IJsonRpcTransport)
  public
    function ReadMessage: TJSONObject;
    procedure WriteMessage(const AMessage: TJSONObject);
  end;

function TSilentTransport.ReadMessage: TJSONObject;
begin
  raise EJsonRpcTransportClosed.Create('Kein LSP-Client im MCP-Modus');
end;

procedure TSilentTransport.WriteMessage(const AMessage: TJSONObject);
begin
end;

/// <summary>Läuft der Prozess noch?</summary>
function ProcessRunning(APid: Cardinal): Boolean;
const
  QueryLimitedInformation = $1000;
var
  Process: THandle;
  Code: Cardinal;
begin
  Process := OpenProcess(QueryLimitedInformation, False, APid);
  if Process = 0 then
    Exit(False);
  try
    Result := GetExitCodeProcess(Process, Code) and (Code = STILL_ACTIVE);
  finally
    CloseHandle(Process);
  end;
end;

/// <summary>Im Editor der IDE ungespeichert geänderte Dateien: editor-dirty-<pid>.json je laufender IDE.</summary>
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
      Text := TFile.ReadAllText(FileName, TEncoding.UTF8);
    except
      on Exception do
        Continue;
    end;
    Json := TJSONObject.ParseJSONValue(Text);
    try
      if not (Json is TJSONObject) or not TJSONObject(Json).TryGetValue<Integer>('pid', Pid) or
        not ProcessRunning(Cardinal(Pid)) then
        Continue;
      if TJSONObject(Json).GetValue('files') is TJSONArray then
        for Item in TJSONArray(TJSONObject(Json).GetValue('files')) do
          Result := Result + [Item.Value];
    finally
      Json.Free;
    end;
  end;
end;

/// <summary>Prozess der IDE, in der AFileName offen ist ("open" in editor-dirty-<pid>.json, #397); 0 ohne.</summary>
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
      Text := TFile.ReadAllText(FileName, TEncoding.UTF8);
    except
      on Exception do
        Continue;
    end;
    Json := TJSONObject.ParseJSONValue(Text);
    try
      if not (Json is TJSONObject) or not TJSONObject(Json).TryGetValue<Integer>('pid', Pid) or
        not ProcessRunning(Cardinal(Pid)) or not (TJSONObject(Json).GetValue('open') is TJSONArray) then
        Continue;
      for Item in TJSONArray(TJSONObject(Json).GetValue('open')) do
        if SameText(Item.Value, AFileName) then
          Exit(Cardinal(Pid));
    finally
      Json.Free;
    end;
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
        Sleep(20);
      end,
      function: Int64
      begin
        Result := GetTickCount64;
      end, Reason) of
      TMcpIdeEditOutcome.Applied:
        Exit;
      TMcpIdeEditOutcome.Failed:
        raise Exception.CreateFmt('IDE: %s', [Reason]);
    end;
  TFileEncoding.SaveToFile(AFileName, AText, FileFormat);
end;

/// <summary>dryRun-Argument; Vorgabe true (#61).</summary>
function DryRunOf(const AArguments: TJSONObject): Boolean;
begin
  if (AArguments = nil) or not AArguments.TryGetValue<Boolean>('dryRun', Result) then
    Result := True;
end;

function ReadSourceText(const AFileName: string; out AText: string): Boolean;
var
  FileFormat: TFileFormat;
begin
  Result := FileExists(AFileName);
  if Result then
    AText := TFileEncoding.LoadFromFile(AFileName, FileFormat)
  else
    AText := '';
end;

procedure RegisterTools(AServer: TMcpServer; ATools: TMcpIndexTools; ACode: TMcpCodeTools;
  AWorkspace: TShellWorkspace; const ARoot: string; AGuard: TMcpPathGuard; AEdit: TMcpEditTools);
begin
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
    'Vollständiger Quelltext der Deklaration eines Symbols, auch aus RTL/VCL, ohne die ganze Datei zu lesen.',
    TMcpServer.StringSchema(['name'], ['Symbolname, am besten qualifiziert (TFoo.Bar)']),
    function(const AArguments: TJSONObject): string
    begin
      Result := ATools.Declaration(TMcpServer.RequiredString(AArguments, 'name'));
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
      ACode.Namespaces := AWorkspace.Namespaces;
      Result := ACode.References(TMcpServer.RequiredString(AArguments, 'name'));
    end);
  AServer.AddTool('get_call_hierarchy',
    'Aufrufer (incoming) und aufgerufene Routinen (outgoing) einer Methode oder Routine.',
    TMcpServer.StringSchema(['name', 'direction'],
      ['Methode oder Routine, z. B. TFoo.Bar', 'incoming, outgoing oder both (Standard)'], 1),
    function(const AArguments: TJSONObject): string
    begin
      ACode.Namespaces := AWorkspace.Namespaces;
      Result := ACode.CallHierarchy(TMcpServer.RequiredString(AArguments, 'name'),
        TMcpCodeTools.ParseDirection(TMcpServer.OptionalString(AArguments, 'direction')));
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
      ACode.Namespaces := AWorkspace.Namespaces;
      Result := ACode.QualifiedName(FileName, Line, Column, WithParameters);
    end);
  AServer.AddTool('get_diagnostics',
    'Syntaxfehler und Befunde der Prüfregeln (wie --check) für eine Datei oder das ganze Projekt.',
    TMcpServer.StringSchema(['file'], ['Pfad einer .pas-Datei; leer = alle Projektdateien'], 0),
    function(const AArguments: TJSONObject): string
    var
      FileName: string;
      Files: TArray<string>;
    begin
      FileName := TMcpServer.OptionalString(AArguments, 'file');
      if FileName <> '' then
        Files := [AGuard.Resolve(FileName)]
      else
        Files := AWorkspace.ProjectFiles;
      if Length(Files) = 0 then
        raise EMcpToolError.Create('Kein Projekt geladen; Datei angeben');
      Result := TMcpCodeTools.Diagnostics(BuiltinRules, AWorkspace.Configuration.Settings, ARoot, Files,
        ReadSourceText);
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
      Result := ACode.CheckCode(BuiltinRules, AWorkspace.Configuration.Settings, ARoot, FileName, Text,
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
        for Finding in TFileChecker.CheckText(BuiltinRules, AWorkspace.Configuration.Settings, RelativePath, Text) do
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
      AEdit.Namespaces := AWorkspace.Namespaces;
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
      Result := AEdit.ApplyCodeAction(BuiltinRules, AWorkspace.Configuration.Settings, ARoot, FileName, Line,
        TMcpServer.OptionalString(AArguments, 'title'), DryRunOf(AArguments));
    end, TMcpToolKind.Write);
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
    RegisterTools(Server, nil, nil, nil, '', nil, nil);
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
// Projekte der einzigen .groupproj im Ordner (wie der LSP-Server ohne IDE, #648); sonst leer.
function GroupProjects(const ARoot: string; const ALogger: ILogger): TArray<string>;
var
  Groups: TArray<string>;
begin
  Result := nil;
  try
    Groups := TDirectory.GetFiles(ARoot, '*.groupproj');
    if Length(Groups) <> 1 then
      Exit;
    Result := TGroupProjReader.Load(Groups[0]);
    ALogger.Info(Format('Projektgruppe %s: %d Projekte', [Groups[0], Length(Result)]));
  except
    on E: Exception do
    begin
      ALogger.Warning('Projektgruppe nicht lesbar: ' + E.Message);
      Result := nil;
    end;
  end;
end;

class function TMcpShell.Run(const AOptions: TCommandLineOptions): Integer;
var
  LoggerImpl: TLogger;
  Logger: ILogger;
  Transport, Silent: IJsonRpcTransport;
  Dispatcher: TJsonRpcDispatcher;
  Connection: TJsonRpcConnection;
  Server: TMcpServer;
  Tools: TMcpIndexTools;
  Code: TMcpCodeTools;
  Index: ISymbolIndex;
  Store: IDocumentStore;
  Workspace: TShellWorkspace;
  Guard: TMcpPathGuard;
  Edit: TMcpEditTools;
  Root, Warning: string;
  Anonymizer: ILogAnonymizer;
  // Weitere Projekte der Gruppe, gleicher Index wie Workspace (Plugin-Units hinter dem Testprojekt).
  Others: TObjectList<TShellWorkspace>;
  Other: TShellWorkspace;
  Main: TProjectInfo;
  ProjectFile: string;
  AllFiles: TFunc<TArray<string>>;
  EnsureAny: TFunc<string, Boolean>;
begin
  Others := TObjectList<TShellWorkspace>.Create(True);
  LoggerImpl := TLogger.Create;
  Logger := LoggerImpl;
  LoggerImpl.AddSink(TStreamLogSink.Create(TStdStreams.CreateError, True), TLogLevel.Warning);
  if AOptions.LogFile <> '' then
    try
      LoggerImpl.AddSink(TShellDiagnostics.LogFileSink(AOptions.LogFile, IntToStr(TParentWatcher.CurrentProcessId),
        AOptions.LogNames, Anonymizer), AOptions.LogLevel);
    except
      on E: Exception do
        Logger.Error(Format('Logdatei "%s" kann nicht geöffnet werden: %s', [AOptions.LogFile, E.Message]));
    end;
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
      Result := TWindowsPathCanonicalizer.Canonicalize(APath);
    end);
  Silent := TSilentTransport.Create;
  Workspace := TShellWorkspace.Create(Root, ExtractFileName(Root), Store, Silent, Logger, Index,
    'atlas-mcp-index');
  AllFiles :=
    function: TArray<string>
    var
      Item: TShellWorkspace;
    begin
      Result := Workspace.ProjectFiles;
      for Item in Others do
        Result := Result + Item.ProjectFiles;
    end;
  EnsureAny :=
    function(AUnitName: string): Boolean
    var
      Item: TShellWorkspace;
    begin
      Result := Workspace.EnsureUnit(AUnitName);
      for Item in Others do
        if not Result then
          Result := Item.EnsureUnit(AUnitName);
    end;
  Tools := TMcpIndexTools.Create(Index, ReadSourceText);
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
      Result := TWindowsPathCanonicalizer.Canonicalize(APath);
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
  Edit.Audit :=
    procedure(const AText: string)
    begin
      Logger.Info(AText);
    end;
  Server := TMcpServer.Create(TProductVersion.Name, TProductVersion.Version);
  Dispatcher := TJsonRpcDispatcher.Create;
  Connection := TJsonRpcConnection.Create(Transport, Dispatcher);
  try
    Server.Instructions := 'Delphi-Projekt in ' + Root + '. Für Fragen zu Typen, Units und Formularen ' +
      'zuerst diese Werkzeuge nutzen statt Quelldateien vollständig zu lesen.';
    RegisterTools(Server, Tools, Code, Workspace, Root, Guard, Edit);
    // Sicherheit (#99).
    Server.Restricted := AOptions.Restricted;
    Server.OnDisabledTools :=
      function: TArray<string>
      begin
        Result := Workspace.Configuration.Settings.McpDisabledTools;
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
    // Vor jedem Werkzeugaufruf geänderte Projektdateien nachladen (#48).
    Server.OnBeforeToolCall :=
      procedure
      var
        Changes: TArray<TFileChange>;
      begin
        Changes := TMcpFreshness.Changes(Index, TDiskIndexFileSystem.Create, AllFiles());
        if Length(Changes) > 0 then
          Logger.Info(Format('%d geänderte Dateien nachgeladen, %d Units aktualisiert',
            [Length(Changes), Workspace.ApplyChanges(Changes)]));
      end;
    Server.Attach(Dispatcher);
    Connection.OnError :=
      procedure(const AError: Exception)
      begin
        Logger.Error(Format('MCP: %s: %s', [AError.ClassName, AError.Message]));
      end;
    Logger.Info(Format('%s %s im MCP-Modus für %s', [TProductVersion.Name, TProductVersion.Version, Root]));
    Workspace.Load;
    // Übrige Projekte der Gruppe (index.projectGroup, Standard an): Sonst fehlen z. B. Units, die nur
    // ein Package enthält, wenn atlas.json auf ein anderes Projekt zeigt.
    if Workspace.Configuration.Settings.IndexProjectGroup then
      for ProjectFile in GroupProjects(Root, Logger) do
      begin
        if Workspace.Project(Main) and SameText(Main.FileName, ProjectFile) then
          Continue;
        Other := TShellWorkspace.Create(ExtractFileDir(ProjectFile), ChangeFileExt(ExtractFileName(ProjectFile), ''),
          Store, Silent, Logger, Index, Format('atlas-mcp-index-%d', [Others.Count + 1]));
        Other.ProjectFile := ProjectFile;
        Others.Add(Other);
        Other.Load;
      end;
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
    for Other in Others do
      Other.Stop;
    Workspace.Stop;
  finally
    Others.Free;
    Connection.Free;
    Dispatcher.Free;
    Server.Free;
    Guard.Free;
    Edit.Free;
    Code.Free;
    Tools.Free;
    Workspace.Free;
  end;
end;

end.
