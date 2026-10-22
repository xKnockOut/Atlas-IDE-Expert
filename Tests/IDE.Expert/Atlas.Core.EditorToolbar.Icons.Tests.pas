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

initialization
  TDUnitX.RegisterTestFixture(TAtlasToolbarIconsTests);

end.
