unit Atlas.Common.Editing.IfCase.Tests;

// Tests für „if-Kette und case umwandeln“ (#646): einfache Kette, Listen,
// Bereiche, Aufzählungen, verschachtelte Anweisungen, Kommentare, Hin- und
// Rückweg; keine Aktion bei Strings, unterschiedlichen Ausdrücken,
// Funktionsaufrufen, Variablen als Marken und doppelten Marken.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TIfCaseTests = class
  public
    [Test]
    procedure SimpleChainToCase;
    [Test]
    procedure ListsAndRanges;
    [Test]
    procedure EnumWithNestedStatements;
    [Test]
    procedure CommentsInBranchesStay;
    [Test]
    procedure CaseToIfChain;
    [Test]
    procedure CaseToIfWithoutElseKeepsSemicolon;
    [Test]
    procedure LargeIntegersUseOrChain;
    [Test]
    procedure InnerIfGetsBeginEnd;
    [Test]
    procedure RoundTripIsEquivalent;
    [Test]
    procedure NoActionForStrings;
    [Test]
    procedure NoActionForDifferentExpressions;
    [Test]
    procedure NoActionForFunctionCalls;
    [Test]
    procedure NoActionForVariablesAsLabels;
    [Test]
    procedure NoActionForDuplicateLabels;
    [Test]
    procedure NoActionForSingleCondition;
    [Test]
    procedure ConvertibleConditionsCounts;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.StatementText,
  Atlas.Common.Editing.IfCase,
  Atlas.Text.Lines;

const
  FileName = 'Probe.pas';

/// <summary>Unit mit Typen, Konstanten und der Routine Run mit ADecls und den Anweisungen ABody.</summary>
function Source(const ADecls, ABody: string): string;
begin
  Result := 'unit Probe;'#10'interface'#10'type'#10'  TState = (stNew, stPaid, stSent, stDone);'#10 +
    'implementation'#10'const'#10'  Limit = 5;'#10'function Next: Integer;'#10'begin'#10'  Result := 1;'#10 +
    'end;'#10'procedure Run;'#10'var'#10 + ADecls + 'begin'#10 + ABody + 'end;'#10'end.'#10;
end;

function ApplyEdit(const AText: string; const AEdit: TTextEdit): string;
var
  Lines: TLineTable;
  Start, Stop: Integer;
begin
  Lines := TLineTable.Build(AText);
  Start := Lines.OffsetAt(AEdit.Range.StartPos);
  Stop := Lines.OffsetAt(AEdit.Range.EndPos);
  Result := Copy(AText, 1, Start) + AEdit.NewText + Copy(AText, Stop + 1, MaxInt);
end;

/// <summary>Position des ersten Vorkommens von AMarker im Text.</summary>
function PositionOf(const AText, AMarker: string): TTextPosition;
begin
  Result := TLineTable.Build(AText).PositionAt(Pos(AMarker, AText) - 1);
end;

function Convert(const AText, AMarker: string; AToCase: Boolean; out AResult: string): Boolean;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Conversion: TIfCaseConversion;
  Layout: TStatementLayout;
begin
  AResult := '';
  Tree := TPascalParser.Parse(AText);
  Resolver := TNameResolver.Create(nil);
  try
    Resolver.PinTree(Tree, FileName);
    try
      Layout := TStatementLayout.Create('', '  ', #10);
      if AToCase then
        Result := TIfCase.ToCase(AText, Tree, PositionOf(AText, AMarker),
          TIfCaseLookup.FromResolver(Resolver, Tree, FileName), Layout, Conversion)
      else
        Result := TIfCase.ToIf(AText, Tree, PositionOf(AText, AMarker),
          TIfCaseLookup.FromResolver(Resolver, Tree, FileName), Layout, Conversion);
      if Result then
      begin
        AResult := ApplyEdit(AText, Conversion.Edit);
        // Das Ergebnis parst fehlerfrei.
        Tree.Free;
        Tree := nil;
        Tree := TPascalParser.Parse(AResult);
        Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)), AResult);
      end;
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

function ToCase(const AText, AMarker: string): string;
begin
  Assert.IsTrue(Convert(AText, AMarker, True, Result), AText);
end;

function ToIf(const AText, AMarker: string): string;
begin
  Assert.IsTrue(Convert(AText, AMarker, False, Result), AText);
end;

procedure NoCase(const AText, AMarker: string);
var
  Output: string;
begin
  Assert.IsFalse(Convert(AText, AMarker, True, Output), Output);
end;

procedure TIfCaseTests.SimpleChainToCase;
var
  Text: string;
begin
  Text := Source('  A, B: Integer;'#10,
    '  if A = 1 then'#10'    B := 10'#10'  else if A = 2 then'#10'    B := 20'#10'  else'#10'    B := 0;'#10);
  Assert.AreEqual(Source('  A, B: Integer;'#10,
    '  case A of'#10'    1: B := 10;'#10'    2: B := 20;'#10'  else'#10'    B := 0;'#10'  end;'#10),
    ToCase(Text, 'if A = 1'));
  // Auch vom inneren if der Kette aus und mit gespiegeltem Vergleich.
  Text := Source('  A, B: Integer;'#10,
    '  if 1 = A then'#10'    B := 10'#10'  else if A = Limit then'#10'    B := 20;'#10);
  Assert.AreEqual(Source('  A, B: Integer;'#10,
    '  case A of'#10'    1: B := 10;'#10'    Limit: B := 20;'#10'  end;'#10), ToCase(Text, 'if A = Limit'));
end;

procedure TIfCaseTests.ListsAndRanges;
var
  Text: string;
begin
  Text := Source('  A, B: Integer;'#10,
    '  if (A = 1) or (A = 2) then'#10'    B := 1'#10'  else if (A >= 3) and (A <= 5) then'#10'    B := 2'#10 +
    '  else if A in [6, 8..9] then'#10'    B := 3'#10'  else if (10 <= A) and (A <= 12) then'#10'    B := 4;'#10);
  Assert.AreEqual(Source('  A, B: Integer;'#10,
    '  case A of'#10'    1, 2: B := 1;'#10'    3..5: B := 2;'#10'    6, 8..9: B := 3;'#10'    10..12: B := 4;'#10 +
    '  end;'#10), ToCase(Text, 'if (A = 1)'));
end;

procedure TIfCaseTests.EnumWithNestedStatements;
var
  Text: string;
begin
  Text := Source('  S: TState;'#10'  N: Integer;'#10,
    '  if S = stNew then'#10'  begin'#10'    N := 1;'#10'    Inc(N);'#10'  end'#10 +
    '  else if S in [stPaid, stSent] then'#10'  begin'#10'    N := 2;'#10'  end'#10 +
    '  else'#10'  begin'#10'    N := 0;'#10'    Dec(N);'#10'  end;'#10);
  // begin … end bleibt nur bei mehreren Anweisungen; im else des case steht die Liste ohne begin.
  Assert.AreEqual(Source('  S: TState;'#10'  N: Integer;'#10,
    '  case S of'#10'    stNew:'#10'      begin'#10'        N := 1;'#10'        Inc(N);'#10'      end;'#10 +
    '    stPaid, stSent: N := 2;'#10'  else'#10'    N := 0;'#10'    Dec(N);'#10'  end;'#10), ToCase(Text, 'if S'));
end;

procedure TIfCaseTests.CommentsInBranchesStay;
var
  Text: string;
begin
  Text := Source('  C: Char;'#10'  N: Integer;'#10,
    '  if C = ''a'' then'#10'    N := 1 // erstes'#10'  else if C = ''b'' then'#10'  begin'#10 +
    '    // zweites'#10'    N := 2;'#10'  end;'#10);
  Assert.AreEqual(Source('  C: Char;'#10'  N: Integer;'#10,
    '  case C of'#10'    ''a'':'#10'      N := 1; // erstes'#10'    ''b'':'#10'      // zweites'#10 +
    '      N := 2;'#10'  end;'#10), ToCase(Text, 'if C'));
  // Kommentar hinter dem Semikolon der Kette wandert mit ins case.
  Text := Source('  C: Char;'#10'  N: Integer;'#10,
    '  if C = ''a'' then'#10'    N := 1'#10'  else if C = ''b'' then'#10'    N := 2'#10'  else'#10 +
    '    N := 0; // Rest'#10);
  Assert.AreEqual(Source('  C: Char;'#10'  N: Integer;'#10,
    '  case C of'#10'    ''a'': N := 1;'#10'    ''b'': N := 2;'#10'  else'#10'    N := 0; // Rest'#10'  end;'#10),
    ToCase(Text, 'if C'));
  // Kommentar in einer Bedingung ginge verloren: keine Aktion.
  NoCase(Source('  C: Char;'#10'  N: Integer;'#10,
    '  if C = ''a'' { klein } then'#10'    N := 1'#10'  else if C = ''b'' then'#10'    N := 2;'#10), 'if C');
end;

procedure TIfCaseTests.CaseToIfChain;
var
  Text: string;
begin
  Text := Source('  S: TState;'#10'  N: Integer;'#10,
    '  case S of'#10'    stNew: N := 1;'#10'    stPaid, stSent:'#10'      begin'#10'        N := 2;'#10 +
    '        Inc(N);'#10'      end;'#10'  else'#10'    N := 0;'#10'    Dec(N);'#10'  end;'#10);
  Assert.AreEqual(Source('  S: TState;'#10'  N: Integer;'#10,
    '  if S = stNew then'#10'    N := 1'#10'  else if S in [stPaid, stSent] then'#10'  begin'#10'    N := 2;'#10 +
    '    Inc(N);'#10'  end'#10'  else'#10'  begin'#10'    N := 0;'#10'    Dec(N);'#10'  end;'#10),
    ToIf(Text, 'case S'));
  // Bereiche bei Zeichen: Vergleiche statt Menge (Char passt nicht ohne Warnung in eine Menge).
  Text := Source('  C: Char;'#10'  N: Integer;'#10,
    '  case C of'#10'    ''a''..''z'': N := 1;'#10'    ''0'', ''1'': N := 2;'#10'  end;'#10);
  Assert.AreEqual(Source('  C: Char;'#10'  N: Integer;'#10,
    '  if (C >= ''a'') and (C <= ''z'') then'#10'    N := 1'#10'  else if (C = ''0'') or (C = ''1'') then'#10 +
    '    N := 2;'#10), ToIf(Text, 'case C'));
end;

procedure TIfCaseTests.CaseToIfWithoutElseKeepsSemicolon;
var
  Text: string;
begin
  Text := Source('  A, B: Integer;'#10,
    '  case A of'#10'    1: B := 1;'#10'    2: B := 2; // zwei'#10'  end;'#10'  B := 3;'#10);
  Assert.AreEqual(Source('  A, B: Integer;'#10,
    '  if A = 1 then'#10'    B := 1'#10'  else if A = 2 then'#10'    B := 2; // zwei'#10'  B := 3;'#10),
    ToIf(Text, 'case A'));
end;

procedure TIfCaseTests.LargeIntegersUseOrChain;
var
  Text: string;
begin
  Text := Source('  A, B: Integer;'#10,
    '  case A of'#10'    1, 2: B := 1;'#10'    300, 400: B := 2;'#10'  end;'#10);
  Assert.AreEqual(Source('  A, B: Integer;'#10,
    '  if A in [1, 2] then'#10'    B := 1'#10'  else if (A = 300) or (A = 400) then'#10'    B := 2;'#10),
    ToIf(Text, 'case A'));
end;

procedure TIfCaseTests.InnerIfGetsBeginEnd;
var
  Text: string;
begin
  Text := Source('  A, B: Integer;'#10,
    '  case A of'#10'    1: if B > 0 then B := 0;'#10'  else'#10'    B := 2;'#10'  end;'#10);
  Assert.AreEqual(Source('  A, B: Integer;'#10,
    '  if A = 1 then'#10'  begin'#10'    if B > 0 then B := 0;'#10'  end'#10'  else'#10'    B := 2;'#10),
    ToIf(Text, 'case A'));
end;

procedure TIfCaseTests.RoundTripIsEquivalent;
var
  Text, Back: string;
begin
  Text := Source('  A, B: Integer;'#10,
    '  if A = 1 then'#10'    B := 10'#10'  else if A in [2, 3] then'#10'    B := 20'#10'  else'#10'    B := 0;'#10);
  Back := ToIf(ToCase(Text, 'if A = 1'), 'case A');
  Assert.AreEqual(Text, Back);
end;

procedure TIfCaseTests.NoActionForStrings;
begin
  NoCase(Source('  S: string;'#10'  B: Integer;'#10,
    '  if S = ''a'' then'#10'    B := 1'#10'  else if S = ''b'' then'#10'    B := 2;'#10), 'if S');
  NoCase(Source('  D: Double;'#10'  B: Integer;'#10,
    '  if D = 1 then'#10'    B := 1'#10'  else if D = 2 then'#10'    B := 2;'#10), 'if D');
end;

procedure TIfCaseTests.NoActionForDifferentExpressions;
begin
  NoCase(Source('  A, C, B: Integer;'#10,
    '  if A = 1 then'#10'    B := 1'#10'  else if C = 2 then'#10'    B := 2;'#10), 'if A');
  NoCase(Source('  A, B: Integer;'#10,
    '  if A = 1 then'#10'    B := 1'#10'  else if A > 2 then'#10'    B := 2;'#10), 'if A');
end;

procedure TIfCaseTests.NoActionForFunctionCalls;
var
  Output: string;
begin
  NoCase(Source('  B: Integer;'#10,
    '  if Next = 1 then'#10'    B := 1'#10'  else if Next = 2 then'#10'    B := 2;'#10), 'if Next');
  NoCase(Source('  B: Integer;'#10,
    '  if Next() = 1 then'#10'    B := 1'#10'  else if Next() = 2 then'#10'    B := 2;'#10), 'if Next');
  Assert.IsFalse(Convert(Source('  B: Integer;'#10,
    '  case Next of'#10'    1: B := 1;'#10'    2: B := 2;'#10'  end;'#10), 'case Next', False, Output), Output);
end;

procedure TIfCaseTests.NoActionForVariablesAsLabels;
begin
  NoCase(Source('  A, B, X: Integer;'#10,
    '  if A = X then'#10'    B := 1'#10'  else if A = 2 then'#10'    B := 2;'#10), 'if A');
end;

procedure TIfCaseTests.NoActionForDuplicateLabels;
begin
  NoCase(Source('  A, B: Integer;'#10,
    '  if A = 1 then'#10'    B := 1'#10'  else if (A >= 0) and (A <= 3) then'#10'    B := 2;'#10), 'if A');
  NoCase(Source('  S: TState;'#10'  B: Integer;'#10,
    '  if S = stNew then'#10'    B := 1'#10'  else if S in [stPaid, stNew] then'#10'    B := 2;'#10), 'if S');
end;

procedure TIfCaseTests.NoActionForSingleCondition;
begin
  NoCase(Source('  A, B: Integer;'#10, '  if A = 1 then'#10'    B := 1'#10'  else'#10'    B := 2;'#10), 'if A');
end;

procedure TIfCaseTests.ConvertibleConditionsCounts;
var
  Text: string;
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Head: TSyntaxNode;
begin
  Text := Source('  A, B: Integer;'#10,
    '  if A = 1 then B := 1 else if A = 2 then B := 2 else if A = 3 then B := 3 else B := 4;'#10);
  Tree := TPascalParser.Parse(Text);
  Resolver := TNameResolver.Create(nil);
  try
    Resolver.PinTree(Tree, FileName);
    try
      Head := Tree.Root.Search(
        function(ANode: TSyntaxNode): TSyntaxSearchStep
        begin
          Result := TSyntaxSearchStep.Descend;
          if ANode.Kind = TSyntaxKind.IfStatement then
            Result := TSyntaxSearchStep.Found;
        end);
      Assert.AreEqual(3, TIfCase.ConvertibleConditions(Text, Tree, Head, TIfCaseLookup.FromResolver(Resolver, Tree,
        FileName)));
      Assert.AreEqual(0, TIfCase.ConvertibleConditions(Text, Tree, Head[2], TIfCaseLookup.FromResolver(Resolver, Tree,
        FileName)));
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TIfCaseTests);

end.
