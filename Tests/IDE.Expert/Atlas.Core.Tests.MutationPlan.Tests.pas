unit Atlas.Core.Tests.MutationPlan.Tests;

// Tests der Auswahl eines Mutationslaufs (#1460): Operatoren aus der
// Einstellung, Anfrage an den Server, innerste Routine an einer Zeile, Auswahl
// nach Methode, Unit und geänderten Routinen, Ausgang eines Testlaufs.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasMutationPlanTests = class
  public
    [Test]
    procedure OperatorsFromSetting;
    [Test]
    procedure RequestJson;
    [Test]
    procedure InnermostRoutine;
    [Test]
    procedure SelectsRoutineAndUnit;
    [Test]
    procedure SelectsChangedOnly;
    [Test]
    procedure StatusOfRun;
  end;

  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasMutationStepsTests = class
  public
    [Test]
    procedure BaselineFailsUnlessGreen;
    [Test]
    procedure OutcomeRelativeToRoutine;
    [Test]
    procedure TotalsAndSurvivorsUpToDone;
    [Test]
    procedure RoutineResultsByName;
    [Test]
    procedure KilledTextByReason;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tests.Mutants,
  Atlas.Core.Tests.MutationResults,
  Atlas.Core.Tests.MutationPlan;

const
  cFile = 'C:\P\Preise.pas';
  cAnswer = '{"format": 1, "mutants": [' +
    '{"id": 1, "operator": "boundary", "routine": "Satz", "line": 6, "character": 13, "endLine": 6, ' +
    '"endCharacter": 15, "original": ">=", "replacement": ">"},' +
    '{"id": 2, "operator": "number", "routine": "Satz", "line": 7, "character": 15, "endLine": 7, ' +
    '"endCharacter": 17, "original": "10", "replacement": "11"},' +
    '{"id": 3, "operator": "arithmetic", "routine": "Doppelt", "line": 13, "character": 15, "endLine": 13, ' +
    '"endCharacter": 16, "original": "+", "replacement": "-"}], ' +
    '"routines": [{"name": "Satz", "line": 3, "endLine": 9}, {"name": "Doppelt", "line": 10, "endLine": 13}, ' +
    '{"name": "Doppelt.Lokal", "line": 11, "endLine": 12}]}';

function SampleLines: TArray<string>;
begin
  Result := TArray<string>.Create('unit Preise;', 'interface', 'implementation',
    'function Satz(AMenge: Integer): Integer;', 'begin', '  if AMenge >= 100 then', '    Result := 10',
    '  else', '    Result := 0;', 'end;', 'function Doppelt(A: Integer): Integer;', 'begin',
    '  Result := A + A;', 'end;', 'end.');
end;

function List: TAtlasMutantList;
begin
  Assert.IsTrue(TAtlasMutants.Parse(cAnswer, Result));
end;

{ TAtlasMutationPlanTests }

procedure TAtlasMutationPlanTests.OperatorsFromSetting;
var
  mIds: TArray<string>;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasMutationPlan.OperatorsOf('  '))));
  mIds := TAtlasMutationPlan.OperatorsOf('Boundary, equality;boundary  not');
  Assert.AreEqual(3, Integer(Length(mIds)));
  Assert.AreEqual('boundary', mIds[0]);
  Assert.AreEqual('equality', mIds[1]);
  Assert.AreEqual('not', mIds[2]);
end;

procedure TAtlasMutationPlanTests.RequestJson;
begin
  Assert.AreEqual('["file:///C:/P/Preise.pas",{}]', TAtlasMutationPlan.RequestJson('file:///C:/P/Preise.pas', nil));
  Assert.AreEqual('["u",{"operators":["boundary","not"]}]',
    TAtlasMutationPlan.RequestJson('u', TArray<string>.Create('boundary', 'not')));
end;

procedure TAtlasMutationPlanTests.InnermostRoutine;
var
  mRoutine: TAtlasMutantRoutine;
begin
  Assert.IsTrue(TAtlasMutationPlan.RoutineAt(List, 5, mRoutine));
  Assert.AreEqual('Satz', mRoutine.Name);
  Assert.IsTrue(TAtlasMutationPlan.RoutineAt(List, 12, mRoutine));
  Assert.AreEqual('Doppelt.Lokal', mRoutine.Name);
  Assert.IsTrue(TAtlasMutationPlan.RoutineAt(List, 13, mRoutine));
  Assert.AreEqual('Doppelt', mRoutine.Name);
  Assert.IsFalse(TAtlasMutationPlan.RoutineAt(List, 1, mRoutine));
end;

procedure TAtlasMutationPlanTests.SelectsRoutineAndUnit;
var
  mJobs: TArray<TAtlasMutationJob>;
begin
  mJobs := TAtlasMutationPlan.Select(List, TAtlasMutationScope.Routine, 6, cFile, SampleLines, nil);
  Assert.AreEqual(2, Integer(Length(mJobs)));
  Assert.AreEqual(0, mJobs[0].Index);
  Assert.AreEqual(1, mJobs[1].Index);
  Assert.AreEqual(3, mJobs[1].Routine.Line);
  mJobs := TAtlasMutationPlan.Select(List, TAtlasMutationScope.Routine, 1, cFile, SampleLines, nil);
  Assert.AreEqual(0, Integer(Length(mJobs)));
  mJobs := TAtlasMutationPlan.Select(List, TAtlasMutationScope.WholeUnit, -1, cFile, SampleLines, nil);
  Assert.AreEqual(3, Integer(Length(mJobs)));
  Assert.AreEqual('Doppelt', mJobs[2].Routine.Name);
  Assert.AreEqual(0, mJobs[2].Index);
end;

procedure TAtlasMutationPlanTests.SelectsChangedOnly;
var
  mResults: TAtlasMutationResults;
  mResult: TAtlasMutationRoutineResult;
  mRoutine: TAtlasMutantRoutine;
  mJobs: TArray<TAtlasMutationJob>;
  mLines: TArray<string>;
begin
  mLines := SampleLines;
  Assert.IsTrue(List.RoutineOf('Satz', mRoutine));
  mResults := TAtlasMutationResults.Create;
  try
    mResult := Default(TAtlasMutationRoutineResult);
    mResult.FileName := cFile;
    mResult.Routine := 'Satz';
    mResult.Body := TAtlasMutants.RoutineBody(mLines, mRoutine);
    mResults.Put(mResult);
    // Satz hat ein gültiges Ergebnis: nur Doppelt.
    mJobs := TAtlasMutationPlan.Select(List, TAtlasMutationScope.Changed, -1, cFile, mLines, mResults);
    Assert.AreEqual(1, Integer(Length(mJobs)));
    Assert.AreEqual('Doppelt', mJobs[0].Routine.Name);
    // Satz geändert: wieder dabei.
    mLines[6] := '    Result := 12';
    mJobs := TAtlasMutationPlan.Select(List, TAtlasMutationScope.Changed, -1, cFile, mLines, mResults);
    Assert.AreEqual(3, Integer(Length(mJobs)));
  finally
    mResults.Free;
  end;
end;

procedure TAtlasMutationPlanTests.StatusOfRun;
const
  cRed = '<test-run total="2"><test-suite type="TestFixture" name="TT" fullname="U.TT">' +
    '<test-case fullname="U.TT.A" name="A" result="Passed"/>' +
    '<test-case fullname="U.TT.B" name="B" result="Failed"><failure><message>x</message></failure></test-case>' +
    '</test-suite></test-run>';
  cGreen = '<test-run total="1"><test-suite type="TestFixture" name="TT" fullname="U.TT">' +
    '<test-case fullname="U.TT.A" name="A" result="Passed"/></test-suite></test-run>';
var
  mBy: string;
begin
  Assert.AreEqual<TAtlasMutationStatus>(TAtlasMutationStatus.Killed,
    TAtlasMutationPlan.StatusOf(False, 0, cRed, mBy));
  Assert.AreEqual('U.TT.B', mBy);
  Assert.AreEqual<TAtlasMutationStatus>(TAtlasMutationStatus.Survived,
    TAtlasMutationPlan.StatusOf(False, 0, cGreen, mBy));
  Assert.AreEqual('', mBy);
  Assert.AreEqual<TAtlasMutationStatus>(TAtlasMutationStatus.TimedOut,
    TAtlasMutationPlan.StatusOf(True, 1, cRed, mBy));
  Assert.AreEqual<TAtlasMutationStatus>(TAtlasMutationStatus.Killed,
    TAtlasMutationPlan.StatusOf(False, 3, '', mBy));
  Assert.AreEqual('3', mBy);
  Assert.AreEqual<TAtlasMutationStatus>(TAtlasMutationStatus.Invalid,
    TAtlasMutationPlan.StatusOf(False, 0, '', mBy));
  Assert.AreEqual<TAtlasMutationStatus>(TAtlasMutationStatus.Invalid,
    TAtlasMutationPlan.StatusOf(False, 0, '<test-run total="0"></test-run>', mBy));
end;

/// <summary>Job des Mutanten AId in Routine ARoutine (Kopf in Zeile ARoutineLine, ab 0) an Zeile ALine (ab 1).
/// </summary>
function Job(const ARoutine: string; ARoutineLine, ALine: Integer): TAtlasMutationJob;
begin
  Result := Default(TAtlasMutationJob);
  Result.Routine.Name := ARoutine;
  Result.Routine.Line := ARoutineLine;
  Result.Routine.EndLine := ARoutineLine + 5;
  Result.Mutant.Line := ALine;
  Result.Mutant.OperatorId := 'boundary';
  Result.Mutant.Original := '>=';
  Result.Mutant.Replacement := '>';
  Result.Mutant.Description := '>= durch >';
  Result.Index := 1;
end;

/// <summary>Ausgang mit dem Stand AStatus.</summary>
function Outcome(AStatus: TAtlasMutationStatus): TAtlasMutationOutcome;
begin
  Result := Default(TAtlasMutationOutcome);
  Result.Status := AStatus;
end;

{ TAtlasMutationStepsTests }

procedure TAtlasMutationStepsTests.BaselineFailsUnlessGreen;
begin
  Assert.IsFalse(TAtlasMutationSteps.BaselineFailed(-1, TAtlasMutationStatus.Survived), 'alle grün ohne Mutation');
  Assert.IsTrue(TAtlasMutationSteps.BaselineFailed(-1, TAtlasMutationStatus.Killed));
  Assert.IsTrue(TAtlasMutationSteps.BaselineFailed(-1, TAtlasMutationStatus.BuildFailed));
  Assert.IsTrue(TAtlasMutationSteps.BaselineFailed(-1, TAtlasMutationStatus.Invalid));
  Assert.IsFalse(TAtlasMutationSteps.BaselineFailed(0, TAtlasMutationStatus.Killed), 'Mutant erkannt');
  Assert.AreEqual(0, TAtlasMutationSteps.Done(-1));
  Assert.AreEqual(3, TAtlasMutationSteps.Done(3));
end;

procedure TAtlasMutationStepsTests.OutcomeRelativeToRoutine;
var
  mOutcome: TAtlasMutationOutcome;
begin
  mOutcome := TAtlasMutationSteps.OutcomeOf(Job('Satz', 3, 6), TAtlasMutationStatus.Killed, 'T.A', 120);
  Assert.AreEqual(2, mOutcome.Line, 'Zeile 6 (ab 1) ist die dritte der Routine ab Zeile 3 (ab 0)');
  Assert.AreEqual<TAtlasMutationStatus>(TAtlasMutationStatus.Killed, mOutcome.Status);
  Assert.AreEqual('T.A', mOutcome.By);
  Assert.AreEqual(120, mOutcome.Milliseconds);
  Assert.AreEqual(1, mOutcome.Index);
  Assert.AreEqual('boundary', mOutcome.OperatorId);
  Assert.AreEqual('>=', mOutcome.Original);
  Assert.AreEqual('>', mOutcome.Replacement);
  Assert.AreEqual('>= durch >', mOutcome.Description);
end;

procedure TAtlasMutationStepsTests.TotalsAndSurvivorsUpToDone;
var
  mOutcomes: TArray<TAtlasMutationOutcome>;
  mTotals: TAtlasMutationTotals;
  mSurvivors: TArray<Integer>;
begin
  mOutcomes := TArray<TAtlasMutationOutcome>.Create(Outcome(TAtlasMutationStatus.Killed),
    Outcome(TAtlasMutationStatus.Survived), Outcome(TAtlasMutationStatus.TimedOut),
    Outcome(TAtlasMutationStatus.Survived));
  // Abgebrochen nach drei: Der vierte zählt nicht.
  mTotals := TAtlasMutationSteps.Totals(mOutcomes, 3);
  Assert.AreEqual(1, mTotals.Killed);
  Assert.AreEqual(1, mTotals.Survived);
  Assert.AreEqual(1, mTotals.TimedOut);
  mSurvivors := TAtlasMutationSteps.Survivors(mOutcomes, 3);
  Assert.AreEqual(1, Integer(Length(mSurvivors)));
  Assert.AreEqual(1, mSurvivors[0]);
  Assert.AreEqual(2, Integer(Length(TAtlasMutationSteps.Survivors(mOutcomes, 9))), 'höchstens alle');
end;

procedure TAtlasMutationStepsTests.RoutineResultsByName;
var
  mJobs: TArray<TAtlasMutationJob>;
  mOutcomes: TArray<TAtlasMutationOutcome>;
  mResult: TAtlasMutationRoutineResult;
  mComplete: Boolean;
begin
  // Satz, Lokal, wieder Satz: Die Mutanten von Satz gehören zusammen, auch mit Lokal dazwischen.
  mJobs := TArray<TAtlasMutationJob>.Create(Job('Satz', 3, 6), Job('Satz.Lokal', 4, 5), Job('Satz', 3, 7));
  mOutcomes := TArray<TAtlasMutationOutcome>.Create(Outcome(TAtlasMutationStatus.Killed),
    Outcome(TAtlasMutationStatus.Survived), Outcome(TAtlasMutationStatus.Killed));
  Assert.IsTrue(TAtlasMutationSteps.FirstOfRoutine(mJobs, 0));
  Assert.IsTrue(TAtlasMutationSteps.FirstOfRoutine(mJobs, 1));
  Assert.IsFalse(TAtlasMutationSteps.FirstOfRoutine(mJobs, 2));
  mResult := TAtlasMutationSteps.RoutineResult(mJobs, mOutcomes, 0, 3, mComplete);
  Assert.AreEqual('Satz', mResult.Routine);
  Assert.AreEqual(3, mResult.Line);
  Assert.AreEqual(8, mResult.EndLine);
  Assert.AreEqual(2, Integer(Length(mResult.Outcomes)));
  Assert.IsTrue(mComplete);
  // Abgebrochen nach zwei: Satz ist nicht ganz geprüft, Lokal schon.
  TAtlasMutationSteps.RoutineResult(mJobs, mOutcomes, 0, 2, mComplete);
  Assert.IsFalse(mComplete);
  TAtlasMutationSteps.RoutineResult(mJobs, mOutcomes, 1, 2, mComplete);
  Assert.IsTrue(mComplete);
end;

procedure TAtlasMutationStepsTests.KilledTextByReason;
begin
  Assert.AreEqual<TAtlasMutationKilledText>(TAtlasMutationKilledText.ExitCode, TAtlasMutationSteps.KilledText('3'));
  Assert.AreEqual<TAtlasMutationKilledText>(TAtlasMutationKilledText.ByTest,
    TAtlasMutationSteps.KilledText('TPreiseTests.Satz'));
  Assert.AreEqual<TAtlasMutationKilledText>(TAtlasMutationKilledText.Plain, TAtlasMutationSteps.KilledText(''));
  Assert.AreEqual<TAtlasMutationKilledText>(TAtlasMutationKilledText.ByTest, TAtlasMutationSteps.KilledText('0'),
    'Exitcode 0 nennt keinen Absturz');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMutationPlanTests);
  TDUnitX.RegisterTestFixture(TAtlasMutationStepsTests);

end.
