unit Atlas.Common.Editing.Conditions.Tests;

// Tests für „Bedingungen umformen“ (#656): umkehren mit Vergleichen, De Morgan,
// in und gemischtem and/or, früher Ausstieg in Routine und Schleifen,
// verschachtelte if zusammenfassen, doppelte Verneinung; keine Aktion, wenn
// Anweisungen folgen, ein else da ist oder ein Kommentar verloren ginge.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TConditionsTests = class
  public
    [Test]
    procedure InvertSwapsBranches;
    [Test]
    procedure InvertNegatesReadably;
    [Test]
    procedure InvertWithElseIfChain;
    [Test]
    procedure InvertWithEmptyThenDropsElse;
    [Test]
    procedure InvertNeedsElse;
    [Test]
    procedure EarlyExitInRoutine;
    [Test]
    procedure EarlyExitInLoops;
    [Test]
    procedure EarlyExitWrapsDirectLoopBody;
    [Test]
    procedure NoEarlyExitWhenStatementsFollow;
    [Test]
    procedure NoEarlyExitWithElseOrInlineVar;
    [Test]
    procedure MergeNestedIfs;
    [Test]
    procedure MergeKeepsOrderAndParentheses;
    [Test]
    procedure NoMergeWithElse;
    [Test]
    procedure RemovesDoubleNegation;
    [Test]
    procedure DoubleNegationKeepsPrecedence;
    [Test]
    procedure CommentsStayOrBlockTheAction;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.StatementText,
  Atlas.Common.Editing.Conditions,
  Atlas.Text.Lines;

type
  TConditionKind = (ckInvert, ckEarlyExit, ckMerge, ckDoubleNegation);

/// <summary>Programm mit der Routine Run und den Anweisungen ABody.</summary>
function Source(const ABody: string): string;
begin
  Result := 'program P;'#10'procedure Run;'#10'var'#10'  I: Integer;'#10'begin'#10 + ABody + 'end;'#10'begin'#10 +
    'end.'#10;
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

function PositionOf(const AText, AMarker: string): TTextPosition;
begin
  Result := TLineTable.Build(AText).PositionAt(Pos(AMarker, AText) - 1);
end;

/// <summary>Umformung AKind an AMarker; das Ergebnis muss fehlerfrei parsen.</summary>
function Rewrite(const AText, AMarker: string; AKind: TConditionKind; out AResult: string;
  out ATitle: string): Boolean;
var
  Tree, Check: TSyntaxTree;
  Done: TStatementRewrite;
  Layout: TStatementLayout;
  Position: TTextPosition;
begin
  AResult := '';
  ATitle := '';
  Tree := TPascalParser.Parse(AText);
  try
    Layout := TStatementLayout.Create('', '  ', #10);
    Position := PositionOf(AText, AMarker);
    case AKind of
      ckInvert:
        Result := TConditions.Invert(AText, Tree, Position, Layout, Done);
      ckEarlyExit:
        Result := TConditions.EarlyExit(AText, Tree, Position, Layout, Done);
      ckMerge:
        Result := TConditions.MergeNested(AText, Tree, Position, Layout, Done);
    else
      Result := TConditions.RemoveDoubleNegation(AText, Tree, Position, Done);
    end;
    if Result then
    begin
      AResult := ApplyEdit(AText, Done.Edit);
      ATitle := Done.Title;
      Check := TPascalParser.Parse(AResult);
      try
        Assert.AreEqual(0, Integer(Length(Check.Diagnostics)), AResult);
      finally
        Check.Free;
      end;
    end;
  finally
    Tree.Free;
  end;
end;

function Rewritten(const AText, AMarker: string; AKind: TConditionKind): string;
var
  Title: string;
begin
  Assert.IsTrue(Rewrite(AText, AMarker, AKind, Result, Title), 'Aktion fehlt');
end;

function Offered(const AText, AMarker: string; AKind: TConditionKind): Boolean;
var
  Text, Title: string;
begin
  Result := Rewrite(AText, AMarker, AKind, Text, Title);
end;

procedure TConditionsTests.InvertSwapsBranches;
var
  Text: string;
begin
  Text := Source('  if I = 1 then'#10'    A'#10'  else'#10'  begin'#10'    B;'#10'    C;'#10'  end;'#10);
  Assert.AreEqual(Source('  if I <> 1 then'#10'  begin'#10'    B;'#10'    C;'#10'  end'#10'  else'#10'    A;'#10),
    Rewritten(Text, 'if I', ckInvert));
end;

procedure TConditionsTests.InvertNegatesReadably;

  function Inverted(const ACondition: string): string;
  var
    Text, Line: string;
  begin
    Text := Source('  if ' + ACondition + ' then'#10'    A'#10'  else'#10'    B;'#10);
    Line := Rewritten(Text, 'if ', ckInvert);
    Result := Copy(Line, Pos('  if ', Line) + 5, MaxInt);
    Result := Copy(Result, 1, Pos(' then', Result) - 1);
  end;

begin
  Assert.AreEqual('I >= 3', Inverted('I < 3'));
  Assert.AreEqual('I <= 3', Inverted('I > 3'));
  Assert.AreEqual('not A or not B', Inverted('A and B'));
  Assert.AreEqual('(I <> 1) and not Ready', Inverted('(I = 1) or Ready'));
  Assert.AreEqual('not (I in [1, 2])', Inverted('I in [1, 2]'));
  Assert.AreEqual('Ready', Inverted('not Ready'));
  Assert.AreEqual('not Assigned(P) or (P.Count = 0)', Inverted('Assigned(P) and (P.Count <> 0)'));
  Assert.AreEqual('not A and ((I <> 1) or not Ready)', Inverted('A or (I = 1) and Ready'));
  Assert.AreEqual('not IsEmpty(S)', Inverted('IsEmpty(S)'));
  // Kein not A = B aus not (A = B).
  Assert.AreEqual('A <> B', Inverted('not not (A = B)'));
end;

procedure TConditionsTests.InvertWithElseIfChain;
var
  Text: string;
begin
  Text := Source('  if I = 1 then'#10'    A'#10'  else if I = 2 then'#10'    B'#10'  else'#10'    C;'#10);
  // Das innere if steht vor dem neuen else und bekommt begin … end.
  Assert.AreEqual(Source('  if I <> 1 then'#10'  begin'#10'    if I = 2 then'#10'      B'#10'    else'#10 +
    '      C;'#10'  end'#10'  else'#10'    A;'#10), Rewritten(Text, 'if I = 1', ckInvert));
  // Auf dem zweiten Glied: nur dieses wird umgekehrt.
  Assert.AreEqual(Source('  if I = 1 then'#10'    A'#10'  else if I <> 2 then'#10'    C'#10'  else'#10'    B;'#10),
    Rewritten(Text, 'if I = 2', ckInvert));
end;

procedure TConditionsTests.InvertWithEmptyThenDropsElse;
begin
  Assert.AreEqual(Source('  if not Ready then'#10'    B;'#10), Rewritten(Source('  if Ready then'#10'  else'#10 +
    '    B;'#10), 'if', ckInvert));
  // Vor dem else eines äußeren if gäbe es ein hängendes else.
  Assert.IsFalse(Offered(Source('  if Q then if Ready then else B else C;'#10), 'if Ready', ckInvert));
end;

procedure TConditionsTests.InvertNeedsElse;
begin
  Assert.IsFalse(Offered(Source('  if I = 1 then'#10'    A;'#10'  B;'#10), 'if', ckInvert));
end;

procedure TConditionsTests.EarlyExitInRoutine;
var
  Title, Text, Done: string;
begin
  Text := Source('  A;'#10'  if Assigned(P) and Ready then'#10'  begin'#10'    B;'#10'    C;'#10'  end;'#10);
  Assert.IsTrue(Rewrite(Text, 'if', ckEarlyExit, Done, Title));
  Text := Done;
  Assert.AreEqual(TConditions.EarlyExitTitle, Title);
  Assert.AreEqual(Source('  A;'#10'  if not Assigned(P) or not Ready then Exit;'#10'  B;'#10'  C;'#10), Text);
  // Ein einzelner Zweig ohne begin … end, auch ohne Semikolon vor end.
  Assert.AreEqual(Source('  if I >= 3 then Exit;'#10'  B;'#10), Rewritten(Source('  if I < 3 then'#10'    B'#10),
    'if', ckEarlyExit));
end;

procedure TConditionsTests.EarlyExitInLoops;
var
  Title, Text, Done: string;
begin
  Text := Source('  while I < 10 do'#10'  begin'#10'    Inc(I);'#10'    if I mod 2 = 0 then'#10'    begin'#10 +
    '      A;'#10'      B;'#10'    end;'#10'  end;'#10);
  Assert.IsTrue(Rewrite(Text, 'if', ckEarlyExit, Done, Title));
  Text := Done;
  Assert.AreEqual(TConditions.EarlyContinueTitle, Title);
  Assert.AreEqual(Source('  while I < 10 do'#10'  begin'#10'    Inc(I);'#10'    if I mod 2 <> 0 then Continue;'#10 +
    '    A;'#10'    B;'#10'  end;'#10), Text);
  Assert.AreEqual(Source('  repeat'#10'    Inc(I);'#10'    if not Done then Continue;'#10'    A;'#10 +
    '  until I > 3;'#10), Rewritten(Source('  repeat'#10'    Inc(I);'#10'    if Done then'#10'      A;'#10 +
    '  until I > 3;'#10), 'if', ckEarlyExit));
  Assert.AreEqual(Source('  for I := 1 to 3 do'#10'  begin'#10'    if I = 2 then Continue;'#10'    A;'#10 +
    '  end;'#10), Rewritten(Source('  for I := 1 to 3 do'#10'  begin'#10'    if I <> 2 then'#10'      A;'#10 +
    '  end;'#10), 'if', ckEarlyExit));
end;

procedure TConditionsTests.EarlyExitWrapsDirectLoopBody;
begin
  Assert.AreEqual(Source('  for I := 1 to 3 do'#10'  begin'#10'    if I = 2 then Continue;'#10'    A;'#10'    B;'#10 +
    '  end;'#10), Rewritten(Source('  for I := 1 to 3 do'#10'    if I <> 2 then'#10'    begin'#10'      A;'#10 +
    '      B;'#10'    end;'#10), 'if', ckEarlyExit));
end;

procedure TConditionsTests.NoEarlyExitWhenStatementsFollow;
begin
  Assert.IsFalse(Offered(Source('  if Ready then'#10'    A;'#10'  B;'#10), 'if', ckEarlyExit));
  // Im then-Zweig eines anderen if: kein Ende der Routine.
  Assert.IsFalse(Offered(Source('  if Q then'#10'  begin'#10'    if Ready then'#10'      A;'#10'  end;'#10),
    'if Ready', ckEarlyExit));
  // Im Hauptprogramm nicht.
  Assert.IsFalse(Offered('program P;'#10'begin'#10'  if Ready then'#10'    A;'#10'end.'#10, 'if', ckEarlyExit));
end;

procedure TConditionsTests.NoEarlyExitWithElseOrInlineVar;
begin
  Assert.IsFalse(Offered(Source('  if Ready then'#10'    A'#10'  else'#10'    B;'#10), 'if', ckEarlyExit));
  Assert.IsFalse(Offered(Source('  if Ready then'#10'  begin'#10'    var X := 1;'#10'    A(X);'#10'  end;'#10), 'if',
    ckEarlyExit));
end;

procedure TConditionsTests.MergeNestedIfs;
var
  Expected: string;
begin
  Expected := Source('  if Assigned(P) and Ready then'#10'    A;'#10);
  Assert.AreEqual(Expected, Rewritten(Source('  if Assigned(P) then'#10'    if Ready then'#10'      A;'#10), 'if',
    ckMerge));
  // Auch mit begin … end um das innere if und auf dem inneren Kopf.
  Assert.AreEqual(Expected, Rewritten(Source('  if Assigned(P) then'#10'  begin'#10'    if Ready then'#10 +
    '      A;'#10'  end;'#10), 'if Ready', ckMerge));
  Assert.AreEqual(Source('  if Q and Ready then'#10'  begin'#10'    A;'#10'    B;'#10'  end;'#10),
    Rewritten(Source('  if Q then'#10'    if Ready then'#10'    begin'#10'      A;'#10'      B;'#10'    end;'#10),
    'if', ckMerge));
end;

procedure TConditionsTests.MergeKeepsOrderAndParentheses;
begin
  Assert.AreEqual(Source('  if (I = 1) and (A or B) then'#10'    C;'#10), Rewritten(Source('  if I = 1 then'#10 +
    '    if A or B then'#10'      C;'#10), 'if', ckMerge));
  Assert.AreEqual(Source('  if (I > 0) and (I < 9) then'#10'    C;'#10), Rewritten(Source('  if (I > 0) then'#10 +
    '    if I < 9 then'#10'      C;'#10), 'if', ckMerge));
end;

procedure TConditionsTests.NoMergeWithElse;
begin
  Assert.IsFalse(Offered(Source('  if A then'#10'    if B then'#10'      C'#10'    else'#10'      D;'#10), 'if A',
    ckMerge));
  Assert.IsFalse(Offered(Source('  if A then'#10'  begin'#10'    if B then'#10'      C;'#10'  end'#10'  else'#10 +
    '    D;'#10), 'if A', ckMerge));
  Assert.IsFalse(Offered(Source('  if A then'#10'  begin'#10'    if B then'#10'      C;'#10'    D;'#10'  end;'#10),
    'if A', ckMerge));
end;

procedure TConditionsTests.RemovesDoubleNegation;
begin
  Assert.AreEqual(Source('  if Ready then A;'#10), Rewritten(Source('  if not not Ready then A;'#10), 'not',
    ckDoubleNegation));
  Assert.AreEqual(Source('  if A = B then C;'#10), Rewritten(Source('  if not (A <> B) then C;'#10), 'not',
    ckDoubleNegation));
  Assert.AreEqual(Source('  X := False;'#10), Rewritten(Source('  X := not True;'#10), 'not', ckDoubleNegation));
  // Das innere not von not not not X: das äußerste wird umgeformt.
  Assert.AreEqual(Source('  if not X then A;'#10), Rewritten(Source('  if not not not X then A;'#10), 'not X',
    ckDoubleNegation));
  Assert.IsFalse(Offered(Source('  if not Ready then A;'#10), 'not', ckDoubleNegation));
  Assert.IsFalse(Offered(Source('  if not (A and B) then C;'#10), 'not', ckDoubleNegation));
end;

procedure TConditionsTests.DoubleNegationKeepsPrecedence;
begin
  // A = B bindet schwächer als and: Klammern bleiben nötig.
  Assert.AreEqual(Source('  if X and (A = B) then C;'#10), Rewritten(Source('  if X and not (A <> B) then C;'#10),
    'not', ckDoubleNegation));
  Assert.AreEqual(Source('  F(A = B);'#10), Rewritten(Source('  F(not (A <> B));'#10), 'not', ckDoubleNegation));
end;

procedure TConditionsTests.CommentsStayOrBlockTheAction;
begin
  Assert.AreEqual(Source('  if I <> 1 then'#10'    B // zwei'#10'  else'#10'    // eins'#10'    A;'#10),
    Rewritten(Source('  if I = 1 then'#10'    // eins'#10'    A'#10'  else'#10'    B; // zwei'#10), 'if', ckInvert));
  Assert.AreEqual(Source('  if not Ready then Exit;'#10'  // Schritt'#10'  A;'#10'  B; // Ende'#10),
    Rewritten(Source('  if Ready then'#10'  begin'#10'    // Schritt'#10'    A;'#10'    B; // Ende'#10'  end;'#10),
    'if', ckEarlyExit));
  // Kommentar in der Bedingung bzw. zwischen den if ginge verloren.
  Assert.IsFalse(Offered(Source('  if Ready {bereit} then'#10'    A'#10'  else'#10'    B;'#10), 'if', ckInvert));
  Assert.IsFalse(Offered(Source('  if A then'#10'    // innen'#10'    if B then'#10'      C;'#10), 'if A', ckMerge));
  Assert.IsFalse(Offered(Source('  if not {x} not A then C;'#10), 'not', ckDoubleNegation));
end;

initialization
  TDUnitX.RegisterTestFixture(TConditionsTests);

end.
