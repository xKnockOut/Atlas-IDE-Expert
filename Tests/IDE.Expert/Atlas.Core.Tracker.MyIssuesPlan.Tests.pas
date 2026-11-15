unit Atlas.Core.Tracker.MyIssuesPlan.Tests;

// Tests von „Meine Issues“ ohne IDE (#1967): „Alle Tracker-Projekte“ mit Gruppen und gemeinsamen Abfragen, was nur
// für ein Projekt gilt, und was eine Aktion an einer Zeile auslöst.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasMyIssuesPlanTests = class
  public
    [Test]
    procedure CommonQueriesByName;
    [Test]
    procedure AllViewGroupsAndKeepsQuery;
    [Test]
    procedure AllViewWithoutGroups;
    [Test]
    procedure ProjectBoundState;
    [Test]
    procedure RowActionSteps;
  end;

implementation

uses
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Queries,
  Atlas.Core.Tracker.MyIssues,
  Atlas.Core.Tracker.MyIssuesPlan;

function Query(const AName: string): TAtlasTrackerQuery;
begin
  Result := TAtlasTrackerQuery.Create(AName, '', '', '');
end;

function Issue(const AKey: string): TAtlasTrackerIssue;
begin
  Result := TAtlasTrackerIssue.Empty;
  Result.Key := AKey;
end;

function Group(const ACaption: string; const AKeys: TArray<string>; const AQueries: TArray<TAtlasTrackerQuery>;
  AQuerying: Boolean): TAtlasIssuesGroupView;
var
  mKey: string;
begin
  Result := Default(TAtlasIssuesGroupView);
  Result.Caption := ACaption;
  Result.Project := ACaption + '.dproj';
  Result.View.Status := TAtlasIssuesStatus.Ready;
  Result.View.Querying := AQuerying;
  Result.View.Queries := AQueries;
  for mKey in AKeys do
  begin
    Result.View.Items := Result.View.Items + [Issue(mKey)];
  end;
end;

procedure TAtlasMyIssuesPlanTests.CommonQueriesByName;
var
  mCommon: TArray<TAtlasTrackerQuery>;
begin
  mCommon := TAtlasMyIssuesPlan.CommonQueries(TArray<TAtlasTrackerQuery>.Create(Query('Meine'), Query('Offen'),
    Query('Sprint')), TArray<TAtlasTrackerQuery>.Create(Query('offen'), Query('Meine')));
  Assert.AreEqual(2, Integer(Length(mCommon)));
  Assert.AreEqual('Meine', mCommon[0].Name);
  Assert.AreEqual('Offen', mCommon[1].Name, 'Name aus der ersten Liste');
  Assert.AreEqual(0, Integer(Length(TAtlasMyIssuesPlan.CommonQueries(nil, mCommon))));
  mCommon := nil;
end;

procedure TAtlasMyIssuesPlanTests.AllViewGroupsAndKeepsQuery;
var
  mBase, mView: TAtlasIssuesView;
  mGroups: TArray<TAtlasIssuesGroupView>;
begin
  mBase := Default(TAtlasIssuesView);
  mBase.Queries := TArray<TAtlasTrackerQuery>.Create(Query('Meine'), Query('Offen'), Query('Sprint'));
  mBase.QueryIndex := 1;
  mBase.QueryCounts := TArray<Integer>.Create(1, 2, 3);
  mBase.Filter := 'Sprint 12';
  mBase.Items := TArray<TAtlasTrackerIssue>.Create(Issue('X-1'));
  mGroups := TArray<TAtlasIssuesGroupView>.Create(
    Group('A', TArray<string>.Create('A-1', 'A-2', 'A-3'), TArray<TAtlasTrackerQuery>.Create(Query('Offen'),
    Query('Meine')), False),
    Group('B', TArray<string>.Create('B-1'), TArray<TAtlasTrackerQuery>.Create(Query('Offen')), True));
  mView := TAtlasMyIssuesPlan.AllView(mBase, mGroups, 2);
  Assert.AreEqual(Integer(Ord(TAtlasIssuesStatus.Ready)), Integer(Ord(mView.Status)));
  Assert.AreEqual('', mView.Filter, 'ohne Filter der Sprint-Kachel');
  Assert.IsTrue(mView.Querying, 'eine Gruppe fragt noch');
  Assert.AreEqual(2, Integer(Length(mView.Groups)));
  Assert.AreEqual(3, Integer(Length(mView.Items)), 'höchstens zwei je Gruppe');
  Assert.AreEqual('A-1', mView.Items[0].Key);
  Assert.AreEqual('B-1', mView.Items[2].Key);
  Assert.AreEqual(1, Integer(Length(mView.Queries)), 'nur gemeinsame Abfragen');
  Assert.AreEqual('Offen', mView.Queries[0].Name);
  Assert.AreEqual(0, mView.QueryIndex, 'gewählte Abfrage nach Namen');
  Assert.AreEqual(0, Integer(Length(mView.QueryCounts)));
  mGroups := TArray<TAtlasIssuesGroupView>.Create(Group('C', nil, TArray<TAtlasTrackerQuery>.Create(Query('Meine')),
    False));
  Assert.AreEqual(-1, TAtlasMyIssuesPlan.AllView(mBase, mGroups, 2).QueryIndex, 'gewählte kennt nicht jeder');
  mGroups := nil;
end;

procedure TAtlasMyIssuesPlanTests.AllViewWithoutGroups;
var
  mBase, mView: TAtlasIssuesView;
begin
  mBase := Default(TAtlasIssuesView);
  mBase.Status := TAtlasIssuesStatus.Ready;
  mBase.Querying := True;
  mBase.QueryIndex := 5;
  mView := TAtlasMyIssuesPlan.AllView(mBase, nil, 10);
  Assert.AreEqual(Integer(Ord(TAtlasIssuesStatus.NotConfigured)), Integer(Ord(mView.Status)));
  Assert.IsFalse(mView.Querying);
  Assert.AreEqual(-1, mView.QueryIndex);
end;

procedure TAtlasMyIssuesPlanTests.ProjectBoundState;
begin
  Assert.IsTrue(TAtlasMyIssuesPlan.SameProject('C:\A.dproj', 'c:\a.dproj'));
  Assert.IsFalse(TAtlasMyIssuesPlan.SameProject('', ''), 'keine laufende Abfrage');
  Assert.IsFalse(TAtlasMyIssuesPlan.SameProject('C:\A.dproj', 'C:\B.dproj'));
  Assert.IsTrue(TAtlasMyIssuesPlan.FilterApplies('Sprint 12', 'C:\A.dproj', 'C:\A.dproj'));
  Assert.IsFalse(TAtlasMyIssuesPlan.FilterApplies('', 'C:\A.dproj', 'C:\A.dproj'), 'kein Filter');
  Assert.IsFalse(TAtlasMyIssuesPlan.FilterApplies('Sprint 12', 'C:\A.dproj', 'C:\B.dproj'), 'anderes Projekt');
end;

procedure TAtlasMyIssuesPlanTests.RowActionSteps;
begin
  Assert.AreEqual(Integer(Ord(TAtlasIssueRowStep.Review)),
    Integer(Ord(TAtlasMyIssuesPlan.StepOf(TAtlasIssueRowAction.Review, False))));
  Assert.AreEqual(Integer(Ord(TAtlasIssueRowStep.Resume)),
    Integer(Ord(TAtlasMyIssuesPlan.StepOf(TAtlasIssueRowAction.Continue, False))), 'auch ohne Marke');
  Assert.AreEqual(Integer(Ord(TAtlasIssueRowStep.Dismiss)),
    Integer(Ord(TAtlasMyIssuesPlan.StepOf(TAtlasIssueRowAction.Dismiss, True))));
  Assert.AreEqual(Integer(Ord(TAtlasIssueRowStep.Reason)),
    Integer(Ord(TAtlasMyIssuesPlan.StepOf(TAtlasIssueRowAction.Reason, True))));
  Assert.AreEqual(Integer(Ord(TAtlasIssueRowStep.Skip)),
    Integer(Ord(TAtlasMyIssuesPlan.StepOf(TAtlasIssueRowAction.Dismiss, False))));
  Assert.AreEqual(Integer(Ord(TAtlasIssueRowStep.Skip)),
    Integer(Ord(TAtlasMyIssuesPlan.StepOf(TAtlasIssueRowAction.Reason, False))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMyIssuesPlanTests);

end.
