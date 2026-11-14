unit Atlas.Core.Tests.Series;

// Tests mehrfach oder in zufälliger Reihenfolge ausführen (#1782), ohne VCL,
// Windows und Open Tools API:
// - DUnitX hält sich bei --run weder an wiederholte Namen noch an deren
//   Reihenfolge: Der Filter wählt nur aus, die Fixtures laufen sortiert, die
//   Tests einer Fixture in der Reihenfolge ihrer Deklaration. Eine Serie
//   besteht darum aus mehreren Starts des Testprogramms nacheinander:
//   - Mehrfach: N Starts mit denselben Namen.
//   - Zufällige Reihenfolge: die Tests der Fixture einzeln (je Test bzw. Fall
//     ein Start) in der Reihenfolge, die der Startwert ergibt. So fällt ein
//     Test auf, der nur nach einem anderen besteht, und einer, der an
//     Zuständen außerhalb des Prozesses (Dateien, Datenbank, Registry) hängt,
//     die ein anderer hinterlässt.
// - Mischen: Fisher-Yates mit dem Generator von Park und Miller (minstd,
//   Faktor 48271); dieselben Namen und derselbe Startwert ergeben unter
//   Delphi und FPC dieselbe Reihenfolge („Mit dieser Reihenfolge erneut“).
// - Auswertung: Ein Start gilt als bestanden, wenn keiner seiner Tests
//   fehlschlug; dazu je Test bestanden und rot über alle Starts und die
//   Beschriftung der Marke („20× ausgeführt · 18 bestanden, 2 rot“).

interface

uses
  System.SysUtils,
  Atlas.Text.DUnitX,
  Atlas.Text.TestResults;

type
{$SCOPEDENUMS ON}
  TAtlasTestSeriesKind = (Repeated, Shuffled);
  /// <summary>Stand einer Serie an der Marke: alle Starts bestanden, alle rot oder gemischt (gelb).</summary>
  TAtlasTestSeriesState = (Passed, Failed, Mixed);
{$SCOPEDENUMS OFF}

  /// <summary>Gegenstand einer Serie: die Marke (Fixture, Test oder Fall), an der ihr Ergebnis steht.</summary>
  TAtlasTestSeriesSubject = record
    UnitName: string;
    Fixture: string;
    /// <summary>'' = die ganze Fixture.</summary>
    Method: string;
    /// <summary>'' = alle Fälle bzw. kein [TestCase].</summary>
    CaseName: string;
    class function Make(const AUnitName, AFixture, AMethod, ACaseName: string): TAtlasTestSeriesSubject; static;
    /// <summary>Dieselbe Marke (ohne Groß- und Kleinschreibung)?</summary>
    function Matches(const AOther: TAtlasTestSeriesSubject): Boolean;
    /// <summary>Für Meldungen: Fixture.Methode[.Fall] bzw. Fixture.</summary>
    function Caption: string;
  end;

  /// <summary>Ergebnisse eines Tests über alle Starts einer Serie.</summary>
  TAtlasTestSeriesTally = record
    FullName: string;
    Passed: Integer;
    Failed: Integer;
    /// <summary>Meldung des letzten Fehlschlags; '' ohne.</summary>
    Message: string;
  end;

  /// <summary>Texte der Marke: Repeated (%d Starts, %d bestanden, %d rot), Shuffled (%d Startwert, %d bestanden,
  /// %d rot), Running (%d laufender Start, %d alle).</summary>
  TAtlasTestSeriesTexts = record
    Repeated: string;
    Shuffled: string;
    Running: string;
  end;

  /// <summary>Eine Serie von Starts des Testprogramms.</summary>
  TAtlasTestSeries = record
  private
    function IndexOfTest(const AFullName: string): Integer;
  public
    Kind: TAtlasTestSeriesKind;
    Subject: TAtlasTestSeriesSubject;
    /// <summary>.dproj des Testprojekts; setzt der Aufrufer.</summary>
    Project: string;
    /// <summary>Startwert der Reihenfolge (nur Shuffled).</summary>
    Seed: Cardinal;
    /// <summary>Namen wie gewählt (Shuffled: ungemischt), für „Mit dieser Reihenfolge erneut“.</summary>
    Names: TArray<string>;
    /// <summary>Namen für --run je Start, in der Reihenfolge der Starts.</summary>
    Steps: TArray<TArray<string>>;
    /// <summary>Gemeldete Starts.</summary>
    Done: Integer;
    PassedSteps: Integer;
    FailedSteps: Integer;
    Tests: TArray<TAtlasTestSeriesTally>;
    /// <summary>Abgebrochen (Benutzer) bzw. Grund, aus dem ein Start ohne Bericht endete; '' ohne.</summary>
    Cancelled: Boolean;
    Stopped: string;
    /// <summary>ACount Starts mit den Namen ANames.</summary>
    class function Repeating(const ASubject: TAtlasTestSeriesSubject; const ANames: TArray<string>;
      ACount: Integer): TAtlasTestSeries; static;
    /// <summary>Je Name ein Start, gemischt mit ASeed.</summary>
    class function Shuffling(const ASubject: TAtlasTestSeriesSubject; const ANames: TArray<string>;
      ASeed: Cardinal): TAtlasTestSeries; static;
    /// <summary>Geplante Starts.</summary>
    function Total: Integer;
    /// <summary>Alle Starts gemeldet, abgebrochen oder ohne Bericht beendet.</summary>
    function Finished: Boolean;
    /// <summary>Namen des nächsten Starts; leer, wenn die Serie fertig ist.</summary>
    function NextNames: TArray<string>;
    /// <summary>Ergebnis des nächsten Starts zählen (ARun mit gültigem Bericht).</summary>
    procedure Add(const ARun: TTestRunResult);
    /// <summary>Tests mit mindestens einem Fehlschlag, die häufigsten zuerst, bei Gleichstand nach Namen.</summary>
    function Failing: TArray<TAtlasTestSeriesTally>;
    /// <summary>Stand für die Marke; Passed ohne Fehlschlag, Failed ohne bestandenen Start, sonst Mixed.</summary>
    function State: TAtlasTestSeriesState;
    /// <summary>Beschriftung der Marke; während der Serie (ARunning) „Tests laufen … 7/20“.</summary>
    function Caption(const ATexts: TAtlasTestSeriesTexts; ARunning: Boolean): string;
  end;

  TAtlasTestShuffle = class
  public const
    /// <summary>Startwerte liegen zwischen 1 und cSeedLimit (fünf Stellen, gut abzuschreiben).</summary>
    cSeedLimit = 99999;
  public
    /// <summary>ANames in der Reihenfolge, die ASeed ergibt (Fisher-Yates, minstd); gleich auf allen Systemen.
    /// </summary>
    class function Shuffled(const ANames: TArray<string>; ASeed: Cardinal): TArray<string>; static;
    /// <summary>Startwert 1 bis cSeedLimit aus einem Zähler (Uhr, Ticks).</summary>
    class function SeedOf(ATicks: UInt64): Cardinal; static;
    /// <summary>Anzahl aus der Eingabe AText, wenn sie eine ganze Zahl von AMin bis AMax ist.</summary>
    class function CountOf(const AText: string; AMin, AMax: Integer; out ACount: Integer): Boolean; static;
    /// <summary>Namen für --run, die je einen Test bzw. Fall treffen: alle Tests der Fixture AFixtureIndex
    /// (ATestIndex = -1), der Test ATestIndex (alle Fälle, ACaseIndex = -1) bzw. der Fall; alle Fixtures mit
    /// AFixtureIndex = -1. Tests mit [Ignore] fehlen. Leer bei ungültigem Index.</summary>
    class function SingleNames(const AUnit: TDUnitXUnit; AFixtureIndex, ATestIndex,
      ACaseIndex: Integer): TArray<string>; static;
  end;

implementation

const
  /// <summary>Modul und Faktor von minstd (Park und Miller, 1993).</summary>
  cMinStdModulus = 2147483647;
  cMinStdFactor = 48271;

{ TAtlasTestSeriesSubject }

class function TAtlasTestSeriesSubject.Make(const AUnitName, AFixture, AMethod,
  ACaseName: string): TAtlasTestSeriesSubject;
begin
  Result.UnitName := AUnitName;
  Result.Fixture := AFixture;
  Result.Method := AMethod;
  Result.CaseName := ACaseName;
end;

function TAtlasTestSeriesSubject.Matches(const AOther: TAtlasTestSeriesSubject): Boolean;
begin
  Result := SameText(UnitName, AOther.UnitName) and SameText(Fixture, AOther.Fixture) and
    SameText(Method, AOther.Method) and SameText(CaseName, AOther.CaseName);
end;

function TAtlasTestSeriesSubject.Caption: string;
begin
  Result := Fixture;
  if Method <> '' then
  begin
    Result := Result + '.' + Method;
  end;
  if CaseName <> '' then
  begin
    Result := Result + '.' + CaseName;
  end;
end;

{ TAtlasTestSeries }

class function TAtlasTestSeries.Repeating(const ASubject: TAtlasTestSeriesSubject; const ANames: TArray<string>;
  ACount: Integer): TAtlasTestSeries;
var
  mIndex: Integer;
begin
  Result := Default(TAtlasTestSeries);
  Result.Kind := TAtlasTestSeriesKind.Repeated;
  Result.Subject := ASubject;
  Result.Names := ANames;
  if (Length(ANames) = 0) or (ACount <= 0) then
  begin
    Exit;
  end;
  SetLength(Result.Steps, ACount);
  for mIndex := 0 to ACount - 1 do
  begin
    Result.Steps[mIndex] := ANames;
  end;
end;

class function TAtlasTestSeries.Shuffling(const ASubject: TAtlasTestSeriesSubject; const ANames: TArray<string>;
  ASeed: Cardinal): TAtlasTestSeries;
var
  mOrder: TArray<string>;
  mIndex: Integer;
begin
  Result := Default(TAtlasTestSeries);
  Result.Kind := TAtlasTestSeriesKind.Shuffled;
  Result.Subject := ASubject;
  Result.Names := ANames;
  Result.Seed := ASeed;
  mOrder := TAtlasTestShuffle.Shuffled(ANames, ASeed);
  SetLength(Result.Steps, Length(mOrder));
  for mIndex := 0 to High(mOrder) do
  begin
    Result.Steps[mIndex] := TArray<string>.Create(mOrder[mIndex]);
  end;
end;

function TAtlasTestSeries.Total: Integer;
begin
  Result := Length(Steps);
end;

function TAtlasTestSeries.Finished: Boolean;
begin
  Result := (Done >= Total) or Cancelled or (Stopped <> '');
end;

function TAtlasTestSeries.NextNames: TArray<string>;
begin
  Result := nil;
  if not Finished then
  begin
    Result := Steps[Done];
  end;
end;

function TAtlasTestSeries.IndexOfTest(const AFullName: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(Tests) do
  begin
    if SameText(Tests[mIndex].FullName, AFullName) then
    begin
      Exit(mIndex);
    end;
  end;
end;

procedure TAtlasTestSeries.Add(const ARun: TTestRunResult);
var
  mCase: TTestCaseResult;
  mIndex: Integer;
  mTally: TAtlasTestSeriesTally;
begin
  if Finished then
  begin
    Exit;
  end;
  Inc(Done);
  if ARun.Count(TTestOutcome.Failed) + ARun.Count(TTestOutcome.Error) > 0 then
  begin
    Inc(FailedSteps);
  end
  else
  begin
    Inc(PassedSteps);
  end;
  for mCase in ARun.Cases do
  begin
    if mCase.Outcome = TTestOutcome.Skipped then
    begin
      Continue;
    end;
    mIndex := IndexOfTest(mCase.FullName);
    if mIndex < 0 then
    begin
      mTally := Default(TAtlasTestSeriesTally);
      mTally.FullName := mCase.FullName;
      Tests := Tests + [mTally];
      mIndex := High(Tests);
    end;
    if mCase.IsFailure then
    begin
      Inc(Tests[mIndex].Failed);
      Tests[mIndex].Message := mCase.Message;
    end
    else
    begin
      Inc(Tests[mIndex].Passed);
    end;
  end;
end;

function TAtlasTestSeries.Failing: TArray<TAtlasTestSeriesTally>;
var
  mTally, mSwap: TAtlasTestSeriesTally;
  mIndex, mOther: Integer;
begin
  Result := nil;
  for mTally in Tests do
  begin
    if mTally.Failed > 0 then
    begin
      Result := Result + [mTally];
    end;
  end;
  // Wenige Einträge: einfaches Einfügen, eindeutig über den Namen (stabil auf allen Systemen).
  for mIndex := 1 to High(Result) do
  begin
    mOther := mIndex;
    while (mOther > 0) and ((Result[mOther - 1].Failed < Result[mOther].Failed) or
      ((Result[mOther - 1].Failed = Result[mOther].Failed) and
      (CompareText(Result[mOther - 1].FullName, Result[mOther].FullName) > 0))) do
    begin
      mSwap := Result[mOther - 1];
      Result[mOther - 1] := Result[mOther];
      Result[mOther] := mSwap;
      Dec(mOther);
    end;
  end;
end;

function TAtlasTestSeries.State: TAtlasTestSeriesState;
begin
  Result := TAtlasTestSeriesState.Mixed;
  if FailedSteps = 0 then
  begin
    Result := TAtlasTestSeriesState.Passed;
  end
  else if PassedSteps = 0 then
  begin
    Result := TAtlasTestSeriesState.Failed;
  end;
end;

function TAtlasTestSeries.Caption(const ATexts: TAtlasTestSeriesTexts; ARunning: Boolean): string;
begin
  if ARunning then
  begin
    // Der laufende Start zählt mit: „1/20“ beim ersten.
    Result := Format(ATexts.Running, [Done + 1, Total]);
  end
  else if Kind = TAtlasTestSeriesKind.Shuffled then
  begin
    Result := Format(ATexts.Shuffled, [Seed, PassedSteps, FailedSteps]);
  end
  else
  begin
    Result := Format(ATexts.Repeated, [Done, PassedSteps, FailedSteps]);
  end;
end;

{ TAtlasTestShuffle }

class function TAtlasTestShuffle.Shuffled(const ANames: TArray<string>; ASeed: Cardinal): TArray<string>;
var
  mState: Int64;
  mIndex, mOther: Integer;
  mSwap: string;
begin
  Result := Copy(ANames);
  mState := Int64(ASeed) mod cMinStdModulus;
  if mState = 0 then
  begin
    mState := 1;
  end;
  for mIndex := High(Result) downto 1 do
  begin
    // Produkt unter 2^47: kein Überlauf in Int64.
    mState := (mState * cMinStdFactor) mod cMinStdModulus;
    mOther := Integer(mState mod (mIndex + 1));
    mSwap := Result[mIndex];
    Result[mIndex] := Result[mOther];
    Result[mOther] := mSwap;
  end;
end;

class function TAtlasTestShuffle.SeedOf(ATicks: UInt64): Cardinal;
begin
  Result := Cardinal(ATicks mod cSeedLimit) + 1;
end;

class function TAtlasTestShuffle.CountOf(const AText: string; AMin, AMax: Integer; out ACount: Integer): Boolean;
begin
  Result := TryStrToInt(Trim(AText), ACount) and (ACount >= AMin) and (ACount <= AMax);
end;

class function TAtlasTestShuffle.SingleNames(const AUnit: TDUnitXUnit; AFixtureIndex, ATestIndex,
  ACaseIndex: Integer): TArray<string>;
var
  mFixture, mTest: Integer;
begin
  Result := nil;
  if AFixtureIndex < 0 then
  begin
    for mFixture := 0 to High(AUnit.Fixtures) do
    begin
      Result := Result + SingleNames(AUnit, mFixture, -1, -1);
    end;
    Exit;
  end;
  if AFixtureIndex > High(AUnit.Fixtures) then
  begin
    Exit;
  end;
  if ATestIndex >= 0 then
  begin
    Result := TDUnitXCommandLine.RunNames(AUnit, AFixtureIndex, ATestIndex, ACaseIndex);
    Exit;
  end;
  for mTest := 0 to High(AUnit.Fixtures[AFixtureIndex].Tests) do
  begin
    if not AUnit.Fixtures[AFixtureIndex].Tests[mTest].Ignored then
    begin
      Result := Result + TDUnitXCommandLine.RunNames(AUnit, AFixtureIndex, mTest, -1);
    end;
  end;
end;

end.
