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
    /// <summary>Zählt AName als beendet; liefert, was danach noch läuft.</summary>
    function EndRunning(const AName: string): string;
    procedure SetOutcome(var ARequest: TDiagnosticRequest; const AResult: TJSONValue; const AError: Exception;
      ANoteCount: Integer);
    procedure AddIndexState(var ARequest: TDiagnosticRequest);
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
      const AError: Exception); overload;
    /// <summary>Wie oben ohne Exception (AError = nil).</summary>
    procedure EndRun(AReason: TDiagnosticEndReason; AExitCode: Integer; AMemoryBytes: Int64); overload;
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
  Shell.Platform,
  Atlas.Text.LogMarks;

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
  if FLogImpl <> nil then
  begin
    FLogImpl.Flush;
  end;
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
  begin
    Exit;
  end;
  try
    ALogger.AddSink(LogFileSink(AFileName, AFallbackTag, ANames, AAnonymizer), ALevel);
  except
    on E: Exception do
    begin
      ALogger.Error(Format('Logdatei "%s" kann nicht geöffnet werden: %s', [TLogMarks.Path(AFileName),
        TLogMarks.Text(E.Message)]));
      Result := False;
    end;
  end;
end;

class function TShellDiagnostics.LogFileSink(const AFileName, AFallbackTag: string; ANames: Boolean;
  out AAnonymizer: ILogAnonymizer): ILogSink;
var
  mAnonymizer: ILogAnonymizer;
  mInner: ILogSink;
begin
  mInner := TStreamLogSink.CreateForFile(AFileName, AFallbackTag);
  AAnonymizer := nil;
  Result := mInner;
  if ANames then
  begin
    Exit;
  end;
  // Eigene Variable: out-Parameter lassen sich nicht einfangen.
  mAnonymizer := TLogAnonymizer.Create(TProcessInfo.IdentityNames);
  AAnonymizer := mAnonymizer;
  Result := TTransformLogSink.Create(mInner,
    function(const AText: string): string
    begin
      Result := mAnonymizer.Anonymize(AText);
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
  begin
    FFolder.Cleanup(ASettings.DiagnosticsLogDays);
  end;
end;

function TShellDiagnostics.BeginRun(const AVersion: string; AMemoryBytes: Int64): Integer;
var
  mProcess: TDiagnosticProcess;
  mPrevious, mIndex: Integer;
begin
  mPrevious := FFolder.BeginRun;
  Result := mPrevious;
  mProcess.MemoryBytes := AMemoryBytes;
  mProcess.Threads := TProcessInfo.ThreadCount;
  FLog.LogStart(AVersion, mProcess);
  for mIndex := 1 to mPrevious do
  begin
    FLog.LogEvent('previous run ended without end line (process terminated or crashed)');
  end;
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

procedure TShellDiagnostics.EndRun(AReason: TDiagnosticEndReason; AExitCode: Integer; AMemoryBytes: Int64);
begin
  EndRun(AReason, AExitCode, AMemoryBytes, nil);
end;

procedure TShellDiagnostics.EndRun(AReason: TDiagnosticEndReason; AExitCode: Integer; AMemoryBytes: Int64;
  const AError: Exception);
var
  mProcess: TDiagnosticProcess;
  mErrorClass, mStack: string;
begin
  // Die Endzeile kommt schon, wenn die Eingabe endet (#647): Das Plugin wartet danach nur kurz und
  // beendet den Prozess, solange noch Anfragen laufen. Der spätere Aufruf aus Run zählt dann nicht.
  if FEnded then
  begin
    Exit;
  end;
  FEnded := True;
  mProcess.MemoryBytes := AMemoryBytes;
  mProcess.Threads := TProcessInfo.ThreadCount;
  mErrorClass := '';
  mStack := '';
  if AError <> nil then
  begin
    // Nur Klasse und Aufrufstapel: Die Meldung kann Pfade oder Namen aus dem Projekt enthalten.
    mErrorClass := AError.ClassName;
    mStack := TShellPlatform.StackTraceOf(AError);
  end;
  FLog.LogEnd(AReason, AExitCode, mProcess, mErrorClass, mStack);
  FLogImpl.Flush;
  if FMapFile and FLog.Enabled then
  begin
    FFolder.WriteMap(FIds.MapLines);
  end;
  FFolder.EndRun;
end;

function TShellDiagnostics.FileLabel(const AFileName: string): string;
begin
  Result := FIds.UnitLabel(ChangeFileExt(ExtractFileName(AFileName), ''), AFileName);
end;

function TShellDiagnostics.LibraryCount: Integer;
var
  mGeneration: Int64;
  mUnitIndex: TUnitIndex;
  mCount: Integer;
begin
  // Teuer bei vielen Units; nur neu zählen, wenn sich der Index geändert hat.
  mGeneration := FIndex.Generation;
  TMonitor.Enter(FLock);
  try
    if mGeneration = FLibraryGeneration then
    begin
      Exit(FLibraryCount);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  mCount := 0;
  for mUnitIndex in FIndex.Units do
  begin
    if mUnitIndex.Library_ then
    begin
      Inc(mCount);
    end;
  end;
  TMonitor.Enter(FLock);
  try
    FLibraryGeneration := mGeneration;
    FLibraryCount := mCount;
  finally
    TMonitor.Exit(FLock);
  end;
  Result := mCount;
end;

procedure TShellDiagnostics.DescribeDocument(const AParams: TJSONValue; var ARequest: TDiagnosticRequest);
var
  mUri: string;
  mLine, mCharacter: Integer;
  mDocument: ITextDocument;
  mText: string;
begin
  if not (AParams is TJSONObject) then
  begin
    Exit;
  end;
  if TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri) then
  begin
    ARequest.Document := FIds.IdOf(TDiagnosticIdKind.Document, TDocumentUris.ToPath(mUri));
    ARequest.Version := -1;
    if (FDocuments <> nil) and FDocuments.TryGet(mUri, mDocument) then
    begin
      mText := mDocument.Text;
      ARequest.Version := mDocument.Version;
      ARequest.Length_ := Length(mText);
      ARequest.Checksum := IntToHex(Cardinal(THashFNV1a32.GetHashValue(mText)), 8);
      ARequest.LineCount := mDocument.LineCount;
    end;
  end;
  if TJSONObject(AParams).TryGetValue<Integer>('position.line', mLine) and
    TJSONObject(AParams).TryGetValue<Integer>('position.character', mCharacter) then
  begin
    ARequest.Line := mLine;
    ARequest.Column := mCharacter;
  end;
end;

class function TShellDiagnostics.CountOf(const AResult: TJSONValue): Integer;
var
  mItems: TJSONValue;
begin
  if (AResult = nil) or (AResult is TJSONNull) then
  begin
    Exit(0);
  end;
  if AResult is TJSONArray then
  begin
    Exit(TJSONArray(AResult).Count);
  end;
  if AResult is TJSONObject then
  begin
    mItems := TJSONObject(AResult).GetValue('items');
    if mItems is TJSONArray then
    begin
      Exit(TJSONArray(mItems).Count);
    end;
  end;
  Result := 1;
end;

class function TShellDiagnostics.ShortMethod(const AMethod: string): string;
var
  mSlash: Integer;
begin
  // Ohne "/": Der Filter des Diagnoselogs verwirft Zeilen mit Schrägstrich.
  mSlash := LastDelimiter('/', AMethod);
  Result := Copy(AMethod, mSlash + 1, MaxInt);
  if StartsText('workspace/', AMethod) and (Result <> '') then
  begin
    Result := 'ws' + UpperCase(Result[1]) + Copy(Result, 2, MaxInt);
  end;
end;

procedure TShellDiagnostics.Started(const AMethod: string);
var
  mName: string;
  mCount: Integer;
begin
  TRequestDiagnostics.Open;
  StartCpuMs := TProcessInfo.ThreadCpuMs;
  mName := ShortMethod(AMethod);
  TMonitor.Enter(FLock);
  try
    if FRunning.TryGetValue(mName, mCount) then
    begin
      FRunning[mName] := mCount + 1;
    end
    else
    begin
      FRunning.Add(mName, 1);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

// Was beim Ende einer Anfrage noch läuft, etwa „hover1,completion2“.
function RunningText(ARunning: TDictionary<string, Integer>): string;
var
  mPair: TPair<string, Integer>;
begin
  Result := '';
  for mPair in ARunning do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + mPair.Key + IntToStr(mPair.Value);
  end;
end;

function TShellDiagnostics.EndRunning(const AName: string): string;
var
  mCount: Integer;
begin
  TMonitor.Enter(FLock);
  try
    if FRunning.TryGetValue(AName, mCount) then
    begin
      if mCount <= 1 then
      begin
        FRunning.Remove(AName);
      end
      else
      begin
        FRunning[AName] := mCount - 1;
      end;
    end;
    Result := RunningText(FRunning);
  finally
    TMonitor.Exit(FLock);
  end;
end;

// Zusätze am Ende einer Anfrage: Rechenzeit, Parallelität, Unit und Regel beim Fehler.
procedure AddEndNotes(var ANotes: TRequestNotes; const AParallel: string);
var
  mCpuMs: Int64;
begin
  // Rechenzeit gegen Laufzeit (#647): cpu weit unter ms heißt Warten (Sperre, volle CPU), nicht Rechnen.
  mCpuMs := TProcessInfo.ThreadCpuMs;
  if (mCpuMs >= 0) and (StartCpuMs >= 0) then
  begin
    ANotes.Notes := ANotes.Notes + ['cpu=' + IntToStr(mCpuMs - StartCpuMs)];
  end;
  if AParallel <> '' then
  begin
    ANotes.Notes := ANotes.Notes + ['parallel=' + AParallel];
  end;
  // Bei einem Fehler noch offen (#1094): die Unit und die Regel, an denen die Anfrage scheiterte.
  if ANotes.Subject <> '' then
  begin
    ANotes.Notes := ANotes.Notes + ['unit=' + ANotes.Subject];
  end;
  if ANotes.Rule <> '' then
  begin
    ANotes.Notes := ANotes.Notes + ['rule=' + ANotes.Rule];
  end;
end;

// Abbruch durch den Wächter (Zeitlimit) oder durch Client bzw. Änderung.
function CancelOutcome(const ATimeoutMs: TFunc<Cardinal>; AWaitedMs: Int64): TDiagnosticOutcome;
var
  mTimeout: Cardinal;
begin
  mTimeout := 0;
  if Assigned(ATimeoutMs) then
  begin
    mTimeout := ATimeoutMs();
  end;
  // Der Wächter bricht nach dem Zeitlimit ab; früher abgebrochen hat der Client oder eine Änderung.
  Result := TDiagnosticOutcome.Cancelled;
  if (mTimeout > 0) and (AWaitedMs >= Int64(mTimeout) - 50) then
  begin
    Result := TDiagnosticOutcome.Timeout;
  end;
end;

procedure TShellDiagnostics.SetOutcome(var ARequest: TDiagnosticRequest; const AResult: TJSONValue;
  const AError: Exception; ANoteCount: Integer);
begin
  if AError is EJsonRpcRequestCancelled then
  begin
    ARequest.Outcome := CancelOutcome(FTimeoutMs, ARequest.QueueMs + ARequest.ElapsedMs);
  end
  else if AError <> nil then
  begin
    ARequest.Outcome := TDiagnosticOutcome.Error;
    ARequest.Reason := AError.ClassName;
  end
  else
  begin
    ARequest.Count := ANoteCount;
    if ARequest.Count < 0 then
    begin
      ARequest.Count := CountOf(AResult);
    end;
    ARequest.Outcome := TDiagnosticOutcome.Empty;
    if ARequest.Count > 0 then
    begin
      ARequest.Outcome := TDiagnosticOutcome.Ok;
    end;
  end;
end;

procedure TShellDiagnostics.AddIndexState(var ARequest: TDiagnosticRequest);
begin
  if FIndex <> nil then
  begin
    ARequest.IndexUnits := FIndex.UnitCount;
    ARequest.IndexLibrary := LibraryCount;
  end;
  ARequest.IndexLoading := -1;
  if Assigned(FIndexLoading) then
  begin
    ARequest.IndexLoading := FIndexLoading();
  end;
end;

procedure TShellDiagnostics.Finished(const AMethod: string; const AParams, AResult: TJSONValue;
  const AError: Exception; AQueueMs, AElapsedMs: Int64);
var
  mNotes: TRequestNotes;
  mRequest: TDiagnosticRequest;
begin
  mNotes := TRequestDiagnostics.Close;
  AddEndNotes(mNotes, EndRunning(ShortMethod(AMethod)));
  if FEnded or not FLog.Enabled then
  begin
    Exit;
  end;
  mRequest := Default(TDiagnosticRequest);
  mRequest.Time := Now;
  mRequest.Method := AMethod;
  mRequest.ElapsedMs := AElapsedMs;
  mRequest.QueueMs := AQueueMs;
  mRequest.Line := -1;
  mRequest.Notes := mNotes.Notes;
  mRequest.Resolve := mNotes.Resolve;
  mRequest.Reason := mNotes.Reason;
  SetOutcome(mRequest, AResult, AError, mNotes.Count);
  DescribeDocument(AParams, mRequest);
  AddIndexState(mRequest);
  FLog.LogRequest(mRequest);
end;

end.
