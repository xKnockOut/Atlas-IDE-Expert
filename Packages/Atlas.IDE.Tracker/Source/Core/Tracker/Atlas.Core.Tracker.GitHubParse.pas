unit Atlas.Core.Tracker.GitHubParse;

// Antworten der GitHub-REST-API lesen (#765, #1264, #1269, #1271, #1279), ohne
// Netz und daher testbar: Issues, Pull Requests und ihre CI-Ampel,
// Einzelheiten der Vorschau, Kommentare, Verweise, Verknüpfungen und
// Benachrichtigungen. Den Ablauf der Abfragen hat der Anbieter
// (Providers.GitHub).

interface

uses
  System.SysUtils,
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
    /// <summary>"open" bzw. "closed" (#1269).</summary>
    State: string;
    /// <summary>merged_at ist gesetzt (#1269).</summary>
    Merged: Boolean;
    /// <summary>updated_at (UTC); 0 = unbekannt.</summary>
    Updated: TDateTime;
  end;

  /// <summary>Zusammenfassungen der Verknüpfungen eines Issues (#1279); -1 = unbekannt (ältere Server).</summary>
  TAtlasGitHubLinkSummary = record
    SubIssues: Integer;
    BlockedBy: Integer;
    Blocking: Integer;
  end;

  /// <summary>Eine Benachrichtigung von /notifications (#1271).</summary>
  TAtlasGitHubThread = record
    /// <summary>"owner/repo".</summary>
    Repository: string;
    Number: Integer;
    Title: string;
    /// <summary>Grund wie bei GitHub: "assign", "author", "comment", "mention", "subscribed" …</summary>
    Reason: string;
    /// <summary>UTC.</summary>
    Updated: TDateTime;
  end;

  TAtlasGitHubParse = class
  public
    /// <summary>Antwort von /search/issues; False bei ungültigem JSON.</summary>
    class function ParseIssues(const AJson: string; AMax: Integer;
      out AIssues: TArray<TAtlasTrackerIssue>): Boolean; static;
    /// <summary>Antwort von /pulls; False bei ungültigem JSON.</summary>
    class function ParsePulls(const AJson: string; out APulls: TArray<TAtlasGitHubPull>): Boolean; static;
    /// <summary>Der Pull Request gehört zu Issue ANumber (Branch, „closes #N“ in Titel oder Beschreibung).
    /// </summary>
    class function PullMentions(const APull: TAtlasGitHubPull; ANumber: Integer): Boolean; static;
    /// <summary>Reiter „Entwicklung“ (#1269): PullMentions oder „#N“ als eigenes Stück im Titel („Vorschau (#753)“).
    /// </summary>
    class function PullRefersTo(const APull: TAtlasGitHubPull; ANumber: Integer): Boolean; static;
    /// <summary>Zustand für den Reiter „Entwicklung“.</summary>
    class function PullState(const APull: TAtlasGitHubPull): TAtlasTrackerPullState; static;
    /// <summary>Antwort von /check-runs zusammengefasst: rot, sobald einer fehlschlug; gelb, solange einer läuft;
    /// sonst grün; Unknown ohne Check Runs. False bei ungültigem JSON.</summary>
    class function ParseCheckRuns(const AJson: string; out AChecks: TAtlasTrackerChecks): Boolean; static;
    /// <summary>Antwort von /status (kombinierter Status); Unknown ohne Einträge. False bei ungültigem JSON.
    /// </summary>
    class function ParseStatus(const AJson: string; out AChecks: TAtlasTrackerChecks): Boolean; static;
    /// <summary>Antwort von /issues/&lt;n&gt;; False bei ungültigem JSON bzw. ohne Nummer.</summary>
    class function ParseDetails(const AJson: string; out ADetails: TAtlasTrackerDetails;
      out ACommentCount: Integer): Boolean; static;
    /// <summary>Antwort von /issues/&lt;n&gt;/comments (älteste zuerst); False bei ungültigem JSON.</summary>
    class function ParseComments(const AJson: string; out AComments: TArray<TAtlasTrackerComment>): Boolean; static;
    /// <summary>Antwort von /issues/&lt;n&gt;/timeline: Verweise ("cross-referenced"); AProject entscheidet, was im
    /// Fenster öffnet. False bei ungültigem JSON.</summary>
    class function ParseTimeline(const AJson, AProject: string; out ALinks: TArray<TAtlasTrackerLink>): Boolean;
      static;
    /// <summary>Dateien in Beschreibung und Kommentaren als Anhänge (im Browser).</summary>
    class function FileAttachments(const ADetails: TAtlasTrackerDetails): TArray<TAtlasTrackerAttachment>; static;
    /// <summary>Labels und Zuständige aus /issues/&lt;n&gt;; False bei ungültigem JSON.</summary>
    class function ParseAssignment(const AJson: string; out ALabels, AAssignees: TArray<string>): Boolean; static;
    /// <summary>Werte "name" (Labels) bzw. "login" (Zuständige) einer Liste; False bei ungültigem JSON.</summary>
    class function ParseNames(const AJson, AField: string; out AValues: TArray<string>): Boolean; static;
    /// <summary>Mögliche Zuständige (…/assignees) als Benutzer ohne Anzeigenamen (#1278); False bei ungültigem
    /// JSON.</summary>
    class function ParseUsers(const AJson: string; out AUsers: TArray<TAtlasTrackerUser>): Boolean; static;
    /// <summary>"body" aus der Antwort von /issues/&lt;n&gt;, ungekürzt ('' bei null); False bei ungültigem JSON
    /// (#1273).
    /// </summary>
    class function ParseBody(const AJson: string; out AText: string): Boolean; static;
    /// <summary>sub_issues_summary und issue_dependencies_summary aus /issues/&lt;n&gt; (#1279).</summary>
    class function ParseLinkSummary(const AJson: string): TAtlasGitHubLinkSummary; static;
    /// <summary>Liste von Issues (…/sub_issues, …/dependencies/…) als Verknüpfungen der Art AKind; AProject
    /// entscheidet, was im Fenster öffnet. False bei ungültigem JSON.</summary>
    class function ParseRelated(const AJson, AProject: string; AKind: TAtlasTrackerLinkKind;
      out ALinks: TArray<TAtlasTrackerLink>): Boolean; static;
    /// <summary>ANew in ALinks übernehmen: eine Erwähnung desselben Issues wird durch die genauere Art ersetzt,
    /// dieselbe Art nicht doppelt; höchstens TAtlasTrackerDetails.cMaxLinks.</summary>
    class procedure MergeLinks(var ALinks: TArray<TAtlasTrackerLink>; const ANew: TArray<TAtlasTrackerLink>); static;
    /// <summary>Interne ID ("id") aus /issues/&lt;n&gt; bzw. der Antwort beim Anlegen; 0 ohne.</summary>
    class function ParseIssueId(const AJson: string): Int64; static;
    /// <summary>Antwort von /notifications: nur Issues, nach ASince. False bei ungültigem JSON.</summary>
    class function ParseNotifications(const AJson: string; ASince: TDateTime;
      out AThreads: TArray<TAtlasGitHubThread>): Boolean; static;
    /// <summary>Der Grund einer Benachrichtigung gehört zum Umfang: Assigned nur "assign", AssignedOrCreated dazu
    /// "author", Watched alle.</summary>
    class function InScope(const AReason: string; AScope: TAtlasTrackerNotifyScope): Boolean; static;
    class function ChangeOf(const AThread: TAtlasGitHubThread; AKind: TAtlasTrackerChangeKind; const AAuthor: string;
      ATime: TDateTime): TAtlasTrackerChange; static;
    /// <summary>Neue Kommentare (angelegt nach ASince) aus …/comments als Änderungen an AThread. False bei
    /// ungültigem JSON.</summary>
    class function ParseCommentChanges(const AJson: string; const AThread: TAtlasGitHubThread; ASince: TDateTime;
      out AChanges: TArray<TAtlasTrackerChange>): Boolean; static;
    /// <summary>Ereignisse nach ASince aus …/events: assigned (AMe: an mich?), closed und reopened. False bei
    /// ungültigem JSON.</summary>
    class function ParseEventChanges(const AJson: string; const AThread: TAtlasGitHubThread; const AMe: string;
      ASince: TDateTime; out AChanges: TArray<TAtlasTrackerChange>): Boolean; static;
  end;

implementation

uses
  System.Classes,
  System.DateUtils,
  System.Generics.Collections,
  System.JSON,
  System.StrUtils,
  Atlas.Core.Tracker.Links,
  Atlas.Core.Tracker.Markdown,
  Atlas.Core.Tracker.Naming,
  Atlas.Core.Tracker.Internals.GitHubApi,
  Atlas.Core.Tracker.Internals.GitHubJson;

/// <summary>Name eines Labels (Objekt mit "name" oder Text), gekürzt; '' ohne.</summary>
function LabelNameOf(AValue: TJSONValue): string;
begin
  Result := '';
  if AValue is TJSONObject then
  begin
    Result := Trim(TAtlasGitHubJson.TextOf(TJSONObject(AValue), 'name'));
  end
  else if AValue is TJSONString then
  begin
    Result := Trim(TJSONString(AValue).Value);
  end;
  if Result <> '' then
  begin
    Result := TAtlasGitHubJson.Shorten(Result, 40);
  end;
end;

/// <summary>Labels eines Issues, höchstens AMax.</summary>
function IssueLabelsOf(ALabels: TJSONValue; AMax: Integer): TArray<string>;
var
  mValue: TJSONValue;
  mName: string;
begin
  Result := nil;
  if not (ALabels is TJSONArray) then
  begin
    Exit;
  end;
  for mValue in TJSONArray(ALabels) do
  begin
    if Length(Result) >= AMax then
    begin
      Break;
    end;
    mName := LabelNameOf(mValue);
    if mName <> '' then
    begin
      Result := Result + [mName];
    end;
  end;
end;

/// <summary>Ein Eintrag von /search/issues; False für Pull Requests und Einträge ohne Nummer.</summary>
function SearchIssueOf(AItem: TJSONValue; out AIssue: TAtlasTrackerIssue): Boolean;
var
  mItem: TJSONObject;
begin
  AIssue := TAtlasTrackerIssue.Empty;
  // Die Suche liefert auch Pull Requests; die gehören nicht in die Liste.
  Result := (AItem is TJSONObject) and (TJSONObject(AItem).Values['pull_request'] = nil);
  if not Result then
  begin
    Exit;
  end;
  mItem := TJSONObject(AItem);
  AIssue.Number := TAtlasGitHubJson.IntOf(mItem, 'number');
  Result := AIssue.Number > 0;
  if not Result then
  begin
    Exit;
  end;
  AIssue.Key := '#' + IntToStr(AIssue.Number);
  AIssue.Title := TAtlasGitHubJson.Shorten(TAtlasGitHubJson.TextOf(mItem, 'title'), TAtlasTrackerIssue.cMaxTitle);
  AIssue.State := TAtlasGitHubJson.TextOf(mItem, 'state');
  AIssue.Assignee := TAtlasGitHubJson.AssigneesOf(mItem);
  AIssue.Labels := IssueLabelsOf(mItem.Values['labels'], TAtlasTrackerIssue.cMaxLabels);
end;

class function TAtlasGitHubParse.ParseIssues(const AJson: string; AMax: Integer;
  out AIssues: TArray<TAtlasTrackerIssue>): Boolean;
var
  mValue, mItems, mItem: TJSONValue;
  mIssue: TAtlasTrackerIssue;
begin
  AIssues := nil;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    mItems := nil;
    if mValue is TJSONObject then
    begin
      mItems := TJSONObject(mValue).Values['items'];
    end;
    Result := mItems is TJSONArray;
    if not Result then
    begin
      Exit;
    end;
    for mItem in TJSONArray(mItems) do
    begin
      if Length(AIssues) >= AMax then
      begin
        Break;
      end;
      if SearchIssueOf(mItem, mIssue) then
      begin
        AIssues := AIssues + [mIssue];
      end;
    end;
  finally
    mValue.Free;
  end;
end;

/// <summary>updated_at (ISO 8601) als UTC; 0 ohne.</summary>
function UpdatedOf(AObject: TJSONObject): TDateTime;
var
  mText: string;
begin
  Result := 0;
  mText := TAtlasGitHubJson.TextOf(AObject, 'updated_at');
  if (mText = '') or not TryISO8601ToDate(mText, Result, True) then
  begin
    Result := 0;
  end;
end;

class function TAtlasGitHubParse.ParsePulls(const AJson: string; out APulls: TArray<TAtlasGitHubPull>): Boolean;
var
  mValue, mItem, mHead: TJSONValue;
  mPull: TAtlasGitHubPull;
begin
  APulls := nil;
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
      mPull := Default(TAtlasGitHubPull);
      mPull.Number := TAtlasGitHubJson.IntOf(TJSONObject(mItem), 'number');
      if mPull.Number <= 0 then
      begin
        Continue;
      end;
      mPull.Draft := TAtlasGitHubJson.FlagOf(TJSONObject(mItem), 'draft');
      mPull.State := LowerCase(TAtlasGitHubJson.TextOf(TJSONObject(mItem), 'state'));
      mPull.Merged := TAtlasGitHubJson.TextOf(TJSONObject(mItem), 'merged_at') <> '';
      mPull.Updated := UpdatedOf(TJSONObject(mItem));
      mPull.Title := TAtlasGitHubJson.TextOf(TJSONObject(mItem), 'title');
      // Nur der Anfang: „closes #N“ steht fast immer oben, und lange Beschreibungen kosten nur Speicher.
      mPull.Body := Copy(TAtlasGitHubJson.TextOf(TJSONObject(mItem), 'body'), 1, 4000);
      mHead := TJSONObject(mItem).Values['head'];
      if mHead is TJSONObject then
      begin
        mPull.Branch := TAtlasGitHubJson.TextOf(TJSONObject(mHead), 'ref');
        mPull.Sha := TAtlasGitHubJson.TextOf(TJSONObject(mHead), 'sha');
      end;
      APulls := APulls + [mPull];
    end;
  finally
    mValue.Free;
  end;
end;

/// <summary>Das Wort vor Stelle AIndex (Leerzeichen und ":" übersprungen); '' ohne.</summary>
function WordBefore(const ALower: string; AIndex: Integer): string;
var
  mStart, mStop: Integer;
begin
  mStart := AIndex - 1;
  while (mStart >= 1) and CharInSet(ALower[mStart], [' ', ':', #9]) do
  begin
    Dec(mStart);
  end;
  mStop := mStart;
  while (mStart >= 1) and CharInSet(ALower[mStart], ['a'..'z']) do
  begin
    Dec(mStart);
  end;
  Result := Copy(ALower, mStart + 1, mStop - mStart);
end;

/// <summary>„close(s|d)“, „fix(es|ed)“ oder „resolve(s|d)“.</summary>
function IsClosingWord(const AWord: string): Boolean;
const
  cWords: array[0..8] of string = ('close', 'closes', 'closed', 'fix', 'fixes', 'fixed', 'resolve', 'resolves',
    'resolved');
begin
  Result := (AWord <> '') and (IndexStr(AWord, cWords) >= 0);
end;

/// <summary>„close(s|d)“, „fix(es|ed)“ oder „resolve(s|d)“, optional „:“, dann „#N“ ohne weitere Ziffer.</summary>
function TextClosesIssue(const AText: string; ANumber: Integer): Boolean;
var
  mLower, mMark: string;
  mIndex, mStop: Integer;
begin
  Result := False;
  mLower := LowerCase(AText);
  mMark := '#' + IntToStr(ANumber);
  mIndex := Pos(mMark, mLower);
  while (mIndex > 0) and not Result do
  begin
    mStop := mIndex + Length(mMark);
    Result := ((mStop > Length(mLower)) or not CharInSet(mLower[mStop], ['0'..'9']))
      and IsClosingWord(WordBefore(mLower, mIndex));
    mIndex := Pos(mMark, mLower, mIndex + 1);
  end;
end;

class function TAtlasGitHubParse.PullMentions(const APull: TAtlasGitHubPull; ANumber: Integer): Boolean;
begin
  Result := False;
  if ANumber <= 0 then
  begin
    Exit;
  end;
  Result := (TAtlasTrackerNaming.KeyOfBranch(TAtlasGitHubApi.cProviderName, '',
    APull.Branch) = '#' + IntToStr(ANumber)) or
    TextClosesIssue(APull.Title, ANumber) or TextClosesIssue(APull.Body, ANumber);
end;

/// <summary>„#N“ ohne Ziffer davor oder danach und ohne Buchstaben davor.</summary>
function NamesNumber(const AText: string; ANumber: Integer): Boolean;
var
  mMark: string;
  mIndex, mStop: Integer;
begin
  Result := False;
  mMark := '#' + IntToStr(ANumber);
  mIndex := Pos(mMark, AText);
  while mIndex > 0 do
  begin
    mStop := mIndex + Length(mMark);
    if ((mStop > Length(AText)) or not CharInSet(AText[mStop], ['0'..'9'])) and
      ((mIndex = 1) or not CharInSet(AText[mIndex - 1], ['0'..'9', 'A'..'Z', 'a'..'z'])) then
    begin
      Exit(True);
    end;
    mIndex := Pos(mMark, AText, mIndex + 1);
  end;
end;

class function TAtlasGitHubParse.PullRefersTo(const APull: TAtlasGitHubPull; ANumber: Integer): Boolean;
begin
  Result := (ANumber > 0) and (PullMentions(APull, ANumber) or NamesNumber(APull.Title, ANumber));
end;

class function TAtlasGitHubParse.PullState(const APull: TAtlasGitHubPull): TAtlasTrackerPullState;
begin
  if APull.Merged then
  begin
    Result := TAtlasTrackerPullState.Merged;
  end
  else if APull.State = 'closed' then
  begin
    Result := TAtlasTrackerPullState.Closed;
  end
  else if APull.Draft then
  begin
    Result := TAtlasTrackerPullState.Draft;
  end
  else
  begin
    Result := TAtlasTrackerPullState.Open;
  end;
end;

class function TAtlasGitHubParse.ParseCheckRuns(const AJson: string; out AChecks: TAtlasTrackerChecks): Boolean;
var
  mValue, mRuns, mRun: TJSONValue;
  mStatus, mConclusion: string;
  mAny, mRunning, mFailed: Boolean;
begin
  AChecks := TAtlasTrackerChecks.Unknown;
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mRuns := TJSONObject(mValue).Values['check_runs'];
    if not (mRuns is TJSONArray) then
    begin
      Exit;
    end;
    Result := True;
    mAny := False;
    mRunning := False;
    mFailed := False;
    for mRun in TJSONArray(mRuns) do
    begin
      if not (mRun is TJSONObject) then
      begin
        Continue;
      end;
      mAny := True;
      mStatus := LowerCase(TAtlasGitHubJson.TextOf(TJSONObject(mRun), 'status'));
      mConclusion := LowerCase(TAtlasGitHubJson.TextOf(TJSONObject(mRun), 'conclusion'));
      if mStatus <> 'completed' then
      begin
        mRunning := True;
      end
      else if (mConclusion = 'failure') or (mConclusion = 'timed_out') or (mConclusion = 'cancelled') or
        (mConclusion = 'action_required') or (mConclusion = 'startup_failure') then
      begin
        mFailed := True;
      end;
    end;
    if mFailed then
    begin
      AChecks := TAtlasTrackerChecks.Failure;
    end
    else if mRunning then
    begin
      AChecks := TAtlasTrackerChecks.Pending;
    end
    else if mAny then
    begin
      AChecks := TAtlasTrackerChecks.Success;
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasGitHubParse.ParseStatus(const AJson: string; out AChecks: TAtlasTrackerChecks): Boolean;
var
  mValue, mStatuses: TJSONValue;
  mState: string;
begin
  AChecks := TAtlasTrackerChecks.Unknown;
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    Result := True;
    // Ohne einzelne Status meldet GitHub "pending"; das ist keine Ampel.
    mStatuses := TJSONObject(mValue).Values['statuses'];
    if not (mStatuses is TJSONArray) or (TJSONArray(mStatuses).Count = 0) then
    begin
      Exit;
    end;
    mState := LowerCase(TAtlasGitHubJson.TextOf(TJSONObject(mValue), 'state'));
    if mState = 'success' then
    begin
      AChecks := TAtlasTrackerChecks.Success;
    end
    else if (mState = 'failure') or (mState = 'error') then
    begin
      AChecks := TAtlasTrackerChecks.Failure;
    end
    else if mState = 'pending' then
    begin
      AChecks := TAtlasTrackerChecks.Pending;
    end;
  finally
    mValue.Free;
  end;
end;

/// <summary>"state", bei "closed" mit Grund ("completed", "not_planned") wie in der Oberfläche.</summary>
function DetailsStateOf(ARoot: TJSONObject): string;
var
  mReason: string;
begin
  Result := TAtlasGitHubJson.TextOf(ARoot, 'state');
  mReason := TAtlasGitHubJson.TextOf(ARoot, 'state_reason');
  if (Result = 'closed') and (mReason <> '') and (mReason <> 'completed') then
  begin
    Result := Result + ' (' + StringReplace(mReason, '_', ' ', [rfReplaceAll]) + ')';
  end;
end;

/// <summary>Feld AField des Unterobjekts AObject, gekürzt auf AMax; '' ohne.</summary>
function NestedText(ARoot: TJSONObject; const AObject, AField: string; AMax: Integer): string;
begin
  Result := '';
  if ARoot.Values[AObject] is TJSONObject then
  begin
    Result := TAtlasGitHubJson.Shorten(TAtlasGitHubJson.TextOf(TJSONObject(ARoot.Values[AObject]), AField), AMax);
  end;
end;

/// <summary>Felder eines Issues aus /issues/&lt;n&gt; nach ADetails (Nummer schon gesetzt).</summary>
procedure ReadDetails(ARoot: TJSONObject; var ADetails: TAtlasTrackerDetails);
begin
  ADetails.Key := '#' + IntToStr(ADetails.Number);
  ADetails.Title := TAtlasGitHubJson.Shorten(TAtlasGitHubJson.TextOf(ARoot, 'title'), 500);
  ADetails.Description := TAtlasGitHubJson.Limited(TAtlasGitHubJson.TextOf(ARoot, 'body'));
  ADetails.State := DetailsStateOf(ARoot);
  ADetails.Created := TAtlasGitHubJson.TimeOf(ARoot, 'created_at');
  ADetails.Updated := TAtlasGitHubJson.TimeOf(ARoot, 'updated_at');
  ADetails.Labels := IssueLabelsOf(ARoot.Values['labels'], MaxInt);
  ADetails.Assignee := TAtlasGitHubJson.AssigneesOf(ARoot);
  ADetails.Sprint := NestedText(ARoot, 'milestone', 'title', 60);
  // Issue-Typen (Bug, Feature …) der Organisation.
  ADetails.Kind := NestedText(ARoot, 'type', 'name', 40);
end;

class function TAtlasGitHubParse.ParseDetails(const AJson: string; out ADetails: TAtlasTrackerDetails;
  out ACommentCount: Integer): Boolean;
var
  mValue: TJSONValue;
begin
  ADetails := TAtlasTrackerDetails.Empty;
  ACommentCount := 0;
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if mValue is TJSONObject then
    begin
      ADetails.Number := TAtlasGitHubJson.IntOf(TJSONObject(mValue), 'number');
      Result := ADetails.Number > 0;
    end;
    if Result then
    begin
      ReadDetails(TJSONObject(mValue), ADetails);
      ACommentCount := TAtlasGitHubJson.IntOf(TJSONObject(mValue), 'comments');
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasGitHubParse.ParseComments(const AJson: string;
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
      mComment := Default(TAtlasTrackerComment);
      mComment.Author := TAtlasGitHubJson.LoginOf(TJSONObject(mItem).Values['user']);
      mComment.Created := TAtlasGitHubJson.TimeOf(TJSONObject(mItem), 'created_at');
      mComment.Text := TAtlasGitHubJson.Limited(TAtlasGitHubJson.TextOf(TJSONObject(mItem), 'body'));
      AComments := AComments + [mComment];
    end;
  finally
    mValue.Free;
  end;
end;

/// <summary>Verknüpfung auf ein Issue aus einer Antwort der API: Schlüssel (mit ARepository, wenn es nicht
/// AProject ist), Titel, Zustand (#1279) und Seite; False ohne Nummer.</summary>
function IssueLinkOf(AIssue: TJSONObject; const ARepository, AProject: string; out ALink: TAtlasTrackerLink): Boolean;
var
  mNumber: Integer;
  mPage: string;
begin
  ALink := Default(TAtlasTrackerLink);
  mNumber := TAtlasGitHubJson.IntOf(AIssue, 'number');
  Result := mNumber > 0;
  if not Result then
  begin
    Exit;
  end;
  ALink.Local := (ARepository = '') or SameText(ARepository, AProject);
  ALink.Key := '#' + IntToStr(mNumber);
  if not ALink.Local then
  begin
    ALink.Key := ARepository + ALink.Key;
  end;
  ALink.Title := TAtlasGitHubJson.Shorten(TAtlasGitHubJson.TextOf(AIssue, 'title'), 200);
  ALink.State := TAtlasGitHubJson.TextOf(AIssue, 'state');
  ALink.StateKnown := ALink.State <> '';
  ALink.Resolved := SameText(ALink.State, 'closed');
  // Nur Web-Seiten über https; was nicht im Fenster öffnet, geht in den Browser.
  mPage := TAtlasGitHubJson.TextOf(AIssue, 'html_url');
  if StartsText('https://', mPage) then
  begin
    ALink.Page := mPage;
  end;
end;

/// <summary>Das Issue eines Eintrags "cross-referenced" der Zeitleiste; nil sonst.</summary>
function CrossReferencedIssue(AItem: TJSONValue): TJSONObject;
var
  mSource: TJSONValue;
begin
  Result := nil;
  if not (AItem is TJSONObject) or (TAtlasGitHubJson.TextOf(TJSONObject(AItem), 'event') <> 'cross-referenced') then
  begin
    Exit;
  end;
  mSource := TJSONObject(AItem).Values['source'];
  if (mSource is TJSONObject) and (TJSONObject(mSource).Values['issue'] is TJSONObject) then
  begin
    Result := TJSONObject(TJSONObject(mSource).Values['issue']);
  end;
end;

/// <summary>Verweis aus der Zeitleiste: Pull Request oder Erwähnung; False ohne Nummer.</summary>
function TimelineLinkOf(AIssue: TJSONObject; const AProject: string; out ALink: TAtlasTrackerLink): Boolean;
begin
  Result := IssueLinkOf(AIssue, NestedText(AIssue, 'repository', 'full_name', MaxInt), AProject, ALink);
  if AIssue.Values['pull_request'] <> nil then
  begin
    ALink.Relation := 'pull request';
    ALink.Kind := TAtlasTrackerLinkKind.PullRequest;
  end
  else
  begin
    ALink.Relation := 'cross-referenced';
    ALink.Kind := TAtlasTrackerLinkKind.Mentioned;
  end;
end;

/// <summary>ALinks enthält schon einen Eintrag mit Schlüssel AKey.</summary>
function HasLinkKey(const ALinks: TArray<TAtlasTrackerLink>; const AKey: string): Boolean;
var
  mLink: TAtlasTrackerLink;
begin
  Result := False;
  for mLink in ALinks do
  begin
    if SameText(mLink.Key, AKey) then
    begin
      Exit(True);
    end;
  end;
end;

class function TAtlasGitHubParse.ParseTimeline(const AJson, AProject: string;
  out ALinks: TArray<TAtlasTrackerLink>): Boolean;
var
  mValue, mItem: TJSONValue;
  mIssue: TJSONObject;
  mLink: TAtlasTrackerLink;
begin
  ALinks := nil;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := mValue is TJSONArray;
    if not Result then
    begin
      Exit;
    end;
    for mItem in TJSONArray(mValue) do
    begin
      mIssue := CrossReferencedIssue(mItem);
      if (mIssue <> nil) and TimelineLinkOf(mIssue, AProject, mLink) and not HasLinkKey(ALinks, mLink.Key)
        and (Length(ALinks) < TAtlasTrackerDetails.cMaxLinks) then
      begin
        ALinks := ALinks + [mLink];
      end;
    end;
  finally
    mValue.Free;
  end;
end;

/// <summary>Anhang aus einem Markdown-Link auf …/user-attachments/files/ (im Browser); False für andere Links.
/// </summary>
function FileAttachmentOf(const ALink: TAtlasMarkdownLink; out AAttachment: TAtlasTrackerAttachment): Boolean;
begin
  AAttachment := Default(TAtlasTrackerAttachment);
  Result := StartsText('https://', ALink.Url) and (Pos('/user-attachments/files/', ALink.Url) > 0);
  if not Result then
  begin
    Exit;
  end;
  AAttachment.Name := TAtlasGitHubJson.Shorten(ALink.Text, 200);
  if AAttachment.Name = '' then
  begin
    AAttachment.Name := Copy(ALink.Url, LastDelimiter('/', ALink.Url) + 1, 200);
  end;
  AAttachment.Size := -1;
  AAttachment.Url := ALink.Url;
  AAttachment.External := True;
end;

/// <summary>AAttachments enthält schon einen Anhang mit Adresse AUrl.</summary>
function HasAttachmentUrl(const AAttachments: TArray<TAtlasTrackerAttachment>; const AUrl: string): Boolean;
var
  mAttachment: TAtlasTrackerAttachment;
begin
  Result := False;
  for mAttachment in AAttachments do
  begin
    if mAttachment.Url = AUrl then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Dateien aus AText an AAttachments anhängen, ohne doppelte, höchstens MaxAttachments.</summary>
procedure AddFileAttachments(const AText: string; var AAttachments: TArray<TAtlasTrackerAttachment>);
var
  mLink: TAtlasMarkdownLink;
  mAttachment: TAtlasTrackerAttachment;
begin
  for mLink in TAtlasTrackerMarkdown.Links(AText) do
  begin
    if (Length(AAttachments) < TAtlasTrackerDetails.cMaxAttachments) and FileAttachmentOf(mLink, mAttachment)
      and not HasAttachmentUrl(AAttachments, mAttachment.Url) then
    begin
      AAttachments := AAttachments + [mAttachment];
    end;
  end;
end;

class function TAtlasGitHubParse.FileAttachments(
  const ADetails: TAtlasTrackerDetails): TArray<TAtlasTrackerAttachment>;
var
  mComment: TAtlasTrackerComment;
begin
  Result := nil;
  AddFileAttachments(ADetails.Description, Result);
  for mComment in ADetails.Comments do
  begin
    AddFileAttachments(mComment.Text, Result);
  end;
end;

function NamesOf(AValue: TJSONValue; const AField: string): TArray<string>;
var
  mItem: TJSONValue;
  mText: string;
begin
  Result := nil;
  if AValue is TJSONArray then
  begin
    for mItem in TJSONArray(AValue) do
    begin
      if mItem is TJSONObject then
      begin
        mText := Trim(TAtlasGitHubJson.TextOf(TJSONObject(mItem), AField));
        if mText <> '' then
        begin
          Result := Result + [mText];
        end;
      end;
    end;
  end;
end;

class function TAtlasGitHubParse.ParseAssignment(const AJson: string;
  out ALabels, AAssignees: TArray<string>): Boolean;
var
  mValue: TJSONValue;
begin
  ALabels := nil;
  AAssignees := nil;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := mValue is TJSONObject;
    if not Result then
    begin
      Exit;
    end;
    ALabels := NamesOf(TJSONObject(mValue).Values['labels'], 'name');
    AAssignees := NamesOf(TJSONObject(mValue).Values['assignees'], 'login');
  finally
    mValue.Free;
  end;
end;

class function TAtlasGitHubParse.ParseNames(const AJson, AField: string; out AValues: TArray<string>): Boolean;
var
  mValue: TJSONValue;
begin
  AValues := nil;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := mValue is TJSONArray;
    if Result then
    begin
      AValues := NamesOf(mValue, AField);
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasGitHubParse.ParseUsers(const AJson: string;
  out AUsers: TArray<TAtlasTrackerUser>): Boolean;
var
  mLogins: TArray<string>;
  mLogin: string;
begin
  AUsers := nil;
  Result := ParseNames(AJson, 'login', mLogins);
  for mLogin in mLogins do
  begin
    AUsers := AUsers + [TAtlasTrackerUser.Create(mLogin, '')];
  end;
end;

class function TAtlasGitHubParse.ParseBody(const AJson: string; out AText: string): Boolean;
var
  mValue: TJSONValue;
begin
  AText := '';
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := (mValue is TJSONObject) and (TAtlasGitHubJson.IntOf(TJSONObject(mValue), 'number') > 0);
    if Result then
    begin
      AText := TAtlasGitHubJson.TextOf(TJSONObject(mValue), 'body');
    end;
  finally
    mValue.Free;
  end;
end;


function SummaryCount(ARoot: TJSONObject; const AObject, AName: string): Integer;
var
  mValue: TJSONValue;
  mNumber: Int64;
begin
  Result := -1;
  mValue := ARoot.Values[AObject];
  if not (mValue is TJSONObject) then
  begin
    Exit;
  end;
  mValue := TJSONObject(mValue).Values[AName];
  if (mValue is TJSONNumber) and TryStrToInt64(TJSONNumber(mValue).Value, mNumber) and (mNumber >= 0) and
    (mNumber <= MaxInt) then
  begin
    Result := Integer(mNumber);
  end;
end;

class function TAtlasGitHubParse.ParseLinkSummary(const AJson: string): TAtlasGitHubLinkSummary;
var
  mValue: TJSONValue;
begin
  Result.SubIssues := -1;
  Result.BlockedBy := -1;
  Result.Blocking := -1;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
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
  mUrl := TAtlasGitHubJson.TextOf(AIssue, 'repository_url');
  mAt := Pos('/repos/', mUrl);
  if mAt > 0 then
  begin
    Result := Copy(mUrl, mAt + Length('/repos/'), MaxInt);
  end;
end;

class function TAtlasGitHubParse.ParseRelated(const AJson, AProject: string; AKind: TAtlasTrackerLinkKind;
  out ALinks: TArray<TAtlasTrackerLink>): Boolean;
const
  cRelations: array[TAtlasTrackerLinkKind] of string = ('', 'blocked by', 'blocking', 'sub-issue', 'parent', '', '',
    '', 'cross-referenced', 'pull request');
var
  mValue, mItem: TJSONValue;
  mLink: TAtlasTrackerLink;
begin
  ALinks := nil;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := mValue is TJSONArray;
    if not Result then
    begin
      Exit;
    end;
    for mItem in TJSONArray(mValue) do
    begin
      if (mItem is TJSONObject) and (Length(ALinks) < TAtlasTrackerDetails.cMaxLinks)
        and IssueLinkOf(TJSONObject(mItem), RepositoryOf(TJSONObject(mItem)), AProject, mLink) then
      begin
        mLink.Kind := AKind;
        mLink.Relation := cRelations[AKind];
        ALinks := ALinks + [mLink];
      end;
    end;
  finally
    mValue.Free;
  end;
end;

/// <summary>ALink in ALinks übernehmen, wenn derselbe Schlüssel dort steht: True, wenn er dieselbe Art hat
/// oder eine Erwähnung war (die der genaueren Art weicht).</summary>
function MergedIntoKnown(var ALinks: TArray<TAtlasTrackerLink>; const ALink: TAtlasTrackerLink): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to High(ALinks) do
  begin
    if not SameText(ALinks[mIndex].Key, ALink.Key) then
    begin
      Continue;
    end;
    Result := ALinks[mIndex].Kind = ALink.Kind;
    if not Result and (ALinks[mIndex].Kind in [TAtlasTrackerLinkKind.Mentioned, TAtlasTrackerLinkKind.Other]) then
    begin
      ALinks[mIndex] := ALink;
      Result := True;
    end;
    if Result then
    begin
      Exit;
    end;
  end;
end;

class procedure TAtlasGitHubParse.MergeLinks(var ALinks: TArray<TAtlasTrackerLink>;
  const ANew: TArray<TAtlasTrackerLink>);
var
  mLink: TAtlasTrackerLink;
begin
  for mLink in ANew do
  begin
    if not MergedIntoKnown(ALinks, mLink) and (Length(ALinks) < TAtlasTrackerDetails.cMaxLinks) then
    begin
      ALinks := ALinks + [mLink];
    end;
  end;
end;

class function TAtlasGitHubParse.ParseIssueId(const AJson: string): Int64;
var
  mValue, mId: TJSONValue;
begin
  Result := 0;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mId := TJSONObject(mValue).Values['id'];
    if not (mId is TJSONNumber) or not TryStrToInt64(TJSONNumber(mId).Value, Result) or (Result < 0) then
    begin
      Result := 0;
    end;
  finally
    mValue.Free;
  end;
end;

/// <summary>"owner/repo" und Nummer aus ".../repos/owner/repo/issues/12"; False bei anderer Adresse.</summary>
function IssueOfApiUrl(const AUrl: string; out ARepository: string; out ANumber: Integer): Boolean;
var
  mParts: TArray<string>;
  mIndex: Integer;
begin
  Result := False;
  ARepository := '';
  ANumber := 0;
  mParts := AUrl.Split(['/']);
  for mIndex := 0 to High(mParts) - 4 do
  begin
    if (mParts[mIndex] = 'repos') and (mParts[mIndex + 3] = 'issues') and
      TryStrToInt(mParts[mIndex + 4], ANumber) and (ANumber > 0) then
    begin
      ARepository := mParts[mIndex + 1] + '/' + mParts[mIndex + 2];
      Exit(True);
    end;
  end;
end;

class function TAtlasGitHubParse.ParseNotifications(const AJson: string; ASince: TDateTime;
  out AThreads: TArray<TAtlasGitHubThread>): Boolean;
var
  mValue, mItem: TJSONValue;
  mObject, mSubject: TJSONObject;
  mThread: TAtlasGitHubThread;
begin
  AThreads := nil;
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
      mObject := TJSONObject(mItem);
      if not (mObject.Values['subject'] is TJSONObject) then
      begin
        Continue;
      end;
      mSubject := TJSONObject(mObject.Values['subject']);
      // Nur Issues; Pull Requests, Releases und Diskussionen nicht.
      if not SameText(TAtlasGitHubJson.TextOf(mSubject, 'type'), 'Issue') then
      begin
        Continue;
      end;
      mThread := Default(TAtlasGitHubThread);
      if not IssueOfApiUrl(TAtlasGitHubJson.TextOf(mSubject, 'url'), mThread.Repository, mThread.Number) then
      begin
        Continue;
      end;
      mThread.Title := TAtlasGitHubJson.Shorten(TAtlasGitHubJson.TextOf(mSubject, 'title'),
        TAtlasTrackerIssue.cMaxTitle);
      mThread.Reason := LowerCase(TAtlasGitHubJson.TextOf(mObject, 'reason'));
      mThread.Updated := TAtlasGitHubJson.TimeOf(mObject, 'updated_at');
      if mThread.Updated > ASince then
      begin
        AThreads := AThreads + [mThread];
      end;
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasGitHubParse.InScope(const AReason: string; AScope: TAtlasTrackerNotifyScope): Boolean;
begin
  case AScope of
    TAtlasTrackerNotifyScope.Assigned:
      Result := SameText(AReason, 'assign');
    TAtlasTrackerNotifyScope.AssignedOrCreated:
      Result := SameText(AReason, 'assign') or SameText(AReason, 'author');
  else
    Result := True;
  end;
end;

class function TAtlasGitHubParse.ChangeOf(const AThread: TAtlasGitHubThread; AKind: TAtlasTrackerChangeKind;
  const AAuthor: string;
  ATime: TDateTime): TAtlasTrackerChange;
begin
  Result := TAtlasTrackerChange.Create('#' + IntToStr(AThread.Number), AKind, AAuthor, ATime);
  Result.Project := AThread.Repository;
  Result.Title := AThread.Title;
end;

class function TAtlasGitHubParse.ParseCommentChanges(const AJson: string; const AThread: TAtlasGitHubThread;
  ASince: TDateTime; out AChanges: TArray<TAtlasTrackerChange>): Boolean;
var
  mValue, mItem: TJSONValue;
  mTime: TDateTime;
begin
  AChanges := nil;
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
      // since= filtert nach der letzten Bearbeitung; neu ist nur, was danach angelegt wurde.
      mTime := TAtlasGitHubJson.TimeOf(TJSONObject(mItem), 'created_at');
      if mTime > ASince then
      begin
        AChanges := AChanges + [ChangeOf(AThread, TAtlasTrackerChangeKind.Comment,
          TAtlasGitHubJson.LoginOf(TJSONObject(mItem).Values['user']), mTime)];
      end;
    end;
  finally
    mValue.Free;
  end;
end;

/// <summary>Ereignis assigned, closed oder reopened als Änderung an AThread; False für andere.</summary>
function EventChangeOf(AEvent: TJSONObject; const AThread: TAtlasGitHubThread; const AMe: string; ATime: TDateTime;
  out AChange: TAtlasTrackerChange): Boolean;
var
  mEvent, mActor: string;
begin
  mEvent := LowerCase(TAtlasGitHubJson.TextOf(AEvent, 'event'));
  mActor := TAtlasGitHubJson.LoginOf(AEvent.Values['actor']);
  Result := True;
  if mEvent = 'assigned' then
  begin
    AChange := TAtlasGitHubParse.ChangeOf(AThread, TAtlasTrackerChangeKind.Assigned, mActor, ATime);
    AChange.Value := TAtlasGitHubJson.LoginOf(AEvent.Values['assignee']);
    AChange.ToMe := (AMe <> '') and SameText(AChange.Value, AMe);
  end
  else if mEvent = 'closed' then
  begin
    // Zustand wie bei GitHub; die Oberfläche übersetzt "closed" und "open".
    AChange := TAtlasGitHubParse.ChangeOf(AThread, TAtlasTrackerChangeKind.State, mActor, ATime);
    AChange.Value := 'closed';
  end
  else if mEvent = 'reopened' then
  begin
    AChange := TAtlasGitHubParse.ChangeOf(AThread, TAtlasTrackerChangeKind.State, mActor, ATime);
    AChange.Value := 'open';
  end
  else
  begin
    AChange := Default(TAtlasTrackerChange);
    Result := False;
  end;
end;

class function TAtlasGitHubParse.ParseEventChanges(const AJson: string; const AThread: TAtlasGitHubThread;
  const AMe: string; ASince: TDateTime; out AChanges: TArray<TAtlasTrackerChange>): Boolean;
var
  mValue, mItem: TJSONValue;
  mChange: TAtlasTrackerChange;
  mTime: TDateTime;
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
      if not (mItem is TJSONObject) then
      begin
        Continue;
      end;
      mTime := TAtlasGitHubJson.TimeOf(TJSONObject(mItem), 'created_at');
      if (mTime > ASince) and EventChangeOf(TJSONObject(mItem), AThread, AMe, mTime, mChange) then
      begin
        AChanges := AChanges + [mChange];
      end;
    end;
  finally
    mValue.Free;
  end;
end;

end.
