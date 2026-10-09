unit Argus.Common.Rules.SuppressionStats.Tests;

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
  Argus.Common.Documents.Contract,
  Argus.Common.Rules.Contract,
  Argus.Common.Rules.Engine,
  Argus.Common.Rules.Output,
  Argus.Common.Rules.SuppressionStats;

const
  Code =
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
  Result.RuleId := UnusedSuppressionRuleId;
  Result.Range := TTextRange.Create(TTextPosition.Create(ALine, 0), TTextPosition.Create(ALine + 1, 0));
end;

function Find(AStats: TSuppressionStats; const AId: string): TSuppressionCount;
var
  Count: TSuppressionCount;
begin
  for Count in AStats.Counts do
    if Count.RuleId = AId then
      Exit(Count);
  Result := Default(TSuppressionCount);
end;

{ TSuppressionStatsTests }

procedure TSuppressionStatsTests.CountsLineAndFileSuppressionsPerRule;
var
  Stats: TSuppressionStats;
begin
  Stats := TSuppressionStats.Create;
  try
    Stats.Add(Code, nil);
    Assert.AreEqual(1, Find(Stats, 'regel-a').FileCount);
    Assert.AreEqual(1, Find(Stats, 'regel-a').LineCount);
    Assert.AreEqual(0, Find(Stats, 'regel-b').FileCount);
    Assert.AreEqual(2, Find(Stats, 'regel-b').LineCount);
    Assert.AreEqual(2, Find(Stats, 'regel-b').Total);
  finally
    Stats.Free;
  end;
end;

procedure TSuppressionStatsTests.CountsFilesOncePerRule;
var
  Stats: TSuppressionStats;
begin
  Stats := TSuppressionStats.Create;
  try
    Stats.Add(Code, nil);
    Stats.Add(Code, nil);
    Assert.AreEqual(2, Stats.FileCount);
    Assert.AreEqual(2, Find(Stats, 'regel-b').Files);
    Assert.AreEqual(4, Find(Stats, 'regel-b').LineCount);
  finally
    Stats.Free;
  end;
end;

procedure TSuppressionStatsTests.CountsUnusedFromEngineFindings;
var
  Stats: TSuppressionStats;
begin
  Stats := TSuppressionStats.Create;
  try
    // Zeile 6 (0-basiert): "// lsp-ignore: regel-b, regel-a"
    Stats.Add(Code, [Unused(6)]);
    Assert.AreEqual(1, Find(Stats, 'regel-a').UnusedCount);
    Assert.AreEqual(1, Find(Stats, 'regel-b').UnusedCount);
  finally
    Stats.Free;
  end;
end;

procedure TSuppressionStatsTests.SortsByTotalThenId;
var
  Stats: TSuppressionStats;
  Counts: TArray<TSuppressionCount>;
begin
  Stats := TSuppressionStats.Create;
  try
    Stats.Add('// lsp-ignore: zeta' + sLineBreak + 'unit U; // lsp-ignore: alpha, beta, beta', nil);
    Counts := Stats.Counts;
    Assert.AreEqual<NativeInt>(3, Length(Counts));
    Assert.AreEqual('beta', Counts[0].RuleId);
    Assert.AreEqual('alpha', Counts[1].RuleId);
    Assert.AreEqual('zeta', Counts[2].RuleId);
  finally
    Stats.Free;
  end;
end;

procedure TSuppressionStatsTests.RendersJson;
var
  Stats: TSuppressionStats;
begin
  Stats := TSuppressionStats.Create;
  try
    Stats.Add('unit U; // lsp-ignore: regel-a', nil);
    Assert.AreEqual('{"suppressions":[{"rule":"regel-a","total":1,"line":1,"file":0,"unused":0,"files":1}],"files":1}',
      Stats.Render(TFindingsFormat.Json));
  finally
    Stats.Free;
  end;
end;

procedure TSuppressionStatsTests.RendersTextSummary;
var
  Stats: TSuppressionStats;
  Output: string;
begin
  Stats := TSuppressionStats.Create;
  try
    Stats.Add(Code, nil);
    Output := Stats.Render(TFindingsFormat.Text);
    Assert.IsTrue(Pos('regel-a', Output) < Pos('regel-b', Output), Output);
    Assert.IsTrue(Pos('1 Dateien ausgewertet, 2 Regeln unterdrückt', Output) > 0, Output);
  finally
    Stats.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSuppressionStatsTests);

end.
