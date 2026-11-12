unit Atlas.Common.Editing.Extract.Duplicates.Tests;

// Tests für „Methode extrahieren“ mit gleichen Stellen (#2054, Atlas.Common.Editing.Extract.Duplicates): Fund in
// anderen Methoden trotz Kommentaren, Leerraum und Groß-/Kleinschreibung; Ausschluss bei anderer Bedeutung eines
// Namens, anderem Datenfluss, anderer Klasse und Überlappung; Stellen in derselben Routine samt Entfernen der
// lokalen Variablen; abgewählte Stellen; Schalter in den Optionen.
// Die Auswahl steht in den Texten zwischen « und ».

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TExtractDuplicatesTests = class
  public
    [Test]
    procedure ReplacesEqualPlacesInOtherMethods;
    [Test]
    procedure IgnoresCommentsSpacesAndCase;
    [Test]
    procedure SkipsLocalThatHidesField;
    [Test]
    procedure SkipsDifferentDataFlow;
    [Test]
    procedure SkipsOtherClassAndWithBody;
    [Test]
    procedure SkipsOverlappingPlaces;
    [Test]
    procedure ReplacesPlacesInSameRoutine;
    [Test]
    procedure SkipsDependentPlacesInSameRoutine;
    [Test]
    procedure DeselectedPlacesStayUnchanged;
    [Test]
    procedure ReportsMissingDuplicates;
    [Test]
    procedure ActionsFollowTheOption;
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

/// <summary>Text ohne « und » und die Auswahl dazwischen.</summary>
function Unmark(const AMarked: string; out ARange: TTextRange): string;
var
  mStart, mFinish: Integer;
begin
  Result := AMarked;
  mStart := Pos('«', Result);
  Result := StringReplace(Result, '«', '', []);
  mFinish := Pos('»', Result);
  Result := StringReplace(Result, '»', '', []);
  ARange := TTextRange.Create(PositionOf(Result, mStart), PositionOf(Result, mFinish));
end;

function Options: TExtractOptions;
begin
  Result := TExtractOptions.Default;
  Result.Duplicates := True;
end;

/// <summary>Gilt Edit AIndex, wenn nur die Stellen in AChosen gewählt sind?</summary>
function Applies(const AAction: TCodeAction; AIndex: Integer; const AChosen: TArray<Integer>): Boolean;
var
  mChoice, mChosen: Integer;
  mFound: Boolean;
begin
  Result := True;
  if AIndex > High(AAction.EditChoices) then
  begin
    Exit;
  end;
  for mChoice in AAction.EditChoices[AIndex] do
  begin
    mFound := False;
    for mChosen in AChosen do
    begin
      mFound := mFound or (mChosen = mChoice);
    end;
    Result := Result and mFound;
  end;
end;

/// <summary>Alle Stellen gewählt.</summary>
function AllChoices(const AAction: TCodeAction): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(AAction.Choices) do
  begin
    Result := Result + [mIndex];
  end;
end;

type
  /// <summary>Ergebnis eines Laufs: Text nach den gewählten Edits, Titel, Stellen und Grund.</summary>
  TOutcome = record
    Text: string;
    Title: string;
    Places: TArray<string>;
    Reason: string;
    Preview: string;
  end;

/// <summary>Aktion mit gleichen Stellen auf AMarked; mit AAll alle Stellen, sonst nur AChosen. Text '-' ohne
/// Angebot.</summary>
function RunWith(const AMarked: string; AAll: Boolean; const AChosen: TArray<Integer>): TOutcome;
var
  mText: string;
  mRange: TTextRange;
  mTree: TSyntaxTree;
  mAction: TCodeAction;
  mChosen: TArray<Integer>;
  mEdits: TArray<TTextEdit>;
  mIndex: Integer;
  mChoice: TCodeActionChoice;
begin
  Result := Default(TOutcome);
  mText := Unmark(AMarked, mRange);
  mTree := TPascalParser.Parse(mText);
  try
    if not TExtractRefactoring.ExtractMethodWithDuplicates(mText, mTree, mRange, Options, mAction, Result.Reason) then
    begin
      Result.Text := '-';
      Exit;
    end;
    mChosen := AChosen;
    if AAll then
    begin
      mChosen := AllChoices(mAction);
    end;
    mEdits := nil;
    for mIndex := 0 to High(mAction.Edits) do
    begin
      if Applies(mAction, mIndex, mChosen) then
      begin
        mEdits := mEdits + [mAction.Edits[mIndex]];
      end;
    end;
    for mChoice in mAction.Choices do
    begin
      Result.Places := Result.Places + [mChoice.Title];
    end;
    Result.Title := mAction.Title;
    Result.Preview := mAction.Preview;
    Result.Text := TChangeSignature.ApplyEdits(mText, mEdits);
  finally
    mTree.Free;
  end;
end;

function RunAll(const AMarked: string): TOutcome;
begin
  Result := RunWith(AMarked, True, nil);
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

/// <summary>Klasse TParser mit Feld FCount und drei Methoden; ABodies sind die Rümpfe von A, B und C.</summary>
function ParserUnit(const ABodyA, ABodyB, ABodyC: array of string): string;
begin
  Result := Join([
    'unit U;',
    'interface',
    'type',
    '  TParser = class',
    '  private',
    '    FCount: Integer;',
    '  public',
    '    procedure A(AValue: Integer);',
    '    procedure B(AValue: Integer);',
    '    procedure C(AValue: Integer);',
    '  end;',
    'implementation',
    'procedure TParser.A(AValue: Integer);']) + Join(ABodyA) + Join([
    'procedure TParser.B(AValue: Integer);']) + Join(ABodyB) + Join([
    'procedure TParser.C(AValue: Integer);']) + Join(ABodyC) + Join(['end.']);
end;

{ TExtractDuplicatesTests }

procedure TExtractDuplicatesTests.ReplacesEqualPlacesInOtherMethods;
var
  mOutcome: TOutcome;
begin
  mOutcome := RunAll(ParserUnit([
    'begin',
    '  «FCount := FCount + AValue;',
    '  Writeln(FCount);»',
    'end;'], [
    'begin',
    '  AValue := AValue * 2;',
    '  FCount := FCount + AValue;',
    '  Writeln(FCount);',
    'end;'], [
    'begin',
    '  FCount := FCount + AValue;',
    '  Writeln(FCount);',
    'end;']));
  Assert.AreEqual('Methode extrahieren und 2 gleiche Stellen ersetzen', mOutcome.Title);
  Assert.AreEqual(2, Integer(Length(mOutcome.Places)));
  Assert.AreEqual('Zeile 21 in TParser.B', mOutcome.Places[0]);
  Assert.AreEqual('Zeile 26 in TParser.C', mOutcome.Places[1]);
  Assert.Contains(mOutcome.Preview, 'Neue Methode: procedure TParser.ExtractedMethod(const AValue: Integer);');
  Assert.AreEqual(Join([
    'unit U;',
    'interface',
    'type',
    '  TParser = class',
    '  private',
    '    FCount: Integer;',
    '    procedure ExtractedMethod(const AValue: Integer);',
    '  public',
    '    procedure A(AValue: Integer);',
    '    procedure B(AValue: Integer);',
    '    procedure C(AValue: Integer);',
    '  end;',
    'implementation',
    'procedure TParser.ExtractedMethod(const AValue: Integer);',
    'begin',
    '  FCount := FCount + AValue;',
    '  Writeln(FCount);',
    'end;',
    '',
    'procedure TParser.A(AValue: Integer);',
    'begin',
    '  ExtractedMethod(AValue);',
    'end;',
    'procedure TParser.B(AValue: Integer);',
    'begin',
    '  AValue := AValue * 2;',
    '  ExtractedMethod(AValue);',
    'end;',
    'procedure TParser.C(AValue: Integer);',
    'begin',
    '  ExtractedMethod(AValue);',
    'end;',
    'end.']), mOutcome.Text);
  AssertParses(mOutcome.Text);
end;

procedure TExtractDuplicatesTests.IgnoresCommentsSpacesAndCase;
var
  mOutcome: TOutcome;
begin
  mOutcome := RunAll(ParserUnit([
    'begin',
    '  «FCount := FCount + AValue;',
    '  Writeln(FCount);»',
    'end;'], [
    'begin',
    '  fcount:=FCOUNT+avalue; // zählen',
    '  { ausgeben }',
    '  WriteLn( fCount );',
    'end;'], [
    'begin',
    '  Writeln(''FCount'');',
    'end;']));
  Assert.AreEqual(1, Integer(Length(mOutcome.Places)), mOutcome.Reason);
  Assert.Contains(mOutcome.Text, Join([
    'procedure TParser.B(AValue: Integer);',
    'begin',
    '  ExtractedMethod(AValue);',
    'end;']));
  // Ein String-Literal ist kein Bezeichner: andere Schreibweise, andere Stelle.
  Assert.Contains(mOutcome.Text, '  Writeln(''FCount'');');
end;

procedure TExtractDuplicatesTests.SkipsLocalThatHidesField;
var
  mOutcome: TOutcome;
begin
  // In B verdeckt eine lokale Variable das Feld: gleicher Text, andere Bedeutung.
  mOutcome := RunAll(ParserUnit([
    'begin',
    '  «FCount := FCount + AValue;',
    '  Writeln(FCount);»',
    'end;'], [
    'var',
    '  FCount: Integer;',
    'begin',
    '  FCount := 0;',
    '  FCount := FCount + AValue;',
    '  Writeln(FCount);',
    'end;'], [
    'begin',
    '  FCount := FCount + AValue;',
    '  Writeln(FCount);',
    'end;']));
  Assert.AreEqual(1, Integer(Length(mOutcome.Places)), mOutcome.Reason);
  Assert.AreEqual('Zeile 28 in TParser.C', mOutcome.Places[0]);
  Assert.Contains(mOutcome.Text, Join([
    '  FCount := 0;',
    '  FCount := FCount + AValue;',
    '  Writeln(FCount);']));
end;

procedure TExtractDuplicatesTests.SkipsDifferentDataFlow;
var
  mOutcome: TOutcome;
begin
  // In A wird Total danach nicht mehr gebraucht (lokal), in B schon (out): andere Parameterliste.
  mOutcome := RunAll(ParserUnit([
    'var',
    '  Total: Integer;',
    'begin',
    '  «Total := AValue * 2;',
    '  Writeln(Total);»',
    'end;'], [
    'var',
    '  Total: Integer;',
    'begin',
    '  Total := AValue * 2;',
    '  Writeln(Total);',
    '  FCount := Total;',
    'end;'], [
    'var',
    '  Total: Integer;',
    'begin',
    '  Total := AValue * 2;',
    '  Writeln(Total);',
    'end;']));
  Assert.AreEqual(1, Integer(Length(mOutcome.Places)), mOutcome.Reason);
  Assert.AreEqual('Zeile 32 in TParser.C', mOutcome.Places[0]);
  Assert.Contains(mOutcome.Text, Join([
    '  Total := AValue * 2;',
    '  Writeln(Total);',
    '  FCount := Total;']));
  // Total wandert in A und C in die neue Methode; der var-Abschnitt beider Routinen wird leer.
  Assert.Contains(mOutcome.Text, Join([
    'procedure TParser.C(AValue: Integer);',
    'begin',
    '  ExtractedMethod(AValue);',
    'end;']));
  AssertParses(mOutcome.Text);
end;

procedure TExtractDuplicatesTests.SkipsOtherClassAndWithBody;
var
  mOutcome: TOutcome;
begin
  mOutcome := RunAll(Join([
    'unit U;',
    'interface',
    'type',
    '  TFirst = class',
    '    FCount: Integer;',
    '    procedure A;',
    '    procedure B;',
    '  end;',
    '  TSecond = class',
    '    FCount: Integer;',
    '    procedure A;',
    '  end;',
    'implementation',
    'procedure TFirst.A;',
    'begin',
    '  «Inc(FCount);',
    '  Writeln(FCount);»',
    'end;',
    'procedure TFirst.B;',
    'begin',
    '  with Self do',
    '  begin',
    '    Inc(FCount);',
    '    Writeln(FCount);',
    '  end;',
    'end;',
    'procedure TSecond.A;',
    'begin',
    '  Inc(FCount);',
    '  Writeln(FCount);',
    'end;',
    'end.']));
  Assert.AreEqual('-', mOutcome.Text);
  Assert.AreEqual('keine gleichen Stellen in der Unit', mOutcome.Reason);
end;

procedure TExtractDuplicatesTests.SkipsOverlappingPlaces;
var
  mOutcome: TOutcome;
begin
  // Vier gleiche Anweisungen, zwei markiert: Nur die beiden letzten ergeben eine weitere Stelle.
  mOutcome := RunAll(ParserUnit([
    'begin',
    '  «Inc(FCount);',
    '  Inc(FCount);»',
    '  Inc(FCount);',
    '  Inc(FCount);',
    'end;'], [
    'begin',
    'end;'], [
    'begin',
    'end;']));
  Assert.AreEqual(1, Integer(Length(mOutcome.Places)), mOutcome.Reason);
  Assert.Contains(mOutcome.Text, Join([
    'procedure TParser.A(AValue: Integer);',
    'begin',
    '  ExtractedMethod;',
    '  ExtractedMethod;',
    'end;']));
end;

/// <summary>Zwei gleiche Stellen in A mit der Hilfsvariablen Temp, dazwischen eine andere Anweisung.</summary>
function SameRoutineUnit: string;
begin
  Result := ParserUnit([
    'var',
    '  Temp: Integer;',
    'begin',
    '  «Temp := AValue * 2;',
    '  Writeln(Temp);»',
    '  Inc(FCount);',
    '  Temp := AValue * 2;',
    '  Writeln(Temp);',
    'end;'], [
    'begin',
    'end;'], [
    'begin',
    'end;']);
end;

procedure TExtractDuplicatesTests.ReplacesPlacesInSameRoutine;
var
  mOutcome: TOutcome;
begin
  // Für sich allein wäre Temp an der ersten Stelle ein out-Parameter (die zweite liest es), an der zweiten lokal;
  // ersetzt man beide, braucht keine Stelle Temp von außen.
  mOutcome := RunAll(SameRoutineUnit);
  Assert.AreEqual(1, Integer(Length(mOutcome.Places)), mOutcome.Reason);
  Assert.Contains(mOutcome.Text, Join([
    'procedure TParser.ExtractedMethod(const AValue: Integer);',
    'var',
    '  Temp: Integer;',
    'begin']));
  Assert.Contains(mOutcome.Text, Join([
    'procedure TParser.A(AValue: Integer);',
    'begin',
    '  ExtractedMethod(AValue);',
    '  Inc(FCount);',
    '  ExtractedMethod(AValue);',
    'end;']));
  AssertParses(mOutcome.Text);
end;

procedure TExtractDuplicatesTests.SkipsDependentPlacesInSameRoutine;
var
  mOutcome: TOutcome;
begin
  // Die zweite Stelle liest, was die erste schreibt: an der ersten var, an der zweiten Wertparameter. Keine
  // gemeinsame Parameterliste, also keine weitere Stelle.
  mOutcome := RunAll(ParserUnit([
    'var',
    '  Total: Integer;',
    'begin',
    '  Total := AValue;',
    '  «Total := Total + 1;',
    '  Writeln(Total);»',
    '  Total := Total + 1;',
    '  Writeln(Total);',
    'end;'], [
    'begin',
    'end;'], [
    'begin',
    'end;']));
  Assert.AreEqual('-', mOutcome.Text);
  Assert.AreEqual('keine gleichen Stellen in der Unit', mOutcome.Reason);
end;

procedure TExtractDuplicatesTests.DeselectedPlacesStayUnchanged;
var
  mOutcome: TOutcome;
begin
  // Abgewählt: Die zweite Stelle bleibt, und Temp bleibt im var-Abschnitt, weil sie es noch braucht.
  mOutcome := RunWith(SameRoutineUnit, False, nil);
  Assert.Contains(mOutcome.Text, Join([
    'procedure TParser.A(AValue: Integer);',
    'var',
    '  Temp: Integer;',
    'begin',
    '  ExtractedMethod(AValue);',
    '  Inc(FCount);',
    '  Temp := AValue * 2;',
    '  Writeln(Temp);',
    'end;']));
  AssertParses(mOutcome.Text);
end;

procedure TExtractDuplicatesTests.ReportsMissingDuplicates;
var
  mOutcome: TOutcome;
begin
  mOutcome := RunAll(ParserUnit([
    'begin',
    '  «Inc(FCount);»',
    'end;'], [
    'begin',
    '  Dec(FCount);',
    'end;'], [
    'begin',
    'end;']));
  Assert.AreEqual('-', mOutcome.Text);
  Assert.AreEqual('keine gleichen Stellen in der Unit', mOutcome.Reason);
  // Geht schon die Auswahl nicht, nennt der Grund das.
  mOutcome := RunAll(ParserUnit([
    'begin',
    '  «Exit;»',
    'end;'], [
    'begin',
    '  Exit;',
    'end;'], [
    'begin',
    'end;']));
  Assert.AreEqual('Exit in der Auswahl', mOutcome.Reason);
end;

function TitleIndex(const AActions: TArray<TCodeAction>; const ATitle: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := High(AActions) downto 0 do
  begin
    if AActions[mIndex].Title = ATitle then
    begin
      Result := mIndex;
    end;
  end;
end;

procedure TExtractDuplicatesTests.ActionsFollowTheOption;
const
  cWithDuplicates = 'Methode extrahieren und gleiche Stelle ersetzen';
var
  mText: string;
  mRange: TTextRange;
  mTree: TSyntaxTree;
  mOptions: TExtractOptions;
  mActions: TArray<TCodeAction>;
begin
  mText := Unmark(ParserUnit([
    'begin',
    '  «Inc(FCount);»',
    'end;'], [
    'begin',
    '  Inc(FCount);',
    'end;'], [
    'begin',
    'end;']), mRange);
  mTree := TPascalParser.Parse(mText);
  try
    mOptions := TExtractOptions.Default;
    mActions := TExtractRefactoring.Actions(mText, mTree, mRange, mOptions);
    Assert.AreEqual('Methode extrahieren', mActions[0].Title);
    Assert.AreEqual(-1, TitleIndex(mActions, cWithDuplicates), 'abgeschaltet');
    mOptions.Duplicates := True;
    mActions := TExtractRefactoring.Actions(mText, mTree, mRange, mOptions);
    Assert.AreEqual('Methode extrahieren', mActions[0].Title);
    Assert.AreEqual(1, TitleIndex(mActions, cWithDuplicates), 'gleich hinter Methode extrahieren');
    Assert.AreEqual(1, Integer(Length(mActions[1].Choices)));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TExtractDuplicatesTests);

end.
