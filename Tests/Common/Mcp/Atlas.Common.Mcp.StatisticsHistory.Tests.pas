unit Atlas.Common.Mcp.StatisticsHistory.Tests;

// Tests für den Verlauf der MCP-Aufrufstatistik (#2611): eine Zeile je Werkzeug, Grenze 30 Tage, Summen über
// Sitzungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpStatisticsHistoryTests = class
  private
    FFolder: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure LinesForToolsAndCalledResources;
    [Test]
    procedure LinesHaveNoArguments;
    [Test]
    procedure PruneDropsOldAndBrokenLines;
    [Test]
    procedure AppendKeepsThirtyDays;
    [Test]
    procedure TotalsSumOverSessions;
    [Test]
    procedure ReadOfMissingFileIsEmpty;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.DateUtils,
  Atlas.Text.McpStatistics,
  Atlas.Common.Mcp.StatisticsHistory;

const
  cNow: TDateTime = 46324.5;

function Session(const ACalled: string; AErrors: Integer): TMcpSessionStatistics;
var
  mCall: TMcpCallSummary;
begin
  Result := Default(TMcpSessionStatistics);
  Result.Client := 'Assistent A';
  Result.Project := 'C:\App';
  Result.Started := cNow;
  mCall := Default(TMcpCallSummary);
  mCall.Name := ACalled;
  mCall.Calls := 5;
  mCall.Errors := AErrors;
  mCall.MaxMs := 70;
  mCall.LastFailed.At := cNow;
  mCall.LastFailed.Arguments := '{"text":"geheim"}';
  Result.Calls := Result.Calls + [mCall];
  mCall := Default(TMcpCallSummary);
  mCall.Name := 'get_impact';
  Result.Calls := Result.Calls + [mCall];
  mCall := Default(TMcpCallSummary);
  mCall.Kind := TMcpCallKind.Prompt;
  mCall.Name := 'unit_review';
  Result.Calls := Result.Calls + [mCall];
end;

{ TMcpStatisticsHistoryTests }

procedure TMcpStatisticsHistoryTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'Atlas-McpHistory-' + IntToStr(Random(MaxInt)));
end;

procedure TMcpStatisticsHistoryTests.TearDown;
begin
  if TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  FFolder := '';
end;

procedure TMcpStatisticsHistoryTests.LinesForToolsAndCalledResources;
var
  mLines: TArray<string>;
begin
  mLines := TMcpStatisticsHistory.Lines(Session('find_symbol', 0), 4711, cNow);
  Assert.AreEqual(2, Integer(Length(mLines)), 'Werkzeuge auch ohne Aufruf, Prompt ohne Aufruf nicht');
  Assert.IsTrue(mLines[0].Contains('"name":"find_symbol"'), mLines[0]);
  Assert.IsTrue(mLines[0].Contains('"calls":5'), mLines[0]);
  Assert.IsTrue(mLines[0].Contains('"pid":4711'), mLines[0]);
  Assert.IsTrue(mLines[1].Contains('"name":"get_impact"'), mLines[1]);
end;

procedure TMcpStatisticsHistoryTests.LinesHaveNoArguments;
var
  mLine: string;
begin
  for mLine in TMcpStatisticsHistory.Lines(Session('check_code', 3), 1, cNow) do
  begin
    Assert.IsFalse(mLine.Contains('geheim'), mLine);
  end;
end;

procedure TMcpStatisticsHistoryTests.PruneDropsOldAndBrokenLines;
var
  mLines: TArray<string>;
begin
  mLines := TMcpStatisticsHistory.Lines(Session('neu', 0), 1, IncDay(cNow, -29)) +
    TMcpStatisticsHistory.Lines(Session('alt', 0), 2, IncDay(cNow, -31)) + TArray<string>.Create('kein JSON', '');
  mLines := TMcpStatisticsHistory.Prune(mLines, cNow);
  Assert.AreEqual(2, Integer(Length(mLines)));
  Assert.IsTrue(mLines[0].Contains('"name":"neu"'), mLines[0]);
end;

procedure TMcpStatisticsHistoryTests.AppendKeepsThirtyDays;
var
  mFile: string;
  mLines: TArray<string>;
begin
  mFile := TMcpStatisticsHistory.FileIn(FFolder);
  Assert.IsTrue(TMcpStatisticsHistory.Append(mFile, Session('alt', 0), 1, IncDay(cNow, -40)), 'legt Ordner an');
  Assert.IsTrue(TMcpStatisticsHistory.Append(mFile, Session('neu', 0), 2, cNow));
  mLines := TMcpStatisticsHistory.Prune(TFile.ReadAllLines(mFile, TEncoding.UTF8), IncDay(cNow, -100));
  Assert.AreEqual(2, Integer(Length(mLines)), 'die alte Sitzung ist beim zweiten Anhängen weggefallen');
  Assert.IsTrue(mLines[0].Contains('"name":"neu"'), mLines[0]);
  Assert.AreEqual(2, Integer(Length(TMcpStatisticsHistory.Read(mFile, cNow))));
end;

procedure TMcpStatisticsHistoryTests.TotalsSumOverSessions;
var
  mLines: TArray<string>;
  mTotals: TArray<TMcpHistoryTotal>;
begin
  mLines := TMcpStatisticsHistory.Lines(Session('check_code', 1), 1, cNow) +
    TMcpStatisticsHistory.Lines(Session('check_code', 2), 2, cNow);
  mTotals := TMcpStatisticsHistory.Totals(mLines);
  Assert.AreEqual(2, Integer(Length(mTotals)));
  Assert.AreEqual('check_code', mTotals[0].Name);
  Assert.AreEqual(2, mTotals[0].Sessions);
  Assert.AreEqual(10, mTotals[0].Calls);
  Assert.AreEqual(3, mTotals[0].Errors);
  Assert.AreEqual(Int64(70), mTotals[0].MaxMs);
  Assert.AreEqual('get_impact', mTotals[1].Name);
  Assert.AreEqual(0, mTotals[1].Calls);
  Assert.AreEqual(2, TMcpStatisticsHistory.SessionCount(mLines));
end;

procedure TMcpStatisticsHistoryTests.ReadOfMissingFileIsEmpty;
begin
  Assert.AreEqual(0, Integer(Length(TMcpStatisticsHistory.Read(TMcpStatisticsHistory.FileIn(FFolder), cNow))));
  Assert.IsFalse(TDirectory.Exists(FFolder), 'Lesen legt nichts an');
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpStatisticsHistoryTests);

end.
