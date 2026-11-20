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

{ TAtlasTrackerBranchSectionTests }

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
begin
  Assert.IsFalse(TAtlasTrackerBranchSection.IsAvailable, 'ohne Abfrage kein Abschnitt');
  TAtlasTrackerBranchSection.Available :=
    function: Boolean
    begin
      Result := False;
    end;
  Assert.IsFalse(TAtlasTrackerBranchSection.IsAvailable, 'ohne Versionsverwaltung kein Abschnitt');
  TAtlasTrackerBranchSection.Available :=
    function: Boolean
    begin
      Result := True;
    end;
  Assert.IsTrue(TAtlasTrackerBranchSection.IsAvailable);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerBranchSectionTests);

end.
