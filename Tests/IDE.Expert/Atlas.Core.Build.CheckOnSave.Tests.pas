unit Atlas.Core.Build.CheckOnSave.Tests;

// Tests für die Compilerprüfung nach dem Speichern (#548): Entprellung,
// Sperre während eines Builds und Abschaltung.

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
    procedure SlowCheckDisablesProject;
  end;

implementation

uses
  Atlas.Core.Build.CheckOnSave;

procedure TAtlasCheckOnSaveTests.DebouncesSaves;
var
  mCheck: TAtlasCheckOnSave;
begin
  mCheck := TAtlasCheckOnSave.Create(2000, 1500);
  try
    Assert.IsFalse(mCheck.Due(0, False));
    mCheck.Saved('C:\P\A.dproj', 1000);
    Assert.IsFalse(mCheck.Due(2999, False));
    // Weiteres Speichern verschiebt die Prüfung.
    mCheck.Saved('C:\P\A.dproj', 2500);
    Assert.IsFalse(mCheck.Due(4000, False));
    Assert.IsTrue(mCheck.Due(4500, False));
    Assert.AreEqual('C:\P\A.dproj', mCheck.Take);
    Assert.IsFalse(mCheck.Due(9000, False));
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
    mCheck.Saved('C:\P\A.dproj', 0);
    mCheck.BuildStarted;
    Assert.IsFalse(mCheck.Due(1000, False));
    mCheck.BuildFinished;
    Assert.IsFalse(mCheck.Due(1000, True));
    Assert.IsTrue(mCheck.Due(1000, False));
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
    mCheck.Saved('c:\p\a.dproj', 0);
    Assert.IsFalse(mCheck.Due(1000, False));
    // Andere Projekte prüfen weiter.
    mCheck.Saved('C:\P\B.dproj', 0);
    Assert.IsTrue(mCheck.Due(1000, False));
  finally
    mCheck.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCheckOnSaveTests);

end.