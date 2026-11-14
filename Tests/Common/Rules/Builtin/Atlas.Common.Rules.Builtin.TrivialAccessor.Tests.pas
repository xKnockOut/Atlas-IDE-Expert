unit Atlas.Common.Rules.Builtin.TrivialAccessor.Tests;

// Tests für trivial-accessor (#717): stumm ohne refactoring.inlineAccessorDiagnostic
// bzw. mit refactoring.inlineAccessor aus, Hinweis an trivialem Getter und
// Setter, Gleichheitsprüfung nach refactoring.inlineAccessorEqualityCheck,
// Setter mit Benachrichtigung stumm.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTrivialAccessorRuleTests = class
  public
    [Test]
    procedure SilentByDefault;
    [Test]
    procedure ReportsTrivialAccessors;
    [Test]
    procedure EqualityCheckFollowsSetting;
    [Test]
    procedure SwitchedOffWithAction;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.TrivialAccessor,
  Atlas.Tests.RuleAssert;

const
  cText =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '  private'#10 +
    '    FName: string;'#10 +
    '    FSize: Integer;'#10 +
    '    FColor: Integer;'#10 +
    '    function GetName: string;'#10 +                         // 8
    '    procedure SetSize(const Value: Integer);'#10 +          // 9
    '    procedure SetColor(const Value: Integer);'#10 +
    '  public'#10 +
    '    property Name: string read GetName;'#10 +
    '    property Size: Integer read FSize write SetSize;'#10 +
    '    property Color: Integer read FColor write SetColor;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TFoo.GetName: string;'#10'begin'#10'  Result := FName;'#10'end;'#10 +
    'procedure TFoo.SetSize(const Value: Integer);'#10'begin'#10'  if FSize <> Value then'#10 +
    '    FSize := Value;'#10'end;'#10 +
    'procedure TFoo.SetColor(const Value: Integer);'#10'begin'#10'  FColor := Value;'#10'  Invalidate;'#10'end;'#10 +
    'end.';
  cEnabled = '{"refactoring": {"inlineAccessorDiagnostic": true}}';

procedure TTrivialAccessorRuleTests.SilentByDefault;
begin
  TRuleAssert.Silent(TTrivialAccessorRule.Create, cText);
end;

procedure TTrivialAccessorRuleTests.ReportsTrivialAccessors;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TTrivialAccessorRule.Create, cText, cEnabled);
  Assert.AreEqual(2, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(mFindings[0].Confidence));
  Assert.AreEqual('GetName liefert nur FName: Die Property kann direkt auf das Feld zeigen (Glühbirne ' +
    '„Zugriffsmethode durch Feld ersetzen“).', mFindings[0].Message);
  Assert.AreEqual(8, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(13, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual(9, mFindings[1].Range.StartPos.Line);
  Assert.IsTrue(mFindings[1].Message.StartsWith('SetSize setzt nur FSize'), mFindings[1].Message);
end;

procedure TTrivialAccessorRuleTests.EqualityCheckFollowsSetting;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TTrivialAccessorRule.Create, cText,
    '{"refactoring": {"inlineAccessorDiagnostic": true, "inlineAccessorEqualityCheck": false}}');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(8, mFindings[0].Range.StartPos.Line);
end;

procedure TTrivialAccessorRuleTests.SwitchedOffWithAction;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TTrivialAccessorRule.Create, cText,
    '{"refactoring": {"inlineAccessorDiagnostic": true, "inlineAccessor": false}}'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TTrivialAccessorRuleTests);

end.
