unit Atlas.Core.Debug.IgnoreList.Tests;

// Tests der Ignorier-Liste beim Debuggen (#517, #783): Klassen ohne
// Groß/klein und ohne Doppel, Orte je Projekt, JSON hin und zurück,
// unbrauchbare Einträge, Laden und Speichern im Ordner.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasDebugIgnoreListTests = class
  private
    FFolder: string;
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ClassesWithoutCaseAndDuplicates;
    [Test]
    procedure LocationsPerProject;
    [Test]
    procedure JsonRoundTrip;
    [Test]
    procedure ParseDropsBrokenEntries;
    [Test]
    procedure LoadAndSave;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Core.Debug.IgnoreList;

const
  Project = 'C:\Projekte\Demo.dproj';
  Kunde = 'C:\Projekte\Kunde.pas';

{ TAtlasDebugIgnoreListTests }

procedure TAtlasDebugIgnoreListTests.TearDown;
begin
  if (FFolder <> '') and TDirectory.Exists(FFolder) then
    TDirectory.Delete(FFolder, True);
  FFolder := '';
end;

procedure TAtlasDebugIgnoreListTests.ClassesWithoutCaseAndDuplicates;
var
  List: TAtlasDebugIgnoreList;
begin
  List := TAtlasDebugIgnoreList.Empty;
  Assert.IsTrue(List.AddClass('EAbort'));
  Assert.IsFalse(List.AddClass('eabort'), 'ohne Groß/klein schon da');
  Assert.IsFalse(List.AddClass('  '));
  Assert.IsTrue(List.AddClass(' EConvertError '));
  Assert.AreEqual(2, Integer(Length(List.Classes)));
  Assert.AreEqual('EConvertError', List.Classes[1], 'getrimmt');
  Assert.IsTrue(List.IgnoresClass('EABORT'));
  Assert.IsTrue(List.Ignores(Project, 'EAbort', Kunde, 1));
  Assert.IsTrue(List.RemoveClass('EAbort'));
  Assert.IsFalse(List.RemoveClass('EAbort'));
  Assert.IsFalse(List.IgnoresClass('EAbort'));
end;

procedure TAtlasDebugIgnoreListTests.LocationsPerProject;
var
  List: TAtlasDebugIgnoreList;
begin
  List := TAtlasDebugIgnoreList.Empty;
  Assert.IsTrue(List.AddLocation(Project, 'EConvertError', Kunde, 42));
  Assert.IsFalse(List.AddLocation(Project, 'econverterror', 'c:\projekte\KUNDE.pas', 42), 'gleicher Ort');
  Assert.IsFalse(List.AddLocation(Project, 'EConvertError', Kunde, 0), 'ohne Zeile kein Ort');
  Assert.IsFalse(List.AddLocation(Project, '', Kunde, 1));
  Assert.IsTrue(List.Ignores(Project, 'EConvertError', Kunde, 42));
  Assert.IsFalse(List.Ignores(Project, 'EConvertError', Kunde, 43), 'andere Zeile');
  Assert.IsFalse(List.Ignores('C:\Anderes.dproj', 'EConvertError', Kunde, 42), 'anderes Projekt');
  Assert.IsFalse(List.Ignores(Project, 'EAbort', Kunde, 42), 'andere Klasse');
  Assert.AreEqual(1, Integer(Length(List.LocationsOf(Project))));
  Assert.AreEqual(0, Integer(Length(List.LocationsOf('C:\Anderes.dproj'))));
  Assert.IsTrue(List.RemoveLocation(Project, 'EConvertError', Kunde, 42));
  Assert.IsFalse(List.IgnoresLocation(Project, 'EConvertError', Kunde, 42));
end;

procedure TAtlasDebugIgnoreListTests.JsonRoundTrip;
var
  List, Loaded: TAtlasDebugIgnoreList;
  Valid: Boolean;
begin
  List := TAtlasDebugIgnoreList.Empty;
  List.AddClass('EAbort');
  List.AddLocation(Project, 'EConvertError', Kunde, 42);
  Loaded := TAtlasDebugIgnoreList.Parse(List.ToJson, Valid);
  Assert.IsTrue(Valid);
  Assert.AreEqual(1, Integer(Length(Loaded.Classes)));
  Assert.AreEqual('EAbort', Loaded.Classes[0]);
  Assert.AreEqual(1, Integer(Length(Loaded.Locations)));
  Assert.AreEqual(Project, Loaded.Locations[0].Project);
  Assert.AreEqual('EConvertError', Loaded.Locations[0].ExceptionClass);
  Assert.AreEqual(Kunde, Loaded.Locations[0].FileName);
  Assert.AreEqual(42, Loaded.Locations[0].Line);
  Assert.IsTrue(Pos('"format": 1', List.ToJson) > 0);
end;

procedure TAtlasDebugIgnoreListTests.ParseDropsBrokenEntries;
var
  Loaded: TAtlasDebugIgnoreList;
  Valid: Boolean;
begin
  Loaded := TAtlasDebugIgnoreList.Parse('{"classes": ["EAbort", 3, "eabort"], "locations": [{"class": "E", ' +
    '"file": "a.pas", "line": 0}, 7, {"project": "p", "class": "E", "file": "a.pas", "line": 5}]}', Valid);
  Assert.IsTrue(Valid);
  Assert.AreEqual(1, Integer(Length(Loaded.Classes)));
  Assert.AreEqual(1, Integer(Length(Loaded.Locations)));
  Assert.AreEqual(5, Loaded.Locations[0].Line);
  Loaded := TAtlasDebugIgnoreList.Parse('kein JSON', Valid);
  Assert.IsFalse(Valid);
  Assert.AreEqual(0, Integer(Length(Loaded.Classes)));
  Loaded := TAtlasDebugIgnoreList.Parse('[1, 2]', Valid);
  Assert.IsFalse(Valid);
end;

procedure TAtlasDebugIgnoreListTests.LoadAndSave;
var
  List, Loaded: TAtlasDebugIgnoreList;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasDebugIgnore' + IntToStr(Random(1000000)));
  TDirectory.CreateDirectory(FFolder);
  Loaded := TAtlasDebugIgnoreList.Load(FFolder);
  Assert.AreEqual(0, Integer(Length(Loaded.Classes)), 'ohne Datei leer');
  List := TAtlasDebugIgnoreList.Empty;
  List.AddClass('EAbort');
  Assert.IsTrue(TAtlasDebugIgnoreList.Save(FFolder, List));
  Assert.IsTrue(TFile.Exists(TPath.Combine(FFolder, TAtlasDebugIgnoreList.FileName)));
  Loaded := TAtlasDebugIgnoreList.Load(FFolder);
  Assert.AreEqual(1, Integer(Length(Loaded.Classes)));
  Assert.AreEqual('EAbort', Loaded.Classes[0]);
  Assert.IsFalse(TAtlasDebugIgnoreList.Save('', List));
  Assert.AreEqual(0, Integer(Length(TAtlasDebugIgnoreList.Load('').Classes)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDebugIgnoreListTests);

end.
