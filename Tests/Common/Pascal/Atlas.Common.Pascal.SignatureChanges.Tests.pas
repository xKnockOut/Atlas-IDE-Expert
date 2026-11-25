unit Atlas.Common.Pascal.SignatureChanges.Tests;

// Tests für die Textbausteine von „Signatur ändern“ (#100).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TChangeSignatureTests = class
  public
    [Test]
    procedure ReadsBodyHeaderWithoutParameters;
    [Test]
    procedure BuildsParameterLists;
    [Test]
    procedure RenamesOnlyChangedNames;
    [Test]
    procedure ValidatesChanges;
    [Test]
    procedure RewritesCalls;
    [Test]
    procedure KeepsOmittedDefaults;
    [Test]
    procedure BuildsForwardCallAndDirectives;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.Signatures,
  Atlas.Common.Pascal.TestSupport,
  Atlas.Common.Documents.TextChanges,
  Atlas.Common.Pascal.SignatureChanges;

function CallText(const AText, AName: string; AOccurrence: Integer; const AOld: TArray<TSignatureParameter>;
  const AChanges: TArray<TParameterChange>): string;
var
  mTokens: TArray<TPascalToken>;
  mEdit: TTextEdit;
begin
  mTokens := TPascalLexer.Tokenize(AText);
  if TChangeSignature.CallEdit(AText, mTokens, TPascalTest.TokenOf(mTokens, AName, AOccurrence),
    TCallChange.Create(AOld, AChanges, nil), mEdit) then
  begin
    Result := TTextChanges.Apply(AText, [mEdit]);
  end
  else
  begin
    Result := AText;
  end;
end;

{ TChangeSignatureTests }

procedure TChangeSignatureTests.ReadsBodyHeaderWithoutParameters;
const
  cText = 'procedure TAussen.TInnen.Lauf;'#10'begin'#10'end;';
var
  mTokens: TArray<TPascalToken>;
  mHeader: TSignatureHeader;
  mTree: TSyntaxTree;
  mSource: string;
begin
  mSource := 'unit U;'#10'interface'#10'implementation'#10 + cText + #10'end.';
  mTree := TPascalParser.Parse(mSource);
  try
    mTokens := mTree.Tokens;
    Assert.IsTrue(TPascalSignatures.ReadHeader(mSource, mTokens, TPascalTest.TokenOf(mTokens, 'Lauf', 1), mHeader));
    Assert.AreEqual('TAussen.TInnen.Lauf', mHeader.QualifiedName);
    Assert.AreEqual(-1, mHeader.OpenToken);
    Assert.AreEqual('end', mTokens[TPascalSignatures.BodyEnd(mTree, mHeader) - 1].Text);
    // Ohne Klammern fügt HeaderEdit die Liste hinter dem Namen ein.
    Assert.AreEqual(mTokens[mHeader.NameToken].EndPos.Character,
      TChangeSignature.HeaderEdit(mTokens, mHeader, '(A: Integer)').Range.StartPos.Character);
  finally
    mTree.Free;
  end;
end;

procedure TChangeSignatureTests.BuildsParameterLists;
var
  mOld: TArray<TSignatureParameter>;
  mChanges: TArray<TParameterChange>;
begin
  mOld := TPascalSignatures.ParseParameters('A, B: Integer; const C: string = ''x''');
  mChanges := [TParameterChange.Kept(1, 'B'), TParameterChange.Kept(0, 'A'),
    TParameterChange.Added('D', 'Boolean', 'const', 'False'), TParameterChange.Kept(2, 'C')];
  Assert.AreEqual('(B, A: Integer; const D: Boolean; const C: string = ''x'')',
    TPascalSignatures.ParameterList(TChangeSignature.NewParameters(mOld, mChanges, ['A', 'B', 'C'], True), True));
  // Rumpf ohne Standardwerte; neue Parameter nie mit Standardwert.
  Assert.AreEqual('(B, A: Integer; const D: Boolean; const C: string)',
    TPascalSignatures.ParameterList(TChangeSignature.NewParameters(mOld, mChanges, ['A', 'B', 'C'], False), False));
  Assert.AreEqual('', TPascalSignatures.ParameterList(nil, True));
end;

procedure TChangeSignatureTests.RenamesOnlyChangedNames;
var
  mOwn: TArray<TSignatureParameter>;
  mResult_: TArray<TSignatureParameter>;
begin
  // Die Überschreibung heißt den Parameter anders; ohne Umbenennung bleibt ihr Name.
  mOwn := TPascalSignatures.ParseParameters('AWert: Integer; ATeil: Integer');
  mResult_ := TChangeSignature.NewParameters(mOwn, [TParameterChange.Kept(0, 'Wert'), TParameterChange.Kept(1, 'Neu')],
    ['Wert', 'Teil'], True);
  Assert.AreEqual('AWert', mResult_[0].Name);
  Assert.AreEqual('Neu', mResult_[1].Name);
end;

procedure TChangeSignatureTests.ValidatesChanges;
var
  mOld: TArray<TSignatureParameter>;
begin
  mOld := TPascalSignatures.ParseParameters('A: Integer; B: Integer = 0');
  Assert.AreEqual('', TChangeSignature.Validate(mOld, [TParameterChange.Added('N', 'Integer', '', '1'),
    TParameterChange.Kept(0, 'A'), TParameterChange.Kept(1, 'B')]));
  Assert.Contains(TChangeSignature.Validate(mOld, [TParameterChange.Kept(0, 'A'), TParameterChange.Kept(1, 'B'),
    TParameterChange.Added('N', 'Integer', '', '1')]), 'Standardwert');
  Assert.Contains(TChangeSignature.Validate(mOld, [TParameterChange.Added('N', 'Integer', '', '')]), 'Wert');
  Assert.Contains(TChangeSignature.Validate(mOld, [TParameterChange.Added('N', '', '', '1')]), 'Typ');
  Assert.Contains(TChangeSignature.Validate(mOld, [TParameterChange.Kept(0, 'A'), TParameterChange.Kept(0, 'X')]),
    'zweimal');
  Assert.Contains(TChangeSignature.Validate(mOld, [TParameterChange.Kept(0, 'begin')]), 'gültig');
end;

procedure TChangeSignatureTests.RewritesCalls;
var
  mOld: TArray<TSignatureParameter>;
begin
  mOld := TPascalSignatures.ParseParameters('A, B: Integer');
  Assert.AreEqual('X := Teile(B1 + 2, Foo(1, 2));', CallText('X := Teile(Foo(1, 2), B1 + 2);', 'Teile', 1, mOld,
    [TParameterChange.Kept(1, 'B'), TParameterChange.Kept(0, 'A')]));
  Assert.AreEqual('Teile(1, 2, nil);', CallText('Teile(1, 2);', 'Teile', 1, mOld,
    [TParameterChange.Kept(0, 'A'), TParameterChange.Kept(1, 'B'), TParameterChange.Added('C', 'TObject', '', 'nil')]));
  Assert.AreEqual('Teile(2);', CallText('Teile(1, 2);', 'Teile', 1, mOld, [TParameterChange.Kept(1, 'B')]));
  // Ohne Argumente verschwinden die Klammern; ohne Klammern kommen sie dazu.
  Assert.AreEqual('Lauf;', CallText('Lauf(1);', 'Lauf', 1, TPascalSignatures.ParseParameters('A: Integer'), nil));
  Assert.AreEqual('Lauf(True);', CallText('Lauf;', 'Lauf', 1, nil, [TParameterChange.Added('X', 'Boolean', '',
    'True')]));
end;

procedure TChangeSignatureTests.KeepsOmittedDefaults;
var
  mOld: TArray<TSignatureParameter>;
begin
  mOld := TPascalSignatures.ParseParameters('A: Integer; B: Integer = 7; C: Integer = 8');
  // Ausgelassene Argumente am Ende bleiben weg; mitten in der Liste kommt der Standardwert.
  Assert.AreEqual('Foo(1);', CallText('Foo(1);', 'Foo', 1, mOld, [TParameterChange.Kept(0, 'A'),
    TParameterChange.Kept(2, 'C'), TParameterChange.Kept(1, 'B')]));
  Assert.AreEqual('Foo(1, 8, 2);', CallText('Foo(1, 2);', 'Foo', 1, mOld, [TParameterChange.Kept(0, 'A'),
    TParameterChange.Kept(2, 'C'), TParameterChange.Kept(1, 'B')]));
end;

procedure TChangeSignatureTests.BuildsForwardCallAndDirectives;
const
  cText = 'function TFoo.Teile(A, B: Integer): Integer; overload; virtual; stdcall;';
var
  mTokens: TArray<TPascalToken>;
  mHeader: TSignatureHeader;
begin
  mTokens := TPascalLexer.Tokenize(cText);
  Assert.IsTrue(TPascalSignatures.ReadHeader(cText, mTokens, TPascalTest.TokenOf(mTokens, 'Teile', 1), mHeader));
  Assert.AreEqual('Result := Teile(B, A, 0);', TChangeSignature.ForwardCall(mHeader, mHeader.Parameters,
    [TParameterChange.Kept(1, 'B'), TParameterChange.Kept(0, 'A'), TParameterChange.Added('C', 'Integer', '', '0')]));
  Assert.AreEqual(' overload; stdcall;', TPascalSignatures.OverloadDirectives(mHeader, False));
  Assert.AreEqual(' overload; stdcall; virtual;', TPascalSignatures.OverloadDirectives(mHeader, True));
  Assert.AreEqual('function TFoo.Teile(A, B: Integer): Integer;', TPascalSignatures.HeaderText(mHeader, 'TFoo.Teile',
    mHeader.Parameters, False));
end;

end.
