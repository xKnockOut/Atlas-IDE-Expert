unit Atlas.Core.Tracker.NewIssuePlan.Tests;

// Tests von „Issue anlegen …“ ohne IDE (#1967): Auswahl und Beschriftung der Tracker, gleicher Tracker, Vorlagen
// der Arbeitskopie und Seiten im Browser.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasNewIssuePlanTests = class
  public
    [Test]
    procedure CaptionNamesProviderAndConnection;
    [Test]
    procedure ProjectTrackerFirst;
    [Test]
    procedure WithoutProjectTracker;
    [Test]
    procedure SameTrackerTemplatesAndPages;
  end;

implementation

uses
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.NewIssuePlan;

function Connection(const AName, AProvider, AUrl: string): TAtlasTrackerConnection;
begin
  Result := Default(TAtlasTrackerConnection);
  Result.Name := AName;
  Result.Provider := AProvider;
  Result.Url := AUrl;
  Result.Language := 'de';
end;

function Connections: TArray<TAtlasTrackerConnection>;
begin
  Result := TArray<TAtlasTrackerConnection>.Create(Connection('Firma', TAtlasTrackerTarget.cYouTrack,
    'https://yt.firma.local'), Connection('Privat', TAtlasTrackerTarget.cGitHub, 'https://github.com'));
end;

procedure TAtlasNewIssuePlanTests.CaptionNamesProviderAndConnection;
var
  mTarget: TAtlasTrackerTarget;
begin
  mTarget := TAtlasTrackerTarget.Create(TAtlasTrackerTarget.cGitHub, 'https://github.com', 'a/b', '');
  Assert.AreEqual('GitHub · ' + mTarget.Server, TAtlasNewIssuePlan.CaptionOf('', mTarget));
  Assert.AreEqual('Privat (GitHub · ' + mTarget.Server + ')', TAtlasNewIssuePlan.CaptionOf('Privat', mTarget));
  mTarget := TAtlasTrackerTarget.Create(TAtlasTrackerTarget.cYouTrack, 'https://yt.firma.local', 'ATL', '');
  Assert.AreEqual('YouTrack · ' + mTarget.Server, TAtlasNewIssuePlan.CaptionOf('', mTarget));
end;

procedure TAtlasNewIssuePlanTests.ProjectTrackerFirst;
var
  mChoices: TArray<TAtlasNewIssueChoice>;
  mIndex: Integer;
begin
  mChoices := TAtlasNewIssuePlan.Choices(TAtlasTrackerTarget.Create(TAtlasTrackerTarget.cYouTrack,
    'https://yt.firma.local', 'ATL', ''), 'Firma', Connections, mIndex);
  Assert.AreEqual(0, mIndex);
  Assert.AreEqual(2, Integer(Length(mChoices)), 'Firma nicht doppelt');
  Assert.AreEqual('ATL', mChoices[0].Target.Project);
  Assert.AreEqual('de', mChoices[0].Target.Language, 'Sprache aus der Verbindung');
  Assert.AreEqual(TAtlasTrackerTarget.cGitHub, mChoices[1].Target.Provider);
  Assert.AreEqual('', mChoices[1].Target.Project);
  Assert.AreEqual('de', mChoices[1].Target.Language);
  mChoices := nil;
end;

procedure TAtlasNewIssuePlanTests.WithoutProjectTracker;
var
  mChoices: TArray<TAtlasNewIssueChoice>;
  mIndex: Integer;
begin
  mChoices := TAtlasNewIssuePlan.Choices(Default(TAtlasTrackerTarget), '', Connections, mIndex);
  Assert.AreEqual(0, mIndex);
  Assert.AreEqual(2, Integer(Length(mChoices)));
  mChoices := TAtlasNewIssuePlan.Choices(Default(TAtlasTrackerTarget), '', nil, mIndex);
  Assert.AreEqual(-1, mIndex, 'keine Verbindung');
  Assert.AreEqual(0, Integer(Length(mChoices)));
  mChoices := TAtlasNewIssuePlan.ChoicesFor(TAtlasTrackerTarget.Create(TAtlasTrackerTarget.cGitHub,
    'https://github.com', 'a/b', ''), '', '', mIndex);
  Assert.AreEqual(1, Integer(Length(mChoices)), 'ohne issues.connections nur das Projekt');
  Assert.AreEqual(0, mIndex);
  mChoices := nil;
end;

procedure TAtlasNewIssuePlanTests.SameTrackerTemplatesAndPages;
var
  mGitHub, mOther: TAtlasTrackerTarget;
begin
  mGitHub := TAtlasTrackerTarget.Create(TAtlasTrackerTarget.cGitHub, 'https://github.com', 'a/b', '');
  mOther := TAtlasTrackerTarget.Create(TAtlasTrackerTarget.cGitHub, 'https://GitHub.com', 'A/B', '');
  Assert.IsTrue(TAtlasNewIssuePlan.SameTracker(mGitHub, mOther));
  mOther.Project := 'a/c';
  Assert.IsFalse(TAtlasNewIssuePlan.SameTracker(mGitHub, mOther));
  Assert.IsTrue(TAtlasNewIssuePlan.TemplatesPossible(True, True, mGitHub));
  Assert.IsFalse(TAtlasNewIssuePlan.TemplatesPossible(False, True, mGitHub), 'ohne Projekt');
  Assert.IsFalse(TAtlasNewIssuePlan.TemplatesPossible(True, False, mGitHub), 'abgeschaltet');
  Assert.IsFalse(TAtlasNewIssuePlan.TemplatesPossible(True, True, TAtlasTrackerTarget.Create(
    TAtlasTrackerTarget.cYouTrack, 'https://yt', 'ATL', '')), 'nur GitHub');
  Assert.IsTrue(TAtlasNewIssuePlan.Opens('HTTPS://github.com/a/b/issues/1'));
  Assert.IsFalse(TAtlasNewIssuePlan.Opens('file:///C:/Temp/issue.html'));
  Assert.IsFalse(TAtlasNewIssuePlan.Opens(''));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasNewIssuePlanTests);

end.
