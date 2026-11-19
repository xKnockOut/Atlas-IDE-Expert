unit Atlas.Common.Pascal.Cancellation.Tests;

// Tests für das Abbruchsignal aus einer Funktion: ohne Funktion nie
// abgebrochen, sonst folgt IsCancelled der Funktion.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPascalCancellationTests = class
  public
    [Test]
    procedure WithoutCheckNeverCancelled;
    [Test]
    procedure FollowsCheck;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Cancellation;

type
  TCheckState = class
  public
    Cancelled: Boolean;
  end;

function CheckOf(AState: TCheckState): TFunc<Boolean>;
begin
  Result :=
    function: Boolean
    begin
      Result := AState.Cancelled;
    end;
end;

{ TPascalCancellationTests }

procedure TPascalCancellationTests.WithoutCheckNeverCancelled;
var
  mCancellation: IPascalCancellation;
begin
  mCancellation := TPascalCancellations.FromCheck(nil);
  Assert.IsFalse(mCancellation.IsCancelled);
end;

procedure TPascalCancellationTests.FollowsCheck;
var
  mState: TCheckState;
  mCancellation: IPascalCancellation;
begin
  mState := TCheckState.Create;
  try
    mCancellation := TPascalCancellations.FromCheck(CheckOf(mState));
    Assert.IsFalse(mCancellation.IsCancelled);
    mState.Cancelled := True;
    Assert.IsTrue(mCancellation.IsCancelled);
  finally
    mCancellation := nil;
    mState.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TPascalCancellationTests);

end.
