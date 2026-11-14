unit Atlas.Common.Rules.SuppressionStats.Tests;

// Tests für die Auswertung der Unterdrückungskommentare (#147).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSuppressionStatsTests = class
  public
    [Test]
    procedure CountsLineAndFileSuppressionsPerRule;
    [Test]
    procedure CountsFilesOncePerRule;
    [Test]
    procedure CountsUnusedFromEngineFindings;
    [Test]
    procedure SortsByTotalThenId;
    [Test]
    procedure RendersJson;
    [Test]
    procedure RendersTextSummary;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Output,
  Atlas.Common.Rules.SuppressionStats;

const
  cCode =
    '// lsp-ignore-file: regel-a' + sLineBreak +
    'unit U;' + sLineBreak +
    'interface' + sLineBreak +
    'implementation' + sLineBreak +
    'procedure P;' + sLineBreak +
    'begin' + sLineBreak +
    '  // lsp-ignore: regel-b, regel-a' + sLineBreak +
    '  X := 1;' + sLineBreak +
    '  Y := 2; // lsp-ignore: regel-b' + sLineBreak +
    'end;' + sLineBreak +
    'end.';

function Unused(ALine: Integer): TRuleFinding;
begin
  Result := Default(TRuleFinding);
  Result.RuleId := cUnusedSuppressionRuleId;
  Result.Range := TTextRange.Create(TTextPosition.Create(ALine, 0), TTextPosition.Create(ALine + 1, 0));
end;

function Find(AStats: TSuppressionStats; const AId: string): TSuppressionCount;
var
  mCount: TSuppressionCount;
begin
  for mCount in AStats.Counts do
  begin
    if mCount.RuleId = AId then
    begin
      Exit(mCount);
    end;
  end;
  Result := Default(TSuppressionCount);
end;

{ TSuppressionStatsTests }

procedure TSuppressionStatsTests.CountsLineAndFileSuppressionsPerRule;
var
  mStats: TSuppressionStats;
begin
  mStats := TSuppressionStats.Create;
  try
    mStats.Add(cCode, nil);
    Assert.AreEqual(1, Find(mStats, 'regel-a').FileCount);
    Assert.AreEqual(1, Find(mStats, 'regel-a').LineCount);
    Assert.AreEqual(0, Find(mStats, 'regel-b').FileCount);
    Assert.AreEqual(2, Find(mStats, 'regel-b').LineCount);
    Assert.AreEqual(2, Find(mStats, 'regel-b').Total);
  finally
    mStats.Free;
  end;
end;

procedure TSuppressionStatsTests.CountsFilesOncePerRule;
var
  mStats: TSuppressionStats;
begin
  mStats := TSuppressionStats.Create;
  try
    mStats.Add(cCode, nil);
    mStats.Add(cCode, nil);
    Assert.AreEqual(2, mStats.FileCount);
    Assert.AreEqual(2, Find(mStats, 'regel-b').Files);
    Assert.AreEqual(4, Find(mStats, 'regel-b').LineCount);
  finally
    mStats.Free;
  end;
end;

procedure TSuppressionStatsTests.CountsUnusedFromEngineFindings;
var
  mStats: TSuppressionStats;
begin
  mStats := TSuppressionStats.Create;
  try
    // Zeile 6 (0-basiert): "// lsp-ignore: regel-b, regel-a"
    mStats.Add(cCode, [Unused(6)]);
    Assert.AreEqual(1, Find(mStats, 'regel-a').UnusedCount);
    Assert.AreEqual(1, Find(mStats, 'regel-b').UnusedCount);
  finally
    mStats.Free;
  end;
end;

procedure TSuppressionStatsTests.SortsByTotalThenId;
var
  mStats: TSuppressionStats;
  mCounts: TArray<TSuppressionCount>;
begin
  mStats := TSuppressionStats.Create;
  try
    mStats.Add('// lsp-ignore: zeta' + sLineBreak + 'unit U; // lsp-ignore: alpha, beta, beta', nil);
    mCounts := mStats.Counts;
    Assert.AreEqual<NativeInt>(3, Length(mCounts));
    Assert.AreEqual('beta', mCounts[0].RuleId);
    Assert.AreEqual('alpha', mCounts[1].RuleId);
    Assert.AreEqual('zeta', mCounts[2].RuleId);
  finally
    mStats.Free;
  end;
end;

procedure TSuppressionStatsTests.RendersJson;
var
  mStats: TSuppressionStats;
begin
  mStats := TSuppressionStats.Create;
  try
    mStats.Add('unit U; // lsp-ignore: regel-a', nil);
    Assert.AreEqual('{"suppressions":[{"rule":"regel-a","total":1,"line":1,"file":0,"unused":0,"files":1}],"files":1}',
      mStats.Render(TFindingsFormat.Json));
  finally
    mStats.Free;
  end;
end;

procedure TSuppressionStatsTests.RendersTextSummary;
var
  mStats: TSuppressionStats;
  mOutput: string;
begin
  mStats := TSuppressionStats.Create;
  try
    mStats.Add(cCode, nil);
    mOutput := mStats.Render(TFindingsFormat.Text);
    Assert.IsTrue(Pos('regel-a', mOutput) < Pos('regel-b', mOutput), mOutput);
    Assert.IsTrue(Pos('1 Dateien ausgewertet, 2 Regeln unterdrückt', mOutput) > 0, mOutput);
  finally
    mStats.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSuppressionStatsTests);

end.
