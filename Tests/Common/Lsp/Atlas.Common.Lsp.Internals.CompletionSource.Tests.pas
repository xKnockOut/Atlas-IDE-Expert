unit Atlas.Common.Lsp.Internals.CompletionSource.Tests;

// Helfer der Vervollständigung über den Index der eigenen Unit (Code-Review D-09, Block H Schritt 2).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCompletionSourceTests = class
  public
    [Test]
    procedure EnclosingTypeFindsInnermost;
    [Test]
    procedure EnclosingTypeHonoursEnd;
    [Test]
    procedure EnclosingTypeNeedsAncestors;
    [Test]
    procedure TypeChainFollowsAncestors;
    [Test]
    procedure TypeChainStopsAtUnknown;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Internals.CompletionSource;

const
  // Zeile 4: im Rumpf von TInnen, Zeile 6: "end;" von TInnen, Zeile 8: "end;" von TAussen.
  UnitText =
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TAussen = class'#13#10 +
    '  type TInnen = class'#13#10 +
    '    Wert: Integer;'#13#10 +
    '  end;'#13#10 +
    '    Name: string;'#13#10 +
    '  end;'#13#10 +
    '  IFoo = interface'#13#10 +
    '  end;'#13#10 +
    '  TBasis = class'#13#10 +
    '  end;'#13#10 +
    '  TMitte = class(TBasis)'#13#10 +
    '  end;'#13#10 +
    '  TImpl = class(TMitte, IFoo)'#13#10 +
    '    X: Integer;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';

function UnitOf: TUnitIndex;
begin
  Result := TIndexExtractor.ExtractText(UnitText, 'C:\P\Haupt.pas', nil);
end;

procedure TCompletionSourceTests.EnclosingTypeFindsInnermost;
var
  Symbol: TIndexSymbol;
begin
  Assert.IsTrue(EnclosingTypeAt(UnitOf, 5, [TIndexSymbolKind.ClassType], 0, True, Symbol));
  Assert.AreEqual('TInnen', Symbol.Name);
  Assert.AreEqual('TAussen.TInnen', QualifiedTypeName(Symbol));
  Assert.IsTrue(EnclosingTypeAt(UnitOf, 7, [TIndexSymbolKind.ClassType], 0, True, Symbol));
  Assert.AreEqual('TAussen', QualifiedTypeName(Symbol));
  // Andere Art: kein Treffer.
  Assert.IsFalse(EnclosingTypeAt(UnitOf, 5, [TIndexSymbolKind.RecordType], 0, True, Symbol));
end;

procedure TCompletionSourceTests.EnclosingTypeHonoursEnd;
var
  Symbol: TIndexSymbol;
begin
  // Zeile 17 ist das "end;" von TImpl: mit AInclusiveEnd noch drin, sonst nicht.
  Assert.IsTrue(EnclosingTypeAt(UnitOf, 17, [TIndexSymbolKind.ClassType], 0, True, Symbol));
  Assert.AreEqual('TImpl', Symbol.Name);
  Assert.IsFalse(EnclosingTypeAt(UnitOf, 17, [TIndexSymbolKind.ClassType], 0, False, Symbol));
  Assert.IsTrue(EnclosingTypeAt(UnitOf, 16, [TIndexSymbolKind.ClassType], 0, False, Symbol));
  // Kopfzeile zählt nicht.
  Assert.IsFalse(EnclosingTypeAt(UnitOf, 15, [TIndexSymbolKind.ClassType], 0, True, Symbol));
end;

procedure TCompletionSourceTests.EnclosingTypeNeedsAncestors;
var
  Symbol: TIndexSymbol;
begin
  // TImpl hat Vorfahr und Interface, TAussen keinen Vorfahren in der Liste.
  Assert.IsTrue(EnclosingTypeAt(UnitOf, 16, [TIndexSymbolKind.ClassType], 2, False, Symbol));
  Assert.AreEqual('TImpl', Symbol.Name);
  Assert.IsFalse(EnclosingTypeAt(UnitOf, 7, [TIndexSymbolKind.ClassType], 2, False, Symbol));
end;

procedure TCompletionSourceTests.TypeChainFollowsAncestors;
var
  Index: ISymbolIndex;
  Resolver: TNameResolver;
  Chain: TArray<string>;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(UnitOf);
  Resolver := TNameResolver.Create(Index);
  try
    Chain := TypeChain(Resolver, UnitOf, 'TImpl');
    Assert.IsTrue(Length(Chain) >= 3, string.Join(',', Chain));
    Assert.AreEqual('TImpl,TMitte,TBasis', string.Join(',', Copy(Chain, 0, 3)));
  finally
    Resolver.Free;
  end;
end;

procedure TCompletionSourceTests.TypeChainStopsAtUnknown;
var
  Index: ISymbolIndex;
  Resolver: TNameResolver;
  Chain: TArray<string>;
begin
  Index := TSymbolIndex.Create;
  Resolver := TNameResolver.Create(Index);
  try
    Chain := TypeChain(Resolver, UnitOf, 'TUnbekannt');
    Assert.AreEqual('TUnbekannt', string.Join(',', Chain));
  finally
    Resolver.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCompletionSourceTests);

end.
