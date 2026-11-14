unit Atlas.Common.Pascal.Parser.Cursor.Tests;

// Tests der Klassenkette des Parsers (Pascal.Parser.Cursor, .Expressions,
// .Declarations, .Types): Reihenfolge der Schichten, Korrekturen der
// Diagnosen und die Teile, die beim Aufteilen der Parse-Methoden entstanden
// sind, über TPascalParser.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TParserChainTests = class
  public
    [Test]
    procedure LayersInheritInOrder;
    [Test]
    procedure FixReplacesOneRange;
    [Test]
    procedure IncludeAsValueOnlyAfterValueStart;
    [Test]
    procedure OpenStringOffersClosingQuote;
    [Test]
    procedure OpenCommentHidesLaterDiagnostics;
    [Test]
    procedure SelectorsNestInReadingOrder;
    [Test]
    procedure RelationalOperatorsWithTwoWords;
    [Test]
    procedure GenericParamsSkipConstraints;
    [Test]
    procedure ModifiersOnlyBeforeNames;
    [Test]
    procedure VariantLabelsKeepText;
    [Test]
    procedure MissingEndEndsMemberList;
    [Test]
    procedure CaseRangesAndExceptionHandlers;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.Parser.Cursor,
  Atlas.Common.Pascal.Parser.Expressions,
  Atlas.Common.Pascal.Parser.Declarations,
  Atlas.Common.Pascal.Parser.Types;

/// <summary>Art und Name von ANode mit allen Kindern, z. B. "Call:F(Identifier:F,Literal:1)".</summary>
function Shape(ANode: TSyntaxNode): string;
var
  mIndex: Integer;
begin
  Result := SyntaxKindName(ANode.Kind);
  if ANode.Name <> '' then
  begin
    Result := Result + ':' + ANode.Name;
  end;
  if ANode.ChildCount = 0 then
  begin
    Exit;
  end;
  Result := Result + '(';
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if mIndex > 0 then
    begin
      Result := Result + ',';
    end;
    Result := Result + Shape(ANode[mIndex]);
  end;
  Result := Result + ')';
end;

/// <summary>Erster Knoten der Art AKind unter ARoot (Tiefensuche), sonst nil.</summary>
function First(ARoot: TSyntaxNode; AKind: TSyntaxKind): TSyntaxNode;
begin
  Result := ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      if ANode.Kind = AKind then
      begin
        Result := TSyntaxSearchStep.Found;
      end
      else
      begin
        Result := TSyntaxSearchStep.Descend;
      end;
    end);
end;

/// <summary>Codes aller Diagnosen von ATree, durch Komma getrennt.</summary>
function Codes(ATree: TSyntaxTree): string;
var
  mDiagnostic: TSyntaxDiagnostic;
begin
  Result := '';
  for mDiagnostic in ATree.Diagnostics do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + mDiagnostic.Code;
  end;
end;

function ProgramText(const ABody: string): string;
begin
  Result := 'program P;' + sLineBreak + 'begin' + sLineBreak + ABody + sLineBreak + 'end.';
end;

procedure TParserChainTests.LayersInheritInOrder;
begin
  Assert.IsTrue(TParserBase.InheritsFrom(TParserCursor));
  Assert.IsTrue(TExpressionParser.InheritsFrom(TParserBase));
  Assert.IsTrue(TDeclarationParser.InheritsFrom(TExpressionParser));
  Assert.IsTrue(TTypeParser.InheritsFrom(TDeclarationParser));
end;

procedure TParserChainTests.FixReplacesOneRange;
var
  mFix: TParserFix;
begin
  mFix := TParserFix.Create('Ersetzen', TTextPosition.Create(1, 2), TTextPosition.Create(1, 4), 'xy', True);
  Assert.AreEqual('Ersetzen', mFix.Title);
  Assert.AreEqual(1, Integer(Length(mFix.Edits)));
  Assert.AreEqual(2, mFix.Edits[0].Range.StartPos.Character);
  Assert.AreEqual(4, mFix.Edits[0].Range.EndPos.Character);
  Assert.AreEqual('xy', mFix.Edits[0].NewText);
  Assert.IsTrue(mFix.Safe);
end;

procedure TParserChainTests.IncludeAsValueOnlyAfterValueStart;
var
  mToken: TPascalToken;
begin
  mToken := Default(TPascalToken);
  mToken.Kind := TPascalTokenKind.Symbol;
  mToken.Text := '=';
  Assert.IsTrue(IncludeAsValue(mToken));
  mToken.Text := ';';
  Assert.IsFalse(IncludeAsValue(mToken));
  mToken.Kind := TPascalTokenKind.Identifier;
  mToken.Text := 'V';
  Assert.IsFalse(IncludeAsValue(mToken));
end;

procedure TParserChainTests.OpenStringOffersClosingQuote;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(ProgramText('S := ''abc;'));
  try
    Assert.AreEqual('E2052', Codes(mTree));
    Assert.AreEqual('String schließen', mTree.Diagnostics[0].FixTitle);
    Assert.AreEqual('''', mTree.Diagnostics[0].FixEdits[0].NewText);
  finally
    mTree.Free;
  end;
end;

procedure TParserChainTests.OpenCommentHidesLaterDiagnostics;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse('unit U;' + sLineBreak + 'interface' + sLineBreak + '{ offen' + sLineBreak +
    'const = ;');
  try
    Assert.AreEqual('E2057', Codes(mTree));
    Assert.AreEqual('}', mTree.Diagnostics[0].FixEdits[0].NewText);
    Assert.AreEqual(7, mTree.Diagnostics[0].FixEdits[0].Range.StartPos.Character);
  finally
    mTree.Free;
  end;
end;

procedure TParserChainTests.SelectorsNestInReadingOrder;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(ProgramText('X := inherited A.B(1)[2]^;'));
  try
    Assert.AreEqual('', Codes(mTree));
    Assert.AreEqual('AssignStatement:X(Identifier:X,Dereference(IndexAccess:B(Call:B(MemberAccess:B(' +
      'InheritedExpr:A),Literal:1),Literal:2)))', Shape(First(mTree.Root, TSyntaxKind.AssignStatement)));
  finally
    mTree.Free;
  end;
end;

procedure TParserChainTests.RelationalOperatorsWithTwoWords;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(ProgramText('B := X is not TFoo;'));
  try
    Assert.AreEqual('is not', First(mTree.Root, TSyntaxKind.BinaryExpr).Name);
  finally
    mTree.Free;
  end;
  mTree := TPascalParser.Parse(ProgramText('B := Y not in [1, 2..3];'));
  try
    Assert.AreEqual('BinaryExpr:not in(Identifier:Y,SetConstructor(Literal:1,RangeExpr:..(Literal:2,Literal:3)))',
      Shape(First(mTree.Root, TSyntaxKind.BinaryExpr)));
  finally
    mTree.Free;
  end;
end;

procedure TParserChainTests.GenericParamsSkipConstraints;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse('unit U;' + sLineBreak + 'interface' + sLineBreak + 'type' + sLineBreak +
    '  TFoo<T: class, constructor; U: IBar<T>> = class end;' + sLineBreak + 'implementation' + sLineBreak + 'end.');
  try
    Assert.AreEqual('', Codes(mTree));
    Assert.AreEqual('GenericParams(Identifier:T,Identifier:U)', Shape(First(mTree.Root, TSyntaxKind.GenericParams)));
  finally
    mTree.Free;
  end;
end;

procedure TParserChainTests.ModifiersOnlyBeforeNames;
var
  mTree: TSyntaxTree;
  mParams: TSyntaxNode;
begin
  mTree := TPascalParser.Parse('unit U;' + sLineBreak + 'interface' + sLineBreak +
    'procedure P(const A: Integer; out: Integer; constref C: string; var D);' + sLineBreak + 'implementation' +
    sLineBreak + 'end.');
  try
    Assert.AreEqual('', Codes(mTree));
    mParams := First(mTree.Root, TSyntaxKind.Parameters);
    Assert.AreEqual(4, mParams.ChildCount);
    Assert.AreEqual<TParameterModifier>(TParameterModifier.ConstParam, mParams[0].Modifier);
    Assert.AreEqual('out', mParams[1].Name);
    Assert.AreEqual<TParameterModifier>(TParameterModifier.None, mParams[1].Modifier);
    Assert.AreEqual<TParameterModifier>(TParameterModifier.ConstRefParam, mParams[2].Modifier);
    Assert.AreEqual<TParameterModifier>(TParameterModifier.VarParam, mParams[3].Modifier);
  finally
    mTree.Free;
  end;
end;

procedure TParserChainTests.VariantLabelsKeepText;
var
  mTree: TSyntaxTree;
  mVariant: TSyntaxNode;
begin
  mTree := TPascalParser.Parse('unit U;' + sLineBreak + 'interface' + sLineBreak + 'type' + sLineBreak +
    '  R = record case Kind: Integer of 0, 1: (A: Integer); 2..3: (B: string); end;' + sLineBreak +
    'implementation' + sLineBreak + 'end.');
  try
    Assert.AreEqual('', Codes(mTree));
    mVariant := First(mTree.Root, TSyntaxKind.CaseItem).Parent;
    Assert.AreEqual('Kind', mVariant.Name);
    Assert.AreEqual('0, 1', mVariant[1].Name);
    Assert.AreEqual('2..3', mVariant[2].Name);
  finally
    mTree.Free;
  end;
end;

procedure TParserChainTests.MissingEndEndsMemberList;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse('unit U;' + sLineBreak + 'interface' + sLineBreak + 'type' + sLineBreak +
    '  T = class' + sLineBreak + '    procedure P;' + sLineBreak + 'implementation' + sLineBreak + 'end.');
  try
    Assert.IsTrue(Length(mTree.Diagnostics) > 0);
    Assert.StartsWith('''end'' erwartet', mTree.Diagnostics[0].Message);
    Assert.IsNotNull(First(mTree.Root, TSyntaxKind.ImplementationSection));
  finally
    mTree.Free;
  end;
end;

procedure TParserChainTests.CaseRangesAndExceptionHandlers;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(ProgramText('try case X of 1..2, 5: Y; else Z; end; except on E: EFoo do W; else V; end;'));
  try
    Assert.AreEqual('', Codes(mTree));
    Assert.AreEqual('CaseItem(RangeExpr:..(Literal:1,Literal:2),Literal:5,CallStatement:Y(Identifier:Y))',
      Shape(First(mTree.Root, TSyntaxKind.CaseItem)));
    Assert.AreEqual('ExceptionHandler:E(TypeReference:EFoo,CallStatement:W(Identifier:W))',
      Shape(First(mTree.Root, TSyntaxKind.ExceptionHandler)));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TParserChainTests);

end.
