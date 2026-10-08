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
  BDLsp.Common.Lsp.Definition,
  BDLsp.Common.Lsp.Hover,
  BDLsp.Common.Lsp.WorkspaceSymbols,
  BDLsp.Common.Lsp.DocumentHighlights,
  BDLsp.Common.Lsp.WatchedFiles,
  BDLsp.Common.Lsp.Configuration,
  BDLsp.Common.Lsp.WorkDoneProgress,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Projects.UnitResolver,
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Index.Service,
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
    FDefinition: TLspDefinition;
    FHover: TLspHover;
    FWorkspaceSymbols: TLspWorkspaceSymbols;
    FDocumentHighlights: TLspDocumentHighlights;
    FWatchedFiles: TLspWatchedFiles;
    FConfiguration: TLspConfiguration;
    FConnection: TJsonRpcConnection;
    FIndex: ISymbolIndex;
    FIndexService: TIndexService;
    FIndexProgress: TLspWorkDoneProgress;
    FUnitResolver: TUnitResolver;
    FIndexSignature: string;
    /// <summary>Startet den Indexaufbau, wenn sich Projekt, Konfiguration, Plattform oder Version geändert haben.</summary>
    procedure StartIndex(const ASettings: TServerSettings);
    /// <summary>Dateiänderungen von außen: Projektdateien laden das Projekt neu, Quelltexte aktualisieren den Index.</summary>
    procedure HandleWatchedFiles(const AChanges: TArray<TFileChange>);
    function FindProjectFile(const ASettings: TServerSettings): string;
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
    property Index: ISymbolIndex read FIndex;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  BDLsp.Common.Product.Version,
  BDLsp.Common.Logging.Providers.Logger,
  BDLsp.Common.Logging.Providers.StreamSink,
  BDLsp.Common.JsonRpc.StreamTransport,
  BDLsp.Common.JsonRpc.TracingTransport,
  BDLsp.Common.Lsp.Adapters.LogMessageSink,
  BDLsp.Common.Documents.Providers.DocumentStore,
  BDLsp.Common.Documents.FileEncoding,
  BDLsp.Common.Documents.Uris,
  BDLsp.Common.Projects.Contract,
  BDLsp.Common.Projects.Paths,
  BDLsp.Common.Projects.DprojReader,
  BDLsp.Common.Index.SymbolIndex,
  BDLsp.Common.Index.Builder,
  BDLsp.Common.Index.ProjectFiles,
  BDLsp.Common.Index.Adapters.DiskFileSystem,
  BDLsp.Windows.Console.StdStreams,
  BDLsp.Windows.Projects.DelphiInstallation,
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
      StartIndex(ASettings);
    end;
  FConfiguration.Attach;
  FIndex := TSymbolIndex.Create;
  FIndexService := TIndexService.Create(FIndex, TDiskIndexFileSystem.Create);
  FDefinition := TLspDefinition.Create(FDocuments, FIndex,
    function(const AUnitName: string): Boolean
    begin
      Result := FIndexService.EnsureUnit(AUnitName);
    end);
  FDefinition.Attach(FDispatcher);
  FHover := TLspHover.Create(FDocuments, FIndex,
    function(const AFileName: string; out AText: string): Boolean
    var
      Document: ITextDocument;
      FileFormat: TFileFormat;
    begin
      // Geöffnete Dokumente haben Vorrang vor dem Stand auf der Festplatte.
      if FDocuments.TryGet(TDocumentUris.FromPath(AFileName), Document) then
      begin
        AText := Document.Text;
        Exit(True);
      end;
      Result := FileExists(AFileName);
      if Result then
        AText := TFileEncoding.LoadFromFile(AFileName, FileFormat)
      else
        AText := '';
    end,
    function(const AUnitName: string): Boolean
    begin
      Result := FIndexService.EnsureUnit(AUnitName);
    end);
  FHover.Attach(FDispatcher);
  FWorkspaceSymbols := TLspWorkspaceSymbols.Create(FIndex);
  FWorkspaceSymbols.Attach(FDispatcher);
  FDocumentHighlights := TLspDocumentHighlights.Create(FDocuments, FIndex,
    function(const AUnitName: string): Boolean
    begin
      Result := FIndexService.EnsureUnit(AUnitName);
    end);
  FDocumentHighlights.Attach(FDispatcher);
  FWatchedFiles := TLspWatchedFiles.Create(FTransport);
  FWatchedFiles.OnChanged := HandleWatchedFiles;
  FWatchedFiles.Attach(FDispatcher);
  FIndexProgress := TLspWorkDoneProgress.Create(FTransport, 'bdlsp-index');
  FIndexService.OnProgress := FIndexProgress.AsIndexProgress;
  FIndexService.OnFinished :=
    procedure(const AResult: TIndexBuildResult; AElapsedMs: Int64)
    begin
      FLogger.Info(Format('Symbolindex fertig in %d ms: %d Units, %d Symbole (%d neu eingelesen, %d aus dem Cache, %d fehlen)%s',
        [AElapsedMs, FIndex.UnitCount, FIndex.SymbolCount, AResult.Parsed, AResult.FromCache, AResult.Missing,
         IfThen(AResult.Cancelled, ', abgebrochen', '')]));
    end;
  FIndexService.OnError :=
    procedure(const AError: Exception)
    begin
      FLogger.Error(Format('Fehler beim Aufbau des Symbolindex: %s: %s', [AError.ClassName, AError.Message]));
    end;
  FLifecycle.OnInitialized :=
    procedure
    begin
      FConfiguration.LoadWorkspace(TLspConfiguration.RootPathFromInitialize(FLifecycle.InitializeParams));
      FWatchedFiles.RegisterWatchers(FLifecycle.InitializeParams);
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
  FIndexService.Free;
  FIndexProgress.Free;
  FUnitResolver.Free;
  FIndex := nil;
  FSyntaxDiagnostics.Free;
  FDocumentSymbols.Free;
  FFoldingRanges.Free;
  FSelectionRanges.Free;
  FDefinition.Free;
  FHover.Free;
  FWorkspaceSymbols.Free;
  FDocumentHighlights.Free;
  FWatchedFiles.Free;
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

function TServerComposition.FindProjectFile(const ASettings: TServerSettings): string;
var
  Root: string;
  Candidates: TArray<string>;
begin
  Result := '';
  Root := FConfiguration.RootPath;
  if ASettings.Project <> '' then
  begin
    if TProjectPaths.IsAbsolute(ASettings.Project) then
      Result := ASettings.Project
    else if Root <> '' then
      Result := TProjectPaths.Combine(Root, ASettings.Project);
    if not FileExists(Result) then
    begin
      FLogger.Warning('Projektdatei nicht gefunden: ' + Result);
      Result := '';
    end;
    Exit;
  end;
  // Ohne Angabe: die einzige .dproj im Wurzelordner.
  if (Root = '') or not TDirectory.Exists(Root) then
    Exit;
  Candidates := TDirectory.GetFiles(Root, '*.dproj');
  if Length(Candidates) = 1 then
    Result := Candidates[0]
  else if Length(Candidates) > 1 then
    FLogger.Info(Format('%d Projektdateien im Arbeitsbereich; "project" in %s wählt eine aus',
      [Length(Candidates), ConfigurationFileName]));
end;

procedure TServerComposition.StartIndex(const ASettings: TServerSettings);
var
  ProjectFile, Signature, CacheFile: string;
  Installation: ILibraryPathProvider;
  Options: TDprojOptions;
  Project: TProjectInfo;
  LibraryPaths: TArray<string>;
  Request: TIndexRequest;
  Resolver: TUnitResolver;
  FileExistsFunc: TFunc<string, Boolean>;
begin
  ProjectFile := FindProjectFile(ASettings);
  if ProjectFile = '' then
    Exit;
  try
    if ASettings.DelphiVersion <> '' then
      Installation := TDelphiInstallation.Create(ASettings.DelphiVersion)
    else
      Installation := TDelphiInstallation.Latest;
  except
    on E: EProjectError do
    begin
      FLogger.Warning('Delphi-Installation nicht gefunden: ' + E.Message);
      Installation := nil;
    end;
  end;
  FileExistsFunc :=
    function(AFileName: string): Boolean
    begin
      Result := FileExists(AFileName);
    end;
  Options := Default(TDprojOptions);
  Options.Config := ASettings.Config;
  Options.Platform := ASettings.Platform;
  Options.FileExists := FileExistsFunc;
  if Installation <> nil then
    Options.Variables := Installation.Variables;
  try
    Project := TDprojReader.Load(ProjectFile, Options);
  except
    on E: EProjectError do
    begin
      FLogger.Error(Format('Projekt %s nicht lesbar: %s', [ProjectFile, E.Message]));
      Exit;
    end;
  end;
  Signature := TIndexProjectFiles.Signature(Project, ASettings.DelphiVersion);
  if Signature = FIndexSignature then
    Exit;
  FIndexSignature := Signature;
  FDefinition.Namespaces := Project.Namespaces;
  FHover.Namespaces := Project.Namespaces;
  FDocumentHighlights.Namespaces := Project.Namespaces;
  FIndexService.Stop;
  if Installation <> nil then
    LibraryPaths := Installation.LibraryPaths(Project.Platform) + Installation.BrowsingPaths(Project.Platform)
  else
    LibraryPaths := nil;
  Resolver := TUnitResolver.Create(Project, LibraryPaths, FileExistsFunc);
  FUnitResolver.Free;
  FUnitResolver := Resolver;
  Request.Files := TIndexProjectFiles.Files(Project);
  Request.Defines := TIndexProjectFiles.Defines(Project, ASettings.DelphiVersion);
  Request.ResolveUnit :=
    function(const AUnitName: string): string
    begin
      Result := Resolver.Resolve(AUnitName);
    end;
  CacheFile := TPath.Combine(TPath.Combine(TPath.GetCachePath, 'BetterDelphiLSP'),
    Format('index-%.8x.json', [Cardinal(Signature.GetHashCode)]));
  Request.CacheFile := CacheFile;
  FLogger.Info(Format('Symbolindex für %s (%s, %s): %d Projektdateien, Cache %s',
    [ProjectFile, Project.Config, Project.Platform, Length(Request.Files), CacheFile]));
  FIndexService.Start(Request);
end;

procedure TServerComposition.HandleWatchedFiles(const AChanges: TArray<TFileChange>);
var
  Change: TFileChange;
  Sources: TArray<TFileChange>;
  ProjectChanged: Boolean;
  Updated: Integer;
begin
  Sources := nil;
  ProjectChanged := False;
  for Change in AChanges do
    if TLspWatchedFiles.IsProjectFile(Change.FileName) then
      ProjectChanged := True
    else if SameText(ExtractFileExt(Change.FileName), '.pas') or SameText(ExtractFileExt(Change.FileName), '.dpr') then
      Sources := Sources + [Change];
  if ProjectChanged then
  begin
    // Neu aufbauen: Suchpfade, Defines oder Units können sich geändert haben.
    FLogger.Info('Projektdatei geändert, Symbolindex wird neu aufgebaut');
    FIndexSignature := '';
    StartIndex(FConfiguration.Settings);
    Exit;
  end;
  if Length(Sources) = 0 then
    Exit;
  Updated := FIndexService.ApplyChanges(Sources);
  FLogger.Debug(Format('%d Dateiänderungen von außen, %d Units im Index aktualisiert', [Length(Sources), Updated]));
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
  Result.AddPair('definitionProvider', TJSONBool.Create(True));
  Result.AddPair('declarationProvider', TJSONBool.Create(True));
  Result.AddPair('hoverProvider', TJSONBool.Create(True));
  Result.AddPair('workspaceSymbolProvider', TJSONBool.Create(True));
  Result.AddPair('documentHighlightProvider', TJSONBool.Create(True));
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
