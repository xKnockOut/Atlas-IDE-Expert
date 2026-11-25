unit Atlas.Plugin.Projects.Contract.Summary.Tests;

// Datentypen der Projekt-Zusammenfassung im Vertrag: leere Abschnitte, Name des Projekts, Reihen des Verlaufs,
// Einrichtung, Testlauf, Release-Versionen und Build-Server, ohne Datei und ohne Windows.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasProjectContractSummaryTests = class
  public
    [Test]
    procedure CreateFillsEmptySections;
    [Test]
    procedure NameDropsFolderAndExtension;
    [Test]
    procedure WorkingCopyNeedsKnownGitOrSvn;
    [Test]
    procedure TrendPointSetsAndClearsSeries;
    [Test]
    procedure PathsCleanAllowsUncertainFindings;
    [Test]
    procedure FailedTestsWithoutDoublesAndTotal;
    [Test]
    procedure ReleaseRemembersNewestFirst;
    [Test]
    procedure CiMatchesJobAndKnowsBuild;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Plugin.CiBuild.Contract,
  Atlas.Plugin.Projects.Contract.Summary;

{ TAtlasProjectContractSummaryTests }

procedure TAtlasProjectContractSummaryTests.CreateFillsEmptySections;
var
  mSummary: TAtlasProjectSummary;
begin
  mSummary := TAtlasProjectSummary.Create('C:\Projekte\Kasse.dproj');
  Assert.AreEqual('C:\Projekte\Kasse.dproj', mSummary.Project);
  Assert.AreEqual(-1, mSummary.Vcs.Changed);
  Assert.AreEqual(-1, mSummary.Vcs.Behind);
  Assert.IsFalse(mSummary.Build.Known);
  Assert.IsFalse(mSummary.Ci.HasBuild);
  Assert.AreEqual(0, Integer(Length(mSummary.Trends.Points)));
end;

procedure TAtlasProjectContractSummaryTests.NameDropsFolderAndExtension;
var
  mSummary: TAtlasProjectSummary;
begin
  mSummary := TAtlasProjectSummary.Create('D:/Quellen/Lager.Verwaltung.dproj');
  Assert.AreEqual('Lager.Verwaltung', mSummary.Name);
  mSummary.Project := 'Ohne';
  Assert.AreEqual('Ohne', mSummary.Name);
end;

procedure TAtlasProjectContractSummaryTests.WorkingCopyNeedsKnownGitOrSvn;
var
  mVcs: TAtlasProjectVcs;
begin
  mVcs := TAtlasProjectVcs.Empty;
  mVcs.Kind := 'git';
  Assert.IsFalse(mVcs.InWorkingCopy);
  mVcs.Known := True;
  Assert.IsTrue(mVcs.InWorkingCopy);
  mVcs.Kind := 'none';
  Assert.IsFalse(mVcs.InWorkingCopy);
end;

procedure TAtlasProjectContractSummaryTests.TrendPointSetsAndClearsSeries;
var
  mPoint: TAtlasTrendPoint;
begin
  mPoint := TAtlasTrendPoint.Create(EncodeDate(2026, 11, 19), 7);
  Assert.AreEqual(7, mPoint.Build);
  mPoint.SetValue(TAtlasTrendSeries.Duration, 125);
  Assert.IsTrue(mPoint.Has[TAtlasTrendSeries.Duration]);
  Assert.AreEqual(125, mPoint.Values[TAtlasTrendSeries.Duration]);
  mPoint.Clear(TAtlasTrendSeries.Duration);
  Assert.IsFalse(mPoint.Has[TAtlasTrendSeries.Duration]);
  Assert.AreEqual(0, mPoint.Values[TAtlasTrendSeries.Duration]);
end;

procedure TAtlasProjectContractSummaryTests.PathsCleanAllowsUncertainFindings;
var
  mSetup: TAtlasProjectSetup;
begin
  mSetup := TAtlasProjectSetup.Empty;
  Assert.IsFalse(mSetup.PathsClean, 'ungeprüft');
  mSetup.Checked := True;
  mSetup.MissingUnitCount := 2;
  mSetup.UncertainUnitCount := 2;
  Assert.IsTrue(mSetup.PathsClean, 'nur unsichere Funde');
  mSetup.UndefinedDefineCount := 1;
  Assert.IsFalse(mSetup.PathsClean, 'Define ohne Quelle');
end;

procedure TAtlasProjectContractSummaryTests.FailedTestsWithoutDoublesAndTotal;
var
  mTests: TAtlasProjectTests;
  mFailure: TAtlasProjectTestFailure;
begin
  mTests := TAtlasProjectTests.Empty;
  mFailure := Default(TAtlasProjectTestFailure);
  mFailure.Test := 'Kasse.Tests.Summe';
  mTests.Failures := [mFailure, mFailure];
  mFailure.Test := '';
  mTests.Failures := mTests.Failures + [mFailure];
  Assert.AreEqual(1, Integer(Length(mTests.FailedTests)));
  Assert.AreEqual('Kasse.Tests.Summe', mTests.FailedTests[0]);
  mTests.Passed := 4;
  mTests.Failed := 2;
  mTests.Errors := 1;
  mTests.Skipped := 3;
  Assert.AreEqual(10, mTests.Total);
  mTests.Failures := nil;
end;

procedure TAtlasProjectContractSummaryTests.ReleaseRemembersNewestFirst;
var
  mRelease: TAtlasProjectRelease;
begin
  mRelease := TAtlasProjectRelease.Empty;
  mRelease.Remember('Release', 'Win32', '1.0.0.0', 1);
  mRelease.Remember('Release', 'Win64', '1.1.0.0', 2);
  mRelease.Remember('release', 'win32', '1.2.0.0', 3);
  Assert.IsTrue(mRelease.Known);
  Assert.AreEqual(2, Integer(Length(mRelease.Builds)));
  Assert.AreEqual('1.2.0.0', mRelease.Builds[0].Version);
  Assert.AreEqual('1.2.0.0', mRelease.VersionOf('Release', 'Win32'));
  Assert.AreEqual('', mRelease.VersionOf('Debug', 'Win32'));
  mRelease.Builds := nil;
end;

procedure TAtlasProjectContractSummaryTests.CiMatchesJobAndKnowsBuild;
var
  mCi: TAtlasProjectCi;
  mJob: TAtlasCiJob;
begin
  mCi := TAtlasProjectCi.Empty;
  mCi.Provider := 'jenkins';
  mCi.Server := 'https://ci.example';
  mCi.Job := 'team/kasse';
  mCi.Branch := 'main';
  mJob := TAtlasCiJob.Create('Jenkins', 'https://ci.example/', 'team/kasse', True, 'main');
  Assert.IsFalse(mCi.Matches(mJob), 'unbekannt');
  mCi.Known := True;
  Assert.IsTrue(mCi.Matches(mJob));
  Assert.IsFalse(mCi.HasBuild);
  mCi.Build.Number := 482;
  Assert.IsTrue(mCi.HasBuild);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasProjectContractSummaryTests);

end.
