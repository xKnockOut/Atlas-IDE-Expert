unit Atlas.UI.Settings.Page.Tests;

// Tests für die Optionsseite (#227): Die IDE erzeugt sie über die Klasse,
// TCustomFrame.Create braucht dafür die DFM-Ressource.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSettingsPageTests = class
  public
    /// <summary>Erstes Erzeugen von Steuerelementen legt einmalige VCL-Daten an (Themes, Schriften).</summary>
    [SetupFixture]
    procedure WarmUp;
    [Test]
    procedure CreatesAndRoundTripsSettings;
  end;

implementation

uses
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.Page;

procedure TAtlasSettingsPageTests.WarmUp;
begin
  TAtlasSettingsPage.Create(nil).Free;
end;

procedure TAtlasSettingsPageTests.CreatesAndRoundTripsSettings;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Settings.Enabled := False;
  Settings.VisibleRows := 12;
  Settings.Preview := True;
  Settings.HoverTooltip := False;
  Settings.ListWidth := 333;
  Settings.PairOwners := False;
  Settings.PairGuideWidth := 3;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
  finally
    Page.Free;
  end;
  Assert.IsFalse(Saved.Enabled);
  Assert.AreEqual(12, Saved.VisibleRows);
  Assert.IsTrue(Saved.Preview);
  Assert.IsFalse(Saved.HoverTooltip);
  Assert.AreEqual(333, Saved.ListWidth);
  Assert.IsFalse(Saved.PairOwners);
  Assert.AreEqual(3, Saved.PairGuideWidth);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsPageTests);

end.