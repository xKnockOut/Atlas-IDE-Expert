unit Atlas.Core.Tests.Leaks;

// Lecks je Test (#1774), ohne VCL und Open Tools API:
// - Mit Leckmonitor (DUnitX.MemoryLeakMonitor.FastMM4/FastMM5) meldet DUnitX
//   einen Test, der Speicher nicht freigibt, als Fehlschlag mit
//   „40 bytes were leaked in the test method“ (TTestResults.LeakBytesOf).
// - Mit tests.leaks gilt er als bestanden mit Leck: Shown setzt das Ergebnis
//   auf bestanden und behält LeakBytes. Die Marke wird gelb, Atlas-Probleme
//   bekommt eine Warnung am Methodenkopf (TAtlasTestRun.LeakProblems).
// - Ohne tests.leaks bleibt es beim Fehlschlag aus dem Bericht.
// - Lecks am Programmende (keinem Test zuzuordnen): FastMM4 und FastMM5
//   schreiben ihren Bericht ohne Meldungsfenster in
//   <Programm>_MemoryManager_EventLog.txt neben die EXE (LogFileOf). Der
//   Läufer liest die Datei, wenn der Lauf sie geschrieben hat, sonst die
//   Ausgabe des Programms; ShutdownSummary fasst den Bericht
//   (Atlas.Text.LeakReport) zu „TStringList x 2, UnicodeString x 1“
//   zusammen.

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
    /// <summary>Datei, in die FastMM4/FastMM5 den Leckbericht von AExecutable schreiben.</summary>
    class function LogFileOf(const AExecutable: string): string; static;
    /// <summary>Lecks am Programmende aus dem Bericht AText: höchstens AMaxNames Namen mit Anzahl („TStringList x
    /// 2, UnicodeString x 1“, dahinter „…“), ABlocks alle Blöcke; '' ohne Bericht.</summary>
    class function ShutdownSummary(const AText: string; AMaxNames: Integer; out ABlocks: Integer): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.LeakReport;

const
  cLogSuffix = '_MemoryManager_EventLog.txt';
  cNameSeparator = ', ';
  cMore = ', …';
  cNameCount = '%s x %d';

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

class function TAtlasTestLeaks.LogFileOf(const AExecutable: string): string;
begin
  Result := '';
  if AExecutable <> '' then
  begin
    Result := ChangeFileExt(AExecutable, '') + cLogSuffix;
  end;
end;

class function TAtlasTestLeaks.ShutdownSummary(const AText: string; AMaxNames: Integer;
  out ABlocks: Integer): string;
var
  mReport: TLeakReport;
  mIndex: Integer;
begin
  Result := '';
  ABlocks := 0;
  mReport := TLeakReports.Parse(AText);
  if mReport.IsEmpty then
  begin
    Exit;
  end;
  for mIndex := 0 to High(mReport.Counts) do
  begin
    Inc(ABlocks, mReport.Counts[mIndex].Count);
    if mIndex < AMaxNames then
    begin
      if Result <> '' then
      begin
        Result := Result + cNameSeparator;
      end;
      Result := Result + Format(cNameCount, [mReport.Counts[mIndex].Name, mReport.Counts[mIndex].Count]);
    end
    else if mIndex = AMaxNames then
    begin
      Result := Result + cMore;
    end;
  end;
  Inc(ABlocks, Length(mReport.LargeSizes));
end;

end.
