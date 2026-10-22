unit Atlas.Common.Rules.Builtin.Directives.Tests;

// Tests der Regeln für Compiler-Direktiven (#989): offene und überzählige
// bedingte Direktiven, Symbole, unbekannte Direktiven und {$WARN}-Bezeichner,
// {$PUSHOPT}/{$POPOPT}, {$ALIGN} und die Einstellungen.

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
    procedure UnbalancedOptionStack;
    [Test]
    procedure UnbalancedAlign;
    [Test]
    procedure UnbalancedOptions;
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
  Assert.AreEqual('Unbekannte Direktive {$MODE} (wie W1030).', OnlyMessage(Dienst('{$MODE DELPHI}'#10, '')));
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
  Assert.AreEqual('Unbekannte Direktive {$OPTIMISATION}; gemeint ist wohl {$OPTIMIZATION} (wie W1030).',
    Found[0].Message);
  Assert.AreEqual('Tippfehler korrigieren: {$OPTIMIZATION}', Found[0].Fixes[0].Title);
  Assert.AreEqual(Dienst('', '  {$OPTIMIZATION ON}'#10), ApplyFix(Source, Found[0].Fixes[0]));
  // Kleinschreibung bleibt.
  Source := Dienst('', '  {$optimisation on}'#10);
  Assert.AreEqual(Dienst('', '  {$optimization on}'#10), ApplyFix(Source, Findings(Source)[0].Fixes[0]));
  Assert.AreEqual('Unbekannte Direktive {$FOOBAR} (wie W1030).', OnlyMessage(Dienst('{$FOOBAR}'#10, '')));
  // {$WARN} mit unbekanntem Bezeichner.
  Assert.AreEqual('Unbekannte Warnung UNKOWN in {$WARN} (wie W1030).',
    OnlyMessage(Dienst('{$WARN UNKOWN OFF}'#10, '')));
  Source := Dienst('{$WARN SYMBOL_PLATFROM OFF}'#10, '');
  Found := Findings(Source);
  Assert.AreEqual('Unbekannte Warnung SYMBOL_PLATFROM in {$WARN}; gemeint ist wohl SYMBOL_PLATFORM (wie W1030).',
    Found[0].Message);
  Assert.AreEqual(Dienst('{$WARN SYMBOL_PLATFORM OFF}'#10, ''), ApplyFix(Source, Found[0].Fixes[0]));
  // Ein Tippfehler in {$IFDEF} lässt das {$ENDIF} ohne Gegenstück.
  Found := Findings(Dienst('{$IFDEFF DEBUG}'#10'{$ENDIF}'#10, ''));
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('Unbekannte Direktive {$IFDEFF}; gemeint ist wohl {$IFDEF} (wie W1030).', Found[0].Message);
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

initialization
  TDUnitX.RegisterTestFixture(TDirectiveRulesTests);

end.
