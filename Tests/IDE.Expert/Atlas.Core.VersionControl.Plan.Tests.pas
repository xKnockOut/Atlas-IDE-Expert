unit Atlas.Core.VersionControl.Plan.Tests;

// Tests für die Entscheidungen der Versionsverwaltung in der IDE (#571,
// #1288): Zeitlimit, Zustand ohne Prozess, Ort der Suche und der Abschluss
// von „Branch anlegen“.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.VersionControl')]
  TAtlasVcsPlanTests = class
  public
    /// <summary>Das größere der beiden Zeitlimits.</summary>
    [Test]
    procedure AtLeastTakesLarger;
    /// <summary>Aus, keine Arbeitskopie, Programm fehlt, bereit.</summary>
    [Test]
    procedure LocalOutcomeInOrder;
    /// <summary>Ort aus dem Dialog unter „^/“, sonst die Vorgabe.</summary>
    [Test]
    procedure SearchLocationPrefersDialog;
    /// <summary>Reihenfolge: vorhanden, Ordner belegt, angelegt, Rückfrage, gescheitert.</summary>
    [Test]
    procedure BranchFinishInOrder;
  end;

implementation

uses
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.Plan;

{ TAtlasVcsPlanTests }

procedure TAtlasVcsPlanTests.AtLeastTakesLarger;
begin
  Assert.AreEqual(Int64(30000), Int64(TAtlasVcsPlan.AtLeast(10000, 30000)));
  Assert.AreEqual(Int64(60000), Int64(TAtlasVcsPlan.AtLeast(60000, 30000)));
end;

procedure TAtlasVcsPlanTests.LocalOutcomeInOrder;
begin
  Assert.AreEqual(Ord(TAtlasVcsOutcome.Disabled), Ord(TAtlasVcsPlan.LocalOutcome(TAtlasVcsProvider.Off,
    TAtlasVcsKind.Git, TAtlasVcsKind.Git)), 'aus');
  Assert.AreEqual(Ord(TAtlasVcsOutcome.NoWorkingCopy), Ord(TAtlasVcsPlan.LocalOutcome(TAtlasVcsProvider.Auto,
    TAtlasVcsKind.None, TAtlasVcsKind.Git)));
  Assert.AreEqual(Ord(TAtlasVcsOutcome.ToolMissing), Ord(TAtlasVcsPlan.LocalOutcome(TAtlasVcsProvider.Git,
    TAtlasVcsKind.Git, TAtlasVcsKind.None)));
  Assert.AreEqual(Ord(TAtlasVcsOutcome.Ok), Ord(TAtlasVcsPlan.LocalOutcome(TAtlasVcsProvider.Svn,
    TAtlasVcsKind.Svn, TAtlasVcsKind.Svn)));
end;

procedure TAtlasVcsPlanTests.SearchLocationPrefersDialog;
begin
  Assert.AreEqual('^/branches', TAtlasVcsPlan.SearchLocation('branches', '^/feature'));
  Assert.AreEqual('^/feature', TAtlasVcsPlan.SearchLocation('', '^/feature'));
end;

procedure TAtlasVcsPlanTests.BranchFinishInOrder;
begin
  Assert.AreEqual(Ord(TAtlasVcsBranchFinish.Exists), Ord(TAtlasVcsPlan.BranchFinish(True, True, True, True, True)));
  Assert.AreEqual(Ord(TAtlasVcsBranchFinish.FolderTaken),
    Ord(TAtlasVcsPlan.BranchFinish(False, True, True, True, True)));
  Assert.AreEqual(Ord(TAtlasVcsBranchFinish.Created), Ord(TAtlasVcsPlan.BranchFinish(False, False, True, True, True)));
  Assert.AreEqual(Ord(TAtlasVcsBranchFinish.OfferLocal),
    Ord(TAtlasVcsPlan.BranchFinish(False, False, False, True, True)));
  Assert.AreEqual(Ord(TAtlasVcsBranchFinish.Failed), Ord(TAtlasVcsPlan.BranchFinish(False, False, False, False, True)),
    'zweiter Lauf fragt nicht');
  Assert.AreEqual(Ord(TAtlasVcsBranchFinish.Failed), Ord(TAtlasVcsPlan.BranchFinish(False, False, False, True, False)),
    'anderer Fehler');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasVcsPlanTests);

end.
