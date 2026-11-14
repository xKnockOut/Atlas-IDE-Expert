unit Atlas.Core.Problems.ScopeProjects.Tests;

// Tests für die Bereichsliste des Fensters „Atlas-Prüfung“ mit einzelnen
// Projekten (#1843): Einträge, Trennstrich, Wahl je Eintrag, Rückfall auf das
// aktive Projekt und Vereinigung der Dateien der Gruppe.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasScopeProjectsTests = class
  public
    [Test]
    procedure ProjectNameFromFile;
    [Test]
    procedure FixedEntriesWithoutGroup;
    [Test]
    procedure ProjectsBelowSeparator;
    [Test]
    procedure SingleProjectOrSwitchOffShowsNoProjects;
    [Test]
    procedure ChoiceAndIndexRoundTrip;
    [Test]
    procedure MissingProjectFallsBackToActive;
    [Test]
    procedure HiddenProjectsFallBackToActive;
    [Test]
    procedure UnknownGroupKeepsChoice;
    [Test]
    procedure KeyFollowsActiveProject;
    [Test]
    procedure UnionDropsDuplicatesIgnoringCase;
    [Test]
    procedure FindByName;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Problems.Findings,
  Atlas.Core.Problems.ScopeProjects;

function Group(AActive: Integer): TArray<TAtlasScopeProject>;
begin
  Result := TArray<TAtlasScopeProject>.Create(
    TAtlasScopeProject.Create('C:\G\Atlas.Common.dproj', AActive = 0),
    TAtlasScopeProject.Create('C:\G\Atlas.IDE.Base.dproj', AActive = 1),
    TAtlasScopeProject.Create('C:\G\Tests\Atlas.Tests.dproj', AActive = 2));
end;

{ TAtlasScopeProjectsTests }

procedure TAtlasScopeProjectsTests.ProjectNameFromFile;
begin
  Assert.AreEqual('Atlas.IDE.Base', TAtlasScopeProject.Create('C:\G\Atlas.IDE.Base.dproj', False).Name);
  Assert.AreEqual('Kunde', TAtlasScopeProject.Create('D:/Src/Kunde.dproj', True).Name, 'auch mit /');
end;

procedure TAtlasScopeProjectsTests.FixedEntriesWithoutGroup;
var
  mList: TAtlasScopeList;
begin
  mList := TAtlasScopeList.Create(nil, True);
  Assert.AreEqual(3, mList.Count);
  Assert.AreEqual(-1, mList.SeparatorIndex);
  Assert.IsFalse(mList.IsSeparator(-1));
  Assert.AreEqual<TAtlasFindingScope>(TAtlasFindingScope.CurrentFile, mList.ChoiceAt(0).Scope);
  Assert.AreEqual<TAtlasFindingScope>(TAtlasFindingScope.Project, mList.ChoiceAt(1).Scope);
  Assert.AreEqual<TAtlasFindingScope>(TAtlasFindingScope.Group, mList.ChoiceAt(2).Scope);
  Assert.AreEqual('', mList.ActiveName);
end;

procedure TAtlasScopeProjectsTests.ProjectsBelowSeparator;
var
  mList: TAtlasScopeList;
  mProject: TAtlasScopeProject;
begin
  mList := TAtlasScopeList.Create(Group(1), True);
  Assert.AreEqual(7, mList.Count, 'drei feste, Trennstrich, drei Projekte');
  Assert.AreEqual(3, mList.SeparatorIndex);
  Assert.IsTrue(mList.IsSeparator(3));
  Assert.IsFalse(mList.ProjectAt(3, mProject), 'Trennstrich ist kein Projekt');
  Assert.IsFalse(mList.ProjectAt(1, mProject), 'fester Eintrag ist kein Projekt');
  Assert.IsTrue(mList.ProjectAt(4, mProject));
  Assert.AreEqual('Atlas.Common', mProject.Name);
  Assert.IsTrue(mList.ProjectAt(5, mProject));
  Assert.IsTrue(mProject.Active);
  Assert.IsTrue(mList.ProjectAt(6, mProject));
  Assert.AreEqual('Atlas.Tests', mProject.Name);
  Assert.IsFalse(mList.ProjectAt(7, mProject));
  Assert.AreEqual('Atlas.IDE.Base', mList.ActiveName);
end;

procedure TAtlasScopeProjectsTests.SingleProjectOrSwitchOffShowsNoProjects;
var
  mList: TAtlasScopeList;
begin
  mList := TAtlasScopeList.Create(Copy(Group(0), 0, 1), True);
  Assert.AreEqual(3, mList.Count, 'ein Projekt: keine Einzelprojekte');
  Assert.AreEqual('Atlas.Common', mList.ActiveName);
  mList := TAtlasScopeList.Create(Group(0), False);
  Assert.AreEqual(3, mList.Count, 'Schalter aus');
  Assert.AreEqual(-1, mList.SeparatorIndex);
  Assert.AreEqual('Atlas.Common', mList.ActiveName, 'das aktive kennt die Liste trotzdem');
end;

procedure TAtlasScopeProjectsTests.ChoiceAndIndexRoundTrip;
var
  mList: TAtlasScopeList;
  mIndex: Integer;
  mChoice: TAtlasScopeChoice;
begin
  mList := TAtlasScopeList.Create(Group(1), True);
  for mIndex := 0 to mList.Count - 1 do
  begin
    if not mList.IsSeparator(mIndex) then
    begin
      Assert.AreEqual(mIndex, mList.IndexOf(mList.ChoiceAt(mIndex)), 'Eintrag ' + mIndex.ToString);
    end;
  end;
  mChoice := mList.ChoiceAt(6);
  Assert.AreEqual<TAtlasFindingScope>(TAtlasFindingScope.Project, mChoice.Scope);
  Assert.AreEqual('Atlas.Tests', mChoice.Project);
  Assert.AreEqual(6, mList.IndexOf(TAtlasScopeChoice.Create(TAtlasFindingScope.Project, 'atlas.tests')),
    'Name ohne Groß-/Kleinschreibung');
  Assert.AreEqual('', TAtlasScopeChoice.Create(TAtlasFindingScope.Group, 'Atlas.Tests').Project,
    'Projekt nur beim Bereich Projekt');
  Assert.AreEqual('', mList.ChoiceAt(3).Project, 'Trennstrich ergibt das aktive Projekt');
  Assert.AreEqual<TAtlasFindingScope>(TAtlasFindingScope.Project, mList.ChoiceAt(3).Scope);
end;

procedure TAtlasScopeProjectsTests.MissingProjectFallsBackToActive;
var
  mList: TAtlasScopeList;
  mChoice: TAtlasScopeChoice;
begin
  mList := TAtlasScopeList.Create(Group(1), True);
  mChoice := mList.Resolve(TAtlasScopeChoice.Create(TAtlasFindingScope.Project, 'Atlas.Server'));
  Assert.AreEqual<TAtlasFindingScope>(TAtlasFindingScope.Project, mChoice.Scope);
  Assert.AreEqual('', mChoice.Project);
  Assert.AreEqual(1, mList.IndexOf(mChoice));
  mChoice := mList.Resolve(TAtlasScopeChoice.Create(TAtlasFindingScope.Project, 'Atlas.Common'));
  Assert.AreEqual('Atlas.Common', mChoice.Project, 'vorhandenes Projekt bleibt, auch wenn nicht aktiv');
end;

procedure TAtlasScopeProjectsTests.HiddenProjectsFallBackToActive;
var
  mChoice: TAtlasScopeChoice;
begin
  mChoice := TAtlasScopeList.Create(Group(1), False).Resolve(
    TAtlasScopeChoice.Create(TAtlasFindingScope.Project, 'Atlas.Common'));
  Assert.AreEqual('', mChoice.Project, 'Schalter aus: aktives Projekt');
end;

procedure TAtlasScopeProjectsTests.UnknownGroupKeepsChoice;
var
  mChoice: TAtlasScopeChoice;
begin
  mChoice := TAtlasScopeList.Create(nil, True).Resolve(
    TAtlasScopeChoice.Create(TAtlasFindingScope.Project, 'Atlas.Common'));
  Assert.AreEqual('Atlas.Common', mChoice.Project, 'Gruppe noch nicht geladen');
end;

procedure TAtlasScopeProjectsTests.KeyFollowsActiveProject;
begin
  Assert.AreNotEqual(TAtlasScopeList.Create(Group(0), True).Key, TAtlasScopeList.Create(Group(1), True).Key);
  Assert.AreNotEqual(TAtlasScopeList.Create(Group(0), True).Key, TAtlasScopeList.Create(Group(0), False).Key);
  Assert.AreEqual(TAtlasScopeList.Create(Group(2), True).Key, TAtlasScopeList.Create(Group(2), True).Key);
end;

procedure TAtlasScopeProjectsTests.UnionDropsDuplicatesIgnoringCase;
var
  mLists: TArray<TArray<string>>;
  mFiles: TArray<string>;
begin
  SetLength(mLists, 3);
  mLists[0] := TArray<string>.Create('C:\G\A.pas', 'C:\G\Shared.pas');
  mLists[1] := TArray<string>.Create('c:\g\shared.pas', '', 'C:\G\B.pas');
  mLists[2] := nil;
  mFiles := TAtlasScopeFiles.Union(mLists);
  Assert.AreEqual(3, Integer(Length(mFiles)));
  Assert.AreEqual('C:\G\A.pas', mFiles[0]);
  Assert.AreEqual('C:\G\Shared.pas', mFiles[1], 'erstes Auftreten gewinnt');
  Assert.AreEqual('C:\G\B.pas', mFiles[2]);
  Assert.AreEqual(0, Integer(Length(TAtlasScopeFiles.Union(nil))));
end;

procedure TAtlasScopeProjectsTests.FindByName;
var
  mProject: TAtlasScopeProject;
begin
  Assert.IsTrue(TAtlasScopeFiles.Find(Group(0), ' atlas.ide.base ', mProject));
  Assert.AreEqual('C:\G\Atlas.IDE.Base.dproj', mProject.FileName);
  Assert.IsFalse(TAtlasScopeFiles.Find(Group(0), 'Atlas.Server', mProject));
  Assert.AreEqual('', mProject.Name);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasScopeProjectsTests);

end.
