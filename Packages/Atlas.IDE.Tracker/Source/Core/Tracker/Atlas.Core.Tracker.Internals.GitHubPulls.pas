unit Atlas.Core.Tracker.Internals.GitHubPulls;

// Pull Request beim Beenden anlegen (#2136), ohne VCL und Open Tools API.
// Über die REST-API (GitHubApi), der Reihe nach:
// - GET …/pulls?state=open&head=<owner>:<branch>: Gibt es schon einen
//   offenen Pull Request für den Branch, gilt er (Existing); kein zweiter.
// - Ohne Ziel-Branch GET …/repos/<owner/repo> für den Standard-Branch.
// - POST …/pulls mit Titel, Kopf, Ziel, Text und Entwurf. Ein abgelehnter
//   Pull Request (422 „No commits between …“, 403) kommt mit dem Text von
//   GitHub zurück (erster Eintrag von "errors", sonst "message").
// - Labels und Meilenstein des Issues (GET …/issues/<n>) per PATCH
//   …/issues/<pr>, Prüfer per POST …/pulls/<pr>/requested_reviewers. Scheitert
//   das, steht der Pull Request trotzdem (DecorateFailed, ReviewersFailed).
// Jede Anfrage höchstens ACall.TimeoutMs; nichts wird wiederholt.

interface

uses
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract;

type
  TAtlasGitHubPulls = class
  public const
    /// <summary>Höchstens so viele Prüfer je Anfrage (Grenze von GitHub).</summary>
    cMaxReviewers = 15;
  public
    /// <summary>Offene Pull Requests mit Kopf AHead im Repository von ATarget; '' ohne Server, Projekt oder Branch.
    /// </summary>
    class function OpenUrl(const ATarget: TAtlasTrackerTarget; const AHead: string): string; static;
    /// <summary>Adresse des Repositorys (…/repos/&lt;owner/repo&gt;); '' ohne Server oder Projekt.</summary>
    class function RepositoryUrl(const ATarget: TAtlasTrackerTarget): string; static;
    /// <summary>Inhalt von POST …/pulls für ASpec mit Ziel ABase.</summary>
    class function CreateJson(const ASpec: TAtlasTrackerPullSpec; const ABase: string): string; static;
    /// <summary>PATCH-Inhalt mit Labels und Meilenstein aus der Antwort AIssueJson auf GET …/issues/&lt;n&gt;; ''
    /// ohne beides.</summary>
    class function DecorateJson(const AIssueJson: string): string; static;
    /// <summary>Inhalt {"reviewers": [...]} ohne leere und doppelte Namen, höchstens cMaxReviewers; '' ohne.</summary>
    class function ReviewersJson(const AReviewers: TArray<string>): string; static;
    /// <summary>Pull Request aus einer Antwort (Objekt bzw. erstes Element einer Liste); False ohne.</summary>
    class function ParsePull(const AJson: string; out APull: TAtlasTrackerPullResult): Boolean; static;
    /// <summary>Standard-Branch aus der Antwort auf GET …/repos/&lt;owner/repo&gt;; '' ohne.</summary>
    class function DefaultBranch(const AJson: string): string; static;
    /// <summary>Fehlertext einer Ablehnung: erster Eintrag von "errors" (message), sonst "message".</summary>
    class function RejectText(const AJson: string): string; static;
    /// <summary>Vorhandenen Pull Request finden oder ASpec anlegen (siehe Kopf der Unit).</summary>
    class function Create(const ACall: TAtlasTrackerCall; const ASend: IAtlasCiSend; const AKey: string;
      const ASpec: TAtlasTrackerPullSpec): TAtlasTrackerPullResult; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.CiBuild.Contract,
  Atlas.Text.Uris,
  Atlas.Core.Tracker.Internals.GitHubApi,
  Atlas.Core.Tracker.Internals.GitHubJson,
  Atlas.Text.Json;

const
  cMaxMessage = 300;
  cPullsPart = '/pulls';

class function TAtlasGitHubPulls.RepositoryUrl(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := TAtlasGitHubApi.Base(ATarget);
  if (Result = '') or (ATarget.Project = '') then
  begin
    Exit('');
  end;
  Result := Result + '/repos/' + TTextUris.PercentEncode(ATarget.Project);
end;

class function TAtlasGitHubPulls.OpenUrl(const ATarget: TAtlasTrackerTarget; const AHead: string): string;
var
  mOwner: string;
begin
  Result := RepositoryUrl(ATarget);
  mOwner := Copy(ATarget.Project, 1, Pos('/', ATarget.Project) - 1);
  if (Result = '') or (mOwner = '') or (Trim(AHead) = '') then
  begin
    Exit('');
  end;
  Result := Result + cPullsPart + '?state=open&head=' + TTextUris.PercentEncode(mOwner + ':' + Trim(AHead));
end;

class function TAtlasGitHubPulls.CreateJson(const ASpec: TAtlasTrackerPullSpec; const ABase: string): string;
var
  mRoot: TJSONObject;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('title', Trim(ASpec.Title));
    mRoot.AddPair('head', Trim(ASpec.Head));
    mRoot.AddPair('base', Trim(ABase));
    mRoot.AddPair('body', ASpec.Body);
    mRoot.AddPair('draft', TJSONBool.Create(ASpec.Draft));
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

/// <summary>Namen der Labels einer Issue-Antwort.</summary>
function LabelsOf(AIssue: TJSONObject): TJSONArray;
var
  mItems: TJSONArray;
  mItem: TJSONValue;
  mName: string;
begin
  Result := TJSONArray.Create;
  mItems := TJsonRead.Items(AIssue, 'labels');
  if mItems = nil then
  begin
    Exit;
  end;
  for mItem in mItems do
  begin
    mName := TJsonRead.Text(TJsonRead.AsObject(mItem), 'name');
    if mName <> '' then
    begin
      Result.Add(mName);
    end;
  end;
end;

class function TAtlasGitHubPulls.DecorateJson(const AIssueJson: string): string;
var
  mIssue, mRoot: TJSONObject;
  mLabels: TJSONArray;
  mMilestone: Integer;
begin
  Result := '';
  mIssue := TJsonRead.ParseObject(AIssueJson);
  if mIssue = nil then
  begin
    Exit;
  end;
  mRoot := TJSONObject.Create;
  try
    mLabels := LabelsOf(mIssue);
    if mLabels.Count > 0 then
    begin
      mRoot.AddPair('labels', mLabels);
    end
    else
    begin
      mLabels.Free;
    end;
    mMilestone := TJsonRead.IntOr(TJsonRead.Obj(mIssue, 'milestone'), 'number', 0);
    if mMilestone > 0 then
    begin
      mRoot.AddPair('milestone', TJSONNumber.Create(mMilestone));
    end;
    if mRoot.Count > 0 then
    begin
      Result := mRoot.ToJSON;
    end;
  finally
    mRoot.Free;
    mIssue.Free;
  end;
end;

class function TAtlasGitHubPulls.ReviewersJson(const AReviewers: TArray<string>): string;
var
  mRoot: TJSONObject;
  mNames: TJSONArray;
  mSeen: TList<string>;
  mName: string;
begin
  Result := '';
  mSeen := TList<string>.Create;
  try
    for mName in AReviewers do
    begin
      if (Trim(mName) <> '') and not mSeen.Contains(LowerCase(Trim(mName))) and (mSeen.Count < cMaxReviewers) then
      begin
        mSeen.Add(LowerCase(Trim(mName)));
      end;
    end;
    if mSeen.Count = 0 then
    begin
      Exit;
    end;
    mRoot := TJSONObject.Create;
    try
      mNames := TJSONArray.Create;
      mRoot.AddPair('reviewers', mNames);
      for mName in mSeen do
      begin
        mNames.Add(mName);
      end;
      Result := mRoot.ToJSON;
    finally
      mRoot.Free;
    end;
  finally
    mSeen.Free;
  end;
end;

/// <summary>Pull Request aus dem Objekt einer Antwort; False ohne Nummer.</summary>
function PullOf(AObject: TJSONObject; out APull: TAtlasTrackerPullResult): Boolean;
begin
  APull := TAtlasTrackerPullResult.Make(TAtlasTrackerPullOutcome.Created);
  APull.Number := TJsonRead.IntOr(AObject, 'number', 0);
  APull.Url := TJsonRead.Text(AObject, 'html_url');
  APull.Base := TJsonRead.Text(TJsonRead.Obj(AObject, 'base'), 'ref');
  APull.Draft := TJsonRead.Flag(AObject, 'draft');
  Result := APull.Number > 0;
end;

class function TAtlasGitHubPulls.ParsePull(const AJson: string; out APull: TAtlasTrackerPullResult): Boolean;
var
  mValue: TJSONValue;
  mObject: TJSONObject;
begin
  APull := TAtlasTrackerPullResult.Make(TAtlasTrackerPullOutcome.None);
  mValue := TJsonRead.Parse(AJson);
  try
    mObject := TJsonRead.AsObject(mValue);
    if (mObject = nil) and (mValue is TJSONArray) and (TJSONArray(mValue).Count > 0) then
    begin
      mObject := TJsonRead.AsObject(TJSONArray(mValue).Items[0]);
    end;
    Result := (mObject <> nil) and PullOf(mObject, APull);
  finally
    mValue.Free;
  end;
end;

class function TAtlasGitHubPulls.DefaultBranch(const AJson: string): string;
var
  mObject: TJSONObject;
begin
  mObject := TJsonRead.ParseObject(AJson);
  try
    Result := TJsonRead.Text(mObject, 'default_branch');
  finally
    mObject.Free;
  end;
end;

class function TAtlasGitHubPulls.RejectText(const AJson: string): string;
var
  mObject: TJSONObject;
  mErrors: TJSONArray;
begin
  Result := '';
  mObject := TJsonRead.ParseObject(AJson);
  try
    mErrors := TJsonRead.Items(mObject, 'errors');
    if (mErrors <> nil) and (mErrors.Count > 0) then
    begin
      Result := TJsonRead.Text(TJsonRead.AsObject(mErrors.Items[0]), 'message');
    end;
    if Result = '' then
    begin
      Result := TJsonRead.Text(mObject, 'message');
    end;
  finally
    mObject.Free;
  end;
  Result := TAtlasGitHubJson.Shorten(Result, cMaxMessage);
end;

type
  /// <summary>Anfrage an den Tracker samt Schreibzugang.</summary>
  TPullCall = record
    Call: TAtlasTrackerCall;
    Send: IAtlasCiSend;
  end;

/// <summary>AMethod auf AUrl mit ABody; True bei 2xx mit AText, sonst False mit APull als Fehler.</summary>
function SendJson(const ACall: TPullCall; const AMethod, AUrl, ABody: string; out AText: string;
  var APull: TAtlasTrackerPullResult): Boolean;
var
  mResponse: TAtlasCiResponse;
begin
  AText := '';
  if not ACall.Send.Send(AMethod, AUrl, ABody, ACall.Call.TimeoutMs, mResponse) then
  begin
    APull := TAtlasTrackerPullResult.Failure(mResponse.Error, 0, '');
    Exit(False);
  end;
  Result := TAtlasGitHubApi.Answered(mResponse.Status);
  AText := mResponse.Text;
  if not Result then
  begin
    APull := TAtlasTrackerPullResult.Failure(TAtlasGitHubApi.ErrorOfStatus(mResponse.Status), mResponse.Status,
      TAtlasGitHubPulls.RejectText(mResponse.Text));
  end;
end;

/// <summary>Ziel des Pull Requests: ABase, sonst der Standard-Branch; False mit APull als Fehler.</summary>
function BaseOf(const ACall: TAtlasTrackerCall; const ABase: string; out AName: string;
  var APull: TAtlasTrackerPullResult): Boolean;
var
  mText: string;
  mError: TAtlasCiFetchError;
begin
  AName := Trim(ABase);
  if AName <> '' then
  begin
    Exit(True);
  end;
  Result := TAtlasGitHubApi.GetText(ACall.Transport, TAtlasGitHubPulls.RepositoryUrl(ACall.Target),
    ACall.TimeoutMs, mText, mError);
  if Result then
  begin
    AName := TAtlasGitHubPulls.DefaultBranch(mText);
    Result := AName <> '';
    mError := TAtlasCiFetchError.Invalid;
  end;
  if not Result then
  begin
    APull := TAtlasTrackerPullResult.Failure(mError, 0, '');
  end;
end;

/// <summary>Labels und Meilenstein von AKey an Pull Request APull übernehmen; False, wenn es scheiterte.</summary>
function Decorate(const ACall: TPullCall; const AKey: string; const APull: TAtlasTrackerPullResult): Boolean;
var
  mText, mBody, mIgnored: string;
  mError: TAtlasCiFetchError;
  mFailure: TAtlasTrackerPullResult;
begin
  Result := TAtlasGitHubApi.GetText(ACall.Call.Transport, TAtlasGitHubApi.IssueApiUrl(ACall.Call.Target, AKey),
    ACall.Call.TimeoutMs, mText, mError);
  if not Result then
  begin
    Exit;
  end;
  mBody := TAtlasGitHubPulls.DecorateJson(mText);
  mFailure := APull;
  Result := (mBody = '') or SendJson(ACall, 'PATCH', TAtlasGitHubApi.IssueApiUrl(ACall.Call.Target,
    '#' + IntToStr(APull.Number)), mBody, mIgnored, mFailure);
end;

/// <summary>Prüfer an Pull Request APull; False, wenn es scheiterte.</summary>
function RequestReviewers(const ACall: TPullCall; const AReviewers: TArray<string>;
  const APull: TAtlasTrackerPullResult): Boolean;
var
  mBody, mIgnored: string;
  mFailure: TAtlasTrackerPullResult;
begin
  mBody := TAtlasGitHubPulls.ReviewersJson(AReviewers);
  mFailure := APull;
  Result := (mBody = '') or SendJson(ACall, 'POST', TAtlasGitHubPulls.RepositoryUrl(ACall.Call.Target) +
    cPullsPart + '/' + IntToStr(APull.Number) + '/requested_reviewers', mBody, mIgnored, mFailure);
end;

/// <summary>Offenen Pull Request mit Kopf AHead suchen: False mit APull (Existing bzw. Fehler), wenn nichts
/// anzulegen ist.</summary>
function NoneOpen(const ACall: TAtlasTrackerCall; const AUrl: string; out APull: TAtlasTrackerPullResult): Boolean;
var
  mText: string;
  mError: TAtlasCiFetchError;
begin
  if not TAtlasGitHubApi.GetText(ACall.Transport, AUrl, ACall.TimeoutMs, mText, mError) then
  begin
    APull := TAtlasTrackerPullResult.Failure(mError, 0, '');
    Exit(False);
  end;
  Result := not TAtlasGitHubPulls.ParsePull(mText, APull);
  if not Result then
  begin
    APull.Outcome := TAtlasTrackerPullOutcome.Existing;
  end;
end;

/// <summary>ASpec anlegen, dann Labels, Meilenstein und Prüfer.</summary>
function OpenPull(const ACall: TPullCall; const AKey: string;
  const ASpec: TAtlasTrackerPullSpec): TAtlasTrackerPullResult;
var
  mText, mBase: string;
begin
  Result := TAtlasTrackerPullResult.Make(TAtlasTrackerPullOutcome.None);
  if not BaseOf(ACall.Call, ASpec.Base, mBase, Result) or
    not SendJson(ACall, 'POST', TAtlasGitHubPulls.RepositoryUrl(ACall.Call.Target) + cPullsPart,
    TAtlasGitHubPulls.CreateJson(ASpec, mBase), mText, Result) then
  begin
    Exit;
  end;
  if not TAtlasGitHubPulls.ParsePull(mText, Result) then
  begin
    Exit(TAtlasTrackerPullResult.Failure(TAtlasCiFetchError.Invalid, 0, ''));
  end;
  if Result.Base = '' then
  begin
    Result.Base := mBase;
  end;
  Result.DecorateFailed := ASpec.CopyIssue and not Decorate(ACall, AKey, Result);
  Result.ReviewersFailed := not RequestReviewers(ACall, ASpec.Reviewers, Result);
end;

class function TAtlasGitHubPulls.Create(const ACall: TAtlasTrackerCall; const ASend: IAtlasCiSend;
  const AKey: string; const ASpec: TAtlasTrackerPullSpec): TAtlasTrackerPullResult;
var
  mUrl: string;
  mCall: TPullCall;
begin
  mUrl := OpenUrl(ACall.Target, ASpec.Head);
  if (mUrl = '') or (ASend = nil) or (ACall.Transport = nil) or (Trim(ASpec.Title) = '') then
  begin
    Exit(TAtlasTrackerPullResult.Failure(TAtlasCiFetchError.NotConfigured, 0, ''));
  end;
  if NoneOpen(ACall, mUrl, Result) then
  begin
    mCall.Call := ACall;
    mCall.Send := ASend;
    Result := OpenPull(mCall, AKey, ASpec);
  end;
end;

end.
