unit Lsp.HoverValues.Tests;

interface

uses
  DUnitX.TestFramework,
  Lsp.HoverValues;

type
  [TestFixture]
  TLspHoverValuesTests = class
  public
    [Test]
    procedure ParsesNumberNotations;
    [Test]
    procedure RejectsNonNumbers;
    [Test]
    procedure FormatsNumbers;
    [Test]
    procedure ReadsConstantValues;
    [Test]
    procedure ReadsSetConstants;
    [Test]
    procedure ReadsStringConstants;
    [Test]
    procedure ReadsSetTypes;
    [Test]
    procedure FindsDeprecationDirectives;
    /// <summary>Aus "A, B: Integer" nur der gefragte Name mit Typ und Wörtern davor.</summary>
    [Test]
    procedure ReducesNameListToOneName;
    /// <summary>Routinen, Typen, Konstanten, Properties und fremde Namen bleiben unberührt.</summary>
    [Test]
    procedure KeepsOtherDeclarations;
    /// <summary>Aufzählung über mehrere Zeilen mit Kommentar je Wert: alle Werte in einer Zeile.</summary>
    [Test]
    procedure JoinsEnumerationOverSeveralLines;
    /// <summary>Parameterliste und Vorfahren über mehrere Zeilen, Direktiven hinter der Klammer.</summary>
    [Test]
    procedure JoinsParameterListsAndAncestors;
    /// <summary>Sehr lange Listen enden mit "…" vor der schließenden Klammer.</summary>
    [Test]
    procedure ShortensLongLists;
    /// <summary>Einzeilige, offene und Klassen-Deklarationen bleiben beim Text der ersten Zeile.</summary>
    [Test]
    procedure KeepsSingleLineDeclarations;
    /// <summary>Beginnt die Stelle mitten in einer Klammer (Aufzählungswert NoChange in „(None, NoChange, …);“),
    /// schließt die erste Zeile eine fremde Klammer: nichts zusammenziehen, statt bis zur nächsten Klammer weiter
    /// unten zu lesen.</summary>
    [Test]
    procedure IgnoresClosingBracketOpenedBefore;
  end;

implementation

uses
  System.SysUtils;

{ TLspHoverValuesTests }

procedure TLspHoverValuesTests.ParsesNumberNotations;
var
  mValue: Int64;
begin
  Assert.IsTrue(THoverValues.TryParseNumber('15', mValue));
  Assert.AreEqual(Int64(15), mValue);
  Assert.IsTrue(THoverValues.TryParseNumber('$FF', mValue));
  Assert.AreEqual(Int64(255), mValue);
  Assert.IsTrue(THoverValues.TryParseNumber('%1010', mValue));
  Assert.AreEqual(Int64(10), mValue);
  Assert.IsTrue(THoverValues.TryParseNumber('&17', mValue));
  Assert.AreEqual(Int64(15), mValue);
  Assert.IsTrue(THoverValues.TryParseNumber('1_000', mValue));
  Assert.AreEqual(Int64(1000), mValue);
  Assert.IsTrue(THoverValues.TryParseNumber('-3', mValue));
  Assert.AreEqual(Int64(-3), mValue);
end;

procedure TLspHoverValuesTests.RejectsNonNumbers;
var
  mValue: Int64;
begin
  Assert.IsFalse(THoverValues.TryParseNumber('', mValue));
  Assert.IsFalse(THoverValues.TryParseNumber('Foo', mValue));
  Assert.IsFalse(THoverValues.TryParseNumber('1.5', mValue));
  Assert.IsFalse(THoverValues.TryParseNumber('$', mValue));
end;

procedure TLspHoverValuesTests.FormatsNumbers;
begin
  Assert.AreEqual('15 · $0F · %1111', THoverValues.FormatNumber(15));
  Assert.AreEqual('256 · $0100 · %100000000', THoverValues.FormatNumber(256));
  Assert.AreEqual('65536 · $00010000 · %10000000000000000', THoverValues.FormatNumber(65536));
end;

procedure TLspHoverValuesTests.ReadsConstantValues;
begin
  Assert.AreEqual('15 · $0F · %1111', THoverValues.ConstantValue('MaxCount = $F;'));
  Assert.AreEqual('3 · $03 · %11', THoverValues.ConstantValue('Limit: Integer = 3;'));
  Assert.AreEqual('7 · $07 · %111', THoverValues.ConstantValue('Old = 7 deprecated;'));
  Assert.AreEqual('''Text''', THoverValues.ConstantValue('Name = ''Text'';'));
  Assert.AreEqual('', THoverValues.ConstantValue('Value: Integer;'));
  Assert.AreEqual('', THoverValues.ConstantValue('Max = High(Integer);'));
end;

procedure TLspHoverValuesTests.ReadsSetConstants;
begin
  Assert.AreEqual('[fsBold, fsItalic] · 2 Elemente',
    THoverValues.ConstantValue('Stile: TFontStyles = [fsBold, fsItalic];'));
  Assert.AreEqual('[fsBold, fsItalic] · 2 Elemente',
    THoverValues.ConstantValue('Stile = [fsBold,fsItalic] deprecated ''Neu'';'));
  Assert.AreEqual('[1..5, 9] · 6 Elemente', THoverValues.ConstantValue('Ziffern = [1..5, 9];'));
  Assert.AreEqual('[''a''..''z''] · 26 Elemente', THoverValues.ConstantValue('Klein = [''a''..''z''];'));
  Assert.AreEqual('[Rot..Blau]', THoverValues.ConstantValue('Farben = [Rot..Blau];'));
  Assert.AreEqual('[] · leer', THoverValues.ConstantValue('Keine: TFontStyles = [];'));
end;

procedure TLspHoverValuesTests.ReadsStringConstants;
begin
  Assert.AreEqual('''Datei nicht gefunden''', THoverValues.ConstantValue('SNotFound = ''Datei nicht gefunden'';'));
  Assert.AreEqual('''Zeile 1⏎Zeile 2: Peter''s''',
    THoverValues.ConstantValue('SZwei = ''Zeile 1'' + #13#10 + ''Zeile 2: Peter''''s'';'));
  Assert.AreEqual('''AB''', THoverValues.ConstantValue('S = #$41''B'';'));
  Assert.AreEqual('', THoverValues.ConstantValue('S = ''A'' + Name;'));
end;

procedure TLspHoverValuesTests.ReadsSetTypes;
var
  mBaseType: string;
begin
  Assert.IsTrue(THoverValues.SetBaseType('TFontStyles = set of TFontStyle;', mBaseType));
  Assert.AreEqual('TFontStyle', mBaseType);
  Assert.AreEqual(-1, THoverValues.BaseTypeCount(mBaseType));
  Assert.IsTrue(THoverValues.SetBaseType('TOpts = set of (oA, oB, oC);', mBaseType));
  Assert.AreEqual(3, THoverValues.BaseTypeCount(mBaseType));
  Assert.IsTrue(THoverValues.SetBaseType('TBits = set of 0..31;', mBaseType));
  Assert.AreEqual(32, THoverValues.BaseTypeCount(mBaseType));
  Assert.AreEqual(256, THoverValues.BaseTypeCount('Byte'));
  Assert.IsFalse(THoverValues.SetBaseType('TFoo = class', mBaseType));
end;

procedure TLspHoverValuesTests.FindsDeprecationDirectives;
begin
  Assert.AreEqual('**Veraltet**', THoverValues.Deprecation(TArray<string>.Create('overload', 'deprecated'), ''));
  Assert.AreEqual('**Veraltet**: Bar verwenden',
    THoverValues.Deprecation(TArray<string>.Create('deprecated'), 'Bar verwenden'));
  Assert.AreEqual('**Plattformspezifisch**', THoverValues.Deprecation(TArray<string>.Create('platform'), ''));
  Assert.AreEqual('**Experimentell**', THoverValues.Deprecation(TArray<string>.Create('experimental'), ''));
  // Der erste Hinweis zählt; library und andere Direktiven zeigt der Hover nicht.
  Assert.AreEqual('**Plattformspezifisch**',
    THoverValues.Deprecation(TArray<string>.Create('platform', 'deprecated'), 'Alt'));
  Assert.AreEqual('', THoverValues.Deprecation(TArray<string>.Create('inline', 'library'), ''));
  Assert.AreEqual('', THoverValues.Deprecation(nil, ''));
end;

procedure TLspHoverValuesTests.ReducesNameListToOneName;
var
  mResult: string;
begin
  Assert.IsTrue(THoverValues.NameDeclaration('mTest1, mTest2, mTest3: string;', 'mTest2', mResult));
  Assert.AreEqual('mTest2: string;', mResult);
  Assert.IsTrue(THoverValues.NameDeclaration('Zaehler: Integer;', 'Zaehler', mResult));
  Assert.AreEqual('Zaehler: Integer;', mResult);
  Assert.IsTrue(THoverValues.NameDeclaration('const C, D: string', 'D', mResult));
  Assert.AreEqual('const D: string', mResult);
  Assert.IsTrue(THoverValues.NameDeclaration('class var A, B: TList<Integer>;', 'a', mResult));
  Assert.AreEqual('class var a: TList<Integer>;', mResult);
  Assert.IsTrue(THoverValues.NameDeclaration('A { erste }, B: Integer = 1', 'B', mResult));
  Assert.AreEqual('B: Integer = 1', mResult);
  // out ist hier der erste Name, kein Wort davor.
  Assert.IsTrue(THoverValues.NameDeclaration('out, B: Integer', 'B', mResult));
  Assert.AreEqual('B: Integer', mResult);
  Assert.IsTrue(THoverValues.NameDeclaration('out X, Y: Integer', 'X', mResult));
  Assert.AreEqual('out X: Integer', mResult);
  Assert.IsTrue(THoverValues.NameDeclaration('&Type, B: Integer;', '&Type', mResult));
  Assert.AreEqual('&Type: Integer;', mResult);
end;

procedure TLspHoverValuesTests.KeepsOtherDeclarations;
var
  mResult: string;
begin
  Assert.IsFalse(THoverValues.NameDeclaration('function Summe(A, B: Integer): Integer;', 'A', mResult));
  Assert.AreEqual('', mResult);
  Assert.IsFalse(THoverValues.NameDeclaration('TFoo = class', 'TFoo', mResult));
  Assert.IsFalse(THoverValues.NameDeclaration('Max = 10;', 'Max', mResult));
  Assert.IsFalse(THoverValues.NameDeclaration('property Count: Integer read FCount;', 'Count', mResult));
  Assert.IsFalse(THoverValues.NameDeclaration('A, B: Integer;', 'C', mResult));
  Assert.IsFalse(THoverValues.NameDeclaration('A, B', 'A', mResult));
  Assert.IsFalse(THoverValues.NameDeclaration('', 'A', mResult));
end;

procedure TLspHoverValuesTests.JoinsEnumerationOverSeveralLines;
var
  mLines: TArray<string>;
  mResult: string;
begin
  mLines := TArray<string>.Create(
    '  { Token-Arten der XML-Syntaxhervorhebung }',
    '  TXmlTokenKind = (',
    '    tkText,       // Text zwischen Tags',
    '    tkTagName,    // Tag-Namen und Attributnamen',
    '    tkEquals,     // = zwischen Attributname und -wert',
    '    tkAttrValue,  // Attributwert inkl. Anfuehrungszeichen',
    '    tkEntity,     // &name; &#123; &#x1F;',
    '    tkComment,    // <!-- ... --> (inkl. Begrenzer)',
    '    tkCData,      // <![CDATA[ ... ]]> (inkl. Begrenzer)',
    '    tkPI,         // <?ziel daten?> inkl. XML-Deklaration',
    '    tkDocType,    // <!DOCTYPE ...> inkl. interner DTD',
    '    tkInvalid     // Zeichen, die an dieser Stelle nicht erlaubt sind',
    '  );',
    '  TNext = class');
  Assert.IsTrue(THoverValues.SpannedDeclaration(mLines, 1, 2, mResult));
  Assert.AreEqual('TXmlTokenKind = (tkText, tkTagName, tkEquals, tkAttrValue, tkEntity, tkComment, tkCData, tkPI, ' +
    'tkDocType, tkInvalid);', mResult);
  // Werte mit Blockkommentaren und Zuweisungen, Klammer in der Zeile des letzten Werts.
  mLines := TArray<string>.Create(
    'TStufe = (sAus = 0, { nichts }',
    '  sEin = 1 (* alles *));');
  Assert.IsTrue(THoverValues.SpannedDeclaration(mLines, 0, 0, mResult));
  Assert.AreEqual('TStufe = (sAus = 0, sEin = 1);', mResult);
end;

procedure TLspHoverValuesTests.JoinsParameterListsAndAncestors;
var
  mLines: TArray<string>;
  mResult: string;
begin
  mLines := TArray<string>.Create(
    '    function Suche(const AText: string;',
    '      AFrom: Integer; // ab 1',
    '      out AFound: Integer): Boolean; overload; deprecated;',
    '    procedure Weiter;');
  Assert.IsTrue(THoverValues.SpannedDeclaration(mLines, 0, 4, mResult));
  Assert.AreEqual('function Suche(const AText: string; AFrom: Integer; out AFound: Integer): Boolean; overload; ' +
    'deprecated;', mResult);
  mLines := TArray<string>.Create(
    '  TDienst = class(TInterfacedObject,',
    '    IDienst)',
    '    FWert: Integer;');
  Assert.IsTrue(THoverValues.SpannedDeclaration(mLines, 0, 2, mResult));
  Assert.AreEqual('TDienst = class(TInterfacedObject, IDienst)', mResult);
end;

procedure TLspHoverValuesTests.ShortensLongLists;
var
  mLines: TArray<string>;
  mResult: string;
  mIndex: Integer;
begin
  SetLength(mLines, 102);
  mLines[0] := 'TViele = (';
  for mIndex := 1 to 100 do
  begin
    mLines[mIndex] := Format('  vWert%.3d,', [mIndex]);
  end;
  mLines[100] := '  vWert100';
  mLines[101] := ');';
  Assert.IsTrue(THoverValues.SpannedDeclaration(mLines, 0, 0, mResult));
  Assert.IsTrue(mResult.StartsWith('TViele = (vWert001, vWert002, '), mResult);
  Assert.IsTrue(mResult.EndsWith(', …);'), mResult);
  Assert.IsTrue(Length(mResult) <= 400, mResult);
  Assert.IsFalse(mResult.Contains('vWert100'), mResult);
end;

procedure TLspHoverValuesTests.IgnoresClosingBracketOpenedBefore;
var
  mLines: TArray<string>;
  mResult: string;
begin
  // Wie Atlas.Core.Assistants.Log: dahinter ein Record und eine Klasse mit einer Klammer in einer späteren Zeile.
  mLines := TArray<string>.Create(
    '  TBlock = (None, NoChange, AlreadyReverted);',
    '  TEintrag = record',
    '    Id: Integer;',
    '  end;',
    '  TLog = class',
    '    procedure SetEnabled(AValue: Boolean);',
    '  end;');
  Assert.IsFalse(THoverValues.SpannedDeclaration(mLines, 0, 18, mResult), mResult);
  Assert.AreEqual('', mResult);
  mLines := nil;
end;

procedure TLspHoverValuesTests.KeepsSingleLineDeclarations;
var
  mLines: TArray<string>;
  mResult: string;
begin
  mLines := TArray<string>.Create('  TFarbe = (Rot, Gruen); // Farben', '  TNext = (A, B);');
  Assert.IsFalse(THoverValues.SpannedDeclaration(mLines, 0, 2, mResult));
  Assert.AreEqual('', mResult);
  mLines := TArray<string>.Create('  TFoo = class(TBar)', '    FWert: Integer;', '  end;');
  Assert.IsFalse(THoverValues.SpannedDeclaration(mLines, 0, 2, mResult));
  mLines := TArray<string>.Create('  TFoo =', '    (A, B);');
  Assert.IsFalse(THoverValues.SpannedDeclaration(mLines, 0, 2, mResult));
  // Unvollständiger Code: Klammer bleibt offen.
  mLines := TArray<string>.Create('  TOffen = (A,', '    B,');
  Assert.IsFalse(THoverValues.SpannedDeclaration(mLines, 0, 2, mResult));
  Assert.IsFalse(THoverValues.SpannedDeclaration(mLines, 5, 0, mResult));
  Assert.IsFalse(THoverValues.SpannedDeclaration(nil, 0, 0, mResult));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspHoverValuesTests);

end.
