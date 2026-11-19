unit Atlas.Common.Lsp.Internals.Cancellation;

// Reicht das Abbruchsignal einer JSON-RPC-Anfrage an den Parser weiter, damit
// abgebrochene oder zu lange Anfragen nicht bis zum Ende parsen.

interface

uses
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Pascal.Contract;

type
  TRequestCancellation = record
  public
    /// <summary>Signal für den Parser, das dem Token folgt; ohne Token bricht es nie ab.</summary>
    class function Create(const AToken: IJsonRpcCancellationToken): IPascalCancellation; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.Cancellation;

{ TRequestCancellation }

class function TRequestCancellation.Create(const AToken: IJsonRpcCancellationToken): IPascalCancellation;
var
  mToken: IJsonRpcCancellationToken;
begin
  mToken := AToken;
  Result := TPascalCancellations.FromCheck(
    function: Boolean
    begin
      Result := (mToken <> nil) and mToken.IsCancellationRequested;
    end);
end;

end.
