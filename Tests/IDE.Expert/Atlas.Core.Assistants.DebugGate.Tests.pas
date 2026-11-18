unit Atlas.Core.Assistants.DebugGate.Tests;

// Tests für Rechte, Pause und Sitzung beim Debuggen durch KI-Assistenten (#1874) und das Warten auf den nächsten
// Halt, ohne IDE.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Assistants.DebugGate;

type
  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasDebugGateTests = class
  private
    FGate: TAtlasDebugGate;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure PauseRefusesEverything;
    [Test]
    procedure RefusesUserSessionUnlessAttach;
    [Test]
    procedure OwnSessionAllowsSteps;
    [Test]
    procedure StepsNeedAStoppedProgram;
    [Test]
    procedure EvaluateNeedsRights;
    [Test]
    procedure FindsAssignmentsOutsideStrings;
    [Test]
    procedure EndsOwnSessionWhenDebuggerStops;
    [Test]
    procedure TakeOverDisconnectsAssistant;
    [Test]
    procedure CountsStepsAndLastTool;
    [Test]
    procedure WaitEndsOnNewStopEndOrDeadline;
    [Test]
    procedure WaitForLaunchIgnoresDebuggerBeforeStart;
  end;

implementation

uses
  Atlas.Core.DebugControl.Types,
  Atlas.Core.Assistants.DebugInbox;

function Request(ACommand: TAtlasDebugCommand): TAtlasDebugRequest;
begin
  Result := Default(TAtlasDebugRequest);
  Result.Command := ACommand;
end;

function Evaluate(const AExpression: string; ASideEffects: Boolean): TAtlasDebugRequest;
begin
  Result := Request(TAtlasDebugCommand.Evaluate);
  Result.Expression := AExpression;
  Result.SideEffects := ASideEffects;
end;

function NoRights: TAtlasDebugRights;
begin
  Result := TAtlasDebugRights.Make(False, False, False);
end;

{ TAtlasDebugGateTests }

procedure TAtlasDebugGateTests.Setup;
begin
  FGate := TAtlasDebugGate.Create;
end;

procedure TAtlasDebugGateTests.TearDown;
begin
  FGate.Free;
  FGate := nil;
end;

procedure TAtlasDebugGateTests.PauseRefusesEverything;
begin
  FGate.SetPaused(True);
  Assert.AreEqual(Ord(TAtlasDebugRefusal.Paused), Ord(FGate.Refusal(Request(TAtlasDebugCommand.State),
    TAtlasDebugControlPhase.None, NoRights)));
  FGate.SetPaused(False);
  Assert.AreEqual(Ord(TAtlasDebugRefusal.None), Ord(FGate.Refusal(Request(TAtlasDebugCommand.State),
    TAtlasDebugControlPhase.None, NoRights)));
end;

procedure TAtlasDebugGateTests.RefusesUserSessionUnlessAttach;
begin
  Assert.AreEqual(Ord(TAtlasDebugRefusal.UserSession), Ord(FGate.Refusal(Request(TAtlasDebugCommand.State),
    TAtlasDebugControlPhase.Running, NoRights)));
  Assert.AreEqual(Ord(TAtlasDebugRefusal.UserSession), Ord(FGate.Refusal(Request(TAtlasDebugCommand.SetBreakpoint),
    TAtlasDebugControlPhase.Stopped, NoRights)));
  Assert.AreEqual(Ord(TAtlasDebugRefusal.None), Ord(FGate.Refusal(Request(TAtlasDebugCommand.Step),
    TAtlasDebugControlPhase.Stopped, TAtlasDebugRights.Make(False, False, True))), 'mit attach');
  Assert.AreEqual(Ord(TAtlasDebugRefusal.AlreadyRunning), Ord(FGate.Refusal(Request(TAtlasDebugCommand.Start),
    TAtlasDebugControlPhase.Stopped, TAtlasDebugRights.Make(False, False, True))));
end;

procedure TAtlasDebugGateTests.OwnSessionAllowsSteps;
begin
  Assert.AreEqual(Ord(TAtlasDebugRefusal.None), Ord(FGate.Refusal(Request(TAtlasDebugCommand.Start),
    TAtlasDebugControlPhase.None, NoRights)));
  FGate.Launched('S1');
  Assert.IsTrue(FGate.Own);
  Assert.AreEqual('S1', FGate.Session);
  Assert.AreEqual(Ord(TAtlasDebugRefusal.None), Ord(FGate.Refusal(Request(TAtlasDebugCommand.Step),
    TAtlasDebugControlPhase.Stopped, NoRights)));
  Assert.AreEqual(Ord(TAtlasDebugRefusal.AlreadyRunning), Ord(FGate.Refusal(Request(TAtlasDebugCommand.Start),
    TAtlasDebugControlPhase.Running, NoRights)));
end;

procedure TAtlasDebugGateTests.StepsNeedAStoppedProgram;
begin
  Assert.AreEqual(Ord(TAtlasDebugRefusal.NoProgram), Ord(FGate.Refusal(Request(TAtlasDebugCommand.Resume),
    TAtlasDebugControlPhase.None, NoRights)));
  FGate.Launched('S1');
  Assert.AreEqual(Ord(TAtlasDebugRefusal.NotStopped), Ord(FGate.Refusal(Request(TAtlasDebugCommand.Step),
    TAtlasDebugControlPhase.Running, NoRights)));
  Assert.AreEqual(Ord(TAtlasDebugRefusal.NotStopped), Ord(FGate.Refusal(Evaluate('X', False),
    TAtlasDebugControlPhase.Running, NoRights)));
  Assert.AreEqual(Ord(TAtlasDebugRefusal.None), Ord(FGate.Refusal(Request(TAtlasDebugCommand.Stop),
    TAtlasDebugControlPhase.Running, NoRights)), 'beenden geht immer');
  Assert.AreEqual(Ord(TAtlasDebugRefusal.None), Ord(FGate.Refusal(Request(TAtlasDebugCommand.SetBreakpoint),
    TAtlasDebugControlPhase.Running, NoRights)));
end;

procedure TAtlasDebugGateTests.EvaluateNeedsRights;
begin
  FGate.Launched('S1');
  Assert.AreEqual(Ord(TAtlasDebugRefusal.None), Ord(FGate.Refusal(Evaluate('Liste.Count', False),
    TAtlasDebugControlPhase.Stopped, NoRights)));
  Assert.AreEqual(Ord(TAtlasDebugRefusal.SideEffects), Ord(FGate.Refusal(Evaluate('Liste.Get(0)', True),
    TAtlasDebugControlPhase.Stopped, NoRights)));
  Assert.AreEqual(Ord(TAtlasDebugRefusal.None), Ord(FGate.Refusal(Evaluate('Liste.Get(0)', True),
    TAtlasDebugControlPhase.Stopped, TAtlasDebugRights.Make(True, False, False))));
  Assert.AreEqual(Ord(TAtlasDebugRefusal.Modify), Ord(FGate.Refusal(Evaluate('I := 3', False),
    TAtlasDebugControlPhase.Stopped, TAtlasDebugRights.Make(True, False, False))));
  Assert.AreEqual(Ord(TAtlasDebugRefusal.None), Ord(FGate.Refusal(Evaluate('I := 3', False),
    TAtlasDebugControlPhase.Stopped, TAtlasDebugRights.Make(False, True, False))));
end;

procedure TAtlasDebugGateTests.FindsAssignmentsOutsideStrings;
begin
  Assert.IsTrue(TAtlasDebugGate.Assigns('X:=1'));
  Assert.IsTrue(TAtlasDebugGate.Assigns('S := ''a'''));
  Assert.IsFalse(TAtlasDebugGate.Assigns('S = '':='''));
  Assert.IsFalse(TAtlasDebugGate.Assigns('A >= B'));
  Assert.IsFalse(TAtlasDebugGate.Assigns(''));
end;

procedure TAtlasDebugGateTests.EndsOwnSessionWhenDebuggerStops;
begin
  FGate.Launched('S1');
  Assert.AreEqual('running', FGate.StateName(TAtlasDebugControlPhase.Running));
  FGate.Observe(TAtlasDebugControlPhase.Running);
  Assert.IsTrue(FGate.Own);
  FGate.Observe(TAtlasDebugControlPhase.None);
  Assert.IsFalse(FGate.Own);
  Assert.AreEqual('terminated', FGate.StateName(TAtlasDebugControlPhase.None));
  FGate.Launched('S2');
  Assert.AreEqual('stopped', FGate.StateName(TAtlasDebugControlPhase.Stopped));
end;

procedure TAtlasDebugGateTests.TakeOverDisconnectsAssistant;
begin
  FGate.Launched('S1');
  FGate.TakeOver;
  Assert.IsFalse(FGate.Own);
  Assert.AreEqual('', FGate.Session);
  Assert.AreEqual(Ord(TAtlasDebugRefusal.UserSession), Ord(FGate.Refusal(Request(TAtlasDebugCommand.Step),
    TAtlasDebugControlPhase.Stopped, NoRights)), 'Sitzung gehört jetzt dem Benutzer');
  Assert.AreEqual('none', FGate.StateName(TAtlasDebugControlPhase.None));
end;

procedure TAtlasDebugGateTests.CountsStepsAndLastTool;
var
  mRequest: TAtlasDebugRequest;
begin
  mRequest := Request(TAtlasDebugCommand.Start);
  mRequest.Client := 'Agent';
  FGate.Note(mRequest);
  FGate.Launched('S1');
  FGate.Note(Request(TAtlasDebugCommand.Step));
  FGate.Note(Request(TAtlasDebugCommand.Resume));
  FGate.Note(Request(TAtlasDebugCommand.Evaluate));
  Assert.AreEqual(2, FGate.Steps);
  Assert.AreEqual('debug_evaluate', FGate.LastTool);
  Assert.AreEqual('Agent', FGate.Client, 'Name bleibt ohne neuen');
end;

procedure TAtlasDebugGateTests.WaitEndsOnNewStopEndOrDeadline;
var
  mWait: TAtlasDebugWait;
begin
  mWait := TAtlasDebugWait.Start(4, 1000, 2, False);
  Assert.IsFalse(mWait.Done(TAtlasDebugControlPhase.Running, 4, 1500));
  Assert.IsFalse(mWait.Done(TAtlasDebugControlPhase.Stopped, 4, 1500), 'noch der alte Halt');
  Assert.IsTrue(mWait.Done(TAtlasDebugControlPhase.Stopped, 5, 1600), 'neuer Halt');
  mWait := TAtlasDebugWait.Start(4, 1000, 2, False);
  Assert.IsTrue(mWait.Done(TAtlasDebugControlPhase.None, 4, 1100), 'Programm beendet');
  mWait := TAtlasDebugWait.Start(4, 1000, 2, False);
  Assert.IsTrue(mWait.Done(TAtlasDebugControlPhase.Running, 4, 3000), 'Frist');
  mWait := TAtlasDebugWait.Start(4, 1000, 0, False);
  Assert.IsTrue(mWait.Done(TAtlasDebugControlPhase.Running, 4, 1000), 'ohne Warten');
end;

procedure TAtlasDebugGateTests.WaitForLaunchIgnoresDebuggerBeforeStart;
var
  mWait: TAtlasDebugWait;
begin
  mWait := TAtlasDebugWait.Start(0, 0, 10, True);
  Assert.IsFalse(mWait.Done(TAtlasDebugControlPhase.None, 0, 100), 'Prozess noch nicht angelegt');
  Assert.IsFalse(mWait.Done(TAtlasDebugControlPhase.Running, 0, 200));
  Assert.IsTrue(mWait.Done(TAtlasDebugControlPhase.None, 0, 300), 'gelaufen und beendet');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDebugGateTests);

end.
