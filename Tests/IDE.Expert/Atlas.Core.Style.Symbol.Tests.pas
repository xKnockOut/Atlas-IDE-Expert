unit Atlas.Core.Style.Symbol.Tests;

// Tests der Auswahl des Atlas-Symbols (#751): Bildgröße je Pixeldichte und
// Variante je Thema bzw. Hintergrund, Ressourcennamen.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Symbol;

type
  [TestFixture]
  TAtlasSymbolTests = class
  public
    [Test]
    procedure SizesAscendFrom16To256;
    [Test]
    procedure MenuSizeFollowsScaling;
    [Test]
    procedure HeaderAndAboutSizesFollowScaling;
    [Test]
    procedure OddScalingTakesNextLargerSize;
    [Test]
    procedure BeyondLargestTakesLargest;
    [Test]
    procedure MissingDpiCountsAs100Percent;
    [Test]
    procedure DarkThemeTakesDarkVariant;
    [Test]
    procedure BackgroundDecidesVariant;
    [Test]
    procedure ResourceNamesMatchResourceFile;
  end;

implementation

{ TAtlasSymbolTests }

procedure TAtlasSymbolTests.SizesAscendFrom16To256;
var
  Index: Integer;
begin
  Assert.AreEqual(16, TAtlasSymbol.Size(0));
  Assert.AreEqual(256, TAtlasSymbol.Size(TAtlasSymbol.SizeCount - 1));
  for Index := 1 to TAtlasSymbol.SizeCount - 1 do
    Assert.IsTrue(TAtlasSymbol.Size(Index) > TAtlasSymbol.Size(Index - 1));
end;

procedure TAtlasSymbolTests.MenuSizeFollowsScaling;
begin
  // 100, 125, 150, 175, 200 % für 16 px: jede Stufe hat ihre eigene Datei.
  Assert.AreEqual(16, TAtlasSymbol.SizeFor(TAtlasSymbol.MenuSize, 96));
  Assert.AreEqual(20, TAtlasSymbol.SizeFor(TAtlasSymbol.MenuSize, 120));
  Assert.AreEqual(24, TAtlasSymbol.SizeFor(TAtlasSymbol.MenuSize, 144));
  Assert.AreEqual(32, TAtlasSymbol.SizeFor(TAtlasSymbol.MenuSize, 168));
  Assert.AreEqual(32, TAtlasSymbol.SizeFor(TAtlasSymbol.MenuSize, 192));
  Assert.AreEqual(28, TAtlasSymbol.PixelSize(TAtlasSymbol.MenuSize, 168));
end;

procedure TAtlasSymbolTests.HeaderAndAboutSizesFollowScaling;
begin
  Assert.AreEqual(32, TAtlasSymbol.SizeFor(TAtlasSymbol.HeaderSize, 96));
  Assert.AreEqual(48, TAtlasSymbol.SizeFor(TAtlasSymbol.HeaderSize, 144));
  Assert.AreEqual(64, TAtlasSymbol.SizeFor(TAtlasSymbol.HeaderSize, 192));
  Assert.AreEqual(48, TAtlasSymbol.SizeFor(TAtlasSymbol.AboutSize, 96));
  Assert.AreEqual(128, TAtlasSymbol.SizeFor(TAtlasSymbol.AboutSize, 144));
  Assert.AreEqual(24, TAtlasSymbol.SizeFor(TAtlasSymbol.SplashSize, 96));
  Assert.AreEqual(48, TAtlasSymbol.SizeFor(TAtlasSymbol.SplashSize, 192));
end;

procedure TAtlasSymbolTests.OddScalingTakesNextLargerSize;
begin
  // 110 %: 16 px werden 18 px, die nächste Datei hat 20 px und wird verkleinert.
  Assert.AreEqual(18, TAtlasSymbol.PixelSize(16, 106));
  Assert.AreEqual(20, TAtlasSymbol.SizeFor(16, 106));
end;

procedure TAtlasSymbolTests.BeyondLargestTakesLargest;
begin
  Assert.AreEqual(256, TAtlasSymbol.SizeFor(256, 192));
end;

procedure TAtlasSymbolTests.MissingDpiCountsAs100Percent;
begin
  Assert.AreEqual(16, TAtlasSymbol.SizeFor(16, 0));
end;

procedure TAtlasSymbolTests.DarkThemeTakesDarkVariant;
begin
  Assert.IsTrue(TAtlasSymbol.VariantFor(True) = TAtlasSymbolVariant.Dark);
  Assert.IsTrue(TAtlasSymbol.VariantFor(False) = TAtlasSymbolVariant.Light);
end;

procedure TAtlasSymbolTests.BackgroundDecidesVariant;
begin
  // Hintergründe der IDE-Themen: Dunkel ($1E1E1E), Mountain Mist (hell), Weiß.
  Assert.IsTrue(TAtlasSymbol.VariantFor(TAtlasColor($1E1E1E)) = TAtlasSymbolVariant.Dark);
  Assert.IsTrue(TAtlasSymbol.VariantFor(TAtlasColor($F0F0F0)) = TAtlasSymbolVariant.Light);
  Assert.IsTrue(TAtlasSymbol.VariantFor(TAtlasColor($FFFFFF)) = TAtlasSymbolVariant.Light);
end;

procedure TAtlasSymbolTests.ResourceNamesMatchResourceFile;
begin
  // Namen wie in Resources\Symbol\Quellen\Erzeuge-Res.py.
  Assert.AreEqual('ATLAS_HELL_16', TAtlasSymbol.ResourceName(TAtlasSymbolVariant.Light, 16));
  Assert.AreEqual('ATLAS_DUNKEL_256', TAtlasSymbol.ResourceName(TAtlasSymbolVariant.Dark, 256));
  Assert.AreEqual('ATLAS_ICON_HELL', TAtlasSymbol.IconName(TAtlasSymbolVariant.Light));
  Assert.AreEqual('ATLAS_ICON_DUNKEL', TAtlasSymbol.IconName(TAtlasSymbolVariant.Dark));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSymbolTests);

end.
