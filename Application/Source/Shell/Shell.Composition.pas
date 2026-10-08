unit Shell.Composition;

// Host-Rolle Shell: Komposition des Servers von Hand (DI-Strategie ohne Container).
// Verbindet stdin/stdout, Transport, Dispatcher, Lebenszyklus, Dokumentverwaltung,
// Syntaxdiagnosen, Nachrichtenschleife, Logging, Zeitlimit für Anfragen und
// Absturzprotokoll mit Stacktrace.

interface

uses
  System.SysUtils,
  System.JSON,
  BDLsp.Common.Logging.Contract,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.JsonRpc.Dispatcher,
  BDLsp.Common.JsonRpc.Connection,
  BDLsp.Common.JsonRpc.Watchdog,
  BDLsp.Common.Lsp.Lifecycle,
  BDLsp.Common.Lsp.TextDocumentSync,
  BDLsp.Common.Lsp.SyntaxDiagnostics,
  BDLsp.Common.Lsp.DocumentSymbols,
  BDLsp.Common.Lsp.FoldingRanges,
  BDLsp.Common.Lsp.SelectionRanges,
  BDLsp.Common.Lsp.Configuration,
  BDLsp.Common.Documents.Contract,
  Shell.CommandLine;

type
  TServerComposition = class
  private
    FTransport: IJsonRpcTransport;
    FLogger: ILogger;
    FDispatcher: TJsonRpcDispatcher;
    FLifecycle: TLspLifecycle;
    FDocuments: IDocumentStore;
    FTextDocumentSync: TLspTextDocumentSync;
    FSyntaxDiagnostics: TLspSyntaxDiagnostics;
    FDocumentSymbols: TLspDocumentSymbols;
    FFoldingRanges: TLspFoldingRanges;
    FSelectionRanges: TLspSelectionRanges;
    FConfiguration: TLspConfiguration;
    FConnection: TJsonRpcConnection;
    class function BuildCapabilities: TJSONObject; static;
    /// <summary>Fehlerbeschreibung mit letzter Nachricht und Stacktrace für das Log.</summary>
    function DescribeFailure(const AError: Exception): string;
  public const
    /// <summary>Anfragen, die länger laufen, werden abgebrochen und gemeldet.</summary>
    RequestTimeoutMs = 10000;
  public
    constructor Create(const ATransport: IJsonRpcTransport; const ALogger: ILogger);
    destructor Destroy; override;
    /// <summary>Komposition mit stdin/stdout des Prozesses und Logging nach AOptions.</summary>
    class function CreateForStdio(const AOptions: TCommandLineOptions): TServerComposition; static;
    /// <summary>Verarbeitet Nachrichten bis exit oder Ende der Eingabe und liefert den Exit-Code.</summary>
    function Run: Integer;
    property Logger: ILogger read FLogger;
    /// <summary>Geöffnete Dokumente, für Features, die Dateien auswerten.</summary>
    property Documents: IDocumentStore read FDocuments;
    /// <summary>Einstellungen aus delphi-lsp.json.</summary>
    property Configuration: TLspConfiguration read FConfiguration;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  BDLsp.Common.Product.Version,
  BDLsp.Common.Logging.Providers.Logger,
  BDLsp.Common.Logging.Providers.StreamSink,
  BDLsp.Common.JsonRpc.StreamTransport,
  BDLsp.Common.JsonRpc.TracingTransport,
  BDLsp.Common.Lsp.Adapters.LogMessageSink,
  BDLsp.Common.Documents.Providers.DocumentStore,
  BDLsp.Common.Documents.FileEncoding,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Windows.Console.StdStreams,
  BDLsp.Windows.Documents.PathCanonicalizer,
  BDLsp.Windows.Diagnostics.Adapters.DebugOutputSink,
  BDLsp.Windows.Diagnostics.StackTrace;

function CreateTraceStream(const AFileName: string): TStream;
var
  Directory: string;
begin
  Directory := TPath.GetDirectoryName(TPath.GetFullPath(AFileName));
  if Directory <> '' then
    ForceDirectories(Directory);
  Result := TFileStream.Create(AFileName, fmCreate or fmShareDenyWrite);
end;

{ TServerComposition }

constructor TServerComposition.Create(const ATransport: IJsonRpcTransport; const ALogger: ILogger);
begin
  inherited Create;
  FTransport := ATransport;
  FLogger := ALogger;
  FDispatcher := TJsonRpcDispatcher.Create;
  FDispatcher.Watchdog := TJsonRpcWatchdog.Create(FDispatcher.PendingRequests, RequestTimeoutMs,
    procedure(const AMethod: string; ATimeoutMs: Cardinal)
    begin
      FLogger.Warning(Format('Anfrage %s nach %d ms abgebrochen (Zeitlimit)', [AMethod, ATimeoutMs]));
    end);
  FDispatcher.OnRequestFailed :=
    procedure(const AMethod: string; const AParams: TJSONValue; const AError: Exception)
    var
      Params: string;
    begin
      Params := '';
      if AParams <> nil then
        Params := AParams.ToJSON;
      if Length(Params) > 500 then
        Params := Copy(Params, 1, 500) + '…';
      FLogger.Error(Format('Anfrage %s fehlgeschlagen: %s: %s%sParameter: %s%s%s',
        [AMethod, AError.ClassName, AError.Message, sLineBreak, Params, sLineBreak, AError.StackTrace]));
    end;
  FLifecycle := TLspLifecycle.Create(TProductVersion.Name, TProductVersion.Version,
    function: TJSONObject
    begin
      Result := BuildCapabilities;
    end);
  FLifecycle.Attach(FDispatcher);
  FDocuments := TDocumentStore.Create(
    function(const APath: string): string
    begin
      Result := TWindowsPathCanonicalizer.Canonicalize(APath);
    end);
  FTextDocumentSync := TLspTextDocumentSync.Create(FDocuments);
  FTextDocumentSync.Attach(FDispatcher);
  FSyntaxDiagnostics := TLspSyntaxDiagnostics.Create(FDocuments, FTransport);
  FSyntaxDiagnostics.OnError :=
    procedure(AError: Exception)
    begin
      FLogger.Error(Format('Fehler beim Prüfen der Syntax: %s: %s', [AError.ClassName, AError.Message]));
    end;
  FSyntaxDiagnostics.Attach;
  FDocumentSymbols := TLspDocumentSymbols.Create(FDocuments);
  FDocumentSymbols.Attach(FDispatcher);
  FFoldingRanges := TLspFoldingRanges.Create(FDocuments);
  FFoldingRanges.Attach(FDispatcher);
  FSelectionRanges := TLspSelectionRanges.Create(FDocuments);
  FSelectionRanges.Attach(FDispatcher);
  FConfiguration := TLspConfiguration.Create(FDocuments, FTransport,
    function(const AFileName: string; out AText: string): Boolean
    var
      FileFormat: TFileFormat;
    begin
      Result := FileExists(AFileName);
      if Result then
        AText := TFileEncoding.LoadFromFile(AFileName, FileFormat)
      else
        AText := '';
    end);
  FConfiguration.OnChanged :=
    procedure(const ASettings: TServerSettings)
    begin
      FLogger.Info(Format('Einstellungen geladen: Delphi %s, Projekt %s, %d Regeleinstellungen, %d Ausschlüsse',
        [ASettings.DelphiVersion, ASettings.Project, Length(ASettings.Rules), Length(ASettings.Exclude)]));
    end;
  FConfiguration.Attach;
  FLifecycle.OnInitialized :=
    procedure
    begin
      FConfiguration.LoadWorkspace(TLspConfiguration.RootPathFromInitialize(FLifecycle.InitializeParams));
    end;
  FConnection := TJsonRpcConnection.Create(FTransport, FDispatcher);
  FConnection.OnError :=
    procedure(const AError: Exception)
    begin
      FLogger.Error('Fehler bei der Verarbeitung: ' + DescribeFailure(AError));
    end;
  FLifecycle.OnExit :=
    procedure
    begin
      FConnection.Stop;
    end;
end;

destructor TServerComposition.Destroy;
begin
  FConnection.Free;
  FSyntaxDiagnostics.Free;
  FDocumentSymbols.Free;
  FFoldingRanges.Free;
  FSelectionRanges.Free;
  FConfiguration.Free;
  FTextDocumentSync.Free;
  FDocuments := nil;
  FLifecycle.Free;
  FDispatcher.Watchdog := nil;
  FDispatcher.Free;
  FTransport := nil;
  FLogger := nil;
  inherited;
end;

class function TServerComposition.CreateForStdio(const AOptions: TCommandLineOptions): TServerComposition;
var
  LoggerImpl: TLogger;
  Logger: ILogger;
  Transport: IJsonRpcTransport;
  Warning: string;
begin
  // Stacktraces für das Absturzprotokoll (Exception.StackTrace).
  TStackTrace.Install;
  LoggerImpl := TLogger.Create;
  Logger := LoggerImpl;
  LoggerImpl.AddSink(TDebugOutputLogSink.Create, TLogLevel.Debug);
  // stderr zeigt VS Code ebenfalls im Ausgabefenster; dort nur Fehler, um
  // Doppelungen mit window/logMessage zu vermeiden.
  LoggerImpl.AddSink(TStreamLogSink.Create(TStdStreams.CreateError, True), TLogLevel.Error);
  if AOptions.LogFile <> '' then
    try
      LoggerImpl.AddSink(TStreamLogSink.CreateForFile(AOptions.LogFile), AOptions.LogLevel);
    except
      on E: Exception do
        Logger.Error(Format('Logdatei "%s" kann nicht geöffnet werden: %s', [AOptions.LogFile, E.Message]));
    end;

  // Ab hier erreichen versehentliche Ausgaben (Writeln, Bibliotheken) nur noch stderr.
  Transport := TJsonRpcStreamTransport.Create(TStdStreams.CreateInput, TStdStreams.ReserveOutputForProtocol, True);
  if AOptions.TraceFile <> '' then
    try
      Transport := TJsonRpcTracingTransport.Create(Transport, CreateTraceStream(AOptions.TraceFile), True);
    except
      on E: Exception do
        Logger.Error(Format('Mitschnitt "%s" kann nicht angelegt werden: %s', [AOptions.TraceFile, E.Message]));
    end;
  LoggerImpl.AddSink(TLspLogMessageSink.Create(Transport), AOptions.LogLevel);

  for Warning in AOptions.Warnings do
    Logger.Warning(Warning);

  Result := TServerComposition.Create(Transport, Logger);
end;

function TServerComposition.DescribeFailure(const AError: Exception): string;
begin
  Result := Format('%s: %s%sLetzte Nachricht: %s', [AError.ClassName, AError.Message, sLineBreak,
    FDispatcher.LastMessage]);
  if AError.StackTrace <> '' then
    Result := Result + sLineBreak + AError.StackTrace;
end;

class function TServerComposition.BuildCapabilities: TJSONObject;
begin
  // Die Features tragen ihre Capabilities hier ein, sobald sie umgesetzt sind.
  Result := TJSONObject.Create;
  Result.AddPair('textDocumentSync', TLspTextDocumentSync.Capability);
  Result.AddPair('documentSymbolProvider', TJSONBool.Create(True));
  Result.AddPair('foldingRangeProvider', TJSONBool.Create(True));
  Result.AddPair('selectionRangeProvider', TJSONBool.Create(True));
end;

function TServerComposition.Run: Integer;
begin
  FLogger.Info(Format('%s %s gestartet', [TProductVersion.Name, TProductVersion.Version]));
  try
    FConnection.Run;
    Result := FLifecycle.ExitCode;
  except
    on E: Exception do
    begin
      FLogger.Error('Server abgebrochen: ' + DescribeFailure(E));
      Result := 1;
    end;
  end;
  FLogger.Info(Format('Beendet mit Exit-Code %d', [Result]));
end;

end.
