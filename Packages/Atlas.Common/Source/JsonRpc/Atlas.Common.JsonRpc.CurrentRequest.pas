unit Atlas.Common.JsonRpc.CurrentRequest;

// Abbruchsignal der Anfrage, die im aktuellen Thread läuft (Code-Review A-06).
// Für tiefe Aufrufe ohne Token-Parameter, z. B. EnsureUnit über TEnsureUnitFunc
// (rund 50 Verwendungen, die Signatur bleibt). Der Dispatcher setzt es für die
// Dauer jedes Handlers.

interface

uses
  Atlas.Common.JsonRpc.Contract;

type
  TJsonRpcCurrentRequest = record
  public
    /// <summary>Setzt AToken für den aktuellen Thread; liefert das vorige für Leave.</summary>
    class function Enter(const AToken: IJsonRpcCancellationToken): Pointer; static;
    /// <summary>Stellt das Token vor Enter wieder her.</summary>
    class procedure Leave(APrevious: Pointer); static;
    /// <summary>Token der laufenden Anfrage; nil außerhalb eines Handlers.</summary>
    class function Token: IJsonRpcCancellationToken; static;
    /// <summary>Löst EJsonRpcRequestCancelled (bzw. EJsonRpcContentModified) aus, wenn die laufende Anfrage
    /// abgebrochen ist; außerhalb eines Handlers nichts.</summary>
    class procedure ThrowIfCancellationRequested; static;
  end;

implementation

threadvar
  // Nicht gezählt (threadvar verwaltet keine Interfaces): Der Dispatcher hält das Token, solange der
  // Handler läuft.
  Current: Pointer;

{ TJsonRpcCurrentRequest }

class function TJsonRpcCurrentRequest.Enter(const AToken: IJsonRpcCancellationToken): Pointer;
begin
  Result := Current;
  Current := Pointer(AToken);
end;

class procedure TJsonRpcCurrentRequest.Leave(APrevious: Pointer);
begin
  Current := APrevious;
end;

class function TJsonRpcCurrentRequest.Token: IJsonRpcCancellationToken;
begin
  Result := IJsonRpcCancellationToken(Current);
end;

class procedure TJsonRpcCurrentRequest.ThrowIfCancellationRequested;
var
  Active: IJsonRpcCancellationToken;
begin
  Active := Token;
  if Active <> nil then
    Active.ThrowIfCancellationRequested;
end;

end.
