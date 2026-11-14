unit Atlas.Common.JsonRpc.CurrentRequest.Tests;

// Abbruchsignal der laufenden Anfrage je Thread.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TJsonRpcCurrentRequestTests = class
  public
    [Test]
    procedure TokenIsNilOutsideHandler;
    [Test]
    procedure EnterAffectsCurrentThreadOnly;
    [Test]
    procedure LeaveRestoresPreviousToken;
    [Test]
    procedure ThrowIfCancellationRequestedRaisesForCancelledToken;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.PendingRequests,
  Atlas.Common.JsonRpc.CurrentRequest;

{ TJsonRpcCurrentRequestTests }

procedure TJsonRpcCurrentRequestTests.TokenIsNilOutsideHandler;
begin
  Assert.IsNull(TJsonRpcCurrentRequest.Token);
  // Ohne Anfrage nichts auslösen.
  TJsonRpcCurrentRequest.ThrowIfCancellationRequested;
end;

procedure TJsonRpcCurrentRequestTests.EnterAffectsCurrentThreadOnly;
var
  mToken: IJsonRpcCancellationToken;
  mPrevious: Pointer;
  mOtherSeen: Boolean;
  mOther: TThread;
begin
  mToken := TJsonRpcCancellation.Create;
  mOtherSeen := True;
  mPrevious := TJsonRpcCurrentRequest.Enter(mToken);
  try
    mOther := TThread.CreateAnonymousThread(
      procedure
      begin
        mOtherSeen := TJsonRpcCurrentRequest.Token <> nil;
      end);
    mOther.FreeOnTerminate := False;
    try
      mOther.Start;
      mOther.WaitFor;
    finally
      mOther.Free;
    end;
    Assert.AreSame(mToken as IInterface, TJsonRpcCurrentRequest.Token as IInterface);
  finally
    TJsonRpcCurrentRequest.Leave(mPrevious);
  end;
  Assert.IsFalse(mOtherSeen);
end;

procedure TJsonRpcCurrentRequestTests.LeaveRestoresPreviousToken;
var
  mOuter, mInner: IJsonRpcCancellationToken;
  mOuterPrevious, mInnerPrevious: Pointer;
begin
  mOuter := TJsonRpcCancellation.Create;
  mInner := TJsonRpcCancellation.Create;
  mOuterPrevious := TJsonRpcCurrentRequest.Enter(mOuter);
  try
    mInnerPrevious := TJsonRpcCurrentRequest.Enter(mInner);
    try
      Assert.AreSame(mInner as IInterface, TJsonRpcCurrentRequest.Token as IInterface);
    finally
      TJsonRpcCurrentRequest.Leave(mInnerPrevious);
    end;
    Assert.AreSame(mOuter as IInterface, TJsonRpcCurrentRequest.Token as IInterface);
  finally
    TJsonRpcCurrentRequest.Leave(mOuterPrevious);
  end;
  Assert.IsNull(TJsonRpcCurrentRequest.Token);
end;

procedure TJsonRpcCurrentRequestTests.ThrowIfCancellationRequestedRaisesForCancelledToken;
var
  mSource: IJsonRpcCancellationSource;
  mPrevious: Pointer;
begin
  mSource := TJsonRpcCancellation.Create;
  mPrevious := TJsonRpcCurrentRequest.Enter(mSource);
  try
    TJsonRpcCurrentRequest.ThrowIfCancellationRequested;
    mSource.Cancel;
    Assert.WillRaise(
      procedure
      begin
        TJsonRpcCurrentRequest.ThrowIfCancellationRequested;
      end, EJsonRpcRequestCancelled);
  finally
    TJsonRpcCurrentRequest.Leave(mPrevious);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonRpcCurrentRequestTests);

end.
