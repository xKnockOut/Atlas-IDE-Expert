unit Atlas.Core.Debug.BreakpointRules.Tests;

// Tests für abhängige Haltepunkte und Trefferbedingungen (#864) ohne IDE:
// Zählung, Trefferbedingungen, Thread-Filter, Zustandsfolge abhängiger
// Haltepunkte, Speichern und Laden, Mitziehen beim Verschieben.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.BreakpointRules;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasBreakpointRulesTests = class
  public
    [Test]
    procedure HitConditions;
    /// <summary>Akzeptanzkriterium: „bei jedem 5. Treffer“ hält in einer Schleife über 20 Elemente viermal.</summary>
    [Test]
    procedure EveryFifthStopsFourTimes;
    /// <summary>Akzeptanzkriterium: „nur im Hauptthread“ hält nicht im Worker-Thread.</summary>
    [Test]
    procedure MainThreadOnly;
    [Test]
    procedure ThreadNameAndId;
    /// <summary>Akzeptanzkriterien: abhängig hält erst nach dem Auslöser; „nur einmal“ erst nach erneutem Auslösen.
    /// </summary>
    [Test]
    procedure DependentOnce;
    [Test]
    procedure DependentUntilEnd;
    [Test]
    procedure JsonRoundTrip;
    [Test]
    procedure PutAndMove;
    /// <summary>Akzeptanzkriterium: Aufruf aus B hält, aus A nicht; der Stapel lässt den Rahmen des Haltepunkts
    /// selbst aus.</summary>
    [Test]
    procedure CallerAnywhere;
    /// <summary>Akzeptanzkriterium: „nur direkter Aufrufer“ unterscheidet B → Hilfsroutine → Ziel von B → Ziel.
    /// </summary>
    [Test]
    procedure CallerDirect;
    /// <summary>Akzeptanzkriterium: „beim 2. Treffer“ zählt nur passende Aufrufe.</summary>
    [Test]
    procedure CallerAndHitCount;
    [Test]
    procedure CallerJsonOldAndNew;
  end;

implementation

uses
  System.SysUtils;

const
  cMain = 100;
  cWorker = 200;
  cLoop = 20;
  cEvery = 5;

function Rule: TAtlasBreakpointRule;
begin
  Result := Default(TAtlasBreakpointRule);
  Result.FileName := 'C:\Src\Kunden.pas';
  Result.Line := 41;
end;

function MainStop: TAtlasStopThread;
begin
  Result := TAtlasStopThread.Create('Main', cMain, cMain);
end;

/// <summary>Halt im Hauptthread mit dem Stapel ARoutines (Routine des Haltepunkts zuerst).</summary>
function StackStop(const ARoutines: array of string): TAtlasStopThread;
var
  mIndex: Integer;
begin
  Result := MainStop;
  SetLength(Result.Routines, Length(ARoutines));
  for mIndex := 0 to High(ARoutines) do
  begin
    Result.Routines[mIndex] := ARoutines[mIndex];
  end;
end;

function CallerRule(const ACaller: string; ADirect: Boolean): TAtlasBreakpointRule;
begin
  Result := Rule;
  Result.Caller := ACaller;
  Result.CallerDirect := ADirect;
end;

{ TAtlasBreakpointRulesTests }

procedure TAtlasBreakpointRulesTests.HitConditions;
begin
  Assert.IsTrue(TAtlasBreakpointRules.HitMatches(TAtlasHitMode.Any, 3, 1));
  Assert.IsTrue(TAtlasBreakpointRules.HitMatches(TAtlasHitMode.Exactly, 3, 3));
  Assert.IsFalse(TAtlasBreakpointRules.HitMatches(TAtlasHitMode.Exactly, 3, 4));
  Assert.IsFalse(TAtlasBreakpointRules.HitMatches(TAtlasHitMode.AtLeast, 3, 2));
  Assert.IsTrue(TAtlasBreakpointRules.HitMatches(TAtlasHitMode.AtLeast, 3, 7));
  Assert.IsTrue(TAtlasBreakpointRules.HitMatches(TAtlasHitMode.EveryNth, 3, 6));
  Assert.IsFalse(TAtlasBreakpointRules.HitMatches(TAtlasHitMode.EveryNth, 3, 7));
  // Zahl unter 1 gilt als 1.
  Assert.IsTrue(TAtlasBreakpointRules.HitMatches(TAtlasHitMode.EveryNth, 0, 7));
end;

procedure TAtlasBreakpointRulesTests.EveryFifthStopsFourTimes;
var
  mRule: TAtlasBreakpointRule;
  mState: TAtlasRuleState;
  mIndex, mStops: Integer;
begin
  mRule := Rule;
  mRule.Hit := TAtlasHitMode.EveryNth;
  mRule.HitCount := cEvery;
  mState := TAtlasRuleState.Start(mRule);
  mStops := 0;
  for mIndex := 1 to cLoop do
  begin
    if TAtlasBreakpointRules.Decide(mRule, mState, MainStop) = TAtlasRuleDecision.Stop then
    begin
      Inc(mStops);
    end;
  end;
  Assert.AreEqual(cLoop div cEvery, mStops);
  Assert.AreEqual(cLoop, mState.Hits);
end;

procedure TAtlasBreakpointRulesTests.MainThreadOnly;
var
  mRule: TAtlasBreakpointRule;
  mState: TAtlasRuleState;
begin
  mRule := Rule;
  mRule.Thread := TAtlasThreadFilter.MainThread;
  mState := TAtlasRuleState.Start(mRule);
  Assert.AreEqual<TAtlasRuleDecision>(TAtlasRuleDecision.Continue,
    TAtlasBreakpointRules.Decide(mRule, mState, TAtlasStopThread.Create('Worker', cWorker, cMain)));
  Assert.AreEqual(0, mState.Hits, 'Anderer Thread zählt nicht');
  Assert.AreEqual<TAtlasRuleDecision>(TAtlasRuleDecision.Stop, TAtlasBreakpointRules.Decide(mRule, mState, MainStop));
end;

procedure TAtlasBreakpointRulesTests.ThreadNameAndId;
var
  mRule: TAtlasBreakpointRule;
begin
  mRule := Rule;
  mRule.Thread := TAtlasThreadFilter.NameContains;
  mRule.ThreadText := 'import';
  Assert.IsTrue(TAtlasBreakpointRules.ThreadMatches(mRule, TAtlasStopThread.Create('TImportThread', cWorker, cMain)));
  Assert.IsFalse(TAtlasBreakpointRules.ThreadMatches(mRule, MainStop));
  mRule.Thread := TAtlasThreadFilter.ThreadId;
  mRule.ThreadId := cWorker;
  Assert.IsTrue(TAtlasBreakpointRules.ThreadMatches(mRule, TAtlasStopThread.Create('', cWorker, cMain)));
  Assert.IsFalse(TAtlasBreakpointRules.ThreadMatches(mRule, MainStop));
end;

procedure TAtlasBreakpointRulesTests.DependentOnce;
var
  mRule: TAtlasBreakpointRule;
  mState: TAtlasRuleState;
begin
  mRule := Rule;
  mRule.Depend := TAtlasDependMode.Once;
  mRule.TriggerFile := 'C:\Src\Haupt.pas';
  mRule.TriggerLine := 10;
  mState := TAtlasRuleState.Start(mRule);
  // Programmstart: unscharf, ausgeschaltet; ein Halt dort zählt nicht.
  Assert.IsFalse(TAtlasBreakpointRules.ShouldBeEnabled(mRule, mState));
  Assert.AreEqual<TAtlasRuleDecision>(TAtlasRuleDecision.Continue,
    TAtlasBreakpointRules.Decide(mRule, mState, MainStop));
  Assert.IsTrue(mRule.TriggeredBy('c:\src\haupt.pas', 10));
  Assert.IsTrue(TAtlasBreakpointRules.Arm(mRule, mState));
  Assert.IsTrue(TAtlasBreakpointRules.ShouldBeEnabled(mRule, mState));
  Assert.AreEqual<TAtlasRuleDecision>(TAtlasRuleDecision.Stop, TAtlasBreakpointRules.Decide(mRule, mState, MainStop));
  // „nur einmal“: danach wieder unscharf, bis der Auslöser erneut hält.
  Assert.IsFalse(TAtlasBreakpointRules.ShouldBeEnabled(mRule, mState));
  Assert.AreEqual<TAtlasRuleDecision>(TAtlasRuleDecision.Continue,
    TAtlasBreakpointRules.Decide(mRule, mState, MainStop));
  Assert.IsTrue(TAtlasBreakpointRules.Arm(mRule, mState));
  Assert.AreEqual<TAtlasRuleDecision>(TAtlasRuleDecision.Stop, TAtlasBreakpointRules.Decide(mRule, mState, MainStop));
end;

procedure TAtlasBreakpointRulesTests.DependentUntilEnd;
var
  mRule: TAtlasBreakpointRule;
  mState: TAtlasRuleState;
begin
  mRule := Rule;
  mRule.Depend := TAtlasDependMode.UntilEnd;
  mRule.TriggerFile := 'C:\Src\Haupt.pas';
  mState := TAtlasRuleState.Start(mRule);
  Assert.IsTrue(TAtlasBreakpointRules.Arm(mRule, mState));
  Assert.IsFalse(TAtlasBreakpointRules.Arm(mRule, mState), 'Schon scharf');
  Assert.AreEqual<TAtlasRuleDecision>(TAtlasRuleDecision.Stop, TAtlasBreakpointRules.Decide(mRule, mState, MainStop));
  Assert.AreEqual<TAtlasRuleDecision>(TAtlasRuleDecision.Stop, TAtlasBreakpointRules.Decide(mRule, mState, MainStop));
  Assert.IsTrue(TAtlasBreakpointRules.ShouldBeEnabled(mRule, mState));
end;

procedure TAtlasBreakpointRulesTests.JsonRoundTrip;
var
  mRule: TAtlasBreakpointRule;
  mRules: TAtlasBreakpointRuleList;
begin
  mRule := Rule;
  mRule.Hit := TAtlasHitMode.AtLeast;
  mRule.HitCount := 3;
  mRule.Thread := TAtlasThreadFilter.NameContains;
  mRule.ThreadText := 'Import';
  mRule.Depend := TAtlasDependMode.Once;
  mRule.TriggerFile := 'C:\Src\Haupt.pas';
  mRule.TriggerLine := 10;
  Assert.IsTrue(TAtlasBreakpointRules.Parse(TAtlasBreakpointRules.ToJson([mRule, Rule]), mRules));
  // Die leere Regel fällt weg.
  Assert.AreEqual(1, Integer(Length(mRules)));
  Assert.AreEqual(41, mRules[0].Line);
  Assert.AreEqual(Ord(TAtlasHitMode.AtLeast), Ord(mRules[0].Hit));
  Assert.AreEqual(3, mRules[0].HitCount);
  Assert.AreEqual(Ord(TAtlasThreadFilter.NameContains), Ord(mRules[0].Thread));
  Assert.AreEqual('Import', mRules[0].ThreadText);
  Assert.AreEqual(Ord(TAtlasDependMode.Once), Ord(mRules[0].Depend));
  Assert.AreEqual(10, mRules[0].TriggerLine);
  Assert.IsFalse(TAtlasBreakpointRules.Parse('{"format": 2}', mRules));
end;

procedure TAtlasBreakpointRulesTests.PutAndMove;
var
  mRules: TAtlasBreakpointRuleList;
  mRule, mDependent: TAtlasBreakpointRule;
begin
  mRules := nil;
  mRule := Rule;
  mRule.Hit := TAtlasHitMode.Exactly;
  TAtlasBreakpointRules.Put(mRules, mRule);
  mDependent := Rule;
  mDependent.Line := 80;
  mDependent.Depend := TAtlasDependMode.UntilEnd;
  mDependent.TriggerFile := mRule.FileName;
  mDependent.TriggerLine := mRule.Line;
  TAtlasBreakpointRules.Put(mRules, mDependent);
  Assert.AreEqual(2, Integer(Length(mRules)));
  TAtlasBreakpointRules.Moved(mRules, 'c:\src\kunden.pas', 41, 51);
  Assert.AreEqual(0, TAtlasBreakpointRules.IndexOf(mRules, mRule.FileName, 51));
  Assert.AreEqual(51, mRules[1].TriggerLine, 'Verweis als Auslöser zieht mit');
  // Leere Regel entfernt.
  mRule.Line := 51;
  mRule.Hit := TAtlasHitMode.Any;
  TAtlasBreakpointRules.Put(mRules, mRule);
  Assert.AreEqual(1, Integer(Length(mRules)));
end;

procedure TAtlasBreakpointRulesTests.CallerAnywhere;
var
  mRule: TAtlasBreakpointRule;
  mState: TAtlasRuleState;
begin
  mRule := CallerRule('TB.Run', False);
  Assert.IsFalse(mRule.IsEmpty, 'Aufrufer allein ist eine Regel');
  mState := TAtlasRuleState.Start(mRule);
  Assert.AreEqual<TAtlasRuleDecision>(TAtlasRuleDecision.Continue,
    TAtlasBreakpointRules.Decide(mRule, mState, StackStop(['U.Ziel', 'U.TA.Run', 'P.Main'])));
  Assert.AreEqual(0, mState.Hits, 'Anderer Aufrufer zählt nicht');
  Assert.AreEqual<TAtlasRuleDecision>(TAtlasRuleDecision.Stop,
    TAtlasBreakpointRules.Decide(mRule, mState, StackStop(['U.Ziel', 'U.Hilfe', 'U.TB.Run', 'P.Main'])));
  // Die Routine des Haltepunkts selbst ist kein Aufrufer.
  Assert.IsFalse(TAtlasBreakpointRules.CallerMatches(CallerRule('Ziel', False), ['U.Ziel', 'P.Main']));
  Assert.IsFalse(TAtlasBreakpointRules.CallerMatches(mRule, nil), 'leerer Stapel');
  Assert.IsFalse(TAtlasBreakpointRules.CallerMatches(mRule, ['U.Ziel', '', ':7714C3E2']), 'Rahmen ohne Namen');
  Assert.IsTrue(TAtlasBreakpointRules.CallerMatches(Rule, nil), 'ohne Aufrufer immer');
end;

procedure TAtlasBreakpointRulesTests.CallerDirect;
var
  mRule: TAtlasBreakpointRule;
begin
  mRule := CallerRule('U.TB.*', True);
  Assert.IsFalse(TAtlasBreakpointRules.CallerMatches(mRule, ['U.Ziel', 'U.Hilfe', 'U.TB.Run']));
  Assert.IsTrue(TAtlasBreakpointRules.CallerMatches(mRule, ['U.Ziel', 'U.TB.Run', 'P.Main']));
  Assert.IsFalse(TAtlasBreakpointRules.CallerMatches(mRule, ['U.Ziel']), 'kein Rahmen darunter');
end;

procedure TAtlasBreakpointRulesTests.CallerAndHitCount;
var
  mRule: TAtlasBreakpointRule;
  mState: TAtlasRuleState;
  mFromA, mFromB: TAtlasStopThread;
begin
  mRule := CallerRule('TB', False);
  mRule.Hit := TAtlasHitMode.Exactly;
  mRule.HitCount := 2;
  mState := TAtlasRuleState.Start(mRule);
  mFromA := StackStop(['U.Ziel', 'U.TA.Run']);
  mFromB := StackStop(['U.Ziel', 'U.TB.Run']);
  Assert.AreEqual<TAtlasRuleDecision>(TAtlasRuleDecision.Continue, TAtlasBreakpointRules.Decide(mRule, mState, mFromB));
  Assert.AreEqual<TAtlasRuleDecision>(TAtlasRuleDecision.Continue, TAtlasBreakpointRules.Decide(mRule, mState, mFromA));
  Assert.AreEqual<TAtlasRuleDecision>(TAtlasRuleDecision.Continue, TAtlasBreakpointRules.Decide(mRule, mState, mFromA));
  Assert.AreEqual<TAtlasRuleDecision>(TAtlasRuleDecision.Stop, TAtlasBreakpointRules.Decide(mRule, mState, mFromB));
  Assert.AreEqual(2, mState.Hits);
end;

procedure TAtlasBreakpointRulesTests.CallerJsonOldAndNew;
var
  mRules: TAtlasBreakpointRuleList;
begin
  Assert.IsTrue(TAtlasBreakpointRules.Parse(TAtlasBreakpointRules.ToJson([CallerRule('Kunden.*', True)]), mRules));
  Assert.AreEqual(1, Integer(Length(mRules)));
  Assert.AreEqual('Kunden.*', mRules[0].Caller);
  Assert.IsTrue(mRules[0].CallerDirect);
  // Datei vor #2548: ohne "caller", Regel bleibt erhalten.
  Assert.IsTrue(TAtlasBreakpointRules.Parse('{"format": 1, "rules": [{"file": "C:\\Src\\Kunden.pas", ' +
    '"line": 42, "hit": "exactly", "hitCount": 2}]}', mRules));
  Assert.AreEqual(1, Integer(Length(mRules)));
  Assert.AreEqual('', mRules[0].Caller);
  Assert.IsFalse(mRules[0].CallerDirect);
  Assert.AreEqual(41, mRules[0].Line);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBreakpointRulesTests);

end.
