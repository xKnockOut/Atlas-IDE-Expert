unit Atlas.UI.Settings.Keys.Tests;

// Tests für die Seite „Tastenkonflikte“ (#494): Laden und Speichern, Status je
// Zeile über eine vorgegebene Belegung und die Wahl „Atlas verwenden“.

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
  end;

implementation

uses
  System.SysUtils,
  Vcl.Menus,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Commands.KeyConflicts,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Keys;

procedure TAtlasKeysPageTests.WarmUp;
begin
  TAtlasKeysPage.Create(nil).Free;
end;

procedure TAtlasKeysPageTests.CreatesAndRoundTripsSettings;
var
  Page: TAtlasKeysPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Settings.CompletionKey := $6048;
  Settings.CompletionKeyPriority := True;
  Settings.CheckKeyPriority := True;
  Page := TAtlasKeysPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.AreEqual(ShortCutToText($6048), Page.KeyEdit(2).Text);
    Assert.AreEqual('', Page.KeyEdit(3).Text, 'Parameter-Hint: Taste der IDE');
    // Diagnosemodus (#479) als sechste Zeile mit eigener Vorgabe.
    Assert.AreEqual(ShortCutToText($E044), Page.KeyEdit(5).Text);
    Page.KeyEdit(5).Text := ShortCutToText($6044);
    // Neue Taste für die Befehlspalette eintippen.
    Page.KeyEdit(0).Text := ShortCutToText($6050);
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
  finally
    Page.Free;
  end;
  Assert.AreEqual($6048, Saved.CompletionKey);
  Assert.IsTrue(Saved.CompletionKeyPriority);
  Assert.IsTrue(Saved.CheckKeyPriority);
  Assert.AreEqual($6050, Saved.PaletteKey);
  Assert.AreEqual(0, Saved.SignatureKey);
  Assert.AreEqual($6044, Saved.DiagnosticModeKey);
end;

procedure TAtlasKeysPageTests.ShowsOwnerAndChoice;
var
  Page: TAtlasKeysPage;
begin
  Page := TAtlasKeysPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Page.OwnerOf :=
      function(AShortCut: Word): string
      begin
        if AShortCut = TAtlasKeyConflicts.PaletteDefault then
          Result := 'IDE: Makro'
        else
          Result := '';
      end;
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.KeysStatusLeft, ['IDE: Makro']), Page.StatusLabel(0).Caption);
    Assert.AreEqual(Ord(TAtlasKeyChoice.LeaveOther), Page.ChoiceBox(0).Choice);
    Assert.IsTrue(Page.ChoiceBox(0).Enabled);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.KeysStatusFree), Page.StatusLabel(1).Caption);
    Assert.IsFalse(Page.ChoiceBox(1).Enabled, 'freie Taste: nichts zu entscheiden');
    Page.ChoiceBox(0).Choice := Ord(TAtlasKeyChoice.UseAtlas);
    Page.ChoiceBox(0).OnChange(Page.ChoiceBox(0));
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.KeysStatusAtlasWins, ['IDE: Makro']), Page.StatusLabel(0).Caption);
    Page.KeyEdit(1).Text := 'kein Kürzel';
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.KeysInvalid, ['kein Kürzel']), Page.StatusLabel(1).Caption);
  finally
    Page.Free;
  end;
end;

procedure TAtlasKeysPageTests.UseAtlasTakesIdeKey;
var
  Page: TAtlasKeysPage;
  Saved: TAtlasPluginSettings;
begin
  Page := TAtlasKeysPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.KeysStatusIdeKey,
      [ShortCutToText(TAtlasKeyConflicts.IdeSignatureKey)]), Page.StatusLabel(3).Caption);
    Page.ChoiceBox(3).Choice := Ord(TAtlasKeyChoice.UseAtlas);
    Page.ChoiceBox(3).OnChange(Page.ChoiceBox(3));
    Assert.AreEqual(ShortCutToText(TAtlasKeyConflicts.IdeSignatureKey), Page.KeyEdit(3).Text);
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
  finally
    Page.Free;
  end;
  Assert.AreEqual(Integer(TAtlasKeyConflicts.IdeSignatureKey), Saved.SignatureKey);
  Assert.IsTrue(Saved.SignatureKeyPriority);
end;

procedure TAtlasKeysPageTests.ListsForeignCompletions;
var
  Page: TAtlasKeysPage;
begin
  Page := TAtlasKeysPage.Create(nil);
  try
    Page.ShowForeignCompletions(['CnPack']);
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.KeysForeign, ['CnPack']), Page.ForeignLabel.Caption);
  finally
    Page.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasKeysPageTests);

end.
