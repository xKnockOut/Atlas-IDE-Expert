unit Atlas.Common.Editing.Extract.Tests;

// Tests für Extrahieren (#50, Teil A): Methode extrahieren mit Parametern nach
// Datenfluss, Ablehnungen (Exit, Result, Teilauswahl, Break), Variable
// einführen (inline, var-Abschnitt, alle Vorkommen) und Konstante extrahieren.
// Die Auswahl steht in den Texten zwischen « und ».

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TExtractTests = class
  public
    [Test]
    procedure ExtractMethodWithConstAndVarParameters;
    [Test]
    procedure ExtractRoutineWithOutParameter;
    [Test]
    procedure ExtractMethodRejectsExit;
    [Test]
    procedure ExtractMethodRejectsResultAndPartialSelection;
    [Test]
    procedure ExtractMethodChecksBreak;
    [Test]
    procedure ExtractMethodInLoopUsesVar;
    [Test]
    procedure ExtractMethodCopiesConstants;
    [Test]
    procedure IntroduceInlineVariable;
    [Test]
    procedure IntroduceVariableInVarSection;
    [Test]
    procedure IntroduceVariableForAllOccurrences;
    [Test]
    procedure IntroduceVariableRejectsUnsafePlaces;
    [Test]
    procedure ExtractConstantInRoutineAndUnit;
    [Test]
    procedure ExtractConstantRejectsNonLiterals;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.Extract;

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

/// <summary>Text ohne « und » und die Auswahl dazwischen; ein "|" steht für den Cursor.</summary>
function Unmark(const AMarked: string; out ARange: TTextRange): string;
var
  Start, Finish: Integer;
begin
  Result := AMarked;
  Start := Pos('|', Result);
  if Start > 0 then
  begin
    Result := StringReplace(Result, '|', '', []);
    ARange := TTextRange.Create(PositionOf(Result, Start), PositionOf(Result, Start));
    Exit;
  end;
  Start := Pos('«', Result);
  Result := StringReplace(Result, '«', '', []);
  Finish := Pos('»', Result);
  Result := StringReplace(Result, '»', '', []);
  ARange := TTextRange.Create(PositionOf(Result, Start), PositionOf(Result, Finish));
end;

type
  TRun = reference to function(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
    out AAction: TCodeAction): Boolean;

/// <summary>Ergebnis der Aktion auf AMarked; '-' ohne Angebot.</summary>
function Apply(const AMarked: string; const ARun: TRun; out ATitle: string): string;
var
  Text: string;
  Range: TTextRange;
  Tree: TSyntaxTree;
  Action: TCodeAction;
begin
  ATitle := '';
  Text := Unmark(AMarked, Range);
  Tree := TPascalParser.Parse(Text);
  try
    if not ARun(Text, Tree, Range, Action) then
      Exit('-');
    ATitle := Action.Title;
    Result := TChangeSignature.ApplyEdits(Text, Action.Edits);
  finally
    Tree.Free;
  end;
end;

function Options(AInline: Boolean): TExtractOptions;
begin
  Result := TExtractOptions.Default;
  Result.InlineVar := AInline;
end;

function Method(const AMarked: string; out AReason: string): string;
var
  Title, Reason: string;
begin
  Reason := '';
  Result := Apply(AMarked,
    function(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange; out AAction: TCodeAction): Boolean
    begin
      Result := TExtractRefactoring.ExtractMethod(AText, ATree, ARange, Options(True), AAction, Reason);
    end, Title);
  AReason := Reason;
end;

function Variable(const AMarked: string; AInline, AAll: Boolean; out ATitle: string): string;
begin
  Result := Apply(AMarked,
    function(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange; out AAction: TCodeAction): Boolean
    begin
      Result := TExtractRefactoring.IntroduceVariable(AText, ATree, ARange, Options(AInline), AAll, AAction);
    end, ATitle);
end;

function Constant(const AMarked: string; AUnit: Boolean; out ATitle: string): string;
begin
  Result := Apply(AMarked,
    function(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange; out AAction: TCodeAction): Boolean
    begin
      Result := TExtractRefactoring.ExtractConstant(AText, ATree, ARange, Options(True), AUnit, AAction);
    end, ATitle);
end;

procedure AssertParses(const AText: string);
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)), 'parst fehlerfrei');
  finally
    Tree.Free;
  end;
end;

{ TExtractTests }

procedure TExtractTests.ExtractMethodWithConstAndVarParameters;
var
  Reason, Result_: string;
begin
  // Zusätzliche Abnahme: liest AValue, schreibt Total (danach gelesen) → const und var; Temp nur innen.
  Result_ := Method(Join([
    'unit U;',
    'interface',
    'type',
    '  TRechner = class',
    '  private',
    '    FWert: Integer;',
    '  public',
    '    procedure Rechne(AValue: Integer);',
    '  end;',
    'implementation',
    'procedure TRechner.Rechne(AValue: Integer);',
    'var',
    '  Total, Temp: Integer;',
    'begin',
    '  Total := 0;',
    '  «Temp := AValue * 2;',
    '  Total := Total + Temp;»',
    '  FWert := Total;',
    'end;',
    'end.']), Reason);
  Assert.AreEqual(Join([
    'unit U;',
    'interface',
    'type',
    '  TRechner = class',
    '  private',
    '    FWert: Integer;',
    '    procedure ExtractedMethod(const AValue: Integer; var Total: Integer);',
    '  public',
    '    procedure Rechne(AValue: Integer);',
    '  end;',
    'implementation',
    'procedure TRechner.ExtractedMethod(const AValue: Integer; var Total: Integer);',
    'var',
    '  Temp: Integer;',
    'begin',
    '  Temp := AValue * 2;',
    '  Total := Total + Temp;',
    'end;',
    '',
    'procedure TRechner.Rechne(AValue: Integer);',
    'var',
    '  Total: Integer;',
    'begin',
    '  Total := 0;',
    '  ExtractedMethod(AValue, Total);',
    '  FWert := Total;',
    'end;',
    'end.']), Result_, Reason);
  AssertParses(Result_);
end;

procedure TExtractTests.ExtractRoutineWithOutParameter;
var
  Reason, Result_: string;
begin
  // Unbedingt zuerst geschrieben und danach gelesen → out; ohne Klasse eine Routine davor.
  Result_ := Method(Join([
    'program P;',
    'procedure Run;',
    'var',
    '  A, B: Integer;',
    'begin',
    '  A := 1;',
    '  «B := A + 1;»',
    '  Writeln(B);',
    'end;',
    'begin',
    'end.']), Reason);
  Assert.AreEqual(Join([
    'program P;',
    'procedure ExtractedMethod(const A: Integer; out B: Integer);',
    'begin',
    '  B := A + 1;',
    'end;',
    '',
    'procedure Run;',
    'var',
    '  A, B: Integer;',
    'begin',
    '  A := 1;',
    '  ExtractedMethod(A, B);',
    '  Writeln(B);',
    'end;',
    'begin',
    'end.']), Result_, Reason);
  AssertParses(Result_);
end;

procedure TExtractTests.ExtractMethodRejectsExit;
var
  Reason: string;
begin
  // Zusätzliche Abnahme: Ein Block mit Exit wird nicht angeboten.
  Assert.AreEqual('-', Method(Join([
    'program P;',
    'procedure Run(A: Integer);',
    'begin',
    '  «if A < 0 then',
    '    Exit;',
    '  A := A + 1;»',
    'end;',
    'begin',
    'end.']), Reason));
  Assert.AreEqual('Exit in der Auswahl', Reason);
  Assert.AreEqual('-', Method(Join([
    'program P;',
    'procedure Run(A: Integer);',
    'begin',
    '  «Exit(1);»',
    'end;',
    'begin',
    'end.']), Reason));
end;

procedure TExtractTests.ExtractMethodRejectsResultAndPartialSelection;
var
  Reason: string;
begin
  Assert.AreEqual('-', Method(Join([
    'program P;',
    'function Run(A: Integer): Integer;',
    'begin',
    '  «Result := A * 2;»',
    'end;',
    'begin',
    'end.']), Reason));
  Assert.AreEqual('Result in der Auswahl', Reason);
  // Nur ein Teil einer Anweisung.
  Assert.AreEqual('-', Method(Join([
    'program P;',
    'procedure Run(A: Integer);',
    'begin',
    '  A := «A * 2»;',
    'end;',
    'begin',
    'end.']), Reason));
  Assert.AreEqual('keine vollständigen Anweisungen', Reason);
  // with um die Auswahl.
  Assert.AreEqual('-', Method(Join([
    'program P;',
    'procedure Run(A: TObject);',
    'begin',
    '  with A do',
    '  begin',
    '    «Free;»',
    '  end;',
    'end;',
    'begin',
    'end.']), Reason));
end;

procedure TExtractTests.ExtractMethodChecksBreak;
var
  Reason, Result_: string;
begin
  // Break ohne Schleife in der Auswahl springt hinaus.
  Assert.AreEqual('-', Method(Join([
    'program P;',
    'procedure Run;',
    'var',
    '  I: Integer;',
    'begin',
    '  for I := 1 to 3 do',
    '  begin',
    '    «if I = 2 then',
    '      Break;»',
    '  end;',
    'end;',
    'begin',
    'end.']), Reason));
  Assert.AreEqual('Break springt aus der Auswahl', Reason);
  // Mit der ganzen Schleife ist Break innen; I wird nur innen gebraucht.
  Result_ := Method(Join([
    'program P;',
    'procedure Run;',
    'var',
    '  I: Integer;',
    'begin',
    '  «for I := 1 to 3 do',
    '    if I = 2 then',
    '      Break;»',
    'end;',
    'begin',
    'end.']), Reason);
  Assert.AreEqual(Join([
    'program P;',
    'procedure ExtractedMethod;',
    'var',
    '  I: Integer;',
    'begin',
    '  for I := 1 to 3 do',
    '    if I = 2 then',
    '      Break;',
    'end;',
    '',
    'procedure Run;',
    'begin',
    '  ExtractedMethod;',
    'end;',
    'begin',
    'end.']), Result_, Reason);
end;

procedure TExtractTests.ExtractMethodInLoopUsesVar;
var
  Reason, Result_: string;
begin
  // In einer Schleife: Sum wird vor der Auswahl in der Schleife gelesen, also „danach“; zuerst unbedingt
  // geschrieben → out statt lokaler Variable.
  Result_ := Method(Join([
    'program P;',
    'procedure Run;',
    'var',
    '  I, Sum: Integer;',
    'begin',
    '  Sum := 0;',
    '  for I := 1 to 3 do',
    '  begin',
    '    Writeln(Sum);',
    '    «Sum := I;»',
    '  end;',
    'end;',
    'begin',
    'end.']), Reason);
  Assert.Contains(Result_, 'procedure ExtractedMethod(const I: Integer; out Sum: Integer);', Reason);
  AssertParses(Result_);
end;

procedure TExtractTests.ExtractMethodCopiesConstants;
var
  Reason, Result_: string;
begin
  Result_ := Method(Join([
    'program P;',
    'procedure Run;',
    'const',
    '  Faktor = 3;',
    'var',
    '  X: Integer;',
    'begin',
    '  X := 2;',
    '  «Writeln(X * Faktor);»',
    'end;',
    'begin',
    'end.']), Reason);
  Assert.AreEqual(Join([
    'program P;',
    'procedure ExtractedMethod(const X: Integer);',
    'const',
    '  Faktor = 3;',
    'begin',
    '  Writeln(X * Faktor);',
    'end;',
    '',
    'procedure Run;',
    'const',
    '  Faktor = 3;',
    'var',
    '  X: Integer;',
    'begin',
    '  X := 2;',
    '  ExtractedMethod(X);',
    'end;',
    'begin',
    'end.']), Result_, Reason);
end;

procedure TExtractTests.IntroduceInlineVariable;
var
  Title: string;
begin
  // Zusätzliche Abnahme (Teil 1): mit Inline-Variablen (Delphi 12) entsteht var X := ….
  Assert.AreEqual(Join([
    'program P;',
    'procedure Run(Count: Integer);',
    'begin',
    '  var Value := Count * 2;',
    '  Writeln(Format(''%d'', [Value]));',
    'end;',
    'begin',
    'end.']), Variable(Join([
    'program P;',
    'procedure Run(Count: Integer);',
    'begin',
    '  Writeln(Format(''%d'', [«Count * 2»]));',
    'end;',
    'begin',
    'end.']), True, False, Title));
  Assert.AreEqual('Variable einführen', Title);
end;

procedure TExtractTests.IntroduceVariableInVarSection;
var
  Title: string;
begin
  // Zusätzliche Abnahme (Teil 2): refactoring.inlineVar: false → Eintrag im var-Abschnitt.
  Assert.AreEqual(Join([
    'program P;',
    'procedure Run(Count: Integer);',
    'var',
    '  Text: string;',
    '  Value: Integer;',
    'begin',
    '  Value := Count * 2;',
    '  Text := IntToStr(Value);',
    'end;',
    'begin',
    'end.']), Variable(Join([
    'program P;',
    'procedure Run(Count: Integer);',
    'var',
    '  Text: string;',
    'begin',
    '  Text := IntToStr(«Count * 2»);',
    'end;',
    'begin',
    'end.']), False, False, Title));
  // Ohne var-Abschnitt entsteht einer vor begin.
  Assert.AreEqual(Join([
    'program P;',
    'procedure Run(const AText: string);',
    'var',
    '  Value: string;',
    'begin',
    '  Value := AText + ''!'';',
    '  Writeln(Value);',
    'end;',
    'begin',
    'end.']), Variable(Join([
    'program P;',
    'procedure Run(const AText: string);',
    'begin',
    '  Writeln(«AText + ''!''»);',
    'end;',
    'begin',
    'end.']), False, False, Title));
end;

procedure TExtractTests.IntroduceVariableForAllOccurrences;
var
  Title, Marked: string;
begin
  Marked := Join([
    'program P;',
    'procedure Run(Liste: TStrings);',
    'var',
    '  A, B: Integer;',
    'begin',
    '  A := «Liste.Count» + 1;',
    '  B := Liste.Count + 2;',
    'end;',
    'begin',
    'end.']);
  Assert.AreEqual(Join([
    'program P;',
    'procedure Run(Liste: TStrings);',
    'var',
    '  A, B: Integer;',
    'begin',
    '  var Count := Liste.Count;',
    '  A := Count + 1;',
    '  B := Count + 2;',
    'end;',
    'begin',
    'end.']), Variable(Marked, True, True, Title));
  Assert.AreEqual('Variable einführen (alle 2 Vorkommen)', Title);
  // Ändert sich ein Name dazwischen, gibt es nur die einzelne Variante.
  Assert.AreEqual('-', Variable(StringReplace(Marked, '  B := Liste', '  Liste := nil;'#10'  B := Liste', []),
    True, True, Title));
  // Nur ein Vorkommen: keine Variante für alle.
  Assert.AreEqual('-', Variable(StringReplace(Marked, 'Liste.Count + 2', '2', []), True, True, Title));
end;

procedure TExtractTests.IntroduceVariableRejectsUnsafePlaces;
var
  Title: string;
begin
  // Ziel einer Zuweisung, Bedingung einer Schleife, Zweig ohne begin, kein ganzer Ausdruck.
  Assert.AreEqual('-', Variable(Join([
    'program P;',
    'procedure Run(var A: Integer);',
    'begin',
    '  «A» := 1;',
    'end;',
    'begin',
    'end.']), True, False, Title));
  Assert.AreEqual('-', Variable(Join([
    'program P;',
    'procedure Run(A: Integer);',
    'begin',
    '  while «A > 0» do',
    '    Dec(A);',
    'end;',
    'begin',
    'end.']), True, False, Title));
  Assert.AreEqual('-', Variable(Join([
    'program P;',
    'procedure Run(L: TList);',
    'begin',
    '  if L <> nil then',
    '    Writeln(«L.Count»);',
    'end;',
    'begin',
    'end.']), True, False, Title));
  Assert.AreEqual('-', Variable(Join([
    'program P;',
    'procedure Run(A, B: Integer);',
    'begin',
    '  Writeln(A «+ B»);',
    'end;',
    'begin',
    'end.']), True, False, Title));
end;

procedure TExtractTests.ExtractConstantInRoutineAndUnit;
var
  Title, Marked: string;
begin
  Marked := Join([
    'unit U;',
    'interface',
    'implementation',
    'procedure Run;',
    'begin',
    '  Sleep(«250»);',
    'end;',
    'end.']);
  Assert.AreEqual(Join([
    'unit U;',
    'interface',
    'implementation',
    'procedure Run;',
    'const',
    '  NewConstant = 250;',
    'begin',
    '  Sleep(NewConstant);',
    'end;',
    'end.']), Constant(Marked, False, Title));
  Assert.AreEqual('Konstante extrahieren', Title);
  Assert.AreEqual(Join([
    'unit U;',
    'interface',
    'implementation',
    'const',
    '  NewConstant = 250;',
    '',
    'procedure Run;',
    'begin',
    '  Sleep(NewConstant);',
    'end;',
    'end.']), Constant(Marked, True, Title));
  Assert.AreEqual('Konstante in der Unit extrahieren', Title);
  // Cursor im Literal genügt; ein vorhandener const-Abschnitt wird ergänzt.
  Assert.AreEqual(Join([
    'unit U;',
    'interface',
    'implementation',
    'procedure Run;',
    'const',
    '  Pause = 10;',
    '  NewConstant = ''Hallo'';',
    'begin',
    '  Writeln(NewConstant);',
    'end;',
    'end.']), Constant(Join([
    'unit U;',
    'interface',
    'implementation',
    'procedure Run;',
    'const',
    '  Pause = 10;',
    'begin',
    '  Writeln(''Ha|llo'');',
    'end;',
    'end.']), False, Title));
end;

procedure TExtractTests.ExtractConstantRejectsNonLiterals;
var
  Title: string;
begin
  Assert.AreEqual('-', Constant(Join([
    'program P;',
    'procedure Run(A: Integer);',
    'begin',
    '  Writeln(«A»);',
    'end;',
    'begin',
    'end.']), False, Title));
  // Außerhalb einer Routine.
  Assert.AreEqual('-', Constant(Join([
    'unit U;',
    'interface',
    'const',
    '  X = «5»;',
    'implementation',
    'end.']), False, Title));
end;

initialization
  TDUnitX.RegisterTestFixture(TExtractTests);

end.
