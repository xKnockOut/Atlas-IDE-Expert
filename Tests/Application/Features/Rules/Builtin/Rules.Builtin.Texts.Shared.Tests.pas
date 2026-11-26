unit Rules.Builtin.Texts.Shared.Tests;

// Tests der gemeinsamen Texthilfen der Regeln (Rules.Builtin.Texts.Shared): Format-Platzhalter mitten im Text und
// am Ende, Text für Menschen gegenüber Bezeichnern und Vorlagen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLiteralTextsTests = class
  public
    [Test]
    procedure FormatSpecifiers;
    [Test]
    procedure FormatSpecifierAtEnd;
    [Test]
    procedure TextForPeople;
  end;

implementation

uses
  Rules.Builtin.Texts.Shared;

{ TLiteralTextsTests }

procedure TLiteralTextsTests.FormatSpecifiers;
begin
  Assert.AreEqual(2, TLiteralTexts.FormatSpecifierLength('a %s b', 3));
  Assert.AreEqual(4, TLiteralTexts.FormatSpecifierLength('%0:s', 1));
  Assert.AreEqual(6, TLiteralTexts.FormatSpecifierLength('%-8.2f', 1));
  Assert.AreEqual(3, TLiteralTexts.FormatSpecifierLength('%*d', 1));
  Assert.AreEqual(2, TLiteralTexts.FormatSpecifierLength('%%', 1));
  Assert.AreEqual(0, TLiteralTexts.FormatSpecifierLength('a %s b', 1), 'kein %');
  Assert.AreEqual(0, TLiteralTexts.FormatSpecifierLength('50 %', 4), '% am Ende');
  Assert.AreEqual(0, TLiteralTexts.FormatSpecifierLength('%q', 1), 'unbekannter Typ');
  Assert.AreEqual(0, TLiteralTexts.FormatSpecifierLength('', 1), 'leer');
end;

procedure TLiteralTextsTests.FormatSpecifierAtEnd;
begin
  Assert.IsTrue(TLiteralTexts.EndsWithFormatSpecifier('Wert %s'));
  Assert.IsTrue(TLiteralTexts.EndsWithFormatSpecifier('Fehler (%s).%s'));
  Assert.IsTrue(TLiteralTexts.EndsWithFormatSpecifier('Wert %0:d'));
  Assert.IsTrue(TLiteralTexts.EndsWithFormatSpecifier('Betrag %.2f'));
  Assert.IsFalse(TLiteralTexts.EndsWithFormatSpecifier('Wert %s Teile'));
  Assert.IsFalse(TLiteralTexts.EndsWithFormatSpecifier('Rabatt 100%%'));
  Assert.IsFalse(TLiteralTexts.EndsWithFormatSpecifier('Rabatt 100%%s'), '%% ist ein Prozentzeichen');
  Assert.IsFalse(TLiteralTexts.EndsWithFormatSpecifier('Blubb'));
  Assert.IsFalse(TLiteralTexts.EndsWithFormatSpecifier(''));
end;

procedure TLiteralTextsTests.TextForPeople;
begin
  Assert.IsTrue(TLiteralTexts.LooksLikeText('Datei nicht gefunden'));
  Assert.IsTrue(TLiteralTexts.LooksLikeText('Wert %s ist zu groß'));
  Assert.IsFalse(TLiteralTexts.LooksLikeText('AtlasServer'), 'ohne Leerzeichen');
  Assert.IsFalse(TLiteralTexts.LooksLikeText('%s → %s (%s)'), 'Vorlage ohne Buchstaben');
  Assert.IsFalse(TLiteralTexts.LooksLikeText('a b'), 'zu wenige Buchstaben');
  Assert.IsFalse(TLiteralTexts.LooksLikeText(' Text '), 'Leerzeichen nur am Rand');
end;

initialization
  TDUnitX.RegisterTestFixture(TLiteralTextsTests);

end.
