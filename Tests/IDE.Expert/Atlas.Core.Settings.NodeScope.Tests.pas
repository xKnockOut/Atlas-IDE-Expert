unit Atlas.Core.Settings.NodeScope.Tests;

// Optionen je Package (#1903): Besitzer eines Elements und Zusammenführen der Änderungen mehrerer Knoten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSettingsNodeScopeTests = class
  public
    [Test]
    procedure BaseTakesElementsWithoutOwner;
    [Test]
    procedure BaseTakesBaseSettings;
    [Test]
    procedure ModuleTakesItsSwitchAndSections;
    [Test]
    procedure ModuleWithoutSwitchTakesOnlySections;
    [Test]
    procedure ModuleOfFollowsMasterSwitch;
    [Test]
    procedure SearchFindsCaptionAndKey;
    [Test]
    procedure MergeKeepsChangesOfOtherNode;
    [Test]
    procedure MergeWritesNothingWithoutChange;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.Catalog,
  Atlas.Core.Settings.Groups,
  Atlas.Core.Settings.History,
  Atlas.Core.Settings.NodeScope;

procedure TAtlasSettingsNodeScopeTests.BaseTakesElementsWithoutOwner;
begin
  Assert.IsTrue(TAtlasSettingsNodeScope.Base.Includes(nil, nil));
  Assert.IsFalse(TAtlasSettingsNodeScope.Module('atlas.tests', 'tests').Includes(nil, nil));
end;

procedure TAtlasSettingsNodeScopeTests.BaseTakesBaseSettings;
begin
  Assert.IsTrue(TAtlasSettingsNodeScope.Base.Includes(nil, ['']));
  Assert.IsFalse(TAtlasSettingsNodeScope.Base.Includes(nil, ['tests']));
  Assert.IsFalse(TAtlasSettingsNodeScope.Base.Includes(['atlas.tests'], nil));
  Assert.IsTrue(TAtlasSettingsNodeScope.Base.Includes(nil, ['tests', '']), 'gemischt: in beiden');
end;

procedure TAtlasSettingsNodeScopeTests.ModuleTakesItsSwitchAndSections;
var
  mScope: TAtlasSettingsNodeScope;
begin
  mScope := TAtlasSettingsNodeScope.Module('atlas.tests', 'tests');
  Assert.IsTrue(mScope.Includes(nil, ['TESTS']));
  Assert.IsTrue(mScope.Includes(['atlas.tests'], nil));
  Assert.IsFalse(mScope.Includes(nil, ['debug']));
  Assert.IsFalse(mScope.Includes(nil, ['']));
  // Beitrag eines anderen Moduls: Der Knoten des Abschnitts entscheidet, nicht der Schalter der Einstellung.
  Assert.IsFalse(mScope.Includes(['atlas.vcs'], ['tests']));
  Assert.IsTrue(TAtlasSettingsNodeScope.Module('atlas.vcs', 'vcs').Includes(['atlas.vcs'], ['issues']));
end;

procedure TAtlasSettingsNodeScopeTests.ModuleWithoutSwitchTakesOnlySections;
var
  mScope: TAtlasSettingsNodeScope;
begin
  mScope := TAtlasSettingsNodeScope.Module('atlas.assistants', '');
  Assert.IsFalse(mScope.Includes(nil, ['']));
  Assert.IsTrue(mScope.Includes(['atlas.assistants'], nil));
end;

procedure TAtlasSettingsNodeScopeTests.ModuleOfFollowsMasterSwitch;
var
  mCatalog: TAtlasSettingsCatalog;
  mGroups: TAtlasSettingsGroups;
  mIndex: Integer;
  mSwitch: string;
begin
  mCatalog := TAtlasSettingsCatalog.CreateDefault;
  mGroups := TAtlasSettingsGroups.Create(mCatalog);
  try
    // Ein Modulschalter gehört seinem Modul, „Atlas aktiv“ gehört Base.
    mSwitch := '';
    for mIndex := 0 to mCatalog.Count - 1 do
    begin
      if mCatalog[mIndex].Module = 'tests' then
      begin
        mSwitch := mCatalog[mIndex].Name;
        Break;
      end;
    end;
    Assert.AreNotEqual('', mSwitch, 'Schalter des Moduls Tests im Katalog');
    Assert.AreEqual('tests', TAtlasSettingsNodeScope.ModuleOf(mCatalog, mGroups, mSwitch));
    Assert.AreEqual('', TAtlasSettingsNodeScope.ModuleOf(mCatalog, mGroups, 'Enabled'));
    for mIndex := 0 to mCatalog.Count - 1 do
    begin
      if SameText(mGroups.ParentOf(mCatalog[mIndex].Name), mSwitch) then
      begin
        Assert.AreEqual('tests', TAtlasSettingsNodeScope.ModuleOf(mCatalog, mGroups, mCatalog[mIndex].Name),
          mCatalog[mIndex].Name);
      end;
    end;
  finally
    mGroups.Free;
    mCatalog.Free;
  end;
end;

procedure TAtlasSettingsNodeScopeTests.SearchFindsCaptionAndKey;
var
  mCatalog: TAtlasSettingsCatalog;
  mGroups: TAtlasSettingsGroups;
  mHits: TArray<TAtlasSettingHit>;
  mIndex: Integer;
  mFound: Boolean;
begin
  mCatalog := TAtlasSettingsCatalog.CreateDefault;
  mGroups := TAtlasSettingsGroups.Create(mCatalog);
  try
    Assert.AreEqual(0, Integer(Length(TAtlasSettingsSearch.Find(mCatalog, mGroups, '  ', False, 10))));
    mIndex := mCatalog.IndexOfName('Enabled');
    Assert.IsTrue(mIndex >= 0);
    mHits := TAtlasSettingsSearch.Find(mCatalog, mGroups, mCatalog[mIndex].Key, False, 1000);
    mFound := False;
    for mIndex := 0 to High(mHits) do
    begin
      mFound := mFound or ((mHits[mIndex].Name = 'Enabled') and (mHits[mIndex].Module = ''));
    end;
    Assert.IsTrue(mFound, 'Schlüssel von Enabled');
    Assert.AreEqual(2, Integer(Length(TAtlasSettingsSearch.Find(mCatalog, mGroups, 'e', False, 2))));
  finally
    mGroups.Free;
    mCatalog.Free;
  end;
end;

procedure TAtlasSettingsNodeScopeTests.MergeKeepsChangesOfOtherNode;
var
  mBefore, mAfter, mTarget: IAtlasMemorySettingsStore;
  mNames: TArray<string>;
begin
  mBefore := TAtlasMemorySettingsStore.Create;
  mBefore.WriteInteger('A', 1);
  mBefore.WriteString('B', 'alt');
  mAfter := TAtlasMemorySettingsStore.Create;
  mAfter.WriteInteger('A', 1);
  mAfter.WriteString('B', 'neu');
  // Der gespeicherte Stand hat schon die Änderung eines anderen Knotens an A.
  mTarget := TAtlasMemorySettingsStore.Create;
  mTarget.WriteInteger('A', 5);
  mTarget.WriteString('B', 'alt');
  mNames := TAtlasSettingsMerge.Changes(mBefore, mAfter, mTarget);
  Assert.AreEqual(1, Integer(Length(mNames)));
  Assert.AreEqual(5, mTarget.ReadInteger('A', 0));
  Assert.AreEqual('neu', mTarget.ReadString('B', ''));
end;

procedure TAtlasSettingsNodeScopeTests.MergeWritesNothingWithoutChange;
var
  mBefore, mAfter, mTarget: IAtlasMemorySettingsStore;
begin
  mBefore := TAtlasMemorySettingsStore.Create;
  mBefore.WriteInteger('A', 1);
  mAfter := TAtlasMemorySettingsStore.Create;
  mAfter.WriteInteger('A', 1);
  mTarget := TAtlasMemorySettingsStore.Create;
  mTarget.WriteInteger('A', 7);
  Assert.AreEqual(0, Integer(Length(TAtlasSettingsMerge.Changes(mBefore, mAfter, mTarget))));
  Assert.AreEqual(7, mTarget.ReadInteger('A', 0));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsNodeScopeTests);

end.
