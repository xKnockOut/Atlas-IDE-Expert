unit Atlas.Common.Rules.Builtin.LineBreaks.Tests;

// Tests der Regel line-break-split-replace (#2095): #13 und #10 in zwei getrennten Ersetzen machen aus #13#10 zwei
// Zeichen; still, wenn vorher #13#10 ersetzt wird oder #13 verschwindet.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLineBreakRulesTests = class
  public
    /// <summary>Fall aus dem Test mit sLineBreak: StringReplace(…, #13, ' ') und danach #10.</summary>
    [Test]
    procedure SeparateReplaces;
    [Test]
    procedure ReplaceMethodAndHexLiterals;
    [Test]
    procedure SilentCases;
    [Test]
    procedure RuleIsRegistered;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.LineBreaks,
  Atlas.Tests.RuleAssert;

/// <summary>Unit mit der Routine Fall und den Anweisungen AStatements.</summary>
function Source(const AStatements: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'uses'#10'  System.SysUtils, System.StrUtils;'#10 +
    'function Fall(const A: string): string;'#10'begin'#10 + AStatements + 'end;'#10'end.';
end;

function Messages(const AFound: TArray<TRuleFinding>): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in AFound do
  begin
    Result := Result + IntToStr(mFinding.Range.StartPos.Line) + ': ' + mFinding.Message + '|';
  end;
end;

{ TLineBreakRulesTests }

procedure TLineBreakRulesTests.SeparateReplaces;
begin
  Assert.AreEqual('8: #13 und #10 werden einzeln ersetzt (Zeile 8 und hier): Aus einem Windows-Zeilenende #13#10 ' +
    'werden zwei Zeichen. Zuerst #13#10 (sLineBreak) ersetzen, dann die einzelnen.|',
    Messages(TRuleAssert.Findings(TLineBreakSplitReplaceRule.Create, Source(
    '  Result := StringReplace(A, #13, '' '', [rfReplaceAll]);'#10 +
    '  Result := StringReplace(Result, #10, '' '', [rfReplaceAll]);'#10))));
end;

procedure TLineBreakRulesTests.ReplaceMethodAndHexLiterals;
begin
  // Erst #10, dann #13 (ReplaceStr und .Replace); #$D als Schreibweise von #13.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TLineBreakSplitReplaceRule.Create, Source(
    '  Result := ReplaceStr(A, #10, ''|'');'#10'  Result := Result.Replace(#$D, ''|'');'#10)))));
end;

procedure TLineBreakRulesTests.SilentCases;
begin
  // Vorher #13#10 bzw. sLineBreak ersetzt.
  TRuleAssert.Silent(TLineBreakSplitReplaceRule.Create, Source(
    '  Result := StringReplace(A, #13#10, '' '', [rfReplaceAll]);'#10 +
    '  Result := StringReplace(Result, #13, '' '', [rfReplaceAll]);'#10 +
    '  Result := StringReplace(Result, #10, '' '', [rfReplaceAll]);'#10));
  TRuleAssert.Silent(TLineBreakSplitReplaceRule.Create, Source(
    '  Result := A.Replace(sLineBreak, '' '').Replace(#13, '' '').Replace(#10, '' '');'#10));
  // #13 verschwindet bzw. wird zu #10: Aus #13#10 bleibt ein Zeichen.
  TRuleAssert.Silent(TLineBreakSplitReplaceRule.Create, Source(
    '  Result := StringReplace(A, #13, '''', [rfReplaceAll]);'#10 +
    '  Result := StringReplace(Result, #10, '' '', [rfReplaceAll]);'#10));
  TRuleAssert.Silent(TLineBreakSplitReplaceRule.Create, Source(
    '  Result := StringReplace(A, #13, #10, [rfReplaceAll]);'#10 +
    '  Result := StringReplace(Result, #10, '' '', [rfReplaceAll]);'#10));
  TRuleAssert.Silent(TLineBreakSplitReplaceRule.Create, Source(
    '  Result := StringReplace(A, #10, '' '', [rfReplaceAll]);'#10 +
    '  Result := StringReplace(Result, #13, '''', [rfReplaceAll]);'#10));
  // Nur eines der beiden.
  TRuleAssert.Silent(TLineBreakSplitReplaceRule.Create, Source(
    '  Result := StringReplace(A, #10, '' '', [rfReplaceAll]);'#10));
end;

procedure TLineBreakRulesTests.RuleIsRegistered;
var
  mRule: IRule;
  mFound: Boolean;
begin
  mFound := False;
  for mRule in BuiltinRules do
  begin
    mFound := mFound or (mRule.Descriptor.Id = cLineBreakSplitReplaceRuleId);
  end;
  Assert.IsTrue(mFound);
end;

initialization
  TDUnitX.RegisterTestFixture(TLineBreakRulesTests);

end.
