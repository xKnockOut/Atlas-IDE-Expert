unit Shell.Mcp.BuildTestTools;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), Werkzeuge für Builds in der IDE und DUnitX-Testläufe
// (get_last_build, build_project, run_tests).

interface

uses
  Shell.Mcp.Context;

/// <summary>Meldet get_last_build, build_project und run_tests an.</summary>
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
  Atlas.Common.Compiler.Contract,
  Atlas.Text.Lines,
  Atlas.Text.DUnitX,
  Atlas.Text.TestResults,
  Atlas.Common.Lsp.IdeBuild,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Atlas.Common.Projects.Contract,
  Shell.Platform,
  Shell.Mcp.Ide,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TMcpBuildTestText = (GetLastBuildTool, GetLastBuildProject, BuildProjectTool, BuildProjectProject, BuildProjectMode,
    BuildProjectConfiguration, BuildProjectPlatform, RunTestsTool, RunTestsProject, RunTestsTests, RunTestsBuild,
    RunTestsConfiguration, RunTestsPlatform, RunTestsTimeoutSeconds, ProjectUnreadable, BuildFailed, TimedOut,
    ExeMissing);
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
    En: 'Test EXE missing: %s. Build with "build": true or build the project in the IDE for %s/%s.'));

function ReadSourceLines(const AFileName: string; out ALines: TArray<string>): Boolean;
var
  Text: string;
begin
  Result := ReadSourceText(AFileName, Text);
  if Result then
  begin
    ALines := TTextLines.SplitLines(Text);
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
  KeptLines = 40;
var
  Process: ICompilerProcess;
  Request: TCompilerRequest;
  Finished: TEvent;
  Watcher: TThread;
  Output: TArray<string>;
  TimedOut: Boolean;
begin
  Process := TProcessRunner.Create;
  Request := Default(TCompilerRequest);
  Request.Executable := ATarget.Executable;
  Request.Arguments := AArguments;
  Request.WorkingDir := ATarget.WorkingDir;
  Output := nil;
  TimedOut := False;
  Finished := TEvent.Create(nil, True, False, '');
  try
    Watcher := TThread.CreateAnonymousThread(
      procedure
      begin
        if Finished.WaitFor(Cardinal(ATimeoutSeconds) * 1000) = wrTimeout then
        begin
          TimedOut := True;
          Process.Cancel;
        end;
      end);
    Watcher.FreeOnTerminate := False;
    Watcher.Start;
    try
      try
        Result := Process.Run(Request,
          procedure(const ALine: string)
          begin
            Output := Output + [ALine];
            if Length(Output) > KeptLines then
            begin
              Delete(Output, 0, Length(Output) - KeptLines);
            end;
          end);
      except
        on ECompilerCancelled do
          Result := -1;
      end;
    finally
      Finished.SetEvent;
      Watcher.WaitFor;
      Watcher.Free;
    end;
  finally
    Finished.Free;
  end;
  AOutput := Output;
  ATimedOut := TimedOut;
end;

function ToolGetLastBuild(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  FileName: string;
  Build: TIdeBuild;
begin
  FileName := TIndexCacheDirectory.BuildFileFor(TIndexCacheDirectory.DefaultRoot, AContext.Root);
  if not FileExists(FileName) or
    not TMcpBuildTools.FromFileText(TFile.ReadAllText(FileName, TEncoding.UTF8), Build) then
  begin
    Exit(TMcpBuildTools.NoBuild(AContext.Root));
  end;
  Result := TMcpBuildTools.Report(Build, AContext.Root, TMcpServer.OptionalString(AArguments, 'project'));
end;

procedure AddGetLastBuild(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_last_build', cTexts[TMcpBuildTestText.GetLastBuildTool].Text,
    TMcpServer.StringSchema(['project'],
      [cTexts[TMcpBuildTestText.GetLastBuildProject].Text], 0),
    ContextTool(AContext, ToolGetLastBuild));
end;

function ToolBuildProject(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := TMcpBuildTools.Report(BuildInIde(AContext.Root, TMcpServer.OptionalString(AArguments, 'project'),
    TMcpServer.OptionalString(AArguments, 'mode'), TMcpServer.OptionalString(AArguments, 'configuration'),
    TMcpServer.OptionalString(AArguments, 'platform')), AContext.Root, '');
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
  mWanted := TMcpServer.OptionalString(AArguments, 'project');
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
  mConfiguration := TMcpServer.OptionalString(AArguments, 'configuration');
  // Erst die Vorgaben der Datei lesen, dann für die Wahl der Plattform auswerten.
  LoadTestProject(AProject, mConfiguration, '', AInfo);
  if not TMcpTestTools.ChoosePlatform(TMcpServer.OptionalString(AArguments, 'platform'), AInfo.Platform,
    AInfo.Platforms, Result.Platform, mReason) then
  begin
    raise EMcpToolError.Create(mReason);
  end;
  LoadTestProject(AProject, mConfiguration, Result.Platform, AInfo);
  Result.Configuration := AInfo.Config;
  Result.Executable := TMcpTestTools.ExecutableOf(AInfo);
  Result.WorkingDir := ExtractFileDir(Result.Executable);
end;

/// <summary>Zeitlimit aus timeoutSeconds, begrenzt auf TMcpTestTools.MaxTimeoutSeconds.</summary>
function TestTimeoutOf(const AArguments: TJSONObject): Integer;
begin
  if (AArguments = nil) or not AArguments.TryGetValue<Integer>('timeoutSeconds', Result) or (Result <= 0) then
  begin
    Result := TMcpTestTools.DefaultTimeoutSeconds;
  end;
  if Result > TMcpTestTools.MaxTimeoutSeconds then
  begin
    Result := TMcpTestTools.MaxTimeoutSeconds;
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

procedure RegisterBuildTestTools(const AContext: TMcpToolContext);
begin
  AddGetLastBuild(AContext);
  AddBuildProject(AContext);
  AddRunTests(AContext);
end;

initialization
  TAtlasTextTables.Add('Shell.Mcp.BuildTestTools', cTexts);

end.
