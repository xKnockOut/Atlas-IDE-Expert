unit Atlas.Text.McpStatistics.Tests;

// Tests für das gemeinsame Modell der MCP-Aufrufstatistik (#2611): Fehlerquote, Zellen mit Einheiten, JSON des
// Abschnitts mcp; Sitzungen der KI-Assistenten aus Statusdateien, Zeilen der Tabelle, Kennung des Stands.

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

  [TestFixture]
  TMcpAssistantSessionsTests = class
  private
    FFolder: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReadsMcpStatusWithStatistics;
    [Test]
    procedure McpWithoutSectionDoesNotCount;
    [Test]
    procedure OtherKindsAndBrokenTextAreSkipped;
    [Test]
    procedure FolderKeepsFreshMcpFilesInOrder;
    [Test]
    procedure MissingFolderGivesNoSessions;
    [Test]
    procedure RowsSpanSessionsAndCountConspicuous;
    [Test]
    procedure SignatureFollowsPidAndWritten;
    [Test]
    procedure ClientFallsBackToUnknown;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.IOUtils,
  System.DateUtils,
  Atlas.Tests.TempFolder,
  Atlas.Text.Timestamps,
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

/// <summary>Inhalt einer Statusdatei der Art AKind mit pid APid, geschrieben AWritten, mit dem Abschnitt mcp
/// AMcp ('' ohne).</summary>
function StatusText(APid: Cardinal; const AKind: string; AWritten: TDateTime; const AMcp: string): string;
begin
  Result := Format('{"pid":%d,"written":"%s","kind":"%s"', [APid, TTextTimestamp.IsoOrEmpty(AWritten), AKind]);
  if AMcp <> '' then
  begin
    Result := Result + ',"mcp":' + AMcp;
  end;
  Result := Result + '}';
end;

/// <summary>Abschnitt mcp eines Clients mit den Werkzeugen check_code (6 Aufrufe, 2 Fehler) und find_symbol, Beginn
/// AStarted.</summary>
function McpText(const AClient: string; AStarted: TDateTime): string;
var
  mStats: TMcpSessionStatistics;
  mJson: TJSONObject;
begin
  mStats := Default(TMcpSessionStatistics);
  mStats.Client := AClient;
  mStats.Started := AStarted;
  mStats.Calls := TArray<TMcpCallSummary>.Create(TMcpStatisticsTestSupport.Called('check_code', 6, 2),
    TMcpStatisticsTestSupport.Called('find_symbol', 10, 0));
  mJson := mStats.ToJson;
  try
    Result := mJson.ToJSON([]);
  finally
    mJson.Free;
  end;
end;

{ TMcpAssistantSessionsTests }

procedure TMcpAssistantSessionsTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'Atlas-McpAssistants-' + IntToStr(Random(MaxInt)));
  TDirectory.CreateDirectory(FFolder);
end;

procedure TMcpAssistantSessionsTests.TearDown;
begin
  TTestTempFolder.Remove(FFolder);
end;

procedure TMcpAssistantSessionsTests.ReadsMcpStatusWithStatistics;
var
  mSession: TMcpAssistantSession;
begin
  Assert.IsTrue(TMcpAssistantSessions.FromStatus(StatusText(4711, 'mcp', cNow, McpText('Assistent A', cNow)),
    mSession));
  Assert.AreEqual(Int64(4711), Int64(mSession.Pid));
  Assert.IsTrue(mSession.HasStatistics);
  Assert.AreEqual('Assistent A', mSession.Statistics.Client);
  Assert.AreEqual(16, mSession.Statistics.TotalCalls);
  Assert.IsTrue(Abs(mSession.Written - cNow) < 1 / SecsPerDay);
end;

procedure TMcpAssistantSessionsTests.McpWithoutSectionDoesNotCount;
var
  mSession: TMcpAssistantSession;
begin
  Assert.IsTrue(TMcpAssistantSessions.FromStatus(StatusText(12, 'mcp', cNow, ''), mSession));
  Assert.IsFalse(mSession.HasStatistics, 'mcp.statistics aus: kein Abschnitt');
  mSession := TMcpAssistantSessions.FromStatus(13, cNow, '');
  Assert.IsFalse(mSession.HasStatistics, 'Eintrag ohne Abschnitt (AtlasMonitor)');
  mSession := TMcpAssistantSessions.FromStatus(14, cNow, McpText('B', cNow));
  Assert.IsTrue(mSession.HasStatistics);
  Assert.AreEqual('B', mSession.Statistics.Client);
end;

procedure TMcpAssistantSessionsTests.OtherKindsAndBrokenTextAreSkipped;
var
  mSession: TMcpAssistantSession;
begin
  Assert.IsFalse(TMcpAssistantSessions.FromStatus(StatusText(1, 'lsp', cNow, McpText('A', cNow)), mSession));
  Assert.IsFalse(TMcpAssistantSessions.FromStatus(StatusText(1, 'cli', cNow, ''), mSession));
  Assert.IsFalse(TMcpAssistantSessions.FromStatus('', mSession), 'leer (gerade ersetzt)');
  Assert.IsFalse(TMcpAssistantSessions.FromStatus('{"kind":"mcp"', mSession), 'abgeschnitten');
  Assert.IsFalse(TMcpAssistantSessions.FromStatus('{"kind":"mcp","written":"2026-11-27T05:00:00"}', mSession),
    'ohne pid');
end;

procedure TMcpAssistantSessionsTests.FolderKeepsFreshMcpFilesInOrder;
var
  mNow: TDateTime;
  mSessions: TArray<TMcpAssistantSession>;
begin
  mNow := Now;
  TFile.WriteAllText(TPath.Combine(FFolder, 'server-30.json'), StatusText(30, 'mcp', IncSecond(mNow, -2),
    McpText('Später', IncMinute(mNow, -5))), TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(FFolder, 'server-20.json'), StatusText(20, 'mcp', IncSecond(mNow, -1),
    McpText('Früher', IncMinute(mNow, -30))), TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(FFolder, 'server-10.json'), StatusText(10, 'lsp', mNow, ''), TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(FFolder, 'server-40.json'), StatusText(40, 'mcp',
    IncSecond(mNow, -(TMcpAssistantSessions.cMaxAgeSeconds + 30)), McpText('Verwaist', mNow)), TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(FFolder, 'anderes.json'), StatusText(50, 'mcp', mNow, ''), TEncoding.UTF8);
  mSessions := TMcpAssistantSessions.ReadFolder(FFolder, mNow);
  Assert.AreEqual(2, Integer(Length(mSessions)), 'nur frische MCP-Dateien server-*.json');
  Assert.AreEqual('Früher', mSessions[0].Statistics.Client, 'früher begonnen zuerst');
  Assert.AreEqual('Später', mSessions[1].Statistics.Client);
  Assert.IsTrue(TFile.Exists(TPath.Combine(FFolder, 'server-40.json')), 'der Leser löscht nichts');
end;

procedure TMcpAssistantSessionsTests.MissingFolderGivesNoSessions;
begin
  Assert.AreEqual(0, Integer(Length(TMcpAssistantSessions.ReadFolder(TPath.Combine(FFolder, 'fehlt'), Now))));
  Assert.AreEqual(0, Integer(Length(TMcpAssistantSessions.ReadFolder('', Now))));
  Assert.IsTrue(TMcpAssistantSessions.DefaultFolder.EndsWith(TMcpAssistantSessions.cFolderName),
    TMcpAssistantSessions.DefaultFolder);
end;

procedure TMcpAssistantSessionsTests.RowsSpanSessionsAndCountConspicuous;
var
  mSessions: TArray<TMcpAssistantSession>;
  mRows: TArray<TMcpAssistantRow>;
begin
  mSessions := TArray<TMcpAssistantSession>.Create(TMcpAssistantSessions.FromStatus(1, cNow, McpText('A', cNow)),
    TMcpAssistantSessions.FromStatus(2, cNow, ''), TMcpAssistantSessions.FromStatus(3, cNow, McpText('C', cNow)));
  mRows := TMcpAssistantSessions.Rows(mSessions);
  Assert.AreEqual(4, Integer(Length(mRows)), 'zwei Werkzeuge je zählender Sitzung');
  Assert.AreEqual(0, mRows[0].Session);
  Assert.AreEqual('check_code', mRows[0].Call.Name);
  Assert.AreEqual(2, mRows[2].Session, 'die Sitzung ohne Statistik hat keine Zeilen');
  Assert.AreEqual(2, TMcpAssistantSessions.ConspicuousCount(mRows), 'check_code: 2 von 6 sind über 20 %');
end;

procedure TMcpAssistantSessionsTests.SignatureFollowsPidAndWritten;
var
  mFirst, mSecond: TArray<TMcpAssistantSession>;
begin
  mFirst := TArray<TMcpAssistantSession>.Create(TMcpAssistantSessions.FromStatus(1, cNow, ''));
  mSecond := TArray<TMcpAssistantSession>.Create(TMcpAssistantSessions.FromStatus(1, cNow, McpText('A', cNow)));
  Assert.AreEqual(TMcpAssistantSessions.Signature(mFirst), TMcpAssistantSessions.Signature(mSecond));
  mSecond[0].Written := IncSecond(cNow, 5);
  Assert.AreNotEqual(TMcpAssistantSessions.Signature(mFirst), TMcpAssistantSessions.Signature(mSecond));
  Assert.AreEqual('', TMcpAssistantSessions.Signature(nil));
end;

procedure TMcpAssistantSessionsTests.ClientFallsBackToUnknown;
begin
  Assert.AreEqual('?', TMcpAssistantSessions.FromStatus(1, cNow, '').ClientOr('?'));
  Assert.AreEqual('A', TMcpAssistantSessions.FromStatus(1, cNow, McpText('A', cNow)).ClientOr('?'));
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpStatisticsModelTests);
  TDUnitX.RegisterTestFixture(TMcpAssistantSessionsTests);

end.
