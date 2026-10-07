unit BDLsp.Common.JsonRpc.Connection;

// Nachrichtenschleife einer Verbindung.
//
//   Lese-Thread      liest Nachrichten vom Transport, führt $/cancelRequest sofort
//                    aus und stellt alle übrigen Nachrichten in den Posteingang.
//   Run (Aufrufer)   verarbeitet den Posteingang der Reihe nach: Benachrichtigungen
//                    und normale Anfragen laufen hier, damit z. B. didChange in
//                    der gesendeten Reihenfolge ankommt.
//   Worker           nebenläufige Anfragen laufen im Thread-Pool und antworten
//                    selbst; der Transport schreibt threadsicher.

interface

uses
  System.SysUtils,
  System.JSON,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.JsonRpc.Dispatcher;

type
  /// <summary>Meldet Fehler, die die Schleife abgefangen hat (z. B. für das Logging).</summary>
  TJsonRpcErrorEvent = reference to procedure(const AError: Exception);

  TJsonRpcConnection = class
  public const
    /// <summary>So lange wartet Run beim Beenden auf laufende nebenläufige Anfragen.</summary>
    DefaultWorkTimeout = 5000;
    /// <summary>So lange wartet Run beim Beenden auf den Lese-Thread.</summary>
    DefaultReaderTimeout = 2000;
  private
    FTransport: IJsonRpcTransport;
    FDispatcher: TJsonRpcDispatcher;
    FStopped: Boolean;
    FOnError: TJsonRpcErrorEvent;
    /// <summary>Posteingang des laufenden Run (IJsonRpcInbox), sonst nil.</summary>
    FInbox: IInterface;
    FWorkTimeout: Cardinal;
    procedure ReportError(const AError: Exception);
    procedure ReportProblem(const AText: string);
    procedure Send(AMessage: TJSONObject);
    procedure Process(const AMessage: TJSONObject);
    function CreateResponder: TJsonRpcResponder;
  public
    /// <summary>Der Dispatcher bleibt im Besitz des Aufrufers.</summary>
    constructor Create(const ATransport: IJsonRpcTransport; ADispatcher: TJsonRpcDispatcher);
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
    property Stopped: Boolean read FStopped;
    /// <summary>Wird aus der Schleife und aus Worker-Threads aufgerufen.</summary>
    property OnError: TJsonRpcErrorEvent read FOnError write FOnError;
    property WorkTimeout: Cardinal read FWorkTimeout write FWorkTimeout;
  end;

implementation

uses
  System.Classes,
  System.SyncObjs,
  System.Threading,
  System.Generics.Collections,
  BDLsp.Common.JsonRpc.Messages,
  BDLsp.Common.JsonRpc.PendingRequests;

const
  WaitForever = Cardinal($FFFFFFFF);

type
  TJsonRpcInboxKind = (ikMessage, ikInvalid, ikClosed, ikFailed, ikWakeUp);

  TJsonRpcInboxItem = record
    Kind: TJsonRpcInboxKind;
    /// <summary>ikMessage: gelesene Nachricht.</summary>
    Message: TJSONObject;
    /// <summary>ikInvalid: Code und Text der unlesbaren Nachricht.</summary>
    Code: Integer;
    Text: string;
    /// <summary>ikFailed: Fehler des Transports, wird in Run erneut ausgelöst.</summary>
    Error: Exception;
    procedure Release;
  end;

  /// <summary>Posteingang zwischen Lese-Thread und Nachrichtenschleife.</summary>
  IJsonRpcInbox = interface
    ['{C1F5A8E2-4B7D-4D39-A6E0-8F3B2C9D5E14}']
    /// <summary>Stellt ein Element ein; nach Close wird es verworfen.</summary>
    procedure Put(const AItem: TJsonRpcInboxItem);
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
    FClosed: Boolean;
    FReaderDone: TLightweightEvent;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Put(const AItem: TJsonRpcInboxItem);
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

procedure TJsonRpcInboxItem.Release;
begin
  FreeAndNil(Message);
  FreeAndNil(Error);
end;

{ TJsonRpcInbox }

constructor TJsonRpcInbox.Create;
begin
  inherited Create;
  FQueue := TQueue<TJsonRpcInboxItem>.Create;
  FReaderDone := TLightweightEvent.Create(False);
end;

destructor TJsonRpcInbox.Destroy;
begin
  Close;
  FReaderDone.Free;
  FQueue.Free;
  inherited;
end;

procedure TJsonRpcInbox.Put(const AItem: TJsonRpcInboxItem);
var
  Item: TJsonRpcInboxItem;
begin
  Item := AItem;
  TMonitor.Enter(FQueue);
  try
    if not FClosed then
    begin
      FQueue.Enqueue(Item);
      TMonitor.Pulse(FQueue);
      Exit;
    end;
  finally
    TMonitor.Exit(FQueue);
  end;
  Item.Release;
end;

function TJsonRpcInbox.Take: TJsonRpcInboxItem;
begin
  TMonitor.Enter(FQueue);
  try
    while (FQueue.Count = 0) and not FClosed do
      TMonitor.Wait(FQueue, WaitForever);
    if FQueue.Count > 0 then
      Result := FQueue.Dequeue
    else
      Result := InboxItem(ikClosed);
  finally
    TMonitor.Exit(FQueue);
  end;
end;

procedure TJsonRpcInbox.Close;
var
  Item: TJsonRpcInboxItem;
begin
  TMonitor.Enter(FQueue);
  try
    FClosed := True;
    while FQueue.Count > 0 do
    begin
      Item := FQueue.Dequeue;
      Item.Release;
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

// Startet den Lese-Thread. Er hält nur referenzgezählte Objekte, damit er auch
// dann sicher endet, wenn Run nicht auf ihn warten konnte (blockierendes stdin).
procedure StartReader(const ATransport: IJsonRpcTransport; const APending: IJsonRpcPendingRequests;
  const AInbox: IJsonRpcInbox);
var
  Transport: IJsonRpcTransport;
  Pending: IJsonRpcPendingRequests;
  Inbox: IJsonRpcInbox;
  Reader: TThread;
begin
  Transport := ATransport;
  Pending := APending;
  Inbox := AInbox;
  Reader := TThread.CreateAnonymousThread(
    procedure
    var
      Item: TJsonRpcInboxItem;
      Incoming: TJSONObject;
    begin
      try
        try
          while not Inbox.IsClosed do
          begin
            try
              Incoming := Transport.ReadMessage;
            except
              on EJsonRpcTransportClosed do
              begin
                Inbox.Put(InboxItem(ikClosed));
                Exit;
              end;
              on E: EJsonRpcError do
              begin
                // Einzelne unlesbare Nachricht: weiterlesen.
                Item := InboxItem(ikInvalid);
                Item.Code := E.Code;
                Item.Text := E.Message;
                Inbox.Put(Item);
                Continue;
              end;
            end;

            try
              if Pending.Observe(Incoming) then
              begin
                FreeAndNil(Incoming);
                Continue;
              end;
            except
              FreeAndNil(Incoming);
              raise;
            end;
            Item := InboxItem(ikMessage);
            Item.Message := Incoming;
            Inbox.Put(Item);
          end;
        except
          // Zerstörter Nachrichtenstrom: Run löst den Fehler erneut aus.
          on Exception do
          begin
            Item := InboxItem(ikFailed);
            Item.Error := Exception(AcquireExceptionObject);
            Inbox.Put(Item);
          end;
        end;
      finally
        Inbox.ReaderDone;
      end;
    end);
  Reader.FreeOnTerminate := True;
  Reader.Start;
end;

function ThreadPoolScheduler: TJsonRpcScheduler;
begin
  Result :=
    procedure(const AWork: TProc)
    begin
      TTask.Run(AWork);
    end;
end;

{ TJsonRpcConnection }

constructor TJsonRpcConnection.Create(const ATransport: IJsonRpcTransport; ADispatcher: TJsonRpcDispatcher);
begin
  inherited Create;
  FTransport := ATransport;
  FDispatcher := ADispatcher;
  FWorkTimeout := DefaultWorkTimeout;
end;

procedure TJsonRpcConnection.ReportError(const AError: Exception);
begin
  if Assigned(FOnError) then
    FOnError(AError);
end;

procedure TJsonRpcConnection.ReportProblem(const AText: string);
var
  Problem: Exception;
begin
  Problem := EJsonRpcTransportError.Create(AText);
  try
    ReportError(Problem);
  finally
    Problem.Free;
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
  Transport: IJsonRpcTransport;
  OnError: TJsonRpcErrorEvent;
begin
  // Ohne Self: ein Worker kann die Verbindung überleben, wenn er beim Beenden
  // nicht rechtzeitig fertig wird.
  Transport := FTransport;
  OnError := FOnError;
  Result :=
    procedure(const AResponse: TJSONObject)
    begin
      try
        try
          Transport.WriteMessage(AResponse);
        finally
          AResponse.Free;
        end;
      except
        on E: Exception do
          if Assigned(OnError) then
            try
              OnError(E);
            except
              // Ein Fehler beim Melden darf den Worker nicht beenden.
            end;
      end;
    end;
end;

procedure TJsonRpcConnection.Process(const AMessage: TJSONObject);
var
  Response: TJSONObject;
begin
  Response := nil;
  try
    Response := FDispatcher.DispatchMessage(AMessage);
  except
    // Fehler eines Benachrichtigungs-Handlers: melden und weiterarbeiten.
    on E: Exception do
    begin
      ReportError(E);
      Exit;
    end;
  end;
  if Response <> nil then
    Send(Response);
end;

procedure TJsonRpcConnection.Run;
var
  Inbox: IJsonRpcInbox;
  Item: TJsonRpcInboxItem;
  Failure: Exception;
  OwnScheduler: Boolean;
  OwnResponder: Boolean;
  Error: Exception;
begin
  FStopped := False;
  Inbox := TJsonRpcInbox.Create;
  FInbox := Inbox;

  OwnScheduler := not Assigned(FDispatcher.Scheduler);
  if OwnScheduler then
    FDispatcher.Scheduler := ThreadPoolScheduler;
  OwnResponder := not Assigned(FDispatcher.Responder);
  if OwnResponder then
    FDispatcher.Responder := CreateResponder;

  Failure := nil;
  try
    StartReader(FTransport, FDispatcher.PendingRequests, Inbox);
    while not FStopped do
    begin
      Item := Inbox.Take;
      case Item.Kind of
        ikMessage:
          try
            Process(Item.Message);
          finally
            Item.Release;
          end;
        ikInvalid:
          begin
            Error := EJsonRpcError.Create(Item.Code, Item.Text);
            try
              ReportError(Error);
            finally
              Error.Free;
            end;
            Send(TJsonRpcMessages.Error(nil, Item.Code, Item.Text));
          end;
        ikClosed:
          Break;
        ikFailed:
          begin
            Failure := Item.Error;
            Break;
          end;
        ikWakeUp:
          ; // Stop wurde aufgerufen
      end;
    end;
  finally
    FInbox := nil;
    Inbox.Close;
    FDispatcher.PendingRequests.CancelAll;
    if not FDispatcher.PendingRequests.WaitForWork(FWorkTimeout) then
      ReportProblem('Nebenläufige Anfragen wurden beim Beenden nicht rechtzeitig fertig');
    if OwnScheduler then
      FDispatcher.Scheduler := nil;
    if OwnResponder then
      FDispatcher.Responder := nil;
    Inbox.WaitForReader(DefaultReaderTimeout);
  end;

  if Failure <> nil then
    raise Failure;
end;

procedure TJsonRpcConnection.Stop;
var
  Inbox: IJsonRpcInbox;
begin
  FStopped := True;
  if Supports(FInbox, IJsonRpcInbox, Inbox) then
    Inbox.Put(InboxItem(ikWakeUp));
end;

end.
