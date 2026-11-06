unit Atlas.UI.Settings.Page.Build.Tests;

// Tests der Einstellungsseite: Reiter „Compiler“ von Base und Listenmodus der Vervollständigung. Die Einstellungen
// der Module zum Compiler testen deren Abschnitte (#1456).

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Reiter „Compiler“ von Base.</summary>
  [TestFixture]
  TAtlasSettingsPageBuildTests = class
  public
    /// <summary>Erstes Erzeugen von Steuerelementen legt einmalige VCL-Daten an (Themes, Schriften).</summary>
    [SetupFixture]
    procedure WarmUp;
    /// <summary>Aktion nach dem Speichern (#398, #548): nichts, Syntaxprüfung oder Kompilieren, nie beides; Kosten
    /// einer interface-Änderung (#554).</summary>
    [Test]
    procedure AfterSaveRoundTrip;
    [Test]
    procedure ListModeRoundTrip;
  end;

implementation

uses
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.Page.TestSupport,
  Atlas.UI.Settings.Page.Build,
  Atlas.UI.Settings.Page.Completion;

procedure TAtlasSettingsPageBuildTests.WarmUp;
begin
  WarmUpSettingsPage;
end;

procedure TAtlasSettingsPageBuildTests.AfterSaveRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mSaved := TAtlasPluginSettings.Defaults;
    mSaved.CheckOnSave := False;
    mSaved.CompileOnSave := False;
    mPage.LoadFrom(mSaved);
    Assert.AreEqual(0, mPage.Part<TAtlasSettingsBuildPart>.AfterSaveChoice.Choice, 'nichts');
    Assert.IsTrue(CheckOf(mPage, 'ShowInterfaceCost').Checked, 'Kosten einer interface-Änderung standardmäßig an');
    mPage.Part<TAtlasSettingsBuildPart>.AfterSaveChoice.Choice := 2;
    CheckOf(mPage, 'ShowInterfaceCost').Checked := False;
    mPage.SaveTo(mSaved);
    Assert.IsFalse(mSaved.CheckOnSave);
    Assert.IsTrue(mSaved.CompileOnSave, 'Kompilieren');
    Assert.IsFalse(mSaved.ShowInterfaceCost);
    mPage.Part<TAtlasSettingsBuildPart>.AfterSaveChoice.Choice := 1;
    mPage.SaveTo(mSaved);
    Assert.IsTrue(mSaved.CheckOnSave, 'Syntaxprüfung');
    Assert.IsFalse(mSaved.CompileOnSave, 'nie beides');
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    mPage.LoadFrom(mSaved);
    Assert.AreEqual(1, mPage.Part<TAtlasSettingsBuildPart>.AfterSaveChoice.Choice);
    Assert.IsFalse(CheckOf(mPage, 'ShowInterfaceCost').Checked);
  finally
    mPage.Free;
  end;
end;

procedure TAtlasSettingsPageBuildTests.ListModeRoundTrip;
var
  mPage: TAtlasSettingsPage;
  mSaved: TAtlasPluginSettings;
begin
  // Listenmodus der Vervollständigung (#497).
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.AreEqual(0, mPage.Part<TAtlasSettingsCompletionPart>.ListModeChoice.Choice, 'nur Treffer');
    Assert.AreEqual(0, mPage.Part<TAtlasSettingsCompletionPart>.ListScopeChoice.Choice, 'Mitgliederlisten');
    mPage.Part<TAtlasSettingsCompletionPart>.ListModeChoice.Choice := 2;
    mPage.Part<TAtlasSettingsCompletionPart>.ListScopeChoice.Choice := 1;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.AreEqual('rest', mSaved.CompletionListMode);
    Assert.AreEqual('everywhere', mSaved.CompletionListScope);
    mPage.Part<TAtlasSettingsCompletionPart>.ListModeChoice.Choice := 1;
    mPage.SaveTo(mSaved);
    Assert.AreEqual('all', mSaved.CompletionListMode);
    mPage.LoadFrom(mSaved);
    Assert.AreEqual(1, mPage.Part<TAtlasSettingsCompletionPart>.ListModeChoice.Choice);
    Assert.AreEqual(1, mPage.Part<TAtlasSettingsCompletionPart>.ListScopeChoice.Choice);
  finally
    mPage.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsPageBuildTests);

end.
