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
// - Verknüpfungen (#1279): Linktyp mit Namen und Beschriftungen (auch
//   lokalisiert) und „aggregation“, je Issue resolved und Zustand; die Art
//   bestimmt TAtlasTrackerLinks.YouTrackKind.
// - Unteraufgabe anlegen (#1279): GET /api/issues/<Eltern>?fields=project(id),
//   POST /api/issues mit Projekt, summary und description, dann
//   POST /api/issues/<Eltern>/links/<Linktyp><s|t>/issues mit {"idReadable"}.
//   Den Linktyp (Subtask bzw. Depend) liefert /api/issueLinkTypes; s = das
//   Issue im Pfad ist die Quelle, t = das Ziel.
// - Checklisten (#1273, IAtlasTrackerDescriptions): Beschreibung ungekürzt aus
//   GET <url>/api/issues/<Kennung>?fields=idReadable,description, zurück mit
//   POST <url>/api/issues/<Kennung>?fields=idReadable und {"description": …}.

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract;

type
  TAtlasYouTrackTracker = class(TInterfacedObject, IAtlasTrackerProvider, IAtlasTrackerWriter,
    IAtlasTrackerLinkWriter, IAtlasTrackerDescriptions)
  public const
    ProviderName = 'youtrack';
    Query = 'for: me #Unresolved';
    Fields = 'idReadable,numberInProject,summary,customFields(name,value(name,presentation))';
    /// <summary>Felder der Vorschau (#1264) ohne Kommentare.</summary>
    DetailFields = 'idReadable,numberInProject,summary,description,created,updated,' +
      'customFields(name,value(name,presentation,login,fullName)),tags(name),' +
      'attachments(name,size,url,mimeType,removed),' +
      'links(direction,linkType(name,localizedName,sourceToTarget,localizedSourceToTarget,targetToSource,' +
      'localizedTargetToSource,aggregation),issues(idReadable,summary,resolved,customFields(name,value(name))))';
    CommentFields = 'comments(text,created,deleted,author(login,fullName))';
    /// <summary>Felder der Projekte für die Klapplisten (#1266).</summary>
    ProjectFields = 'shortName,customFields(field(name,fieldType(id)),bundle(values(name,archived)))';
    /// <summary>Höchstens so viele Werte je Klappliste.</summary>
    MaxValues = 200;
    /// <summary>Felder der Linktypen (#1279).</summary>
    LinkTypeFields = 'id,name,localizedName,sourceToTarget,localizedSourceToTarget,targetToSource,' +
      'localizedTargetToSource,aggregation';
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
    /// <summary>Adresse der Linktypen; '' ohne Server.</summary>
    class function LinkTypesUrl(const ATarget: TAtlasTrackerTarget): string; static;
    /// <summary>Linktyp aus /api/issueLinkTypes, mit dem ein Link am Issue im Pfad die Art AKind ergibt: AId
    /// samt Richtung ("80-1s", "81-2t"). Typen mit bekanntem Namen gehen vor. False ohne passenden Typ.</summary>
    class function ParseLinkType(const AJson: string; AKind: TAtlasTrackerLinkKind; out AId: string): Boolean;
      static;
    /// <summary>Projekt-ID aus /api/issues/<Kennung>?fields=project(id); False ohne.</summary>
    class function ParseProjectId(const AJson: string; out AId: string): Boolean; static;
    /// <summary>Inhalt für POST /api/issues.</summary>
    class function NewIssueBody(const AProjectId, ATitle, ADescription: string): string; static;
    /// <summary>Inhalt für POST …/links/<Typ>/issues.</summary>
    class function LinkBody(const AKey: string): string; static;
    /// <summary>Kennung des angelegten Issues aus der Antwort von POST /api/issues; '' ohne.</summary>
    class function ParseCreatedKey(const AJson: string): string; static;
    /// <summary>Adresse zum Lesen (AFields "idReadable,description") bzw. Schreiben ("idReadable") der
    /// Beschreibung (#1273); '' bei ungültiger Kennung oder ohne Server.</summary>
    class function IssueUrl(const ATarget: TAtlasTrackerTarget; const AKey, AFields: string): string; static;
    /// <summary>"description" ungekürzt ('' bei null); False bei ungültigem JSON bzw. ohne "idReadable".</summary>
    class function ParseDescription(const AJson: string; out AText: string): Boolean; static;
    /// <summary>Inhalt des POST: {"description": AText}.</summary>
    class function DescriptionJson(const AText: string): string; static;
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
    { IAtlasTrackerLinkWriter }
    function CreateSubtask(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const AParentKey, ATitle, ADescription: string; ATimeoutMs: Integer; out AKey: string;
      out AError: TAtlasCiFetchError): Boolean;
    function AddLink(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      AKind: TAtlasTrackerLinkKind; const AOtherKey: string; ATimeoutMs: Integer;
      out AError: TAtlasCiFetchError): Boolean;
    { IAtlasTrackerDescriptions }
    function Description(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      ATimeoutMs: Integer; out AText: string; out AError: TAtlasCiFetchError): Boolean;
    function UpdateDescription(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const AKey, AText: string; ATimeoutMs: Integer; out AError: TAtlasCiFetchError): Boolean;
  end;

implementation

uses
  System.Classes,
  System.DateUtils,
  System.Generics.Collections,
  System.JSON,
  System.StrUtils,
  System.Diagnostics,
  Atlas.Text.Uris,
  Atlas.Core.Tracker.Links;

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

function FirstText(AObject: TJSONObject; const AName, AFallback: string): string;
begin
  Result := TextOf(AObject, AName);
  if Result = '' then
    Result := TextOf(AObject, AFallback);
end;

/// <summary>Art eines Links (#1279) aus dem Linktyp: englische und lokalisierte Namen und Beschriftungen.</summary>
function TypeKind(AType: TJSONObject; const ADirection: string): TAtlasTrackerLinkKind;
var
  mAggregation: Boolean;
begin
  mAggregation := BoolOf(AType, 'aggregation');
  Result := TAtlasTrackerLinks.YouTrackKind(TextOf(AType, 'name'), TextOf(AType, 'sourceToTarget'),
    TextOf(AType, 'targetToSource'), ADirection, mAggregation);
  if Result = TAtlasTrackerLinkKind.Other then
    Result := TAtlasTrackerLinks.YouTrackKind(TextOf(AType, 'localizedName'),
      TextOf(AType, 'localizedSourceToTarget'), TextOf(AType, 'localizedTargetToSource'), ADirection, mAggregation);
end;

/// <summary>Zustand eines verknüpften Issues aus customFields (State, Status, Zustand); '' ohne.</summary>
function StateOf(AIssue: TJSONObject): string;
var
  mFields, mField: TJSONValue;
begin
  Result := '';
  mFields := AIssue.Values['customFields'];
  if not (mFields is TJSONArray) then
    Exit;
  for mField in TJSONArray(mFields) do
    if (mField is TJSONObject) and IsOneOf(TextOf(TJSONObject(mField), 'name'), ['State', 'Status', 'Zustand']) then
    begin
      Result := ValueText(TJSONObject(mField).Values['value']);
      if Result <> '' then
        Exit;
    end;
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
  mKind: TAtlasTrackerLinkKind;
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
        mKind := TAtlasTrackerLinkKind.Other;
        if mObject.Values['linkType'] is TJSONObject then
        begin
          mType := TJSONObject(mObject.Values['linkType']);
          // Beschriftung in der Sprache der Oberfläche, sonst die englische.
          if mDirection = 'INWARD' then
            mRelation := FirstText(mType, 'localizedTargetToSource', 'targetToSource')
          else
            mRelation := FirstText(mType, 'localizedSourceToTarget', 'sourceToTarget');
          if mRelation = '' then
            mRelation := FirstText(mType, 'localizedName', 'name');
          mKind := TypeKind(mType, mDirection);
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
          mLink.Kind := mKind;
          // Zustand (#1279): resolved ist null, solange das Issue offen ist; fehlt das Feld, bleibt er unbekannt.
          mLink.StateKnown := TJSONObject(mIssue).Values['resolved'] <> nil;
          mLink.Resolved := TJSONObject(mIssue).Values['resolved'] is TJSONNumber;
          mLink.State := StateOf(TJSONObject(mIssue));
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

{ Verknüpfungen (#1279) }

class function TAtlasYouTrackTracker.LinkTypesUrl(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := '';
  if ATarget.Server <> '' then
    Result := ATarget.Url + '/api/issueLinkTypes?fields=' + TTextUris.PercentEncode(LinkTypeFields);
end;

class function TAtlasYouTrackTracker.ParseLinkType(const AJson: string; AKind: TAtlasTrackerLinkKind;
  out AId: string): Boolean;
const
  KnownLinkTypes: array[0..3] of string = ('Depend', 'Subtask', 'Abhängigkeit', 'Unteraufgabe');
  Directions: array[0..1] of string = ('OUTWARD', 'INWARD');
  Suffixes: array[0..1] of string = ('s', 't');
var
  mValue, mItem: TJSONValue;
  mType: TJSONObject;
  mPass, mSide: Integer;
  mId: string;
begin
  AId := '';
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONArray) then
      Exit;
    // Erst die Typen mit bekanntem Namen (Depend, Subtask), dann alle, deren Beschriftungen passen.
    for mPass := 0 to 1 do
      for mItem in TJSONArray(mValue) do
      begin
        if not (mItem is TJSONObject) then
          Continue;
        mType := TJSONObject(mItem);
        mId := TextOf(mType, 'id');
        if mId = '' then
          Continue;
        if (mPass = 0) and not IsOneOf(TextOf(mType, 'name'), KnownLinkTypes) then
          Continue;
        for mSide := 0 to 1 do
          if TypeKind(mType, Directions[mSide]) = AKind then
          begin
            AId := mId + Suffixes[mSide];
            Exit(True);
          end;
      end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasYouTrackTracker.ParseProjectId(const AJson: string; out AId: string): Boolean;
var
  mValue: TJSONValue;
begin
  AId := '';
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if (mValue is TJSONObject) and (TJSONObject(mValue).Values['project'] is TJSONObject) then
      AId := TextOf(TJSONObject(TJSONObject(mValue).Values['project']), 'id');
  finally
    mValue.Free;
  end;
  Result := AId <> '';
end;

class function TAtlasYouTrackTracker.NewIssueBody(const AProjectId, ATitle, ADescription: string): string;
var
  mRoot, mProject: TJSONObject;
begin
  mRoot := TJSONObject.Create;
  try
    mProject := TJSONObject.Create;
    mProject.AddPair('id', AProjectId);
    mRoot.AddPair('project', mProject);
    mRoot.AddPair('summary', Trim(ATitle));
    if Trim(ADescription) <> '' then
      mRoot.AddPair('description', ADescription);
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasYouTrackTracker.LinkBody(const AKey: string): string;
var
  mRoot: TJSONObject;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('idReadable', Trim(AKey));
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasYouTrackTracker.ParseCreatedKey(const AJson: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if mValue is TJSONObject then
      Result := Trim(TextOf(TJSONObject(mValue), 'idReadable'));
  finally
    mValue.Free;
  end;
  if not ValidKey(Result) then
    Result := '';
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

/// <summary>Link des Issues AKey (Linktyp mit Richtung AType) auf AOtherKey anlegen.</summary>
function PostLink(const ATarget: TAtlasTrackerTarget; const APost: IAtlasCiSend; const AKey, AType, AOtherKey: string;
  ATimeoutMs: Integer; out AError: TAtlasCiFetchError): Boolean;
var
  mStatus: Integer;
  mText: string;
begin
  Result := False;
  if not APost.Send('POST', ATarget.Url + '/api/issues/' + Trim(AKey) + '/links/' + AType + '/issues?fields=id',
    TAtlasYouTrackTracker.LinkBody(AOtherKey), ATimeoutMs, mStatus, mText, AError) then
    Exit;
  if (mStatus <> 200) and (mStatus <> 201) then
  begin
    AError := TAtlasYouTrackTracker.ErrorOfStatus(mStatus);
    Exit;
  end;
  AError := TAtlasCiFetchError.None;
  Result := True;
end;

/// <summary>Linktyp mit Richtung für AKind ("80-1s"); False mit AError ohne passenden Typ.</summary>
function FindLinkType(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  AKind: TAtlasTrackerLinkKind; ATimeoutMs: Integer; out AType: string; out AError: TAtlasCiFetchError): Boolean;
var
  mStatus: Integer;
  mText: string;
begin
  AType := '';
  Result := False;
  if not ATransport.Get(TAtlasYouTrackTracker.LinkTypesUrl(ATarget), ATimeoutMs, mStatus, mText, AError) then
    Exit;
  if mStatus <> 200 then
  begin
    AError := TAtlasYouTrackTracker.ErrorOfStatus(mStatus);
    Exit;
  end;
  if not TAtlasYouTrackTracker.ParseLinkType(mText, AKind, AType) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  AError := TAtlasCiFetchError.None;
  Result := True;
end;

function TAtlasYouTrackTracker.CreateSubtask(const ATarget: TAtlasTrackerTarget;
  const ATransport: IAtlasCiTransport; const AParentKey, ATitle, ADescription: string; ATimeoutMs: Integer;
  out AKey: string; out AError: TAtlasCiFetchError): Boolean;
var
  mPost: IAtlasCiSend;
  mWatch: TStopwatch;
  mStatus: Integer;
  mText, mProject, mType: string;
begin
  AKey := '';
  AError := TAtlasCiFetchError.NotConfigured;
  Result := False;
  if (ATarget.Server = '') or (ATransport = nil) or not Supports(ATransport, IAtlasCiSend, mPost) or
    not ValidKey(Trim(AParentKey)) then
    Exit;
  if Trim(ATitle) = '' then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  mWatch := TStopwatch.StartNew;
  // Projekt des übergeordneten Issues: die Unteraufgabe liegt im selben.
  if not ATransport.Get(ATarget.Url + '/api/issues/' + Trim(AParentKey) + '?fields=' +
    TTextUris.PercentEncode('id,project(id)'), ATimeoutMs, mStatus, mText, AError) then
    Exit;
  if mStatus <> 200 then
  begin
    AError := ErrorOfStatus(mStatus);
    Exit;
  end;
  if not ParseProjectId(mText, mProject) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  // Linktyp vor dem Anlegen: ohne Subtask-Typ entsteht kein loses Issue.
  if not FindLinkType(ATarget, ATransport, TAtlasTrackerLinkKind.Subtask, Rest(mWatch, ATimeoutMs), mType,
    AError) then
    Exit;
  if not mPost.Send('POST', ATarget.Url + '/api/issues?fields=idReadable', NewIssueBody(mProject, ATitle,
    ADescription), Rest(mWatch, ATimeoutMs), mStatus, mText, AError) then
    Exit;
  if (mStatus <> 200) and (mStatus <> 201) then
  begin
    AError := ErrorOfStatus(mStatus);
    Exit;
  end;
  AKey := ParseCreatedKey(mText);
  if AKey = '' then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  Result := PostLink(ATarget, mPost, AParentKey, mType, AKey, Rest(mWatch, ATimeoutMs), AError);
end;

function TAtlasYouTrackTracker.AddLink(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; AKind: TAtlasTrackerLinkKind; const AOtherKey: string; ATimeoutMs: Integer;
  out AError: TAtlasCiFetchError): Boolean;
var
  mPost: IAtlasCiSend;
  mWatch: TStopwatch;
  mType: string;
begin
  AError := TAtlasCiFetchError.NotConfigured;
  Result := False;
  if (ATarget.Server = '') or (ATransport = nil) or not Supports(ATransport, IAtlasCiSend, mPost) then
    Exit;
  if not (AKind in [TAtlasTrackerLinkKind.DependsOn, TAtlasTrackerLinkKind.Blocks]) or
    not ValidKey(Trim(AKey)) or not ValidKey(Trim(AOtherKey)) or SameText(Trim(AKey), Trim(AOtherKey)) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  mWatch := TStopwatch.StartNew;
  if not FindLinkType(ATarget, ATransport, AKind, ATimeoutMs, mType, AError) then
    Exit;
  Result := PostLink(ATarget, mPost, AKey, mType, AOtherKey, Rest(mWatch, ATimeoutMs), AError);
end;

class function TAtlasYouTrackTracker.IssueUrl(const ATarget: TAtlasTrackerTarget; const AKey,
  AFields: string): string;
begin
  Result := '';
  if (ATarget.Server = '') or not ValidKey(Trim(AKey)) then
    Exit;
  Result := ATarget.Url + '/api/issues/' + Trim(AKey) + '?fields=' + TTextUris.PercentEncode(AFields);
end;

class function TAtlasYouTrackTracker.ParseDescription(const AJson: string; out AText: string): Boolean;
var
  mValue: TJSONValue;
begin
  AText := '';
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := (mValue is TJSONObject) and (TextOf(TJSONObject(mValue), 'idReadable') <> '');
    if Result then
      AText := TextOf(TJSONObject(mValue), 'description');
  finally
    mValue.Free;
  end;
end;

class function TAtlasYouTrackTracker.DescriptionJson(const AText: string): string;
var
  mObject: TJSONObject;
begin
  mObject := TJSONObject.Create;
  try
    mObject.AddPair('description', AText);
    Result := mObject.ToJSON;
  finally
    mObject.Free;
  end;
end;

function TAtlasYouTrackTracker.Description(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; ATimeoutMs: Integer; out AText: string; out AError: TAtlasCiFetchError): Boolean;
var
  mUrl, mJson: string;
  mStatus: Integer;
begin
  AText := '';
  AError := TAtlasCiFetchError.None;
  Result := False;
  mUrl := IssueUrl(ATarget, AKey, 'idReadable,description');
  if (mUrl = '') or (ATransport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  if not ATransport.Get(mUrl, ATimeoutMs, mStatus, mJson, AError) then
    Exit;
  if mStatus <> 200 then
  begin
    AError := ErrorOfStatus(mStatus);
    Exit;
  end;
  if not ParseDescription(mJson, AText) or (Length(AText) > TAtlasTrackerDetails.MaxDescription) then
  begin
    AText := '';
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  Result := True;
end;

function TAtlasYouTrackTracker.UpdateDescription(const ATarget: TAtlasTrackerTarget;
  const ATransport: IAtlasCiTransport; const AKey, AText: string; ATimeoutMs: Integer;
  out AError: TAtlasCiFetchError): Boolean;
var
  mUrl, mAnswer: string;
  mStatus: Integer;
  mSend: IAtlasCiSend;
begin
  AError := TAtlasCiFetchError.None;
  Result := False;
  mUrl := IssueUrl(ATarget, AKey, 'idReadable');
  if (mUrl = '') or not Supports(ATransport, IAtlasCiSend, mSend) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  if Length(AText) > TAtlasTrackerDetails.MaxDescription then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  if not mSend.Send('POST', mUrl, DescriptionJson(AText), ATimeoutMs, mStatus, mAnswer, AError) then
    Exit;
  if mStatus <> 200 then
  begin
    AError := ErrorOfStatus(mStatus);
    Exit;
  end;
  Result := True;
end;

end.
