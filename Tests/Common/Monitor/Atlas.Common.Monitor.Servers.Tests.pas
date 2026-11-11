unit Atlas.Common.Monitor.Servers.Tests;

// Tests für die Logik des Reiters „Server“ und des Symbols im Infobereich von AtlasMonitor (#1901): Zustand je
// Server, schlechtester Zustand, Texte in beiden Sprachen, Hinweis, Spalten und Einzelheiten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMonitorServersTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure IdleWhenReady;
    [Test]
    procedure BusyWhileRequestRunsOrIndexLoads;
    [Test]
    procedure HangingWhenSilentOrRequestTooLong;
    [Test]
    procedure OverallIsWorst;
    [Test]
    procedure KindTextNamesKindAndCommand;
    [Test]
    procedure HintCountsServers;
    [Test]
    procedure ColumnsMatchTitles;
    [Test]
    procedure DetailsShowActivity;
    [Test]
    procedure MenuTextNamesPlaceAndPid;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Lsp.StatusFile,
  Atlas.Common.Monitor.Servers;

const
  cNow: TDateTime = 46324.5;

/// <summary>Bereiter IDE-Server, vor 2 s geschrieben.</summary>
function ReadyEntry: TServerStatusEntry;
begin
  Result := Default(TServerStatusEntry);
  Result.Pid := 100;
  Result.Kind := TServerStatusEntry.cKindLsp;
  Result.Written := IncSecond(cNow, -2);
  Result.Started := IncHour(cNow, -1);
  Result.State := TServerStatusEntry.cStateReady;
  Result.Roots := TArray<string>.Create('C:\Projekte\App');
  Result.Version := '2.1.0';
  Result.MemoryBytes := 300 * 1024 * 1024;
end;

procedure TMonitorServersTests.Setup;
begin
  TAtlasLocale.Use(TTextLanguage.German);
end;

procedure TMonitorServersTests.TearDown;
begin
  TAtlasLocale.Use(TTextLanguage.German);
end;

procedure TMonitorServersTests.IdleWhenReady;
begin
  Assert.IsTrue(TMonitorServers.HealthOf(ReadyEntry, cNow) = TMonitorHealth.Idle);
  Assert.AreEqual('ruht', TMonitorServers.HealthText(TMonitorHealth.Idle));
end;

procedure TMonitorServersTests.BusyWhileRequestRunsOrIndexLoads;
var
  mEntry: TServerStatusEntry;
begin
  mEntry := ReadyEntry;
  mEntry.Running := 1;
  mEntry.RunningMs := 800;
  Assert.IsTrue(TMonitorServers.HealthOf(mEntry, cNow) = TMonitorHealth.Busy);
  mEntry := ReadyEntry;
  mEntry.State := 'loading';
  Assert.IsTrue(TMonitorServers.HealthOf(mEntry, cNow) = TMonitorHealth.Busy);
  mEntry.State := '';
  Assert.IsTrue(TMonitorServers.HealthOf(mEntry, cNow) = TMonitorHealth.Idle, 'alte Datei ohne Zustand');
end;

procedure TMonitorServersTests.HangingWhenSilentOrRequestTooLong;
var
  mEntry: TServerStatusEntry;
begin
  mEntry := ReadyEntry;
  mEntry.Written := IncSecond(cNow, -(TMonitorServers.cSilentSeconds + 1));
  Assert.IsTrue(TMonitorServers.HealthOf(mEntry, cNow) = TMonitorHealth.Hanging);
  mEntry := ReadyEntry;
  mEntry.Running := 1;
  mEntry.RunningMs := TMonitorServers.cHangingRequestMs + 1;
  Assert.IsTrue(TMonitorServers.HealthOf(mEntry, cNow) = TMonitorHealth.Hanging);
  // Eine Uhr, die nachgeht, macht keinen Server hängend.
  mEntry := ReadyEntry;
  mEntry.Written := IncSecond(cNow, 30);
  Assert.IsTrue(TMonitorServers.HealthOf(mEntry, cNow) = TMonitorHealth.Idle);
end;

procedure TMonitorServersTests.OverallIsWorst;
var
  mBusy, mHanging: TServerStatusEntry;
begin
  mBusy := ReadyEntry;
  mBusy.Running := 1;
  mHanging := ReadyEntry;
  mHanging.Written := IncMinute(cNow, -5);
  Assert.IsTrue(TMonitorServers.Overall(nil, cNow) = TMonitorHealth.Idle);
  Assert.IsTrue(TMonitorServers.Overall(TArray<TServerStatusEntry>.Create(ReadyEntry, mBusy), cNow) =
    TMonitorHealth.Busy);
  Assert.IsTrue(TMonitorServers.Overall(TArray<TServerStatusEntry>.Create(mHanging, mBusy), cNow) =
    TMonitorHealth.Hanging);
end;

procedure TMonitorServersTests.KindTextNamesKindAndCommand;
var
  mEntry: TServerStatusEntry;
begin
  mEntry := ReadyEntry;
  Assert.AreEqual('IDE-Server', TMonitorServers.KindText(mEntry));
  mEntry.Kind := '';
  Assert.AreEqual('IDE-Server', TMonitorServers.KindText(mEntry), 'ohne Art: LSP');
  mEntry.Kind := TServerStatusEntry.cKindMcp;
  Assert.AreEqual('KI-Assistent (MCP)', TMonitorServers.KindText(mEntry));
  mEntry.Kind := TServerStatusEntry.cKindCli;
  Assert.AreEqual('Kommandozeile', TMonitorServers.KindText(mEntry));
  mEntry.Command := 'format-check';
  Assert.AreEqual('Kommandozeile: format-check', TMonitorServers.KindText(mEntry));
  TAtlasLocale.Use(TTextLanguage.English);
  Assert.AreEqual('Command line: format-check', TMonitorServers.KindText(mEntry));
  Assert.AreEqual('not responding', TMonitorServers.HealthText(TMonitorHealth.Hanging));
end;

procedure TMonitorServersTests.HintCountsServers;
var
  mBusy: TServerStatusEntry;
begin
  mBusy := ReadyEntry;
  mBusy.Running := 2;
  Assert.AreEqual('Atlas: keine Server', TMonitorServers.Hint(nil, cNow));
  Assert.AreEqual('Atlas-Server: 2, arbeitet',
    TMonitorServers.Hint(TArray<TServerStatusEntry>.Create(ReadyEntry, mBusy), cNow));
  TAtlasLocale.Use(TTextLanguage.English);
  Assert.AreEqual('Atlas servers: 1, idle', TMonitorServers.Hint(TArray<TServerStatusEntry>.Create(ReadyEntry),
    cNow));
end;

procedure TMonitorServersTests.ColumnsMatchTitles;
var
  mCells: TArray<string>;
  mEntry: TServerStatusEntry;
begin
  mEntry := ReadyEntry;
  mCells := TMonitorServers.Columns(mEntry, cNow);
  Assert.AreEqual(Integer(Length(TMonitorServers.ColumnTitles)), Integer(Length(mCells)));
  Assert.AreEqual('IDE-Server', mCells[0]);
  Assert.AreEqual('C:\Projekte\App', mCells[1], 'ohne Ziel der erste Ordner');
  Assert.AreEqual('ruht', mCells[2]);
  Assert.AreEqual('300 MB', mCells[3]);
  Assert.AreEqual('100', mCells[4]);
  Assert.AreEqual('2.1.0', mCells[5]);
  mEntry.Target := 'C:\Projekte\App\App.dproj';
  Assert.AreEqual('C:\Projekte\App\App.dproj', TMonitorServers.PlaceOf(mEntry), 'Ziel vor Ordner');
  mCells := nil;
end;

procedure TMonitorServersTests.DetailsShowActivity;
var
  mEntry: TServerStatusEntry;
  mText: string;
begin
  mEntry := ReadyEntry;
  mEntry.Running := 3;
  mEntry.RunningMethod := 'textDocument/references';
  mEntry.RunningMs := 4500;
  mEntry.Done := 7;
  mEntry.Total := 20;
  mEntry.Timeouts := 2;
  mEntry.Errors := 1;
  mEntry.LogFile := 'C:\Logs\server.log';
  mText := string.Join(#10, TMonitorServers.Details(mEntry, cNow));
  Assert.IsTrue(mText.Contains('Prozess: 100'), mText);
  Assert.IsTrue(mText.Contains('Längste Anfrage: textDocument/references seit 4 s und 2 weitere'), mText);
  Assert.IsTrue(mText.Contains('Fortschritt: 7 von 20'), mText);
  Assert.IsTrue(mText.Contains('Zeitüberschreitungen: 2'), mText);
  Assert.IsTrue(mText.Contains('Fehler: 1'), mText);
  Assert.IsTrue(mText.Contains('Ordner: C:\Projekte\App'), mText);
  Assert.IsTrue(mText.Contains('Protokoll: C:\Logs\server.log'), mText);
  Assert.IsTrue(mText.Contains('Letzte Meldung: vor 2 s'), mText);
  mText := string.Join(#10, TMonitorServers.Details(ReadyEntry, cNow));
  Assert.IsFalse(mText.Contains('Längste Anfrage'), 'ohne laufende Anfrage');
  Assert.IsFalse(mText.Contains('Fortschritt'), 'ohne Fortschritt');
end;

procedure TMonitorServersTests.MenuTextNamesPlaceAndPid;
begin
  Assert.AreEqual('IDE-Server · C:\Projekte\App · ruht (100)', TMonitorServers.MenuText(ReadyEntry, cNow));
end;

initialization
  TDUnitX.RegisterTestFixture(TMonitorServersTests);

end.
