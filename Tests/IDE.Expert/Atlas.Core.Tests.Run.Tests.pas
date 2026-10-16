unit Atlas.Core.Tests.Run.Tests;

// Tests des Testlaufs aus der IDE (#69) ohne IDE: Testprogramm und Plattform,
// Lauf nach dem Build (mit build.zeroHints #530), Zuordnung fehlgeschlagener
// Tests zur Testmethode, Probleme mit erwartetem und tatsächlichem Wert,
// Abschnitt "tests" der Projekt-Zusammenfassung und Stand für die Code Lens.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTestRunTests = class
  public
    [Test]
    procedure RecognizesTestProgramAndPlatforms;
    [Test]
    procedure RunsAfterSuccessfulUserBuildOnly;
    [Test]
    procedure ZeroHintsNeedsCleanBuild;
    [Test]
    procedure FailureSitsOnTestMethod;
    [Test]
    procedure ProblemsCarryExpectedAndActual;
    [Test]
    procedure SummaryForWelcomePage;
    [Test]
    procedure StatusForLens;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Store,
  Atlas.Core.Build.Messages,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Tests.Run,
  Atlas.Text.TestResults;

const
  UnitFile = 'C:\Projekt\Tests\Rechner.Tests.pas';
  Report =
    '<test-results total="3">' +
    '<test-suite type="Assembly" name="Rechner.Tests.exe" time="0.5"><results>' +
    '<test-suite type="Namespace" name="Rechner"><results>' +
    '<test-suite type="TestFixture" name="TRechnerTests"><results>' +
    '<test-case name="Rechner.Tests.TRechnerTests.Addiert" executed="True" result="Success" time="0.01"/>' +
    '<test-case name="Rechner.Tests.TRechnerTests.Summe.Gross" executed="True" result="Failure" time="0.02">' +
      '<failure><message>Expected 30 but got 31</message></failure></test-case>' +
    '<test-case name="Rechner.Tests.TRechnerTests.Teilt" executed="True" result="Error" time="0.01">' +
      '<failure><message>EZeroDivide: Division durch 0' + #10 + 'bei Zeile 7</message></failure></test-case>' +
    '</results></test-suite></results></test-suite></results></test-suite></test-results>';

function Source: TArray<string>;
begin
  Result := [
    'unit Rechner.Tests;',                                  // 0
    'interface',                                            // 1
    'uses DUnitX.TestFramework;',                           // 2
    'type',                                                 // 3
    '  [TestFixture]',                                      // 4
    '  TRechnerTests = class',                              // 5
    '  public',                                             // 6
    '    [Test]',                                           // 7
    '    procedure Addiert;',                               // 8
    '    [TestCase(''Gross'', ''10,20,30'')]',              // 9
    '    procedure Summe(A, B, C: Integer);',               // 10
    '    [Test]',                                           // 11
    '    procedure Teilt;',                                 // 12
    '  end;',                                               // 13
    'implementation',                                       // 14
    'procedure TRechnerTests.Addiert;',                     // 15
    'begin',                                                // 16
    'end;',                                                 // 17
    '  procedure TRechnerTests.Summe(A, B, C: Integer);',   // 18
    'begin',                                                // 19
    'end;',                                                 // 20
    'procedure TRechnerTests.Teilt;',                       // 21
    'begin',                                                // 22
    'end;',                                                 // 23
    'end.'];
end;

function Failures(out AReads: Integer): TArray<TAtlasTestFailure>;
var
  Reads: Integer;
begin
  Reads := 0;
  Result := TAtlasTestRun.Failures(TTestResults.Parse(Report),
    function(const AUnitName: string): string
    begin
      Result := '';
      if SameText(AUnitName, 'Rechner.Tests') then
        Result := UnitFile;
    end,
    function(const AFileName: string; out ALines: TArray<string>): Boolean
    begin
      Inc(Reads);
      Result := SameText(AFileName, UnitFile);
      if Result then
        ALines := Source
      else
        ALines := nil;
    end);
  AReads := Reads;
end;

function Settings: TAtlasPluginSettings;
begin
  Result := TAtlasPluginSettings.Defaults;
  Result.TestsAfterBuild := True;
end;

{ TAtlasTestRunTests }

procedure TAtlasTestRunTests.RecognizesTestProgramAndPlatforms;
begin
  Assert.IsTrue(TAtlasTestRun.IsTestProgram(['program Rechner.Tests;', 'uses', '  DUnitX.TestFramework,',
    '  Rechner.Tests;', 'begin', 'end.']));
  Assert.IsFalse(TAtlasTestRun.IsTestProgram(['program Rechner;', 'uses', '  Vcl.Forms;', 'begin', 'end.']));
  Assert.IsTrue(TAtlasTestRun.CanRun('Win64'), 'nur Win64 läuft als Win64');
  Assert.IsTrue(TAtlasTestRun.CanRun('win32'));
  Assert.IsFalse(TAtlasTestRun.CanRun('Linux64'));
  Assert.IsFalse(TAtlasTestRun.CanRun('Android64'));
end;

procedure TAtlasTestRunTests.RunsAfterSuccessfulUserBuildOnly;
var
  Value: TAtlasPluginSettings;
begin
  Value := Settings;
  Assert.IsTrue(TAtlasTestRun.ShouldRunAfterBuild(Value, True, False, '', 3, True));
  Assert.IsFalse(TAtlasTestRun.ShouldRunAfterBuild(Value, False, False, '', 0, True), 'Build fehlgeschlagen');
  Assert.IsFalse(TAtlasTestRun.ShouldRunAfterBuild(Value, True, True, '', 0, True), 'Hintergrundprüfung');
  Assert.IsFalse(TAtlasTestRun.ShouldRunAfterBuild(Value, True, False, TAtlasTestRun.RequestedBy, 0, True),
    'Build vor den Tests');
  Assert.IsFalse(TAtlasTestRun.ShouldRunAfterBuild(Value, True, False, 'mcp', 0, True), 'Build für Claude Code');
  Assert.IsFalse(TAtlasTestRun.ShouldRunAfterBuild(Value, True, False, '', 0, False), 'kein Testprogramm');
  Value.TestsAfterBuild := False;
  Assert.IsFalse(TAtlasTestRun.ShouldRunAfterBuild(Value, True, False, '', 0, True), 'Vorgabe aus');
  Value := Settings;
  Value.TestRun := False;
  Assert.IsFalse(TAtlasTestRun.ShouldRunAfterBuild(Value, True, False, '', 0, True), 'Tests ausführen aus');
  Value := Settings;
  Value.Enabled := False;
  Assert.IsFalse(TAtlasTestRun.ShouldRunAfterBuild(Value, True, False, '', 0, True), 'Atlas aus');
end;

procedure TAtlasTestRunTests.ZeroHintsNeedsCleanBuild;
var
  Value: TAtlasPluginSettings;
  Messages: TArray<TAtlasCompilerMessage>;
begin
  SetLength(Messages, 3);
  Messages[0].Severity := TAtlasCompilerSeverity.Hint;
  Messages[1].Severity := TAtlasCompilerSeverity.Warning;
  Messages[2].Severity := TAtlasCompilerSeverity.Info;
  Assert.AreEqual(2, TAtlasTestRun.WarningsAndHints(Messages));
  Value := Settings;
  Value.BuildZeroHints := True;
  Assert.IsFalse(TAtlasTestRun.ShouldRunAfterBuild(Value, True, False, '', 2, True), 'mit Hinweisen nicht');
  Assert.IsTrue(TAtlasTestRun.ShouldRunAfterBuild(Value, True, False, '', 0, True), 'ohne Hinweise');
end;

procedure TAtlasTestRunTests.FailureSitsOnTestMethod;
var
  Found: TArray<TAtlasTestFailure>;
  Reads: Integer;
begin
  Found := Failures(Reads);
  Assert.AreEqual(2, Length(Found));
  Assert.AreEqual(1, Reads, 'jede Testunit einmal lesen');
  Assert.AreEqual(UnitFile, Found[0].FileName);
  Assert.AreEqual(18, Found[0].Line, 'Methodenkopf im implementation-Teil, nicht die Deklaration');
  Assert.AreEqual(2, Found[0].StartCharacter, 'ab dem ersten Zeichen');
  Assert.AreEqual(Length('  procedure TRechnerTests.Summe(A, B, C: Integer);'), Found[0].EndCharacter);
  Assert.AreEqual(21, Found[1].Line);
end;

procedure TAtlasTestRunTests.ProblemsCarryExpectedAndActual;
var
  Found: TArray<TAtlasTestFailure>;
  Reads: Integer;
  Items: TArray<TPair<string, TAtlasProblem>>;
begin
  Found := Failures(Reads);
  Items := TAtlasTestRun.Problems(Found, 'Test %s fehlgeschlagen: %s', 'Test %s fehlgeschlagen: erwartet %s, erhalten %s');
  Assert.AreEqual(2, Length(Items));
  Assert.AreEqual(UnitFile, Items[0].Key);
  Assert.AreEqual('Test TRechnerTests.Summe.Gross fehlgeschlagen: erwartet 30, erhalten 31', Items[0].Value.Message);
  Assert.AreEqual(18, Items[0].Value.StartLine);
  Assert.AreEqual(TAtlasProblemStore.TestSource, Items[0].Value.Source);
  Assert.IsTrue(Items[0].Value.Severity = TAtlasProblemSeverity.Error);
  Assert.AreEqual('', Items[0].Value.Code, 'kein Regeltreffer');
  Assert.AreEqual('Test TRechnerTests.Teilt fehlgeschlagen: EZeroDivide: Division durch 0', Items[1].Value.Message,
    'nur die erste Zeile');
  // Ohne Fundstelle kein Problem.
  Found[1].FileName := '';
  Assert.AreEqual(1, Length(TAtlasTestRun.Problems(Found, '%s %s', '%s %s %s')));
end;

procedure TAtlasTestRunTests.SummaryForWelcomePage;
var
  Target: TAtlasTestTarget;
  Found: TArray<TAtlasTestFailure>;
  Reads: Integer;
  Tests: TAtlasProjectTests;
begin
  Target := Default(TAtlasTestTarget);
  Target.Project := 'C:\Projekt\Rechner.Tests.dproj';
  Target.Configuration := 'Debug';
  Target.Platform := 'Win64';
  Found := Failures(Reads);
  Tests := TAtlasTestRun.SummaryOf(Target, TTestResults.Parse(Report), Found, EncodeDate(2026, 10, 16));
  Assert.IsTrue(Tests.Known);
  Assert.AreEqual('Win64', Tests.Platform);
  Assert.AreEqual(1, Tests.Passed);
  Assert.AreEqual(1, Tests.Failed);
  Assert.AreEqual(1, Tests.Errors);
  Assert.AreEqual(500, Tests.DurationMs);
  Assert.AreEqual(2, Length(Tests.Failures));
  Assert.AreEqual('Rechner.Tests.TRechnerTests.Summe.Gross', Tests.Failures[0].Test, 'voller Name für --run');
  Assert.AreEqual(19, Tests.Failures[0].Line, '1-basiert');
  Assert.AreEqual(UnitFile, Tests.Failures[0].FileName);
  Assert.AreEqual(2, Length(Tests.FailedTests));
end;

procedure TAtlasTestRunTests.StatusForLens;
var
  Cases: TArray<TTestCaseResult>;
begin
  Cases := TTestResults.Parse(Report).Cases;
  Assert.IsTrue(TAtlasTestRun.StatusOf(Cases, 'Rechner.Tests', 'TRechnerTests', 'Addiert') = TAtlasTestStatus.Passed);
  Assert.IsTrue(TAtlasTestRun.StatusOf(Cases, 'Rechner.Tests', 'TRechnerTests', 'Summe') = TAtlasTestStatus.Failed,
    'ein Fall fehlgeschlagen');
  Assert.IsTrue(TAtlasTestRun.StatusOf(Cases, 'Rechner.Tests', 'TRechnerTests', '') = TAtlasTestStatus.Failed,
    'Fixture mit Fehlschlag');
  Assert.IsTrue(TAtlasTestRun.StatusOf(Cases, 'Rechner.Tests', 'TRechnerTests', 'Neu') = TAtlasTestStatus.Unknown);
  Assert.IsTrue(TAtlasTestRun.StatusOf(Cases, 'Andere.Tests', 'TRechnerTests', 'Addiert') = TAtlasTestStatus.Unknown,
    'andere Unit');
  // Einzelner Fall (#585, Marke je [TestCase]).
  Assert.IsTrue(TAtlasTestRun.StatusOf(Cases, 'Rechner.Tests', 'TRechnerTests', 'Summe', 'Gross') =
    TAtlasTestStatus.Failed);
  Assert.IsTrue(TAtlasTestRun.StatusOf(Cases, 'Rechner.Tests', 'TRechnerTests', 'Summe', 'Mittel') =
    TAtlasTestStatus.Unknown, 'Fall nicht im Bericht');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTestRunTests);

end.
