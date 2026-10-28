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
// - Zustand und Kommentar (#1266, IAtlasTrackerWriter): Zustand und
//   Zuständigkeit über die Befehlsschnittstelle POST <url>/api/commands
//   ({"query": "<Zustandsfeld> <Wert> <Benutzerfeld> me", "issues":
//   [{"idReadable": …}], "comment": …}); Namen und Werte mit Leerzeichen in
//   geschweiften Klammern, wie in der Oberfläche. Kommentar allein: POST
//   <url>/api/issues/<Kennung>/comments. Werte für die Klapplisten aus
//   /api/admin/projects (Felder des Projekts mit ihren Werten, ohne Projekt
//   aus /api/admin/customFieldSettings/customFields) und /api/users.
// - Zeit buchen (#1267, IAtlasTrackerTimeWriter): POST
//   <url>/api/issues/<Kennung>/timeTracking/workItems mit
//   {"duration": {"presentation": "1h 25m"}, "date": <ms>, "type": {"name":
//   …}, "text": …}; Zeiterfassung und Arbeitstypen aus
//   /api/admin/projects/<Kürzel>/timeTrackingSettings, ohne Leserecht die
//   allgemeinen Arbeitstypen (/api/admin/timeTrackingSettings/workItemTypes).

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract;

type
  TAtlasYouTrackTracker = class(TInterfacedObject, IAtlasTrackerProvider, IAtlasTrackerWriter,
    IAtlasTrackerTimeWriter)
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
    /// <summary>Felder der Projekte für die Klapplisten (#1266).</summary>
    ProjectFields = 'shortName,customFields(field(name,fieldType(id)),bundle(values(name,archived)))';
    /// <summary>Höchstens so viele Werte je Klappliste.</summary>
    MaxValues = 200;
    /// <summary>Felder der Zeiterfassung eines Projekts (#1267).</summary>
    TimeSettingsFields = 'enabled,workItemTypes(name)';
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
    /// <summary>Name bzw. Wert für einen Befehl: mit Leerzeichen oder Klammern in geschweiften Klammern.</summary>
    class function CommandWord(const AText: string): string; static;
    /// <summary>Befehl zu AChange ohne Kommentar ("State {In Arbeit} Assignee me"); '' = nur Kommentar.</summary>
    class function CommandQuery(const AChange: TAtlasTrackerChange): string; static;
    /// <summary>Inhalt für /api/commands.</summary>
    class function CommandJson(const AKey, AQuery, AComment: string): string; static;
    /// <summary>Inhalt für …/comments: {"text": AText}.</summary>
    class function CommentJson(const AText: string): string; static;
    /// <summary>Fehlertext aus einer Antwort ("error_description", sonst "error"); '' ohne.</summary>
    class function ErrorMessage(const AJson: string): string; static;
    /// <summary>Werte aus /api/admin/projects (AProject = Kürzel; '' = alle Projekte) bzw. ohne Projekt aus
    /// /api/admin/customFieldSettings/customFields; False bei ungültigem JSON.</summary>
    class function ParseFieldValues(const AJson, AProject: string; AKind: TAtlasTrackerValueKind; const AField: string;
      out AValues: TArray<string>): Boolean; static;
    /// <summary>Anmeldenamen aus /api/users; False bei ungültigem JSON.</summary>
    class function ParseUsers(const AJson: string; out AValues: TArray<string>): Boolean; static;
    /// <summary>Projektkürzel aus der Kennung ("ATL-123" → "ATL"); '' ohne Bindestrich.</summary>
    class function ProjectOfKey(const AKey: string): string; static;
    /// <summary>Körper für timeTracking/workItems (#1267); "date" = Mittag des Tages in UTC (Millisekunden), damit
    /// der Tag in jeder Zeitzone stimmt.</summary>
    class function WorkItemJson(const AItem: TAtlasTrackerWorkItem): string; static;
    /// <summary>{"enabled": …, "workItemTypes": [{"name": …}]} bzw. eine Liste [{"name": …}] (AList).</summary>
    class function ParseTimeSettings(const AJson: string; AList: Boolean;
      out ASettings: TAtlasTrackerTimeSettings): Boolean; static;
    /// <summary>Die Buchung scheiterte, weil die Zeiterfassung im Projekt aus ist (400 mit Hinweis darauf).
    /// </summary>
    class function TimeTrackingOff(const AResult: TAtlasTrackerWriteResult): Boolean; static;
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
    { IAtlasTrackerWriter }
    function Apply(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      const AChange: TAtlasTrackerChange; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
    function Values(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      AKind: TAtlasTrackerValueKind; const AField: string; ATimeoutMs: Integer;
      out AValues: TArray<string>): TAtlasTrackerWriteResult;
    { IAtlasTrackerTimeWriter }
    function TimeSettings(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      ATimeoutMs: Integer; out ASettings: TAtlasTrackerTimeSettings): TAtlasTrackerWriteResult;
    function BookTime(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      const AItem: TAtlasTrackerWorkItem; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
    function IsTrackingOff(const AResult: TAtlasTrackerWriteResult): Boolean;
  end;

implementation

uses
  System.Classes,
  System.DateUtils,
  System.Generics.Collections,
  System.JSON,
  System.StrUtils,
  Atlas.Core.Tracker.TimeLog,
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

{ IAtlasTrackerWriter (#1266) }

class function TAtlasYouTrackTracker.CommandWord(const AText: string): string;
var
  mIndex: Integer;
  mPlain: Boolean;
begin
  Result := Trim(AText);
  mPlain := Result <> '';
  for mIndex := 1 to Length(Result) do
    if (Ord(Result[mIndex]) < 128) and
      not CharInSet(Result[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', '@']) then
      mPlain := False;
  // Umlaute stehen in der Oberfläche ohne Klammern; Leerzeichen und Satzzeichen brauchen sie.
  if not mPlain then
    Result := '{' + StringReplace(StringReplace(Result, '{', '', [rfReplaceAll]), '}', '', [rfReplaceAll]) + '}';
end;

class function TAtlasYouTrackTracker.CommandQuery(const AChange: TAtlasTrackerChange): string;
var
  mField: string;
begin
  Result := '';
  if Trim(AChange.State) <> '' then
  begin
    mField := Trim(AChange.StateField);
    if mField = '' then
      mField := 'State';
    Result := CommandWord(mField) + ' ' + CommandWord(AChange.State);
  end;
  if AChange.Assign = TAtlasTrackerAssign.Keep then
    Exit;
  if (AChange.Assign = TAtlasTrackerAssign.User) and (Trim(AChange.Assignee) = '') then
    Exit;
  mField := Trim(AChange.AssigneeField);
  if mField = '' then
    mField := 'Assignee';
  if Result <> '' then
    Result := Result + ' ';
  if AChange.Assign = TAtlasTrackerAssign.Me then
    Result := Result + CommandWord(mField) + ' me'
  else
    Result := Result + CommandWord(mField) + ' ' + CommandWord(AChange.Assignee);
end;

class function TAtlasYouTrackTracker.CommandJson(const AKey, AQuery, AComment: string): string;
var
  mObject, mIssue: TJSONObject;
  mIssues: TJSONArray;
begin
  mObject := TJSONObject.Create;
  try
    mObject.AddPair('query', AQuery);
    mIssues := TJSONArray.Create;
    mIssue := TJSONObject.Create;
    mIssue.AddPair('idReadable', Trim(AKey));
    mIssues.AddElement(mIssue);
    mObject.AddPair('issues', mIssues);
    if Trim(AComment) <> '' then
      mObject.AddPair('comment', AComment);
    Result := mObject.ToJSON;
  finally
    mObject.Free;
  end;
end;

class function TAtlasYouTrackTracker.CommentJson(const AText: string): string;
var
  mObject: TJSONObject;
begin
  mObject := TJSONObject.Create;
  try
    mObject.AddPair('text', AText);
    Result := mObject.ToJSON;
  finally
    mObject.Free;
  end;
end;

class function TAtlasYouTrackTracker.ErrorMessage(const AJson: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if mValue is TJSONObject then
    begin
      Result := TextOf(TJSONObject(mValue), 'error_description');
      if Result = '' then
        Result := TextOf(TJSONObject(mValue), 'error');
    end;
  finally
    mValue.Free;
  end;
  Result := Shorten(Result, 300);
end;

function FieldTypeOf(AField: TJSONObject): string;
var
  mType: TJSONValue;
begin
  Result := '';
  mType := AField.Values['fieldType'];
  if mType is TJSONObject then
    Result := LowerCase(TextOf(TJSONObject(mType), 'id'));
end;

function KindMatches(const AType: string; AKind: TAtlasTrackerValueKind): Boolean;
begin
  case AKind of
    TAtlasTrackerValueKind.StateFields, TAtlasTrackerValueKind.States:
      Result := AType.StartsWith('state');
    TAtlasTrackerValueKind.UserFields:
      Result := AType.StartsWith('user');
  else
    Result := False;
  end;
end;

procedure AddValue(var AValues: TArray<string>; const AText: string);
var
  mItem: string;
begin
  if (Trim(AText) = '') or (Length(AValues) >= TAtlasYouTrackTracker.MaxValues) then
    Exit;
  for mItem in AValues do
    if SameText(mItem, Trim(AText)) then
      Exit;
  AValues := AValues + [Trim(AText)];
end;

/// <summary>Ein Eintrag von customFields eines Projekts: {"field": {...}, "bundle": {"values": [...]}}.</summary>
procedure AddProjectField(AEntry: TJSONObject; AKind: TAtlasTrackerValueKind; const AField: string;
  var AValues: TArray<string>);
var
  mField, mBundle, mItems, mItem: TJSONValue;
  mName: string;
begin
  mField := AEntry.Values['field'];
  if not (mField is TJSONObject) then
    Exit;
  mName := TextOf(TJSONObject(mField), 'name');
  if not KindMatches(FieldTypeOf(TJSONObject(mField)), AKind) then
    Exit;
  if AKind <> TAtlasTrackerValueKind.States then
  begin
    AddValue(AValues, mName);
    Exit;
  end;
  if (AField <> '') and not SameText(mName, AField) then
    Exit;
  mBundle := AEntry.Values['bundle'];
  if not (mBundle is TJSONObject) then
    Exit;
  mItems := TJSONObject(mBundle).Values['values'];
  if mItems is TJSONArray then
    for mItem in TJSONArray(mItems) do
      if (mItem is TJSONObject) and not BoolOf(TJSONObject(mItem), 'archived') then
        AddValue(AValues, TextOf(TJSONObject(mItem), 'name'));
end;

class function TAtlasYouTrackTracker.ParseFieldValues(const AJson, AProject: string; AKind: TAtlasTrackerValueKind;
  const AField: string; out AValues: TArray<string>): Boolean;
var
  mValue, mProject, mFields, mEntry: TJSONValue;
begin
  AValues := nil;
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONArray) then
      Exit;
    Result := True;
    for mProject in TJSONArray(mValue) do
    begin
      if not (mProject is TJSONObject) then
        Continue;
      // Liste der Projekte: nur das eigene; Liste der Felder (ohne Projekt): Einträge sind die Felder selbst.
      mFields := TJSONObject(mProject).Values['customFields'];
      if mFields is TJSONArray then
      begin
        if (AProject <> '') and not SameText(TextOf(TJSONObject(mProject), 'shortName'), AProject) then
          Continue;
        for mEntry in TJSONArray(mFields) do
          if mEntry is TJSONObject then
            AddProjectField(TJSONObject(mEntry), AKind, AField, AValues);
      end
      else if (AKind <> TAtlasTrackerValueKind.States) and
        KindMatches(FieldTypeOf(TJSONObject(mProject)), AKind) then
        AddValue(AValues, TextOf(TJSONObject(mProject), 'name'));
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasYouTrackTracker.ParseUsers(const AJson: string; out AValues: TArray<string>): Boolean;
var
  mValue, mItem: TJSONValue;
begin
  AValues := nil;
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONArray) then
      Exit;
    Result := True;
    for mItem in TJSONArray(mValue) do
      if (mItem is TJSONObject) and not BoolOf(TJSONObject(mItem), 'banned') then
        AddValue(AValues, TextOf(TJSONObject(mItem), 'login'));
  finally
    mValue.Free;
  end;
end;

function TAtlasYouTrackTracker.Apply(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; const AChange: TAtlasTrackerChange; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
var
  mSend: IAtlasCiSend;
  mQuery, mUrl, mBody, mAnswer: string;
  mStatus: Integer;
  mError: TAtlasCiFetchError;
begin
  Result := TAtlasTrackerWriteResult.Ok;
  if not AChange.HasWork then
    Exit;
  if (ATarget.Server = '') or not ValidKey(Trim(AKey)) or not Supports(ATransport, IAtlasCiSend, mSend) then
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, ''));
  mQuery := CommandQuery(AChange);
  if mQuery = '' then
  begin
    mUrl := ATarget.Url + '/api/issues/' + Trim(AKey) + '/comments?fields=id';
    mBody := CommentJson(AChange.Comment);
  end
  else
  begin
    mUrl := ATarget.Url + '/api/commands';
    mBody := CommandJson(AKey, mQuery, AChange.Comment);
  end;
  if not mSend.Send('POST', mUrl, mBody, ATimeoutMs, mStatus, mAnswer, mError) then
    Exit(TAtlasTrackerWriteResult.Failed(mError, 0, ''));
  if (mStatus < 200) or (mStatus > 299) then
    Result := TAtlasTrackerWriteResult.Failed(ErrorOfStatus(mStatus), mStatus, ErrorMessage(mAnswer));
end;

function TAtlasYouTrackTracker.Values(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  AKind: TAtlasTrackerValueKind; const AField: string; ATimeoutMs: Integer;
  out AValues: TArray<string>): TAtlasTrackerWriteResult;
var
  mUrl, mText: string;
  mStatus: Integer;
  mError: TAtlasCiFetchError;
  mOk: Boolean;
begin
  AValues := nil;
  Result := TAtlasTrackerWriteResult.Ok;
  if (ATarget.Server = '') or (ATransport = nil) then
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, ''));
  if AKind = TAtlasTrackerValueKind.Users then
    mUrl := ATarget.Url + '/api/users?fields=' + TTextUris.PercentEncode('login,banned') + '&$top=' +
      IntToStr(MaxValues)
  else if (ATarget.Project = '') and (AKind <> TAtlasTrackerValueKind.States) then
    mUrl := ATarget.Url + '/api/admin/customFieldSettings/customFields?fields=' +
      TTextUris.PercentEncode('name,fieldType(id)') + '&$top=' + IntToStr(MaxValues)
  else
    mUrl := ATarget.Url + '/api/admin/projects?fields=' + TTextUris.PercentEncode(ProjectFields) + '&$top=500';
  if not ATransport.Get(mUrl, ATimeoutMs, mStatus, mText, mError) then
    Exit(TAtlasTrackerWriteResult.Failed(mError, 0, ''));
  if mStatus <> 200 then
    Exit(TAtlasTrackerWriteResult.Failed(ErrorOfStatus(mStatus), mStatus, ErrorMessage(mText)));
  if AKind = TAtlasTrackerValueKind.Users then
    mOk := ParseUsers(mText, AValues)
  else
    mOk := ParseFieldValues(mText, ATarget.Project, AKind, Trim(AField), AValues);
  if not mOk then
    Result := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, mStatus, '');
end;

{ IAtlasTrackerTimeWriter (#1267) }

class function TAtlasYouTrackTracker.ProjectOfKey(const AKey: string): string;
var
  mDash: Integer;
begin
  Result := '';
  mDash := LastDelimiter('-', Trim(AKey));
  if mDash > 1 then
    Result := Copy(Trim(AKey), 1, mDash - 1);
end;

class function TAtlasYouTrackTracker.WorkItemJson(const AItem: TAtlasTrackerWorkItem): string;
var
  mObject, mDuration, mType: TJSONObject;
begin
  mObject := TJSONObject.Create;
  try
    mDuration := TJSONObject.Create;
    mDuration.AddPair('presentation', TAtlasTimeRounding.Presentation(AItem.Minutes));
    mObject.AddPair('duration', mDuration);
    mObject.AddPair('date', TJSONNumber.Create(DateTimeToUnix(Trunc(AItem.Date) + 0.5, True) * 1000));
    if AItem.WorkType <> '' then
    begin
      mType := TJSONObject.Create;
      mType.AddPair('name', AItem.WorkType);
      mObject.AddPair('type', mType);
    end;
    if Trim(AItem.Text) <> '' then
      mObject.AddPair('text', AItem.Text);
    Result := mObject.ToJSON;
  finally
    mObject.Free;
  end;
end;

class function TAtlasYouTrackTracker.ParseTimeSettings(const AJson: string; AList: Boolean;
  out ASettings: TAtlasTrackerTimeSettings): Boolean;
var
  mValue, mTypes, mItem: TJSONValue;
begin
  ASettings.Enabled := True;
  ASettings.WorkTypes := nil;
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if AList then
    begin
      if not (mValue is TJSONArray) then
        Exit;
      mTypes := mValue;
    end
    else
    begin
      if not (mValue is TJSONObject) then
        Exit;
      ASettings.Enabled := BoolOf(TJSONObject(mValue), 'enabled');
      mTypes := TJSONObject(mValue).Values['workItemTypes'];
    end;
    if (mTypes <> nil) and not (mTypes is TJSONArray) then
      Exit;
    Result := True;
    if mTypes <> nil then
      for mItem in TJSONArray(mTypes) do
        if mItem is TJSONObject then
          AddValue(ASettings.WorkTypes, TextOf(TJSONObject(mItem), 'name'));
  finally
    mValue.Free;
  end;
end;

class function TAtlasYouTrackTracker.TimeTrackingOff(const AResult: TAtlasTrackerWriteResult): Boolean;
begin
  Result := (AResult.Status = 400) and (ContainsText(AResult.Message, 'time tracking') or
    ContainsText(AResult.Message, 'timetracking') or ContainsText(AResult.Message, 'Zeiterfassung'));
end;

function TAtlasYouTrackTracker.IsTrackingOff(const AResult: TAtlasTrackerWriteResult): Boolean;
begin
  Result := TimeTrackingOff(AResult);
end;

function TAtlasYouTrackTracker.TimeSettings(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; ATimeoutMs: Integer; out ASettings: TAtlasTrackerTimeSettings): TAtlasTrackerWriteResult;
var
  mProject, mUrl, mText: string;
  mStatus: Integer;
  mError: TAtlasCiFetchError;
begin
  ASettings.Enabled := True;
  ASettings.WorkTypes := nil;
  Result := TAtlasTrackerWriteResult.Ok;
  mProject := ProjectOfKey(AKey);
  if (ATarget.Server = '') or (ATransport = nil) or (mProject = '') then
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, ''));
  mUrl := ATarget.Url + '/api/admin/projects/' + TTextUris.PercentEncode(mProject) + '/timeTrackingSettings?fields=' +
    TTextUris.PercentEncode(TimeSettingsFields);
  if not ATransport.Get(mUrl, ATimeoutMs, mStatus, mText, mError) then
    Exit(TAtlasTrackerWriteResult.Failed(mError, 0, ''));
  if mStatus = 200 then
  begin
    if not ParseTimeSettings(mText, False, ASettings) then
      Result := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, mStatus, '');
    Exit;
  end;
  if (mStatus <> 403) and (mStatus <> 404) then
    Exit(TAtlasTrackerWriteResult.Failed(ErrorOfStatus(mStatus), mStatus, ErrorMessage(mText)));
  // Ohne Leserecht auf das Projekt: Zeiterfassung gilt als an, Arbeitstypen allgemein (sonst frei).
  mUrl := ATarget.Url + '/api/admin/timeTrackingSettings/workItemTypes?fields=name&$top=' + IntToStr(MaxValues);
  if ATransport.Get(mUrl, ATimeoutMs, mStatus, mText, mError) and (mStatus = 200) and
    not ParseTimeSettings(mText, True, ASettings) then
    ASettings.WorkTypes := nil;
end;

function TAtlasYouTrackTracker.BookTime(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; const AItem: TAtlasTrackerWorkItem; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
var
  mSend: IAtlasCiSend;
  mAnswer: string;
  mStatus: Integer;
  mError: TAtlasCiFetchError;
begin
  if AItem.Minutes <= 0 then
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 0, ''));
  if (ATarget.Server = '') or not ValidKey(Trim(AKey)) or not Supports(ATransport, IAtlasCiSend, mSend) then
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, ''));
  Result := TAtlasTrackerWriteResult.Ok;
  if not mSend.Send('POST', ATarget.Url + '/api/issues/' + Trim(AKey) + '/timeTracking/workItems?fields=id',
    WorkItemJson(AItem), ATimeoutMs, mStatus, mAnswer, mError) then
    Exit(TAtlasTrackerWriteResult.Failed(mError, 0, ''));
  if (mStatus < 200) or (mStatus > 299) then
    Result := TAtlasTrackerWriteResult.Failed(ErrorOfStatus(mStatus), mStatus, ErrorMessage(mAnswer));
end;

end.
