unit Atlas.Core.Tracker.Internals.GitHubLinkedBranches.Tests;

// Verknüpfte Branches eines GitHub-Issues (#2138) gegen eine Fake-
// Transportschicht: Rumpf der Abfrage, Anlegen vom Kopf der Basis bzw. des
// Standard-Branchs, schon verknüpfter Branch, vorhandener Branch, fehlende
// Rechte, Lesen für den Reiter „Entwicklung“ und der Vergleich von origin mit
// dem Repository des Trackers. GraphQL-Rümpfe werden als Text verglichen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasGitHubLinkedBranchesTests = class
  public
    [Test]
    procedure FactsQueryNamesBranchBaseAndIssue;
    [Test]
    procedure CreatesBranchFromHeadOfBase;
    [Test]
    procedure WithoutBaseUsesDefaultBranch;
    [Test]
    procedure AlreadyLinkedBranchIsFound;
    [Test]
    procedure ExistingBranchIsNotLinked;
    [Test]
    procedure MissingRightsAreDenied;
    [Test]
    procedure LinkedReadsBranchNames;
    [Test]
    procedure SameRepositoryForHttpsSshAndScp;
    [Test]
    procedure OtherRepositoryOrServerIsForeign;
    [Test]
    procedure ProviderOffersBranchLinker;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Providers.GitHub,
  Atlas.Core.Tracker.Internals.GitHubLinkedBranches;

const
  cGraphQlUrl = 'https://api.github.com/graphql';
  cBranch = 'feature/7-statusfeld';
  cHead = '{"name":"main","target":{"oid":"abc123"}}';
  cDefault = '{"name":"develop","target":{"oid":"def456"}}';
  cLinkOk = '{"data":{"createLinkedBranch":{"linkedBranch":{"ref":{"name":"feature/7-statusfeld"}}}}}';
  cForbidden = '{"data":null,"errors":[{"type":"FORBIDDEN","message":"Resource not accessible by integration"}]}';

type
  /// <summary>Antworten nach Textstück im Inhalt; merkt sich alle Inhalte.</summary>
  TFakeLinkTransport = class(TInterfacedObject, IAtlasCiTransport, IAtlasCiSend)
  private
    FParts: TArray<string>;
    FTexts: TArray<string>;
  public
    Bodies: TArray<string>;
    procedure Answer(const APart, AText: string);
    function Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
    function Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer; out AResponse: TAtlasCiResponse):
      Boolean;
  end;

procedure TFakeLinkTransport.Answer(const APart, AText: string);
begin
  FParts := FParts + [APart];
  FTexts := FTexts + [AText];
end;

function TFakeLinkTransport.Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
begin
  AStatus := 404;
  AText := '';
  AError := TAtlasCiFetchError.None;
  Result := True;
end;

function TFakeLinkTransport.Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer;
  out AResponse: TAtlasCiResponse): Boolean;
var
  mIndex: Integer;
begin
  Bodies := Bodies + [ABody];
  AResponse := TAtlasCiResponse.Failed(TAtlasCiFetchError.None);
  AResponse.Status := 404;
  AResponse.Text := '';
  Result := True;
  if AUrl <> cGraphQlUrl then
  begin
    Exit;
  end;
  for mIndex := 0 to High(FParts) do
  begin
    if Pos(FParts[mIndex], ABody) > 0 then
    begin
      AResponse.Status := 200;
      AResponse.Text := FTexts[mIndex];
      Exit;
    end;
  end;
end;

function GitHubTarget: TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create('github', '', 'beispiel/atlas', '');
end;

/// <summary>Antwort auf die Abfrage des Stands mit Basis ABase, verknüpften ALinked und vorhandenem AExisting
/// (JSON-Teile, 'null' = fehlt).</summary>
function FactsJson(const ABase, ALinked, AExisting: string): string;
begin
  Result := '{"data":{"repository":{"id":"R_1","defaultBranchRef":' + cDefault + ',"base":' + ABase +
    ',"existing":' + AExisting + ',"issue":{"id":"I_7","linkedBranches":{"nodes":[' + ALinked + ']}}}}}';
end;

/// <summary>Wert unter "variables"/AName im Inhalt ABody; '' ohne.</summary>
function Variable(const ABody, AName: string): string;
var
  mValue: TJSONValue;
  mVariables: TJSONValue;
begin
  Result := '';
  mValue := TJSONObject.ParseJSONValue(ABody);
  try
    if mValue is TJSONObject then
    begin
      mVariables := TJSONObject(mValue).Values['variables'];
      if (mVariables is TJSONObject) and (TJSONObject(mVariables).Values[AName] <> nil) then
      begin
        Result := TJSONObject(mVariables).Values[AName].Value;
      end;
    end;
  finally
    mValue.Free;
  end;
end;

function Link(ATransport: TFakeLinkTransport; const ABase: string): TAtlasTrackerBranchLink;
var
  mTransport: IAtlasCiTransport;
begin
  mTransport := ATransport;
  Result := TAtlasGitHubLinkedBranches.Link(TAtlasTrackerCall.Create(GitHubTarget, mTransport, 5000),
    ATransport, '#7', cBranch, ABase);
end;

{ TAtlasGitHubLinkedBranchesTests }

procedure TAtlasGitHubLinkedBranchesTests.FactsQueryNamesBranchBaseAndIssue;
var
  mTransport: TFakeLinkTransport;
  mKeep: IAtlasCiTransport;
begin
  mTransport := TFakeLinkTransport.Create;
  mKeep := mTransport;
  Link(mTransport, 'main');
  Assert.AreEqual(1, Integer(Length(mTransport.Bodies)));
  Assert.IsTrue(Pos('issue(number:7)', mTransport.Bodies[0]) > 0, mTransport.Bodies[0]);
  Assert.IsTrue(Pos('linkedBranches(first:20)', mTransport.Bodies[0]) > 0, mTransport.Bodies[0]);
  Assert.AreEqual('beispiel', Variable(mTransport.Bodies[0], 'owner'));
  Assert.AreEqual('atlas', Variable(mTransport.Bodies[0], 'name'));
  Assert.AreEqual('refs/heads/main', Variable(mTransport.Bodies[0], 'base'));
  Assert.AreEqual('refs/heads/' + cBranch, Variable(mTransport.Bodies[0], 'branch'));
end;

procedure TAtlasGitHubLinkedBranchesTests.CreatesBranchFromHeadOfBase;
var
  mTransport: TFakeLinkTransport;
  mKeep: IAtlasCiTransport;
  mLink: TAtlasTrackerBranchLink;
begin
  mTransport := TFakeLinkTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('createLinkedBranch', cLinkOk);
  mTransport.Answer('repository(owner', FactsJson(cHead, '', 'null'));
  mLink := Link(mTransport, 'main');
  Assert.IsTrue(mLink.Outcome = TAtlasTrackerBranchLinkOutcome.Created);
  Assert.AreEqual(cBranch, mLink.Branch);
  Assert.AreEqual('main', mLink.Base);
  Assert.AreEqual(2, Integer(Length(mTransport.Bodies)));
  Assert.AreEqual('I_7', Variable(mTransport.Bodies[1], 'issue'));
  Assert.AreEqual('abc123', Variable(mTransport.Bodies[1], 'oid'));
  Assert.AreEqual(cBranch, Variable(mTransport.Bodies[1], 'name'));
  Assert.AreEqual('R_1', Variable(mTransport.Bodies[1], 'repository'));
end;

procedure TAtlasGitHubLinkedBranchesTests.WithoutBaseUsesDefaultBranch;
var
  mTransport: TFakeLinkTransport;
  mKeep: IAtlasCiTransport;
  mLink: TAtlasTrackerBranchLink;
begin
  mTransport := TFakeLinkTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('createLinkedBranch', cLinkOk);
  mTransport.Answer('repository(owner', FactsJson('null', '', 'null'));
  mLink := Link(mTransport, 'main-merging');
  Assert.IsTrue(mLink.Outcome = TAtlasTrackerBranchLinkOutcome.Created);
  Assert.AreEqual('develop', mLink.Base);
  Assert.AreEqual('def456', Variable(mTransport.Bodies[1], 'oid'));
end;

procedure TAtlasGitHubLinkedBranchesTests.AlreadyLinkedBranchIsFound;
var
  mTransport: TFakeLinkTransport;
  mKeep: IAtlasCiTransport;
  mLink: TAtlasTrackerBranchLink;
begin
  mTransport := TFakeLinkTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('repository(owner', FactsJson(cHead, '{"ref":{"name":"7-anderer-name"}}', 'null'));
  mLink := Link(mTransport, 'main');
  Assert.IsTrue(mLink.Outcome = TAtlasTrackerBranchLinkOutcome.Found);
  Assert.AreEqual('7-anderer-name', mLink.Branch);
  Assert.IsTrue(mLink.OnServer);
  Assert.AreEqual(1, Integer(Length(mTransport.Bodies)), 'nichts angelegt');
end;

procedure TAtlasGitHubLinkedBranchesTests.ExistingBranchIsNotLinked;
var
  mTransport: TFakeLinkTransport;
  mKeep: IAtlasCiTransport;
  mLink: TAtlasTrackerBranchLink;
begin
  mTransport := TFakeLinkTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('repository(owner', FactsJson(cHead, '', '{"name":"' + cBranch + '"}'));
  mLink := Link(mTransport, 'main');
  Assert.IsTrue(mLink.Outcome = TAtlasTrackerBranchLinkOutcome.Exists);
  Assert.IsFalse(mLink.OnServer);
  Assert.AreEqual(1, Integer(Length(mTransport.Bodies)), 'nichts angelegt');
end;

procedure TAtlasGitHubLinkedBranchesTests.MissingRightsAreDenied;
var
  mTransport: TFakeLinkTransport;
  mKeep: IAtlasCiTransport;
  mLink: TAtlasTrackerBranchLink;
begin
  mTransport := TFakeLinkTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('createLinkedBranch', cForbidden);
  mTransport.Answer('repository(owner', FactsJson(cHead, '', 'null'));
  mLink := Link(mTransport, 'main');
  Assert.IsTrue(mLink.Outcome = TAtlasTrackerBranchLinkOutcome.Denied);
  Assert.IsTrue(mLink.Error = TAtlasCiFetchError.Unauthorized);
  Assert.AreEqual('Resource not accessible by integration', mLink.Message);
end;

procedure TAtlasGitHubLinkedBranchesTests.LinkedReadsBranchNames;
var
  mTransport: TFakeLinkTransport;
  mKeep: IAtlasCiTransport;
  mNames: TArray<string>;
  mError: TAtlasCiFetchError;
begin
  mTransport := TFakeLinkTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('linkedBranches', '{"data":{"repository":{"id":"R_1","issue":{"id":"I_7","linkedBranches":' +
    '{"nodes":[{"ref":{"name":"7-a"}},{"ref":null},{"ref":{"name":"feature/7-b"}}]}}}}}');
  Assert.IsTrue(TAtlasGitHubLinkedBranches.Linked(TAtlasTrackerCall.Create(GitHubTarget, mKeep, 5000), mTransport,
    '#7', mNames, mError));
  Assert.AreEqual('7-a|feature/7-b', string.Join('|', mNames));
  Assert.IsTrue(Pos('existing', mTransport.Bodies[0]) = 0, 'nur die verknüpften Branches');
end;

procedure TAtlasGitHubLinkedBranchesTests.SameRepositoryForHttpsSshAndScp;
begin
  Assert.IsTrue(TAtlasGitHubLinkedBranches.SameRepository(GitHubTarget, 'https://github.com/beispiel/atlas.git'));
  Assert.IsTrue(TAtlasGitHubLinkedBranches.SameRepository(GitHubTarget, 'https://github.com/Beispiel/Atlas/'));
  Assert.IsTrue(TAtlasGitHubLinkedBranches.SameRepository(GitHubTarget, 'git@github.com:beispiel/atlas.git'));
  Assert.IsTrue(TAtlasGitHubLinkedBranches.SameRepository(GitHubTarget, 'ssh://git@github.com/beispiel/atlas'));
  Assert.IsTrue(TAtlasGitHubLinkedBranches.SameRepository(
    TAtlasTrackerTarget.Create('github', 'https://git.firma.local', 'team/kasse', ''),
    'https://git.firma.local:8443/team/kasse.git'));
end;

procedure TAtlasGitHubLinkedBranchesTests.OtherRepositoryOrServerIsForeign;
begin
  Assert.IsFalse(TAtlasGitHubLinkedBranches.SameRepository(GitHubTarget, 'https://github.com/beispiel/atlas-docs'));
  Assert.IsFalse(TAtlasGitHubLinkedBranches.SameRepository(GitHubTarget, 'https://github.com/fork/atlas.git'));
  Assert.IsFalse(TAtlasGitHubLinkedBranches.SameRepository(GitHubTarget, 'https://gitlab.com/beispiel/atlas.git'));
  Assert.IsFalse(TAtlasGitHubLinkedBranches.SameRepository(GitHubTarget, ''));
end;

procedure TAtlasGitHubLinkedBranchesTests.ProviderOffersBranchLinker;
var
  mProvider: IAtlasTrackerProvider;
  mLinker: IAtlasTrackerBranchLinker;
begin
  mProvider := TAtlasGitHubTracker.Create;
  Assert.IsTrue(Supports(mProvider, IAtlasTrackerBranchLinker, mLinker));
  Assert.IsTrue(mLinker.SameRepository(GitHubTarget, 'git@github.com:beispiel/atlas.git'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasGitHubLinkedBranchesTests);

end.
