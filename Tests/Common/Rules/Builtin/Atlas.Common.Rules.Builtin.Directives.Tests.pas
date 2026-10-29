unit Atlas.Common.Rules.Builtin.Directives.Tests;

// Tests der Regeln für Compiler-Direktiven (#989): offene und überzählige
// bedingte Direktiven, Symbole, unbekannte Direktiven und {$WARN}-Bezeichner,
// {$PUSHOPT}/{$POPOPT}, {$ALIGN} und die Einstellungen; compiler-warnings-disabled
// (#972); directive-typo still bei Methodenzuordnungen (#1325, Minimalfall F03);
// compiler-directive-invalid (#1379): {$MESSAGE}, Package-Schalter,
// {$OBJTYPENAME}, {$CODEPAGE}, fehlende und rekursive Include-Dateien, fehlende
// Ressourcen, je mit Gegenfall aus Tests/Compilermeldungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDirectiveRulesTests = class
  public
    [Test]
    procedure UnbalancedIssueExample;
    [Test]
    procedure UnbalancedSilentCases;
    [Test]
    procedure UnbalancedStrayDirectives;
    [Test]
    procedure UnbalancedSymbols;
    [Test]
    procedure UnbalancedUnknownDirectives;
    [Test]
    procedure UnknownDirectiveCodeFollowsDelphiVersion;
    [Test]
    procedure UnbalancedOptionStack;
    [Test]
    procedure UnbalancedAlign;
    [Test]
    procedure UnbalancedOptions;
    [Test]
    procedure TypoIssueExample;
    [Test]
    procedure TypoOtherDirectives;
    [Test]
    procedure TypoWithoutSuggestion;
    [Test]
    procedure TypoPropertyDefault;
    [Test]
    procedure TypoSilentCases;
    [Test]
    procedure TypoMethodResolution;
    [Test]
    procedure TypoOptions;
    [Test]
    procedure WarningsIssueExample;
    [Test]
    procedure WarningsAllSwitches;
    [Test]
    procedure WarningsRestoredIsSilent;
    [Test]
    procedure WarningsAllowAndOff;
    [Test]
    procedure InvalidMessages;
    [Test]
    procedure InvalidPackageSwitches;
    [Test]
    procedure InvalidPackageOnlyInUnit;
    [Test]
    procedure InvalidObjTypeName;
    [Test]
    procedure InvalidCodePage;
    [Test]
    procedure InvalidMissingInclude;
    [Test]
    procedure InvalidRecursiveInclude;
    [Test]
    procedure InvalidMissingResource;
    [Test]
    procedure InvalidOptions;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.Directives,
  Atlas.Tests.RuleAssert;

function Dienst(const ABefore, ABody: string): string;
begin
  Result := 'unit Dienst;'#10'interface'#10'implementation'#10 + ABefore +
    'procedure Starten;'#10'begin'#10 + ABody + 'end;'#10'end.';
end;

function Findings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TConditionalDirectiveUnbalancedRule.Create, ASource);
end;

function Findings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TConditionalDirectiveUnbalancedRule.Create, ASource, AConfig, APath);
end;

function OnlyMessage(const ASource: string): string;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(ASource);
  Assert.AreEqual(1, Integer(Length(Found)), ASource);
  Result := Found[0].Message;
end;

/// <summary>Offset von APosition in AText mit Zeilen aus #10.</summary>
function OffsetOf(const AText: string; const APosition: TTextPosition): Integer;
var
  Line, Index: Integer;
begin
  Line := 0;
  Index := 1;
  while (Line < APosition.Line) and (Index <= Length(AText)) do
  begin
    if AText[Index] = #10 then
      Inc(Line);
    Inc(Index);
  end;
  Result := Index + APosition.Character;
end;

/// <summary>Wendet die Edits einer Korrektur von hinten nach vorn an, auch über Zeilen.</summary>
function ApplyFix(const AText: string; const AFix: TRuleFix): string;
var
  Index, Start, Stop: Integer;
begin
  Result := AText;
  for Index := High(AFix.Edits) downto 0 do
  begin
    Start := OffsetOf(Result, AFix.Edits[Index].Range.StartPos);
    Stop := OffsetOf(Result, AFix.Edits[Index].Range.EndPos);
    Result := Copy(Result, 1, Start - 1) + AFix.Edits[Index].NewText + Copy(Result, Stop, MaxInt);
  end;
end;

{ TDirectiveRulesTests }

procedure TDirectiveRulesTests.UnbalancedIssueExample;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := 'unit Dienst;'#10'interface'#10'implementation'#10'{$IFDEF DEBUG}'#10 +
    '  Protokoll.Ausfuehrlich := True;'#10#10'procedure TDienst.Starten;'#10'begin'#10'end;'#10'end.';
  Found := Findings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('{$IFDEF DEBUG} wird nie geschlossen; der Rest der Datei hängt an DEBUG (wie E2095).',
    Found[0].Message);
  Assert.AreEqual(3, Found[0].Range.StartPos.Line);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('{$ENDIF} nach Zeile 5 ergänzen', Found[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Found[0].Fixes[0]);
  Assert.AreEqual('unit Dienst;'#10'interface'#10'implementation'#10'{$IFDEF DEBUG}'#10 +
    '  Protokoll.Ausfuehrlich := True;'#10'{$ENDIF}'#10#10'procedure TDienst.Starten;'#10'begin'#10'end;'#10'end.',
    Fixed);
  TRuleAssert.Silent(TConditionalDirectiveUnbalancedRule.Create, Fixed);
  // {$IF} meldet wie E2280, {$IFNDEF} nennt die Verneinung.
  Assert.AreEqual('{$IF CompilerVersion >= 36} wird nie geschlossen; der Rest der Datei hängt an ' +
    'CompilerVersion >= 36 (wie E2280).', OnlyMessage(Dienst('{$IF CompilerVersion >= 36}'#10, '')));
  Assert.AreEqual('{$IFNDEF RELEASE} wird nie geschlossen; der Rest der Datei hängt an not RELEASE (wie E2095).',
    OnlyMessage(Dienst('{$IFNDEF RELEASE}'#10, '')));
end;

procedure TDirectiveRulesTests.UnbalancedSilentCases;
begin
  TRuleAssert.Silent(TConditionalDirectiveUnbalancedRule.Create, Dienst(
    '{$IFDEF DEBUG}'#10'{$IFNDEF WIN64}'#10'const A = 1;'#10'{$ENDIF}'#10'{$ELSEIF Defined(X)}'#10'{$ELSE}'#10 +
    '{$ENDIF}'#10'{$IF CompilerVersion >= 36}'#10'{$IFEND}'#10'{$IFOPT R+}'#10'{$ENDIF}'#10 +
    '(*$IFDEF X*)'#10'(*$ENDIF*)'#10, '  {$R *.res}'#10'  {$WARN SYMBOL_PLATFORM OFF}'#10'  {$A8}'#10 +
    '  {$ALIGN 16}'#10'  {$PUSHOPT}'#10'  {$R+,Q-}'#10'  {$POPOPT}'#10'  {$YD}'#10'  {$M+}'#10 +
    '  {$SetPEFlags 1}'#10'  {$region ''Teil''}'#10'  {$endregion}'#10'  {$I+}'#10'  {$Z4}'#10'  {$ALIGN ON}'#10));
  // FPC-Zweige: Direktiven, die nur FPC kennt, bleiben still.
  TRuleAssert.Silent(TConditionalDirectiveUnbalancedRule.Create, Dienst(
    '{$IFDEF FPC}'#10'{$MODE DELPHI}'#10'{$IFDEF CPU64}'#10'{$ASMMODE INTEL}'#10'{$ENDIF}'#10'{$ENDIF}'#10 +
    '{$IFNDEF FPC}'#10'{$ELSE}'#10'{$MODESWITCH ADVANCEDRECORDS}'#10'{$ENDIF}'#10 +
    '{$IF Defined(FPC_FULLVERSION)}'#10'{$WARN 5024 OFF}'#10'{$WARN UNKNOWN_FPC OFF}'#10'{$ENDIF}'#10, ''));
  // Außerhalb eines FPC-Zweigs meldet {$MODE}.
  Assert.AreEqual('Unbekannte Direktive {$MODE} (wie E1030).', OnlyMessage(Dienst('{$MODE DELPHI}'#10, '')));
end;

procedure TDirectiveRulesTests.UnbalancedStrayDirectives;
var
  Source: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Dienst('{$ENDIF}'#10, '');
  Found := Findings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('{$ENDIF} ohne passendes {$IF…} (wie E2279).', Found[0].Message);
  Assert.AreEqual('Überzähliges {$ENDIF} entfernen', Found[0].Fixes[0].Title);
  Assert.AreEqual(Dienst('', ''), ApplyFix(Source, Found[0].Fixes[0]));
  // In einer Zeile mit anderem Code nur die Direktive.
  Source := Dienst('', '  Exit; {$ELSE}'#10);
  Found := Findings(Source);
  Assert.AreEqual('{$ELSE} ohne passendes {$IF…} (wie E2279).', Found[0].Message);
  Assert.AreEqual(Dienst('', '  Exit; '#10), ApplyFix(Source, Found[0].Fixes[0]));
  Assert.AreEqual('{$ELSE} nach {$ELSE} von {$IFDEF X} aus Zeile 4 (wie E2279).',
    OnlyMessage(Dienst('{$IFDEF X}'#10'{$ELSE}'#10'{$ELSE}'#10'{$ENDIF}'#10, '')));
  Assert.AreEqual('{$ELSEIF} nach {$ELSE} von {$IF A} aus Zeile 4 (wie E2279).',
    OnlyMessage(Dienst('{$IF A}'#10'{$ELSE}'#10'{$ELSEIF B}'#10'{$ENDIF}'#10, '')));
end;

procedure TDirectiveRulesTests.UnbalancedSymbols;
begin
  Assert.AreEqual('{$IFDEF} ohne Symbol (wie E2173).', OnlyMessage(Dienst('{$IFDEF}'#10'{$ENDIF}'#10, '')));
  Assert.AreEqual('1X ist kein gültiges Symbol für {$DEFINE} (wie E2173).',
    OnlyMessage(Dienst('{$DEFINE 1X}'#10, '')));
  Assert.AreEqual('{$UNDEF} ohne Symbol (wie E2173).', OnlyMessage(Dienst('{$UNDEF }'#10, '')));
  TRuleAssert.Silent(TConditionalDirectiveUnbalancedRule.Create, Dienst('{$DEFINE Atlas_1}'#10 +
    '{$IFNDEF Atlas_1}'#10'{$ENDIF}'#10, ''));
end;

procedure TDirectiveRulesTests.UnbalancedUnknownDirectives;
var
  Source: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Dienst('', '  {$OPTIMISATION ON}'#10);
  Found := Findings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Unbekannte Direktive {$OPTIMISATION}; gemeint ist wohl {$OPTIMIZATION} (wie E1030).',
    Found[0].Message);
  Assert.AreEqual('Tippfehler korrigieren: {$OPTIMIZATION}', Found[0].Fixes[0].Title);
  Assert.AreEqual(Dienst('', '  {$OPTIMIZATION ON}'#10), ApplyFix(Source, Found[0].Fixes[0]));
  // Kleinschreibung bleibt.
  Source := Dienst('', '  {$optimisation on}'#10);
  Assert.AreEqual(Dienst('', '  {$optimization on}'#10), ApplyFix(Source, Findings(Source)[0].Fixes[0]));
  Assert.AreEqual('Unbekannte Direktive {$FOOBAR} (wie E1030).', OnlyMessage(Dienst('{$FOOBAR}'#10, '')));
  // {$WARN} mit unbekanntem Bezeichner.
  Assert.AreEqual('Unbekannte Warnung UNKOWN in {$WARN} (wie E1030).',
    OnlyMessage(Dienst('{$WARN UNKOWN OFF}'#10, '')));
  Source := Dienst('{$WARN SYMBOL_PLATFROM OFF}'#10, '');
  Found := Findings(Source);
  Assert.AreEqual('Unbekannte Warnung SYMBOL_PLATFROM in {$WARN}; gemeint ist wohl SYMBOL_PLATFORM (wie E1030).',
    Found[0].Message);
  Assert.AreEqual(Dienst('{$WARN SYMBOL_PLATFORM OFF}'#10, ''), ApplyFix(Source, Found[0].Fixes[0]));
  // Ein Tippfehler in {$IFDEF} lässt das {$ENDIF} ohne Gegenstück.
  Found := Findings(Dienst('{$IFDEFF DEBUG}'#10'{$ENDIF}'#10, ''));
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('Unbekannte Direktive {$IFDEFF}; gemeint ist wohl {$IFDEF} (wie E1030).', Found[0].Message);
end;

procedure TDirectiveRulesTests.UnknownDirectiveCodeFollowsDelphiVersion;
var
  mFound: TArray<TRuleFinding>;
begin
  // Delphi 13 meldet E1030 (Fall Cm.W1030), ältere Versionen W1030 (#1382).
  mFound := Findings(Dienst('{$FOOBAR}'#10'{$WARN UNKOWN OFF}'#10, ''), '{"delphiVersion": "23.0"}', 'Dienst.pas');
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual('Unbekannte Direktive {$FOOBAR} (wie W1030).', mFound[0].Message);
  Assert.AreEqual('Unbekannte Warnung UNKOWN in {$WARN} (wie W1030).', mFound[1].Message);
  mFound := Findings(Dienst('{$FOOBAR}'#10, ''), '{"delphiVersion": "37.0"}', 'Dienst.pas');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Unbekannte Direktive {$FOOBAR} (wie E1030).', mFound[0].Message);
  mFound := nil;
end;

procedure TDirectiveRulesTests.UnbalancedOptionStack;
var
  Found: TArray<TRuleFinding>;
begin
  Assert.AreEqual('{$POPOPT} ohne vorheriges {$PUSHOPT} (wie W1078).', OnlyMessage(Dienst('', '  {$POPOPT}'#10)));
  Found := Findings(Dienst('{$PUSHOPT}'#10'{$PUSHOPT}'#10, '  {$POPOPT}'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('{$PUSHOPT} ohne passendes {$POPOPT} (wie W1079).', Found[0].Message);
  Assert.AreEqual(3, Found[0].Range.StartPos.Line);
  // In bedingten Zweigen prüft die Regel die Paare nicht.
  TRuleAssert.Silent(TConditionalDirectiveUnbalancedRule.Create, Dienst('{$IFDEF X}'#10'{$PUSHOPT}'#10 +
    '{$ENDIF}'#10, ''));
end;

procedure TDirectiveRulesTests.UnbalancedAlign;
begin
  Assert.AreEqual('Ungültiger Wert 3 für {$ALIGN}; erlaubt sind ON, OFF, 1, 2, 4, 8 und 16 (wie E2573).',
    OnlyMessage(Dienst('{$ALIGN 3}'#10, '')));
  Assert.AreEqual('Ungültiger Wert 32 für {$ALIGN}; erlaubt sind ON, OFF, 1, 2, 4, 8 und 16 (wie E2573).',
    OnlyMessage(Dienst('{$R+,A32}'#10, '')));
  Assert.AreEqual('Ungültiger Wert DOUBLE für {$ALIGN}; erlaubt sind ON, OFF, 1, 2, 4, 8 und 16 (wie E2573).',
    OnlyMessage(Dienst('{$ALIGN DOUBLE}'#10, '')));
  TRuleAssert.Silent(TConditionalDirectiveUnbalancedRule.Create, Dienst('{$A+}'#10'{$A-}'#10'{$A4}'#10 +
    '{$ALIGN OFF}'#10, ''));
end;

procedure TDirectiveRulesTests.UnbalancedOptions;
var
  Source: string;
begin
  Source := Dienst('{$IFDEF DEBUG}'#10, '');
  Assert.AreEqual(1, Integer(Length(Findings(Source, '', 'Source/Dienst.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"conditional-directive-unbalanced": "off"}}',
    'Source/Dienst.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"group:compiler": "off"}}', 'Source/Dienst.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source,
    '{"rules": {"conditional-directive-unbalanced": {"exclude": ["Source/*.pas"]}}}', 'Source/Dienst.pas'))));
  Assert.AreEqual(1, Integer(Length(Findings(Source,
    '{"rules": {"conditional-directive-unbalanced": {"exclude": ["Alt/*.pas"]}}}', 'Source/Dienst.pas'))));
end;

function Klasse(const AMembers: string): string;
begin
  Result := 'unit Dienst;'#10'interface'#10'type'#10'  TAnzeige = class'#10 + AMembers + '  end;'#10 +
    'implementation'#10'end.';
end;

function TypoFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TDirectiveTypoRule.Create, ASource);
end;

function TypoFindings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TDirectiveTypoRule.Create, ASource, AConfig, APath);
end;

procedure TDirectiveRulesTests.TypoIssueExample;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Klasse('    procedure Paint; overide;'#10);
  Found := TypoFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Unbekannte Direktive overide; gemeint ist override (wie E2070).', Found[0].Message);
  Assert.IsTrue(Found[0].Confidence = TRuleConfidence.High);
  Assert.AreEqual(4, Found[0].Range.StartPos.Line);
  Assert.AreEqual(21, Found[0].Range.StartPos.Character);
  Assert.AreEqual(28, Found[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('Durch override ersetzen', Found[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Found[0].Fixes[0]);
  Assert.AreEqual(Klasse('    procedure Paint; override;'#10), Fixed);
  TRuleAssert.Silent(TDirectiveTypoRule.Create, Fixed);
end;

procedure TDirectiveRulesTests.TypoOtherDirectives;
var
  Found: TArray<TRuleFinding>;
begin
  Found := TypoFindings(Klasse('    procedure Laden; virutal; overlaod;'#10 +
    '    procedure Zeichnen; REINTRODUCES;'#10));
  Assert.AreEqual(3, Integer(Length(Found)));
  Assert.AreEqual('Unbekannte Direktive virutal; gemeint ist virtual (wie E2070).', Found[0].Message);
  Assert.AreEqual('Unbekannte Direktive overlaod; gemeint ist overload (wie E2070).', Found[1].Message);
  // Groß geschrieben bleibt groß.
  Assert.AreEqual('Unbekannte Direktive REINTRODUCES; gemeint ist REINTRODUCE (wie E2070).', Found[2].Message);
  Found := TypoFindings('unit Dienst;'#10'interface'#10'implementation'#10'procedure Frei; stdcal;'#10 +
    'begin'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Unbekannte Direktive stdcal; gemeint ist stdcall (wie E2070).', Found[0].Message);
end;

procedure TDirectiveRulesTests.TypoWithoutSuggestion;
var
  Found: TArray<TRuleFinding>;
begin
  Found := TypoFindings(Klasse('    procedure Paint; Zeichnen;'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Unbekannte Direktive Zeichnen (wie E2070).', Found[0].Message);
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
end;

procedure TDirectiveRulesTests.TypoPropertyDefault;
var
  Source: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Klasse('    function Get(I: Integer): string;'#10 +
    '    property Items[I: Integer]: string read Get; defualt;'#10);
  Found := TypoFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Unbekannte Direktive defualt; gemeint ist default (wie E2070).', Found[0].Message);
  TRuleAssert.Silent(TDirectiveTypoRule.Create, ApplyFix(Source, Found[0].Fixes[0]));
end;

procedure TDirectiveRulesTests.TypoSilentCases;
begin
  // Bekannte Direktiven, Hinweise, external mit Argumenten, inline und Felder nach Methoden.
  TRuleAssert.Silent(TDirectiveTypoRule.Create, Klasse('    procedure A; virtual; abstract;'#10 +
    '    procedure B; overload; deprecated ''Nutze A'';'#10 +
    '    procedure C(Msg: Integer); message 15;'#10 +
    '    function D: Integer; inline;'#10 +
    '    class procedure E; static;'#10 +
    '    property Items[I: Integer]: Integer read D; default;'#10));
  TRuleAssert.Silent(TDirectiveTypoRule.Create, 'unit Dienst;'#10'interface'#10 +
    'function MessageBoxW(H: Pointer; T, C: PChar; F: Cardinal): Integer; stdcall; external ''user32.dll'' ' +
    'name ''MessageBoxW'';'#10'implementation'#10'end.');
  // FPC kennt weitere Direktiven.
  TRuleAssert.Silent(TDirectiveTypoRule.Create, 'unit Dienst;'#10'interface'#10'implementation'#10 +
    'procedure Frei;'#10'{$IFDEF FPC} nostackframe; {$ENDIF}'#10'begin'#10'end;'#10'end.');
end;

procedure TDirectiveRulesTests.TypoMethodResolution;
begin
  // F03: "= MyGetX" ist das Ziel einer Methodenzuordnung, keine Direktive; auch bei generischen Interfaces.
  TRuleAssert.Silent(TDirectiveTypoRule.Create, 'unit F03_MethodResolution;'#10'interface'#10'type'#10 +
    '  IFoo = interface'#10'    function GetX: Integer;'#10'  end;'#10'  TA = class(TInterfacedObject, IFoo)'#10 +
    '    function IFoo.GetX = MyGetX;'#10'    function MyGetX: Integer;'#10'  end;'#10 +
    '  TE<T> = class(TInterfacedObject, IEnumerator<T>)'#10'    function GetCurrentGen: T;'#10 +
    '    function IEnumerator<T>.GetCurrent = GetCurrentGen;'#10'  end;'#10'implementation'#10'end.');
  // Gegenprobe: ein Tippfehler neben einer Zuordnung wird weiter gemeldet.
  Assert.AreEqual(1, Integer(Length(TypoFindings(Klasse('    function IFoo.GetX = MyGetX;'#10 +
    '    procedure Paint; overide;'#10)))));
end;

procedure TDirectiveRulesTests.TypoOptions;
var
  Source: string;
begin
  Source := Klasse('    procedure Paint; overide;'#10);
  Assert.AreEqual(1, Integer(Length(TypoFindings(Source, '', 'Source/Dienst.pas'))));
  Assert.AreEqual(0, Integer(Length(TypoFindings(Source, '{"rules": {"directive-typo": "off"}}',
    'Source/Dienst.pas'))));
  Assert.AreEqual(0, Integer(Length(TypoFindings(Source, '{"rules": {"group:compiler": "off"}}',
    'Source/Dienst.pas'))));
  Assert.AreEqual(0, Integer(Length(TypoFindings(Source, '{"rules": {"directive-typo": {"exclude": ["Source/*.pas"]}}}',
    'Source/Dienst.pas'))));
end;

function WarningsFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TCompilerWarningsDisabledRule.Create, ASource);
end;

function WarningsFindings(const ASource, AConfig: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TCompilerWarningsDisabledRule.Create, ASource, AConfig, 'Dienst.pas');
end;

const
  // Beispiel aus #972
  AlteBerechnung = 'unit Dienst;'#10'interface'#10'implementation'#10'{$WARNINGS OFF}'#10 +
    'function AlteBerechnung(const Wert: Integer): Integer;'#10'begin'#10'  Result := Wert * 2;'#10'end;'#10#10 +
    'procedure Neu;'#10'begin'#10'end;'#10'end.';

procedure TDirectiveRulesTests.WarningsIssueExample;
var
  Found: TArray<TRuleFinding>;
begin
  Found := WarningsFindings(AlteBerechnung);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Found[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Found[0].Confidence));
  Assert.AreEqual('WARNINGS bleibt bis zum Ende der Unit aus; alle späteren Warnungen fehlen.', Found[0].Message);
  Assert.AreEqual(3, Found[0].Range.StartPos.Line);
  Assert.AreEqual(15, Found[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('Nach dem nächsten Block wiederherstellen', Found[0].Fixes[0].Title);
  Assert.IsTrue(Found[0].Fixes[0].Safe);
  Assert.AreEqual(StringReplace(AlteBerechnung, 'Wert * 2;'#10'end;'#10, 'Wert * 2;'#10'end;'#10'{$WARNINGS ON}'#10,
    []), ApplyFix(AlteBerechnung, Found[0].Fixes[0]));
  // Korrigierte Form
  Assert.AreEqual(0, Integer(Length(WarningsFindings(ApplyFix(AlteBerechnung, Found[0].Fixes[0])))));
end;

procedure TDirectiveRulesTests.WarningsAllSwitches;
var
  Source: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Dienst('{$HINTS OFF}'#10'{$WARN SYMBOL_PLATFORM OFF}'#10'{$R-,Q-}'#10'{$OVERFLOWCHECKS OFF}'#10,
    '  X := 1;'#10);
  Found := WarningsFindings(Source);
  Assert.AreEqual(5, Integer(Length(Found)));
  Assert.AreEqual('HINTS bleibt bis zum Ende der Unit aus; alle späteren Hinweise fehlen.', Found[0].Message);
  Assert.AreEqual('Die Warnung SYMBOL_PLATFORM bleibt bis zum Ende der Unit aus.', Found[1].Message);
  Assert.AreEqual('Die Bereichsprüfung bleibt bis zum Ende der Unit aus; Überschreitungen fallen nicht mehr auf.',
    Found[2].Message);
  Assert.AreEqual('Die Überlaufprüfung bleibt bis zum Ende der Unit aus; Überläufe fallen nicht mehr auf.',
    Found[3].Message);
  Assert.AreEqual(Found[2].Range.StartPos.Line, Found[3].Range.StartPos.Line, '{$R-,Q-} meldet beide');
  Assert.IsTrue(ApplyFix(Source, Found[1].Fixes[0]).Contains('end;'#10'{$WARN SYMBOL_PLATFORM DEFAULT}'));
  // {$R+} könnte die Prüfung erst einschalten: nur einzeln
  Assert.IsTrue(Found[1].Fixes[0].Safe);
  Assert.IsFalse(Found[2].Fixes[0].Safe);
  Assert.IsTrue(ApplyFix(Source, Found[2].Fixes[0]).Contains('end;'#10'{$R+}'));
  Assert.IsTrue(ApplyFix(Source, Found[3].Fixes[0]).Contains('end;'#10'{$Q+}'));
  Assert.IsTrue(ApplyFix(Source, Found[4].Fixes[0]).Contains('end;'#10'{$OVERFLOWCHECKS ON}'));
end;

procedure TDirectiveRulesTests.WarningsRestoredIsSilent;
begin
  // Wiederhergestellt, auch über {$IFOPT}-Muster und {$POPOPT}
  Assert.AreEqual(0, Integer(Length(WarningsFindings(Dienst('{$WARNINGS OFF}'#10, '  X := 1;'#10) +
    #10'{$WARNINGS ON}'))));
  Assert.AreEqual(0, Integer(Length(WarningsFindings(Dienst('{$IFOPT R+}{$DEFINE BEREICH}{$ENDIF}{$R-}'#10,
    '  X := 1;'#10'{$IFDEF BEREICH}{$R+}{$ENDIF}'#10)))));
  Assert.AreEqual(0, Integer(Length(WarningsFindings(Dienst('{$PUSHOPT}{$Q-}'#10, '  X := 1;'#10'{$POPOPT}'#10)))));
  Assert.AreEqual(0, Integer(Length(WarningsFindings(Dienst('{$WARN GARBAGE OFF}'#10,
    '  X := 1;'#10'{$WARN GARBAGE ERROR}'#10)))));
  // Gewollt je Konfiguration
  Assert.AreEqual(0, Integer(Length(WarningsFindings(Dienst('{$IFDEF DEBUG}{$R+}{$ELSE}{$R-}{$ENDIF}'#10,
    '  X := 1;'#10)))));
  // Ressourcen, eingeschaltete Schalter, nichts mehr dahinter
  Assert.AreEqual(0, Integer(Length(WarningsFindings(Dienst('{$R *.dfm}'#10'{$R+}'#10'{$HINTS ON}'#10, '')))));
  Assert.AreEqual(0, Integer(Length(WarningsFindings('unit Dienst;'#10'interface'#10'implementation'#10 +
    '{$WARNINGS OFF}'#10'end.'))));
  // Optionen eines Packages pflegt die IDE in der .dpk.
  Assert.AreEqual(0, Integer(Length(WarningsFindings('package Paket;'#10'{$R *.res}'#10'{$RANGECHECKS OFF}'#10 +
    '{$OVERFLOWCHECKS OFF}'#10'requires'#10'  rtl;'#10'contains'#10'  Dienst in ''Dienst.pas'';'#10'end.'))));
end;

procedure TDirectiveRulesTests.WarningsAllowAndOff;
var
  Source: string;
  Issues: TArray<TConfigurationIssue>;
begin
  TConfigurationParser.Parse('{"rules": {"compiler-warnings-disabled": {"allow": "R"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual('"allow" muss eine Liste von Texten sein', Issues[0].Message);
  Source := Dienst('{$WARN SYMBOL_PLATFORM OFF}'#10'{$R-}'#10, '');
  Assert.AreEqual(2, Integer(Length(WarningsFindings(Source, ''))));
  Assert.AreEqual(1, Integer(Length(WarningsFindings(Source,
    '{"rules": {"compiler-warnings-disabled": {"allow": ["symbol_platform"]}}}'))));
  Assert.AreEqual(0, Integer(Length(WarningsFindings(Source,
    '{"rules": {"compiler-warnings-disabled": {"allow": ["SYMBOL_PLATFORM", "R"]}}}'))));
  Assert.AreEqual(1, Integer(Length(WarningsFindings(Source,
    '{"rules": {"compiler-warnings-disabled": {"allow": ["RANGECHECKS"]}}}'))));
  Assert.AreEqual(0, Integer(Length(WarningsFindings(Source, '{"rules": {"compiler-warnings-disabled": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(WarningsFindings(Source, '{"rules": {"group:robustness": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TCompilerWarningsDisabledRule.Create, Source,
    '{"rules": {"compiler-warnings-disabled": {"exclude": ["Alt/*.pas"]}}}', 'Alt/Dienst.pas'))));
end;

type
  /// <summary>Unit-Suche, die für FindFile immer FAnswer liefert (#1379).</summary>
  TFileLookup = class(TInterfacedObject, IRuleUnitLookup)
  private
    FAnswer: TRuleUnitAnswer;
  public
    constructor Create(AAnswer: TRuleUnitAnswer);
    function Find(const AUnitName, AInPath, AFromFile: string; ASources: TRuleUnitSources): TRuleUnitAnswer;
    function FindPackage(const APackage: string): TRuleUnitAnswer;
    function FindFile(const AFileName, AFromFile: string): TRuleUnitAnswer;
    function KnownUnits(ASources: TRuleUnitSources): TArray<string>;
    function FolderOutsidePaths(const AUnitName: string): string;
    function ReadProject(out AFileName, AText: string): Boolean;
  end;

constructor TFileLookup.Create(AAnswer: TRuleUnitAnswer);
begin
  inherited Create;
  FAnswer := AAnswer;
end;

function TFileLookup.Find(const AUnitName, AInPath, AFromFile: string; ASources: TRuleUnitSources): TRuleUnitAnswer;
begin
  Result := TRuleUnitAnswer.Unknown;
end;

function TFileLookup.FindPackage(const APackage: string): TRuleUnitAnswer;
begin
  Result := TRuleUnitAnswer.Unknown;
end;

function TFileLookup.FindFile(const AFileName, AFromFile: string): TRuleUnitAnswer;
begin
  Result := FAnswer;
end;

function TFileLookup.KnownUnits(ASources: TRuleUnitSources): TArray<string>;
begin
  Result := nil;
end;

function TFileLookup.FolderOutsidePaths(const AUnitName: string): string;
begin
  Result := '';
end;

function TFileLookup.ReadProject(out AFileName, AText: string): Boolean;
begin
  AFileName := '';
  AText := '';
  Result := False;
end;

function InvalidFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TCompilerDirectiveInvalidRule.Create, ASource);
end;

function InvalidFindings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TCompilerDirectiveInvalidRule.Create, ASource, AConfig, APath);
end;

function InvalidMessage(const ASource: string): string;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := InvalidFindings(ASource);
  Assert.AreEqual(1, Integer(Length(mFound)), ASource);
  Result := mFound[0].Message;
end;

/// <summary>Dateizugriff neben der Unit: ANames (Inhalt ATexts) gibt es, sonst nichts. Eigene Routine, damit die
/// anonymen Methoden nur die Parameter einfangen.</summary>
function FileContext(const ASource: string; const ANames, ATexts: TArray<string>;
  const AUnits: IRuleUnitLookup): TRuleContext;
begin
  Result := Default(TRuleContext);
  Result.RelativePath := 'Source/Dienst.pas';
  Result.UnitName := 'Dienst';
  Result.FileName := 'C:\P\Source\Dienst.pas';
  Result.Text := ASource;
  Result.Units := AUnits;
  Result.FileExists :=
    function(const AName: string): Boolean
    var
      mIndex: Integer;
    begin
      Result := False;
      for mIndex := 0 to High(ANames) do
        if SameText(ANames[mIndex], AName) then
          Result := True;
    end;
  Result.ReadFile :=
    function(const AName: string; out AData: TBytes): Boolean
    var
      mIndex: Integer;
    begin
      Result := False;
      for mIndex := 0 to High(ANames) do
        if SameText(ANames[mIndex], AName) then
        begin
          AData := TEncoding.UTF8.GetBytes(ATexts[mIndex]);
          Result := True;
        end;
    end;
end;

function FileFindings(const ASource: string; const ANames, ATexts: TArray<string>;
  AAnswer: TRuleUnitAnswer): TArray<TRuleFinding>;
var
  mUnits: IRuleUnitLookup;
begin
  // Erst in eine Variable: direkt an einen const-Parameter übergeben, würde das Objekt nie freigegeben.
  mUnits := TFileLookup.Create(AAnswer);
  Result := TRuleAssert.ContextFindings(TCompilerDirectiveInvalidRule.Create,
    FileContext(ASource, ANames, ATexts, mUnits), '');
end;

procedure TDirectiveRulesTests.InvalidMessages;
var
  mFound: TArray<TRuleFinding>;
begin
  // Fälle Cm.W1054 und Cm.H1054: dcc meldet die Texte als Warnung bzw. Hinweis.
  mFound := InvalidFindings(Dienst('{$MESSAGE WARN ''Eigene Warnung''}'#10'{$MESSAGE Hint ''Eigener Hinweis''}'#10,
    ''));
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual('{$MESSAGE WARN}: Eigene Warnung (wie W1054).', mFound[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFound[0].Severity));
  Assert.AreEqual(3, mFound[0].Range.StartPos.Line);
  Assert.AreEqual('{$MESSAGE HINT}: Eigener Hinweis (wie H1054).', mFound[1].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFound[1].Severity));
  Assert.AreEqual('{$MESSAGE WARN}: Kunde''s Wert (wie W1054).',
    InvalidMessage(Dienst('{$MESSAGE WARN ''Kunde''''s Wert''}'#10, '')));
  // Ohne Art, ERROR/FATAL (noch nicht mit dcc abgeglichen) und in bedingten Zweigen still.
  TRuleAssert.Silent(TCompilerDirectiveInvalidRule.Create, Dienst('{$MESSAGE ''Ohne Art''}'#10 +
    '{$MESSAGE ERROR ''Fehler''}'#10'{$MESSAGE FATAL ''Abbruch''}'#10'{$MESSAGE WARN}'#10 +
    '{$IFDEF DEBUG}'#10'{$MESSAGE WARN ''Nur im Debug''}'#10'{$ENDIF}'#10, ''));
end;

procedure TDirectiveRulesTests.InvalidPackageSwitches;
var
  mFound: TArray<TRuleFinding>;
begin
  // Fall Cm.E2222: dcc meldet an der zweiten Direktive.
  mFound := InvalidFindings('unit Dienst;'#10'{$WEAKPACKAGEUNIT ON}'#10'{$DENYPACKAGEUNIT ON}'#10'interface'#10 +
    'implementation'#10'end.');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('{$WEAKPACKAGEUNIT ON} und {$DENYPACKAGEUNIT ON} schließen sich aus (wie E2222).',
    mFound[0].Message);
  Assert.AreEqual(2, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(1, Integer(Length(InvalidFindings(Dienst('{$DENYPACKAGEUNIT ON}'#10'{$WEAKPACKAGEUNIT ON}'#10,
    '')))));
  // Nur einer, wieder aus, oder in einem bedingten Zweig: ohne Meldung.
  TRuleAssert.Silent(TCompilerDirectiveInvalidRule.Create, Dienst('{$WEAKPACKAGEUNIT ON}'#10, ''));
  TRuleAssert.Silent(TCompilerDirectiveInvalidRule.Create, Dienst('{$WEAKPACKAGEUNIT ON}'#10 +
    '{$WEAKPACKAGEUNIT OFF}'#10'{$DENYPACKAGEUNIT ON}'#10, ''));
  TRuleAssert.Silent(TCompilerDirectiveInvalidRule.Create, Dienst('{$IFDEF X}'#10'{$WEAKPACKAGEUNIT ON}'#10 +
    '{$ENDIF}'#10'{$DENYPACKAGEUNIT ON}'#10, ''));
end;

procedure TDirectiveRulesTests.InvalidPackageOnlyInUnit;
begin
  // Fall Cm.E2224.
  Assert.AreEqual('{$DESIGNONLY} ist nur in einem Package (.dpk) erlaubt, nicht in einer Unit (wie E2224).',
    InvalidMessage('unit Dienst;'#10'{$DESIGNONLY}'#10'interface'#10'implementation'#10'end.'));
  Assert.AreEqual('{$RUNONLY} ist nur in einem Package (.dpk) erlaubt, nicht in einer Unit (wie E2224).',
    InvalidMessage(Dienst('{$RUNONLY ON}'#10, '')));
  // Im Package gehören sie hin.
  TRuleAssert.Silent(TCompilerDirectiveInvalidRule.Create, 'package Paket;'#10'{$R *.res}'#10'{$DESIGNONLY}'#10 +
    '{$RUNONLY OFF}'#10'requires'#10'  rtl;'#10'contains'#10'  Dienst in ''Dienst.pas'';'#10'end.');
  TRuleAssert.Silent(TCompilerDirectiveInvalidRule.Create, Dienst('{$IFDEF PAKET}'#10'{$DESIGNONLY}'#10 +
    '{$ENDIF}'#10, ''));
end;

procedure TDirectiveRulesTests.InvalidObjTypeName;
begin
  // Fall Cm.E2560.
  Assert.AreEqual('{$OBJTYPENAME} gilt nicht für den Alias TZahl; erlaubt sind nur globale Typen, die kein Alias ' +
    'sind (wie E2560).', InvalidMessage('unit Dienst;'#10'interface'#10'type'#10'  TZahl = Integer;'#10 +
    '  {$OBJTYPENAME TZahl ''Bzahl''}'#10'implementation'#10'end.'));
  // Eigener Typ, Klasse, unbekannter Name: ohne Meldung.
  TRuleAssert.Silent(TCompilerDirectiveInvalidRule.Create, 'unit Dienst;'#10'interface'#10'type'#10 +
    '  TZahl = type Integer;'#10'  TKunde = class'#10'  end;'#10'  {$OBJTYPENAME TZahl ''Bzahl''}'#10 +
    '  {$OBJTYPENAME TKunde ''NKunde''}'#10'  {$OBJTYPENAME TFehlt ''NFehlt''}'#10'implementation'#10'end.');
end;

procedure TDirectiveRulesTests.InvalidCodePage;
begin
  // Fall Cm.E2424: Delphi 13 meldet E1030 für {$CODEPAGE 99999}.
  Assert.AreEqual('99999 ist keine Codepage für {$CODEPAGE} (wie E1030).',
    InvalidMessage('unit Dienst;'#10'{$CODEPAGE 99999}'#10'interface'#10'implementation'#10'end.'));
  TRuleAssert.Silent(TCompilerDirectiveInvalidRule.Create, Dienst('{$CODEPAGE 1252}'#10'{$CODEPAGE 65001}'#10, ''));
end;

procedure TDirectiveRulesTests.InvalidMissingInclude;
var
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  // Fall Cm.E1026: Delphi 13 meldet F1026.
  mSource := Dienst('{$I Cm.Fehlt.E1026.inc}'#10, '');
  mFound := FileFindings(mSource, nil, nil, TRuleUnitAnswer.Missing);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Include-Datei Cm.Fehlt.E1026.inc nicht gefunden (wie F1026).', mFound[0].Message);
  Assert.AreEqual(3, mFound[0].Range.StartPos.Line);
  Assert.AreEqual('Include-Datei Fehlt nicht gefunden (wie F1026).', FileFindings(Dienst('{$INCLUDE ''Fehlt''}'#10,
    ''), nil, nil, TRuleUnitAnswer.Missing)[0].Message);
  // Neben der Unit (auch ohne Endung als .inc), über die Suchpfade oder ohne sichere Aussage: still.
  Assert.AreEqual(0, Integer(Length(FileFindings(Dienst('{$I Da.inc}'#10'{$I Ohne}'#10, ''), ['Da.inc', 'Ohne.inc'],
    ['', ''], TRuleUnitAnswer.Missing))));
  Assert.AreEqual(0, Integer(Length(FileFindings(mSource, nil, nil, TRuleUnitAnswer.Found))));
  Assert.AreEqual(0, Integer(Length(FileFindings(mSource, nil, nil, TRuleUnitAnswer.Unknown))));
  Assert.AreEqual(0, Integer(Length(InvalidFindings(mSource))), 'ohne Dateizugriff keine Aussage');
  // Kurzschalter, Makros und bedingte Zweige.
  Assert.AreEqual(0, Integer(Length(FileFindings(Dienst('{$I+}'#10'{$I-,R+}'#10'{$I %DATE%}'#10 +
    '{$IFDEF FPC}'#10'{$I fpc.inc}'#10'{$ENDIF}'#10, ''), nil, nil, TRuleUnitAnswer.Missing))));
end;

procedure TDirectiveRulesTests.InvalidRecursiveInclude;
var
  mFound: TArray<TRuleFinding>;
begin
  // Fall Cm.E2245: Die Include-Datei bindet sich selbst ein.
  mFound := FileFindings(Dienst('{$I Cm.E2245.inc}'#10, ''), ['Cm.E2245.inc'],
    ['// Bindet sich selbst ein.'#10'{$I Cm.E2245.inc}'#10], TRuleUnitAnswer.Missing);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Rekursive Include-Datei: Cm.E2245.inc → Cm.E2245.inc (wie E2245).', mFound[0].Message);
  // Über eine zweite Datei.
  Assert.AreEqual('Rekursive Include-Datei: A.inc → B.inc → A.inc (wie E2245).',
    FileFindings(Dienst('{$I A.inc}'#10, ''), ['A.inc', 'B.inc'], ['{$I B.inc}', '{$INCLUDE ''A.inc''}'],
    TRuleUnitAnswer.Missing)[0].Message);
  // Mit Wächter, zweimal nacheinander und als Kette ohne Kreis: still.
  Assert.AreEqual(0, Integer(Length(FileFindings(Dienst('{$I A.inc}'#10'{$I A.inc}'#10, ''), ['A.inc', 'B.inc'],
    ['{$IFNDEF A_INC}'#10'{$DEFINE A_INC}'#10'{$I A.inc}'#10'{$ENDIF}'#10'{$I B.inc}', 'const B = 1;'],
    TRuleUnitAnswer.Missing))));
end;

procedure TDirectiveRulesTests.InvalidMissingResource;
var
  mFound: TArray<TRuleFinding>;
begin
  // Fall Cm.W1026: Delphi 13 meldet E1026.
  mFound := FileFindings(Dienst('{$R Cm.Fehlt.W1026.res}'#10, ''), nil, nil, TRuleUnitAnswer.Missing);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Ressourcendatei Cm.Fehlt.W1026.res nicht gefunden (wie E1026).', mFound[0].Message);
  Assert.AreEqual('Ressourcendatei Bilder nicht gefunden (wie E1026).', FileFindings(Dienst(
    '{$RESOURCE ''Bilder''}'#10, ''), nil, nil, TRuleUnitAnswer.Missing)[0].Message);
  // Vorhanden, aus einer .rc erzeugt, Masken, Formulare, Kurzschalter, über die Suchpfade gefunden: still.
  Assert.AreEqual(0, Integer(Length(FileFindings(Dienst('{$R Da.res}'#10'{$R Bilder}'#10'{$R Version.res}'#10 +
    '{$R ''Icons.res'' ''Icons.rc''}'#10'{$R *.res}'#10'{$R *.dfm}'#10'{$R Haupt.dfm}'#10'{$R-}'#10'{$R+,Q-}'#10,
    ''), ['Da.res', 'Bilder.res', 'Version.rc'], ['', '', ''], TRuleUnitAnswer.Missing))));
  Assert.AreEqual(0, Integer(Length(FileFindings(Dienst('{$R Fehlt.res}'#10, ''), nil, nil,
    TRuleUnitAnswer.Found))));
end;

procedure TDirectiveRulesTests.InvalidOptions;
var
  mSource: string;
begin
  mSource := Dienst('{$MESSAGE WARN ''Eigene Warnung''}'#10, '');
  Assert.AreEqual(1, Integer(Length(InvalidFindings(mSource, '', ''))));
  Assert.AreEqual(0, Integer(Length(InvalidFindings(mSource, '{"rules": {"compiler-directive-invalid": "off"}}',
    ''))));
  Assert.AreEqual(0, Integer(Length(InvalidFindings(mSource, '{"rules": {"group:compiler": "off"}}', ''))));
  Assert.AreEqual(0, Integer(Length(InvalidFindings(mSource,
    '{"rules": {"compiler-directive-invalid": {"exclude": ["Alt/*.pas"]}}}', 'Alt/Dienst.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TDirectiveRulesTests);

end.
