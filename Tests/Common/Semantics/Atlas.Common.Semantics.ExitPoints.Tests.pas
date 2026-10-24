unit Atlas.Common.Semantics.ExitPoints.Tests;

// Tests der Austrittspunkte (#698): Exit, Exit(Wert), raise; im except-Teil,
// Abort, Halt, Herausfallen am end, nur die eigene Routine (verschachtelt,
// anonyme Methode), Aufrufe, die immer auslösen, Result-Zuweisungen mit
// fehlendem Weg, Exceptions laut XMLDoc, Break/Continue in verschachtelten
// Schleifen, Schlüsselwörter aus highlight.exitKeywords.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TExitPointsTests = class
  public
    [Test]
    procedure ProcedureExitsAndFallThrough;
    [Test]
    procedure RoutineNameInHeader;
    [Test]
    procedure NestedRoutineCountsOnlyItself;
    [Test]
    procedure AnonymousMethodCountsOnlyItself;
    [Test]
    procedure NoFallThroughAfterRaise;
    [Test]
    procedure ReraiseAbortHaltAndRunError;
    [Test]
    procedure RoutinesThatAlwaysRaise;
    [Test]
    procedure QualifiedExitIsNoExit;
    [Test]
    procedure ResultAssignmentsAndMissingPath;
    [Test]
    procedure ResultSetOnEveryPath;
    [Test]
    procedure FunctionNameAsTarget;
    [Test]
    procedure ExceptionsFromXmlDoc;
    [Test]
    procedure BareExceptTakesEveryDocumentedCall;
    [Test]
    procedure ExceptionsSwitchedOff;
    [Test]
    procedure BreakAndContinueOfNestedLoops;
    [Test]
    procedure KeywordsFilterExits;
    [Test]
    procedure MethodWithClassAncestor;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Semantics.ExitPoints;

const
  KindNames: array[TExitPointKind] of string = ('exit', 'raise', 'halt', 'call', 'end', 'result', 'source',
    'handler', 'loop', 'jump');

function Query(const ASource: string; ALine, ACharacter: Integer; const AOptions: TExitPointOptions;
  out ASet: TExitPointSet): string; overload;
var
  Tree: TSyntaxTree;
  Point: TExitPoint;
begin
  Result := '';
  Tree := TPascalParser.Parse(ASource);
  try
    ASet := TExitPoints.Find(Tree, TTextLines.SplitLines(ASource), TTextPosition.Create(ALine, ACharacter),
      AOptions);
    for Point in ASet.Points do
    begin
      if Result <> '' then
        Result := Result + ' ';
      Result := Result + Format('%s@%d:%d', [KindNames[Point.Kind], Point.Range.StartPos.Line,
        Point.Range.StartPos.Character]);
      if Point.ResultMissing then
        Result := Result + '!';
    end;
  finally
    Tree.Free;
  end;
end;

function Query(const ASource: string; ALine, ACharacter: Integer; out ASet: TExitPointSet): string; overload;
begin
  Result := Query(ASource, ALine, ACharacter, TExitPointOptions.Default, ASet);
end;

function Query(const ASource: string; ALine, ACharacter: Integer): string; overload;
var
  Found: TExitPointSet;
begin
  Result := Query(ASource, ALine, ACharacter, Found);
end;

function Lines(const AParts: array of string): string;
var
  Part: string;
begin
  Result := '';
  for Part in AParts do
    Result := Result + Part + #10;
end;

{ TExitPointsTests }

procedure TExitPointsTests.ProcedureExitsAndFallThrough;
var
  Source: string;
  Found: TExitPointSet;
begin
  Source := Lines(['unit U;', 'implementation', 'procedure P(A: Boolean);', 'begin', '  if A then', '    Exit;',
    '  Foo;', 'end;', 'end.']);
  Assert.AreEqual('exit@5:4 end@7:0', Query(Source, 5, 5, Found));
  Assert.IsTrue(Found.Query = TExitPointQuery.Routine);
  Assert.AreEqual(2, Found.ExitCount);
  Assert.IsTrue(Found.HasRoutine);
  Assert.AreEqual(2, Found.RoutineRange.StartPos.Line);
  Assert.AreEqual(10, Found.RoutineRange.StartPos.Character);
  Assert.IsFalse(Found.ResultMissing, 'Prozedur');
  // Mitten im Wort und direkt dahinter.
  Assert.AreEqual('exit@5:4 end@7:0', Query(Source, 5, 8));
  // Auf Foo: nichts.
  Assert.AreEqual('', Query(Source, 6, 3, Found));
  Assert.IsFalse(Found.Found);
end;

procedure TExitPointsTests.RoutineNameInHeader;
const
  Source = 'unit U;'#10'implementation'#10'procedure TFoo.Run;'#10'begin'#10'  raise E;'#10'end;'#10'end.';
var
  Found: TExitPointSet;
begin
  Assert.AreEqual('raise@4:2', Query(Source, 2, 16, Found));
  Assert.AreEqual('TFoo.Run', Found.RoutineName);
  Assert.AreEqual(15, Found.RoutineRange.StartPos.Character);
  // Auf dem Klassennamen im Kopf nicht.
  Assert.AreEqual('', Query(Source, 2, 11));
end;

procedure TExitPointsTests.NestedRoutineCountsOnlyItself;
var
  Source: string;
begin
  Source := Lines(['unit U;', 'implementation', 'procedure P;', '  procedure Q;', '  begin', '    Exit;', '  end;',
    'begin', '  if A then', '    Exit;', '  Q;', 'end;', 'end.']);
  Assert.AreEqual('exit@9:4 end@11:0', Query(Source, 9, 5), 'P');
  // Q springt immer mit Exit: kein end.
  Assert.AreEqual('exit@5:4', Query(Source, 5, 5), 'Q');
  Assert.AreEqual('exit@5:4', Query(Source, 3, 13), 'Kopf von Q');
end;

procedure TExitPointsTests.AnonymousMethodCountsOnlyItself;
var
  Source: string;
begin
  Source := Lines(['unit U;', 'implementation', 'procedure P;', 'begin', '  Run(procedure', '    begin',
    '      if A then', '        Exit;', '    end);', '  Exit;', 'end;', 'end.']);
  Assert.AreEqual('exit@7:8 end@8:4', Query(Source, 7, 9), 'anonyme Methode');
  Assert.AreEqual('exit@9:2', Query(Source, 9, 3), 'P fällt nicht heraus');
end;

procedure TExitPointsTests.NoFallThroughAfterRaise;
var
  Source: string;
begin
  Source := Lines(['unit U;', 'implementation', 'procedure P;', 'begin', '  if A then', '    Exit;',
    '  raise E.Create(''x'');', 'end;', 'end.']);
  Assert.AreEqual('exit@5:4 raise@6:2', Query(Source, 6, 3));
end;

procedure TExitPointsTests.ReraiseAbortHaltAndRunError;
var
  Source: string;
begin
  Source := Lines(['unit U;', 'implementation', 'procedure P;', 'begin', '  try', '    Foo;', '  except',
    '    raise;', '  end;', '  if A then', '    Abort;', '  if B then', '    Halt(1);', '  RunError(5);', 'end;',
    'end.']);
  Assert.AreEqual('raise@7:4 raise@10:4 halt@12:4 halt@13:2', Query(Source, 7, 5));
end;

procedure TExitPointsTests.RoutinesThatAlwaysRaise;
var
  Source: string;
  Found: TExitPointSet;
begin
  Source := Lines(['unit U;', 'implementation', 'procedure Fail(const AText: string);', 'begin',
    '  raise EFoo.Create(AText);', 'end;', 'procedure Check(A: Boolean);', 'begin', '  if not A then',
    '    Fail(''nein'');', 'end;', 'procedure P(H: THandle);', 'begin', '  if H = 0 then', '    RaiseLastOSError;',
    '  Fail(''immer'');', 'end;', 'end.']);
  // Fail löst immer aus; Check nicht (ruft Fail nur auf einem Weg). Kein end, weil jeder Weg auslöst.
  Assert.AreEqual('call@14:4 call@15:2', Query(Source, 15, 3, Found));
  Assert.AreEqual(2, Found.ExitCount);
  Assert.AreEqual('Fail', Found.Points[1].Detail);
  Assert.AreEqual('call@9:4 end@10:0', Query(Source, 6, 12), 'Check: Aufruf von Fail und end');
end;

procedure TExitPointsTests.QualifiedExitIsNoExit;
var
  Source: string;
begin
  Source := Lines(['unit U;', 'implementation', 'procedure P;', 'begin', '  TMonitor.Exit(FLock);', '  Exit;',
    'end;', 'end.']);
  Assert.AreEqual('', Query(Source, 4, 12), 'TMonitor.Exit');
  Assert.AreEqual('exit@5:2', Query(Source, 5, 3));
end;

procedure TExitPointsTests.ResultAssignmentsAndMissingPath;
var
  Source: string;
  Found: TExitPointSet;
begin
  Source := Lines(['unit U;', 'implementation', 'function F(A, B: Boolean): Integer;', 'begin', '  if A then',
    '    Exit;', '  if B then', '    Exit(2);', '  if A or B then', '    Result := 1;', 'end;', 'end.']);
  // Auf Result: Austritte und Zuweisungen; Exit ohne Wert und das end kommen ohne Ergebnis an.
  Assert.AreEqual('exit@5:4! exit@7:4 result@9:4 end@10:0!', Query(Source, 9, 6, Found));
  Assert.IsTrue(Found.Query = TExitPointQuery.ResultValue);
  Assert.IsTrue(Found.IsFunction);
  Assert.IsTrue(Found.ResultMissing);
  Assert.AreEqual(3, Found.ExitCount, 'Zuweisungen zählen nicht als Austritt');
  // Auf Exit: dieselben Austritte, ohne die Zuweisungen.
  Assert.AreEqual('exit@5:4! exit@7:4 end@10:0!', Query(Source, 7, 5));
end;

procedure TExitPointsTests.ResultSetOnEveryPath;
var
  Source: string;
  Found: TExitPointSet;
begin
  Source := Lines(['unit U;', 'implementation', 'function F(A: Boolean): Integer;', 'begin', '  Result := 0;',
    '  if A then', '    Exit;', '  Result := 1;', 'end;', 'end.']);
  Assert.AreEqual('result@4:2 exit@6:4 result@7:2 end@8:0', Query(Source, 4, 3, Found));
  Assert.IsFalse(Found.ResultMissing);
end;

procedure TExitPointsTests.FunctionNameAsTarget;
var
  Source: string;
begin
  Source := Lines(['unit U;', 'implementation', 'function F: Integer;', 'begin', '  F := 1;', 'end;', 'end.']);
  Assert.AreEqual('result@4:2 end@5:0', Query(Source, 4, 2));
end;

procedure TExitPointsTests.ExceptionsFromXmlDoc;
var
  Source: string;
  Found: TExitPointSet;
begin
  Source := Lines(['unit U;', 'interface', 'type', '  EOwn = class(EFoo);', '  TLoader = class',
    '    /// <summary>Liest.</summary>', '    /// <exception cref="EFoo">kaputt</exception>',
    '    procedure Load;', '  end;', '/// <exception cref="EBar">nie</exception>', 'procedure Other;',
    'implementation', 'procedure Other;', 'begin', 'end;', 'procedure TLoader.Load;', 'begin', 'end;',
    'procedure P(L: TLoader);', 'begin', '  try', '    L.Load;', '    Other;', '    raise EOwn.Create(''x'');',
    '    raise EBar.Create(''y'');', '  except', '    on E: EFoo do', '      Log(E);', '  end;', 'end;', 'end.']);
  // Auf der Klasse des Handlers: L.Load (laut Doku EFoo) und raise EOwn (stammt von EFoo ab), nicht Other (EBar).
  Assert.AreEqual('source@21:6 source@23:4 handler@26:10', Query(Source, 26, 12, Found));
  Assert.IsTrue(Found.Query = TExitPointQuery.Exceptions);
  Assert.AreEqual('EFoo', Found.Points[0].ExceptionClass);
  Assert.AreEqual('EOwn', Found.Points[1].Detail);
  // Auf "on" dasselbe.
  Assert.AreEqual('source@21:6 source@23:4 handler@26:4', Query(Source, 26, 5));
  // Im Rumpf des Handlers nichts.
  Assert.AreEqual('', Query(Source, 27, 7));
end;

procedure TExitPointsTests.BareExceptTakesEveryDocumentedCall;
var
  Source: string;
begin
  Source := Lines(['unit U;', 'implementation', '/// <exception cref="EBar">nie</exception>', 'procedure Other;',
    'begin', 'end;', 'procedure P;', 'begin', '  try', '    Other;', '    Plain;', '    raise EBaz.Create(''y'');',
    '  except', '    Log;', '  end;', 'end;', 'end.']);
  Assert.AreEqual('source@9:4 source@11:4 handler@12:2', Query(Source, 12, 3));
end;

procedure TExitPointsTests.ExceptionsSwitchedOff;
var
  Source: string;
  Options: TExitPointOptions;
  Found: TExitPointSet;
begin
  Source := Lines(['unit U;', 'implementation', 'procedure P;', 'begin', '  try', '    Foo;', '  except',
    '    Log;', '  end;', 'end;', 'end.']);
  Options := TExitPointOptions.Default;
  Options.Exceptions := False;
  Assert.AreEqual('', Query(Source, 6, 3, Options, Found));
  Assert.IsFalse(Found.Found);
end;

procedure TExitPointsTests.BreakAndContinueOfNestedLoops;
var
  Source: string;
  Options: TExitPointOptions;
  Found: TExitPointSet;
begin
  Source := Lines(['unit U;', 'implementation', 'procedure P;', 'begin', '  for I := 0 to 9 do', '  begin',
    '    while A do', '    begin', '      if B then', '        Break;', '      Continue;', '    end;',
    '    if C then', '      Break;', '  end;', 'end;', 'end.']);
  // Break der inneren Schleife: while, do, end und ihre Sprünge.
  Assert.AreEqual('loop@6:4 loop@6:12 jump@9:8 jump@10:6 loop@11:4', Query(Source, 9, 9));
  // Break der äußeren: for, do, end und nur ihr eigenes Break.
  Assert.AreEqual('loop@4:2 loop@4:18 jump@13:6 loop@14:2', Query(Source, 13, 7));
  Options := TExitPointOptions.Default;
  Options.Loops := False;
  Assert.AreEqual('', Query(Source, 13, 7, Options, Found));
end;

procedure TExitPointsTests.KeywordsFilterExits;
var
  Source: string;
  Options: TExitPointOptions;
  Found: TExitPointSet;
begin
  Source := Lines(['unit U;', 'implementation', 'procedure P;', 'begin', '  if A then', '    Exit;', '  if B then',
    '    Halt;', '  RunError(1);', '  raise E;', 'end;', 'end.']);
  Options := TExitPointOptions.Default;
  Options.Keywords := ['Exit', 'raise'];
  Assert.AreEqual('exit@5:4 raise@9:2', Query(Source, 5, 5, Options, Found));
  Options.Keywords := ['Exit', 'Halt'];
  Assert.AreEqual('exit@5:4 halt@7:4 halt@8:2', Query(Source, 5, 5, Options, Found), 'RunError gilt mit Halt');
end;

procedure TExitPointsTests.MethodWithClassAncestor;
var
  Tree: TSyntaxTree;
  IsA: TExitPointClassTest;
const
  Source = 'unit U;'#10'interface'#10'type'#10'  EA = class(Exception);'#10'  EB = class(EA);'#10 +
    '  EC = class(EB);'#10'implementation'#10'end.';
begin
  Tree := TPascalParser.Parse(Source);
  try
    IsA := TExitPoints.TreeClassTest(Tree);
    Assert.IsTrue(IsA('EC', 'EA', 0), 'über zwei Stufen');
    Assert.IsTrue(IsA('EC', 'EC', 0));
    Assert.IsTrue(IsA('EUnbekannt', 'Exception', 0), 'Konvention');
    Assert.IsFalse(IsA('EA', 'EC', 0), 'nicht umgekehrt');
    Assert.IsFalse(IsA('EUnbekannt', 'EA', 0));
  finally
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TExitPointsTests);

end.
