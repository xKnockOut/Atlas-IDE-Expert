unit Atlas.Core.CodeInsight.Plan.Tests;

// Entscheidungen des Code Insight-Managers (Atlas.Core.CodeInsight.Plan): Zeichen, Dateien, Start der Sitzung,
// Absturz, Prüfung der Server-Exe, Neustarts und Reihenfolge der Projekte.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCodeInsightPlanTests = class
  public
    [Test]
    procedure KeysThatAskCodeInsight;
    [Test]
    procedure TokenCharsWithDotWhenPrevalidating;
    [Test]
    procedure HandlesPascalSourcesOnly;
    [Test]
    procedure EnsureNestedOutsideMainOrWhileStarting;
    [Test]
    procedure EnsureReadyStartOrHeld;
    [Test]
    procedure NestedResultNoSessionAfterShutdownInMain;
    [Test]
    procedure CrashedOnlyWhenServerEndedItself;
    [Test]
    procedure ServerCheckFirstAndAfterInterval;
    [Test]
    procedure RestartsAfterFirstStart;
    [Test]
    procedure ActiveProjectFirst;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.CodeInsight.Plan;

function MainState: TAtlasSessionState;
begin
  Result := Default(TAtlasSessionState);
  Result.Main := True;
end;

{ TCodeInsightPlanTests }

procedure TCodeInsightPlanTests.KeysThatAskCodeInsight;
begin
  Assert.IsTrue(TAtlasCodeInsightPlan.AllowsKey(#0));
  Assert.IsTrue(TAtlasCodeInsightPlan.AllowsKey('.'));
  Assert.IsTrue(TAtlasCodeInsightPlan.AllowsKey('('));
  Assert.IsTrue(TAtlasCodeInsightPlan.AllowsKey(','));
  Assert.IsTrue(TAtlasCodeInsightPlan.AllowsKey('<'));
  Assert.IsTrue(TAtlasCodeInsightPlan.AllowsKey('['));
  Assert.IsTrue(TAtlasCodeInsightPlan.AllowsKey(#3));
  Assert.IsFalse(TAtlasCodeInsightPlan.AllowsKey('a'));
  Assert.IsFalse(TAtlasCodeInsightPlan.AllowsKey(';'));
end;

procedure TCodeInsightPlanTests.TokenCharsWithDotWhenPrevalidating;
begin
  Assert.IsTrue(CharInSet('_', TAtlasCodeInsightPlan.TokenChars(False)));
  Assert.IsTrue(CharInSet('&', TAtlasCodeInsightPlan.TokenChars(False)));
  Assert.IsFalse(CharInSet('.', TAtlasCodeInsightPlan.TokenChars(False)));
  Assert.IsTrue(CharInSet('.', TAtlasCodeInsightPlan.TokenChars(True)));
end;

procedure TCodeInsightPlanTests.HandlesPascalSourcesOnly;
begin
  Assert.IsTrue(TAtlasCodeInsightPlan.HandlesExtension('C:\Src\Main.PAS'));
  Assert.IsTrue(TAtlasCodeInsightPlan.HandlesExtension('Project.dpr'));
  Assert.IsTrue(TAtlasCodeInsightPlan.HandlesExtension('Package.dpk'));
  Assert.IsTrue(TAtlasCodeInsightPlan.HandlesExtension('Defines.inc'));
  Assert.IsFalse(TAtlasCodeInsightPlan.HandlesExtension('Form.dfm'));
  Assert.IsFalse(TAtlasCodeInsightPlan.HandlesExtension('Project.dproj'));
end;

procedure TCodeInsightPlanTests.EnsureNestedOutsideMainOrWhileStarting;
var
  mState: TAtlasSessionState;
begin
  mState := MainState;
  mState.Main := False;
  mState.Ready := True;
  Assert.AreEqual<TAtlasSessionEnsure>(TAtlasSessionEnsure.Nested, TAtlasCodeInsightPlan.Ensure(mState));
  mState := MainState;
  mState.Starting := True;
  Assert.AreEqual<TAtlasSessionEnsure>(TAtlasSessionEnsure.Nested, TAtlasCodeInsightPlan.Ensure(mState));
  mState := MainState;
  mState.Stopping := True;
  Assert.AreEqual<TAtlasSessionEnsure>(TAtlasSessionEnsure.Nested, TAtlasCodeInsightPlan.Ensure(mState));
  mState := MainState;
  mState.ShutDown := True;
  Assert.AreEqual<TAtlasSessionEnsure>(TAtlasSessionEnsure.Nested, TAtlasCodeInsightPlan.Ensure(mState));
end;

procedure TCodeInsightPlanTests.EnsureReadyStartOrHeld;
var
  mState: TAtlasSessionState;
begin
  mState := MainState;
  Assert.AreEqual<TAtlasSessionEnsure>(TAtlasSessionEnsure.Start, TAtlasCodeInsightPlan.Ensure(mState));
  mState.Held := True;
  Assert.AreEqual<TAtlasSessionEnsure>(TAtlasSessionEnsure.Held, TAtlasCodeInsightPlan.Ensure(mState));
  // Eine bereite Sitzung zählt vor dem Anhalten.
  mState.Ready := True;
  Assert.AreEqual<TAtlasSessionEnsure>(TAtlasSessionEnsure.Ready, TAtlasCodeInsightPlan.Ensure(mState));
end;

procedure TCodeInsightPlanTests.NestedResultNoSessionAfterShutdownInMain;
var
  mState: TAtlasSessionState;
begin
  mState := MainState;
  mState.Running := True;
  Assert.IsTrue(TAtlasCodeInsightPlan.NestedResult(mState));
  mState.ShutDown := True;
  Assert.IsFalse(TAtlasCodeInsightPlan.NestedResult(mState));
  mState.Main := False;
  Assert.IsTrue(TAtlasCodeInsightPlan.NestedResult(mState), 'Hintergrund-Thread bekommt, was läuft');
  mState.Running := False;
  Assert.IsFalse(TAtlasCodeInsightPlan.NestedResult(mState));
end;

procedure TCodeInsightPlanTests.CrashedOnlyWhenServerEndedItself;
begin
  Assert.IsTrue(TAtlasCodeInsightPlan.Crashed(True, False));
  Assert.IsFalse(TAtlasCodeInsightPlan.Crashed(True, True));
  Assert.IsFalse(TAtlasCodeInsightPlan.Crashed(False, False));
end;

procedure TCodeInsightPlanTests.ServerCheckFirstAndAfterInterval;
begin
  Assert.IsTrue(TAtlasCodeInsightPlan.ServerCheckDue(False, 0));
  Assert.IsFalse(TAtlasCodeInsightPlan.ServerCheckDue(True, TAtlasCodeInsightPlan.cServerCheckMs));
  Assert.IsTrue(TAtlasCodeInsightPlan.ServerCheckDue(True, TAtlasCodeInsightPlan.cServerCheckMs + 1));
end;

procedure TCodeInsightPlanTests.RestartsAfterFirstStart;
begin
  Assert.AreEqual(0, TAtlasCodeInsightPlan.Restarts(0));
  Assert.AreEqual(0, TAtlasCodeInsightPlan.Restarts(1));
  Assert.AreEqual(2, TAtlasCodeInsightPlan.Restarts(3));
end;

procedure TCodeInsightPlanTests.ActiveProjectFirst;
var
  mOrder: TArray<string>;
begin
  mOrder := TAtlasCodeInsightPlan.ProjectOrder('C:\B.dproj', True,
    TArray<string>.Create('C:\A.dproj', 'c:\b.dproj', 'C:\C.dproj'));
  Assert.AreEqual(3, Integer(Length(mOrder)));
  Assert.AreEqual('C:\B.dproj', mOrder[0]);
  Assert.AreEqual('C:\A.dproj', mOrder[1]);
  Assert.AreEqual('C:\C.dproj', mOrder[2]);
  // Aktives Projekt ungespeichert oder keins: nur die gespeicherten in ihrer Reihenfolge.
  mOrder := TAtlasCodeInsightPlan.ProjectOrder('Project1.dproj', False, TArray<string>.Create('C:\A.dproj'));
  Assert.AreEqual(1, Integer(Length(mOrder)));
  Assert.AreEqual('C:\A.dproj', mOrder[0]);
  Assert.AreEqual(1, Integer(Length(TAtlasCodeInsightPlan.ProjectOrder('', False,
    TArray<string>.Create('C:\A.dproj')))));
end;

end.
