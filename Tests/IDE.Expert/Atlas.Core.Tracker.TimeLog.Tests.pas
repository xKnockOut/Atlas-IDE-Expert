unit Atlas.Core.Tracker.TimeLog.Tests;

// Tests zur Zeiterfassung (#1267) ohne IDE und Server: Uhr mit fester
// Zeitquelle (Leerlauf, Pause, Wechsel, Tageswechsel), Einträge je Tag ohne
// doppeltes Zählen, Abziehen und Korrigieren, Datei time.json mit Sperre,
// Rundung und Eingabe der Dauer sowie Aufbau und Fehler der YouTrack-Buchung
// (Work Item) gegen einen Transport mit festen Antworten.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Tracker.TimeClock,
  Atlas.Core.Tracker.TimeLog;

type
  [TestFixture]
  TAtlasTimeClockTests = class
  private
    FNow: TDateTime;
    FClock: TAtlasTimeClock;
    function Issue(const AKey: string): TAtlasTimeIssue;
    function Seconds(const ASpans: TArray<TAtlasTimeSpan>): Int64;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>15 min ohne Eingabe bei 10 min Leerlauf: Die Uhr steht, der Leerlauf zählt nicht.</summary>
    [Test]
    procedure IdleStopsAndIsNotCounted;
    [Test]
    procedure TickClosesAfterIdle;
    [Test]
    procedure PauseAndResume;
    [Test]
    procedure WithoutIssueNothingCounts;
    /// <summary>Die offene Spanne gehört dem bisherigen Issue.</summary>
    [Test]
    procedure SetIssueClosesSpanForOldIssue;
    [Test]
    procedure TakeKeepsClockRunning;
    [Test]
    procedure DiscardDropsUnsaved;
    /// <summary>Eine Spanne über Mitternacht verteilt sich auf zwei Tage.</summary>
    [Test]
    procedure DayChangeSplitsSpan;
  end;

  [TestFixture]
  TAtlasTimeLogTests = class
  private
    FFolder: string;
  public
    [TearDown]
    procedure TearDown;
    /// <summary>Zwei IDE-Instanzen melden dieselbe Zeit: sie zählt einmal.</summary>
    [Test]
    procedure AddCountsOverlapOnce;
    [Test]
    procedure SubtractFromOldestDay;
    [Test]
    procedure SetTotalCorrects;
    [Test]
    procedure OpenNewestFirst;
    [Test]
    procedure JsonRoundTrip;
    [Test]
    procedure InvalidJsonOrVersionIsRejected;
    [Test]
    procedure FileUpdateAndRead;
    /// <summary>Eine unlesbare Datei wird nicht überschrieben.</summary>
    [Test]
    procedure UnreadableFileStays;
    /// <summary>Hält eine andere Instanz die Sperre, scheitert das Schreiben nach LockWaitMs.</summary>
    [Test]
    procedure LockedFileFails;
  end;

  [TestFixture]
  TAtlasTimeRoundingTests = class
  public
    [Test]
    procedure MinutesRoundToStep;
    [Test]
    procedure ClockAndPresentation;
    [Test]
    procedure ParseDuration;
  end;

  [TestFixture]
  TAtlasTrackerTimeWriterTests = class
  public
    [Test]
    procedure WorkItemJson;
    [Test]
    procedure BookTimeAgainstFakeTransport;
    /// <summary>400 „time tracking is disabled“ heißt Zeiterfassung aus; 403 ist ein Rechtefehler.</summary>
    [Test]
    procedure BookTimeErrors;
    [Test]
    procedure TimeSettingsOfProject;
    /// <summary>Ohne Leserecht auf das Projekt: Zeiterfassung gilt als an, Arbeitstypen allgemein.</summary>
    [Test]
    procedure TimeSettingsWithoutProjectRights;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.DateUtils,
  System.IOUtils,
  System.JSON,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Providers.YouTrack;

const
  Minute = 1 / MinsPerDay;

type
  /// <summary>Transport mit festen Antworten je Methode und Adressanfang; merkt sich Aufrufe und Inhalte.</summary>
  TFakeTimeTransport = class(TInterfacedObject, IAtlasCiTransport, IAtlasCiSend)
  private
    FMethods: TArray<string>;
    FPrefixes: TArray<string>;
    FStatus: TArray<Integer>;
    FTexts: TArray<string>;
    function Reply(const AMethod, AUrl: string; out AStatus: Integer; out AText: string): Boolean;
  public
    Calls: TArray<string>;
    Bodies: TArray<string>;
    procedure Answer(const AMethod, APrefix: string; AStatus: Integer; const AText: string);
    function Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
    function Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
  end;

procedure TFakeTimeTransport.Answer(const AMethod, APrefix: string; AStatus: Integer; const AText: string);
begin
  FMethods := FMethods + [AMethod];
  FPrefixes := FPrefixes + [APrefix];
  FStatus := FStatus + [AStatus];
  FTexts := FTexts + [AText];
end;

function TFakeTimeTransport.Reply(const AMethod, AUrl: string; out AStatus: Integer; out AText: string): Boolean;
var
  mIndex: Integer;
begin
  Calls := Calls + [AMethod + ' ' + AUrl];
  AStatus := 404;
  AText := '';
  Result := True;
  for mIndex := 0 to High(FPrefixes) do
    if (FMethods[mIndex] = AMethod) and (Copy(AUrl, 1, Length(FPrefixes[mIndex])) = FPrefixes[mIndex]) then
    begin
      AStatus := FStatus[mIndex];
      AText := FTexts[mIndex];
      Exit;
    end;
end;

function TFakeTimeTransport.Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
begin
  AError := TAtlasCiFetchError.None;
  Result := Reply('GET', AUrl, AStatus, AText);
end;

function TFakeTimeTransport.Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer; out AStatus: Integer;
  out AText: string; out AError: TAtlasCiFetchError): Boolean;
begin
  AError := TAtlasCiFetchError.None;
  Bodies := Bodies + [ABody];
  Result := Reply(AMethod, AUrl, AStatus, AText);
end;

function YouTrackIssue(const AKey: string): TAtlasTimeIssue;
begin
  Result := TAtlasTimeIssue.Create('youtrack', 'https://yt.beispiel.de/', 'ATL', AKey);
end;

function YouTrackTarget: TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create('youtrack', 'https://yt.beispiel.de', 'ATL', '');
end;

function At(AHour, AMinute: Word): TDateTime;
begin
  Result := EncodeDateTime(2026, 10, 28, AHour, AMinute, 0, 0);
end;

{ TAtlasTimeClockTests }

procedure TAtlasTimeClockTests.Setup;
begin
  FNow := At(10, 0);
  FClock := TAtlasTimeClock.Create(
    function: TDateTime
    begin
      Result := FNow;
    end, 10);
end;

procedure TAtlasTimeClockTests.TearDown;
begin
  FreeAndNil(FClock);
end;

function TAtlasTimeClockTests.Issue(const AKey: string): TAtlasTimeIssue;
begin
  Result := YouTrackIssue(AKey);
end;

function TAtlasTimeClockTests.Seconds(const ASpans: TArray<TAtlasTimeSpan>): Int64;
var
  mSpan: TAtlasTimeSpan;
begin
  Result := 0;
  for mSpan in ASpans do
    Inc(Result, mSpan.Seconds);
end;

procedure TAtlasTimeClockTests.IdleStopsAndIsNotCounted;
var
  mSpans: TArray<TAtlasTimeSpan>;
begin
  FClock.SetIssue(Issue('ATL-1'));
  FClock.Activity(At(10, 0));
  FClock.Activity(At(10, 5));
  // 15 Minuten nichts: Die Uhr steht.
  FNow := At(10, 20);
  Assert.IsFalse(FClock.Running, 'Leerlauf über 10 min');
  FClock.Activity(At(10, 20));
  FClock.Activity(At(10, 25));
  mSpans := FClock.Take;
  Assert.AreEqual(2, Integer(Length(mSpans)));
  Assert.AreEqual(5 * 60, Integer(mSpans[0].Seconds), 'bis zur letzten Eingabe vor dem Leerlauf');
  Assert.AreEqual(5 * 60, Integer(mSpans[1].Seconds));
  Assert.AreEqual(10 * 60, Integer(Seconds(mSpans)), 'die 15 min Leerlauf zählen nicht');
end;

procedure TAtlasTimeClockTests.TickClosesAfterIdle;
begin
  FClock.SetIssue(Issue('ATL-1'));
  FClock.Activity(At(10, 0));
  FClock.Activity(At(10, 8));
  FNow := At(10, 9);
  FClock.Tick;
  Assert.IsTrue(FClock.Running, 'innerhalb des Leerlaufs');
  FNow := At(10, 30);
  FClock.Tick;
  Assert.IsFalse(FClock.Running);
  Assert.AreEqual(8 * 60, Integer(FClock.Unsaved));
  // Mit 20 min Leerlauf zählt dieselbe Lücke.
  FClock.SetIdleMinutes(20);
  FClock.Activity(At(10, 30));
  FClock.Activity(At(10, 45));
  Assert.AreEqual(23 * 60, Integer(FClock.Unsaved));
end;

procedure TAtlasTimeClockTests.PauseAndResume;
begin
  FClock.SetIssue(Issue('ATL-1'));
  FClock.Activity(At(10, 0));
  FClock.Activity(At(10, 4));
  FClock.Pause;
  Assert.IsTrue(FClock.Paused);
  FClock.Activity(At(10, 6));
  Assert.AreEqual(4 * 60, Integer(FClock.Unsaved), 'angehalten zählt nichts');
  FClock.Resume;
  FClock.Activity(At(10, 7));
  FClock.Activity(At(10, 9));
  Assert.AreEqual(6 * 60, Integer(FClock.Unsaved), 'nach Weiter ab der nächsten Eingabe');
end;

procedure TAtlasTimeClockTests.WithoutIssueNothingCounts;
begin
  FClock.Activity(At(10, 0));
  FClock.Activity(At(10, 5));
  Assert.AreEqual(0, Integer(FClock.Unsaved));
  Assert.AreEqual(0, Integer(Length(FClock.Take)));
end;

procedure TAtlasTimeClockTests.SetIssueClosesSpanForOldIssue;
var
  mSpans: TArray<TAtlasTimeSpan>;
begin
  FClock.SetIssue(Issue('ATL-1'));
  FClock.Activity(At(10, 0));
  FClock.Activity(At(10, 3));
  FClock.SetIssue(Issue('ATL-2'));
  FClock.Activity(At(10, 4));
  FClock.Activity(At(10, 6));
  mSpans := FClock.Take;
  Assert.AreEqual(2, Integer(Length(mSpans)));
  Assert.AreEqual('ATL-1', mSpans[0].Issue.Key);
  Assert.AreEqual(3 * 60, Integer(mSpans[0].Seconds));
  Assert.AreEqual('ATL-2', mSpans[1].Issue.Key);
  Assert.AreEqual(2 * 60, Integer(mSpans[1].Seconds));
  // Dasselbe Issue mit anderer Schreibweise der Adresse ist kein Wechsel.
  FClock.SetIssue(TAtlasTimeIssue.Create('youtrack', 'https://YT.beispiel.de', 'atl', 'atl-2'));
  FClock.Activity(At(10, 8));
  Assert.AreEqual(2 * 60, Integer(FClock.Unsaved));
end;

procedure TAtlasTimeClockTests.TakeKeepsClockRunning;
var
  mSpans: TArray<TAtlasTimeSpan>;
begin
  FClock.SetIssue(Issue('ATL-1'));
  FClock.Activity(At(10, 0));
  FClock.Activity(At(10, 2));
  mSpans := FClock.Take;
  Assert.AreEqual(2 * 60, Integer(Seconds(mSpans)));
  Assert.AreEqual(0, Integer(FClock.Unsaved));
  FClock.Activity(At(10, 5));
  mSpans := FClock.Take;
  Assert.AreEqual(3 * 60, Integer(Seconds(mSpans)), 'weiter ab der letzten Abgabe');
end;

procedure TAtlasTimeClockTests.DiscardDropsUnsaved;
begin
  FClock.SetIssue(Issue('ATL-1'));
  FClock.Activity(At(10, 0));
  FClock.Activity(At(10, 7));
  FClock.Discard;
  Assert.AreEqual(0, Integer(FClock.Unsaved));
  FClock.Activity(At(10, 9));
  Assert.AreEqual(2 * 60, Integer(FClock.Unsaved));
end;

procedure TAtlasTimeClockTests.DayChangeSplitsSpan;
var
  mLog: TAtlasTimeLog;
  mSpan: TAtlasTimeSpan;
begin
  FClock.SetIssue(Issue('ATL-1'));
  FClock.Activity(At(23, 50));
  FClock.Activity(At(23, 58));
  FClock.Activity(EncodeDateTime(2026, 10, 29, 0, 6, 0, 0));
  FClock.Activity(EncodeDateTime(2026, 10, 29, 0, 10, 0, 0));
  mLog := TAtlasTimeLog.Empty;
  for mSpan in FClock.Take do
    mLog.Add(mSpan);
  Assert.AreEqual(2, Integer(Length(mLog.Entries)));
  Assert.AreEqual(Integer(Trunc(At(0, 0))), mLog.Entries[0].Day);
  Assert.AreEqual(10 * 60, Integer(mLog.Entries[0].Seconds), 'bis Mitternacht');
  Assert.AreEqual(Integer(Trunc(At(0, 0))) + 1, mLog.Entries[1].Day);
  Assert.AreEqual(10 * 60, Integer(mLog.Entries[1].Seconds), 'ab Mitternacht');
  Assert.AreEqual(20 * 60, Integer(mLog.Total(Issue('ATL-1'))));
end;

{ TAtlasTimeLogTests }

procedure TAtlasTimeLogTests.TearDown;
begin
  if (FFolder <> '') and TDirectory.Exists(FFolder) then
    TDirectory.Delete(FFolder, True);
  FFolder := '';
end;

procedure TAtlasTimeLogTests.AddCountsOverlapOnce;
var
  mLog: TAtlasTimeLog;
  mIssue: TAtlasTimeIssue;
begin
  mIssue := YouTrackIssue('ATL-1');
  mLog := TAtlasTimeLog.Empty;
  mLog.Add(TAtlasTimeSpan.Create(mIssue, At(10, 0), At(10, 30)));
  // Zweite Instanz meldet 10:10–10:40: nur 10:30–10:40 ist neu.
  mLog.Add(TAtlasTimeSpan.Create(mIssue, At(10, 10), At(10, 40)));
  Assert.AreEqual(40 * 60, Integer(mLog.Total(mIssue)));
  // Ganz bekannte Zeit zählt nicht.
  mLog.Add(TAtlasTimeSpan.Create(mIssue, At(10, 0), At(10, 20)));
  Assert.AreEqual(40 * 60, Integer(mLog.Total(mIssue)));
  Assert.AreEqual(1, Integer(Length(mLog.Entries)));
  // Anderes Issue für sich.
  mLog.Add(TAtlasTimeSpan.Create(YouTrackIssue('ATL-2'), At(10, 0), At(10, 15)));
  Assert.AreEqual(15 * 60, Integer(mLog.Total(YouTrackIssue('ATL-2'))));
end;

procedure TAtlasTimeLogTests.SubtractFromOldestDay;
var
  mLog: TAtlasTimeLog;
  mIssue: TAtlasTimeIssue;
begin
  mIssue := YouTrackIssue('ATL-1');
  mLog := TAtlasTimeLog.Empty;
  mLog.Add(TAtlasTimeSpan.Create(mIssue, At(10, 0) - 1, At(10, 30) - 1));
  mLog.Add(TAtlasTimeSpan.Create(mIssue, At(10, 0), At(10, 20)));
  mLog.Subtract(mIssue, 40 * 60);
  Assert.AreEqual(10 * 60, Integer(mLog.Total(mIssue)), 'vom ältesten Tag an');
  Assert.AreEqual(1, Integer(Length(mLog.Entries)), 'der leere Vortag fällt weg');
  Assert.AreEqual(Integer(Trunc(At(0, 0))), mLog.Entries[0].Day);
  mLog.Subtract(mIssue, 99 * 60);
  Assert.AreEqual(0, Integer(mLog.Total(mIssue)));
  Assert.AreEqual(1, Integer(Length(mLog.Entries)), 'der jüngste Tag bleibt mit "last"');
  // Später gemeldete, schon gezählte Zeit kommt nicht zurück.
  mLog.Add(TAtlasTimeSpan.Create(mIssue, At(10, 0), At(10, 20)));
  Assert.AreEqual(0, Integer(mLog.Total(mIssue)));
  Assert.AreEqual(0, Integer(Length(mLog.Open)));
end;

procedure TAtlasTimeLogTests.SetTotalCorrects;
var
  mLog: TAtlasTimeLog;
  mIssue: TAtlasTimeIssue;
begin
  mIssue := YouTrackIssue('ATL-1');
  mLog := TAtlasTimeLog.Empty;
  mLog.Add(TAtlasTimeSpan.Create(mIssue, At(10, 0) - 2, At(11, 0) - 2));
  mLog.Add(TAtlasTimeSpan.Create(mIssue, At(10, 0), At(10, 30)));
  mLog.SetTotal(mIssue, 25 * 60, At(12, 0));
  Assert.AreEqual(25 * 60, Integer(mLog.Total(mIssue)));
  Assert.AreEqual(1, Integer(Length(mLog.Entries)), 'alles auf heute');
  Assert.IsTrue(mLog.Entries[0].Last >= At(10, 30), '"last" bleibt');
end;

procedure TAtlasTimeLogTests.OpenNewestFirst;
var
  mLog: TAtlasTimeLog;
  mOpen: TArray<TAtlasTimeOpen>;
begin
  mLog := TAtlasTimeLog.Empty;
  mLog.Add(TAtlasTimeSpan.Create(YouTrackIssue('ATL-2'), At(9, 0) - 1, At(9, 30) - 1));
  mLog.Add(TAtlasTimeSpan.Create(YouTrackIssue('ATL-1'), At(9, 0) - 3, At(9, 10) - 3));
  mLog.Add(TAtlasTimeSpan.Create(YouTrackIssue('ATL-1'), At(9, 0), At(9, 20)));
  mLog.Add(TAtlasTimeSpan.Create(YouTrackIssue('ATL-3'), At(9, 0), At(9, 5)));
  mOpen := mLog.Open;
  Assert.AreEqual(3, Integer(Length(mOpen)));
  Assert.AreEqual('ATL-1', mOpen[0].Issue.Key, 'heute, bei Gleichstand nach Kennung');
  Assert.AreEqual(30 * 60, Integer(mOpen[0].Seconds));
  Assert.AreEqual(Integer(Trunc(At(0, 0))) - 3, mOpen[0].FirstDay);
  Assert.AreEqual(Integer(Trunc(At(0, 0))), mOpen[0].LastDay);
  Assert.AreEqual('ATL-3', mOpen[1].Issue.Key);
  Assert.AreEqual('ATL-2', mOpen[2].Issue.Key);
end;

procedure TAtlasTimeLogTests.JsonRoundTrip;
var
  mLog, mRead: TAtlasTimeLog;
  mIssue: TAtlasTimeIssue;
begin
  mIssue := YouTrackIssue('ATL-1');
  mLog := TAtlasTimeLog.Empty;
  mLog.Add(TAtlasTimeSpan.Create(mIssue, At(10, 0), At(11, 25)));
  Assert.IsTrue(TAtlasTimeLog.Parse(mLog.ToJson, mRead));
  Assert.AreEqual(1, Integer(Length(mRead.Entries)));
  Assert.AreEqual('youtrack', mRead.Entries[0].Issue.Provider);
  Assert.AreEqual('https://yt.beispiel.de', mRead.Entries[0].Issue.Url, 'ohne "/" am Ende');
  Assert.AreEqual('ATL', mRead.Entries[0].Issue.Project);
  Assert.AreEqual('ATL-1', mRead.Entries[0].Issue.Key);
  Assert.AreEqual(85 * 60, Integer(mRead.Entries[0].Seconds));
  Assert.AreEqual(Integer(Trunc(At(0, 0))), mRead.Entries[0].Day);
  Assert.IsTrue(SameDateTime(At(11, 25), mRead.Entries[0].Last));
  Assert.IsTrue(TAtlasTimeLog.Parse('', mRead), 'leer = keine Zeit');
  Assert.AreEqual(0, Integer(Length(mRead.Entries)));
  Assert.IsTrue(TAtlasTimeLog.Parse(#$FEFF + mLog.ToJson, mRead), 'mit BOM');
end;

procedure TAtlasTimeLogTests.InvalidJsonOrVersionIsRejected;
var
  mRead: TAtlasTimeLog;
begin
  Assert.IsFalse(TAtlasTimeLog.Parse('{kaputt', mRead));
  Assert.IsFalse(TAtlasTimeLog.Parse('{"version": 2, "entries": []}', mRead));
  Assert.IsFalse(TAtlasTimeLog.Parse('{"version": 1, "entries": {}}', mRead));
  // Unvollständige Einträge fallen weg, der Rest bleibt.
  Assert.IsTrue(TAtlasTimeLog.Parse('{"version": 1, "entries": [{"key": "ATL-1"}, {"provider": "youtrack", ' +
    '"url": "https://yt.beispiel.de", "key": "ATL-2", "date": "2026-10-28", "seconds": 60}]}', mRead));
  Assert.AreEqual(1, Integer(Length(mRead.Entries)));
  Assert.AreEqual('ATL-2', mRead.Entries[0].Issue.Key);
end;

procedure TAtlasTimeLogTests.FileUpdateAndRead;
var
  mPath: string;
  mLog: TAtlasTimeLog;
  mIssue: TAtlasTimeIssue;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'atlas-time-' + TGUID.NewGuid.ToString);
  mPath := TPath.Combine(FFolder, TAtlasTimeFile.FileName);
  mIssue := YouTrackIssue('ATL-1');
  Assert.IsTrue(TAtlasTimeFile.Read(mPath, mLog), 'fehlende Datei = leer');
  Assert.AreEqual(0, Integer(Length(mLog.Entries)));
  Assert.IsTrue(TAtlasTimeFile.Update(mPath,
    procedure(var ALog: TAtlasTimeLog)
    begin
      ALog.Add(TAtlasTimeSpan.Create(mIssue, At(10, 0), At(10, 30)));
    end, mLog));
  Assert.AreEqual(30 * 60, Integer(mLog.Total(mIssue)));
  // Nach einem Neustart (neu gelesen) ist die Zeit des Tages noch da.
  Assert.IsTrue(TAtlasTimeFile.Read(mPath, mLog));
  Assert.AreEqual(30 * 60, Integer(mLog.Total(mIssue)));
  Assert.IsTrue(TAtlasTimeFile.Update(mPath,
    procedure(var ALog: TAtlasTimeLog)
    begin
      ALog.Add(TAtlasTimeSpan.Create(mIssue, At(10, 20), At(10, 45)));
    end, mLog));
  Assert.AreEqual(45 * 60, Integer(mLog.Total(mIssue)), 'Überlappung zählt einmal');
  // Die Sperre ist wieder frei.
  TFileStream.Create(mPath + TAtlasTimeFile.LockExtension, fmCreate or fmShareExclusive).Free;
end;

procedure TAtlasTimeLogTests.UnreadableFileStays;
var
  mPath: string;
  mLog: TAtlasTimeLog;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'atlas-time-' + TGUID.NewGuid.ToString);
  ForceDirectories(FFolder);
  mPath := TPath.Combine(FFolder, TAtlasTimeFile.FileName);
  TFile.WriteAllText(mPath, '{kaputt');
  Assert.IsFalse(TAtlasTimeFile.Read(mPath, mLog));
  Assert.IsFalse(TAtlasTimeFile.Update(mPath,
    procedure(var ALog: TAtlasTimeLog)
    begin
      ALog.Add(TAtlasTimeSpan.Create(YouTrackIssue('ATL-1'), At(10, 0), At(10, 30)));
    end, mLog));
  Assert.AreEqual('{kaputt', TFile.ReadAllText(mPath));
end;

procedure TAtlasTimeLogTests.LockedFileFails;
var
  mPath: string;
  mLog: TAtlasTimeLog;
  mLock: TStream;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'atlas-time-' + TGUID.NewGuid.ToString);
  ForceDirectories(FFolder);
  mPath := TPath.Combine(FFolder, TAtlasTimeFile.FileName);
  mLock := TFileStream.Create(mPath + TAtlasTimeFile.LockExtension, fmCreate or fmShareExclusive);
  try
    Assert.IsFalse(TAtlasTimeFile.Update(mPath,
      procedure(var ALog: TAtlasTimeLog)
      begin
        ALog.Add(TAtlasTimeSpan.Create(YouTrackIssue('ATL-1'), At(10, 0), At(10, 30)));
      end, mLog));
  finally
    mLock.Free;
  end;
  Assert.IsFalse(FileExists(mPath), 'nichts geschrieben');
  Assert.IsTrue(TAtlasTimeFile.Read(mPath, mLog), 'nach dem Freigeben wieder lesbar');
end;

{ TAtlasTimeRoundingTests }

procedure TAtlasTimeRoundingTests.MinutesRoundToStep;
begin
  Assert.AreEqual(0, TAtlasTimeRounding.Minutes(0, 5));
  Assert.AreEqual(5, TAtlasTimeRounding.Minutes(1, 5), 'mindestens ein Schritt');
  Assert.AreEqual(5, TAtlasTimeRounding.Minutes(7 * 60, 5));
  Assert.AreEqual(10, TAtlasTimeRounding.Minutes(7 * 60 + 30, 5), 'halb wird aufgerundet');
  Assert.AreEqual(85, TAtlasTimeRounding.Minutes(87 * 60, 5));
  Assert.AreEqual(90, TAtlasTimeRounding.Minutes(88 * 60, 5));
  Assert.AreEqual(87, TAtlasTimeRounding.Minutes(87 * 60 + 10, 1));
  Assert.AreEqual(45, TAtlasTimeRounding.Minutes(50 * 60, 15), '50 min auf 15 Minuten');
end;

procedure TAtlasTimeRoundingTests.ClockAndPresentation;
begin
  Assert.AreEqual('1:25', TAtlasTimeRounding.ClockText(85 * 60 + 59));
  Assert.AreEqual('0:00', TAtlasTimeRounding.ClockText(59));
  Assert.AreEqual('12:05', TAtlasTimeRounding.ClockText(12 * 3600 + 5 * 60));
  Assert.AreEqual('1h 25m', TAtlasTimeRounding.Presentation(85));
  Assert.AreEqual('45m', TAtlasTimeRounding.Presentation(45));
  Assert.AreEqual('2h', TAtlasTimeRounding.Presentation(120));
  Assert.AreEqual('', TAtlasTimeRounding.Presentation(0));
end;

procedure TAtlasTimeRoundingTests.ParseDuration;
var
  mMinutes: Integer;
begin
  Assert.IsTrue(TAtlasTimeRounding.ParseDuration('1:25', mMinutes));
  Assert.AreEqual(85, mMinutes);
  Assert.IsTrue(TAtlasTimeRounding.ParseDuration('85', mMinutes));
  Assert.AreEqual(85, mMinutes);
  Assert.IsTrue(TAtlasTimeRounding.ParseDuration('85 min', mMinutes));
  Assert.AreEqual(85, mMinutes);
  Assert.IsTrue(TAtlasTimeRounding.ParseDuration('1 h 25 min', mMinutes));
  Assert.AreEqual(85, mMinutes);
  Assert.IsTrue(TAtlasTimeRounding.ParseDuration('1h 25m', mMinutes));
  Assert.AreEqual(85, mMinutes);
  Assert.IsTrue(TAtlasTimeRounding.ParseDuration('1,5 h', mMinutes));
  Assert.AreEqual(90, mMinutes);
  Assert.IsTrue(TAtlasTimeRounding.ParseDuration('2 Std', mMinutes));
  Assert.AreEqual(120, mMinutes);
  Assert.IsFalse(TAtlasTimeRounding.ParseDuration('', mMinutes));
  Assert.IsFalse(TAtlasTimeRounding.ParseDuration('0', mMinutes));
  Assert.IsFalse(TAtlasTimeRounding.ParseDuration('1:75', mMinutes));
  Assert.IsFalse(TAtlasTimeRounding.ParseDuration('viel', mMinutes));
  Assert.IsFalse(TAtlasTimeRounding.ParseDuration('3 Tage', mMinutes));
  Assert.IsFalse(TAtlasTimeRounding.ParseDuration('999 h', mMinutes), 'über eine Woche');
  Assert.AreEqual(0, mMinutes);
end;

{ TAtlasTrackerTimeWriterTests }

procedure TAtlasTrackerTimeWriterTests.WorkItemJson;
var
  mValue: TJSONValue;
  mObject: TJSONObject;
  mJson: string;
begin
  mJson := TAtlasYouTrackTracker.WorkItemJson(TAtlasTrackerWorkItem.Create(85, At(17, 30), 'Entwicklung',
    'Parser repariert'));
  mValue := TJSONObject.ParseJSONValue(mJson);
  try
    Assert.IsTrue(mValue is TJSONObject);
    mObject := TJSONObject(mValue);
    Assert.AreEqual('1h 25m', mObject.GetValue<string>('duration.presentation'));
    // Mittag des Tages in UTC: in jeder Zeitzone derselbe Tag.
    Assert.IsTrue(DateTimeToUnix(EncodeDateTime(2026, 10, 28, 12, 0, 0, 0), True) * 1000 =
      mObject.GetValue<Int64>('date'));
    Assert.AreEqual('Entwicklung', mObject.GetValue<string>('type.name'));
    Assert.AreEqual('Parser repariert', mObject.GetValue<string>('text'));
  finally
    mValue.Free;
  end;
  mJson := TAtlasYouTrackTracker.WorkItemJson(TAtlasTrackerWorkItem.Create(30, At(9, 0), '', ''));
  Assert.IsFalse(mJson.Contains('"type"'), 'ohne Arbeitstyp kein Feld');
  Assert.IsFalse(mJson.Contains('"text"'), 'ohne Beschreibung kein Feld');
end;

procedure TAtlasTrackerTimeWriterTests.BookTimeAgainstFakeTransport;
var
  mTransport: TFakeTimeTransport;
  mKeep: IAtlasCiTransport;
  mWriter: IAtlasTrackerTimeWriter;
  mResult: TAtlasTrackerWriteResult;
begin
  mWriter := TAtlasYouTrackTracker.Create;
  mTransport := TFakeTimeTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('POST', 'https://yt.beispiel.de/api/issues/ATL-123/timeTracking/workItems', 200, '{"id":"1"}');
  mResult := mWriter.BookTime(YouTrackTarget, mKeep, 'ATL-123',
    TAtlasTrackerWorkItem.Create(85, At(10, 0), 'Entwicklung', 'Text'), 5000);
  Assert.IsTrue(mResult.Succeeded);
  Assert.AreEqual(1, Integer(Length(mTransport.Calls)));
  Assert.IsTrue(mTransport.Bodies[0].Contains('"presentation":"1h 25m"'));
  // Ohne Dauer wird nichts gesendet.
  mResult := mWriter.BookTime(YouTrackTarget, mKeep, 'ATL-123',
    TAtlasTrackerWorkItem.Create(0, At(10, 0), '', ''), 5000);
  Assert.IsFalse(mResult.Succeeded);
  Assert.AreEqual(1, Integer(Length(mTransport.Calls)));
end;

procedure TAtlasTrackerTimeWriterTests.BookTimeErrors;
var
  mTransport: TFakeTimeTransport;
  mKeep: IAtlasCiTransport;
  mWriter: IAtlasTrackerTimeWriter;
  mResult: TAtlasTrackerWriteResult;
  mItem: TAtlasTrackerWorkItem;
begin
  mWriter := TAtlasYouTrackTracker.Create;
  mItem := TAtlasTrackerWorkItem.Create(30, At(10, 0), '', '');
  mTransport := TFakeTimeTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('POST', 'https://yt.beispiel.de/api/issues/', 400,
    '{"error":"bad_request","error_description":"Time tracking is disabled for the project"}');
  mResult := mWriter.BookTime(YouTrackTarget, mKeep, 'ATL-123', mItem, 5000);
  Assert.AreEqual(Ord(TAtlasCiFetchError.Invalid), Ord(mResult.Error));
  Assert.IsTrue(mWriter.IsTrackingOff(mResult), 'Zeiterfassung im Projekt aus');
  Assert.AreEqual(1, Integer(Length(mTransport.Calls)), 'nichts wird wiederholt');
  mTransport := TFakeTimeTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('POST', 'https://yt.beispiel.de/api/issues/', 403, '{"error_description":"Keine Rechte"}');
  mResult := mWriter.BookTime(YouTrackTarget, mKeep, 'ATL-123', mItem, 5000);
  Assert.AreEqual(Ord(TAtlasCiFetchError.Unauthorized), Ord(mResult.Error));
  Assert.AreEqual(403, mResult.Status);
  Assert.IsFalse(mWriter.IsTrackingOff(mResult));
end;

procedure TAtlasTrackerTimeWriterTests.TimeSettingsOfProject;
var
  mTransport: TFakeTimeTransport;
  mKeep: IAtlasCiTransport;
  mWriter: IAtlasTrackerTimeWriter;
  mSettings: TAtlasTrackerTimeSettings;
begin
  mWriter := TAtlasYouTrackTracker.Create;
  mTransport := TFakeTimeTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('GET', 'https://yt.beispiel.de/api/admin/projects/ATL/timeTrackingSettings', 200,
    '{"enabled":false,"workItemTypes":[{"name":"Entwicklung"},{"name":"Test"}]}');
  Assert.IsTrue(mWriter.TimeSettings(YouTrackTarget, mKeep, 'ATL-123', 5000, mSettings).Succeeded);
  Assert.IsFalse(mSettings.Enabled);
  Assert.AreEqual(2, Integer(Length(mSettings.WorkTypes)));
  Assert.AreEqual('Test', mSettings.WorkTypes[1]);
  Assert.AreEqual('ATL', TAtlasYouTrackTracker.ProjectOfKey('ATL-123'));
  Assert.AreEqual('MY-PRJ', TAtlasYouTrackTracker.ProjectOfKey('MY-PRJ-7'));
  Assert.AreEqual('', TAtlasYouTrackTracker.ProjectOfKey('123'));
end;

procedure TAtlasTrackerTimeWriterTests.TimeSettingsWithoutProjectRights;
var
  mTransport: TFakeTimeTransport;
  mKeep: IAtlasCiTransport;
  mWriter: IAtlasTrackerTimeWriter;
  mSettings: TAtlasTrackerTimeSettings;
begin
  mWriter := TAtlasYouTrackTracker.Create;
  mTransport := TFakeTimeTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('GET', 'https://yt.beispiel.de/api/admin/projects/', 403, '{"error":"Forbidden"}');
  mTransport.Answer('GET', 'https://yt.beispiel.de/api/admin/timeTrackingSettings/workItemTypes', 200,
    '[{"name":"Entwicklung"}]');
  Assert.IsTrue(mWriter.TimeSettings(YouTrackTarget, mKeep, 'ATL-123', 5000, mSettings).Succeeded);
  Assert.IsTrue(mSettings.Enabled, 'unbekannt gilt als an');
  Assert.AreEqual(1, Integer(Length(mSettings.WorkTypes)));
  Assert.AreEqual(2, Integer(Length(mTransport.Calls)));
end;

end.
