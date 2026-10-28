unit Atlas.Core.Tracker.Notify.Tests;

// Meldungen zu meinen Issues (#1271) ohne IDE und Netz: Verbindung und Umfang,
// Takt mit Verdoppeln nach Fehlern (eigene Uhr), eine Meldung je Issue,
// eigene Änderungen, Punkte bis zum Öffnen und notify.json.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTrackerNotifyTests = class
  private
    FDir: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ConnectionIdPerProviderAndServer;
    [Test]
    procedure ScopeNamesAndSettings;
    [Test]
    procedure IntervalAndUserActive;
    /// <summary>Abnahme: Nach Fehlern verdoppelt sich der Abstand bis 60 Minuten; Erfolg setzt zurück.</summary>
    [Test]
    procedure BackoffDoublesUpToCap;
    [Test]
    procedure DueAndOnDemand;
    /// <summary>Abnahme: Ein Fehler wird einmal gemeldet, bis eine Abfrage wieder gelingt.</summary>
    [Test]
    procedure ErrorReportedOnce;
    [Test]
    procedure OwnChangesDropped;
    /// <summary>Abnahme: eine Meldung je Issue mit Kommentaren, Zuweisung und Zustand; neueste zuerst.</summary>
    [Test]
    procedure SummarizePerIssue;
    [Test]
    procedure SummarizeLimitsAndCountsRest;
    [Test]
    procedure NextSinceNeverGoesBack;
    [Test]
    procedure UnseenUntilOpened;
    [Test]
    procedure LoginFromProbe;
    [Test]
    procedure JsonRoundTrip;
    [Test]
    procedure LoadAndSave;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.DateUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Notify;

function At(AMinute: Integer): TDateTime;
begin
  Result := EncodeDateTime(2026, 1, 1, 10, AMinute, 0, 0);
end;

function Change(const AKey: string; AKind: TAtlasTrackerChangeKind; const AAuthor: string;
  AMinute: Integer): TAtlasTrackerChange;
begin
  Result := TAtlasTrackerChange.Create(AKey, AKind, AAuthor, At(AMinute));
  Result.Title := 'Titel ' + AKey;
end;

function Notice(const AKey: string; AAnchor: TDateTime): TAtlasTrackerNotice;
begin
  Result := Default(TAtlasTrackerNotice);
  Result.Key := AKey;
  Result.Anchor := AAnchor;
end;

{ TAtlasTrackerNotifyTests }

procedure TAtlasTrackerNotifyTests.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'AtlasNotifyTests' + IntToStr(Random(1000000)));
end;

procedure TAtlasTrackerNotifyTests.TearDown;
begin
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
  FDir := '';
end;

procedure TAtlasTrackerNotifyTests.ConnectionIdPerProviderAndServer;
var
  mFirst, mSecond: TAtlasTrackerTarget;
begin
  mFirst := TAtlasTrackerTarget.Create('youtrack', 'https://YouTrack.Firma.local/', 'ATL', '');
  mSecond := TAtlasTrackerTarget.Create('youtrack', 'https://youtrack.firma.local', 'WEB', 'for: me');
  Assert.AreEqual('youtrack|https://youtrack.firma.local', TAtlasTrackerNotify.ConnectionId(mFirst));
  Assert.AreEqual(TAtlasTrackerNotify.ConnectionId(mFirst), TAtlasTrackerNotify.ConnectionId(mSecond),
    'eine Verbindung je Server, gleich welches Projekt');
  Assert.AreEqual('github|https://github.com',
    TAtlasTrackerNotify.ConnectionId(TAtlasTrackerTarget.Create('github', '', 'beispiel/atlas', '')));
  Assert.AreEqual('', TAtlasTrackerNotify.ConnectionId(TAtlasTrackerTarget.Create('', '', '', '')));
  // Punkte: GitHub je Repository, YouTrack ohne (die Kennung enthält das Projekt).
  Assert.AreEqual('beispiel/atlas',
    TAtlasTrackerNotify.UnseenProject(TAtlasTrackerTarget.Create('github', '', 'beispiel/atlas', '')));
  Assert.AreEqual('', TAtlasTrackerNotify.UnseenProject(mFirst));
end;

procedure TAtlasTrackerNotifyTests.ScopeNamesAndSettings;
var
  mScope: TAtlasTrackerNotifyScope;
begin
  for mScope := Low(TAtlasTrackerNotifyScope) to High(TAtlasTrackerNotifyScope) do
    Assert.IsTrue(TAtlasTrackerNotify.ScopeOf(TAtlasTrackerNotify.ScopeName(mScope)) = mScope);
  Assert.IsTrue(TAtlasTrackerNotify.ScopeOf(' WATCHED ') = TAtlasTrackerNotifyScope.Watched);
  Assert.IsTrue(TAtlasTrackerNotify.ScopeOf('alles') = TAtlasTrackerNotifyScope.AssignedOrCreated, 'Vorgabe');
  // Die Einstellungen kennen den Kern der Meldungen nicht (A-09): dieselben Werte wie dort.
  Assert.AreEqual(TAtlasTrackerNotify.ScopeAssigned, TAtlasPluginSettings.IssuesNotifyAssigned);
  Assert.AreEqual(TAtlasTrackerNotify.ScopeAssignedOrCreated, TAtlasPluginSettings.IssuesNotifyAssignedOrCreated);
  Assert.AreEqual(TAtlasTrackerNotify.ScopeWatched, TAtlasPluginSettings.IssuesNotifyWatched);
  Assert.AreEqual(Integer(TAtlasTrackerNotify.MinInterval), Integer(TAtlasPluginSettings.MinIssuesNotifyMinutes));
  Assert.AreEqual(Integer(TAtlasTrackerNotify.DefaultInterval),
    Integer(TAtlasPluginSettings.DefaultIssuesNotifyMinutes));
end;

procedure TAtlasTrackerNotifyTests.IntervalAndUserActive;
begin
  Assert.AreEqual(2, TAtlasTrackerNotify.Interval(0));
  Assert.AreEqual(2, TAtlasTrackerNotify.Interval(1));
  Assert.AreEqual(15, TAtlasTrackerNotify.Interval(15));
  Assert.IsTrue(TAtlasTrackerNotify.UserActive(False, 0));
  Assert.IsTrue(TAtlasTrackerNotify.UserActive(False, 29 * 60000));
  Assert.IsFalse(TAtlasTrackerNotify.UserActive(False, 30 * 60000), '30 Minuten ohne Eingabe');
  Assert.IsFalse(TAtlasTrackerNotify.UserActive(True, 0), 'minimiert');
end;

procedure TAtlasTrackerNotifyTests.BackoffDoublesUpToCap;
var
  mSchedule: TAtlasTrackerNotifySchedule;
begin
  mSchedule := Default(TAtlasTrackerNotifySchedule);
  Assert.AreEqual(UInt64(10 * 60000), mSchedule.DelayMs(10));
  Assert.AreEqual(UInt64(2 * 60000), mSchedule.DelayMs(1), 'mindestens 2 Minuten');
  mSchedule.Failed;
  Assert.AreEqual(UInt64(20 * 60000), mSchedule.DelayMs(10));
  mSchedule.Failed;
  Assert.AreEqual(UInt64(40 * 60000), mSchedule.DelayMs(10));
  mSchedule.Failed;
  Assert.AreEqual(UInt64(60 * 60000), mSchedule.DelayMs(10), 'höchstens 60 Minuten');
  mSchedule.Failed;
  Assert.AreEqual(UInt64(60 * 60000), mSchedule.DelayMs(10));
  Assert.AreEqual(UInt64(90 * 60000), mSchedule.DelayMs(90), 'nie unter dem eingestellten Abstand');
  mSchedule.Succeeded(0);
  Assert.AreEqual(UInt64(10 * 60000), mSchedule.DelayMs(10), 'Erfolg setzt zurück');
  // GitHub X-Poll-Interval verlängert den Abstand.
  mSchedule.Succeeded(900);
  Assert.AreEqual(UInt64(15 * 60000), mSchedule.DelayMs(10));
  Assert.AreEqual(UInt64(20 * 60000), mSchedule.DelayMs(20));
end;

procedure TAtlasTrackerNotifyTests.DueAndOnDemand;
var
  mSchedule: TAtlasTrackerNotifySchedule;
begin
  mSchedule := Default(TAtlasTrackerNotifySchedule);
  Assert.IsTrue(mSchedule.Due(1000, True, 10), 'erste Abfrage gleich');
  Assert.IsFalse(mSchedule.Due(1000, False, 10), 'nur bei aktiver IDE');
  Assert.IsTrue(mSchedule.DueOnDemand(1000));
  mSchedule.Started(1000);
  Assert.IsFalse(mSchedule.Due(1000 + 9 * 60000, True, 10));
  Assert.IsTrue(mSchedule.Due(1000 + 10 * 60000, True, 10));
  Assert.IsFalse(mSchedule.DueOnDemand(1000 + 59000), 'höchstens einmal je Minute');
  Assert.IsTrue(mSchedule.DueOnDemand(1000 + 60000));
  // Zähler zurückgesetzt (Neustart des Rechners): wieder fällig.
  Assert.IsTrue(mSchedule.Due(500, True, 10));
  // Nach einem Fehler wartet auch das Öffnen von „Meine Issues“ den verlängerten Abstand ab.
  mSchedule.Failed;
  Assert.IsFalse(mSchedule.DueOnDemand(1000 + 60000));
  Assert.IsFalse(mSchedule.Due(1000 + 10 * 60000, True, 10));
  Assert.IsTrue(mSchedule.Due(1000 + 20 * 60000, True, 10));
end;

procedure TAtlasTrackerNotifyTests.ErrorReportedOnce;
var
  mSchedule: TAtlasTrackerNotifySchedule;
begin
  mSchedule := Default(TAtlasTrackerNotifySchedule);
  Assert.IsTrue(mSchedule.Failed, 'erster Fehler');
  Assert.IsFalse(mSchedule.Failed);
  Assert.IsFalse(mSchedule.Failed);
  mSchedule.Succeeded(0);
  Assert.IsTrue(mSchedule.Failed, 'nach einem Erfolg wieder');
end;

procedure TAtlasTrackerNotifyTests.OwnChangesDropped;
var
  mChanges: TArray<TAtlasTrackerChange>;
begin
  mChanges := [Change('ATL-1', TAtlasTrackerChangeKind.Comment, 'Marco', 1),
    Change('ATL-1', TAtlasTrackerChangeKind.Comment, 'anna', 2),
    Change('ATL-2', TAtlasTrackerChangeKind.State, 'marco', 3)];
  Assert.AreEqual(Integer(1), Integer(Length(TAtlasTrackerNotify.Foreign(mChanges, 'marco'))));
  Assert.AreEqual('anna', TAtlasTrackerNotify.Foreign(mChanges, 'marco')[0].Author);
  Assert.AreEqual(Integer(3), Integer(Length(TAtlasTrackerNotify.Foreign(mChanges, ''))), 'unbekannter Benutzer');
end;

procedure TAtlasTrackerNotifyTests.SummarizePerIssue;
var
  mChanges: TArray<TAtlasTrackerChange>;
  mNotices: TArray<TAtlasTrackerNotice>;
  mRest: Integer;
  mAssigned, mOther, mState: TAtlasTrackerChange;
begin
  mAssigned := Change('ATL-1', TAtlasTrackerChangeKind.Assigned, 'ben', 3);
  mAssigned.ToMe := True;
  mOther := Change('#7', TAtlasTrackerChangeKind.Other, '', 1);
  mOther.Project := 'beispiel/andere';
  mState := Change('ATL-2', TAtlasTrackerChangeKind.State, 'ben', 6);
  mState.Value := 'Fertig';
  mChanges := [Change('ATL-1', TAtlasTrackerChangeKind.Comment, 'anna', 5),
    Change('ATL-1', TAtlasTrackerChangeKind.Comment, 'ben', 2), mAssigned,
    Change('ATL-1', TAtlasTrackerChangeKind.Comment, 'anna', 4),
    mState, mOther];
  mChanges[0].AuthorName := 'Anna Muster';
  mChanges[3].AuthorName := 'Anna Muster';
  mNotices := TAtlasTrackerNotify.Summarize(mChanges, 10, mRest);
  Assert.AreEqual(0, mRest);
  Assert.AreEqual(Integer(3), Integer(Length(mNotices)), 'eine Meldung je Issue');
  // Neueste zuerst.
  Assert.AreEqual('ATL-2', mNotices[0].Key);
  Assert.AreEqual('Fertig', mNotices[0].State, 'Zustand');
  Assert.AreEqual('ATL-1', mNotices[1].Key);
  Assert.AreEqual(3, mNotices[1].Comments);
  Assert.AreEqual(Integer(2), Integer(Length(mNotices[1].CommentAuthors)), 'jeder Urheber einmal');
  Assert.AreEqual('ben', mNotices[1].CommentAuthors[0], 'in der Reihenfolge der Kommentare');
  Assert.AreEqual('Anna Muster', mNotices[1].CommentAuthors[1]);
  Assert.IsTrue(mNotices[1].AssignedToMe);
  Assert.IsFalse(mNotices[1].Other);
  Assert.AreEqual(At(2), mNotices[1].Anchor, 1 / SecsPerDay, 'Anker: erster neuer Kommentar');
  Assert.AreEqual(At(5), mNotices[1].Time, 1 / SecsPerDay);
  Assert.AreEqual('Titel ATL-1', mNotices[1].Title);
  Assert.AreEqual('#7', mNotices[2].Key);
  Assert.AreEqual('beispiel/andere', mNotices[2].Project);
  Assert.IsTrue(mNotices[2].Other, 'nur allgemeine Änderung');
  Assert.AreEqual(Double(0), Double(mNotices[2].Anchor));
end;

procedure TAtlasTrackerNotifyTests.SummarizeLimitsAndCountsRest;
var
  mChanges: TArray<TAtlasTrackerChange>;
  mNotices: TArray<TAtlasTrackerNotice>;
  mRest, mIndex: Integer;
  mState: TAtlasTrackerChange;
begin
  mChanges := nil;
  for mIndex := 1 to 13 do
    mChanges := mChanges + [Change('ATL-' + IntToStr(mIndex), TAtlasTrackerChangeKind.Comment, 'anna', mIndex)];
  // Gleiche Kennung in zwei Repositories: zwei Meldungen.
  mState := Change('#1', TAtlasTrackerChangeKind.State, 'ben', 30);
  mState.Project := 'beispiel/a';
  mState.Value := 'closed';
  mChanges := mChanges + [mState];
  mState.Project := 'beispiel/b';
  mChanges := mChanges + [mState];
  mNotices := TAtlasTrackerNotify.Summarize(mChanges, 10, mRest);
  Assert.AreEqual(Integer(10), Integer(Length(mNotices)));
  Assert.AreEqual(5, mRest, '15 Issues, 10 einzeln');
  // Gleichstand der Zeit: nach Projekt und Kennung.
  Assert.AreEqual('beispiel/a', mNotices[0].Project);
  Assert.AreEqual('beispiel/b', mNotices[1].Project);
  Assert.AreEqual('ATL-13', mNotices[2].Key);
  Assert.AreEqual('closed', mNotices[0].State);
end;

procedure TAtlasTrackerNotifyTests.NextSinceNeverGoesBack;
begin
  Assert.AreEqual(At(5), TAtlasTrackerNotify.NextSince(At(1), At(5)), 1 / SecsPerDay);
  Assert.AreEqual(At(5), TAtlasTrackerNotify.NextSince(At(5), At(1)), 1 / SecsPerDay, 'falsch gehende Uhr');
  Assert.AreEqual(At(5), TAtlasTrackerNotify.NextSince(At(5), 0), 1 / SecsPerDay, 'nichts gesehen');
end;

procedure TAtlasTrackerNotifyTests.UnseenUntilOpened;
var
  mConnection: TAtlasTrackerNotifyConnection;
  mNotices: TArray<TAtlasTrackerNotice>;
  mIndex: Integer;
begin
  mConnection := TAtlasTrackerNotify.Fresh('youtrack|https://youtrack.firma.local', At(0));
  Assert.AreEqual(At(0), mConnection.Since, 1 / SecsPerDay, 'beim Einschalten gilt jetzt');
  TAtlasTrackerNotify.MarkUnseen(mConnection, [Notice('ATL-1', At(2)), Notice('ATL-2', 0)]);
  Assert.AreEqual(Integer(2), Integer(Length(mConnection.Unseen)));
  // Später weitere Kommentare: der Anker bleibt der älteste ungesehene.
  TAtlasTrackerNotify.MarkUnseen(mConnection, [Notice('atl-1', At(7)), Notice('ATL-2', At(8))]);
  Assert.AreEqual(Integer(2), Integer(Length(mConnection.Unseen)));
  Assert.AreEqual(At(2), mConnection.Unseen[mConnection.IndexOfUnseen('ATL-1', '')].Anchor, 1 / SecsPerDay);
  Assert.AreEqual(At(8), mConnection.Unseen[mConnection.IndexOfUnseen('ATL-2', '')].Anchor, 1 / SecsPerDay,
    'erster Kommentar nach allgemeiner Änderung');
  Assert.IsTrue(TAtlasTrackerNotify.Seen(mConnection, 'Atl-1', ''));
  Assert.IsFalse(TAtlasTrackerNotify.Seen(mConnection, 'ATL-1', ''), 'nur einmal');
  Assert.AreEqual(-1, mConnection.IndexOfUnseen('ATL-1', ''));
  Assert.IsFalse(TAtlasTrackerNotify.Seen(mConnection, 'ATL-2', 'beispiel/atlas'), 'anderes Projekt');
  // Höchstens MaxUnseen: die ältesten fallen heraus.
  mNotices := nil;
  for mIndex := 1 to TAtlasTrackerNotify.MaxUnseen + 5 do
    mNotices := mNotices + [Notice('WEB-' + IntToStr(mIndex), 0)];
  TAtlasTrackerNotify.MarkUnseen(mConnection, mNotices);
  Assert.AreEqual(Integer(TAtlasTrackerNotify.MaxUnseen), Integer(Length(mConnection.Unseen)));
  Assert.AreEqual(-1, mConnection.IndexOfUnseen('ATL-2', ''));
  Assert.IsTrue(mConnection.IndexOfUnseen('WEB-55', '') >= 0);
end;

procedure TAtlasTrackerNotifyTests.LoginFromProbe;
begin
  Assert.AreEqual('marco', TAtlasTrackerNotify.LoginOf('{"login":" marco ","$type":"Me"}'));
  Assert.AreEqual('', TAtlasTrackerNotify.LoginOf('{"name":"x"}'));
  Assert.AreEqual('', TAtlasTrackerNotify.LoginOf('<html></html>'));
  Assert.AreEqual('', TAtlasTrackerNotify.LoginOf('[]'));
end;

procedure TAtlasTrackerNotifyTests.JsonRoundTrip;
var
  mFile, mRead: TAtlasTrackerNotifyFile;
  mConnection: TAtlasTrackerNotifyConnection;
begin
  mFile := TAtlasTrackerNotifyFile.Empty;
  mFile.Enabled := True;
  mConnection := TAtlasTrackerNotify.Fresh('github|https://github.com', At(3));
  mConnection.Me := 'marco';
  mConnection.LastModified := 'Thu, 01 Jan 2026 10:03:00 GMT';
  TAtlasTrackerNotify.MarkUnseen(mConnection, [Notice('#12', At(2))]);
  mConnection.Unseen[0].Project := 'beispiel/atlas';
  mFile.Put(mConnection);
  mFile.Put(TAtlasTrackerNotify.Fresh('youtrack|https://youtrack.firma.local', At(1)));
  // Put ersetzt eine vorhandene Verbindung.
  mFile.Put(mConnection);
  Assert.AreEqual(Integer(2), Integer(Length(mFile.Connections)));
  Assert.IsTrue(TAtlasTrackerNotify.FromJson(TAtlasTrackerNotify.ToJson(mFile), mRead));
  Assert.IsTrue(mRead.Enabled);
  Assert.AreEqual(Integer(2), Integer(Length(mRead.Connections)));
  Assert.IsTrue(mRead.Find('GITHUB|https://github.com', mConnection), 'ohne Groß-/Kleinschreibung');
  Assert.AreEqual(At(3), mConnection.Since, 1 / SecsPerDay);
  Assert.AreEqual('marco', mConnection.Me);
  Assert.AreEqual('Thu, 01 Jan 2026 10:03:00 GMT', mConnection.LastModified);
  Assert.AreEqual(Integer(1), Integer(Length(mConnection.Unseen)));
  Assert.AreEqual('#12', mConnection.Unseen[0].Key);
  Assert.AreEqual('beispiel/atlas', mConnection.Unseen[0].Project);
  Assert.AreEqual(At(2), mConnection.Unseen[0].Anchor, 1 / SecsPerDay);
  Assert.IsFalse(mRead.Find('jira|x', mConnection));
  Assert.AreEqual(Double(0), Double(mConnection.Since), 'unbekannt: ohne Stand');
  // Andere Version oder kaputt: wie ohne Datei.
  Assert.IsFalse(TAtlasTrackerNotify.FromJson('{"version":2,"enabled":true}', mRead));
  Assert.IsFalse(mRead.Enabled);
  Assert.IsFalse(TAtlasTrackerNotify.FromJson('kaputt', mRead));
  // Verbindung ohne Stand fällt heraus.
  Assert.IsTrue(TAtlasTrackerNotify.FromJson('{"version":1,"connections":[{"id":"github|x"}]}', mRead));
  Assert.AreEqual(Integer(0), Integer(Length(mRead.Connections)));
end;

procedure TAtlasTrackerNotifyTests.LoadAndSave;
var
  mFile, mRead: TAtlasTrackerNotifyFile;
begin
  mRead := TAtlasTrackerNotify.Load(FDir);
  Assert.IsFalse(mRead.Enabled, 'ohne Datei');
  Assert.AreEqual(Integer(0), Integer(Length(mRead.Connections)));
  mFile := TAtlasTrackerNotifyFile.Empty;
  mFile.Enabled := True;
  mFile.Put(TAtlasTrackerNotify.Fresh('github|https://github.com', At(4)));
  Assert.IsTrue(TAtlasTrackerNotify.Save(FDir, mFile), 'legt den Ordner an');
  Assert.IsFalse(TFile.Exists(TPath.Combine(FDir, TAtlasTrackerNotify.FileName + '.tmp')), 'keine Zwischendatei');
  mRead := TAtlasTrackerNotify.Load(FDir);
  Assert.IsTrue(mRead.Enabled);
  Assert.AreEqual(Integer(1), Integer(Length(mRead.Connections)));
  Assert.IsTrue(TAtlasTrackerNotify.Save(FDir, mRead), 'überschreibt');
  TFile.WriteAllText(TPath.Combine(FDir, TAtlasTrackerNotify.FileName), 'kaputt');
  Assert.IsFalse(TAtlasTrackerNotify.Load(FDir).Enabled, 'kaputt: wie ohne Datei');
  Assert.IsFalse(TAtlasTrackerNotify.Save('', mFile));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerNotifyTests);

end.
