unit Atlas.Common.Editing.Inline.Tests;

// Tests für Einbetten (#103, Teil A): Variable einbetten (Klammern, var-Abschnitt,
// Inline-Variable, Ablehnungen nach Datenfluss und Seiteneffekten) und Methode
// einbetten (einfache Form, Hilfsvariablen, var-Parameter, Vorgabewerte,
// Mitglieder mit Empfänger, Exit als Wächter, Ablehnungen). Ein "|" im Text
// steht für die Einfügemarke.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TInlineTests = class
  public
    [Test]
    procedure InlineVariableAddsParentheses;
    [Test]
    procedure InlineVariableRemovesVarSection;
    [Test]
    procedure InlineVariableFromInlineDeclaration;
    [Test]
    procedure InlineVariableFromDeclaration;
    [Test]
    procedure InlineVariableRejectsChangedValues;
    [Test]
    procedure InlineVariableChecksSideEffects;
    [Test]
    procedure InlineVariableRejectsOtherLocals;
    [Test]
    procedure InlineSimpleFunction;
    [Test]
    procedure InlineFunctionWithDefaultParameter;
    [Test]
    procedure InlineProcedureWithHelperVariable;
    [Test]
    procedure InlineProcedureIntoVarSection;
    [Test]
    procedure InlineVarParameters;
    [Test]
    procedure InlineIntoBranchAddsBlock;
    [Test]
    procedure InlineMethodWithReceiverAndGuard;
    [Test]
    procedure InlineProcedureGuardNegates;
    [Test]
    procedure InlineMethodRejects;
    [Test]
    procedure InlineMethodChecksMeaningAtCall;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.Inline;

const
  /// <summary>Routine mit const-Parameter: Die Datenflussanalyse weiß, dass Log ihr Argument nicht ändert.</summary>
  LogDecl = 'procedure Log(const A: Integer);'#10'begin'#10'end;'#10;

function Join(const ALines: array of string): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(ALines) do
    Result := Result + ALines[Index] + #10;
end;

function PositionOf(const AText: string; AIndex: Integer): TTextPosition;
var
  Index, Line, Character: Integer;
begin
  Line := 0;
  Character := 0;
  for Index := 1 to AIndex - 1 do
    if AText[Index] = #10 then
    begin
      Inc(Line);
      Character := 0;
    end
    else
      Inc(Character);
  Result := TTextPosition.Create(Line, Character);
end;

/// <summary>Text ohne "|" und die Stelle der Marke.</summary>
function Unmark(const AMarked: string; out APosition: TTextPosition): string;
var
  Start: Integer;
begin
  Start := Pos('|', AMarked);
  Result := StringReplace(AMarked, '|', '', []);
  APosition := PositionOf(Result, Start);
end;

function Unit_(const ABody: array of string): string;
begin
  Result := Join(['unit U;', '', 'interface', '', 'implementation', '']) + Join(ABody) + Join(['', 'end.']);
end;

/// <summary>Namensauflösung für Tests: FCount ist privates Feld von TCounter, Limit hat in AShadowTree eine
/// andere Bedeutung; alles andere ist ein globaler Name, Next, Log, Writeln, Inc und Run sind Routinen.</summary>
function FakeLookup(AShadowTree: TSyntaxTree): TInlineLookup;
begin
  Result :=
    function(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
      AOffset: Integer): TInlineMeaning
    var
      Name: string;
    begin
      Result := Default(TInlineMeaning);
      Name := ANames[High(ANames)];
      Result.Found := True;
      Result.Key := LowerCase(string.Join('.', ANames));
      if SameText(Name, 'FCount') or SameText(Name, 'FSecret') then
      begin
        Result.IsMember := True;
        Result.Container := 'TCounter';
        Result.Visibility := TInlineVisibility.Private;
        if SameText(Name, 'FSecret') then
          Result.Visibility := TInlineVisibility.StrictPrivate;
      end;
      if MatchText(Name, ['Next', 'Log', 'Writeln', 'Inc', 'Run']) then
        Result.IsRoutine := True;
      if MatchText(Name, ['Integer', 'string']) then
        Result.IsType := True;
      if SameText(Name, 'Limit') and (ATree = AShadowTree) then
        Result.Key := 'local.limit';
    end;
end;

/// <summary>Vorher und Nachher müssen fehlerfrei parsen (Abnahme von #103).</summary>
procedure CheckParses(const AText: string);
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)), AText);
  finally
    Tree.Free;
  end;
end;

function Options(AInline: Boolean): TInlineOptions;
begin
  Result := TInlineOptions.Default;
  Result.InlineVar := AInline;
  Result.Lookup := FakeLookup(nil);
end;

/// <summary>„Variable einbetten“ an der Marke; '-' ohne Angebot (Grund in AReason).</summary>
function Variable(const AMarked: string; out AReason: string): string; overload;
var
  Text: string;
  Position: TTextPosition;
  Tree: TSyntaxTree;
  Action: TCodeAction;
begin
  Text := Unmark(AMarked, Position);
  CheckParses(Text);
  Tree := TPascalParser.Parse(Text);
  try
    if not TInlineRefactoring.InlineVariable(TInlineSource.Create('u.pas', Text, Tree), Position, Options(True),
      Action, AReason) then
      Exit('-');
    Result := TChangeSignature.ApplyEdits(Text, Action.Edits);
    CheckParses(Result);
  finally
    Tree.Free;
  end;
end;

function Variable(const AMarked: string): string; overload;
var
  Reason: string;
begin
  Result := Variable(AMarked, Reason);
end;

/// <summary>„Methode einbetten“ an der Marke mit dem Rumpf aus derselben Datei; '-' ohne Angebot.</summary>
function Method(const AMarked: string; AInline: Boolean; out ATitle, AReason: string): string; overload;
var
  Text: string;
  Position: TTextPosition;
  Tree: TSyntaxTree;
  Action: TCodeAction;
  Call: TInlineCall;
  Routines: TArray<TSyntaxNode>;
  Source: TInlineSource;
begin
  ATitle := '';
  AReason := '';
  Text := Unmark(AMarked, Position);
  CheckParses(Text);
  Tree := TPascalParser.Parse(Text);
  try
    Source := TInlineSource.Create('u.pas', Text, Tree);
    if not TInlineRefactoring.CallAt(Tree, Text, Position, Call) then
      Exit('-');
    Routines := TInlineRefactoring.FindRoutines(Tree, Call.Name);
    if Length(Routines) <> 1 then
      Exit('-');
    if not TInlineRefactoring.InlineMethod(Source, Position, Source, Routines[0], Options(AInline), Action,
      AReason) then
      Exit('-');
    ATitle := Action.Title;
    Result := TChangeSignature.ApplyEdits(Text, Action.Edits);
    CheckParses(Result);
  finally
    Tree.Free;
  end;
end;

function Method(const AMarked: string; AInline: Boolean): string; overload;
var
  Title, Reason: string;
begin
  Result := Method(AMarked, AInline, Title, Reason);
end;

{ Variable einbetten }

procedure TInlineTests.InlineVariableAddsParentheses;
begin
  Assert.AreEqual(Unit_(['procedure P;', 'var', '  Y: Integer;', 'begin', '  Y := (1 + 2) * 3;',
    '  Writeln(1 + 2);', 'end;']),
    Variable(Unit_(['procedure P;', 'var', '  X, Y: Integer;', 'begin', '  X := 1 + 2;', '  Y := |X * 3;',
    '  Writeln(X);', 'end;'])));
end;

procedure TInlineTests.InlineVariableRemovesVarSection;
begin
  Assert.AreEqual(Unit_(['procedure P(A: Integer);', 'begin', '  Writeln(A * 2);', 'end;']),
    Variable(Unit_(['procedure P(A: Integer);', 'var', '  |X: Integer;', 'begin', '  X := A * 2;',
    '  Writeln(X);', 'end;'])));
end;

procedure TInlineTests.InlineVariableFromInlineDeclaration;
begin
  Assert.AreEqual(Unit_(['procedure P;', 'begin', '  Writeln(''a'');', '  Writeln(''a'');', 'end;']),
    Variable(Unit_(['procedure P;', 'begin', '  var |S := ''a'';', '  Writeln(S);', '  Writeln(S);', 'end;'])));
  // Deklaration ohne Startwert und eine Zuweisung.
  Assert.AreEqual(Unit_(['procedure P(A: Integer);', 'begin', '  Writeln(A);', 'end;']),
    Variable(Unit_(['procedure P(A: Integer);', 'begin', '  var S: Integer;', '  S := A;', '  Writeln(|S);',
    'end;'])));
end;

procedure TInlineTests.InlineVariableFromDeclaration;
begin
  // Feld ohne Aufruf dazwischen.
  Assert.AreEqual(Unit_(['procedure TFoo.P;', 'var', '  Y: Integer;', 'begin', '  Y := FCount + 1;', 'end;']),
    Variable(Unit_(['procedure TFoo.P;', 'var', '  Y, |X: Integer;', 'begin', '  X := FCount;',
    '  Y := X + 1;', 'end;'])));
end;

procedure TInlineTests.InlineVariableRejectsChangedValues;
var
  Reason: string;
begin
  // Zwei Zuweisungen.
  Assert.AreEqual('-', Variable(Unit_(['procedure P;', 'var', '  X: Integer;', 'begin', '  X := 1;',
    '  X := 2;', '  Writeln(|X);', 'end;']), Reason));
  Assert.Contains(Reason, 'mehrfach');
  // Lokaler Name des Ausdrucks ändert sich dazwischen.
  Assert.AreEqual('-', Variable(Unit_(['procedure P(A: Integer);', 'var', '  X: Integer;', 'begin',
    '  X := A;', '  A := 5;', '  Writeln(|X);', 'end;']), Reason));
  Assert.Contains(Reason, 'A ändert sich');
  // Feld und Aufruf dazwischen.
  Assert.AreEqual('-', Variable(Unit_(['procedure TFoo.P;', 'var', '  X: Integer;', 'begin', '  X := FCount;',
    '  Inc(FCount);', '  Writeln(|X);', 'end;']), Reason));
  // Nicht auf jedem Weg zugewiesen.
  Assert.AreEqual('-', Variable(Unit_(['procedure P(A: Boolean);', 'var', '  X: Integer;', 'begin',
    '  if A then', '    X := 1;', '  Writeln(|X);', 'end;']), Reason));
  // Feld in einer Schleife ohne die Zuweisung.
  Assert.AreEqual('-', Variable(Unit_(['procedure TFoo.P;', 'var', '  X, I: Integer;', 'begin',
    '  X := FCount;', '  for I := 1 to 3 do', '    FTotal := FTotal + |X;', 'end;']), Reason));
end;

procedure TInlineTests.InlineVariableChecksSideEffects;
var
  Reason: string;
begin
  Assert.AreEqual(Unit_(['procedure P;', 'var', '  Y: Integer;', 'begin', '  Y := Next();', 'end;']),
    Variable(Unit_(['procedure P;', 'var', '  X, Y: Integer;', 'begin', '  X := Next();', '  Y := |X;',
    'end;'])));
  // Zweimal gelesen.
  Assert.AreEqual('-', Variable(Unit_(['procedure P;', 'var', '  X: Integer;', 'begin', '  X := Next();',
    '  Writeln(X + |X);', 'end;']), Reason));
  Assert.Contains(Reason, 'mehrfach gelesen');
  // Davor wird etwas gelesen: die Reihenfolge änderte sich.
  Assert.AreEqual('-', Variable(Unit_(['procedure P(A: Integer);', 'var', '  X, Y: Integer;', 'begin',
    '  X := Next();', '  Y := A + |X;', 'end;']), Reason));
  Assert.Contains(Reason, 'Reihenfolge');
  // Routine ohne Klammern laut Namensauflösung.
  Assert.AreEqual('-', Variable(Unit_(['procedure P;', 'var', '  X: Integer;', 'begin', '  X := Next;',
    '  Writeln(|X, X);', 'end;']), Reason));
end;

procedure TInlineTests.InlineVariableRejectsOtherLocals;
var
  Reason: string;
begin
  Assert.AreEqual('-', Variable(Unit_(['procedure P(A: Integer);', 'begin', '  Writeln(|A);', 'end;']), Reason));
  Assert.AreEqual('-', Variable(Unit_(['procedure P;', 'var', '  I: Integer;', 'begin', '  for I := 1 to 2 do',
    '    Writeln(|I);', 'end;']), Reason));
  Assert.Contains(Reason, 'Laufvariable');
  Assert.AreEqual('-', Variable(Unit_(['procedure P;', 'var', '  X: Integer;', 'begin', '  X := 1;',
    '  Run(procedure begin Writeln(|X) end);', 'end;']), Reason));
  Assert.Contains(Reason, 'anonymen Methode');
  Assert.AreEqual('-', Variable(Unit_(['procedure P;', 'var', '  X: Integer;', 'begin', '  X := 1;',
    '  Inc(|X);', 'end;']), Reason));
  Assert.Contains(Reason, 'verändert');
end;

{ Methode einbetten }

procedure TInlineTests.InlineSimpleFunction;
var
  Title, Reason: string;
begin
  Assert.AreEqual(Unit_(['function Twice(A: Integer): Integer;', 'begin', '  Result := A * 2;', 'end;', '',
    'procedure P;', 'var', '  Y: Integer;', 'begin', '  Y := ((Y + 1) * 2) + 1;', 'end;']),
    Method(Unit_(['function Twice(A: Integer): Integer;', 'begin', '  Result := A * 2;', 'end;', '',
    'procedure P;', 'var', '  Y: Integer;', 'begin', '  Y := |Twice(Y + 1) + 1;', 'end;']), True, Title, Reason));
  Assert.AreEqual('Routine Twice einbetten', Title);
end;

procedure TInlineTests.InlineFunctionWithDefaultParameter;
begin
  Assert.AreEqual(Unit_(['function Scale(A: Integer; F: Integer = 10): Integer;', 'begin', '  Exit(A * F);',
    'end;', '', 'procedure P;', 'var', '  Y: Integer;', 'begin', '  Y := Y * 10;', 'end;']),
    Method(Unit_(['function Scale(A: Integer; F: Integer = 10): Integer;', 'begin', '  Exit(A * F);', 'end;', '',
    'procedure P;', 'var', '  Y: Integer;', 'begin', '  Y := Sca|le(Y);', 'end;']), True));
end;

procedure TInlineTests.InlineProcedureWithHelperVariable;
begin
  Assert.AreEqual(Unit_(['procedure Show(const S: string);', 'var', '  N: Integer;', 'begin',
    '  N := Length(S);', '  Writeln(S, N);', 'end;', '', 'procedure P;', 'var', '  N: Integer;', 'begin',
    '  N := 1;', '  var S: string := IntToStr(N);', '  var N2: Integer;', '  N2 := Length(S);',
    '  Writeln(S, N2);', 'end;']),
    Method(Unit_(['procedure Show(const S: string);', 'var', '  N: Integer;', 'begin', '  N := Length(S);',
    '  Writeln(S, N);', 'end;', '', 'procedure P;', 'var', '  N: Integer;', 'begin', '  N := 1;',
    '  |Show(IntToStr(N));', 'end;']), True));
end;

procedure TInlineTests.InlineProcedureIntoVarSection;
begin
  Assert.AreEqual(Unit_(['procedure Show(const S: string);', 'const', '  Prefix = ''> '';', 'var',
    '  N: Integer;', 'begin', '  N := Length(S);', '  Writeln(Prefix, S, N);', 'end;', '', 'procedure P;',
    'const', '  Prefix = 1;', '  Prefix2 = ''> '';', 'var', '  N: Integer;', '  S: string;', '  N2: Integer;',
    'begin', '  N := Prefix;', '  S := IntToStr(N);', '  N2 := Length(S);', '  Writeln(Prefix2, S, N2);',
    'end;']),
    Method(Unit_(['procedure Show(const S: string);', 'const', '  Prefix = ''> '';', 'var', '  N: Integer;',
    'begin', '  N := Length(S);', '  Writeln(Prefix, S, N);', 'end;', '', 'procedure P;', 'const',
    '  Prefix = 1;', 'var', '  N: Integer;', 'begin', '  N := Prefix;', '  |Show(IntToStr(N));', 'end;']),
    False));
end;

procedure TInlineTests.InlineVarParameters;
begin
  Assert.AreEqual(Unit_(['procedure Swap(var A, B: Integer);', 'var', '  T: Integer;', 'begin', '  T := A;',
    '  A := B;', '  B := T;', 'end;', '', 'procedure P;', 'var', '  X, Y, T: Integer;', 'begin',
    '  var T2: Integer;', '  T2 := X;', '  X := Y;', '  Y := T2;', 'end;']),
    Method(Unit_(['procedure Swap(var A, B: Integer);', 'var', '  T: Integer;', 'begin', '  T := A;',
    '  A := B;', '  B := T;', 'end;', '', 'procedure P;', 'var', '  X, Y, T: Integer;', 'begin',
    '  |Swap(X, Y);', 'end;']), True));
  // Kein einfaches var-Argument.
  Assert.AreEqual('-', Method(Unit_(['procedure Swap(var A, B: Integer);', 'begin', '  A := B;', 'end;', '',
    'procedure P;', 'begin', '  |Swap(Items[Next()], B);', 'end;']), True));
end;

procedure TInlineTests.InlineIntoBranchAddsBlock;
begin
  // Log ist hier deklariert: Sein Parameter ist const, A wird also nicht geändert.
  Assert.AreEqual(Unit_([LogDecl, 'procedure Log2(A: Integer);', 'begin', '  Log(A);', '  Log(A);', 'end;', '',
    'procedure P(X: Integer);', 'begin', '  if X > 0 then', '  begin', '    Log(X);', '    Log(X);', '  end;',
    'end;']),
    Method(Unit_([LogDecl, 'procedure Log2(A: Integer);', 'begin', '  Log(A);', '  Log(A);', 'end;', '',
    'procedure P(X: Integer);', 'begin', '  if X > 0 then', '  |Log2(X);', 'end;']), True));
end;

procedure TInlineTests.InlineMethodWithReceiverAndGuard;
const
  Head: array[0..18] of string = ('type', '  TCounter = class', '  private', '    FCount: Integer;', '  public',
    '    function Add(AValue: Integer): Integer;', '    procedure Run(C: TCounter);', '  end;', '',
    'function TCounter.Add(AValue: Integer): Integer;', 'begin', '  if AValue < 0 then', '    Exit(0);',
    '  FCount := FCount + AValue;', '  Result := FCount;', 'end;', '', 'procedure TCounter.Run(C: TCounter);', 'var');
var
  Title, Reason: string;
begin
  Assert.AreEqual(Join(['unit U;', '', 'interface', '', 'implementation', '']) + Join(Head) +
    Join(['  Y: Integer;', 'begin', '  var AddResult: Integer;', '  if 5 < 0 then', '    AddResult := 0', '  else',
    '  begin', '    C.FCount := C.FCount + 5;', '    AddResult := C.FCount;', '  end;', '  Y := AddResult;', 'end;',
    '', 'end.']),
    Method(Join(['unit U;', '', 'interface', '', 'implementation', '']) + Join(Head) +
    Join(['  Y: Integer;', 'begin', '  Y := C.|Add(5);', 'end;', '', 'end.']), True, Title, Reason));
  Assert.AreEqual('Methode Add einbetten', Title);
  // Außerhalb der Klasse ist das private Feld nicht zugänglich.
  Assert.AreEqual('-', Method(Join(['unit U;', '', 'interface', '', 'implementation', '']) +
    Join(Slice(Head, 17)) + Join(['procedure P(C: TCounter);', 'var', '  Y: Integer;', 'begin',
    '  Y := C.|Add(5);', 'end;', '', 'end.']), True, Title, Reason));
  Assert.Contains(Reason, 'nicht sichtbar');
end;

procedure TInlineTests.InlineProcedureGuardNegates;
begin
  Assert.AreEqual(Unit_([LogDecl, 'procedure Check(A: Integer);', 'begin', '  if A > 5 then', '    Exit;',
    '  Log(A);', 'end;', '', 'procedure P(X: Integer);', 'begin', '  if not (X > 5) then', '  begin', '    Log(X);',
    '  end;', 'end;']),
    Method(Unit_([LogDecl, 'procedure Check(A: Integer);', 'begin', '  if A > 5 then', '    Exit;', '  Log(A);',
    'end;', '', 'procedure P(X: Integer);', 'begin', '  |Check(X);', 'end;']), True));
end;

procedure TInlineTests.InlineMethodRejects;
var
  Title, Reason: string;
begin
  // Rekursion.
  Assert.AreEqual('-', Method(Unit_(['procedure R(A: Integer);', 'begin', '  if A > 0 then', '    R(A - 1);',
    'end;', '', 'procedure P;', 'begin', '  |R(3);', 'end;']), True, Title, Reason));
  Assert.Contains(Reason, 'rekursiv');
  // Zwei Exit.
  Assert.AreEqual('-', Method(Unit_(['function F(A: Integer): Integer;', 'begin', '  if A > 0 then', '    Exit(1);',
    '  Exit(2);', 'end;', '', 'procedure P;', 'begin', '  Writeln(|F(3));', 'end;']), True, Title, Reason));
  Assert.Contains(Reason, 'mehrere Exit');
  // Exit in einer Schleife.
  Assert.AreEqual('-', Method(Unit_(['procedure Q(A: Integer);', 'var', '  I: Integer;', 'begin',
    '  for I := 1 to A do', '    if I > 2 then', '      Exit;', 'end;', '', 'procedure P;', 'begin', '  |Q(3);',
    'end;']), True, Title, Reason));
  Assert.Contains(Reason, 'Exit');
  // Konstruktor.
  Assert.AreEqual('-', Method(Unit_(['constructor TFoo.Create;', 'begin', '  FCount := 1;', 'end;', '',
    'procedure P;', 'var', '  F: TFoo;', 'begin', '  F := TFoo.|Create;', 'end;']), True, Title, Reason));
  // Result gelesen, bevor es gesetzt ist.
  Assert.AreEqual('-', Method(Unit_(['function G: string;', 'begin', '  Result := Result + ''a'';', 'end;', '',
    'procedure P;', 'begin', '  Writeln(|G());', 'end;']), True, Title, Reason));
  Assert.Contains(Reason, 'Result');
  // Result in einer Schleife gesetzt.
  Assert.AreEqual('-', Method(Unit_(['function S(A: Integer): Integer;', 'var', '  I: Integer;', 'begin',
    '  Result := 0;', '  for I := 1 to A do', '    Result := Result + I;', 'end;', '', 'procedure P;', 'begin',
    '  Writeln(|S(3));', 'end;']), True, Title, Reason));
  Assert.Contains(Reason, 'Schleife');
  // Aufruf davor in derselben Anweisung.
  Assert.AreEqual('-', Method(Unit_(['function H(A: Integer): Integer;', 'begin', '  Log(A);', '  Result := A;',
    'end;', '', 'procedure P;', 'begin', '  Writeln(Next() + |H(1));', 'end;']), True, Title, Reason));
  Assert.Contains(Reason, 'Reihenfolge');
  // strict private außerhalb der Klasse.
  Assert.AreEqual('-', Method(Unit_(['function TCounter.Get: Integer;', 'begin', '  Result := FSecret;', 'end;',
    '', 'procedure P(C: TCounter);', 'begin', '  Writeln(C.|Get + 1);', 'end;']), True, Title, Reason));
  Assert.Contains(Reason, 'nicht sichtbar');
end;

procedure TInlineTests.InlineMethodChecksMeaningAtCall;
var
  CallerText, CalleeText, Reason: string;
  Position: TTextPosition;
  Caller, Callee: TSyntaxTree;
  Options: TInlineOptions;
  Action: TCodeAction;
begin
  CalleeText := Unit_(['function Clamp(A: Integer): Integer;', 'begin', '  Result := Min(A, Limit);', 'end;']);
  CallerText := Unmark(Unit_(['procedure P(Y: Integer);', 'begin', '  Y := |Clamp(Y);', 'end;']), Position);
  Callee := TPascalParser.Parse(CalleeText);
  Caller := TPascalParser.Parse(CallerText);
  try
    Options := TInlineOptions.Default;
    // Gleiche Bedeutung: aus der anderen Datei eingesetzt.
    Options.Lookup := FakeLookup(nil);
    Assert.IsTrue(TInlineRefactoring.InlineMethod(TInlineSource.Create('p.pas', CallerText, Caller), Position,
      TInlineSource.Create('c.pas', CalleeText, Callee), TInlineRefactoring.FindRoutines(Callee, 'Clamp')[0],
      Options, Action, Reason), Reason);
    Assert.AreEqual(Unit_(['procedure P(Y: Integer);', 'begin', '  Y := Min(Y, Limit);', 'end;']),
      TChangeSignature.ApplyEdits(CallerText, Action.Edits));
    // Limit bedeutet am Aufruf etwas anderes.
    Options.Lookup := FakeLookup(Caller);
    Assert.IsFalse(TInlineRefactoring.InlineMethod(TInlineSource.Create('p.pas', CallerText, Caller), Position,
      TInlineSource.Create('c.pas', CalleeText, Callee), TInlineRefactoring.FindRoutines(Callee, 'Clamp')[0],
      Options, Action, Reason));
    Assert.Contains(Reason, 'Limit');
  finally
    Caller.Free;
    Callee.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TInlineTests);

end.
