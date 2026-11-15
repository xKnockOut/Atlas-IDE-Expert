unit Atlas.Core.Commands.KeyScan.Tests;

// Tests für die Entscheidungen beim Einsammeln der Tastenkürzel (#520, #1967): welche Atlas-Taste eine Zeile
// bekommt und ob sie die Taste hält, Übernahme von Strg+F12 (#777), abzufragende Tasten, Markieren wirksamer
// Tastaturbelegungen, Zählung (#600), Einrichtung (#625), Tasten der Befehlspalette (#502) und Meldung beim Start.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasKeyScanTests = class
  public
    [Test]
    procedure AtlasKeyIdFindsAtlasRowOnly;
    [Test]
    procedure ListsOnlyKeysWithOwnRow;
    [Test]
    procedure AtlasItemHoldsFreeKeyOrPriority;
    [Test]
    procedure WindowKeyAlwaysHoldsItsKey;
    [Test]
    procedure UnitSearchItemTakesActionWithPriority;
    [Test]
    procedure AtlasCategoryNeedsAtlasOrSubcategory;
    [Test]
    procedure UnitSearchTakeOverFollowsSwitch;
    [Test]
    procedure KnownIdeCommandDropsPrefix;
    [Test]
    procedure ProbeKeysStartWithRowsAndAreUnique;
    [Test]
    procedure AtlasBindingMarkedOnlyWhenUnique;
    [Test]
    procedure IdeBindingMarksRowOrAsksForNewOne;
    [Test]
    procedure UsageIdFollowsSourceAndOrigin;
    [Test]
    procedure SetupEntryKeepsPriorityOnlyWhenAtlasWins;
    [Test]
    procedure PaletteGetsFirstHeldKeyPerCommand;
    [Test]
    procedure StartConflictsSkipReportedKeys;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Commands.KeyConflicts,
  Atlas.Core.Commands.KeyMap,
  Atlas.Core.Commands.KeyScan,
  Atlas.Core.Commands.ShortcutTips;

const
  cCtrlShiftP = $6050;
  cCtrlW = $4057;
  cCtrlF12 = $407B;
  cKeyA = $0041;
  cProbeKeyCount = 324;

function AtlasRow(AFunc: TAtlasKeyFunction; AKey: Word): TAtlasKeyItem;
begin
  Result := TAtlasKeyItem.Create(AKey, 'Taste', 'Atlas', TAtlasKeyProvenance.Create(TAtlasKeyOrigin.Atlas,
    TAtlasKeyMap.cAtlasName, TAtlasKeyMap.ContextOf(AFunc), TAtlasKeyMap.SourceOf(AFunc),
    TAtlasKeyScan.AtlasKeyId(AFunc), 1));
  Result.Func := AFunc;
end;

function Row(AOrigin: TAtlasKeyOrigin; ASource: TAtlasKeySource; const AId: string; AKey: Word): TAtlasKeyItem;
begin
  Result := TAtlasKeyItem.Create(AKey, 'Taste', AId, TAtlasKeyProvenance.Create(AOrigin, 'Name',
    TAtlasKeyContext.Editor, ASource, AId, 1));
end;

function OwnerTable(AKey: Word; const AOwner: string): TFunc<Word, string>;
begin
  Result :=
    function(AQueried: Word): string
    begin
      Result := '';
      if AQueried = AKey then
      begin
        Result := AOwner;
      end;
    end;
end;

function ReportedTable(AKey: Word): TFunc<Word, Boolean>;
begin
  Result :=
    function(AQueried: Word): Boolean
    begin
      Result := AQueried = AKey;
    end;
end;

{ TAtlasKeyScanTests }

procedure TAtlasKeyScanTests.AtlasKeyIdFindsAtlasRowOnly;
var
  mItems: TArray<TAtlasKeyItem>;
begin
  Assert.AreEqual('Atlas.Key.' + IntToStr(Ord(TAtlasKeyFunction.Check)),
    TAtlasKeyScan.AtlasKeyId(TAtlasKeyFunction.Check));
  mItems := TArray<TAtlasKeyItem>.Create(Row(TAtlasKeyOrigin.Ide, TAtlasKeySource.Action,
    TAtlasKeyScan.AtlasKeyId(TAtlasKeyFunction.Check), cCtrlW), AtlasRow(TAtlasKeyFunction.Check, cCtrlW));
  Assert.AreEqual(1, TAtlasKeyScan.IndexOfFunc(mItems, TAtlasKeyFunction.Check), 'gleiche Kennung der IDE zählt nicht');
  Assert.AreEqual(-1, TAtlasKeyScan.IndexOfFunc(mItems, TAtlasKeyFunction.Palette));
end;

procedure TAtlasKeyScanTests.ListsOnlyKeysWithOwnRow;
begin
  Assert.IsTrue(TAtlasKeyScan.IsListed(TAtlasKeyEntry.Create(TAtlasKeyFunction.Palette, cCtrlShiftP, False)));
  Assert.IsFalse(TAtlasKeyScan.IsListed(TAtlasKeyEntry.Create(TAtlasKeyFunction.Palette, 0, False)), 'ohne Taste');
  Assert.IsFalse(TAtlasKeyScan.IsListed(TAtlasKeyEntry.Create(TAtlasKeyFunction.Palette, cCtrlShiftP, False, False)),
    'abgeschaltet');
  Assert.IsFalse(TAtlasKeyScan.IsListed(TAtlasKeyEntry.Create(TAtlasKeyFunction.UnitSearchIde, cCtrlF12, True)),
    'Strg+F12 kommt mit den Aktionen');
end;

procedure TAtlasKeyScanTests.AtlasItemHoldsFreeKeyOrPriority;
var
  mItem: TAtlasKeyItem;
begin
  mItem := TAtlasKeyScan.AtlasItem(TAtlasKeyEntry.Create(TAtlasKeyFunction.Palette, cCtrlShiftP, False), 'Text',
    'Palette', OwnerTable(cCtrlW, 'Fremd'));
  Assert.IsTrue(mItem.Active, 'frei');
  Assert.AreEqual(TAtlasKeyMap.cAtlasName, mItem.Category);
  Assert.AreEqual('Text', mItem.KeyText);
  Assert.AreEqual('Palette', mItem.Command);
  Assert.AreEqual(TAtlasKeyScan.AtlasKeyId(TAtlasKeyFunction.Palette), mItem.Id);
  Assert.AreEqual(TAtlasKeyScan.BindOrderOf(TAtlasKeyFunction.Palette), mItem.Order);
  mItem := TAtlasKeyScan.AtlasItem(TAtlasKeyEntry.Create(TAtlasKeyFunction.Palette, cCtrlShiftP, False), 'Text',
    'Palette', OwnerTable(cCtrlShiftP, 'Fremd'));
  Assert.IsFalse(mItem.Active, 'belegt ohne Vorrang');
  mItem := TAtlasKeyScan.AtlasItem(TAtlasKeyEntry.Create(TAtlasKeyFunction.Palette, cCtrlShiftP, True), 'Text',
    'Palette', OwnerTable(cCtrlShiftP, 'Fremd'));
  Assert.IsTrue(mItem.Active, 'belegt mit Vorrang');
  Assert.IsTrue(mItem.Priority);
end;

procedure TAtlasKeyScanTests.WindowKeyAlwaysHoldsItsKey;
var
  mItem: TAtlasKeyItem;
begin
  mItem := TAtlasKeyScan.AtlasItem(TAtlasKeyEntry.Create(TAtlasKeyFunction.WelcomeSearch, cCtrlW, False), 'Text',
    'Suche', OwnerTable(cCtrlW, 'Fremd'));
  Assert.AreEqual(Ord(TAtlasKeySource.Window), Ord(mItem.Source));
  Assert.IsTrue(mItem.Active);
end;

procedure TAtlasKeyScanTests.UnitSearchItemTakesActionWithPriority;
var
  mItem: TAtlasKeyItem;
begin
  mItem := TAtlasKeyScan.UnitSearchItem(cCtrlF12, 'Strg+F12', 'Units suchen', 'Ansicht', 42);
  Assert.AreEqual(Ord(TAtlasKeyOrigin.Atlas), Ord(mItem.Origin));
  Assert.AreEqual(Ord(TAtlasKeySource.Action), Ord(mItem.Source));
  Assert.AreEqual(Ord(TAtlasKeyFunction.UnitSearchIde), Ord(mItem.Func));
  Assert.AreEqual('Ansicht', mItem.Category);
  Assert.AreEqual(42, mItem.Order);
  Assert.IsTrue(mItem.Priority);
end;

procedure TAtlasKeyScanTests.AtlasCategoryNeedsAtlasOrSubcategory;
begin
  Assert.IsTrue(TAtlasKeyScan.IsAtlasCategory('Atlas'));
  Assert.IsTrue(TAtlasKeyScan.IsAtlasCategory('atlas.Suche'));
  Assert.IsFalse(TAtlasKeyScan.IsAtlasCategory('AtlasSuche'));
  Assert.IsFalse(TAtlasKeyScan.IsAtlasCategory('Edit'));
end;

procedure TAtlasKeyScanTests.UnitSearchTakeOverFollowsSwitch;
var
  mEntries: TArray<TAtlasKeyEntry>;
begin
  mEntries := TArray<TAtlasKeyEntry>.Create(TAtlasKeyEntry.Create(TAtlasKeyFunction.Palette, cCtrlShiftP, False));
  Assert.IsFalse(TAtlasKeyScan.UnitSearchTakenOver(mEntries), 'ohne Eintrag');
  mEntries := mEntries + [TAtlasKeyEntry.Create(TAtlasKeyFunction.UnitSearchIde, cCtrlF12, True)];
  Assert.IsTrue(TAtlasKeyScan.UnitSearchTakenOver(mEntries));
  mEntries[1].Disabled := True;
  Assert.IsFalse(TAtlasKeyScan.UnitSearchTakenOver(mEntries));
end;

procedure TAtlasKeyScanTests.KnownIdeCommandDropsPrefix;
begin
  Assert.AreEqual('Makro abspielen', TAtlasKeyScan.KnownIdeCommand('IDE: Makro abspielen'));
  Assert.AreEqual('Ohne Vorsatz', TAtlasKeyScan.KnownIdeCommand('Ohne Vorsatz'));
end;

procedure TAtlasKeyScanTests.ProbeKeysStartWithRowsAndAreUnique;
var
  mKeys: TArray<Word>;
  mSeen: TDictionary<Word, Boolean>;
  mKey: Word;
begin
  mKeys := TAtlasKeyScan.ProbeKeys(TArray<TAtlasKeyItem>.Create(AtlasRow(TAtlasKeyFunction.Palette, cKeyA),
    AtlasRow(TAtlasKeyFunction.Check, cCtrlShiftP), AtlasRow(TAtlasKeyFunction.Check, 0)));
  Assert.AreEqual(cProbeKeyCount + 1, Integer(Length(mKeys)), 'A kommt dazu, Strg+Umschalt+P ist schon dabei');
  Assert.AreEqual(Integer(cKeyA), Integer(mKeys[0]));
  Assert.AreEqual(Integer(cCtrlShiftP), Integer(mKeys[1]));
  mSeen := TDictionary<Word, Boolean>.Create;
  try
    for mKey in mKeys do
    begin
      Assert.IsFalse(mSeen.ContainsKey(mKey), 'doppelt: ' + IntToStr(mKey));
      mSeen.Add(mKey, True);
    end;
    Assert.IsTrue(mSeen.ContainsKey($70), 'F1');
    Assert.IsTrue(mSeen.ContainsKey(TAtlasKeyMap.cScShift or $7B), 'Umschalt+F12');
    Assert.IsTrue(mSeen.ContainsKey(TAtlasKeyMap.cScAlt or $0D), 'Alt+Enter');
    Assert.IsFalse(mSeen.ContainsKey(TAtlasKeyMap.cScShift or Ord('A')), 'Umschalt+A nicht');
  finally
    mSeen.Free;
  end;
end;

procedure TAtlasKeyScanTests.AtlasBindingMarkedOnlyWhenUnique;
var
  mItems: TList<TAtlasKeyItem>;
begin
  mItems := TList<TAtlasKeyItem>.Create;
  try
    mItems.Add(AtlasRow(TAtlasKeyFunction.Check, cCtrlW));
    mItems.Add(Row(TAtlasKeyOrigin.Ide, TAtlasKeySource.Binding, 'Editor', cCtrlW));
    TAtlasKeyScan.MarkAtlasBinding(mItems, cCtrlW);
    Assert.IsTrue(mItems[0].Effective);
    Assert.IsTrue(mItems[0].Active);
    Assert.IsFalse(mItems[1].Effective);
    mItems.Add(AtlasRow(TAtlasKeyFunction.Palette, cCtrlShiftP));
    mItems.Add(AtlasRow(TAtlasKeyFunction.CodeActions, cCtrlShiftP));
    TAtlasKeyScan.MarkAtlasBinding(mItems, cCtrlShiftP);
    Assert.IsFalse(mItems[2].Effective, 'zwei Atlas-Belegungen: nicht eindeutig');
    Assert.IsFalse(mItems[3].Effective);
  finally
    mItems.Free;
  end;
end;

procedure TAtlasKeyScanTests.IdeBindingMarksRowOrAsksForNewOne;
var
  mItems: TList<TAtlasKeyItem>;
begin
  mItems := TList<TAtlasKeyItem>.Create;
  try
    mItems.Add(Row(TAtlasKeyOrigin.Ide, TAtlasKeySource.Binding, 'Editor', cCtrlW));
    mItems.Add(Row(TAtlasKeyOrigin.Ide, TAtlasKeySource.Action, 'Speichern', cKeyA));
    mItems.Add(Row(TAtlasKeyOrigin.Plugin, TAtlasKeySource.Action, 'Fremd', cCtrlShiftP));
    Assert.IsFalse(TAtlasKeyScan.MarkIdeBinding(mItems, cCtrlW));
    Assert.IsTrue(mItems[0].Effective);
    Assert.IsFalse(TAtlasKeyScan.MarkIdeBinding(mItems, cKeyA), 'nur IDE: keine neue Zeile');
    Assert.IsFalse(mItems[1].Effective);
    Assert.IsTrue(TAtlasKeyScan.MarkIdeBinding(mItems, cCtrlShiftP), 'Taste einer Erweiterung');
    Assert.IsFalse(TAtlasKeyScan.MarkIdeBinding(mItems, cCtrlF12), 'Taste ohne Zeile');
  finally
    mItems.Free;
  end;
end;

procedure TAtlasKeyScanTests.UsageIdFollowsSourceAndOrigin;
var
  mItem: TAtlasKeyItem;
begin
  mItem := AtlasRow(TAtlasKeyFunction.Palette, cCtrlShiftP);
  Assert.AreEqual(TAtlasShortcutTips.AtlasCommandId(TAtlasKeyFunction.Palette), TAtlasKeyScan.UsageIdOf(mItem));
  mItem := TAtlasKeyScan.UnitSearchItem(cCtrlF12, 'Strg+F12', 'Units suchen', 'Ansicht', 1);
  Assert.AreEqual(TAtlasShortcutTips.AtlasCommandId(TAtlasKeyFunction.UnitSearchIde), TAtlasKeyScan.UsageIdOf(mItem));
  Assert.AreEqual('ViewUnitsCommand', TAtlasKeyScan.UsageIdOf(Row(TAtlasKeyOrigin.Ide, TAtlasKeySource.Action,
    'ViewUnitsCommand', cCtrlF12)));
  Assert.AreEqual('', TAtlasKeyScan.UsageIdOf(Row(TAtlasKeyOrigin.Plugin, TAtlasKeySource.Binding, 'Editor', cCtrlW)));
  Assert.AreEqual('', TAtlasKeyScan.UsageIdOf(AtlasRow(TAtlasKeyFunction.WelcomeSearch, cCtrlW)));
end;

procedure TAtlasKeyScanTests.SetupEntryKeepsPriorityOnlyWhenAtlasWins;
var
  mItems: TArray<TAtlasKeyItem>;
  mEntry: TAtlasKeyEntry;
  mOwner: string;
begin
  mItems := TArray<TAtlasKeyItem>.Create(AtlasRow(TAtlasKeyFunction.Palette, cCtrlShiftP),
    Row(TAtlasKeyOrigin.Ide, TAtlasKeySource.Binding, 'Makro', cCtrlShiftP));
  mItems[0].Active := True;
  mItems[0].Priority := True;
  mItems[1].Effective := True;
  TAtlasKeyMap.Analyze(mItems);
  mEntry := TAtlasKeyScan.SetupEntry(mItems, TAtlasKeyEntry.Create(TAtlasKeyFunction.Palette, cCtrlShiftP, True),
    mOwner);
  Assert.AreEqual(mItems[1].Holder, mOwner);
  Assert.AreEqual(mItems[0].Wins, mEntry.Priority);
  mItems[0].Wins := False;
  mEntry := TAtlasKeyScan.SetupEntry(mItems, TAtlasKeyEntry.Create(TAtlasKeyFunction.Palette, cCtrlShiftP, True),
    mOwner);
  Assert.IsFalse(mEntry.Priority, 'Vorrang ohne die Taste zählt nicht');
  mEntry := TAtlasKeyScan.SetupEntry(mItems, TAtlasKeyEntry.Create(TAtlasKeyFunction.Check, cCtrlW, True), mOwner);
  Assert.AreEqual('', mOwner, 'ohne Zeile kein Besitzer');
  Assert.IsTrue(mEntry.Priority);
end;

procedure TAtlasKeyScanTests.PaletteGetsFirstHeldKeyPerCommand;
var
  mEntries, mHeld: TArray<TAtlasKeyEntry>;
begin
  Assert.AreEqual(TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.UnitSearch),
    TAtlasKeyMap.CommandIdOf(TAtlasKeyFunction.UnitSearchIde), 'Voraussetzung: gemeinsamer Befehl');
  mEntries := TArray<TAtlasKeyEntry>.Create(TAtlasKeyEntry.Create(TAtlasKeyFunction.UnitSearch, cCtrlW, False),
    TAtlasKeyEntry.Create(TAtlasKeyFunction.UnitSearchIde, cCtrlF12, False),
    TAtlasKeyEntry.Create(TAtlasKeyFunction.UnitSearch, cKeyA, False),
    TAtlasKeyEntry.Create(TAtlasKeyFunction.Palette, 0, False),
    TAtlasKeyEntry.Create(TAtlasKeyFunction.Check, cCtrlShiftP, False, False));
  mHeld := TAtlasKeyScan.HeldCommandKeys(mEntries, OwnerTable(cCtrlW, 'Fremd'));
  Assert.AreEqual(1, Integer(Length(mHeld)), 'belegt, gehalten, doppelt; ohne Taste und abgeschaltet fehlen');
  Assert.AreEqual(Integer(cCtrlF12), Integer(mHeld[0].Key));
end;

procedure TAtlasKeyScanTests.StartConflictsSkipReportedKeys;
var
  mItems: TArray<TAtlasKeyItem>;
  mConflicts: TArray<TAtlasKeyStartConflict>;
begin
  mItems := TArray<TAtlasKeyItem>.Create(AtlasRow(TAtlasKeyFunction.Palette, cCtrlShiftP),
    Row(TAtlasKeyOrigin.Ide, TAtlasKeySource.Binding, 'Makro', cCtrlShiftP));
  mItems[1].Effective := True;
  TAtlasKeyMap.Analyze(mItems);
  mConflicts := TAtlasKeyScan.StartConflicts(mItems, ReportedTable(cCtrlW));
  Assert.AreEqual(1, Integer(Length(mConflicts)));
  Assert.AreEqual(0, mConflicts[0].Index);
  Assert.AreEqual(1, mConflicts[0].Partner);
  Assert.AreEqual(mItems[0].Winner, mConflicts[0].Winner);
  mConflicts := TAtlasKeyScan.StartConflicts(mItems, ReportedTable(cCtrlShiftP));
  Assert.AreEqual(0, Integer(Length(mConflicts)), 'schon gemeldet');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasKeyScanTests);

end.
