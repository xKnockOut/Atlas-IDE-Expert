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
    /// <summary>Ergebnis von run_tests als JSON-Text. AExitCode des Testprogramms; AOutput dessen letzte Zeilen
    /// (nur, wenn kein Bericht kam).</summary>
    class function Report(const ATarget: TMcpTestTarget; const ATests: TArray<string>; const ARun: TTestRunResult;
      AExitCode: Integer; const AOutput: TArray<string>; const AUnits: TArray<TProjectUnit>;
      const AReadLines: TMcpReadLines): string; static;
  end;

implementation

uses
  System.StrUtils,
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
    APlatform := AFileDefault
  else if Length(AEnabled) > 0 then
    APlatform := AEnabled[0]
  else
    APlatform := 'Win32';
  Result := True;
end;

class function TMcpTestTools.PickProject(const ACandidates: TArray<string>; const AWanted: string;
  const AIsTestProject: TFunc<string, Boolean>; out AProject, AReason: string): Boolean;
var
  Candidate: string;
  Found: TArray<string>;
  Names: string;
begin
  AProject := '';
  AReason := '';
  if AWanted <> '' then
  begin
    for Candidate in ACandidates do
      if SameProject(Candidate, AWanted) then
      begin
        AProject := Candidate;
        Exit(True);
      end;
    AReason := Format('Projekt "%s" nicht gefunden.', [AWanted]);
    Exit(False);
  end;
  Found := nil;
  for Candidate in ACandidates do
    if AIsTestProject(Candidate) then
      Found := Found + [Candidate];
  if Length(Found) = 1 then
  begin
    AProject := Found[0];
    Exit(True);
  end;
  if Length(Found) = 0 then
    AReason := 'Kein DUnitX-Testprojekt gefunden (Hauptdatei mit uses DUnitX.TestFramework); "project" angeben.'
  else
  begin
    Names := '';
    for Candidate in Found do
    begin
      if Names <> '' then
        Names := Names + ', ';
      Names := Names + TProjectPaths.BaseName(Candidate) + TProjectPaths.Extension(Candidate);
    end;
    AReason := Format('Mehrere Testprojekte (%s); "project" angeben.', [Names]);
  end;
  Result := False;
end;

class function TMcpTestTools.PropertyOf(const AInfo: TProjectInfo; const AName: string): string;
var
  Index: Integer;
begin
  // Die letzte Zuweisung gilt (wie in MSBuild).
  for Index := High(AInfo.Properties) downto 0 do
    if SameText(AInfo.Properties[Index].Key, AName) then
      Exit(AInfo.Properties[Index].Value);
  Result := '';
end;

class function TMcpTestTools.ExecutableOf(const AInfo: TProjectInfo): string;
var
  Directory, Output, Name: string;
begin
  Directory := TProjectPaths.DirectoryOf(AInfo.FileName);
  Output := PropertyOf(AInfo, 'DCC_ExeOutput');
  if Output <> '' then
    Directory := TProjectPaths.Combine(Directory, Output);
  if AInfo.MainSource <> '' then
    Name := TProjectPaths.BaseName(AInfo.MainSource)
  else
    Name := TProjectPaths.BaseName(AInfo.FileName);
  Result := TProjectPaths.Combine(Directory, Name + '.exe');
end;

class function TMcpTestTools.TestsOf(const AArguments: TJSONObject): TArray<string>;
var
  Value, Item: TJSONValue;
  Part: string;
begin
  Result := nil;
  if AArguments = nil then
    Exit;
  Value := AArguments.GetValue('tests');
  if Value is TJSONArray then
  begin
    for Item in TJSONArray(Value) do
      if Trim(Item.Value) <> '' then
        Result := Result + [Trim(Item.Value)];
  end
  else if (Value <> nil) and not (Value is TJSONNull) then
    for Part in Value.Value.Split([',']) do
      if Trim(Part) <> '' then
        Result := Result + [Trim(Part)];
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
    Exit(False);
  for ProjectUnit in AUnits do
    if SameText(ProjectUnit.Name, ACase.UnitName) then
    begin
      AFileName := ProjectUnit.FileName;
      Break;
    end;
  if (AFileName = '') and (AProjectDir <> '') then
    AFileName := TProjectPaths.Combine(AProjectDir, ACase.UnitName + '.pas');
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

class function TMcpTestTools.Report(const ATarget: TMcpTestTarget; const ATests: TArray<string>;
  const ARun: TTestRunResult; AExitCode: Integer; const AOutput: TArray<string>; const AUnits: TArray<TProjectUnit>;
  const AReadLines: TMcpReadLines): string;
var
  Root, Item: TJSONObject;
  Items, Filter, Output: TJSONArray;
  Failure: TTestCaseResult;
  Failures: TArray<TTestCaseResult>;
  FileName, Line, Status: string;
  LineNumber, Index: Integer;
begin
  Root := TJSONObject.Create;
  try
    if not ARun.Valid then
      Status := 'noReport'
    else if ARun.Total = 0 then
      Status := 'noTests'
    else if ARun.AllPassed then
      Status := 'passed'
    else
      Status := 'failed';
    Root.AddPair('result', Status);
    Root.AddPair('project', ATarget.Project);
    Root.AddPair('configuration', ATarget.Configuration);
    Root.AddPair('platform', ATarget.Platform);
    Root.AddPair('executable', ATarget.Executable);
    if Length(ATests) > 0 then
    begin
      Filter := TJSONArray.Create;
      for Line in ATests do
        Filter.Add(Line);
      Root.AddPair('tests', Filter);
    end;
    Root.AddPair('exitCode', TJSONNumber.Create(AExitCode));
    if not ARun.Valid then
    begin
      Root.AddPair('reason', 'Das Testprogramm hat keinen XML-Bericht geschrieben (' + ARun.Error + '). Es braucht ' +
        'einen DUnitX-XML-Logger: runner.AddLogger(TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile)) ' +
        'wie in der Vorlage von RAD Studio.');
      Output := TJSONArray.Create;
      for Line in AOutput do
        Output.Add(Line);
      Root.AddPair('output', Output);
      Exit(Root.Format(2));
    end;
    Root.AddPair('total', TJSONNumber.Create(ARun.Total));
    Root.AddPair('passed', TJSONNumber.Create(ARun.Count(TTestOutcome.Passed)));
    Root.AddPair('failed', TJSONNumber.Create(ARun.Count(TTestOutcome.Failed)));
    Root.AddPair('errors', TJSONNumber.Create(ARun.Count(TTestOutcome.Error)));
    Root.AddPair('skipped', TJSONNumber.Create(ARun.Count(TTestOutcome.Skipped)));
    Root.AddPair('durationMs', TJSONNumber.Create(ARun.DurationMs));
    Items := TJSONArray.Create;
    Root.AddPair('failures', Items);
    Failures := ARun.Failures;
    for Index := 0 to High(Failures) do
    begin
      if Index = MaxFailures then
      begin
        Root.AddPair('omittedFailures', TJSONNumber.Create(Length(Failures) - MaxFailures));
        Break;
      end;
      Failure := Failures[Index];
      Item := TJSONObject.Create;
      Items.AddElement(Item);
      Item.AddPair('test', Failure.FullName);
      Item.AddPair('outcome', OutcomeText(Failure.Outcome));
      Item.AddPair('message', Failure.Message);
      if Failure.HasValues then
      begin
        Item.AddPair('expected', Failure.Expected);
        Item.AddPair('actual', Failure.Actual);
      end;
      if Locate(Failure, AUnits, TProjectPaths.DirectoryOf(ATarget.Project), AReadLines, FileName, LineNumber) then
      begin
        Item.AddPair('file', FileName);
        if LineNumber > 0 then
          Item.AddPair('line', TJSONNumber.Create(LineNumber));
      end;
    end;
    Result := Root.Format(2);
  finally
    Root.Free;
  end;
end;

end.
