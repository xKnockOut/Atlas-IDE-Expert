unit Atlas.Common.JsonRpc.Messages;

// Aufbau von JSON-RPC-2.0-Nachrichten (Antwort, Fehlerantwort, Benachrichtigung).

interface

uses
  System.JSON;

type
  TJsonRpcMessages = record
  public const
    Version = '2.0';
  public
    /// <summary>
    /// Erfolgsantwort. AId wird kopiert, AResult geht in die Antwort über
    /// (nil wird als null gesendet).
    /// </summary>
    class function Response(const AId: TJSONValue; AResult: TJSONValue): TJSONObject; static;
    /// <summary>Fehlerantwort. AId wird kopiert; nil wird als null gesendet.</summary>
    class function Error(const AId: TJSONValue; ACode: Integer; const AMessage: string): TJSONObject; static;
    /// <summary>Benachrichtigung ohne id. AParams geht in die Nachricht über und darf nil sein.</summary>
    class function Notification(const AMethod: string; AParams: TJSONValue): TJSONObject; static;
  end;

implementation

function CloneOrNull(const AValue: TJSONValue): TJSONValue;
begin
  if AValue = nil then
    Result := TJSONNull.Create
  else
    Result := TJSONValue(AValue.Clone);
end;

{ TJsonRpcMessages }

class function TJsonRpcMessages.Response(const AId: TJSONValue; AResult: TJSONValue): TJSONObject;
begin
  if AResult = nil then
    AResult := TJSONNull.Create;
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', Version);
  Result.AddPair('id', CloneOrNull(AId));
  Result.AddPair('result', AResult);
end;

class function TJsonRpcMessages.Error(const AId: TJSONValue; ACode: Integer; const AMessage: string): TJSONObject;
var
  ErrorObject: TJSONObject;
begin
  ErrorObject := TJSONObject.Create;
  ErrorObject.AddPair('code', TJSONNumber.Create(ACode));
  ErrorObject.AddPair('message', AMessage);

  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', Version);
  Result.AddPair('id', CloneOrNull(AId));
  Result.AddPair('error', ErrorObject);
end;

class function TJsonRpcMessages.Notification(const AMethod: string; AParams: TJSONValue): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', Version);
  Result.AddPair('method', AMethod);
  if AParams <> nil then
    Result.AddPair('params', AParams);
end;

end.
