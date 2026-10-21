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
  Quiet = TAtlasBuildIdleGate.QuietMs;

{ TAtlasBuildIdleGateTests }

procedure TAtlasBuildIdleGateTests.WaitsQuietTimeAfterCreate;
var
  Gate: TAtlasBuildIdleGate;
begin
  // Nach dem (Neu-)Laden erst Ruhe abwarten: Ein laufender Gruppen-Build meldet sich mit dem nächsten Projekt.
  Gate := TAtlasBuildIdleGate.Create(1000);
  try
    Assert.IsFalse(Gate.Idle(1000));
    Assert.IsFalse(Gate.Idle(1000 + Quiet - 1));
    Assert.IsTrue(Gate.Idle(1000 + Quiet));
  finally
    Gate.Free;
  end;
end;

procedure TAtlasBuildIdleGateTests.BusyWhileProjectCompiles;
var
  Gate: TAtlasBuildIdleGate;
begin
  Gate := TAtlasBuildIdleGate.Create(0);
  try
    Gate.ProjectStarted(10000);
    Assert.IsFalse(Gate.Idle(10000 + 10 * Quiet), 'Compile läuft');
    Gate.ProjectFinished(50000);
    Assert.IsFalse(Gate.Idle(50000 + Quiet - 1));
    Assert.IsTrue(Gate.Idle(50000 + Quiet));
  finally
    Gate.Free;
  end;
end;

procedure TAtlasBuildIdleGateTests.BusyDuringGroupBetweenProjects;
var
  Gate: TAtlasBuildIdleGate;
begin
  Gate := TAtlasBuildIdleGate.Create(0);
  try
    Gate.GroupStarted(10000);
    Gate.ProjectStarted(10000);
    Gate.ProjectFinished(11000);
    // Zwischen zwei Projekten der Gruppe: kein Projekt aktiv, die Gruppe aber schon.
    Assert.IsFalse(Gate.Idle(11000 + 10 * Quiet));
    Gate.GroupFinished(20000);
    Assert.IsFalse(Gate.Idle(20000 + Quiet - 1));
    Assert.IsTrue(Gate.Idle(20000 + Quiet));
  finally
    Gate.Free;
  end;
end;

procedure TAtlasBuildIdleGateTests.FinishWithoutStartAfterReload;
var
  Gate: TAtlasBuildIdleGate;
begin
  // Neu geladen mitten im Compile: Das Ende kommt ohne Anfang und darf nicht unter null zählen.
  Gate := TAtlasBuildIdleGate.Create(0);
  try
    Gate.ProjectFinished(5000);
    Gate.ProjectStarted(6000);
    Assert.IsFalse(Gate.Idle(6000 + Quiet));
    Gate.ProjectFinished(7000);
    Assert.IsTrue(Gate.Idle(7000 + Quiet));
  finally
    Gate.Free;
  end;
end;

procedure TAtlasBuildIdleGateTests.GroupFinishedClearsOpenProjects;
var
  Gate: TAtlasBuildIdleGate;
begin
  // Abgebrochene Gruppe: Ein Projekt ohne ProjectFinished hält die Sperre nicht fest.
  Gate := TAtlasBuildIdleGate.Create(0);
  try
    Gate.GroupStarted(1000);
    Gate.ProjectStarted(1000);
    Gate.GroupFinished(2000);
    Assert.IsTrue(Gate.Idle(2000 + Quiet));
  finally
    Gate.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBuildIdleGateTests);

end.
