unit Atlas.Core.Tracker.Providers.GitHub;

// Issue-Tracker GitHub (#765), ohne VCL und Open Tools API: Adressen der
// REST-API, Lesen der Antworten und Ablauf einer Abfrage. Das Netz kommt über
// IAtlasCiTransport von außen, damit alles hier ohne Server testbar ist.
// - Schnittstelle: github.com → https://api.github.com, GitHub Enterprise →
//   <Server>/api/v3. Das Token geht nur dorthin (ApiServer).
// - Issues: GET /search/issues?q=<Abfrage> repo:<owner/repo> is:issue
//   &per_page=<Max>&sort=updated&order=desc (Vorgabe der Abfrage
//   "assignee:@me state:open"). Einträge mit "pull_request" sind Pull
//   Requests und entfallen.
// - Pull Requests: GET /repos/<owner/repo>/pulls?state=open&per_page=50. Ein
//   PR gehört zu Issue N, wenn sein Branch N als eigenes Stück enthält
//   („feature/753-…“, wie Atlas ihn anlegt) oder Titel bzw. Beschreibung
//   „closes/fixes/resolves #N“ sagen.
// - CI-Ampel: GET /repos/<owner/repo>/commits/<sha>/check-runs; ohne Check
//   Runs der kombinierte Status /commits/<sha>/status. Höchstens MaxChecks
//   Pull Requests je Abfrage.
// - Verbindung prüfen (#1260): GET /user (angemeldeter Benutzer).
// - Vorschau (#1264): GET /repos/<owner/repo>/issues/<n> (Felder, Beschreibung,
//   Labels, Zuständige, Meilenstein, Typ), mit AComments …/comments (die
//   neuesten MaxComments; sonst nicht abgefragt) und …/timeline für Verweise
//   aus anderen Issues und Pull Requests ("cross-referenced"; im selben
//   Repository öffnen sie im Fenster, sonst im Browser). GitHub kennt keine
//   Anhangsliste: Dateien (/user-attachments/files/…) aus Beschreibung und
//   Kommentaren gelten als Anhänge und öffnen im Browser, weil das Token nur
//   an die API geht.
// - Zustand und Kommentar (#1266, IAtlasTrackerWriter): Kommentar mit POST
//   …/issues/<n>/comments, danach Labels, Zuständige und Zustand in einem
//   PATCH …/issues/<n> (Zustand = Label; das Label aus „Beginnen“ entfällt;
//   ein Erledigt-Zustand schließt das Issue mit state_reason "completed").
//   „Mir zuweisen“ fragt vorher /user. Werte für die Klapplisten: Labels
//   (…/labels) und mögliche Zuständige (…/assignees).
// - Checklisten (#1273, IAtlasTrackerDescriptions): Beschreibung ungekürzt aus
//   GET …/issues/<n> ("body"), zurück mit PATCH …/issues/<n> und {"body": …}.
// - Verknüpfungen (#1279): …/sub_issues (Unteraufgaben),
//   …/dependencies/blocked_by (hängt ab von) und …/dependencies/blocking
//   (blockiert); abgefragt nur, wenn sub_issues_summary bzw.
//   issue_dependencies_summary des Issues Einträge melden (fehlen die
//   Zusammenfassungen, wird gefragt; 404 heißt: kennt der Server nicht). Ohne
//   „blocked by“ gelten Erwähnungen wie „depends on #12“ oder „Benötigt: #12“
//   im Text (TAtlasTrackerLinks.TextDependencies); deren Zustand liest
//   …/issues/<n>, höchstens TAtlasTrackerLinks.MaxTextDependencies.
// - Unteraufgabe anlegen (#1279): POST /repos/<owner/repo>/issues, dann
//   POST …/issues/<Eltern>/sub_issues mit {"sub_issue_id": <id>};
//   Verknüpfen: POST …/issues/<n>/dependencies/blocked_by mit
//   {"issue_id": <id>} (die interne ID aus …/issues/<m>).
// - Palettensuche (#1270): GET /search/issues?q=repo:<owner/repo> is:issue
//   <Text>&per_page=<Max> ohne Sortierung (beste Treffer zuerst), ohne Pull
//   Requests und Ampeln; eine Kennung ("#42") liest Lookup direkt über
//   /repos/<owner/repo>/issues/42.
// - Benutzer für @-Erwähnungen (#1278, IAtlasTrackerPeople): die möglichen
//   Zuständigen des Repositorys (…/assignees, eine Seite), gefiltert nach
//   dem getippten Text; GitHub liefert dort keine Anzeigenamen.
// - Entwicklung (#1269): GET /repos/<owner/repo>/pulls?state=all&per_page=100
//   &sort=updated&direction=desc; zum Issue N gehören die Pull Requests, die
//   PullMentions erkennt oder die „#N“ im Titel tragen (PullRefersTo), mit
//   Zustand (offen, Entwurf, gemergt, geschlossen) und CI-Ampel wie oben,
//   höchstens MaxChecks Ampeln.
// - Änderungen (#1271): GET /notifications?since=<Stand> über alle
//   Repositories, bedingt mit If-Modified-Since (IAtlasCiConditional; 304 =
//   nichts Neues), X-Poll-Interval wird zum kleinsten Abstand. Nur Issues;
//   der Grund ("assign", "author", sonst beobachtet) entscheidet über den
//   Umfang. Je Issue …/comments?since=<Stand> (neue Kommentare) und …/events
//   (assigned, closed, reopened); ohne erkennbare Einzelheit bleibt eine
//   allgemeine Änderung. Eigene Aktionen meldet GitHub ohnehin nicht.
// - Anhängen (#1276, IAtlasTrackerAttach): GitHub nimmt über die API keine
//   Dateien an (CanUpload = False). Texte (Protokoll, Debug-Notiz,
//   Exception-Verlauf) gehen als Kommentar POST /repos/<owner/repo>/issues/
//   <n>/comments mit {"body": …}, Protokolle als Codeblock; Bilder legt die
//   IDE-Schicht in die Zwischenablage und öffnet das Issue im Browser.
// Die Zeitgrenze gilt für die ganze Abfrage; reicht sie nach der Liste nicht
// mehr für Pull Requests und Ampeln, bleiben diese unbekannt.


interface

uses
  System.SysUtils,
  System.Diagnostics,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Internals.GitHubApi,
  Atlas.Core.Tracker.GitHubParse,
  Atlas.Core.Tracker.Board,
  Atlas.Core.Tracker.Attach;

type
  TAtlasGitHubTracker = class(TInterfacedObject, IAtlasTrackerProvider, IAtlasTrackerWriter,
    IAtlasTrackerDescriptions, IAtlasTrackerLinkWriter, IAtlasTrackerBoards, IAtlasTrackerPeople, IAtlasTrackerAttach)
  public const
    ProviderName = TAtlasGitHubApi.ProviderName;
    Query = TAtlasGitHubApi.DefaultQuery;
    ApiHost = TAtlasGitHubApi.ApiHost;
    /// <summary>Höchstens so viele Pull Requests bekommen eine Ampel.</summary>
    MaxChecks = 8;
    /// <summary>Höchstens so viele offene Pull Requests werden gelesen.</summary>
    MaxPulls = TAtlasGitHubApi.MaxPulls;
    /// <summary>Einträge je Seite für Kommentare und Zeitleiste (#1264).</summary>
    MaxPageSize = TAtlasGitHubApi.MaxPageSize;
  private const
    /// <summary>Höchstens so viele Issues je Abfrage bekommen Kommentare und Ereignisse (#1271).</summary>
    MaxChangedIssues = 20;
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
    { IAtlasTrackerBoards (#1272): über TAtlasGitHubBoards }
    function LoadBoard(const ARequest: TAtlasBoardRequest; out ASnapshot: TAtlasBoardSnapshot;
      out AError: TAtlasCiFetchError): Boolean;
    function MoveCard(const AMove: TAtlasBoardMove; const ASnapshot: TAtlasBoardSnapshot): TAtlasTrackerWriteResult;
    { IAtlasTrackerProvider: Suche und einzelnes Issue (#1270) }
    function Search(const ACall: TAtlasTrackerCall; const AText: string; AMax: Integer;
      out AIssues: TArray<TAtlasTrackerIssue>; out AError: TAtlasCiFetchError): Boolean;
    function Lookup(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const AKey: string; ATimeoutMs: Integer; out AIssue: TAtlasTrackerIssue; out AError: TAtlasCiFetchError): Boolean;
    { IAtlasTrackerPeople }
    function Users(const ACall: TAtlasTrackerCall; const AText: string; AMax: Integer;
      out AUsers: TArray<TAtlasTrackerUser>; out AError: TAtlasCiFetchError): Boolean;
    function Development(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const AKey: string; ATimeoutMs: Integer; out ADevelopment: TAtlasTrackerDevelopment;
      out AError: TAtlasCiFetchError): Boolean;
    function Changes(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      ATimeoutMs: Integer; var APoll: TAtlasTrackerPoll; out AChanges: TArray<TAtlasTrackerChange>;
      out AError: TAtlasCiFetchError): Boolean;
    { IAtlasTrackerAttach (#1276) }
    function CanUpload: Boolean;
    function Upload(const ATarget: TAtlasTrackerTarget; const ASend: IAtlasCiPost;
      const AKey: string; const AFiles: TAtlasAttachFiles; ATimeoutMs: Integer;
      out AError: TAtlasCiFetchError): Boolean;
    function Comment(const ATarget: TAtlasTrackerTarget; const ASend: IAtlasCiPost; const AKey,
      AMarkdown: string; ATimeoutMs: Integer; out AError: TAtlasCiFetchError): Boolean;
    function CommentText(const AComment: string; const AFiles: TAtlasAttachFiles): string;
  end;

implementation

uses
  System.Classes,
  System.DateUtils,
  System.Generics.Collections,
  System.JSON,
  System.StrUtils,
  Atlas.Text.Uris,
  Atlas.Core.Tracker.Links,
  Atlas.Core.Tracker.Markdown,
  Atlas.Core.Tracker.Checklist,
  Atlas.Core.Tracker.Internals.GitHubJson,
  Atlas.Core.Tracker.GitHubBoards;

function TAtlasGitHubTracker.Name: string;
begin
  Result := TAtlasGitHubApi.ProviderName;
end;

function TAtlasGitHubTracker.Caption: string;
begin
  Result := 'GitHub';
end;

function TAtlasGitHubTracker.DefaultQuery: string;
begin
  Result := Query;
end;

function TAtlasGitHubTracker.ApiServer(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := TAtlasTrackerTarget.Create('', TAtlasGitHubApi.Base(ATarget), '', '').Server;
end;

/// <summary>CI-Ampel des Stands ASha in der restlichen Zeit: Check Runs, sonst der ältere kombinierte Status
/// (externe CI wie Jenkins).</summary>
function ChecksOf(const ACall: TAtlasTrackerCall; const AWatch: TStopwatch; const ASha: string): TAtlasTrackerChecks;
var
  mText: string;
begin
  Result := TAtlasTrackerChecks.Unknown;
  if TAtlasGitHubApi.GetInTime(ACall, AWatch, TAtlasGitHubApi.CheckRunsUrl(ACall.Target, ASha), mText) then
  begin
    TAtlasGitHubParse.ParseCheckRuns(mText, Result);
  end;
  if (Result = TAtlasTrackerChecks.Unknown)
    and TAtlasGitHubApi.GetInTime(ACall, AWatch, TAtlasGitHubApi.StatusUrl(ACall.Target, ASha), mText) then
  begin
    TAtlasGitHubParse.ParseStatus(mText, Result);
  end;
end;

/// <summary>Noch eine Ampel: weniger als MaxChecks abgefragt, Zeit übrig, Stand bekannt; zählt AChecked hoch.
/// </summary>
function TakeCheck(const ACall: TAtlasTrackerCall; const AWatch: TStopwatch; const ASha: string;
  var AChecked: Integer): Boolean;
begin
  Result := (AChecked < TAtlasGitHubTracker.MaxChecks) and (TAtlasGitHubApi.Remaining(AWatch, ACall.TimeoutMs) > 0)
    and (TAtlasGitHubApi.CheckRunsUrl(ACall.Target, ASha) <> '');
  if Result then
  begin
    Inc(AChecked);
  end;
end;

/// <summary>Der erste Pull Request zu AIssue (PullMentions) mit Ampel, solange TakeCheck es erlaubt.</summary>
procedure AddPullRequest(var AIssue: TAtlasTrackerIssue; const APulls: TArray<TAtlasGitHubPull>;
  const ACall: TAtlasTrackerCall; const AWatch: TStopwatch; var AChecked: Integer);
var
  mPull: TAtlasGitHubPull;
begin
  for mPull in APulls do
  begin
    if TAtlasGitHubParse.PullMentions(mPull, AIssue.Number) then
    begin
      AIssue.PullRequest.Number := mPull.Number;
      AIssue.PullRequest.Draft := mPull.Draft;
      if TakeCheck(ACall, AWatch, mPull.Sha, AChecked) then
      begin
        AIssue.PullRequest.Checks := ChecksOf(ACall, AWatch, mPull.Sha);
      end;
      Exit;
    end;
  end;
end;

/// <summary>Pull Requests und Ampeln in der restlichen Zeit; was fehlt, bleibt unbekannt.</summary>
procedure AddPullRequests(var AIssues: TArray<TAtlasTrackerIssue>; const ACall: TAtlasTrackerCall;
  const AWatch: TStopwatch);
var
  mText: string;
  mPulls: TArray<TAtlasGitHubPull>;
  mIndex, mChecked: Integer;
begin
  if (Length(AIssues) = 0) or not TAtlasGitHubApi.GetInTime(ACall, AWatch, TAtlasGitHubApi.PullsUrl(ACall.Target),
    mText) or not TAtlasGitHubParse.ParsePulls(mText, mPulls) then
  begin
    Exit;
  end;
  mChecked := 0;
  for mIndex := 0 to High(AIssues) do
  begin
    AddPullRequest(AIssues[mIndex], mPulls, ACall, AWatch, mChecked);
  end;
end;

function TAtlasGitHubTracker.Fetch(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  ATimeoutMs, AMax: Integer; out AIssues: TArray<TAtlasTrackerIssue>; out AError: TAtlasCiFetchError): Boolean;
var
  mWatch: TStopwatch;
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
  mWatch := TStopwatch.StartNew;
  if not TAtlasGitHubApi.GetText(ATransport, TAtlasGitHubApi.SearchUrl(ATarget, AMax), ATimeoutMs, mText, AError) then
  begin
    Exit;
  end;
  Result := TAtlasGitHubParse.ParseIssues(mText, AMax, AIssues);
  if Result then
  begin
    AddPullRequests(AIssues, TAtlasTrackerCall.Create(ATarget, ATransport, ATimeoutMs), mWatch);
  end
  else
  begin
    AError := TAtlasCiFetchError.Invalid;
  end;
end;

function TAtlasGitHubTracker.IssuePage(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
begin
  Result := TAtlasGitHubApi.IssuePage(ATarget, AKey);
end;

function TAtlasGitHubTracker.PullRequestPage(const ATarget: TAtlasTrackerTarget; ANumber: Integer): string;
begin
  Result := '';
  if (ATarget.Server = '') or (ATarget.Project = '') or (ANumber <= 0) then
  begin
    Exit;
  end;
  Result := ATarget.Server + '/' + TTextUris.PercentEncode(ATarget.Project) + '/pull/' + IntToStr(ANumber);
end;

function TAtlasGitHubTracker.ProbeUrl(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := TAtlasGitHubApi.Base(ATarget);
  if Result <> '' then
  begin
    Result := Result + '/user';
  end;
end;

function TAtlasGitHubTracker.ListUrl(const ATarget: TAtlasTrackerTarget; AMax: Integer): string;
begin
  Result := TAtlasGitHubApi.SearchUrl(ATarget, AMax);
end;

function TAtlasGitHubTracker.SentQuery(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := TAtlasGitHubApi.SearchText(ATarget);
end;

function TAtlasGitHubTracker.ParseList(const AText: string; AMax: Integer;
  out AIssues: TArray<TAtlasTrackerIssue>): Boolean;
begin
  Result := TAtlasGitHubParse.ParseIssues(AText, AMax, AIssues);
end;

function TAtlasGitHubTracker.LocaleUrl(const ATarget: TAtlasTrackerTarget): string;
begin
  // Die Suchbegriffe von GitHub sind in jeder Sprache englisch.
  Result := '';
end;

/// <summary>Seite APage der Kommentare unter AUrl in der restlichen Zeit; False ohne.</summary>
function CommentsPage(const ACall: TAtlasTrackerCall; const AWatch: TStopwatch; const AUrl: string; APage: Integer;
  out AComments: TArray<TAtlasTrackerComment>): Boolean;
var
  mText: string;
begin
  AComments := nil;
  Result := TAtlasGitHubApi.GetInTime(ACall, AWatch, AUrl + '/comments?per_page=' +
    IntToStr(TAtlasGitHubApi.MaxPageSize) + '&page=' + IntToStr(APage), mText)
    and TAtlasGitHubParse.ParseComments(mText, AComments);
end;

/// <summary>Die neuesten MaxComments von ACount Kommentaren: letzte Seite, bei Bedarf die davor.</summary>
function LatestComments(const ACall: TAtlasTrackerCall; const AWatch: TStopwatch; const AUrl: string;
  ACount: Integer): TArray<TAtlasTrackerComment>;
var
  mPage: Integer;
  mOlder: TArray<TAtlasTrackerComment>;
begin
  Result := nil;
  mPage := (ACount + TAtlasGitHubApi.MaxPageSize - 1) div TAtlasGitHubApi.MaxPageSize;
  if (ACount <= 0) or not CommentsPage(ACall, AWatch, AUrl, mPage, Result) then
  begin
    Exit;
  end;
  if (mPage > 1) and (Length(Result) < TAtlasTrackerDetails.MaxComments)
    and CommentsPage(ACall, AWatch, AUrl, mPage - 1, mOlder) then
  begin
    Result := mOlder + Result;
  end;
  if Length(Result) > TAtlasTrackerDetails.MaxComments then
  begin
    Result := Copy(Result, Length(Result) - TAtlasTrackerDetails.MaxComments, TAtlasTrackerDetails.MaxComments);
  end;
end;

/// <summary>Verweise aus der Zeitleiste in der restlichen Zeit; leer ohne.</summary>
function TimelineLinks(const ACall: TAtlasTrackerCall; const AWatch: TStopwatch;
  const AUrl: string): TArray<TAtlasTrackerLink>;
var
  mText: string;
begin
  Result := nil;
  if TAtlasGitHubApi.GetInTime(ACall, AWatch, AUrl + '/timeline?per_page=' + IntToStr(TAtlasGitHubApi.MaxPageSize),
    mText) then
  begin
    TAtlasGitHubParse.ParseTimeline(mText, ACall.Target.Project, Result);
  end;
end;

/// <summary>Verknüpfungen der Art AKind von AUrl in ALinks übernehmen; True, wenn welche kamen.</summary>
function MergeRelated(const ACall: TAtlasTrackerCall; const AWatch: TStopwatch; const AUrl: string;
  AKind: TAtlasTrackerLinkKind; var ALinks: TArray<TAtlasTrackerLink>): Boolean;
var
  mText: string;
  mLinks: TArray<TAtlasTrackerLink>;
begin
  Result := TAtlasGitHubApi.GetInTime(ACall, AWatch, AUrl, mText)
    and TAtlasGitHubParse.ParseRelated(mText, ACall.Target.Project, AKind, mLinks);
  if Result then
  begin
    TAtlasGitHubParse.MergeLinks(ALinks, mLinks);
    Result := Length(mLinks) > 0;
  end;
end;

/// <summary>ALinks enthält schon „hängt ab von“ AKey.</summary>
function HasDependency(const ALinks: TArray<TAtlasTrackerLink>; const AKey: string): Boolean;
var
  mLink: TAtlasTrackerLink;
begin
  Result := False;
  for mLink in ALinks do
  begin
    if SameText(mLink.Key, AKey) and (mLink.Kind = TAtlasTrackerLinkKind.DependsOn) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>„Hängt ab von“ AKey aus dem Text, mit Titel und Zustand, wenn die Zeit reicht.</summary>
function TextDependencyLink(const ACall: TAtlasTrackerCall; const AWatch: TStopwatch;
  const AKey: string): TAtlasTrackerLink;
var
  mText: string;
  mOther: TAtlasTrackerDetails;
  mCount: Integer;
begin
  Result := Default(TAtlasTrackerLink);
  Result.Key := AKey;
  Result.Local := True;
  Result.Kind := TAtlasTrackerLinkKind.DependsOn;
  Result.Relation := 'depends on';
  Result.Page := TAtlasGitHubApi.IssuePage(ACall.Target, AKey);
  if TAtlasGitHubApi.GetInTime(ACall, AWatch, TAtlasGitHubApi.IssueApiUrl(ACall.Target, AKey), mText)
    and TAtlasGitHubParse.ParseDetails(mText, mOther, mCount) then
  begin
    Result.Title := TAtlasGitHubJson.Shorten(mOther.Title, 200);
    Result.State := mOther.State;
    Result.StateKnown := True;
    Result.Resolved := StartsText('closed', mOther.State);
  end;
end;

/// <summary>Verknüpfungen (#1279) in der restlichen Zeit: Unteraufgaben, „blocked by“, „blocking“, sonst
/// Abhängigkeiten aus dem Text.</summary>
procedure LoadRelations(const ACall: TAtlasTrackerCall; const AUrl: string; const ASummary: TAtlasGitHubLinkSummary;
  const AWatch: TStopwatch; var ADetails: TAtlasTrackerDetails);
var
  mPerPage, mKey: string;
  mBlockers: Boolean;
  mNumber: Integer;
begin
  mPerPage := '?per_page=' + IntToStr(TAtlasGitHubApi.MaxPageSize);
  // Nur fragen, was die Zusammenfassung meldet; ohne Zusammenfassung (-1) trotzdem.
  if ASummary.SubIssues <> 0 then
  begin
    MergeRelated(ACall, AWatch, AUrl + '/sub_issues' + mPerPage, TAtlasTrackerLinkKind.Subtask, ADetails.Links);
  end;
  mBlockers := (ASummary.BlockedBy <> 0) and MergeRelated(ACall, AWatch, AUrl + '/dependencies/blocked_by' +
    mPerPage, TAtlasTrackerLinkKind.DependsOn, ADetails.Links);
  if ASummary.Blocking <> 0 then
  begin
    MergeRelated(ACall, AWatch, AUrl + '/dependencies/blocking' + mPerPage, TAtlasTrackerLinkKind.Blocks,
      ADetails.Links);
  end;
  if mBlockers then
  begin
    Exit;
  end;
  // Ohne „blocked by“: Abhängigkeiten aus dem Text, Zustand je Issue nachgefragt.
  for mNumber in TAtlasTrackerLinks.TextDependencies(ADetails.Description) do
  begin
    mKey := '#' + IntToStr(mNumber);
    if (mNumber <> ADetails.Number) and not HasDependency(ADetails.Links, mKey) then
    begin
      TAtlasGitHubParse.MergeLinks(ADetails.Links, TArray<TAtlasTrackerLink>.Create(TextDependencyLink(ACall, AWatch,
        mKey)));
    end;
  end;
end;

function TAtlasGitHubTracker.Details(const ACall: TAtlasTrackerCall; const AKey: string; AComments: Boolean;
  out ADetails: TAtlasTrackerDetails; out AError: TAtlasCiFetchError): Boolean;
var
  mWatch: TStopwatch;
  mUrl, mText: string;
  mCount: Integer;
begin
  ADetails := TAtlasTrackerDetails.Empty;
  AError := TAtlasCiFetchError.None;
  Result := False;
  mUrl := TAtlasGitHubApi.IssueApiUrl(ACall.Target, AKey);
  if (mUrl = '') or (ACall.Transport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  mWatch := TStopwatch.StartNew;
  if not TAtlasGitHubApi.GetText(ACall.Transport, mUrl, ACall.TimeoutMs, mText, AError) then
  begin
    Exit;
  end;
  Result := TAtlasGitHubParse.ParseDetails(mText, ADetails, mCount);
  if not Result then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  ADetails.Page := IssuePage(ACall.Target, ADetails.Key);
  // Kommentare und Verweise in der restlichen Zeit; was fehlt, bleibt leer.
  ADetails.CommentsLoaded := AComments;
  if AComments then
  begin
    ADetails.Comments := LatestComments(ACall, mWatch, mUrl, mCount);
  end;
  ADetails.Links := TimelineLinks(ACall, mWatch, mUrl);
  LoadRelations(ACall, mUrl, TAtlasGitHubParse.ParseLinkSummary(mText), mWatch, ADetails);
  ADetails.Attachments := TAtlasGitHubParse.FileAttachments(ADetails);
end;

/// <summary>GET für einen Schreibzugriff: Fehler ohne Antwort oder mit anderem Status als 200, sonst Ok.
/// </summary>
function GetForWrite(const ATransport: IAtlasCiTransport; const AUrl: string; ATimeoutMs: Integer; out AText: string;
  out AStatus: Integer): TAtlasTrackerWriteResult;
var
  mError: TAtlasCiFetchError;
begin
  Result := TAtlasTrackerWriteResult.Ok;
  if not ATransport.Get(AUrl, ATimeoutMs, AStatus, AText, mError) then
  begin
    Result := TAtlasTrackerWriteResult.Failed(mError, 0, '');
  end
  else if AStatus <> 200 then
  begin
    Result := TAtlasTrackerWriteResult.Failed(TAtlasGitHubApi.ErrorOfStatus(AStatus), AStatus,
      TAtlasGitHubApi.ErrorMessage(AText));
  end;
end;

/// <summary>Eigener Anmeldename über /user für „Mir zuweisen“; ohne ihn Invalid.</summary>
function ReadMe(const ACall: TAtlasTrackerCall; out AMe: string): TAtlasTrackerWriteResult;
var
  mText: string;
  mStatus: Integer;
  mValue: TJSONValue;
begin
  AMe := '';
  Result := GetForWrite(ACall.Transport, TAtlasGitHubApi.Base(ACall.Target) + '/user', ACall.TimeoutMs, mText,
    mStatus);
  if not Result.Succeeded then
  begin
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(mText);
  try
    if mValue is TJSONObject then
    begin
      AMe := Trim(TAtlasGitHubJson.TextOf(TJSONObject(mValue), 'login'));
    end;
  finally
    mValue.Free;
  end;
  if AMe = '' then
  begin
    Result := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, mStatus, '');
  end;
end;

/// <summary>Labels, Zuständige und Zustand in einem PATCH nach AChange; nichts, wenn sich nichts ändert.</summary>
function PatchAssignment(const ACall: TAtlasTrackerCall; const AWatch: TStopwatch; const AUrl: string;
  const AChange: TAtlasTrackerWrite; const AMe: string): TAtlasTrackerWriteResult;
var
  mSend: IAtlasCiSend;
  mText, mBody: string;
  mStatus: Integer;
  mLabels, mAssignees: TArray<string>;
  mResponse: TAtlasCiResponse;
begin
  Result := GetForWrite(ACall.Transport, AUrl, TAtlasGitHubApi.Remaining(AWatch, ACall.TimeoutMs), mText, mStatus);
  if not Result.Succeeded then
  begin
    Exit;
  end;
  if not TAtlasGitHubParse.ParseAssignment(mText, mLabels, mAssignees) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, mStatus, ''));
  end;
  mBody := TAtlasGitHubApi.PatchJson(mLabels, mAssignees, AChange, AMe);
  if (mBody <> '') and Supports(ACall.Transport, IAtlasCiSend, mSend) then
  begin
    Result := TAtlasGitHubApi.WriteResult(mSend.Send('PATCH', AUrl, mBody,
      TAtlasGitHubApi.Remaining(AWatch, ACall.TimeoutMs), mResponse), mResponse);
  end;
end;

function TAtlasGitHubTracker.Apply(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; const AChange: TAtlasTrackerWrite; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
var
  mWatch: TStopwatch;
  mSend: IAtlasCiSend;
  mCall: TAtlasTrackerCall;
  mUrl, mMe: string;
begin
  Result := TAtlasTrackerWriteResult.Ok;
  if not AChange.HasWork then
  begin
    Exit;
  end;
  mUrl := TAtlasGitHubApi.IssueApiUrl(ATarget, AKey);
  if (mUrl = '') or not Supports(ATransport, IAtlasCiSend, mSend) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, ''));
  end;
  mCall := TAtlasTrackerCall.Create(ATarget, ATransport, ATimeoutMs);
  mWatch := TStopwatch.StartNew;
  mMe := '';
  if AChange.Assign = TAtlasTrackerAssign.Me then
  begin
    Result := ReadMe(mCall, mMe);
  end;
  // Zuerst der Kommentar: Fehlen die Schreibrechte, ändert sich nichts am Issue.
  if Result.Succeeded and (Trim(AChange.Comment) <> '') then
  begin
    Result := TAtlasGitHubApi.PostComment(ATarget, mSend, AKey, AChange.Comment,
      TAtlasGitHubApi.Remaining(mWatch, ATimeoutMs));
  end;
  if Result.Succeeded and ((Trim(AChange.State) <> '') or (AChange.Assign <> TAtlasTrackerAssign.Keep)) then
  begin
    Result := PatchAssignment(mCall, mWatch, mUrl, AChange, mMe);
  end;
end;

function TAtlasGitHubTracker.Values(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  AKind: TAtlasTrackerValueKind; const AField: string; ATimeoutMs: Integer;
  out AValues: TArray<string>): TAtlasTrackerWriteResult;
var
  mUrl, mText, mField: string;
  mStatus: Integer;
  mError: TAtlasCiFetchError;
begin
  AValues := nil;
  Result := TAtlasTrackerWriteResult.Ok;
  // GitHub kennt keine Felder: Zustände sind Labels, zuständig sind Benutzer.
  if (AKind = TAtlasTrackerValueKind.StateFields) or (AKind = TAtlasTrackerValueKind.UserFields) then
  begin
    Exit;
  end;
  mUrl := TAtlasGitHubApi.Base(ATarget);
  if (mUrl = '') or (ATarget.Project = '') or (ATransport = nil) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, ''));
  end;
  if AKind = TAtlasTrackerValueKind.Users then
  begin
    mUrl := TAtlasGitHubApi.AssigneesUrl(ATarget);
    mField := 'login';
  end
  else
  begin
    mUrl := mUrl + '/repos/' + TTextUris.PercentEncode(ATarget.Project) + '/labels?per_page=' +
      IntToStr(TAtlasGitHubApi.MaxPageSize);
    mField := 'name';
  end;
  if not ATransport.Get(mUrl, ATimeoutMs, mStatus, mText, mError) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(mError, 0, ''));
  end;
  if mStatus <> 200 then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasGitHubApi.ErrorOfStatus(mStatus), mStatus,
      TAtlasGitHubApi.ErrorMessage(mText)));
  end;
  if not TAtlasGitHubParse.ParseNames(mText, mField, AValues) then
  begin
    Result := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, mStatus, '');
  end;
end;

function TAtlasGitHubTracker.Description(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; ATimeoutMs: Integer; out AText: string; out AError: TAtlasCiFetchError): Boolean;
var
  mUrl, mJson: string;
  mStatus: Integer;
begin
  AText := '';
  AError := TAtlasCiFetchError.None;
  Result := False;
  mUrl := TAtlasGitHubApi.IssueApiUrl(ATarget, AKey);
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
    AError := TAtlasGitHubApi.ErrorOfStatus(mStatus);
    Exit;
  end;
  if not TAtlasGitHubParse.ParseBody(mJson, AText) or (Length(AText) > TAtlasTrackerDetails.MaxDescription) then
  begin
    AText := '';
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  Result := True;
end;

function TAtlasGitHubTracker.UpdateDescription(const ATarget: TAtlasTrackerTarget;
  const ATransport: IAtlasCiTransport; const AKey, AText: string; ATimeoutMs: Integer;
  out AError: TAtlasCiFetchError): Boolean;
var
  mUrl: string;
  mResponse: TAtlasCiResponse;
  mSend: IAtlasCiSend;
begin
  AError := TAtlasCiFetchError.None;
  Result := False;
  mUrl := TAtlasGitHubApi.IssueApiUrl(ATarget, AKey);
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
  if not mSend.Send('PATCH', mUrl, TAtlasGitHubApi.BodyJson(AText), ATimeoutMs, mResponse) then
  begin
    AError := mResponse.Error;
    Exit;
  end;
  if mResponse.Status <> 200 then
  begin
    AError := TAtlasGitHubApi.ErrorOfStatus(mResponse.Status);
    Exit;
  end;
  Result := True;
end;

/// <summary>Interne ID des Issues AKey über GET; 0 mit AError.</summary>
function IssueId(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
  ATimeoutMs: Integer; out AError: TAtlasCiFetchError): Int64;
var
  mStatus: Integer;
  mText: string;
begin
  Result := 0;
  if not ATransport.Get(TAtlasGitHubApi.IssueApiUrl(ATarget, AKey), ATimeoutMs, mStatus, mText, AError) then
  begin
    Exit;
  end;
  if mStatus <> 200 then
  begin
    AError := TAtlasGitHubApi.ErrorOfStatus(mStatus);
    Exit;
  end;
  Result := TAtlasGitHubParse.ParseIssueId(mText);
  if Result = 0 then
  begin
    AError := TAtlasCiFetchError.Invalid;
  end;
end;

/// <summary>POST mit AStatus 200/201 als Erfolg.</summary>
function Posted(const APost: IAtlasCiSend; const AUrl, ABody: string; ATimeoutMs: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
var
  mResponse: TAtlasCiResponse;
begin
  Result := False;
  AError := TAtlasCiFetchError.None;
  if not APost.Send('POST', AUrl, ABody, ATimeoutMs, mResponse) then
  begin
    AText := '';
    AError := mResponse.Error;
    Exit;
  end;
  AText := mResponse.Text;
  if (mResponse.Status <> 200) and (mResponse.Status <> 201) then
  begin
    AError := TAtlasGitHubApi.ErrorOfStatus(mResponse.Status);
    Exit;
  end;
  AError := TAtlasCiFetchError.None;
  Result := True;
end;

function TAtlasGitHubTracker.CreateSubtask(const ACall: TAtlasTrackerCall; const AParentKey, ATitle,
  ADescription: string; out AKey: string; out AError: TAtlasCiFetchError): Boolean;
var
  mPost: IAtlasCiSend;
  mWatch: TStopwatch;
  mParent, mText: string;
  mId: Int64;
  mNumber: Integer;
  mValue: TJSONValue;
begin
  AKey := '';
  AError := TAtlasCiFetchError.NotConfigured;
  Result := False;
  mParent := TAtlasGitHubApi.IssueApiUrl(ACall.Target, AParentKey);
  if (mParent = '') or (ACall.Transport = nil) or not Supports(ACall.Transport, IAtlasCiSend, mPost) then
  begin
    Exit;
  end;
  if Trim(ATitle) = '' then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  mWatch := TStopwatch.StartNew;
  if not Posted(mPost,
    TAtlasGitHubApi.Base(ACall.Target) + '/repos/' + TTextUris.PercentEncode(ACall.Target.Project) + '/issues',
    TAtlasGitHubApi.NewIssueBody(ATitle, ADescription), ACall.TimeoutMs, mText, AError) then
  begin
    Exit;
  end;
  mId := TAtlasGitHubParse.ParseIssueId(mText);
  mNumber := 0;
  mValue := TJSONObject.ParseJSONValue(mText);
  try
    if mValue is TJSONObject then
    begin
      mNumber := TAtlasGitHubJson.IntOf(TJSONObject(mValue), 'number');
    end;
  finally
    mValue.Free;
  end;
  if (mId = 0) or (mNumber = 0) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  AKey := '#' + IntToStr(mNumber);
  Result := Posted(mPost, mParent + '/sub_issues', TAtlasGitHubApi.IdBody('sub_issue_id', mId),
    TAtlasGitHubApi.Remaining(mWatch, ACall.TimeoutMs),
    mText, AError);
end;

function TAtlasGitHubTracker.AddLink(const ACall: TAtlasTrackerCall; const AKey: string; AKind: TAtlasTrackerLinkKind;
  const AOtherKey: string; out AError: TAtlasCiFetchError): Boolean;
var
  mPost: IAtlasCiSend;
  mWatch: TStopwatch;
  mBlocked, mBlocker, mText: string;
  mId: Int64;
begin
  AError := TAtlasCiFetchError.NotConfigured;
  Result := False;
  if (ACall.Transport = nil) or not Supports(ACall.Transport, IAtlasCiSend, mPost) then
  begin
    Exit;
  end;
  // „hängt ab von“: AKey wird von AOtherKey blockiert; „blockiert“: umgekehrt.
  if AKind = TAtlasTrackerLinkKind.DependsOn then
  begin
    mBlocked := AKey;
    mBlocker := AOtherKey;
  end
  else if AKind = TAtlasTrackerLinkKind.Blocks then
  begin
    mBlocked := AOtherKey;
    mBlocker := AKey;
  end
  else
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  if (TAtlasGitHubApi.IssueApiUrl(ACall.Target, mBlocked) = '') or (TAtlasGitHubApi.IssueApiUrl(ACall.Target,
    mBlocker) = '') or
    (TAtlasGitHubApi.NumberOfKey(mBlocked) = TAtlasGitHubApi.NumberOfKey(mBlocker)) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  mWatch := TStopwatch.StartNew;
  mId := IssueId(ACall.Target, ACall.Transport, mBlocker, ACall.TimeoutMs, AError);
  if mId = 0 then
  begin
    Exit;
  end;
  Result := Posted(mPost, TAtlasGitHubApi.IssueApiUrl(ACall.Target, mBlocked) + '/dependencies/blocked_by',
    TAtlasGitHubApi.IdBody('issue_id', mId),
    TAtlasGitHubApi.Remaining(mWatch, ACall.TimeoutMs), mText, AError);
end;


function TAtlasGitHubTracker.LoadBoard(const ARequest: TAtlasBoardRequest; out ASnapshot: TAtlasBoardSnapshot;
  out AError: TAtlasCiFetchError): Boolean;
var
  mBoards: IAtlasTrackerBoards;
begin
  mBoards := TAtlasGitHubBoards.Create;
  Result := mBoards.LoadBoard(ARequest, ASnapshot, AError);
end;

function TAtlasGitHubTracker.MoveCard(const AMove: TAtlasBoardMove;
  const ASnapshot: TAtlasBoardSnapshot): TAtlasTrackerWriteResult;
var
  mBoards: IAtlasTrackerBoards;
begin
  mBoards := TAtlasGitHubBoards.Create;
  Result := mBoards.MoveCard(AMove, ASnapshot);
end;

function TAtlasGitHubTracker.Search(const ACall: TAtlasTrackerCall; const AText: string; AMax: Integer;
  out AIssues: TArray<TAtlasTrackerIssue>; out AError: TAtlasCiFetchError): Boolean;
var
  mUrl, mText: string;
  mStatus: Integer;
begin
  AIssues := nil;
  AError := TAtlasCiFetchError.None;
  Result := False;
  mUrl := TAtlasGitHubApi.TextSearchUrl(ACall.Target, AText, AMax);
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
    AError := TAtlasGitHubApi.ErrorOfStatus(mStatus);
    Exit;
  end;
  if not TAtlasGitHubParse.ParseIssues(mText, AMax, AIssues) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  Result := True;
end;

function TAtlasGitHubTracker.Lookup(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; ATimeoutMs: Integer; out AIssue: TAtlasTrackerIssue; out AError: TAtlasCiFetchError): Boolean;
var
  mUrl, mText: string;
  mStatus, mComments: Integer;
  mDetails: TAtlasTrackerDetails;
begin
  AIssue := TAtlasTrackerIssue.Empty;
  AError := TAtlasCiFetchError.None;
  Result := False;
  mUrl := TAtlasGitHubApi.IssueApiUrl(ATarget, AKey);
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
    AError := TAtlasGitHubApi.ErrorOfStatus(mStatus);
    Exit;
  end;
  if not TAtlasGitHubParse.ParseDetails(mText, mDetails, mComments) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  AIssue := mDetails.Issue;
  Result := True;
end;

function TAtlasGitHubTracker.Users(const ACall: TAtlasTrackerCall; const AText: string; AMax: Integer;
  out AUsers: TArray<TAtlasTrackerUser>; out AError: TAtlasCiFetchError): Boolean;
var
  mUrl, mText: string;
  mStatus: Integer;
  mUsers: TArray<TAtlasTrackerUser>;
begin
  AUsers := nil;
  AError := TAtlasCiFetchError.None;
  Result := False;
  mUrl := TAtlasGitHubApi.AssigneesUrl(ACall.Target);
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
    AError := TAtlasGitHubApi.ErrorOfStatus(mStatus);
    Exit;
  end;
  if not TAtlasGitHubParse.ParseUsers(mText, mUsers) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  // GitHub filtert …/assignees nicht: der getippte Text entscheidet hier.
  AUsers := TAtlasTrackerUser.Filter(mUsers, AText, AMax);
  Result := True;
end;

/// <summary>Pull Request für den Reiter „Entwicklung“, ohne Seite und Ampel.</summary>
function DevelopmentPullOf(const APull: TAtlasGitHubPull): TAtlasTrackerPull;
begin
  Result := Default(TAtlasTrackerPull);
  Result.Number := APull.Number;
  Result.Title := TAtlasGitHubJson.Shorten(APull.Title, TAtlasTrackerIssue.MaxTitle);
  Result.Branch := APull.Branch;
  Result.State := TAtlasGitHubParse.PullState(APull);
  Result.Updated := APull.Updated;
  Result.Checks := TAtlasTrackerChecks.Unknown;
end;

function TAtlasGitHubTracker.Development(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; ATimeoutMs: Integer; out ADevelopment: TAtlasTrackerDevelopment;
  out AError: TAtlasCiFetchError): Boolean;
var
  mWatch: TStopwatch;
  mCall: TAtlasTrackerCall;
  mUrl, mText: string;
  mNumber, mChecked: Integer;
  mPulls: TArray<TAtlasGitHubPull>;
  mGitHubPull: TAtlasGitHubPull;
  mPull: TAtlasTrackerPull;
begin
  ADevelopment := TAtlasTrackerDevelopment.Empty;
  AError := TAtlasCiFetchError.None;
  Result := False;
  mUrl := TAtlasGitHubApi.AllPullsUrl(ATarget);
  mNumber := TAtlasGitHubApi.NumberOfKey(AKey);
  if (mUrl = '') or (mNumber = 0) or (ATransport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  mWatch := TStopwatch.StartNew;
  if not TAtlasGitHubApi.GetText(ATransport, mUrl, ATimeoutMs, mText, AError) then
  begin
    Exit;
  end;
  Result := TAtlasGitHubParse.ParsePulls(mText, mPulls);
  if not Result then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  mCall := TAtlasTrackerCall.Create(ATarget, ATransport, ATimeoutMs);
  mChecked := 0;
  for mGitHubPull in mPulls do
  begin
    if Length(ADevelopment.Pulls) >= TAtlasTrackerDevelopment.MaxPulls then
    begin
      Break;
    end;
    if TAtlasGitHubParse.PullRefersTo(mGitHubPull, mNumber) then
    begin
      mPull := DevelopmentPullOf(mGitHubPull);
      mPull.Page := PullRequestPage(ATarget, mGitHubPull.Number);
      // Ampel in der restlichen Zeit, wie in der Liste: Check Runs, sonst der kombinierte Status.
      if TakeCheck(mCall, mWatch, mGitHubPull.Sha, mChecked) then
      begin
        mPull.Checks := ChecksOf(mCall, mWatch, mGitHubPull.Sha);
      end;
      ADevelopment.Pulls := ADevelopment.Pulls + [mPull];
    end;
  end;
end;

/// <summary>Benachrichtigungen seit APoll.Since, bedingt mit If-Modified-Since, wenn der Transport es kann;
/// übernimmt X-Poll-Interval in APoll.PollSeconds. False ohne Antwort.</summary>
function GetNotifications(const ACall: TAtlasTrackerCall; var APoll: TAtlasTrackerPoll;
  out AResponse: TAtlasCiResponse): Boolean;
var
  mConditional: IAtlasCiConditional;
  mUrl: string;
begin
  AResponse := Default(TAtlasCiResponse);
  mUrl := TAtlasGitHubApi.NotificationsUrl(ACall.Target, APoll.Since);
  if Supports(ACall.Transport, IAtlasCiConditional, mConditional) then
  begin
    Result := mConditional.GetConditional(mUrl, APoll.LastModified, ACall.TimeoutMs, AResponse);
  end
  else
  begin
    Result := ACall.Transport.Get(mUrl, ACall.TimeoutMs, AResponse.Status, AResponse.Text, AResponse.Error);
  end;
  if Result and (AResponse.PollSeconds > 0) then
  begin
    APoll.PollSeconds := AResponse.PollSeconds;
  end;
end;

/// <summary>Änderungen an einem Issue: neue Kommentare und Ereignisse; ohne erkennbare Einzelheit eine
/// allgemeine Änderung.</summary>
function ThreadChanges(const ACall: TAtlasTrackerCall; const AWatch: TStopwatch; const ABase: string;
  const AThread: TAtlasGitHubThread; const APoll: TAtlasTrackerPoll): TArray<TAtlasTrackerChange>;
var
  mIssueUrl, mText: string;
  mMore: TArray<TAtlasTrackerChange>;
begin
  Result := nil;
  mIssueUrl := ABase + '/repos/' + TTextUris.PercentEncode(AThread.Repository) + '/issues/' +
    IntToStr(AThread.Number);
  if TAtlasGitHubApi.GetInTime(ACall, AWatch, mIssueUrl + '/comments?since=' +
    TTextUris.PercentEncode(TAtlasGitHubApi.IsoTime(APoll.Since)) + '&per_page=' +
    IntToStr(TAtlasGitHubApi.MaxPageSize), mText)
    and TAtlasGitHubParse.ParseCommentChanges(mText, AThread, APoll.Since, mMore) then
  begin
    Result := Result + mMore;
  end;
  if TAtlasGitHubApi.GetInTime(ACall, AWatch, mIssueUrl + '/events?per_page=' + IntToStr(TAtlasGitHubApi.MaxPageSize),
    mText) and TAtlasGitHubParse.ParseEventChanges(mText, AThread, APoll.Me, APoll.Since, mMore) then
  begin
    Result := Result + mMore;
  end;
  // Nichts Erkennbares (z. B. Erwähnung, ältere Ereignisse auf späteren Seiten): allgemeine Änderung.
  if Length(Result) = 0 then
  begin
    Result := [TAtlasGitHubParse.ChangeOf(AThread, TAtlasTrackerChangeKind.Other, '', AThread.Updated)];
  end;
end;

/// <summary>Änderungen der Issues im Umfang, höchstens MaxChangedIssues; hebt APoll.Latest auf den jüngsten
/// Stand (auch ein Kommentar, den GitHub später stempelt als die Benachrichtigung, kommt nicht noch einmal).
/// </summary>
function CollectChanges(const ACall: TAtlasTrackerCall; const AWatch: TStopwatch; const ABase: string;
  const AThreads: TArray<TAtlasGitHubThread>; var APoll: TAtlasTrackerPoll): TArray<TAtlasTrackerChange>;
var
  mThread: TAtlasGitHubThread;
  mChange: TAtlasTrackerChange;
  mCount: Integer;
begin
  Result := nil;
  mCount := 0;
  for mThread in AThreads do
  begin
    if mThread.Updated > APoll.Latest then
    begin
      APoll.Latest := mThread.Updated;
    end;
    if TAtlasGitHubParse.InScope(mThread.Reason, APoll.Scope) and (mCount < TAtlasGitHubTracker.MaxChangedIssues) then
    begin
      Inc(mCount);
      Result := Result + ThreadChanges(ACall, AWatch, ABase, mThread, APoll);
    end;
  end;
  for mChange in Result do
  begin
    if mChange.Time > APoll.Latest then
    begin
      APoll.Latest := mChange.Time;
    end;
  end;
end;

function TAtlasGitHubTracker.Changes(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  ATimeoutMs: Integer; var APoll: TAtlasTrackerPoll; out AChanges: TArray<TAtlasTrackerChange>;
  out AError: TAtlasCiFetchError): Boolean;
var
  mWatch: TStopwatch;
  mCall: TAtlasTrackerCall;
  mBase: string;
  mThreads: TArray<TAtlasGitHubThread>;
  mResponse: TAtlasCiResponse;
begin
  AChanges := nil;
  AError := TAtlasCiFetchError.None;
  Result := False;
  mBase := TAtlasGitHubApi.Base(ATarget);
  if (mBase = '') or (ATransport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  mCall := TAtlasTrackerCall.Create(ATarget, ATransport, ATimeoutMs);
  mWatch := TStopwatch.StartNew;
  if not GetNotifications(mCall, APoll, mResponse) then
  begin
    AError := mResponse.Error;
  end
  else if mResponse.Status = 304 then
  begin
    // Unverändert seit der letzten Antwort.
    Result := True;
  end
  else if mResponse.Status <> 200 then
  begin
    AError := TAtlasGitHubApi.ErrorOfStatus(mResponse.Status);
  end
  else if not TAtlasGitHubParse.ParseNotifications(mResponse.Text, APoll.Since, mThreads) then
  begin
    AError := TAtlasCiFetchError.Invalid;
  end
  else
  begin
    if mResponse.LastModified <> '' then
    begin
      APoll.LastModified := mResponse.LastModified;
    end;
    Result := True;
    AChanges := CollectChanges(mCall, mWatch, mBase, mThreads, APoll);
  end;
end;

function TAtlasGitHubTracker.CanUpload: Boolean;
begin
  Result := False;
end;

function TAtlasGitHubTracker.Upload(const ATarget: TAtlasTrackerTarget; const ASend: IAtlasCiPost;
  const AKey: string; const AFiles: TAtlasAttachFiles; ATimeoutMs: Integer; out AError: TAtlasCiFetchError): Boolean;
begin
  // Die API von GitHub nimmt keine Dateien an; TAtlasAttachSender nimmt dann den Rückfall.
  AError := TAtlasCiFetchError.NotConfigured;
  Result := False;
end;

function TAtlasGitHubTracker.Comment(const ATarget: TAtlasTrackerTarget; const ASend: IAtlasCiPost; const AKey,
  AMarkdown: string; ATimeoutMs: Integer; out AError: TAtlasCiFetchError): Boolean;
var
  mResponse: TAtlasCiResponse;
begin
  Result := TAtlasAttachSender.Post(ASend, TAtlasGitHubApi.CommentsUrl(ATarget, AKey), 'application/json',
    TAtlasAttachComment.JsonBody('body', AMarkdown), ATimeoutMs, mResponse);
  AError := mResponse.Error;
  if not Result and (mResponse.Status <> 0) then
  begin
    AError := TAtlasGitHubApi.ErrorOfStatus(mResponse.Status);
  end;
end;

function TAtlasGitHubTracker.CommentText(const AComment: string; const AFiles: TAtlasAttachFiles): string;
begin
  Result := TAtlasAttachComment.WithTexts(AComment, AFiles, TAtlasAttachComment.MaxTextsLength);
end;

end.
