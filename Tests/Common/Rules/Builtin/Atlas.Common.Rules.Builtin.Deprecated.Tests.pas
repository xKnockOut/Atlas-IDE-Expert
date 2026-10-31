unit Atlas.Common.Rules.Builtin.Deprecated.Tests;

// Tests der Regel deprecated-symbol (#38, #1018): Aufruf einer veralteten
// Routine mit Grund, die Arten deprecated, experimental, platform und library
// samt Option kinds, Schalter {$WARN …} und {$WARNINGS} auch in {$IF}-Zweigen,
// Hinweise im Unit-Kopf (W1004–W1007), Ersatz aus dem Grund bzw. für
// IncludeTrailingBackslash, keine Meldung an Deklaration und Implementierung,
// Symbole der eigenen Datei ohne Index, abschaltbar, Tag Deprecated im
// LSP-Ergebnis nur für deprecated, der Abschnitt automated (W1000, #1373).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDeprecatedRulesTests = class
  public
    [Test]
    procedure CallReportsReason;
    /// <summary>Eigene Deklarationen gleichen Namens (Feld, Aufzählungswert, Konstante, Parameter) sind keine
    /// Verwendung des veralteten Symbols; ein Aufruf daneben bleibt gemeldet.</summary>
    [Test]
    procedure DeclarationsOfSameNameAreNoUse;
    [Test]
    procedure KindsOption;
    [Test]
    procedure KindsOptionIsValidated;
    [Test]
    procedure WarnSwitches;
    [Test]
    procedure WarnSwitchesInConditionalBranches;
    [Test]
    procedure DeprecatedUnits;
    [Test]
    procedure OnlyTheChosenOverload;
    [Test]
    procedure ReplacementFromKnownRoutine;
    [Test]
    procedure ReplacementMustBeUnique;
    [Test]
    procedure DeclarationAndImplementationAreSilent;
    [Test]
    procedure OwnUnitWithoutIndex;
    [Test]
    procedure AutomatedSection;
    [Test]
    procedure SilentWithoutIndex;
    [Test]
    procedure SwitchableViaRules;
    [Test]
    procedure DiagnosticCarriesDeprecatedTag;
    [Test]
    procedure RuleIsRegistered;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.Deprecated,
  Atlas.Common.Lsp.SyntaxDiagnostics;

const
  UnitWerkzeug =
    'unit Werkzeug;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TAlt = class'#10 +
    '  end experimental;'#10 +
    '  TListe = class'#10 +
    '    procedure Anhaengen; deprecated ''Use Add'';'#10 +
    '    procedure Add;'#10 +
    '  end;'#10 +
    'const'#10 +
    '  Grenze = 10 platform;'#10 +
    'procedure Alt; deprecated ''Nutze Neu'';'#10 +
    'procedure Ohne; deprecated;'#10 +
    'procedure Zwei; deprecated ''Neu oder Ohne'';'#10 +
    'procedure Typisch; deprecated ''Use TAlt'';'#10 +
    'procedure Fern; deprecated ''Use IncludeTrailingPathDelimiter'';'#10 +
    'procedure Bib; library;'#10 +
    'procedure Neu;'#10 +
    'implementation'#10 +
    'procedure TListe.Anhaengen;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TListe.Add;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Alt;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Ohne;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Zwei;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Typisch;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Fern;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Bib;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Neu;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  UnitSysUtils =
    'unit System.SysUtils;'#10 +
    'interface'#10 +
    'function IncludeTrailingBackslash(const S: string): string; platform;'#10 +
    'function IncludeTrailingPathDelimiter(const S: string): string;'#10 +
    'function FileAge(const FileName: string): LongInt; overload; deprecated;'#10 +
    'function FileAge(const FileName: string; out FileDateTime: TDateTime;'#10 +
    '  FollowLink: Boolean = True): Boolean; overload;'#10 +
    'implementation'#10 +
    'function IncludeTrailingBackslash(const S: string): string;'#10 +
    'begin'#10 +
    '  Result := S;'#10 +
    'end;'#10 +
    'function IncludeTrailingPathDelimiter(const S: string): string;'#10 +
    'begin'#10 +
    '  Result := S;'#10 +
    'end;'#10 +
    'end.';

  // Wie die RTL: TDateTime ist ein eigener Typ über Double.
  UnitSystem =
    'unit System;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TDateTime = type Double;'#10 +
    'implementation'#10 +
    'end.';

  UnitAltlast =
    'unit Werk.Altlast deprecated ''Nutze Werkzeug'';'#10 +
    'interface'#10 +
    'implementation'#10 +
    'end.';

  UnitWindows =
    'unit Werk.Windows platform experimental;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'end.';

  UnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Werkzeug;'#10 +
    'implementation'#10 +
    'procedure Lauf;'#10 +
    'var'#10 +
    '  X: TAlt;'#10 +
    'begin'#10 +
    '  Alt;'#10 +
    '  Neu;'#10 +
    '  Ohne;'#10 +
    '  if Grenze > 1 then'#10 +
    '    Bib;'#10 +
    'end;'#10 +
    'end.';

function NewIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText(UnitWerkzeug, 'C:\P\Werkzeug.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText(UnitSysUtils, 'C:\RTL\System.SysUtils.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText(UnitSystem, 'C:\RTL\System.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText(UnitAltlast, 'C:\P\Werk.Altlast.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText(UnitWindows, 'C:\P\Werk.Windows.pas', nil));
end;

function Run(const ASource, AConfigJson: string; AWithIndex: Boolean): TArray<TRuleFinding>;
var
  Context: TRuleContext;
  Tree: TSyntaxTree;
  Index: ISymbolIndex;
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Index := NewIndex;
  if AConfigJson = '' then
    Settings := TServerSettings.Default
  else
    Settings := TConfigurationParser.Parse(AConfigJson, Issues);
  Tree := TPascalParser.Parse(ASource);
  try
    Context := Default(TRuleContext);
    Context.RelativePath := 'Haupt.pas';
    Context.UnitName := 'Haupt';
    Context.Text := ASource;
    Context.Tree := Tree;
    if AWithIndex then
      Context.Index := Index;
    Result := TRuleEngine.Run([IRule(TDeprecatedSymbolRule.Create)], Settings, Context);
  finally
    Tree.Free;
  end;
end;

function Messages(const AFindings: TArray<TRuleFinding>): string;
var
  Finding: TRuleFinding;
begin
  Result := '';
  for Finding in AFindings do
    Result := Result + Format('%d:%d %s|', [Finding.Range.StartPos.Line, Finding.Range.StartPos.Character,
      Finding.Message]);
end;

/// <summary>Haupt mit uses AUses und dem Rumpf ABody in Lauf.</summary>
function Haupt(const AUses, ABody: string): string;
begin
  Result := 'unit Haupt;'#10'interface'#10'uses ' + AUses + ';'#10'implementation'#10 +
    'procedure Lauf;'#10'var'#10'  L: TListe;'#10'  S: string;'#10'begin'#10 + ABody + 'end;'#10'end.';
end;

function KindsConfig(const AKinds: string): string;
begin
  Result := '{"rules": {"deprecated-symbol": {"severity": "warning", "kinds": [' + AKinds + ']}}}';
end;

{ TDeprecatedRulesTests }

procedure TDeprecatedRulesTests.DeclarationsOfSameNameAreNoUse;
const
  Source =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Werkzeug;'#10 +
    'type'#10 +
    '  TStand = record'#10 +
    '    Alt: Integer;'#10 +
    '  end;'#10 +
    '  TArt = (Eins, Alt);'#10 +
    'implementation'#10 +
    'procedure Lauf(Ohne: Integer);'#10 +
    'begin'#10 +
    '  Neu;'#10 +
    'end;'#10 +
    'procedure Aufruf;'#10 +
    'begin'#10 +
    '  Werkzeug.Alt;'#10 +
    'end;'#10 +
    'end.';
begin
  // Vorher meldete die Regel das Feld (Zeile 5), den Aufzählungswert (7) und den Parameter (9).
  Assert.AreEqual('15:11 Alt ist deprecated: Nutze Neu (wie W1000).|', Messages(Run(Source, '', True)));
end;

procedure TDeprecatedRulesTests.CallReportsReason;
var
  Findings: TArray<TRuleFinding>;
  Finding: TRuleFinding;
  Text: string;
begin
  // Wie dcc ab Werk alle vier Arten (#1378).
  Findings := Run(UnitHaupt, '', True);
  Text := Messages(Findings);
  Assert.AreEqual('6:5 TAlt ist experimental (wie W1003).|8:2 Alt ist deprecated: Nutze Neu (wie W1000).|' +
    '10:2 Ohne ist deprecated (wie W1000).|11:5 Grenze ist platform (wie W1002).|12:4 Bib ist library (wie W1001).|',
    Text);
  for Finding in Findings do
    if Finding.Message.StartsWith('Alt ') then
    begin
      Assert.AreEqual(DeprecatedSymbolRuleId, Finding.RuleId);
      Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Finding.Severity));
      Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Finding.Confidence));
      Assert.AreEqual(3, Finding.Range.EndPos.Character - Finding.Range.StartPos.Character);
      // Der Grund nennt Neu, und Neu ist hier sichtbar.
      Assert.AreEqual(1, Integer(Length(Finding.Fixes)));
      Assert.AreEqual('Durch Neu ersetzen', Finding.Fixes[0].Title);
      Assert.AreEqual('Neu', Finding.Fixes[0].Edits[0].NewText);
    end
    else
      Assert.AreEqual(0, Integer(Length(Finding.Fixes)), Finding.Message);
  // Methode: Ersatz im selben Typ.
  Findings := Run(Haupt('Werkzeug', '  L.Anhaengen;'#10), '', True);
  Assert.AreEqual('9:4 Anhaengen ist deprecated: Use Add (wie W1000).|', Messages(Findings));
  Assert.AreEqual('Add', Findings[0].Fixes[0].Edits[0].NewText);
end;

procedure TDeprecatedRulesTests.KindsOption;
begin
  Assert.AreEqual('11:5 Grenze ist platform (wie W1002).|',
    Messages(Run(UnitHaupt, KindsConfig('"platform"'), True)));
  Assert.AreEqual('12:4 Bib ist library (wie W1001).|', Messages(Run(UnitHaupt, KindsConfig('"library"'), True)));
  Assert.AreEqual('8:2 Alt ist deprecated: Nutze Neu (wie W1000).|10:2 Ohne ist deprecated (wie W1000).|',
    Messages(Run(UnitHaupt, KindsConfig('"deprecated"'), True)));
  Assert.AreEqual(0, Integer(Length(Run(UnitHaupt, KindsConfig(''), True))));
end;

procedure TDeprecatedRulesTests.KindsOptionIsValidated;
var
  Issues: TArray<TConfigurationIssue>;
begin
  TConfigurationParser.Parse(KindsConfig('"platfrom"'), Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual('"kinds" darf nur "deprecated", "experimental", "platform" und "library" enthalten',
    Issues[0].Message);
  TConfigurationParser.Parse(KindsConfig('"platform", "library"'), Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Issues := nil;
end;

procedure TDeprecatedRulesTests.WarnSwitches;
var
  Findings: TArray<TRuleFinding>;
begin
  // Aus, wieder an, als Fehler, Standard; WARNINGS OFF schaltet alles ab.
  Findings := Run(Haupt('Werkzeug',
    '  {$WARN SYMBOL_DEPRECATED OFF}'#10 +
    '  Alt;'#10 +
    '  {$WARN SYMBOL_DEPRECATED ON}'#10 +
    '  Ohne;'#10 +
    '  {$WARN SYMBOL_DEPRECATED ERROR}'#10 +
    '  Alt;'#10 +
    '  {$WARN SYMBOL_PLATFORM ON}'#10 +
    '  S := IntToStr(Grenze);'#10 +
    '  {$WARN SYMBOL_PLATFORM DEFAULT}'#10 +
    '  S := IntToStr(Grenze);'#10 +
    '  {$WARNINGS OFF}'#10 +
    '  Ohne;'#10 +
    '  {$WARNINGS ON}'#10 +
    '  (*$WARN SYMBOL_DEPRECATED OFF*)'#10 +
    '  Ohne;'#10), '', True);
  Assert.AreEqual('12:2 Ohne ist deprecated (wie W1000).|14:2 Alt ist deprecated: Nutze Neu (wie W1000).|' +
    '16:16 Grenze ist platform (wie W1002).|18:16 Grenze ist platform (wie W1002).|', Messages(Findings));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[1].Severity));
end;

procedure TDeprecatedRulesTests.WarnSwitchesInConditionalBranches;
begin
  // Der Schalter im selben Zweig gilt, der im anderen Zweig nicht; danach ist der Zustand nicht sicher.
  Assert.AreEqual('13:2 Ohne ist deprecated (wie W1000).|',
    Messages(Run(Haupt('Werkzeug',
    '  {$IFDEF DEBUG}'#10 +
    '  {$WARN SYMBOL_DEPRECATED OFF}'#10 +
    '  Alt;'#10 +
    '  {$ELSE}'#10 +
    '  Ohne;'#10 +
    '  {$ENDIF}'#10 +
    '  Alt;'#10), '', True)));
end;

procedure TDeprecatedRulesTests.OnlyTheChosenOverload;
const
  Source =
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'uses System.SysUtils;'#13#10 +
    'type'#13#10 +
    '  TDatei = class'#13#10 +
    '    function Stempel(const AFileName: string; out AStamp: Int64): Boolean;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'function TDatei.Stempel(const AFileName: string; out AStamp: Int64): Boolean;'#13#10 +
    'var'#13#10 +
    '  Age: TDateTime;'#13#10 +
    'begin'#13#10 +
    '  Result := FileAge(AFileName, Age);'#13#10 +
    '  AStamp := FileAge(AFileName);'#13#10 +
    '  Result := FileAge(AFileName, Age, False);'#13#10 +
    'end;'#13#10 +
    'end.';
begin
  // Nur die Überladung FileAge(string): LongInt ist deprecated; gemeldet wird nur der Aufruf, der sie wählt.
  Assert.AreEqual('13:12 FileAge ist deprecated (wie W1000).|', Messages(Run(Source, '', True)));
end;

procedure TDeprecatedRulesTests.DeprecatedUnits;
var
  Source: string;
  UnitIndex: TUnitIndex;
begin
  UnitIndex := TIndexExtractor.ExtractText(UnitAltlast, 'C:\P\Werk.Altlast.pas', nil);
  Assert.AreEqual('deprecated', String.Join(',', UnitIndex.Directives));
  Assert.AreEqual('Nutze Werkzeug', UnitIndex.DeprecatedText);
  // Der Unit-Name selbst ist kein Hinweis: Werk.Deprecated ist nicht deprecated.
  UnitIndex := TIndexExtractor.ExtractText('unit Werk.Deprecated;'#10'interface'#10'implementation'#10'end.',
    'C:\P\Werk.Deprecated.pas', nil);
  Assert.AreEqual('', String.Join(',', UnitIndex.Directives));
  UnitIndex := TIndexExtractor.ExtractText('unit Werk.Experimental platform;'#10'interface'#10'implementation'#10'end.',
    'C:\P\Werk.Experimental.pas', nil);
  Assert.AreEqual('platform', String.Join(',', UnitIndex.Directives));
  Source := Haupt('Werkzeug, Werk.Altlast, Werk.Windows', '');
  Assert.AreEqual('2:15 Unit Werk.Altlast ist deprecated: Nutze Werkzeug (wie W1006).|' +
    '2:29 Unit Werk.Windows ist experimental (wie W1007).|2:29 Unit Werk.Windows ist platform (wie W1005).|',
    Messages(Run(Source, '', True)));
  Assert.AreEqual('2:29 Unit Werk.Windows ist platform (wie W1005).|',
    Messages(Run(Source, KindsConfig('"platform"'), True)));
  Assert.AreEqual(0, Integer(Length(Run(ReplaceStr(Source, 'uses ', '{$WARN UNIT_DEPRECATED OFF}'#10 +
    '{$WARN UNIT_EXPERIMENTAL OFF}'#10'{$WARN UNIT_PLATFORM OFF}'#10'uses '), '', True))));
end;

procedure TDeprecatedRulesTests.ReplacementFromKnownRoutine;
var
  Findings: TArray<TRuleFinding>;
begin
  // Das Beispiel aus #1018: platform ohne Grund, Ersatz aus der Tabelle der RTL.
  Findings := Run(Haupt('System.SysUtils', '  S := IncludeTrailingBackslash(S) + ''Name'';'#10), KindsConfig('"platform"'),
    True);
  Assert.AreEqual('9:7 IncludeTrailingBackslash ist platform; besser IncludeTrailingPathDelimiter (wie W1002).|',
    Messages(Findings));
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('IncludeTrailingPathDelimiter', Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(7, Findings[0].Fixes[0].Edits[0].Range.StartPos.Character);
  Assert.AreEqual(31, Findings[0].Fixes[0].Edits[0].Range.EndPos.Character);
  // Die korrigierte Form ist still.
  Assert.AreEqual(0, Integer(Length(Run(Haupt('System.SysUtils',
    '  S := IncludeTrailingPathDelimiter(S) + ''Name'';'#10), KindsConfig('"platform"'), True))));
end;

procedure TDeprecatedRulesTests.ReplacementMustBeUnique;
var
  Findings: TArray<TRuleFinding>;
begin
  // Zwei passende Namen im Grund bzw. ein Typ als Ersatz einer Routine: keine Korrektur.
  Findings := Run(Haupt('Werkzeug', '  Zwei;'#10'  Typisch;'#10), '', True);
  Assert.AreEqual('9:2 Zwei ist deprecated: Neu oder Ohne (wie W1000).|' +
    '10:2 Typisch ist deprecated: Use TAlt (wie W1000).|', Messages(Findings));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual(0, Integer(Length(Findings[1].Fixes)));
  // Ersatz, der an der Stelle nicht sichtbar ist (System.SysUtils fehlt in uses): Meldung ohne Korrektur.
  Findings := Run(Haupt('Werkzeug', '  Fern;'#10), '', True);
  Assert.AreEqual('9:2 Fern ist deprecated: Use IncludeTrailingPathDelimiter (wie W1000).|', Messages(Findings));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TDeprecatedRulesTests.DeclarationAndImplementationAreSilent;
var
  Findings: TArray<TRuleFinding>;
begin
  // Die Unit selbst: weder die Deklaration noch der Kopf der Implementierung zählt.
  Findings := Run(UnitWerkzeug, '', True);
  Assert.AreEqual(0, Integer(Length(Findings)), Messages(Findings));
end;

procedure TDeprecatedRulesTests.OwnUnitWithoutIndex;
const
  Source =
    'unit Haupt;'#10 +
    'interface'#10 +
    'procedure Alt; deprecated ''Nutze Neu'';'#10 +
    'procedure Neu;'#10 +
    'implementation'#10 +
    'procedure Alt;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Neu;'#10 +
    'begin'#10 +
    '  Alt;'#10 +
    'end;'#10 +
    'end.';
var
  Findings: TArray<TRuleFinding>;
begin
  // Wie der Compiler auch in derselben Unit; der Linter hat keinen Projektindex.
  Findings := Run(Source, '', False);
  Assert.AreEqual('10:2 Alt ist deprecated: Nutze Neu (wie W1000).|', Messages(Findings));
  Assert.AreEqual('Neu', Findings[0].Fixes[0].Edits[0].NewText);
end;

procedure TDeprecatedRulesTests.AutomatedSection;
const
  cSource =
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TAuto = class'#10 +
    '  automated'#10 +
    '    procedure Machen;'#10 +
    '  end;'#10 +
    '  {$WARN SYMBOL_DEPRECATED OFF}'#10 +
    '  TStill = class'#10 +
    '  automated'#10 +
    '  end;'#10 +
    '  {$WARN SYMBOL_DEPRECATED ON}'#10 +
    '  TRecord = record'#10 +
    '    automated: Integer;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TAuto.Machen;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';
var
  mFindings: TArray<TRuleFinding>;
begin
  // Wie dcc: „Symbol 'AUTOMATED' ist veraltet“ (Fälle Cm.E2175 … Cm.E2185), auch ohne Projektindex.
  mFindings := Run(cSource, '', False);
  Assert.AreEqual('4:2 automated ist deprecated (wie W1000).|', Messages(mFindings));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual(4, mFindings[0].Range.EndPos.Line);
  Assert.AreEqual(11, mFindings[0].Range.EndPos.Character);
  Assert.AreEqual(0, Integer(Length(Run(cSource, KindsConfig('"platform"'), False))));
end;

procedure TDeprecatedRulesTests.SilentWithoutIndex;
begin
  // Werkzeug ist ohne Index unbekannt.
  Assert.AreEqual(0, Integer(Length(Run(UnitHaupt, '', False))));
end;

procedure TDeprecatedRulesTests.SwitchableViaRules;
begin
  Assert.AreEqual(0, Integer(Length(Run(UnitHaupt, '{"rules": {"deprecated-symbol": "off"}}', True))));
  Assert.AreEqual(0, Integer(Length(Run(UnitHaupt, '{"rules": {"group:compiler": "off"}}', True))));
  Assert.AreEqual(0, Integer(Length(Run(UnitHaupt,
    '{"rules": {"deprecated-symbol": {"severity": "warning", "exclude": ["Haupt.pas"]}}}', True))));
end;

procedure TDeprecatedRulesTests.DiagnosticCarriesDeprecatedTag;
var
  Finding: TRuleFinding;
  Item: TJSONObject;
begin
  Finding := Default(TRuleFinding);
  Finding.RuleId := DeprecatedSymbolRuleId;
  Finding.Message := 'Alt ist deprecated: Nutze Neu (wie W1000).';
  Item := TLspSyntaxDiagnostics.FindingToJson(Finding);
  try
    Assert.AreEqual('[2]', Item.GetValue('tags').ToJSON);
  finally
    Item.Free;
  end;
  // platform ist nicht veraltet und wird nicht durchgestrichen.
  Finding.Message := 'Grenze ist platform (wie W1002).';
  Item := TLspSyntaxDiagnostics.FindingToJson(Finding);
  try
    Assert.IsNull(Item.GetValue('tags'));
  finally
    Item.Free;
  end;
  Finding.RuleId := 'unused-variable';
  Item := TLspSyntaxDiagnostics.FindingToJson(Finding);
  try
    Assert.IsNull(Item.GetValue('tags'));
  finally
    Item.Free;
  end;
end;

procedure TDeprecatedRulesTests.RuleIsRegistered;
var
  Rule: IRule;
  Found: Boolean;
begin
  Found := False;
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id = DeprecatedSymbolRuleId then
      Found := True;
  Assert.IsTrue(Found);
end;

initialization
  TDUnitX.RegisterTestFixture(TDeprecatedRulesTests);

end.
