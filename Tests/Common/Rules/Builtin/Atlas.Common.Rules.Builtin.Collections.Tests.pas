unit Atlas.Common.Rules.Builtin.Collections.Tests;

// Tests der Regel legacy-tlist (#981): Beispiel aus dem Issue, Lesezugriffe
// über Items, First, Last, Extract und as, TObjectList aus Contnrs, lokale
// Variable und Parameter, mehrere Zieltypen, Deklaration in einer anderen
// Unit, stille Fälle (generische Liste, ohne Cast, Pointer, eigene Klasse
// TList, unbekannte Typen) und Einstellungen (Standard aus, off, exclude).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLegacyTListTests = class
  public
    [Test]
    procedure IssueExample;
    [Test]
    procedure ReadForms;
    [Test]
    procedure ObjectListLocalsAndParameters;
    [Test]
    procedure SeveralCastTypes;
    [Test]
    procedure DeclaredInOtherUnit;
    [Test]
    procedure SilentCases;
    [Test]
    procedure Settings;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Collections,
  Atlas.Tests.RuleAssert;

const
  RuleOn = '{"rules": {"legacy-tlist": "info"}}';

function RtlIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText('unit System;'#10'interface'#10'type'#10'  TObject = class'#10 +
    '  end;'#10'implementation'#10'end.', 'C:\BDS\source\System.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText('unit System.Classes;'#10'interface'#10'type'#10 +
    '  TList = class(TObject)'#10'  protected'#10'    function Get(Index: Integer): Pointer;'#10 +
    '  public'#10'    function Add(Item: Pointer): Integer;'#10'    function First: Pointer;'#10 +
    '    function Last: Pointer;'#10'    function Extract(Item: Pointer): Pointer;'#10 +
    '    property Count: Integer read FCount;'#10 +
    '    property Items[Index: Integer]: Pointer read Get; default;'#10'  end;'#10 +
    '  TStrings = class(TObject)'#10'  public'#10 +
    '    property Objects[Index: Integer]: TObject read GetObject;'#10'  end;'#10 +
    'implementation'#10'end.', 'C:\BDS\source\System.Classes.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText('unit System.Contnrs;'#10'interface'#10'uses'#10'  System.Classes;'#10 +
    'type'#10'  TObjectList = class(TList)'#10'  protected'#10'    function GetItem(Index: Integer): TObject;'#10 +
    '  public'#10'    function First: TObject;'#10'    function Last: TObject;'#10 +
    '    property Items[Index: Integer]: TObject read GetItem; default;'#10'  end;'#10 +
    'implementation'#10'end.', 'C:\BDS\source\System.Contnrs.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText('unit System.Generics.Collections;'#10'interface'#10'type'#10 +
    '  TList<T> = class(TObject)'#10'  protected'#10'    function GetItem(Index: Integer): T;'#10'  public'#10 +
    '    function First: T;'#10'    property Items[Index: Integer]: T read GetItem; default;'#10'  end;'#10 +
    '  TObjectList<T: class> = class(TList<T>)'#10'  end;'#10 +
    'implementation'#10'end.', 'C:\BDS\source\System.Generics.Collections.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText('unit Lager;'#10'interface'#10'uses'#10'  System.Classes;'#10 +
    'type'#10'  TLager = class'#10'  public'#10'    Regale: TList;'#10'  end;'#10'implementation'#10'end.',
    'C:\Projekt\Lager.pas', nil));
end;

function Findings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TLegacyTListRule.Create, ASource, RtlIndex, RuleOn, 'Auftraege.pas');
end;

function Findings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TLegacyTListRule.Create, ASource, RtlIndex, AConfig, APath);
end;

/// <summary>Unit mit TPosition und TAuftrag (Feld FPositionen vom Typ AListType); AStatements in TAuftrag.Summe.
/// </summary>
function Auftrag(const AUses, AListType, AStatements: string): string;
begin
  Result := 'unit Auftraege;'#10'interface'#10'uses'#10'  ' + AUses + ';'#10'type'#10'  TPosition = class'#10 +
    '  end;'#10'  TAuftrag = class'#10'  private'#10'    FPositionen: ' + AListType + ';'#10'  public'#10 +
    '    procedure Summe;'#10'  end;'#10'implementation'#10'procedure TAuftrag.Summe;'#10'var'#10 +
    '  I: Integer;'#10'  Pos: TPosition;'#10'  Obj: TObject;'#10'begin'#10 + AStatements + 'end;'#10'end.';
end;

procedure TLegacyTListTests.IssueExample;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(Auftrag('System.Classes', 'TList', '  Pos := TPosition(FPositionen[I]);'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Ungenerische TList mit Cast beim Lesen; TList<TPosition> prüft den Typ beim Übersetzen.',
    Found[0].Message);
  // An der Deklaration des Felds.
  Assert.AreEqual(9, Found[0].Range.StartPos.Line);
  Assert.AreEqual(4, Found[0].Range.StartPos.Character);
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
  // Mit System.Generics.Collections hinter System.Classes bleibt TList die ungenerische Klasse.
  Assert.AreEqual(1, Integer(Length(Findings(Auftrag('System.Classes, System.Generics.Collections', 'TList',
    '  Pos := TPosition(FPositionen[I]);'#10)))));
  // Die korrigierte Form ist still.
  Assert.AreEqual(0, Integer(Length(Findings(Auftrag('System.Classes, System.Generics.Collections',
    'TList<TPosition>', '  Pos := FPositionen[I];'#10)))));
end;

procedure TLegacyTListTests.ReadForms;
var
  Statement: string;
  Found: TArray<TRuleFinding>;
  Index: ISymbolIndex;
begin
  for Statement in ['  Pos := TPosition(FPositionen.Items[I]);'#10, '  Pos := TPosition(FPositionen.First);'#10,
    '  Pos := TPosition(FPositionen.Last());'#10, '  Pos := TPosition(Self.FPositionen[I]);'#10,
    '  Pos := FPositionen[I] as TPosition;'#10, '  Pos := (FPositionen[I]) as TPosition;'#10,
    '  if TPosition(FPositionen[0]) = nil then'#10'    Exit;'#10,
    '  Pos := TPosition(FPositionen.Extract(Pos));'#10] do
  begin
    Found := Findings(Auftrag('System.Classes', 'TList', Statement));
    Assert.AreEqual(1, Integer(Length(Found)), Statement);
    Assert.AreEqual(9, Found[0].Range.StartPos.Line, Statement);
  end;
  // Mehrere Casts derselben Liste: ein Treffer.
  Found := Findings(Auftrag('System.Classes', 'TList', '  Pos := TPosition(FPositionen[0]);'#10 +
    '  Pos := TPosition(FPositionen.Last);'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  // RTL-Quellen ohne Namespace (Classes statt System.Classes).
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText('unit Classes;'#10'interface'#10'type'#10'  TList = class'#10 +
    '  public'#10'    function Get(Index: Integer): Pointer;'#10 +
    '    property Items[Index: Integer]: Pointer read Get; default;'#10'  end;'#10'implementation'#10'end.',
    'C:\Alt\Classes.pas', nil));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.IndexFindings(TLegacyTListRule.Create,
    Auftrag('Classes', 'TList', '  Pos := TPosition(FPositionen[I]);'#10), Index, RuleOn, 'Auftraege.pas'))));
end;

procedure TLegacyTListTests.ObjectListLocalsAndParameters;
var
  Source: string;
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(Auftrag('System.Classes, System.Contnrs', 'TObjectList',
    '  Pos := TPosition(FPositionen[I]);'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Ungenerische TObjectList mit Cast beim Lesen; TObjectList<TPosition> prüft den Typ beim ' +
    'Übersetzen.', Found[0].Message);
  // Lokale Variable und Parameter: je Deklaration ein Treffer an ihrem Namen.
  Source := 'unit Auftraege;'#10'interface'#10'uses'#10'  System.Classes;'#10'type'#10'  TPosition = class'#10 +
    '  end;'#10'implementation'#10'procedure Lesen(Quelle: TList);'#10'var'#10'  Ziel: TList;'#10 +
    '  Pos: TPosition;'#10'begin'#10'  Pos := TPosition(Quelle[0]);'#10'  Pos := TPosition(Ziel.First);'#10 +
    'end;'#10'end.';
  Found := Findings(Source);
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual(8, Found[0].Range.StartPos.Line);
  Assert.AreEqual(16, Found[0].Range.StartPos.Character);
  Assert.AreEqual(10, Found[1].Range.StartPos.Line);
  Assert.AreEqual(2, Found[1].Range.StartPos.Character);
end;

procedure TLegacyTListTests.SeveralCastTypes;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(Auftrag('System.Classes', 'TList', '  Pos := TPosition(FPositionen[0]);'#10 +
    '  Obj := TObject(FPositionen[1]);'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Ungenerische TList mit Casts auf TPosition, TObject beim Lesen; eine generische Liste prüft den ' +
    'Typ beim Übersetzen.', Found[0].Message);
end;

procedure TLegacyTListTests.DeclaredInOtherUnit;
var
  Source: string;
  Found: TArray<TRuleFinding>;
begin
  // Das Feld steht in Lager: der Treffer sitzt am Cast dieser Datei.
  Source := 'unit Auftraege;'#10'interface'#10'uses'#10'  System.Classes, Lager;'#10'type'#10 +
    '  TPosition = class'#10'  end;'#10'implementation'#10'procedure Lesen(L: TLager);'#10'var'#10 +
    '  Pos: TPosition;'#10'begin'#10'  Pos := TPosition(L.Regale[0]);'#10'end;'#10'end.';
  Found := Findings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(12, Found[0].Range.StartPos.Line);
  Assert.AreEqual(9, Found[0].Range.StartPos.Character);
  Assert.AreEqual(12, Found[0].Range.EndPos.Line);
  Assert.AreEqual(31, Found[0].Range.EndPos.Character);
end;

procedure TLegacyTListTests.SilentCases;
var
  Statement: string;
begin
  for Statement in [
    // Ohne Cast, Pointer, Funktionsaufruf statt Cast, unbekannter Typ.
    '  I := FPositionen.Count;'#10'  FPositionen.Add(Pos);'#10, '  Obj := Pointer(FPositionen[I]);'#10,
    '  Pos := Umwandeln(FPositionen[I]);'#10, '  Pos := TUnbekannt(FPositionen[I]);'#10,
    // Cast auf etwas anderes als die Liste.
    '  Pos := TPosition(Obj);'#10] do
    Assert.AreEqual(0, Integer(Length(Findings(Auftrag('System.Classes', 'TList', Statement).Replace('begin'#10,
      'function Umwandeln(P: Pointer): TPosition;'#10'begin'#10'end;'#10#10'begin'#10)))), Statement);
  // Generische Liste mit überflüssigem Cast: nicht diese Regel.
  Assert.AreEqual(0, Integer(Length(Findings(Auftrag('System.Generics.Collections', 'TList<TObject>',
    '  Pos := TPosition(FPositionen[I]);'#10)))));
  // TStringList.Objects ist keine ungenerische Liste.
  Assert.AreEqual(0, Integer(Length(Findings(Auftrag('System.Classes', 'TStrings',
    '  Pos := TPosition(FPositionen.Objects[I]);'#10)))));
  // Eigene Klasse TList in der Unit.
  Assert.AreEqual(0, Integer(Length(Findings(Auftrag('System.Classes', 'TList',
    '  Pos := TPosition(FPositionen[I]);'#10).Replace('  TPosition = class'#10,
    '  TList = class'#10'    function Get(Index: Integer): TObject;'#10 +
    '    property Items[Index: Integer]: TObject read Get; default;'#10'  end;'#10'  TPosition = class'#10)))));
  // Ohne Index keine Aussage.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.IndexFindings(TLegacyTListRule.Create,
    Auftrag('System.Classes', 'TList', '  Pos := TPosition(FPositionen[I]);'#10), nil, RuleOn, 'Auftraege.pas'))));
end;

procedure TLegacyTListTests.Settings;
var
  Source: string;
begin
  Source := Auftrag('System.Classes', 'TList', '  Pos := TPosition(FPositionen[I]);'#10);
  // Standard aus.
  Assert.AreEqual(0, Integer(Length(Findings(Source, '', 'Source/Auftraege.pas'))));
  Assert.AreEqual(1, Integer(Length(Findings(Source, RuleOn, 'Source/Auftraege.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"legacy-tlist": "off"}}', 'Source/Auftraege.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source,
    '{"rules": {"legacy-tlist": {"severity": "info", "exclude": ["Source/*.pas"]}}}', 'Source/Auftraege.pas'))));
  Assert.AreEqual(1, Integer(Length(Findings(Source,
    '{"rules": {"legacy-tlist": {"severity": "info", "exclude": ["Alt/*.pas"]}}}', 'Source/Auftraege.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TLegacyTListTests);

end.
