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
// Die Zeitgrenze gilt für die ganze Abfrage; reicht sie nach der Liste nicht
// mehr für Pull Requests und Ampeln, bleiben diese unbekannt.

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Internals.GitHubApi;

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

  TAtlasGitHubTracker = class(TInterfacedObject, IAtlasTrackerProvider)
  public const
    ProviderName = 'github';
    Query = 'assignee:@me state:open';
    ApiHost = TAtlasGitHubApi.ApiHost;
    /// <summary>Höchstens so viele Pull Requests bekommen eine Ampel.</summary>
    MaxChecks = 8;
    /// <summary>Höchstens so viele offene Pull Requests werden gelesen.</summary>
    MaxPulls = 50;
  public
    /// <summary>Basis der REST-API ohne „/“ am Ende; '' ohne Server.</summary>
    class function ApiBase(const ATarget: TAtlasTrackerTarget): string; static;
    class function SearchUrl(const ATarget: TAtlasTrackerTarget; AMax: Integer): string; static;
    /// <summary>Suchtext, wie er an /search/issues geht (mit repo: und is:issue).</summary>
    class function SearchText(const ATarget: TAtlasTrackerTarget): string; static;
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
  end;

implementation

uses
  System.Classes,
  System.Diagnostics,
  System.Generics.Collections,
  System.JSON,
  Atlas.Text.Uris,
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
begin
  Result := TAtlasGitHubApi.Base(ATarget);
end;

class function TAtlasGitHubTracker.SearchText(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := ATarget.Query;
  if Result = '' then
    Result := Query;
  Result := Result + ' repo:' + ATarget.Project + ' is:issue';
end;

class function TAtlasGitHubTracker.SearchUrl(const ATarget: TAtlasTrackerTarget; AMax: Integer): string;
var
  Text: string;
  Limit: Integer;
begin
  Result := ApiBase(ATarget);
  if (Result = '') or (ATarget.Project = '') then
    Exit('');
  Text := SearchText(ATarget);
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
  else
    Result := TAtlasCiFetchError.Server;
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

function TAtlasGitHubTracker.ListUrl(const ATarget: TAtlasTrackerTarget; AMax: Integer): string;
begin
  Result := SearchUrl(ATarget, AMax);
end;

function TAtlasGitHubTracker.SentQuery(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := SearchText(ATarget);
end;

function TAtlasGitHubTracker.ParseList(const AText: string; AMax: Integer;
  out AIssues: TArray<TAtlasTrackerIssue>): Boolean;
begin
  Result := ParseIssues(AText, AMax, AIssues);
end;

function TAtlasGitHubTracker.LocaleUrl(const ATarget: TAtlasTrackerTarget): string;
begin
  // Die Suchbegriffe von GitHub sind in jeder Sprache englisch.
  Result := '';
end;

end.
