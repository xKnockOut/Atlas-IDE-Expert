unit Shell.Mcp.BuildTestTools;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), Werkzeuge für Builds in der IDE und DUnitX-Testläufe
// (get_last_build, build_project, run_tests), das Profil aus „Mit Profil ausführen“ (get_profile, #2057) und die
// Mutanten einer Unit (get_mutants, #1460) und Grenzfälle einer Routine als Testfälle (suggest_test_cases, #2173).

interface

uses
  Shell.Mcp.Context;

/// <summary>Meldet get_last_build, build_project, run_tests, get_profile, get_mutants und suggest_test_cases an.
/// </summary>
procedure RegisterBuildTestTools(const AContext: TMcpToolContext);

implementation

uses
{$IFDEF MSWINDOWS}
  // Für das inline-DeleteFile der RTL (H2443); die Plattformadapter kommen aus Shell.Platform.
  Winapi.Windows,
{$ENDIF}
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.IOUtils,
  System.JSON,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.BuildTools,
  Atlas.Common.Mcp.TestTools,
  Atlas.Common.Mcp.ProfileTools,
  Atlas.Common.Profiling.Profile,
  Atlas.Common.Compiler.Contract,
  Atlas.Text.Lines,
  Atlas.Text.DUnitX,
  Atlas.Text.TestResults,
  Atlas.Common.Lsp.IdeBuild,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Mutation.Contract,
  Atlas.Common.Mutation.Report,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Lsp.BoundaryCases,
  Shell.Platform,
  Shell.Texts,
  Shell.Mcp.Ide,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TMcpBuildTestText = (GetLastBuildTool, GetLastBuildProject, BuildProjectTool, BuildProjectProject, BuildProjectMode,
    BuildProjectConfiguration, BuildProjectPlatform, RunTestsTool, RunTestsProject, RunTestsTests, RunTestsBuild,
    RunTestsConfiguration, RunTestsPlatform, RunTestsTimeoutSeconds, ProjectUnreadable, BuildFailed, TimedOut,
    ExeMissing, GetProfileTool, GetProfileTop, GetProfileUnit, GetProfileRun, GetProfileCompareWith,
    GetProfileFormat, GetProfileOwnCode,
    GetMutantsTool, GetMutantsFile, GetMutantsRoutine, GetMutantsOperators, GetMutantsFirstLine,
    GetMutantsLastLine, GetMutantsFormat, UnknownOperators, SourceUnreadable,
    SuggestTool, SuggestFile, SuggestRoutine, SuggestLine, SuggestMax, SuggestFormat, SuggestNoRoutine);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TMcpBuildTestText] of TAtlasText = (
    (De: 'Ergebnis des letzten Builds, den der Benutzer in der IDE gestartet hat: Erfolg, Art, Zeitpunkt, Dauer, ' +
    'Projekt, Konfiguration, Plattform und alle Compilermeldungen mit Datei, Zeile, Spalte, Code und Text.';
    En: 'Result of the last build the user started in the IDE: success, kind, time, duration, project, ' +
    'configuration, platform and all compiler messages with file, line, column, code and text.'),
    (De: 'Projekt (Name oder .dproj) zum Filtern; leer = letzter Build';
    En: 'Project (name or .dproj) to filter by; empty = last build'),
    (De: 'Baut ein Projekt in der laufenden RAD-Studio-IDE über das Atlas-Plugin (#261), auch ohne ' +
    'Kommandozeilen-Compiler (Starter Edition), und liefert Ergebnis und alle Compilermeldungen wie ' +
    'get_last_build. Das Projekt muss in der IDE offen sein; ohne project baut es das aktive Projekt, wenn ' +
    'es unter dem Arbeitsordner liegt. Wartet bis zum Ende des Builds.';
    En: 'Builds a project in the running RAD Studio IDE through the Atlas plugin (#261), also without a ' +
    'command-line compiler (Starter Edition), and returns the result and all compiler messages like ' +
    'get_last_build. The project must be open in the IDE; without project it builds the active project if it ' +
    'lies below the working folder. Waits until the build has finished.'),
    (De: 'Projekt (.dproj mit Pfad, Dateiname oder Name); leer = aktives Projekt der IDE';
    En: 'Project (.dproj with path, file name or name); empty = active project of the IDE'),
    (De: 'make: geänderte Units, build: alles neu, check: nur Syntax';
    En: 'make: changed units, build: everything, check: syntax only'),
    (De: 'z. B. Debug oder Release; leer = aktive Konfiguration';
    En: 'e.g. Debug or Release; empty = active configuration'),
    (De: 'z. B. Win32 oder Win64; leer = aktive Plattform'; En: 'e.g. Win32 or Win64; empty = active platform'),
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
    (De: 'Profil eines Laufs mit „Mit Profil ausführen“ in der IDE (#2057): die teuersten Methoden nach ' +
    'Eigenanteil (Proben, in denen sie gerade rechnete) und Gesamtanteil (irgendwo im Aufrufstapel) mit Datei ' +
    'und heißester Zeile; RTL und VCL zusammengefasst, solange ownCode an ist. Mit compareWith der Vergleich ' +
    'zweier Läufe. Gespeichert bleiben die letzten fünf Läufe. Lesend.';
    En: 'Profile of a run with "Run with profile" in the IDE (#2057): the most expensive methods by self share ' +
    '(samples in which they were computing) and total share (anywhere in the call stack) with file and hottest ' +
    'line; RTL and VCL summarized while ownCode is on. With compareWith the comparison of two runs. The last ' +
    'five runs are kept. Read-only.'),
    (De: 'Anzahl Methoden; Vorgabe 10, höchstens 100'; En: 'Number of methods; default 10, at most 100'),
    (De: 'Nur Methoden dieser Unit bzw. Datei (Teil des Namens)'; En: 'Only methods of this unit or file (part ' +
    'of the name)'),
    (De: 'Lauf: leer = neuester, 2 = zweitneuester, oder Dateiname'; En: 'Run: empty = newest, 2 = second newest, ' +
    'or file name'),
    (De: 'Zweiter Lauf zum Vergleich (wie run)'; En: 'Second run to compare with (like run)'),
    (De: 'text (Vorgabe) oder json'; En: 'text (default) or json'),
    (De: 'RTL, VCL und andere Bibliotheken zu ihrem Aufruf aus eigenem Code zusammenfassen; Vorgabe true';
    En: 'Summarize RTL, VCL and other libraries into their call from own code; default true'),
    (De: 'Mutanten einer Unit für Mutationstests (#1460): kleine Fehler, die die DUnitX-Tests bemerken sollten ' +
    '(Vergleich < und <=, = und <>, and und or, not entfernen, + und -, +1 entfernen, True und False, 0 und 1, ' +
    'Anweisung entfernen, Exit(x) durch Exit(Default(Typ))). Erzeugt aus dem Syntaxbaum, nur in aktiven Zweigen, ' +
    'ohne Assert, Protokollaufrufe und Zeilen mit // atlas-ignore: mutation. Baut und testet nicht: Je Mutant ' +
    'die Datei ändern, das Testprojekt bauen (build_project) und die Tests laufen lassen (run_tests); bleiben alle ' +
    'grün, fehlt an der Stelle ein Test. Dieselben Mutanten wie --mutate.';
    En: 'Mutants of a unit for mutation testing (#1460): small faults the DUnitX tests should notice (comparison ' +
    '< and <=, = and <>, and and or, remove not, + and -, remove +1, True and False, 0 and 1, remove statement, ' +
    'Exit(x) by Exit(Default(Type))). Generated from the syntax tree, only in active branches, without Assert, ' +
    'logging calls and lines with // atlas-ignore: mutation. Does not build or test: for each mutant change the ' +
    'file, build the test project (build_project) and run the tests (run_tests); if all stay green, a test is ' +
    'missing at that place. The same mutants as --mutate.'),
    (De: 'Pfad der Unit (relativ zum Projekt oder absolut)';
    En: 'Path of the unit (relative to the project or absolute)'),
    (De: 'Nur diese Routine: "TFoo.Bar" oder "Bar"; leer = alle'; En: 'Only this routine: "TFoo.Bar" or "Bar"; ' +
    'empty = all'),
    (De: 'Nur diese Operatoren: boundary, equality, logical, not, arithmetic, increment, boolean, number, ' +
    'statement, exit; leer = alle';
    En: 'Only these operators: boundary, equality, logical, not, arithmetic, increment, boolean, number, ' +
    'statement, exit; empty = all'),
    (De: 'Nur Stellen ab dieser Zeile (ab 1)'; En: 'Only places from this line on (from 1)'),
    (De: 'Nur Stellen bis zu dieser Zeile'; En: 'Only places up to this line'),
    (De: 'markdown (Vorgabe), json (mit Offsets für eigene Änderungen) oder diff (je Mutant ein Patch)';
    En: 'markdown (default), json (with offsets for own changes) or diff (one patch per mutant)'),
    (De: 'Unbekannte Operatoren: %s'; En: 'Unknown operators: %s'),
    (De: '%s ist nicht lesbar'; En: '%s is not readable'),
    (De: 'Grenzfälle einer Routine als Testfälle (#2173): aus den Bedingungen über ihre Parameter (Vergleich mit ' +
    'einer Konstanten, case-Marken, in [...], SameText/StartsText/Pos, Length, nil, Boolean) je Bedingung Werte ' +
    'knapp davor, darauf und dahinter, mit Grund und Zeile; je Fall weicht ein Parameter ab, die übrigen stehen ' +
    'auf einem neutralen Wert. Werte in der Schreibweise von DUnitX-[TestCase]; nil-Fälle passen in kein ' +
    '[TestCase]. Felder und Funktionsaufrufe liefern nichts. Lesend; erzeugt keinen Test.';
    En: 'Boundary cases of a routine as test cases (#2173): from the conditions on its parameters (comparison ' +
    'with a constant, case labels, in [...], SameText/StartsText/Pos, Length, nil, Boolean) values just before, ' +
    'on and after each condition, with reason and line; in each case one parameter deviates, the others stay ' +
    'on a neutral value. Values in DUnitX [TestCase] notation; nil cases fit no [TestCase]. Fields and ' +
    'function calls yield nothing. Read-only; creates no test.'),
    (De: 'Pfad der Unit (relativ zum Projekt oder absolut)';
    En: 'Path of the unit (relative to the project or absolute)'),
    (De: 'Routine: "TFoo.Bar" oder "Bar"; statt line'; En: 'Routine: "TFoo.Bar" or "Bar"; instead of line'),
    (De: 'Zeile (ab 1) irgendwo in der Routine; statt routine'; En: 'Line (from 1) anywhere in the routine; ' +
    'instead of routine'),
    (De: 'Höchstens so viele Fälle; Vorgabe 20, 1 bis 200'; En: 'At most this many cases; default 20, 1 to 200'),
    (De: 'markdown (Vorgabe) oder json'; En: 'markdown (default) or json'),
    (De: 'Keine Routine mit Rumpf in %s (routine oder line angeben)';
    En: 'No routine with a body in %s (give routine or line)'));

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
function RunTestProcess(const ATarget: TMcpTestTarget; const AArguments: TArray<string>; ATimeoutSeconds: Integer;
  out AOutput: TArray<string>; out ATimedOut: Boolean): Integer;
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
  mProcess := TProcessRunner.Create;
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

function ToolGetLastBuild(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mFileName: string;
  mBuild: TIdeBuild;
begin
  mFileName := TIndexCacheDirectory.BuildFileFor(TIndexCacheDirectory.DefaultRoot, AContext.Root);
  if not FileExists(mFileName) or
    not TMcpBuildTools.FromFileText(TFile.ReadAllText(mFileName, TEncoding.UTF8), mBuild) then
  begin
    Exit(TMcpBuildTools.NoBuild(AContext.Root));
  end;
  Result := TMcpBuildTools.Report(mBuild, AContext.Root, TMcpArgs.OptionalString(AArguments, 'project'));
end;

procedure AddGetLastBuild(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_last_build', cTexts[TMcpBuildTestText.GetLastBuildTool].Text,
    TMcpArgs.StringSchema(['project'],
      [cTexts[TMcpBuildTestText.GetLastBuildProject].Text], 0),
    ContextTool(AContext, ToolGetLastBuild));
end;

function ToolBuildProject(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := TMcpBuildTools.Report(BuildInIde(AContext.Root, TMcpArgs.OptionalString(AArguments, 'project'),
    TMcpArgs.OptionalString(AArguments, 'mode'), TMcpArgs.OptionalString(AArguments, 'configuration'),
    TMcpArgs.OptionalString(AArguments, 'platform')), AContext.Root, '');
end;

procedure AddBuildProject(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('build_project', cTexts[TMcpBuildTestText.BuildProjectTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"project":{"type":"string","description":%s},' +
      '"mode":{"type":"string","enum":["make","build","check"],"default":"make","description":%s},' +
      '"configuration":{"type":"string","description":%s},' +
      '"platform":{"type":"string","description":%s}}}',
      [cTexts[TMcpBuildTestText.BuildProjectProject].Text,
      cTexts[TMcpBuildTestText.BuildProjectMode].Text,
      cTexts[TMcpBuildTestText.BuildProjectConfiguration].Text,
      cTexts[TMcpBuildTestText.BuildProjectPlatform].Text]),
    ContextTool(AContext, ToolBuildProject), TMcpToolKind.Process);
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
    raise EMcpToolError.Create(cTexts[TMcpBuildTestText.ProjectUnreadable].Fmt([AProject]));
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
    mBuild := BuildInIde(ARoot, ATarget.Project, 'make', ATarget.Configuration, ATarget.Platform);
    Result := not mBuild.Success;
    if Result then
    begin
      AReport := cTexts[TMcpBuildTestText.BuildFailed].Text + sLineBreak +
        TMcpBuildTools.Report(mBuild, ARoot, '');
    end;
  end;
end;

/// <summary>Startet die Test-EXE mit dem XML-Logger von DUnitX und liefert den Bericht.</summary>
function RunTestExe(const ATarget: TMcpTestTarget; const ATests: TArray<string>; ATimeout: Integer;
  const AInfo: TProjectInfo): string;
var
  mResultFile, mXml: string;
  mOutput: TArray<string>;
  mTimedOut: Boolean;
  mCode: Integer;
begin
  mResultFile := TPath.Combine(TPath.GetTempPath, Format('atlas-tests-%s.xml',
    [TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '')]));
  try
    mCode := RunTestProcess(ATarget, TDUnitXCommandLine.Arguments(mResultFile, ATests), ATimeout, mOutput, mTimedOut);
    if mTimedOut then
    begin
      raise EMcpToolError.Create(cTexts[TMcpBuildTestText.TimedOut].Fmt([ATimeout]));
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
    raise EMcpToolError.Create(cTexts[TMcpBuildTestText.ExeMissing].Fmt([mTarget.Executable, mTarget.Configuration,
      mTarget.Platform]));
  end;
  Result := RunTestExe(mTarget, mTests, mTimeout, mInfo);
end;

procedure AddRunTests(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('run_tests', cTexts[TMcpBuildTestText.RunTestsTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"project":{"type":"string","description":%s},' +
      '"tests":{"type":"array","items":{"type":"string"},' +
      '"description":%s},' +
      '"build":{"type":"boolean","default":false,"description":%s},' +
      '"configuration":{"type":"string","description":%s},' +
      '"platform":{"type":"string","description":%s},' +
      '"timeoutSeconds":{"type":"integer","default":600,"description":%s}}}',
      [cTexts[TMcpBuildTestText.RunTestsProject].Text,
      cTexts[TMcpBuildTestText.RunTestsTests].Text,
      cTexts[TMcpBuildTestText.RunTestsBuild].Text,
      cTexts[TMcpBuildTestText.RunTestsConfiguration].Text,
      cTexts[TMcpBuildTestText.RunTestsPlatform].Text,
      cTexts[TMcpBuildTestText.RunTestsTimeoutSeconds].Text]),
    ContextTool(AContext, ToolRunTests), TMcpToolKind.Process);
end;

/// <summary>Gespeicherte Läufe unter AFolder, neueste zuerst; unlesbare Dateien bleiben weg.</summary>
function LoadProfileRuns(const AFolder: string): TArray<TMcpProfileRun>;
var
  mFile: string;
  mRun: TMcpProfileRun;
begin
  Result := nil;
  if not TDirectory.Exists(AFolder) then
  begin
    Exit;
  end;
  for mFile in TAtlasProfileStore.Newest(TDirectory.GetFiles(AFolder, TAtlasProfileStore.cPrefix + '*.json')) do
  begin
    mRun := Default(TMcpProfileRun);
    mRun.Name := ExtractFileName(mFile);
    if TAtlasProfileJson.TryParse(TFile.ReadAllText(mFile, TEncoding.UTF8), mRun.Profile) then
    begin
      Result := Result + [mRun];
    end;
  end;
end;

function ToolGetProfile(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mFolder: string;
  mRuns: TArray<TMcpProfileRun>;
begin
  mFolder := TAtlasProfileStore.Folder(TIndexCacheDirectory.DefaultRoot);
  mRuns := LoadProfileRuns(mFolder);
  if Length(mRuns) = 0 then
  begin
    Exit(TMcpProfileTools.NoRuns(mFolder));
  end;
  Result := TMcpProfileTools.Report(mRuns, TMcpProfileRequest.FromArguments(AArguments));
end;

procedure AddGetProfile(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_profile', cTexts[TMcpBuildTestText.GetProfileTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"top":{"type":"integer","default":10,"description":%s},' +
      '"unit":{"type":"string","description":%s},' +
      '"run":{"type":"string","description":%s},' +
      '"compareWith":{"type":"string","description":%s},' +
      '"format":{"type":"string","enum":["text","json"],"default":"text","description":%s},' +
      '"ownCode":{"type":"boolean","default":true,"description":%s}}}',
      [cTexts[TMcpBuildTestText.GetProfileTop].Text,
      cTexts[TMcpBuildTestText.GetProfileUnit].Text,
      cTexts[TMcpBuildTestText.GetProfileRun].Text,
      cTexts[TMcpBuildTestText.GetProfileCompareWith].Text,
      cTexts[TMcpBuildTestText.GetProfileFormat].Text,
      cTexts[TMcpBuildTestText.GetProfileOwnCode].Text]),
    ContextTool(AContext, ToolGetProfile));
end;

/// <summary>Kennungen aus "operators": Liste oder Text mit Kommas; nil = alle.</summary>
function OperatorIdsOf(const AArguments: TJSONObject): TArray<string>;
var
  mArray: TJSONArray;
  mIndex: Integer;
begin
  Result := nil;
  if AArguments = nil then
  begin
    Exit;
  end;
  if AArguments.GetValue('operators') is TJSONArray then
  begin
    mArray := TJSONArray(AArguments.GetValue('operators'));
    for mIndex := 0 to mArray.Count - 1 do
    begin
      Result := Result + [mArray.Items[mIndex].Value];
    end;
  end
  else
  begin
    Result := TMcpArgs.OptionalString(AArguments, 'operators').Split([',', ';']);
  end;
end;

/// <summary>Zeile ab 1 aus AName als Zeile ab 0; -1 ohne Angabe.</summary>
function LineOf(const AArguments: TJSONObject; const AName: string): Integer;
var
  mLine: Integer;
begin
  Result := -1;
  if (AArguments <> nil) and AArguments.TryGetValue<Integer>(AName, mLine) and (mLine > 0) then
  begin
    Result := mLine - 1;
  end;
end;

function ToolGetMutants(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mFileName, mText: string;
  mFormat: TMutationOutputFormat;
  mOptions: TMutationOptions;
  mIds, mUnknown: TArray<string>;
begin
  mFileName := AContext.Guard.Resolve(TMcpArgs.RequiredString(AArguments, 'file'));
  if not TMutationReport.TryParseFormat(TMcpArgs.OptionalString(AArguments, 'format'), mFormat) then
  begin
    raise EMcpToolError.Create(TShellTexts.Choice('format', ['markdown', 'json', 'diff']));
  end;
  mOptions := TMutationOptions.Default;
  mOptions.Routine := Trim(TMcpArgs.OptionalString(AArguments, 'routine'));
  mOptions.FirstLine := LineOf(AArguments, 'firstLine');
  mOptions.LastLine := LineOf(AArguments, 'lastLine');
  mIds := OperatorIdsOf(AArguments);
  if Length(mIds) > 0 then
  begin
    mOptions.Operators := TMutation.ParseOperators(mIds, mUnknown);
    if Length(mUnknown) > 0 then
    begin
      raise EMcpToolError.Create(cTexts[TMcpBuildTestText.UnknownOperators].Fmt([string.Join(', ', mUnknown)]));
    end;
  end;
  if not ReadSourceText(mFileName, mText) then
  begin
    raise EMcpToolError.Create(cTexts[TMcpBuildTestText.SourceUnreadable].Fmt([mFileName]));
  end;
  // Aktive Zweige wie beim Prüfen: Symbole des Projekts, zu dem die Datei gehört.
  mOptions.Defines := AContext.CheckSource(mFileName).Defines;
  Result := TMutationReport.Render(ExtractRelativePath(IncludeTrailingPathDelimiter(AContext.Root), mFileName)
    .Replace('\', '/'), mText, mOptions, mFormat);
end;

procedure AddGetMutants(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_mutants', cTexts[TMcpBuildTestText.GetMutantsTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"file":{"type":"string","description":%s},' +
      '"routine":{"type":"string","description":%s},' +
      '"operators":{"type":"array","items":{"type":"string","enum":["boundary","equality","logical","not",' +
      '"arithmetic","increment","boolean","number","statement","exit"]},"description":%s},' +
      '"firstLine":{"type":"integer","minimum":1,"description":%s},' +
      '"lastLine":{"type":"integer","minimum":1,"description":%s},' +
      '"format":{"type":"string","enum":["markdown","json","diff"],"description":%s}},"required":["file"]}',
      [cTexts[TMcpBuildTestText.GetMutantsFile].Text,
      cTexts[TMcpBuildTestText.GetMutantsRoutine].Text,
      cTexts[TMcpBuildTestText.GetMutantsOperators].Text,
      cTexts[TMcpBuildTestText.GetMutantsFirstLine].Text,
      cTexts[TMcpBuildTestText.GetMutantsLastLine].Text,
      cTexts[TMcpBuildTestText.GetMutantsFormat].Text]),
    ContextTool(AContext, ToolGetMutants));
end;

function ToolSuggestTestCases(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mFileName, mText, mFormat: string;
  mRequest: TLspBoundaryRequest;
begin
  mFileName := AContext.Guard.Resolve(TMcpArgs.RequiredString(AArguments, 'file'));
  mFormat := LowerCase(Trim(TMcpArgs.OptionalString(AArguments, 'format')));
  if (mFormat <> '') and (mFormat <> 'markdown') and (mFormat <> 'json') then
  begin
    raise EMcpToolError.Create(TShellTexts.Choice('format', ['markdown', 'json']));
  end;
  if not ReadSourceText(mFileName, mText) then
  begin
    raise EMcpToolError.Create(cTexts[TMcpBuildTestText.SourceUnreadable].Fmt([mFileName]));
  end;
  mRequest := Default(TLspBoundaryRequest);
  if not AArguments.TryGetValue<Integer>('maxCases', mRequest.Max) then
  begin
    mRequest.Max := 0;
  end;
  mRequest.FileName := ExtractRelativePath(IncludeTrailingPathDelimiter(AContext.Root), mFileName)
    .Replace('\', '/');
  mRequest.Line := LineOf(AArguments, 'line');
  mRequest.Routine := TMcpArgs.OptionalString(AArguments, 'routine');
  mRequest.Json := mFormat = 'json';
  if not TLspBoundaryCases.Report(mText, mRequest, Result) then
  begin
    raise EMcpToolError.Create(cTexts[TMcpBuildTestText.SuggestNoRoutine].Fmt([mRequest.FileName]));
  end;
end;

procedure AddSuggestTestCases(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('suggest_test_cases', cTexts[TMcpBuildTestText.SuggestTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"file":{"type":"string","description":%s},' +
      '"routine":{"type":"string","description":%s},' +
      '"line":{"type":"integer","minimum":1,"description":%s},' +
      '"maxCases":{"type":"integer","minimum":1,"maximum":200,"description":%s},' +
      '"format":{"type":"string","enum":["markdown","json"],"description":%s}},"required":["file"]}',
      [cTexts[TMcpBuildTestText.SuggestFile].Text,
      cTexts[TMcpBuildTestText.SuggestRoutine].Text,
      cTexts[TMcpBuildTestText.SuggestLine].Text,
      cTexts[TMcpBuildTestText.SuggestMax].Text,
      cTexts[TMcpBuildTestText.SuggestFormat].Text]),
    ContextTool(AContext, ToolSuggestTestCases));
end;

procedure RegisterBuildTestTools(const AContext: TMcpToolContext);
begin
  AddGetLastBuild(AContext);
  AddBuildProject(AContext);
  AddRunTests(AContext);
  AddGetProfile(AContext);
  AddGetMutants(AContext);
  AddSuggestTestCases(AContext);
end;

initialization
  TAtlasTextTables.Add('Shell.Mcp.BuildTestTools', cTexts);

end.
