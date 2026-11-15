unit Atlas.Core.Tracker.SyncPlan.Tests;

// Tests der Entscheidungen von „Tracker nachführen“ (#1266, #1967) ohne IDE und Server: „Beginnen“ unter einer
// Zustandsmaschine gegen einen Anbieter, der jeden Aufruf mitschreibt (Übergang, blockiert, ohne Regeln), Werte für
// den Beenden-Dialog und für „Prüfen“, die Zeile nach „Beginnen“, was der Beenden-Dialog je Anbieter zeigt, die
// Einstellungen und die anonyme Protokollzeile.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasTrackerSyncPlanTests = class
  public
    [Test]
    procedure RunStartFiresTransitionAndReadsState;
    [Test]
    procedure RunStartBlockedKeepsState;
    [Test]
    procedure RunStartWithoutRulesWritesValue;
    [Test]
    procedure EndValuesReadFieldsAndTime;
    [Test]
    procedure EndValuesWithoutFieldsOrTime;
    [Test]
    procedure ReviewValuesWithoutUsers;
    [Test]
    procedure StartNoteFailedSyncedAndBlocked;
    [Test]
    procedure ProviderDecidesEndDialog;
    [Test]
    procedure StartWritesOnlyWithWork;
    [Test]
    procedure OptionsFollowSettings;
    [Test]
    procedure LogLineIsAnonymous;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Providers.GitHub,
  Atlas.Core.Tracker.Providers.YouTrack,
  Atlas.Core.Tracker.SyncPlan,
  Atlas.Core.Tracker.Workflow;

type
  /// <summary>Anbieter, der jeden Zugriff als Zeile mitschreibt. Regeln: aktueller Zustand Open, Übergang „Start“
  /// nach In Progress; nach einem Übergang steht das Issue auf In Progress. RulesFail: Regeln nicht lesbar.</summary>
  TFakeIssueAccess = class(TInterfacedObject, IAtlasTrackerWriter, IAtlasTrackerStateRules, IAtlasTrackerFields,
    IAtlasTrackerTimeWriter)
  private
    FMoved: Boolean;
  public
    Calls: TArray<string>;
    RulesFail: Boolean;
    function Apply(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      const AChange: TAtlasTrackerWrite; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
    function Values(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      AKind: TAtlasTrackerValueKind; const AField: string; ATimeoutMs: Integer;
      out AValues: TArray<string>): TAtlasTrackerWriteResult;
    function StateRules(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey,
      AField: string; ATimeoutMs: Integer; out ARules: TAtlasTrackerStateRules): TAtlasTrackerWriteResult;
    function FieldValues(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey,
      AField: string; ATimeoutMs: Integer; out AValues: TArray<string>): TAtlasTrackerWriteResult;
    function SetField(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey, AField,
      AValue: string; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
    function TimeSettings(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      ATimeoutMs: Integer; out ASettings: TAtlasTrackerTimeSettings): TAtlasTrackerWriteResult;
    function BookTime(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      const AItem: TAtlasTrackerWorkItem; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
    function IsTrackingOff(const AResult: TAtlasTrackerWriteResult): Boolean;
  end;

{ TFakeIssueAccess }

function TFakeIssueAccess.Apply(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; const AChange: TAtlasTrackerWrite; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
begin
  Calls := Calls + ['apply ' + AKey + ' state=' + AChange.State + ' transition=' + AChange.Transition.Id];
  FMoved := AChange.Transition.Id <> '';
  Result := TAtlasTrackerWriteResult.Ok;
end;

function TFakeIssueAccess.Values(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  AKind: TAtlasTrackerValueKind; const AField: string; ATimeoutMs: Integer;
  out AValues: TArray<string>): TAtlasTrackerWriteResult;
begin
  Calls := Calls + ['values ' + IntToStr(Ord(AKind)) + ' ' + AField];
  AValues := TArray<string>.Create('v' + IntToStr(Ord(AKind)));
  Result := TAtlasTrackerWriteResult.Ok;
end;

function TFakeIssueAccess.StateRules(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey, AField: string; ATimeoutMs: Integer; out ARules: TAtlasTrackerStateRules): TAtlasTrackerWriteResult;
begin
  Calls := Calls + ['rules ' + AKey + ' ' + AField];
  ARules := Default(TAtlasTrackerStateRules);
  if RulesFail then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Unauthorized, 403, ''));
  end;
  ARules.StateMachine := True;
  ARules.FieldId := '82-11';
  ARules.Current := 'Open';
  if FMoved then
  begin
    ARules.Current := 'In Progress';
  end;
  ARules.Transitions := TArray<TAtlasTrackerTransition>.Create(TAtlasTrackerTransition.Create('start', 'In Progress'));
  Result := TAtlasTrackerWriteResult.Ok;
end;

function TFakeIssueAccess.FieldValues(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey, AField: string; ATimeoutMs: Integer; out AValues: TArray<string>): TAtlasTrackerWriteResult;
begin
  Calls := Calls + ['fields ' + AField];
  AValues := TArray<string>.Create(AField + '1', AField + '2');
  Result := TAtlasTrackerWriteResult.Ok;
end;

function TFakeIssueAccess.SetField(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey, AField, AValue: string; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
begin
  Calls := Calls + ['set ' + AField];
  Result := TAtlasTrackerWriteResult.Ok;
end;

function TFakeIssueAccess.TimeSettings(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; ATimeoutMs: Integer; out ASettings: TAtlasTrackerTimeSettings): TAtlasTrackerWriteResult;
begin
  Calls := Calls + ['time'];
  ASettings.Enabled := True;
  ASettings.WorkTypes := TArray<string>.Create('Development');
  Result := TAtlasTrackerWriteResult.Ok;
end;

function TFakeIssueAccess.BookTime(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; const AItem: TAtlasTrackerWorkItem; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
begin
  Calls := Calls + ['book'];
  Result := TAtlasTrackerWriteResult.Ok;
end;

function TFakeIssueAccess.IsTrackingOff(const AResult: TAtlasTrackerWriteResult): Boolean;
begin
  Result := False;
end;

/// <summary>Zugriff auf ATL-7 mit allen Verträgen von AAccess, Zustandsfeld State.</summary>
function CallOf(AAccess: TFakeIssueAccess): TAtlasTrackerIssueCall;
begin
  Result := Default(TAtlasTrackerIssueCall);
  Result.Writer := AAccess;
  Result.Rules := AAccess;
  Result.Fields := AAccess;
  Result.Time := AAccess;
  Result.Key := 'ATL-7';
  Result.Field := 'State';
end;

function StateChange(const AState: string): TAtlasTrackerWrite;
begin
  Result := TAtlasTrackerWrite.Empty;
  Result.State := AState;
end;

{ TAtlasTrackerSyncPlanTests }

procedure TAtlasTrackerSyncPlanTests.RunStartFiresTransitionAndReadsState;
var
  mAccess: TFakeIssueAccess;
  mKeep: IAtlasTrackerWriter;
  mStarted: TAtlasTrackerStarted;
begin
  mAccess := TFakeIssueAccess.Create;
  mKeep := mAccess;
  mStarted := TAtlasTrackerStarted.Create(StateChange('In Progress'));
  TAtlasTrackerSyncPlan.RunStart(CallOf(mAccess), mStarted);
  Assert.IsTrue(mStarted.Outcome.Succeeded);
  Assert.IsFalse(mStarted.Blocked);
  Assert.AreEqual('start', mStarted.Change.Transition.Id);
  Assert.AreEqual('82-11', mStarted.Change.FieldId);
  Assert.AreEqual('In Progress', mStarted.NewState, 'Zustand nach dem Übergang einmal gelesen');
  Assert.AreEqual('rules ATL-7 State|apply ATL-7 state= transition=start|rules ATL-7 State',
    string.Join('|', mAccess.Calls));
end;

procedure TAtlasTrackerSyncPlanTests.RunStartBlockedKeepsState;
var
  mAccess: TFakeIssueAccess;
  mKeep: IAtlasTrackerWriter;
  mStarted: TAtlasTrackerStarted;
  mNote: TAtlasTrackerStartNote;
begin
  mAccess := TFakeIssueAccess.Create;
  mKeep := mAccess;
  mStarted := TAtlasTrackerStarted.Create(StateChange('Fixed'));
  mStarted.Change.Comment := 'Begonnen';
  TAtlasTrackerSyncPlan.RunStart(CallOf(mAccess), mStarted);
  Assert.IsTrue(mStarted.Blocked);
  Assert.AreEqual('', mStarted.Change.State, 'Zustand entfällt, Kommentar bleibt');
  Assert.AreEqual('', mStarted.NewState, 'ohne Übergang nichts nachgelesen');
  Assert.AreEqual(Integer(2), Integer(Length(mAccess.Calls)));
  mNote := TAtlasTrackerSyncPlan.StartNote(mStarted);
  Assert.IsFalse(mNote.Failed);
  Assert.IsTrue(mNote.Synced, 'Kommentar geschrieben');
  Assert.AreEqual(Integer(Ord(TAtlasTrackerStartBlock.Transitions)), Integer(Ord(mNote.Block)));
  Assert.AreEqual('Open', mNote.Current);
  Assert.AreEqual('In Progress', string.Join(',', mNote.Transitions));
end;

procedure TAtlasTrackerSyncPlanTests.RunStartWithoutRulesWritesValue;
var
  mAccess: TFakeIssueAccess;
  mKeep: IAtlasTrackerWriter;
  mStarted: TAtlasTrackerStarted;
begin
  mAccess := TFakeIssueAccess.Create;
  mKeep := mAccess;
  mAccess.RulesFail := True;
  mStarted := TAtlasTrackerStarted.Create(StateChange('In Progress'));
  TAtlasTrackerSyncPlan.RunStart(CallOf(mAccess), mStarted);
  Assert.IsTrue(mStarted.Outcome.Succeeded);
  Assert.IsFalse(mStarted.Blocked);
  Assert.AreEqual('In Progress', mStarted.Change.State, 'Befehl mit dem Wert wie bisher');
  Assert.AreEqual('rules ATL-7 State|apply ATL-7 state=In Progress transition=', string.Join('|', mAccess.Calls));
end;

procedure TAtlasTrackerSyncPlanTests.EndValuesReadFieldsAndTime;
var
  mAccess: TFakeIssueAccess;
  mKeep: IAtlasTrackerWriter;
  mValues: TAtlasTrackerEndValues;
begin
  mAccess := TFakeIssueAccess.Create;
  mKeep := mAccess;
  mValues := Default(TAtlasTrackerEndValues);
  mValues.FieldNames := TArray<string>.Create('Priority', 'Fix version');
  mValues.WithTime := True;
  TAtlasTrackerSyncPlan.ReadEndValues(CallOf(mAccess), mValues);
  Assert.AreEqual('v' + IntToStr(Ord(TAtlasTrackerValueKind.Users)), string.Join(',', mValues.Users));
  Assert.AreEqual('v' + IntToStr(Ord(TAtlasTrackerValueKind.States)), string.Join(',', mValues.States));
  Assert.AreEqual('Open', mValues.Rules.Current);
  Assert.AreEqual(Integer(2), Integer(Length(mValues.FieldValues)));
  Assert.AreEqual('Fix version1,Fix version2', string.Join(',', mValues.FieldValues[1]));
  Assert.AreEqual('1,2', string.Join(',', mValues.KnownFields), 'Felder des Projekts mit leerem Namen');
  Assert.IsTrue(mValues.TimeRead);
  Assert.AreEqual('Development', string.Join(',', mValues.Time.WorkTypes));
end;

procedure TAtlasTrackerSyncPlanTests.EndValuesWithoutFieldsOrTime;
var
  mAccess: TFakeIssueAccess;
  mKeep: IAtlasTrackerWriter;
  mCall: TAtlasTrackerIssueCall;
  mValues: TAtlasTrackerEndValues;
begin
  mAccess := TFakeIssueAccess.Create;
  mKeep := mAccess;
  mCall := CallOf(mAccess);
  mCall.Rules := nil;
  mCall.Fields := nil;
  mValues := Default(TAtlasTrackerEndValues);
  mValues.FieldNames := TArray<string>.Create('Priority');
  TAtlasTrackerSyncPlan.ReadEndValues(mCall, mValues);
  Assert.AreEqual(Integer(0), Integer(Length(mValues.FieldValues)));
  Assert.IsFalse(mValues.TimeRead, 'Zeit nicht gefragt');
  Assert.IsFalse(mValues.Rules.StateMachine, 'ohne Regeln bleibt die Liste der Zustände');
  Assert.AreEqual(Integer(2), Integer(Length(mAccess.Calls)), 'nur Benutzer und Zustände');
end;

procedure TAtlasTrackerSyncPlanTests.ReviewValuesWithoutUsers;
var
  mAccess: TFakeIssueAccess;
  mKeep: IAtlasTrackerWriter;
  mValues: TAtlasTrackerEndValues;
begin
  mAccess := TFakeIssueAccess.Create;
  mKeep := mAccess;
  mValues := TAtlasTrackerSyncPlan.ReadReviewValues(CallOf(mAccess));
  Assert.AreEqual(Integer(0), Integer(Length(mValues.Users)));
  Assert.AreEqual(Integer(1), Integer(Length(mValues.States)));
  Assert.AreEqual('Open', mValues.Rules.Current);
  Assert.AreEqual('values ' + IntToStr(Ord(TAtlasTrackerValueKind.States)) + ' State|rules ATL-7 State',
    string.Join('|', mAccess.Calls));
end;

procedure TAtlasTrackerSyncPlanTests.StartNoteFailedSyncedAndBlocked;
var
  mStarted: TAtlasTrackerStarted;
  mNote: TAtlasTrackerStartNote;
begin
  mStarted := TAtlasTrackerStarted.Create(StateChange('Fixed'));
  mNote := TAtlasTrackerSyncPlan.StartNote(mStarted);
  Assert.IsTrue(mNote.Failed, 'vor dem Lauf gilt Network');
  Assert.IsFalse(mNote.Synced);
  mStarted.Outcome := TAtlasTrackerWriteResult.Ok;
  mNote := TAtlasTrackerSyncPlan.StartNote(mStarted);
  Assert.IsTrue(mNote.Synced);
  Assert.AreEqual(Integer(Ord(TAtlasTrackerStartBlock.None)), Integer(Ord(mNote.Block)));
  mStarted.Change := TAtlasTrackerWrite.Empty;
  mStarted.Blocked := True;
  mStarted.Rules.Current := 'Verified';
  mNote := TAtlasTrackerSyncPlan.StartNote(mStarted);
  Assert.IsFalse(mNote.Synced, 'nichts geschrieben');
  Assert.AreEqual(Integer(Ord(TAtlasTrackerStartBlock.NoTransitions)), Integer(Ord(mNote.Block)));
  Assert.AreEqual('Verified', mNote.Current);
end;

procedure TAtlasTrackerSyncPlanTests.ProviderDecidesEndDialog;
var
  mGitHub, mYouTrack: IAtlasTrackerProvider;
  mOptions: TAtlasTrackerSyncOptions;
begin
  mGitHub := TAtlasGitHubTracker.Create;
  mYouTrack := TAtlasYouTrackTracker.Create;
  mOptions := TAtlasTrackerSyncOptions.Create(True, 'State', 'Assignee').WithEndSteps('Priority', True);
  Assert.AreEqual(Integer(0), Integer(Length(TAtlasTrackerSyncPlan.EndOptions(mOptions, mGitHub).EndFields)));
  Assert.AreEqual('Priority', string.Join(',', TAtlasTrackerSyncPlan.EndOptions(mOptions, mYouTrack).EndFields));
  Assert.IsFalse(TAtlasTrackerSyncPlan.AsksEndTime(mOptions, mGitHub), 'GitHub bucht keine Zeit');
  Assert.IsTrue(TAtlasTrackerSyncPlan.AsksEndTime(mOptions, mYouTrack));
  Assert.IsFalse(TAtlasTrackerSyncPlan.AsksEndTime(mOptions.WithEndSteps('', False), mYouTrack));
  Assert.IsFalse(TAtlasTrackerSyncPlan.AsksEndTime(mOptions, nil));
  Assert.IsFalse(TAtlasTrackerSyncPlan.ShowsEndTime(59));
  Assert.IsTrue(TAtlasTrackerSyncPlan.ShowsEndTime(60));
  Assert.IsTrue(TAtlasTrackerSyncPlan.StartsWithRules(StateChange('In Progress'), mYouTrack));
  Assert.IsFalse(TAtlasTrackerSyncPlan.StartsWithRules(StateChange(''), mYouTrack), 'kein Zustand zu setzen');
  Assert.IsFalse(TAtlasTrackerSyncPlan.StartsWithRules(StateChange('In Progress'), mGitHub));
  Assert.IsNotNull(TAtlasTrackerSyncPlan.IssueCall(mYouTrack, Default(TAtlasTrackerTarget), 'ATL-7', 'State').Time);
  Assert.IsNull(TAtlasTrackerSyncPlan.IssueCall(mGitHub, Default(TAtlasTrackerTarget), '#7', 'State').Fields);
  Assert.IsNull(TAtlasTrackerSyncPlan.WriterOf(nil));
end;

procedure TAtlasTrackerSyncPlanTests.StartWritesOnlyWithWork;
var
  mOptions: TAtlasTrackerSyncOptions;
begin
  mOptions := TAtlasTrackerSyncOptions.Create(True, 'State', 'Assignee');
  Assert.IsFalse(TAtlasTrackerSyncPlan.WritesOnStart(mOptions, TAtlasTrackerSprintRef.None));
  Assert.IsTrue(TAtlasTrackerSyncPlan.WritesOnStart(mOptions, TAtlasTrackerSprintRef.Create('Board', 'Sprint 4', 0)),
    'Sprint allein reicht');
  Assert.IsTrue(TAtlasTrackerSyncPlan.WritesOnStart(mOptions.WithStart('In Progress', False, ''),
    TAtlasTrackerSprintRef.None));
end;

procedure TAtlasTrackerSyncPlanTests.OptionsFollowSettings;
var
  mSettings: TAtlasPluginSettings;
  mOptions: TAtlasTrackerSyncOptions;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.IssuesSyncState := True;
  mSettings.IssuesStartState := 'In Progress';
  mSettings.IssuesEndFields := 'Priority';
  mSettings.IssuesEndTime := True;
  mOptions := TAtlasTrackerSyncPlan.Options(mSettings, False, Default(TAtlasTrackerTarget));
  Assert.IsTrue(mOptions.SyncState);
  Assert.AreEqual('In Progress', mOptions.StartState);
  Assert.AreEqual('Priority', string.Join(',', mOptions.EndFields));
  Assert.IsTrue(mOptions.EndTime);
  Assert.AreEqual(TAtlasTrackerWorkflow.EndCommentFor(mSettings.IssuesEndComment, False), mOptions.EndComment);
  Assert.AreEqual(TAtlasTrackerWorkflow.EndCommentFor(mSettings.IssuesEndComment, True),
    TAtlasTrackerSyncPlan.Options(mSettings, True, Default(TAtlasTrackerTarget)).EndComment);
end;

procedure TAtlasTrackerSyncPlanTests.LogLineIsAnonymous;
var
  mYouTrack: IAtlasTrackerProvider;
  mLine: string;
begin
  mYouTrack := TAtlasYouTrackTracker.Create;
  mLine := TAtlasTrackerSyncPlan.LogLine(mYouTrack, 'Beginnen', TAtlasTrackerWriteResult.Ok);
  Assert.AreEqual('Tracker nachführen: ' + mYouTrack.Name + ' Beginnen geschrieben', mLine);
  mLine := TAtlasTrackerSyncPlan.LogLine(nil, 'Kommentar',
    TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Unauthorized, 401, 'geheim'));
  Assert.AreEqual('Tracker nachführen:  Kommentar nicht geschrieben (' +
    TAtlasCiBuild.ErrorKey(TAtlasCiFetchError.Unauthorized) + ', 401)', mLine);
end;

end.
