unit Atlas.Core.Tracker.YouTrackParse;

// Antworten der YouTrack-REST-API lesen (#765, #1264, #1266, #1267, #1269,
// #1271, #1278, #1279), ohne Netz und daher testbar: Issues, Einzelheiten der
// Vorschau, Werte der Klapplisten, Zeiterfassung, Linktypen, Benutzer,
// VCS-Änderungen und Aktivitäten. Den Ablauf der Abfragen hat der Anbieter
// (Providers.YouTrack).

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Tracker.Contract;

type
  TAtlasYouTrackParse = class
  public
    /// <summary>Ein Eintrag von /api/issues mit den Feldern aus Fields; False ohne Kennung.</summary>
    class function IssueOf(AItem: TJSONObject; out AIssue: TAtlasTrackerIssue): Boolean; static;
    /// <summary>Antwort von /api/issues; False bei ungültigem JSON.</summary>
    class function ParseIssues(const AJson: string; AMax: Integer;
      out AIssues: TArray<TAtlasTrackerIssue>): Boolean; static;
    /// <summary>Antwort von /api/issues/&lt;Kennung&gt;; False bei ungültigem JSON bzw. ohne Kennung.</summary>
    class function ParseDetails(const AJson: string; const ATarget: TAtlasTrackerTarget; AComments: Boolean;
      out ADetails: TAtlasTrackerDetails): Boolean; static;
    /// <summary>Werte aus /api/admin/projects (AProject = Kürzel; '' = alle Projekte) bzw. ohne Projekt aus
    /// /api/admin/customFieldSettings/customFields; False bei ungültigem JSON.</summary>
    class function ParseFieldValues(const AJson, AProject: string; AKind: TAtlasTrackerValueKind; const AField: string;
      out AValues: TArray<string>): Boolean; static;
    /// <summary>Felder des Projekts AProject aus /api/admin/projects (#2123): AField '' = Namen aller Felder,
    /// sonst die nicht archivierten Werte von AField. False bei ungültigem JSON.</summary>
    class function ParseProjectFields(const AJson, AProject, AField: string; out AValues: TArray<string>): Boolean;
      static;
    /// <summary>Anmeldenamen aus /api/users; False bei ungültigem JSON.</summary>
    class function ParseUsers(const AJson: string; out AValues: TArray<string>): Boolean; static;
    /// <summary>Antwort von /api/users mit login und fullName, ohne gesperrte (#1278); False bei ungültigem JSON.
    /// </summary>
    class function ParseUserList(const AJson: string; out AUsers: TArray<TAtlasTrackerUser>): Boolean; static;
    /// <summary>{"enabled": …, "workItemTypes": [{"name": …}]} bzw. eine Liste [{"name": …}] (AList).</summary>
    class function ParseTimeSettings(const AJson: string; AList: Boolean;
      out ASettings: TAtlasTrackerTimeSettings): Boolean; static;
    /// <summary>"description" ungekürzt ('' bei null); False bei ungültigem JSON bzw. ohne "idReadable".</summary>
    class function ParseDescription(const AJson: string; out AText: string): Boolean; static;
    /// <summary>Linktyp aus /api/issueLinkTypes, mit dem ein Link am Issue im Pfad die Art AKind ergibt: AId
    /// samt Richtung ("80-1s", "81-2t"). Typen mit bekanntem Namen gehen vor. False ohne passenden Typ.</summary>
    class function ParseLinkType(const AJson: string; AKind: TAtlasTrackerLinkKind; out AId: string): Boolean;
      static;
    /// <summary>Projekt-ID aus /api/issues/&lt;Kennung&gt;?fields=project(id); False ohne.</summary>
    class function ParseProjectId(const AJson: string; out AId: string): Boolean; static;
    /// <summary>Kennung des angelegten Issues aus der Antwort von POST /api/issues; '' ohne.</summary>
    class function ParseCreatedKey(const AJson: string): string; static;
    /// <summary>Antwort von …/vcsChanges, neueste zuerst; False bei ungültigem JSON.</summary>
    class function ParseVcsChanges(const AJson: string; out AChanges: TArray<TAtlasTrackerVcsChange>): Boolean;
      static;
    /// <summary>Antwort der geänderten Issues: Kennung, Titel und Zeit, nur nach ASince. False bei ungültigem JSON.
    /// </summary>
    class function ParseChangedIssues(const AJson: string; ASince: TDateTime;
      out AIssues: TArray<TAtlasTrackerChange>): Boolean; static;
    /// <summary>Antwort von /activities als Änderungen an AKey (ATitle): Kommentare, Zuständig (AMe: an mich?) und
    /// Zustand nach ASince; andere Felder entfallen. False bei ungültigem JSON.</summary>
    class function ParseActivities(const AJson, AKey, ATitle, AMe: string; ASince: TDateTime;
      out AChanges: TArray<TAtlasTrackerChange>): Boolean; static;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.StrUtils,
  System.Math,
  Atlas.Core.Tracker.Links,
  Atlas.Core.Tracker.Internals.YouTrackJson,
  Atlas.Core.Tracker.YouTrackApi,
  Atlas.Text.Json;

/// <summary>Setzt ASlot auf AText, wenn er noch leer ist (der erste Wert gilt).</summary>
procedure SetFirst(var ASlot: string; const AText: string);
begin
  if ASlot = '' then
  begin
    ASlot := AText;
  end;
end;

/// <summary>Ruft AProc für jedes Objekt in customFields mit Namen und nicht leerem Wert auf.</summary>
procedure ForEachField(AFields: TJSONValue; const AProc: TProc<string, string>);
var
  mField: TJSONValue;
  mText: string;
begin
  if not (AFields is TJSONArray) then
  begin
    Exit;
  end;
  for mField in TJSONArray(AFields) do
  begin
    if mField is TJSONObject then
    begin
      mText := TAtlasYouTrackJson.ValueText(TJSONObject(mField).Values['value']);
      if mText <> '' then
      begin
        AProc(Trim(TJsonRead.Text(TJSONObject(mField), 'name')), mText);
      end;
    end;
  end;
end;

/// <summary>Ein Feld der Liste: Zustand, Priorität, Sprint, Zuständig (dieselben Namen wie in der Vorschau, #1264).
/// </summary>
procedure TakeIssueField(var AIssue: TAtlasTrackerIssue; const AName, AText: string);
begin
  if TAtlasYouTrackJson.IsOneOf(AName, ['State', 'Status', 'Zustand']) then
  begin
    SetFirst(AIssue.State, AText);
  end
  else if TAtlasYouTrackJson.IsOneOf(AName, ['Priority', 'Priorität']) then
  begin
    SetFirst(AIssue.Priority, AText);
  end
  else if TAtlasYouTrackJson.IsOneOf(AName, ['Sprint', 'Sprints', 'Board']) then
  begin
    SetFirst(AIssue.Sprint, AText);
  end
  else if TAtlasYouTrackJson.IsOneOf(AName, ['Assignee', 'Zuständig', 'Bearbeiter', 'Verantwortlich']) then
  begin
    SetFirst(AIssue.Assignee, AText);
  end;
end;

/// <summary>Ein Eintrag von /api/issues mit den Feldern aus Fields; False ohne Kennung.</summary>
class function TAtlasYouTrackParse.IssueOf(AItem: TJSONObject; out AIssue: TAtlasTrackerIssue): Boolean;
var
  mIssue: TAtlasTrackerIssue;
begin
  mIssue := TAtlasTrackerIssue.Empty;
  mIssue.Key := Trim(TJsonRead.Text(AItem, 'idReadable'));
  mIssue.Number := Max(0, TJsonRead.Int(AItem, 'numberInProject'));
  mIssue.Title := TAtlasYouTrackJson.Shorten(TJsonRead.Text(AItem, 'summary'), TAtlasTrackerIssue.cMaxTitle);
  ForEachField(AItem.Values['customFields'],
    procedure(AName, AText: string)
    begin
      TakeIssueField(mIssue, AName, AText);
    end);
  AIssue := mIssue;
  Result := AIssue.Key <> '';
  if not Result then
  begin
    AIssue := TAtlasTrackerIssue.Empty;
  end;
end;

class function TAtlasYouTrackParse.ParseIssues(const AJson: string; AMax: Integer;
  out AIssues: TArray<TAtlasTrackerIssue>): Boolean;
var
  mValue, mItem: TJSONValue;
  mIssue: TAtlasTrackerIssue;
begin
  AIssues := nil;
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONArray) then
    begin
      Exit;
    end;
    Result := True;
    for mItem in TJSONArray(mValue) do
    begin
      if Length(AIssues) >= AMax then
      begin
        Break;
      end;
      if (mItem is TJSONObject) and IssueOf(TJSONObject(mItem), mIssue) then
      begin
        AIssues := AIssues + [mIssue];
      end;
    end;
  finally
    mValue.Free;
  end;
end;

/// <summary>Art eines Links (#1279) aus dem Linktyp: englische und lokalisierte Namen und Beschriftungen.</summary>
function TypeKind(AType: TJSONObject; const ADirection: string): TAtlasTrackerLinkKind;
var
  mAggregation: Boolean;
begin
  mAggregation := TJsonRead.Flag(AType, 'aggregation');
  Result := TAtlasTrackerLinks.YouTrackKind(TJsonRead.Text(AType, 'name'), TJsonRead.Text(AType, 'sourceToTarget'),
    TJsonRead.Text(AType, 'targetToSource'), ADirection, mAggregation);
  if Result = TAtlasTrackerLinkKind.Other then
  begin
    Result := TAtlasTrackerLinks.YouTrackKind(TJsonRead.Text(AType, 'localizedName'),
      TJsonRead.Text(AType, 'localizedSourceToTarget'), TJsonRead.Text(AType, 'localizedTargetToSource'), ADirection, mAggregation);
  end;
end;

/// <summary>Zustand eines verknüpften Issues aus customFields (State, Status, Zustand); '' ohne.</summary>
function StateOf(AIssue: TJSONObject): string;
var
  mFields, mField: TJSONValue;
begin
  Result := '';
  mFields := AIssue.Values['customFields'];
  if not (mFields is TJSONArray) then
  begin
    Exit;
  end;
  for mField in TJSONArray(mFields) do
  begin
    if (mField is TJSONObject) and TAtlasYouTrackJson.IsOneOf(TJsonRead.Text(TJSONObject(mField), 'name'),
      ['State', 'Status', 'Zustand']) then
    begin
      Result := TAtlasYouTrackJson.ValueText(TJSONObject(mField).Values['value']);
      if Result <> '' then
      begin
        Exit;
      end;
    end;
  end;
end;

/// <summary>Ein Feld der Vorschau: Zustand, Priorität, Typ, Zuständig, Sprint bzw. Meilenstein.</summary>
procedure TakeDetailField(var ADetails: TAtlasTrackerDetails; const AName, AText: string);
begin
  if TAtlasYouTrackJson.IsOneOf(AName, ['State', 'Status', 'Zustand']) then
  begin
    SetFirst(ADetails.State, AText);
  end
  else if TAtlasYouTrackJson.IsOneOf(AName, ['Priority', 'Priorität']) then
  begin
    SetFirst(ADetails.Priority, AText);
  end
  else if TAtlasYouTrackJson.IsOneOf(AName, ['Type', 'Typ']) then
  begin
    SetFirst(ADetails.Kind, AText);
  end
  else if TAtlasYouTrackJson.IsOneOf(AName, ['Assignee', 'Zuständig', 'Bearbeiter', 'Verantwortlich']) then
  begin
    SetFirst(ADetails.Assignee, AText);
  end
  else if TAtlasYouTrackJson.IsOneOf(AName, ['Sprint', 'Sprints', 'Board', 'Fix versions', 'Fix version',
    'Meilenstein']) then
  begin
    SetFirst(ADetails.Sprint, AText);
  end;
end;

/// <summary>Namen der Schlagwörter ("tags").</summary>
function TagsOf(ATags: TJSONValue): TArray<string>;
var
  mTag: TJSONValue;
  mText: string;
begin
  Result := nil;
  if not (ATags is TJSONArray) then
  begin
    Exit;
  end;
  for mTag in TJSONArray(ATags) do
  begin
    if mTag is TJSONObject then
    begin
      mText := TAtlasYouTrackJson.Shorten(TJsonRead.Text(TJSONObject(mTag), 'name'), TAtlasTrackerTextLimits.cName);
      if mText <> '' then
      begin
        Result := Result + [mText];
      end;
    end;
  end;
end;

/// <summary>Größe in Byte; -1 ohne.</summary>
function AttachmentSizeOf(AObject: TJSONObject): Int64;
var
  mSize: TJSONValue;
begin
  Result := -1;
  mSize := AObject.Values['size'];
  if not (mSize is TJSONNumber) or not TryStrToInt64(TJSONNumber(mSize).Value, Result) or (Result < 0) then
  begin
    Result := -1;
  end;
end;

/// <summary>Ein Anhang; False ohne Namen oder Adresse. Die signierte Adresse ist relativ zum Server
/// ("/youtrack/api/files/…?sign=…").</summary>
function AttachmentOf(AObject: TJSONObject; const AServer: string; out AAttachment: TAtlasTrackerAttachment): Boolean;
var
  mUrl: string;
begin
  AAttachment := Default(TAtlasTrackerAttachment);
  AAttachment.Name := TAtlasYouTrackJson.Shorten(TJsonRead.Text(AObject, 'name'), TAtlasTrackerTextLimits.cTitle);
  AAttachment.MimeType := TJsonRead.Text(AObject, 'mimeType');
  AAttachment.Size := AttachmentSizeOf(AObject);
  mUrl := TJsonRead.Text(AObject, 'url');
  if StartsStr('/', mUrl) and (AServer <> '') then
  begin
    mUrl := AServer + mUrl;
  end;
  AAttachment.Url := mUrl;
  AAttachment.External := not SameText(TAtlasTrackerTarget.Create('', mUrl, '', '').Server, AServer);
  Result := (AAttachment.Name <> '') and (mUrl <> '');
end;

/// <summary>Anhänge ohne entfernte, höchstens MaxAttachments.</summary>
function AttachmentsOf(AItems: TJSONValue; const AServer: string): TArray<TAtlasTrackerAttachment>;
var
  mItem: TJSONValue;
  mAttachment: TAtlasTrackerAttachment;
begin
  Result := nil;
  if not (AItems is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AItems) do
  begin
    if Length(Result) >= TAtlasTrackerDetails.cMaxAttachments then
    begin
      Break;
    end;
    if (mItem is TJSONObject) and not TJsonRead.Flag(TJSONObject(mItem), 'removed') and
      AttachmentOf(TJSONObject(mItem), AServer, mAttachment) then
    begin
      Result := Result + [mAttachment];
    end;
  end;
end;

/// <summary>Beschriftung eines Linktyps in der Richtung, in der Sprache der Oberfläche, sonst die englische, sonst
/// sein Name.</summary>
function RelationOf(AType: TJSONObject; const ADirection: string): string;
begin
  if ADirection = 'INWARD' then
  begin
    Result := TAtlasYouTrackJson.FirstText(AType, 'localizedTargetToSource', 'targetToSource');
  end
  else
  begin
    Result := TAtlasYouTrackJson.FirstText(AType, 'localizedSourceToTarget', 'sourceToTarget');
  end;
  if Result = '' then
  begin
    Result := TAtlasYouTrackJson.FirstText(AType, 'localizedName', 'name');
  end;
end;

/// <summary>Ein verknüpftes Issue einer Linkgruppe. Zustand (#1279): resolved ist null, solange das Issue offen
/// ist; fehlt das Feld, bleibt er unbekannt. Gleicher Tracker: öffnet im Fenster.</summary>
function LinkOf(AIssue: TJSONObject; const ARelation: string; AKind: TAtlasTrackerLinkKind): TAtlasTrackerLink;
begin
  Result := Default(TAtlasTrackerLink);
  Result.Key := Trim(TJsonRead.Text(AIssue, 'idReadable'));
  Result.Title := TAtlasYouTrackJson.Shorten(TJsonRead.Text(AIssue, 'summary'), TAtlasTrackerTextLimits.cTitle);
  Result.Relation := TAtlasYouTrackJson.Shorten(ARelation, TAtlasTrackerTextLimits.cName);
  Result.Kind := AKind;
  Result.StateKnown := AIssue.Values['resolved'] <> nil;
  Result.Resolved := AIssue.Values['resolved'] is TJSONNumber;
  Result.State := StateOf(AIssue);
  Result.Local := TAtlasYouTrackJson.ValidKey(Result.Key);
end;

/// <summary>Die Issues einer Linkgruppe ({"direction", "linkType", "issues"}) an ALinks, bis MaxLinks.</summary>
procedure AddLinkGroup(AGroup: TJSONObject; var ALinks: TArray<TAtlasTrackerLink>);
var
  mIssue: TJSONValue;
  mDirection, mRelation: string;
  mKind: TAtlasTrackerLinkKind;
  mLink: TAtlasTrackerLink;
begin
  if not (AGroup.Values['issues'] is TJSONArray) then
  begin
    Exit;
  end;
  mDirection := UpperCase(TJsonRead.Text(AGroup, 'direction'));
  mRelation := '';
  mKind := TAtlasTrackerLinkKind.Other;
  if AGroup.Values['linkType'] is TJSONObject then
  begin
    mRelation := RelationOf(TJSONObject(AGroup.Values['linkType']), mDirection);
    mKind := TypeKind(TJSONObject(AGroup.Values['linkType']), mDirection);
  end;
  for mIssue in TJSONArray(AGroup.Values['issues']) do
  begin
    if (mIssue is TJSONObject) and (Length(ALinks) < TAtlasTrackerDetails.cMaxLinks) then
    begin
      mLink := LinkOf(TJSONObject(mIssue), mRelation, mKind);
      if mLink.Key <> '' then
      begin
        ALinks := ALinks + [mLink];
      end;
    end;
  end;
end;

function LinksOf(AGroups: TJSONValue): TArray<TAtlasTrackerLink>;
var
  mGroup: TJSONValue;
begin
  Result := nil;
  if not (AGroups is TJSONArray) then
  begin
    Exit;
  end;
  for mGroup in TJSONArray(AGroups) do
  begin
    if mGroup is TJSONObject then
    begin
      AddLinkGroup(TJSONObject(mGroup), Result);
    end;
  end;
end;

function CommentOf(AObject: TJSONObject): TAtlasTrackerComment;
begin
  Result := Default(TAtlasTrackerComment);
  Result.Text := TAtlasYouTrackJson.Limited(TJsonRead.Text(AObject, 'text'));
  Result.Created := TAtlasYouTrackJson.TimeOf(AObject, 'created');
  if AObject.Values['author'] is TJSONObject then
  begin
    Result.Author := TAtlasYouTrackJson.Shorten(TAtlasYouTrackJson.ValueText(AObject.Values['author']),
      TAtlasTrackerTextLimits.cPerson);
  end;
end;

/// <summary>Kommentare ohne gelöschte, nur die neuesten MaxComments.</summary>
function CommentsOf(AItems: TJSONValue): TArray<TAtlasTrackerComment>;
var
  mItem: TJSONValue;
begin
  Result := nil;
  if not (AItems is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AItems) do
  begin
    if (mItem is TJSONObject) and not TJsonRead.Flag(TJSONObject(mItem), 'deleted') then
    begin
      Result := Result + [CommentOf(TJSONObject(mItem))];
    end;
  end;
  if Length(Result) > TAtlasTrackerDetails.cMaxComments then
  begin
    Result := Copy(Result, Length(Result) - TAtlasTrackerDetails.cMaxComments, TAtlasTrackerDetails.cMaxComments);
  end;
end;

/// <summary>Einzelheiten aus dem Objekt eines Issues mit Kennung.</summary>
function DetailsOf(ARoot: TJSONObject; const AServer: string; AComments: Boolean): TAtlasTrackerDetails;
var
  mDetails: TAtlasTrackerDetails;
begin
  mDetails := TAtlasTrackerDetails.Empty;
  mDetails.Key := Trim(TJsonRead.Text(ARoot, 'idReadable'));
  mDetails.Number := Max(0, TJsonRead.Int(ARoot, 'numberInProject'));
  mDetails.Title := TAtlasYouTrackJson.Shorten(TJsonRead.Text(ARoot, 'summary'), TAtlasTrackerTextLimits.cDetailsTitle);
  mDetails.Description := TAtlasYouTrackJson.Limited(TJsonRead.Text(ARoot, 'description'));
  mDetails.Created := TAtlasYouTrackJson.TimeOf(ARoot, 'created');
  mDetails.Updated := TAtlasYouTrackJson.TimeOf(ARoot, 'updated');
  ForEachField(ARoot.Values['customFields'],
    procedure(AName, AText: string)
    begin
      TakeDetailField(mDetails, AName, AText);
    end);
  mDetails.Labels := TagsOf(ARoot.Values['tags']);
  mDetails.Attachments := AttachmentsOf(ARoot.Values['attachments'], AServer);
  mDetails.Links := LinksOf(ARoot.Values['links']);
  mDetails.CommentsLoaded := AComments;
  if AComments then
  begin
    mDetails.Comments := CommentsOf(ARoot.Values['comments']);
  end;
  Result := mDetails;
end;

class function TAtlasYouTrackParse.ParseDetails(const AJson: string; const ATarget: TAtlasTrackerTarget;
  AComments: Boolean; out ADetails: TAtlasTrackerDetails): Boolean;
var
  mValue: TJSONValue;
begin
  ADetails := TAtlasTrackerDetails.Empty;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := (mValue is TJSONObject) and (Trim(TJsonRead.Text(TJSONObject(mValue), 'idReadable')) <> '');
    if Result then
    begin
      ADetails := DetailsOf(TJSONObject(mValue), ATarget.Server, AComments);
    end;
  finally
    mValue.Free;
  end;
end;

function FieldTypeOf(AField: TJSONObject): string;
var
  mType: TJSONValue;
begin
  Result := '';
  mType := AField.Values['fieldType'];
  if mType is TJSONObject then
  begin
    Result := LowerCase(TJsonRead.Text(TJSONObject(mType), 'id'));
  end;
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
  if (Trim(AText) = '') or (Length(AValues) >= TAtlasYouTrackApi.cMaxValues) then
  begin
    Exit;
  end;
  for mItem in AValues do
  begin
    if SameText(mItem, Trim(AText)) then
    begin
      Exit;
    end;
  end;
  AValues := AValues + [Trim(AText)];
end;

/// <summary>Nicht archivierte Werte eines Bundles ({"values": [...]}).</summary>
procedure AddBundleValues(ABundle: TJSONValue; var AValues: TArray<string>);
var
  mItem: TJSONValue;
begin
  if not (ABundle is TJSONObject) or not (TJSONObject(ABundle).Values['values'] is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(TJSONObject(ABundle).Values['values']) do
  begin
    if (mItem is TJSONObject) and not TJsonRead.Flag(TJSONObject(mItem), 'archived') then
    begin
      AddValue(AValues, TJsonRead.Text(TJSONObject(mItem), 'name'));
    end;
  end;
end;

/// <summary>Ein Eintrag von customFields eines Projekts: {"field": {...}, "bundle": {"values": [...]}}.</summary>
procedure AddProjectField(AEntry: TJSONObject; AKind: TAtlasTrackerValueKind; const AField: string;
  var AValues: TArray<string>);
var
  mField: TJSONValue;
  mName: string;
begin
  mField := AEntry.Values['field'];
  if not (mField is TJSONObject) or not KindMatches(FieldTypeOf(TJSONObject(mField)), AKind) then
  begin
    Exit;
  end;
  mName := TJsonRead.Text(TJSONObject(mField), 'name');
  if AKind <> TAtlasTrackerValueKind.States then
  begin
    AddValue(AValues, mName);
  end
  else if (AField = '') or SameText(mName, AField) then
  begin
    AddBundleValues(AEntry.Values['bundle'], AValues);
  end;
end;

/// <summary>Ein Eintrag der Antwort. Liste der Projekte: nur das eigene; Liste der Felder (ohne Projekt): Einträge
/// sind die Felder selbst.</summary>
procedure AddFieldEntry(AEntry: TJSONObject; const AProject: string; AKind: TAtlasTrackerValueKind;
  const AField: string; var AValues: TArray<string>);
var
  mEntry: TJSONValue;
begin
  if not (AEntry.Values['customFields'] is TJSONArray) then
  begin
    if (AKind <> TAtlasTrackerValueKind.States) and KindMatches(FieldTypeOf(AEntry), AKind) then
    begin
      AddValue(AValues, TJsonRead.Text(AEntry, 'name'));
    end;
    Exit;
  end;
  if (AProject <> '') and not SameText(TJsonRead.Text(AEntry, 'shortName'), AProject) then
  begin
    Exit;
  end;
  for mEntry in TJSONArray(AEntry.Values['customFields']) do
  begin
    if mEntry is TJSONObject then
    begin
      AddProjectField(TJSONObject(mEntry), AKind, AField, AValues);
    end;
  end;
end;

class function TAtlasYouTrackParse.ParseFieldValues(const AJson, AProject: string; AKind: TAtlasTrackerValueKind;
  const AField: string; out AValues: TArray<string>): Boolean;
var
  mValue, mEntry: TJSONValue;
begin
  AValues := nil;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := mValue is TJSONArray;
    if not Result then
    begin
      Exit;
    end;
    for mEntry in TJSONArray(mValue) do
    begin
      if mEntry is TJSONObject then
      begin
        AddFieldEntry(TJSONObject(mEntry), AProject, AKind, AField, AValues);
      end;
    end;
  finally
    mValue.Free;
  end;
end;

/// <summary>Namen bzw. Werte der Felder eines Projekteintrags ({"shortName", "customFields": [...]}).</summary>
procedure AddProjectFields(AProject: TJSONObject; const AField: string; var AValues: TArray<string>);
var
  mEntry, mField: TJSONValue;
  mName: string;
begin
  if not (AProject.Values['customFields'] is TJSONArray) then
  begin
    Exit;
  end;
  for mEntry in TJSONArray(AProject.Values['customFields']) do
  begin
    if not (mEntry is TJSONObject) then
    begin
      Continue;
    end;
    mField := TJSONObject(mEntry).Values['field'];
    if not (mField is TJSONObject) then
    begin
      Continue;
    end;
    mName := TJsonRead.Text(TJSONObject(mField), 'name');
    if AField = '' then
    begin
      AddValue(AValues, mName);
    end
    else if SameText(mName, AField) then
    begin
      AddBundleValues(TJSONObject(mEntry).Values['bundle'], AValues);
    end;
  end;
end;

class function TAtlasYouTrackParse.ParseProjectFields(const AJson, AProject, AField: string;
  out AValues: TArray<string>): Boolean;
var
  mValue, mEntry: TJSONValue;
begin
  AValues := nil;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := mValue is TJSONArray;
    if not Result then
    begin
      Exit;
    end;
    for mEntry in TJSONArray(mValue) do
    begin
      if (mEntry is TJSONObject) and SameText(TJsonRead.Text(TJSONObject(mEntry), 'shortName'), AProject) then
      begin
        AddProjectFields(TJSONObject(mEntry), Trim(AField), AValues);
      end;
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasYouTrackParse.ParseUsers(const AJson: string; out AValues: TArray<string>): Boolean;
var
  mValue, mItem: TJSONValue;
begin
  AValues := nil;
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONArray) then
    begin
      Exit;
    end;
    Result := True;
    for mItem in TJSONArray(mValue) do
    begin
      if (mItem is TJSONObject) and not TJsonRead.Flag(TJSONObject(mItem), 'banned') then
      begin
        AddValue(AValues, TJsonRead.Text(TJSONObject(mItem), 'login'));
      end;
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasYouTrackParse.ParseUserList(const AJson: string;
  out AUsers: TArray<TAtlasTrackerUser>): Boolean;
var
  mValue, mItem: TJSONValue;
  mLogin: string;
begin
  AUsers := nil;
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONArray) then
    begin
      Exit;
    end;
    Result := True;
    for mItem in TJSONArray(mValue) do
    begin
      if not (mItem is TJSONObject) or TJsonRead.Flag(TJSONObject(mItem), 'banned') then
      begin
        Continue;
      end;
      mLogin := Trim(TJsonRead.Text(TJSONObject(mItem), 'login'));
      if mLogin <> '' then
      begin
        AUsers := AUsers + [TAtlasTrackerUser.Create(mLogin,
          TAtlasYouTrackJson.Shorten(TJsonRead.Text(TJSONObject(mItem), 'fullName'), TAtlasTrackerTextLimits.cPerson))];
      end;
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasYouTrackParse.ParseTimeSettings(const AJson: string; AList: Boolean;
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
      begin
        Exit;
      end;
      mTypes := mValue;
    end
    else
    begin
      if not (mValue is TJSONObject) then
      begin
        Exit;
      end;
      ASettings.Enabled := TJsonRead.Flag(TJSONObject(mValue), 'enabled');
      mTypes := TJSONObject(mValue).Values['workItemTypes'];
    end;
    if (mTypes <> nil) and not (mTypes is TJSONArray) then
    begin
      Exit;
    end;
    Result := True;
    if mTypes <> nil then
    begin
      for mItem in TJSONArray(mTypes) do
      begin
        if mItem is TJSONObject then
        begin
          AddValue(ASettings.WorkTypes, TJsonRead.Text(TJSONObject(mItem), 'name'));
        end;
      end;
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasYouTrackParse.ParseDescription(const AJson: string; out AText: string): Boolean;
var
  mValue: TJSONValue;
begin
  AText := '';
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := (mValue is TJSONObject) and (TJsonRead.Text(TJSONObject(mValue), 'idReadable') <> '');
    if Result then
    begin
      AText := TJsonRead.Text(TJSONObject(mValue), 'description');
    end;
  finally
    mValue.Free;
  end;
end;

/// <summary>Kennung samt Richtung ("80-1s", "81-2t"), mit der ein Linktyp die Art AKind ergibt; AKnownOnly nur
/// für Typen mit bekanntem Namen (Depend, Subtask). False ohne.</summary>
function LinkTypeId(AType: TJSONObject; AKind: TAtlasTrackerLinkKind; AKnownOnly: Boolean; out AId: string): Boolean;
const
  cKnownLinkTypes: array[0..3] of string = ('Depend', 'Subtask', 'Abhängigkeit', 'Unteraufgabe');
  cDirections: array[0..1] of string = ('OUTWARD', 'INWARD');
  cSuffixes: array[0..1] of string = ('s', 't');
var
  mSide: Integer;
begin
  AId := '';
  Result := False;
  if (TJsonRead.Text(AType, 'id') = '') or
    (AKnownOnly and not TAtlasYouTrackJson.IsOneOf(TJsonRead.Text(AType, 'name'), cKnownLinkTypes)) then
  begin
    Exit;
  end;
  for mSide := 0 to 1 do
  begin
    if TypeKind(AType, cDirections[mSide]) = AKind then
    begin
      AId := TJsonRead.Text(AType, 'id') + cSuffixes[mSide];
      Exit(True);
    end;
  end;
end;

/// <summary>Erster Typ der Liste, der passt (siehe LinkTypeId).</summary>
function FirstLinkTypeId(ATypes: TJSONArray; AKind: TAtlasTrackerLinkKind; AKnownOnly: Boolean;
  out AId: string): Boolean;
var
  mItem: TJSONValue;
begin
  AId := '';
  Result := False;
  for mItem in ATypes do
  begin
    if (mItem is TJSONObject) and LinkTypeId(TJSONObject(mItem), AKind, AKnownOnly, AId) then
    begin
      Exit(True);
    end;
  end;
end;

class function TAtlasYouTrackParse.ParseLinkType(const AJson: string; AKind: TAtlasTrackerLinkKind;
  out AId: string): Boolean;
var
  mValue: TJSONValue;
begin
  AId := '';
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    // Erst die Typen mit bekanntem Namen (Depend, Subtask), dann alle, deren Beschriftungen passen.
    Result := (mValue is TJSONArray) and (FirstLinkTypeId(TJSONArray(mValue), AKind, True, AId) or
      FirstLinkTypeId(TJSONArray(mValue), AKind, False, AId));
  finally
    mValue.Free;
  end;
end;

class function TAtlasYouTrackParse.ParseProjectId(const AJson: string; out AId: string): Boolean;
var
  mValue: TJSONValue;
begin
  AId := '';
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if (mValue is TJSONObject) and (TJSONObject(mValue).Values['project'] is TJSONObject) then
    begin
      AId := TJsonRead.Text(TJSONObject(TJSONObject(mValue).Values['project']), 'id');
    end;
  finally
    mValue.Free;
  end;
  Result := AId <> '';
end;

class function TAtlasYouTrackParse.ParseCreatedKey(const AJson: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if mValue is TJSONObject then
    begin
      Result := Trim(TJsonRead.Text(TJSONObject(mValue), 'idReadable'));
    end;
  finally
    mValue.Free;
  end;
  if not TAtlasYouTrackJson.ValidKey(Result) then
  begin
    Result := '';
  end;
end;

/// <summary>Erste Zeile eines Texts ohne Wagenrücklauf.</summary>
function FirstLine(const AText: string): string;
var
  mBreak: Integer;
begin
  Result := StringReplace(AText, #13, '', [rfReplaceAll]);
  mBreak := Pos(#10, Result);
  if mBreak > 0 then
  begin
    Result := Copy(Result, 1, mBreak - 1);
  end;
end;

/// <summary>Eine VCS-Änderung; False ohne Version und Text.</summary>
function VcsChangeOf(AItem: TJSONObject; out AChange: TAtlasTrackerVcsChange): Boolean;
var
  mUser: TJSONValue;
begin
  AChange := Default(TAtlasTrackerVcsChange);
  AChange.Version := Trim(TJsonRead.Text(AItem, 'version'));
  AChange.Text := TAtlasYouTrackJson.Shorten(FirstLine(TJsonRead.Text(AItem, 'text')),
    TAtlasTrackerIssue.cMaxTitle);
  AChange.Date := TAtlasYouTrackJson.TimeOf(AItem, 'date');
  mUser := AItem.Values['user'];
  if mUser is TJSONObject then
  begin
    AChange.Author := TAtlasYouTrackJson.FirstText(TJSONObject(mUser), 'fullName', 'login');
  end;
  Result := (AChange.Version <> '') or (AChange.Text <> '');
end;

/// <summary>Neueste zuerst; bei gleicher Zeit nach Version, damit die Reihenfolge feststeht.</summary>
function NewestFirst: IComparer<TAtlasTrackerVcsChange>;
begin
  Result := TComparer<TAtlasTrackerVcsChange>.Construct(
    function(const ALeft, ARight: TAtlasTrackerVcsChange): Integer
    begin
      if ALeft.Date > ARight.Date then
      begin
        Result := -1;
      end
      else if ALeft.Date < ARight.Date then
      begin
        Result := 1;
      end
      else
      begin
        Result := CompareStr(ALeft.Version, ARight.Version);
      end;
    end);
end;

class function TAtlasYouTrackParse.ParseVcsChanges(const AJson: string;
  out AChanges: TArray<TAtlasTrackerVcsChange>): Boolean;
var
  mValue, mItem: TJSONValue;
  mChange: TAtlasTrackerVcsChange;
  mList: TList<TAtlasTrackerVcsChange>;
begin
  AChanges := nil;
  mValue := TJSONObject.ParseJSONValue(AJson);
  mList := TList<TAtlasTrackerVcsChange>.Create;
  try
    Result := mValue is TJSONArray;
    if not Result then
    begin
      Exit;
    end;
    for mItem in TJSONArray(mValue) do
    begin
      if (mItem is TJSONObject) and VcsChangeOf(TJSONObject(mItem), mChange) then
      begin
        mList.Add(mChange);
      end;
    end;
    mList.Sort(NewestFirst());
    if mList.Count > TAtlasTrackerDevelopment.cMaxChanges then
    begin
      mList.Count := TAtlasTrackerDevelopment.cMaxChanges;
    end;
    AChanges := mList.ToArray;
  finally
    mList.Free;
    mValue.Free;
  end;
end;

class function TAtlasYouTrackParse.ParseChangedIssues(const AJson: string; ASince: TDateTime;
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
    begin
      Exit;
    end;
    Result := True;
    for mItem in TJSONArray(mValue) do
    begin
      if not (mItem is TJSONObject) then
      begin
        Continue;
      end;
      mIssue := TAtlasTrackerChange.Create(Trim(TJsonRead.Text(TJSONObject(mItem), 'idReadable')),
        TAtlasTrackerChangeKind.Other, '', TAtlasYouTrackJson.TimeOf(TJSONObject(mItem), 'updated'));
      mIssue.Title := TAtlasYouTrackJson.Shorten(TJsonRead.Text(TJSONObject(mItem), 'summary'),
        TAtlasTrackerIssue.cMaxTitle);
      if TAtlasYouTrackJson.ValidKey(mIssue.Key) and (mIssue.Time > ASince) then
      begin
        AIssues := AIssues + [mIssue];
      end;
    end;
  finally
    mValue.Free;
  end;
end;

/// <summary>Art einer Aktivität: Kommentar, Zuständig oder Zustand; False für andere Felder.</summary>
function ActivityKind(AObject: TJSONObject; out AKind: TAtlasTrackerChangeKind): Boolean;
var
  mCategory, mField: string;
begin
  mCategory := '';
  if AObject.Values['category'] is TJSONObject then
  begin
    mCategory := TJsonRead.Text(TJSONObject(AObject.Values['category']), 'id');
  end;
  mField := '';
  if AObject.Values['field'] is TJSONObject then
  begin
    mField := Trim(TJsonRead.Text(TJSONObject(AObject.Values['field']), 'name'));
  end;
  AKind := TAtlasTrackerChangeKind.Other;
  if SameText(mCategory, 'CommentsCategory') then
  begin
    AKind := TAtlasTrackerChangeKind.Comment;
  end
  else if TAtlasYouTrackJson.IsOneOf(mField, ['Assignee', 'Zuständig', 'Bearbeiter', 'Verantwortlich']) then
  begin
    AKind := TAtlasTrackerChangeKind.Assigned;
  end
  else if TAtlasYouTrackJson.IsOneOf(mField, ['State', 'Status', 'Zustand']) then
  begin
    AKind := TAtlasTrackerChangeKind.State;
  end;
  Result := AKind <> TAtlasTrackerChangeKind.Other;
end;

/// <summary>True, wenn unter den hinzugefügten Benutzern AMe ist.</summary>
function AddsMe(AAdded: TJSONArray; const AMe: string): Boolean;
var
  mEntry: TJSONValue;
begin
  Result := False;
  if AMe = '' then
  begin
    Exit;
  end;
  for mEntry in AAdded do
  begin
    if (mEntry is TJSONObject) and SameText(TJsonRead.Text(TJSONObject(mEntry), 'login'), AMe) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Autor und Wert einer gemeldeten Aktivität an AChange.</summary>
procedure FillActivity(AObject: TJSONObject; AAdded: TJSONArray; const AMe: string; var AChange: TAtlasTrackerChange);
var
  mAuthor: TJSONObject;
begin
  if AObject.Values['author'] is TJSONObject then
  begin
    mAuthor := TJSONObject(AObject.Values['author']);
    AChange.Author := Trim(TJsonRead.Text(mAuthor, 'login'));
    AChange.AuthorName := TAtlasYouTrackJson.Shorten(TJsonRead.Text(mAuthor, 'fullName'),
      TAtlasTrackerTextLimits.cPerson);
  end;
  if AChange.Kind <> TAtlasTrackerChangeKind.Comment then
  begin
    AChange.Value := TAtlasYouTrackJson.ValueText(AAdded);
  end;
  AChange.ToMe := (AChange.Kind = TAtlasTrackerChangeKind.Assigned) and AddsMe(AAdded, AMe);
end;

/// <summary>Eine gemeldete Aktivität; False ohne Hinzugefügtes (entfernte Kommentare und geleerte Felder melden
/// nichts) und für andere Felder.</summary>
function ActivityOf(AObject: TJSONObject; const AKey, AMe: string; out AChange: TAtlasTrackerChange): Boolean;
var
  mAdded: TJSONValue;
  mKind: TAtlasTrackerChangeKind;
begin
  mAdded := AObject.Values['added'];
  Result := (mAdded is TJSONArray) and (TJSONArray(mAdded).Count > 0) and ActivityKind(AObject, mKind);
  if Result then
  begin
    AChange := TAtlasTrackerChange.Create(AKey, mKind, '', TAtlasYouTrackJson.TimeOf(AObject, 'timestamp'));
    FillActivity(AObject, TJSONArray(mAdded), AMe, AChange);
  end;
end;

class function TAtlasYouTrackParse.ParseActivities(const AJson, AKey, ATitle, AMe: string; ASince: TDateTime;
  out AChanges: TArray<TAtlasTrackerChange>): Boolean;
var
  mValue, mItem: TJSONValue;
  mChange: TAtlasTrackerChange;
begin
  AChanges := nil;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := mValue is TJSONArray;
    if not Result then
    begin
      Exit;
    end;
    for mItem in TJSONArray(mValue) do
    begin
      if (mItem is TJSONObject) and ActivityOf(TJSONObject(mItem), AKey, AMe, mChange) and (mChange.Time > ASince) then
      begin
        mChange.Title := ATitle;
        AChanges := AChanges + [mChange];
      end;
    end;
  finally
    mValue.Free;
  end;
end;

end.
