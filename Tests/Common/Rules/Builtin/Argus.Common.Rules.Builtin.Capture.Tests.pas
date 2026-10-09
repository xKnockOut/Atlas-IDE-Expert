unit Argus.Common.Rules.Builtin.Capture.Tests;

// Tests für captured-loop-variable (#116).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCaptureRuleTests = class
  public
    [Test]
    procedure ForInVariableInQueueReports;
    [Test]
    procedure SynchronizeIsSilent;
    [Test]
    procedure VariableChangedInWhileLoopReports;
    [Test]
    procedure VariableNotChangedAfterCaptureIsSilent;
    [Test]
    procedure ClassicForCounterIsSilent;
    [Test]
    procedure InlineForVariableReports;
    [Test]
    procedure EventPropertyIsMedium;
    [Test]
    procedure CustomDeferredApiFromOptions;
    [Test]
    procedure FixCopiesValuePerIteration;
  end;

implementation

uses
  System.SysUtils,
  Argus.Common.Documents.Contract,
  Argus.Common.Configuration.Contract,
  Argus.Common.Rules.Contract,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Pascal.Parser,
  Argus.Common.Rules.Builtin.Capture,
  Argus.Tests.RuleAssert;

function Routine(const ABody: string; const AVars: string = ''): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10 + AVars + 'begin'#10 + ABody +
    #10'end;'#10'end.';
end;

const
  QueueLoop = '  for S in Liste do'#10'    TThread.Queue(nil, procedure begin Memo1.Lines.Add(S); end);';
  StringVar = 'var'#10'  S: string;'#10;

/// <summary>Wendet alle Änderungen der ersten Korrektur an, von hinten nach vorn (Zeilen mit #10).</summary>
function ApplyFix(const AText: string; const AFix: TRuleFix): string;
var
  Index: Integer;
  Edit: TRuleEdit;

  function OffsetOf(const APosition: TTextPosition): Integer;
  var
    Line, Position: Integer;
  begin
    Position := 0;
    for Line := 1 to APosition.Line do
      Position := Pos(#10, AText, Position + 1);
    Result := Position + APosition.Character;
  end;

begin
  Result := AText;
  for Index := High(AFix.Edits) downto 0 do
  begin
    Edit := AFix.Edits[Index];
    Result := Copy(Result, 1, OffsetOf(Edit.Range.StartPos)) + Edit.NewText +
      Copy(Result, OffsetOf(Edit.Range.EndPos) + 1, MaxInt);
  end;
end;

procedure TCaptureRuleTests.ForInVariableInQueueReports;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TCapturedLoopVariableRule.Create, Routine(QueueLoop, StringVar));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual(8, Findings[0].Range.StartPos.Line);
end;

procedure TCaptureRuleTests.SynchronizeIsSilent;
begin
  TRuleAssert.Silent(TCapturedLoopVariableRule.Create,
    Routine(StringReplace(QueueLoop, 'Queue', 'Synchronize', []), StringVar));
end;

procedure TCaptureRuleTests.VariableChangedInWhileLoopReports;
begin
  TRuleAssert.Reports(TCapturedLoopVariableRule.Create,
    Routine('  I := 0;'#10'  while I < 3 do'#10'  begin'#10'    TTask.Run(procedure begin Foo(I); end);'#10 +
      '    Inc(I);'#10'  end;', 'var'#10'  I: Integer;'#10));
end;

procedure TCaptureRuleTests.VariableNotChangedAfterCaptureIsSilent;
begin
  TRuleAssert.Silent(TCapturedLoopVariableRule.Create,
    Routine('  I := 5;'#10'  TTask.Run(procedure begin Foo(I); end);', 'var'#10'  I: Integer;'#10));
end;

procedure TCaptureRuleTests.ClassicForCounterIsSilent;
begin
  TRuleAssert.Silent(TCapturedLoopVariableRule.Create,
    Routine('  for I := 1 to 3 do'#10'    TTask.Run(procedure begin Foo(I); end);', 'var'#10'  I: Integer;'#10));
end;

procedure TCaptureRuleTests.InlineForVariableReports;
begin
  TRuleAssert.Reports(TCapturedLoopVariableRule.Create,
    Routine('  for var I := 1 to 3 do'#10'    TTask.Run(procedure begin Foo(I); end);'));
end;

procedure TCaptureRuleTests.EventPropertyIsMedium;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TCapturedLoopVariableRule.Create,
    Routine('  for S in Liste do'#10'    F.OnDone := procedure begin Log(S); end;', StringVar));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
end;

procedure TCaptureRuleTests.CustomDeferredApiFromOptions;
var
  Source: string;
begin
  Source := Routine('  for S in Liste do'#10'    Pool.Post(procedure begin Log(S); end);', StringVar);
  TRuleAssert.Silent(TCapturedLoopVariableRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TCapturedLoopVariableRule.Create, Source,
    '{"rules": {"captured-loop-variable": {"deferredApis": ["Pool.Post"]}}}'))));
end;

procedure TCaptureRuleTests.FixCopiesValuePerIteration;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
  Tree: TSyntaxTree;
begin
  Source := Routine(QueueLoop, StringVar);
  Findings := TRuleAssert.Findings(TCapturedLoopVariableRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Fixed := ApplyFix(Source, Findings[0].Fixes[0]);
  Assert.AreEqual(Routine('  for S in Liste do'#10'    TThread.Queue(nil, CaptureS(S));',
    StringVar + '  function CaptureS(const AValue: string): TProc;'#10'  begin'#10 +
    '    Result := procedure begin Memo1.Lines.Add(AValue); end;'#10'  end;'#10#10), Fixed);
  Tree := TPascalParser.Parse(Fixed);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)));
  finally
    Tree.Free;
  end;
  TRuleAssert.Silent(TCapturedLoopVariableRule.Create, Fixed);
end;

initialization
  TDUnitX.RegisterTestFixture(TCaptureRuleTests);

end.
