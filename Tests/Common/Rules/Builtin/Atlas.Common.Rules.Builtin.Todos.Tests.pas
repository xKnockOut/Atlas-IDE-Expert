unit Atlas.Common.Rules.Builtin.Todos.Tests;

// Tests der Regel todo-comment (#68): freiwillig (ohne Konfiguration still),
// Hinweis auf dem Kommentar, DONE nie, Unterdrückung, Marken aus "keywords".
// commented-out-code (#942): Codeblöcke ab minLines Zeilen, Prosa, XMLDoc und
// Dateikopf still, mehrzeilige { }-Kommentare, Korrektur entfernt die Zeilen.

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
    [Test]
    procedure CommentedCodeReported;
    [Test]
    procedure CommentedCodeFixRemovesLines;
    [Test]
    procedure ProseCommentsSilent;
    [Test]
    procedure XmlDocAndHeaderSilent;
    [Test]
    procedure DocumentationExamplesSilent;
    [Test]
    procedure CommentedBlockReported;
    [Test]
    procedure CommentedCodeMinLines;
    [Test]
    procedure CommentedCodeOff;
    [Test]
    procedure CommentedDeclarationsReported;
    [Test]
    procedure LooksLikeCode;
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

  CommentedCode =
    '// Atlas'#10 +
    'unit U;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'procedure Run;'#10 +
    'begin'#10 +
    '  Speichern;'#10 +
    '  // if Kunde.Aktiv then'#10 +
    '  //   Kunde.Speichern;'#10 +
    '  // Log(''gespeichert'');'#10 +
    '  Fertig;'#10 +
    'end;'#10 +
    'end.';

function InRoutine(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure Run;'#10'begin'#10 + ABody +
    'end;'#10'end.';
end;

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

procedure TTodoRulesTests.CommentedCodeReported;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TCommentedOutCodeRule.Create, CommentedCode);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(CommentedOutCodeRuleId, Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual('3 Zeilen auskommentierter Code; die Versionsverwaltung bewahrt ihn auf.', Findings[0].Message);
  Assert.AreEqual(7, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(2, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(9, Findings[0].Range.EndPos.Line);
  Assert.IsFalse((TCommentedOutCodeRule.Create as IRule).Descriptor.Experimental, 'Standard an');
end;

procedure TTodoRulesTests.CommentedCodeFixRemovesLines;
var
  Findings: TArray<TRuleFinding>;
  Edit: TRuleEdit;
begin
  Findings := TRuleAssert.Findings(TCommentedOutCodeRule.Create, CommentedCode);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Auskommentierten Code entfernen', Findings[0].Fixes[0].Title);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes[0].Edits)));
  Edit := Findings[0].Fixes[0].Edits[0];
  Assert.AreEqual(7, Edit.Range.StartPos.Line);
  Assert.AreEqual(0, Edit.Range.StartPos.Character);
  Assert.AreEqual(10, Edit.Range.EndPos.Line);
  Assert.AreEqual(0, Edit.Range.EndPos.Character);
  Assert.AreEqual('', Edit.NewText);
end;

procedure TTodoRulesTests.ProseCommentsSilent;
begin
  TRuleAssert.Silent(TCommentedOutCodeRule.Create, InRoutine(
    '  // Hier wird der Kunde gespeichert, sofern er aktiv ist.'#10 +
    '  // Danach schreibt die Routine einen Eintrag ins Protokoll'#10 +
    '  // und meldet den Erfolg an die Oberfläche.'#10 +
    '  Speichern;'#10));
  // Zwei Codezeilen reichen nicht.
  TRuleAssert.Silent(TCommentedOutCodeRule.Create, InRoutine(
    '  // Speichern;'#10 +
    '  // Fertig;'#10 +
    '  Speichern;'#10));
  // Codezeichen, die sich nicht parsen lassen.
  TRuleAssert.Silent(TCommentedOutCodeRule.Create, InRoutine(
    '  // Achtung: erst prüfen;'#10 +
    '  // dann speichern := immer;'#10 +
    '  // sonst geht es schief;'#10 +
    '  Speichern;'#10));
end;

procedure TTodoRulesTests.XmlDocAndHeaderSilent;
begin
  TRuleAssert.Silent(TCommentedOutCodeRule.Create,
    '// Speichern;'#10'// Laden;'#10'// Fertig;'#10 +
    'unit U;'#10'interface'#10 +
    '/// Speichern;'#10'/// Laden;'#10'/// Fertig;'#10 +
    'procedure Run;'#10'implementation'#10'procedure Run;'#10'begin'#10'end;'#10'end.');
end;

procedure TTodoRulesTests.DocumentationExamplesSilent;
begin
  // Beispiel hinter einer Prosazeile mit Doppelpunkt, auch mit Leerzeile dazwischen.
  TRuleAssert.Silent(TCommentedOutCodeRule.Create, InRoutine(
    '  // Der Setter sieht so aus:'#10 +
    '  //'#10 +
    '  //   if FName <> Value then'#10 +
    '  //     FName := Value;'#10 +
    '  //   Invalidate;'#10 +
    '  Speichern;'#10));
  // Beispiel in <code>.
  TRuleAssert.Silent(TCommentedOutCodeRule.Create, InRoutine(
    '  // <code>'#10 +
    '  //   if FName <> Value then'#10 +
    '  //     FName := Value;'#10 +
    '  //   Invalidate;'#10 +
    '  // </code>'#10 +
    '  Speichern;'#10));
end;

procedure TTodoRulesTests.CommentedBlockReported;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TCommentedOutCodeRule.Create, InRoutine(
    '  {'#10 +
    '  if Kunde.Aktiv then'#10 +
    '    Kunde.Speichern;'#10 +
    '  Log(''gespeichert'');'#10 +
    '  }'#10 +
    '  Speichern;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(5, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(5, Findings[0].Fixes[0].Edits[0].Range.StartPos.Line);
  Assert.AreEqual(10, Findings[0].Fixes[0].Edits[0].Range.EndPos.Line);
  // Prosa im Blockkommentar bleibt still.
  TRuleAssert.Silent(TCommentedOutCodeRule.Create, InRoutine(
    '  {'#10 +
    '  Hier wird gespeichert.'#10 +
    '  Danach wird protokolliert.'#10 +
    '  Am Ende kommt die Meldung.'#10 +
    '  }'#10 +
    '  Speichern;'#10));
end;

procedure TTodoRulesTests.CommentedCodeMinLines;
var
  Source: string;
begin
  Source := InRoutine('  // Speichern;'#10'  // Fertig;'#10'  Laden;'#10);
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TCommentedOutCodeRule.Create, Source,
    '{"rules": {"commented-out-code": {"severity": "hint", "minLines": 2}}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TCommentedOutCodeRule.Create, CommentedCode,
    '{"rules": {"commented-out-code": {"severity": "hint", "minLines": 4}}}'))));
end;

procedure TTodoRulesTests.CommentedCodeOff;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TCommentedOutCodeRule.Create, CommentedCode,
    '{"rules": {"commented-out-code": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TCommentedOutCodeRule.Create, CommentedCode,
    '{"rules": {"commented-out-code": {"severity": "hint", "exclude": ["*.pas"]}}}', 'U.pas'))));
end;

procedure TTodoRulesTests.CommentedDeclarationsReported;
begin
  // Klassenmitglieder und Deklarationen gelten ebenfalls als Code.
  TRuleAssert.Reports(TCommentedOutCodeRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TKunde = class'#10 +
    '  //  FName: string;'#10'  //  procedure Speichern;'#10'  //  property Name: string read FName;'#10 +
    '  end;'#10'implementation'#10'end.');
end;

procedure TTodoRulesTests.LooksLikeCode;
begin
  Assert.IsTrue(TCommentedOutCodeRule.LooksLikeCode('  Speichern;'));
  Assert.IsTrue(TCommentedOutCodeRule.LooksLikeCode('X := 1'));
  Assert.IsTrue(TCommentedOutCodeRule.LooksLikeCode('begin'));
  Assert.IsTrue(TCommentedOutCodeRule.LooksLikeCode('if A then'));
  Assert.IsFalse(TCommentedOutCodeRule.LooksLikeCode('Hier wird gespeichert.'));
  Assert.IsFalse(TCommentedOutCodeRule.LooksLikeCode(''));
end;

initialization
  TDUnitX.RegisterTestFixture(TTodoRulesTests);

end.
