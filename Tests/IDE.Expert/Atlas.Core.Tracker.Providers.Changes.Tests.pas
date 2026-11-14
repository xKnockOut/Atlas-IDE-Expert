unit Atlas.Core.Tracker.Providers.Changes.Tests;

// Änderungen an Issues seit einem Zeitpunkt (Benachrichtigungen): YouTrack-Aktivitäten und GitHub-Benachrichtigungen
// aus Beispieldateien, Bereich und Adressen, Abruf über einen Transport mit festen Antworten und Fehler.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasTrackerChangesTests = class
  public
    [Test]
    procedure YouTrackScopeAndUrls;
    [Test]
    procedure YouTrackChangedIssues;
    /// <summary>Abnahme: Kommentar, Zuweisung an mich und Zustand; andere Felder, alte und leere Einträge nicht.
    /// </summary>
    [Test]
    procedure YouTrackActivities;
    [Test]
    procedure YouTrackChangesOverTransport;
    [Test]
    procedure GitHubNotificationsOnlyIssues;
    [Test]
    procedure GitHubScope;
    [Test]
    procedure GitHubCommentsAndEvents;
    [Test]
    procedure GitHubChangesOverTransport;
    [Test]
    procedure ChangesErrors;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.DateUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Providers.GitHub,
  Atlas.Core.Tracker.Providers.YouTrack,
  Atlas.Text.Uris,
  Atlas.Core.Tracker.Internals.GitHubApi,
  Atlas.Core.Tracker.GitHubParse,
  Atlas.Core.Tracker.YouTrackApi,
  Atlas.Core.Tracker.YouTrackParse,
  Atlas.Core.Tracker.TestSupport;

{ TAtlasTrackerChangesTests }

/// <summary>Stand der Beispiele: 31.12.2025 12:00 UTC.</summary>
function Since: TDateTime;
begin
  Result := EncodeDateTime(2025, 12, 31, 12, 0, 0, 0);
end;

function GitHubThread(const ARepository: string; ANumber: Integer): TAtlasGitHubThread;
begin
  Result := Default(TAtlasGitHubThread);
  Result.Repository := ARepository;
  Result.Number := ANumber;
  Result.Title := 'Absturz beim Speichern';
  Result.Reason := 'assign';
end;

procedure TAtlasTrackerChangesTests.YouTrackScopeAndUrls;
var
  mUrl: string;
begin
  Assert.AreEqual('for: me', TAtlasYouTrackApi.ScopeQuery(TAtlasTrackerNotifyScope.Assigned));
  Assert.AreEqual('(for: me or reporter: me)',
    TAtlasYouTrackApi.ScopeQuery(TAtlasTrackerNotifyScope.AssignedOrCreated));
  Assert.AreEqual('(for: me or reporter: me or has: star)',
    TAtlasYouTrackApi.ScopeQuery(TAtlasTrackerNotifyScope.Watched));
  mUrl := TAtlasYouTrackApi.ChangedIssuesUrl(YouTrackTarget, Since, TAtlasTrackerNotifyScope.AssignedOrCreated);
  Assert.IsTrue(mUrl.StartsWith('https://beispiel.youtrack.cloud/api/issues?query='), mUrl);
  // Einen Tag früher (Zeitzone des Servers); ohne Projekt: alle Projekte der Verbindung.
  Assert.IsTrue(Pos(TTextUris.PercentEncode('(for: me or reporter: me) updated: 2025-12-30 .. *'), mUrl) > 0, mUrl);
  Assert.AreEqual('', TAtlasYouTrackApi.ChangedIssuesUrl(TAtlasTrackerTarget.Create('youtrack', '', '', ''),
    Since, TAtlasTrackerNotifyScope.Assigned));
  mUrl := TAtlasYouTrackApi.ActivitiesUrl(YouTrackTarget, 'ATL-1', Since);
  Assert.IsTrue(mUrl.StartsWith('https://beispiel.youtrack.cloud/api/issues/ATL-1/activities?categories='), mUrl);
  Assert.IsTrue(Pos('&start=1767182400001&', mUrl) > 0, 'Millisekunden nach dem Stand: ' + mUrl);
  Assert.AreEqual('', TAtlasYouTrackApi.ActivitiesUrl(YouTrackTarget, 'ATL 1/../x', Since), 'ungültige Kennung');
end;

procedure TAtlasTrackerChangesTests.YouTrackChangedIssues;
var
  mIssues: TArray<TAtlasTrackerChange>;
begin
  Assert.IsTrue(TAtlasYouTrackParse.ParseChangedIssues(Fixture('YouTrack', 'changed-issues.json'), Since,
    mIssues));
  Assert.AreEqual(Integer(1), Integer(Length(mIssues)), 'nur nach dem Stand und mit gültiger Kennung');
  Assert.AreEqual('ATL-1', mIssues[0].Key);
  Assert.AreEqual('Absturz beim Speichern', mIssues[0].Title);
  Assert.AreEqual<TAtlasTrackerChangeKind>(TAtlasTrackerChangeKind.Other, mIssues[0].Kind);
  Assert.AreEqual(EncodeDateTime(2026, 1, 1, 0, 4, 0, 0), mIssues[0].Time, 1 / MSecsPerDay);
  Assert.IsFalse(TAtlasYouTrackParse.ParseChangedIssues('{"error":"x"}', Since, mIssues));
end;

procedure TAtlasTrackerChangesTests.YouTrackActivities;
var
  mChanges: TArray<TAtlasTrackerChange>;
begin
  Assert.IsTrue(TAtlasYouTrackParse.ParseActivities(Fixture('YouTrack', 'activities.json'), 'ATL-1', 'Titel',
    'marco', Since, mChanges));
  Assert.AreEqual(Integer(3), Integer(Length(mChanges)));
  Assert.AreEqual<TAtlasTrackerChangeKind>(TAtlasTrackerChangeKind.Comment, mChanges[0].Kind);
  Assert.AreEqual('anna', mChanges[0].Author);
  Assert.AreEqual('Anna Muster', mChanges[0].Who);
  Assert.AreEqual('ATL-1', mChanges[0].Key);
  Assert.AreEqual('Titel', mChanges[0].Title);
  Assert.AreEqual<TAtlasTrackerChangeKind>(TAtlasTrackerChangeKind.Assigned, mChanges[1].Kind);
  Assert.AreEqual('Marco B.', mChanges[1].Value);
  Assert.IsTrue(mChanges[1].ToMe, 'an den angemeldeten Benutzer');
  Assert.AreEqual<TAtlasTrackerChangeKind>(TAtlasTrackerChangeKind.State, mChanges[2].Kind);
  Assert.AreEqual('Fertig', mChanges[2].Value);
  // #2127: Zustand davor und Text des Kommentars.
  Assert.AreEqual('Zur Prüfung', mChanges[2].Previous);
  Assert.AreEqual('Bitte prüfen', mChanges[0].Text);
  // Ohne bekannten Benutzer: keine Zuweisung „an mich“.
  Assert.IsTrue(TAtlasYouTrackParse.ParseActivities(Fixture('YouTrack', 'activities.json'), 'ATL-1', 'Titel',
    '', Since, mChanges));
  Assert.IsFalse(mChanges[1].ToMe);
  Assert.IsFalse(TAtlasYouTrackParse.ParseActivities('kein JSON', 'ATL-1', '', '', Since, mChanges));
end;

procedure TAtlasTrackerChangesTests.YouTrackChangesOverTransport;
var
  mTransport: TFakeTransport;
  mTransportRef: IAtlasCiTransport;
  mProvider: IAtlasTrackerProvider;
  mPoll: TAtlasTrackerPoll;
  mChanges: TArray<TAtlasTrackerChange>;
  mError: TAtlasCiFetchError;
begin
  mProvider := TAtlasYouTrackTracker.Create;
  mTransport := TFakeTransport.Create;
  mTransportRef := mTransport;
  mTransport.Answer('https://beispiel.youtrack.cloud/api/issues?', 200, Fixture('YouTrack', 'changed-issues.json'));
  mTransport.Answer('https://beispiel.youtrack.cloud/api/issues/ATL-1/activities', 200,
    Fixture('YouTrack', 'activities.json'));
  mPoll := TAtlasTrackerPoll.Create(Since, 'marco', TAtlasTrackerNotifyScope.Assigned);
  Assert.IsTrue(mProvider.Changes(YouTrackTarget, mTransportRef, 5000, mPoll, mChanges, mError));
  Assert.AreEqual(Integer(3), Integer(Length(mChanges)));
  Assert.AreEqual('Absturz beim Speichern', mChanges[0].Title, 'Titel aus der Liste');
  Assert.AreEqual(EncodeDateTime(2026, 1, 1, 0, 4, 0, 0), mPoll.Latest, 1 / MSecsPerDay, 'neuester Stand');
  Assert.AreEqual(Integer(2), Integer(Length(mTransport.Calls)));
  Assert.IsTrue(Pos(TTextUris.PercentEncode('for: me updated:'), mTransport.Calls[0]) > 0, 'Umfang Assigned');
  // Aktivitäten nicht lesbar: das Issue meldet sich ohne Einzelheiten.
  mTransport := TFakeTransport.Create;
  mTransportRef := mTransport;
  mTransport.Answer('https://beispiel.youtrack.cloud/api/issues?', 200, Fixture('YouTrack', 'changed-issues.json'));
  mPoll := TAtlasTrackerPoll.Create(Since, 'marco', TAtlasTrackerNotifyScope.Assigned);
  Assert.IsTrue(mProvider.Changes(YouTrackTarget, mTransportRef, 5000, mPoll, mChanges, mError));
  Assert.AreEqual(Integer(1), Integer(Length(mChanges)));
  Assert.AreEqual<TAtlasTrackerChangeKind>(TAtlasTrackerChangeKind.Other, mChanges[0].Kind);
end;

procedure TAtlasTrackerChangesTests.GitHubNotificationsOnlyIssues;
var
  mThreads: TArray<TAtlasGitHubThread>;
begin
  Assert.AreEqual('https://api.github.com/notifications?since=' + TTextUris.PercentEncode('2025-12-31T12:00:00Z') +
    '&per_page=50', TAtlasGitHubApi.NotificationsUrl(GitHubTarget, Since));
  Assert.IsTrue(TAtlasGitHubParse.ParseNotifications(Fixture('GitHub', 'notifications.json'), Since, mThreads));
  Assert.AreEqual(Integer(2), Integer(Length(mThreads)), 'ohne Pull Request und ohne alte');
  Assert.AreEqual('beispiel/atlas', mThreads[0].Repository);
  Assert.AreEqual(12, mThreads[0].Number);
  Assert.AreEqual('assign', mThreads[0].Reason);
  Assert.AreEqual('Absturz beim Speichern', mThreads[0].Title);
  Assert.AreEqual('beispiel/andere', mThreads[1].Repository, 'alle Repositories des Servers');
  Assert.AreEqual(7, mThreads[1].Number);
  Assert.AreEqual('subscribed', mThreads[1].Reason);
  Assert.IsFalse(TAtlasGitHubParse.ParseNotifications('{}', Since, mThreads));
end;

procedure TAtlasTrackerChangesTests.GitHubScope;
begin
  Assert.IsTrue(TAtlasGitHubParse.InScope('assign', TAtlasTrackerNotifyScope.Assigned));
  Assert.IsFalse(TAtlasGitHubParse.InScope('author', TAtlasTrackerNotifyScope.Assigned));
  Assert.IsTrue(TAtlasGitHubParse.InScope('author', TAtlasTrackerNotifyScope.AssignedOrCreated));
  Assert.IsFalse(TAtlasGitHubParse.InScope('subscribed', TAtlasTrackerNotifyScope.AssignedOrCreated));
  Assert.IsTrue(TAtlasGitHubParse.InScope('subscribed', TAtlasTrackerNotifyScope.Watched));
  Assert.IsTrue(TAtlasGitHubParse.InScope('mention', TAtlasTrackerNotifyScope.Watched));
end;

procedure TAtlasTrackerChangesTests.GitHubCommentsAndEvents;
var
  mChanges: TArray<TAtlasTrackerChange>;
begin
  Assert.IsTrue(TAtlasGitHubParse.ParseCommentChanges(Fixture('GitHub', 'issue-comments-since.json'),
    GitHubThread('beispiel/atlas', 12), Since, mChanges));
  Assert.AreEqual(Integer(2), Integer(Length(mChanges)), 'nur nach dem Stand angelegte');
  Assert.AreEqual('#12', mChanges[0].Key);
  Assert.AreEqual('beispiel/atlas', mChanges[0].Project);
  Assert.AreEqual('anna', mChanges[0].Author);
  Assert.AreEqual<TAtlasTrackerChangeKind>(TAtlasTrackerChangeKind.Comment, mChanges[0].Kind);
  Assert.AreEqual('marco', mChanges[1].Author);
  Assert.AreNotEqual('', mChanges[0].Text, '#2127: Text des Kommentars');
  Assert.IsTrue(TAtlasGitHubParse.ParseEventChanges(Fixture('GitHub', 'issue-events.json'),
    GitHubThread('beispiel/atlas', 12), 'Marco', Since, mChanges));
  Assert.AreEqual(Integer(2), Integer(Length(mChanges)), 'labeled und alte Ereignisse nicht');
  Assert.AreEqual<TAtlasTrackerChangeKind>(TAtlasTrackerChangeKind.Assigned, mChanges[0].Kind);
  Assert.AreEqual('marco', mChanges[0].Value);
  Assert.IsTrue(mChanges[0].ToMe, 'Anmeldename ohne Groß-/Kleinschreibung');
  Assert.AreEqual('ben', mChanges[0].Author);
  Assert.AreEqual<TAtlasTrackerChangeKind>(TAtlasTrackerChangeKind.State, mChanges[1].Kind);
  Assert.AreEqual('closed', mChanges[1].Value);
  Assert.AreEqual('open', mChanges[1].Previous, '#2127: Zustand davor');
  Assert.IsFalse(TAtlasGitHubParse.ParseEventChanges('nichts', GitHubThread('beispiel/atlas', 12), '', Since,
    mChanges));
end;

procedure TAtlasTrackerChangesTests.GitHubChangesOverTransport;
var
  mTransport: TFakeTransport;
  mTransportRef: IAtlasCiTransport;
  mProvider: IAtlasTrackerProvider;
  mPoll: TAtlasTrackerPoll;
  mChanges: TArray<TAtlasTrackerChange>;
  mError: TAtlasCiFetchError;
begin
  mProvider := TAtlasGitHubTracker.Create;
  mTransport := TFakeTransport.Create;
  mTransportRef := mTransport;
  mTransport.Answer('https://api.github.com/notifications', 200, Fixture('GitHub', 'notifications.json'));
  mTransport.Answer('https://api.github.com/repos/beispiel/atlas/issues/12/comments', 200,
    Fixture('GitHub', 'issue-comments-since.json'));
  mTransport.Answer('https://api.github.com/repos/beispiel/atlas/issues/12/events', 200,
    Fixture('GitHub', 'issue-events.json'));
  mPoll := TAtlasTrackerPoll.Create(Since, 'marco', TAtlasTrackerNotifyScope.Watched);
  Assert.IsTrue(mProvider.Changes(GitHubTarget, mTransportRef, 5000, mPoll, mChanges, mError));
  // #12: zwei Kommentare, Zuweisung, geschlossen; #7 (beobachtet, ohne Einzelheiten): allgemeine Änderung.
  Assert.AreEqual(Integer(5), Integer(Length(mChanges)));
  Assert.AreEqual<TAtlasTrackerChangeKind>(TAtlasTrackerChangeKind.Other, mChanges[4].Kind);
  Assert.AreEqual('#7', mChanges[4].Key);
  Assert.AreEqual('beispiel/andere', mChanges[4].Project);
  Assert.AreEqual(EncodeDateTime(2026, 1, 1, 0, 2, 0, 0), mPoll.Latest, 1 / MSecsPerDay);
  // Umfang „zugewiesen oder erstellt“: #7 entfällt, der Stand rückt trotzdem vor.
  mPoll := TAtlasTrackerPoll.Create(Since, 'marco', TAtlasTrackerNotifyScope.AssignedOrCreated);
  Assert.IsTrue(mProvider.Changes(GitHubTarget, mTransportRef, 5000, mPoll, mChanges, mError));
  Assert.AreEqual(Integer(4), Integer(Length(mChanges)));
  Assert.AreEqual(EncodeDateTime(2026, 1, 1, 0, 2, 0, 0), mPoll.Latest, 1 / MSecsPerDay);
end;

procedure TAtlasTrackerChangesTests.ChangesErrors;
var
  mTransport: TFakeTransport;
  mTransportRef: IAtlasCiTransport;
  mProvider: IAtlasTrackerProvider;
  mPoll: TAtlasTrackerPoll;
  mChanges: TArray<TAtlasTrackerChange>;
  mError: TAtlasCiFetchError;
begin
  mProvider := TAtlasGitHubTracker.Create;
  mPoll := TAtlasTrackerPoll.Create(Since, '', TAtlasTrackerNotifyScope.Watched);
  Assert.IsFalse(mProvider.Changes(GitHubTarget, nil, 5000, mPoll, mChanges, mError));
  Assert.AreEqual<TAtlasCiFetchError>(TAtlasCiFetchError.NotConfigured, mError, 'ohne Token');
  mTransport := TFakeTransport.Create;
  mTransportRef := mTransport;
  mTransport.Answer('https://api.github.com/notifications', 401, '{}');
  Assert.IsFalse(mProvider.Changes(GitHubTarget, mTransportRef, 5000, mPoll, mChanges, mError));
  Assert.AreEqual<TAtlasCiFetchError>(TAtlasCiFetchError.Unauthorized, mError);
  mTransport.FailWith(TAtlasCiFetchError.Timeout);
  Assert.IsFalse(mProvider.Changes(GitHubTarget, mTransportRef, 5000, mPoll, mChanges, mError));
  Assert.AreEqual<TAtlasCiFetchError>(TAtlasCiFetchError.Timeout, mError);
  mProvider := TAtlasYouTrackTracker.Create;
  mTransport := TFakeTransport.Create;
  mTransportRef := mTransport;
  mTransport.Answer('https://beispiel.youtrack.cloud/api/issues?', 200, '<html>Anmeldung</html>');
  Assert.IsFalse(mProvider.Changes(YouTrackTarget, mTransportRef, 5000, mPoll, mChanges, mError));
  Assert.AreEqual<TAtlasCiFetchError>(TAtlasCiFetchError.Invalid, mError, 'Anmeldeseite statt JSON');
  Assert.AreEqual<TDateTime>(Since, mPoll.Since, 'Stand unverändert');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerChangesTests);

end.
