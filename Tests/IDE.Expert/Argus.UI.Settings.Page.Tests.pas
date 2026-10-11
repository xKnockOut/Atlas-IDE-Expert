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
    /// <summary>Die Einstellungen stehen auf Reitern je Bereich statt auf einer langen Seite.</summary>
    [Test]
    procedure GroupsSettingsOnTabs;
  end;

implementation

uses
  Vcl.ComCtrls,
  Argus.Core.Settings.Plugin,
  Argus.UI.Strings,
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

procedure TArgusSettingsPageTests.GroupsSettingsOnTabs;
var
  Page: TArgusSettingsPage;
  Sheet: TTabSheet;
  I: Integer;
begin
  Page := TArgusSettingsPage.Create(nil);
  try
    Assert.AreEqual(5, Page.Pages.PageCount);
    Assert.AreEqual(TArgusStrings.Text(TArgusTextId.SettingsTabGeneral), Page.Pages.Pages[0].Caption);
    Assert.AreEqual(TArgusStrings.Text(TArgusTextId.SettingsTabRobustness), Page.Pages.Pages[4].Caption);
    for I := 0 to Page.Pages.PageCount - 1 do
    begin
      Sheet := Page.Pages.Pages[I];
      Assert.IsTrue(Sheet.ControlCount > 0, Sheet.Caption);
    end;
    Assert.AreEqual(0, Page.Pages.ActivePageIndex);
  finally
    Page.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TArgusSettingsPageTests);

end.