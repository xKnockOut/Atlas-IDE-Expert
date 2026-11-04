unit Atlas.Core.Tracker.YouTrackBoards;

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Board,
  Atlas.Core.Tracker.Sprint;

type
  // Agile Boards von YouTrack (#1272), ohne VCL und Open Tools API.
  // - Boards: GET /api/agiles mit Spalten (columnSettings: Spaltenfeld, je
  //   Spalte die Werte des Feldes wie auf dem Board des Servers, auch deutsche).
  //   Gewählt wird das Board ABoardId, sonst das erste mit dem Projekt des
  //   Ziels, sonst das erste.
  // - Sprints: GET /api/agiles/<id>/sprints; Karten aus
  //   GET /api/agiles/<id>/sprints/<sprint|current> mit den Issues.
  // - Eine Karte liest Kennung, Titel und Verknüpfungen über
  //   TAtlasYouTrackParse.ParseDetails (Schloss über TAtlasTrackerLinks.Locked,
  //   #1279), die Checkliste aus der Beschreibung (#1273), den Wert des
  //   Spaltenfeldes, den Anmeldenamen des Zuständigen und die Farbe der
  //   Priorität.
  // - Verschieben: ein Befehl über TAtlasYouTrackApi.ApplyChange (#1266) mit dem
  //   Spaltenfeld und dem ersten Wert der Zielspalte, Kommentar im selben
  //   Befehl.
  // - Sprint-Kachel (#1277): Schätzfeld des Boards (estimationField, Zahl bzw.
  //   Zeitraum in Stunden), Zeitpunkt der Erledigung (resolved) und die
  //   Arbeitstage aus GET /api/admin/timeTrackingSettings/workTimeSettings
  //   (workDays, 1 = Montag … 7 = Sonntag; ohne Recht bleibt Mo–Fr).
  TAtlasYouTrackBoards = class(TInterfacedObject, IAtlasTrackerBoards, IAtlasTrackerWorkDays)
  public const
    AgileFields = 'id,name,projects(shortName),columnSettings(field(name),columns(presentation,isResolved,' +
      'fieldValues(name))),currentSprint(id),estimationField(name)';
    SprintFields = 'id,name,start,finish,archived';
    WorkDaysPath = '/api/admin/timeTrackingSettings/workTimeSettings?fields=workDays';
    /// <summary>Felder einer Karte: wie die Vorschau (#1264) ohne Anhänge und Tags, dazu login, Farbe und minutes
    /// (Schätzung als Zeitraum, #1277).</summary>
    CardFields = 'idReadable,numberInProject,summary,description,resolved,' +
      'customFields(name,value(name,presentation,login,fullName,minutes,color(background))),' +
      'links(direction,linkType(name,localizedName,sourceToTarget,localizedSourceToTarget,targetToSource,' +
      'localizedTargetToSource,aggregation),issues(idReadable,summary,resolved,customFields(name,value(name))))';
  public
    class function AgilesUrl(const ATarget: TAtlasTrackerTarget): string; static;
    class function SprintsUrl(const ATarget: TAtlasTrackerTarget; const ABoardId: string): string; static;
    /// <summary>ASprintId '' = "current".</summary>
    class function SprintUrl(const ATarget: TAtlasTrackerTarget; const ABoardId, ASprintId: string): string; static;
    /// <summary>Antwort von /api/agiles: Boards zur Auswahl und das gewählte mit Spalten und Feld in ASnapshot;
    /// ACurrentSprint = ID des aktuellen Sprints. False bei ungültigem JSON oder ohne Board.</summary>
    class function ParseAgiles(const AJson, ABoardId, AProject: string; var ASnapshot: TAtlasBoardSnapshot;
      out ACurrentSprint: string): Boolean; static;
    /// <summary>Antwort von …/sprints; False bei ungültigem JSON.</summary>
    class function ParseSprints(const AJson: string; out ASprints: TArray<TAtlasBoardSprint>): Boolean; static;
    /// <summary>Antwort von …/sprints/&lt;id&gt;: Sprint und Karten in ASnapshot (Spaltenfeld ASnapshot.Field).
    /// False bei ungültigem JSON.</summary>
    class function ParseSprint(const AJson: string; const ATarget: TAtlasTrackerTarget;
      var ASnapshot: TAtlasBoardSnapshot): Boolean; static;
    /// <summary>Antwort von workTimeSettings: Arbeitstage (1 = Montag … 7 = Sonntag); False ohne gültige.</summary>
    class function ParseWorkDays(const AJson: string; out ADays: TArray<Integer>): Boolean; static;
    /// <summary>Board im Browser: …/agiles/&lt;Board&gt;/&lt;Sprint|current&gt;.</summary>
    class function BoardPage(const ATarget: TAtlasTrackerTarget; const ABoardId, ASprintId: string): string; static;
    { IAtlasTrackerBoards }
    function LoadBoard(const ARequest: TAtlasBoardRequest; out ASnapshot: TAtlasBoardSnapshot;
      out AError: TAtlasCiFetchError): Boolean;
    function MoveCard(const AMove: TAtlasBoardMove; const ASnapshot: TAtlasBoardSnapshot): TAtlasTrackerWriteResult;
    { IAtlasTrackerWorkDays }
    function WorkDays(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; ATimeoutMs: Integer;
      out ADays: TArray<Integer>): Boolean;
  end;

implementation

uses
  System.Diagnostics,
  System.Generics.Collections,
  System.JSON,
  Atlas.Text.Uris,
  Atlas.Core.Tracker.Links,
  Atlas.Core.Tracker.Checklist,
  Atlas.Core.Tracker.Internals.YouTrackJson,
  Atlas.Core.Tracker.YouTrackApi,
  Atlas.Core.Tracker.YouTrackParse;

class function TAtlasYouTrackBoards.AgilesUrl(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := '';
  if ATarget.Server <> '' then
  begin
    Result := ATarget.Url + '/api/agiles?fields=' + TTextUris.PercentEncode(AgileFields) + '&$top=' +
      IntToStr(TAtlasBoardSnapshot.MaxBoards);
  end;
end;

class function TAtlasYouTrackBoards.SprintsUrl(const ATarget: TAtlasTrackerTarget; const ABoardId: string): string;
begin
  Result := '';
  if (ATarget.Server <> '') and TAtlasYouTrackJson.ValidId(ABoardId) then
  begin
    Result := ATarget.Url + '/api/agiles/' + ABoardId + '/sprints?fields=' + TTextUris.PercentEncode(SprintFields) +
      '&$top=' + IntToStr(TAtlasBoardSnapshot.MaxSprints);
  end;
end;

class function TAtlasYouTrackBoards.SprintUrl(const ATarget: TAtlasTrackerTarget;
  const ABoardId, ASprintId: string): string;
var
  mSprint: string;
begin
  Result := '';
  mSprint := Trim(ASprintId);
  if mSprint = '' then
  begin
    mSprint := 'current';
  end;
  if (ATarget.Server <> '') and TAtlasYouTrackJson.ValidId(ABoardId) and TAtlasYouTrackJson.ValidId(mSprint) then
  begin
    Result := ATarget.Url + '/api/agiles/' + ABoardId + '/sprints/' + mSprint + '?fields=' +
      TTextUris.PercentEncode(SprintFields + ',issues(' + CardFields + ')');
  end;
end;

function HasProject(ABoard: TJSONObject; const AProject: string): Boolean;
var
  mItem: TJSONValue;
begin
  Result := False;
  if (AProject = '') or not (ABoard.Values['projects'] is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(ABoard.Values['projects']) do
  begin
    if (mItem is TJSONObject) and SameText(TAtlasYouTrackJson.TextOf(TJSONObject(mItem), 'shortName'), AProject) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Text AField des Objekts AName in AObject; '' ohne.</summary>
function NestedText(AObject: TJSONObject; const AName, AField: string): string;
begin
  Result := '';
  if AObject.Values[AName] is TJSONObject then
  begin
    Result := TAtlasYouTrackJson.TextOf(TJSONObject(AObject.Values[AName]), AField);
  end;
end;

/// <summary>Namen aus fieldValues einer Spalte.</summary>
function ColumnValues(AColumn: TJSONObject): TArray<string>;
var
  mValue: TJSONValue;
  mName: string;
begin
  Result := nil;
  if not (AColumn.Values['fieldValues'] is TJSONArray) then
  begin
    Exit;
  end;
  for mValue in TJSONArray(AColumn.Values['fieldValues']) do
  begin
    if mValue is TJSONObject then
    begin
      mName := TAtlasYouTrackJson.TextOf(TJSONObject(mValue), 'name');
      if mName <> '' then
      begin
        Result := Result + [mName];
      end;
    end;
  end;
end;

/// <summary>Eine Spalte; presentation fasst mehrere Werte zusammen ("Offen, Nachgefragt"), ohne sie der erste Wert.
/// </summary>
function ColumnOf(AColumn: TJSONObject): TAtlasBoardColumn;
var
  mValues: TArray<string>;
  mName: string;
begin
  mValues := ColumnValues(AColumn);
  mName := TAtlasYouTrackJson.TextOf(AColumn, 'presentation');
  if (mName = '') and (Length(mValues) > 0) then
  begin
    mName := mValues[0];
  end;
  Result := TAtlasBoardColumn.Create(mName, mValues, '', TAtlasYouTrackJson.BoolOf(AColumn, 'isResolved'));
end;

/// <summary>Spalten und Feld eines Boards aus columnSettings.</summary>
procedure ReadColumns(ABoard: TJSONObject; var ASnapshot: TAtlasBoardSnapshot);
var
  mSettings: TJSONObject;
  mItem: TJSONValue;
begin
  ASnapshot.Columns := nil;
  ASnapshot.Field := '';
  if not (ABoard.Values['columnSettings'] is TJSONObject) then
  begin
    Exit;
  end;
  mSettings := TJSONObject(ABoard.Values['columnSettings']);
  ASnapshot.Field := NestedText(mSettings, 'field', 'name');
  if not (mSettings.Values['columns'] is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(mSettings.Values['columns']) do
  begin
    if mItem is TJSONObject then
    begin
      ASnapshot.Columns := ASnapshot.Columns + [ColumnOf(TJSONObject(mItem))];
    end;
  end;
end;

/// <summary>Board-Objekt mit gültiger Kennung, sonst nil.</summary>
function ValidBoard(AItem: TJSONValue): TJSONObject;
begin
  Result := nil;
  if (AItem is TJSONObject) and TAtlasYouTrackJson.ValidId(TAtlasYouTrackJson.TextOf(TJSONObject(AItem), 'id')) then
  begin
    Result := TJSONObject(AItem);
  end;
end;

/// <summary>Sammelt die Boards (höchstens MaxBoards) in ASnapshot und wählt eins: das mit ABoardId, sonst das erste
/// mit dem Projekt, sonst das erste gültige; nil ohne.</summary>
function ChooseBoard(AList: TJSONArray; const ABoardId, AProject: string;
  var ASnapshot: TAtlasBoardSnapshot): TJSONObject;
var
  mItem: TJSONValue;
  mBoard, mChosen, mByProject, mFirst: TJSONObject;
begin
  ASnapshot.Boards := nil;
  mChosen := nil;
  mByProject := nil;
  mFirst := nil;
  for mItem in AList do
  begin
    mBoard := ValidBoard(mItem);
    if mFirst = nil then
    begin
      mFirst := mBoard;
    end;
    if (mBoard = nil) or (Length(ASnapshot.Boards) >= TAtlasBoardSnapshot.MaxBoards) then
    begin
      Continue;
    end;
    ASnapshot.Boards := ASnapshot.Boards + [TAtlasBoardRef.Create(TAtlasYouTrackJson.TextOf(mBoard, 'id'),
      TAtlasYouTrackJson.TextOf(mBoard, 'name'))];
    if (ABoardId <> '') and SameText(TAtlasYouTrackJson.TextOf(mBoard, 'id'), ABoardId) then
    begin
      mChosen := mBoard;
    end;
    if (mByProject = nil) and HasProject(mBoard, AProject) then
    begin
      mByProject := mBoard;
    end;
  end;
  Result := mChosen;
  if Result = nil then
  begin
    Result := mByProject;
  end;
  if Result = nil then
  begin
    Result := mFirst;
  end;
end;

class function TAtlasYouTrackBoards.ParseAgiles(const AJson, ABoardId, AProject: string;
  var ASnapshot: TAtlasBoardSnapshot; out ACurrentSprint: string): Boolean;
var
  mValue: TJSONValue;
  mChosen: TJSONObject;
begin
  ACurrentSprint := '';
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := mValue is TJSONArray;
    if not Result then
    begin
      Exit;
    end;
    mChosen := ChooseBoard(TJSONArray(mValue), ABoardId, AProject, ASnapshot);
    Result := mChosen <> nil;
    if not Result then
    begin
      Exit;
    end;
    ASnapshot.Kind := TAtlasBoardKind.Agile;
    ASnapshot.Board := TAtlasBoardRef.Create(TAtlasYouTrackJson.TextOf(mChosen, 'id'),
      TAtlasYouTrackJson.TextOf(mChosen, 'name'));
    ReadColumns(mChosen, ASnapshot);
    ASnapshot.PointsField := NestedText(mChosen, 'estimationField', 'name');
    ACurrentSprint := NestedText(mChosen, 'currentSprint', 'id');
  finally
    mValue.Free;
  end;
end;

function SprintOf(AObject: TJSONObject): TAtlasBoardSprint;
begin
  Result := Default(TAtlasBoardSprint);
  Result.Id := TAtlasYouTrackJson.TextOf(AObject, 'id');
  Result.Name := TAtlasYouTrackJson.TextOf(AObject, 'name');
  Result.Start := TAtlasYouTrackJson.TimeOf(AObject, 'start');
  Result.Finish := TAtlasYouTrackJson.TimeOf(AObject, 'finish');
  Result.Archived := TAtlasYouTrackJson.BoolOf(AObject, 'archived');
end;

class function TAtlasYouTrackBoards.ParseSprints(const AJson: string;
  out ASprints: TArray<TAtlasBoardSprint>): Boolean;
var
  mValue, mItem: TJSONValue;
  mSprint: TAtlasBoardSprint;
begin
  ASprints := nil;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := mValue is TJSONArray;
    if not Result then
    begin
      Exit;
    end;
    for mItem in TJSONArray(mValue) do
    begin
      if not (mItem is TJSONObject) or (Length(ASprints) >= TAtlasBoardSnapshot.MaxSprints) then
      begin
        Continue;
      end;
      mSprint := SprintOf(TJSONObject(mItem));
      if TAtlasYouTrackJson.ValidId(mSprint.Id) then
      begin
        ASprints := ASprints + [mSprint];
      end;
    end;
  finally
    mValue.Free;
  end;
end;

/// <summary>Schätzung: Zahl (Story Points) bzw. Zeitraum ({"minutes": …}) in Stunden.</summary>
procedure ReadPoints(AValue: TJSONValue; var ACard: TAtlasBoardCard);
var
  mMinutes: TJSONValue;
begin
  if AValue is TJSONNumber then
  begin
    ACard.Points := TJSONNumber(AValue).AsDouble;
    ACard.HasPoints := True;
  end
  else if AValue is TJSONObject then
  begin
    mMinutes := TJSONObject(AValue).Values['minutes'];
    if mMinutes is TJSONNumber then
    begin
      ACard.Points := TJSONNumber(mMinutes).AsDouble / 60;
      ACard.HasPoints := True;
    end;
  end;
end;

/// <summary>Spaltenwert, Zuständige (Anmeldename), Prioritätsfarbe und Schätzung (APoints) aus customFields.
/// </summary>
/// <summary>Zuständig (Anmeldename) bzw. Farbe der Priorität aus dem Wert eines Felds.</summary>
procedure ReadObjectField(const AName: string; AValue: TJSONObject; var ACard: TAtlasBoardCard);
var
  mLogin: string;
begin
  if TAtlasYouTrackJson.IsOneOf(AName, ['Assignee', 'Zuständig', 'Bearbeiter', 'Verantwortlich']) then
  begin
    mLogin := TAtlasYouTrackJson.TextOf(AValue, 'login');
    if mLogin <> '' then
    begin
      ACard.Logins := ACard.Logins + [mLogin];
    end;
  end
  else if TAtlasYouTrackJson.IsOneOf(AName, ['Priority', 'Priorität']) and (AValue.Values['color'] is TJSONObject) then
  begin
    ACard.PriorityColor := TAtlasYouTrackJson.TextOf(TJSONObject(AValue.Values['color']), 'background');
  end;
end;

/// <summary>Ein Eintrag von customFields: Spaltenfeld (Zustand), Punkte, Zuständig oder Priorität.</summary>
procedure ReadField(AField: TJSONObject; const AStateField, APoints: string; var ACard: TAtlasBoardCard);
var
  mName: string;
  mValue: TJSONValue;
begin
  mName := Trim(TAtlasYouTrackJson.TextOf(AField, 'name'));
  mValue := AField.Values['value'];
  if (AStateField <> '') and SameText(mName, AStateField) and (mValue is TJSONObject) then
  begin
    ACard.State := TAtlasYouTrackJson.TextOf(TJSONObject(mValue), 'name');
  end
  else if (APoints <> '') and SameText(mName, APoints) then
  begin
    ReadPoints(mValue, ACard);
  end
  else if mValue is TJSONObject then
  begin
    ReadObjectField(mName, TJSONObject(mValue), ACard);
  end;
end;

procedure ReadFields(AIssue: TJSONObject; const AField, APoints: string; var ACard: TAtlasBoardCard);
var
  mItem: TJSONValue;
begin
  if not (AIssue.Values['customFields'] is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AIssue.Values['customFields']) do
  begin
    if mItem is TJSONObject then
    begin
      ReadField(TJSONObject(mItem), AField, APoints, ACard);
    end;
  end;
end;

class function TAtlasYouTrackBoards.ParseSprint(const AJson: string; const ATarget: TAtlasTrackerTarget;
  var ASnapshot: TAtlasBoardSnapshot): Boolean;
var
  mValue, mItem: TJSONValue;
  mRoot, mIssue: TJSONObject;
  mDetails: TAtlasTrackerDetails;
  mCard: TAtlasBoardCard;
begin
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mRoot := TJSONObject(mValue);
    ASnapshot.Sprint := SprintOf(mRoot);
    ASnapshot.Cards := nil;
    if mRoot.Values['issues'] is TJSONArray then
    begin
      for mItem in TJSONArray(mRoot.Values['issues']) do
      begin
        if not (mItem is TJSONObject) or (Length(ASnapshot.Cards) >= TAtlasBoardSnapshot.MaxCards) then
        begin
          Continue;
        end;
        mIssue := TJSONObject(mItem);
        // Dieselbe Auswertung wie die Vorschau: Titel, Felder, Beschreibung und Verknüpfungen.
        if not TAtlasYouTrackParse.ParseDetails(mIssue.ToJSON, ATarget, False, mDetails) then
        begin
          Continue;
        end;
        mCard := Default(TAtlasBoardCard);
        mCard.Key := mDetails.Key;
        mCard.Number := mDetails.Number;
        mCard.Title := Copy(mDetails.Title, 1, TAtlasBoardCard.MaxTitle);
        mCard.Assignee := mDetails.Assignee;
        mCard.Priority := mDetails.Priority;
        mCard.Checklist := TAtlasTrackerChecklist.Progress(mDetails.Description);
        mCard.Locked := TAtlasTrackerLinks.Locked(mDetails);
        mCard.Page := TAtlasYouTrackApi.IssuePage(ATarget, mDetails.Key);
        mCard.ResolvedAt := TAtlasYouTrackJson.TimeOf(mIssue, 'resolved');
        ReadFields(mIssue, ASnapshot.Field, ASnapshot.PointsField, mCard);
        ASnapshot.Cards := ASnapshot.Cards + [mCard];
      end;
    end;
    Result := True;
  finally
    mValue.Free;
  end;
end;

class function TAtlasYouTrackBoards.ParseWorkDays(const AJson: string; out ADays: TArray<Integer>): Boolean;
var
  mValue, mItem: TJSONValue;
  mDay: Integer;
begin
  ADays := nil;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if (mValue is TJSONObject) and (TJSONObject(mValue).Values['workDays'] is TJSONArray) then
    begin
      for mItem in TJSONArray(TJSONObject(mValue).Values['workDays']) do
      begin
        if (mItem is TJSONNumber) and TryStrToInt(TJSONNumber(mItem).Value, mDay) and (mDay >= 1) and (mDay <= 7) then
        begin
          ADays := ADays + [mDay];
        end;
      end;
    end;
  finally
    mValue.Free;
  end;
  Result := Length(ADays) > 0;
end;

class function TAtlasYouTrackBoards.BoardPage(const ATarget: TAtlasTrackerTarget;
  const ABoardId, ASprintId: string): string;
var
  mSprint: string;
begin
  Result := '';
  mSprint := Trim(ASprintId);
  if mSprint = '' then
  begin
    mSprint := 'current';
  end;
  if (ATarget.Server <> '') and TAtlasYouTrackJson.ValidId(ABoardId) and TAtlasYouTrackJson.ValidId(mSprint) then
  begin
    Result := ATarget.Url + '/agiles/' + ABoardId + '/' + mSprint;
  end;
end;

/// <summary>Boards laden und eins wählen (ASnapshot.Board, Spalten); ACurrent ist sein aktueller Sprint.</summary>
function LoadAgiles(const ARequest: TAtlasBoardRequest; var ASnapshot: TAtlasBoardSnapshot; out ACurrent: string;
  out AError: TAtlasCiFetchError): Boolean;
var
  mText: string;
begin
  ACurrent := '';
  Result := False;
  AError := TAtlasCiFetchError.NotConfigured;
  if (ARequest.Target.Server = '') or (ARequest.Transport = nil) or
    not TAtlasYouTrackApi.GetText(ARequest.Transport, TAtlasYouTrackBoards.AgilesUrl(ARequest.Target),
    ARequest.TimeoutMs, mText, AError) then
  begin
    Exit;
  end;
  Result := TAtlasYouTrackBoards.ParseAgiles(mText, ARequest.BoardId, ARequest.Target.Project, ASnapshot, ACurrent);
  // Leere Liste: kein Board für dieses Konto.
  if Result then
  begin
    AError := TAtlasCiFetchError.None;
  end
  else if Pos('[', mText) = 0 then
  begin
    AError := TAtlasCiFetchError.Invalid;
  end
  else
  begin
    AError := TAtlasCiFetchError.NotFound;
  end;
end;

/// <summary>Sprints des Boards (ohne sie bleibt die Auswahl leer) und die Karten des gewählten Sprints, sonst des
/// aktuellen (ACurrent).</summary>
function LoadSprint(const ARequest: TAtlasBoardRequest; const AWatch: TStopwatch; const ACurrent: string;
  var ASnapshot: TAtlasBoardSnapshot; out AError: TAtlasCiFetchError): Boolean;
var
  mText, mSprint: string;
  mSprints: TArray<TAtlasBoardSprint>;
  mError: TAtlasCiFetchError;
begin
  if TAtlasYouTrackApi.GetText(ARequest.Transport, TAtlasYouTrackBoards.SprintsUrl(ARequest.Target,
    ASnapshot.Board.Id), TAtlasYouTrackApi.Rest(AWatch, ARequest.TimeoutMs), mText, mError) and
    TAtlasYouTrackBoards.ParseSprints(mText, mSprints) then
  begin
    ASnapshot.Sprints := mSprints;
  end;
  mSprint := Trim(ARequest.SprintId);
  if mSprint = '' then
  begin
    mSprint := ACurrent;
  end;
  Result := TAtlasYouTrackApi.GetText(ARequest.Transport, TAtlasYouTrackBoards.SprintUrl(ARequest.Target,
    ASnapshot.Board.Id, mSprint), TAtlasYouTrackApi.Rest(AWatch, ARequest.TimeoutMs), mText, AError);
  if Result and not TAtlasYouTrackBoards.ParseSprint(mText, ARequest.Target, ASnapshot) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Result := False;
  end;
end;

/// <summary>Eigener Anmeldename für „Nur meine“; '' ohne (dann filtert das Board nicht).</summary>
function MyLogin(const ARequest: TAtlasBoardRequest; const AWatch: TStopwatch): string;
var
  mText: string;
  mValue: TJSONValue;
  mError: TAtlasCiFetchError;
begin
  Result := '';
  if not TAtlasYouTrackApi.GetText(ARequest.Transport, ARequest.Target.Url + '/api/users/me?fields=login',
    TAtlasYouTrackApi.Rest(AWatch, ARequest.TimeoutMs), mText, mError) then
  begin
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(mText);
  try
    if mValue is TJSONObject then
    begin
      Result := TAtlasYouTrackJson.TextOf(TJSONObject(mValue), 'login');
    end;
  finally
    mValue.Free;
  end;
end;

function TAtlasYouTrackBoards.LoadBoard(const ARequest: TAtlasBoardRequest; out ASnapshot: TAtlasBoardSnapshot;
  out AError: TAtlasCiFetchError): Boolean;
var
  mWatch: TStopwatch;
  mCurrent: string;
  mSnapshot: TAtlasBoardSnapshot;
begin
  mSnapshot := TAtlasBoardSnapshot.Empty;
  mWatch := TStopwatch.StartNew;
  Result := LoadAgiles(ARequest, mSnapshot, mCurrent, AError) and
    LoadSprint(ARequest, mWatch, mCurrent, mSnapshot, AError);
  if Result then
  begin
    mSnapshot.Page := BoardPage(ARequest.Target, mSnapshot.Board.Id, mSnapshot.Sprint.Id);
    mSnapshot.Me := MyLogin(ARequest, mWatch);
  end;
  ASnapshot := mSnapshot;
end;

function TAtlasYouTrackBoards.MoveCard(const AMove: TAtlasBoardMove;
  const ASnapshot: TAtlasBoardSnapshot): TAtlasTrackerWriteResult;
var
  mChange: TAtlasTrackerWrite;
begin
  if (AMove.Column < 0) or (AMove.Column > High(ASnapshot.Columns))
    or (Length(ASnapshot.Columns[AMove.Column].Values) = 0) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 0, ''));
  end;
  // Derselbe Schreibweg wie „Beginnen“ und „Beenden“ (#1266): ein Befehl mit Feld, Wert und Kommentar.
  mChange := TAtlasTrackerWrite.Empty;
  mChange.StateField := ASnapshot.Field;
  mChange.State := ASnapshot.Columns[AMove.Column].Values[0];
  mChange.Comment := AMove.Comment;
  Result := TAtlasYouTrackApi.ApplyChange(AMove.Target, AMove.Transport, AMove.Card.Key, mChange, AMove.TimeoutMs);
end;

function TAtlasYouTrackBoards.WorkDays(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  ATimeoutMs: Integer; out ADays: TArray<Integer>): Boolean;
var
  mText: string;
  mError: TAtlasCiFetchError;
begin
  ADays := nil;
  // Braucht oft Administratorrechte; ohne Antwort bleibt die Vorgabe Mo–Fr beim Aufrufer.
  Result := (ATarget.Server <> '') and (ATransport <> nil) and
    TAtlasYouTrackApi.GetText(ATransport, ATarget.Url + WorkDaysPath, ATimeoutMs, mText, mError) and ParseWorkDays(mText, ADays);
end;

end.
