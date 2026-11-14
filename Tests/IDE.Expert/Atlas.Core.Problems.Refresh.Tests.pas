unit Atlas.Core.Problems.Refresh.Tests;

// Tests für die Aktualisierung der Prüfung (problems.update,
// problems.liveDelayMs): Takt, Entscheidung je Art und Anforderung. Die Werte
// der Einstellungen prüft Atlas.Core.Settings.ProblemsUpdate.Tests.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasProblemsRefreshTests = class
  public
    [Test]
    procedure TickFollowsShortDelay;
    [Test]
    procedure RequestAlwaysChecks;
    [Test]
    procedure UnchangedTextIsNotChecked;
    [Test]
    procedure LiveWaitsForDelay;
    [Test]
    procedure SaveWaitsForSavedBuffer;
    [Test]
    procedure ManualChecksOnlyFirstUnmodifiedView;
    [Test]
    procedure RequestIsTakenOnce;
    /// <summary>#1817: angeforderte Dateien einmal, ohne Doppelte, unabhängig von Clear.</summary>
    [Test]
    procedure FilesAreTakenOnce;
  end;

implementation

uses
  Atlas.Core.Settings.ProblemsUpdate,
  Atlas.Core.Problems.Refresh;

function State(AChanged, ACheckedBefore, AModified: Boolean; AQuietMs: Cardinal): TAtlasProblemsRefreshState;
begin
  Result := Default(TAtlasProblemsRefreshState);
  Result.Changed := AChanged;
  Result.CheckedBefore := ACheckedBefore;
  Result.Modified := AModified;
  Result.QuietMs := AQuietMs;
end;

procedure TAtlasProblemsRefreshTests.TickFollowsShortDelay;
begin
  Assert.AreEqual(250, TAtlasProblemsRefresh.TickMs(400));
  Assert.AreEqual(250, TAtlasProblemsRefresh.TickMs(5000));
  Assert.AreEqual(150, TAtlasProblemsRefresh.TickMs(150));
  Assert.AreEqual(100, TAtlasProblemsRefresh.TickMs(10));
end;

procedure TAtlasProblemsRefreshTests.RequestAlwaysChecks;
var
  mState: TAtlasProblemsRefreshState;
  mMode: TAtlasProblemsUpdate;
begin
  // Auch ungeändert, ungespeichert und ohne Pause: angefordert ist angefordert.
  mState := State(False, True, True, 0);
  mState.Requested := True;
  for mMode := Low(TAtlasProblemsUpdate) to High(TAtlasProblemsUpdate) do
  begin
    Assert.IsTrue(TAtlasProblemsRefresh.Due(mMode, mState, 400), TAtlasProblemsUpdateSetting.Name(mMode));
  end;
end;

procedure TAtlasProblemsRefreshTests.UnchangedTextIsNotChecked;
var
  mMode: TAtlasProblemsUpdate;
begin
  for mMode := Low(TAtlasProblemsUpdate) to High(TAtlasProblemsUpdate) do
  begin
    Assert.IsFalse(TAtlasProblemsRefresh.Due(mMode, State(False, True, False, 5000), 400),
      TAtlasProblemsUpdateSetting.Name(mMode));
  end;
end;

procedure TAtlasProblemsRefreshTests.LiveWaitsForDelay;
begin
  Assert.IsFalse(TAtlasProblemsRefresh.Due(TAtlasProblemsUpdate.Live, State(True, True, True, 399), 400));
  Assert.IsTrue(TAtlasProblemsRefresh.Due(TAtlasProblemsUpdate.Live, State(True, True, True, 400), 400));
  // Längere Verzögerung eingestellt.
  Assert.IsFalse(TAtlasProblemsRefresh.Due(TAtlasProblemsUpdate.Live, State(True, True, True, 1500), 2000));
  Assert.IsTrue(TAtlasProblemsRefresh.Due(TAtlasProblemsUpdate.Live, State(True, True, True, 2000), 2000));
  // Zu kleine Werte gelten als 100 ms.
  Assert.IsFalse(TAtlasProblemsRefresh.Due(TAtlasProblemsUpdate.Live, State(True, True, True, 50), 0));
  Assert.IsTrue(TAtlasProblemsRefresh.Due(TAtlasProblemsUpdate.Live, State(True, True, True, 100), 0));
end;

procedure TAtlasProblemsRefreshTests.SaveWaitsForSavedBuffer;
begin
  Assert.IsFalse(TAtlasProblemsRefresh.Due(TAtlasProblemsUpdate.Save, State(True, True, True, 5000), 400),
    'ungespeichert');
  Assert.IsTrue(TAtlasProblemsRefresh.Due(TAtlasProblemsUpdate.Save, State(True, True, False, 5000), 400),
    'gespeichert');
  Assert.IsTrue(TAtlasProblemsRefresh.Due(TAtlasProblemsUpdate.Save, State(True, False, False, 5000), 400),
    'erstmals geöffnet');
end;

procedure TAtlasProblemsRefreshTests.ManualChecksOnlyFirstUnmodifiedView;
begin
  Assert.IsTrue(TAtlasProblemsRefresh.Due(TAtlasProblemsUpdate.Manual, State(True, False, False, 0), 400),
    'erstmals geöffnet');
  Assert.IsFalse(TAtlasProblemsRefresh.Due(TAtlasProblemsUpdate.Manual, State(True, False, True, 5000), 400),
    'erstmals, aber geändert');
  Assert.IsFalse(TAtlasProblemsRefresh.Due(TAtlasProblemsUpdate.Manual, State(True, True, True, 5000), 400),
    'getippt');
  Assert.IsFalse(TAtlasProblemsRefresh.Due(TAtlasProblemsUpdate.Manual, State(True, True, False, 5000), 400),
    'gespeichert');
end;

procedure TAtlasProblemsRefreshTests.RequestIsTakenOnce;
begin
  TAtlasProblemsCheckRequest.Clear;
  try
    Assert.IsFalse(TAtlasProblemsCheckRequest.Take, 'nichts angefordert');
    TAtlasProblemsCheckRequest.Request;
    TAtlasProblemsCheckRequest.Request;
    Assert.IsTrue(TAtlasProblemsCheckRequest.Pending);
    Assert.IsTrue(TAtlasProblemsCheckRequest.Take, 'angefordert');
    Assert.IsFalse(TAtlasProblemsCheckRequest.Pending);
    Assert.IsFalse(TAtlasProblemsCheckRequest.Take, 'nur einmal');
  finally
    TAtlasProblemsCheckRequest.Clear;
  end;
end;

procedure TAtlasProblemsRefreshTests.FilesAreTakenOnce;
var
  mFiles: TArray<string>;
begin
  TAtlasProblemsCheckRequest.TakeFiles;
  TAtlasProblemsCheckRequest.RequestFiles(['C:\P\A.pas', 'C:\P\B.pas']);
  TAtlasProblemsCheckRequest.RequestFiles(['c:\p\a.pas', '', 'C:\P\C.pas']);
  TAtlasProblemsCheckRequest.Clear;
  Assert.IsFalse(TAtlasProblemsCheckRequest.Pending, 'keine Prüfung der offenen Datei');
  mFiles := TAtlasProblemsCheckRequest.TakeFiles;
  Assert.AreEqual(3, Integer(Length(mFiles)));
  Assert.AreEqual('C:\P\A.pas', mFiles[0]);
  Assert.AreEqual('C:\P\C.pas', mFiles[2]);
  Assert.AreEqual(0, Integer(Length(TAtlasProblemsCheckRequest.TakeFiles)), 'nur einmal');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasProblemsRefreshTests);

end.
