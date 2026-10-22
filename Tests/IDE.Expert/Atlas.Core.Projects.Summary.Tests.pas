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
    /// überschrieben (Bericht N3).</summary>
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
    /// <summary>#533: Release-Wächter, letzte Prüfung und Versionen je Konfiguration und Plattform.</summary>
    [Test]
    procedure ReleaseRoundTripAndRemember;
    /// <summary>#763: letzter Abruf vom Build-Server samt Testbericht; unbekannte Felder bleiben.</summary>
    [Test]
    procedure CiRoundTripAndMatches;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Projects.Summary;

const
  Project = 'C:\Projekte\Demo.dproj';
  Full =
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
    TDirectory.Delete(FFolder, True);
  // Der Leckmonitor misst den Saldo von Setup und TearDown.
  FFolder := '';
end;

procedure TAtlasProjectSummaryTests.KeyIsStableAndIgnoresCaseAndSlashes;
begin
  // Festgeschrieben: Spätere Bereiche (#755, #758 …) und Werkzeuge rechnen denselben Schlüssel.
  Assert.AreEqual('cea7b8ab83412c7a', TAtlasProjectSummaries.KeyOf(Project));
  Assert.AreEqual('cea7b8ab83412c7a', TAtlasProjectSummaries.KeyOf(' c:/projekte/demo.dproj '));
  // Nur ASCII-Buchstaben werden groß; Umlaute zählen wie geschrieben.
  Assert.AreEqual('dfab3d8087a2e100', TAtlasProjectSummaries.KeyOf('C:\Projekte\Über.dproj'));
  Assert.AreNotEqual(TAtlasProjectSummaries.KeyOf(Project), TAtlasProjectSummaries.KeyOf('C:\Projekte\Demo.dpr'));
  Assert.AreEqual('C:\PROJEKTE\DEMO.DPROJ', TAtlasProjectSummaries.NormalizedPath('c:/Projekte/Demo.dproj'));
end;

procedure TAtlasProjectSummaryTests.FileNameUsesKey;
begin
  Assert.AreEqual(IncludeTrailingPathDelimiter(FFolder) + 'cea7b8ab83412c7a.json',
    TAtlasProjectSummaries.FileFor(FFolder, Project));
end;

procedure TAtlasProjectSummaryTests.TimeRoundTrip;
var
  Value: TDateTime;
begin
  Value := At(2026, 10, 15, 9, 30, 5);
  Assert.AreEqual('2026-10-15T09:30:05Z', TAtlasProjectSummaries.TimeText(Value));
  Assert.IsTrue(SameTime(Value, TAtlasProjectSummaries.TimeOf('2026-10-15T09:30:05Z')));
  Assert.IsTrue(SameTime(Value, TAtlasProjectSummaries.TimeOf('2026-10-15T09:30:05.123Z')), 'Bruchteile');
  Assert.AreEqual('', TAtlasProjectSummaries.TimeText(0));
end;

procedure TAtlasProjectSummaryTests.InvalidTimeGivesZero;
begin
  Assert.IsTrue(TAtlasProjectSummaries.TimeOf('') = 0);
  Assert.IsTrue(TAtlasProjectSummaries.TimeOf('gestern') = 0);
  Assert.IsTrue(TAtlasProjectSummaries.TimeOf('2026-13-40T25:00:00Z') = 0);
end;

procedure TAtlasProjectSummaryTests.ParsesAllFields;
var
  Summary: TAtlasProjectSummary;
begin
  Assert.IsTrue(TAtlasProjectSummaries.Parse(Full, Summary));
  Assert.AreEqual(Project, Summary.Project);
  Assert.IsTrue(SameTime(At(2026, 10, 14, 8, 15, 0), Summary.LastOpened));
  Assert.IsTrue(SameTime(At(2026, 10, 14, 17, 45, 30), Summary.LastClosed));
  Assert.IsTrue(Summary.Hidden);
  Assert.IsTrue(Summary.Vcs.Known);
  Assert.IsTrue(Summary.Vcs.InWorkingCopy);
  Assert.AreEqual('git', Summary.Vcs.Kind);
  Assert.AreEqual('main', Summary.Vcs.Branch);
  Assert.AreEqual('0123456789abcdef', Summary.Vcs.Revision);
  Assert.AreEqual(3, Summary.Vcs.Changed);
  Assert.AreEqual(1, Summary.Vcs.Ahead);
  Assert.AreEqual(2, Summary.Vcs.Behind);
  Assert.IsTrue(Summary.Build.Known);
  Assert.AreEqual('build', Summary.Build.Kind);
  Assert.AreEqual('Debug', Summary.Build.Configuration);
  Assert.AreEqual('Win32', Summary.Build.Platform);
  Assert.IsFalse(Summary.Build.Succeeded);
  Assert.AreEqual(2, Summary.Build.Errors);
  Assert.AreEqual(1, Summary.Build.Warnings);
  Assert.AreEqual(4, Summary.Build.Hints);
  Assert.AreEqual('C:\Projekte\Main.pas', Summary.Build.First.FileName);
  Assert.AreEqual(12, Summary.Build.First.Line);
  Assert.AreEqual(5, Summary.Build.First.Column);
  Assert.AreEqual('E2003', Summary.Build.First.Code);
  Assert.AreEqual('x', Summary.Build.First.Text);
  Assert.IsTrue(Summary.Check.Known);
  Assert.AreEqual(1, Summary.Check.Errors);
  Assert.AreEqual('C:\Projekte\Unit2.pas', Summary.Check.First.FileName);
  Assert.AreEqual(7, Summary.Check.First.Line);
  Assert.IsTrue(Summary.Rules.Known);
  Assert.AreEqual(5, Summary.Rules.NewHits);
end;

procedure TAtlasProjectSummaryTests.WriteAndReadRoundTrip;
var
  Summary, Read: TAtlasProjectSummary;
begin
  Summary := TAtlasProjectSummary.Create(Project);
  Summary.LastOpened := At(2026, 10, 15, 7, 0, 0);
  Summary.Vcs := TAtlasProjectVcs.Empty;
  Summary.Vcs.Known := True;
  Summary.Vcs.At := At(2026, 10, 15, 7, 0, 1);
  Summary.Vcs.Kind := 'svn';
  Summary.Vcs.Branch := 'branches/x';
  Summary.Vcs.Revision := '42';
  Summary.Vcs.Changed := 0;
  Summary.Build.Known := True;
  Summary.Build.At := At(2026, 10, 15, 7, 5, 0);
  Summary.Build.Kind := 'make';
  Summary.Build.Succeeded := True;
  Summary.Build.Configuration := 'Release';
  Summary.Build.Platform := 'Win64';
  Assert.IsTrue(TAtlasProjectSummaries.Parse(TAtlasProjectSummaries.ToJson(Summary), Read));
  Assert.AreEqual(Project, Read.Project);
  Assert.IsTrue(SameTime(Summary.LastOpened, Read.LastOpened));
  Assert.IsTrue(Read.LastClosed = 0, 'nicht geschrieben');
  Assert.IsFalse(Read.Hidden);
  Assert.AreEqual('svn', Read.Vcs.Kind);
  Assert.AreEqual('branches/x', Read.Vcs.Branch);
  Assert.AreEqual(0, Read.Vcs.Changed);
  Assert.AreEqual(-1, Read.Vcs.Ahead, 'SVN kennt keinen Upstream');
  Assert.IsTrue(Read.Build.Succeeded);
  Assert.AreEqual('Release', Read.Build.Configuration);
  Assert.AreEqual(0, Read.Build.Errors);
  Assert.IsTrue(Read.Build.First.IsEmpty);
  Assert.IsFalse(Read.Check.Known);
  Assert.IsFalse(Read.Rules.Known);
  Assert.AreEqual(1, TAtlasProjectSummaries.FormatOf(TAtlasProjectSummaries.ToJson(Summary)));
end;

procedure TAtlasProjectSummaryTests.KeepsUnknownFields;
var
  Summary: TAtlasProjectSummary;
  Root: TJSONObject;
  Build, History: TJSONValue;
begin
  // Felder späterer Fassungen (#758: Messpunkte je Build) überstehen das Schreiben durch diese Fassung.
  Assert.IsTrue(TAtlasProjectSummaries.Parse(
    '{"format": 1, "project": "C:\\P.dproj", "history": [{"at": "2026-10-01T00:00:00Z", "todos": 3}],' +
    ' "build": {"at": "2026-10-01T00:00:00Z", "kind": "build", "succeeded": true, "errors": 0,' +
    ' "warnings": 0, "hints": 0, "metrics": {"lines": 1200}}}', Summary));
  Summary.Build.Errors := 2;
  Summary.Build.Succeeded := False;
  Root := TJSONObject.ParseJSONValue(TAtlasProjectSummaries.ToJson(Summary)) as TJSONObject;
  try
    History := Root.GetValue('history');
    Assert.IsTrue(History is TJSONArray, 'unbekanntes Feld oben');
    Assert.AreEqual(1, Integer(TJSONArray(History).Count));
    Build := Root.GetValue('build');
    Assert.IsTrue(Build is TJSONObject);
    Assert.IsTrue(TJSONObject(Build).GetValue('metrics') is TJSONObject, 'unbekanntes Feld im Abschnitt');
    Assert.AreEqual('2', TJSONObject(Build).GetValue('errors').Value, 'bekanntes Feld neu geschrieben');
    Assert.AreEqual(9, Integer(TJSONObject(Build).Count), 'acht bekannte Felder und metrics, errors nur einmal');
  finally
    Root.Free;
  end;
end;

procedure TAtlasProjectSummaryTests.MissingSectionsStayUnknown;
var
  Summary: TAtlasProjectSummary;
begin
  // Ohne "format" gilt Format 1.
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"project": "C:\\P.dproj"}', Summary));
  Assert.IsFalse(Summary.Vcs.Known);
  Assert.IsFalse(Summary.Vcs.InWorkingCopy);
  Assert.AreEqual(-1, Summary.Vcs.Changed);
  Assert.IsFalse(Summary.Build.Known);
  Assert.IsFalse(Summary.Check.Known);
  Assert.IsFalse(Summary.Rules.Known);
  Assert.IsFalse(Summary.Metrics.Known);
  Assert.IsFalse(Summary.Todos.Known);
  Assert.IsFalse(Summary.Baseline.Known);
  Assert.IsFalse(Summary.Tests.Known);
  Assert.IsFalse(Summary.Release.Known);
  Assert.IsFalse(Summary.Ci.Known);
  Assert.IsFalse(Summary.Ci.HasBuild);
  Assert.IsTrue(Summary.LastOpened = 0);
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"project": "C:\\P.dproj", "vcs": {"kind": "none"}}', Summary));
  Assert.IsTrue(Summary.Vcs.Known);
  Assert.IsFalse(Summary.Vcs.InWorkingCopy, 'ohne Arbeitskopie');
end;

procedure TAtlasProjectSummaryTests.RejectsInvalidAndNewerFormat;
var
  Summary: TAtlasProjectSummary;
begin
  Assert.IsFalse(TAtlasProjectSummaries.Parse('', Summary));
  Assert.IsFalse(TAtlasProjectSummaries.Parse('kein json', Summary));
  Assert.IsFalse(TAtlasProjectSummaries.Parse('[1, 2]', Summary));
  Assert.IsFalse(TAtlasProjectSummaries.Parse('{"format": 2, "project": "C:\\P.dproj"}', Summary));
  Assert.AreEqual('', Summary.Project, 'leer nach Ablehnung');
  Assert.AreEqual(2, TAtlasProjectSummaries.FormatOf('{"format": 2}'));
  Assert.AreEqual(0, TAtlasProjectSummaries.FormatOf('kein json'));
end;

procedure TAtlasProjectSummaryTests.SaveAndLoadOnDisk;
var
  Summary, Loaded: TAtlasProjectSummary;
  Bytes: TBytes;
begin
  Assert.IsFalse(TAtlasProjectSummaries.Load(FFolder, Project, Loaded), 'noch keine Datei');
  Assert.AreEqual(Project, Loaded.Project);
  Summary := TAtlasProjectSummary.Create(Project);
  Summary.Check.Known := True;
  Summary.Check.Errors := 3;
  Summary.Check.At := At(2026, 10, 15, 8, 0, 0);
  Assert.IsTrue(TAtlasProjectSummaries.Save(FFolder, Summary), 'legt den Ordner an');
  Assert.IsTrue(FileExists(TAtlasProjectSummaries.FileFor(FFolder, Project)));
  Assert.IsFalse(FileExists(TAtlasProjectSummaries.FileFor(FFolder, Project) + '.tmp'), 'keine Reste');
  Bytes := TFile.ReadAllBytes(TAtlasProjectSummaries.FileFor(FFolder, Project));
  Assert.AreEqual(Ord('{'), Integer(Bytes[0]), 'UTF-8 ohne BOM');
  Assert.IsTrue(TAtlasProjectSummaries.Load(FFolder, 'c:/projekte/demo.dproj', Loaded), 'andere Schreibweise');
  Assert.AreEqual(Project, Loaded.Project, 'gespeicherter Pfad');
  Assert.AreEqual(3, Loaded.Check.Errors);
  // Zweites Speichern ersetzt die Datei.
  Loaded.Check.Errors := 0;
  Assert.IsTrue(TAtlasProjectSummaries.Save(FFolder, Loaded));
  Assert.IsTrue(TAtlasProjectSummaries.Load(FFolder, Project, Loaded));
  Assert.AreEqual(0, Loaded.Check.Errors);
end;

procedure TAtlasProjectSummaryTests.SaveKeepsNewerFormatFile;
var
  Summary: TAtlasProjectSummary;
  FileName, Newer: string;
begin
  ForceDirectories(FFolder);
  FileName := TAtlasProjectSummaries.FileFor(FFolder, Project);
  Newer := '{"format": 2, "project": "C:\\Projekte\\Demo.dproj", "neu": true}';
  TFile.WriteAllText(FileName, Newer);
  Assert.IsFalse(TAtlasProjectSummaries.Load(FFolder, Project, Summary), 'höheres Format nicht lesen');
  Summary.Hidden := True;
  Assert.IsFalse(TAtlasProjectSummaries.Save(FFolder, Summary), 'und nicht überschreiben');
  Assert.IsFalse(TAtlasProjectSummaries.Update(FFolder, Project,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      ASummary.Hidden := True;
    end));
  Assert.AreEqual(2, TAtlasProjectSummaries.FormatOf(TFile.ReadAllText(FileName)));
end;

procedure TAtlasProjectSummaryTests.UpdateCreatesAndChanges;
var
  Summary: TAtlasProjectSummary;
begin
  Assert.IsTrue(TAtlasProjectSummaries.Update(FFolder, Project,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      ASummary.LastOpened := At(2026, 10, 15, 6, 0, 0);
      ASummary.Hidden := True;
    end));
  Assert.IsTrue(TAtlasProjectSummaries.Update(FFolder, Project,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      Assert.IsTrue(ASummary.Hidden, 'liest den gespeicherten Stand');
      ASummary.Hidden := False;
      ASummary.LastClosed := At(2026, 10, 15, 9, 0, 0);
    end));
  Assert.IsTrue(TAtlasProjectSummaries.Load(FFolder, Project, Summary));
  Assert.IsFalse(Summary.Hidden);
  Assert.IsTrue(SameTime(At(2026, 10, 15, 6, 0, 0), Summary.LastOpened));
  Assert.IsTrue(SameTime(At(2026, 10, 15, 9, 0, 0), Summary.LastClosed));
  Assert.IsFalse(TAtlasProjectSummaries.Update(FFolder, '', nil), 'ohne Projekt');
end;

procedure TAtlasProjectSummaryTests.NameWithoutExtension;
begin
  Assert.AreEqual('Demo', TAtlasProjectSummary.Create(Project).Name);
  Assert.AreEqual('Gruppe', TAtlasProjectSummary.Create('C:\G\Gruppe.groupproj').Name);
  Assert.AreEqual('Atlas.IDE.Expert', TAtlasProjectSummary.Create('C:\A\Atlas.IDE.Expert.dpk').Name);
end;

procedure TAtlasProjectSummaryTests.MetricsFromServerAndRoundTrip;
const
  // Antwort von atlas.server.metrics im Modus "summary" (#66).
  Answer = '{"format": 1, "limits": {"length": 60, "nesting": 4, "cyclomatic": 15, "cognitive": 15, ' +
    '"parameters": 6}, "summary": {"files": 2, "methods": 3, "overLimits": 1, ' +
    '"average": {"length": 30.3, "nesting": 2.0, "cyclomatic": 6.7, "cognitive": 7.0, "parameters": 3.0}, ' +
    '"maximum": {"length": 75, "nesting": 5, "cyclomatic": 17, "cognitive": 20, "parameters": 7}, ' +
    '"exceeded": {"length": 1, "nesting": 1, "cyclomatic": 1, "cognitive": 1, "parameters": 1}}}';
var
  Metrics: TAtlasProjectMetrics;
  Summary, Read: TAtlasProjectSummary;
  Stamp: TDateTime;
  Json: string;
begin
  Stamp := EncodeDate(2026, 10, 15) + EncodeTime(9, 30, 0, 0);
  Assert.IsTrue(TAtlasProjectMetrics.FromServer(Answer, Stamp, Metrics));
  Assert.IsTrue(Metrics.Known);
  Assert.IsTrue(Metrics.At = Stamp, 'Zeitpunkt des Builds');
  Assert.AreEqual(2, Metrics.Files);
  Assert.AreEqual(3, Metrics.Methods);
  Assert.AreEqual(1, Metrics.OverLimits);
  Assert.AreEqual(303, Metrics.AverageTenths[0], 'mittlere Methodenlänge für den Projektverlauf (#758)');
  Assert.AreEqual(67, Metrics.AverageTenths[2]);
  Assert.AreEqual(75, Metrics.Maximum[0]);
  Assert.AreEqual(1, Metrics.Exceeded[4]);
  Summary := TAtlasProjectSummary.Create(Project);
  Summary.Metrics := Metrics;
  Json := TAtlasProjectSummaries.ToJson(Summary);
  Assert.Contains(Json, '"metrics":{"at":"2026-10-15T09:30:00Z","files":2,"methods":3,"overLimits":1');
  Assert.Contains(Json, '"average":{"length":30.3');
  Assert.Contains(Json, '"maximum":{"length":75');
  Assert.IsTrue(TAtlasProjectSummaries.Parse(Json, Read));
  Assert.IsTrue(Read.Metrics.Known);
  Assert.AreEqual(303, Read.Metrics.AverageTenths[0]);
  Assert.AreEqual(20, Read.Metrics.Maximum[3]);
  Assert.IsTrue(Read.Metrics.At = Stamp);
  // Unbekannte Felder im Abschnitt bleiben (z. B. eine Verlaufsreihe aus #758).
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"project": "C:\\P.dproj", "metrics": {"methods": 1, ' +
    '"history": [1, 2]}}', Read));
  Assert.Contains(TAtlasProjectSummaries.ToJson(Read), '"history":[1,2]');
end;

procedure TAtlasProjectSummaryTests.MetricsRejectInvalidAnswer;
var
  Metrics: TAtlasProjectMetrics;
begin
  Assert.IsFalse(TAtlasProjectMetrics.FromServer('', 0, Metrics));
  Assert.IsFalse(TAtlasProjectMetrics.FromServer('"# Bericht"', 0, Metrics));
  Assert.IsFalse(TAtlasProjectMetrics.FromServer('{"summary": {"files": 1}}', 0, Metrics));
  Assert.IsFalse(Metrics.Known);
end;

procedure TAtlasProjectSummaryTests.TodosFromServerAndRoundTrip;
const
  // Antwort von atlas.server.todos im Modus "summary" (#68).
  Answer = '{"format": 1, "summary": {"files": 2, "open": 5, "done": 1, "keywords": {"FIXME": 2, "TODO": 3}}}';
var
  Todos: TAtlasProjectTodos;
  Summary, Read: TAtlasProjectSummary;
  Stamp: TDateTime;
  Json: string;
begin
  Stamp := EncodeDate(2026, 10, 15) + EncodeTime(9, 30, 0, 0);
  Assert.IsTrue(TAtlasProjectTodos.FromServer(Answer, Stamp, Todos));
  Assert.IsTrue(Todos.Known);
  Assert.IsTrue(Todos.At = Stamp, 'Zeitpunkt des Builds');
  Assert.AreEqual(2, Todos.Files);
  Assert.AreEqual(5, Todos.Open, 'Reihe „offene TODOs“ des Projektverlaufs (#758)');
  Assert.AreEqual(1, Todos.Done);
  Assert.AreEqual(2, Todos.CountOf('fixme'));
  Assert.AreEqual(0, Todos.CountOf('HACK'));
  Summary := TAtlasProjectSummary.Create(Project);
  Assert.IsFalse(Summary.Todos.Known);
  Summary.Todos := Todos;
  Json := TAtlasProjectSummaries.ToJson(Summary);
  Assert.Contains(Json, '"todos":{"at":"2026-10-15T09:30:00Z","files":2,"open":5,"done":1,' +
    '"keywords":{"FIXME":2,"TODO":3}}');
  Assert.IsTrue(TAtlasProjectSummaries.Parse(Json, Read));
  Assert.IsTrue(Read.Todos.Known);
  Assert.AreEqual(5, Read.Todos.Open);
  Assert.AreEqual(3, Read.Todos.CountOf('TODO'));
  Assert.IsTrue(Read.Todos.At = Stamp);
  // Ohne Abschnitt bleibt er unbekannt; unbekannte Felder im Abschnitt bleiben.
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"project": "C:\\P.dproj"}', Read));
  Assert.IsFalse(Read.Todos.Known);
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"project": "C:\\P.dproj", "todos": {"open": 0, ' +
    '"history": [3, 0]}}', Read));
  Assert.IsTrue(Read.Todos.Known);
  Assert.AreEqual(0, Read.Todos.Open);
  Assert.Contains(TAtlasProjectSummaries.ToJson(Read), '"history":[3,0]');
end;

procedure TAtlasProjectSummaryTests.TestsRoundTripAndLimits;
var
  Summary, Read: TAtlasProjectSummary;
  Failure: TAtlasProjectTestFailure;
  Index: Integer;
  Json: string;
  Names: TArray<string>;
begin
  Summary := TAtlasProjectSummary.Create(Project);
  Summary.Tests.Known := True;
  Summary.Tests.At := At(2026, 10, 16, 10, 0, 0);
  Summary.Tests.Project := 'C:\Projekte\Demo.Tests.dproj';
  Summary.Tests.Configuration := 'Debug';
  Summary.Tests.Platform := 'Win64';
  Summary.Tests.Passed := 40;
  Summary.Tests.Failed := 1;
  Summary.Tests.Errors := 1;
  Summary.Tests.Skipped := 2;
  Summary.Tests.DurationMs := 1250;
  Failure := Default(TAtlasProjectTestFailure);
  Failure.Test := 'Demo.Tests.TRechner.Summe.Gross';
  Failure.Message := 'Erwartet: 30, erhalten: 31';
  Failure.FileName := 'C:\Projekte\Demo.Tests.pas';
  Failure.Line := 35;
  Summary.Tests.Failures := [Failure, Failure];
  Failure := Default(TAtlasProjectTestFailure);
  Failure.Test := 'Demo.Tests.TRechner.Teilt';
  Summary.Tests.Failures := Summary.Tests.Failures + [Failure];
  Assert.AreEqual(44, Summary.Tests.Total);
  Json := TAtlasProjectSummaries.ToJson(Summary);
  Assert.Contains(Json, '"tests":{"at":"2026-10-16T10:00:00Z","project":"C:\\Projekte\\Demo.Tests.dproj",' +
    '"configuration":"Debug","platform":"Win64","passed":40,"failed":1,"errors":1,"skipped":2,"durationMs":1250,' +
    '"failures":[{"test":"Demo.Tests.TRechner.Summe.Gross","message":"Erwartet: 30, erhalten: 31",' +
    '"file":"C:\\Projekte\\Demo.Tests.pas","line":35}');
  Assert.Contains(Json, '{"test":"Demo.Tests.TRechner.Teilt"}', 'ohne Meldung und Fundstelle nur der Name');
  Assert.IsTrue(TAtlasProjectSummaries.Parse(Json, Read));
  Assert.IsTrue(Read.Tests.Known);
  Assert.AreEqual('Win64', Read.Tests.Platform);
  Assert.AreEqual(1250, Read.Tests.DurationMs);
  Assert.AreEqual(3, Integer(Length(Read.Tests.Failures)));
  Assert.AreEqual(35, Read.Tests.Failures[0].Line);
  Assert.AreEqual('C:\Projekte\Demo.Tests.pas', Read.Tests.Failures[0].FileName);
  Names := Read.Tests.FailedTests;
  Assert.AreEqual(2, Integer(Length(Names)), 'erneut ausführen: jeder Test einmal');
  Assert.AreEqual('Demo.Tests.TRechner.Summe.Gross', Names[0]);
  Assert.AreEqual('Demo.Tests.TRechner.Teilt', Names[1]);
  // Höchstens MaxFailures in der Datei; unbekannte Felder bleiben.
  Summary.Tests.Failures := nil;
  for Index := 1 to TAtlasProjectTests.MaxFailures + 5 do
  begin
    Failure.Test := 'Demo.Tests.T.M' + IntToStr(Index);
    Summary.Tests.Failures := Summary.Tests.Failures + [Failure];
  end;
  Assert.IsTrue(TAtlasProjectSummaries.Parse(TAtlasProjectSummaries.ToJson(Summary), Read));
  Assert.AreEqual(TAtlasProjectTests.MaxFailures, Integer(Length(Read.Tests.Failures)));
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"project": "C:\\P.dproj", "tests": {"passed": 3, "jenkins": ' +
    '{"job": "x"}}}', Read));
  Assert.IsTrue(Read.Tests.Known);
  Assert.AreEqual(3, Read.Tests.Passed);
  Assert.Contains(TAtlasProjectSummaries.ToJson(Read), '"jenkins":{"job":"x"}');
end;

procedure TAtlasProjectSummaryTests.ReleaseRoundTripAndRemember;
var
  Summary, Read: TAtlasProjectSummary;
  Json: string;
  Index: Integer;
begin
  Summary := TAtlasProjectSummary.Create(Project);
  Assert.AreEqual('', Summary.Release.VersionOf('Release', 'Win64'));
  Summary.Release.Remember('Release', 'Win32', '1.0.0.0', At(2026, 10, 1, 8, 0, 0));
  Summary.Release.Remember('Release', 'Win64', '1.1.0.0', At(2026, 10, 2, 8, 0, 0));
  Summary.Release.Remember('release', 'WIN32', '1.2.0.0', At(2026, 10, 3, 8, 0, 0));
  Assert.IsTrue(Summary.Release.Known);
  Assert.AreEqual(2, Integer(Length(Summary.Release.Builds)), 'je Konfiguration und Plattform ein Eintrag');
  Assert.AreEqual('1.2.0.0', Summary.Release.VersionOf('Release', 'Win32'));
  Assert.AreEqual('1.1.0.0', Summary.Release.VersionOf('Release', 'Win64'));
  Assert.AreEqual('', Summary.Release.VersionOf('Ship', 'Win64'));
  Json := TAtlasProjectSummaries.ToJson(Summary);
  Assert.Contains(Json, '"release":{"builds":[{"configuration":"release","platform":"WIN32","version":"1.2.0.0",' +
    '"at":"2026-10-03T08:00:00Z"},{"configuration":"Release","platform":"Win64","version":"1.1.0.0",' +
    '"at":"2026-10-02T08:00:00Z"}]}', 'ohne Prüfung nur die Builds');
  Summary.Release.CheckedAt := At(2026, 10, 16, 9, 0, 0);
  Summary.Release.Configuration := 'Release';
  Summary.Release.Platform := 'Win64';
  Summary.Release.Findings := 2;
  Summary.Release.Blocked := True;
  Summary.Release.Rules := ['release-debug-define', 'release-assertions'];
  Json := TAtlasProjectSummaries.ToJson(Summary);
  Assert.Contains(Json, '"release":{"checkedAt":"2026-10-16T09:00:00Z","configuration":"Release",' +
    '"platform":"Win64","findings":2,"blocked":true,"rules":["release-debug-define","release-assertions"],');
  Assert.IsTrue(TAtlasProjectSummaries.Parse(Json, Read));
  Assert.IsTrue(Read.Release.Known);
  Assert.IsTrue(Read.Release.Blocked);
  Assert.AreEqual(2, Read.Release.Findings);
  Assert.AreEqual(2, Integer(Length(Read.Release.Rules)));
  Assert.AreEqual('1.1.0.0', Read.Release.VersionOf('Release', 'Win64'));
  Assert.IsTrue(SameTime(At(2026, 10, 2, 8, 0, 0), Read.Release.Builds[1].At));
  // Höchstens MaxBuilds Einträge, der neueste zuerst; unbekannte Felder bleiben.
  for Index := 1 to TAtlasProjectRelease.MaxBuilds + 3 do
    Summary.Release.Remember('Release', 'P' + IntToStr(Index), IntToStr(Index), 0);
  Assert.AreEqual(TAtlasProjectRelease.MaxBuilds, Integer(Length(Summary.Release.Builds)));
  Assert.AreEqual('P' + IntToStr(TAtlasProjectRelease.MaxBuilds + 3), Summary.Release.Builds[0].Platform);
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"project": "C:\\P.dproj", "release": {"findings": 1, "gate": ' +
    '"block", "builds": [{"configuration": "Release", "platform": "Win32", "version": "2.0.0.0", "signed": true}]}}',
    Read));
  Assert.AreEqual('2.0.0.0', Read.Release.VersionOf('Release', 'Win32'));
  Read.Release.Remember('Release', 'Win64', '2.0.0.0', 0);
  Json := TAtlasProjectSummaries.ToJson(Read);
  Assert.Contains(Json, '"gate":"block"');
  Assert.Contains(Json, '"version":"2.0.0.0","signed":true}');
end;

procedure TAtlasProjectSummaryTests.CiRoundTripAndMatches;
var
  Summary, Read: TAtlasProjectSummary;
  Job: TAtlasCiJob;
  Failure: TAtlasCiFailure;
  Json: string;
begin
  Job := TAtlasCiJob.Create('jenkins', 'https://CI.Firma.de/', 'team/kasse', True, 'main');
  Summary := TAtlasProjectSummary.Create(Project);
  Assert.IsFalse(Summary.Ci.Matches(Job));
  Summary.Ci.Known := True;
  Summary.Ci.Provider := Job.Provider;
  Summary.Ci.Server := Job.Server;
  Summary.Ci.Job := Job.Job;
  Summary.Ci.Branch := Job.JobBranch;
  Summary.Ci.Attempt := At(2026, 10, 16, 9, 5, 0);
  Summary.Ci.Error := TAtlasCiFetchError.Timeout;
  Summary.Ci.At := At(2026, 10, 16, 8, 30, 0);
  Summary.Ci.Build.Number := 482;
  Summary.Ci.Build.Outcome := TAtlasCiOutcome.Unstable;
  Summary.Ci.Build.StartedUtc := At(2026, 10, 16, 8, 20, 0);
  Summary.Ci.Build.DurationMs := 61234;
  Summary.Ci.Build.TestsKnown := True;
  Summary.Ci.Build.Passed := 410;
  Summary.Ci.Build.Failed := 2;
  Summary.Ci.Build.Skipped := 3;
  Failure.Test := 'Atlas.Core.Index.Tests.TIndexTests.FindsDeclarations';
  Failure.Message := 'Erwartet 3 Deklarationen, gefunden 0';
  Summary.Ci.Build.Failures := [Failure];
  Assert.IsTrue(Summary.Ci.Matches(Job));
  Assert.IsTrue(Summary.Ci.HasBuild);
  Json := TAtlasProjectSummaries.ToJson(Summary);
  Assert.Contains(Json, '"ci":{"provider":"jenkins","server":"https://ci.firma.de","job":"team/kasse",' +
    '"branch":"main","attempt":"2026-10-16T09:05:00Z","error":"timeout","at":"2026-10-16T08:30:00Z",' +
    '"number":482,"result":"unstable","started":"2026-10-16T08:20:00Z","durationMs":61234,"passed":410,' +
    '"failed":2,"skipped":3,"failures":[{"test":"Atlas.Core.Index.Tests.TIndexTests.FindsDeclarations",' +
    '"message":"Erwartet 3 Deklarationen, gefunden 0"}]}');
  Assert.DoesNotContain(Json, 'https://CI.Firma.de/', 'nur der Server, wie TAtlasCiJob.Server');
  Assert.IsTrue(TAtlasProjectSummaries.Parse(Json, Read));
  Assert.IsTrue(Read.Ci.Known);
  Assert.IsTrue(Read.Ci.Matches(Job));
  Assert.IsFalse(Read.Ci.Matches(TAtlasCiJob.Create('jenkins', 'https://ci.firma.de', 'team/kasse', True,
    'develop')), 'anderer Branch');
  Assert.IsTrue(Read.Ci.Error = TAtlasCiFetchError.Timeout);
  Assert.IsTrue(SameTime(At(2026, 10, 16, 8, 30, 0), Read.Ci.At));
  Assert.IsTrue(SameTime(At(2026, 10, 16, 9, 5, 0), Read.Ci.Attempt));
  Assert.AreEqual(482, Read.Ci.Build.Number);
  Assert.IsTrue(Read.Ci.Build.Outcome = TAtlasCiOutcome.Unstable);
  Assert.IsTrue(Read.Ci.Build.TestsKnown);
  Assert.AreEqual(410, Read.Ci.Build.Passed);
  Assert.AreEqual(2, Read.Ci.Build.Failed);
  Assert.AreEqual(1, Integer(Length(Read.Ci.Build.Failures)));
  Assert.AreEqual('Erwartet 3 Deklarationen, gefunden 0', Read.Ci.Build.Failures[0].Message);
  // Ohne Testbericht fehlen die Zähler; fremde Felder (auch in "failures") bleiben.
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"project": "C:\\P.dproj", "ci": {"provider": "jenkins",' +
    ' "server": "https://ci", "job": "kasse", "number": 7, "result": "success", "error": "neu", "extra": 1,' +
    ' "failures": [{"test": "A.B", "flaky": true}]}}', Read));
  Assert.IsTrue(Read.Ci.Error = TAtlasCiFetchError.Network, 'unbekannter Fehler gilt als Netzfehler');
  Assert.IsTrue(Read.Ci.Build.TestsKnown);
  Json := TAtlasProjectSummaries.ToJson(Read);
  Assert.Contains(Json, '"extra":1');
  Assert.Contains(Json, '{"test":"A.B","flaky":true}');
  Read.Ci.Build.TestsKnown := False;
  Read.Ci.Build.Failures := nil;
  Json := TAtlasProjectSummaries.ToJson(Read);
  Assert.DoesNotContain(Json, '"passed"');
  Assert.DoesNotContain(Json, '"failures"');
end;

procedure TAtlasProjectSummaryTests.TodosRejectInvalidAnswer;
var
  Todos: TAtlasProjectTodos;
begin
  Assert.IsFalse(TAtlasProjectTodos.FromServer('', 0, Todos));
  Assert.IsFalse(TAtlasProjectTodos.FromServer('"# TODOs"', 0, Todos));
  Assert.IsFalse(TAtlasProjectTodos.FromServer('{"summary": {"files": 1}}', 0, Todos));
  Assert.IsFalse(Todos.Known);
  // Ein Projekt ohne TODOs: 0 ist ein Wert, keine Lücke.
  Assert.IsTrue(TAtlasProjectTodos.FromServer('{"summary": {"files": 0, "open": 0, "done": 0, "keywords": {}}}', 1,
    Todos));
  Assert.IsTrue(Todos.Known);
  Assert.AreEqual(0, Integer(Length(Todos.Keywords)));
end;

procedure TAtlasProjectSummaryTests.BaselineRoundTripAndUnknownFields;
var
  Summary, Read: TAtlasProjectSummary;
  Stamp: TDateTime;
  Json: string;
begin
  Stamp := EncodeDate(2026, 10, 15) + EncodeTime(9, 30, 0, 0);
  Summary := TAtlasProjectSummary.Create(Project);
  Summary.Baseline.Known := True;
  Summary.Baseline.At := Stamp;
  Summary.Baseline.Exists := True;
  Summary.Baseline.Valid := True;
  Summary.Baseline.Entries := 40;
  Summary.Baseline.Hits := 52;
  Summary.Baseline.Orphaned := 2;
  Json := TAtlasProjectSummaries.ToJson(Summary);
  // Ohne Aktualisieren über Atlas keine Zähler.
  Assert.Contains(Json, '"baseline":{"at":"2026-10-15T09:30:00Z","exists":true,"valid":true,"entries":40,' +
    '"hits":52,"orphaned":2}');
  Summary.Baseline.Updated := Stamp;
  Summary.Baseline.Added := 3;
  Summary.Baseline.Removed := 5;
  Json := TAtlasProjectSummaries.ToJson(Summary);
  Assert.Contains(Json, '"orphaned":2,"updated":"2026-10-15T09:30:00Z","added":3,"removed":5}');
  Assert.IsTrue(TAtlasProjectSummaries.Parse(Json, Read));
  Assert.IsTrue(Read.Baseline.Known);
  Assert.IsTrue(Read.Baseline.Exists);
  Assert.IsTrue(Read.Baseline.Valid);
  Assert.AreEqual(40, Read.Baseline.Entries);
  Assert.AreEqual(52, Read.Baseline.Hits);
  Assert.AreEqual(2, Read.Baseline.Orphaned);
  Assert.IsTrue(Read.Baseline.Updated = Stamp);
  Assert.AreEqual(3, Read.Baseline.Added);
  Assert.AreEqual(5, Read.Baseline.Removed);
  // Keine Baseline: bekannt, aber nicht vorhanden (Lücke im Projektverlauf, „Baseline erzeugen“ in der
  // Einrichtung); unbekannte Felder im Abschnitt bleiben.
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"project": "C:\\P.dproj", "baseline": {"at": ' +
    '"2026-10-15T09:30:00Z", "exists": false, "trend": [1, 2]}}', Read));
  Assert.IsTrue(Read.Baseline.Known);
  Assert.IsFalse(Read.Baseline.Exists);
  Assert.IsTrue(Read.Baseline.Updated = 0);
  Json := TAtlasProjectSummaries.ToJson(Read);
  Assert.Contains(Json, '"trend":[1,2]');
  Assert.IsTrue(Pos('"updated"', Json) = 0, Json);
end;

procedure TAtlasProjectSummaryTests.SetupRoundTripAndLimits;
var
  Summary, Read: TAtlasProjectSummary;
  Stamp: TDateTime;
  Json: string;
  Finding: TAtlasSetupFinding;
  Index: Integer;
begin
  Stamp := EncodeDate(2026, 10, 15) + EncodeTime(9, 30, 0, 0);
  Finding := Default(TAtlasSetupFinding);
  Summary := TAtlasProjectSummary.Create(Project);
  Assert.IsFalse(Summary.Setup.Known);
  Assert.IsFalse(Summary.Setup.PathsClean);
  Summary.Setup.Known := True;
  Summary.Setup.Dismissed := True;
  Summary.Setup.DismissedAt := Stamp;
  Json := TAtlasProjectSummaries.ToJson(Summary);
  Assert.Contains(Json, '"setup":{"dismissed":true,"dismissedAt":"2026-10-15T09:30:00Z"}');
  Summary.Setup.Dismissed := False;
  Summary.Setup.Checked := True;
  Summary.Setup.CheckedAt := Stamp;
  Summary.Setup.Files := 12;
  Summary.Setup.MissingUnitCount := 60;
  Summary.Setup.UndefinedDefineCount := 1;
  for Index := 1 to 60 do
  begin
    Finding.Name := 'Unit' + IntToStr(Index);
    Finding.FileName := 'Src\Main.pas';
    Finding.Line := Index;
    Finding.Count := 1;
    Summary.Setup.MissingUnits := Summary.Setup.MissingUnits + [Finding];
  end;
  Finding.Name := 'USE_LOG';
  Finding.FileName := '';
  Finding.Line := 0;
  Finding.Count := 3;
  Summary.Setup.UndefinedDefines := [Finding];
  Json := TAtlasProjectSummaries.ToJson(Summary);
  Assert.Contains(Json, '"setup":{"paths":{"at":"2026-10-15T09:30:00Z","files":12,"unreadable":0,' +
    '"missingUnits":60,"undefinedDefines":1,"units":[{"name":"Unit1","file":"Src\\Main.pas","line":1,"count":1}');
  Assert.Contains(Json, '"defines":[{"name":"USE_LOG","count":3}]');
  Assert.IsTrue(Pos('"Unit51"', Json) = 0, 'höchstens MaxFindings je Liste');
  Assert.IsTrue(TAtlasProjectSummaries.Parse(Json, Read));
  Assert.IsTrue(Read.Setup.Known);
  Assert.IsFalse(Read.Setup.Dismissed);
  Assert.IsTrue(Read.Setup.Checked);
  Assert.IsTrue(Read.Setup.CheckedAt = Stamp);
  Assert.AreEqual(12, Read.Setup.Files);
  Assert.AreEqual(60, Read.Setup.MissingUnitCount);
  Assert.AreEqual(TAtlasProjectSetup.MaxFindings, Integer(Length(Read.Setup.MissingUnits)));
  Assert.AreEqual('Src\Main.pas', Read.Setup.MissingUnits[0].FileName);
  Assert.AreEqual(3, Integer(Read.Setup.UndefinedDefines[0].Count));
  Assert.IsFalse(Read.Setup.PathsClean);
  // Sauber; unbekannte Felder bleiben, Zähler nie kleiner als die Funde.
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"setup": {"dismissed": false, "x": 1, "paths": {"at": ' +
    '"2026-10-15T09:30:00Z", "missingUnits": 0, "undefinedDefines": 0, "units": [], "defines": [], "y": 2}}}', Read));
  Assert.IsTrue(Read.Setup.PathsClean);
  Json := TAtlasProjectSummaries.ToJson(Read);
  Assert.Contains(Json, '"x":1');
  Assert.Contains(Json, '"y":2');
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"setup": {"paths": {"missingUnits": 0, "units": [{"name": "A"}, ' +
    '{"file": "ohne Namen"}]}}}', Read));
  Assert.AreEqual(1, Read.Setup.MissingUnitCount);
  Assert.AreEqual(1, Integer(Read.Setup.MissingUnits[0].Count));
end;

procedure TAtlasProjectSummaryTests.SetupKeepsUncertainFindings;
var
  Summary, Read: TAtlasProjectSummary;
  Finding: TAtlasSetupFinding;
  Json: string;
begin
  Summary := TAtlasProjectSummary.Create(Project);
  Summary.Setup.Known := True;
  Summary.Setup.Checked := True;
  Summary.Setup.MissingUnitCount := 2;
  Summary.Setup.UncertainUnitCount := 1;
  Summary.Setup.SkippedMacros := ['MYLIB', 'TOOLS'];
  Finding := Default(TAtlasSetupFinding);
  Finding.Name := 'Lib.Core';
  Finding.Count := 1;
  Finding.Uncertain := True;
  // Der Projektname gilt nur in der Karte einer Gruppe und wird nicht gespeichert.
  Finding.Project := 'App';
  Summary.Setup.MissingUnits := [Finding];
  Json := TAtlasProjectSummaries.ToJson(Summary);
  Assert.Contains(Json, '"uncertainUnits":1');
  Assert.IsTrue(Pos('"uncertainDefines"', Json) = 0, 'nur, wenn es unsichere gibt');
  Assert.Contains(Json, '"skippedMacros":["MYLIB","TOOLS"]');
  Assert.Contains(Json, '{"name":"Lib.Core","count":1,"uncertain":true}');
  Assert.IsTrue(Pos('"App"', Json) = 0);
  Assert.IsTrue(TAtlasProjectSummaries.Parse(Json, Read));
  Assert.AreEqual(1, Read.Setup.UncertainUnitCount);
  Assert.AreEqual('MYLIB|TOOLS', string.Join('|', Read.Setup.SkippedMacros));
  Assert.IsTrue(Read.Setup.MissingUnits[0].Uncertain);
  Assert.IsFalse(Read.Setup.PathsClean, 'ein sicherer Fund bleibt');
  // Unsichere nie mehr als alle; nur unsichere: erledigt.
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"setup": {"paths": {"missingUnits": 1, "uncertainUnits": 5, ' +
    '"skippedMacros": ["A", 3, ""]}}}', Read));
  Assert.AreEqual(1, Read.Setup.UncertainUnitCount);
  Assert.AreEqual('A', string.Join('|', Read.Setup.SkippedMacros));
  Assert.IsTrue(Read.Setup.PathsClean);
end;

procedure TAtlasProjectSummaryTests.BrokenFileSetAsideLockedFileKept;
var
  Summary: TAtlasProjectSummary;
  FileName: string;
  Lock: TFileStream;
begin
  ForceDirectories(FFolder);
  FileName := TAtlasProjectSummaries.FileFor(FFolder, Project);
  TFile.WriteAllText(FileName, '{"format": 1, "check": {');
  Assert.IsFalse(TAtlasProjectSummaries.Load(FFolder, Project, Summary));
  Assert.AreEqual(Project, Summary.Project);
  Assert.IsTrue(FileExists(FileName + TAtlasDataFile.DefectExtension), 'beiseitegelegt');
  Assert.IsTrue(TAtlasProjectSummaries.Update(FFolder, Project,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      ASummary.Hidden := True;
    end), 'beginnt neu');
  Lock := TFileStream.Create(FileName, fmOpenRead or fmShareExclusive);
  try
    Assert.IsFalse(TAtlasProjectSummaries.Update(FFolder, Project,
      procedure(var ASummary: TAtlasProjectSummary)
      begin
        ASummary.Hidden := False;
      end), 'gesperrt: nicht überschreiben');
  finally
    Lock.Free;
  end;
  Assert.IsTrue(TAtlasProjectSummaries.Load(FFolder, Project, Summary));
  Assert.IsTrue(Summary.Hidden);
  // Gemeldete Datendateien vergessen: Das Register bliebe sonst als Leck stehen.
  TAtlasDataFile.ForgetReports;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasProjectSummaryTests);

end.
