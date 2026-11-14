unit Atlas.Common.Lsp.Internals.CompletionSource.Tests;

// Helfer der Vervollständigung über den Index der eigenen Unit.

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
  cUnitText =
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
  Result := TIndexExtractor.ExtractText(cUnitText, 'C:\P\Haupt.pas', nil);
end;

procedure TCompletionSourceTests.EnclosingTypeFindsInnermost;
var
  mSymbol: TIndexSymbol;
begin
  Assert.IsTrue(EnclosingTypeAt(UnitOf, 5, [TIndexSymbolKind.ClassType], 0, True, mSymbol));
  Assert.AreEqual('TInnen', mSymbol.Name);
  Assert.AreEqual('TAussen.TInnen', QualifiedTypeName(mSymbol));
  Assert.IsTrue(EnclosingTypeAt(UnitOf, 7, [TIndexSymbolKind.ClassType], 0, True, mSymbol));
  Assert.AreEqual('TAussen', QualifiedTypeName(mSymbol));
  // Andere Art: kein Treffer.
  Assert.IsFalse(EnclosingTypeAt(UnitOf, 5, [TIndexSymbolKind.RecordType], 0, True, mSymbol));
end;

procedure TCompletionSourceTests.EnclosingTypeHonoursEnd;
var
  mSymbol: TIndexSymbol;
begin
  // Zeile 17 ist das "end;" von TImpl: mit AInclusiveEnd noch drin, sonst nicht.
  Assert.IsTrue(EnclosingTypeAt(UnitOf, 17, [TIndexSymbolKind.ClassType], 0, True, mSymbol));
  Assert.AreEqual('TImpl', mSymbol.Name);
  Assert.IsFalse(EnclosingTypeAt(UnitOf, 17, [TIndexSymbolKind.ClassType], 0, False, mSymbol));
  Assert.IsTrue(EnclosingTypeAt(UnitOf, 16, [TIndexSymbolKind.ClassType], 0, False, mSymbol));
  // Kopfzeile zählt nicht.
  Assert.IsFalse(EnclosingTypeAt(UnitOf, 15, [TIndexSymbolKind.ClassType], 0, True, mSymbol));
end;

procedure TCompletionSourceTests.EnclosingTypeNeedsAncestors;
var
  mSymbol: TIndexSymbol;
begin
  // TImpl hat Vorfahr und Interface, TAussen keinen Vorfahren in der Liste.
  Assert.IsTrue(EnclosingTypeAt(UnitOf, 16, [TIndexSymbolKind.ClassType], 2, False, mSymbol));
  Assert.AreEqual('TImpl', mSymbol.Name);
  Assert.IsFalse(EnclosingTypeAt(UnitOf, 7, [TIndexSymbolKind.ClassType], 2, False, mSymbol));
end;

procedure TCompletionSourceTests.TypeChainFollowsAncestors;
var
  mIndex: ISymbolIndex;
  mResolver: TNameResolver;
  mChain: TArray<string>;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(UnitOf);
  mResolver := TNameResolver.Create(mIndex);
  try
    mChain := TypeChain(mResolver, UnitOf, 'TImpl');
    Assert.IsTrue(Length(mChain) >= 3, string.Join(',', mChain));
    Assert.AreEqual('TImpl,TMitte,TBasis', string.Join(',', Copy(mChain, 0, 3)));
  finally
    mResolver.Free;
  end;
end;

procedure TCompletionSourceTests.TypeChainStopsAtUnknown;
var
  mIndex: ISymbolIndex;
  mResolver: TNameResolver;
  mChain: TArray<string>;
begin
  mIndex := TSymbolIndex.Create;
  mResolver := TNameResolver.Create(mIndex);
  try
    mChain := TypeChain(mResolver, UnitOf, 'TUnbekannt');
    Assert.AreEqual('TUnbekannt', string.Join(',', mChain));
  finally
    mResolver.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCompletionSourceTests);

end.
