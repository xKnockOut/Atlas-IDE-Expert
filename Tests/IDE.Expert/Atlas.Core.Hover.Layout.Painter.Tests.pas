unit Atlas.Core.Hover.Layout.Painter.Tests;

// Tests der Zeichenbausteine des Hover-Satzes: Klickflächen und Hervorhebung, neue Bausteine, Skalierung und
// gekürzter Text. Messwerte wie in Atlas.Core.Hover.Layout.TestSupport (Editorschrift 8 Pixel je Zeichen).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  THoverPainterTests = class
  public
    /// <summary>Ohne Klickfläche und Hervorhebung; mit Hervorhebung nur der Index unter der Maus.</summary>
    [Test]
    procedure HotSpots;
    /// <summary>MakeHot setzt Art, Index und Farbe der Hervorhebung am Baustein.</summary>
    [Test]
    procedure MakeHotMarksItem;
    /// <summary>Neuer Baustein ohne Hervorhebung, Stiftbreite 1.</summary>
    [Test]
    procedure NewItemDefaults;
    /// <summary>Skalierung wie MulDiv(Wert, PPI, 96), gerundet.</summary>
    [Test]
    procedure ScaleRounds;
    /// <summary>Text passt, wird mit „…“ gekürzt oder fällt ohne Platz weg.</summary>
    [Test]
    procedure ClippedShortensWithEllipsis;
  end;

implementation

uses
  System.Types,
  Atlas.Core.Style.Color,
  Atlas.Core.Hover.Items,
  Atlas.Core.Hover.Layout.Contract,
  Atlas.Core.Hover.Layout.Painter,
  Atlas.Core.Hover.Layout.TestSupport;

type
  /// <summary>Macht die geschützten Bausteine des Malers für die Tests erreichbar.</summary>
  TPainterProbe = class(TAtlasHoverPainter)
  public
    function ScaleOf(AValue: Integer): Integer;
    function ClippedMono(const AText: string; AMax: Integer): string;
    class function NoHotSpot: TAtlasHoverHotSpot; static;
    class function HoverHotSpot(AIndex: Integer; AColor: TAtlasColor): TAtlasHoverHotSpot; static;
    class procedure MarkHot(var AItem: TAtlasHoverItem; AIndex: Integer; AColor: TAtlasColor); static;
    class function Item(AColor: TAtlasColor): TAtlasHoverItem; static;
  end;

function TPainterProbe.ScaleOf(AValue: Integer): Integer;
begin
  Result := Scale(AValue);
end;

function TPainterProbe.ClippedMono(const AText: string; AMax: Integer): string;
begin
  Result := Clipped(TAtlasHoverFace.Create(TAtlasHoverFont.Mono, False, False), AText, AMax);
end;

class function TPainterProbe.NoHotSpot: TAtlasHoverHotSpot;
begin
  Result := NoHot;
end;

class function TPainterProbe.HoverHotSpot(AIndex: Integer; AColor: TAtlasColor): TAtlasHoverHotSpot;
begin
  Result := HoverHot(TAtlasHoverHitKind.Published, AIndex, AColor);
end;

class procedure TPainterProbe.MarkHot(var AItem: TAtlasHoverItem; AIndex: Integer; AColor: TAtlasColor);
begin
  MakeHot(AItem, TAtlasHoverHitKind.Published, AIndex, AColor);
end;

class function TPainterProbe.Item(AColor: TAtlasColor): TAtlasHoverItem;
begin
  Result := NewItem(TAtlasHoverItemKind.Frame, TRect.Create(1, 2, 3, 4), AColor);
end;

/// <summary>Maler für 96 bzw. 144 dpi mit der Messung der Tests.</summary>
function Probe(APPI: Integer): TPainterProbe;
var
  mInput: TAtlasHoverInput;
begin
  mInput := HoverTestInput(ActionsView, 300);
  mInput.PPI := APPI;
  Result := TPainterProbe.Create(mInput, TFakeMeasure.Create('x'));
end;

procedure THoverPainterTests.HotSpots;
var
  mHot: TAtlasHoverHotSpot;
begin
  mHot := TPainterProbe.NoHotSpot;
  Assert.AreEqual(-1, mHot.Index);
  Assert.AreEqual(-1, mHot.HotIndex);
  mHot := TPainterProbe.HoverHotSpot(3, 7);
  Assert.AreEqual(-1, mHot.Index, 'die Klickfläche legt der Aufrufer an');
  Assert.AreEqual(3, mHot.HotIndex);
  Assert.AreEqual(Ord(TAtlasHoverHitKind.Published), Ord(mHot.Kind));
  Assert.AreEqual(Integer(7), Integer(mHot.HotColor));
end;

procedure THoverPainterTests.MakeHotMarksItem;
var
  mItem: TAtlasHoverItem;
begin
  mItem := TPainterProbe.Item(5);
  TPainterProbe.MarkHot(mItem, 2, 9);
  Assert.AreEqual(Ord(TAtlasHoverHitKind.Published), Ord(mItem.HotKind));
  Assert.AreEqual(2, mItem.HotIndex);
  Assert.AreEqual(Integer(9), Integer(mItem.HotColor));
end;

procedure THoverPainterTests.NewItemDefaults;
var
  mItem: TAtlasHoverItem;
begin
  mItem := TPainterProbe.Item(5);
  Assert.AreEqual(Ord(TAtlasHoverItemKind.Frame), Ord(mItem.Kind));
  Assert.AreEqual(3, mItem.Rect.Right);
  Assert.AreEqual(Integer(5), Integer(mItem.Color));
  Assert.AreEqual(Integer(5), Integer(mItem.HotColor));
  Assert.AreEqual(1, mItem.PenWidth);
  Assert.AreEqual(-1, mItem.HotIndex);
end;

procedure THoverPainterTests.ScaleRounds;
var
  mProbe: TPainterProbe;
begin
  mProbe := Probe(96);
  try
    Assert.AreEqual(7, mProbe.ScaleOf(7));
  finally
    mProbe.Free;
  end;
  mProbe := Probe(144);
  try
    Assert.AreEqual(11, mProbe.ScaleOf(7), '10,5 aufgerundet');
    Assert.AreEqual(12, mProbe.ScaleOf(8));
  finally
    mProbe.Free;
  end;
end;

procedure THoverPainterTests.ClippedShortensWithEllipsis;
var
  mProbe: TPainterProbe;
begin
  mProbe := Probe(96);
  try
    Assert.AreEqual('abcd', mProbe.ClippedMono('abcd', 32));
    Assert.AreEqual('ab…', mProbe.ClippedMono('abcd', 24));
    Assert.AreEqual('', mProbe.ClippedMono('abcd', 4));
  finally
    mProbe.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(THoverPainterTests);

end.
