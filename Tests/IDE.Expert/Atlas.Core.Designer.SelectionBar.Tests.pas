unit Atlas.Core.Designer.SelectionBar.Tests;

// Tests der Schnellleiste über einer Mehrfachauswahl (#735): gemeinsame und
// gemischte Werte, fehlende Eigenschaften, Mengen, Schriftgrößenschritte,
// Knopfliste und Lage der Leiste.

interface

uses
  DUnitX.TestFramework,
  System.Types,
  Atlas.Core.Designer.SelectionBar;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasSelectionBarTests = class
  public
    [Test]
    procedure CombineCommon;
    [Test]
    procedure CombineMixed;
    [Test]
    procedure CombineMissingCountsPartial;
    [Test]
    procedure CombineNonePresent;
    [Test]
    procedure FlagStates;
    [Test]
    procedure FlagIgnoresMissing;
    [Test]
    procedure SetFlagBoldMixed;
    [Test]
    procedure SetWithAddsAndRemoves;
    [Test]
    procedure TargetTurnsOnUnlessAllOn;
    [Test]
    procedure FontSizeSteps;
    [Test]
    procedure ParseItemsKeepsOrder;
    [Test]
    procedure DefaultItemsWithoutOptional;
    [Test]
    procedure PlaceAboveOrBelow;
    [Test]
    procedure PlaceOutsideIsEmpty;
  end;

implementation

uses
  System.SysUtils;

function Props(const AValues: array of string): TArray<TAtlasBarProp>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AValues));
  for mIndex := 0 to High(AValues) do
  begin
    if AValues[mIndex] = '-' then
    begin
      Result[mIndex] := TAtlasBarProp.Missing;
    end
    else
    begin
      Result[mIndex] := TAtlasBarProp.Create(AValues[mIndex]);
    end;
  end;
end;

procedure TAtlasSelectionBarTests.CombineCommon;
var
  mValue: TAtlasBarValue;
begin
  mValue := TAtlasSelectionBar.Combine(Props(['9', '9', '9']));
  Assert.IsTrue(mValue.State = TAtlasBarState.On);
  Assert.AreEqual('9', mValue.Value);
  Assert.AreEqual(3, mValue.Count);
  Assert.IsFalse(mValue.Partial);
end;

procedure TAtlasSelectionBarTests.CombineMixed;
var
  mValue: TAtlasBarValue;
begin
  mValue := TAtlasSelectionBar.Combine(Props(['9', '10', '9']));
  Assert.IsTrue(mValue.State = TAtlasBarState.Mixed);
  Assert.AreEqual('', mValue.Value);
end;

procedure TAtlasSelectionBarTests.CombineMissingCountsPartial;
var
  mValue: TAtlasBarValue;
begin
  // Zwei Labels, ein Edit, eine ComboBox: Alignment haben nur zwei.
  mValue := TAtlasSelectionBar.Combine(Props(['taLeftJustify', 'taLeftJustify', '-', '-']));
  Assert.IsTrue(mValue.State = TAtlasBarState.On);
  Assert.AreEqual(2, mValue.Count);
  Assert.AreEqual(4, mValue.Total);
  Assert.IsTrue(mValue.Partial);
end;

procedure TAtlasSelectionBarTests.CombineNonePresent;
var
  mValue: TAtlasBarValue;
begin
  mValue := TAtlasSelectionBar.Combine(Props(['-', '-']));
  Assert.IsTrue(mValue.State = TAtlasBarState.None);
  Assert.AreEqual(0, mValue.Count);
  Assert.IsFalse(mValue.Partial);
end;

procedure TAtlasSelectionBarTests.FlagStates;
begin
  Assert.IsTrue(TAtlasSelectionBar.Flag(Props(['True', 'True']), 'True') = TAtlasBarState.On);
  Assert.IsTrue(TAtlasSelectionBar.Flag(Props(['False', 'False']), 'True') = TAtlasBarState.Off);
  Assert.IsTrue(TAtlasSelectionBar.Flag(Props(['True', 'False']), 'True') = TAtlasBarState.Mixed);
  Assert.IsTrue(TAtlasSelectionBar.Flag(Props(['taCenter', 'taCenter']), 'TACENTER') = TAtlasBarState.On);
end;

procedure TAtlasSelectionBarTests.FlagIgnoresMissing;
begin
  Assert.IsTrue(TAtlasSelectionBar.Flag(Props(['True', '-', 'True']), 'True') = TAtlasBarState.On);
  Assert.IsTrue(TAtlasSelectionBar.Flag(Props(['-', '-']), 'True') = TAtlasBarState.None);
end;

procedure TAtlasSelectionBarTests.SetFlagBoldMixed;
begin
  // Nur ein Label fett: halb gefüllt.
  Assert.IsTrue(TAtlasSelectionBar.SetFlag(Props(['[fsBold]', '[]', '[fsItalic]', '']), 'fsBold') =
    TAtlasBarState.Mixed);
  Assert.IsTrue(TAtlasSelectionBar.SetFlag(Props(['[akLeft,akTop]', 'akTop,akLeft', '-']), 'akTop') =
    TAtlasBarState.On);
  Assert.IsTrue(TAtlasSelectionBar.SetFlag(Props(['[akLeft,akTop]', '[akLeft]']), 'akRight') =
    TAtlasBarState.Off);
end;

procedure TAtlasSelectionBarTests.SetWithAddsAndRemoves;
begin
  Assert.AreEqual('[akLeft,akTop,akRight]', TAtlasSelectionBar.SetWith('[akLeft,akTop]', 'akRight', True));
  Assert.AreEqual('[akLeft,akTop]', TAtlasSelectionBar.SetWith('[akLeft,akTop,akRight]', 'akRight', False));
  Assert.AreEqual('[akLeft,akTop]', TAtlasSelectionBar.SetWith('akLeft,akTop', 'AKTOP', True));
  Assert.AreEqual('[fsBold]', TAtlasSelectionBar.SetWith('[]', 'fsBold', True));
  Assert.AreEqual('[]', TAtlasSelectionBar.SetWith('', 'fsBold', False));
  Assert.IsTrue(TAtlasSelectionBar.SetHas('[ fsBold , fsItalic ]', 'fsItalic'));
end;

procedure TAtlasSelectionBarTests.TargetTurnsOnUnlessAllOn;
begin
  Assert.IsTrue(TAtlasSelectionBar.Target(TAtlasBarState.Mixed));
  Assert.IsTrue(TAtlasSelectionBar.Target(TAtlasBarState.Off));
  Assert.IsFalse(TAtlasSelectionBar.Target(TAtlasBarState.On));
end;

procedure TAtlasSelectionBarTests.FontSizeSteps;
begin
  Assert.AreEqual(10, TAtlasSelectionBar.NextFontSize(9, 1));
  Assert.AreEqual(8, TAtlasSelectionBar.NextFontSize(9, -1));
  Assert.AreEqual(TAtlasSelectionBar.cMinFontSize, TAtlasSelectionBar.NextFontSize(1, -1));
  Assert.AreEqual(2, TAtlasSelectionBar.NextFontSize(0, 1));
  Assert.AreEqual(TAtlasSelectionBar.cMaxFontSize,
    TAtlasSelectionBar.NextFontSize(TAtlasSelectionBar.cMaxFontSize, 1));
end;

procedure TAtlasSelectionBarTests.ParseItemsKeepsOrder;
var
  mItems: TArray<TAtlasBarItem>;
begin
  mItems := TAtlasSelectionBar.ParseItems('bold; anchorRight, unknown, BOLD fitText');
  Assert.AreEqual(3, Integer(Length(mItems)));
  Assert.IsTrue(mItems[0] = TAtlasBarItem.Bold);
  Assert.IsTrue(mItems[1] = TAtlasBarItem.AnchorRight);
  Assert.IsTrue(mItems[2] = TAtlasBarItem.FitText);
  Assert.AreEqual(0, Integer(Length(TAtlasSelectionBar.ParseItems(''))));
end;

procedure TAtlasSelectionBarTests.DefaultItemsWithoutOptional;
var
  mItems: TArray<TAtlasBarItem>;
begin
  mItems := TAtlasSelectionBar.ParseItems(TAtlasSelectionBar.DefaultItems);
  Assert.AreEqual(Ord(TAtlasBarItem.AlignRight) + 1, Integer(Length(mItems)));
  Assert.IsTrue(mItems[0] = TAtlasBarItem.FontSmaller);
  Assert.IsFalse(TAtlasSelectionBar.DefaultItems.Contains('fitText'));
  Assert.AreEqual('anchorRight', TAtlasSelectionBar.KeyOf(TAtlasBarItem.AnchorRight));
end;

procedure TAtlasSelectionBarTests.PlaceAboveOrBelow;
var
  mRect: TRect;
begin
  mRect := TAtlasSelectionBar.Place(Rect(100, 100, 300, 200), TSize.Create(150, 24), Rect(0, 0, 800, 600), 4);
  Assert.AreEqual(100, mRect.Left);
  Assert.AreEqual(72, mRect.Top);
  // Oben kein Platz: unter die Auswahl.
  mRect := TAtlasSelectionBar.Place(Rect(100, 10, 300, 200), TSize.Create(150, 24), Rect(0, 0, 800, 600), 4);
  Assert.AreEqual(204, mRect.Top);
  // Rechts am Rand: in den Bereich geschoben.
  mRect := TAtlasSelectionBar.Place(Rect(700, 100, 790, 200), TSize.Create(150, 24), Rect(0, 0, 800, 600), 4);
  Assert.AreEqual(650, mRect.Left);
  Assert.AreEqual(800, mRect.Right);
end;

procedure TAtlasSelectionBarTests.PlaceOutsideIsEmpty;
begin
  Assert.IsTrue(TAtlasSelectionBar.Place(Rect(900, 100, 950, 200), TSize.Create(150, 24),
    Rect(0, 0, 800, 600), 4).IsEmpty);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSelectionBarTests);

end.
