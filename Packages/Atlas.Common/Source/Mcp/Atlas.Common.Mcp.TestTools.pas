unit Atlas.Common.Mcp.TestTools;

// DUnitX-Tests für Claude Code ausführen (#69, MCP-Werkzeug run_tests), ohne
// Windows: Wahl des Testprojekts, der Plattform und der Test-EXE, Befehlszeile
// und Bericht mit Datei und Zeile jedes fehlgeschlagenen Tests. Den Prozess
// startet die Shell (Shell.Mcp); bauen lässt sie vorher auf Wunsch über die
// IDE wie build_project (#261).
// - Testprojekt: ein .dproj, dessen Hauptdatei DUnitX.TestFramework verwendet
//   (Atlas.Text.DUnitX). Ohne Angabe das einzige solche Projekt unter dem
//   Arbeitsordner.
// - Plattform (#14): die gewünschte, sonst die Vorgabe der Datei, wenn sie
//   aktiviert ist, sonst die erste aktivierte Plattform. Atlas nimmt nicht
//   Win32 an: Ein Projekt nur für Win64 läuft als Win64.
// - Test-EXE: DCC_ExeOutput (relativ zum Projektordner, $(Platform) und
//   $(Config) eingesetzt) und der Name der Hauptdatei mit .exe. Läuft ohne
//   Compiler; fehlt sie, nennt der Bericht den Weg (build: true oder in der IDE
//   bauen).
// - Ergebnis: XML-Bericht des DUnitX-Loggers (--xmlfile, Atlas.Text.TestResults);
//   fehlgeschlagene Tests mit erwartetem und tatsächlichem Wert, Datei und
//   Zeile des Methodenkopfs (1-basiert).

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Projects.Contract,
  Atlas.Text.TestResults;

type
  /// <summary>Liest eine Quelldatei zeilenweise; False, wenn sie fehlt.</summary>
  TMcpReadLines = reference to function(const AFileName: string; out ALines: TArray<string>): Boolean;

  /// <summary>Was ausgeführt wird.</summary>
  TMcpTestTarget = record
    Project: string;
    Configuration: string;
    Platform: string;
    Executable: string;
    /// <summary>Arbeitsordner des Prozesses: Ordner der EXE.</summary>
    WorkingDir: string;
  end;

  /// <summary>Was das Testprogramm selbst geliefert hat: Exit-Code und letzte Zeilen der Ausgabe.</summary>
  TMcpTestProcess = record
    ExitCode: Integer;
    Output: TArray<string>;
    class function Make(AExitCode: Integer; const AOutput: TArray<string>): TMcpTestProcess; static;
  end;

  TMcpTestTools = class
  public const
    /// <summary>Vorgabe des Zeitlimits eines Laufs in Sekunden.</summary>
    DefaultTimeoutSeconds = 600;
    MaxTimeoutSeconds = 3600;
    /// <summary>Höchstens so viele fehlgeschlagene Tests im Bericht; der Rest wird gezählt.</summary>
    MaxFailures = 100;
  public
    /// <summary>Plattform des Laufs. False mit Grund, wenn ARequested nicht aktiviert ist. AEnabled leer = alte
    /// Projektdatei ohne Angabe: dann gilt ARequested bzw. AFileDefault.</summary>
    class function ChoosePlatform(const ARequested, AFileDefault: string; const AEnabled: TArray<string>;
      out APlatform, AReason: string): Boolean; static;
    /// <summary>Testprojekt aus ACandidates (.dproj); AIsTestProject prüft die Hauptdatei. AWanted ('' = keins)
    /// passt auf vollen Pfad, Dateinamen oder Namen ohne Endung. False mit Grund.</summary>
    class function PickProject(const ACandidates: TArray<string>; const AWanted: string;
      const AIsTestProject: TFunc<string, Boolean>; out AProject, AReason: string): Boolean; static;
    /// <summary>Wert einer Eigenschaft des ausgewerteten Projekts; '' ohne.</summary>
    class function PropertyOf(const AInfo: TProjectInfo; const AName: string): string; static;
    /// <summary>Test-EXE des ausgewerteten Projekts (Konfiguration und Plattform aus AInfo).</summary>
    class function ExecutableOf(const AInfo: TProjectInfo): string; static;
    /// <summary>Namen für --run aus dem Argument "tests" (Liste oder Text mit Kommas); nil = alle.</summary>
    class function TestsOf(const AArguments: TJSONObject): TArray<string>; static;
    /// <summary>Datei und Zeile (1-basiert) eines Tests: Unit aus AUnits (sonst Ordner AProjectDir), dort der
    /// Methodenkopf im implementation-Teil, sonst die Deklaration, sonst die Fixture. False ohne Fundstelle.
    /// </summary>
    class function Locate(const ACase: TTestCaseResult; const AUnits: TArray<TProjectUnit>;
      const AProjectDir: string; const AReadLines: TMcpReadLines; out AFileName: string; out ALine: Integer): Boolean;
      static;
    /// <summary>Ergebnis von run_tests als JSON-Text. AProcess: Exit-Code des Testprogramms und dessen letzte
    /// Zeilen (nur, wenn kein Bericht kam).</summary>
    class function Report(const ATarget: TMcpTestTarget; const ATests: TArray<string>; const ARun: TTestRunResult;
      const AProcess: TMcpTestProcess; const AUnits: TArray<TProjectUnit>; const AReadLines: TMcpReadLines): string;
      static;
  end;

implementation

uses
  System.Generics.Collections,
  System.StrUtils,
  System.Math,
  Atlas.Common.Projects.Paths,
  Atlas.Text.DUnitX;

function SameProject(const AFileName, AWanted: string): Boolean;
begin
  Result := SameText(AFileName, AWanted) or SameText(TProjectPaths.BaseName(AFileName) +
    TProjectPaths.Extension(AFileName), AWanted) or SameText(TProjectPaths.BaseName(AFileName), AWanted) or
    SameText(TProjectPaths.BaseName(AFileName), TProjectPaths.BaseName(AWanted));
end;

{ TMcpTestTools }

class function TMcpTestTools.ChoosePlatform(const ARequested, AFileDefault: string; const AEnabled: TArray<string>;
  out APlatform, AReason: string): Boolean;
begin
  APlatform := '';
  AReason := '';
  if ARequested <> '' then
  begin
    if (Length(AEnabled) > 0) and (IndexText(ARequested, AEnabled) < 0) then
    begin
      AReason := Format('Plattform "%s" ist im Testprojekt nicht aktiviert (vorhanden: %s).',
        [ARequested, string.Join(', ', AEnabled)]);
      Exit(False);
    end;
    APlatform := ARequested;
    Exit(True);
  end;
  if (AFileDefault <> '') and ((Length(AEnabled) = 0) or (IndexText(AFileDefault, AEnabled) >= 0)) then
  begin
    APlatform := AFileDefault;
  end
  else if Length(AEnabled) > 0 then
  begin
    APlatform := AEnabled[0];
  end
  else
  begin
    APlatform := 'Win32';
  end;
  Result := True;
end;

/// <summary>Alle Kandidaten, die AIsTestProject als Testprojekt erkennt.</summary>
function TestProjects(const ACandidates: TArray<string>; const AIsTestProject: TFunc<string, Boolean>):
  TArray<string>;
var
  mCandidate: string;
begin
  Result := nil;
  for mCandidate in ACandidates do
  begin
    if AIsTestProject(mCandidate) then
    begin
      Result := Result + [mCandidate];
    end;
  end;
end;

/// <summary>Dateinamen der Projekte, mit Komma getrennt.</summary>
function ProjectNames(const AProjects: TArray<string>): string;
var
  mProject: string;
begin
  Result := '';
  for mProject in AProjects do
  begin
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + TProjectPaths.BaseName(mProject) + TProjectPaths.Extension(mProject);
  end;
end;

/// <summary>Kandidat, der zu AWanted passt; False mit Grund.</summary>
function PickWanted(const ACandidates: TArray<string>; const AWanted: string; out AProject, AReason: string):
  Boolean;
var
  mCandidate: string;
begin
  AProject := '';
  AReason := '';
  for mCandidate in ACandidates do
  begin
    if SameProject(mCandidate, AWanted) then
    begin
      AProject := mCandidate;
      Exit(True);
    end;
  end;
  AReason := Format('Projekt "%s" nicht gefunden.', [AWanted]);
  Result := False;
end;

class function TMcpTestTools.PickProject(const ACandidates: TArray<string>; const AWanted: string;
  const AIsTestProject: TFunc<string, Boolean>; out AProject, AReason: string): Boolean;
var
  mFound: TArray<string>;
begin
  if AWanted <> '' then
  begin
    Exit(PickWanted(ACandidates, AWanted, AProject, AReason));
  end;
  AProject := '';
  AReason := '';
  mFound := TestProjects(ACandidates, AIsTestProject);
  Result := Length(mFound) = 1;
  if Result then
  begin
    AProject := mFound[0];
  end
  else if Length(mFound) = 0 then
  begin
    AReason := 'Kein DUnitX-Testprojekt gefunden (Hauptdatei mit uses DUnitX.TestFramework); "project" angeben.';
  end
  else
  begin
    AReason := Format('Mehrere Testprojekte (%s); "project" angeben.', [ProjectNames(mFound)]);
  end;
end;

class function TMcpTestTools.PropertyOf(const AInfo: TProjectInfo; const AName: string): string;
var
  Index: Integer;
begin
  // Die letzte Zuweisung gilt (wie in MSBuild).
  for Index := High(AInfo.Properties) downto 0 do
  begin
    if SameText(AInfo.Properties[Index].Key, AName) then
    begin
      Exit(AInfo.Properties[Index].Value);
    end;
  end;
  Result := '';
end;

class function TMcpTestTools.ExecutableOf(const AInfo: TProjectInfo): string;
var
  Directory, Output, Name: string;
begin
  Directory := TProjectPaths.DirectoryOf(AInfo.FileName);
  Output := PropertyOf(AInfo, 'DCC_ExeOutput');
  if Output <> '' then
  begin
    Directory := TProjectPaths.Combine(Directory, Output);
  end;
  if AInfo.MainSource <> '' then
  begin
    Name := TProjectPaths.BaseName(AInfo.MainSource);
  end
  else
  begin
    Name := TProjectPaths.BaseName(AInfo.FileName);
  end;
  Result := TProjectPaths.Combine(Directory, Name + '.exe');
end;

class function TMcpTestTools.TestsOf(const AArguments: TJSONObject): TArray<string>;
var
  Value, Item: TJSONValue;
  Part: string;
begin
  Result := nil;
  if AArguments = nil then
  begin
    Exit;
  end;
  Value := AArguments.GetValue('tests');
  if Value is TJSONArray then
  begin
    for Item in TJSONArray(Value) do
    begin
      if Trim(Item.Value) <> '' then
      begin
        Result := Result + [Trim(Item.Value)];
      end;
    end;
  end
  else if (Value <> nil) and not (Value is TJSONNull) then
  begin
    for Part in Value.Value.Split([',']) do
    begin
      if Trim(Part) <> '' then
      begin
        Result := Result + [Trim(Part)];
      end;
    end;
  end;
end;

class function TMcpTestTools.Locate(const ACase: TTestCaseResult; const AUnits: TArray<TProjectUnit>;
  const AProjectDir: string; const AReadLines: TMcpReadLines; out AFileName: string; out ALine: Integer): Boolean;
var
  ProjectUnit: TProjectUnit;
  Lines: TArray<string>;
begin
  AFileName := '';
  ALine := 0;
  if ACase.UnitName = '' then
  begin
    Exit(False);
  end;
  for ProjectUnit in AUnits do
  begin
    if SameText(ProjectUnit.Name, ACase.UnitName) then
    begin
      AFileName := ProjectUnit.FileName;
      Break;
    end;
  end;
  if (AFileName = '') and (AProjectDir <> '') then
  begin
    AFileName := TProjectPaths.Combine(AProjectDir, ACase.UnitName + '.pas');
  end;
  if (AFileName = '') or not AReadLines(AFileName, Lines) then
  begin
    AFileName := '';
    Exit(False);
  end;
  // Ohne Fundstelle in der Datei: nur die Datei (ALine = 0).
  ALine := TDUnitXSource.Scan(Lines).LineOf(ACase.Fixture, ACase.Method) + 1;
  Result := True;
end;

function OutcomeText(AOutcome: TTestOutcome): string;
const
  Texts: array[TTestOutcome] of string = ('passed', 'failed', 'error', 'skipped');
begin
  Result := Texts[AOutcome];
end;

class function TMcpTestProcess.Make(AExitCode: Integer; const AOutput: TArray<string>): TMcpTestProcess;
begin
  Result.ExitCode := AExitCode;
  Result.Output := AOutput;
end;

function StatusOf(const ARun: TTestRunResult): string;
begin
  if not ARun.Valid then
  begin
    Result := 'noReport';
  end
  else if ARun.Total = 0 then
  begin
    Result := 'noTests';
  end
  else if ARun.AllPassed then
  begin
    Result := 'passed';
  end
  else
  begin
    Result := 'failed';
  end;
end;

function StringsJson(const AItems: TArray<string>): TJSONArray;
var
  mItem: string;
begin
  Result := TJSONArray.Create;
  for mItem in AItems do
  begin
    Result.Add(mItem);
  end;
end;

/// <summary>Kopf des Berichts: Ergebnis, Ziel, Filter und Exit-Code.</summary>
procedure AddHead(ARoot: TJSONObject; const ATarget: TMcpTestTarget; const ATests: TArray<string>;
  const ARun: TTestRunResult; AExitCode: Integer);
begin
  ARoot.AddPair('result', StatusOf(ARun));
  ARoot.AddPair('project', ATarget.Project);
  ARoot.AddPair('configuration', ATarget.Configuration);
  ARoot.AddPair('platform', ATarget.Platform);
  ARoot.AddPair('executable', ATarget.Executable);
  if Length(ATests) > 0 then
  begin
    ARoot.AddPair('tests', StringsJson(ATests));
  end;
  ARoot.AddPair('exitCode', TJSONNumber.Create(AExitCode));
end;

procedure AddCounts(ARoot: TJSONObject; const ARun: TTestRunResult);
begin
  ARoot.AddPair('total', TJSONNumber.Create(ARun.Total));
  ARoot.AddPair('passed', TJSONNumber.Create(ARun.Count(TTestOutcome.Passed)));
  ARoot.AddPair('failed', TJSONNumber.Create(ARun.Count(TTestOutcome.Failed)));
  ARoot.AddPair('errors', TJSONNumber.Create(ARun.Count(TTestOutcome.Error)));
  ARoot.AddPair('skipped', TJSONNumber.Create(ARun.Count(TTestOutcome.Skipped)));
  ARoot.AddPair('durationMs', TJSONNumber.Create(ARun.DurationMs));
end;

/// <summary>Ein fehlgeschlagener Test mit Werten und, wenn gefunden, Datei und Zeile.</summary>
function FailureJson(const AFailure: TTestCaseResult; const ATarget: TMcpTestTarget;
  const AUnits: TArray<TProjectUnit>; const AReadLines: TMcpReadLines): TJSONObject;
var
  mFileName: string;
  mLine: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('test', AFailure.FullName);
  Result.AddPair('outcome', OutcomeText(AFailure.Outcome));
  Result.AddPair('message', AFailure.Message);
  if AFailure.HasValues then
  begin
    Result.AddPair('expected', AFailure.Expected);
    Result.AddPair('actual', AFailure.Actual);
  end;
  if TMcpTestTools.Locate(AFailure, AUnits, TProjectPaths.DirectoryOf(ATarget.Project), AReadLines, mFileName,
    mLine) then
  begin
    Result.AddPair('file', mFileName);
    if mLine > 0 then
    begin
      Result.AddPair('line', TJSONNumber.Create(mLine));
    end;
  end;
end;

class function TMcpTestTools.Report(const ATarget: TMcpTestTarget; const ATests: TArray<string>;
  const ARun: TTestRunResult; const AProcess: TMcpTestProcess; const AUnits: TArray<TProjectUnit>;
  const AReadLines: TMcpReadLines): string;
var
  mRoot: TJSONObject;
  mItems: TJSONArray;
  mFailures: TArray<TTestCaseResult>;
  mIndex: Integer;
begin
  mRoot := TJSONObject.Create;
  try
    AddHead(mRoot, ATarget, ATests, ARun, AProcess.ExitCode);
    if not ARun.Valid then
    begin
      mRoot.AddPair('reason', 'Das Testprogramm hat keinen XML-Bericht geschrieben (' + ARun.Error + '). Es braucht ' +
        'einen DUnitX-XML-Logger: runner.AddLogger(TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile)) ' +
        'wie in der Vorlage von RAD Studio.');
      mRoot.AddPair('output', StringsJson(AProcess.Output));
      Exit(mRoot.Format(2));
    end;
    AddCounts(mRoot, ARun);
    mItems := TJSONArray.Create;
    mRoot.AddPair('failures', mItems);
    mFailures := ARun.Failures;
    for mIndex := 0 to Min(Length(mFailures), MaxFailures) - 1 do
    begin
      mItems.AddElement(FailureJson(mFailures[mIndex], ATarget, AUnits, AReadLines));
    end;
    if Length(mFailures) > MaxFailures then
    begin
      mRoot.AddPair('omittedFailures', TJSONNumber.Create(Length(mFailures) - MaxFailures));
    end;
    Result := mRoot.Format(2);
  finally
    mRoot.Free;
  end;
end;

end.
