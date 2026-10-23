unit Shell.Diagnostics;

// Host-Rolle Shell: Anbindung des anonymisierten Diagnoselogs (#647).
// - Beobachter des Dispatchers: je Anfrage Dauer, Wartezeit, Ergebnis mit
//   Grundcode, Dokument als Kurz-ID mit Version, Länge und Prüfsumme, Position
//   als Zahlen und Zustand des Index.
// - Start und Ende des Serverlaufs mit Grund, Speicher und Threads; bei einer
//   Exception Klasse und Aufrufstapel (Adressen und Atlas-eigene Routinen aus
//   der Map-Datei, ohne Dateinamen).
// - Läufe, die ohne Endzeile aufhörten (Prozess von der IDE beendet oder
//   abgestürzt), meldet der nächste Start; im Server-Log ebenso (#175).
// Ordner: %LOCALAPPDATA%\Atlas\Logs\Diagnose, eine Datei je Tag und Prozess.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Diagnostics.Contract,
  Atlas.Common.Diagnostics.Anonymizer,
  Atlas.Common.Diagnostics.Providers.Log,
  Atlas.Common.Diagnostics.Adapters.LogFolder;

type
  TShellDiagnostics = class(TInterfacedObject, IJsonRpcRequestObserver)
  private
    FLogImpl: TDiagnosticLog;
    FLog: IDiagnosticLog;
    FFolder: TDiagnosticLogFolder;
    FWriter: IDiagnosticWriter;
    FIds: TDiagnosticIds;
    FDocuments: IDocumentStore;
    FIndex: ISymbolIndex;
    FLock: TObject;
    FLibraryGeneration: Int64;
    FLibraryCount: Integer;
    /// <summary>Laufende Anfragen je Kurzname (hover, diagnostic, wsDiagnostic); unter FLock.</summary>
    FRunning: TDictionary<string, Integer>;
    FMapFile: Boolean;
    FIndexLoading: TFunc<Integer>;
    FTimeoutMs: TFunc<Cardinal>;
    /// <summary>Endzeile geschrieben; danach keine Zeilen mehr.</summary>
    FEnded: Boolean;
    class function ShortMethod(const AMethod: string): string; static;
    function LibraryCount: Integer;
    procedure DescribeDocument(const AParams: TJSONValue; var ARequest: TDiagnosticRequest);
    class function CountOf(const AResult: TJSONValue): Integer; static;
  public
    /// <summary>AFolder: Ordner der Tagesdateien; ATag unterscheidet die Prozesse.</summary>
    constructor Create(const AFolder, ATag: string; const ADocuments: IDocumentStore; const AIndex: ISymbolIndex);
    destructor Destroy; override;
    class function DefaultFolder: string; static;
    /// <summary>Senke für das Server-Log (--log). Anonymisiert (#647), außer mit ANames (--log-names);
    /// AAnonymizer ist dann nil.</summary>
    class function LogFileSink(const AFileName, AFallbackTag: string; ANames: Boolean;
      out AAnonymizer: ILogAnonymizer): ILogSink; static;
    /// <summary>Hängt die Logdatei AFileName (--log) ab ALevel an ALogger; gemeinsam für LSP-Server und
    /// MCP-Modus (D-08). Lässt sie sich nicht öffnen, steht der Fehler im Log und das Ergebnis ist False.
    /// Ohne AFileName geschieht nichts (True).</summary>
    class function AddLogFile(ALogger: TLogger; const AFileName, AFallbackTag: string; ANames: Boolean;
      ALevel: TLogLevel; out AAnonymizer: ILogAnonymizer): Boolean; static;
    { IJsonRpcRequestObserver }
    procedure Started(const AMethod: string);
    procedure Finished(const AMethod: string; const AParams, AResult: TJSONValue; const AError: Exception;
      AQueueMs, AElapsedMs: Int64);
    /// <summary>Startzeile und Meldung früherer Läufe ohne Ende; liefert deren Zahl.</summary>
    function BeginRun(const AVersion: string; AMemoryBytes: Int64): Integer;
    /// <summary>Lesbarer Grund für das Server-Log, z. B. „Eingabe geschlossen ohne exit“ (#175).</summary>
    class function EndReasonText(AReason: TDiagnosticEndReason): string; static;
    /// <summary>Endzeile; AError nur bei einer unbehandelten Exception. Nur der erste Aufruf zählt.</summary>
    procedure EndRun(AReason: TDiagnosticEndReason; AExitCode: Integer; AMemoryBytes: Int64;
      const AError: Exception = nil);
    procedure ApplySettings(const ASettings: TServerSettings);
    /// <summary>Feste Methodennamen, die "/" enthalten dürfen.</summary>
    procedure AllowMethods(const AMethods: TArray<string>);
    /// <summary>Ordner der Delphi-Installation: Units darunter erscheinen mit Namen.</summary>
    procedure SetLibraryRoots(const ARoots: TArray<string>);
    /// <summary>Anonymes Kennzeichen einer Quelldatei für das Diagnoselog (#1094): "unit#N", unter einem
    /// Bibliothekspfad der Unit-Name.</summary>
    function FileLabel(const AFileName: string): string;
    property Log: IDiagnosticLog read FLog;
    /// <summary>Fortschritt des Indexaufbaus in Prozent, -1 ohne Aufbau.</summary>
    property IndexLoading: TFunc<Integer> read FIndexLoading write FIndexLoading;
    /// <summary>Zeitlimit für Anfragen; abgebrochene Anfragen ab dieser Dauer gelten als timeout.</summary>
    property TimeoutMs: TFunc<Cardinal> read FTimeoutMs write FTimeoutMs;
  end;

implementation

uses
  System.IOUtils,
  System.Hash,
  System.StrUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Diagnostics.RequestScope,
  Atlas.Common.Logging.Providers.StreamSink,
  Atlas.Common.Logging.Providers.TransformSink,
  Shell.Platform;

threadvar
  /// <summary>Rechenzeit des Handler-Threads beim Start der Anfrage.</summary>
  StartCpuMs: Int64;

{ TShellDiagnostics }

constructor TShellDiagnostics.Create(const AFolder, ATag: string; const ADocuments: IDocumentStore;
  const AIndex: ISymbolIndex);
begin
  inherited Create;
  FLock := TObject.Create;
  FRunning := TDictionary<string, Integer>.Create;
  FFolder := TDiagnosticLogFolder.Create(AFolder, ATag);
  FWriter := FFolder;
  FLogImpl := TDiagnosticLog.Create(FWriter, TDiagnosticFilter.Create(TProcessInfo.IdentityNames));
  FLog := FLogImpl;
  FIds := TDiagnosticIds.Create;
  FDocuments := ADocuments;
  FIndex := AIndex;
  FLibraryGeneration := -1;
end;

destructor TShellDiagnostics.Destroy;
begin
  FLogImpl.Flush;
  FLog := nil;
  FWriter := nil;
  FIds.Free;
  FRunning.Free;
  FLock.Free;
  inherited;
end;

class function TShellDiagnostics.DefaultFolder: string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.Combine(TPath.GetCachePath, 'Atlas'), 'Logs'), 'Diagnose');
end;

class function TShellDiagnostics.AddLogFile(ALogger: TLogger; const AFileName, AFallbackTag: string;
  ANames: Boolean; ALevel: TLogLevel; out AAnonymizer: ILogAnonymizer): Boolean;
begin
  AAnonymizer := nil;
  Result := True;
  if AFileName = '' then
    Exit;
  try
    ALogger.AddSink(LogFileSink(AFileName, AFallbackTag, ANames, AAnonymizer), ALevel);
  except
    on E: Exception do
    begin
      ALogger.Error(Format('Logdatei "%s" kann nicht geöffnet werden: %s', [AFileName, E.Message]));
      Result := False;
    end;
  end;
end;

class function TShellDiagnostics.LogFileSink(const AFileName, AFallbackTag: string; ANames: Boolean;
  out AAnonymizer: ILogAnonymizer): ILogSink;
var
  Anonymizer: ILogAnonymizer;
  Inner: ILogSink;
begin
  Inner := TStreamLogSink.CreateForFile(AFileName, AFallbackTag);
  AAnonymizer := nil;
  Result := Inner;
  if ANames then
    Exit;
  // Eigene Variable: out-Parameter lassen sich nicht einfangen.
  Anonymizer := TLogAnonymizer.Create(TProcessInfo.IdentityNames);
  AAnonymizer := Anonymizer;
  Result := TTransformLogSink.Create(Inner,
    function(const AText: string): string
    begin
      Result := Anonymizer.Anonymize(AText);
    end);
end;

procedure TShellDiagnostics.AllowMethods(const AMethods: TArray<string>);
begin
  // Nur beim Start gesetzt, bevor Anfragen laufen.
  FLogImpl.Filter.Allowed := AMethods;
end;

procedure TShellDiagnostics.SetLibraryRoots(const ARoots: TArray<string>);
begin
  FIds.SetLibraryRoots(ARoots);
end;

procedure TShellDiagnostics.ApplySettings(const ASettings: TServerSettings);
begin
  FMapFile := ASettings.DiagnosticsLogMapFile;
  FFolder.RetentionDays := ASettings.DiagnosticsLogDays;
  FLog.Configure(ASettings.DiagnosticsLog);
  if ASettings.DiagnosticsLog then
    FFolder.Cleanup(ASettings.DiagnosticsLogDays);
end;

function TShellDiagnostics.BeginRun(const AVersion: string; AMemoryBytes: Int64): Integer;
var
  Process: TDiagnosticProcess;
  Previous, Index: Integer;
begin
  Previous := FFolder.BeginRun;
  Result := Previous;
  Process.MemoryBytes := AMemoryBytes;
  Process.Threads := TProcessInfo.ThreadCount;
  FLog.LogStart(AVersion, Process);
  for Index := 1 to Previous do
    FLog.LogEvent('previous run ended without end line (process terminated or crashed)');
end;

class function TShellDiagnostics.EndReasonText(AReason: TDiagnosticEndReason): string;
begin
  case AReason of
    TDiagnosticEndReason.Clean:
      Result := 'shutdown und exit vom Client';
    TDiagnosticEndReason.InputClosed:
      Result := 'Eingabe geschlossen ohne exit (IDE hat die Verbindung getrennt)';
    TDiagnosticEndReason.ParentExited:
      Result := 'Editor-Prozess beendet';
  else
    Result := 'unbehandelte Exception';
  end;
end;

procedure TShellDiagnostics.EndRun(AReason: TDiagnosticEndReason; AExitCode: Integer; AMemoryBytes: Int64;
  const AError: Exception);
var
  Process: TDiagnosticProcess;
  ErrorClass, Stack: string;
begin
  // Die Endzeile kommt schon, wenn die Eingabe endet (#647): Das Plugin wartet danach nur kurz und
  // beendet den Prozess, solange noch Anfragen laufen. Der spätere Aufruf aus Run zählt dann nicht.
  if FEnded then
    Exit;
  FEnded := True;
  Process.MemoryBytes := AMemoryBytes;
  Process.Threads := TProcessInfo.ThreadCount;
  ErrorClass := '';
  Stack := '';
  if AError <> nil then
  begin
    // Nur Klasse und Aufrufstapel: Die Meldung kann Pfade oder Namen aus dem Projekt enthalten.
    ErrorClass := AError.ClassName;
    Stack := TShellPlatform.StackTraceOf(AError);
  end;
  FLog.LogEnd(AReason, AExitCode, Process, ErrorClass, Stack);
  FLogImpl.Flush;
  if FMapFile and FLog.Enabled then
    FFolder.WriteMap(FIds.MapLines);
  FFolder.EndRun;
end;

function TShellDiagnostics.FileLabel(const AFileName: string): string;
begin
  Result := FIds.UnitLabel(ChangeFileExt(ExtractFileName(AFileName), ''), AFileName);
end;

function TShellDiagnostics.LibraryCount: Integer;
var
  Generation: Int64;
  UnitIndex: TUnitIndex;
  Count: Integer;
begin
  // Teuer bei vielen Units; nur neu zählen, wenn sich der Index geändert hat.
  Generation := FIndex.Generation;
  TMonitor.Enter(FLock);
  try
    if Generation = FLibraryGeneration then
      Exit(FLibraryCount);
  finally
    TMonitor.Exit(FLock);
  end;
  Count := 0;
  for UnitIndex in FIndex.Units do
    if UnitIndex.Library_ then
      Inc(Count);
  TMonitor.Enter(FLock);
  try
    FLibraryGeneration := Generation;
    FLibraryCount := Count;
  finally
    TMonitor.Exit(FLock);
  end;
  Result := Count;
end;

procedure TShellDiagnostics.DescribeDocument(const AParams: TJSONValue; var ARequest: TDiagnosticRequest);
var
  Uri: string;
  Line, Character: Integer;
  Document: ITextDocument;
  Text: string;
begin
  if not (AParams is TJSONObject) then
    Exit;
  if TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) then
  begin
    ARequest.Document := FIds.IdOf(TDiagnosticIdKind.Document, TDocumentUris.ToPath(Uri));
    ARequest.Version := -1;
    if (FDocuments <> nil) and FDocuments.TryGet(Uri, Document) then
    begin
      Text := Document.Text;
      ARequest.Version := Document.Version;
      ARequest.Length_ := Length(Text);
      ARequest.Checksum := IntToHex(Cardinal(THashFNV1a32.GetHashValue(Text)), 8);
      ARequest.LineCount := Document.LineCount;
    end;
  end;
  if TJSONObject(AParams).TryGetValue<Integer>('position.line', Line) and
    TJSONObject(AParams).TryGetValue<Integer>('position.character', Character) then
  begin
    ARequest.Line := Line;
    ARequest.Column := Character;
  end;
end;

class function TShellDiagnostics.CountOf(const AResult: TJSONValue): Integer;
var
  Items: TJSONValue;
begin
  if (AResult = nil) or (AResult is TJSONNull) then
    Exit(0);
  if AResult is TJSONArray then
    Exit(TJSONArray(AResult).Count);
  if AResult is TJSONObject then
  begin
    Items := TJSONObject(AResult).GetValue('items');
    if Items is TJSONArray then
      Exit(TJSONArray(Items).Count);
  end;
  Result := 1;
end;

class function TShellDiagnostics.ShortMethod(const AMethod: string): string;
var
  Slash: Integer;
begin
  // Ohne "/": Der Filter des Diagnoselogs verwirft Zeilen mit Schrägstrich.
  Slash := LastDelimiter('/', AMethod);
  Result := Copy(AMethod, Slash + 1, MaxInt);
  if StartsText('workspace/', AMethod) and (Result <> '') then
    Result := 'ws' + UpperCase(Result[1]) + Copy(Result, 2, MaxInt);
end;

procedure TShellDiagnostics.Started(const AMethod: string);
var
  Name: string;
  Count: Integer;
begin
  TRequestDiagnostics.Open;
  StartCpuMs := TProcessInfo.ThreadCpuMs;
  Name := ShortMethod(AMethod);
  TMonitor.Enter(FLock);
  try
    if FRunning.TryGetValue(Name, Count) then
      FRunning[Name] := Count + 1
    else
      FRunning.Add(Name, 1);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TShellDiagnostics.Finished(const AMethod: string; const AParams, AResult: TJSONValue;
  const AError: Exception; AQueueMs, AElapsedMs: Int64);
var
  Notes: TRequestNotes;
  Request: TDiagnosticRequest;
  Timeout: Cardinal;
  CpuMs: Int64;
  Name, Parallel: string;
  Count: Integer;
  Pair: TPair<string, Integer>;
begin
  Notes := TRequestDiagnostics.Close;
  // Rechenzeit gegen Laufzeit (#647): cpu weit unter ms heißt Warten (Sperre, volle CPU), nicht Rechnen.
  CpuMs := TProcessInfo.ThreadCpuMs;
  if (CpuMs >= 0) and (StartCpuMs >= 0) then
    Notes.Notes := Notes.Notes + ['cpu=' + IntToStr(CpuMs - StartCpuMs)];
  Name := ShortMethod(AMethod);
  Parallel := '';
  TMonitor.Enter(FLock);
  try
    if FRunning.TryGetValue(Name, Count) then
    begin
      if Count <= 1 then
        FRunning.Remove(Name)
      else
        FRunning[Name] := Count - 1;
    end;
    // Was beim Ende dieser Anfrage noch läuft.
    for Pair in FRunning do
    begin
      if Parallel <> '' then
        Parallel := Parallel + ',';
      Parallel := Parallel + Pair.Key + IntToStr(Pair.Value);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  if Parallel <> '' then
    Notes.Notes := Notes.Notes + ['parallel=' + Parallel];
  // Bei einem Fehler noch offen (#1094): die Unit und die Regel, an denen die Anfrage scheiterte.
  if Notes.Subject <> '' then
    Notes.Notes := Notes.Notes + ['unit=' + Notes.Subject];
  if Notes.Rule <> '' then
    Notes.Notes := Notes.Notes + ['rule=' + Notes.Rule];
  if FEnded or not FLog.Enabled then
    Exit;
  Request := Default(TDiagnosticRequest);
  Request.Time := Now;
  Request.Method := AMethod;
  Request.ElapsedMs := AElapsedMs;
  Request.QueueMs := AQueueMs;
  Request.Line := -1;
  Request.Notes := Notes.Notes;
  Request.Resolve := Notes.Resolve;
  Request.Reason := Notes.Reason;
  if AError is EJsonRpcRequestCancelled then
  begin
    Timeout := 0;
    if Assigned(FTimeoutMs) then
      Timeout := FTimeoutMs();
    // Der Wächter bricht nach dem Zeitlimit ab; früher abgebrochen hat der Client oder eine Änderung.
    if (Timeout > 0) and (AQueueMs + AElapsedMs >= Int64(Timeout) - 50) then
      Request.Outcome := TDiagnosticOutcome.Timeout
    else
      Request.Outcome := TDiagnosticOutcome.Cancelled;
  end
  else if AError <> nil then
  begin
    Request.Outcome := TDiagnosticOutcome.Error;
    Request.Reason := AError.ClassName;
  end
  else
  begin
    Request.Count := Notes.Count;
    if Request.Count < 0 then
      Request.Count := CountOf(AResult);
    if Request.Count > 0 then
      Request.Outcome := TDiagnosticOutcome.Ok
    else
      Request.Outcome := TDiagnosticOutcome.Empty;
  end;
  DescribeDocument(AParams, Request);
  if FIndex <> nil then
  begin
    Request.IndexUnits := FIndex.UnitCount;
    Request.IndexLibrary := LibraryCount;
  end;
  Request.IndexLoading := -1;
  if Assigned(FIndexLoading) then
    Request.IndexLoading := FIndexLoading();
  FLog.LogRequest(Request);
end;

end.
