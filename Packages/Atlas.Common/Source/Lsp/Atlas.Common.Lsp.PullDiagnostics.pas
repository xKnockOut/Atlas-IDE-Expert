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

  TLspPullDiagnostics = class
  public const
    DocumentMethod = 'textDocument/diagnostic';
    WorkspaceMethod = 'workspace/diagnostic';
    RefreshMethod = 'workspace/diagnostic/refresh';
    /// <summary>Pause der Projektprüfung vom Client (#1247), z. B. {"reason":"debug","paused":true} beim
    /// Debuggen (#1241).</summary>
    PauseMethod = 'atlas/workspaceCheck/pause';
    /// <summary>Alle Dateien neu prüfen (#1231, Klick auf die Live-Prüfung der Atlas-Statusleiste): ruft Changed.
    /// </summary>
    RecheckCommand = 'atlas.server.recheck';
    Identifier = 'atlas';
    DefaultWaitMs = 10000;
    /// <summary>Grundcodes leerer Antworten im Diagnoselog (#647).</summary>
    ReasonIndexLoading = 'indexLoading';
    ReasonNoChanges = 'noChanges';
    /// <summary>Höchstzahl Dateibefunde je Antwort; den Rest holt der Client gleich mit der nächsten.</summary>
    MaxWorkspaceReports = 200;
    /// <summary>Takt, in dem Wartende den Abbruch prüfen; Änderungen wecken sofort.</summary>
    ChangeSliceMs = 100;
    /// <summary>Neuer Fortschritt ohne neue Befunde beendet das Long-Polling frühestens nach dieser Zeit.</summary>
    ProgressMs = 1000;
    /// <summary>Neue Befunde während eines Laufs sammelt eine Anfrage so lange, bevor sie antwortet.</summary>
    BatchMs = 1000;
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
    function IsBusy: Boolean;
    procedure SetBusy(const AValue: TPullBusy);
    /// <summary>Projektprüfung mit den Anbietern dieses Objekts anlegen.</summary>
    function CreateCheck(const AFiles: TPullFilesProvider): TLspWorkspaceCheck;
    /// <summary>Generation heben und geöffnete Dokumente neu holen lassen.</summary>
    procedure NextGeneration;
    /// <summary>Zeitrahmen dieser Anfrage aus RequestTimeout; High(Cardinal) ohne Limit.</summary>
    function TimeLimit: Cardinal;
    function LabelOf(const AFileName: string): string;
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
  System.Diagnostics,
  Atlas.Common.Diagnostics.RequestScope,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.TextDocument;

function Diagnose(ADiagnostics: TLspSyntaxDiagnostics; const ADocument: ITextDocument;
  const ACancellation: IJsonRpcCancellationToken): TJSONArray;
var
  Params: TJSONObject;
  Cancelled: TRuleCancelled;
begin
  Cancelled := nil;
  if ACancellation <> nil then
  begin
    Cancelled :=
      function: Boolean
      begin
        Result := ACancellation.IsCancellationRequested;
      end;
  end;
  try
    Params := ADiagnostics.Compute(ADocument, Cancelled);
  except
    on ERuleCheckCancelled do
    begin
      // Liefert EJsonRpcRequestCancelled bzw. EJsonRpcContentModified wie jede abgebrochene Anfrage.
      if ACancellation <> nil then
      begin
        ACancellation.ThrowIfCancellationRequested;
      end;
      raise;
    end;
  end;
  try
    Result := Params.GetValue('diagnostics').Clone as TJSONArray;
  finally
    Params.Free;
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
  FWaitMs := DefaultWaitMs;
  FReports := TPullReportCache.Create;
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
      Result := Diagnose(mOwner.FDiagnostics, ADocument, ACancellation);
      TInterlocked.Increment(mOwner.FComputed);
    end);
  Result.FileLabel :=
    function(const AFileName: string): string
    begin
      Result := mOwner.LabelOf(AFileName);
    end;
end;

destructor TLspPullDiagnostics.Destroy;
begin
  // Zuerst: Der Thread der Projektprüfung rechnet mit FDiagnostics und FStore.
  FCheck.Free;
  FReports.Free;
  inherited;
end;

function TLspPullDiagnostics.IsBusy: Boolean;
begin
  Result := Assigned(FBusy) and FBusy();
end;

procedure TLspPullDiagnostics.SetBusy(const AValue: TPullBusy);
begin
  FBusy := AValue;
  FCheck.Busy := AValue;
end;

procedure TLspPullDiagnostics.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(DocumentMethod, HandleDocument);
  ADispatcher.RegisterConcurrentRequest(WorkspaceMethod, WorkspaceReport);
  ADispatcher.RegisterNotification(PauseMethod, HandlePause);
end;

class function TLspPullProtocol.ClientSupportsPull(const AInitializeParams: TJSONObject): Boolean;
begin
  Result := (AInitializeParams <> nil) and (AInitializeParams.FindValue('capabilities.textDocument.diagnostic') <> nil);
end;

class function TLspPullProtocol.ClientSupportsRefresh(const AInitializeParams: TJSONObject): Boolean;
var
  Value: Boolean;
begin
  Result := (AInitializeParams <> nil) and
    AInitializeParams.TryGetValue<Boolean>('capabilities.workspace.diagnostics.refreshSupport', Value) and Value;
end;

class function TLspPullProtocol.Capability: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('identifier', TLspPullDiagnostics.Identifier);
  Result.AddPair('interFileDependencies', TJSONBool.Create(True));
  Result.AddPair('workspaceDiagnostics', TJSONBool.Create(True));
end;

class function TLspPullProtocol.TimeLimitMs(ATimeoutMs: Cardinal): Cardinal;
var
  Half, Reserved: Int64;
begin
  if ATimeoutMs = 0 then
  begin
    Exit(High(Cardinal));
  end;
  Half := Int64(ATimeoutMs) div 2;
  Reserved := Int64(ATimeoutMs) - 2000;
  if Reserved > Half then
  begin
    Result := Cardinal(Reserved);
  end
  else
  begin
    Result := Cardinal(Half);
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

function TLspPullDiagnostics.LabelOf(const AFileName: string): string;
begin
  Result := 'unit';
  if Assigned(FFileLabel) then
  begin
    Result := FFileLabel(AFileName);
  end;
end;

function TLspPullDiagnostics.TimeLimit: Cardinal;
begin
  if Assigned(FRequestTimeout) then
  begin
    Result := TLspPullProtocol.TimeLimitMs(FRequestTimeout());
  end
  else
  begin
    Result := High(Cardinal);
  end;
end;

procedure TLspPullDiagnostics.NextGeneration;
var
  Request: TJSONObject;
  Counter: Integer;
begin
  TInterlocked.Increment(FGeneration);
  if not FRefreshSupport or (FTransport = nil) then
  begin
    Exit;
  end;
  // Geöffnete Dokumente holt der Client nach refresh neu ab (z. B. nach einem Compilerlauf).
  Counter := TInterlocked.Increment(FRefreshCounter);
  Request := TJSONObject.Create;
  try
    Request.AddPair('jsonrpc', '2.0');
    Request.AddPair('id', Format('atlas/diagnostic-refresh-%d', [Counter]));
    Request.AddPair('method', RefreshMethod);
    FTransport.WriteMessage(Request);
  finally
    Request.Free;
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

/// <summary>Berechnung der Befunde von ADocument für den Speicher; zählt Computed.</summary>
function Computation(AOwner: TLspPullDiagnostics; const ADocument: ITextDocument;
  const ACancellation: IJsonRpcCancellationToken): TPullCompute;
begin
  Result :=
    function: TJSONArray
    begin
      Result := Diagnose(AOwner.FDiagnostics, ADocument, ACancellation);
      TInterlocked.Increment(AOwner.FComputed);
    end;
end;

function TLspPullDiagnostics.DocumentReport(const AUri, APreviousResultId: string;
  const ACancellation: IJsonRpcCancellationToken): TJSONObject;
var
  Document: ITextDocument;
  FileName, Text, ResultId: string;
  Stamp: Int64;
begin
  FileName := TDocumentUris.ToPath(AUri);
  // atlas.json prüft TLspConfiguration und meldet weiter per publishDiagnostics.
  if SameText(ExtractFileExt(FileName), '.json') then
  begin
    ResultId := '';
  end
  else if FStore.TryGet(AUri, Document) then
  begin
    ResultId := Format('%d:v%d', [FGeneration, Document.Version]);
  end
  else if Assigned(FStamp) and FStamp(FileName, Stamp) and FReadText(FileName, Text) then
  begin
    ResultId := Format('%d:t%d', [FGeneration, Stamp]);
    Document := TTextDocument.Create(AUri, 'objectpascal', 0, Text);
  end
  else
  begin
    ResultId := '';
  end;
  Result := TJSONObject.Create;
  if (ResultId <> '') and (ResultId = APreviousResultId) then
  begin
    Result.AddPair('kind', 'unchanged');
    Result.AddPair('resultId', ResultId);
    Exit;
  end;
  Result.AddPair('kind', 'full');
  if ResultId <> '' then
  begin
    Result.AddPair('resultId', ResultId);
  end;
  if Document = nil then
  begin
    Result.AddPair('items', TJSONArray.Create);
  end
  else
  begin
    TRequestDiagnostics.Subject(LabelOf(FileName));
    // Vorrang vor der Projektprüfung (#1247): Sie beginnt solange keine neue Datei.
    FCheck.EnterForeground;
    try
      try
        Result.AddPair('items', FReports.Get(AUri, ResultId, Computation(Self, Document, ACancellation),
          ACancellation));
        TRequestDiagnostics.Subject('');
      except
        Result.Free;
        raise;
      end;
    finally
      FCheck.LeaveForeground;
    end;
  end;
end;

function TLspPullDiagnostics.HandleDocument(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Uri, Previous: string;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Feld "textDocument.uri" fehlt in ' + DocumentMethod);
  end;
  if not TJSONObject(AParams).TryGetValue<string>('previousResultId', Previous) then
  begin
    Previous := '';
  end;
  ACancellation.ThrowIfCancellationRequested;
  Result := DocumentReport(Uri, Previous, ACancellation);
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
  Result := (AItems.Count > 0) and ((AClock.ElapsedMilliseconds >= TLspPullDiagnostics.BatchMs) or
    (AItems.Count >= TLspPullDiagnostics.MaxWorkspaceReports) or not ACheck.Run.Active);
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
  Result := ACheck.Collect(APrevious, TLspPullDiagnostics.MaxWorkspaceReports);
  while (AClock.ElapsedMilliseconds < Int64(APollMs)) and not ACancellation.IsCancellationRequested and
    not ReadyToSend(ACheck, Result, AClock) do
  begin
    mNext := ACheck.WaitForChange(mChange, TLspPullDiagnostics.ChangeSliceMs);
    if mNext = mChange then
    begin
      Continue;
    end;
    mChange := mNext;
    Result.Free;
    Result := ACheck.Collect(APrevious, TLspPullDiagnostics.MaxWorkspaceReports);
    mNow := ACheck.Run;
    // Anfang, Ende, Pause sofort melden; bloßen Fortschritt höchstens alle ProgressMs.
    if mNow.StateDiffers(mStart) or ((mNow.Done <> mStart.Done) and
      (AClock.ElapsedMilliseconds >= TLspPullDiagnostics.ProgressMs)) then
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
    TRequestDiagnostics.Reason(TLspPullDiagnostics.ReasonIndexLoading);
  end
  else
  begin
    TRequestDiagnostics.DefaultReason(TLspPullDiagnostics.ReasonNoChanges);
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
  if TimeLimit < mPollMs then
  begin
    mPollMs := TimeLimit;
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
      NoteEmpty(mNow, IsBusy);
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

end.
