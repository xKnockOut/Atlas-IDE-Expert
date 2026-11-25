unit Atlas.Core.Welcome.QuickActionRuns.Tests;

// Tests des Stands der Schnellaktionen je Projekt (#764): Schlüssel über die Funktion, Ende einer Aktion,
// Testläufe mit Ergebnis und ohne (Schonzeit), Projektaufgaben nur mit passendem Namen.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Welcome.QuickActionRuns;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasQuickActionRunsTests = class
  private
    FRuns: TAtlasQuickActionRuns;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure StateIsKeyedByFunction;
    [Test]
    procedure FinishKeepsStart;
    [Test]
    procedure TestsFinishedUpdatesRow;
    [Test]
    procedure EndTestsReturnsRunningRows;
    [Test]
    procedure TaskFinishedNeedsSameName;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Welcome.QuickActions;

function LowerKey(const AProject: string): string;
begin
  Result := LowerCase(AProject);
end;

procedure TAtlasQuickActionRunsTests.Setup;
begin
  FRuns := TAtlasQuickActionRuns.Create(LowerKey);
end;

procedure TAtlasQuickActionRunsTests.TearDown;
begin
  FRuns.Free;
  FRuns := nil;
end;

procedure TAtlasQuickActionRunsTests.StateIsKeyedByFunction;
begin
  Assert.IsFalse(FRuns.State('C:\A.dproj').Running, 'ohne Aktion Idle');
  FRuns.SetState('C:\A.dproj', TAtlasQuickActionState.Started(TAtlasQuickAction.Build, 100));
  Assert.IsTrue(FRuns.State('c:\a.dproj').Running);
  Assert.IsTrue(FRuns.OtherUsesIde('C:\B.dproj'), 'Build von A sperrt B');
  Assert.IsFalse(FRuns.OtherUsesIde('C:\A.dproj'));
end;

procedure TAtlasQuickActionRunsTests.FinishKeepsStart;
var
  mState: TAtlasQuickActionState;
begin
  FRuns.SetState('A', TAtlasQuickActionState.Started(TAtlasQuickAction.Build, 100));
  FRuns.Finish('A', TAtlasQuickAction.Build, TAtlasQuickActionPhase.Refused, 'Grund');
  mState := FRuns.State('A');
  Assert.IsFalse(mState.Running);
  Assert.AreEqual(Ord(TAtlasQuickActionPhase.Refused), Ord(mState.Phase));
  Assert.AreEqual('Grund', mState.Detail);
  Assert.AreEqual<UInt64>(100, mState.StartedMs);
end;

procedure TAtlasQuickActionRunsTests.TestsFinishedUpdatesRow;
begin
  FRuns.SetState('Zeile', TAtlasQuickActionState.Started(TAtlasQuickAction.Tests, 100));
  FRuns.TestsStarted('T.dproj', 'Zeile');
  Assert.IsTrue(FRuns.TestsPending('t.dproj'));
  Assert.IsFalse(FRuns.TestsFinished('Anderes.dproj', 1, 0));
  Assert.IsTrue(FRuns.TestsFinished('T.dproj', 3, 1));
  Assert.IsFalse(FRuns.TestsPending);
  Assert.IsFalse(FRuns.State('Zeile').Running);
end;

procedure TAtlasQuickActionRunsTests.EndTestsReturnsRunningRows;
var
  mRows: TArray<string>;
begin
  FRuns.SetState('Zeile', TAtlasQuickActionState.Started(TAtlasQuickAction.Tests, 100));
  FRuns.TestsStarted('T.dproj', 'Zeile');
  Assert.AreEqual(0, Integer(Length(FRuns.EndTests(200, 1500))), 'in der Schonzeit');
  mRows := FRuns.EndTests(5000, 1500);
  Assert.AreEqual(1, Integer(Length(mRows)));
  Assert.AreEqual('Zeile', mRows[0]);
  Assert.IsFalse(FRuns.TestsPending);
end;

procedure TAtlasQuickActionRunsTests.TaskFinishedNeedsSameName;
begin
  FRuns.TaskStarted('P', 'Prüfung');
  Assert.IsFalse(FRuns.TaskFinished('P', 'Andere'));
  Assert.IsTrue(FRuns.TaskFinished('p', 'prüfung'));
  Assert.IsFalse(FRuns.TaskFinished('P', 'Prüfung'), 'nur einmal');
  FRuns.TaskStarted('P', 'Prüfung');
  FRuns.TaskDropped('P');
  Assert.IsFalse(FRuns.TaskFinished('P', 'Prüfung'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasQuickActionRunsTests);

end.
