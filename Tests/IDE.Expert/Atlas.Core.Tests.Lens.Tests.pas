unit Atlas.Core.Tests.Lens.Tests;

// Tests der Code Lens „Test ausführen“ (#69, #585) und der Marke „getestet von“
// (#1778) ohne IDE: Marken einer Testunit, Art und Beschriftung, Farbe nach dem
// Stand und Knopf unter der Maus.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasTestLensTests = class
  public
    [Test]
    procedure MarksForFixtureTestsAndCases;
    [Test]
    procedure SeriesStatusMixesToPartial;
    [Test]
    procedure CaptionSwitches;
    [Test]
    procedure ToneFollowsStatusWarnAndStale;
    [Test]
    procedure HitFindsButtonUnderPoint;
    [Test]
    procedure PillSizeAndRect;
  end;

implementation

uses
  System.Types,
  System.SysUtils,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Text.DUnitX,
  Atlas.Core.Tests.Run,
  Atlas.Core.Tests.Debug,
  Atlas.Core.Tests.Lens;

function Sample: TArray<string>;
begin
  Result := [
    'unit Rechner.Tests;',                                      // 0
    'interface',                                                // 1
    'uses DUnitX.TestFramework;',                               // 2
    'type',                                                     // 3
    '  [TestFixture]',                                          // 4
    '  TRechnerTests = class',                                  // 5
    '  public',                                                 // 6
    '    [Test]',                                               // 7
    '    procedure Addiert;',                                   // 8
    '    [TestCase(''Klein'', ''1,2,3'')]',                     // 9
    '    [TestCase(''Gross'', ''10,20,30'')]',                  // 10
    '    procedure Summe(A, B, C: Integer);',                   // 11
    '  end;',                                                   // 12
    'implementation',                                           // 13
    'procedure TRechnerTests.Addiert;',                         // 14
    'begin',                                                    // 15
    'end;',                                                     // 16
    'procedure TRechnerTests.Summe(A, B, C: Integer);',         // 17
    'begin',                                                    // 18
    'end;',                                                     // 19
    'end.'];                                                    // 20
end;

function Series(ARunning, APassed, AFailed: Boolean): TAtlasTestSeriesMark;
begin
  Result := Default(TAtlasTestSeriesMark);
  Result.Running := ARunning;
  Result.AnyPassed := APassed;
  Result.AnyFailed := AFailed;
end;

{ TAtlasTestLensTests }

procedure TAtlasTestLensTests.MarksForFixtureTestsAndCases;
var
  mMarks: TArray<TAtlasTestLensMark>;
begin
  mMarks := TAtlasTestLens.Marks(TDUnitXSource.Scan(Sample));
  // Fixture, Addiert, Summe (alle Fälle), Klein, Gross.
  Assert.AreEqual(5, Integer(Length(mMarks)));
  Assert.AreEqual<TAtlasTestLensKind>(TAtlasTestLensKind.Fixture,
    TAtlasTestLens.KindOf(mMarks[0].Selection));
  Assert.AreEqual(3, Integer(Length(mMarks[0].Expected)), 'die Fixture ergibt alle Tests');
  Assert.AreEqual<TAtlasTestLensKind>(TAtlasTestLensKind.Test,
    TAtlasTestLens.KindOf(mMarks[1].Selection));
  Assert.AreEqual('Addiert', mMarks[1].Selection.Method);
  Assert.AreEqual<TAtlasTestLensKind>(TAtlasTestLensKind.Test,
    TAtlasTestLens.KindOf(mMarks[2].Selection));
  Assert.AreEqual('Summe', mMarks[2].Selection.Method);
  Assert.AreEqual(2, TAtlasTestLens.CaseCount(mMarks[2].Selection, mMarks[2].Expected));
  Assert.AreEqual<TAtlasTestLensKind>(TAtlasTestLensKind.TestCase,
    TAtlasTestLens.KindOf(mMarks[3].Selection));
  Assert.AreEqual(9, mMarks[3].Line);
  Assert.AreEqual('Klein', mMarks[3].Selection.CaseName);
  Assert.AreEqual(0, TAtlasTestLens.CaseCount(mMarks[3].Selection, mMarks[3].Expected), 'ein Fall zählt nicht');
  Assert.AreEqual(10, mMarks[4].Line);
  Assert.AreEqual(1, Integer(Length(mMarks[4].Expected)));
  Assert.AreEqual(0, TAtlasTestLens.CaseCount(mMarks[0].Selection, mMarks[0].Expected), 'Fixture ohne Fälle');
end;

procedure TAtlasTestLensTests.SeriesStatusMixesToPartial;
begin
  Assert.AreEqual<TAtlasTestStatus>(TAtlasTestStatus.Unknown,
    TAtlasTestLens.SeriesStatus(Series(True, True, True)), 'läuft');
  Assert.AreEqual<TAtlasTestStatus>(TAtlasTestStatus.Partial,
    TAtlasTestLens.SeriesStatus(Series(False, True, True)), 'gemischt');
  Assert.AreEqual<TAtlasTestStatus>(TAtlasTestStatus.Failed,
    TAtlasTestLens.SeriesStatus(Series(False, False, True)));
  Assert.AreEqual<TAtlasTestStatus>(TAtlasTestStatus.Passed,
    TAtlasTestLens.SeriesStatus(Series(False, True, False)));
end;

procedure TAtlasTestLensTests.CaptionSwitches;
begin
  Assert.AreEqual(500, TAtlasTestLens.SlowLimit(TAtlasTestStatus.Passed, False, 500));
  Assert.AreEqual(0, TAtlasTestLens.SlowLimit(TAtlasTestStatus.Failed, False, 500), 'rot ist nie langsam');
  Assert.AreEqual(0, TAtlasTestLens.SlowLimit(TAtlasTestStatus.Passed, True, 500), 'veraltet ist nie langsam');
  Assert.IsTrue(TAtlasTestLens.ShowsLeak(1, TAtlasTestStatus.Passed));
  Assert.IsFalse(TAtlasTestLens.ShowsLeak(0, TAtlasTestStatus.Passed));
  Assert.IsFalse(TAtlasTestLens.ShowsLeak(2, TAtlasTestStatus.Failed));
  Assert.IsTrue(TAtlasTestLens.Comparable(TAtlasTestStatus.Failed, False));
  Assert.IsFalse(TAtlasTestLens.Comparable(TAtlasTestStatus.Failed, True));
  Assert.IsFalse(TAtlasTestLens.Comparable(TAtlasTestStatus.Passed, False));
end;

procedure TAtlasTestLensTests.ToneFollowsStatusWarnAndStale;
const
  cDefault = TAtlasColor(9);
var
  mColors: TAtlasColors;
begin
  mColors := Default(TAtlasColors);
  mColors.Error := 1;
  mColors.Add := 2;
  mColors.Warn := 3;
  mColors.Muted := 4;
  Assert.AreEqual(9, Integer(TAtlasTestLens.Tone(mColors, cDefault, TAtlasTestStatus.Unknown, False, False)));
  Assert.AreEqual(1, Integer(TAtlasTestLens.Tone(mColors, cDefault, TAtlasTestStatus.Failed, False, False)));
  Assert.AreEqual(2, Integer(TAtlasTestLens.Tone(mColors, cDefault, TAtlasTestStatus.Passed, False, False)));
  Assert.AreEqual(3, Integer(TAtlasTestLens.Tone(mColors, cDefault, TAtlasTestStatus.Partial, False, False)));
  Assert.AreEqual(3, Integer(TAtlasTestLens.Tone(mColors, cDefault, TAtlasTestStatus.Passed, True, False)),
    'langsam, Leck oder wackelt');
  Assert.AreEqual(4, Integer(TAtlasTestLens.Tone(mColors, cDefault, TAtlasTestStatus.Failed, True, True)),
    'veraltet gewinnt');
end;

procedure TAtlasTestLensTests.HitFindsButtonUnderPoint;
var
  mRects: TAtlasTestLensRects;
  mButton: TAtlasTestLensButton;
begin
  mRects := Default(TAtlasTestLensRects);
  mRects[TAtlasTestLensButton.Run] := TRect.Create(0, 0, 10, 10);
  mRects[TAtlasTestLensButton.Compare] := TRect.Create(20, 0, 30, 10);
  Assert.IsTrue(TAtlasTestLens.Hit(mRects, TPoint.Create(5, 5), mButton));
  Assert.AreEqual<TAtlasTestLensButton>(TAtlasTestLensButton.Run, mButton);
  Assert.IsTrue(TAtlasTestLens.Hit(mRects, TPoint.Create(25, 5), mButton));
  Assert.AreEqual<TAtlasTestLensButton>(TAtlasTestLensButton.Compare, mButton);
  Assert.IsFalse(TAtlasTestLens.Hit(mRects, TPoint.Create(15, 5), mButton), 'zwischen den Knöpfen');
end;

procedure TAtlasTestLensTests.PillSizeAndRect;
var
  mRect: TRect;
begin
  Assert.AreEqual(9, TAtlasTestLens.PillFontSize(10));
  Assert.AreEqual(TAtlasTestLens.cMinFontSize, TAtlasTestLens.PillFontSize(TAtlasTestLens.cMinFontSize));
  // Zeile 20 hoch, Text 10 hoch: 4 Punkte oben frei.
  mRect := TAtlasTestLens.PillRect(TRect.Create(0, 100, 500, 120), 40, 30, 10);
  Assert.AreEqual(40, mRect.Left);
  Assert.AreEqual(104, mRect.Top);
  Assert.AreEqual(80, mRect.Right);
  Assert.AreEqual(116, mRect.Bottom);
  // Zu niedrige Zeile: oben bündig.
  Assert.AreEqual(100, TAtlasTestLens.PillRect(TRect.Create(0, 100, 500, 105), 0, 1, 10).Top);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTestLensTests);

end.
