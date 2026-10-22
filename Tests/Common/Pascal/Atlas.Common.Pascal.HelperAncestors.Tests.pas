unit Atlas.Common.Pascal.HelperAncestors.Tests;

// Tests für Helfer mit Vorfahr (#848): class helper (TBaseHelper) for TFoo
// wird als Helfer gelesen, steht mit Vorfahr und Ziel im Index, und die
// Namensauflösung findet die Mitglieder des Vorfahr-Helfers über TFoo. Die
// Quelle von CaseFour ist der nachgestellte Fall 04 aus
// planung/parser-luecken-faelle.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  THelperAncestorsTests = class
  public
    /// <summary>Abnahme: Fall 04 parst ohne Diagnosen, Vorfahr TBaseHelper, Ziel TFoo, TOther unverändert.
    /// </summary>
    [Test]
    procedure ParsesCaseFour;
    [Test]
    procedure RecordHelperWithAncestor;
    [Test]
    procedure IndexHoldsAncestorAndTarget;
    /// <summary>Abnahme: Ein Mitglied aus TBaseHelper ist über TFoo erreichbar.</summary>
    [Test]
    procedure ResolvesMemberOfAncestorHelper;
    [Test]
    procedure CandidatesIncludeAncestorHelper;
    [Test]
    procedure HoverChainNamesAncestorHelper;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.HoverTypes;

const
  CaseFour =
    'unit U4;'#10'interface'#10'type'#10'  TMyHelper = class helper (TBaseHelper) for TFoo'#10 +
    '    procedure A;'#10'  end;'#10'  TOther = class'#10'    procedure B;'#10'  end;'#10'implementation'#10'end.';
  UnitHelpers =
    'unit Helfer;'#10'interface'#10'type'#10'  TFoo = class'#10'    Name: string;'#10'  end;'#10 +
    '  TBaseHelper = class helper for TFoo'#10'    function AsText: string;'#10'    procedure Reset;'#10'  end;'#10 +
    '  TFooHelper = class helper (TBaseHelper) for TFoo'#10'    procedure Reset;'#10'  end;'#10 +
    'implementation'#10 +
    'function TBaseHelper.AsText: string; begin Result := Name; end;'#10 +
    'procedure TBaseHelper.Reset; begin end;'#10 +
    'procedure TFooHelper.Reset; begin end;'#10 +
    'end.';
  MainFile = 'C:\P\Haupt.pas';
  UnitMain =
    'unit Haupt;'#10'interface'#10'uses Helfer;'#10'implementation'#10'procedure P;'#10'var'#10 +
    '  Foo: TFoo;'#10'begin'#10'  Foo.AsText;'#10'  Foo.Reset;'#10'  Foo.'#10'end;'#10'end.';

function FindType(ANode: TSyntaxNode; const AName: string): TSyntaxNode;
var
  Index: Integer;
begin
  if (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, AName) then
    Exit(ANode);
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Result := FindType(ANode[Index], AName);
    if Result <> nil then
      Exit;
  end;
  Result := nil;
end;

/// <summary>Rumpf (erstes Kind mit Art) einer Typdeklaration.</summary>
function BodyOf(ADecl: TSyntaxNode; AKind: TSyntaxKind): TSyntaxNode;
var
  Index: Integer;
begin
  for Index := 0 to ADecl.ChildCount - 1 do
    if ADecl[Index].Kind = AKind then
      Exit(ADecl[Index]);
  Result := nil;
end;

/// <summary>Namen der direkten Kinder einer Art, mit Komma.</summary>
function ChildNames(ANode: TSyntaxNode; AKind: TSyntaxKind): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to ANode.ChildCount - 1 do
    if ANode[Index].Kind = AKind then
    begin
      if Result <> '' then
        Result := Result + ',';
      Result := Result + ANode[Index].Name;
    end;
end;

function SymbolOf(const AUnit: TUnitIndex; const AName: string): TIndexSymbol;
var
  Symbol: TIndexSymbol;
begin
  for Symbol in AUnit.Symbols do
    if (Symbol.Container = '') and SameText(Symbol.Name, AName) then
      Exit(Symbol);
  raise Exception.CreateFmt('%s fehlt im Index', [AName]);
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

function NewIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText(UnitHelpers, 'C:\P\Helfer.pas', nil));
end;

{ THelperAncestorsTests }

procedure THelperAncestorsTests.ParsesCaseFour;
var
  Tree: TSyntaxTree;
  Helper, Other: TSyntaxNode;
begin
  Tree := TPascalParser.Parse(CaseFour);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)));
    Helper := BodyOf(FindType(Tree.Root, 'TMyHelper'), TSyntaxKind.HelperType);
    Assert.IsNotNull(Helper);
    Assert.AreEqual('class', Helper.Name);
    // Erst der Vorfahr, zuletzt das Ziel.
    Assert.AreEqual('TBaseHelper,TFoo', ChildNames(Helper, TSyntaxKind.TypeReference));
    Assert.AreEqual('A', ChildNames(Helper, TSyntaxKind.RoutineHeader));
    Other := BodyOf(FindType(Tree.Root, 'TOther'), TSyntaxKind.ClassType);
    Assert.IsNotNull(Other);
    Assert.AreEqual('B', ChildNames(Other, TSyntaxKind.RoutineHeader));
  finally
    Tree.Free;
  end;
end;

procedure THelperAncestorsTests.RecordHelperWithAncestor;
var
  Tree: TSyntaxTree;
  Helper: TSyntaxNode;
begin
  Tree := TPascalParser.Parse('unit R;'#10'interface'#10'type'#10 +
    '  TIntHelper2 = record helper (TIntHelper) for Integer'#10'    function Twice: Integer;'#10'  end;'#10 +
    'implementation'#10'end.');
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)));
    Helper := BodyOf(FindType(Tree.Root, 'TIntHelper2'), TSyntaxKind.HelperType);
    Assert.IsNotNull(Helper);
    Assert.AreEqual('record', Helper.Name);
    Assert.AreEqual('TIntHelper,Integer', ChildNames(Helper, TSyntaxKind.TypeReference));
  finally
    Tree.Free;
  end;
end;

procedure THelperAncestorsTests.IndexHoldsAncestorAndTarget;
var
  U: TUnitIndex;
  Symbol: TIndexSymbol;
begin
  U := TIndexExtractor.ExtractText(CaseFour, 'C:\P\U4.pas', nil);
  Symbol := SymbolOf(U, 'TMyHelper');
  Assert.IsTrue(Symbol.Kind = TIndexSymbolKind.HelperType);
  Assert.AreEqual('TBaseHelper,TFoo', string.Join(',', Symbol.Ancestors));
  Symbol := SymbolOf(U, 'TOther');
  Assert.IsTrue(Symbol.Kind = TIndexSymbolKind.ClassType);
  // Keine Felder namens "helper" oder "TFoo" mehr.
  for Symbol in U.Symbols do
    Assert.IsFalse(Symbol.Kind = TIndexSymbolKind.Field, Symbol.Name);
end;

procedure THelperAncestorsTests.ResolvesMemberOfAncestorHelper;
var
  Index: ISymbolIndex;
  Resolver: TNameResolver;
  Tree: TSyntaxTree;
  Found: TResolvedSymbol;
begin
  Index := NewIndex;
  Resolver := TNameResolver.Create(Index);
  Tree := TPascalParser.Parse(UnitMain);
  try
    Found := Resolver.Resolve(Tree, MainFile, PositionOf(UnitMain, 'AsText;'));
    Assert.IsTrue(Found.Found);
    Assert.AreEqual('TBaseHelper', Found.Container);
    // Der abgeleitete Helfer verdeckt das gleichnamige Mitglied seines Vorfahren.
    Found := Resolver.Resolve(Tree, MainFile, PositionOf(UnitMain, 'Reset;'));
    Assert.IsTrue(Found.Found);
    Assert.AreEqual('TFooHelper', Found.Container);
  finally
    Tree.Free;
    Resolver.Free;
  end;
  Index := nil;
end;

procedure THelperAncestorsTests.CandidatesIncludeAncestorHelper;
var
  Index: ISymbolIndex;
  Resolver: TNameResolver;
  Tree: TSyntaxTree;
  Candidate: TResolvedSymbol;
  Listed: string;
begin
  Index := NewIndex;
  Resolver := TNameResolver.Create(Index);
  Tree := TPascalParser.Parse(UnitMain);
  try
    Listed := '';
    for Candidate in Resolver.MemberCandidates(Tree, MainFile, ['Foo'], Pos('Foo.'#10, UnitMain) + 3) do
      Listed := Listed + Candidate.Container + '.' + Candidate.Name + ' ';
  finally
    Tree.Free;
    Resolver.Free;
  end;
  Index := nil;
  Assert.Contains(Listed, 'TFooHelper.Reset ');
  Assert.Contains(Listed, 'TBaseHelper.AsText ');
  Assert.Contains(Listed, 'TFoo.Name ');
  // Reset nur einmal, aus dem abgeleiteten Helfer.
  Assert.DoesNotContain(Listed, 'TBaseHelper.Reset ');
end;

procedure THelperAncestorsTests.HoverChainNamesAncestorHelper;
var
  Index: ISymbolIndex;
  Resolver: TNameResolver;
  Helper: TResolvedSymbol;
  Chain: TArray<THoverTypeRef>;
  U: TUnitIndex;
begin
  Index := NewIndex;
  Resolver := TNameResolver.Create(Index);
  try
    U := Index.Units[0];
    Assert.IsTrue(Resolver.ResolveTypeFrom(U, 'TFooHelper', Helper));
    Chain := TLspHoverTypes.Chain(Resolver, Helper);
    Assert.AreEqual(2, Integer(Length(Chain)));
    Assert.AreEqual('TFooHelper', Chain[0].Name);
    Assert.AreEqual('TBaseHelper', Chain[1].Name);
    // Ein Helfer ohne Vorfahr hat keine Kette; das Ziel ist kein Vorfahr.
    Assert.IsTrue(Resolver.ResolveTypeFrom(U, 'TBaseHelper', Helper));
    Assert.AreEqual(0, Integer(Length(TLspHoverTypes.Chain(Resolver, Helper))));
  finally
    Resolver.Free;
  end;
  Index := nil;
end;

end.
