unit Atlas.Core.Tests.LastRun;

// Letzten Testlauf für KI-Assistenten ablegen (#2409, tests.lastRun), ohne VCL und Open Tools API, auch unter FPC
// prüfbar: Aus Ziel, Bericht, Fundstellen, Protokoll je Test (#2168) und dem Verlauf der wackelnden Tests (#1773)
// entsteht der Lauf im Format von Atlas.Text.TestRunFile; neu rot bzw. wieder grün kommt aus dem Vergleich mit der
// Datei des Laufs davor. Schreiben und die Daten der IDE holt Atlas.IDE.Tests.LastRun.

interface

uses
  Atlas.Text.TestResults,
  Atlas.Text.TestRunFile,
  Atlas.Core.Tests.Log;

type
  /// <summary>Fundstelle eines Tests: Datei und Zeile (0-basiert; -1 ohne).</summary>
  TAtlasTestPlace = record
    Name: string;
    FileName: string;
    Line: Integer;
    class function Make(const AName, AFileName: string; ALine: Integer): TAtlasTestPlace; static;
  end;

  /// <summary>Wackelt ACase? Dann rote und alle gemerkten Läufe; nil = keine Abfrage.</summary>
  TAtlasTestFlakyCount = reference to function(const ACase: TTestCaseResult; out AFailed, ARuns: Integer): Boolean;

  /// <summary>Was zum Lauf gehört.</summary>
  TAtlasTestLastRunParts = record
    Project: string;
    Configuration: string;
    Platform: string;
    /// <summary>Namen für --run; leer = alle.</summary>
    Filter: TArray<string>;
    Run: TTestRunResult;
    Places: TArray<TAtlasTestPlace>;
    Log: TAtlasTestLogRun;
    Units: TArray<TTestRunUnit>;
    FinishedAtUtc: TDateTime;
    Flaky: TAtlasTestFlakyCount;
  end;

  TAtlasTestLastRun = class
  public const
    /// <summary>Höchstens so viele Protokollzeilen je rotem Test (die letzten).</summary>
    cLogLines = 10;
  public
    /// <summary>Lauf aus AParts; APreviousText ist der Inhalt der Datei davor ('' ohne) für neu rot und wieder
    /// grün.</summary>
    class function Build(const AParts: TAtlasTestLastRunParts; const APreviousText: string): TTestRunFile; static;
    /// <summary>Units der Tests in ACases, jede einmal, in Reihenfolge des Berichts.</summary>
    class function UnitNames(const ACases: TArray<TTestCaseResult>): TArray<string>; static;
    /// <summary>Die letzten AMax Zeilen aus Log und Konsole des Tests AName; leer ohne Logger oder Zeilen.</summary>
    class function LogExcerpt(const ALog: TAtlasTestLogRun; const AName: string; AMax: Integer): TArray<string>;
      static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

{ TAtlasTestPlace }

class function TAtlasTestPlace.Make(const AName, AFileName: string; ALine: Integer): TAtlasTestPlace;
begin
  Result.Name := AName;
  Result.FileName := AFileName;
  Result.Line := ALine;
end;

{ TAtlasTestLastRun }

class function TAtlasTestLastRun.UnitNames(const ACases: TArray<TTestCaseResult>): TArray<string>;
var
  mCase: TTestCaseResult;
begin
  Result := nil;
  for mCase in ACases do
  begin
    if (mCase.UnitName <> '') and not MatchText(mCase.UnitName, Result) then
    begin
      Result := Result + [mCase.UnitName];
    end;
  end;
end;

class function TAtlasTestLastRun.LogExcerpt(const ALog: TAtlasTestLogRun; const AName: string;
  AMax: Integer): TArray<string>;
var
  mIndex: Integer;
  mLine: TAtlasTestLogLine;
begin
  Result := nil;
  mIndex := ALog.IndexOf(AName);
  if (mIndex < 0) or (AMax <= 0) then
  begin
    Exit;
  end;
  for mLine in ALog.Entries[mIndex].Lines do
  begin
    // Beginn und Ende setzt Atlas selbst; sie sagen nichts über den Fehlschlag.
    if mLine.Origin in [TAtlasTestLogOrigin.Log, TAtlasTestLogOrigin.Console] then
    begin
      Result := Result + [mLine.Text];
    end;
  end;
  if Length(Result) > AMax then
  begin
    Result := Copy(Result, Length(Result) - AMax, AMax);
  end;
end;

/// <summary>Fundstelle des Tests AName in APlaces; False ohne.</summary>
function PlaceOf(const APlaces: TArray<TAtlasTestPlace>; const AName: string; out APlace: TAtlasTestPlace): Boolean;
var
  mPlace: TAtlasTestPlace;
begin
  for mPlace in APlaces do
  begin
    if SameText(mPlace.Name, AName) then
    begin
      APlace := mPlace;
      Exit(True);
    end;
  end;
  APlace := Default(TAtlasTestPlace);
  Result := False;
end;

function CaseOf(const AParts: TAtlasTestLastRunParts; const ATest: TTestCaseResult): TTestRunFileCase;
var
  mPlace: TAtlasTestPlace;
  mFailed, mRuns: Integer;
begin
  Result := Default(TTestRunFileCase);
  Result.Test := ATest;
  // Der Stacktrace bleibt in der IDE; Datei und Zeile stehen schon als Fundstelle da.
  Result.Test.StackTrace := '';
  if PlaceOf(AParts.Places, ATest.FullName, mPlace) and (mPlace.FileName <> '') then
  begin
    Result.FileName := mPlace.FileName;
    if mPlace.Line >= 0 then
    begin
      Result.Line := mPlace.Line + 1;
    end;
  end;
  if Assigned(AParts.Flaky) and AParts.Flaky(ATest, mFailed, mRuns) then
  begin
    Result.FlakyFailed := mFailed;
    Result.FlakyRuns := mRuns;
  end;
  if ATest.IsFailure then
  begin
    Result.Log := TAtlasTestLastRun.LogExcerpt(AParts.Log, ATest.FullName, TAtlasTestLastRun.cLogLines);
  end;
end;

class function TAtlasTestLastRun.Build(const AParts: TAtlasTestLastRunParts;
  const APreviousText: string): TTestRunFile;
var
  mTest: TTestCaseResult;
  mPrevious: TTestRunFile;
begin
  Result := Default(TTestRunFile);
  Result.Project := AParts.Project;
  Result.Configuration := AParts.Configuration;
  Result.Platform := AParts.Platform;
  Result.Filter := Copy(AParts.Filter);
  Result.FinishedAtUtc := AParts.FinishedAtUtc;
  Result.DurationMs := AParts.Run.DurationMs;
  Result.Units := Copy(AParts.Units);
  for mTest in AParts.Run.Cases do
  begin
    Result.Cases := Result.Cases + [CaseOf(AParts, mTest)];
  end;
  if (APreviousText <> '') and TTestRunFiles.Parse(APreviousText, mPrevious) and
    SameText(mPrevious.Project, AParts.Project) then
  begin
    TTestRunFiles.MarkChanges(mPrevious, Result);
  end;
end;

end.
