unit Atlas.Common.Rules.Builtin.Deprecated.Tests;

// Tests der Regel deprecated-symbol (#38): Aufruf einer veralteten Routine mit
// Grund, platform und experimental, keine Meldung an Deklaration und
// Implementierung, abschaltbar über rules, Tag Deprecated im LSP-Ergebnis.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDeprecatedRulesTests = class
  public
    [Test]
    procedure CallReportsReason;
    [Test]
    procedure PlatformAndExperimental;
    [Test]
    procedure DeclarationAndImplementationAreSilent;
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
  System.JSON,
  System.Generics.Collections,
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
    'const'#10 +
    '  Grenze = 10 platform;'#10 +
    'procedure Alt; deprecated ''Nutze Neu'';'#10 +
    'procedure Ohne; deprecated;'#10 +
    'procedure Neu;'#10 +
    'implementation'#10 +
    'procedure Alt;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Ohne;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Neu;'#10 +
    'begin'#10 +
    'end;'#10 +
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
    '    Neu;'#10 +
    'end;'#10 +
    'end.';

function Run(const ASource, AConfigJson: string; AWithIndex: Boolean): TArray<TRuleFinding>;
var
  Context: TRuleContext;
  Tree: TSyntaxTree;
  Index: ISymbolIndex;
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText(UnitWerkzeug, 'C:\P\Werkzeug.pas', nil));
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

{ TDeprecatedRulesTests }

procedure TDeprecatedRulesTests.CallReportsReason;
var
  Findings: TArray<TRuleFinding>;
  Finding: TRuleFinding;
begin
  Findings := Run(UnitHaupt, '', True);
  Assert.IsTrue(Messages(Findings).Contains('8:2 "Alt" ist veraltet: Nutze Neu|'), Messages(Findings));
  Assert.IsTrue(Messages(Findings).Contains('10:2 "Ohne" ist veraltet|'), Messages(Findings));
  Assert.IsFalse(Messages(Findings).Contains('"Neu"'), Messages(Findings));
  for Finding in Findings do
    if Finding.Message.StartsWith('"Alt"') then
    begin
      Assert.AreEqual(DeprecatedSymbolRuleId, Finding.RuleId);
      Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Finding.Severity));
      Assert.AreEqual(3, Finding.Range.EndPos.Character - Finding.Range.StartPos.Character);
    end;
end;

procedure TDeprecatedRulesTests.PlatformAndExperimental;
var
  Text: string;
begin
  Text := Messages(Run(UnitHaupt, '', True));
  Assert.IsTrue(Text.Contains('6:5 "TAlt" ist experimentell|'), Text);
  Assert.IsTrue(Text.Contains('11:5 "Grenze" ist plattformspezifisch|'), Text);
  Assert.AreEqual(4, Integer(Length(Run(UnitHaupt, '', True))), Text);
end;

procedure TDeprecatedRulesTests.DeclarationAndImplementationAreSilent;
var
  Findings: TArray<TRuleFinding>;
begin
  // Die Unit selbst: weder die Deklaration noch der Kopf der Implementierung zählt.
  Findings := Run(UnitWerkzeug, '', True);
  Assert.AreEqual(0, Integer(Length(Findings)), Messages(Findings));
end;

procedure TDeprecatedRulesTests.SilentWithoutIndex;
begin
  Assert.AreEqual(0, Integer(Length(Run(UnitHaupt, '', False))));
end;

procedure TDeprecatedRulesTests.SwitchableViaRules;
begin
  Assert.AreEqual(0, Integer(Length(Run(UnitHaupt, '{"rules": {"deprecated-symbol": "off"}}', True))));
end;

procedure TDeprecatedRulesTests.DiagnosticCarriesDeprecatedTag;
var
  Finding: TRuleFinding;
  Item: TJSONObject;
begin
  Finding := Default(TRuleFinding);
  Finding.RuleId := DeprecatedSymbolRuleId;
  Finding.Message := '"Alt" ist veraltet: Nutze Neu';
  Item := TLspSyntaxDiagnostics.FindingToJson(Finding);
  try
    Assert.AreEqual('[2]', Item.GetValue('tags').ToJSON);
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
