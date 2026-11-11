unit Atlas.Common.Semantics.UsesUsage.Tests;

// Tests der Nutzung der uses-Einträge über die Namensauflösung (#1925):
// Ein Mitgliedsname (Count) hält die Unit seiner Klasse nicht, eine eigene
// Deklaration verdeckt die Unit, bei gleichem Namen gewinnt die letzte Unit,
// qualifizierter Zugriff und Enum-Werte halten ihre Unit, Überladungen aus
// mehreren Units halten alle, ein Helper hält seine Unit, der Rumpf einer
// gerufenen inline-Routine hält die Unit, die er braucht (H2443), nicht
// auflösbare Namen fallen auf den Namensvergleich zurück, ein Attribut ohne
// Endung ([Pruef]) hält seine Unit. Dazu die Aufteilung
// der Namen in UnitInfo, der Fall ohne Index und mit Syntaxfehlern sowie
// SameUnit über Namespaces.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TUsesUsageTests = class
  public
    [Test]
    procedure MemberNameDoesNotKeepUnit;
    [Test]
    procedure OwnDeclarationHidesUnit;
    [Test]
    procedure LastUnitWins;
    [Test]
    procedure QualifiedAccessKeepsUnit;
    [Test]
    procedure EnumValueKeepsUnit;
    [Test]
    procedure OverloadsKeepAllUnits;
    [Test]
    procedure HelperKeepsUnit;
    [Test]
    procedure InlineBodyKeepsUnit;
    [Test]
    procedure AttributeKeepsUnit;
    [Test]
    procedure UnresolvedNameFallsBack;
    [Test]
    procedure InterfaceUseIsQuiet;
    [Test]
    procedure UnitInfoSplitsNames;
    [Test]
    procedure WithoutIndexOrWithSyntaxErrorIsInactive;
    [Test]
    procedure SameUnitUsesNamespaces;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.UsesActions,
  Atlas.Common.Semantics.InlineCallees,
  Atlas.Common.Semantics.UsesUsage;

const
  cListe = 'unit Liste;'#10'interface'#10'type'#10'  TListe = class'#10'  public'#10 +
    '    function Count: Integer;'#10'    procedure Add(A: Integer);'#10'  end;'#10'implementation'#10 +
    'function TListe.Count: Integer;'#10'begin'#10'  Result := 0;'#10'end;'#10 +
    'procedure TListe.Add(A: Integer);'#10'begin'#10'end;'#10'end.';
  cMathe = 'unit Mathe;'#10'interface'#10'function Max(A, B: Integer): Integer;'#10'implementation'#10 +
    'function Max(A, B: Integer): Integer;'#10'begin'#10'  Result := A;'#10'end;'#10'end.';
  cErste = 'unit Erste;'#10'interface'#10'procedure Tu;'#10'implementation'#10 +
    'procedure Tu;'#10'begin'#10'end;'#10'end.';
  cZweite = 'unit Zweite;'#10'interface'#10'procedure Tu;'#10'implementation'#10 +
    'procedure Tu;'#10'begin'#10'end;'#10'end.';
  cUeberEins = 'unit UeberEins;'#10'interface'#10'procedure Mach(A: Integer); overload;'#10'implementation'#10 +
    'procedure Mach(A: Integer);'#10'begin'#10'end;'#10'end.';
  cUeberZwei = 'unit UeberZwei;'#10'interface'#10'procedure Mach(const A: string); overload;'#10'implementation'#10 +
    'procedure Mach(const A: string);'#10'begin'#10'end;'#10'end.';
  cHelfer = 'unit Helfer;'#10'interface'#10'type'#10'  TZahlHelfer = record helper for Integer'#10 +
    '    function Doppelt: Integer;'#10'  end;'#10'implementation'#10 +
    'function TZahlHelfer.Doppelt: Integer;'#10'begin'#10'  Result := Self * 2;'#10'end;'#10'end.';
  cTypen = 'unit Typen;'#10'interface'#10'type'#10'  TFarbe = (Rot, Gruen);'#10'implementation'#10'end.';
  cBasis = 'unit Basis;'#10'interface'#10'function Grund: Integer;'#10'implementation'#10 +
    'function Grund: Integer;'#10'begin'#10'  Result := 1;'#10'end;'#10'end.';
  cSchnell = 'unit Schnell;'#10'interface'#10'function Flott: Integer; inline;'#10'implementation'#10 +
    'uses Basis;'#10'function Flott: Integer;'#10'begin'#10'  Result := Grund;'#10'end;'#10'end.';
  cMerkmal = 'unit Merkmal;'#10'interface'#10'type'#10'  PruefAttribute = class(TCustomAttribute)'#10 +
    '  end;'#10'implementation'#10'end.';
  cLangsam = 'unit Langsam;'#10'interface'#10'function Flott: Integer;'#10'implementation'#10 +
    'uses Basis;'#10'function Flott: Integer;'#10'begin'#10'  Result := Grund;'#10'end;'#10'end.';

function NewIndex: ISymbolIndex;
const
  cUnits: array[0..11] of string = (cListe, cMathe, cErste, cZweite, cUeberEins, cUeberZwei, cHelfer, cTypen,
    cBasis, cSchnell, cLangsam, cMerkmal);
var
  mText, mName: string;
begin
  Result := TSymbolIndex.Create;
  for mText in cUnits do
  begin
    mName := Copy(mText, 6, Pos(';', mText) - 6);
    Result.AddUnit(TIndexExtractor.ExtractText(mText, mName + '.pas', nil));
  end;
end;

/// <summary>Unit Bericht mit AUses im interface und der Routine Lauf (lokale Deklarationen AVar, Rumpf ABody);
/// ADecl steht davor im implementation-Teil.</summary>
function Bericht(const AUses, ADecl, AVar, ABody: string): string;
begin
  Result := 'unit Bericht;'#10'interface'#10'uses ' + AUses + ';'#10'implementation'#10 + ADecl +
    'procedure Lauf;'#10 + AVar + 'begin'#10 + ABody + 'end;'#10'end.';
end;

function StateName(AState: TUsesEntryState): string;
begin
  case AState of
    TUsesEntryState.Unused:
      Result := 'unused';
    TUsesEntryState.OnlyImplementation:
      Result := 'impl';
    TUsesEntryState.KeptForInitialization:
      Result := 'init';
  else
    Result := 'keep';
  end;
end;

/// <summary>Auffällige Einträge "Name=Zustand;" mit Namensauflösung, ohne sie (AResolved False) wie vor #1925.
/// </summary>
function States(const AText: string; AResolved: Boolean): string;
var
  mIndex: ISymbolIndex;
  mInfo: TUsesUnitInfoFunc;
  mSource: TUsesUsageSource;
  mTree: TSyntaxTree;
  mResolution: TUsesResolution;
  mEntry: TUsesEntry;
begin
  Result := '';
  mIndex := NewIndex;
  mInfo := TUsesUsage.UnitInfo(mIndex, nil, nil);
  mSource := Default(TUsesUsageSource);
  mSource.Index := mIndex;
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)), 'Syntaxfehler im Testtext');
    mResolution := Default(TUsesResolution);
    if AResolved then
    begin
      mResolution := TUsesUsage.Resolve(mSource, mTree, 'Bericht.pas', nil, mInfo);
      Assert.IsTrue(mResolution.Active);
    end;
    for mEntry in TUsesActions.Entries(mTree.Tokens, nil, mInfo, nil, mResolution) do
    begin
      Result := Result + mEntry.Name + '=' + StateName(mEntry.State) + ';';
    end;
  finally
    mTree.Free;
  end;
end;

procedure TUsesUsageTests.MemberNameDoesNotKeepUnit;
var
  mText: string;
begin
  // Count ist hier eine lokale Variable; TListe.Count aus Liste ist nicht gemeint. Der bloße Namensvergleich hielt
  // Liste für benutzt.
  mText := Bericht('Liste, Mathe', '', 'var'#10'  Count: Integer;'#10, '  Count := Max(1, 2);'#10);
  Assert.AreEqual('Liste=unused;Mathe=impl;', States(mText, True));
  Assert.AreEqual('Liste=impl;Mathe=impl;', States(mText, False));
end;

procedure TUsesUsageTests.OwnDeclarationHidesUnit;
begin
  Assert.AreEqual('Mathe=unused;', States(Bericht('Mathe', 'function Max(A, B: Integer): Integer;'#10'begin'#10 +
    '  Result := B;'#10'end;'#10, '', '  Max(1, 2);'#10), True));
end;

procedure TUsesUsageTests.LastUnitWins;
begin
  Assert.AreEqual('Erste=unused;Zweite=impl;', States(Bericht('Erste, Zweite', '', '', '  Tu;'#10), True));
  Assert.AreEqual('Zweite=unused;Erste=impl;', States(Bericht('Zweite, Erste', '', '', '  Tu;'#10), True));
end;

procedure TUsesUsageTests.QualifiedAccessKeepsUnit;
begin
  Assert.AreEqual('Erste=impl;Zweite=unused;', States(Bericht('Erste, Zweite', '', '', '  Erste.Tu;'#10), True));
end;

procedure TUsesUsageTests.EnumValueKeepsUnit;
begin
  Assert.AreEqual('Typen=impl;Liste=unused;', States(Bericht('Typen, Liste', '', '',
    '  if Gruen = Rot then'#10'    Exit;'#10), True));
end;

procedure TUsesUsageTests.OverloadsKeepAllUnits;
begin
  // Welche Überladung gewinnt, entscheiden die Argumente; beide Units bleiben.
  Assert.AreEqual('UeberEins=impl;UeberZwei=impl;', States(Bericht('UeberEins, UeberZwei', '', '', '  Mach(1);'#10),
    True));
end;

procedure TUsesUsageTests.HelperKeepsUnit;
begin
  Assert.AreEqual('Helfer=impl;Liste=unused;', States(Bericht('Helfer, Liste', '', 'var'#10'  Zahl: Integer;'#10,
    '  Zahl := 2;'#10'  Zahl := Zahl.Doppelt;'#10), True));
end;

procedure TUsesUsageTests.InlineBodyKeepsUnit;
const
  cBody = '  Zahl := Flott;'#10;
  cVar = 'var'#10'  Zahl: Integer;'#10;
begin
  // Ohne Basis bettet dcc Flott nicht ein (H2443): Basis bleibt. Bei einer Routine ohne inline nicht.
  Assert.AreEqual('Schnell=impl;Basis=impl;', States(Bericht('Schnell, Basis', '', cVar, cBody), True));
  Assert.AreEqual('Langsam=impl;Basis=unused;', States(Bericht('Langsam, Basis', '', cVar, cBody), True));
end;

procedure TUsesUsageTests.AttributeKeepsUnit;
begin
  // [Pruef] meint PruefAttribute aus Merkmal.
  Assert.AreEqual('Liste=unused;', States('unit Bericht;'#10'interface'#10'uses Merkmal, Liste;'#10'type'#10 +
    '  [Pruef]'#10'  TBericht = class'#10'  end;'#10'implementation'#10'end.', True));
end;

procedure TUsesUsageTests.UnresolvedNameFallsBack;
begin
  // Fremd ist unbekannt, also auch Tu im with: Dann gilt der Namensvergleich, Erste bleibt.
  Assert.AreEqual('Erste=impl;Liste=unused;', States(Bericht('Erste, Liste', '', '',
    '  with Fremd do'#10'    Tu;'#10), True));
end;

procedure TUsesUsageTests.InterfaceUseIsQuiet;
begin
  Assert.AreEqual('', States('unit Bericht;'#10'interface'#10'uses Liste;'#10'type'#10'  TBericht = class'#10 +
    '    FListe: TListe;'#10'  end;'#10'implementation'#10'end.', True));
end;

procedure TUsesUsageTests.UnitInfoSplitsNames;
var
  mInfoOf: TUsesUnitInfoFunc;
  mInfo: TUsesUnitInfo;
begin
  mInfoOf := TUsesUsage.UnitInfo(NewIndex, nil, nil);
  mInfo := mInfoOf('Helfer');
  Assert.IsTrue(mInfo.Known);
  Assert.AreEqual('TZahlHelfer', string.Join(',', mInfo.TopNames));
  Assert.AreEqual('Doppelt', string.Join(',', mInfo.HelperNames));
  mInfo := mInfoOf('Liste');
  Assert.AreEqual('TListe', string.Join(',', mInfo.TopNames));
  Assert.AreEqual('', string.Join(',', mInfo.HelperNames));
  Assert.IsTrue(Pos('Count', string.Join(',', mInfo.Names)) > 0);
  mInfo := mInfoOf('Typen');
  Assert.AreEqual('TFarbe,Rot,Gruen', string.Join(',', mInfo.TopNames));
  Assert.IsFalse(mInfoOf('Fehlt').Known);
end;

procedure TUsesUsageTests.WithoutIndexOrWithSyntaxErrorIsInactive;
var
  mIndex: ISymbolIndex;
  mInfo: TUsesUnitInfoFunc;
  mSource: TUsesUsageSource;
  mTree: TSyntaxTree;
  mText: string;
  mResolve: TUsesResolveFunc;
begin
  mIndex := NewIndex;
  mInfo := TUsesUsage.UnitInfo(mIndex, nil, nil);
  mSource := Default(TUsesUsageSource);
  mText := Bericht('Liste', '', '', '  Tu;'#10);
  mTree := TSyntaxTreeCache.Parse(mText);
  try
    Assert.IsFalse(TUsesUsage.Resolve(mSource, mTree, 'Bericht.pas', nil, mInfo).Active);
  finally
    mTree.Free;
  end;
  mSource.Index := mIndex;
  mResolve := TUsesUsage.ResolveFunc(mSource, 'Bericht.pas', mInfo);
  Assert.IsTrue(mResolve(mText, nil).Active);
  Assert.IsFalse(mResolve('unit Bericht;'#10'interface'#10'uses Liste;'#10'implementation'#10'procedure ;'#10'end.',
    nil).Active);
end;

procedure TUsesUsageTests.SameUnitUsesNamespaces;
begin
  Assert.IsTrue(TInlineCallees.SameUnit('SysUtils', 'System.SysUtils', ['System']));
  Assert.IsTrue(TInlineCallees.SameUnit('system.sysutils', 'System.SysUtils', nil));
  Assert.IsFalse(TInlineCallees.SameUnit('Classes', 'System.SysUtils', ['System']));
end;

end.
