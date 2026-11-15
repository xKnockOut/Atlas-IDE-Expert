unit Atlas.Core.Debug.EventBreakWatch.Tests;

// Tests für den Ablauf von „Beim nächsten Ereignis anhalten“ (#856, #1967): Art des Setzens, Pause, neuer Halt,
// Zahl der Stellen, Zähler im Dialog, Sender und Antworten der Auswertung; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasEventBreakWatchTests = class
  public
    [Test]
    procedure ArmWayFollowsScopeAndState;
    [Test]
    procedure PauseStopsOrTimesOut;
    [Test]
    procedure StoppedAnewAfterRunOrElsewhere;
    [Test]
    procedure StartWhileRunning;
    [Test]
    procedure CountOfLocations;
    [Test]
    procedure CountChoiceTreatsVisibleAsAll;
    [Test]
    procedure SenderOnlyForSharedHandler;
    [Test]
    procedure ReadsEvaluatedValues;
  end;

implementation

uses
  Atlas.Core.Debug.EventBreak,
  Atlas.Core.Debug.EventBreakWatch;

{ TAtlasEventBreakWatchTests }

procedure TAtlasEventBreakWatchTests.ArmWayFollowsScopeAndState;
begin
  Assert.AreEqual<TAtlasEventArmWay>(TAtlasEventArmWay.Direct,
    TAtlasEventBreakWatch.ArmWay(TAtlasEventScope.AllForms, False));
  Assert.AreEqual<TAtlasEventArmWay>(TAtlasEventArmWay.Direct,
    TAtlasEventBreakWatch.ArmWay(TAtlasEventScope.OneForm, True));
  Assert.AreEqual<TAtlasEventArmWay>(TAtlasEventArmWay.VisibleNow,
    TAtlasEventBreakWatch.ArmWay(TAtlasEventScope.VisibleForms, True));
  Assert.AreEqual<TAtlasEventArmWay>(TAtlasEventArmWay.PauseFirst,
    TAtlasEventBreakWatch.ArmWay(TAtlasEventScope.VisibleForms, False));
end;

procedure TAtlasEventBreakWatchTests.PauseStopsOrTimesOut;
begin
  Assert.AreEqual<TAtlasEventPauseOutcome>(TAtlasEventPauseOutcome.Stopped,
    TAtlasEventBreakWatch.PauseOutcome(True, 5000, 3000));
  Assert.AreEqual<TAtlasEventPauseOutcome>(TAtlasEventPauseOutcome.Waiting,
    TAtlasEventBreakWatch.PauseOutcome(False, 2999, 3000));
  Assert.AreEqual<TAtlasEventPauseOutcome>(TAtlasEventPauseOutcome.TimedOut,
    TAtlasEventBreakWatch.PauseOutcome(False, 3000, 3000));
end;

procedure TAtlasEventBreakWatchTests.StoppedAnewAfterRunOrElsewhere;
var
  mWatch: TAtlasEventWatch;
begin
  mWatch := Default(TAtlasEventWatch);
  mWatch.Start(True, 'Unit1.pas', 10);
  Assert.AreEqual<TAtlasEventWatchPhase>(TAtlasEventWatchPhase.Watching, mWatch.Phase);
  // Noch am Start, nie gelaufen: kein neuer Halt.
  Assert.IsFalse(mWatch.StoppedAnew('UNIT1.PAS', 10));
  Assert.IsTrue(mWatch.StoppedAnew('Unit1.pas', 11));
  Assert.IsTrue(mWatch.StoppedAnew('Unit2.pas', 10));
  mWatch.Running;
  Assert.IsTrue(mWatch.StoppedAnew('Unit1.pas', 10));
end;

procedure TAtlasEventBreakWatchTests.StartWhileRunning;
var
  mWatch: TAtlasEventWatch;
begin
  mWatch := Default(TAtlasEventWatch);
  mWatch.Start(False, 'Unit1.pas', 10);
  Assert.IsTrue(mWatch.SeenRunning);
  Assert.AreEqual('', mWatch.StartFile);
  Assert.AreEqual(-1, mWatch.StartLine);
end;

procedure TAtlasEventBreakWatchTests.CountOfLocations;
begin
  Assert.AreEqual<TAtlasEventArmCount>(TAtlasEventArmCount.Empty, TAtlasEventBreakWatch.ArmCount(0));
  Assert.AreEqual<TAtlasEventArmCount>(TAtlasEventArmCount.Normal,
    TAtlasEventBreakWatch.ArmCount(TAtlasEventBreak.cManyBreakpoints));
  Assert.AreEqual<TAtlasEventArmCount>(TAtlasEventArmCount.Many,
    TAtlasEventBreakWatch.ArmCount(TAtlasEventBreak.cManyBreakpoints + 1));
end;

procedure TAtlasEventBreakWatchTests.CountChoiceTreatsVisibleAsAll;
var
  mChoice: TAtlasEventChoice;
begin
  mChoice := TAtlasEventChoice.Defaults;
  mChoice.Scope := TAtlasEventScope.VisibleForms;
  Assert.AreEqual<TAtlasEventScope>(TAtlasEventScope.AllForms, TAtlasEventBreakWatch.CountChoice(mChoice).Scope);
  mChoice.Scope := TAtlasEventScope.OneForm;
  mChoice.Form := 'TForm1';
  Assert.AreEqual<TAtlasEventScope>(TAtlasEventScope.OneForm, TAtlasEventBreakWatch.CountChoice(mChoice).Scope);
  Assert.AreEqual('TForm1', TAtlasEventBreakWatch.CountChoice(mChoice).Form);
end;

procedure TAtlasEventBreakWatchTests.SenderOnlyForSharedHandler;
var
  mLocation: TAtlasEventLocation;
begin
  mLocation := Default(TAtlasEventLocation);
  mLocation.Handlers := [3];
  Assert.IsFalse(TAtlasEventBreakWatch.NeedsSender(mLocation));
  mLocation.Handlers := [3, 4];
  Assert.IsTrue(TAtlasEventBreakWatch.NeedsSender(mLocation));
end;

procedure TAtlasEventBreakWatchTests.ReadsEvaluatedValues;
var
  mCount: Integer;
begin
  Assert.IsTrue(TAtlasEventBreakWatch.FormCount(' 3 ', mCount));
  Assert.AreEqual(3, mCount);
  Assert.IsTrue(TAtlasEventBreakWatch.FormCount('0', mCount));
  Assert.IsFalse(TAtlasEventBreakWatch.FormCount('-1', mCount));
  Assert.IsFalse(TAtlasEventBreakWatch.FormCount('?', mCount));
  Assert.IsTrue(TAtlasEventBreakWatch.IsTrue(' true'));
  Assert.IsFalse(TAtlasEventBreakWatch.IsTrue('False'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasEventBreakWatchTests);

end.
