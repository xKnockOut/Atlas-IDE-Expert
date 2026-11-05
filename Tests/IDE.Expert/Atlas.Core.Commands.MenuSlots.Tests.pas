unit Atlas.Core.Commands.MenuSlots.Tests;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Einträge der Module im Kontextmenü: Untermenüs nach Section, Trennlinien nur zwischen sichtbaren
  /// Befehlen, zu viele Einträge werden gezählt.</summary>
  [TestFixture]
  TAtlasMenuSlotsTests = class
  public
    [Test]
    procedure SectionsBecomeGroupsInOrder;
    [Test]
    procedure SeparatorsOnlyBetweenVisibleCommands;
    [Test]
    procedure GroupWithoutVisibleCommandStaysHidden;
    [Test]
    procedure CountsItemsWithoutSlot;
    [Test]
    procedure EmptyInputLeavesAllSlotsFree;
  end;

implementation

uses
  Atlas.Core.Commands.MenuSlots;

function Item(const AId, ASection: string; AVisible: Boolean): TAtlasSlotItem;
begin
  Result := Default(TAtlasSlotItem);
  Result.Id := AId;
  Result.Section := ASection;
  Result.Visible := AVisible;
end;

procedure TAtlasMenuSlotsTests.SectionsBecomeGroupsInOrder;
var
  mLayout: TAtlasSlotLayout;
begin
  mLayout := TAtlasMenuSlots.Layout(TArray<TAtlasSlotItem>.Create(Item('Debug.A', 'Debuggen', True),
    Item('Path', '', True), Item('Tests.A', 'Tests', True), Item('Debug.B', 'Debuggen', True)), 2, 3, 3);
  Assert.AreEqual('Debuggen', mLayout.Groups[0].Caption);
  Assert.AreEqual(0, mLayout.Groups[0].Items[0]);
  Assert.AreEqual(3, mLayout.Groups[0].Items[1]);
  Assert.AreEqual(-1, mLayout.Groups[0].Items[2]);
  Assert.AreEqual('Tests', mLayout.Groups[1].Caption);
  Assert.AreEqual(2, mLayout.Groups[1].Items[0]);
  Assert.AreEqual('', mLayout.Groups[2].Caption, 'dritte Gruppe frei');
  Assert.IsFalse(mLayout.Groups[2].Shown);
  Assert.AreEqual(1, mLayout.Top.Items[0]);
  Assert.IsTrue(mLayout.Top.Visible[0]);
  Assert.IsFalse(mLayout.Top.Visible[1], 'freier Platz');
  Assert.AreEqual(0, mLayout.Missing);
end;

procedure TAtlasMenuSlotsTests.SeparatorsOnlyBetweenVisibleCommands;
var
  mLayout: TAtlasSlotLayout;
begin
  // Führende Trennlinie, zwei Trennlinien hintereinander, ausgeblendeter Befehl, Trennlinie am Ende.
  mLayout := TAtlasMenuSlots.Layout(TArray<TAtlasSlotItem>.Create(Item('-', 'N', True), Item('A', 'N', True),
    Item('-', 'N', True), Item('-', 'N', True), Item('B', 'N', False), Item('C', 'N', True),
    Item('-', 'N', True)), 0, 1, 8);
  Assert.IsFalse(mLayout.Groups[0].Visible[0], 'führende Trennlinie');
  Assert.IsTrue(mLayout.Groups[0].Visible[1]);
  Assert.IsFalse(mLayout.Groups[0].Visible[2], 'erste von zwei Trennlinien');
  Assert.IsTrue(mLayout.Groups[0].Visible[3], 'letzte von zwei Trennlinien');
  Assert.IsFalse(mLayout.Groups[0].Visible[4], 'ausgeblendeter Befehl');
  Assert.IsTrue(mLayout.Groups[0].Visible[5]);
  Assert.IsFalse(mLayout.Groups[0].Visible[6], 'Trennlinie am Ende');
  Assert.IsTrue(mLayout.Groups[0].Shown);
end;

procedure TAtlasMenuSlotsTests.GroupWithoutVisibleCommandStaysHidden;
var
  mLayout: TAtlasSlotLayout;
begin
  mLayout := TAtlasMenuSlots.Layout(TArray<TAtlasSlotItem>.Create(Item('A', 'Tests', False),
    Item('-', 'Tests', True)), 0, 1, 4);
  Assert.AreEqual('Tests', mLayout.Groups[0].Caption);
  Assert.IsFalse(mLayout.Groups[0].Shown);
  Assert.IsFalse(mLayout.Groups[0].Visible[0]);
  Assert.IsFalse(mLayout.Groups[0].Visible[1]);
end;

procedure TAtlasMenuSlotsTests.CountsItemsWithoutSlot;
var
  mLayout: TAtlasSlotLayout;
begin
  // Ein Platz oben, eine Gruppe mit einem Platz: je ein Eintrag zu viel, dazu eine dritte Section ohne Gruppe.
  mLayout := TAtlasMenuSlots.Layout(TArray<TAtlasSlotItem>.Create(Item('A', '', True), Item('B', '', True),
    Item('C', 'X', True), Item('D', 'X', True), Item('E', 'Y', True)), 1, 1, 1);
  Assert.AreEqual(3, mLayout.Missing);
  Assert.AreEqual(0, mLayout.Top.Items[0]);
  Assert.AreEqual(2, mLayout.Groups[0].Items[0]);
end;

procedure TAtlasMenuSlotsTests.EmptyInputLeavesAllSlotsFree;
var
  mLayout: TAtlasSlotLayout;
begin
  mLayout := TAtlasMenuSlots.Layout(nil, 2, 1, 2);
  Assert.AreEqual(2, Integer(Length(mLayout.Top.Items)));
  Assert.AreEqual(-1, mLayout.Top.Items[1]);
  Assert.IsFalse(mLayout.Top.Shown);
  Assert.AreEqual(2, Integer(Length(mLayout.Groups[0].Items)));
  Assert.AreEqual(0, mLayout.Missing);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMenuSlotsTests);

end.
