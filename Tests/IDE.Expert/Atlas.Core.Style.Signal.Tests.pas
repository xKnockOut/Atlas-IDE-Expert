unit Atlas.Core.Style.Signal.Tests;

// Signalfarben je Design (#1255): Kontrast zu den Flächen der Leisten, Zeichen
// und Plaketten lesbar, Ok/Warnung/Fehler deutlich verschieden, Zuordnung der
// Statuszustände und Palette.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSignalTests = class
  public
    [Test]
    procedure LightRingsStandOutOnBars;
    [Test]
    procedure DarkFillsStandOutOnBars;
    [Test]
    procedure MarksReadableOnFill;
    [Test]
    procedure BadgeTextReadable;
    [Test]
    procedure OkWarnErrorDistinct;
    [Test]
    procedure StatusStatesMapToSignals;
    [Test]
    procedure PaletteFollowsSurface;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Style.Signal,
  Atlas.Core.Status.Contract;

const
  // Flächen der Leisten: clBtnFace hell und dunkel, Fensterfläche, Abgesetztes.
  LightBars: array[0..2] of string = ('#F0F0F0', '#FFFFFF', '#F3F5F8');
  DarkBars: array[0..3] of string = ('#2B2B2B', '#1E1E1E', '#15181D', '#1A1E25');

function Name(AKind: TAtlasSignalKind): string;
begin
  Result := IntToStr(Ord(AKind));
end;

procedure TAtlasSignalTests.LightRingsStandOutOnBars;
var
  mSignals: TAtlasSignals;
  mKind: TAtlasSignalKind;
  mBar: string;
begin
  mSignals := TAtlasSignals.Light;
  for mKind := Low(TAtlasSignalKind) to High(TAtlasSignalKind) do
    for mBar in LightBars do
      Assert.IsTrue(TAtlasColorMath.Contrast(mSignals.Get(mKind).Ring, TAtlasColorMath.FromHex(mBar)) >= 4.0,
        Name(mKind) + ' auf ' + mBar);
end;

procedure TAtlasSignalTests.DarkFillsStandOutOnBars;
var
  mSignals: TAtlasSignals;
  mKind: TAtlasSignalKind;
  mBar: string;
begin
  mSignals := TAtlasSignals.Dark;
  for mKind := Low(TAtlasSignalKind) to High(TAtlasSignalKind) do
    for mBar in DarkBars do
      Assert.IsTrue(TAtlasColorMath.Contrast(mSignals.Get(mKind).Fill, TAtlasColorMath.FromHex(mBar)) >= 4.0,
        Name(mKind) + ' auf ' + mBar);
end;

procedure TAtlasSignalTests.MarksReadableOnFill;
const
  Kinds: array[0..2] of TAtlasSignalKind = (TAtlasSignalKind.Error, TAtlasSignalKind.Warn, TAtlasSignalKind.Info);
var
  mKind: TAtlasSignalKind;
begin
  // Kreuz, Ausrufezeichen und „i“ der Befundsymbole; vorher Weiß bzw. Schwarz fest.
  for mKind in Kinds do
  begin
    Assert.IsTrue(TAtlasColorMath.Contrast(TAtlasSignals.Light.Get(mKind).Mark,
      TAtlasSignals.Light.Get(mKind).Fill) >= 3.5, 'hell ' + Name(mKind));
    Assert.IsTrue(TAtlasColorMath.Contrast(TAtlasSignals.Dark.Get(mKind).Mark,
      TAtlasSignals.Dark.Get(mKind).Fill) >= 3.5, 'dunkel ' + Name(mKind));
  end;
end;

procedure TAtlasSignalTests.BadgeTextReadable;
var
  mKind: TAtlasSignalKind;
begin
  for mKind := Low(TAtlasSignalKind) to High(TAtlasSignalKind) do
  begin
    Assert.IsTrue(TAtlasColorMath.Contrast(TAtlasSignals.Light.Get(mKind).OnSolid,
      TAtlasSignals.Light.Get(mKind).Solid) >= 4.5, 'hell ' + Name(mKind));
    Assert.IsTrue(TAtlasColorMath.Contrast(TAtlasSignals.Dark.Get(mKind).OnSolid,
      TAtlasSignals.Dark.Get(mKind).Solid) >= 4.5, 'dunkel ' + Name(mKind));
  end;
end;

procedure TAtlasSignalTests.OkWarnErrorDistinct;
const
  Kinds: array[0..2] of TAtlasSignalKind = (TAtlasSignalKind.Ok, TAtlasSignalKind.Warn, TAtlasSignalKind.Error);
var
  mLeft, mRight: Integer;
begin
  // Der eigentliche Fehler (#1255): Die Punkte waren im hellen Design kaum zu unterscheiden.
  for mLeft := 0 to High(Kinds) do
    for mRight := mLeft + 1 to High(Kinds) do
    begin
      Assert.IsTrue(TAtlasColorMath.DeltaE2000(TAtlasSignals.Light.Get(Kinds[mLeft]).Fill,
        TAtlasSignals.Light.Get(Kinds[mRight]).Fill) >= 20, 'hell');
      Assert.IsTrue(TAtlasColorMath.DeltaE2000(TAtlasSignals.Dark.Get(Kinds[mLeft]).Fill,
        TAtlasSignals.Dark.Get(Kinds[mRight]).Fill) >= 20, 'dunkel');
    end;
end;

procedure TAtlasSignalTests.StatusStatesMapToSignals;
var
  mSignals: TAtlasSignals;
begin
  Assert.IsTrue(TAtlasSignals.KindOf(TAtlasStatusState.Green) = TAtlasSignalKind.Ok);
  Assert.IsTrue(TAtlasSignals.KindOf(TAtlasStatusState.Yellow) = TAtlasSignalKind.Warn);
  Assert.IsTrue(TAtlasSignals.KindOf(TAtlasStatusState.Red) = TAtlasSignalKind.Error);
  Assert.IsTrue(TAtlasSignals.KindOf(TAtlasStatusState.Neutral) = TAtlasSignalKind.Idle);
  mSignals := TAtlasSignals.Light;
  Assert.AreEqual(mSignals.Get(TAtlasSignalKind.Error).Fill, mSignals.ForStatus(TAtlasStatusState.Red).Fill);
end;

procedure TAtlasSignalTests.PaletteFollowsSurface;
var
  mOk: TAtlasColor;
begin
  mOk := TAtlasSignals.Light.Get(TAtlasSignalKind.Ok).Fill;
  Assert.AreEqual(mOk, TAtlasColors.Light.Signals.Get(TAtlasSignalKind.Ok).Fill);
  // Leisten: Palette nach der Fläche der Leiste, nicht nach der Fensterfläche.
  Assert.AreEqual(mOk, TAtlasColors.ForChrome(TAtlasColorMath.FromHex('#F0F0F0'),
    TAtlasColorMath.FromHex('#000000')).Signals.Get(TAtlasSignalKind.Ok).Fill);
  Assert.AreEqual(TAtlasSignals.Dark.Get(TAtlasSignalKind.Ok).Fill, TAtlasColors.ForChrome(
    TAtlasColorMath.FromHex('#2B2B2B'), TAtlasColorMath.FromHex('#E6E6E6')).Signals.Get(TAtlasSignalKind.Ok).Fill);
  // Textfarben bleiben für Text.
  Assert.IsTrue(TAtlasColors.Light.Add <> mOk);
end;

end.
