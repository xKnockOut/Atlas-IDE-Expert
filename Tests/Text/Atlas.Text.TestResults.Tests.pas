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
  NUnit2 =
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
  Run: TTestRunResult;
  Failures: TArray<TTestCaseResult>;
begin
  Run := TTestResults.Parse(NUnit2);
  Assert.IsTrue(Run.Valid);
  Assert.AreEqual('nunit2', Run.Format);
  Assert.AreEqual(4, Run.Total);
  Assert.AreEqual(1, Run.Count(TTestOutcome.Passed));
  Assert.AreEqual(1, Run.Count(TTestOutcome.Failed));
  Assert.AreEqual(1, Run.Count(TTestOutcome.Error));
  Assert.AreEqual(1, Run.Count(TTestOutcome.Skipped));
  Assert.AreEqual(Int64(1250), Run.DurationMs, 'Dauer der äußersten Suite');
  Assert.IsFalse(Run.AllPassed);
  Failures := Run.Failures;
  Assert.AreEqual(2, Integer(Length(Failures)));
  Assert.AreEqual('Summe', Failures[0].Method);
  Assert.AreEqual('Gross', Failures[0].CaseName);
  Assert.AreEqual('Rechner.Tests.pas:35', Failures[0].StackTrace);
  Assert.AreEqual(Int64(20), Failures[0].DurationMs);
  Assert.AreEqual('EZeroDivide: Division durch <0>', Failures[1].Message);
  Assert.IsFalse(Failures[1].HasValues);
  Assert.AreEqual('später', Run.Cases[3].Message, 'Grund des Ignorierens');
end;

procedure TTestResultsTests.SplitsNamesWithDottedUnit;
var
  Run: TTestRunResult;
  UnitName, Fixture, Method, CaseName: string;
begin
  Run := TTestResults.Parse(NUnit2);
  Assert.AreEqual('Rechner.Tests', Run.Cases[0].UnitName, 'Unit mit Punkt über die Fixture der Suite');
  Assert.AreEqual('TRechnerTests', Run.Cases[0].Fixture);
  Assert.AreEqual('Addiert', Run.Cases[0].Method);
  Assert.AreEqual('', Run.Cases[0].CaseName);
  TTestResults.SplitName('A.B.TFix.M.Fall', 'tfix', UnitName, Fixture, Method, CaseName);
  Assert.AreEqual('A.B', UnitName);
  Assert.AreEqual('TFix', Fixture, 'Schreibweise aus dem Namen');
  Assert.AreEqual('M', Method);
  Assert.AreEqual('Fall', CaseName);
  TTestResults.SplitName('A.B.TFix.M', '', UnitName, Fixture, Method, CaseName);
  Assert.AreEqual('A.B', UnitName, 'ohne Fixture: die letzten beiden Teile');
  Assert.AreEqual('TFix', Fixture);
  Assert.AreEqual('M', Method);
  TTestResults.SplitName('Einzeln', '', UnitName, Fixture, Method, CaseName);
  Assert.AreEqual('Einzeln', Method);
end;

procedure TTestResultsTests.ReadsExpectedAndActual;
var
  Run: TTestRunResult;
  Expected, Actual: string;
begin
  Run := TTestResults.Parse(NUnit2);
  Assert.IsTrue(Run.Cases[1].HasValues);
  Assert.AreEqual('30', Run.Cases[1].Expected);
  Assert.AreEqual('31', Run.Cases[1].Actual);
  Assert.IsTrue(TTestResults.SplitValues('Expected "abc" but got "abd"', Expected, Actual));
  Assert.AreEqual('abc', Expected);
  Assert.AreEqual('abd', Actual);
  Assert.IsTrue(TTestResults.SplitValues('  Expected: 3'#13#10'  But was:  4'#13#10'at x', Expected, Actual));
  Assert.AreEqual('3', Expected);
  Assert.AreEqual('4', Actual);
  Assert.IsTrue(TTestResults.SplitValues('Expected <1> but got <2>', Expected, Actual));
  Assert.AreEqual('1', Expected);
  Assert.AreEqual('2', Actual);
  Assert.IsFalse(TTestResults.SplitValues('Condition is not True', Expected, Actual));
  Assert.AreEqual('', Expected);
end;

procedure TTestResultsTests.ReadsNUnit3Report;
var
  Run: TTestRunResult;
begin
  Run := TTestResults.Parse(
    '<test-run total="3" duration="0.5">' +
    '<test-suite type="TestFixture" name="TT" fullname="U.TT">' +
    '<test-case fullname="U.TT.A" name="A" result="Passed" duration="0.1"/>' +
    '<test-case fullname="U.TT.B" name="B" result="Failed" label="Error" duration="0.2">' +
      '<failure><message>Zugriffsverletzung</message></failure></test-case>' +
    '<test-case fullname="U.TT.C" name="C" result="Skipped"/>' +
    '</test-suite></test-run>');
  Assert.IsTrue(Run.Valid);
  Assert.AreEqual('nunit3', Run.Format);
  Assert.AreEqual(Int64(500), Run.DurationMs);
  Assert.IsTrue(Run.Cases[0].Outcome = TTestOutcome.Passed);
  Assert.IsTrue(Run.Cases[1].Outcome = TTestOutcome.Error);
  Assert.AreEqual('Zugriffsverletzung', Run.Cases[1].Message);
  Assert.AreEqual('U', Run.Cases[1].UnitName);
  Assert.IsTrue(Run.Cases[2].Outcome = TTestOutcome.Skipped);
end;

procedure TTestResultsTests.ReadsJUnitReport;
var
  Run: TTestRunResult;
begin
  Run := TTestResults.Parse(
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
  Assert.IsTrue(Run.Valid);
  Assert.AreEqual('junit', Run.Format);
  Assert.AreEqual(4, Run.Total);
  Assert.AreEqual(Int64(750), Run.DurationMs);
  Assert.AreEqual('Rechner.Tests', Run.Cases[1].UnitName);
  Assert.AreEqual('TRechnerTests', Run.Cases[1].Fixture);
  Assert.AreEqual('Summe', Run.Cases[1].Method);
  Assert.AreEqual('Klein', Run.Cases[1].CaseName);
  Assert.IsTrue(Run.Cases[1].Outcome = TTestOutcome.Failed);
  Assert.AreEqual('3', Run.Cases[1].Expected);
  Assert.AreEqual('4', Run.Cases[1].Actual);
  Assert.AreEqual('Aufrufliste', Run.Cases[1].StackTrace);
  Assert.IsTrue(Run.Cases[2].Outcome = TTestOutcome.Error);
  Assert.AreEqual('EZeroDivide', Run.Cases[2].Message, 'erste Zeile ohne Attribut');
  Assert.IsTrue(Run.Cases[3].Outcome = TTestOutcome.Skipped);
  Assert.AreEqual('später', Run.Cases[3].Message);
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
  Run: TTestRunResult;
begin
  Run := TTestResults.Parse('<html><body>kein Bericht</body></html>');
  Assert.IsFalse(Run.Valid);
  Assert.AreNotEqual('', Run.Error);
  Run := TTestResults.Parse('');
  Assert.IsFalse(Run.Valid);
  Run := TTestResults.Parse('<test-results total="0"></test-results>');
  Assert.IsTrue(Run.Valid, 'leerer Lauf ist ein Bericht');
  Assert.AreEqual(0, Run.Total);
  Assert.IsFalse(Run.AllPassed, 'ohne Tests nicht grün');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestResultsTests);

end.
