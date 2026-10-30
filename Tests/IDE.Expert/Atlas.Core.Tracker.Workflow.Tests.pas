unit Atlas.Core.Tracker.Workflow.Tests;

// Tests zu „Tracker nachführen“ (#1266) ohne Server: Platzhalter der
// Kommentarvorlagen, Listen, Werte je Verbindung, Commits für {commits},
// Aufbau des YouTrack-Befehls (Namen mit Leerzeichen in {}), PATCH für
// GitHub, Schreiben gegen einen Transport mit festen Antworten (POST/PATCH
// über IAtlasCiSend) und die Abbildung der Fehler 400/403/404.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTrackerWorkflowTests = class
  public
    [Test]
    procedure ParseListAndListText;
    [Test]
    procedure FillReplacesPlaceholders;
    [Test]
    procedure MentionsKeyAsOwnWord;
    [Test]
    procedure CommitLinesOldestFirstWithKey;
    [Test]
    procedure CommitsForUsesFirstExistingBase;
    [Test]
    procedure ForConnectionOverridesGlobal;
    /// <summary>Mit syncState aus schreibt „Beginnen“ nichts.</summary>
    [Test]
    procedure StartChangeOnlyWithSyncState;
    [Test]
    procedure EndChangeStateCommentAndHandOver;
    [Test]
    procedure DurationText;
    /// <summary>Betreffzeilen der Commits ohne Kurz-Hash für den Buchungstext (#1267).</summary>
    [Test]
    procedure CommitSubjects;
    [Test]
    procedure ConnectionKeepsWorkflowFields;
    /// <summary>Zustandsfeld und Benutzerfeld nur bei Anbietern mit Feldern (YouTrack), nicht bei GitHub.</summary>
    [Test]
    procedure UsesFieldsOnlyWithoutGitHub;
  end;

  [TestFixture]
  TAtlasTrackerWriterTests = class
  public
    /// <summary>Namen mit Leerzeichen oder Satzzeichen in {}, Umlaute ohne.</summary>
    [Test]
    procedure YouTrackCommandWithBraces;
    [Test]
    procedure YouTrackCommandJson;
    [Test]
    procedure YouTrackApplyCommandOrComment;
    [Test]
    procedure YouTrackValues;
    /// <summary>400, 403 und 404 mit dem Text des Trackers; nichts wird wiederholt.</summary>
    [Test]
    procedure YouTrackErrors;
    [Test]
    procedure GitHubPatchJson;
    [Test]
    procedure GitHubApplyAgainstFakeTransport;
    [Test]
    procedure GitHubForbiddenStopsBeforeChange;
    [Test]
    procedure GitHubValues;
    [Test]
    procedure LoadValuesStopsAtFirstError;
    [Test]
    procedure WithoutSendIsNotConfigured;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.Workflow,
  Atlas.Core.Tracker.Providers.GitHub,
  Atlas.Core.Tracker.Providers.YouTrack,
  Atlas.Core.Vcs.Contract;

type
  /// <summary>Transport mit festen Antworten je Methode und Adressanfang; merkt sich Aufrufe und Inhalte.</summary>
  TFakeSendTransport = class(TInterfacedObject, IAtlasCiTransport, IAtlasCiSend)
  private
    FMethods: TArray<string>;
    FPrefixes: TArray<string>;
    FStatus: TArray<Integer>;
    FTexts: TArray<string>;
  public
    Calls: TArray<string>;
    Bodies: TArray<string>;
    procedure Answer(const AMethod, APrefix: string; AStatus: Integer; const AText: string);
    function Reply(const AMethod, AUrl: string; out AStatus: Integer; out AText: string): Boolean;
    function Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
    function Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
  end;

  /// <summary>Nur GET, kein IAtlasCiSend.</summary>
  TFakeGetTransport = class(TInterfacedObject, IAtlasCiTransport)
  public
    function Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
  end;

  /// <summary>Lokale Commits: Outgoing gelingt nur für AGoodBase.</summary>
  TFakeLocalWork = class(TInterfacedObject, IAtlasVcsLocalWork)
  private
    FGoodBase: string;
    FCommits: TArray<TAtlasVcsCommit>;
  public
    Asked: TArray<string>;
    constructor Create(const AGoodBase: string; const ACommits: TArray<TAtlasVcsCommit>);
    function Branches(out ABranches: TArray<TAtlasVcsBranch>): TAtlasVcsOutcome;
    function Stashes(out AStashes: TArray<TAtlasVcsStash>): TAtlasVcsOutcome;
    function Remotes(out ANames: TArray<string>): TAtlasVcsOutcome;
    function Outgoing(const ABranch, AUpstream: string; AMax: Integer;
      out ACommits: TArray<TAtlasVcsCommit>): TAtlasVcsOutcome;
    function ChangesIn(const ARevision: string; out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
    function Push(const ABranch, ARemote, ARemoteRef: string; ASetUpstream: Boolean): TAtlasVcsOutcome;
  end;

{ TFakeSendTransport }

procedure TFakeSendTransport.Answer(const AMethod, APrefix: string; AStatus: Integer; const AText: string);
begin
  FMethods := FMethods + [AMethod];
  FPrefixes := FPrefixes + [APrefix];
  FStatus := FStatus + [AStatus];
  FTexts := FTexts + [AText];
end;

function TFakeSendTransport.Reply(const AMethod, AUrl: string; out AStatus: Integer; out AText: string): Boolean;
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

function TFakeSendTransport.Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
begin
  AError := TAtlasCiFetchError.None;
  Result := Reply('GET', AUrl, AStatus, AText);
end;

function TFakeSendTransport.Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer; out AStatus: Integer;
  out AText: string; out AError: TAtlasCiFetchError): Boolean;
begin
  AError := TAtlasCiFetchError.None;
  Bodies := Bodies + [ABody];
  Result := Reply(AMethod, AUrl, AStatus, AText);
end;

{ TFakeGetTransport }

function TFakeGetTransport.Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
begin
  AStatus := 200;
  AText := '[]';
  AError := TAtlasCiFetchError.None;
  Result := True;
end;

{ TFakeLocalWork }

constructor TFakeLocalWork.Create(const AGoodBase: string; const ACommits: TArray<TAtlasVcsCommit>);
begin
  inherited Create;
  FGoodBase := AGoodBase;
  FCommits := ACommits;
end;

function TFakeLocalWork.Branches(out ABranches: TArray<TAtlasVcsBranch>): TAtlasVcsOutcome;
begin
  ABranches := nil;
  Result := TAtlasVcsOutcome.Failed;
end;

function TFakeLocalWork.Stashes(out AStashes: TArray<TAtlasVcsStash>): TAtlasVcsOutcome;
begin
  AStashes := nil;
  Result := TAtlasVcsOutcome.Failed;
end;

function TFakeLocalWork.Remotes(out ANames: TArray<string>): TAtlasVcsOutcome;
begin
  ANames := nil;
  Result := TAtlasVcsOutcome.Failed;
end;

function TFakeLocalWork.Outgoing(const ABranch, AUpstream: string; AMax: Integer;
  out ACommits: TArray<TAtlasVcsCommit>): TAtlasVcsOutcome;
begin
  Asked := Asked + [AUpstream];
  ACommits := nil;
  if AUpstream <> FGoodBase then
    Exit(TAtlasVcsOutcome.Failed);
  ACommits := FCommits;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeLocalWork.ChangesIn(const ARevision: string; out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
begin
  AChanges := nil;
  Result := TAtlasVcsOutcome.Failed;
end;

function TFakeLocalWork.Push(const ABranch, ARemote, ARemoteRef: string; ASetUpstream: Boolean): TAtlasVcsOutcome;
begin
  Result := TAtlasVcsOutcome.Failed;
end;

function Commit(const AHash, ASummary: string): TAtlasVcsCommit;
begin
  Result := Default(TAtlasVcsCommit);
  Result.Hash := AHash;
  Result.Summary := ASummary;
end;

function YouTrackTarget: TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create('youtrack', 'https://yt.beispiel.de', 'ATL', '');
end;

function GitHubTarget: TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create('github', '', 'beispiel/atlas', '');
end;

function Options(const AEndStates: string): TAtlasTrackerSyncOptions;
begin
  Result := TAtlasTrackerSyncOptions.Create(True, '', '', 'In Arbeit', True, 'Beginne {kennung}', AEndStates,
    TAtlasTrackerWorkflow.DefaultEndComment);
end;

/// <summary>Wert AName des JSON-Objekts AJson als Text ('' ohne).</summary>
function JsonText(const AJson, AName: string): string;
var
  mValue: TJSONValue;
  mItem: TJSONValue;
begin
  Result := '';
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if mValue is TJSONObject then
    begin
      mItem := TJSONObject(mValue).Values[AName];
      if mItem is TJSONArray then
        Result := mItem.ToJSON
      else if mItem <> nil then
        Result := mItem.Value;
    end;
  finally
    mValue.Free;
  end;
end;

{ TAtlasTrackerWorkflowTests }

procedure TAtlasTrackerWorkflowTests.ParseListAndListText;
var
  mItems: TArray<string>;
begin
  mItems := TAtlasTrackerWorkflow.ParseList(' Zur Prüfung, Erledigt;erledigt'#13#10'Fertig,, ');
  Assert.AreEqual(3, Integer(Length(mItems)), 'leere und doppelte entfallen');
  Assert.AreEqual('Zur Prüfung', mItems[0]);
  Assert.AreEqual('Erledigt', mItems[1]);
  Assert.AreEqual('Fertig', mItems[2]);
  Assert.AreEqual('Zur Prüfung, Erledigt, Fertig', TAtlasTrackerWorkflow.ListText(mItems));
  Assert.AreEqual(0, Integer(Length(TAtlasTrackerWorkflow.ParseList(' , ; '))));
end;

procedure TAtlasTrackerWorkflowTests.UsesFieldsOnlyWithoutGitHub;
begin
  Assert.IsTrue(TAtlasTrackerWorkflow.UsesFields(TAtlasTrackerTarget.YouTrack), 'YouTrack');
  Assert.IsFalse(TAtlasTrackerWorkflow.UsesFields(TAtlasTrackerTarget.GitHub), 'GitHub');
  Assert.IsFalse(TAtlasTrackerWorkflow.UsesFields(' GitHub '), 'Schreibweise und Leerraum');
  Assert.IsTrue(TAtlasTrackerWorkflow.UsesFields(''), 'ohne Anbieter');
end;

procedure TAtlasTrackerWorkflowTests.FillReplacesPlaceholders;
var
  mValues: TAtlasTrackerPlaceholders;
begin
  mValues := TAtlasTrackerPlaceholders.Create('ATL-123', 'feature/ATL-123-export');
  mValues.Commits := 'abc1234 ATL-123: Export'#13#10'def5678 ATL-123: Test';
  mValues.PullRequest := 'https://github.com/beispiel/atlas/pull/7';
  mValues.Time := '1 h 25 min';
  Assert.AreEqual('Erledigt in feature/ATL-123-export.'#10'abc1234 ATL-123: Export'#10'def5678 ATL-123: Test',
    TAtlasTrackerWorkflow.Fill(TAtlasTrackerWorkflow.DefaultEndComment, mValues));
  Assert.AreEqual('ATL-123: PR https://github.com/beispiel/atlas/pull/7, Zeit 1 h 25 min',
    TAtlasTrackerWorkflow.Fill('{KENNUNG}: PR {pr}, Zeit {time}', mValues), 'ohne Groß-/Kleinschreibung');
  Assert.AreEqual('ATL-123', TAtlasTrackerWorkflow.Fill('{key}', mValues));
  // Leere Platzhalter am Ende hinterlassen keine Leerzeilen.
  mValues.Commits := '';
  Assert.AreEqual('Erledigt in feature/ATL-123-export.',
    TAtlasTrackerWorkflow.Fill(TAtlasTrackerWorkflow.DefaultEndComment, mValues));
  Assert.AreEqual('{unbekannt} bleibt', TAtlasTrackerWorkflow.Fill('{unbekannt} bleibt', mValues));
end;

procedure TAtlasTrackerWorkflowTests.MentionsKeyAsOwnWord;
begin
  Assert.IsTrue(TAtlasTrackerWorkflow.MentionsKey('ATL-123: Export', 'ATL-123'));
  Assert.IsTrue(TAtlasTrackerWorkflow.MentionsKey('[atl-123] klein', 'ATL-123'));
  Assert.IsTrue(TAtlasTrackerWorkflow.MentionsKey('Fix für #753', '#753'));
  Assert.IsFalse(TAtlasTrackerWorkflow.MentionsKey('ATL-1234: anderes', 'ATL-123'), 'längere Kennung');
  Assert.IsFalse(TAtlasTrackerWorkflow.MentionsKey('XATL-123', 'ATL-123'));
  Assert.IsFalse(TAtlasTrackerWorkflow.MentionsKey('#7531', '#753'));
  Assert.IsFalse(TAtlasTrackerWorkflow.MentionsKey('ATL-123', ''));
end;

procedure TAtlasTrackerWorkflowTests.CommitLinesOldestFirstWithKey;
var
  mCommits: TArray<TAtlasVcsCommit>;
  mIndex: Integer;
  mLines: TArray<string>;
begin
  // Wie git log: neueste zuerst.
  mCommits := TArray<TAtlasVcsCommit>.Create(Commit('3333333aaaa', 'ATL-123: drei'), Commit('2222222bbbb', 'ohne'),
    Commit('1111111cccc', 'ATL-123: eins'));
  Assert.AreEqual('1111111 ATL-123: eins'#10'3333333 ATL-123: drei',
    TAtlasTrackerWorkflow.CommitLines(mCommits, 'ATL-123'));
  Assert.AreEqual('', TAtlasTrackerWorkflow.CommitLines(mCommits, 'ATL-9'));
  mCommits := nil;
  for mIndex := 1 to TAtlasTrackerWorkflow.MaxCommits + 5 do
    mCommits := mCommits + [Commit(Format('%.7d', [mIndex]), 'ATL-123: ' + IntToStr(mIndex))];
  mLines := TAtlasTrackerWorkflow.CommitLines(mCommits, 'ATL-123').Split([#10]);
  Assert.AreEqual(TAtlasTrackerWorkflow.MaxCommits, Integer(Length(mLines)), 'höchstens MaxCommits');
end;

procedure TAtlasTrackerWorkflowTests.CommitsForUsesFirstExistingBase;
var
  mWork: TFakeLocalWork;
  mKeep: IAtlasVcsLocalWork;
begin
  mWork := TFakeLocalWork.Create('master', TArray<TAtlasVcsCommit>.Create(Commit('aaaaaaa1', 'ATL-5: a')));
  mKeep := mWork;
  Assert.AreEqual('aaaaaaa ATL-5: a', TAtlasTrackerWorkflow.CommitsFor(mKeep, 'feature/ATL-5', '', 'ATL-5'));
  Assert.AreEqual(2, Integer(Length(mWork.Asked)), 'main, dann master');
  Assert.AreEqual('main', mWork.Asked[0]);
  mWork.Asked := nil;
  Assert.AreEqual('', TAtlasTrackerWorkflow.CommitsFor(mKeep, 'feature/ATL-5', 'develop', 'ATL-5'),
    'nur issues.branchBase');
  Assert.AreEqual(1, Integer(Length(mWork.Asked)));
  Assert.AreEqual('', TAtlasTrackerWorkflow.CommitsFor(mKeep, '', '', 'ATL-5'), 'ohne Branch');
  Assert.AreEqual('', TAtlasTrackerWorkflow.CommitsFor(nil, 'feature/ATL-5', '', 'ATL-5'), 'ohne Versionsverwaltung');
  mWork.Asked := nil;
end;

procedure TAtlasTrackerWorkflowTests.ForConnectionOverridesGlobal;
var
  mConnection, mOther: TAtlasTrackerConnection;
  mOptions: TAtlasTrackerSyncOptions;
begin
  mConnection := TAtlasTrackerConnection.Create('Firma', 'youtrack', 'https://yt.beispiel.de/');
  mConnection.StateField := 'Status';
  mConnection.EndStates := TArray<string>.Create('Geprüft');
  mOther := TAtlasTrackerConnection.Create('Andere', 'youtrack', 'https://anders.beispiel.de');
  mOther.StateField := 'Falsch';
  mOptions := TAtlasTrackerWorkflow.ForConnection(Options('Erledigt'), TArray<TAtlasTrackerConnection>.Create(mOther,
    mConnection), YouTrackTarget);
  Assert.AreEqual('Status', mOptions.StateField, 'Verbindung mit demselben Server');
  Assert.AreEqual('Assignee', mOptions.AssigneeField, 'leer = global');
  Assert.AreEqual('In Arbeit', mOptions.StartState);
  Assert.AreEqual(1, Integer(Length(mOptions.EndStates)));
  Assert.AreEqual('Geprüft', mOptions.EndStates[0]);
  mOptions := TAtlasTrackerWorkflow.ForConnection(Options('Erledigt'), TArray<TAtlasTrackerConnection>.Create(mOther),
    YouTrackTarget);
  Assert.AreEqual('State', mOptions.StateField, 'ohne passende Verbindung die globalen Werte');
  Assert.AreEqual('Erledigt', mOptions.EndStates[0]);
end;

procedure TAtlasTrackerWorkflowTests.StartChangeOnlyWithSyncState;
var
  mOptions: TAtlasTrackerSyncOptions;
  mChange: TAtlasTrackerWrite;
begin
  mOptions := Options('');
  Assert.IsTrue(mOptions.HasStartWork);
  mChange := TAtlasTrackerWorkflow.StartChange(mOptions, TAtlasTrackerPlaceholders.Create('ATL-1', 'feature/ATL-1'));
  Assert.AreEqual('In Arbeit', mChange.State);
  Assert.AreEqual('State', mChange.StateField);
  Assert.AreEqual(Ord(TAtlasTrackerAssign.Me), Ord(mChange.Assign));
  Assert.AreEqual('Beginne ATL-1', mChange.Comment);
  mOptions.SyncState := False;
  Assert.IsFalse(mOptions.HasStartWork);
  Assert.IsFalse(TAtlasTrackerWorkflow.StartChange(mOptions, TAtlasTrackerPlaceholders.Create('ATL-1', '')).HasWork,
    'syncState aus: „Beginnen“ wie bisher');
  mOptions := TAtlasTrackerSyncOptions.Create(True, '', '', '', False, '', '', '');
  Assert.IsFalse(mOptions.HasStartWork, 'nichts eingestellt');
end;

procedure TAtlasTrackerWorkflowTests.EndChangeStateCommentAndHandOver;
var
  mChange: TAtlasTrackerWrite;
begin
  mChange := TAtlasTrackerWorkflow.EndChange(Options('Erledigt'), 'Erledigt', ' Fertig ', True, ' anna ');
  Assert.AreEqual('Erledigt', mChange.State);
  Assert.AreEqual('In Arbeit', mChange.PreviousState, 'Label aus „Beginnen“ fällt weg');
  Assert.AreEqual('Fertig', mChange.Comment);
  Assert.AreEqual(Ord(TAtlasTrackerAssign.User), Ord(mChange.Assign));
  Assert.AreEqual('anna', mChange.Assignee);
  mChange := TAtlasTrackerWorkflow.EndChange(Options(''), '', '', True, '');
  Assert.IsFalse(mChange.HasWork, 'Zustand bleibt, kein Kommentar, niemand gewählt');
  Assert.AreEqual(Ord(TAtlasTrackerAssign.Keep), Ord(mChange.Assign));
end;

procedure TAtlasTrackerWorkflowTests.DurationText;
begin
  Assert.AreEqual('', TAtlasTrackerWorkflow.DurationText(0));
  Assert.AreEqual('25 min', TAtlasTrackerWorkflow.DurationText(25));
  Assert.AreEqual('2 h', TAtlasTrackerWorkflow.DurationText(120));
  Assert.AreEqual('1 h 25 min', TAtlasTrackerWorkflow.DurationText(85));
end;

procedure TAtlasTrackerWorkflowTests.CommitSubjects;
begin
  Assert.AreEqual('', TAtlasTrackerWorkflow.CommitSubjects(''));
  Assert.AreEqual('Statusfeld zeigt Zeit'#10'Leerlauf erkennen',
    TAtlasTrackerWorkflow.CommitSubjects('a1b2c3d Statusfeld zeigt Zeit'#13#10#13#10'  9f8e7d6  Leerlauf erkennen  '#10));
end;

procedure TAtlasTrackerWorkflowTests.ConnectionKeepsWorkflowFields;
var
  mConnection, mMoved: TAtlasTrackerConnection;
  mRead: TArray<TAtlasTrackerConnection>;
begin
  mConnection := TAtlasTrackerConnection.Create('Firma', 'youtrack', 'https://yt.beispiel.de');
  mConnection.StateField := 'Status';
  mConnection.AssigneeField := 'Zuständig';
  mConnection.StartState := 'In Arbeit';
  mConnection.EndStates := TArray<string>.Create('Zur Prüfung', 'Erledigt');
  // Andere Adresse auf der Optionsseite: die Werte für Zustand und Zuständigkeit bleiben.
  mMoved := mConnection.WithUrl(' https://neu.beispiel.de/ ');
  Assert.AreEqual('https://neu.beispiel.de', mMoved.Url);
  Assert.AreEqual('Status', mMoved.StateField);
  Assert.AreEqual('Zuständig', mMoved.AssigneeField);
  Assert.AreEqual('In Arbeit', mMoved.StartState);
  Assert.AreEqual(2, Integer(Length(mMoved.EndStates)));
  mRead := TAtlasTrackerConnections.Read(TAtlasTrackerConnections.ToJson(TArray<TAtlasTrackerConnection>.Create(
    mMoved)));
  Assert.AreEqual(1, Integer(Length(mRead)));
  Assert.AreEqual('Status', mRead[0].StateField);
  Assert.AreEqual('Zuständig', mRead[0].AssigneeField);
  Assert.AreEqual('In Arbeit', mRead[0].StartState);
  Assert.AreEqual('Erledigt', mRead[0].EndStates[1]);
  // Ohne Werte bleiben die Schlüssel weg.
  Assert.IsFalse(TAtlasTrackerConnections.ToJson(TArray<TAtlasTrackerConnection>.Create(
    TAtlasTrackerConnection.Create('X', 'github', 'https://github.com'))).Contains('stateField'));
end;

{ TAtlasTrackerWriterTests }

procedure TAtlasTrackerWriterTests.YouTrackCommandWithBraces;
var
  mChange: TAtlasTrackerWrite;
begin
  Assert.AreEqual('Erledigt', TAtlasYouTrackTracker.CommandWord('Erledigt'));
  Assert.AreEqual('Geprüft', TAtlasYouTrackTracker.CommandWord(' Geprüft '), 'Umlaute ohne Klammern');
  Assert.AreEqual('{In Arbeit}', TAtlasYouTrackTracker.CommandWord('In Arbeit'));
  Assert.AreEqual('{Won''t fix}', TAtlasYouTrackTracker.CommandWord('Won''t fix'));
  Assert.AreEqual('{a b}', TAtlasYouTrackTracker.CommandWord('a {b}'), 'Klammern im Namen entfallen');
  mChange := TAtlasTrackerWrite.Empty;
  mChange.StateField := 'Status';
  mChange.State := 'In Arbeit';
  mChange.Assign := TAtlasTrackerAssign.Me;
  Assert.AreEqual('Status {In Arbeit} Assignee me', TAtlasYouTrackTracker.CommandQuery(mChange));
  mChange.AssigneeField := 'Zuständige Person';
  mChange.Assign := TAtlasTrackerAssign.User;
  mChange.Assignee := 'anna.m';
  Assert.AreEqual('Status {In Arbeit} {Zuständige Person} anna.m', TAtlasYouTrackTracker.CommandQuery(mChange));
  mChange := TAtlasTrackerWrite.CommentOnly('Nur Text');
  Assert.AreEqual('', TAtlasYouTrackTracker.CommandQuery(mChange), 'nur Kommentar: kein Befehl');
end;

procedure TAtlasTrackerWriterTests.YouTrackCommandJson;
var
  mJson: string;
  mValue: TJSONValue;
begin
  mJson := TAtlasYouTrackTracker.CommandJson('ATL-123', 'State {In Arbeit} Assignee me', 'Beginne');
  Assert.AreEqual('State {In Arbeit} Assignee me', JsonText(mJson, 'query'));
  Assert.AreEqual('Beginne', JsonText(mJson, 'comment'));
  mValue := TJSONObject.ParseJSONValue(mJson);
  try
    Assert.AreEqual('ATL-123', TJSONObject(TJSONArray(TJSONObject(mValue).Values['issues']).Items[0])
      .Values['idReadable'].Value);
  finally
    mValue.Free;
  end;
  Assert.AreEqual('', JsonText(TAtlasYouTrackTracker.CommandJson('ATL-1', 'State Erledigt', ''), 'comment'),
    'ohne Kommentar kein Feld');
  Assert.AreEqual('Hallo', JsonText(TAtlasYouTrackTracker.CommentJson('Hallo'), 'text'));
end;

procedure TAtlasTrackerWriterTests.YouTrackApplyCommandOrComment;
var
  mTransport: TFakeSendTransport;
  mKeep: IAtlasCiTransport;
  mWriter: IAtlasTrackerWriter;
  mChange: TAtlasTrackerWrite;
  mResult: TAtlasTrackerWriteResult;
begin
  mWriter := TAtlasYouTrackTracker.Create;
  mTransport := TFakeSendTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('POST', 'https://yt.beispiel.de/api/commands', 200, '{}');
  mTransport.Answer('POST', 'https://yt.beispiel.de/api/issues/ATL-123/comments', 200, '{"id":"1"}');
  mChange := TAtlasTrackerWrite.Empty;
  mChange.State := 'In Arbeit';
  mChange.Comment := 'Beginne';
  mResult := mWriter.Apply(YouTrackTarget, mKeep, 'ATL-123', mChange, 5000);
  Assert.IsTrue(mResult.Succeeded);
  Assert.AreEqual(1, Integer(Length(mTransport.Calls)), 'Zustand und Kommentar in einem Befehl');
  Assert.AreEqual('POST https://yt.beispiel.de/api/commands', mTransport.Calls[0]);
  Assert.AreEqual('State {In Arbeit}', JsonText(mTransport.Bodies[0], 'query'));
  Assert.AreEqual('Beginne', JsonText(mTransport.Bodies[0], 'comment'));
  mResult := mWriter.Apply(YouTrackTarget, mKeep, 'ATL-123', TAtlasTrackerWrite.CommentOnly('Nur Text'), 5000);
  Assert.IsTrue(mResult.Succeeded);
  Assert.AreEqual('POST https://yt.beispiel.de/api/issues/ATL-123/comments?fields=id', mTransport.Calls[1]);
  Assert.AreEqual('Nur Text', JsonText(mTransport.Bodies[1], 'text'));
  // Nichts zu tun: kein Aufruf.
  Assert.IsTrue(mWriter.Apply(YouTrackTarget, mKeep, 'ATL-123', TAtlasTrackerWrite.Empty, 5000).Succeeded);
  Assert.AreEqual(2, Integer(Length(mTransport.Calls)));
  // Ungültige Kennung: nichts senden.
  Assert.IsFalse(mWriter.Apply(YouTrackTarget, mKeep, 'ATL 1/../x', TAtlasTrackerWrite.CommentOnly('x'),
    5000).Succeeded);
  Assert.AreEqual(2, Integer(Length(mTransport.Calls)));
end;

procedure TAtlasTrackerWriterTests.YouTrackValues;
const
  cProjects = '[{"shortName":"ATL","customFields":[' +
    '{"field":{"name":"Status","fieldType":{"id":"state[1]"}},"bundle":{"values":[{"name":"Offen","archived":false},' +
    '{"name":"In Arbeit","archived":false},{"name":"Alt","archived":true}]}},' +
    '{"field":{"name":"Zuständig","fieldType":{"id":"user[1]"}},"bundle":{"values":[]}}]},' +
    '{"shortName":"XYZ","customFields":[{"field":{"name":"Status","fieldType":{"id":"state[1]"}},' +
    '"bundle":{"values":[{"name":"Fremd","archived":false}]}}]}]';
var
  mValues: TArray<string>;
begin
  Assert.IsTrue(TAtlasYouTrackTracker.ParseFieldValues(cProjects, 'ATL', TAtlasTrackerValueKind.States, 'Status',
    mValues));
  Assert.AreEqual(2, Integer(Length(mValues)), 'archivierte entfallen, nur das eigene Projekt');
  Assert.AreEqual('In Arbeit', mValues[1]);
  Assert.IsTrue(TAtlasYouTrackTracker.ParseFieldValues(cProjects, 'ATL', TAtlasTrackerValueKind.StateFields, '',
    mValues));
  Assert.AreEqual(1, Integer(Length(mValues)));
  Assert.AreEqual('Status', mValues[0]);
  Assert.IsTrue(TAtlasYouTrackTracker.ParseFieldValues(cProjects, 'ATL', TAtlasTrackerValueKind.UserFields, '',
    mValues));
  Assert.AreEqual('Zuständig', mValues[0]);
  Assert.IsTrue(TAtlasYouTrackTracker.ParseFieldValues(cProjects, '', TAtlasTrackerValueKind.States, 'Status',
    mValues));
  Assert.AreEqual(3, Integer(Length(mValues)), 'ohne Projekt alle Projekte');
  Assert.IsTrue(TAtlasYouTrackTracker.ParseUsers('[{"login":"anna","banned":false},{"login":"alt","banned":true},' +
    '{"login":"bert"}]', mValues));
  Assert.AreEqual(2, Integer(Length(mValues)), 'gesperrte entfallen');
  Assert.AreEqual('bert', mValues[1]);
  Assert.IsFalse(TAtlasYouTrackTracker.ParseUsers('kein JSON', mValues));
end;

procedure TAtlasTrackerWriterTests.YouTrackErrors;
var
  mTransport: TFakeSendTransport;
  mKeep: IAtlasCiTransport;
  mWriter: IAtlasTrackerWriter;
  mResult: TAtlasTrackerWriteResult;
  mChange: TAtlasTrackerWrite;
begin
  mWriter := TAtlasYouTrackTracker.Create;
  mChange := TAtlasTrackerWrite.Empty;
  mChange.State := 'Erledigt';
  mTransport := TFakeSendTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('POST', 'https://yt.beispiel.de/api/commands', 403,
    '{"error":"Forbidden","error_description":"Keine Rechte für ATL-123"}');
  mResult := mWriter.Apply(YouTrackTarget, mKeep, 'ATL-123', mChange, 5000);
  Assert.AreEqual(Ord(TAtlasCiFetchError.Unauthorized), Ord(mResult.Error));
  Assert.AreEqual(403, mResult.Status);
  Assert.AreEqual('Keine Rechte für ATL-123', mResult.Message, 'Text des Trackers');
  Assert.AreEqual(1, Integer(Length(mTransport.Calls)), 'nichts wird wiederholt');
  mTransport := TFakeSendTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('POST', 'https://yt.beispiel.de/api/commands', 400, '{"error":"invalid_query"}');
  mResult := mWriter.Apply(YouTrackTarget, mKeep, 'ATL-123', mChange, 5000);
  Assert.AreEqual(Ord(TAtlasCiFetchError.Invalid), Ord(mResult.Error));
  Assert.AreEqual(400, mResult.Status);
  Assert.AreEqual('invalid_query', mResult.Message);
  mTransport := TFakeSendTransport.Create;
  mKeep := mTransport;
  mResult := mWriter.Apply(YouTrackTarget, mKeep, 'ATL-123', mChange, 5000);
  Assert.AreEqual(Ord(TAtlasCiFetchError.NotFound), Ord(mResult.Error), 'ohne Antwort 404');
  Assert.AreEqual(404, mResult.Status);
end;

procedure TAtlasTrackerWriterTests.GitHubPatchJson;
var
  mChange: TAtlasTrackerWrite;
  mJson: string;
begin
  Assert.IsTrue(TAtlasGitHubTracker.ClosesIssue('Erledigt'));
  Assert.IsTrue(TAtlasGitHubTracker.ClosesIssue('done'));
  Assert.IsFalse(TAtlasGitHubTracker.ClosesIssue('Zur Prüfung'));
  // Beginnen: Label dazu, mich als Zuständigen dazu.
  mChange := TAtlasTrackerWrite.Empty;
  mChange.State := 'in arbeit';
  mChange.Assign := TAtlasTrackerAssign.Me;
  mJson := TAtlasGitHubTracker.PatchJson(TArray<string>.Create('bug'), TArray<string>.Create('bert'), mChange, 'anna');
  Assert.AreEqual('["bug","in arbeit"]', JsonText(mJson, 'labels'));
  Assert.AreEqual('["bert","anna"]', JsonText(mJson, 'assignees'));
  Assert.AreEqual('', JsonText(mJson, 'state'));
  // Schon so: nichts zu ändern.
  Assert.AreEqual('', TAtlasGitHubTracker.PatchJson(TArray<string>.Create('in arbeit'), TArray<string>.Create('anna'),
    mChange, 'anna'));
  // Beenden: Label aus „Beginnen“ weg, „Erledigt“ schließt (ohne Label), übergeben ersetzt die Zuständigen.
  mChange := TAtlasTrackerWrite.Empty;
  mChange.State := 'Erledigt';
  mChange.PreviousState := 'in arbeit';
  mChange.Assign := TAtlasTrackerAssign.User;
  mChange.Assignee := 'carl';
  mJson := TAtlasGitHubTracker.PatchJson(TArray<string>.Create('bug', 'In Arbeit'), TArray<string>.Create('anna',
    'bert'), mChange, '');
  Assert.AreEqual('["bug"]', JsonText(mJson, 'labels'));
  Assert.AreEqual('["carl"]', JsonText(mJson, 'assignees'));
  Assert.AreEqual('closed', JsonText(mJson, 'state'));
  Assert.AreEqual('completed', JsonText(mJson, 'state_reason'));
end;

procedure TAtlasTrackerWriterTests.GitHubApplyAgainstFakeTransport;
var
  mTransport: TFakeSendTransport;
  mKeep: IAtlasCiTransport;
  mWriter: IAtlasTrackerWriter;
  mChange: TAtlasTrackerWrite;
begin
  mWriter := TAtlasGitHubTracker.Create;
  mTransport := TFakeSendTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('GET', 'https://api.github.com/user', 200, '{"login":"anna"}');
  mTransport.Answer('POST', 'https://api.github.com/repos/beispiel/atlas/issues/7/comments', 201, '{"id":1}');
  mTransport.Answer('GET', 'https://api.github.com/repos/beispiel/atlas/issues/7', 200,
    '{"number":7,"labels":[{"name":"bug"}],"assignees":[]}');
  mTransport.Answer('PATCH', 'https://api.github.com/repos/beispiel/atlas/issues/7', 200, '{"number":7}');
  mChange := TAtlasTrackerWrite.Empty;
  mChange.State := 'In Arbeit';
  mChange.Assign := TAtlasTrackerAssign.Me;
  mChange.Comment := 'Beginne';
  Assert.IsTrue(mWriter.Apply(GitHubTarget, mKeep, '#7', mChange, 5000).Succeeded);
  Assert.AreEqual(4, Integer(Length(mTransport.Calls)));
  Assert.AreEqual('GET https://api.github.com/user', mTransport.Calls[0]);
  Assert.AreEqual('POST https://api.github.com/repos/beispiel/atlas/issues/7/comments', mTransport.Calls[1],
    'Kommentar zuerst');
  Assert.AreEqual('GET https://api.github.com/repos/beispiel/atlas/issues/7', mTransport.Calls[2]);
  Assert.AreEqual('PATCH https://api.github.com/repos/beispiel/atlas/issues/7', mTransport.Calls[3]);
  Assert.AreEqual('Beginne', JsonText(mTransport.Bodies[0], 'body'));
  Assert.AreEqual('["bug","In Arbeit"]', JsonText(mTransport.Bodies[1], 'labels'));
  Assert.AreEqual('["anna"]', JsonText(mTransport.Bodies[1], 'assignees'));
  // Nur ein Kommentar: kein GET und kein PATCH.
  mTransport.Calls := nil;
  Assert.IsTrue(mWriter.Apply(GitHubTarget, mKeep, '#7', TAtlasTrackerWrite.CommentOnly('Hallo'), 5000).Succeeded);
  Assert.AreEqual(1, Integer(Length(mTransport.Calls)));
  mTransport.Calls := nil;
  mTransport.Bodies := nil;
end;

procedure TAtlasTrackerWriterTests.GitHubForbiddenStopsBeforeChange;
var
  mTransport: TFakeSendTransport;
  mKeep: IAtlasCiTransport;
  mWriter: IAtlasTrackerWriter;
  mChange: TAtlasTrackerWrite;
  mResult: TAtlasTrackerWriteResult;
begin
  mWriter := TAtlasGitHubTracker.Create;
  mTransport := TFakeSendTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('POST', 'https://api.github.com/repos/beispiel/atlas/issues/7/comments', 403,
    '{"message":"Must have admin rights to Repository."}');
  mChange := TAtlasTrackerWrite.Empty;
  mChange.State := 'Erledigt';
  mChange.Comment := 'Fertig';
  mResult := mWriter.Apply(GitHubTarget, mKeep, '#7', mChange, 5000);
  Assert.AreEqual(Ord(TAtlasCiFetchError.Unauthorized), Ord(mResult.Error));
  Assert.AreEqual(403, mResult.Status);
  Assert.AreEqual('Must have admin rights to Repository.', mResult.Message);
  Assert.AreEqual(1, Integer(Length(mTransport.Calls)), 'nach 403 keine Änderung am Issue');
  // 404 beim Lesen des Issues.
  mTransport := TFakeSendTransport.Create;
  mKeep := mTransport;
  mResult := mWriter.Apply(GitHubTarget, mKeep, '#8', TAtlasTrackerWrite.Empty, 5000);
  Assert.IsTrue(mResult.Succeeded, 'nichts zu tun');
  mChange := TAtlasTrackerWrite.Empty;
  mChange.State := 'Zur Prüfung';
  mResult := mWriter.Apply(GitHubTarget, mKeep, '#8', mChange, 5000);
  Assert.AreEqual(Ord(TAtlasCiFetchError.NotFound), Ord(mResult.Error));
  Assert.AreEqual(404, mResult.Status);
end;

procedure TAtlasTrackerWriterTests.GitHubValues;
var
  mTransport: TFakeSendTransport;
  mKeep: IAtlasCiTransport;
  mWriter: IAtlasTrackerWriter;
  mValues: TArray<string>;
begin
  mWriter := TAtlasGitHubTracker.Create;
  mTransport := TFakeSendTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('GET', 'https://api.github.com/repos/beispiel/atlas/labels', 200,
    '[{"name":"bug"},{"name":"In Arbeit"}]');
  mTransport.Answer('GET', 'https://api.github.com/repos/beispiel/atlas/assignees', 200, '[{"login":"anna"}]');
  Assert.IsTrue(mWriter.Values(GitHubTarget, mKeep, TAtlasTrackerValueKind.States, '', 5000, mValues).Succeeded);
  Assert.AreEqual(2, Integer(Length(mValues)));
  Assert.AreEqual('In Arbeit', mValues[1]);
  Assert.IsTrue(mWriter.Values(GitHubTarget, mKeep, TAtlasTrackerValueKind.Users, '', 5000, mValues).Succeeded);
  Assert.AreEqual('anna', mValues[0]);
  Assert.IsTrue(mWriter.Values(GitHubTarget, mKeep, TAtlasTrackerValueKind.StateFields, '', 5000,
    mValues).Succeeded);
  Assert.AreEqual(0, Integer(Length(mValues)), 'GitHub kennt keine Felder');
  Assert.AreEqual(2, Integer(Length(mTransport.Calls)), 'Felder ohne Netz');
end;

procedure TAtlasTrackerWriterTests.LoadValuesStopsAtFirstError;
var
  mTransport: TFakeSendTransport;
  mKeep: IAtlasCiTransport;
  mWriter: IAtlasTrackerWriter;
  mValues: TAtlasTrackerValueSet;
begin
  // Über eine Variable: ein frisch erzeugtes Objekt als const-Interface-Parameter würde nie freigegeben.
  mWriter := TAtlasYouTrackTracker.Create;
  mTransport := TFakeSendTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('GET', 'https://yt.beispiel.de/api/admin/projects', 403, '{"error":"Forbidden"}');
  mValues := TAtlasTrackerWorkflow.LoadValues(mWriter, YouTrackTarget, mKeep, '');
  Assert.IsFalse(mValues.Outcome.Succeeded);
  Assert.AreEqual(403, mValues.Outcome.Status);
  Assert.AreEqual(1, Integer(Length(mTransport.Calls)), 'nach dem ersten Fehler keine weitere Abfrage');
  mValues := TAtlasTrackerWorkflow.LoadValues(nil, YouTrackTarget, mKeep, '');
  Assert.AreEqual(Ord(TAtlasCiFetchError.UnknownProvider), Ord(mValues.Outcome.Error), 'Anbieter ohne Schreiben');
end;

procedure TAtlasTrackerWriterTests.WithoutSendIsNotConfigured;
var
  mKeep: IAtlasCiTransport;
  mResult: TAtlasTrackerWriteResult;
begin
  // Ein Transport ohne IAtlasCiSend (kein Token für das Schreiben): nichts geschrieben, Grund „nicht eingerichtet“.
  mKeep := TFakeGetTransport.Create;
  mResult := (TAtlasYouTrackTracker.Create as IAtlasTrackerWriter).Apply(YouTrackTarget, mKeep, 'ATL-1',
    TAtlasTrackerWrite.CommentOnly('x'), 5000);
  Assert.AreEqual(Ord(TAtlasCiFetchError.NotConfigured), Ord(mResult.Error));
  mResult := (TAtlasGitHubTracker.Create as IAtlasTrackerWriter).Apply(GitHubTarget, mKeep, '#1',
    TAtlasTrackerWrite.CommentOnly('x'), 5000);
  Assert.AreEqual(Ord(TAtlasCiFetchError.NotConfigured), Ord(mResult.Error));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerWorkflowTests);
  TDUnitX.RegisterTestFixture(TAtlasTrackerWriterTests);

end.
