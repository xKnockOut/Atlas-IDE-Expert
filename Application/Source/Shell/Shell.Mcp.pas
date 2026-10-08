unit Shell.Mcp;

// Host-Rolle Shell: MCP-Modus (--mcp, #48). Bietet den Symbolindex eines
// Projektordners über das Model Context Protocol an, z. B. für Claude Code:
//
//   claude mcp add delphi -- BetterDelphiLSP.exe --mcp --root C:\Projekte\App
//
// stdout gehört dem Protokoll (eine JSON-Nachricht je Zeile); Meldungen gehen
// auf stderr und in die Logdatei.

interface

uses
  Shell.CommandLine;

type
  TMcpShell = class
  public
    /// <summary>Läuft, bis der Client die Eingabe schließt; liefert den Exit-Code.</summary>
    class function Run(const AOptions: TCommandLineOptions): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  BDLsp.Common.Product.Version,
  BDLsp.Common.Logging.Contract,
  BDLsp.Common.Logging.Providers.Logger,
  BDLsp.Common.Logging.Providers.StreamSink,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.JsonRpc.Dispatcher,
  BDLsp.Common.JsonRpc.Connection,
  BDLsp.Common.JsonRpc.LineTransport,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Documents.Providers.DocumentStore,
  BDLsp.Common.Documents.FileEncoding,
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Index.SymbolIndex,
  BDLsp.Common.Dfm.Parser,
  BDLsp.Common.Mcp.Server,
  BDLsp.Common.Mcp.IndexTools,
  BDLsp.Common.Mcp.CodeTools,
  BDLsp.Common.Rules.Builtin,
  BDLsp.Windows.Console.StdStreams,
  BDLsp.Windows.Documents.PathCanonicalizer,
  Shell.Workspace;

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
  AWorkspace: TShellWorkspace; const ARoot: string);
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
      begin
        if TPath.IsRelativePath(FileName) then
          FileName := TPath.Combine(ARoot, FileName);
        Files := [FileName];
      end
      else
        Files := AWorkspace.ProjectFiles;
      if Length(Files) = 0 then
        raise EMcpToolError.Create('Kein Projekt geladen; Datei angeben');
      Result := TMcpCodeTools.Diagnostics(BuiltinRules, AWorkspace.Configuration.Settings, ARoot, Files,
        ReadSourceText);
    end);
  AServer.AddTool('get_dfm_info',
    'Komponenten eines Formulars (.dfm/.fmx in Textform) mit Typen, Eigenschaften und Ereignisbehandlern.',
    TMcpServer.StringSchema(['file'], ['Pfad der .dfm/.fmx-Datei oder der zugehörigen .pas-Datei']),
    function(const AArguments: TJSONObject): string
    var
      FileName, Text: string;
    begin
      FileName := TMcpServer.RequiredString(AArguments, 'file');
      if TPath.IsRelativePath(FileName) then
        FileName := TPath.Combine(ARoot, FileName);
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
  Root, Warning: string;
begin
  LoggerImpl := TLogger.Create;
  Logger := LoggerImpl;
  LoggerImpl.AddSink(TStreamLogSink.Create(TStdStreams.CreateError, True), TLogLevel.Warning);
  if AOptions.LogFile <> '' then
    try
      LoggerImpl.AddSink(TStreamLogSink.CreateForFile(AOptions.LogFile), AOptions.LogLevel);
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
    'bdlsp-mcp-index');
  Tools := TMcpIndexTools.Create(Index, ReadSourceText);
  Code := TMcpCodeTools.Create(Index, ReadSourceText,
    function: TArray<string>
    begin
      Result := Workspace.ProjectFiles;
    end,
    function(const AUnitName: string): Boolean
    begin
      Result := Workspace.EnsureUnit(AUnitName);
    end);
  Server := TMcpServer.Create(TProductVersion.Name, TProductVersion.Version);
  Dispatcher := TJsonRpcDispatcher.Create;
  Connection := TJsonRpcConnection.Create(Transport, Dispatcher);
  try
    Server.Instructions := 'Delphi-Projekt in ' + Root + '. Für Fragen zu Typen, Units und Formularen ' +
      'zuerst diese Werkzeuge nutzen statt Quelldateien vollständig zu lesen.';
    RegisterTools(Server, Tools, Code, Workspace, Root);
    Server.Attach(Dispatcher);
    Connection.OnError :=
      procedure(const AError: Exception)
      begin
        Logger.Error(Format('MCP: %s: %s', [AError.ClassName, AError.Message]));
      end;
    Logger.Info(Format('%s %s im MCP-Modus für %s', [TProductVersion.Name, TProductVersion.Version, Root]));
    Workspace.Load;
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
    Workspace.Stop;
  finally
    Connection.Free;
    Dispatcher.Free;
    Server.Free;
    Code.Free;
    Tools.Free;
    Workspace.Free;
  end;
end;

end.
