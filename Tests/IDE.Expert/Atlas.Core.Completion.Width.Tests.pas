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
  Assert.AreEqual(TAtlasPopupWidth.cMinListWidth, TAtlasPopupWidth.Fit(100, TAtlasPopupWidth.cMinListWidth,
    TAtlasPopupWidth.cMaxListWidth));
  Assert.AreEqual(TAtlasPopupWidth.cMaxListWidth, TAtlasPopupWidth.Fit(5000, TAtlasPopupWidth.cMinListWidth,
    TAtlasPopupWidth.cMaxListWidth));
  Assert.AreEqual(400, TAtlasPopupWidth.Fit(400, TAtlasPopupWidth.cMinListWidth, TAtlasPopupWidth.cMaxListWidth));
end;

procedure TAtlasPopupWidthTests.LongSignatureFitsWithinMaxWidth;
const
  // 60 Zeichen Signatur bei 7 px je Zeichen, Name, Badge und Ränder.
  cMeasured = 60 * 7 + 120 + 47 + 30;
begin
  Assert.AreEqual(cMeasured, TAtlasPopupWidth.Fit(cMeasured, TAtlasPopupWidth.cMinListWidth,
    TAtlasPopupWidth.cMaxListWidth), 'Ohne Kürzung, solange MaxWidth reicht');
end;

procedure TAtlasPopupWidthTests.GrowsButNeverShrinks;
var
  mSession: Integer;
begin
  // Filtern von "A" (breite Einträge) zu "Add" (schmale): die Breite bleibt.
  mSession := TAtlasPopupWidth.Grow(0, 520);
  mSession := TAtlasPopupWidth.Grow(mSession, 310);
  Assert.AreEqual(520, mSession);
  mSession := TAtlasPopupWidth.Grow(mSession, 610);
  Assert.AreEqual(610, mSession);
end;

procedure TAtlasPopupWidthTests.ManualWidthWins;
begin
  Assert.AreEqual(450, TAtlasPopupWidth.Effective(450, 610));
  // Doppelklick auf den Griff setzt die gezogene Breite auf 0: wieder automatisch.
  Assert.AreEqual(610, TAtlasPopupWidth.Effective(0, 610));
end;

procedure TAtlasPopupWidthTests.PanelHasOwnLimits;
var
  mPanelMin, mListMin: Integer;
begin
  // Gezogene Panelbreite (#416): eigene Grenzen, unabhängig von der Liste.
  Assert.AreEqual(TAtlasPopupWidth.cMaxPanelWidth, TAtlasPopupWidth.Fit(900, TAtlasPopupWidth.cMinPanelWidth,
    TAtlasPopupWidth.cMaxPanelWidth));
  Assert.AreEqual(TAtlasPopupWidth.cMinPanelWidth, TAtlasPopupWidth.Fit(100, TAtlasPopupWidth.cMinPanelWidth,
    TAtlasPopupWidth.cMaxPanelWidth));
  // Über Variablen: Der Vergleich der Konstanten selbst ergibt W1022.
  mPanelMin := TAtlasPopupWidth.cMinPanelWidth;
  mListMin := TAtlasPopupWidth.cMinListWidth;
  Assert.IsTrue(mPanelMin < mListMin);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasPopupWidthTests);

end.
