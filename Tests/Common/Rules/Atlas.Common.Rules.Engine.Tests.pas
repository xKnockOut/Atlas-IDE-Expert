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
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
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
    procedure GroupSwitchDisablesAllRulesOfGroup;
    [Test]
    procedure CompilerGroupTypeLevel;
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
    procedure UnknownRuleIdWithSuggestion;
    [Test]
    procedure UnknownRuleIdWithoutSuggestion;
    [Test]
    procedure UnknownRuleIdCanBeSwitchedOff;
    [Test]
    procedure SuggestsClosestRuleId;
    [Test]
    procedure PassesFixesThrough;
    [Test]
    procedure SortsByPosition;
    [Test]
    procedure RuleAssertPositiveAndNegative;
    /// <summary>Abbruch wirkt vor der nächsten Regel (Diagnoselog 15.10.2026).</summary>
    [Test]
    procedure CancelledStopsBeforeNextRule;
    [Test]
    procedure SlowRuleNamedInDiagnostics;
    /// <summary>Alle Regeln eines Laufs teilen einen Ableitungscache (Review P-03).</summary>
    [Test]
    procedure RunSharesDerivedCacheBetweenRules;
    [Test]
    procedure RunClearsOwnCache;
    [Test]
    procedure RunKeepsCallerCache;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Suppressions,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Diagnostics.RequestScope,
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

var
  // Zähler für TProbe: erzeugte und freigegebene Instanzen.
  ProbeCreated: Integer;
  ProbeFreed: Integer;

type
  /// <summary>Abgeleiteter Wert im Cache; zählt Erzeugung und Freigabe.</summary>
  TProbe = class
  public
    constructor Create;
    destructor Destroy; override;
  end;

  /// <summary>Regel ohne Treffer, die den Wert "test.probe" aus dem Ableitungscache holt.</summary>
  TProbeRule = class(TInterfacedObject, IRule)
  private
    FId: string;
  public
    constructor Create(const AId: string);
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

constructor TProbe.Create;
begin
  inherited Create;
  Inc(ProbeCreated);
end;

destructor TProbe.Destroy;
begin
  Inc(ProbeFreed);
  inherited Destroy;
end;

constructor TProbeRule.Create(const AId: string);
begin
  inherited Create;
  FId := AId;
end;

function TProbeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(FId, TRuleSeverity.Warning, 'Holt einen abgeleiteten Wert');
end;

procedure TProbeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Cache: IRuleDerivedCache;
begin
  Cache := TRuleDerived.Open(AContext);
  TRuleDerived.Get<TProbe>(Cache, 'test.probe',
    function: TProbe
    begin
      Result := TProbe.Create;
    end);
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

procedure TRuleEngineTests.WarmUpFirstUse;
begin
  CancelledStopsBeforeNextRule;
end;

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

procedure TRuleEngineTests.GroupSwitchDisablesAllRulesOfGroup;
begin
  // Hauptschalter der Gruppe (#909): empty-except gehört zu „Exceptions“.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create('empty-except'), Source,
    '{ "rules": { "group:exceptions": "off" } }'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create('empty-except'), Source,
    '{ "rules": { "empty-except": "error", "group:exceptions": "off" } }'))), 'auch einzeln eingestellte');
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create('empty-except'), Source,
    '{ "rules": { "group:threads": "off" } }'))), 'andere Gruppe');
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create('empty-except'), Source,
    '{ "rules": { "group:exceptions": "warning" } }'))), 'nur off schaltet ab');
  // Regeln außerhalb des Katalogs haben keine Gruppe.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create, Source,
    '{ "rules": { "group:exceptions": "off" } }'))));
  Assert.IsTrue(TRuleEngine.GroupOff('EMPTY-EXCEPT', TServerSettings.Default) = False);
end;

procedure TRuleEngineTests.CompilerGroupTypeLevel;
var
  Issues: TArray<TConfigurationIssue>;
begin
  // Gruppe „Compiler vorab“ (#1024): argument-count-mismatch hat Stufe T, comparison-as-statement Stufe A.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create('argument-count-mismatch'), Source,
    '{ "rules": { "group:compiler": { "typeLevel": "off" } } }'))), 'Stufe T aus');
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create('comparison-as-statement'), Source,
    '{ "rules": { "group:compiler": { "typeLevel": "off" } } }'))), 'Stufe A bleibt');
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create('argument-count-mismatch'), Source,
    '{ "rules": { "group:compiler": { "typeLevel": "certain" } } }'))), 'certain');
  // Hauptschalter auch als Objekt.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create('comparison-as-statement'), Source,
    '{ "rules": { "group:compiler": { "severity": "off", "typeLevel": "certain" } } }'))), 'Objekt mit off');
  // Andere Gruppen kennen typeLevel nicht; ohne Katalog keine Stufe.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create, Source,
    '{ "rules": { "group:compiler": { "typeLevel": "off" } } }'))));
  TConfigurationParser.Parse('{"rules": {"group:compiler": {"typeLevel": "nie"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual('"typeLevel" muss "certain" oder "off" sein', Issues[0].Message);
  TConfigurationParser.Parse('{"rules": {"group:compiler": {"typeLevel": "off"}}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
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
  TRuleAssert.Silent(TMarkerRule.Create, SourceWith('  Marker := 1; { lsp-ignore: empty-except, * }'#13#10));
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
    SourceWith('  Marker := 1; // lsp-ignore: empty-except -- gilt nicht für *'#13#10), 1);
  TRuleAssert.Silent(TMarkerRule.Create, SourceWith('  Marker := 1; // lsp-ignore: marker -- Absicht'#13#10));
end;

procedure TRuleEngineTests.UnknownRuleIdWithSuggestion;
const
  Line = '  Marker := 1; // lsp-ignore: empty-exept, marker';
var
  Findings: TArray<TRuleFinding>;
begin
  // Abnahme #41: Tippfehler ergibt unknown-rule-id mit Vorschlag, aber keine unused-suppression.
  Findings := TRuleAssert.Findings(TMarkerRule.Create, SourceWith(Line + #13#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(UnknownRuleIdRuleId, Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Assert.IsTrue(Pos('"empty-except"', Findings[0].Message) > 0, Findings[0].Message);
  // Genau die Kennung ist markiert, die Korrektur ersetzt nur sie.
  Assert.AreEqual(5, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(Pos('empty-exept', Line) - 1, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(Pos('empty-exept', Line) - 1 + Length('empty-exept'), Findings[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('empty-except', Findings[0].Fixes[0].Edits[0].NewText);
  // Allein in der Zeile und ohne Treffer darunter: weiterhin keine unused-suppression daneben.
  Findings := TRuleAssert.Findings(TMarkerRule.Create, SourceWith('  // lsp-ignore: empty-exept'#13#10'  X := 1;'#13#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(UnknownRuleIdRuleId, Findings[0].RuleId);
  // Auch in { } und mit Begründung; die Begründung wird nie gelesen.
  Findings := TRuleAssert.Findings(TMarkerRule.Create,
    SourceWith('  Marker := 1; { lsp-ignore: marker -- empty-exept }'#13#10));
  Assert.AreEqual(0, Integer(Length(Findings)));
end;

procedure TRuleEngineTests.UnknownRuleIdWithoutSuggestion;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TMarkerRule.Create, SourceWith('  X := 1; // lsp-ignore: voellig-anders'#13#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(UnknownRuleIdRuleId, Findings[0].RuleId);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  Assert.IsTrue(Pos('wirkt nicht', Findings[0].Message) > 0, Findings[0].Message);
  // Kennungen der übergebenen Regeln, des Katalogs und "*" sind bekannt.
  TRuleAssert.Silent(TMarkerRule.Create, SourceWith('  Marker := 1; // lsp-ignore: marker, *, with-statement'#13#10));
end;

procedure TRuleEngineTests.UnknownRuleIdCanBeSwitchedOff;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create,
    SourceWith('  X := 1; // lsp-ignore: empty-exept'#13#10), '{"rules": {"unknown-rule-id": "off"}}'))));
end;

procedure TRuleEngineTests.SuggestsClosestRuleId;
begin
  Assert.AreEqual('empty-except', TSuppressions.Suggest('empty-exept', ['with-statement', 'empty-except']));
  Assert.AreEqual('empty-except', TSuppressions.Suggest('EMPTY-EXCEPT', ['empty-except']));
  Assert.AreEqual('', TSuppressions.Suggest('voellig-anders', ['with-statement', 'empty-except']));
  // Kurze Kennungen: höchstens ein Zeichen daneben.
  Assert.AreEqual('', TSuppressions.Suggest('abc', ['xyz']));
  Assert.AreEqual('abd', TSuppressions.Suggest('abc', ['abd']));
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

procedure TRuleEngineTests.CancelledStopsBeforeNextRule;
var
  Stop: Boolean;
  Runs: Integer;
  Context: TRuleContext;
  Tree: TSyntaxTree;
begin
  Stop := False;
  Runs := 0;
  Tree := TPascalParser.Parse(Source);
  try
    Context := Default(TRuleContext);
    Context.Text := Source;
    Context.Tree := Tree;
    Context.Cancelled :=
      function: Boolean
      begin
        Result := Stop;
      end;
    Assert.WillRaise(
      procedure
      begin
        TRuleEngine.Run([
          TCallbackRule.Create('erste',
            procedure
            begin
              Inc(Runs);
              Stop := True;
            end),
          TCallbackRule.Create('zweite',
            procedure
            begin
              Inc(Runs);
            end)], TServerSettings.Default, Context);
      end, ERuleCheckCancelled);
    Assert.AreEqual(1, Runs);
  finally
    // Context hängt in der Closure und hält über Cancelled die Closure selbst: Kreis lösen.
    Context.Cancelled := nil;
    Tree.Free;
  end;
end;

procedure TRuleEngineTests.SlowRuleNamedInDiagnostics;
var
  Context: TRuleContext;
  Tree: TSyntaxTree;
  Notes: TRequestNotes;
  Joined, Note: string;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Context := Default(TRuleContext);
    Context.Text := Source;
    Context.Tree := Tree;
    TRequestDiagnostics.Open;
    try
      TRuleEngine.Run([
        TCallbackRule.Create('schnell',
          procedure
          begin
          end),
        TCallbackRule.Create('langsam',
          procedure
          begin
            Sleep(TRuleEngine.SlowRuleMs + 50);
          end)], TServerSettings.Default, Context);
    finally
      Notes := TRequestDiagnostics.Close;
    end;
  finally
    Tree.Free;
  end;
  Joined := '';
  for Note in Notes.Notes do
    Joined := Joined + Note + ' ';
  Assert.Contains(Joined, 'slowRule=langsam ');
  Assert.Contains(Joined, 'slowRuleMs=');
  Assert.DoesNotContain(Joined, 'schnell');
end;

procedure TRuleEngineTests.RunSharesDerivedCacheBetweenRules;
var
  Context: TRuleContext;
  Tree: TSyntaxTree;
begin
  ProbeCreated := 0;
  ProbeFreed := 0;
  Tree := TPascalParser.Parse(Source);
  try
    Context := Default(TRuleContext);
    Context.Text := Source;
    Context.Tree := Tree;
    TRuleEngine.Run([TProbeRule.Create('probe-a'), TProbeRule.Create('probe-b'), TProbeRule.Create('probe-c')],
      TServerSettings.Default, Context);
  finally
    Tree.Free;
  end;
  Assert.AreEqual(1, ProbeCreated, 'einmal je Lauf erzeugt');
end;

procedure TRuleEngineTests.RunClearsOwnCache;
var
  Context: TRuleContext;
  Tree: TSyntaxTree;
begin
  ProbeCreated := 0;
  ProbeFreed := 0;
  Tree := TPascalParser.Parse(Source);
  try
    Context := Default(TRuleContext);
    Context.Text := Source;
    Context.Tree := Tree;
    TRuleEngine.Run([TProbeRule.Create('probe-a')], TServerSettings.Default, Context);
    // Noch vor dem Baum freigegeben: abgeleitete Objekte zeigen in den Baum.
    Assert.AreEqual(1, ProbeFreed, 'nach dem Lauf freigegeben');
  finally
    Tree.Free;
  end;
end;

procedure TRuleEngineTests.RunKeepsCallerCache;
var
  Context: TRuleContext;
  Tree: TSyntaxTree;
  Cache: IRuleDerivedCache;
  Value: TObject;
begin
  ProbeCreated := 0;
  ProbeFreed := 0;
  Tree := TPascalParser.Parse(Source);
  try
    Cache := TRuleDerivedCache.Create;
    Context := Default(TRuleContext);
    Context.Text := Source;
    Context.Tree := Tree;
    Context.Derived := Cache;
    TRuleEngine.Run([TProbeRule.Create('probe-a')], TServerSettings.Default, Context);
    TRuleEngine.Run([TProbeRule.Create('probe-b')], TServerSettings.Default, Context);
    Assert.AreEqual(1, ProbeCreated, 'Cache des Aufrufers über beide Läufe');
    Assert.AreEqual(0, ProbeFreed, 'Cache des Aufrufers bleibt gefüllt');
    Assert.IsTrue(Cache.TryGet('test.probe', Value));
    Context.Derived := nil;
    Cache := nil;
    Assert.AreEqual(1, ProbeFreed, 'mit dem Cache freigegeben');
  finally
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleEngineTests);

end.
