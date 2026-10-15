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
// workspace/diagnostic arbeitet pro Anfrage höchstens BudgetMs und liefert den
// Rest bei der nächsten Anfrage. Gibt es nichts Neues, wartet die Anfrage bis
// WaitMs auf eine Änderung (Long-Polling), damit der Client nicht ständig fragt.
//
// Solange der Symbolindex aufgebaut wird (Busy), prüft workspace/diagnostic
// nichts (#647): Die Befunde wären voller nicht gefundener Units, kosteten
// pro Datei Hunderte Millisekunden und blieben nach dem Aufbau stehen, weil
// sich ihre Ergebnis-Id nicht ändert. Nach dem Aufbau ruft der Server Changed.
//
// CPU-Last: Es prüft immer nur eine workspace/diagnostic-Anfrage. Kommt eine
// zweite, während die erste läuft (Client hat nach einer Zeitüberschreitung neu
// gefragt), wartet sie nur auf eine Änderung und antwortet leer. Befunde einer
// Datei bleiben je Ergebnis-Id gespeichert: Fragt der Client dieselbe Datei im
// selben Stand erneut ohne previousResultId, wird nicht neu geprüft.
//
// Laufzeit (Diagnoselog 15.10.2026): Die Prüfregeln fragen vor jeder Regel das
// Abbruchsignal der Anfrage. Ein Zeitlimit, $/cancelRequest oder eine Änderung
// des Dokuments (ContentModified) beendet die Prüfung, statt sie bis zu vier
// Minuten weiterlaufen zu lassen. Fragen mehrere Anfragen dieselbe Datei im
// selben Stand an, rechnet nur die erste; die übrigen warten auf ihr Ergebnis.

interface

uses
  System.SysUtils,
  System.JSON,
  System.SyncObjs,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.SyntaxDiagnostics;

type
  /// <summary>Dateien, deren Befunde workspace/diagnostic meldet.</summary>
  TPullFilesProvider = reference to function: TArray<string>;
  /// <summary>Zeitstempel einer Datei; False, wenn sie fehlt.</summary>
  TPullFileStamp = reference to function(const AFileName: string; out AStamp: Int64): Boolean;
  /// <summary>Text einer Datei von der Platte.</summary>
  TPullReadText = reference to function(const AFileName: string; out AText: string): Boolean;
  /// <summary>True, solange der Symbolindex aufgebaut wird.</summary>
  TPullBusy = reference to function: Boolean;

  TLspPullDiagnostics = class
  public const
    DocumentMethod = 'textDocument/diagnostic';
    WorkspaceMethod = 'workspace/diagnostic';
    RefreshMethod = 'workspace/diagnostic/refresh';
    Identifier = 'atlas';
    DefaultBudgetMs = 3000;
    DefaultWaitMs = 10000;
    /// <summary>Grundcodes leerer Antworten im Diagnoselog (#647).</summary>
    ReasonIndexLoading = 'indexLoading';
    ReasonNoChanges = 'noChanges';
    /// <summary>Eine andere workspace/diagnostic-Anfrage prüft gerade.</summary>
    ReasonWorkspaceBusy = 'workspaceBusy';
    /// <summary>Höchstzahl gespeicherter Dateibefunde, danach wird der Speicher geleert.</summary>
    MaxCachedReports = 500;
    /// <summary>Takt, in dem eine Anfrage auf die gleiche Berechnung einer anderen wartet.</summary>
    RunningPollMs = 20;
  private
    FStore: IDocumentStore;
    FDiagnostics: TLspSyntaxDiagnostics;
    FTransport: IJsonRpcTransport;
    FFiles: TPullFilesProvider;
    FStamp: TPullFileStamp;
    FReadText: TPullReadText;
    FGeneration: Integer;
    FChanged: TEvent;
    FRefreshSupport: Boolean;
    FRefreshCounter: Integer;
    FBudgetMs: Cardinal;
    FWaitMs: Cardinal;
    FBusy: TPullBusy;
    // 1, solange eine workspace/diagnostic-Anfrage prüft.
    FWorkspaceActive: Integer;
    // Befunde je Datei: Uri -> (Ergebnis-Id, Befunde). Unter FCacheLock.
    FCache: TObjectDictionary<string, TJSONArray>;
    FCacheIds: TDictionary<string, string>;
    FCacheLock: TObject;
    // Laufende Berechnungen: Uri + #0 + Ergebnis-Id. Unter FCacheLock.
    FRunning: TDictionary<string, Boolean>;
    FComputed: Integer;
    function IsBusy: Boolean;
    /// <summary>Befunde zu ADocument im Stand AResultId, aus dem Speicher oder neu berechnet. Rechnet
    /// gerade eine andere Anfrage denselben Stand, wartet es auf deren Ergebnis. ACancellation darf nil sein.</summary>
    function CachedDiagnose(const AUri, AResultId: string; const ADocument: ITextDocument;
      const ACancellation: IJsonRpcCancellationToken): TJSONArray;
    /// <summary>True: Der Aufrufer rechnet AKey jetzt selbst. False mit ACached: Befunde aus dem
    /// Speicher (gehören dem Aufrufer). False ohne: Eine andere Anfrage rechnet gerade.</summary>
    function Claim(const AUri, AResultId, AKey: string; out ACached: TJSONArray): Boolean;
    /// <summary>Wartet ohne zu prüfen bis WaitMs auf eine Änderung (zweite gleichzeitige Anfrage).</summary>
    procedure WaitForChange(const ACancellation: IJsonRpcCancellationToken);
    function HandleDocument(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function CollectWorkspace(const APrevious: TDictionary<string, string>;
      const ACancellation: IJsonRpcCancellationToken; out AComplete: Boolean): TJSONArray;
  public
    constructor Create(const AStore: IDocumentStore; ADiagnostics: TLspSyntaxDiagnostics;
      const ATransport: IJsonRpcTransport; const AFiles: TPullFilesProvider; const AStamp: TPullFileStamp;
      const AReadText: TPullReadText);
    destructor Destroy; override;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>True, wenn der Client laut initialize-Parametern Pull-Diagnosen kann.</summary>
    class function ClientSupportsPull(const AInitializeParams: TJSONObject): Boolean; static;
    class function ClientSupportsRefresh(const AInitializeParams: TJSONObject): Boolean; static;
    /// <summary>Eintrag diagnosticProvider für die Server-Capabilities.</summary>
    class function Capability: TJSONObject; static;
    /// <summary>Einstellungen, Index oder Compilermeldungen haben sich geändert. Threadsicher.</summary>
    procedure Changed;
    /// <summary>Ergebnis zu einer Datei: {kind, resultId[, items]}. Threadsicher.</summary>
    function DocumentReport(const AUri, APreviousResultId: string): TJSONObject; overload;
    /// <summary>Wie DocumentReport; bricht beim Signal von ACancellation ab (nil = nie).</summary>
    function DocumentReport(const AUri, APreviousResultId: string;
      const ACancellation: IJsonRpcCancellationToken): TJSONObject; overload;
    /// <summary>Antwort auf workspace/diagnostic; wartet ohne Neuigkeiten bis WaitMs.</summary>
    function WorkspaceReport(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    property Generation: Integer read FGeneration;
    property RefreshSupport: Boolean read FRefreshSupport write FRefreshSupport;
    property BudgetMs: Cardinal read FBudgetMs write FBudgetMs;
    property WaitMs: Cardinal read FWaitMs write FWaitMs;
    /// <summary>Ohne Provider gilt der Index als fertig.</summary>
    property Busy: TPullBusy read FBusy write FBusy;
    /// <summary>Anzahl tatsächlich berechneter Dateibefunde (für Tests und das Diagnoselog).</summary>
    property Computed: Integer read FComputed;
  end;

implementation

uses
  System.Diagnostics,
  Atlas.Common.Diagnostics.RequestScope,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.TextDocument;

{ TLspPullDiagnostics }

constructor TLspPullDiagnostics.Create(const AStore: IDocumentStore; ADiagnostics: TLspSyntaxDiagnostics;
  const ATransport: IJsonRpcTransport; const AFiles: TPullFilesProvider; const AStamp: TPullFileStamp;
  const AReadText: TPullReadText);
begin
  inherited Create;
  FStore := AStore;
  FDiagnostics := ADiagnostics;
  FTransport := ATransport;
  FFiles := AFiles;
  FStamp := AStamp;
  FReadText := AReadText;
  FGeneration := 1;
  FChanged := TEvent.Create(nil, False, False, '');
  FBudgetMs := DefaultBudgetMs;
  FWaitMs := DefaultWaitMs;
  FCache := TObjectDictionary<string, TJSONArray>.Create([doOwnsValues]);
  FCacheIds := TDictionary<string, string>.Create;
  FCacheLock := TObject.Create;
  FRunning := TDictionary<string, Boolean>.Create;
end;

destructor TLspPullDiagnostics.Destroy;
begin
  FRunning.Free;
  FCacheLock.Free;
  FCacheIds.Free;
  FCache.Free;
  FChanged.Free;
  inherited;
end;

function TLspPullDiagnostics.IsBusy: Boolean;
begin
  Result := Assigned(FBusy) and FBusy();
end;

procedure TLspPullDiagnostics.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(DocumentMethod, HandleDocument);
  ADispatcher.RegisterConcurrentRequest(WorkspaceMethod, WorkspaceReport);
end;

class function TLspPullDiagnostics.ClientSupportsPull(const AInitializeParams: TJSONObject): Boolean;
begin
  Result := (AInitializeParams <> nil) and (AInitializeParams.FindValue('capabilities.textDocument.diagnostic') <> nil);
end;

class function TLspPullDiagnostics.ClientSupportsRefresh(const AInitializeParams: TJSONObject): Boolean;
var
  Value: Boolean;
begin
  Result := (AInitializeParams <> nil) and
    AInitializeParams.TryGetValue<Boolean>('capabilities.workspace.diagnostics.refreshSupport', Value) and Value;
end;

class function TLspPullDiagnostics.Capability: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('identifier', Identifier);
  Result.AddPair('interFileDependencies', TJSONBool.Create(True));
  Result.AddPair('workspaceDiagnostics', TJSONBool.Create(True));
end;

procedure TLspPullDiagnostics.Changed;
var
  Request: TJSONObject;
  Counter: Integer;
begin
  TInterlocked.Increment(FGeneration);
  FChanged.SetEvent;
  if not FRefreshSupport or (FTransport = nil) then
    Exit;
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

function Diagnose(ADiagnostics: TLspSyntaxDiagnostics; const ADocument: ITextDocument;
  const ACancellation: IJsonRpcCancellationToken): TJSONArray;
var
  Params: TJSONObject;
  Cancelled: TRuleCancelled;
begin
  Cancelled := nil;
  if ACancellation <> nil then
    Cancelled :=
      function: Boolean
      begin
        Result := ACancellation.IsCancellationRequested;
      end;
  try
    Params := ADiagnostics.Compute(ADocument, Cancelled);
  except
    on ERuleCheckCancelled do
    begin
      // Liefert EJsonRpcRequestCancelled bzw. EJsonRpcContentModified wie jede abgebrochene Anfrage.
      if ACancellation <> nil then
        ACancellation.ThrowIfCancellationRequested;
      raise;
    end;
  end;
  try
    Result := Params.GetValue('diagnostics').Clone as TJSONArray;
  finally
    Params.Free;
  end;
end;

function TLspPullDiagnostics.CachedDiagnose(const AUri, AResultId: string; const ADocument: ITextDocument;
  const ACancellation: IJsonRpcCancellationToken): TJSONArray;
var
  Key: string;
  Cached: TJSONArray;
begin
  if AResultId = '' then
  begin
    Result := Diagnose(FDiagnostics, ADocument, ACancellation);
    TInterlocked.Increment(FComputed);
    Exit;
  end;
  Key := AUri + #0 + AResultId;
  while not Claim(AUri, AResultId, Key, Cached) do
  begin
    if Cached <> nil then
      Exit(Cached);
    // Dieselbe Datei im selben Stand rechnet schon eine andere Anfrage: auf ihr Ergebnis warten.
    if ACancellation <> nil then
      ACancellation.ThrowIfCancellationRequested;
    Sleep(RunningPollMs);
  end;
  try
    Result := Diagnose(FDiagnostics, ADocument, ACancellation);
    TInterlocked.Increment(FComputed);
    TMonitor.Enter(FCacheLock);
    try
      if FCache.Count >= MaxCachedReports then
      begin
        FCache.Clear;
        FCacheIds.Clear;
      end;
      FCache.AddOrSetValue(AUri, Result.Clone as TJSONArray);
      FCacheIds.AddOrSetValue(AUri, AResultId);
    finally
      TMonitor.Exit(FCacheLock);
    end;
  finally
    TMonitor.Enter(FCacheLock);
    try
      FRunning.Remove(Key);
    finally
      TMonitor.Exit(FCacheLock);
    end;
  end;
end;

function TLspPullDiagnostics.Claim(const AUri, AResultId, AKey: string; out ACached: TJSONArray): Boolean;
var
  Known: string;
  Items: TJSONArray;
begin
  ACached := nil;
  TMonitor.Enter(FCacheLock);
  try
    if FCacheIds.TryGetValue(AUri, Known) and (Known = AResultId) and FCache.TryGetValue(AUri, Items) then
    begin
      ACached := Items.Clone as TJSONArray;
      Exit(False);
    end;
    Result := not FRunning.ContainsKey(AKey);
    if Result then
      FRunning.Add(AKey, True);
  finally
    TMonitor.Exit(FCacheLock);
  end;
end;

procedure TLspPullDiagnostics.WaitForChange(const ACancellation: IJsonRpcCancellationToken);
var
  Generation: Integer;
  Waited: Cardinal;
begin
  Generation := FGeneration;
  Waited := 0;
  while (Waited < FWaitMs) and (FGeneration = Generation) and (FWorkspaceActive <> 0) and
    not ACancellation.IsCancellationRequested do
  begin
    Sleep(100);
    Inc(Waited, 100);
  end;
end;

function TLspPullDiagnostics.DocumentReport(const AUri, APreviousResultId: string): TJSONObject;
begin
  Result := DocumentReport(AUri, APreviousResultId, nil);
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
    ResultId := ''
  else if FStore.TryGet(AUri, Document) then
    ResultId := Format('%d:v%d', [FGeneration, Document.Version])
  else if Assigned(FStamp) and FStamp(FileName, Stamp) and FReadText(FileName, Text) then
  begin
    ResultId := Format('%d:t%d', [FGeneration, Stamp]);
    Document := TTextDocument.Create(AUri, 'objectpascal', 0, Text);
  end
  else
    ResultId := '';
  Result := TJSONObject.Create;
  if (ResultId <> '') and (ResultId = APreviousResultId) then
  begin
    Result.AddPair('kind', 'unchanged');
    Result.AddPair('resultId', ResultId);
    Exit;
  end;
  Result.AddPair('kind', 'full');
  if ResultId <> '' then
    Result.AddPair('resultId', ResultId);
  if Document = nil then
    Result.AddPair('items', TJSONArray.Create)
  else
  begin
    try
      Result.AddPair('items', CachedDiagnose(AUri, ResultId, Document, ACancellation));
    except
      Result.Free;
      raise;
    end;
  end;
end;

function TLspPullDiagnostics.HandleDocument(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Uri, Previous: string;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Feld "textDocument.uri" fehlt in ' + DocumentMethod);
  if not TJSONObject(AParams).TryGetValue<string>('previousResultId', Previous) then
    Previous := '';
  ACancellation.ThrowIfCancellationRequested;
  Result := DocumentReport(Uri, Previous, ACancellation);
end;

function TLspPullDiagnostics.CollectWorkspace(const APrevious: TDictionary<string, string>;
  const ACancellation: IJsonRpcCancellationToken; out AComplete: Boolean): TJSONArray;
var
  FileName, Uri, Text, ResultId, Known: string;
  Stamp: Int64;
  Document, Disk: ITextDocument;
  Report: TJSONObject;
  Items: TJSONArray;
  Clock: TStopwatch;
begin
  Result := TJSONArray.Create;
  AComplete := True;
  if not Assigned(FFiles) then
    Exit;
  Clock := TStopwatch.StartNew;
  try
    for FileName in FFiles() do
    begin
      ACancellation.ThrowIfCancellationRequested;
      Uri := TDocumentUris.FromPath(FileName);
      // Geöffnete Dateien laufen über textDocument/diagnostic.
      if FStore.TryGet(Uri, Document) then
        Continue;
      if not FStamp(FileName, Stamp) then
        Continue;
      ResultId := Format('%d:t%d', [FGeneration, Stamp]);
      if APrevious.TryGetValue(Uri, Known) and (Known = ResultId) then
        Continue;
      if Clock.ElapsedMilliseconds > FBudgetMs then
      begin
        AComplete := False;
        Break;
      end;
      if not FReadText(FileName, Text) then
        Continue;
      // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
      Disk := TTextDocument.Create(Uri, 'objectpascal', 0, Text);
      // Erst prüfen, dann den Bericht anlegen: Ein Abbruch hinterlässt so kein Objekt.
      Items := CachedDiagnose(Uri, ResultId, Disk, ACancellation);
      Report := TJSONObject.Create;
      Report.AddPair('uri', Uri);
      Report.AddPair('version', TJSONNull.Create);
      Report.AddPair('kind', 'full');
      Report.AddPair('resultId', ResultId);
      Report.AddPair('items', Items);
      Result.AddElement(Report);
      APrevious.AddOrSetValue(Uri, ResultId);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TLspPullDiagnostics.WorkspaceReport(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Previous: TDictionary<string, string>;
  PreviousIds: TJSONArray;
  Entry: TJSONValue;
  Uri, Value: string;
  Items: TJSONArray;
  Complete: Boolean;
  Pending: Boolean;
  Waited: Cardinal;
  Generation: Integer;
begin
  // Nur eine Anfrage prüft; eine zweite wartet bloß auf eine Änderung und antwortet leer.
  if TInterlocked.CompareExchange(FWorkspaceActive, 1, 0) <> 0 then
  begin
    WaitForChange(ACancellation);
    TRequestDiagnostics.Reason(ReasonWorkspaceBusy);
    Result := TJSONObject.Create;
    TJSONObject(Result).AddPair('items', TJSONArray.Create);
    Exit;
  end;
  Previous := TDictionary<string, string>.Create;
  try
    if (AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<TJSONArray>('previousResultIds', PreviousIds) then
      for Entry in PreviousIds do
        if Entry.TryGetValue<string>('uri', Uri) and Entry.TryGetValue<string>('value', Value) then
          Previous.AddOrSetValue(Uri, Value);
    Generation := FGeneration;
    // Während des Indexaufbaus nichts prüfen, sondern warten, bis er fertig ist.
    Pending := IsBusy;
    Complete := True;
    if Pending then
      Items := TJSONArray.Create
    else
      Items := CollectWorkspace(Previous, ACancellation, Complete);
    // Nichts Neues: auf eine Änderung warten, statt sofort leer zu antworten.
    Waited := 0;
    while (Items.Count = 0) and Complete and (Waited < FWaitMs) and not ACancellation.IsCancellationRequested do
    begin
      FChanged.WaitFor(100);
      if (FGeneration <> Generation) or (Pending and not IsBusy) then
      begin
        Generation := FGeneration;
        Pending := IsBusy;
        if not Pending then
        begin
          Items.Free;
          Items := CollectWorkspace(Previous, ACancellation, Complete);
        end;
      end;
      Inc(Waited, 100);
    end;
    if Items.Count = 0 then
    begin
      if Pending then
        TRequestDiagnostics.Reason(ReasonIndexLoading)
      else
        TRequestDiagnostics.DefaultReason(ReasonNoChanges);
    end;
    Result := TJSONObject.Create;
    TJSONObject(Result).AddPair('items', Items);
  finally
    Previous.Free;
    TInterlocked.Exchange(FWorkspaceActive, 0);
  end;
end;

end.
