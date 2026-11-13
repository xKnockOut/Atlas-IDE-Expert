unit Atlas.Core.Tracker.Internals.GitHubProjects;

// Zustand eines GitHub-Issues im Projektfeld „Status“ (Projects v2, #2134),
// ohne VCL und Open Tools API. Über die GraphQL-Schicht (GitHubGraphQl):
// - Einträge des Issues (projectItems über die node_id des Issues) mit Projekt,
//   Statusfeld, seinen Optionen und dem aktuellen Wert. Statusfeld ist wie
//   beim Board das Auswahlfeld „Status“, sonst das erste außer der Priorität.
// - Ist das Issue in mehreren Projekten, gilt issues.github.project
//   ("<owner>/<nummer>"), sonst das erste (Several meldet das).
// - Ohne Projekt und mit issues.github.addToProject: das eingestellte Projekt
//   unter den Projekten des Repositorys suchen und das Issue aufnehmen
//   (addProjectV2ItemById).
// - Den Zustand ordnet Run einer Option zu (Name ohne Groß-/Kleinschreibung)
//   und setzt sie mit updateProjectV2ItemFieldValue. Fehlt die Option, kommt
//   ein Fehler mit Grund; fehlen die Rechte zum Lesen der Projekte
//   (Berechtigung „project“), bleibt das Label (Denied).

interface

uses
  System.Diagnostics,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract;

type
  TAtlasGitHubProjectOption = record
    Id: string;
    Name: string;
  end;

  /// <summary>Ein Projekt mit Statusfeld und, für ein Issue, dessen Eintrag (ItemId) und aktueller Wert.</summary>
  TAtlasGitHubProjectItem = record
    /// <summary>Eintrag des Issues im Projekt; '' bei einem Projekt ohne das Issue.</summary>
    ItemId: string;
    ProjectId: string;
    Title: string;
    /// <summary>„owner/nummer“ wie in issues.github.project.</summary>
    Ref: string;
    FieldId: string;
    Options: TArray<TAtlasGitHubProjectOption>;
    /// <summary>Aktueller Wert des Statusfeldes; '' ohne.</summary>
    Current: string;
  end;

  /// <summary>Was Run tat: Handled = Zustand im Projekt geführt (dann kein Label).</summary>
  TAtlasGitHubStatusStep = record
    Handled: Boolean;
    Outcome: TAtlasTrackerWriteResult;
    Status: TAtlasTrackerProjectStatus;
  end;

  TAtlasGitHubProjects = class
  public const
    /// <summary>Projekteinträge eines Issues über seine node_id.</summary>
    cItemsQuery = 'query($id:ID!){node(id:$id){... on Issue{projectItems(first:20){nodes{id ' +
      'project{id title number owner{... on User{login} ... on Organization{login}} ' +
      'fields(first:50){nodes{... on ProjectV2SingleSelectField{id name options{id name}}}}} ' +
      'fieldValues(first:20){nodes{... on ProjectV2ItemFieldSingleSelectValue{name ' +
      'field{... on ProjectV2SingleSelectField{id}}}}}}}}}}';
    /// <summary>Projekte des Repositorys mit Statusfeld (für die Aufnahme und die Klapplisten).</summary>
    cProjectsQuery = 'query($owner:String!,$name:String!){repository(owner:$owner,name:$name){projectsV2(first:50)' +
      '{nodes{id title number owner{... on User{login} ... on Organization{login}} ' +
      'fields(first:50){nodes{... on ProjectV2SingleSelectField{id name options{id name}}}}}}}}';
    cAddMutation = 'mutation($project:ID!,$content:ID!){addProjectV2ItemById(input:{projectId:$project,' +
      'contentId:$content}){item{id}}}';
    cSetMutation = 'mutation($project:ID!,$item:ID!,$field:ID!,$option:String!){updateProjectV2ItemFieldValue(' +
      'input:{projectId:$project,itemId:$item,fieldId:$field,value:{singleSelectOptionId:$option}})' +
      '{projectV2Item{id}}}';
  public
    /// <summary>Antwort auf cItemsQuery: Einträge mit Statusfeld; False bei ungültigem JSON.</summary>
    class function ParseItems(const AJson: string; out AItems: TArray<TAtlasGitHubProjectItem>): Boolean; static;
    /// <summary>Antwort auf cProjectsQuery: Projekte (ohne ItemId); False bei ungültigem JSON.</summary>
    class function ParseProjects(const AJson: string; out AProjects: TArray<TAtlasGitHubProjectItem>): Boolean;
      static;
    /// <summary>Eintrag nach AProject („owner/nummer“, ohne Groß-/Kleinschreibung), sonst der erste; -1 ohne.
    /// </summary>
    class function Choose(const AItems: TArray<TAtlasGitHubProjectItem>; const AProject: string): Integer; static;
    /// <summary>Option für AState (Name ohne Groß-/Kleinschreibung); False ohne.</summary>
    class function OptionOf(const AItem: TAtlasGitHubProjectItem; const AState: string;
      out AOption: TAtlasGitHubProjectOption): Boolean; static;
    /// <summary>Namen der Optionen des Statusfeldes (für die Klapplisten).</summary>
    class function OptionNames(const AItem: TAtlasGitHubProjectItem): TArray<string>; static;
    /// <summary>Zustand AChange.State des Issues mit der node_id ANodeId im Projekt setzen (nach
    /// AChange.GitHub); Handled False = kein Projekt, das Label gilt.</summary>
    class function Run(const ACall: TAtlasTrackerCall; const AWatch: TStopwatch; const ASend: IAtlasCiSend;
      const ANodeId: string; const AChange: TAtlasTrackerWrite): TAtlasGitHubStatusStep; static;
    /// <summary>Projekte des Repositorys von ACall.Target („owner/nummer“) bzw. mit AProject die Optionen des
    /// Statusfeldes dieses Projekts ('' = erstes).</summary>
    class function Values(const ACall: TAtlasTrackerCall; const AProject: string; AOptions: Boolean;
      out AValues: TArray<string>): TAtlasTrackerWriteResult; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  Atlas.Core.Tracker.Internals.GitHubApi,
  Atlas.Core.Tracker.Internals.GitHubGraphQl,
  Atlas.Text.Json;

const
  /// <summary>Prioritätsfeld, wie beim Board: nie das Statusfeld.</summary>
  cPriorityNames: array[0..1] of string = ('Priority', 'Priorität'); // german-ok: Feldname im GitHub-Projekt

/// <summary>Statusfeld: „Status“ geht vor, sonst das erste Auswahlfeld außer der Priorität; nil ohne.</summary>
function StatusFieldOf(AProject: TJSONObject): TJSONObject;
var
  mNodes: TJSONArray;
  mItem: TJSONValue;
  mName: string;
begin
  Result := nil;
  mNodes := TAtlasGitHubGraphQl.NodesOf(AProject, 'fields');
  if mNodes = nil then
  begin
    Exit;
  end;
  for mItem in mNodes do
  begin
    if not (mItem is TJSONObject) or not (TJSONObject(mItem).Values['options'] is TJSONArray) then
    begin
      Continue;
    end;
    mName := TJsonRead.Text(TJSONObject(mItem), 'name');
    if SameText(mName, 'Status') then
    begin
      Exit(TJSONObject(mItem));
    end;
    if (Result = nil) and not MatchText(mName, cPriorityNames) then
    begin
      Result := TJSONObject(mItem);
    end;
  end;
end;

/// <summary>Projekt mit Statusfeld; False ohne Statusfeld.</summary>
function ReadProject(AProject: TJSONObject; out AItem: TAtlasGitHubProjectItem): Boolean;
var
  mField, mOwner: TJSONObject;
  mOption: TJSONValue;
  mEntry: TAtlasGitHubProjectOption;
begin
  AItem := Default(TAtlasGitHubProjectItem);
  mField := StatusFieldOf(AProject);
  Result := mField <> nil;
  if not Result then
  begin
    Exit;
  end;
  AItem.ProjectId := TJsonRead.Text(AProject, 'id');
  AItem.Title := TJsonRead.Text(AProject, 'title');
  mOwner := TAtlasGitHubGraphQl.ObjectAt(AProject, ['owner']);
  if mOwner <> nil then
  begin
    AItem.Ref := TJsonRead.Text(mOwner, 'login') + '/' + IntToStr(TJsonRead.Int(AProject, 'number'));
  end;
  AItem.FieldId := TJsonRead.Text(mField, 'id');
  for mOption in TJSONArray(mField.Values['options']) do
  begin
    if mOption is TJSONObject then
    begin
      mEntry.Id := TJsonRead.Text(TJSONObject(mOption), 'id');
      mEntry.Name := TJsonRead.Text(TJSONObject(mOption), 'name');
      AItem.Options := AItem.Options + [mEntry];
    end;
  end;
end;

/// <summary>Aktueller Wert des Feldes AFieldId unter fieldValues; '' ohne.</summary>
function CurrentOf(AEntry: TJSONObject; const AFieldId: string): string;
var
  mNodes: TJSONArray;
  mItem: TJSONValue;
  mField: TJSONObject;
begin
  Result := '';
  mNodes := TAtlasGitHubGraphQl.NodesOf(AEntry, 'fieldValues');
  if mNodes = nil then
  begin
    Exit;
  end;
  for mItem in mNodes do
  begin
    if not (mItem is TJSONObject) then
    begin
      Continue;
    end;
    mField := TAtlasGitHubGraphQl.ObjectAt(mItem, ['field']);
    if (mField <> nil) and (TJsonRead.Text(mField, 'id') = AFieldId) then
    begin
      Exit(TJsonRead.Text(TJSONObject(mItem), 'name'));
    end;
  end;
end;

/// <summary>Liste "nodes" unter APath + ANodes als Projekte; mit AEntries sind es Einträge (Projekt unter
/// "project").</summary>
function ParseList(const AJson: string; const APath: array of string; const ANodes: string; AEntries: Boolean;
  out AItems: TArray<TAtlasGitHubProjectItem>): Boolean;
var
  mValue, mNode: TJSONValue;
  mNodes: TJSONArray;
  mProject: TJSONObject;
  mItem: TAtlasGitHubProjectItem;
begin
  AItems := nil;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := mValue is TJSONObject;
    if not Result then
    begin
      Exit;
    end;
    mNodes := TAtlasGitHubGraphQl.NodesOf(TAtlasGitHubGraphQl.ObjectAt(mValue, APath), ANodes);
    if mNodes = nil then
    begin
      Exit;
    end;
    for mNode in mNodes do
    begin
      mProject := TAtlasGitHubGraphQl.ObjectAt(mNode, []);
      if AEntries then
      begin
        mProject := TAtlasGitHubGraphQl.ObjectAt(mNode, ['project']);
      end;
      if (mProject <> nil) and ReadProject(mProject, mItem) then
      begin
        if AEntries then
        begin
          mItem.ItemId := TJsonRead.Text(TJSONObject(mNode), 'id');
          mItem.Current := CurrentOf(TJSONObject(mNode), mItem.FieldId);
        end;
        AItems := AItems + [mItem];
      end;
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasGitHubProjects.ParseItems(const AJson: string;
  out AItems: TArray<TAtlasGitHubProjectItem>): Boolean;
begin
  Result := ParseList(AJson, ['data', 'node'], 'projectItems', True, AItems);
end;

class function TAtlasGitHubProjects.ParseProjects(const AJson: string;
  out AProjects: TArray<TAtlasGitHubProjectItem>): Boolean;
begin
  Result := ParseList(AJson, ['data', 'repository'], 'projectsV2', False, AProjects);
end;

class function TAtlasGitHubProjects.Choose(const AItems: TArray<TAtlasGitHubProjectItem>;
  const AProject: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  if Length(AItems) = 0 then
  begin
    Exit;
  end;
  Result := 0;
  for mIndex := 0 to High(AItems) do
  begin
    if (Trim(AProject) <> '') and SameText(AItems[mIndex].Ref, Trim(AProject)) then
    begin
      Exit(mIndex);
    end;
  end;
end;

class function TAtlasGitHubProjects.OptionOf(const AItem: TAtlasGitHubProjectItem; const AState: string;
  out AOption: TAtlasGitHubProjectOption): Boolean;
var
  mOption: TAtlasGitHubProjectOption;
begin
  AOption := Default(TAtlasGitHubProjectOption);
  for mOption in AItem.Options do
  begin
    if SameText(mOption.Name, Trim(AState)) then
    begin
      AOption := mOption;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasGitHubProjects.OptionNames(const AItem: TAtlasGitHubProjectItem): TArray<string>;
var
  mOption: TAtlasGitHubProjectOption;
begin
  Result := nil;
  for mOption in AItem.Options do
  begin
    Result := Result + [mOption.Name];
  end;
end;

type
  /// <summary>Was jede Anfrage braucht: Ziel und Zeitgrenze, Uhr, Schreibweg und die node_id des Issues.</summary>
  TProjectCall = record
    Call: TAtlasTrackerCall;
    Watch: TStopwatch;
    Send: IAtlasCiSend;
    NodeId: string;
  end;

function ProjectCall(const ACall: TAtlasTrackerCall; const AWatch: TStopwatch; const ASend: IAtlasCiSend;
  const ANodeId: string): TProjectCall;
begin
  Result.Call := ACall;
  Result.Watch := AWatch;
  Result.Send := ASend;
  Result.NodeId := ANodeId;
end;

/// <summary>GraphQL-Anfrage als Schreibergebnis; AText: Antwort.</summary>
function Ask(const ACall: TProjectCall; const ABody: string; out AText: string): TAtlasTrackerWriteResult;
var
  mReply: TAtlasGitHubGraphQlReply;
begin
  Result := TAtlasTrackerWriteResult.Ok;
  if not TAtlasGitHubGraphQl.Query(ACall.Send, TAtlasGitHubGraphQl.Url(ACall.Call.Target), ABody,
    TAtlasGitHubApi.Remaining(ACall.Watch, ACall.Call.TimeoutMs), mReply) then
  begin
    Result := TAtlasTrackerWriteResult.Failed(mReply.Error, 0, mReply.Message);
  end;
  AText := mReply.Text;
end;

/// <summary>Projekte des Repositorys mit Statusfeld.</summary>
function RepositoryProjects(const ACall: TProjectCall;
  out AProjects: TArray<TAtlasGitHubProjectItem>): TAtlasTrackerWriteResult;
var
  mText, mOwner, mName: string;
  mAt: Integer;
begin
  AProjects := nil;
  mAt := Pos('/', ACall.Call.Target.Project);
  mOwner := Copy(ACall.Call.Target.Project, 1, mAt - 1);
  mName := Copy(ACall.Call.Target.Project, mAt + 1, MaxInt);
  Result := Ask(ACall, TAtlasGitHubGraphQl.Body(TAtlasGitHubProjects.cProjectsQuery, ['owner', mOwner, 'name',
    mName]), mText);
  if Result.Succeeded and not TAtlasGitHubProjects.ParseProjects(mText, AProjects) then
  begin
    Result := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 0, '');
  end;
end;

/// <summary>Eintrag aus der Antwort auf cAddMutation; '' ohne.</summary>
function AddedItemId(const AText: string): string;
var
  mValue: TJSONValue;
  mAdded: TJSONObject;
begin
  Result := '';
  mValue := TJSONObject.ParseJSONValue(AText);
  try
    mAdded := TAtlasGitHubGraphQl.ObjectAt(mValue, ['data', 'addProjectV2ItemById', 'item']);
    if mAdded <> nil then
    begin
      Result := TJsonRead.Text(mAdded, 'id');
    end;
  finally
    mValue.Free;
  end;
end;

/// <summary>Issue in das Projekt AProject („owner/nummer“) aufnehmen; AItem: das Projekt mit dem
/// neuen Eintrag. False ohne passendes Projekt (dann gilt das Label) oder bei einem Fehler in AResult.</summary>
function AddToProject(const ACall: TProjectCall; const AProject: string; out AItem: TAtlasGitHubProjectItem;
  out AResult: TAtlasTrackerWriteResult): Boolean;
var
  mProjects: TArray<TAtlasGitHubProjectItem>;
  mIndex: Integer;
  mText: string;
begin
  Result := False;
  AItem := Default(TAtlasGitHubProjectItem);
  AResult := RepositoryProjects(ACall, mProjects);
  mIndex := -1;
  if AResult.Succeeded then
  begin
    mIndex := TAtlasGitHubProjects.Choose(mProjects, AProject);
  end;
  // Choose fällt auf das erste zurück; aufgenommen wird nur in das eingestellte Projekt.
  if (mIndex < 0) or not SameText(mProjects[mIndex].Ref, Trim(AProject)) then
  begin
    Exit;
  end;
  AItem := mProjects[mIndex];
  AResult := Ask(ACall, TAtlasGitHubGraphQl.Body(TAtlasGitHubProjects.cAddMutation, ['project', AItem.ProjectId,
    'content', ACall.NodeId]), mText);
  if AResult.Succeeded then
  begin
    AItem.ItemId := AddedItemId(mText);
    if AItem.ItemId = '' then
    begin
      AResult := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 0, '');
    end;
  end;
  Result := AResult.Succeeded;
end;

/// <summary>Einträge des Issues lesen. Ohne Berechtigung „project“ (Unauthorized) gilt das Label: Ok mit
/// AStep.Status.Denied.</summary>
function ReadItems(const ACall: TProjectCall; var AStep: TAtlasGitHubStatusStep;
  out AItems: TArray<TAtlasGitHubProjectItem>): Boolean;
var
  mText: string;
begin
  AItems := nil;
  AStep.Outcome := Ask(ACall, TAtlasGitHubGraphQl.Body(TAtlasGitHubProjects.cItemsQuery, ['id', ACall.NodeId]),
    mText);
  if AStep.Outcome.Error = TAtlasCiFetchError.Unauthorized then
  begin
    AStep.Status.Denied := True;
    AStep.Outcome := TAtlasTrackerWriteResult.Ok;
    Exit(False);
  end;
  if AStep.Outcome.Succeeded and not TAtlasGitHubProjects.ParseItems(mText, AItems) then
  begin
    AStep.Outcome := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 0, '');
  end;
  Result := AStep.Outcome.Succeeded;
end;

/// <summary>Eintrag des Issues: vorhanden (nach issues.github.project) oder mit addToProject neu aufgenommen.
/// False ohne Eintrag; AStep.Outcome trägt einen Fehler, AStep.Status.Denied fehlende Leserechte.</summary>
function FindItem(const ACall: TProjectCall; const AState: TAtlasTrackerGitHubState;
  var AStep: TAtlasGitHubStatusStep; out AItem: TAtlasGitHubProjectItem): Boolean;
var
  mItems: TArray<TAtlasGitHubProjectItem>;
  mIndex: Integer;
begin
  Result := False;
  AItem := Default(TAtlasGitHubProjectItem);
  if not ReadItems(ACall, AStep, mItems) then
  begin
    Exit;
  end;
  mIndex := TAtlasGitHubProjects.Choose(mItems, AState.Project);
  if mIndex >= 0 then
  begin
    AItem := mItems[mIndex];
    AStep.Status.Several := Length(mItems) > 1;
    Result := True;
  end
  else if AState.AddToProject and (Trim(AState.Project) <> '') then
  begin
    Result := AddToProject(ACall, AState.Project, AItem, AStep.Outcome);
    AStep.Status.Added := Result;
  end;
end;

class function TAtlasGitHubProjects.Run(const ACall: TAtlasTrackerCall; const AWatch: TStopwatch;
  const ASend: IAtlasCiSend; const ANodeId: string; const AChange: TAtlasTrackerWrite): TAtlasGitHubStatusStep;
var
  mCall: TProjectCall;
  mItem: TAtlasGitHubProjectItem;
  mOption: TAtlasGitHubProjectOption;
  mText: string;
begin
  Result := Default(TAtlasGitHubStatusStep);
  Result.Outcome := TAtlasTrackerWriteResult.Ok;
  mCall := ProjectCall(ACall, AWatch, ASend, ANodeId);
  if not FindItem(mCall, AChange.GitHub, Result, mItem) then
  begin
    // Fehler beim Lesen oder Aufnehmen: nichts weiter schreiben (Handled, damit kein Label entsteht).
    Result.Handled := not Result.Outcome.Succeeded;
    Exit;
  end;
  Result.Handled := True;
  Result.Status.Project := mItem.Title;
  Result.Status.Before := mItem.Current;
  if not OptionOf(mItem, AChange.State, mOption) then
  begin
    Result.Outcome := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 0, '');
    Result.Status.MissingOption := Trim(AChange.State);
    Exit;
  end;
  Result.Status.After := mOption.Name;
  if SameText(mItem.Current, mOption.Name) then
  begin
    Exit;
  end;
  Result.Outcome := Ask(mCall, TAtlasGitHubGraphQl.Body(cSetMutation, ['project', mItem.ProjectId, 'item',
    mItem.ItemId, 'field', mItem.FieldId, 'option', mOption.Id]), mText);
end;

class function TAtlasGitHubProjects.Values(const ACall: TAtlasTrackerCall; const AProject: string;
  AOptions: Boolean; out AValues: TArray<string>): TAtlasTrackerWriteResult;
var
  mSend: IAtlasCiSend;
  mProjects: TArray<TAtlasGitHubProjectItem>;
  mProject: TAtlasGitHubProjectItem;
  mIndex: Integer;
begin
  AValues := nil;
  if (TAtlasGitHubGraphQl.Url(ACall.Target) = '') or (Pos('/', ACall.Target.Project) <= 1) or
    not Supports(ACall.Transport, IAtlasCiSend, mSend) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, ''));
  end;
  Result := RepositoryProjects(ProjectCall(ACall, TStopwatch.StartNew, mSend, ''), mProjects);
  mIndex := Choose(mProjects, AProject);
  if not Result.Succeeded or (AOptions and (mIndex < 0)) then
  begin
    Exit;
  end;
  if AOptions then
  begin
    AValues := OptionNames(mProjects[mIndex]);
    Exit;
  end;
  for mProject in mProjects do
  begin
    AValues := AValues + [mProject.Ref];
  end;
end;

end.
