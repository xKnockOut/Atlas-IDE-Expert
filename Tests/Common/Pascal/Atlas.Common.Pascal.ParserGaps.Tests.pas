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
    /// <summary>#1138 (Probe p02): () an Unit-, Klassen- und lokalen Konstanten und Variablen ohne Diagnose.
    /// </summary>
    [Test]
    procedure EmptyRecordConstant;
    /// <summary>#1138: () bleibt außerhalb einer Initialisierung ein Syntaxfehler.</summary>
    [Test]
    procedure EmptyParenOnlyAsInitializer;
    /// <summary>#1134 (Proben p01, p09): Methodenzuordnung einer Funktion, auch mit generischem Interface,
    /// meldet kein E2023; die Zuordnung steht im Baum.</summary>
    [Test]
    procedure FunctionResolutionWithoutResultType;
    /// <summary>#1134 Gegentest: function GetX; in einer Klasse meldet E2023 weiterhin.</summary>
    [Test]
    procedure FunctionWithoutResultStillReported;
    /// <summary>#1140 (Probe p03): private class threadvar ohne Diagnose, Feld und Methode im Index.</summary>
    [Test]
    procedure ClassThreadVar;
    /// <summary>#1140 (Probe p04): class operator In und weitere reservierte Operatornamen.</summary>
    [Test]
    procedure ClassOperatorKeywordNames;
    /// <summary>#1140 (Probe p06): type AnsiString(Codepage).</summary>
    [Test]
    procedure CodepageString;
    /// <summary>#1142 (Probe p07): end align 16 am Record.</summary>
    [Test]
    procedure RecordAlign;
    /// <summary>#1142 (Probe p08): Attribut an einem Feld im varianten Zweig.</summary>
    [Test]
    procedure AttributeInVariantPart;
    /// <summary>#1142 (Probe p10): Vorgabewert direkt hinter generischem Typ (IBaz&lt;string&gt;=nil).</summary>
    [Test]
    procedure GenericDefaultParameter;
    /// <summary>#1142 (Probe p11): %_0101 wie $_FF.</summary>
    [Test]
    procedure BinaryWithLeadingSeparator;
    /// <summary>#1167 (Probe p13): reserviertes Wort als Name eines benannten Arguments.</summary>
    [Test]
    procedure NamedArgumentWithKeyword;
    /// <summary>#1167 (Probe p14): Aufrufkonvention an einer anonymen Methode, die Routine dahinter bleibt.</summary>
    [Test]
    procedure AnonymousMethodWithCallingConvention;
    /// <summary>#1167 (Probe p15): Attribut an einer Inline-Variablen; Typ und Wert bleiben die Kinder.</summary>
    [Test]
    procedure InlineVariableWithAttribute;
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
  EmptyRecord =
    'unit p02_empty_record_const;'#10'interface'#10'type'#10'  TRec = record'#10'    A: Integer;'#10'  end;'#10 +
    '  TComparer = record'#10'    const Ordinal: TRec = ();'#10'  end;'#10'const'#10'  Empty: TRec = ();'#10 +
    '  EmptyGuid: TGUID = ( );'#10'var'#10'  Start: TRec = ();'#10'implementation'#10'procedure P;'#10'const'#10 +
    '  Lokal: TRec = ();'#10'begin'#10'end;'#10'end.';
  FunctionResolution =
    'unit p01_resolution_function;'#10'interface'#10'type'#10'  IFoo = interface'#10 +
    '    function GetX: Integer;'#10'  end;'#10'  TFoo = class(TInterfacedObject, IFoo)'#10 +
    '    function IFoo.GetX = MyGetX;'#10'    function MyGetX: Integer;'#10'  end;'#10 +
    'implementation'#10'function TFoo.MyGetX: Integer;'#10'begin'#10'  Result := 1;'#10'end;'#10'end.';
  GenericResolution =
    'unit p09_generic_resolution;'#10'interface'#10'uses'#10'  System.SysUtils;'#10'type'#10 +
    '  TGenerator<T> = class(TInterfacedObject, TFunc<T>)'#10'  private'#10 +
    '    function TFunc<T>.Invoke = Bind;'#10'  public'#10'    function Bind: T;'#10'  end;'#10 +
    'implementation'#10'function TGenerator<T>.Bind: T;'#10'begin'#10'  Result := Default(T);'#10'end;'#10'end.';
  ClassThreadVarSource =
    'unit p03_class_threadvar;'#10'interface'#10'type'#10'  TFoo = class'#10'  private class threadvar'#10 +
    '    FCurrent: Integer;'#10'  public'#10'    class function Current: Integer; static;'#10'  end;'#10 +
    'implementation'#10'class function TFoo.Current: Integer;'#10'begin'#10'  Result := FCurrent;'#10'end;'#10'end.';
  OperatorIn =
    'unit p04_class_operator_in;'#10'interface'#10'type'#10'  TSet = record'#10 +
    '    class operator In(const A: Integer; const B: TSet): Boolean;'#10 +
    '    class operator And(const A, B: TSet): TSet;'#10'    class operator Not(const A: TSet): TSet;'#10 +
    '    class operator Shl(const A: TSet; B: Integer): TSet;'#10'    procedure Danach;'#10'  end;'#10 +
    'implementation'#10'class operator TSet.In(const A: Integer; const B: TSet): Boolean;'#10'begin'#10 +
    '  Result := A > 0;'#10'end;'#10'procedure TSet.Danach;'#10'begin'#10'end;'#10'end.';
  CodepageSource =
    'unit p06_codepage_string;'#10'interface'#10'const'#10'  CP_WINANSI = 1252;'#10'type'#10 +
    '  WinAnsiString = type AnsiString(CP_WINANSI);'#10'  RawUnicode = type AnsiString(1200);'#10'var'#10 +
    '  W: WinAnsiString;'#10'implementation'#10'end.';
  RecordAlignSource =
    'unit p07_record_align;'#10'interface'#10'type'#10'  TMyRecord = record'#10'    Value: Integer;'#10 +
    '  end align 16;'#10'  TDanach = Integer;'#10'implementation'#10'end.';
  VariantAttribute =
    'unit p08_variant_attribute;'#10'interface'#10'type'#10'  TVariantRecord = record'#10'    case Byte of'#10 +
    '      1: ('#10'        Value: Double;'#10'        [Example]'#10'        ValueWithAttribute: Integer;'#10 +
    '        );'#10'  end;'#10'implementation'#10'end.';
  GenericDefault =
    'unit p10_generic_default_param;'#10'interface'#10'type'#10'  IBaz<T> = interface'#10'  end;'#10 +
    '  TFoo = class(TObject)'#10'    procedure Bar(Baz: IBaz<string>=nil);'#10'    procedure Danach;'#10'  end;'#10 +
    'implementation'#10'procedure TFoo.Bar(Baz: IBaz<string>=nil);'#10'begin'#10 +
    '  if A < B >= C then'#10'    Exit;'#10'end;'#10'procedure TFoo.Danach;'#10'begin'#10'end;'#10'end.';
  BinarySeparator =
    'unit p11_binary_separator;'#10'interface'#10'const'#10'  A = %_0101;'#10'  B = $_FF;'#10'  C = 1_000;'#10 +
    'implementation'#10'end.';
  NamedKeyword =
    'unit p13_named_arg_keyword;'#10'interface'#10'implementation'#10'procedure Test(Word: OleVariant);'#10 +
    'begin'#10'  Word.Documents.Open(FileName := ''a.docx'', ReadOnly := True);'#10'  Word.Foo(Type := 1);'#10 +
    'end;'#10'end.';
  AnonymousConvention =
    'unit p14_anon_callconv;'#10'interface'#10'implementation'#10'type'#10 +
    '  TPred = reference to function(const S: string): Boolean;'#10'procedure Use(P: TPred);'#10'begin'#10 +
    'end;'#10'procedure Test;'#10'begin'#10'  Use(function(const S: string): Boolean register'#10'    begin'#10 +
    '      Result := S = '''';'#10'    end);'#10'end;'#10'procedure Danach;'#10'begin'#10'end;'#10'end.';
  InlineAttribute =
    'unit p15_inline_var_attribute;'#10'interface'#10'implementation'#10'procedure Test;'#10'begin'#10 +
    '  var [Weak] Obj: IInterface := nil;'#10'  var [Unsafe, Weak] A, B: TObject;'#10'end;'#10'end.';
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

procedure TParserGapsTests.EmptyRecordConstant;
var
  Tree: TSyntaxTree;
  Decl: TSyntaxNode;
begin
  Assert.AreEqual('', Diagnostics(EmptyRecord));
  Tree := TPascalParser.Parse(EmptyRecord);
  try
    Decl := Find(Tree.Root, TSyntaxKind.ConstDecl, 'Empty');
    Assert.IsNotNull(Decl);
    Assert.IsTrue(Decl[Decl.ChildCount - 1].Kind = TSyntaxKind.ParenExpr);
    Assert.AreEqual(0, Decl[Decl.ChildCount - 1].ChildCount);
    Assert.IsNotNull(Find(Tree.Root, TSyntaxKind.ConstDecl, 'Ordinal'), 'Klassenkonstante');
    Assert.IsNotNull(Find(Tree.Root, TSyntaxKind.ConstDecl, 'Lokal'), 'lokale Konstante');
    Assert.IsNotNull(Find(Tree.Root, TSyntaxKind.RoutineDecl, 'P'), 'Routine dahinter');
  finally
    Tree.Free;
  end;
end;

procedure TParserGapsTests.EmptyParenOnlyAsInitializer;
begin
  Assert.AreNotEqual('', Diagnostics('unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'var'#10 +
    '  R: TRec;'#10'begin'#10'  R := ();'#10'end;'#10'end.'));
  Assert.AreNotEqual('', Diagnostics('unit U;'#10'interface'#10'const'#10'  C = ();'#10'implementation'#10'end.'));
end;

procedure TParserGapsTests.FunctionResolutionWithoutResultType;
var
  Tree: TSyntaxTree;
  Header: TSyntaxNode;
begin
  Assert.AreEqual('', Diagnostics(FunctionResolution));
  Assert.AreEqual('', Diagnostics(GenericResolution));
  Tree := TPascalParser.Parse(GenericResolution);
  try
    Header := Find(Find(Tree.Root, TSyntaxKind.TypeDecl, 'TGenerator'), TSyntaxKind.RoutineHeader, '');
    Assert.IsNotNull(Header);
    Assert.IsTrue(Header.IsMethodResolution, Header.Name);
    Assert.AreEqual('Bind', Header.ResolutionTarget);
    Assert.IsNotNull(Find(Tree.Root, TSyntaxKind.RoutineHeader, 'Bind'), 'Methode dahinter');
  finally
    Tree.Free;
  end;
end;

procedure TParserGapsTests.FunctionWithoutResultStillReported;
begin
  Assert.Contains(Diagnostics('unit U;'#10'interface'#10'type'#10'  TFoo = class'#10'    function GetX;'#10 +
    '  end;'#10'implementation'#10'end.'), 'E2023');
end;

procedure TParserGapsTests.ClassThreadVar;
var
  U: TUnitIndex;
  Symbol: TIndexSymbol;
  Directive: string;
  ClassField: Boolean;
begin
  Assert.AreEqual('', Diagnostics(ClassThreadVarSource));
  U := TIndexExtractor.ExtractText(ClassThreadVarSource, MainFile, nil);
  Assert.IsTrue(HasSymbol(U, 'TFoo', 'Current'));
  // Das Feld ist ein Klassenfeld wie bei class var.
  ClassField := False;
  for Symbol in U.Symbols do
    if SameText(Symbol.Container, 'TFoo') and SameText(Symbol.Name, 'FCurrent') then
      for Directive in Symbol.Directives do
        ClassField := ClassField or SameText(Directive, 'class');
  Assert.IsTrue(ClassField);
end;

procedure TParserGapsTests.ClassOperatorKeywordNames;
var
  Tree: TSyntaxTree;
  TypeNode: TSyntaxNode;
begin
  Assert.AreEqual('', Diagnostics(OperatorIn));
  Tree := TPascalParser.Parse(OperatorIn);
  try
    TypeNode := Find(Tree.Root, TSyntaxKind.TypeDecl, 'TSet');
    Assert.IsNotNull(Find(TypeNode, TSyntaxKind.RoutineHeader, 'In'), 'In');
    Assert.IsNotNull(Find(TypeNode, TSyntaxKind.RoutineHeader, 'And'), 'And');
    Assert.IsNotNull(Find(TypeNode, TSyntaxKind.RoutineHeader, 'Not'), 'Not');
    Assert.IsNotNull(Find(TypeNode, TSyntaxKind.RoutineHeader, 'Shl'), 'Shl');
    Assert.IsNotNull(Find(TypeNode, TSyntaxKind.RoutineHeader, 'Danach'), 'Danach');
    Assert.IsNotNull(Find(Tree.Root, TSyntaxKind.RoutineDecl, 'TSet.In'), 'Rumpf');
  finally
    Tree.Free;
  end;
  Assert.IsTrue(HasSymbol(TIndexExtractor.ExtractText(OperatorIn, MainFile, nil), 'TSet', 'In'));
end;

procedure TParserGapsTests.CodepageString;
var
  Tree: TSyntaxTree;
begin
  Assert.AreEqual('', Diagnostics(CodepageSource));
  Tree := TPascalParser.Parse(CodepageSource);
  try
    Assert.IsNotNull(Find(Tree.Root, TSyntaxKind.TypeDecl, 'WinAnsiString'));
    Assert.IsNotNull(Find(Tree.Root, TSyntaxKind.TypeDecl, 'RawUnicode'));
    Assert.IsNotNull(Find(Tree.Root, TSyntaxKind.VarDecl, 'W'));
  finally
    Tree.Free;
  end;
end;

procedure TParserGapsTests.RecordAlign;
var
  Tree: TSyntaxTree;
begin
  Assert.AreEqual('', Diagnostics(RecordAlignSource));
  Tree := TPascalParser.Parse(RecordAlignSource);
  try
    Assert.IsNotNull(Find(Tree.Root, TSyntaxKind.RecordType, ''));
    Assert.IsNull(Find(Tree.Root, TSyntaxKind.TypeReference, 'align'), 'align ist kein Typ');
    Assert.IsNotNull(Find(Tree.Root, TSyntaxKind.TypeDecl, 'TDanach'));
  finally
    Tree.Free;
  end;
end;

procedure TParserGapsTests.AttributeInVariantPart;
var
  U: TUnitIndex;
begin
  Assert.AreEqual('', Diagnostics(VariantAttribute));
  U := TIndexExtractor.ExtractText(VariantAttribute, MainFile, nil);
  Assert.IsTrue(HasSymbol(U, 'TVariantRecord', 'Value'));
  Assert.IsTrue(HasSymbol(U, 'TVariantRecord', 'ValueWithAttribute'));
end;

procedure TParserGapsTests.GenericDefaultParameter;
var
  Tree: TSyntaxTree;
  Parameter: TSyntaxNode;
begin
  // Der Ausdruck A < B >= C im Rumpf bleibt ein Vergleich, nur die Typen der Parameter teilen >=.
  Assert.AreEqual('', Diagnostics(GenericDefault));
  Tree := TPascalParser.Parse(GenericDefault);
  try
    Parameter := Find(Find(Tree.Root, TSyntaxKind.TypeDecl, 'TFoo'), TSyntaxKind.Parameter, 'Baz');
    Assert.IsNotNull(Parameter);
    Assert.IsNotNull(Find(Parameter, TSyntaxKind.GenericArgs, ''), 'IBaz<string>');
    Assert.IsNotNull(Find(Tree.Root, TSyntaxKind.RoutineDecl, 'TFoo.Danach'), 'Routine dahinter');
  finally
    Tree.Free;
  end;
end;

procedure TParserGapsTests.BinaryWithLeadingSeparator;
begin
  Assert.AreEqual('', Diagnostics(BinarySeparator));
end;

procedure TParserGapsTests.NamedArgumentWithKeyword;
begin
  Assert.AreEqual('', Diagnostics(NamedKeyword));
end;

procedure TParserGapsTests.AnonymousMethodWithCallingConvention;
var
  mTree: TSyntaxTree;
begin
  Assert.AreEqual('', Diagnostics(AnonymousConvention));
  mTree := TPascalParser.Parse(AnonymousConvention);
  try
    Assert.IsNotNull(Find(mTree.Root, TSyntaxKind.AnonymousMethod, 'function'));
    Assert.IsNotNull(Find(mTree.Root, TSyntaxKind.RoutineDecl, 'Danach'), 'Routine dahinter');
  finally
    mTree.Free;
  end;
end;

procedure TParserGapsTests.InlineVariableWithAttribute;
var
  mTree: TSyntaxTree;
  mVariable: TSyntaxNode;
begin
  Assert.AreEqual('', Diagnostics(InlineAttribute));
  mTree := TPascalParser.Parse(InlineAttribute);
  try
    mVariable := Find(mTree.Root, TSyntaxKind.InlineVar, 'Obj');
    Assert.IsNotNull(mVariable);
    Assert.AreEqual(2, mVariable.ChildCount);
    Assert.AreEqual(Ord(TSyntaxKind.TypeReference), Ord(mVariable[0].Kind));
    Assert.IsNotNull(Find(mTree.Root, TSyntaxKind.InlineVar, 'A,B'));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TParserGapsTests);

end.
