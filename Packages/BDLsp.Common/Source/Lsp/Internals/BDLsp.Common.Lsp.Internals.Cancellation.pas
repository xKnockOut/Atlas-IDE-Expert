unit BDLsp.Common.Lsp.Internals.Cancellation;

// Reicht das Abbruchsignal einer JSON-RPC-Anfrage an den Parser weiter, damit
// abgebrochene oder zu lange Anfragen nicht bis zum Ende parsen.

interface

uses
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.Pascal.Contract;

type
  TRequestCancellation = class(TInterfacedObject, IPascalCancellation)
  private
    FToken: IJsonRpcCancellationToken;
  public
    constructor Create(const AToken: IJsonRpcCancellationToken);
    function IsCancelled: Boolean;
  end;

implementation

{ TRequestCancellation }

constructor TRequestCancellation.Create(const AToken: IJsonRpcCancellationToken);
begin
  inherited Create;
  FToken := AToken;
end;

function TRequestCancellation.IsCancelled: Boolean;
begin
  Result := (FToken <> nil) and FToken.IsCancellationRequested;
end;

end.
