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
// Die Zeitgrenze gilt für die ganze Abfrage; reicht sie nach der Liste nicht
// mehr für Pull Requests und Ampeln, bleiben diese unbekannt.

interface

uses
  System.SysUtils,
  System.Diagnostics,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract;

type
  /// <summary>Offener Pull Request, wie ihn /pulls liefert.</summary>
  TAtlasGitHubPull = record
    Number: Integer;
    Draft: Boolean;
    Title: string;
    Body: string;
    Branch: string;
    Sha: string;
  end;

  /// <summary>Zusammenfassungen der Verknüpfungen eines Issues (#1279); -1 = unbekannt (ältere Server).</summary>
  TAtlasGitHubLinkSummary = record
    SubIssues: Integer;
    BlockedBy: Integer;
    Blocking: Integer;
  end;

  TAtlasGitHubTracker = class(TInterfacedObject, IAtlasTrackerProvider, IAtlasTrackerLinkWriter)
  public const
    ProviderName = 'github';
    Query = 'assignee:@me state:open';
    ApiHost = 'https://api.github.com';
    /// <summary>Höchstens so viele Pull Requests bekommen eine Ampel.</summary>
    MaxChecks = 8;
    /// <summary>Höchstens so viele offene Pull Requests werden gelesen.</summary>
    MaxPulls = 50;
    /// <summary>Einträge je Seite für Kommentare und Zeitleiste (#1264).</summary>
    MaxPageSize = 100;
  private
    /// <summary>Verknüpfungen (#1279) in der restlichen Zeit: Unteraufgaben, „blocked by“, „blocking“, sonst
    /// Abhängigkeiten aus dem Text.</summary>
    procedure LoadRelations(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const AUrl: string; const ASummary: TAtlasGitHubLinkSummary; const AWatch: TStopwatch; ATimeoutMs: Integer;
      var ADetails: TAtlasTrackerDetails);
  public
    /// <summary>Basis der REST-API ohne „/“ am Ende; '' ohne Server.</summary>
    class function ApiBase(const ATarget: TAtlasTrackerTarget): string; static;
    class function SearchUrl(const ATarget: TAtlasTrackerTarget; AMax: Integer): string; static;
    class function PullsUrl(const ATarget: TAtlasTrackerTarget): string; static;
    class function CheckRunsUrl(const ATarget: TAtlasTrackerTarget; const ASha: string): string; static;
    class function StatusUrl(const ATarget: TAtlasTrackerTarget; const ASha: string): string; static;
    /// <summary>Antwort von /search/issues; False bei ungültigem JSON.</summary>
    class function ParseIssues(const AJson: string; AMax: Integer;
      out AIssues: TArray<TAtlasTrackerIssue>): Boolean; static;
    /// <summary>Antwort von /pulls; False bei ungültigem JSON.</summary>
    class function ParsePulls(const AJson: string; out APulls: TArray<TAtlasGitHubPull>): Boolean; static;
    /// <summary>Der Pull Request gehört zu Issue ANumber (Branch, „closes #N“ in Titel oder Beschreibung).
    /// </summary>
    class function PullMentions(const APull: TAtlasGitHubPull; ANumber: Integer): Boolean; static;
    /// <summary>Antwort von /check-runs zusammengefasst: rot, sobald einer fehlschlug; gelb, solange einer läuft;
    /// sonst grün; Unknown ohne Check Runs. False bei ungültigem JSON.</summary>
    class function ParseCheckRuns(const AJson: string; out AChecks: TAtlasTrackerChecks): Boolean; static;
    /// <summary>Antwort von /status (kombinierter Status); Unknown ohne Einträge. False bei ungültigem JSON.
    /// </summary>
    class function ParseStatus(const AJson: string; out AChecks: TAtlasTrackerChecks): Boolean; static;
    /// <summary>Fehler zu einem HTTP-Status außer 200.</summary>
    class function ErrorOfStatus(AStatus: Integer): TAtlasCiFetchError; static;
    /// <summary>Adresse eines Issues in der API (ohne Anhang wie /comments); '' bei ungültiger Kennung.</summary>
    class function IssueApiUrl(const ATarget: TAtlasTrackerTarget; const AKey: string): string; static;
    /// <summary>Antwort von /issues/<n>; False bei ungültigem JSON bzw. ohne Nummer.</summary>
    class function ParseDetails(const AJson: string; out ADetails: TAtlasTrackerDetails;
      out ACommentCount: Integer): Boolean; static;
    /// <summary>Antwort von /issues/<n>/comments (älteste zuerst); False bei ungültigem JSON.</summary>
    class function ParseComments(const AJson: string; out AComments: TArray<TAtlasTrackerComment>): Boolean; static;
    /// <summary>Antwort von /issues/<n>/timeline: Verweise ("cross-referenced"); AProject entscheidet, was im
    /// Fenster öffnet. False bei ungültigem JSON.</summary>
    class function ParseTimeline(const AJson, AProject: string; out ALinks: TArray<TAtlasTrackerLink>): Boolean;
      static;
    /// <summary>Dateien in Beschreibung und Kommentaren als Anhänge (im Browser).</summary>
    class function FileAttachments(const ADetails: TAtlasTrackerDetails): TArray<TAtlasTrackerAttachment>; static;
    /// <summary>sub_issues_summary und issue_dependencies_summary aus /issues/<n> (#1279).</summary>
    class function ParseLinkSummary(const AJson: string): TAtlasGitHubLinkSummary; static;
    /// <summary>Liste von Issues (…/sub_issues, …/dependencies/…) als Verknüpfungen der Art AKind; AProject
    /// entscheidet, was im Fenster öffnet. False bei ungültigem JSON.</summary>
    class function ParseRelated(const AJson, AProject: string; AKind: TAtlasTrackerLinkKind;
      out ALinks: TArray<TAtlasTrackerLink>): Boolean; static;
    /// <summary>ANew in ALinks übernehmen: eine Erwähnung desselben Issues wird durch die genauere Art ersetzt,
    /// dieselbe Art nicht doppelt; höchstens TAtlasTrackerDetails.MaxLinks.</summary>
    class procedure MergeLinks(var ALinks: TArray<TAtlasTrackerLink>; const ANew: TArray<TAtlasTrackerLink>); static;
    /// <summary>Interne ID ("id") aus /issues/<n> bzw. der Antwort beim Anlegen; 0 ohne.</summary>
    class function ParseIssueId(const AJson: string): Int64; static;
    /// <summary>Inhalt für POST /issues.</summary>
    class function NewIssueBody(const ATitle, ADescription: string): string; static;
    /// <summary>Inhalt {"<AName>": AId} für sub_issues bzw. blocked_by.</summary>
    class function IdBody(const AName: string; AId: Int64): string; static;
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
    { IAtlasTrackerLinkWriter }
    function CreateSubtask(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const AParentKey, ATitle, ADescription: string; ATimeoutMs: Integer; out AKey: string;
      out AError: TAtlasCiFetchError): Boolean;
    function AddLink(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; const AKey: string;
      AKind: TAtlasTrackerLinkKind; const AOtherKey: string; ATimeoutMs: Integer;
      out AError: TAtlasCiFetchError): Boolean;
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
  Atlas.Core.Tracker.Naming;

function TextOf(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  Value := AObject.Values[AName];
  if Value is TJSONString then
    Result := TJSONString(Value).Value;
end;

function IntOf(AObject: TJSONObject; const AName: string): Integer;
var
  Value: TJSONValue;
  Number: Int64;
begin
  Result := 0;
  Value := AObject.Values[AName];
  if (Value is TJSONNumber) and TryStrToInt64(TJSONNumber(Value).Value, Number) and (Number > 0) and
    (Number <= MaxInt) then
    Result := Integer(Number);
end;

function FlagOf(AObject: TJSONObject; const AName: string): Boolean;
var
  Value: TJSONValue;
begin
  Value := AObject.Values[AName];
  Result := (Value is TJSONBool) and TJSONBool(Value).AsBoolean;
end;

function Shorten(const AText: string; AMax: Integer): string;
begin
  Result := Trim(StringReplace(StringReplace(AText, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]));
  if Length(Result) > AMax then
    Result := Copy(Result, 1, AMax - 1) + '…';
end;

{ TAtlasGitHubTracker }

class function TAtlasGitHubTracker.ApiBase(const ATarget: TAtlasTrackerTarget): string;
var
  Server: string;
begin
  Server := ATarget.Server;
  if Server = '' then
    Exit('');
  if (Server = 'https://github.com') or (Server = 'https://www.github.com') then
    Result := ApiHost
  else
    Result := Server + '/api/v3';
end;

class function TAtlasGitHubTracker.SearchUrl(const ATarget: TAtlasTrackerTarget; AMax: Integer): string;
var
  Text: string;
  Limit: Integer;
begin
  Result := ApiBase(ATarget);
  if (Result = '') or (ATarget.Project = '') then
    Exit('');
  Text := ATarget.Query;
  if Text = '' then
    Text := Query;
  Text := Text + ' repo:' + ATarget.Project + ' is:issue';
  Limit := AMax;
  if Limit < 1 then
    Limit := 1;
  if Limit > 100 then
    Limit := 100;
  Result := Result + '/search/issues?q=' + TTextUris.PercentEncode(Text) + '&per_page=' + IntToStr(Limit) +
    '&sort=updated&order=desc';
end;

class function TAtlasGitHubTracker.PullsUrl(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := ApiBase(ATarget);
  if (Result = '') or (ATarget.Project = '') then
    Exit('');
  Result := Result + '/repos/' + TTextUris.PercentEncode(ATarget.Project) + '/pulls?state=open&per_page=' +
    IntToStr(MaxPulls);
end;

function SafeSha(const ASha: string): Boolean;
var
  Index: Integer;
begin
  Result := (Length(ASha) >= 7) and (Length(ASha) <= 64);
  if Result then
    for Index := 1 to Length(ASha) do
      if not CharInSet(ASha[Index], ['0'..'9', 'a'..'f', 'A'..'F']) then
        Exit(False);
end;

class function TAtlasGitHubTracker.CheckRunsUrl(const ATarget: TAtlasTrackerTarget; const ASha: string): string;
begin
  Result := ApiBase(ATarget);
  if (Result = '') or (ATarget.Project = '') or not SafeSha(ASha) then
    Exit('');
  Result := Result + '/repos/' + TTextUris.PercentEncode(ATarget.Project) + '/commits/' + ASha +
    '/check-runs?per_page=100';
end;

class function TAtlasGitHubTracker.StatusUrl(const ATarget: TAtlasTrackerTarget; const ASha: string): string;
begin
  Result := ApiBase(ATarget);
  if (Result = '') or (ATarget.Project = '') or not SafeSha(ASha) then
    Exit('');
  Result := Result + '/repos/' + TTextUris.PercentEncode(ATarget.Project) + '/commits/' + ASha + '/status';
end;

class function TAtlasGitHubTracker.ParseIssues(const AJson: string; AMax: Integer;
  out AIssues: TArray<TAtlasTrackerIssue>): Boolean;
var
  Value, Items, Item, Labels, LabelValue: TJSONValue;
  Issue: TAtlasTrackerIssue;
  LabelName: string;
begin
  AIssues := nil;
  Result := False;
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Value is TJSONObject) then
      Exit;
    Items := TJSONObject(Value).Values['items'];
    if not (Items is TJSONArray) then
      Exit;
    Result := True;
    for Item in TJSONArray(Items) do
    begin
      if Length(AIssues) >= AMax then
        Break;
      if not (Item is TJSONObject) then
        Continue;
      // Die Suche liefert auch Pull Requests; die gehören nicht in die Liste.
      if TJSONObject(Item).Values['pull_request'] <> nil then
        Continue;
      Issue := TAtlasTrackerIssue.Empty;
      Issue.Number := IntOf(TJSONObject(Item), 'number');
      if Issue.Number <= 0 then
        Continue;
      Issue.Key := '#' + IntToStr(Issue.Number);
      Issue.Title := Shorten(TextOf(TJSONObject(Item), 'title'), TAtlasTrackerIssue.MaxTitle);
      Issue.State := TextOf(TJSONObject(Item), 'state');
      Labels := TJSONObject(Item).Values['labels'];
      if Labels is TJSONArray then
        for LabelValue in TJSONArray(Labels) do
        begin
          if Length(Issue.Labels) >= TAtlasTrackerIssue.MaxLabels then
            Break;
          LabelName := '';
          if LabelValue is TJSONObject then
            LabelName := Trim(TextOf(TJSONObject(LabelValue), 'name'))
          else if LabelValue is TJSONString then
            LabelName := Trim(TJSONString(LabelValue).Value);
          if LabelName <> '' then
            Issue.Labels := Issue.Labels + [Shorten(LabelName, 40)];
        end;
      AIssues := AIssues + [Issue];
    end;
  finally
    Value.Free;
  end;
end;

class function TAtlasGitHubTracker.ParsePulls(const AJson: string; out APulls: TArray<TAtlasGitHubPull>): Boolean;
var
  Value, Item, Head: TJSONValue;
  Pull: TAtlasGitHubPull;
begin
  APulls := nil;
  Result := False;
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Value is TJSONArray) then
      Exit;
    Result := True;
    for Item in TJSONArray(Value) do
    begin
      if not (Item is TJSONObject) then
        Continue;
      Pull := Default(TAtlasGitHubPull);
      Pull.Number := IntOf(TJSONObject(Item), 'number');
      if Pull.Number <= 0 then
        Continue;
      Pull.Draft := FlagOf(TJSONObject(Item), 'draft');
      Pull.Title := TextOf(TJSONObject(Item), 'title');
      // Nur der Anfang: „closes #N“ steht fast immer oben, und lange Beschreibungen kosten nur Speicher.
      Pull.Body := Copy(TextOf(TJSONObject(Item), 'body'), 1, 4000);
      Head := TJSONObject(Item).Values['head'];
      if Head is TJSONObject then
      begin
        Pull.Branch := TextOf(TJSONObject(Head), 'ref');
        Pull.Sha := TextOf(TJSONObject(Head), 'sha');
      end;
      APulls := APulls + [Pull];
    end;
  finally
    Value.Free;
  end;
end;

/// <summary>„close(s|d)“, „fix(es|ed)“ oder „resolve(s|d)“, optional „:“, dann „#N“ ohne weitere Ziffer.</summary>
function ClosesIssue(const AText: string; ANumber: Integer): Boolean;
const
  Words: array[0..8] of string = ('close', 'closes', 'closed', 'fix', 'fixes', 'fixed', 'resolve', 'resolves',
    'resolved');
var
  Lower, Mark: string;
  Index, Start, Stop: Integer;
  Word: string;
begin
  Result := False;
  Lower := LowerCase(AText);
  Mark := '#' + IntToStr(ANumber);
  Index := Pos(Mark, Lower);
  while Index > 0 do
  begin
    Stop := Index + Length(Mark);
    if (Stop > Length(Lower)) or not CharInSet(Lower[Stop], ['0'..'9']) then
    begin
      // Rückwärts: Leerzeichen und ":" überspringen, dann das Wort davor.
      Start := Index - 1;
      while (Start >= 1) and CharInSet(Lower[Start], [' ', ':', #9]) do
        Dec(Start);
      Stop := Start;
      while (Start >= 1) and CharInSet(Lower[Start], ['a'..'z']) do
        Dec(Start);
      if Stop > Start then
        for Word in Words do
          if Copy(Lower, Start + 1, Stop - Start) = Word then
            Exit(True);
    end;
    Index := Pos(Mark, Lower, Index + 1);
  end;
end;

class function TAtlasGitHubTracker.PullMentions(const APull: TAtlasGitHubPull; ANumber: Integer): Boolean;
begin
  Result := False;
  if ANumber <= 0 then
    Exit;
  Result := (TAtlasTrackerNaming.KeyOfBranch(ProviderName, '', APull.Branch) = '#' + IntToStr(ANumber)) or
    ClosesIssue(APull.Title, ANumber) or ClosesIssue(APull.Body, ANumber);
end;

class function TAtlasGitHubTracker.ParseCheckRuns(const AJson: string; out AChecks: TAtlasTrackerChecks): Boolean;
var
  Value, Runs, Run: TJSONValue;
  Status, Conclusion: string;
  Any, Running, Failed: Boolean;
begin
  AChecks := TAtlasTrackerChecks.Unknown;
  Result := False;
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Value is TJSONObject) then
      Exit;
    Runs := TJSONObject(Value).Values['check_runs'];
    if not (Runs is TJSONArray) then
      Exit;
    Result := True;
    Any := False;
    Running := False;
    Failed := False;
    for Run in TJSONArray(Runs) do
    begin
      if not (Run is TJSONObject) then
        Continue;
      Any := True;
      Status := LowerCase(TextOf(TJSONObject(Run), 'status'));
      Conclusion := LowerCase(TextOf(TJSONObject(Run), 'conclusion'));
      if Status <> 'completed' then
        Running := True
      else if (Conclusion = 'failure') or (Conclusion = 'timed_out') or (Conclusion = 'cancelled') or
        (Conclusion = 'action_required') or (Conclusion = 'startup_failure') then
        Failed := True;
    end;
    if Failed then
      AChecks := TAtlasTrackerChecks.Failure
    else if Running then
      AChecks := TAtlasTrackerChecks.Pending
    else if Any then
      AChecks := TAtlasTrackerChecks.Success;
  finally
    Value.Free;
  end;
end;

class function TAtlasGitHubTracker.ParseStatus(const AJson: string; out AChecks: TAtlasTrackerChecks): Boolean;
var
  Value, Statuses: TJSONValue;
  State: string;
begin
  AChecks := TAtlasTrackerChecks.Unknown;
  Result := False;
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Value is TJSONObject) then
      Exit;
    Result := True;
    // Ohne einzelne Status meldet GitHub "pending"; das ist keine Ampel.
    Statuses := TJSONObject(Value).Values['statuses'];
    if not (Statuses is TJSONArray) or (TJSONArray(Statuses).Count = 0) then
      Exit;
    State := LowerCase(TextOf(TJSONObject(Value), 'state'));
    if State = 'success' then
      AChecks := TAtlasTrackerChecks.Success
    else if (State = 'failure') or (State = 'error') then
      AChecks := TAtlasTrackerChecks.Failure
    else if State = 'pending' then
      AChecks := TAtlasTrackerChecks.Pending;
  finally
    Value.Free;
  end;
end;

class function TAtlasGitHubTracker.ErrorOfStatus(AStatus: Integer): TAtlasCiFetchError;
begin
  case AStatus of
    401, 403:
      Result := TAtlasCiFetchError.Unauthorized;
    404:
      Result := TAtlasCiFetchError.NotFound;
    400, 422:
      Result := TAtlasCiFetchError.Invalid;
    // Gelöschtes Issue (Vorschau, #1264).
    410:
      Result := TAtlasCiFetchError.NotFound;
  else
    Result := TAtlasCiFetchError.Server;
  end;
end;

function NumberOfKey(const AKey: string): Integer;
begin
  if not TryStrToInt(TAtlasTrackerNaming.BranchKey(AKey), Result) or (Result <= 0) then
    Result := 0;
end;

/// <summary>ISO 8601 ("2026-10-28T10:40:49Z") als UTC; 0 ohne.</summary>
function TimeOf(AObject: TJSONObject; const AName: string): TDateTime;
var
  mText: string;
begin
  Result := 0;
  mText := TextOf(AObject, AName);
  if (mText = '') or not TryISO8601ToDate(mText, Result, True) then
    Result := 0;
end;

function LoginOf(AValue: TJSONValue): string;
begin
  Result := '';
  if AValue is TJSONObject then
    Result := Shorten(TextOf(TJSONObject(AValue), 'login'), 60);
end;

function Limited(const AText: string): string;
begin
  Result := Copy(AText, 1, TAtlasTrackerDetails.MaxText);
end;

class function TAtlasGitHubTracker.IssueApiUrl(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
var
  mNumber: Integer;
begin
  Result := ApiBase(ATarget);
  mNumber := NumberOfKey(AKey);
  if (Result = '') or (ATarget.Project = '') or (mNumber = 0) then
    Exit('');
  Result := Result + '/repos/' + TTextUris.PercentEncode(ATarget.Project) + '/issues/' + IntToStr(mNumber);
end;

class function TAtlasGitHubTracker.ParseDetails(const AJson: string; out ADetails: TAtlasTrackerDetails;
  out ACommentCount: Integer): Boolean;
var
  mValue, mItem, mEntry: TJSONValue;
  mRoot: TJSONObject;
  mText, mReason: string;
begin
  ADetails := TAtlasTrackerDetails.Empty;
  ACommentCount := 0;
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) then
      Exit;
    mRoot := TJSONObject(mValue);
    ADetails.Number := IntOf(mRoot, 'number');
    if ADetails.Number <= 0 then
      Exit;
    ADetails.Key := '#' + IntToStr(ADetails.Number);
    ADetails.Title := Shorten(TextOf(mRoot, 'title'), 500);
    ADetails.Description := Limited(TextOf(mRoot, 'body'));
    // "closed" mit Grund ("completed", "not_planned") wie in der Oberfläche.
    ADetails.State := TextOf(mRoot, 'state');
    mReason := TextOf(mRoot, 'state_reason');
    if (ADetails.State = 'closed') and (mReason <> '') and (mReason <> 'completed') then
      ADetails.State := ADetails.State + ' (' + StringReplace(mReason, '_', ' ', [rfReplaceAll]) + ')';
    ADetails.Created := TimeOf(mRoot, 'created_at');
    ADetails.Updated := TimeOf(mRoot, 'updated_at');
    ACommentCount := IntOf(mRoot, 'comments');
    mItem := mRoot.Values['labels'];
    if mItem is TJSONArray then
      for mEntry in TJSONArray(mItem) do
      begin
        mText := '';
        if mEntry is TJSONObject then
          mText := Trim(TextOf(TJSONObject(mEntry), 'name'))
        else if mEntry is TJSONString then
          mText := Trim(TJSONString(mEntry).Value);
        if mText <> '' then
          ADetails.Labels := ADetails.Labels + [Shorten(mText, 40)];
      end;
    mItem := mRoot.Values['assignees'];
    if mItem is TJSONArray then
      for mEntry in TJSONArray(mItem) do
      begin
        mText := LoginOf(mEntry);
        if mText = '' then
          Continue;
        if ADetails.Assignee <> '' then
          ADetails.Assignee := ADetails.Assignee + ', ';
        ADetails.Assignee := ADetails.Assignee + mText;
      end;
    if ADetails.Assignee = '' then
      ADetails.Assignee := LoginOf(mRoot.Values['assignee']);
    if mRoot.Values['milestone'] is TJSONObject then
      ADetails.Sprint := Shorten(TextOf(TJSONObject(mRoot.Values['milestone']), 'title'), 60);
    // Issue-Typen (Bug, Feature …) der Organisation.
    if mRoot.Values['type'] is TJSONObject then
      ADetails.Kind := Shorten(TextOf(TJSONObject(mRoot.Values['type']), 'name'), 40);
    Result := True;
  finally
    mValue.Free;
  end;
end;

class function TAtlasGitHubTracker.ParseComments(const AJson: string;
  out AComments: TArray<TAtlasTrackerComment>): Boolean;
var
  mValue, mItem: TJSONValue;
  mComment: TAtlasTrackerComment;
begin
  AComments := nil;
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
      mComment := Default(TAtlasTrackerComment);
      mComment.Author := LoginOf(TJSONObject(mItem).Values['user']);
      mComment.Created := TimeOf(TJSONObject(mItem), 'created_at');
      mComment.Text := Limited(TextOf(TJSONObject(mItem), 'body'));
      AComments := AComments + [mComment];
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasGitHubTracker.ParseTimeline(const AJson, AProject: string;
  out ALinks: TArray<TAtlasTrackerLink>): Boolean;
var
  mValue, mItem, mSource, mIssue: TJSONValue;
  mLink: TAtlasTrackerLink;
  mRepository, mPage: string;
  mNumber, mIndex: Integer;
  mKnown: Boolean;
begin
  ALinks := nil;
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONArray) then
      Exit;
    Result := True;
    for mItem in TJSONArray(mValue) do
    begin
      if not (mItem is TJSONObject) or (TextOf(TJSONObject(mItem), 'event') <> 'cross-referenced') then
        Continue;
      mSource := TJSONObject(mItem).Values['source'];
      if not (mSource is TJSONObject) then
        Continue;
      mIssue := TJSONObject(mSource).Values['issue'];
      if not (mIssue is TJSONObject) then
        Continue;
      mNumber := IntOf(TJSONObject(mIssue), 'number');
      if mNumber <= 0 then
        Continue;
      mRepository := '';
      if TJSONObject(mIssue).Values['repository'] is TJSONObject then
        mRepository := TextOf(TJSONObject(TJSONObject(mIssue).Values['repository']), 'full_name');
      mLink := Default(TAtlasTrackerLink);
      mLink.Local := (mRepository = '') or SameText(mRepository, AProject);
      if mLink.Local then
        mLink.Key := '#' + IntToStr(mNumber)
      else
        mLink.Key := mRepository + '#' + IntToStr(mNumber);
      mLink.Title := Shorten(TextOf(TJSONObject(mIssue), 'title'), 200);
      if TJSONObject(mIssue).Values['pull_request'] <> nil then
      begin
        mLink.Relation := 'pull request';
        mLink.Kind := TAtlasTrackerLinkKind.PullRequest;
      end
      else
      begin
        mLink.Relation := 'cross-referenced';
        mLink.Kind := TAtlasTrackerLinkKind.Mentioned;
      end;
      // Zustand (#1279) steht im Eintrag.
      mLink.State := TextOf(TJSONObject(mIssue), 'state');
      mLink.StateKnown := mLink.State <> '';
      mLink.Resolved := SameText(mLink.State, 'closed');
      // Nur Web-Seiten über https; was nicht im Fenster öffnet, geht in den Browser.
      mPage := TextOf(TJSONObject(mIssue), 'html_url');
      if StartsText('https://', mPage) then
        mLink.Page := mPage;
      mKnown := False;
      for mIndex := 0 to High(ALinks) do
        if SameText(ALinks[mIndex].Key, mLink.Key) then
          mKnown := True;
      if not mKnown and (Length(ALinks) < TAtlasTrackerDetails.MaxLinks) then
        ALinks := ALinks + [mLink];
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasGitHubTracker.FileAttachments(
  const ADetails: TAtlasTrackerDetails): TArray<TAtlasTrackerAttachment>;
var
  mTexts: TArray<string>;
  mText: string;
  mComment: TAtlasTrackerComment;
  mLink: TAtlasMarkdownLink;
  mAttachment: TAtlasTrackerAttachment;
  mIndex: Integer;
  mKnown: Boolean;
begin
  Result := nil;
  mTexts := TArray<string>.Create(ADetails.Description);
  for mComment in ADetails.Comments do
    mTexts := mTexts + [mComment.Text];
  for mText in mTexts do
    for mLink in TAtlasTrackerMarkdown.Links(mText) do
    begin
      if not StartsText('https://', mLink.Url) or (Pos('/user-attachments/files/', mLink.Url) = 0) then
        Continue;
      mKnown := False;
      for mIndex := 0 to High(Result) do
        if Result[mIndex].Url = mLink.Url then
          mKnown := True;
      if mKnown or (Length(Result) >= TAtlasTrackerDetails.MaxAttachments) then
        Continue;
      mAttachment := Default(TAtlasTrackerAttachment);
      mAttachment.Name := Shorten(mLink.Text, 200);
      if mAttachment.Name = '' then
        mAttachment.Name := Copy(mLink.Url, LastDelimiter('/', mLink.Url) + 1, 200);
      mAttachment.Size := -1;
      mAttachment.Url := mLink.Url;
      mAttachment.External := True;
      Result := Result + [mAttachment];
    end;
end;

function TAtlasGitHubTracker.Name: string;
begin
  Result := ProviderName;
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
  Result := TAtlasTrackerTarget.Create('', ApiBase(ATarget), '', '').Server;
end;

function Remaining(const AWatch: TStopwatch; ATimeoutMs: Integer): Integer;
var
  Rest: Int64;
begin
  Rest := ATimeoutMs - AWatch.ElapsedMilliseconds;
  Result := 0;
  if Rest > 0 then
    Result := Integer(Rest);
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
  if not ATransport.Get(SearchUrl(ATarget, AMax), ATimeoutMs, Status, Text, AError) then
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
  if (Length(AIssues) = 0) or (Remaining(Watch, ATimeoutMs) = 0) then
    Exit;
  // Pull Requests und Ampeln in der restlichen Zeit; was fehlt, bleibt unbekannt.
  if not ATransport.Get(PullsUrl(ATarget), Remaining(Watch, ATimeoutMs), Status, Text, Ignored) or
    (Status <> 200) or not ParsePulls(Text, Pulls) then
    Exit;
  Checked := 0;
  for Index := 0 to High(AIssues) do
    for PullIndex := 0 to High(Pulls) do
    begin
      Pull := Pulls[PullIndex];
      if not PullMentions(Pull, AIssues[Index].Number) then
        Continue;
      AIssues[Index].PullRequest.Number := Pull.Number;
      AIssues[Index].PullRequest.Draft := Pull.Draft;
      if (Checked < MaxChecks) and (Remaining(Watch, ATimeoutMs) > 0) and (CheckRunsUrl(ATarget, Pull.Sha) <> '') then
      begin
        Inc(Checked);
        Checks := TAtlasTrackerChecks.Unknown;
        if ATransport.Get(CheckRunsUrl(ATarget, Pull.Sha), Remaining(Watch, ATimeoutMs), Status, Text, Ignored) and
          (Status = 200) then
          ParseCheckRuns(Text, Checks);
        // Ohne Check Runs: der ältere kombinierte Status (externe CI wie Jenkins).
        if (Checks = TAtlasTrackerChecks.Unknown) and (Remaining(Watch, ATimeoutMs) > 0) and
          ATransport.Get(StatusUrl(ATarget, Pull.Sha), Remaining(Watch, ATimeoutMs), Status, Text, Ignored) and
          (Status = 200) then
          ParseStatus(Text, Checks);
        AIssues[Index].PullRequest.Checks := Checks;
      end;
      Break;
    end;
  AError := TAtlasCiFetchError.None;
end;

function TAtlasGitHubTracker.IssuePage(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
var
  Number: Integer;
begin
  Result := '';
  if (ATarget.Server = '') or (ATarget.Project = '') then
    Exit;
  if not TryStrToInt(TAtlasTrackerNaming.BranchKey(AKey), Number) or (Number <= 0) then
    Exit;
  Result := ATarget.Server + '/' + TTextUris.PercentEncode(ATarget.Project) + '/issues/' + IntToStr(Number);
end;

function TAtlasGitHubTracker.PullRequestPage(const ATarget: TAtlasTrackerTarget; ANumber: Integer): string;
begin
  Result := '';
  if (ATarget.Server = '') or (ATarget.Project = '') or (ANumber <= 0) then
    Exit;
  Result := ATarget.Server + '/' + TTextUris.PercentEncode(ATarget.Project) + '/pull/' + IntToStr(ANumber);
end;

function TAtlasGitHubTracker.ProbeUrl(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := ApiBase(ATarget);
  if Result <> '' then
    Result := Result + '/user';
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
  mUrl := IssueApiUrl(ATarget, AKey);
  if (mUrl = '') or (ATransport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  mWatch := TStopwatch.StartNew;
  if not ATransport.Get(mUrl, ATimeoutMs, mStatus, mText, AError) then
    Exit;
  if mStatus <> 200 then
  begin
    AError := ErrorOfStatus(mStatus);
    Exit;
  end;
  if not ParseDetails(mText, ADetails, mCount) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  mSummary := ParseLinkSummary(mText);
  ADetails.Page := IssuePage(ATarget, ADetails.Key);
  Result := True;
  // Kommentare und Verweise in der restlichen Zeit; was fehlt, bleibt leer.
  ADetails.CommentsLoaded := AComments;
  if AComments and (mCount > 0) and (Remaining(mWatch, ATimeoutMs) > 0) then
  begin
    // Die neuesten: letzte Seite, bei Bedarf die davor.
    mPage := (mCount + MaxPageSize - 1) div MaxPageSize;
    if ATransport.Get(mUrl + '/comments?per_page=' + IntToStr(MaxPageSize) + '&page=' + IntToStr(mPage),
      Remaining(mWatch, ATimeoutMs), mStatus, mText, mIgnored) and (mStatus = 200) and
      ParseComments(mText, mComments) then
    begin
      if (mPage > 1) and (Length(mComments) < TAtlasTrackerDetails.MaxComments) and
        (Remaining(mWatch, ATimeoutMs) > 0) and ATransport.Get(mUrl + '/comments?per_page=' +
        IntToStr(MaxPageSize) + '&page=' + IntToStr(mPage - 1), Remaining(mWatch, ATimeoutMs), mStatus, mText,
        mIgnored) and (mStatus = 200) and ParseComments(mText, mOlder) then
        mComments := mOlder + mComments;
      if Length(mComments) > TAtlasTrackerDetails.MaxComments then
        mComments := Copy(mComments, Length(mComments) - TAtlasTrackerDetails.MaxComments,
          TAtlasTrackerDetails.MaxComments);
      ADetails.Comments := mComments;
    end;
  end;
  if (Remaining(mWatch, ATimeoutMs) > 0) and ATransport.Get(mUrl + '/timeline?per_page=' + IntToStr(MaxPageSize),
    Remaining(mWatch, ATimeoutMs), mStatus, mText, mIgnored) and (mStatus = 200) and
    ParseTimeline(mText, ATarget.Project, mLinks) then
    ADetails.Links := mLinks;
  LoadRelations(ATarget, ATransport, mUrl, mSummary, mWatch, ATimeoutMs, ADetails);
  ADetails.Attachments := FileAttachments(ADetails);
end;

{ Verknüpfungen (#1279) }

function SummaryCount(ARoot: TJSONObject; const AObject, AName: string): Integer;
var
  mValue: TJSONValue;
  mNumber: Int64;
begin
  Result := -1;
  mValue := ARoot.Values[AObject];
  if not (mValue is TJSONObject) then
    Exit;
  mValue := TJSONObject(mValue).Values[AName];
  if (mValue is TJSONNumber) and TryStrToInt64(TJSONNumber(mValue).Value, mNumber) and (mNumber >= 0) and
    (mNumber <= MaxInt) then
    Result := Integer(mNumber);
end;

class function TAtlasGitHubTracker.ParseLinkSummary(const AJson: string): TAtlasGitHubLinkSummary;
var
  mValue: TJSONValue;
begin
  Result.SubIssues := -1;
  Result.BlockedBy := -1;
  Result.Blocking := -1;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) then
      Exit;
    Result.SubIssues := SummaryCount(TJSONObject(mValue), 'sub_issues_summary', 'total');
    Result.BlockedBy := SummaryCount(TJSONObject(mValue), 'issue_dependencies_summary', 'total_blocked_by');
    Result.Blocking := SummaryCount(TJSONObject(mValue), 'issue_dependencies_summary', 'total_blocking');
  finally
    mValue.Free;
  end;
end;

/// <summary>"owner/repo" eines Issues aus repository_url (…/repos/owner/repo); '' ohne.</summary>
function RepositoryOf(AIssue: TJSONObject): string;
var
  mUrl: string;
  mAt: Integer;
begin
  Result := '';
  mUrl := TextOf(AIssue, 'repository_url');
  mAt := Pos('/repos/', mUrl);
  if mAt > 0 then
    Result := Copy(mUrl, mAt + Length('/repos/'), MaxInt);
end;

class function TAtlasGitHubTracker.ParseRelated(const AJson, AProject: string; AKind: TAtlasTrackerLinkKind;
  out ALinks: TArray<TAtlasTrackerLink>): Boolean;
const
  Relations: array[TAtlasTrackerLinkKind] of string = ('', 'blocked by', 'blocking', 'sub-issue', 'parent', '', '',
    '', 'cross-referenced', 'pull request');
var
  mValue, mItem: TJSONValue;
  mIssue: TJSONObject;
  mLink: TAtlasTrackerLink;
  mNumber: Integer;
  mRepository, mPage: string;
begin
  ALinks := nil;
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONArray) then
      Exit;
    Result := True;
    for mItem in TJSONArray(mValue) do
    begin
      if not (mItem is TJSONObject) or (Length(ALinks) >= TAtlasTrackerDetails.MaxLinks) then
        Continue;
      mIssue := TJSONObject(mItem);
      mNumber := IntOf(mIssue, 'number');
      if mNumber <= 0 then
        Continue;
      mRepository := RepositoryOf(mIssue);
      mLink := Default(TAtlasTrackerLink);
      mLink.Local := (mRepository = '') or SameText(mRepository, AProject);
      if mLink.Local then
        mLink.Key := '#' + IntToStr(mNumber)
      else
        mLink.Key := mRepository + '#' + IntToStr(mNumber);
      mLink.Title := Shorten(TextOf(mIssue, 'title'), 200);
      mLink.Kind := AKind;
      mLink.Relation := Relations[AKind];
      mLink.State := TextOf(mIssue, 'state');
      mLink.StateKnown := mLink.State <> '';
      mLink.Resolved := SameText(mLink.State, 'closed');
      mPage := TextOf(mIssue, 'html_url');
      if StartsText('https://', mPage) then
        mLink.Page := mPage;
      ALinks := ALinks + [mLink];
    end;
  finally
    mValue.Free;
  end;
end;

class procedure TAtlasGitHubTracker.MergeLinks(var ALinks: TArray<TAtlasTrackerLink>;
  const ANew: TArray<TAtlasTrackerLink>);
var
  mLink: TAtlasTrackerLink;
  mIndex: Integer;
  mDone: Boolean;
begin
  for mLink in ANew do
  begin
    mDone := False;
    for mIndex := 0 to High(ALinks) do
      if SameText(ALinks[mIndex].Key, mLink.Key) then
      begin
        if ALinks[mIndex].Kind = mLink.Kind then
          mDone := True
        // Die Erwähnung desselben Issues weicht der genaueren Art.
        else if ALinks[mIndex].Kind in [TAtlasTrackerLinkKind.Mentioned, TAtlasTrackerLinkKind.Other] then
        begin
          ALinks[mIndex] := mLink;
          mDone := True;
        end;
        if mDone then
          Break;
      end;
    if not mDone and (Length(ALinks) < TAtlasTrackerDetails.MaxLinks) then
      ALinks := ALinks + [mLink];
  end;
end;

class function TAtlasGitHubTracker.ParseIssueId(const AJson: string): Int64;
var
  mValue, mId: TJSONValue;
begin
  Result := 0;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) then
      Exit;
    mId := TJSONObject(mValue).Values['id'];
    if not (mId is TJSONNumber) or not TryStrToInt64(TJSONNumber(mId).Value, Result) or (Result < 0) then
      Result := 0;
  finally
    mValue.Free;
  end;
end;

class function TAtlasGitHubTracker.NewIssueBody(const ATitle, ADescription: string): string;
var
  mRoot: TJSONObject;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('title', Trim(ATitle));
    if Trim(ADescription) <> '' then
      mRoot.AddPair('body', ADescription);
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasGitHubTracker.IdBody(const AName: string; AId: Int64): string;
var
  mRoot: TJSONObject;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair(AName, TJSONNumber.Create(AId));
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
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
  if (ASummary.SubIssues <> 0) and (Remaining(AWatch, ATimeoutMs) > 0) and
    ATransport.Get(AUrl + '/sub_issues?per_page=' + IntToStr(MaxPageSize), Remaining(AWatch, ATimeoutMs), mStatus,
    mText, mIgnored) and (mStatus = 200) and ParseRelated(mText, ATarget.Project, TAtlasTrackerLinkKind.Subtask,
    mLinks) then
    MergeLinks(ADetails.Links, mLinks);
  mBlockers := False;
  if (ASummary.BlockedBy <> 0) and (Remaining(AWatch, ATimeoutMs) > 0) and
    ATransport.Get(AUrl + '/dependencies/blocked_by?per_page=' + IntToStr(MaxPageSize), Remaining(AWatch,
    ATimeoutMs), mStatus, mText, mIgnored) and (mStatus = 200) and ParseRelated(mText, ATarget.Project,
    TAtlasTrackerLinkKind.DependsOn, mLinks) then
  begin
    MergeLinks(ADetails.Links, mLinks);
    mBlockers := Length(mLinks) > 0;
  end;
  if (ASummary.Blocking <> 0) and (Remaining(AWatch, ATimeoutMs) > 0) and
    ATransport.Get(AUrl + '/dependencies/blocking?per_page=' + IntToStr(MaxPageSize), Remaining(AWatch,
    ATimeoutMs), mStatus, mText, mIgnored) and (mStatus = 200) and ParseRelated(mText, ATarget.Project,
    TAtlasTrackerLinkKind.Blocks, mLinks) then
    MergeLinks(ADetails.Links, mLinks);
  if mBlockers then
    Exit;
  // Ohne „blocked by“: Abhängigkeiten aus dem Text, Zustand je Issue nachgefragt.
  for mNumber in TAtlasTrackerLinks.TextDependencies(ADetails.Description) do
  begin
    if mNumber = ADetails.Number then
      Continue;
    mLink := Default(TAtlasTrackerLink);
    mLink.Key := '#' + IntToStr(mNumber);
    mKnown := False;
    for mIndex := 0 to High(ADetails.Links) do
      if SameText(ADetails.Links[mIndex].Key, mLink.Key) and
        (ADetails.Links[mIndex].Kind = TAtlasTrackerLinkKind.DependsOn) then
        mKnown := True;
    if mKnown then
      Continue;
    mLink.Local := True;
    mLink.Kind := TAtlasTrackerLinkKind.DependsOn;
    mLink.Relation := 'depends on';
    mLink.Page := IssuePage(ATarget, mLink.Key);
    if (Remaining(AWatch, ATimeoutMs) > 0) and ATransport.Get(IssueApiUrl(ATarget, mLink.Key),
      Remaining(AWatch, ATimeoutMs), mStatus, mText, mIgnored) and (mStatus = 200) and
      ParseDetails(mText, mOther, mCount) then
    begin
      mLink.Title := Shorten(mOther.Title, 200);
      mLink.State := mOther.State;
      mLink.StateKnown := True;
      mLink.Resolved := StartsText('closed', mOther.State);
    end;
    MergeLinks(ADetails.Links, TArray<TAtlasTrackerLink>.Create(mLink));
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
  if not ATransport.Get(TAtlasGitHubTracker.IssueApiUrl(ATarget, AKey), ATimeoutMs, mStatus, mText, AError) then
    Exit;
  if mStatus <> 200 then
  begin
    AError := TAtlasGitHubTracker.ErrorOfStatus(mStatus);
    Exit;
  end;
  Result := TAtlasGitHubTracker.ParseIssueId(mText);
  if Result = 0 then
    AError := TAtlasCiFetchError.Invalid;
end;

/// <summary>POST mit AStatus 200/201 als Erfolg.</summary>
function Posted(const APost: IAtlasCiPost; const AUrl, ABody: string; ATimeoutMs: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
var
  mStatus: Integer;
begin
  Result := False;
  if not APost.Post(AUrl, ABody, ATimeoutMs, mStatus, AText, AError) then
    Exit;
  if (mStatus <> 200) and (mStatus <> 201) then
  begin
    AError := TAtlasGitHubTracker.ErrorOfStatus(mStatus);
    Exit;
  end;
  AError := TAtlasCiFetchError.None;
  Result := True;
end;

function TAtlasGitHubTracker.CreateSubtask(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AParentKey, ATitle, ADescription: string; ATimeoutMs: Integer; out AKey: string;
  out AError: TAtlasCiFetchError): Boolean;
var
  mPost: IAtlasCiPost;
  mWatch: TStopwatch;
  mParent, mText: string;
  mId: Int64;
  mNumber: Integer;
  mValue: TJSONValue;
begin
  AKey := '';
  AError := TAtlasCiFetchError.NotConfigured;
  Result := False;
  mParent := IssueApiUrl(ATarget, AParentKey);
  if (mParent = '') or (ATransport = nil) or not Supports(ATransport, IAtlasCiPost, mPost) then
    Exit;
  if Trim(ATitle) = '' then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  mWatch := TStopwatch.StartNew;
  if not Posted(mPost, ApiBase(ATarget) + '/repos/' + TTextUris.PercentEncode(ATarget.Project) + '/issues',
    NewIssueBody(ATitle, ADescription), ATimeoutMs, mText, AError) then
    Exit;
  mId := ParseIssueId(mText);
  mNumber := 0;
  mValue := TJSONObject.ParseJSONValue(mText);
  try
    if mValue is TJSONObject then
      mNumber := IntOf(TJSONObject(mValue), 'number');
  finally
    mValue.Free;
  end;
  if (mId = 0) or (mNumber = 0) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  AKey := '#' + IntToStr(mNumber);
  Result := Posted(mPost, mParent + '/sub_issues', IdBody('sub_issue_id', mId), Remaining(mWatch, ATimeoutMs),
    mText, AError);
end;

function TAtlasGitHubTracker.AddLink(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AKey: string; AKind: TAtlasTrackerLinkKind; const AOtherKey: string; ATimeoutMs: Integer;
  out AError: TAtlasCiFetchError): Boolean;
var
  mPost: IAtlasCiPost;
  mWatch: TStopwatch;
  mBlocked, mBlocker, mText: string;
  mId: Int64;
begin
  AError := TAtlasCiFetchError.NotConfigured;
  Result := False;
  if (ATransport = nil) or not Supports(ATransport, IAtlasCiPost, mPost) then
    Exit;
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
  if (IssueApiUrl(ATarget, mBlocked) = '') or (IssueApiUrl(ATarget, mBlocker) = '') or
    (NumberOfKey(mBlocked) = NumberOfKey(mBlocker)) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  mWatch := TStopwatch.StartNew;
  mId := IssueId(ATarget, ATransport, mBlocker, ATimeoutMs, AError);
  if mId = 0 then
    Exit;
  Result := Posted(mPost, IssueApiUrl(ATarget, mBlocked) + '/dependencies/blocked_by', IdBody('issue_id', mId),
    Remaining(mWatch, ATimeoutMs), mText, AError);
end;

end.
