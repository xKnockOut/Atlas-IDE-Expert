unit Atlas.Common.Pascal.Signatures.Tests;

// Tests für das Lesen von Routinenköpfen, Parameterlisten und Verwendungen eines Namens.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPascalSignaturesTests = class
  public
    [Test]
    procedure ParsesParameters;
    [Test]
    procedure ReadsDeclarationHeader;
    [Test]
    procedure ReadsProcedureType;
    [Test]
    procedure ClassifiesUses;
    [Test]
    procedure FindsParameterUses;
  end;

implementation

uses
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.Signatures,
  Atlas.Common.Pascal.TestSupport;

procedure TPascalSignaturesTests.ParsesParameters;
var
  mParameters: TArray<TSignatureParameter>;
begin
  mParameters := TPascalSignatures.ParseParameters('const A, B: Integer; var Buffer; [ref] const C: TList<string>; ' +
    'D: string = ''x;y''; out E: array of Byte');
  Assert.AreEqual(6, Integer(Length(mParameters)));
  Assert.AreEqual('const', mParameters[0].Modifier);
  Assert.AreEqual('B', mParameters[1].Name);
  Assert.AreEqual('Integer', mParameters[1].TypeName);
  Assert.AreEqual('var', mParameters[2].Modifier);
  Assert.AreEqual('', mParameters[2].TypeName);
  Assert.AreEqual('[ref] const', mParameters[3].Modifier);
  Assert.AreEqual('TList<string>', mParameters[3].TypeName);
  Assert.AreEqual('''x;y''', mParameters[4].DefaultValue);
  Assert.AreEqual('array of Byte', mParameters[5].TypeName);
  Assert.AreEqual('out', mParameters[5].Modifier);
end;

procedure TPascalSignaturesTests.ReadsDeclarationHeader;
const
  cText = '  class function Teile(A, B: Integer; const C: string = ''-''): Double; virtual; abstract;';
var
  mTokens: TArray<TPascalToken>;
  mHeader: TSignatureHeader;
begin
  mTokens := TPascalLexer.Tokenize(cText);
  Assert.IsTrue(TPascalSignatures.ReadHeader(cText, mTokens, TPascalTest.TokenOf(mTokens, 'Teile', 1), mHeader));
  Assert.IsTrue(mHeader.IsClass);
  Assert.IsTrue(mHeader.IsFunction);
  Assert.AreEqual('Double', mHeader.ResultType);
  Assert.AreEqual(3, Integer(Length(mHeader.Parameters)));
  Assert.AreEqual('''-''', mHeader.Parameters[2].DefaultValue);
  Assert.AreEqual(2, Integer(Length(mHeader.Directives)));
  Assert.IsTrue(mHeader.HasDirective('abstract'));
  Assert.AreEqual('class', mTokens[mHeader.StartToken].Text);
  Assert.AreEqual(';', mTokens[mHeader.EndToken].Text);
  Assert.IsTrue(mHeader.LastToken > mHeader.EndToken);
  // Ein Aufruf ist kein Kopf.
  Assert.IsFalse(TPascalSignatures.ReadHeader('X := Teile(1, 2);', TPascalLexer.Tokenize('X := Teile(1, 2);'), 2,
    mHeader));
end;

procedure TPascalSignaturesTests.ReadsProcedureType;
const
  cText = '  TWertEvent = procedure(Sender: TObject; Wert: Integer) of object;';
var
  mTokens: TArray<TPascalToken>;
  mHeader: TSignatureHeader;
begin
  mTokens := TPascalLexer.Tokenize(cText);
  Assert.IsTrue(TPascalSignatures.ReadProcedureType(cText, mTokens, TPascalTest.TokenOf(mTokens, 'TWertEvent', 1), mHeader));
  Assert.AreEqual(2, Integer(Length(mHeader.Parameters)));
  Assert.AreEqual('Wert', mHeader.Parameters[1].Name);
  Assert.AreEqual(')', mTokens[mHeader.CloseToken].Text);
end;

procedure TPascalSignaturesTests.ClassifiesUses;
var
  mTokens: TArray<TPascalToken>;
begin
  mTokens := TPascalLexer.Tokenize('Liste.Teile(1); F := Teile; P := @Teile; property X: Integer read Teile; Teile;');
  Assert.AreEqual(Ord(TSignatureUse.Call), Ord(TPascalSignatures.UseOf(mTokens, TPascalTest.TokenOf(mTokens, 'Teile', 1), True)));
  Assert.AreEqual(Ord(TSignatureUse.Pointer_), Ord(TPascalSignatures.UseOf(mTokens, TPascalTest.TokenOf(mTokens, 'Teile', 2),
    False)));
  Assert.AreEqual(Ord(TSignatureUse.Pointer_), Ord(TPascalSignatures.UseOf(mTokens, TPascalTest.TokenOf(mTokens, 'Teile', 3),
    False)));
  Assert.AreEqual(Ord(TSignatureUse.Accessor), Ord(TPascalSignatures.UseOf(mTokens, TPascalTest.TokenOf(mTokens, 'Teile', 4),
    False)));
  Assert.AreEqual(Ord(TSignatureUse.Call), Ord(TPascalSignatures.UseOf(mTokens, TPascalTest.TokenOf(mTokens, 'Teile', 5), False)));
  Assert.AreEqual(Ord(TSignatureUse.Pointer_), Ord(TPascalSignatures.UseOf(mTokens, TPascalTest.TokenOf(mTokens, 'Teile', 5), True)));
end;

procedure TPascalSignaturesTests.FindsParameterUses;
var
  mTokens: TArray<TPascalToken>;
begin
  mTokens := TPascalLexer.Tokenize('begin Wert := Self.Wert + &Wert; end;');
  Assert.AreEqual(2, Integer(Length(TPascalSignatures.Uses_(mTokens, 0, High(mTokens), 'Wert'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TPascalSignaturesTests);

end.
