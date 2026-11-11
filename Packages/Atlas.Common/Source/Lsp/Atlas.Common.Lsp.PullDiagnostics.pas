unit Atlas.Common.Lsp.PullDiagnostics;

// Pull-Diagnosen nach LSP 3.17 (#82):
//
//   textDocument/diagnostic   Befunde einer Datei, geöffnet oder von der Platte
//   workspace/diagnostic      Befunde aller nicht geöffneten Projektdateien
//
// Unterstützt der Client das nicht, bleibt es bei publishDiagnostics
// (TLspSyntaxDiagnostics). Ergebnis-Ids bestehen aus einer Generation, die bei
// geänderten Einstellungen, Index oder Compilerlauf steigt, und dem Stand der
// Datei (Version bzw. Zeitstempel); unveränderte Dateien kosten so nichts.
//
// workspace/diagnostic rechnet nicht selbst (#1247): Die Projektprüfung
// (TLspWorkspaceCheck) prüft in einem eigenen Thread als begrenzter Lauf, und
// die Anfrage liefert ihre gespeicherten Befunde samt Fortschritt
// ("atlas": {"run": …}). Gibt es nichts Neues, wartet die Anfrage bis WaitMs
// auf eine Änderung (Long-Polling); mit RequestTimeout endet das Warten sicher
// vor dem Zeitlimit des Watchdogs (Code-Review P-14). Die erste Anfrage
// startet die Projektprüfung; ohne Projektprüfung im Client ruht sie.
//
// Changed (Einstellungen, Index, „neu prüfen“) hebt die Generation der
// geöffneten Dateien und startet einen erzwungenen Lauf über alle Units;
// FilesChanged (neue Compilermeldungen) prüft nur die genannten Dateien neu.
// textDocument/diagnostic hat Vorrang: Während es rechnet, beginnt die
// Projektprüfung keine neue Datei.
//
// Laufzeit (Diagnoselog 15.10.2026): Die Prüfregeln fragen vor jeder Regel das
// Abbruchsignal der Anfrage. Ein Zeitlimit, $/cancelRequest oder eine Änderung
// des Dokuments (ContentModified) beendet die Prüfung, statt sie bis zu vier
// Minuten weiterlaufen zu lassen. Fragen mehrere Anfragen dieselbe Datei im
// selben Stand an, rechnet nur die erste; die übrigen warten auf ihr Ergebnis.
// Geöffnete Dateien prüft ein eigener Thread je Stand (#1761). Die Anfrage
// wartet höchstens OpenJobs.WaitMs (vor dem Zeitlimit) und antwortet sonst mit
// ServerCancelled; die Prüfung rechnet zu Ende (höchstens DetachedMaxMs),
// speichert die Befunde und bittet den Client mit refresh, sie abzuholen.
// Vorher brach eine Unit, deren Prüfung länger als das Zeitlimit dauerte, bei
// jeder Anfrage von vorn ab: Absturzfall je Änderung, und das Fenster
// „Atlas-Prüfung“ blieb leer.
// Befunde einer Datei bleiben je Ergebnis-Id gespeichert: Fragt der Client
// dieselbe Datei im selben Stand erneut ohne previousResultId, wird nicht neu
// geprüft.

interface

uses
  System.SysUtils,
  System.JSON,
  System.SyncObjs,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.SyntaxDiagnostics,
  Atlas.Common.Lsp.WorkspaceCheck,
  Atlas.Common.Lsp.PullDiagnostics.Cache;

type
  /// <summary>Dateien, deren Befunde workspace/diagnostic meldet.</summary>
  TPullFilesProvider = TWorkspaceCheckFiles;
  /// <summary>Zeitstempel einer Datei; False, wenn sie fehlt.</summary>
  TPullFileStamp = TWorkspaceCheckStamp;
  /// <summary>Text einer Datei von der Platte.</summary>
  TPullReadText = TWorkspaceCheckRead;
  /// <summary>True, solange der Symbolindex aufgebaut wird.</summary>
  TPullBusy = TWorkspaceCheckBusy;
  /// <summary>Aktuelles Zeitlimit des Watchdogs für Anfragen in ms (0 = keines).</summary>
  TPullTimeout = reference to function: Cardinal;
  /// <summary>Anonymes Kennzeichen einer Datei für das Diagnoselog, z. B. "unit#12"; nie Pfad oder Name.</summary>
  TPullFileLabel = TWorkspaceCheckLabel;

  /// <summary>Fähigkeiten und Zeitrahmen der Pull-Diagnosen im Protokoll.</summary>
  TLspPullProtocol = class
  public
    /// <summary>True, wenn der Client laut initialize-Parametern Pull-Diagnosen kann.</summary>
    class function ClientSupportsPull(const AInitializeParams: TJSONObject): Boolean; static;
    class function ClientSupportsRefresh(const AInitializeParams: TJSONObject): Boolean; static;
    /// <summary>Eintrag diagnosticProvider für die Server-Capabilities.</summary>
    class function Capability: TJSONObject; static;
    /// <summary>Antwort sicher vor dem Zeitlimit des Watchdogs (P-14): 2 s Reserve, bei kurzen Limits die
    /// Hälfte. ATimeoutMs = 0 (kein Limit): High(Cardinal).</summary>
    class function TimeLimitMs(ATimeoutMs: Cardinal): Cardinal; static;
    /// <summary>Wartezeit des Long-Pollings: AWaitMs, höchstens TimeLimitMs(ATimeoutMs).</summary>
    class function LongPollMs(AWaitMs, ATimeoutMs: Cardinal): Cardinal; static;
  end;

  /// <summary>Prüfung einer geöffneten Datei in einem eigenen Thread (#1761).</summary>
  IPullDocumentJob = interface
    ['{8B4E2D17-9C3A-4F61-A5D8-2E7B0C9F1A46}']
    function Finished: Boolean;
    /// <summary>Wartet höchstens ATimeoutMs auf das Ende der Prüfung; True, wenn sie fertig ist.</summary>
    function WaitFinished(ATimeoutMs: Cardinal): Boolean;
    /// <summary>Eine Anfrage wartet nicht mehr; True, solange die Prüfung noch läuft.</summary>
    function Abandon: Boolean;
    /// <summary>Ende der Prüfung; True, wenn eine Anfrage vorher aufgegeben hat.</summary>
    function Finish: Boolean;
    /// <summary>Ergebnis der Prüfung, vor Finish.</summary>
    procedure Succeed(const AItems: TJSONArray);
    /// <summary>Fehler der Prüfung, vor Finish.</summary>
    procedure Fail(AError: Exception);
    function Failed: Boolean;
    /// <summary>Befunde (gehören dem Aufrufer) oder der Fehler der Prüfung als Ausnahme.</summary>
    function Items: TJSONArray;
  end;

  TLspPullDiagnostics = class;

  /// <summary>Prüfungen geöffneter Dateien in eigenen Threads (#1761), je Datei und Stand eine.</summary>
  TPullOpenJobs = class
  private
    FOwner: TLspPullDiagnostics;
    /// <summary>Laufende Prüfungen: Uri + #0 + Ergebnis-Id -> TPullDocumentJob. Sperre: das Wörterbuch selbst;
    /// das Ende jeder Prüfung weckt Destroy mit PulseAll.</summary>
    FJobs: TDictionary<string, IPullDocumentJob>;
    FRunning: Integer;
    FStopping: Integer;
    FWaitMs: Cardinal;
    /// <summary>Wartezeit einer Anfrage auf die Prüfung, höchstens das Zeitlimit der Anfrage.</summary>
    function Wait: Cardinal;
    /// <summary>Prüfung von ADocument im Stand AResultId; eine laufende für denselben Stand wird geteilt.</summary>
    function Start(const AResultId: string; const ADocument: ITextDocument; AGeneration: Integer): IPullDocumentJob;
    /// <summary>Im Thread der Prüfung: rechnen, ablegen, Ende melden.</summary>
    procedure Run(const AJob: IPullDocumentJob; const AKey, AResultId: string; const ADocument: ITextDocument;
      AGeneration: Integer);
    /// <summary>True ab dem Freigeben: Laufende Prüfungen enden vor der nächsten Regel.</summary>
    function Stopping: Boolean;
    /// <summary>ADocument ist nicht mehr der Stand im Speicher, oder die Generation ist nicht mehr AGeneration.
    /// Threadsicher.</summary>
    function Outdated(const ADocument: ITextDocument; AGeneration: Integer): Boolean;
  public
    constructor Create(AOwner: TLspPullDiagnostics);
    /// <summary>Beendet die laufenden Prüfungen vor der nächsten Regel und wartet auf sie.</summary>
    destructor Destroy; override;
    /// <summary>Befunde der geöffneten Datei; nach Wait EJsonRpcError ServerCancelled.</summary>
    function Items(const AResultId: string; const ADocument: ITextDocument; AGeneration: Integer;
      const ACancellation: IJsonRpcCancellationToken): TJSONArray;
    property WaitMs: Cardinal read FWaitMs write FWaitMs;
  end;

  TLspPullDiagnostics = class
  public const
    cDocumentMethod = 'textDocument/diagnostic';
    cWorkspaceMethod = 'workspace/diagnostic';
    cRefreshMethod = 'workspace/diagnostic/refresh';
    /// <summary>Pause der Projektprüfung vom Client (#1247), z. B. {"reason":"debug","paused":true} beim
    /// Debuggen (#1241).</summary>
    cPauseMethod = 'atlas/workspaceCheck/pause';
    /// <summary>Alle Dateien neu prüfen (#1231, Klick auf die Live-Prüfung der Atlas-Statusleiste): ruft Changed.
    /// </summary>
    cRecheckCommand = 'atlas.server.recheck';
    cIdentifier = 'atlas';
    cDefaultWaitMs = 10000;
    /// <summary>Grundcodes leerer Antworten im Diagnoselog (#647).</summary>
    cReasonIndexLoading = 'indexLoading';
    cReasonNoChanges = 'noChanges';
    /// <summary>Höchstzahl Dateibefunde je Antwort; den Rest holt der Client gleich mit der nächsten.</summary>
    cMaxWorkspaceReports = 200;
    /// <summary>Takt, in dem Wartende den Abbruch prüfen; Änderungen wecken sofort.</summary>
    cChangeSliceMs = 100;
    /// <summary>Neuer Fortschritt ohne neue Befunde beendet das Long-Polling frühestens nach dieser Zeit.</summary>
    cProgressMs = 1000;
    /// <summary>Neue Befunde während eines Laufs sammelt eine Anfrage so lange, bevor sie antwortet.</summary>
    cBatchMs = 1000;
    /// <summary>So lange rechnet die Prüfung einer geöffneten Datei nach abgelaufenem Zeitlimit höchstens weiter.
    /// </summary>
    cDetachedMaxMs = 120000;
    /// <summary>So lange wartet textDocument/diagnostic auf die Prüfung einer geöffneten Datei, höchstens bis
    /// TimeLimitMs; das Plugin wartet 8 s.</summary>
    cDefaultDocumentWaitMs = 5000;
  private
    FStore: IDocumentStore;
    FDiagnostics: TLspSyntaxDiagnostics;
    FTransport: IJsonRpcTransport;
    FStamp: TPullFileStamp;
    FReadText: TPullReadText;
    FCheck: TLspWorkspaceCheck;
    FGeneration: Integer;
    FRequestTimeout: TPullTimeout;
    FRefreshSupport: Boolean;
    FRefreshCounter: Integer;
    FWaitMs: Cardinal;
    FBusy: TPullBusy;
    /// <summary>Befunde je Datei und Ergebnis-Id (#1237).</summary>
    FReports: TPullReportCache;
    FComputed: Integer;
    FFileLabel: TPullFileLabel;
    FOpenJobs: TPullOpenJobs;
    procedure SetBusy(const AValue: TPullBusy);
    /// <summary>Projektprüfung mit den Anbietern dieses Objekts anlegen.</summary>
    function CreateCheck(const AFiles: TPullFilesProvider): TLspWorkspaceCheck;
    /// <summary>Generation heben und geöffnete Dokumente neu holen lassen.</summary>
    procedure NextGeneration;
    /// <summary>Den Client bitten, die Befunde geöffneter Dokumente neu zu holen.</summary>
    procedure SendRefresh;
    function HandleDocument(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    procedure HandlePause(const AParams: TJSONValue);
  public
    constructor Create(const AStore: IDocumentStore; ADiagnostics: TLspSyntaxDiagnostics;
      const ATransport: IJsonRpcTransport; const AFiles: TPullFilesProvider; const AStamp: TPullFileStamp;
      const AReadText: TPullReadText);
    destructor Destroy; override;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Einstellungen oder Index haben sich geändert: neue Generation, alle Units neu prüfen.
    /// Threadsicher.</summary>
    procedure Changed;
    /// <summary>Compilermeldungen von AFiles haben sich geändert: neue Generation für geöffnete Dateien, in der
    /// Projektprüfung nur AFiles neu (#1247). Threadsicher.</summary>
    procedure FilesChanged(const AFiles: TArray<string>);
    /// <summary>Der Benutzer tippt (didChange): Die Projektprüfung macht Platz.</summary>
    procedure Typed;
    /// <summary>Ergebnis zu einer Datei: {kind, resultId[, items]}; bricht beim Signal von ACancellation ab
    /// (nil = nie). Threadsicher.</summary>
    function DocumentReport(const AUri, APreviousResultId: string;
      const ACancellation: IJsonRpcCancellationToken): TJSONObject;
    /// <summary>Antwort auf workspace/diagnostic; wartet ohne Neuigkeiten bis WaitMs.</summary>
    function WorkspaceReport(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    property Generation: Integer read FGeneration;
    property RefreshSupport: Boolean read FRefreshSupport write FRefreshSupport;
    /// <summary>Projektprüfung (#1247): Lauf, Pausen, betroffene Dateien, Frist je Datei (FileLimitMs) und
    /// übersprungene Dateien (Skipped).</summary>
    property Check: TLspWorkspaceCheck read FCheck;
    property WaitMs: Cardinal read FWaitMs write FWaitMs;
    /// <summary>Wartezeit von textDocument/diagnostic auf die Prüfung einer geöffneten Datei (#1761).</summary>
    property OpenJobs: TPullOpenJobs read FOpenJobs;
    /// <summary>Ohne Provider gilt der Index als fertig.</summary>
    property Busy: TPullBusy read FBusy write SetBusy;
    /// <summary>Zeitlimit des Watchdogs; ohne Provider (Tests) gilt WaitMs unverändert.</summary>
    property RequestTimeout: TPullTimeout read FRequestTimeout write FRequestTimeout;
    /// <summary>Anzahl berechneter Dateibefunde, Vordergrund und Projektprüfung (für Tests und das Diagnoselog).
    /// </summary>
    property Computed: Integer read FComputed;
    /// <summary>Kennzeichen je Datei für das Diagnoselog; ohne Provider steht dort "unit".</summary>
    property FileLabel: TPullFileLabel read FFileLabel write FFileLabel;
  end;

implementation

uses
  System.Classes,
  System.Diagnostics,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.CompactJson,
  Atlas.Common.Diagnostics.RequestScope,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.TextDocument,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TPullDiagnosticsText = (FieldTextDocumentUriMissingIn, StillChecking);

const
  cTexts: array[TPullDiagnosticsText] of TAtlasText = (
    (De: 'Feld "textDocument.uri" fehlt in '; En: 'Field "textDocument.uri" missing in '),
    (De: 'Prüfung läuft noch (nach %d ms); die Befunde folgen nach workspace/diagnostic/refresh.';
     En: 'Check still running (after %d ms); the findings follow after workspace/diagnostic/refresh.'));

{$SCOPEDENUMS OFF}

/// <summary>Kennzeichen von AFileName für das Diagnoselog; ohne AFileLabel "unit".</summary>
function LabelOf(const AFileLabel: TPullFileLabel; const AFileName: string): string;
begin
  Result := 'unit';
  if Assigned(AFileLabel) then
  begin
    Result := AFileLabel(AFileName);
  end;
end;

/// <summary>Zeitrahmen einer Anfrage aus ARequestTimeout; High(Cardinal) ohne Limit.</summary>
function TimeLimit(const ARequestTimeout: TPullTimeout): Cardinal;
begin
  if Assigned(ARequestTimeout) then
  begin
    Result := TLspPullProtocol.TimeLimitMs(ARequestTimeout());
  end
  else
  begin
    Result := High(Cardinal);
  end;
end;

/// <summary>Abbruch der Regelprüfung beim Signal von ACancellation; nil ohne.</summary>
function RequestCancelled(const ACancellation: IJsonRpcCancellationToken): TRuleCancelled;
begin
  Result := nil;
  if ACancellation <> nil then
  begin
    Result :=
      function: Boolean
      begin
        Result := ACancellation.IsCancellationRequested;
      end;
  end;
end;

/// <summary>Befunde von ADocument; ACancelled bricht vor jeder Prüfregel ab.</summary>
function Diagnose(ADiagnostics: TLspSyntaxDiagnostics; const ADocument: ITextDocument;
  const ACancelled: TRuleCancelled; const ACancellation: IJsonRpcCancellationToken): TJSONArray;
var
  mParams: TJSONObject;
begin
  try
    mParams := ADiagnostics.Compute(ADocument, ACancelled);
  except
    on ERuleCheckCancelled do
    begin
      // Liefert EJsonRpcRequestCancelled bzw. EJsonRpcContentModified wie jede abgebrochene Anfrage.
      if ACancellation <> nil then
      begin
        ACancellation.ThrowIfCancellationRequested;
      end;
      // Ohne Signal der Anfrage: Das Dokument hat sich geändert (DocumentCancelled).
      raise EJsonRpcContentModified.Create;
    end;
  end;
  try
    Result := mParams.GetValue('diagnostics').Clone as TJSONArray;
  finally
    mParams.Free;
  end;
end;

{ TLspPullDiagnostics }

constructor TLspPullDiagnostics.Create(const AStore: IDocumentStore; ADiagnostics: TLspSyntaxDiagnostics;
  const ATransport: IJsonRpcTransport; const AFiles: TPullFilesProvider; const AStamp: TPullFileStamp;
  const AReadText: TPullReadText);
begin
  inherited Create;
  FStore := AStore;
  FDiagnostics := ADiagnostics;
  FTransport := ATransport;
  FStamp := AStamp;
  FReadText := AReadText;
  FGeneration := 1;
  FWaitMs := cDefaultWaitMs;
  FReports := TPullReportCache.Create;
  FOpenJobs := TPullOpenJobs.Create(Self);
  FCheck := CreateCheck(AFiles);
end;

function TLspPullDiagnostics.CreateCheck(const AFiles: TPullFilesProvider): TLspWorkspaceCheck;
var
  mOwner: TLspPullDiagnostics;
begin
  mOwner := Self;
  Result := TLspWorkspaceCheck.Create(AFiles, FStamp, FReadText,
    function(const AUri: string): Boolean
    var
      mDocument: ITextDocument;
    begin
      Result := mOwner.FStore.TryGet(AUri, mDocument);
    end,
    function(const ADocument: ITextDocument; const ACancellation: IJsonRpcCancellationToken): TJSONArray
    begin
      Result := Diagnose(mOwner.FDiagnostics, ADocument, RequestCancelled(ACancellation), ACancellation);
      TInterlocked.Increment(mOwner.FComputed);
    end);
  Result.FileLabel :=
    function(const AFileName: string): string
    begin
      Result := LabelOf(mOwner.FFileLabel, AFileName);
    end;
end;

destructor TLspPullDiagnostics.Destroy;
begin
  // Zuerst die Prüfungen geöffneter Dateien: Sie enden vor der nächsten Regel und rechnen mit FCheck, FReports,
  // FDiagnostics und FStore.
  FOpenJobs.Free;
  // Dann: Der Thread der Projektprüfung rechnet mit FDiagnostics und FStore.
  FCheck.Free;
  FReports.Free;
  inherited;
end;

procedure TLspPullDiagnostics.SetBusy(const AValue: TPullBusy);
begin
  FBusy := AValue;
  FCheck.Busy := AValue;
end;

procedure TLspPullDiagnostics.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(cDocumentMethod, HandleDocument);
  ADispatcher.RegisterConcurrentRequest(cWorkspaceMethod, WorkspaceReport);
  ADispatcher.RegisterNotification(cPauseMethod, HandlePause);
end;

class function TLspPullProtocol.ClientSupportsPull(const AInitializeParams: TJSONObject): Boolean;
begin
  Result := (AInitializeParams <> nil) and (AInitializeParams.FindValue('capabilities.textDocument.diagnostic') <> nil);
end;

class function TLspPullProtocol.ClientSupportsRefresh(const AInitializeParams: TJSONObject): Boolean;
var
  mValue: Boolean;
begin
  Result := (AInitializeParams <> nil) and
    AInitializeParams.TryGetValue<Boolean>('capabilities.workspace.diagnostics.refreshSupport', mValue) and mValue;
end;

class function TLspPullProtocol.Capability: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('identifier', TLspPullDiagnostics.cIdentifier);
  Result.AddPair('interFileDependencies', TJSONBool.Create(True));
  Result.AddPair('workspaceDiagnostics', TJSONBool.Create(True));
end;

class function TLspPullProtocol.TimeLimitMs(ATimeoutMs: Cardinal): Cardinal;
var
  mHalf, mReserved: Int64;
begin
  if ATimeoutMs = 0 then
  begin
    Exit(High(Cardinal));
  end;
  mHalf := Int64(ATimeoutMs) div 2;
  mReserved := Int64(ATimeoutMs) - 2000;
  if mReserved > mHalf then
  begin
    Result := Cardinal(mReserved);
  end
  else
  begin
    Result := Cardinal(mHalf);
  end;
end;

class function TLspPullProtocol.LongPollMs(AWaitMs, ATimeoutMs: Cardinal): Cardinal;
begin
  Result := TimeLimitMs(ATimeoutMs);
  if AWaitMs < Result then
  begin
    Result := AWaitMs;
  end;
end;


procedure TLspPullDiagnostics.NextGeneration;
begin
  TInterlocked.Increment(FGeneration);
  SendRefresh;
end;

procedure TLspPullDiagnostics.SendRefresh;
var
  mRequest: TJSONObject;
  mCounter: Integer;
begin
  if not FRefreshSupport or (FTransport = nil) then
  begin
    Exit;
  end;
  // Geöffnete Dokumente holt der Client nach refresh neu ab (z. B. nach einem Compilerlauf).
  mCounter := TInterlocked.Increment(FRefreshCounter);
  mRequest := TJSONObject.Create;
  try
    mRequest.AddPair('jsonrpc', '2.0');
    mRequest.AddPair('id', Format('atlas/diagnostic-refresh-%d', [mCounter]));
    mRequest.AddPair('method', cRefreshMethod);
    FTransport.WriteMessage(mRequest);
  finally
    mRequest.Free;
  end;
end;

procedure TLspPullDiagnostics.Changed;
begin
  NextGeneration;
  // Erzwungener Lauf über alle Units: Einstellungen oder Index gelten für alle.
  FCheck.Start(True);
end;

procedure TLspPullDiagnostics.FilesChanged(const AFiles: TArray<string>);
begin
  NextGeneration;
  // Nur diese Dateien (#1247): Früher veralteten nach jedem Build die Befunde aller Units.
  FCheck.Affected(AFiles, False);
end;

procedure TLspPullDiagnostics.Typed;
begin
  FCheck.Typed;
end;

procedure TLspPullDiagnostics.HandlePause(const AParams: TJSONValue);
var
  mReason: string;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('reason', mReason)) or
    (mReason = '') then
  begin
    Exit;
  end;
  FCheck.Pause(mReason, TJSONObject(AParams).GetValue<Boolean>('paused', False));
end;


/// <summary>Abbruch der Prüfung der geöffneten Datei ADocument: bei geändertem Dokument oder neuer Generation,
/// beim Beenden und nach DetachedMaxMs; nicht durch Zeitlimit oder Abbruch einer wartenden Anfrage.</summary>
function DocumentCancelled(AJobs: TPullOpenJobs; const ADocument: ITextDocument;
  AGeneration: Integer): TRuleCancelled;
var
  mClock: TStopwatch;
begin
  mClock := TStopwatch.StartNew;
  Result :=
    function: Boolean
    begin
      Result := AJobs.Stopping or AJobs.Outdated(ADocument, AGeneration) or
        (mClock.ElapsedMilliseconds > TLspPullDiagnostics.cDetachedMaxMs);
    end;
end;

/// <summary>Berechnung der Befunde von ADocument für den Speicher; zählt Computed.</summary>
function Computation(AOwner: TLspPullDiagnostics; const ADocument: ITextDocument; const ACancelled: TRuleCancelled;
  const ACancellation: IJsonRpcCancellationToken): TPullCompute;
begin
  Result :=
    function: TJSONArray
    begin
      Result := Diagnose(AOwner.FDiagnostics, ADocument, ACancelled, ACancellation);
      TInterlocked.Increment(AOwner.FComputed);
    end;
end;

type
  /// <summary>Zustand über TInterlocked; Ergebnis bzw. Fehler stehen fest, bevor der Zustand auf fertig wechselt.
  /// </summary>
  TPullDocumentJob = class(TInterfacedObject, IPullDocumentJob)
  private const
    cRunning = 0;
    cDone = 1;
    cAbandoned = 2;
    cDoneAbandoned = 3;
  private
    FState: Integer;
    /// <summary>Gesetzt mit Finish; Wartende schlafen darauf, statt den Zustand abzufragen.</summary>
    FDone: TEvent;
    FItems: TBytes;
    FErrorClass: ExceptClass;
    FErrorMessage: string;
    FErrorCode: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    function Finished: Boolean;
    function WaitFinished(ATimeoutMs: Cardinal): Boolean;
    function Abandon: Boolean;
    function Finish: Boolean;
    procedure Succeed(const AItems: TJSONArray);
    procedure Fail(AError: Exception);
    function Failed: Boolean;
    function Items: TJSONArray;
  end;

{ TPullDocumentJob }

constructor TPullDocumentJob.Create;
begin
  inherited Create;
  FDone := TEvent.Create(nil, True, False, '');
end;

destructor TPullDocumentJob.Destroy;
begin
  FDone.Free;
  inherited;
end;

function TPullDocumentJob.WaitFinished(ATimeoutMs: Cardinal): Boolean;
begin
  Result := Finished or (FDone.WaitFor(ATimeoutMs) = wrSignaled);
end;

procedure TPullDocumentJob.Succeed(const AItems: TJSONArray);
begin
  FItems := TCompactJson.Pack(AItems);
end;

function TPullDocumentJob.Failed: Boolean;
begin
  Result := FErrorClass <> nil;
end;

function TPullDocumentJob.Finished: Boolean;
var
  mState: Integer;
begin
  mState := TInterlocked.CompareExchange(FState, 0, 0);
  Result := (mState = cDone) or (mState = cDoneAbandoned);
end;

function TPullDocumentJob.Abandon: Boolean;
var
  mState: Integer;
begin
  mState := TInterlocked.CompareExchange(FState, cAbandoned, cRunning);
  Result := (mState = cRunning) or (mState = cAbandoned);
end;

function TPullDocumentJob.Finish: Boolean;
begin
  Result := TInterlocked.CompareExchange(FState, cDone, cRunning) = cAbandoned;
  if Result then
  begin
    TInterlocked.Exchange(FState, cDoneAbandoned);
  end;
  // Erst nach dem Zustand: Wer aufwacht, sieht Finished.
  FDone.SetEvent;
end;

procedure TPullDocumentJob.Fail(AError: Exception);
begin
  FErrorClass := ExceptClass(AError.ClassType);
  FErrorMessage := AError.Message;
  FErrorCode := 0;
  if AError is EJsonRpcError then
  begin
    FErrorCode := EJsonRpcError(AError).Code;
  end;
end;

function TPullDocumentJob.Items: TJSONArray;
begin
  if FErrorClass = nil then
  begin
    Exit(TCompactJson.UnpackArray(FItems));
  end;
  if FErrorCode <> 0 then
  begin
    raise EJsonRpcError.Create(FErrorCode, FErrorMessage);
  end;
  // Gewollt: dieselbe Klasse mit derselben Meldung; eigene Felder hat nur EJsonRpcError (oben).
  // lsp-ignore: class-reference-nonvirtual-constructor -- nur die Meldung wird übertragen
  raise FErrorClass.Create(FErrorMessage);
end;

{ TPullOpenJobs }

constructor TPullOpenJobs.Create(AOwner: TLspPullDiagnostics);
begin
  inherited Create;
  FOwner := AOwner;
  FJobs := TDictionary<string, IPullDocumentJob>.Create;
  FWaitMs := TLspPullDiagnostics.cDefaultDocumentWaitMs;
end;

destructor TPullOpenJobs.Destroy;
begin
  TInterlocked.Exchange(FStopping, 1);
  // Laufende Prüfungen enden vor der nächsten Regel; JobProc weckt nach jedem Ende.
  System.TMonitor.Enter(FJobs);
  try
    while TInterlocked.CompareExchange(FRunning, 0, 0) > 0 do
    begin
      System.TMonitor.Wait(FJobs, TLspPullDiagnostics.cChangeSliceMs);
    end;
  finally
    System.TMonitor.Exit(FJobs);
  end;
  FJobs.Free;
  inherited;
end;

function TPullOpenJobs.Stopping: Boolean;
begin
  Result := TInterlocked.CompareExchange(FStopping, 0, 0) <> 0;
end;

function TPullOpenJobs.Outdated(const ADocument: ITextDocument; AGeneration: Integer): Boolean;
var
  mCurrent: ITextDocument;
begin
  Result := (TInterlocked.CompareExchange(FOwner.FGeneration, 0, 0) <> AGeneration) or
    not FOwner.FStore.TryGet(ADocument.Uri, mCurrent) or (mCurrent.Version <> ADocument.Version);
end;

function TPullOpenJobs.Wait: Cardinal;
begin
  Result := FWaitMs;
  if TimeLimit(FOwner.FRequestTimeout) < Result then
  begin
    Result := TimeLimit(FOwner.FRequestTimeout);
  end;
end;

procedure TPullOpenJobs.Run(const AJob: IPullDocumentJob; const AKey, AResultId: string;
  const ADocument: ITextDocument; AGeneration: Integer);
var
  mItems: TJSONArray;
begin
  // Vorrang vor der Projektprüfung (#1247): Sie beginnt solange keine neue Datei.
  FOwner.FCheck.EnterForeground;
  try
    try
      mItems := FOwner.FReports.Get(ADocument.Uri, AResultId,
        Computation(FOwner, ADocument, DocumentCancelled(Self, ADocument, AGeneration), nil), nil);
      try
        AJob.Succeed(mItems);
      finally
        mItems.Free;
      end;
    except
      // lsp-ignore: catch-all-without-raise -- Fehlergrenze des Hintergrundjobs; AJob.Fail meldet
      on E: Exception do
      begin
        AJob.Fail(E);
      end;
    end;
  finally
    FOwner.FCheck.LeaveForeground;
  end;
  System.TMonitor.Enter(FJobs);
  try
    FJobs.Remove(AKey);
  finally
    System.TMonitor.Exit(FJobs);
  end;
  // Keine Anfrage hat das Ergebnis abgewartet: Der Client holt es nach refresh ab.
  if AJob.Finish and not AJob.Failed then
  begin
    FOwner.SendRefresh;
  end;
end;

/// <summary>Arbeit des Threads einer Dateiprüfung; hält AJob bis zum Ende.</summary>
function JobProc(AJobs: TPullOpenJobs; const AJob: IPullDocumentJob; const AKey, AResultId: string;
  const ADocument: ITextDocument; AGeneration: Integer): TProc;
begin
  Result :=
    procedure
    begin
      try
        AJobs.Run(AJob, AKey, AResultId, ADocument, AGeneration);
      finally
        // Unter der Sperre, damit Destroy zwischen Prüfen und Warten kein Ende verpasst.
        System.TMonitor.Enter(AJobs.FJobs);
        try
          TInterlocked.Decrement(AJobs.FRunning);
          System.TMonitor.PulseAll(AJobs.FJobs);
        finally
          System.TMonitor.Exit(AJobs.FJobs);
        end;
      end;
    end;
end;

function TPullOpenJobs.Start(const AResultId: string; const ADocument: ITextDocument;
  AGeneration: Integer): IPullDocumentJob;
var
  mKey: string;
begin
  mKey := ADocument.Uri + #0 + AResultId;
  System.TMonitor.Enter(FJobs);
  try
    if FJobs.TryGetValue(mKey, Result) then
    begin
      Exit;
    end;
    Result := TPullDocumentJob.Create;
    FJobs.Add(mKey, Result);
    TInterlocked.Increment(FRunning);
  finally
    System.TMonitor.Exit(FJobs);
  end;
  TThread.CreateAnonymousThread(JobProc(Self, Result, mKey, AResultId, ADocument, AGeneration)).Start;
end;

function TPullOpenJobs.Items(const AResultId: string; const ADocument: ITextDocument;
  AGeneration: Integer; const ACancellation: IJsonRpcCancellationToken): TJSONArray;
var
  mJob: IPullDocumentJob;
  mClock: TStopwatch;
  mWait: Cardinal;
begin
  mClock := TStopwatch.StartNew;
  mWait := Wait;
  mJob := Start(AResultId, ADocument, AGeneration);
  while not mJob.Finished do
  begin
    if (ACancellation <> nil) and ACancellation.IsCancellationRequested then
    begin
      // Die Prüfung rechnet weiter; der Client holt ihr Ergebnis nach refresh ab.
      mJob.Abandon;
      ACancellation.ThrowIfCancellationRequested;
    end;
    if (mClock.ElapsedMilliseconds >= Int64(mWait)) and mJob.Abandon then
    begin
      raise EJsonRpcError.Create(TLspErrorCode.cServerCancelled,
        cTexts[TPullDiagnosticsText.StillChecking].Fmt([mWait]));
    end;
    // Das Ende der Prüfung weckt sofort; Abbruch und Wartezeit im Takt ChangeSliceMs.
    mJob.WaitFinished(TLspPullDiagnostics.cChangeSliceMs);
  end;
  Result := mJob.Items;
end;

{ TLspPullDiagnostics }

/// <summary>Stand der Datei AUri für textDocument/diagnostic: Ergebnis-Id ('' ohne Stand, etwa atlas.json, das
/// TLspConfiguration prüft und per publishDiagnostics meldet), Generation, ADocument (nil ohne) und ob sie
/// geöffnet ist.</summary>
function DocumentState(AOwner: TLspPullDiagnostics; const AUri, AFileName: string; out AGeneration: Integer;
  out ADocument: ITextDocument; out AOpen: Boolean): string;
var
  mText: string;
  mStamp: Int64;
begin
  Result := '';
  ADocument := nil;
  AOpen := False;
  AGeneration := TInterlocked.CompareExchange(AOwner.FGeneration, 0, 0);
  if SameText(ExtractFileExt(AFileName), '.json') then
  begin
    Exit;
  end;
  if AOwner.FStore.TryGet(AUri, ADocument) then
  begin
    Result := Format('%d:v%d', [AGeneration, ADocument.Version]);
    AOpen := True;
  end
  else if Assigned(AOwner.FStamp) and AOwner.FStamp(AFileName, mStamp) and AOwner.FReadText(AFileName, mText) then
  begin
    Result := Format('%d:t%d', [AGeneration, mStamp]);
    ADocument := TTextDocument.Create(AUri, 'objectpascal', 0, mText);
  end;
end;

/// <summary>Befunde von ADocument im Stand AResultId: geöffnet über eine eigene Prüfung (#1761), sonst über den
/// Speicher mit Vorrang vor der Projektprüfung (#1247).</summary>
function DocumentItems(AOwner: TLspPullDiagnostics; const ADocument: ITextDocument; const AResultId: string;
  AGeneration: Integer; AOpen: Boolean; const ACancellation: IJsonRpcCancellationToken): TJSONArray;
begin
  if AOpen then
  begin
    // Die Prüfung läuft im eigenen Thread zu Ende, auch wenn die Anfrage vorher antwortet.
    Exit(AOwner.FOpenJobs.Items(AResultId, ADocument, AGeneration, ACancellation));
  end;
  AOwner.FCheck.EnterForeground;
  try
    Result := AOwner.FReports.Get(ADocument.Uri, AResultId,
      Computation(AOwner, ADocument, RequestCancelled(ACancellation), ACancellation), ACancellation);
  finally
    AOwner.FCheck.LeaveForeground;
  end;
end;

function TLspPullDiagnostics.DocumentReport(const AUri, APreviousResultId: string;
  const ACancellation: IJsonRpcCancellationToken): TJSONObject;
var
  mDocument: ITextDocument;
  mFileName, mResultId: string;
  mGeneration: Integer;
  mOpen: Boolean;
begin
  mFileName := TDocumentUris.ToPath(AUri);
  mResultId := DocumentState(Self, AUri, mFileName, mGeneration, mDocument, mOpen);
  Result := TJSONObject.Create;
  if (mResultId <> '') and (mResultId = APreviousResultId) then
  begin
    Result.AddPair('kind', 'unchanged');
    Result.AddPair('resultId', mResultId);
    Exit;
  end;
  Result.AddPair('kind', 'full');
  if mResultId <> '' then
  begin
    Result.AddPair('resultId', mResultId);
  end;
  if mDocument = nil then
  begin
    Result.AddPair('items', TJSONArray.Create);
    Exit;
  end;
  TRequestDiagnostics.Subject(LabelOf(FFileLabel, mFileName));
  try
    Result.AddPair('items', DocumentItems(Self, mDocument, mResultId, mGeneration, mOpen, ACancellation));
    TRequestDiagnostics.Subject('');
  except
    Result.Free;
    raise;
  end;
end;

function TLspPullDiagnostics.HandleDocument(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mUri, mPrevious: string;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TPullDiagnosticsText.FieldTextDocumentUriMissingIn].Text + cDocumentMethod);
  end;
  if not TJSONObject(AParams).TryGetValue<string>('previousResultId', mPrevious) then
  begin
    mPrevious := '';
  end;
  ACancellation.ThrowIfCancellationRequested;
  Result := DocumentReport(mUri, mPrevious, ACancellation);
end;

/// <summary>previousResultIds der Anfrage AParams nach APrevious (Uri -> Ergebnis-Id).</summary>
procedure ReadPreviousIds(const AParams: TJSONValue; APrevious: TDictionary<string, string>);
var
  mPreviousIds: TJSONArray;
  mEntry: TJSONValue;
  mUri, mValue: string;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<TJSONArray>('previousResultIds',
    mPreviousIds)) then
  begin
    Exit;
  end;
  for mEntry in mPreviousIds do
  begin
    if mEntry.TryGetValue<string>('uri', mUri) and mEntry.TryGetValue<string>('value', mValue) then
    begin
      APrevious.AddOrSetValue(mUri, mValue);
    end;
  end;
end;

/// <summary>Befunde gebündelt ausliefern: Solange der Lauf rechnet, folgen gleich weitere. Früher kam jede Unit
/// einzeln, der Client fragte sofort neu, und das Plugin baute seine Ansicht je Unit neu auf.</summary>
function ReadyToSend(ACheck: TLspWorkspaceCheck; AItems: TJSONArray; const AClock: TStopwatch): Boolean;
begin
  Result := (AItems.Count > 0) and ((AClock.ElapsedMilliseconds >= TLspPullDiagnostics.cBatchMs) or
    (AItems.Count >= TLspPullDiagnostics.cMaxWorkspaceReports) or not ACheck.Run.Active);
end;

/// <summary>Befunde der Projektprüfung; gibt es nichts Neues, wartet es bis APollMs auf neue Befunde oder einen
/// neuen Stand des Laufs (Long-Polling). Der Aufrufer übernimmt das Ergebnis.</summary>
function CollectWaiting(ACheck: TLspWorkspaceCheck; APrevious: TDictionary<string, string>;
  const AClock: TStopwatch; APollMs: Cardinal; const ACancellation: IJsonRpcCancellationToken): TJSONArray;
var
  mChange, mNext: Integer;
  mStart, mNow: TWorkspaceCheckRun;
begin
  mChange := ACheck.ChangeCount;
  mStart := ACheck.Run;
  Result := ACheck.Collect(APrevious, TLspPullDiagnostics.cMaxWorkspaceReports);
  while (AClock.ElapsedMilliseconds < Int64(APollMs)) and not ACancellation.IsCancellationRequested and
    not ReadyToSend(ACheck, Result, AClock) do
  begin
    mNext := ACheck.WaitForChange(mChange, TLspPullDiagnostics.cChangeSliceMs);
    if mNext = mChange then
    begin
      Continue;
    end;
    mChange := mNext;
    Result.Free;
    Result := ACheck.Collect(APrevious, TLspPullDiagnostics.cMaxWorkspaceReports);
    mNow := ACheck.Run;
    // Anfang, Ende, Pause sofort melden; bloßen Fortschritt höchstens alle ProgressMs.
    if mNow.StateDiffers(mStart) or ((mNow.Done <> mStart.Done) and
      (AClock.ElapsedMilliseconds >= TLspPullDiagnostics.cProgressMs)) then
    begin
      Break;
    end;
  end;
end;

/// <summary>Grund einer leeren Antwort für das Diagnoselog.</summary>
procedure NoteEmpty(const ARun: TWorkspaceCheckRun; ABusy: Boolean);
begin
  if (ARun.Paused = TLspWorkspaceCheck.cPauseIndex) or ABusy then
  begin
    TRequestDiagnostics.Reason(TLspPullDiagnostics.cReasonIndexLoading);
  end
  else
  begin
    TRequestDiagnostics.DefaultReason(TLspPullDiagnostics.cReasonNoChanges);
  end;
end;

function TLspPullDiagnostics.WorkspaceReport(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mPrevious: TDictionary<string, string>;
  mItems: TJSONArray;
  mClock: TStopwatch;
  mPollMs: Cardinal;
  mNow: TWorkspaceCheckRun;
  mAtlas: TJSONObject;
begin
  // Zeitrahmen der Anfrage: Antwort vor dem Zeitlimit des Watchdogs (P-14).
  mClock := TStopwatch.StartNew;
  mPollMs := FWaitMs;
  if TimeLimit(FRequestTimeout) < mPollMs then
  begin
    mPollMs := TimeLimit(FRequestTimeout);
  end;
  // Die erste Anfrage startet die Projektprüfung.
  FCheck.Want;
  mPrevious := TDictionary<string, string>.Create;
  try
    ReadPreviousIds(AParams, mPrevious);
    mItems := CollectWaiting(FCheck, mPrevious, mClock, mPollMs, ACancellation);
    mNow := FCheck.Run;
    if mItems.Count = 0 then
    begin
      NoteEmpty(mNow, Assigned(FBusy) and FBusy());
    end;
    Result := TJSONObject.Create;
    TJSONObject(Result).AddPair('items', mItems);
    // Fortschritt für die Statusleiste des Plugins (#1232); andere Clients übergehen das Feld.
    mAtlas := TJSONObject.Create;
    mAtlas.AddPair('run', mNow.ToJson);
    TJSONObject(Result).AddPair('atlas', mAtlas);
  finally
    mPrevious.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.PullDiagnostics', cTexts);

end.
