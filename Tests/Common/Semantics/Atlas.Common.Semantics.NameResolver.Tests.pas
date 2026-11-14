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
    function ResolveAt(const AText, AMarker: string): TResolvedSymbol; overload;
    function ResolveAt(const AText, AMarker: string; AOccurrence: Integer): TResolvedSymbol; overload;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ResolvesLocalsParametersAndResult;
    [Test]
    procedure DuplicateLocalsAndResultLikeDcc;
    [Test]
    procedure NodeTypeAndPropertyReadsField;
    [Test]
    procedure ResolvesInlineVarsOnlyAfterDeclaration;
    [Test]
    procedure ResolvesMembersInMethodsAndSelf;
    [Test]
    procedure ResolvesPropertyAccessors;
    [Test]
    procedure LocalsHideFieldsOfTheSameName;
    [Test]
    procedure AnonymousMethodLocalsHideFields;
    [Test]
    procedure CandidatesInAnonymousMethodHideFields;
    /// <summary>Methoden verschachtelter Typen in strict-Abschnitten ohne Endlosrekursion.</summary>
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
    procedure NamespacesChangeRememberedUnits;
    [Test]
    procedure LoadsOnlyUnitsMissingFromIndex;
    [Test]
    procedure GivesUpOnExpressions;
    [Test]
    procedure FallsBackToSystem;
    /// <summary>PinTree desselben Baums verschachtelt; erst das letzte UnpinTree löst.</summary>
    [Test]
    procedure PinTreeNestedSameTreeKeepsPin;
    /// <summary>Ein Fremdbaum über dem eigenen; nach seinem UnpinTree gilt der eigene weiter.</summary>
    [Test]
    procedure PinTreeNestedOtherTreeRestoresOuter;
    [Test]
    procedure ExtractedUnitEqualsExtract;
    [Test]
    procedure UnpinTreeWithoutPinIsNoop;
    /// <summary>ResolveTypeFrom leert den Helfer-Cache nicht mehr.</summary>
    [Test]
    procedure ResolveTypeFromKeepsHelperCache;
    /// <summary>Helfer nur aus implementation-uses sind im interface-Teil nicht sichtbar,
    /// auch wenn derselbe Resolver sie vorher im implementation-Teil gefunden hat.</summary>
    [Test]
    procedure HelperVisibilityDependsOnSection;
    /// <summary>DeclaredMember über die Namenstabelle, auch geerbt; Vorfahren-Cache
    /// über ResolveTypeFrom hinweg.</summary>
    [Test]
    procedure DeclaredMemberFindsInherited;
    /// <summary>#1028: Typtext mit Typargumenten wählt den generischen Typ nach der Zahl der Typparameter.
    /// </summary>
    [Test]
    procedure ResolveTypeTextFromPicksArity;
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
  cUnitBasis =
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

  cUnitZweit =
    'unit Zweit;'#10 +
    'interface'#10 +
    'function Wert: Integer;'#10 +
    'implementation'#10 +
    'function Wert: Integer; begin Result := 2; end;'#10 +
    'end.';

  cUnitSystem =
    'unit System;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TObject = class'#10 +
    '    procedure Free;'#10 +
    '  end;'#10 +
    'procedure WriteLn;'#10 +
    'implementation'#10 +
    'end.';

  cUnitDotted =
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
  mIndex, mFound, mLine, mLineStart: Integer;
begin
  mFound := 0;
  mIndex := 0;
  repeat
    mIndex := Pos(AMarker, AText, mIndex + 1);
    if mIndex = 0 then
    begin
      raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
    end;
    Inc(mFound);
  until mFound = AOccurrence;
  mLine := 0;
  mLineStart := 1;
  for mFound := 1 to mIndex - 1 do
  begin
    if AText[mFound] = #10 then
    begin
      Inc(mLine);
      mLineStart := mFound + 1;
    end;
  end;
  Result := TTextPosition.Create(mLine, mIndex - mLineStart);
end;

{ TNameResolverTests }

procedure TNameResolverTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  AddUnit('C:\Lib\System.pas', cUnitSystem);
  AddUnit('C:\P\Basis.pas', cUnitBasis);
  AddUnit('C:\P\Zweit.pas', cUnitZweit);
  AddUnit('C:\P\Firma.Werkzeuge.pas', cUnitDotted);
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

function TNameResolverTests.ResolveAt(const AText, AMarker: string): TResolvedSymbol;
begin
  Result := ResolveAt(AText, AMarker, 1);
end;

function TNameResolverTests.ResolveAt(const AText, AMarker: string; AOccurrence: Integer): TResolvedSymbol;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := FResolver.Resolve(mTree, 'C:\P\Haupt.pas', PositionOf(AText, AMarker, AOccurrence));
  finally
    mTree.Free;
  end;
end;

procedure TNameResolverTests.ResolvesLocalsParametersAndResult;
const
  cSource =
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
  R := ResolveAt(cSource, 'Zwischen :=');
  Assert.AreEqual<TResolvedKind>(TResolvedKind.Local, R.Kind);
  Assert.AreEqual('Double', R.TypeName);
  Assert.AreEqual(6, R.SelectionRange.StartPos.Line);
  R := ResolveAt(cSource, 'B;');
  Assert.IsTrue(R.IsParameter);
  Assert.AreEqual('Integer', R.TypeName);
  R := ResolveAt(cSource, 'Result :=');
  Assert.AreEqual<TResolvedKind>(TResolvedKind.Local, R.Kind);
  Assert.AreEqual('Integer', R.TypeName);
  R := ResolveAt(cSource, 'Zaehler;');
  Assert.AreEqual<TResolvedKind>(TResolvedKind.Symbol, R.Kind);
  Assert.AreEqual('Haupt', R.UnitName);
  Assert.AreEqual(3, R.SelectionRange.StartPos.Line);
end;

procedure TNameResolverTests.DuplicateLocalsAndResultLikeDcc;
const
  // #1369: Wie dcc gilt von zwei lokalen Deklarationen die letzte (E2004), und Result hat den Typ aus dem
  // interface-Teil, auch wenn der Kopf der Implementierung abweicht (E2037).
  cSource =
    'unit Haupt;'#10 +
    'interface'#10 +
    'function Liefere: Integer;'#10 +
    'implementation'#10 +
    'function Liefere: string;'#10 +
    'var'#10 +
    '  Wert: Integer;'#10 +
    '  Wert: string;'#10 +
    'begin'#10 +
    '  Wert := '''';'#10 +
    '  Result := '''';'#10 +
    'end;'#10 +
    'function Intern: string;'#10 +
    'begin'#10 +
    '  Result := '''';'#10 +
    'end;'#10 +
    'end.';
var
  R: TResolvedSymbol;
begin
  R := ResolveAt(cSource, 'Wert :=');
  Assert.AreEqual('string', R.TypeName);
  Assert.AreEqual(7, R.SelectionRange.StartPos.Line);
  R := ResolveAt(cSource, 'Result :=');
  Assert.AreEqual('Integer', R.TypeName);
  // Ohne Deklaration im interface-Teil gilt der eigene Kopf.
  R := ResolveAt(cSource, 'Result :=', 2);
  Assert.AreEqual('string', R.TypeName);
end;

procedure TNameResolverTests.ResolvesStrictMembersInNestedTypeMethods;
const
  cSource =
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
  R := ResolveAt(cSource, 'FWert := 1');
  Assert.IsTrue(R.Found, 'strict private Feld im eigenen Rumpf');
  Assert.AreEqual('Integer', R.TypeName);
  Assert.AreEqual(8, R.SelectionRange.StartPos.Line);
  R := ResolveAt(cSource, 'FZahl := 2');
  Assert.IsTrue(R.Found, 'strict protected Feld im eigenen Rumpf');
  Assert.AreEqual(15, R.SelectionRange.StartPos.Line);
end;

procedure TNameResolverTests.ResolvesInlineVarsOnlyAfterDeclaration;
const
  cSource =
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
  R := ResolveAt(cSource, 'X := 1');
  Assert.AreEqual<TResolvedKind>(TResolvedKind.Symbol, R.Kind, 'vor der Inline-Variablen gilt die globale');
  R := ResolveAt(cSource, 'X := ''a''');
  Assert.AreEqual<TResolvedKind>(TResolvedKind.Local, R.Kind);
  Assert.AreEqual('string', R.TypeName);
end;

procedure TNameResolverTests.ResolvesMembersInMethodsAndSelf;
const
  cSource =
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
  R := ResolveAt(cSource, 'FWert := 1');
  Assert.AreEqual<TResolvedKind>(TResolvedKind.Symbol, R.Kind);
  Assert.AreEqual('TFoo.FWert', R.QualifiedName);
  Assert.AreEqual(5, R.SelectionRange.StartPos.Line);
  R := ResolveAt(cSource, 'FWert := 2');
  Assert.AreEqual('TFoo.FWert', R.QualifiedName);
  R := ResolveAt(cSource, 'Self');
  Assert.IsTrue(R.IsType);
  Assert.AreEqual('TFoo', R.Name);
  // Methodenkopf in implementation führt zur Deklaration in der Klasse.
  R := ResolveAt(cSource, 'Run;', 2);
  Assert.AreEqual('TFoo.Run', R.QualifiedName);
  Assert.AreEqual(6, R.SelectionRange.StartPos.Line);
end;

procedure TNameResolverTests.ResolvesPropertyAccessors;
const
  cSource =
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '  strict private'#10 +
    '    FWert: Integer;'#10 +
    '    procedure SetWert(AValue: Integer);'#10 +
    '  public'#10 +
    '    property Wert: Integer read FWert write SetWert;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFoo.SetWert(AValue: Integer);'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';
var
  R: TResolvedSymbol;
begin
  // read und write stehen im Bereich der Klasse, auch für strict private (#690).
  R := ResolveAt(cSource, 'FWert write');
  Assert.AreEqual<TResolvedKind>(TResolvedKind.Symbol, R.Kind);
  Assert.AreEqual('TFoo.FWert', R.QualifiedName);
  Assert.AreEqual(5, R.SelectionRange.StartPos.Line);
  R := ResolveAt(cSource, 'SetWert;');
  Assert.AreEqual('TFoo.SetWert', R.QualifiedName);
  Assert.AreEqual(6, R.SelectionRange.StartPos.Line);
  // Der Typ der Property bleibt ein Typ.
  R := ResolveAt(cSource, 'Integer read');
  Assert.AreNotEqual('TFoo', R.Container, 'Integer ist kein Mitglied');
end;

const
  // Parameter, lokale Variablen und Felder mit gleichem Namen; ohne Self gewinnt wie in Delphi der lokale Name.
  cSourceVerdeckt =
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
  R := ResolveAt(cSourceVerdeckt, 'Name := Name; {M1}');
  Assert.AreEqual<TResolvedKind>(TResolvedKind.Symbol, R.Kind, 'Self.Name ist das Feld');
  Assert.AreEqual('TKunde.Name', R.QualifiedName);
  R := ResolveAt(cSourceVerdeckt, 'Name; {M1}');
  Assert.AreEqual<TResolvedKind>(TResolvedKind.Local, R.Kind);
  Assert.IsTrue(R.IsParameter);
  R := ResolveAt(cSourceVerdeckt, 'Anzahl := Wert; {M2}');
  Assert.AreEqual<TResolvedKind>(TResolvedKind.Local, R.Kind);
  Assert.AreEqual(19, R.SelectionRange.StartPos.Line);
  R := ResolveAt(cSourceVerdeckt, 'Wert; {M2}');
  Assert.AreEqual('TKunde.Wert', R.QualifiedName);
end;

procedure TNameResolverTests.AnonymousMethodLocalsHideFields;
var
  R: TResolvedSymbol;
begin
  // Parameter der anonymen Methode verdeckt das Feld Wert; Anzahl bleibt das Feld.
  R := ResolveAt(cSourceVerdeckt, 'Wert; {M3}');
  Assert.AreEqual<TResolvedKind>(TResolvedKind.Local, R.Kind);
  Assert.IsTrue(R.IsParameter);
  Assert.AreEqual(28, R.SelectionRange.StartPos.Line);
  R := ResolveAt(cSourceVerdeckt, 'Anzahl := Wert; {M3}');
  Assert.AreEqual('TKunde.Anzahl', R.QualifiedName);
  // var-Abschnitt der anonymen Methode; Wert ist dort wieder das Feld.
  R := ResolveAt(cSourceVerdeckt, 'Anzahl := Wert; {M4}');
  Assert.AreEqual<TResolvedKind>(TResolvedKind.Local, R.Kind);
  Assert.AreEqual(34, R.SelectionRange.StartPos.Line);
  R := ResolveAt(cSourceVerdeckt, 'Wert; {M4}');
  Assert.AreEqual('TKunde.Wert', R.QualifiedName);
  R := ResolveAt(cSourceVerdeckt, 'Result := Anzahl');
  Assert.AreEqual<TResolvedKind>(TResolvedKind.Local, R.Kind);
  // Außerhalb der anonymen Methoden gilt wieder das Feld.
  R := ResolveAt(cSourceVerdeckt, 'Wert := 1; {M5}');
  Assert.AreEqual('TKunde.Wert', R.QualifiedName);
end;

procedure TNameResolverTests.CandidatesInAnonymousMethodHideFields;
var
  mTree: TSyntaxTree;
  mCandidates: TArray<TResolvedSymbol>;
  mCandidate: TResolvedSymbol;
  mFound: Integer;
begin
  mTree := TPascalParser.Parse(cSourceVerdeckt);
  try
    mCandidates := FResolver.Candidates.OwnScopeCandidates(mTree, 'C:\P\Haupt.pas', Pos('Anzahl := Wert; {M3}',
      cSourceVerdeckt) - 1);
    FResolver.Candidates.UsedScopeCandidates;
  finally
    mTree.Free;
  end;
  mFound := 0;
  for mCandidate in mCandidates do
  begin
    if SameText(mCandidate.Name, 'Wert') then
    begin
      Inc(mFound);
      Assert.IsTrue(mCandidate.IsParameter);
      Assert.AreEqual(1, Integer(Length(mCandidate.Hides)));
      Assert.AreEqual('Feld TKunde.Wert', mCandidate.Hides[0]);
    end;
  end;
  Assert.AreEqual(1, mFound);
end;

procedure TNameResolverTests.ResolvesInheritedMembersAcrossUnits;

const
  cSource =
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
  R := ResolveAt(cSource, 'Melde');
  Assert.AreEqual('TBasis.Melde', R.QualifiedName);
  Assert.AreEqual('Basis', R.UnitName);
  Assert.AreEqual('C:\P\Basis.pas', R.FileName);
  R := ResolveAt(cSource, 'FName');
  Assert.AreEqual('TBasis.FName', R.QualifiedName);
  // TBasis ohne Vorfahr erbt von System.TObject.
  R := ResolveAt(cSource, 'Free');
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
  cSource =
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
  R := ResolveAt(cSource, 'Melde');
  Assert.AreEqual('TBasis.Melde', R.QualifiedName);
  R := ResolveAt(cSource, 'FName');
  Assert.AreEqual('TBasis.FName', R.QualifiedName);
  R := ResolveAt(cSource, 'Create');
  Assert.AreEqual('TBasis.Create', R.QualifiedName);
  Assert.AreEqual<TIndexSymbolKind>(TIndexSymbolKind.Constructor_, R.SymbolKind);
end;

procedure TNameResolverTests.ResolvesQualifiedNames;
const
  cSource =
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
  R := ResolveAt(cSource, 'Wert');
  Assert.AreEqual('Basis', R.UnitName, 'Basis.Wert trotz Zweit dahinter');
  R := ResolveAt(cSource, 'Basis', 2);
  Assert.AreEqual<TResolvedKind>(TResolvedKind.UnitName, R.Kind);
  R := ResolveAt(cSource, 'Create');
  Assert.AreEqual('TBasis.Create', R.QualifiedName);
  R := ResolveAt(cSource, 'TWerkzeug');
  Assert.AreEqual('Firma.Werkzeuge', R.UnitName);
  // Create gibt es in TWerkzeug nicht, aber im Vorfahren TObject? Nein: nur Free.
  R := ResolveAt(cSource, 'Create', 2);
  Assert.IsFalse(R.Found);
end;

procedure TNameResolverTests.InterfaceDoesNotSeeImplementation;
const
  cSource =
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
  R := ResolveAt(cSource, 'B;');
  Assert.IsFalse(R.Found);
  R := ResolveAt(cSource, 'B;', 2);
  Assert.IsTrue(R.Found);
  Assert.AreEqual(4, R.SelectionRange.StartPos.Line);
end;

procedure TNameResolverTests.ResolvesInherited;
const
  cSource =
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
  R := ResolveAt(cSource, 'Create;', 3);
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

procedure TNameResolverTests.NamespacesChangeRememberedUnits;
const
  cSource = 'unit Haupt; interface uses Werkzeuge; implementation procedure P; begin TWerkzeug.Create; end; end.';
var
  R: TResolvedSymbol;
begin
  // Der Resolver merkt sich die Antwort je Unit-Name (#1342); neue Namespaces gelten trotzdem sofort.
  R := ResolveAt(cSource, 'TWerkzeug');
  Assert.IsFalse(R.Found, 'ohne Namespace gibt es keine Unit Werkzeuge');
  R := ResolveAt(cSource, 'TWerkzeug');
  Assert.IsFalse(R.Found, 'gemerkt');
  FResolver.Namespaces := ['Firma'];
  R := ResolveAt(cSource, 'TWerkzeug');
  Assert.AreEqual('Firma.Werkzeuge', R.UnitName);
  FResolver.Namespaces := nil;
  R := ResolveAt(cSource, 'TWerkzeug');
  Assert.IsFalse(R.Found, 'Namespace wieder entfernt');
end;

procedure TNameResolverTests.LoadsOnlyUnitsMissingFromIndex;
const
  cSource = 'unit Haupt; interface uses Werkzeuge, Fehlt; implementation procedure P; begin TWerkzeug.Create; ' +
    'Unbekannt; end; end.';
var
  mCalls: TArray<string>;
  mResolver: TNameResolver;
  mTree: TSyntaxTree;
  R: TResolvedSymbol;
begin
  // Nachladen durchsucht die Suchpfade aller Projekte (#647): nicht für Units, die der Index mit
  // Namespace schon kennt, und eine fehlende Unit je Resolver nur einmal. Die Namespaces probiert
  // der Unit-Resolver selbst; Firma.Fehlt wird nicht noch einmal gesucht.
  mCalls := nil;
  mResolver := TNameResolver.Create(FIndex,
    function(const AUnitName: string): Boolean
    begin
      mCalls := mCalls + [AUnitName];
      Result := False;
    end);
  try
    mResolver.Namespaces := ['Firma'];
    mTree := TPascalParser.Parse(cSource);
    try
      R := mResolver.Resolve(mTree, 'C:\P\Haupt.pas', PositionOf(cSource, 'TWerkzeug', 1));
      Assert.AreEqual('Firma.Werkzeuge', R.UnitName);
      R := mResolver.Resolve(mTree, 'C:\P\Haupt.pas', PositionOf(cSource, 'Unbekannt', 1));
      Assert.IsFalse(R.Found);
    finally
      mTree.Free;
    end;
  finally
    mResolver.Free;
  end;
  Assert.AreEqual('Fehlt', string.Join(',', mCalls));
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
  cPinSource =
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
  cPinOther =
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
  mTree: TSyntaxTree;
  mFirst, mSecond: TUnitIndex;
begin
  mTree := TPascalParser.Parse(cPinSource);
  try
    FResolver.PinTree(mTree, 'C:\P\Haupt.pas');
    FResolver.PinTree(mTree, 'C:\P\Haupt.pas');
    // Gepinnt: dieselbe Auswertung, kein neues Extrakt (gleiches Symbol-Array).
    mFirst := FResolver.ExtractedUnit(mTree, 'C:\P\Haupt.pas');
    mSecond := FResolver.ExtractedUnit(mTree, 'C:\P\Haupt.pas');
    Assert.AreEqual<Pointer>(Pointer(mSecond.Symbols), Pointer(mFirst.Symbols));
    Assert.AreEqual('TBasis.Melde', FResolver.Resolve(mTree, 'C:\P\Haupt.pas',
      PositionOf(cPinSource, 'Melde;', 1)).QualifiedName);
    FResolver.UnpinTree;
    // Das innere UnpinTree löst den Baum noch nicht.
    mSecond := FResolver.ExtractedUnit(mTree, 'C:\P\Haupt.pas');
    Assert.AreEqual<Pointer>(Pointer(mSecond.Symbols), Pointer(mFirst.Symbols));
    Assert.AreEqual('TBasis.Melde', FResolver.Resolve(mTree, 'C:\P\Haupt.pas',
      PositionOf(cPinSource, 'Melde;', 1)).QualifiedName);
    FResolver.UnpinTree;
    // Ungepinnt teilt der Aufruf das am Baum hinterlegte Extrakt (kein neues Extrahieren je Anbieter).
    mSecond := FResolver.ExtractedUnit(mTree, 'C:\P\Haupt.pas');
    Assert.AreEqual<Pointer>(Pointer(mSecond.Symbols), Pointer(mFirst.Symbols));
    Assert.AreEqual(Integer(Length(mFirst.Symbols)), Integer(Length(mSecond.Symbols)));
    Assert.AreEqual('TBasis.Melde', FResolver.Resolve(mTree, 'C:\P\Haupt.pas',
      PositionOf(cPinSource, 'Melde;', 1)).QualifiedName);
  finally
    mTree.Free;
  end;
end;

procedure TNameResolverTests.PinTreeNestedOtherTreeRestoresOuter;
var
  mOuter, mInner: TSyntaxTree;
  mPinned: TUnitIndex;
  R: TResolvedSymbol;
begin
  mOuter := TPascalParser.Parse(cPinSource);
  try
    FResolver.PinTree(mOuter, 'C:\P\Haupt.pas');
    try
      mPinned := FResolver.ExtractedUnit(mOuter, 'C:\P\Haupt.pas');
      mInner := TPascalParser.Parse(cPinOther);
      try
        FResolver.PinTree(mInner, 'C:\P\Andere.pas');
        try
          Assert.AreEqual('Zweit', FResolver.Resolve(mInner, 'C:\P\Andere.pas',
            PositionOf(cPinOther, 'Wert;', 1)).UnitName);
          // Der äußere Baum bleibt gepinnt, auch während der innere es ist.
          Assert.AreEqual<Pointer>(Pointer(FResolver.ExtractedUnit(mOuter, 'C:\P\Haupt.pas').Symbols),
            Pointer(mPinned.Symbols));
        finally
          FResolver.UnpinTree;
        end;
      finally
        mInner.Free;
      end;
      Assert.AreEqual<Pointer>(Pointer(FResolver.ExtractedUnit(mOuter, 'C:\P\Haupt.pas').Symbols),
        Pointer(mPinned.Symbols));
      R := FResolver.Resolve(mOuter, 'C:\P\Haupt.pas', PositionOf(cPinSource, 'Zahl :=', 1));
      Assert.IsTrue(R.Found);
      Assert.AreEqual('Zahl', R.Name);
      Assert.AreEqual<TResolvedKind>(TResolvedKind.Local, R.Kind);
      Assert.AreEqual('TBasis.Melde', FResolver.Resolve(mOuter, 'C:\P\Haupt.pas',
        PositionOf(cPinSource, 'Melde;', 1)).QualifiedName);
    finally
      FResolver.UnpinTree;
    end;
  finally
    mOuter.Free;
  end;
end;

procedure TNameResolverTests.ExtractedUnitEqualsExtract;
var
  mTree: TSyntaxTree;
  mExpected, mActual: TUnitIndex;

  procedure Check;
  var
    mIndex: Integer;
  begin
    Assert.AreEqual(mExpected.UnitName, mActual.UnitName);
    Assert.AreEqual(Integer(Length(mExpected.Symbols)), Integer(Length(mActual.Symbols)));
    for mIndex := 0 to High(mExpected.Symbols) do
    begin
      Assert.AreEqual(mExpected.Symbols[mIndex].QualifiedName, mActual.Symbols[mIndex].QualifiedName);
      Assert.AreEqual(mExpected.Symbols[mIndex].Range.StartPos.Line, mActual.Symbols[mIndex].Range.StartPos.Line);
    end;
  end;

begin
  mTree := TPascalParser.Parse(cPinSource);
  try
    mExpected := TIndexExtractor.Extract(mTree, 'C:\P\Haupt.pas');
    mActual := FResolver.ExtractedUnit(mTree, 'C:\P\Haupt.pas');
    Check;
    FResolver.PinTree(mTree, 'C:\P\Haupt.pas');
    try
      mActual := FResolver.ExtractedUnit(mTree, 'C:\P\Haupt.pas');
      Check;
    finally
      FResolver.UnpinTree;
    end;
  finally
    mTree.Free;
  end;
end;

procedure TNameResolverTests.UnpinTreeWithoutPinIsNoop;
begin
  FResolver.UnpinTree;
  FResolver.UnpinTree;
  Assert.AreEqual('TBasis.Melde', ResolveAt(cPinSource, 'Melde;').QualifiedName);
end;

const
  cUnitHelfer =
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
  cHelferSource =
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
  mTree: TSyntaxTree;
  mBasisUnit: TUnitIndex;
  mFound: TResolvedSymbol;
begin
  AddUnit('C:\P\Helfer.pas', cUnitHelfer);
  Assert.IsTrue(FIndex.FindUnit('Basis', mBasisUnit));
  mTree := TPascalParser.Parse(cHelferSource);
  try
    FResolver.PinTree(mTree, 'C:\P\Haupt.pas');
    try
      Assert.AreEqual('TBasisHelfer', FResolver.Resolve(mTree, 'C:\P\Haupt.pas',
        PositionOf(cHelferSource, 'Anrede', 1)).Container);
      // Dazwischen aus einer anderen Unit auflösen (wie TypeAt und TypeChain der Vervollständigung).
      Assert.IsTrue(FResolver.ResolveTypeFrom(mBasisUnit, 'TBasis', mFound));
      Assert.AreEqual('TBasisHelfer', FResolver.Resolve(mTree, 'C:\P\Haupt.pas',
        PositionOf(cHelferSource, 'Anrede', 1)).Container);
    finally
      FResolver.UnpinTree;
    end;
  finally
    mTree.Free;
  end;
end;

procedure TNameResolverTests.ResolveTypeTextFromPicksArity;
var
  mListen: TUnitIndex;
  mFound: TResolvedSymbol;
begin
  AddUnit('C:\P\Listen.pas', 'unit Listen;'#10'interface'#10'type'#10'  TListe = class'#10'  end;'#10 +
    '  TListe<T: class> = class'#10'  end;'#10'implementation'#10'end.');
  Assert.IsTrue(FIndex.FindUnit('Listen', mListen));
  Assert.IsTrue(FResolver.ResolveTypeTextFrom(mListen, 'TListe<TObject>', mFound));
  Assert.AreEqual('T', mFound.TypeParams);
  Assert.IsTrue(Pos('T: class', mFound.Signature) > 0, mFound.Signature);
  Assert.AreEqual(1, Integer(Length(mFound.Bindings)));
  Assert.IsTrue(FResolver.ResolveTypeTextFrom(mListen, 'TListe', mFound));
  Assert.AreEqual('', mFound.TypeParams);
  // Eingebaute Typen ohne Deklaration.
  Assert.IsTrue(FResolver.ResolveTypeTextFrom(mListen, 'Integer', mFound));
  Assert.IsTrue(mFound.Builtin);
  Assert.IsFalse(FResolver.ResolveTypeTextFrom(mListen, 'TUnbekannt', mFound));
end;

procedure TNameResolverTests.HelperVisibilityDependsOnSection;
var
  mTree: TSyntaxTree;
  mInImplementation, mInInterface: Integer;
begin
  AddUnit('C:\P\Helfer.pas', cUnitHelfer);
  mTree := TPascalParser.Parse(cHelferSource);
  try
    // Offsets ab 0.
    mInImplementation := Pos('S.Anrede', cHelferSource) - 1;
    mInInterface := Pos('S: TBasis', cHelferSource) - 1;
    FResolver.PinTree(mTree, 'C:\P\Haupt.pas');
    try
      Assert.IsTrue(FResolver.ResolveChain(mTree, 'C:\P\Haupt.pas', ['S', 'Anrede'], mInImplementation).Found);
      Assert.IsFalse(FResolver.ResolveChain(mTree, 'C:\P\Haupt.pas', ['S', 'Anrede'], mInInterface).Found);
      Assert.IsTrue(FResolver.ResolveChain(mTree, 'C:\P\Haupt.pas', ['S', 'Anrede'], mInImplementation).Found);
    finally
      FResolver.UnpinTree;
    end;
  finally
    mTree.Free;
  end;
end;

procedure TNameResolverTests.DeclaredMemberFindsInherited;
const
  cUnitKinder =
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
  mKinderUnit, mBasisUnit: TUnitIndex;
  mKind, mMember, mAncestor, mOther: TResolvedSymbol;
begin
  AddUnit('C:\P\Kinder.pas', cUnitKinder);
  Assert.IsTrue(FIndex.FindUnit('Kinder', mKinderUnit));
  Assert.IsTrue(FIndex.FindUnit('Basis', mBasisUnit));
  Assert.IsTrue(FResolver.ResolveTypeFrom(mKinderUnit, 'TKind', mKind));
  Assert.IsTrue(FResolver.DeclaredMember(mKind, 'Eigen', mMember));
  Assert.AreEqual('TKind.Eigen', mMember.QualifiedName);
  Assert.IsTrue(FResolver.DeclaredMember(mKind, 'melde', mMember));
  Assert.AreEqual('TBasis.Melde', mMember.QualifiedName);
  Assert.IsFalse(FResolver.DeclaredMember(mKind, 'Fehlt', mMember));
  Assert.IsTrue(FResolver.AncestorOf(mKind, mAncestor));
  Assert.AreEqual('TBasis', mAncestor.Name);
  // Vorfahren-Cache über ResolveTypeFrom aus einer anderen Unit hinweg: gleiches Ergebnis.
  Assert.IsTrue(FResolver.ResolveTypeFrom(mBasisUnit, 'TBasis', mOther));
  Assert.IsTrue(FResolver.AncestorOf(mKind, mAncestor));
  Assert.AreEqual('TBasis', mAncestor.Name);
  Assert.IsTrue(FResolver.DeclaredMember(mKind, 'Melde', mMember));
  Assert.AreEqual('TBasis.Melde', mMember.QualifiedName);
end;

procedure TNameResolverTests.NodeTypeAndPropertyReadsField;
const
  cText = 'unit Haupt;'#10'interface'#10'type'#10'  TPunkt = record'#10'    X: Integer;'#10'  end;'#10 +
    '  TFigur = class'#10'  private'#10'    FPos: TPunkt;'#10'    function GetMitte: TPunkt;'#10'  public'#10 +
    '    property Pos: TPunkt read FPos;'#10'    property Mitte: TPunkt read GetMitte;'#10'  end;'#10 +
    'implementation'#10'function TFigur.GetMitte: TPunkt;'#10'begin'#10'end;'#10 +
    'procedure P(F: TFigur);'#10'begin'#10'  F.Pos.X := 1;'#10'  F.Mitte.X := 2;'#10'end;'#10'end.';
var
  mTree: TSyntaxTree;
  mReceivers: TArray<TSyntaxNode>;
  mSymbol, mTypeInfo: TResolvedSymbol;
  mTypeFound, mReadsField: Boolean;
begin
  mTree := TPascalParser.Parse(cText);
  try
    mReceivers := nil;
    mTree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        if (ANode.Kind = TSyntaxKind.MemberAccess) and MatchText(ANode.Name, ['Pos', 'Mitte']) then
        begin
          mReceivers := mReceivers + [ANode];
        end;
        Result := True;
      end);
    Assert.AreEqual(2, Integer(Length(mReceivers)));
    // #1005: Deklaration und Typ eines Teilausdrucks, und ob die Property ein Feld liest.
    Assert.IsTrue(FResolver.NodeType(mTree, 'C:\P\Haupt.pas', mReceivers[0], mSymbol, mTypeInfo, mTypeFound));
    Assert.AreEqual('Pos', mSymbol.Name);
    Assert.IsTrue(mTypeFound);
    Assert.AreEqual('TPunkt', mTypeInfo.Name);
    Assert.AreEqual<TIndexSymbolKind>(TIndexSymbolKind.RecordType, mTypeInfo.SymbolKind);
    Assert.IsTrue(FResolver.PropertyReadsField(mSymbol, mReadsField));
    Assert.IsTrue(mReadsField);
    Assert.IsTrue(FResolver.NodeType(mTree, 'C:\P\Haupt.pas', mReceivers[1], mSymbol, mTypeInfo, mTypeFound));
    Assert.AreEqual('Mitte', mSymbol.Name);
    Assert.IsTrue(FResolver.PropertyReadsField(mSymbol, mReadsField));
    Assert.IsFalse(mReadsField);
    Assert.IsFalse(FResolver.PropertyReadsField(mTypeInfo, mReadsField));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TNameResolverTests);

end.
