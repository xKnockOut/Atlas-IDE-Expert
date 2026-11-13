unit Atlas.Core.Tracker.Internals.GitHubProjects.Tests;

// Status im GitHub-Projekt beim Beginnen und Beenden (#2134) gegen eine
// Fake-Transportschicht: Lesen der Projekteinträge, Zuordnung Zustand →
// Option, Aufnahme ins Projekt, Rückfall auf das Label, Fehler mit Grund,
// Schließen nach dem Status, Werte für die Klapplisten und die Optionen aus
// Einstellungen und Verbindung. GraphQL-Rümpfe werden als Text verglichen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasGitHubProjectsTests = class
  public
    [Test]
    procedure ParseItemsReadsStatusFieldOptionsAndCurrent;
    [Test]
    procedure ChooseTakesConfiguredProjectElseFirst;
    [Test]
    procedure OptionOfIgnoresCase;
    [Test]
    procedure StartSetsProjectStatusInsteadOfLabel;
    [Test]
    procedure SameStatusWritesNothing;
    [Test]
    procedure AddsIssueToConfiguredProject;
    [Test]
    procedure WithoutProjectKeepsLabel;
    [Test]
    procedure MissingProjectScopeKeepsLabelAndSaysSo;
    [Test]
    procedure MissingOptionFailsWithReason;
    [Test]
    procedure LabelTargetDoesNotAskProjects;
    [Test]
    procedure EndSetsStatusThenCloses;
    [Test]
    procedure NotPlannedKeepsProjectUntouched;
    [Test]
    procedure ValuesListProjectsAndOptions;
    [Test]
    procedure OptionsFromSettingsAndConnection;
    [Test]
    procedure ConnectionKeepsGitHubFields;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.Workflow,
  Atlas.Core.Tracker.Providers.GitHub,
  Atlas.Core.Tracker.Internals.GitHubGraphQl,
  Atlas.Core.Tracker.Internals.GitHubProjects;

const
  cIssueUrl = 'https://api.github.com/repos/beispiel/atlas/issues/7';
  cGraphQlUrl = 'https://api.github.com/graphql';
  cIssueJson = '{"number":7,"node_id":"I_7","labels":[{"name":"bug"}],"assignees":[]}';
  /// <summary>Statusfeld mit drei Optionen; davor ein Prioritätsfeld, das nicht zählt.</summary>
  cFields = '"fields":{"nodes":[{},{"id":"F_P","name":"Priority","options":[{"id":"P1","name":"Hoch"}]},' +
    '{"id":"F_S","name":"Status","options":[{"id":"O_T","name":"Todo"},{"id":"O_I","name":"In Progress"},' +
    '{"id":"O_D","name":"Done"}]}]}';
  cProject4 = '{"id":"P_4","title":"Atlas 2.1","number":4,"owner":{"login":"beispiel"},' + cFields + '}';
  cProject9 = '{"id":"P_9","title":"Wartung","number":9,"owner":{"login":"beispiel"},' + cFields + '}';
  cItemTodo = '{"id":"IT_4","project":' + cProject4 + ',"fieldValues":{"nodes":[{},{"name":"Todo",' +
    '"field":{"id":"F_S"}}]}}';
  cItemsTodo = '{"data":{"node":{"projectItems":{"nodes":[' + cItemTodo + ']}}}}';
  cItemsNone = '{"data":{"node":{"projectItems":{"nodes":[]}}}}';
  cProjects = '{"data":{"repository":{"projectsV2":{"nodes":[' + cProject9 + ',' + cProject4 + ']}}}}';
  cSetOk = '{"data":{"updateProjectV2ItemFieldValue":{"projectV2Item":{"id":"IT_4"}}}}';
  cNoScope = '{"data":null,"errors":[{"type":"INSUFFICIENT_SCOPES","message":"Your token has not been granted ' +
    'the required scopes."}]}';

type
  /// <summary>Antworten je Methode, Adressanfang und Textstück im Inhalt ('' = jeder); merkt sich alle Aufrufe.
  /// </summary>
  TFakeProjectTransport = class(TInterfacedObject, IAtlasCiTransport, IAtlasCiSend)
  private
    FMethods: TArray<string>;
    FPrefixes: TArray<string>;
    FParts: TArray<string>;
    FStatus: TArray<Integer>;
    FTexts: TArray<string>;
    function Reply(const AMethod, AUrl, ABody: string; out AStatus: Integer; out AText: string): Boolean;
  public
    Calls: TArray<string>;
    Bodies: TArray<string>;
    procedure Answer(const AMethod, APrefix, APart: string; AStatus: Integer; const AText: string);
    function Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
    function Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer; out AResponse: TAtlasCiResponse):
      Boolean;
  end;

procedure TFakeProjectTransport.Answer(const AMethod, APrefix, APart: string; AStatus: Integer;
  const AText: string);
begin
  FMethods := FMethods + [AMethod];
  FPrefixes := FPrefixes + [APrefix];
  FParts := FParts + [APart];
  FStatus := FStatus + [AStatus];
  FTexts := FTexts + [AText];
end;

function TFakeProjectTransport.Reply(const AMethod, AUrl, ABody: string; out AStatus: Integer;
  out AText: string): Boolean;
var
  mIndex: Integer;
begin
  Calls := Calls + [AMethod + ' ' + AUrl];
  Bodies := Bodies + [ABody];
  AStatus := 404;
  AText := '';
  Result := True;
  for mIndex := 0 to High(FMethods) do
  begin
    if (FMethods[mIndex] = AMethod) and (Copy(AUrl, 1, Length(FPrefixes[mIndex])) = FPrefixes[mIndex]) and
      ((FParts[mIndex] = '') or (Pos(FParts[mIndex], ABody) > 0)) then
    begin
      AStatus := FStatus[mIndex];
      AText := FTexts[mIndex];
      Exit;
    end;
  end;
end;

function TFakeProjectTransport.Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer;
  out AText: string; out AError: TAtlasCiFetchError): Boolean;
begin
  AError := TAtlasCiFetchError.None;
  Result := Reply('GET', AUrl, '', AStatus, AText);
end;

function TFakeProjectTransport.Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer;
  out AResponse: TAtlasCiResponse): Boolean;
begin
  AResponse := TAtlasCiResponse.Failed(TAtlasCiFetchError.None);
  Result := Reply(AMethod, AUrl, ABody, AResponse.Status, AResponse.Text);
end;

function GitHubTarget: TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create('github', '', 'beispiel/atlas', '');
end;

/// <summary>Transport mit dem Issue #7 (node_id I_7) und den Antworten für Einträge und Setzen.</summary>
function IssueTransport(const AItems: string): TFakeProjectTransport;
begin
  Result := TFakeProjectTransport.Create;
  Result.Answer('GET', cIssueUrl, '', 200, cIssueJson);
  Result.Answer('PATCH', cIssueUrl, '', 200, '{"number":7}');
  Result.Answer('POST', cGraphQlUrl, 'projectItems', 200, AItems);
  Result.Answer('POST', cGraphQlUrl, 'updateProjectV2ItemFieldValue', 200, cSetOk);
end;

/// <summary>Beginnen mit Zustand AState und Projektstatus.</summary>
function StartChange(const AState: string): TAtlasTrackerWrite;
begin
  Result := TAtlasTrackerWrite.Empty;
  Result.State := AState;
  Result.GitHub.ToProject := True;
end;

/// <summary>Wert AName im JSON-Objekt AJson als Text (Listen als JSON); '' ohne.</summary>
function JsonText(const AJson, AName: string): string;
var
  mValue, mItem: TJSONValue;
begin
  Result := '';
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if mValue is TJSONObject then
    begin
      mItem := TJSONObject(mValue).Values[AName];
      if mItem is TJSONArray then
      begin
        Result := mItem.ToJSON;
      end
      else if mItem <> nil then
      begin
        Result := mItem.Value;
      end;
    end;
  finally
    mValue.Free;
  end;
end;

/// <summary>Index des ersten Aufrufs, dessen Inhalt APart enthält; -1 ohne.</summary>
function BodyWith(ATransport: TFakeProjectTransport; const APart: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ATransport.Bodies) do
  begin
    if Pos(APart, ATransport.Bodies[mIndex]) > 0 then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure Clear(ATransport: TFakeProjectTransport);
begin
  ATransport.Calls := nil;
  ATransport.Bodies := nil;
end;

{ TAtlasGitHubProjectsTests }

procedure TAtlasGitHubProjectsTests.ParseItemsReadsStatusFieldOptionsAndCurrent;
var
  mItems: TArray<TAtlasGitHubProjectItem>;
begin
  Assert.IsTrue(TAtlasGitHubProjects.ParseItems(cItemsTodo, mItems));
  Assert.AreEqual(1, Integer(Length(mItems)));
  Assert.AreEqual('IT_4', mItems[0].ItemId);
  Assert.AreEqual('P_4', mItems[0].ProjectId);
  Assert.AreEqual('Atlas 2.1', mItems[0].Title);
  Assert.AreEqual('beispiel/4', mItems[0].Ref);
  Assert.AreEqual('F_S', mItems[0].FieldId, 'Status geht vor, Priorität zählt nicht');
  Assert.AreEqual(3, Integer(Length(mItems[0].Options)));
  Assert.AreEqual('O_I', mItems[0].Options[1].Id);
  Assert.AreEqual('Todo', mItems[0].Current);
  Assert.IsFalse(TAtlasGitHubProjects.ParseItems('kein JSON', mItems));
  Assert.IsTrue(TAtlasGitHubProjects.ParseItems(cItemsNone, mItems));
  Assert.AreEqual(0, Integer(Length(mItems)));
end;

procedure TAtlasGitHubProjectsTests.ChooseTakesConfiguredProjectElseFirst;
var
  mItems: TArray<TAtlasGitHubProjectItem>;
begin
  Assert.IsTrue(TAtlasGitHubProjects.ParseProjects(cProjects, mItems));
  Assert.AreEqual(2, Integer(Length(mItems)));
  Assert.AreEqual('', mItems[0].ItemId, 'Projekte des Repositorys ohne Eintrag');
  Assert.AreEqual(1, TAtlasGitHubProjects.Choose(mItems, ' Beispiel/4 '));
  Assert.AreEqual(0, TAtlasGitHubProjects.Choose(mItems, ''), 'ohne Einstellung das erste');
  Assert.AreEqual(0, TAtlasGitHubProjects.Choose(mItems, 'beispiel/77'), 'unbekannt: das erste');
  Assert.AreEqual(-1, TAtlasGitHubProjects.Choose(nil, 'beispiel/4'));
end;

procedure TAtlasGitHubProjectsTests.OptionOfIgnoresCase;
var
  mItems: TArray<TAtlasGitHubProjectItem>;
  mOption: TAtlasGitHubProjectOption;
begin
  TAtlasGitHubProjects.ParseItems(cItemsTodo, mItems);
  Assert.IsTrue(TAtlasGitHubProjects.OptionOf(mItems[0], ' in progress ', mOption));
  Assert.AreEqual('O_I', mOption.Id);
  Assert.AreEqual('In Progress', mOption.Name);
  Assert.IsFalse(TAtlasGitHubProjects.OptionOf(mItems[0], 'In Arbeit', mOption));
  Assert.AreEqual('Todo, In Progress, Done', string.Join(', ', TAtlasGitHubProjects.OptionNames(mItems[0])));
end;

procedure TAtlasGitHubProjectsTests.StartSetsProjectStatusInsteadOfLabel;
var
  mTransport: TFakeProjectTransport;
  mKeep: IAtlasCiTransport;
  mWriter: IAtlasTrackerWriter;
  mResult: TAtlasTrackerWriteResult;
  mSet: Integer;
begin
  mWriter := TAtlasGitHubTracker.Create;
  mTransport := IssueTransport(cItemsTodo);
  mKeep := mTransport;
  mResult := mWriter.Apply(GitHubTarget, mKeep, '#7', StartChange('in progress'), 5000);
  Assert.IsTrue(mResult.Succeeded, mResult.Message);
  // Issue lesen, Einträge lesen, Status setzen; kein PATCH, weil kein Label zu ändern ist.
  Assert.AreEqual('GET ' + cIssueUrl + ' | POST ' + cGraphQlUrl + ' | POST ' + cGraphQlUrl,
    string.Join(' | ', mTransport.Calls));
  Assert.AreEqual(TAtlasGitHubGraphQl.Body(TAtlasGitHubProjects.cItemsQuery, ['id', 'I_7']), mTransport.Bodies[1]);
  mSet := BodyWith(mTransport, 'updateProjectV2ItemFieldValue');
  Assert.AreEqual(2, mSet);
  Assert.AreEqual(TAtlasGitHubGraphQl.Body(TAtlasGitHubProjects.cSetMutation, ['project', 'P_4', 'item', 'IT_4',
    'field', 'F_S', 'option', 'O_I']), mTransport.Bodies[mSet]);
  Assert.AreEqual('Atlas 2.1', mResult.Project.Project);
  Assert.AreEqual('Todo', mResult.Project.Before);
  Assert.AreEqual('In Progress', mResult.Project.After);
  Assert.IsFalse(mResult.Project.Several);
  Clear(mTransport);
end;

procedure TAtlasGitHubProjectsTests.SameStatusWritesNothing;
var
  mTransport: TFakeProjectTransport;
  mKeep: IAtlasCiTransport;
  mWriter: IAtlasTrackerWriter;
  mResult: TAtlasTrackerWriteResult;
begin
  mWriter := TAtlasGitHubTracker.Create;
  mTransport := IssueTransport(cItemsTodo);
  mKeep := mTransport;
  mResult := mWriter.Apply(GitHubTarget, mKeep, '#7', StartChange('Todo'), 5000);
  Assert.IsTrue(mResult.Succeeded);
  Assert.AreEqual(-1, BodyWith(mTransport, 'updateProjectV2ItemFieldValue'), 'steht schon dort');
  Assert.AreEqual('Todo', mResult.Project.After);
  Clear(mTransport);
end;

procedure TAtlasGitHubProjectsTests.AddsIssueToConfiguredProject;
var
  mTransport: TFakeProjectTransport;
  mKeep: IAtlasCiTransport;
  mWriter: IAtlasTrackerWriter;
  mChange: TAtlasTrackerWrite;
  mResult: TAtlasTrackerWriteResult;
  mAdd, mSet: Integer;
begin
  mWriter := TAtlasGitHubTracker.Create;
  mTransport := IssueTransport(cItemsNone);
  mKeep := mTransport;
  mTransport.Answer('POST', cGraphQlUrl, 'projectsV2', 200, cProjects);
  mTransport.Answer('POST', cGraphQlUrl, 'addProjectV2ItemById', 200,
    '{"data":{"addProjectV2ItemById":{"item":{"id":"IT_NEU"}}}}');
  mChange := StartChange('In Progress');
  mChange.GitHub.AddToProject := True;
  mChange.GitHub.Project := 'beispiel/4';
  mResult := mWriter.Apply(GitHubTarget, mKeep, '#7', mChange, 5000);
  Assert.IsTrue(mResult.Succeeded, mResult.Message);
  Assert.AreEqual(TAtlasGitHubGraphQl.Body(TAtlasGitHubProjects.cProjectsQuery, ['owner', 'beispiel', 'name',
    'atlas']), mTransport.Bodies[BodyWith(mTransport, 'projectsV2')]);
  mAdd := BodyWith(mTransport, 'addProjectV2ItemById');
  Assert.AreEqual(TAtlasGitHubGraphQl.Body(TAtlasGitHubProjects.cAddMutation, ['project', 'P_4', 'content', 'I_7']),
    mTransport.Bodies[mAdd]);
  mSet := BodyWith(mTransport, 'updateProjectV2ItemFieldValue');
  Assert.IsTrue(mSet > mAdd, 'erst aufnehmen, dann Status setzen');
  Assert.IsTrue(Pos('"IT_NEU"', mTransport.Bodies[mSet]) > 0);
  Assert.IsTrue(mResult.Project.Added);
  Assert.AreEqual('Atlas 2.1', mResult.Project.Project);
  Assert.AreEqual('', mResult.Project.Before);
  Clear(mTransport);
end;

procedure TAtlasGitHubProjectsTests.WithoutProjectKeepsLabel;
var
  mTransport: TFakeProjectTransport;
  mKeep: IAtlasCiTransport;
  mWriter: IAtlasTrackerWriter;
  mResult: TAtlasTrackerWriteResult;
  mPatch: Integer;
begin
  mWriter := TAtlasGitHubTracker.Create;
  mTransport := IssueTransport(cItemsNone);
  mKeep := mTransport;
  // Ohne addToProject (bzw. ohne eingestelltes Projekt) bleibt es beim Label.
  mResult := mWriter.Apply(GitHubTarget, mKeep, '#7', StartChange('In Progress'), 5000);
  Assert.IsTrue(mResult.Succeeded);
  Assert.AreEqual(-1, BodyWith(mTransport, 'projectsV2'));
  mPatch := High(mTransport.Calls);
  Assert.AreEqual('PATCH ' + cIssueUrl, mTransport.Calls[mPatch]);
  Assert.AreEqual('["bug","In Progress"]', JsonText(mTransport.Bodies[mPatch], 'labels'));
  Assert.AreEqual('', mResult.Project.Project);
  Clear(mTransport);
end;

procedure TAtlasGitHubProjectsTests.MissingProjectScopeKeepsLabelAndSaysSo;
var
  mTransport: TFakeProjectTransport;
  mKeep: IAtlasCiTransport;
  mWriter: IAtlasTrackerWriter;
  mResult: TAtlasTrackerWriteResult;
begin
  mWriter := TAtlasGitHubTracker.Create;
  mTransport := IssueTransport(cNoScope);
  mKeep := mTransport;
  mResult := mWriter.Apply(GitHubTarget, mKeep, '#7', StartChange('In Progress'), 5000);
  Assert.IsTrue(mResult.Succeeded, 'Label statt Fehler');
  Assert.IsTrue(mResult.Project.Denied);
  Assert.AreEqual('["bug","In Progress"]', JsonText(mTransport.Bodies[High(mTransport.Bodies)], 'labels'));
  Clear(mTransport);
end;

procedure TAtlasGitHubProjectsTests.MissingOptionFailsWithReason;
var
  mTransport: TFakeProjectTransport;
  mKeep: IAtlasCiTransport;
  mWriter: IAtlasTrackerWriter;
  mResult: TAtlasTrackerWriteResult;
begin
  mWriter := TAtlasGitHubTracker.Create;
  mTransport := IssueTransport(cItemsTodo);
  mKeep := mTransport;
  mResult := mWriter.Apply(GitHubTarget, mKeep, '#7', StartChange('In Arbeit'), 5000);
  Assert.IsFalse(mResult.Succeeded);
  Assert.AreEqual(Ord(TAtlasCiFetchError.Invalid), Ord(mResult.Error));
  Assert.AreEqual('In Arbeit', mResult.Project.MissingOption);
  Assert.AreEqual('Atlas 2.1', mResult.Project.Project);
  Assert.AreEqual(-1, BodyWith(mTransport, 'updateProjectV2ItemFieldValue'));
  Assert.AreEqual('POST ' + cGraphQlUrl, mTransport.Calls[High(mTransport.Calls)], 'kein PATCH');
  Clear(mTransport);
end;

procedure TAtlasGitHubProjectsTests.LabelTargetDoesNotAskProjects;
var
  mTransport: TFakeProjectTransport;
  mKeep: IAtlasCiTransport;
  mWriter: IAtlasTrackerWriter;
  mChange: TAtlasTrackerWrite;
begin
  mWriter := TAtlasGitHubTracker.Create;
  mTransport := IssueTransport(cItemsTodo);
  mKeep := mTransport;
  mChange := StartChange('In Progress');
  mChange.GitHub.ToProject := False;
  Assert.IsTrue(mWriter.Apply(GitHubTarget, mKeep, '#7', mChange, 5000).Succeeded);
  Assert.AreEqual('GET ' + cIssueUrl + ' | PATCH ' + cIssueUrl, string.Join(' | ', mTransport.Calls));
  Clear(mTransport);
end;

procedure TAtlasGitHubProjectsTests.EndSetsStatusThenCloses;
var
  mTransport: TFakeProjectTransport;
  mKeep: IAtlasCiTransport;
  mWriter: IAtlasTrackerWriter;
  mResult: TAtlasTrackerWriteResult;
  mPatch, mSet: Integer;
begin
  mWriter := TAtlasGitHubTracker.Create;
  mTransport := IssueTransport(cItemsTodo);
  mKeep := mTransport;
  mResult := mWriter.Apply(GitHubTarget, mKeep, '#7', StartChange('Done'), 5000);
  Assert.IsTrue(mResult.Succeeded, mResult.Message);
  mSet := BodyWith(mTransport, 'updateProjectV2ItemFieldValue');
  mPatch := High(mTransport.Calls);
  Assert.AreEqual('PATCH ' + cIssueUrl, mTransport.Calls[mPatch]);
  Assert.IsTrue(mSet < mPatch, 'Status vor dem Schließen');
  Assert.AreEqual('closed', JsonText(mTransport.Bodies[mPatch], 'state'));
  Assert.AreEqual('completed', JsonText(mTransport.Bodies[mPatch], 'state_reason'));
  Assert.AreEqual('', JsonText(mTransport.Bodies[mPatch], 'labels'), 'kein Label „Done“');
  Assert.AreEqual('Done', mResult.Project.After);
  Clear(mTransport);
end;

procedure TAtlasGitHubProjectsTests.NotPlannedKeepsProjectUntouched;
var
  mTransport: TFakeProjectTransport;
  mKeep: IAtlasCiTransport;
  mWriter: IAtlasTrackerWriter;
  mChange: TAtlasTrackerWrite;
begin
  mWriter := TAtlasGitHubTracker.Create;
  mTransport := IssueTransport(cItemsTodo);
  mKeep := mTransport;
  mChange := StartChange('Done');
  mChange.Close := TAtlasTrackerClose.NotPlanned;
  Assert.IsTrue(mWriter.Apply(GitHubTarget, mKeep, '#7', mChange, 5000).Succeeded);
  Assert.AreEqual(-1, BodyWith(mTransport, 'projectItems'), 'nicht geplant: Projekt bleibt');
  Clear(mTransport);
end;

procedure TAtlasGitHubProjectsTests.ValuesListProjectsAndOptions;
var
  mTransport: TFakeProjectTransport;
  mKeep: IAtlasCiTransport;
  mWriter: IAtlasTrackerWriter;
  mValues: TArray<string>;
begin
  mWriter := TAtlasGitHubTracker.Create;
  mTransport := TFakeProjectTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('POST', cGraphQlUrl, 'projectsV2', 200, cProjects);
  Assert.IsTrue(mWriter.Values(GitHubTarget, mKeep, TAtlasTrackerValueKind.Projects, '', 5000, mValues).Succeeded);
  Assert.AreEqual('beispiel/9, beispiel/4', string.Join(', ', mValues));
  Assert.IsTrue(mWriter.Values(GitHubTarget, mKeep, TAtlasTrackerValueKind.ProjectStates, 'beispiel/4', 5000,
    mValues).Succeeded);
  Assert.AreEqual('Todo, In Progress, Done', string.Join(', ', mValues));
  // Fehlende Rechte: Fehler, die Liste bleibt leer.
  mTransport := TFakeProjectTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('POST', cGraphQlUrl, 'projectsV2', 200, cNoScope);
  Assert.AreEqual(Ord(TAtlasCiFetchError.Unauthorized), Ord(mWriter.Values(GitHubTarget, mKeep,
    TAtlasTrackerValueKind.Projects, '', 5000, mValues).Error));
  Assert.AreEqual(0, Integer(Length(mValues)));
end;

procedure TAtlasGitHubProjectsTests.OptionsFromSettingsAndConnection;
var
  mOptions: TAtlasTrackerSyncOptions;
  mConnection: TAtlasTrackerConnection;
  mStart, mEnd: TAtlasTrackerWrite;
begin
  mOptions := TAtlasTrackerSyncOptions.Create(True, '', '').WithStart('In Progress', False, '').WithGitHub(
    'project', ' beispiel/4 ', True);
  Assert.IsTrue(mOptions.GitHub.ToProject);
  Assert.AreEqual('beispiel/4', mOptions.GitHub.Project);
  Assert.IsFalse(TAtlasTrackerSyncOptions.Create(True, '', '').WithGitHub('Label', '', False).GitHub.ToProject);
  Assert.IsTrue(TAtlasTrackerWorkflow.StateInProject(''), 'Vorgabe: Projektfeld');
  mStart := TAtlasTrackerWorkflow.StartChange(mOptions, TAtlasTrackerPlaceholders.Create('#7', 'b'));
  Assert.IsTrue(mStart.GitHub.ToProject);
  Assert.IsTrue(mStart.GitHub.AddToProject);
  mEnd := TAtlasTrackerWorkflow.EndChange(mOptions, 'Done', '', False, '');
  Assert.AreEqual('beispiel/4', mEnd.GitHub.Project);
  Assert.IsFalse(mEnd.GitHub.AddToProject, 'aufgenommen wird nur beim Beginnen');
  // Die Verbindung überschreibt Ziel und Projekt.
  mConnection := TAtlasTrackerConnection.Create('GH', 'github', 'https://github.com');
  mConnection.GitHubStateTarget := 'label';
  mConnection.GitHubProject := 'beispiel/9';
  mOptions := TAtlasTrackerWorkflow.ForConnection(mOptions, TArray<TAtlasTrackerConnection>.Create(mConnection),
    TAtlasTrackerTarget.Create('github', 'https://github.com', 'beispiel/atlas', ''));
  Assert.IsFalse(mOptions.GitHub.ToProject);
  Assert.AreEqual('beispiel/9', mOptions.GitHub.Project);
end;

procedure TAtlasGitHubProjectsTests.ConnectionKeepsGitHubFields;
var
  mConnection: TAtlasTrackerConnection;
  mRead: TArray<TAtlasTrackerConnection>;
  mJson: string;
begin
  mConnection := TAtlasTrackerConnection.Create('GH', 'github', 'https://github.com');
  Assert.IsFalse(TAtlasTrackerConnections.ToJson(TArray<TAtlasTrackerConnection>.Create(mConnection)).Contains(
    'githubProject'), 'leer: nicht geschrieben');
  mConnection.GitHubStateTarget := 'label';
  mConnection.GitHubProject := 'beispiel/4';
  mJson := TAtlasTrackerConnections.ToJson(TArray<TAtlasTrackerConnection>.Create(mConnection));
  mRead := TAtlasTrackerConnections.Read(mJson);
  Assert.AreEqual(1, Integer(Length(mRead)));
  Assert.AreEqual('label', mRead[0].GitHubStateTarget);
  Assert.AreEqual('beispiel/4', mRead[0].GitHubProject);
  Assert.AreEqual('beispiel/4', mRead[0].WithUrl('https://github.example.com').GitHubProject);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasGitHubProjectsTests);

end.
