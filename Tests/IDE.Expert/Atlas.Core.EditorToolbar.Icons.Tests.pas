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
  Assert.AreEqual<TAtlasToolbarIcon>(TAtlasToolbarIcon.InterfacePart,
    TAtlasToolbarIcons.IconOf(TAtlasToolbarItems.cGotoInterface));
  Assert.AreEqual<TAtlasToolbarIcon>(TAtlasToolbarIcon.Problems, TAtlasToolbarIcons.IconOf('Atlas.ProblemsWindow'));
  Assert.AreEqual<TAtlasToolbarIcon>(TAtlasToolbarIcon.Back,
    TAtlasToolbarIcons.IconOf('atlas.navback'), 'ohne Groß-/Kleinschreibung');
  Assert.AreEqual<TAtlasToolbarIcon>(TAtlasToolbarIcon.Letter, TAtlasToolbarIcons.IconOf('Atlas.Rename'), 'unbekannt');
  // Jeder Knopf der Vorgabe hat ein eigenes Symbol.
  for Id in TAtlasToolbarItems.Default do
  begin
    if not TAtlasToolbarItems.IsSeparator(Id) then
    begin
      Assert.AreNotEqual<TAtlasToolbarIcon>(TAtlasToolbarIcon.Letter, TAtlasToolbarIcons.IconOf(Id), Id);
    end;
  end;
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
      begin
        Assert.IsTrue(Shape.Closed, 'Flächen sind geschlossen');
      end;
      for Point in Shape.Points do
      begin
        Assert.IsTrue((Point.X >= 0) and (Point.X <= TAtlasGlyphs.cSize), 'X im Feld');
        Assert.IsTrue((Point.Y >= 0) and (Point.Y <= TAtlasGlyphs.cSize), 'Y im Feld');
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
  begin
    Assert.IsTrue(Shape.Closed, 'nur geschlossene Umrisse, keine Strahlen');
  end;
  Outer := 0;
  Inner := 0;
  for Point in Shapes[0].Points do
  begin
    Radius := Sqrt(Sqr(Point.X - 8) + Sqr(Point.Y - 8));
    if Abs(Radius - 6.8) < 0.01 then
    begin
      Inc(Outer);
    end
    else if Abs(Radius - 5) < 0.01 then
    begin
      Inc(Inner);
    end
    else
    begin
      Assert.Fail(Format('Punkt %.2f/%.2f weder Kopf noch Fuß', [Point.X, Point.Y]));
    end;
  end;
  Assert.AreEqual(16, Outer, 'acht Zähne mit je zwei Kopfpunkten');
  Assert.AreEqual(16, Inner, 'acht Lücken mit je zwei Fußpunkten');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasToolbarIconsTests);

end.
