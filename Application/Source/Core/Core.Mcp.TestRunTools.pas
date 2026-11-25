unit Core.Mcp.TestRunTools;

// Host-Rolle Core: MCP-Modus (--mcp, #48), DUnitX-Testläufe (run_tests, #69) und der letzte Testlauf der IDE
// (get_last_tests, #2409).

interface

uses
  Core.Mcp.Context;

/// <summary>Meldet run_tests an.</summary>
procedure AddRunTests(const AContext: TMcpToolContext);
/// <summary>Meldet get_last_tests an.</summary>
procedure AddGetLastTests(const AContext: TMcpToolContext);

implementation

uses
{$IFDEF MSWINDOWS}
  // Für das inline-DeleteFile der RTL (H2443); die Plattformadapter kommen aus Platform.Server.
  Winapi.Windows,
{$ENDIF}
  System.SysUtils,
  // Inline-Funktionen von TJSONArray (H2443).
  System.Generics.Collections,
  System.Classes,
  System.SyncObjs,
  System.IOUtils,
  System.JSON,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.BuildTools,
  Atlas.Common.Mcp.TestTools,
  Atlas.Common.Mcp.ProfileTools,
  Atlas.Common.Mcp.LastTests,
  Atlas.Text.TestRunFile,
  Atlas.Common.Compiler.Contract,
  Atlas.Text.Lines,
  Atlas.Text.DUnitX.CommandLine,
  Atlas.Text.TestResults,
  Atlas.Common.Compiler.IdeBuild,
  Atlas.Common.Index.CacheDirectory,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Mutation.Report,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Lsp.BoundaryCases,
  Atlas.Common.Mcp.CompilerMessageTools,
  Atlas.Common.Mcp.IndexTools,
  Atlas.Common.Mcp.Paths,
  Atlas.Common.Configuration.Contract,
  Core.Texts,
  Core.Mcp.Ide,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TMcpTestRunText = (RunTestsTool, RunTestsProject, RunTestsTests, RunTestsBuild, RunTestsConfiguration,
    RunTestsPlatform, RunTestsTimeoutSeconds, ProjectUnreadable, BuildFailed, TimedOut, ExeMissing, GetLastTestsTool,
    GetLastTestsProject, GetLastTestsOnly, GetLastTestsMax, GetLastTestsFormat);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TMcpTestRunText] of TAtlasText = (
    (De: 'Führt die DUnitX-Tests eines Testprojekts aus (#69) und liefert bestandene, fehlgeschlagene und ' +
    'übersprungene Tests; jeder fehlgeschlagene Test mit Meldung, erwartetem und tatsächlichem Wert, Datei ' +
    'und Zeile. Startet die vorhandene Test-EXE ohne Compiler; mit build: true baut es das Projekt vorher in ' +
    'der laufenden IDE wie build_project. Die Plattform kommt aus dem Testprojekt (ein Projekt nur für Win64 ' +
    'läuft als Win64). Das Testprogramm braucht den XML-Logger von DUnitX (Vorlage von RAD Studio).';
    En: 'Runs the DUnitX tests of a test project (#69) and returns passed, failed and skipped tests; each failed ' +
    'test with message, expected and actual value, file and line. Starts the existing test EXE without a ' +
    'compiler; with build: true it first builds the project in the running IDE like build_project. The ' +
    'platform comes from the test project (a project only for Win64 runs as Win64). The test program needs ' +
    'the XML logger of DUnitX (RAD Studio template).'),
    (De: 'Testprojekt (.dproj mit Pfad, Dateiname oder Name); leer = das einzige DUnitX-Projekt unter dem ' +
    'Arbeitsordner';
    En: 'Test project (.dproj with path, file name or name); empty = the only DUnitX project below the working ' +
    'folder'),
    (De: 'Nur diese Tests: Unit.Fixture oder Unit.Fixture.Methode; leer = alle';
    En: 'Only these tests: Unit.Fixture or Unit.Fixture.Method; empty = all'),
    (De: 'Vorher in der IDE bauen (make)'; En: 'Build in the IDE first (make)'),
    (De: 'z. B. Debug; leer = Vorgabe des Projekts'; En: 'e.g. Debug; empty = project default'),
    (De: 'z. B. Win64; leer = Vorgabe des Projekts, sonst die erste aktivierte Plattform';
    En: 'e.g. Win64; empty = project default, otherwise the first enabled platform'),
    (De: 'Zeitlimit des Testlaufs in Sekunden (höchstens 3600)';
    En: 'Time limit of the test run in seconds (at most 3600)'),
    (De: 'Projektdatei nicht lesbar: %s'; En: 'Project file not readable: %s'),
    (De: 'Build fehlgeschlagen; Tests nicht ausgeführt.'; En: 'Build failed; tests not run.'),
    (De: 'Testlauf nach %d s abgebrochen (timeoutSeconds).'; En: 'Test run aborted after %d s (timeoutSeconds).'),
    (De: 'Test-EXE fehlt: %s. Mit "build": true bauen oder das Projekt in der IDE für %s/%s bauen.';
    En: 'Test EXE missing: %s. Build with "build": true or build the project in the IDE for %s/%s.'),
    (De: 'Ergebnis des letzten Testlaufs in der IDE ohne neuen Lauf (#2409): Testprojekt, Plattform, ' +
    'Konfiguration, Zeitpunkt, Dauer und Zahlen; je Test Meldung, Datei und Zeile, erwartet und erhalten, ' +
    'Protokollauszug und Marken neu rot, wieder grün, wackelig, Leck und veraltet (Testunit seit dem Lauf ' +
    'geändert). Erst hier nachsehen, dann gezielt run_tests mit tests. Ohne laufende IDE die zuletzt abgelegte ' +
    'Fassung mit Zeitstempel. Lesend.';
    En: 'Result of the last test run in the IDE without a new run (#2409): test project, platform, ' +
    'configuration, time, duration and counts; per test message, file and line, expected and actual, log ' +
    'excerpt and marks newly red, green again, flaky, leak and stale (test unit changed since the run). Look ' +
    'here first, then run_tests with tests for the ones that matter. Without a running IDE the last stored ' +
    'version with time stamp. Read-only.'),
    (De: 'Testprojekt (Name, .dproj oder Pfad); leer = letzter Lauf, bevorzugt unter dem Arbeitsordner';
    En: 'Test project (name, .dproj or path); empty = last run, preferably below the working folder'),
    (De: 'failed (Vorgabe): rote Tests; flaky: wackelnde; slow: langsamste zuerst; leaks: mit Leck; stale: ' +
    'veraltete Ergebnisse; all: alle';
    En: 'failed (default): red tests; flaky: flaky ones; slow: slowest first; leaks: with leak; stale: stale ' +
    'results; all: all'),
    (De: 'Höchstens so viele Tests (Vorgabe 20, bis 500); der Rest als Zahl';
    En: 'At most this many tests (default 20, up to 500); the rest as a number'),
    (De: 'text oder json'; En: 'text or json'));

function ReadSourceLines(const AFileName: string; out ALines: TArray<string>): Boolean;
var
  mText: string;
begin
  Result := ReadSourceText(AFileName, mText);
  if Result then
  begin
    ALines := TTextLines.SplitLines(mText);
  end
  else
  begin
    ALines := nil;
  end;
end;

/// <summary>Führt die Test-EXE aus (#69): Ergebnis im XML-Bericht AResultFile; AOutput die letzten Zeilen der
/// Ausgabe. Beendet den Prozess nach ATimeoutSeconds; dann ATimedOut.</summary>
function RunTestProcess(const AProcess: ICompilerProcess; const ATarget: TMcpTestTarget;
  const AArguments: TArray<string>; ATimeoutSeconds: Integer; out AOutput: TArray<string>;
  out ATimedOut: Boolean): Integer;
const
  cKeptLines = 40;
var
  mProcess: ICompilerProcess;
  mRequest: TCompilerRequest;
  mFinished: TEvent;
  mWatcher: TThread;
  mOutput: TArray<string>;
  mTimedOut: Boolean;
begin
  mProcess := AProcess;
  mRequest := Default(TCompilerRequest);
  mRequest.Executable := ATarget.Executable;
  mRequest.Arguments := AArguments;
  mRequest.WorkingDir := ATarget.WorkingDir;
  mOutput := nil;
  mTimedOut := False;
  mFinished := TEvent.Create(nil, True, False, '');
  try
    mWatcher := TThread.CreateAnonymousThread(
      procedure
      begin
        if mFinished.WaitFor(Cardinal(ATimeoutSeconds) * 1000) = wrTimeout then
        begin
          mTimedOut := True;
          mProcess.Cancel;
        end;
      end);
    mWatcher.FreeOnTerminate := False;
    mWatcher.Start;
    try
      try
        Result := mProcess.Run(mRequest,
          procedure(const ALine: string)
          begin
            mOutput := mOutput + [ALine];
            if Length(mOutput) > cKeptLines then
            begin
              Delete(mOutput, 0, Length(mOutput) - cKeptLines);
            end;
          end);
      except
        on ECompilerCancelled do
          Result := -1;
      end;
    finally
      mFinished.SetEvent;
      mWatcher.WaitFor;
      mWatcher.Free;
    end;
  finally
    mFinished.Free;
  end;
  AOutput := mOutput;
  ATimedOut := mTimedOut;
end;

/// <summary>Testprojekt aus dem Argument project: Pfad (relativ zum Arbeitsordner) oder Name; ohne das einzige
/// DUnitX-Projekt unter ARoot. EMcpToolError, wenn keins passt.</summary>
function TestProjectOf(const ARoot: string; const AArguments: TJSONObject): string;
var
  mWanted, mReason: string;
begin
  mWanted := TMcpArgs.OptionalString(AArguments, 'project');
  if (mWanted <> '') and ((Pos('\', mWanted) > 0) or (Pos('/', mWanted) > 0)) and not TPath.IsPathRooted(mWanted) then
  begin
    mWanted := TPath.GetFullPath(TPath.Combine(ARoot, mWanted));
  end;
  if (mWanted <> '') and TPath.IsPathRooted(mWanted) and FileExists(mWanted) then
  begin
    Exit(mWanted);
  end;
  if not TMcpTestTools.PickProject(ProjectFilesUnder(ARoot), mWanted,
    function(AFileName: string): Boolean
    begin
      Result := IsTestProject(AFileName);
    end, Result, mReason) then
  begin
    raise EMcpToolError.Create(mReason);
  end;
end;

/// <summary>Liest AProject für AConfiguration und APlatform ('' = Vorgaben); EMcpToolError, wenn nicht lesbar.
/// </summary>
procedure LoadTestProject(const AProject, AConfiguration, APlatform: string; out AInfo: TProjectInfo);
begin
  if not LoadProject(AProject, AConfiguration, APlatform, AInfo) then
  begin
    raise EMcpToolError.Create(cTexts[TMcpTestRunText.ProjectUnreadable].Fmt([AProject]));
  end;
end;

/// <summary>Ziel des Testlaufs: Projekt, Plattform aus dem Projekt (#14), Konfiguration und Test-EXE.</summary>
function TestTargetOf(const AProject: string; const AArguments: TJSONObject; out AInfo: TProjectInfo):
  TMcpTestTarget;
var
  mConfiguration, mReason: string;
begin
  Result := Default(TMcpTestTarget);
  Result.Project := AProject;
  mConfiguration := TMcpArgs.OptionalString(AArguments, 'configuration');
  // Erst die Vorgaben der Datei lesen, dann für die Wahl der Plattform auswerten.
  LoadTestProject(AProject, mConfiguration, '', AInfo);
  if not TMcpTestTools.ChoosePlatform(TMcpArgs.OptionalString(AArguments, 'platform'), AInfo.Platform,
    AInfo.Platforms, Result.Platform, mReason) then
  begin
    raise EMcpToolError.Create(mReason);
  end;
  LoadTestProject(AProject, mConfiguration, Result.Platform, AInfo);
  Result.Configuration := AInfo.Config;
  Result.Executable := TMcpTestTools.ExecutableOf(AInfo);
  Result.WorkingDir := ExtractFileDir(Result.Executable);
end;

/// <summary>Zeitlimit aus timeoutSeconds, begrenzt auf TMcpTestTools.cMaxTimeoutSeconds.</summary>
function TestTimeoutOf(const AArguments: TJSONObject): Integer;
begin
  if (AArguments = nil) or not AArguments.TryGetValue<Integer>('timeoutSeconds', Result) or (Result <= 0) then
  begin
    Result := TMcpTestTools.cDefaultTimeoutSeconds;
  end;
  if Result > TMcpTestTools.cMaxTimeoutSeconds then
  begin
    Result := TMcpTestTools.cMaxTimeoutSeconds;
  end;
end;

/// <summary>Mit build: true vorher in der IDE bauen; True mit dem Bericht in AReport, wenn das scheitert.</summary>
function BuildBeforeTestsFailed(const ARoot: string; const ATarget: TMcpTestTarget; const AArguments: TJSONObject;
  out AReport: string): Boolean;
var
  mBuildFirst: Boolean;
  mBuild: TIdeBuild;
begin
  AReport := '';
  if (AArguments = nil) or not AArguments.TryGetValue<Boolean>('build', mBuildFirst) then
  begin
    mBuildFirst := False;
  end;
  Result := False;
  if mBuildFirst then
  begin
    mBuild := BuildInIde(ARoot, ATarget.Project, 'make', ATarget.Configuration, ATarget.Platform,
      Default(TMcpIdeOpen));
    Result := not mBuild.Success;
    if Result then
    begin
      AReport := cTexts[TMcpTestRunText.BuildFailed].Text + sLineBreak +
        TMcpBuildTools.Report(mBuild, ARoot, '');
    end;
  end;
end;

/// <summary>Startet die Test-EXE mit dem XML-Logger von DUnitX und liefert den Bericht.</summary>
function RunTestExe(const AProcess: ICompilerProcess; const ATarget: TMcpTestTarget; const ATests: TArray<string>;
  ATimeout: Integer; const AInfo: TProjectInfo): string;
var
  mResultFile, mXml: string;
  mOutput: TArray<string>;
  mTimedOut: Boolean;
  mCode: Integer;
begin
  mResultFile := TPath.Combine(TPath.GetTempPath, Format('atlas-tests-%s.xml',
    [TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '')]));
  try
    mCode := RunTestProcess(AProcess, ATarget, TDUnitXCommandLine.Arguments(mResultFile, ATests), ATimeout, mOutput,
      mTimedOut);
    if mTimedOut then
    begin
      raise EMcpToolError.Create(cTexts[TMcpTestRunText.TimedOut].Fmt([ATimeout]));
    end;
    mXml := '';
    if FileExists(mResultFile) then
    begin
      mXml := TFile.ReadAllText(mResultFile, TEncoding.UTF8);
    end;
    Result := TMcpTestTools.Report(ATarget, ATests, TTestResults.Parse(mXml),
      TMcpTestProcess.Make(mCode, mOutput), AInfo.Units,
      ReadSourceLines);
  finally
    if FileExists(mResultFile) then
    begin
      System.SysUtils.DeleteFile(mResultFile);
    end;
  end;
end;

function ToolRunTests(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mTarget: TMcpTestTarget;
  mInfo: TProjectInfo;
  mTests: TArray<string>;
  mTimeout: Integer;
begin
  mTarget := TestTargetOf(TestProjectOf(AContext.Root, AArguments), AArguments, mInfo);
  mTests := TMcpTestTools.TestsOf(AArguments);
  mTimeout := TestTimeoutOf(AArguments);
  if BuildBeforeTestsFailed(AContext.Root, mTarget, AArguments, Result) then
  begin
    Exit;
  end;
  if not FileExists(mTarget.Executable) then
  begin
    raise EMcpToolError.Create(cTexts[TMcpTestRunText.ExeMissing].Fmt([mTarget.Executable, mTarget.Configuration,
      mTarget.Platform]));
  end;
  Result := RunTestExe(AContext.Adapters.NewProcess(), mTarget, mTests, mTimeout, mInfo);
end;

procedure AddRunTests(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('run_tests', cTexts[TMcpTestRunText.RunTestsTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"project":{"type":"string","description":%s},' +
      '"tests":{"type":"array","items":{"type":"string"},' +
      '"description":%s},' +
      '"build":{"type":"boolean","default":false,"description":%s},' +
      '"configuration":{"type":"string","description":%s},' +
      '"platform":{"type":"string","description":%s},' +
      '"timeoutSeconds":{"type":"integer","default":600,"description":%s}}}',
      [cTexts[TMcpTestRunText.RunTestsProject].Text,
      cTexts[TMcpTestRunText.RunTestsTests].Text,
      cTexts[TMcpTestRunText.RunTestsBuild].Text,
      cTexts[TMcpTestRunText.RunTestsConfiguration].Text,
      cTexts[TMcpTestRunText.RunTestsPlatform].Text,
      cTexts[TMcpTestRunText.RunTestsTimeoutSeconds].Text]),
    ContextTool(AContext, ToolRunTests), TMcpToolKind.Process);
end;

/// <summary>Abgelegte Testläufe der IDE (#2409); unlesbare Dateien fallen weg.</summary>
function LoadTestRuns(const AFolder: string): TArray<TTestRunFile>;
var
  mFile, mText: string;
  mRun: TTestRunFile;
begin
  Result := nil;
  if not TDirectory.Exists(AFolder) then
  begin
    Exit;
  end;
  for mFile in TDirectory.GetFiles(AFolder, '*.json') do
  begin
    // Das Plugin ersetzt die Datei atomar; gesperrt oder halb geschrieben zählt wie nicht vorhanden.
    if ReadSourceText(mFile, mText) and TTestRunFiles.Parse(mText, mRun) then
    begin
      Result := Result + [mRun];
    end;
  end;
end;

/// <summary>Letzte Schreibzeit von AFileName in UTC; 0, wenn die Datei fehlt.</summary>
function WrittenUtc(const AFileName: string): TDateTime;
begin
  Result := 0;
  if FileExists(AFileName) then
  begin
    Result := TFile.GetLastWriteTimeUtc(AFileName);
  end;
end;

function ToolGetLastTests(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mFolder, mReason: string;
  mRuns: TArray<TTestRunFile>;
  mRequest: TMcpLastTestsRequest;
  mIndex: Integer;
begin
  mRequest := TMcpLastTestsRequest.FromArguments(AArguments);
  mFolder := TTestRunFiles.Folder(TIndexCacheDirectory.DefaultRoot);
  mRuns := LoadTestRuns(mFolder);
  if Length(mRuns) = 0 then
  begin
    Exit(TMcpLastTests.NoRuns(mFolder));
  end;
  mIndex := TMcpLastTests.Pick(mRuns, AContext.Root, mRequest.Project, mReason);
  if mIndex < 0 then
  begin
    raise EMcpToolError.Create(mReason);
  end;
  Result := TMcpLastTests.Report(mRuns[mIndex], TMcpLastTests.StaleUnits(mRuns[mIndex], WrittenUtc,
    EditorDirtyFiles), mRequest);
end;

procedure AddGetLastTests(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_last_tests', cTexts[TMcpTestRunText.GetLastTestsTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"project":{"type":"string","description":%s},' +
      '"only":{"type":"string","enum":["failed","flaky","slow","leaks","stale","all"],"default":"failed",' +
      '"description":%s},' +
      '"max":{"type":"integer","minimum":1,"maximum":500,"default":20,"description":%s},' +
      '"format":{"type":"string","enum":["text","json"],"default":"text","description":%s}}}',
      [cTexts[TMcpTestRunText.GetLastTestsProject].Text,
      cTexts[TMcpTestRunText.GetLastTestsOnly].Text,
      cTexts[TMcpTestRunText.GetLastTestsMax].Text,
      cTexts[TMcpTestRunText.GetLastTestsFormat].Text]),
    ContextTool(AContext, ToolGetLastTests));
end;

initialization
  TAtlasTextTables.Add('Core.Mcp.TestRunTools', cTexts);

end.
