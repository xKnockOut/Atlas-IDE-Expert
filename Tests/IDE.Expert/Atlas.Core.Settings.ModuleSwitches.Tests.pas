unit Atlas.Core.Settings.ModuleSwitches.Tests;

// Modul-Schalter (#1454): Schalter und Mitglieder aus dem Katalog (auch
// verschachtelt über x-parent und Präfixregel), Werte für „aus“ in den
// wirksamen Werten (boolesch und x-offValue), gespeicherte Werte bleiben,
// Zustände bleiben unberührt; der echte Katalog kennt alle Module.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasModuleSwitchesTests = class
  public
    [Test]
    procedure ReadFindsSwitchesAndMembers;
    [Test]
    procedure ModuleOffMasksMembers;
    [Test]
    procedure ModuleOnKeepsValues;
    [Test]
    procedure OffValueForChoices;
    [Test]
    procedure IsOnOffModulesAndModuleOf;
    [Test]
    procedure RealCatalogKnowsAllModules;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Catalog,
  Atlas.Core.Settings.ModuleSwitches;

const
  cPluginSchema =
    '{"x-areas":{"debug":{"caption":"Debuggen"}},"properties":{' +
    '"PairColors":{"type":"boolean","default":true,"x-key":"highlight.pairColors","x-area":"debug",' +
      '"x-page":"Editor"},' +
    '"DebugEnabled":{"type":"boolean","default":true,"x-key":"debug.enabled","x-area":"debug","x-page":"Debuggen",' +
      '"x-parent":"","x-module":"debug","x-caption":"Debugger"},' +
    '"DebugExceptionHistory":{"type":"boolean","default":true,"x-key":"debug.exceptionHistory","x-area":"debug",' +
      '"x-page":"Debuggen"},' +
    '"DebugExceptionBanner":{"type":"boolean","default":false,"x-key":"debug.exceptionBanner","x-area":"debug",' +
      '"x-page":"Debuggen","x-parent":"debug.exceptionHistory"},' +
    '"DebugInlineValuesPerLine":{"type":"integer","default":5,"x-key":"debug.inlineValuesPerLine",' +
      '"x-area":"debug","x-page":"Debuggen"},' +
    '"ArchitectureWindowPlaced":{"type":"boolean","default":false,"x-key":"debug.windowPlaced","x-area":"debug",' +
      '"x-page":"Debuggen","x-state":true},' +
    '"BuildToolsEnabled":{"type":"boolean","default":true,"x-key":"buildTools.enabled","x-area":"debug",' +
      '"x-page":"Compiler","x-parent":"","x-module":"buildTools"},' +
    '"BuildGate":{"type":"string","default":"off","enum":["off","warn","block"],"x-key":"build.gate",' +
      '"x-area":"debug","x-page":"Compiler","x-parent":"buildTools.enabled","x-offValue":"off"}' +
    '}}';

function Switches: TArray<TAtlasModuleSwitch>;
var
  mCatalog: TAtlasSettingsCatalog;
begin
  mCatalog := TAtlasSettingsCatalog.Create(cPluginSchema, '{}');
  try
    Result := TAtlasModuleSwitches.Read(mCatalog);
  finally
    mCatalog.Free;
  end;
end;

function Settings(ADebug: Boolean): TAtlasPluginSettings;
begin
  Result := TAtlasPluginSettings.Defaults;
  Result.DebugEnabled := ADebug;
  Result.DebugExceptionHistory := True;
  Result.DebugExceptionBanner := True;
  Result.DebugInlineValuesPerLine := 9;
  Result.ArchitectureWindowPlaced := True;
  Result.PairColors := True;
end;

function MemberNames(const ASwitch: TAtlasModuleSwitch): string;
var
  mEntry: TAtlasCatalogEntry;
begin
  Result := '';
  for mEntry in ASwitch.Members do
  begin
    Result := Result + mEntry.Name + ';';
  end;
end;

procedure TAtlasModuleSwitchesTests.ReadFindsSwitchesAndMembers;
var
  mSwitches: TArray<TAtlasModuleSwitch>;
begin
  mSwitches := Switches;
  Assert.AreEqual(2, Integer(Length(mSwitches)));
  Assert.AreEqual('debug', mSwitches[0].Module);
  Assert.AreEqual('DebugEnabled', mSwitches[0].Name);
  Assert.AreEqual('debug.enabled', mSwitches[0].Key);
  Assert.AreEqual('Debugger', mSwitches[0].Caption);
  // Präfixregel (debug.exceptionHistory) und verschachtelt über x-parent (debug.exceptionBanner); Zahlen und
  // Zustände haben keinen Wert für „aus“.
  Assert.AreEqual('DebugExceptionHistory;DebugExceptionBanner;', MemberNames(mSwitches[0]));
  Assert.AreEqual('buildTools', mSwitches[1].Module);
  Assert.AreEqual('BuildGate;', MemberNames(mSwitches[1]));
end;

procedure TAtlasModuleSwitchesTests.ModuleOffMasksMembers;
var
  mStored, mEffective: TAtlasPluginSettings;
begin
  mStored := Settings(False);
  mEffective := TAtlasModuleSwitches.Apply(mStored, Switches);
  Assert.IsFalse(mEffective.DebugExceptionHistory);
  Assert.IsFalse(mEffective.DebugExceptionBanner, 'auch verschachtelt');
  Assert.AreEqual(9, mEffective.DebugInlineValuesPerLine, 'Zahlen bleiben');
  Assert.IsTrue(mEffective.ArchitectureWindowPlaced, 'Zustände bleiben');
  Assert.IsTrue(mEffective.PairColors, 'Kern unverändert');
  Assert.IsFalse(mEffective.DebugEnabled, 'der Schalter selbst bleibt');
  Assert.IsTrue(mStored.DebugExceptionHistory, 'gespeicherte Werte unverändert');
  Assert.IsTrue(mStored.DebugExceptionBanner);
end;

procedure TAtlasModuleSwitchesTests.ModuleOnKeepsValues;
var
  mEffective: TAtlasPluginSettings;
begin
  mEffective := TAtlasModuleSwitches.Apply(Settings(True), Switches);
  Assert.IsTrue(mEffective.DebugExceptionHistory);
  Assert.IsTrue(mEffective.DebugExceptionBanner);
  Assert.IsTrue(mEffective.DebugEnabled);
  mEffective := TAtlasModuleSwitches.Apply(Settings(False), nil);
  Assert.IsTrue(mEffective.DebugExceptionHistory, 'ohne Modul-Schalter im Katalog');
end;

procedure TAtlasModuleSwitchesTests.OffValueForChoices;
var
  mStored, mEffective: TAtlasPluginSettings;
begin
  mStored := Settings(True);
  mStored.BuildGate := 'block';
  mStored.BuildToolsEnabled := False;
  mEffective := TAtlasModuleSwitches.Apply(mStored, Switches);
  Assert.AreEqual('off', mEffective.BuildGate);
  Assert.IsTrue(mEffective.DebugExceptionHistory, 'anderes Modul unberührt');
  mStored.BuildToolsEnabled := True;
  Assert.AreEqual('block', TAtlasModuleSwitches.Apply(mStored, Switches).BuildGate);
end;

procedure TAtlasModuleSwitchesTests.IsOnOffModulesAndModuleOf;
var
  mSwitches: TArray<TAtlasModuleSwitch>;
  mSettings: TAtlasPluginSettings;
  mOff: TArray<string>;
begin
  mSwitches := Switches;
  mSettings := Settings(False);
  Assert.IsFalse(TAtlasModuleSwitches.IsOn(mSettings, mSwitches, 'debug'));
  Assert.IsTrue(TAtlasModuleSwitches.IsOn(mSettings, mSwitches, 'buildTools'));
  Assert.IsTrue(TAtlasModuleSwitches.IsOn(mSettings, mSwitches, 'unbekannt'), 'unbekannt = an');
  mSettings.BuildToolsEnabled := False;
  mOff := TAtlasModuleSwitches.OffModules(mSettings, mSwitches);
  Assert.AreEqual(2, Integer(Length(mOff)));
  Assert.AreEqual('debug', mOff[0]);
  Assert.AreEqual('buildTools', mOff[1]);
  Assert.AreEqual('debug', TAtlasModuleSwitches.ModuleOf(mSwitches, 'debug.exceptionBanner'));
  Assert.AreEqual('debug', TAtlasModuleSwitches.ModuleOf(mSwitches, 'DebugEnabled'), 'der Schalter selbst');
  Assert.AreEqual('buildTools', TAtlasModuleSwitches.ModuleOf(mSwitches, 'BuildGate'));
  Assert.AreEqual('', TAtlasModuleSwitches.ModuleOf(mSwitches, 'highlight.pairColors'), 'Kern');
end;

procedure TAtlasModuleSwitchesTests.RealCatalogKnowsAllModules;
const
  cModules: array[0..13] of string = ('debug', 'issues', 'analysis', 'tests', 'buildTools', 'buildPipeline',
    'bookmarks', 'designer', 'ruleChecks', 'search', 'welcome', 'vcs', 'assistants', 'help');
var
  mCatalog: TAtlasSettingsCatalog;
  mSwitches: TArray<TAtlasModuleSwitch>;
  mModule: string;
  mSwitch: TAtlasModuleSwitch;
  mFound: Boolean;
begin
  mCatalog := TAtlasSettingsCatalog.CreateDefault;
  try
    mSwitches := TAtlasModuleSwitches.Read(mCatalog);
  finally
    mCatalog.Free;
  end;
  Assert.AreEqual(Integer(Length(cModules)), Integer(Length(mSwitches)));
  for mModule in cModules do
  begin
    mFound := False;
    for mSwitch in mSwitches do
    begin
      if mSwitch.Module = mModule then
      begin
        mFound := True;
        // Hilfe (#1886) hat nur den Modulschalter selbst.
        Assert.IsTrue((Length(mSwitch.Members) > 0) or (mModule = 'help'), mModule + ' ohne Einstellungen');
      end;
    end;
    Assert.IsTrue(mFound, mModule);
  end;
  Assert.AreEqual('debug', TAtlasModuleSwitches.ModuleOf(mSwitches, 'debug.inlineValues'));
  Assert.AreEqual('issues', TAtlasModuleSwitches.ModuleOf(mSwitches, 'welcomePage.issues'));
  Assert.AreEqual('issues', TAtlasModuleSwitches.ModuleOf(mSwitches, 'welcomePage.tests.ci.login'));
  Assert.AreEqual('welcome', TAtlasModuleSwitches.ModuleOf(mSwitches, 'welcomePage.discover'));
  Assert.AreEqual('tests', TAtlasModuleSwitches.ModuleOf(mSwitches, 'codeLens.tests'));
  Assert.AreEqual('tests', TAtlasModuleSwitches.ModuleOf(mSwitches, 'tests.debug'));
  Assert.AreEqual('buildTools', TAtlasModuleSwitches.ModuleOf(mSwitches, 'startProfiles.statusField'));
  Assert.AreEqual('buildTools', TAtlasModuleSwitches.ModuleOf(mSwitches, 'taskRunner.beforeBuild'));
  Assert.AreEqual('buildPipeline', TAtlasModuleSwitches.ModuleOf(mSwitches, 'build.gate'));
  Assert.AreEqual('buildPipeline', TAtlasModuleSwitches.ModuleOf(mSwitches, 'build.releaseGuard'));
  Assert.AreEqual('assistants', TAtlasModuleSwitches.ModuleOf(mSwitches, 'compiler.mcpBuild'));
  Assert.AreEqual('bookmarks', TAtlasModuleSwitches.ModuleOf(mSwitches, 'notes.enabled'));
  Assert.AreEqual('analysis', TAtlasModuleSwitches.ModuleOf(mSwitches, 'navigation.symbolPath'));
  Assert.AreEqual('designer', TAtlasModuleSwitches.ModuleOf(mSwitches, 'editor.designerBar'));
  Assert.AreEqual('search', TAtlasModuleSwitches.ModuleOf(mSwitches, 'unitSearch.preview'));
  Assert.AreEqual('ruleChecks', TAtlasModuleSwitches.ModuleOf(mSwitches, 'fix.bulk'));
  // Kern: Compilermeldungen, Prüfen nach dem Speichern, Fenster „Atlas-Prüfung“, Vervollständigung.
  Assert.AreEqual('', TAtlasModuleSwitches.ModuleOf(mSwitches, 'build.checkOnSave'));
  Assert.AreEqual('', TAtlasModuleSwitches.ModuleOf(mSwitches, 'problems.window'));
  Assert.AreEqual('', TAtlasModuleSwitches.ModuleOf(mSwitches, 'completion.enabled'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasModuleSwitchesTests);

end.
