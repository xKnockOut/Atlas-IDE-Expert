unit Atlas.UI.Tests.SettingsSection.Tests;

// Abschnitte des Moduls Tests (#1456) auf den Seiten „Compiler“, „Debuggen“ und „Editor“: Laden und Speichern
// über die Seite (vorher in den Tests der Seite von Base) und der Platz auf den Reitern.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Modules.Contract;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TTestsSettingsSectionTests = class
  private
    FRegistrations: TArray<IAtlasRegistration>;
  public
    [SetupFixture]
    procedure WarmUp;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>DUnitX-Tests (#69), Code Lens an Testmethoden und Test im Debugger (#585).</summary>
    [Test]
    procedure TestsRoundTrip;
    /// <summary>Ein Modul, drei Seiten: Debuggen entsteht für den Abschnitt, Compiler und Editor hat Base.</summary>
    [Test]
    procedure SectionsOnTheirSheets;
  end;

implementation

uses
  Vcl.Forms,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.Page.TestSupport,
  Atlas.UI.Tests.SettingsSection;

procedure TTestsSettingsSectionTests.WarmUp;
begin
  WarmUpSettingsPage;
end;

procedure TTestsSettingsSectionTests.Setup;
begin
  FRegistrations := ProvideSections([TAtlasTestsCompilerSection, TAtlasTestsDebugSection, TAtlasTestsEditorSection]);
end;

procedure TTestsSettingsSectionTests.TearDown;
begin
  RevokeAll(FRegistrations);
end;

procedure TTestsSettingsSectionTests.TestsRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(CheckOf(mPage, 'TestsEnabled').Checked, 'Modulschalter');
    Assert.IsTrue(CheckOf(mPage, 'CodeLensTests').Checked, 'Code Lens standardmäßig an');
    Assert.IsTrue(CheckOf(mPage, 'TestRun').Checked);
    Assert.IsTrue(CheckOf(mPage, 'TestsBuildFirst').Checked);
    Assert.IsFalse(CheckOf(mPage, 'TestsAfterBuild').Checked);
    Assert.IsTrue(CheckOf(mPage, 'TestDebug').Checked, 'Test debuggen standardmäßig an');
    Assert.IsTrue(CheckOf(mPage, 'TestBreakAtStart').Checked, 'Haltepunkt am Anfang standardmäßig an');
    Assert.IsTrue(CheckOf(mPage, 'CodeLensCoveredBy').Checked, '„getestet von“ standardmäßig an (#1778)');
    Assert.IsFalse(CheckOf(mPage, 'TestsCoveredByPrivate').Checked, 'private Methoden standardmäßig aus (#1778)');
    Assert.IsTrue(CheckOf(mPage, 'CodeLensUntested').Checked, '„Methoden getestet“ standardmäßig an (#1783)');
    CheckOf(mPage, 'CodeLensTests').Checked := False;
    CheckOf(mPage, 'TestRun').Checked := False;
    CheckOf(mPage, 'TestsBuildFirst').Checked := False;
    CheckOf(mPage, 'TestsAfterBuild').Checked := True;
    CheckOf(mPage, 'TestDebug').Checked := False;
    CheckOf(mPage, 'TestBreakAtStart').Checked := False;
    EditOf(mPage, 'TestsAffectedDepth').Text := '4';
    CheckOf(mPage, 'CodeLensCoveredBy').Checked := False;
    CheckOf(mPage, 'TestsCoveredByPrivate').Checked := True;
    EditOf(mPage, 'TestsCoveredByDepth').Text := '2';
    CheckOf(mPage, 'CodeLensUntested').Checked := False;
    EditOf(mPage, 'TestsUntestedWarnPercent').Text := '80';
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.CodeLensTests);
    Assert.IsFalse(mSaved.TestRun);
    Assert.IsFalse(mSaved.TestsBuildFirst);
    Assert.IsTrue(mSaved.TestsAfterBuild);
    Assert.IsFalse(mSaved.TestDebug);
    Assert.IsFalse(mSaved.TestBreakAtStart);
    Assert.AreEqual(4, mSaved.TestsAffectedDepth);
    Assert.IsFalse(mSaved.CodeLensCoveredBy);
    Assert.IsTrue(mSaved.TestsCoveredByPrivate);
    Assert.AreEqual(2, mSaved.TestsCoveredByDepth);
    Assert.IsFalse(mSaved.CodeLensUntested);
    Assert.AreEqual(80, mSaved.TestsUntestedWarnPercent);
    mSaved.TestBreakAtStart := True;
    mPage.LoadFrom(mSaved);
    Assert.IsFalse(CheckOf(mPage, 'CodeLensTests').Checked);
    Assert.IsTrue(CheckOf(mPage, 'TestsAfterBuild').Checked);
    Assert.IsFalse(CheckOf(mPage, 'TestDebug').Checked);
    Assert.IsTrue(CheckOf(mPage, 'TestBreakAtStart').Checked);
  finally
    mPage.Free;
  end;
end;

procedure TTestsSettingsSectionTests.SectionsOnTheirSheets;
var
  mHost: TForm;
  mPage: TAtlasSettingsPage;
begin
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    // Unterpunkte (x-node) der Bereiche von Base nehmen auch die Zeilen des Moduls auf.
    Assert.IsTrue(SheetOf(CheckOf(mPage, 'TestRun')) = mPage.NodeSheet('compiler.tests'), 'Compiler › Tests');
    Assert.IsTrue(SheetOf(CheckOf(mPage, 'CodeLensTests')) = mPage.NodeSheet('editor.codeLens'), 'Editor › Code Lens');
    Assert.IsTrue(SheetOf(CheckOf(mPage, 'TestDebug')) = SheetOf(CheckOf(mPage, 'TestBreakAtStart')));
    Assert.IsFalse(SheetOf(CheckOf(mPage, 'TestDebug')) = SheetOf(CheckOf(mPage, 'TestsEnabled')), 'eigener Reiter');
  finally
    mHost.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestsSettingsSectionTests);

end.
