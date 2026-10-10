unit Argus.UI.Settings.Page.Tests;

// Tests für die Optionsseite (#227): Die IDE erzeugt sie über die Klasse,
// TCustomFrame.Create braucht dafür die DFM-Ressource.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TArgusSettingsPageTests = class
  public
    /// <summary>Erstes Erzeugen von Steuerelementen legt einmalige VCL-Daten an (Themes, Schriften).</summary>
    [SetupFixture]
    procedure WarmUp;
    [Test]
    procedure CreatesAndRoundTripsSettings;
  end;

implementation

uses
  Argus.Core.Settings.Plugin,
  Argus.UI.Settings.Page;

procedure TArgusSettingsPageTests.WarmUp;
begin
  TArgusSettingsPage.Create(nil).Free;
end;

procedure TArgusSettingsPageTests.CreatesAndRoundTripsSettings;
var
  Page: TArgusSettingsPage;
  Settings, Saved: TArgusPluginSettings;
begin
  Settings := TArgusPluginSettings.Defaults;
  Settings.Enabled := False;
  Settings.VisibleRows := 12;
  Settings.Preview := True;
  Settings.HoverTooltip := False;
  Settings.ListWidth := 333;
  Page := TArgusSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Saved := TArgusPluginSettings.Defaults;
    Page.SaveTo(Saved);
  finally
    Page.Free;
  end;
  Assert.IsFalse(Saved.Enabled);
  Assert.AreEqual(12, Saved.VisibleRows);
  Assert.IsTrue(Saved.Preview);
  Assert.IsFalse(Saved.HoverTooltip);
  Assert.AreEqual(333, Saved.ListWidth);
end;

initialization
  TDUnitX.RegisterTestFixture(TArgusSettingsPageTests);

end.