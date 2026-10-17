unit Atlas.Common.Lsp.Internals.Cancellation.Tests;

// Tests für die Weitergabe des Abbruchsignals an den Parser (#415): ohne
// Token nie abgebrochen, sonst folgt IsCancelled dem Token der Anfrage.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRequestCancellationTests = class
  public
    [Test]
    procedure WithoutTokenNeverCancelled;
    [Test]
    procedure FollowsToken;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Lsp.Internals.Cancellation;

type
  TFakeToken = class(TInterfacedObject, IJsonRpcCancellationToken)
  public
    Cancelled: Boolean;
    function IsCancellationRequested: Boolean;
    procedure ThrowIfCancellationRequested;
  end;

function TFakeToken.IsCancellationRequested: Boolean;
begin
  Result := Cancelled;
end;

procedure TFakeToken.ThrowIfCancellationRequested;
begin
end;

{ TRequestCancellationTests }

procedure TRequestCancellationTests.WithoutTokenNeverCancelled;
var
  Cancellation: IPascalCancellation;
begin
  Cancellation := TRequestCancellation.Create(nil);
  Assert.IsFalse(Cancellation.IsCancelled);
end;

procedure TRequestCancellationTests.FollowsToken;
var
  Fake: TFakeToken;
  Token: IJsonRpcCancellationToken;
  Cancellation: IPascalCancellation;
begin
  Fake := TFakeToken.Create;
  Token := Fake;
  Cancellation := TRequestCancellation.Create(Token);
  Assert.IsFalse(Cancellation.IsCancelled);
  Fake.Cancelled := True;
  Assert.IsTrue(Cancellation.IsCancelled);
  Fake.Cancelled := False;
  Assert.IsFalse(Cancellation.IsCancelled);
end;

initialization
  TDUnitX.RegisterTestFixture(TRequestCancellationTests);

end.
