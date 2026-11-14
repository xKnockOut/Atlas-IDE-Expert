unit Atlas.Core.Tests.MutationPlan.Tests;

// Tests der Auswahl eines Mutationslaufs (#1460): Operatoren aus der
// Einstellung, Anfrage an den Server, innerste Routine an einer Zeile, Auswahl
// nach Methode, Unit und geänderten Routinen.

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

initialization
  TDUnitX.RegisterTestFixture(TAtlasMutationPlanTests);

end.
