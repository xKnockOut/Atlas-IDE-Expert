unit Atlas.Common.Semantics.NameResolver.LanguageFeatures.Tests;

// Tests für die Namensauflösung, Ausbaustufe 2 (#263): Überladungen,
// Generics, Helfer, with, Inline-Variablen, Sichtbarkeit und Ausdrücke
// als Empfänger. Je Punkt ein positiver und ein negativer Fall.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  [TestFixture]
  TNameResolverLanguageFeatureTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    procedure AddUnit(const AFileName, AText: string);
    function ResolveAllAt(const AText, AMarker: string): TArray<TResolvedSymbol>; overload;
    function ResolveAllAt(const AText, AMarker: string; AOccurrence: Integer): TArray<TResolvedSymbol>; overload;
    function ResolveAt(const AText, AMarker: string): TResolvedSymbol; overload;
    function ResolveAt(const AText, AMarker: string; AOccurrence: Integer): TResolvedSymbol; overload;
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
    procedure ParameterTypeAliasFitsItsBaseType;
    [Test]
    procedure SubstitutesGenericTypeArguments;
    [Test]
    procedure FollowsGenericAncestors;
    [Test]
    procedure NonGenericTypeBeatsGenericOfSameName;
    [Test]
    procedure BindsGenericMethodArguments;
    [Test]
    procedure UsesHelpersForBuiltinAndClassTypes;
    /// <summary>#686: sichtbarer Helper zu einem Typnamen, auch für eingebaute Typen.</summary>
    [Test]
    procedure VisibleHelperForTypeName;
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
    [Test]
    procedure MissingMembersOfGenericInterfaces;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Cache,
  Atlas.Common.Index.Extractor;

const
  cUnitSystem =
    'unit System;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TObject = class'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '  end;'#10 +
    '  IInterface = interface end;'#10 +
    '  TArray<T> = array of T;'#10 +
    '  TDateTime = type Double;'#10 +
    'implementation'#10 +
    'constructor TObject.Create; begin end;'#10 +
    'end.';

  cUnitSysUtils =
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
    'function FileAge(const FileName: string): LongInt; overload; deprecated;'#10 +
    'function FileAge(const FileName: string; out FileDateTime: TDateTime;'#10 +
    '  FollowLink: Boolean = True): Boolean; overload;'#10 +
    'implementation'#10 +
    'end.';

  cUnitCollections =
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

  cUnitKunden =
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
  cHead =
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
    '  Alter: TDateTime;'#10 +
    'begin'#10;
  cTail =
    #10'end;'#10 +
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

{ TNameResolverLanguageFeatureTests }

procedure TNameResolverLanguageFeatureTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  AddUnit('C:\Lib\System.pas', cUnitSystem);
  AddUnit('C:\Lib\System.SysUtils.pas', cUnitSysUtils);
  AddUnit('C:\Lib\System.Generics.Collections.pas', cUnitCollections);
  AddUnit('C:\P\Kunden.pas', cUnitKunden);
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TNameResolverLanguageFeatureTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

procedure TNameResolverLanguageFeatureTests.AddUnit(const AFileName, AText: string);
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(AText, AFileName, nil));
end;

function TNameResolverLanguageFeatureTests.ResolveAllAt(const AText, AMarker: string): TArray<TResolvedSymbol>;
begin
  Result := ResolveAllAt(AText, AMarker, 1);
end;

function TNameResolverLanguageFeatureTests.ResolveAllAt(const AText, AMarker: string;
  AOccurrence: Integer): TArray<TResolvedSymbol>;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := FResolver.ResolveAll(mTree, 'C:\P\Haupt.pas', PositionOf(AText, AMarker, AOccurrence));
  finally
    mTree.Free;
  end;
end;

function TNameResolverLanguageFeatureTests.ResolveAt(const AText, AMarker: string): TResolvedSymbol;
begin
  Result := ResolveAt(AText, AMarker, 1);
end;

function TNameResolverLanguageFeatureTests.ResolveAt(const AText, AMarker: string;
  AOccurrence: Integer): TResolvedSymbol;
var
  mResults: TArray<TResolvedSymbol>;
begin
  mResults := ResolveAllAt(AText, AMarker, AOccurrence);
  if Length(mResults) > 0 then
  begin
    Result := mResults[0];
  end
  else
  begin
    Result := Default(TResolvedSymbol);
  end;
end;

procedure TNameResolverLanguageFeatureTests.ChoosesOverloadByArgumentCount;
const
  cSource = cHead + '  S := Format(''%d'', [1]);'#10'  S := Format(''%d'', [1], FS);' + cTail;
var
  R: TResolvedSymbol;
begin
  R := ResolveAt(cSource, 'Format(''%d'', [1]);');
  Assert.AreEqual('System.SysUtils', R.UnitName);
  Assert.AreEqual(2, R.MaxArgs);
  R := ResolveAt(cSource, 'Format(''%d'', [1], FS)');
  Assert.AreEqual(3, R.MaxArgs);
  // Negativ: drei Argumente wählen nie die Überladung mit zwei.
  Assert.AreEqual(1, Integer(Length(ResolveAllAt(cSource, 'Format(''%d'', [1], FS)'))));
end;

procedure TNameResolverLanguageFeatureTests.AmbiguousOverloadsGiveAllCandidates;
const
  cSource = cHead + '  S := IntToStr(I);'#10'  S := IntToStr(Name);' + cTail;
begin
  // Integer passt genau, Int64 nur der Familie nach: beide gleich gut, also beide.
  Assert.AreEqual(2, Integer(Length(ResolveAllAt(cSource, 'IntToStr(I)'))));
  Assert.IsTrue(ResolveAt(cSource, 'IntToStr(I)').Found);
end;

procedure TNameResolverLanguageFeatureTests.ParameterTypeAliasFitsItsBaseType;
const
  cSource = cHead + '  if FileAge(S, Alter) then'#10'    I := FileAge(S);' + cTail;
var
  mResults: TArray<TResolvedSymbol>;
begin
  // Das Argument Alter: TDateTime zählt als Double (Alias verfolgt), der Parameter TDateTime ebenso. Vorher passte
  // keine Überladung, und die erste (veraltete, ein Argument) stand vorn.
  mResults := ResolveAllAt(cSource, 'FileAge(S, Alter)');
  Assert.AreEqual(1, Integer(Length(mResults)));
  Assert.AreEqual(3, mResults[0].MaxArgs);
  mResults := ResolveAllAt(cSource, 'FileAge(S);');
  Assert.AreEqual(1, Integer(Length(mResults)));
  Assert.AreEqual(1, mResults[0].MaxArgs);
  mResults := nil;
end;

procedure TNameResolverLanguageFeatureTests.SubstitutesGenericTypeArguments;
const
  cSource = cHead + '  S := L.First.Name;'#10'  S := L.Items[0].Name;'#10'  S := L[0].Name;'#10 +
    '  S := L.First.Unbekannt;' + cTail;
var
  R: TResolvedSymbol;
begin
  R := ResolveAt(cSource, 'Name;');
  Assert.AreEqual('TKunde', R.Container);
  Assert.AreEqual('Kunden', R.UnitName);
  Assert.AreEqual('TKunde', ResolveAt(cSource, 'Name;', 2).Container);
  Assert.AreEqual('TKunde', ResolveAt(cSource, 'Name;', 3).Container);
  Assert.IsFalse(ResolveAt(cSource, 'Unbekannt').Found);
end;

procedure TNameResolverLanguageFeatureTests.NonGenericTypeBeatsGenericOfSameName;
const
  cUnitClasses = 'unit System.Classes;'#10'interface'#10'type'#10'  TList = class'#10'  public'#10 +
    '    function Extract(Item: Pointer): Pointer;'#10'  end;'#10'implementation'#10'end.';
  cBody = 'type'#10'  TBestand = class'#10'    Alt: TList;'#10'    Neu: TList<TKunde>;'#10'  end;'#10 +
    'implementation'#10'procedure P(B: TBestand);'#10'begin'#10'  B.Alt.Extract(nil);'#10'  B.Neu.First;'#10 +
    'end;'#10'end.';
var
  mUsesOrder: string;
  R: TResolvedSymbol;
begin
  // Wie im Compiler (#981): TList ohne Typargumente ist System.Classes.TList, auch wenn
  // System.Generics.Collections mit TList<T> weiter hinten in uses steht; TList<…> bleibt generisch.
  AddUnit('C:\Lib\System.Classes.pas', cUnitClasses);
  for mUsesOrder in ['System.Classes, System.Generics.Collections', 'System.Generics.Collections, System.Classes'] do
  begin
    R := ResolveAt('unit Haupt;'#10'interface'#10'uses ' + mUsesOrder + ', Kunden;'#10 + cBody, 'Extract');
    Assert.IsTrue(R.Found, mUsesOrder);
    Assert.AreEqual('System.Classes', R.UnitName, mUsesOrder);
    R := ResolveAt('unit Haupt;'#10'interface'#10'uses ' + mUsesOrder + ', Kunden;'#10 + cBody, 'First');
    Assert.AreEqual('System.Generics.Collections', R.UnitName, mUsesOrder);
  end;
end;

procedure TNameResolverLanguageFeatureTests.FollowsGenericAncestors;
const
  cSource = cHead + '  S := Liste.First.Name;'#10'  I := Liste.Count;'#10'  S := Liste.FCount;' + cTail;
begin
  Assert.AreEqual('TKunde', ResolveAt(cSource, 'Name;').Container);
  Assert.AreEqual('TList', ResolveAt(cSource, 'Count;').Container);
  // FCount ist private in einer anderen Unit.
  Assert.IsFalse(ResolveAt(cSource, 'FCount').Found);
end;

procedure TNameResolverLanguageFeatureTests.MissingMembersOfGenericInterfaces;
const
  cUnitListen =
    'unit Listen;'#10'interface'#10'type'#10 +
    '  IVergleich<T> = interface'#10'    function Compare(const Left, Right: T): Integer;'#10'  end;'#10 +
    '  IListe<T> = interface(IVergleich<T>)'#10'    procedure Add(const AItem: T);'#10'  end;'#10 +
    'implementation'#10'end.';
  cSource =
    'unit Haupt;'#10'interface'#10'uses Listen, Kunden;'#10'type'#10 +
    '  TMeineListe = class(TObject, IListe<TKunde>)'#10 +
    '    function Compare(const Left, Right: TKunde): Integer;'#10'  end;'#10 +
    'implementation'#10'end.';
var
  mTree: TSyntaxTree;
  mMissing: TArray<TResolvedSymbol>;
begin
  AddUnit('C:\P\Listen.pas', cUnitListen);
  mTree := TPascalParser.Parse(cSource);
  try
    // Ohne Typargumente aus dem Quelltext (Index kennt nur die des ersten Vorfahren) und mit ihnen.
    mMissing := FResolver.Queries.MissingInterfaceMembers(TIndexExtractor.Extract(mTree, 'C:\P\Haupt.pas'), 'TMeineListe',
      ['TObject', 'IListe<TKunde>']);
    Assert.AreEqual(1, Integer(Length(mMissing)));
    Assert.AreEqual('Add', mMissing[0].Name);
    Assert.AreEqual('IListe', mMissing[0].Container);
    Assert.AreEqual(1, Integer(Length(mMissing[0].Bindings)));
    Assert.AreEqual('T=TKunde', mMissing[0].Bindings[0]);
  finally
    mTree.Free;
  end;
  Assert.AreEqual('TKunde', FResolver.Queries.UnqualifyType('Kunden.TKunde'));
  Assert.AreEqual('TList<TKunde>', FResolver.Queries.UnqualifyType('System.Generics.Collections.TList<Kunden.TKunde>'));
  Assert.AreEqual('TOuter.TInner', FResolver.Queries.UnqualifyType('TOuter.TInner'));
  Assert.AreEqual('TKunde', FResolver.Queries.UnqualifyType('Haupt.TKunde', 'Haupt'));
end;

procedure TNameResolverLanguageFeatureTests.BindsGenericMethodArguments;
const
  cSource = cHead + '  S := L.Map<TKunde>(K).Name;'#10'  S := L.Map<Integer>(1).Name;' + cTail;
begin
  Assert.AreEqual('TKunde', ResolveAt(cSource, 'Name;').Container);
  Assert.IsFalse(ResolveAt(cSource, 'Name;', 2).Found);
end;

procedure TNameResolverLanguageFeatureTests.UsesHelpersForBuiltinAndClassTypes;
const
  cSource = cHead + '  S.Split(['','']);'#10'  S := K.Anrede;'#10'  I.Split(['','']);' + cTail;
var
  R: TResolvedSymbol;
begin
  R := ResolveAt(cSource, 'Split');
  Assert.AreEqual('TStringHelper', R.Container);
  Assert.AreEqual('System.SysUtils', R.UnitName);
  Assert.AreEqual('TKundeHelper', ResolveAt(cSource, 'Anrede').Container);
  Assert.IsFalse(ResolveAt(cSource, 'Split', 2).Found);
end;

procedure TNameResolverLanguageFeatureTests.VisibleHelperForTypeName;
const
  cSource = cHead + '  S := '''';' + cTail;
var
  mTree: TSyntaxTree;
  mOffset: Integer;
  mHelper: TResolvedSymbol;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mOffset := Pos('S := ''''', cSource) - 1;
    Assert.IsTrue(FResolver.VisibleHelper(mTree, 'C:\P\Haupt.pas', 'string', mOffset, mHelper));
    Assert.AreEqual('TStringHelper', mHelper.Name);
    Assert.AreEqual('System.SysUtils', mHelper.UnitName);
    Assert.IsTrue(FResolver.VisibleHelper(mTree, 'C:\P\Haupt.pas', 'TKunde', mOffset, mHelper));
    Assert.AreEqual('TKundeHelper', mHelper.Name);
    Assert.IsFalse(FResolver.VisibleHelper(mTree, 'C:\P\Haupt.pas', 'Integer', mOffset, mHelper));
    Assert.IsFalse(FResolver.VisibleHelper(mTree, 'C:\P\Haupt.pas', '', mOffset, mHelper));
  finally
    mTree.Free;
  end;
end;

procedure TNameResolverLanguageFeatureTests.WithFindsMembersOfExpression;
const
  cSource = cHead + '  with L.First do'#10'    S := Kopie.Name;'#10'  with K do'#10'    Name := '''';' + cTail;
begin
  Assert.AreEqual('TKunde', ResolveAt(cSource, 'Kopie').Container);
  // Mitglied verdeckt die lokale Variable Name: Integer.
  Assert.AreEqual('TKunde', ResolveAt(cSource, 'Name :=').Container);
end;

procedure TNameResolverLanguageFeatureTests.WithUnknownTypeGivesNoResult;
const
  cSource = cHead + '  with Unbekannt do'#10'    Name := 1;'#10'  Name := 2;' + cTail;
var
  R: TResolvedSymbol;
begin
  Assert.IsFalse(ResolveAt(cSource, 'Name := 1').Found);
  // Außerhalb des with wieder die lokale Variable.
  R := ResolveAt(cSource, 'Name := 2');
  Assert.AreEqual<TResolvedKind>(TResolvedKind.Local, R.Kind);
end;

procedure TNameResolverLanguageFeatureTests.InfersInlineVarTypes;
const
  cSource = cHead + '  var Neu := TKunde.Create;'#10'  S := Neu.Name;'#10 +
    '  var W := if True then ''a'' else ''b'';'#10'  S := W.ToUpper;'#10 +
    '  var Zahl := 5;'#10'  Zahl.ToUpper;' + cTail;
begin
  Assert.AreEqual('TKunde', ResolveAt(cSource, 'Name;').Container);
  Assert.AreEqual('TStringHelper', ResolveAt(cSource, 'ToUpper').Container);
  Assert.IsFalse(ResolveAt(cSource, 'ToUpper', 2).Found);
end;

procedure TNameResolverLanguageFeatureTests.ForVarIsLocalToLoop;
const
  cSource = cHead + '  for var Lauf := 0 to 3 do'#10'    I := Lauf;'#10'  I := Lauf;' + cTail;
var
  R: TResolvedSymbol;
begin
  R := ResolveAt(cSource, 'Lauf;');
  Assert.AreEqual<TResolvedKind>(TResolvedKind.Local, R.Kind);
  Assert.IsFalse(ResolveAt(cSource, 'Lauf;', 2).Found);
end;

procedure TNameResolverLanguageFeatureTests.HidesMembersByVisibility;
const
  cSource = cHead + '  I := K.FIntern;'#10'  I := K.FGeheim;'#10'  K.Schuetzt;'#10'  S := K.Name;' + cTail;
var
  R: TResolvedSymbol;
begin
  Assert.IsFalse(ResolveAt(cSource, 'FIntern').Found);
  Assert.IsFalse(ResolveAt(cSource, 'FGeheim').Found);
  Assert.IsFalse(ResolveAt(cSource, 'Schuetzt;', 2).Found);
  Assert.IsTrue(ResolveAt(cSource, 'Name;').Found);
  // protected im Nachfahren sichtbar.
  R := ResolveAt(cSource, 'Schuetzt;');
  Assert.AreEqual('TKunde', R.Container);
end;

procedure TNameResolverLanguageFeatureTests.ResolvesExpressionReceivers;
const
  cSource = cHead + '  S := Liefere(1).Name;'#10'  S := (O as TKunde).Name;'#10'  S := L.First.Kopie.Name;'#10 +
    '  S := (O as Unbekannt).Name;' + cTail;
begin
  Assert.AreEqual('TKunde', ResolveAt(cSource, 'Name;').Container);
  Assert.AreEqual('TKunde', ResolveAt(cSource, 'Name;', 2).Container);
  Assert.AreEqual('TKunde', ResolveAt(cSource, 'Name;', 3).Container);
  Assert.IsFalse(ResolveAt(cSource, 'Name;', 4).Found);
end;

procedure TNameResolverLanguageFeatureTests.IndexKeepsSignaturesAndGenerics;
var
  mUnits: TArray<TUnitIndex>;
  mSymbol: TIndexSymbol;
  mChecked: Integer;
begin
  mUnits := TIndexCache.Deserialize(TIndexCache.Serialize([TIndexExtractor.ExtractText(cUnitCollections,
    'C:\Lib\System.Generics.Collections.pas', nil), TIndexExtractor.ExtractText(cUnitKunden, 'C:\P\Kunden.pas', nil)]));
  Assert.AreEqual(2, Integer(Length(mUnits)));
  mChecked := 0;
  for mSymbol in mUnits[0].Symbols do
  begin
    if mSymbol.Name = 'TList' then
    begin
      Assert.AreEqual('T', mSymbol.TypeParams);
      Inc(mChecked);
    end
    else if mSymbol.Name = 'Items' then
    begin
      Assert.IsTrue(mSymbol.IsDefault);
      Assert.AreEqual(1, mSymbol.MaxArgs);
      Inc(mChecked);
    end
    else if mSymbol.Name = 'FCount' then
    begin
      Assert.AreEqual(Ord(TIndexVisibility.Private), Ord(mSymbol.Visibility));
      Inc(mChecked);
    end;
  end;
  for mSymbol in mUnits[1].Symbols do
  begin
    if mSymbol.Name = 'TKundenListe' then
    begin
      Assert.AreEqual('TObjectList', mSymbol.Ancestors[0]);
      Assert.AreEqual(1, Integer(Length(mSymbol.AncestorArgs)));
      Assert.AreEqual('TKunde', mSymbol.AncestorArgs[0]);
      Inc(mChecked);
    end;
  end;
  Assert.AreEqual(4, mChecked);
end;

initialization
  TDUnitX.RegisterTestFixture(TNameResolverLanguageFeatureTests);

end.
