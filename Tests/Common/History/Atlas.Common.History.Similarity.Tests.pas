unit Atlas.Common.History.Similarity.Tests;

// Tests der Ähnlichkeit von Rümpfen (#2641): gleiche Anweisungsfolge bis auf Namen, Kommentare ohne Gewicht,
// fremde Rümpfe, zu kurze Rümpfe.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSymbolSimilarityTests = class
  public
    [Test]
    procedure SameStatementsWithOtherNamesAreEqual;
    [Test]
    procedure CommentsAndHeaderDoNotCount;
    [Test]
    procedure ForeignBodyIsLow;
    [Test]
    procedure ShortBodiesCompareAsZero;
  end;

implementation

uses
  Atlas.Common.History.Similarity;

const
  cBody =
    'procedure TFoo.Alt(AWert: Integer);'#10 +
    'var'#10 +
    '  mSumme: Integer;'#10 +
    'begin'#10 +
    '  mSumme := 0;'#10 +
    '  while AWert > 0 do'#10 +
    '  begin'#10 +
    '    mSumme := mSumme + AWert;'#10 +
    '    Dec(AWert);'#10 +
    '  end;'#10 +
    '  Ausgabe(''Summe'', mSumme);'#10 +
    'end;';
  cRenamed =
    'function TBar.Neu(const AZahl: Int64; ATiefe: Integer): Boolean;'#10 +
    'var'#10 +
    '  mTotal: Integer;'#10 +
    'begin'#10 +
    '  // Summe bilden'#10 +
    '  mTotal := 1;'#10 +
    '  while AZahl > 0 do'#10 +
    '  begin'#10 +
    '    mTotal := mTotal + AZahl;'#10 +
    '    Dec(AZahl);'#10 +
    '  end;'#10 +
    '  Melde(''Total'', mTotal);'#10 +
    'end;';
  cForeign =
    'procedure TFoo.Andere;'#10 +
    'begin'#10 +
    '  if FListe.Count = 0 then'#10 +
    '    Exit;'#10 +
    '  try'#10 +
    '    FListe.Sort;'#10 +
    '  finally'#10 +
    '    FListe.Free;'#10 +
    '  end;'#10 +
    'end;';

procedure TSymbolSimilarityTests.SameStatementsWithOtherNamesAreEqual;
begin
  Assert.AreEqual(1.0, TSymbolSimilarity.Compare(TSymbolSimilarity.Shape(cBody), TSymbolSimilarity.Shape(cRenamed)),
    0.0001);
end;

procedure TSymbolSimilarityTests.CommentsAndHeaderDoNotCount;
var
  mShape: TArray<string>;
begin
  mShape := TSymbolSimilarity.Shape(cRenamed);
  Assert.AreEqual('var', mShape[0], 'Kopf übersprungen');
  Assert.AreEqual(Integer(Length(TSymbolSimilarity.Shape(cBody))), Integer(Length(mShape)), 'Kommentar fehlt');
end;

procedure TSymbolSimilarityTests.ForeignBodyIsLow;
begin
  Assert.IsTrue(TSymbolSimilarity.Compare(TSymbolSimilarity.Shape(cBody), TSymbolSimilarity.Shape(cForeign)) < 0.5);
end;

procedure TSymbolSimilarityTests.ShortBodiesCompareAsZero;
var
  mShort: TArray<string>;
begin
  mShort := TSymbolSimilarity.Shape('procedure A;'#10'begin'#10'  B;'#10'end;');
  Assert.AreEqual(0.0, TSymbolSimilarity.Compare(mShort, mShort), 0.0001);
end;

initialization
  TDUnitX.RegisterTestFixture(TSymbolSimilarityTests);

end.
