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
  private
    /// <summary>Verknüpfungen (#1279) in der restlichen Zeit: Unteraufgaben, „blocked by“, „blocking“, sonst
    /// Abhängigkeiten aus dem Text.</summary>
    procedure LoadRelations(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const AUrl: string; const ASummary: TAtlasGitHubLinkSummary; const AWatch: TStopwatch; ATimeoutMs: Integer;
      var ADetails: TAtlasTrackerDetails);
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
    function Details(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      AComments: Boolean; ATimeoutMs: Integer; out ADetails: TAtlasTrackerDetails;
      out AError: TAtlasCiFetchError): Boolean;
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
    function CreateSubtask(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const AParentKey, ATitle, ADescription: string; ATimeoutMs: Integer; out AKey: string;
      out AError: TAtlasCiFetchError): Boolean;
    function AddLink(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      AKind: TAtlasTrackerLinkKind; const AOtherKey: string; ATimeoutMs: Integer;
      out AError: TAtlasCiFetchError): Boolean;
    { IAtlasTrackerBoards (#1272): über TAtlasGitHubBoards }
    function LoadBoard(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const ABoardId, ASprintId: string; ATimeoutMs: Integer; out ASnapshot: TAtlasBoardSnapshot;
      out AError: TAtlasCiFetchError): Boolean;
    function MoveCard(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const ASnapshot: TAtlasBoardSnapshot; const ACard: TAtlasBoardCard; AColumn: Integer; const AComment: string;
      ATimeoutMs: Integer): TAtlasTrackerWriteResult;
    { IAtlasTrackerProvider: Suche und einzelnes Issue (#1270) }
    function Search(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const AText: string; ATimeoutMs, AMax: Integer; out AIssues: TArray<TAtlasTrackerIssue>;
      out AError: TAtlasCiFetchError): Boolean;
    function Lookup(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const AKey: string; ATimeoutMs: Integer; out AIssue: TAtlasTrackerIssue; out AError: TAtlasCiFetchError): Boolean;
    { IAtlasTrackerPeople }
    function Users(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const AText: string; ATimeoutMs, AMax: Integer; out AUsers: TArray<TAtlasTrackerUser>;
      out AError: TAtlasCiFetchError): Boolean;
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

function TAtlasGitHubTracker.Fetch(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  ATimeoutMs, AMax: Integer; out AIssues: TArray<TAtlasTrackerIssue>; out AError: TAtlasCiFetchError): Boolean;
var
  Watch: TStopwatch;
  Status, Index, PullIndex, Checked: Integer;
  Text: string;
  Pulls: TArray<TAtlasGitHubPull>;
  Checks: TAtlasTrackerChecks;
  Ignored: TAtlasCiFetchError;
  Pull: TAtlasGitHubPull;
begin
  AIssues := nil;
  AError := TAtlasCiFetchError.None;
  Result := False;
  if not ATarget.Configured or (ATransport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  Watch := TStopwatch.StartNew;
  if not ATransport.Get(TAtlasGitHubApi.SearchUrl(ATarget, AMax), ATimeoutMs, Status, Text, AError) then
  begin
    Exit;
  end;
  if Status <> 200 then
  begin
    AError := TAtlasGitHubApi.ErrorOfStatus(Status);
    Exit;
  end;
  if not TAtlasGitHubParse.ParseIssues(Text, AMax, AIssues) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  Result := True;
  if (Length(AIssues) = 0) or (TAtlasGitHubApi.Remaining(Watch, ATimeoutMs) = 0) then
  begin
    Exit;
  end;
  // Pull Requests und Ampeln in der restlichen Zeit; was fehlt, bleibt unbekannt.
  if not ATransport.Get(TAtlasGitHubApi.PullsUrl(ATarget), TAtlasGitHubApi.Remaining(Watch, ATimeoutMs), Status, Text,
    Ignored) or
    (Status <> 200) or not TAtlasGitHubParse.ParsePulls(Text, Pulls) then
  begin
    Exit;
  end;
  Checked := 0;
  for Index := 0 to High(AIssues) do
  begin
    for PullIndex := 0 to High(Pulls) do
    begin
      Pull := Pulls[PullIndex];
      if not TAtlasGitHubParse.PullMentions(Pull, AIssues[Index].Number) then
      begin
        Continue;
      end;
      AIssues[Index].PullRequest.Number := Pull.Number;
      AIssues[Index].PullRequest.Draft := Pull.Draft;
      if (Checked < MaxChecks) and (TAtlasGitHubApi.Remaining(Watch,
        ATimeoutMs) > 0) and (TAtlasGitHubApi.CheckRunsUrl(ATarget, Pull.Sha) <> '') then
      begin
        Inc(Checked);
        Checks := TAtlasTrackerChecks.Unknown;
        if ATransport.Get(TAtlasGitHubApi.CheckRunsUrl(ATarget, Pull.Sha), TAtlasGitHubApi.Remaining(Watch,
          ATimeoutMs), Status, Text, Ignored) and
          (Status = 200) then
        begin
          TAtlasGitHubParse.ParseCheckRuns(Text, Checks);
        end;
        // Ohne Check Runs: der ältere kombinierte Status (externe CI wie Jenkins).
        if (Checks = TAtlasTrackerChecks.Unknown) and (TAtlasGitHubApi.Remaining(Watch, ATimeoutMs) > 0) and
          ATransport.Get(TAtlasGitHubApi.StatusUrl(ATarget, Pull.Sha), TAtlasGitHubApi.Remaining(Watch, ATimeoutMs),
            Status, Text, Ignored) and
          (Status = 200) then
        begin
          TAtlasGitHubParse.ParseStatus(Text, Checks);
        end;
        AIssues[Index].PullRequest.Checks := Checks;
      end;
      Break;
    end;
  end;
  AError := TAtlasCiFetchError.None;
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

function TAtlasGitHubTracker.Details(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; AComments: Boolean; ATimeoutMs: Integer; out ADetails: TAtlasTrackerDetails;
  out AError: TAtlasCiFetchError): Boolean;
var
  mWatch: TStopwatch;
  mUrl, mText: string;
  mStatus, mCount, mPage: Integer;
  mIgnored: TAtlasCiFetchError;
  mComments, mOlder: TArray<TAtlasTrackerComment>;
  mLinks: TArray<TAtlasTrackerLink>;
  mSummary: TAtlasGitHubLinkSummary;
begin
  ADetails := TAtlasTrackerDetails.Empty;
  AError := TAtlasCiFetchError.None;
  Result := False;
  mUrl := TAtlasGitHubApi.IssueApiUrl(ATarget, AKey);
  if (mUrl = '') or (ATransport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  mWatch := TStopwatch.StartNew;
  if not ATransport.Get(mUrl, ATimeoutMs, mStatus, mText, AError) then
  begin
    Exit;
  end;
  if mStatus <> 200 then
  begin
    AError := TAtlasGitHubApi.ErrorOfStatus(mStatus);
    Exit;
  end;
  if not TAtlasGitHubParse.ParseDetails(mText, ADetails, mCount) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  mSummary := TAtlasGitHubParse.ParseLinkSummary(mText);
  ADetails.Page := IssuePage(ATarget, ADetails.Key);
  Result := True;
  // Kommentare und Verweise in der restlichen Zeit; was fehlt, bleibt leer.
  ADetails.CommentsLoaded := AComments;
  if AComments and (mCount > 0) and (TAtlasGitHubApi.Remaining(mWatch, ATimeoutMs) > 0) then
  begin
    // Die neuesten: letzte Seite, bei Bedarf die davor.
    mPage := (mCount + TAtlasGitHubApi.MaxPageSize - 1) div TAtlasGitHubApi.MaxPageSize;
    if ATransport.Get(mUrl + '/comments?per_page=' + IntToStr(TAtlasGitHubApi.MaxPageSize) + '&page=' + IntToStr(mPage),
      TAtlasGitHubApi.Remaining(mWatch, ATimeoutMs), mStatus, mText, mIgnored) and (mStatus = 200) and
      TAtlasGitHubParse.ParseComments(mText, mComments) then
    begin
      if (mPage > 1) and (Length(mComments) < TAtlasTrackerDetails.MaxComments) and
        (TAtlasGitHubApi.Remaining(mWatch, ATimeoutMs) > 0) and ATransport.Get(mUrl + '/comments?per_page=' +
        IntToStr(TAtlasGitHubApi.MaxPageSize) + '&page=' + IntToStr(mPage - 1), TAtlasGitHubApi.Remaining(mWatch,
          ATimeoutMs), mStatus, mText,
        mIgnored) and (mStatus = 200) and TAtlasGitHubParse.ParseComments(mText, mOlder) then
      begin
        mComments := mOlder + mComments;
      end;
      if Length(mComments) > TAtlasTrackerDetails.MaxComments then
      begin
        mComments := Copy(mComments, Length(mComments) - TAtlasTrackerDetails.MaxComments,
          TAtlasTrackerDetails.MaxComments);
      end;
      ADetails.Comments := mComments;
    end;
  end;
  if (TAtlasGitHubApi.Remaining(mWatch,
    ATimeoutMs) > 0) and ATransport.Get(mUrl + '/timeline?per_page=' + IntToStr(TAtlasGitHubApi.MaxPageSize),
    TAtlasGitHubApi.Remaining(mWatch, ATimeoutMs), mStatus, mText, mIgnored) and (mStatus = 200) and
    TAtlasGitHubParse.ParseTimeline(mText, ATarget.Project, mLinks) then
  begin
    ADetails.Links := mLinks;
  end;
  LoadRelations(ATarget, ATransport, mUrl, mSummary, mWatch, ATimeoutMs, ADetails);
  ADetails.Attachments := TAtlasGitHubParse.FileAttachments(ADetails);
end;

function TAtlasGitHubTracker.Apply(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; const AChange: TAtlasTrackerWrite; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
var
  mWatch: TStopwatch;
  mSend: IAtlasCiSend;
  mUrl, mText, mMe, mBody: string;
  mStatus: Integer;
  mError: TAtlasCiFetchError;
  mResponse: TAtlasCiResponse;
  mValue: TJSONValue;
  mLabels, mAssignees: TArray<string>;
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
  mWatch := TStopwatch.StartNew;
  mMe := '';
  if AChange.Assign = TAtlasTrackerAssign.Me then
  begin
    if not ATransport.Get(TAtlasGitHubApi.Base(ATarget) + '/user', ATimeoutMs, mStatus, mText, mError) then
    begin
      Exit(TAtlasTrackerWriteResult.Failed(mError, 0, ''));
    end;
    if mStatus <> 200 then
    begin
      Exit(TAtlasTrackerWriteResult.Failed(TAtlasGitHubApi.ErrorOfStatus(mStatus), mStatus,
        TAtlasGitHubApi.ErrorMessage(mText)));
    end;
    mValue := TJSONObject.ParseJSONValue(mText);
    try
      if mValue is TJSONObject then
      begin
        mMe := Trim(TAtlasGitHubJson.TextOf(TJSONObject(mValue), 'login'));
      end;
    finally
      mValue.Free;
    end;
    if mMe = '' then
    begin
      Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, mStatus, ''));
    end;
  end;
  // Zuerst der Kommentar: Fehlen die Schreibrechte, ändert sich nichts am Issue.
  if Trim(AChange.Comment) <> '' then
  begin
    Result := TAtlasGitHubApi.PostComment(ATarget, mSend, AKey, AChange.Comment,
      TAtlasGitHubApi.Remaining(mWatch, ATimeoutMs));
    if not Result.Succeeded then
    begin
      Exit;
    end;
  end;
  if (Trim(AChange.State) = '') and (AChange.Assign = TAtlasTrackerAssign.Keep) then
  begin
    Exit;
  end;
  if not ATransport.Get(mUrl, TAtlasGitHubApi.Remaining(mWatch, ATimeoutMs), mStatus, mText, mError) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(mError, 0, ''));
  end;
  if mStatus <> 200 then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasGitHubApi.ErrorOfStatus(mStatus), mStatus,
      TAtlasGitHubApi.ErrorMessage(mText)));
  end;
  if not TAtlasGitHubParse.ParseAssignment(mText, mLabels, mAssignees) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, mStatus, ''));
  end;
  mBody := TAtlasGitHubApi.PatchJson(mLabels, mAssignees, AChange, mMe);
  if mBody = '' then
  begin
    Exit;
  end;
  if not mSend.Send('PATCH', mUrl, mBody, TAtlasGitHubApi.Remaining(mWatch, ATimeoutMs), mResponse) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(mResponse.Error, 0, ''));
  end;
  if not TAtlasGitHubApi.Answered(mResponse.Status) then
  begin
    Result := TAtlasTrackerWriteResult.Failed(TAtlasGitHubApi.ErrorOfStatus(mResponse.Status), mResponse.Status,
      TAtlasGitHubApi.ErrorMessage(mResponse.Text));
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

procedure TAtlasGitHubTracker.LoadRelations(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AUrl: string; const ASummary: TAtlasGitHubLinkSummary; const AWatch: TStopwatch; ATimeoutMs: Integer;
  var ADetails: TAtlasTrackerDetails);
var
  mStatus, mNumber, mCount: Integer;
  mText: string;
  mIgnored: TAtlasCiFetchError;
  mLinks: TArray<TAtlasTrackerLink>;
  mLink: TAtlasTrackerLink;
  mOther: TAtlasTrackerDetails;
  mBlockers, mKnown: Boolean;
  mIndex: Integer;
begin
  // Nur fragen, was die Zusammenfassung meldet; ohne Zusammenfassung (-1) trotzdem.
  if (ASummary.SubIssues <> 0) and (TAtlasGitHubApi.Remaining(AWatch, ATimeoutMs) > 0) and
    ATransport.Get(AUrl + '/sub_issues?per_page=' + IntToStr(TAtlasGitHubApi.MaxPageSize),
      TAtlasGitHubApi.Remaining(AWatch, ATimeoutMs), mStatus,
    mText, mIgnored) and (mStatus = 200) and TAtlasGitHubParse.ParseRelated(mText, ATarget.Project,
      TAtlasTrackerLinkKind.Subtask,
    mLinks) then
  begin
    TAtlasGitHubParse.MergeLinks(ADetails.Links, mLinks);
  end;
  mBlockers := False;
  if (ASummary.BlockedBy <> 0) and (TAtlasGitHubApi.Remaining(AWatch, ATimeoutMs) > 0) and
    ATransport.Get(AUrl + '/dependencies/blocked_by?per_page=' + IntToStr(TAtlasGitHubApi.MaxPageSize),
      TAtlasGitHubApi.Remaining(AWatch,
    ATimeoutMs), mStatus, mText, mIgnored) and (mStatus = 200) and TAtlasGitHubParse.ParseRelated(mText,
      ATarget.Project,
    TAtlasTrackerLinkKind.DependsOn, mLinks) then
  begin
    TAtlasGitHubParse.MergeLinks(ADetails.Links, mLinks);
    mBlockers := Length(mLinks) > 0;
  end;
  if (ASummary.Blocking <> 0) and (TAtlasGitHubApi.Remaining(AWatch, ATimeoutMs) > 0) and
    ATransport.Get(AUrl + '/dependencies/blocking?per_page=' + IntToStr(TAtlasGitHubApi.MaxPageSize),
      TAtlasGitHubApi.Remaining(AWatch,
    ATimeoutMs), mStatus, mText, mIgnored) and (mStatus = 200) and TAtlasGitHubParse.ParseRelated(mText,
      ATarget.Project,
    TAtlasTrackerLinkKind.Blocks, mLinks) then
  begin
    TAtlasGitHubParse.MergeLinks(ADetails.Links, mLinks);
  end;
  if mBlockers then
  begin
    Exit;
  end;
  // Ohne „blocked by“: Abhängigkeiten aus dem Text, Zustand je Issue nachgefragt.
  for mNumber in TAtlasTrackerLinks.TextDependencies(ADetails.Description) do
  begin
    if mNumber = ADetails.Number then
    begin
      Continue;
    end;
    mLink := Default(TAtlasTrackerLink);
    mLink.Key := '#' + IntToStr(mNumber);
    mKnown := False;
    for mIndex := 0 to High(ADetails.Links) do
    begin
      if SameText(ADetails.Links[mIndex].Key, mLink.Key) and
        (ADetails.Links[mIndex].Kind = TAtlasTrackerLinkKind.DependsOn) then
      begin
        mKnown := True;
      end;
    end;
    if mKnown then
    begin
      Continue;
    end;
    mLink.Local := True;
    mLink.Kind := TAtlasTrackerLinkKind.DependsOn;
    mLink.Relation := 'depends on';
    mLink.Page := IssuePage(ATarget, mLink.Key);
    if (TAtlasGitHubApi.Remaining(AWatch, ATimeoutMs) > 0) and ATransport.Get(TAtlasGitHubApi.IssueApiUrl(ATarget,
      mLink.Key),
      TAtlasGitHubApi.Remaining(AWatch, ATimeoutMs), mStatus, mText, mIgnored) and (mStatus = 200) and
      TAtlasGitHubParse.ParseDetails(mText, mOther, mCount) then
    begin
      mLink.Title := TAtlasGitHubJson.Shorten(mOther.Title, 200);
      mLink.State := mOther.State;
      mLink.StateKnown := True;
      mLink.Resolved := StartsText('closed', mOther.State);
    end;
    TAtlasGitHubParse.MergeLinks(ADetails.Links, TArray<TAtlasTrackerLink>.Create(mLink));
  end;
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

function TAtlasGitHubTracker.CreateSubtask(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AParentKey, ATitle, ADescription: string; ATimeoutMs: Integer; out AKey: string;
  out AError: TAtlasCiFetchError): Boolean;
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
  mParent := TAtlasGitHubApi.IssueApiUrl(ATarget, AParentKey);
  if (mParent = '') or (ATransport = nil) or not Supports(ATransport, IAtlasCiSend, mPost) then
  begin
    Exit;
  end;
  if Trim(ATitle) = '' then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  mWatch := TStopwatch.StartNew;
  if not Posted(mPost, TAtlasGitHubApi.Base(ATarget) + '/repos/' + TTextUris.PercentEncode(ATarget.Project) + '/issues',
    TAtlasGitHubApi.NewIssueBody(ATitle, ADescription), ATimeoutMs, mText, AError) then
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
    TAtlasGitHubApi.Remaining(mWatch, ATimeoutMs),
    mText, AError);
end;

function TAtlasGitHubTracker.AddLink(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; AKind: TAtlasTrackerLinkKind; const AOtherKey: string; ATimeoutMs: Integer;
  out AError: TAtlasCiFetchError): Boolean;
var
  mPost: IAtlasCiSend;
  mWatch: TStopwatch;
  mBlocked, mBlocker, mText: string;
  mId: Int64;
begin
  AError := TAtlasCiFetchError.NotConfigured;
  Result := False;
  if (ATransport = nil) or not Supports(ATransport, IAtlasCiSend, mPost) then
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
  if (TAtlasGitHubApi.IssueApiUrl(ATarget, mBlocked) = '') or (TAtlasGitHubApi.IssueApiUrl(ATarget, mBlocker) = '') or
    (TAtlasGitHubApi.NumberOfKey(mBlocked) = TAtlasGitHubApi.NumberOfKey(mBlocker)) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  mWatch := TStopwatch.StartNew;
  mId := IssueId(ATarget, ATransport, mBlocker, ATimeoutMs, AError);
  if mId = 0 then
  begin
    Exit;
  end;
  Result := Posted(mPost, TAtlasGitHubApi.IssueApiUrl(ATarget, mBlocked) + '/dependencies/blocked_by',
    TAtlasGitHubApi.IdBody('issue_id', mId),
    TAtlasGitHubApi.Remaining(mWatch, ATimeoutMs), mText, AError);
end;


function TAtlasGitHubTracker.LoadBoard(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const ABoardId, ASprintId: string; ATimeoutMs: Integer; out ASnapshot: TAtlasBoardSnapshot;
  out AError: TAtlasCiFetchError): Boolean;
var
  mBoards: IAtlasTrackerBoards;
begin
  mBoards := TAtlasGitHubBoards.Create;
  Result := mBoards.LoadBoard(ATarget, ATransport, ABoardId, ASprintId, ATimeoutMs, ASnapshot, AError);
end;

function TAtlasGitHubTracker.MoveCard(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const ASnapshot: TAtlasBoardSnapshot; const ACard: TAtlasBoardCard; AColumn: Integer; const AComment: string;
  ATimeoutMs: Integer): TAtlasTrackerWriteResult;
var
  mBoards: IAtlasTrackerBoards;
begin
  mBoards := TAtlasGitHubBoards.Create;
  Result := mBoards.MoveCard(ATarget, ATransport, ASnapshot, ACard, AColumn, AComment, ATimeoutMs);
end;

function TAtlasGitHubTracker.Search(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AText: string; ATimeoutMs, AMax: Integer; out AIssues: TArray<TAtlasTrackerIssue>;
  out AError: TAtlasCiFetchError): Boolean;
var
  mUrl, mText: string;
  mStatus: Integer;
begin
  AIssues := nil;
  AError := TAtlasCiFetchError.None;
  Result := False;
  mUrl := TAtlasGitHubApi.TextSearchUrl(ATarget, AText, AMax);
  if not ATarget.Configured or (mUrl = '') or (ATransport = nil) then
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

function TAtlasGitHubTracker.Users(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AText: string; ATimeoutMs, AMax: Integer; out AUsers: TArray<TAtlasTrackerUser>;
  out AError: TAtlasCiFetchError): Boolean;
var
  mUrl, mText: string;
  mStatus: Integer;
  mUsers: TArray<TAtlasTrackerUser>;
begin
  AUsers := nil;
  AError := TAtlasCiFetchError.None;
  Result := False;
  mUrl := TAtlasGitHubApi.AssigneesUrl(ATarget);
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
  if not TAtlasGitHubParse.ParseUsers(mText, mUsers) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  // GitHub filtert …/assignees nicht: der getippte Text entscheidet hier.
  AUsers := TAtlasTrackerUser.Filter(mUsers, AText, AMax);
  Result := True;
end;

function TAtlasGitHubTracker.Development(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; ATimeoutMs: Integer; out ADevelopment: TAtlasTrackerDevelopment;
  out AError: TAtlasCiFetchError): Boolean;
var
  mWatch: TStopwatch;
  mUrl, mText: string;
  mStatus, mNumber, mChecked: Integer;
  mPulls: TArray<TAtlasGitHubPull>;
  mGitHubPull: TAtlasGitHubPull;
  mPull: TAtlasTrackerPull;
  mChecks: TAtlasTrackerChecks;
  mIgnored: TAtlasCiFetchError;
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
  if not ATransport.Get(mUrl, ATimeoutMs, mStatus, mText, AError) then
  begin
    Exit;
  end;
  if mStatus <> 200 then
  begin
    AError := TAtlasGitHubApi.ErrorOfStatus(mStatus);
    Exit;
  end;
  if not TAtlasGitHubParse.ParsePulls(mText, mPulls) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  Result := True;
  AError := TAtlasCiFetchError.None;
  mChecked := 0;
  for mGitHubPull in mPulls do
  begin
    if not TAtlasGitHubParse.PullRefersTo(mGitHubPull, mNumber) then
    begin
      Continue;
    end;
    if Length(ADevelopment.Pulls) >= TAtlasTrackerDevelopment.MaxPulls then
    begin
      Break;
    end;
    mPull := Default(TAtlasTrackerPull);
    mPull.Number := mGitHubPull.Number;
    mPull.Title := TAtlasGitHubJson.Shorten(mGitHubPull.Title, TAtlasTrackerIssue.MaxTitle);
    mPull.Branch := mGitHubPull.Branch;
    mPull.State := TAtlasGitHubParse.PullState(mGitHubPull);
    mPull.Updated := mGitHubPull.Updated;
    mPull.Page := PullRequestPage(ATarget, mGitHubPull.Number);
    mPull.Checks := TAtlasTrackerChecks.Unknown;
    // Ampel in der restlichen Zeit, wie in der Liste: Check Runs, sonst der kombinierte Status.
    if (mChecked < MaxChecks) and (TAtlasGitHubApi.Remaining(mWatch, ATimeoutMs) > 0) and
      (TAtlasGitHubApi.CheckRunsUrl(ATarget, mGitHubPull.Sha) <> '') then
    begin
      Inc(mChecked);
      mChecks := TAtlasTrackerChecks.Unknown;
      if ATransport.Get(TAtlasGitHubApi.CheckRunsUrl(ATarget, mGitHubPull.Sha), TAtlasGitHubApi.Remaining(mWatch,
        ATimeoutMs), mStatus, mText,
        mIgnored) and (mStatus = 200) then
      begin
        TAtlasGitHubParse.ParseCheckRuns(mText, mChecks);
      end;
      if (mChecks = TAtlasTrackerChecks.Unknown) and (TAtlasGitHubApi.Remaining(mWatch, ATimeoutMs) > 0) and
        ATransport.Get(TAtlasGitHubApi.StatusUrl(ATarget, mGitHubPull.Sha), TAtlasGitHubApi.Remaining(mWatch,
          ATimeoutMs), mStatus, mText,
        mIgnored) and (mStatus = 200) then
      begin
        TAtlasGitHubParse.ParseStatus(mText, mChecks);
      end;
      mPull.Checks := mChecks;
    end;
    ADevelopment.Pulls := ADevelopment.Pulls + [mPull];
  end;
end;

function TAtlasGitHubTracker.Changes(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  ATimeoutMs: Integer; var APoll: TAtlasTrackerPoll; out AChanges: TArray<TAtlasTrackerChange>;
  out AError: TAtlasCiFetchError): Boolean;
var
  mWatch: TStopwatch;
  mConditional: IAtlasCiConditional;
  mStatus, mPoll, mCount, mIndex: Integer;
  mText, mLastModified, mBase, mIssueUrl: string;
  mThreads: TArray<TAtlasGitHubThread>;
  mThread: TAtlasGitHubThread;
  mFound, mMore: TArray<TAtlasTrackerChange>;
  mIgnored: TAtlasCiFetchError;
  mAnswered: Boolean;
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
  mWatch := TStopwatch.StartNew;
  mPoll := 0;
  mLastModified := '';
  if Supports(ATransport, IAtlasCiConditional, mConditional) then
  begin
    mAnswered := mConditional.GetConditional(TAtlasGitHubApi.NotificationsUrl(ATarget, APoll.Since),
      APoll.LastModified, ATimeoutMs,
      mResponse);
    mStatus := mResponse.Status;
    mText := mResponse.Text;
    mLastModified := mResponse.LastModified;
    mPoll := mResponse.PollSeconds;
    AError := mResponse.Error;
  end
  else
  begin
    mAnswered := ATransport.Get(TAtlasGitHubApi.NotificationsUrl(ATarget, APoll.Since), ATimeoutMs, mStatus, mText,
      AError);
  end;
  if not mAnswered then
  begin
    Exit;
  end;
  if mPoll > 0 then
  begin
    APoll.PollSeconds := mPoll;
  end;
  // Unverändert seit der letzten Antwort.
  if mStatus = 304 then
  begin
    Exit(True);
  end;
  if mStatus <> 200 then
  begin
    AError := TAtlasGitHubApi.ErrorOfStatus(mStatus);
    Exit;
  end;
  if not TAtlasGitHubParse.ParseNotifications(mText, APoll.Since, mThreads) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  if mLastModified <> '' then
  begin
    APoll.LastModified := mLastModified;
  end;
  Result := True;
  mCount := 0;
  for mThread in mThreads do
  begin
    if mThread.Updated > APoll.Latest then
    begin
      APoll.Latest := mThread.Updated;
    end;
    if not TAtlasGitHubParse.InScope(mThread.Reason, APoll.Scope) or (mCount >= MaxChangedIssues) then
    begin
      Continue;
    end;
    Inc(mCount);
    mFound := nil;
    mIssueUrl := mBase + '/repos/' + TTextUris.PercentEncode(mThread.Repository) + '/issues/' +
      IntToStr(mThread.Number);
    if (TAtlasGitHubApi.Remaining(mWatch, ATimeoutMs) > 0) and ATransport.Get(mIssueUrl + '/comments?since=' +
      TTextUris.PercentEncode(TAtlasGitHubApi.IsoTime(APoll.Since)) + '&per_page=' +
        IntToStr(TAtlasGitHubApi.MaxPageSize),
      TAtlasGitHubApi.Remaining(mWatch, ATimeoutMs), mStatus, mText, mIgnored) and (mStatus = 200) and
      TAtlasGitHubParse.ParseCommentChanges(mText, mThread, APoll.Since, mMore) then
    begin
      mFound := mFound + mMore;
    end;
    if (TAtlasGitHubApi.Remaining(mWatch, ATimeoutMs) > 0) and ATransport.Get(mIssueUrl + '/events?per_page=' +
      IntToStr(TAtlasGitHubApi.MaxPageSize), TAtlasGitHubApi.Remaining(mWatch, ATimeoutMs), mStatus, mText,
        mIgnored) and (mStatus = 200) and
      TAtlasGitHubParse.ParseEventChanges(mText, mThread, APoll.Me, APoll.Since, mMore) then
    begin
      mFound := mFound + mMore;
    end;
    // Nichts Erkennbares (z. B. Erwähnung, ältere Ereignisse auf späteren Seiten): allgemeine Änderung.
    if Length(mFound) = 0 then
    begin
      mFound := [TAtlasGitHubParse.ChangeOf(mThread, TAtlasTrackerChangeKind.Other, '', mThread.Updated)];
    end;
    AChanges := AChanges + mFound;
  end;
  // Auch ein Kommentar, den GitHub später stempelt als die Benachrichtigung, kommt nicht noch einmal.
  for mIndex := 0 to High(AChanges) do
  begin
    if AChanges[mIndex].Time > APoll.Latest then
    begin
      APoll.Latest := AChanges[mIndex].Time;
    end;
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
