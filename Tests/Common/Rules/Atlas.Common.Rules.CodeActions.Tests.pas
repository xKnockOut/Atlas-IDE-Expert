unit Atlas.Common.Rules.CodeActions.Tests;

// Tests für die Brücke von Regeltreffern zu Code-Aktionen (#42, #182). Lagen bis A-11
// in Atlas.Common.Editing.CodeActions.Tests.

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
    procedure FindingOutsideRangeIgnored;
    [Test]
    procedure ForRangeAddsTryFinally;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Rules.CodeActions;

const
  LB = #13#10;
  Body =
    'procedure P;' + LB +
    'var' + LB +
    '  L: TStringList;' + LB +
    'begin' + LB +
    '  L := TStringList.Create;' + LB +
    '  L.Add(''x'');' + LB +
    'end;';

function FindingWith(ALine: Integer; const ANewText: string; ASafe: Boolean): TRuleFinding;
begin
  Result := Default(TRuleFinding);
  Result.RuleId := 'regel';
  Result.Range := TTextRange.Create(ALine, 0, ALine, 1);
  Result.Fixes := [TRuleFix.Create('Fix', [TRuleEdit.Create(TTextRange.Create(ALine, 0, ALine, 1), ANewText)], ASafe)];
end;

procedure TRuleCodeActionTests.FixAllTakesOnlySafeFixes;
var
  Action: TCodeAction;
begin
  Assert.IsFalse(TRuleCodeActions.FixAll([FindingWith(0, 'a', False)], Action));
  Assert.IsTrue(TRuleCodeActions.FixAll([FindingWith(0, 'a', False), FindingWith(2, 'b', True), FindingWith(4, 'c', True)],
    Action));
  Assert.AreEqual(FixAllKind, Action.Kind);
  Assert.AreEqual(2, Integer(Length(Action.Edits)));
  Assert.AreEqual('b', Action.Edits[0].NewText);
  Assert.AreEqual('c', Action.Edits[1].NewText);
end;

procedure TRuleCodeActionTests.FixAllSkipsOverlappingFixes;
var
  Action: TCodeAction;
begin
  Assert.IsTrue(TRuleCodeActions.FixAll([FindingWith(1, 'a', True), FindingWith(1, 'b', True)], Action));
  Assert.AreEqual(1, Integer(Length(Action.Edits)));
  Assert.AreEqual('a', Action.Edits[0].NewText);
end;

procedure TRuleCodeActionTests.FindingInRangeGivesFixAndSuppressions;
var
  Finding: TRuleFinding;
  Actions: TArray<TCodeAction>;
begin
  Finding := Default(TRuleFinding);
  Finding.RuleId := 'marker';
  Finding.Range := TTextRange.Create(5, 2, 5, 3);
  Finding.Fixes := [TRuleFix.Create('Beheben', [TRuleEdit.Create(Finding.Range, 'M')])];
  Actions := TRuleCodeActions.ForFindings([Finding], Body, TTextRange.Create(5, 0, 5, 0));
  Assert.AreEqual(3, Integer(Length(Actions)));
  Assert.AreEqual('Beheben', Actions[0].Title);
  Assert.IsTrue(Actions[0].IsPreferred);
  Assert.AreEqual(QuickFixKind, Actions[1].Kind);
  Assert.AreEqual('marker', Actions[2].RuleId);
end;

procedure TRuleCodeActionTests.FindingOutsideRangeIgnored;
var
  Finding: TRuleFinding;
begin
  Finding := Default(TRuleFinding);
  Finding.RuleId := 'marker';
  Finding.Range := TTextRange.Create(1, 0, 1, 3);
  Assert.AreEqual(0, Integer(Length(TRuleCodeActions.ForFindings([Finding], Body, TTextRange.Create(5, 0, 5, 0)))));
end;

procedure TRuleCodeActionTests.ForRangeAddsTryFinally;
var
  Actions: TArray<TCodeAction>;
begin
  Actions := TRuleCodeActions.ForRange(nil, Body, TTextRange.Create(4, 0, 4, 0));
  Assert.AreEqual(1, Integer(Length(Actions)));
  Assert.AreEqual('', Actions[0].RuleId);
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleCodeActionTests);

end.
