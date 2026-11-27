unit Atlas.Common.Monitor.Assistants.Tests;

// Tests für die Logik des Reiters „KI-Assistenten“ von AtlasMonitor (#2611): Sitzungen aus den Einträgen der
// Statusdateien, Spalten und Zellen, Zeile je Sitzung in beiden Sprachen, Hinweis ohne Assistenten, auffällige
// Fehlerquoten, Einzelheiten mit dem letzten fehlgeschlagenen Aufruf im Klartext.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMonitorAssistantsTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SessionsComeOnlyFromMcpEntries;
    [Test]
    procedure ColumnsMatchTitles;
    [Test]
    procedure SessionLineInBothLanguages;
    [Test]
    procedure SummaryWithoutAssistantsGivesHint;
    [Test]
    procedure SummaryCountsConspicuousRows;
    [Test]
    procedure DetailsShowLastFailedCallPlain;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  System.JSON,
  Atlas.Text.LogMarks,
  Atlas.Text.McpStatistics,
  Atlas.Text.McpStatistics.TestSupport,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Diagnostics.StatusFile,
  Atlas.Common.Monitor.Assistants;

const
  cNow: TDateTime = 46324.5;

/// <summary>Abschnitt mcp des Clients AClient: check_code mit 6 Aufrufen und 2 Fehlern (letzter mit Pfad),
/// find_symbol mit 10 Aufrufen; Beginn 11:00.</summary>
function McpText(const AClient: string): string;
var
  mStats: TMcpSessionStatistics;
  mFailed: TMcpCallSummary;
  mJson: TJSONObject;
begin
  mStats := Default(TMcpSessionStatistics);
  mStats.Client := AClient;
  mStats.Project := TLogMarks.Path('C:\App\App.dproj');
  mStats.Started := IncHour(cNow, -1);
  mFailed := TMcpStatisticsTestSupport.Called('check_code', 6, 2);
  mFailed.LastFailed.At := cNow;
  mFailed.LastFailed.Arguments := 'file="' + TLogMarks.Path('C:\App\Run.pas') + '"';
  mFailed.LastFailed.Message := TLogMarks.Text('Datei fehlt');
  mStats.Calls := TArray<TMcpCallSummary>.Create(mFailed, TMcpStatisticsTestSupport.Called('find_symbol', 10, 0));
  mJson := mStats.ToJson;
  try
    Result := mJson.ToJSON([]);
  finally
    mJson.Free;
  end;
end;

/// <summary>Eintrag der Art AKind mit pid APid und dem Abschnitt mcp AMcp.</summary>
function Entry(APid: Cardinal; const AKind, AMcp: string): TServerStatusEntry;
begin
  Result := Default(TServerStatusEntry);
  Result.Pid := APid;
  Result.Kind := AKind;
  Result.Written := cNow;
  Result.Mcp := AMcp;
end;

function OneSession: TArray<TMcpAssistantSession>;
begin
  Result := TMonitorAssistants.Sessions(TArray<TServerStatusEntry>.Create(Entry(4711, TServerStatusEntry.cKindMcp,
    McpText('Assistent A'))));
end;

{ TMonitorAssistantsTests }

procedure TMonitorAssistantsTests.Setup;
begin
  TAtlasLocale.Use(TTextLanguage.German);
end;

procedure TMonitorAssistantsTests.TearDown;
begin
  TAtlasLocale.Use(TTextLanguage.German);
end;

procedure TMonitorAssistantsTests.SessionsComeOnlyFromMcpEntries;
var
  mSessions: TArray<TMcpAssistantSession>;
begin
  mSessions := TMonitorAssistants.Sessions(TArray<TServerStatusEntry>.Create(
    Entry(1, TServerStatusEntry.cKindLsp, ''), Entry(2, TServerStatusEntry.cKindMcp, McpText('A')),
    Entry(3, TServerStatusEntry.cKindCli, ''), Entry(4, TServerStatusEntry.cKindMcp, '')));
  Assert.AreEqual(2, Integer(Length(mSessions)));
  // Ohne Statistik kein Beginn: Die Sitzung steht vorn.
  Assert.AreEqual(Int64(4), Int64(mSessions[0].Pid));
  Assert.IsFalse(mSessions[0].HasStatistics);
  Assert.AreEqual(Int64(2), Int64(mSessions[1].Pid));
  Assert.IsTrue(mSessions[1].HasStatistics);
end;

procedure TMonitorAssistantsTests.ColumnsMatchTitles;
var
  mSessions: TArray<TMcpAssistantSession>;
  mRows: TArray<TMcpAssistantRow>;
  mCells: TArray<string>;
begin
  mSessions := OneSession;
  mRows := TMcpAssistantSessions.Rows(mSessions);
  mCells := TMonitorAssistants.Columns(mSessions, mRows[0]);
  Assert.AreEqual(Integer(Length(TMonitorAssistants.ColumnTitles)), Integer(Length(mCells)));
  Assert.AreEqual('Assistent A (4711)', mCells[0]);
  Assert.AreEqual('check_code', mCells[1]);
  Assert.AreEqual('2 (33 %)', mCells[1 + Ord(TMcpCallColumn.Errors)]);
  Assert.AreEqual('1,2 s', mCells[1 + Ord(TMcpCallColumn.MedianMs)]);
  TAtlasLocale.Use(TTextLanguage.English);
  mCells := TMonitorAssistants.Columns(mSessions, mRows[0]);
  Assert.AreEqual('1.2 s', mCells[1 + Ord(TMcpCallColumn.MedianMs)]);
  Assert.AreEqual('AI assistant', TMonitorAssistants.ColumnTitles[0]);
  Assert.AreEqual('AI assistants', TMonitorAssistants.TabCaption);
end;

procedure TMonitorAssistantsTests.SessionLineInBothLanguages;
var
  mSessions: TArray<TMcpAssistantSession>;
  mLine: string;
begin
  mSessions := OneSession;
  mLine := TMonitorAssistants.SessionLine(mSessions[0]);
  Assert.IsTrue(mLine.StartsWith('KI-Assistent „Assistent A“ (Prozess 4711)'), mLine);
  Assert.IsTrue(mLine.Contains('16 Aufrufe, 2 Fehler'), mLine);
  Assert.IsTrue(mLine.EndsWith('Projekt C:\App\App.dproj'), mLine);
  Assert.IsFalse(TLogMarks.HasMarks(mLine), 'Projekt im Klartext');
  TAtlasLocale.Use(TTextLanguage.English);
  mLine := TMonitorAssistants.SessionLine(mSessions[0]);
  Assert.IsTrue(mLine.StartsWith('AI assistant "Assistent A" (process 4711)'), mLine);
  mLine := TMonitorAssistants.SessionLine(TMcpAssistantSessions.FromStatus(9, cNow, ''));
  Assert.IsTrue(mLine.Contains('process 9'), mLine);
  Assert.IsTrue(mLine.Contains('mcp.statistics'), mLine);
end;

procedure TMonitorAssistantsTests.SummaryWithoutAssistantsGivesHint;
var
  mLines: TArray<string>;
begin
  mLines := TMonitorAssistants.Summary(nil);
  Assert.AreEqual(1, Integer(Length(mLines)));
  Assert.IsTrue(mLines[0].StartsWith('Kein KI-Assistent verbunden'), mLines[0]);
end;

procedure TMonitorAssistantsTests.SummaryCountsConspicuousRows;
var
  mLines: TArray<string>;
begin
  mLines := TMonitorAssistants.Summary(OneSession);
  Assert.AreEqual(2, Integer(Length(mLines)), 'Sitzung und Auffällige');
  Assert.AreEqual('Auffällige Fehlerquote (über 20 %, rot): 1', mLines[1]);
end;

procedure TMonitorAssistantsTests.DetailsShowLastFailedCallPlain;
var
  mSessions: TArray<TMcpAssistantSession>;
  mRows: TArray<TMcpAssistantRow>;
  mText: string;
begin
  mSessions := OneSession;
  mRows := TMcpAssistantSessions.Rows(mSessions);
  mText := string.Join(#10, TMonitorAssistants.Details(mSessions, mRows[0]));
  Assert.IsTrue(mText.Contains('Werkzeug: check_code'), mText);
  Assert.IsTrue(mText.Contains('Fehler: 2 (33 %)'), mText);
  Assert.IsTrue(mText.Contains('Auffällige Fehlerquote'), mText);
  Assert.IsTrue(mText.Contains('Argumente: file="C:\App\Run.pas"'), mText);
  Assert.IsTrue(mText.Contains('Meldung: Datei fehlt'), mText);
  mText := string.Join(#10, TMonitorAssistants.Details(mSessions, mRows[1]));
  Assert.IsFalse(mText.Contains('Argumente'), 'ohne Fehlschlag kein letzter Aufruf');
  Assert.IsFalse(mText.Contains('Auffällige'), mText);
end;

initialization
  TDUnitX.RegisterTestFixture(TMonitorAssistantsTests);

end.
