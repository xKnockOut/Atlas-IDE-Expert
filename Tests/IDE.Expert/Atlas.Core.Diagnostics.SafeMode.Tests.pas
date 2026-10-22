unit Atlas.Core.Diagnostics.SafeMode.Tests;

// Abgesicherter Start (#722): Startmarke anlegen und lesen, Erkennung eines
// Absturzes, Zählung wiederholter Abstürze, Zeitlimit beim Laden, Taste und
// Kommandozeile, Auswahl der Funktionen im abgesicherten Modus, Vorschlag und
// Einstellungsstände zurücksetzen.

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
    procedure SlowStartCountsAsCrash;
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
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.DateUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.History,
  Atlas.Core.Settings.QuickToggles,
  Atlas.Core.Diagnostics.SafeMode;

function Options: TAtlasSafeOptions;
begin
  Result := TAtlasSafeOptions.Create(True, True, TAtlasStartupKey.Shift, 10000);
end;

function Crashed(AProcess: Cardinal; AStartedAt: TDateTime): TAtlasSessionMarker;
begin
  Result := TAtlasSessionMarker.Create(AProcess, '1.0.0', AStartedAt);
  Result.Features := ['PairColors', 'Problems'];
  Result.AddFailure('Pairs');
end;

procedure TAtlasSafeModeTests.MarkerRoundTrips;
var
  Marker, Loaded: TAtlasSessionMarker;
begin
  Marker := TAtlasSessionMarker.Create(4711, '1.2.3', EncodeDateTime(2026, 10, 14, 12, 0, 0, 0));
  Marker.Features := ['PairColors', 'HoverTooltip'];
  Marker.AddFailure('Pairs');
  Marker.AddFailure('pairs');
  Marker.AddFailure('Hover');
  Marker.Loaded := True;
  Marker.LoadMs := 812;
  Marker.Level := TAtlasSafeLevel.Safe;
  Assert.IsTrue(TAtlasSessionMarker.FromJson(Marker.ToJson, Loaded));
  Assert.AreEqual(Int64(4711), Int64(Loaded.ProcessId));
  Assert.AreEqual('1.2.3', Loaded.Version);
  Assert.IsTrue(SameDateTime(Marker.StartedAt, Loaded.StartedAt));
  Assert.IsTrue(Loaded.Loaded);
  Assert.AreEqual(Int64(812), Loaded.LoadMs);
  Assert.IsTrue(Loaded.Level = TAtlasSafeLevel.Safe);
  Assert.AreEqual(2, Integer(Length(Loaded.Features)));
  Assert.AreEqual(2, Loaded.FailureCount('Pairs'));
  Assert.AreEqual(1, Loaded.FailureCount('Hover'));
  Assert.AreEqual(0, Loaded.FailureCount('Problems'));
  Assert.IsFalse(TAtlasSessionMarker.FromJson('kaputt', Loaded));
  Assert.IsFalse(TAtlasSessionMarker.FromJson('{}', Loaded));
end;

procedure TAtlasSafeModeTests.NoMarkerStartsNormal;
var
  State: TAtlasSafeState;
  Decision: TAtlasSafeDecision;
begin
  State := Default(TAtlasSafeState);
  Decision := TAtlasSafeMode.Decide(State, nil, Now, Options, TAtlasStartupKey.None, False);
  Assert.IsTrue(Decision.Level = TAtlasSafeLevel.Normal);
  Assert.IsFalse(Decision.Crashed);
  Assert.IsFalse(Decision.Ask);
  Assert.AreEqual(0, State.CrashCount);
end;

procedure TAtlasSafeModeTests.CrashAsksAndStartsSafe;
var
  State: TAtlasSafeState;
  Decision: TAtlasSafeDecision;
  Start: TDateTime;
  Marker: TAtlasSessionMarker;
begin
  State := Default(TAtlasSafeState);
  Start := EncodeDateTime(2026, 10, 14, 9, 0, 0, 0);
  Decision := TAtlasSafeMode.Decide(State, [Crashed(1, Start - 1 / 24), Crashed(2, Start - 1 / 48)], Start,
    Options, TAtlasStartupKey.None, False);
  Assert.IsTrue(Decision.Crashed);
  Assert.IsTrue(Decision.Ask, 'Rückfrage');
  Assert.IsTrue(Decision.Level = TAtlasSafeLevel.Safe, 'bis zur Antwort abgesichert');
  Assert.IsTrue(Decision.Reason = TAtlasSafeReason.Crash);
  Assert.AreEqual(1, State.CrashCount);
  // Details zeigen die zuletzt gestartete Sitzung.
  Assert.IsTrue(TAtlasSessionMarker.FromJson(State.CrashedMarker, Marker));
  Assert.AreEqual(Int64(2), Int64(Marker.ProcessId));
end;

procedure TAtlasSafeModeTests.RepeatedCrashStartsSafeWithoutAsking;
var
  State: TAtlasSafeState;
  Decision: TAtlasSafeDecision;
  Start: TDateTime;
begin
  State := Default(TAtlasSafeState);
  Start := EncodeDateTime(2026, 10, 14, 9, 0, 0, 0);
  TAtlasSafeMode.Decide(State, [Crashed(1, Start - 1 / 1440)], Start, Options, TAtlasStartupKey.None, False);
  // Zweiter Absturz fünf Minuten später.
  Decision := TAtlasSafeMode.Decide(State, [Crashed(2, Start)], IncMinute(Start, 5), Options,
    TAtlasStartupKey.None, False);
  Assert.AreEqual(2, State.CrashCount);
  Assert.IsTrue(Decision.Level = TAtlasSafeLevel.Safe);
  Assert.IsTrue(Decision.Reason = TAtlasSafeReason.RepeatedCrash);
  Assert.IsFalse(Decision.Ask, 'ohne Rückfrage, nur Meldung');
  // Nach langer Pause gilt der nächste Absturz wieder als erster.
  Decision := TAtlasSafeMode.Decide(State, [Crashed(3, Start)], IncHour(Start, 3), Options,
    TAtlasStartupKey.None, False);
  Assert.AreEqual(1, State.CrashCount);
  Assert.IsTrue(Decision.Reason = TAtlasSafeReason.Crash);
end;

procedure TAtlasSafeModeTests.CleanExitResetsCount;
var
  State: TAtlasSafeState;
  Decision: TAtlasSafeDecision;
  Start: TDateTime;
begin
  State := Default(TAtlasSafeState);
  Start := EncodeDateTime(2026, 10, 14, 9, 0, 0, 0);
  TAtlasSafeMode.Decide(State, [Crashed(1, Start)], Start, Options, TAtlasStartupKey.None, False);
  TAtlasSafeMode.CleanExit(State);
  Assert.AreEqual(0, State.CrashCount);
  Decision := TAtlasSafeMode.Decide(State, [Crashed(2, Start)], IncMinute(Start, 2), Options,
    TAtlasStartupKey.None, False);
  Assert.IsTrue(Decision.Reason = TAtlasSafeReason.Crash, 'nach sauberem Ende nicht „wiederholt“');
end;

procedure TAtlasSafeModeTests.SlowStartCountsAsCrash;
var
  State: TAtlasSafeState;
  Decision: TAtlasSafeDecision;
begin
  State := Default(TAtlasSafeState);
  Assert.IsFalse(TAtlasSafeMode.LoadFinished(State, 9000, Options));
  Assert.IsFalse(State.SlowStart);
  Assert.IsTrue(TAtlasSafeMode.LoadFinished(State, 12000, Options));
  Assert.IsTrue(State.SlowStart);
  Decision := TAtlasSafeMode.Decide(State, nil, Now, Options, TAtlasStartupKey.None, False);
  Assert.IsTrue(Decision.Crashed, 'hängender Start zählt wie ein Absturz');
  Assert.IsTrue(Decision.Ask);
  Assert.IsFalse(State.SlowStart, 'nur einmal');
end;

procedure TAtlasSafeModeTests.KeyAndCommandLineStartMinimal;
var
  State: TAtlasSafeState;
  Decision: TAtlasSafeDecision;
begin
  State := Default(TAtlasSafeState);
  Decision := TAtlasSafeMode.Decide(State, nil, Now, Options, TAtlasStartupKey.Shift, False);
  Assert.IsTrue(Decision.Level = TAtlasSafeLevel.Minimal);
  Assert.IsTrue(Decision.Reason = TAtlasSafeReason.StartupKey);
  Decision := TAtlasSafeMode.Decide(State, nil, Now, Options, TAtlasStartupKey.Ctrl, False);
  Assert.IsTrue(Decision.Level = TAtlasSafeLevel.Normal, 'andere Taste als eingestellt');
  Decision := TAtlasSafeMode.Decide(State, nil, Now, Options, TAtlasStartupKey.None, True);
  Assert.IsTrue(Decision.Level = TAtlasSafeLevel.Minimal);
  Assert.IsTrue(Decision.Reason = TAtlasSafeReason.Forced);
  Assert.IsTrue(TAtlasSafeMode.IsForced('1', nil));
  Assert.IsTrue(TAtlasSafeMode.IsForced('', ['bds.exe', '-pDelphi', '-AtlasSafeMode']));
  Assert.IsTrue(TAtlasSafeMode.IsForced('', ['/atlassafemode']));
  Assert.IsFalse(TAtlasSafeMode.IsForced('0', ['-np']));
  Assert.IsTrue(TAtlasSafeMode.KeyOf('ctrl') = TAtlasStartupKey.Ctrl);
  Assert.IsTrue(TAtlasSafeMode.KeyOf('none') = TAtlasStartupKey.None);
  Assert.IsTrue(TAtlasSafeMode.KeyOf('quatsch') = TAtlasStartupKey.Shift);
  Assert.AreEqual('ctrl', TAtlasSafeMode.KeyText(TAtlasStartupKey.Ctrl));
end;

procedure TAtlasSafeModeTests.SwitchedOffNeverAsks;
var
  State: TAtlasSafeState;
  Decision: TAtlasSafeDecision;
  Off: TAtlasSafeOptions;
  Start: TDateTime;
begin
  // safeMode.askAfterCrash und autoAfterRepeatedCrash aus, startupKey none: abgeschaltet.
  Off := TAtlasSafeOptions.Create(False, False, TAtlasStartupKey.None, 10000);
  State := Default(TAtlasSafeState);
  Start := EncodeDateTime(2026, 10, 14, 9, 0, 0, 0);
  Decision := TAtlasSafeMode.Decide(State, [Crashed(1, Start)], Start, Off, TAtlasStartupKey.Shift, False);
  Assert.IsTrue(Decision.Level = TAtlasSafeLevel.Normal);
  Assert.IsFalse(Decision.Ask);
  Decision := TAtlasSafeMode.Decide(State, [Crashed(2, Start)], IncMinute(Start, 1), Off,
    TAtlasStartupKey.Shift, False);
  Assert.IsTrue(Decision.Level = TAtlasSafeLevel.Normal, 'auch nach wiederholtem Absturz');
end;

procedure TAtlasSafeModeTests.StateRoundTrips;
var
  State, Loaded: TAtlasSafeState;
  Marker: TAtlasSessionMarker;
begin
  State := Default(TAtlasSafeState);
  State.CrashCount := 2;
  State.LastCrashAt := EncodeDateTime(2026, 10, 14, 9, 30, 0, 0);
  State.SlowStart := True;
  State.CrashedMarker := Crashed(7, State.LastCrashAt).ToJson;
  Loaded := TAtlasSafeState.FromJson(State.ToJson);
  Assert.AreEqual(2, Loaded.CrashCount);
  Assert.IsTrue(SameDateTime(State.LastCrashAt, Loaded.LastCrashAt));
  Assert.IsTrue(Loaded.SlowStart);
  Assert.IsTrue(TAtlasSessionMarker.FromJson(Loaded.CrashedMarker, Marker));
  Assert.AreEqual(Int64(7), Int64(Marker.ProcessId));
  Loaded := TAtlasSafeState.FromJson('kein JSON');
  Assert.AreEqual(0, Loaded.CrashCount);
end;

procedure TAtlasSafeModeTests.SafeSessionTurnsEveryToggleOff;
var
  Toggles: TArray<TAtlasQuickToggle>;
  Session: TAtlasToggleSession;
  Effective, Stored: TAtlasPluginSettings;
begin
  Toggles := TAtlasQuickToggles.Build(TAtlasQuickToggles.PluginCatalog, '');
  Session := TAtlasSafeMode.SafeSession(Toggles);
  Assert.AreEqual(Integer(Length(Toggles)), Integer(Length(Session.Overrides)));
  Stored := TAtlasPluginSettings.Defaults;
  Effective := Session.Apply(Stored, Toggles);
  // Editor-Zeichnungen, Tippen (Vervollständigung, Hover) und Hintergrundprüfung aus.
  Assert.IsFalse(Effective.PairColors);
  Assert.IsFalse(Effective.PairGuides);
  Assert.IsFalse(Effective.InactiveDim);
  Assert.IsFalse(Effective.Problems);
  Assert.IsFalse(Effective.HoverTooltip);
  Assert.IsFalse(Effective.Enabled);
  Assert.IsFalse(Effective.CheckOnSave);
  // Atlas auf der Willkommensseite (#753) ist ebenfalls ein Schnellschalter.
  Assert.IsFalse(Effective.WelcomePage);
  // Grundfunktionen bleiben, gespeicherte Werte unverändert.
  Assert.IsTrue(Effective.StatusField);
  Assert.IsTrue(Stored.PairColors);
  // Einzeln wieder einschalten (#604).
  Session.Put('PairColors', True);
  Effective := Session.Apply(Stored, Toggles);
  Assert.IsTrue(Effective.PairColors);
  Assert.IsFalse(Effective.PairGuides);
end;

procedure TAtlasSafeModeTests.SuggestsChangedThenFaulty;
var
  Toggles: TArray<TAtlasQuickToggle>;
  Marker: TAtlasSessionMarker;
  Keys: TArray<string>;
begin
  Toggles := TAtlasQuickToggles.Build(TAtlasQuickToggles.PluginCatalog, '');
  Marker := TAtlasSessionMarker.Create(1, '1.0.0', Now);
  Marker.AddFailure('Hover');
  Marker.AddFailure('Problems');
  Marker.AddFailure('Problems');
  Keys := TAtlasSafeMode.Suggest(Toggles, ['VisibleRows', 'PairGuides'], Marker);
  // Zuerst zuletzt geändert (nur Schnellschalter), dann Fehler: Probleme (2) vor Hover (1).
  // Zum Feature Hover gehören zwei Schalter (DebugHoverValues seit #891), bei Gleichstand in Katalogfolge.
  Assert.AreEqual(4, Integer(Length(Keys)));
  Assert.AreEqual('PairGuides', Keys[0]);
  Assert.AreEqual('Problems', Keys[1]);
  Assert.AreEqual('HoverTooltip', Keys[2]);
  Assert.AreEqual('DebugHoverValues', Keys[3]);
  Assert.AreEqual(0, Integer(Length(TAtlasSafeMode.Suggest(Toggles, nil, TAtlasSessionMarker.Create(1, '', 0)))));
  Assert.IsTrue(Length(TAtlasSafeMode.Details(Marker)) >= 5);
end;

procedure TAtlasSafeModeTests.LogLinesOfCrashedSession;
var
  Lines: TArray<string>;
begin
  Lines := ['2026-10-14 08:00:00.000 alte Sitzung', '2026-10-14 09:00:00.000 Start', 'Stack-Zeile ohne Zeit',
    '2026-10-14 09:05:00.000 Fehler Klammerpaare', '2026-10-14 10:00:00.000 neue Sitzung'];
  Lines := TAtlasSafeMode.LogLinesBetween(Lines, EncodeDateTime(2026, 10, 14, 9, 0, 0, 0),
    EncodeDateTime(2026, 10, 14, 10, 0, 0, 0), 10);
  Assert.AreEqual(3, Integer(Length(Lines)));
  Assert.AreEqual('Stack-Zeile ohne Zeit', Lines[1]);
  Lines := TAtlasSafeMode.LogLinesBetween(['2026-10-14 09:00:00.000 a', '2026-10-14 09:00:01.000 b',
    '2026-10-14 09:00:02.000 c'], EncodeDateTime(2026, 10, 14, 9, 0, 0, 0), 0, 2);
  Assert.AreEqual(2, Integer(Length(Lines)), 'nur die letzten');
  Assert.AreEqual('2026-10-14 09:00:02.000 c', Lines[1]);
end;

procedure TAtlasSafeModeTests.SettingsHistoryRestores;
var
  History, Loaded: TAtlasSettingsHistory;
  First, Second, Third: TAtlasPluginSettings;
  Keys: TArray<string>;
begin
  First := TAtlasPluginSettings.Defaults;
  Second := First;
  Second.PairColors := False;
  Third := Second;
  Third.VisibleRows := 12;
  Third.ServerPath := 'X:\Server.exe';
  History := TAtlasSettingsHistory.Create;
  try
    History.Push(First, First, Now, 5);
    Assert.AreEqual(0, Integer(History.Count), 'ohne Änderung kein Stand');
    History.Push(First, Second, EncodeDateTime(2026, 10, 14, 8, 0, 0, 0), 5);
    History.Push(Second, Third, EncodeDateTime(2026, 10, 14, 9, 0, 0, 0), 5);
    Assert.AreEqual(2, Integer(History.Count));
    // Neuester zuerst: Stand vor der letzten Änderung.
    Assert.IsFalse(History[0].Settings.PairColors);
    Assert.AreEqual(TAtlasPluginSettings.Defaults.VisibleRows, History[0].Settings.VisibleRows);
    Keys := History.LastChangedKeys(Third);
    Assert.AreEqual(2, Integer(Length(Keys)));
    Assert.AreEqual('VisibleRows', Keys[0]);
    Assert.AreEqual('ServerPath', Keys[1]);
    Assert.AreEqual(3, Integer(Length(History.ChangedKeys(1, Third))));
    Loaded := TAtlasSettingsHistory.Create;
    try
      Assert.IsTrue(Loaded.LoadJson(History.ToJson));
      Assert.AreEqual(2, Integer(Loaded.Count));
      Assert.IsTrue(Loaded[1].Settings.PairColors);
      Assert.IsTrue(SameDateTime(History[0].ChangedAt, Loaded[0].ChangedAt));
      Assert.IsFalse(Loaded.LoadJson('kaputt'), 'keine Liste');
      Assert.AreEqual(0, Integer(Loaded.Count));
    finally
      Loaded.Free;
    end;
    // Höchstens AKeep Stände; 0 merkt nichts.
    History.Push(Third, First, Now, 1);
    Assert.AreEqual(1, Integer(History.Count));
    History.Clear;
    History.Push(First, Second, Now, 0);
    Assert.AreEqual(0, Integer(History.Count));
  finally
    History.Free;
  end;
end;

procedure TAtlasSafeModeTests.MarkerFilesFindCrashedSessions;
var
  Folder: string;
  Own, Running, Gone: TAtlasSessionMarker;
  Found: TArray<TAtlasSessionMarker>;
  State: TAtlasSafeState;
begin
  Folder := TPath.Combine(TPath.GetTempPath, 'atlas-safemode-' + IntToStr(Random(MaxInt)));
  try
    // Eigene Sitzung, eine laufende zweite IDE und eine abgestürzte.
    Own := TAtlasSessionMarker.Create(10, '1.0.0', EncodeDateTime(2026, 10, 14, 12, 0, 0, 0));
    Running := TAtlasSessionMarker.Create(20, '1.0.0', EncodeDateTime(2026, 10, 14, 11, 0, 0, 0));
    Gone := Crashed(30, EncodeDateTime(2026, 10, 14, 10, 0, 0, 0));
    TAtlasSessionFiles.WriteMarker(Folder, Own);
    TAtlasSessionFiles.WriteMarker(Folder, Running);
    TAtlasSessionFiles.WriteMarker(Folder, Gone);
    TFile.WriteAllText(TAtlasSessionFiles.MarkerFile(Folder, 40), '{kaputt');
    Assert.IsTrue(TFile.Exists(TAtlasSessionFiles.MarkerFile(Folder, 30)), 'Marke angelegt');
    Found := TAtlasSessionFiles.TakeCrashed(Folder, 10,
      function(AProcessId: Cardinal; AStartedAt: TDateTime): Boolean
      begin
        Result := AProcessId = 20;
      end);
    Assert.AreEqual(1, Integer(Length(Found)));
    Assert.AreEqual(Int64(30), Int64(Found[0].ProcessId));
    Assert.AreEqual(1, Found[0].FailureCount('Pairs'));
    // Die abgestürzte und die kaputte Marke sind weg, die laufenden bleiben.
    Assert.IsFalse(TFile.Exists(TAtlasSessionFiles.MarkerFile(Folder, 30)), 'abgestürzte Marke gelöscht');
    Assert.IsFalse(TFile.Exists(TAtlasSessionFiles.MarkerFile(Folder, 40)), 'kaputte Marke gelöscht');
    Assert.IsTrue(TFile.Exists(TAtlasSessionFiles.MarkerFile(Folder, 10)), 'eigene Marke bleibt');
    Assert.IsTrue(TFile.Exists(TAtlasSessionFiles.MarkerFile(Folder, 20)), 'laufende IDE bleibt');
    // Ein zweiter Start findet nichts mehr; sauberes Ende löscht die eigene Marke.
    Found := TAtlasSessionFiles.TakeCrashed(Folder, 10,
      function(AProcessId: Cardinal; AStartedAt: TDateTime): Boolean
      begin
        Result := AProcessId = 20;
      end);
    Assert.AreEqual(0, Integer(Length(Found)));
    TAtlasSessionFiles.DeleteMarker(Folder, 10);
    Assert.IsFalse(TFile.Exists(TAtlasSessionFiles.MarkerFile(Folder, 10)), 'eigene Marke beim Beenden gelöscht');
    // Zustand über die Datei.
    State := Default(TAtlasSafeState);
    State.CrashCount := 2;
    State.SlowStart := True;
    TAtlasSessionFiles.WriteState(Folder, State);
    State := TAtlasSessionFiles.ReadState(Folder);
    Assert.AreEqual(2, State.CrashCount);
    Assert.IsTrue(State.SlowStart);
    // Ersetzen in einem Schritt (Bericht N3): neuer Stand, keine Reste daneben.
    State.CrashCount := 3;
    TAtlasSessionFiles.WriteState(Folder, State);
    Assert.AreEqual(3, TAtlasSessionFiles.ReadState(Folder).CrashCount);
    Assert.IsFalse(TFile.Exists(TAtlasSessionFiles.StateFile(Folder) + '.tmp'), 'keine Zwischendatei');
    Assert.IsFalse(TFile.Exists(TAtlasSessionFiles.StateFile(Folder) + '.bak'), 'keine Sicherung');
  finally
    if TDirectory.Exists(Folder) then
      TDirectory.Delete(Folder, True);
  end;
  State := TAtlasSessionFiles.ReadState(Folder);
  Assert.AreEqual(0, State.CrashCount, 'ohne Datei leer');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSafeModeTests);

end.
