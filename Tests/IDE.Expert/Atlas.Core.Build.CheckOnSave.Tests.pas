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
  Check: TAtlasCheckOnSave;
begin
  Check := TAtlasCheckOnSave.Create(2000, 1500);
  try
    Assert.IsFalse(Check.Due(0, False));
    Check.Saved('C:\P\A.dproj', 1000);
    Assert.IsFalse(Check.Due(2999, False));
    // Weiteres Speichern verschiebt die Prüfung.
    Check.Saved('C:\P\A.dproj', 2500);
    Assert.IsFalse(Check.Due(4000, False));
    Assert.IsTrue(Check.Due(4500, False));
    Assert.AreEqual('C:\P\A.dproj', Check.Take);
    Assert.IsFalse(Check.Due(9000, False));
  finally
    Check.Free;
  end;
end;

procedure TAtlasCheckOnSaveTests.WaitsForBuildAndDebugger;
var
  Check: TAtlasCheckOnSave;
begin
  Check := TAtlasCheckOnSave.Create(100, 1500);
  try
    Check.Saved('C:\P\A.dproj', 0);
    Check.BuildStarted;
    Assert.IsFalse(Check.Due(1000, False));
    Check.BuildFinished;
    Assert.IsFalse(Check.Due(1000, True));
    Assert.IsTrue(Check.Due(1000, False));
  finally
    Check.Free;
  end;
end;

procedure TAtlasCheckOnSaveTests.SlowCheckDisablesProject;
var
  Check: TAtlasCheckOnSave;
begin
  Check := TAtlasCheckOnSave.Create(100, 1500);
  try
    Assert.IsFalse(Check.CheckFinished('C:\P\A.dproj', 1500));
    Assert.IsTrue(Check.CheckFinished('C:\P\A.dproj', 1501));
    // Nur einmal gemeldet; danach keine Vormerkung mehr für das Projekt.
    Assert.IsFalse(Check.CheckFinished('C:\P\A.dproj', 5000));
    Check.Saved('c:\p\a.dproj', 0);
    Assert.IsFalse(Check.Due(1000, False));
    // Andere Projekte prüfen weiter.
    Check.Saved('C:\P\B.dproj', 0);
    Assert.IsTrue(Check.Due(1000, False));
  finally
    Check.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCheckOnSaveTests);

end.