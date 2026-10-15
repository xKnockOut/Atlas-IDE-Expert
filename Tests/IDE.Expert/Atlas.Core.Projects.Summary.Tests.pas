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
    [Test]
    procedure UpdateCreatesAndChanges;
    [Test]
    procedure NameWithoutExtension;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
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

procedure TAtlasProjectSummaryTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasProjects' + IntToStr(Random(1000000)));
end;

procedure TAtlasProjectSummaryTests.TearDown;
begin
  if DirectoryExists(FFolder) then
    TDirectory.Delete(FFolder, True);
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
    Assert.AreEqual(1, TJSONArray(History).Count);
    Build := Root.GetValue('build');
    Assert.IsTrue(Build is TJSONObject);
    Assert.IsTrue(TJSONObject(Build).GetValue('metrics') is TJSONObject, 'unbekanntes Feld im Abschnitt');
    Assert.AreEqual('2', TJSONObject(Build).GetValue('errors').Value, 'bekanntes Feld neu geschrieben');
    Assert.AreEqual(9, TJSONObject(Build).Count, 'acht bekannte Felder und metrics, errors nur einmal');
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

initialization
  TDUnitX.RegisterTestFixture(TAtlasProjectSummaryTests);

end.
