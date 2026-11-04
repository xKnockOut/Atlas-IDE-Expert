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
  Shell.Mcp.Ide;

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
  AContext.Server.AddTool('get_last_build',
    'Ergebnis des letzten Builds, den der Benutzer in der IDE gestartet hat: Erfolg, Art, Zeitpunkt, Dauer, ' +
    'Projekt, Konfiguration, Plattform und alle Compilermeldungen mit Datei, Zeile, Spalte, Code und Text.',
    TMcpServer.StringSchema(['project'], ['Projekt (Name oder .dproj) zum Filtern; leer = letzter Build'], 0),
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
  AContext.Server.AddTool('build_project',
    'Baut ein Projekt in der laufenden RAD-Studio-IDE über das Atlas-Plugin (#261), auch ohne ' +
    'Kommandozeilen-Compiler (Starter Edition), und liefert Ergebnis und alle Compilermeldungen wie ' +
    'get_last_build. Das Projekt muss in der IDE offen sein; ohne project baut es das aktive Projekt, wenn es ' +
    'unter dem Arbeitsordner liegt. Wartet bis zum Ende des Builds.',
    '{"type":"object","properties":{' +
      '"project":{"type":"string","description":"Projekt (.dproj mit Pfad, Dateiname oder Name); ' +
        'leer = aktives Projekt der IDE"},' +
      '"mode":{"type":"string","enum":["make","build","check"],"default":"make",' +
        '"description":"make: geänderte Units, build: alles neu, check: nur Syntax"},' +
      '"configuration":{"type":"string","description":"z. B. Debug oder Release; leer = aktive Konfiguration"},' +
      '"platform":{"type":"string","description":"z. B. Win32 oder Win64; leer = aktive Plattform"}}}',
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
    raise EMcpToolError.Create('Projektdatei nicht lesbar: ' + AProject);
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
      AReport := 'Build fehlgeschlagen; Tests nicht ausgeführt.' + sLineBreak +
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
      raise EMcpToolError.CreateFmt('Testlauf nach %d s abgebrochen (timeoutSeconds).', [ATimeout]);
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
    raise EMcpToolError.CreateFmt('Test-EXE fehlt: %s. Mit "build": true bauen oder das Projekt in der IDE ' +
      'für %s/%s bauen.', [mTarget.Executable, mTarget.Configuration, mTarget.Platform]);
  end;
  Result := RunTestExe(mTarget, mTests, mTimeout, mInfo);
end;

procedure AddRunTests(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('run_tests',
    'Führt die DUnitX-Tests eines Testprojekts aus (#69) und liefert bestandene, fehlgeschlagene und ' +
    'übersprungene Tests; jeder fehlgeschlagene Test mit Meldung, erwartetem und tatsächlichem Wert, Datei und ' +
    'Zeile. Startet die vorhandene Test-EXE ohne Compiler; mit build: true baut es das Projekt vorher in der ' +
    'laufenden IDE wie build_project. Die Plattform kommt aus dem Testprojekt (ein Projekt nur für Win64 läuft ' +
    'als Win64). Das Testprogramm braucht den XML-Logger von DUnitX (Vorlage von RAD Studio).',
    '{"type":"object","properties":{' +
      '"project":{"type":"string","description":"Testprojekt (.dproj mit Pfad, Dateiname oder Name); leer = ' +
        'das einzige DUnitX-Projekt unter dem Arbeitsordner"},' +
      '"tests":{"type":"array","items":{"type":"string"},"description":"Nur diese Tests: Unit.Fixture oder ' +
        'Unit.Fixture.Methode; leer = alle"},' +
      '"build":{"type":"boolean","default":false,"description":"Vorher in der IDE bauen (make)"},' +
      '"configuration":{"type":"string","description":"z. B. Debug; leer = Vorgabe des Projekts"},' +
      '"platform":{"type":"string","description":"z. B. Win64; leer = Vorgabe des Projekts, sonst die erste ' +
        'aktivierte Plattform"},' +
      '"timeoutSeconds":{"type":"integer","default":600,"description":"Zeitlimit des Testlaufs in Sekunden ' +
        '(höchstens 3600)"}}}',
    ContextTool(AContext, ToolRunTests), TMcpToolKind.Process);
end;

procedure RegisterBuildTestTools(const AContext: TMcpToolContext);
begin
  AddGetLastBuild(AContext);
  AddBuildProject(AContext);
  AddRunTests(AContext);
end;

end.
