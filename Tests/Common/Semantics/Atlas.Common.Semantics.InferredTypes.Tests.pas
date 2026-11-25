unit Atlas.Common.Semantics.InferredTypes.Tests;

// Tests für die Typableitung von Inline-Variablen, -Konstanten und
// for-in-Laufvariablen ohne Typangabe (#453).

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  [TestFixture]
  TInferredTypesTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Literal, Funktion, Array, Enumerator, String und Konstante; mit Typangabe nichts.</summary>
    [Test]
    procedure FindsInlineForInAndConstants;
    /// <summary>At trifft nur auf dem Namen der Variablen.</summary>
    [Test]
    procedure AtMatchesOnlyTheName;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.InferredTypes,
  Atlas.Common.Semantics.InferredTypes.TestSupport;

function Describe(const AFound: TArray<TInferredType>): string;
var
  mFound: TInferredType;
begin
  Result := '';
  for mFound in AFound do
  begin
    Result := Result + Format('%d:%d %s: %s|', [mFound.NameEnd.Line, mFound.NameEnd.Character, mFound.Name,
      mFound.TypeName]);
  end;
end;

{ TInferredTypesTests }

procedure TInferredTypesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitDaten, cDatenFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitQuelle, cQuelleFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TInferredTypesTests.TearDown;
begin
  FResolver.Free;
  FResolver := nil;
  FIndex := nil;
end;

procedure TInferredTypesTests.FindsInlineForInAndConstants;
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(cUnitNutzer);
  try
    Assert.AreEqual('9:7 X: TDaten|10:11 Z: Integer|12:11 K: TDaten|14:11 C: Char|16:9 N: Integer|',
      Describe(TInferredTypes.Find(FResolver, mTree, cNutzerFile, TTextRange.Create(0, 0, 100, 0))));
    // Nur der Bereich: Zeilen 9 bis 10.
    Assert.AreEqual('9:7 X: TDaten|10:11 Z: Integer|',
      Describe(TInferredTypes.Find(FResolver, mTree, cNutzerFile, TTextRange.Create(9, 0, 10, 100))));
  finally
    mTree.Free;
  end;
end;

procedure TInferredTypesTests.AtMatchesOnlyTheName;
var
  mTree: TSyntaxTree;
  mFound: TInferredType;
begin
  mTree := TSyntaxTreeCache.Parse(cUnitNutzer);
  try
    Assert.IsTrue(TInferredTypes.At(FResolver, mTree, cNutzerFile, TTextPosition.Create(9, 6), mFound));
    Assert.AreEqual('TDaten', mFound.TypeName);
    Assert.IsFalse(mFound.ForIn);
    Assert.IsTrue(TInferredTypes.At(FResolver, mTree, cNutzerFile, TTextPosition.Create(12, 10), mFound));
    Assert.IsTrue(mFound.ForIn);
    // Hinter dem Namen und bei Typangabe nichts.
    Assert.IsFalse(TInferredTypes.At(FResolver, mTree, cNutzerFile, TTextPosition.Create(9, 12), mFound));
    Assert.IsFalse(TInferredTypes.At(FResolver, mTree, cNutzerFile, TTextPosition.Create(17, 10), mFound));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TInferredTypesTests);

end.
