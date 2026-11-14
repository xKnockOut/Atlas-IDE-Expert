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
  mCancellation: IPascalCancellation;
begin
  mCancellation := TRequestCancellation.Create(nil);
  Assert.IsFalse(mCancellation.IsCancelled);
end;

procedure TRequestCancellationTests.FollowsToken;
var
  mFake: TFakeToken;
  mToken: IJsonRpcCancellationToken;
  mCancellation: IPascalCancellation;
begin
  mFake := TFakeToken.Create;
  mToken := mFake;
  mCancellation := TRequestCancellation.Create(mToken);
  Assert.IsFalse(mCancellation.IsCancelled);
  mFake.Cancelled := True;
  Assert.IsTrue(mCancellation.IsCancelled);
  mFake.Cancelled := False;
  Assert.IsFalse(mCancellation.IsCancelled);
end;

initialization
  TDUnitX.RegisterTestFixture(TRequestCancellationTests);

end.
