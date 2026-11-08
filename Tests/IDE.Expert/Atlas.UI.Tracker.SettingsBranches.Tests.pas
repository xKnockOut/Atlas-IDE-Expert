unit Atlas.UI.Tracker.SettingsBranches.Tests;

// Unterpunkt „Versionsverwaltung“ des Issue-Trackers (#1903): gehört dem Tracker, nur mit Versionsverwaltung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasTrackerBranchSectionTests = class
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure BelongsToTracker;
    [Test]
    procedure OnlyWithVersionControl;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Settings.Contract,
  Atlas.UI.Tracker.SettingsBranches;

procedure TAtlasTrackerBranchSectionTests.TearDown;
begin
  TAtlasTrackerBranchSection.Available := nil;
end;

procedure TAtlasTrackerBranchSectionTests.BelongsToTracker;
var
  mSection: IAtlasSettingsSection;
begin
  mSection := TAtlasTrackerBranchSection.Create;
  Assert.AreEqual('atlas.tracker', mSection.OwnerId);
  Assert.AreEqual('issues', mSection.AreaId);
  mSection.Close;
end;

procedure TAtlasTrackerBranchSectionTests.OnlyWithVersionControl;
var
  mProvider: IAtlasSettingsSectionProvider;
  mSection: IAtlasSettingsSection;
begin
  mProvider := TAtlasTrackerBranchProvider.Create;
  Assert.IsNull(mProvider.CreateSection, 'ohne Abfrage kein Abschnitt');
  TAtlasTrackerBranchSection.Available :=
    function: Boolean
    begin
      Result := False;
    end;
  Assert.IsNull(mProvider.CreateSection, 'ohne Versionsverwaltung kein Abschnitt');
  TAtlasTrackerBranchSection.Available :=
    function: Boolean
    begin
      Result := True;
    end;
  mSection := mProvider.CreateSection;
  Assert.IsNotNull(mSection);
  mSection.Close;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerBranchSectionTests);

end.
