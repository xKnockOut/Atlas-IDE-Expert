unit Atlas.Core.Build.CheckOnSave.Tests;

// Tests für die Compilerprüfung nach dem Speichern (#548): Entprellung,
// Sperre während eines Builds (auch zwischen den Projekten einer Gruppe)
// und Abschaltung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasCheckOnSaveTests = class
  public
    [Test]
    procedure DebouncesSaves;
    [Test]
    procedure WaitsForBuildAndDebugger;
    [Test]
    procedure WaitsForWholeGroup;
    [Test]
    procedure WaitsForOverlappingProjects;
    [Test]
    procedure SlowCheckDisablesProject;
    [Test]
    procedure BelongsByModuleOrProjectSource;
  end;

implementation

uses
  Atlas.Core.Build.IdleGate,
  Atlas.Core.Build.CheckOnSave;

{ TAtlasCheckOnSaveTests }

procedure TAtlasCheckOnSaveTests.DebouncesSaves;
var
  mCheck: TAtlasCheckOnSave;
begin
  mCheck := TAtlasCheckOnSave.Create(2000, 1500);
  try
    Assert.IsFalse(mCheck.Due(10000, False));
    mCheck.Saved('C:\P\A.dproj', 11000);
    Assert.IsFalse(mCheck.Due(12999, False));
    // Weiteres Speichern verschiebt die Prüfung.
    mCheck.Saved('C:\P\A.dproj', 12500);
    Assert.IsFalse(mCheck.Due(14000, False));
    Assert.IsTrue(mCheck.Due(14500, False));
    Assert.AreEqual('C:\P\A.dproj', mCheck.Take);
    Assert.IsFalse(mCheck.Due(19000, False));
  finally
    mCheck.Free;
  end;
end;

procedure TAtlasCheckOnSaveTests.WaitsForBuildAndDebugger;
var
  mCheck: TAtlasCheckOnSave;
begin
  mCheck := TAtlasCheckOnSave.Create(100, 1500);
  try
    mCheck.Saved('C:\P\A.dproj', 10000);
    mCheck.ProjectStarted(10050);
    Assert.IsFalse(mCheck.Due(11000, False));
    mCheck.ProjectFinished(11000);
    // Ruhezeit nach dem Build: Die IDE räumt noch auf (Fortschrittsdialog, Packages).
    Assert.IsFalse(mCheck.Due(11000 + TAtlasBuildIdleGate.cQuietMs - 1, False));
    Assert.IsFalse(mCheck.Due(11000 + TAtlasBuildIdleGate.cQuietMs, True));
    Assert.IsTrue(mCheck.Due(11000 + TAtlasBuildIdleGate.cQuietMs, False));
  finally
    mCheck.Free;
  end;
end;

procedure TAtlasCheckOnSaveTests.WaitsForWholeGroup;
var
  mCheck: TAtlasCheckOnSave;
begin
  mCheck := TAtlasCheckOnSave.Create(100, 1500);
  try
    mCheck.Saved('C:\P\A.dproj', 10000);
    mCheck.GroupStarted(10010);
    mCheck.ProjectStarted(10020);
    mCheck.ProjectFinished(12000);
    // Das erste Projekt der Gruppe ist fertig, die Gruppe läuft weiter: keine Prüfung mitten im Gruppen-Build.
    Assert.IsFalse(mCheck.Due(60000, False));
    mCheck.ProjectStarted(60000);
    mCheck.ProjectFinished(70000);
    Assert.IsFalse(mCheck.Due(90000, False));
    Assert.IsFalse(mCheck.BuildIdle(90000));
    mCheck.GroupFinished(90000);
    Assert.IsFalse(mCheck.Due(90001, False));
    Assert.IsTrue(mCheck.Due(90000 + TAtlasBuildIdleGate.cQuietMs, False));
  finally
    mCheck.Free;
  end;
end;

procedure TAtlasCheckOnSaveTests.WaitsForOverlappingProjects;
var
  mCheck: TAtlasCheckOnSave;
begin
  mCheck := TAtlasCheckOnSave.Create(100, 1500);
  try
    mCheck.Saved('C:\P\A.dproj', 10000);
    mCheck.ProjectStarted(10000);
    mCheck.ProjectStarted(10100);
    mCheck.ProjectFinished(11000);
    // Ein Projekt läuft noch.
    Assert.IsFalse(mCheck.Due(30000, False));
    mCheck.ProjectFinished(30000);
    Assert.IsTrue(mCheck.Due(30000 + TAtlasBuildIdleGate.cQuietMs, False));
  finally
    mCheck.Free;
  end;
end;

procedure TAtlasCheckOnSaveTests.SlowCheckDisablesProject;
var
  mCheck: TAtlasCheckOnSave;
begin
  mCheck := TAtlasCheckOnSave.Create(100, 1500);
  try
    Assert.IsFalse(mCheck.CheckFinished('C:\P\A.dproj', 1500));
    Assert.IsTrue(mCheck.CheckFinished('C:\P\A.dproj', 1501));
    // Nur einmal gemeldet; danach keine Vormerkung mehr für das Projekt.
    Assert.IsFalse(mCheck.CheckFinished('C:\P\A.dproj', 5000));
    mCheck.Saved('c:\p\a.dproj', 10000);
    Assert.IsFalse(mCheck.Due(11000, False));
    // Andere Projekte prüfen weiter.
    mCheck.Saved('C:\P\B.dproj', 10000);
    Assert.IsTrue(mCheck.Due(11000, False));
  finally
    mCheck.Free;
  end;
end;

procedure TAtlasCheckOnSaveTests.BelongsByModuleOrProjectSource;
begin
  Assert.IsTrue(TAtlasCheckOnSave.Belongs('P/A.dproj', ['P/Unit1.pas', 'P/Unit2.pas'], 'p/unit2.PAS'));
  Assert.IsTrue(TAtlasCheckOnSave.Belongs('P/A.dproj', nil, 'P/A.dpr'));
  Assert.IsTrue(TAtlasCheckOnSave.Belongs('P/A.dproj', nil, 'P/A.dpk'));
  Assert.IsFalse(TAtlasCheckOnSave.Belongs('P/A.dproj', ['P/Unit1.pas'], 'P/Other.pas'));
  Assert.IsFalse(TAtlasCheckOnSave.Belongs('P/A.dproj', nil, 'P/B.dpr'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCheckOnSaveTests);

end.