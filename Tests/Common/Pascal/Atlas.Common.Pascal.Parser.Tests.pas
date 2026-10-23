unit Atlas.Common.Pascal.Parser.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPascalParserTests = class
  public
    [Test]
    procedure ParsesEmptyUnit;
    [Test]
    procedure ParsesProgramWithUsesAndBlock;
    [Test]
    procedure ParsesPackageWithRequiresAndContains;
    [Test]
    procedure ParsesExportsWithParameterLists;
    [Test]
    procedure ParsesClassWithMembers;
    [Test]
    procedure EndsVarSectionAtVisibility;
    [Test]
    procedure ParsesGenericsAndAttributes;
    [Test]
    procedure ParsesTypeArgsBeforeIdentifier;
    [Test]
    procedure ParsesHelperWithAncestor;
    [Test]
    procedure ParsesFileKeywordInExpression;
    [Test]
    procedure ParsesRecordWithVariantPart;
    [Test]
    procedure ParsesProcedureTypesWithCallingConvention;
    [Test]
    procedure ParsesConstArrayWithSubrange;
    [Test]
    procedure RespectsOperatorPrecedence;
    [Test]
    procedure ParsesStatements;
    [Test]
    procedure KeepsEmptyThenBeforeElse;
    [Test]
    procedure ParsesInlineVarAndAnonymousMethod;
    [Test]
    procedure ReportsRangesInUtf16;
    [Test]
    procedure RecoversFromMissingSemicolon;
    [Test]
    procedure RecoversFromMissingExpression;
    [Test]
    procedure RecoversFromMissingClassEnd;
    [Test]
    procedure KeepsTokensIncludingComments;
    [Test]
    procedure StopsEarlyWhenCancelled;
    [Test]
    procedure KeepsUnknownDirectiveAsDirective;
    [Test]
    procedure KeepsLocalExportsClause;
    [Test]
    procedure FieldNamedOperator;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser;

// Gliederung eines Knotens, z. B. "UnitFile:U(InterfaceSection,ImplementationSection)".
function Outline(ANode: TSyntaxNode): string;
var
  Index: Integer;
begin
  Result := SyntaxKindName(ANode.Kind);
  if ANode.Name <> '' then
    Result := Result + ':' + ANode.Name;
  if ANode.ChildCount > 0 then
  begin
    Result := Result + '(';
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      if Index > 0 then
        Result := Result + ',';
      Result := Result + Outline(ANode[Index]);
    end;
    Result := Result + ')';
  end;
end;

// Erster Knoten der Art in Tiefensuche, sonst nil.
function FindFirst(ANode: TSyntaxNode; AKind: TSyntaxKind): TSyntaxNode;
var
  Index: Integer;
begin
  if ANode.Kind = AKind then
    Exit(ANode);
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Result := FindFirst(ANode[Index], AKind);
    if Result <> nil then
      Exit;
  end;
  Result := nil;
end;

// Anzahl der Knoten der Art im ganzen Baum.
function CountKind(ANode: TSyntaxNode; AKind: TSyntaxKind): Integer;
var
  Index: Integer;
begin
  Result := Ord(ANode.Kind = AKind);
  for Index := 0 to ANode.ChildCount - 1 do
    Inc(Result, CountKind(ANode[Index], AKind));
end;

function Lines(const ALines: array of string): string;
begin
  Result := string.Join(#13#10, ALines);
end;

procedure AssertNoDiagnostics(ATree: TSyntaxTree);
begin
  if Length(ATree.Diagnostics) > 0 then
    Assert.Fail(Format('Unerwartete Diagnose in %d:%d: %s', [ATree.Diagnostics[0].StartPos.Line,
      ATree.Diagnostics[0].StartPos.Character, ATree.Diagnostics[0].Message]));
end;

type
  TCountingCancellation = class(TInterfacedObject, IPascalCancellation)
  private
    FCalls: Integer;
  public
    function IsCancelled: Boolean;
  end;

function TCountingCancellation.IsCancelled: Boolean;
begin
  Inc(FCalls);
  Result := True;
end;

{ TPascalParserTests }

procedure TPascalParserTests.ParsesEmptyUnit;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(Lines(['unit U;', 'interface', 'implementation', 'end.']));
  try
    AssertNoDiagnostics(Tree);
    Assert.AreEqual('UnitFile:U(InterfaceSection,ImplementationSection)', Outline(Tree.Root));
  finally
    Tree.Free;
  end;
end;

procedure TPascalParserTests.ParsesProgramWithUsesAndBlock;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(Lines(['program P;', 'uses A in ''a.pas'', B.C;', 'var X: Integer;',
    'begin', '  X := 1;', 'end.']));
  try
    AssertNoDiagnostics(Tree);
    Assert.AreEqual('ProgramFile:P(UsesClause(UsedUnit:A,UsedUnit:B.C),' +
      'VarSection:var(VarDecl:X(TypeReference:Integer)),' +
      'Block(AssignStatement:X(Identifier:X,Literal:1)))', Outline(Tree.Root));
  finally
    Tree.Free;
  end;
end;

procedure TPascalParserTests.ParsesPackageWithRequiresAndContains;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(Lines(['package P;', 'requires', '  rtl;', 'contains',
    '  A in ''A.pas'';', 'end.']));
  try
    AssertNoDiagnostics(Tree);
    Assert.AreEqual(TSyntaxKind.PackageFile, Tree.Root.Kind);
    Assert.AreEqual(2, CountKind(Tree.Root, TSyntaxKind.UsesClause));
  finally
    Tree.Free;
  end;
end;

procedure TPascalParserTests.ParsesExportsWithParameterLists;
var
  Tree: TSyntaxTree;
  Exports_: TSyntaxNode;
begin
  // Überladene Routinen stehen mit Parameterliste in exports, darin ";" (#973).
  Tree := TPascalParser.Parse(Lines(['library L;', 'procedure Setze(const A: string; var B: Integer); overload;',
    'begin', 'end;', 'exports', '  Setze(const A: string; var B: Integer) name ''SetzeA'' index 3,', '  Lies;',
    'begin', 'end.']));
  try
    AssertNoDiagnostics(Tree);
    Assert.AreEqual(Ord(TSyntaxKind.LibraryFile), Ord(Tree.Root.Kind));
    Exports_ := FindFirst(Tree.Root, TSyntaxKind.ExportsClause);
    Assert.IsNotNull(Exports_);
    Assert.AreEqual(4, Exports_.StartPos.Line);
    Assert.AreEqual(6, Exports_.EndPos.Line);
    Assert.AreEqual(0, CountKind(Tree.Root, TSyntaxKind.VarSection));
  finally
    Tree.Free;
  end;
end;

procedure TPascalParserTests.ParsesClassWithMembers;
var
  Tree: TSyntaxTree;
  ClassNode: TSyntaxNode;
begin
  Tree := TPascalParser.Parse(Lines(['unit U;', 'interface', 'type',
    '  TFoo = class(TInterfacedObject, IFoo)',
    '  strict private',
    '    FValue: Integer;',
    '  public',
    '    constructor Create(const AValue: Integer = 0); overload;',
    '    function Get: Integer; virtual; abstract;',
    '    property Value: Integer read FValue write FValue default 0;',
    '  end;',
    'implementation', 'end.']));
  try
    AssertNoDiagnostics(Tree);
    ClassNode := FindFirst(Tree.Root, TSyntaxKind.ClassType);
    Assert.IsNotNull(ClassNode);
    Assert.AreEqual('TFoo', ClassNode.Parent.Name);
    Assert.AreEqual('strict private', FindFirst(ClassNode, TSyntaxKind.Visibility).Name);
    Assert.AreEqual(2, CountKind(ClassNode, TSyntaxKind.RoutineHeader));
    Assert.AreEqual('Value', FindFirst(ClassNode, TSyntaxKind.PropertyDecl).Name);
  finally
    Tree.Free;
  end;
end;

procedure TPascalParserTests.EndsVarSectionAtVisibility;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(Lines(['unit U;', 'interface', 'type',
    '  TFoo = class',
    '  private',
    '    class var FCount: Integer;',
    '  public',
    '    type TInner = Integer;',
    '  protected',
    '    procedure X;',
    '  end;',
    'implementation', 'end.']));
  try
    AssertNoDiagnostics(Tree);
    Assert.AreEqual(3, CountKind(Tree.Root, TSyntaxKind.Visibility));
  finally
    Tree.Free;
  end;
end;

procedure TPascalParserTests.ParsesGenericsAndAttributes;
var
  Tree: TSyntaxTree;
  Params: TSyntaxNode;
begin
  Tree := TPascalParser.Parse(Lines(['unit U;', 'interface', 'type',
    '  [Attr(''x''), Other]',
    '  TList<T: class, constructor> = class(TEnumerable<T>)',
    '    function Map<R>(const F: TFunc<T, R>): TList<R>;',
    '  end;',
    '  TPaar<K: class, TBasis; V: IFoo, constructor> = class',
    '  end;',
    'implementation',
    'procedure X;',
    'begin',
    '  L := TList<Integer>.Create;',
    '  B := A < C;',
    'end;',
    'end.']));
  try
    AssertNoDiagnostics(Tree);
    Assert.AreEqual(1, CountKind(Tree.Root, TSyntaxKind.Attribute));
    Assert.IsTrue(CountKind(Tree.Root, TSyntaxKind.GenericParams) >= 2);
    Assert.IsTrue(CountKind(Tree.Root, TSyntaxKind.GenericArgs) >= 1);
    Assert.AreEqual('<', FindFirst(Tree.Root, TSyntaxKind.BinaryExpr).Name);
    // Typen aus Einschränkungen sind keine Typparameter (#1029).
    Params := FindFirst(Tree.Root, TSyntaxKind.GenericParams);
    Assert.AreEqual(1, Params.ChildCount);
    Assert.AreEqual('T', Params[0].Name);
    Params := FindFirst(FindFirst(Tree.Root, TSyntaxKind.TypeSection)[2], TSyntaxKind.GenericParams);
    Assert.AreEqual(2, Params.ChildCount);
    Assert.AreEqual('K', Params[0].Name);
    Assert.AreEqual('V', Params[1].Name);
  finally
    Tree.Free;
  end;
end;

procedure TPascalParserTests.ParsesHelperWithAncestor;
var
  Tree: TSyntaxTree;
  Helper: TSyntaxNode;
begin
  // class helper (TBasis) for T und record helper (…) for T sind Helfer, keine Klassen (#848, #994).
  Tree := TPascalParser.Parse(Lines(['unit U;', 'interface', 'type',
    '  TListeHelfer = class helper (TBasisHelfer) for TListe',
    '    procedure Leeren;',
    '  end;',
    '  TZahlHelfer = record helper (TBasisZahl) for Integer',
    '  end;',
    'implementation', 'end.']));
  try
    AssertNoDiagnostics(Tree);
    Assert.AreEqual(2, CountKind(Tree.Root, TSyntaxKind.HelperType));
    Assert.AreEqual(0, CountKind(Tree.Root, TSyntaxKind.ClassType));
    Helper := FindFirst(Tree.Root, TSyntaxKind.HelperType);
    Assert.AreEqual('TBasisHelfer', Helper[0].Name);
    Assert.AreEqual('TListe', Helper[1].Name);
    Assert.AreEqual('Leeren', Helper[2].Name);
  finally
    Tree.Free;
  end;
end;

procedure TPascalParserTests.ParsesFileKeywordInExpression;
var
  Tree: TSyntaxTree;
  Call: TSyntaxNode;
begin
  // file steht wie string als Typname im Ausdruck: Default(File), SizeOf(file) (#1084).
  Tree := TPascalParser.Parse(Lines(['unit U;', 'interface', 'implementation', 'procedure P;', 'begin',
    '  X := Default(File);', '  Y := SizeOf(string);', 'end;', 'end.']));
  try
    AssertNoDiagnostics(Tree);
    Call := FindFirst(Tree.Root, TSyntaxKind.Call);
    Assert.AreEqual('Default', Call.Name);
    Assert.AreEqual(2, Integer(Call.ChildCount));
    Assert.AreEqual('File', Call[1].Name);
    Assert.IsTrue(Call[1].Kind = TSyntaxKind.Identifier);
  finally
    Tree.Free;
  end;
end;

procedure TPascalParserTests.ParsesTypeArgsBeforeIdentifier;
var
  Tree: TSyntaxTree;
  Prop, TypeRef: TSyntaxNode;
begin
  // Im Typverweis folgt den Typargumenten auch ein Bezeichner (read, write, deprecated) (#1004).
  Tree := TPascalParser.Parse(Lines(['unit U;', 'interface', 'type',
    '  TKarte = class',
    '    property Liste: TList<Integer> read FListe write FListe;',
    '    property Tabelle: TDictionary<string, TList<Integer>> read FTabelle;',
    '  end;',
    'implementation',
    'end.']));
  try
    AssertNoDiagnostics(Tree);
    Prop := FindFirst(Tree.Root, TSyntaxKind.PropertyDecl);
    TypeRef := Prop.FindChild(TSyntaxKind.TypeReference);
    Assert.AreEqual('TList', TypeRef.Name);
    Assert.IsNotNull(TypeRef.FindChild(TSyntaxKind.GenericArgs));
    Assert.AreEqual(2, CountKind(Tree.Root, TSyntaxKind.PropertyDecl));
    Assert.AreEqual(3, CountKind(Tree.Root, TSyntaxKind.GenericArgs));
  finally
    Tree.Free;
  end;
end;

procedure TPascalParserTests.ParsesRecordWithVariantPart;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(Lines(['unit U;', 'interface', 'type',
    '  TRec = packed record',
    '    Tag: Byte;',
    '    case Integer of',
    '      0: (A: Integer);',
    '      1: (B, C: Word);',
    '  end;',
    'implementation', 'end.']));
  try
    AssertNoDiagnostics(Tree);
    Assert.IsNotNull(FindFirst(Tree.Root, TSyntaxKind.RecordType));
    Assert.IsNotNull(FindFirst(Tree.Root, TSyntaxKind.VariantPart));
  finally
    Tree.Free;
  end;
end;

procedure TPascalParserTests.ParsesProcedureTypesWithCallingConvention;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(Lines(['unit U;', 'interface', 'type',
    '  TCallback = procedure(A: Integer); stdcall;',
    '  TEvent = procedure(Sender: TObject) of object;',
    '  TFunc = reference to function: Integer;',
    'var',
    '  Hook: function(P: Pointer): Integer; cdecl;',
    'implementation', 'end.']));
  try
    AssertNoDiagnostics(Tree);
    Assert.AreEqual(4, CountKind(Tree.Root, TSyntaxKind.ProcedureType));
  finally
    Tree.Free;
  end;
end;

procedure TPascalParserTests.ParsesConstArrayWithSubrange;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(Lines(['unit U;', 'interface', 'const',
    '  Names: array[0..1] of string = (''a'', ''b'');',
    '  Mask = 1 shl 3;',
    'implementation', 'end.']));
  try
    AssertNoDiagnostics(Tree);
    Assert.AreEqual(2, CountKind(Tree.Root, TSyntaxKind.ConstDecl));
    Assert.IsNotNull(FindFirst(Tree.Root, TSyntaxKind.ArrayType));
  finally
    Tree.Free;
  end;
end;

procedure TPascalParserTests.RespectsOperatorPrecedence;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(Lines(['program P;', 'begin', '  X := 1 + 2 * 3;', 'end.']));
  try
    AssertNoDiagnostics(Tree);
    Assert.AreEqual('BinaryExpr:+(Literal:1,BinaryExpr:*(Literal:2,Literal:3))',
      Outline(FindFirst(Tree.Root, TSyntaxKind.BinaryExpr)));
  finally
    Tree.Free;
  end;
end;

procedure TPascalParserTests.KeepsEmptyThenBeforeElse;
var
  Tree: TSyntaxTree;
  Node: TSyntaxNode;
begin
  // if A then else B: Der then-Zweig ist leer, B gehört ins else (#656).
  Tree := TPascalParser.Parse(Lines(['program P;', 'begin', '  if A then else B;', '  if C then ;', 'end.']));
  try
    AssertNoDiagnostics(Tree);
    Node := FindFirst(Tree.Root, TSyntaxKind.IfStatement);
    Assert.AreEqual(3, Node.ChildCount);
    Assert.AreEqual(Ord(TSyntaxKind.EmptyStatement), Ord(Node[1].Kind));
    Assert.AreEqual(Ord(TSyntaxKind.CallStatement), Ord(Node[2].Kind));
    // Ohne else bleibt es bei Bedingung allein.
    Assert.AreEqual(1, Node.Parent[1].ChildCount);
  finally
    Tree.Free;
  end;
end;

procedure TPascalParserTests.ParsesStatements;
var
  Tree: TSyntaxTree;
  Item: TSyntaxNode;
begin
  Tree := TPascalParser.Parse(Lines(['program P;', 'begin',
    '  if (A >= B) and not C then X := Y.Z(1)[2]^ else begin end;',
    '  case I of 1..2, 3: ; else Exit; end;',
    '  try raise E.Create(''x'') except on E: Exception do ; end;',
    '  try finally end;',
    '  while A < B do repeat until True;',
    '  for I := 0 to 10 do with A, B do ;',
    '  asm mov eax, 1 end;',
    '  S := [1..3, A];',
    '  inherited Create;',
    'end.']));
  try
    AssertNoDiagnostics(Tree);
    Assert.IsNotNull(FindFirst(Tree.Root, TSyntaxKind.IfStatement));
    Assert.IsNotNull(FindFirst(Tree.Root, TSyntaxKind.CaseStatement));
    Assert.IsNotNull(FindFirst(Tree.Root, TSyntaxKind.ExceptionHandler));
    Assert.IsNotNull(FindFirst(Tree.Root, TSyntaxKind.FinallyBlock));
    Assert.IsNotNull(FindFirst(Tree.Root, TSyntaxKind.RepeatStatement));
    Assert.IsNotNull(FindFirst(Tree.Root, TSyntaxKind.WithStatement));
    Assert.IsNotNull(FindFirst(Tree.Root, TSyntaxKind.AsmBlock));
    Assert.IsNotNull(FindFirst(Tree.Root, TSyntaxKind.SetConstructor));
    Assert.IsNotNull(FindFirst(Tree.Root, TSyntaxKind.Dereference));
    Assert.IsNotNull(FindFirst(Tree.Root, TSyntaxKind.InheritedExpr));
    // Marke 1..2 ist ein Bereich wie in Mengen (#983), danach die Marke 3.
    Item := FindFirst(Tree.Root, TSyntaxKind.CaseItem);
    Assert.AreEqual(2, Item.ChildCount);
    Assert.AreEqual(Ord(TSyntaxKind.RangeExpr), Ord(Item[0].Kind));
    Assert.AreEqual(2, Item[0].ChildCount);
    Assert.AreEqual(Ord(TSyntaxKind.Literal), Ord(Item[1].Kind));
  finally
    Tree.Free;
  end;
end;

procedure TPascalParserTests.ParsesInlineVarAndAnonymousMethod;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(Lines(['program P;', 'begin',
    '  var X: Integer := 1;',
    '  for var S in List do ;',
    '  P := procedure(A: Integer) begin Writeln(A) end;',
    'end.']));
  try
    AssertNoDiagnostics(Tree);
    Assert.IsNotNull(FindFirst(Tree.Root, TSyntaxKind.InlineVar));
    Assert.IsNotNull(FindFirst(Tree.Root, TSyntaxKind.ForInStatement));
    Assert.IsNotNull(FindFirst(Tree.Root, TSyntaxKind.AnonymousMethod));
  finally
    Tree.Free;
  end;
end;

procedure TPascalParserTests.ReportsRangesInUtf16;
var
  Tree: TSyntaxTree;
  Node: TSyntaxNode;
begin
  Tree := TPascalParser.Parse(Lines(['program P;', 'begin', '  S := ''' + #$D83D#$DE00 + ''';', 'end.']));
  try
    AssertNoDiagnostics(Tree);
    Node := FindFirst(Tree.Root, TSyntaxKind.AssignStatement);
    Assert.IsTrue(TTextPosition.Create(2, 2) = Node.StartPos);
    Assert.IsTrue(TTextPosition.Create(2, 11) = Node.EndPos);
  finally
    Tree.Free;
  end;
end;

procedure TPascalParserTests.RecoversFromMissingSemicolon;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(Lines(['program P;', 'begin', '  A := 1', '  B := 2;', 'end.']));
  try
    Assert.AreEqual<NativeInt>(1, Length(Tree.Diagnostics));
    // Gemeldet am Ende der Zeile, in der das Semikolon fehlt.
    Assert.IsTrue(TTextPosition.Create(2, 8) = Tree.Diagnostics[0].StartPos);
    Assert.IsTrue(TTextPosition.Create(2, 8) = Tree.Diagnostics[0].EndPos);
    Assert.AreEqual(''';'' fehlt (wie E2066).', Tree.Diagnostics[0].Message);
    Assert.AreEqual(2, CountKind(Tree.Root, TSyntaxKind.AssignStatement));
  finally
    Tree.Free;
  end;
end;

procedure TPascalParserTests.RecoversFromMissingExpression;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(Lines(['program P;', 'begin', '  A := ;', '  if then B;', '  C;', 'end.']));
  try
    Assert.AreEqual<NativeInt>(2, Length(Tree.Diagnostics));
    Assert.AreEqual(2, CountKind(Tree.Root, TSyntaxKind.Error));
    Assert.AreEqual(2, CountKind(Tree.Root, TSyntaxKind.CallStatement));
  finally
    Tree.Free;
  end;
end;

procedure TPascalParserTests.RecoversFromMissingClassEnd;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(Lines(['unit U;', 'interface', 'type', '  T = class', '    procedure A;',
    'implementation', 'procedure B;', 'begin', 'end;', 'end.']));
  try
    Assert.AreEqual<NativeInt>(1, Length(Tree.Diagnostics));
    Assert.IsTrue(TTextPosition.Create(5, 0) = Tree.Diagnostics[0].StartPos);
    Assert.IsNotNull(FindFirst(Tree.Root, TSyntaxKind.RoutineDecl));
  finally
    Tree.Free;
  end;
end;

procedure TPascalParserTests.KeepsTokensIncludingComments;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse('program P; { Kommentar } begin end.');
  try
    AssertNoDiagnostics(Tree);
    Assert.AreEqual<NativeInt>(7, Length(Tree.Tokens));
    Assert.AreEqual(TPascalTokenKind.Comment, Tree.Tokens[3].Kind);
  finally
    Tree.Free;
  end;
end;

procedure TPascalParserTests.StopsEarlyWhenCancelled;
var
  Text: TStringBuilder;
  Index: Integer;
  Cancellation: TCountingCancellation;
  Token: IPascalCancellation;
  Tree: TSyntaxTree;
begin
  Text := TStringBuilder.Create;
  try
    Text.Append('unit U;'#13#10'interface'#13#10'implementation'#13#10'procedure P;'#13#10'begin'#13#10);
    for Index := 1 to 5000 do
      Text.Append('  X := X + 1;'#13#10);
    Text.Append('end;'#13#10'end.');
    Cancellation := TCountingCancellation.Create;
    Token := Cancellation;
    Tree := TPascalParser.Parse(Text.ToString, Token);
    try
      // Nach der ersten Prüfung springt der Parser ans Ende und endet ohne Ausnahme.
      Assert.AreEqual(1, Cancellation.FCalls);
      Assert.IsNotNull(Tree.Root);
    finally
      Tree.Free;
    end;
  finally
    Text.Free;
  end;
end;

procedure TPascalParserTests.KeepsUnknownDirectiveAsDirective;
var
  Tree: TSyntaxTree;
begin
  // overide; ist ein Tippfehler an der Stelle einer Direktive (#1068): kein Feld, kein Folgefehler.
  Tree := TPascalParser.Parse(Lines(['unit U;', 'interface', 'type', '  TFoo = class',
    '    procedure Paint; overide;', '    procedure Q;', '  end;', 'implementation', 'end.']));
  try
    AssertNoDiagnostics(Tree);
    Assert.AreEqual('overide', FindFirst(Tree.Root, TSyntaxKind.Directive).Name);
    Assert.AreEqual(0, CountKind(Tree.Root, TSyntaxKind.Field));
  finally
    Tree.Free;
  end;
end;

procedure TPascalParserTests.KeepsLocalExportsClause;
var
  Tree: TSyntaxTree;
  Clause: TSyntaxNode;
begin
  // exports in lokalen Deklarationen (E2191 des Compilers) ist kein Syntaxfehler.
  Tree := TPascalParser.Parse(Lines(['library L;', 'procedure A;', 'exports A;', 'begin', 'end;', 'begin', 'end.']));
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)));
    Clause := FindFirst(Tree.Root, TSyntaxKind.ExportsClause);
    Assert.IsNotNull(Clause);
    Assert.IsTrue(Clause.Parent.Kind = TSyntaxKind.RoutineDecl);
  finally
    Tree.Free;
  end;
end;

procedure TPascalParserTests.FieldNamedOperator;
var
  Tree: TSyntaxTree;
begin
  // Operator: string ist ein Feld, kein FPC-Operator; sonst meldete field-after-method (E2169) die Felder danach.
  Tree := TPascalParser.Parse(Lines(['unit U;', 'interface', 'type', '  TRun = record', '    Operator: string;',
    '    Operator2, Count: Integer;', '    Count2: Integer;', '  end;', 'implementation', 'end.']));
  try
    AssertNoDiagnostics(Tree);
    Assert.AreEqual(0, CountKind(Tree.Root, TSyntaxKind.RoutineDecl));
    Assert.AreEqual(3, CountKind(Tree.Root, TSyntaxKind.Field));
  finally
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TPascalParserTests);

end.
