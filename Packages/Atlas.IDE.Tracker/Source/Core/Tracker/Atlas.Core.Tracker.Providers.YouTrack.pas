unit Atlas.Core.Tracker.Providers.YouTrack;

// Issue-Tracker YouTrack (#765), Cloud und Server, ohne VCL und Open Tools
// API. Das Netz kommt über IAtlasCiTransport von außen.
// - Anmeldung mit permanentem Token („Authorization: Bearer perm-…“, älter perm:…), nur an
//   den eingetragenen Server.
// - Issues: GET <url>/api/issues?query=<Abfrage>&fields=idReadable,
//   numberInProject,summary,customFields(name,value(name,presentation))
//   &$top=<Max>. Die Abfrage ist die Suchsprache der YouTrack-Oberfläche
//   (Vorgabe "for: me #Unresolved", bei erkannter Sprache „Mir zugewiesen“
//   aus Atlas.Core.Tracker.Templates, #1263); mit Projektkürzel aus .atlas steht
//   "project: <Kürzel>" davor, damit die Liste dieselben Issues zeigt wie die
//   Suche dort im Projekt.
// - Felder: Zustand (State, Status, Zustand), Priorität (Priority,
//   Priorität) und Sprint bzw. Board (Sprint, Sprints, Board); Werte als
//   Objekt oder Liste mit "name" (bzw. "presentation").
// - Browser: <url>/issue/<Kennung>.
// - Verbindung prüfen (#1260): GET <url>/api/users/me?fields=login.
// - Sprache der Oberfläche (#1263): GET
//   <url>/api/admin/globalSettings/localeSettings?fields=locale(id,language,locale)
//   (braucht Leserecht auf die globalen Einstellungen).
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
// - Übergänge (#2122, IAtlasTrackerStateRules): Steht das Zustandsfeld unter
//   einer Zustandsmaschine, liest StateRules die erlaubten Übergänge des
//   Issues (GET <url>/api/issues/<Kennung>?fields=customFields(name,id,
//   value(name),possibleEvents(id,presentation))); Apply löst einen Übergang
//   statt eines Befehls mit dem Wert aus (TAtlasYouTrackApi.ApplyChange).
// - Felder beim Beenden (#2123, IAtlasTrackerFields): Namen und Werte aus
//   /api/admin/projects (Projekt aus .atlas, sonst aus der Kennung); ein Feld
//   setzt ein Befehl „Feld Wert“ über /api/commands. Lehnt eine Regel des
//   Ablaufs ab (400), steht ihr Text in der Antwort.
// - Zeit buchen (#1267, IAtlasTrackerTimeWriter): POST
//   <url>/api/issues/<Kennung>/timeTracking/workItems mit
//   {"duration": {"presentation": "1h 25m"}, "date": <ms>, "type": {"name":
//   …}, "text": …}; Zeiterfassung und Arbeitstypen aus
//   /api/admin/projects/<Kürzel>/timeTrackingSettings, ohne Leserecht die
//   allgemeinen Arbeitstypen (/api/admin/timeTrackingSettings/workItemTypes).
// - Checklisten (#1273, IAtlasTrackerDescriptions): Beschreibung ungekürzt aus
//   GET <url>/api/issues/<Kennung>?fields=idReadable,description, zurück mit
//   POST <url>/api/issues/<Kennung>?fields=idReadable und {"description": …}.
// - Verknüpfungen (#1279): Linktyp mit Namen und Beschriftungen (auch
//   lokalisiert) und „aggregation“, je Issue resolved und Zustand; die Art
//   bestimmt TAtlasTrackerLinks.YouTrackKind.
// - Unteraufgabe anlegen (#1279): GET /api/issues/<Eltern>?fields=project(id),
//   POST /api/issues mit Projekt, summary und description, dann
//   POST /api/issues/<Eltern>/links/<Linktyp><s|t>/issues mit {"idReadable"}.
//   Den Linktyp (Subtask bzw. Depend) liefert /api/issueLinkTypes; s = das
//   Issue im Pfad ist die Quelle, t = das Ziel.
// - Palettensuche (#1270): GET <url>/api/issues?query=project: <Kürzel>
//   <Text>&fields=…&$top=<Max> (Felder wie die Liste, dazu Zuständig); eine
//   Kennung liest Lookup direkt über /api/issues/<Kennung>?fields=….
// - Benutzer für @-Erwähnungen (#1278, IAtlasTrackerPeople): GET
//   <url>/api/users?query=<Text>&fields=login,fullName,banned&$top=<Max>;
//   gesperrte Benutzer entfallen, passende Anmeldenamen kommen zuerst.
// - Entwicklung (#1269): GET <url>/api/issues/<Kennung>/vcsChanges?fields=
//   version,text,date,user(login,fullName)&$top=100, die Änderungen, die die
//   VCS-Anbindung von YouTrack dem Issue zugeordnet hat. Ohne Anbindung
//   (404) ist die Liste leer, kein Fehler. Pull Requests kennt YouTrack hier
//   nicht.
// - Änderungen (#1271): GET <url>/api/issues?query=<Umfang> updated: <Tag>
//   .. *&fields=idReadable,summary,updated über alle Projekte des Servers
//   (Umfang "for: me", dazu "reporter: me", dazu "has: star"; der Tag liegt
//   einen Tag vor dem letzten Stand, damit die Zeitzone des Servers nichts
//   verschluckt, genau gefiltert wird mit "updated"), dann je Treffer
//   GET <url>/api/issues/<Kennung>/activities?categories=CommentsCategory,
//   CustomFieldCategory&start=<ms> ab dem letzten Stand: neue Kommentare,
//   Zuständig und Zustand.
// - Anhängen (#1276, IAtlasTrackerAttach): POST <url>/api/issues/<Kennung>/
//   attachments als multipart/form-data, danach POST …/comments mit
//   {"text": …}; der Kommentar bettet die Bilder ein (![](Name)) und
//   verweist auf die übrigen Dateien ([Name](Name)).
// - Ablauf-Karte (#2125, IAtlasTrackerFlow): Zustandswechsel des Projekts
//   über /api/activitiesPage, siehe Atlas.Core.Tracker.YouTrackFlow.


interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.YouTrackApi,
  Atlas.Core.Tracker.Board,
  Atlas.Core.Tracker.Sprint,
  Atlas.Core.Tracker.FlowMap,
  Atlas.Core.Tracker.Attach;

type
  TAtlasYouTrackTracker = class(TInterfacedObject, IAtlasTrackerProvider, IAtlasTrackerWriter,
    IAtlasTrackerTimeWriter, IAtlasTrackerDescriptions, IAtlasTrackerLinkWriter, IAtlasTrackerBoards,
    IAtlasTrackerWorkDays, IAtlasTrackerPeople, IAtlasTrackerAttach, IAtlasTrackerStateRules, IAtlasTrackerFields,
    IAtlasTrackerFlow)
  public const
    cProviderName = TAtlasYouTrackApi.cProviderName;
    cQuery = TAtlasYouTrackApi.cDefaultQuery;
    cMaxValues = TAtlasYouTrackApi.cMaxValues;
  public
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
    function ListUrl(const ATarget: TAtlasTrackerTarget; AMax: Integer): string;
    function SentQuery(const ATarget: TAtlasTrackerTarget): string;
    function ParseList(const AText: string; AMax: Integer; out AIssues: TArray<TAtlasTrackerIssue>): Boolean;
    function LocaleUrl(const ATarget: TAtlasTrackerTarget): string;
    function Details(const ACall: TAtlasTrackerCall; const AKey: string; AComments: Boolean;
      out ADetails: TAtlasTrackerDetails; out AError: TAtlasCiFetchError): Boolean;
    { IAtlasTrackerWriter }
    function Apply(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      const AChange: TAtlasTrackerWrite; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
    function Values(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      AKind: TAtlasTrackerValueKind; const AField: string; ATimeoutMs: Integer;
      out AValues: TArray<string>): TAtlasTrackerWriteResult;
    { IAtlasTrackerStateRules (#2122): über TAtlasYouTrackWorkflow }
    function StateRules(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey,
      AField: string; ATimeoutMs: Integer; out ARules: TAtlasTrackerStateRules): TAtlasTrackerWriteResult;
    { IAtlasTrackerFields (#2123) }
    function FieldValues(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey,
      AField: string; ATimeoutMs: Integer; out AValues: TArray<string>): TAtlasTrackerWriteResult;
    function SetField(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey, AField,
      AValue: string; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
    { IAtlasTrackerTimeWriter }
    function TimeSettings(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      ATimeoutMs: Integer; out ASettings: TAtlasTrackerTimeSettings): TAtlasTrackerWriteResult;
    function BookTime(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      const AItem: TAtlasTrackerWorkItem; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
    function IsTrackingOff(const AResult: TAtlasTrackerWriteResult): Boolean;
    { IAtlasTrackerDescriptions }
    function Description(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      ATimeoutMs: Integer; out AText: string; out AError: TAtlasCiFetchError): Boolean;
    function UpdateDescription(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const AKey, AText: string; ATimeoutMs: Integer; out AError: TAtlasCiFetchError): Boolean;
    { IAtlasTrackerLinkWriter }
    function CreateSubtask(const ACall: TAtlasTrackerCall; const AParentKey, ATitle,
      ADescription: string; out AKey: string; out AError: TAtlasCiFetchError): Boolean;
    function AddLink(const ACall: TAtlasTrackerCall; const AKey: string; AKind: TAtlasTrackerLinkKind;
      const AOtherKey: string; out AError: TAtlasCiFetchError): Boolean;
    { IAtlasTrackerBoards (#1272): über TAtlasYouTrackBoards }
    function LoadBoard(const ARequest: TAtlasBoardRequest; out ASnapshot: TAtlasBoardSnapshot;
      out AError: TAtlasCiFetchError): Boolean;
    function MoveCard(const AMove: TAtlasBoardMove; const ASnapshot: TAtlasBoardSnapshot): TAtlasTrackerWriteResult;
    { IAtlasTrackerWorkDays (#1277): über TAtlasYouTrackBoards }
    function WorkDays(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; ATimeoutMs: Integer;
      out ADays: TArray<Integer>): Boolean;
    { IAtlasTrackerFlow (#2125): über TAtlasYouTrackFlow }
    function LoadFlow(const ARequest: TAtlasFlowRequest; out AData: TAtlasFlowData;
      out AError: TAtlasCiFetchError): Boolean;
    function Search(const ACall: TAtlasTrackerCall; const AText: string; AMax: Integer;
      out AIssues: TArray<TAtlasTrackerIssue>; out AError: TAtlasCiFetchError): Boolean;
    function Lookup(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      ATimeoutMs: Integer; out AIssue: TAtlasTrackerIssue; out AError: TAtlasCiFetchError): Boolean;
    { IAtlasTrackerPeople }
    function Users(const ACall: TAtlasTrackerCall; const AText: string; AMax: Integer;
      out AUsers: TArray<TAtlasTrackerUser>; out AError: TAtlasCiFetchError): Boolean;
    function Development(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      ATimeoutMs: Integer; out ADevelopment: TAtlasTrackerDevelopment; out AError: TAtlasCiFetchError): Boolean;
    function Changes(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; ATimeoutMs: Integer;
      var APoll: TAtlasTrackerPoll; out AChanges: TArray<TAtlasTrackerChange>; out AError: TAtlasCiFetchError): Boolean;
    { IAtlasTrackerAttach }
    function CanUpload: Boolean;
    function Upload(const ATarget: TAtlasTrackerTarget; const ASend: IAtlasCiPost; const AKey: string;
      const AFiles: TAtlasAttachFiles; ATimeoutMs: Integer; out AError: TAtlasCiFetchError): Boolean;
    function Comment(const ATarget: TAtlasTrackerTarget; const ASend: IAtlasCiPost; const AKey, AMarkdown: string;
      ATimeoutMs: Integer; out AError: TAtlasCiFetchError): Boolean;
    function CommentText(const AComment: string; const AFiles: TAtlasAttachFiles): string;
  end;

implementation

uses
  System.Diagnostics,
  System.Generics.Collections,
  System.Math,
  System.JSON,
  Atlas.Text.Uris,
  Atlas.Core.Tracker.Internals.YouTrackJson,
  Atlas.Core.Tracker.YouTrackParse,
  Atlas.Core.Tracker.YouTrackBoards,
  Atlas.Core.Tracker.YouTrackWorkflow,
  Atlas.Core.Tracker.YouTrackFlow;

function TAtlasYouTrackTracker.IssuePage(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
begin
  Result := TAtlasYouTrackApi.IssuePage(ATarget, AKey);
end;

function TAtlasYouTrackTracker.Apply(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; const AChange: TAtlasTrackerWrite; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
begin
  Result := TAtlasYouTrackApi.ApplyChange(ATarget, ATransport, AKey, AChange, ATimeoutMs);
end;

function TAtlasYouTrackTracker.StateRules(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey, AField: string; ATimeoutMs: Integer; out ARules: TAtlasTrackerStateRules): TAtlasTrackerWriteResult;
begin
  Result := TAtlasYouTrackWorkflow.Read(ATarget, ATransport, AKey, AField, ATimeoutMs, ARules);
end;

function TAtlasYouTrackTracker.FieldValues(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey, AField: string; ATimeoutMs: Integer; out AValues: TArray<string>): TAtlasTrackerWriteResult;
var
  mProject, mText: string;
  mError: TAtlasCiFetchError;
begin
  AValues := nil;
  mProject := Trim(ATarget.Project);
  if mProject = '' then
  begin
    mProject := TAtlasYouTrackApi.ProjectOfKey(AKey);
  end;
  if (mProject = '') or (ATransport = nil) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, ''));
  end;
  if not TAtlasYouTrackApi.GetText(ATransport, TAtlasYouTrackApi.ProjectFieldsUrl(ATarget), ATimeoutMs, mText,
    mError) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(mError, 0, ''));
  end;
  Result := TAtlasTrackerWriteResult.Ok;
  if not TAtlasYouTrackParse.ParseProjectFields(mText, mProject, AField, AValues) then
  begin
    Result := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 0, '');
  end;
end;

function TAtlasYouTrackTracker.SetField(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey, AField, AValue: string; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
begin
  Result := TAtlasYouTrackApi.SetField(ATarget, ATransport, AKey, AField, AValue, ATimeoutMs);
end;

function TAtlasYouTrackTracker.Name: string;
begin
  Result := TAtlasYouTrackApi.cProviderName;
end;

function TAtlasYouTrackTracker.Caption: string;
begin
  Result := 'YouTrack';
end;

function TAtlasYouTrackTracker.DefaultQuery: string;
begin
  Result := cQuery;
end;

function TAtlasYouTrackTracker.ApiServer(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := ATarget.Server;
end;

function TAtlasYouTrackTracker.Fetch(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  ATimeoutMs, AMax: Integer; out AIssues: TArray<TAtlasTrackerIssue>; out AError: TAtlasCiFetchError): Boolean;
var
  mStatus: Integer;
  mText: string;
begin
  AIssues := nil;
  AError := TAtlasCiFetchError.None;
  Result := False;
  if not ATarget.Configured or (ATransport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  if not ATransport.Get(TAtlasYouTrackApi.IssuesUrl(ATarget, AMax), ATimeoutMs, mStatus, mText, AError) then
  begin
    Exit;
  end;
  if mStatus <> 200 then
  begin
    AError := TAtlasYouTrackApi.ErrorOfStatus(mStatus);
    Exit;
  end;
  if not TAtlasYouTrackParse.ParseIssues(mText, AMax, AIssues) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  Result := True;
end;

function TAtlasYouTrackTracker.PullRequestPage(const ATarget: TAtlasTrackerTarget; ANumber: Integer): string;
begin
  Result := '';
end;

function TAtlasYouTrackTracker.ProbeUrl(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := '';
  if ATarget.Server <> '' then
  begin
    Result := ATarget.Url + '/api/users/me?fields=login';
  end;
end;

function TAtlasYouTrackTracker.ListUrl(const ATarget: TAtlasTrackerTarget; AMax: Integer): string;
begin
  Result := TAtlasYouTrackApi.IssuesUrl(ATarget, AMax);
end;

function TAtlasYouTrackTracker.SentQuery(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := TAtlasYouTrackApi.FullQuery(ATarget);
end;

function TAtlasYouTrackTracker.ParseList(const AText: string; AMax: Integer;
  out AIssues: TArray<TAtlasTrackerIssue>): Boolean;
begin
  Result := TAtlasYouTrackParse.ParseIssues(AText, AMax, AIssues);
end;

function TAtlasYouTrackTracker.LocaleUrl(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := '';
  if ATarget.Server <> '' then
  begin
    Result := ATarget.Url + TAtlasYouTrackApi.cLocalePath;
  end;
end;

function TAtlasYouTrackTracker.Details(const ACall: TAtlasTrackerCall; const AKey: string; AComments: Boolean;
  out ADetails: TAtlasTrackerDetails; out AError: TAtlasCiFetchError): Boolean;
var
  mStatus: Integer;
  mText, mUrl: string;
begin
  ADetails := TAtlasTrackerDetails.Empty;
  AError := TAtlasCiFetchError.None;
  Result := False;
  mUrl := TAtlasYouTrackApi.DetailsUrl(ACall.Target, AKey, AComments);
  if (mUrl = '') or (ACall.Transport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  if not ACall.Transport.Get(mUrl, ACall.TimeoutMs, mStatus, mText, AError) then
  begin
    Exit;
  end;
  if mStatus <> 200 then
  begin
    AError := TAtlasYouTrackApi.ErrorOfStatus(mStatus);
    Exit;
  end;
  if not TAtlasYouTrackParse.ParseDetails(mText, ACall.Target, AComments, ADetails) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  ADetails.Page := TAtlasYouTrackApi.IssuePage(ACall.Target, ADetails.Key);
  Result := True;
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
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, ''));
  end;
  if AKind = TAtlasTrackerValueKind.Users then
  begin
    mUrl := ATarget.Url + '/api/users?fields=' + TTextUris.PercentEncode('login,banned') + '&$top=' +
      IntToStr(TAtlasYouTrackApi.cMaxValues);
  end
  else if (ATarget.Project = '') and (AKind <> TAtlasTrackerValueKind.States) then
  begin
    mUrl := ATarget.Url + '/api/admin/customFieldSettings/customFields?fields=' +
      TTextUris.PercentEncode('name,fieldType(id)') + '&$top=' + IntToStr(TAtlasYouTrackApi.cMaxValues);
  end
  else
  begin
    mUrl := TAtlasYouTrackApi.ProjectFieldsUrl(ATarget);
  end;
  if not ATransport.Get(mUrl, ATimeoutMs, mStatus, mText, mError) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(mError, 0, ''));
  end;
  if mStatus <> 200 then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasYouTrackApi.ErrorOfStatus(mStatus), mStatus,
      TAtlasYouTrackApi.ErrorMessage(mText)));
  end;
  if AKind = TAtlasTrackerValueKind.Users then
  begin
    mOk := TAtlasYouTrackParse.ParseUsers(mText, AValues);
  end
  else
  begin
    mOk := TAtlasYouTrackParse.ParseFieldValues(mText, ATarget.Project, AKind, Trim(AField), AValues);
  end;
  if not mOk then
  begin
    Result := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, mStatus, '');
  end;
end;

function TAtlasYouTrackTracker.IsTrackingOff(const AResult: TAtlasTrackerWriteResult): Boolean;
begin
  Result := TAtlasYouTrackApi.TimeTrackingOff(AResult);
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
  mProject := TAtlasYouTrackApi.ProjectOfKey(AKey);
  if (ATarget.Server = '') or (ATransport = nil) or (mProject = '') then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, ''));
  end;
  mUrl := ATarget.Url + '/api/admin/projects/' + TTextUris.PercentEncode(mProject) + '/timeTrackingSettings?fields=' +
    TTextUris.PercentEncode(TAtlasYouTrackApi.cTimeSettingsFields);
  if not ATransport.Get(mUrl, ATimeoutMs, mStatus, mText, mError) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(mError, 0, ''));
  end;
  if mStatus = 200 then
  begin
    if not TAtlasYouTrackParse.ParseTimeSettings(mText, False, ASettings) then
    begin
      Result := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, mStatus, '');
    end;
    Exit;
  end;
  if (mStatus <> 403) and (mStatus <> 404) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasYouTrackApi.ErrorOfStatus(mStatus), mStatus,
      TAtlasYouTrackApi.ErrorMessage(mText)));
  end;
  // Ohne Leserecht auf das Projekt: Zeiterfassung gilt als an, Arbeitstypen allgemein (sonst frei).
  mUrl := ATarget.Url + '/api/admin/timeTrackingSettings/workItemTypes?fields=name&$top=' + IntToStr(TAtlasYouTrackApi.cMaxValues);
  if ATransport.Get(mUrl, ATimeoutMs, mStatus, mText, mError) and (mStatus = 200) and
    not TAtlasYouTrackParse.ParseTimeSettings(mText, True, ASettings) then
  begin
    ASettings.WorkTypes := nil;
  end;
end;

function TAtlasYouTrackTracker.BookTime(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; const AItem: TAtlasTrackerWorkItem; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
var
  mSend: IAtlasCiSend;
  mResponse: TAtlasCiResponse;
begin
  if AItem.Minutes <= 0 then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 0, ''));
  end;
  if (ATarget.Server = '') or not TAtlasYouTrackJson.ValidKey(Trim(AKey)) or
    not Supports(ATransport, IAtlasCiSend, mSend) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, ''));
  end;
  Result := TAtlasTrackerWriteResult.Ok;
  if not mSend.Send('POST', ATarget.Url + '/api/issues/' + Trim(AKey) + '/timeTracking/workItems?fields=id',
    TAtlasYouTrackBodies.WorkItemJson(AItem), ATimeoutMs, mResponse) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(mResponse.Error, 0, ''));
  end;
  if (mResponse.Status < 200) or (mResponse.Status > 299) then
  begin
    Result := TAtlasTrackerWriteResult.Failed(TAtlasYouTrackApi.ErrorOfStatus(mResponse.Status), mResponse.Status,
      TAtlasYouTrackApi.ErrorMessage(mResponse.Text));
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
  mUrl := TAtlasYouTrackApi.IssueUrl(ATarget, AKey, 'idReadable,description');
  if (mUrl = '') or (ATransport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  if not ATransport.Get(mUrl, ATimeoutMs, mStatus, mJson, AError) then
  begin
    Exit;
  end;
  if mStatus <> 200 then
  begin
    AError := TAtlasYouTrackApi.ErrorOfStatus(mStatus);
    Exit;
  end;
  if not TAtlasYouTrackParse.ParseDescription(mJson, AText) or
    (Length(AText) > TAtlasTrackerDetails.cMaxDescription) then
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
  mUrl: string;
  mResponse: TAtlasCiResponse;
  mSend: IAtlasCiSend;
begin
  AError := TAtlasCiFetchError.None;
  Result := False;
  mUrl := TAtlasYouTrackApi.IssueUrl(ATarget, AKey, 'idReadable');
  if (mUrl = '') or not Supports(ATransport, IAtlasCiSend, mSend) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  if Length(AText) > TAtlasTrackerDetails.cMaxDescription then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  if not mSend.Send('POST', mUrl, TAtlasYouTrackBodies.DescriptionJson(AText), ATimeoutMs, mResponse) then
  begin
    AError := mResponse.Error;
    Exit;
  end;
  if mResponse.Status <> 200 then
  begin
    AError := TAtlasYouTrackApi.ErrorOfStatus(mResponse.Status);
    Exit;
  end;
  Result := True;
end;

/// <summary>Derselbe Aufruf mit der restlichen Zeit seit AWatch.</summary>
function Later(const ACall: TAtlasTrackerCall; const AWatch: TStopwatch): TAtlasTrackerCall;
begin
  Result := TAtlasTrackerCall.Create(ACall.Target, ACall.Transport, TAtlasYouTrackApi.Rest(AWatch, ACall.TimeoutMs));
end;

/// <summary>POST an AUrl; True bei 200 oder 201 mit der Antwort in AText, sonst AError.</summary>
function PostCreated(const ACall: TAtlasTrackerCall; const AUrl, ABody: string; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
var
  mPost: IAtlasCiSend;
  mResponse: TAtlasCiResponse;
begin
  AText := '';
  Result := False;
  AError := TAtlasCiFetchError.NotConfigured;
  if not Supports(ACall.Transport, IAtlasCiSend, mPost) then
  begin
    Exit;
  end;
  if not mPost.Send('POST', AUrl, ABody, ACall.TimeoutMs, mResponse) then
  begin
    AError := mResponse.Error;
  end
  else if (mResponse.Status <> 200) and (mResponse.Status <> 201) then
  begin
    AError := TAtlasYouTrackApi.ErrorOfStatus(mResponse.Status);
  end
  else
  begin
    AText := mResponse.Text;
    AError := TAtlasCiFetchError.None;
    Result := True;
  end;
end;

/// <summary>Link des Issues AKey (Linktyp mit Richtung AType) auf AOtherKey anlegen.</summary>
function PostLink(const ACall: TAtlasTrackerCall; const AKey, AType, AOtherKey: string;
  out AError: TAtlasCiFetchError): Boolean;
var
  mText: string;
begin
  Result := PostCreated(ACall, ACall.Target.Url + '/api/issues/' + Trim(AKey) + '/links/' + AType +
    '/issues?fields=id', TAtlasYouTrackBodies.LinkBody(AOtherKey), mText, AError);
end;

/// <summary>Linktyp mit Richtung für AKind ("80-1s"); False mit AError ohne passenden Typ.</summary>
function FindLinkType(const ACall: TAtlasTrackerCall; AKind: TAtlasTrackerLinkKind; out AType: string;
  out AError: TAtlasCiFetchError): Boolean;
var
  mText: string;
begin
  AType := '';
  Result := TAtlasYouTrackApi.GetText(ACall.Transport, TAtlasYouTrackApi.LinkTypesUrl(ACall.Target), ACall.TimeoutMs,
    mText, AError);
  if Result and not TAtlasYouTrackParse.ParseLinkType(mText, AKind, AType) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Result := False;
  end;
end;

/// <summary>Projekt des übergeordneten Issues: die Unteraufgabe liegt im selben.</summary>
function ParentProject(const ACall: TAtlasTrackerCall; const AParentKey: string; out AProject: string;
  out AError: TAtlasCiFetchError): Boolean;
var
  mText: string;
begin
  AProject := '';
  Result := TAtlasYouTrackApi.GetText(ACall.Transport, ACall.Target.Url + '/api/issues/' + Trim(AParentKey) +
    '?fields=' + TTextUris.PercentEncode('id,project(id)'), ACall.TimeoutMs, mText, AError);
  if Result and not TAtlasYouTrackParse.ParseProjectId(mText, AProject) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Result := False;
  end;
end;

/// <summary>Issue im Projekt AProject anlegen; AKey ist seine Kennung.</summary>
function CreateIssue(const ACall: TAtlasTrackerCall; const AProject, ATitle, ADescription: string; out AKey: string;
  out AError: TAtlasCiFetchError): Boolean;
var
  mText: string;
begin
  AKey := '';
  Result := PostCreated(ACall, ACall.Target.Url + '/api/issues?fields=idReadable',
    TAtlasYouTrackBodies.NewIssueBody(AProject, ATitle, ADescription), mText, AError);
  if Result then
  begin
    AKey := TAtlasYouTrackParse.ParseCreatedKey(mText);
  end;
  if Result and (AKey = '') then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Result := False;
  end;
end;

function TAtlasYouTrackTracker.CreateSubtask(const ACall: TAtlasTrackerCall; const AParentKey, ATitle,
  ADescription: string; out AKey: string; out AError: TAtlasCiFetchError): Boolean;
var
  mWatch: TStopwatch;
  mProject, mType: string;
begin
  AKey := '';
  AError := TAtlasCiFetchError.NotConfigured;
  Result := False;
  if (ACall.Target.Server = '') or (ACall.Transport = nil) or not Supports(ACall.Transport, IAtlasCiSend) or
    not TAtlasYouTrackJson.ValidKey(Trim(AParentKey)) then
  begin
    Exit;
  end;
  if Trim(ATitle) = '' then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  mWatch := TStopwatch.StartNew;
  // Linktyp vor dem Anlegen: ohne Subtask-Typ entsteht kein loses Issue.
  Result := ParentProject(ACall, AParentKey, mProject, AError) and
    FindLinkType(Later(ACall, mWatch), TAtlasTrackerLinkKind.Subtask, mType, AError) and
    CreateIssue(Later(ACall, mWatch), mProject, ATitle, ADescription, AKey, AError) and
    PostLink(Later(ACall, mWatch), AParentKey, mType, AKey, AError);
end;

function TAtlasYouTrackTracker.AddLink(const ACall: TAtlasTrackerCall; const AKey: string;
  AKind: TAtlasTrackerLinkKind; const AOtherKey: string; out AError: TAtlasCiFetchError): Boolean;
var
  mWatch: TStopwatch;
  mType: string;
begin
  AError := TAtlasCiFetchError.NotConfigured;
  Result := False;
  if (ACall.Target.Server = '') or (ACall.Transport = nil) or not Supports(ACall.Transport, IAtlasCiSend) then
  begin
    Exit;
  end;
  if not (AKind in [TAtlasTrackerLinkKind.DependsOn, TAtlasTrackerLinkKind.Blocks]) or
    not TAtlasYouTrackJson.ValidKey(Trim(AKey)) or not TAtlasYouTrackJson.ValidKey(Trim(AOtherKey)) or
      SameText(Trim(AKey), Trim(AOtherKey)) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  mWatch := TStopwatch.StartNew;
  Result := FindLinkType(ACall, AKind, mType, AError) and
    PostLink(Later(ACall, mWatch), AKey, mType, AOtherKey, AError);
end;


function TAtlasYouTrackTracker.LoadBoard(const ARequest: TAtlasBoardRequest; out ASnapshot: TAtlasBoardSnapshot;
  out AError: TAtlasCiFetchError): Boolean;
var
  mBoards: IAtlasTrackerBoards;
begin
  mBoards := TAtlasYouTrackBoards.Create;
  Result := mBoards.LoadBoard(ARequest, ASnapshot, AError);
end;

function TAtlasYouTrackTracker.MoveCard(const AMove: TAtlasBoardMove;
  const ASnapshot: TAtlasBoardSnapshot): TAtlasTrackerWriteResult;
var
  mBoards: IAtlasTrackerBoards;
begin
  mBoards := TAtlasYouTrackBoards.Create;
  Result := mBoards.MoveCard(AMove, ASnapshot);
end;

function TAtlasYouTrackTracker.WorkDays(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  ATimeoutMs: Integer; out ADays: TArray<Integer>): Boolean;
var
  mWorkDays: IAtlasTrackerWorkDays;
begin
  mWorkDays := TAtlasYouTrackBoards.Create;
  Result := mWorkDays.WorkDays(ATarget, ATransport, ATimeoutMs, ADays);
end;

function TAtlasYouTrackTracker.LoadFlow(const ARequest: TAtlasFlowRequest; out AData: TAtlasFlowData;
  out AError: TAtlasCiFetchError): Boolean;
var
  mFlow: IAtlasTrackerFlow;
begin
  mFlow := TAtlasYouTrackFlow.Create;
  Result := mFlow.LoadFlow(ARequest, AData, AError);
end;

function TAtlasYouTrackTracker.Search(const ACall: TAtlasTrackerCall; const AText: string; AMax: Integer;
  out AIssues: TArray<TAtlasTrackerIssue>; out AError: TAtlasCiFetchError): Boolean;
var
  mUrl, mText: string;
  mStatus: Integer;
begin
  AIssues := nil;
  AError := TAtlasCiFetchError.None;
  Result := False;
  mUrl := TAtlasYouTrackApi.TextSearchUrl(ACall.Target, AText, AMax);
  if not ACall.Target.Configured or (mUrl = '') or (ACall.Transport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  if not ACall.Transport.Get(mUrl, ACall.TimeoutMs, mStatus, mText, AError) then
  begin
    Exit;
  end;
  if mStatus <> 200 then
  begin
    AError := TAtlasYouTrackApi.ErrorOfStatus(mStatus);
    Exit;
  end;
  if not TAtlasYouTrackParse.ParseIssues(mText, AMax, AIssues) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  Result := True;
end;

function TAtlasYouTrackTracker.Lookup(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; ATimeoutMs: Integer; out AIssue: TAtlasTrackerIssue; out AError: TAtlasCiFetchError): Boolean;
var
  mUrl, mText: string;
  mStatus: Integer;
  mValue: TJSONValue;
begin
  AIssue := TAtlasTrackerIssue.Empty;
  AError := TAtlasCiFetchError.None;
  Result := False;
  mUrl := TAtlasYouTrackApi.LookupUrl(ATarget, AKey);
  if (mUrl = '') or (ATransport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  if not ATransport.Get(mUrl, ATimeoutMs, mStatus, mText, AError) then
  begin
    Exit;
  end;
  if mStatus <> 200 then
  begin
    AError := TAtlasYouTrackApi.ErrorOfStatus(mStatus);
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(mText);
  try
    Result := (mValue is TJSONObject) and TAtlasYouTrackParse.IssueOf(TJSONObject(mValue), AIssue);
  finally
    mValue.Free;
  end;
  if not Result then
  begin
    AError := TAtlasCiFetchError.Invalid;
  end;
end;

function TAtlasYouTrackTracker.Users(const ACall: TAtlasTrackerCall; const AText: string; AMax: Integer;
  out AUsers: TArray<TAtlasTrackerUser>; out AError: TAtlasCiFetchError): Boolean;
var
  mUrl, mText: string;
  mStatus: Integer;
  mUsers: TArray<TAtlasTrackerUser>;
begin
  AUsers := nil;
  AError := TAtlasCiFetchError.None;
  Result := False;
  mUrl := TAtlasYouTrackApi.UsersUrl(ACall.Target, AText, AMax);
  if (mUrl = '') or (ACall.Transport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  if not ACall.Transport.Get(mUrl, ACall.TimeoutMs, mStatus, mText, AError) then
  begin
    Exit;
  end;
  if mStatus <> 200 then
  begin
    AError := TAtlasYouTrackApi.ErrorOfStatus(mStatus);
    Exit;
  end;
  if not TAtlasYouTrackParse.ParseUserList(mText, mUsers) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  // YouTrack sucht auch in der E-Mail-Adresse: Treffer ohne Text im Namen bleiben, nur weiter hinten.
  AUsers := TAtlasTrackerUser.Ranked(mUsers, AText, AMax);
  Result := True;
end;

/// <summary>Antwort von …/vcsChanges. Ohne VCS-Anbindung gibt es die Liste nicht (404): leer, kein Fehler.
/// </summary>
function ReadVcsChanges(AStatus: Integer; const AText: string; var ADevelopment: TAtlasTrackerDevelopment;
  out AError: TAtlasCiFetchError): Boolean;
var
  mChanges: TArray<TAtlasTrackerVcsChange>;
begin
  AError := TAtlasCiFetchError.None;
  Result := AStatus = 404;
  if Result then
  begin
    Exit;
  end;
  if AStatus <> 200 then
  begin
    AError := TAtlasYouTrackApi.ErrorOfStatus(AStatus);
  end
  else if TAtlasYouTrackParse.ParseVcsChanges(AText, mChanges) then
  begin
    ADevelopment.Changes := mChanges;
    Result := True;
  end
  else
  begin
    AError := TAtlasCiFetchError.Invalid;
  end;
end;

function TAtlasYouTrackTracker.Development(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; ATimeoutMs: Integer; out ADevelopment: TAtlasTrackerDevelopment;
  out AError: TAtlasCiFetchError): Boolean;
var
  mStatus: Integer;
  mText, mUrl: string;
begin
  ADevelopment := TAtlasTrackerDevelopment.Empty;
  AError := TAtlasCiFetchError.NotConfigured;
  Result := False;
  mUrl := TAtlasYouTrackApi.VcsChangesUrl(ATarget, AKey);
  if (mUrl = '') or (ATransport = nil) or not ATransport.Get(mUrl, ATimeoutMs, mStatus, mText, AError) then
  begin
    Exit;
  end;
  Result := ReadVcsChanges(mStatus, mText, ADevelopment, AError);
end;

/// <summary>Seit APoll.Since geänderte Issues; False mit AError.</summary>
function ChangedIssues(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; ATimeoutMs: Integer;
  const APoll: TAtlasTrackerPoll; out AIssues: TArray<TAtlasTrackerChange>; out AError: TAtlasCiFetchError): Boolean;
var
  mText: string;
begin
  AIssues := nil;
  Result := TAtlasYouTrackApi.GetText(ATransport, TAtlasYouTrackApi.ChangedIssuesUrl(ATarget, APoll.Since,
    APoll.Scope), ATimeoutMs, mText, AError);
  if Result and not TAtlasYouTrackParse.ParseChangedIssues(mText, APoll.Since, AIssues) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Result := False;
  end;
end;

/// <summary>Aktivitäten eines geänderten Issues. Ohne Zeit (ARestMs) oder Antwort meldet sich das Issue ohne
/// Einzelheiten (die Zeit des Issues bleibt der Stand).</summary>
function IssueActivities(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AIssue: TAtlasTrackerChange; const APoll: TAtlasTrackerPoll; ARestMs: Integer): TArray<TAtlasTrackerChange>;
var
  mText: string;
  mIgnored: TAtlasCiFetchError;
begin
  if (ARestMs <= 0) or not TAtlasYouTrackApi.GetText(ATransport, TAtlasYouTrackApi.ActivitiesUrl(ATarget, AIssue.Key,
    APoll.Since), ARestMs, mText, mIgnored) or not TAtlasYouTrackParse.ParseActivities(mText, AIssue.Key,
    AIssue.Title, APoll.Me, APoll.Since, Result) then
  begin
    Result := [AIssue];
  end;
end;

/// <summary>Späteste Zeit aus ALatest und AChanges.</summary>
function LatestOf(const AChanges: TArray<TAtlasTrackerChange>; ALatest: TDateTime): TDateTime;
var
  mChange: TAtlasTrackerChange;
begin
  Result := ALatest;
  for mChange in AChanges do
  begin
    if mChange.Time > Result then
    begin
      Result := mChange.Time;
    end;
  end;
end;

function TAtlasYouTrackTracker.Changes(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  ATimeoutMs: Integer; var APoll: TAtlasTrackerPoll; out AChanges: TArray<TAtlasTrackerChange>;
  out AError: TAtlasCiFetchError): Boolean;
var
  mWatch: TStopwatch;
  mIndex: Integer;
  mIssues: TArray<TAtlasTrackerChange>;
begin
  AChanges := nil;
  AError := TAtlasCiFetchError.NotConfigured;
  Result := False;
  mWatch := TStopwatch.StartNew;
  if (ATarget.Server = '') or (ATransport = nil) or
    not ChangedIssues(ATarget, ATransport, ATimeoutMs, APoll, mIssues, AError) then
  begin
    Exit;
  end;
  Result := True;
  APoll.Latest := LatestOf(mIssues, APoll.Latest);
  for mIndex := 0 to Min(High(mIssues), TAtlasYouTrackApi.cMaxChangedIssues - 1) do
  begin
    AChanges := AChanges + IssueActivities(ATarget, ATransport, mIssues[mIndex], APoll,
      ATimeoutMs - Integer(mWatch.ElapsedMilliseconds));
  end;
  // Auch eine Aktivität, die der Server später stempelt als das Issue, kommt nicht noch einmal.
  APoll.Latest := LatestOf(AChanges, APoll.Latest);
end;

function TAtlasYouTrackTracker.CanUpload: Boolean;
begin
  Result := True;
end;

/// <summary>POST über ASend; der Status einer abgelehnten Antwort wird zum Fehler von YouTrack.</summary>
function PostTo(const ASend: IAtlasCiPost; const AUrl, AContentType: string; const ABody: TBytes;
  ATimeoutMs: Integer; out AError: TAtlasCiFetchError): Boolean;
var
  mResponse: TAtlasCiResponse;
begin
  Result := TAtlasAttachSender.Post(ASend, AUrl, AContentType, ABody, ATimeoutMs, mResponse);
  AError := mResponse.Error;
  if not Result and (mResponse.Status <> 0) then
  begin
    AError := TAtlasYouTrackApi.ErrorOfStatus(mResponse.Status);
  end;
end;

function TAtlasYouTrackTracker.Upload(const ATarget: TAtlasTrackerTarget; const ASend: IAtlasCiPost;
  const AKey: string; const AFiles: TAtlasAttachFiles; ATimeoutMs: Integer; out AError: TAtlasCiFetchError): Boolean;
var
  mBoundary: string;
begin
  mBoundary := TAtlasAttachMultipart.NewBoundary;
  Result := PostTo(ASend, TAtlasYouTrackApi.AttachmentsUrl(ATarget, AKey), TAtlasAttachMultipart.ContentType(mBoundary),
    TAtlasAttachMultipart.Build(mBoundary, AFiles), ATimeoutMs, AError);
end;

function TAtlasYouTrackTracker.Comment(const ATarget: TAtlasTrackerTarget; const ASend: IAtlasCiPost; const AKey,
  AMarkdown: string; ATimeoutMs: Integer; out AError: TAtlasCiFetchError): Boolean;
begin
  Result := PostTo(ASend, TAtlasYouTrackApi.CommentsUrl(ATarget, AKey), 'application/json',
    TAtlasAttachComment.JsonBody('text', AMarkdown), ATimeoutMs, AError);
end;

function TAtlasYouTrackTracker.CommentText(const AComment: string; const AFiles: TAtlasAttachFiles): string;
begin
  Result := TAtlasAttachComment.Referencing(AComment, AFiles);
end;

end.
