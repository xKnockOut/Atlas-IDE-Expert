unit Atlas.Core.StatusBar.Layout.Tests;

// Atlas-Statusleiste (#1155): Aufteilung der Breite. Alles passt in voller
// Breite; sonst kürzt sich die Methode zuerst bis auf ihre Mindestbreite, dann
// die nächste Stufe; reicht auch das nicht, fallen Elemente ganz weg. Nichts
// bricht um. Klickflächen nebeneinander mit Trennstrichen, auch bei der
// doppelten Pixeldichte.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasStatusBarLayoutTests = class
  public
    [Test]
    procedure EverythingFits;
    [Test]
    procedure MethodShrinksFirst;
    [Test]
    procedure NextStageShrinksAfterMethod;
    [Test]
    procedure DropsWhenEvenMinimumIsTooWide;
    [Test]
    procedure PlaceAndHitTest;
    [Test]
    procedure ScalesWithDpi;
    [Test]
    procedure MinWidthNeverAboveWidth;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.StatusBar.Layout;

const
  Gap = 9;

function Slots(AScale: Integer): TArray<TAtlasStatusSlot>;
begin
  // Status, Meldungen, Live-Prüfung, Methode (kürzt sich zuerst).
  Result := [TAtlasStatusSlot.Create(110 * AScale, 70 * AScale, 3), TAtlasStatusSlot.Create(120 * AScale,
    120 * AScale, 4), TAtlasStatusSlot.Create(140 * AScale, 60 * AScale, 2), TAtlasStatusSlot.Create(260 * AScale,
    90 * AScale, 1)];
end;

function Joined(const AWidths: TArray<Integer>): string;
var
  Width: Integer;
begin
  Result := '';
  for Width in AWidths do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + IntToStr(Width);
  end;
end;

procedure TAtlasStatusBarLayoutTests.EverythingFits;
begin
  Assert.AreEqual(110 + 120 + 140 + 260 + 3 * Gap, TAtlasStatusBarLayout.FullWidth(Slots(1), Gap));
  Assert.AreEqual('110 120 140 260', Joined(TAtlasStatusBarLayout.Fit(Slots(1), 1000, Gap)));
  Assert.AreEqual('110 120 140 260', Joined(TAtlasStatusBarLayout.Fit(Slots(1), 657, Gap)), 'genau passend');
end;

procedure TAtlasStatusBarLayoutTests.MethodShrinksFirst;
begin
  // 100 Pixel zu wenig: nur die Methode wird kürzer.
  Assert.AreEqual('110 120 140 160', Joined(TAtlasStatusBarLayout.Fit(Slots(1), 557, Gap)));
end;

procedure TAtlasStatusBarLayoutTests.NextStageShrinksAfterMethod;
begin
  // Methode auf 90 (170 gewonnen), dann die Live-Prüfung um weitere 30.
  Assert.AreEqual('110 120 110 90', Joined(TAtlasStatusBarLayout.Fit(Slots(1), 657 - 200, Gap)));
  // Alle auf Mindestbreite: 70 + 120 + 60 + 90 + 27.
  Assert.AreEqual('70 120 60 90', Joined(TAtlasStatusBarLayout.Fit(Slots(1), 367, Gap)));
end;

procedure TAtlasStatusBarLayoutTests.DropsWhenEvenMinimumIsTooWide;
begin
  // Ein Pixel weniger als alle Mindestbreiten: Die Methode fällt weg.
  Assert.AreEqual('70 120 60 0', Joined(TAtlasStatusBarLayout.Fit(Slots(1), 366, Gap)));
  // Danach die Live-Prüfung, dann der Status; die Meldungen bleiben am längsten.
  Assert.AreEqual('70 120 0 0', Joined(TAtlasStatusBarLayout.Fit(Slots(1), 199, Gap)));
  Assert.AreEqual('0 120 0 0', Joined(TAtlasStatusBarLayout.Fit(Slots(1), 120, Gap)));
  Assert.AreEqual('0 0 0 0', Joined(TAtlasStatusBarLayout.Fit(Slots(1), 50, Gap)));
  Assert.AreEqual('', Joined(TAtlasStatusBarLayout.Fit(nil, 50, Gap)), 'leere Leiste');
end;

procedure TAtlasStatusBarLayoutTests.PlaceAndHitTest;
var
  Spans: TArray<TAtlasStatusSpan>;
begin
  Spans := TAtlasStatusBarLayout.Place([100, 0, 50], 4, Gap);
  Assert.AreEqual(4, Spans[0].Left);
  Assert.AreEqual(104, Spans[0].Right);
  Assert.IsTrue(Spans[1].IsEmpty, 'weggefallen');
  // Nur ein Trennstrich zwischen den sichtbaren.
  Assert.AreEqual(113, Spans[2].Left);
  Assert.AreEqual(163, Spans[2].Right);
  Assert.AreEqual(0, TAtlasStatusBarLayout.IndexAt(Spans, 4));
  Assert.AreEqual(0, TAtlasStatusBarLayout.IndexAt(Spans, 103));
  Assert.AreEqual(-1, TAtlasStatusBarLayout.IndexAt(Spans, 104), 'Trennstrich');
  Assert.AreEqual(-1, TAtlasStatusBarLayout.IndexAt(Spans, 110));
  Assert.AreEqual(2, TAtlasStatusBarLayout.IndexAt(Spans, 113));
  Assert.AreEqual(-1, TAtlasStatusBarLayout.IndexAt(Spans, 163));
  Assert.AreEqual(-1, TAtlasStatusBarLayout.IndexAt(Spans, 0));
end;

procedure TAtlasStatusBarLayoutTests.ScalesWithDpi;
begin
  // Doppelte Dichte: dieselbe Aufteilung mit doppelten Zahlen.
  Assert.AreEqual('220 240 280 320', Joined(TAtlasStatusBarLayout.Fit(Slots(2), 2 * 557, 2 * Gap)));
  Assert.AreEqual('140 240 120 0', Joined(TAtlasStatusBarLayout.Fit(Slots(2), 2 * 366, 2 * Gap)));
end;

procedure TAtlasStatusBarLayoutTests.MinWidthNeverAboveWidth;
var
  Slot: TAtlasStatusSlot;
begin
  Slot := TAtlasStatusSlot.Create(40, 90, 1);
  Assert.AreEqual(40, Slot.MinWidth);
  Assert.AreEqual('40', Joined(TAtlasStatusBarLayout.Fit([Slot], 40, Gap)));
  Assert.AreEqual('0', Joined(TAtlasStatusBarLayout.Fit([Slot], 30, Gap)), 'nicht kürzbar: fällt weg');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStatusBarLayoutTests);

end.
