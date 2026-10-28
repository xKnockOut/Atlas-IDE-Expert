unit Atlas.Core.Tracker.Providers.YouTrackBoard;

// Agile Boards von YouTrack (#1272), ohne VCL und Open Tools API.
// - Boards: GET /api/agiles mit Spalten (columnSettings: Spaltenfeld, je
//   Spalte die Werte des Feldes wie auf dem Board des Servers, auch deutsche).
//   Gewählt wird das Board ABoardId, sonst das erste mit dem Projekt des
//   Ziels, sonst das erste.
// - Sprints: GET /api/agiles/<id>/sprints; Karten aus
//   GET /api/agiles/<id>/sprints/<sprint|current> mit den Issues.
// - Eine Karte liest Kennung, Titel und Verknüpfungen über
//   TAtlasYouTrackTracker.ParseDetails (Schloss über TAtlasTrackerLinks.Locked,
//   #1279), die Checkliste aus der Beschreibung (#1273), den Wert des
//   Spaltenfeldes, den Anmeldenamen des Zuständigen und die Farbe der
//   Priorität.
// - Verschieben: ein Befehl über TAtlasYouTrackTracker.Apply (#1266) mit dem
//   Spaltenfeld und dem ersten Wert der Zielspalte, Kommentar im selben
//   Befehl.
// - Sprint-Kachel (#1277): Schätzfeld des Boards (estimationField, Zahl bzw.
//   Zeitraum in Stunden), Zeitpunkt der Erledigung (resolved) und die
//   Arbeitstage aus GET /api/admin/timeTrackingSettings/workTimeSettings
//   (workDays, 1 = Montag … 7 = Sonntag; ohne Recht bleibt Mo–Fr).

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Board,
  Atlas.Core.Tracker.Sprint;

type
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
    function LoadBoard(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const ABoardId, ASprintId: string; ATimeoutMs: Integer; out ASnapshot: TAtlasBoardSnapshot;
      out AError: TAtlasCiFetchError): Boolean;
    function MoveCard(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const ASnapshot: TAtlasBoardSnapshot; const ACard: TAtlasBoardCard; AColumn: Integer; const AComment: string;
      ATimeoutMs: Integer): TAtlasTrackerWriteResult;
    { IAtlasTrackerWorkDays }
    function WorkDays(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; ATimeoutMs: Integer;
      out ADays: TArray<Integer>): Boolean;
  end;

implementation

uses
  System.DateUtils,
  System.Diagnostics,
  System.Generics.Collections,
  System.JSON,
  Atlas.Text.Uris,
  Atlas.Core.Tracker.Checklist,
  Atlas.Core.Tracker.Links,
  Atlas.Core.Tracker.Providers.YouTrack;

function TextOf(AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := AObject.Values[AName];
  if mValue is TJSONString then
    Result := TJSONString(mValue).Value;
end;

function FlagOf(AObject: TJSONObject; const AName: string): Boolean;
var
  mValue: TJSONValue;
begin
  mValue := AObject.Values[AName];
  Result := (mValue is TJSONBool) and TJSONBool(mValue).AsBoolean;
end;

/// <summary>Millisekunden seit 1970 (YouTrack) als UTC; 0 ohne.</summary>
function TimeOf(AObject: TJSONObject; const AName: string): TDateTime;
var
  mValue: TJSONValue;
  mMs: Int64;
begin
  Result := 0;
  mValue := AObject.Values[AName];
  if (mValue is TJSONNumber) and TryStrToInt64(TJSONNumber(mValue).Value, mMs) and (mMs > 0) then
    Result := UnixToDateTime(mMs div 1000, True) + (mMs mod 1000) / MSecsPerDay;
end;

function IsOneOf(const AName: string; const ANames: array of string): Boolean;
var
  mName: string;
begin
  Result := False;
  for mName in ANames do
    if SameText(AName, mName) then
      Exit(True);
end;

function ValidId(const AId: string): Boolean;
var
  mIndex: Integer;
begin
  Result := AId <> '';
  for mIndex := 1 to Length(AId) do
    if not CharInSet(AId[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.']) then
      Exit(False);
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

{ TAtlasYouTrackBoards }

class function TAtlasYouTrackBoards.AgilesUrl(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := '';
  if ATarget.Server <> '' then
    Result := ATarget.Url + '/api/agiles?fields=' + TTextUris.PercentEncode(AgileFields) + '&$top=' +
      IntToStr(TAtlasBoardSnapshot.MaxBoards);
end;

class function TAtlasYouTrackBoards.SprintsUrl(const ATarget: TAtlasTrackerTarget; const ABoardId: string): string;
begin
  Result := '';
  if (ATarget.Server <> '') and ValidId(ABoardId) then
    Result := ATarget.Url + '/api/agiles/' + ABoardId + '/sprints?fields=' + TTextUris.PercentEncode(SprintFields) +
      '&$top=' + IntToStr(TAtlasBoardSnapshot.MaxSprints);
end;

class function TAtlasYouTrackBoards.SprintUrl(const ATarget: TAtlasTrackerTarget;
  const ABoardId, ASprintId: string): string;
var
  mSprint: string;
begin
  Result := '';
  mSprint := Trim(ASprintId);
  if mSprint = '' then
    mSprint := 'current';
  if (ATarget.Server <> '') and ValidId(ABoardId) and ValidId(mSprint) then
    Result := ATarget.Url + '/api/agiles/' + ABoardId + '/sprints/' + mSprint + '?fields=' +
      TTextUris.PercentEncode(SprintFields + ',issues(' + CardFields + ')');
end;

function HasProject(ABoard: TJSONObject; const AProject: string): Boolean;
var
  mItem: TJSONValue;
begin
  Result := False;
  if (AProject = '') or not (ABoard.Values['projects'] is TJSONArray) then
    Exit;
  for mItem in TJSONArray(ABoard.Values['projects']) do
    if (mItem is TJSONObject) and SameText(TextOf(TJSONObject(mItem), 'shortName'), AProject) then
      Exit(True);
end;

/// <summary>Spalten und Feld eines Boards aus columnSettings.</summary>
procedure ReadColumns(ABoard: TJSONObject; var ASnapshot: TAtlasBoardSnapshot);
var
  mSettings, mItem, mValue: TJSONValue;
  mColumn: TJSONObject;
  mValues: TArray<string>;
  mName: string;
begin
  ASnapshot.Columns := nil;
  ASnapshot.Field := '';
  mSettings := ABoard.Values['columnSettings'];
  if not (mSettings is TJSONObject) then
    Exit;
  if TJSONObject(mSettings).Values['field'] is TJSONObject then
    ASnapshot.Field := TextOf(TJSONObject(TJSONObject(mSettings).Values['field']), 'name');
  if not (TJSONObject(mSettings).Values['columns'] is TJSONArray) then
    Exit;
  for mItem in TJSONArray(TJSONObject(mSettings).Values['columns']) do
  begin
    if not (mItem is TJSONObject) then
      Continue;
    mColumn := TJSONObject(mItem);
    mValues := nil;
    if mColumn.Values['fieldValues'] is TJSONArray then
      for mValue in TJSONArray(mColumn.Values['fieldValues']) do
        if (mValue is TJSONObject) and (TextOf(TJSONObject(mValue), 'name') <> '') then
          mValues := mValues + [TextOf(TJSONObject(mValue), 'name')];
    // presentation fasst mehrere Werte zusammen ("Offen, Nachgefragt"); ohne sie der erste Wert.
    mName := TextOf(mColumn, 'presentation');
    if (mName = '') and (Length(mValues) > 0) then
      mName := mValues[0];
    ASnapshot.Columns := ASnapshot.Columns + [TAtlasBoardColumn.Create(mName, mValues, '',
      FlagOf(mColumn, 'isResolved'))];
  end;
end;

class function TAtlasYouTrackBoards.ParseAgiles(const AJson, ABoardId, AProject: string;
  var ASnapshot: TAtlasBoardSnapshot; out ACurrentSprint: string): Boolean;
var
  mValue, mItem: TJSONValue;
  mBoard, mChosen, mByProject: TJSONObject;
  mId: string;
begin
  ACurrentSprint := '';
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONArray) then
      Exit;
    ASnapshot.Boards := nil;
    mChosen := nil;
    mByProject := nil;
    for mItem in TJSONArray(mValue) do
    begin
      if not (mItem is TJSONObject) or (Length(ASnapshot.Boards) >= TAtlasBoardSnapshot.MaxBoards) then
        Continue;
      mBoard := TJSONObject(mItem);
      mId := TextOf(mBoard, 'id');
      if not ValidId(mId) then
        Continue;
      ASnapshot.Boards := ASnapshot.Boards + [TAtlasBoardRef.Create(mId, TextOf(mBoard, 'name'))];
      if (ABoardId <> '') and SameText(mId, ABoardId) then
        mChosen := mBoard;
      if (mByProject = nil) and HasProject(mBoard, AProject) then
        mByProject := mBoard;
    end;
    if mChosen = nil then
      mChosen := mByProject;
    if (mChosen = nil) and (TJSONArray(mValue).Count > 0) then
      for mItem in TJSONArray(mValue) do
        if (mItem is TJSONObject) and ValidId(TextOf(TJSONObject(mItem), 'id')) then
        begin
          mChosen := TJSONObject(mItem);
          Break;
        end;
    if mChosen = nil then
      Exit;
    ASnapshot.Kind := TAtlasBoardKind.Agile;
    ASnapshot.Board := TAtlasBoardRef.Create(TextOf(mChosen, 'id'), TextOf(mChosen, 'name'));
    ReadColumns(mChosen, ASnapshot);
    ASnapshot.PointsField := '';
    if mChosen.Values['estimationField'] is TJSONObject then
      ASnapshot.PointsField := TextOf(TJSONObject(mChosen.Values['estimationField']), 'name');
    if mChosen.Values['currentSprint'] is TJSONObject then
      ACurrentSprint := TextOf(TJSONObject(mChosen.Values['currentSprint']), 'id');
    Result := True;
  finally
    mValue.Free;
  end;
end;

function SprintOf(AObject: TJSONObject): TAtlasBoardSprint;
begin
  Result := Default(TAtlasBoardSprint);
  Result.Id := TextOf(AObject, 'id');
  Result.Name := TextOf(AObject, 'name');
  Result.Start := TimeOf(AObject, 'start');
  Result.Finish := TimeOf(AObject, 'finish');
  Result.Archived := FlagOf(AObject, 'archived');
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
      Exit;
    for mItem in TJSONArray(mValue) do
    begin
      if not (mItem is TJSONObject) or (Length(ASprints) >= TAtlasBoardSnapshot.MaxSprints) then
        Continue;
      mSprint := SprintOf(TJSONObject(mItem));
      if ValidId(mSprint.Id) then
        ASprints := ASprints + [mSprint];
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
procedure ReadFields(AIssue: TJSONObject; const AField, APoints: string; var ACard: TAtlasBoardCard);
var
  mItem, mValue, mColor: TJSONValue;
  mField: TJSONObject;
  mName, mLogin: string;
begin
  if not (AIssue.Values['customFields'] is TJSONArray) then
    Exit;
  for mItem in TJSONArray(AIssue.Values['customFields']) do
  begin
    if not (mItem is TJSONObject) then
      Continue;
    mField := TJSONObject(mItem);
    mName := Trim(TextOf(mField, 'name'));
    mValue := mField.Values['value'];
    if (AField <> '') and SameText(mName, AField) and (mValue is TJSONObject) then
      ACard.State := TextOf(TJSONObject(mValue), 'name')
    else if (APoints <> '') and SameText(mName, APoints) then
      ReadPoints(mValue, ACard)
    else if IsOneOf(mName, ['Assignee', 'Zuständig', 'Bearbeiter', 'Verantwortlich']) and
      (mValue is TJSONObject) then
    begin
      mLogin := TextOf(TJSONObject(mValue), 'login');
      if mLogin <> '' then
        ACard.Logins := ACard.Logins + [mLogin];
    end
    else if IsOneOf(mName, ['Priority', 'Priorität']) and (mValue is TJSONObject) then
    begin
      mColor := TJSONObject(mValue).Values['color'];
      if mColor is TJSONObject then
        ACard.PriorityColor := TextOf(TJSONObject(mColor), 'background');
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
  mProvider: IAtlasTrackerProvider;
begin
  Result := False;
  mProvider := TAtlasYouTrackTracker.Create;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) then
      Exit;
    mRoot := TJSONObject(mValue);
    ASnapshot.Sprint := SprintOf(mRoot);
    ASnapshot.Cards := nil;
    if mRoot.Values['issues'] is TJSONArray then
      for mItem in TJSONArray(mRoot.Values['issues']) do
      begin
        if not (mItem is TJSONObject) or (Length(ASnapshot.Cards) >= TAtlasBoardSnapshot.MaxCards) then
          Continue;
        mIssue := TJSONObject(mItem);
        // Dieselbe Auswertung wie die Vorschau: Titel, Felder, Beschreibung und Verknüpfungen.
        if not TAtlasYouTrackTracker.ParseDetails(mIssue.ToJSON, ATarget, False, mDetails) then
          Continue;
        mCard := Default(TAtlasBoardCard);
        mCard.Key := mDetails.Key;
        mCard.Number := mDetails.Number;
        mCard.Title := Copy(mDetails.Title, 1, TAtlasBoardCard.MaxTitle);
        mCard.Assignee := mDetails.Assignee;
        mCard.Priority := mDetails.Priority;
        mCard.Checklist := TAtlasTrackerChecklist.Progress(mDetails.Description);
        mCard.Locked := TAtlasTrackerLinks.Locked(mDetails);
        mCard.Page := mProvider.IssuePage(ATarget, mDetails.Key);
        mCard.ResolvedAt := TimeOf(mIssue, 'resolved');
        ReadFields(mIssue, ASnapshot.Field, ASnapshot.PointsField, mCard);
        ASnapshot.Cards := ASnapshot.Cards + [mCard];
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
      for mItem in TJSONArray(TJSONObject(mValue).Values['workDays']) do
        if (mItem is TJSONNumber) and TryStrToInt(TJSONNumber(mItem).Value, mDay) and (mDay >= 1) and (mDay <= 7) then
          ADays := ADays + [mDay];
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
    mSprint := 'current';
  if (ATarget.Server <> '') and ValidId(ABoardId) and ValidId(mSprint) then
    Result := ATarget.Url + '/agiles/' + ABoardId + '/' + mSprint;
end;

/// <summary>GET mit Fehler aus dem Status; True nur mit 200.</summary>
function GetText(const ATransport: IAtlasCiTransport; const AUrl: string; ATimeoutMs: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
var
  mStatus: Integer;
begin
  Result := False;
  AText := '';
  if AUrl = '' then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  if not ATransport.Get(AUrl, ATimeoutMs, mStatus, AText, AError) then
    Exit;
  if mStatus <> 200 then
  begin
    AError := TAtlasYouTrackTracker.ErrorOfStatus(mStatus);
    Exit;
  end;
  Result := True;
end;

function TAtlasYouTrackBoards.LoadBoard(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const ABoardId, ASprintId: string; ATimeoutMs: Integer; out ASnapshot: TAtlasBoardSnapshot;
  out AError: TAtlasCiFetchError): Boolean;
var
  mWatch: TStopwatch;
  mText, mCurrent, mSprint: string;
  mValue: TJSONValue;
  mError: TAtlasCiFetchError;
  mSprints: TArray<TAtlasBoardSprint>;
begin
  ASnapshot := TAtlasBoardSnapshot.Empty;
  AError := TAtlasCiFetchError.None;
  Result := False;
  if (ATarget.Server = '') or (ATransport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  mWatch := TStopwatch.StartNew;
  if not GetText(ATransport, AgilesUrl(ATarget), ATimeoutMs, mText, AError) then
    Exit;
  if not ParseAgiles(mText, ABoardId, ATarget.Project, ASnapshot, mCurrent) then
  begin
    // Leere Liste: kein Board für dieses Konto.
    AError := TAtlasCiFetchError.NotFound;
    if Pos('[', mText) = 0 then
      AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  if GetText(ATransport, SprintsUrl(ATarget, ASnapshot.Board.Id), Rest(mWatch, ATimeoutMs), mText, mError) and
    ParseSprints(mText, mSprints) then
    ASnapshot.Sprints := mSprints;
  // Gewählter Sprint, sonst der aktuelle des Boards.
  mSprint := Trim(ASprintId);
  if mSprint = '' then
    mSprint := mCurrent;
  if not GetText(ATransport, SprintUrl(ATarget, ASnapshot.Board.Id, mSprint), Rest(mWatch, ATimeoutMs), mText,
    AError) then
    Exit;
  if not ParseSprint(mText, ATarget, ASnapshot) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  ASnapshot.Page := BoardPage(ATarget, ASnapshot.Board.Id, ASnapshot.Sprint.Id);
  // Eigener Anmeldename für „Nur meine“; ohne ihn filtert das Board nicht.
  if GetText(ATransport, ATarget.Url + '/api/users/me?fields=login', Rest(mWatch, ATimeoutMs), mText, mError) then
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

function TAtlasYouTrackBoards.MoveCard(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const ASnapshot: TAtlasBoardSnapshot; const ACard: TAtlasBoardCard; AColumn: Integer; const AComment: string;
  ATimeoutMs: Integer): TAtlasTrackerWriteResult;
var
  mChange: TAtlasTrackerChange;
  mWriter: IAtlasTrackerWriter;
begin
  if (AColumn < 0) or (AColumn > High(ASnapshot.Columns)) or (Length(ASnapshot.Columns[AColumn].Values) = 0) then
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 0, ''));
  // Derselbe Schreibweg wie „Beginnen“ und „Beenden“ (#1266): ein Befehl mit Feld, Wert und Kommentar.
  mChange := TAtlasTrackerChange.Empty;
  mChange.StateField := ASnapshot.Field;
  mChange.State := ASnapshot.Columns[AColumn].Values[0];
  mChange.Comment := AComment;
  mWriter := TAtlasYouTrackTracker.Create;
  Result := mWriter.Apply(ATarget, ATransport, ACard.Key, mChange, ATimeoutMs);
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
    GetText(ATransport, ATarget.Url + WorkDaysPath, ATimeoutMs, mText, mError) and ParseWorkDays(mText, ADays);
end;

end.
