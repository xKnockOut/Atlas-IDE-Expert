unit Atlas.Core.Tests.Run;

// DUnitX-Tests aus der IDE ausführen (#69), ohne VCL und Open Tools API:
// - Testprogramm erkennen (Hauptdatei verwendet DUnitX.TestFramework) und
//   entscheiden, ob die Tests nach einem Build laufen (Einstellungen
//   TestRun und TestsAfterBuild, nur nach einem Build, der nach der Bewertung
//   von #530 als erfolgreich gilt (build.zeroHints, build.warningsAsErrors,
//   Basislinie; Atlas.Core.Build.Verdict); nie nach der Hintergrundprüfung und
//   nie nach einem Build, den Atlas oder Claude Code angestoßen hat).
// - Ergebnis aus dem XML-Bericht (Atlas.Text.TestResults) den Testmethoden
//   zuordnen: Unit der Fixture über das Projekt, darin der Methodenkopf im
//   implementation-Teil (Atlas.Text.DUnitX, gemeinsam mit dem MCP-Werkzeug
//   run_tests und #154).
// - Daraus Probleme im Editor (Quelle "DUnitX", erwarteter und tatsächlicher
//   Wert), den Abschnitt "tests" der Projekt-Zusammenfassung (#592, Karte
//   Tests #763) und den Stand je Test für die Code Lens.
// Dateien liest der Aufrufer (Puffer der IDE oder Platte); Zeilen sind hier
// 0-basiert, in der Zusammenfassung 1-basiert.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Projects.Summary,
  Atlas.Text.DUnitX,
  Atlas.Text.TestResults;

type
{$SCOPEDENUMS ON}
  /// <summary>Stand eines Tests bzw. einer Fixture nach dem letzten Lauf. Partial: Von mehreren Tests (Fixture,
  /// [TestCase]-Methode) lief erst ein Teil, keiner schlug fehl.</summary>
  TAtlasTestStatus = (Unknown, Passed, Failed, Partial);
{$SCOPEDENUMS OFF}

  /// <summary>Ein Test, den der Lauf einer Marke ergibt: Methode und Fall ('' ohne [TestCase]).</summary>
  TAtlasTestKey = record
    Method: string;
    CaseName: string;
  end;

  /// <summary>Stand der Tests einer Marke (Fixture, Test mit Fällen) über alle bisherigen Läufe.</summary>
  TAtlasTestTally = record
    /// <summary>Tests der Marke.</summary>
    Total: Integer;
    /// <summary>Davon mit Ergebnis (bestanden, fehlgeschlagen oder übersprungen).</summary>
    Ran: Integer;
    Passed: Integer;
    Failed: Integer;
    /// <summary>Failed bei einem Fehlschlag; Passed erst, wenn jeder Test ein Ergebnis hat und mindestens einer
    /// bestand; Partial, wenn erst ein Teil lief; sonst Unknown.</summary>
    function Status: TAtlasTestStatus;
  end;

  /// <summary>Datei der Unit AUnitName im Testprojekt; '' ohne.</summary>
  TAtlasTestUnitFile = reference to function(const AUnitName: string): string;
  /// <summary>Zeilen einer Datei (ohne Zeilenende); False, wenn sie nicht lesbar ist.</summary>
  TAtlasTestReadLines = reference to function(const AFileName: string; out ALines: TArray<string>): Boolean;

  /// <summary>Was läuft: Testprojekt, Ziel und Filter.</summary>
  TAtlasTestTarget = record
    /// <summary>.dproj des Testprojekts.</summary>
    Project: string;
    Configuration: string;
    Platform: string;
    /// <summary>Test-EXE (Zielname des Projekts).</summary>
    Executable: string;
    /// <summary>Namen für --run; leer = alle.</summary>
    Tests: TArray<string>;
  end;

  /// <summary>Fehlgeschlagener Test mit Fundstelle.</summary>
  TAtlasTestFailure = record
    Test: TTestCaseResult;
    /// <summary>Datei der Testunit; '' ohne Fundstelle.</summary>
    FileName: string;
    /// <summary>Zeile des Methodenkopfs (0-basiert); -1 ohne.</summary>
    Line: Integer;
    /// <summary>Erstes und letztes Zeichen des Texts in der Zeile (0-basiert) für die Markierung.</summary>
    StartCharacter: Integer;
    EndCharacter: Integer;
  end;

  TAtlasTestRun = class
  public const
    /// <summary>Zeitlimit eines Laufs.</summary>
    cTimeoutMs = 600000;
    /// <summary>Auftraggeber eines Builds vor den Tests (Compile-Ereignisse #527): löst keinen Lauf nach dem
    /// Build aus.</summary>
    cRequestedBy = 'tests';
  public
    /// <summary>Hauptdatei eines DUnitX-Testprogramms?</summary>
    class function IsTestProgram(const ALines: TArray<string>): Boolean; static;
    /// <summary>Kann Atlas eine EXE der Plattform starten (Windows)? '' gilt als Win32 der IDE.</summary>
    class function CanRun(const APlatform: string): Boolean; static;
    /// <summary>Tests nach diesem Build ausführen? ASucceeded: Der Build gilt als erfolgreich
    /// (TAtlasBuildVerdict.Effective, #530). AIsTestProgram: das gebaute Projekt ist ein Testprogramm.
    /// ARequestedBy: Auftraggeber des Builds ('' = Benutzer).</summary>
    class function ShouldRunAfterBuild(const ASettings: TAtlasPluginSettings; ASucceeded, ABackground: Boolean;
      const ARequestedBy: string; AIsTestProgram: Boolean): Boolean; static;
    /// <summary>Fehlgeschlagene Tests mit Fundstelle; liest jede Testunit höchstens einmal.</summary>
    class function Failures(const ARun: TTestRunResult; const AUnitFile: TAtlasTestUnitFile;
      const AReadLines: TAtlasTestReadLines): TArray<TAtlasTestFailure>; static;
    /// <summary>Kurzer Name eines Tests für Meldungen: Fixture.Methode[.Fall].</summary>
    class function ShortName(const ACase: TTestCaseResult): string; static;
    /// <summary>Text des Problems: AValuesFormat (%s Name, %s erwartet, %s erhalten) mit erwartetem und
    /// tatsächlichem Wert, sonst AFormat (%s Name, %s Meldung).</summary>
    class function ProblemText(const ACase: TTestCaseResult; const AFormat, AValuesFormat: string): string; static;
    /// <summary>Probleme je Datei (nur Tests mit Fundstelle) für den Problem-Speicher.</summary>
    class function Problems(const AFailures: TArray<TAtlasTestFailure>; const AFormat,
      AValuesFormat: string): TArray<TPair<string, TAtlasProblem>>; static;
    /// <summary>Abschnitt "tests" der Projekt-Zusammenfassung; höchstens TAtlasProjectTests.MaxFailures Tests.
    /// </summary>
    class function SummaryOf(const ATarget: TAtlasTestTarget; const ARun: TTestRunResult;
      const AFailures: TArray<TAtlasTestFailure>; AAtUtc: TDateTime): TAtlasProjectTests; static;
    /// <summary>Stand eines Tests (AMethod) bzw. einer Fixture (AMethod = '') in den Ergebnissen: Failed, wenn
    /// ein Fall fehlschlug, Passed, wenn mindestens einer bestand und keiner fehlschlug, sonst Unknown.</summary>
    class function StatusOf(const ACases: TArray<TTestCaseResult>; const AUnitName, AFixture,
      AMethod: string): TAtlasTestStatus; overload; static;
    /// <summary>Wie oben, nur der Fall ACaseName eines [TestCase] (#585); ACaseName '' = alle Fälle.</summary>
    class function StatusOf(const ACases: TArray<TTestCaseResult>; const AUnitName, AFixture, AMethod,
      ACaseName: string): TAtlasTestStatus; overload; static;
    /// <summary>Tests, die der Lauf einer Marke ergibt: Fixture AFixtureIndex, Test ATestIndex (-1 = alle) und Fall
    /// ACaseIndex (-1 = alle). Tests mit [Ignore] zählen nicht.</summary>
    class function Expected(const AUnit: TDUnitXUnit; AFixtureIndex, ATestIndex,
      ACaseIndex: Integer): TArray<TAtlasTestKey>; static;
    /// <summary>Stand der Tests AKeys der Fixture AFixture in den Ergebnissen.</summary>
    class function TallyOf(const ACases: TArray<TTestCaseResult>; const AUnitName, AFixture: string;
      const AKeys: TArray<TAtlasTestKey>): TAtlasTestTally; static;
  end;

implementation

uses
  Atlas.Core.Problems.Store;

{ TAtlasTestTally }

function TAtlasTestTally.Status: TAtlasTestStatus;
begin
  Result := TAtlasTestStatus.Unknown;
  if Failed > 0 then
  begin
    Result := TAtlasTestStatus.Failed;
  end
  else if (Total > 0) and (Ran >= Total) and (Passed > 0) then
  begin
    Result := TAtlasTestStatus.Passed;
  end
  else if (Ran > 0) and (Ran < Total) then
  begin
    Result := TAtlasTestStatus.Partial;
  end;
end;

{ TAtlasTestRun }

class function TAtlasTestRun.IsTestProgram(const ALines: TArray<string>): Boolean;
begin
  Result := TDUnitXSource.UsesDUnitX(ALines);
end;

class function TAtlasTestRun.CanRun(const APlatform: string): Boolean;
begin
  Result := (APlatform = '') or SameText(APlatform, 'Win32') or SameText(APlatform, 'Win64') or
    SameText(APlatform, 'Win64x');
end;

class function TAtlasTestRun.ShouldRunAfterBuild(const ASettings: TAtlasPluginSettings; ASucceeded,
  ABackground: Boolean; const ARequestedBy: string; AIsTestProgram: Boolean): Boolean;
begin
  // build.zeroHints und build.warningsAsErrors stecken in ASucceeded (eine Bewertung, #530).
  Result := ASettings.Enabled and ASettings.TestRun and ASettings.TestsAfterBuild and ASucceeded and
    not ABackground and (ARequestedBy = '') and AIsTestProgram;
end;

/// <summary>Zeile und Spalten des Tests in ALines eintragen; ohne Fundstelle Zeile -1.</summary>
procedure PlaceFailure(var AFailure: TAtlasTestFailure; const AFound: TDUnitXUnit; const ALines: TArray<string>);
var
  mText: string;
  mIndex: Integer;
begin
  AFailure.Line := AFound.LineOf(AFailure.Test.Fixture, AFailure.Test.Method);
  if (AFailure.Line < 0) or (AFailure.Line > High(ALines)) then
  begin
    AFailure.Line := -1;
    Exit;
  end;
  mText := ALines[AFailure.Line];
  mIndex := 0;
  while (mIndex < Length(mText)) and ((mText[mIndex + 1] = ' ') or (mText[mIndex + 1] = #9)) do
  begin
    Inc(mIndex);
  end;
  AFailure.StartCharacter := mIndex;
  AFailure.EndCharacter := Length(TrimRight(mText));
end;

/// <summary>Unit einmal je Datei lesen und durchsuchen; das Ergebnis bleibt in AUnits und ATexts.</summary>
procedure ScanOnce(const AFileName: string; const AReadLines: TAtlasTestReadLines;
  AUnits: TDictionary<string, TDUnitXUnit>; ATexts: TDictionary<string, TArray<string>>;
  out AFound: TDUnitXUnit; out ALines: TArray<string>);
var
  mKey: string;
begin
  mKey := AnsiLowerCase(AFileName);
  if not AUnits.TryGetValue(mKey, AFound) then
  begin
    if not Assigned(AReadLines) or not AReadLines(AFileName, ALines) then
    begin
      ALines := nil;
    end;
    AFound := TDUnitXSource.Scan(ALines);
    AUnits.Add(mKey, AFound);
    ATexts.Add(mKey, ALines);
  end;
  ALines := ATexts[mKey];
end;

class function TAtlasTestRun.Failures(const ARun: TTestRunResult; const AUnitFile: TAtlasTestUnitFile;
  const AReadLines: TAtlasTestReadLines): TArray<TAtlasTestFailure>;
var
  mUnits: TDictionary<string, TDUnitXUnit>;
  mTexts: TDictionary<string, TArray<string>>;
  mItem: TTestCaseResult;
  mFailure: TAtlasTestFailure;
  mFound: TDUnitXUnit;
  mLines: TArray<string>;
begin
  Result := nil;
  mUnits := TDictionary<string, TDUnitXUnit>.Create;
  mTexts := TDictionary<string, TArray<string>>.Create;
  try
    for mItem in ARun.Failures do
    begin
      mFailure := Default(TAtlasTestFailure);
      mFailure.Test := mItem;
      mFailure.Line := -1;
      if (mItem.UnitName <> '') and Assigned(AUnitFile) then
      begin
        mFailure.FileName := AUnitFile(mItem.UnitName);
      end;
      if mFailure.FileName <> '' then
      begin
        ScanOnce(mFailure.FileName, AReadLines, mUnits, mTexts, mFound, mLines);
        if Length(mLines) = 0 then
        begin
          // Datei nicht lesbar: keine Fundstelle.
          mFailure.FileName := '';
        end
        else
        begin
          PlaceFailure(mFailure, mFound, mLines);
        end;
      end;
      Result := Result + [mFailure];
    end;
  finally
    mTexts.Free;
    mUnits.Free;
  end;
end;

class function TAtlasTestRun.ShortName(const ACase: TTestCaseResult): string;
begin
  Result := ACase.Method;
  if ACase.Fixture <> '' then
  begin
    Result := ACase.Fixture + '.' + Result;
  end;
  if ACase.CaseName <> '' then
  begin
    Result := Result + '.' + ACase.CaseName;
  end;
  if Result = '' then
  begin
    Result := ACase.FullName;
  end;
end;

class function TAtlasTestRun.ProblemText(const ACase: TTestCaseResult; const AFormat, AValuesFormat: string): string;
var
  mMessage: string;
  mIndex: Integer;
begin
  if ACase.HasValues then
  begin
    Exit(Format(AValuesFormat, [ShortName(ACase), ACase.Expected, ACase.Actual]));
  end;
  // Nur die erste Zeile: Die Liste der Probleme zeigt eine Zeile je Eintrag.
  mMessage := Trim(ACase.Message);
  mIndex := Pos(#10, mMessage);
  if mIndex > 0 then
  begin
    mMessage := TrimRight(Copy(mMessage, 1, mIndex - 1));
  end;
  Result := Format(AFormat, [ShortName(ACase), mMessage]);
end;

class function TAtlasTestRun.Problems(const AFailures: TArray<TAtlasTestFailure>; const AFormat,
  AValuesFormat: string): TArray<TPair<string, TAtlasProblem>>;
var
  mFailure: TAtlasTestFailure;
  mProblem: TAtlasProblem;
begin
  Result := nil;
  for mFailure in AFailures do
  begin
    if (mFailure.FileName = '') or (mFailure.Line < 0) then
    begin
      Continue;
    end;
    mProblem := Default(TAtlasProblem);
    mProblem.StartLine := mFailure.Line;
    mProblem.EndLine := mFailure.Line;
    mProblem.StartCharacter := mFailure.StartCharacter;
    mProblem.EndCharacter := mFailure.EndCharacter;
    mProblem.Severity := TAtlasProblemSeverity.Error;
    // Ohne Code: kein Regeltreffer (Projekt-Zusammenfassung, Baseline).
    mProblem.Code := '';
    mProblem.Source := TAtlasProblemStore.TestSource;
    mProblem.Message := ProblemText(mFailure.Test, AFormat, AValuesFormat);
    Result := Result + [TPair<string, TAtlasProblem>.Create(mFailure.FileName, mProblem)];
  end;
end;

class function TAtlasTestRun.SummaryOf(const ATarget: TAtlasTestTarget; const ARun: TTestRunResult;
  const AFailures: TArray<TAtlasTestFailure>; AAtUtc: TDateTime): TAtlasProjectTests;
var
  mFailure: TAtlasTestFailure;
  mItem: TAtlasProjectTestFailure;
begin
  Result := TAtlasProjectTests.Empty;
  Result.Known := True;
  Result.At := AAtUtc;
  Result.Project := ATarget.Project;
  Result.Configuration := ATarget.Configuration;
  Result.Platform := ATarget.Platform;
  Result.Passed := ARun.Count(TTestOutcome.Passed);
  Result.Failed := ARun.Count(TTestOutcome.Failed);
  Result.Errors := ARun.Count(TTestOutcome.Error);
  Result.Skipped := ARun.Count(TTestOutcome.Skipped);
  Result.DurationMs := Integer(ARun.DurationMs);
  for mFailure in AFailures do
  begin
    if Length(Result.Failures) >= TAtlasProjectTests.MaxFailures then
    begin
      Break;
    end;
    mItem := Default(TAtlasProjectTestFailure);
    mItem.Test := mFailure.Test.FullName;
    mItem.Message := mFailure.Test.Message;
    mItem.FileName := mFailure.FileName;
    if mFailure.Line >= 0 then
    begin
      mItem.Line := mFailure.Line + 1;
    end;
    Result.Failures := Result.Failures + [mItem];
  end;
end;

/// <summary>Gehört das Ergebnis AItem zu Unit, Fixture, Methode ('' = alle) und Fall ('' = alle)?</summary>
function Matches(const AItem: TTestCaseResult; const AUnitName, AFixture, AMethod, ACaseName: string): Boolean;
begin
  Result := SameText(AItem.Fixture, AFixture) and ((AUnitName = '') or (AItem.UnitName = '') or
    SameText(AItem.UnitName, AUnitName)) and ((AMethod = '') or SameText(AItem.Method, AMethod)) and
    ((ACaseName = '') or SameText(AItem.CaseName, ACaseName));
end;

class function TAtlasTestRun.StatusOf(const ACases: TArray<TTestCaseResult>; const AUnitName, AFixture,
  AMethod: string): TAtlasTestStatus;
begin
  Result := StatusOf(ACases, AUnitName, AFixture, AMethod, '');
end;

class function TAtlasTestRun.StatusOf(const ACases: TArray<TTestCaseResult>; const AUnitName, AFixture, AMethod,
  ACaseName: string): TAtlasTestStatus;
var
  mItem: TTestCaseResult;
begin
  Result := TAtlasTestStatus.Unknown;
  for mItem in ACases do
  begin
    if not Matches(mItem, AUnitName, AFixture, AMethod, ACaseName) then
    begin
      Continue;
    end;
    if mItem.IsFailure then
    begin
      Exit(TAtlasTestStatus.Failed);
    end;
    if mItem.Outcome = TTestOutcome.Passed then
    begin
      Result := TAtlasTestStatus.Passed;
    end;
  end;
end;

/// <summary>Schlüssel des Tests ATest anhängen: alle Fälle (ACaseIndex -1), ein Fall oder der Test ohne Fälle.
/// </summary>
procedure AddKeys(var AKeys: TArray<TAtlasTestKey>; const ATest: TDUnitXTest; ACaseIndex: Integer);
var
  mCase, mCount: Integer;
begin
  if ATest.Ignored then
  begin
    Exit;
  end;
  mCount := Length(AKeys);
  if Length(ATest.Cases) = 0 then
  begin
    SetLength(AKeys, mCount + 1);
    AKeys[mCount].Method := ATest.Method;
    AKeys[mCount].CaseName := '';
  end
  else if (ACaseIndex >= 0) and (ACaseIndex <= High(ATest.Cases)) then
  begin
    SetLength(AKeys, mCount + 1);
    AKeys[mCount].Method := ATest.Method;
    AKeys[mCount].CaseName := ATest.Cases[ACaseIndex];
  end
  else
  begin
    SetLength(AKeys, mCount + Length(ATest.Cases));
    for mCase := 0 to High(ATest.Cases) do
    begin
      AKeys[mCount + mCase].Method := ATest.Method;
      AKeys[mCount + mCase].CaseName := ATest.Cases[mCase];
    end;
  end;
end;

class function TAtlasTestRun.Expected(const AUnit: TDUnitXUnit; AFixtureIndex, ATestIndex,
  ACaseIndex: Integer): TArray<TAtlasTestKey>;
var
  mTests: TArray<TDUnitXTest>;
  mTest: Integer;
begin
  Result := nil;
  if (AFixtureIndex < 0) or (AFixtureIndex > High(AUnit.Fixtures)) then
  begin
    Exit;
  end;
  mTests := AUnit.Fixtures[AFixtureIndex].Tests;
  if ATestIndex < 0 then
  begin
    for mTest := 0 to High(mTests) do
    begin
      AddKeys(Result, mTests[mTest], -1);
    end;
  end
  else if ATestIndex <= High(mTests) then
  begin
    AddKeys(Result, mTests[ATestIndex], ACaseIndex);
  end;
end;

/// <summary>Gibt es ein Ergebnis (auch übersprungen) zum Test AKey?</summary>
function HasResult(const ACases: TArray<TTestCaseResult>; const AUnitName, AFixture: string;
  const AKey: TAtlasTestKey): Boolean;
var
  mItem: TTestCaseResult;
begin
  Result := False;
  for mItem in ACases do
  begin
    if Matches(mItem, AUnitName, AFixture, AKey.Method, AKey.CaseName) then
    begin
      Exit(True);
    end;
  end;
end;

class function TAtlasTestRun.TallyOf(const ACases: TArray<TTestCaseResult>; const AUnitName, AFixture: string;
  const AKeys: TArray<TAtlasTestKey>): TAtlasTestTally;
var
  mKey: TAtlasTestKey;
  mStatus: TAtlasTestStatus;
begin
  Result := Default(TAtlasTestTally);
  Result.Total := Length(AKeys);
  for mKey in AKeys do
  begin
    if not HasResult(ACases, AUnitName, AFixture, mKey) then
    begin
      Continue;
    end;
    Inc(Result.Ran);
    mStatus := StatusOf(ACases, AUnitName, AFixture, mKey.Method, mKey.CaseName);
    if mStatus = TAtlasTestStatus.Failed then
    begin
      Inc(Result.Failed);
    end
    else if mStatus = TAtlasTestStatus.Passed then
    begin
      Inc(Result.Passed);
    end;
  end;
end;

end.
