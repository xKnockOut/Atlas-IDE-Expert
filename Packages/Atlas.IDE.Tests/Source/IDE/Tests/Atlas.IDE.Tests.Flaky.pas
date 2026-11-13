unit Atlas.IDE.Tests.Flaky;

// Wackelnde Tests in der IDE (#1773, tests.flaky, tests.flaky.runs):
// - Nach jedem gemeldeten Lauf (Haken OnReported des Läufers) hängt das Modul
//   je Test das Ergebnis mit der Prüfsumme des Rumpfs aus dem Text der
//   Testunit (Puffer der IDE, sonst Platte) an den Verlauf des Testprojekts
//   (Atlas.Core.Tests.Flaky) und schreibt ihn in
//   %LOCALAPPDATA%\Atlas\projects\tests-history\<Schlüssel>.json (Schlüssel
//   wie die Projekt-Zusammenfassung, TAtlasProjectSummaries.KeyOf). Den Lauf
//   reicht es danach an ANext weiter.
// - Ist ein Test, der beim Lauf davor rot war, jetzt grün, wackelt aber
//   (etwa nach „Fehlgeschlagene erneut ausführen“), steht in der
//   Meldungsansicht „bestanden, wackelt aber“.
// - Testlinse und Fenster „Atlas-Tests“ fragen über FlakyIn, welche Tests
//   einer Unit wackeln. Die Verläufe der Testprojekte der Projektgruppe lädt
//   das Modul beim ersten Bedarf, damit sie einen Neustart überstehen.
// Mit tests.flaky aus wird nichts geschrieben und nichts gemeldet.
// Nur im Hauptthread.

interface

uses
  System.Generics.Collections,
  Atlas.Text.DUnitX,
  Atlas.Text.TestResults,
  Atlas.Core.Tests.Run,
  Atlas.Core.Tests.Flaky,
  Atlas.IDE.Tests.Runner;

type
  TAtlasIdeFlakyTests = class
  private const
    cFolderName = 'tests-history';
    cKind = 'Testverlauf';
  private
    FTests: TAtlasIdeTests;
    FNext: TAtlasTestsReportedProc;
    /// <summary>Verlauf je Testprojekt (Schlüssel klein).</summary>
    FHistories: TObjectDictionary<string, TAtlasTestHistory>;
    /// <summary>Testprojekte (Schlüssel klein), deren Datei vorhanden, aber nicht lesbar war: nicht überschreiben.
    /// </summary>
    FKept: TArray<string>;
    /// <summary>Verlauf von AProject; beim ersten Mal aus der Datei.</summary>
    function HistoryOf(const AProject: string): TAtlasTestHistory;
    procedure Save(const AProject: string; AHistory: TAtlasTestHistory);
    /// <summary>„bestanden, wackelt aber“ für die Tests AKeys, die jetzt grün sind und davor rot waren.</summary>
    procedure TellPassedButFlaky(AHistory: TAtlasTestHistory; const AKeys: TArray<string>;
      const ACases: TArray<TTestCaseResult>);
  public
    /// <summary>ATests gehört dem Aufrufer und lebt länger; ANext bekommt jeden Lauf danach (nil = keiner).
    /// </summary>
    constructor Create(ATests: TAtlasIdeTests; const ANext: TAtlasTestsReportedProc);
    destructor Destroy; override;
    /// <summary>Datei des Verlaufs von AProject.</summary>
    class function FileOf(const AProject: string): string; static;
    /// <summary>Ergebnisse aus ARun an den Verlauf hängen (Haken OnReported).</summary>
    procedure Remember(const ATarget: TAtlasTestTarget; const ARun: TTestRunResult);
    /// <summary>Wackelnde Tests von AUnit (Text ALines); leer mit tests.flaky aus.</summary>
    function FlakyIn(const AUnit: TDUnitXUnit; const ALines: TArray<string>): TArray<TAtlasFlakyTest>;
    /// <summary>Abfragen für Testlinse und Fenster: veraltete Tests über AStaleKeys, wackelnde über FlakyIn.
    /// </summary>
    function QueriesWith(const AStaleKeys: TAtlasTestStaleKeys): TAtlasTestStateQueries;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.IOUtils,
  System.DateUtils,
  ToolsAPI,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Tests.Stale,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Tests.Projects,
  Atlas.UI.Tests.Strings;

{ TAtlasIdeFlakyTests }

constructor TAtlasIdeFlakyTests.Create(ATests: TAtlasIdeTests; const ANext: TAtlasTestsReportedProc);
begin
  inherited Create;
  FTests := ATests;
  FNext := ANext;
  FHistories := TObjectDictionary<string, TAtlasTestHistory>.Create([doOwnsValues]);
end;

destructor TAtlasIdeFlakyTests.Destroy;
begin
  FHistories.Free;
  FNext := nil;
  FKept := nil;
  inherited Destroy;
end;

class function TAtlasIdeFlakyTests.FileOf(const AProject: string): string;
begin
  Result := TAtlasProjectSummaries.FileFor(TPath.Combine(TAtlasProjectSummaries.DefaultFolder, cFolderName),
    AProject);
end;

function TAtlasIdeFlakyTests.HistoryOf(const AProject: string): TAtlasTestHistory;
var
  mKey: string;
  mHistory: TAtlasTestHistory;
begin
  mKey := AnsiLowerCase(AProject);
  if FHistories.TryGetValue(mKey, Result) then
  begin
    Exit;
  end;
  mHistory := TAtlasTestHistory.Create;
  FHistories.Add(mKey, mHistory);
  mHistory.MaxRuns := TAtlasIdeSettings.Current.TestsFlakyRuns;
  // Fehlt die Datei oder ist sie unbrauchbar, beginnt der Verlauf leer; eine gesperrte bleibt unangetastet.
  if not TAtlasDataFile.Writable(TAtlasDataFile.Load(FileOf(AProject), cKind,
    function(const AText: string): Boolean
    begin
      Result := mHistory.LoadJson(AText);
    end)) then
  begin
    FKept := FKept + [mKey];
  end;
  Result := mHistory;
end;

procedure TAtlasIdeFlakyTests.Save(const AProject: string; AHistory: TAtlasTestHistory);
begin
  if IndexStr(AnsiLowerCase(AProject), FKept) >= 0 then
  begin
    Exit;
  end;
  try
    TAtlasDataFile.Write(FileOf(AProject), AHistory.ToJson(AProject));
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten(cKind, E);
  end;
end;

/// <summary>Kurzer Name eines Tests (Fixture.Methode) aus ACases zum Schlüssel AKey; sonst der Schlüssel.</summary>
function ShortNameOf(const ACases: TArray<TTestCaseResult>; const AKey: string): string;
var
  mCase: TTestCaseResult;
begin
  for mCase in ACases do
  begin
    if TAtlasTestStamps.KeyOf(mCase.UnitName, mCase.Fixture, mCase.Method) = AKey then
    begin
      Exit(mCase.Fixture + '.' + mCase.Method);
    end;
  end;
  Result := AKey;
end;

procedure TAtlasIdeFlakyTests.TellPassedButFlaky(AHistory: TAtlasTestHistory; const AKeys: TArray<string>;
  const ACases: TArray<TTestCaseResult>);
var
  mKey: string;
  mFlaky: TAtlasFlakyTest;
begin
  for mKey in AKeys do
  begin
    if AHistory.PassedButFlaky(mKey, mFlaky) then
    begin
      FTests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsFlakyPassed, [ShortNameOf(ACases, mKey),
        mFlaky.Failed, mFlaky.Runs]));
    end;
  end;
end;

procedure TAtlasIdeFlakyTests.Remember(const ATarget: TAtlasTestTarget; const ARun: TTestRunResult);
var
  mHistory: TAtlasTestHistory;
  mDone, mKeys, mLines: TArray<string>;
  mItem: TTestCaseResult;
  mFileName: string;
  mNow: TDateTime;
begin
  if TAtlasIdeSettings.Current.TestsFlaky and (ATarget.Project <> '') and (Length(ARun.Cases) > 0) then
  begin
    mHistory := HistoryOf(ATarget.Project);
    mHistory.MaxRuns := TAtlasIdeSettings.Current.TestsFlakyRuns;
    mNow := TTimeZone.Local.ToUniversalTime(Now);
    mDone := nil;
    mKeys := nil;
    // Jede Testunit des Laufs einmal, mit dem Text von jetzt.
    for mItem in ARun.Cases do
    begin
      if (mItem.UnitName = '') or (IndexText(mItem.UnitName, mDone) >= 0) then
      begin
        Continue;
      end;
      mDone := mDone + [mItem.UnitName];
      mFileName := TAtlasIdeTests.UnitFileOf(ATarget.Project, mItem.UnitName);
      if (mFileName <> '') and TAtlasIdeFiles.ReadLines(mFileName, mLines) then
      begin
        mKeys := mKeys + mHistory.Remember(TDUnitXSource.Scan(mLines), mLines, ARun.Cases, mNow);
      end;
    end;
    if Length(mKeys) > 0 then
    begin
      Save(ATarget.Project, mHistory);
      TellPassedButFlaky(mHistory, mKeys, ARun.Cases);
    end;
  end;
  if Assigned(FNext) then
  begin
    FNext(ATarget, ARun);
  end;
end;

function TAtlasIdeFlakyTests.FlakyIn(const AUnit: TDUnitXUnit; const ALines: TArray<string>): TArray<TAtlasFlakyTest>;
var
  mProject: IOTAProject;
  mHistory: TAtlasTestHistory;
  mFlaky: TAtlasFlakyTest;
  mKeys: TArray<string>;
begin
  Result := nil;
  if not TAtlasIdeSettings.Current.TestsFlaky or (Length(AUnit.Fixtures) = 0) then
  begin
    Exit;
  end;
  // Verläufe der Testprojekte der Projektgruppe: nach einem Neustart beim ersten Bedarf aus der Datei.
  for mProject in TAtlasIdeTestProjects.TestProjects('') do
  begin
    HistoryOf(mProject.FileName);
  end;
  mKeys := nil;
  for mHistory in FHistories.Values do
  begin
    for mFlaky in mHistory.FlakyIn(AUnit, ALines) do
    begin
      // Liegt eine Unit in mehreren Testprojekten, zählt der erste Verlauf, der wackelt.
      if IndexStr(mFlaky.Key, mKeys) < 0 then
      begin
        mKeys := mKeys + [mFlaky.Key];
        Result := Result + [mFlaky];
      end;
    end;
  end;
end;

function TAtlasIdeFlakyTests.QueriesWith(const AStaleKeys: TAtlasTestStaleKeys): TAtlasTestStateQueries;
begin
  Result := Default(TAtlasTestStateQueries);
  Result.StaleKeys := AStaleKeys;
  Result.Flaky := FlakyIn;
end;

end.
