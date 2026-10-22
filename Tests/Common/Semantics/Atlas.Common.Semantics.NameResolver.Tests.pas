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
    procedure NodeTypeAndPropertyReadsField;
    [Test]
    procedure ResolvesInlineVarsOnlyAfterDeclaration;
    [Test]
    procedure ResolvesMembersInMethodsAndSelf;
    [Test]
    procedure LocalsHideFieldsOfTheSameName;
    [Test]
    procedure AnonymousMethodLocalsHideFields;
    [Test]
    procedure CandidatesInAnonymousMethodHideFields;
    /// <summary>Code-Review F-02: Methoden verschachtelter Typen in strict-Abschnitten ohne Endlosrekursion.</summary>
    [Test]
    procedure ResolvesStrictMembersInNestedTypeMethods;
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
    /// <summary>Code-Review P-01/P-02: PinTree desselben Baums verschachtelt; erst das letzte UnpinTree löst.</summary>
    [Test]
    procedure PinTreeNestedSameTreeKeepsPin;
    /// <summary>Code-Review P-01: Ein Fremdbaum über dem eigenen; nach seinem UnpinTree gilt der eigene weiter.</summary>
    [Test]
    procedure PinTreeNestedOtherTreeRestoresOuter;
    [Test]
    procedure ExtractedUnitEqualsExtract;
    [Test]
    procedure UnpinTreeWithoutPinIsNoop;
    /// <summary>Code-Review P-17: ResolveTypeFrom leert den Helfer-Cache nicht mehr.</summary>
    [Test]
    procedure ResolveTypeFromKeepsHelperCache;
    /// <summary>Code-Review P-17: Helfer nur aus implementation-uses sind im interface-Teil nicht sichtbar,
    /// auch wenn derselbe Resolver sie vorher im implementation-Teil gefunden hat.</summary>
    [Test]
    procedure HelperVisibilityDependsOnSection;
    /// <summary>Code-Review P-05/P-17: DeclaredMember über die Namenstabelle, auch geerbt; Vorfahren-Cache
    /// über ResolveTypeFrom hinweg.</summary>
    [Test]
    procedure DeclaredMemberFindsInherited;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
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

procedure TNameResolverTests.ResolvesStrictMembersInNestedTypeMethods;
const
  Source =
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TAussen = class'#10 +
    '  strict private'#10 +
    '    type'#10 +
    '      TInnen = class'#10 +
    '      strict private'#10 +
    '        FWert: Integer;'#10 +
    '        procedure Lauf;'#10 +
    '      end;'#10 +
    '  strict protected'#10 +
    '    type'#10 +
    '      TGeschuetzt = class'#10 +
    '      strict protected'#10 +
    '        FZahl: Integer;'#10 +
    '        procedure Zaehle;'#10 +
    '      end;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TAussen.TInnen.Lauf;'#10 +
    'begin'#10 +
    '  FWert := 1;'#10 +
    'end;'#10 +
    'procedure TAussen.TGeschuetzt.Zaehle;'#10 +
    'begin'#10 +
    '  FZahl := 2;'#10 +
    'end;'#10 +
    'end.';
var
  R: TResolvedSymbol;
begin
  // Bisher: Der Kopf TAussen.TInnen wurde mit der Sichtbarkeit des Rumpfs aufgelöst, die nach der Klasse
  // der Methode fragt, die gerade ermittelt wurde (Rekursion bis zum Stapelüberlauf).
  R := ResolveAt(Source, 'FWert := 1');
  Assert.IsTrue(R.Found, 'strict private Feld im eigenen Rumpf');
  Assert.AreEqual('Integer', R.TypeName);
  Assert.AreEqual(8, R.SelectionRange.StartPos.Line);
  R := ResolveAt(Source, 'FZahl := 2');
  Assert.IsTrue(R.Found, 'strict protected Feld im eigenen Rumpf');
  Assert.AreEqual(15, R.SelectionRange.StartPos.Line);
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

const
  // Parameter, lokale Variablen und Felder mit gleichem Namen; ohne Self gewinnt wie in Delphi der lokale Name.
  SourceVerdeckt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TKunde = class'#10 +
    '  private'#10 +
    '    Name: string;'#10 +
    '    Wert: Integer;'#10 +
    '    Anzahl: Integer;'#10 +
    '    procedure SetzeName(const Name: string);'#10 +
    '    procedure Zaehle;'#10 +
    '    procedure Anonym;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TKunde.SetzeName(const Name: string);'#10 +
    'begin'#10 +
    '  Self.Name := Name; {M1}'#10 +
    'end;'#10 +
    'procedure TKunde.Zaehle;'#10 +
    'var'#10 +
    '  Anzahl: Integer;'#10 +
    'begin'#10 +
    '  Anzahl := Wert; {M2}'#10 +
    'end;'#10 +
    'procedure TKunde.Anonym;'#10 +
    'var'#10 +
    '  P: TProc<Integer>;'#10 +
    '  F: TFunc<Integer>;'#10 +
    'begin'#10 +
    '  P := procedure(Wert: Integer)'#10 +
    '    begin'#10 +
    '      Anzahl := Wert; {M3}'#10 +
    '    end;'#10 +
    '  F := function: Integer'#10 +
    '    var'#10 +
    '      Anzahl: Integer;'#10 +
    '    begin'#10 +
    '      Anzahl := Wert; {M4}'#10 +
    '      Result := Anzahl;'#10 +
    '    end;'#10 +
    '  Wert := 1; {M5}'#10 +
    'end;'#10 +
    'end.';

procedure TNameResolverTests.LocalsHideFieldsOfTheSameName;
var
  R: TResolvedSymbol;
begin
  R := ResolveAt(SourceVerdeckt, 'Name := Name; {M1}');
  Assert.IsTrue(R.Kind = TResolvedKind.Symbol, 'Self.Name ist das Feld');
  Assert.AreEqual('TKunde.Name', R.QualifiedName);
  R := ResolveAt(SourceVerdeckt, 'Name; {M1}');
  Assert.IsTrue(R.Kind = TResolvedKind.Local);
  Assert.IsTrue(R.IsParameter);
  R := ResolveAt(SourceVerdeckt, 'Anzahl := Wert; {M2}');
  Assert.IsTrue(R.Kind = TResolvedKind.Local);
  Assert.AreEqual(19, R.SelectionRange.StartPos.Line);
  R := ResolveAt(SourceVerdeckt, 'Wert; {M2}');
  Assert.AreEqual('TKunde.Wert', R.QualifiedName);
end;

procedure TNameResolverTests.AnonymousMethodLocalsHideFields;
var
  R: TResolvedSymbol;
begin
  // Parameter der anonymen Methode verdeckt das Feld Wert; Anzahl bleibt das Feld.
  R := ResolveAt(SourceVerdeckt, 'Wert; {M3}');
  Assert.IsTrue(R.Kind = TResolvedKind.Local);
  Assert.IsTrue(R.IsParameter);
  Assert.AreEqual(28, R.SelectionRange.StartPos.Line);
  R := ResolveAt(SourceVerdeckt, 'Anzahl := Wert; {M3}');
  Assert.AreEqual('TKunde.Anzahl', R.QualifiedName);
  // var-Abschnitt der anonymen Methode; Wert ist dort wieder das Feld.
  R := ResolveAt(SourceVerdeckt, 'Anzahl := Wert; {M4}');
  Assert.IsTrue(R.Kind = TResolvedKind.Local);
  Assert.AreEqual(34, R.SelectionRange.StartPos.Line);
  R := ResolveAt(SourceVerdeckt, 'Wert; {M4}');
  Assert.AreEqual('TKunde.Wert', R.QualifiedName);
  R := ResolveAt(SourceVerdeckt, 'Result := Anzahl');
  Assert.IsTrue(R.Kind = TResolvedKind.Local);
  // Außerhalb der anonymen Methoden gilt wieder das Feld.
  R := ResolveAt(SourceVerdeckt, 'Wert := 1; {M5}');
  Assert.AreEqual('TKunde.Wert', R.QualifiedName);
end;

procedure TNameResolverTests.CandidatesInAnonymousMethodHideFields;
var
  Tree: TSyntaxTree;
  Candidates: TArray<TResolvedSymbol>;
  Candidate: TResolvedSymbol;
  Found: Integer;
begin
  Tree := TPascalParser.Parse(SourceVerdeckt);
  try
    Candidates := FResolver.OwnScopeCandidates(Tree, 'C:\P\Haupt.pas', Pos('Anzahl := Wert; {M3}', SourceVerdeckt) - 1);
    FResolver.UsedScopeCandidates;
  finally
    Tree.Free;
  end;
  Found := 0;
  for Candidate in Candidates do
    if SameText(Candidate.Name, 'Wert') then
    begin
      Inc(Found);
      Assert.IsTrue(Candidate.IsParameter);
      Assert.AreEqual(1, Integer(Length(Candidate.Hides)));
      Assert.AreEqual('Feld TKunde.Wert', Candidate.Hides[0]);
    end;
  Assert.AreEqual(1, Found);
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
  // Namespace schon kennt, und eine fehlende Unit je Resolver nur einmal. Die Namespaces probiert
  // der Unit-Resolver selbst; Firma.Fehlt wird nicht noch einmal gesucht.
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
  Assert.AreEqual('Fehlt', string.Join(',', Calls));
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

const
  PinSource =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Basis;'#10 +
    'type'#10 +
    '  TKind = class(TBasis)'#10 +
    '    procedure Tu;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TKind.Tu;'#10 +
    'var'#10 +
    '  Zahl: Integer;'#10 +
    'begin'#10 +
    '  Melde;'#10 +
    '  Zahl := 1;'#10 +
    'end;'#10 +
    'end.';
  PinOther =
    'unit Andere;'#10 +
    'interface'#10 +
    'uses Zweit;'#10 +
    'implementation'#10 +
    'procedure P;'#10 +
    'begin'#10 +
    '  Wert;'#10 +
    'end;'#10 +
    'end.';

procedure TNameResolverTests.PinTreeNestedSameTreeKeepsPin;
var
  Tree: TSyntaxTree;
  First, Second: TUnitIndex;
begin
  Tree := TPascalParser.Parse(PinSource);
  try
    FResolver.PinTree(Tree, 'C:\P\Haupt.pas');
    FResolver.PinTree(Tree, 'C:\P\Haupt.pas');
    // Gepinnt: dieselbe Auswertung, kein neues Extrakt (gleiches Symbol-Array).
    First := FResolver.ExtractedUnit(Tree, 'C:\P\Haupt.pas');
    Second := FResolver.ExtractedUnit(Tree, 'C:\P\Haupt.pas');
    Assert.IsTrue(Pointer(First.Symbols) = Pointer(Second.Symbols));
    Assert.AreEqual('TBasis.Melde', FResolver.Resolve(Tree, 'C:\P\Haupt.pas',
      PositionOf(PinSource, 'Melde;', 1)).QualifiedName);
    FResolver.UnpinTree;
    // Das innere UnpinTree löst den Baum noch nicht.
    Second := FResolver.ExtractedUnit(Tree, 'C:\P\Haupt.pas');
    Assert.IsTrue(Pointer(First.Symbols) = Pointer(Second.Symbols));
    Assert.AreEqual('TBasis.Melde', FResolver.Resolve(Tree, 'C:\P\Haupt.pas',
      PositionOf(PinSource, 'Melde;', 1)).QualifiedName);
    FResolver.UnpinTree;
    // Ungepinnt wertet jeder Aufruf neu aus; das Ergebnis bleibt gleich.
    Second := FResolver.ExtractedUnit(Tree, 'C:\P\Haupt.pas');
    Assert.IsFalse(Pointer(First.Symbols) = Pointer(Second.Symbols));
    Assert.AreEqual(Integer(Length(First.Symbols)), Integer(Length(Second.Symbols)));
    Assert.AreEqual('TBasis.Melde', FResolver.Resolve(Tree, 'C:\P\Haupt.pas',
      PositionOf(PinSource, 'Melde;', 1)).QualifiedName);
  finally
    Tree.Free;
  end;
end;

procedure TNameResolverTests.PinTreeNestedOtherTreeRestoresOuter;
var
  Outer, Inner: TSyntaxTree;
  Pinned: TUnitIndex;
  R: TResolvedSymbol;
begin
  Outer := TPascalParser.Parse(PinSource);
  try
    FResolver.PinTree(Outer, 'C:\P\Haupt.pas');
    try
      Pinned := FResolver.ExtractedUnit(Outer, 'C:\P\Haupt.pas');
      Inner := TPascalParser.Parse(PinOther);
      try
        FResolver.PinTree(Inner, 'C:\P\Andere.pas');
        try
          Assert.AreEqual('Zweit', FResolver.Resolve(Inner, 'C:\P\Andere.pas',
            PositionOf(PinOther, 'Wert;', 1)).UnitName);
          // Der äußere Baum bleibt gepinnt, auch während der innere es ist.
          Assert.IsTrue(Pointer(Pinned.Symbols) = Pointer(FResolver.ExtractedUnit(Outer, 'C:\P\Haupt.pas').Symbols));
        finally
          FResolver.UnpinTree;
        end;
      finally
        Inner.Free;
      end;
      Assert.IsTrue(Pointer(Pinned.Symbols) = Pointer(FResolver.ExtractedUnit(Outer, 'C:\P\Haupt.pas').Symbols));
      R := FResolver.Resolve(Outer, 'C:\P\Haupt.pas', PositionOf(PinSource, 'Zahl :=', 1));
      Assert.IsTrue(R.Found);
      Assert.AreEqual('Zahl', R.Name);
      Assert.IsTrue(R.Kind = TResolvedKind.Local);
      Assert.AreEqual('TBasis.Melde', FResolver.Resolve(Outer, 'C:\P\Haupt.pas',
        PositionOf(PinSource, 'Melde;', 1)).QualifiedName);
    finally
      FResolver.UnpinTree;
    end;
  finally
    Outer.Free;
  end;
end;

procedure TNameResolverTests.ExtractedUnitEqualsExtract;
var
  Tree: TSyntaxTree;
  Expected, Actual: TUnitIndex;

  procedure Check;
  var
    Index: Integer;
  begin
    Assert.AreEqual(Expected.UnitName, Actual.UnitName);
    Assert.AreEqual(Integer(Length(Expected.Symbols)), Integer(Length(Actual.Symbols)));
    for Index := 0 to High(Expected.Symbols) do
    begin
      Assert.AreEqual(Expected.Symbols[Index].QualifiedName, Actual.Symbols[Index].QualifiedName);
      Assert.AreEqual(Expected.Symbols[Index].Range.StartPos.Line, Actual.Symbols[Index].Range.StartPos.Line);
    end;
  end;

begin
  Tree := TPascalParser.Parse(PinSource);
  try
    Expected := TIndexExtractor.Extract(Tree, 'C:\P\Haupt.pas');
    Actual := FResolver.ExtractedUnit(Tree, 'C:\P\Haupt.pas');
    Check;
    FResolver.PinTree(Tree, 'C:\P\Haupt.pas');
    try
      Actual := FResolver.ExtractedUnit(Tree, 'C:\P\Haupt.pas');
      Check;
    finally
      FResolver.UnpinTree;
    end;
  finally
    Tree.Free;
  end;
end;

procedure TNameResolverTests.UnpinTreeWithoutPinIsNoop;
begin
  FResolver.UnpinTree;
  FResolver.UnpinTree;
  Assert.AreEqual('TBasis.Melde', ResolveAt(PinSource, 'Melde;').QualifiedName);
end;

const
  UnitHelfer =
    'unit Helfer;'#10 +
    'interface'#10 +
    'uses Basis;'#10 +
    'type'#10 +
    '  TBasisHelfer = class helper for TBasis'#10 +
    '    function Anrede: string;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TBasisHelfer.Anrede: string; begin Result := ''''; end;'#10 +
    'end.';
  HelferSource =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Basis;'#10 +
    'var'#10 +
    '  S: TBasis;'#10 +
    'implementation'#10 +
    'uses Helfer;'#10 +
    'procedure P;'#10 +
    'begin'#10 +
    '  S.Anrede;'#10 +
    'end;'#10 +
    'end.';

procedure TNameResolverTests.ResolveTypeFromKeepsHelperCache;
var
  Tree: TSyntaxTree;
  BasisUnit: TUnitIndex;
  Found: TResolvedSymbol;
begin
  AddUnit('C:\P\Helfer.pas', UnitHelfer);
  Assert.IsTrue(FIndex.FindUnit('Basis', BasisUnit));
  Tree := TPascalParser.Parse(HelferSource);
  try
    FResolver.PinTree(Tree, 'C:\P\Haupt.pas');
    try
      Assert.AreEqual('TBasisHelfer', FResolver.Resolve(Tree, 'C:\P\Haupt.pas',
        PositionOf(HelferSource, 'Anrede', 1)).Container);
      // Dazwischen aus einer anderen Unit auflösen (wie TypeAt und TypeChain der Vervollständigung).
      Assert.IsTrue(FResolver.ResolveTypeFrom(BasisUnit, 'TBasis', Found));
      Assert.AreEqual('TBasisHelfer', FResolver.Resolve(Tree, 'C:\P\Haupt.pas',
        PositionOf(HelferSource, 'Anrede', 1)).Container);
    finally
      FResolver.UnpinTree;
    end;
  finally
    Tree.Free;
  end;
end;

procedure TNameResolverTests.HelperVisibilityDependsOnSection;
var
  Tree: TSyntaxTree;
  InImplementation, InInterface: Integer;
begin
  AddUnit('C:\P\Helfer.pas', UnitHelfer);
  Tree := TPascalParser.Parse(HelferSource);
  try
    // Offsets ab 0.
    InImplementation := Pos('S.Anrede', HelferSource) - 1;
    InInterface := Pos('S: TBasis', HelferSource) - 1;
    FResolver.PinTree(Tree, 'C:\P\Haupt.pas');
    try
      Assert.IsTrue(FResolver.ResolveChain(Tree, 'C:\P\Haupt.pas', ['S', 'Anrede'], InImplementation).Found);
      Assert.IsFalse(FResolver.ResolveChain(Tree, 'C:\P\Haupt.pas', ['S', 'Anrede'], InInterface).Found);
      Assert.IsTrue(FResolver.ResolveChain(Tree, 'C:\P\Haupt.pas', ['S', 'Anrede'], InImplementation).Found);
    finally
      FResolver.UnpinTree;
    end;
  finally
    Tree.Free;
  end;
end;

procedure TNameResolverTests.DeclaredMemberFindsInherited;
const
  UnitKinder =
    'unit Kinder;'#10 +
    'interface'#10 +
    'uses Basis;'#10 +
    'type'#10 +
    '  TKind = class(TBasis)'#10 +
    '    procedure Eigen;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TKind.Eigen; begin end;'#10 +
    'end.';
var
  KinderUnit, BasisUnit: TUnitIndex;
  Kind, Member, Ancestor, Other: TResolvedSymbol;
begin
  AddUnit('C:\P\Kinder.pas', UnitKinder);
  Assert.IsTrue(FIndex.FindUnit('Kinder', KinderUnit));
  Assert.IsTrue(FIndex.FindUnit('Basis', BasisUnit));
  Assert.IsTrue(FResolver.ResolveTypeFrom(KinderUnit, 'TKind', Kind));
  Assert.IsTrue(FResolver.DeclaredMember(Kind, 'Eigen', Member));
  Assert.AreEqual('TKind.Eigen', Member.QualifiedName);
  Assert.IsTrue(FResolver.DeclaredMember(Kind, 'melde', Member));
  Assert.AreEqual('TBasis.Melde', Member.QualifiedName);
  Assert.IsFalse(FResolver.DeclaredMember(Kind, 'Fehlt', Member));
  Assert.IsTrue(FResolver.AncestorOf(Kind, Ancestor));
  Assert.AreEqual('TBasis', Ancestor.Name);
  // Vorfahren-Cache über ResolveTypeFrom aus einer anderen Unit hinweg: gleiches Ergebnis.
  Assert.IsTrue(FResolver.ResolveTypeFrom(BasisUnit, 'TBasis', Other));
  Assert.IsTrue(FResolver.AncestorOf(Kind, Ancestor));
  Assert.AreEqual('TBasis', Ancestor.Name);
  Assert.IsTrue(FResolver.DeclaredMember(Kind, 'Melde', Member));
  Assert.AreEqual('TBasis.Melde', Member.QualifiedName);
end;

procedure TNameResolverTests.NodeTypeAndPropertyReadsField;
const
  Text = 'unit Haupt;'#10'interface'#10'type'#10'  TPunkt = record'#10'    X: Integer;'#10'  end;'#10 +
    '  TFigur = class'#10'  private'#10'    FPos: TPunkt;'#10'    function GetMitte: TPunkt;'#10'  public'#10 +
    '    property Pos: TPunkt read FPos;'#10'    property Mitte: TPunkt read GetMitte;'#10'  end;'#10 +
    'implementation'#10'function TFigur.GetMitte: TPunkt;'#10'begin'#10'end;'#10 +
    'procedure P(F: TFigur);'#10'begin'#10'  F.Pos.X := 1;'#10'  F.Mitte.X := 2;'#10'end;'#10'end.';
var
  Tree: TSyntaxTree;
  Receivers: TArray<TSyntaxNode>;
  Symbol, TypeInfo: TResolvedSymbol;
  TypeFound, ReadsField: Boolean;
begin
  Tree := TPascalParser.Parse(Text);
  try
    Receivers := nil;
    Tree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        if (ANode.Kind = TSyntaxKind.MemberAccess) and MatchText(ANode.Name, ['Pos', 'Mitte']) then
          Receivers := Receivers + [ANode];
        Result := True;
      end);
    Assert.AreEqual(2, Integer(Length(Receivers)));
    // #1005: Deklaration und Typ eines Teilausdrucks, und ob die Property ein Feld liest.
    Assert.IsTrue(FResolver.NodeType(Tree, 'C:\P\Haupt.pas', Receivers[0], Symbol, TypeInfo, TypeFound));
    Assert.AreEqual('Pos', Symbol.Name);
    Assert.IsTrue(TypeFound);
    Assert.AreEqual('TPunkt', TypeInfo.Name);
    Assert.IsTrue(TypeInfo.SymbolKind = TIndexSymbolKind.RecordType);
    Assert.IsTrue(FResolver.PropertyReadsField(Symbol, ReadsField));
    Assert.IsTrue(ReadsField);
    Assert.IsTrue(FResolver.NodeType(Tree, 'C:\P\Haupt.pas', Receivers[1], Symbol, TypeInfo, TypeFound));
    Assert.AreEqual('Mitte', Symbol.Name);
    Assert.IsTrue(FResolver.PropertyReadsField(Symbol, ReadsField));
    Assert.IsFalse(ReadsField);
    Assert.IsFalse(FResolver.PropertyReadsField(TypeInfo, ReadsField));
  finally
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TNameResolverTests);

end.
