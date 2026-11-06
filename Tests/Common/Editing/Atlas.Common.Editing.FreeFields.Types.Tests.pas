unit Atlas.Common.Editing.FreeFields.Types.Tests;

// Tests für die Typauflösung von „Felder im Destruktor freigeben“: Art eines
// Typs, Aliase (auch aus anderen Units über den Index), Vorfahrenkette,
// Komponenten, Feldtypen einer Klasse und Typ eines Felds von Record oder
// Klasse.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFreeFieldTypesTests = class
  public
    [Test]
    procedure GuessesKindsFromFile;
    [Test]
    procedure FollowsAliasesAndFallbacks;
    [Test]
    procedure FollowsAliasesOfOtherUnits;
    [Test]
    procedure ChainEndsAtComponent;
    [Test]
    procedure OwnerByArgument;
    [Test]
    procedure FieldTypesOfClass;
    [Test]
    procedure MemberTypeOfRecordAndClass;
    [Test]
    procedure TextHelpers;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.FreeFields.Types;

const
  cUnit = 'unit U;'#10'interface'#10'type'#10 +
    '  TFoo = class(TBar)'#10'    FList: TList<TFoo>;'#10'    FName: string;'#10'  end;'#10 +
    '  TBar = class(TComponent)'#10'  end;'#10 +
    '  TPlain = class'#10'  end;'#10 +
    '  TPoint3 = record'#10'    X, Y: Integer;'#10'    Thing: IThing;'#10'  end;'#10 +
    '  IThing = interface'#10'  end;'#10 +
    '  TColorSet = set of Byte;'#10 +
    '  TAlias = TPoint3;'#10 +
    'implementation'#10'end.'#10;

function Guess(const AName: string): TTypeGuess;
var
  mTree: TSyntaxTree;
  mTypes: TFreeFieldTypes;
begin
  mTree := TPascalParser.Parse(cUnit);
  mTypes := TFreeFieldTypes.Create(mTree, cUnit, nil);
  try
    Result := mTypes.TypeGuess(AName);
  finally
    mTypes.Free;
    mTree.Free;
  end;
end;

procedure TFreeFieldTypesTests.GuessesKindsFromFile;
begin
  Assert.IsTrue(Guess('TFoo') = tgClass);
  Assert.IsTrue(Guess('TPoint3') = tgRecord);
  Assert.IsTrue(Guess('IThing') = tgInterface);
  Assert.IsTrue(Guess('TColorSet') = tgOther);
end;

procedure TFreeFieldTypesTests.FollowsAliasesAndFallbacks;
begin
  Assert.IsTrue(Guess('TAlias') = tgRecord);
  Assert.IsTrue(Guess('TArray<Integer>') = tgOther);
  Assert.IsTrue(Guess('TStopwatch') = tgRecord);
  Assert.IsTrue(Guess('IUnknownThing') = tgInterface);
  Assert.IsTrue(Guess('TUnknown') = tgUnknown);
end;

procedure TFreeFieldTypesTests.FollowsAliasesOfOtherUnits;
const
  cLage = 'unit Werk.Lage;'#10'interface'#10'type'#10'  TLage = record'#10'    Zeile: Integer;'#10'  end;'#10 +
    'implementation'#10'end.';
  cKurz = 'unit Werk.Kurz;'#10'interface'#10'uses Werk.Lage;'#10'type'#10'  TPos = Werk.Lage.TLage;'#10 +
    '  TLage = Werk.Lage.TLage;'#10'  TFremd = Fremd.TFremd;'#10'implementation'#10'end.';
  cHier = 'unit Hier;'#10'interface'#10'uses Werk.Kurz;'#10'type'#10'  TOrt = Werk.Kurz.TPos;'#10 +
    'implementation'#10'end.';
var
  mIndex: ISymbolIndex;
  mTree: TSyntaxTree;
  mTypes: TFreeFieldTypes;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cLage, 'C:\P\Werk.Lage.pas', nil));
  mIndex.AddUnit(TIndexExtractor.ExtractText(cKurz, 'C:\P\Werk.Kurz.pas', nil));
  mTree := TPascalParser.Parse(cHier);
  mTypes := TFreeFieldTypes.Create(mTree, cHier, mIndex);
  try
    // Alias anderen Namens in einer anderen Unit, gleichen Namens dort und Alias der Datei auf einen davon.
    Assert.IsTrue(mTypes.TypeGuess('TPos') = tgRecord);
    Assert.IsTrue(mTypes.TypeGuess('TLage') = tgRecord);
    Assert.IsTrue(mTypes.TypeGuess('TOrt') = tgRecord);
    // Ziel unbekannt: bleibt unbekannt.
    Assert.IsTrue(mTypes.TypeGuess('TFremd') = tgUnknown);
  finally
    mTypes.Free;
    mTree.Free;
  end;
end;

procedure TFreeFieldTypesTests.ChainEndsAtComponent;
var
  mTree: TSyntaxTree;
  mTypes: TFreeFieldTypes;
  mEndsKnown: Boolean;
begin
  mTree := TPascalParser.Parse(cUnit);
  mTypes := TFreeFieldTypes.Create(mTree, cUnit, nil);
  try
    Assert.AreEqual('TFoo|TBar|TComponent', string.Join('|', mTypes.ComponentChain('TFoo', mEndsKnown)));
    Assert.IsTrue(mEndsKnown);
    Assert.IsTrue(mTypes.IsComponent('TFoo'));
    Assert.IsFalse(mTypes.IsComponent('TPlain'));
    // Klasse ohne Vorfahren: Ende bekannt; unbekannte Klasse: nicht.
    Assert.IsTrue(mTypes.ComponentKnown('TPlain'));
    Assert.IsFalse(mTypes.ComponentKnown('TUnknown'));
  finally
    mTypes.Free;
    mTree.Free;
  end;
end;

procedure TFreeFieldTypesTests.OwnerByArgument;
const
  cCode = 'unit U;'#10'implementation'#10'procedure P;'#10'begin'#10 +
    '  X := TFoo.Create(Self);'#10'  Y := TFoo.Create(Other);'#10'end;'#10'end.'#10;
var
  mTree: TSyntaxTree;
  mTypes: TFreeFieldTypes;
  mArguments: TArray<TSyntaxNode>;
begin
  mTree := TPascalParser.Parse(cCode);
  mTypes := TFreeFieldTypes.Create(mTree, cCode, nil);
  try
    mArguments := nil;
    mTree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := True;
        if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2) then
        begin
          mArguments := mArguments + [ANode[1]];
        end;
      end);
    Assert.AreEqual(2, Integer(Length(mArguments)));
    // Unbekannte Vorfahren: Owner am Argument erkennen.
    Assert.IsTrue(mTypes.OwnedByArgument('TFoo', mArguments[0]));
    Assert.IsFalse(mTypes.OwnedByArgument('TFoo', mArguments[1]));
  finally
    mArguments := nil;
    mTypes.Free;
    mTree.Free;
  end;
end;

procedure TFreeFieldTypesTests.FieldTypesOfClass;
var
  mTree: TSyntaxTree;
  mTypes: TFreeFieldTypes;
begin
  mTree := TPascalParser.Parse(cUnit);
  mTypes := TFreeFieldTypes.Create(mTree, cUnit, nil);
  try
    Assert.AreEqual('TList<TFoo>|string', string.Join('|', mTypes.ClassFieldTypes('TFoo')));
    Assert.AreEqual(0, Integer(Length(mTypes.ClassFieldTypes('TUnknown'))));
  finally
    mTypes.Free;
    mTree.Free;
  end;
end;

procedure TFreeFieldTypesTests.MemberTypeOfRecordAndClass;
var
  mTree: TSyntaxTree;
  mTypes: TFreeFieldTypes;
begin
  mTree := TPascalParser.Parse(cUnit);
  mTypes := TFreeFieldTypes.Create(mTree, cUnit, nil);
  try
    Assert.AreEqual('IThing', mTypes.MemberType('TPoint3', 'thing'));
    Assert.AreEqual('Integer', mTypes.MemberType('TPoint3', 'Y'));
    Assert.AreEqual('TList<TFoo>', mTypes.MemberType('TFoo', 'FList'));
    Assert.AreEqual('', mTypes.MemberType('TPoint3', 'Z'));
    Assert.AreEqual('', mTypes.MemberType('TUnknown', 'X'));
  finally
    mTypes.Free;
    mTree.Free;
  end;
end;

procedure TFreeFieldTypesTests.TextHelpers;
begin
  Assert.AreEqual('TObjectList', TFreeFieldTypes.BaseName(' TObjectList<TOrder> '));
  Assert.AreEqual('a b c', TFreeFieldTypes.Collapse('  a'#9#10' b   c  '));
end;

initialization
  TDUnitX.RegisterTestFixture(TFreeFieldTypesTests);

end.
