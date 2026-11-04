unit Atlas.Core.Tracker.Internals.GitHubApi;

// Adressen und Anfragen der GitHub-REST-API (#765, #1268), ohne Netz und daher
// testbar: github.com → https://api.github.com, GitHub Enterprise →
// <Server>/api/v3. Der Anbieter (Providers.GitHub), sein Board
// (GitHubBoards) und „Issue anlegen“ (NewIssue) bauen ihre Adressen
// alle hierauf, damit Enterprise überall gleich behandelt wird. Dazu die
// Inhalte schreibender Anfragen (Kommentar, Beschreibung, Labels und
// Zuständige) und die Zuordnung von HTTP-Status zu Fehlern.

interface

uses
  System.SysUtils,
  System.Diagnostics,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract;

type
  TAtlasGitHubApi = class
  public const
    ApiHost = 'https://api.github.com';
    ProviderName = 'github';
    /// <summary>Vorgabe der Abfrage „Meine Issues“.</summary>
    DefaultQuery = 'assignee:@me state:open';
    /// <summary>Höchstens so viele offene Pull Requests je Abfrage.</summary>
    MaxPulls = 50;
    /// <summary>Größte Seite der REST-API.</summary>
    MaxPageSize = 100;
  public
    /// <summary>Basis der REST-API; '' ohne gültigen Server.</summary>
    class function Base(const ATarget: TAtlasTrackerTarget): string; static;
    /// <summary>Seite des Issues AKey ("#753") im Browser; '' ohne Server, Projekt oder gültige Nummer.</summary>
    class function IssuePage(const ATarget: TAtlasTrackerTarget; const AKey: string): string; static;
    /// <summary>Kommentar AText an das Issue AKey (POST …/comments); Ok bei 2xx, sonst Fehler mit Status und
    /// Meldung von GitHub.</summary>
    class function PostComment(const ATarget: TAtlasTrackerTarget; const ASend: IAtlasCiSend; const AKey,
      AText: string; ATimeoutMs: Integer): TAtlasTrackerWriteResult; static;
    /// <summary>Suchtext, wie er an /search/issues geht (mit repo: und is:issue).</summary>
    class function SearchText(const ATarget: TAtlasTrackerTarget): string; static;
    class function SearchUrl(const ATarget: TAtlasTrackerTarget; AMax: Integer): string; static;
    /// <summary>Freitextsuche der Palette (#1270); '' ohne Server, Projekt oder Text.</summary>
    class function TextSearchUrl(const ATarget: TAtlasTrackerTarget; const AText: string; AMax: Integer): string;
      static;
    class function PullsUrl(const ATarget: TAtlasTrackerTarget): string; static;
    class function CheckRunsUrl(const ATarget: TAtlasTrackerTarget; const ASha: string): string; static;
    class function StatusUrl(const ATarget: TAtlasTrackerTarget; const ASha: string): string; static;
    /// <summary>Alle Pull Requests, zuletzt geänderte zuerst (#1269).</summary>
    class function AllPullsUrl(const ATarget: TAtlasTrackerTarget): string; static;
    /// <summary>Fehler zu einem HTTP-Status außer 200.</summary>
    class function ErrorOfStatus(AStatus: Integer): TAtlasCiFetchError; static;
    class function NumberOfKey(const AKey: string): Integer; static;
    /// <summary>Adresse eines Issues in der API (ohne Anhang wie /comments); '' bei ungültiger Kennung.</summary>
    class function IssueApiUrl(const ATarget: TAtlasTrackerTarget; const AKey: string): string; static;
    class function Remaining(const AWatch: TStopwatch; ATimeoutMs: Integer): Integer; static;
    /// <summary>AState schließt das Issue statt ein Label zu setzen (Erledigt, Done, Closed, Geschlossen, Completed,
    /// Fertig; ohne Groß-/Kleinschreibung).</summary>
    class function ClosesIssue(const AState: string): Boolean; static;
    /// <summary>Inhalt für …/comments: {"body": AText}.</summary>
    class function CommentJson(const AText: string): string; static;
    /// <summary>PATCH-Inhalt für AChange auf dem Stand ALabels/AAssignees; AMe = eigener Anmeldename. '' = nichts
    /// zu ändern.</summary>
    class function PatchJson(const ALabels, AAssignees: TArray<string>; const AChange: TAtlasTrackerWrite;
      const AMe: string): string; static;
    /// <summary>…/repos/&lt;owner/repo&gt;/assignees (#1266, #1278); '' ohne Server oder Projekt.</summary>
    class function AssigneesUrl(const ATarget: TAtlasTrackerTarget): string; static;
    /// <summary>Fehlertext ("message") einer Antwort; '' ohne.</summary>
    class function ErrorMessage(const AJson: string): string; static;
    class function Answered(AStatus: Integer): Boolean; static;
    /// <summary>Inhalt des PATCH: {"body": AText}.</summary>
    class function BodyJson(const AText: string): string; static;
    /// <summary>Inhalt für POST /issues.</summary>
    class function NewIssueBody(const ATitle, ADescription: string): string; static;
    /// <summary>Inhalt {"&lt;AName&gt;": AId} für sub_issues bzw. blocked_by.</summary>
    class function IdBody(const AName: string; AId: Int64): string; static;
    /// <summary>ISO 8601 in UTC ("2026-10-28T10:40:49Z").</summary>
    class function IsoTime(ATime: TDateTime): string; static;
    /// <summary>Adresse der Benachrichtigungen ab ASince (#1271); '' ohne Server.</summary>
    class function NotificationsUrl(const ATarget: TAtlasTrackerTarget; ASince: TDateTime): string; static;
    /// <summary>Adresse für einen neuen Kommentar (#1276); '' bei ungültiger Kennung.</summary>
    class function CommentsUrl(const ATarget: TAtlasTrackerTarget; const AKey: string): string; static;
  end;

implementation

uses
  System.Classes,
  System.DateUtils,
  System.Generics.Collections,
  System.JSON,
  System.StrUtils,
  Atlas.Text.Uris,
  Atlas.Core.Tracker.Internals.GitHubJson;

class function TAtlasGitHubApi.Base(const ATarget: TAtlasTrackerTarget): string;
var
  mServer: string;
begin
  mServer := ATarget.Server;
  if mServer = '' then
  begin
    Exit('');
  end;
  if (mServer = 'https://github.com') or (mServer = 'https://www.github.com') then
  begin
    Result := ApiHost;
  end
  else
  begin
    Result := mServer + '/api/v3';
  end;
end;

class function TAtlasGitHubApi.SearchText(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := ATarget.Query;
  if Result = '' then
  begin
    Result := DefaultQuery;
  end;
  Result := Result + ' repo:' + ATarget.Project + ' is:issue';
end;

class function TAtlasGitHubApi.SearchUrl(const ATarget: TAtlasTrackerTarget; AMax: Integer): string;
var
  Text: string;
  Limit: Integer;
begin
  Result := Base(ATarget);
  if (Result = '') or (ATarget.Project = '') then
  begin
    Exit('');
  end;
  Text := SearchText(ATarget);
  Limit := AMax;
  if Limit < 1 then
  begin
    Limit := 1;
  end;
  if Limit > 100 then
  begin
    Limit := 100;
  end;
  Result := Result + '/search/issues?q=' + TTextUris.PercentEncode(Text) + '&per_page=' + IntToStr(Limit) +
    '&sort=updated&order=desc';
end;

class function TAtlasGitHubApi.TextSearchUrl(const ATarget: TAtlasTrackerTarget; const AText: string;
  AMax: Integer): string;
var
  mLimit: Integer;
begin
  Result := Base(ATarget);
  if (Result = '') or (ATarget.Project = '') or (Trim(AText) = '') then
  begin
    Exit('');
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
  // Ohne sort: GitHub ordnet nach Treffergüte.
  Result := Result + '/search/issues?q=' + TTextUris.PercentEncode('repo:' + ATarget.Project + ' is:issue ' +
    Trim(AText)) + '&per_page=' + IntToStr(mLimit);
end;

class function TAtlasGitHubApi.PullsUrl(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := Base(ATarget);
  if (Result = '') or (ATarget.Project = '') then
  begin
    Exit('');
  end;
  Result := Result + '/repos/' + TTextUris.PercentEncode(ATarget.Project) + '/pulls?state=open&per_page=' +
    IntToStr(MaxPulls);
end;

function SafeSha(const ASha: string): Boolean;
var
  Index: Integer;
begin
  Result := (Length(ASha) >= 7) and (Length(ASha) <= 64);
  if Result then
  begin
    for Index := 1 to Length(ASha) do
    begin
      if not CharInSet(ASha[Index], ['0'..'9', 'a'..'f', 'A'..'F']) then
      begin
        Exit(False);
      end;
    end;
  end;
end;

class function TAtlasGitHubApi.CheckRunsUrl(const ATarget: TAtlasTrackerTarget; const ASha: string): string;
begin
  Result := Base(ATarget);
  if (Result = '') or (ATarget.Project = '') or not SafeSha(ASha) then
  begin
    Exit('');
  end;
  Result := Result + '/repos/' + TTextUris.PercentEncode(ATarget.Project) + '/commits/' + ASha +
    '/check-runs?per_page=100';
end;

class function TAtlasGitHubApi.StatusUrl(const ATarget: TAtlasTrackerTarget; const ASha: string): string;
begin
  Result := Base(ATarget);
  if (Result = '') or (ATarget.Project = '') or not SafeSha(ASha) then
  begin
    Exit('');
  end;
  Result := Result + '/repos/' + TTextUris.PercentEncode(ATarget.Project) + '/commits/' + ASha + '/status';
end;

class function TAtlasGitHubApi.AllPullsUrl(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := Base(ATarget);
  if (Result = '') or (ATarget.Project = '') then
  begin
    Exit('');
  end;
  Result := Result + '/repos/' + TTextUris.PercentEncode(ATarget.Project) + '/pulls?state=all&per_page=' +
    IntToStr(MaxPageSize) + '&sort=updated&direction=desc';
end;

class function TAtlasGitHubApi.ErrorOfStatus(AStatus: Integer): TAtlasCiFetchError;
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

/// <summary>Kennung ohne führende "#" ("#753" → "753"), wie TAtlasTrackerNaming.BranchKey.</summary>
function NumberText(const AKey: string): string;
begin
  Result := Trim(AKey);
  while (Result <> '') and (Result[1] = '#') do
  begin
    Delete(Result, 1, 1);
  end;
end;

class function TAtlasGitHubApi.NumberOfKey(const AKey: string): Integer;
begin
  if not TryStrToInt(NumberText(AKey), Result) or (Result <= 0) then
  begin
    Result := 0;
  end;
end;

class function TAtlasGitHubApi.IssueApiUrl(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
var
  mNumber: Integer;
begin
  Result := Base(ATarget);
  mNumber := NumberOfKey(AKey);
  if (Result = '') or (ATarget.Project = '') or (mNumber = 0) then
  begin
    Exit('');
  end;
  Result := Result + '/repos/' + TTextUris.PercentEncode(ATarget.Project) + '/issues/' + IntToStr(mNumber);
end;

class function TAtlasGitHubApi.Remaining(const AWatch: TStopwatch; ATimeoutMs: Integer): Integer;
var
  Rest: Int64;
begin
  Rest := ATimeoutMs - AWatch.ElapsedMilliseconds;
  Result := 0;
  if Rest > 0 then
  begin
    Result := Integer(Rest);
  end;
end;


const
  ClosingStates: array[0..5] of string = ('Erledigt', 'Done', 'Closed', 'Geschlossen', 'Completed', 'Fertig');

class function TAtlasGitHubApi.ClosesIssue(const AState: string): Boolean;
var
  mState: string;
begin
  Result := False;
  for mState in ClosingStates do
  begin
    if SameText(mState, Trim(AState)) then
    begin
      Exit(True);
    end;
  end;
end;

class function TAtlasGitHubApi.CommentJson(const AText: string): string;
var
  mObject: TJSONObject;
begin
  mObject := TJSONObject.Create;
  try
    mObject.AddPair('body', AText);
    Result := mObject.ToJSON;
  finally
    mObject.Free;
  end;
end;

function IndexOfText(const AItems: TArray<string>; const AText: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AItems) do
  begin
    if SameText(AItems[mIndex], AText) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function JsonList(const AItems: TArray<string>): TJSONArray;
var
  mItem: string;
begin
  Result := TJSONArray.Create;
  for mItem in AItems do
  begin
    Result.Add(mItem);
  end;
end;

class function TAtlasGitHubApi.PatchJson(const ALabels, AAssignees: TArray<string>;
  const AChange: TAtlasTrackerWrite; const AMe: string): string;
var
  mObject: TJSONObject;
  mLabels, mAssignees: TArray<string>;
  mState, mPrevious: string;
  mIndex: Integer;
  mClose, mLabelsChanged, mAssigneesChanged: Boolean;
begin
  Result := '';
  mLabels := Copy(ALabels);
  mAssignees := Copy(AAssignees);
  mState := Trim(AChange.State);
  mPrevious := Trim(AChange.PreviousState);
  mClose := (mState <> '') and ClosesIssue(mState);
  mLabelsChanged := False;
  if mState <> '' then
  begin
    // Der Zustand aus „Beginnen“ gilt nicht mehr.
    mIndex := IndexOfText(mLabels, mPrevious);
    if (mPrevious <> '') and not SameText(mPrevious, mState) and (mIndex >= 0) then
    begin
      Delete(mLabels, mIndex, 1);
      mLabelsChanged := True;
    end;
    if not mClose and (IndexOfText(mLabels, mState) < 0) then
    begin
      mLabels := mLabels + [mState];
      mLabelsChanged := True;
    end;
  end;
  mAssigneesChanged := False;
  case AChange.Assign of
    TAtlasTrackerAssign.Me:
      if (AMe <> '') and (IndexOfText(mAssignees, AMe) < 0) then
      begin
        mAssignees := mAssignees + [AMe];
        mAssigneesChanged := True;
      end;
    TAtlasTrackerAssign.User:
      if Trim(AChange.Assignee) <> '' then
      begin
        // Übergeben: der neue Zuständige statt aller bisherigen.
        mAssigneesChanged := (Length(mAssignees) <> 1) or not SameText(mAssignees[0], Trim(AChange.Assignee));
        mAssignees := TArray<string>.Create(Trim(AChange.Assignee));
      end;
  else
    // Keep: Zuständige bleiben.
  end;
  if not (mLabelsChanged or mAssigneesChanged or mClose) then
  begin
    Exit;
  end;
  mObject := TJSONObject.Create;
  try
    if mLabelsChanged then
    begin
      mObject.AddPair('labels', JsonList(mLabels));
    end;
    if mAssigneesChanged then
    begin
      mObject.AddPair('assignees', JsonList(mAssignees));
    end;
    if mClose then
    begin
      mObject.AddPair('state', 'closed');
      mObject.AddPair('state_reason', 'completed');
    end;
    Result := mObject.ToJSON;
  finally
    mObject.Free;
  end;
end;

class function TAtlasGitHubApi.AssigneesUrl(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := Base(ATarget);
  if (Result = '') or (ATarget.Project = '') then
  begin
    Exit('');
  end;
  Result := Result + '/repos/' + TTextUris.PercentEncode(ATarget.Project) + '/assignees?per_page=' +
    IntToStr(MaxPageSize);
end;

class function TAtlasGitHubApi.ErrorMessage(const AJson: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if mValue is TJSONObject then
    begin
      Result := TAtlasGitHubJson.TextOf(TJSONObject(mValue), 'message');
    end;
  finally
    mValue.Free;
  end;
  Result := TAtlasGitHubJson.Shorten(Result, 300);
end;

class function TAtlasGitHubApi.Answered(AStatus: Integer): Boolean;
begin
  Result := (AStatus >= 200) and (AStatus <= 299);
end;

class function TAtlasGitHubApi.BodyJson(const AText: string): string;
var
  mObject: TJSONObject;
begin
  mObject := TJSONObject.Create;
  try
    mObject.AddPair('body', AText);
    Result := mObject.ToJSON;
  finally
    mObject.Free;
  end;
end;

class function TAtlasGitHubApi.NewIssueBody(const ATitle, ADescription: string): string;
var
  mRoot: TJSONObject;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('title', Trim(ATitle));
    if Trim(ADescription) <> '' then
    begin
      mRoot.AddPair('body', ADescription);
    end;
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasGitHubApi.IdBody(const AName: string; AId: Int64): string;
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

class function TAtlasGitHubApi.IsoTime(ATime: TDateTime): string;
begin
  Result := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss"Z"', ATime);
end;

class function TAtlasGitHubApi.NotificationsUrl(const ATarget: TAtlasTrackerTarget; ASince: TDateTime): string;
begin
  Result := Base(ATarget);
  if Result <> '' then
  begin
    Result := Result + '/notifications?since=' + TTextUris.PercentEncode(IsoTime(ASince)) + '&per_page=50';
  end;
end;

class function TAtlasGitHubApi.CommentsUrl(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
begin
  Result := IssueApiUrl(ATarget, AKey);
  if Result <> '' then
  begin
    Result := Result + '/comments';
  end;
end;

class function TAtlasGitHubApi.IssuePage(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
begin
  Result := '';
  if (ATarget.Server <> '') and (ATarget.Project <> '') and (NumberOfKey(AKey) > 0) then
  begin
    Result := ATarget.Server + '/' + TTextUris.PercentEncode(ATarget.Project) + '/issues/' +
      IntToStr(NumberOfKey(AKey));
  end;
end;

class function TAtlasGitHubApi.PostComment(const ATarget: TAtlasTrackerTarget; const ASend: IAtlasCiSend; const AKey,
  AText: string; ATimeoutMs: Integer): TAtlasTrackerWriteResult;
var
  mUrl: string;
  mResponse: TAtlasCiResponse;
begin
  mUrl := IssueApiUrl(ATarget, AKey);
  if (mUrl = '') or (ASend = nil) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.NotConfigured, 0, ''));
  end;
  if not ASend.Send('POST', mUrl + '/comments', CommentJson(AText), ATimeoutMs, mResponse) then
  begin
    Exit(TAtlasTrackerWriteResult.Failed(mResponse.Error, 0, ''));
  end;
  Result := TAtlasTrackerWriteResult.Ok;
  if not Answered(mResponse.Status) then
  begin
    Result := TAtlasTrackerWriteResult.Failed(ErrorOfStatus(mResponse.Status), mResponse.Status,
      ErrorMessage(mResponse.Text));
  end;
end;

end.
