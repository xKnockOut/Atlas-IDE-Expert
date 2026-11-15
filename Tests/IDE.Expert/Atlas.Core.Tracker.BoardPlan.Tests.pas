unit Atlas.Core.Tracker.BoardPlan.Tests;

// Entscheidungen des Fensters „Atlas-Board“ (#1272, #1967) ohne Fenster: Anzeige nach dem Laden, Grund je
// Fehler, Karten aus anderen Repositories, Prüfung vor dem Ziehen, Übergänge in der Fehlermeldung und
// Aktualisieren.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasBoardPlanTests = class
  public
    [Test]
    procedure LoadViewFreshCachedNoticeSilent;
    [Test]
    procedure ReasonPerError;
    /// <summary>GitHub „owner/repo#12“: nur im Browser, kein Beginnen und kein Zuweisen.</summary>
    [Test]
    procedure ForeignCardsOnlyInBrowser;
    [Test]
    procedure BrowsePagePrefersProvider;
    [Test]
    procedure TargetChangedIgnoresCase;
    [Test]
    procedure MoveCheckLockedAndWorkflow;
    [Test]
    procedure TransitionsOnlyWhenRejectedUnderStateMachine;
    [Test]
    procedure RefreshesOnlyWhenIdle;
  end;

implementation

uses
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Board,
  Atlas.Core.Tracker.BoardPlan;

function PlanCard(const AKey, AState: string): TAtlasBoardCard;
begin
  Result := Default(TAtlasBoardCard);
  Result.Key := AKey;
  Result.State := AState;
end;

/// <summary>Drei Spalten, eine Karte in „Offen“ unter einer Zustandsmaschine mit dem Übergang „in-arbeit“.
/// </summary>
function PlanSnapshot: TAtlasBoardSnapshot;
begin
  Result := TAtlasBoardSnapshot.Empty;
  Result.Columns := [TAtlasBoardColumn.Create('Offen', TArray<string>.Create('Offen'), '', False),
    TAtlasBoardColumn.Create('In Arbeit', TArray<string>.Create('In Arbeit'), '', False),
    TAtlasBoardColumn.Create('Erledigt', TArray<string>.Create('Erledigt'), '', True)];
  Result.Cards := [PlanCard('ATL-1', 'Offen')];
  Result.Cards[0].Workflow.StateMachine := True;
  Result.Cards[0].Workflow.FieldId := '82-11';
  Result.Cards[0].Workflow.Transitions := [TAtlasTrackerTransition.Create('in-arbeit', '')];
end;

function ViewOf(ASucceeded, ADenied, ACache: Boolean; AError: TAtlasCiFetchError): Integer;
begin
  Result := Ord(TAtlasBoardPlan.LoadView(ASucceeded, ADenied, ACache, AError));
end;

{ TAtlasBoardPlanTests }

procedure TAtlasBoardPlanTests.LoadViewFreshCachedNoticeSilent;
begin
  Assert.AreEqual(Integer(Ord(TAtlasBoardLoadView.Fresh)), ViewOf(True, False, True, TAtlasCiFetchError.None));
  Assert.AreEqual(Integer(Ord(TAtlasBoardLoadView.FreshDenied)), ViewOf(True, True, False,
    TAtlasCiFetchError.None));
  Assert.AreEqual(Integer(Ord(TAtlasBoardLoadView.Cached)), ViewOf(False, False, True,
    TAtlasCiFetchError.Timeout));
  Assert.AreEqual(Integer(Ord(TAtlasBoardLoadView.Cached)), ViewOf(False, False, True,
    TAtlasCiFetchError.Cancelled), 'abgebrochen: letzter Stand bleibt');
  Assert.AreEqual(Integer(Ord(TAtlasBoardLoadView.Notice)), ViewOf(False, False, True,
    TAtlasCiFetchError.NotFound), 'kein Board: kein alter Stand');
  Assert.AreEqual(Integer(Ord(TAtlasBoardLoadView.Notice)), ViewOf(False, False, False,
    TAtlasCiFetchError.Network));
  Assert.AreEqual(Integer(Ord(TAtlasBoardLoadView.Silent)), ViewOf(False, False, False,
    TAtlasCiFetchError.Cancelled));
end;

procedure TAtlasBoardPlanTests.ReasonPerError;
begin
  Assert.AreEqual(Integer(Ord(TAtlasBoardReason.Token)),
    Integer(Ord(TAtlasBoardPlan.ReasonOf(TAtlasCiFetchError.Unauthorized))));
  Assert.AreEqual(Integer(Ord(TAtlasBoardReason.NoBoard)),
    Integer(Ord(TAtlasBoardPlan.ReasonOf(TAtlasCiFetchError.NotFound))));
  Assert.AreEqual(Integer(Ord(TAtlasBoardReason.Timeout)),
    Integer(Ord(TAtlasBoardPlan.ReasonOf(TAtlasCiFetchError.Timeout))));
  Assert.AreEqual(Integer(Ord(TAtlasBoardReason.NoTracker)),
    Integer(Ord(TAtlasBoardPlan.ReasonOf(TAtlasCiFetchError.NotConfigured))));
  Assert.AreEqual(Integer(Ord(TAtlasBoardReason.NoTracker)),
    Integer(Ord(TAtlasBoardPlan.ReasonOf(TAtlasCiFetchError.UnknownProvider))));
  Assert.AreEqual(Integer(Ord(TAtlasBoardReason.Invalid)),
    Integer(Ord(TAtlasBoardPlan.ReasonOf(TAtlasCiFetchError.Server))));
  Assert.AreEqual(Integer(Ord(TAtlasBoardReason.Network)),
    Integer(Ord(TAtlasBoardPlan.ReasonOf(TAtlasCiFetchError.Network))));
end;

procedure TAtlasBoardPlanTests.ForeignCardsOnlyInBrowser;
begin
  Assert.IsTrue(TAtlasBoardPlan.Foreign('owner/repo#12'));
  Assert.IsFalse(TAtlasBoardPlan.Foreign('#12'));
  Assert.IsTrue(TAtlasBoardPlan.Actionable('ATL-1'));
  Assert.IsFalse(TAtlasBoardPlan.Actionable('owner/repo#12'));
  Assert.IsFalse(TAtlasBoardPlan.Actionable(''));
  Assert.AreEqual(Integer(Ord(TAtlasBoardCardOpen.Preview)), Integer(Ord(TAtlasBoardPlan.CardOpen('ATL-1', True))));
  Assert.AreEqual(Integer(Ord(TAtlasBoardCardOpen.Browse)), Integer(Ord(TAtlasBoardPlan.CardOpen('ATL-1', False))),
    'ohne Vorschau');
  Assert.AreEqual(Integer(Ord(TAtlasBoardCardOpen.Browse)),
    Integer(Ord(TAtlasBoardPlan.CardOpen('owner/repo#12', True))));
  Assert.AreEqual(Integer(Ord(TAtlasBoardCardOpen.None)), Integer(Ord(TAtlasBoardPlan.CardOpen('', True))));
end;

procedure TAtlasBoardPlanTests.BrowsePagePrefersProvider;
begin
  Assert.AreEqual('https://tracker.example/issue/ATL-1', TAtlasBoardPlan.BrowsePage('ATL-1',
    'https://antwort.example/1', 'https://tracker.example/issue/ATL-1'));
  Assert.AreEqual('https://antwort.example/1', TAtlasBoardPlan.BrowsePage('ATL-1', 'https://antwort.example/1', ''));
  Assert.AreEqual('https://github.com/owner/repo/issues/12', TAtlasBoardPlan.BrowsePage('owner/repo#12',
    'https://github.com/owner/repo/issues/12', 'https://github.com/mein/repo/issues/12'), 'fremdes Repository');
end;

procedure TAtlasBoardPlanTests.TargetChangedIgnoresCase;
var
  mOld, mNew: TAtlasTrackerTarget;
begin
  mOld := TAtlasTrackerTarget.Create(TAtlasTrackerTarget.cGitHub, '', 'owner/repo', '');
  mNew := TAtlasTrackerTarget.Create(TAtlasTrackerTarget.cGitHub, '', 'Owner/Repo', '');
  Assert.IsFalse(TAtlasBoardPlan.TargetChanged(mOld, mNew));
  mNew := TAtlasTrackerTarget.Create(TAtlasTrackerTarget.cGitHub, '', 'owner/anders', '');
  Assert.IsTrue(TAtlasBoardPlan.TargetChanged(mOld, mNew));
  Assert.IsTrue(TAtlasBoardPlan.TargetChanged(Default(TAtlasTrackerTarget), mNew), 'erster Tracker');
end;

procedure TAtlasBoardPlanTests.MoveCheckLockedAndWorkflow;
var
  mSnapshot: TAtlasBoardSnapshot;
begin
  mSnapshot := PlanSnapshot;
  Assert.AreEqual(Integer(Ord(TAtlasBoardMoveCheck.Locked)),
    Integer(Ord(TAtlasBoardPlan.MoveCheck(False, True, mSnapshot, 0, 1))), 'ohne Verbindung');
  Assert.AreEqual(Integer(Ord(TAtlasBoardMoveCheck.Locked)),
    Integer(Ord(TAtlasBoardPlan.MoveCheck(True, False, mSnapshot, 0, 1))), 'ohne Schreibweg');
  Assert.AreEqual(Integer(Ord(TAtlasBoardMoveCheck.Allowed)),
    Integer(Ord(TAtlasBoardPlan.MoveCheck(True, True, mSnapshot, 0, 1))));
  Assert.AreEqual(Integer(Ord(TAtlasBoardMoveCheck.NotAllowed)),
    Integer(Ord(TAtlasBoardPlan.MoveCheck(True, True, mSnapshot, 0, 2))), 'kein Übergang nach Erledigt');
  Assert.AreEqual(Integer(Ord(TAtlasBoardMoveCheck.Refused)),
    Integer(Ord(TAtlasBoardPlan.MoveCheck(True, True, mSnapshot, 0, 0))), 'gleiche Spalte, ohne Meldung');
  mSnapshot.Cards[0].Workflow.Transitions := nil;
  Assert.AreEqual(Integer(Ord(TAtlasBoardMoveCheck.NoTransition)),
    Integer(Ord(TAtlasBoardPlan.MoveCheck(True, True, mSnapshot, 0, 1))));
end;

procedure TAtlasBoardPlanTests.TransitionsOnlyWhenRejectedUnderStateMachine;
var
  mCard: TAtlasBoardCard;
  mRejected: TAtlasTrackerWriteResult;
begin
  mCard := PlanSnapshot.Cards[0];
  mRejected := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 400, '');
  Assert.IsTrue(TAtlasBoardPlan.ShowsTransitions(mCard, mRejected));
  Assert.IsFalse(TAtlasBoardPlan.ShowsTransitions(mCard, TAtlasTrackerWriteResult.Failed(
    TAtlasCiFetchError.Network, 0, '')), 'Netzfehler');
  mCard.Workflow.Transitions := nil;
  Assert.IsFalse(TAtlasBoardPlan.ShowsTransitions(mCard, mRejected), 'keine Übergänge');
  mCard := PlanSnapshot.Cards[0];
  mCard.Workflow.StateMachine := False;
  Assert.IsFalse(TAtlasBoardPlan.ShowsTransitions(mCard, mRejected), 'ohne Zustandsmaschine');
end;

procedure TAtlasBoardPlanTests.RefreshesOnlyWhenIdle;
begin
  Assert.IsTrue(TAtlasBoardPlan.Refreshes(True, True, True, False, False));
  Assert.IsFalse(TAtlasBoardPlan.Refreshes(False, True, True, False, False), 'nicht gestartet');
  Assert.IsFalse(TAtlasBoardPlan.Refreshes(True, False, True, False, False), 'issues.board aus');
  Assert.IsFalse(TAtlasBoardPlan.Refreshes(True, True, False, False, False), 'Fenster zu');
  Assert.IsFalse(TAtlasBoardPlan.Refreshes(True, True, True, True, False), 'lädt schon');
  Assert.IsFalse(TAtlasBoardPlan.Refreshes(True, True, True, False, True), 'verschiebt');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBoardPlanTests);

end.
