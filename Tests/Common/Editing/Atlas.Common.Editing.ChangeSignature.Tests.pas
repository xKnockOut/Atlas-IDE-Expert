unit Atlas.Common.Editing.ChangeSignature.Tests;

// Tests für die Textbausteine von „Signatur ändern“ (#100).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TChangeSignatureTests = class
  public
    [Test]
    procedure ParsesParameters;
    [Test]
    procedure ReadsDeclarationHeader;
    [Test]
    procedure ReadsBodyHeaderWithoutParameters;
    [Test]
    procedure ReadsProcedureType;
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
    procedure ClassifiesUses;
    [Test]
    procedure FindsParameterUses;
    [Test]
    procedure BuildsForwardCallAndDirectives;
    [Test]
    procedure AppliesEdits;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ChangeSignature;

function TokenOf(const ATokens: TArray<TPascalToken>; const AText: string; AOccurrence: Integer): Integer;
var
  mIndex, mCount: Integer;
begin
  mCount := 0;
  for mIndex := 0 to High(ATokens) do
  begin
    if ATokens[mIndex].Text = AText then
    begin
      Inc(mCount);
      if mCount = AOccurrence then
      begin
        Exit(mIndex);
      end;
    end;
  end;
  Result := -1;
end;

function CallText(const AText, AName: string; AOccurrence: Integer; const AOld: TArray<TSignatureParameter>;
  const AChanges: TArray<TParameterChange>): string;
var
  mTokens: TArray<TPascalToken>;
  mEdit: TTextEdit;
begin
  mTokens := TPascalLexer.Tokenize(AText);
  if TChangeSignature.CallEdit(AText, mTokens, TokenOf(mTokens, AName, AOccurrence),
    TCallChange.Create(AOld, AChanges, nil), mEdit) then
  begin
    Result := TChangeSignature.ApplyEdits(AText, [mEdit]);
  end
  else
  begin
    Result := AText;
  end;
end;

procedure TChangeSignatureTests.ParsesParameters;
var
  mParameters: TArray<TSignatureParameter>;
begin
  mParameters := TChangeSignature.ParseParameters('const A, B: Integer; var Buffer; [ref] const C: TList<string>; ' +
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

procedure TChangeSignatureTests.ReadsDeclarationHeader;
const
  cText = '  class function Teile(A, B: Integer; const C: string = ''-''): Double; virtual; abstract;';
var
  mTokens: TArray<TPascalToken>;
  mHeader: TSignatureHeader;
begin
  mTokens := TPascalLexer.Tokenize(cText);
  Assert.IsTrue(TChangeSignature.ReadHeader(cText, mTokens, TokenOf(mTokens, 'Teile', 1), mHeader));
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
  Assert.IsFalse(TChangeSignature.ReadHeader('X := Teile(1, 2);', TPascalLexer.Tokenize('X := Teile(1, 2);'), 2,
    mHeader));
end;

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
    Assert.IsTrue(TChangeSignature.ReadHeader(mSource, mTokens, TokenOf(mTokens, 'Lauf', 1), mHeader));
    Assert.AreEqual('TAussen.TInnen.Lauf', mHeader.QualifiedName);
    Assert.AreEqual(-1, mHeader.OpenToken);
    Assert.AreEqual('end', mTokens[TChangeSignature.BodyEnd(mTree, mHeader) - 1].Text);
    // Ohne Klammern fügt HeaderEdit die Liste hinter dem Namen ein.
    Assert.AreEqual(mTokens[mHeader.NameToken].EndPos.Character,
      TChangeSignature.HeaderEdit(mTokens, mHeader, '(A: Integer)').Range.StartPos.Character);
  finally
    mTree.Free;
  end;
end;

procedure TChangeSignatureTests.ReadsProcedureType;
const
  cText = '  TWertEvent = procedure(Sender: TObject; Wert: Integer) of object;';
var
  mTokens: TArray<TPascalToken>;
  mHeader: TSignatureHeader;
begin
  mTokens := TPascalLexer.Tokenize(cText);
  Assert.IsTrue(TChangeSignature.ReadProcedureType(cText, mTokens, TokenOf(mTokens, 'TWertEvent', 1), mHeader));
  Assert.AreEqual(2, Integer(Length(mHeader.Parameters)));
  Assert.AreEqual('Wert', mHeader.Parameters[1].Name);
  Assert.AreEqual(')', mTokens[mHeader.CloseToken].Text);
end;

procedure TChangeSignatureTests.BuildsParameterLists;
var
  mOld: TArray<TSignatureParameter>;
  mChanges: TArray<TParameterChange>;
begin
  mOld := TChangeSignature.ParseParameters('A, B: Integer; const C: string = ''x''');
  mChanges := [TParameterChange.Kept(1, 'B'), TParameterChange.Kept(0, 'A'),
    TParameterChange.Added('D', 'Boolean', 'const', 'False'), TParameterChange.Kept(2, 'C')];
  Assert.AreEqual('(B, A: Integer; const D: Boolean; const C: string = ''x'')',
    TChangeSignature.ParameterList(TChangeSignature.NewParameters(mOld, mChanges, ['A', 'B', 'C'], True), True));
  // Rumpf ohne Standardwerte; neue Parameter nie mit Standardwert.
  Assert.AreEqual('(B, A: Integer; const D: Boolean; const C: string)',
    TChangeSignature.ParameterList(TChangeSignature.NewParameters(mOld, mChanges, ['A', 'B', 'C'], False), False));
  Assert.AreEqual('', TChangeSignature.ParameterList(nil, True));
end;

procedure TChangeSignatureTests.RenamesOnlyChangedNames;
var
  mOwn: TArray<TSignatureParameter>;
  mResult_: TArray<TSignatureParameter>;
begin
  // Die Überschreibung heißt den Parameter anders; ohne Umbenennung bleibt ihr Name.
  mOwn := TChangeSignature.ParseParameters('AWert: Integer; ATeil: Integer');
  mResult_ := TChangeSignature.NewParameters(mOwn, [TParameterChange.Kept(0, 'Wert'), TParameterChange.Kept(1, 'Neu')],
    ['Wert', 'Teil'], True);
  Assert.AreEqual('AWert', mResult_[0].Name);
  Assert.AreEqual('Neu', mResult_[1].Name);
end;

procedure TChangeSignatureTests.ValidatesChanges;
var
  mOld: TArray<TSignatureParameter>;
begin
  mOld := TChangeSignature.ParseParameters('A: Integer; B: Integer = 0');
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
  mOld := TChangeSignature.ParseParameters('A, B: Integer');
  Assert.AreEqual('X := Teile(B1 + 2, Foo(1, 2));', CallText('X := Teile(Foo(1, 2), B1 + 2);', 'Teile', 1, mOld,
    [TParameterChange.Kept(1, 'B'), TParameterChange.Kept(0, 'A')]));
  Assert.AreEqual('Teile(1, 2, nil);', CallText('Teile(1, 2);', 'Teile', 1, mOld,
    [TParameterChange.Kept(0, 'A'), TParameterChange.Kept(1, 'B'), TParameterChange.Added('C', 'TObject', '', 'nil')]));
  Assert.AreEqual('Teile(2);', CallText('Teile(1, 2);', 'Teile', 1, mOld, [TParameterChange.Kept(1, 'B')]));
  // Ohne Argumente verschwinden die Klammern; ohne Klammern kommen sie dazu.
  Assert.AreEqual('Lauf;', CallText('Lauf(1);', 'Lauf', 1, TChangeSignature.ParseParameters('A: Integer'), nil));
  Assert.AreEqual('Lauf(True);', CallText('Lauf;', 'Lauf', 1, nil, [TParameterChange.Added('X', 'Boolean', '',
    'True')]));
end;

procedure TChangeSignatureTests.KeepsOmittedDefaults;
var
  mOld: TArray<TSignatureParameter>;
begin
  mOld := TChangeSignature.ParseParameters('A: Integer; B: Integer = 7; C: Integer = 8');
  // Ausgelassene Argumente am Ende bleiben weg; mitten in der Liste kommt der Standardwert.
  Assert.AreEqual('Foo(1);', CallText('Foo(1);', 'Foo', 1, mOld, [TParameterChange.Kept(0, 'A'),
    TParameterChange.Kept(2, 'C'), TParameterChange.Kept(1, 'B')]));
  Assert.AreEqual('Foo(1, 8, 2);', CallText('Foo(1, 2);', 'Foo', 1, mOld, [TParameterChange.Kept(0, 'A'),
    TParameterChange.Kept(2, 'C'), TParameterChange.Kept(1, 'B')]));
end;

procedure TChangeSignatureTests.ClassifiesUses;
var
  mTokens: TArray<TPascalToken>;
begin
  mTokens := TPascalLexer.Tokenize('Liste.Teile(1); F := Teile; P := @Teile; property X: Integer read Teile; Teile;');
  Assert.AreEqual(Ord(TSignatureUse.Call), Ord(TChangeSignature.UseOf(mTokens, TokenOf(mTokens, 'Teile', 1), True)));
  Assert.AreEqual(Ord(TSignatureUse.Pointer_), Ord(TChangeSignature.UseOf(mTokens, TokenOf(mTokens, 'Teile', 2),
    False)));
  Assert.AreEqual(Ord(TSignatureUse.Pointer_), Ord(TChangeSignature.UseOf(mTokens, TokenOf(mTokens, 'Teile', 3),
    False)));
  Assert.AreEqual(Ord(TSignatureUse.Accessor), Ord(TChangeSignature.UseOf(mTokens, TokenOf(mTokens, 'Teile', 4),
    False)));
  Assert.AreEqual(Ord(TSignatureUse.Call), Ord(TChangeSignature.UseOf(mTokens, TokenOf(mTokens, 'Teile', 5), False)));
  Assert.AreEqual(Ord(TSignatureUse.Pointer_), Ord(TChangeSignature.UseOf(mTokens, TokenOf(mTokens, 'Teile', 5), True)));
end;

procedure TChangeSignatureTests.FindsParameterUses;
var
  mTokens: TArray<TPascalToken>;
begin
  mTokens := TPascalLexer.Tokenize('begin Wert := Self.Wert + &Wert; end;');
  Assert.AreEqual(2, Integer(Length(TChangeSignature.Uses_(mTokens, 0, High(mTokens), 'Wert'))));
end;

procedure TChangeSignatureTests.BuildsForwardCallAndDirectives;
const
  cText = 'function TFoo.Teile(A, B: Integer): Integer; overload; virtual; stdcall;';
var
  mTokens: TArray<TPascalToken>;
  mHeader: TSignatureHeader;
begin
  mTokens := TPascalLexer.Tokenize(cText);
  Assert.IsTrue(TChangeSignature.ReadHeader(cText, mTokens, TokenOf(mTokens, 'Teile', 1), mHeader));
  Assert.AreEqual('Result := Teile(B, A, 0);', TChangeSignature.ForwardCall(mHeader, mHeader.Parameters,
    [TParameterChange.Kept(1, 'B'), TParameterChange.Kept(0, 'A'), TParameterChange.Added('C', 'Integer', '', '0')]));
  Assert.AreEqual(' overload; stdcall;', TChangeSignature.OverloadDirectives(mHeader, False));
  Assert.AreEqual(' overload; stdcall; virtual;', TChangeSignature.OverloadDirectives(mHeader, True));
  Assert.AreEqual('function TFoo.Teile(A, B: Integer): Integer;', TChangeSignature.HeaderText(mHeader, 'TFoo.Teile',
    mHeader.Parameters, False));
end;

procedure TChangeSignatureTests.AppliesEdits;
begin
  Assert.AreEqual('ab XY cd', TChangeSignature.ApplyEdits('ab cd', [
    TTextEdit.Create(TTextRange.Create(0, 2, 0, 2), ' XY'),
    TTextEdit.Create(TTextRange.Create(0, 0, 0, 0), '')]));
  Assert.AreEqual('a'#10'Z', TChangeSignature.ApplyEdits('a'#10'b', [TTextEdit.Create(TTextRange.Create(1, 0, 1, 1),
    'Z')]));
end;

end.
