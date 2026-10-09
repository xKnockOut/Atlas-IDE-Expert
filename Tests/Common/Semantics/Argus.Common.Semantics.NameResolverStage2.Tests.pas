unit Argus.Common.Semantics.NameResolverStage2.Tests;

// Tests für die Namensauflösung, Ausbaustufe 2 (#263): Überladungen,
// Generics, Helfer, with, Inline-Variablen, Sichtbarkeit und Ausdrücke
// als Empfänger. Je Punkt ein positiver und ein negativer Fall.

interface

uses
  DUnitX.TestFramework,
  Argus.Common.Index.Contract,
  Argus.Common.Semantics.NameResolver;

type
  [TestFixture]
  TNameResolverStage2Tests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    procedure AddUnit(const AFileName, AText: string);
    function ResolveAllAt(const AText, AMarker: string; AOccurrence: Integer = 1): TArray<TResolvedSymbol>;
    function ResolveAt(const AText, AMarker: string; AOccurrence: Integer = 1): TResolvedSymbol;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ChoosesOverloadByArgumentCount;
    [Test]
    procedure AmbiguousOverloadsGiveAllCandidates;
    [Test]
    procedure SubstitutesGenericTypeArguments;
    [Test]
    procedure FollowsGenericAncestors;
    [Test]
    procedure BindsGenericMethodArguments;
    [Test]
    procedure UsesHelpersForBuiltinAndClassTypes;
    [Test]
    procedure WithFindsMembersOfExpression;
    [Test]
    procedure WithUnknownTypeGivesNoResult;
    [Test]
    procedure InfersInlineVarTypes;
    [Test]
    procedure ForVarIsLocalToLoop;
    [Test]
    procedure HidesMembersByVisibility;
    [Test]
    procedure ResolvesExpressionReceivers;
    [Test]
    procedure IndexKeepsSignaturesAndGenerics;
  end;

implementation

uses
  System.SysUtils,
  Argus.Common.Documents.Contract,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Pascal.Parser,
  Argus.Common.Index.SymbolIndex,
  Argus.Common.Index.Cache,
  Argus.Common.Index.Extractor;

const
  UnitSystem =
    'unit System;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TObject = class'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '  end;'#10 +
    '  IInterface = interface end;'#10 +
    '  TArray<T> = array of T;'#10 +
    'implementation'#10 +
    'constructor TObject.Create; begin end;'#10 +
    'end.';

  UnitSysUtils =
    'unit System.SysUtils;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFormatSettings = record'#10 +
    '    DecimalSeparator: Char;'#10 +
    '  end;'#10 +
    '  TStringHelper = record helper for string'#10 +
    '    function Split(const Separators: array of Char): TArray<string>;'#10 +
    '    function ToUpper: string;'#10 +
    '  end;'#10 +
    'function Format(const Format: string; const Args: array of const): string; overload;'#10 +
    'function Format(const Format: string; const Args: array of const;'#10 +
    '  const AFormatSettings: TFormatSettings): string; overload;'#10 +
    'function IntToStr(Value: Integer): string; overload;'#10 +
    'function IntToStr(Value: Int64): string; overload;'#10 +
    'implementation'#10 +
    'end.';

  UnitCollections =
    'unit System.Generics.Collections;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TList<T> = class'#10 +
    '  private'#10 +
    '    FCount: Integer;'#10 +
    '    function GetItem(Index: Integer): T;'#10 +
    '  public'#10 +
    '    function First: T;'#10 +
    '    function Add(const Value: T): Integer;'#10 +
    '    function Map<R>(const Value: R): R;'#10 +
    '    property Items[Index: Integer]: T read GetItem; default;'#10 +
    '    property Count: Integer read FCount;'#10 +
    '  end;'#10 +
    '  TObjectList<T> = class(TList<T>)'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

  UnitKunden =
    'unit Kunden;'#10 +
    'interface'#10 +
    'uses System.Generics.Collections;'#10 +
    'type'#10 +
    '  TKunde = class'#10 +
    '  strict private'#10 +
    '    FGeheim: Integer;'#10 +
    '  private'#10 +
    '    FIntern: Integer;'#10 +
    '  protected'#10 +
    '    procedure Schuetzt;'#10 +
    '  public'#10 +
    '    Name: string;'#10 +
    '    function Kopie: TKunde;'#10 +
    '  end;'#10 +
    '  TKundenListe = class(TObjectList<TKunde>)'#10 +
    '  end;'#10 +
    '  TKundeHelper = class helper for TKunde'#10 +
    '    function Anrede: string;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TKunde.Schuetzt; begin end;'#10 +
    'function TKunde.Kopie: TKunde; begin Result := Self; end;'#10 +
    'function TKundeHelper.Anrede: string; begin Result := ''''; end;'#10 +
    'end.';

  // Rumpf einer Routine in Haupt; Kopf mit allen Variablen der Tests.
  Head =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses System.SysUtils, System.Generics.Collections, Kunden;'#10 +
    'type'#10 +
    '  TMein = class(TKunde)'#10 +
    '    procedure Arbeite;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function Liefere(A: Integer): TKunde; begin Result := nil; end;'#10 +
    'procedure TMein.Arbeite; begin Schuetzt; end;'#10 +
    'procedure P;'#10 +
    'var'#10 +
    '  L: TList<TKunde>;'#10 +
    '  Liste: TKundenListe;'#10 +
    '  K: TKunde;'#10 +
    '  S: string;'#10 +
    '  I: Integer;'#10 +
    '  O: TObject;'#10 +
    '  FS: TFormatSettings;'#10 +
    '  Name: Integer;'#10 +
    'begin'#10;
  Tail =
    #10'end;'#10 +
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

{ TNameResolverStage2Tests }

procedure TNameResolverStage2Tests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  AddUnit('C:\Lib\System.pas', UnitSystem);
  AddUnit('C:\Lib\System.SysUtils.pas', UnitSysUtils);
  AddUnit('C:\Lib\System.Generics.Collections.pas', UnitCollections);
  AddUnit('C:\P\Kunden.pas', UnitKunden);
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TNameResolverStage2Tests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

procedure TNameResolverStage2Tests.AddUnit(const AFileName, AText: string);
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(AText, AFileName, nil));
end;

function TNameResolverStage2Tests.ResolveAllAt(const AText, AMarker: string;
  AOccurrence: Integer): TArray<TResolvedSymbol>;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := FResolver.ResolveAll(Tree, 'C:\P\Haupt.pas', PositionOf(AText, AMarker, AOccurrence));
  finally
    Tree.Free;
  end;
end;

function TNameResolverStage2Tests.ResolveAt(const AText, AMarker: string; AOccurrence: Integer): TResolvedSymbol;
var
  Results: TArray<TResolvedSymbol>;
begin
  Results := ResolveAllAt(AText, AMarker, AOccurrence);
  if Length(Results) > 0 then
    Result := Results[0]
  else
    Result := Default(TResolvedSymbol);
end;

procedure TNameResolverStage2Tests.ChoosesOverloadByArgumentCount;
const
  Source = Head + '  S := Format(''%d'', [1]);'#10'  S := Format(''%d'', [1], FS);' + Tail;
var
  R: TResolvedSymbol;
begin
  R := ResolveAt(Source, 'Format(''%d'', [1]);');
  Assert.AreEqual('System.SysUtils', R.UnitName);
  Assert.AreEqual(2, R.MaxArgs);
  R := ResolveAt(Source, 'Format(''%d'', [1], FS)');
  Assert.AreEqual(3, R.MaxArgs);
  // Negativ: drei Argumente wählen nie die Überladung mit zwei.
  Assert.AreEqual(1, Integer(Length(ResolveAllAt(Source, 'Format(''%d'', [1], FS)'))));
end;

procedure TNameResolverStage2Tests.AmbiguousOverloadsGiveAllCandidates;
const
  Source = Head + '  S := IntToStr(I);'#10'  S := IntToStr(Name);' + Tail;
begin
  // Integer passt genau, Int64 nur der Familie nach: beide gleich gut, also beide.
  Assert.AreEqual(2, Integer(Length(ResolveAllAt(Source, 'IntToStr(I)'))));
  Assert.IsTrue(ResolveAt(Source, 'IntToStr(I)').Found);
end;

procedure TNameResolverStage2Tests.SubstitutesGenericTypeArguments;
const
  Source = Head + '  S := L.First.Name;'#10'  S := L.Items[0].Name;'#10'  S := L[0].Name;'#10 +
    '  S := L.First.Unbekannt;' + Tail;
var
  R: TResolvedSymbol;
begin
  R := ResolveAt(Source, 'Name;');
  Assert.AreEqual('TKunde', R.Container);
  Assert.AreEqual('Kunden', R.UnitName);
  Assert.AreEqual('TKunde', ResolveAt(Source, 'Name;', 2).Container);
  Assert.AreEqual('TKunde', ResolveAt(Source, 'Name;', 3).Container);
  Assert.IsFalse(ResolveAt(Source, 'Unbekannt').Found);
end;

procedure TNameResolverStage2Tests.FollowsGenericAncestors;
const
  Source = Head + '  S := Liste.First.Name;'#10'  I := Liste.Count;'#10'  S := Liste.FCount;' + Tail;
begin
  Assert.AreEqual('TKunde', ResolveAt(Source, 'Name;').Container);
  Assert.AreEqual('TList', ResolveAt(Source, 'Count;').Container);
  // FCount ist private in einer anderen Unit.
  Assert.IsFalse(ResolveAt(Source, 'FCount').Found);
end;

procedure TNameResolverStage2Tests.BindsGenericMethodArguments;
const
  Source = Head + '  S := L.Map<TKunde>(K).Name;'#10'  S := L.Map<Integer>(1).Name;' + Tail;
begin
  Assert.AreEqual('TKunde', ResolveAt(Source, 'Name;').Container);
  Assert.IsFalse(ResolveAt(Source, 'Name;', 2).Found);
end;

procedure TNameResolverStage2Tests.UsesHelpersForBuiltinAndClassTypes;
const
  Source = Head + '  S.Split(['','']);'#10'  S := K.Anrede;'#10'  I.Split(['','']);' + Tail;
var
  R: TResolvedSymbol;
begin
  R := ResolveAt(Source, 'Split');
  Assert.AreEqual('TStringHelper', R.Container);
  Assert.AreEqual('System.SysUtils', R.UnitName);
  Assert.AreEqual('TKundeHelper', ResolveAt(Source, 'Anrede').Container);
  Assert.IsFalse(ResolveAt(Source, 'Split', 2).Found);
end;

procedure TNameResolverStage2Tests.WithFindsMembersOfExpression;
const
  Source = Head + '  with L.First do'#10'    S := Kopie.Name;'#10'  with K do'#10'    Name := '''';' + Tail;
begin
  Assert.AreEqual('TKunde', ResolveAt(Source, 'Kopie').Container);
  // Mitglied verdeckt die lokale Variable Name: Integer.
  Assert.AreEqual('TKunde', ResolveAt(Source, 'Name :=').Container);
end;

procedure TNameResolverStage2Tests.WithUnknownTypeGivesNoResult;
const
  Source = Head + '  with Unbekannt do'#10'    Name := 1;'#10'  Name := 2;' + Tail;
var
  R: TResolvedSymbol;
begin
  Assert.IsFalse(ResolveAt(Source, 'Name := 1').Found);
  // Außerhalb des with wieder die lokale Variable.
  R := ResolveAt(Source, 'Name := 2');
  Assert.IsTrue(R.Kind = TResolvedKind.Local);
end;

procedure TNameResolverStage2Tests.InfersInlineVarTypes;
const
  Source = Head + '  var Neu := TKunde.Create;'#10'  S := Neu.Name;'#10 +
    '  var W := if True then ''a'' else ''b'';'#10'  S := W.ToUpper;'#10 +
    '  var Zahl := 5;'#10'  Zahl.ToUpper;' + Tail;
begin
  Assert.AreEqual('TKunde', ResolveAt(Source, 'Name;').Container);
  Assert.AreEqual('TStringHelper', ResolveAt(Source, 'ToUpper').Container);
  Assert.IsFalse(ResolveAt(Source, 'ToUpper', 2).Found);
end;

procedure TNameResolverStage2Tests.ForVarIsLocalToLoop;
const
  Source = Head + '  for var Lauf := 0 to 3 do'#10'    I := Lauf;'#10'  I := Lauf;' + Tail;
var
  R: TResolvedSymbol;
begin
  R := ResolveAt(Source, 'Lauf;');
  Assert.IsTrue(R.Kind = TResolvedKind.Local);
  Assert.IsFalse(ResolveAt(Source, 'Lauf;', 2).Found);
end;

procedure TNameResolverStage2Tests.HidesMembersByVisibility;
const
  Source = Head + '  I := K.FIntern;'#10'  I := K.FGeheim;'#10'  K.Schuetzt;'#10'  S := K.Name;' + Tail;
var
  R: TResolvedSymbol;
begin
  Assert.IsFalse(ResolveAt(Source, 'FIntern').Found);
  Assert.IsFalse(ResolveAt(Source, 'FGeheim').Found);
  Assert.IsFalse(ResolveAt(Source, 'Schuetzt;', 2).Found);
  Assert.IsTrue(ResolveAt(Source, 'Name;').Found);
  // protected im Nachfahren sichtbar.
  R := ResolveAt(Source, 'Schuetzt;');
  Assert.AreEqual('TKunde', R.Container);
end;

procedure TNameResolverStage2Tests.ResolvesExpressionReceivers;
const
  Source = Head + '  S := Liefere(1).Name;'#10'  S := (O as TKunde).Name;'#10'  S := L.First.Kopie.Name;'#10 +
    '  S := (O as Unbekannt).Name;' + Tail;
begin
  Assert.AreEqual('TKunde', ResolveAt(Source, 'Name;').Container);
  Assert.AreEqual('TKunde', ResolveAt(Source, 'Name;', 2).Container);
  Assert.AreEqual('TKunde', ResolveAt(Source, 'Name;', 3).Container);
  Assert.IsFalse(ResolveAt(Source, 'Name;', 4).Found);
end;

procedure TNameResolverStage2Tests.IndexKeepsSignaturesAndGenerics;
var
  Units: TArray<TUnitIndex>;
  Symbol: TIndexSymbol;
  Checked: Integer;
begin
  Units := TIndexCache.Deserialize(TIndexCache.Serialize([TIndexExtractor.ExtractText(UnitCollections,
    'C:\Lib\System.Generics.Collections.pas', nil), TIndexExtractor.ExtractText(UnitKunden, 'C:\P\Kunden.pas', nil)]));
  Assert.AreEqual(2, Integer(Length(Units)));
  Checked := 0;
  for Symbol in Units[0].Symbols do
    if (Symbol.Name = 'TList') then
    begin
      Assert.AreEqual('T', Symbol.TypeParams);
      Inc(Checked);
    end
    else if (Symbol.Name = 'Items') then
    begin
      Assert.IsTrue(Symbol.IsDefault);
      Assert.AreEqual(1, Symbol.MaxArgs);
      Inc(Checked);
    end
    else if (Symbol.Name = 'FCount') then
    begin
      Assert.AreEqual(Ord(TIndexVisibility.Private), Ord(Symbol.Visibility));
      Inc(Checked);
    end;
  for Symbol in Units[1].Symbols do
    if Symbol.Name = 'TKundenListe' then
    begin
      Assert.AreEqual('TObjectList', Symbol.Ancestors[0]);
      Assert.AreEqual('TKunde', Symbol.AncestorArgs);
      Inc(Checked);
    end;
  Assert.AreEqual(4, Checked);
end;

initialization
  TDUnitX.RegisterTestFixture(TNameResolverStage2Tests);

end.
