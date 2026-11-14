unit Atlas.Common.Editing.Extract.Tests;

// Tests für Extrahieren (#50, Teil A): Methode extrahieren mit Parametern nach
// Datenfluss, Ablehnungen (Exit, Result, Teilauswahl, Break), Variable
// einführen (inline, var-Abschnitt, alle Vorkommen), Konstante extrahieren und
// Bedingung in Funktion auslagern (#980).
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
    /// <summary>Neue Namen mit den Präfixen der Namensregel (#1111): cNewConstant, mValue.</summary>
    [Test]
    procedure NewNamesWithPrefixes;
    [Test]
    procedure ExtractConditionAsMethod;
    [Test]
    procedure ExtractConditionAsRoutineWithConstant;
    [Test]
    procedure ExtractConditionRejectsWritesAndPartialSelection;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.Extract;

function Join(const ALines: array of string): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(ALines) do
  begin
    Result := Result + ALines[mIndex] + #10;
  end;
end;

function PositionOf(const AText: string; AIndex: Integer): TTextPosition;
var
  mIndex, mLine, mCharacter: Integer;
begin
  mLine := 0;
  mCharacter := 0;
  for mIndex := 1 to AIndex - 1 do
  begin
    if AText[mIndex] = #10 then
    begin
      Inc(mLine);
      mCharacter := 0;
    end
    else
    begin
      Inc(mCharacter);
    end;
  end;
  Result := TTextPosition.Create(mLine, mCharacter);
end;

/// <summary>Text ohne « und » und die Auswahl dazwischen; ein "|" steht für den Cursor.</summary>
function Unmark(const AMarked: string; out ARange: TTextRange): string;
var
  mStart, mFinish: Integer;
begin
  Result := AMarked;
  mStart := Pos('|', Result);
  if mStart > 0 then
  begin
    Result := StringReplace(Result, '|', '', []);
    ARange := TTextRange.Create(PositionOf(Result, mStart), PositionOf(Result, mStart));
    Exit;
  end;
  mStart := Pos('«', Result);
  Result := StringReplace(Result, '«', '', []);
  mFinish := Pos('»', Result);
  Result := StringReplace(Result, '»', '', []);
  ARange := TTextRange.Create(PositionOf(Result, mStart), PositionOf(Result, mFinish));
end;

type
  TRun = reference to function(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange;
    out AAction: TCodeAction): Boolean;

/// <summary>Ergebnis der Aktion auf AMarked; '-' ohne Angebot.</summary>
function Apply(const AMarked: string; const ARun: TRun; out ATitle: string): string;
var
  mText: string;
  mRange: TTextRange;
  mTree: TSyntaxTree;
  mAction: TCodeAction;
begin
  ATitle := '';
  mText := Unmark(AMarked, mRange);
  mTree := TPascalParser.Parse(mText);
  try
    if not ARun(mText, mTree, mRange, mAction) then
    begin
      Exit('-');
    end;
    ATitle := mAction.Title;
    Result := TChangeSignature.ApplyEdits(mText, mAction.Edits);
  finally
    mTree.Free;
  end;
end;

function Options(AInline: Boolean): TExtractOptions;
begin
  Result := TExtractOptions.Default;
  Result.InlineVar := AInline;
end;

function Method(const AMarked: string; out AReason: string): string;
var
  mTitle, mReason: string;
begin
  mReason := '';
  Result := Apply(AMarked,
    function(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange; out AAction: TCodeAction): Boolean
    begin
      Result := TExtractRefactoring.ExtractMethod(AText, ATree, ARange, Options(True), AAction, mReason);
    end, mTitle);
  AReason := mReason;
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

function Condition(const AMarked: string; out AReason: string): string;
var
  mTitle, mReason: string;
begin
  mReason := '';
  Result := Apply(AMarked,
    function(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange; out AAction: TCodeAction): Boolean
    begin
      Result := TExtractRefactoring.ExtractCondition(AText, ATree, ARange, Options(True), AAction, mReason);
    end, mTitle);
  AReason := mReason;
end;

procedure AssertParses(const AText: string);
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)), 'parst fehlerfrei');
  finally
    mTree.Free;
  end;
end;

{ TExtractTests }

procedure TExtractTests.ExtractMethodWithConstAndVarParameters;
var
  mReason, mResult_: string;
begin
  // Zusätzliche Abnahme: liest AValue, schreibt Total (danach gelesen) → const und var; Temp nur innen.
  mResult_ := Method(Join([
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
    'end.']), mReason);
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
    'end.']), mResult_, mReason);
  AssertParses(mResult_);
end;

procedure TExtractTests.ExtractRoutineWithOutParameter;
var
  mReason, mResult_: string;
begin
  // Unbedingt zuerst geschrieben und danach gelesen → out; ohne Klasse eine Routine davor.
  mResult_ := Method(Join([
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
    'end.']), mReason);
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
    'end.']), mResult_, mReason);
  AssertParses(mResult_);
end;

procedure TExtractTests.ExtractMethodRejectsExit;
var
  mReason: string;
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
    'end.']), mReason));
  Assert.AreEqual('Exit in der Auswahl', mReason);
  Assert.AreEqual('-', Method(Join([
    'program P;',
    'procedure Run(A: Integer);',
    'begin',
    '  «Exit(1);»',
    'end;',
    'begin',
    'end.']), mReason));
end;

procedure TExtractTests.ExtractMethodRejectsResultAndPartialSelection;
var
  mReason: string;
begin
  Assert.AreEqual('-', Method(Join([
    'program P;',
    'function Run(A: Integer): Integer;',
    'begin',
    '  «Result := A * 2;»',
    'end;',
    'begin',
    'end.']), mReason));
  Assert.AreEqual('Result in der Auswahl', mReason);
  // Nur ein Teil einer Anweisung.
  Assert.AreEqual('-', Method(Join([
    'program P;',
    'procedure Run(A: Integer);',
    'begin',
    '  A := «A * 2»;',
    'end;',
    'begin',
    'end.']), mReason));
  Assert.AreEqual('keine vollständigen Anweisungen', mReason);
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
    'end.']), mReason));
end;

procedure TExtractTests.ExtractMethodChecksBreak;
var
  mReason, mResult_: string;
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
    'end.']), mReason));
  Assert.AreEqual('Break springt aus der Auswahl', mReason);
  // Mit der ganzen Schleife ist Break innen; I wird nur innen gebraucht.
  mResult_ := Method(Join([
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
    'end.']), mReason);
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
    'end.']), mResult_, mReason);
end;

procedure TExtractTests.ExtractMethodInLoopUsesVar;
var
  mReason, mResult_: string;
begin
  // In einer Schleife: Sum wird vor der Auswahl in der Schleife gelesen, also „danach“; zuerst unbedingt
  // geschrieben → out statt lokaler Variable.
  mResult_ := Method(Join([
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
    'end.']), mReason);
  Assert.Contains(mResult_, 'procedure ExtractedMethod(const I: Integer; out Sum: Integer);', mReason);
  AssertParses(mResult_);
end;

procedure TExtractTests.ExtractMethodCopiesConstants;
var
  mReason, mResult_: string;
begin
  mResult_ := Method(Join([
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
    'end.']), mReason);
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
    'end.']), mResult_, mReason);
end;

procedure TExtractTests.IntroduceInlineVariable;
var
  mTitle: string;
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
    'end.']), True, False, mTitle));
  Assert.AreEqual('Variable einführen', mTitle);
end;

procedure TExtractTests.IntroduceVariableInVarSection;
var
  mTitle: string;
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
    'end.']), False, False, mTitle));
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
    'end.']), False, False, mTitle));
end;

procedure TExtractTests.IntroduceVariableForAllOccurrences;
var
  mTitle, mMarked: string;
begin
  mMarked := Join([
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
    'end.']), Variable(mMarked, True, True, mTitle));
  Assert.AreEqual('Variable einführen (alle 2 Vorkommen)', mTitle);
  // Ändert sich ein Name dazwischen, gibt es nur die einzelne Variante.
  Assert.AreEqual('-', Variable(StringReplace(mMarked, '  B := Liste', '  Liste := nil;'#10'  B := Liste', []),
    True, True, mTitle));
  // Nur ein Vorkommen: keine Variante für alle.
  Assert.AreEqual('-', Variable(StringReplace(mMarked, 'Liste.Count + 2', '2', []), True, True, mTitle));
end;

procedure TExtractTests.IntroduceVariableRejectsUnsafePlaces;
var
  mTitle: string;
begin
  // Ziel einer Zuweisung, Bedingung einer Schleife, Zweig ohne begin, kein ganzer Ausdruck.
  Assert.AreEqual('-', Variable(Join([
    'program P;',
    'procedure Run(var A: Integer);',
    'begin',
    '  «A» := 1;',
    'end;',
    'begin',
    'end.']), True, False, mTitle));
  Assert.AreEqual('-', Variable(Join([
    'program P;',
    'procedure Run(A: Integer);',
    'begin',
    '  while «A > 0» do',
    '    Dec(A);',
    'end;',
    'begin',
    'end.']), True, False, mTitle));
  Assert.AreEqual('-', Variable(Join([
    'program P;',
    'procedure Run(L: TList);',
    'begin',
    '  if L <> nil then',
    '    Writeln(«L.Count»);',
    'end;',
    'begin',
    'end.']), True, False, mTitle));
  Assert.AreEqual('-', Variable(Join([
    'program P;',
    'procedure Run(A, B: Integer);',
    'begin',
    '  Writeln(A «+ B»);',
    'end;',
    'begin',
    'end.']), True, False, mTitle));
end;

/// <summary>Konstante in der Routine oder in der Unit extrahieren.</summary>
procedure AssertConstantInRoutineOrUnit;
var
  mTitle, mMarked: string;
begin
  mMarked := Join([
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
    'end.']), Constant(mMarked, False, mTitle));
  Assert.AreEqual('Konstante extrahieren', mTitle);
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
    'end.']), Constant(mMarked, True, mTitle));
  Assert.AreEqual('Konstante in der Unit extrahieren', mTitle);
end;

/// <summary>Cursor im Literal genügt; ein vorhandener const-Abschnitt wird ergänzt.</summary>
procedure AssertConstantAtCursorJoinsSection;
var
  mTitle: string;
begin
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
    'end.']), False, mTitle));
end;

procedure TExtractTests.ExtractConstantInRoutineAndUnit;
begin
  AssertConstantInRoutineOrUnit;
  AssertConstantAtCursorJoinsSection;
end;

procedure TExtractTests.ExtractConstantRejectsNonLiterals;
var
  mTitle: string;
begin
  Assert.AreEqual('-', Constant(Join([
    'program P;',
    'procedure Run(A: Integer);',
    'begin',
    '  Writeln(«A»);',
    'end;',
    'begin',
    'end.']), False, mTitle));
  // Außerhalb einer Routine.
  Assert.AreEqual('-', Constant(Join([
    'unit U;',
    'interface',
    'const',
    '  X = «5»;',
    'implementation',
    'end.']), False, mTitle));
end;

procedure TExtractTests.ExtractConditionAsMethod;
var
  mReason, mResult_: string;
begin
  // Methode der Klasse: Deklaration im private-Abschnitt, gelesene Namen als const-Parameter, Felder bleiben.
  mResult_ := Condition(Join([
    'unit U;',
    'interface',
    'type',
    '  TKasse = class',
    '  private',
    '    FOffen: Boolean;',
    '  public',
    '    procedure Buche(Betrag: Currency);',
    '  end;',
    'implementation',
    'procedure TKasse.Buche(Betrag: Currency);',
    'var',
    '  Grenze: Currency;',
    'begin',
    '  Grenze := 100;',
    '  while «FOffen and (Betrag > 0) and (Betrag < Grenze)» do',
    '    Betrag := Betrag - 1;',
    'end;',
    'end.']), mReason);
  Assert.AreEqual(Join([
    'unit U;',
    'interface',
    'type',
    '  TKasse = class',
    '  private',
    '    FOffen: Boolean;',
    '    function ExtractedCondition(const Betrag: Currency; const Grenze: Currency): Boolean;',
    '  public',
    '    procedure Buche(Betrag: Currency);',
    '  end;',
    'implementation',
    'function TKasse.ExtractedCondition(const Betrag: Currency; const Grenze: Currency): Boolean;',
    'begin',
    '  Result := FOffen and (Betrag > 0) and (Betrag < Grenze);',
    'end;',
    '',
    'procedure TKasse.Buche(Betrag: Currency);',
    'var',
    '  Grenze: Currency;',
    'begin',
    '  Grenze := 100;',
    '  while ExtractedCondition(Betrag, Grenze) do',
    '    Betrag := Betrag - 1;',
    'end;',
    'end.']), mResult_, mReason);
  AssertParses(mResult_);
end;

procedure TExtractTests.ExtractConditionAsRoutineWithConstant;
var
  mReason, mResult_: string;
begin
  // Ohne Klasse eine Routine davor; lokale Konstanten werden mitkopiert, Klammern um die ganze Bedingung fallen.
  mResult_ := Condition(Join([
    'program P;',
    'procedure Run(A: Integer);',
    'const',
    '  Max = 10;',
    'begin',
    '  repeat',
    '    Inc(A);',
    '  until «(A > Max) or (A = 0)»;',
    'end;',
    'begin',
    'end.']), mReason);
  Assert.AreEqual(Join([
    'program P;',
    'function ExtractedCondition(const A: Integer): Boolean;',
    'const',
    '  Max = 10;',
    'begin',
    '  Result := (A > Max) or (A = 0);',
    'end;',
    '',
    'procedure Run(A: Integer);',
    'const',
    '  Max = 10;',
    'begin',
    '  repeat',
    '    Inc(A);',
    '  until ExtractedCondition(A);',
    'end;',
    'begin',
    'end.']), mResult_, mReason);
  AssertParses(mResult_);
  mResult_ := Condition(Join([
    'program P;',
    'procedure Run(A: Integer);',
    'begin',
    '  if «(A > 1)» then',
    '    Exit;',
    'end;',
    'begin',
    'end.']), mReason);
  Assert.Contains(mResult_, '  Result := A > 1;');
  Assert.Contains(mResult_, '  if ExtractedCondition(A) then');
end;

procedure TExtractTests.ExtractConditionRejectsWritesAndPartialSelection;
var
  mReason: string;
begin
  // Ein var-Argument ändert A: die Funktion bekäme es nur als const.
  Assert.AreEqual('-', Condition(Join([
    'program P;',
    'function Lies(var X: Integer): Boolean;',
    'begin',
    '  Result := True;',
    'end;',
    'procedure Run(A: Integer);',
    'begin',
    '  if «Lies(A) and (A > 0)» then',
    '    Exit;',
    'end;',
    'begin',
    'end.']), mReason));
  Assert.AreEqual('die Bedingung ändert A', mReason);
  // Nur ein Teil der Bedingung.
  Assert.AreEqual('-', Condition(Join([
    'program P;',
    'procedure Run(A, B: Integer);',
    'begin',
    '  if «(A > 0) and (B > 0)» or (A = B) then',
    '    Exit;',
    'end;',
    'begin',
    'end.']), mReason));
  Assert.AreEqual('keine ganze Bedingung', mReason);
  // Result ist in der neuen Funktion ein anderes.
  Assert.AreEqual('-', Condition(Join([
    'program P;',
    'function Run(A: Integer): Boolean;',
    'begin',
    '  Result := A > 0;',
    '  if «Result and (A < 9)» then',
    '    Exit;',
    'end;',
    'begin',
    'end.']), mReason));
  Assert.AreEqual('Result in der Bedingung', mReason);
end;


procedure TExtractTests.NewNamesWithPrefixes;
var
  mTitle, mChanged: string;
  mNames: TPascalNamePrefixes;
begin
  mNames := TPascalNamePrefixes.None;
  mNames.ConstantPrefix := 'c';
  mNames.LocalPrefix := 'm';
  mChanged := Apply(Join(['unit U;', 'interface', 'implementation', 'procedure Run;', 'begin', '  Sleep(«250»);',
    'end;', 'end.']),
    function(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange; out AAction: TCodeAction): Boolean
    var
      Extract: TExtractOptions;
    begin
      Extract := Options(True);
      Extract.Names := mNames;
      Result := TExtractRefactoring.ExtractConstant(AText, ATree, ARange, Extract, False, AAction);
    end, mTitle);
  Assert.IsTrue(Pos('  cNewConstant = 250;', mChanged) > 0, mChanged);
  Assert.IsTrue(Pos('Sleep(cNewConstant)', mChanged) > 0, mChanged);
  mChanged := Apply(Join(['unit U;', 'interface', 'implementation', 'procedure Run(X: Integer);', 'begin',
    '  Sleep(«X + 1»);', 'end;', 'end.']),
    function(const AText: string; ATree: TSyntaxTree; const ARange: TTextRange; out AAction: TCodeAction): Boolean
    var
      Extract: TExtractOptions;
    begin
      Extract := Options(True);
      Extract.Names := mNames;
      Result := TExtractRefactoring.IntroduceVariable(AText, ATree, ARange, Extract, False, AAction);
    end, mTitle);
  Assert.IsTrue(Pos('mValue', mChanged) > 0, mChanged);
end;

initialization
  TDUnitX.RegisterTestFixture(TExtractTests);

end.
