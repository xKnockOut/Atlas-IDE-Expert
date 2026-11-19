unit Atlas.Common.JsonRpc.CustomCancellation.Tests;

// Tests für das Abbruchsignal mit eigenem Grund: ohne Grund weiter, mit Grund
// abgebrochen mit der genannten Ausnahme, das innere Token geht vor.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TJsonRpcCustomCancellationTests = class
  public
    [Test]
    procedure WithoutReasonContinues;
    [Test]
    procedure ReasonCancelsWithItsException;
    [Test]
    procedure InnerTokenComesFirst;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.CustomCancellation;

type
  EProbeReason = class(Exception);
  EProbeInner = class(Exception);

  TInnerToken = class(TInterfacedObject, IJsonRpcCancellationToken)
  public
    Cancelled: Boolean;
    function IsCancellationRequested: Boolean;
    procedure ThrowIfCancellationRequested;
  end;

  TReasonState = class
  public
    Text: string;
  end;

{ TInnerToken }

function TInnerToken.IsCancellationRequested: Boolean;
begin
  Result := Cancelled;
end;

procedure TInnerToken.ThrowIfCancellationRequested;
begin
  if Cancelled then
  begin
    raise EProbeInner.Create('inner');
  end;
end;

function ReasonOf(AState: TReasonState): TJsonRpcCancelReason;
begin
  Result :=
    function(out AClass: ExceptClass): string
    begin
      AClass := EProbeReason;
      Result := AState.Text;
    end;
end;

{ TJsonRpcCustomCancellationTests }

procedure TJsonRpcCustomCancellationTests.WithoutReasonContinues;
var
  mState: TReasonState;
  mToken: IJsonRpcCancellationToken;
begin
  mState := TReasonState.Create;
  try
    mToken := TJsonRpcCancellations.WithReason(nil, ReasonOf(mState));
    Assert.IsFalse(mToken.IsCancellationRequested);
    mToken.ThrowIfCancellationRequested;
    Assert.Pass;
  finally
    mToken := nil;
    mState.Free;
  end;
end;

procedure TJsonRpcCustomCancellationTests.ReasonCancelsWithItsException;
var
  mState: TReasonState;
  mToken: IJsonRpcCancellationToken;
begin
  mState := TReasonState.Create;
  try
    mToken := TJsonRpcCancellations.WithReason(nil, ReasonOf(mState));
    mState.Text := 'Frist';
    Assert.IsTrue(mToken.IsCancellationRequested);
    Assert.WillRaiseWithMessage(
      procedure
      begin
        mToken.ThrowIfCancellationRequested;
      end, EProbeReason, 'Frist');
  finally
    mToken := nil;
    mState.Free;
  end;
end;

procedure TJsonRpcCustomCancellationTests.InnerTokenComesFirst;
var
  mState: TReasonState;
  mFake: TInnerToken;
  mInner: IJsonRpcCancellationToken;
  mToken: IJsonRpcCancellationToken;
begin
  mState := TReasonState.Create;
  try
    mFake := TInnerToken.Create;
    mInner := mFake;
    mToken := TJsonRpcCancellations.WithReason(mInner, ReasonOf(mState));
    mFake.Cancelled := True;
    mState.Text := 'Frist';
    Assert.IsTrue(mToken.IsCancellationRequested);
    Assert.WillRaise(
      procedure
      begin
        mToken.ThrowIfCancellationRequested;
      end, EProbeInner);
  finally
    mToken := nil;
    mInner := nil;
    mState.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonRpcCustomCancellationTests);

end.
