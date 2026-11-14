unit Atlas.Common.Rules.Builtin.OpenTools.Tests;

// Tests der Regel ota-notifier-not-removed (#944): Aufruf ohne Zuweisung,
// Zuweisung ohne RemoveNotifier, Korrekturen mit Feld und Destruktor bzw.
// globaler Variable und finalization, Ausnahmen und Optionen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TOpenToolsRulesTests = class
  public
    [Test]
    procedure IssueExampleReported;
    [Test]
    procedure IssueExampleFixUsesFinalization;
    [Test]
    procedure MethodFixUsesFieldAndDestructor;
    [Test]
    procedure AssignedIndexWithoutRemove;
    [Test]
    procedure RemovedIndexIsSilent;
    [Test]
    procedure RegisterProcedureIsSilent;
    [Test]
    procedure LocalReceiverWithoutFix;
    [Test]
    procedure RegisterPairsOption;
    [Test]
    procedure OffAndExclude;
    [Test]
    procedure IndexNames;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.OpenTools,
  Atlas.Tests.RuleAssert;

const
  cIssueExample =
    'unit Speichern;'#10 +
    #10 +
    'interface'#10 +
    #10 +
    'procedure Register;'#10 +
    #10 +
    'implementation'#10 +
    #10 +
    'procedure Register;'#10 +
    'begin'#10 +
    '  (BorlandIDEServices as IOTAServices).AddNotifier(TSpeicherNotifier.Create);'#10 +
    'end;'#10 +
    #10 +
    'end.';

  cMethodExample =
    'unit Spion;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TSpion = class'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TSpion.Create;'#10 +
    'begin'#10 +
    '  inherited Create;'#10 +
    '  (BorlandIDEServices as IOTAEditorServices).AddNotifier(TEditorNotifier.Create);'#10 +
    'end;'#10 +
    'end.';

/// <summary>Quelltext nach den Korrekturen des ersten Treffers (Edits nach Position sortiert).</summary>
function Fixed(const ASource: string; const AFinding: TRuleFinding): string;
var
  mLines: TArray<string>;
  mOffsets: TArray<Integer>;
  mIndex: Integer;
  mEdit: TTextEdit;
begin
  mLines := ASource.Split([#10]);
  SetLength(mOffsets, Length(mLines) + 1);
  mOffsets[0] := 0;
  for mIndex := 0 to High(mLines) do
  begin
    mOffsets[mIndex + 1] := mOffsets[mIndex] + Length(mLines[mIndex]) + 1;
  end;
  Result := ASource;
  for mIndex := High(AFinding.Fixes[0].Edits) downto 0 do
  begin
    mEdit := AFinding.Fixes[0].Edits[mIndex];
    Result := Copy(Result, 1, mOffsets[mEdit.Range.StartPos.Line] + mEdit.Range.StartPos.Character) + mEdit.NewText +
      Copy(Result, mOffsets[mEdit.Range.EndPos.Line] + mEdit.Range.EndPos.Character + 1, MaxInt);
  end;
end;

procedure AssertParses(const ASource: string);
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(ASource);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)), ASource);
  finally
    mTree.Free;
  end;
end;

{ TOpenToolsRulesTests }

procedure TOpenToolsRulesTests.IssueExampleReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TOtaNotifierNotRemovedRule.Create, cIssueExample);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('ota-notifier-not-removed', mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(mFindings[0].Confidence));
  Assert.AreEqual('Der Index von AddNotifier wird nicht gemerkt; ohne RemoveNotifier ruft die IDE nach dem ' +
    'Entladen ins Leere.', mFindings[0].Message);
  Assert.AreEqual(10, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(39, mFindings[0].Range.StartPos.Character);
end;

procedure TOpenToolsRulesTests.IssueExampleFixUsesFinalization;
var
  mFindings: TArray<TRuleFinding>;
  mSource: string;
begin
  mFindings := TRuleAssert.Findings(TOtaNotifierNotRemovedRule.Create, cIssueExample);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('Index merken und RemoveNotifier in finalization ergänzen', mFindings[0].Fixes[0].Title);
  mSource := Fixed(cIssueExample, mFindings[0]);
  Assert.AreEqual(
    'unit Speichern;'#10#10'interface'#10#10'procedure Register;'#10#10'implementation'#10#10 +
    'var'#10'  NotifierIndex: Integer = -1;'#10#10 +
    'procedure Register;'#10'begin'#10 +
    '  NotifierIndex := (BorlandIDEServices as IOTAServices).AddNotifier(TSpeicherNotifier.Create);'#10 +
    'end;'#10#10 +
    'initialization'#10#10 +
    'finalization'#10'  if NotifierIndex >= 0 then'#10 +
    '    (BorlandIDEServices as IOTAServices).RemoveNotifier(NotifierIndex);'#10#10 +
    'end.', mSource);
  AssertParses(mSource);
  TRuleAssert.Silent(TOtaNotifierNotRemovedRule.Create, mSource);
  // Vorhandene finalization wird ergänzt.
  mSource := StringReplace(cIssueExample, #10'end.', #10'initialization'#10'finalization'#10'  Aufraeumen;'#10'end.',
    []);
  mFindings := TRuleAssert.Findings(TOtaNotifierNotRemovedRule.Create, mSource);
  mSource := Fixed(mSource, mFindings[0]);
  Assert.Contains(mSource, 'finalization'#10'  if NotifierIndex >= 0 then'#10 +
    '    (BorlandIDEServices as IOTAServices).RemoveNotifier(NotifierIndex);'#10'  Aufraeumen;');
  AssertParses(mSource);
end;

procedure TOpenToolsRulesTests.MethodFixUsesFieldAndDestructor;
var
  mFindings: TArray<TRuleFinding>;
  mSource: string;
begin
  mFindings := TRuleAssert.Findings(TOtaNotifierNotRemovedRule.Create, cMethodExample);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Index in ein Feld legen und RemoveNotifier im Destruktor ergänzen', mFindings[0].Fixes[0].Title);
  mSource := Fixed(cMethodExample, mFindings[0]);
  Assert.Contains(mSource, '  end;'#10'implementation', 'Klasse endet wie vorher');
  Assert.Contains(mSource, '  private'#10'    FNotifierIndex: Integer;'#10'  end;');
  Assert.Contains(mSource, '  FNotifierIndex := (BorlandIDEServices as IOTAEditorServices).AddNotifier(');
  Assert.Contains(mSource, 'destructor Destroy; override;');
  Assert.Contains(mSource, 'destructor TSpion.Destroy;'#10'begin'#10 +
    '  (BorlandIDEServices as IOTAEditorServices).RemoveNotifier(FNotifierIndex);'#10'  inherited;'#10'end;');
  AssertParses(mSource);
  TRuleAssert.Silent(TOtaNotifierNotRemovedRule.Create, mSource);
end;

procedure TOpenToolsRulesTests.AssignedIndexWithoutRemove;
var
  mFindings: TArray<TRuleFinding>;
  mSource: string;
begin
  mSource := StringReplace(cMethodExample, '    constructor Create;', '    FIndex: Integer;'#10 +
    '    constructor Create;'#10'    destructor Destroy; override;', []);
  mSource := StringReplace(mSource, '  (BorlandIDEServices as IOTAEditorServices).AddNotifier',
    '  FIndex := (BorlandIDEServices as IOTAEditorServices).AddNotifier', []);
  mSource := StringReplace(mSource, #10'end.', #10'destructor TSpion.Destroy;'#10'begin'#10'  inherited;'#10 +
    'end;'#10'end.', []);
  mFindings := TRuleAssert.Findings(TOtaNotifierNotRemovedRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Der Index FIndex von AddNotifier geht nie an RemoveNotifier; die IDE ruft nach dem Entladen ' +
    'ins Leere.', mFindings[0].Message);
  Assert.AreEqual('RemoveNotifier im Destruktor ergänzen', mFindings[0].Fixes[0].Title);
  mSource := Fixed(mSource, mFindings[0]);
  Assert.Contains(mSource, 'destructor TSpion.Destroy;'#10'begin'#10 +
    '  (BorlandIDEServices as IOTAEditorServices).RemoveNotifier(FIndex);'#10'  inherited;');
  TRuleAssert.Silent(TOtaNotifierNotRemovedRule.Create, mSource);
end;

procedure TOpenToolsRulesTests.RemovedIndexIsSilent;
begin
  // Abmeldung in finalization, auch mit Self. und anderem Empfänger.
  TRuleAssert.Silent(TOtaNotifierNotRemovedRule.Create,
    'unit U;'#10'interface'#10'implementation'#10'var'#10'  Index: Integer;'#10 +
    'procedure Anmelden;'#10'begin'#10'  Index := Services.AddNotifier(TN.Create);'#10'end;'#10 +
    'initialization'#10'  Anmelden;'#10'finalization'#10'  Services.RemoveNotifier(Index);'#10'end.');
  TRuleAssert.Silent(TOtaNotifierNotRemovedRule.Create,
    'unit U;'#10'interface'#10'implementation'#10 +
    'procedure TA.Start;'#10'begin'#10'  Self.FIndex := FModule.AddNotifier(TN.Create);'#10'end;'#10 +
    'procedure TA.Destroyed;'#10'begin'#10'  FModule.RemoveNotifier(FIndex);'#10'end;'#10'end.');
  // Index + 1 gespeichert, damit 0 „nicht angemeldet“ heißt.
  TRuleAssert.Silent(TOtaNotifierNotRemovedRule.Create,
    'unit U;'#10'interface'#10'implementation'#10 +
    'procedure TA.Start;'#10'begin'#10'  FIndex := Services.AddNotifier(TN.Create) + 1;'#10'end;'#10 +
    'procedure TA.Stop;'#10'begin'#10'  Services.RemoveNotifier(FIndex - 1);'#10'end;'#10'end.');
  // Feld eines anderen Objekts, abgemeldet über eine Kopie im Objekt selbst.
  TRuleAssert.Silent(TOtaNotifierNotRemovedRule.Create,
    'unit U;'#10'interface'#10'implementation'#10 +
    'procedure TN.Abmelden;'#10'var'#10'  Index: Integer;'#10'begin'#10'  Index := FIndex;'#10'  FIndex := -1;'#10 +
    '  FProject.RemoveNotifier(Index);'#10'end;'#10 +
    'procedure Beobachten(const AProject: IOTAProject);'#10'var'#10'  Notifier: TN;'#10'begin'#10 +
    '  Notifier := TN.Create;'#10'  Notifier.FIndex := AProject.AddNotifier(Notifier);'#10'end;'#10'end.');
  // Im Ausdruck verwendet: unklar, keine Meldung.
  TRuleAssert.Silent(TOtaNotifierNotRemovedRule.Create,
    'unit U;'#10'interface'#10'implementation'#10 +
    'procedure P;'#10'begin'#10'  Merken(Services.AddNotifier(TN.Create));'#10'end;'#10'end.');
end;

procedure TOpenToolsRulesTests.RegisterProcedureIsSilent;
begin
  TRuleAssert.Silent(TOtaNotifierNotRemovedRule.Create,
    'unit U;'#10'interface'#10'procedure Register;'#10'implementation'#10 +
    'procedure Register;'#10'begin'#10'  RegisterPackageWizard(TAtlasWizard.Create);'#10'end;'#10'end.');
  // Außerhalb von Register gemeldet.
  TRuleAssert.Reports(TOtaNotifierNotRemovedRule.Create,
    'unit U;'#10'interface'#10'implementation'#10 +
    'procedure Starten;'#10'begin'#10'  RegisterPackageWizard(TAtlasWizard.Create);'#10'end;'#10'end.');
end;

procedure TOpenToolsRulesTests.LocalReceiverWithoutFix;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TOtaNotifierNotRemovedRule.Create,
    'unit U;'#10'interface'#10'implementation'#10 +
    'procedure Beobachten(const AModule: IOTAModule);'#10'begin'#10'  AModule.AddNotifier(TN.Create);'#10 +
    'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
end;

procedure TOpenToolsRulesTests.RegisterPairsOption;
const
  cSource = 'unit U;'#10'interface'#10'implementation'#10 +
    'procedure P;'#10'begin'#10'  Services.AddWizard(TW.Create);'#10'  Services.AddNotifier(TN.Create);'#10 +
    'end;'#10'end.';
var
  mFindings: TArray<TRuleFinding>;
  mIssues: TArray<TConfigurationIssue>;
begin
  mFindings := TRuleAssert.Findings(TOtaNotifierNotRemovedRule.Create, cSource,
    '{"rules": {"ota-notifier-not-removed": {"registerPairs": [{"open": "AddWizard", "close": "RemoveWizard"}]}}}');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.Contains(mFindings[0].Message, 'AddWizard');
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TOtaNotifierNotRemovedRule.Create, cSource))));
  TConfigurationParser.Parse('{"rules": {"ota-notifier-not-removed": {"registerPairs": ["AddWizard"]}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
end;

procedure TOpenToolsRulesTests.OffAndExclude;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOtaNotifierNotRemovedRule.Create, cIssueExample,
    '{"rules": {"ota-notifier-not-removed": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOtaNotifierNotRemovedRule.Create, cIssueExample,
    '{"rules": {"ota-notifier-not-removed": {"exclude": ["Speichern.pas"]}}}', 'Speichern.pas'))));
end;

procedure TOpenToolsRulesTests.IndexNames;
begin
  Assert.AreEqual('NotifierIndex', TOtaNotifierNotRemovedRule.IndexName('AddNotifier'));
  Assert.AreEqual('PackageWizardIndex', TOtaNotifierNotRemovedRule.IndexName('RegisterPackageWizard'));
  Assert.AreEqual('HookIndex', TOtaNotifierNotRemovedRule.IndexName('hook'));
  Assert.AreEqual(2, Integer(Length(TOtaNotifierNotRemovedRule.Pairs(''))));
end;

initialization
  TDUnitX.RegisterTestFixture(TOpenToolsRulesTests);

end.
