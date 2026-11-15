unit Atlas.Core.Tracker.NotifyPlan.Tests;

// Entscheidungen der Meldungen zu meinen Issues (#1271, #1967) ohne IDE: Fälligkeit, Anmeldename, Fehlermeldung,
// Ein- und Ausschalten, Tracker und Sprungstelle einer Meldung, Punkte je Tracker.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasNotifyPlanTests = class
  public
    [Test]
    procedure DueFollowsTickOrDemand;
    [Test]
    procedure AsksLoginOnceWithProbe;
    [Test]
    procedure ReportsFirstErrorNotCancel;
    /// <summary>Beim Einschalten gilt „jetzt“: Altes kommt nicht als neu, Punkte und Last-Modified verschwinden.
    /// </summary>
    [Test]
    procedure SwitchResetsConnections;
    [Test]
    procedure NoticeTargetUsesNoticeRepository;
    /// <summary>#2127: Wieder geöffnet springt zum Kommentar seit dem Beenden.</summary>
    [Test]
    procedure AnchorPrefersReopenComment;
    [Test]
    procedure UnseenPerRepository;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Notify,
  Atlas.Core.Tracker.NotifyPlan,
  Atlas.Core.Tracker.Reopened;

function Unseen(const AKey, AProject: string; AAnchor: TDateTime): TAtlasTrackerUnseen;
begin
  Result := Default(TAtlasTrackerUnseen);
  Result.Key := AKey;
  Result.Project := AProject;
  Result.Anchor := AAnchor;
end;

function Repository(const AProject: string): TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create(TAtlasTrackerTarget.cGitHub, '', AProject, '');
end;

{ TAtlasNotifyPlanTests }

procedure TAtlasNotifyPlanTests.DueFollowsTickOrDemand;
var
  mPlan, mDirect: TAtlasTrackerNotifySchedule;
begin
  mPlan := Default(TAtlasTrackerNotifySchedule);
  mPlan.Started(1000);
  mDirect := mPlan;
  Assert.AreEqual(Integer(Ord(mDirect.Due(400000, True, 5))),
    Integer(Ord(TAtlasNotifyPlan.IsDue(mPlan, False, True, 400000, 5))));
  Assert.AreEqual(Integer(Ord(mDirect.Due(400000, False, 5))),
    Integer(Ord(TAtlasNotifyPlan.IsDue(mPlan, False, False, 400000, 5))));
  Assert.AreEqual(Integer(Ord(mDirect.DueOnDemand(2000))), Integer(Ord(TAtlasNotifyPlan.IsDue(mPlan, True, True, 2000,
    5))));
  Assert.AreEqual(Integer(Ord(mDirect.DueOnDemand(400000))),
    Integer(Ord(TAtlasNotifyPlan.IsDue(mPlan, True, False, 400000, 5))));
  Assert.IsFalse(TAtlasNotifyPlan.IsDue(mPlan, True, True, 2000, 5), 'eben erst gefragt');
end;

procedure TAtlasNotifyPlanTests.AsksLoginOnceWithProbe;
begin
  Assert.IsTrue(TAtlasNotifyPlan.AsksLogin('', 'https://api.github.com/user'));
  Assert.IsFalse(TAtlasNotifyPlan.AsksLogin('marco', 'https://api.github.com/user'), 'schon bekannt');
  Assert.IsFalse(TAtlasNotifyPlan.AsksLogin('', ''), 'Anbieter ohne Adresse');
end;

procedure TAtlasNotifyPlanTests.ReportsFirstErrorNotCancel;
begin
  Assert.IsTrue(TAtlasNotifyPlan.ReportsError(True, TAtlasCiFetchError.Network));
  Assert.IsFalse(TAtlasNotifyPlan.ReportsError(False, TAtlasCiFetchError.Network), 'schon gemeldet');
  Assert.IsFalse(TAtlasNotifyPlan.ReportsError(True, TAtlasCiFetchError.Cancelled));
end;

procedure TAtlasNotifyPlanTests.SwitchResetsConnections;
var
  mFile: TAtlasTrackerNotifyFile;
  mNow: TDateTime;
begin
  mNow := EncodeDateTime(2026, 11, 15, 10, 0, 0, 0);
  mFile := TAtlasTrackerNotifyFile.Empty;
  mFile.Put(TAtlasTrackerNotifyConnection.Create('github|https://github.com', IncDay(mNow, -3)));
  mFile.Connections[0].LastModified := 'Sat, 14 Nov 2026 10:00:00 GMT';
  mFile.Connections[0].Unseen := [Unseen('#12', 'owner/repo', 0)];
  Assert.IsFalse(TAtlasNotifyPlan.Switch(mFile, mFile.Enabled, mNow), 'unverändert');
  Assert.AreEqual(1, Integer(Length(mFile.Connections[0].Unseen)));
  Assert.IsTrue(TAtlasNotifyPlan.Switch(mFile, True, mNow));
  Assert.IsTrue(mFile.Enabled);
  Assert.AreEqual(Double(mNow), Double(mFile.Connections[0].Since), 1E-9);
  Assert.AreEqual('', mFile.Connections[0].LastModified);
  Assert.AreEqual(0, Integer(Length(mFile.Connections[0].Unseen)));
  Assert.IsTrue(TAtlasNotifyPlan.Switch(mFile, False, mNow));
  Assert.IsFalse(mFile.Enabled);
end;

procedure TAtlasNotifyPlanTests.NoticeTargetUsesNoticeRepository;
var
  mNotice: TAtlasTrackerNotice;
begin
  mNotice := Default(TAtlasTrackerNotice);
  mNotice.Key := '#12';
  Assert.AreEqual('owner/repo', TAtlasNotifyPlan.NoticeTarget(Repository('owner/repo'), mNotice).Project);
  mNotice.Project := 'owner/anders';
  Assert.AreEqual('owner/anders', TAtlasNotifyPlan.NoticeTarget(Repository('owner/repo'), mNotice).Project);
end;

procedure TAtlasNotifyPlanTests.AnchorPrefersReopenComment;
var
  mNotice: TAtlasTrackerNotice;
  mReopen: TAtlasTrackerReopen;
  mFirst, mComment: TDateTime;
begin
  mFirst := EncodeDateTime(2026, 11, 15, 9, 0, 0, 0);
  mComment := EncodeDateTime(2026, 11, 15, 9, 30, 0, 0);
  mNotice := Default(TAtlasTrackerNotice);
  mNotice.Anchor := mFirst;
  mReopen := Default(TAtlasTrackerReopen);
  Assert.AreEqual(Double(mFirst), Double(TAtlasNotifyPlan.NoticeAnchor(mNotice, True, mReopen)), 1E-9,
    'ohne Kommentar');
  mReopen.CommentAt := mComment;
  Assert.AreEqual(Double(mComment), Double(TAtlasNotifyPlan.NoticeAnchor(mNotice, True, mReopen)), 1E-9);
  Assert.AreEqual(Double(mFirst), Double(TAtlasNotifyPlan.NoticeAnchor(mNotice, False, mReopen)), 1E-9,
    'nicht wieder geöffnet');
end;

procedure TAtlasNotifyPlanTests.UnseenPerRepository;
var
  mConnection: TAtlasTrackerNotifyConnection;
  mAnchor: TDateTime;
begin
  mAnchor := EncodeDateTime(2026, 11, 15, 9, 0, 0, 0);
  mConnection := TAtlasTrackerNotifyConnection.Create('github|https://github.com', mAnchor);
  mConnection.Unseen := [Unseen('#12', 'owner/repo', mAnchor), Unseen('#13', 'owner/anders', 0),
    Unseen('#14', 'Owner/Repo', 0)];
  Assert.AreEqual('#12,#14', string.Join(',', TAtlasNotifyPlan.UnseenKeys(mConnection, Repository('owner/repo'))));
  Assert.AreEqual(Double(mAnchor), Double(TAtlasNotifyPlan.UnseenAnchor(mConnection, Repository('owner/repo'), '#12')),
    1E-9);
  Assert.AreEqual(Double(0), Double(TAtlasNotifyPlan.UnseenAnchor(mConnection, Repository('owner/repo'), '#13')),
    1E-9, 'anderes Repository');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasNotifyPlanTests);

end.
