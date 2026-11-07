unit Atlas.Text.TestResults.Tests;

// Tests des Lesens von DUnitX-Berichten (#69): NUnit 2 (Logger der Vorlage
// von RAD Studio) mit Namensräumen, Fixtures, Testfällen, Fehlschlag, Fehler
// und Ignoriert; NUnit 3; JUnit; erwarteter und tatsächlicher Wert; Zeiten mit
// Komma; kein Bericht.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestResultsTests = class
  public
    [Test]
    procedure ReadsNUnit2Report;
    [Test]
    procedure SplitsNamesWithDottedUnit;
    [Test]
    procedure ReadsExpectedAndActual;
    [Test]
    procedure ReadsNUnit3Report;
    [Test]
    procedure ReadsJUnitReport;
    [Test]
    procedure CommaSecondsAndInvalid;
    [Test]
    procedure NotAReport;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.TestResults;

const
  cNUnit2 =
    '<?xml version="1.0" encoding="UTF-8"?>'#13#10 +
    '<test-results name="Rechner.Tests.exe" total="4" errors="1" failures="1" ignored="1" date="2026-10-16" ' +
      'time="10:00:00">'#13#10 +
    '  <environment nunit-version="DUnitX"/>'#13#10 +
    '  <test-suite type="Assembly" name="Rechner.Tests.exe" executed="true" result="Failure" time="1.250">'#13#10 +
    '    <results>'#13#10 +
    '      <test-suite type="Namespace" name="Rechner" executed="true" result="Failure" time="1.2">'#13#10 +
    '        <results>'#13#10 +
    '          <test-suite type="TestFixture" name="TRechnerTests" executed="true" result="Failure" time="1.2">'#13#10 +
    '            <results>'#13#10 +
    '              <test-case name="Rechner.Tests.TRechnerTests.Addiert" executed="True" result="Success" ' +
                     'success="True" time="0.010" asserts="1"/>'#13#10 +
    '              <test-case name="Rechner.Tests.TRechnerTests.Summe.Gross" executed="True" result="Failure" ' +
                     'success="False" time="0.020">'#13#10 +
    '                <failure>'#13#10 +
    '                  <message><![CDATA[Expected 30 but got 31 ]]></message>'#13#10 +
    '                  <stack-trace><![CDATA[Rechner.Tests.pas:35]]></stack-trace>'#13#10 +
    '                </failure>'#13#10 +
    '              </test-case>'#13#10 +
    '              <test-case name="Rechner.Tests.TRechnerTests.Teilt" executed="True" result="Error" ' +
                     'success="False" time="0.005">'#13#10 +
    '                <failure><message>EZeroDivide: Division durch &lt;0&gt;</message></failure>'#13#10 +
    '              </test-case>'#13#10 +
    '              <test-case name="Rechner.Tests.TRechnerTests.Spaeter" executed="False" result="Ignored">'#13#10 +
    '                <reason><message>später</message></reason>'#13#10 +
    '              </test-case>'#13#10 +
    '            </results>'#13#10 +
    '          </test-suite>'#13#10 +
    '        </results>'#13#10 +
    '      </test-suite>'#13#10 +
    '    </results>'#13#10 +
    '  </test-suite>'#13#10 +
    '</test-results>';

{ TTestResultsTests }

procedure TTestResultsTests.ReadsNUnit2Report;
var
  mRun: TTestRunResult;
  mFailures: TArray<TTestCaseResult>;
begin
  mRun := TTestResults.Parse(cNUnit2);
  Assert.IsTrue(mRun.Valid);
  Assert.AreEqual('nunit2', mRun.Format);
  Assert.AreEqual(4, mRun.Total);
  Assert.AreEqual(1, mRun.Count(TTestOutcome.Passed));
  Assert.AreEqual(1, mRun.Count(TTestOutcome.Failed));
  Assert.AreEqual(1, mRun.Count(TTestOutcome.Error));
  Assert.AreEqual(1, mRun.Count(TTestOutcome.Skipped));
  Assert.AreEqual(Int64(1250), mRun.DurationMs, 'Dauer der äußersten Suite');
  Assert.IsFalse(mRun.AllPassed);
  mFailures := mRun.Failures;
  Assert.AreEqual(2, Integer(Length(mFailures)));
  Assert.AreEqual('Summe', mFailures[0].Method);
  Assert.AreEqual('Gross', mFailures[0].CaseName);
  Assert.AreEqual('Rechner.Tests.pas:35', mFailures[0].StackTrace);
  Assert.AreEqual(Int64(20), mFailures[0].DurationMs);
  Assert.AreEqual('EZeroDivide: Division durch <0>', mFailures[1].Message);
  Assert.IsFalse(mFailures[1].HasValues);
  Assert.AreEqual('später', mRun.Cases[3].Message, 'Grund des Ignorierens');
end;

procedure TTestResultsTests.SplitsNamesWithDottedUnit;
var
  mRun: TTestRunResult;
  mUnitName, mFixture, mMethod, mCaseName: string;
begin
  mRun := TTestResults.Parse(cNUnit2);
  Assert.AreEqual('Rechner.Tests', mRun.Cases[0].UnitName, 'Unit mit Punkt über die Fixture der Suite');
  Assert.AreEqual('TRechnerTests', mRun.Cases[0].Fixture);
  Assert.AreEqual('Addiert', mRun.Cases[0].Method);
  Assert.AreEqual('', mRun.Cases[0].CaseName);
  TTestResults.SplitName('A.B.TFix.M.Fall', 'tfix', mUnitName, mFixture, mMethod, mCaseName);
  Assert.AreEqual('A.B', mUnitName);
  Assert.AreEqual('TFix', mFixture, 'Schreibweise aus dem Namen');
  Assert.AreEqual('M', mMethod);
  Assert.AreEqual('Fall', mCaseName);
  TTestResults.SplitName('A.B.TFix.M', '', mUnitName, mFixture, mMethod, mCaseName);
  Assert.AreEqual('A.B', mUnitName, 'ohne Fixture: die letzten beiden Teile');
  Assert.AreEqual('TFix', mFixture);
  Assert.AreEqual('M', mMethod);
  TTestResults.SplitName('Einzeln', '', mUnitName, mFixture, mMethod, mCaseName);
  Assert.AreEqual('Einzeln', mMethod);
end;

procedure TTestResultsTests.ReadsExpectedAndActual;
var
  mRun: TTestRunResult;
  mExpected, mActual: string;
begin
  mRun := TTestResults.Parse(cNUnit2);
  Assert.IsTrue(mRun.Cases[1].HasValues);
  Assert.AreEqual('30', mRun.Cases[1].Expected);
  Assert.AreEqual('31', mRun.Cases[1].Actual);
  Assert.IsTrue(TTestResults.SplitValues('Expected "abc" but got "abd"', mExpected, mActual));
  Assert.AreEqual('abc', mExpected);
  Assert.AreEqual('abd', mActual);
  Assert.IsTrue(TTestResults.SplitValues('  Expected: 3'#13#10'  But was:  4'#13#10'at x', mExpected, mActual));
  Assert.AreEqual('3', mExpected);
  Assert.AreEqual('4', mActual);
  Assert.IsTrue(TTestResults.SplitValues('Expected <1> but got <2>', mExpected, mActual));
  Assert.AreEqual('1', mExpected);
  Assert.AreEqual('2', mActual);
  Assert.IsFalse(TTestResults.SplitValues('Condition is not True', mExpected, mActual));
  Assert.AreEqual('', mExpected);
end;

procedure TTestResultsTests.ReadsNUnit3Report;
var
  mRun: TTestRunResult;
begin
  mRun := TTestResults.Parse(
    '<test-run total="3" duration="0.5">' +
    '<test-suite type="TestFixture" name="TT" fullname="U.TT">' +
    '<test-case fullname="U.TT.A" name="A" result="Passed" duration="0.1"/>' +
    '<test-case fullname="U.TT.B" name="B" result="Failed" label="Error" duration="0.2">' +
      '<failure><message>Zugriffsverletzung</message></failure></test-case>' +
    '<test-case fullname="U.TT.C" name="C" result="Skipped"/>' +
    '</test-suite></test-run>');
  Assert.IsTrue(mRun.Valid);
  Assert.AreEqual('nunit3', mRun.Format);
  Assert.AreEqual(Int64(500), mRun.DurationMs);
  Assert.IsTrue(mRun.Cases[0].Outcome = TTestOutcome.Passed);
  Assert.IsTrue(mRun.Cases[1].Outcome = TTestOutcome.Error);
  Assert.AreEqual('Zugriffsverletzung', mRun.Cases[1].Message);
  Assert.AreEqual('U', mRun.Cases[1].UnitName);
  Assert.IsTrue(mRun.Cases[2].Outcome = TTestOutcome.Skipped);
end;

procedure TTestResultsTests.ReadsJUnitReport;
var
  mRun: TTestRunResult;
begin
  mRun := TTestResults.Parse(
    '<?xml version="1.0"?>' +
    '<testsuites time="0,75">' +
    '<testsuite name="Rechner.Tests.TRechnerTests" tests="4">' +
    '<testcase classname="Rechner.Tests.TRechnerTests" name="Addiert" time="0.25"/>' +
    '<testcase classname="Rechner.Tests.TRechnerTests" name="Summe.Klein" time="0.25">' +
      '<failure message="Expected 3 but got 4" type="ETestFailure">Aufrufliste</failure></testcase>' +
    '<testcase classname="Rechner.Tests.TRechnerTests" name="Teilt"><error>EZeroDivide' + #10 +
      'bei Zeile 7</error></testcase>' +
    '<testcase classname="Rechner.Tests.TRechnerTests" name="Spaeter"><skipped message="später"/></testcase>' +
    '</testsuite></testsuites>');
  Assert.IsTrue(mRun.Valid);
  Assert.AreEqual('junit', mRun.Format);
  Assert.AreEqual(4, mRun.Total);
  Assert.AreEqual(Int64(750), mRun.DurationMs);
  Assert.AreEqual('Rechner.Tests', mRun.Cases[1].UnitName);
  Assert.AreEqual('TRechnerTests', mRun.Cases[1].Fixture);
  Assert.AreEqual('Summe', mRun.Cases[1].Method);
  Assert.AreEqual('Klein', mRun.Cases[1].CaseName);
  Assert.IsTrue(mRun.Cases[1].Outcome = TTestOutcome.Failed);
  Assert.AreEqual('3', mRun.Cases[1].Expected);
  Assert.AreEqual('4', mRun.Cases[1].Actual);
  Assert.AreEqual('Aufrufliste', mRun.Cases[1].StackTrace);
  Assert.IsTrue(mRun.Cases[2].Outcome = TTestOutcome.Error);
  Assert.AreEqual('EZeroDivide', mRun.Cases[2].Message, 'erste Zeile ohne Attribut');
  Assert.IsTrue(mRun.Cases[3].Outcome = TTestOutcome.Skipped);
  Assert.AreEqual('später', mRun.Cases[3].Message);
end;

procedure TTestResultsTests.CommaSecondsAndInvalid;
begin
  Assert.AreEqual(Int64(12), TTestResults.SecondsToMs('0,012'));
  Assert.AreEqual(Int64(1500), TTestResults.SecondsToMs(' 1.5 '));
  Assert.AreEqual(Int64(0), TTestResults.SecondsToMs('x'));
  Assert.AreEqual(Int64(0), TTestResults.SecondsToMs('-1'));
end;

procedure TTestResultsTests.NotAReport;
var
  mRun: TTestRunResult;
begin
  mRun := TTestResults.Parse('<html><body>kein Bericht</body></html>');
  Assert.IsFalse(mRun.Valid);
  Assert.AreNotEqual('', mRun.Error);
  mRun := TTestResults.Parse('');
  Assert.IsFalse(mRun.Valid);
  mRun := TTestResults.Parse('<test-results total="0"></test-results>');
  Assert.IsTrue(mRun.Valid, 'leerer Lauf ist ein Bericht');
  Assert.AreEqual(0, mRun.Total);
  Assert.IsFalse(mRun.AllPassed, 'ohne Tests nicht grün');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestResultsTests);

end.
