unit Atlas.Core.Editor.BarDock.Tests;

// Reihenfolge der Leisten neben dem Editor-Bereich: eigene Leisten stehen in
// Order direkt am Editor, vor den Steuerelementen der IDE; die Top-Werte
// führen die Ordnung der VCL (alTop nach Top, alBottom nach Unterkante) genau
// dorthin.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Editor.BarDock;

type
  [TestFixture]
  TAtlasBarDockTests = class
  private
    /// <summary>Reihenfolge, in der die VCL die Einträge ab dem Editor anordnet (Indizes).</summary>
    function VclOrder(ASide: TAtlasBarSide; const AItems: TArray<TAtlasBarDockItem>;
      const ATops: TArray<Integer>): string;
  public
    [Test]
    procedure BottomStatusBarBelowBindingBarAboveIdeStatus;
    [Test]
    procedure BottomNewBarAtVeryBottomIsNotOrdered;
    [Test]
    procedure BottomOrderedStaysUnchanged;
    [Test]
    procedure BottomWithoutForeignGoesBelowClientHeight;
    [Test]
    procedure BottomForeignBetweenEditorAndOwnIsNotOrdered;
    [Test]
    procedure TopOwnBarBelowIdeTabs;
    [Test]
    procedure TopOrderedStaysUnchanged;
    [Test]
    procedure EmptyIsOrdered;
  end;

implementation

uses
  System.SysUtils;

function Item(AOwn: Boolean; AOrder, ATop, AHeight: Integer): TAtlasBarDockItem;
begin
  Result := TAtlasBarDockItem.Create(AOwn, AOrder, ATop, AHeight);
end;

function TAtlasBarDockTests.VclOrder(ASide: TAtlasBarSide; const AItems: TArray<TAtlasBarDockItem>;
  const ATops: TArray<Integer>): string;
var
  mKeys: TArray<Integer>;
  mDone: TArray<Boolean>;
  mIndex, mStep, mBest: Integer;
begin
  // Ab dem Editor: oben das größte Top zuerst, unten die kleinste Unterkante zuerst.
  SetLength(mKeys, Length(AItems));
  SetLength(mDone, Length(AItems));
  for mIndex := 0 to High(AItems) do
  begin
    mKeys[mIndex] := ATops[mIndex];
    if ASide = TAtlasBarSide.Bottom then
    begin
      mKeys[mIndex] := -(ATops[mIndex] + AItems[mIndex].Height);
    end;
    mDone[mIndex] := False;
  end;
  Result := '';
  for mStep := 0 to High(AItems) do
  begin
    mBest := -1;
    for mIndex := 0 to High(AItems) do
    begin
      if not mDone[mIndex] and ((mBest < 0) or (mKeys[mIndex] > mKeys[mBest])) then
      begin
        mBest := mIndex;
      end;
    end;
    mDone[mBest] := True;
    Result := Result + IntToStr(mBest);
  end;
end;

procedure TAtlasBarDockTests.BottomStatusBarBelowBindingBarAboveIdeStatus;
var
  mItems: TArray<TAtlasBarDockItem>;
  mTops: TArray<Integer>;
begin
  // 0: Statuszeile der IDE, 1: Atlas-Statusleiste, 2: Brotkrumenleiste, frisch ganz unten eingehängt.
  mItems := TArray<TAtlasBarDockItem>.Create(Item(False, 0, 500, 24), Item(True, TAtlasBarDock.cOrderStatusBar, 478,
    22), Item(True, TAtlasBarDock.cOrderNearest, 524, 24));
  Assert.IsFalse(TAtlasBarDock.Ordered(TAtlasBarSide.Bottom, mItems));
  mTops := TAtlasBarDock.Tops(TAtlasBarSide.Bottom, mItems, 524);
  Assert.AreEqual(500, mTops[0], 'Fremde bleiben');
  Assert.AreEqual('210', VclOrder(TAtlasBarSide.Bottom, mItems, mTops));
  mItems[1].Top := mTops[1];
  mItems[2].Top := mTops[2];
  Assert.IsTrue(TAtlasBarDock.Ordered(TAtlasBarSide.Bottom, mItems));
end;

procedure TAtlasBarDockTests.BottomNewBarAtVeryBottomIsNotOrdered;
var
  mItems: TArray<TAtlasBarDockItem>;
begin
  mItems := TArray<TAtlasBarDockItem>.Create(Item(True, TAtlasBarDock.cOrderStatusBar, 400, 22),
    Item(True, TAtlasBarDock.cOrderNearest, 422, 24));
  Assert.IsFalse(TAtlasBarDock.Ordered(TAtlasBarSide.Bottom, mItems));
  Assert.AreEqual('10', VclOrder(TAtlasBarSide.Bottom, mItems, TAtlasBarDock.Tops(TAtlasBarSide.Bottom, mItems,
    446)));
end;

procedure TAtlasBarDockTests.BottomOrderedStaysUnchanged;
var
  mItems: TArray<TAtlasBarDockItem>;
begin
  // Wie nach dem Ausrichten: Brotkrumen 376..400, Statusleiste 400..422, Statuszeile der IDE 422..446.
  mItems := TArray<TAtlasBarDockItem>.Create(Item(True, TAtlasBarDock.cOrderStatusBar, 400, 22),
    Item(False, 0, 422, 24), Item(True, TAtlasBarDock.cOrderNearest, 376, 24));
  Assert.IsTrue(TAtlasBarDock.Ordered(TAtlasBarSide.Bottom, mItems));
end;

procedure TAtlasBarDockTests.BottomWithoutForeignGoesBelowClientHeight;
var
  mItems: TArray<TAtlasBarDockItem>;
  mTops: TArray<Integer>;
begin
  mItems := TArray<TAtlasBarDockItem>.Create(Item(True, TAtlasBarDock.cOrderNearest, 0, 24));
  mTops := TAtlasBarDock.Tops(TAtlasBarSide.Bottom, mItems, 300);
  Assert.IsTrue(mTops[0] + 24 > 300);
end;

procedure TAtlasBarDockTests.BottomForeignBetweenEditorAndOwnIsNotOrdered;
var
  mItems: TArray<TAtlasBarDockItem>;
begin
  mItems := TArray<TAtlasBarDockItem>.Create(Item(False, 0, 400, 20), Item(True, TAtlasBarDock.cOrderStatusBar, 420,
    22));
  Assert.IsFalse(TAtlasBarDock.Ordered(TAtlasBarSide.Bottom, mItems));
  Assert.AreEqual('10', VclOrder(TAtlasBarSide.Bottom, mItems, TAtlasBarDock.Tops(TAtlasBarSide.Bottom, mItems,
    442)));
end;

procedure TAtlasBarDockTests.TopOwnBarBelowIdeTabs;
var
  mItems: TArray<TAtlasBarDockItem>;
  mTops: TArray<Integer>;
begin
  // 0: Reiter der IDE oben, 1: Designer-Leiste, frisch bei 0 eingehängt.
  mItems := TArray<TAtlasBarDockItem>.Create(Item(False, 0, 0, 26), Item(True, TAtlasBarDock.cOrderNearest, 0, 24));
  Assert.IsFalse(TAtlasBarDock.Ordered(TAtlasBarSide.Top, mItems));
  mTops := TAtlasBarDock.Tops(TAtlasBarSide.Top, mItems, 400);
  Assert.AreEqual(0, mTops[0]);
  Assert.AreEqual('10', VclOrder(TAtlasBarSide.Top, mItems, mTops));
end;

procedure TAtlasBarDockTests.TopOrderedStaysUnchanged;
var
  mItems: TArray<TAtlasBarDockItem>;
begin
  mItems := TArray<TAtlasBarDockItem>.Create(Item(False, 0, 0, 26), Item(True, TAtlasBarDock.cOrderNearest, 26, 24));
  Assert.IsTrue(TAtlasBarDock.Ordered(TAtlasBarSide.Top, mItems));
end;

procedure TAtlasBarDockTests.EmptyIsOrdered;
begin
  Assert.IsTrue(TAtlasBarDock.Ordered(TAtlasBarSide.Bottom, nil));
  Assert.AreEqual(0, Integer(Length(TAtlasBarDock.Tops(TAtlasBarSide.Top, nil, 100))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBarDockTests);

end.
