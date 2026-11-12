unit Atlas.Core.Tracker.YouTrackFlow;

// Daten der Ablauf-Karte (#2125) aus YouTrack, ohne VCL; Adressen und Lesen
// der Antworten ohne Netz und daher testbar.
// - Zustandswechsel: GET <url>/api/activitiesPage?categories=
//   CustomFieldCategory&issueQuery=project: <Kürzel>&start=<ms> liefert alle
//   Feldänderungen des Projekts seit start, älteste zuerst, seitenweise über
//   afterCursor/hasAfter. Auf ein Feld filtern kann die Abfrage nicht; das
//   Zustandsfeld wählt Atlas aus: per Name (Einstellung bzw. Verbindung),
//   sonst am Feldtyp "state[…]", sonst an den üblichen Namen. Aus target
//   kommen Kennung, Titel und Anlage des Issues, aus added/removed die Werte
//   samt isResolved.
// - Offene Issues: /api/issues?query=project: <Kürzel> #Unresolved mit
//   Zustand, Zuständig und Anlage; meine dazu über "for: me".
// - Grenzen: höchstens cMaxPages Seiten zu cPageSize bzw. cMaxOpen offene
//   Issues und die Zeitgrenze des Auftrags; was danach fehlt, meldet
//   Truncated. Scheitert schon die erste Abfrage, gibt es keine Daten.
// Rechte: Leserecht auf die Issues; Aktivitäten verborgener Issues fehlen.

interface

uses
  System.SysUtils,
  System.Diagnostics,
  System.JSON,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.FlowMap;

type
  /// <summary>Eine gelesene Seite von /api/activitiesPage.</summary>
  TAtlasYouTrackFlowPage = record
    Changes: TArray<TAtlasFlowChange>;
    /// <summary>Als erledigt gekennzeichnete Zustände der Seite.</summary>
    Resolved: TArray<string>;
    Cursor: string;
    HasMore: Boolean;
  end;

  TAtlasYouTrackFlow = class(TInterfacedObject, IAtlasTrackerFlow)
  public const
    cPageSize = 400;
    cMaxPages = 100;
    cMaxOpen = 2000;
    cOpenPage = 500;
    cActivityFields = 'id,timestamp,target(idReadable,summary,created),field(name,customField(fieldType(id))),' +
      'added(name,isResolved),removed(name,isResolved)';
    cOpenFields = 'idReadable,summary,created,customFields($type,name,value(name,login,fullName))';
    // Für „meine“ genügt der Schlüssel.
    cMineFields = 'idReadable';
    // Suchzusatz für die eigenen Issues (YouTrack-Abfragesprache, nicht übersetzen).
    cMineQuery = ' for: me';
  public
    /// <summary>"project: ATL" (Kürzel mit Leerzeichen in geschweiften Klammern); '' ohne Projekt.</summary>
    class function ProjectQuery(const ATarget: TAtlasTrackerTarget): string; static;
    /// <summary>Adresse einer Seite der Wechsel ab ASince; ACursor '' = erste Seite. '' ohne Server oder Projekt.
    /// </summary>
    class function ActivitiesUrl(const ATarget: TAtlasTrackerTarget; ASince: TDateTime;
      const ACursor: string): string; static;
    /// <summary>Adresse der offenen Issues ab ASkip; AMine: nur mir zugewiesene (nur Kennung).</summary>
    class function OpenUrl(const ATarget: TAtlasTrackerTarget; ASkip: Integer; AMine: Boolean): string; static;
    /// <summary>Ist das Feld der Aktivität AField das Zustandsfeld? Name AStateField, sonst Feldtyp "state[…]",
    /// ohne Typ die üblichen Namen (die Vorgabe "State" passt so auch zu „Zustand“).</summary>
    class function IsStateField(AField: TJSONObject; const AStateField: string): Boolean; static;
    /// <summary>Eine Seite lesen; nur Wechsel des Zustandsfeldes. False bei ungültigem JSON.</summary>
    class function ParsePage(const AJson, AStateField: string; out APage: TAtlasYouTrackFlowPage): Boolean; static;
    /// <summary>Offene Issues lesen; Zustand aus dem Feld AStateField, sonst dem ersten Zustandsfeld. False bei
    /// ungültigem JSON.</summary>
    class function ParseOpen(const AJson, AStateField: string; out AIssues: TArray<TAtlasFlowIssue>): Boolean;
      static;
    /// <summary>Kennungen aus einer Liste von Issues; False bei ungültigem JSON.</summary>
    class function ParseKeys(const AJson: string; out AKeys: TArray<string>): Boolean; static;
    { IAtlasTrackerFlow }
    function LoadFlow(const ARequest: TAtlasFlowRequest; out AData: TAtlasFlowData;
      out AError: TAtlasCiFetchError): Boolean;
  end;

implementation

uses
  System.Math,
  Atlas.Text.Json,
  Atlas.Text.Uris,
  Atlas.Core.Tracker.YouTrackApi,
  Atlas.Core.Tracker.Internals.YouTrackJson;

const
  // Übliche Namen des Zustandsfeldes, wenn weder Name noch Typ es verraten.
  cStateNames: array[0..2] of string = ('State', 'Status', 'Zustand');
  // Feldnamen in YouTrack, keine Oberflächentexte.
  cAssigneeNames: array[0..3] of string = ('Assignee', 'Zuständig', 'Bearbeiter', 'Verantwortlich'); // german-ok

class function TAtlasYouTrackFlow.ProjectQuery(const ATarget: TAtlasTrackerTarget): string;
var
  mProject: string;
begin
  Result := '';
  mProject := Trim(ATarget.Project);
  if mProject = '' then
  begin
    Exit;
  end;
  if Pos(' ', mProject) > 0 then
  begin
    mProject := '{' + mProject + '}';
  end;
  Result := 'project: ' + mProject;
end;

class function TAtlasYouTrackFlow.ActivitiesUrl(const ATarget: TAtlasTrackerTarget; ASince: TDateTime;
  const ACursor: string): string;
begin
  Result := '';
  if (ATarget.Server = '') or (ProjectQuery(ATarget) = '') then
  begin
    Exit;
  end;
  Result := ATarget.Url + '/api/activitiesPage?categories=CustomFieldCategory&issueQuery=' +
    TTextUris.PercentEncode(ProjectQuery(ATarget)) + '&start=' + IntToStr(Max(Int64(0),
    TAtlasYouTrackJson.MsOf(ASince))) + '&fields=' + TTextUris.PercentEncode('hasAfter,afterCursor,activities(' +
    cActivityFields + ')') + '&$top=' + IntToStr(cPageSize);
  if ACursor <> '' then
  begin
    Result := Result + '&cursor=' + TTextUris.PercentEncode(ACursor);
  end;
end;

class function TAtlasYouTrackFlow.OpenUrl(const ATarget: TAtlasTrackerTarget; ASkip: Integer; AMine: Boolean): string;
var
  mQuery, mFields: string;
begin
  Result := '';
  if (ATarget.Server = '') or (ProjectQuery(ATarget) = '') then
  begin
    Exit;
  end;
  mQuery := ProjectQuery(ATarget) + ' #Unresolved';
  mFields := cOpenFields;
  if AMine then
  begin
    mQuery := mQuery + cMineQuery;
    mFields := cMineFields;
  end;
  Result := ATarget.Url + '/api/issues?query=' + TTextUris.PercentEncode(mQuery) + '&fields=' +
    TTextUris.PercentEncode(mFields) + '&$skip=' + IntToStr(Max(0, ASkip)) + '&$top=' + IntToStr(cOpenPage);
end;

{ Lesen }

class function TAtlasYouTrackFlow.IsStateField(AField: TJSONObject; const AStateField: string): Boolean;
var
  mName, mType: string;
  mCustom, mFieldType: TJSONObject;
begin
  Result := False;
  if AField = nil then
  begin
    Exit;
  end;
  mName := Trim(TJsonRead.Text(AField, 'name'));
  if (Trim(AStateField) <> '') and SameText(mName, Trim(AStateField)) then
  begin
    Exit(True);
  end;
  mType := '';
  mCustom := TJsonRead.Obj(AField, 'customField');
  if mCustom <> nil then
  begin
    mFieldType := TJsonRead.Obj(mCustom, 'fieldType');
    if mFieldType <> nil then
    begin
      mType := TJsonRead.Text(mFieldType, 'id');
    end;
  end;
  if mType <> '' then
  begin
    // "state[1]": Zustandsfeld, egal wie es heißt.
    Exit(mType.StartsWith('state', True));
  end;
  Result := TAtlasYouTrackJson.IsOneOf(mName, cStateNames);
end;

/// <summary>Erster Name aus added bzw. removed; nimmt erledigte Zustände in AResolved auf.</summary>
function StateName(AValue: TJSONValue; var AResolved: TArray<string>): string;
var
  mItem: TJSONValue;
  mName: string;
begin
  Result := '';
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AValue) do
  begin
    if not (mItem is TJSONObject) then
    begin
      Continue;
    end;
    mName := Trim(TJsonRead.Text(TJSONObject(mItem), 'name'));
    if (mName <> '') and TJsonRead.Flag(TJSONObject(mItem), 'isResolved') and
      not TAtlasYouTrackJson.IsOneOf(mName, AResolved) then
    begin
      AResolved := AResolved + [mName];
    end;
    if (Result = '') and (mName <> '') then
    begin
      Result := mName;
    end;
  end;
end;

/// <summary>Ein Zustandswechsel aus einer Aktivität; False für andere Felder oder ohne Issue.</summary>
function ChangeOf(AItem: TJSONObject; const AStateField: string; var APage: TAtlasYouTrackFlowPage;
  out AChange: TAtlasFlowChange): Boolean;
var
  mTarget: TJSONObject;
begin
  Result := TAtlasYouTrackFlow.IsStateField(TJsonRead.Obj(AItem, 'field'), AStateField);
  mTarget := TJsonRead.Obj(AItem, 'target');
  Result := Result and (mTarget <> nil) and TAtlasYouTrackJson.ValidKey(Trim(TJsonRead.Text(mTarget, 'idReadable')));
  if not Result then
  begin
    Exit;
  end;
  AChange := TAtlasFlowChange.Create(TJsonRead.Text(AItem, 'id'), Trim(TJsonRead.Text(mTarget, 'idReadable')),
    TAtlasYouTrackJson.TimeOf(AItem, 'timestamp'), StateName(AItem.Values['removed'], APage.Resolved),
    StateName(AItem.Values['added'], APage.Resolved));
  AChange.Title := TAtlasYouTrackJson.Shorten(TJsonRead.Text(mTarget, 'summary'), TAtlasTrackerIssue.cMaxTitle);
  AChange.Created := TAtlasYouTrackJson.TimeOf(mTarget, 'created');
  Result := (AChange.Time > 0) and not SameText(AChange.FromState, AChange.ToState);
end;

class function TAtlasYouTrackFlow.ParsePage(const AJson, AStateField: string;
  out APage: TAtlasYouTrackFlowPage): Boolean;
var
  mValue, mItem: TJSONValue;
  mRoot: TJSONObject;
  mChange: TAtlasFlowChange;
  mList: TJSONArray;
begin
  APage := Default(TAtlasYouTrackFlowPage);
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := mValue is TJSONObject;
    if not Result then
    begin
      Exit;
    end;
    mRoot := TJSONObject(mValue);
    APage.Cursor := TJsonRead.Text(mRoot, 'afterCursor');
    APage.HasMore := TJsonRead.Flag(mRoot, 'hasAfter') and (APage.Cursor <> '');
    mList := TJsonRead.Items(mRoot, 'activities');
    if mList = nil then
    begin
      Exit;
    end;
    for mItem in mList do
    begin
      if (mItem is TJSONObject) and ChangeOf(TJSONObject(mItem), AStateField, APage, mChange) then
      begin
        APage.Changes := APage.Changes + [mChange];
      end;
    end;
  finally
    mValue.Free;
  end;
end;

/// <summary>$type eines Zustandsfeldes am Issue.</summary>
function IsStateType(const AType: string): Boolean;
begin
  Result := SameText(AType, 'StateIssueCustomField') or SameText(AType, 'StateMachineIssueCustomField');
end;

/// <summary>Wert des Zustandsfeldes: zuerst per Name AStateField, sonst am $type bzw. üblichen Namen.</summary>
function StateOf(AFields: TJSONArray; const AStateField: string): string;
var
  mItem: TJSONValue;
  mField: TJSONObject;
  mName, mType, mFallback: string;
begin
  Result := '';
  mFallback := '';
  for mItem in AFields do
  begin
    if not (mItem is TJSONObject) then
    begin
      Continue;
    end;
    mField := TJSONObject(mItem);
    mName := Trim(TJsonRead.Text(mField, 'name'));
    mType := TJsonRead.Text(mField, '$type');
    if (Trim(AStateField) <> '') and SameText(mName, Trim(AStateField)) then
    begin
      Exit(Trim(TAtlasYouTrackJson.ValueText(mField.Values['value'])));
    end;
    if (mFallback = '') and (IsStateType(mType) or ((mType = '') and TAtlasYouTrackJson.IsOneOf(mName,
      cStateNames))) then
    begin
      mFallback := Trim(TAtlasYouTrackJson.ValueText(mField.Values['value']));
    end;
  end;
  Result := mFallback;
end;

/// <summary>Zustand und Zuständig aus customFields eines offenen Issues.</summary>
procedure TakeFields(AFields: TJSONArray; const AStateField: string; var AIssue: TAtlasFlowIssue);
var
  mItem: TJSONValue;
begin
  if AFields = nil then
  begin
    Exit;
  end;
  AIssue.State := StateOf(AFields, AStateField);
  for mItem in AFields do
  begin
    if (mItem is TJSONObject) and TAtlasYouTrackJson.IsOneOf(Trim(TJsonRead.Text(TJSONObject(mItem), 'name')),
      cAssigneeNames) then
    begin
      AIssue.Assignee := TAtlasYouTrackJson.Shorten(TAtlasYouTrackJson.ValueText(TJSONObject(mItem).Values['value']),
        TAtlasTrackerTextLimits.cPerson);
      Exit;
    end;
  end;
end;

class function TAtlasYouTrackFlow.ParseOpen(const AJson, AStateField: string;
  out AIssues: TArray<TAtlasFlowIssue>): Boolean;
var
  mValue, mItem: TJSONValue;
  mObject: TJSONObject;
  mIssue: TAtlasFlowIssue;
begin
  AIssues := nil;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := mValue is TJSONArray;
    if not Result then
    begin
      Exit;
    end;
    for mItem in TJSONArray(mValue) do
    begin
      if not (mItem is TJSONObject) then
      begin
        Continue;
      end;
      mObject := TJSONObject(mItem);
      mIssue := TAtlasFlowIssue.Create(Trim(TJsonRead.Text(mObject, 'idReadable')),
        TAtlasYouTrackJson.Shorten(TJsonRead.Text(mObject, 'summary'), TAtlasTrackerIssue.cMaxTitle), '');
      mIssue.Created := TAtlasYouTrackJson.TimeOf(mObject, 'created');
      TakeFields(TJsonRead.Items(mObject, 'customFields'), AStateField, mIssue);
      if TAtlasYouTrackJson.ValidKey(mIssue.Key) and (mIssue.State <> '') then
      begin
        AIssues := AIssues + [mIssue];
      end;
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasYouTrackFlow.ParseKeys(const AJson: string; out AKeys: TArray<string>): Boolean;
var
  mValue, mItem: TJSONValue;
begin
  AKeys := nil;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := mValue is TJSONArray;
    if Result then
    begin
      for mItem in TJSONArray(mValue) do
      begin
        if mItem is TJSONObject then
        begin
          AKeys := AKeys + [Trim(TJsonRead.Text(TJSONObject(mItem), 'idReadable'))];
        end;
      end;
    end;
  finally
    mValue.Free;
  end;
end;

{ Abruf }

type
  /// <summary>Ein laufender Abruf: Auftrag, Uhr und Ergebnis.</summary>
  TFlowFetch = record
    Request: TAtlasFlowRequest;
    Watch: TStopwatch;
    Data: TAtlasFlowData;
    Error: TAtlasCiFetchError;
    function Get(const AUrl: string; out AText: string): Boolean;
  end;

function TFlowFetch.Get(const AUrl: string; out AText: string): Boolean;
var
  mRest: Integer;
begin
  AText := '';
  mRest := TAtlasYouTrackApi.Rest(Watch, Request.TimeoutMs);
  Result := mRest > 0;
  if not Result then
  begin
    Error := TAtlasCiFetchError.Timeout;
    Exit;
  end;
  Result := TAtlasYouTrackApi.GetText(Request.Transport, AUrl, mRest, AText, Error);
end;

/// <summary>Offene Issues seitenweise; False, wenn schon die erste Seite scheitert.</summary>
function FetchOpen(var AFetch: TFlowFetch): Boolean;
var
  mText: string;
  mIssues: TArray<TAtlasFlowIssue>;
begin
  Result := False;
  repeat
    if not AFetch.Get(TAtlasYouTrackFlow.OpenUrl(AFetch.Request.Target, Length(AFetch.Data.Open), False), mText) or
      not TAtlasYouTrackFlow.ParseOpen(mText, AFetch.Request.StateField, mIssues) then
    begin
      if Result then
      begin
        AFetch.Data.Truncated := True;
      end
      else if AFetch.Error = TAtlasCiFetchError.None then
      begin
        AFetch.Error := TAtlasCiFetchError.Invalid;
      end;
      Exit;
    end;
    Result := True;
    AFetch.Data.Open := AFetch.Data.Open + mIssues;
  until (Length(mIssues) < TAtlasYouTrackFlow.cOpenPage) or (Length(AFetch.Data.Open) >= TAtlasYouTrackFlow.cMaxOpen);
  AFetch.Data.Truncated := AFetch.Data.Truncated or (Length(mIssues) >= TAtlasYouTrackFlow.cOpenPage);
end;

/// <summary>Meine offenen Issues markieren; ohne Antwort bleibt nichts markiert.</summary>
procedure MarkMine(var AFetch: TFlowFetch);
var
  mText, mKey: string;
  mKeys: TArray<string>;
  mIndex: Integer;
begin
  if not AFetch.Get(TAtlasYouTrackFlow.OpenUrl(AFetch.Request.Target, 0, True), mText) or
    not TAtlasYouTrackFlow.ParseKeys(mText, mKeys) then
  begin
    AFetch.Error := TAtlasCiFetchError.None;
    Exit;
  end;
  for mIndex := 0 to High(AFetch.Data.Open) do
  begin
    for mKey in mKeys do
    begin
      if SameText(mKey, AFetch.Data.Open[mIndex].Key) then
      begin
        AFetch.Data.Open[mIndex].Mine := True;
        Break;
      end;
    end;
  end;
end;

procedure AddResolved(var AData: TAtlasFlowData; const ANames: TArray<string>);
var
  mName: string;
begin
  for mName in ANames do
  begin
    if not TAtlasYouTrackJson.IsOneOf(mName, AData.Resolved) then
    begin
      AData.Resolved := AData.Resolved + [mName];
    end;
  end;
end;

/// <summary>Wechsel seitenweise; nach einer Seite zählt ein Fehler nur als unvollständig.</summary>
procedure FetchChanges(var AFetch: TFlowFetch);
var
  mText, mCursor: string;
  mPage: TAtlasYouTrackFlowPage;
  mPages: Integer;
begin
  mCursor := '';
  for mPages := 1 to TAtlasYouTrackFlow.cMaxPages do
  begin
    if not AFetch.Get(TAtlasYouTrackFlow.ActivitiesUrl(AFetch.Request.Target, AFetch.Request.Since, mCursor), mText)
      or not TAtlasYouTrackFlow.ParsePage(mText, AFetch.Request.StateField, mPage) then
    begin
      AFetch.Data.Truncated := True;
      Exit;
    end;
    AFetch.Data.Changes := AFetch.Data.Changes + mPage.Changes;
    AddResolved(AFetch.Data, mPage.Resolved);
    if not mPage.HasMore then
    begin
      Exit;
    end;
    mCursor := mPage.Cursor;
  end;
  AFetch.Data.Truncated := True;
end;

function TAtlasYouTrackFlow.LoadFlow(const ARequest: TAtlasFlowRequest; out AData: TAtlasFlowData;
  out AError: TAtlasCiFetchError): Boolean;
var
  mFetch: TFlowFetch;
begin
  AData := TAtlasFlowData.Empty;
  AError := TAtlasCiFetchError.None;
  Result := False;
  if (ARequest.Transport = nil) or (ActivitiesUrl(ARequest.Target, ARequest.Since, '') = '') then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  mFetch := Default(TFlowFetch);
  mFetch.Request := ARequest;
  mFetch.Watch := TStopwatch.StartNew;
  mFetch.Data.StateField := ARequest.StateField;
  // Offene Issues zuerst: Sie prüfen Zugang und Projekt mit einer kleinen Abfrage.
  if not FetchOpen(mFetch) then
  begin
    AError := mFetch.Error;
    Exit;
  end;
  MarkMine(mFetch);
  FetchChanges(mFetch);
  AData := mFetch.Data;
  Result := True;
end;

end.
