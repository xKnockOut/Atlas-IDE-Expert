unit Atlas.Core.Tests.ListFile.Tests;

// Tests der Ablage „nur für mich“ der Testlisten (#2167): Schreiben und
// Lesen, höheres Format, ungültiger Inhalt, Ablegen je Projekt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasTestListFileTests = class
  public
    [Test]
    procedure RoundTrip;
    [Test]
    procedure HigherFormatAndInvalidAreEmpty;
    [Test]
    procedure PutReplacesAndDropsEmpty;
  end;

implementation

uses
  Atlas.Core.Tests.Lists,
  Atlas.Core.Tests.ListFile;

function Entry(const AProject, ALastRun: string): TAtlasTestListProject;
begin
  Result := Default(TAtlasTestListProject);
  Result.Project := AProject;
  Result.LastRun := ALastRun;
end;

procedure TAtlasTestListFileTests.RoundTrip;
var
  mEntry: TAtlasTestListProject;
  mList: TAtlasTestList;
  mRead: TAtlasTestListProjects;
  mText: string;
begin
  mList := Default(TAtlasTestList);
  mList.Name := 'Parser';
  mList.Tests := ['Parser.Tests'];
  mEntry := Entry('C:\Projekt\Tests.dproj', 'Vor dem Commit');
  mEntry.Lists := [mList];
  mText := TAtlasTestListFile.ToJson([mEntry, Entry('C:\Ander\Ä.dproj', 'Schnell')]);
  Assert.AreEqual(1, TAtlasTestListFile.FormatOf(mText));
  mRead := TAtlasTestListFile.Parse(mText);
  Assert.AreEqual(2, Integer(Length(mRead)));
  Assert.AreEqual('C:\Projekt\Tests.dproj', mRead[0].Project);
  Assert.AreEqual('Vor dem Commit', mRead[0].LastRun);
  Assert.AreEqual(1, Integer(Length(mRead[0].Lists)));
  Assert.AreEqual('Parser', mRead[0].Lists[0].Name);
  Assert.AreEqual<TAtlasTestListStore>(TAtlasTestListStore.Personal, mRead[0].Lists[0].Store);
  Assert.AreEqual('Parser.Tests', mRead[0].Lists[0].Tests[0]);
  Assert.AreEqual('C:\Ander\Ä.dproj', mRead[1].Project);
  Assert.AreEqual(0, Integer(Length(mRead[1].Lists)));
  Assert.AreEqual(1, TAtlasTestListFile.IndexOf(mRead, 'c:\ander\Ä.dproj'));
  Assert.AreEqual(-1, TAtlasTestListFile.IndexOf(mRead, 'C:\Fehlt.dproj'));
end;

procedure TAtlasTestListFileTests.HigherFormatAndInvalidAreEmpty;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasTestListFile.Parse(
    '{"format": 2, "projects": [{"project": "C:\\a.dproj", "lastRun": "X"}]}'))));
  Assert.AreEqual(2, TAtlasTestListFile.FormatOf('{"format": 2}'));
  Assert.AreEqual(0, TAtlasTestListFile.FormatOf('kein JSON'));
  Assert.AreEqual(0, Integer(Length(TAtlasTestListFile.Parse('[1, 2]'))));
  // Ohne Projekt fällt ein Eintrag weg.
  Assert.AreEqual(1, Integer(Length(TAtlasTestListFile.Parse(
    '{"format": 1, "projects": [{"lastRun": "X"}, {"project": "C:\\a.dproj", "lastRun": "X"}]}'))));
end;

procedure TAtlasTestListFileTests.PutReplacesAndDropsEmpty;
var
  mProjects: TAtlasTestListProjects;
begin
  mProjects := nil;
  TAtlasTestListFile.Put(mProjects, Entry('C:\a.dproj', 'Eins'));
  TAtlasTestListFile.Put(mProjects, Entry('C:\b.dproj', 'Zwei'));
  TAtlasTestListFile.Put(mProjects, Entry('c:\A.dproj', 'Drei'));
  Assert.AreEqual(2, Integer(Length(mProjects)));
  Assert.AreEqual('Drei', mProjects[0].LastRun, 'zuletzt benutzt vorn');
  Assert.AreEqual('Zwei', mProjects[1].LastRun);
  // Ohne Listen und ohne letzte Liste bleibt nichts vom Projekt.
  TAtlasTestListFile.Put(mProjects, Entry('C:\b.dproj', ''));
  Assert.AreEqual(1, Integer(Length(mProjects)));
  Assert.AreEqual('c:\A.dproj', mProjects[0].Project);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTestListFileTests);

end.
