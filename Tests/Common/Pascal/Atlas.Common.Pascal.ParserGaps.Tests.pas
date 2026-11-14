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
    /// <summary>#1137 (Probe p05): &amp;&amp;op_Equality ohne Diagnose, Methode im Typ und im
    /// implementation-Teil.</summary>
    /// <summary>Hinweiswort vor dem Startwert (System.NoErrMsg).</summary>
    [Test]
    procedure HintBeforeInitialValue;
    [Test]
    procedure DoubleAmpersandParses;
    /// <summary>#1137: Deklarationen hinter der Stelle bleiben im Index, der Name ohne &amp;.</summary>
    [Test]
    procedure DoubleAmpersandKeepsIndex;
    /// <summary>#1137: Gliederung nennt &amp;op_Equality, Gehe zu führt von Rumpf und Aufruf zur Deklaration.</summary>
    [Test]
    procedure DoubleAmpersandOutlineAndResolve;
    /// <summary>#1137: Mitglied &amp;Type wird über TFoo.&amp;Type gefunden; Index und Gliederung nennen es
    /// Type.</summary>
    [Test]
    procedure EscapedMemberResolves;
    /// <summary>#1137: PlainName nimmt genau ein Escape-&amp; je Namensteil, SourceName setzt es wieder.</summary>
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
  System.Generics.Collections,
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
  cMainFile = 'C:\P\U.pas';
  cDoubleAmpersand =
    'unit p05_double_ampersand;'#10'interface'#10'type'#10'  TValue = record'#10 +
    '    class function &&op_Equality(const L, R: TValue): Boolean; static;'#10'    procedure Danach;'#10 +
    '  end;'#10'var'#10'  Letzte: Integer;'#10'implementation'#10 +
    'class function TValue.&&op_Equality(const L, R: TValue): Boolean;'#10'begin'#10'  Result := True;'#10 +
    'end;'#10'procedure TValue.Danach;'#10'begin'#10'  if TValue.&&op_Equality(Self, Self) then'#10'    Exit;'#10 +
    'end;'#10'procedure Zuletzt;'#10'begin'#10'end;'#10'end.';
  cEmptyRecord =
    'unit p02_empty_record_const;'#10'interface'#10'type'#10'  TRec = record'#10'    A: Integer;'#10'  end;'#10 +
    '  TComparer = record'#10'    const Ordinal: TRec = ();'#10'  end;'#10'const'#10'  Empty: TRec = ();'#10 +
    '  EmptyGuid: TGUID = ( );'#10'var'#10'  Start: TRec = ();'#10'implementation'#10'procedure P;'#10'const'#10 +
    '  Lokal: TRec = ();'#10'begin'#10'end;'#10'end.';
  cFunctionResolution =
    'unit p01_resolution_function;'#10'interface'#10'type'#10'  IFoo = interface'#10 +
    '    function GetX: Integer;'#10'  end;'#10'  TFoo = class(TInterfacedObject, IFoo)'#10 +
    '    function IFoo.GetX = MyGetX;'#10'    function MyGetX: Integer;'#10'  end;'#10 +
    'implementation'#10'function TFoo.MyGetX: Integer;'#10'begin'#10'  Result := 1;'#10'end;'#10'end.';
  cGenericResolution =
    'unit p09_generic_resolution;'#10'interface'#10'uses'#10'  System.SysUtils;'#10'type'#10 +
    '  TGenerator<T> = class(TInterfacedObject, TFunc<T>)'#10'  private'#10 +
    '    function TFunc<T>.Invoke = Bind;'#10'  public'#10'    function Bind: T;'#10'  end;'#10 +
    'implementation'#10'function TGenerator<T>.Bind: T;'#10'begin'#10'  Result := Default(T);'#10'end;'#10'end.';
  cClassThreadVarSource =
    'unit p03_class_threadvar;'#10'interface'#10'type'#10'  TFoo = class'#10'  private class threadvar'#10 +
    '    FCurrent: Integer;'#10'  public'#10'    class function Current: Integer; static;'#10'  end;'#10 +
    'implementation'#10'class function TFoo.Current: Integer;'#10'begin'#10'  Result := FCurrent;'#10'end;'#10'end.';
  cOperatorIn =
    'unit p04_class_operator_in;'#10'interface'#10'type'#10'  TSet = record'#10 +
    '    class operator In(const A: Integer; const B: TSet): Boolean;'#10 +
    '    class operator And(const A, B: TSet): TSet;'#10'    class operator Not(const A: TSet): TSet;'#10 +
    '    class operator Shl(const A: TSet; B: Integer): TSet;'#10'    procedure Danach;'#10'  end;'#10 +
    'implementation'#10'class operator TSet.In(const A: Integer; const B: TSet): Boolean;'#10'begin'#10 +
    '  Result := A > 0;'#10'end;'#10'procedure TSet.Danach;'#10'begin'#10'end;'#10'end.';
  cCodepageSource =
    'unit p06_codepage_string;'#10'interface'#10'const'#10'  CP_WINANSI = 1252;'#10'type'#10 +
    '  WinAnsiString = type AnsiString(CP_WINANSI);'#10'  RawUnicode = type AnsiString(1200);'#10'var'#10 +
    '  W: WinAnsiString;'#10'implementation'#10'end.';
  cRecordAlignSource =
    'unit p07_record_align;'#10'interface'#10'type'#10'  TMyRecord = record'#10'    Value: Integer;'#10 +
    '  end align 16;'#10'  TDanach = Integer;'#10'implementation'#10'end.';
  cVariantAttribute =
    'unit p08_variant_attribute;'#10'interface'#10'type'#10'  TVariantRecord = record'#10'    case Byte of'#10 +
    '      1: ('#10'        Value: Double;'#10'        [Example]'#10'        ValueWithAttribute: Integer;'#10 +
    '        );'#10'  end;'#10'implementation'#10'end.';
  cGenericDefault =
    'unit p10_generic_default_param;'#10'interface'#10'type'#10'  IBaz<T> = interface'#10'  end;'#10 +
    '  TFoo = class(TObject)'#10'    procedure Bar(Baz: IBaz<string>=nil);'#10'    procedure Danach;'#10'  end;'#10 +
    'implementation'#10'procedure TFoo.Bar(Baz: IBaz<string>=nil);'#10'begin'#10 +
    '  if A < B >= C then'#10'    Exit;'#10'end;'#10'procedure TFoo.Danach;'#10'begin'#10'end;'#10'end.';
  cBinarySeparator =
    'unit p11_binary_separator;'#10'interface'#10'const'#10'  A = %_0101;'#10'  B = $_FF;'#10'  C = 1_000;'#10 +
    'implementation'#10'end.';
  cNamedKeyword =
    'unit p13_named_arg_keyword;'#10'interface'#10'implementation'#10'procedure Test(Word: OleVariant);'#10 +
    'begin'#10'  Word.Documents.Open(FileName := ''a.docx'', ReadOnly := True);'#10'  Word.Foo(Type := 1);'#10 +
    'end;'#10'end.';
  cAnonymousConvention =
    'unit p14_anon_callconv;'#10'interface'#10'implementation'#10'type'#10 +
    '  TPred = reference to function(const S: string): Boolean;'#10'procedure Use(P: TPred);'#10'begin'#10 +
    'end;'#10'procedure Test;'#10'begin'#10'  Use(function(const S: string): Boolean register'#10'    begin'#10 +
    '      Result := S = '''';'#10'    end);'#10'end;'#10'procedure Danach;'#10'begin'#10'end;'#10'end.';
  cInlineAttribute =
    'unit p15_inline_var_attribute;'#10'interface'#10'implementation'#10'procedure Test;'#10'begin'#10 +
    '  var [Weak] Obj: IInterface := nil;'#10'  var [Unsafe, Weak] A, B: TObject;'#10'end;'#10'end.';
  cEscapedMember =
    'unit U;'#10'interface'#10'type'#10'  TFoo = class'#10'    procedure &Type;'#10'  end;'#10'implementation'#10 +
    'procedure TFoo.&Type;'#10'begin'#10'end;'#10'procedure P(F: TFoo);'#10'begin'#10'  F.&Type;'#10'end;'#10'end.';

function Find(ANode: TSyntaxNode; AKind: TSyntaxKind; const AName: string): TSyntaxNode;
var
  mIndex: Integer;
begin
  if (ANode.Kind = AKind) and ((AName = '') or SameText(ANode.Name, AName)) then
  begin
    Exit(ANode);
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    Result := Find(ANode[mIndex], AKind, AName);
    if Result <> nil then
    begin
      Exit;
    end;
  end;
  Result := nil;
end;

function Diagnostics(const AText: string): string;
var
  mTree: TSyntaxTree;
  mDiagnostic: TSyntaxDiagnostic;
begin
  Result := '';
  mTree := TPascalParser.Parse(AText);
  try
    for mDiagnostic in mTree.Diagnostics do
    begin
      Result := Result + Format('%d:%d %s; ', [mDiagnostic.StartPos.Line, mDiagnostic.StartPos.Character,
        mDiagnostic.Message]);
    end;
  finally
    mTree.Free;
  end;
end;

function PositionOf(const AText, AMarker: string): TTextPosition;
var
  mIndex, mLine, mLineStart, mScan: Integer;
begin
  mIndex := Pos(AMarker, AText);
  mLine := 0;
  mLineStart := 1;
  for mScan := 1 to mIndex - 1 do
  begin
    if AText[mScan] = #10 then
    begin
      Inc(mLine);
      mLineStart := mScan + 1;
    end;
  end;
  Result := TTextPosition.Create(mLine, mIndex - mLineStart);
end;

function HasSymbol(const AUnit: TUnitIndex; const AContainer, AName: string): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in AUnit.Symbols do
  begin
    if SameText(mSymbol.Container, AContainer) and SameText(mSymbol.Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function OutlineText(const AText: string): string;
var
  mTree: TSyntaxTree;
  mOutline: TJSONArray;
begin
  mTree := TPascalParser.Parse(AText);
  try
    mOutline := TLspDocumentSymbols.BuildSymbols(mTree);
    try
      Result := mOutline.ToJSON;
    finally
      mOutline.Free;
    end;
  finally
    mTree.Free;
  end;
end;

{ TParserGapsTests }

procedure TParserGapsTests.HintBeforeInitialValue;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse('unit U;'#10'interface'#10'var'#10'  NoErrMsg: Boolean platform = False;'#10 +
    '  Weiter: Integer;'#10'implementation'#10'end.');
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)));
  finally
    mTree.Free;
  end;
end;

procedure TParserGapsTests.DoubleAmpersandParses;
var
  mTree: TSyntaxTree;
  mTypeNode, mMethod: TSyntaxNode;
begin
  Assert.AreEqual('', Diagnostics(cDoubleAmpersand));
  mTree := TPascalParser.Parse(cDoubleAmpersand);
  try
    mTypeNode := Find(mTree.Root, TSyntaxKind.TypeDecl, 'TValue');
    Assert.IsNotNull(mTypeNode);
    mMethod := Find(mTypeNode, TSyntaxKind.RoutineHeader, '&&op_Equality');
    Assert.IsNotNull(mMethod, 'Methode im Typ');
    Assert.IsNotNull(Find(mTypeNode, TSyntaxKind.RoutineHeader, 'Danach'), 'Methode dahinter');
    Assert.IsNotNull(Find(mTree.Root, TSyntaxKind.RoutineDecl, 'TValue.&&op_Equality'), 'Rumpf');
    Assert.IsNotNull(Find(mTree.Root, TSyntaxKind.RoutineDecl, 'Zuletzt'), 'Routine am Ende');
  finally
    mTree.Free;
  end;
end;

procedure TParserGapsTests.DoubleAmpersandKeepsIndex;
var
  U: TUnitIndex;
begin
  U := TIndexExtractor.ExtractText(cDoubleAmpersand, cMainFile, nil);
  // Der Bezeichner heißt &op_Equality; nur das erste & ist Escape.
  Assert.IsTrue(HasSymbol(U, 'TValue', '&op_Equality'));
  Assert.IsFalse(HasSymbol(U, 'TValue', '&&op_Equality'));
  Assert.IsTrue(HasSymbol(U, 'TValue', 'Danach'));
  Assert.IsTrue(HasSymbol(U, '', 'Letzte'));
  Assert.IsTrue(HasSymbol(U, '', 'Zuletzt'));
end;

procedure TParserGapsTests.DoubleAmpersandOutlineAndResolve;
var
  mTree: TSyntaxTree;
  mIndex: ISymbolIndex;
  mResolver: TNameResolver;
  mFound: TResolvedSymbol;
  mText: string;
begin
  mText := OutlineText(cDoubleAmpersand);
  Assert.IsTrue(mText.Contains('"name":"&op_Equality"'), mText);
  Assert.IsTrue(mText.Contains('"name":"TValue.&op_Equality"'), mText);
  Assert.IsTrue(mText.Contains('"name":"Zuletzt"'), mText);
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cDoubleAmpersand, cMainFile, nil));
  mResolver := TNameResolver.Create(mIndex);
  mTree := TPascalParser.Parse(cDoubleAmpersand);
  try
    mFound := mResolver.Resolve(mTree, cMainFile, PositionOf(cDoubleAmpersand, 'op_Equality(Self'));
    Assert.IsTrue(mFound.Found, 'Aufruf');
    Assert.AreEqual('&op_Equality', mFound.Name);
    Assert.AreEqual('TValue', mFound.Container);
    Assert.AreEqual(4, mFound.SelectionRange.StartPos.Line);
    mFound := mResolver.Resolve(mTree, cMainFile, PositionOf(cDoubleAmpersand, 'op_Equality(const L, R: TValue): Boolean;'#10'begin'));
    Assert.IsTrue(mFound.Found, 'Rumpf');
    Assert.AreEqual(4, mFound.SelectionRange.StartPos.Line);
  finally
    mTree.Free;
    mResolver.Free;
  end;
  mIndex := nil;
end;

procedure TParserGapsTests.EscapedMemberResolves;
var
  U: TUnitIndex;
  mTree: TSyntaxTree;
  mIndex: ISymbolIndex;
  mResolver: TNameResolver;
  mFound: TResolvedSymbol;
  mText: string;
begin
  Assert.AreEqual('', Diagnostics(cEscapedMember));
  U := TIndexExtractor.ExtractText(cEscapedMember, cMainFile, nil);
  Assert.IsTrue(HasSymbol(U, 'TFoo', 'Type'));
  mText := OutlineText(cEscapedMember);
  Assert.IsTrue(mText.Contains('"name":"Type"'), mText);
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(U);
  mResolver := TNameResolver.Create(mIndex);
  mTree := TPascalParser.Parse(cEscapedMember);
  try
    mFound := mResolver.Resolve(mTree, cMainFile, PositionOf(cEscapedMember, 'Type;'#10'end;'#10'end.'));
    Assert.IsTrue(mFound.Found);
    Assert.AreEqual('Type', mFound.Name);
    Assert.AreEqual('TFoo', mFound.Container);
    Assert.AreEqual(4, mFound.SelectionRange.StartPos.Line);
    Assert.AreEqual(14, mFound.SelectionRange.StartPos.Character);
  finally
    mTree.Free;
    mResolver.Free;
  end;
  mIndex := nil;
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
  mTree: TSyntaxTree;
  mDecl: TSyntaxNode;
begin
  Assert.AreEqual('', Diagnostics(cEmptyRecord));
  mTree := TPascalParser.Parse(cEmptyRecord);
  try
    mDecl := Find(mTree.Root, TSyntaxKind.ConstDecl, 'Empty');
    Assert.IsNotNull(mDecl);
    Assert.AreEqual<TSyntaxKind>(TSyntaxKind.ParenExpr, mDecl[mDecl.ChildCount - 1].Kind);
    Assert.AreEqual(0, mDecl[mDecl.ChildCount - 1].ChildCount);
    Assert.IsNotNull(Find(mTree.Root, TSyntaxKind.ConstDecl, 'Ordinal'), 'Klassenkonstante');
    Assert.IsNotNull(Find(mTree.Root, TSyntaxKind.ConstDecl, 'Lokal'), 'lokale Konstante');
    Assert.IsNotNull(Find(mTree.Root, TSyntaxKind.RoutineDecl, 'P'), 'Routine dahinter');
  finally
    mTree.Free;
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
  mTree: TSyntaxTree;
  mHeader: TSyntaxNode;
begin
  Assert.AreEqual('', Diagnostics(cFunctionResolution));
  Assert.AreEqual('', Diagnostics(cGenericResolution));
  mTree := TPascalParser.Parse(cGenericResolution);
  try
    mHeader := Find(Find(mTree.Root, TSyntaxKind.TypeDecl, 'TGenerator'), TSyntaxKind.RoutineHeader, '');
    Assert.IsNotNull(mHeader);
    Assert.IsTrue(mHeader.IsMethodResolution, mHeader.Name);
    Assert.AreEqual('Bind', mHeader.ResolutionTarget);
    Assert.IsNotNull(Find(mTree.Root, TSyntaxKind.RoutineHeader, 'Bind'), 'Methode dahinter');
  finally
    mTree.Free;
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
  mSymbol: TIndexSymbol;
  mDirective: string;
  mClassField: Boolean;
begin
  Assert.AreEqual('', Diagnostics(cClassThreadVarSource));
  U := TIndexExtractor.ExtractText(cClassThreadVarSource, cMainFile, nil);
  Assert.IsTrue(HasSymbol(U, 'TFoo', 'Current'));
  // Das Feld ist ein Klassenfeld wie bei class var.
  mClassField := False;
  for mSymbol in U.Symbols do
  begin
    if SameText(mSymbol.Container, 'TFoo') and SameText(mSymbol.Name, 'FCurrent') then
    begin
      for mDirective in mSymbol.Directives do
      begin
        mClassField := mClassField or SameText(mDirective, 'class');
      end;
    end;
  end;
  Assert.IsTrue(mClassField);
end;

procedure TParserGapsTests.ClassOperatorKeywordNames;
var
  mTree: TSyntaxTree;
  mTypeNode: TSyntaxNode;
begin
  Assert.AreEqual('', Diagnostics(cOperatorIn));
  mTree := TPascalParser.Parse(cOperatorIn);
  try
    mTypeNode := Find(mTree.Root, TSyntaxKind.TypeDecl, 'TSet');
    Assert.IsNotNull(Find(mTypeNode, TSyntaxKind.RoutineHeader, 'In'), 'In');
    Assert.IsNotNull(Find(mTypeNode, TSyntaxKind.RoutineHeader, 'And'), 'And');
    Assert.IsNotNull(Find(mTypeNode, TSyntaxKind.RoutineHeader, 'Not'), 'Not');
    Assert.IsNotNull(Find(mTypeNode, TSyntaxKind.RoutineHeader, 'Shl'), 'Shl');
    Assert.IsNotNull(Find(mTypeNode, TSyntaxKind.RoutineHeader, 'Danach'), 'Danach');
    Assert.IsNotNull(Find(mTree.Root, TSyntaxKind.RoutineDecl, 'TSet.In'), 'Rumpf');
  finally
    mTree.Free;
  end;
  Assert.IsTrue(HasSymbol(TIndexExtractor.ExtractText(cOperatorIn, cMainFile, nil), 'TSet', 'In'));
end;

procedure TParserGapsTests.CodepageString;
var
  mTree: TSyntaxTree;
begin
  Assert.AreEqual('', Diagnostics(cCodepageSource));
  mTree := TPascalParser.Parse(cCodepageSource);
  try
    Assert.IsNotNull(Find(mTree.Root, TSyntaxKind.TypeDecl, 'WinAnsiString'));
    Assert.IsNotNull(Find(mTree.Root, TSyntaxKind.TypeDecl, 'RawUnicode'));
    Assert.IsNotNull(Find(mTree.Root, TSyntaxKind.VarDecl, 'W'));
  finally
    mTree.Free;
  end;
end;

procedure TParserGapsTests.RecordAlign;
var
  mTree: TSyntaxTree;
begin
  Assert.AreEqual('', Diagnostics(cRecordAlignSource));
  mTree := TPascalParser.Parse(cRecordAlignSource);
  try
    Assert.IsNotNull(Find(mTree.Root, TSyntaxKind.RecordType, ''));
    Assert.IsNull(Find(mTree.Root, TSyntaxKind.TypeReference, 'align'), 'align ist kein Typ');
    Assert.IsNotNull(Find(mTree.Root, TSyntaxKind.TypeDecl, 'TDanach'));
  finally
    mTree.Free;
  end;
end;

procedure TParserGapsTests.AttributeInVariantPart;
var
  U: TUnitIndex;
begin
  Assert.AreEqual('', Diagnostics(cVariantAttribute));
  U := TIndexExtractor.ExtractText(cVariantAttribute, cMainFile, nil);
  Assert.IsTrue(HasSymbol(U, 'TVariantRecord', 'Value'));
  Assert.IsTrue(HasSymbol(U, 'TVariantRecord', 'ValueWithAttribute'));
end;

procedure TParserGapsTests.GenericDefaultParameter;
var
  mTree: TSyntaxTree;
  mParameter: TSyntaxNode;
begin
  // Der Ausdruck A < B >= C im Rumpf bleibt ein Vergleich, nur die Typen der Parameter teilen >=.
  Assert.AreEqual('', Diagnostics(cGenericDefault));
  mTree := TPascalParser.Parse(cGenericDefault);
  try
    mParameter := Find(Find(mTree.Root, TSyntaxKind.TypeDecl, 'TFoo'), TSyntaxKind.Parameter, 'Baz');
    Assert.IsNotNull(mParameter);
    Assert.IsNotNull(Find(mParameter, TSyntaxKind.GenericArgs, ''), 'IBaz<string>');
    Assert.IsNotNull(Find(mTree.Root, TSyntaxKind.RoutineDecl, 'TFoo.Danach'), 'Routine dahinter');
  finally
    mTree.Free;
  end;
end;

procedure TParserGapsTests.BinaryWithLeadingSeparator;
begin
  Assert.AreEqual('', Diagnostics(cBinarySeparator));
end;

procedure TParserGapsTests.NamedArgumentWithKeyword;
begin
  Assert.AreEqual('', Diagnostics(cNamedKeyword));
end;

procedure TParserGapsTests.AnonymousMethodWithCallingConvention;
var
  mTree: TSyntaxTree;
begin
  Assert.AreEqual('', Diagnostics(cAnonymousConvention));
  mTree := TPascalParser.Parse(cAnonymousConvention);
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
  Assert.AreEqual('', Diagnostics(cInlineAttribute));
  mTree := TPascalParser.Parse(cInlineAttribute);
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
