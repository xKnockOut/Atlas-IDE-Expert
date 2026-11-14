unit Atlas.Core.Tests.MutationResults.Tests;

// Tests der Ergebnisse des Mutationslaufs (#1460): merken und nachschlagen
// mit Prüfsumme, veraltet, Zahlen und Anteil, vergessen, JSON hin und zurück,
// Marken je Zeile nur bei unveränderter Routine.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasMutationResultsTests = class
  public
    [Test]
    procedure LookupNeedsSameBody;
    [Test]
    procedure TotalsAndScore;
    [Test]
    procedure ForgetsFile;
    [Test]
    procedure JsonRoundTrip;
    [Test]
    procedure RejectsInvalidJson;
    [Test]
    procedure StatusIds;
    [Test]
    procedure MarksFollowBody;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Core.Tests.Mutants,
  Atlas.Core.Tests.MutationResults;

const
  cFile = 'C:\P\Preise.pas';

function Outcome(AIndex: Integer; AStatus: TAtlasMutationStatus): TAtlasMutationOutcome;
begin
  Result := Default(TAtlasMutationOutcome);
  Result.Index := AIndex;
  Result.OperatorId := 'boundary';
  Result.Original := '>=';
  Result.Replacement := '>';
  Result.Line := 2;
  Result.Status := AStatus;
  Result.Milliseconds := 120;
end;

function Routine(const AFileName, AName, ABody: string;
  const AOutcomes: TArray<TAtlasMutationOutcome>): TAtlasMutationRoutineResult;
begin
  Result := Default(TAtlasMutationRoutineResult);
  Result.FileName := AFileName;
  Result.Routine := AName;
  Result.Body := ABody;
  Result.Line := 3;
  Result.EndLine := 9;
  Result.AtUtc := EncodeDateTime(2026, 11, 14, 8, 30, 0, 0);
  Result.Outcomes := AOutcomes;
end;

{ TAtlasMutationResultsTests }

procedure TAtlasMutationResultsTests.LookupNeedsSameBody;
var
  mResults: TAtlasMutationResults;
  mResult: TAtlasMutationRoutineResult;
begin
  mResults := TAtlasMutationResults.Create;
  try
    mResults.Put(Routine(cFile, 'Satz', 'abc', [Outcome(0, TAtlasMutationStatus.Survived)]));
    // Dateiname ohne Rücksicht auf Groß-/Kleinschreibung.
    Assert.IsTrue(mResults.Lookup('c:\p\preise.pas', 'Satz', 'abc', mResult));
    Assert.AreEqual(1, Integer(Length(mResult.Outcomes)));
    Assert.IsFalse(mResults.Lookup(cFile, 'Satz', 'neu', mResult));
    Assert.AreEqual('', mResult.Routine);
    Assert.IsTrue(mResults.IsStale(cFile, 'Satz', 'neu'));
    Assert.IsFalse(mResults.IsStale(cFile, 'Satz', 'abc'));
    Assert.IsFalse(mResults.IsStale(cFile, 'Fehlt', 'abc'));
    // Neuer Lauf ersetzt den alten.
    mResults.Put(Routine(cFile, 'Satz', 'neu', [Outcome(0, TAtlasMutationStatus.Killed)]));
    Assert.IsTrue(mResults.Lookup(cFile, 'Satz', 'neu', mResult));
    Assert.AreEqual(1, mResults.Count);
  finally
    mResults.Free;
  end;
end;

procedure TAtlasMutationResultsTests.TotalsAndScore;
var
  mResults: TAtlasMutationResults;
  mTotals: TAtlasMutationTotals;
begin
  mResults := TAtlasMutationResults.Create;
  try
    Assert.AreEqual(-1, mResults.Totals('').Score);
    mResults.Put(Routine(cFile, 'Satz', 'a', [Outcome(0, TAtlasMutationStatus.Killed),
      Outcome(1, TAtlasMutationStatus.Survived), Outcome(2, TAtlasMutationStatus.TimedOut)]));
    mResults.Put(Routine('C:\P\Andere.pas', 'X', 'b', [Outcome(0, TAtlasMutationStatus.BuildFailed),
      Outcome(1, TAtlasMutationStatus.Invalid), Outcome(2, TAtlasMutationStatus.Survived)]));
    mTotals := mResults.Totals(cFile);
    Assert.AreEqual(1, mTotals.Killed);
    Assert.AreEqual(1, mTotals.Survived);
    Assert.AreEqual(1, mTotals.TimedOut);
    // Zeitüberschreitung zählt als erkannt: 2 von 3.
    Assert.AreEqual(66, mTotals.Score);
    mTotals := mResults.Totals('');
    Assert.AreEqual(1, mTotals.BuildFailed);
    Assert.AreEqual(1, mTotals.Invalid);
    // Nicht übersetzbar und nicht anwendbar zählen nicht mit: 2 von 4.
    Assert.AreEqual(50, mTotals.Score);
  finally
    mResults.Free;
  end;
end;

procedure TAtlasMutationResultsTests.ForgetsFile;
var
  mResults: TAtlasMutationResults;
begin
  mResults := TAtlasMutationResults.Create;
  try
    mResults.Put(Routine(cFile, 'Satz', 'a', nil));
    mResults.Put(Routine(cFile, 'Doppelt', 'b', nil));
    mResults.Put(Routine('C:\P\Andere.pas', 'X', 'c', nil));
    Assert.AreEqual(2, Integer(Length(mResults.RoutinesOf(cFile))));
    Assert.AreEqual('Doppelt', mResults.RoutinesOf(cFile)[0].Routine);
    mResults.Forget(cFile);
    Assert.AreEqual(1, mResults.Count);
    mResults.Forget('');
    Assert.AreEqual(0, mResults.Count);
  finally
    mResults.Free;
  end;
end;

procedure TAtlasMutationResultsTests.JsonRoundTrip;
var
  mResults, mLoaded: TAtlasMutationResults;
  mJson: string;
  mResult: TAtlasMutationRoutineResult;
  mOutcome: TAtlasMutationOutcome;
begin
  mResults := TAtlasMutationResults.Create;
  mLoaded := TAtlasMutationResults.Create;
  try
    mOutcome := Outcome(1, TAtlasMutationStatus.Killed);
    mOutcome.By := 'PreiseTests.TPreiseTests.Grenze';
    mOutcome.Description := '>= durch >';
    mResults.Put(Routine(cFile, 'Satz', 'abc', [Outcome(0, TAtlasMutationStatus.Survived), mOutcome]));
    mResults.Put(Routine(cFile, 'Doppelt', 'def', [Outcome(0, TAtlasMutationStatus.TimedOut)]));
    mResults.Put(Routine('C:\P\Ä.pas', 'X', 'ghi', nil));
    mJson := mResults.ToJson('C:\P\Demo.Tests.dproj');
    Assert.Contains(mJson, '"format":1');
    Assert.Contains(mJson, 'Ä.pas', 'Umlaute lesbar');
    Assert.IsTrue(mLoaded.LoadJson(mJson));
    Assert.AreEqual(3, mLoaded.Count);
    Assert.IsTrue(mLoaded.Lookup(cFile, 'Satz', 'abc', mResult));
    Assert.AreEqual(2, Integer(Length(mResult.Outcomes)));
    Assert.AreEqual('PreiseTests.TPreiseTests.Grenze', mResult.Outcomes[1].By);
    Assert.AreEqual(Ord(TAtlasMutationStatus.Killed), Ord(mResult.Outcomes[1].Status));
    Assert.AreEqual(2, mResult.Outcomes[1].Line);
    Assert.AreEqual('>', mResult.Outcomes[1].Replacement);
    Assert.AreEqual(120, mResult.Outcomes[1].Milliseconds);
    Assert.AreEqual('>= durch >', mResult.Outcomes[1].Description);
    Assert.AreEqual(3, mResult.Line);
    Assert.AreEqual(9, mResult.EndLine);
    Assert.AreEqual(EncodeDateTime(2026, 11, 14, 8, 30, 0, 0), mResult.AtUtc, 1 / SecsPerDay);
    Assert.AreEqual(mJson, mLoaded.ToJson('C:\P\Demo.Tests.dproj'));
  finally
    mLoaded.Free;
    mResults.Free;
  end;
end;

procedure TAtlasMutationResultsTests.RejectsInvalidJson;
var
  mResults: TAtlasMutationResults;
begin
  mResults := TAtlasMutationResults.Create;
  try
    mResults.Put(Routine(cFile, 'Satz', 'a', nil));
    Assert.IsFalse(mResults.LoadJson('{"format": 2, "files": []}'));
    Assert.AreEqual(0, mResults.Count);
    Assert.IsFalse(mResults.LoadJson('kaputt'));
    // Unbrauchbare Einträge fallen weg, der Rest bleibt.
    Assert.IsTrue(mResults.LoadJson('{"format": 1, "files": [{"file": "", "routines": []}, ' +
      '{"file": "C:\\P\\A.pas", "routines": [{"routine": ""}, {"routine": "R", "body": "x", ' +
      '"mutants": [{"index": 0, "line": 1, "status": "unbekannt"}, {"index": 0, "line": 1, "status": "killed"}]}]}]}'));
    Assert.AreEqual(1, mResults.Count);
    Assert.AreEqual(1, mResults.Totals('').Killed);
  finally
    mResults.Free;
  end;
end;

procedure TAtlasMutationResultsTests.StatusIds;
var
  mStatus, mParsed: TAtlasMutationStatus;
begin
  for mStatus := Low(TAtlasMutationStatus) to High(TAtlasMutationStatus) do
  begin
    Assert.IsTrue(TAtlasMutationResults.TryParseStatus(TAtlasMutationResults.StatusId(mStatus), mParsed));
    Assert.AreEqual(Ord(mStatus), Ord(mParsed));
  end;
  Assert.IsFalse(TAtlasMutationResults.TryParseStatus('gibtsnicht', mParsed));
end;

procedure TAtlasMutationResultsTests.MarksFollowBody;
var
  mResults: TAtlasMutationResults;
  mLines: TArray<string>;
  mRoutine: TAtlasMutantRoutine;
  mResult: TAtlasMutationRoutineResult;
  mSecond: TAtlasMutationOutcome;
  mMarks: TArray<TAtlasMutationLineMark>;
begin
  mLines := TArray<string>.Create('unit Preise;', 'interface', 'implementation',
    'function Satz(AMenge: Integer): Integer;', 'begin', '  if AMenge >= 100 then', '    Result := 10',
    '  else', '    Result := 0;', 'end;', 'end.');
  mRoutine := Default(TAtlasMutantRoutine);
  mRoutine.Line := 3;
  mRoutine.EndLine := 9;
  mSecond := Outcome(1, TAtlasMutationStatus.Killed);
  mSecond.Line := 3;
  mResult := Routine(cFile, 'Satz', TAtlasMutants.RoutineBody(mLines, mRoutine),
    [Outcome(0, TAtlasMutationStatus.Survived), mSecond, Outcome(2, TAtlasMutationStatus.Killed)]);
  mResults := TAtlasMutationResults.Create;
  try
    mResults.Put(mResult);
    mMarks := mResults.MarksOf(cFile, mLines);
    // Zeile 2 und 3 relativ zum Kopf in Zeile 3: absolut 5 und 6.
    Assert.AreEqual(2, Integer(Length(mMarks)));
    Assert.AreEqual(5, mMarks[0].Line);
    Assert.AreEqual(2, Integer(Length(mMarks[0].Outcomes)));
    Assert.IsTrue(mMarks[0].AnySurvived);
    Assert.IsTrue(mMarks[0].AnyKilled);
    Assert.AreEqual(6, mMarks[1].Line);
    Assert.IsFalse(mMarks[1].AnySurvived);
    // Routine geändert: keine Marken mehr.
    mLines[6] := '    Result := 11';
    Assert.AreEqual(0, Integer(Length(mResults.MarksOf(cFile, mLines))));
    Assert.AreEqual(0, Integer(Length(mResults.MarksOf('C:\P\Andere.pas', mLines))));
  finally
    mResults.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMutationResultsTests);

end.
