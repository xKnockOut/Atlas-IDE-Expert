unit Atlas.Core.Designer.LabelPairs.Tests;

// Tests für Label und Eingabefeld als Paar (#729): Paar links, darüber, zu
// weit, ohne Überlappung, nächstes Feld; Grundlinie und Lage neuer Labels;
// Text und Name aus dem Feldnamen mit Abkürzungen; freies Tastenkürzel.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasLabelPairsTests = class
  public
    [Test]
    procedure LeftOfField;
    [Test]
    procedure AboveField;
    [Test]
    procedure TooFarOrBeside;
    [Test]
    procedure NearestAndLeftFirst;
    [Test]
    procedure Baseline;
    [Test]
    procedure PlaceNewLabel;
    [Test]
    procedure CaptionAndName;
    [Test]
    procedure Accelerator;
  end;

implementation

uses
  System.Types,
  Atlas.Core.Designer.LabelPairs;

procedure TAtlasLabelPairsTests.LeftOfField;
var
  mMatch: TAtlasPairMatch;
begin
  mMatch := TAtlasLabelPairs.FindField(Bounds(8, 12, 60, 15), [Bounds(76, 8, 120, 23)], 16);
  Assert.AreEqual(0, mMatch.Field);
  Assert.AreEqual<TAtlasPairSide>(TAtlasPairSide.Left, mMatch.Side);
end;

procedure TAtlasLabelPairsTests.AboveField;
var
  mMatch: TAtlasPairMatch;
begin
  mMatch := TAtlasLabelPairs.FindField(Bounds(10, 8, 60, 15), [Bounds(8, 26, 120, 23)], 16);
  Assert.AreEqual(0, mMatch.Field);
  Assert.AreEqual<TAtlasPairSide>(TAtlasPairSide.Above, mMatch.Side);
end;

procedure TAtlasLabelPairsTests.TooFarOrBeside;
begin
  Assert.AreEqual(-1, TAtlasLabelPairs.FindField(Bounds(8, 12, 60, 15), [Bounds(90, 8, 120, 23)], 16).Field,
    'Lücke 22 > 16');
  Assert.AreEqual(-1, TAtlasLabelPairs.FindField(Bounds(8, 40, 60, 15), [Bounds(76, 8, 120, 23)], 16).Field,
    'unter dem Feld');
  Assert.AreEqual(-1, TAtlasLabelPairs.FindField(Bounds(8, 8, 60, 15), [Bounds(40, 30, 120, 23)], 16).Field,
    'darüber, aber linke Kante 32 entfernt');
  Assert.AreEqual(-1, TAtlasLabelPairs.FindField(Bounds(100, 12, 60, 15), [Bounds(76, 8, 120, 23)], 16).Field,
    'überlappt das Feld');
  Assert.AreEqual(-1, TAtlasLabelPairs.FindField(Bounds(8, 12, 60, 15), nil, 16).Field);
end;

procedure TAtlasLabelPairsTests.NearestAndLeftFirst;
var
  mMatch: TAtlasPairMatch;
begin
  mMatch := TAtlasLabelPairs.FindField(Bounds(8, 12, 60, 15), [Bounds(82, 8, 120, 23), Bounds(72, 8, 120, 23)], 16);
  Assert.AreEqual(1, mMatch.Field, 'näheres Feld');
  mMatch := TAtlasLabelPairs.FindField(Bounds(8, 12, 60, 15), [Bounds(8, 28, 120, 23), Bounds(80, 8, 120, 23)], 16);
  Assert.AreEqual(1, mMatch.Field, 'links vor darüber');
  Assert.AreEqual<TAtlasPairSide>(TAtlasPairSide.Left, mMatch.Side);
end;

procedure TAtlasLabelPairsTests.Baseline;
begin
  // Segoe UI 9: Feld 23 hoch, Text 15 hoch, Ascent 12 → Grundlinie 8 + 4 + 12 = 24; Label-Ascent 12 → Top 12.
  Assert.AreEqual(12, TAtlasLabelPairs.BaselineTop(24, 12));
  // Segoe UI 12: Ascent 16 im Label, Feld 27 hoch mit Text 21 → Grundlinie 8 + 3 + 16 = 27 → Top 11.
  Assert.AreEqual(11, TAtlasLabelPairs.BaselineTop(27, 16));
end;

procedure TAtlasLabelPairsTests.PlaceNewLabel;
var
  mPoint: TPoint;
begin
  mPoint := TAtlasLabelPairs.Place(Bounds(100, 40, 120, 23), TSize.Create(50, 15), TAtlasPairSide.Left, 8, 56, 12);
  Assert.AreEqual(42, mPoint.X);
  Assert.AreEqual(44, mPoint.Y);
  mPoint := TAtlasLabelPairs.Place(Bounds(100, 40, 120, 23), TSize.Create(50, 15), TAtlasPairSide.Above, 4, 56, 12);
  Assert.AreEqual(103, mPoint.X);
  Assert.AreEqual(21, mPoint.Y);
end;

procedure TAtlasLabelPairsTests.CaptionAndName;
const
  cAbbr = TAtlasLabelPairs.cDefaultAbbreviations;
begin
  Assert.AreEqual('PLZ:', TAtlasLabelPairs.CaptionFor('edtPlz', cAbbr));
  Assert.AreEqual('Zahlungsart:', TAtlasLabelPairs.CaptionFor('cbxZahlungsart', cAbbr));
  Assert.AreEqual('Kunden Nr:', TAtlasLabelPairs.CaptionFor('edtKundenNr', cAbbr));
  Assert.AreEqual('USt ID:', TAtlasLabelPairs.CaptionFor('edtUstId', cAbbr));
  Assert.AreEqual('IBAN:', TAtlasLabelPairs.CaptionFor('edtIBAN', cAbbr), 'Großbuchstaben am Stück bleiben ein Wort');
  Assert.AreEqual('Edit1:', TAtlasLabelPairs.CaptionFor('Edit1', cAbbr), 'ohne Präfix');
  Assert.AreEqual('Name:', TAtlasLabelPairs.CaptionFor('name', cAbbr), 'nur klein');
  Assert.AreEqual('lblPlz', TAtlasLabelPairs.NameFor('edtPlz'));
  Assert.AreEqual('lblZahlungsart', TAtlasLabelPairs.NameFor('cbxZahlungsart'));
  Assert.AreEqual('lblEdit1', TAtlasLabelPairs.NameFor('Edit1'));
end;

procedure TAtlasLabelPairsTests.Accelerator;
begin
  Assert.AreEqual('&PLZ:', TAtlasLabelPairs.FreeAccelerator('PLZ:', ''));
  Assert.AreEqual('P&LZ:', TAtlasLabelPairs.FreeAccelerator('PLZ:', 'sp'));
  Assert.AreEqual('', TAtlasLabelPairs.FreeAccelerator('&Name:', ''), 'hat schon eins');
  Assert.AreEqual('', TAtlasLabelPairs.FreeAccelerator('AB:', 'ab'), 'keiner frei');
end;

end.
