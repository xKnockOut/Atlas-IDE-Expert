unit Atlas.Core.Tasks.PreBuild.Tests;

// Tests für Projektaufgaben vor dem Build (#900): welche Compiles Aufgaben
// auslösen, warn und block, Freischein nach bestandenem Lauf, laufende
// Aufgaben, Aufgeben.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTaskPreBuildTests = class
  public
    [Test]
    procedure OnlyUserBuildsOfMakeBuildCheck;
    [Test]
    procedure WarnRunsAlongsideBlockCancelsAndPasses;
    [Test]
    procedure FailedOrAbandonedRunGivesNoPass;
    [Test]
    procedure PassExpiresAndBelongsToTheProject;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Build.Events,
  Atlas.Core.Tasks.PreBuild;

function Project(const AFileName: string; AKind: TAtlasCompileKind): TAtlasCompileProject;
begin
  Result := Default(TAtlasCompileProject);
  Result.FileName := AFileName;
  Result.Kind := AKind;
end;

{ TAtlasTaskPreBuildTests }

procedure TAtlasTaskPreBuildTests.OnlyUserBuildsOfMakeBuildCheck;
var
  Item: TAtlasCompileProject;
begin
  Assert.IsTrue(TAtlasTaskPreBuild.Applies(Project('C:\p\A.dproj', TAtlasCompileKind.Make)));
  Assert.IsTrue(TAtlasTaskPreBuild.Applies(Project('C:\p\A.dproj', TAtlasCompileKind.Build)));
  Assert.IsTrue(TAtlasTaskPreBuild.Applies(Project('C:\p\A.dproj', TAtlasCompileKind.Check)));
  Assert.IsFalse(TAtlasTaskPreBuild.Applies(Project('C:\p\A.dproj', TAtlasCompileKind.Clean)));
  Assert.IsFalse(TAtlasTaskPreBuild.Applies(Project('C:\p\A.dproj', TAtlasCompileKind.MakeUnit)));
  Assert.IsFalse(TAtlasTaskPreBuild.Applies(Project('', TAtlasCompileKind.Make)), 'ohne Projekt');
  Item := Project('C:\p\A.dproj', TAtlasCompileKind.Make);
  Item.Background := True;
  Assert.IsFalse(TAtlasTaskPreBuild.Applies(Item), 'Hintergrundprüfung von Atlas');
  Item.Background := False;
  Item.RequestedBy := 'mcp';
  Assert.IsFalse(TAtlasTaskPreBuild.Applies(Item), 'Build für Claude Code');
end;

procedure TAtlasTaskPreBuildTests.WarnRunsAlongsideBlockCancelsAndPasses;
var
  Gate: TAtlasTaskPreBuild;
  A: TAtlasCompileProject;
begin
  A := Project('C:\p\A.dproj', TAtlasCompileKind.Make);
  Gate := TAtlasTaskPreBuild.Create;
  try
    Assert.IsTrue(Gate.Decide(A, False, False, 0) = TAtlasTaskPreBuildAction.None, 'ohne check-Aufgaben');
    Assert.IsTrue(Gate.Decide(A, False, True, 0) = TAtlasTaskPreBuildAction.StartWarn);
    Assert.IsTrue(Gate.Running);
    Assert.IsTrue(Gate.Decide(A, False, True, 10) = TAtlasTaskPreBuildAction.None, 'warn läuft schon');
    Assert.IsTrue(Gate.Decide(A, True, False, 10) = TAtlasTaskPreBuildAction.Busy, 'block wartet nicht');
    Assert.IsFalse(Gate.Finish(True, 20), 'warn baut nicht neu');
    Assert.IsTrue(Gate.Decide(A, True, True, 30) = TAtlasTaskPreBuildAction.StartAndCancel);
    Assert.IsTrue(Gate.Blocking);
    Assert.AreEqual('C:\p\A.dproj', Gate.Project.FileName);
    Assert.IsTrue(Gate.Finish(True, 40), 'bestanden: neu bauen');
    Assert.IsFalse(Gate.Running);
    Assert.IsTrue(Gate.Decide(A, True, True, 50) = TAtlasTaskPreBuildAction.None, 'Freischein');
    Assert.IsTrue(Gate.Decide(A, True, True, 60) = TAtlasTaskPreBuildAction.StartAndCancel,
      'der Freischein gilt einmal');
  finally
    Gate.Free;
  end;
end;

procedure TAtlasTaskPreBuildTests.FailedOrAbandonedRunGivesNoPass;
var
  Gate: TAtlasTaskPreBuild;
  A: TAtlasCompileProject;
begin
  A := Project('C:\p\A.dproj', TAtlasCompileKind.Build);
  Gate := TAtlasTaskPreBuild.Create;
  try
    Gate.Decide(A, True, False, 0);
    Assert.IsFalse(Gate.Finish(False, 10), 'Verstoß: Build bleibt abgebrochen');
    Assert.IsTrue(Gate.Decide(A, True, False, 20) = TAtlasTaskPreBuildAction.StartAndCancel);
    Gate.Abandon;
    Assert.IsFalse(Gate.Running);
    Assert.IsFalse(Gate.Finish(True, 30), 'nach Aufgeben nichts mehr');
    Assert.IsTrue(Gate.Decide(A, True, False, 40) = TAtlasTaskPreBuildAction.StartAndCancel);
  finally
    Gate.Free;
  end;
end;

procedure TAtlasTaskPreBuildTests.PassExpiresAndBelongsToTheProject;
var
  Gate: TAtlasTaskPreBuild;
  A, B: TAtlasCompileProject;
begin
  A := Project('C:\p\A.dproj', TAtlasCompileKind.Make);
  B := Project('C:\p\B.dproj', TAtlasCompileKind.Make);
  Gate := TAtlasTaskPreBuild.Create;
  try
    Gate.Decide(A, True, False, 0);
    Gate.Finish(True, 1000);
    Assert.IsTrue(Gate.Decide(B, True, False, 1100) = TAtlasTaskPreBuildAction.StartAndCancel, 'anderes Projekt');
    Gate.Finish(False, 1200);
    Assert.IsTrue(Gate.Decide(A, True, False, 1000 + TAtlasTaskPreBuild.PassMs + 1) =
      TAtlasTaskPreBuildAction.StartAndCancel, 'abgelaufen');
  finally
    Gate.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTaskPreBuildTests);

end.
