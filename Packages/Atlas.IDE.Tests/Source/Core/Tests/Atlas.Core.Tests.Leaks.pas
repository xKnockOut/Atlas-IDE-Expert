unit Atlas.Core.Tests.Leaks;

// Lecks je Test (#1774), ohne VCL und Open Tools API:
// - Mit Leckmonitor (DUnitX.MemoryLeakMonitor.FastMM4/FastMM5) meldet DUnitX
//   einen Test, der Speicher nicht freigibt, als Fehlschlag mit
//   „40 bytes were leaked in the test method“ (TTestResults.LeakBytesOf).
// - Mit tests.leaks gilt er als bestanden mit Leck: Shown setzt das Ergebnis
//   auf bestanden und behält LeakBytes. Die Marke wird gelb, Atlas-Probleme
//   bekommt eine Warnung am Methodenkopf (TAtlasTestRun.LeakProblems).
// - Ohne tests.leaks bleibt es beim Fehlschlag aus dem Bericht.

interface

uses
  Atlas.Text.TestResults;

type
  TAtlasTestLeaks = class
  public
    /// <summary>ARun mit AShow (tests.leaks): Tests, die nur wegen eines Lecks fehlschlugen, als bestanden mit
    /// Leck; sonst ARun unverändert.</summary>
    class function Shown(const ARun: TTestRunResult; AShow: Boolean): TTestRunResult; static;
    /// <summary>Bestandene Tests mit Leck in Berichtsreihenfolge.</summary>
    class function Leaked(const ACases: TArray<TTestCaseResult>): TArray<TTestCaseResult>; static;
    /// <summary>Summe der nicht freigegebenen Bytes von ACases.</summary>
    class function TotalBytes(const ACases: TArray<TTestCaseResult>): Int64; static;
  end;

implementation

class function TAtlasTestLeaks.Shown(const ARun: TTestRunResult; AShow: Boolean): TTestRunResult;
var
  mIndex: Integer;
begin
  Result := ARun;
  if not AShow then
  begin
    Exit;
  end;
  // Eigene Kopie: Das Feld Cases teilt sich sonst das Array mit ARun.
  Result.Cases := Copy(ARun.Cases);
  for mIndex := 0 to High(Result.Cases) do
  begin
    if Result.Cases[mIndex].IsFailure and Result.Cases[mIndex].IsLeak then
    begin
      Result.Cases[mIndex].Outcome := TTestOutcome.Passed;
    end;
  end;
end;

class function TAtlasTestLeaks.Leaked(const ACases: TArray<TTestCaseResult>): TArray<TTestCaseResult>;
var
  mItem: TTestCaseResult;
begin
  Result := nil;
  for mItem in ACases do
  begin
    if (mItem.Outcome = TTestOutcome.Passed) and mItem.IsLeak then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

class function TAtlasTestLeaks.TotalBytes(const ACases: TArray<TTestCaseResult>): Int64;
var
  mItem: TTestCaseResult;
begin
  Result := 0;
  for mItem in ACases do
  begin
    Inc(Result, mItem.LeakBytes);
  end;
end;

end.
