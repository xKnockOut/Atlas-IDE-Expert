unit Atlas.Core.Projects.Summary.Tests;

// Tests der Projekt-Zusammenfassung (#592): Schlüssel und Dateiname, Zeiten,
// Lesen und Schreiben aller Felder, unbekannte Felder bleiben erhalten (auch
// in bekannten Abschnitten), höheres Format wird weder gelesen noch
// überschrieben, Update über die Platte.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasProjectSummaryTests = class
  private
    FFolder: string;
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure KeyIsStableAndIgnoresCaseAndSlashes;
    [Test]
    procedure FileNameUsesKey;
    [Test]
    procedure TimeRoundTrip;
    [Test]
    procedure InvalidTimeGivesZero;
    [Test]
    procedure ParsesAllFields;
    [Test]
    procedure WriteAndReadRoundTrip;
    [Test]
    procedure KeepsUnknownFields;
    [Test]
    procedure MissingSectionsStayUnknown;
    [Test]
    procedure RejectsInvalidAndNewerFormat;
    [Test]
    procedure SaveAndLoadOnDisk;
    [Test]
    procedure SaveKeepsNewerFormatFile;
    /// <summary>Unbrauchbare Datei liegt danach als .defekt daneben; eine beim Lesen gesperrte wird nicht
    /// überschrieben.</summary>
    [Test]
    procedure BrokenFileSetAsideLockedFileKept;
    [Test]
    procedure UpdateCreatesAndChanges;
    [Test]
    procedure NameWithoutExtension;
    [Test]
    procedure MetricsFromServerAndRoundTrip;
    [Test]
    procedure MetricsRejectInvalidAnswer;
    [Test]
    procedure TodosFromServerAndRoundTrip;
    [Test]
    procedure TodosRejectInvalidAnswer;
    /// <summary>Abschnitt "baseline" (#97) für Projektverlauf (#758) und Einrichtung (#759).</summary>
    [Test]
    procedure BaselineRoundTripAndUnknownFields;
    [Test]
    procedure SetupRoundTripAndLimits;
    /// <summary>#759: unsichere Funde und übersprungene Makros (Suchpfad mit unbekanntem Makro).</summary>
    [Test]
    procedure SetupKeepsUncertainFindings;
    /// <summary>#69: letzter Testlauf für die Karte Tests (#763) und „Fehlgeschlagene erneut ausführen“.</summary>
    [Test]
    procedure TestsRoundTripAndLimits;
    /// <summary>#1455: Das Modul Tests liest die fehlgeschlagenen Tests ohne die Willkommensseite.</summary>
    [Test]
    procedure FailedTestsOfStoredRun;
    [Test]
    procedure SlowestRoundTripAndLimit;
    /// <summary>#533: Release-Wächter, letzte Prüfung und Versionen je Konfiguration und Plattform.</summary>
    [Test]
    procedure ReleaseRoundTripAndRemember;
    /// <summary>#763: letzter Abruf vom Build-Server samt Testbericht; unbekannte Felder bleiben.</summary>
    [Test]
    procedure CiRoundTripAndMatches;
    /// <summary>Feldleser und Abschnitte ohne Datei: fehlende Abschnitte bleiben unbekannt.</summary>
    [Test]
    procedure FieldHelpersAndSectionsWithoutObject;
  end;

implementation

uses
  System.DateUtils,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Projects.Summary.Json,
  Atlas.Core.Projects.Summary.Sections,
  Atlas.Text.Json;

const
  cProject = 'C:\Projekte\Demo.dproj';
  cFull =
    '{"format": 1, "project": "C:\\Projekte\\Demo.dproj",' +
    ' "lastOpened": "2026-10-14T08:15:00Z", "lastClosed": "2026-10-14T17:45:30Z", "hidden": true,' +
    ' "vcs": {"at": "2026-10-14T17:45:31Z", "kind": "git", "branch": "main", "revision": "0123456789abcdef",' +
    '   "changed": 3, "ahead": 1, "behind": 2},' +
    ' "build": {"at": "2026-10-14T16:00:00Z", "kind": "build", "configuration": "Debug", "platform": "Win32",' +
    '   "succeeded": false, "errors": 2, "warnings": 1, "hints": 4,' +
    '   "first": {"file": "C:\\Projekte\\Main.pas", "line": 12, "column": 5, "code": "E2003", "text": "x"}},' +
    ' "check": {"at": "2026-10-14T16:30:00Z", "errors": 1,' +
    '   "first": {"file": "C:\\Projekte\\Unit2.pas", "line": 7, "column": 1}},' +
    ' "rules": {"at": "2026-10-14T16:31:00Z", "newHits": 5}}';

function At(AYear, AMonth, ADay, AHour, AMinute, ASecond: Word): TDateTime;
begin
  Result := EncodeDate(AYear, AMonth, ADay) + EncodeTime(AHour, AMinute, ASecond, 0);
end;

/// <summary>Gleich bis auf eine halbe Sekunde.</summary>
function SameTime(A, B: TDateTime): Boolean;
begin
  Result := Abs(A - B) < 1 / 86400 / 2;
end;

{ TAtlasProjectSummaryTests }

procedure TAtlasProjectSummaryTests.WarmUpFirstUse;
begin
  Setup;
  try
    KeyIsStableAndIgnoresCaseAndSlashes;
  finally
    TearDown;
  end;
  // Gesperrte Datei: Erstgebrauch der Melde- und Fehlerpfade.
  Setup;
  try
    BrokenFileSetAsideLockedFileKept;
  finally
    TearDown;
  end;
end;

procedure TAtlasProjectSummaryTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasProjects' + IntToStr(Random(1000000)));
end;

procedure TAtlasProjectSummaryTests.TearDown;
begin
  if DirectoryExists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  // Der Leckmonitor misst den Saldo von Setup und TearDown.
  FFolder := '';
end;

procedure TAtlasProjectSummaryTests.KeyIsStableAndIgnoresCaseAndSlashes;
begin
  // Festgeschrieben: Spätere Bereiche (#755, #758 …) und Werkzeuge rechnen denselben Schlüssel.
  Assert.AreEqual('cea7b8ab83412c7a', TAtlasProjectSummaries.KeyOf(cProject));
  Assert.AreEqual('cea7b8ab83412c7a', TAtlasProjectSummaries.KeyOf(' c:/projekte/demo.dproj '));
  // Nur ASCII-Buchstaben werden groß; Umlaute zählen wie geschrieben.
  Assert.AreEqual('dfab3d8087a2e100', TAtlasProjectSummaries.KeyOf('C:\Projekte\Über.dproj'));
  Assert.AreNotEqual(TAtlasProjectSummaries.KeyOf(cProject), TAtlasProjectSummaries.KeyOf('C:\Projekte\Demo.dpr'));
  Assert.AreEqual('C:\PROJEKTE\DEMO.DPROJ', TAtlasProjectSummaries.NormalizedPath('c:/Projekte/Demo.dproj'));
end;

procedure TAtlasProjectSummaryTests.FileNameUsesKey;
begin
  Assert.AreEqual(IncludeTrailingPathDelimiter(FFolder) + 'cea7b8ab83412c7a.json',
    TAtlasProjectSummaries.FileFor(FFolder, cProject));
end;

procedure TAtlasProjectSummaryTests.TimeRoundTrip;
var
  mValue: TDateTime;
begin
  mValue := At(2026, 10, 15, 9, 30, 5);
  Assert.AreEqual('2026-10-15T09:30:05Z', TAtlasProjectSummaries.TimeText(mValue));
  Assert.IsTrue(SameTime(mValue, TAtlasProjectSummaries.TimeOf('2026-10-15T09:30:05Z')));
  Assert.IsTrue(SameTime(mValue, TAtlasProjectSummaries.TimeOf('2026-10-15T09:30:05.123Z')), 'Bruchteile');
  Assert.AreEqual('', TAtlasProjectSummaries.TimeText(0));
end;

procedure TAtlasProjectSummaryTests.InvalidTimeGivesZero;
begin
  Assert.AreEqual<TDateTime>(0, TAtlasProjectSummaries.TimeOf(''));
  Assert.AreEqual<TDateTime>(0, TAtlasProjectSummaries.TimeOf('gestern'));
  Assert.AreEqual<TDateTime>(0, TAtlasProjectSummaries.TimeOf('2026-13-40T25:00:00Z'));
end;

procedure TAtlasProjectSummaryTests.ParsesAllFields;
var
  mSummary: TAtlasProjectSummary;
begin
  Assert.IsTrue(TAtlasProjectSummaries.Parse(cFull, mSummary));
  Assert.AreEqual(cProject, mSummary.Project);
  Assert.IsTrue(SameTime(At(2026, 10, 14, 8, 15, 0), mSummary.LastOpened));
  Assert.IsTrue(SameTime(At(2026, 10, 14, 17, 45, 30), mSummary.LastClosed));
  Assert.IsTrue(mSummary.Hidden);
  Assert.IsTrue(mSummary.Vcs.Known);
  Assert.IsTrue(mSummary.Vcs.InWorkingCopy);
  Assert.AreEqual('git', mSummary.Vcs.Kind);
  Assert.AreEqual('main', mSummary.Vcs.Branch);
  Assert.AreEqual('0123456789abcdef', mSummary.Vcs.Revision);
  Assert.AreEqual(3, mSummary.Vcs.Changed);
  Assert.AreEqual(1, mSummary.Vcs.Ahead);
  Assert.AreEqual(2, mSummary.Vcs.Behind);
  Assert.IsTrue(mSummary.Build.Known);
  Assert.AreEqual('build', mSummary.Build.Kind);
  Assert.AreEqual('Debug', mSummary.Build.Configuration);
  Assert.AreEqual('Win32', mSummary.Build.Platform);
  Assert.IsFalse(mSummary.Build.Succeeded);
  Assert.AreEqual(2, mSummary.Build.Errors);
  Assert.AreEqual(1, mSummary.Build.Warnings);
  Assert.AreEqual(4, mSummary.Build.Hints);
  Assert.AreEqual('C:\Projekte\Main.pas', mSummary.Build.First.FileName);
  Assert.AreEqual(12, mSummary.Build.First.Line);
  Assert.AreEqual(5, mSummary.Build.First.Column);
  Assert.AreEqual('E2003', mSummary.Build.First.Code);
  Assert.AreEqual('x', mSummary.Build.First.Text);
  Assert.IsTrue(mSummary.Check.Known);
  Assert.AreEqual(1, mSummary.Check.Errors);
  Assert.AreEqual('C:\Projekte\Unit2.pas', mSummary.Check.First.FileName);
  Assert.AreEqual(7, mSummary.Check.First.Line);
  Assert.IsTrue(mSummary.Rules.Known);
  Assert.AreEqual(5, mSummary.Rules.NewHits);
end;

procedure TAtlasProjectSummaryTests.WriteAndReadRoundTrip;
var
  mSummary, mRead: TAtlasProjectSummary;
begin
  mSummary := TAtlasProjectSummary.Create(cProject);
  mSummary.LastOpened := At(2026, 10, 15, 7, 0, 0);
  mSummary.Vcs := TAtlasProjectVcs.Empty;
  mSummary.Vcs.Known := True;
  mSummary.Vcs.At := At(2026, 10, 15, 7, 0, 1);
  mSummary.Vcs.Kind := 'svn';
  mSummary.Vcs.Branch := 'branches/x';
  mSummary.Vcs.Revision := '42';
  mSummary.Vcs.Changed := 0;
  mSummary.Build.Known := True;
  mSummary.Build.At := At(2026, 10, 15, 7, 5, 0);
  mSummary.Build.Kind := 'make';
  mSummary.Build.Succeeded := True;
  mSummary.Build.Configuration := 'Release';
  mSummary.Build.Platform := 'Win64';
  Assert.IsTrue(TAtlasProjectSummaries.Parse(TAtlasProjectSummaries.ToJson(mSummary), mRead));
  Assert.AreEqual(cProject, mRead.Project);
  Assert.IsTrue(SameTime(mSummary.LastOpened, mRead.LastOpened));
  Assert.AreEqual<TDateTime>(0, mRead.LastClosed, 'nicht geschrieben');
  Assert.IsFalse(mRead.Hidden);
  Assert.AreEqual('svn', mRead.Vcs.Kind);
  Assert.AreEqual('branches/x', mRead.Vcs.Branch);
  Assert.AreEqual(0, mRead.Vcs.Changed);
  Assert.AreEqual(-1, mRead.Vcs.Ahead, 'SVN kennt keinen Upstream');
  Assert.IsTrue(mRead.Build.Succeeded);
  Assert.AreEqual('Release', mRead.Build.Configuration);
  Assert.AreEqual(0, mRead.Build.Errors);
  Assert.IsTrue(mRead.Build.First.IsEmpty);
  Assert.IsFalse(mRead.Check.Known);
  Assert.IsFalse(mRead.Rules.Known);
  Assert.AreEqual(1, TAtlasProjectSummaries.FormatOf(TAtlasProjectSummaries.ToJson(mSummary)));
end;

procedure TAtlasProjectSummaryTests.KeepsUnknownFields;
var
  mSummary: TAtlasProjectSummary;
  mRoot: TJSONObject;
  mBuild, mHistory: TJSONValue;
begin
  // Felder späterer Fassungen (#758: Messpunkte je Build) überstehen das Schreiben durch diese Fassung.
  Assert.IsTrue(TAtlasProjectSummaries.Parse(
    '{"format": 1, "project": "C:\\P.dproj", "history": [{"at": "2026-10-01T00:00:00Z", "todos": 3}],' +
    ' "build": {"at": "2026-10-01T00:00:00Z", "kind": "build", "succeeded": true, "errors": 0,' +
    ' "warnings": 0, "hints": 0, "metrics": {"lines": 1200}}}', mSummary));
  mSummary.Build.Errors := 2;
  mSummary.Build.Succeeded := False;
  mRoot := TJSONObject.ParseJSONValue(TAtlasProjectSummaries.ToJson(mSummary)) as TJSONObject;
  try
    mHistory := mRoot.GetValue('history');
    Assert.IsTrue(mHistory is TJSONArray, 'unbekanntes Feld oben');
    Assert.AreEqual(1, Integer(TJSONArray(mHistory).Count));
    mBuild := mRoot.GetValue('build');
    Assert.IsTrue(mBuild is TJSONObject);
    Assert.IsTrue(TJSONObject(mBuild).GetValue('metrics') is TJSONObject, 'unbekanntes Feld im Abschnitt');
    Assert.AreEqual('2', TJSONObject(mBuild).GetValue('errors').Value, 'bekanntes Feld neu geschrieben');
    Assert.AreEqual(9, Integer(TJSONObject(mBuild).Count), 'acht bekannte Felder und metrics, errors nur einmal');
  finally
    mRoot.Free;
  end;
end;

procedure TAtlasProjectSummaryTests.MissingSectionsStayUnknown;
var
  mSummary: TAtlasProjectSummary;
begin
  // Ohne "format" gilt Format 1.
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"project": "C:\\P.dproj"}', mSummary));
  Assert.IsFalse(mSummary.Vcs.Known);
  Assert.IsFalse(mSummary.Vcs.InWorkingCopy);
  Assert.AreEqual(-1, mSummary.Vcs.Changed);
  Assert.IsFalse(mSummary.Build.Known);
  Assert.IsFalse(mSummary.Check.Known);
  Assert.IsFalse(mSummary.Rules.Known);
  Assert.IsFalse(mSummary.Metrics.Known);
  Assert.IsFalse(mSummary.Todos.Known);
  Assert.IsFalse(mSummary.Baseline.Known);
  Assert.IsFalse(mSummary.Tests.Known);
  Assert.IsFalse(mSummary.Release.Known);
  Assert.IsFalse(mSummary.Ci.Known);
  Assert.IsFalse(mSummary.Ci.HasBuild);
  Assert.AreEqual<TDateTime>(0, mSummary.LastOpened);
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"project": "C:\\P.dproj", "vcs": {"kind": "none"}}', mSummary));
  Assert.IsTrue(mSummary.Vcs.Known);
  Assert.IsFalse(mSummary.Vcs.InWorkingCopy, 'ohne Arbeitskopie');
end;

procedure TAtlasProjectSummaryTests.RejectsInvalidAndNewerFormat;
var
  mSummary: TAtlasProjectSummary;
begin
  Assert.IsFalse(TAtlasProjectSummaries.Parse('', mSummary));
  Assert.IsFalse(TAtlasProjectSummaries.Parse('kein json', mSummary));
  Assert.IsFalse(TAtlasProjectSummaries.Parse('[1, 2]', mSummary));
  Assert.IsFalse(TAtlasProjectSummaries.Parse('{"format": 2, "project": "C:\\P.dproj"}', mSummary));
  Assert.AreEqual('', mSummary.Project, 'leer nach Ablehnung');
  Assert.AreEqual(2, TAtlasProjectSummaries.FormatOf('{"format": 2}'));
  Assert.AreEqual(0, TAtlasProjectSummaries.FormatOf('kein json'));
end;

procedure TAtlasProjectSummaryTests.SaveAndLoadOnDisk;
var
  mSummary, mLoaded: TAtlasProjectSummary;
  mBytes: TBytes;
begin
  Assert.IsFalse(TAtlasProjectSummaries.Load(FFolder, cProject, mLoaded), 'noch keine Datei');
  Assert.AreEqual(cProject, mLoaded.Project);
  mSummary := TAtlasProjectSummary.Create(cProject);
  mSummary.Check.Known := True;
  mSummary.Check.Errors := 3;
  mSummary.Check.At := At(2026, 10, 15, 8, 0, 0);
  Assert.IsTrue(TAtlasProjectSummaries.Save(FFolder, mSummary), 'legt den Ordner an');
  Assert.IsTrue(FileExists(TAtlasProjectSummaries.FileFor(FFolder, cProject)));
  Assert.IsFalse(FileExists(TAtlasProjectSummaries.FileFor(FFolder, cProject) + '.tmp'), 'keine Reste');
  mBytes := TFile.ReadAllBytes(TAtlasProjectSummaries.FileFor(FFolder, cProject));
  Assert.AreEqual(Ord('{'), Integer(mBytes[0]), 'UTF-8 ohne BOM');
  Assert.IsTrue(TAtlasProjectSummaries.Load(FFolder, 'c:/projekte/demo.dproj', mLoaded), 'andere Schreibweise');
  Assert.AreEqual(cProject, mLoaded.Project, 'gespeicherter Pfad');
  Assert.AreEqual(3, mLoaded.Check.Errors);
  // Zweites Speichern ersetzt die Datei.
  mLoaded.Check.Errors := 0;
  Assert.IsTrue(TAtlasProjectSummaries.Save(FFolder, mLoaded));
  Assert.IsTrue(TAtlasProjectSummaries.Load(FFolder, cProject, mLoaded));
  Assert.AreEqual(0, mLoaded.Check.Errors);
end;

procedure TAtlasProjectSummaryTests.SaveKeepsNewerFormatFile;
var
  mSummary: TAtlasProjectSummary;
  mFileName, mNewer: string;
begin
  ForceDirectories(FFolder);
  mFileName := TAtlasProjectSummaries.FileFor(FFolder, cProject);
  mNewer := '{"format": 2, "project": "C:\\Projekte\\Demo.dproj", "neu": true}';
  TFile.WriteAllText(mFileName, mNewer);
  Assert.IsFalse(TAtlasProjectSummaries.Load(FFolder, cProject, mSummary), 'höheres Format nicht lesen');
  mSummary.Hidden := True;
  Assert.IsFalse(TAtlasProjectSummaries.Save(FFolder, mSummary), 'und nicht überschreiben');
  Assert.IsFalse(TAtlasProjectSummaries.Update(FFolder, cProject,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      ASummary.Hidden := True;
    end));
  Assert.AreEqual(2, TAtlasProjectSummaries.FormatOf(TFile.ReadAllText(mFileName, TEncoding.UTF8)));
end;

procedure TAtlasProjectSummaryTests.UpdateCreatesAndChanges;
var
  mSummary: TAtlasProjectSummary;
begin
  Assert.IsTrue(TAtlasProjectSummaries.Update(FFolder, cProject,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      ASummary.LastOpened := At(2026, 10, 15, 6, 0, 0);
      ASummary.Hidden := True;
    end));
  Assert.IsTrue(TAtlasProjectSummaries.Update(FFolder, cProject,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      Assert.IsTrue(ASummary.Hidden, 'liest den gespeicherten Stand');
      ASummary.Hidden := False;
      ASummary.LastClosed := At(2026, 10, 15, 9, 0, 0);
    end));
  Assert.IsTrue(TAtlasProjectSummaries.Load(FFolder, cProject, mSummary));
  Assert.IsFalse(mSummary.Hidden);
  Assert.IsTrue(SameTime(At(2026, 10, 15, 6, 0, 0), mSummary.LastOpened));
  Assert.IsTrue(SameTime(At(2026, 10, 15, 9, 0, 0), mSummary.LastClosed));
  Assert.IsFalse(TAtlasProjectSummaries.Update(FFolder, '', nil), 'ohne Projekt');
end;

procedure TAtlasProjectSummaryTests.NameWithoutExtension;
begin
  Assert.AreEqual('Demo', TAtlasProjectSummary.Create(cProject).Name);
  Assert.AreEqual('Gruppe', TAtlasProjectSummary.Create('C:\G\Gruppe.groupproj').Name);
  Assert.AreEqual('Atlas.IDE.Expert', TAtlasProjectSummary.Create('C:\A\Atlas.IDE.Expert.dpk').Name);
end;

procedure TAtlasProjectSummaryTests.MetricsFromServerAndRoundTrip;
const
  // Antwort von atlas.server.metrics im Modus "summary" (#66).
  cAnswer = '{"format": 1, "limits": {"length": 60, "nesting": 4, "cyclomatic": 15, "cognitive": 15, ' +
    '"parameters": 6}, "summary": {"files": 2, "methods": 3, "overLimits": 1, ' +
    '"average": {"length": 30.3, "nesting": 2.0, "cyclomatic": 6.7, "cognitive": 7.0, "parameters": 3.0}, ' +
    '"maximum": {"length": 75, "nesting": 5, "cyclomatic": 17, "cognitive": 20, "parameters": 7}, ' +
    '"exceeded": {"length": 1, "nesting": 1, "cyclomatic": 1, "cognitive": 1, "parameters": 1}}}';
var
  mMetrics: TAtlasProjectMetrics;
  mSummary, mRead: TAtlasProjectSummary;
  mStamp: TDateTime;
  mJson: string;
begin
  mStamp := EncodeDate(2026, 10, 15) + EncodeTime(9, 30, 0, 0);
  Assert.IsTrue(TAtlasProjectMetrics.FromServer(cAnswer, mStamp, mMetrics));
  Assert.IsTrue(mMetrics.Known);
  Assert.AreEqual<TDateTime>(mStamp, mMetrics.At, 'Zeitpunkt des Builds');
  Assert.AreEqual(2, mMetrics.Files);
  Assert.AreEqual(3, mMetrics.Methods);
  Assert.AreEqual(1, mMetrics.OverLimits);
  Assert.AreEqual(303, mMetrics.AverageTenths[0], 'mittlere Methodenlänge für den Projektverlauf (#758)');
  Assert.AreEqual(67, mMetrics.AverageTenths[2]);
  Assert.AreEqual(75, mMetrics.Maximum[0]);
  Assert.AreEqual(1, mMetrics.Exceeded[4]);
  mSummary := TAtlasProjectSummary.Create(cProject);
  mSummary.Metrics := mMetrics;
  mJson := TAtlasProjectSummaries.ToJson(mSummary);
  Assert.Contains(mJson, '"metrics":{"at":"2026-10-15T09:30:00Z","files":2,"methods":3,"overLimits":1');
  Assert.Contains(mJson, '"average":{"length":30.3');
  Assert.Contains(mJson, '"maximum":{"length":75');
  Assert.IsTrue(TAtlasProjectSummaries.Parse(mJson, mRead));
  Assert.IsTrue(mRead.Metrics.Known);
  Assert.AreEqual(303, mRead.Metrics.AverageTenths[0]);
  Assert.AreEqual(20, mRead.Metrics.Maximum[3]);
  Assert.AreEqual<TDateTime>(mStamp, mRead.Metrics.At);
  // Unbekannte Felder im Abschnitt bleiben (z. B. eine Verlaufsreihe aus #758).
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"project": "C:\\P.dproj", "metrics": {"methods": 1, ' +
    '"history": [1, 2]}}', mRead));
  Assert.Contains(TAtlasProjectSummaries.ToJson(mRead), '"history":[1,2]');
end;

procedure TAtlasProjectSummaryTests.MetricsRejectInvalidAnswer;
var
  mMetrics: TAtlasProjectMetrics;
begin
  Assert.IsFalse(TAtlasProjectMetrics.FromServer('', 0, mMetrics));
  Assert.IsFalse(TAtlasProjectMetrics.FromServer('"# Bericht"', 0, mMetrics));
  Assert.IsFalse(TAtlasProjectMetrics.FromServer('{"summary": {"files": 1}}', 0, mMetrics));
  Assert.IsFalse(mMetrics.Known);
end;

procedure TAtlasProjectSummaryTests.TodosFromServerAndRoundTrip;
const
  // Antwort von atlas.server.todos im Modus "summary" (#68).
  cAnswer = '{"format": 1, "summary": {"files": 2, "open": 5, "done": 1, "keywords": {"FIXME": 2, "TODO": 3}}}';
var
  mTodos: TAtlasProjectTodos;
  mSummary, mRead: TAtlasProjectSummary;
  mStamp: TDateTime;
  mJson: string;
begin
  mStamp := EncodeDate(2026, 10, 15) + EncodeTime(9, 30, 0, 0);
  Assert.IsTrue(TAtlasProjectTodos.FromServer(cAnswer, mStamp, mTodos));
  Assert.IsTrue(mTodos.Known);
  Assert.AreEqual<TDateTime>(mStamp, mTodos.At, 'Zeitpunkt des Builds');
  Assert.AreEqual(2, mTodos.Files);
  Assert.AreEqual(5, mTodos.Open, 'Reihe „offene TODOs“ des Projektverlaufs (#758)');
  Assert.AreEqual(1, mTodos.Done);
  Assert.AreEqual(2, mTodos.CountOf('fixme'));
  Assert.AreEqual(0, mTodos.CountOf('HACK'));
  mSummary := TAtlasProjectSummary.Create(cProject);
  Assert.IsFalse(mSummary.Todos.Known);
  mSummary.Todos := mTodos;
  mJson := TAtlasProjectSummaries.ToJson(mSummary);
  Assert.Contains(mJson, '"todos":{"at":"2026-10-15T09:30:00Z","files":2,"open":5,"done":1,' +
    '"keywords":{"FIXME":2,"TODO":3}}');
  Assert.IsTrue(TAtlasProjectSummaries.Parse(mJson, mRead));
  Assert.IsTrue(mRead.Todos.Known);
  Assert.AreEqual(5, mRead.Todos.Open);
  Assert.AreEqual(3, mRead.Todos.CountOf('TODO'));
  Assert.AreEqual<TDateTime>(mStamp, mRead.Todos.At);
  // Ohne Abschnitt bleibt er unbekannt; unbekannte Felder im Abschnitt bleiben.
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"project": "C:\\P.dproj"}', mRead));
  Assert.IsFalse(mRead.Todos.Known);
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"project": "C:\\P.dproj", "todos": {"open": 0, ' +
    '"history": [3, 0]}}', mRead));
  Assert.IsTrue(mRead.Todos.Known);
  Assert.AreEqual(0, mRead.Todos.Open);
  Assert.Contains(TAtlasProjectSummaries.ToJson(mRead), '"history":[3,0]');
end;

procedure TAtlasProjectSummaryTests.TestsRoundTripAndLimits;
var
  mSummary, mRead: TAtlasProjectSummary;
  mFailure: TAtlasProjectTestFailure;
  mIndex: Integer;
  mJson: string;
  mNames: TArray<string>;
begin
  mSummary := TAtlasProjectSummary.Create(cProject);
  mSummary.Tests.Known := True;
  mSummary.Tests.At := At(2026, 10, 16, 10, 0, 0);
  mSummary.Tests.Project := 'C:\Projekte\Demo.Tests.dproj';
  mSummary.Tests.Configuration := 'Debug';
  mSummary.Tests.Platform := 'Win64';
  mSummary.Tests.Passed := 40;
  mSummary.Tests.Failed := 1;
  mSummary.Tests.Errors := 1;
  mSummary.Tests.Skipped := 2;
  mSummary.Tests.DurationMs := 1250;
  mFailure := Default(TAtlasProjectTestFailure);
  mFailure.Test := 'Demo.Tests.TRechner.Summe.Gross';
  mFailure.Message := 'Erwartet: 30, erhalten: 31';
  mFailure.FileName := 'C:\Projekte\Demo.Tests.pas';
  mFailure.Line := 35;
  mSummary.Tests.Failures := [mFailure, mFailure];
  mFailure := Default(TAtlasProjectTestFailure);
  mFailure.Test := 'Demo.Tests.TRechner.Teilt';
  mSummary.Tests.Failures := mSummary.Tests.Failures + [mFailure];
  Assert.AreEqual(44, mSummary.Tests.Total);
  mJson := TAtlasProjectSummaries.ToJson(mSummary);
  Assert.Contains(mJson, '"tests":{"at":"2026-10-16T10:00:00Z","project":"C:\\Projekte\\Demo.Tests.dproj",' +
    '"configuration":"Debug","platform":"Win64","passed":40,"failed":1,"errors":1,"skipped":2,"durationMs":1250,' +
    '"failures":[{"test":"Demo.Tests.TRechner.Summe.Gross","message":"Erwartet: 30, erhalten: 31",' +
    '"file":"C:\\Projekte\\Demo.Tests.pas","line":35}');
  Assert.Contains(mJson, '{"test":"Demo.Tests.TRechner.Teilt"}', 'ohne Meldung und Fundstelle nur der Name');
  Assert.IsTrue(TAtlasProjectSummaries.Parse(mJson, mRead));
  Assert.IsTrue(mRead.Tests.Known);
  Assert.AreEqual('Win64', mRead.Tests.Platform);
  Assert.AreEqual(1250, mRead.Tests.DurationMs);
  Assert.AreEqual(3, Integer(Length(mRead.Tests.Failures)));
  Assert.AreEqual(35, mRead.Tests.Failures[0].Line);
  Assert.AreEqual('C:\Projekte\Demo.Tests.pas', mRead.Tests.Failures[0].FileName);
  mNames := mRead.Tests.FailedTests;
  Assert.AreEqual(2, Integer(Length(mNames)), 'erneut ausführen: jeder Test einmal');
  Assert.AreEqual('Demo.Tests.TRechner.Summe.Gross', mNames[0]);
  Assert.AreEqual('Demo.Tests.TRechner.Teilt', mNames[1]);
  // Höchstens MaxFailures in der Datei; unbekannte Felder bleiben.
  mSummary.Tests.Failures := nil;
  for mIndex := 1 to TAtlasProjectTests.cMaxFailures + 5 do
  begin
    mFailure.Test := 'Demo.Tests.T.M' + IntToStr(mIndex);
    mSummary.Tests.Failures := mSummary.Tests.Failures + [mFailure];
  end;
  Assert.IsTrue(TAtlasProjectSummaries.Parse(TAtlasProjectSummaries.ToJson(mSummary), mRead));
  Assert.AreEqual(TAtlasProjectTests.cMaxFailures, Integer(Length(mRead.Tests.Failures)));
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"project": "C:\\P.dproj", "tests": {"passed": 3, "jenkins": ' +
    '{"job": "x"}}}', mRead));
  Assert.IsTrue(mRead.Tests.Known);
  Assert.AreEqual(3, mRead.Tests.Passed);
  Assert.Contains(TAtlasProjectSummaries.ToJson(mRead), '"jenkins":{"job":"x"}');
end;

procedure TAtlasProjectSummaryTests.SlowestRoundTripAndLimit;
var
  mSummary, mRead: TAtlasProjectSummary;
  mSlow: TAtlasProjectSlowTest;
  mIndex: Integer;
  mJson: string;
begin
  mSummary := TAtlasProjectSummary.Create(cProject);
  mSummary.Tests.Known := True;
  mSummary.Tests.Project := 'C:\Projekte\Demo.Tests.dproj';
  mSlow := Default(TAtlasProjectSlowTest);
  mSlow.Test := 'Demo.Tests.TRechner.Laden';
  mSlow.FileName := 'C:\Projekte\Demo.Tests.pas';
  mSlow.Line := 50;
  mSlow.DurationMs := 820;
  mSummary.Tests.Slowest := [mSlow];
  mJson := TAtlasProjectSummaries.ToJson(mSummary);
  Assert.Contains(mJson, '"slowest":[{"test":"Demo.Tests.TRechner.Laden","file":"C:\\Projekte\\Demo.Tests.pas",' +
    '"line":50,"durationMs":820}]');
  Assert.IsTrue(TAtlasProjectSummaries.Parse(mJson, mRead));
  Assert.AreEqual(1, Integer(Length(mRead.Tests.Slowest)));
  Assert.AreEqual('Demo.Tests.TRechner.Laden', mRead.Tests.Slowest[0].Test);
  Assert.AreEqual(50, mRead.Tests.Slowest[0].Line);
  Assert.AreEqual(820, mRead.Tests.Slowest[0].DurationMs);
  // Höchstens cMaxSlowest; ohne Liste kein Eintrag "slowest".
  mSummary.Tests.Slowest := nil;
  Assert.DoesNotContain(TAtlasProjectSummaries.ToJson(mSummary), '"slowest"');
  for mIndex := 1 to TAtlasProjectTests.cMaxSlowest + 2 do
  begin
    mSlow.Test := 'Demo.Tests.T.M' + IntToStr(mIndex);
    mSummary.Tests.Slowest := mSummary.Tests.Slowest + [mSlow];
  end;
  Assert.IsTrue(TAtlasProjectSummaries.Parse(TAtlasProjectSummaries.ToJson(mSummary), mRead));
  Assert.AreEqual(TAtlasProjectTests.cMaxSlowest, Integer(Length(mRead.Tests.Slowest)));
end;

procedure TAtlasProjectSummaryTests.FailedTestsOfStoredRun;
const
  cTestProject = 'C:\Projekte\Demo.Tests.dproj';
var
  mSummary: TAtlasProjectSummary;
  mFailure: TAtlasProjectTestFailure;
  mNames: TArray<string>;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasProjectSummaries.FailedTestsOf(FFolder, cTestProject))), 'ohne Datei');
  mSummary := TAtlasProjectSummary.Create(cTestProject);
  mSummary.Tests.Known := True;
  mSummary.Tests.Project := cTestProject;
  mSummary.Tests.Failed := 1;
  mFailure := Default(TAtlasProjectTestFailure);
  mFailure.Test := 'Demo.Tests.TRechner.Teilt';
  mSummary.Tests.Failures := [mFailure, mFailure];
  Assert.IsTrue(TAtlasProjectSummaries.Save(FFolder, mSummary));
  mNames := TAtlasProjectSummaries.FailedTestsOf(FFolder, 'c:\projekte\demo.tests.dproj');
  Assert.AreEqual(1, Integer(Length(mNames)), 'andere Schreibweise, jeder Test einmal');
  Assert.AreEqual('Demo.Tests.TRechner.Teilt', mNames[0]);
  Assert.AreEqual(0, Integer(Length(TAtlasProjectSummaries.FailedTestsOf(FFolder, ''))), 'ohne Projekt');
  // Der Lauf gehört zu einem anderen Testprojekt (Gruppe, #69): nichts.
  mSummary.Tests.Project := 'C:\Projekte\Andere.Tests.dproj';
  Assert.IsTrue(TAtlasProjectSummaries.Save(FFolder, mSummary));
  Assert.AreEqual(0, Integer(Length(TAtlasProjectSummaries.FailedTestsOf(FFolder, cTestProject))));
  Assert.Contains(TAtlasProjectSummaries.DefaultFolder, TAtlasProjectSummaries.cFolderName);
end;

procedure TAtlasProjectSummaryTests.ReleaseRoundTripAndRemember;
var
  mSummary, mRead: TAtlasProjectSummary;
  mJson: string;
  mIndex: Integer;
begin
  mSummary := TAtlasProjectSummary.Create(cProject);
  Assert.AreEqual('', mSummary.Release.VersionOf('Release', 'Win64'));
  mSummary.Release.Remember('Release', 'Win32', '1.0.0.0', At(2026, 10, 1, 8, 0, 0));
  mSummary.Release.Remember('Release', 'Win64', '1.1.0.0', At(2026, 10, 2, 8, 0, 0));
  mSummary.Release.Remember('release', 'WIN32', '1.2.0.0', At(2026, 10, 3, 8, 0, 0));
  Assert.IsTrue(mSummary.Release.Known);
  Assert.AreEqual(2, Integer(Length(mSummary.Release.Builds)), 'je Konfiguration und Plattform ein Eintrag');
  Assert.AreEqual('1.2.0.0', mSummary.Release.VersionOf('Release', 'Win32'));
  Assert.AreEqual('1.1.0.0', mSummary.Release.VersionOf('Release', 'Win64'));
  Assert.AreEqual('', mSummary.Release.VersionOf('Ship', 'Win64'));
  mJson := TAtlasProjectSummaries.ToJson(mSummary);
  Assert.Contains(mJson, '"release":{"builds":[{"configuration":"release","platform":"WIN32","version":"1.2.0.0",' +
    '"at":"2026-10-03T08:00:00Z"},{"configuration":"Release","platform":"Win64","version":"1.1.0.0",' +
    '"at":"2026-10-02T08:00:00Z"}]}', 'ohne Prüfung nur die Builds');
  mSummary.Release.CheckedAt := At(2026, 10, 16, 9, 0, 0);
  mSummary.Release.Configuration := 'Release';
  mSummary.Release.Platform := 'Win64';
  mSummary.Release.Findings := 2;
  mSummary.Release.Blocked := True;
  mSummary.Release.Rules := ['release-debug-define', 'release-assertions'];
  mJson := TAtlasProjectSummaries.ToJson(mSummary);
  Assert.Contains(mJson, '"release":{"checkedAt":"2026-10-16T09:00:00Z","configuration":"Release",' +
    '"platform":"Win64","findings":2,"blocked":true,"rules":["release-debug-define","release-assertions"],');
  Assert.IsTrue(TAtlasProjectSummaries.Parse(mJson, mRead));
  Assert.IsTrue(mRead.Release.Known);
  Assert.IsTrue(mRead.Release.Blocked);
  Assert.AreEqual(2, mRead.Release.Findings);
  Assert.AreEqual(2, Integer(Length(mRead.Release.Rules)));
  Assert.AreEqual('1.1.0.0', mRead.Release.VersionOf('Release', 'Win64'));
  Assert.IsTrue(SameTime(At(2026, 10, 2, 8, 0, 0), mRead.Release.Builds[1].At));
  // Höchstens MaxBuilds Einträge, der neueste zuerst; unbekannte Felder bleiben.
  for mIndex := 1 to TAtlasProjectRelease.cMaxBuilds + 3 do
  begin
    mSummary.Release.Remember('Release', 'P' + IntToStr(mIndex), IntToStr(mIndex), 0);
  end;
  Assert.AreEqual(TAtlasProjectRelease.cMaxBuilds, Integer(Length(mSummary.Release.Builds)));
  Assert.AreEqual('P' + IntToStr(TAtlasProjectRelease.cMaxBuilds + 3), mSummary.Release.Builds[0].Platform);
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"project": "C:\\P.dproj", "release": {"findings": 1, "gate": ' +
    '"block", "builds": [{"configuration": "Release", "platform": "Win32", "version": "2.0.0.0", "signed": true}]}}',
    mRead));
  Assert.AreEqual('2.0.0.0', mRead.Release.VersionOf('Release', 'Win32'));
  mRead.Release.Remember('Release', 'Win64', '2.0.0.0', 0);
  mJson := TAtlasProjectSummaries.ToJson(mRead);
  Assert.Contains(mJson, '"gate":"block"');
  Assert.Contains(mJson, '"version":"2.0.0.0","signed":true}');
end;

/// <summary>Ohne Testbericht fehlen die Zähler; fremde Felder (auch in "failures") bleiben.</summary>
procedure AssertCiWithoutTestReport;
var
  mRead: TAtlasProjectSummary;
  mJson: string;
begin
  // Ohne Testbericht fehlen die Zähler; fremde Felder (auch in "failures") bleiben.
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"project": "C:\\P.dproj", "ci": {"provider": "jenkins",' +
    ' "server": "https://ci", "job": "kasse", "number": 7, "result": "success", "error": "neu", "extra": 1,' +
    ' "failures": [{"test": "A.B", "flaky": true}]}}', mRead));
  Assert.AreEqual<TAtlasCiFetchError>(TAtlasCiFetchError.Network,
    mRead.Ci.Error, 'unbekannter Fehler gilt als Netzfehler');
  Assert.IsTrue(mRead.Ci.Build.TestsKnown);
  mJson := TAtlasProjectSummaries.ToJson(mRead);
  Assert.Contains(mJson, '"extra":1');
  Assert.Contains(mJson, '{"test":"A.B","flaky":true}');
  mRead.Ci.Build.TestsKnown := False;
  mRead.Ci.Build.Failures := nil;
  mJson := TAtlasProjectSummaries.ToJson(mRead);
  Assert.DoesNotContain(mJson, '"passed"');
  Assert.DoesNotContain(mJson, '"failures"');
end;

procedure TAtlasProjectSummaryTests.CiRoundTripAndMatches;
var
  mSummary, mRead: TAtlasProjectSummary;
  mJob: TAtlasCiJob;
  mFailure: TAtlasCiFailure;
  mJson: string;
begin
  mJob := TAtlasCiJob.Create('jenkins', 'https://CI.Firma.de/', 'team/kasse', True, 'main');
  mSummary := TAtlasProjectSummary.Create(cProject);
  Assert.IsFalse(mSummary.Ci.Matches(mJob));
  mSummary.Ci.Known := True;
  mSummary.Ci.Provider := mJob.Provider;
  mSummary.Ci.Server := mJob.Server;
  mSummary.Ci.Job := mJob.Job;
  mSummary.Ci.Branch := mJob.JobBranch;
  mSummary.Ci.Attempt := At(2026, 10, 16, 9, 5, 0);
  mSummary.Ci.Error := TAtlasCiFetchError.Timeout;
  mSummary.Ci.At := At(2026, 10, 16, 8, 30, 0);
  mSummary.Ci.Build.Number := 482;
  mSummary.Ci.Build.Outcome := TAtlasCiOutcome.Unstable;
  mSummary.Ci.Build.StartedUtc := At(2026, 10, 16, 8, 20, 0);
  mSummary.Ci.Build.DurationMs := 61234;
  mSummary.Ci.Build.TestsKnown := True;
  mSummary.Ci.Build.Passed := 410;
  mSummary.Ci.Build.Failed := 2;
  mSummary.Ci.Build.Skipped := 3;
  mFailure.Test := 'Atlas.Core.Index.Tests.TIndexTests.FindsDeclarations';
  mFailure.Message := 'Erwartet 3 Deklarationen, gefunden 0';
  mSummary.Ci.Build.Failures := [mFailure];
  Assert.IsTrue(mSummary.Ci.Matches(mJob));
  Assert.IsTrue(mSummary.Ci.HasBuild);
  mJson := TAtlasProjectSummaries.ToJson(mSummary);
  Assert.Contains(mJson, '"ci":{"provider":"jenkins","server":"https://ci.firma.de","job":"team/kasse",' +
    '"branch":"main","attempt":"2026-10-16T09:05:00Z","error":"timeout","at":"2026-10-16T08:30:00Z",' +
    '"number":482,"result":"unstable","started":"2026-10-16T08:20:00Z","durationMs":61234,"passed":410,' +
    '"failed":2,"skipped":3,"failures":[{"test":"Atlas.Core.Index.Tests.TIndexTests.FindsDeclarations",' +
    '"message":"Erwartet 3 Deklarationen, gefunden 0"}]}');
  Assert.DoesNotContain(mJson, 'https://CI.Firma.de/', 'nur der Server, wie TAtlasCiJob.Server');
  Assert.IsTrue(TAtlasProjectSummaries.Parse(mJson, mRead));
  Assert.IsTrue(mRead.Ci.Known);
  Assert.IsTrue(mRead.Ci.Matches(mJob));
  Assert.IsFalse(mRead.Ci.Matches(TAtlasCiJob.Create('jenkins', 'https://ci.firma.de', 'team/kasse', True,
    'develop')), 'anderer Branch');
  Assert.AreEqual<TAtlasCiFetchError>(TAtlasCiFetchError.Timeout, mRead.Ci.Error);
  Assert.IsTrue(SameTime(At(2026, 10, 16, 8, 30, 0), mRead.Ci.At));
  Assert.IsTrue(SameTime(At(2026, 10, 16, 9, 5, 0), mRead.Ci.Attempt));
  Assert.AreEqual(482, mRead.Ci.Build.Number);
  Assert.AreEqual<TAtlasCiOutcome>(TAtlasCiOutcome.Unstable, mRead.Ci.Build.Outcome);
  Assert.IsTrue(mRead.Ci.Build.TestsKnown);
  Assert.AreEqual(410, mRead.Ci.Build.Passed);
  Assert.AreEqual(2, mRead.Ci.Build.Failed);
  Assert.AreEqual(1, Integer(Length(mRead.Ci.Build.Failures)));
  Assert.AreEqual('Erwartet 3 Deklarationen, gefunden 0', mRead.Ci.Build.Failures[0].Message);
  AssertCiWithoutTestReport;
end;

procedure TAtlasProjectSummaryTests.TodosRejectInvalidAnswer;
var
  mTodos: TAtlasProjectTodos;
begin
  Assert.IsFalse(TAtlasProjectTodos.FromServer('', 0, mTodos));
  Assert.IsFalse(TAtlasProjectTodos.FromServer('"# TODOs"', 0, mTodos));
  Assert.IsFalse(TAtlasProjectTodos.FromServer('{"summary": {"files": 1}}', 0, mTodos));
  Assert.IsFalse(mTodos.Known);
  // Ein Projekt ohne TODOs: 0 ist ein Wert, keine Lücke.
  Assert.IsTrue(TAtlasProjectTodos.FromServer('{"summary": {"files": 0, "open": 0, "done": 0, "keywords": {}}}', 1,
    mTodos));
  Assert.IsTrue(mTodos.Known);
  Assert.AreEqual(0, Integer(Length(mTodos.Keywords)));
end;

procedure TAtlasProjectSummaryTests.BaselineRoundTripAndUnknownFields;
var
  mSummary, mRead: TAtlasProjectSummary;
  mStamp: TDateTime;
  mJson: string;
begin
  mStamp := EncodeDate(2026, 10, 15) + EncodeTime(9, 30, 0, 0);
  mSummary := TAtlasProjectSummary.Create(cProject);
  mSummary.Baseline.Known := True;
  mSummary.Baseline.At := mStamp;
  mSummary.Baseline.Exists := True;
  mSummary.Baseline.Valid := True;
  mSummary.Baseline.Entries := 40;
  mSummary.Baseline.Hits := 52;
  mSummary.Baseline.Orphaned := 2;
  mJson := TAtlasProjectSummaries.ToJson(mSummary);
  // Ohne Aktualisieren über Atlas keine Zähler.
  Assert.Contains(mJson, '"baseline":{"at":"2026-10-15T09:30:00Z","exists":true,"valid":true,"entries":40,' +
    '"hits":52,"orphaned":2}');
  mSummary.Baseline.Updated := mStamp;
  mSummary.Baseline.Added := 3;
  mSummary.Baseline.Removed := 5;
  mJson := TAtlasProjectSummaries.ToJson(mSummary);
  Assert.Contains(mJson, '"orphaned":2,"updated":"2026-10-15T09:30:00Z","added":3,"removed":5}');
  Assert.IsTrue(TAtlasProjectSummaries.Parse(mJson, mRead));
  Assert.IsTrue(mRead.Baseline.Known);
  Assert.IsTrue(mRead.Baseline.Exists);
  Assert.IsTrue(mRead.Baseline.Valid);
  Assert.AreEqual(40, mRead.Baseline.Entries);
  Assert.AreEqual(52, mRead.Baseline.Hits);
  Assert.AreEqual(2, mRead.Baseline.Orphaned);
  Assert.AreEqual<TDateTime>(mStamp, mRead.Baseline.Updated);
  Assert.AreEqual(3, mRead.Baseline.Added);
  Assert.AreEqual(5, mRead.Baseline.Removed);
  // Keine Baseline: bekannt, aber nicht vorhanden (Lücke im Projektverlauf, „Baseline erzeugen“ in der
  // Einrichtung); unbekannte Felder im Abschnitt bleiben.
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"project": "C:\\P.dproj", "baseline": {"at": ' +
    '"2026-10-15T09:30:00Z", "exists": false, "trend": [1, 2]}}', mRead));
  Assert.IsTrue(mRead.Baseline.Known);
  Assert.IsFalse(mRead.Baseline.Exists);
  Assert.AreEqual<TDateTime>(0, mRead.Baseline.Updated);
  mJson := TAtlasProjectSummaries.ToJson(mRead);
  Assert.Contains(mJson, '"trend":[1,2]');
  Assert.AreEqual(0, Pos('"updated"', mJson), mJson);
end;

/// <summary>Sauber; unbekannte Felder bleiben, Zähler nie kleiner als die Funde.</summary>
procedure AssertSetupCleanKeepsUnknown;
var
  mRead: TAtlasProjectSummary;
  mJson: string;
begin
  // Sauber; unbekannte Felder bleiben, Zähler nie kleiner als die Funde.
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"setup": {"dismissed": false, "x": 1, "paths": {"at": ' +
    '"2026-10-15T09:30:00Z", "missingUnits": 0, "undefinedDefines": 0, "units": [], "defines": [], "y": 2}}}', mRead));
  Assert.IsTrue(mRead.Setup.PathsClean);
  mJson := TAtlasProjectSummaries.ToJson(mRead);
  Assert.Contains(mJson, '"x":1');
  Assert.Contains(mJson, '"y":2');
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"setup": {"paths": {"missingUnits": 0, "units": [{"name": "A"}, ' +
    '{"file": "ohne Namen"}]}}}', mRead));
  Assert.AreEqual(1, mRead.Setup.MissingUnitCount);
  Assert.AreEqual(1, Integer(mRead.Setup.MissingUnits[0].Count));
end;

procedure TAtlasProjectSummaryTests.SetupRoundTripAndLimits;
var
  mSummary, mRead: TAtlasProjectSummary;
  mStamp: TDateTime;
  mJson: string;
  mFinding: TAtlasSetupFinding;
  mIndex: Integer;
begin
  mStamp := EncodeDate(2026, 10, 15) + EncodeTime(9, 30, 0, 0);
  mFinding := Default(TAtlasSetupFinding);
  mSummary := TAtlasProjectSummary.Create(cProject);
  Assert.IsFalse(mSummary.Setup.Known);
  Assert.IsFalse(mSummary.Setup.PathsClean);
  mSummary.Setup.Known := True;
  mSummary.Setup.Dismissed := True;
  mSummary.Setup.DismissedAt := mStamp;
  mJson := TAtlasProjectSummaries.ToJson(mSummary);
  Assert.Contains(mJson, '"setup":{"dismissed":true,"dismissedAt":"2026-10-15T09:30:00Z"}');
  mSummary.Setup.Dismissed := False;
  mSummary.Setup.Checked := True;
  mSummary.Setup.CheckedAt := mStamp;
  mSummary.Setup.Files := 12;
  mSummary.Setup.MissingUnitCount := 60;
  mSummary.Setup.UndefinedDefineCount := 1;
  for mIndex := 1 to 60 do
  begin
    mFinding.Name := 'Unit' + IntToStr(mIndex);
    mFinding.FileName := 'Src\Main.pas';
    mFinding.Line := mIndex;
    mFinding.Count := 1;
    mSummary.Setup.MissingUnits := mSummary.Setup.MissingUnits + [mFinding];
  end;
  mFinding.Name := 'USE_LOG';
  mFinding.FileName := '';
  mFinding.Line := 0;
  mFinding.Count := 3;
  mSummary.Setup.UndefinedDefines := [mFinding];
  mJson := TAtlasProjectSummaries.ToJson(mSummary);
  Assert.Contains(mJson, '"setup":{"paths":{"at":"2026-10-15T09:30:00Z","files":12,"unreadable":0,' +
    '"missingUnits":60,"undefinedDefines":1,"units":[{"name":"Unit1","file":"Src\\Main.pas","line":1,"count":1}');
  Assert.Contains(mJson, '"defines":[{"name":"USE_LOG","count":3}]');
  Assert.AreEqual(0, Pos('"Unit51"', mJson), 'höchstens MaxFindings je Liste');
  Assert.IsTrue(TAtlasProjectSummaries.Parse(mJson, mRead));
  Assert.IsTrue(mRead.Setup.Known);
  Assert.IsFalse(mRead.Setup.Dismissed);
  Assert.IsTrue(mRead.Setup.Checked);
  Assert.AreEqual<TDateTime>(mStamp, mRead.Setup.CheckedAt);
  Assert.AreEqual(12, mRead.Setup.Files);
  Assert.AreEqual(60, mRead.Setup.MissingUnitCount);
  Assert.AreEqual(TAtlasProjectSetup.cMaxFindings, Integer(Length(mRead.Setup.MissingUnits)));
  Assert.AreEqual('Src\Main.pas', mRead.Setup.MissingUnits[0].FileName);
  Assert.AreEqual(3, Integer(mRead.Setup.UndefinedDefines[0].Count));
  Assert.IsFalse(mRead.Setup.PathsClean);
  AssertSetupCleanKeepsUnknown;
end;

procedure TAtlasProjectSummaryTests.SetupKeepsUncertainFindings;
var
  mSummary, mRead: TAtlasProjectSummary;
  mFinding: TAtlasSetupFinding;
  mJson: string;
begin
  mSummary := TAtlasProjectSummary.Create(cProject);
  mSummary.Setup.Known := True;
  mSummary.Setup.Checked := True;
  mSummary.Setup.MissingUnitCount := 2;
  mSummary.Setup.UncertainUnitCount := 1;
  mSummary.Setup.SkippedMacros := ['MYLIB', 'TOOLS'];
  mFinding := Default(TAtlasSetupFinding);
  mFinding.Name := 'Lib.Core';
  mFinding.Count := 1;
  mFinding.Uncertain := True;
  // Der Projektname gilt nur in der Karte einer Gruppe und wird nicht gespeichert.
  mFinding.Project := 'App';
  mSummary.Setup.MissingUnits := [mFinding];
  mJson := TAtlasProjectSummaries.ToJson(mSummary);
  Assert.Contains(mJson, '"uncertainUnits":1');
  Assert.AreEqual(0, Pos('"uncertainDefines"', mJson), 'nur, wenn es unsichere gibt');
  Assert.Contains(mJson, '"skippedMacros":["MYLIB","TOOLS"]');
  Assert.Contains(mJson, '{"name":"Lib.Core","count":1,"uncertain":true}');
  Assert.AreEqual(0, Pos('"App"', mJson));
  Assert.IsTrue(TAtlasProjectSummaries.Parse(mJson, mRead));
  Assert.AreEqual(1, mRead.Setup.UncertainUnitCount);
  Assert.AreEqual('MYLIB|TOOLS', string.Join('|', mRead.Setup.SkippedMacros));
  Assert.IsTrue(mRead.Setup.MissingUnits[0].Uncertain);
  Assert.IsFalse(mRead.Setup.PathsClean, 'ein sicherer Fund bleibt');
  // Unsichere nie mehr als alle; nur unsichere: erledigt.
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"setup": {"paths": {"missingUnits": 1, "uncertainUnits": 5, ' +
    '"skippedMacros": ["A", 3, ""]}}}', mRead));
  Assert.AreEqual(1, mRead.Setup.UncertainUnitCount);
  Assert.AreEqual('A', string.Join('|', mRead.Setup.SkippedMacros));
  Assert.IsTrue(mRead.Setup.PathsClean);
end;

procedure TAtlasProjectSummaryTests.BrokenFileSetAsideLockedFileKept;
var
  mSummary: TAtlasProjectSummary;
  mFileName: string;
  mLock: TFileStream;
begin
  ForceDirectories(FFolder);
  mFileName := TAtlasProjectSummaries.FileFor(FFolder, cProject);
  TFile.WriteAllText(mFileName, '{"format": 1, "check": {');
  Assert.IsFalse(TAtlasProjectSummaries.Load(FFolder, cProject, mSummary));
  Assert.AreEqual(cProject, mSummary.Project);
  Assert.IsTrue(FileExists(mFileName + TAtlasDataFile.cDefectExtension), 'beiseitegelegt');
  Assert.IsTrue(TAtlasProjectSummaries.Update(FFolder, cProject,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      ASummary.Hidden := True;
    end), 'beginnt neu');
  mLock := TFileStream.Create(mFileName, fmOpenRead or fmShareExclusive);
  try
    Assert.IsFalse(TAtlasProjectSummaries.Update(FFolder, cProject,
      procedure(var ASummary: TAtlasProjectSummary)
      begin
        ASummary.Hidden := False;
      end), 'gesperrt: nicht überschreiben');
  finally
    mLock.Free;
  end;
  Assert.IsTrue(TAtlasProjectSummaries.Load(FFolder, cProject, mSummary));
  Assert.IsTrue(mSummary.Hidden);
  // Gemeldete Datendateien vergessen: Das Register bliebe sonst als Leck stehen.
  TAtlasDataFile.ForgetReports;
end;

procedure TAtlasProjectSummaryTests.FieldHelpersAndSectionsWithoutObject;
begin
  Assert.AreEqual('', TJsonRead.Text(nil, 'project'));
  Assert.AreEqual(7, TJsonRead.IntOr(nil, 'errors', 7));
  Assert.IsFalse(TJsonRead.Flag(nil, 'hidden'));
  Assert.AreEqual('2026-10-15T09:30:05Z', SummaryTimeText(SummaryTimeOf('2026-10-15 09:30:05')));
  Assert.AreEqual<TDateTime>(0, SummaryTimeOf('2026-10-15X09:30:05Z'), 'Trenner');
  Assert.IsFalse(TAtlasSummarySections.SetupOf(nil).Known);
  Assert.IsFalse(TAtlasSummarySections.TestsOf(nil).Known);
  Assert.IsFalse(TAtlasSummarySections.ReleaseOf(nil).Known);
  Assert.IsFalse(TAtlasSummarySections.CiOf(nil).Known);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasProjectSummaryTests);

end.
