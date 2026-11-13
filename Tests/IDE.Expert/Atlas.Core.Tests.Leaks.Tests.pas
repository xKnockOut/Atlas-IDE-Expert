unit Atlas.Core.Tests.Leaks.Tests;

// Tests der Lecks je Test (#1774): Ein Test, der nur wegen eines Lecks
// fehlschlug, gilt mit tests.leaks als bestanden mit Leck; ohne bleibt der
// Fehlschlag; gewöhnliche Fehlschläge bleiben immer. Lecks am Programmende
// aus dem Bericht von FastMM bzw. der RTL als kurze Zusammenfassung.

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
    [Test]
    procedure LogFileNextToTheProgram;
    [Test]
    procedure ShutdownSummaryNamesAndBlocks;
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
  Assert.AreEqual(Ord(TTestOutcome.Passed), Ord(mRun.Cases[0].Outcome), 'nur Leck: bestanden');
  Assert.AreEqual(Int64(40), mRun.Cases[0].LeakBytes);
  Assert.AreEqual(Ord(TTestOutcome.Failed), Ord(mRun.Cases[1].Outcome), 'gewöhnlicher Fehlschlag bleibt');
  Assert.AreEqual(2, mRun.Count(TTestOutcome.Passed));
  Assert.AreEqual(Ord(TTestOutcome.Failed), Ord(mReport.Cases[0].Outcome), 'der gelesene Bericht bleibt unverändert');
end;

procedure TAtlasTestLeaksTests.WithoutSettingTheReportStays;
var
  mRun: TTestRunResult;
begin
  mRun := TAtlasTestLeaks.Shown(TTestResults.Parse(cReport), False);
  Assert.AreEqual(Ord(TTestOutcome.Failed), Ord(mRun.Cases[0].Outcome));
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

procedure TAtlasTestLeaksTests.LogFileNextToTheProgram;
begin
  Assert.AreEqual('C:\Tests\Konto.Tests_MemoryManager_EventLog.txt',
    TAtlasTestLeaks.LogFileOf('C:\Tests\Konto.Tests.exe'));
  Assert.AreEqual('', TAtlasTestLeaks.LogFileOf(''));
end;

procedure TAtlasTestLeaksTests.ShutdownSummaryNamesAndBlocks;
const
  cNl = #13#10;
  cReport =
    'This application has leaked memory. The small block leaks are:' + cNl + cNl +
    '1 - 12 bytes: TKunde x 3, UnicodeString x 5' + cNl +
    '13 - 20 bytes: TStringList x 2' + cNl + cNl +
    'The sizes of unexpected leaked medium and large blocks are: 40100' + cNl;
var
  mBlocks: Integer;
begin
  Assert.AreEqual('UnicodeString x 5, TKunde x 3, TStringList x 2',
    TAtlasTestLeaks.ShutdownSummary(cReport, 3, mBlocks), 'nach Anzahl absteigend');
  Assert.AreEqual(11, mBlocks, '10 kleine und ein großer Block');
  Assert.AreEqual('UnicodeString x 5, …', TAtlasTestLeaks.ShutdownSummary(cReport, 1, mBlocks));
  Assert.AreEqual('', TAtlasTestLeaks.ShutdownSummary('Tests: 3 bestanden', 3, mBlocks), 'kein Bericht');
  Assert.AreEqual(0, mBlocks);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTestLeaksTests);

end.
