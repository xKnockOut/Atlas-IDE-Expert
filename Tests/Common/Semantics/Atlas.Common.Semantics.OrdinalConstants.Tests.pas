unit Atlas.Common.Semantics.OrdinalConstants.Tests;

// Tests der Auswertung ordinaler Konstantenausdrücke (#983): Zahlen in allen
// Schreibweisen, Zeichen, Operatoren mit Vorrang, Ord/Chr/Succ/Pred und
// Umwandlungen, Namen über die Rückfrage und nicht auswertbare Ausdrücke.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TOrdinalConstantsTests = class
  public
    [Test]
    procedure NumbersInAllNotations;
    [Test]
    procedure CharactersAndStrings;
    [Test]
    procedure OperatorsAndPrecedence;
    [Test]
    procedure FunctionsAndCasts;
    [Test]
    procedure NamesThroughLookup;
    [Test]
    procedure NotEvaluable;
    [Test]
    procedure SizeOfHighLowOfFixedTypes;
    [Test]
    procedure CheckGivesReason;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Semantics.OrdinalConstants;

function ValueOf(const AText: string): Int64;
begin
  Assert.IsTrue(TOrdinalConstants.Evaluate(AText, nil, Result), AText);
end;

procedure Unknown(const AText: string);
var
  Value: Int64;
begin
  Assert.IsFalse(TOrdinalConstants.Evaluate(AText, nil, Value), AText);
end;

{ TOrdinalConstantsTests }

procedure TOrdinalConstantsTests.NumbersInAllNotations;
begin
  Assert.AreEqual(Int64(42), ValueOf('42'));
  Assert.AreEqual(Int64(255), ValueOf('$FF'));
  Assert.AreEqual(Int64(5), ValueOf('%101'));
  Assert.AreEqual(Int64(8), ValueOf('&10'));
  Assert.AreEqual(Int64(1000000), ValueOf('1_000_000'));
  Assert.AreEqual(Int64(-3), ValueOf('-3'));
end;

procedure TOrdinalConstantsTests.CharactersAndStrings;
begin
  Assert.AreEqual(Int64(97), ValueOf('''a'''));
  Assert.AreEqual(Int64(39), ValueOf(''''''''''));
  Assert.AreEqual(Int64(13), ValueOf('#13'));
  Assert.AreEqual(Int64(13), ValueOf('#$0D'));
  Unknown('''ab''');
  Unknown('#13#10');
  Unknown('''a''#0');
end;

procedure TOrdinalConstantsTests.OperatorsAndPrecedence;
begin
  Assert.AreEqual(Int64(7), ValueOf('1 + 2 * 3'));
  Assert.AreEqual(Int64(9), ValueOf('(1 + 2) * 3'));
  Assert.AreEqual(Int64(3), ValueOf('7 div 2'));
  Assert.AreEqual(Int64(1), ValueOf('7 mod 2'));
  Assert.AreEqual(Int64(16), ValueOf('1 shl 4'));
  Assert.AreEqual(Int64(6), ValueOf('$F and 6'));
  Assert.AreEqual(Int64(7), ValueOf('3 or 4'));
  Assert.AreEqual(Int64(6), ValueOf('5 xor 3'));
  Assert.AreEqual(Int64(-1), ValueOf('not 0'));
  Assert.AreEqual(Int64(1), ValueOf('True'));
end;

procedure TOrdinalConstantsTests.FunctionsAndCasts;
begin
  Assert.AreEqual(Int64(120), ValueOf('Ord(''x'')'));
  Assert.AreEqual(Int64(65), ValueOf('Chr(65)'));
  Assert.AreEqual(Int64(4), ValueOf('Succ(3)'));
  Assert.AreEqual(Int64(2), ValueOf('Pred(3)'));
  Assert.AreEqual(Int64(200), ValueOf('Byte(200)'));
  Unknown('Length(''abc'')');
  // Low und High eingebauter Typen, MaxInt (#1083).
  Assert.AreEqual(Int64(2147483647), ValueOf('High(Integer)'));
  Assert.AreEqual(Int64(-128), ValueOf('Low(ShortInt)'));
  Assert.AreEqual(Int64(4294967295), ValueOf('High(Cardinal)'));
  Assert.AreEqual(Int64(65535), ValueOf('High(Char)'));
  Assert.AreEqual(Int64(2147483646), ValueOf('MaxInt - 1'));
  Unknown('High(NativeInt)');
  Unknown('High(Werte)');
  Unknown('High(Integer');
end;

procedure TOrdinalConstantsTests.NamesThroughLookup;
var
  Tokens: TArray<TPascalToken>;
  Value: Int64;
  Seen: string;
  Lookup: TOrdinalNameLookup;
begin
  Seen := '';
  Lookup :=
    function(const ANames: TArray<string>; ATokenIndex: Integer; out AValue: Int64): Boolean
    begin
      Seen := Seen + string.Join('.', ANames) + '@' + IntToStr(ATokenIndex) + ' ';
      AValue := 10;
      Result := ANames[High(ANames)] = 'Max';
    end;
  Tokens := TPascalLexer.Tokenize('Max + TGrenzen.Max');
  Assert.IsTrue(TOrdinalConstants.Evaluate(Tokens, 0, High(Tokens), Lookup, Value));
  Assert.AreEqual(Int64(20), Value);
  Assert.AreEqual('Max@0 TGrenzen.Max@2 ', Seen);
  Assert.IsFalse(TOrdinalConstants.Evaluate('Min + 1', Lookup, Value));
  // Nur die Token AFirst..ALast zählen.
  Tokens := TPascalLexer.Tokenize('1, 2..5');
  Assert.IsTrue(TOrdinalConstants.Evaluate(Tokens, 2, 2, nil, Value));
  Assert.AreEqual(Int64(2), Value);
  Seen := '';
end;

procedure TOrdinalConstantsTests.NotEvaluable;
begin
  Unknown('');
  Unknown('1.5');
  Unknown('1 / 2');
  Unknown('1 div 0');
  Unknown('1 +');
  Unknown('(1');
  Unknown('1 2');
  Unknown('$7FFFFFFFFFFFFFFF * 2');
  Unknown('99999999999999999999');
  Unknown('Foo');
end;

procedure TOrdinalConstantsTests.SizeOfHighLowOfFixedTypes;
begin
  Assert.AreEqual(Int64(255), ValueOf('High(Byte)'));
  Assert.AreEqual(Int64(-128), ValueOf('Low(ShortInt)'));
  Assert.AreEqual(Int64(4), ValueOf('SizeOf(Integer)'));
  Assert.AreEqual(Int64(8), ValueOf('SizeOf(Double)'));
  Assert.AreEqual(Int64(2), ValueOf('SizeOf(Char)'));
  Assert.AreEqual(Int64(High(Int64)), ValueOf('High(Int64)'));
  Assert.AreEqual(Int64(16), ValueOf('SizeOf(Int64) * 2'));
  // Plattformabhängig oder unbekannt.
  Unknown('SizeOf(NativeInt)');
  Unknown('SizeOf(Pointer)');
  Unknown('High(UInt64)');
  Unknown('High(Double)');
  Unknown('SizeOf(TKunde)');
end;

procedure TOrdinalConstantsTests.CheckGivesReason;
var
  Value: Int64;
begin
  Assert.AreEqual(Ord(TOrdinalStatus.Value), Ord(TOrdinalConstants.Check('6 div 2', nil, Value)));
  Assert.AreEqual(Int64(3), Value);
  Assert.AreEqual(Ord(TOrdinalStatus.DivisionByZero), Ord(TOrdinalConstants.Check('100 div 0', nil, Value)));
  Assert.AreEqual(Ord(TOrdinalStatus.DivisionByZero), Ord(TOrdinalConstants.Check('100 mod (2 - 2)', nil, Value)));
  Assert.AreEqual(Ord(TOrdinalStatus.Overflow), Ord(TOrdinalConstants.Check('1000000 * 1000000 * 1000000 * 1000',
    nil, Value)));
  Assert.AreEqual(Ord(TOrdinalStatus.Overflow), Ord(TOrdinalConstants.Check('Low(Int64) - 10', nil, Value)));
  // Passt noch in UInt64: Delphi rechnet es vorzeichenlos, Atlas weiß es nicht sicher.
  Assert.AreEqual(Ord(TOrdinalStatus.Unknown), Ord(TOrdinalConstants.Check('High(Int64) + 1', nil, Value)));
  Assert.AreEqual(Ord(TOrdinalStatus.Unknown), Ord(TOrdinalConstants.Check('$7FFFFFFFFFFFFFFF * 2', nil, Value)));
  // Unbekannter linker Teil: kein Grund.
  Assert.AreEqual(Ord(TOrdinalStatus.Unknown), Ord(TOrdinalConstants.Check('Foo div 0', nil, Value)));
  Assert.AreEqual(Ord(TOrdinalStatus.Unknown), Ord(TOrdinalConstants.Check('1.5', nil, Value)));
end;

initialization
  TDUnitX.RegisterTestFixture(TOrdinalConstantsTests);

end.
