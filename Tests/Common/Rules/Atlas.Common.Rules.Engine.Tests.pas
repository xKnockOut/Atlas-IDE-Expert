unit Atlas.Common.Rules.Engine.Tests;

// Tests für Prüfregel-Framework: Registrierung, Schweregrad aus der
// Konfiguration, Ausnahmen, Unterdrückung per Kommentar und Korrekturen;
// keine unused-suppression, wo eine Regel mangels Wissen nicht entscheidet.

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
    procedure UndecidedLineKeepsSuppression;
    [Test]
    procedure UnknownRuleIdWithSuggestion;
    [Test]
    procedure UnknownRuleIdWithoutSuggestion;
    /// <summary>#1458: Meldung und Korrektur auf Englisch.</summary>
    [Test]
    procedure UnknownRuleIdInEnglish;
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
    /// <summary>Alle Regeln eines Laufs teilen einen Ableitungscache.</summary>
    [Test]
    procedure RunSharesDerivedCacheBetweenRules;
    [Test]
    procedure RunClearsOwnCache;
    [Test]
    procedure RunKeepsCallerCache;
    /// <summary>#1094: Eine Regel, die eine Ausnahme wirft, kostet nur ihre eigenen Treffer; das
    /// Diagnoselog nennt Regel, Unit und Ausnahmeklasse.</summary>
    [Test]
    procedure FailingRuleKeepsOtherFindings;
    /// <summary>#1094: Ist die Anfrage abgebrochen, geht die Ausnahme einer Regel weiter wie bisher.</summary>
    [Test]
    procedure FailingRuleAfterCancelStillRaises;
    /// <summary>#1094: Ein abgefangener Stapelüberlauf stellt die Schutzseite wieder her.</summary>
    [Test]
    procedure OverflowInRuleRestoresStackGuard;
    /// <summary>#1094: Zu tiefe Syntaxbäume prüfen die Regeln nicht; das Diagnoselog nennt die Unit,
    /// und die Unit bekommt den Hinweis unit-too-deep an der tiefsten Stelle.</summary>
    [Test]
    procedure TooDeepTreeSkipsRules;
    [Test]
    procedure TooDeepHintCanBeSwitchedOff;
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
  Atlas.Common.Diagnostics.StackGuard,
  Atlas.Common.Localization.Texts,
  Atlas.Tests.RuleAssert;

type
  /// <summary>Gleichnamig zur veralteten RTL-Klasse (W1000): Atlas erkennt den Überlauf am Namen.</summary>
  EStackOverflow = class(Exception);

type
  /// <summary>Beispielregel: meldet jeden Bezeichner "Marker".</summary>
  TMarkerRule = class(TInterfacedObject, IRule)
  private
    FId: string;
    FWithFix: Boolean;
  public
    constructor Create(const AId: string; AWithFix: Boolean);
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
  mToken: TPascalToken;
  mRange: TTextRange;
begin
  for mToken in AContext.Tree.Tokens do
  begin
    if (mToken.Kind = TPascalTokenKind.Identifier) and SameText(mToken.Text, 'Marker') then
    begin
      mRange := TTextRange.Create(mToken.StartPos, mToken.EndPos);
      if FWithFix then
      begin
        AReport.Add(mRange, 'Marker gefunden', [TRuleFix.Create('Umbenennen', [TRuleEdit.Create(mRange, 'Zeichen')])]);
      end
      else
      begin
        AReport.Add(mRange, 'Marker gefunden');
      end;
    end;
  end;
end;

type
  /// <summary>Wie TMarkerRule, kann aber die Zeile FUndecided nicht entscheiden (IRuleLineCertainty).</summary>
  TUncertainMarkerRule = class(TMarkerRule, IRuleLineCertainty)
  private
    FUndecided: Integer;
  public
    constructor Create(AUndecided: Integer);
    function Decides(const AContext: TRuleContext; ALine: Integer): Boolean;
  end;

constructor TUncertainMarkerRule.Create(AUndecided: Integer);
begin
  inherited Create('marker', False);
  FUndecided := AUndecided;
end;

function TUncertainMarkerRule.Decides(const AContext: TRuleContext; ALine: Integer): Boolean;
begin
  Result := ALine <> FUndecided;
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
  mCache: IRuleDerivedCache;
begin
  mCache := TRuleDerived.Open(AContext);
  TRuleDerived.Get<TProbe>(mCache, 'test.probe',
    function: TProbe
    begin
      Result := TProbe.Create;
    end);
end;

type
  /// <summary>Meldet einen Treffer und wirft dann eine Ausnahme der Klasse AError (#1094).</summary>
  TFailingRule = class(TInterfacedObject, IRule)
  private
    FId: string;
    FError: ExceptClass;
    FBefore: TProc;
  public
    constructor Create(const AId: string; AError: ExceptClass); overload;
    constructor Create(const AId: string; AError: ExceptClass; const ABefore: TProc); overload;
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

constructor TFailingRule.Create(const AId: string; AError: ExceptClass);
begin
  Create(AId, AError, nil);
end;

constructor TFailingRule.Create(const AId: string; AError: ExceptClass; const ABefore: TProc);
begin
  inherited Create;
  FId := AId;
  FError := AError;
  FBefore := ABefore;
end;

function TFailingRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(FId, TRuleSeverity.Warning, 'Scheitert immer');
end;

procedure TFailingRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  if Assigned(FBefore) then
  begin
    FBefore();
  end;
  AReport.Add(TTextRange.Create(0, 0, 0, 4), 'halber Treffer');
  raise FError.Create('Regel gescheitert');
end;

function JoinNotes(const ANotes: TRequestNotes): string;
var
  mNote: string;
begin
  Result := ' ';
  for mNote in ANotes.Notes do
  begin
    Result := Result + mNote + ' ';
  end;
end;

/// <summary>Prozedur mit einer Kette aus ACount Subtraktionen: linkslastig und so tief wie lang.</summary>
function DeepSource(ACount: Integer): string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('unit U;'#13#10'interface'#13#10'implementation'#13#10'procedure P;'#13#10'begin'#13#10);
    mBuilder.Append('  Marker := 1');
    for mIndex := 1 to ACount do
    begin
      mBuilder.Append(' - 1');
    end;
    mBuilder.Append(';'#13#10'end;'#13#10'end.');
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

const
  cSource =
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
  mRegistry: TRuleRegistry;
begin
  mRegistry := TRuleRegistry.Create;
  try
    mRegistry.Register(TMarkerRule.Create('a', False));
    Assert.WillRaise(
      procedure
      begin
        mRegistry.Register(TMarkerRule.Create('A', False));
      end, ERuleRegistry);
    Assert.AreEqual(1, Integer(Length(mRegistry.Rules)));
  finally
    mRegistry.Free;
  end;
end;

procedure TRuleEngineTests.RegistryFindsIgnoringCase;
var
  mRegistry: TRuleRegistry;
  mRule: IRule;
begin
  mRegistry := TRuleRegistry.Create;
  try
    mRegistry.Register(TMarkerRule.Create('empty-except', False));
    Assert.IsTrue(mRegistry.Find('Empty-Except', mRule));
    Assert.IsFalse(mRegistry.Find('other', mRule));
  finally
    mRegistry.Free;
  end;
end;

procedure TRuleEngineTests.UsesDefaultSeverity;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TMarkerRule.Create('marker', False), cSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual('marker', mFindings[0].RuleId);
  Assert.AreEqual(5, mFindings[0].Range.StartPos.Line);
end;

procedure TRuleEngineTests.ConfigurationOverridesSeverity;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TMarkerRule.Create('marker', False), cSource, '{ "rules": { "marker": "error" } }');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(mFindings[0].Severity));
end;

procedure TRuleEngineTests.OffDisablesRule;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create('marker', False), cSource,
    '{ "rules": { "marker": "off" } }'))));
end;

procedure TRuleEngineTests.GroupSwitchDisablesAllRulesOfGroup;
begin
  // Hauptschalter der Gruppe (#909): empty-except gehört zu „Exceptions“.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create('empty-except', False), cSource,
    '{ "rules": { "group:exceptions": "off" } }'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create('empty-except', False), cSource,
    '{ "rules": { "empty-except": "error", "group:exceptions": "off" } }'))), 'auch einzeln eingestellte');
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create('empty-except', False), cSource,
    '{ "rules": { "group:threads": "off" } }'))), 'andere Gruppe');
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create('empty-except', False), cSource,
    '{ "rules": { "group:exceptions": "warning" } }'))), 'nur off schaltet ab');
  // Regeln außerhalb des Katalogs haben keine Gruppe.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create('marker', False), cSource,
    '{ "rules": { "group:exceptions": "off" } }'))));
  Assert.IsFalse(TRuleEngine.GroupOff('EMPTY-EXCEPT', TServerSettings.Default));
end;

procedure TRuleEngineTests.CompilerGroupTypeLevel;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  // Gruppe „Compiler vorab“ (#1024): argument-count-mismatch hat Stufe T, comparison-as-statement Stufe A.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create('argument-count-mismatch', False), cSource,
    '{ "rules": { "group:compiler": { "typeLevel": "off" } } }'))), 'Stufe T aus');
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create('comparison-as-statement', False), cSource,
    '{ "rules": { "group:compiler": { "typeLevel": "off" } } }'))), 'Stufe A bleibt');
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create('argument-count-mismatch', False), cSource,
    '{ "rules": { "group:compiler": { "typeLevel": "certain" } } }'))), 'certain');
  // Hauptschalter auch als Objekt.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create('comparison-as-statement', False), cSource,
    '{ "rules": { "group:compiler": { "severity": "off", "typeLevel": "certain" } } }'))), 'Objekt mit off');
  // Andere Gruppen kennen typeLevel nicht; ohne Katalog keine Stufe.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create('marker', False), cSource,
    '{ "rules": { "group:compiler": { "typeLevel": "off" } } }'))));
  TConfigurationParser.Parse('{"rules": {"group:compiler": {"typeLevel": "nie"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.AreEqual('"typeLevel" muss "certain" oder "off" sein', mIssues[0].Message);
  TConfigurationParser.Parse('{"rules": {"group:compiler": {"typeLevel": "off"}}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
end;

procedure TRuleEngineTests.ExcludeByGlobInRuleOptions;
const
  cConfig = '{ "rules": { "marker": { "severity": "hint", "exclude": ["Legacy/**"] } } }';
var
  mFindings: TArray<TRuleFinding>;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create('marker', False), cSource, cConfig, 'Legacy\Alt\U.pas'))));
  mFindings := TRuleAssert.Findings(TMarkerRule.Create('marker', False), cSource, cConfig, 'Neu\U.pas');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
end;

procedure TRuleEngineTests.ExcludeByUnitNameInRuleOptions;
const
  cConfig = '{ "rules": { "marker": { "exclude": ["Alt.Unit"] } } }';
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create('marker', False), cSource, cConfig, 'Src\Alt.Unit.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create('marker', False), cSource, cConfig, 'Src\Neu.Unit.pas'))));
end;

procedure TRuleEngineTests.GlobalExcludeSkipsFile;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create('marker', False), cSource,
    '{ "exclude": ["Generated/**"] }', 'Generated\U.pas'))));
end;

procedure TRuleEngineTests.SuppressesSameLine;
begin
  TRuleAssert.Silent(TMarkerRule.Create('marker', False), SourceWith('  Marker := 1; // lsp-ignore: marker'#13#10));
end;

procedure TRuleEngineTests.SuppressesNextLine;
begin
  TRuleAssert.Reports(TMarkerRule.Create('marker', False), SourceWith(
    '  // lsp-ignore: marker'#13#10 +
    '  Marker := 1;'#13#10 +
    '  Marker := 2;'#13#10), 1);
end;

procedure TRuleEngineTests.SuppressionNamesOtherRule;
begin
  TRuleAssert.Reports(TMarkerRule.Create('marker', False), SourceWith('  Marker := 1; // lsp-ignore: empty-except'#13#10));
end;

procedure TRuleEngineTests.SuppressesWithWildcardInBraceComment;
begin
  TRuleAssert.Silent(TMarkerRule.Create('marker', False), SourceWith('  Marker := 1; { lsp-ignore: empty-except, * }'#13#10));
end;

procedure TRuleEngineTests.SuppressesWholeFile;
begin
  TRuleAssert.Silent(TMarkerRule.Create('marker', False), '// lsp-ignore-file: marker'#13#10 +
    SourceWith('  Marker := 1;'#13#10'  Marker := 2;'#13#10));
end;

procedure TRuleEngineTests.UndecidedLineKeepsSuppression;
var
  mFindings: TArray<TRuleFinding>;
begin
  // Zeile 5 kann die Regel nicht entscheiden: Ihr lsp-ignore dort ist keine unused-suppression, auch nicht "*".
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TUncertainMarkerRule.Create(5),
    SourceWith('  X := 1; // lsp-ignore: marker'#13#10)))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TUncertainMarkerRule.Create(5),
    SourceWith('  X := 1; // lsp-ignore: *'#13#10)))));
  mFindings := TRuleAssert.Findings(TUncertainMarkerRule.Create(7), SourceWith('  X := 1; // lsp-ignore: marker'#13#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(cUnusedSuppressionRuleId, mFindings[0].RuleId);
end;

procedure TRuleEngineTests.SuppressionReasonIsNoId;
begin
  // Nach "--" steht eine Begründung; das "*" darin gilt nicht als Kennung (#297).
  TRuleAssert.Reports(TMarkerRule.Create('marker', False),
    SourceWith('  Marker := 1; // lsp-ignore: empty-except -- gilt nicht für *'#13#10), 1);
  TRuleAssert.Silent(TMarkerRule.Create('marker', False), SourceWith('  Marker := 1; // lsp-ignore: marker -- Absicht'#13#10));
end;

procedure TRuleEngineTests.UnknownRuleIdWithSuggestion;
const
  cLine = '  Marker := 1; // lsp-ignore: empty-exept, marker';
var
  mFindings: TArray<TRuleFinding>;
begin
  // Abnahme #41: Tippfehler ergibt unknown-rule-id mit Vorschlag, aber keine unused-suppression.
  mFindings := TRuleAssert.Findings(TMarkerRule.Create('marker', False), SourceWith(cLine + #13#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(cUnknownRuleIdRuleId, mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
  Assert.IsTrue(Pos('"empty-except"', mFindings[0].Message) > 0, mFindings[0].Message);
  // Genau die Kennung ist markiert, die Korrektur ersetzt nur sie.
  Assert.AreEqual(5, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(Pos('empty-exept', cLine) - 1, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(Pos('empty-exept', cLine) - 1 + Length('empty-exept'), mFindings[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('empty-except', mFindings[0].Fixes[0].Edits[0].NewText);
  // Allein in der Zeile und ohne Treffer darunter: weiterhin keine unused-suppression daneben.
  mFindings := TRuleAssert.Findings(TMarkerRule.Create('marker', False), SourceWith('  // lsp-ignore: empty-exept'#13#10'  X := 1;'#13#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(cUnknownRuleIdRuleId, mFindings[0].RuleId);
  // Auch in { } und mit Begründung; die Begründung wird nie gelesen.
  mFindings := TRuleAssert.Findings(TMarkerRule.Create('marker', False),
    SourceWith('  Marker := 1; { lsp-ignore: marker -- empty-exept }'#13#10));
  Assert.AreEqual(0, Integer(Length(mFindings)));
end;

procedure TRuleEngineTests.UnknownRuleIdWithoutSuggestion;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TMarkerRule.Create('marker', False), SourceWith('  X := 1; // lsp-ignore: voellig-anders'#13#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(cUnknownRuleIdRuleId, mFindings[0].RuleId);
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
  Assert.IsTrue(Pos('wirkt nicht', mFindings[0].Message) > 0, mFindings[0].Message);
  // Kennungen der übergebenen Regeln, des Katalogs und "*" sind bekannt.
  TRuleAssert.Silent(TMarkerRule.Create('marker', False), SourceWith('  Marker := 1; // lsp-ignore: marker, *, with-statement'#13#10));
end;

procedure TRuleEngineTests.UnknownRuleIdInEnglish;
var
  mFindings: TArray<TRuleFinding>;
  mSaved: TTextLanguage;
begin
  mSaved := TAtlasLocale.Language;
  TAtlasLocale.Use(TTextLanguage.English);
  try
    mFindings := TRuleAssert.Findings(TMarkerRule.Create('marker', False),
      SourceWith('  Marker := 1; // lsp-ignore: empty-exept, marker'#13#10));
    Assert.AreEqual(1, Integer(Length(mFindings)));
    Assert.AreEqual('Unknown rule id "empty-exept"; probably "empty-except" is meant', mFindings[0].Message);
    Assert.AreEqual('Replace with "empty-except"', mFindings[0].Fixes[0].Title);
  finally
    TAtlasLocale.Use(mSaved);
  end;
end;

procedure TRuleEngineTests.UnknownRuleIdCanBeSwitchedOff;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create('marker', False),
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
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TMarkerRule.Create('marker', True), cSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('Umbenennen', mFindings[0].Fixes[0].Title);
  Assert.AreEqual('Zeichen', mFindings[0].Fixes[0].Edits[0].NewText);
end;

procedure TRuleEngineTests.SortsByPosition;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TMarkerRule.Create('marker', False), SourceWith(
    '  Marker := 1;'#13#10 +
    '  X := Marker + Marker;'#13#10));
  Assert.AreEqual(3, Integer(Length(mFindings)));
  Assert.AreEqual(5, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(6, mFindings[1].Range.StartPos.Line);
  Assert.IsTrue(mFindings[1].Range.StartPos.Character < mFindings[2].Range.StartPos.Character);
end;

procedure TRuleEngineTests.RuleAssertPositiveAndNegative;
begin
  TRuleAssert.Reports(TMarkerRule.Create('marker', False), cSource);
  TRuleAssert.Silent(TMarkerRule.Create('marker', False), SourceWith('  X := 1;'#13#10));
end;

procedure TRuleEngineTests.CancelledStopsBeforeNextRule;
var
  mStop: Boolean;
  mRuns: Integer;
  mContext: TRuleContext;
  mTree: TSyntaxTree;
begin
  mStop := False;
  mRuns := 0;
  mTree := TPascalParser.Parse(cSource);
  try
    mContext := Default(TRuleContext);
    mContext.Text := cSource;
    mContext.Tree := mTree;
    mContext.Cancelled :=
      function: Boolean
      begin
        Result := mStop;
      end;
    Assert.WillRaise(
      procedure
      begin
        TRuleEngine.Run([
          TCallbackRule.Create('erste',
            procedure
            begin
              Inc(mRuns);
              mStop := True;
            end),
          TCallbackRule.Create('zweite',
            procedure
            begin
              Inc(mRuns);
            end)], TServerSettings.Default, mContext);
      end, ERuleCheckCancelled);
    Assert.AreEqual(1, mRuns);
  finally
    // Context hängt in der Closure und hält über Cancelled die Closure selbst: Kreis lösen.
    mContext.Cancelled := nil;
    mTree.Free;
  end;
end;

procedure TRuleEngineTests.SlowRuleNamedInDiagnostics;
var
  mContext: TRuleContext;
  mTree: TSyntaxTree;
  mNotes: TRequestNotes;
  mJoined, mNote: string;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mContext := Default(TRuleContext);
    mContext.Text := cSource;
    mContext.Tree := mTree;
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
            Sleep(TRuleEngine.cSlowRuleMs + 50);
          end)], TServerSettings.Default, mContext);
    finally
      mNotes := TRequestDiagnostics.Close;
    end;
  finally
    mTree.Free;
  end;
  mJoined := '';
  for mNote in mNotes.Notes do
  begin
    mJoined := mJoined + mNote + ' ';
  end;
  Assert.Contains(mJoined, 'slowRule=langsam ');
  Assert.Contains(mJoined, 'slowRuleMs=');
  Assert.DoesNotContain(mJoined, 'schnell');
end;

procedure TRuleEngineTests.RunSharesDerivedCacheBetweenRules;
var
  mContext: TRuleContext;
  mTree: TSyntaxTree;
begin
  ProbeCreated := 0;
  ProbeFreed := 0;
  mTree := TPascalParser.Parse(cSource);
  try
    mContext := Default(TRuleContext);
    mContext.Text := cSource;
    mContext.Tree := mTree;
    TRuleEngine.Run([TProbeRule.Create('probe-a'), TProbeRule.Create('probe-b'), TProbeRule.Create('probe-c')],
      TServerSettings.Default, mContext);
  finally
    mTree.Free;
  end;
  Assert.AreEqual(1, ProbeCreated, 'einmal je Lauf erzeugt');
end;

procedure TRuleEngineTests.RunClearsOwnCache;
var
  mContext: TRuleContext;
  mTree: TSyntaxTree;
begin
  ProbeCreated := 0;
  ProbeFreed := 0;
  mTree := TPascalParser.Parse(cSource);
  try
    mContext := Default(TRuleContext);
    mContext.Text := cSource;
    mContext.Tree := mTree;
    TRuleEngine.Run([TProbeRule.Create('probe-a')], TServerSettings.Default, mContext);
    // Noch vor dem Baum freigegeben: abgeleitete Objekte zeigen in den Baum.
    Assert.AreEqual(1, ProbeFreed, 'nach dem Lauf freigegeben');
  finally
    mTree.Free;
  end;
end;

procedure TRuleEngineTests.RunKeepsCallerCache;
var
  mContext: TRuleContext;
  mTree: TSyntaxTree;
  mCache: IRuleDerivedCache;
  mValue: TObject;
begin
  ProbeCreated := 0;
  ProbeFreed := 0;
  mTree := TPascalParser.Parse(cSource);
  try
    mCache := TRuleDerivedCache.Create;
    mContext := Default(TRuleContext);
    mContext.Text := cSource;
    mContext.Tree := mTree;
    mContext.Derived := mCache;
    TRuleEngine.Run([TProbeRule.Create('probe-a')], TServerSettings.Default, mContext);
    TRuleEngine.Run([TProbeRule.Create('probe-b')], TServerSettings.Default, mContext);
    Assert.AreEqual(1, ProbeCreated, 'Cache des Aufrufers über beide Läufe');
    Assert.AreEqual(0, ProbeFreed, 'Cache des Aufrufers bleibt gefüllt');
    Assert.IsTrue(mCache.TryGet('test.probe', mValue));
    mContext.Derived := nil;
    mCache := nil;
    Assert.AreEqual(1, ProbeFreed, 'mit dem Cache freigegeben');
  finally
    mTree.Free;
  end;
end;

procedure TRuleEngineTests.FailingRuleKeepsOtherFindings;
var
  mContext: TRuleContext;
  mTree: TSyntaxTree;
  mFindings: TArray<TRuleFinding>;
  mNotes: TRequestNotes;
  mJoined: string;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mContext := Default(TRuleContext);
    mContext.Text := cSource;
    mContext.Tree := mTree;
    TRequestDiagnostics.Open;
    try
      TRequestDiagnostics.Subject('unit#3');
      mFindings := TRuleEngine.Run([TFailingRule.Create('kaputt', EArgumentException), TMarkerRule.Create('marker', False)],
        TServerSettings.Default, mContext);
    finally
      mNotes := TRequestDiagnostics.Close;
    end;
  finally
    mTree.Free;
  end;
  Assert.AreEqual(1, Integer(Length(mFindings)), 'nur der Treffer der heilen Regel');
  Assert.AreEqual('marker', mFindings[0].RuleId);
  mJoined := JoinNotes(mNotes);
  Assert.Contains(mJoined, ' failedRules=1 ');
  Assert.Contains(mJoined, ' failRule=kaputt ');
  Assert.Contains(mJoined, ' failRuleUnit=unit#3 ');
  Assert.Contains(mJoined, ' failRuleClass=EArgumentException ');
  Assert.AreEqual('', mNotes.Rule, 'keine Regel mehr offen');
  mFindings := nil;
end;

procedure TRuleEngineTests.FailingRuleAfterCancelStillRaises;
var
  mStop: Boolean;
  mContext: TRuleContext;
  mTree: TSyntaxTree;
begin
  mStop := False;
  mTree := TPascalParser.Parse(cSource);
  try
    mContext := Default(TRuleContext);
    mContext.Text := cSource;
    mContext.Tree := mTree;
    mContext.Cancelled :=
      function: Boolean
      begin
        Result := mStop;
      end;
    Assert.WillRaise(
      procedure
      begin
        TRuleEngine.Run([
          TFailingRule.Create('kaputt', EArgumentException,
            procedure
            begin
              mStop := True;
            end)], TServerSettings.Default, mContext);
      end, EArgumentException);
  finally
    mContext.Cancelled := nil;
    mTree.Free;
  end;
end;

procedure TRuleEngineTests.OverflowInRuleRestoresStackGuard;
var
  mContext: TRuleContext;
  mTree: TSyntaxTree;
  mFindings: TArray<TRuleFinding>;
  mRestores: Integer;
begin
  mRestores := 0;
  TStackGuard.Restore :=
    procedure
    begin
      Inc(mRestores);
    end;
  try
    mTree := TPascalParser.Parse(cSource);
    try
      mContext := Default(TRuleContext);
      mContext.Text := cSource;
      mContext.Tree := mTree;
      mFindings := TRuleEngine.Run([TFailingRule.Create('tief', EStackOverflow), TMarkerRule.Create('marker', False)],
        TServerSettings.Default, mContext);
    finally
      mTree.Free;
    end;
  finally
    TStackGuard.Restore := nil;
  end;
  Assert.AreEqual(1, mRestores);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('marker', mFindings[0].RuleId);
  mFindings := nil;
end;

procedure TRuleEngineTests.TooDeepTreeSkipsRules;
var
  mContext: TRuleContext;
  mTree: TSyntaxTree;
  mText, mJoined: string;
  mFindings: TArray<TRuleFinding>;
  mNotes: TRequestNotes;
  mDepth: Integer;
begin
  mText := DeepSource(TRuleEngine.cMaxTreeDepth + 200);
  mTree := TPascalParser.Parse(mText);
  try
    mDepth := mTree.Depth;
    Assert.IsTrue(mDepth > TRuleEngine.cMaxTreeDepth, 'Subtraktion bleibt linkslastig');
    mContext := Default(TRuleContext);
    mContext.Text := mText;
    mContext.Tree := mTree;
    TRequestDiagnostics.Open;
    try
      TRequestDiagnostics.Subject('unit#5');
      mFindings := TRuleEngine.Run([TMarkerRule.Create('marker', False)], TServerSettings.Default, mContext);
    finally
      mNotes := TRequestDiagnostics.Close;
    end;
  finally
    mTree.Free;
  end;
  // Statt der Regeln nur der Hinweis, am ersten Glied der Kette ("  Marker := 1" in Zeile 6).
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(cUnitTooDeepRuleId, mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
  Assert.AreEqual(5, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(12, mFindings[0].Range.StartPos.Character);
  Assert.IsTrue(Pos(IntToStr(mDepth), mFindings[0].Message) > 0, mFindings[0].Message);
  mFindings := nil;
  mJoined := JoinNotes(mNotes);
  Assert.Contains(mJoined, ' deepUnits=1 ');
  Assert.Contains(mJoined, ' deepUnit=unit#5 ');
  Assert.Contains(mJoined, ' deepUnitDepth=' + IntToStr(mDepth) + ' ');
  // Flache Bäume prüfen die Regeln wie bisher.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create('marker', False), DeepSource(10)))));
end;

procedure TRuleEngineTests.TooDeepHintCanBeSwitchedOff;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMarkerRule.Create('marker', False),
    DeepSource(TRuleEngine.cMaxTreeDepth + 200), '{"rules": {"unit-too-deep": "off"}}'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleEngineTests);

end.
