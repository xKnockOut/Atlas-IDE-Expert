unit Atlas.Core.Tracker.Internals.GitHubPulls.Tests;

// Pull Request beim Beenden (#2136) gegen eine Fake-Transportschicht: schon
// offener Pull Request, Anlegen mit Labels, Meilenstein und Prüfer, Standard-
// Branch als Ziel, Ablehnung durch GitHub mit Fehlertext, dazu die JSON-Rümpfe
// und der Anbieter, der die Schnittstelle anbietet.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasGitHubPullsTests = class
  public
    [Test]
    procedure OpenUrlNamesOwnerAndBranch;
    [Test]
    procedure OpenPullIsExistingWithoutPost;
    [Test]
    procedure CreatesPullWithLabelsMilestoneAndReviewer;
    [Test]
    procedure WithoutBaseUsesDefaultBranch;
    [Test]
    procedure RejectionCarriesGitHubText;
    [Test]
    procedure FailedDecorationKeepsPull;
    [Test]
    procedure WithoutTitleIsNotConfigured;
    [Test]
    procedure CreateJsonCarriesDraft;
    [Test]
    procedure DecorateJsonWithoutLabelsAndMilestoneIsEmpty;
    [Test]
    procedure ReviewersJsonSkipsEmptyAndDuplicates;
    [Test]
    procedure RejectTextFallsBackToMessage;
    [Test]
    procedure ProviderOffersPullRequests;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Providers.GitHub,
  Atlas.Core.Tracker.Internals.GitHubPulls;

const
  cRepo = 'https://api.github.com/repos/beispiel/atlas';
  cOpenUrl = cRepo + '/pulls?state=open&head=beispiel%3Afeature/7-statusfeld';
  cBranch = 'feature/7-statusfeld';
  cCreated = '{"number":42,"html_url":"https://github.com/beispiel/atlas/pull/42","base":{"ref":"main"},' +
    '"draft":false}';
  cIssue = '{"number":7,"labels":[{"name":"bug"},{"name":"tracker"}],"milestone":{"number":3}}';

type
  /// <summary>Antworten je Methode und Adresse; merkt sich alle Anfragen als „METHODE Adresse“ und ihre Inhalte.
  /// </summary>
  TFakePullTransport = class(TInterfacedObject, IAtlasCiTransport, IAtlasCiSend)
  private
    FKeys: TArray<string>;
    FStatus: TArray<Integer>;
    FTexts: TArray<string>;
    function Find(const AKey: string; out AStatus: Integer; out AText: string): Boolean;
  public
    Calls: TArray<string>;
    Bodies: TArray<string>;
    procedure Answer(const AMethod, AUrl: string; AStatus: Integer; const AText: string);
    function Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
    function Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer; out AResponse: TAtlasCiResponse):
      Boolean;
  end;

procedure TFakePullTransport.Answer(const AMethod, AUrl: string; AStatus: Integer; const AText: string);
begin
  FKeys := FKeys + [AMethod + ' ' + AUrl];
  FStatus := FStatus + [AStatus];
  FTexts := FTexts + [AText];
end;

function TFakePullTransport.Find(const AKey: string; out AStatus: Integer; out AText: string): Boolean;
var
  mIndex: Integer;
begin
  AStatus := 404;
  AText := '';
  for mIndex := 0 to High(FKeys) do
  begin
    if FKeys[mIndex] = AKey then
    begin
      AStatus := FStatus[mIndex];
      AText := FTexts[mIndex];
      Exit(True);
    end;
  end;
  Result := False;
end;

function TFakePullTransport.Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
begin
  Calls := Calls + ['GET ' + AUrl];
  Bodies := Bodies + [''];
  AError := TAtlasCiFetchError.None;
  Find('GET ' + AUrl, AStatus, AText);
  Result := True;
end;

function TFakePullTransport.Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer;
  out AResponse: TAtlasCiResponse): Boolean;
begin
  Calls := Calls + [AMethod + ' ' + AUrl];
  Bodies := Bodies + [ABody];
  AResponse := TAtlasCiResponse.Failed(TAtlasCiFetchError.None);
  Find(AMethod + ' ' + AUrl, AResponse.Status, AResponse.Text);
  Result := True;
end;

function GitHubTarget: TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create('github', '', 'beispiel/atlas', '');
end;

function Spec(const ABase: string): TAtlasTrackerPullSpec;
begin
  Result := TAtlasTrackerPullSpec.None;
  Result.Wanted := True;
  Result.Head := cBranch;
  Result.Base := ABase;
  Result.Title := 'Statusfeld';
  Result.Body := 'Closes #7';
  Result.CopyIssue := True;
  Result.Reviewers := ['anna'];
end;

function CreatePull(ATransport: TFakePullTransport; const ASpec: TAtlasTrackerPullSpec): TAtlasTrackerPullResult;
var
  mTransport: IAtlasCiTransport;
begin
  mTransport := ATransport;
  Result := TAtlasGitHubPulls.Create(TAtlasTrackerCall.Create(GitHubTarget, mTransport, 5000), ATransport, '#7',
    ASpec);
end;

/// <summary>Index der Anfrage AKey in ATransport.Calls; -1 ohne.</summary>
function CallIndex(ATransport: TFakePullTransport; const AKey: string): Integer;
begin
  for Result := 0 to High(ATransport.Calls) do
  begin
    if ATransport.Calls[Result] = AKey then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;

/// <summary>Text unter AName im JSON-Objekt AJson; '' ohne.</summary>
function Field(const AJson, AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if (mValue is TJSONObject) and (TJSONObject(mValue).Values[AName] <> nil) then
    begin
      Result := TJSONObject(mValue).Values[AName].ToJSON;
    end;
  finally
    mValue.Free;
  end;
end;

{ TAtlasGitHubPullsTests }

procedure TAtlasGitHubPullsTests.OpenUrlNamesOwnerAndBranch;
begin
  Assert.AreEqual(cOpenUrl, TAtlasGitHubPulls.OpenUrl(GitHubTarget, ' ' + cBranch + ' '));
  Assert.AreEqual('', TAtlasGitHubPulls.OpenUrl(GitHubTarget, ''));
  Assert.AreEqual(cRepo, TAtlasGitHubPulls.RepositoryUrl(GitHubTarget));
end;

procedure TAtlasGitHubPullsTests.OpenPullIsExistingWithoutPost;
var
  mTransport: TFakePullTransport;
  mKeep: IAtlasCiTransport;
  mPull: TAtlasTrackerPullResult;
begin
  mTransport := TFakePullTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('GET', cOpenUrl, 200, '[' + cCreated + ']');
  mPull := CreatePull(mTransport, Spec('main'));
  Assert.AreEqual<TAtlasTrackerPullOutcome>(TAtlasTrackerPullOutcome.Existing, mPull.Outcome);
  Assert.AreEqual(42, mPull.Number);
  Assert.AreEqual('https://github.com/beispiel/atlas/pull/42', mPull.Url);
  Assert.IsTrue(mPull.Stands);
  Assert.AreEqual(1, Integer(Length(mTransport.Calls)), 'kein zweiter Pull Request');
end;

procedure TAtlasGitHubPullsTests.CreatesPullWithLabelsMilestoneAndReviewer;
var
  mTransport: TFakePullTransport;
  mKeep: IAtlasCiTransport;
  mPull: TAtlasTrackerPullResult;
  mIndex: Integer;
begin
  mTransport := TFakePullTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('GET', cOpenUrl, 200, '[]');
  mTransport.Answer('POST', cRepo + '/pulls', 201, cCreated);
  mTransport.Answer('GET', cRepo + '/issues/7', 200, cIssue);
  mTransport.Answer('PATCH', cRepo + '/issues/42', 200, '{}');
  mTransport.Answer('POST', cRepo + '/pulls/42/requested_reviewers', 201, '{}');
  mPull := CreatePull(mTransport, Spec('main'));
  Assert.AreEqual<TAtlasTrackerPullOutcome>(TAtlasTrackerPullOutcome.Created, mPull.Outcome);
  Assert.AreEqual(42, mPull.Number);
  Assert.AreEqual('main', mPull.Base);
  Assert.IsFalse(mPull.DecorateFailed);
  Assert.IsFalse(mPull.ReviewersFailed);
  mIndex := CallIndex(mTransport, 'POST ' + cRepo + '/pulls');
  Assert.IsTrue(mIndex > 0);
  Assert.AreEqual('"' + cBranch + '"', Field(mTransport.Bodies[mIndex], 'head'));
  Assert.AreEqual('"main"', Field(mTransport.Bodies[mIndex], 'base'));
  Assert.AreEqual('"Statusfeld"', Field(mTransport.Bodies[mIndex], 'title'));
  mIndex := CallIndex(mTransport, 'PATCH ' + cRepo + '/issues/42');
  Assert.IsTrue(mIndex > 0);
  Assert.AreEqual('["bug","tracker"]', Field(mTransport.Bodies[mIndex], 'labels'));
  Assert.AreEqual('3', Field(mTransport.Bodies[mIndex], 'milestone'));
  mIndex := CallIndex(mTransport, 'POST ' + cRepo + '/pulls/42/requested_reviewers');
  Assert.IsTrue(mIndex > 0);
  Assert.AreEqual('["anna"]', Field(mTransport.Bodies[mIndex], 'reviewers'));
end;

procedure TAtlasGitHubPullsTests.WithoutBaseUsesDefaultBranch;
var
  mTransport: TFakePullTransport;
  mKeep: IAtlasCiTransport;
  mPull: TAtlasTrackerPullResult;
  mSpec: TAtlasTrackerPullSpec;
  mIndex: Integer;
begin
  mTransport := TFakePullTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('GET', cOpenUrl, 200, '[]');
  mTransport.Answer('GET', cRepo, 200, '{"default_branch":"develop"}');
  mTransport.Answer('POST', cRepo + '/pulls', 201, '{"number":43,"html_url":"u"}');
  mSpec := Spec('');
  mSpec.CopyIssue := False;
  mSpec.Reviewers := nil;
  mPull := CreatePull(mTransport, mSpec);
  Assert.AreEqual<TAtlasTrackerPullOutcome>(TAtlasTrackerPullOutcome.Created, mPull.Outcome);
  Assert.AreEqual('develop', mPull.Base);
  mIndex := CallIndex(mTransport, 'POST ' + cRepo + '/pulls');
  Assert.AreEqual('"develop"', Field(mTransport.Bodies[mIndex], 'base'));
  Assert.AreEqual(-1, CallIndex(mTransport, 'GET ' + cRepo + '/issues/7'), 'ohne Labels kein Abruf des Issues');
end;

procedure TAtlasGitHubPullsTests.RejectionCarriesGitHubText;
var
  mTransport: TFakePullTransport;
  mKeep: IAtlasCiTransport;
  mPull: TAtlasTrackerPullResult;
begin
  mTransport := TFakePullTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('GET', cOpenUrl, 200, '[]');
  mTransport.Answer('POST', cRepo + '/pulls', 422,
    '{"message":"Validation Failed","errors":[{"message":"No commits between main and feature/7-statusfeld"}]}');
  mPull := CreatePull(mTransport, Spec('main'));
  Assert.AreEqual<TAtlasTrackerPullOutcome>(TAtlasTrackerPullOutcome.Failed, mPull.Outcome);
  Assert.AreEqual<TAtlasCiFetchError>(TAtlasCiFetchError.Invalid, mPull.Error);
  Assert.AreEqual(422, mPull.Status);
  Assert.AreEqual('No commits between main and feature/7-statusfeld', mPull.Message);
  Assert.IsFalse(mPull.Stands);
end;

procedure TAtlasGitHubPullsTests.FailedDecorationKeepsPull;
var
  mTransport: TFakePullTransport;
  mKeep: IAtlasCiTransport;
  mPull: TAtlasTrackerPullResult;
begin
  mTransport := TFakePullTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('GET', cOpenUrl, 200, '[]');
  mTransport.Answer('POST', cRepo + '/pulls', 201, cCreated);
  mTransport.Answer('GET', cRepo + '/issues/7', 200, cIssue);
  mTransport.Answer('PATCH', cRepo + '/issues/42', 403, '{"message":"Forbidden"}');
  mTransport.Answer('POST', cRepo + '/pulls/42/requested_reviewers', 422, '{"message":"not a collaborator"}');
  mPull := CreatePull(mTransport, Spec('main'));
  Assert.AreEqual<TAtlasTrackerPullOutcome>(TAtlasTrackerPullOutcome.Created, mPull.Outcome);
  Assert.IsTrue(mPull.DecorateFailed);
  Assert.IsTrue(mPull.ReviewersFailed);
  Assert.AreEqual(42, mPull.Number);
end;

procedure TAtlasGitHubPullsTests.WithoutTitleIsNotConfigured;
var
  mTransport: TFakePullTransport;
  mKeep: IAtlasCiTransport;
  mSpec: TAtlasTrackerPullSpec;
  mPull: TAtlasTrackerPullResult;
begin
  mTransport := TFakePullTransport.Create;
  mKeep := mTransport;
  mSpec := Spec('main');
  mSpec.Title := ' ';
  mPull := CreatePull(mTransport, mSpec);
  Assert.AreEqual<TAtlasTrackerPullOutcome>(TAtlasTrackerPullOutcome.Failed, mPull.Outcome);
  Assert.AreEqual<TAtlasCiFetchError>(TAtlasCiFetchError.NotConfigured, mPull.Error);
  Assert.AreEqual(0, Integer(Length(mTransport.Calls)));
end;

procedure TAtlasGitHubPullsTests.CreateJsonCarriesDraft;
var
  mSpec: TAtlasTrackerPullSpec;
  mJson: string;
begin
  mSpec := Spec('main');
  mSpec.Draft := True;
  mJson := TAtlasGitHubPulls.CreateJson(mSpec, 'develop');
  Assert.AreEqual('true', Field(mJson, 'draft'));
  Assert.AreEqual('"develop"', Field(mJson, 'base'));
  Assert.AreEqual('"Closes #7"', Field(mJson, 'body'));
end;

procedure TAtlasGitHubPullsTests.DecorateJsonWithoutLabelsAndMilestoneIsEmpty;
begin
  Assert.AreEqual('', TAtlasGitHubPulls.DecorateJson('{"number":7,"labels":[],"milestone":null}'));
  Assert.AreEqual('', TAtlasGitHubPulls.DecorateJson('kein JSON'));
  Assert.AreEqual('3', Field(TAtlasGitHubPulls.DecorateJson('{"milestone":{"number":3}}'), 'milestone'));
end;

procedure TAtlasGitHubPullsTests.ReviewersJsonSkipsEmptyAndDuplicates;
begin
  Assert.AreEqual('', TAtlasGitHubPulls.ReviewersJson(['', ' ']));
  Assert.AreEqual('["anna","ben"]', Field(TAtlasGitHubPulls.ReviewersJson(['Anna', ' ', 'anna', 'ben']),
    'reviewers'));
end;

procedure TAtlasGitHubPullsTests.RejectTextFallsBackToMessage;
begin
  Assert.AreEqual('Resource not accessible by integration',
    TAtlasGitHubPulls.RejectText('{"message":"Resource not accessible by integration"}'));
  Assert.AreEqual('', TAtlasGitHubPulls.RejectText(''));
end;

procedure TAtlasGitHubPullsTests.ProviderOffersPullRequests;
var
  mProvider: IAtlasTrackerProvider;
begin
  mProvider := TAtlasGitHubTracker.Create;
  Assert.IsTrue(Supports(mProvider, IAtlasTrackerPullRequests));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasGitHubPullsTests);

end.
