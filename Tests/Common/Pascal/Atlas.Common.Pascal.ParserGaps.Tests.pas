unit Atlas.Common.Pascal.ParserGaps.Tests;

// Tests für die Lücken aus der Gegenprüfung mit DelphiAST
// (berichte/parser-gegenpruefung-delphiast-2026-10-23.md). Die Quellen folgen
// den Proben aus werkzeuge/delphiast/gegenpruefung/proben.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TParserGapsTests = class
  public
    /// <summary>#1137 (Probe p05): &&op_Equality ohne Diagnose, Methode im Typ und im implementation-Teil.</summary>
    [Test]
    procedure DoubleAmpersandParses;
    /// <summary>#1137: Deklarationen hinter der Stelle bleiben im Index, der Name ohne &.</summary>
    [Test]
    procedure DoubleAmpersandKeepsIndex;
    /// <summary>#1137: Gliederung nennt &op_Equality, Gehe zu führt von Rumpf und Aufruf zur Deklaration.</summary>
    [Test]
    procedure DoubleAmpersandOutlineAndResolve;
    /// <summary>#1137: Mitglied &Type wird über TFoo.&Type gefunden; Index und Gliederung nennen es Type.</summary>
    [Test]
    procedure EscapedMemberResolves;
    /// <summary>#1137: PlainName nimmt genau ein Escape-& je Namensteil, SourceName setzt es wieder.</summary>
    [Test]
    procedure PlainAndSourceNames;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.DocumentSymbols;

const
  MainFile = 'C:\P\U.pas';
  DoubleAmpersand =
    'unit p05_double_ampersand;'#10'interface'#10'type'#10'  TValue = record'#10 +
    '    class function &&op_Equality(const L, R: TValue): Boolean; static;'#10'    procedure Danach;'#10 +
    '  end;'#10'var'#10'  Letzte: Integer;'#10'implementation'#10 +
    'class function TValue.&&op_Equality(const L, R: TValue): Boolean;'#10'begin'#10'  Result := True;'#10 +
    'end;'#10'procedure TValue.Danach;'#10'begin'#10'  if TValue.&&op_Equality(Self, Self) then'#10'    Exit;'#10 +
    'end;'#10'procedure Zuletzt;'#10'begin'#10'end;'#10'end.';
  EscapedMember =
    'unit U;'#10'interface'#10'type'#10'  TFoo = class'#10'    procedure &Type;'#10'  end;'#10'implementation'#10 +
    'procedure TFoo.&Type;'#10'begin'#10'end;'#10'procedure P(F: TFoo);'#10'begin'#10'  F.&Type;'#10'end;'#10'end.';

function Find(ANode: TSyntaxNode; AKind: TSyntaxKind; const AName: string): TSyntaxNode;
var
  Index: Integer;
begin
  if (ANode.Kind = AKind) and ((AName = '') or SameText(ANode.Name, AName)) then
    Exit(ANode);
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Result := Find(ANode[Index], AKind, AName);
    if Result <> nil then
      Exit;
  end;
  Result := nil;
end;

function Diagnostics(const AText: string): string;
var
  Tree: TSyntaxTree;
  Diagnostic: TSyntaxDiagnostic;
begin
  Result := '';
  Tree := TPascalParser.Parse(AText);
  try
    for Diagnostic in Tree.Diagnostics do
      Result := Result + Format('%d:%d %s; ', [Diagnostic.StartPos.Line, Diagnostic.StartPos.Character,
        Diagnostic.Message]);
  finally
    Tree.Free;
  end;
end;

function PositionOf(const AText, AMarker: string): TTextPosition;
var
  Index, Line, LineStart, Scan: Integer;
begin
  Index := Pos(AMarker, AText);
  Line := 0;
  LineStart := 1;
  for Scan := 1 to Index - 1 do
    if AText[Scan] = #10 then
    begin
      Inc(Line);
      LineStart := Scan + 1;
    end;
  Result := TTextPosition.Create(Line, Index - LineStart);
end;

function HasSymbol(const AUnit: TUnitIndex; const AContainer, AName: string): Boolean;
var
  Symbol: TIndexSymbol;
begin
  for Symbol in AUnit.Symbols do
    if SameText(Symbol.Container, AContainer) and SameText(Symbol.Name, AName) then
      Exit(True);
  Result := False;
end;

function OutlineText(const AText: string): string;
var
  Tree: TSyntaxTree;
  Outline: TJSONArray;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Outline := TLspDocumentSymbols.BuildSymbols(Tree);
    try
      Result := Outline.ToJSON;
    finally
      Outline.Free;
    end;
  finally
    Tree.Free;
  end;
end;

{ TParserGapsTests }

procedure TParserGapsTests.DoubleAmpersandParses;
var
  Tree: TSyntaxTree;
  TypeNode, Method: TSyntaxNode;
begin
  Assert.AreEqual('', Diagnostics(DoubleAmpersand));
  Tree := TPascalParser.Parse(DoubleAmpersand);
  try
    TypeNode := Find(Tree.Root, TSyntaxKind.TypeDecl, 'TValue');
    Assert.IsNotNull(TypeNode);
    Method := Find(TypeNode, TSyntaxKind.RoutineHeader, '&&op_Equality');
    Assert.IsNotNull(Method, 'Methode im Typ');
    Assert.IsNotNull(Find(TypeNode, TSyntaxKind.RoutineHeader, 'Danach'), 'Methode dahinter');
    Assert.IsNotNull(Find(Tree.Root, TSyntaxKind.RoutineDecl, 'TValue.&&op_Equality'), 'Rumpf');
    Assert.IsNotNull(Find(Tree.Root, TSyntaxKind.RoutineDecl, 'Zuletzt'), 'Routine am Ende');
  finally
    Tree.Free;
  end;
end;

procedure TParserGapsTests.DoubleAmpersandKeepsIndex;
var
  U: TUnitIndex;
begin
  U := TIndexExtractor.ExtractText(DoubleAmpersand, MainFile, nil);
  // Der Bezeichner heißt &op_Equality; nur das erste & ist Escape.
  Assert.IsTrue(HasSymbol(U, 'TValue', '&op_Equality'));
  Assert.IsFalse(HasSymbol(U, 'TValue', '&&op_Equality'));
  Assert.IsTrue(HasSymbol(U, 'TValue', 'Danach'));
  Assert.IsTrue(HasSymbol(U, '', 'Letzte'));
  Assert.IsTrue(HasSymbol(U, '', 'Zuletzt'));
end;

procedure TParserGapsTests.DoubleAmpersandOutlineAndResolve;
var
  Tree: TSyntaxTree;
  Index: ISymbolIndex;
  Resolver: TNameResolver;
  Found: TResolvedSymbol;
  Text: string;
begin
  Text := OutlineText(DoubleAmpersand);
  Assert.IsTrue(Text.Contains('"name":"&op_Equality"'), Text);
  Assert.IsTrue(Text.Contains('"name":"TValue.&op_Equality"'), Text);
  Assert.IsTrue(Text.Contains('"name":"Zuletzt"'), Text);
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText(DoubleAmpersand, MainFile, nil));
  Resolver := TNameResolver.Create(Index);
  Tree := TPascalParser.Parse(DoubleAmpersand);
  try
    Found := Resolver.Resolve(Tree, MainFile, PositionOf(DoubleAmpersand, 'op_Equality(Self'));
    Assert.IsTrue(Found.Found, 'Aufruf');
    Assert.AreEqual('&op_Equality', Found.Name);
    Assert.AreEqual('TValue', Found.Container);
    Assert.AreEqual(4, Found.SelectionRange.StartPos.Line);
    Found := Resolver.Resolve(Tree, MainFile, PositionOf(DoubleAmpersand, 'op_Equality(const L, R: TValue): Boolean;'#10'begin'));
    Assert.IsTrue(Found.Found, 'Rumpf');
    Assert.AreEqual(4, Found.SelectionRange.StartPos.Line);
  finally
    Tree.Free;
    Resolver.Free;
  end;
  Index := nil;
end;

procedure TParserGapsTests.EscapedMemberResolves;
var
  U: TUnitIndex;
  Tree: TSyntaxTree;
  Index: ISymbolIndex;
  Resolver: TNameResolver;
  Found: TResolvedSymbol;
  Text: string;
begin
  Assert.AreEqual('', Diagnostics(EscapedMember));
  U := TIndexExtractor.ExtractText(EscapedMember, MainFile, nil);
  Assert.IsTrue(HasSymbol(U, 'TFoo', 'Type'));
  Text := OutlineText(EscapedMember);
  Assert.IsTrue(Text.Contains('"name":"Type"'), Text);
  Index := TSymbolIndex.Create;
  Index.AddUnit(U);
  Resolver := TNameResolver.Create(Index);
  Tree := TPascalParser.Parse(EscapedMember);
  try
    Found := Resolver.Resolve(Tree, MainFile, PositionOf(EscapedMember, 'Type;'#10'end;'#10'end.'));
    Assert.IsTrue(Found.Found);
    Assert.AreEqual('Type', Found.Name);
    Assert.AreEqual('TFoo', Found.Container);
    Assert.AreEqual(4, Found.SelectionRange.StartPos.Line);
    Assert.AreEqual(14, Found.SelectionRange.StartPos.Character);
  finally
    Tree.Free;
    Resolver.Free;
  end;
  Index := nil;
end;

procedure TParserGapsTests.PlainAndSourceNames;
begin
  Assert.AreEqual('begin', TPascalLexer.PlainName('&begin'));
  Assert.AreEqual('&op_Equality', TPascalLexer.PlainName('&&op_Equality'));
  Assert.AreEqual('TValue.&op_Equality', TPascalLexer.PlainName('TValue.&&op_Equality'));
  Assert.AreEqual('TFoo.Type', TPascalLexer.PlainName('TFoo.&Type'));
  Assert.AreEqual('Wert', TPascalLexer.PlainName('Wert'));
  Assert.AreEqual('&begin', TPascalLexer.SourceName('begin'));
  Assert.AreEqual('&&op_Equality', TPascalLexer.SourceName('&op_Equality'));
  Assert.AreEqual('Wert', TPascalLexer.SourceName('Wert'));
  Assert.AreEqual('', TPascalLexer.SourceName(''));
end;

initialization
  TDUnitX.RegisterTestFixture(TParserGapsTests);

end.
