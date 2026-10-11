unit Atlas.Common.Rules.Engine.Tests;

// Tests für Prüfregel-Framework: Registrierung, Schweregrad aus der
// Konfiguration, Ausnahmen, Unterdrückung per Kommentar und Korrekturen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleEngineTests = class
  public
    [Test]
    procedure RegistryRejectsDuplicateId;
    [Test]
    procedure RegistryFindsIgnoringCase;
    [Test]
    procedure UsesDefaultSeverity;
    [Test]
    procedure ConfigurationOverridesSeverity;
    [Test]
    procedure OffDisablesRule;
    [Test]
    procedure ExcludeByGlobInRuleOptions;
    [Test]
    procedure ExcludeByUnitNameInRuleOptions;
    [Test]
    procedure GlobalExcludeSkipsFile;
    [Test]
    procedure SuppressesSameLine;
    [Test]
    procedure SuppressesNextLine;
    [Test]
    procedure SuppressionNamesOtherRule;
    [Test]
    procedure SuppressesWithWildcardInBraceComment;
    [Test]
    procedure SuppressesWholeFile;
    [Test]
    procedure SuppressionReasonIsNoId;
    [Test]
    procedure PassesFixesThrough;
    [Test]
    procedure SortsByPosition;
    [Test]
    procedure RuleAssertPositiveAndNegative;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry,
  Atlas.Tests.RuleAssert;

type
  /// <summary>Beispielregel: meldet jeden Bezeichner "Marker".</summary>
  TMarkerRule = class(TInterfacedObject, IRule)
  private
    FId: string;
    FWithFix: Boolean;
  public
    constructor Create(const AId: string = 'marker'; AWithFix: Boolean = False);
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

constructor TMarkerRule.Create(const AId: string; AWithFix: Boolean);
begin
  inherited Create;
  FId := AId;
  FWithFix := AWithFix;
end;

function TMarkerRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(FId, TRuleSeverity.Warning, 'Meldet den Bezeichner Marker');
end;

procedure TMarkerRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Token: TPascalToken;
  Range: TTextRange;
begin
  for Token in AContext.Tree.Tokens do
    if (Token.Kind = TPascalTokenKind.Identifier) and SameText(Token.Text, 'Marker') then
    begin
      Range := TTextRange.Create(Token.StartPos, Token.EndPos);
      if FWithFix then
        AReport.Add(Range, 'Marker gefunden', [TRuleFix.Create('Umbenennen', [TRuleEdit.Create(Range, 'Zeichen')])])
      else
        AReport.Add(Range, 'Marker gefunden');
    end;
end;

const
  Source =
    'unit U;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'begin'#13#10 +
    '  Marker := 1;'#13#10 +
    'end;'#13#10 +
    'end.';

function SourceWith(const ABody: string): string;
begin
  Result :=
    'unit U;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'begin'#13#10 +
    ABody +
    'end;'#13#10 +
    'end.';
end;

{ TRuleEngineTests }

procedure TRuleEngineTests.RegistryRejectsDuplicateId;
var
  Registry: TRuleRegistry;
begin
  Registry := TRuleRegistry.Create;
  try
    Registry.Register(TMarkerRule.Create('a'));
    Assert.WillRaise(
      procedure
      begin
        Registry.Register(TMarkerRule.Create('A'));
      end, ERuleRegistry);
    Assert.AreEqual(1, Integer(Length(Registry.Rules)));
  finally
    Registry.Free;
  end;
end;

procedure TRuleEngineTests.RegistryFindsIgnoringCase;
var
  Registry: TRuleRegistry;
  Rule: IRule;
begin
  Registry := TRuleRegistry.Create;
  try
    Registry.Register(TMarkerRule.Create('empty-except'));
    Assert.IsTrue(Registry.Find('Empty-Except', Rule));
    Assert.IsFalse(Registry.Find('other', Rule));
  finally
    Registry.Free;
  end;
end;

procedure TRuleEngineTests.UsesDefaultSeverity;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TMarkerRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual('marker', Findings[0].RuleId);
  Assert.AreEqual(5, Findings[0].Range.StartPos.Line);
end;

procedure TRuleEngineTests.ConfigurationOverridesSeverity;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TMarkerRule.Create, Source, '{ "rules": { "marker": "error" } }');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
end;

procedure TRuleEngineTests.OffDisablesRule;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create, Source,
    '{ "rules": { "marker": "off" } }'))));
end;

procedure TRuleEngineTests.ExcludeByGlobInRuleOptions;
const
  Config = '{ "rules": { "marker": { "severity": "hint", "exclude": ["Legacy/**"] } } }';
var
  Findings: TArray<TRuleFinding>;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create, Source, Config, 'Legacy\Alt\U.pas'))));
  Findings := TRuleAssert.Findings(TMarkerRule.Create, Source, Config, 'Neu\U.pas');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
end;

procedure TRuleEngineTests.ExcludeByUnitNameInRuleOptions;
const
  Config = '{ "rules": { "marker": { "exclude": ["Alt.Unit"] } } }';
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create, Source, Config, 'Src\Alt.Unit.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create, Source, Config, 'Src\Neu.Unit.pas'))));
end;

procedure TRuleEngineTests.GlobalExcludeSkipsFile;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create, Source,
    '{ "exclude": ["Generated/**"] }', 'Generated\U.pas'))));
end;

procedure TRuleEngineTests.SuppressesSameLine;
begin
  TRuleAssert.Silent(TMarkerRule.Create, SourceWith('  Marker := 1; // lsp-ignore: marker'#13#10));
end;

procedure TRuleEngineTests.SuppressesNextLine;
begin
  TRuleAssert.Reports(TMarkerRule.Create, SourceWith(
    '  // lsp-ignore: marker'#13#10 +
    '  Marker := 1;'#13#10 +
    '  Marker := 2;'#13#10), 1);
end;

procedure TRuleEngineTests.SuppressionNamesOtherRule;
begin
  TRuleAssert.Reports(TMarkerRule.Create, SourceWith('  Marker := 1; // lsp-ignore: empty-except'#13#10));
end;

procedure TRuleEngineTests.SuppressesWithWildcardInBraceComment;
begin
  TRuleAssert.Silent(TMarkerRule.Create, SourceWith('  Marker := 1; { lsp-ignore: other, * }'#13#10));
end;

procedure TRuleEngineTests.SuppressesWholeFile;
begin
  TRuleAssert.Silent(TMarkerRule.Create, '// lsp-ignore-file: marker'#13#10 +
    SourceWith('  Marker := 1;'#13#10'  Marker := 2;'#13#10));
end;

procedure TRuleEngineTests.SuppressionReasonIsNoId;
begin
  // Nach "--" steht eine Begründung; das "*" darin gilt nicht als Kennung (#297).
  TRuleAssert.Reports(TMarkerRule.Create,
    SourceWith('  Marker := 1; // lsp-ignore: other -- gilt nicht für *'#13#10), 1);
  TRuleAssert.Silent(TMarkerRule.Create, SourceWith('  Marker := 1; // lsp-ignore: marker -- Absicht'#13#10));
end;

procedure TRuleEngineTests.PassesFixesThrough;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TMarkerRule.Create('marker', True), Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Umbenennen', Findings[0].Fixes[0].Title);
  Assert.AreEqual('Zeichen', Findings[0].Fixes[0].Edits[0].NewText);
end;

procedure TRuleEngineTests.SortsByPosition;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TMarkerRule.Create, SourceWith(
    '  Marker := 1;'#13#10 +
    '  X := Marker + Marker;'#13#10));
  Assert.AreEqual(3, Integer(Length(Findings)));
  Assert.AreEqual(5, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(6, Findings[1].Range.StartPos.Line);
  Assert.IsTrue(Findings[1].Range.StartPos.Character < Findings[2].Range.StartPos.Character);
end;

procedure TRuleEngineTests.RuleAssertPositiveAndNegative;
begin
  TRuleAssert.Reports(TMarkerRule.Create, Source);
  TRuleAssert.Silent(TMarkerRule.Create, SourceWith('  X := 1;'#13#10));
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleEngineTests);

end.
