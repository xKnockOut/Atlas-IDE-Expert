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
  [Category('Atlas.IDE.Tests')]
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
    [Test]
    procedure ExpectedTestsOfMarks;
    [Test]
    procedure FixtureNotPassedAfterSingleTest;
    [Test]
    procedure FixturePassedWhenAllRan;
    [Test]
    procedure CasesOfMethodCountSeparately;
    [Test]
    procedure TallyStatus;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Store,
  Atlas.Core.Build.Messages,
  Atlas.Core.Build.Verdict,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Tests.Run,
  Atlas.Text.DUnitX,
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
      begin
        Result := UnitFile;
      end;
    end,
    function(const AFileName: string; out ALines: TArray<string>): Boolean
    begin
      Inc(Reads);
      Result := SameText(AFileName, UnitFile);
      if Result then
      begin
        ALines := Source;
      end
      else
      begin
        ALines := nil;
      end;
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
  Assert.IsTrue(TAtlasTestRun.ShouldRunAfterBuild(Value, True, False, '', True));
  Assert.IsFalse(TAtlasTestRun.ShouldRunAfterBuild(Value, False, False, '', True), 'Build fehlgeschlagen');
  Assert.IsFalse(TAtlasTestRun.ShouldRunAfterBuild(Value, True, True, '', True), 'Hintergrundprüfung');
  Assert.IsFalse(TAtlasTestRun.ShouldRunAfterBuild(Value, True, False, TAtlasTestRun.RequestedBy, True),
    'Build vor den Tests');
  Assert.IsFalse(TAtlasTestRun.ShouldRunAfterBuild(Value, True, False, 'mcp', True), 'Build für Claude Code');
  Assert.IsFalse(TAtlasTestRun.ShouldRunAfterBuild(Value, True, False, '', False), 'kein Testprogramm');
  Value.TestsAfterBuild := False;
  Assert.IsFalse(TAtlasTestRun.ShouldRunAfterBuild(Value, True, False, '', True), 'Vorgabe aus');
  Value := Settings;
  Value.TestRun := False;
  Assert.IsFalse(TAtlasTestRun.ShouldRunAfterBuild(Value, True, False, '', True), 'Tests ausführen aus');
  Value := Settings;
  Value.Enabled := False;
  Assert.IsFalse(TAtlasTestRun.ShouldRunAfterBuild(Value, True, False, '', True), 'Atlas aus');
end;

procedure TAtlasTestRunTests.ZeroHintsNeedsCleanBuild;
var
  Value: TAtlasPluginSettings;
  Messages: TArray<TAtlasCompilerMessage>;
  Verdict: TAtlasBuildVerdict;
begin
  // Abnahme #530: Mit zeroHints gilt ein Build mit Hinweis als gescheitert, Tests nach dem Build starten nicht.
  SetLength(Messages, 2);
  Messages[0] := TAtlasCompilerMessages.FromIde('Hint', 'H2164 Variable X wurde deklariert, aber nicht verwendet',
    'C:\P\U.pas', 5, 3);
  Messages[1] := TAtlasCompilerMessages.FromIde('Info', 'Erfolg', '', 0, 0);
  Value := Settings;
  Value.BuildZeroHints := True;
  Verdict := TAtlasBuildVerdicts.Evaluate(Messages, nil, True, TAtlasBuildVerdictSettings.Create(
    Value.BuildZeroHints, Value.BuildWarningsAsErrors));
  Assert.IsFalse(TAtlasTestRun.ShouldRunAfterBuild(Value, Verdict.Effective, False, '', True), 'mit Hinweisen nicht');
  // Derselbe Hinweis in der Basislinie zählt nicht.
  Verdict := TAtlasBuildVerdicts.Evaluate(Messages, TArray<Boolean>.Create(True, False), True,
    TAtlasBuildVerdictSettings.Create(Value.BuildZeroHints, Value.BuildWarningsAsErrors));
  Assert.IsTrue(TAtlasTestRun.ShouldRunAfterBuild(Value, Verdict.Effective, False, '', True), 'in der Basislinie');
  Value.BuildZeroHints := False;
  Verdict := TAtlasBuildVerdicts.Evaluate(Messages, nil, True, TAtlasBuildVerdictSettings.Create(
    Value.BuildZeroHints, Value.BuildWarningsAsErrors));
  Assert.IsTrue(TAtlasTestRun.ShouldRunAfterBuild(Value, Verdict.Effective, False, '', True), 'ohne zeroHints');
end;

procedure TAtlasTestRunTests.FailureSitsOnTestMethod;
var
  Found: TArray<TAtlasTestFailure>;
  Reads: Integer;
begin
  Found := Failures(Reads);
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual(1, Reads, 'jede Testunit einmal lesen');
  Assert.AreEqual(UnitFile, Found[0].FileName);
  Assert.AreEqual(18, Found[0].Line, 'Methodenkopf im implementation-Teil, nicht die Deklaration');
  Assert.AreEqual(2, Found[0].StartCharacter, 'ab dem ersten Zeichen');
  Assert.AreEqual(Integer(Length('  procedure TRechnerTests.Summe(A, B, C: Integer);')), Found[0].EndCharacter);
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
  Assert.AreEqual(2, Integer(Length(Items)));
  Assert.AreEqual(UnitFile, Items[0].Key);
  Assert.AreEqual('Test TRechnerTests.Summe.Gross fehlgeschlagen: erwartet 30, erhalten 31', Items[0].Value.Message);
  Assert.AreEqual(18, Items[0].Value.StartLine);
  Assert.AreEqual(TAtlasProblemStore.cTestSource, Items[0].Value.Source);
  Assert.IsTrue(Items[0].Value.Severity = TAtlasProblemSeverity.Error);
  Assert.AreEqual('', Items[0].Value.Code, 'kein Regeltreffer');
  Assert.AreEqual('Test TRechnerTests.Teilt fehlgeschlagen: EZeroDivide: Division durch 0', Items[1].Value.Message,
    'nur die erste Zeile');
  // Ohne Fundstelle kein Problem.
  Found[1].FileName := '';
  Assert.AreEqual(1, Integer(Length(TAtlasTestRun.Problems(Found, '%s %s', '%s %s %s'))));
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
  Assert.AreEqual(2, Integer(Length(Tests.Failures)));
  Assert.AreEqual('Rechner.Tests.TRechnerTests.Summe.Gross', Tests.Failures[0].Test, 'voller Name für --run');
  Assert.AreEqual(19, Tests.Failures[0].Line, '1-basiert');
  Assert.AreEqual(UnitFile, Tests.Failures[0].FileName);
  Assert.AreEqual(2, Integer(Length(Tests.FailedTests)));
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

/// <summary>Fixture mit vier Tests (einer mit zwei Fällen, einer mit [Ignore]) wie im Bild von Marco.</summary>
function WelcomeSource: TDUnitXUnit;
begin
  Result := TDUnitXSource.Scan(TArray<string>.Create(
    'unit Welcome.Tests;',
    'interface',
    'uses DUnitX.TestFramework;',
    'type',
    '  [TestFixture]',
    '  TNameTests = class',
    '  public',
    '    [Test]',
    '    procedure IsReported;',
    '    [TestCase(''Kurz'', ''a'')]',
    '    [TestCase(''Lang'', ''abc'')]',
    '    procedure Lookup(const A: string);',
    '    [Test]',
    '    [Ignore(''später'')]',
    '    procedure Spaeter;',
    '    [Test]',
    '    procedure NothingAfterFree;',
    '  end;',
    'implementation',
    'end.'));
end;

/// <summary>Bericht mit den Ergebnissen AResults (Name=Success|Failure|Ignored) der Fixture TNameTests.</summary>
function WelcomeCases(const AResults: array of string): TArray<TTestCaseResult>;
var
  mXml: string;
  mResult: string;
  mParts: TArray<string>;
begin
  mXml := '<test-results><test-suite type="Assembly" name="W.exe"><results>' +
    '<test-suite type="TestFixture" name="TNameTests"><results>';
  for mResult in AResults do
  begin
    mParts := mResult.Split(['=']);
    mXml := mXml + '<test-case name="Welcome.Tests.TNameTests.' + mParts[0] + '" executed="True" result="' +
      mParts[1] + '" time="0.01"/>';
  end;
  mXml := mXml + '</results></test-suite></results></test-suite></test-results>';
  Result := TTestResults.Parse(mXml).Cases;
end;

/// <summary>Stand der Marke Fixture/Test/Fall von WelcomeSource nach den Ergebnissen AResults.</summary>
function WelcomeTally(const AResults: array of string; ATest, ACase: Integer): TAtlasTestTally;
begin
  Result := TAtlasTestRun.TallyOf(WelcomeCases(AResults), 'Welcome.Tests', 'TNameTests',
    TAtlasTestRun.Expected(WelcomeSource, 0, ATest, ACase));
end;

procedure TAtlasTestRunTests.ExpectedTestsOfMarks;
var
  mKeys: TArray<TAtlasTestKey>;
begin
  mKeys := TAtlasTestRun.Expected(WelcomeSource, 0, -1, -1);
  Assert.AreEqual(4, Integer(Length(mKeys)), 'Fixture: IsReported, zwei Fälle, NothingAfterFree; [Ignore] nicht');
  Assert.AreEqual('IsReported', mKeys[0].Method);
  Assert.AreEqual('', mKeys[0].CaseName);
  Assert.AreEqual('Lookup', mKeys[1].Method);
  Assert.AreEqual('Kurz', mKeys[1].CaseName);
  Assert.AreEqual('Lang', mKeys[2].CaseName);
  Assert.AreEqual('NothingAfterFree', mKeys[3].Method);
  mKeys := TAtlasTestRun.Expected(WelcomeSource, 0, 1, -1);
  Assert.AreEqual(2, Integer(Length(mKeys)), 'Methode mit Fällen: alle Fälle');
  mKeys := TAtlasTestRun.Expected(WelcomeSource, 0, 1, 1);
  Assert.AreEqual(1, Integer(Length(mKeys)), 'ein Fall');
  Assert.AreEqual('Lang', mKeys[0].CaseName);
  Assert.AreEqual(0, Integer(Length(TAtlasTestRun.Expected(WelcomeSource, 0, 2, -1))), '[Ignore]');
  Assert.AreEqual(0, Integer(Length(TAtlasTestRun.Expected(WelcomeSource, 1, -1, -1))), 'keine Fixture');
end;

procedure TAtlasTestRunTests.FixtureNotPassedAfterSingleTest;
var
  mTally: TAtlasTestTally;
begin
  mTally := WelcomeTally(['NothingAfterFree=Success'], -1, -1);
  Assert.IsTrue(mTally.Status = TAtlasTestStatus.Partial, 'nur ein Test gelaufen');
  Assert.AreEqual(1, mTally.Passed);
  Assert.AreEqual(4, mTally.Total);
  Assert.IsTrue(WelcomeTally(['NothingAfterFree=Success'], 3, -1).Status = TAtlasTestStatus.Passed,
    'der gelaufene Test selbst');
  Assert.IsTrue(WelcomeTally(['NothingAfterFree=Success'], 0, -1).Status = TAtlasTestStatus.Unknown,
    'nicht gelaufener Test');
  Assert.IsTrue(WelcomeTally(['NothingAfterFree=Failure'], -1, -1).Status = TAtlasTestStatus.Failed,
    'ein Fehlschlag gilt für die Fixture sofort');
end;

procedure TAtlasTestRunTests.FixturePassedWhenAllRan;
var
  mTally: TAtlasTestTally;
begin
  mTally := WelcomeTally(['IsReported=Success', 'Lookup.Kurz=Success', 'Lookup.Lang=Success',
    'Spaeter=Ignored', 'NothingAfterFree=Success'], -1, -1);
  Assert.IsTrue(mTally.Status = TAtlasTestStatus.Passed);
  Assert.AreEqual(4, mTally.Passed);
end;

procedure TAtlasTestRunTests.CasesOfMethodCountSeparately;
begin
  Assert.IsTrue(WelcomeTally(['Lookup.Kurz=Success'], 1, -1).Status = TAtlasTestStatus.Partial,
    'ein Fall von zwei');
  Assert.IsTrue(WelcomeTally(['Lookup.Kurz=Success'], 1, 0).Status = TAtlasTestStatus.Passed, 'der Fall selbst');
  Assert.IsTrue(WelcomeTally(['Lookup.Kurz=Success'], 1, 1).Status = TAtlasTestStatus.Unknown, 'anderer Fall');
  Assert.IsTrue(WelcomeTally(['Lookup.Kurz=Success', 'Lookup.Lang=Success'], 1, -1).Status =
    TAtlasTestStatus.Passed);
end;

procedure TAtlasTestRunTests.TallyStatus;
var
  mTally: TAtlasTestTally;
begin
  mTally := Default(TAtlasTestTally);
  Assert.IsTrue(mTally.Status = TAtlasTestStatus.Unknown, 'ohne Tests');
  mTally.Total := 2;
  mTally.Ran := 2;
  Assert.IsTrue(mTally.Status = TAtlasTestStatus.Unknown, 'alle übersprungen');
  mTally.Passed := 1;
  Assert.IsTrue(mTally.Status = TAtlasTestStatus.Passed, 'einer bestanden, einer übersprungen');
  mTally.Ran := 1;
  Assert.IsTrue(mTally.Status = TAtlasTestStatus.Partial);
  mTally.Failed := 1;
  Assert.IsTrue(mTally.Status = TAtlasTestStatus.Failed);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTestRunTests);

end.
