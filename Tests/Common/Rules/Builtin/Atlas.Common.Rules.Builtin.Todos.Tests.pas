unit Atlas.Common.Rules.Builtin.Todos.Tests;

// Tests der Regel todo-comment (#68): freiwillig (ohne Konfiguration still),
// Hinweis auf dem Kommentar, DONE nie, Unterdrückung, Marken aus "keywords".

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTodoRulesTests = class
  public
    [Test]
    procedure OffByDefault;
    [Test]
    procedure ReportsOpenEntriesAsHint;
    [Test]
    procedure DoneIsNeverReported;
    [Test]
    procedure SuppressedByComment;
    [Test]
    procedure KeywordsFromConfiguration;
    [Test]
    procedure KeywordsFromOptions;
    [Test]
    procedure KeywordsFromSettings;
    [Test]
    procedure RuleIsRegistered;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.Todos,
  Atlas.Tests.RuleAssert;

const
  Enabled = '{"rules": {"todo-comment": "hint"}}';
  Source =
    'unit U;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'procedure Run;'#10 +
    'begin'#10 +
    '  { TODO 1 -oMarco -cGUI : Fokus setzen }'#10 +
    '  // FIXME Rabatt'#10 +
    '  { DONE erledigt }'#10 +
    '  // HACK Umweg'#10 +
    'end;'#10 +
    'end.';

{ TTodoRulesTests }

procedure TTodoRulesTests.OffByDefault;
var
  Rule: IRule;
begin
  TRuleAssert.Silent(TTodoRule.Create, Source);
  Rule := TTodoRule.Create;
  Assert.IsTrue(Rule.Descriptor.Experimental, 'nur eingeschaltet');
end;

procedure TTodoRulesTests.ReportsOpenEntriesAsHint;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TTodoRule.Create, Source, Enabled);
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual(TodoCommentRuleId, Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Assert.AreEqual('TODO 1 [GUI, Marco]: Fokus setzen', Findings[0].Message);
  Assert.AreEqual(5, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(2, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(41, Findings[0].Range.EndPos.Character);
  Assert.AreEqual('FIXME: Rabatt', Findings[1].Message);
  Findings := TRuleAssert.Findings(TTodoRule.Create, Source, '{"rules": {"todo-comment": "warning"}}');
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
end;

procedure TTodoRulesTests.DoneIsNeverReported;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TTodoRule.Create,
    'unit U;'#10'{ DONE 1 -oAnna : fertig }'#10'end.', Enabled))));
end;

procedure TTodoRulesTests.SuppressedByComment;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TTodoRule.Create,
    'unit U;'#10'// lsp-ignore: todo-comment'#10'x := 1; // TODO prüfen'#10'end.', Enabled))));
end;

procedure TTodoRulesTests.KeywordsFromConfiguration;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TTodoRule.Create, Source,
    '{"rules": {"todo-comment": {"severity": "hint", "keywords": ["HACK", "TODO"]}}}');
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual('TODO 1 [GUI, Marco]: Fokus setzen', Findings[0].Message);
  Assert.AreEqual('HACK: Umweg', Findings[1].Message);
end;

procedure TTodoRulesTests.KeywordsFromOptions;
begin
  Assert.AreEqual('TODO FIXME', string.Join(' ', TTodoRules.KeywordsFromOptions('')));
  Assert.AreEqual('TODO FIXME', string.Join(' ', TTodoRules.KeywordsFromOptions('{"keywords": []}')));
  Assert.AreEqual('TODO FIXME', string.Join(' ', TTodoRules.KeywordsFromOptions('{"keywords": "HACK"}')));
  Assert.AreEqual('HACK XXX', string.Join(' ',
    TTodoRules.KeywordsFromOptions('{"keywords": ["hack", " XXX ", "DONE", "TO-DO", 1]}')));
  Assert.IsTrue(TTodoRules.IsValidKeyword('Note'));
  Assert.IsFalse(TTodoRules.IsValidKeyword('done'));
  Assert.IsFalse(TTodoRules.IsValidKeyword(''));
  Assert.IsFalse(TTodoRules.IsValidKeyword('TO DO'));
end;

procedure TTodoRulesTests.KeywordsFromSettings;
var
  Issues: TArray<TConfigurationIssue>;
  Settings: TServerSettings;
begin
  Assert.AreEqual('TODO FIXME', string.Join(' ', TTodoRules.Keywords(TServerSettings.Default)));
  // Die Marken gelten auch bei abgeschalteter Regel (für get_todos und --todos).
  Settings := TConfigurationParser.Parse('{"rules": {"todo-comment": {"severity": "off", "keywords": ["NOTE"]}}}',
    Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual('NOTE', string.Join(' ', TTodoRules.Keywords(Settings)));
end;

procedure TTodoRulesTests.RuleIsRegistered;
var
  Rule: IRule;
  Found: Boolean;
begin
  Found := False;
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id = TodoCommentRuleId then
      Found := True;
  Assert.IsTrue(Found);
end;

initialization
  TDUnitX.RegisterTestFixture(TTodoRulesTests);

end.
