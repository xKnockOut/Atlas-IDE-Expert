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
  Token: IJsonRpcCancellationToken;
  Previous: Pointer;
  OtherSeen: Boolean;
  Other: TThread;
begin
  Token := TJsonRpcCancellation.Create;
  OtherSeen := True;
  Previous := TJsonRpcCurrentRequest.Enter(Token);
  try
    Other := TThread.CreateAnonymousThread(
      procedure
      begin
        OtherSeen := TJsonRpcCurrentRequest.Token <> nil;
      end);
    Other.FreeOnTerminate := False;
    try
      Other.Start;
      Other.WaitFor;
    finally
      Other.Free;
    end;
    Assert.AreSame(Token as IInterface, TJsonRpcCurrentRequest.Token as IInterface);
  finally
    TJsonRpcCurrentRequest.Leave(Previous);
  end;
  Assert.IsFalse(OtherSeen);
end;

procedure TJsonRpcCurrentRequestTests.LeaveRestoresPreviousToken;
var
  Outer, Inner: IJsonRpcCancellationToken;
  OuterPrevious, InnerPrevious: Pointer;
begin
  Outer := TJsonRpcCancellation.Create;
  Inner := TJsonRpcCancellation.Create;
  OuterPrevious := TJsonRpcCurrentRequest.Enter(Outer);
  try
    InnerPrevious := TJsonRpcCurrentRequest.Enter(Inner);
    try
      Assert.AreSame(Inner as IInterface, TJsonRpcCurrentRequest.Token as IInterface);
    finally
      TJsonRpcCurrentRequest.Leave(InnerPrevious);
    end;
    Assert.AreSame(Outer as IInterface, TJsonRpcCurrentRequest.Token as IInterface);
  finally
    TJsonRpcCurrentRequest.Leave(OuterPrevious);
  end;
  Assert.IsNull(TJsonRpcCurrentRequest.Token);
end;

procedure TJsonRpcCurrentRequestTests.ThrowIfCancellationRequestedRaisesForCancelledToken;
var
  Source: IJsonRpcCancellationSource;
  Previous: Pointer;
begin
  Source := TJsonRpcCancellation.Create;
  Previous := TJsonRpcCurrentRequest.Enter(Source);
  try
    TJsonRpcCurrentRequest.ThrowIfCancellationRequested;
    Source.Cancel;
    Assert.WillRaise(
      procedure
      begin
        TJsonRpcCurrentRequest.ThrowIfCancellationRequested;
      end, EJsonRpcRequestCancelled);
  finally
    TJsonRpcCurrentRequest.Leave(Previous);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonRpcCurrentRequestTests);

end.
