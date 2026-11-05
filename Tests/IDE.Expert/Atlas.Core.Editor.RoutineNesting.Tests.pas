unit Atlas.Core.Editor.RoutineNesting.Tests;

// Tests für die Färbung lokaler Routinen (#1788): Arten, Farben, Bänder und Palette aus den Einstellungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasRoutineNestingTests = class
  public
    [Test]
    procedure StyleNamesRoundTripAndUnknownIsDeeper;
    [Test]
    procedure OuterKeepsTheDepth;
    [Test]
    procedure DeeperAddsTheNesting;
    [Test]
    procedure OwnColorOnlyInLocalRoutines;
    [Test]
    procedure BandsOnlyForLocalRoutineBodiesAndOnlyWithBand;
    [Test]
    procedure InnermostBandWinsPerLine;
    [Test]
    procedure PaletteTakesCustomColorsPerTheme;
    [Test]
    procedure ParseColorAcceptsOnlyOneHexColor;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Editor.Pairs,
  Atlas.Core.Editor.RoutineNesting;

const
  /// <summary>A mit lokaler Funktion B, darin lokale Prozedur C; Zeilen 0 bis 11.</summary>
  cNested = 'procedure A;'#10'  function B: Boolean;'#10'    procedure C;'#10'    begin'#10'    end;'#10 +
    '  begin'#10'    if X then'#10'    begin'#10'    end;'#10'  end;'#10'begin'#10'end;';

/// <summary>Farben als „#RRGGBB“ vergleichen: lesbare Meldung, keine Überladung für TAtlasColor nötig.</summary>
procedure SameColor(AExpected, AActual: TAtlasColor; const AMessage: string);
begin
  Assert.AreEqual(TAtlasColorMath.ToHex(AExpected), TAtlasColorMath.ToHex(AActual), AMessage);
end;

function Blocks(const AText: string): TArray<TAtlasPairBlock>;
begin
  TAtlasPairs.Analyze(AText, Result);
end;

procedure TAtlasRoutineNestingTests.StyleNamesRoundTripAndUnknownIsDeeper;
var
  mStyle: TAtlasNestedRoutineStyle;
begin
  for mStyle := Low(TAtlasNestedRoutineStyle) to High(TAtlasNestedRoutineStyle) do
  begin
    Assert.IsTrue(mStyle = TAtlasRoutineNesting.StyleOf(TAtlasRoutineNesting.StyleNames[mStyle]));
  end;
  Assert.IsTrue(TAtlasNestedRoutineStyle.OwnColor = TAtlasRoutineNesting.StyleOf(' COLOR '));
  Assert.IsTrue(TAtlasNestedRoutineStyle.Deeper = TAtlasRoutineNesting.StyleOf('irgendwas'));
  Assert.AreEqual('deeper', TAtlasRoutineNesting.NormalizeName(''));
  Assert.AreEqual('outer', TAtlasRoutineNesting.NormalizeName('Outer'));
end;

procedure TAtlasRoutineNestingTests.OuterKeepsTheDepth;
var
  mNesting: TAtlasRoutineNesting;
  mPalette: TAtlasColors;
begin
  mNesting := TAtlasRoutineNesting.Create('outer', False);
  mPalette := TAtlasColors.Dark;
  Assert.AreEqual(1, mNesting.Depth(1, 2));
  Assert.IsFalse(mNesting.OwnColor(2));
  SameColor(mPalette.Pairs[0], mNesting.Color(mPalette, 0, 1), 'wie die äußere Routine');
end;

procedure TAtlasRoutineNestingTests.DeeperAddsTheNesting;
var
  mNesting: TAtlasRoutineNesting;
  mPalette: TAtlasColors;
begin
  mNesting := TAtlasRoutineNesting.Create('deeper', False);
  mPalette := TAtlasColors.Light;
  Assert.AreEqual(0, mNesting.Depth(0, 0));
  Assert.AreEqual(3, mNesting.Depth(1, 2));
  SameColor(mPalette.Pairs[1], mNesting.Color(mPalette, 0, 1), 'lokale Routine eine Stufe tiefer');
  // Zyklisch wie die Paarfarben.
  SameColor(mPalette.Pairs[1], mNesting.Color(mPalette, 4, 2), '');
end;

procedure TAtlasRoutineNestingTests.OwnColorOnlyInLocalRoutines;
var
  mNesting: TAtlasRoutineNesting;
  mPalette: TAtlasColors;
begin
  mNesting := TAtlasRoutineNesting.Create('color', False);
  mPalette := TAtlasColors.Dark;
  Assert.IsFalse(mNesting.OwnColor(0));
  Assert.IsTrue(mNesting.OwnColor(1));
  SameColor(mPalette.Pairs[2], mNesting.Color(mPalette, 2, 0), 'äußere Routine: Paarfarbe');
  SameColor(mPalette.NestedRoutine, mNesting.Color(mPalette, 2, 1), 'lokale Routine: eigene Farbe');
  Assert.AreEqual(2, mNesting.Depth(2, 1), 'Tiefe bleibt');
end;

procedure TAtlasRoutineNestingTests.BandsOnlyForLocalRoutineBodiesAndOnlyWithBand;
var
  mBands: TArray<TAtlasRoutineBand>;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasRoutineNesting.Create('deeper', False).Bands(Blocks(cNested)))),
    'ohne Band keine Bänder');
  mBands := TAtlasRoutineNesting.Create('outer', True).Bands(Blocks(cNested));
  // C (Zeilen 2–4) und B (Zeilen 1–9); weder der if-Block noch A.
  Assert.AreEqual(2, Integer(Length(mBands)));
  Assert.AreEqual(2, mBands[0].FirstLine);
  Assert.AreEqual(4, mBands[0].LastLine);
  Assert.AreEqual(2, mBands[0].Routine);
  Assert.AreEqual(1, mBands[1].FirstLine, 'ab dem Kopf');
  Assert.AreEqual(9, mBands[1].LastLine);
  Assert.AreEqual(1, mBands[1].Routine);
end;

procedure TAtlasRoutineNestingTests.InnermostBandWinsPerLine;
var
  mBands: TArray<TAtlasRoutineBand>;
  mOf: TArray<Integer>;
begin
  mBands := TAtlasRoutineNesting.Create('outer', True).Bands(Blocks(cNested));
  mOf := TAtlasRoutineNesting.BandOfLines(mBands, 12);
  Assert.AreEqual(12, Integer(Length(mOf)));
  Assert.AreEqual(-1, mOf[0], 'äußere Routine ohne Band');
  Assert.AreEqual(1, mOf[1], 'Kopf von B');
  Assert.AreEqual(0, mOf[3], 'C liegt innen');
  Assert.AreEqual(1, mOf[5], 'Rumpf von B');
  Assert.AreEqual(-1, mOf[10]);
  Assert.AreEqual(0, Integer(Length(TAtlasRoutineNesting.BandOfLines(mBands, 0))));
end;

procedure TAtlasRoutineNestingTests.PaletteTakesCustomColorsPerTheme;
var
  mSettings: TAtlasPluginSettings;
  mPalette: TAtlasColors;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mPalette := TAtlasRoutineNesting.PairPalette(TAtlasColors.Dark, mSettings);
  SameColor(TAtlasColors.Dark.NestedRoutine, mPalette.NestedRoutine, 'leer = Palette');
  mSettings.NestedRoutineColorDark := '#123456';
  mSettings.NestedRoutineColorLight := '#654321';
  mSettings.PairColorsDark := '#000001,#000002,#000003,#000004,#000005';
  mPalette := TAtlasRoutineNesting.PairPalette(TAtlasColors.Dark, mSettings);
  SameColor(TAtlasColorMath.FromHex('#123456'), mPalette.NestedRoutine, '');
  SameColor(TAtlasColorMath.FromHex('#000002'), mPalette.Pairs[1], '');
  mPalette := TAtlasRoutineNesting.PairPalette(TAtlasColors.Light, mSettings);
  SameColor(TAtlasColorMath.FromHex('#654321'), mPalette.NestedRoutine, 'helles Thema');
  SameColor(TAtlasColors.Light.Pairs[1], mPalette.Pairs[1], '');
  mSettings.NestedRoutines := 'color';
  mSettings.NestedRoutineBand := True;
  Assert.IsTrue(TAtlasNestedRoutineStyle.OwnColor = TAtlasRoutineNesting.FromSettings(mSettings).Style);
  Assert.IsTrue(TAtlasRoutineNesting.FromSettings(mSettings).Band);
end;

procedure TAtlasRoutineNestingTests.ParseColorAcceptsOnlyOneHexColor;
var
  mColor: TAtlasColor;
begin
  Assert.IsTrue(TAtlasColors.ParseColor(' #A85A00 ', mColor));
  Assert.AreEqual('#A85A00', TAtlasColorMath.ToHex(mColor));
  Assert.IsFalse(TAtlasColors.ParseColor('', mColor));
  Assert.IsFalse(TAtlasColors.ParseColor('blau', mColor));
  Assert.IsFalse(TAtlasColors.ParseColor('#12345', mColor));
  Assert.IsFalse(TAtlasColors.ParseColor('#12345G', mColor));
  SameColor(TAtlasColors.Light.NestedRoutine, TAtlasColors.Light.WithNestedRoutine('kaputt').NestedRoutine, '');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasRoutineNestingTests);

end.
