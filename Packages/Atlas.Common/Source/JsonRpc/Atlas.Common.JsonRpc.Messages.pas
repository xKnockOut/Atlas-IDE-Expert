unit Atlas.Common.JsonRpc.Messages;

// Aufbau von JSON-RPC-2.0-Nachrichten (Antwort, Fehlerantwort, Benachrichtigung).

interface

uses
  System.JSON;

type
  TJsonRpcMessages = record
  public const
    cVersion = '2.0';
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
  begin
    Result := TJSONNull.Create;
  end
  else
  begin
    Result := TJSONValue(AValue.Clone);
  end;
end;

{ TJsonRpcMessages }

class function TJsonRpcMessages.Response(const AId: TJSONValue; AResult: TJSONValue): TJSONObject;
begin
  if AResult = nil then
  begin
    AResult := TJSONNull.Create;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', cVersion);
  Result.AddPair('id', CloneOrNull(AId));
  Result.AddPair('result', AResult);
end;

class function TJsonRpcMessages.Error(const AId: TJSONValue; ACode: Integer; const AMessage: string): TJSONObject;
var
  mErrorObject: TJSONObject;
begin
  mErrorObject := TJSONObject.Create;
  mErrorObject.AddPair('code', TJSONNumber.Create(ACode));
  mErrorObject.AddPair('message', AMessage);

  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', cVersion);
  Result.AddPair('id', CloneOrNull(AId));
  Result.AddPair('error', mErrorObject);
end;

class function TJsonRpcMessages.Notification(const AMethod: string; AParams: TJSONValue): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', cVersion);
  Result.AddPair('method', AMethod);
  if AParams <> nil then
  begin
    Result.AddPair('params', AParams);
  end;
end;

end.
