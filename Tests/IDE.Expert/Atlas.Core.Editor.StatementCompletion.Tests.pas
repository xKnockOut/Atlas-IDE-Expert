unit Atlas.Core.Editor.StatementCompletion.Tests;

// Tests für Anweisung vervollständigen (#697): je Anweisungsart vorher und
// nachher. "|" markiert vorher die Cursorzeile, nachher den Cursor.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Editor.StatementCompletion;

type
  [TestFixture]
  TAtlasStatementCompletionTests = class
  private
    function Completed(const AText: string; const AOptions: TAtlasStatementOptions): string; overload;
    function Completed(const AText: string): string; overload;
    function Completed(const AText: string; AMode: TAtlasBeginEndMode): string; overload;
  public
    [Test]
    procedure IfGetsThenAndCursorLine;
    [Test]
    procedure WhileWithOnGetDo;
    [Test]
    procedure ForGetsLimitOrDo;
    [Test]
    procedure BeginEndModes;
    [Test]
    procedure ExistingBeginBlock;
    [Test]
    procedure NoSemicolonBeforeElse;
    [Test]
    procedure ClosesBracketsAndStrings;
    [Test]
    procedure CompleteStatementMovesToNewLine;
    [Test]
    procedure CaseGetsOfAndEnd;
    [Test]
    procedure TryGetsFinallyOrExcept;
    [Test]
    procedure RepeatGetsUntil;
    [Test]
    procedure BeginGetsEnd;
    [Test]
    procedure MethodDeclarationAsksForBody;
    [Test]
    procedure RoutineInImplementationGetsBody;
    [Test]
    procedure KeepsTrailingComment;
    [Test]
    procedure NothingInCommentOrEmptyLine;
    [Test]
    procedure CaseBranchesReplaceCursorLine;
  end;

implementation

uses
  System.SysUtils;

function TAtlasStatementCompletionTests.Completed(const AText: string;
  const AOptions: TAtlasStatementOptions): string;
var
  Lines, NewLines: TArray<string>;
  Line, Index: Integer;
  Edit: TAtlasStatementEdit;
begin
  Result := '-';
  Lines := AText.Split([#10]);
  Line := -1;
  for Index := 0 to High(Lines) do
    if Pos('|', Lines[Index]) > 0 then
    begin
      Line := Index;
      Lines[Index] := StringReplace(Lines[Index], '|', '', []);
    end;
  if not TAtlasStatementCompleter.Complete(string.Join(#10, Lines), Line, AOptions, Edit) then
    Exit;
  NewLines := TAtlasStatementCompleter.Apply(Lines, Edit);
  NewLines[Edit.CursorLine] := Copy(NewLines[Edit.CursorLine], 1, Edit.CursorCharacter) + '|' +
    Copy(NewLines[Edit.CursorLine], Edit.CursorCharacter + 1, MaxInt);
  Result := string.Join(#10, NewLines);
end;

function TAtlasStatementCompletionTests.Completed(const AText: string): string;
begin
  Result := Completed(AText, TAtlasStatementOptions.Defaults);
end;

function TAtlasStatementCompletionTests.Completed(const AText: string; AMode: TAtlasBeginEndMode): string;
var
  Options: TAtlasStatementOptions;
begin
  Options := TAtlasStatementOptions.Defaults;
  Options.BeginEnd := AMode;
  Result := Completed(AText, Options);
end;

{ TAtlasStatementCompletionTests }

procedure TAtlasStatementCompletionTests.IfGetsThenAndCursorLine;
begin
  Assert.AreEqual('  if A > 0 then'#10'    |'#10'  B;', Completed('  if A > 0|'#10'  B;'));
  Assert.AreEqual('  if A then'#10'    |', Completed('  if A then|'));
  // Anweisung in derselben Zeile: nur das Semikolon.
  Assert.AreEqual('  if A then B := 1;|', Completed('  if A then B := 1|'));
  Assert.AreEqual('  end else if B then'#10'    |', Completed('  end else if B|'));
  Assert.AreEqual('  else'#10'    |', Completed('  else|'));
end;

procedure TAtlasStatementCompletionTests.WhileWithOnGetDo;
begin
  Assert.AreEqual('while not Eof(F) do'#10'  |', Completed('while not Eof(F|'));
  Assert.AreEqual('with Liste do'#10'  |', Completed('with Liste|'));
  Assert.AreEqual('  on E: EConvertError do'#10'    |', Completed('  on E: EConvertError|'));
end;

procedure TAtlasStatementCompletionTests.ForGetsLimitOrDo;
begin
  // Ohne Grenze: Platz für sie, der Cursor steht dort.
  Assert.AreEqual('for I := 0 to | do'#10'  ', Completed('for I := 0|'));
  Assert.AreEqual('for I := | to do'#10'  ', Completed('for I|'));
  Assert.AreEqual('for I := 0 to 9 do'#10'  |', Completed('for I := 0 to 9|'));
  Assert.AreEqual('for S in Liste do'#10'  |', Completed('for S in Liste|'));
  Assert.AreEqual('for I := 9 downto 0 do'#10'  |', Completed('for I := 9 downto 0|'));
end;

procedure TAtlasStatementCompletionTests.BeginEndModes;
const
  Two = 'if A|'#10'  B;'#10'  C;'#10'D;';
  One = 'if A|'#10'  B;'#10'D;';
begin
  // Always: immer, auch ohne Rumpf.
  Assert.AreEqual('if A then'#10'begin'#10'  |'#10'end;', Completed('if A|', TAtlasBeginEndMode.Always));
  Assert.AreEqual('if A then'#10'begin'#10'  B;|'#10'end;'#10'D;', Completed(One, TAtlasBeginEndMode.Always));
  // MultiLine: erst ab zwei Anweisungen.
  Assert.AreEqual('if A then'#10'begin'#10'  B;'#10'  C;|'#10'end;'#10'D;',
    Completed(Two, TAtlasBeginEndMode.MultiLine));
  Assert.AreEqual('if A then'#10'  B;|'#10'D;', Completed(One, TAtlasBeginEndMode.MultiLine));
  Assert.AreEqual('if A then'#10'  |', Completed('if A|', TAtlasBeginEndMode.MultiLine));
  // Never: nie.
  Assert.AreEqual('if A then'#10'  B;'#10'  C;|'#10'D;', Completed(Two, TAtlasBeginEndMode.Never));
  // Mehrzeiliger Aufruf ist eine Anweisung.
  Assert.AreEqual('if A then'#10'  B(1,'#10'    2);|'#10'D;',
    Completed('if A|'#10'  B(1,'#10'    2);'#10'D;', TAtlasBeginEndMode.MultiLine));
  // Vor else ohne Semikolon.
  Assert.AreEqual('if A then'#10'begin'#10'  |'#10'end'#10'else'#10'  C;',
    Completed('if A|'#10'else'#10'  C;', TAtlasBeginEndMode.Always));
end;

procedure TAtlasStatementCompletionTests.ExistingBeginBlock;
begin
  Assert.AreEqual('if A then'#10'begin'#10'  |'#10'end;', Completed('if A|'#10'begin'#10'end;'));
end;

procedure TAtlasStatementCompletionTests.NoSemicolonBeforeElse;
begin
  Assert.AreEqual('if A then'#10'  B := 1|'#10'else'#10'  B := 2;',
    Completed('if A then'#10'  B := 1|'#10'else'#10'  B := 2;'));
  // Ein vorhandenes Semikolon vor else fällt weg.
  Assert.AreEqual('if A then'#10'  B := 1|'#10'else', Completed('if A then'#10'  B := 1;|'#10'else'));
end;

procedure TAtlasStatementCompletionTests.ClosesBracketsAndStrings;
begin
  Assert.AreEqual('  ShowMessage(''Hallo'');|', Completed('  ShowMessage(''Hallo|'));
  Assert.AreEqual('  Writeln(Format(''%d'', [A]));|', Completed('  Writeln(Format(''%d'', [A|'));
  // Endet der Text auf "(" oder ",": Cursor vor den Klammern.
  Assert.AreEqual('  Add(A, |);', Completed('  Add(A,|'));
  Assert.AreEqual('  Foo(|);', Completed('  Foo(|'));
  Assert.AreEqual('  X := |;', Completed('  X :=|'));
  // Klammern in Strings zählen nicht.
  Assert.AreEqual('  S := ''(['';'#10'  |', Completed('  S := ''(['';|'));
  Assert.AreEqual('  A := B;|', Completed('  A := B|'));
end;

procedure TAtlasStatementCompletionTests.CompleteStatementMovesToNewLine;
begin
  Assert.AreEqual('  A := B;'#10'  |'#10'  C;', Completed('  A := B;|'#10'  C;'));
  Assert.AreEqual('  Foo(1);'#10'  |', Completed('  Foo(1);|'));
end;

procedure TAtlasStatementCompletionTests.CaseGetsOfAndEnd;
var
  Edit: TAtlasStatementEdit;
begin
  Assert.AreEqual('  case Kind of'#10'    |'#10'  end;', Completed('  case Kind|'));
  Assert.AreEqual('  case Kind of'#10'    skA: ;|'#10'  end;'#10'X;',
    Completed('  case Kind of|'#10'    skA: ;'#10'X;'));
  Assert.AreEqual('  case Kind of'#10'    |'#10'  end;', Completed('  case Kind of|'#10'  end;'));
  Assert.IsTrue(TAtlasStatementCompleter.Complete('  case Kind', 0, TAtlasStatementOptions.Defaults, Edit));
  Assert.AreEqual(Ord(TAtlasStatementFollowUp.CaseBranches), Ord(Edit.FollowUp));
  Assert.AreEqual(0, Edit.FollowLine);
  Assert.AreEqual(2, Edit.FollowCharacter);
end;

procedure TAtlasStatementCompletionTests.TryGetsFinallyOrExcept;
var
  Options: TAtlasStatementOptions;
begin
  Assert.AreEqual('  try'#10'    |'#10'  finally'#10#10'  end;', Completed('  try|'));
  Assert.AreEqual('  try'#10'    A;'#10'  finally'#10'    |'#10'  end;', Completed('  try|'#10'    A;'));
  Options := TAtlasStatementOptions.Defaults;
  Options.TryKind := TAtlasTryKind.TryExcept;
  Assert.AreEqual('  try'#10'    |'#10'  except'#10#10'  end;', Completed('  try|', Options));
  // Schon vollständig: nur in den Block.
  Assert.AreEqual('  try'#10'    |'#10'  finally'#10'  end;', Completed('  try|'#10'  finally'#10'  end;'));
  Assert.IsTrue(TAtlasStatementCompleter.NeedsTryKind('  try', 0));
  Assert.IsFalse(TAtlasStatementCompleter.NeedsTryKind('  try'#10'  except'#10'  end;', 0));
  Assert.IsFalse(TAtlasStatementCompleter.NeedsTryKind('  A;', 0));
end;

procedure TAtlasStatementCompletionTests.RepeatGetsUntil;
begin
  Assert.AreEqual('repeat'#10'  |'#10'until ;', Completed('repeat|'));
  Assert.AreEqual('repeat'#10'  Inc(I);'#10'until |;'#10'X;', Completed('repeat|'#10'  Inc(I);'#10'X;'));
  Assert.AreEqual('repeat'#10'  |'#10'until I > 3;', Completed('repeat|'#10'until I > 3;'));
end;

procedure TAtlasStatementCompletionTests.BeginGetsEnd;
begin
  Assert.AreEqual('begin'#10'  |'#10'end;', Completed('begin|'));
  Assert.AreEqual('  if A then begin'#10'    |'#10'  end;', Completed('  if A then begin|'));
  Assert.AreEqual('begin'#10'  A;|'#10'end;', Completed('begin|'#10'  A;'));
end;

procedure TAtlasStatementCompletionTests.MethodDeclarationAsksForBody;
const
  Unit_ =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '  public'#10 +
    '    procedure Lauf(A: Integer|'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';
var
  Edit: TAtlasStatementEdit;
  Options: TAtlasStatementOptions;
begin
  Assert.AreEqual(StringReplace(Unit_, 'Integer|', 'Integer);|', []), Completed(Unit_));
  Assert.IsTrue(TAtlasStatementCompleter.Complete(StringReplace(Unit_, '|', '', []), 5,
    TAtlasStatementOptions.Defaults, Edit));
  Assert.AreEqual(Ord(TAtlasStatementFollowUp.MethodBody), Ord(Edit.FollowUp));
  Assert.AreEqual(5, Edit.FollowLine);
  // Im Namen "Lauf".
  Assert.AreEqual(15, Edit.FollowCharacter);
  Options := TAtlasStatementOptions.Defaults;
  Options.MethodBody := False;
  Assert.IsTrue(TAtlasStatementCompleter.Complete(StringReplace(Unit_, '|', '', []), 5, Options, Edit));
  Assert.AreEqual(Ord(TAtlasStatementFollowUp.None), Ord(Edit.FollowUp));
  // Im interface-Teil ohne Typ: nur das Semikolon.
  Assert.AreEqual('interface'#10'procedure Frei;|'#10'implementation',
    Completed('interface'#10'procedure Frei|'#10'implementation'));
end;

procedure TAtlasStatementCompletionTests.RoutineInImplementationGetsBody;
begin
  Assert.AreEqual('implementation'#10'procedure TFoo.Lauf;'#10'begin'#10'  |'#10'end;',
    Completed('implementation'#10'procedure TFoo.Lauf|'));
  // Mit Rumpf oder var: nur das Semikolon.
  Assert.AreEqual('implementation'#10'function Wert: Integer;|'#10'var'#10'  I: Integer;',
    Completed('implementation'#10'function Wert: Integer|'#10'var'#10'  I: Integer;'));
end;

procedure TAtlasStatementCompletionTests.KeepsTrailingComment;
begin
  Assert.AreEqual('  A := B;| // Kommentar', Completed('  A := B| // Kommentar'));
  Assert.AreEqual('  if A then { warum }'#10'    |', Completed('  if A { warum }|'));
end;

procedure TAtlasStatementCompletionTests.NothingInCommentOrEmptyLine;
begin
  Assert.AreEqual('-', Completed('  |'));
  Assert.AreEqual('-', Completed('  // nur Kommentar|'));
  Assert.AreEqual('-', Completed('{ Block'#10'  if A|'#10'}'));
end;

procedure TAtlasStatementCompletionTests.CaseBranchesReplaceCursorLine;
var
  Lines: TArray<string>;
  Line, Character: Integer;
begin
  Lines := ['  case Kind of', '    ', '    skA: ;', '    skB: ;', '  end;'];
  Line := 1;
  Character := 4;
  Assert.IsTrue(TAtlasStatementCompleter.AfterCaseBranches(Lines, Line, Character));
  Assert.AreEqual(4, Integer(Length(Lines)));
  Assert.AreEqual('    skA: ;', Lines[1]);
  Assert.AreEqual(1, Line);
  Assert.AreEqual(9, Character);
  Lines := ['  case Kind of', '    ', '  end;'];
  Assert.IsFalse(TAtlasStatementCompleter.AfterCaseBranches(Lines, Line, Character));
  Lines := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStatementCompletionTests);

end.
