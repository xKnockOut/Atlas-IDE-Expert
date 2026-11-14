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
  Atlas.Tests.RuleAssert,
  Atlas.Common.Rules.Profiles;

const
  cEnabled = '{"rules": {"todo-comment": "hint"}}';
  cSource =
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

  cCommentedCode =
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
  mRule: IRule;
begin
  TRuleAssert.Silent(TTodoRule.Create, cSource);
  mRule := TTodoRule.Create;
  Assert.IsTrue(TRuleProfiles.IsExperimental(mRule.Descriptor.Id), 'nur eingeschaltet');
end;

procedure TTodoRulesTests.ReportsOpenEntriesAsHint;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TTodoRule.Create, cSource, cEnabled);
  Assert.AreEqual(2, Integer(Length(mFindings)));
  Assert.AreEqual(cTodoCommentRuleId, mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
  Assert.AreEqual('TODO 1 [GUI, Marco]: Fokus setzen', mFindings[0].Message);
  Assert.AreEqual(5, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(41, mFindings[0].Range.EndPos.Character);
  Assert.AreEqual('FIXME: Rabatt', mFindings[1].Message);
  mFindings := TRuleAssert.Findings(TTodoRule.Create, cSource, '{"rules": {"todo-comment": "warning"}}');
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
end;

procedure TTodoRulesTests.DoneIsNeverReported;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TTodoRule.Create,
    'unit U;'#10'{ DONE 1 -oAnna : fertig }'#10'end.', cEnabled))));
end;

procedure TTodoRulesTests.SuppressedByComment;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TTodoRule.Create,
    'unit U;'#10'// lsp-ignore: todo-comment'#10'x := 1; // TODO prüfen'#10'end.', cEnabled))));
end;

procedure TTodoRulesTests.KeywordsFromConfiguration;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TTodoRule.Create, cSource,
    '{"rules": {"todo-comment": {"severity": "hint", "keywords": ["HACK", "TODO"]}}}');
  Assert.AreEqual(2, Integer(Length(mFindings)));
  Assert.AreEqual('TODO 1 [GUI, Marco]: Fokus setzen', mFindings[0].Message);
  Assert.AreEqual('HACK: Umweg', mFindings[1].Message);
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
  mIssues: TArray<TConfigurationIssue>;
  mSettings: TServerSettings;
begin
  Assert.AreEqual('TODO FIXME', string.Join(' ', TTodoRules.Keywords(TServerSettings.Default)));
  // Die Marken gelten auch bei abgeschalteter Regel (für get_todos und --todos).
  mSettings := TConfigurationParser.Parse('{"rules": {"todo-comment": {"severity": "off", "keywords": ["NOTE"]}}}',
    mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual('NOTE', string.Join(' ', TTodoRules.Keywords(mSettings)));
end;

procedure TTodoRulesTests.RuleIsRegistered;
var
  mRule: IRule;
  mFound: Boolean;
begin
  mFound := False;
  for mRule in BuiltinRules do
  begin
    if mRule.Descriptor.Id = cTodoCommentRuleId then
    begin
      mFound := True;
    end;
  end;
  Assert.IsTrue(mFound);
end;

procedure TTodoRulesTests.CommentedCodeReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TCommentedOutCodeRule.Create, cCommentedCode);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(cCommentedOutCodeRuleId, mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(mFindings[0].Confidence));
  Assert.AreEqual('3 Zeilen auskommentierter Code; die Versionsverwaltung bewahrt ihn auf.', mFindings[0].Message);
  Assert.AreEqual(7, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(9, mFindings[0].Range.EndPos.Line);
  Assert.IsFalse(TRuleProfiles.IsExperimental((TCommentedOutCodeRule.Create as IRule).Descriptor.Id), 'Standard an');
end;

procedure TTodoRulesTests.CommentedCodeFixRemovesLines;
var
  mFindings: TArray<TRuleFinding>;
  mEdit: TRuleEdit;
begin
  mFindings := TRuleAssert.Findings(TCommentedOutCodeRule.Create, cCommentedCode);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('Auskommentierten Code entfernen', mFindings[0].Fixes[0].Title);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes[0].Edits)));
  mEdit := mFindings[0].Fixes[0].Edits[0];
  Assert.AreEqual(7, mEdit.Range.StartPos.Line);
  Assert.AreEqual(0, mEdit.Range.StartPos.Character);
  Assert.AreEqual(10, mEdit.Range.EndPos.Line);
  Assert.AreEqual(0, mEdit.Range.EndPos.Character);
  Assert.AreEqual('', mEdit.NewText);
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
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TCommentedOutCodeRule.Create, InRoutine(
    '  {'#10 +
    '  if Kunde.Aktiv then'#10 +
    '    Kunde.Speichern;'#10 +
    '  Log(''gespeichert'');'#10 +
    '  }'#10 +
    '  Speichern;'#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(5, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(5, mFindings[0].Fixes[0].Edits[0].Range.StartPos.Line);
  Assert.AreEqual(10, mFindings[0].Fixes[0].Edits[0].Range.EndPos.Line);
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
  mSource: string;
begin
  mSource := InRoutine('  // Speichern;'#10'  // Fertig;'#10'  Laden;'#10);
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TCommentedOutCodeRule.Create, mSource,
    '{"rules": {"commented-out-code": {"severity": "hint", "minLines": 2}}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TCommentedOutCodeRule.Create, cCommentedCode,
    '{"rules": {"commented-out-code": {"severity": "hint", "minLines": 4}}}'))));
end;

procedure TTodoRulesTests.CommentedCodeOff;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TCommentedOutCodeRule.Create, cCommentedCode,
    '{"rules": {"commented-out-code": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TCommentedOutCodeRule.Create, cCommentedCode,
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
