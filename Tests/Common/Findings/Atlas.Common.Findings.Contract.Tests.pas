unit Atlas.Common.Findings.Contract.Tests;

// Tests der Befund-Wertetypen: Korrekturen setzen jedes Feld, Kennwörter der Konfidenz.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFindingsContractTests = class
  public
    [Test]
    procedure CreateClearsJumpAndOtherFiles;
    [Test]
    procedure CreateWithoutSafeIsUnsafe;
    [Test]
    procedure JumpHasTargetAndNoEdits;
    [Test]
    procedure SignatureHelpJumpsAndOpensHint;
    [Test]
    procedure UnitRelationsShowsGraphOnly;
    [Test]
    procedure ConfidenceNamesAndTexts;
    [Test]
    procedure SeverityNames;
  end;

implementation

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Findings.Contract;

{ TFindingsContractTests }

procedure TFindingsContractTests.CreateClearsJumpAndOtherFiles;
var
  mFix: TRuleFix;
begin
  mFix := TRuleFix.Create('Titel', [TTextEdit.Create(TTextRange.Create(1, 2, 1, 4), 'x')], True);
  Assert.AreEqual('Titel', mFix.Title);
  Assert.AreEqual(1, Integer(Length(mFix.Edits)));
  Assert.IsTrue(mFix.Safe);
  Assert.IsFalse(mFix.Alternative);
  Assert.IsFalse(mFix.HasJump);
  Assert.IsFalse(mFix.OpensSignature);
  Assert.IsFalse(mFix.ShowsUnitRelations);
  Assert.AreEqual('', mFix.FileName);
  Assert.AreEqual(0, Integer(Length(mFix.OtherFiles)));
  mFix := Default(TRuleFix);
end;

procedure TFindingsContractTests.CreateWithoutSafeIsUnsafe;
var
  mFix: TRuleFix;
begin
  mFix := TRuleFix.Create('Titel', nil);
  Assert.IsFalse(mFix.Safe);
  mFix := Default(TRuleFix);
end;

procedure TFindingsContractTests.JumpHasTargetAndNoEdits;
var
  mFix: TRuleFix;
  mTarget: TTextPosition;
begin
  mTarget := TTextPosition.Create(3, 7);
  mFix := TRuleFix.Jump('Springen', mTarget);
  Assert.IsTrue(mFix.HasJump);
  Assert.AreEqual(3, mFix.JumpTo.Line);
  Assert.AreEqual(7, mFix.JumpTo.Character);
  Assert.AreEqual(0, Integer(Length(mFix.Edits)));
  Assert.IsFalse(mFix.OpensSignature);
  mFix := Default(TRuleFix);
end;

procedure TFindingsContractTests.SignatureHelpJumpsAndOpensHint;
var
  mFix: TRuleFix;
begin
  mFix := TRuleFix.SignatureHelp('Parameter', TTextPosition.Create(2, 5));
  Assert.IsTrue(mFix.HasJump);
  Assert.IsTrue(mFix.OpensSignature);
  Assert.AreEqual(5, mFix.JumpTo.Character);
  mFix := Default(TRuleFix);
end;

procedure TFindingsContractTests.UnitRelationsShowsGraphOnly;
var
  mFix: TRuleFix;
begin
  mFix := TRuleFix.UnitRelations('Graph');
  Assert.IsTrue(mFix.ShowsUnitRelations);
  Assert.IsFalse(mFix.HasJump);
  Assert.AreEqual(0, Integer(Length(mFix.Edits)));
  mFix := Default(TRuleFix);
end;

procedure TFindingsContractTests.ConfidenceNamesAndTexts;
begin
  Assert.AreEqual('low', ConfidenceName(TRuleConfidence.Low));
  Assert.AreEqual('medium', ConfidenceName(TRuleConfidence.Medium));
  Assert.AreEqual('high', ConfidenceName(TRuleConfidence.High));
  Assert.AreEqual('niedrig', ConfidenceText(TRuleConfidence.Low));
  Assert.AreEqual('mittel', ConfidenceText(TRuleConfidence.Medium));
  Assert.AreEqual('hoch', ConfidenceText(TRuleConfidence.High));
end;

procedure TFindingsContractTests.SeverityNames;
begin
  Assert.AreEqual('error', SeverityName(TRuleSeverity.Error));
  Assert.AreEqual('warning', SeverityName(TRuleSeverity.Warning));
  Assert.AreEqual('info', SeverityName(TRuleSeverity.Information));
  Assert.AreEqual('hint', SeverityName(TRuleSeverity.Hint));
end;

initialization
  TDUnitX.RegisterTestFixture(TFindingsContractTests);

end.
