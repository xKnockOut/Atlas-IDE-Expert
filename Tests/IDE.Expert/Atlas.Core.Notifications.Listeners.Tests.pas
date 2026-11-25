unit Atlas.Core.Notifications.Listeners.Tests;

// Beobachter der Benachrichtigungszentrale (TAtlasNotificationListeners).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasNotificationListenersTests = class
  public
    [Test]
    procedure ChangedCallsEveryListenerAndCountsVersion;
    [Test]
    procedure RemovedListenerIsNotCalled;
    [Test]
    procedure FailingListenerDoesNotStopOthers;
    /// <summary>RemoveOwned meldet genau die Beobachter ab, deren Code dem Modul gehört.</summary>
    [Test]
    procedure RemoveOwnedDropsOnlyModuleListeners;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Notifications.Listeners;

{ TAtlasNotificationListenersTests }

procedure TAtlasNotificationListenersTests.ChangedCallsEveryListenerAndCountsVersion;
var
  mListeners: TAtlasNotificationListeners;
  mCalls: Integer;
begin
  mCalls := 0;
  mListeners := TAtlasNotificationListeners.Create;
  try
    Assert.AreEqual(0, mListeners.Version);
    mListeners.Add(
      procedure
      begin
        Inc(mCalls);
      end);
    mListeners.Add(
      procedure
      begin
        Inc(mCalls, 10);
      end);
    mListeners.Changed;
    mListeners.Changed;
    Assert.AreEqual(22, mCalls);
    Assert.AreEqual(2, mListeners.Version);
  finally
    mListeners.Free;
  end;
end;

procedure TAtlasNotificationListenersTests.RemovedListenerIsNotCalled;
var
  mListeners: TAtlasNotificationListeners;
  mCalls, mHandle: Integer;
begin
  mCalls := 0;
  mListeners := TAtlasNotificationListeners.Create;
  try
    mHandle := mListeners.Add(
      procedure
      begin
        Inc(mCalls);
      end);
    mListeners.Remove(mHandle);
    // Unbekannter Griff: übergangen.
    mListeners.Remove(mHandle + 1);
    mListeners.Changed;
    Assert.AreEqual(0, mCalls);
    Assert.AreEqual(1, mListeners.Version);
  finally
    mListeners.Free;
  end;
end;

procedure TAtlasNotificationListenersTests.FailingListenerDoesNotStopOthers;
var
  mListeners: TAtlasNotificationListeners;
  mCalls: Integer;
begin
  mCalls := 0;
  mListeners := TAtlasNotificationListeners.Create;
  try
    mListeners.Add(
      procedure
      begin
        raise Exception.Create('Beobachter kaputt');
      end);
    mListeners.Add(
      procedure
      begin
        Inc(mCalls);
      end);
    Assert.WillNotRaise(
      procedure
      begin
        mListeners.Changed;
      end);
    Assert.AreEqual(1, mCalls);
  finally
    mListeners.Free;
  end;
end;

procedure TAtlasNotificationListenersTests.RemoveOwnedDropsOnlyModuleListeners;
var
  mListeners: TAtlasNotificationListeners;
  mModule, mOther: TProc;
  mModuleCode: Pointer;
  mCalls: Integer;
begin
  mCalls := 0;
  mModule :=
    procedure
    begin
      Inc(mCalls, 10);
    end;
  mOther :=
    procedure
    begin
      Inc(mCalls);
    end;
  mModuleCode := PPointer(@mModule)^;
  mListeners := TAtlasNotificationListeners.Create;
  try
    mListeners.Add(mModule);
    mListeners.Add(mOther);
    Assert.AreEqual(1, mListeners.RemoveOwned(
      function(AReference: Pointer): Boolean
      begin
        Result := AReference = mModuleCode;
      end));
    mListeners.Changed;
    Assert.AreEqual(1, mCalls, 'nur der fremde Beobachter');
    Assert.AreEqual(0, mListeners.RemoveOwned(
      function(AReference: Pointer): Boolean
      begin
        Result := AReference = mModuleCode;
      end), 'schon abgemeldet');
  finally
    mListeners.Free;
  end;
  mModule := nil;
  mOther := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasNotificationListenersTests);

end.
