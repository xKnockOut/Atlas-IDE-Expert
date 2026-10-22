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

initialization
  TDUnitX.RegisterTestFixture(TOrdinalConstantsTests);

end.
