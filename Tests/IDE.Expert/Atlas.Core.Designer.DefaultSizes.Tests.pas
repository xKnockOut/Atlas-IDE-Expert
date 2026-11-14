unit Atlas.Core.Designer.DefaultSizes.Tests;

// Tests für Standardgrößen je Klasse (#747): Tabelle lesen und schreiben,
// Auflösung mit Nachfahren, leere Werte, „text“, Lage in Reihen und einzeln,
// Anker und Lernen aus einem Formular.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasDefaultSizesTests = class
  public
    [Test]
    procedure ParseTable;
    [Test]
    procedure ParseSkipsBadEntries;
    [Test]
    procedure TextRoundTrip;
    [Test]
    procedure ResolveDescendants;
    [Test]
    procedure TargetValues;
    [Test]
    procedure RowAtRightEdgeKeepsRight;
    [Test]
    procedure RowAtLeftKeepsLeft;
    [Test]
    procedure SingleAnchors;
    [Test]
    procedure StackedStaySingle;
    [Test]
    procedure LearnMostFrequent;
  end;

implementation

uses
  System.Types,
  Atlas.Core.Designer.DefaultSizes;

procedure TAtlasDefaultSizesTests.ParseTable;
var
  mEntries: TArray<TAtlasSizeEntry>;
begin
  mEntries := TAtlasDefaultSizes.Parse('TButton=88,25; TCustomEdit=,23;TCheckBox = text , ');
  Assert.AreEqual(3, Integer(Length(mEntries)));
  Assert.AreEqual('TButton', mEntries[0].ClassName);
  Assert.AreEqual<TAtlasSizeKind>(TAtlasSizeKind.Fixed, mEntries[0].Width.Kind);
  Assert.AreEqual(88, mEntries[0].Width.Value);
  Assert.AreEqual(25, mEntries[0].Height.Value);
  Assert.AreEqual<TAtlasSizeKind>(TAtlasSizeKind.Keep, mEntries[1].Width.Kind);
  Assert.AreEqual(23, mEntries[1].Height.Value);
  Assert.AreEqual('TCheckBox', mEntries[2].ClassName);
  Assert.AreEqual<TAtlasSizeKind>(TAtlasSizeKind.Text, mEntries[2].Width.Kind);
  Assert.AreEqual<TAtlasSizeKind>(TAtlasSizeKind.Keep, mEntries[2].Height.Kind);
end;

procedure TAtlasDefaultSizesTests.ParseSkipsBadEntries;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasDefaultSizes.Parse(''))));
  Assert.AreEqual(1, Integer(Length(TAtlasDefaultSizes.Parse('TButton=88;TEdit=abc,21;=1,2;TPanel=0,5;TLabel=,text;' +
    'TMemo=200,100'))));
end;

procedure TAtlasDefaultSizesTests.TextRoundTrip;
const
  cText = 'TButton=88,25; TCustomEdit=,23; TCheckBox=text,';
begin
  Assert.AreEqual(cText, TAtlasDefaultSizes.ToText(TAtlasDefaultSizes.Parse(cText)));
end;

procedure TAtlasDefaultSizesTests.ResolveDescendants;
var
  mEntries: TArray<TAtlasSizeEntry>;
  mEntry: TAtlasSizeEntry;
begin
  mEntries := TAtlasDefaultSizes.Parse('TCustomEdit=,23; TMaskEdit=150,');
  Assert.IsTrue(TAtlasDefaultSizes.Resolve(mEntries, ['TEdit', 'TCustomEdit', 'TWinControl'], mEntry));
  Assert.AreEqual('TCustomEdit', mEntry.ClassName);
  Assert.IsTrue(TAtlasDefaultSizes.Resolve(mEntries, ['TMaskEdit', 'TCustomMaskEdit', 'TCustomEdit'], mEntry));
  Assert.AreEqual('TMaskEdit', mEntry.ClassName, 'eigener Eintrag gewinnt');
  Assert.IsFalse(TAtlasDefaultSizes.Resolve(mEntries, ['TButton', 'TButtonControl'], mEntry));
end;

procedure TAtlasDefaultSizesTests.TargetValues;
begin
  Assert.AreEqual(-1, TAtlasDefaultSizes.Target(TAtlasSizeValue.Keep, 50));
  Assert.AreEqual(88, TAtlasDefaultSizes.Target(TAtlasSizeValue.Fixed(88), 50));
  Assert.AreEqual(50, TAtlasDefaultSizes.Target(TAtlasSizeValue.Text, 50));
  Assert.AreEqual(-1, TAtlasDefaultSizes.Target(TAtlasSizeValue.Text, -1));
end;

procedure TAtlasDefaultSizesTests.RowAtRightEdgeKeepsRight;
var
  mRects: TArray<TRect>;
begin
  // Knopfreihe unten rechts (Parent 500 breit, rechts 8 Rand), Abstand 6: rechte Kante bleibt.
  mRects := TAtlasDefaultSizes.Layout([TAtlasSizeItem.Create(Bounds(336, 400, 75, 25), 88, 25, False, False),
    TAtlasSizeItem.Create(Bounds(417, 400, 75, 25), 88, 25, False, False)], 500);
  Assert.AreEqual(492, mRects[1].Right);
  Assert.AreEqual(404, mRects[1].Left);
  Assert.AreEqual(398, mRects[0].Right, 'Abstand 6 bleibt');
  Assert.AreEqual(310, mRects[0].Left);
end;

procedure TAtlasDefaultSizesTests.RowAtLeftKeepsLeft;
var
  mRects: TArray<TRect>;
begin
  mRects := TAtlasDefaultSizes.Layout([TAtlasSizeItem.Create(Bounds(90, 10, 75, 25), 88, -1, False, False),
    TAtlasSizeItem.Create(Bounds(8, 10, 75, 25), 88, -1, False, False)], 500);
  Assert.AreEqual(8, mRects[1].Left);
  Assert.AreEqual(96, mRects[1].Right);
  Assert.AreEqual(103, mRects[0].Left, 'Abstand 7 bleibt');
  Assert.AreEqual(25, mRects[0].Height, 'Höhe bleibt');
end;

procedure TAtlasDefaultSizesTests.SingleAnchors;
var
  mRects: TArray<TRect>;
begin
  mRects := TAtlasDefaultSizes.Layout([TAtlasSizeItem.Create(Bounds(100, 100, 75, 25), 88, 30, True, True)], 500);
  Assert.AreEqual(175, mRects[0].Right);
  Assert.AreEqual(87, mRects[0].Left);
  Assert.AreEqual(125, mRects[0].Bottom);
  Assert.AreEqual(95, mRects[0].Top);
  mRects := TAtlasDefaultSizes.Layout([TAtlasSizeItem.Create(Bounds(100, 100, 121, 21), -1, 23, False, False)], 500);
  Assert.IsTrue(mRects[0] = Bounds(100, 100, 121, 23), 'nur die Höhe');
end;

procedure TAtlasDefaultSizesTests.StackedStaySingle;
var
  mRects: TArray<TRect>;
begin
  // Untereinander und überlappend in der Waagerechten: keine Reihe, jede behält links.
  mRects := TAtlasDefaultSizes.Layout([TAtlasSizeItem.Create(Bounds(8, 10, 75, 25), 88, -1, False, False),
    TAtlasSizeItem.Create(Bounds(8, 40, 75, 25), 88, -1, False, False),
    TAtlasSizeItem.Create(Bounds(40, 12, 75, 25), 88, -1, False, False)], 500);
  Assert.AreEqual(8, mRects[0].Left);
  Assert.AreEqual(8, mRects[1].Left);
  Assert.AreEqual(40, mRects[2].Left);
  Assert.AreEqual(128, mRects[2].Right);
end;

procedure TAtlasDefaultSizesTests.LearnMostFrequent;
var
  mEntries: TArray<TAtlasSizeEntry>;
begin
  mEntries := TAtlasDefaultSizes.Learn([TAtlasSizeSample.Create('TButton', 75, 25),
    TAtlasSizeSample.Create('TEdit', 121, 21), TAtlasSizeSample.Create('TButton', 88, 25),
    TAtlasSizeSample.Create('TButton', 88, 25), TAtlasSizeSample.Create('TEdit', 150, 21)]);
  Assert.AreEqual('TButton=88,25; TEdit=121,21', TAtlasDefaultSizes.ToText(mEntries));
end;

end.
