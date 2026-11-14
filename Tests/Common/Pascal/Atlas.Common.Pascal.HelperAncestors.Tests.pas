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
  cCaseFour =
    'unit U4;'#10'interface'#10'type'#10'  TMyHelper = class helper (TBaseHelper) for TFoo'#10 +
    '    procedure A;'#10'  end;'#10'  TOther = class'#10'    procedure B;'#10'  end;'#10'implementation'#10'end.';
  cUnitHelpers =
    'unit Helfer;'#10'interface'#10'type'#10'  TFoo = class'#10'    Name: string;'#10'  end;'#10 +
    '  TBaseHelper = class helper for TFoo'#10'    function AsText: string;'#10'    procedure Reset;'#10'  end;'#10 +
    '  TFooHelper = class helper (TBaseHelper) for TFoo'#10'    procedure Reset;'#10'  end;'#10 +
    'implementation'#10 +
    'function TBaseHelper.AsText: string; begin Result := Name; end;'#10 +
    'procedure TBaseHelper.Reset; begin end;'#10 +
    'procedure TFooHelper.Reset; begin end;'#10 +
    'end.';
  cMainFile = 'C:\P\Haupt.pas';
  cUnitMain =
    'unit Haupt;'#10'interface'#10'uses Helfer;'#10'implementation'#10'procedure P;'#10'var'#10 +
    '  Foo: TFoo;'#10'begin'#10'  Foo.AsText;'#10'  Foo.Reset;'#10'  Foo.'#10'end;'#10'end.';

function FindType(ANode: TSyntaxNode; const AName: string): TSyntaxNode;
var
  mIndex: Integer;
begin
  if (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, AName) then
  begin
    Exit(ANode);
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    Result := FindType(ANode[mIndex], AName);
    if Result <> nil then
    begin
      Exit;
    end;
  end;
  Result := nil;
end;

/// <summary>Rumpf (erstes Kind mit Art) einer Typdeklaration.</summary>
function BodyOf(ADecl: TSyntaxNode; AKind: TSyntaxKind): TSyntaxNode;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ADecl.ChildCount - 1 do
  begin
    if ADecl[mIndex].Kind = AKind then
    begin
      Exit(ADecl[mIndex]);
    end;
  end;
  Result := nil;
end;

/// <summary>Namen der direkten Kinder einer Art, mit Komma.</summary>
function ChildNames(ANode: TSyntaxNode; AKind: TSyntaxKind): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if ANode[mIndex].Kind = AKind then
    begin
      if Result <> '' then
      begin
        Result := Result + ',';
      end;
      Result := Result + ANode[mIndex].Name;
    end;
  end;
end;

function SymbolOf(const AUnit: TUnitIndex; const AName: string): TIndexSymbol;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Container = '') and SameText(mSymbol.Name, AName) then
    begin
      Exit(mSymbol);
    end;
  end;
  raise Exception.CreateFmt('%s fehlt im Index', [AName]);
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

function NewIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText(cUnitHelpers, 'C:\P\Helfer.pas', nil));
end;

{ THelperAncestorsTests }

procedure THelperAncestorsTests.ParsesCaseFour;
var
  mTree: TSyntaxTree;
  mHelper, mOther: TSyntaxNode;
begin
  mTree := TPascalParser.Parse(cCaseFour);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)));
    mHelper := BodyOf(FindType(mTree.Root, 'TMyHelper'), TSyntaxKind.HelperType);
    Assert.IsNotNull(mHelper);
    Assert.AreEqual('class', mHelper.Name);
    // Erst der Vorfahr, zuletzt das Ziel.
    Assert.AreEqual('TBaseHelper,TFoo', ChildNames(mHelper, TSyntaxKind.TypeReference));
    Assert.AreEqual('A', ChildNames(mHelper, TSyntaxKind.RoutineHeader));
    mOther := BodyOf(FindType(mTree.Root, 'TOther'), TSyntaxKind.ClassType);
    Assert.IsNotNull(mOther);
    Assert.AreEqual('B', ChildNames(mOther, TSyntaxKind.RoutineHeader));
  finally
    mTree.Free;
  end;
end;

procedure THelperAncestorsTests.RecordHelperWithAncestor;
var
  mTree: TSyntaxTree;
  mHelper: TSyntaxNode;
begin
  mTree := TPascalParser.Parse('unit R;'#10'interface'#10'type'#10 +
    '  TIntHelper2 = record helper (TIntHelper) for Integer'#10'    function Twice: Integer;'#10'  end;'#10 +
    'implementation'#10'end.');
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)));
    mHelper := BodyOf(FindType(mTree.Root, 'TIntHelper2'), TSyntaxKind.HelperType);
    Assert.IsNotNull(mHelper);
    Assert.AreEqual('record', mHelper.Name);
    Assert.AreEqual('TIntHelper,Integer', ChildNames(mHelper, TSyntaxKind.TypeReference));
  finally
    mTree.Free;
  end;
end;

procedure THelperAncestorsTests.IndexHoldsAncestorAndTarget;
var
  U: TUnitIndex;
  mSymbol: TIndexSymbol;
begin
  U := TIndexExtractor.ExtractText(cCaseFour, 'C:\P\U4.pas', nil);
  mSymbol := SymbolOf(U, 'TMyHelper');
  Assert.AreEqual<TIndexSymbolKind>(TIndexSymbolKind.HelperType, mSymbol.Kind);
  Assert.AreEqual('TBaseHelper,TFoo', string.Join(',', mSymbol.Ancestors));
  mSymbol := SymbolOf(U, 'TOther');
  Assert.AreEqual<TIndexSymbolKind>(TIndexSymbolKind.ClassType, mSymbol.Kind);
  // Keine Felder namens "helper" oder "TFoo" mehr.
  for mSymbol in U.Symbols do
  begin
    Assert.AreNotEqual<TIndexSymbolKind>(TIndexSymbolKind.Field, mSymbol.Kind, mSymbol.Name);
  end;
end;

procedure THelperAncestorsTests.ResolvesMemberOfAncestorHelper;
var
  mIndex: ISymbolIndex;
  mResolver: TNameResolver;
  mTree: TSyntaxTree;
  mFound: TResolvedSymbol;
begin
  mIndex := NewIndex;
  mResolver := TNameResolver.Create(mIndex);
  mTree := TPascalParser.Parse(cUnitMain);
  try
    mFound := mResolver.Resolve(mTree, cMainFile, PositionOf(cUnitMain, 'AsText;'));
    Assert.IsTrue(mFound.Found);
    Assert.AreEqual('TBaseHelper', mFound.Container);
    // Der abgeleitete Helfer verdeckt das gleichnamige Mitglied seines Vorfahren.
    mFound := mResolver.Resolve(mTree, cMainFile, PositionOf(cUnitMain, 'Reset;'));
    Assert.IsTrue(mFound.Found);
    Assert.AreEqual('TFooHelper', mFound.Container);
  finally
    mTree.Free;
    mResolver.Free;
  end;
  mIndex := nil;
end;

procedure THelperAncestorsTests.CandidatesIncludeAncestorHelper;
var
  mIndex: ISymbolIndex;
  mResolver: TNameResolver;
  mTree: TSyntaxTree;
  mCandidate: TResolvedSymbol;
  mListed: string;
begin
  mIndex := NewIndex;
  mResolver := TNameResolver.Create(mIndex);
  mTree := TPascalParser.Parse(cUnitMain);
  try
    mListed := '';
    for mCandidate in mResolver.Candidates.MemberCandidates(mTree, cMainFile, ['Foo'], Pos('Foo.'#10, cUnitMain) + 3) do
    begin
      mListed := mListed + mCandidate.Container + '.' + mCandidate.Name + ' ';
    end;
  finally
    mTree.Free;
    mResolver.Free;
  end;
  mIndex := nil;
  Assert.Contains(mListed, 'TFooHelper.Reset ');
  Assert.Contains(mListed, 'TBaseHelper.AsText ');
  Assert.Contains(mListed, 'TFoo.Name ');
  // Reset nur einmal, aus dem abgeleiteten Helfer.
  Assert.DoesNotContain(mListed, 'TBaseHelper.Reset ');
end;

procedure THelperAncestorsTests.HoverChainNamesAncestorHelper;
var
  mIndex: ISymbolIndex;
  mResolver: TNameResolver;
  mHelper: TResolvedSymbol;
  mChain: TArray<THoverTypeRef>;
  U: TUnitIndex;
begin
  mIndex := NewIndex;
  mResolver := TNameResolver.Create(mIndex);
  try
    U := mIndex.Units[0];
    Assert.IsTrue(mResolver.ResolveTypeFrom(U, 'TFooHelper', mHelper));
    mChain := TLspHoverTypes.Chain(mResolver, mHelper);
    Assert.AreEqual(2, Integer(Length(mChain)));
    Assert.AreEqual('TFooHelper', mChain[0].Name);
    Assert.AreEqual('TBaseHelper', mChain[1].Name);
    // Ein Helfer ohne Vorfahr hat keine Kette; das Ziel ist kein Vorfahr.
    Assert.IsTrue(mResolver.ResolveTypeFrom(U, 'TBaseHelper', mHelper));
    Assert.AreEqual(0, Integer(Length(TLspHoverTypes.Chain(mResolver, mHelper))));
  finally
    mResolver.Free;
  end;
  mIndex := nil;
end;

end.
