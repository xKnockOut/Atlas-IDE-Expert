unit Atlas.Core.Hover.Painter.Tests;

// Tests für die Grundformen des Hover-Satzes (Atlas.Core.Hover.Painter) und den
// Einstieg der published-Mitglieder (Atlas.Core.Hover.PublishedPainter). Messwerte:
// je Zeichen 7 Pixel, Zeilenhöhe 15, 96 dpi.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  THoverPainterTests = class
  public
    [Test]
    procedure NoHotHasNeitherHitNorHighlight;
    [Test]
    procedure HotSpotKeepsKindIndexAndColor;
    [Test]
    procedure MakeHotMarksItem;
    [Test]
    procedure FlowWrapsAtRightEdge;
    [Test]
    procedure FlowLinkAddsHit;
    [Test]
    procedure BlockIsLimitedToMaxLines;
    [Test]
    procedure ScaleRoundsToPixels;
    [Test]
    procedure WithoutMembersNothingIsPainted;
  end;

implementation

uses
  System.Types,
  Atlas.Core.Hover.Items,
  Atlas.Core.Hover.View,
  Atlas.Core.Hover.Painter,
  Atlas.Core.Hover.PublishedPainter;

type
  TFixedMeasure = class(TInterfacedObject, IAtlasHoverMeasure)
  public
    function TextWidth(const AFace: TAtlasHoverFace; const AText: string): Integer;
    function TextHeight(const AFace: TAtlasHoverFace): Integer;
    function BlockHeight(const AText: string; AWidth: Integer): Integer;
    function DeclarationWidth(AFrom, ATill: Integer): Integer;
    function DeclarationLines(AWidth, AIndent: Integer): TArray<TPoint>;
  end;

  /// <summary>Macht die geschützten Grundformen für die Tests zugänglich.</summary>
  TTestPainter = class(TAtlasHoverPublishedPainter)
  public
    procedure Start(ALeft, ARight: Integer);
    procedure Text(const AText: string);
    procedure Link(const AText: string; ACode: Integer);
    procedure Lines(const AText: string; AMaxLines: Integer);
    procedure Members;
    function ScaleOf(AValue: Integer): Integer;
    function ItemCount: Integer;
    function HitCount: Integer;
    function Item(AIndex: Integer): TAtlasHoverItem;
    function Hit(AIndex: Integer): TAtlasHoverHit;
    function Y: Integer;
    function MembersScroll: TAtlasHoverScroll;
  end;

function TFixedMeasure.TextWidth(const AFace: TAtlasHoverFace; const AText: string): Integer;
begin
  Result := 7 * Length(AText);
end;

function TFixedMeasure.TextHeight(const AFace: TAtlasHoverFace): Integer;
begin
  Result := 15;
end;

function TFixedMeasure.BlockHeight(const AText: string; AWidth: Integer): Integer;
begin
  // Jede angefangene Breite eine Zeile.
  Result := 15 * ((7 * Length(AText) + AWidth - 1) div AWidth);
end;

function TFixedMeasure.DeclarationWidth(AFrom, ATill: Integer): Integer;
begin
  Result := 8 * (ATill - AFrom);
end;

function TFixedMeasure.DeclarationLines(AWidth, AIndent: Integer): TArray<TPoint>;
begin
  Result := nil;
end;

procedure TTestPainter.Start(ALeft, ARight: Integer);
begin
  FLeft := ALeft;
  FRight := ARight;
  FX := ALeft;
  FY := 0;
end;

procedure TTestPainter.Text(const AText: string);
begin
  Flow(AText, 1, False);
end;

procedure TTestPainter.Link(const AText: string; ACode: Integer);
begin
  FlowLink(AText, 2, TAtlasHoverHitKind.DebugFix, ACode);
end;

procedure TTestPainter.Lines(const AText: string; AMaxLines: Integer);
begin
  Block(AText, 3, AMaxLines);
end;

procedure TTestPainter.Members;
begin
  PublishedMembers;
end;

function TTestPainter.ScaleOf(AValue: Integer): Integer;
begin
  Result := Scale(AValue);
end;

function TTestPainter.ItemCount: Integer;
begin
  Result := FItemCount;
end;

function TTestPainter.HitCount: Integer;
begin
  Result := FHitCount;
end;

function TTestPainter.Item(AIndex: Integer): TAtlasHoverItem;
begin
  Result := FItems[AIndex];
end;

function TTestPainter.Hit(AIndex: Integer): TAtlasHoverHit;
begin
  Result := FHits[AIndex];
end;

function TTestPainter.Y: Integer;
begin
  Result := FY;
end;

function TTestPainter.MembersScroll: TAtlasHoverScroll;
begin
  Result := FMembers;
end;

function NewPainter(APPI: Integer): TTestPainter;
var
  mInput: TAtlasHoverInput;
  mMeasure: IAtlasHoverMeasure;
begin
  mInput := Default(TAtlasHoverInput);
  mInput.View := Default(TAtlasHoverView);
  mInput.Width := 200;
  mInput.PPI := APPI;
  mMeasure := TFixedMeasure.Create;
  Result := TTestPainter.Create(mInput, mMeasure);
end;

{ THoverPainterTests }

procedure THoverPainterTests.NoHotHasNeitherHitNorHighlight;
var
  mHot: TAtlasHoverHotSpot;
begin
  mHot := HoverNoHot;
  Assert.AreEqual(-1, mHot.Index);
  Assert.AreEqual(-1, mHot.HotIndex);
end;

procedure THoverPainterTests.HotSpotKeepsKindIndexAndColor;
var
  mHot: TAtlasHoverHotSpot;
begin
  mHot := HoverHot(TAtlasHoverHitKind.Path, 4, 77);
  Assert.IsTrue(mHot.Kind = TAtlasHoverHitKind.Path);
  Assert.AreEqual(4, mHot.HotIndex);
  Assert.AreEqual(-1, mHot.Index, 'keine eigene Klickfläche');
  Assert.AreEqual(Int64(77), Int64(mHot.HotColor));
end;

procedure THoverPainterTests.MakeHotMarksItem;
var
  mItem: TAtlasHoverItem;
begin
  mItem := Default(TAtlasHoverItem);
  HoverMakeHot(mItem, TAtlasHoverHitKind.Back, 2, 9);
  Assert.IsTrue(mItem.HotKind = TAtlasHoverHitKind.Back);
  Assert.AreEqual(2, mItem.HotIndex);
  Assert.AreEqual(Int64(9), Int64(mItem.HotColor));
end;

procedure THoverPainterTests.FlowWrapsAtRightEdge;
var
  mPainter: TTestPainter;
begin
  mPainter := NewPainter(96);
  try
    mPainter.Start(10, 100);
    // 70 Pixel passen, die nächsten 70 nicht mehr: neue Zeile am linken Rand, 15 + 4 tiefer.
    mPainter.Text('abcdefghij');
    mPainter.Text('klmnopqrst');
    Assert.AreEqual(2, mPainter.ItemCount);
    Assert.AreEqual(10, mPainter.Item(0).Rect.Left);
    Assert.AreEqual(0, mPainter.Item(0).Rect.Top);
    Assert.AreEqual(10, mPainter.Item(1).Rect.Left);
    Assert.AreEqual(19, mPainter.Item(1).Rect.Top);
    Assert.AreEqual(0, mPainter.HitCount);
  finally
    mPainter.Free;
  end;
end;

procedure THoverPainterTests.FlowLinkAddsHit;
var
  mPainter: TTestPainter;
begin
  mPainter := NewPainter(96);
  try
    mPainter.Start(0, 300);
    mPainter.Link('Anheften', 5);
    Assert.AreEqual(1, mPainter.HitCount);
    Assert.IsTrue(mPainter.Hit(0).Kind = TAtlasHoverHitKind.DebugFix);
    Assert.AreEqual(5, mPainter.Hit(0).Index);
    Assert.AreEqual(56, mPainter.Hit(0).Rect.Width);
    Assert.IsTrue(mPainter.Item(0).HotUnderline);
  finally
    mPainter.Free;
  end;
end;

procedure THoverPainterTests.BlockIsLimitedToMaxLines;
var
  mPainter: TTestPainter;
begin
  mPainter := NewPainter(96);
  try
    mPainter.Start(0, 70);
    // 40 Zeichen = 280 Pixel = vier Zeilen auf 70 Pixel; höchstens zwei, dann 6 Pixel Abstand.
    mPainter.Lines('0123456789012345678901234567890123456789', 2);
    Assert.AreEqual(30, mPainter.Item(0).Rect.Height);
    Assert.AreEqual(36, mPainter.Y);
  finally
    mPainter.Free;
  end;
end;

procedure THoverPainterTests.ScaleRoundsToPixels;
var
  mPainter: TTestPainter;
begin
  mPainter := NewPainter(144);
  try
    Assert.AreEqual(15, mPainter.ScaleOf(10));
    Assert.AreEqual(2, mPainter.ScaleOf(1));
  finally
    mPainter.Free;
  end;
end;

procedure THoverPainterTests.WithoutMembersNothingIsPainted;
var
  mPainter: TTestPainter;
begin
  mPainter := NewPainter(96);
  try
    mPainter.Start(0, 200);
    mPainter.Members;
    Assert.AreEqual(0, mPainter.ItemCount);
    Assert.IsFalse(mPainter.MembersScroll.Scrollable);
  finally
    mPainter.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(THoverPainterTests);

end.
