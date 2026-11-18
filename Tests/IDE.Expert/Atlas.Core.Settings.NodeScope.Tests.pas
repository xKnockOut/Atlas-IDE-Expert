unit Atlas.Core.Settings.NodeScope.Tests;

// Optionen je Package (#1903): Besitzer eines Elements und Zusammenführen der Änderungen mehrerer Knoten;
// Speichern einmal für alle Knoten eines Dialogs (#2372).

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
    procedure SwitchOfKeyByNameKeyOrPrefix;
    [Test]
    procedure MergeKeepsChangesOfOtherNode;
    [Test]
    procedure MergeWritesNothingWithoutChange;
    [Test]
    procedure BatchWithoutChangeStaysEmpty;
    [Test]
    procedure BatchCollectsChangesOfAllNodes;
    [Test]
    procedure BatchKeepsEmptiedText;
    [Test]
    procedure BatchClearForgetsChanges;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Catalog,
  Atlas.Core.Settings.Groups,
  Atlas.Core.Settings.History,
  Atlas.Core.Settings.NodeScope;

{ TAtlasSettingsNodeScopeTests }

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

procedure TAtlasSettingsNodeScopeTests.SwitchOfKeyByNameKeyOrPrefix;
var
  mCatalog: TAtlasSettingsCatalog;
  mGroups: TAtlasSettingsGroups;
  mIndex: Integer;
  mKey, mName: string;
begin
  mCatalog := TAtlasSettingsCatalog.CreateDefault;
  mGroups := TAtlasSettingsGroups.Create(mCatalog);
  try
    mKey := '';
    mName := '';
    for mIndex := 0 to mCatalog.Count - 1 do
    begin
      if (mCatalog[mIndex].Module = 'tests') and (mCatalog[mIndex].Key <> '') and
        not SameText(mCatalog[mIndex].Key, mCatalog[mIndex].Name) then
      begin
        mKey := mCatalog[mIndex].Key;
        mName := mCatalog[mIndex].Name;
        Break;
      end;
    end;
    Assert.AreNotEqual('', mKey, 'Schlüssel des Moduls Tests im Katalog');
    Assert.AreEqual('tests', TAtlasSettingsNodeScope.SwitchOfKey(mCatalog, mGroups, mKey));
    Assert.AreEqual('tests', TAtlasSettingsNodeScope.SwitchOfKey(mCatalog, mGroups, mName));
    Assert.AreEqual('', TAtlasSettingsNodeScope.SwitchOfKey(mCatalog, mGroups, 'Enabled'));
    Assert.AreEqual(TAtlasSettingsNodeScope.cVcsSwitch, TAtlasSettingsNodeScope.SwitchOfKey(mCatalog, mGroups,
      'VcsProjects'));
    Assert.AreEqual('', TAtlasSettingsNodeScope.SwitchOfKey(mCatalog, mGroups, 'GibtEsNicht'));
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

procedure TAtlasSettingsNodeScopeTests.BatchWithoutChangeStaysEmpty;
var
  mBatch: TAtlasSettingsBatch;
  mBase, mResult: TAtlasPluginSettings;
begin
  // Nur angesehene Knoten speichern nichts und melden nichts (#2372).
  mBatch := Default(TAtlasSettingsBatch);
  Assert.AreEqual(0, Integer(Length(mBatch.Add(TAtlasPluginSettings.Defaults, TAtlasPluginSettings.Defaults))));
  Assert.IsFalse(mBatch.HasChanges);
  mBase := TAtlasPluginSettings.Defaults;
  mBase.VisibleRows := 12;
  mResult := mBatch.ApplyTo(mBase);
  Assert.AreEqual(12, mResult.VisibleRows);
end;

procedure TAtlasSettingsNodeScopeTests.BatchCollectsChangesOfAllNodes;
var
  mBatch: TAtlasSettingsBatch;
  mLoaded, mFirst, mSecond, mStored, mResult: TAtlasPluginSettings;
begin
  mBatch := Default(TAtlasSettingsBatch);
  mLoaded := TAtlasPluginSettings.Defaults;
  mFirst := mLoaded;
  mFirst.VisibleRows := 14;
  mSecond := mLoaded;
  mSecond.CompletionListMode := 'all';
  Assert.AreEqual(1, Integer(Length(mBatch.Add(mLoaded, mFirst))));
  Assert.AreEqual(1, Integer(Length(mBatch.Add(mLoaded, mSecond))));
  Assert.IsTrue(mBatch.HasChanges);
  // Seit dem Öffnen anderswo gespeichert (gezogene Breite): bleibt erhalten.
  mStored := TAtlasPluginSettings.Defaults;
  mStored.PanelWidth := 400;
  mResult := mBatch.ApplyTo(mStored);
  Assert.AreEqual(14, mResult.VisibleRows);
  Assert.AreEqual('all', mResult.CompletionListMode);
  Assert.AreEqual(400, mResult.PanelWidth);
end;

procedure TAtlasSettingsNodeScopeTests.BatchKeepsEmptiedText;
var
  mBatch: TAtlasSettingsBatch;
  mLoaded, mAfter, mStored: TAtlasPluginSettings;
begin
  mBatch := Default(TAtlasSettingsBatch);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.ContinueCommentsBlockPrefix := '* ';
  mAfter := mLoaded;
  mAfter.ContinueCommentsBlockPrefix := '';
  mBatch.Add(mLoaded, mAfter);
  mStored := mLoaded;
  Assert.AreEqual('', mBatch.ApplyTo(mStored).ContinueCommentsBlockPrefix);
end;

procedure TAtlasSettingsNodeScopeTests.BatchClearForgetsChanges;
var
  mBatch: TAtlasSettingsBatch;
  mLoaded, mAfter: TAtlasPluginSettings;
begin
  mBatch := Default(TAtlasSettingsBatch);
  mLoaded := TAtlasPluginSettings.Defaults;
  mAfter := mLoaded;
  mAfter.VisibleRows := 14;
  mBatch.Add(mLoaded, mAfter);
  mBatch.Clear;
  Assert.IsFalse(mBatch.HasChanges);
  Assert.AreEqual(mLoaded.VisibleRows, mBatch.ApplyTo(mLoaded).VisibleRows);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsNodeScopeTests);

end.
