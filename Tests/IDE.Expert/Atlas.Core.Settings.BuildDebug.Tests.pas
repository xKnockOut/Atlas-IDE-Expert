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
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tasks.Definitions,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.TestSupport;

procedure TAtlasBuildDebugSettingsTests.ReleaseGuardOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.ReleaseGuard, 'Release-Wächter standardmäßig an');
  Assert.AreEqual('off', Settings.BuildGate, 'build.gate standardmäßig off (#529)');
  Assert.AreEqual('Release', Settings.ReleaseConfigs);
  Assert.AreEqual('debugDefine,debugInfo=off,stackFrames=off,assertions=off,rangeChecks=off,overflowChecks=off,' +
    'memoryLeaks,versionInfo,outputFolder', Settings.ReleaseChecks, 'alle Prüfungen an, Sollwerte aus');
  // Leeres Speicher-Objekt: Vorgaben.
  Store := TMemoryStore.Create;
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.AreEqual(Settings.ReleaseChecks, Loaded.ReleaseChecks);
  // Normalisieren: unbekannter Modus = off, Liste ohne Doppelte, Prüfungen vollständig in fester Reihenfolge.
  Settings.BuildGate := 'BLOCK';
  Settings.ReleaseConfigs := 'Release; Ship,, ship';
  Settings.ReleaseChecks := '-assertions, rangeChecks=on, quatsch';
  Settings.Normalize;
  Assert.AreEqual('block', Settings.BuildGate);
  Assert.AreEqual('Release, Ship', Settings.ReleaseConfigs);
  Assert.AreEqual('debugDefine,debugInfo=off,stackFrames=off,-assertions=off,rangeChecks=on,overflowChecks=off,' +
    'memoryLeaks,versionInfo,outputFolder', Settings.ReleaseChecks);
  Settings.BuildGate := 'streng';
  Settings.Normalize;
  Assert.AreEqual('off', Settings.BuildGate);
  // Speichern und Laden.
  Settings.ReleaseGuard := False;
  Settings.BuildGate := 'warn';
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.ReleaseGuard, 'abschaltbar');
  Assert.AreEqual('warn', Loaded.BuildGate);
  Assert.AreEqual('Release, Ship', Loaded.ReleaseConfigs);
  Assert.AreEqual(Settings.ReleaseChecks, Loaded.ReleaseChecks);
end;
procedure TAtlasBuildDebugSettingsTests.StopRunningProgramOption;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('ask', Settings.BuildStopRunningProgram, 'standardmäßig Rückfrage');
  Settings.BuildStopRunningProgram := ' Always ';
  Settings.Normalize;
  Assert.AreEqual('always', Settings.BuildStopRunningProgram);
  Settings.BuildStopRunningProgram := 'immer';
  Settings.Normalize;
  Assert.AreEqual('ask', Settings.BuildStopRunningProgram, 'Unbekanntes = ask');
  Settings.BuildStopRunningProgram := 'never';
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.AreEqual('never', Loaded.BuildStopRunningProgram);
end;

procedure TAtlasBuildDebugSettingsTests.TasksOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
  Mode: TAtlasTaskBeforeBuild;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.TasksEnabled, 'tasks.enabled standardmäßig an (#900)');
  Assert.IsTrue(Settings.TasksProblemsFromOutput);
  Assert.AreEqual('off', Settings.TasksBeforeBuild);
  Assert.IsTrue(Settings.TasksSaveBeforeRun);
  Assert.IsFalse(Settings.TasksRunChecksParallel);
  Assert.IsFalse(Settings.TasksOnlyFindings);
  // Normalisieren: Groß-/Kleinschreibung egal, Unbekanntes = off.
  Settings.TasksBeforeBuild := ' Block ';
  Settings.Normalize;
  Assert.AreEqual('block', Settings.TasksBeforeBuild);
  Settings.TasksBeforeBuild := 'immer';
  Settings.Normalize;
  Assert.AreEqual('off', Settings.TasksBeforeBuild);
  // Die Einstellungen kennen die Projektaufgaben nicht: dieselben Werte wie dort.
  for Mode := Low(TAtlasTaskBeforeBuild) to High(TAtlasTaskBeforeBuild) do
  begin
    Settings.TasksBeforeBuild := UpperCase(TAtlasTasks.cBeforeBuildNames[Mode]);
    Settings.Normalize;
    Assert.AreEqual(TAtlasTasks.cBeforeBuildNames[Mode], Settings.TasksBeforeBuild);
  end;
  // Speichern und Laden, jede Einstellung abweichend von der Vorgabe.
  Settings.TasksEnabled := False;
  Settings.TasksProblemsFromOutput := False;
  Settings.TasksBeforeBuild := 'warn';
  Settings.TasksSaveBeforeRun := False;
  Settings.TasksRunChecksParallel := True;
  Settings.TasksOnlyFindings := True;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.TasksEnabled, 'abschaltbar');
  Assert.IsFalse(Loaded.TasksProblemsFromOutput);
  Assert.AreEqual('warn', Loaded.TasksBeforeBuild);
  Assert.IsFalse(Loaded.TasksSaveBeforeRun);
  Assert.IsTrue(Loaded.TasksRunChecksParallel);
  Assert.IsTrue(Loaded.TasksOnlyFindings);
end;
procedure TAtlasBuildDebugSettingsTests.BuildGateTimeoutOption;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual(300, Settings.BuildGateTimeoutMs, 'Vorgabe 300 ms');
  Settings.BuildGateTimeoutMs := 1;
  Settings.Normalize;
  Assert.AreEqual(50, Settings.BuildGateTimeoutMs, 'untere Grenze');
  Settings.BuildGateTimeoutMs := 100000;
  Settings.Normalize;
  Assert.AreEqual(10000, Settings.BuildGateTimeoutMs, 'obere Grenze');
  Settings.BuildGateTimeoutMs := 750;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.AreEqual(750, Loaded.BuildGateTimeoutMs);
end;
procedure TAtlasBuildDebugSettingsTests.BuildSummaryOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.BuildSummary, 'Zusammenfassung standardmäßig an');
  Assert.AreEqual('', Settings.BuildWarningsAsErrors);
  Settings.BuildSummary := False;
  Settings.BuildWarningsAsErrors := 'w1035; H2164 x123 W1035';
  Settings.Normalize;
  Assert.AreEqual('W1035, H2164', Settings.BuildWarningsAsErrors, 'groß, ohne Doppelte und Ungültiges');
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.BuildSummary);
  Assert.AreEqual('W1035, H2164', Loaded.BuildWarningsAsErrors);
end;
procedure TAtlasBuildDebugSettingsTests.BuildOnOpenOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsFalse(Settings.BuildOnOpen, 'standardmäßig aus');
  Assert.AreEqual('make', Settings.BuildOnOpenKind);
  Assert.AreEqual('all', Settings.BuildOnOpenScope);
  Assert.AreEqual(3000, Settings.BuildOnOpenDelayMs);
  Assert.AreEqual('', Settings.BuildOnOpenExclude);
  Assert.AreEqual('', Settings.BuildOnOpenConfig, 'wie im Projekt (#1293)');
  Assert.AreEqual('', Settings.BuildOnOpenPlatform, 'wie im Projekt (#1293)');
  // Normalisieren: unbekannte Art = make, unbekannter Umfang = all, Wartezeit in den Grenzen, Liste ohne Endung
  // und Doppelte.
  Settings.BuildOnOpenKind := 'BUILD';
  Settings.BuildOnOpenScope := 'Active';
  Settings.BuildOnOpenDelayMs := 10;
  Settings.BuildOnOpenExclude := ' Atlas.IDE.Expert.dproj; atlas.ide.expert,, Demo ';
  Settings.BuildOnOpenConfig := ' Debug ';
  Settings.BuildOnOpenPlatform := ' Win64 ';
  Settings.Normalize;
  Assert.AreEqual('Debug', Settings.BuildOnOpenConfig);
  Assert.AreEqual('Win64', Settings.BuildOnOpenPlatform);
  Assert.AreEqual('build', Settings.BuildOnOpenKind);
  Assert.AreEqual('active', Settings.BuildOnOpenScope);
  Assert.AreEqual(500, Settings.BuildOnOpenDelayMs);
  Assert.AreEqual('Atlas.IDE.Expert, Demo', Settings.BuildOnOpenExclude);
  Settings.BuildOnOpenKind := 'erzeugen';
  Settings.BuildOnOpenScope := 'keins';
  Settings.BuildOnOpenDelayMs := 999999;
  Settings.Normalize;
  Assert.AreEqual('make', Settings.BuildOnOpenKind);
  Assert.AreEqual('all', Settings.BuildOnOpenScope);
  Assert.AreEqual(60000, Settings.BuildOnOpenDelayMs);
  // Speichern und Laden.
  Settings.BuildOnOpen := True;
  Settings.BuildOnOpenKind := 'check';
  Settings.BuildOnOpenScope := 'active';
  Settings.BuildOnOpenDelayMs := 5000;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsTrue(Loaded.BuildOnOpen);
  Assert.AreEqual('check', Loaded.BuildOnOpenKind);
  Assert.AreEqual('active', Loaded.BuildOnOpenScope);
  Assert.AreEqual(5000, Loaded.BuildOnOpenDelayMs);
  Assert.AreEqual('Atlas.IDE.Expert, Demo', Loaded.BuildOnOpenExclude);
  Assert.AreEqual('Debug', Loaded.BuildOnOpenConfig);
  Assert.AreEqual('Win64', Loaded.BuildOnOpenPlatform);
end;
procedure TAtlasBuildDebugSettingsTests.DebugDisplayRuleOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // #854: an, Aufrufe aus; beide überleben Speichern und Laden.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.DebugDisplayRules);
  Assert.IsFalse(Settings.DebugDisplayRulesAllowCalls);
  Settings.DebugDisplayRules := False;
  Settings.DebugDisplayRulesAllowCalls := True;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Loaded.Normalize;
  Assert.IsFalse(Loaded.DebugDisplayRules);
  Assert.IsTrue(Loaded.DebugDisplayRulesAllowCalls);
end;
procedure TAtlasBuildDebugSettingsTests.DebugStepIntoTargetOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // #836: an mit Strg+Alt+F7; Schalter und Taste überleben Speichern und Laden, 0 = keine Taste.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.DebugStepIntoTarget);
  Assert.AreEqual($C076, Settings.DebugStepIntoTargetKey);
  Settings.DebugStepIntoTarget := False;
  Settings.DebugStepIntoTargetKey := 0;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Loaded.Normalize;
  Assert.IsFalse(Loaded.DebugStepIntoTarget);
  Assert.AreEqual(0, Loaded.DebugStepIntoTargetKey);
  Loaded.DebugStepIntoTargetKey := -5;
  Loaded.Normalize;
  Assert.AreEqual(0, Loaded.DebugStepIntoTargetKey);
end;
procedure TAtlasBuildDebugSettingsTests.DebugBreakOnNextEventOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // #856: an, ausgenommen OnPaint, OnMouseMove und OnUpdate; die Liste wird beim Normalisieren bereinigt.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.DebugBreakOnNextEvent);
  Assert.AreEqual('OnPaint, OnMouseMove, OnUpdate', Settings.DebugBreakOnNextEventExcluded);
  Settings.DebugBreakOnNextEvent := False;
  Settings.DebugBreakOnNextEventExcluded := 'OnPaint, OnResize';
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Loaded.Normalize;
  Assert.IsFalse(Loaded.DebugBreakOnNextEvent);
  Assert.AreEqual('OnPaint, OnResize', Loaded.DebugBreakOnNextEventExcluded);
  Loaded.DebugBreakOnNextEventExcluded := ' OnPaint ;; OnResize,';
  Loaded.Normalize;
  Assert.AreEqual('OnPaint, OnResize', Loaded.DebugBreakOnNextEventExcluded);
end;
procedure TAtlasBuildDebugSettingsTests.DebugBreakpointOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // #577: Haltepunkte vor dem Start prüfen ist an; der Wert überlebt Speichern und Laden.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.DebugCheckBreakpoints);
  Settings.DebugCheckBreakpoints := False;
  // #586: Haltepunkt-Satz mit dem Branch wechseln ist an.
  Assert.IsTrue(Settings.DebugBreakpointSetPerBranch);
  Settings.DebugBreakpointSetPerBranch := False;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.DebugCheckBreakpoints);
  Assert.IsFalse(Loaded.DebugBreakpointSetPerBranch);
end;
procedure TAtlasBuildDebugSettingsTests.DebugStepFilterOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // #850: an, Getter und triviale Routinen, keine Muster; alles überlebt Speichern und Laden, Normalize bereinigt.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.DebugStepFilters);
  Assert.AreEqual('getters,trivial', Settings.DebugStepFilterKinds);
  Assert.AreEqual('', Settings.DebugStepFilterPatterns);
  Settings.DebugStepFilters := False;
  Settings.DebugStepFilterKinds := 'Operators, setters, quatsch';
  Settings.DebugStepFilterPatterns := ' *.Log* ;; TBasisForm.*;*.log*';
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Loaded.Normalize;
  Assert.IsFalse(Loaded.DebugStepFilters);
  Assert.AreEqual('setters,operators', Loaded.DebugStepFilterKinds);
  Assert.AreEqual('*.Log*;TBasisForm.*', Loaded.DebugStepFilterPatterns);
end;
procedure TAtlasBuildDebugSettingsTests.DebugVisualizerOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.DebugVisualizers);
  Assert.AreEqual('lists,dictionaries,dataSets,bytes,json,colors,guid,geometry,graphics',
    Settings.DebugVisualizerTypes);
  Assert.AreEqual('Name,Caption,Text', Settings.DebugVisualizerNameFields);
  Assert.AreEqual(120, Settings.DebugVisualizerMaxLength);
  Assert.AreEqual(200, Settings.DebugVisualizerTimeoutMs);
  Assert.AreEqual(4000000, Settings.DebugVisualizerMaxImagePixels);
  Assert.AreEqual('properties', Settings.DebugVisualizerEvaluation);
  Settings.DebugVisualizers := False;
  Settings.DebugVisualizerTypes := 'json,lists';
  Settings.DebugVisualizerNameFields := 'Bezeichnung';
  Settings.DebugVisualizerMaxLength := 80;
  Settings.DebugVisualizerTimeoutMs := 500;
  Settings.DebugVisualizerMaxImagePixels := 100000;
  Settings.DebugVisualizerEvaluation := 'calls';
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Loaded.Normalize;
  Assert.IsFalse(Loaded.DebugVisualizers);
  Assert.AreEqual('lists,json', Loaded.DebugVisualizerTypes, 'feste Reihenfolge');
  Assert.AreEqual('Bezeichnung', Loaded.DebugVisualizerNameFields);
  Assert.AreEqual(80, Loaded.DebugVisualizerMaxLength);
  Assert.AreEqual(500, Loaded.DebugVisualizerTimeoutMs);
  Assert.AreEqual(100000, Loaded.DebugVisualizerMaxImagePixels);
  Assert.AreEqual('calls', Loaded.DebugVisualizerEvaluation);
  // Grenzen und unbekannte Werte.
  Loaded.DebugVisualizerTypes := 'gibtsnicht, Colors';
  Loaded.DebugVisualizerNameFields := ' Name , ,Name, Text ';
  Loaded.DebugVisualizerMaxLength := 5;
  Loaded.DebugVisualizerTimeoutMs := 100000;
  Loaded.DebugVisualizerMaxImagePixels := 1;
  Loaded.DebugVisualizerEvaluation := 'alles';
  Loaded.Normalize;
  Assert.AreEqual('colors', Loaded.DebugVisualizerTypes);
  Assert.AreEqual('Name,Text', Loaded.DebugVisualizerNameFields);
  Assert.AreEqual(20, Loaded.DebugVisualizerMaxLength);
  Assert.AreEqual(5000, Loaded.DebugVisualizerTimeoutMs);
  Assert.AreEqual(10000, Loaded.DebugVisualizerMaxImagePixels);
  Assert.AreEqual('fields', Loaded.DebugVisualizerEvaluation, 'unbekannt = erster Wert');
  Loaded.DebugVisualizerTypes := '';
  Loaded.Normalize;
  Assert.AreEqual('', Loaded.DebugVisualizerTypes, 'leer = keine Art');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBuildDebugSettingsTests);

end.
