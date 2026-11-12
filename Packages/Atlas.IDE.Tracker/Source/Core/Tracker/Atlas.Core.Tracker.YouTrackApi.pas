unit Atlas.Core.Tracker.YouTrackApi;

// Adressen und Anfragen der YouTrack-REST-API (#765), ohne Netz und daher
// testbar, für den Anbieter (Providers.YouTrack) und sein Board
// (YouTrackBoards): Adressen, Felder der Abfragen, Zuordnung von HTTP-Status
// zu Fehlern und der Schreibweg über Befehle (#1266). TAtlasYouTrackBodies
// baut die Inhalte schreibender Anfragen.
// Unter einer Zustandsmaschine (#1569, #2122) gilt im Befehl der Name des
// Übergangs, nicht der Zielwert; ApplyChange löst deshalb einen Übergang
// (TAtlasTrackerWrite.Transition) über POST <url>/api/issues/<Kennung>/
// fields/<Feld-ID> aus, wie das Board von YouTrack. Kommentar und
// Zuständigkeit gehen vorher als eigener Befehl bzw. Kommentar hinaus.

interface

uses
  System.SysUtils,
  System.Diagnostics,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract;

type
  TAtlasYouTrackApi = class
  public const
    cProviderName = 'youtrack';
    /// <summary>Vorgabe der Abfrage „Meine Issues“.</summary>
    cDefaultQuery = 'for: me #Unresolved';
    cFields = 'idReadable,numberInProject,summary,customFields(name,value(name,presentation,login,fullName))';
    cLocalePath = '/api/admin/globalSettings/localeSettings?fields=locale(id,language,locale)';
    /// <summary>Felder der Vorschau (#1264) ohne Kommentare.</summary>
    cDetailFields = 'idReadable,numberInProject,summary,description,created,updated,' +
      'customFields(name,value(name,presentation,login,fullName)),tags(name),' +
      'attachments(name,size,url,mimeType,removed),' +
      'links(direction,linkType(name,localizedName,sourceToTarget,localizedSourceToTarget,targetToSource,' +
      'localizedTargetToSource,aggregation),issues(idReadable,summary,resolved,customFields(name,value(name))))';
    cCommentFields = 'comments(text,created,deleted,author(login,fullName))';
    /// <summary>Felder der Projekte für die Klapplisten (#1266).</summary>
    cProjectFields = 'shortName,customFields(field(name,fieldType(id)),bundle(values(name,archived)))';
    /// <summary>Höchstens so viele Werte je Klappliste.</summary>
    cMaxValues = 200;
    /// <summary>Felder der Zeiterfassung eines Projekts (#1267).</summary>
    cTimeSettingsFields = 'enabled,workItemTypes(name)';
    /// <summary>Felder der Linktypen (#1279).</summary>
    cLinkTypeFields = 'id,name,localizedName,sourceToTarget,localizedSourceToTarget,targetToSource,' +
      'localizedTargetToSource,aggregation';
    /// <summary>Felder der VCS-Änderungen (#1269).</summary>
    cVcsChangeFields = 'version,text,date,user(login,fullName)';
    /// <summary>Felder der Änderungsabfrage (#1271).</summary>
    cChangeIssueFields = 'idReadable,summary,updated';
    cActivityFields = 'timestamp,author(login,fullName),category(id),field(name),' +
      'added(id,name,login,fullName,text,presentation),removed(id,name,login,fullName,presentation)';
    cActivityCategories = 'CommentsCategory,CustomFieldCategory';
    /// <summary>Höchstens so viele geänderte Issues je Abfrage bekommen ihre Einzelheiten.</summary>
    cMaxChangedIssues = 20;
    /// <summary>$type eines Feldes unter einer Zustandsmaschine (#1569).</summary>
    cStateMachineType = 'StateMachineIssueCustomField';
    /// <summary>Felder der Regeln des Zustandsfeldes eines Issues (#2122).</summary>
    cStateRuleFields = 'idReadable,customFields(name,id,value(name),possibleEvents(id,presentation))';
    /// <summary>Bereich der HTTP-Status, die ein Schreiben bestätigen.</summary>
    cStatusOkFirst = 200;
    cStatusOkLast = 299;
  public
    /// <summary>Abfrage, wie sie an YouTrack geht (mit "project: …").</summary>
    class function FullQuery(const ATarget: TAtlasTrackerTarget): string; static;
    class function IssuesUrl(const ATarget: TAtlasTrackerTarget; AMax: Integer): string; static;
    /// <summary>Freitextsuche der Palette (#1270): "project: &lt;Kürzel&gt; &lt;Text&gt;" ohne die Abfrage der
    /// Einstellungen;
    /// '' ohne Server oder Text.</summary>
    class function TextSearchUrl(const ATarget: TAtlasTrackerTarget; const AText: string; AMax: Integer): string;
      static;
    /// <summary>Fehler zu einem HTTP-Status außer 200.</summary>
    class function ErrorOfStatus(AStatus: Integer): TAtlasCiFetchError; static;
    /// <summary>Ein Issue mit den Feldern der Liste (#1270); '' bei ungültiger Kennung oder ohne Server.</summary>
    class function LookupUrl(const ATarget: TAtlasTrackerTarget; const AKey: string): string; static;
    /// <summary>Adresse der Vorschau eines Issues; '' bei ungültiger Kennung oder ohne Server.</summary>
    class function DetailsUrl(const ATarget: TAtlasTrackerTarget; const AKey: string; AComments: Boolean): string;
      static;
    class function IssuePage(const ATarget: TAtlasTrackerTarget; const AKey: string): string; static;
    /// <summary>Fehlertext aus einer Antwort ("error_description", sonst "error"); '' ohne.</summary>
    class function ErrorMessage(const AJson: string): string; static;
    /// <summary>Suche nach Benutzern für Erwähnungen (#1278); '' ohne Server.</summary>
    class function UsersUrl(const ATarget: TAtlasTrackerTarget; const AText: string; AMax: Integer): string; static;
    class function ApplyChange(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const AKey: string; const AChange: TAtlasTrackerWrite; ATimeoutMs: Integer): TAtlasTrackerWriteResult; static;
    /// <summary>Projektkürzel aus der Kennung ("ATL-123" → "ATL"); '' ohne Bindestrich.</summary>
    class function ProjectOfKey(const AKey: string): string; static;
    /// <summary>Die Buchung scheiterte, weil die Zeiterfassung im Projekt aus ist (400 mit Hinweis darauf).
    /// </summary>
    class function TimeTrackingOff(const AResult: TAtlasTrackerWriteResult): Boolean; static;
    /// <summary>Adresse zum Lesen (AFields "idReadable,description") bzw. Schreiben ("idReadable") der
    /// Beschreibung (#1273); '' bei ungültiger Kennung oder ohne Server.</summary>
    class function IssueUrl(const ATarget: TAtlasTrackerTarget; const AKey, AFields: string): string; static;
    /// <summary>Adresse des Feldes AFieldId am Issue AKey (Übergang auslösen, #1569); '' ohne Server oder bei
    /// ungültiger Kennung bzw. ID.</summary>
    class function FieldUrl(const ATarget: TAtlasTrackerTarget; const AKey, AFieldId: string): string; static;
    /// <summary>Adresse der Linktypen; '' ohne Server.</summary>
    class function LinkTypesUrl(const ATarget: TAtlasTrackerTarget): string; static;
    class function Rest(const AWatch: TStopwatch; ATimeoutMs: Integer): Integer; static;
    /// <summary>GET mit Fehler aus dem Status; True nur mit 200.</summary>
    class function GetText(const ATransport: IAtlasCiTransport; const AUrl: string; ATimeoutMs: Integer;
      out AText: string;
      out AError: TAtlasCiFetchError): Boolean; static;
    /// <summary>Adresse der VCS-Änderungen eines Issues (#1269); '' bei ungültiger Kennung oder ohne Server.
    /// </summary>
    class function VcsChangesUrl(const ATarget: TAtlasTrackerTarget; const AKey: string): string; static;
    /// <summary>Umfang als Suchausdruck (#1271), z. B. "(for: me or reporter: me)".</summary>
    class function ScopeQuery(AScope: TAtlasTrackerNotifyScope): string; static;
    /// <summary>Adresse der geänderten Issues ab ASince (UTC) im Umfang AScope; '' ohne Server.</summary>
    class function ChangedIssuesUrl(const ATarget: TAtlasTrackerTarget; ASince: TDateTime;
      AScope: TAtlasTrackerNotifyScope): string; static;
    /// <summary>Adresse der Aktivitäten von AKey nach ASince; '' bei ungültiger Kennung oder ohne Server.</summary>
    class function ActivitiesUrl(const ATarget: TAtlasTrackerTarget; const AKey: string; ASince: TDateTime): string;
      static;
    /// <summary>Adresse zum Hochladen von Anhängen (#1276); '' bei ungültiger Kennung oder ohne Server.</summary>
    class function AttachmentsUrl(const ATarget: TAtlasTrackerTarget; const AKey: string): string; static;
    /// <summary>Adresse für einen neuen Kommentar (#1276); '' bei ungültiger Kennung oder ohne Server.</summary>
    class function CommentsUrl(const ATarget: TAtlasTrackerTarget; const AKey: string): string; static;
  end;

  TAtlasYouTrackBodies = class
  public
    /// <summary>Name bzw. Wert für einen Befehl: mit Leerzeichen oder Klammern in geschweiften Klammern.</summary>
    class function CommandWord(const AText: string): string; static;
    /// <summary>Befehl zu AChange ohne Kommentar ("State {In Arbeit} Assignee me"); '' = nur Kommentar.</summary>
    class function CommandQuery(const AChange: TAtlasTrackerWrite): string; static;
    /// <summary>Inhalt für /api/commands.</summary>
    class function CommandJson(const AKey, AQuery, AComment: string): string; static;
    /// <summary>Inhalt des POST auf FieldUrl, der ATransition am Feld AFieldId auslöst.</summary>
    class function EventJson(const AFieldId: string; const ATransition: TAtlasTrackerTransition): string; static;
    /// <summary>Inhalt für …/comments: {"text": AText}.</summary>
    class function CommentJson(const AText: string): string; static;
    /// <summary>Körper für timeTracking/workItems (#1267); "date" = Mittag des Tages in UTC (Millisekunden), damit
    /// der Tag in jeder Zeitzone stimmt.</summary>
    class function WorkItemJson(const AItem: TAtlasTrackerWorkItem): string; static;
    /// <summary>Inhalt des POST: {"description": AText}.</summary>
    class function DescriptionJson(const AText: string): string; static;
    /// <summary>Inhalt für POST /api/issues.</summary>
    class function NewIssueBody(const AProjectId, ATitle, ADescription: string): string; static;
    /// <summary>Inhalt für POST …/links/&lt;Typ&gt;/issues.</summary>
    class function LinkBody(const AKey: string): string; static;
  end;

implementation

uses
  System.DateUtils,
  System.Generics.Collections,
  System.JSON,
  System.Math,
  System.StrUtils,
  Atlas.Core.Tracker.TimeLog,
  Atlas.Text.Uris,
  Atlas.Core.Tracker.Templates,
  Atlas.Core.Tracker.Internals.YouTrackJson,
  Atlas.Text.Json;

class function TAtlasYouTrackApi.FullQuery(const ATarget: TAtlasTrackerTarget): string;
var
  mProject: string;
begin
  Result := ATarget.Query;
  if Result = '' then
  begin
    Result := TAtlasTrackerTemplates.DefaultQuery(cProviderName, ATarget.Language);
  end;
  if Result = '' then
  begin
    Result := cDefaultQuery;
  end;
  mProject := ATarget.Project;
  if mProject = '' then
  begin
    Exit;
  end;
  // Kürzel mit Leerzeichen oder Sonderzeichen in geschweiften Klammern, wie in der Oberfläche.
  if Pos(' ', mProject) > 0 then
  begin
    mProject := '{' + mProject + '}';
  end;
  Result := 'project: ' + mProject + ' ' + Result;
end;

class function TAtlasYouTrackApi.IssuesUrl(const ATarget: TAtlasTrackerTarget; AMax: Integer): string;
var
  mLimit: Integer;
begin
  Result := '';
  if ATarget.Server = '' then
  begin
    Exit;
  end;
  mLimit := AMax;
  if mLimit < 1 then
  begin
    mLimit := 1;
  end;
  if mLimit > 100 then
  begin
    mLimit := 100;
  end;
  Result := ATarget.Url + '/api/issues?query=' + TTextUris.PercentEncode(FullQuery(ATarget)) + '&fields=' +
    TTextUris.PercentEncode(cFields) + '&$top=' + IntToStr(mLimit);
end;

class function TAtlasYouTrackApi.TextSearchUrl(const ATarget: TAtlasTrackerTarget; const AText: string;
  AMax: Integer): string;
var
  mTarget: TAtlasTrackerTarget;
begin
  Result := '';
  if Trim(AText) = '' then
  begin
    Exit;
  end;
  // Der Suchtext ersetzt die Abfrage der Einstellungen; "project: …" setzt FullQuery davor.
  mTarget := ATarget;
  mTarget.Query := Trim(AText);
  Result := IssuesUrl(mTarget, AMax);
end;

class function TAtlasYouTrackApi.ErrorOfStatus(AStatus: Integer): TAtlasCiFetchError;
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

class function TAtlasYouTrackApi.LookupUrl(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
begin
  Result := '';
  if (ATarget.Server = '') or not TAtlasYouTrackJson.ValidKey(Trim(AKey)) then
  begin
    Exit;
  end;
  Result := ATarget.Url + '/api/issues/' + Trim(AKey) + '?fields=' + TTextUris.PercentEncode(cFields);
end;

class function TAtlasYouTrackApi.DetailsUrl(const ATarget: TAtlasTrackerTarget; const AKey: string;
  AComments: Boolean): string;
var
  mFields: string;
begin
  Result := '';
  if (ATarget.Server = '') or not TAtlasYouTrackJson.ValidKey(Trim(AKey)) then
  begin
    Exit;
  end;
  mFields := cDetailFields;
  if AComments then
  begin
    mFields := mFields + ',' + cCommentFields;
  end;
  Result := ATarget.Url + '/api/issues/' + Trim(AKey) + '?fields=' + TTextUris.PercentEncode(mFields);
end;

class function TAtlasYouTrackApi.IssuePage(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
var
  mKey: string;
  mIndex: Integer;
begin
  Result := '';
  mKey := Trim(AKey);
  if (ATarget.Server = '') or (mKey = '') then
  begin
    Exit;
  end;
  for mIndex := 1 to Length(mKey) do
  begin
    if not CharInSet(mKey[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '-', '_']) then
    begin
      Exit;
    end;
  end;
  Result := ATarget.Url + '/issue/' + mKey;
end;

class function TAtlasYouTrackApi.ErrorMessage(const AJson: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if mValue is TJSONObject then
    begin
      Result := TJsonRead.Text(TJSONObject(mValue), 'error_description');
      if Result = '' then
      begin
        Result := TJsonRead.Text(TJSONObject(mValue), 'error');
      end;
    end;
  finally
    mValue.Free;
  end;
  Result := TAtlasYouTrackJson.Shorten(Result, 300);
end;

class function TAtlasYouTrackApi.UsersUrl(const ATarget: TAtlasTrackerTarget; const AText: string;
  AMax: Integer): string;
var
  mLimit: Integer;
begin
  Result := '';
  if ATarget.Server = '' then
  begin
    Exit;
  end;
  // Etwas mehr als gezeigt: Gesperrte fallen heraus.
  mLimit := EnsureRange(AMax * 2, 1, cMaxValues);
  Result := ATarget.Url + '/api/users?query=' + TTextUris.PercentEncode(Trim(AText)) + '&fields=' +
    TTextUris.PercentEncode('login,fullName,banned') + '&$top=' + IntToStr(mLimit);
end;

/// <summary>POST AUrl mit ABody; Fehler mit Status und Text von YouTrack.</summary>
function PostJson(const ASend: IAtlasCiSend; const AUrl, ABody: string; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
var
  mResponse: TAtlasCiResponse;
begin
  Result := TAtlasTrackerWriteResult.Ok;
  if not ASend.Send('POST', AUrl, ABody, ATimeoutMs, mResponse) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(mResponse.Error, 0, ''));
  end;
  if (mResponse.Status < TAtlasYouTrackApi.cStatusOkFirst) or (mResponse.Status > TAtlasYouTrackApi.cStatusOkLast) then
  begin
    Result := TAtlasTrackerWriteResult.Failed(TAtlasYouTrackApi.ErrorOfStatus(mResponse.Status), mResponse.Status,
      TAtlasYouTrackApi.ErrorMessage(mResponse.Text));
  end;
end;

/// <summary>Übergang von AChange auslösen: zuerst Zuständigkeit und Kommentar (ohne Zustand), dann das Ereignis.
/// </summary>
function FireTransition(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const ASend: IAtlasCiSend; const AKey: string; const AChange: TAtlasTrackerWrite;
  ATimeoutMs: Integer): TAtlasTrackerWriteResult;
var
  mWatch: TStopwatch;
  mBefore: TAtlasTrackerWrite;
  mUrl: string;
begin
  mUrl := TAtlasYouTrackApi.FieldUrl(ATarget, AKey, AChange.FieldId);
  if mUrl = '' then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, ''));
  end;
  mWatch := TStopwatch.StartNew;
  mBefore := AChange;
  mBefore.State := '';
  mBefore.Transition := TAtlasTrackerTransition.Create('', '');
  Result := TAtlasYouTrackApi.ApplyChange(ATarget, ATransport, AKey, mBefore, ATimeoutMs);
  if Result.Succeeded then
  begin
    Result := PostJson(ASend, mUrl, TAtlasYouTrackBodies.EventJson(AChange.FieldId, AChange.Transition),
      TAtlasYouTrackApi.Rest(mWatch, ATimeoutMs));
  end;
end;

class function TAtlasYouTrackApi.ApplyChange(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; const AChange: TAtlasTrackerWrite; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
var
  mSend: IAtlasCiSend;
  mQuery, mUrl, mBody: string;
begin
  Result := TAtlasTrackerWriteResult.Ok;
  if not AChange.HasWork then
  begin
    Exit;
  end;
  if (ATarget.Server = '') or not TAtlasYouTrackJson.ValidKey(Trim(AKey)) or
    not Supports(ATransport, IAtlasCiSend, mSend) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, ''));
  end;
  if AChange.Transition.Id <> '' then
  begin
    Exit(FireTransition(ATarget, ATransport, mSend, AKey, AChange, ATimeoutMs));
  end;
  mQuery := TAtlasYouTrackBodies.CommandQuery(AChange);
  if mQuery = '' then
  begin
    mUrl := ATarget.Url + '/api/issues/' + Trim(AKey) + '/comments?fields=id';
    mBody := TAtlasYouTrackBodies.CommentJson(AChange.Comment);
  end
  else
  begin
    mUrl := ATarget.Url + '/api/commands';
    mBody := TAtlasYouTrackBodies.CommandJson(AKey, mQuery, AChange.Comment);
  end;
  Result := PostJson(mSend, mUrl, mBody, ATimeoutMs);
end;


class function TAtlasYouTrackApi.ProjectOfKey(const AKey: string): string;
var
  mDash: Integer;
begin
  Result := '';
  mDash := LastDelimiter('-', Trim(AKey));
  if mDash > 1 then
  begin
    Result := Copy(Trim(AKey), 1, mDash - 1);
  end;
end;

class function TAtlasYouTrackApi.TimeTrackingOff(const AResult: TAtlasTrackerWriteResult): Boolean;
begin
  Result := (AResult.Status = 400) and (ContainsText(AResult.Message, 'time tracking') or
    ContainsText(AResult.Message, 'timetracking') or ContainsText(AResult.Message, 'Zeiterfassung'));
end;

class function TAtlasYouTrackApi.IssueUrl(const ATarget: TAtlasTrackerTarget; const AKey,
  AFields: string): string;
begin
  Result := '';
  if (ATarget.Server = '') or not TAtlasYouTrackJson.ValidKey(Trim(AKey)) then
  begin
    Exit;
  end;
  Result := ATarget.Url + '/api/issues/' + Trim(AKey) + '?fields=' + TTextUris.PercentEncode(AFields);
end;


class function TAtlasYouTrackApi.FieldUrl(const ATarget: TAtlasTrackerTarget; const AKey, AFieldId: string): string;
begin
  Result := '';
  if (ATarget.Server <> '') and TAtlasYouTrackJson.ValidKey(Trim(AKey)) and
    TAtlasYouTrackJson.ValidKey(AFieldId) then
  begin
    Result := ATarget.Url + '/api/issues/' + Trim(AKey) + '/fields/' + AFieldId + '?fields=id';
  end;
end;

class function TAtlasYouTrackApi.LinkTypesUrl(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := '';
  if ATarget.Server <> '' then
  begin
    Result := ATarget.Url + '/api/issueLinkTypes?fields=' + TTextUris.PercentEncode(cLinkTypeFields);
  end;
end;

class function TAtlasYouTrackApi.Rest(const AWatch: TStopwatch; ATimeoutMs: Integer): Integer;
var
  mRest: Int64;
begin
  mRest := ATimeoutMs - AWatch.ElapsedMilliseconds;
  Result := 0;
  if mRest > 0 then
  begin
    Result := Integer(mRest);
  end;
end;

/// <summary>GET mit Fehler aus dem Status; True nur mit 200.</summary>
class function TAtlasYouTrackApi.GetText(const ATransport: IAtlasCiTransport; const AUrl: string; ATimeoutMs: Integer;
  out AText: string;
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
  begin
    Exit;
  end;
  if mStatus <> 200 then
  begin
    AError := ErrorOfStatus(mStatus);
    Exit;
  end;
  Result := True;
end;

class function TAtlasYouTrackApi.VcsChangesUrl(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
begin
  Result := '';
  if (ATarget.Server = '') or not TAtlasYouTrackJson.ValidKey(Trim(AKey)) then
  begin
    Exit;
  end;
  Result := ATarget.Url + '/api/issues/' + Trim(AKey) + '/vcsChanges?fields=' +
    TTextUris.PercentEncode(cVcsChangeFields) + '&$top=' + IntToStr(TAtlasTrackerDevelopment.cMaxChanges);
end;

class function TAtlasYouTrackApi.ScopeQuery(AScope: TAtlasTrackerNotifyScope): string;
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

class function TAtlasYouTrackApi.ChangedIssuesUrl(const ATarget: TAtlasTrackerTarget; ASince: TDateTime;
  AScope: TAtlasTrackerNotifyScope): string;
var
  mQuery: string;
begin
  Result := '';
  if ATarget.Server = '' then
  begin
    Exit;
  end;
  // Einen Tag früher: Der Server wertet den Tag in seiner Zeitzone; genau gefiltert wird mit "updated".
  mQuery := ScopeQuery(AScope) + ' updated: ' + FormatDateTime('yyyy"-"mm"-"dd', ASince - 1) + ' .. *';
  Result := ATarget.Url + '/api/issues?query=' + TTextUris.PercentEncode(mQuery) + '&fields=' +
    TTextUris.PercentEncode(cChangeIssueFields) + '&$top=' + IntToStr(cMaxChangedIssues * 2);
end;

class function TAtlasYouTrackApi.ActivitiesUrl(const ATarget: TAtlasTrackerTarget; const AKey: string;
  ASince: TDateTime): string;
begin
  Result := '';
  if (ATarget.Server = '') or not TAtlasYouTrackJson.ValidKey(Trim(AKey)) then
  begin
    Exit;
  end;
  Result := ATarget.Url + '/api/issues/' + Trim(AKey) + '/activities?categories=' + cActivityCategories +
    '&start=' + IntToStr(TAtlasYouTrackJson.MsOf(ASince) + 1) + '&fields=' + TTextUris.PercentEncode(cActivityFields) + '&$top=100';
end;

class function TAtlasYouTrackApi.AttachmentsUrl(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
begin
  Result := '';
  if (ATarget.Server <> '') and TAtlasYouTrackJson.ValidKey(Trim(AKey)) then
  begin
    Result := ATarget.Url + '/api/issues/' + Trim(AKey) + '/attachments?fields=id,name';
  end;
end;

class function TAtlasYouTrackApi.CommentsUrl(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
begin
  Result := '';
  if (ATarget.Server <> '') and TAtlasYouTrackJson.ValidKey(Trim(AKey)) then
  begin
    Result := ATarget.Url + '/api/issues/' + Trim(AKey) + '/comments?fields=id';
  end;
end;

class function TAtlasYouTrackBodies.CommandWord(const AText: string): string;
var
  mIndex: Integer;
  mPlain: Boolean;
begin
  Result := Trim(AText);
  mPlain := Result <> '';
  for mIndex := 1 to Length(Result) do
  begin
    if (Ord(Result[mIndex]) < 128) and
      not CharInSet(Result[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', '@']) then
    begin
      mPlain := False;
    end;
  end;
  // Umlaute stehen in der Oberfläche ohne Klammern; Leerzeichen und Satzzeichen brauchen sie.
  if not mPlain then
  begin
    Result := '{' + StringReplace(StringReplace(Result, '{', '', [rfReplaceAll]), '}', '', [rfReplaceAll]) + '}';
  end;
end;

class function TAtlasYouTrackBodies.CommandQuery(const AChange: TAtlasTrackerWrite): string;
var
  mField: string;
begin
  Result := '';
  if Trim(AChange.State) <> '' then
  begin
    mField := Trim(AChange.StateField);
    if mField = '' then
    begin
      mField := 'State';
    end;
    Result := CommandWord(mField) + ' ' + CommandWord(AChange.State);
  end;
  if AChange.Assign = TAtlasTrackerAssign.Keep then
  begin
    Exit;
  end;
  if (AChange.Assign = TAtlasTrackerAssign.User) and (Trim(AChange.Assignee) = '') then
  begin
    Exit;
  end;
  mField := Trim(AChange.AssigneeField);
  if mField = '' then
  begin
    mField := 'Assignee';
  end;
  if Result <> '' then
  begin
    Result := Result + ' ';
  end;
  if AChange.Assign = TAtlasTrackerAssign.Me then
  begin
    Result := Result + CommandWord(mField) + ' me';
  end
  else
  begin
    Result := Result + CommandWord(mField) + ' ' + CommandWord(AChange.Assignee);
  end;
end;

class function TAtlasYouTrackBodies.CommandJson(const AKey, AQuery, AComment: string): string;
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
    begin
      mObject.AddPair('comment', AComment);
    end;
    Result := mObject.ToJSON;
  finally
    mObject.Free;
  end;
end;

class function TAtlasYouTrackBodies.EventJson(const AFieldId: string;
  const ATransition: TAtlasTrackerTransition): string;
var
  mObject, mEvent: TJSONObject;
begin
  mObject := TJSONObject.Create;
  try
    mEvent := TJSONObject.Create;
    mEvent.AddPair('id', ATransition.Id);
    mEvent.AddPair('presentation', ATransition.Name);
    mEvent.AddPair('$type', 'Event');
    mObject.AddPair('event', mEvent);
    mObject.AddPair('id', AFieldId);
    mObject.AddPair('$type', TAtlasYouTrackApi.cStateMachineType);
    Result := mObject.ToJSON;
  finally
    mObject.Free;
  end;
end;

class function TAtlasYouTrackBodies.CommentJson(const AText: string): string;
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

class function TAtlasYouTrackBodies.WorkItemJson(const AItem: TAtlasTrackerWorkItem): string;
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
    begin
      mObject.AddPair('text', AItem.Text);
    end;
    Result := mObject.ToJSON;
  finally
    mObject.Free;
  end;
end;

class function TAtlasYouTrackBodies.DescriptionJson(const AText: string): string;
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

class function TAtlasYouTrackBodies.NewIssueBody(const AProjectId, ATitle, ADescription: string): string;
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
    begin
      mRoot.AddPair('description', ADescription);
    end;
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasYouTrackBodies.LinkBody(const AKey: string): string;
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

end.
