unit Atlas.Core.Tasks.PreBuild.Tests;

// Tests für Projektaufgaben vor dem Build (#900): welche Compiles Aufgaben
// auslösen, warn und block, Freischein nach bestandenem Lauf, laufende
// Aufgaben, Aufgeben.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Build')]
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
  mItem: TAtlasCompileProject;
begin
  Assert.IsTrue(TAtlasTaskPreBuild.Applies(Project('C:\p\A.dproj', TAtlasCompileKind.Make)));
  Assert.IsTrue(TAtlasTaskPreBuild.Applies(Project('C:\p\A.dproj', TAtlasCompileKind.Build)));
  Assert.IsTrue(TAtlasTaskPreBuild.Applies(Project('C:\p\A.dproj', TAtlasCompileKind.Check)));
  Assert.IsFalse(TAtlasTaskPreBuild.Applies(Project('C:\p\A.dproj', TAtlasCompileKind.Clean)));
  Assert.IsFalse(TAtlasTaskPreBuild.Applies(Project('C:\p\A.dproj', TAtlasCompileKind.MakeUnit)));
  Assert.IsFalse(TAtlasTaskPreBuild.Applies(Project('', TAtlasCompileKind.Make)), 'ohne Projekt');
  mItem := Project('C:\p\A.dproj', TAtlasCompileKind.Make);
  mItem.Background := True;
  Assert.IsFalse(TAtlasTaskPreBuild.Applies(mItem), 'Hintergrundprüfung von Atlas');
  mItem.Background := False;
  mItem.RequestedBy := 'mcp';
  Assert.IsFalse(TAtlasTaskPreBuild.Applies(mItem), 'Build für Claude Code');
end;

procedure TAtlasTaskPreBuildTests.WarnRunsAlongsideBlockCancelsAndPasses;
var
  mGate: TAtlasTaskPreBuild;
  A: TAtlasCompileProject;
begin
  A := Project('C:\p\A.dproj', TAtlasCompileKind.Make);
  mGate := TAtlasTaskPreBuild.Create;
  try
    Assert.IsTrue(mGate.Decide(A, False, False, 0) = TAtlasTaskPreBuildAction.None, 'ohne check-Aufgaben');
    Assert.IsTrue(mGate.Decide(A, False, True, 0) = TAtlasTaskPreBuildAction.StartWarn);
    Assert.IsTrue(mGate.Running);
    Assert.IsTrue(mGate.Decide(A, False, True, 10) = TAtlasTaskPreBuildAction.None, 'warn läuft schon');
    Assert.IsTrue(mGate.Decide(A, True, False, 10) = TAtlasTaskPreBuildAction.Busy, 'block wartet nicht');
    Assert.IsFalse(mGate.Finish(True, 20), 'warn baut nicht neu');
    Assert.IsTrue(mGate.Decide(A, True, True, 30) = TAtlasTaskPreBuildAction.StartAndCancel);
    Assert.IsTrue(mGate.Blocking);
    Assert.AreEqual('C:\p\A.dproj', mGate.Project.FileName);
    Assert.IsTrue(mGate.Finish(True, 40), 'bestanden: neu bauen');
    Assert.IsFalse(mGate.Running);
    Assert.IsTrue(mGate.Decide(A, True, True, 50) = TAtlasTaskPreBuildAction.None, 'Freischein');
    Assert.IsTrue(mGate.Decide(A, True, True, 60) = TAtlasTaskPreBuildAction.StartAndCancel,
      'der Freischein gilt einmal');
  finally
    mGate.Free;
  end;
end;

procedure TAtlasTaskPreBuildTests.FailedOrAbandonedRunGivesNoPass;
var
  mGate: TAtlasTaskPreBuild;
  A: TAtlasCompileProject;
begin
  A := Project('C:\p\A.dproj', TAtlasCompileKind.Build);
  mGate := TAtlasTaskPreBuild.Create;
  try
    mGate.Decide(A, True, False, 0);
    Assert.IsFalse(mGate.Finish(False, 10), 'Verstoß: Build bleibt abgebrochen');
    Assert.IsTrue(mGate.Decide(A, True, False, 20) = TAtlasTaskPreBuildAction.StartAndCancel);
    mGate.Abandon;
    Assert.IsFalse(mGate.Running);
    Assert.IsFalse(mGate.Finish(True, 30), 'nach Aufgeben nichts mehr');
    Assert.IsTrue(mGate.Decide(A, True, False, 40) = TAtlasTaskPreBuildAction.StartAndCancel);
  finally
    mGate.Free;
  end;
end;

procedure TAtlasTaskPreBuildTests.PassExpiresAndBelongsToTheProject;
var
  mGate: TAtlasTaskPreBuild;
  A, B: TAtlasCompileProject;
begin
  A := Project('C:\p\A.dproj', TAtlasCompileKind.Make);
  B := Project('C:\p\B.dproj', TAtlasCompileKind.Make);
  mGate := TAtlasTaskPreBuild.Create;
  try
    mGate.Decide(A, True, False, 0);
    mGate.Finish(True, 1000);
    Assert.IsTrue(mGate.Decide(B, True, False, 1100) = TAtlasTaskPreBuildAction.StartAndCancel, 'anderes Projekt');
    mGate.Finish(False, 1200);
    Assert.IsTrue(mGate.Decide(A, True, False, 1000 + TAtlasTaskPreBuild.cPassMs + 1) =
      TAtlasTaskPreBuildAction.StartAndCancel, 'abgelaufen');
  finally
    mGate.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTaskPreBuildTests);

end.
