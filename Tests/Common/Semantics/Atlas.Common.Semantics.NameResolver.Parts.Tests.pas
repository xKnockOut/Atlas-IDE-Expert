unit Atlas.Common.Semantics.NameResolver.Parts.Tests;

// Tests der Teile von TNameResolver einzeln (Stelle, Units, Nachschlagen, Typen, Mitglieder, lokale Namen,
// Ausdrücke, Ketten, Kandidaten, fehlende Interface-Methoden, Abfragen, Kern). Das Verhalten der Fassade prüfen
// Atlas.Common.Semantics.NameResolver.Tests und NameResolver.LanguageFeatures.Tests.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver.Core;

type
  [TestFixture]
  TResolverPartsTests = class
  private
    FIndex: ISymbolIndex;
    FCore: TResolverCore;
    FTree: TSyntaxTree;
    procedure AddUnit(const AFileName, AText: string);
    procedure MoveTo(const AMarker: string);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TextSplitsAndBindsTypeArguments;
    [Test]
    procedure TextKnowsArgumentsAndClassReferences;
    [Test]
    procedure SymbolsDescribeShadowedDeclarations;
    [Test]
    procedure PlaceKnowsTheSection;
    [Test]
    procedure UnitsFindIndexedUnits;
    [Test]
    procedure LookupFindsNamesThroughUses;
    [Test]
    procedure TypingKnowsMethodClassAndAncestor;
    [Test]
    procedure MembersIncludeInheritedOnes;
    [Test]
    procedure LocalsFindParameters;
    [Test]
    procedure ExpressionsSelectOverloadsByArgumentCount;
    [Test]
    procedure ChainsResolveMemberChains;
    [Test]
    procedure CandidateListMergesOverloadsAndShadows;
    [Test]
    procedure CandidatesListOwnAndUsedScope;
    [Test]
    procedure UnqualifyRemovesUnitPrefixes;
    [Test]
    procedure QueriesListMissingInterfaceMembers;
    [Test]
    procedure CoreInfersInlineVariableTypes;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.NameResolver.Symbols,
  Atlas.Common.Semantics.NameResolver.Place,
  Atlas.Common.Semantics.NameResolver.Units,
  Atlas.Common.Semantics.NameResolver.Lookup,
  Atlas.Common.Semantics.NameResolver.Typing,
  Atlas.Common.Semantics.NameResolver.Members,
  Atlas.Common.Semantics.NameResolver.Locals,
  Atlas.Common.Semantics.NameResolver.Expressions,
  Atlas.Common.Semantics.NameResolver.Chains,
  Atlas.Common.Semantics.NameResolver.Candidates,
  Atlas.Common.Semantics.NameResolver.InterfaceMembers,
  Atlas.Common.Semantics.NameResolver.Queries;

const
  cMainFile = 'C:\P\Haupt.pas';

  cUnitSystem =
    'unit System;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TObject = class'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '    procedure Free;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

  cUnitBasis =
    'unit Basis;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TBasis = class'#10 +
    '  public'#10 +
    '    FName: string;'#10 +
    '    procedure Melde;'#10 +
    '  end;'#10 +
    'function Wert: Integer;'#10 +
    'implementation'#10 +
    'function Wert: Integer; begin Result := 1; end;'#10 +
    'procedure TBasis.Melde; begin end;'#10 +
    'end.';

  cUnitMain =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Basis;'#10 +
    'type'#10 +
    '  TKunde = class(TBasis)'#10 +
    '    procedure Tu(AZahl: Integer);'#10 +
    '  end;'#10 +
    '  IZaehler = interface'#10 +
    '    procedure Zaehle;'#10 +
    '    function Stand: Integer;'#10 +
    '  end;'#10 +
    '  TZaehler = class(TInterfacedObject, IZaehler)'#10 +
    '    procedure Zaehle;'#10 +
    '  end;'#10 +
    'var G: TKunde;'#10 +
    'implementation'#10 +
    'procedure TKunde.Tu(AZahl: Integer);'#10 +
    'begin'#10 +
    '  var mNeu := TKunde.Create;'#10 +
    '  G.Melde; {M}'#10 +
    'end;'#10 +
    'procedure TZaehler.Zaehle; begin end;'#10 +
    'end.';

/// <summary>Routine ohne Unit mit AArgs Parametern ohne Typ.</summary>
function Routine(AArgs: Integer): TResolvedSymbol;
begin
  Result := TResolvedSymbol.Empty;
  Result.Kind := TResolvedKind.Symbol;
  Result.Name := 'Rechne';
  Result.SymbolKind := TIndexSymbolKind.Routine;
  Result.MinArgs := AArgs;
  Result.MaxArgs := AArgs;
end;

procedure TResolverPartsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  AddUnit('C:\Lib\System.pas', cUnitSystem);
  AddUnit('C:\P\Basis.pas', cUnitBasis);
  AddUnit(cMainFile, cUnitMain);
  FCore := TResolverCore.Create(FIndex, nil, nil);
  FTree := TPascalParser.Parse(cUnitMain);
end;

procedure TResolverPartsTests.TearDown;
begin
  FCore.Free;
  FTree.Free;
  FIndex := nil;
end;

procedure TResolverPartsTests.AddUnit(const AFileName, AText: string);
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(AText, AFileName, nil));
end;

procedure TResolverPartsTests.MoveTo(const AMarker: string);
begin
  FCore.Place.MoveTo(FTree, cMainFile, Pos(AMarker, cUnitMain) - 1);
end;

procedure TResolverPartsTests.TextSplitsAndBindsTypeArguments;
var
  mArgs: TArray<string>;
begin
  mArgs := TResolverText.SplitArgs('TPair<A, B>, C');
  Assert.AreEqual(2, Integer(Length(mArgs)));
  Assert.AreEqual('TPair<A, B>', mArgs[0]);
  Assert.AreEqual('TList<TKunde>', TResolverText.Substitute('TList<T>',
    TResolverText.Bind('T', TArray<string>.Create('TKunde'))));
end;

procedure TResolverPartsTests.TextKnowsArgumentsAndClassReferences;
begin
  Assert.IsTrue(TResolverText.ArgumentFits('Double', 'Integer'));
  Assert.IsTrue(TResolverText.ArgumentFits('string', 'Char'));
  Assert.IsFalse(TResolverText.ArgumentFits('Integer', 'string'));
  Assert.AreEqual('Exception', TResolverText.ClassRefTarget('ExceptClass = class of Exception;'));
  Assert.IsTrue(TResolverText.LooksLikeException('System.SysUtils.EFehler'));
  Assert.IsFalse(TResolverText.LooksLikeException('Eagle'));
end;

procedure TResolverPartsTests.SymbolsDescribeShadowedDeclarations;
var
  mSymbol: TResolvedSymbol;
begin
  mSymbol := TResolvedSymbol.Empty;
  mSymbol.Kind := TResolvedKind.Local;
  mSymbol.Name := 'X';
  mSymbol.IsParameter := True;
  Assert.AreEqual('Parameter X', mSymbol.ShadowText);
  mSymbol.Kind := TResolvedKind.Symbol;
  mSymbol.Container := 'TKunde';
  mSymbol.SymbolKind := TIndexSymbolKind.Field;
  Assert.AreEqual('Feld TKunde.X', mSymbol.ShadowText);
end;

procedure TResolverPartsTests.PlaceKnowsTheSection;
var
  mMoves: Integer;
begin
  MoveTo('G: TKunde');
  Assert.IsFalse(FCore.Place.InImplementation);
  MoveTo('{M}');
  Assert.IsTrue(FCore.Place.InImplementation);
  Assert.AreEqual('Haupt', FCore.Place.Current.UnitName);
  mMoves := FCore.Place.MoveCount;
  FCore.Place.MoveToUnit(FCore.Place.Current);
  Assert.IsTrue(FCore.Place.MoveCount > mMoves);
  Assert.IsTrue(FCore.Place.Tree = nil);
end;

procedure TResolverPartsTests.UnitsFindIndexedUnits;
var
  mUnit: TUnitIndex;
begin
  Assert.IsTrue(FCore.Units.FindUnit('Basis', mUnit));
  Assert.AreEqual('Basis', mUnit.UnitName);
  Assert.IsFalse(FCore.Units.FindUnit('Fehlt', mUnit));
  MoveTo('{M}');
  Assert.IsTrue(Pos('Basis', string.Join(',', FCore.Units.ScopeUnits(FCore.Place.Current, True))) > 0);
end;

procedure TResolverPartsTests.LookupFindsNamesThroughUses;
var
  mFound: TResolvedSymbol;
begin
  MoveTo('{M}');
  Assert.IsTrue(FCore.Lookup.LookupGlobal(FCore.Place.Current, 'Wert', True, False, mFound));
  Assert.AreEqual('Basis', mFound.UnitName);
  Assert.AreEqual('Basis.TBasis', FCore.Lookup.QualifyType('TBasis', FCore.Place.Current, True));
end;

procedure TResolverPartsTests.TypingKnowsMethodClassAndAncestor;
var
  mClass, mAncestor: TResolvedSymbol;
begin
  MoveTo('{M}');
  Assert.IsTrue(FCore.Typing.CurrentClass(mClass));
  Assert.AreEqual('TKunde', mClass.Name);
  Assert.IsTrue(FCore.Typing.AncestorOf(mClass, mAncestor));
  Assert.AreEqual('TBasis', mAncestor.Name);
end;

procedure TResolverPartsTests.MembersIncludeInheritedOnes;
var
  mClass: TResolvedSymbol;
  mMembers: TArray<TResolvedSymbol>;
begin
  MoveTo('{M}');
  Assert.IsTrue(FCore.Typing.CurrentClass(mClass));
  mMembers := FCore.Members.FindMembers(mClass, 'Melde');
  Assert.AreEqual(1, Integer(Length(mMembers)));
  Assert.AreEqual('TBasis', mMembers[0].Container);
end;

procedure TResolverPartsTests.LocalsFindParameters;
var
  mLocal: TResolvedSymbol;
begin
  MoveTo('{M}');
  Assert.IsTrue(FCore.Locals.LookupLocal('AZahl', mLocal));
  Assert.IsTrue(mLocal.Kind = TResolvedKind.Local);
  Assert.IsTrue(mLocal.IsParameter);
end;

procedure TResolverPartsTests.ExpressionsSelectOverloadsByArgumentCount;
var
  mSelected: TArray<TResolvedSymbol>;
begin
  mSelected := FCore.Expressions.SelectOverloads(TArray<TResolvedSymbol>.Create(Routine(1), Routine(2)), 2, nil);
  Assert.AreEqual(1, Integer(Length(mSelected)));
  Assert.AreEqual(2, mSelected[0].MaxArgs);
end;

procedure TResolverPartsTests.ChainsResolveMemberChains;
var
  mField: TResolvedSymbol;
  mChain: TResolvedChainType;
begin
  mField := FCore.Chains.ResolveChain(FTree, cMainFile, TArray<string>.Create('G', 'FName'),
    Pos('{M}', cUnitMain) - 1, False);
  Assert.AreEqual('FName', mField.Name);
  Assert.AreEqual('TBasis', mField.Container);
  Assert.IsTrue(FCore.Chains.ChainType(FTree, cMainFile, TArray<string>.Create('G'), Pos('{M}', cUnitMain) - 1,
    mChain));
  Assert.IsTrue(mChain.TypeFound);
  Assert.AreEqual('TKunde', mChain.TypeInfo.Name);
end;

procedure TResolverPartsTests.CandidateListMergesOverloadsAndShadows;
var
  mList: TResolverCandidateList;
  mSymbol, mOther: TResolvedSymbol;
  mItems: TArray<TResolvedSymbol>;
begin
  mSymbol := Routine(1);
  mSymbol.ParamTypes := TArray<string>.Create('Integer');
  mOther := mSymbol;
  mOther.ParamTypes := TArray<string>.Create('string');
  mList := TResolverCandidateList.Create;
  try
    mList.Add(mSymbol);
    mList.Add(mOther);
    mOther.Kind := TResolvedKind.Local;
    mOther.IsParameter := True;
    mList.Add(mOther);
    mItems := mList.ToArray;
  finally
    mList.Free;
  end;
  Assert.AreEqual(1, Integer(Length(mItems)));
  Assert.AreEqual(1, Integer(Length(mItems[0].Overloads)));
  Assert.AreEqual(1, Integer(Length(mItems[0].Hides)));
  Assert.AreEqual('Parameter Rechne', mItems[0].Hides[0]);
end;

procedure TResolverPartsTests.CandidatesListOwnAndUsedScope;
var
  mNames: string;
  mSymbol: TResolvedSymbol;
begin
  mNames := '';
  for mSymbol in FCore.Candidates.OwnScopeCandidates(FTree, cMainFile, Pos('{M}', cUnitMain) - 1) do
  begin
    mNames := mNames + mSymbol.Name + ',';
  end;
  Assert.IsTrue(Pos('AZahl,', mNames) > 0);
  Assert.IsTrue(Pos('Self,', mNames) > 0);
  mNames := '';
  for mSymbol in FCore.Candidates.UsedScopeCandidates do
  begin
    mNames := mNames + mSymbol.Name + ',';
  end;
  Assert.IsTrue(Pos('Wert,', mNames) > 0);
end;

procedure TResolverPartsTests.UnqualifyRemovesUnitPrefixes;
begin
  Assert.AreEqual('TBasis<TObject>', TResolverUnqualify.TypeText(FIndex, 'Basis.TBasis<System.TObject>', ''));
  Assert.AreEqual('TEigen', TResolverUnqualify.TypeText(FIndex, 'Eigen.TEigen', 'Eigen'));
  Assert.AreEqual('Fremd.TTyp', TResolverUnqualify.TypeText(FIndex, 'Fremd.TTyp', ''));
end;

procedure TResolverPartsTests.QueriesListMissingInterfaceMembers;
var
  mMain: TUnitIndex;
  mMissing: TArray<TResolvedSymbol>;
  mComplete: Boolean;
begin
  Assert.IsTrue(FCore.Units.FindUnit('Haupt', mMain));
  mMissing := FCore.Queries.MissingInterfaceMembers(mMain, 'TZaehler', nil, nil, mComplete);
  Assert.AreEqual(1, Integer(Length(mMissing)));
  Assert.AreEqual('Stand', mMissing[0].Name);
  Assert.IsTrue(mComplete);
end;

procedure TResolverPartsTests.CoreInfersInlineVariableTypes;
var
  mLocal, mType: TResolvedSymbol;
  mConsumed: Integer;
begin
  Assert.IsTrue(Assigned(FCore.Typing.Infer));
  MoveTo('{M}');
  Assert.IsTrue(FCore.Expressions.ResolveFirst(TArray<string>.Create('mNeu'), mConsumed, mLocal), 'mNeu');
  Assert.IsTrue(FCore.Typing.TypeOf(mLocal, mType), 'Typ von mNeu');
  Assert.AreEqual('TKunde', mType.Name);
end;

initialization
  TDUnitX.RegisterTestFixture(TResolverPartsTests);

end.
