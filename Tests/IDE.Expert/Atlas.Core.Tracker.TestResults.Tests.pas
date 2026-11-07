unit Atlas.Core.Tracker.TestResults.Tests;

// Tests des Bereichs „Testergebnisse“ ohne VCL (#763): Ampel lokal und auf
// dem Server, Abgleich „lokal grün, Server rot“, Liste der Fehlschläge mit
// Grenze, was „Fehlgeschlagene erneut ausführen“ startet, Abfragegrenze,
// Stand nach Abruf und Fehler („Stand vom …“), Meldung beim Rotwerden und die
// Zeilen der Ansicht.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasTestResultsTests = class
  public
    [Test]
    procedure LocalLevel;
    [Test]
    procedure CiLevel;
    /// <summary>Abnahme: Vergleich lokal/Server.</summary>
    [Test]
    procedure CompareLocalAndServer;
    [Test]
    procedure SameTestAcceptsMissingUnit;
    /// <summary>Abnahme: 412 bestanden, 2 fehlgeschlagen → beide mit Meldung und Zeile.</summary>
    [Test]
    procedure ViewShowsLocalFailures;
    /// <summary>Abnahme: „Fehlgeschlagene erneut ausführen“ startet genau diese zwei.</summary>
    [Test]
    procedure RerunExactlyTheFailed;
    [Test]
    procedure MergeMarksServerAndRespectsLimit;
    /// <summary>Abnahme: Abfragegrenze welcomePage.tests.ci.intervalMinutes.</summary>
    [Test]
    procedure DueAfterInterval;
    /// <summary>Server nicht erreichbar: letzter Stand bleibt („Stand vom …“).</summary>
    [Test]
    procedure RecordedKeepsLastBuildOnError;
    [Test]
    procedure RecordedForOtherJobStartsFresh;
    [Test]
    procedure TurnedRedOnlyOnTransition;
    [Test]
    procedure ViewWithServerRow;
    /// <summary>welcomePage.tests.ci aus: keine Server-Zeile, auch wenn .atlas einen Job nennt.</summary>
    [Test]
    procedure ViewWithoutCiIgnoresServer;
    [Test]
    procedure ViewSkipsDuplicatesAndKeepsSelection;
    [Test]
    procedure NormalizeSettings;
  end;

  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasTestResultsSettingsTests = class
  public
    /// <summary>welcomePage.tests an (5), welcomePage.tests.ci aus, jenkins, 10 Minuten, Meldung an.</summary>
    [Test]
    procedure Defaults;
    [Test]
    procedure NormalizeClampsAndKnowsProviders;
    [Test]
    procedure SaveAndLoadRoundTrip;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  System.Generics.Collections,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Tracker.TestResults;

const
  cTestProject = 'C:\Projekte\Atlas\Atlas.Tests.dproj';

function Now0: TDateTime;
begin
  Result := EncodeDate(2026, 10, 16) + EncodeTime(19, 41, 0, 0);
end;

function Failure(const ATest, AMessage, AFile: string; ALine: Integer): TAtlasProjectTestFailure;
begin
  Result.Test := ATest;
  Result.Message := AMessage;
  Result.FileName := AFile;
  Result.Line := ALine;
end;

function CiFailure(const ATest, AMessage: string): TAtlasCiFailure;
begin
  Result.Test := ATest;
  Result.Message := AMessage;
end;

/// <summary>412 bestanden, 3 übersprungen, 2 fehlgeschlagen (Beispiel aus dem Issue).</summary>
function LocalRun: TAtlasProjectTests;
begin
  Result := TAtlasProjectTests.Empty;
  Result.Known := True;
  Result.At := Now0;
  Result.Project := cTestProject;
  Result.Passed := 412;
  Result.Failed := 2;
  Result.Skipped := 3;
  Result.DurationMs := 18400;
  Result.Failures := [
    Failure('Atlas.Core.Index.Tests.TIndexTests.FindsDeclarations', 'Erwartet 3 Deklarationen, gefunden 0',
      'C:\Projekte\Atlas\Atlas.Core.Index.Tests.pas', 214),
    Failure('Atlas.Core.Hover.Tests.THoverTests.ShowsDocumentation', 'Zugriffsverletzung',
      'C:\Projekte\Atlas\Atlas.Core.Hover.Tests.pas', 88)];
end;

function GreenRun: TAtlasProjectTests;
begin
  Result := TAtlasProjectTests.Empty;
  Result.Known := True;
  Result.Project := cTestProject;
  Result.Passed := 57;
end;

function Job: TAtlasCiJob;
begin
  Result := TAtlasCiJob.Create('jenkins', 'https://ci.firma.de', 'atlas', True, 'main');
end;

function Build(ANumber: Integer; AOutcome: TAtlasCiOutcome; AFailed: Integer): TAtlasCiBuild;
var
  mIndex: Integer;
begin
  Result := TAtlasCiBuild.Empty;
  Result.Number := ANumber;
  Result.Outcome := AOutcome;
  Result.TestsKnown := True;
  Result.Passed := 400;
  Result.Failed := AFailed;
  for mIndex := 1 to AFailed do
  begin
    Result.Failures := Result.Failures + [CiFailure('Atlas.Server.Tests.TServerTests.Case' + IntToStr(mIndex),
      'Server ' + IntToStr(mIndex))];
  end;
end;

function Ci(const AJob: TAtlasCiJob; const ABuild: TAtlasCiBuild): TAtlasProjectCi;
begin
  Result := TAtlasTestResults.Recorded(TAtlasProjectCi.Empty, AJob, True, ABuild, TAtlasCiFetchError.None,
    Now0 - 40 * OneMinute);
end;

function Project(const AFile: string; const ATests: TAtlasProjectTests; const AJob: TAtlasCiJob;
  const ACi: TAtlasProjectCi): TAtlasTestProject;
begin
  Result.Project := AFile;
  Result.Summary := TAtlasProjectSummary.Create(AFile);
  Result.Summary.Tests := ATests;
  Result.Summary.Ci := ACi;
  Result.Job := AJob;
  Result.Querying := False;
end;

function NoJob: TAtlasCiJob;
begin
  Result := TAtlasCiJob.Create('', '', '', False, '');
end;

type
  TTestsStore = class(TInterfacedObject, IAtlasSettingsStore)
  private
    FValues: TDictionary<string, string>;
  public
    constructor Create;
    destructor Destroy; override;
    function ReadInteger(const AName: string; ADefault: Integer): Integer;
    procedure WriteInteger(const AName: string; AValue: Integer);
    function ReadString(const AName, ADefault: string): string;
    procedure WriteString(const AName, AValue: string);
  end;

constructor TTestsStore.Create;
begin
  inherited Create;
  FValues := TDictionary<string, string>.Create;
end;

destructor TTestsStore.Destroy;
begin
  FValues.Free;
  inherited;
end;

function TTestsStore.ReadInteger(const AName: string; ADefault: Integer): Integer;
var
  mText: string;
begin
  Result := ADefault;
  if FValues.TryGetValue(AName, mText) then
  begin
    Result := StrToIntDef(mText, ADefault);
  end;
end;

procedure TTestsStore.WriteInteger(const AName: string; AValue: Integer);
begin
  FValues.AddOrSetValue(AName, IntToStr(AValue));
end;

function TTestsStore.ReadString(const AName, ADefault: string): string;
begin
  if not FValues.TryGetValue(AName, Result) then
  begin
    Result := ADefault;
  end;
end;

procedure TTestsStore.WriteString(const AName, AValue: string);
begin
  FValues.AddOrSetValue(AName, AValue);
end;

{ TAtlasTestResultsTests }

procedure TAtlasTestResultsTests.LocalLevel;
var
  mTests: TAtlasProjectTests;
begin
  mTests := TAtlasProjectTests.Empty;
  Assert.IsTrue(TAtlasTestResults.LocalLevel(mTests) = TAtlasTestLevel.Unknown);
  Assert.IsTrue(TAtlasTestResults.LocalLevel(LocalRun) = TAtlasTestLevel.Failed);
  Assert.IsTrue(TAtlasTestResults.LocalLevel(GreenRun) = TAtlasTestLevel.Passed);
  mTests := GreenRun;
  mTests.Errors := 1;
  Assert.IsTrue(TAtlasTestResults.LocalLevel(mTests) = TAtlasTestLevel.Failed, 'Fehler zählen als rot');
  mTests := GreenRun;
  mTests.Passed := 0;
  mTests.Skipped := 4;
  Assert.IsTrue(TAtlasTestResults.LocalLevel(mTests) = TAtlasTestLevel.Warning, 'nur übersprungen');
end;

procedure TAtlasTestResultsTests.CiLevel;
var
  mValue: TAtlasCiBuild;
begin
  Assert.IsTrue(TAtlasTestResults.CiLevel(TAtlasCiBuild.Empty) = TAtlasTestLevel.Unknown);
  Assert.IsTrue(TAtlasTestResults.CiLevel(Build(5, TAtlasCiOutcome.Success, 0)) = TAtlasTestLevel.Passed);
  Assert.IsTrue(TAtlasTestResults.CiLevel(Build(5, TAtlasCiOutcome.Unstable, 2)) = TAtlasTestLevel.Failed);
  Assert.IsTrue(TAtlasTestResults.CiLevel(Build(5, TAtlasCiOutcome.Unstable, 0)) = TAtlasTestLevel.Warning);
  Assert.IsTrue(TAtlasTestResults.CiLevel(Build(5, TAtlasCiOutcome.Aborted, 0)) = TAtlasTestLevel.Warning);
  mValue := Build(5, TAtlasCiOutcome.Failure, 0);
  mValue.TestsKnown := False;
  Assert.IsTrue(TAtlasTestResults.CiLevel(mValue) = TAtlasTestLevel.Failed, 'Build rot ohne Testbericht');
end;

procedure TAtlasTestResultsTests.CompareLocalAndServer;
begin
  Assert.IsTrue(TAtlasTestResults.Compare(TAtlasTestLevel.Passed, TAtlasTestLevel.Failed) =
    TAtlasTestMismatch.LocalGreenServerRed);
  Assert.IsTrue(TAtlasTestResults.Compare(TAtlasTestLevel.Failed, TAtlasTestLevel.Passed) =
    TAtlasTestMismatch.LocalRedServerGreen);
  Assert.IsTrue(TAtlasTestResults.Compare(TAtlasTestLevel.Failed, TAtlasTestLevel.Failed) =
    TAtlasTestMismatch.None);
  Assert.IsTrue(TAtlasTestResults.Compare(TAtlasTestLevel.Unknown, TAtlasTestLevel.Failed) =
    TAtlasTestMismatch.None, 'ohne lokalen Lauf kein Abgleich');
  Assert.IsTrue(TAtlasTestResults.Compare(TAtlasTestLevel.Passed, TAtlasTestLevel.Warning) =
    TAtlasTestMismatch.None);
end;

procedure TAtlasTestResultsTests.SameTestAcceptsMissingUnit;
begin
  Assert.IsTrue(TAtlasTestResults.SameTest('U.TFix.Method', 'u.tfix.method'));
  Assert.IsTrue(TAtlasTestResults.SameTest('Atlas.U.TFix.Method', 'TFix.Method'));
  Assert.IsFalse(TAtlasTestResults.SameTest('U.TFix.Method', 'Fix.Method'), 'nur ganze Namensteile');
  Assert.IsFalse(TAtlasTestResults.SameTest('', ''));
end;

procedure TAtlasTestResultsTests.ViewShowsLocalFailures;
var
  mView: TAtlasTestResultsView;
  mRow: TAtlasTestRow;
begin
  mView := TAtlasTestResults.View([Project(cTestProject, LocalRun, NoJob, TAtlasProjectCi.Empty)], '', 5,
    True);
  Assert.AreEqual(1, Integer(Length(mView.Rows)));
  Assert.IsTrue(mView.SelectedRow(mRow));
  Assert.AreEqual('Atlas.Tests', mRow.Name);
  Assert.IsTrue(mRow.LocalLevel = TAtlasTestLevel.Failed);
  Assert.AreEqual(2, mRow.Local.Failed);
  Assert.IsFalse(mRow.HasCi);
  Assert.AreEqual(2, Integer(Length(mView.Failures)));
  Assert.AreEqual('Atlas.Core.Index.Tests.TIndexTests.FindsDeclarations', mView.Failures[0].Test);
  Assert.AreEqual('Erwartet 3 Deklarationen, gefunden 0', mView.Failures[0].Message);
  Assert.AreEqual(214, mView.Failures[0].Line);
  Assert.AreEqual('C:\Projekte\Atlas\Atlas.Core.Index.Tests.pas', mView.Failures[0].FileName);
  Assert.IsTrue(mView.Failures[0].Local);
  Assert.IsFalse(mView.Failures[0].Server);
  Assert.AreEqual(88, mView.Failures[1].Line);
  Assert.AreEqual(0, mView.More);
end;

procedure TAtlasTestResultsTests.RerunExactlyTheFailed;
var
  mView: TAtlasTestResultsView;
  mTests: TAtlasProjectTests;
begin
  mView := TAtlasTestResults.View([Project(cTestProject, LocalRun, NoJob, TAtlasProjectCi.Empty)], '', 5,
    True);
  Assert.AreEqual(2, Integer(Length(mView.Rerun)));
  Assert.AreEqual('Atlas.Core.Index.Tests.TIndexTests.FindsDeclarations', mView.Rerun[0]);
  Assert.AreEqual('Atlas.Core.Hover.Tests.THoverTests.ShowsDocumentation', mView.Rerun[1]);
  // Grenze der Liste gilt nicht für „erneut ausführen“.
  mView := TAtlasTestResults.View([Project(cTestProject, LocalRun, NoJob, TAtlasProjectCi.Empty)], '', 1,
    True);
  Assert.AreEqual(1, Integer(Length(mView.Failures)));
  Assert.AreEqual(1, mView.More);
  Assert.AreEqual(2, Integer(Length(mView.Rerun)));
  // Server-Fehlschläge kommen dazu, gleiche Tests einmal.
  mTests := LocalRun;
  Assert.AreEqual(3, Integer(Length(TAtlasTestResults.RerunNames(mTests,
    Build(9, TAtlasCiOutcome.Unstable, 1), True))));
  Assert.AreEqual(2, Integer(Length(TAtlasTestResults.RerunNames(mTests,
    Build(9, TAtlasCiOutcome.Unstable, 1), False))));
  Assert.AreEqual(0, Integer(Length(TAtlasTestResults.RerunNames(GreenRun, TAtlasCiBuild.Empty, True))));
end;

procedure TAtlasTestResultsTests.MergeMarksServerAndRespectsLimit;
var
  mServer: TAtlasCiBuild;
  mItems: TArray<TAtlasTestFailureItem>;
  mMore: Integer;
begin
  mServer := Build(482, TAtlasCiOutcome.Unstable, 3);
  // Gleicher Test lokal und auf dem Server (Bericht ohne Unit-Namen).
  mServer.Failures[0] := CiFailure('TIndexTests.FindsDeclarations', 'auf dem Server');
  mItems := TAtlasTestResults.MergeFailures(LocalRun, mServer, True, 5, mMore);
  Assert.AreEqual(4, Integer(Length(mItems)));
  Assert.IsTrue(mItems[0].Local and mItems[0].Server, 'beide Marken');
  Assert.AreEqual(214, mItems[0].Line, 'lokale Fundstelle bleibt');
  Assert.IsTrue(mItems[1].Local and not mItems[1].Server);
  Assert.IsTrue(not mItems[2].Local and mItems[2].Server, 'nur auf dem Server');
  Assert.AreEqual('Server 2', mItems[2].Message);
  Assert.AreEqual(0, mItems[2].Line);
  Assert.AreEqual(0, mMore);
  // Grenze 2: je ein Platz für lokal und Server.
  mItems := TAtlasTestResults.MergeFailures(LocalRun, mServer, True, 2, mMore);
  Assert.AreEqual(2, Integer(Length(mItems)));
  Assert.IsTrue(mItems[0].Local);
  Assert.IsTrue(not mItems[1].Local and mItems[1].Server);
  Assert.AreEqual(2, mMore);
  // Ohne Server-Stand keine Server-Einträge; gezählte, nicht gespeicherte Fehlschläge zählen mit.
  mServer.Failed := 10;
  mItems := TAtlasTestResults.MergeFailures(LocalRun, mServer, False, 5, mMore);
  Assert.AreEqual(2, Integer(Length(mItems)));
  Assert.AreEqual(0, mMore);
  mItems := TAtlasTestResults.MergeFailures(LocalRun, mServer, True, 50, mMore);
  Assert.AreEqual(4, Integer(Length(mItems)));
  Assert.AreEqual(7, mMore, '10 gezählt, 3 gespeichert');
end;

procedure TAtlasTestResultsTests.DueAfterInterval;
begin
  Assert.IsTrue(TAtlasTestResults.Due(0, Now0, 10), 'noch nie gefragt');
  Assert.IsFalse(TAtlasTestResults.Due(Now0 - 9 * OneMinute, Now0, 10));
  Assert.IsTrue(TAtlasTestResults.Due(Now0 - 10 * OneMinute, Now0, 10));
  Assert.IsFalse(TAtlasTestResults.Due(Now0 - 59 * OneMinute, Now0, 60));
  Assert.IsTrue(TAtlasTestResults.Due(Now0 + OneHour, Now0, 10), 'Uhr zurückgestellt');
  Assert.IsFalse(TAtlasTestResults.Due(Now0, Now0, 0), 'mindestens eine Minute');
end;

procedure TAtlasTestResultsTests.RecordedKeepsLastBuildOnError;
var
  mOld, mNext: TAtlasProjectCi;
begin
  mOld := Ci(Job, Build(482, TAtlasCiOutcome.Unstable, 2));
  Assert.IsTrue(mOld.Matches(Job));
  Assert.IsTrue(mOld.Error = TAtlasCiFetchError.None);
  mNext := TAtlasTestResults.Recorded(mOld, Job, False, TAtlasCiBuild.Empty, TAtlasCiFetchError.Timeout, Now0);
  Assert.AreEqual(482, mNext.Build.Number, 'letzter Stand bleibt');
  Assert.IsTrue(mNext.Error = TAtlasCiFetchError.Timeout);
  Assert.IsTrue(SameDateTime(Now0, mNext.Attempt));
  Assert.IsTrue(SameDateTime(mOld.At, mNext.At), 'Stand vom … bleibt der letzte gelungene Abruf');
  mNext := TAtlasTestResults.Recorded(mNext, Job, True, Build(483, TAtlasCiOutcome.Success, 0),
    TAtlasCiFetchError.None, Now0 + OneHour);
  Assert.AreEqual(483, mNext.Build.Number);
  Assert.IsTrue(mNext.Error = TAtlasCiFetchError.None);
  Assert.IsTrue(SameDateTime(Now0 + OneHour, mNext.At));
end;

procedure TAtlasTestResultsTests.RecordedForOtherJobStartsFresh;
var
  mOld, mNext: TAtlasProjectCi;
  mOther: TAtlasCiJob;
begin
  mOld := Ci(Job, Build(482, TAtlasCiOutcome.Unstable, 2));
  mOther := TAtlasCiJob.Create('jenkins', 'https://ci.firma.de', 'atlas', True, 'develop');
  mNext := TAtlasTestResults.Recorded(mOld, mOther, False, TAtlasCiBuild.Empty, TAtlasCiFetchError.None, Now0);
  Assert.IsTrue(mNext.Matches(mOther));
  Assert.AreEqual('develop', mNext.Branch);
  Assert.IsFalse(mNext.HasBuild, 'Build des anderen Branches gilt nicht');
  Assert.IsTrue(mNext.Error = TAtlasCiFetchError.Network, 'Fehler ohne Angabe');
  Assert.IsTrue(mNext.At = 0);
end;

procedure TAtlasTestResultsTests.TurnedRedOnlyOnTransition;
var
  mGreen, mRed: TAtlasProjectCi;
begin
  mGreen := Ci(Job, Build(481, TAtlasCiOutcome.Success, 0));
  mRed := Ci(Job, Build(482, TAtlasCiOutcome.Unstable, 2));
  Assert.IsTrue(TAtlasTestResults.TurnedRed(mGreen, Job, Build(482, TAtlasCiOutcome.Unstable, 2)));
  Assert.IsFalse(TAtlasTestResults.TurnedRed(mRed, Job, Build(483, TAtlasCiOutcome.Failure, 1)),
    'war schon rot');
  Assert.IsFalse(TAtlasTestResults.TurnedRed(mGreen, Job, Build(481, TAtlasCiOutcome.Failure, 1)),
    'derselbe Build');
  Assert.IsFalse(TAtlasTestResults.TurnedRed(mGreen, Job, Build(482, TAtlasCiOutcome.Success, 0)));
  Assert.IsFalse(TAtlasTestResults.TurnedRed(TAtlasProjectCi.Empty, Job,
    Build(482, TAtlasCiOutcome.Failure, 1)), 'erster Abruf meldet nichts');
  Assert.IsFalse(TAtlasTestResults.TurnedRed(mGreen, TAtlasCiJob.Create('jenkins', 'https://ci.firma.de',
    'atlas', True, 'develop'), Build(482, TAtlasCiOutcome.Failure, 1)), 'anderer Branch');
end;

procedure TAtlasTestResultsTests.ViewWithServerRow;
var
  mView: TAtlasTestResultsView;
  mRow: TAtlasTestRow;
  mState: TAtlasProjectCi;
begin
  mState := Ci(Job, Build(482, TAtlasCiOutcome.Unstable, 2));
  mView := TAtlasTestResults.View([Project(cTestProject, GreenRun, Job, mState)], '', 5, True);
  Assert.IsTrue(mView.SelectedRow(mRow));
  Assert.IsTrue(mRow.HasCi);
  Assert.AreEqual(482, mRow.Ci.Build.Number);
  Assert.IsTrue(mRow.LocalLevel = TAtlasTestLevel.Passed);
  Assert.IsTrue(mRow.CiLevel = TAtlasTestLevel.Failed);
  Assert.IsTrue(mRow.Mismatch = TAtlasTestMismatch.LocalGreenServerRed, 'lokal grün, Server rot');
  Assert.IsTrue(mRow.Level = TAtlasTestLevel.Failed);
  Assert.IsFalse(mRow.CiStale);
  Assert.AreEqual(2, Integer(Length(mView.Failures)), 'Server-Fehlschläge in derselben Liste');
  Assert.IsTrue(mView.Failures[0].Server);
  // Nach einem Fehler: Stand vom letzten Abruf.
  mState := TAtlasTestResults.Recorded(mState, Job, False, TAtlasCiBuild.Empty, TAtlasCiFetchError.Network,
    Now0);
  mView := TAtlasTestResults.View([Project(cTestProject, GreenRun, Job, mState)], '', 5, True);
  Assert.IsTrue(mView.SelectedRow(mRow));
  Assert.IsTrue(mRow.CiStale);
  Assert.AreEqual(482, mRow.Ci.Build.Number);
  // Nur Server, ohne lokalen Lauf: Zeile mit dem Projektnamen.
  mView := TAtlasTestResults.View([Project('C:\P\Kasse.dproj', TAtlasProjectTests.Empty, Job, mState)], '', 5,
    True);
  Assert.AreEqual(1, Integer(Length(mView.Rows)));
  Assert.AreEqual('Kasse', mView.Rows[0].Name);
  Assert.IsTrue(mView.Rows[0].Mismatch = TAtlasTestMismatch.None);
  // Stand eines anderen Branches zählt nicht.
  mView := TAtlasTestResults.View([Project(cTestProject, GreenRun, TAtlasCiJob.Create('jenkins',
    'https://ci.firma.de', 'atlas', True, 'develop'), mState)], '', 5, True);
  Assert.IsTrue(mView.Rows[0].HasCi);
  Assert.IsFalse(mView.Rows[0].Ci.HasBuild);
  Assert.IsTrue(mView.Rows[0].CiLevel = TAtlasTestLevel.Unknown);
end;

procedure TAtlasTestResultsTests.ViewWithoutCiIgnoresServer;
var
  mView: TAtlasTestResultsView;
  mState: TAtlasProjectCi;
begin
  mState := Ci(Job, Build(482, TAtlasCiOutcome.Unstable, 2));
  mView := TAtlasTestResults.View([Project(cTestProject, GreenRun, Job, mState)], '', 5, False);
  Assert.AreEqual(1, Integer(Length(mView.Rows)));
  Assert.IsFalse(mView.Rows[0].HasCi);
  Assert.AreEqual(0, Integer(Length(mView.Failures)));
  mView := TAtlasTestResults.View([Project('C:\P\Kasse.dproj', TAtlasProjectTests.Empty, Job, mState)], '', 5,
    False);
  Assert.IsTrue(mView.Empty, 'ohne lokalen Lauf und ohne Server nichts zu zeigen');
  Assert.AreEqual(-1, mView.Selected);
end;

procedure TAtlasTestResultsTests.ViewSkipsDuplicatesAndKeepsSelection;
var
  mView: TAtlasTestResultsView;
begin
  // Projektgruppe und Testprojekt tragen denselben Lauf.
  mView := TAtlasTestResults.View([
    Project('C:\Projekte\Atlas\Atlas.groupproj', LocalRun, NoJob, TAtlasProjectCi.Empty),
    Project(cTestProject, LocalRun, NoJob, TAtlasProjectCi.Empty),
    Project('C:\P\Kasse.Tests.dproj', GreenRun, NoJob, TAtlasProjectCi.Empty)], '', 5, True);
  Assert.AreEqual(1, Integer(Length(mView.Rows)), 'gleiches Testprojekt einmal');
  mView := TAtlasTestResults.View([
    Project('C:\Projekte\Atlas\Atlas.groupproj', LocalRun, NoJob, TAtlasProjectCi.Empty),
    Project('C:\P\Kasse.dproj', TAtlasProjectTests.Empty, Job, Ci(Job, Build(7, TAtlasCiOutcome.Success, 0)))],
    'c:\p\kasse.dproj', 5, True);
  Assert.AreEqual(2, Integer(Length(mView.Rows)));
  Assert.AreEqual(1, mView.Selected, 'Auswahl ohne Rücksicht auf Groß- und Kleinschreibung');
  Assert.AreEqual(0, Integer(Length(mView.Failures)));
  mView := TAtlasTestResults.View([
    Project('C:\Projekte\Atlas\Atlas.groupproj', LocalRun, NoJob, TAtlasProjectCi.Empty)], 'C:\gibt\es\nicht', 5,
    True);
  Assert.AreEqual(0, mView.Selected, 'unbekannte Auswahl: erste Zeile');
end;

procedure TAtlasTestResultsTests.NormalizeSettings;
begin
  Assert.AreEqual(1, TAtlasTestResults.NormalizedMaxFailures(0));
  Assert.AreEqual(50, TAtlasTestResults.NormalizedMaxFailures(500));
  Assert.AreEqual(5, TAtlasTestResults.NormalizedMaxFailures(5));
  Assert.AreEqual(1, TAtlasTestResults.NormalizedInterval(-3));
  Assert.AreEqual(1440, TAtlasTestResults.NormalizedInterval(100000));
  Assert.AreEqual('Jenkins', TAtlasTestResults.ProviderCaption('jenkins'));
  Assert.AreEqual('Gitlab', TAtlasTestResults.ProviderCaption('gitlab'));
  Assert.AreEqual('', TAtlasTestResults.ProviderCaption(''));
end;

{ TAtlasTestResultsSettingsTests }

procedure TAtlasTestResultsSettingsTests.Defaults;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.WelcomePageTests);
  Assert.AreEqual(5, mSettings.WelcomePageTestsMaxFailures);
  Assert.AreEqual(TAtlasTestResults.cDefaultMaxFailures, mSettings.WelcomePageTestsMaxFailures);
  Assert.IsFalse(mSettings.WelcomePageTestsCi, 'ohne Zustimmung kein Netzzugriff');
  Assert.AreEqual('jenkins', mSettings.WelcomePageTestsCiProvider);
  Assert.AreEqual(TAtlasTestResults.cDefaultProvider, TAtlasPluginSettings.DefaultCiProvider);
  Assert.AreEqual(10, mSettings.WelcomePageTestsCiIntervalMinutes);
  Assert.AreEqual(TAtlasTestResults.cDefaultIntervalMinutes, mSettings.WelcomePageTestsCiIntervalMinutes);
  Assert.IsTrue(mSettings.WelcomePageTestsCiNotify);
  Assert.IsTrue(mSettings.CiLogin);
end;

procedure TAtlasTestResultsSettingsTests.NormalizeClampsAndKnowsProviders;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.WelcomePageTestsMaxFailures := 0;
  mSettings.WelcomePageTestsCiIntervalMinutes := 0;
  mSettings.WelcomePageTestsCiProvider := ' JENKINS ';
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MinTestFailures, mSettings.WelcomePageTestsMaxFailures);
  Assert.AreEqual(TAtlasPluginSettings.MinCiIntervalMinutes, mSettings.WelcomePageTestsCiIntervalMinutes);
  Assert.AreEqual('jenkins', mSettings.WelcomePageTestsCiProvider);
  mSettings.WelcomePageTestsMaxFailures := 1000;
  mSettings.WelcomePageTestsCiIntervalMinutes := 100000;
  mSettings.WelcomePageTestsCiProvider := 'travis';
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MaxTestFailures, mSettings.WelcomePageTestsMaxFailures);
  Assert.AreEqual(TAtlasPluginSettings.MaxCiIntervalMinutes, mSettings.WelcomePageTestsCiIntervalMinutes);
  Assert.AreEqual('jenkins', mSettings.WelcomePageTestsCiProvider, 'unbekannter Anbieter: Vorgabe');
  // Grenzen wie im Bereich.
  Assert.AreEqual(TAtlasTestResults.cMinMaxFailures, TAtlasPluginSettings.MinTestFailures);
  Assert.AreEqual(TAtlasTestResults.cMaxMaxFailures, TAtlasPluginSettings.MaxTestFailures);
  Assert.AreEqual(TAtlasTestResults.cMinIntervalMinutes, TAtlasPluginSettings.MinCiIntervalMinutes);
  Assert.AreEqual(TAtlasTestResults.cMaxIntervalMinutes, TAtlasPluginSettings.MaxCiIntervalMinutes);
end;

procedure TAtlasTestResultsSettingsTests.SaveAndLoadRoundTrip;
var
  mStore: IAtlasSettingsStore;
  mSaved, mLoaded: TAtlasPluginSettings;
begin
  mStore := TTestsStore.Create;
  mSaved := TAtlasPluginSettings.Defaults;
  mSaved.WelcomePageTests := False;
  mSaved.WelcomePageTestsMaxFailures := 12;
  mSaved.WelcomePageTestsCi := True;
  mSaved.WelcomePageTestsCiIntervalMinutes := 30;
  mSaved.WelcomePageTestsCiNotify := False;
  mSaved.CiLogin := False;
  mSaved.Save(mStore);
  Assert.AreEqual(0, mStore.ReadInteger('WelcomePageTests', 1), 'Registry-Name');
  Assert.AreEqual(12, mStore.ReadInteger('WelcomePageTestsMaxFailures', 0));
  Assert.AreEqual(1, mStore.ReadInteger('WelcomePageTestsCi', 0));
  Assert.AreEqual('jenkins', mStore.ReadString('WelcomePageTestsCiProvider', ''));
  Assert.AreEqual(30, mStore.ReadInteger('WelcomePageTestsCiIntervalMinutes', 0));
  Assert.AreEqual(0, mStore.ReadInteger('WelcomePageTestsCiNotify', 1));
  Assert.AreEqual(0, mStore.ReadInteger('CiLogin', 1));
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.WelcomePageTests);
  Assert.AreEqual(12, mLoaded.WelcomePageTestsMaxFailures);
  Assert.IsTrue(mLoaded.WelcomePageTestsCi);
  Assert.AreEqual(30, mLoaded.WelcomePageTestsCiIntervalMinutes);
  Assert.IsFalse(mLoaded.WelcomePageTestsCiNotify);
  Assert.IsFalse(mLoaded.CiLogin);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTestResultsTests);
  TDUnitX.RegisterTestFixture(TAtlasTestResultsSettingsTests);

end.
