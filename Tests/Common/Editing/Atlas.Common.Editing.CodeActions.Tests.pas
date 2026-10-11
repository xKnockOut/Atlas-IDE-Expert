unit Atlas.Common.Editing.CodeActions.Tests;

// Tests für Code-Aktionen ohne Protokoll (#42, #147).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCodeActionTests = class
  public
    [Test]
    procedure TryFinallyAfterCreate;
    [Test]
    procedure TryFinallyResultCompilesStructurally;
    [Test]
    procedure NoTryFinallyWhenAlreadyProtected;
    [Test]
    procedure ResultGetsTryExceptInsteadOfFree;
    [Test]
    procedure FixAllTakesOnlySafeFixes;
    [Test]
    procedure FixAllSkipsOverlappingFixes;
    [Test]
    procedure OrganizeImportsAsSourceAction;
    [Test]
    procedure MatchesRequestedKinds;
    [Test]
    procedure NoTryFinallyWithoutCreate;
    [Test]
    procedure SuppressLineInsertsCommentAbove;
    [Test]
    procedure SuppressLineExtendsExistingComment;
    [Test]
    procedure SuppressFileAtTop;
    [Test]
    procedure FindingInRangeGivesFixAndSuppressions;
    [Test]
    procedure FindingOutsideRangeIgnored;
    [Test]
    procedure UnusedSuppressionReportedWithRemoval;
    [Test]
    procedure UsedSuppressionNotReported;
    [Test]
    procedure SuppressionForUnknownRuleNotReported;
    [Test]
    procedure SwapAssignmentsIsRewrite;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Editing.CodeActions,
  Atlas.Tests.RuleAssert;

type
  /// <summary>Meldet jeden Bezeichner "Marker".</summary>
  TMarkerRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

function TMarkerRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('marker', TRuleSeverity.Warning, 'Marker');
end;

procedure TMarkerRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Token: TPascalToken;
begin
  for Token in AContext.Tree.Tokens do
    if (Token.Kind = TPascalTokenKind.Identifier) and SameText(Token.Text, 'Marker') then
      AReport.Add(TTextRange.Create(Token.StartPos, Token.EndPos), 'Marker gefunden');
end;

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

function Apply(const AText: string; const AEdit: TRuleEdit): string;
var
  Lines: TArray<string>;
  I, Offset: Integer;
  function OffsetOf(const APos: TTextPosition): Integer;
  var
    L: Integer;
  begin
    Result := 0;
    for L := 0 to APos.Line - 1 do
      Inc(Result, Length(Lines[L]) + 1);
    Inc(Result, APos.Character);
  end;
begin
  Lines := AText.Split([#10]);
  Offset := OffsetOf(AEdit.Range.StartPos);
  I := OffsetOf(AEdit.Range.EndPos);
  Result := Copy(AText, 1, Offset) + AEdit.NewText + Copy(AText, I + 1, MaxInt);
end;

{ TCodeActionTests }

procedure TCodeActionTests.TryFinallyAfterCreate;
var
  Action: TCodeAction;
begin
  Assert.IsTrue(TCodeActions.TryFinally(Body, 4, Action));
  Assert.AreEqual(RewriteKind, Action.Kind);
  Assert.AreEqual(1, Integer(Length(Action.Edits)));
  Assert.AreEqual(4, Action.Edits[0].Range.StartPos.Line);
  Assert.AreEqual(Length('  L := TStringList.Create;'), Action.Edits[0].Range.StartPos.Character);
end;

procedure TCodeActionTests.TryFinallyResultCompilesStructurally;
var
  Action: TCodeAction;
  NewText: string;
begin
  Assert.IsTrue(TCodeActions.TryFinally(Body, 4, Action));
  NewText := Apply(Body, Action.Edits[0]);
  Assert.AreEqual(
    'procedure P;' + LB + 'var' + LB + '  L: TStringList;' + LB + 'begin' + LB +
    '  L := TStringList.Create;' + LB + '  try' + LB + LB + '  finally' + LB + '    L.Free;' + LB + '  end;' + LB +
    '  L.Add(''x'');' + LB + 'end;', NewText);
end;

procedure TCodeActionTests.ResultGetsTryExceptInsteadOfFree;
var
  Action: TCodeAction;
  NewText: string;
begin
  // Ein Rückgabewert darf nicht im finally freigegeben werden, nur im Fehlerfall.
  Assert.IsTrue(TCodeActions.TryFinally('begin' + LB + '  Result := TList.Create;' + LB + 'end;', 1, Action));
  NewText := Apply('begin' + LB + '  Result := TList.Create;' + LB + 'end;', Action.Edits[0]);
  Assert.AreEqual('begin' + LB + '  Result := TList.Create;' + LB + '  try' + LB + LB + '  except' + LB +
    '    Result.Free;' + LB + '    raise;' + LB + '  end;' + LB + 'end;', NewText);
  Assert.AreEqual(0, Pos('finally', NewText));
end;

function FindingWith(ALine: Integer; const ANewText: string; ASafe: Boolean): TRuleFinding;
begin
  Result := Default(TRuleFinding);
  Result.RuleId := 'regel';
  Result.Range := TTextRange.Create(ALine, 0, ALine, 1);
  Result.Fixes := [TRuleFix.Create('Fix', [TRuleEdit.Create(TTextRange.Create(ALine, 0, ALine, 1), ANewText)], ASafe)];
end;

procedure TCodeActionTests.FixAllTakesOnlySafeFixes;
var
  Action: TCodeAction;
begin
  Assert.IsFalse(TCodeActions.FixAll([FindingWith(0, 'a', False)], Action));
  Assert.IsTrue(TCodeActions.FixAll([FindingWith(0, 'a', False), FindingWith(2, 'b', True), FindingWith(4, 'c', True)],
    Action));
  Assert.AreEqual(FixAllKind, Action.Kind);
  Assert.AreEqual(2, Integer(Length(Action.Edits)));
  Assert.AreEqual('b', Action.Edits[0].NewText);
  Assert.AreEqual('c', Action.Edits[1].NewText);
end;

procedure TCodeActionTests.FixAllSkipsOverlappingFixes;
var
  Action: TCodeAction;
begin
  Assert.IsTrue(TCodeActions.FixAll([FindingWith(1, 'a', True), FindingWith(1, 'b', True)], Action));
  Assert.AreEqual(1, Integer(Length(Action.Edits)));
  Assert.AreEqual('a', Action.Edits[0].NewText);
end;

procedure TCodeActionTests.OrganizeImportsAsSourceAction;
var
  Action: TCodeAction;
begin
  Assert.IsTrue(TCodeActions.OrganizeImports('unit A;' + LB + 'interface' + LB + 'uses B, B;' + LB +
    'implementation' + LB + 'end.', False, Action));
  Assert.AreEqual(OrganizeImportsKind, Action.Kind);
  Assert.AreEqual('B', Action.Edits[0].NewText);
  Assert.IsFalse(TCodeActions.OrganizeImports('unit A;' + LB + 'interface' + LB + 'uses B, C;' + LB +
    'implementation' + LB + 'end.', True, Action));
end;

procedure TCodeActionTests.MatchesRequestedKinds;
begin
  Assert.IsTrue(TCodeActions.KindRequested(FixAllKind, nil));
  Assert.IsTrue(TCodeActions.KindRequested(FixAllKind, ['source']));
  Assert.IsTrue(TCodeActions.KindRequested(OrganizeImportsKind, ['source.organizeImports']));
  Assert.IsFalse(TCodeActions.KindRequested(FixAllKind, ['source.organizeImports']));
  Assert.IsFalse(TCodeActions.KindRequested(QuickFixKind, ['source']));
  Assert.IsFalse(TCodeActions.KindRequested('sourceX', ['source']));
end;

procedure TCodeActionTests.NoTryFinallyWhenAlreadyProtected;
var
  Action: TCodeAction;
begin
  Assert.IsFalse(TCodeActions.TryFinally('begin' + LB + '  L := T.Create;' + LB + LB + '  try' + LB + 'end;', 1, Action));
end;

procedure TCodeActionTests.NoTryFinallyWithoutCreate;
var
  Action: TCodeAction;
begin
  Assert.IsFalse(TCodeActions.TryFinally(Body, 5, Action));
  Assert.IsFalse(TCodeActions.TryFinally(Body, 2, Action));
end;

procedure TCodeActionTests.SuppressLineInsertsCommentAbove;
var
  Edit: TRuleEdit;
begin
  Edit := TCodeActions.SuppressLine(Body, 5, 'marker');
  Assert.AreEqual(5, Edit.Range.StartPos.Line);
  Assert.AreEqual(0, Edit.Range.StartPos.Character);
  Assert.AreEqual('  // lsp-ignore: marker' + LB, Edit.NewText);
end;

procedure TCodeActionTests.SuppressLineExtendsExistingComment;
var
  Edit: TRuleEdit;
begin
  Edit := TCodeActions.SuppressLine('begin' + LB + '  // lsp-ignore: a' + LB + '  X;' + LB + 'end;', 2, 'b');
  Assert.AreEqual(1, Edit.Range.StartPos.Line);
  Assert.AreEqual(Length('  // lsp-ignore: a'), Edit.Range.StartPos.Character);
  Assert.AreEqual(', b', Edit.NewText);
end;

procedure TCodeActionTests.SuppressFileAtTop;
var
  Edit: TRuleEdit;
begin
  Edit := TCodeActions.SuppressFile('unit U;' + #10, 'marker');
  Assert.AreEqual(0, Edit.Range.StartPos.Line);
  Assert.AreEqual('// lsp-ignore-file: marker' + #10, Edit.NewText);
end;

procedure TCodeActionTests.FindingInRangeGivesFixAndSuppressions;
var
  Finding: TRuleFinding;
  Actions: TArray<TCodeAction>;
begin
  Finding := Default(TRuleFinding);
  Finding.RuleId := 'marker';
  Finding.Range := TTextRange.Create(5, 2, 5, 3);
  Finding.Fixes := [TRuleFix.Create('Beheben', [TRuleEdit.Create(Finding.Range, 'M')])];
  Actions := TCodeActions.ForFindings([Finding], Body, TTextRange.Create(5, 0, 5, 0));
  Assert.AreEqual(3, Integer(Length(Actions)));
  Assert.AreEqual('Beheben', Actions[0].Title);
  Assert.IsTrue(Actions[0].IsPreferred);
  Assert.AreEqual(QuickFixKind, Actions[1].Kind);
  Assert.AreEqual('marker', Actions[2].RuleId);
end;

procedure TCodeActionTests.FindingOutsideRangeIgnored;
var
  Finding: TRuleFinding;
begin
  Finding := Default(TRuleFinding);
  Finding.RuleId := 'marker';
  Finding.Range := TTextRange.Create(1, 0, 1, 3);
  Assert.AreEqual(0, Integer(Length(TCodeActions.ForFindings([Finding], Body, TTextRange.Create(5, 0, 5, 0)))));
end;

procedure TCodeActionTests.UnusedSuppressionReportedWithRemoval;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TMarkerRule.Create,
    'unit U; interface implementation' + LB + '  // lsp-ignore: marker' + LB + 'var X: Integer;' + LB + 'end.');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(UnusedSuppressionRuleId, Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  // Eigene Zeile: Die ganze Zeile entfällt.
  Assert.AreEqual(1, Findings[0].Fixes[0].Edits[0].Range.StartPos.Line);
  Assert.AreEqual(0, Findings[0].Fixes[0].Edits[0].Range.StartPos.Character);
  Assert.AreEqual(2, Findings[0].Fixes[0].Edits[0].Range.EndPos.Line);
  // Ungenutzte Unterdrückungen zu entfernen ist sicher und läuft über source.fixAll (#182).
  Assert.IsTrue(Findings[0].Fixes[0].Safe);
end;

procedure TCodeActionTests.UsedSuppressionNotReported;
begin
  TRuleAssert.Silent(TMarkerRule.Create,
    'unit U; interface implementation' + LB + '  // lsp-ignore: marker' + LB + 'var Marker: Integer;' + LB + 'end.');
end;

procedure TCodeActionTests.SuppressionForUnknownRuleNotReported;
begin
  TRuleAssert.Silent(TMarkerRule.Create,
    'unit U; interface implementation' + LB + 'var X: Integer; // lsp-ignore: other-rule' + LB + 'end.');
end;

procedure TCodeActionTests.SwapAssignmentsIsRewrite;
var
  Action: TCodeAction;
begin
  Assert.IsTrue(TCodeActions.SwapAssignments('  A := B;', TTextRange.Create(0, 0, 0, 0), nil, Action));
  Assert.AreEqual(RewriteKind, Action.Kind);
  Assert.AreEqual('  B := A;', Action.Edits[0].NewText);
  Assert.IsFalse(TCodeActions.SwapAssignments('  A := F(B);', TTextRange.Create(0, 0, 0, 0), nil, Action));
end;

initialization
  TDUnitX.RegisterTestFixture(TCodeActionTests);

end.
