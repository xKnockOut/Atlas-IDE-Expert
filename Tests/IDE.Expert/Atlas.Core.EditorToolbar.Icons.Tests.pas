unit Atlas.Core.EditorToolbar.Icons.Tests;

// Atlas-Editorleiste (#1101): Symbole je Befehl und ihre Vektorformen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasToolbarIconsTests = class
  public
    [Test]
    procedure IconsOfKnownCommands;
    [Test]
    procedure GlyphsStayInTheBox;
    /// <summary>Das Zahnrad ist ein geschlossener Zahnkranz mit Loch, keine Strahlen (sah aus wie eine Sonne).
    /// </summary>
    [Test]
    procedure GearHasTeethNotRays;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.ToolbarItems,
  Atlas.Core.EditorToolbar.Icons,
  Atlas.Core.EditorToolbar.Glyphs;

procedure TAtlasToolbarIconsTests.IconsOfKnownCommands;
var
  Id: string;
begin
  Assert.IsTrue(TAtlasToolbarIcons.IconOf(TAtlasToolbarItems.GotoInterface) = TAtlasToolbarIcon.InterfacePart);
  Assert.IsTrue(TAtlasToolbarIcons.IconOf('Atlas.ProblemsWindow') = TAtlasToolbarIcon.Problems);
  Assert.IsTrue(TAtlasToolbarIcons.IconOf('atlas.navback') = TAtlasToolbarIcon.Back, 'ohne Groß-/Kleinschreibung');
  Assert.IsTrue(TAtlasToolbarIcons.IconOf('Atlas.Rename') = TAtlasToolbarIcon.Letter, 'unbekannt');
  // Jeder Knopf der Vorgabe hat ein eigenes Symbol.
  for Id in TAtlasToolbarItems.Default do
    if not TAtlasToolbarItems.IsSeparator(Id) then
      Assert.IsFalse(TAtlasToolbarIcons.IconOf(Id) = TAtlasToolbarIcon.Letter, Id);
end;

procedure TAtlasToolbarIconsTests.GlyphsStayInTheBox;
var
  Icon: TAtlasToolbarIcon;
  Shapes: TArray<TAtlasGlyphShape>;
  Shape: TAtlasGlyphShape;
  Point: TAtlasGlyphPoint;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasGlyphs.Shapes(TAtlasToolbarIcon.Letter))));
  for Icon := Succ(Low(TAtlasToolbarIcon)) to High(TAtlasToolbarIcon) do
  begin
    Shapes := TAtlasGlyphs.Shapes(Icon);
    Assert.IsTrue(Length(Shapes) > 0, 'Symbol ' + IntToStr(Ord(Icon)));
    for Shape in Shapes do
    begin
      Assert.IsTrue(Length(Shape.Points) >= 2, 'mindestens eine Strecke');
      if Shape.Filled then
        Assert.IsTrue(Shape.Closed, 'Flächen sind geschlossen');
      for Point in Shape.Points do
      begin
        Assert.IsTrue((Point.X >= 0) and (Point.X <= TAtlasGlyphs.Size), 'X im Feld');
        Assert.IsTrue((Point.Y >= 0) and (Point.Y <= TAtlasGlyphs.Size), 'Y im Feld');
      end;
    end;
  end;
end;

procedure TAtlasToolbarIconsTests.GearHasTeethNotRays;
var
  Shapes: TArray<TAtlasGlyphShape>;
  Shape: TAtlasGlyphShape;
  Point: TAtlasGlyphPoint;
  Radius: Double;
  Outer, Inner: Integer;
begin
  Shapes := TAtlasGlyphs.Shapes(TAtlasToolbarIcon.Gear);
  Assert.AreEqual(2, Integer(Length(Shapes)), 'Zahnkranz und Loch');
  for Shape in Shapes do
    Assert.IsTrue(Shape.Closed, 'nur geschlossene Umrisse, keine Strahlen');
  Outer := 0;
  Inner := 0;
  for Point in Shapes[0].Points do
  begin
    Radius := Sqrt(Sqr(Point.X - 8) + Sqr(Point.Y - 8));
    if Abs(Radius - 6.8) < 0.01 then
      Inc(Outer)
    else if Abs(Radius - 5) < 0.01 then
      Inc(Inner)
    else
      Assert.Fail(Format('Punkt %.2f/%.2f weder Kopf noch Fuß', [Point.X, Point.Y]));
  end;
  Assert.AreEqual(16, Outer, 'acht Zähne mit je zwei Kopfpunkten');
  Assert.AreEqual(16, Inner, 'acht Lücken mit je zwei Fußpunkten');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasToolbarIconsTests);

end.
