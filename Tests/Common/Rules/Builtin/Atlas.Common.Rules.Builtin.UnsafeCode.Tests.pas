unit Atlas.Common.Rules.Builtin.UnsafeCode.Tests;

// Tests der Regel unsafe-code (#1378): @-Operator auf Parameter, Felder und
// Variablen (wie W1047) und Pointer nach Klasse (wie W1048), jeweils nur mit
// eingeschalteter Warnung ({$WARN UNSAFE_CODE ON}, Projektoption), ERROR als
// Fehler, OFF und {$WARNINGS OFF}; Gegenfälle, die dcc ohne Meldung übersetzt:
// ab Werk, @ auf Routinen, typisierte Zeiger, Ganzzahlen, Interfaces,
// Umwandlung als Argument; abschaltbar.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TUnsafeCodeTests = class
  public
    [Test]
    procedure AddressOperatorLikeDcc;
    [Test]
    procedure AddressSilentByDefault;
    [Test]
    procedure AddressOfFieldsAndLocals;
    [Test]
    procedure AddressOfRoutinesIsSilent;
    [Test]
    procedure SwitchesOffErrorAndWarnings;
    [Test]
    procedure ProjectOption;
    [Test]
    procedure PointerToClassLikeDcc;
    [Test]
    procedure PointerToTObjectFromIndex;
    [Test]
    procedure OtherCastsAreSilent;
    [Test]
    procedure CastSilentByDefault;
    [Test]
    procedure OffAndRegistered;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.UnsafeCode,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Tests.RuleAssert;

const
  cKunde = 'type'#10'  TKunde = class'#10'  end;'#10'  IKunde = interface'#10'  end;'#10;

/// <summary>Unit mit Kopfzeile AHead (Schalter), den Typen aus cKunde und der Funktion Lauf mit Deklarationen
/// ADecls und Anweisungen ABody.</summary>
function Source(const AHead, ADecls, ABody: string): string;
begin
  Result := AHead + 'unit Fall;'#10'interface'#10'implementation'#10 + cKunde +
    'function Lauf(var AWert: Integer; AZeiger: Pointer): TKunde;'#10'var'#10 + ADecls + 'begin'#10 + ABody +
    'end;'#10'end.';
end;

function Findings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TUnsafeCodeRule.Create, ASource, '', 'Fall.pas');
end;

function Findings(const ASource: string; const AProjectWarnings: TArray<string>): TArray<TRuleFinding>; overload;
var
  mContext: TRuleContext;
begin
  mContext := Default(TRuleContext);
  mContext.RelativePath := 'Fall.pas';
  mContext.UnitName := 'Fall';
  mContext.Text := ASource;
  mContext.ProjectWarnings := AProjectWarnings;
  Result := TRuleAssert.ContextFindings(TUnsafeCodeRule.Create, mContext, '');
end;

function Messages(const AFindings: TArray<TRuleFinding>): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in AFindings do
    Result := Result + Format('%d:%d %s|', [mFinding.Range.StartPos.Line, mFinding.Range.StartPos.Character,
      mFinding.Message]);
end;

{ TUnsafeCodeTests }

procedure TUnsafeCodeTests.AddressOperatorLikeDcc;
var
  mFound: TArray<TRuleFinding>;
begin
  // Fall Cm.W1047 aus Tests/Compilermeldungen: dcc meldet „Unsicherer Code '@-Operator'“.
  mFound := Findings(Source('{$WARN UNSAFE_CODE ON}'#10, '  P: Pointer;'#10, '  P := @AWert;'#10));
  Assert.AreEqual('13:7 @AWert: Der @-Operator ist unsicherer Code (wie W1047).|', Messages(mFound));
  Assert.AreEqual(UnsafeCodeRuleId, mFound[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFound[0].Severity));
  Assert.AreEqual(13, mFound[0].Range.EndPos.Character);
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
end;

procedure TUnsafeCodeTests.AddressSilentByDefault;
begin
  // dcc schaltet UNSAFE_CODE ab Werk ab.
  Assert.AreEqual('', Messages(Findings(Source('', '  P: Pointer;'#10, '  P := @AWert;'#10))));
  Assert.AreEqual('', Messages(Findings(Source('{$WARN UNSAFE_CODE DEFAULT}'#10, '  P: Pointer;'#10,
    '  P := @AWert;'#10))));
end;

procedure TUnsafeCodeTests.AddressOfFieldsAndLocals;
const
  cSource =
    '{$WARN UNSAFE_CODE ON}'#10 +
    'unit Fall;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TZaehler = class'#10 +
    '  private'#10 +
    '    FWert: Integer;'#10 +
    '    function Adresse: Pointer;'#10 +
    '  end;'#10 +
    'var'#10 +
    '  GWert: Integer;'#10 +
    'implementation'#10 +
    'function TZaehler.Adresse: Pointer;'#10 +
    'var'#10 +
    '  mZahl: Integer;'#10 +
    'begin'#10 +
    '  Result := @FWert;'#10 +
    '  Result := @mZahl;'#10 +
    '  Result := @GWert;'#10 +
    '  Result := (@mZahl);'#10 +
    'end;'#10 +
    'end.';
begin
  Assert.AreEqual('16:12 @FWert: Der @-Operator ist unsicherer Code (wie W1047).|' +
    '17:12 @mZahl: Der @-Operator ist unsicherer Code (wie W1047).|' +
    '18:12 @GWert: Der @-Operator ist unsicherer Code (wie W1047).|' +
    '19:13 @mZahl: Der @-Operator ist unsicherer Code (wie W1047).|', Messages(Findings(cSource)));
end;

procedure TUnsafeCodeTests.AddressOfRoutinesIsSilent;
const
  cSource =
    '{$WARN UNSAFE_CODE ON}'#10 +
    'unit Fall;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'type'#10 +
    '  TArbeit = class'#10 +
    '    procedure Machen;'#10 +
    '  end;'#10 +
    'procedure Lauf;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TArbeit.Machen;'#10 +
    'var'#10 +
    '  P: Pointer;'#10 +
    '  U: Pointer;'#10 +
    'begin'#10 +
    '  P := @Lauf;'#10 +
    '  P := @TArbeit.Machen;'#10 +
    '  P := @Unbekannt;'#10 +
    '  P := @U;'#10 +
    'end;'#10 +
    'end.';
begin
  // Routinen, Methoden und Unbekanntes bleiben still; nur @U ist eine Variable.
  Assert.AreEqual('19:7 @U: Der @-Operator ist unsicherer Code (wie W1047).|', Messages(Findings(cSource)));
end;

procedure TUnsafeCodeTests.SwitchesOffErrorAndWarnings;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(Source('{$WARN UNSAFE_CODE ON}'#10, '  P: Pointer;'#10,
    '  {$WARN UNSAFE_CODE OFF}'#10 +
    '  P := @AWert;'#10 +
    '  {$WARN UNSAFE_CODE ERROR}'#10 +
    '  P := @AWert;'#10 +
    '  {$WARNINGS OFF}'#10 +
    '  P := @AWert;'#10 +
    '  {$WARNINGS ON}'#10 +
    '  {$WARN UNSAFE_CODE DEFAULT}'#10 +
    '  P := @AWert;'#10));
  Assert.AreEqual('16:7 @AWert: Der @-Operator ist unsicherer Code (wie W1047).|', Messages(mFound));
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(mFound[0].Severity));
  // Schalter in einem Zweig, der nicht sicher mit übersetzt wird: still.
  Assert.AreEqual('', Messages(Findings(Source('{$IFDEF DEBUG}{$WARN UNSAFE_CODE ON}{$ENDIF}'#10, '  P: Pointer;'#10,
    '  P := @AWert;'#10))));
end;

procedure TUnsafeCodeTests.ProjectOption;
var
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Source('', '  P: Pointer;'#10, '  P := @AWert;'#10);
  Assert.AreEqual('12:7 @AWert: Der @-Operator ist unsicherer Code (wie W1047).|',
    Messages(Findings(mSource, ['UNSAFE_CODE=true'])));
  mFound := Findings(mSource, ['UNSAFE_CODE=error']);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(mFound[0].Severity));
  Assert.AreEqual('', Messages(Findings(mSource, ['UNSAFE_CODE=false'])));
  Assert.AreEqual('', Messages(Findings(mSource, ['UNSAFE_CODE=true', 'WARNINGS=false'])));
  // Die Datei schaltet ab, was das Projekt einschaltet.
  Assert.AreEqual('', Messages(Findings(Source('{$WARN UNSAFE_CODE OFF}'#10, '  P: Pointer;'#10, '  P := @AWert;'#10),
    ['UNSAFE_CODE=true'])));
end;

procedure TUnsafeCodeTests.PointerToClassLikeDcc;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(Source('{$WARN UNSAFE_CAST ON}'#10, '  Q: Pointer;'#10,
    '  Q := AZeiger;'#10'  Result := TKunde(AZeiger);'#10'  Result := TKunde((Q));'#10));
  Assert.AreEqual('14:12 Umwandlung von Pointer nach TKunde ist unsicher (wie W1048).|' +
    '15:12 Umwandlung von Pointer nach TKunde ist unsicher (wie W1048).|', Messages(mFound));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFound[0].Severity));
  // UNSAFE_CODE schaltet die Umwandlungen nicht ein.
  Assert.AreEqual('', Messages(Findings(Source('{$WARN UNSAFE_CODE ON}'#10, '', '  Result := TKunde(AZeiger);'#10))));
  Assert.AreEqual(1, Integer(Length(Findings(Source('', '', '  Result := TKunde(AZeiger);'#10),
    ['UNSAFE_CAST=true']))));
end;

procedure TUnsafeCodeTests.PointerToTObjectFromIndex;
var
  mIndex: ISymbolIndex;
  mSource: string;
begin
  // Fall Cm.W1048: „Unsichere Typumwandlung von 'Pointer' nach 'TObject'“.
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit System;'#10'interface'#10'type'#10'  TObject = class'#10 +
    '  end;'#10'implementation'#10'end.', 'C:\BDS\source\System.pas', nil));
  mSource := '{$WARN UNSAFE_CAST ON}'#10'unit Fall;'#10'interface'#10'implementation'#10 +
    'function Umwandeln(AZeiger: Pointer): TObject;'#10'begin'#10'  Result := TObject(AZeiger);'#10'end;'#10'end.';
  Assert.AreEqual('6:12 Umwandlung von Pointer nach TObject ist unsicher (wie W1048).|',
    Messages(TRuleAssert.IndexFindings(TUnsafeCodeRule.Create, mSource, mIndex, '', 'Fall.pas')));
  // Ohne System im Index (Linter ohne RTL) bleibt TObject die Klasse aus System, ein eigener Typ nicht.
  Assert.AreEqual('6:12 Umwandlung von Pointer nach TObject ist unsicher (wie W1048).|', Messages(Findings(mSource)));
  Assert.AreEqual('', Messages(Findings(ReplaceStr(mSource, 'implementation'#10,
    'implementation'#10'type'#10'  TObject = record'#10'  end;'#10))));
end;

procedure TUnsafeCodeTests.OtherCastsAreSilent;
begin
  // Typisierte Zeiger, Ganzzahlen, Interfaces, Umwandlung als Argument und unbekannte Typen.
  Assert.AreEqual('', Messages(Findings(Source('{$WARN UNSAFE_CAST ON}'#10,
    '  PI: PInteger;'#10'  N: NativeInt;'#10'  K: IKunde;'#10,
    '  PI := nil;'#10'  N := 0;'#10'  K := nil;'#10 +
    '  Result := TKunde(PI);'#10 +
    '  Result := TKunde(N);'#10 +
    '  Result := TKunde(Pointer(N));'#10 +
    '  K := IKunde(AZeiger);'#10 +
    '  Result := TFremd(AZeiger);'#10 +
    '  Result := TKunde(Unbekannt);'#10))));
end;

procedure TUnsafeCodeTests.CastSilentByDefault;
begin
  Assert.AreEqual('', Messages(Findings(Source('', '', '  Result := TKunde(AZeiger);'#10))));
end;

procedure TUnsafeCodeTests.OffAndRegistered;
var
  mSource: string;
  mRule: IRule;
  mFound: Boolean;
begin
  mSource := Source('{$WARN UNSAFE_CODE ON}'#10, '  P: Pointer;'#10, '  P := @AWert;'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TUnsafeCodeRule.Create, mSource,
    '{"rules": {"unsafe-code": "off"}}', 'Fall.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TUnsafeCodeRule.Create, mSource,
    '{"rules": {"group:compiler": "off"}}', 'Fall.pas'))));
  mFound := False;
  for mRule in BuiltinRules do
    if mRule.Descriptor.Id = UnsafeCodeRuleId then
      mFound := True;
  Assert.IsTrue(mFound);
end;

initialization
  TDUnitX.RegisterTestFixture(TUnsafeCodeTests);

end.
