unit Atlas.Common.Metrics.Calculator.Tests;

// Tests der Zählweise der Code-Metriken (#66) mit festen Beispielmethoden:
// case-Zweige, and/or in Bedingungen, except on, Schleifen, Tiefe, kognitive
// Komplexität, Codezeilen ohne Kommentare und Parameter; #980: Operanden einer
// Bedingung, lokale Variablen, Ausstiege und die Liste der Bedingungen.

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
    [Test]
    procedure OperandsOfLargestCondition;
    [Test]
    procedure OperandsThroughParensAndNot;
    [Test]
    procedure LocalsCountVarInlineAndForVar;
    [Test]
    procedure ExitsCountExitAndRaise;
    [Test]
    procedure ConditionsListedByPosition;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
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

procedure TMetricsCalculatorTests.OperandsOfLargestCondition;
var
  Metrics: TRoutineMetrics;
begin
  Metrics := Body('  if A and B then X;'#10'  while (C or D) and E and F do Y;'#10'  repeat Z until G xor H;');
  Assert.AreEqual(4, Value(Metrics, TMetricKind.BooleanOperands), 'größte Bedingung: while');
  Assert.AreEqual(1, Value(Body('  if A then X;'), TMetricKind.BooleanOperands));
  Assert.AreEqual(0, Value(Body('  X := A and B and C;'), TMetricKind.BooleanOperands), 'keine Bedingung');
  Assert.AreEqual(3, Value(Body('  Y := if A and B and C then 1 else 2;'), TMetricKind.BooleanOperands),
    'Bedingungsausdruck');
end;

procedure TMetricsCalculatorTests.OperandsThroughParensAndNot;
begin
  // not (A and B) und (C or (D and E)): fünf Glieder; Vergleiche und Aufrufe sind je ein Operand.
  Assert.AreEqual(5, Value(Body('  if not (A and B) and (C or (D and E)) then X;'), TMetricKind.BooleanOperands));
  Assert.AreEqual(2, Value(Body('  if (Liste.Count > 0) and Pruefe(A or B) then X;'), TMetricKind.BooleanOperands),
    'or im Argument gehört nicht zur Bedingung');
end;

procedure TMetricsCalculatorTests.LocalsCountVarInlineAndForVar;
var
  Found: TArray<TRoutineMetrics>;
  Item: TRoutineMetrics;
  Checked: Integer;
begin
  // P: A, B, C, D, E, I, S = 7; klassisches for C zählt nicht doppelt. Inner hat X und Y, die anonyme Methode
  // zählt für sich.
  Found := TMetricsCalculator.ForText(InUnit('procedure P;'#10'var'#10'  A, B: Integer;'#10'  C: string;'#10 +
    '  procedure Inner;'#10'  var'#10'    X: Integer;'#10'  begin'#10'    var Y := 1;'#10'  end;'#10'begin'#10 +
    '  var D, E: Integer;'#10'  for var I := 0 to 1 do'#10'    Inner;'#10'  for var S in Liste do'#10 +
    '    Call(procedure'#10'      begin'#10'        var Z := 2;'#10'      end);'#10'  for C := 1 to 2 do;'#10 +
    'end;'));
  Checked := 0;
  for Item in Found do
    if Item.Name = 'P' then
    begin
      Assert.AreEqual(7, Value(Item, TMetricKind.LocalCount));
      Inc(Checked);
    end
    else if Item.Name = 'P.Inner' then
    begin
      Assert.AreEqual(2, Value(Item, TMetricKind.LocalCount));
      Inc(Checked);
    end;
  Assert.AreEqual(2, Checked);
end;

procedure TMetricsCalculatorTests.ExitsCountExitAndRaise;
var
  Metrics: TRoutineMetrics;
begin
  Metrics := Only('function F(A: Integer): Integer;'#10'begin'#10'  if A = 0 then Exit;'#10 +
    '  if A = 1 then Exit(1);'#10'  try'#10'    if A < 0 then raise EFehler.Create(''x'');'#10'  except'#10 +
    '    raise;'#10'  end;'#10'  Call(procedure begin Exit; end);'#10'  Result := ExitCode;'#10'end;');
  Assert.AreEqual(4, Value(Metrics, TMetricKind.ExitPoints), 'Exit, Exit(1), raise, raise; ohne anonyme Methode');
  Assert.AreEqual(0, Value(Body('  X := 1;'), TMetricKind.ExitPoints));
end;

procedure TMetricsCalculatorTests.ConditionsListedByPosition;
var
  Conditions: TArray<TConditionMetrics>;
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(InUnit('procedure P;'#10'begin'#10'  if A and B then'#10'    while C do'#10 +
    '      X;'#10'  repeat'#10'  until D or E or F;'#10'end;'));
  try
    Conditions := TMetricsCalculator.Conditions(Tree);
  finally
    Tree.Free;
  end;
  Assert.AreEqual(3, Integer(Length(Conditions)));
  Assert.AreEqual(2, Conditions[0].Operands);
  Assert.AreEqual(5, Conditions[0].Range.StartPos.Line);
  Assert.AreEqual(5, Conditions[0].Range.StartPos.Character);
  Assert.AreEqual(12, Conditions[0].Range.EndPos.Character);
  Assert.AreEqual(1, Conditions[1].Operands);
  Assert.AreEqual(3, Conditions[2].Operands);
  Assert.AreEqual(9, Conditions[2].Range.StartPos.Line);
  Assert.IsTrue(Conditions[0].StartOffset < Conditions[0].EndOffset);
end;

initialization
  TDUnitX.RegisterTestFixture(TMetricsCalculatorTests);

end.
