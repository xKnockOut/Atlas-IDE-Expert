unit Atlas.Core.Completion.Width.Tests;

// Tests für die Breite des Vervollständigungs-Popups (#416, #415): Grenzen,
// nur wachsen, gezogene Breite vor der Automatik, Grenzen des Panels.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasPopupWidthTests = class
  public
    [Test]
    procedure FitsIntoLimits;
    [Test]
    procedure LongSignatureFitsWithinMaxWidth;
    [Test]
    procedure GrowsButNeverShrinks;
    [Test]
    procedure ManualWidthWins;
    [Test]
    procedure PanelHasOwnLimits;
  end;

implementation

uses
  Atlas.Core.Completion.Width;

{ TAtlasPopupWidthTests }

procedure TAtlasPopupWidthTests.FitsIntoLimits;
begin
  Assert.AreEqual(TAtlasPopupWidth.MinListWidth, TAtlasPopupWidth.Fit(100, TAtlasPopupWidth.MinListWidth,
    TAtlasPopupWidth.MaxListWidth));
  Assert.AreEqual(TAtlasPopupWidth.MaxListWidth, TAtlasPopupWidth.Fit(5000, TAtlasPopupWidth.MinListWidth,
    TAtlasPopupWidth.MaxListWidth));
  Assert.AreEqual(400, TAtlasPopupWidth.Fit(400, TAtlasPopupWidth.MinListWidth, TAtlasPopupWidth.MaxListWidth));
end;

procedure TAtlasPopupWidthTests.LongSignatureFitsWithinMaxWidth;
const
  // 60 Zeichen Signatur bei 7 px je Zeichen, Name, Badge und Ränder.
  Measured = 60 * 7 + 120 + 47 + 30;
begin
  Assert.AreEqual(Measured, TAtlasPopupWidth.Fit(Measured, TAtlasPopupWidth.MinListWidth,
    TAtlasPopupWidth.MaxListWidth), 'Ohne Kürzung, solange MaxWidth reicht');
end;

procedure TAtlasPopupWidthTests.GrowsButNeverShrinks;
var
  Session: Integer;
begin
  // Filtern von "A" (breite Einträge) zu "Add" (schmale): die Breite bleibt.
  Session := TAtlasPopupWidth.Grow(0, 520);
  Session := TAtlasPopupWidth.Grow(Session, 310);
  Assert.AreEqual(520, Session);
  Session := TAtlasPopupWidth.Grow(Session, 610);
  Assert.AreEqual(610, Session);
end;

procedure TAtlasPopupWidthTests.ManualWidthWins;
begin
  Assert.AreEqual(450, TAtlasPopupWidth.Effective(450, 610));
  // Doppelklick auf den Griff setzt die gezogene Breite auf 0: wieder automatisch.
  Assert.AreEqual(610, TAtlasPopupWidth.Effective(0, 610));
end;

procedure TAtlasPopupWidthTests.PanelHasOwnLimits;
begin
  // Gezogene Panelbreite (#416): eigene Grenzen, unabhängig von der Liste.
  Assert.AreEqual(TAtlasPopupWidth.MaxPanelWidth, TAtlasPopupWidth.Fit(900, TAtlasPopupWidth.MinPanelWidth,
    TAtlasPopupWidth.MaxPanelWidth));
  Assert.AreEqual(TAtlasPopupWidth.MinPanelWidth, TAtlasPopupWidth.Fit(100, TAtlasPopupWidth.MinPanelWidth,
    TAtlasPopupWidth.MaxPanelWidth));
  Assert.IsTrue(TAtlasPopupWidth.MinPanelWidth < TAtlasPopupWidth.MinListWidth);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasPopupWidthTests);

end.
