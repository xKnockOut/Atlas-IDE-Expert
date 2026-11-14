unit Atlas.Core.Build.IdleGate.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasBuildIdleGateTests = class
  public
    [Test]
    procedure WaitsQuietTimeAfterCreate;
    [Test]
    procedure BusyWhileProjectCompiles;
    [Test]
    procedure BusyDuringGroupBetweenProjects;
    [Test]
    procedure FinishWithoutStartAfterReload;
    [Test]
    procedure GroupFinishedClearsOpenProjects;
  end;

implementation

uses
  Atlas.Core.Build.IdleGate;

const
  cQuiet = TAtlasBuildIdleGate.cQuietMs;

{ TAtlasBuildIdleGateTests }

procedure TAtlasBuildIdleGateTests.WaitsQuietTimeAfterCreate;
var
  mGate: TAtlasBuildIdleGate;
begin
  // Nach dem (Neu-)Laden erst Ruhe abwarten: Ein laufender Gruppen-Build meldet sich mit dem nächsten Projekt.
  mGate := TAtlasBuildIdleGate.Create(1000);
  try
    Assert.IsFalse(mGate.Idle(1000));
    Assert.IsFalse(mGate.Idle(1000 + cQuiet - 1));
    Assert.IsTrue(mGate.Idle(1000 + cQuiet));
  finally
    mGate.Free;
  end;
end;

procedure TAtlasBuildIdleGateTests.BusyWhileProjectCompiles;
var
  mGate: TAtlasBuildIdleGate;
begin
  mGate := TAtlasBuildIdleGate.Create(0);
  try
    mGate.ProjectStarted(10000);
    Assert.IsFalse(mGate.Idle(10000 + 10 * cQuiet), 'Compile läuft');
    mGate.ProjectFinished(50000);
    Assert.IsFalse(mGate.Idle(50000 + cQuiet - 1));
    Assert.IsTrue(mGate.Idle(50000 + cQuiet));
  finally
    mGate.Free;
  end;
end;

procedure TAtlasBuildIdleGateTests.BusyDuringGroupBetweenProjects;
var
  mGate: TAtlasBuildIdleGate;
begin
  mGate := TAtlasBuildIdleGate.Create(0);
  try
    mGate.GroupStarted(10000);
    mGate.ProjectStarted(10000);
    mGate.ProjectFinished(11000);
    // Zwischen zwei Projekten der Gruppe: kein Projekt aktiv, die Gruppe aber schon.
    Assert.IsFalse(mGate.Idle(11000 + 10 * cQuiet));
    mGate.GroupFinished(20000);
    Assert.IsFalse(mGate.Idle(20000 + cQuiet - 1));
    Assert.IsTrue(mGate.Idle(20000 + cQuiet));
  finally
    mGate.Free;
  end;
end;

procedure TAtlasBuildIdleGateTests.FinishWithoutStartAfterReload;
var
  mGate: TAtlasBuildIdleGate;
begin
  // Neu geladen mitten im Compile: Das Ende kommt ohne Anfang und darf nicht unter null zählen.
  mGate := TAtlasBuildIdleGate.Create(0);
  try
    mGate.ProjectFinished(5000);
    mGate.ProjectStarted(6000);
    Assert.IsFalse(mGate.Idle(6000 + cQuiet));
    mGate.ProjectFinished(7000);
    Assert.IsTrue(mGate.Idle(7000 + cQuiet));
  finally
    mGate.Free;
  end;
end;

procedure TAtlasBuildIdleGateTests.GroupFinishedClearsOpenProjects;
var
  mGate: TAtlasBuildIdleGate;
begin
  // Abgebrochene Gruppe: Ein Projekt ohne ProjectFinished hält die Sperre nicht fest.
  mGate := TAtlasBuildIdleGate.Create(0);
  try
    mGate.GroupStarted(1000);
    mGate.ProjectStarted(1000);
    mGate.GroupFinished(2000);
    Assert.IsTrue(mGate.Idle(2000 + cQuiet));
  finally
    mGate.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBuildIdleGateTests);

end.
