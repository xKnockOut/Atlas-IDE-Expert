unit Atlas.Core.Tracker.Internals.GitHubLinkedBranches;

// Verknüpfte Branches eines GitHub-Issues (#2138, Bereich „Development“ am
// Issue), ohne VCL und Open Tools API. Über die GraphQL-Schicht
// (GitHubGraphQl):
// - Eine Abfrage liest Repository, Issue mit seinen verknüpften Branches, den
//   gewünschten Branch (gibt es ihn schon?), die Basis und den Standard-Branch
//   mit ihrem Kopf.
// - Hat das Issue schon einen verknüpften Branch, gilt dieser (Found; der mit
//   dem gewünschten Namen zuerst). Gibt es den Branch schon, wird nichts
//   verknüpft (Exists). Sonst legt createLinkedBranch ihn vom Kopf der Basis
//   an, fehlt sie auf dem Server, vom Standard-Branch.
// - Fehlende Rechte (Token ohne „Contents: write“) melden Denied.
// - SameRepository: Der Remote origin (https, ssh oder git@host:owner/repo)
//   zeigt auf den Server und das Repository des Trackers.

interface

uses
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract;

type
  /// <summary>Stand auf dem Server vor dem Anlegen.</summary>
  TAtlasGitHubBranchFacts = record
    RepositoryId: string;
    IssueId: string;
    /// <summary>Basis mit Kopf: die gewünschte, sonst der Standard-Branch; '' ohne.</summary>
    BaseName: string;
    BaseOid: string;
    /// <summary>Den gewünschten Branch gibt es auf dem Server schon.</summary>
    Exists: Boolean;
    /// <summary>Verknüpfte Branches des Issues (Namen ohne refs/heads/).</summary>
    Linked: TArray<string>;
  end;

  TAtlasGitHubLinkedBranches = class
  public const
    /// <summary>Höchstens so viele verknüpfte Branches lesen.</summary>
    cMaxLinked = 20;
    cRefPrefix = 'refs/heads/';
    /// <summary>Branch anlegen und mit dem Issue verknüpfen.</summary>
    cLinkMutation = 'mutation($issue:ID!,$oid:GitObjectID!,$name:String!,$repository:ID!){createLinkedBranch(' +
      'input:{issueId:$issue,oid:$oid,name:$name,repositoryId:$repository}){linkedBranch{ref{name}}}}';
  public
    /// <summary>Abfrage des Stands für Issue ANumber (Variablen owner, name, base, branch als „refs/heads/…“).
    /// </summary>
    class function FactsQuery(ANumber: Integer): string; static;
    /// <summary>Nur die verknüpften Branches von Issue ANumber (Variablen owner, name).</summary>
    class function LinkedQuery(ANumber: Integer): string; static;
    /// <summary>Antwort auf FactsQuery bzw. LinkedQuery; False bei ungültigem JSON oder ohne Repository.</summary>
    class function ParseFacts(const AJson: string; out AFacts: TAtlasGitHubBranchFacts): Boolean; static;
    /// <summary>Was mit AFacts für ABranch geschieht: False mit ALink (Found, Exists, Failed), True = anlegen.
    /// </summary>
    class function Decide(const AFacts: TAtlasGitHubBranchFacts; const ABranch: string;
      out ALink: TAtlasTrackerBranchLink): Boolean; static;
    /// <summary>AOriginUrl zeigt auf Server und Repository ("owner/repo") von ATarget.</summary>
    class function SameRepository(const ATarget: TAtlasTrackerTarget; const AOriginUrl: string): Boolean; static;
    /// <summary>Verknüpften Branch finden oder ABranch von ABase anlegen (siehe Kopf der Unit).</summary>
    class function Link(const ACall: TAtlasTrackerCall; const ASend: IAtlasCiSend; const AKey, ABranch,
      ABase: string): TAtlasTrackerBranchLink; static;
    /// <summary>Verknüpfte Branches von AKey; False mit AError, wenn die Abfrage scheiterte.</summary>
    class function Linked(const ACall: TAtlasTrackerCall; const ASend: IAtlasCiSend; const AKey: string;
      out ANames: TArray<string>; out AError: TAtlasCiFetchError): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  Atlas.Core.Tracker.Internals.GitHubApi,
  Atlas.Core.Tracker.Internals.GitHubGraphQl,
  Atlas.Text.Json;

const
  cIssuePart = 'issue(number:%d){id linkedBranches(first:%d){nodes{ref{name}}}}';
  /// <summary>Stand vor dem Anlegen; %s = cIssuePart.</summary>
  cFactsQuery = 'query($owner:String!,$name:String!,$base:String!,$branch:String!){repository(owner:$owner,' +
    'name:$name){id defaultBranchRef{name target{oid}} base:ref(qualifiedName:$base){name target{oid}} ' +
    'existing:ref(qualifiedName:$branch){name} %s}}';
  /// <summary>Nur die verknüpften Branches; %s = cIssuePart.</summary>
  cLinkedQuery = 'query($owner:String!,$name:String!){repository(owner:$owner,name:$name){id %s}}';
  cGitSuffix = '.git';
  cApiPrefix = 'api.';

class function TAtlasGitHubLinkedBranches.FactsQuery(ANumber: Integer): string;
begin
  Result := Format(cFactsQuery, [Format(cIssuePart, [ANumber, cMaxLinked], TFormatSettings.Invariant)],
    TFormatSettings.Invariant);
end;

class function TAtlasGitHubLinkedBranches.LinkedQuery(ANumber: Integer): string;
begin
  Result := Format(cLinkedQuery, [Format(cIssuePart, [ANumber, cMaxLinked], TFormatSettings.Invariant)],
    TFormatSettings.Invariant);
end;

/// <summary>Name und Kopf eines Refs ("name", "target.oid"); False ohne.</summary>
function RefOf(ARef: TJSONObject; out AName, AOid: string): Boolean;
begin
  AName := '';
  AOid := '';
  if ARef = nil then
  begin
    Exit(False);
  end;
  AName := TJsonRead.Text(ARef, 'name');
  AOid := TJsonRead.Text(TJsonRead.Obj(ARef, 'target'), 'oid');
  Result := (AName <> '') and (AOid <> '');
end;

/// <summary>Namen der verknüpften Branches eines Issues.</summary>
function LinkedOf(AIssue: TJSONObject): TArray<string>;
var
  mNodes: TJSONArray;
  mNode: TJSONValue;
  mName: string;
begin
  Result := nil;
  mNodes := TAtlasGitHubGraphQl.NodesOf(AIssue, 'linkedBranches');
  if mNodes = nil then
  begin
    Exit;
  end;
  for mNode in mNodes do
  begin
    mName := TJsonRead.Text(TAtlasGitHubGraphQl.ObjectAt(mNode, ['ref']), 'name');
    if mName <> '' then
    begin
      Result := Result + [mName];
    end;
  end;
end;

class function TAtlasGitHubLinkedBranches.ParseFacts(const AJson: string;
  out AFacts: TAtlasGitHubBranchFacts): Boolean;
var
  mValue: TJSONValue;
  mRepository, mIssue: TJSONObject;
  mName, mOid: string;
begin
  AFacts := Default(TAtlasGitHubBranchFacts);
  AFacts.Linked := nil;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    mRepository := TAtlasGitHubGraphQl.ObjectAt(mValue, ['data', 'repository']);
    Result := mRepository <> nil;
    if not Result then
    begin
      Exit;
    end;
    AFacts.RepositoryId := TJsonRead.Text(mRepository, 'id');
    mIssue := TJsonRead.Obj(mRepository, 'issue');
    AFacts.IssueId := TJsonRead.Text(mIssue, 'id');
    AFacts.Linked := LinkedOf(mIssue);
    AFacts.Exists := TJsonRead.Obj(mRepository, 'existing') <> nil;
    if RefOf(TJsonRead.Obj(mRepository, 'base'), mName, mOid) or
      RefOf(TJsonRead.Obj(mRepository, 'defaultBranchRef'), mName, mOid) then
    begin
      AFacts.BaseName := mName;
      AFacts.BaseOid := mOid;
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasGitHubLinkedBranches.Decide(const AFacts: TAtlasGitHubBranchFacts; const ABranch: string;
  out ALink: TAtlasTrackerBranchLink): Boolean;
begin
  Result := False;
  if (AFacts.IssueId = '') or (AFacts.RepositoryId = '') then
  begin
    ALink := TAtlasTrackerBranchLink.Failure(TAtlasCiFetchError.NotFound, '');
  end
  else if Length(AFacts.Linked) > 0 then
  begin
    // Der gewünschte Name zuerst, sonst der erste verknüpfte.
    ALink := TAtlasTrackerBranchLink.Make(TAtlasTrackerBranchLinkOutcome.Found, AFacts.Linked[0]);
    if MatchText(ABranch, AFacts.Linked) then
    begin
      ALink.Branch := ABranch;
    end;
  end
  else if AFacts.Exists then
  begin
    ALink := TAtlasTrackerBranchLink.Make(TAtlasTrackerBranchLinkOutcome.Exists, ABranch);
  end
  else if AFacts.BaseOid = '' then
  begin
    ALink := TAtlasTrackerBranchLink.Failure(TAtlasCiFetchError.NotFound, '');
  end
  else
  begin
    ALink := TAtlasTrackerBranchLink.Make(TAtlasTrackerBranchLinkOutcome.Created, ABranch);
    ALink.Base := AFacts.BaseName;
    Result := True;
  end;
end;

/// <summary>Rechner ohne Schema und Port, ohne „api.“ und „www.“ (github.com).</summary>
function HostOf(const AServer: string): string;
var
  mAt: Integer;
begin
  Result := LowerCase(AServer);
  mAt := Pos('://', Result);
  if mAt > 0 then
  begin
    Result := Copy(Result, mAt + Length('://'), MaxInt);
  end;
  mAt := Pos(':', Result);
  if mAt > 0 then
  begin
    Result := Copy(Result, 1, mAt - 1);
  end;
  if StartsStr(cApiPrefix, Result) then
  begin
    Result := Copy(Result, Length(cApiPrefix) + 1, MaxInt);
  end;
  if StartsStr('www.', Result) then
  begin
    Result := Copy(Result, Length('www.') + 1, MaxInt);
  end;
end;

class function TAtlasGitHubLinkedBranches.SameRepository(const ATarget: TAtlasTrackerTarget;
  const AOriginUrl: string): Boolean;
var
  mUrl, mHost, mRest: string;
  mAt: Integer;
begin
  Result := False;
  mUrl := Trim(AOriginUrl);
  mHost := HostOf(ATarget.Server);
  mAt := Pos(mHost, LowerCase(mUrl));
  if (mHost = '') or (ATarget.Project = '') or (mAt = 0) then
  begin
    Exit;
  end;
  // Nach dem Rechner folgt "/" (https, ssh://, mit Port) bzw. ":" (git@host:owner/repo).
  mRest := Copy(mUrl, mAt + Length(mHost), MaxInt);
  while EndsStr('/', mRest) do
  begin
    Delete(mRest, Length(mRest), 1);
  end;
  if EndsText(cGitSuffix, mRest) then
  begin
    Delete(mRest, Length(mRest) - Length(cGitSuffix) + 1, Length(cGitSuffix));
  end;
  Result := EndsText('/' + ATarget.Project, mRest) or EndsText(':' + ATarget.Project, mRest);
end;

/// <summary>Owner und Name aus "owner/repo".</summary>
procedure SplitProject(const AProject: string; out AOwner, AName: string);
var
  mAt: Integer;
begin
  mAt := Pos('/', AProject);
  AOwner := Copy(AProject, 1, mAt - 1);
  AName := Copy(AProject, mAt + 1, MaxInt);
end;

class function TAtlasGitHubLinkedBranches.Link(const ACall: TAtlasTrackerCall; const ASend: IAtlasCiSend;
  const AKey, ABranch, ABase: string): TAtlasTrackerBranchLink;
var
  mOwner, mName, mUrl: string;
  mNumber: Integer;
  mReply: TAtlasGitHubGraphQlReply;
  mFacts: TAtlasGitHubBranchFacts;
begin
  mUrl := TAtlasGitHubGraphQl.Url(ACall.Target);
  mNumber := TAtlasGitHubApi.NumberOfKey(AKey);
  if (mUrl = '') or (mNumber = 0) or (ASend = nil) or (ABranch = '') then
  begin
    Exit(TAtlasTrackerBranchLink.Failure(TAtlasCiFetchError.NotConfigured, ''));
  end;
  SplitProject(ACall.Target.Project, mOwner, mName);
  if not TAtlasGitHubGraphQl.Query(ASend, mUrl, TAtlasGitHubGraphQl.Body(FactsQuery(mNumber), ['owner', mOwner,
    'name', mName, 'base', cRefPrefix + ABase, 'branch', cRefPrefix + ABranch]), ACall.TimeoutMs, mReply) then
  begin
    Exit(TAtlasTrackerBranchLink.Failure(mReply.Error, mReply.Message));
  end;
  if not ParseFacts(mReply.Text, mFacts) then
  begin
    Exit(TAtlasTrackerBranchLink.Failure(TAtlasCiFetchError.Invalid, ''));
  end;
  if not Decide(mFacts, ABranch, Result) then
  begin
    Exit;
  end;
  if not TAtlasGitHubGraphQl.Query(ASend, mUrl, TAtlasGitHubGraphQl.Body(cLinkMutation, ['issue', mFacts.IssueId,
    'oid', mFacts.BaseOid, 'name', ABranch, 'repository', mFacts.RepositoryId]), ACall.TimeoutMs, mReply) then
  begin
    Result := TAtlasTrackerBranchLink.Failure(mReply.Error, mReply.Message);
  end;
end;

class function TAtlasGitHubLinkedBranches.Linked(const ACall: TAtlasTrackerCall; const ASend: IAtlasCiSend;
  const AKey: string; out ANames: TArray<string>; out AError: TAtlasCiFetchError): Boolean;
var
  mOwner, mName, mUrl: string;
  mNumber: Integer;
  mReply: TAtlasGitHubGraphQlReply;
  mFacts: TAtlasGitHubBranchFacts;
begin
  ANames := nil;
  AError := TAtlasCiFetchError.NotConfigured;
  mUrl := TAtlasGitHubGraphQl.Url(ACall.Target);
  mNumber := TAtlasGitHubApi.NumberOfKey(AKey);
  Result := (mUrl <> '') and (mNumber > 0) and (ASend <> nil);
  if not Result then
  begin
    Exit;
  end;
  SplitProject(ACall.Target.Project, mOwner, mName);
  Result := TAtlasGitHubGraphQl.Query(ASend, mUrl, TAtlasGitHubGraphQl.Body(LinkedQuery(mNumber), ['owner', mOwner,
    'name', mName]), ACall.TimeoutMs, mReply) and ParseFacts(mReply.Text, mFacts);
  AError := mReply.Error;
  if Result then
  begin
    ANames := mFacts.Linked;
  end
  else if AError = TAtlasCiFetchError.None then
  begin
    AError := TAtlasCiFetchError.Invalid;
  end;
end;

end.
