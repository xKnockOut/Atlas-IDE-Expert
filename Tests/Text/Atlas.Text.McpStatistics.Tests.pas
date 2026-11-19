unit Atlas.Text.McpStatistics.Tests;

// Tests für das gemeinsame Modell der MCP-Aufrufstatistik (#2611): Fehlerquote, Zellen mit Einheiten, JSON des
// Abschnitts mcp.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpStatisticsModelTests = class
  public
    [Test]
    procedure FormatsDurationAndSize;
    [Test]
    procedure CellsOfCalledTool;
    [Test]
    procedure UncalledToolShowsPlaceholders;
    [Test]
    procedure ErrorRateIsConspicuousFromFiveCalls;
    [Test]
    procedure LastFailedIsPlainText;
    [Test]
    procedure SessionSurvivesJson;
    [Test]
    procedure InvalidTextGivesEmptySession;
    [Test]
    procedure PlainCopyHasNoMarks;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Text.LogMarks,
  Atlas.Text.McpStatistics,
  Atlas.Text.McpStatistics.TestSupport;

const
  cNow: TDateTime = 46324.5;

{ TMcpStatisticsModelTests }

procedure TMcpStatisticsModelTests.FormatsDurationAndSize;
begin
  Assert.AreEqual('40 ms', TMcpStatisticsFormat.DurationText(40, ','));
  Assert.AreEqual('1.2 s', TMcpStatisticsFormat.DurationText(1200, '.'));
  Assert.AreEqual('512 B', TMcpStatisticsFormat.SizeText(512, ','));
  Assert.AreEqual('2,0 KB', TMcpStatisticsFormat.SizeText(2048, ','));
  Assert.AreEqual('120 KB', TMcpStatisticsFormat.SizeText(120 * 1024, ','));
  Assert.AreEqual('1,5 MB', TMcpStatisticsFormat.SizeText(3 * 1024 * 1024 div 2, ','));
end;

procedure TMcpStatisticsModelTests.CellsOfCalledTool;
var
  mCells: TArray<string>;
begin
  mCells := TMcpStatisticsTestSupport.Called('check_code', 41, 9).Cells(',', '–');
  Assert.AreEqual(Ord(High(TMcpCallColumn)) + 1, Integer(Length(mCells)));
  Assert.AreEqual('check_code', mCells[Ord(TMcpCallColumn.Name)]);
  Assert.AreEqual('41', mCells[Ord(TMcpCallColumn.Calls)]);
  Assert.AreEqual('9 (22 %)', mCells[Ord(TMcpCallColumn.Errors)]);
  Assert.AreEqual('1,2 s', mCells[Ord(TMcpCallColumn.MedianMs)]);
  Assert.AreEqual('1,5 s', mCells[Ord(TMcpCallColumn.MaxMs)]);
  Assert.AreEqual('4,0 KB', mCells[Ord(TMcpCallColumn.MedianBytes)]);
  Assert.AreEqual('1,5 MB', mCells[Ord(TMcpCallColumn.MaxBytes)]);
  Assert.AreEqual('', mCells[Ord(TMcpCallColumn.LastFailed)]);
  Assert.AreEqual('0', TMcpStatisticsTestSupport.Called('a', 3, 0).Cells(',', '–')[Ord(TMcpCallColumn.Errors)],
    'ohne Quote');
end;

procedure TMcpStatisticsModelTests.UncalledToolShowsPlaceholders;
var
  mCells: TArray<string>;
begin
  mCells := TMcpStatisticsTestSupport.Called('get_impact', 0, 0).Cells(',', '–');
  Assert.AreEqual('0', mCells[Ord(TMcpCallColumn.Calls)]);
  Assert.AreEqual('–', mCells[Ord(TMcpCallColumn.Errors)]);
  Assert.AreEqual('–', mCells[Ord(TMcpCallColumn.MedianMs)]);
  Assert.AreEqual('–', mCells[Ord(TMcpCallColumn.MaxBytes)]);
end;

procedure TMcpStatisticsModelTests.ErrorRateIsConspicuousFromFiveCalls;
begin
  Assert.IsFalse(TMcpStatisticsTestSupport.Called('a', 4, 4).Conspicuous, 'unter fünf Aufrufen nie auffällig');
  Assert.IsFalse(TMcpStatisticsTestSupport.Called('a', 5, 1).Conspicuous, 'genau 20 % ist nicht über der Schwelle');
  Assert.IsTrue(TMcpStatisticsTestSupport.Called('a', 41, 9).Conspicuous, '22 %');
  Assert.AreEqual(22, TMcpStatisticsTestSupport.Called('a', 41, 9).ErrorPercent);
  Assert.AreEqual(0, TMcpStatisticsTestSupport.Called('a', 0, 0).ErrorPercent);
end;

procedure TMcpStatisticsModelTests.LastFailedIsPlainText;
var
  mCall: TMcpCallSummary;
begin
  mCall := TMcpStatisticsTestSupport.Called('check_code', 1, 1);
  mCall.LastFailed.At := cNow;
  mCall.LastFailed.Arguments := 'file="' + TLogMarks.Path('C:\App\Run.pas') + '"';
  mCall.LastFailed.Message := TLogMarks.Text('Datei fehlt');
  Assert.AreEqual('12:00 file="C:\App\Run.pas": Datei fehlt', mCall.LastFailedText);
end;

procedure TMcpStatisticsModelTests.SessionSurvivesJson;
var
  mStats, mRead: TMcpSessionStatistics;
  mCall: TMcpCallSummary;
  mJson: TJSONObject;
begin
  mStats := Default(TMcpSessionStatistics);
  mStats.Client := 'Assistent A';
  mStats.Project := 'C:\App';
  mStats.Started := cNow;
  mCall := TMcpStatisticsTestSupport.Called('find_symbol', 5, 1);
  mCall.Kind := TMcpCallKind.Resource;
  mCall.LastFailed.At := cNow;
  mCall.LastFailed.Arguments := 'name="x"';
  mStats.Calls := TArray<TMcpCallSummary>.Create(mCall);
  mJson := mStats.ToJson;
  try
    mRead := TMcpSessionStatistics.FromText(mJson.ToJSON([]));
  finally
    mJson.Free;
  end;
  Assert.AreEqual('Assistent A', mRead.Client);
  Assert.AreEqual('C:\App', mRead.Project);
  Assert.IsTrue(Abs(mRead.Started - cNow) < 1 / 86400);
  Assert.AreEqual(1, Integer(Length(mRead.Calls)));
  Assert.AreEqual<TMcpCallKind>(TMcpCallKind.Resource, mRead.Calls[0].Kind);
  Assert.AreEqual(5, mRead.TotalCalls);
  Assert.AreEqual(1, mRead.TotalErrors);
  Assert.AreEqual(Int64(4096), mRead.Calls[0].MedianBytes);
  Assert.AreEqual('name="x"', mRead.Calls[0].LastFailed.Arguments);
end;

procedure TMcpStatisticsModelTests.InvalidTextGivesEmptySession;
begin
  Assert.AreEqual(0, Integer(Length(TMcpSessionStatistics.FromText('kein JSON').Calls)));
  Assert.AreEqual('', TMcpSessionStatistics.FromText('').Client);
end;

procedure TMcpStatisticsModelTests.PlainCopyHasNoMarks;
var
  mStats, mPlain: TMcpSessionStatistics;
  mCall: TMcpCallSummary;
begin
  mStats := Default(TMcpSessionStatistics);
  mCall := TMcpStatisticsTestSupport.Called('check_code', 1, 1);
  mCall.LastFailed.Arguments := 'file="' + TLogMarks.Path('C:\App\Run.pas') + '"';
  mCall.LastFailed.Message := TLogMarks.Text('kaputt');
  mStats.Calls := TArray<TMcpCallSummary>.Create(mCall);
  mPlain := mStats.Plain;
  Assert.AreEqual('file="C:\App\Run.pas"', mPlain.Calls[0].LastFailed.Arguments);
  Assert.AreEqual('kaputt', mPlain.Calls[0].LastFailed.Message);
  Assert.IsTrue(TLogMarks.HasMarks(mStats.Calls[0].LastFailed.Arguments), 'das Original bleibt gekennzeichnet');
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpStatisticsModelTests);

end.
