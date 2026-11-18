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
    /// <summary>Das Auge folgt dem Pfad des Mockups: Je Bogen acht Strecken, die Bögen beginnen links, oben, rechts
    /// und unten.</summary>
    [Test]
    procedure EyeFollowsTheMockup;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.ToolbarItems,
  Atlas.Core.EditorToolbar.Icons,
  Atlas.Core.EditorToolbar.Glyphs;

{ TAtlasToolbarIconsTests }

procedure TAtlasToolbarIconsTests.IconsOfKnownCommands;
var
  mId: string;
begin
  Assert.AreEqual<TAtlasToolbarIcon>(TAtlasToolbarIcon.InterfacePart,
    TAtlasToolbarIcons.IconOf(TAtlasToolbarItems.cGotoInterface));
  Assert.AreEqual<TAtlasToolbarIcon>(TAtlasToolbarIcon.Problems, TAtlasToolbarIcons.IconOf('Atlas.ProblemsWindow'));
  Assert.AreEqual<TAtlasToolbarIcon>(TAtlasToolbarIcon.Back,
    TAtlasToolbarIcons.IconOf('atlas.navback'), 'ohne Groß-/Kleinschreibung');
  Assert.AreEqual<TAtlasToolbarIcon>(TAtlasToolbarIcon.Letter, TAtlasToolbarIcons.IconOf('Atlas.Rename'), 'unbekannt');
  // Jeder Knopf der Vorgabe hat ein eigenes Symbol.
  for mId in TAtlasToolbarItems.Default do
  begin
    if not TAtlasToolbarItems.IsSeparator(mId) then
    begin
      Assert.AreNotEqual<TAtlasToolbarIcon>(TAtlasToolbarIcon.Letter, TAtlasToolbarIcons.IconOf(mId), mId);
    end;
  end;
end;

procedure TAtlasToolbarIconsTests.GlyphsStayInTheBox;
var
  mIcon: TAtlasToolbarIcon;
  mShapes: TArray<TAtlasGlyphShape>;
  mShape: TAtlasGlyphShape;
  mPoint: TAtlasGlyphPoint;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasGlyphs.Shapes(TAtlasToolbarIcon.Letter))));
  for mIcon := Succ(Low(TAtlasToolbarIcon)) to High(TAtlasToolbarIcon) do
  begin
    mShapes := TAtlasGlyphs.Shapes(mIcon);
    Assert.IsTrue(Length(mShapes) > 0, 'Symbol ' + IntToStr(Ord(mIcon)));
    for mShape in mShapes do
    begin
      Assert.IsTrue(Length(mShape.Points) >= 2, 'mindestens eine Strecke');
      if mShape.Filled then
      begin
        Assert.IsTrue(mShape.Closed, 'Flächen sind geschlossen');
      end;
      for mPoint in mShape.Points do
      begin
        Assert.IsTrue((mPoint.X >= 0) and (mPoint.X <= TAtlasGlyphs.cSize), 'X im Feld');
        Assert.IsTrue((mPoint.Y >= 0) and (mPoint.Y <= TAtlasGlyphs.cSize), 'Y im Feld');
      end;
    end;
  end;
end;

procedure TAtlasToolbarIconsTests.GearHasTeethNotRays;
var
  mShapes: TArray<TAtlasGlyphShape>;
  mShape: TAtlasGlyphShape;
  mPoint: TAtlasGlyphPoint;
  mRadius: Double;
  mOuter, mInner: Integer;
begin
  mShapes := TAtlasGlyphs.Shapes(TAtlasToolbarIcon.Gear);
  Assert.AreEqual(2, Integer(Length(mShapes)), 'Zahnkranz und Loch');
  for mShape in mShapes do
  begin
    Assert.IsTrue(mShape.Closed, 'nur geschlossene Umrisse, keine Strahlen');
  end;
  mOuter := 0;
  mInner := 0;
  for mPoint in mShapes[0].Points do
  begin
    mRadius := Sqrt(Sqr(mPoint.X - 8) + Sqr(mPoint.Y - 8));
    if Abs(mRadius - 6.8) < 0.01 then
    begin
      Inc(mOuter);
    end
    else if Abs(mRadius - 5) < 0.01 then
    begin
      Inc(mInner);
    end
    else
    begin
      Assert.Fail(Format('Punkt %.2f/%.2f weder Kopf noch Fuß', [mPoint.X, mPoint.Y]));
    end;
  end;
  Assert.AreEqual(16, mOuter, 'acht Zähne mit je zwei Kopfpunkten');
  Assert.AreEqual(16, mInner, 'acht Lücken mit je zwei Fußpunkten');
end;

procedure TAtlasToolbarIconsTests.EyeFollowsTheMockup;
const
  cDelta = 0.001;
var
  mEye: TAtlasGlyphShape;

  procedure AssertPoint(AIndex: Integer; AX, AY: Double);
  begin
    Assert.AreEqual(AX, Double(mEye.Points[AIndex].X), cDelta, Format('X von Punkt %d', [AIndex]));
    Assert.AreEqual(AY, Double(mEye.Points[AIndex].Y), cDelta, Format('Y von Punkt %d', [AIndex]));
  end;

begin
  mEye := TAtlasGlyphs.Shapes(TAtlasToolbarIcon.NonVisual)[0];
  Assert.IsTrue(mEye.Closed and not mEye.Filled, 'Umriss');
  Assert.AreEqual(32, Integer(Length(mEye.Points)), 'vier Bögen mit je acht Strecken');
  AssertPoint(0, 1.5, 8);
  AssertPoint(8, 8, 3.5);
  AssertPoint(16, 14.5, 8);
  AssertPoint(24, 8, 12.5);
  // Mitte des oberen linken Bogens: (1.5 + 3 * 1.5 + 3 * 3.9 + 8) / 8 und (8 + 3 * 8 + 3 * 3.5 + 3.5) / 8.
  AssertPoint(4, 3.2125, 5.75);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasToolbarIconsTests);

end.
