unit Atlas.Core.Tracker.Providers.YouTrack;

// Issue-Tracker YouTrack (#765), Cloud und Server, ohne VCL und Open Tools
// API. Das Netz kommt über IAtlasCiTransport von außen.
// - Anmeldung mit permanentem Token („Authorization: Bearer perm:…“), nur an
//   den eingetragenen Server.
// - Issues: GET <url>/api/issues?query=<Abfrage>&fields=idReadable,
//   numberInProject,summary,customFields(name,value(name,presentation))
//   &$top=<Max>. Die Abfrage ist die Suchsprache der YouTrack-Oberfläche
//   (Vorgabe "for: me #Unresolved"); mit Projektkürzel aus .atlas steht
//   "project: <Kürzel>" davor, damit die Liste dieselben Issues zeigt wie die
//   Suche dort im Projekt.
// - Felder: Zustand (State, Status, Zustand), Priorität (Priority,
//   Priorität) und Sprint bzw. Board (Sprint, Sprints, Board); Werte als
//   Objekt oder Liste mit "name" (bzw. "presentation").
// - Browser: <url>/issue/<Kennung>.
// - Verbindung prüfen (#1260): GET <url>/api/users/me?fields=login.
// - Vorschau (#1264): GET <url>/api/issues/<Kennung>?fields=… mit Feldern,
//   Beschreibung, Tags, Anhängen und Links in einer Abfrage; Kommentare nur
//   mit AComments (Feld comments, sonst nicht abgefragt). Anhänge mit
//   relativer Adresse liegen beim selben Server (signierte Adresse); Links
//   zeigen auf Issues desselben Trackers und öffnen im Fenster.
// - Änderungen (#1271): GET <url>/api/issues?query=<Umfang> updated: <Tag>
//   .. *&fields=idReadable,summary,updated über alle Projekte des Servers
//   (Umfang "for: me", dazu "reporter: me", dazu "has: star"; der Tag liegt
//   einen Tag vor dem letzten Stand, damit die Zeitzone des Servers nichts
//   verschluckt, genau gefiltert wird mit "updated"), dann je Treffer
//   GET <url>/api/issues/<Kennung>/activities?categories=CommentsCategory,
//   CustomFieldCategory&start=<ms> ab dem letzten Stand: neue Kommentare,
//   Zuständig und Zustand.

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract;

type
  TAtlasYouTrackTracker = class(TInterfacedObject, IAtlasTrackerProvider)
  public const
    ProviderName = 'youtrack';
    Query = 'for: me #Unresolved';
    Fields = 'idReadable,numberInProject,summary,customFields(name,value(name,presentation))';
    /// <summary>Felder der Vorschau (#1264) ohne Kommentare.</summary>
    DetailFields = 'idReadable,numberInProject,summary,description,created,updated,' +
      'customFields(name,value(name,presentation,login,fullName)),tags(name),' +
      'attachments(name,size,url,mimeType,removed),' +
      'links(direction,linkType(name,sourceToTarget,targetToSource),issues(idReadable,summary))';
    CommentFields = 'comments(text,created,deleted,author(login,fullName))';
    /// <summary>Felder der Änderungsabfrage (#1271).</summary>
    ChangeIssueFields = 'idReadable,summary,updated';
    ActivityFields = 'timestamp,author(login,fullName),category(id),field(name),' +
      'added(id,name,login,fullName,text,presentation)';
    ActivityCategories = 'CommentsCategory,CustomFieldCategory';
    /// <summary>Höchstens so viele geänderte Issues je Abfrage bekommen ihre Einzelheiten.</summary>
    MaxChangedIssues = 20;
  public
    class function IssuesUrl(const ATarget: TAtlasTrackerTarget; AMax: Integer): string; static;
    /// <summary>Abfrage, wie sie an YouTrack geht (mit "project: …").</summary>
    class function FullQuery(const ATarget: TAtlasTrackerTarget): string; static;
    /// <summary>Antwort von /api/issues; False bei ungültigem JSON.</summary>
    class function ParseIssues(const AJson: string; AMax: Integer;
      out AIssues: TArray<TAtlasTrackerIssue>): Boolean; static;
    /// <summary>Fehler zu einem HTTP-Status außer 200.</summary>
    class function ErrorOfStatus(AStatus: Integer): TAtlasCiFetchError; static;
    /// <summary>Adresse der Vorschau eines Issues; '' bei ungültiger Kennung oder ohne Server.</summary>
    class function DetailsUrl(const ATarget: TAtlasTrackerTarget; const AKey: string; AComments: Boolean): string;
      static;
    /// <summary>Antwort von /api/issues/<Kennung>; False bei ungültigem JSON bzw. ohne Kennung.</summary>
    class function ParseDetails(const AJson: string; const ATarget: TAtlasTrackerTarget; AComments: Boolean;
      out ADetails: TAtlasTrackerDetails): Boolean; static;
    /// <summary>Umfang als Suchausdruck (#1271), z. B. "(for: me or reporter: me)".</summary>
    class function ScopeQuery(AScope: TAtlasTrackerNotifyScope): string; static;
    /// <summary>Adresse der geänderten Issues ab ASince (UTC) im Umfang AScope; '' ohne Server.</summary>
    class function ChangedIssuesUrl(const ATarget: TAtlasTrackerTarget; ASince: TDateTime;
      AScope: TAtlasTrackerNotifyScope): string; static;
    /// <summary>Antwort der geänderten Issues: Kennung, Titel und Zeit, nur nach ASince. False bei ungültigem JSON.
    /// </summary>
    class function ParseChangedIssues(const AJson: string; ASince: TDateTime;
      out AIssues: TArray<TAtlasTrackerChange>): Boolean; static;
    /// <summary>Adresse der Aktivitäten von AKey nach ASince; '' bei ungültiger Kennung oder ohne Server.</summary>
    class function ActivitiesUrl(const ATarget: TAtlasTrackerTarget; const AKey: string; ASince: TDateTime): string;
      static;
    /// <summary>Antwort von /activities als Änderungen an AKey (ATitle): Kommentare, Zuständig (AMe: an mich?) und
    /// Zustand nach ASince; andere Felder entfallen. False bei ungültigem JSON.</summary>
    class function ParseActivities(const AJson, AKey, ATitle, AMe: string; ASince: TDateTime;
      out AChanges: TArray<TAtlasTrackerChange>): Boolean; static;
    { IAtlasTrackerProvider }
    function Name: string;
    function Caption: string;
    function DefaultQuery: string;
    function ApiServer(const ATarget: TAtlasTrackerTarget): string;
    function Fetch(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; ATimeoutMs, AMax: Integer;
      out AIssues: TArray<TAtlasTrackerIssue>; out AError: TAtlasCiFetchError): Boolean;
    function IssuePage(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
    function PullRequestPage(const ATarget: TAtlasTrackerTarget; ANumber: Integer): string;
    function ProbeUrl(const ATarget: TAtlasTrackerTarget): string;
    function Details(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      AComments: Boolean; ATimeoutMs: Integer; out ADetails: TAtlasTrackerDetails;
      out AError: TAtlasCiFetchError): Boolean;
    function Changes(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; ATimeoutMs: Integer;
      var APoll: TAtlasTrackerPoll; out AChanges: TArray<TAtlasTrackerChange>; out AError: TAtlasCiFetchError): Boolean;
  end;

implementation

uses
  System.Classes,
  System.DateUtils,
  System.Diagnostics,
  System.Generics.Collections,
  System.JSON,
  System.StrUtils,
  Atlas.Text.Uris;

function TextOf(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  Value := AObject.Values[AName];
  if Value is TJSONString then
    Result := TJSONString(Value).Value;
end;

function Shorten(const AText: string; AMax: Integer): string;
begin
  Result := Trim(StringReplace(StringReplace(AText, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]));
  if Length(Result) > AMax then
    Result := Copy(Result, 1, AMax - 1) + '…';
end;

/// <summary>Name eines Werts: "name", sonst "presentation"; bei einer Liste die Namen mit ", ".</summary>
function ValueText(AValue: TJSONValue): string;
var
  Item: TJSONValue;
  Part: string;
begin
  Result := '';
  if AValue is TJSONObject then
  begin
    Result := TextOf(TJSONObject(AValue), 'name');
    if Result = '' then
      Result := TextOf(TJSONObject(AValue), 'presentation');
    // Benutzer (Zuständig, #1264).
    if Result = '' then
      Result := TextOf(TJSONObject(AValue), 'fullName');
    if Result = '' then
      Result := TextOf(TJSONObject(AValue), 'login');
  end
  else if AValue is TJSONString then
    Result := TJSONString(AValue).Value
  else if AValue is TJSONArray then
    for Item in TJSONArray(AValue) do
    begin
      Part := ValueText(Item);
      if Part = '' then
        Continue;
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + Part;
    end;
  Result := Shorten(Result, 60);
end;

function IsOneOf(const AName: string; const ANames: array of string): Boolean;
var
  Name: string;
begin
  Result := False;
  for Name in ANames do
    if SameText(AName, Name) then
      Exit(True);
end;

{ TAtlasYouTrackTracker }

class function TAtlasYouTrackTracker.FullQuery(const ATarget: TAtlasTrackerTarget): string;
var
  Project: string;
begin
  Result := ATarget.Query;
  if Result = '' then
    Result := Query;
  Project := ATarget.Project;
  if Project = '' then
    Exit;
  // Kürzel mit Leerzeichen oder Sonderzeichen in geschweiften Klammern, wie in der Oberfläche.
  if Pos(' ', Project) > 0 then
    Project := '{' + Project + '}';
  Result := 'project: ' + Project + ' ' + Result;
end;

class function TAtlasYouTrackTracker.IssuesUrl(const ATarget: TAtlasTrackerTarget; AMax: Integer): string;
var
  Limit: Integer;
begin
  Result := '';
  if ATarget.Server = '' then
    Exit;
  Limit := AMax;
  if Limit < 1 then
    Limit := 1;
  if Limit > 100 then
    Limit := 100;
  Result := ATarget.Url + '/api/issues?query=' + TTextUris.PercentEncode(FullQuery(ATarget)) + '&fields=' +
    TTextUris.PercentEncode(Fields) + '&$top=' + IntToStr(Limit);
end;

class function TAtlasYouTrackTracker.ParseIssues(const AJson: string; AMax: Integer;
  out AIssues: TArray<TAtlasTrackerIssue>): Boolean;
var
  Value, Item, Custom, Field: TJSONValue;
  Issue: TAtlasTrackerIssue;
  FieldName, Text: string;
  Number: Int64;
  NumberValue: TJSONValue;
begin
  AIssues := nil;
  Result := False;
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Value is TJSONArray) then
      Exit;
    Result := True;
    for Item in TJSONArray(Value) do
    begin
      if Length(AIssues) >= AMax then
        Break;
      if not (Item is TJSONObject) then
        Continue;
      Issue := TAtlasTrackerIssue.Empty;
      Issue.Key := Trim(TextOf(TJSONObject(Item), 'idReadable'));
      if Issue.Key = '' then
        Continue;
      NumberValue := TJSONObject(Item).Values['numberInProject'];
      if (NumberValue is TJSONNumber) and TryStrToInt64(TJSONNumber(NumberValue).Value, Number) and (Number > 0) and
        (Number <= MaxInt) then
        Issue.Number := Integer(Number);
      Issue.Title := Shorten(TextOf(TJSONObject(Item), 'summary'), TAtlasTrackerIssue.MaxTitle);
      Custom := TJSONObject(Item).Values['customFields'];
      if Custom is TJSONArray then
        for Field in TJSONArray(Custom) do
        begin
          if not (Field is TJSONObject) then
            Continue;
          FieldName := Trim(TextOf(TJSONObject(Field), 'name'));
          Text := ValueText(TJSONObject(Field).Values['value']);
          if Text = '' then
            Continue;
          if IsOneOf(FieldName, ['State', 'Status', 'Zustand']) and (Issue.State = '') then
            Issue.State := Text
          else if IsOneOf(FieldName, ['Priority', 'Priorität']) and (Issue.Priority = '') then
            Issue.Priority := Text
          else if IsOneOf(FieldName, ['Sprint', 'Sprints', 'Board']) and (Issue.Sprint = '') then
            Issue.Sprint := Text;
        end;
      AIssues := AIssues + [Issue];
    end;
  finally
    Value.Free;
  end;
end;

class function TAtlasYouTrackTracker.ErrorOfStatus(AStatus: Integer): TAtlasCiFetchError;
begin
  case AStatus of
    401, 403:
      Result := TAtlasCiFetchError.Unauthorized;
    404:
      Result := TAtlasCiFetchError.NotFound;
    400:
      Result := TAtlasCiFetchError.Invalid;
  else
    Result := TAtlasCiFetchError.Server;
  end;
end;

function ValidKey(const AKey: string): Boolean;
var
  mIndex: Integer;
begin
  Result := AKey <> '';
  for mIndex := 1 to Length(AKey) do
    if not CharInSet(AKey[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '-', '_']) then
      Exit(False);
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

function BoolOf(AObject: TJSONObject; const AName: string): Boolean;
var
  mValue: TJSONValue;
begin
  mValue := AObject.Values[AName];
  Result := (mValue is TJSONBool) and TJSONBool(mValue).AsBoolean;
end;

function Limited(const AText: string): string;
begin
  Result := Copy(AText, 1, TAtlasTrackerDetails.MaxText);
end;

class function TAtlasYouTrackTracker.DetailsUrl(const ATarget: TAtlasTrackerTarget; const AKey: string;
  AComments: Boolean): string;
var
  mFields: string;
begin
  Result := '';
  if (ATarget.Server = '') or not ValidKey(Trim(AKey)) then
    Exit;
  mFields := DetailFields;
  if AComments then
    mFields := mFields + ',' + CommentFields;
  Result := ATarget.Url + '/api/issues/' + Trim(AKey) + '?fields=' + TTextUris.PercentEncode(mFields);
end;

class function TAtlasYouTrackTracker.ParseDetails(const AJson: string; const ATarget: TAtlasTrackerTarget;
  AComments: Boolean; out ADetails: TAtlasTrackerDetails): Boolean;
var
  mValue, mItem, mField, mIssue, mSize: TJSONValue;
  mRoot, mObject, mType: TJSONObject;
  mName, mText, mUrl, mDirection, mRelation, mServer: string;
  mNumber: Int64;
  mComment: TAtlasTrackerComment;
  mAttachment: TAtlasTrackerAttachment;
  mLink: TAtlasTrackerLink;
begin
  ADetails := TAtlasTrackerDetails.Empty;
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) then
      Exit;
    mRoot := TJSONObject(mValue);
    ADetails.Key := Trim(TextOf(mRoot, 'idReadable'));
    if ADetails.Key = '' then
      Exit;
    mItem := mRoot.Values['numberInProject'];
    if (mItem is TJSONNumber) and TryStrToInt64(TJSONNumber(mItem).Value, mNumber) and (mNumber > 0) and
      (mNumber <= MaxInt) then
      ADetails.Number := Integer(mNumber);
    ADetails.Title := Shorten(TextOf(mRoot, 'summary'), 500);
    ADetails.Description := Limited(TextOf(mRoot, 'description'));
    ADetails.Created := TimeOf(mRoot, 'created');
    ADetails.Updated := TimeOf(mRoot, 'updated');
    mServer := ATarget.Server;
    mItem := mRoot.Values['customFields'];
    if mItem is TJSONArray then
      for mField in TJSONArray(mItem) do
      begin
        if not (mField is TJSONObject) then
          Continue;
        mName := Trim(TextOf(TJSONObject(mField), 'name'));
        mText := ValueText(TJSONObject(mField).Values['value']);
        if mText = '' then
          Continue;
        if IsOneOf(mName, ['State', 'Status', 'Zustand']) and (ADetails.State = '') then
          ADetails.State := mText
        else if IsOneOf(mName, ['Priority', 'Priorität']) and (ADetails.Priority = '') then
          ADetails.Priority := mText
        else if IsOneOf(mName, ['Type', 'Typ']) and (ADetails.Kind = '') then
          ADetails.Kind := mText
        else if IsOneOf(mName, ['Assignee', 'Zuständig', 'Bearbeiter', 'Verantwortlich']) and
          (ADetails.Assignee = '') then
          ADetails.Assignee := mText
        else if IsOneOf(mName, ['Sprint', 'Sprints', 'Board', 'Fix versions', 'Fix version', 'Meilenstein']) and
          (ADetails.Sprint = '') then
          ADetails.Sprint := mText;
      end;
    mItem := mRoot.Values['tags'];
    if mItem is TJSONArray then
      for mField in TJSONArray(mItem) do
        if mField is TJSONObject then
        begin
          mText := Shorten(TextOf(TJSONObject(mField), 'name'), 60);
          if mText <> '' then
            ADetails.Labels := ADetails.Labels + [mText];
        end;
    mItem := mRoot.Values['attachments'];
    if mItem is TJSONArray then
      for mField in TJSONArray(mItem) do
      begin
        if not (mField is TJSONObject) or BoolOf(TJSONObject(mField), 'removed') then
          Continue;
        if Length(ADetails.Attachments) >= TAtlasTrackerDetails.MaxAttachments then
          Break;
        mObject := TJSONObject(mField);
        mAttachment := Default(TAtlasTrackerAttachment);
        mAttachment.Name := Shorten(TextOf(mObject, 'name'), 200);
        mAttachment.MimeType := TextOf(mObject, 'mimeType');
        mAttachment.Size := -1;
        mSize := mObject.Values['size'];
        if (mSize is TJSONNumber) and TryStrToInt64(TJSONNumber(mSize).Value, mNumber) and (mNumber >= 0) then
          mAttachment.Size := mNumber;
        // Signierte Adresse relativ zum Server ("/youtrack/api/files/…?sign=…").
        mUrl := TextOf(mObject, 'url');
        if StartsStr('/', mUrl) and (mServer <> '') then
          mUrl := mServer + mUrl;
        mAttachment.Url := mUrl;
        mAttachment.External := not SameText(TAtlasTrackerTarget.Create('', mUrl, '', '').Server, mServer);
        if (mAttachment.Name <> '') and (mUrl <> '') then
          ADetails.Attachments := ADetails.Attachments + [mAttachment];
      end;
    mItem := mRoot.Values['links'];
    if mItem is TJSONArray then
      for mField in TJSONArray(mItem) do
      begin
        if not (mField is TJSONObject) then
          Continue;
        mObject := TJSONObject(mField);
        mDirection := UpperCase(TextOf(mObject, 'direction'));
        mRelation := '';
        if mObject.Values['linkType'] is TJSONObject then
        begin
          mType := TJSONObject(mObject.Values['linkType']);
          if mDirection = 'INWARD' then
            mRelation := TextOf(mType, 'targetToSource')
          else
            mRelation := TextOf(mType, 'sourceToTarget');
          if mRelation = '' then
            mRelation := TextOf(mType, 'name');
        end;
        if not (mObject.Values['issues'] is TJSONArray) then
          Continue;
        for mIssue in TJSONArray(mObject.Values['issues']) do
        begin
          if not (mIssue is TJSONObject) or (Length(ADetails.Links) >= TAtlasTrackerDetails.MaxLinks) then
            Continue;
          mLink := Default(TAtlasTrackerLink);
          mLink.Key := Trim(TextOf(TJSONObject(mIssue), 'idReadable'));
          mLink.Title := Shorten(TextOf(TJSONObject(mIssue), 'summary'), 200);
          mLink.Relation := Shorten(mRelation, 60);
          // Gleicher Tracker: öffnet im Fenster.
          mLink.Local := ValidKey(mLink.Key);
          if mLink.Key <> '' then
            ADetails.Links := ADetails.Links + [mLink];
        end;
      end;
    ADetails.CommentsLoaded := AComments;
    mItem := mRoot.Values['comments'];
    if AComments and (mItem is TJSONArray) then
      for mField in TJSONArray(mItem) do
      begin
        if not (mField is TJSONObject) or BoolOf(TJSONObject(mField), 'deleted') then
          Continue;
        mObject := TJSONObject(mField);
        mComment := Default(TAtlasTrackerComment);
        mComment.Text := Limited(TextOf(mObject, 'text'));
        mComment.Created := TimeOf(mObject, 'created');
        if mObject.Values['author'] is TJSONObject then
          mComment.Author := Shorten(ValueText(mObject.Values['author']), 80);
        ADetails.Comments := ADetails.Comments + [mComment];
      end;
    // Nur die neuesten MaxComments.
    if Length(ADetails.Comments) > TAtlasTrackerDetails.MaxComments then
      ADetails.Comments := Copy(ADetails.Comments, Length(ADetails.Comments) - TAtlasTrackerDetails.MaxComments,
        TAtlasTrackerDetails.MaxComments);
    Result := True;
  finally
    mValue.Free;
  end;
end;

function TAtlasYouTrackTracker.Name: string;
begin
  Result := ProviderName;
end;

function TAtlasYouTrackTracker.Caption: string;
begin
  Result := 'YouTrack';
end;

function TAtlasYouTrackTracker.DefaultQuery: string;
begin
  Result := Query;
end;

function TAtlasYouTrackTracker.ApiServer(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := ATarget.Server;
end;

function TAtlasYouTrackTracker.Fetch(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  ATimeoutMs, AMax: Integer; out AIssues: TArray<TAtlasTrackerIssue>; out AError: TAtlasCiFetchError): Boolean;
var
  Status: Integer;
  Text: string;
begin
  AIssues := nil;
  AError := TAtlasCiFetchError.None;
  Result := False;
  if not ATarget.Configured or (ATransport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  if not ATransport.Get(IssuesUrl(ATarget, AMax), ATimeoutMs, Status, Text, AError) then
    Exit;
  if Status <> 200 then
  begin
    AError := ErrorOfStatus(Status);
    Exit;
  end;
  if not ParseIssues(Text, AMax, AIssues) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  Result := True;
end;

function TAtlasYouTrackTracker.IssuePage(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
var
  Key: string;
  Index: Integer;
begin
  Result := '';
  Key := Trim(AKey);
  if (ATarget.Server = '') or (Key = '') then
    Exit;
  for Index := 1 to Length(Key) do
    if not CharInSet(Key[Index], ['A'..'Z', 'a'..'z', '0'..'9', '-', '_']) then
      Exit;
  Result := ATarget.Url + '/issue/' + Key;
end;

function TAtlasYouTrackTracker.PullRequestPage(const ATarget: TAtlasTrackerTarget; ANumber: Integer): string;
begin
  Result := '';
end;

function TAtlasYouTrackTracker.ProbeUrl(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := '';
  if ATarget.Server <> '' then
    Result := ATarget.Url + '/api/users/me?fields=login';
end;

function TAtlasYouTrackTracker.Details(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; AComments: Boolean; ATimeoutMs: Integer; out ADetails: TAtlasTrackerDetails;
  out AError: TAtlasCiFetchError): Boolean;
var
  mStatus: Integer;
  mText, mUrl: string;
begin
  ADetails := TAtlasTrackerDetails.Empty;
  AError := TAtlasCiFetchError.None;
  Result := False;
  mUrl := DetailsUrl(ATarget, AKey, AComments);
  if (mUrl = '') or (ATransport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  if not ATransport.Get(mUrl, ATimeoutMs, mStatus, mText, AError) then
    Exit;
  if mStatus <> 200 then
  begin
    AError := ErrorOfStatus(mStatus);
    Exit;
  end;
  if not ParseDetails(mText, ATarget, AComments, ADetails) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  ADetails.Page := IssuePage(ATarget, ADetails.Key);
  Result := True;
end;

/// <summary>Millisekunden seit 1970 zu einer UTC-Zeit.</summary>
function MsOf(ATime: TDateTime): Int64;
begin
  Result := Round((ATime - UnixDateDelta) * MSecsPerDay);
end;

class function TAtlasYouTrackTracker.ScopeQuery(AScope: TAtlasTrackerNotifyScope): string;
begin
  case AScope of
    TAtlasTrackerNotifyScope.Assigned:
      Result := 'for: me';
    TAtlasTrackerNotifyScope.Watched:
      Result := '(for: me or reporter: me or has: star)';
  else
    Result := '(for: me or reporter: me)';
  end;
end;

class function TAtlasYouTrackTracker.ChangedIssuesUrl(const ATarget: TAtlasTrackerTarget; ASince: TDateTime;
  AScope: TAtlasTrackerNotifyScope): string;
var
  mQuery: string;
begin
  Result := '';
  if ATarget.Server = '' then
    Exit;
  // Einen Tag früher: Der Server wertet den Tag in seiner Zeitzone; genau gefiltert wird mit "updated".
  mQuery := ScopeQuery(AScope) + ' updated: ' + FormatDateTime('yyyy"-"mm"-"dd', ASince - 1) + ' .. *';
  Result := ATarget.Url + '/api/issues?query=' + TTextUris.PercentEncode(mQuery) + '&fields=' +
    TTextUris.PercentEncode(ChangeIssueFields) + '&$top=' + IntToStr(MaxChangedIssues * 2);
end;

class function TAtlasYouTrackTracker.ParseChangedIssues(const AJson: string; ASince: TDateTime;
  out AIssues: TArray<TAtlasTrackerChange>): Boolean;
var
  mValue, mItem: TJSONValue;
  mIssue: TAtlasTrackerChange;
begin
  AIssues := nil;
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONArray) then
      Exit;
    Result := True;
    for mItem in TJSONArray(mValue) do
    begin
      if not (mItem is TJSONObject) then
        Continue;
      mIssue := TAtlasTrackerChange.Create(Trim(TextOf(TJSONObject(mItem), 'idReadable')),
        TAtlasTrackerChangeKind.Other, '', TimeOf(TJSONObject(mItem), 'updated'));
      mIssue.Title := Shorten(TextOf(TJSONObject(mItem), 'summary'), TAtlasTrackerIssue.MaxTitle);
      if ValidKey(mIssue.Key) and (mIssue.Time > ASince) then
        AIssues := AIssues + [mIssue];
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasYouTrackTracker.ActivitiesUrl(const ATarget: TAtlasTrackerTarget; const AKey: string;
  ASince: TDateTime): string;
begin
  Result := '';
  if (ATarget.Server = '') or not ValidKey(Trim(AKey)) then
    Exit;
  Result := ATarget.Url + '/api/issues/' + Trim(AKey) + '/activities?categories=' + ActivityCategories +
    '&start=' + IntToStr(MsOf(ASince) + 1) + '&fields=' + TTextUris.PercentEncode(ActivityFields) + '&$top=100';
end;

class function TAtlasYouTrackTracker.ParseActivities(const AJson, AKey, ATitle, AMe: string; ASince: TDateTime;
  out AChanges: TArray<TAtlasTrackerChange>): Boolean;
var
  mValue, mItem, mAdded, mEntry: TJSONValue;
  mObject, mAuthor: TJSONObject;
  mCategory, mField, mLogin: string;
  mChange: TAtlasTrackerChange;
  mKind: TAtlasTrackerChangeKind;
begin
  AChanges := nil;
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONArray) then
      Exit;
    Result := True;
    for mItem in TJSONArray(mValue) do
    begin
      if not (mItem is TJSONObject) then
        Continue;
      mObject := TJSONObject(mItem);
      mAdded := mObject.Values['added'];
      // Entfernte Kommentare und geleerte Felder melden nichts.
      if not (mAdded is TJSONArray) or (TJSONArray(mAdded).Count = 0) then
        Continue;
      mCategory := '';
      if mObject.Values['category'] is TJSONObject then
        mCategory := TextOf(TJSONObject(mObject.Values['category']), 'id');
      mField := '';
      if mObject.Values['field'] is TJSONObject then
        mField := Trim(TextOf(TJSONObject(mObject.Values['field']), 'name'));
      if SameText(mCategory, 'CommentsCategory') then
        mKind := TAtlasTrackerChangeKind.Comment
      else if IsOneOf(mField, ['Assignee', 'Zuständig', 'Bearbeiter', 'Verantwortlich']) then
        mKind := TAtlasTrackerChangeKind.Assigned
      else if IsOneOf(mField, ['State', 'Status', 'Zustand']) then
        mKind := TAtlasTrackerChangeKind.State
      else
        Continue;
      mChange := TAtlasTrackerChange.Create(AKey, mKind, '', TimeOf(mObject, 'timestamp'));
      if mChange.Time <= ASince then
        Continue;
      mChange.Title := ATitle;
      if mObject.Values['author'] is TJSONObject then
      begin
        mAuthor := TJSONObject(mObject.Values['author']);
        mChange.Author := Trim(TextOf(mAuthor, 'login'));
        mChange.AuthorName := Shorten(TextOf(mAuthor, 'fullName'), 80);
      end;
      if mKind <> TAtlasTrackerChangeKind.Comment then
      begin
        mChange.Value := ValueText(mAdded);
        if mKind = TAtlasTrackerChangeKind.Assigned then
          for mEntry in TJSONArray(mAdded) do
            if mEntry is TJSONObject then
            begin
              mLogin := TextOf(TJSONObject(mEntry), 'login');
              if (AMe <> '') and SameText(mLogin, AMe) then
                mChange.ToMe := True;
            end;
      end;
      AChanges := AChanges + [mChange];
    end;
  finally
    mValue.Free;
  end;
end;

function TAtlasYouTrackTracker.Changes(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  ATimeoutMs: Integer; var APoll: TAtlasTrackerPoll; out AChanges: TArray<TAtlasTrackerChange>;
  out AError: TAtlasCiFetchError): Boolean;
var
  mWatch: TStopwatch;
  mStatus, mIndex, mRest: Integer;
  mText: string;
  mIssues, mFound: TArray<TAtlasTrackerChange>;
  mIgnored: TAtlasCiFetchError;
begin
  AChanges := nil;
  AError := TAtlasCiFetchError.None;
  Result := False;
  if (ATarget.Server = '') or (ATransport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  mWatch := TStopwatch.StartNew;
  if not ATransport.Get(ChangedIssuesUrl(ATarget, APoll.Since, APoll.Scope), ATimeoutMs, mStatus, mText, AError) then
    Exit;
  if mStatus <> 200 then
  begin
    AError := ErrorOfStatus(mStatus);
    Exit;
  end;
  if not ParseChangedIssues(mText, APoll.Since, mIssues) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  Result := True;
  for mIndex := 0 to High(mIssues) do
  begin
    if mIssues[mIndex].Time > APoll.Latest then
      APoll.Latest := mIssues[mIndex].Time;
    if mIndex >= MaxChangedIssues then
      Continue;
    mRest := ATimeoutMs - Integer(mWatch.ElapsedMilliseconds);
    // Zeit aufgebraucht: Das Issue meldet sich ohne Einzelheiten (die Zeit des Issues bleibt der Stand).
    if (mRest <= 0) or not ATransport.Get(ActivitiesUrl(ATarget, mIssues[mIndex].Key, APoll.Since), mRest, mStatus,
      mText, mIgnored) or (mStatus <> 200) or not ParseActivities(mText, mIssues[mIndex].Key, mIssues[mIndex].Title,
      APoll.Me, APoll.Since, mFound) then
      mFound := [mIssues[mIndex]];
    AChanges := AChanges + mFound;
  end;
  // Auch eine Aktivität, die der Server später stempelt als das Issue, kommt nicht noch einmal.
  for mIndex := 0 to High(AChanges) do
    if AChanges[mIndex].Time > APoll.Latest then
      APoll.Latest := AChanges[mIndex].Time;
end;

end.
