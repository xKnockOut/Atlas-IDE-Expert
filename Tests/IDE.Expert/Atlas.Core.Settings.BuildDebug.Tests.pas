unit Atlas.Core.Settings.BuildDebug.Tests;

// Tests der Einstellungen für Debugger und Build.

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Einstellungen von Debugger und Build.</summary>
  [TestFixture]
  TAtlasBuildDebugSettingsTests = class
  public
    [Test]
    procedure DebugVisualizerOptions;
    [Test]
    procedure DebugDisplayRuleOptions;
    [Test]
    procedure DebugStepIntoTargetOptions;
    [Test]
    procedure DebugBreakOnNextEventOptions;
    [Test]
    procedure DebugBreakpointOptions;
    [Test]
    procedure DebugStepFilterOptions;
    /// <summary>Release-Build-Wächter (#533): build.releaseGuard, build.gate, build.releaseConfigs und
    /// build.releaseChecks mit Vorgaben, Normalisieren, Speichern und Laden.</summary>
    [Test]
    procedure ReleaseGuardOptions;
    [Test]
    procedure TasksOptions;
    /// <summary>Prüfung vor dem Compile (#529): build.gateTimeoutMs mit Vorgabe, Grenzen, Speichern und Laden.
    /// </summary>
    [Test]
    procedure BuildGateTimeoutOption;
    /// <summary>Schranke für Hinweise und Warnungen (#530): build.summary und build.warningsAsErrors mit Vorgaben,
    /// Normalisieren, Speichern und Laden.</summary>
    [Test]
    procedure BuildSummaryOptions;
    /// <summary>Beim Öffnen bauen: build.onOpen, build.onOpenKind, build.onOpenScope, build.onOpenDelayMs und
    /// build.onOpenExclude mit Vorgaben, Normalisieren, Speichern und Laden.</summary>
    [Test]
    procedure BuildOnOpenOptions;
    /// <summary>Laufendes Programm vor dem Build beenden (#551): build.stopRunningProgram mit Vorgabe ask,
    /// Normalisieren, Speichern und Laden.</summary>
    [Test]
    procedure StopRunningProgramOption;
    /// <summary>Ereignisprotokoll (#580): debug.eventLog an, debug.eventLogColors mit Vorgabe, Speichern und Laden.
    /// </summary>
    [Test]
    procedure EventLogOptions;
    /// <summary>Logpunkte (#583): an, Präfix getrimmt, gespeichert und geladen.</summary>
    [Test]
    procedure LogpointOptions;
    /// <summary>Fenster „Kein Quelltext“ (#869): an, Liste getrimmt, gespeichert und geladen.</summary>
    [Test]
    procedure NoSourceOptions;
    /// <summary>Neu starten (#872): an, Haltepunkte wieder einschalten aus, gespeichert und geladen.</summary>
    [Test]
    procedure RestartOptions;
    /// <summary>Erneut anhängen (#2171): an, Umschalt+Alt+P, 100 ms; Abstand begrenzt, gespeichert und geladen.
    /// </summary>
    [Test]
    procedure ReattachOptions;
    /// <summary>Startverbünde (#867): an, gespeichert und geladen.</summary>
    [Test]
    procedure LaunchGroupOptions;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tasks.Definitions,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Plugin.Debug,
  Atlas.Core.Settings.TestSupport;

procedure TAtlasBuildDebugSettingsTests.ReleaseGuardOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.ReleaseGuard, 'Release-Wächter standardmäßig an');
  Assert.AreEqual('off', mSettings.BuildGate, 'build.gate standardmäßig off (#529)');
  Assert.AreEqual('Release', mSettings.ReleaseConfigs);
  Assert.AreEqual('debugDefine,debugInfo=off,stackFrames=off,assertions=off,rangeChecks=off,overflowChecks=off,' +
    'memoryLeaks,versionInfo,outputFolder', mSettings.ReleaseChecks, 'alle Prüfungen an, Sollwerte aus');
  // Leeres Speicher-Objekt: Vorgaben.
  mStore := TMemoryStore.Create;
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.AreEqual(mSettings.ReleaseChecks, mLoaded.ReleaseChecks);
  // Normalisieren: unbekannter Modus = off, Liste ohne Doppelte, Prüfungen vollständig in fester Reihenfolge.
  mSettings.BuildGate := 'BLOCK';
  mSettings.ReleaseConfigs := 'Release; Ship,, ship';
  mSettings.ReleaseChecks := '-assertions, rangeChecks=on, quatsch';
  mSettings.Normalize;
  Assert.AreEqual('block', mSettings.BuildGate);
  Assert.AreEqual('Release, Ship', mSettings.ReleaseConfigs);
  Assert.AreEqual('debugDefine,debugInfo=off,stackFrames=off,-assertions=off,rangeChecks=on,overflowChecks=off,' +
    'memoryLeaks,versionInfo,outputFolder', mSettings.ReleaseChecks);
  mSettings.BuildGate := 'streng';
  mSettings.Normalize;
  Assert.AreEqual('off', mSettings.BuildGate);
  // Speichern und Laden.
  mSettings.ReleaseGuard := False;
  mSettings.BuildGate := 'warn';
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.ReleaseGuard, 'abschaltbar');
  Assert.AreEqual('warn', mLoaded.BuildGate);
  Assert.AreEqual('Release, Ship', mLoaded.ReleaseConfigs);
  Assert.AreEqual(mSettings.ReleaseChecks, mLoaded.ReleaseChecks);
end;
procedure TAtlasBuildDebugSettingsTests.StopRunningProgramOption;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('ask', mSettings.BuildStopRunningProgram, 'standardmäßig Rückfrage');
  mSettings.BuildStopRunningProgram := ' Always ';
  mSettings.Normalize;
  Assert.AreEqual('always', mSettings.BuildStopRunningProgram);
  mSettings.BuildStopRunningProgram := 'immer';
  mSettings.Normalize;
  Assert.AreEqual('ask', mSettings.BuildStopRunningProgram, 'Unbekanntes = ask');
  mSettings.BuildStopRunningProgram := 'never';
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.AreEqual('never', mLoaded.BuildStopRunningProgram);
end;

procedure TAtlasBuildDebugSettingsTests.EventLogOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.DebugEventLog, 'standardmäßig an');
  Assert.AreEqual(cDefaultEventLogColors, mSettings.DebugEventLogColors);
  mSettings.DebugEventLog := False;
  mSettings.DebugEventLogColors := ' [X]=#00FF00 ';
  mSettings.Normalize;
  Assert.AreEqual('[X]=#00FF00', mSettings.DebugEventLogColors);
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.DebugEventLog);
  Assert.AreEqual('[X]=#00FF00', mLoaded.DebugEventLogColors);
end;

procedure TAtlasBuildDebugSettingsTests.LogpointOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.DebugLogpoints, 'standardmäßig an');
  Assert.AreEqual(cDefaultLogpointPrefix, mSettings.DebugLogpointPrefix);
  mSettings.DebugLogpoints := False;
  mSettings.DebugLogpointPrefix := ' >> ';
  mSettings.Normalize;
  Assert.AreEqual('>>', mSettings.DebugLogpointPrefix);
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.DebugLogpoints);
  Assert.AreEqual('>>', mLoaded.DebugLogpointPrefix);
end;

procedure TAtlasBuildDebugSettingsTests.NoSourceOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.DebugNoSourcePage, 'standardmäßig an');
  Assert.AreEqual('', mSettings.DebugNoSourceIgnoredUnits);
  mSettings.DebugNoSourcePage := False;
  mSettings.DebugNoSourceIgnoredUnits := ' Vcl.Forms; System.SysUtils ';
  mSettings.Normalize;
  Assert.AreEqual('Vcl.Forms; System.SysUtils', mSettings.DebugNoSourceIgnoredUnits);
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.DebugNoSourcePage);
  Assert.AreEqual('Vcl.Forms; System.SysUtils', mLoaded.DebugNoSourceIgnoredUnits);
end;

procedure TAtlasBuildDebugSettingsTests.RestartOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.DebugRestart, 'standardmäßig an');
  Assert.IsFalse(mSettings.DebugRestartReenableBreakpoints, 'standardmäßig aus');
  mSettings.DebugRestart := False;
  mSettings.DebugRestartReenableBreakpoints := True;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.DebugRestart);
  Assert.IsTrue(mLoaded.DebugRestartReenableBreakpoints);
end;

procedure TAtlasBuildDebugSettingsTests.ReattachOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.DebugReattach, 'standardmäßig an');
  Assert.AreEqual(Integer($A050), mSettings.DebugReattachKey, 'Umschalt+Alt+P');
  Assert.AreEqual(Integer(100), mSettings.DebugReattachWaitIntervalMs);
  mSettings.DebugReattach := False;
  mSettings.DebugReattachKey := 0;
  mSettings.DebugReattachWaitIntervalMs := 5000;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.DebugReattach);
  Assert.AreEqual(Integer(0), mLoaded.DebugReattachKey);
  Assert.AreEqual(Integer(2000), mLoaded.DebugReattachWaitIntervalMs, 'höchstens 2000 ms');
end;

procedure TAtlasBuildDebugSettingsTests.LaunchGroupOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.DebugLaunchGroups, 'standardmäßig an');
  mSettings.DebugLaunchGroups := False;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.DebugLaunchGroups);
end;

procedure TAtlasBuildDebugSettingsTests.TasksOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
  mMode: TAtlasTaskBeforeBuild;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.TasksEnabled, 'tasks.enabled standardmäßig an (#900)');
  Assert.IsTrue(mSettings.TasksProblemsFromOutput);
  Assert.AreEqual('off', mSettings.TasksBeforeBuild);
  Assert.IsTrue(mSettings.TasksSaveBeforeRun);
  Assert.IsFalse(mSettings.TasksRunChecksParallel);
  Assert.IsFalse(mSettings.TasksOnlyFindings);
  // Normalisieren: Groß-/Kleinschreibung egal, Unbekanntes = off.
  mSettings.TasksBeforeBuild := ' Block ';
  mSettings.Normalize;
  Assert.AreEqual('block', mSettings.TasksBeforeBuild);
  mSettings.TasksBeforeBuild := 'immer';
  mSettings.Normalize;
  Assert.AreEqual('off', mSettings.TasksBeforeBuild);
  // Die Einstellungen kennen die Projektaufgaben nicht: dieselben Werte wie dort.
  for mMode := Low(TAtlasTaskBeforeBuild) to High(TAtlasTaskBeforeBuild) do
  begin
    mSettings.TasksBeforeBuild := UpperCase(TAtlasTasks.cBeforeBuildNames[mMode]);
    mSettings.Normalize;
    Assert.AreEqual(TAtlasTasks.cBeforeBuildNames[mMode], mSettings.TasksBeforeBuild);
  end;
  // Speichern und Laden, jede Einstellung abweichend von der Vorgabe.
  mSettings.TasksEnabled := False;
  mSettings.TasksProblemsFromOutput := False;
  mSettings.TasksBeforeBuild := 'warn';
  mSettings.TasksSaveBeforeRun := False;
  mSettings.TasksRunChecksParallel := True;
  mSettings.TasksOnlyFindings := True;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.TasksEnabled, 'abschaltbar');
  Assert.IsFalse(mLoaded.TasksProblemsFromOutput);
  Assert.AreEqual('warn', mLoaded.TasksBeforeBuild);
  Assert.IsFalse(mLoaded.TasksSaveBeforeRun);
  Assert.IsTrue(mLoaded.TasksRunChecksParallel);
  Assert.IsTrue(mLoaded.TasksOnlyFindings);
end;
procedure TAtlasBuildDebugSettingsTests.BuildGateTimeoutOption;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual(300, mSettings.BuildGateTimeoutMs, 'Vorgabe 300 ms');
  mSettings.BuildGateTimeoutMs := 1;
  mSettings.Normalize;
  Assert.AreEqual(50, mSettings.BuildGateTimeoutMs, 'untere Grenze');
  mSettings.BuildGateTimeoutMs := 100000;
  mSettings.Normalize;
  Assert.AreEqual(10000, mSettings.BuildGateTimeoutMs, 'obere Grenze');
  mSettings.BuildGateTimeoutMs := 750;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.AreEqual(750, mLoaded.BuildGateTimeoutMs);
end;
procedure TAtlasBuildDebugSettingsTests.BuildSummaryOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.BuildSummary, 'Zusammenfassung standardmäßig an');
  Assert.AreEqual('', mSettings.BuildWarningsAsErrors);
  mSettings.BuildSummary := False;
  mSettings.BuildWarningsAsErrors := 'w1035; H2164 x123 W1035';
  mSettings.Normalize;
  Assert.AreEqual('W1035, H2164', mSettings.BuildWarningsAsErrors, 'groß, ohne Doppelte und Ungültiges');
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.BuildSummary);
  Assert.AreEqual('W1035, H2164', mLoaded.BuildWarningsAsErrors);
end;
procedure TAtlasBuildDebugSettingsTests.BuildOnOpenOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsFalse(mSettings.BuildOnOpen, 'standardmäßig aus');
  Assert.AreEqual('make', mSettings.BuildOnOpenKind);
  Assert.AreEqual('all', mSettings.BuildOnOpenScope);
  Assert.AreEqual(3000, mSettings.BuildOnOpenDelayMs);
  Assert.AreEqual('', mSettings.BuildOnOpenExclude);
  Assert.AreEqual('', mSettings.BuildOnOpenConfig, 'wie im Projekt (#1293)');
  Assert.AreEqual('', mSettings.BuildOnOpenPlatform, 'wie im Projekt (#1293)');
  // Normalisieren: unbekannte Art = make, unbekannter Umfang = all, Wartezeit in den Grenzen, Liste ohne Endung
  // und Doppelte.
  mSettings.BuildOnOpenKind := 'BUILD';
  mSettings.BuildOnOpenScope := 'Active';
  mSettings.BuildOnOpenDelayMs := 10;
  mSettings.BuildOnOpenExclude := ' Atlas.IDE.Expert.dproj; atlas.ide.expert,, Demo ';
  mSettings.BuildOnOpenConfig := ' Debug ';
  mSettings.BuildOnOpenPlatform := ' Win64 ';
  mSettings.Normalize;
  Assert.AreEqual('Debug', mSettings.BuildOnOpenConfig);
  Assert.AreEqual('Win64', mSettings.BuildOnOpenPlatform);
  Assert.AreEqual('build', mSettings.BuildOnOpenKind);
  Assert.AreEqual('active', mSettings.BuildOnOpenScope);
  Assert.AreEqual(500, mSettings.BuildOnOpenDelayMs);
  Assert.AreEqual('Atlas.IDE.Expert, Demo', mSettings.BuildOnOpenExclude);
  mSettings.BuildOnOpenKind := 'erzeugen';
  mSettings.BuildOnOpenScope := 'keins';
  mSettings.BuildOnOpenDelayMs := 999999;
  mSettings.Normalize;
  Assert.AreEqual('make', mSettings.BuildOnOpenKind);
  Assert.AreEqual('all', mSettings.BuildOnOpenScope);
  Assert.AreEqual(60000, mSettings.BuildOnOpenDelayMs);
  // Speichern und Laden.
  mSettings.BuildOnOpen := True;
  mSettings.BuildOnOpenKind := 'check';
  mSettings.BuildOnOpenScope := 'active';
  mSettings.BuildOnOpenDelayMs := 5000;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsTrue(mLoaded.BuildOnOpen);
  Assert.AreEqual('check', mLoaded.BuildOnOpenKind);
  Assert.AreEqual('active', mLoaded.BuildOnOpenScope);
  Assert.AreEqual(5000, mLoaded.BuildOnOpenDelayMs);
  Assert.AreEqual('Atlas.IDE.Expert, Demo', mLoaded.BuildOnOpenExclude);
  Assert.AreEqual('Debug', mLoaded.BuildOnOpenConfig);
  Assert.AreEqual('Win64', mLoaded.BuildOnOpenPlatform);
end;
procedure TAtlasBuildDebugSettingsTests.DebugDisplayRuleOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  // #854: an, Aufrufe aus; beide überleben Speichern und Laden.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.DebugDisplayRules);
  Assert.IsFalse(mSettings.DebugDisplayRulesAllowCalls);
  mSettings.DebugDisplayRules := False;
  mSettings.DebugDisplayRulesAllowCalls := True;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  mLoaded.Normalize;
  Assert.IsFalse(mLoaded.DebugDisplayRules);
  Assert.IsTrue(mLoaded.DebugDisplayRulesAllowCalls);
end;
procedure TAtlasBuildDebugSettingsTests.DebugStepIntoTargetOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  // #836: an mit Strg+Alt+F7; Schalter und Taste überleben Speichern und Laden, 0 = keine Taste.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.DebugStepIntoTarget);
  Assert.AreEqual($C076, mSettings.DebugStepIntoTargetKey);
  mSettings.DebugStepIntoTarget := False;
  mSettings.DebugStepIntoTargetKey := 0;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  mLoaded.Normalize;
  Assert.IsFalse(mLoaded.DebugStepIntoTarget);
  Assert.AreEqual(0, mLoaded.DebugStepIntoTargetKey);
  mLoaded.DebugStepIntoTargetKey := -5;
  mLoaded.Normalize;
  Assert.AreEqual(0, mLoaded.DebugStepIntoTargetKey);
end;
procedure TAtlasBuildDebugSettingsTests.DebugBreakOnNextEventOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  // #856: an, ausgenommen OnPaint, OnMouseMove und OnUpdate; die Liste wird beim Normalisieren bereinigt.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.DebugBreakOnNextEvent);
  Assert.AreEqual('OnPaint, OnMouseMove, OnUpdate', mSettings.DebugBreakOnNextEventExcluded);
  mSettings.DebugBreakOnNextEvent := False;
  mSettings.DebugBreakOnNextEventExcluded := 'OnPaint, OnResize';
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  mLoaded.Normalize;
  Assert.IsFalse(mLoaded.DebugBreakOnNextEvent);
  Assert.AreEqual('OnPaint, OnResize', mLoaded.DebugBreakOnNextEventExcluded);
  mLoaded.DebugBreakOnNextEventExcluded := ' OnPaint ;; OnResize,';
  mLoaded.Normalize;
  Assert.AreEqual('OnPaint, OnResize', mLoaded.DebugBreakOnNextEventExcluded);
end;
procedure TAtlasBuildDebugSettingsTests.DebugBreakpointOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  // #577: Haltepunkte vor dem Start prüfen ist an; der Wert überlebt Speichern und Laden.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.DebugCheckBreakpoints);
  mSettings.DebugCheckBreakpoints := False;
  // #586: Haltepunkt-Satz mit dem Branch wechseln ist an.
  Assert.IsTrue(mSettings.DebugBreakpointSetPerBranch);
  mSettings.DebugBreakpointSetPerBranch := False;
  // #851: Bis hier ausführen per Klick ist an.
  Assert.IsTrue(mSettings.DebugRunToClick);
  mSettings.DebugRunToClick := False;
  // #863: Haltepunktfenster ist an; der Wert überlebt Speichern und Laden.
  Assert.IsTrue(mSettings.DebugBreakpointsWindow);
  mSettings.DebugBreakpointsWindow := False;
  // #841: Haltepunkte nachziehen ist an.
  Assert.IsTrue(mSettings.DebugBreakpointAnchors);
  mSettings.DebugBreakpointAnchors := False;
  // #864: Haltepunkt-Regeln sind an.
  Assert.IsTrue(mSettings.DebugBreakpointRules);
  mSettings.DebugBreakpointRules := False;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.DebugCheckBreakpoints);
  // #855: Haltepunkte auf Methoden nach Muster ist an und überlebt Speichern und Laden ebenso.
  Assert.IsTrue(TAtlasPluginSettings.Defaults.DebugMethodBreakpoints);
  mSettings.DebugMethodBreakpoints := False;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.DebugMethodBreakpoints);
  // #857: Haltepunkt nur für ein Objekt ist an; der Wert überlebt Speichern und Laden.
  Assert.IsTrue(mSettings.DebugInstanceBreakpoints);
  mSettings.DebugInstanceBreakpoints := False;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.DebugInstanceBreakpoints);
  // #584: Anhalten, wenn sich ein Feld ändert, ist an; der Wert überlebt Speichern und Laden.
  Assert.IsTrue(mSettings.DebugDataBreakpoints);
  mSettings.DebugDataBreakpoints := False;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.DebugDataBreakpoints);
  Assert.IsFalse(mLoaded.DebugBreakpointSetPerBranch);
  Assert.IsFalse(mLoaded.DebugRunToClick);
  Assert.IsFalse(mLoaded.DebugBreakpointsWindow);
  Assert.IsFalse(mLoaded.DebugBreakpointAnchors);
  Assert.IsFalse(mLoaded.DebugBreakpointRules);
end;
procedure TAtlasBuildDebugSettingsTests.DebugStepFilterOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  // #850: an, Getter und triviale Routinen, keine Muster; alles überlebt Speichern und Laden, Normalize bereinigt.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.DebugStepFilters);
  Assert.AreEqual('getters,trivial', mSettings.DebugStepFilterKinds);
  Assert.AreEqual('', mSettings.DebugStepFilterPatterns);
  mSettings.DebugStepFilters := False;
  mSettings.DebugStepFilterKinds := 'Operators, setters, quatsch';
  mSettings.DebugStepFilterPatterns := ' *.Log* ;; TBasisForm.*;*.log*';
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  mLoaded.Normalize;
  Assert.IsFalse(mLoaded.DebugStepFilters);
  Assert.AreEqual('setters,operators', mLoaded.DebugStepFilterKinds);
  Assert.AreEqual('*.Log*;TBasisForm.*', mLoaded.DebugStepFilterPatterns);
end;
procedure TAtlasBuildDebugSettingsTests.DebugVisualizerOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.DebugVisualizers);
  Assert.AreEqual('lists,dictionaries,dataSets,bytes,json,colors,guid,geometry,graphics',
    mSettings.DebugVisualizerTypes);
  Assert.AreEqual('Name,Caption,Text', mSettings.DebugVisualizerNameFields);
  Assert.AreEqual(120, mSettings.DebugVisualizerMaxLength);
  Assert.AreEqual(200, mSettings.DebugVisualizerTimeoutMs);
  Assert.AreEqual(4000000, mSettings.DebugVisualizerMaxImagePixels);
  Assert.AreEqual('properties', mSettings.DebugVisualizerEvaluation);
  mSettings.DebugVisualizers := False;
  mSettings.DebugVisualizerTypes := 'json,lists';
  mSettings.DebugVisualizerNameFields := 'Bezeichnung';
  mSettings.DebugVisualizerMaxLength := 80;
  mSettings.DebugVisualizerTimeoutMs := 500;
  mSettings.DebugVisualizerMaxImagePixels := 100000;
  mSettings.DebugVisualizerEvaluation := 'calls';
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  mLoaded.Normalize;
  Assert.IsFalse(mLoaded.DebugVisualizers);
  Assert.AreEqual('lists,json', mLoaded.DebugVisualizerTypes, 'feste Reihenfolge');
  Assert.AreEqual('Bezeichnung', mLoaded.DebugVisualizerNameFields);
  Assert.AreEqual(80, mLoaded.DebugVisualizerMaxLength);
  Assert.AreEqual(500, mLoaded.DebugVisualizerTimeoutMs);
  Assert.AreEqual(100000, mLoaded.DebugVisualizerMaxImagePixels);
  Assert.AreEqual('calls', mLoaded.DebugVisualizerEvaluation);
  // Grenzen und unbekannte Werte.
  mLoaded.DebugVisualizerTypes := 'gibtsnicht, Colors';
  mLoaded.DebugVisualizerNameFields := ' Name , ,Name, Text ';
  mLoaded.DebugVisualizerMaxLength := 5;
  mLoaded.DebugVisualizerTimeoutMs := 100000;
  mLoaded.DebugVisualizerMaxImagePixels := 1;
  mLoaded.DebugVisualizerEvaluation := 'alles';
  mLoaded.Normalize;
  Assert.AreEqual('colors', mLoaded.DebugVisualizerTypes);
  Assert.AreEqual('Name,Text', mLoaded.DebugVisualizerNameFields);
  Assert.AreEqual(20, mLoaded.DebugVisualizerMaxLength);
  Assert.AreEqual(5000, mLoaded.DebugVisualizerTimeoutMs);
  Assert.AreEqual(10000, mLoaded.DebugVisualizerMaxImagePixels);
  Assert.AreEqual('fields', mLoaded.DebugVisualizerEvaluation, 'unbekannt = erster Wert');
  mLoaded.DebugVisualizerTypes := '';
  mLoaded.Normalize;
  Assert.AreEqual('', mLoaded.DebugVisualizerTypes, 'leer = keine Art');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBuildDebugSettingsTests);

end.
