unit Atlas.Core.Modules.Registration.Tests;

// Gemeinsame Anmeldung von Base (#1455, Regel 4): Revoke löst genau einmal,
// Detach markiert als gelöst, ohne die Ablage zu rufen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRegistrationTests = class
  public
    [Test]
    procedure RevokeCallsOwnerOnce;
    [Test]
    procedure DetachSkipsOwner;
    [Test]
    procedure RevokeAfterFailureStaysRevoked;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registration;

type
  /// <summary>Zählt die Aufrufe von DoRevoke; Fail wirft dabei.</summary>
  TCountingRegistration = class(TAtlasRegistration)
  protected
    procedure DoRevoke; override;
  public
    Count: Integer;
    Fail: Boolean;
  end;

procedure TCountingRegistration.DoRevoke;
begin
  Inc(Count);
  if Fail then
  begin
    raise EInvalidOp.Create('Lösen gescheitert');
  end;
end;

{ TRegistrationTests }

procedure TRegistrationTests.RevokeCallsOwnerOnce;
var
  mItem: TCountingRegistration;
  mRef: IAtlasRegistration;
begin
  mItem := TCountingRegistration.Create;
  mRef := mItem;
  Assert.IsFalse(mRef.IsRevoked);
  mRef.Revoke;
  mRef.Revoke;
  Assert.IsTrue(mRef.IsRevoked);
  Assert.AreEqual(1, mItem.Count);
end;

procedure TRegistrationTests.DetachSkipsOwner;
var
  mItem: TCountingRegistration;
  mRef: IAtlasRegistration;
begin
  mItem := TCountingRegistration.Create;
  mRef := mItem;
  mItem.Detach;
  Assert.IsTrue(mRef.IsRevoked);
  mRef.Revoke;
  Assert.AreEqual(0, mItem.Count);
end;

procedure TRegistrationTests.RevokeAfterFailureStaysRevoked;
var
  mItem: TCountingRegistration;
  mRef: IAtlasRegistration;
  mRaised: Boolean;
begin
  mItem := TCountingRegistration.Create;
  mRef := mItem;
  mItem.Fail := True;
  mRaised := False;
  try
    mRef.Revoke;
  except
    on EInvalidOp do
      mRaised := True;
  end;
  Assert.IsTrue(mRaised);
  Assert.IsTrue(mRef.IsRevoked);
  mRef.Revoke;
  Assert.AreEqual(1, mItem.Count);
end;

initialization
  TDUnitX.RegisterTestFixture(TRegistrationTests);

end.
