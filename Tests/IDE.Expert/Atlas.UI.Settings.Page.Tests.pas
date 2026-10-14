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
    [Test]
    procedure ShowsAndReenablesTrippedFeatures;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Diagnostics.Guard,
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
  Settings.XmlDocFull := False;
  Settings.XmlDocMaxLines := 7;
  Settings.ListWidth := 333;
  Settings.ProviderTimeLimitMs := 400;
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
  Assert.IsFalse(Saved.XmlDocFull);
  Assert.AreEqual(7, Saved.XmlDocMaxLines);
  Assert.AreEqual(333, Saved.ListWidth);
  Assert.AreEqual(400, Saved.ProviderTimeLimitMs);
end;

procedure TAtlasSettingsPageTests.ShowsAndReenablesTrippedFeatures;
var
  Page: TAtlasSettingsPage;
  Index: Integer;
begin
  TAtlasGuard.Fuse.ResetAll;
  try
    for Index := 1 to 3 do
    begin
      TAtlasGuard.ReportProvider('Testquelle', 'Fehler');
      TAtlasGuard.Fuse.Failed(TAtlasFeature.Pairs);
    end;
    Page := TAtlasSettingsPage.Create(nil);
    try
      Page.LoadFrom(TAtlasPluginSettings.Defaults);
      Assert.AreEqual(2, Page.FuseList.Items.Count);
      Assert.AreEqual(TAtlasGuard.FeatureName(TAtlasFeature.Pairs), Page.FuseList.Items[0]);
      Assert.AreEqual('Testquelle', Page.FuseList.Items[1]);
      Assert.IsTrue(Page.FuseEnableAll.Enabled);
      // Nur die Quelle wieder einschalten.
      Page.FuseList.Selected[1] := True;
      Page.FuseEnableSelected.Click;
      Assert.IsFalse(TAtlasGuard.ProviderDisabled('Testquelle'));
      Assert.IsTrue(TAtlasGuard.Disabled(TAtlasFeature.Pairs));
      Page.FuseEnableAll.Click;
      Assert.IsFalse(TAtlasGuard.Disabled(TAtlasFeature.Pairs));
      Assert.AreEqual(1, Page.FuseList.Items.Count, 'nur der Hinweis „keine“');
      Assert.IsFalse(Page.FuseEnableAll.Enabled);
    finally
      Page.Free;
    end;
  finally
    TAtlasGuard.Fuse.ResetAll;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsPageTests);

end.