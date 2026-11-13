unit Atlas.Core.Tests.Leaks.Tests;

// Tests der Lecks je Test (#1774): Ein Test, der nur wegen eines Lecks
// fehlschlug, gilt mit tests.leaks als bestanden mit Leck; ohne bleibt der
// Fehlschlag; gewöhnliche Fehlschläge bleiben immer.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasTestLeaksTests = class
  public
    [Test]
    procedure LeakOnlyFailurePassesWithLeak;
    [Test]
    procedure WithoutSettingTheReportStays;
    [Test]
    procedure LeakedListsPassedTestsWithLeak;
  end;

implementation

uses
  Atlas.Text.TestResults,
  Atlas.Core.Tests.Leaks;

const
  cReport =
    '<test-results total="3" failures="2">' +
    '<test-suite type="TestFixture" name="TKontoTests"><results>' +
    '<test-case name="Konto.Tests.TKontoTests.Bucht" executed="True" result="Failure" success="False" ' +
      'time="0.001"><failure><message><![CDATA[ 40 bytes were leaked in the test method ]]></message>' +
      '</failure></test-case>' +
    '<test-case name="Konto.Tests.TKontoTests.Rechnet" executed="True" result="Failure" success="False" ' +
      'time="0.001"><failure><message><![CDATA[Expected 3 but got 4]]></message></failure></test-case>' +
    '<test-case name="Konto.Tests.TKontoTests.Leert" executed="True" result="Success" success="True" ' +
      'time="0.001"/>' +
    '</results></test-suite></test-results>';

{ TAtlasTestLeaksTests }

procedure TAtlasTestLeaksTests.LeakOnlyFailurePassesWithLeak;
var
  mReport, mRun: TTestRunResult;
begin
  mReport := TTestResults.Parse(cReport);
  mRun := TAtlasTestLeaks.Shown(mReport, True);
  Assert.IsTrue(mRun.Cases[0].Outcome = TTestOutcome.Passed, 'nur Leck: bestanden');
  Assert.AreEqual(Int64(40), mRun.Cases[0].LeakBytes);
  Assert.IsTrue(mRun.Cases[1].Outcome = TTestOutcome.Failed, 'gewöhnlicher Fehlschlag bleibt');
  Assert.AreEqual(2, mRun.Count(TTestOutcome.Passed));
  Assert.IsTrue(mReport.Cases[0].Outcome = TTestOutcome.Failed, 'der gelesene Bericht bleibt unverändert');
end;

procedure TAtlasTestLeaksTests.WithoutSettingTheReportStays;
var
  mRun: TTestRunResult;
begin
  mRun := TAtlasTestLeaks.Shown(TTestResults.Parse(cReport), False);
  Assert.IsTrue(mRun.Cases[0].Outcome = TTestOutcome.Failed);
  Assert.AreEqual(0, Integer(Length(TAtlasTestLeaks.Leaked(mRun.Cases))), 'kein Leck ohne tests.leaks');
end;

procedure TAtlasTestLeaksTests.LeakedListsPassedTestsWithLeak;
var
  mLeaked: TArray<TTestCaseResult>;
begin
  mLeaked := TAtlasTestLeaks.Leaked(TAtlasTestLeaks.Shown(TTestResults.Parse(cReport), True).Cases);
  Assert.AreEqual(1, Integer(Length(mLeaked)));
  Assert.AreEqual('Bucht', mLeaked[0].Method);
  Assert.AreEqual(Int64(40), TAtlasTestLeaks.TotalBytes(mLeaked));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTestLeaksTests);

end.
