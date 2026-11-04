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
    /// <summary>"body" aus der Antwort von /issues/&lt;n&gt;, ungekürzt ('' bei null); False bei ungültigem JSON (#1273).
    /// </summary>
    class function ParseBody(const AJson: string; out AText: string): Boolean; static;
    /// <summary>sub_issues_summary und issue_dependencies_summary aus /issues/&lt;n&gt; (#1279).</summary>
    class function ParseLinkSummary(const AJson: string): TAtlasGitHubLinkSummary; static;
    /// <summary>Liste von Issues (…/sub_issues, …/dependencies/…) als Verknüpfungen der Art AKind; AProject
    /// entscheidet, was im Fenster öffnet. False bei ungültigem JSON.</summary>
    class function ParseRelated(const AJson, AProject: string; AKind: TAtlasTrackerLinkKind;
      out ALinks: TArray<TAtlasTrackerLink>): Boolean; static;
    /// <summary>ANew in ALinks übernehmen: eine Erwähnung desselben Issues wird durch die genauere Art ersetzt,
    /// dieselbe Art nicht doppelt; höchstens TAtlasTrackerDetails.MaxLinks.</summary>
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
  Atlas.Core.Tracker.Checklist,
  Atlas.Core.Tracker.Internals.GitHubApi,
  Atlas.Core.Tracker.Internals.GitHubJson;

class function TAtlasGitHubParse.ParseIssues(const AJson: string; AMax: Integer;
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
    begin
      Exit;
    end;
    Items := TJSONObject(Value).Values['items'];
    if not (Items is TJSONArray) then
    begin
      Exit;
    end;
    Result := True;
    for Item in TJSONArray(Items) do
    begin
      if Length(AIssues) >= AMax then
      begin
        Break;
      end;
      if not (Item is TJSONObject) then
      begin
        Continue;
      end;
      // Die Suche liefert auch Pull Requests; die gehören nicht in die Liste.
      if TJSONObject(Item).Values['pull_request'] <> nil then
      begin
        Continue;
      end;
      Issue := TAtlasTrackerIssue.Empty;
      Issue.Number := TAtlasGitHubJson.IntOf(TJSONObject(Item), 'number');
      if Issue.Number <= 0 then
      begin
        Continue;
      end;
      Issue.Key := '#' + IntToStr(Issue.Number);
      Issue.Title := TAtlasGitHubJson.Shorten(TAtlasGitHubJson.TextOf(TJSONObject(Item), 'title'),
        TAtlasTrackerIssue.MaxTitle);
      Issue.State := TAtlasGitHubJson.TextOf(TJSONObject(Item), 'state');
      Issue.Assignee := TAtlasGitHubJson.AssigneesOf(TJSONObject(Item));
      Labels := TJSONObject(Item).Values['labels'];
      if Labels is TJSONArray then
      begin
        for LabelValue in TJSONArray(Labels) do
        begin
          if Length(Issue.Labels) >= TAtlasTrackerIssue.MaxLabels then
          begin
            Break;
          end;
          LabelName := '';
          if LabelValue is TJSONObject then
          begin
            LabelName := Trim(TAtlasGitHubJson.TextOf(TJSONObject(LabelValue), 'name'));
          end
          else if LabelValue is TJSONString then
          begin
            LabelName := Trim(TJSONString(LabelValue).Value);
          end;
          if LabelName <> '' then
          begin
            Issue.Labels := Issue.Labels + [TAtlasGitHubJson.Shorten(LabelName, 40)];
          end;
        end;
      end;
      AIssues := AIssues + [Issue];
    end;
  finally
    Value.Free;
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
  Value, Item, Head: TJSONValue;
  Pull: TAtlasGitHubPull;
begin
  APulls := nil;
  Result := False;
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Value is TJSONArray) then
    begin
      Exit;
    end;
    Result := True;
    for Item in TJSONArray(Value) do
    begin
      if not (Item is TJSONObject) then
      begin
        Continue;
      end;
      Pull := Default(TAtlasGitHubPull);
      Pull.Number := TAtlasGitHubJson.IntOf(TJSONObject(Item), 'number');
      if Pull.Number <= 0 then
      begin
        Continue;
      end;
      Pull.Draft := TAtlasGitHubJson.FlagOf(TJSONObject(Item), 'draft');
      Pull.State := LowerCase(TAtlasGitHubJson.TextOf(TJSONObject(Item), 'state'));
      Pull.Merged := TAtlasGitHubJson.TextOf(TJSONObject(Item), 'merged_at') <> '';
      Pull.Updated := UpdatedOf(TJSONObject(Item));
      Pull.Title := TAtlasGitHubJson.TextOf(TJSONObject(Item), 'title');
      // Nur der Anfang: „closes #N“ steht fast immer oben, und lange Beschreibungen kosten nur Speicher.
      Pull.Body := Copy(TAtlasGitHubJson.TextOf(TJSONObject(Item), 'body'), 1, 4000);
      Head := TJSONObject(Item).Values['head'];
      if Head is TJSONObject then
      begin
        Pull.Branch := TAtlasGitHubJson.TextOf(TJSONObject(Head), 'ref');
        Pull.Sha := TAtlasGitHubJson.TextOf(TJSONObject(Head), 'sha');
      end;
      APulls := APulls + [Pull];
    end;
  finally
    Value.Free;
  end;
end;

/// <summary>„close(s|d)“, „fix(es|ed)“ oder „resolve(s|d)“, optional „:“, dann „#N“ ohne weitere Ziffer.</summary>
function TextClosesIssue(const AText: string; ANumber: Integer): Boolean;
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
      begin
        Dec(Start);
      end;
      Stop := Start;
      while (Start >= 1) and CharInSet(Lower[Start], ['a'..'z']) do
      begin
        Dec(Start);
      end;
      if Stop > Start then
      begin
        for Word in Words do
        begin
          if Copy(Lower, Start + 1, Stop - Start) = Word then
          begin
            Exit(True);
          end;
        end;
      end;
    end;
    Index := Pos(Mark, Lower, Index + 1);
  end;
end;

class function TAtlasGitHubParse.PullMentions(const APull: TAtlasGitHubPull; ANumber: Integer): Boolean;
begin
  Result := False;
  if ANumber <= 0 then
  begin
    Exit;
  end;
  Result := (TAtlasTrackerNaming.KeyOfBranch(TAtlasGitHubApi.ProviderName, '',
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
  Value, Runs, Run: TJSONValue;
  Status, Conclusion: string;
  Any, Running, Failed: Boolean;
begin
  AChecks := TAtlasTrackerChecks.Unknown;
  Result := False;
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Value is TJSONObject) then
    begin
      Exit;
    end;
    Runs := TJSONObject(Value).Values['check_runs'];
    if not (Runs is TJSONArray) then
    begin
      Exit;
    end;
    Result := True;
    Any := False;
    Running := False;
    Failed := False;
    for Run in TJSONArray(Runs) do
    begin
      if not (Run is TJSONObject) then
      begin
        Continue;
      end;
      Any := True;
      Status := LowerCase(TAtlasGitHubJson.TextOf(TJSONObject(Run), 'status'));
      Conclusion := LowerCase(TAtlasGitHubJson.TextOf(TJSONObject(Run), 'conclusion'));
      if Status <> 'completed' then
      begin
        Running := True;
      end
      else if (Conclusion = 'failure') or (Conclusion = 'timed_out') or (Conclusion = 'cancelled') or
        (Conclusion = 'action_required') or (Conclusion = 'startup_failure') then
      begin
        Failed := True;
      end;
    end;
    if Failed then
    begin
      AChecks := TAtlasTrackerChecks.Failure;
    end
    else if Running then
    begin
      AChecks := TAtlasTrackerChecks.Pending;
    end
    else if Any then
    begin
      AChecks := TAtlasTrackerChecks.Success;
    end;
  finally
    Value.Free;
  end;
end;

class function TAtlasGitHubParse.ParseStatus(const AJson: string; out AChecks: TAtlasTrackerChecks): Boolean;
var
  Value, Statuses: TJSONValue;
  State: string;
begin
  AChecks := TAtlasTrackerChecks.Unknown;
  Result := False;
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Value is TJSONObject) then
    begin
      Exit;
    end;
    Result := True;
    // Ohne einzelne Status meldet GitHub "pending"; das ist keine Ampel.
    Statuses := TJSONObject(Value).Values['statuses'];
    if not (Statuses is TJSONArray) or (TJSONArray(Statuses).Count = 0) then
    begin
      Exit;
    end;
    State := LowerCase(TAtlasGitHubJson.TextOf(TJSONObject(Value), 'state'));
    if State = 'success' then
    begin
      AChecks := TAtlasTrackerChecks.Success;
    end
    else if (State = 'failure') or (State = 'error') then
    begin
      AChecks := TAtlasTrackerChecks.Failure;
    end
    else if State = 'pending' then
    begin
      AChecks := TAtlasTrackerChecks.Pending;
    end;
  finally
    Value.Free;
  end;
end;

class function TAtlasGitHubParse.ParseDetails(const AJson: string; out ADetails: TAtlasTrackerDetails;
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
    begin
      Exit;
    end;
    mRoot := TJSONObject(mValue);
    ADetails.Number := TAtlasGitHubJson.IntOf(mRoot, 'number');
    if ADetails.Number <= 0 then
    begin
      Exit;
    end;
    ADetails.Key := '#' + IntToStr(ADetails.Number);
    ADetails.Title := TAtlasGitHubJson.Shorten(TAtlasGitHubJson.TextOf(mRoot, 'title'), 500);
    ADetails.Description := TAtlasGitHubJson.Limited(TAtlasGitHubJson.TextOf(mRoot, 'body'));
    // "closed" mit Grund ("completed", "not_planned") wie in der Oberfläche.
    ADetails.State := TAtlasGitHubJson.TextOf(mRoot, 'state');
    mReason := TAtlasGitHubJson.TextOf(mRoot, 'state_reason');
    if (ADetails.State = 'closed') and (mReason <> '') and (mReason <> 'completed') then
    begin
      ADetails.State := ADetails.State + ' (' + StringReplace(mReason, '_', ' ', [rfReplaceAll]) + ')';
    end;
    ADetails.Created := TAtlasGitHubJson.TimeOf(mRoot, 'created_at');
    ADetails.Updated := TAtlasGitHubJson.TimeOf(mRoot, 'updated_at');
    ACommentCount := TAtlasGitHubJson.IntOf(mRoot, 'comments');
    mItem := mRoot.Values['labels'];
    if mItem is TJSONArray then
    begin
      for mEntry in TJSONArray(mItem) do
      begin
        mText := '';
        if mEntry is TJSONObject then
        begin
          mText := Trim(TAtlasGitHubJson.TextOf(TJSONObject(mEntry), 'name'));
        end
        else if mEntry is TJSONString then
        begin
          mText := Trim(TJSONString(mEntry).Value);
        end;
        if mText <> '' then
        begin
          ADetails.Labels := ADetails.Labels + [TAtlasGitHubJson.Shorten(mText, 40)];
        end;
      end;
    end;
    ADetails.Assignee := TAtlasGitHubJson.AssigneesOf(mRoot);
    if mRoot.Values['milestone'] is TJSONObject then
    begin
      ADetails.Sprint := TAtlasGitHubJson.Shorten(TAtlasGitHubJson.TextOf(TJSONObject(mRoot.Values['milestone']),
        'title'), 60);
    end;
    // Issue-Typen (Bug, Feature …) der Organisation.
    if mRoot.Values['type'] is TJSONObject then
    begin
      ADetails.Kind := TAtlasGitHubJson.Shorten(TAtlasGitHubJson.TextOf(TJSONObject(mRoot.Values['type']), 'name'), 40);
    end;
    Result := True;
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

class function TAtlasGitHubParse.ParseTimeline(const AJson, AProject: string;
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
    begin
      Exit;
    end;
    Result := True;
    for mItem in TJSONArray(mValue) do
    begin
      if not (mItem is TJSONObject) or (TAtlasGitHubJson.TextOf(TJSONObject(mItem), 'event') <> 'cross-referenced') then
      begin
        Continue;
      end;
      mSource := TJSONObject(mItem).Values['source'];
      if not (mSource is TJSONObject) then
      begin
        Continue;
      end;
      mIssue := TJSONObject(mSource).Values['issue'];
      if not (mIssue is TJSONObject) then
      begin
        Continue;
      end;
      mNumber := TAtlasGitHubJson.IntOf(TJSONObject(mIssue), 'number');
      if mNumber <= 0 then
      begin
        Continue;
      end;
      mRepository := '';
      if TJSONObject(mIssue).Values['repository'] is TJSONObject then
      begin
        mRepository := TAtlasGitHubJson.TextOf(TJSONObject(TJSONObject(mIssue).Values['repository']), 'full_name');
      end;
      mLink := Default(TAtlasTrackerLink);
      mLink.Local := (mRepository = '') or SameText(mRepository, AProject);
      if mLink.Local then
      begin
        mLink.Key := '#' + IntToStr(mNumber);
      end
      else
      begin
        mLink.Key := mRepository + '#' + IntToStr(mNumber);
      end;
      mLink.Title := TAtlasGitHubJson.Shorten(TAtlasGitHubJson.TextOf(TJSONObject(mIssue), 'title'), 200);
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
      mLink.State := TAtlasGitHubJson.TextOf(TJSONObject(mIssue), 'state');
      mLink.StateKnown := mLink.State <> '';
      mLink.Resolved := SameText(mLink.State, 'closed');
      // Nur Web-Seiten über https; was nicht im Fenster öffnet, geht in den Browser.
      mPage := TAtlasGitHubJson.TextOf(TJSONObject(mIssue), 'html_url');
      if StartsText('https://', mPage) then
      begin
        mLink.Page := mPage;
      end;
      mKnown := False;
      for mIndex := 0 to High(ALinks) do
      begin
        if SameText(ALinks[mIndex].Key, mLink.Key) then
        begin
          mKnown := True;
        end;
      end;
      if not mKnown and (Length(ALinks) < TAtlasTrackerDetails.MaxLinks) then
      begin
        ALinks := ALinks + [mLink];
      end;
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasGitHubParse.FileAttachments(
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
  begin
    mTexts := mTexts + [mComment.Text];
  end;
  for mText in mTexts do
  begin
    for mLink in TAtlasTrackerMarkdown.Links(mText) do
    begin
      if not StartsText('https://', mLink.Url) or (Pos('/user-attachments/files/', mLink.Url) = 0) then
      begin
        Continue;
      end;
      mKnown := False;
      for mIndex := 0 to High(Result) do
      begin
        if Result[mIndex].Url = mLink.Url then
        begin
          mKnown := True;
        end;
      end;
      if mKnown or (Length(Result) >= TAtlasTrackerDetails.MaxAttachments) then
      begin
        Continue;
      end;
      mAttachment := Default(TAtlasTrackerAttachment);
      mAttachment.Name := TAtlasGitHubJson.Shorten(mLink.Text, 200);
      if mAttachment.Name = '' then
      begin
        mAttachment.Name := Copy(mLink.Url, LastDelimiter('/', mLink.Url) + 1, 200);
      end;
      mAttachment.Size := -1;
      mAttachment.Url := mLink.Url;
      mAttachment.External := True;
      Result := Result + [mAttachment];
    end;
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
    begin
      Exit;
    end;
    Result := True;
    for mItem in TJSONArray(mValue) do
    begin
      if not (mItem is TJSONObject) or (Length(ALinks) >= TAtlasTrackerDetails.MaxLinks) then
      begin
        Continue;
      end;
      mIssue := TJSONObject(mItem);
      mNumber := TAtlasGitHubJson.IntOf(mIssue, 'number');
      if mNumber <= 0 then
      begin
        Continue;
      end;
      mRepository := RepositoryOf(mIssue);
      mLink := Default(TAtlasTrackerLink);
      mLink.Local := (mRepository = '') or SameText(mRepository, AProject);
      if mLink.Local then
      begin
        mLink.Key := '#' + IntToStr(mNumber);
      end
      else
      begin
        mLink.Key := mRepository + '#' + IntToStr(mNumber);
      end;
      mLink.Title := TAtlasGitHubJson.Shorten(TAtlasGitHubJson.TextOf(mIssue, 'title'), 200);
      mLink.Kind := AKind;
      mLink.Relation := Relations[AKind];
      mLink.State := TAtlasGitHubJson.TextOf(mIssue, 'state');
      mLink.StateKnown := mLink.State <> '';
      mLink.Resolved := SameText(mLink.State, 'closed');
      mPage := TAtlasGitHubJson.TextOf(mIssue, 'html_url');
      if StartsText('https://', mPage) then
      begin
        mLink.Page := mPage;
      end;
      ALinks := ALinks + [mLink];
    end;
  finally
    mValue.Free;
  end;
end;

class procedure TAtlasGitHubParse.MergeLinks(var ALinks: TArray<TAtlasTrackerLink>;
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
    begin
      if SameText(ALinks[mIndex].Key, mLink.Key) then
      begin
        if ALinks[mIndex].Kind = mLink.Kind then
        begin
          mDone := True;
        end
        // Die Erwähnung desselben Issues weicht der genaueren Art.
        else if ALinks[mIndex].Kind in [TAtlasTrackerLinkKind.Mentioned, TAtlasTrackerLinkKind.Other] then
        begin
          ALinks[mIndex] := mLink;
          mDone := True;
        end;
        if mDone then
        begin
          Break;
        end;
      end;
    end;
    if not mDone and (Length(ALinks) < TAtlasTrackerDetails.MaxLinks) then
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
        TAtlasTrackerIssue.MaxTitle);
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

class function TAtlasGitHubParse.ParseEventChanges(const AJson: string; const AThread: TAtlasGitHubThread;
  const AMe: string; ASince: TDateTime; out AChanges: TArray<TAtlasTrackerChange>): Boolean;
var
  mValue, mItem: TJSONValue;
  mObject: TJSONObject;
  mEvent: string;
  mChange: TAtlasTrackerChange;
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
      mObject := TJSONObject(mItem);
      mTime := TAtlasGitHubJson.TimeOf(mObject, 'created_at');
      if mTime <= ASince then
      begin
        Continue;
      end;
      mEvent := LowerCase(TAtlasGitHubJson.TextOf(mObject, 'event'));
      if mEvent = 'assigned' then
      begin
        mChange := ChangeOf(AThread, TAtlasTrackerChangeKind.Assigned,
          TAtlasGitHubJson.LoginOf(mObject.Values['actor']), mTime);
        mChange.Value := TAtlasGitHubJson.LoginOf(mObject.Values['assignee']);
        mChange.ToMe := (AMe <> '') and SameText(mChange.Value, AMe);
      end
      else if (mEvent = 'closed') or (mEvent = 'reopened') then
      begin
        mChange := ChangeOf(AThread, TAtlasTrackerChangeKind.State, TAtlasGitHubJson.LoginOf(mObject.Values['actor']),
          mTime);
        // Zustand wie bei GitHub; die Oberfläche übersetzt "closed" und "open".
        if mEvent = 'closed' then
        begin
          mChange.Value := 'closed';
        end
        else
        begin
          mChange.Value := 'open';
        end;
      end
      else
      begin
        Continue;
      end;
      AChanges := AChanges + [mChange];
    end;
  finally
    mValue.Free;
  end;
end;

end.
