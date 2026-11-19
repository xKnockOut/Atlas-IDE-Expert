unit Atlas.Core.Notifications.Listeners.Tests;

// Beobachter der Benachrichtigungszentrale (TAtlasNotificationListeners) und Beobachter mit Wert
// (TAtlasListeners<T>, Bereiche der Willkommensseite).

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
    /// <summary>TAtlasListeners<T> gibt jedem Beobachter den gemeldeten Wert und zählt die Version.</summary>
    [Test]
    procedure ValueReachesEveryListener;
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

procedure TAtlasNotificationListenersTests.ValueReachesEveryListener;
var
  mListeners: TAtlasListeners<string>;
  mSeen: string;
  mHandle: Integer;
begin
  mSeen := '';
  mListeners := TAtlasListeners<string>.Create;
  try
    mHandle := mListeners.Add(
      procedure(AValue: string)
      begin
        mSeen := mSeen + '[' + AValue + ']';
      end);
    mListeners.Changed('atlas.state');
    mListeners.Changed('');
    Assert.AreEqual('[atlas.state][]', mSeen);
    Assert.AreEqual(2, mListeners.Version);
    mListeners.Remove(mHandle);
    mListeners.Changed('atlas.news');
    Assert.AreEqual('[atlas.state][]', mSeen);
  finally
    mListeners.Free;
  end;
  mSeen := '';
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasNotificationListenersTests);

end.
