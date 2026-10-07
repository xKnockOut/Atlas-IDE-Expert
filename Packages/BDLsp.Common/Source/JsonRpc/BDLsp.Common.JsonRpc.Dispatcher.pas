unit BDLsp.Common.JsonRpc.Dispatcher;

// Verteilt eingehende JSON-RPC-Nachrichten anhand des Methodennamens auf
// registrierte Handler. Anfragen (mit id) erhalten immer eine Antwort,
// Benachrichtigungen (ohne id) nie.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  BDLsp.Common.JsonRpc.Contract;

type
  TJsonRpcDispatcher = class
  private
    FRequestHandlers: TDictionary<string, TJsonRpcRequestHandler>;
    FNotificationHandlers: TDictionary<string, TJsonRpcNotificationHandler>;
    FGuard: TJsonRpcGuard;
    function DispatchRequest(const AId: TJSONValue; const AMethod: string; const AParams: TJSONValue): TJSONObject;
    procedure DispatchNotification(const AMethod: string; const AParams: TJSONValue);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Registriert den Handler einer Anfrage; ein vorhandener wird ersetzt.</summary>
    procedure RegisterRequest(const AMethod: string; const AHandler: TJsonRpcRequestHandler);
    /// <summary>Registriert den Handler einer Benachrichtigung; ein vorhandener wird ersetzt.</summary>
    procedure RegisterNotification(const AMethod: string; const AHandler: TJsonRpcNotificationHandler);
    /// <summary>
    /// Verarbeitet eine Nachricht und liefert die Antwort, die der Aufrufer
    /// sendet und freigibt, oder nil, wenn keine Antwort fällig ist.
    /// Fehler in Anfrage-Handlern werden zur Fehlerantwort; Fehler in
    /// Benachrichtigungs-Handlern gehen an den Aufrufer.
    /// </summary>
    function DispatchMessage(const AMessage: TJSONObject): TJSONObject;
    /// <summary>Optionale Prüfung vor jeder Verteilung, z. B. für den Lebenszyklus des Servers.</summary>
    property Guard: TJsonRpcGuard read FGuard write FGuard;
  end;

implementation

uses
  BDLsp.Common.JsonRpc.Messages;

{ TJsonRpcDispatcher }

constructor TJsonRpcDispatcher.Create;
begin
  inherited Create;
  FRequestHandlers := TDictionary<string, TJsonRpcRequestHandler>.Create;
  FNotificationHandlers := TDictionary<string, TJsonRpcNotificationHandler>.Create;
end;

destructor TJsonRpcDispatcher.Destroy;
begin
  FNotificationHandlers.Free;
  FRequestHandlers.Free;
  inherited;
end;

procedure TJsonRpcDispatcher.RegisterRequest(const AMethod: string; const AHandler: TJsonRpcRequestHandler);
begin
  FRequestHandlers.AddOrSetValue(AMethod, AHandler);
end;

procedure TJsonRpcDispatcher.RegisterNotification(const AMethod: string; const AHandler: TJsonRpcNotificationHandler);
begin
  FNotificationHandlers.AddOrSetValue(AMethod, AHandler);
end;

function TJsonRpcDispatcher.DispatchMessage(const AMessage: TJSONObject): TJSONObject;
var
  Id: TJSONValue;
  MethodValue: TJSONValue;
  Params: TJSONValue;
begin
  Id := AMessage.GetValue('id');
  MethodValue := AMessage.GetValue('method');
  Params := AMessage.GetValue('params');

  if MethodValue = nil then
  begin
    // Antworten der Gegenseite auf eigene Anfragen werden noch nicht ausgewertet.
    if (AMessage.GetValue('result') <> nil) or (AMessage.GetValue('error') <> nil) then
      Exit(nil);
    Exit(TJsonRpcMessages.Error(Id, TJsonRpcErrorCode.InvalidRequest, 'Feld "method" fehlt'));
  end;

  if not (MethodValue is TJSONString) then
  begin
    if Id = nil then
      Exit(nil);
    Exit(TJsonRpcMessages.Error(Id, TJsonRpcErrorCode.InvalidRequest, 'Feld "method" ist keine Zeichenkette'));
  end;

  if Id = nil then
  begin
    DispatchNotification(MethodValue.Value, Params);
    Result := nil;
  end
  else
    Result := DispatchRequest(Id, MethodValue.Value, Params);
end;

function TJsonRpcDispatcher.DispatchRequest(const AId: TJSONValue; const AMethod: string;
  const AParams: TJSONValue): TJSONObject;
var
  Handler: TJsonRpcRequestHandler;
begin
  try
    if Assigned(FGuard) then
      FGuard(AMethod, True);
    if not FRequestHandlers.TryGetValue(AMethod, Handler) then
      raise EJsonRpcError.Create(TJsonRpcErrorCode.MethodNotFound, 'Methode nicht unterstützt: ' + AMethod);
    Result := TJsonRpcMessages.Response(AId, Handler(AParams));
  except
    on E: EJsonRpcError do
      Result := TJsonRpcMessages.Error(AId, E.Code, E.Message);
    on E: Exception do
      Result := TJsonRpcMessages.Error(AId, TJsonRpcErrorCode.InternalError, E.ClassName + ': ' + E.Message);
  end;
end;

procedure TJsonRpcDispatcher.DispatchNotification(const AMethod: string; const AParams: TJSONValue);
var
  Handler: TJsonRpcNotificationHandler;
begin
  // Benachrichtigungen erhalten keine Antwort, auch keine Fehlerantwort.
  // Unbekannte und vom Guard abgelehnte Benachrichtigungen werden verworfen.
  // Andere Exceptions eines Handlers gehen an den Aufrufer.
  if Assigned(FGuard) then
    try
      FGuard(AMethod, False);
    except
      on EJsonRpcError do
        Exit;
    end;
  if FNotificationHandlers.TryGetValue(AMethod, Handler) then
    Handler(AParams);
end;

end.
