unit Atlas.Common.Semantics.TypeIdentity.Tests;

// Tests der Typgleichheit (#1324): Typtext ohne Kommentare und Direktiven,
// eingebaute Aliase der Unit System, Unit-Qualifizierer und Typargumente ohne
// Index; mit Index Aliase über Units hinweg bis zum Ziel, "type A = type B"
// und Zeigertypen als eigene Typen, gleichnamige Typen verschiedener Units und
// unbekannte Namen (Unknown).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTypeIdentityTests = class
  public
    [Test]
    procedure CleanDropsCommentsDirectivesAndEscapes;
    [Test]
    procedure BuiltinAliasesOfSystem;
    [Test]
    procedure SameWithoutIndex;
    [Test]
    procedure DistinctAliasIsDetected;
    [Test]
    procedure AliasesFollowedThroughIndex;
    [Test]
    procedure DistinctAndPointerTypesStay;
    [Test]
    procedure SameNameFromDifferentUnitsDiffers;
    [Test]
    procedure UnknownNameGivesUnknown;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.TypeIdentity;

const
  cFremd = 'unit Fremd;'#10'interface'#10'type'#10'  TPort = UInt16;'#10'  TZahl = TGanz;'#10'  TGanz = Integer;'#10 +
    '  TEigen = type Integer;'#10'  TDaten = record'#10'    N: Integer;'#10'  end;'#10'  PDaten = ^TDaten;'#10 +
    '  TBild = class'#10'  end;'#10'  TListe<T> = class'#10'  end;'#10'  TZahlen = TListe<TZahl>;'#10 +
    'implementation'#10'end.';
  cAndere = 'unit Andere;'#10'interface'#10'type'#10'  TBild = class'#10'  end;'#10'implementation'#10'end.';
  cHaupt = 'unit Haupt;'#10'interface'#10'uses'#10'  Fremd, Andere;'#10'implementation'#10'end.';

/// <summary>Index aus Fremd, Andere und Haupt; AHaupt ist die Unit, aus der aufgelöst wird.</summary>
function NewIndex(out AHaupt: TUnitIndex): ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText(cFremd, 'C:\P\Fremd.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText(cAndere, 'C:\P\Andere.pas', nil));
  AHaupt := TIndexExtractor.ExtractText(cHaupt, 'C:\P\Haupt.pas', nil);
  Result.AddUnit(AHaupt);
end;

/// <summary>Löst Namen so auf, wie sie in AUnit stünden.</summary>
function ChainIn(AResolver: TNameResolver; const AUnit: TUnitIndex): TTypeChainResolver;
begin
  Result :=
    function(const ANames: TArray<string>; out AType: TResolvedSymbol): Boolean
    begin
      Result := AResolver.ResolveTypeTextFrom(AUnit, string.Join('.', ANames), AType);
    end;
end;

/// <summary>Vergleich von ALeft und ARight, beide aufgelöst in Haupt.</summary>
function Compared(const ALeft, ARight: string): TTypeMatch;
var
  mIndex: ISymbolIndex;
  mHaupt: TUnitIndex;
  mResolver: TNameResolver;
  mChain: TTypeChainResolver;
begin
  mIndex := NewIndex(mHaupt);
  mResolver := TNameResolver.Create(mIndex);
  try
    mChain := ChainIn(mResolver, mHaupt);
    Result := TTypeIdentity.Compare(ALeft, ARight, mChain, mChain, mResolver);
    mChain := nil;
  finally
    mResolver.Free;
  end;
end;

{ TTypeIdentityTests }

procedure TTypeIdentityTests.CleanDropsCommentsDirectivesAndEscapes;
begin
  Assert.AreEqual('Boolean', TTypeIdentity.Clean('Boolean { Do not Localize }'));
  Assert.AreEqual('TIdMessageFlagsSet', TTypeIdentity.Clean('{Pointer}TIdMessageFlagsSet'));
  Assert.AreEqual('boolean', TTypeIdentity.Clean('boolean{$endif}'));
  Assert.AreEqual('System.Object', TTypeIdentity.Clean('System.&Object'));
  Assert.AreEqual('array of Byte', TTypeIdentity.Clean('array  of'#10'  Byte // Puffer'));
  Assert.AreEqual('TList<Integer>', TTypeIdentity.Clean('TList < Integer >'));
end;

procedure TTypeIdentityTests.BuiltinAliasesOfSystem;
begin
  Assert.AreEqual('Integer', TTypeIdentity.BuiltinName('Longint'));
  Assert.AreEqual('Integer', TTypeIdentity.BuiltinName('Int32'));
  Assert.AreEqual('Cardinal', TTypeIdentity.BuiltinName('LongWord'));
  Assert.AreEqual('Word', TTypeIdentity.BuiltinName('UInt16'));
  Assert.AreEqual('IInterface', TTypeIdentity.BuiltinName('IUnknown'));
  Assert.AreEqual('string', TTypeIdentity.BuiltinName('UnicodeString'));
  Assert.AreEqual('TKunde', TTypeIdentity.BuiltinName('TKunde'));
end;

procedure TTypeIdentityTests.SameWithoutIndex;
begin
  // Minimalfall F05 und die Muster aus dem Korpus.
  Assert.IsTrue(TTypeIdentity.Same('IInterface', 'IUnknown'));
  Assert.IsTrue(TTypeIdentity.Same('Longint', 'Integer'));
  Assert.IsTrue(TTypeIdentity.Same('integer', 'Int32'));
  Assert.IsTrue(TTypeIdentity.Same('IList<DUnitX.TestFramework.ITestResult>', 'IList<ITestResult>'));
  Assert.IsTrue(TTypeIdentity.Same('TList<System.string>', 'TList<string>'));
  Assert.IsTrue(TTypeIdentity.Same('Classes.TCollection', 'TCollection'));
  Assert.IsTrue(TTypeIdentity.Same('string{', 'string'));
  Assert.IsTrue(TTypeIdentity.Same('pointer{PDocVariantOptions}', 'pointer'));
  // Gegentests: echte Abweichungen.
  Assert.IsFalse(TTypeIdentity.Same('Integer', 'Int64'));
  Assert.IsFalse(TTypeIdentity.Same('TDate', 'TDateTime'));
  Assert.IsFalse(TTypeIdentity.Same('array of Integer', 'TArray<Integer>'));
  Assert.IsFalse(TTypeIdentity.Same('TList<Integer>', 'TList<Int64>'));
end;

procedure TTypeIdentityTests.DistinctAliasIsDetected;
begin
  Assert.IsTrue(TTypeIdentity.IsDistinctAlias('TMyInt = type Integer'));
  Assert.IsTrue(TTypeIdentity.IsDistinctAlias('TMyInt=type'#10'Integer'));
  Assert.IsFalse(TTypeIdentity.IsDistinctAlias('TMyInt = Integer'));
  Assert.IsFalse(TTypeIdentity.IsDistinctAlias('TTyp = TypeInfo'));
end;

procedure TTypeIdentityTests.AliasesFollowedThroughIndex;
begin
  Assert.AreEqual(Ord(TTypeMatch.Same), Ord(Compared('TPort', 'Word')));
  Assert.AreEqual(Ord(TTypeMatch.Same), Ord(Compared('TPort', 'UInt16')));
  // Über zwei Stufen: TZahl = TGanz = Integer.
  Assert.AreEqual(Ord(TTypeMatch.Same), Ord(Compared('TZahl', 'Longint')));
  Assert.AreEqual(Ord(TTypeMatch.Same), Ord(Compared('Fremd.TDaten', 'TDaten')));
  // Alias eines generischen Typs mit Typargument.
  Assert.AreEqual(Ord(TTypeMatch.Same), Ord(Compared('TZahlen', 'TListe<Integer>')));
  Assert.AreEqual(Ord(TTypeMatch.Different), Ord(Compared('TZahl', 'Int64')));
end;

procedure TTypeIdentityTests.DistinctAndPointerTypesStay;
begin
  // type TEigen = type Integer ist ein eigener Typ (Gegentest aus #1324).
  Assert.AreEqual(Ord(TTypeMatch.Different), Ord(Compared('TEigen', 'Integer')));
  Assert.AreEqual(Ord(TTypeMatch.Different), Ord(Compared('PDaten', 'TDaten')));
  Assert.AreEqual(Ord(TTypeMatch.Different), Ord(Compared('PDaten', 'Pointer')));
end;

procedure TTypeIdentityTests.SameNameFromDifferentUnitsDiffers;
begin
  Assert.AreEqual(Ord(TTypeMatch.Different), Ord(Compared('Fremd.TBild', 'Andere.TBild')));
  Assert.AreEqual(Ord(TTypeMatch.Same), Ord(Compared('Andere.TBild', 'Andere.TBild')));
end;

procedure TTypeIdentityTests.UnknownNameGivesUnknown;
begin
  // TUnbekannt kann ein Alias von Integer aus einer Unit außerhalb des Index sein.
  Assert.AreEqual(Ord(TTypeMatch.Unknown), Ord(Compared('TUnbekannt', 'Integer')));
  Assert.AreEqual(Ord(TTypeMatch.Same), Ord(Compared('TUnbekannt', 'Nirgends.TUnbekannt')));
  // Verschiedener Aufbau bleibt verschieden.
  Assert.AreEqual(Ord(TTypeMatch.Different), Ord(Compared('array of TUnbekannt', 'TUnbekannt')));
end;

initialization
  TDUnitX.RegisterTestFixture(TTypeIdentityTests);

end.
