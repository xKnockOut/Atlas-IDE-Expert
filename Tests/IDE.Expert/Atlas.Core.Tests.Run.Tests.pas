unit Atlas.Core.Tests.Run.Tests;

// Tests des Testlaufs aus der IDE (#69) ohne IDE: Testprogramm und Plattform,
// Lauf nach dem Build (mit build.zeroHints #530), Zuordnung fehlgeschlagener
// Tests zur Testmethode, Probleme mit erwartetem und tatsächlichem Wert,
// Abschnitt "tests" der Projekt-Zusammenfassung und Stand für die Code Lens
// (veraltete Ergebnisse #1770).

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
    [Test]
    procedure StaleResultsAreNotCountedAsPassed;
    [Test]
    procedure FailureAtAssertWithShortText;
    [Test]
    procedure SummaryKeepsSlowestTests;
    [Test]
    procedure TallySumsDurations;
    [Test]
    procedure TallyAndProblemsOfLeaks;
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
  cUnitFile = 'C:\Projekt\Tests\Rechner.Tests.pas';
  cReport =
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
  mReads: Integer;
begin
  mReads := 0;
  Result := TAtlasTestRun.Failures(TTestResults.Parse(cReport),
    function(const AUnitName: string): string
    begin
      Result := '';
      if SameText(AUnitName, 'Rechner.Tests') then
      begin
        Result := cUnitFile;
      end;
    end,
    function(const AFileName: string; out ALines: TArray<string>): Boolean
    begin
      Inc(mReads);
      Result := SameText(AFileName, cUnitFile);
      if Result then
      begin
        ALines := Source;
      end
      else
      begin
        ALines := nil;
      end;
    end);
  AReads := mReads;
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
  mValue: TAtlasPluginSettings;
begin
  mValue := Settings;
  Assert.IsTrue(TAtlasTestRun.ShouldRunAfterBuild(mValue, True, False, '', True));
  Assert.IsFalse(TAtlasTestRun.ShouldRunAfterBuild(mValue, False, False, '', True), 'Build fehlgeschlagen');
  Assert.IsFalse(TAtlasTestRun.ShouldRunAfterBuild(mValue, True, True, '', True), 'Hintergrundprüfung');
  Assert.IsFalse(TAtlasTestRun.ShouldRunAfterBuild(mValue, True, False, TAtlasTestRun.cRequestedBy, True),
    'Build vor den Tests');
  Assert.IsFalse(TAtlasTestRun.ShouldRunAfterBuild(mValue, True, False, 'mcp', True), 'Build für Claude Code');
  Assert.IsFalse(TAtlasTestRun.ShouldRunAfterBuild(mValue, True, False, '', False), 'kein Testprogramm');
  mValue.TestsAfterBuild := False;
  Assert.IsFalse(TAtlasTestRun.ShouldRunAfterBuild(mValue, True, False, '', True), 'Vorgabe aus');
  mValue := Settings;
  mValue.TestRun := False;
  Assert.IsFalse(TAtlasTestRun.ShouldRunAfterBuild(mValue, True, False, '', True), 'Tests ausführen aus');
  mValue := Settings;
  mValue.Enabled := False;
  Assert.IsFalse(TAtlasTestRun.ShouldRunAfterBuild(mValue, True, False, '', True), 'Atlas aus');
end;

procedure TAtlasTestRunTests.ZeroHintsNeedsCleanBuild;
var
  mValue: TAtlasPluginSettings;
  mMessages: TArray<TAtlasCompilerMessage>;
  mVerdict: TAtlasBuildVerdict;
begin
  // Abnahme #530: Mit zeroHints gilt ein Build mit Hinweis als gescheitert, Tests nach dem Build starten nicht.
  SetLength(mMessages, 2);
  mMessages[0] := TAtlasCompilerMessages.FromIde('Hint', 'H2164 Variable X wurde deklariert, aber nicht verwendet',
    'C:\P\U.pas', 5, 3);
  mMessages[1] := TAtlasCompilerMessages.FromIde('Info', 'Erfolg', '', 0, 0);
  mValue := Settings;
  mValue.BuildZeroHints := True;
  mVerdict := TAtlasBuildVerdicts.Evaluate(mMessages, nil, True, TAtlasBuildVerdictSettings.Create(
    mValue.BuildZeroHints, mValue.BuildWarningsAsErrors));
  Assert.IsFalse(TAtlasTestRun.ShouldRunAfterBuild(mValue, mVerdict.Effective, False, '', True), 'mit Hinweisen nicht');
  // Derselbe Hinweis in der Basislinie zählt nicht.
  mVerdict := TAtlasBuildVerdicts.Evaluate(mMessages, TArray<Boolean>.Create(True, False), True,
    TAtlasBuildVerdictSettings.Create(mValue.BuildZeroHints, mValue.BuildWarningsAsErrors));
  Assert.IsTrue(TAtlasTestRun.ShouldRunAfterBuild(mValue, mVerdict.Effective, False, '', True), 'in der Basislinie');
  mValue.BuildZeroHints := False;
  mVerdict := TAtlasBuildVerdicts.Evaluate(mMessages, nil, True, TAtlasBuildVerdictSettings.Create(
    mValue.BuildZeroHints, mValue.BuildWarningsAsErrors));
  Assert.IsTrue(TAtlasTestRun.ShouldRunAfterBuild(mValue, mVerdict.Effective, False, '', True), 'ohne zeroHints');
end;

procedure TAtlasTestRunTests.FailureSitsOnTestMethod;
var
  mFound: TArray<TAtlasTestFailure>;
  mReads: Integer;
begin
  mFound := Failures(mReads);
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual(1, mReads, 'jede Testunit einmal lesen');
  Assert.AreEqual(cUnitFile, mFound[0].FileName);
  Assert.AreEqual(18, mFound[0].Line, 'Methodenkopf im implementation-Teil, nicht die Deklaration');
  Assert.AreEqual(2, mFound[0].StartCharacter, 'ab dem ersten Zeichen');
  Assert.AreEqual(Integer(Length('  procedure TRechnerTests.Summe(A, B, C: Integer);')), mFound[0].EndCharacter);
  Assert.AreEqual(21, mFound[1].Line);
end;

procedure TAtlasTestRunTests.ProblemsCarryExpectedAndActual;
var
  mFound: TArray<TAtlasTestFailure>;
  mReads: Integer;
  mItems: TArray<TPair<string, TAtlasProblem>>;
begin
  mFound := Failures(mReads);
  mItems := TAtlasTestRun.Problems(mFound, 'Test %s fehlgeschlagen: %s', 'Test %s fehlgeschlagen: erwartet %s, erhalten %s');
  Assert.AreEqual(2, Integer(Length(mItems)));
  Assert.AreEqual(cUnitFile, mItems[0].Key);
  Assert.AreEqual('Test TRechnerTests.Summe.Gross fehlgeschlagen: erwartet 30, erhalten 31', mItems[0].Value.Message);
  Assert.AreEqual(18, mItems[0].Value.StartLine);
  Assert.AreEqual(TAtlasProblemStore.cTestSource, mItems[0].Value.Source);
  Assert.IsTrue(mItems[0].Value.Severity = TAtlasProblemSeverity.Error);
  Assert.AreEqual('', mItems[0].Value.Code, 'kein Regeltreffer');
  Assert.AreEqual('Test TRechnerTests.Teilt fehlgeschlagen: EZeroDivide: Division durch 0', mItems[1].Value.Message,
    'nur die erste Zeile');
  // Ohne Fundstelle kein Problem.
  mFound[1].FileName := '';
  Assert.AreEqual(1, Integer(Length(TAtlasTestRun.Problems(mFound, '%s %s', '%s %s %s'))));
end;

procedure TAtlasTestRunTests.SummaryForWelcomePage;
var
  mTarget: TAtlasTestTarget;
  mFound: TArray<TAtlasTestFailure>;
  mReads: Integer;
  mTests: TAtlasProjectTests;
begin
  mTarget := Default(TAtlasTestTarget);
  mTarget.Project := 'C:\Projekt\Rechner.Tests.dproj';
  mTarget.Configuration := 'Debug';
  mTarget.Platform := 'Win64';
  mFound := Failures(mReads);
  mTests := TAtlasTestRun.SummaryOf(mTarget, TTestResults.Parse(cReport), mFound, EncodeDate(2026, 10, 16));
  Assert.IsTrue(mTests.Known);
  Assert.AreEqual('Win64', mTests.Platform);
  Assert.AreEqual(1, mTests.Passed);
  Assert.AreEqual(1, mTests.Failed);
  Assert.AreEqual(1, mTests.Errors);
  Assert.AreEqual(500, mTests.DurationMs);
  Assert.AreEqual(2, Integer(Length(mTests.Failures)));
  Assert.AreEqual('Rechner.Tests.TRechnerTests.Summe.Gross', mTests.Failures[0].Test, 'voller Name für --run');
  Assert.AreEqual(19, mTests.Failures[0].Line, '1-basiert');
  Assert.AreEqual(cUnitFile, mTests.Failures[0].FileName);
  Assert.AreEqual(2, Integer(Length(mTests.FailedTests)));
end;

procedure TAtlasTestRunTests.SummaryKeepsSlowestTests;
var
  mRun: TTestRunResult;
  mSlow: TArray<TAtlasTestFailure>;
  mTests: TAtlasProjectTests;
begin
  mRun := TTestResults.Parse(cReport);
  mSlow := TAtlasTestRun.Locate(TTestResults.Slowest(mRun.Cases, 10),
    function(const AUnitName: string): string
    begin
      Result := cUnitFile;
    end,
    function(const AFileName: string; out ALines: TArray<string>): Boolean
    begin
      ALines := Source;
      Result := True;
    end);
  Assert.AreEqual(3, Integer(Length(mSlow)));
  Assert.AreEqual('Rechner.Tests.TRechnerTests.Summe.Gross', mSlow[0].Test.FullName, 'langsamster zuerst');
  Assert.AreEqual(cUnitFile, mSlow[0].FileName);
  Assert.AreEqual(18, mSlow[0].Line, 'Methodenkopf, 0-basiert');
  mTests := TAtlasTestRun.SummaryOf(Default(TAtlasTestTarget), mRun, nil, mSlow, EncodeDate(2026, 11, 13));
  Assert.AreEqual(3, Integer(Length(mTests.Slowest)));
  Assert.AreEqual('Rechner.Tests.TRechnerTests.Summe.Gross', mTests.Slowest[0].Test);
  Assert.AreEqual(20, mTests.Slowest[0].DurationMs);
  Assert.AreEqual(19, mTests.Slowest[0].Line, '1-basiert');
  Assert.AreEqual(0, Integer(Length(TAtlasTestRun.SummaryOf(Default(TAtlasTestTarget), mRun, nil, 0).Slowest)),
    'ohne Liste keine langsamsten');
end;

procedure TAtlasTestRunTests.StatusForLens;
var
  mCases: TArray<TTestCaseResult>;
begin
  mCases := TTestResults.Parse(cReport).Cases;
  Assert.IsTrue(TAtlasTestRun.StatusOf(mCases, 'Rechner.Tests', 'TRechnerTests', 'Addiert') = TAtlasTestStatus.Passed);
  Assert.IsTrue(TAtlasTestRun.StatusOf(mCases, 'Rechner.Tests', 'TRechnerTests', 'Summe') = TAtlasTestStatus.Failed,
    'ein Fall fehlgeschlagen');
  Assert.IsTrue(TAtlasTestRun.StatusOf(mCases, 'Rechner.Tests', 'TRechnerTests', '') = TAtlasTestStatus.Failed,
    'Fixture mit Fehlschlag');
  Assert.IsTrue(TAtlasTestRun.StatusOf(mCases, 'Rechner.Tests', 'TRechnerTests', 'Neu') = TAtlasTestStatus.Unknown);
  Assert.IsTrue(TAtlasTestRun.StatusOf(mCases, 'Andere.Tests', 'TRechnerTests', 'Addiert') = TAtlasTestStatus.Unknown,
    'andere Unit');
  // Einzelner Fall (#585, Marke je [TestCase]).
  Assert.IsTrue(TAtlasTestRun.StatusOf(mCases, 'Rechner.Tests', 'TRechnerTests', 'Summe', 'Gross') =
    TAtlasTestStatus.Failed);
  Assert.IsTrue(TAtlasTestRun.StatusOf(mCases, 'Rechner.Tests', 'TRechnerTests', 'Summe', 'Mittel') =
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

procedure TAtlasTestRunTests.TallySumsDurations;
var
  mCases: TArray<TTestCaseResult>;
  mTally: TAtlasTestTally;
  mKey, mOther: TAtlasTestKey;
begin
  mCases := TTestResults.Parse(cReport).Cases;
  mKey := Default(TAtlasTestKey);
  mKey.Method := 'Addiert';
  mTally := TAtlasTestRun.TallyOf(mCases, 'Rechner.Tests', 'TRechnerTests', [mKey]);
  Assert.AreEqual(Int64(10), mTally.DurationMs);
  Assert.AreEqual(Int64(10), mTally.SlowestMs);
  // Klassenmarke: Summe; der langsamste Test ist die Methode mit Fällen (Summe ihrer Fälle).
  mOther := mKey;
  mOther.Method := 'Summe';
  mTally := TAtlasTestRun.TallyOf(mCases, 'Rechner.Tests', 'TRechnerTests', [mKey, mOther]);
  Assert.AreEqual(Int64(30), mTally.DurationMs);
  Assert.AreEqual(Int64(20), mTally.SlowestMs);
end;

procedure TAtlasTestRunTests.TallyAndProblemsOfLeaks;
var
  mCases: TArray<TTestCaseResult>;
  mTally: TAtlasTestTally;
  mKey: TAtlasTestKey;
  mLeak: TAtlasTestFailure;
  mItems: TArray<TPair<string, TAtlasProblem>>;
begin
  // Bestanden mit Leck (#1774): zählt als bestanden, Leaked und LeakBytes tragen das Leck.
  mCases := TTestResults.Parse(cReport).Cases;
  mCases[0].LeakBytes := 40;
  mKey := Default(TAtlasTestKey);
  mKey.Method := 'Addiert';
  mTally := TAtlasTestRun.TallyOf(mCases, 'Rechner.Tests', 'TRechnerTests', [mKey]);
  Assert.IsTrue(mTally.Status = TAtlasTestStatus.Passed);
  Assert.AreEqual(1, mTally.Leaked);
  Assert.AreEqual(Int64(40), mTally.LeakBytes);
  mLeak := Default(TAtlasTestFailure);
  mLeak.Test := mCases[0];
  mLeak.FileName := cUnitFile;
  mLeak.Line := 15;
  mItems := TAtlasTestRun.LeakProblems([mLeak], 'Leck in %s: %d Bytes');
  Assert.AreEqual(1, Integer(Length(mItems)));
  Assert.AreEqual('Leck in TRechnerTests.Addiert: 40 Bytes', mItems[0].Value.Message);
  Assert.IsTrue(mItems[0].Value.Severity = TAtlasProblemSeverity.Warning);
  Assert.AreEqual(TAtlasProblemStore.cTestSource, mItems[0].Value.Source);
  Assert.AreEqual(15, mItems[0].Value.StartLine);
  // Ohne Fundstelle keine Warnung.
  mLeak.Line := -1;
  Assert.AreEqual(0, Integer(Length(TAtlasTestRun.LeakProblems([mLeak], '%s %d'))));
end;

/// <summary>Veraltet ist das Ergebnis des Tests AMethod.</summary>
function StaleOnly(const AMethod: string): TAtlasTestStaleFunc;
var
  mMethod: string;
begin
  mMethod := AMethod;
  Result :=
    function(const AName: string): Boolean
    begin
      Result := SameText(AName, mMethod);
    end;
end;

procedure TAtlasTestRunTests.FailureAtAssertWithShortText;
const
  cAssertReport =
    '<test-results total="2">' +
    '<test-suite type="Namespace" name="Rechner"><results>' +
    '<test-suite type="TestFixture" name="TRechnerTests"><results>' +
    '<test-case name="Rechner.Tests.TRechnerTests.Addiert" executed="True" result="Failure" time="0.01">' +
      '<failure><message>Expected 4 but got 3</message></failure></test-case>' +
    '<test-case name="Rechner.Tests.TRechnerTests.Teilt" executed="True" result="Error" time="0.01">' +
      '<failure><message>EZeroDivide</message><stack-trace>' +
      '[004C1234] Rechner.Tests.TRechnerTests.Teilt (Line 15, "Rechner.Tests.pas" + 1) + $12' +
      '</stack-trace></failure></test-case>' +
    '</results></test-suite></results></test-suite></test-results>';
var
  mLines: TArray<string>;
  mFound: TArray<TAtlasTestFailure>;
  mItems: TArray<TPair<string, TAtlasProblem>>;
  mUnitFile: TAtlasTestUnitFile;
  mReadLines: TAtlasTestReadLines;
begin
  mLines := TArray<string>.Create('unit Rechner.Tests;', 'interface', 'uses DUnitX.TestFramework;', 'type',
    '  [TestFixture]', '  TRechnerTests = class', '    [Test]', '    procedure Addiert;', '    [Test]',
    '    procedure Teilt;', '  end;', 'implementation',                    // 9..11
    'procedure TRechnerTests.Teilt;', 'begin', '  Rechne(1, 0);', 'end;', // 12..15
    'procedure TRechnerTests.Addiert;', 'begin',                          // 16, 17
    '  Assert.AreEqual(2, Summe(1, 1));', '  Assert.AreEqual(4, Summe(2, 2)); // zweiter', 'end;', 'end.');
  mUnitFile :=
    function(const AUnitName: string): string
    begin
      Result := cUnitFile;
    end;
  mReadLines :=
    function(const AFileName: string; out ALines: TArray<string>): Boolean
    begin
      ALines := mLines;
      Result := True;
    end;
  mFound := TAtlasTestRun.Failures(TTestResults.Parse(cAssertReport), mUnitFile, mReadLines, True);
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual(19, mFound[0].Line, 'Assert mit erwartetem Wert 4');
  Assert.IsTrue(mFound[0].AtAssert);
  Assert.AreEqual(2, mFound[0].StartCharacter);
  Assert.AreEqual(Integer(Length('  Assert.AreEqual(4, Summe(2, 2));')), mFound[0].EndCharacter, 'ohne Kommentar');
  Assert.AreEqual(14, mFound[1].Line, 'Ausnahme: Zeile aus dem Stacktrace');
  mItems := TAtlasTestRun.Problems(mFound, '%s: %s', '%s: erwartet %s, erhalten %s', 'erwartet %s, erhalten %s');
  Assert.AreEqual('erwartet 4, erhalten 3', mItems[0].Value.Details, 'kurzer Text');
  Assert.AreEqual('', mItems[1].Value.Details, 'ohne Werte kein kurzer Text');
  Assert.AreEqual('', TAtlasTestRun.Problems(mFound, '%s: %s', '%s: erwartet %s, erhalten %s')[0].Value.Details,
    'tests.failureInline aus');
  mFound := TAtlasTestRun.Failures(TTestResults.Parse(cAssertReport), mUnitFile, mReadLines, False);
  Assert.AreEqual(16, mFound[0].Line, 'tests.failureAtAssert aus: Methodenkopf');
  Assert.IsFalse(mFound[0].AtAssert);
  mLines := nil;
end;

procedure TAtlasTestRunTests.StaleResultsAreNotCountedAsPassed;
var
  mCases: TArray<TTestCaseResult>;
  mTally: TAtlasTestTally;
begin
  mCases := WelcomeCases(['IsReported=Success', 'Lookup.Kurz=Success', 'Lookup.Lang=Success',
    'NothingAfterFree=Success']);
  // Fixture: vier bestanden, einer davon seit dem Lauf geändert (#1770).
  mTally := TAtlasTestRun.TallyOf(mCases, 'Welcome.Tests', 'TNameTests',
    TAtlasTestRun.Expected(WelcomeSource, 0, -1, -1), StaleOnly('IsReported'));
  Assert.IsTrue(mTally.IsStale);
  Assert.AreEqual(1, mTally.Stale);
  Assert.AreEqual(4, mTally.Passed, 'Stand des Laufs');
  Assert.AreEqual(3, mTally.FreshPassed, 'die Zählung nimmt den veralteten nicht als bestanden');
  Assert.IsTrue(mTally.Status = TAtlasTestStatus.Passed, 'alter Stand');
  Assert.IsTrue(mTally.Shown = TAtlasTestStatus.Partial, 'die Marke zeigt 3/4');
  // Der veraltete Test selbst: alter Stand „bestanden“ mit Zusatz.
  mTally := TAtlasTestRun.TallyOf(mCases, 'Welcome.Tests', 'TNameTests',
    TAtlasTestRun.Expected(WelcomeSource, 0, 0, -1), StaleOnly('IsReported'));
  Assert.IsTrue(mTally.IsStale);
  Assert.IsTrue(mTally.Shown = TAtlasTestStatus.Passed);
  // Ein anderer Test ist nicht betroffen.
  mTally := TAtlasTestRun.TallyOf(mCases, 'Welcome.Tests', 'TNameTests',
    TAtlasTestRun.Expected(WelcomeSource, 0, 3, -1), StaleOnly('IsReported'));
  Assert.IsFalse(mTally.IsStale);
  // Veralteter Fehlschlag bleibt Fehlschlag (alter Stand), ist aber veraltet.
  mCases := WelcomeCases(['IsReported=Failure']);
  mTally := TAtlasTestRun.TallyOf(mCases, 'Welcome.Tests', 'TNameTests',
    TAtlasTestRun.Expected(WelcomeSource, 0, 0, -1), StaleOnly('IsReported'));
  Assert.IsTrue(mTally.Shown = TAtlasTestStatus.Failed);
  Assert.IsTrue(mTally.IsStale);
  // Schlüssel aus TAtlasTestStamps.StaleIn als Abfrage für die Marke.
  mTally := TAtlasTestRun.TallyOf(mCases, 'Welcome.Tests', 'TNameTests',
    TAtlasTestRun.Expected(WelcomeSource, 0, 0, -1), TAtlasTestRun.StaleOf(['welcome.tests.tnametests.isreported'],
    'Welcome.Tests', 'TNameTests'));
  Assert.IsTrue(mTally.IsStale, 'StaleOf');
  Assert.IsFalse(Assigned(TAtlasTestRun.StaleOf(nil, 'Welcome.Tests', 'TNameTests')), 'ohne veraltete Tests nil');
  // Ohne Angabe (tests.stale aus): wie bisher.
  mTally := TAtlasTestRun.TallyOf(mCases, 'Welcome.Tests', 'TNameTests',
    TAtlasTestRun.Expected(WelcomeSource, 0, 0, -1), nil);
  Assert.IsFalse(mTally.IsStale);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTestRunTests);

end.
