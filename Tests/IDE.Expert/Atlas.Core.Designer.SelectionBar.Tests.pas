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
    [Test]
    procedure DueNeedsFocus;
    [Test]
    procedure DueShortcutWaitsForRequest;
    [Test]
    procedure DueAfterDelay;
    [Test]
    procedure TryFontSizeRange;
    [Test]
    procedure ColorChoicesUsedFirst;
    [Test]
    procedure ItemTables;
    [Test]
    procedure StateOfItems;
    [Test]
    procedure HintArgumentOfItems;
    [Test]
    procedure TrackingNewSelection;
    [Test]
    procedure TrackingMovedSelection;
    [Test]
    procedure HistoryPushAndPop;
    [Test]
    procedure HistoryKeepsMaxSteps;
    [Test]
    procedure HistoryIgnoresEmptyStep;
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

{ TAtlasSelectionBarTests }

procedure TAtlasSelectionBarTests.CombineCommon;
var
  mValue: TAtlasBarValue;
begin
  mValue := TAtlasSelectionBar.Combine(Props(['9', '9', '9']));
  Assert.AreEqual<TAtlasBarState>(TAtlasBarState.On, mValue.State);
  Assert.AreEqual('9', mValue.Value);
  Assert.AreEqual(3, mValue.Count);
  Assert.IsFalse(mValue.Partial);
end;

procedure TAtlasSelectionBarTests.CombineMixed;
var
  mValue: TAtlasBarValue;
begin
  mValue := TAtlasSelectionBar.Combine(Props(['9', '10', '9']));
  Assert.AreEqual<TAtlasBarState>(TAtlasBarState.Mixed, mValue.State);
  Assert.AreEqual('', mValue.Value);
end;

procedure TAtlasSelectionBarTests.CombineMissingCountsPartial;
var
  mValue: TAtlasBarValue;
begin
  // Zwei Labels, ein Edit, eine ComboBox: Alignment haben nur zwei.
  mValue := TAtlasSelectionBar.Combine(Props(['taLeftJustify', 'taLeftJustify', '-', '-']));
  Assert.AreEqual<TAtlasBarState>(TAtlasBarState.On, mValue.State);
  Assert.AreEqual(2, mValue.Count);
  Assert.AreEqual(4, mValue.Total);
  Assert.IsTrue(mValue.Partial);
end;

procedure TAtlasSelectionBarTests.CombineNonePresent;
var
  mValue: TAtlasBarValue;
begin
  mValue := TAtlasSelectionBar.Combine(Props(['-', '-']));
  Assert.AreEqual<TAtlasBarState>(TAtlasBarState.None, mValue.State);
  Assert.AreEqual(0, mValue.Count);
  Assert.IsFalse(mValue.Partial);
end;

procedure TAtlasSelectionBarTests.FlagStates;
begin
  Assert.AreEqual<TAtlasBarState>(TAtlasBarState.On, TAtlasSelectionBar.Flag(Props(['True', 'True']), 'True'));
  Assert.AreEqual<TAtlasBarState>(TAtlasBarState.Off, TAtlasSelectionBar.Flag(Props(['False', 'False']), 'True'));
  Assert.AreEqual<TAtlasBarState>(TAtlasBarState.Mixed, TAtlasSelectionBar.Flag(Props(['True', 'False']), 'True'));
  Assert.AreEqual<TAtlasBarState>(TAtlasBarState.On,
    TAtlasSelectionBar.Flag(Props(['taCenter', 'taCenter']), 'TACENTER'));
end;

procedure TAtlasSelectionBarTests.FlagIgnoresMissing;
begin
  Assert.AreEqual<TAtlasBarState>(TAtlasBarState.On, TAtlasSelectionBar.Flag(Props(['True', '-', 'True']), 'True'));
  Assert.AreEqual<TAtlasBarState>(TAtlasBarState.None, TAtlasSelectionBar.Flag(Props(['-', '-']), 'True'));
end;

procedure TAtlasSelectionBarTests.SetFlagBoldMixed;
begin
  // Nur ein Label fett: halb gefüllt.
  Assert.AreEqual<TAtlasBarState>(TAtlasBarState.Mixed,
    TAtlasSelectionBar.SetFlag(Props(['[fsBold]', '[]', '[fsItalic]', '']), 'fsBold'));
  Assert.AreEqual<TAtlasBarState>(TAtlasBarState.On,
    TAtlasSelectionBar.SetFlag(Props(['[akLeft,akTop]', 'akTop,akLeft', '-']), 'akTop'));
  Assert.AreEqual<TAtlasBarState>(TAtlasBarState.Off,
    TAtlasSelectionBar.SetFlag(Props(['[akLeft,akTop]', '[akLeft]']), 'akRight'));
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
  mItems := TAtlasSelectionBar.ParseItems('bold; anchorRight, unknown, BOLD fitText Transfer');
  Assert.AreEqual(4, Integer(Length(mItems)));
  Assert.AreEqual<TAtlasBarItem>(TAtlasBarItem.Bold, mItems[0]);
  Assert.AreEqual<TAtlasBarItem>(TAtlasBarItem.AnchorRight, mItems[1]);
  Assert.AreEqual<TAtlasBarItem>(TAtlasBarItem.FitText, mItems[2]);
  Assert.AreEqual<TAtlasBarItem>(TAtlasBarItem.Transfer, mItems[3]);
  Assert.AreEqual(0, Integer(Length(TAtlasSelectionBar.ParseItems(''))));
end;

procedure TAtlasSelectionBarTests.DefaultItemsWithoutOptional;
var
  mItems: TArray<TAtlasBarItem>;
begin
  mItems := TAtlasSelectionBar.ParseItems(TAtlasSelectionBar.DefaultItems);
  Assert.AreEqual(Ord(TAtlasBarItem.Transfer) + 1, Integer(Length(mItems)));
  Assert.AreEqual<TAtlasBarItem>(TAtlasBarItem.Transfer, mItems[High(mItems)]);
  Assert.AreEqual<TAtlasBarItem>(TAtlasBarItem.FontSmaller, mItems[0]);
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

function StepOf(const AFileName: string; ACount: Integer): TAtlasBarStep;
var
  mIndex: Integer;
begin
  Result.FileName := AFileName;
  Result.Changes := nil;
  for mIndex := 1 to ACount do
  begin
    Result.Changes := Result.Changes + [TAtlasBarChange.Create('Button' + IntToStr(mIndex), 'Width', '75')];
  end;
end;

procedure TAtlasSelectionBarTests.DueNeedsFocus;
begin
  Assert.IsFalse(TAtlasSelectionBar.Due(False, False, True, 5000, 0, 100));
  Assert.IsFalse(TAtlasSelectionBar.Due(False, True, True, 5000, 0, 100));
end;

procedure TAtlasSelectionBarTests.DueShortcutWaitsForRequest;
begin
  Assert.IsFalse(TAtlasSelectionBar.Due(True, True, False, 5000, 0, 100));
  // Mit Tastendruck gleich, ohne die Verzögerung abzuwarten.
  Assert.IsTrue(TAtlasSelectionBar.Due(True, True, True, 1000, 990, 100));
end;

procedure TAtlasSelectionBarTests.DueAfterDelay;
begin
  Assert.IsFalse(TAtlasSelectionBar.Due(True, False, False, 1050, 1000, 100));
  Assert.IsTrue(TAtlasSelectionBar.Due(True, False, False, 1100, 1000, 100));
  // Refresh setzt Since auf 0: gleich zeigen.
  Assert.IsTrue(TAtlasSelectionBar.Due(True, False, True, 1000, 0, 400));
  Assert.IsTrue(TAtlasSelectionBar.IsShortcut('Shortcut'));
  Assert.IsFalse(TAtlasSelectionBar.IsShortcut('delay'));
end;

procedure TAtlasSelectionBarTests.TryFontSizeRange;
var
  mSize: Integer;
begin
  Assert.IsTrue(TAtlasSelectionBar.TryFontSize(' 12 ', mSize));
  Assert.AreEqual(12, mSize);
  Assert.IsFalse(TAtlasSelectionBar.TryFontSize('0', mSize));
  Assert.IsFalse(TAtlasSelectionBar.TryFontSize('1639', mSize));
  Assert.IsFalse(TAtlasSelectionBar.TryFontSize('zwölf', mSize));
  Assert.IsTrue(TAtlasSelectionBar.TryFontSize('1638', mSize));
end;

procedure TAtlasSelectionBarTests.ColorChoicesUsedFirst;
var
  mColors: TArray<Integer>;
  mUsed: Integer;
begin
  mColors := TAtlasSelectionBar.ColorChoices(TArray<Integer>.Create(255, 0, 255),
    TArray<Integer>.Create(0, 128, 255, 128), mUsed);
  Assert.AreEqual(2, mUsed);
  Assert.AreEqual(3, Integer(Length(mColors)));
  Assert.AreEqual(255, mColors[0]);
  Assert.AreEqual(0, mColors[1]);
  Assert.AreEqual(128, mColors[2]);
  mColors := TAtlasSelectionBar.ColorChoices(nil, TArray<Integer>.Create(1, 2), mUsed);
  Assert.AreEqual(0, mUsed);
  Assert.AreEqual(2, Integer(Length(mColors)));
end;

procedure TAtlasSelectionBarTests.ItemTables;
begin
  Assert.AreEqual('Font.Style', TAtlasBarItems.PathOf(TAtlasBarItem.Bold));
  Assert.AreEqual('fsBold', TAtlasBarItems.ElementOf(TAtlasBarItem.Bold));
  Assert.AreEqual('TAlignment', TAtlasBarItems.PropTypeOf(TAtlasBarItem.AlignCenter));
  Assert.AreEqual('', TAtlasBarItems.PropTypeOf(TAtlasBarItem.SameWidth));
  Assert.AreEqual('Width', TAtlasBarItems.PathOf(TAtlasBarItem.FitText));
  Assert.AreEqual('', TAtlasBarItems.PathOf(TAtlasBarItem.Transfer));
  Assert.AreEqual('W=', TAtlasBarItems.TextOf(TAtlasBarItem.SameWidth));
end;

procedure TAtlasSelectionBarTests.StateOfItems;
begin
  Assert.AreEqual<TAtlasBarState>(TAtlasBarState.Mixed,
    TAtlasBarItems.StateOf(TAtlasBarItem.Bold, Props(['[fsBold]', '[]'])));
  Assert.AreEqual<TAtlasBarState>(TAtlasBarState.On,
    TAtlasBarItems.StateOf(TAtlasBarItem.Enabled, Props(['True', '-', 'True'])));
  Assert.AreEqual<TAtlasBarState>(TAtlasBarState.On,
    TAtlasBarItems.StateOf(TAtlasBarItem.AlignCenter, Props(['taCenter', 'taCenter'])));
  // Werte ohne Umschalter: immer Off.
  Assert.AreEqual<TAtlasBarState>(TAtlasBarState.Off,
    TAtlasBarItems.StateOf(TAtlasBarItem.FontSize, Props(['9', '9'])));
end;

procedure TAtlasSelectionBarTests.HintArgumentOfItems;
begin
  Assert.AreEqual('Visible', TAtlasBarItems.HintArgument(TAtlasBarItem.Visible, 'Edit1'));
  Assert.AreEqual('akTop', TAtlasBarItems.HintArgument(TAtlasBarItem.AnchorTop, 'Edit1'));
  Assert.AreEqual('Edit1', TAtlasBarItems.HintArgument(TAtlasBarItem.SameHeight, 'Edit1'));
  Assert.AreEqual('', TAtlasBarItems.HintArgument(TAtlasBarItem.FontColor, 'Edit1'));
end;

procedure TAtlasSelectionBarTests.TrackingNewSelection;
var
  mTracking: TAtlasBarTracking;
begin
  mTracking := Default(TAtlasBarTracking);
  mTracking.Update('a|b', '1', 100);
  mTracking.Requested := True;
  mTracking.Update('a|b', '1', 200);
  Assert.AreEqual<UInt64>(100, mTracking.Since);
  Assert.IsTrue(mTracking.Requested);
  mTracking.Update('a|c', '1', 300);
  Assert.AreEqual<UInt64>(300, mTracking.Since);
  Assert.IsFalse(mTracking.Requested);
  mTracking.Clear;
  mTracking.Update('a|c', '1', 400);
  Assert.AreEqual<UInt64>(400, mTracking.Since);
end;

procedure TAtlasSelectionBarTests.TrackingMovedSelection;
var
  mTracking: TAtlasBarTracking;
begin
  mTracking := Default(TAtlasBarTracking);
  mTracking.Update('a|b', '1', 100);
  mTracking.Requested := True;
  mTracking.Update('a|b', '2', 250);
  Assert.AreEqual<UInt64>(250, mTracking.Since);
  Assert.AreEqual('2', mTracking.Bounds);
  // Ziehen nimmt die Anforderung nicht weg.
  Assert.IsTrue(mTracking.Requested);
end;

procedure TAtlasSelectionBarTests.HistoryPushAndPop;
var
  mHistory: TAtlasBarHistory;
  mStep: TAtlasBarStep;
begin
  mHistory := Default(TAtlasBarHistory);
  Assert.IsFalse(mHistory.CanUndo('Unit1.dfm'));
  mHistory.Push(StepOf('Unit1.dfm', 2));
  Assert.IsTrue(mHistory.CanUndo('UNIT1.DFM'));
  Assert.IsFalse(mHistory.CanUndo('Unit2.dfm'));
  Assert.IsTrue(mHistory.Pop(mStep));
  Assert.AreEqual(2, Integer(Length(mStep.Changes)));
  Assert.AreEqual('Button2', mStep.Changes[1].Name);
  Assert.IsFalse(mHistory.Pop(mStep));
end;

procedure TAtlasSelectionBarTests.HistoryKeepsMaxSteps;
var
  mHistory: TAtlasBarHistory;
  mIndex: Integer;
begin
  mHistory := Default(TAtlasBarHistory);
  for mIndex := 1 to TAtlasBarHistory.cMaxSteps + 3 do
  begin
    mHistory.Push(StepOf('Unit' + IntToStr(mIndex) + '.dfm', 1));
  end;
  Assert.AreEqual(TAtlasBarHistory.cMaxSteps, Integer(Length(mHistory.Steps)));
  Assert.AreEqual('Unit4.dfm', mHistory.Steps[0].FileName);
end;

procedure TAtlasSelectionBarTests.HistoryIgnoresEmptyStep;
var
  mHistory: TAtlasBarHistory;
begin
  mHistory := Default(TAtlasBarHistory);
  mHistory.Push(StepOf('Unit1.dfm', 0));
  Assert.AreEqual(0, Integer(Length(mHistory.Steps)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSelectionBarTests);

end.
