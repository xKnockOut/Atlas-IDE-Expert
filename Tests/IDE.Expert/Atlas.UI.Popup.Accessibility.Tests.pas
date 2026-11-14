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
  cControlTypeProperty = 30003;
  cNameProperty = 30005;
  cHelpTextProperty = 30013;
  cItemStatusProperty = 30026;
  cPositionInSetProperty = 30152;
  cSizeOfSetProperty = 30153;
  cSelectionItemPattern = 10010;
  cSelectionPattern = 10001;
  cElementNotAvailable = HResult($80040201);

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
  begin
    Result := 'deprecated';
  end;
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
  Assert.AreEqual(0, TAtlasAccessibility.NavigateTarget(cUiaNavigateFirstChild, -1, 3));
  Assert.AreEqual(2, TAtlasAccessibility.NavigateTarget(cUiaNavigateLastChild, -1, 3));
  Assert.AreEqual(-1, TAtlasAccessibility.NavigateTarget(cUiaNavigateFirstChild, -1, 0));
  Assert.AreEqual(2, TAtlasAccessibility.NavigateTarget(cUiaNavigateNextSibling, 1, 3));
  Assert.AreEqual(-1, TAtlasAccessibility.NavigateTarget(cUiaNavigateNextSibling, 2, 3));
  Assert.AreEqual(0, TAtlasAccessibility.NavigateTarget(cUiaNavigatePreviousSibling, 1, 3));
  Assert.AreEqual(-1, TAtlasAccessibility.NavigateTarget(cUiaNavigatePreviousSibling, 0, 3));
  // Einträge haben keine Kinder.
  Assert.AreEqual(-1, TAtlasAccessibility.NavigateTarget(cUiaNavigateFirstChild, 1, 3));
end;

procedure TAtlasAccessibilityTests.ItemsAreListItemsWithPositionAndStatus;
var
  mList, mFirst, mNext, mParent: IAtlasRawElementFragment;
  mBounds: TAtlasUiaRect;
begin
  mList := TAtlasAccessibleList.Create(0, 'Vorschläge', NewFake);
  mFirst := Child(mList, cUiaNavigateFirstChild);
  Assert.IsNotNull(mFirst);
  Assert.AreEqual(cUiaListItemControlType, Integer(Prop(mFirst, cControlTypeProperty)));
  Assert.AreEqual('Add', string(Prop(mFirst, cNameProperty)));
  Assert.AreEqual('function Add', string(Prop(mFirst, cHelpTextProperty)));
  Assert.AreEqual(1, Integer(Prop(mFirst, cPositionInSetProperty)));
  Assert.AreEqual(5, Integer(Prop(mFirst, cSizeOfSetProperty)));
  Assert.IsTrue(VarIsEmpty(Prop(mFirst, cItemStatusProperty)));
  mNext := Child(Child(mFirst, cUiaNavigateNextSibling), cUiaNavigateNextSibling);
  Assert.AreEqual('AddPair', string(Prop(mNext, cNameProperty)));
  Assert.AreEqual('deprecated', string(Prop(mNext, cItemStatusProperty)));
  Assert.AreEqual(3, Integer(Prop(mNext, cPositionInSetProperty)));
  Assert.AreEqual(S_OK, mNext.get_BoundingRectangle(mBounds));
  Assert.AreEqual(240.0, mBounds.Top, 0.001);
  Assert.AreEqual(200.0, mBounds.Width, 0.001);
  mParent := Child(mNext, cUiaNavigateParent);
  Assert.AreSame((mList as IUnknown), (mParent as IUnknown));
  Assert.AreEqual('Assign', string(Prop(Child(mList, cUiaNavigateLastChild), cNameProperty)));
  Assert.IsNull(Child(Child(mList, cUiaNavigateLastChild), cUiaNavigateNextSibling));
end;

procedure TAtlasAccessibilityTests.HeadersAreTextAndNotSelectable;
var
  mList, mHeader: IAtlasRawElementFragment;
  mPattern: IUnknown;
begin
  mList := TAtlasAccessibleList.Create(0, 'Vorschläge', NewFake);
  mHeader := Child(Child(mList, cUiaNavigateLastChild), cUiaNavigatePreviousSibling);
  Assert.AreEqual(cUiaTextControlType, Integer(Prop(mHeader, cControlTypeProperty)));
  Assert.AreEqual('Weitere Einträge', string(Prop(mHeader, cNameProperty)));
  Assert.AreEqual(S_OK, (mHeader as IAtlasRawElementProvider).GetPatternProvider(cSelectionItemPattern, mPattern));
  Assert.IsNull(mPattern);
end;

procedure TAtlasAccessibilityTests.SelectionFollowsTheSource;
var
  mFake: TFakeItems;
  mSource: IAtlasAccessibleItems;
  mList, mSecond: IAtlasRawElementFragment;
  mPattern: IUnknown;
  mSelected: BOOL;
begin
  mFake := NewFake;
  mSource := mFake;
  mList := TAtlasAccessibleList.Create(0, 'Vorschläge', mSource);
  Assert.AreEqual(S_OK, (mList as IAtlasRawElementProvider).GetPatternProvider(cSelectionPattern, mPattern));
  Assert.IsNotNull(mPattern);
  mSecond := Child(Child(mList, cUiaNavigateFirstChild), cUiaNavigateNextSibling);
  Assert.AreEqual(S_OK, (mSecond as IAtlasRawElementProvider).GetPatternProvider(cSelectionItemPattern, mPattern));
  Assert.IsNotNull(mPattern);
  Assert.AreEqual(S_OK, (mPattern as IAtlasSelectionItemProvider).get_IsSelected(mSelected));
  Assert.IsFalse(Boolean(mSelected));
  Assert.AreEqual(S_OK, (mPattern as IAtlasSelectionItemProvider).Select);
  Assert.AreEqual(1, mFake.Selected);
  Assert.AreEqual(S_OK, (mPattern as IAtlasSelectionItemProvider).get_IsSelected(mSelected));
  Assert.IsTrue(Boolean(mSelected));
end;

procedure TAtlasAccessibilityTests.ItemKeepsItsEntryAfterFiltering;
var
  mFake: TFakeItems;
  mSource: IAtlasAccessibleItems;
  mList, mItem: IAtlasRawElementFragment;
  mValue: OleVariant;
begin
  mFake := NewFake;
  mSource := mFake;
  mList := TAtlasAccessibleList.Create(0, 'Vorschläge', mSource);
  mItem := Child(Child(mList, cUiaNavigateFirstChild), cUiaNavigateNextSibling);
  // Weitergetippt: "Add" fällt heraus, AddStrings steht jetzt vorn.
  mFake.Ids := [1, 2];
  mFake.Names := ['AddStrings', 'AddPair'];
  Assert.AreEqual('AddStrings', string(Prop(mItem, cNameProperty)));
  Assert.AreEqual(1, Integer(Prop(mItem, cPositionInSetProperty)));
  // Ganz herausgefiltert: nicht mehr verfügbar.
  mFake.Ids := [2];
  mFake.Names := ['AddPair'];
  Assert.AreEqual(cElementNotAvailable, (mItem as IAtlasRawElementProvider).GetPropertyValue(cNameProperty, mValue));
end;

procedure TAtlasAccessibilityTests.DetachedItemsAreNotAvailable;
var
  mListObject: TAtlasAccessibleList;
  mList, mItem, mTarget: IAtlasRawElementFragment;
  mValue: OleVariant;
begin
  mListObject := TAtlasAccessibleList.Create(0, 'Vorschläge', NewFake);
  mList := mListObject;
  mItem := Child(mList, cUiaNavigateFirstChild);
  mListObject.Detach;
  Assert.AreEqual(cElementNotAvailable, (mItem as IAtlasRawElementProvider).GetPropertyValue(cNameProperty, mValue));
  Assert.AreEqual(cElementNotAvailable, mItem.Navigate(cUiaNavigateNextSibling, mTarget));
  Assert.IsNull(Child(mList, cUiaNavigateFirstChild));
end;

end.
