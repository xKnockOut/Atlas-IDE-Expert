unit Atlas.Common.Metrics.Calculator.Tests;

// Tests der Zählweise der Code-Metriken (#66) mit festen Beispielmethoden:
// case-Zweige, and/or in Bedingungen, except on, Schleifen, Tiefe, kognitive
// Komplexität, Codezeilen ohne Kommentare und Parameter.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMetricsCalculatorTests = class
  public
    [Test]
    procedure EmptyRoutineHasCyclomaticOne;
    [Test]
    procedure CaseBranchesCountWithoutElse;
    [Test]
    procedure AndOrCountOnlyInConditions;
    [Test]
    procedure ExceptOnCountsEachHandler;
    [Test]
    procedure ExceptWithoutOnCountsOnce;
    [Test]
    procedure LoopsCountOnce;
    [Test]
    procedure NestingDepthKeepsElseIfOnLevel;
    [Test]
    procedure NestingDepthCountsTry;
    [Test]
    procedure CognitiveWeightsNesting;
    [Test]
    procedure CognitiveElseIfAndElse;
    [Test]
    procedure CognitiveElseWithoutThen;
    [Test]
    procedure CognitiveOperatorSequences;
    [Test]
    procedure CognitiveAnonymousMethodNests;
    [Test]
    procedure CodeLinesSkipCommentsAndBlankLines;
    [Test]
    procedure CodeLinesSkipLocalRoutines;
    [Test]
    procedure ParametersCountNames;
    [Test]
    procedure ParametersFromDeclaration;
    [Test]
    procedure NamesAndRanges;
    [Test]
    procedure SkipsForwardAndAsm;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Metrics.Calculator;

function InUnit(const ARoutines: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10 + ARoutines + #10'end.';
end;

function Only(const ARoutines: string): TRoutineMetrics;
var
  Found: TArray<TRoutineMetrics>;
begin
  Found := TMetricsCalculator.ForText(InUnit(ARoutines));
  Assert.AreEqual(1, Integer(Length(Found)), 'genau eine Routine');
  Result := Found[0];
end;

function Body(const AStatements: string): TRoutineMetrics;
begin
  Result := Only('procedure P;'#10'begin'#10 + AStatements + #10'end;');
end;

function Value(const AMetrics: TRoutineMetrics; AKind: TMetricKind): Integer;
begin
  Result := AMetrics.Values[AKind];
end;

procedure TMetricsCalculatorTests.EmptyRoutineHasCyclomaticOne;
var
  Metrics: TRoutineMetrics;
begin
  Metrics := Body('');
  Assert.AreEqual(1, Value(Metrics, TMetricKind.Cyclomatic));
  Assert.AreEqual(0, Value(Metrics, TMetricKind.Cognitive));
  Assert.AreEqual(0, Value(Metrics, TMetricKind.NestingDepth));
  Assert.AreEqual(0, Value(Metrics, TMetricKind.ParameterCount));
end;

procedure TMetricsCalculatorTests.CaseBranchesCountWithoutElse;
var
  Metrics: TRoutineMetrics;
begin
  // 1 + drei Zweige; else zählt nicht.
  Metrics := Body('  case A of'#10'    1: X;'#10'    2, 3: Y;'#10'    4: ;'#10'  else'#10'    Z;'#10'  end;');
  Assert.AreEqual(4, Value(Metrics, TMetricKind.Cyclomatic));
  // case einmal (+1), keine Schachtelung.
  Assert.AreEqual(1, Value(Metrics, TMetricKind.Cognitive));
  Assert.AreEqual(1, Value(Metrics, TMetricKind.NestingDepth));
end;

procedure TMetricsCalculatorTests.AndOrCountOnlyInConditions;
var
  Metrics: TRoutineMetrics;
begin
  // if (+1), and (+1), or (+1); die Zuweisung und das bitweise and außerhalb zählen nicht.
  Metrics := Body('  if (A and B) or C then'#10'    X := 1;'#10'  F := A and B;'#10'  M := N and $FF;');
  Assert.AreEqual(4, Value(Metrics, TMetricKind.Cyclomatic));
  // while mit not (A or B) und until mit and: je Schleife +1, je Operator +1.
  Metrics := Body('  while not (A or B) do'#10'    X;'#10'  repeat'#10'    Y;'#10'  until C and D;');
  Assert.AreEqual(5, Value(Metrics, TMetricKind.Cyclomatic));
end;

procedure TMetricsCalculatorTests.ExceptOnCountsEachHandler;
var
  Metrics: TRoutineMetrics;
begin
  Metrics := Body('  try'#10'    X;'#10'  except'#10'    on E: EAbort do'#10'      Y;'#10 +
    '    on E: Exception do'#10'      Z;'#10'  end;');
  Assert.AreEqual(3, Value(Metrics, TMetricKind.Cyclomatic));
  // Je Handler +1 (Ebene 0).
  Assert.AreEqual(2, Value(Metrics, TMetricKind.Cognitive));
end;

procedure TMetricsCalculatorTests.ExceptWithoutOnCountsOnce;
var
  Metrics: TRoutineMetrics;
begin
  Metrics := Body('  try'#10'    X;'#10'  except'#10'    Y;'#10'    Z;'#10'  end;');
  Assert.AreEqual(2, Value(Metrics, TMetricKind.Cyclomatic));
  Assert.AreEqual(1, Value(Metrics, TMetricKind.Cognitive));
  // finally zählt nicht.
  Metrics := Body('  try'#10'    X;'#10'  finally'#10'    Y;'#10'  end;');
  Assert.AreEqual(1, Value(Metrics, TMetricKind.Cyclomatic));
  Assert.AreEqual(0, Value(Metrics, TMetricKind.Cognitive));
end;

procedure TMetricsCalculatorTests.LoopsCountOnce;
var
  Metrics: TRoutineMetrics;
begin
  Metrics := Body('  for I := 0 to 9 do X;'#10'  for S in L do Y;'#10'  while A do Z;'#10 +
    '  repeat Inc(I); until I > 3;');
  Assert.AreEqual(5, Value(Metrics, TMetricKind.Cyclomatic));
  Assert.AreEqual(4, Value(Metrics, TMetricKind.Cognitive));
  Assert.AreEqual(1, Value(Metrics, TMetricKind.NestingDepth));
end;

procedure TMetricsCalculatorTests.NestingDepthKeepsElseIfOnLevel;
var
  Metrics: TRoutineMetrics;
begin
  Metrics := Body('  if A then'#10'    for I := 0 to 3 do'#10'      while B do'#10'        X;');
  Assert.AreEqual(3, Value(Metrics, TMetricKind.NestingDepth));
  // Eine else-if-Kette bleibt auf Ebene 1.
  Metrics := Body('  if A then X'#10'  else if B then Y'#10'  else if C then Z'#10'  else W;');
  Assert.AreEqual(1, Value(Metrics, TMetricKind.NestingDepth));
  // begin … end allein schachtelt nicht.
  Metrics := Body('  if A then'#10'  begin'#10'    if B then'#10'    begin'#10'      X;'#10'    end;'#10'  end;');
  Assert.AreEqual(2, Value(Metrics, TMetricKind.NestingDepth));
end;

procedure TMetricsCalculatorTests.NestingDepthCountsTry;
var
  Metrics: TRoutineMetrics;
begin
  Metrics := Body('  try'#10'    if A then'#10'      X;'#10'  finally'#10'    Y;'#10'  end;');
  Assert.AreEqual(2, Value(Metrics, TMetricKind.NestingDepth));
end;

procedure TMetricsCalculatorTests.CognitiveWeightsNesting;
var
  Metrics: TRoutineMetrics;
begin
  // if +1, for +2 (Ebene 1), if +3 (Ebene 2), and/or zwei Folgen +2, else +1 = 9.
  Metrics := Body('  if A then'#10'    for I := 0 to 3 do'#10'      if B and C or D then'#10'        X'#10 +
    '      else'#10'        Y;');
  Assert.AreEqual(9, Value(Metrics, TMetricKind.Cognitive));
  // Dieselben Strukturen hintereinander: je +1.
  Metrics := Body('  if A then X;'#10'  for I := 0 to 3 do Y;'#10'  if B then Z;');
  Assert.AreEqual(3, Value(Metrics, TMetricKind.Cognitive));
end;

procedure TMetricsCalculatorTests.CognitiveElseIfAndElse;
var
  Metrics: TRoutineMetrics;
begin
  // if +1, else if +1, else +1.
  Metrics := Body('  if A then X'#10'  else if B then Y'#10'  else Z;');
  Assert.AreEqual(3, Value(Metrics, TMetricKind.Cognitive));
  Assert.AreEqual(3, Value(Metrics, TMetricKind.Cyclomatic));
end;

procedure TMetricsCalculatorTests.CognitiveElseWithoutThen;
var
  Metrics: TRoutineMetrics;
begin
  // if A then else B: der Zweig hinter else zählt als else.
  Metrics := Body('  if A then else B;');
  Assert.AreEqual(2, Value(Metrics, TMetricKind.Cognitive));
  Metrics := Body('  if A then B;');
  Assert.AreEqual(1, Value(Metrics, TMetricKind.Cognitive));
end;

procedure TMetricsCalculatorTests.CognitiveOperatorSequences;
var
  Metrics: TRoutineMetrics;
begin
  // A and B and C: eine Folge (+1) zum if (+1).
  Metrics := Body('  if A and B and C then X;');
  Assert.AreEqual(2, Value(Metrics, TMetricKind.Cognitive));
  Assert.AreEqual(4, Value(Metrics, TMetricKind.Cyclomatic));
  // A and B or C and D: drei Folgen.
  Metrics := Body('  if A and B or C and D then X;');
  Assert.AreEqual(4, Value(Metrics, TMetricKind.Cognitive));
  // Klammern trennen keine Folge.
  Metrics := Body('  if A and (B and C) then X;');
  Assert.AreEqual(2, Value(Metrics, TMetricKind.Cognitive));
end;

procedure TMetricsCalculatorTests.CognitiveAnonymousMethodNests;
var
  Metrics: TRoutineMetrics;
begin
  // Das if in der anonymen Methode steht eine Ebene tiefer: +2.
  Metrics := Body('  Run(procedure'#10'    begin'#10'      if A then X;'#10'    end);');
  Assert.AreEqual(2, Value(Metrics, TMetricKind.Cognitive));
  Assert.AreEqual(2, Value(Metrics, TMetricKind.Cyclomatic));
end;

procedure TMetricsCalculatorTests.CodeLinesSkipCommentsAndBlankLines;
var
  Metrics: TRoutineMetrics;
begin
  Metrics := Only('procedure P;'#10'var'#10'  X: Integer;'#10'begin'#10'  // Kommentar'#10#10 +
    '  X := 1; { dahinter }'#10'  { mehrzeiliger'#10'    Kommentar }'#10'  {$IFDEF DEBUG}'#10'end;');
  // procedure, var, X: Integer, begin, X := 1, end
  Assert.AreEqual(6, Value(Metrics, TMetricKind.MethodLength));
end;

procedure TMetricsCalculatorTests.CodeLinesSkipLocalRoutines;
var
  Found: TArray<TRoutineMetrics>;
begin
  Found := TMetricsCalculator.ForText(InUnit('procedure P;'#10'  procedure Inner;'#10'  begin'#10'    X;'#10 +
    '  end;'#10'begin'#10'  Inner;'#10'end;'));
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('P', Found[0].Name);
  // procedure P, begin, Inner;, end
  Assert.AreEqual(4, Value(Found[0], TMetricKind.MethodLength));
  Assert.AreEqual('P.Inner', Found[1].Name);
  Assert.AreEqual(4, Value(Found[1], TMetricKind.MethodLength));
end;

procedure TMetricsCalculatorTests.ParametersCountNames;
var
  Metrics: TRoutineMetrics;
begin
  Metrics := Only('function F(A, B: Integer; const C: string; var D; out E: Byte): Boolean;'#10'begin'#10'end;');
  Assert.AreEqual(5, Value(Metrics, TMetricKind.ParameterCount));
end;

procedure TMetricsCalculatorTests.ParametersFromDeclaration;
var
  Found: TArray<TRoutineMetrics>;
begin
  Found := TMetricsCalculator.ForText('unit U;'#10'interface'#10'type'#10'  TFoo = class'#10 +
    '    procedure Bar(A, B: Integer; const C: string);'#10'  end;'#10'implementation'#10 +
    'procedure TFoo.Bar;'#10'begin'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(3, Value(Found[0], TMetricKind.ParameterCount));
end;

procedure TMetricsCalculatorTests.NamesAndRanges;
var
  Found: TArray<TRoutineMetrics>;
begin
  Found := TMetricsCalculator.ForText(InUnit('class function TFoo.Bar(A: Integer): Integer;'#10'begin'#10 +
    '  Result := A;'#10'end;'));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('TFoo.Bar', Found[0].Name);
  // Zeile 3 (ab 0), Name ab Spalte 15 bis hinter "Bar".
  Assert.AreEqual(3, Found[0].NameRange.StartPos.Line);
  Assert.AreEqual(15, Found[0].NameRange.StartPos.Character);
  Assert.AreEqual(23, Found[0].NameRange.EndPos.Character);
  Assert.AreEqual(3, Found[0].Range.StartPos.Line);
  Assert.AreEqual(6, Found[0].Range.EndPos.Line);
end;

procedure TMetricsCalculatorTests.SkipsForwardAndAsm;
var
  Found: TArray<TRoutineMetrics>;
begin
  Found := TMetricsCalculator.ForText(InUnit('procedure F; forward;'#10'procedure Q;'#10'asm'#10'  mov eax, 1'#10 +
    'end;'#10'procedure F;'#10'begin'#10'end;'));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('F', Found[0].Name);
end;

initialization
  TDUnitX.RegisterTestFixture(TMetricsCalculatorTests);

end.
