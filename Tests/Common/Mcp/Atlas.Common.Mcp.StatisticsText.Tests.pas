unit Atlas.Common.Mcp.StatisticsText.Tests;

// Tests für die Anzeige der MCP-Aufrufstatistik (#2611): Tabellen, auffällige Werkzeuge im Klartext, Verlauf.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpStatisticsTextTests = class
  public
    [Test]
    procedure MarkdownHasTableAndConspicuousTool;
    [Test]
    procedure HistoryNamesNeverCalledTools;
    [Test]
    procedure EmptyHistoryHasNoSection;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.LogMarks,
  Atlas.Text.McpStatistics,
  Atlas.Common.Mcp.StatisticsHistory,
  Atlas.Common.Mcp.StatisticsText;

const
  cNow: TDateTime = 46324.5;

function Called(const AName: string; ACalls, AErrors: Integer): TMcpCallSummary;
begin
  Result := Default(TMcpCallSummary);
  Result.Name := AName;
  Result.Calls := ACalls;
  Result.Errors := AErrors;
  Result.MedianMs := 1200;
  Result.MaxMs := 1500;
  Result.MedianBytes := 4096;
  Result.MaxBytes := 3 * 1024 * 1024 div 2;
end;

{ TMcpStatisticsTextTests }

procedure TMcpStatisticsTextTests.MarkdownHasTableAndConspicuousTool;
var
  mStats: TMcpSessionStatistics;
  mCall: TMcpCallSummary;
  mText: string;
begin
  mStats := Default(TMcpSessionStatistics);
  mStats.Client := 'Assistent A';
  mStats.Started := cNow;
  mCall := Called('check_code', 41, 9);
  mCall.LastFailed.At := cNow;
  mCall.LastFailed.Arguments := 'file="' + TLogMarks.Path('C:\App\Run.pas') + '"';
  mStats.Calls := TArray<TMcpCallSummary>.Create(mCall, Called('get_impact', 0, 0));
  mText := TMcpStatisticsText.Markdown(mStats);
  Assert.IsTrue(mText.Contains('Assistent A'), mText);
  Assert.IsTrue(mText.Contains('41 Aufrufe, 9 Fehler'), mText);
  Assert.IsTrue(mText.Contains('| check_code | 41 | 9 (22 %) | 1,2 s | 1,5 s | 4,0 KB | 1,5 MB |'), mText);
  Assert.IsTrue(mText.Contains('| get_impact | 0 | – | – | – | – | – |'), mText);
  Assert.IsTrue(mText.Contains('Auffällig: check_code, 22 % Fehler, letzter Aufruf 12:00 file="C:\App\Run.pas"'),
    mText);
  Assert.IsFalse(TLogMarks.HasMarks(mText), 'Anzeige im Klartext');
end;

procedure TMcpStatisticsTextTests.HistoryNamesNeverCalledTools;
var
  mStats: TMcpSessionStatistics;
  mText: string;
begin
  mStats := Default(TMcpSessionStatistics);
  mStats.Calls := TArray<TMcpCallSummary>.Create(Called('check_code', 10, 5), Called('get_impact', 0, 0));
  mText := TMcpStatisticsText.HistoryMarkdown(TMcpStatisticsHistory.Lines(mStats, 1, cNow) +
    TMcpStatisticsHistory.Lines(mStats, 2, cNow));
  Assert.IsTrue(mText.Contains('2 Sitzungen'), mText);
  Assert.IsTrue(mText.Contains('Nie aufgerufen: get_impact'), mText);
  Assert.IsTrue(mText.Contains('Häufig fehlgeschlagen: check_code (10/20)'), mText);
end;

procedure TMcpStatisticsTextTests.EmptyHistoryHasNoSection;
begin
  Assert.AreEqual('', TMcpStatisticsText.HistoryMarkdown(nil));
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpStatisticsTextTests);

end.
