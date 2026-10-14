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
    /// <summary>Die Einstellungen stehen auf Reitern je Bereich statt auf einer langen Seite (#227).</summary>
    [Test]
    procedure GroupsSettingsOnTabs;
  end;

implementation

uses
  Vcl.Forms,
  Vcl.ComCtrls,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Page;

procedure TAtlasSettingsPageTests.WarmUp;
var
  Host: TForm;
  Page: TAtlasSettingsPage;
begin
  TAtlasSettingsPage.Create(nil).Free;
  // Auch mit Fenster (Reiter, PageControl): einmalige VCL-Daten nicht dem ersten Test anrechnen.
  Host := TForm.CreateNew(nil);
  try
    Page := TAtlasSettingsPage.Create(Host);
    Page.Parent := Host;
    Page.HandleNeeded;
  finally
    Host.Free;
  end;
end;

procedure TAtlasSettingsPageTests.GroupsSettingsOnTabs;
var
  Host: TForm;
  Page: TAtlasSettingsPage;
  Sheet: TTabSheet;
  Index: Integer;
begin
  // Wie in der IDE: Die Reiter hängen erst am PageControl, wenn die Seite ein Fenster hat.
  Host := TForm.CreateNew(nil);
  try
    Page := TAtlasSettingsPage.Create(Host);
    Page.Parent := Host;
    Page.HandleNeeded;
    Assert.AreEqual(7, Page.Pages.PageCount);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabGeneral), Page.Pages.Pages[0].Caption);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabRobustness), Page.Pages.Pages[6].Caption);
    for Index := 0 to Page.Pages.PageCount - 1 do
    begin
      Sheet := Page.Pages.Pages[Index];
      Assert.IsTrue(Sheet.ControlCount > 0, Sheet.Caption);
    end;
    Assert.AreEqual(0, Page.Pages.ActivePageIndex);
  finally
    Host.Free;
  end;
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
  Settings.PairGuideOpacity := 70;
  Settings.PairColorsLight := '#0071E3,#007C8A,#C000E0,#008700,#4040FF';
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
  Assert.AreEqual(70, Saved.PairGuideOpacity);
  Assert.AreEqual('#0071E3,#007C8A,#C000E0,#008700,#4040FF', Saved.PairColorsLight);
  Assert.AreEqual('', Saved.PairColorsDark, 'Standardfarben bleiben leer');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsPageTests);

end.