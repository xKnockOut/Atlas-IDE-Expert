unit BDLsp.Common.JsonRpc.Connection;

// Nachrichtenschleife: liest Nachrichten vom Transport, lässt sie vom
// Dispatcher verarbeiten und schreibt die Antworten zurück.
// Die Verarbeitung läuft vorerst im aufrufenden Thread; Worker-Threads und
// $/cancelRequest folgen mit #4.

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
  private
    FTransport: IJsonRpcTransport;
    FDispatcher: TJsonRpcDispatcher;
    FStopped: Boolean;
    FOnError: TJsonRpcErrorEvent;
    procedure ReportError(const AError: Exception);
    procedure Send(AMessage: TJSONObject);
    procedure Process(const AMessage: TJSONObject);
  public
    /// <summary>Der Dispatcher bleibt im Besitz des Aufrufers.</summary>
    constructor Create(const ATransport: IJsonRpcTransport; ADispatcher: TJsonRpcDispatcher);
    /// <summary>
    /// Verarbeitet Nachrichten, bis Stop aufgerufen oder die Eingabe geschlossen wird.
    /// Ein zerstörter Nachrichtenstrom beendet die Schleife mit EJsonRpcTransportError.
    /// </summary>
    procedure Run;
    /// <summary>Beendet die Schleife nach der aktuellen Nachricht.</summary>
    procedure Stop;
    property Stopped: Boolean read FStopped;
    property OnError: TJsonRpcErrorEvent read FOnError write FOnError;
  end;

implementation

uses
  BDLsp.Common.JsonRpc.Messages;

{ TJsonRpcConnection }

constructor TJsonRpcConnection.Create(const ATransport: IJsonRpcTransport; ADispatcher: TJsonRpcDispatcher);
begin
  inherited Create;
  FTransport := ATransport;
  FDispatcher := ADispatcher;
end;

procedure TJsonRpcConnection.ReportError(const AError: Exception);
begin
  if Assigned(FOnError) then
    FOnError(AError);
end;

procedure TJsonRpcConnection.Send(AMessage: TJSONObject);
begin
  try
    FTransport.WriteMessage(AMessage);
  finally
    AMessage.Free;
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
  Incoming: TJSONObject;
begin
  FStopped := False;
  while not FStopped do
  begin
    Incoming := nil;
    try
      Incoming := FTransport.ReadMessage;
    except
      on EJsonRpcTransportClosed do
        Break;
      on E: EJsonRpcError do
      begin
        // Einzelne unlesbare Nachricht: Fehlerantwort ohne id, dann weiter.
        ReportError(E);
        Send(TJsonRpcMessages.Error(nil, E.Code, E.Message));
        Continue;
      end;
    end;

    try
      Process(Incoming);
    finally
      Incoming.Free;
    end;
  end;
end;

procedure TJsonRpcConnection.Stop;
begin
  FStopped := True;
end;

end.
