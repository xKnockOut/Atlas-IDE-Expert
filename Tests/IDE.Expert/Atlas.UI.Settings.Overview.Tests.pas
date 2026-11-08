unit Atlas.UI.Settings.Overview.Tests;

// Übersicht „Atlas“ im Optionsdialog (#1903): Stand der Packages, Suche und Klick auf Treffer.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSettingsOverviewTests = class
  public
    /// <summary>Katalog und Texte einmal vorab anlegen: Ihr Zwischenspeicher zählt sonst als Leck im ersten Test.
    /// </summary>
    [SetupFixture]
    procedure WarmUp;
    [Test]
    procedure ShowsPackages;
    [Test]
    procedure HitClickOpensNodeOfSetting;
    [Test]
    procedure PackagesClickOpensModules;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Settings.Overview;

procedure TAtlasSettingsOverviewTests.WarmUp;
begin
  with TAtlasSettingsOverview.Create(nil) do
  try
    Load(1, 1, 1);
    SearchFor('enabled');
  finally
    Free;
  end;
end;

procedure TAtlasSettingsOverviewTests.ShowsPackages;
var
  mPage: TAtlasSettingsOverview;
begin
  mPage := TAtlasSettingsOverview.Create(nil);
  try
    mPage.Load(12, 13, 11);
    Assert.Contains(mPage.PackagesText, '12');
    Assert.Contains(mPage.PackagesText, '11');
  finally
    mPage.Free;
  end;
end;

procedure TAtlasSettingsOverviewTests.HitClickOpensNodeOfSetting;
var
  mPage: TAtlasSettingsOverview;
  mSetting, mSwitch: string;
begin
  mSetting := '-';
  mPage := TAtlasSettingsOverview.Create(nil);
  try
    mPage.OnOpen :=
      procedure(ASetting, ASwitch: string)
      begin
        mSetting := ASetting;
        mSwitch := ASwitch;
      end;
    mPage.SearchFor('completion.enabled');
    Assert.IsTrue(Length(mPage.HitTexts) > 0);
    mPage.ClickHit(0);
    Assert.AreEqual('Enabled', mSetting);
    Assert.AreEqual('', mSwitch, 'gehört Base');
  finally
    mPage.Free;
  end;
end;

procedure TAtlasSettingsOverviewTests.PackagesClickOpensModules;
var
  mSetting: string;
begin
  mSetting := '-';
  with TAtlasSettingsOverview.Create(nil) do
  try
    OnOpen :=
      procedure(ASetting, ASwitch: string)
      begin
        mSetting := ASetting;
      end;
    ClickPackages;
    Assert.AreEqual('', mSetting, 'Knoten Module');
  finally
    Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsOverviewTests);

end.
