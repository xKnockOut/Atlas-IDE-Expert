unit Atlas.Core.Welcome.TestResults.Tests;

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
  TAtlasWelcomeTestResultsTests = class
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
  Atlas.Core.Ci.Contract,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Welcome.TestResults;

const
  TestProject = 'C:\Projekte\Atlas\Atlas.Tests.dproj';

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
  Result.Project := TestProject;
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
  Result.Project := TestProject;
  Result.Passed := 57;
end;

function Job: TAtlasCiJob;
begin
  Result := TAtlasCiJob.Create('jenkins', 'https://ci.firma.de', 'atlas', True, 'main');
end;

function Build(ANumber: Integer; AOutcome: TAtlasCiOutcome; AFailed: Integer): TAtlasCiBuild;
var
  Index: Integer;
begin
  Result := TAtlasCiBuild.Empty;
  Result.Number := ANumber;
  Result.Outcome := AOutcome;
  Result.TestsKnown := True;
  Result.Passed := 400;
  Result.Failed := AFailed;
  for Index := 1 to AFailed do
    Result.Failures := Result.Failures + [CiFailure('Atlas.Server.Tests.TServerTests.Case' + IntToStr(Index),
      'Server ' + IntToStr(Index))];
end;

function Ci(const AJob: TAtlasCiJob; const ABuild: TAtlasCiBuild): TAtlasProjectCi;
begin
  Result := TAtlasWelcomeTestResults.Recorded(TAtlasProjectCi.Empty, AJob, True, ABuild, TAtlasCiFetchError.None,
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
  Text: string;
begin
  Result := ADefault;
  if FValues.TryGetValue(AName, Text) then
    Result := StrToIntDef(Text, ADefault);
end;

procedure TTestsStore.WriteInteger(const AName: string; AValue: Integer);
begin
  FValues.AddOrSetValue(AName, IntToStr(AValue));
end;

function TTestsStore.ReadString(const AName, ADefault: string): string;
begin
  if not FValues.TryGetValue(AName, Result) then
    Result := ADefault;
end;

procedure TTestsStore.WriteString(const AName, AValue: string);
begin
  FValues.AddOrSetValue(AName, AValue);
end;

{ TAtlasWelcomeTestResultsTests }

procedure TAtlasWelcomeTestResultsTests.LocalLevel;
var
  Tests: TAtlasProjectTests;
begin
  Tests := TAtlasProjectTests.Empty;
  Assert.IsTrue(TAtlasWelcomeTestResults.LocalLevel(Tests) = TAtlasTestLevel.Unknown);
  Assert.IsTrue(TAtlasWelcomeTestResults.LocalLevel(LocalRun) = TAtlasTestLevel.Failed);
  Assert.IsTrue(TAtlasWelcomeTestResults.LocalLevel(GreenRun) = TAtlasTestLevel.Passed);
  Tests := GreenRun;
  Tests.Errors := 1;
  Assert.IsTrue(TAtlasWelcomeTestResults.LocalLevel(Tests) = TAtlasTestLevel.Failed, 'Fehler zählen als rot');
  Tests := GreenRun;
  Tests.Passed := 0;
  Tests.Skipped := 4;
  Assert.IsTrue(TAtlasWelcomeTestResults.LocalLevel(Tests) = TAtlasTestLevel.Warning, 'nur übersprungen');
end;

procedure TAtlasWelcomeTestResultsTests.CiLevel;
var
  Value: TAtlasCiBuild;
begin
  Assert.IsTrue(TAtlasWelcomeTestResults.CiLevel(TAtlasCiBuild.Empty) = TAtlasTestLevel.Unknown);
  Assert.IsTrue(TAtlasWelcomeTestResults.CiLevel(Build(5, TAtlasCiOutcome.Success, 0)) = TAtlasTestLevel.Passed);
  Assert.IsTrue(TAtlasWelcomeTestResults.CiLevel(Build(5, TAtlasCiOutcome.Unstable, 2)) = TAtlasTestLevel.Failed);
  Assert.IsTrue(TAtlasWelcomeTestResults.CiLevel(Build(5, TAtlasCiOutcome.Unstable, 0)) = TAtlasTestLevel.Warning);
  Assert.IsTrue(TAtlasWelcomeTestResults.CiLevel(Build(5, TAtlasCiOutcome.Aborted, 0)) = TAtlasTestLevel.Warning);
  Value := Build(5, TAtlasCiOutcome.Failure, 0);
  Value.TestsKnown := False;
  Assert.IsTrue(TAtlasWelcomeTestResults.CiLevel(Value) = TAtlasTestLevel.Failed, 'Build rot ohne Testbericht');
end;

procedure TAtlasWelcomeTestResultsTests.CompareLocalAndServer;
begin
  Assert.IsTrue(TAtlasWelcomeTestResults.Compare(TAtlasTestLevel.Passed, TAtlasTestLevel.Failed) =
    TAtlasTestMismatch.LocalGreenServerRed);
  Assert.IsTrue(TAtlasWelcomeTestResults.Compare(TAtlasTestLevel.Failed, TAtlasTestLevel.Passed) =
    TAtlasTestMismatch.LocalRedServerGreen);
  Assert.IsTrue(TAtlasWelcomeTestResults.Compare(TAtlasTestLevel.Failed, TAtlasTestLevel.Failed) =
    TAtlasTestMismatch.None);
  Assert.IsTrue(TAtlasWelcomeTestResults.Compare(TAtlasTestLevel.Unknown, TAtlasTestLevel.Failed) =
    TAtlasTestMismatch.None, 'ohne lokalen Lauf kein Abgleich');
  Assert.IsTrue(TAtlasWelcomeTestResults.Compare(TAtlasTestLevel.Passed, TAtlasTestLevel.Warning) =
    TAtlasTestMismatch.None);
end;

procedure TAtlasWelcomeTestResultsTests.SameTestAcceptsMissingUnit;
begin
  Assert.IsTrue(TAtlasWelcomeTestResults.SameTest('U.TFix.Method', 'u.tfix.method'));
  Assert.IsTrue(TAtlasWelcomeTestResults.SameTest('Atlas.U.TFix.Method', 'TFix.Method'));
  Assert.IsFalse(TAtlasWelcomeTestResults.SameTest('U.TFix.Method', 'Fix.Method'), 'nur ganze Namensteile');
  Assert.IsFalse(TAtlasWelcomeTestResults.SameTest('', ''));
end;

procedure TAtlasWelcomeTestResultsTests.ViewShowsLocalFailures;
var
  View: TAtlasTestResultsView;
  Row: TAtlasTestRow;
begin
  View := TAtlasWelcomeTestResults.View([Project(TestProject, LocalRun, NoJob, TAtlasProjectCi.Empty)], '', 5,
    True);
  Assert.AreEqual(1, Integer(Length(View.Rows)));
  Assert.IsTrue(View.SelectedRow(Row));
  Assert.AreEqual('Atlas.Tests', Row.Name);
  Assert.IsTrue(Row.LocalLevel = TAtlasTestLevel.Failed);
  Assert.AreEqual(2, Row.Local.Failed);
  Assert.IsFalse(Row.HasCi);
  Assert.AreEqual(2, Integer(Length(View.Failures)));
  Assert.AreEqual('Atlas.Core.Index.Tests.TIndexTests.FindsDeclarations', View.Failures[0].Test);
  Assert.AreEqual('Erwartet 3 Deklarationen, gefunden 0', View.Failures[0].Message);
  Assert.AreEqual(214, View.Failures[0].Line);
  Assert.AreEqual('C:\Projekte\Atlas\Atlas.Core.Index.Tests.pas', View.Failures[0].FileName);
  Assert.IsTrue(View.Failures[0].Local);
  Assert.IsFalse(View.Failures[0].Server);
  Assert.AreEqual(88, View.Failures[1].Line);
  Assert.AreEqual(0, View.More);
end;

procedure TAtlasWelcomeTestResultsTests.RerunExactlyTheFailed;
var
  View: TAtlasTestResultsView;
  Tests: TAtlasProjectTests;
begin
  View := TAtlasWelcomeTestResults.View([Project(TestProject, LocalRun, NoJob, TAtlasProjectCi.Empty)], '', 5,
    True);
  Assert.AreEqual(2, Integer(Length(View.Rerun)));
  Assert.AreEqual('Atlas.Core.Index.Tests.TIndexTests.FindsDeclarations', View.Rerun[0]);
  Assert.AreEqual('Atlas.Core.Hover.Tests.THoverTests.ShowsDocumentation', View.Rerun[1]);
  // Grenze der Liste gilt nicht für „erneut ausführen“.
  View := TAtlasWelcomeTestResults.View([Project(TestProject, LocalRun, NoJob, TAtlasProjectCi.Empty)], '', 1,
    True);
  Assert.AreEqual(1, Integer(Length(View.Failures)));
  Assert.AreEqual(1, View.More);
  Assert.AreEqual(2, Integer(Length(View.Rerun)));
  // Server-Fehlschläge kommen dazu, gleiche Tests einmal.
  Tests := LocalRun;
  Assert.AreEqual(3, Integer(Length(TAtlasWelcomeTestResults.RerunNames(Tests,
    Build(9, TAtlasCiOutcome.Unstable, 1), True))));
  Assert.AreEqual(2, Integer(Length(TAtlasWelcomeTestResults.RerunNames(Tests,
    Build(9, TAtlasCiOutcome.Unstable, 1), False))));
  Assert.AreEqual(0, Integer(Length(TAtlasWelcomeTestResults.RerunNames(GreenRun, TAtlasCiBuild.Empty, True))));
end;

procedure TAtlasWelcomeTestResultsTests.MergeMarksServerAndRespectsLimit;
var
  Server: TAtlasCiBuild;
  Items: TArray<TAtlasTestFailureItem>;
  More: Integer;
begin
  Server := Build(482, TAtlasCiOutcome.Unstable, 3);
  // Gleicher Test lokal und auf dem Server (Bericht ohne Unit-Namen).
  Server.Failures[0] := CiFailure('TIndexTests.FindsDeclarations', 'auf dem Server');
  Items := TAtlasWelcomeTestResults.MergeFailures(LocalRun, Server, True, 5, More);
  Assert.AreEqual(4, Integer(Length(Items)));
  Assert.IsTrue(Items[0].Local and Items[0].Server, 'beide Marken');
  Assert.AreEqual(214, Items[0].Line, 'lokale Fundstelle bleibt');
  Assert.IsTrue(Items[1].Local and not Items[1].Server);
  Assert.IsTrue(not Items[2].Local and Items[2].Server, 'nur auf dem Server');
  Assert.AreEqual('Server 2', Items[2].Message);
  Assert.AreEqual(0, Items[2].Line);
  Assert.AreEqual(0, More);
  // Grenze 2: je ein Platz für lokal und Server.
  Items := TAtlasWelcomeTestResults.MergeFailures(LocalRun, Server, True, 2, More);
  Assert.AreEqual(2, Integer(Length(Items)));
  Assert.IsTrue(Items[0].Local);
  Assert.IsTrue(not Items[1].Local and Items[1].Server);
  Assert.AreEqual(2, More);
  // Ohne Server-Stand keine Server-Einträge; gezählte, nicht gespeicherte Fehlschläge zählen mit.
  Server.Failed := 10;
  Items := TAtlasWelcomeTestResults.MergeFailures(LocalRun, Server, False, 5, More);
  Assert.AreEqual(2, Integer(Length(Items)));
  Assert.AreEqual(0, More);
  Items := TAtlasWelcomeTestResults.MergeFailures(LocalRun, Server, True, 50, More);
  Assert.AreEqual(4, Integer(Length(Items)));
  Assert.AreEqual(7, More, '10 gezählt, 3 gespeichert');
end;

procedure TAtlasWelcomeTestResultsTests.DueAfterInterval;
begin
  Assert.IsTrue(TAtlasWelcomeTestResults.Due(0, Now0, 10), 'noch nie gefragt');
  Assert.IsFalse(TAtlasWelcomeTestResults.Due(Now0 - 9 * OneMinute, Now0, 10));
  Assert.IsTrue(TAtlasWelcomeTestResults.Due(Now0 - 10 * OneMinute, Now0, 10));
  Assert.IsFalse(TAtlasWelcomeTestResults.Due(Now0 - 59 * OneMinute, Now0, 60));
  Assert.IsTrue(TAtlasWelcomeTestResults.Due(Now0 + OneHour, Now0, 10), 'Uhr zurückgestellt');
  Assert.IsFalse(TAtlasWelcomeTestResults.Due(Now0, Now0, 0), 'mindestens eine Minute');
end;

procedure TAtlasWelcomeTestResultsTests.RecordedKeepsLastBuildOnError;
var
  Old, Next: TAtlasProjectCi;
begin
  Old := Ci(Job, Build(482, TAtlasCiOutcome.Unstable, 2));
  Assert.IsTrue(Old.Matches(Job));
  Assert.IsTrue(Old.Error = TAtlasCiFetchError.None);
  Next := TAtlasWelcomeTestResults.Recorded(Old, Job, False, TAtlasCiBuild.Empty, TAtlasCiFetchError.Timeout, Now0);
  Assert.AreEqual(482, Next.Build.Number, 'letzter Stand bleibt');
  Assert.IsTrue(Next.Error = TAtlasCiFetchError.Timeout);
  Assert.IsTrue(SameDateTime(Now0, Next.Attempt));
  Assert.IsTrue(SameDateTime(Old.At, Next.At), 'Stand vom … bleibt der letzte gelungene Abruf');
  Next := TAtlasWelcomeTestResults.Recorded(Next, Job, True, Build(483, TAtlasCiOutcome.Success, 0),
    TAtlasCiFetchError.None, Now0 + OneHour);
  Assert.AreEqual(483, Next.Build.Number);
  Assert.IsTrue(Next.Error = TAtlasCiFetchError.None);
  Assert.IsTrue(SameDateTime(Now0 + OneHour, Next.At));
end;

procedure TAtlasWelcomeTestResultsTests.RecordedForOtherJobStartsFresh;
var
  Old, Next: TAtlasProjectCi;
  Other: TAtlasCiJob;
begin
  Old := Ci(Job, Build(482, TAtlasCiOutcome.Unstable, 2));
  Other := TAtlasCiJob.Create('jenkins', 'https://ci.firma.de', 'atlas', True, 'develop');
  Next := TAtlasWelcomeTestResults.Recorded(Old, Other, False, TAtlasCiBuild.Empty, TAtlasCiFetchError.None, Now0);
  Assert.IsTrue(Next.Matches(Other));
  Assert.AreEqual('develop', Next.Branch);
  Assert.IsFalse(Next.HasBuild, 'Build des anderen Branches gilt nicht');
  Assert.IsTrue(Next.Error = TAtlasCiFetchError.Network, 'Fehler ohne Angabe');
  Assert.IsTrue(Next.At = 0);
end;

procedure TAtlasWelcomeTestResultsTests.TurnedRedOnlyOnTransition;
var
  Green, Red: TAtlasProjectCi;
begin
  Green := Ci(Job, Build(481, TAtlasCiOutcome.Success, 0));
  Red := Ci(Job, Build(482, TAtlasCiOutcome.Unstable, 2));
  Assert.IsTrue(TAtlasWelcomeTestResults.TurnedRed(Green, Job, Build(482, TAtlasCiOutcome.Unstable, 2)));
  Assert.IsFalse(TAtlasWelcomeTestResults.TurnedRed(Red, Job, Build(483, TAtlasCiOutcome.Failure, 1)),
    'war schon rot');
  Assert.IsFalse(TAtlasWelcomeTestResults.TurnedRed(Green, Job, Build(481, TAtlasCiOutcome.Failure, 1)),
    'derselbe Build');
  Assert.IsFalse(TAtlasWelcomeTestResults.TurnedRed(Green, Job, Build(482, TAtlasCiOutcome.Success, 0)));
  Assert.IsFalse(TAtlasWelcomeTestResults.TurnedRed(TAtlasProjectCi.Empty, Job,
    Build(482, TAtlasCiOutcome.Failure, 1)), 'erster Abruf meldet nichts');
  Assert.IsFalse(TAtlasWelcomeTestResults.TurnedRed(Green, TAtlasCiJob.Create('jenkins', 'https://ci.firma.de',
    'atlas', True, 'develop'), Build(482, TAtlasCiOutcome.Failure, 1)), 'anderer Branch');
end;

procedure TAtlasWelcomeTestResultsTests.ViewWithServerRow;
var
  View: TAtlasTestResultsView;
  Row: TAtlasTestRow;
  State: TAtlasProjectCi;
begin
  State := Ci(Job, Build(482, TAtlasCiOutcome.Unstable, 2));
  View := TAtlasWelcomeTestResults.View([Project(TestProject, GreenRun, Job, State)], '', 5, True);
  Assert.IsTrue(View.SelectedRow(Row));
  Assert.IsTrue(Row.HasCi);
  Assert.AreEqual(482, Row.Ci.Build.Number);
  Assert.IsTrue(Row.LocalLevel = TAtlasTestLevel.Passed);
  Assert.IsTrue(Row.CiLevel = TAtlasTestLevel.Failed);
  Assert.IsTrue(Row.Mismatch = TAtlasTestMismatch.LocalGreenServerRed, 'lokal grün, Server rot');
  Assert.IsTrue(Row.Level = TAtlasTestLevel.Failed);
  Assert.IsFalse(Row.CiStale);
  Assert.AreEqual(2, Integer(Length(View.Failures)), 'Server-Fehlschläge in derselben Liste');
  Assert.IsTrue(View.Failures[0].Server);
  // Nach einem Fehler: Stand vom letzten Abruf.
  State := TAtlasWelcomeTestResults.Recorded(State, Job, False, TAtlasCiBuild.Empty, TAtlasCiFetchError.Network,
    Now0);
  View := TAtlasWelcomeTestResults.View([Project(TestProject, GreenRun, Job, State)], '', 5, True);
  Assert.IsTrue(View.SelectedRow(Row));
  Assert.IsTrue(Row.CiStale);
  Assert.AreEqual(482, Row.Ci.Build.Number);
  // Nur Server, ohne lokalen Lauf: Zeile mit dem Projektnamen.
  View := TAtlasWelcomeTestResults.View([Project('C:\P\Kasse.dproj', TAtlasProjectTests.Empty, Job, State)], '', 5,
    True);
  Assert.AreEqual(1, Integer(Length(View.Rows)));
  Assert.AreEqual('Kasse', View.Rows[0].Name);
  Assert.IsTrue(View.Rows[0].Mismatch = TAtlasTestMismatch.None);
  // Stand eines anderen Branches zählt nicht.
  View := TAtlasWelcomeTestResults.View([Project(TestProject, GreenRun, TAtlasCiJob.Create('jenkins',
    'https://ci.firma.de', 'atlas', True, 'develop'), State)], '', 5, True);
  Assert.IsTrue(View.Rows[0].HasCi);
  Assert.IsFalse(View.Rows[0].Ci.HasBuild);
  Assert.IsTrue(View.Rows[0].CiLevel = TAtlasTestLevel.Unknown);
end;

procedure TAtlasWelcomeTestResultsTests.ViewWithoutCiIgnoresServer;
var
  View: TAtlasTestResultsView;
  State: TAtlasProjectCi;
begin
  State := Ci(Job, Build(482, TAtlasCiOutcome.Unstable, 2));
  View := TAtlasWelcomeTestResults.View([Project(TestProject, GreenRun, Job, State)], '', 5, False);
  Assert.AreEqual(1, Integer(Length(View.Rows)));
  Assert.IsFalse(View.Rows[0].HasCi);
  Assert.AreEqual(0, Integer(Length(View.Failures)));
  View := TAtlasWelcomeTestResults.View([Project('C:\P\Kasse.dproj', TAtlasProjectTests.Empty, Job, State)], '', 5,
    False);
  Assert.IsTrue(View.Empty, 'ohne lokalen Lauf und ohne Server nichts zu zeigen');
  Assert.AreEqual(-1, View.Selected);
end;

procedure TAtlasWelcomeTestResultsTests.ViewSkipsDuplicatesAndKeepsSelection;
var
  View: TAtlasTestResultsView;
begin
  // Projektgruppe und Testprojekt tragen denselben Lauf.
  View := TAtlasWelcomeTestResults.View([
    Project('C:\Projekte\Atlas\Atlas.groupproj', LocalRun, NoJob, TAtlasProjectCi.Empty),
    Project(TestProject, LocalRun, NoJob, TAtlasProjectCi.Empty),
    Project('C:\P\Kasse.Tests.dproj', GreenRun, NoJob, TAtlasProjectCi.Empty)], '', 5, True);
  Assert.AreEqual(1, Integer(Length(View.Rows)), 'gleiches Testprojekt einmal');
  View := TAtlasWelcomeTestResults.View([
    Project('C:\Projekte\Atlas\Atlas.groupproj', LocalRun, NoJob, TAtlasProjectCi.Empty),
    Project('C:\P\Kasse.dproj', TAtlasProjectTests.Empty, Job, Ci(Job, Build(7, TAtlasCiOutcome.Success, 0)))],
    'c:\p\kasse.dproj', 5, True);
  Assert.AreEqual(2, Integer(Length(View.Rows)));
  Assert.AreEqual(1, View.Selected, 'Auswahl ohne Rücksicht auf Groß- und Kleinschreibung');
  Assert.AreEqual(0, Integer(Length(View.Failures)));
  View := TAtlasWelcomeTestResults.View([
    Project('C:\Projekte\Atlas\Atlas.groupproj', LocalRun, NoJob, TAtlasProjectCi.Empty)], 'C:\gibt\es\nicht', 5,
    True);
  Assert.AreEqual(0, View.Selected, 'unbekannte Auswahl: erste Zeile');
end;

procedure TAtlasWelcomeTestResultsTests.NormalizeSettings;
begin
  Assert.AreEqual(1, TAtlasWelcomeTestResults.NormalizedMaxFailures(0));
  Assert.AreEqual(50, TAtlasWelcomeTestResults.NormalizedMaxFailures(500));
  Assert.AreEqual(5, TAtlasWelcomeTestResults.NormalizedMaxFailures(5));
  Assert.AreEqual(1, TAtlasWelcomeTestResults.NormalizedInterval(-3));
  Assert.AreEqual(1440, TAtlasWelcomeTestResults.NormalizedInterval(100000));
  Assert.AreEqual('Jenkins', TAtlasWelcomeTestResults.ProviderCaption('jenkins'));
  Assert.AreEqual('Gitlab', TAtlasWelcomeTestResults.ProviderCaption('gitlab'));
  Assert.AreEqual('', TAtlasWelcomeTestResults.ProviderCaption(''));
end;

{ TAtlasTestResultsSettingsTests }

procedure TAtlasTestResultsSettingsTests.Defaults;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.WelcomePageTests);
  Assert.AreEqual(5, Settings.WelcomePageTestsMaxFailures);
  Assert.AreEqual(TAtlasWelcomeTestResults.DefaultMaxFailures, Settings.WelcomePageTestsMaxFailures);
  Assert.IsFalse(Settings.WelcomePageTestsCi, 'ohne Zustimmung kein Netzzugriff');
  Assert.AreEqual('jenkins', Settings.WelcomePageTestsCiProvider);
  Assert.AreEqual(TAtlasWelcomeTestResults.DefaultProvider, TAtlasPluginSettings.DefaultCiProvider);
  Assert.AreEqual(10, Settings.WelcomePageTestsCiIntervalMinutes);
  Assert.AreEqual(TAtlasWelcomeTestResults.DefaultIntervalMinutes, Settings.WelcomePageTestsCiIntervalMinutes);
  Assert.IsTrue(Settings.WelcomePageTestsCiNotify);
  Assert.IsTrue(Settings.CiLogin);
end;

procedure TAtlasTestResultsSettingsTests.NormalizeClampsAndKnowsProviders;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Settings.WelcomePageTestsMaxFailures := 0;
  Settings.WelcomePageTestsCiIntervalMinutes := 0;
  Settings.WelcomePageTestsCiProvider := ' JENKINS ';
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MinTestFailures, Settings.WelcomePageTestsMaxFailures);
  Assert.AreEqual(TAtlasPluginSettings.MinCiIntervalMinutes, Settings.WelcomePageTestsCiIntervalMinutes);
  Assert.AreEqual('jenkins', Settings.WelcomePageTestsCiProvider);
  Settings.WelcomePageTestsMaxFailures := 1000;
  Settings.WelcomePageTestsCiIntervalMinutes := 100000;
  Settings.WelcomePageTestsCiProvider := 'travis';
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MaxTestFailures, Settings.WelcomePageTestsMaxFailures);
  Assert.AreEqual(TAtlasPluginSettings.MaxCiIntervalMinutes, Settings.WelcomePageTestsCiIntervalMinutes);
  Assert.AreEqual('jenkins', Settings.WelcomePageTestsCiProvider, 'unbekannter Anbieter: Vorgabe');
  // Grenzen wie im Bereich.
  Assert.AreEqual(TAtlasWelcomeTestResults.MinMaxFailures, TAtlasPluginSettings.MinTestFailures);
  Assert.AreEqual(TAtlasWelcomeTestResults.MaxMaxFailures, TAtlasPluginSettings.MaxTestFailures);
  Assert.AreEqual(TAtlasWelcomeTestResults.MinIntervalMinutes, TAtlasPluginSettings.MinCiIntervalMinutes);
  Assert.AreEqual(TAtlasWelcomeTestResults.MaxIntervalMinutes, TAtlasPluginSettings.MaxCiIntervalMinutes);
end;

procedure TAtlasTestResultsSettingsTests.SaveAndLoadRoundTrip;
var
  Store: IAtlasSettingsStore;
  Saved, Loaded: TAtlasPluginSettings;
begin
  Store := TTestsStore.Create;
  Saved := TAtlasPluginSettings.Defaults;
  Saved.WelcomePageTests := False;
  Saved.WelcomePageTestsMaxFailures := 12;
  Saved.WelcomePageTestsCi := True;
  Saved.WelcomePageTestsCiIntervalMinutes := 30;
  Saved.WelcomePageTestsCiNotify := False;
  Saved.CiLogin := False;
  Saved.Save(Store);
  Assert.AreEqual(0, Store.ReadInteger('WelcomePageTests', 1), 'Registry-Name');
  Assert.AreEqual(12, Store.ReadInteger('WelcomePageTestsMaxFailures', 0));
  Assert.AreEqual(1, Store.ReadInteger('WelcomePageTestsCi', 0));
  Assert.AreEqual('jenkins', Store.ReadString('WelcomePageTestsCiProvider', ''));
  Assert.AreEqual(30, Store.ReadInteger('WelcomePageTestsCiIntervalMinutes', 0));
  Assert.AreEqual(0, Store.ReadInteger('WelcomePageTestsCiNotify', 1));
  Assert.AreEqual(0, Store.ReadInteger('CiLogin', 1));
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.WelcomePageTests);
  Assert.AreEqual(12, Loaded.WelcomePageTestsMaxFailures);
  Assert.IsTrue(Loaded.WelcomePageTestsCi);
  Assert.AreEqual(30, Loaded.WelcomePageTestsCiIntervalMinutes);
  Assert.IsFalse(Loaded.WelcomePageTestsCiNotify);
  Assert.IsFalse(Loaded.CiLogin);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeTestResultsTests);
  TDUnitX.RegisterTestFixture(TAtlasTestResultsSettingsTests);

end.
