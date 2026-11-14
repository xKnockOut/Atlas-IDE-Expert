unit Atlas.Core.Diagnostics.SafeMode.Tests;

// Abgesicherter Start (#722): Startmarke anlegen und lesen, Erkennung eines
// Absturzes, Zählung wiederholter Abstürze, langsamer Start ist kein Absturz
//, Taste und Kommandozeile, Auswahl der Funktionen im
// abgesicherten Modus, Vorschlag und Einstellungsstände zurücksetzen.
// Sitzungen mit ATLAS_NO_SESSION_MARKER schreiben keine Marke und zählen keine
// fremden Abstürze.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSafeModeTests = class
  public
    [Test]
    procedure MarkerRoundTrips;
    [Test]
    procedure NoMarkerStartsNormal;
    [Test]
    procedure CrashAsksAndStartsSafe;
    [Test]
    procedure RepeatedCrashStartsSafeWithoutAsking;
    [Test]
    procedure CleanExitResetsCount;
    [Test]
    procedure SlowStartIsNoCrash;
    [Test]
    procedure KeyAndCommandLineStartMinimal;
    [Test]
    procedure SwitchedOffNeverAsks;
    [Test]
    procedure StateRoundTrips;
    [Test]
    procedure SafeSessionTurnsEveryToggleOff;
    [Test]
    procedure SuggestsChangedThenFaulty;
    [Test]
    procedure SettingsHistoryRestores;
    [Test]
    procedure LogLinesOfCrashedSession;
    [Test]
    procedure MarkerFilesFindCrashedSessions;
    [Test]
    procedure NoMarkerSwitchValues;
    [Test]
    procedure SessionWithoutMarkerLeavesNoTrace;
    [Test]
    procedure TrackedSessionKeepsItsBook;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.DateUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.History,
  Atlas.Core.Settings.QuickToggles,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Diagnostics.SafeMode;

function Options: TAtlasSafeOptions;
begin
  Result := TAtlasSafeOptions.Create(True, True, TAtlasStartupKey.Shift);
end;

function Crashed(AProcess: Cardinal; AStartedAt: TDateTime): TAtlasSessionMarker;
begin
  Result := TAtlasSessionMarker.Create(AProcess, '1.0.0', AStartedAt);
  Result.Features := ['PairColors', 'Problems'];
  Result.AddFailure('Pairs');
end;

procedure TAtlasSafeModeTests.MarkerRoundTrips;
var
  mMarker, mLoaded: TAtlasSessionMarker;
begin
  mMarker := TAtlasSessionMarker.Create(4711, '1.2.3', EncodeDateTime(2026, 10, 14, 12, 0, 0, 0));
  mMarker.Features := ['PairColors', 'HoverTooltip'];
  mMarker.AddFailure('Pairs');
  mMarker.AddFailure('pairs');
  mMarker.AddFailure('Hover');
  mMarker.Loaded := True;
  mMarker.LoadMs := 812;
  mMarker.Level := TAtlasSafeLevel.Safe;
  Assert.IsTrue(TAtlasSessionMarker.FromJson(mMarker.ToJson, mLoaded));
  Assert.AreEqual(Int64(4711), Int64(mLoaded.ProcessId));
  Assert.AreEqual('1.2.3', mLoaded.Version);
  Assert.IsTrue(SameDateTime(mMarker.StartedAt, mLoaded.StartedAt));
  Assert.IsTrue(mLoaded.Loaded);
  Assert.AreEqual(Int64(812), mLoaded.LoadMs);
  Assert.AreEqual<TAtlasSafeLevel>(TAtlasSafeLevel.Safe, mLoaded.Level);
  Assert.AreEqual(2, Integer(Length(mLoaded.Features)));
  Assert.AreEqual(2, mLoaded.FailureCount('Pairs'));
  Assert.AreEqual(1, mLoaded.FailureCount('Hover'));
  Assert.AreEqual(0, mLoaded.FailureCount('Problems'));
  Assert.IsFalse(TAtlasSessionMarker.FromJson('kaputt', mLoaded));
  Assert.IsFalse(TAtlasSessionMarker.FromJson('{}', mLoaded));
end;

procedure TAtlasSafeModeTests.NoMarkerStartsNormal;
var
  mState: TAtlasSafeState;
  mDecision: TAtlasSafeDecision;
begin
  mState := Default(TAtlasSafeState);
  mDecision := TAtlasSafeMode.Decide(mState, nil, Now, Options, TAtlasStartupKey.None, False);
  Assert.AreEqual<TAtlasSafeLevel>(TAtlasSafeLevel.Normal, mDecision.Level);
  Assert.IsFalse(mDecision.Crashed);
  Assert.IsFalse(mDecision.Ask);
  Assert.AreEqual(0, mState.CrashCount);
end;

procedure TAtlasSafeModeTests.CrashAsksAndStartsSafe;
var
  mState: TAtlasSafeState;
  mDecision: TAtlasSafeDecision;
  mStart: TDateTime;
  mMarker: TAtlasSessionMarker;
begin
  mState := Default(TAtlasSafeState);
  mStart := EncodeDateTime(2026, 10, 14, 9, 0, 0, 0);
  mDecision := TAtlasSafeMode.Decide(mState, [Crashed(1, mStart - 1 / 24), Crashed(2, mStart - 1 / 48)], mStart,
    Options, TAtlasStartupKey.None, False);
  Assert.IsTrue(mDecision.Crashed);
  Assert.IsTrue(mDecision.Ask, 'Rückfrage');
  Assert.AreEqual<TAtlasSafeLevel>(TAtlasSafeLevel.Safe, mDecision.Level, 'bis zur Antwort abgesichert');
  Assert.AreEqual<TAtlasSafeReason>(TAtlasSafeReason.Crash, mDecision.Reason);
  Assert.AreEqual(1, mState.CrashCount);
  // Details zeigen die zuletzt gestartete Sitzung.
  Assert.IsTrue(TAtlasSessionMarker.FromJson(mState.CrashedMarker, mMarker));
  Assert.AreEqual(Int64(2), Int64(mMarker.ProcessId));
end;

procedure TAtlasSafeModeTests.RepeatedCrashStartsSafeWithoutAsking;
var
  mState: TAtlasSafeState;
  mDecision: TAtlasSafeDecision;
  mStart: TDateTime;
begin
  mState := Default(TAtlasSafeState);
  mStart := EncodeDateTime(2026, 10, 14, 9, 0, 0, 0);
  TAtlasSafeMode.Decide(mState, [Crashed(1, mStart - 1 / 1440)], mStart, Options, TAtlasStartupKey.None, False);
  // Zweiter Absturz fünf Minuten später.
  mDecision := TAtlasSafeMode.Decide(mState, [Crashed(2, mStart)], IncMinute(mStart, 5), Options,
    TAtlasStartupKey.None, False);
  Assert.AreEqual(2, mState.CrashCount);
  Assert.AreEqual<TAtlasSafeLevel>(TAtlasSafeLevel.Safe, mDecision.Level);
  Assert.AreEqual<TAtlasSafeReason>(TAtlasSafeReason.RepeatedCrash, mDecision.Reason);
  Assert.IsFalse(mDecision.Ask, 'ohne Rückfrage, nur Meldung');
  // Nach langer Pause gilt der nächste Absturz wieder als erster.
  mDecision := TAtlasSafeMode.Decide(mState, [Crashed(3, mStart)], IncHour(mStart, 3), Options,
    TAtlasStartupKey.None, False);
  Assert.AreEqual(1, mState.CrashCount);
  Assert.AreEqual<TAtlasSafeReason>(TAtlasSafeReason.Crash, mDecision.Reason);
end;

procedure TAtlasSafeModeTests.CleanExitResetsCount;
var
  mState: TAtlasSafeState;
  mDecision: TAtlasSafeDecision;
  mStart: TDateTime;
begin
  mState := Default(TAtlasSafeState);
  mStart := EncodeDateTime(2026, 10, 14, 9, 0, 0, 0);
  TAtlasSafeMode.Decide(mState, [Crashed(1, mStart)], mStart, Options, TAtlasStartupKey.None, False);
  TAtlasSafeMode.CleanExit(mState);
  Assert.AreEqual(0, mState.CrashCount);
  mDecision := TAtlasSafeMode.Decide(mState, [Crashed(2, mStart)], IncMinute(mStart, 2), Options,
    TAtlasStartupKey.None, False);
  Assert.AreEqual<TAtlasSafeReason>(TAtlasSafeReason.Crash, mDecision.Reason, 'nach sauberem Ende nicht „wiederholt“');
end;

procedure TAtlasSafeModeTests.SlowStartIsNoCrash;
var
  mState: TAtlasSafeState;
  mDecision: TAtlasSafeDecision;
begin
  // Ein langsamer Start schaltete früher beim nächsten Start alles ab. Ein Zustand älterer Fassungen
  // mit "slowStart" startet jetzt normal; die Startanteile nennen stattdessen die Ursache.
  mState := TAtlasSafeState.FromJson('{"crashCount": 0, "slowStart": true}');
  mDecision := TAtlasSafeMode.Decide(mState, nil, Now, Options, TAtlasStartupKey.None, False);
  Assert.IsFalse(mDecision.Crashed, 'langsamer Start ist kein Absturz');
  Assert.IsFalse(mDecision.Ask);
  Assert.AreEqual<TAtlasSafeLevel>(TAtlasSafeLevel.Normal, mDecision.Level);
  Assert.AreEqual(0, mState.CrashCount);
  Assert.IsFalse(mState.ToJson.Contains('slowStart'), 'wird nicht mehr geschrieben');
end;

procedure TAtlasSafeModeTests.KeyAndCommandLineStartMinimal;
var
  mState: TAtlasSafeState;
  mDecision: TAtlasSafeDecision;
begin
  mState := Default(TAtlasSafeState);
  mDecision := TAtlasSafeMode.Decide(mState, nil, Now, Options, TAtlasStartupKey.Shift, False);
  Assert.AreEqual<TAtlasSafeLevel>(TAtlasSafeLevel.Minimal, mDecision.Level);
  Assert.AreEqual<TAtlasSafeReason>(TAtlasSafeReason.StartupKey, mDecision.Reason);
  mDecision := TAtlasSafeMode.Decide(mState, nil, Now, Options, TAtlasStartupKey.Ctrl, False);
  Assert.AreEqual<TAtlasSafeLevel>(TAtlasSafeLevel.Normal, mDecision.Level, 'andere Taste als eingestellt');
  mDecision := TAtlasSafeMode.Decide(mState, nil, Now, Options, TAtlasStartupKey.None, True);
  Assert.AreEqual<TAtlasSafeLevel>(TAtlasSafeLevel.Minimal, mDecision.Level);
  Assert.AreEqual<TAtlasSafeReason>(TAtlasSafeReason.Forced, mDecision.Reason);
  Assert.IsTrue(TAtlasSafeMode.IsForced('1', nil));
  Assert.IsTrue(TAtlasSafeMode.IsForced('', ['bds.exe', '-pDelphi', '-AtlasSafeMode']));
  Assert.IsTrue(TAtlasSafeMode.IsForced('', ['/atlassafemode']));
  Assert.IsFalse(TAtlasSafeMode.IsForced('0', ['-np']));
  Assert.AreEqual<TAtlasStartupKey>(TAtlasStartupKey.Ctrl, TAtlasSafeMode.KeyOf('ctrl'));
  Assert.AreEqual<TAtlasStartupKey>(TAtlasStartupKey.None, TAtlasSafeMode.KeyOf('none'));
  Assert.AreEqual<TAtlasStartupKey>(TAtlasStartupKey.Shift, TAtlasSafeMode.KeyOf('quatsch'));
  Assert.AreEqual('ctrl', TAtlasSafeMode.KeyText(TAtlasStartupKey.Ctrl));
end;

procedure TAtlasSafeModeTests.SwitchedOffNeverAsks;
var
  mState: TAtlasSafeState;
  mDecision: TAtlasSafeDecision;
  mOff: TAtlasSafeOptions;
  mStart: TDateTime;
begin
  // safeMode.askAfterCrash und autoAfterRepeatedCrash aus, startupKey none: abgeschaltet.
  mOff := TAtlasSafeOptions.Create(False, False, TAtlasStartupKey.None);
  mState := Default(TAtlasSafeState);
  mStart := EncodeDateTime(2026, 10, 14, 9, 0, 0, 0);
  mDecision := TAtlasSafeMode.Decide(mState, [Crashed(1, mStart)], mStart, mOff, TAtlasStartupKey.Shift, False);
  Assert.AreEqual<TAtlasSafeLevel>(TAtlasSafeLevel.Normal, mDecision.Level);
  Assert.IsFalse(mDecision.Ask);
  mDecision := TAtlasSafeMode.Decide(mState, [Crashed(2, mStart)], IncMinute(mStart, 1), mOff,
    TAtlasStartupKey.Shift, False);
  Assert.AreEqual<TAtlasSafeLevel>(TAtlasSafeLevel.Normal, mDecision.Level, 'auch nach wiederholtem Absturz');
end;

procedure TAtlasSafeModeTests.StateRoundTrips;
var
  mState, mLoaded: TAtlasSafeState;
  mMarker: TAtlasSessionMarker;
begin
  mState := Default(TAtlasSafeState);
  mState.CrashCount := 2;
  mState.LastCrashAt := EncodeDateTime(2026, 10, 14, 9, 30, 0, 0);
  mState.CrashedMarker := Crashed(7, mState.LastCrashAt).ToJson;
  mLoaded := TAtlasSafeState.FromJson(mState.ToJson);
  Assert.AreEqual(2, mLoaded.CrashCount);
  Assert.IsTrue(SameDateTime(mState.LastCrashAt, mLoaded.LastCrashAt));
  Assert.IsTrue(TAtlasSessionMarker.FromJson(mLoaded.CrashedMarker, mMarker));
  Assert.AreEqual(Int64(7), Int64(mMarker.ProcessId));
  mLoaded := TAtlasSafeState.FromJson('kein JSON');
  Assert.AreEqual(0, mLoaded.CrashCount);
end;

procedure TAtlasSafeModeTests.SafeSessionTurnsEveryToggleOff;
var
  mToggles: TArray<TAtlasQuickToggle>;
  mSession: TAtlasToggleSession;
  mEffective, mStored: TAtlasPluginSettings;
begin
  mToggles := TAtlasQuickToggles.Build(TAtlasQuickToggles.PluginCatalog, '');
  mSession := TAtlasSafeMode.SafeSession(mToggles);
  Assert.AreEqual(Integer(Length(mToggles)), Integer(Length(mSession.Overrides)));
  mStored := TAtlasPluginSettings.Defaults;
  mEffective := mSession.Apply(mStored, mToggles);
  // Editor-Zeichnungen, Tippen (Vervollständigung, Hover) und Hintergrundprüfung aus.
  Assert.IsFalse(mEffective.PairColors);
  Assert.IsFalse(mEffective.PairGuides);
  Assert.IsFalse(mEffective.InactiveDim);
  Assert.IsFalse(mEffective.Problems);
  Assert.IsFalse(mEffective.HoverTooltip);
  Assert.IsFalse(mEffective.Enabled);
  Assert.IsFalse(mEffective.CheckOnSave);
  // Atlas auf der Willkommensseite (#753) ist ebenfalls ein Schnellschalter.
  Assert.IsFalse(mEffective.WelcomePage);
  // Grundfunktionen bleiben, gespeicherte Werte unverändert.
  Assert.IsTrue(mEffective.StatusField);
  Assert.IsTrue(mStored.PairColors);
  // Einzeln wieder einschalten (#604).
  mSession.Put('PairColors', True);
  mEffective := mSession.Apply(mStored, mToggles);
  Assert.IsTrue(mEffective.PairColors);
  Assert.IsFalse(mEffective.PairGuides);
end;

procedure TAtlasSafeModeTests.SuggestsChangedThenFaulty;
var
  mToggles: TArray<TAtlasQuickToggle>;
  mMarker: TAtlasSessionMarker;
  mKeys: TArray<string>;
begin
  mToggles := TAtlasQuickToggles.Build(TAtlasQuickToggles.PluginCatalog, '');
  mMarker := TAtlasSessionMarker.Create(1, '1.0.0', Now);
  mMarker.AddFailure('Hover');
  mMarker.AddFailure('Problems');
  mMarker.AddFailure('Problems');
  mKeys := TAtlasSafeMode.Suggest(mToggles, ['VisibleRows', 'PairGuides'], mMarker);
  // Zuerst zuletzt geändert (nur Schnellschalter), dann Fehler: Probleme (2) vor Hover (1).
  // Zum Feature Hover gehören zwei Schalter (DebugHoverValues seit #891), zu Problems drei
  // (Fenster „Atlas-Prüfung“ seit #909, offene Units zuerst seit #1108); bei Gleichstand in Katalogfolge.
  Assert.AreEqual(6, Integer(Length(mKeys)));
  Assert.AreEqual('PairGuides', mKeys[0]);
  Assert.AreEqual('Problems', mKeys[1]);
  Assert.AreEqual('ProblemsWindow', mKeys[2]);
  Assert.AreEqual('ProblemsWindowOpenFirst', mKeys[3]);
  Assert.AreEqual('HoverTooltip', mKeys[4]);
  Assert.AreEqual('DebugHoverValues', mKeys[5]);
  Assert.AreEqual(0, Integer(Length(TAtlasSafeMode.Suggest(mToggles, nil, TAtlasSessionMarker.Create(1, '', 0)))));
  Assert.IsTrue(Length(TAtlasSafeMode.Details(mMarker)) >= 5);
end;

procedure TAtlasSafeModeTests.LogLinesOfCrashedSession;
var
  mLines: TArray<string>;
begin
  mLines := ['2026-10-14 08:00:00.000 alte Sitzung', '2026-10-14 09:00:00.000 Start', 'Stack-Zeile ohne Zeit',
    '2026-10-14 09:05:00.000 Fehler Klammerpaare', '2026-10-14 10:00:00.000 neue Sitzung'];
  mLines := TAtlasSafeMode.LogLinesBetween(mLines, EncodeDateTime(2026, 10, 14, 9, 0, 0, 0),
    EncodeDateTime(2026, 10, 14, 10, 0, 0, 0), 10);
  Assert.AreEqual(3, Integer(Length(mLines)));
  Assert.AreEqual('Stack-Zeile ohne Zeit', mLines[1]);
  mLines := TAtlasSafeMode.LogLinesBetween(['2026-10-14 09:00:00.000 a', '2026-10-14 09:00:01.000 b',
    '2026-10-14 09:00:02.000 c'], EncodeDateTime(2026, 10, 14, 9, 0, 0, 0), 0, 2);
  Assert.AreEqual(2, Integer(Length(mLines)), 'nur die letzten');
  Assert.AreEqual('2026-10-14 09:00:02.000 c', mLines[1]);
end;

procedure TAtlasSafeModeTests.SettingsHistoryRestores;
var
  mHistory, mLoaded: TAtlasSettingsHistory;
  mFirst, mSecond, mThird: TAtlasPluginSettings;
  mKeys: TArray<string>;
begin
  mFirst := TAtlasPluginSettings.Defaults;
  mSecond := mFirst;
  mSecond.PairColors := False;
  mThird := mSecond;
  mThird.VisibleRows := 12;
  mThird.ServerPath := 'X:\Server.exe';
  mHistory := TAtlasSettingsHistory.Create;
  try
    mHistory.Push(mFirst, mFirst, Now, 5);
    Assert.AreEqual(0, Integer(mHistory.Count), 'ohne Änderung kein Stand');
    mHistory.Push(mFirst, mSecond, EncodeDateTime(2026, 10, 14, 8, 0, 0, 0), 5);
    mHistory.Push(mSecond, mThird, EncodeDateTime(2026, 10, 14, 9, 0, 0, 0), 5);
    Assert.AreEqual(2, Integer(mHistory.Count));
    // Neuester zuerst: Stand vor der letzten Änderung.
    Assert.IsFalse(mHistory[0].Settings.PairColors);
    Assert.AreEqual(TAtlasPluginSettings.Defaults.VisibleRows, mHistory[0].Settings.VisibleRows);
    mKeys := mHistory.LastChangedKeys(mThird);
    Assert.AreEqual(2, Integer(Length(mKeys)));
    Assert.AreEqual('VisibleRows', mKeys[0]);
    Assert.AreEqual('ServerPath', mKeys[1]);
    Assert.AreEqual(3, Integer(Length(mHistory.ChangedKeys(1, mThird))));
    mLoaded := TAtlasSettingsHistory.Create;
    try
      Assert.IsTrue(mLoaded.LoadJson(mHistory.ToJson));
      Assert.AreEqual(2, Integer(mLoaded.Count));
      Assert.IsTrue(mLoaded[1].Settings.PairColors);
      Assert.IsTrue(SameDateTime(mHistory[0].ChangedAt, mLoaded[0].ChangedAt));
      Assert.IsFalse(mLoaded.LoadJson('kaputt'), 'keine Liste');
      Assert.AreEqual(0, Integer(mLoaded.Count));
    finally
      mLoaded.Free;
    end;
    // Höchstens AKeep Stände; 0 merkt nichts.
    mHistory.Push(mThird, mFirst, Now, 1);
    Assert.AreEqual(1, Integer(mHistory.Count));
    mHistory.Clear;
    mHistory.Push(mFirst, mSecond, Now, 0);
    Assert.AreEqual(0, Integer(mHistory.Count));
  finally
    mHistory.Free;
  end;
end;

procedure TAtlasSafeModeTests.MarkerFilesFindCrashedSessions;
var
  mFolder: string;
  mOwn, mRunning, mGone: TAtlasSessionMarker;
  mFound: TArray<TAtlasSessionMarker>;
  mState: TAtlasSafeState;
begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'atlas-safemode-' + IntToStr(Random(MaxInt)));
  try
    // Eigene Sitzung, eine laufende zweite IDE und eine abgestürzte.
    mOwn := TAtlasSessionMarker.Create(10, '1.0.0', EncodeDateTime(2026, 10, 14, 12, 0, 0, 0));
    mRunning := TAtlasSessionMarker.Create(20, '1.0.0', EncodeDateTime(2026, 10, 14, 11, 0, 0, 0));
    mGone := Crashed(30, EncodeDateTime(2026, 10, 14, 10, 0, 0, 0));
    TAtlasSessionFiles.WriteMarker(mFolder, mOwn);
    TAtlasSessionFiles.WriteMarker(mFolder, mRunning);
    TAtlasSessionFiles.WriteMarker(mFolder, mGone);
    TFile.WriteAllText(TAtlasSessionFiles.MarkerFile(mFolder, 40), '{kaputt');
    Assert.IsTrue(TFile.Exists(TAtlasSessionFiles.MarkerFile(mFolder, 30)), 'Marke angelegt');
    mFound := TAtlasSessionFiles.TakeCrashed(mFolder, 10,
      function(AProcessId: Cardinal; AStartedAt: TDateTime): Boolean
      begin
        Result := AProcessId = 20;
      end);
    Assert.AreEqual(1, Integer(Length(mFound)));
    Assert.AreEqual(Int64(30), Int64(mFound[0].ProcessId));
    Assert.AreEqual(1, mFound[0].FailureCount('Pairs'));
    // Die abgestürzte und die kaputte Marke sind weg, die laufenden bleiben.
    Assert.IsFalse(TFile.Exists(TAtlasSessionFiles.MarkerFile(mFolder, 30)), 'abgestürzte Marke gelöscht');
    Assert.IsFalse(TFile.Exists(TAtlasSessionFiles.MarkerFile(mFolder, 40)), 'kaputte Marke gelöscht');
    Assert.IsTrue(TFile.Exists(TAtlasSessionFiles.MarkerFile(mFolder, 10)), 'eigene Marke bleibt');
    Assert.IsTrue(TFile.Exists(TAtlasSessionFiles.MarkerFile(mFolder, 20)), 'laufende IDE bleibt');
    // Ein zweiter Start findet nichts mehr; sauberes Ende löscht die eigene Marke.
    mFound := TAtlasSessionFiles.TakeCrashed(mFolder, 10,
      function(AProcessId: Cardinal; AStartedAt: TDateTime): Boolean
      begin
        Result := AProcessId = 20;
      end);
    Assert.AreEqual(0, Integer(Length(mFound)));
    TAtlasSessionFiles.DeleteMarker(mFolder, 10);
    Assert.IsFalse(TFile.Exists(TAtlasSessionFiles.MarkerFile(mFolder, 10)), 'eigene Marke beim Beenden gelöscht');
    // Zustand über die Datei.
    mState := Default(TAtlasSafeState);
    mState.CrashCount := 2;
    TAtlasSessionFiles.WriteState(mFolder, mState);
    mState := TAtlasSessionFiles.ReadState(mFolder);
    Assert.AreEqual(2, mState.CrashCount);
    // Ersetzen in einem Schritt: neuer Stand, keine Reste daneben.
    mState.CrashCount := 3;
    TAtlasSessionFiles.WriteState(mFolder, mState);
    Assert.AreEqual(3, TAtlasSessionFiles.ReadState(mFolder).CrashCount);
    Assert.IsFalse(TFile.Exists(TAtlasSessionFiles.StateFile(mFolder) + '.tmp'), 'keine Zwischendatei');
    Assert.IsFalse(TFile.Exists(TAtlasSessionFiles.StateFile(mFolder) + '.bak'), 'keine Sicherung');
  finally
    if TDirectory.Exists(mFolder) then
    begin
      TDirectory.Delete(mFolder, True);
    end;
  end;
  mState := TAtlasSessionFiles.ReadState(mFolder);
  Assert.AreEqual(0, mState.CrashCount, 'ohne Datei leer');
end;

procedure TAtlasSafeModeTests.NoMarkerSwitchValues;
begin
  Assert.IsTrue(TAtlasSafeMode.IsSwitchOn('1'));
  Assert.IsTrue(TAtlasSafeMode.IsSwitchOn(' TRUE '));
  Assert.IsTrue(TAtlasSafeMode.IsSwitchOn('yes'));
  Assert.IsFalse(TAtlasSafeMode.IsSwitchOn(''));
  Assert.IsFalse(TAtlasSafeMode.IsSwitchOn('0'));
  Assert.IsFalse(TAtlasSafeMode.IsSwitchOn('no'));
  Assert.IsFalse(TAtlasSessionBook.Create('x', 1, '1').Tracked, 'Variable gesetzt: kein Buch');
  Assert.IsTrue(TAtlasSessionBook.Create('x', 1, '').Tracked, 'ohne Variable: Buch');
  Assert.IsTrue(TAtlasSessionBook.Create('x', 1, '0').Tracked, '0: Buch');
end;

function NoneAlive(AProcessId: Cardinal; AStartedAt: TDateTime): Boolean;
begin
  Result := False;
end;

function TempFolder: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'atlas-safemode-' + IntToStr(Random(MaxInt)));
end;

procedure TAtlasSafeModeTests.SessionWithoutMarkerLeavesNoTrace;
var
  mFolder: string;
  mBook: TAtlasSessionBook;
  mState: TAtlasSafeState;
  mFound: TArray<TAtlasSessionMarker>;
  mDecision: TAtlasSafeDecision;
  mNow: TDateTime;
begin
  mFolder := TempFolder;
  mNow := EncodeDateTime(2026, 11, 5, 12, 0, 0, 0);
  try
    // Eine abgewürgte Sitzung mit Buch und ein Zustand mit einem Absturz liegen schon da.
    TAtlasSessionFiles.WriteMarker(mFolder, Crashed(30, IncMinute(mNow, -30)));
    mState := Default(TAtlasSafeState);
    mState.CrashCount := 1;
    mState.LastCrashAt := IncMinute(mNow, -5);
    TAtlasSessionFiles.WriteState(mFolder, mState);
    // Bau-IDE mit ATLAS_NO_SESSION_MARKER=1.
    mBook := TAtlasSessionBook.Create(mFolder, 10, '1');
    mBook.Open(NoneAlive, mState, mFound);
    Assert.AreEqual(0, Integer(Length(mFound)), 'keine fremden Marken ausgewertet');
    mDecision := TAtlasSafeMode.Decide(mState, mFound, mNow, Options, TAtlasStartupKey.None, False);
    Assert.AreEqual<TAtlasSafeLevel>(TAtlasSafeLevel.Normal, mDecision.Level, 'normal gestartet');
    Assert.IsFalse(mDecision.Crashed, 'kein Absturz');
    mBook.SaveState(mState);
    mBook.SaveMarker(TAtlasSessionMarker.Create(10, '1.0.0', mNow));
    Assert.IsFalse(TFile.Exists(TAtlasSessionFiles.MarkerFile(mFolder, 10)), 'keine eigene Marke');
    Assert.IsTrue(TFile.Exists(TAtlasSessionFiles.MarkerFile(mFolder, 30)), 'fremde Marke bleibt liegen');
    Assert.AreEqual(1, TAtlasSessionFiles.ReadState(mFolder).CrashCount, 'Zähler nach dem Start unverändert');
    mBook.Close;
    Assert.AreEqual(1, TAtlasSessionFiles.ReadState(mFolder).CrashCount, 'Zähler nach dem Ende unverändert');
    // Die nächste Sitzung mit Buch sieht den Absturz weiterhin.
    mBook := TAtlasSessionBook.Create(mFolder, 11, '');
    mBook.Open(NoneAlive, mState, mFound);
    Assert.AreEqual(1, Integer(Length(mFound)));
    Assert.AreEqual(Int64(30), Int64(mFound[0].ProcessId));
  finally
    if TDirectory.Exists(mFolder) then
    begin
      TDirectory.Delete(mFolder, True);
    end;
  end;
end;

procedure TAtlasSafeModeTests.TrackedSessionKeepsItsBook;
var
  mFolder: string;
  mBook: TAtlasSessionBook;
  mState: TAtlasSafeState;
  mFound: TArray<TAtlasSessionMarker>;
begin
  mFolder := TempFolder;
  try
    mBook := TAtlasSessionBook.Create(mFolder, 10, '');
    mBook.Open(NoneAlive, mState, mFound);
    Assert.AreEqual(0, Integer(Length(mFound)));
    mState.CrashCount := 2;
    mBook.SaveState(mState);
    mBook.SaveMarker(TAtlasSessionMarker.Create(10, '1.0.0', EncodeDateTime(2026, 11, 5, 12, 0, 0, 0)));
    Assert.IsTrue(TFile.Exists(TAtlasSessionFiles.MarkerFile(mFolder, 10)), 'eigene Marke geschrieben');
    Assert.AreEqual(2, TAtlasSessionFiles.ReadState(mFolder).CrashCount);
    mBook.Close;
    Assert.IsFalse(TFile.Exists(TAtlasSessionFiles.MarkerFile(mFolder, 10)), 'Marke beim Ende gelöscht');
    Assert.AreEqual(0, TAtlasSessionFiles.ReadState(mFolder).CrashCount, 'sauberes Ende setzt zurück');
  finally
    if TDirectory.Exists(mFolder) then
    begin
      TDirectory.Delete(mFolder, True);
    end;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSafeModeTests);

end.
