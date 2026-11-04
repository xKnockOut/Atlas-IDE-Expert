unit Atlas.Core.Tracker.GitHubBoards;

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Board;

type
  // Board für GitHub (#1272), ohne VCL und Open Tools API.
  // - Projekte (v2) über GraphQL (POST <api>/graphql; github.com:
  //   api.github.com/graphql, Enterprise: <server>/api/graphql): erst die
  //   Projekte des Repositorys und der Anmeldename (viewer), dann das gewählte
  //   Projekt mit Feldern und Einträgen. Spalten sind die Optionen des Feldes
  //   „Status“ (sonst des ersten Auswahlfeldes), Sprints die Iterationen des
  //   ersten Iterationsfeldes (aktuelle = enthält heute). Karten nur für
  //   Issues (keine Pull Requests und Entwürfe), höchstens 100 Einträge.
  // - Ohne Projekt: Spalten Offen und Geschlossen aus der REST-Liste der Issues
  //   (offene, dazu die zuletzt geänderten geschlossenen).
  // - Verschieben: erst der Kommentar (fehlen die Rechte, ändert sich nichts),
  //   dann updateProjectV2ItemFieldValue bzw. PATCH state des Issues.
  // GraphQL meldet Fehler mit Status 200 in "errors": fehlende Rechte
  // (INSUFFICIENT_SCOPES, FORBIDDEN) als Unauthorized, sonst Invalid. Dürfen
  // die Projekte nicht gelesen werden, zeigt das Board Offen/Geschlossen mit
  // ProjectsDenied (Hinweis auf die Berechtigung „project“).
  TAtlasGitHubBoards = class(TInterfacedObject, IAtlasTrackerBoards)
  public const
    /// <summary>Projekte des Repositorys und eigener Anmeldename.</summary>
    ProjectsQuery = 'query($owner:String!,$name:String!){viewer{login}repository(owner:$owner,name:$name)' +
      '{projectsV2(first:50){nodes{id title closed}}}}';
    /// <summary>Ein Projekt mit Feldern und Einträgen.</summary>
    ProjectQuery = 'query($id:ID!){node(id:$id){... on ProjectV2{id title url ' +
      'fields(first:50){nodes{... on ProjectV2SingleSelectField{id name options{id name}} ' +
      '... on ProjectV2Field{id name dataType} ' +
      '... on ProjectV2IterationField{id name configuration{iterations{id title startDate duration} ' +
      'completedIterations{id title startDate duration}}}}} ' +
      'items(first:100){nodes{id fieldValues(first:20){nodes{' +
      '... on ProjectV2ItemFieldSingleSelectValue{name optionId field{... on ProjectV2SingleSelectField{name}}} ' +
      '... on ProjectV2ItemFieldIterationValue{iterationId field{... on ProjectV2IterationField{name}}} ' +
      '... on ProjectV2ItemFieldNumberValue{number field{... on ProjectV2Field{name}}}}} ' +
      'content{... on Issue{number title url state closedAt body repository{nameWithOwner} ' +
      'assignees(first:5){nodes{login name}}}}}}}}}';
    MoveMutation = 'mutation($project:ID!,$item:ID!,$field:ID!,$option:String!){updateProjectV2ItemFieldValue(' +
      'input:{projectId:$project,itemId:$item,fieldId:$field,value:{singleSelectOptionId:$option}})' +
      '{projectV2Item{id}}}';
    /// <summary>Höchstens so viele geschlossene Issues ohne Projekt.</summary>
    MaxClosed = 30;
  public
    /// <summary>Adresse der GraphQL-Schnittstelle; '' ohne Server.</summary>
    class function GraphQlUrl(const ATarget: TAtlasTrackerTarget): string; static;
    /// <summary>Inhalt eines POST: {"query": AQuery, "variables": {Name: Wert, …}} aus Paaren in AVariables.
    /// </summary>
    class function GraphQlBody(const AQuery: string; const AVariables: array of string): string; static;
    /// <summary>Fehler einer GraphQL-Antwort mit Status 200 ("errors"); None ohne. AMessage: erster Text.</summary>
    class function GraphQlError(const AJson: string; out AMessage: string): TAtlasCiFetchError; static;
    /// <summary>Antwort auf ProjectsQuery: Projekte (offene zuerst) in ASnapshot.Boards, Anmeldename in
    /// ASnapshot.Me. False bei ungültigem JSON.</summary>
    class function ParseProjects(const AJson: string; var ASnapshot: TAtlasBoardSnapshot): Boolean; static;
    /// <summary>Antwort auf ProjectQuery: Spalten, Sprints, Sprint ASprintId ('' = aktueller nach ANow, UTC) und
    /// dessen Karten. False bei ungültigem JSON oder ohne Projekt.</summary>
    class function ParseProject(const AJson: string; const ATarget: TAtlasTrackerTarget; const ASprintId: string;
      ANow: TDateTime; var ASnapshot: TAtlasBoardSnapshot): Boolean; static;
    /// <summary>REST-Liste /issues (ohne Pull Requests) als Karten an ASnapshot.Cards anhängen; False bei
    /// ungültigem JSON.</summary>
    class function ParseIssues(const AJson: string; const ATarget: TAtlasTrackerTarget;
      var ASnapshot: TAtlasBoardSnapshot): Boolean; static;
    { IAtlasTrackerBoards }
    function LoadBoard(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const ABoardId, ASprintId: string; ATimeoutMs: Integer; out ASnapshot: TAtlasBoardSnapshot;
      out AError: TAtlasCiFetchError): Boolean;
    function MoveCard(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const ASnapshot: TAtlasBoardSnapshot; const ACard: TAtlasBoardCard; AColumn: Integer; const AComment: string;
      ATimeoutMs: Integer): TAtlasTrackerWriteResult;
  end;

implementation

uses
  System.Classes,
  System.Diagnostics,
  System.DateUtils,
  System.Generics.Collections,
  System.JSON,
  System.StrUtils,
  Atlas.Core.Tracker.Links,
  Atlas.Core.Tracker.Markdown,
  Atlas.Core.Tracker.Checklist,
  Atlas.Core.Tracker.Internals.GitHubApi,
  Atlas.Core.Tracker.Internals.GitHubJson;

/// <summary>ISO 8601 ("2026-10-28T09:12:00Z") als UTC; 0 ohne.</summary>
function TimeOfText(const AText: string): TDateTime;
begin
  Result := 0;
  if (AText = '') or not TryISO8601ToDate(AText, Result, True) then
  begin
    Result := 0;
  end;
end;

/// <summary>Objekt unter einem Pfad aus Namen ("data", "node"); nil, wenn ein Teil fehlt.</summary>
function ObjectAt(AValue: TJSONValue; const APath: array of string): TJSONObject;
var
  mName: string;
  mValue: TJSONValue;
begin
  Result := nil;
  mValue := AValue;
  for mName in APath do
  begin
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mValue := TJSONObject(mValue).Values[mName];
  end;
  if mValue is TJSONObject then
  begin
    Result := TJSONObject(mValue);
  end;
end;

/// <summary>Liste "nodes" eines Objekts; nil ohne.</summary>
function NodesOf(AObject: TJSONObject; const AName: string): TJSONArray;
var
  mValue: TJSONValue;
begin
  Result := nil;
  if AObject = nil then
  begin
    Exit;
  end;
  mValue := AObject.Values[AName];
  if mValue is TJSONObject then
  begin
    mValue := TJSONObject(mValue).Values['nodes'];
  end;
  if mValue is TJSONArray then
  begin
    Result := TJSONArray(mValue);
  end;
end;


class function TAtlasGitHubBoards.GraphQlUrl(const ATarget: TAtlasTrackerTarget): string;
var
  mBase: string;
begin
  Result := '';
  mBase := TAtlasGitHubApi.Base(ATarget);
  if mBase = '' then
  begin
    Exit;
  end;
  if mBase = TAtlasGitHubApi.ApiHost then
  begin
    Result := mBase + '/graphql';
  end
  else
  begin
    Result := ATarget.Server + '/api/graphql';
  end;
end;

class function TAtlasGitHubBoards.GraphQlBody(const AQuery: string; const AVariables: array of string): string;
var
  mRoot, mVariables: TJSONObject;
  mIndex: Integer;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('query', AQuery);
    mVariables := TJSONObject.Create;
    mIndex := 0;
    while mIndex + 1 <= High(AVariables) do
    begin
      mVariables.AddPair(AVariables[mIndex], AVariables[mIndex + 1]);
      Inc(mIndex, 2);
    end;
    mRoot.AddPair('variables', mVariables);
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasGitHubBoards.GraphQlError(const AJson: string; out AMessage: string): TAtlasCiFetchError;
var
  mValue, mItem: TJSONValue;
  mType: string;
begin
  AMessage := '';
  Result := TAtlasCiFetchError.None;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) then
    begin
      Exit(TAtlasCiFetchError.Invalid);
    end;
    if not (TJSONObject(mValue).Values['errors'] is TJSONArray) then
    begin
      Exit;
    end;
    for mItem in TJSONArray(TJSONObject(mValue).Values['errors']) do
    begin
      if not (mItem is TJSONObject) then
      begin
        Continue;
      end;
      if AMessage = '' then
      begin
        AMessage := Copy(TAtlasGitHubJson.TextOf(TJSONObject(mItem), 'message'), 1, 300);
      end;
      mType := UpperCase(TAtlasGitHubJson.TextOf(TJSONObject(mItem), 'type'));
      if (mType = 'INSUFFICIENT_SCOPES') or (mType = 'FORBIDDEN') then
      begin
        Exit(TAtlasCiFetchError.Unauthorized);
      end;
      if mType = 'NOT_FOUND' then
      begin
        Result := TAtlasCiFetchError.NotFound;
      end;
    end;
    if Result = TAtlasCiFetchError.None then
    begin
      Result := TAtlasCiFetchError.Invalid;
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasGitHubBoards.ParseProjects(const AJson: string; var ASnapshot: TAtlasBoardSnapshot): Boolean;
var
  mValue, mItem: TJSONValue;
  mViewer, mProject: TJSONObject;
  mNodes: TJSONArray;
  mOpen, mClosed: TArray<TAtlasBoardRef>;
  mRef: TAtlasBoardRef;
begin
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mViewer := ObjectAt(mValue, ['data', 'viewer']);
    if mViewer <> nil then
    begin
      ASnapshot.Me := TAtlasGitHubJson.TextOf(mViewer, 'login');
    end;
    mOpen := nil;
    mClosed := nil;
    mNodes := NodesOf(ObjectAt(mValue, ['data', 'repository']), 'projectsV2');
    if mNodes <> nil then
    begin
      for mItem in mNodes do
      begin
        if not (mItem is TJSONObject) then
        begin
          Continue;
        end;
        mProject := TJSONObject(mItem);
        mRef := TAtlasBoardRef.Create(TAtlasGitHubJson.TextOf(mProject, 'id'), TAtlasGitHubJson.TextOf(mProject,
          'title'));
        if mRef.Id = '' then
        begin
          Continue;
        end;
        if TAtlasGitHubJson.FlagOf(mProject, 'closed') then
        begin
          mClosed := mClosed + [mRef];
        end
        else
        begin
          mOpen := mOpen + [mRef];
        end;
      end;
    end;
    ASnapshot.Boards := Copy(mOpen + mClosed, 0, TAtlasBoardSnapshot.MaxBoards);
    Result := True;
  finally
    mValue.Free;
  end;
end;

function IterationOf(AObject: TJSONObject): TAtlasBoardSprint;
var
  mStart: TDateTime;
begin
  Result := Default(TAtlasBoardSprint);
  Result.Id := TAtlasGitHubJson.TextOf(AObject, 'id');
  Result.Name := TAtlasGitHubJson.TextOf(AObject, 'title');
  // startDate "2026-10-27" (Tag, UTC), duration in Tagen.
  if TryISO8601ToDate(TAtlasGitHubJson.TextOf(AObject, 'startDate'), mStart, True) then
  begin
    Result.Start := mStart;
    if TAtlasGitHubJson.IntOf(AObject, 'duration') > 0 then
    begin
      Result.Finish := mStart + TAtlasGitHubJson.IntOf(AObject, 'duration');
    end;
  end;
end;

/// <summary>Zahlenfeld als Schätzung (#1277): "Estimate", "Story Points", "Points", "Size", deutsch ebenso.
/// </summary>
function IsPointsName(const AName: string): Boolean;
const
  Names: array[0..7] of string = ('Estimate', 'Estimation', 'Story Points', 'Points', 'Size', 'Schätzung',
    'Punkte', 'Aufwand');
var
  mName: string;
begin
  Result := False;
  for mName in Names do
  begin
    if SameText(Trim(AName), mName) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Spalten, Feld, Schätzfeld und Sprints aus fields.</summary>
procedure ReadFields(AProject: TJSONObject; var ASnapshot: TAtlasBoardSnapshot; out AIteration, APriority: string);
var
  mNodes, mOptions: TJSONArray;
  mItem, mOption: TJSONValue;
  mField, mChosen, mFirst, mConfig: TJSONObject;
  mSprint: TAtlasBoardSprint;
  mName: string;
begin
  AIteration := '';
  APriority := '';
  mChosen := nil;
  mFirst := nil;
  ASnapshot.Columns := nil;
  ASnapshot.Sprints := nil;
  ASnapshot.PointsField := '';
  mNodes := NodesOf(AProject, 'fields');
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
    mField := TJSONObject(mItem);
    mName := TAtlasGitHubJson.TextOf(mField, 'name');
    if mField.Values['options'] is TJSONArray then
    begin
      // Auswahlfeld: „Status“ geht vor, sonst das erste außer der Priorität; diese gibt den Farbbalken.
      if SameText(mName, 'Priority') or SameText(mName, 'Priorität') then
      begin
        APriority := mName;
      end
      else if SameText(mName, 'Status') then
      begin
        mChosen := mField;
      end
      else if (mChosen = nil) and (mFirst = nil) then
      begin
        mFirst := mField;
      end;
    end
    else if (ASnapshot.PointsField = '') and SameText(TAtlasGitHubJson.TextOf(mField, 'dataType'), 'NUMBER') and
      IsPointsName(mName) then
    begin
      ASnapshot.PointsField := mName;
    end
    else if (AIteration = '') and (mField.Values['configuration'] is TJSONObject) then
    begin
      AIteration := mName;
      mConfig := TJSONObject(mField.Values['configuration']);
      // Laufende und künftige, dann abgeschlossene.
      if mConfig.Values['iterations'] is TJSONArray then
      begin
        for mOption in TJSONArray(mConfig.Values['iterations']) do
        begin
          if mOption is TJSONObject then
          begin
            ASnapshot.Sprints := ASnapshot.Sprints + [IterationOf(TJSONObject(mOption))];
          end;
        end;
      end;
      if mConfig.Values['completedIterations'] is TJSONArray then
      begin
        for mOption in TJSONArray(mConfig.Values['completedIterations']) do
        begin
          if mOption is TJSONObject then
          begin
            mSprint := IterationOf(TJSONObject(mOption));
            mSprint.Archived := True;
            ASnapshot.Sprints := ASnapshot.Sprints + [mSprint];
          end;
        end;
      end;
      ASnapshot.Sprints := Copy(ASnapshot.Sprints, 0, TAtlasBoardSnapshot.MaxSprints);
    end;
  end;
  if mChosen = nil then
  begin
    mChosen := mFirst;
  end;
  if mChosen = nil then
  begin
    Exit;
  end;
  ASnapshot.Field := TAtlasGitHubJson.TextOf(mChosen, 'name');
  ASnapshot.FieldId := TAtlasGitHubJson.TextOf(mChosen, 'id');
  mOptions := TJSONArray(mChosen.Values['options']);
  for mOption in mOptions do
  begin
    if (mOption is TJSONObject) and (TAtlasGitHubJson.TextOf(TJSONObject(mOption), 'name') <> '') then
    begin
      ASnapshot.Columns := ASnapshot.Columns + [TAtlasBoardColumn.Create(TAtlasGitHubJson.TextOf(TJSONObject(mOption),
        'name'),
        TArray<string>.Create(TAtlasGitHubJson.TextOf(TJSONObject(mOption), 'name')),
          TAtlasGitHubJson.TextOf(TJSONObject(mOption), 'id'),
        TAtlasGitHubApi.ClosesIssue(TAtlasGitHubJson.TextOf(TJSONObject(mOption), 'name')))];
    end;
  end;
end;

/// <summary>Kennung eines Issues: "#12" im Repository des Ziels, sonst "owner/repo#12".</summary>
function KeyOf(AIssue: TJSONObject; const AProject: string): string;
var
  mRepository: string;
begin
  Result := '#' + IntToStr(TAtlasGitHubJson.IntOf(AIssue, 'number'));
  mRepository := '';
  if AIssue.Values['repository'] is TJSONObject then
  begin
    mRepository := TAtlasGitHubJson.TextOf(TJSONObject(AIssue.Values['repository']), 'nameWithOwner');
  end;
  if (mRepository <> '') and not SameText(mRepository, AProject) then
  begin
    Result := mRepository + Result;
  end;
end;

/// <summary>Zuständige aus assignees (GraphQL: nodes, REST: Liste).</summary>
procedure ReadAssignees(AValue: TJSONValue; var ACard: TAtlasBoardCard);
var
  mItem: TJSONValue;
  mName: string;
begin
  if AValue is TJSONObject then
  begin
    AValue := TJSONObject(AValue).Values['nodes'];
  end;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AValue) do
  begin
    if not (mItem is TJSONObject) or (TAtlasGitHubJson.TextOf(TJSONObject(mItem), 'login') = '') then
    begin
      Continue;
    end;
    ACard.Logins := ACard.Logins + [TAtlasGitHubJson.TextOf(TJSONObject(mItem), 'login')];
    if ACard.Assignee = '' then
    begin
      mName := TAtlasGitHubJson.TextOf(TJSONObject(mItem), 'name');
      if mName = '' then
      begin
        mName := TAtlasGitHubJson.TextOf(TJSONObject(mItem), 'login');
      end;
      ACard.Assignee := mName;
    end;
  end;
end;

class function TAtlasGitHubBoards.ParseProject(const AJson: string; const ATarget: TAtlasTrackerTarget;
  const ASprintId: string; ANow: TDateTime; var ASnapshot: TAtlasBoardSnapshot): Boolean;
var
  mValue, mItem, mField: TJSONValue;
  mProject, mEntry, mIssue, mFieldName: TJSONObject;
  mNodes, mValues: TJSONArray;
  mIteration, mPriority, mItemIteration, mName: string;
  mSprint, mIndex: Integer;
  mCard: TAtlasBoardCard;
begin
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    mProject := ObjectAt(mValue, ['data', 'node']);
    if (mProject = nil) or (TAtlasGitHubJson.TextOf(mProject, 'id') = '') then
    begin
      Exit;
    end;
    ASnapshot.Kind := TAtlasBoardKind.Project;
    ASnapshot.ProjectId := TAtlasGitHubJson.TextOf(mProject, 'id');
    ASnapshot.Board := TAtlasBoardRef.Create(ASnapshot.ProjectId, TAtlasGitHubJson.TextOf(mProject, 'title'));
    ASnapshot.Page := TAtlasGitHubJson.TextOf(mProject, 'url');
    ReadFields(mProject, ASnapshot, mIteration, mPriority);
    // Sprint: gewählt, sonst der aktuelle.
    ASnapshot.Sprint := Default(TAtlasBoardSprint);
    mSprint := -1;
    for mIndex := 0 to High(ASnapshot.Sprints) do
    begin
      if (ASprintId <> '') and SameText(ASnapshot.Sprints[mIndex].Id, ASprintId) then
      begin
        mSprint := mIndex;
      end;
    end;
    if mSprint < 0 then
    begin
      mSprint := TAtlasTrackerBoard.CurrentSprint(ASnapshot.Sprints, ANow);
    end;
    if mSprint >= 0 then
    begin
      ASnapshot.Sprint := ASnapshot.Sprints[mSprint];
    end;
    ASnapshot.Cards := nil;
    mNodes := NodesOf(mProject, 'items');
    if mNodes <> nil then
    begin
      for mItem in mNodes do
      begin
        if not (mItem is TJSONObject) or (Length(ASnapshot.Cards) >= TAtlasBoardSnapshot.MaxCards) then
        begin
          Continue;
        end;
        mEntry := TJSONObject(mItem);
        mIssue := ObjectAt(mEntry, ['content']);
        // Nur Issues; Pull Requests und Entwürfe haben hier keinen Inhalt.
        if (mIssue = nil) or (TAtlasGitHubJson.IntOf(mIssue, 'number') <= 0) then
        begin
          Continue;
        end;
        mCard := Default(TAtlasBoardCard);
        mCard.ItemId := TAtlasGitHubJson.TextOf(mEntry, 'id');
        mCard.Number := TAtlasGitHubJson.IntOf(mIssue, 'number');
        mCard.Key := KeyOf(mIssue, ATarget.Project);
        mCard.Title := Copy(TAtlasGitHubJson.TextOf(mIssue, 'title'), 1, TAtlasBoardCard.MaxTitle);
        mCard.Page := TAtlasGitHubJson.TextOf(mIssue, 'url');
        mCard.Checklist := TAtlasTrackerChecklist.Progress(TAtlasGitHubJson.TextOf(mIssue, 'body'));
        mCard.ResolvedAt := TimeOfText(TAtlasGitHubJson.TextOf(mIssue, 'closedAt'));
        ReadAssignees(mIssue.Values['assignees'], mCard);
        mItemIteration := '';
        mValues := NodesOf(mEntry, 'fieldValues');
        if mValues <> nil then
        begin
          for mField in mValues do
          begin
            if not (mField is TJSONObject) then
            begin
              Continue;
            end;
            mFieldName := ObjectAt(mField, ['field']);
            mName := '';
            if mFieldName <> nil then
            begin
              mName := TAtlasGitHubJson.TextOf(mFieldName, 'name');
            end;
            if TJSONObject(mField).Values['iterationId'] is TJSONString then
            begin
              if SameText(mName, mIteration) then
              begin
                mItemIteration := TAtlasGitHubJson.TextOf(TJSONObject(mField), 'iterationId');
              end;
            end
            else if TJSONObject(mField).Values['number'] is TJSONNumber then
            begin
              if (ASnapshot.PointsField <> '') and SameText(mName, ASnapshot.PointsField) then
              begin
                mCard.Points := TJSONNumber(TJSONObject(mField).Values['number']).AsDouble;
                mCard.HasPoints := True;
              end;
            end
            else if SameText(mName, ASnapshot.Field) then
            begin
              mCard.State := TAtlasGitHubJson.TextOf(TJSONObject(mField), 'name');
            end
            else if (mPriority <> '') and SameText(mName, mPriority) then
            begin
              mCard.Priority := TAtlasGitHubJson.TextOf(TJSONObject(mField), 'name');
            end;
          end;
        end;
        // Mit Iterationen nur die Karten des Sprints.
        if (ASnapshot.Sprint.Id <> '') and not SameText(mItemIteration, ASnapshot.Sprint.Id) then
        begin
          Continue;
        end;
        ASnapshot.Cards := ASnapshot.Cards + [mCard];
      end;
    end;
    Result := True;
  finally
    mValue.Free;
  end;
end;

class function TAtlasGitHubBoards.ParseIssues(const AJson: string; const ATarget: TAtlasTrackerTarget;
  var ASnapshot: TAtlasBoardSnapshot): Boolean;
var
  mValue, mItem: TJSONValue;
  mIssue: TJSONObject;
  mCard: TAtlasBoardCard;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := mValue is TJSONArray;
    if not Result then
    begin
      Exit;
    end;
    for mItem in TJSONArray(mValue) do
    begin
      if not (mItem is TJSONObject) or (Length(ASnapshot.Cards) >= TAtlasBoardSnapshot.MaxCards) then
      begin
        Continue;
      end;
      mIssue := TJSONObject(mItem);
      // /issues enthält auch Pull Requests.
      if (mIssue.Values['pull_request'] <> nil) or (TAtlasGitHubJson.IntOf(mIssue, 'number') <= 0) then
      begin
        Continue;
      end;
      mCard := Default(TAtlasBoardCard);
      mCard.Number := TAtlasGitHubJson.IntOf(mIssue, 'number');
      mCard.Key := '#' + IntToStr(mCard.Number);
      mCard.Title := Copy(TAtlasGitHubJson.TextOf(mIssue, 'title'), 1, TAtlasBoardCard.MaxTitle);
      mCard.State := LowerCase(TAtlasGitHubJson.TextOf(mIssue, 'state'));
      mCard.Page := TAtlasGitHubJson.TextOf(mIssue, 'html_url');
      mCard.Checklist := TAtlasTrackerChecklist.Progress(TAtlasGitHubJson.TextOf(mIssue, 'body'));
      mCard.ResolvedAt := TimeOfText(TAtlasGitHubJson.TextOf(mIssue, 'closed_at'));
      ReadAssignees(mIssue.Values['assignees'], mCard);
      if ASnapshot.CardIndex(mCard.Key) < 0 then
      begin
        ASnapshot.Cards := ASnapshot.Cards + [mCard];
      end;
    end;
  finally
    mValue.Free;
  end;
end;

/// <summary>GraphQL-Anfrage; True nur mit Antwort ohne "errors".</summary>
function Query(const ASend: IAtlasCiSend; const AUrl, ABody: string; ATimeoutMs: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
var
  mResponse: TAtlasCiResponse;
  mMessage: string;
begin
  Result := False;
  if not ASend.Send('POST', AUrl, ABody, ATimeoutMs, mResponse) then
  begin
    AText := '';
    AError := mResponse.Error;
    Exit;
  end;
  AText := mResponse.Text;
  if mResponse.Status <> 200 then
  begin
    AError := TAtlasGitHubApi.ErrorOfStatus(mResponse.Status);
    Exit;
  end;
  AError := TAtlasGitHubBoards.GraphQlError(AText, mMessage);
  Result := AError = TAtlasCiFetchError.None;
end;

function GetText(const ATransport: IAtlasCiTransport; const AUrl: string; ATimeoutMs: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
var
  mStatus: Integer;
begin
  Result := False;
  if not ATransport.Get(AUrl, ATimeoutMs, mStatus, AText, AError) then
  begin
    Exit;
  end;
  if mStatus <> 200 then
  begin
    AError := TAtlasGitHubApi.ErrorOfStatus(mStatus);
    Exit;
  end;
  Result := True;
end;

/// <summary>Ohne Projekt: Spalten Offen und Geschlossen, Karten aus /issues, Anmeldename aus /user.</summary>
function LoadRepository(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AWatch: TStopwatch; ATimeoutMs: Integer; var ASnapshot: TAtlasBoardSnapshot;
  out AError: TAtlasCiFetchError): Boolean;
var
  mBase, mText: string;
  mValue: TJSONValue;
  mError: TAtlasCiFetchError;
begin
  Result := False;
  ASnapshot.Kind := TAtlasBoardKind.Repository;
  ASnapshot.Board := TAtlasBoardRef.Create('', '');
  ASnapshot.Field := 'state';
  ASnapshot.Columns := [TAtlasBoardColumn.Create('open', TArray<string>.Create('open'), '', False),
    TAtlasBoardColumn.Create('closed', TArray<string>.Create('closed'), '', True)];
  ASnapshot.Cards := nil;
  ASnapshot.PointsField := '';
  // Board im Browser: die Issues des Repositorys.
  ASnapshot.Page := TAtlasGitHubApi.IssuePage(ATarget, '#1');
  if ASnapshot.Page <> '' then
  begin
    SetLength(ASnapshot.Page, Length(ASnapshot.Page) - Length('/1'));
  end;
  mBase := TAtlasGitHubApi.Base(ATarget) + '/repos/' + ATarget.Project + '/issues';
  if not GetText(ATransport, mBase + '?state=open&per_page=100', TAtlasGitHubApi.Remaining(AWatch, ATimeoutMs), mText,
    AError) then
  begin
    Exit;
  end;
  if not TAtlasGitHubBoards.ParseIssues(mText, ATarget, ASnapshot) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  if GetText(ATransport, mBase + '?state=closed&sort=updated&per_page=' + IntToStr(TAtlasGitHubBoards.MaxClosed),
    TAtlasGitHubApi.Remaining(AWatch, ATimeoutMs), mText, mError) then
  begin
    TAtlasGitHubBoards.ParseIssues(mText, ATarget, ASnapshot);
  end;
  if (ASnapshot.Me = '') and GetText(ATransport, TAtlasGitHubApi.Base(ATarget) + '/user',
    TAtlasGitHubApi.Remaining(AWatch, ATimeoutMs), mText, mError) then
  begin
    mValue := TJSONObject.ParseJSONValue(mText);
    try
      if mValue is TJSONObject then
      begin
        ASnapshot.Me := TAtlasGitHubJson.TextOf(TJSONObject(mValue), 'login');
      end;
    finally
      mValue.Free;
    end;
  end;
  Result := True;
end;

function TAtlasGitHubBoards.LoadBoard(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const ABoardId, ASprintId: string; ATimeoutMs: Integer; out ASnapshot: TAtlasBoardSnapshot;
  out AError: TAtlasCiFetchError): Boolean;
var
  mWatch: TStopwatch;
  mSend: IAtlasCiSend;
  mUrl, mText, mOwner, mName, mProject: string;
  mIndex: Integer;
  mError: TAtlasCiFetchError;
begin
  ASnapshot := TAtlasBoardSnapshot.Empty;
  AError := TAtlasCiFetchError.None;
  Result := False;
  mUrl := GraphQlUrl(ATarget);
  mIndex := Pos('/', ATarget.Project);
  if (mUrl = '') or (mIndex <= 1) or (ATransport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  mOwner := Copy(ATarget.Project, 1, mIndex - 1);
  mName := Copy(ATarget.Project, mIndex + 1, MaxInt);
  mWatch := TStopwatch.StartNew;
  // GraphQL braucht POST; ohne Schreibweg bleibt nur die Liste ohne Projekt.
  mProject := '';
  mError := TAtlasCiFetchError.None;
  if Supports(ATransport, IAtlasCiSend, mSend) and Query(mSend, mUrl,
    GraphQlBody(ProjectsQuery, ['owner', mOwner, 'name', mName]), ATimeoutMs, mText, mError) and
    ParseProjects(mText, ASnapshot) then
  begin
    for mIndex := 0 to High(ASnapshot.Boards) do
    begin
      if (ABoardId <> '') and SameText(ASnapshot.Boards[mIndex].Id, ABoardId) then
      begin
        mProject := ASnapshot.Boards[mIndex].Id;
      end;
    end;
    if (mProject = '') and (Length(ASnapshot.Boards) > 0) then
    begin
      mProject := ASnapshot.Boards[0].Id;
    end;
  end;
  if mProject = '' then
  begin
    Result := LoadRepository(ATarget, ATransport, mWatch, ATimeoutMs, ASnapshot, AError);
    ASnapshot.ProjectsDenied := mError = TAtlasCiFetchError.Unauthorized;
    Exit;
  end;
  if not Query(mSend, mUrl, GraphQlBody(ProjectQuery, ['id', mProject]), TAtlasGitHubApi.Remaining(mWatch,
    ATimeoutMs), mText, AError) then
  begin
    Exit;
  end;
  if not ParseProject(mText, ATarget, ASprintId, TTimeZone.Local.ToUniversalTime(Now), ASnapshot) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  Result := True;
end;

function TAtlasGitHubBoards.MoveCard(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const ASnapshot: TAtlasBoardSnapshot; const ACard: TAtlasBoardCard; AColumn: Integer; const AComment: string;
  ATimeoutMs: Integer): TAtlasTrackerWriteResult;
var
  mWatch: TStopwatch;
  mSend: IAtlasCiSend;
  mUrl, mMessage, mBody: string;
  mResponse: TAtlasCiResponse;
  mError: TAtlasCiFetchError;
  mColumn: TAtlasBoardColumn;
begin
  if (AColumn < 0) or (AColumn > High(ASnapshot.Columns)) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 0, ''));
  end;
  if not Supports(ATransport, IAtlasCiSend, mSend) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, ''));
  end;
  mColumn := ASnapshot.Columns[AColumn];
  mWatch := TStopwatch.StartNew;
  // Zuerst der Kommentar (#1266): Fehlen die Schreibrechte, ändert sich nichts. Nur im Repository des Ziels.
  if (Trim(AComment) <> '') and (Copy(ACard.Key, 1, 1) = '#') then
  begin
    Result := TAtlasGitHubApi.PostComment(ATarget, mSend, ACard.Key, AComment, ATimeoutMs);
    if not Result.Succeeded then
    begin
      Exit;
    end;
  end;
  if ASnapshot.Kind = TAtlasBoardKind.Project then
  begin
    if (mColumn.OptionId = '') or (ACard.ItemId = '') or (ASnapshot.FieldId = '') then
    begin
      Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 0, ''));
    end;
    mBody := GraphQlBody(MoveMutation, ['project', ASnapshot.ProjectId, 'item', ACard.ItemId, 'field',
      ASnapshot.FieldId, 'option', mColumn.OptionId]);
    if not mSend.Send('POST', GraphQlUrl(ATarget), mBody, TAtlasGitHubApi.Remaining(mWatch, ATimeoutMs), mResponse) then
    begin
      Exit(TAtlasTrackerWriteResult.Failed(mResponse.Error, 0, ''));
    end;
    if mResponse.Status <> 200 then
    begin
      Exit(TAtlasTrackerWriteResult.Failed(TAtlasGitHubApi.ErrorOfStatus(mResponse.Status), mResponse.Status,
        TAtlasGitHubApi.ErrorMessage(mResponse.Text)));
    end;
    mError := GraphQlError(mResponse.Text, mMessage);
    if mError <> TAtlasCiFetchError.None then
    begin
      Exit(TAtlasTrackerWriteResult.Failed(mError, mResponse.Status, mMessage));
    end;
    Exit(TAtlasTrackerWriteResult.Ok);
  end;
  // Ohne Projekt: Zustand des Issues.
  mUrl := TAtlasGitHubApi.IssueApiUrl(ATarget, ACard.Key);
  if (mUrl = '') or (Length(mColumn.Values) = 0) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 0, ''));
  end;
  mBody := '{"state":"open"}';
  if mColumn.Resolved then
  begin
    mBody := '{"state":"closed"}';
  end;
  if not mSend.Send('PATCH', mUrl, mBody, TAtlasGitHubApi.Remaining(mWatch, ATimeoutMs), mResponse) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(mResponse.Error, 0, ''));
  end;
  if not TAtlasGitHubApi.Answered(mResponse.Status) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasGitHubApi.ErrorOfStatus(mResponse.Status), mResponse.Status,
      TAtlasGitHubApi.ErrorMessage(mResponse.Text)));
  end;
  Result := TAtlasTrackerWriteResult.Ok;
end;

end.
