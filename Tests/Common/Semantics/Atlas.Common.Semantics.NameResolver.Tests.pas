unit Atlas.Common.Semantics.NameResolver.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  [TestFixture]
  TNameResolverTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    procedure AddUnit(const AFileName, AText: string);
    function ResolveAt(const AText, AMarker: string; AOccurrence: Integer = 1): TResolvedSymbol;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ResolvesLocalsParametersAndResult;
    [Test]
    procedure ResolvesInlineVarsOnlyAfterDeclaration;
    [Test]
    procedure ResolvesMembersInMethodsAndSelf;
    [Test]
    procedure ResolvesInheritedMembersAcrossUnits;
    [Test]
    procedure LastUsedUnitWins;
    [Test]
    procedure ResolvesMemberChainsThroughDeclaredTypes;
    [Test]
    procedure ResolvesQualifiedNames;
    [Test]
    procedure InterfaceDoesNotSeeImplementation;
    [Test]
    procedure ResolvesInherited;
    [Test]
    procedure UsesNamespacesForShortUnitNames;
    [Test]
    procedure LoadsOnlyUnitsMissingFromIndex;
    [Test]
    procedure GivesUpOnExpressions;
    [Test]
    procedure FallsBackToSystem;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor;

const
  UnitBasis =
    'unit Basis;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TBasis = class'#10 +
    '  public'#10 +
    '    FName: string;'#10 +
    '    constructor Create;'#10 +
    '    procedure Melde;'#10 +
    '  end;'#10 +
    'function Wert: Integer;'#10 +
    'implementation'#10 +
    'function Wert: Integer; begin Result := 1; end;'#10 +
    'constructor TBasis.Create; begin end;'#10 +
    'procedure TBasis.Melde; begin end;'#10 +
    'end.';

  UnitZweit =
    'unit Zweit;'#10 +
    'interface'#10 +
    'function Wert: Integer;'#10 +
    'implementation'#10 +
    'function Wert: Integer; begin Result := 2; end;'#10 +
    'end.';

  UnitSystem =
    'unit System;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TObject = class'#10 +
    '    procedure Free;'#10 +
    '  end;'#10 +
    'procedure WriteLn;'#10 +
    'implementation'#10 +
    'end.';

  UnitDotted =
    'unit Firma.Werkzeuge;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TWerkzeug = class'#10 +
    '    procedure Nutze;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

function PositionOf(const AText, AMarker: string; AOccurrence: Integer): TTextPosition;
var
  Index, Found, Line, LineStart: Integer;
begin
  Found := 0;
  Index := 0;
  repeat
    Index := Pos(AMarker, AText, Index + 1);
    if Index = 0 then
      raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
    Inc(Found);
  until Found = AOccurrence;
  Line := 0;
  LineStart := 1;
  for Found := 1 to Index - 1 do
    if AText[Found] = #10 then
    begin
      Inc(Line);
      LineStart := Found + 1;
    end;
  Result := TTextPosition.Create(Line, Index - LineStart);
end;

{ TNameResolverTests }

procedure TNameResolverTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  AddUnit('C:\Lib\System.pas', UnitSystem);
  AddUnit('C:\P\Basis.pas', UnitBasis);
  AddUnit('C:\P\Zweit.pas', UnitZweit);
  AddUnit('C:\P\Firma.Werkzeuge.pas', UnitDotted);
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TNameResolverTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

procedure TNameResolverTests.AddUnit(const AFileName, AText: string);
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(AText, AFileName, nil));
end;

function TNameResolverTests.ResolveAt(const AText, AMarker: string; AOccurrence: Integer): TResolvedSymbol;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := FResolver.Resolve(Tree, 'C:\P\Haupt.pas', PositionOf(AText, AMarker, AOccurrence));
  finally
    Tree.Free;
  end;
end;

procedure TNameResolverTests.ResolvesLocalsParametersAndResult;
const
  Source =
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'var Zaehler: Integer;'#10 +
    'function Summe(A, B: Integer): Integer;'#10 +
    'var'#10 +
    '  Zwischen: Double;'#10 +
    'begin'#10 +
    '  Zwischen := A + B;'#10 +
    '  Result := Zaehler;'#10 +
    'end;'#10 +
    'end.';
var
  R: TResolvedSymbol;
begin
  R := ResolveAt(Source, 'Zwischen :=');
  Assert.IsTrue(R.Kind = TResolvedKind.Local);
  Assert.AreEqual('Double', R.TypeName);
  Assert.AreEqual(6, R.SelectionRange.StartPos.Line);
  R := ResolveAt(Source, 'B;');
  Assert.IsTrue(R.IsParameter);
  Assert.AreEqual('Integer', R.TypeName);
  R := ResolveAt(Source, 'Result :=');
  Assert.IsTrue(R.Kind = TResolvedKind.Local);
  Assert.AreEqual('Integer', R.TypeName);
  R := ResolveAt(Source, 'Zaehler;');
  Assert.IsTrue(R.Kind = TResolvedKind.Symbol);
  Assert.AreEqual('Haupt', R.UnitName);
  Assert.AreEqual(3, R.SelectionRange.StartPos.Line);
end;

procedure TNameResolverTests.ResolvesInlineVarsOnlyAfterDeclaration;
const
  Source =
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'var X: Integer;'#10 +
    'procedure P;'#10 +
    'begin'#10 +
    '  X := 1;'#10 +
    '  var X: string := '''';'#10 +
    '  X := ''a'';'#10 +
    'end;'#10 +
    'end.';
var
  R: TResolvedSymbol;
begin
  R := ResolveAt(Source, 'X := 1');
  Assert.IsTrue(R.Kind = TResolvedKind.Symbol, 'vor der Inline-Variablen gilt die globale');
  R := ResolveAt(Source, 'X := ''a''');
  Assert.IsTrue(R.Kind = TResolvedKind.Local);
  Assert.AreEqual('string', R.TypeName);
end;

procedure TNameResolverTests.ResolvesMembersInMethodsAndSelf;
const
  Source =
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FWert: Integer;'#10 +
    '    procedure Run;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFoo.Run;'#10 +
    'begin'#10 +
    '  FWert := 1;'#10 +
    '  Self.FWert := 2;'#10 +
    'end;'#10 +
    'end.';
var
  R: TResolvedSymbol;
begin
  R := ResolveAt(Source, 'FWert := 1');
  Assert.IsTrue(R.Kind = TResolvedKind.Symbol);
  Assert.AreEqual('TFoo.FWert', R.QualifiedName);
  Assert.AreEqual(5, R.SelectionRange.StartPos.Line);
  R := ResolveAt(Source, 'FWert := 2');
  Assert.AreEqual('TFoo.FWert', R.QualifiedName);
  R := ResolveAt(Source, 'Self');
  Assert.IsTrue(R.IsType);
  Assert.AreEqual('TFoo', R.Name);
  // Methodenkopf in implementation führt zur Deklaration in der Klasse.
  R := ResolveAt(Source, 'Run;', 2);
  Assert.AreEqual('TFoo.Run', R.QualifiedName);
  Assert.AreEqual(6, R.SelectionRange.StartPos.Line);
end;

procedure TNameResolverTests.ResolvesInheritedMembersAcrossUnits;
const
  Source =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Basis;'#10 +
    'type'#10 +
    '  TKind = class(TBasis)'#10 +
    '    procedure Tu;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TKind.Tu;'#10 +
    'begin'#10 +
    '  Melde;'#10 +
    '  FName := '''';'#10 +
    '  Free;'#10 +
    'end;'#10 +
    'end.';
var
  R: TResolvedSymbol;
begin
  R := ResolveAt(Source, 'Melde');
  Assert.AreEqual('TBasis.Melde', R.QualifiedName);
  Assert.AreEqual('Basis', R.UnitName);
  Assert.AreEqual('C:\P\Basis.pas', R.FileName);
  R := ResolveAt(Source, 'FName');
  Assert.AreEqual('TBasis.FName', R.QualifiedName);
  // TBasis ohne Vorfahr erbt von System.TObject.
  R := ResolveAt(Source, 'Free');
  Assert.AreEqual('TObject.Free', R.QualifiedName);
  Assert.AreEqual('System', R.UnitName);
end;

procedure TNameResolverTests.LastUsedUnitWins;
var
  R: TResolvedSymbol;
begin
  R := ResolveAt('unit Haupt; interface uses Basis, Zweit; implementation procedure P; begin Wert; end; end.', 'Wert');
  Assert.AreEqual('Zweit', R.UnitName);
  R := ResolveAt('unit Haupt; interface uses Zweit, Basis; implementation procedure P; begin Wert; end; end.', 'Wert');
  Assert.AreEqual('Basis', R.UnitName);
  // implementation-uses vor interface-uses
  R := ResolveAt('unit Haupt; interface uses Zweit; implementation uses Basis; procedure P; begin Wert; end; end.', 'Wert');
  Assert.AreEqual('Basis', R.UnitName);
end;

procedure TNameResolverTests.ResolvesMemberChainsThroughDeclaredTypes;
const
  Source =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Basis;'#10 +
    'type'#10 +
    '  TAlias = TBasis;'#10 +
    '  THalter = class'#10 +
    '    Inhalt: TAlias;'#10 +
    '    function Gib: TBasis;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function THalter.Gib: TBasis; begin end;'#10 +
    'procedure P(H: THalter);'#10 +
    'begin'#10 +
    '  H.Inhalt.Melde;'#10 +
    '  H.Gib.FName := '''';'#10 +
    '  TBasis.Create;'#10 +
    'end;'#10 +
    'end.';
var
  R: TResolvedSymbol;
begin
  R := ResolveAt(Source, 'Melde');
  Assert.AreEqual('TBasis.Melde', R.QualifiedName);
  R := ResolveAt(Source, 'FName');
  Assert.AreEqual('TBasis.FName', R.QualifiedName);
  R := ResolveAt(Source, 'Create');
  Assert.AreEqual('TBasis.Create', R.QualifiedName);
  Assert.IsTrue(R.SymbolKind = TIndexSymbolKind.Constructor_);
end;

procedure TNameResolverTests.ResolvesQualifiedNames;
const
  Source =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Basis, Zweit, Firma.Werkzeuge;'#10 +
    'implementation'#10 +
    'procedure P;'#10 +
    'begin'#10 +
    '  Basis.Wert;'#10 +
    '  Basis.TBasis.Create;'#10 +
    '  Firma.Werkzeuge.TWerkzeug.Create;'#10 +
    'end;'#10 +
    'end.';
var
  R: TResolvedSymbol;
begin
  R := ResolveAt(Source, 'Wert');
  Assert.AreEqual('Basis', R.UnitName, 'Basis.Wert trotz Zweit dahinter');
  R := ResolveAt(Source, 'Basis', 2);
  Assert.IsTrue(R.Kind = TResolvedKind.UnitName);
  R := ResolveAt(Source, 'Create');
  Assert.AreEqual('TBasis.Create', R.QualifiedName);
  R := ResolveAt(Source, 'TWerkzeug');
  Assert.AreEqual('Firma.Werkzeuge', R.UnitName);
  // Create gibt es in TWerkzeug nicht, aber im Vorfahren TObject? Nein: nur Free.
  R := ResolveAt(Source, 'Create', 2);
  Assert.IsFalse(R.Found);
end;

procedure TNameResolverTests.InterfaceDoesNotSeeImplementation;
const
  Source =
    'unit Haupt;'#10 +
    'interface'#10 +
    'const A = B;'#10 +
    'implementation'#10 +
    'const B = 1;'#10 +
    'const C = B;'#10 +
    'end.';
var
  R: TResolvedSymbol;
begin
  R := ResolveAt(Source, 'B;');
  Assert.IsFalse(R.Found);
  R := ResolveAt(Source, 'B;', 2);
  Assert.IsTrue(R.Found);
  Assert.AreEqual(4, R.SelectionRange.StartPos.Line);
end;

procedure TNameResolverTests.ResolvesInherited;
const
  Source =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Basis;'#10 +
    'type'#10 +
    '  TKind = class(TBasis)'#10 +
    '    constructor Create;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TKind.Create;'#10 +
    'begin'#10 +
    '  inherited Create;'#10 +
    'end;'#10 +
    'end.';
var
  R: TResolvedSymbol;
begin
  R := ResolveAt(Source, 'Create;', 3);
  Assert.AreEqual('TBasis.Create', R.QualifiedName);
  Assert.AreEqual('Basis', R.UnitName);
end;

procedure TNameResolverTests.UsesNamespacesForShortUnitNames;
var
  R: TResolvedSymbol;
begin
  FResolver.Namespaces := ['Firma'];
  R := ResolveAt('unit Haupt; interface uses Werkzeuge; implementation procedure P; begin TWerkzeug.Create; end; end.',
    'TWerkzeug');
  Assert.AreEqual('Firma.Werkzeuge', R.UnitName);
end;

procedure TNameResolverTests.LoadsOnlyUnitsMissingFromIndex;
const
  Source = 'unit Haupt; interface uses Werkzeuge, Fehlt; implementation procedure P; begin TWerkzeug.Create; ' +
    'Unbekannt; end; end.';
var
  Calls: TArray<string>;
  Resolver: TNameResolver;
  Tree: TSyntaxTree;
  R: TResolvedSymbol;
begin
  // Nachladen durchsucht die Suchpfade aller Projekte (#647): nicht für Units, die der Index mit
  // Namespace schon kennt, und eine fehlende Unit je Resolver nur einmal.
  Calls := nil;
  Resolver := TNameResolver.Create(FIndex,
    function(const AUnitName: string): Boolean
    begin
      Calls := Calls + [AUnitName];
      Result := False;
    end);
  try
    Resolver.Namespaces := ['Firma'];
    Tree := TPascalParser.Parse(Source);
    try
      R := Resolver.Resolve(Tree, 'C:\P\Haupt.pas', PositionOf(Source, 'TWerkzeug', 1));
      Assert.AreEqual('Firma.Werkzeuge', R.UnitName);
      R := Resolver.Resolve(Tree, 'C:\P\Haupt.pas', PositionOf(Source, 'Unbekannt', 1));
      Assert.IsFalse(R.Found);
    finally
      Tree.Free;
    end;
  finally
    Resolver.Free;
  end;
  Assert.AreEqual('Fehlt,Firma.Fehlt', string.Join(',', Calls));
end;

procedure TNameResolverTests.GivesUpOnExpressions;
var
  R: TResolvedSymbol;
begin
  R := ResolveAt('unit Haupt; interface uses Basis; implementation procedure P; begin Wert(1).Melde; end; end.', 'Melde');
  Assert.IsFalse(R.Found);
  R := ResolveAt('unit Haupt; interface implementation procedure P; begin Unbekannt; end; end.', 'Unbekannt');
  Assert.IsFalse(R.Found);
end;

procedure TNameResolverTests.FallsBackToSystem;
var
  R: TResolvedSymbol;
begin
  R := ResolveAt('unit Haupt; interface implementation procedure P; begin WriteLn; end; end.', 'WriteLn');
  Assert.AreEqual('System', R.UnitName);
end;

initialization
  TDUnitX.RegisterTestFixture(TNameResolverTests);

end.
