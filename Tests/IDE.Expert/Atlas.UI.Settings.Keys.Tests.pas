unit Atlas.UI.Settings.Keys.Tests;

// Tests für die Seite „Tastenkonflikte“ (#494): Laden und Speichern, Status je
// Zeile über eine vorgegebene Belegung und die Wahl „Atlas verwenden“;
// Schalter der Tastenkürzel-Übersicht (#520).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasKeysPageTests = class
  public
    [SetupFixture]
    procedure WarmUp;
    [Test]
    procedure CreatesAndRoundTripsSettings;
    [Test]
    procedure ShowsOwnerAndChoice;
    [Test]
    procedure UseAtlasTakesIdeKey;
    [Test]
    procedure ListsForeignCompletions;
    [Test]
    procedure RoundTripsOverviewSwitches;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Menus,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Commands.KeyConflicts,
  Atlas.UI.Settings.Strings,
  Atlas.UI.Settings.Keys;

procedure TAtlasKeysPageTests.WarmUp;
begin
  TAtlasKeysPage.Create(nil).Free;
end;

procedure TAtlasKeysPageTests.CreatesAndRoundTripsSettings;
var
  mPage: TAtlasKeysPage;
  mSettings, mSaved: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.CompletionKey := $6048;
  mSettings.CompletionKeyPriority := True;
  mSettings.CheckKeyPriority := True;
  mPage := TAtlasKeysPage.Create(nil);
  try
    mPage.LoadFrom(mSettings);
    Assert.AreEqual(ShortCutToText($6048), mPage.KeyEdit(2).Text);
    Assert.AreEqual('', mPage.KeyEdit(3).Text, 'Parameter-Hint: Taste der IDE');
    // Diagnosemodus (#479) als sechste Zeile mit eigener Vorgabe.
    Assert.AreEqual(ShortCutToText($E044), mPage.KeyEdit(5).Text);
    mPage.KeyEdit(5).Text := ShortCutToText($6044);
    // Neue Taste für die Befehlspalette eintippen.
    mPage.KeyEdit(0).Text := ShortCutToText($6050);
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
  finally
    mPage.Free;
  end;
  Assert.AreEqual($6048, mSaved.CompletionKey);
  Assert.IsTrue(mSaved.CompletionKeyPriority);
  Assert.IsTrue(mSaved.CheckKeyPriority);
  Assert.AreEqual($6050, mSaved.PaletteKey);
  Assert.AreEqual(0, mSaved.SignatureKey);
  Assert.AreEqual($6044, mSaved.DiagnosticModeKey);
end;

procedure TAtlasKeysPageTests.ShowsOwnerAndChoice;
var
  mPage: TAtlasKeysPage;
begin
  mPage := TAtlasKeysPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    mPage.OwnerOf :=
      function(AShortCut: Word): string
      begin
        if AShortCut = TAtlasKeyConflicts.cPaletteDefault then
        begin
          Result := 'IDE: Makro';
        end
        else
        begin
          Result := '';
        end;
      end;
    Assert.AreEqual(TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.KeysStatusLeft, ['IDE: Makro']),
      mPage.StatusLabel(0).Caption);
    Assert.AreEqual(Ord(TAtlasKeyChoice.LeaveOther), mPage.ChoiceBox(0).Choice);
    Assert.IsTrue(mPage.ChoiceBox(0).Enabled);
    Assert.AreEqual(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.KeysStatusFree), mPage.StatusLabel(1).Caption);
    Assert.IsFalse(mPage.ChoiceBox(1).Enabled, 'freie Taste: nichts zu entscheiden');
    mPage.ChoiceBox(0).Choice := Ord(TAtlasKeyChoice.UseAtlas);
    mPage.ChoiceBox(0).OnChange(mPage.ChoiceBox(0));
    Assert.AreEqual(TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.KeysStatusAtlasWins, ['IDE: Makro']),
      mPage.StatusLabel(0).Caption);
    mPage.KeyEdit(1).Text := 'kein Kürzel';
    Assert.AreEqual(TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.KeysInvalid, ['kein Kürzel']),
      mPage.StatusLabel(1).Caption);
  finally
    mPage.Free;
  end;
end;

procedure TAtlasKeysPageTests.UseAtlasTakesIdeKey;
var
  mPage: TAtlasKeysPage;
  mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasKeysPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.AreEqual(TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.KeysStatusIdeKey,
      [ShortCutToText(TAtlasKeyConflicts.cIdeSignatureKey)]), mPage.StatusLabel(3).Caption);
    mPage.ChoiceBox(3).Choice := Ord(TAtlasKeyChoice.UseAtlas);
    mPage.ChoiceBox(3).OnChange(mPage.ChoiceBox(3));
    Assert.AreEqual(ShortCutToText(TAtlasKeyConflicts.cIdeSignatureKey), mPage.KeyEdit(3).Text);
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
  finally
    mPage.Free;
  end;
  Assert.AreEqual(Integer(TAtlasKeyConflicts.cIdeSignatureKey), mSaved.SignatureKey);
  Assert.IsTrue(mSaved.SignatureKeyPriority);
end;

procedure TAtlasKeysPageTests.ListsForeignCompletions;
var
  mPage: TAtlasKeysPage;
begin
  mPage := TAtlasKeysPage.Create(nil);
  try
    mPage.ShowForeignCompletions(['CnPack']);
    Assert.AreEqual(TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.KeysForeign, ['CnPack']), mPage.ForeignLabel.Caption);
  finally
    mPage.Free;
  end;
end;

procedure TAtlasKeysPageTests.RoundTripsOverviewSwitches;
var
  mPage: TAtlasKeysPage;
  mSettings, mSaved: TAtlasPluginSettings;
begin
  mPage := TAtlasKeysPage.Create(nil);
  try
    mPage.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(mPage.OverviewBox.Checked, 'Menüeintrag standardmäßig an');
    Assert.IsTrue(mPage.StartupCheckBox.Checked, 'Prüfung beim Start standardmäßig an');
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.KeyStartupCheck := False;
    mPage.LoadFrom(mSettings);
    Assert.IsFalse(mPage.StartupCheckBox.Checked);
    mPage.OverviewBox.Checked := False;
    mPage.StartupCheckBox.Checked := True;
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
  finally
    mPage.Free;
  end;
  Assert.IsFalse(mSaved.KeyOverview);
  Assert.IsTrue(mSaved.KeyStartupCheck);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasKeysPageTests);

end.
