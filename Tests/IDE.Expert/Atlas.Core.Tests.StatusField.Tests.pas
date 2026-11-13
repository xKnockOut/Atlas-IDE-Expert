unit Atlas.Core.Tests.StatusField.Tests;

// Tests des Teststands in der Statusleiste (#1777): Text und Ampel nach dem
// Lauf, während des Laufs und ohne Lauf, Tooltip mit letztem Lauf, Zahlen,
// veralteten Tests und Klickziel, kein Feld ohne Testprojekt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasTestStatusFieldTests = class
  public
    [Test]
    procedure HiddenWithoutProject;
    [Test]
    procedure PassedOfRunAndGreen;
    [Test]
    procedure FailedIsRedAndRerunsFailed;
    [Test]
    procedure RunningIsYellow;
    [Test]
    procedure NotRunIsNeutral;
    [Test]
    procedure StaleIsYellow;
    [Test]
    procedure HintNamesRunCountsAndClick;
    [Test]
    procedure SkippedNotCounted;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Core.Status.Contract,
  Atlas.Text.TestResults,
  Atlas.Core.Tests.StatusField;

function Texts: TAtlasTestStatusTexts;
begin
  Result := Default(TAtlasTestStatusTexts);
  Result.Field := 'Tests %d/%d';
  Result.Running := 'Tests laufen …';
  Result.NotRun := 'Tests –';
  Result.Project := 'Testprojekt: %s';
  Result.LastRun := 'Letzter Lauf: %s, %s';
  Result.NoRunYet := 'Noch kein Lauf';
  Result.Counts := '%d bestanden, %d fehlgeschlagen, %d übersprungen';
  Result.Stale := '%d veraltet';
  Result.ClickFailed := 'Klick: fehlgeschlagene';
  Result.ClickAll := 'Klick: alle';
  Result.Context := 'Rechtsklick: mehr';
  Result.DecimalSeparator := ',';
end;

function CaseOf(AOutcome: TTestOutcome): TTestCaseResult;
begin
  Result := Default(TTestCaseResult);
  Result.FullName := 'Demo.Tests.TDemo.Test';
  Result.Outcome := AOutcome;
end;

function InputOf(const AOutcomes: array of TTestOutcome): TAtlasTestStatusInput;
var
  mIndex: Integer;
begin
  Result := Default(TAtlasTestStatusInput);
  Result.Project := 'DemoTests';
  Result.Stale := -1;
  SetLength(Result.Cases, Length(AOutcomes));
  for mIndex := 0 to High(AOutcomes) do
  begin
    Result.Cases[mIndex] := CaseOf(AOutcomes[mIndex]);
  end;
end;

procedure TAtlasTestStatusFieldTests.HiddenWithoutProject;
var
  mInput: TAtlasTestStatusInput;
begin
  mInput := InputOf([TTestOutcome.Passed]);
  mInput.Project := '';
  Assert.IsFalse(TAtlasTestStatusField.Build(mInput, Texts).Visible);
end;

procedure TAtlasTestStatusFieldTests.PassedOfRunAndGreen;
var
  mStatus: TAtlasTestStatus;
begin
  mStatus := TAtlasTestStatusField.Build(InputOf([TTestOutcome.Passed, TTestOutcome.Passed]), Texts);
  Assert.IsTrue(mStatus.Visible);
  Assert.AreEqual('Tests 2/2', mStatus.Text);
  Assert.AreEqual<TAtlasStatusState>(TAtlasStatusState.Green, mStatus.State);
  Assert.IsFalse(mStatus.RerunFailed, 'alle grün: Klick führt alle aus');
end;

procedure TAtlasTestStatusFieldTests.FailedIsRedAndRerunsFailed;
var
  mStatus: TAtlasTestStatus;
begin
  mStatus := TAtlasTestStatusField.Build(InputOf([TTestOutcome.Passed, TTestOutcome.Failed, TTestOutcome.Error]),
    Texts);
  Assert.AreEqual('Tests 1/3', mStatus.Text, 'Fehler zählen als fehlgeschlagen');
  Assert.AreEqual<TAtlasStatusState>(TAtlasStatusState.Red, mStatus.State);
  Assert.IsTrue(mStatus.RerunFailed);
end;

procedure TAtlasTestStatusFieldTests.RunningIsYellow;
var
  mInput: TAtlasTestStatusInput;
  mStatus: TAtlasTestStatus;
begin
  mInput := InputOf([TTestOutcome.Failed]);
  mInput.Busy := True;
  mStatus := TAtlasTestStatusField.Build(mInput, Texts);
  Assert.AreEqual('Tests laufen …', mStatus.Text);
  Assert.AreEqual<TAtlasStatusState>(TAtlasStatusState.Yellow, mStatus.State);
end;

procedure TAtlasTestStatusFieldTests.NotRunIsNeutral;
var
  mStatus: TAtlasTestStatus;
begin
  mStatus := TAtlasTestStatusField.Build(InputOf([]), Texts);
  Assert.IsTrue(mStatus.Visible, 'Testprojekt ohne Lauf: Feld bleibt');
  Assert.AreEqual('Tests –', mStatus.Text);
  Assert.AreEqual<TAtlasStatusState>(TAtlasStatusState.Neutral, mStatus.State);
  Assert.IsTrue(ContainsStr(mStatus.Hint, 'Noch kein Lauf'), mStatus.Hint);
end;

procedure TAtlasTestStatusFieldTests.StaleIsYellow;
var
  mInput: TAtlasTestStatusInput;
begin
  mInput := InputOf([TTestOutcome.Passed]);
  mInput.Stale := 1;
  Assert.AreEqual<TAtlasStatusState>(TAtlasStatusState.Yellow, TAtlasTestStatusField.Build(mInput, Texts).State);
  mInput.Cases[0].Outcome := TTestOutcome.Failed;
  Assert.AreEqual<TAtlasStatusState>(TAtlasStatusState.Red, TAtlasTestStatusField.Build(mInput, Texts).State,
    'rot vor gelb');
end;

procedure TAtlasTestStatusFieldTests.HintNamesRunCountsAndClick;
var
  mInput: TAtlasTestStatusInput;
  mHint: string;
begin
  mInput := InputOf([TTestOutcome.Passed, TTestOutcome.Failed, TTestOutcome.Skipped]);
  mInput.LastRun := EncodeDate(2026, 11, 13) + EncodeTime(14, 5, 0, 0);
  mInput.DurationMs := 1200;
  mInput.Stale := 2;
  mHint := TAtlasTestStatusField.Build(mInput, Texts).Hint;
  Assert.AreEqual('Testprojekt: DemoTests' + sLineBreak + 'Letzter Lauf: 14:05, 1,2 s' + sLineBreak +
    '1 bestanden, 1 fehlgeschlagen, 1 übersprungen' + sLineBreak + '2 veraltet' + sLineBreak +
    'Klick: fehlgeschlagene' + sLineBreak + 'Rechtsklick: mehr', mHint);
end;

procedure TAtlasTestStatusFieldTests.SkippedNotCounted;
var
  mPassed, mFailed, mSkipped: Integer;
begin
  TAtlasTestStatusField.Count(InputOf([TTestOutcome.Passed, TTestOutcome.Skipped]).Cases, mPassed, mFailed,
    mSkipped);
  Assert.AreEqual(1, mPassed);
  Assert.AreEqual(0, mFailed);
  Assert.AreEqual(1, mSkipped);
  Assert.AreEqual('Tests 1/1', TAtlasTestStatusField.Build(InputOf([TTestOutcome.Passed, TTestOutcome.Skipped]),
    Texts).Text, 'übersprungene zählen nicht mit');
end;

end.
