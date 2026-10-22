unit Atlas.Common.Rules.Builtin.Generics.Tests;

// Tests für generic-constraint-violated (#1028): Beispiel aus dem Issue mit
// Korrektur, Typargumente gegen class, record, constructor, Interface und
// Basisklasse, Methoden auf unbeschränktem T, stille Fälle, Index, Abschalten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TGenericConstraintViolatedTests = class
  public
    [Test]
    procedure IssueExampleWithFix;
    [Test]
    procedure ArgumentsAgainstConstraints;
    [Test]
    procedure MethodOnUnconstrainedValue;
    [Test]
    procedure SilentCases;
    [Test]
    procedure GenericFromIndex;
    [Test]
    procedure ParseParams;
    [Test]
    procedure OffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Builtin.Generics,
  Atlas.Tests.RuleAssert;

function Findings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TGenericConstraintViolatedRule.Create, ASource);
end;

function Findings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TGenericConstraintViolatedRule.Create, ASource, AConfig, APath);
end;

/// <summary>Offset (ab 1) der Position APosition in AText mit #10 als Zeilenende.</summary>
function OffsetOf(const AText: string; const APosition: TTextPosition): Integer;
var
  Line: Integer;
begin
  Result := 1;
  for Line := 1 to APosition.Line do
    Result := Pos(#10, AText, Result) + 1;
  Inc(Result, APosition.Character);
end;

function ApplyFix(const AText: string; const AFix: TRuleFix): string;
var
  Edit: TRuleEdit;
begin
  Edit := AFix.Edits[0];
  Result := Copy(AText, 1, OffsetOf(AText, Edit.Range.StartPos) - 1) + Edit.NewText +
    Copy(AText, OffsetOf(AText, Edit.Range.EndPos), MaxInt);
end;

/// <summary>TFabrik mit Einschränkung AConstraint ('' ohne), Neu legt ein T an.</summary>
function Fabrik(const AConstraint: string): string;
begin
  Result := 'unit Fabriken;'#10'interface'#10'type'#10'  TFabrik<T' + AConstraint + '> = class'#10 +
    '    function Neu: T;'#10'  end;'#10'implementation'#10'function TFabrik<T>.Neu: T;'#10'begin'#10 +
    '  Result := T.Create;'#10'end;'#10'end.';
end;

procedure TGenericConstraintViolatedTests.IssueExampleWithFix;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Fabrik(': class');
  Found := Findings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('T hat keine constructor-Einschränkung; T.Create ist nicht erlaubt (wie E2568).',
    Found[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Found[0].Severity));
  Assert.AreEqual(9, Found[0].Range.StartPos.Line);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('Einschränkung ergänzen', Found[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Found[0].Fixes[0]);
  Assert.AreEqual(Fabrik(': class, constructor'), Fixed);
  Assert.AreEqual(0, Integer(Length(Findings(Fixed))), Fixed);
  // Ohne jede Einschränkung: class und constructor ergänzen.
  Found := Findings(Fabrik(''));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(Fabrik(': class, constructor'), ApplyFix(Fabrik(''), Found[0].Fixes[0]));
end;

procedure TGenericConstraintViolatedTests.ArgumentsAgainstConstraints;
const
  Source = 'unit Zoo;'#10'interface'#10'type'#10 +
    '  IVergleich = interface'#10'    function Vergleiche: Integer;'#10'  end;'#10 +
    '  TBasisObjekt = class'#10'  end;'#10 +
    '  TVergleicher = class(TBasisObjekt, IVergleich)'#10'    function Vergleiche: Integer;'#10'  end;'#10 +
    '  TTier = class'#10'  end;'#10'  THund = class(TTier)'#10'  end;'#10'  TAuto = class'#10'  end;'#10 +
    '  TPunkt = record'#10'    X: Integer;'#10'  end;'#10 +
    '  TListe<T: class> = class'#10'  end;'#10'  TPuffer<T: record> = class'#10'  end;'#10 +
    '  TErzeuger<T: constructor> = class'#10'  end;'#10'  TSortierer<T: IVergleich> = class'#10'  end;'#10 +
    '  TZoo<T: TTier> = class'#10'  end;'#10 +
    'var'#10 +
    '  A: TListe<Integer>;'#10 +
    '  B: TPuffer<TAuto>;'#10 +
    '  C: TErzeuger<TPunkt>;'#10 +
    '  D: TSortierer<TAuto>;'#10 +
    '  E: TZoo<TAuto>;'#10 +
    '  F: TListe<THund>;'#10 +
    '  G: TPuffer<TPunkt>;'#10 +
    '  H: TSortierer<TVergleicher>;'#10 +
    '  I: TZoo<THund>;'#10 +
    '  J: TPuffer<string>;'#10 +
    'implementation'#10'function TVergleicher.Vergleiche: Integer;'#10'begin'#10'  Result := 0;'#10'end;'#10 +
    'procedure P;'#10'begin'#10'  TListe<TPunkt>.Create.Free;'#10'end;'#10'end.';
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(Source);
  Assert.AreEqual(7, Integer(Length(Found)));
  Assert.AreEqual('Integer ist kein Klassentyp; T von TListe verlangt class (wie E2511).', Found[0].Message);
  Assert.AreEqual(31, Found[0].Range.StartPos.Line);
  Assert.AreEqual(12, Found[0].Range.StartPos.Character);
  Assert.AreEqual('TAuto ist kein Werttyp; T von TPuffer verlangt record (wie E2512).', Found[1].Message);
  Assert.AreEqual('TPunkt hat keinen parameterlosen Konstruktor; T von TErzeuger verlangt constructor (wie E2513).',
    Found[2].Message);
  Assert.AreEqual('TAuto unterstützt IVergleich nicht; T von TSortierer verlangt IVergleich (wie E2514).',
    Found[3].Message);
  Assert.AreEqual('TAuto ist nicht mit TTier kompatibel; T von TZoo verlangt TTier (wie E2515).', Found[4].Message);
  Assert.AreEqual('string ist kein Werttyp; T von TPuffer verlangt record (wie E2512).', Found[5].Message);
  Assert.AreEqual('TPunkt ist kein Klassentyp; T von TListe verlangt class (wie E2511).', Found[6].Message);
  Assert.AreEqual(0, Integer(Length(Found[6].Fixes)));
end;

procedure TGenericConstraintViolatedTests.MethodOnUnconstrainedValue;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := 'unit Boxen;'#10'interface'#10'type'#10'  TBox<T> = class'#10'    procedure Zeige(V: T);'#10 +
    '  end;'#10'implementation'#10'procedure TBox<T>.Zeige(V: T);'#10'begin'#10'  V.Free;'#10'end;'#10'end.';
  Found := Findings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('T hat keine class- oder Interface-Einschränkung; V.Free ist nicht erlaubt (wie E2571).',
    Found[0].Message);
  Fixed := ApplyFix(Source, Found[0].Fixes[0]);
  Assert.IsTrue(Pos('TBox<T: class> = class', Fixed) > 0, Fixed);
  Assert.AreEqual(0, Integer(Length(Findings(Fixed))), Fixed);
  // Mehrere Namen in einer Gruppe: gemeldet, aber ohne Korrektur.
  Found := Findings(StringReplace(Source, 'TBox<T>', 'TBox<K, T>', [rfReplaceAll]));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
end;

procedure TGenericConstraintViolatedTests.SilentCases;
begin
  // Konstruktor-Einschränkung, Typparameter als Argument, unbekannte Typen, Methode mit Interface-Einschränkung.
  TRuleAssert.Silent(TGenericConstraintViolatedRule.Create, Fabrik(': constructor'));
  TRuleAssert.Silent(TGenericConstraintViolatedRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  IZeigbar = interface'#10'    procedure Zeige;'#10'  end;'#10 +
    '  TListe<T: class> = class'#10'  end;'#10'  THuelle<T: class> = class'#10'    FListe: TListe<T>;'#10 +
    '    FAndere: TListe<TUnbekannt>;'#10'  end;'#10'  TAnzeige<T: IZeigbar> = class'#10 +
    '    procedure Lauf(V: T);'#10'  end;'#10'implementation'#10'procedure TAnzeige<T>.Lauf(V: T);'#10'begin'#10 +
    '  V.Zeige;'#10'end;'#10'end.');
  // Basisklasse als Einschränkung: T.Create bleibt unbewertet.
  TRuleAssert.Silent(TGenericConstraintViolatedRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TTier = class'#10'  end;'#10'  TZoo<T: TTier> = class'#10'    function Neu: T;'#10'  end;'#10 +
    'implementation'#10'function TZoo<T>.Neu: T;'#10'begin'#10'  Result := T.Create;'#10'end;'#10'end.');
end;

procedure TGenericConstraintViolatedTests.GenericFromIndex;
var
  Index: ISymbolIndex;
  Found: TArray<TRuleFinding>;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText('unit Listen;'#10'interface'#10'type'#10 +
    '  TObjektListe<T: class> = class'#10'  end;'#10'implementation'#10'end.', 'C:\Quellen\Listen.pas', nil));
  Found := TRuleAssert.IndexFindings(TGenericConstraintViolatedRule.Create, 'unit U;'#10'interface'#10 +
    'uses Listen;'#10'type'#10'  TKunden = class(TObjektListe<Double>)'#10'  end;'#10'implementation'#10'end.',
    Index, '', 'U.pas');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Double ist kein Klassentyp; T von TObjektListe verlangt class (wie E2511).', Found[0].Message);
end;

procedure TGenericConstraintViolatedTests.ParseParams;
var
  Params: TArray<TGenericParam>;
begin
  Params := TGenericConstraintViolatedRule.ParseParams('TMap<K, V: class, constructor; C: IComparer<K, V>> = class');
  Assert.AreEqual(3, Integer(Length(Params)));
  Assert.AreEqual('K', Params[0].Name);
  Assert.IsFalse(Params[0].Single);
  Assert.IsTrue(Params[1].Has('class'));
  Assert.IsTrue(Params[1].Has('constructor'));
  Assert.AreEqual('C', Params[2].Name);
  Assert.IsTrue(Params[2].Single);
  Assert.AreEqual(1, Integer(Length(Params[2].TypeConstraints)));
  Assert.AreEqual('IComparer<K, V>', Params[2].TypeConstraints[0]);
  Assert.AreEqual(0, Integer(Length(TGenericConstraintViolatedRule.ParseParams('TKunde = class'))));
end;

procedure TGenericConstraintViolatedTests.OffAndExclude;
var
  Source: string;
begin
  Source := Fabrik(': class');
  Assert.AreEqual(1, Integer(Length(Findings(Source, '', 'Source/Fabriken.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"generic-constraint-violated": "off"}}',
    'Source/Fabriken.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"group:compiler": "off"}}',
    'Source/Fabriken.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source,
    '{"rules": {"generic-constraint-violated": {"exclude": ["Source/*.pas"]}}}', 'Source/Fabriken.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TGenericConstraintViolatedTests);

end.
