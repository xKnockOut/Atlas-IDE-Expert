unit Atlas.Core.Style.Symbol.Tests;

// Tests der Auswahl des Atlas-Symbols (#751): Bildgröße je Pixeldichte und
// Variante je Thema bzw. Hintergrund, Ressourcennamen.

interface

uses
  DUnitX.TestFramework,
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

uses
  Atlas.Core.Style.Color;

{ TAtlasSymbolTests }

procedure TAtlasSymbolTests.SizesAscendFrom16To256;
var
  Index: Integer;
begin
  Assert.AreEqual(16, TAtlasSymbol.Size(0));
  Assert.AreEqual(256, TAtlasSymbol.Size(TAtlasSymbol.cSizeCount - 1));
  for Index := 1 to TAtlasSymbol.cSizeCount - 1 do
  begin
    Assert.IsTrue(TAtlasSymbol.Size(Index) > TAtlasSymbol.Size(Index - 1));
  end;
end;

procedure TAtlasSymbolTests.MenuSizeFollowsScaling;
begin
  // 100, 125, 150, 175, 200 % für 16 px: jede Stufe hat ihre eigene Datei.
  Assert.AreEqual(16, TAtlasSymbol.SizeFor(TAtlasSymbol.cMenuSize, 96));
  Assert.AreEqual(20, TAtlasSymbol.SizeFor(TAtlasSymbol.cMenuSize, 120));
  Assert.AreEqual(24, TAtlasSymbol.SizeFor(TAtlasSymbol.cMenuSize, 144));
  Assert.AreEqual(32, TAtlasSymbol.SizeFor(TAtlasSymbol.cMenuSize, 168));
  Assert.AreEqual(32, TAtlasSymbol.SizeFor(TAtlasSymbol.cMenuSize, 192));
  Assert.AreEqual(28, TAtlasSymbol.PixelSize(TAtlasSymbol.cMenuSize, 168));
end;

procedure TAtlasSymbolTests.HeaderAndAboutSizesFollowScaling;
begin
  Assert.AreEqual(32, TAtlasSymbol.SizeFor(TAtlasSymbol.cHeaderSize, 96));
  Assert.AreEqual(48, TAtlasSymbol.SizeFor(TAtlasSymbol.cHeaderSize, 144));
  Assert.AreEqual(64, TAtlasSymbol.SizeFor(TAtlasSymbol.cHeaderSize, 192));
  Assert.AreEqual(48, TAtlasSymbol.SizeFor(TAtlasSymbol.cAboutSize, 96));
  Assert.AreEqual(128, TAtlasSymbol.SizeFor(TAtlasSymbol.cAboutSize, 144));
  Assert.AreEqual(24, TAtlasSymbol.SizeFor(TAtlasSymbol.cSplashSize, 96));
  Assert.AreEqual(48, TAtlasSymbol.SizeFor(TAtlasSymbol.cSplashSize, 192));
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
  Assert.AreEqual<TAtlasSymbolVariant>(TAtlasSymbolVariant.Dark, TAtlasSymbol.VariantFor(True));
  Assert.AreEqual<TAtlasSymbolVariant>(TAtlasSymbolVariant.Light, TAtlasSymbol.VariantFor(False));
end;

procedure TAtlasSymbolTests.BackgroundDecidesVariant;
begin
  // Hintergründe der IDE-Themen: Dunkel ($1E1E1E), Mountain Mist (hell), Weiß.
  Assert.AreEqual<TAtlasSymbolVariant>(TAtlasSymbolVariant.Dark, TAtlasSymbol.VariantFor(TAtlasColor($1E1E1E)));
  Assert.AreEqual<TAtlasSymbolVariant>(TAtlasSymbolVariant.Light, TAtlasSymbol.VariantFor(TAtlasColor($F0F0F0)));
  Assert.AreEqual<TAtlasSymbolVariant>(TAtlasSymbolVariant.Light, TAtlasSymbol.VariantFor(TAtlasColor($FFFFFF)));
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
