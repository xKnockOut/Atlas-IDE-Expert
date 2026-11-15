unit Atlas.Core.Projects.VcsQueries.Tests;

// Tests für die Buchführung der Abfragen der Versionsverwaltung (#571, #1967): höchstens eine Abfrage je
// Projekt, Zeitlimit, nur die eigene Abfrage endet, Frische nach cVcsRefreshMs, Vergessen nach Pull und der
// Stand der letzten gelungenen Abfrage.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Projects.VcsQueries;

type
  [TestFixture]
  TAtlasProjectVcsQueriesTests = class
  private
    FQueries: TAtlasProjectVcsQueries;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure OneQueryPerProject;
    [Test]
    procedure QueryEndsAfterLimit;
    [Test]
    procedure OnlyOwnQueryEndsItsEntry;
    [Test]
    procedure FreshForRefreshInterval;
    [Test]
    procedure NotStartedCountsAsFresh;
    [Test]
    procedure ForgetMakesStale;
    [Test]
    procedure LiveKeepsLastSuccessfulState;
  end;

implementation

uses
  Atlas.Core.Projects.Summary,
  Atlas.Core.Projects.Recording;

const
  cProject = 'C:\Projekte\App\App.dproj';
  cSameProject = ' c:/projekte/app/APP.dproj ';
  cOther = 'C:\Projekte\Lib\Lib.dproj';
  cStart = 10000;

function VcsOnBranch(const ABranch: string): TAtlasProjectVcs;
begin
  Result := TAtlasProjectVcs.Empty;
  Result.Known := True;
  Result.Kind := 'git';
  Result.Branch := ABranch;
end;

{ TAtlasProjectVcsQueriesTests }

procedure TAtlasProjectVcsQueriesTests.Setup;
begin
  FQueries := TAtlasProjectVcsQueries.Create;
end;

procedure TAtlasProjectVcsQueriesTests.TearDown;
begin
  FQueries.Free;
  FQueries := nil;
end;

procedure TAtlasProjectVcsQueriesTests.OneQueryPerProject;
var
  mKey, mOtherKey: string;
  mStarted, mOtherStarted: UInt64;
begin
  Assert.IsTrue(FQueries.TryStart(cProject, cStart, mKey, mStarted));
  Assert.AreEqual(TAtlasProjectVcsQueries.KeyOf(cProject), mKey);
  Assert.AreEqual(Int64(cStart), Int64(mStarted), 'Start ist die genannte Zeit');
  Assert.IsTrue(FQueries.Querying(cSameProject, cStart + 1), 'derselbe Pfad anders geschrieben');
  Assert.IsFalse(FQueries.TryStart(cSameProject, cStart + 1, mOtherKey, mOtherStarted), 'läuft schon');
  Assert.IsTrue(FQueries.TryStart(cOther, cStart + 1, mOtherKey, mOtherStarted), 'anderes Projekt');
  FQueries.Finish(mKey, mStarted, cStart + 2, False, TAtlasProjectVcs.Empty);
  Assert.IsFalse(FQueries.Querying(cProject, cStart + 3));
  Assert.IsTrue(FQueries.Querying(cOther, cStart + 3));
end;

procedure TAtlasProjectVcsQueriesTests.QueryEndsAfterLimit;
var
  mKey: string;
  mStarted: UInt64;
begin
  FQueries.TryStart(cProject, cStart, mKey, mStarted);
  Assert.IsTrue(FQueries.Querying(cProject, cStart + TAtlasProjectRecording.cVcsQueryLimitMs - 1));
  Assert.IsFalse(FQueries.Querying(cProject, cStart + TAtlasProjectRecording.cVcsQueryLimitMs), 'Zeitlimit');
  Assert.IsTrue(FQueries.TryStart(cProject, cStart + TAtlasProjectRecording.cVcsQueryLimitMs, mKey, mStarted),
    'neue Abfrage nach dem Zeitlimit');
end;

procedure TAtlasProjectVcsQueriesTests.OnlyOwnQueryEndsItsEntry;
var
  mKey: string;
  mFirst, mSecond: UInt64;
  mLater: UInt64;
begin
  FQueries.TryStart(cProject, cStart, mKey, mFirst);
  mLater := cStart + TAtlasProjectRecording.cVcsQueryLimitMs;
  FQueries.TryStart(cProject, mLater, mKey, mSecond);
  // Die erste Abfrage kommt spät doch noch zurück: Die zweite läuft weiter.
  FQueries.Finish(mKey, mFirst, mLater + 1, False, TAtlasProjectVcs.Empty);
  Assert.IsTrue(FQueries.Querying(cProject, mLater + 2));
  FQueries.Finish(mKey, mSecond, mLater + 3, False, TAtlasProjectVcs.Empty);
  Assert.IsFalse(FQueries.Querying(cProject, mLater + 4));
end;

procedure TAtlasProjectVcsQueriesTests.FreshForRefreshInterval;
var
  mKey: string;
  mStarted: UInt64;
begin
  Assert.IsTrue(FQueries.IsStale(cProject, cStart), 'nie abgefragt');
  FQueries.TryStart(cProject, cStart, mKey, mStarted);
  Assert.IsTrue(FQueries.IsStale(cProject, cStart + 1), 'läuft noch: nicht frisch');
  FQueries.Finish(mKey, mStarted, cStart + 100, True, VcsOnBranch('main'));
  Assert.IsFalse(FQueries.IsStale(cSameProject, cStart + 100 + TAtlasProjectRecording.cVcsRefreshMs - 1));
  Assert.IsTrue(FQueries.IsStale(cProject, cStart + 100 + TAtlasProjectRecording.cVcsRefreshMs));
end;

procedure TAtlasProjectVcsQueriesTests.NotStartedCountsAsFresh;
var
  mKey: string;
  mStarted: UInt64;
begin
  FQueries.TryStart(cProject, cStart, mKey, mStarted);
  FQueries.NotStarted(mKey, cStart);
  Assert.IsFalse(FQueries.Querying(cProject, cStart), 'kein „wird abgefragt …“');
  Assert.IsFalse(FQueries.IsStale(cProject, cStart + 1), 'nicht bei jedem Zeichnen neu versuchen');
end;

procedure TAtlasProjectVcsQueriesTests.ForgetMakesStale;
var
  mKey: string;
  mStarted: UInt64;
begin
  FQueries.TryStart(cProject, cStart, mKey, mStarted);
  FQueries.Finish(mKey, mStarted, cStart, True, VcsOnBranch('main'));
  FQueries.Forget(cSameProject);
  Assert.IsTrue(FQueries.IsStale(cProject, cStart + 1));
end;

procedure TAtlasProjectVcsQueriesTests.LiveKeepsLastSuccessfulState;
var
  mKey: string;
  mStarted: UInt64;
  mVcs: TAtlasProjectVcs;
begin
  Assert.IsFalse(FQueries.Live(cProject, mVcs));
  Assert.IsFalse(mVcs.Known);
  Assert.AreEqual(-1, mVcs.Changed, 'ohne Stand Empty, nicht Default');
  FQueries.TryStart(cProject, cStart, mKey, mStarted);
  FQueries.Finish(mKey, mStarted, cStart, True, VcsOnBranch('main'));
  FQueries.TryStart(cProject, cStart + 1, mKey, mStarted);
  FQueries.Finish(mKey, mStarted, cStart + 2, False, VcsOnBranch('kaputt'));
  Assert.IsTrue(FQueries.Live(cSameProject, mVcs));
  Assert.AreEqual('main', mVcs.Branch, 'gescheiterte Abfrage ändert den Stand nicht');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasProjectVcsQueriesTests);

end.
