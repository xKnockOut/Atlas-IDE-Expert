unit Argus.Core.Editor.Pairs.Tests;

// Tests für Klammer- und Blockpaare (#514).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TArgusPairsTests = class
  public
    [Test]
    procedure NestedBeginEndHaveThreeDepths;
    [Test]
    procedure BracketsInStringsAndCommentsDoNotCount;
    [Test]
    procedure MissingEndMarksBeginRed;
    [Test]
    procedure TypeDeclarationsAndForwardsAndVariantCase;
    [Test]
    procedure TryFinallyRepeatUntilAndEscapes;
  end;

implementation

uses
  System.SysUtils,
  Argus.Core.Editor.Pairs;

/// <summary>"Text@Tiefe" je Token, unpaarige mit "!".</summary>
function Describe(const AText: string): string;
var
  Lines: TArray<string>;
  Token: TArgusPairToken;
begin
  Lines := AText.Split([#10]);
  Result := '';
  for Token in TArgusPairs.Analyze(AText) do
  begin
    Result := Result + Copy(Lines[Token.Line], Token.Character + 1, Token.Length) + '@' + IntToStr(Token.Depth);
    if Token.Unpaired then
      Result := Result + '!';
    Result := Result + ' ';
  end;
  Result := Trim(Result);
end;

procedure TArgusPairsTests.NestedBeginEndHaveThreeDepths;
begin
  Assert.AreEqual('begin@0 begin@1 begin@2 end@2 end@1 end@0',
    Describe('begin'#10'  begin'#10'    begin'#10'    end;'#10'  end;'#10'end;'));
  // Runde und eckige Klammern teilen sich die Tiefe.
  Assert.AreEqual('(@0 (@1 [@2 ]@2 )@1 )@0', Describe('X := F(G(A[1]));'));
end;

procedure TArgusPairsTests.BracketsInStringsAndCommentsDoNotCount;
begin
  Assert.AreEqual('(@0 )@0', Describe('S := Format(''(%d'', { ( } (* ( *) 1); // )'));
  Assert.AreEqual('', Describe('// begin'#10'{ end }'));
end;

procedure TArgusPairsTests.MissingEndMarksBeginRed;
begin
  Assert.AreEqual('begin@0! begin@1 end@1', Describe('begin'#10'  begin'#10'  end;'));
  Assert.AreEqual('end@0!', Describe('end;'));
  Assert.AreEqual(')@0!', Describe('X)'));
  // Ende der Unit ist kein unpaariges end.
  Assert.AreEqual('', Describe('unit X;'#10'interface'#10'implementation'#10'end.'));
end;

procedure TArgusPairsTests.TypeDeclarationsAndForwardsAndVariantCase;
begin
  Assert.AreEqual('class@0 end@0', Describe('TFoo = class'#10'  class function F: Integer;'#10'end;'));
  // Vorwärtsdeklaration und Kurzform ohne Rumpf.
  Assert.AreEqual('(@0 )@0', Describe('TFoo = class;'#10'TBar = class(TFoo);'));
  Assert.AreEqual('', Describe('TEvent = procedure of object;'#10'TMeta = class of TFoo;'));
  Assert.AreEqual('record@0 (@0 )@0 end@0',
    Describe('TRec = record'#10'  case Integer of'#10'    0: (A: Integer);'#10'end;'));
  Assert.AreEqual('interface@0 end@0', Describe('IFoo = interface'#10'end;'));
end;

procedure TArgusPairsTests.TryFinallyRepeatUntilAndEscapes;
begin
  Assert.AreEqual('try@0 repeat@1 until@1 finally@0 end@0',
    Describe('try'#10'  repeat'#10'  until X;'#10'finally'#10'end;'));
  Assert.AreEqual('begin@0 end@0', Describe('begin'#10'  &end := 1;'#10'  A.Begin;'#10'end;'));
end;

initialization
  TDUnitX.RegisterTestFixture(TArgusPairsTests);

end.