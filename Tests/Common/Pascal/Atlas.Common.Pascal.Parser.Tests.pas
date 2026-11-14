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
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser;

// Gliederung eines Knotens, z. B. "UnitFile:U(InterfaceSection,ImplementationSection)".
function Outline(ANode: TSyntaxNode): string;
var
  mIndex: Integer;
begin
  Result := SyntaxKindName(ANode.Kind);
  if ANode.Name <> '' then
  begin
    Result := Result + ':' + ANode.Name;
  end;
  if ANode.ChildCount > 0 then
  begin
    Result := Result + '(';
    for mIndex := 0 to ANode.ChildCount - 1 do
    begin
      if mIndex > 0 then
      begin
        Result := Result + ',';
      end;
      Result := Result + Outline(ANode[mIndex]);
    end;
    Result := Result + ')';
  end;
end;

// Erster Knoten der Art in Tiefensuche, sonst nil.
function FindFirst(ANode: TSyntaxNode; AKind: TSyntaxKind): TSyntaxNode;
var
  mIndex: Integer;
begin
  if ANode.Kind = AKind then
  begin
    Exit(ANode);
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    Result := FindFirst(ANode[mIndex], AKind);
    if Result <> nil then
    begin
      Exit;
    end;
  end;
  Result := nil;
end;

// Anzahl der Knoten der Art im ganzen Baum.
function CountKind(ANode: TSyntaxNode; AKind: TSyntaxKind): Integer;
var
  mIndex: Integer;
begin
  Result := Ord(ANode.Kind = AKind);
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    Inc(Result, CountKind(ANode[mIndex], AKind));
  end;
end;

function Lines(const ALines: array of string): string;
begin
  Result := string.Join(#13#10, ALines);
end;

procedure AssertNoDiagnostics(ATree: TSyntaxTree);
begin
  if Length(ATree.Diagnostics) > 0 then
  begin
    Assert.Fail(Format('Unerwartete Diagnose in %d:%d: %s', [ATree.Diagnostics[0].StartPos.Line,
      ATree.Diagnostics[0].StartPos.Character, ATree.Diagnostics[0].Message]));
  end;
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
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(Lines(['unit U;', 'interface', 'implementation', 'end.']));
  try
    AssertNoDiagnostics(mTree);
    Assert.AreEqual('UnitFile:U(InterfaceSection,ImplementationSection)', Outline(mTree.Root));
  finally
    mTree.Free;
  end;
end;

procedure TPascalParserTests.ParsesProgramWithUsesAndBlock;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(Lines(['program P;', 'uses A in ''a.pas'', B.C;', 'var X: Integer;',
    'begin', '  X := 1;', 'end.']));
  try
    AssertNoDiagnostics(mTree);
    Assert.AreEqual('ProgramFile:P(UsesClause(UsedUnit:A,UsedUnit:B.C),' +
      'VarSection:var(VarDecl:X(TypeReference:Integer)),' +
      'Block(AssignStatement:X(Identifier:X,Literal:1)))', Outline(mTree.Root));
  finally
    mTree.Free;
  end;
end;

procedure TPascalParserTests.ParsesPackageWithRequiresAndContains;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(Lines(['package P;', 'requires', '  rtl;', 'contains',
    '  A in ''A.pas'';', 'end.']));
  try
    AssertNoDiagnostics(mTree);
    Assert.AreEqual<TSyntaxKind>(TSyntaxKind.PackageFile, mTree.Root.Kind);
    Assert.AreEqual(2, CountKind(mTree.Root, TSyntaxKind.UsesClause));
  finally
    mTree.Free;
  end;
end;

procedure TPascalParserTests.ParsesExportsWithParameterLists;
var
  mTree: TSyntaxTree;
  mExports_: TSyntaxNode;
begin
  // Überladene Routinen stehen mit Parameterliste in exports, darin ";" (#973).
  mTree := TPascalParser.Parse(Lines(['library L;', 'procedure Setze(const A: string; var B: Integer); overload;',
    'begin', 'end;', 'exports', '  Setze(const A: string; var B: Integer) name ''SetzeA'' index 3,', '  Lies;',
    'begin', 'end.']));
  try
    AssertNoDiagnostics(mTree);
    Assert.AreEqual(Ord(TSyntaxKind.LibraryFile), Ord(mTree.Root.Kind));
    mExports_ := FindFirst(mTree.Root, TSyntaxKind.ExportsClause);
    Assert.IsNotNull(mExports_);
    Assert.AreEqual(4, mExports_.StartPos.Line);
    Assert.AreEqual(6, mExports_.EndPos.Line);
    Assert.AreEqual(0, CountKind(mTree.Root, TSyntaxKind.VarSection));
  finally
    mTree.Free;
  end;
end;

procedure TPascalParserTests.ParsesClassWithMembers;
var
  mTree: TSyntaxTree;
  mClassNode: TSyntaxNode;
begin
  mTree := TPascalParser.Parse(Lines(['unit U;', 'interface', 'type',
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
    AssertNoDiagnostics(mTree);
    mClassNode := FindFirst(mTree.Root, TSyntaxKind.ClassType);
    Assert.IsNotNull(mClassNode);
    Assert.AreEqual('TFoo', mClassNode.Parent.Name);
    Assert.AreEqual('strict private', FindFirst(mClassNode, TSyntaxKind.Visibility).Name);
    Assert.AreEqual(2, CountKind(mClassNode, TSyntaxKind.RoutineHeader));
    Assert.AreEqual('Value', FindFirst(mClassNode, TSyntaxKind.PropertyDecl).Name);
  finally
    mTree.Free;
  end;
end;

procedure TPascalParserTests.EndsVarSectionAtVisibility;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(Lines(['unit U;', 'interface', 'type',
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
    AssertNoDiagnostics(mTree);
    Assert.AreEqual(3, CountKind(mTree.Root, TSyntaxKind.Visibility));
  finally
    mTree.Free;
  end;
end;

procedure TPascalParserTests.ParsesGenericsAndAttributes;
var
  mTree: TSyntaxTree;
  mParams: TSyntaxNode;
begin
  mTree := TPascalParser.Parse(Lines(['unit U;', 'interface', 'type',
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
    AssertNoDiagnostics(mTree);
    Assert.AreEqual(1, CountKind(mTree.Root, TSyntaxKind.Attribute));
    Assert.IsTrue(CountKind(mTree.Root, TSyntaxKind.GenericParams) >= 2);
    Assert.IsTrue(CountKind(mTree.Root, TSyntaxKind.GenericArgs) >= 1);
    Assert.AreEqual('<', FindFirst(mTree.Root, TSyntaxKind.BinaryExpr).Name);
    // Typen aus Einschränkungen sind keine Typparameter (#1029).
    mParams := FindFirst(mTree.Root, TSyntaxKind.GenericParams);
    Assert.AreEqual(1, mParams.ChildCount);
    Assert.AreEqual('T', mParams[0].Name);
    mParams := FindFirst(FindFirst(mTree.Root, TSyntaxKind.TypeSection)[2], TSyntaxKind.GenericParams);
    Assert.AreEqual(2, mParams.ChildCount);
    Assert.AreEqual('K', mParams[0].Name);
    Assert.AreEqual('V', mParams[1].Name);
  finally
    mTree.Free;
  end;
end;

procedure TPascalParserTests.ParsesHelperWithAncestor;
var
  mTree: TSyntaxTree;
  mHelper: TSyntaxNode;
begin
  // class helper (TBasis) for T und record helper (…) for T sind Helfer, keine Klassen (#848, #994).
  mTree := TPascalParser.Parse(Lines(['unit U;', 'interface', 'type',
    '  TListeHelfer = class helper (TBasisHelfer) for TListe',
    '    procedure Leeren;',
    '  end;',
    '  TZahlHelfer = record helper (TBasisZahl) for Integer',
    '  end;',
    'implementation', 'end.']));
  try
    AssertNoDiagnostics(mTree);
    Assert.AreEqual(2, CountKind(mTree.Root, TSyntaxKind.HelperType));
    Assert.AreEqual(0, CountKind(mTree.Root, TSyntaxKind.ClassType));
    mHelper := FindFirst(mTree.Root, TSyntaxKind.HelperType);
    Assert.AreEqual('TBasisHelfer', mHelper[0].Name);
    Assert.AreEqual('TListe', mHelper[1].Name);
    Assert.AreEqual('Leeren', mHelper[2].Name);
  finally
    mTree.Free;
  end;
end;

procedure TPascalParserTests.ParsesFileKeywordInExpression;
var
  mTree: TSyntaxTree;
  mCall: TSyntaxNode;
begin
  // file steht wie string als Typname im Ausdruck: Default(File), SizeOf(file) (#1084).
  mTree := TPascalParser.Parse(Lines(['unit U;', 'interface', 'implementation', 'procedure P;', 'begin',
    '  X := Default(File);', '  Y := SizeOf(string);', 'end;', 'end.']));
  try
    AssertNoDiagnostics(mTree);
    mCall := FindFirst(mTree.Root, TSyntaxKind.Call);
    Assert.AreEqual('Default', mCall.Name);
    Assert.AreEqual(2, Integer(mCall.ChildCount));
    Assert.AreEqual('File', mCall[1].Name);
    Assert.AreEqual<TSyntaxKind>(TSyntaxKind.Identifier, mCall[1].Kind);
  finally
    mTree.Free;
  end;
end;

procedure TPascalParserTests.ParsesTypeArgsBeforeIdentifier;
var
  mTree: TSyntaxTree;
  mProp, mTypeRef: TSyntaxNode;
begin
  // Im Typverweis folgt den Typargumenten auch ein Bezeichner (read, write, deprecated) (#1004).
  mTree := TPascalParser.Parse(Lines(['unit U;', 'interface', 'type',
    '  TKarte = class',
    '    property Liste: TList<Integer> read FListe write FListe;',
    '    property Tabelle: TDictionary<string, TList<Integer>> read FTabelle;',
    '  end;',
    'implementation',
    'end.']));
  try
    AssertNoDiagnostics(mTree);
    mProp := FindFirst(mTree.Root, TSyntaxKind.PropertyDecl);
    mTypeRef := mProp.FindChild(TSyntaxKind.TypeReference);
    Assert.AreEqual('TList', mTypeRef.Name);
    Assert.IsNotNull(mTypeRef.FindChild(TSyntaxKind.GenericArgs));
    Assert.AreEqual(2, CountKind(mTree.Root, TSyntaxKind.PropertyDecl));
    Assert.AreEqual(3, CountKind(mTree.Root, TSyntaxKind.GenericArgs));
  finally
    mTree.Free;
  end;
end;

procedure TPascalParserTests.ParsesRecordWithVariantPart;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(Lines(['unit U;', 'interface', 'type',
    '  TRec = packed record',
    '    Tag: Byte;',
    '    case Integer of',
    '      0: (A: Integer);',
    '      1: (B, C: Word);',
    '  end;',
    'implementation', 'end.']));
  try
    AssertNoDiagnostics(mTree);
    Assert.IsNotNull(FindFirst(mTree.Root, TSyntaxKind.RecordType));
    Assert.IsNotNull(FindFirst(mTree.Root, TSyntaxKind.VariantPart));
  finally
    mTree.Free;
  end;
end;

procedure TPascalParserTests.ParsesProcedureTypesWithCallingConvention;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(Lines(['unit U;', 'interface', 'type',
    '  TCallback = procedure(A: Integer); stdcall;',
    '  TEvent = procedure(Sender: TObject) of object;',
    '  TFunc = reference to function: Integer;',
    'var',
    '  Hook: function(P: Pointer): Integer; cdecl;',
    'implementation', 'end.']));
  try
    AssertNoDiagnostics(mTree);
    Assert.AreEqual(4, CountKind(mTree.Root, TSyntaxKind.ProcedureType));
  finally
    mTree.Free;
  end;
end;

procedure TPascalParserTests.ParsesConstArrayWithSubrange;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(Lines(['unit U;', 'interface', 'const',
    '  Names: array[0..1] of string = (''a'', ''b'');',
    '  Mask = 1 shl 3;',
    'implementation', 'end.']));
  try
    AssertNoDiagnostics(mTree);
    Assert.AreEqual(2, CountKind(mTree.Root, TSyntaxKind.ConstDecl));
    Assert.IsNotNull(FindFirst(mTree.Root, TSyntaxKind.ArrayType));
  finally
    mTree.Free;
  end;
end;

procedure TPascalParserTests.RespectsOperatorPrecedence;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(Lines(['program P;', 'begin', '  X := 1 + 2 * 3;', 'end.']));
  try
    AssertNoDiagnostics(mTree);
    Assert.AreEqual('BinaryExpr:+(Literal:1,BinaryExpr:*(Literal:2,Literal:3))',
      Outline(FindFirst(mTree.Root, TSyntaxKind.BinaryExpr)));
  finally
    mTree.Free;
  end;
end;

procedure TPascalParserTests.KeepsEmptyThenBeforeElse;
var
  mTree: TSyntaxTree;
  mNode: TSyntaxNode;
begin
  // if A then else B: Der then-Zweig ist leer, B gehört ins else (#656).
  mTree := TPascalParser.Parse(Lines(['program P;', 'begin', '  if A then else B;', '  if C then ;', 'end.']));
  try
    AssertNoDiagnostics(mTree);
    mNode := FindFirst(mTree.Root, TSyntaxKind.IfStatement);
    Assert.AreEqual(3, mNode.ChildCount);
    Assert.AreEqual(Ord(TSyntaxKind.EmptyStatement), Ord(mNode[1].Kind));
    Assert.AreEqual(Ord(TSyntaxKind.CallStatement), Ord(mNode[2].Kind));
    // Ohne else bleibt es bei Bedingung allein.
    Assert.AreEqual(1, mNode.Parent[1].ChildCount);
  finally
    mTree.Free;
  end;
end;

procedure TPascalParserTests.ParsesStatements;
var
  mTree: TSyntaxTree;
  mItem: TSyntaxNode;
begin
  mTree := TPascalParser.Parse(Lines(['program P;', 'begin',
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
    AssertNoDiagnostics(mTree);
    Assert.IsNotNull(FindFirst(mTree.Root, TSyntaxKind.IfStatement));
    Assert.IsNotNull(FindFirst(mTree.Root, TSyntaxKind.CaseStatement));
    Assert.IsNotNull(FindFirst(mTree.Root, TSyntaxKind.ExceptionHandler));
    Assert.IsNotNull(FindFirst(mTree.Root, TSyntaxKind.FinallyBlock));
    Assert.IsNotNull(FindFirst(mTree.Root, TSyntaxKind.RepeatStatement));
    Assert.IsNotNull(FindFirst(mTree.Root, TSyntaxKind.WithStatement));
    Assert.IsNotNull(FindFirst(mTree.Root, TSyntaxKind.AsmBlock));
    Assert.IsNotNull(FindFirst(mTree.Root, TSyntaxKind.SetConstructor));
    Assert.IsNotNull(FindFirst(mTree.Root, TSyntaxKind.Dereference));
    Assert.IsNotNull(FindFirst(mTree.Root, TSyntaxKind.InheritedExpr));
    // Marke 1..2 ist ein Bereich wie in Mengen (#983), danach die Marke 3.
    mItem := FindFirst(mTree.Root, TSyntaxKind.CaseItem);
    Assert.AreEqual(2, mItem.ChildCount);
    Assert.AreEqual(Ord(TSyntaxKind.RangeExpr), Ord(mItem[0].Kind));
    Assert.AreEqual(2, mItem[0].ChildCount);
    Assert.AreEqual(Ord(TSyntaxKind.Literal), Ord(mItem[1].Kind));
  finally
    mTree.Free;
  end;
end;

procedure TPascalParserTests.ParsesInlineVarAndAnonymousMethod;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(Lines(['program P;', 'begin',
    '  var X: Integer := 1;',
    '  for var S in List do ;',
    '  P := procedure(A: Integer) begin Writeln(A) end;',
    'end.']));
  try
    AssertNoDiagnostics(mTree);
    Assert.IsNotNull(FindFirst(mTree.Root, TSyntaxKind.InlineVar));
    Assert.IsNotNull(FindFirst(mTree.Root, TSyntaxKind.ForInStatement));
    Assert.IsNotNull(FindFirst(mTree.Root, TSyntaxKind.AnonymousMethod));
  finally
    mTree.Free;
  end;
end;

procedure TPascalParserTests.ReportsRangesInUtf16;
var
  mTree: TSyntaxTree;
  mNode: TSyntaxNode;
begin
  mTree := TPascalParser.Parse(Lines(['program P;', 'begin', '  S := ''' + #$D83D#$DE00 + ''';', 'end.']));
  try
    AssertNoDiagnostics(mTree);
    mNode := FindFirst(mTree.Root, TSyntaxKind.AssignStatement);
    Assert.AreEqual(2, mNode.StartPos.Line);
    Assert.AreEqual(2, mNode.StartPos.Character);
    Assert.AreEqual(2, mNode.EndPos.Line);
    Assert.AreEqual(11, mNode.EndPos.Character);
  finally
    mTree.Free;
  end;
end;

procedure TPascalParserTests.RecoversFromMissingSemicolon;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(Lines(['program P;', 'begin', '  A := 1', '  B := 2;', 'end.']));
  try
    Assert.AreEqual<NativeInt>(1, Length(mTree.Diagnostics));
    // Gemeldet am Ende der Zeile, in der das Semikolon fehlt.
    Assert.AreEqual(2, mTree.Diagnostics[0].StartPos.Line);
    Assert.AreEqual(8, mTree.Diagnostics[0].StartPos.Character);
    Assert.AreEqual(2, mTree.Diagnostics[0].EndPos.Line);
    Assert.AreEqual(8, mTree.Diagnostics[0].EndPos.Character);
    Assert.AreEqual(''';'' fehlt (wie E2066).', mTree.Diagnostics[0].Message);
    Assert.AreEqual(2, CountKind(mTree.Root, TSyntaxKind.AssignStatement));
  finally
    mTree.Free;
  end;
end;

procedure TPascalParserTests.RecoversFromMissingExpression;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(Lines(['program P;', 'begin', '  A := ;', '  if then B;', '  C;', 'end.']));
  try
    Assert.AreEqual<NativeInt>(2, Length(mTree.Diagnostics));
    Assert.AreEqual(2, CountKind(mTree.Root, TSyntaxKind.Error));
    Assert.AreEqual(2, CountKind(mTree.Root, TSyntaxKind.CallStatement));
  finally
    mTree.Free;
  end;
end;

procedure TPascalParserTests.RecoversFromMissingClassEnd;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(Lines(['unit U;', 'interface', 'type', '  T = class', '    procedure A;',
    'implementation', 'procedure B;', 'begin', 'end;', 'end.']));
  try
    Assert.AreEqual<NativeInt>(1, Length(mTree.Diagnostics));
    Assert.AreEqual(5, mTree.Diagnostics[0].StartPos.Line);
    Assert.AreEqual(0, mTree.Diagnostics[0].StartPos.Character);
    Assert.IsNotNull(FindFirst(mTree.Root, TSyntaxKind.RoutineDecl));
  finally
    mTree.Free;
  end;
end;

procedure TPascalParserTests.KeepsTokensIncludingComments;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse('program P; { Kommentar } begin end.');
  try
    AssertNoDiagnostics(mTree);
    Assert.AreEqual<NativeInt>(7, Length(mTree.Tokens));
    Assert.AreEqual<TPascalTokenKind>(TPascalTokenKind.Comment, mTree.Tokens[3].Kind);
  finally
    mTree.Free;
  end;
end;

procedure TPascalParserTests.StopsEarlyWhenCancelled;
var
  mText: TStringBuilder;
  mIndex: Integer;
  mCancellation: TCountingCancellation;
  mToken: IPascalCancellation;
  mTree: TSyntaxTree;
begin
  mText := TStringBuilder.Create;
  try
    mText.Append('unit U;'#13#10'interface'#13#10'implementation'#13#10'procedure P;'#13#10'begin'#13#10);
    for mIndex := 1 to 5000 do
    begin
      mText.Append('  X := X + 1;'#13#10);
    end;
    mText.Append('end;'#13#10'end.');
    mCancellation := TCountingCancellation.Create;
    mToken := mCancellation;
    mTree := TPascalParser.Parse(mText.ToString, mToken);
    try
      // Nach der ersten Prüfung springt der Parser ans Ende und endet ohne Ausnahme.
      Assert.AreEqual(1, mCancellation.FCalls);
      Assert.IsNotNull(mTree.Root);
    finally
      mTree.Free;
    end;
  finally
    mText.Free;
  end;
end;

procedure TPascalParserTests.KeepsUnknownDirectiveAsDirective;
var
  mTree: TSyntaxTree;
begin
  // overide; ist ein Tippfehler an der Stelle einer Direktive (#1068): kein Feld, kein Folgefehler.
  mTree := TPascalParser.Parse(Lines(['unit U;', 'interface', 'type', '  TFoo = class',
    '    procedure Paint; overide;', '    procedure Q;', '  end;', 'implementation', 'end.']));
  try
    AssertNoDiagnostics(mTree);
    Assert.AreEqual('overide', FindFirst(mTree.Root, TSyntaxKind.Directive).Name);
    Assert.AreEqual(0, CountKind(mTree.Root, TSyntaxKind.Field));
  finally
    mTree.Free;
  end;
end;

procedure TPascalParserTests.KeepsLocalExportsClause;
var
  mTree: TSyntaxTree;
  mClause: TSyntaxNode;
begin
  // exports in lokalen Deklarationen (E2191 des Compilers) ist kein Syntaxfehler.
  mTree := TPascalParser.Parse(Lines(['library L;', 'procedure A;', 'exports A;', 'begin', 'end;', 'begin', 'end.']));
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)));
    mClause := FindFirst(mTree.Root, TSyntaxKind.ExportsClause);
    Assert.IsNotNull(mClause);
    Assert.AreEqual<TSyntaxKind>(TSyntaxKind.RoutineDecl, mClause.Parent.Kind);
  finally
    mTree.Free;
  end;
end;

procedure TPascalParserTests.FieldNamedOperator;
var
  mTree: TSyntaxTree;
begin
  // Operator: string ist ein Feld, kein FPC-Operator; sonst meldete field-after-method (E2169) die Felder danach.
  mTree := TPascalParser.Parse(Lines(['unit U;', 'interface', 'type', '  TRun = record', '    Operator: string;',
    '    Operator2, Count: Integer;', '    Count2: Integer;', '  end;', 'implementation', 'end.']));
  try
    AssertNoDiagnostics(mTree);
    Assert.AreEqual(0, CountKind(mTree.Root, TSyntaxKind.RoutineDecl));
    Assert.AreEqual(3, CountKind(mTree.Root, TSyntaxKind.Field));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TPascalParserTests);

end.
