unit Atlas.Common.Pascal.FormatStrings.Tests;

// Tests der Zerlegung von Formatstrings (#56): Platzhalter mit Index, Breite,
// Genauigkeit und "*", "%%", ungültige Platzhalter, Argumentzahl, Platzhalter
// abhängig vom Gebietsschema und Werte von Stringliteralen. Für den
// Parameter-Hint (#451): Lage der Zeichen, Verkettungen, Konstanten, Art
// eines Literals und die Typtabelle.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFormatStringsTests = class
  public
    [Test]
    procedure SimpleSpecs;
    [Test]
    procedure IndexWidthAndPrecision;
    [Test]
    procedure StarTakesArguments;
    [Test]
    procedure InvalidSpecs;
    [Test]
    procedure LocaleSpecifiers;
    [Test]
    procedure LiteralValues;
    [Test]
    procedure LiteralOffsetsPointIntoSource;
    [Test]
    procedure ExpressionAndConstantValues;
    [Test]
    procedure LiteralClasses;
    [Test]
    procedure FitsByTypeChar;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.FormatStrings;

procedure TFormatStringsTests.SimpleSpecs;
var
  mFormat: TFormatString;
begin
  mFormat := TFormatString.Parse('Kunde %s hat %d Aufträge, 100%% fertig');
  Assert.IsTrue(mFormat.Valid);
  Assert.AreEqual(2, Integer(Length(mFormat.Specs)));
  Assert.AreEqual('%s', mFormat.Specs[0].Text);
  Assert.AreEqual(7, mFormat.Specs[0].Offset);
  Assert.AreEqual('s', mFormat.Specs[0].TypeChar);
  Assert.AreEqual(0, mFormat.Specs[0].Argument);
  Assert.AreEqual('d', mFormat.Specs[1].TypeChar);
  Assert.AreEqual(1, mFormat.Specs[1].Argument);
  Assert.AreEqual(2, mFormat.ArgumentCount);
  Assert.IsFalse(mFormat.HasExplicitIndex);
  // Großbuchstaben zählen wie kleine.
  mFormat := TFormatString.Parse('%D %X');
  Assert.AreEqual('d', mFormat.Specs[0].TypeChar);
  Assert.AreEqual('x', mFormat.Specs[1].TypeChar);
  Assert.AreEqual(0, TFormatString.Parse('ohne Platzhalter').ArgumentCount);
end;

procedure TFormatStringsTests.IndexWidthAndPrecision;
var
  mFormat: TFormatString;
begin
  // Ein Index zählt die folgenden Platzhalter ab dort weiter (wie FormatBuf).
  mFormat := TFormatString.Parse('%1:s %s %0:-10.2f %d');
  Assert.IsTrue(mFormat.Valid);
  Assert.AreEqual(1, mFormat.Specs[0].Argument);
  Assert.AreEqual(2, mFormat.Specs[1].Argument);
  Assert.AreEqual('%0:-10.2f', mFormat.Specs[2].Text);
  Assert.AreEqual(0, mFormat.Specs[2].Argument);
  Assert.AreEqual(1, mFormat.Specs[3].Argument);
  Assert.AreEqual(3, mFormat.ArgumentCount);
  Assert.IsTrue(mFormat.HasExplicitIndex);
  mFormat := TFormatString.Parse('%0:s %0:s');
  Assert.AreEqual(1, mFormat.ArgumentCount);
  Assert.AreEqual('%-8.3d', TFormatString.Parse('[%-8.3d]').Specs[0].Text);
end;

procedure TFormatStringsTests.StarTakesArguments;
var
  mFormat: TFormatString;
begin
  mFormat := TFormatString.Parse('%*d %.*f %*.*s');
  Assert.IsTrue(mFormat.Valid);
  Assert.AreEqual(0, mFormat.Specs[0].WidthArgument);
  Assert.AreEqual(1, mFormat.Specs[0].Argument);
  Assert.AreEqual(-1, mFormat.Specs[1].WidthArgument);
  Assert.AreEqual(2, mFormat.Specs[1].PrecisionArgument);
  Assert.AreEqual(3, mFormat.Specs[1].Argument);
  Assert.AreEqual(4, mFormat.Specs[2].WidthArgument);
  Assert.AreEqual(5, mFormat.Specs[2].PrecisionArgument);
  Assert.AreEqual(6, mFormat.Specs[2].Argument);
  Assert.AreEqual(7, mFormat.ArgumentCount);
  // Index aus der Argumentliste: Zuordnung ab dort unbekannt.
  mFormat := TFormatString.Parse('%s %*:s %d');
  Assert.IsTrue(mFormat.Valid);
  Assert.IsFalse(mFormat.Specs[0].Dynamic);
  Assert.IsTrue(mFormat.Specs[1].Dynamic);
  Assert.AreEqual(-1, mFormat.Specs[2].Argument);
  Assert.AreEqual(-1, mFormat.ArgumentCount);
end;

procedure TFormatStringsTests.InvalidSpecs;
var
  mFormat: TFormatString;
begin
  mFormat := TFormatString.Parse('Wert %q');
  Assert.IsFalse(mFormat.Valid);
  Assert.AreEqual(Ord(TFormatSpecKind.UnknownType), Ord(mFormat.Specs[0].Kind));
  Assert.AreEqual('%q', mFormat.Specs[0].Text);
  Assert.AreEqual(Ord(TFormatSpecKind.Incomplete), Ord(TFormatString.Parse('100%').Specs[0].Kind));
  mFormat := TFormatString.Parse('Breite %5');
  Assert.AreEqual(Ord(TFormatSpecKind.Incomplete), Ord(mFormat.Specs[0].Kind));
  Assert.AreEqual('%5', mFormat.Specs[0].Text);
  mFormat := TFormatString.Parse('%0: und %s');
  Assert.AreEqual(Ord(TFormatSpecKind.IndexWithoutType), Ord(mFormat.Specs[0].Kind));
  Assert.AreEqual('%0: ', mFormat.Specs[0].Text);
  Assert.AreEqual(Ord(TFormatSpecKind.Incomplete), Ord(TFormatString.Parse('%0:').Specs[0].Kind));
  Assert.AreEqual(Ord(TFormatSpecKind.UnknownType), Ord(TFormatString.Parse('%5 Stück').Specs[0].Kind));
  Assert.AreEqual(0, Integer(Length(TFormatString.Parse('%%').Specs)));
end;

procedure TFormatStringsTests.LocaleSpecifiers;
begin
  Assert.IsTrue(TFormatString.HasLocaleSpecifier('%.2f'));
  Assert.IsTrue(TFormatString.HasLocaleSpecifier('Summe: %0:-10.2n'));
  Assert.IsTrue(TFormatString.HasLocaleSpecifier('%M'));
  Assert.IsTrue(TFormatString.HasLocaleSpecifier('%*.*e'));
  Assert.IsFalse(TFormatString.HasLocaleSpecifier('%d %s %x %p %u'));
  Assert.IsFalse(TFormatString.HasLocaleSpecifier('100%% fertig'));
  Assert.IsFalse(TFormatString.HasLocaleSpecifier('%%f'));
  Assert.IsTrue(TFormatString.IsLocaleType('g'));
  Assert.IsFalse(TFormatString.IsLocaleType('d'));
end;

procedure TFormatStringsTests.LiteralValues;
var
  mValue: string;
begin
  Assert.IsTrue(TFormatString.LiteralValue('''Kunde %s''', mValue));
  Assert.AreEqual('Kunde %s', mValue);
  Assert.IsTrue(TFormatString.LiteralValue('''Kunde''''s %d''', mValue));
  Assert.AreEqual('Kunde''s %d', mValue);
  Assert.IsTrue(TFormatString.LiteralValue('''a''#13#10''b''#$41', mValue));
  Assert.AreEqual('a'#13#10'bA', mValue);
  Assert.IsTrue(TFormatString.LiteralValue('''''', mValue));
  Assert.AreEqual('', mValue);
  Assert.IsFalse(TFormatString.LiteralValue('cFormat', mValue));
  Assert.IsFalse(TFormatString.LiteralValue('''offen', mValue));
  Assert.IsFalse(TFormatString.LiteralValue('#$110000', mValue));
  Assert.IsFalse(TFormatString.LiteralValue('''''''' + #13#10'  Text'#13#10'  ''''''', mValue));
  Assert.IsFalse(TFormatString.LiteralValue('', mValue));
end;

procedure TFormatStringsTests.LiteralOffsetsPointIntoSource;
var
  mValue: string;
  mOffsets: TArray<Integer>;
begin
  // 'a''b'#13'c': a an 1, das doppelte Hochkomma an 2, b an 4, #13 an 6, c an 10.
  Assert.IsTrue(TFormatString.LiteralOffsets('''a''''b''#13''c''', mValue, mOffsets));
  Assert.AreEqual('a''b'#13'c', mValue);
  Assert.AreEqual(5, Integer(Length(mOffsets)));
  Assert.AreEqual(1, mOffsets[0]);
  Assert.AreEqual(2, mOffsets[1]);
  Assert.AreEqual(4, mOffsets[2]);
  Assert.AreEqual(6, mOffsets[3]);
  Assert.AreEqual(10, mOffsets[4]);
  Assert.IsFalse(TFormatString.LiteralOffsets('''offen', mValue, mOffsets));
end;

procedure TFormatStringsTests.ExpressionAndConstantValues;
var
  mValue: string;
begin
  Assert.IsTrue(TFormatString.ExpressionValue('''%s'' + #13 + ''%d''', mValue));
  Assert.AreEqual('%s'#13'%d', mValue);
  Assert.IsFalse(TFormatString.ExpressionValue('''%s'' + cRest', mValue));
  Assert.IsTrue(TFormatString.ConstantValue('cFormat = ''%s=%d''', mValue));
  Assert.AreEqual('%s=%d', mValue);
  Assert.IsTrue(TFormatString.ConstantValue('cFormat: string = ''a'' + ''b''', mValue));
  Assert.AreEqual('ab', mValue);
  // "=" erst im Literal, gekürzte Signatur, kein Wert.
  Assert.IsFalse(TFormatString.ConstantValue('cText: string', mValue));
  Assert.IsFalse(TFormatString.ConstantValue('cFormat = ''sehr lang' + #$2026, mValue));
end;

procedure TFormatStringsTests.LiteralClasses;
var
  mName: string;
begin
  Assert.AreEqual(Ord(TFormatArgumentClass.Text), Ord(TFormatString.LiteralClass('''Text''', mName)));
  Assert.AreEqual('ein String', mName);
  Assert.AreEqual(Ord(TFormatArgumentClass.Character), Ord(TFormatString.LiteralClass('#13', mName)));
  Assert.AreEqual(Ord(TFormatArgumentClass.Integer_), Ord(TFormatString.LiteralClass('-5', mName)));
  Assert.AreEqual('eine Zahl', mName);
  Assert.AreEqual(Ord(TFormatArgumentClass.Integer_), Ord(TFormatString.LiteralClass('$FE', mName)));
  Assert.AreEqual(Ord(TFormatArgumentClass.Float), Ord(TFormatString.LiteralClass('1.5', mName)));
  Assert.AreEqual(Ord(TFormatArgumentClass.Float), Ord(TFormatString.LiteralClass('2E3', mName)));
  Assert.AreEqual(Ord(TFormatArgumentClass.Unknown), Ord(TFormatString.LiteralClass('Name', mName)));
  Assert.AreEqual('', mName);
end;

procedure TFormatStringsTests.FitsByTypeChar;
begin
  Assert.IsTrue(TFormatString.Fits('d', TFormatArgumentClass.Integer_));
  Assert.IsFalse(TFormatString.Fits('d', TFormatArgumentClass.Text));
  Assert.IsFalse(TFormatString.Fits('d', TFormatArgumentClass.Bool));
  Assert.IsTrue(TFormatString.Fits('s', TFormatArgumentClass.Character));
  Assert.IsFalse(TFormatString.Fits('s', TFormatArgumentClass.Integer_));
  Assert.IsFalse(TFormatString.Fits('f', TFormatArgumentClass.Integer_));
  Assert.IsTrue(TFormatString.Fits('p', TFormatArgumentClass.Object_));
  Assert.IsFalse(TFormatString.Fits('*', TFormatArgumentClass.Float));
  // Unbekannt und Variant passen immer.
  Assert.IsTrue(TFormatString.Fits('d', TFormatArgumentClass.Unknown));
  Assert.IsTrue(TFormatString.Fits('f', TFormatArgumentClass.Variant_));
end;

initialization
  TDUnitX.RegisterTestFixture(TFormatStringsTests);

end.
