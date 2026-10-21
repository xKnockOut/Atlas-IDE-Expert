unit Atlas.UI.Popup.Accessibility.Tests;

// Tests der UI-Automation-Elemente der Listen (#447): Navigation, Eigenschaften der Einträge, Auswahl und
// Lösen beim Schließen. Ohne Fenster: Die Liste fragt dann keinen Host.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasAccessibilityTests = class
  public
    [Test]
    procedure NavigateTargetCoversChildrenAndSiblings;
    [Test]
    procedure ItemsAreListItemsWithPositionAndStatus;
    [Test]
    procedure HeadersAreTextAndNotSelectable;
    [Test]
    procedure SelectionFollowsTheSource;
    [Test]
    procedure ItemKeepsItsEntryAfterFiltering;
    [Test]
    procedure DetachedItemsAreNotAvailable;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Types,
  System.Variants,
  Atlas.UI.Popup.Accessibility;

const
  ControlTypeProperty = 30003;
  NameProperty = 30005;
  HelpTextProperty = 30013;
  ItemStatusProperty = 30026;
  PositionInSetProperty = 30152;
  SizeOfSetProperty = 30153;
  SelectionItemPattern = 10010;
  SelectionPattern = 10001;
  ElementNotAvailable = HResult($80040201);

type
  TFakeItems = class(TInterfacedObject, IAtlasAccessibleItems)
  public
    Ids: TArray<Integer>;
    Names: TArray<string>;
    Selected: Integer;
    function AccessibleCount: Integer;
    function AccessibleSelected: Integer;
    function AccessibleId(APosition: Integer): Integer;
    function AccessibleName(APosition: Integer): string;
    function AccessibleStatus(APosition: Integer): string;
    function AccessibleHelp(APosition: Integer): string;
    function AccessibleIsHeader(APosition: Integer): Boolean;
    function AccessibleBounds(APosition: Integer; out ARect: TRect): Boolean;
    procedure AccessibleSelect(APosition: Integer);
  end;

function TFakeItems.AccessibleCount: Integer;
begin
  Result := Length(Ids);
end;

function TFakeItems.AccessibleSelected: Integer;
begin
  Result := Selected;
end;

function TFakeItems.AccessibleId(APosition: Integer): Integer;
begin
  Result := Ids[APosition];
end;

function TFakeItems.AccessibleName(APosition: Integer): string;
begin
  Result := Names[APosition];
end;

function TFakeItems.AccessibleStatus(APosition: Integer): string;
begin
  Result := '';
  if Names[APosition] = 'AddPair' then
    Result := 'deprecated';
end;

function TFakeItems.AccessibleHelp(APosition: Integer): string;
begin
  Result := 'function ' + Names[APosition];
end;

function TFakeItems.AccessibleIsHeader(APosition: Integer): Boolean;
begin
  Result := Ids[APosition] < 0;
end;

function TFakeItems.AccessibleBounds(APosition: Integer; out ARect: TRect): Boolean;
begin
  ARect := Rect(100, 200 + 20 * APosition, 300, 220 + 20 * APosition);
  Result := True;
end;

procedure TFakeItems.AccessibleSelect(APosition: Integer);
begin
  Selected := APosition;
end;

function NewFake: TFakeItems;
begin
  Result := TFakeItems.Create;
  Result.Ids := [0, 1, 2, -4, 3];
  Result.Names := ['Add', 'AddStrings', 'AddPair', 'Weitere Einträge', 'Assign'];
  Result.Selected := 0;
end;

function Child(const AList: IAtlasRawElementFragment; ADirection: Integer): IAtlasRawElementFragment;
begin
  Assert.AreEqual(S_OK, AList.Navigate(ADirection, Result));
end;

function Prop(const AElement: IAtlasRawElementFragment; AProperty: Integer): OleVariant;
begin
  Assert.AreEqual(S_OK, (AElement as IAtlasRawElementProvider).GetPropertyValue(AProperty, Result));
end;

procedure TAtlasAccessibilityTests.NavigateTargetCoversChildrenAndSiblings;
begin
  Assert.AreEqual(0, TAtlasAccessibility.NavigateTarget(UiaNavigateFirstChild, -1, 3));
  Assert.AreEqual(2, TAtlasAccessibility.NavigateTarget(UiaNavigateLastChild, -1, 3));
  Assert.AreEqual(-1, TAtlasAccessibility.NavigateTarget(UiaNavigateFirstChild, -1, 0));
  Assert.AreEqual(2, TAtlasAccessibility.NavigateTarget(UiaNavigateNextSibling, 1, 3));
  Assert.AreEqual(-1, TAtlasAccessibility.NavigateTarget(UiaNavigateNextSibling, 2, 3));
  Assert.AreEqual(0, TAtlasAccessibility.NavigateTarget(UiaNavigatePreviousSibling, 1, 3));
  Assert.AreEqual(-1, TAtlasAccessibility.NavigateTarget(UiaNavigatePreviousSibling, 0, 3));
  // Einträge haben keine Kinder.
  Assert.AreEqual(-1, TAtlasAccessibility.NavigateTarget(UiaNavigateFirstChild, 1, 3));
end;

procedure TAtlasAccessibilityTests.ItemsAreListItemsWithPositionAndStatus;
var
  List, First, Next, Parent: IAtlasRawElementFragment;
  Bounds: TAtlasUiaRect;
begin
  List := TAtlasAccessibleList.Create(0, 'Vorschläge', NewFake);
  First := Child(List, UiaNavigateFirstChild);
  Assert.IsNotNull(First);
  Assert.AreEqual(UiaListItemControlType, Integer(Prop(First, ControlTypeProperty)));
  Assert.AreEqual('Add', string(Prop(First, NameProperty)));
  Assert.AreEqual('function Add', string(Prop(First, HelpTextProperty)));
  Assert.AreEqual(1, Integer(Prop(First, PositionInSetProperty)));
  Assert.AreEqual(5, Integer(Prop(First, SizeOfSetProperty)));
  Assert.IsTrue(VarIsEmpty(Prop(First, ItemStatusProperty)));
  Next := Child(Child(First, UiaNavigateNextSibling), UiaNavigateNextSibling);
  Assert.AreEqual('AddPair', string(Prop(Next, NameProperty)));
  Assert.AreEqual('deprecated', string(Prop(Next, ItemStatusProperty)));
  Assert.AreEqual(3, Integer(Prop(Next, PositionInSetProperty)));
  Assert.AreEqual(S_OK, Next.get_BoundingRectangle(Bounds));
  Assert.AreEqual(240.0, Bounds.Top, 0.001);
  Assert.AreEqual(200.0, Bounds.Width, 0.001);
  Parent := Child(Next, UiaNavigateParent);
  Assert.IsTrue((Parent as IUnknown) = (List as IUnknown));
  Assert.AreEqual('Assign', string(Prop(Child(List, UiaNavigateLastChild), NameProperty)));
  Assert.IsNull(Child(Child(List, UiaNavigateLastChild), UiaNavigateNextSibling));
end;

procedure TAtlasAccessibilityTests.HeadersAreTextAndNotSelectable;
var
  List, Header: IAtlasRawElementFragment;
  Pattern: IUnknown;
begin
  List := TAtlasAccessibleList.Create(0, 'Vorschläge', NewFake);
  Header := Child(Child(List, UiaNavigateLastChild), UiaNavigatePreviousSibling);
  Assert.AreEqual(UiaTextControlType, Integer(Prop(Header, ControlTypeProperty)));
  Assert.AreEqual('Weitere Einträge', string(Prop(Header, NameProperty)));
  Assert.AreEqual(S_OK, (Header as IAtlasRawElementProvider).GetPatternProvider(SelectionItemPattern, Pattern));
  Assert.IsNull(Pattern);
end;

procedure TAtlasAccessibilityTests.SelectionFollowsTheSource;
var
  Fake: TFakeItems;
  Source: IAtlasAccessibleItems;
  List, Second: IAtlasRawElementFragment;
  Pattern: IUnknown;
  Selected: BOOL;
begin
  Fake := NewFake;
  Source := Fake;
  List := TAtlasAccessibleList.Create(0, 'Vorschläge', Source);
  Assert.AreEqual(S_OK, (List as IAtlasRawElementProvider).GetPatternProvider(SelectionPattern, Pattern));
  Assert.IsNotNull(Pattern);
  Second := Child(Child(List, UiaNavigateFirstChild), UiaNavigateNextSibling);
  Assert.AreEqual(S_OK, (Second as IAtlasRawElementProvider).GetPatternProvider(SelectionItemPattern, Pattern));
  Assert.IsNotNull(Pattern);
  Assert.AreEqual(S_OK, (Pattern as IAtlasSelectionItemProvider).get_IsSelected(Selected));
  Assert.IsFalse(Boolean(Selected));
  Assert.AreEqual(S_OK, (Pattern as IAtlasSelectionItemProvider).Select);
  Assert.AreEqual(1, Fake.Selected);
  Assert.AreEqual(S_OK, (Pattern as IAtlasSelectionItemProvider).get_IsSelected(Selected));
  Assert.IsTrue(Boolean(Selected));
end;

procedure TAtlasAccessibilityTests.ItemKeepsItsEntryAfterFiltering;
var
  Fake: TFakeItems;
  Source: IAtlasAccessibleItems;
  List, Item: IAtlasRawElementFragment;
  Value: OleVariant;
begin
  Fake := NewFake;
  Source := Fake;
  List := TAtlasAccessibleList.Create(0, 'Vorschläge', Source);
  Item := Child(Child(List, UiaNavigateFirstChild), UiaNavigateNextSibling);
  // Weitergetippt: "Add" fällt heraus, AddStrings steht jetzt vorn.
  Fake.Ids := [1, 2];
  Fake.Names := ['AddStrings', 'AddPair'];
  Assert.AreEqual('AddStrings', string(Prop(Item, NameProperty)));
  Assert.AreEqual(1, Integer(Prop(Item, PositionInSetProperty)));
  // Ganz herausgefiltert: nicht mehr verfügbar.
  Fake.Ids := [2];
  Fake.Names := ['AddPair'];
  Assert.AreEqual(ElementNotAvailable, (Item as IAtlasRawElementProvider).GetPropertyValue(NameProperty, Value));
end;

procedure TAtlasAccessibilityTests.DetachedItemsAreNotAvailable;
var
  ListObject: TAtlasAccessibleList;
  List, Item, Target: IAtlasRawElementFragment;
  Value: OleVariant;
begin
  ListObject := TAtlasAccessibleList.Create(0, 'Vorschläge', NewFake);
  List := ListObject;
  Item := Child(List, UiaNavigateFirstChild);
  ListObject.Detach;
  Assert.AreEqual(ElementNotAvailable, (Item as IAtlasRawElementProvider).GetPropertyValue(NameProperty, Value));
  Assert.AreEqual(ElementNotAvailable, Item.Navigate(UiaNavigateNextSibling, Target));
  Assert.IsNull(Child(List, UiaNavigateFirstChild));
end;

end.
