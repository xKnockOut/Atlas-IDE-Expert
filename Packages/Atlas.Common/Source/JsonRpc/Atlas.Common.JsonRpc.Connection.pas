unit Atlas.Common.JsonRpc.Connection;

// Nachrichtenschleife einer Verbindung.
//
//   Lese-Thread      liest Nachrichten vom Transport, führt $/cancelRequest sofort
//                    aus und stellt alle übrigen Nachrichten in den Posteingang.
//   Run (Aufrufer)   verarbeitet den Posteingang der Reihe nach: Benachrichtigungen
//                    und normale Anfragen laufen hier, damit z. B. didChange in
//                    der gesendeten Reihenfolge ankommt.
//   Worker           nebenläufige Anfragen laufen im Thread-Pool und antworten
//                    selbst; der Transport schreibt threadsicher.
//
// Zustand, der nur im Thread von Run geändert werden darf (z. B. Neuladen eines
// Arbeitsbereichs), stellen andere Threads über Queue in die Schleife
//.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher;

type
  /// <summary>Meldet Fehler, die die Schleife abgefangen hat (z. B. für das Logging).</summary>
  TJsonRpcErrorEvent = reference to procedure(const AError: Exception);

  TJsonRpcConnection = class
  public const
    /// <summary>So lange wartet Run beim Beenden auf laufende nebenläufige Anfragen.</summary>
    cDefaultWorkTimeout = 5000;
    /// <summary>So lange wartet Run beim Beenden auf den Lese-Thread.</summary>
    cDefaultReaderTimeout = 2000;
  private
    FTransport: IJsonRpcTransport;
    FDispatcher: TJsonRpcDispatcher;
    FStopped: Boolean;
    FOnError: TJsonRpcErrorEvent;
    /// <summary>Posteingang des laufenden Run (IJsonRpcInbox), sonst nil. Nur unter FInboxLock:
    /// Post, Queue und Stop kommen aus fremden Threads (Interface-Zuweisung ist nicht atomar).</summary>
    FInbox: IInterface;
    FInboxLock: TObject;
    FWorkTimeout: Cardinal;
    FOnLoopEnded: TProc;
    FUnfinishedWork: Boolean;
    function LockedInbox: IInterface;
    procedure SetInbox(const AInbox: IInterface);
    procedure RunWork(const AWork: TProc);
    procedure ReportError(const AError: Exception);
    procedure ReportProblem(const AText: string);
    procedure Send(AMessage: TJSONObject);
    procedure Process(const AMessage: TJSONObject; AQueueMs: Int64);
    function CreateResponder: TJsonRpcResponder;
  public
    /// <summary>Der Dispatcher bleibt im Besitz des Aufrufers.</summary>
    constructor Create(const ATransport: IJsonRpcTransport; ADispatcher: TJsonRpcDispatcher);
    destructor Destroy; override;
    /// <summary>
    /// Verarbeitet Nachrichten, bis Stop aufgerufen oder die Eingabe geschlossen wird.
    /// Ein zerstörter Nachrichtenstrom beendet die Schleife mit EJsonRpcTransportError.
    /// Beim Beenden werden offene Anfragen abgebrochen und laufende abgewartet.
    /// Hat der Dispatcher keinen Scheduler, setzt Run für die Dauer der Schleife
    /// einen Thread-Pool ein.
    /// </summary>
    procedure Run;
    /// <summary>Beendet die Schleife nach der aktuellen Nachricht. Threadsicher.</summary>
    procedure Stop;
    /// <summary>Stellt eine eigene Nachricht in die Schleife, z. B. eine Dateiänderung aus einem Beobachter-Thread
    /// (#227): Sie läuft im Thread der Schleife vor den noch nicht verarbeiteten Nachrichten des Clients.
    /// Übernimmt AMessage; ohne laufende Schleife False und AMessage wird freigegeben. Threadsicher.</summary>
    function Post(AMessage: TJSONObject): Boolean;
    /// <summary>Stellt AWork in die Schleife: Es läuft im Thread von Run, vor den noch nicht verarbeiteten
    /// Nachrichten des Clients und nach früheren Post/Queue. Für Zustand, der nur dort geändert werden darf
    /// (Indexaufbau). Ohne laufende Schleife False; AWork läuft dann nicht. Threadsicher.
    /// Ausnahmen von AWork gehen an OnError.</summary>
    function Queue(const AWork: TProc): Boolean;
    /// <summary>Wird aus der Schleife und aus Worker-Threads aufgerufen.</summary>
    property OnError: TJsonRpcErrorEvent read FOnError write FOnError;
    property WorkTimeout: Cardinal read FWorkTimeout write FWorkTimeout;
    /// <summary>True, wenn Run beim Ende nach WorkTimeout noch laufende nebenläufige Anfragen hatte
    ///. Deren Handler können noch auf Objekte des Aufrufers zugreifen; er darf sie dann
    /// nicht freigeben.</summary>
    property UnfinishedWork: Boolean read FUnfinishedWork;
    /// <summary>Die Schleife ist regulär zu Ende (Eingabe geschlossen oder Stop), bevor auf laufende
    /// Anfragen gewartet wird. Für Abschlussmeldungen, die ein ungeduldiger Client sonst abschneidet.</summary>
    property OnLoopEnded: TProc read FOnLoopEnded write FOnLoopEnded;
  end;

implementation

uses
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Messages,
  Atlas.Common.JsonRpc.PendingRequests,
  Atlas.Common.JsonRpc.WorkerPool,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TConnectionText = (ConcurrentRequestsDidNotFinish);

const
  cTexts: array[TConnectionText] of TAtlasText = (
    (De: 'Nebenläufige Anfragen wurden beim Beenden nicht rechtzeitig fertig';
     En: 'Concurrent requests did not finish in time at shutdown'));

{$SCOPEDENUMS OFF}

const
  cWaitForever = Cardinal($FFFFFFFF);
  /// <summary>Warten auf die Arbeitsthreads nach WaitForWork; dann laufen sie höchstens noch aus.</summary>
  cPoolCloseMs = 2000;

type
  TJsonRpcInboxKind = (ikMessage, ikInvalid, ikClosed, ikFailed, ikWakeUp, ikWork);

  TJsonRpcInboxItem = record
    Kind: TJsonRpcInboxKind;
    /// <summary>ikMessage: gelesene Nachricht.</summary>
    Message: TJSONObject;
    /// <summary>ikInvalid: Code und Text der unlesbaren Nachricht.</summary>
    Code: Integer;
    Text: string;
    /// <summary>ikFailed: Fehler des Transports, wird in Run erneut ausgelöst.</summary>
    Error: Exception;
    /// <summary>ikWork: Arbeit für den Thread der Schleife (Queue).</summary>
    Work: TProc;
    /// <summary>Eingang in ms (TThread.GetTickCount64) für die Wartezeit (#874); 0 = unbekannt.</summary>
    Received: UInt64;
    procedure Release;
    /// <summary>Millisekunden seit dem Eingang; 0 ohne Zeitstempel.</summary>
    function WaitedMs: Int64;
  end;

  /// <summary>Posteingang zwischen Lese-Thread und Nachrichtenschleife.</summary>
  IJsonRpcInbox = interface
    ['{C1F5A8E2-4B7D-4D39-A6E0-8F3B2C9D5E14}']
    /// <summary>Stellt ein Element ein; nach Close wird es verworfen.</summary>
    procedure Put(const AItem: TJsonRpcInboxItem);
    /// <summary>Wie Put, aber vor allen Elementen aus Put; untereinander in Reihenfolge. False nach Close.</summary>
    function PutFirst(const AItem: TJsonRpcInboxItem): Boolean;
    /// <summary>Wartet auf das nächste Element.</summary>
    function Take: TJsonRpcInboxItem;
    /// <summary>Verwirft wartende und künftige Elemente.</summary>
    procedure Close;
    function IsClosed: Boolean;
    procedure ReaderDone;
    function WaitForReader(ATimeout: Cardinal): Boolean;
  end;

  TJsonRpcInbox = class(TInterfacedObject, IJsonRpcInbox)
  private
    FQueue: TQueue<TJsonRpcInboxItem>;
    // Eigene Nachrichten (Post); unter dem Monitor von FQueue.
    FFirst: TQueue<TJsonRpcInboxItem>;
    FClosed: Boolean;
    FReaderDone: TLightweightEvent;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Put(const AItem: TJsonRpcInboxItem);
    function PutFirst(const AItem: TJsonRpcInboxItem): Boolean;
    function Take: TJsonRpcInboxItem;
    procedure Close;
    function IsClosed: Boolean;
    procedure ReaderDone;
    function WaitForReader(ATimeout: Cardinal): Boolean;
  end;

function InboxItem(AKind: TJsonRpcInboxKind): TJsonRpcInboxItem;
begin
  Result := Default(TJsonRpcInboxItem);
  Result.Kind := AKind;
end;

{ TJsonRpcInboxItem }

function TJsonRpcInboxItem.WaitedMs: Int64;
begin
  Result := 0;
  if Received <> 0 then
  begin
    Result := Int64(TThread.GetTickCount64 - Received);
  end;
end;

procedure TJsonRpcInboxItem.Release;
begin
  FreeAndNil(Message);
  FreeAndNil(Error);
  Work := nil;
end;

{ TJsonRpcInbox }

constructor TJsonRpcInbox.Create;
begin
  inherited Create;
  FQueue := TQueue<TJsonRpcInboxItem>.Create;
  FFirst := TQueue<TJsonRpcInboxItem>.Create;
  FReaderDone := TLightweightEvent.Create(False);
end;

destructor TJsonRpcInbox.Destroy;
begin
  Close;
  FReaderDone.Free;
  FFirst.Free;
  FQueue.Free;
  inherited;
end;

procedure TJsonRpcInbox.Put(const AItem: TJsonRpcInboxItem);
var
  mItem: TJsonRpcInboxItem;
begin
  mItem := AItem;
  TMonitor.Enter(FQueue);
  try
    if not FClosed then
    begin
      FQueue.Enqueue(mItem);
      TMonitor.Pulse(FQueue);
      Exit;
    end;
  finally
    TMonitor.Exit(FQueue);
  end;
  mItem.Release;
end;

function TJsonRpcInbox.PutFirst(const AItem: TJsonRpcInboxItem): Boolean;
var
  mItem: TJsonRpcInboxItem;
begin
  mItem := AItem;
  TMonitor.Enter(FQueue);
  try
    Result := not FClosed;
    if Result then
    begin
      FFirst.Enqueue(mItem);
      TMonitor.Pulse(FQueue);
      Exit;
    end;
  finally
    TMonitor.Exit(FQueue);
  end;
  mItem.Release;
end;

function TJsonRpcInbox.Take: TJsonRpcInboxItem;
begin
  TMonitor.Enter(FQueue);
  try
    while (FQueue.Count = 0) and (FFirst.Count = 0) and not FClosed do
    begin
      TMonitor.Wait(FQueue, cWaitForever);
    end;
    if FFirst.Count > 0 then
    begin
      Result := FFirst.Dequeue;
    end
    else if FQueue.Count > 0 then
    begin
      Result := FQueue.Dequeue;
    end
    else
    begin
      Result := InboxItem(ikClosed);
    end;
  finally
    TMonitor.Exit(FQueue);
  end;
end;

procedure TJsonRpcInbox.Close;
var
  mItem: TJsonRpcInboxItem;
begin
  TMonitor.Enter(FQueue);
  try
    FClosed := True;
    while FFirst.Count > 0 do
    begin
      mItem := FFirst.Dequeue;
      mItem.Release;
    end;
    while FQueue.Count > 0 do
    begin
      mItem := FQueue.Dequeue;
      mItem.Release;
    end;
    TMonitor.PulseAll(FQueue);
  finally
    TMonitor.Exit(FQueue);
  end;
end;

function TJsonRpcInbox.IsClosed: Boolean;
begin
  TMonitor.Enter(FQueue);
  try
    Result := FClosed;
  finally
    TMonitor.Exit(FQueue);
  end;
end;

procedure TJsonRpcInbox.ReaderDone;
begin
  FReaderDone.SetEvent;
end;

function TJsonRpcInbox.WaitForReader(ATimeout: Cardinal): Boolean;
begin
  Result := FReaderDone.WaitFor(ATimeout) = TWaitResult.wrSignaled;
end;

// Liest eine Nachricht in die Inbox; False, wenn die Eingabe geschlossen ist.
function ReadIncoming(const ATransport: IJsonRpcTransport; const APending: IJsonRpcPendingRequests;
  const AInbox: IJsonRpcInbox): Boolean;
var
  mItem: TJsonRpcInboxItem;
  mIncoming: TJSONObject;
begin
  Result := True;
  try
    mIncoming := ATransport.ReadMessage;
  except
    on EJsonRpcTransportClosed do
    begin
      AInbox.Put(InboxItem(ikClosed));
      Exit(False);
    end;
    on E: EJsonRpcError do
    begin
      // Einzelne unlesbare Nachricht: weiterlesen.
      mItem := InboxItem(ikInvalid);
      mItem.Code := E.Code;
      mItem.Text := E.Message;
      AInbox.Put(mItem);
      Exit;
    end;
  end;
  try
    if APending.Observe(mIncoming) then
    begin
      FreeAndNil(mIncoming);
      Exit;
    end;
  except
    FreeAndNil(mIncoming);
    raise;
  end;
  mItem := InboxItem(ikMessage);
  mItem.Message := mIncoming;
  mItem.Received := TThread.GetTickCount64;
  AInbox.Put(mItem);
end;

// Startet den Lese-Thread. Er hält nur referenzgezählte Objekte, damit er auch
// dann sicher endet, wenn Run nicht auf ihn warten konnte (blockierendes stdin).
// Er gibt sich nicht selbst frei: Run wartet auf ihn (ReleaseReader).
function StartReader(const ATransport: IJsonRpcTransport; const APending: IJsonRpcPendingRequests;
  const AInbox: IJsonRpcInbox): TThread;
var
  mTransport: IJsonRpcTransport;
  mPending: IJsonRpcPendingRequests;
  mInbox: IJsonRpcInbox;
begin
  mTransport := ATransport;
  mPending := APending;
  mInbox := AInbox;
  Result := TThread.CreateAnonymousThread(
    procedure
    var
      mItem: TJsonRpcInboxItem;
    begin
      try
        try
          while not mInbox.IsClosed and ReadIncoming(mTransport, mPending, mInbox) do
          begin
            // weiterlesen
          end;
        except
          // Zerstörter Nachrichtenstrom: Run löst den Fehler erneut aus.
          // lsp-ignore: catch-all-without-raise -- Fehlergrenze des Workers; Fehler wird gemeldet
          on Exception do
          begin
            mItem := InboxItem(ikFailed);
            mItem.Error := Exception(AcquireExceptionObject);
            mInbox.Put(mItem);
          end;
        end;
      finally
        mInbox.ReaderDone;
      end;
    end);
  Result.FreeOnTerminate := False;
  Result.Start;
end;

// Wartet auf den Lese-Thread und gibt ihn frei. Bisher gab er sich
// selbst frei, kurz nach ReaderDone und damit nach dem Ende von Run; was er
// bis dahin hielt, überlebte Run. Hängt er nach ATimeout noch im Lesen
// (blockierendes stdin), gibt er sich bei seiner Rückkehr selbst frei. Liest
// er FreeOnTerminate vor dem Setzen, bleibt höchstens ein Leck (wie
// TAtlasThreadList.StopAll im Plugin).
procedure ReleaseReader(AReader: TThread; const AInbox: IJsonRpcInbox; ATimeout: Cardinal);
begin
  if AReader = nil then
  begin
    Exit;
  end;
  if AInbox.WaitForReader(ATimeout) then
  begin
    // ReaderDone kommt im finally des Threads: Danach endet er sofort.
    AReader.WaitFor;
    AReader.Free;
  end
  else
  begin
    AReader.FreeOnTerminate := True;
  end;
end;

// Eigene Arbeitsthreads statt TTask.Run (Begründung in Atlas.Common.JsonRpc.WorkerPool): Wartende Anfragen
// belegten dort die Plätze des Standard-Threadpools, und kurze Anfragen standen dahinter an.
function PoolScheduler(const APool: IJsonRpcWorkerPool): TJsonRpcScheduler;
var
  mPool: IJsonRpcWorkerPool;
begin
  mPool := APool;
  Result :=
    procedure(const AWork: TProc)
    begin
      if not mPool.Run(AWork) then
      begin
        // Pool schon geschlossen (Ende der Schleife): wie ohne Scheduler im aufrufenden Thread.
        AWork();
      end;
    end;
end;

{ TJsonRpcConnection }

constructor TJsonRpcConnection.Create(const ATransport: IJsonRpcTransport; ADispatcher: TJsonRpcDispatcher);
begin
  inherited Create;
  FTransport := ATransport;
  FDispatcher := ADispatcher;
  FWorkTimeout := cDefaultWorkTimeout;
  FInboxLock := TObject.Create;
end;

destructor TJsonRpcConnection.Destroy;
begin
  FInboxLock.Free;
  inherited;
end;

function TJsonRpcConnection.LockedInbox: IInterface;
begin
  TMonitor.Enter(FInboxLock);
  try
    Result := FInbox;
  finally
    TMonitor.Exit(FInboxLock);
  end;
end;

procedure TJsonRpcConnection.SetInbox(const AInbox: IInterface);
begin
  TMonitor.Enter(FInboxLock);
  try
    FInbox := AInbox;
  finally
    TMonitor.Exit(FInboxLock);
  end;
end;

procedure TJsonRpcConnection.RunWork(const AWork: TProc);
begin
  try
    AWork();
  except
    // Wie bei Benachrichtigungen: melden und weiterarbeiten.
    // lsp-ignore: catch-all-without-raise -- Fehlergrenze des Workers; Fehler wird gemeldet
    on E: Exception do
      ReportError(E);
  end;
end;

procedure TJsonRpcConnection.ReportError(const AError: Exception);
begin
  if Assigned(FOnError) then
  begin
    FOnError(AError);
  end;
end;

procedure TJsonRpcConnection.ReportProblem(const AText: string);
var
  mProblem: Exception;
begin
  mProblem := EJsonRpcTransportError.Create(AText);
  try
    ReportError(mProblem);
  finally
    mProblem.Free;
  end;
end;

procedure TJsonRpcConnection.Send(AMessage: TJSONObject);
begin
  try
    FTransport.WriteMessage(AMessage);
  finally
    AMessage.Free;
  end;
end;

function TJsonRpcConnection.CreateResponder: TJsonRpcResponder;
var
  mTransport: IJsonRpcTransport;
  mOnError: TJsonRpcErrorEvent;
begin
  // Ohne Self: ein Worker kann die Verbindung überleben, wenn er beim Beenden
  // nicht rechtzeitig fertig wird.
  mTransport := FTransport;
  mOnError := FOnError;
  Result :=
    procedure(const AResponse: TJSONObject)
    begin
      try
        try
          mTransport.WriteMessage(AResponse);
        finally
          AResponse.Free;
        end;
      except
        // lsp-ignore: catch-all-without-raise -- Fehlergrenze des Workers; Fehler wird gemeldet
        on E: Exception do
          if Assigned(mOnError) then
            try
              mOnError(E);
            except
              // Ein Fehler beim Melden darf den Worker nicht beenden.
            end;
      end;
    end;
end;

procedure TJsonRpcConnection.Process(const AMessage: TJSONObject; AQueueMs: Int64);
var
  mResponse: TJSONObject;
begin
  try
    // Wartezeit im Posteingang mitgeben: Sie steht sonst nicht im Diagnoselog (#874).
    mResponse := FDispatcher.DispatchMessage(AMessage, AQueueMs);
  except
    // Fehler eines Benachrichtigungs-Handlers: melden und weiterarbeiten.
    // lsp-ignore: catch-all-without-raise -- Fehlergrenze des Workers; Fehler wird gemeldet
    on E: Exception do
    begin
      ReportError(E);
      Exit;
    end;
  end;
  if mResponse <> nil then
  begin
    Send(mResponse);
  end;
end;

procedure TJsonRpcConnection.Run;
var
  mInbox: IJsonRpcInbox;
  mFailure: Exception;
  mOwnScheduler, mOwnResponder: Boolean;
  mPool: IJsonRpcWorkerPool;
  mReader: TThread;

  // Meldet eine unlesbare Nachricht und antwortet mit dem Fehler.
  procedure ReportInvalid(const AItem: TJsonRpcInboxItem);
  var
    mError: Exception;
  begin
    mError := EJsonRpcError.Create(AItem.Code, AItem.Text);
    try
      ReportError(mError);
    finally
      mError.Free;
    end;
    Send(TJsonRpcMessages.Error(nil, AItem.Code, AItem.Text));
  end;

  // Verarbeitet einen Eintrag der Inbox; False, wenn die Schleife endet (mFailure bei Fehler).
  function HandleItem(const AItem: TJsonRpcInboxItem): Boolean;
  begin
    Result := True;
    case AItem.Kind of
      ikMessage:
        try
          Process(AItem.Message, AItem.WaitedMs);
        finally
          AItem.Release;
        end;
      ikInvalid:
        ReportInvalid(AItem);
      ikClosed:
        Result := False;
      ikFailed:
        begin
          mFailure := AItem.Error;
          Result := False;
        end;
      ikWakeUp:
        ; // Stop wurde aufgerufen
      ikWork:
        try
          RunWork(AItem.Work);
        finally
          AItem.Release;
        end;
    end;
  end;

  // Schließt die Inbox, bricht offene Anfragen ab und nimmt eigene Scheduler und Responder zurück.
  procedure FinishRun;
  begin
    SetInbox(nil);
    mInbox.Close;
    FDispatcher.PendingRequests.CancelAll;
    if not FDispatcher.PendingRequests.WaitForWork(FWorkTimeout) then
    begin
      FUnfinishedWork := True;
      ReportProblem(cTexts[TConnectionText.ConcurrentRequestsDidNotFinish].Text);
    end;
    if mOwnScheduler then
    begin
      FDispatcher.Scheduler := nil;
      // Alle Antworten sind geschrieben oder aufgegeben; die Threads enden jetzt ohne Arbeit.
      if not mPool.Close(cPoolCloseMs) then
      begin
        FUnfinishedWork := True;
      end;
    end;
    if mOwnResponder then
    begin
      FDispatcher.Responder := nil;
    end;
  end;

begin
  FStopped := False;
  FUnfinishedWork := False;
  mInbox := TJsonRpcInbox.Create;
  SetInbox(mInbox);

  mOwnScheduler := not Assigned(FDispatcher.Scheduler);
  if mOwnScheduler then
  begin
    mPool := TJsonRpcWorkerPool.Create;
    FDispatcher.Scheduler := PoolScheduler(mPool);
  end;
  mOwnResponder := not Assigned(FDispatcher.Responder);
  if mOwnResponder then
  begin
    FDispatcher.Responder := CreateResponder();
  end;

  mFailure := nil;
  mReader := nil;
  try
    mReader := StartReader(FTransport, FDispatcher.PendingRequests, mInbox);
    while not FStopped and HandleItem(mInbox.Take) do
    begin
      // nächste Nachricht
    end;
    if (mFailure = nil) and Assigned(FOnLoopEnded) then
    begin
      FOnLoopEnded();
    end;
  finally
    FinishRun;
    ReleaseReader(mReader, mInbox, cDefaultReaderTimeout);
  end;

  if mFailure <> nil then
  begin
    raise mFailure;
  end;
end;

function TJsonRpcConnection.Post(AMessage: TJSONObject): Boolean;
var
  mInbox: IJsonRpcInbox;
  mItem: TJsonRpcInboxItem;
begin
  mItem := InboxItem(ikMessage);
  mItem.Message := AMessage;
  if Supports(LockedInbox, IJsonRpcInbox, mInbox) then
  begin
    Result := mInbox.PutFirst(mItem);
  end
  else
  begin
    mItem.Release;
    Result := False;
  end;
end;

function TJsonRpcConnection.Queue(const AWork: TProc): Boolean;
var
  mInbox: IJsonRpcInbox;
  mItem: TJsonRpcInboxItem;
begin
  mItem := InboxItem(ikWork);
  mItem.Work := AWork;
  if Supports(LockedInbox, IJsonRpcInbox, mInbox) then
  begin
    Result := mInbox.PutFirst(mItem);
  end
  else
  begin
    mItem.Release;
    Result := False;
  end;
end;

procedure TJsonRpcConnection.Stop;
var
  mInbox: IJsonRpcInbox;
begin
  FStopped := True;
  if Supports(LockedInbox, IJsonRpcInbox, mInbox) then
  begin
    mInbox.Put(InboxItem(ikWakeUp));
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.JsonRpc.Connection', cTexts);

end.
