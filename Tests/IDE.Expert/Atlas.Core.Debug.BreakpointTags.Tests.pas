unit Atlas.Core.Debug.BreakpointTags.Tests;

// Tests der Haltepunkt-Etiketten (#863): Setzen ohne Doppel, Entfernen,
// Wandern und Vergessen, Vervollständigung je Projekt, JSON hin und zurück,
// Laden und Speichern im Ordner.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasBreakpointTagsTests = class
  private
    FFolder: string;
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SetTagsNormalizes;
    [Test]
    procedure AddAndRemoveTag;
    [Test]
    procedure MoveAndForget;
    [Test]
    procedure CompletionPerProject;
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
  Atlas.Core.Debug.BreakpointTags;

const
  cProject = 'C:\App\App.dproj';
  cOther = 'C:\Anderes\Anderes.dproj';
  cKunde = 'C:\App\Kunde.pas';

{ TAtlasBreakpointTagsTests }

procedure TAtlasBreakpointTagsTests.TearDown;
begin
  if (FFolder <> '') and TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  FFolder := '';
end;

procedure TAtlasBreakpointTagsTests.SetTagsNormalizes;
var
  mTags: TAtlasBreakpointTags;
  mList: TArray<string>;
begin
  mTags := TAtlasBreakpointTags.Empty;
  Assert.IsTrue(mTags.SetTags(cProject, cKunde, 42, TArray<string>.Create(' Import ', 'import', '', 'Bug 4711')));
  mList := mTags.TagsOf(cProject, 'c:/app/KUNDE.pas', 42);
  Assert.AreEqual(2, Integer(Length(mList)));
  Assert.AreEqual('Import', mList[0]);
  Assert.AreEqual('Bug 4711', mList[1]);
  Assert.IsFalse(mTags.SetTags(cProject, cKunde, 42, TArray<string>.Create('Import', 'Bug 4711')), 'gleich');
  Assert.IsFalse(mTags.SetTags(cProject, cKunde, 0, TArray<string>.Create('X')), 'ohne Zeile');
  Assert.IsFalse(mTags.SetTags(cProject, cKunde, 43, nil), 'nichts zu setzen');
  Assert.AreEqual(0, Integer(Length(mTags.TagsOf(cOther, cKunde, 42))), 'anderes Projekt');
  Assert.IsTrue(mTags.SetTags(cProject, cKunde, 42, nil));
  Assert.AreEqual(0, Integer(Length(mTags.Entries)), 'ohne Etiketten fällt der Eintrag weg');
end;

procedure TAtlasBreakpointTagsTests.AddAndRemoveTag;
var
  mTags: TAtlasBreakpointTags;
begin
  mTags := TAtlasBreakpointTags.Empty;
  Assert.IsTrue(mTags.AddTag(cProject, cKunde, 42, 'Import'));
  Assert.IsFalse(mTags.AddTag(cProject, cKunde, 42, 'IMPORT '));
  Assert.IsFalse(mTags.AddTag(cProject, cKunde, 42, ' '));
  Assert.IsTrue(mTags.AddTag(cProject, cKunde, 42, 'Bug 4711'));
  Assert.AreEqual(2, Integer(Length(mTags.TagsOf(cProject, cKunde, 42))));
  Assert.IsTrue(mTags.RemoveTag(cProject, cKunde, 42, 'import'));
  Assert.IsFalse(mTags.RemoveTag(cProject, cKunde, 42, 'Import'));
  Assert.AreEqual('Bug 4711', mTags.TagsOf(cProject, cKunde, 42)[0]);
  Assert.IsTrue(mTags.RemoveTag(cProject, cKunde, 42, 'Bug 4711'));
  Assert.AreEqual(0, Integer(Length(mTags.Entries)));
end;

procedure TAtlasBreakpointTagsTests.MoveAndForget;
var
  mTags: TAtlasBreakpointTags;
begin
  mTags := TAtlasBreakpointTags.Empty;
  mTags.AddTag(cProject, cKunde, 42, 'Import');
  mTags.AddTag(cProject, cKunde, 50, 'Alt');
  Assert.IsTrue(mTags.Move(cProject, cKunde, 42, cKunde, 50));
  Assert.AreEqual(0, Integer(Length(mTags.TagsOf(cProject, cKunde, 42))));
  Assert.AreEqual(1, Integer(Length(mTags.TagsOf(cProject, cKunde, 50))));
  Assert.AreEqual('Import', mTags.TagsOf(cProject, cKunde, 50)[0], 'ersetzt die am Ziel');
  Assert.IsFalse(mTags.Move(cProject, cKunde, 50, cKunde, 50), 'gleiche Stelle');
  Assert.IsFalse(mTags.Move(cProject, cKunde, 7, cKunde, 8), 'ohne Etiketten');
  Assert.IsTrue(mTags.Forget(cProject, cKunde, 50));
  Assert.IsFalse(mTags.Forget(cProject, cKunde, 50));
  Assert.AreEqual(0, Integer(Length(mTags.Entries)));
end;

procedure TAtlasBreakpointTagsTests.CompletionPerProject;
var
  mTags: TAtlasBreakpointTags;
  mAll, mFound: TArray<string>;
begin
  mTags := TAtlasBreakpointTags.Empty;
  mTags.SetTags(cProject, cKunde, 1, TArray<string>.Create('Import', 'Bug 4711'));
  mTags.SetTags(cProject, cKunde, 2, TArray<string>.Create('import', 'Reimport'));
  mTags.SetTags(cOther, cKunde, 1, TArray<string>.Create('Fremd'));
  mAll := mTags.AllTags(cProject);
  Assert.AreEqual(3, Integer(Length(mAll)));
  Assert.AreEqual('Bug 4711', mAll[0]);
  Assert.AreEqual('Import', mAll[1], 'erste Schreibweise');
  Assert.AreEqual('Reimport', mAll[2]);
  mFound := mTags.Complete(cProject, 'imp');
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual('Import', mFound[0], 'Anfang zuerst');
  Assert.AreEqual('Reimport', mFound[1], 'dann enthalten');
  Assert.AreEqual(3, Integer(Length(mTags.Complete(cProject, ''))));
  Assert.AreEqual(1, Integer(Length(mTags.Complete(cOther, ''))));
end;

procedure TAtlasBreakpointTagsTests.JsonRoundTrip;
var
  mTags, mLoaded: TAtlasBreakpointTags;
  mValid: Boolean;
begin
  mTags := TAtlasBreakpointTags.Empty;
  mTags.SetTags(cProject, cKunde, 42, TArray<string>.Create('Import', 'Bug 4711'));
  mLoaded := TAtlasBreakpointTags.Parse(mTags.ToJson, mValid);
  Assert.IsTrue(mValid);
  Assert.AreEqual(1, Integer(Length(mLoaded.Entries)));
  Assert.AreEqual(cProject, mLoaded.Entries[0].Project);
  Assert.AreEqual(cKunde, mLoaded.Entries[0].FileName);
  Assert.AreEqual(42, mLoaded.Entries[0].Line);
  Assert.AreEqual(2, Integer(Length(mLoaded.Entries[0].Tags)));
  Assert.AreEqual('Bug 4711', mLoaded.Entries[0].Tags[1]);
  Assert.IsTrue(Pos('"format"', mTags.ToJson) > 0);
end;

procedure TAtlasBreakpointTagsTests.ParseDropsBrokenEntries;
var
  mLoaded: TAtlasBreakpointTags;
  mValid: Boolean;
begin
  mLoaded := TAtlasBreakpointTags.Parse('{"breakpoints": [7, {"project": "p", "file": "a.pas", "line": 0, ' +
    '"tags": ["X"]}, {"project": "p", "file": "a.pas", "line": 3, "tags": [1, "Y", "y"]}, ' +
    '{"project": "p", "file": "a.pas", "line": 4, "tags": "Z"}]}', mValid);
  Assert.IsTrue(mValid);
  Assert.AreEqual(1, Integer(Length(mLoaded.Entries)));
  Assert.AreEqual(3, mLoaded.Entries[0].Line);
  Assert.AreEqual(1, Integer(Length(mLoaded.Entries[0].Tags)), 'Zahl ist kein Etikett, y doppelt');
  Assert.AreEqual('Y', mLoaded.Entries[0].Tags[0]);
  mLoaded := TAtlasBreakpointTags.Parse('kein JSON', mValid);
  Assert.IsFalse(mValid);
  Assert.AreEqual(0, Integer(Length(mLoaded.Entries)));
end;

procedure TAtlasBreakpointTagsTests.LoadAndSave;
var
  mTags, mLoaded: TAtlasBreakpointTags;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasBreakpointTags' + IntToStr(Random(1000000)));
  TDirectory.CreateDirectory(FFolder);
  mLoaded := TAtlasBreakpointTags.Load(FFolder);
  Assert.AreEqual(0, Integer(Length(mLoaded.Entries)), 'ohne Datei leer');
  mTags := TAtlasBreakpointTags.Empty;
  mTags.AddTag(cProject, cKunde, 42, 'Import');
  Assert.IsTrue(TAtlasBreakpointTags.Save(FFolder, mTags));
  Assert.IsTrue(TFile.Exists(TPath.Combine(FFolder, TAtlasBreakpointTags.cFileName)));
  mLoaded := TAtlasBreakpointTags.Load(FFolder);
  Assert.AreEqual('Import', mLoaded.TagsOf(cProject, cKunde, 42)[0]);
  Assert.IsFalse(TAtlasBreakpointTags.Save('', mTags));
  Assert.AreEqual(0, Integer(Length(TAtlasBreakpointTags.Load('').Entries)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBreakpointTagsTests);

end.
