unit Atlas.Common.Rules.CodeActions.Tests;

// Tests für die Brücke von Regeltreffern zu Code-Aktionen (#42, #182).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleCodeActionTests = class
  public
    [Test]
    procedure FixAllTakesOnlySafeFixes;
    [Test]
    procedure FixAllSkipsOverlappingFixes;
    [Test]
    procedure FindingInRangeGivesFixAndSuppressions;
    [Test]
    procedure AlternativeFixesCarryNoFixTag;
    [Test]
    procedure FindingOutsideRangeIgnored;
    [Test]
    procedure ForRangeAddsTryFinally;
    [Test]
    procedure FixWithOtherFiles;
    [Test]
    procedure UnitRelationsFixRunsClientCommand;
    [Test]
    procedure SuppressLineInsertsCommentAbove;
    [Test]
    procedure SuppressLineExtendsExistingComment;
    /// <summary>Zeilen auch bei CR allein getrennt (TTextLines.SplitLines).</summary>
    [Test]
    procedure SuppressLineInCrOnlyText;
    [Test]
    procedure SuppressFileAtTop;
    [Test]
    procedure UnusedSuppressionReportedWithRemoval;
    [Test]
    procedure UsedSuppressionNotReported;
    [Test]
    procedure SuppressionForUnknownRuleNotReported;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.Rules.CodeActions,
  Atlas.Tests.RuleAssert,
  Atlas.Common.Findings.Suppressions;

const
  cLB = #13#10;
  cBody =
    'procedure P;' + cLB +
    'var' + cLB +
    '  L: TStringList;' + cLB +
    'begin' + cLB +
    '  L := TStringList.Create;' + cLB +
    '  L.Add(''x'');' + cLB +
    'end;';

function FindingWith(ALine: Integer; const ANewText: string; ASafe: Boolean): TRuleFinding;
begin
  Result := Default(TRuleFinding);
  Result.RuleId := 'regel';
  Result.Range := TTextRange.Create(ALine, 0, ALine, 1);
  Result.Fixes := [TRuleFix.Create('Fix', [TRuleEdit.Create(TTextRange.Create(ALine, 0, ALine, 1), ANewText)], ASafe)];
end;

{ TRuleCodeActionTests }

procedure TRuleCodeActionTests.FixAllTakesOnlySafeFixes;
var
  mAction: TCodeAction;
begin
  Assert.IsFalse(TRuleCodeActions.FixAll([FindingWith(0, 'a', False)], mAction));
  Assert.IsTrue(TRuleCodeActions.FixAll([FindingWith(0, 'a', False), FindingWith(2, 'b', True), FindingWith(4, 'c', True)],
    mAction));
  Assert.AreEqual(cFixAllKind, mAction.Kind);
  Assert.AreEqual(2, Integer(Length(mAction.Edits)));
  Assert.AreEqual('b', mAction.Edits[0].NewText);
  Assert.AreEqual('c', mAction.Edits[1].NewText);
end;

procedure TRuleCodeActionTests.FixAllSkipsOverlappingFixes;
var
  mAction: TCodeAction;
begin
  Assert.IsTrue(TRuleCodeActions.FixAll([FindingWith(1, 'a', True), FindingWith(1, 'b', True)], mAction));
  Assert.AreEqual(1, Integer(Length(mAction.Edits)));
  Assert.AreEqual('a', mAction.Edits[0].NewText);
end;

procedure TRuleCodeActionTests.FindingInRangeGivesFixAndSuppressions;
var
  mFinding: TRuleFinding;
  mActions: TArray<TCodeAction>;
begin
  mFinding := Default(TRuleFinding);
  mFinding.RuleId := 'marker';
  mFinding.Range := TTextRange.Create(5, 2, 5, 3);
  mFinding.Fixes := [TRuleFix.Create('Beheben', [TRuleEdit.Create(mFinding.Range, 'M')])];
  mActions := TRuleCodeActions.ForFindings([mFinding], cBody, TTextRange.Create(5, 0, 5, 0));
  Assert.AreEqual(3, Integer(Length(mActions)));
  Assert.AreEqual('Beheben', mActions[0].Title);
  Assert.IsTrue(mActions[0].IsPreferred);
  Assert.AreEqual(cQuickFixKind, mActions[1].Kind);
  Assert.AreEqual('marker', mActions[2].RuleId);
  // Fenster „Atlas-Prüfung“ und Befund-Hover wählen über die Tags (#909).
  Assert.AreEqual(cRuleFixTag, mActions[0].Tag);
  Assert.AreEqual(cRuleSuppressLineTag, mActions[1].Tag);
  Assert.AreEqual(cRuleSuppressFileTag, mActions[2].Tag);
end;

procedure TRuleCodeActionTests.AlternativeFixesCarryNoFixTag;
var
  mFinding: TRuleFinding;
  mFix: TRuleFix;
  mActions: TArray<TCodeAction>;
begin
  mFinding := Default(TRuleFinding);
  mFinding.RuleId := 'marker';
  mFinding.Range := TTextRange.Create(5, 2, 5, 3);
  mFix := TRuleFix.Create('A', [TRuleEdit.Create(mFinding.Range, 'A')]);
  mFix.Alternative := True;
  mFinding.Fixes := [mFix];
  mActions := TRuleCodeActions.ForFindings([mFinding], cBody, TTextRange.Create(5, 0, 5, 0));
  Assert.AreEqual('', mActions[0].Tag);
  Assert.IsFalse(mActions[0].IsPreferred);
end;

procedure TRuleCodeActionTests.FindingOutsideRangeIgnored;
var
  mFinding: TRuleFinding;
begin
  mFinding := Default(TRuleFinding);
  mFinding.RuleId := 'marker';
  mFinding.Range := TTextRange.Create(1, 0, 1, 3);
  Assert.AreEqual(0, Integer(Length(TRuleCodeActions.ForFindings([mFinding], cBody, TTextRange.Create(5, 0, 5, 0)))));
end;

procedure TRuleCodeActionTests.ForRangeAddsTryFinally;
var
  mActions: TArray<TCodeAction>;
begin
  mActions := TRuleCodeActions.ForRange(nil, cBody, TTextRange.Create(4, 0, 4, 0));
  Assert.AreEqual(1, Integer(Length(mActions)));
  Assert.AreEqual('', mActions[0].RuleId);
end;

procedure TRuleCodeActionTests.FixWithOtherFiles;
var
  mFinding: TRuleFinding;
  mOther: TRuleFileEdits;
  mActions: TArray<TCodeAction>;
  mAction: TCodeAction;
begin
  // Korrektur über mehrere Units (#1105): alle Dateien in einer Aktion, aber nie in source.fixAll.
  mFinding := FindingWith(2, 'X', True);
  mOther.FileName := 'C:\P\Andere.pas';
  mOther.Edits := [TRuleEdit.Create(TTextRange.Create(1, 0, 1, 1), 'Y')];
  mFinding.Fixes[0].OtherFiles := [mOther];
  mActions := TRuleCodeActions.ForFindings([mFinding], cBody, TTextRange.Create(2, 0, 2, 0));
  Assert.AreEqual('X', mActions[0].Edits[0].NewText);
  Assert.AreEqual(1, Integer(Length(mActions[0].FileEdits)));
  Assert.AreEqual('C:\P\Andere.pas', mActions[0].FileEdits[0].FileName);
  Assert.AreEqual('Y', mActions[0].FileEdits[0].Edits[0].NewText);
  Assert.IsFalse(TRuleCodeActions.FixAll([mFinding], mAction));
end;

procedure TRuleCodeActionTests.UnitRelationsFixRunsClientCommand;
var
  mFinding: TRuleFinding;
  mActions: TArray<TCodeAction>;
begin
  // „Graph zeigen“ an einem Unit-Zyklus (#896): ohne Änderung, mit Client-Befehl.
  mFinding := Default(TRuleFinding);
  mFinding.RuleId := 'uses-cycle';
  mFinding.Range := TTextRange.Create(5, 2, 5, 3);
  mFinding.Fixes := [TRuleFix.UnitRelations('Graph zeigen (Unit-Beziehungen)')];
  mActions := TRuleCodeActions.ForFindings([mFinding], cBody, TTextRange.Create(5, 0, 5, 0));
  Assert.AreEqual('Graph zeigen (Unit-Beziehungen)', mActions[0].Title);
  Assert.AreEqual(cShowUnitRelationsCommand, mActions[0].Command);
  Assert.AreEqual(0, Integer(Length(mActions[0].Edits)));
end;

procedure TRuleCodeActionTests.SuppressLineInsertsCommentAbove;
var
  mEdit: TRuleEdit;
begin
  mEdit := TRuleCodeActions.SuppressLine(cBody, 5, 'marker');
  Assert.AreEqual(5, mEdit.Range.StartPos.Line);
  Assert.AreEqual(0, mEdit.Range.StartPos.Character);
  Assert.AreEqual('  // lsp-ignore: marker' + cLB, mEdit.NewText);
end;

procedure TRuleCodeActionTests.SuppressLineExtendsExistingComment;
var
  mEdit: TRuleEdit;
begin
  mEdit := TRuleCodeActions.SuppressLine('begin' + cLB + '  // lsp-ignore: a' + cLB + '  X;' + cLB + 'end;', 2, 'b');
  Assert.AreEqual(1, mEdit.Range.StartPos.Line);
  Assert.AreEqual(Integer(Length('  // lsp-ignore: a')), mEdit.Range.StartPos.Character);
  Assert.AreEqual(', b', mEdit.NewText);
end;

procedure TRuleCodeActionTests.SuppressLineInCrOnlyText;
var
  mEdit: TRuleEdit;
begin
  mEdit := TRuleCodeActions.SuppressLine('begin'#13'  // lsp-ignore: a'#13'  X;'#13'end;', 2, 'b');
  Assert.AreEqual(1, mEdit.Range.StartPos.Line);
  Assert.AreEqual(Integer(Length('  // lsp-ignore: a')), mEdit.Range.StartPos.Character);
  Assert.AreEqual(', b', mEdit.NewText);
end;

procedure TRuleCodeActionTests.SuppressFileAtTop;
var
  mEdit: TRuleEdit;
begin
  mEdit := TRuleCodeActions.SuppressFile('unit U;' + #10, 'marker');
  Assert.AreEqual(0, mEdit.Range.StartPos.Line);
  Assert.AreEqual('// lsp-ignore-file: marker' + #10, mEdit.NewText);
end;

procedure TRuleCodeActionTests.UnusedSuppressionReportedWithRemoval;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TMarkerRule.Create,
    'unit U; interface implementation' + cLB + '  // lsp-ignore: marker' + cLB + 'var X: Integer;' + cLB + 'end.');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(cUnusedSuppressionRuleId, mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  // Eigene Zeile: Die ganze Zeile entfällt.
  Assert.AreEqual(1, mFindings[0].Fixes[0].Edits[0].Range.StartPos.Line);
  Assert.AreEqual(0, mFindings[0].Fixes[0].Edits[0].Range.StartPos.Character);
  Assert.AreEqual(2, mFindings[0].Fixes[0].Edits[0].Range.EndPos.Line);
  // Ungenutzte Unterdrückungen zu entfernen ist sicher und läuft über source.fixAll (#182).
  Assert.IsTrue(mFindings[0].Fixes[0].Safe);
end;

procedure TRuleCodeActionTests.UsedSuppressionNotReported;
begin
  TRuleAssert.Silent(TMarkerRule.Create,
    'unit U; interface implementation' + cLB + '  // lsp-ignore: marker' + cLB + 'var Marker: Integer;' + cLB + 'end.');
end;

procedure TRuleCodeActionTests.SuppressionForUnknownRuleNotReported;
begin
  // Kennung einer Regel, die hier nicht lief: keine unused-suppression (unbekannte Kennungen siehe #41).
  TRuleAssert.Silent(TMarkerRule.Create,
    'unit U; interface implementation' + cLB + 'var X: Integer; // lsp-ignore: empty-except' + cLB + 'end.');
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleCodeActionTests);

end.
