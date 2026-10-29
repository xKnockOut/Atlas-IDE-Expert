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
  Atlas.Text.TestResults;

type
{$SCOPEDENUMS ON}
  /// <summary>Stand eines Tests bzw. einer Fixture nach dem letzten Lauf.</summary>
  TAtlasTestStatus = (Unknown, Passed, Failed);
{$SCOPEDENUMS OFF}

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
    TimeoutMs = 600000;
    /// <summary>Auftraggeber eines Builds vor den Tests (Compile-Ereignisse #527): löst keinen Lauf nach dem
    /// Build aus.</summary>
    RequestedBy = 'tests';
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
  end;

implementation

uses
  Atlas.Core.Problems.Store,
  Atlas.Text.DUnitX;

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

class function TAtlasTestRun.Failures(const ARun: TTestRunResult; const AUnitFile: TAtlasTestUnitFile;
  const AReadLines: TAtlasTestReadLines): TArray<TAtlasTestFailure>;
var
  Units: TDictionary<string, TDUnitXUnit>;
  Texts: TDictionary<string, TArray<string>>;
  Item: TTestCaseResult;
  Failure: TAtlasTestFailure;
  Found: TDUnitXUnit;
  Lines: TArray<string>;
  Key, Text: string;
  Index: Integer;
begin
  Result := nil;
  Units := TDictionary<string, TDUnitXUnit>.Create;
  Texts := TDictionary<string, TArray<string>>.Create;
  try
    for Item in ARun.Failures do
    begin
      Failure := Default(TAtlasTestFailure);
      Failure.Test := Item;
      Failure.Line := -1;
      if (Item.UnitName <> '') and Assigned(AUnitFile) then
        Failure.FileName := AUnitFile(Item.UnitName);
      if Failure.FileName <> '' then
      begin
        Key := AnsiLowerCase(Failure.FileName);
        if not Units.TryGetValue(Key, Found) then
        begin
          if not Assigned(AReadLines) or not AReadLines(Failure.FileName, Lines) then
            Lines := nil;
          Found := TDUnitXSource.Scan(Lines);
          Units.Add(Key, Found);
          Texts.Add(Key, Lines);
        end;
        Lines := Texts[Key];
        if Length(Lines) = 0 then
          // Datei nicht lesbar: keine Fundstelle.
          Failure.FileName := ''
        else
        begin
          Failure.Line := Found.LineOf(Item.Fixture, Item.Method);
          if (Failure.Line >= 0) and (Failure.Line <= High(Lines)) then
          begin
            Text := Lines[Failure.Line];
            Index := 0;
            while (Index < Length(Text)) and ((Text[Index + 1] = ' ') or (Text[Index + 1] = #9)) do
              Inc(Index);
            Failure.StartCharacter := Index;
            Failure.EndCharacter := Length(TrimRight(Text));
          end
          else
            Failure.Line := -1;
        end;
      end;
      Result := Result + [Failure];
    end;
  finally
    Texts.Free;
    Units.Free;
  end;
end;

class function TAtlasTestRun.ShortName(const ACase: TTestCaseResult): string;
begin
  Result := ACase.Method;
  if ACase.Fixture <> '' then
    Result := ACase.Fixture + '.' + Result;
  if ACase.CaseName <> '' then
    Result := Result + '.' + ACase.CaseName;
  if Result = '' then
    Result := ACase.FullName;
end;

class function TAtlasTestRun.ProblemText(const ACase: TTestCaseResult; const AFormat, AValuesFormat: string): string;
var
  Message: string;
  Index: Integer;
begin
  if ACase.HasValues then
    Exit(Format(AValuesFormat, [ShortName(ACase), ACase.Expected, ACase.Actual]));
  // Nur die erste Zeile: Die Liste der Probleme zeigt eine Zeile je Eintrag.
  Message := Trim(ACase.Message);
  Index := Pos(#10, Message);
  if Index > 0 then
    Message := TrimRight(Copy(Message, 1, Index - 1));
  Result := Format(AFormat, [ShortName(ACase), Message]);
end;

class function TAtlasTestRun.Problems(const AFailures: TArray<TAtlasTestFailure>; const AFormat,
  AValuesFormat: string): TArray<TPair<string, TAtlasProblem>>;
var
  Failure: TAtlasTestFailure;
  Problem: TAtlasProblem;
begin
  Result := nil;
  for Failure in AFailures do
  begin
    if (Failure.FileName = '') or (Failure.Line < 0) then
      Continue;
    Problem := Default(TAtlasProblem);
    Problem.StartLine := Failure.Line;
    Problem.EndLine := Failure.Line;
    Problem.StartCharacter := Failure.StartCharacter;
    Problem.EndCharacter := Failure.EndCharacter;
    Problem.Severity := TAtlasProblemSeverity.Error;
    // Ohne Code: kein Regeltreffer (Projekt-Zusammenfassung, Baseline).
    Problem.Code := '';
    Problem.Source := TAtlasProblemStore.TestSource;
    Problem.Message := ProblemText(Failure.Test, AFormat, AValuesFormat);
    Result := Result + [TPair<string, TAtlasProblem>.Create(Failure.FileName, Problem)];
  end;
end;

class function TAtlasTestRun.SummaryOf(const ATarget: TAtlasTestTarget; const ARun: TTestRunResult;
  const AFailures: TArray<TAtlasTestFailure>; AAtUtc: TDateTime): TAtlasProjectTests;
var
  Failure: TAtlasTestFailure;
  Item: TAtlasProjectTestFailure;
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
  for Failure in AFailures do
  begin
    if Length(Result.Failures) >= TAtlasProjectTests.MaxFailures then
      Break;
    Item := Default(TAtlasProjectTestFailure);
    Item.Test := Failure.Test.FullName;
    Item.Message := Failure.Test.Message;
    Item.FileName := Failure.FileName;
    if Failure.Line >= 0 then
      Item.Line := Failure.Line + 1;
    Result.Failures := Result.Failures + [Item];
  end;
end;

class function TAtlasTestRun.StatusOf(const ACases: TArray<TTestCaseResult>; const AUnitName, AFixture,
  AMethod: string): TAtlasTestStatus;
begin
  Result := StatusOf(ACases, AUnitName, AFixture, AMethod, '');
end;

class function TAtlasTestRun.StatusOf(const ACases: TArray<TTestCaseResult>; const AUnitName, AFixture, AMethod,
  ACaseName: string): TAtlasTestStatus;
var
  Item: TTestCaseResult;
begin
  Result := TAtlasTestStatus.Unknown;
  for Item in ACases do
  begin
    if not SameText(Item.Fixture, AFixture) or ((AUnitName <> '') and (Item.UnitName <> '') and
      not SameText(Item.UnitName, AUnitName)) then
      Continue;
    if (AMethod <> '') and not SameText(Item.Method, AMethod) then
      Continue;
    if (ACaseName <> '') and not SameText(Item.CaseName, ACaseName) then
      Continue;
    if Item.IsFailure then
      Exit(TAtlasTestStatus.Failed);
    if Item.Outcome = TTestOutcome.Passed then
      Result := TAtlasTestStatus.Passed;
  end;
end;

end.
