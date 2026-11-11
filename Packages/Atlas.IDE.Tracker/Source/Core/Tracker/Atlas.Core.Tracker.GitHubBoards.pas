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
    cProjectsQuery = 'query($owner:String!,$name:String!){viewer{login}repository(owner:$owner,name:$name)' +
      '{projectsV2(first:50){nodes{id title closed}}}}';
    /// <summary>Ein Projekt mit Feldern und Einträgen.</summary>
    cProjectQuery = 'query($id:ID!){node(id:$id){... on ProjectV2{id title url ' +
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
    cMoveMutation = 'mutation($project:ID!,$item:ID!,$field:ID!,$option:String!){updateProjectV2ItemFieldValue(' +
      'input:{projectId:$project,itemId:$item,fieldId:$field,value:{singleSelectOptionId:$option}})' +
      '{projectV2Item{id}}}';
    /// <summary>Höchstens so viele geschlossene Issues ohne Projekt.</summary>
    cMaxClosed = 30;
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
    function LoadBoard(const ARequest: TAtlasBoardRequest; out ASnapshot: TAtlasBoardSnapshot;
      out AError: TAtlasCiFetchError): Boolean;
    function MoveCard(const AMove: TAtlasBoardMove; const ASnapshot: TAtlasBoardSnapshot): TAtlasTrackerWriteResult;
  end;

implementation

uses
  System.Classes,
  System.Diagnostics,
  System.DateUtils,
  System.Generics.Collections,
  System.JSON,
  System.StrUtils,
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
  if mBase = TAtlasGitHubApi.cApiHost then
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
    ASnapshot.Boards := Copy(mOpen + mClosed, 0, TAtlasBoardSnapshot.cMaxBoards);
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
  cNames: array[0..7] of string = ('Estimate', 'Estimation', 'Story Points', 'Points', 'Size', 'Schätzung',
    'Punkte', 'Aufwand');
var
  mName: string;
begin
  Result := False;
  for mName in cNames do
  begin
    if SameText(Trim(AName), mName) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Sprints einer Liste von Iterationen anhängen; AArchived für abgeschlossene.</summary>
procedure AddIterations(AList: TJSONValue; AArchived: Boolean; var ASprints: TArray<TAtlasBoardSprint>);
var
  mOption: TJSONValue;
  mSprint: TAtlasBoardSprint;
begin
  if not (AList is TJSONArray) then
  begin
    Exit;
  end;
  for mOption in TJSONArray(AList) do
  begin
    if mOption is TJSONObject then
    begin
      mSprint := IterationOf(TJSONObject(mOption));
      mSprint.Archived := AArchived;
      ASprints := ASprints + [mSprint];
    end;
  end;
end;

/// <summary>Sprints eines Iterationsfelds: laufende und künftige, dann abgeschlossene.</summary>
function SprintsOf(AConfig: TJSONObject): TArray<TAtlasBoardSprint>;
begin
  Result := nil;
  AddIterations(AConfig.Values['iterations'], False, Result);
  AddIterations(AConfig.Values['completedIterations'], True, Result);
  Result := Copy(Result, 0, TAtlasBoardSnapshot.cMaxSprints);
end;

/// <summary>Spalten aus den Optionen eines Auswahlfelds.</summary>
function OptionColumnsOf(AField: TJSONObject): TArray<TAtlasBoardColumn>;
var
  mOption: TJSONValue;
  mName: string;
begin
  Result := nil;
  for mOption in TJSONArray(AField.Values['options']) do
  begin
    if not (mOption is TJSONObject) then
    begin
      Continue;
    end;
    mName := TAtlasGitHubJson.TextOf(TJSONObject(mOption), 'name');
    if mName <> '' then
    begin
      Result := Result + [TAtlasBoardColumn.Create(mName, TArray<string>.Create(mName),
        TAtlasGitHubJson.TextOf(TJSONObject(mOption), 'id'), TAtlasGitHubApi.ClosesIssue(mName))];
    end;
  end;
end;

type
  /// <summary>Was ReadFields beim Durchgehen der Felder findet.</summary>
  TFieldScan = record
    Iteration: string;
    Priority: string;
    /// <summary>Feld „Status“.</summary>
    Chosen: TJSONObject;
    /// <summary>Erstes andere Auswahlfeld außer der Priorität.</summary>
    First: TJSONObject;
  end;

/// <summary>Auswahlfeld: „Status“ geht vor, sonst das erste außer der Priorität; diese gibt den Farbbalken.
/// </summary>
procedure ScanOptionField(AField: TJSONObject; const AName: string; var AScan: TFieldScan);
begin
  if SameText(AName, 'Priority') or SameText(AName, 'Priorität') then
  begin
    AScan.Priority := AName;
  end
  else if SameText(AName, 'Status') then
  begin
    AScan.Chosen := AField;
  end
  else if (AScan.Chosen = nil) and (AScan.First = nil) then
  begin
    AScan.First := AField;
  end;
end;

/// <summary>Ein Feld: Auswahl, Schätzung (#1277) oder Iteration.</summary>
procedure ScanField(AField: TJSONObject; var ASnapshot: TAtlasBoardSnapshot; var AScan: TFieldScan);
var
  mName: string;
begin
  mName := TAtlasGitHubJson.TextOf(AField, 'name');
  if AField.Values['options'] is TJSONArray then
  begin
    ScanOptionField(AField, mName, AScan);
  end
  else if (ASnapshot.PointsField = '') and SameText(TAtlasGitHubJson.TextOf(AField, 'dataType'), 'NUMBER') and
    IsPointsName(mName) then
  begin
    ASnapshot.PointsField := mName;
  end
  else if (AScan.Iteration = '') and (AField.Values['configuration'] is TJSONObject) then
  begin
    AScan.Iteration := mName;
    ASnapshot.Sprints := SprintsOf(TJSONObject(AField.Values['configuration']));
  end;
end;

/// <summary>Spalten, Feld, Schätzfeld und Sprints aus fields; Ergebnis: Namen von Iterations- und
/// Prioritätsfeld.</summary>
function ReadFields(AProject: TJSONObject; var ASnapshot: TAtlasBoardSnapshot): TFieldScan;
var
  mNodes: TJSONArray;
  mItem: TJSONValue;
  mScan: TFieldScan;
begin
  mScan := Default(TFieldScan);
  ASnapshot.Columns := nil;
  ASnapshot.Sprints := nil;
  ASnapshot.PointsField := '';
  mNodes := NodesOf(AProject, 'fields');
  if mNodes <> nil then
  begin
    for mItem in mNodes do
    begin
      if mItem is TJSONObject then
      begin
        ScanField(TJSONObject(mItem), ASnapshot, mScan);
      end;
    end;
  end;
  Result := mScan;
  if mScan.Chosen = nil then
  begin
    mScan.Chosen := mScan.First;
  end;
  if mScan.Chosen <> nil then
  begin
    ASnapshot.Field := TAtlasGitHubJson.TextOf(mScan.Chosen, 'name');
    ASnapshot.FieldId := TAtlasGitHubJson.TextOf(mScan.Chosen, 'id');
    ASnapshot.Columns := OptionColumnsOf(mScan.Chosen);
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

/// <summary>Sprint ASprintId, sonst der aktuelle nach ANow; leer ohne Sprints.</summary>
function ChosenSprint(const ASnapshot: TAtlasBoardSnapshot; const ASprintId: string;
  ANow: TDateTime): TAtlasBoardSprint;
var
  mIndex, mSprint: Integer;
begin
  Result := Default(TAtlasBoardSprint);
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
    Result := ASnapshot.Sprints[mSprint];
  end;
end;

/// <summary>Name des Feldes eines Feldwerts; '' ohne.</summary>
function FieldNameOf(AValue: TJSONObject): string;
var
  mField: TJSONObject;
begin
  Result := '';
  mField := ObjectAt(AValue, ['field']);
  if mField <> nil then
  begin
    Result := TAtlasGitHubJson.TextOf(mField, 'name');
  end;
end;

/// <summary>Ein Feldwert einer Karte: Iteration (AIteration), Schätzung, Status oder Priorität.</summary>
procedure ReadFieldValue(AValue: TJSONObject; const ASnapshot: TAtlasBoardSnapshot; const AScan: TFieldScan;
  var ACard: TAtlasBoardCard; var AIteration: string);
var
  mName: string;
begin
  mName := FieldNameOf(AValue);
  if AValue.Values['iterationId'] is TJSONString then
  begin
    if SameText(mName, AScan.Iteration) then
    begin
      AIteration := TAtlasGitHubJson.TextOf(AValue, 'iterationId');
    end;
  end
  else if AValue.Values['number'] is TJSONNumber then
  begin
    if (ASnapshot.PointsField <> '') and SameText(mName, ASnapshot.PointsField) then
    begin
      ACard.Points := TJSONNumber(AValue.Values['number']).AsDouble;
      ACard.HasPoints := True;
    end;
  end
  else if SameText(mName, ASnapshot.Field) then
  begin
    ACard.State := TAtlasGitHubJson.TextOf(AValue, 'name');
  end
  else if (AScan.Priority <> '') and SameText(mName, AScan.Priority) then
  begin
    ACard.Priority := TAtlasGitHubJson.TextOf(AValue, 'name');
  end;
end;

/// <summary>Karte aus einem Eintrag des Projekts; False für Pull Requests und Entwürfe (ohne Inhalt) und, mit
/// Iterationen, für Karten außerhalb des Sprints.</summary>
function ProjectCardOf(AEntry: TJSONObject; const AProject: string; const ASnapshot: TAtlasBoardSnapshot;
  const AScan: TFieldScan; out ACard: TAtlasBoardCard): Boolean;
var
  mIssue: TJSONObject;
  mValues: TJSONArray;
  mValue: TJSONValue;
  mIteration: string;
begin
  ACard := Default(TAtlasBoardCard);
  mIssue := ObjectAt(AEntry, ['content']);
  Result := (mIssue <> nil) and (TAtlasGitHubJson.IntOf(mIssue, 'number') > 0);
  if not Result then
  begin
    Exit;
  end;
  ACard.ItemId := TAtlasGitHubJson.TextOf(AEntry, 'id');
  ACard.Number := TAtlasGitHubJson.IntOf(mIssue, 'number');
  ACard.Key := KeyOf(mIssue, AProject);
  ACard.Title := Copy(TAtlasGitHubJson.TextOf(mIssue, 'title'), 1, TAtlasBoardCard.cMaxTitle);
  ACard.Page := TAtlasGitHubJson.TextOf(mIssue, 'url');
  ACard.Checklist := TAtlasTrackerChecklist.Progress(TAtlasGitHubJson.TextOf(mIssue, 'body'));
  ACard.ResolvedAt := TimeOfText(TAtlasGitHubJson.TextOf(mIssue, 'closedAt'));
  ReadAssignees(mIssue.Values['assignees'], ACard);
  mIteration := '';
  mValues := NodesOf(AEntry, 'fieldValues');
  if mValues <> nil then
  begin
    for mValue in mValues do
    begin
      if mValue is TJSONObject then
      begin
        ReadFieldValue(TJSONObject(mValue), ASnapshot, AScan, ACard, mIteration);
      end;
    end;
  end;
  // Mit Iterationen nur die Karten des Sprints.
  Result := (ASnapshot.Sprint.Id = '') or SameText(mIteration, ASnapshot.Sprint.Id);
end;

/// <summary>Karten aus items, höchstens TAtlasBoardSnapshot.cMaxCards.</summary>
procedure ReadProjectCards(AProject: TJSONObject; const ATarget: TAtlasTrackerTarget; const AScan: TFieldScan;
  var ASnapshot: TAtlasBoardSnapshot);
var
  mNodes: TJSONArray;
  mItem: TJSONValue;
  mCard: TAtlasBoardCard;
begin
  ASnapshot.Cards := nil;
  mNodes := NodesOf(AProject, 'items');
  if mNodes = nil then
  begin
    Exit;
  end;
  for mItem in mNodes do
  begin
    if (mItem is TJSONObject) and (Length(ASnapshot.Cards) < TAtlasBoardSnapshot.cMaxCards)
      and ProjectCardOf(TJSONObject(mItem), ATarget.Project, ASnapshot, AScan, mCard) then
    begin
      ASnapshot.Cards := ASnapshot.Cards + [mCard];
    end;
  end;
end;

class function TAtlasGitHubBoards.ParseProject(const AJson: string; const ATarget: TAtlasTrackerTarget;
  const ASprintId: string; ANow: TDateTime; var ASnapshot: TAtlasBoardSnapshot): Boolean;
var
  mValue: TJSONValue;
  mProject: TJSONObject;
  mScan: TFieldScan;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    mProject := ObjectAt(mValue, ['data', 'node']);
    Result := (mProject <> nil) and (TAtlasGitHubJson.TextOf(mProject, 'id') <> '');
    if not Result then
    begin
      Exit;
    end;
    ASnapshot.Kind := TAtlasBoardKind.Project;
    ASnapshot.ProjectId := TAtlasGitHubJson.TextOf(mProject, 'id');
    ASnapshot.Board := TAtlasBoardRef.Create(ASnapshot.ProjectId, TAtlasGitHubJson.TextOf(mProject, 'title'));
    ASnapshot.Page := TAtlasGitHubJson.TextOf(mProject, 'url');
    mScan := ReadFields(mProject, ASnapshot);
    // Sprint: gewählt, sonst der aktuelle.
    ASnapshot.Sprint := ChosenSprint(ASnapshot, ASprintId, ANow);
    ReadProjectCards(mProject, ATarget, mScan, ASnapshot);
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
      if not (mItem is TJSONObject) or (Length(ASnapshot.Cards) >= TAtlasBoardSnapshot.cMaxCards) then
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
      mCard.Title := Copy(TAtlasGitHubJson.TextOf(mIssue, 'title'), 1, TAtlasBoardCard.cMaxTitle);
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
  if not TAtlasGitHubApi.GetText(ATransport, mBase + '?state=open&per_page=100', TAtlasGitHubApi.Remaining(AWatch,
    ATimeoutMs), mText,
    AError) then
  begin
    Exit;
  end;
  if not TAtlasGitHubBoards.ParseIssues(mText, ATarget, ASnapshot) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  if TAtlasGitHubApi.GetText(ATransport,
    mBase + '?state=closed&sort=updated&per_page=' + IntToStr(TAtlasGitHubBoards.cMaxClosed),
    TAtlasGitHubApi.Remaining(AWatch, ATimeoutMs), mText, mError) then
  begin
    TAtlasGitHubBoards.ParseIssues(mText, ATarget, ASnapshot);
  end;
  if (ASnapshot.Me = '') and TAtlasGitHubApi.GetText(ATransport, TAtlasGitHubApi.Base(ATarget) + '/user',
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

/// <summary>Das gewählte Projekt (ABoardId, sonst das erste) aus ASnapshot.Boards; '' ohne Projekte.</summary>
function ChosenProject(const ASnapshot: TAtlasBoardSnapshot; const ABoardId: string): string;
var
  mBoard: TAtlasBoardRef;
begin
  Result := '';
  for mBoard in ASnapshot.Boards do
  begin
    if (ABoardId <> '') and SameText(mBoard.Id, ABoardId) then
    begin
      Result := mBoard.Id;
    end;
  end;
  if (Result = '') and (Length(ASnapshot.Boards) > 0) then
  begin
    Result := ASnapshot.Boards[0].Id;
  end;
end;

/// <summary>Projekte des Repositorys über GraphQL lesen und eins wählen; '' ohne (dann AError: warum).</summary>
function LoadProjectId(const ARequest: TAtlasBoardRequest; const ASend: IAtlasCiSend; const AUrl: string;
  var ASnapshot: TAtlasBoardSnapshot; out AError: TAtlasCiFetchError): string;
var
  mText, mOwner, mName: string;
  mAt: Integer;
begin
  Result := '';
  AError := TAtlasCiFetchError.None;
  mAt := Pos('/', ARequest.Target.Project);
  mOwner := Copy(ARequest.Target.Project, 1, mAt - 1);
  mName := Copy(ARequest.Target.Project, mAt + 1, MaxInt);
  if Query(ASend, AUrl, TAtlasGitHubBoards.GraphQlBody(TAtlasGitHubBoards.cProjectsQuery, ['owner', mOwner, 'name',
    mName]), ARequest.TimeoutMs, mText, AError) and TAtlasGitHubBoards.ParseProjects(mText, ASnapshot) then
  begin
    Result := ChosenProject(ASnapshot, ARequest.BoardId);
  end;
end;

function TAtlasGitHubBoards.LoadBoard(const ARequest: TAtlasBoardRequest; out ASnapshot: TAtlasBoardSnapshot;
  out AError: TAtlasCiFetchError): Boolean;
var
  mWatch: TStopwatch;
  mSend: IAtlasCiSend;
  mUrl, mText, mProject: string;
  mError: TAtlasCiFetchError;
begin
  ASnapshot := TAtlasBoardSnapshot.Empty;
  AError := TAtlasCiFetchError.None;
  Result := False;
  mUrl := GraphQlUrl(ARequest.Target);
  if (mUrl = '') or (Pos('/', ARequest.Target.Project) <= 1) or (ARequest.Transport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  mWatch := TStopwatch.StartNew;
  // GraphQL braucht POST; ohne Schreibweg bleibt nur die Liste ohne Projekt.
  mProject := '';
  mError := TAtlasCiFetchError.None;
  if Supports(ARequest.Transport, IAtlasCiSend, mSend) then
  begin
    mProject := LoadProjectId(ARequest, mSend, mUrl, ASnapshot, mError);
  end;
  if mProject = '' then
  begin
    Result := LoadRepository(ARequest.Target, ARequest.Transport, mWatch, ARequest.TimeoutMs, ASnapshot, AError);
    ASnapshot.ProjectsDenied := mError = TAtlasCiFetchError.Unauthorized;
  end
  else if Query(mSend, mUrl, GraphQlBody(cProjectQuery, ['id', mProject]), TAtlasGitHubApi.Remaining(mWatch,
    ARequest.TimeoutMs), mText, AError) then
  begin
    Result := ParseProject(mText, ARequest.Target, ARequest.SprintId, TTimeZone.Local.ToUniversalTime(Now),
      ASnapshot);
    if not Result then
    begin
      AError := TAtlasCiFetchError.Invalid;
    end;
  end;
end;

/// <summary>Ergebnis einer GraphQL-Antwort auf einen Schreibzugriff: Fehler bei fehlender Antwort, anderem
/// Status als 200 bzw. "errors", sonst Ok.</summary>
function GraphQlWriteResult(ASent: Boolean; const AResponse: TAtlasCiResponse): TAtlasTrackerWriteResult;
var
  mError: TAtlasCiFetchError;
  mMessage: string;
begin
  if ASent and (AResponse.Status <> 200) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasGitHubApi.ErrorOfStatus(AResponse.Status), AResponse.Status,
      TAtlasGitHubApi.ErrorMessage(AResponse.Text)));
  end;
  Result := TAtlasGitHubApi.WriteResult(ASent, AResponse);
  if Result.Succeeded then
  begin
    mError := TAtlasGitHubBoards.GraphQlError(AResponse.Text, mMessage);
    if mError <> TAtlasCiFetchError.None then
    begin
      Result := TAtlasTrackerWriteResult.Failed(mError, AResponse.Status, mMessage);
    end;
  end;
end;

/// <summary>Projekt: Feld „Status“ des Eintrags auf die Option der Spalte setzen.</summary>
function MoveInProject(const AMove: TAtlasBoardMove; const ASnapshot: TAtlasBoardSnapshot; const ASend: IAtlasCiSend;
  ATimeoutMs: Integer): TAtlasTrackerWriteResult;
var
  mColumn: TAtlasBoardColumn;
  mBody: string;
  mResponse: TAtlasCiResponse;
begin
  mColumn := ASnapshot.Columns[AMove.Column];
  if (mColumn.OptionId = '') or (AMove.Card.ItemId = '') or (ASnapshot.FieldId = '') then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 0, ''));
  end;
  mBody := TAtlasGitHubBoards.GraphQlBody(TAtlasGitHubBoards.cMoveMutation, ['project', ASnapshot.ProjectId, 'item',
    AMove.Card.ItemId, 'field', ASnapshot.FieldId, 'option', mColumn.OptionId]);
  Result := GraphQlWriteResult(ASend.Send('POST', TAtlasGitHubBoards.GraphQlUrl(AMove.Target), mBody, ATimeoutMs,
    mResponse), mResponse);
end;

/// <summary>Ohne Projekt: Zustand des Issues nach der Spalte (offen oder geschlossen).</summary>
function MoveInRepository(const AMove: TAtlasBoardMove; const ASnapshot: TAtlasBoardSnapshot;
  const ASend: IAtlasCiSend; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
var
  mColumn: TAtlasBoardColumn;
  mUrl, mBody: string;
  mResponse: TAtlasCiResponse;
begin
  mColumn := ASnapshot.Columns[AMove.Column];
  mUrl := TAtlasGitHubApi.IssueApiUrl(AMove.Target, AMove.Card.Key);
  if (mUrl = '') or (Length(mColumn.Values) = 0) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 0, ''));
  end;
  mBody := '{"state":"open"}';
  if mColumn.Resolved then
  begin
    mBody := '{"state":"closed"}';
  end;
  Result := TAtlasGitHubApi.WriteResult(ASend.Send('PATCH', mUrl, mBody, ATimeoutMs, mResponse), mResponse);
end;

function TAtlasGitHubBoards.MoveCard(const AMove: TAtlasBoardMove;
  const ASnapshot: TAtlasBoardSnapshot): TAtlasTrackerWriteResult;
var
  mWatch: TStopwatch;
  mSend: IAtlasCiSend;
begin
  if (AMove.Column < 0) or (AMove.Column > High(ASnapshot.Columns)) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 0, ''));
  end;
  if not Supports(AMove.Transport, IAtlasCiSend, mSend) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, ''));
  end;
  mWatch := TStopwatch.StartNew;
  Result := TAtlasTrackerWriteResult.Ok;
  // Zuerst der Kommentar (#1266): Fehlen die Schreibrechte, ändert sich nichts. Nur im Repository des Ziels.
  if (Trim(AMove.Comment) <> '') and (Copy(AMove.Card.Key, 1, 1) = '#') then
  begin
    Result := TAtlasGitHubApi.PostComment(AMove.Target, mSend, AMove.Card.Key, AMove.Comment, AMove.TimeoutMs);
  end;
  if not Result.Succeeded then
  begin
    Exit;
  end;
  if ASnapshot.Kind = TAtlasBoardKind.Project then
  begin
    Result := MoveInProject(AMove, ASnapshot, mSend, TAtlasGitHubApi.Remaining(mWatch, AMove.TimeoutMs));
  end
  else
  begin
    Result := MoveInRepository(AMove, ASnapshot, mSend, TAtlasGitHubApi.Remaining(mWatch, AMove.TimeoutMs));
  end;
end;

end.
