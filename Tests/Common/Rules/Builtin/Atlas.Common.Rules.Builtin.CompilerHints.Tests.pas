unit Atlas.Common.Rules.Builtin.CompilerHints.Tests;

// Tests der Regel compiler-hints (#1381): W1055 (published ohne RTTI) mit
// Gegenfällen ({$M+}, {$TYPEINFO ON}, Vorfahr mit RTTI in der Datei und in
// einer anderen Unit, unbekannter Vorfahr, {$WARN … OFF}, generisch), H2243
// (Initialize/Finalize mit Integer, Double, Alias) und H2244 (PString) mit
// Gegenfällen (verwaltete Typen, P^, eigene Routine Finalize, with,
// {$HINTS OFF}, eigener Typ PString); abschaltbar und registriert.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCompilerHintsRulesTests = class
  public
    /// <summary>Wie Cm.W1055: Meldung am ersten published-Mitglied, einmal je Klasse.</summary>
    [Test]
    procedure PublishedWithoutTypeInfo;
    [Test]
    procedure TypeInfoSwitchIsSilent;
    [Test]
    procedure AncestorWithTypeInfoInFile;
    [Test]
    procedure AncestorInOtherUnit;
    [Test]
    procedure UnknownAncestorIsSilent;
    [Test]
    procedure WarningOffIsSilent;
    [Test]
    procedure GenericAndEmptySectionAreSilent;
    /// <summary>Wie Cm.E2243 (Delphi 13 meldet H2243).</summary>
    [Test]
    procedure FinalizePlainType;
    [Test]
    procedure ManagedTypesAreSilent;
    /// <summary>Wie Cm.H2244.</summary>
    [Test]
    procedure FinalizePointerToManagedType;
    [Test]
    procedure OwnRoutineAndWithAreSilent;
    [Test]
    procedure HintsOffIsSilent;
    [Test]
    procedure Switchable;
    [Test]
    procedure RuleIsRegistered;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.CompilerHints,
  Atlas.Tests.RuleAssert;

const
  cBasisUnit =
    'unit Werk.Basis;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TOhne = class'#10 +
    '  public'#10 +
    '    procedure Lauf;'#10 +
    '  end;'#10 +
    '{$M+}'#10 +
    '  TMitRtti = class'#10 +
    '  end;'#10 +
    '{$M-}'#10 +
    'implementation'#10 +
    'procedure TOhne.Lauf;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

function Findings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TCompilerHintsRule.Create, ASource, nil, '', 'Haupt.pas');
end;

function Findings(const ASource, AConfig: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TCompilerHintsRule.Create, ASource, nil, AConfig, 'Haupt.pas');
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

function Klasse(const AHead, ABody: string): string;
begin
  Result := 'unit Haupt;'#10'interface'#10'type'#10 + AHead + #10 + ABody + '  end;'#10'implementation'#10'end.';
end;

function Routine(const ADeclarations, ABody: string): string;
begin
  Result := 'unit Haupt;'#10'interface'#10'implementation'#10 + ADeclarations +
    'procedure Fall(AZeiger: PString);'#10'var'#10'  mZahl: Integer;'#10'  mWert: Double;'#10'  mText: string;'#10 +
    '  mFeld: TArray<Integer>;'#10'begin'#10 + ABody + 'end;'#10'end.';
end;

/// <summary>Liest nur Werk.Basis, wenn AReadable.</summary>
function BasisReader(AReadable: Boolean): TRuleFileReader;
begin
  Result :=
    function(const AName: string; out AData: TBytes): Boolean
    begin
      Result := AReadable and SameText(AName, 'C:\P\Werk.Basis.pas');
      if Result then
        AData := TEncoding.UTF8.GetBytes(cBasisUnit);
    end;
end;

/// <summary>Zahl der Treffer für eine Klasse AHead mit published-Methode in Haupt, die Werk.Basis verwendet.
/// </summary>
function AncestorFindings(const AHead: string; AReadable: Boolean): Integer;
var
  mIndex: ISymbolIndex;
  mContext: TRuleContext;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cBasisUnit, 'C:\P\Werk.Basis.pas', nil));
  mContext := Default(TRuleContext);
  mContext.RelativePath := 'Haupt.pas';
  mContext.FileName := 'C:\P\Haupt.pas';
  mContext.Text := 'unit Haupt;'#10'interface'#10'uses Werk.Basis;'#10'type'#10 + AHead + #10 +
    '  published'#10'    procedure Machen;'#10'  end;'#10'implementation'#10'end.';
  mContext.Index := mIndex;
  mContext.ReadFile := BasisReader(AReadable);
  Result := Length(TRuleAssert.ContextFindings(TCompilerHintsRule.Create, mContext, ''));
end;

{ TCompilerHintsRulesTests }

procedure TCompilerHintsRulesTests.PublishedWithoutTypeInfo;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(Klasse('  TOhneRtti = class', '  published'#10'    procedure Machen;'#10 +
    '    procedure Weiter;'#10'  published'#10'    property Wert: Integer read FWert;'#10));
  Assert.AreEqual('5:14 published schaltet für TOhneRtti RTTI ein ($M+), weil weder die Klasse noch ein Vorfahr ' +
    'mit RTTI übersetzt wird (wie W1055). Von TPersistent ableiten oder {$M+} vor die Deklaration setzen, wenn ' +
    'das gewollt ist.|', Messages(mFound));
  Assert.AreEqual(CompilerHintsRuleId, mFound[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFound[0].Severity));
  // Ausdrücklich TObject als Vorfahr und ein Feld (Cm.E2217) melden ebenso.
  Assert.AreEqual(1, Integer(Length(Findings(Klasse('  TKlasse = class(TObject)',
    '  published'#10'    FWert: Integer;'#10)))));
end;

procedure TCompilerHintsRulesTests.TypeInfoSwitchIsSilent;
const
  cBody = '  published'#10'    procedure Machen;'#10;
begin
  Assert.AreEqual('', Messages(Findings(Klasse('{$M+}'#10'  TKlasse = class', cBody))));
  Assert.AreEqual('', Messages(Findings(Klasse('{$TYPEINFO ON}'#10'  TKlasse = class', cBody))));
  Assert.AreEqual('', Messages(Findings(Klasse('{$R-,M+}'#10'  TKlasse = class', cBody))));
  // {$M+} nur in einem inaktiven Zweig zählt nicht.
  Assert.AreEqual(1, Integer(Length(Findings(Klasse('{$IFDEF NIE_DEFINIERT}{$M+}{$ENDIF}'#10 +
    '  TKlasse = class', cBody)))));
  Assert.AreEqual(1, Integer(Length(Findings(Klasse('{$M+}{$M-}'#10'  TKlasse = class', cBody)))));
end;

procedure TCompilerHintsRulesTests.AncestorWithTypeInfoInFile;
begin
  // Bekannte Nachfahren von TPersistent und Vorfahren aus der Datei mit {$M+} bzw. eigenem published.
  Assert.AreEqual('', Messages(Findings(Klasse('  TKlasse = class(TPersistent)',
    '  published'#10'    procedure Machen;'#10))));
  Assert.AreEqual('', Messages(Findings(Klasse('  TForm1 = class(TForm)',
    '  published'#10'    procedure Machen;'#10))));
  Assert.AreEqual('', Messages(Findings(Klasse('{$M+}'#10'  TBasis = class'#10'  end;'#10'{$M-}'#10 +
    '  TKind = class(TBasis)', '  published'#10'    procedure Machen;'#10))));
  // Nur der Vorfahr meldet; der Nachfahr erbt die RTTI.
  Assert.AreEqual('5:14 published schaltet für TBasis RTTI ein ($M+), weil weder die Klasse noch ein Vorfahr ' +
    'mit RTTI übersetzt wird (wie W1055). Von TPersistent ableiten oder {$M+} vor die Deklaration setzen, wenn ' +
    'das gewollt ist.|', Messages(Findings(Klasse('  TBasis = class'#10'  published'#10'    procedure Basis;'#10 +
    '  end;'#10'  TKind = class(TBasis)', '  published'#10'    procedure Machen;'#10))));
  // Vorfahr ohne RTTI in der Datei: der Nachfahr meldet.
  Assert.AreEqual(1, Integer(Length(Findings(Klasse('  TBasis = class'#10'  end;'#10 +
    '  TKind = class(TBasis)', '  published'#10'    procedure Machen;'#10)))));
end;

procedure TCompilerHintsRulesTests.AncestorInOtherUnit;
begin
  Assert.AreEqual(1, AncestorFindings('  TKind = class(TOhne)', True));
  Assert.AreEqual(0, AncestorFindings('  TKind = class(TMitRtti)', True));
  // Lässt sich die Datei des Vorfahren nicht lesen, ist {$M+} dort unbekannt.
  Assert.AreEqual(0, AncestorFindings('  TKind = class(TOhne)', False));
end;

procedure TCompilerHintsRulesTests.UnknownAncestorIsSilent;
begin
  Assert.AreEqual('', Messages(Findings(Klasse('  TKlasse = class(TFremd)',
    '  published'#10'    procedure Machen;'#10))));
end;

procedure TCompilerHintsRulesTests.WarningOffIsSilent;
const
  cBody = '  published'#10'    procedure Machen;'#10;
begin
  Assert.AreEqual('', Messages(Findings(Klasse('{$WARN TYPEINFO_IMPLICITLY_ADDED OFF}'#10'  TKlasse = class',
    cBody))));
  Assert.AreEqual('', Messages(Findings(Klasse('{$WARNINGS OFF}'#10'  TKlasse = class', cBody))));
  // Wie Cm.W1055: ausdrücklich eingeschaltet.
  Assert.AreEqual(1, Integer(Length(Findings(Klasse('{$WARN TYPEINFO_IMPLICITLY_ADDED ON}'#10 +
    '  TKlasse = class', cBody)))));
end;

procedure TCompilerHintsRulesTests.GenericAndEmptySectionAreSilent;
begin
  Assert.AreEqual('', Messages(Findings(Klasse('  TListe<T> = class', '  published'#10'    procedure Machen;'#10))));
  Assert.AreEqual('', Messages(Findings(Klasse('  TKlasse = class', '  published'#10'  public'#10 +
    '    procedure Machen;'#10))));
  Assert.AreEqual('', Messages(Findings(Klasse('  TKlasse = class', '  public'#10'    procedure Machen;'#10))));
end;

procedure TCompilerHintsRulesTests.FinalizePlainType;
begin
  Assert.AreEqual('10:2 Finalize(mZahl) hat keine Wirkung: Integer braucht kein Initialize/Finalize (wie H2243).|' +
    '11:2 Initialize(mWert) hat keine Wirkung: Double braucht kein Initialize/Finalize (wie H2243).|',
    Messages(Findings(Routine('', '  Finalize(mZahl);'#10'  Initialize(mWert);'#10))));
  // Über einen Alias.
  Assert.AreEqual(1, Integer(Length(Findings(ReplaceStr(Routine('type'#10'  TZahl = Integer;'#10,
    '  Finalize(mZahl);'#10), 'mZahl: Integer', 'mZahl: TZahl')))));
end;

procedure TCompilerHintsRulesTests.ManagedTypesAreSilent;
begin
  Assert.AreEqual('', Messages(Findings(Routine('', '  Finalize(mText);'#10'  Finalize(mFeld);'#10 +
    '  Finalize(AZeiger^);'#10'  Finalize(mZahl, 2);'#10))));
end;

procedure TCompilerHintsRulesTests.FinalizePointerToManagedType;
begin
  Assert.AreEqual('10:2 Finalize(AZeiger) wirkt auf den Zeiger, nicht auf das Ziel: AZeiger braucht kein ' +
    'Initialize/Finalize, gemeint ist wohl AZeiger^ (wie H2244).|',
    Messages(Findings(Routine('', '  Finalize(AZeiger);'#10))));
  // Ein eigener Typ PString ist kein Zeiger auf einen String.
  Assert.AreEqual('', Messages(Findings(Routine('type'#10'  PString = ^Integer;'#10, '  Finalize(AZeiger);'#10))));
end;

procedure TCompilerHintsRulesTests.OwnRoutineAndWithAreSilent;
begin
  Assert.AreEqual('', Messages(Findings(Routine('procedure Finalize(var AWert: Integer);'#10'begin'#10'end;'#10,
    '  Finalize(mZahl);'#10))));
  Assert.AreEqual('', Messages(Findings(Routine('', '  with TObject.Create do'#10'    Finalize(mZahl);'#10))));
end;

procedure TCompilerHintsRulesTests.HintsOffIsSilent;
begin
  Assert.AreEqual('', Messages(Findings(Routine('{$HINTS OFF}'#10, '  Finalize(mZahl);'#10))));
  Assert.AreEqual(1, Integer(Length(Findings(Routine('{$HINTS OFF}'#10'{$HINTS ON}'#10,
    '  Finalize(mZahl);'#10)))));
end;

procedure TCompilerHintsRulesTests.Switchable;
const
  cSource = 'unit Haupt;'#10'interface'#10'type'#10'  TKlasse = class'#10'  published'#10'    procedure Machen;'#10 +
    '  end;'#10'implementation'#10'end.';
begin
  Assert.AreEqual(0, Integer(Length(Findings(cSource, '{"rules": {"compiler-hints": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(Findings(cSource, '{"rules": {"group:compiler": "off"}}'))));
end;

procedure TCompilerHintsRulesTests.RuleIsRegistered;
var
  mRule: IRule;
  mFound: Boolean;
begin
  mFound := False;
  for mRule in BuiltinRules do
    if mRule.Descriptor.Id = CompilerHintsRuleId then
      mFound := True;
  Assert.IsTrue(mFound);
end;

initialization
  TDUnitX.RegisterTestFixture(TCompilerHintsRulesTests);

end.
