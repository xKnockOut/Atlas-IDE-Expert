unit Atlas.Core.Tracker.Providers.GitHubBoard;

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

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Board;

type
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
  System.DateUtils,
  System.Diagnostics,
  System.Generics.Collections,
  System.JSON,
  Atlas.Core.Tracker.Checklist,
  Atlas.Core.Tracker.Providers.GitHub;

function TextOf(AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := AObject.Values[AName];
  if mValue is TJSONString then
    Result := TJSONString(mValue).Value;
end;

function IntOf(AObject: TJSONObject; const AName: string): Integer;
var
  mValue: TJSONValue;
begin
  Result := 0;
  mValue := AObject.Values[AName];
  if (mValue is TJSONNumber) and not TryStrToInt(TJSONNumber(mValue).Value, Result) then
    Result := 0;
end;

function FlagOf(AObject: TJSONObject; const AName: string): Boolean;
var
  mValue: TJSONValue;
begin
  mValue := AObject.Values[AName];
  Result := (mValue is TJSONBool) and TJSONBool(mValue).AsBoolean;
end;

/// <summary>ISO 8601 ("2026-10-28T09:12:00Z") als UTC; 0 ohne.</summary>
function TimeOfText(const AText: string): TDateTime;
begin
  Result := 0;
  if (AText = '') or not TryISO8601ToDate(AText, Result, True) then
    Result := 0;
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
      Exit;
    mValue := TJSONObject(mValue).Values[mName];
  end;
  if mValue is TJSONObject then
    Result := TJSONObject(mValue);
end;

/// <summary>Liste "nodes" eines Objekts; nil ohne.</summary>
function NodesOf(AObject: TJSONObject; const AName: string): TJSONArray;
var
  mValue: TJSONValue;
begin
  Result := nil;
  if AObject = nil then
    Exit;
  mValue := AObject.Values[AName];
  if mValue is TJSONObject then
    mValue := TJSONObject(mValue).Values['nodes'];
  if mValue is TJSONArray then
    Result := TJSONArray(mValue);
end;

function Rest(const AWatch: TStopwatch; ATimeoutMs: Integer): Integer;
var
  mRest: Int64;
begin
  mRest := ATimeoutMs - AWatch.ElapsedMilliseconds;
  Result := 0;
  if mRest > 0 then
    Result := Integer(mRest);
end;

function Answered(AStatus: Integer): Boolean;
begin
  Result := (AStatus >= 200) and (AStatus <= 299);
end;

{ TAtlasGitHubBoards }

class function TAtlasGitHubBoards.GraphQlUrl(const ATarget: TAtlasTrackerTarget): string;
var
  mBase: string;
begin
  Result := '';
  mBase := TAtlasGitHubTracker.ApiBase(ATarget);
  if mBase = '' then
    Exit;
  if mBase = TAtlasGitHubTracker.ApiHost then
    Result := mBase + '/graphql'
  else
    Result := ATarget.Server + '/api/graphql';
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
      Exit(TAtlasCiFetchError.Invalid);
    if not (TJSONObject(mValue).Values['errors'] is TJSONArray) then
      Exit;
    for mItem in TJSONArray(TJSONObject(mValue).Values['errors']) do
    begin
      if not (mItem is TJSONObject) then
        Continue;
      if AMessage = '' then
        AMessage := Copy(TextOf(TJSONObject(mItem), 'message'), 1, 300);
      mType := UpperCase(TextOf(TJSONObject(mItem), 'type'));
      if (mType = 'INSUFFICIENT_SCOPES') or (mType = 'FORBIDDEN') then
        Exit(TAtlasCiFetchError.Unauthorized);
      if mType = 'NOT_FOUND' then
        Result := TAtlasCiFetchError.NotFound;
    end;
    if Result = TAtlasCiFetchError.None then
      Result := TAtlasCiFetchError.Invalid;
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
      Exit;
    mViewer := ObjectAt(mValue, ['data', 'viewer']);
    if mViewer <> nil then
      ASnapshot.Me := TextOf(mViewer, 'login');
    mOpen := nil;
    mClosed := nil;
    mNodes := NodesOf(ObjectAt(mValue, ['data', 'repository']), 'projectsV2');
    if mNodes <> nil then
      for mItem in mNodes do
      begin
        if not (mItem is TJSONObject) then
          Continue;
        mProject := TJSONObject(mItem);
        mRef := TAtlasBoardRef.Create(TextOf(mProject, 'id'), TextOf(mProject, 'title'));
        if mRef.Id = '' then
          Continue;
        if FlagOf(mProject, 'closed') then
          mClosed := mClosed + [mRef]
        else
          mOpen := mOpen + [mRef];
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
  Result.Id := TextOf(AObject, 'id');
  Result.Name := TextOf(AObject, 'title');
  // startDate "2026-10-27" (Tag, UTC), duration in Tagen.
  if TryISO8601ToDate(TextOf(AObject, 'startDate'), mStart, True) then
  begin
    Result.Start := mStart;
    if IntOf(AObject, 'duration') > 0 then
      Result.Finish := mStart + IntOf(AObject, 'duration');
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
    if SameText(Trim(AName), mName) then
      Exit(True);
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
    Exit;
  for mItem in mNodes do
  begin
    if not (mItem is TJSONObject) then
      Continue;
    mField := TJSONObject(mItem);
    mName := TextOf(mField, 'name');
    if mField.Values['options'] is TJSONArray then
    begin
      // Auswahlfeld: „Status“ geht vor, sonst das erste außer der Priorität; diese gibt den Farbbalken.
      if SameText(mName, 'Priority') or SameText(mName, 'Priorität') then
        APriority := mName
      else if SameText(mName, 'Status') then
        mChosen := mField
      else if (mChosen = nil) and (mFirst = nil) then
        mFirst := mField;
    end
    else if (ASnapshot.PointsField = '') and SameText(TextOf(mField, 'dataType'), 'NUMBER') and
      IsPointsName(mName) then
      ASnapshot.PointsField := mName
    else if (AIteration = '') and (mField.Values['configuration'] is TJSONObject) then
    begin
      AIteration := mName;
      mConfig := TJSONObject(mField.Values['configuration']);
      // Laufende und künftige, dann abgeschlossene.
      if mConfig.Values['iterations'] is TJSONArray then
        for mOption in TJSONArray(mConfig.Values['iterations']) do
          if mOption is TJSONObject then
            ASnapshot.Sprints := ASnapshot.Sprints + [IterationOf(TJSONObject(mOption))];
      if mConfig.Values['completedIterations'] is TJSONArray then
        for mOption in TJSONArray(mConfig.Values['completedIterations']) do
          if mOption is TJSONObject then
          begin
            mSprint := IterationOf(TJSONObject(mOption));
            mSprint.Archived := True;
            ASnapshot.Sprints := ASnapshot.Sprints + [mSprint];
          end;
      ASnapshot.Sprints := Copy(ASnapshot.Sprints, 0, TAtlasBoardSnapshot.MaxSprints);
    end;
  end;
  if mChosen = nil then
    mChosen := mFirst;
  if mChosen = nil then
    Exit;
  ASnapshot.Field := TextOf(mChosen, 'name');
  ASnapshot.FieldId := TextOf(mChosen, 'id');
  mOptions := TJSONArray(mChosen.Values['options']);
  for mOption in mOptions do
    if (mOption is TJSONObject) and (TextOf(TJSONObject(mOption), 'name') <> '') then
      ASnapshot.Columns := ASnapshot.Columns + [TAtlasBoardColumn.Create(TextOf(TJSONObject(mOption), 'name'),
        TArray<string>.Create(TextOf(TJSONObject(mOption), 'name')), TextOf(TJSONObject(mOption), 'id'),
        TAtlasGitHubTracker.ClosesIssue(TextOf(TJSONObject(mOption), 'name')))];
end;

/// <summary>Kennung eines Issues: "#12" im Repository des Ziels, sonst "owner/repo#12".</summary>
function KeyOf(AIssue: TJSONObject; const AProject: string): string;
var
  mRepository: string;
begin
  Result := '#' + IntToStr(IntOf(AIssue, 'number'));
  mRepository := '';
  if AIssue.Values['repository'] is TJSONObject then
    mRepository := TextOf(TJSONObject(AIssue.Values['repository']), 'nameWithOwner');
  if (mRepository <> '') and not SameText(mRepository, AProject) then
    Result := mRepository + Result;
end;

/// <summary>Zuständige aus assignees (GraphQL: nodes, REST: Liste).</summary>
procedure ReadAssignees(AValue: TJSONValue; var ACard: TAtlasBoardCard);
var
  mItem: TJSONValue;
  mName: string;
begin
  if AValue is TJSONObject then
    AValue := TJSONObject(AValue).Values['nodes'];
  if not (AValue is TJSONArray) then
    Exit;
  for mItem in TJSONArray(AValue) do
  begin
    if not (mItem is TJSONObject) or (TextOf(TJSONObject(mItem), 'login') = '') then
      Continue;
    ACard.Logins := ACard.Logins + [TextOf(TJSONObject(mItem), 'login')];
    if ACard.Assignee = '' then
    begin
      mName := TextOf(TJSONObject(mItem), 'name');
      if mName = '' then
        mName := TextOf(TJSONObject(mItem), 'login');
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
    if (mProject = nil) or (TextOf(mProject, 'id') = '') then
      Exit;
    ASnapshot.Kind := TAtlasBoardKind.Project;
    ASnapshot.ProjectId := TextOf(mProject, 'id');
    ASnapshot.Board := TAtlasBoardRef.Create(ASnapshot.ProjectId, TextOf(mProject, 'title'));
    ASnapshot.Page := TextOf(mProject, 'url');
    ReadFields(mProject, ASnapshot, mIteration, mPriority);
    // Sprint: gewählt, sonst der aktuelle.
    ASnapshot.Sprint := Default(TAtlasBoardSprint);
    mSprint := -1;
    for mIndex := 0 to High(ASnapshot.Sprints) do
      if (ASprintId <> '') and SameText(ASnapshot.Sprints[mIndex].Id, ASprintId) then
        mSprint := mIndex;
    if mSprint < 0 then
      mSprint := TAtlasTrackerBoard.CurrentSprint(ASnapshot.Sprints, ANow);
    if mSprint >= 0 then
      ASnapshot.Sprint := ASnapshot.Sprints[mSprint];
    ASnapshot.Cards := nil;
    mNodes := NodesOf(mProject, 'items');
    if mNodes <> nil then
      for mItem in mNodes do
      begin
        if not (mItem is TJSONObject) or (Length(ASnapshot.Cards) >= TAtlasBoardSnapshot.MaxCards) then
          Continue;
        mEntry := TJSONObject(mItem);
        mIssue := ObjectAt(mEntry, ['content']);
        // Nur Issues; Pull Requests und Entwürfe haben hier keinen Inhalt.
        if (mIssue = nil) or (IntOf(mIssue, 'number') <= 0) then
          Continue;
        mCard := Default(TAtlasBoardCard);
        mCard.ItemId := TextOf(mEntry, 'id');
        mCard.Number := IntOf(mIssue, 'number');
        mCard.Key := KeyOf(mIssue, ATarget.Project);
        mCard.Title := Copy(TextOf(mIssue, 'title'), 1, TAtlasBoardCard.MaxTitle);
        mCard.Page := TextOf(mIssue, 'url');
        mCard.Checklist := TAtlasTrackerChecklist.Progress(TextOf(mIssue, 'body'));
        mCard.ResolvedAt := TimeOfText(TextOf(mIssue, 'closedAt'));
        ReadAssignees(mIssue.Values['assignees'], mCard);
        mItemIteration := '';
        mValues := NodesOf(mEntry, 'fieldValues');
        if mValues <> nil then
          for mField in mValues do
          begin
            if not (mField is TJSONObject) then
              Continue;
            mFieldName := ObjectAt(mField, ['field']);
            mName := '';
            if mFieldName <> nil then
              mName := TextOf(mFieldName, 'name');
            if TJSONObject(mField).Values['iterationId'] is TJSONString then
            begin
              if SameText(mName, mIteration) then
                mItemIteration := TextOf(TJSONObject(mField), 'iterationId');
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
              mCard.State := TextOf(TJSONObject(mField), 'name')
            else if (mPriority <> '') and SameText(mName, mPriority) then
              mCard.Priority := TextOf(TJSONObject(mField), 'name');
          end;
        // Mit Iterationen nur die Karten des Sprints.
        if (ASnapshot.Sprint.Id <> '') and not SameText(mItemIteration, ASnapshot.Sprint.Id) then
          Continue;
        ASnapshot.Cards := ASnapshot.Cards + [mCard];
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
      Exit;
    for mItem in TJSONArray(mValue) do
    begin
      if not (mItem is TJSONObject) or (Length(ASnapshot.Cards) >= TAtlasBoardSnapshot.MaxCards) then
        Continue;
      mIssue := TJSONObject(mItem);
      // /issues enthält auch Pull Requests.
      if (mIssue.Values['pull_request'] <> nil) or (IntOf(mIssue, 'number') <= 0) then
        Continue;
      mCard := Default(TAtlasBoardCard);
      mCard.Number := IntOf(mIssue, 'number');
      mCard.Key := '#' + IntToStr(mCard.Number);
      mCard.Title := Copy(TextOf(mIssue, 'title'), 1, TAtlasBoardCard.MaxTitle);
      mCard.State := LowerCase(TextOf(mIssue, 'state'));
      mCard.Page := TextOf(mIssue, 'html_url');
      mCard.Checklist := TAtlasTrackerChecklist.Progress(TextOf(mIssue, 'body'));
      mCard.ResolvedAt := TimeOfText(TextOf(mIssue, 'closed_at'));
      ReadAssignees(mIssue.Values['assignees'], mCard);
      if ASnapshot.CardIndex(mCard.Key) < 0 then
        ASnapshot.Cards := ASnapshot.Cards + [mCard];
    end;
  finally
    mValue.Free;
  end;
end;

/// <summary>GraphQL-Anfrage; True nur mit Antwort ohne "errors".</summary>
function Query(const ASend: IAtlasCiSend; const AUrl, ABody: string; ATimeoutMs: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
var
  mStatus: Integer;
  mMessage: string;
begin
  Result := False;
  if not ASend.Send('POST', AUrl, ABody, ATimeoutMs, mStatus, AText, AError) then
    Exit;
  if mStatus <> 200 then
  begin
    AError := TAtlasGitHubTracker.ErrorOfStatus(mStatus);
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
    Exit;
  if mStatus <> 200 then
  begin
    AError := TAtlasGitHubTracker.ErrorOfStatus(mStatus);
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
  ASnapshot.Page := (TAtlasGitHubTracker.Create as IAtlasTrackerProvider).IssuePage(ATarget, '#1');
  if ASnapshot.Page <> '' then
    SetLength(ASnapshot.Page, Length(ASnapshot.Page) - Length('/1'));
  mBase := TAtlasGitHubTracker.ApiBase(ATarget) + '/repos/' + ATarget.Project + '/issues';
  if not GetText(ATransport, mBase + '?state=open&per_page=100', Rest(AWatch, ATimeoutMs), mText, AError) then
    Exit;
  if not TAtlasGitHubBoards.ParseIssues(mText, ATarget, ASnapshot) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  if GetText(ATransport, mBase + '?state=closed&sort=updated&per_page=' + IntToStr(TAtlasGitHubBoards.MaxClosed),
    Rest(AWatch, ATimeoutMs), mText, mError) then
    TAtlasGitHubBoards.ParseIssues(mText, ATarget, ASnapshot);
  if (ASnapshot.Me = '') and GetText(ATransport, TAtlasGitHubTracker.ApiBase(ATarget) + '/user',
    Rest(AWatch, ATimeoutMs), mText, mError) then
  begin
    mValue := TJSONObject.ParseJSONValue(mText);
    try
      if mValue is TJSONObject then
        ASnapshot.Me := TextOf(TJSONObject(mValue), 'login');
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
      if (ABoardId <> '') and SameText(ASnapshot.Boards[mIndex].Id, ABoardId) then
        mProject := ASnapshot.Boards[mIndex].Id;
    if (mProject = '') and (Length(ASnapshot.Boards) > 0) then
      mProject := ASnapshot.Boards[0].Id;
  end;
  if mProject = '' then
  begin
    Result := LoadRepository(ATarget, ATransport, mWatch, ATimeoutMs, ASnapshot, AError);
    ASnapshot.ProjectsDenied := mError = TAtlasCiFetchError.Unauthorized;
    Exit;
  end;
  if not Query(mSend, mUrl, GraphQlBody(ProjectQuery, ['id', mProject]), Rest(mWatch, ATimeoutMs), mText, AError) then
    Exit;
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
  mWriter: IAtlasTrackerWriter;
  mUrl, mText, mMessage, mBody: string;
  mStatus: Integer;
  mError: TAtlasCiFetchError;
  mColumn: TAtlasBoardColumn;
begin
  if (AColumn < 0) or (AColumn > High(ASnapshot.Columns)) then
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 0, ''));
  if not Supports(ATransport, IAtlasCiSend, mSend) then
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, ''));
  mColumn := ASnapshot.Columns[AColumn];
  mWatch := TStopwatch.StartNew;
  // Zuerst der Kommentar (#1266): Fehlen die Schreibrechte, ändert sich nichts. Nur im Repository des Ziels.
  if (Trim(AComment) <> '') and (Copy(ACard.Key, 1, 1) = '#') then
  begin
    mWriter := TAtlasGitHubTracker.Create;
    Result := mWriter.Apply(ATarget, ATransport, ACard.Key, TAtlasTrackerChange.CommentOnly(AComment), ATimeoutMs);
    if not Result.Succeeded then
      Exit;
  end;
  if ASnapshot.Kind = TAtlasBoardKind.Project then
  begin
    if (mColumn.OptionId = '') or (ACard.ItemId = '') or (ASnapshot.FieldId = '') then
      Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 0, ''));
    mBody := GraphQlBody(MoveMutation, ['project', ASnapshot.ProjectId, 'item', ACard.ItemId, 'field',
      ASnapshot.FieldId, 'option', mColumn.OptionId]);
    if not mSend.Send('POST', GraphQlUrl(ATarget), mBody, Rest(mWatch, ATimeoutMs), mStatus, mText, mError) then
      Exit(TAtlasTrackerWriteResult.Failed(mError, 0, ''));
    if mStatus <> 200 then
      Exit(TAtlasTrackerWriteResult.Failed(TAtlasGitHubTracker.ErrorOfStatus(mStatus), mStatus,
        TAtlasGitHubTracker.ErrorMessage(mText)));
    mError := GraphQlError(mText, mMessage);
    if mError <> TAtlasCiFetchError.None then
      Exit(TAtlasTrackerWriteResult.Failed(mError, mStatus, mMessage));
    Exit(TAtlasTrackerWriteResult.Ok);
  end;
  // Ohne Projekt: Zustand des Issues.
  mUrl := TAtlasGitHubTracker.IssueApiUrl(ATarget, ACard.Key);
  if (mUrl = '') or (Length(mColumn.Values) = 0) then
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 0, ''));
  mBody := '{"state":"open"}';
  if mColumn.Resolved then
    mBody := '{"state":"closed"}';
  if not mSend.Send('PATCH', mUrl, mBody, Rest(mWatch, ATimeoutMs), mStatus, mText, mError) then
    Exit(TAtlasTrackerWriteResult.Failed(mError, 0, ''));
  if not Answered(mStatus) then
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasGitHubTracker.ErrorOfStatus(mStatus), mStatus,
      TAtlasGitHubTracker.ErrorMessage(mText)));
  Result := TAtlasTrackerWriteResult.Ok;
end;

end.
