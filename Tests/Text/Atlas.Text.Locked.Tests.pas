unit Atlas.Text.Locked.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextLockedTests = class
  public
    [Test]
    procedure ReadCopiesFieldAndReleasesLock;
  end;

implementation

uses
  System.Classes,
  System.SyncObjs,
  Atlas.Text.Locked;

function FreeInOtherThread(ALock: TCriticalSection): Boolean;
var
  mFree: Boolean;
  mThread: TThread;
begin
  mFree := False;
  mThread := TThread.CreateAnonymousThread(
    procedure
    begin
      mFree := ALock.TryEnter;
      if mFree then
      begin
        ALock.Leave;
      end;
    end);
  mThread.FreeOnTerminate := False;
  try
    mThread.Start;
    mThread.WaitFor;
  finally
    mThread.Free;
  end;
  Result := mFree;
end;

{ TTextLockedTests }

procedure TTextLockedTests.ReadCopiesFieldAndReleasesLock;
var
  mLock: TCriticalSection;
  mField: string;
begin
  mLock := TCriticalSection.Create;
  try
    mField := 'Wert';
    Assert.AreEqual('Wert', TTextLocked.Read<string>(mLock, mField));
    Assert.IsTrue(FreeInOtherThread(mLock), 'Sperre nach dem Lesen frei');
  finally
    mLock.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTextLockedTests);

end.
