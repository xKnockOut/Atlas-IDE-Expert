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
  Index, Count: Integer;
begin
  Count := 0;
  for Index := 0 to High(ATokens) do
    if ATokens[Index].Text = AText then
    begin
      Inc(Count);
      if Count = AOccurrence then
        Exit(Index);
    end;
  Result := -1;
end;

function CallText(const AText, AName: string; AOccurrence: Integer; const AOld: TArray<TSignatureParameter>;
  const AChanges: TArray<TParameterChange>): string;
var
  Tokens: TArray<TPascalToken>;
  Edit: TTextEdit;
begin
  Tokens := TPascalLexer.Tokenize(AText);
  if TChangeSignature.CallEdit(AText, Tokens, TokenOf(Tokens, AName, AOccurrence), AOld, AChanges, nil, Edit) then
    Result := TChangeSignature.ApplyEdits(AText, [Edit])
  else
    Result := AText;
end;

procedure TChangeSignatureTests.ParsesParameters;
var
  Parameters: TArray<TSignatureParameter>;
begin
  Parameters := TChangeSignature.ParseParameters('const A, B: Integer; var Buffer; [ref] const C: TList<string>; ' +
    'D: string = ''x;y''; out E: array of Byte');
  Assert.AreEqual(6, Integer(Length(Parameters)));
  Assert.AreEqual('const', Parameters[0].Modifier);
  Assert.AreEqual('B', Parameters[1].Name);
  Assert.AreEqual('Integer', Parameters[1].TypeName);
  Assert.AreEqual('var', Parameters[2].Modifier);
  Assert.AreEqual('', Parameters[2].TypeName);
  Assert.AreEqual('[ref] const', Parameters[3].Modifier);
  Assert.AreEqual('TList<string>', Parameters[3].TypeName);
  Assert.AreEqual('''x;y''', Parameters[4].DefaultValue);
  Assert.AreEqual('array of Byte', Parameters[5].TypeName);
  Assert.AreEqual('out', Parameters[5].Modifier);
end;

procedure TChangeSignatureTests.ReadsDeclarationHeader;
const
  Text = '  class function Teile(A, B: Integer; const C: string = ''-''): Double; virtual; abstract;';
var
  Tokens: TArray<TPascalToken>;
  Header: TSignatureHeader;
begin
  Tokens := TPascalLexer.Tokenize(Text);
  Assert.IsTrue(TChangeSignature.ReadHeader(Text, Tokens, TokenOf(Tokens, 'Teile', 1), Header));
  Assert.IsTrue(Header.IsClass);
  Assert.IsTrue(Header.IsFunction);
  Assert.AreEqual('Double', Header.ResultType);
  Assert.AreEqual(3, Integer(Length(Header.Parameters)));
  Assert.AreEqual('''-''', Header.Parameters[2].DefaultValue);
  Assert.AreEqual(2, Integer(Length(Header.Directives)));
  Assert.IsTrue(Header.HasDirective('abstract'));
  Assert.AreEqual('class', Tokens[Header.StartToken].Text);
  Assert.AreEqual(';', Tokens[Header.EndToken].Text);
  Assert.IsTrue(Header.LastToken > Header.EndToken);
  // Ein Aufruf ist kein Kopf.
  Assert.IsFalse(TChangeSignature.ReadHeader('X := Teile(1, 2);', TPascalLexer.Tokenize('X := Teile(1, 2);'), 2,
    Header));
end;

procedure TChangeSignatureTests.ReadsBodyHeaderWithoutParameters;
const
  Text = 'procedure TAussen.TInnen.Lauf;'#10'begin'#10'end;';
var
  Tokens: TArray<TPascalToken>;
  Header: TSignatureHeader;
  Tree: TSyntaxTree;
  Source: string;
begin
  Source := 'unit U;'#10'interface'#10'implementation'#10 + Text + #10'end.';
  Tree := TPascalParser.Parse(Source);
  try
    Tokens := Tree.Tokens;
    Assert.IsTrue(TChangeSignature.ReadHeader(Source, Tokens, TokenOf(Tokens, 'Lauf', 1), Header));
    Assert.AreEqual('TAussen.TInnen.Lauf', Header.QualifiedName);
    Assert.AreEqual(-1, Header.OpenToken);
    Assert.AreEqual('end', Tokens[TChangeSignature.BodyEnd(Tree, Header) - 1].Text);
    // Ohne Klammern fügt HeaderEdit die Liste hinter dem Namen ein.
    Assert.AreEqual(Tokens[Header.NameToken].EndPos.Character,
      TChangeSignature.HeaderEdit(Tokens, Header, '(A: Integer)').Range.StartPos.Character);
  finally
    Tree.Free;
  end;
end;

procedure TChangeSignatureTests.ReadsProcedureType;
const
  Text = '  TWertEvent = procedure(Sender: TObject; Wert: Integer) of object;';
var
  Tokens: TArray<TPascalToken>;
  Header: TSignatureHeader;
begin
  Tokens := TPascalLexer.Tokenize(Text);
  Assert.IsTrue(TChangeSignature.ReadProcedureType(Text, Tokens, TokenOf(Tokens, 'TWertEvent', 1), Header));
  Assert.AreEqual(2, Integer(Length(Header.Parameters)));
  Assert.AreEqual('Wert', Header.Parameters[1].Name);
  Assert.AreEqual(')', Tokens[Header.CloseToken].Text);
end;

procedure TChangeSignatureTests.BuildsParameterLists;
var
  Old: TArray<TSignatureParameter>;
  Changes: TArray<TParameterChange>;
begin
  Old := TChangeSignature.ParseParameters('A, B: Integer; const C: string = ''x''');
  Changes := [TParameterChange.Kept(1, 'B'), TParameterChange.Kept(0, 'A'),
    TParameterChange.Added('D', 'Boolean', 'const', 'False'), TParameterChange.Kept(2, 'C')];
  Assert.AreEqual('(B, A: Integer; const D: Boolean; const C: string = ''x'')',
    TChangeSignature.ParameterList(TChangeSignature.NewParameters(Old, Changes, ['A', 'B', 'C'], True), True));
  // Rumpf ohne Standardwerte; neue Parameter nie mit Standardwert.
  Assert.AreEqual('(B, A: Integer; const D: Boolean; const C: string)',
    TChangeSignature.ParameterList(TChangeSignature.NewParameters(Old, Changes, ['A', 'B', 'C'], False), False));
  Assert.AreEqual('', TChangeSignature.ParameterList(nil, True));
end;

procedure TChangeSignatureTests.RenamesOnlyChangedNames;
var
  Own: TArray<TSignatureParameter>;
  Result_: TArray<TSignatureParameter>;
begin
  // Die Überschreibung heißt den Parameter anders; ohne Umbenennung bleibt ihr Name.
  Own := TChangeSignature.ParseParameters('AWert: Integer; ATeil: Integer');
  Result_ := TChangeSignature.NewParameters(Own, [TParameterChange.Kept(0, 'Wert'), TParameterChange.Kept(1, 'Neu')],
    ['Wert', 'Teil'], True);
  Assert.AreEqual('AWert', Result_[0].Name);
  Assert.AreEqual('Neu', Result_[1].Name);
end;

procedure TChangeSignatureTests.ValidatesChanges;
var
  Old: TArray<TSignatureParameter>;
begin
  Old := TChangeSignature.ParseParameters('A: Integer; B: Integer = 0');
  Assert.AreEqual('', TChangeSignature.Validate(Old, [TParameterChange.Added('N', 'Integer', '', '1'),
    TParameterChange.Kept(0, 'A'), TParameterChange.Kept(1, 'B')]));
  Assert.Contains(TChangeSignature.Validate(Old, [TParameterChange.Kept(0, 'A'), TParameterChange.Kept(1, 'B'),
    TParameterChange.Added('N', 'Integer', '', '1')]), 'Standardwert');
  Assert.Contains(TChangeSignature.Validate(Old, [TParameterChange.Added('N', 'Integer', '', '')]), 'Wert');
  Assert.Contains(TChangeSignature.Validate(Old, [TParameterChange.Added('N', '', '', '1')]), 'Typ');
  Assert.Contains(TChangeSignature.Validate(Old, [TParameterChange.Kept(0, 'A'), TParameterChange.Kept(0, 'X')]),
    'zweimal');
  Assert.Contains(TChangeSignature.Validate(Old, [TParameterChange.Kept(0, 'begin')]), 'gültig');
end;

procedure TChangeSignatureTests.RewritesCalls;
var
  Old: TArray<TSignatureParameter>;
begin
  Old := TChangeSignature.ParseParameters('A, B: Integer');
  Assert.AreEqual('X := Teile(B1 + 2, Foo(1, 2));', CallText('X := Teile(Foo(1, 2), B1 + 2);', 'Teile', 1, Old,
    [TParameterChange.Kept(1, 'B'), TParameterChange.Kept(0, 'A')]));
  Assert.AreEqual('Teile(1, 2, nil);', CallText('Teile(1, 2);', 'Teile', 1, Old,
    [TParameterChange.Kept(0, 'A'), TParameterChange.Kept(1, 'B'), TParameterChange.Added('C', 'TObject', '', 'nil')]));
  Assert.AreEqual('Teile(2);', CallText('Teile(1, 2);', 'Teile', 1, Old, [TParameterChange.Kept(1, 'B')]));
  // Ohne Argumente verschwinden die Klammern; ohne Klammern kommen sie dazu.
  Assert.AreEqual('Lauf;', CallText('Lauf(1);', 'Lauf', 1, TChangeSignature.ParseParameters('A: Integer'), nil));
  Assert.AreEqual('Lauf(True);', CallText('Lauf;', 'Lauf', 1, nil, [TParameterChange.Added('X', 'Boolean', '',
    'True')]));
end;

procedure TChangeSignatureTests.KeepsOmittedDefaults;
var
  Old: TArray<TSignatureParameter>;
begin
  Old := TChangeSignature.ParseParameters('A: Integer; B: Integer = 7; C: Integer = 8');
  // Ausgelassene Argumente am Ende bleiben weg; mitten in der Liste kommt der Standardwert.
  Assert.AreEqual('Foo(1);', CallText('Foo(1);', 'Foo', 1, Old, [TParameterChange.Kept(0, 'A'),
    TParameterChange.Kept(2, 'C'), TParameterChange.Kept(1, 'B')]));
  Assert.AreEqual('Foo(1, 8, 2);', CallText('Foo(1, 2);', 'Foo', 1, Old, [TParameterChange.Kept(0, 'A'),
    TParameterChange.Kept(2, 'C'), TParameterChange.Kept(1, 'B')]));
end;

procedure TChangeSignatureTests.ClassifiesUses;
var
  Tokens: TArray<TPascalToken>;
begin
  Tokens := TPascalLexer.Tokenize('Liste.Teile(1); F := Teile; P := @Teile; property X: Integer read Teile; Teile;');
  Assert.AreEqual(Ord(TSignatureUse.Call), Ord(TChangeSignature.UseOf(Tokens, TokenOf(Tokens, 'Teile', 1), True)));
  Assert.AreEqual(Ord(TSignatureUse.Pointer_), Ord(TChangeSignature.UseOf(Tokens, TokenOf(Tokens, 'Teile', 2),
    False)));
  Assert.AreEqual(Ord(TSignatureUse.Pointer_), Ord(TChangeSignature.UseOf(Tokens, TokenOf(Tokens, 'Teile', 3),
    False)));
  Assert.AreEqual(Ord(TSignatureUse.Accessor), Ord(TChangeSignature.UseOf(Tokens, TokenOf(Tokens, 'Teile', 4),
    False)));
  Assert.AreEqual(Ord(TSignatureUse.Call), Ord(TChangeSignature.UseOf(Tokens, TokenOf(Tokens, 'Teile', 5), False)));
  Assert.AreEqual(Ord(TSignatureUse.Pointer_), Ord(TChangeSignature.UseOf(Tokens, TokenOf(Tokens, 'Teile', 5), True)));
end;

procedure TChangeSignatureTests.FindsParameterUses;
var
  Tokens: TArray<TPascalToken>;
begin
  Tokens := TPascalLexer.Tokenize('begin Wert := Self.Wert + &Wert; end;');
  Assert.AreEqual(2, Integer(Length(TChangeSignature.Uses_(Tokens, 0, High(Tokens), 'Wert'))));
end;

procedure TChangeSignatureTests.BuildsForwardCallAndDirectives;
const
  Text = 'function TFoo.Teile(A, B: Integer): Integer; overload; virtual; stdcall;';
var
  Tokens: TArray<TPascalToken>;
  Header: TSignatureHeader;
begin
  Tokens := TPascalLexer.Tokenize(Text);
  Assert.IsTrue(TChangeSignature.ReadHeader(Text, Tokens, TokenOf(Tokens, 'Teile', 1), Header));
  Assert.AreEqual('Result := Teile(B, A, 0);', TChangeSignature.ForwardCall(Header, Header.Parameters,
    [TParameterChange.Kept(1, 'B'), TParameterChange.Kept(0, 'A'), TParameterChange.Added('C', 'Integer', '', '0')]));
  Assert.AreEqual(' overload; stdcall;', TChangeSignature.OverloadDirectives(Header, False));
  Assert.AreEqual(' overload; stdcall; virtual;', TChangeSignature.OverloadDirectives(Header, True));
  Assert.AreEqual('function TFoo.Teile(A, B: Integer): Integer;', TChangeSignature.HeaderText(Header, 'TFoo.Teile',
    Header.Parameters, False));
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
