unit Atlas.Core.Debug.IgnoreList.Tests;

// Tests der Ignorier-Liste beim Debuggen (#517, #783): Klassen ohne
// Groß/klein und ohne Doppel, Orte je Projekt, JSON hin und zurück,
// unbrauchbare Einträge, Laden und Speichern im Ordner.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
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
  cProject = 'C:\Projekte\Demo.dproj';
  cKunde = 'C:\Projekte\Kunde.pas';

{ TAtlasDebugIgnoreListTests }

procedure TAtlasDebugIgnoreListTests.TearDown;
begin
  if (FFolder <> '') and TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  FFolder := '';
end;

procedure TAtlasDebugIgnoreListTests.ClassesWithoutCaseAndDuplicates;
var
  mList: TAtlasDebugIgnoreList;
begin
  mList := TAtlasDebugIgnoreList.Empty;
  Assert.IsTrue(mList.AddClass('EAbort'));
  Assert.IsFalse(mList.AddClass('eabort'), 'ohne Groß/klein schon da');
  Assert.IsFalse(mList.AddClass('  '));
  Assert.IsTrue(mList.AddClass(' EConvertError '));
  Assert.AreEqual(2, Integer(Length(mList.Classes)));
  Assert.AreEqual('EConvertError', mList.Classes[1], 'getrimmt');
  Assert.IsTrue(mList.IgnoresClass('EABORT'));
  Assert.IsTrue(mList.Ignores(cProject, 'EAbort', cKunde, 1));
  Assert.IsTrue(mList.RemoveClass('EAbort'));
  Assert.IsFalse(mList.RemoveClass('EAbort'));
  Assert.IsFalse(mList.IgnoresClass('EAbort'));
end;

procedure TAtlasDebugIgnoreListTests.LocationsPerProject;
var
  mList: TAtlasDebugIgnoreList;
begin
  mList := TAtlasDebugIgnoreList.Empty;
  Assert.IsTrue(mList.AddLocation(cProject, 'EConvertError', cKunde, 42));
  Assert.IsFalse(mList.AddLocation(cProject, 'econverterror', 'c:\projekte\KUNDE.pas', 42), 'gleicher Ort');
  Assert.IsFalse(mList.AddLocation(cProject, 'EConvertError', cKunde, 0), 'ohne Zeile kein Ort');
  Assert.IsFalse(mList.AddLocation(cProject, '', cKunde, 1));
  Assert.IsTrue(mList.Ignores(cProject, 'EConvertError', cKunde, 42));
  Assert.IsFalse(mList.Ignores(cProject, 'EConvertError', cKunde, 43), 'andere Zeile');
  Assert.IsFalse(mList.Ignores('C:\Anderes.dproj', 'EConvertError', cKunde, 42), 'anderes Projekt');
  Assert.IsFalse(mList.Ignores(cProject, 'EAbort', cKunde, 42), 'andere Klasse');
  Assert.AreEqual(1, Integer(Length(mList.LocationsOf(cProject))));
  Assert.AreEqual(0, Integer(Length(mList.LocationsOf('C:\Anderes.dproj'))));
  Assert.IsTrue(mList.RemoveLocation(cProject, 'EConvertError', cKunde, 42));
  Assert.IsFalse(mList.IgnoresLocation(cProject, 'EConvertError', cKunde, 42));
end;

procedure TAtlasDebugIgnoreListTests.JsonRoundTrip;
var
  mList, mLoaded: TAtlasDebugIgnoreList;
  mValid: Boolean;
begin
  mList := TAtlasDebugIgnoreList.Empty;
  mList.AddClass('EAbort');
  mList.AddLocation(cProject, 'EConvertError', cKunde, 42);
  mLoaded := TAtlasDebugIgnoreList.Parse(mList.ToJson, mValid);
  Assert.IsTrue(mValid);
  Assert.AreEqual(1, Integer(Length(mLoaded.Classes)));
  Assert.AreEqual('EAbort', mLoaded.Classes[0]);
  Assert.AreEqual(1, Integer(Length(mLoaded.Locations)));
  Assert.AreEqual(cProject, mLoaded.Locations[0].Project);
  Assert.AreEqual('EConvertError', mLoaded.Locations[0].ExceptionClass);
  Assert.AreEqual(cKunde, mLoaded.Locations[0].FileName);
  Assert.AreEqual(42, mLoaded.Locations[0].Line);
  Assert.IsTrue(Pos('"format": 1', mList.ToJson) > 0);
end;

procedure TAtlasDebugIgnoreListTests.ParseDropsBrokenEntries;
var
  mLoaded: TAtlasDebugIgnoreList;
  mValid: Boolean;
begin
  mLoaded := TAtlasDebugIgnoreList.Parse('{"classes": ["EAbort", 3, "eabort"], "locations": [{"class": "E", ' +
    '"file": "a.pas", "line": 0}, 7, {"project": "p", "class": "E", "file": "a.pas", "line": 5}]}', mValid);
  Assert.IsTrue(mValid);
  Assert.AreEqual(1, Integer(Length(mLoaded.Classes)));
  Assert.AreEqual(1, Integer(Length(mLoaded.Locations)));
  Assert.AreEqual(5, mLoaded.Locations[0].Line);
  mLoaded := TAtlasDebugIgnoreList.Parse('kein JSON', mValid);
  Assert.IsFalse(mValid);
  Assert.AreEqual(0, Integer(Length(mLoaded.Classes)));
  TAtlasDebugIgnoreList.Parse('[1, 2]', mValid);
  Assert.IsFalse(mValid);
end;

procedure TAtlasDebugIgnoreListTests.LoadAndSave;
var
  mList, mLoaded: TAtlasDebugIgnoreList;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasDebugIgnore' + IntToStr(Random(1000000)));
  TDirectory.CreateDirectory(FFolder);
  mLoaded := TAtlasDebugIgnoreList.Load(FFolder);
  Assert.AreEqual(0, Integer(Length(mLoaded.Classes)), 'ohne Datei leer');
  mList := TAtlasDebugIgnoreList.Empty;
  mList.AddClass('EAbort');
  Assert.IsTrue(TAtlasDebugIgnoreList.Save(FFolder, mList));
  Assert.IsTrue(TFile.Exists(TPath.Combine(FFolder, TAtlasDebugIgnoreList.cFileName)));
  mLoaded := TAtlasDebugIgnoreList.Load(FFolder);
  Assert.AreEqual(1, Integer(Length(mLoaded.Classes)));
  Assert.AreEqual('EAbort', mLoaded.Classes[0]);
  Assert.IsFalse(TAtlasDebugIgnoreList.Save('', mList));
  Assert.AreEqual(0, Integer(Length(TAtlasDebugIgnoreList.Load('').Classes)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDebugIgnoreListTests);

end.
