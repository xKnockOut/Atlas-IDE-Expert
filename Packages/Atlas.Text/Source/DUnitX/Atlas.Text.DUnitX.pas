unit Atlas.Text.DUnitX;

// DUnitX-Tests im Quelltext erkennen, gemeinsam für Server und Plugin
// (#69, #154, #585): Attribute nach dem Namen ([TestFixture],
// [DUnitX.Attributes.TestFixture], [TestFixtureAttribute], [Test],
// [TestCase('Name', '1,2')], [Ignore('Grund')], [Category('Langsam')],
// [Setup] …), Fixtures und Testmethoden einer Unit mit ihren Zeilen und die
// Befehlszeile eines DUnitX-Testprogramms.
//
// Die Erkennung braucht keine Namensauflösung: Sie liest die Tokens der Unit
// (Kommentare, Direktiven und Zeichenketten überspringt sie) und erkennt
// - Fixtures: Klassen mit [TestFixture] oder einem Aufruf
//   RegisterTestFixture(TKlasse) in der Unit,
// - Tests: Methoden einer Fixture mit [Test] oder [TestCase] sowie
//   published-Methoden ohne Attribut (DUnitX behandelt sie wie DUnit als Test);
//   [Test(False)] und die Methoden mit [Setup], [TearDown], [SetupFixture]
//   oder [TearDownFixture] sind keine Tests,
// - die Zeile des Methodenkopfs im implementation-Teil, die der ersten
//   Anweisung (Haltepunkt beim Test-Debuggen, #585) und die des
//   abschließenden end (lokale Routinen, Typen mit end und asm-Blöcke
//   werden übersprungen),
// - die Zeile jedes [TestCase] (einzelne Fälle ausführen, #585).
// Zeilen sind 0-basiert. Der volle Name eines Tests in DUnitX ist
// Unit.Fixture.Methode, bei [TestCase] Unit.Fixture.Methode.Fall (beginnt der
// Fall mit „(“, ohne Punkt). --run (TNameFilter von DUnitX) trifft einen Test,
// wenn ein Name ein Anfang des vollen Namens seiner Fixture oder genau sein
// voller Name ist; Unit.Fixture.Methode trifft die Fälle eines [TestCase]
// darum nicht. TDUnitXCommandLine.RunNames bildet die passenden Namen.

interface

{$SCOPEDENUMS ON}

type
  TDUnitXAttribute = (None, TestFixture, Test, TestCase, Ignore, Category, Setup, TearDown, SetupFixture,
    TearDownFixture);

  TDUnitXTest = record
    /// <summary>Name der Methode wie deklariert.</summary>
    Method: string;
    /// <summary>Zeile der Methode in der Klassendeklaration.</summary>
    Line: Integer;
    /// <summary>Zeile des ersten Attributs davor ([Test]); ohne Attribut = Line.</summary>
    AttributeLine: Integer;
    /// <summary>Zeile des Methodenkopfs im implementation-Teil; -1 unbekannt.</summary>
    BodyLine: Integer;
    /// <summary>Zeile der ersten Anweisung im Rumpf (ohne Anweisung die von begin); -1 unbekannt.</summary>
    BeginLine: Integer;
    /// <summary>Zeile des end, das den Rumpf abschließt; -1 unbekannt.</summary>
    EndLine: Integer;
    /// <summary>Namen der Testfälle aus [TestCase('Name', …)], in Reihenfolge.</summary>
    Cases: TArray<string>;
    /// <summary>Zeile je Testfall (gleiche Reihenfolge wie Cases).</summary>
    CaseLines: TArray<Integer>;
    /// <summary>[Ignore] steht am Test.</summary>
    Ignored: Boolean;
  end;

  TDUnitXFixture = record
    /// <summary>Klassenname, z. B. TRechnerTests.</summary>
    Name: string;
    /// <summary>Zeile von „TRechnerTests = class“.</summary>
    Line: Integer;
    /// <summary>Zeile des ersten Attributs davor ([TestFixture]); ohne Attribut = Line.</summary>
    AttributeLine: Integer;
    Tests: TArray<TDUnitXTest>;
  end;

  TDUnitXUnit = record
    /// <summary>Name aus „unit …;“ (auch mit Punkten); '' ohne.</summary>
    UnitName: string;
    Fixtures: TArray<TDUnitXFixture>;
    /// <summary>Tests aller Fixtures.</summary>
    function TestCount: Integer;
    /// <summary>Fixture und Test zum Namen (ohne Rücksicht auf Groß-/Kleinschreibung); ATest = -1, wenn nur die
    /// Fixture passt oder AMethod leer ist. False, wenn es die Fixture nicht gibt.</summary>
    function Find(const AFixture, AMethod: string; out AFixtureIndex, ATestIndex: Integer): Boolean;
    /// <summary>Fixture bzw. Test, dessen Attribut- oder Deklarationszeile ALine ist. False ohne.</summary>
    function AtLine(ALine: Integer; out AFixtureIndex, ATestIndex: Integer): Boolean;
    /// <summary>Zeile, an der ein Ergebnis des Tests steht (Diagnostic, Datei:Zeile): Methodenkopf im
    /// implementation-Teil, sonst die Deklaration, sonst (unbekannte Methode oder AMethod leer) die Fixture.
    /// -1, wenn es die Fixture nicht gibt.</summary>
    function LineOf(const AFixture, AMethod: string): Integer;
    /// <summary>Test an ALine für „Test ausführen/debuggen“ am Cursor (#585): Zeile eines [TestCase] (ACaseIndex
    /// dieser Fall; stehen mehrere Fälle in der Zeile, -1 = alle), Attribut- oder Deklarationszeile von Fixture
    /// bzw. Test, Zeilen dazwischen oder der Rumpf der Testmethode bis zu ihrem end. ATestIndex = -1: die
    /// Fixture. False ohne Test an der Zeile.</summary>
    function TestAt(ALine: Integer; out AFixtureIndex, ATestIndex, ACaseIndex: Integer): Boolean;
    /// <summary>Zeile der Marke eines Tests (Code Lens): sein erstes Attribut; ist das ein [TestCase] mit eigener
    /// Marke, die Deklaration.</summary>
    function MarkLine(AFixtureIndex, ATestIndex: Integer): Integer;
    /// <summary>Hat der Fall ACaseIndex eine Zeile für sich (kein weiterer [TestCase] und nicht die Deklaration der
    /// Methode in derselben Zeile)?</summary>
    function CaseHasOwnLine(AFixtureIndex, ATestIndex, ACaseIndex: Integer): Boolean;
  end;

  TDUnitXSource = class
  public
    /// <summary>Attribut zum geschriebenen Namen: mit oder ohne Endung „Attribute“, qualifiziert oder nicht,
    /// ohne Rücksicht auf Groß-/Kleinschreibung. None für alles andere.</summary>
    class function AttributeOf(const AName: string): TDUnitXAttribute; static;
    /// <summary>Fixtures und Tests einer Unit (Zeilen ohne Zeilenende).</summary>
    class function Scan(const ALines: TArray<string>): TDUnitXUnit; static;
    /// <summary>Verwendet der Quelltext (Programm oder Unit) DUnitX.TestFramework? Kennzeichen eines
    /// DUnitX-Testprogramms (.dpr).</summary>
    class function UsesDUnitX(const ALines: TArray<string>): Boolean; static;
  end;

  TDUnitXCommandLine = class
  public const
    /// <summary>Höchstlänge der Namen in einem --run-Argument; darüber alle Tests (Windows erlaubt 32767 Zeichen
    /// je Befehlszeile).</summary>
    cMaxRunLength = 24000;
  public
    /// <summary>Voller Name für --run: Unit.Fixture bzw. Unit.Fixture.Methode (AMethod = '').</summary>
    class function TestName(const AUnitName, AFixture, AMethod: string): string; static;
    /// <summary>Voller Name eines Testfalls wie in DUnitX: Unit.Fixture.Methode.Fall; ein Fall in Klammern
    /// ohne Punkt davor, ein leerer Fall ergibt Unit.Fixture.Methode.</summary>
    class function CaseName(const AUnitName, AFixture, AMethod, ACase: string): string; static;
    /// <summary>Namen für --run, die genau die Fixture AFixtureIndex (ATestIndex = -1), den Test ATestIndex mit
    /// allen Fällen (ACaseIndex = -1) bzw. nur den Fall ACaseIndex treffen (#585). [TestCase]-Methoden: je Fall
    /// ein Name (Unit.Fixture.Methode allein trifft sie nicht); mit [Ignore] führt DUnitX sie als einen Test
    /// ohne Fall. Eine Fixture, deren Name der Anfang einer anderen Fixture der Unit ist, wird über ihre Tests
    /// genannt, sonst liefe die andere mit (DUnitX vergleicht den Anfang). Leer bei ungültigem Index.</summary>
    class function RunNames(const AUnit: TDUnitXUnit; AFixtureIndex, ATestIndex,
      ACaseIndex: Integer): TArray<string>; static;
    /// <summary>Argumente eines Laufs: XML-Bericht nach AResultFile, ohne Warten am Ende, mit --run, wenn ATests
    /// Namen enthält (sonst alle Tests).</summary>
    class function Arguments(const AResultFile: string; const ATests: TArray<string>): TArray<string>; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Chars;

type
  TTokenKind = (Ident, Str, Sym, Num);

  TToken = record
    Kind: TTokenKind;
    Text: string;
    Line: Integer;
  end;

  /// <summary>Attribut vor einer Deklaration.</summary>
  TPendingAttribute = record
    Kind: TDUnitXAttribute;
    Line: Integer;
    /// <summary>Erstes Argument als Text (Zeichenkette ohne Anführungszeichen, sonst das Token).</summary>
    FirstArgument: string;
  end;

type
  /// <summary>Zerlegt Zeilen in Tokens; Kommentare über Zeilen hinweg merkt es in InBrace und InParen.</summary>
  TTokenizer = record
    Tokens: TArray<TToken>;
    Count: Integer;
    Line: string;
    LineIndex: Integer;
    Index: Integer;
    InBrace: Boolean;
    InParen: Boolean;
    procedure Add(AKind: TTokenKind; const AText: string);
    /// <summary>Folgt auf das Zeichen an Index das Zeichen AChar?</summary>
    function NextIs(AChar: Char): Boolean;
    procedure SkipIdentChars;
    /// <summary>Innerhalb eines Kommentars: ein Zeichen weiter und True; sonst False.</summary>
    function SkipComment: Boolean;
    procedure AddSymbol;
    procedure SkipCharCode;
    procedure ReadQuoted(var AValue: string);
    procedure ReadString;
    procedure ReadNumber;
    procedure ReadWordOrSymbol;
    procedure ReadToken;
    procedure ScanLine(ALineIndex: Integer; const ALine: string);
  end;

procedure TTokenizer.Add(AKind: TTokenKind; const AText: string);
begin
  if Count = Length(Tokens) then
  begin
    SetLength(Tokens, Count * 2 + 64);
  end;
  Tokens[Count].Kind := AKind;
  Tokens[Count].Text := AText;
  Tokens[Count].Line := LineIndex;
  Inc(Count);
end;

function TTokenizer.NextIs(AChar: Char): Boolean;
begin
  Result := (Index < Length(Line)) and (Line[Index + 1] = AChar);
end;

procedure TTokenizer.SkipIdentChars;
begin
  while (Index <= Length(Line)) and TTextChars.IsIdentChar(Line[Index]) do
  begin
    Inc(Index);
  end;
end;

function TTokenizer.SkipComment: Boolean;
begin
  Result := InBrace or InParen;
  if InBrace then
  begin
    InBrace := Line[Index] <> '}';
  end
  else if InParen and (Line[Index] = '*') and NextIs(')') then
  begin
    InParen := False;
    Inc(Index);
  end;
  if Result then
  begin
    Inc(Index);
  end;
end;

procedure TTokenizer.AddSymbol;
begin
  Add(TTokenKind.Sym, Line[Index]);
  Inc(Index);
end;

procedure TTokenizer.SkipCharCode;
begin
  Inc(Index);
  while (Index <= Length(Line)) and CharInSet(Line[Index], ['0'..'9', '$', 'A'..'F', 'a'..'f']) do
  begin
    Inc(Index);
  end;
end;

procedure TTokenizer.ReadQuoted(var AValue: string);
begin
  Inc(Index);
  while Index <= Length(Line) do
  begin
    if Line[Index] <> '''' then
    begin
      AValue := AValue + Line[Index];
      Inc(Index);
    end
    else if NextIs('''') then
    begin
      AValue := AValue + '''';
      Inc(Index, 2);
    end
    else
    begin
      Inc(Index);
      Exit;
    end;
  end;
end;

procedure TTokenizer.ReadString;
var
  mValue: string;
begin
  // Zeichenkette samt #13-Teilen als ein Token; nur der Text in Anführungszeichen zählt.
  mValue := '';
  while (Index <= Length(Line)) and CharInSet(Line[Index], ['''', '#']) do
  begin
    if Line[Index] = '#' then
    begin
      SkipCharCode;
    end
    else
    begin
      ReadQuoted(mValue);
    end;
  end;
  Add(TTokenKind.Str, mValue);
end;

procedure TTokenizer.ReadNumber;
var
  mStart: Integer;
begin
  mStart := Index;
  Inc(Index);
  SkipIdentChars;
  Add(TTokenKind.Num, Copy(Line, mStart, Index - mStart));
end;

procedure TTokenizer.ReadWordOrSymbol;
var
  mStart: Integer;
begin
  if (Line[Index] = '&') and (Index < Length(Line)) and TTextChars.IsIdentStart(Line[Index + 1]) then
  begin
    Inc(Index);
  end;
  if not TTextChars.IsIdentStart(Line[Index]) then
  begin
    AddSymbol;
    Exit;
  end;
  mStart := Index;
  Inc(Index);
  SkipIdentChars;
  Add(TTokenKind.Ident, Copy(Line, mStart, Index - mStart));
end;

procedure TTokenizer.ReadToken;
begin
  case Line[Index] of
    ' ', #9, #13, #10:
      Inc(Index);
    '{':
      begin
        InBrace := True;
        Inc(Index);
      end;
    '/':
      if NextIs('/') then
      begin
        Index := Length(Line) + 1;
      end
      else
      begin
        AddSymbol;
      end;
    '(':
      if NextIs('*') then
      begin
        InParen := True;
        Inc(Index, 2);
      end
      else
      begin
        AddSymbol;
      end;
    '''', '#':
      ReadString;
    '0'..'9', '$':
      ReadNumber;
  else
    ReadWordOrSymbol;
  end;
end;

procedure TTokenizer.ScanLine(ALineIndex: Integer; const ALine: string);
begin
  Line := ALine;
  LineIndex := ALineIndex;
  Index := 1;
  while Index <= Length(Line) do
  begin
    if not SkipComment then
    begin
      ReadToken;
    end;
  end;
end;

function Tokenize(const ALines: TArray<string>): TArray<TToken>;
var
  mTokenizer: TTokenizer;
  mLineIndex: Integer;
begin
  mTokenizer := Default(TTokenizer);
  for mLineIndex := 0 to High(ALines) do
  begin
    mTokenizer.ScanLine(mLineIndex, ALines[mLineIndex]);
  end;
  Result := Copy(mTokenizer.Tokens, 0, mTokenizer.Count);
end;

function IsWord(const AToken: TToken; const AWord: string): Boolean;
begin
  Result := (AToken.Kind = TTokenKind.Ident) and SameText(AToken.Text, AWord);
end;

function IsSym(const AToken: TToken; const ASymbol: string): Boolean;
begin
  Result := (AToken.Kind = TTokenKind.Sym) and (AToken.Text = ASymbol);
end;

function IsVisibility(const AToken: TToken): Boolean;
begin
  Result := IsWord(AToken, 'private') or IsWord(AToken, 'protected') or IsWord(AToken, 'public') or
    IsWord(AToken, 'published') or IsWord(AToken, 'strict');
end;

{ TDUnitXUnit }

function TDUnitXUnit.TestCount: Integer;
var
  mFixture: TDUnitXFixture;
begin
  Result := 0;
  for mFixture in Fixtures do
  begin
    Inc(Result, Length(mFixture.Tests));
  end;
end;

function TDUnitXUnit.Find(const AFixture, AMethod: string; out AFixtureIndex, ATestIndex: Integer): Boolean;
var
  mIndex: Integer;
begin
  AFixtureIndex := -1;
  ATestIndex := -1;
  for mIndex := 0 to High(Fixtures) do
  begin
    if SameText(Fixtures[mIndex].Name, AFixture) then
    begin
      AFixtureIndex := mIndex;
      Break;
    end;
  end;
  Result := AFixtureIndex >= 0;
  if not Result or (AMethod = '') then
  begin
    Exit;
  end;
  for mIndex := 0 to High(Fixtures[AFixtureIndex].Tests) do
  begin
    if SameText(Fixtures[AFixtureIndex].Tests[mIndex].Method, AMethod) then
    begin
      ATestIndex := mIndex;
      Exit;
    end;
  end;
end;

function TDUnitXUnit.AtLine(ALine: Integer; out AFixtureIndex, ATestIndex: Integer): Boolean;
var
  mFixtureIndex, mTestIndex: Integer;
begin
  AFixtureIndex := -1;
  ATestIndex := -1;
  for mFixtureIndex := 0 to High(Fixtures) do
  begin
    if (Fixtures[mFixtureIndex].AttributeLine = ALine) or (Fixtures[mFixtureIndex].Line = ALine) then
    begin
      AFixtureIndex := mFixtureIndex;
      Exit(True);
    end;
    for mTestIndex := 0 to High(Fixtures[mFixtureIndex].Tests) do
    begin
      if (Fixtures[mFixtureIndex].Tests[mTestIndex].AttributeLine = ALine) or
        (Fixtures[mFixtureIndex].Tests[mTestIndex].Line = ALine) then
      begin
        AFixtureIndex := mFixtureIndex;
        ATestIndex := mTestIndex;
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

function TDUnitXUnit.LineOf(const AFixture, AMethod: string): Integer;
var
  mFixtureIndex, mTestIndex: Integer;
begin
  if not Find(AFixture, AMethod, mFixtureIndex, mTestIndex) then
  begin
    Exit(-1);
  end;
  if mTestIndex < 0 then
  begin
    Exit(Fixtures[mFixtureIndex].Line);
  end;
  Result := Fixtures[mFixtureIndex].Tests[mTestIndex].BodyLine;
  if Result < 0 then
  begin
    Result := Fixtures[mFixtureIndex].Tests[mTestIndex].Line;
  end;
end;

function TDUnitXUnit.CaseHasOwnLine(AFixtureIndex, ATestIndex, ACaseIndex: Integer): Boolean;
var
  mIndex: Integer;
  mLines: TArray<Integer>;
begin
  Result := False;
  if (AFixtureIndex < 0) or (AFixtureIndex > High(Fixtures)) or (ATestIndex < 0) or
    (ATestIndex > High(Fixtures[AFixtureIndex].Tests)) then
  begin
    Exit;
  end;
  mLines := Fixtures[AFixtureIndex].Tests[ATestIndex].CaseLines;
  if (ACaseIndex < 0) or (ACaseIndex > High(mLines)) or
    (mLines[ACaseIndex] = Fixtures[AFixtureIndex].Tests[ATestIndex].Line) then
  begin
    Exit;
  end;
  for mIndex := 0 to High(mLines) do
  begin
    if (mIndex <> ACaseIndex) and (mLines[mIndex] = mLines[ACaseIndex]) then
    begin
      Exit;
    end;
  end;
  Result := True;
end;

function TDUnitXUnit.MarkLine(AFixtureIndex, ATestIndex: Integer): Integer;
var
  mTest: TDUnitXTest;
  mIndex: Integer;
begin
  Result := -1;
  if (AFixtureIndex < 0) or (AFixtureIndex > High(Fixtures)) then
  begin
    Exit;
  end;
  if ATestIndex < 0 then
  begin
    Exit(Fixtures[AFixtureIndex].AttributeLine);
  end;
  if ATestIndex > High(Fixtures[AFixtureIndex].Tests) then
  begin
    Exit;
  end;
  mTest := Fixtures[AFixtureIndex].Tests[ATestIndex];
  Result := mTest.AttributeLine;
  // Steht dort ein Fall mit eigener Marke, rückt die Marke des Tests an die Deklaration.
  for mIndex := 0 to High(mTest.CaseLines) do
  begin
    if (mTest.CaseLines[mIndex] = Result) and CaseHasOwnLine(AFixtureIndex, ATestIndex, mIndex) then
    begin
      Exit(mTest.Line);
    end;
  end;
end;

// Index des [TestCase] von ATest in Zeile ALine; -1 ohne.
function CaseIndexAt(const ATest: TDUnitXTest; ALine: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ATest.CaseLines) do
  begin
    if ATest.CaseLines[mIndex] = ALine then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

// Liegt ALine zwischen erstem Attribut und Deklaration ([Category] …) oder im Rumpf bis zum end?
function IsInTest(const ATest: TDUnitXTest; ALine: Integer): Boolean;
begin
  Result := (ALine >= ATest.AttributeLine) and (ALine <= ATest.Line);
  if not Result and (ATest.BodyLine >= 0) and (ATest.EndLine >= ATest.BodyLine) then
  begin
    Result := (ALine >= ATest.BodyLine) and (ALine <= ATest.EndLine);
  end;
end;

// Erster Test mit einem [TestCase] in Zeile ALine.
function CaseAt(const AFixtures: TArray<TDUnitXFixture>; ALine: Integer; out AFixtureIndex, ATestIndex,
  ACaseIndex: Integer): Boolean;
var
  mFixture, mTest: Integer;
begin
  AFixtureIndex := -1;
  ATestIndex := -1;
  ACaseIndex := -1;
  for mFixture := 0 to High(AFixtures) do
  begin
    for mTest := 0 to High(AFixtures[mFixture].Tests) do
    begin
      ACaseIndex := CaseIndexAt(AFixtures[mFixture].Tests[mTest], ALine);
      if ACaseIndex >= 0 then
      begin
        AFixtureIndex := mFixture;
        ATestIndex := mTest;
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

// Erster Test, in dessen Attributen oder Rumpf ALine liegt.
function TestRangeAt(const AFixtures: TArray<TDUnitXFixture>; ALine: Integer; out AFixtureIndex,
  ATestIndex: Integer): Boolean;
var
  mFixture, mTest: Integer;
begin
  AFixtureIndex := -1;
  ATestIndex := -1;
  for mFixture := 0 to High(AFixtures) do
  begin
    for mTest := 0 to High(AFixtures[mFixture].Tests) do
    begin
      if IsInTest(AFixtures[mFixture].Tests[mTest], ALine) then
      begin
        AFixtureIndex := mFixture;
        ATestIndex := mTest;
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

function TDUnitXUnit.TestAt(ALine: Integer; out AFixtureIndex, ATestIndex, ACaseIndex: Integer): Boolean;
begin
  // Zeile eines [TestCase]: nur dieser Fall.
  if CaseAt(Fixtures, ALine, AFixtureIndex, ATestIndex, ACaseIndex) then
  begin
    if not CaseHasOwnLine(AFixtureIndex, ATestIndex, ACaseIndex) then
    begin
      ACaseIndex := -1;
    end;
    Exit(True);
  end;
  Result := AtLine(ALine, AFixtureIndex, ATestIndex) or TestRangeAt(Fixtures, ALine, AFixtureIndex, ATestIndex);
end;

{ TDUnitXSource }

class function TDUnitXSource.AttributeOf(const AName: string): TDUnitXAttribute;
const
  cNames: array[TDUnitXAttribute] of string = ('', 'TestFixture', 'Test', 'TestCase', 'Ignore', 'Category', 'Setup',
    'TearDown', 'SetupFixture', 'TearDownFixture');
var
  mName: string;
  mKind: TDUnitXAttribute;
begin
  mName := Trim(AName);
  // Qualifiziert (DUnitX.Attributes.TestFixture): nur der letzte Teil zählt.
  if LastDelimiter('.', mName) > 0 then
  begin
    mName := Copy(mName, LastDelimiter('.', mName) + 1, MaxInt);
  end;
  if (Length(mName) > Length('Attribute')) and SameText(Copy(mName, Length(mName) - 8, 9), 'Attribute') then
  begin
    SetLength(mName, Length(mName) - 9);
  end;
  for mKind := Succ(TDUnitXAttribute.None) to High(TDUnitXAttribute) do
  begin
    if SameText(mName, cNames[mKind]) then
    begin
      Exit(mKind);
    end;
  end;
  Result := TDUnitXAttribute.None;
end;

function IsUsesSeparator(const AToken: TToken): Boolean;
begin
  Result := IsSym(AToken, ',') or IsSym(AToken, ';') or IsWord(AToken, 'in');
end;

class function TDUnitXSource.UsesDUnitX(const ALines: TArray<string>): Boolean;
var
  mTokens: TArray<TToken>;
  mIndex: Integer;
begin
  mTokens := Tokenize(ALines);
  for mIndex := 0 to High(mTokens) - 4 do
  begin
    if IsWord(mTokens[mIndex], 'DUnitX') and IsSym(mTokens[mIndex + 1], '.') and
      IsWord(mTokens[mIndex + 2], 'TestFramework') and IsUsesSeparator(mTokens[mIndex + 3]) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function IsMethodWord(const AToken: TToken): Boolean;
begin
  Result := IsWord(AToken, 'procedure') or IsWord(AToken, 'function');
end;

function IsTypeKeyword(const AToken: TToken): Boolean;
begin
  Result := IsWord(AToken, 'class') or IsWord(AToken, 'object') or IsWord(AToken, 'interface');
end;

function IsSectionWord(const AToken: TToken): Boolean;
begin
  Result := IsWord(AToken, 'implementation') or IsWord(AToken, 'initialization') or IsWord(AToken, 'finalization');
end;

function IsBlockStart(const AToken: TToken): Boolean;
begin
  Result := IsWord(AToken, 'begin') or IsWord(AToken, 'try') or IsWord(AToken, 'case') or IsWord(AToken, 'asm');
end;

// Attribute vor einer Methode auf ATest anwenden. AIsTest: [Test] oder [TestCase]; ANotTest: [Test(False)],
// [Setup], [TearDown], [SetupFixture] oder [TearDownFixture].
procedure ApplyAttributes(const APending: TArray<TPendingAttribute>; var ATest: TDUnitXTest; out AIsTest,
  ANotTest: Boolean);
var
  mAttribute: TPendingAttribute;
begin
  AIsTest := False;
  ANotTest := False;
  for mAttribute in APending do
  begin
    case mAttribute.Kind of
      TDUnitXAttribute.Test:
        // [Test(False)] schaltet den Test ab.
        if SameText(mAttribute.FirstArgument, 'False') then
        begin
          ANotTest := True;
        end
        else
        begin
          AIsTest := True;
        end;
      TDUnitXAttribute.TestCase:
        begin
          AIsTest := True;
          ATest.Cases := ATest.Cases + [mAttribute.FirstArgument];
          ATest.CaseLines := ATest.CaseLines + [mAttribute.Line];
        end;
      TDUnitXAttribute.Ignore:
        ATest.Ignored := True;
      TDUnitXAttribute.Setup, TDUnitXAttribute.TearDown, TDUnitXAttribute.SetupFixture,
      TDUnitXAttribute.TearDownFixture:
        ANotTest := True;
      TDUnitXAttribute.None: ;
      TDUnitXAttribute.TestFixture: ;
      TDUnitXAttribute.Category: ;
    end;
  end;
end;

type
  /// <summary>Klasse, die eine Fixture sein kann: zählt mit [TestFixture] oder RegisterTestFixture.</summary>
  TCandidate = record
    Fixture: TDUnitXFixture;
    HasFixtureAttribute: Boolean;
  end;

  /// <summary>Zustand beim Lesen einer Klassendeklaration.</summary>
  TClassBody = record
    Depth: Integer;
    IsPublished: Boolean;
    /// <summary>„class“ vor procedure/function: Klassenmethode.</summary>
    AfterClassWord: Boolean;
  end;

  /// <summary>Liest Fixtures und Tests aus den Tokens einer Unit; der Zustand gilt für einen Aufruf von Run.</summary>
  TDUnitXScanner = class
  private
    FTokens: TArray<TToken>;
    FCount: Integer;
    FIndex: Integer;
    FCandidates: TArray<TCandidate>;
    FRegistered: TArray<string>;
    FPending: TArray<TPendingAttribute>;
    FInImplementation: Boolean;
    FUnitName: string;
    function Peek(AOffset: Integer): TToken;
    /// <summary>Token an FIndex; hinter dem Ende ein leeres Symbol.</summary>
    function Token: TToken;
    function DottedName: string;
    procedure SkipGroup(const AOpen, AClose: string);
    procedure ReadAttributes;
    function FirstPendingLine(ADefault: Integer): Integer;
    function HasPending(AKind: TDUnitXAttribute): Boolean;
    function StartsTypeWithEnd: Boolean;
    function StartsTypeBody: Boolean;
    function StartsLocalRoutine: Boolean;
    procedure ReadMethod(var AFixture: TDUnitXFixture; APublished: Boolean);
    function SkipClassHead: Boolean;
    function ReadMember(var ABody: TClassBody; var AFixture: TDUnitXFixture): Boolean;
    procedure ReadClassToken(var ABody: TClassBody; var AFixture: TDUnitXFixture);
    procedure ReadClass;
    procedure SkipHeader;
    function SkipStatements: Integer;
    procedure SkipTypeBody;
    procedure ReadStatements(out ABeginLine, AEndLine: Integer);
    procedure ReadRoutine(ADepth: Integer; out ABeginLine, AEndLine: Integer);
    function MarkBody(const AClassName, AMethod: string; ALine: Integer; out ACandidate, ATest: Integer): Boolean;
    procedure ReadBody;
    function IsUnitHeader: Boolean;
    function StartsAttributeList: Boolean;
    function IsRegistration: Boolean;
    function IsClassStart: Boolean;
    function IsBodyStart: Boolean;
    procedure ReadTopLevel;
    function IsRegisteredName(const AName: string): Boolean;
    function Fixtures: TArray<TDUnitXFixture>;
  public
    function Run(const ALines: TArray<string>): TDUnitXUnit;
  end;

function TDUnitXScanner.Peek(AOffset: Integer): TToken;
begin
  if (FIndex + AOffset >= 0) and (FIndex + AOffset < FCount) then
  begin
    Exit(FTokens[FIndex + AOffset]);
  end;
  Result := Default(TToken);
  Result.Kind := TTokenKind.Sym;
  Result.Line := -1;
end;

function TDUnitXScanner.Token: TToken;
begin
  Result := Peek(0);
end;

/// <summary>Punktname ab FIndex (A.B.C); FIndex steht danach hinter dem Namen.</summary>
function TDUnitXScanner.DottedName: string;
begin
  Result := '';
  while Token.Kind = TTokenKind.Ident do
  begin
    Result := Result + Token.Text;
    Inc(FIndex);
    if not IsSym(Token, '.') or (Peek(1).Kind <> TTokenKind.Ident) then
    begin
      Break;
    end;
    Result := Result + '.';
    Inc(FIndex);
  end;
end;

/// <summary>Überspringt bis zur passenden schließenden Klammer; FIndex steht danach dahinter.</summary>
procedure TDUnitXScanner.SkipGroup(const AOpen, AClose: string);
var
  mDepth: Integer;
begin
  mDepth := 0;
  while FIndex < FCount do
  begin
    if IsSym(Token, AOpen) then
    begin
      Inc(mDepth);
    end
    else if IsSym(Token, AClose) then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Inc(FIndex);
        Exit;
      end;
    end;
    Inc(FIndex);
  end;
end;

/// <summary>Liest „[A, B('x')]“ ab FIndex (auf „[“) in FPending.</summary>
procedure TDUnitXScanner.ReadAttributes;
var
  mAttribute: TPendingAttribute;
begin
  Inc(FIndex);
  while (FIndex < FCount) and not IsSym(Token, ']') do
  begin
    if Token.Kind <> TTokenKind.Ident then
    begin
      Inc(FIndex);
      Continue;
    end;
    mAttribute := Default(TPendingAttribute);
    mAttribute.Line := Token.Line;
    mAttribute.Kind := TDUnitXSource.AttributeOf(DottedName);
    if IsSym(Token, '(') then
    begin
      mAttribute.FirstArgument := Peek(1).Text;
      SkipGroup('(', ')');
    end;
    FPending := FPending + [mAttribute];
  end;
  if FIndex < FCount then
  begin
    Inc(FIndex);
  end;
end;

function TDUnitXScanner.FirstPendingLine(ADefault: Integer): Integer;
begin
  Result := ADefault;
  if Length(FPending) > 0 then
  begin
    Result := FPending[0].Line;
  end;
end;

function TDUnitXScanner.HasPending(AKind: TDUnitXAttribute): Boolean;
var
  mAttribute: TPendingAttribute;
begin
  for mAttribute in FPending do
  begin
    if mAttribute.Kind = AKind then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Typ mit end im Deklarationsteil an FIndex: record oder „= class“, „= object“, „= interface“.</summary>
function TDUnitXScanner.StartsTypeWithEnd: Boolean;
begin
  Result := IsWord(Token, 'record') or (IsTypeKeyword(Token) and IsSym(Peek(-1), '='));
end;

/// <summary>Wie StartsTypeWithEnd, aber ohne Vorwärtsdeklaration und Klassenreferenz („= class;“, „= class of“).
/// </summary>
function TDUnitXScanner.StartsTypeBody: Boolean;
begin
  Result := StartsTypeWithEnd and not IsSym(Peek(1), ';') and not IsWord(Peek(1), 'of');
end;

/// <summary>Lokale Routine an FIndex (nicht der Typ „procedure(…) of object“ hinter „=“, „:“ oder „to“).</summary>
function TDUnitXScanner.StartsLocalRoutine: Boolean;
begin
  Result := IsMethodWord(Token) and (Peek(1).Kind = TTokenKind.Ident) and
    not (IsSym(Peek(-1), '=') or IsSym(Peek(-1), ':') or IsWord(Peek(-1), 'to'));
end;

/// <summary>Methode in einer Fixture: FIndex steht auf procedure/function.</summary>
procedure TDUnitXScanner.ReadMethod(var AFixture: TDUnitXFixture; APublished: Boolean);
var
  mTest: TDUnitXTest;
  mIsTest, mNotTest: Boolean;
begin
  mTest := Default(TDUnitXTest);
  mTest.Line := Token.Line;
  mTest.AttributeLine := FirstPendingLine(mTest.Line);
  mTest.BodyLine := -1;
  mTest.BeginLine := -1;
  mTest.EndLine := -1;
  Inc(FIndex);
  if Token.Kind <> TTokenKind.Ident then
  begin
    Exit;
  end;
  mTest.Method := Token.Text;
  Inc(FIndex);
  ApplyAttributes(FPending, mTest, mIsTest, mNotTest);
  if APublished and (Length(FPending) = 0) then
  begin
    mIsTest := True;
  end;
  if mIsTest and not mNotTest then
  begin
    AFixture.Tests := AFixture.Tests + [mTest];
  end;
end;

/// <summary>Kopf der Klasse ab „class“ bis zum Rumpf; False ohne Rumpf.</summary>
function TDUnitXScanner.SkipClassHead: Boolean;
begin
  Inc(FIndex);
  // Vorwärtsdeklaration, Klassenreferenz, class helper ohne Rumpf.
  if IsSym(Token, ';') or IsWord(Token, 'of') then
  begin
    Exit(False);
  end;
  while IsWord(Token, 'sealed') or IsWord(Token, 'abstract') do
  begin
    Inc(FIndex);
  end;
  if IsSym(Token, '(') then
  begin
    SkipGroup('(', ')');
  end;
  // „TFoo = class(TBar);“ ohne Rumpf.
  Result := not IsSym(Token, ';');
end;

/// <summary>Sichtbarkeit, „class“ vor einer Klassenmethode oder Methode auf der Ebene der Klasse; False für alles
/// andere.</summary>
function TDUnitXScanner.ReadMember(var ABody: TClassBody; var AFixture: TDUnitXFixture): Boolean;
begin
  Result := True;
  if IsVisibility(Token) then
  begin
    ABody.IsPublished := IsWord(Token, 'published');
    FPending := nil;
    Inc(FIndex);
  end
  else if IsWord(Token, 'class') then
  begin
    // class procedure/function: Klassenmethoden sind keine Tests.
    ABody.AfterClassWord := True;
    Inc(FIndex);
  end
  else if IsMethodWord(Token) then
  begin
    if ABody.AfterClassWord then
    begin
      Inc(FIndex);
    end
    else
    begin
      ReadMethod(AFixture, ABody.IsPublished);
    end;
    ABody.AfterClassWord := False;
    FPending := nil;
  end
  else
  begin
    Result := False;
  end;
end;

procedure TDUnitXScanner.ReadClassToken(var ABody: TClassBody; var AFixture: TDUnitXFixture);
begin
  if IsSym(Token, '[') then
  begin
    ReadAttributes;
  end
  else if IsWord(Token, 'end') then
  begin
    Dec(ABody.Depth);
    FPending := nil;
    Inc(FIndex);
  end
  else if StartsTypeBody then
  begin
    Inc(ABody.Depth);
    Inc(FIndex);
  end
  else if (ABody.Depth <> 1) or not ReadMember(ABody, AFixture) then
  begin
    // Alles andere zwischen Attribut und Methode (Feld, Eigenschaft, Parameter): die Attribute gehören nicht
    // zu einer Methode.
    ABody.AfterClassWord := False;
    FPending := nil;
    Inc(FIndex);
  end;
end;

/// <summary>Klasse ab FIndex (auf dem Namen vor „= class“); liest bis zum passenden end.</summary>
procedure TDUnitXScanner.ReadClass;
var
  mCandidate: TCandidate;
  mBody: TClassBody;
begin
  mCandidate := Default(TCandidate);
  mCandidate.Fixture.Name := Token.Text;
  mCandidate.Fixture.Line := Token.Line;
  mCandidate.Fixture.AttributeLine := FirstPendingLine(mCandidate.Fixture.Line);
  mCandidate.HasFixtureAttribute := HasPending(TDUnitXAttribute.TestFixture);
  FPending := nil;
  Inc(FIndex, 2);
  if not SkipClassHead then
  begin
    Exit;
  end;
  // Ohne Sichtbarkeit sind Methoden mit {$M+} published; DUnitX-Fixtures haben das selten: wie public.
  mBody := Default(TClassBody);
  mBody.Depth := 1;
  while (FIndex < FCount) and (mBody.Depth > 0) do
  begin
    ReadClassToken(mBody, mCandidate.Fixture);
  end;
  FCandidates := FCandidates + [mCandidate];
end;

/// <summary>Kopf einer Routine bis zum ersten „;“ außerhalb von Klammern; FIndex steht danach dahinter.</summary>
procedure TDUnitXScanner.SkipHeader;
var
  mDepth: Integer;
begin
  mDepth := 0;
  while FIndex < FCount do
  begin
    if IsSym(Token, '(') then
    begin
      Inc(mDepth);
    end
    else if IsSym(Token, ')') then
    begin
      Dec(mDepth);
    end
    else if IsSym(Token, ';') and (mDepth <= 0) then
    begin
      Inc(FIndex);
      Exit;
    end;
    Inc(FIndex);
  end;
end;

/// <summary>Anweisungsteil ab begin bzw. asm (FIndex darauf) bis zum passenden end; Zeile dieses end, -1 ohne.
/// FIndex steht danach dahinter.</summary>
function TDUnitXScanner.SkipStatements: Integer;
var
  mDepth: Integer;
begin
  Result := -1;
  mDepth := 0;
  while FIndex < FCount do
  begin
    if IsBlockStart(Token) then
    begin
      Inc(mDepth);
    end
    else if IsWord(Token, 'end') then
    begin
      Dec(mDepth);
      if mDepth <= 0 then
      begin
        Result := Token.Line;
        Inc(FIndex);
        Exit;
      end;
    end;
    Inc(FIndex);
  end;
end;

/// <summary>Typ mit end im Deklarationsteil (record, class, object, interface; FIndex darauf): bis hinter das
/// passende end. Varianten (case) haben kein eigenes end.</summary>
procedure TDUnitXScanner.SkipTypeBody;
var
  mDepth: Integer;
begin
  mDepth := 0;
  while FIndex < FCount do
  begin
    if StartsTypeWithEnd then
    begin
      Inc(mDepth);
    end
    else if IsWord(Token, 'end') then
    begin
      Dec(mDepth);
      if mDepth <= 0 then
      begin
        Inc(FIndex);
        Exit;
      end;
    end;
    Inc(FIndex);
  end;
end;

/// <summary>Anweisungsteil ab begin bzw. asm: Zeile der ersten Anweisung (ohne Anweisung die von begin) und des
/// abschließenden end.</summary>
procedure TDUnitXScanner.ReadStatements(out ABeginLine, AEndLine: Integer);
begin
  ABeginLine := Token.Line;
  if (FIndex + 1 < FCount) and not IsWord(Peek(1), 'end') then
  begin
    ABeginLine := Peek(1).Line;
  end;
  AEndLine := SkipStatements;
end;

/// <summary>Rumpf einer Routine ab dem Ende ihres Kopfs: Deklarationen samt lokalen Routinen, dann der
/// Anweisungsteil. ABeginLine: Zeile der ersten Anweisung, ohne Anweisung die von begin; AEndLine: Zeile des
/// abschließenden end. Beide -1, wenn kein Rumpf folgt (forward, external, Ende des Abschnitts).</summary>
procedure TDUnitXScanner.ReadRoutine(ADepth: Integer; out ABeginLine, AEndLine: Integer);
var
  mInnerBegin, mInnerEnd: Integer;
begin
  ABeginLine := -1;
  AEndLine := -1;
  while FIndex < FCount do
  begin
    if IsWord(Token, 'begin') or IsWord(Token, 'asm') then
    begin
      ReadStatements(ABeginLine, AEndLine);
      Exit;
    end;
    if IsWord(Token, 'forward') or IsWord(Token, 'external') then
    begin
      SkipHeader;
      Exit;
    end;
    if IsSectionWord(Token) then
    begin
      Exit;
    end;
    if (ADepth < 16) and StartsLocalRoutine then
    begin
      Inc(FIndex);
      SkipHeader;
      ReadRoutine(ADepth + 1, mInnerBegin, mInnerEnd);
    end
    else if StartsTypeBody then
    begin
      SkipTypeBody;
    end
    else
    begin
      Inc(FIndex);
    end;
  end;
end;

/// <summary>Trägt ALine als Kopfzeile des Tests AClassName.AMethod ein (jeder noch ohne Rumpf, der passt);
/// ACandidate und ATest nennen den letzten. False ohne passenden Test.</summary>
function TDUnitXScanner.MarkBody(const AClassName, AMethod: string; ALine: Integer; out ACandidate,
  ATest: Integer): Boolean;
var
  mCandidate, mTest: Integer;
begin
  ACandidate := -1;
  ATest := -1;
  for mCandidate := 0 to High(FCandidates) do
  begin
    if not SameText(FCandidates[mCandidate].Fixture.Name, AClassName) then
    begin
      Continue;
    end;
    for mTest := 0 to High(FCandidates[mCandidate].Fixture.Tests) do
    begin
      if SameText(FCandidates[mCandidate].Fixture.Tests[mTest].Method, AMethod) and
        (FCandidates[mCandidate].Fixture.Tests[mTest].BodyLine < 0) then
      begin
        FCandidates[mCandidate].Fixture.Tests[mTest].BodyLine := ALine;
        ACandidate := mCandidate;
        ATest := mTest;
      end;
    end;
  end;
  Result := ACandidate >= 0;
end;

/// <summary>„procedure TFoo.Bar“ im implementation-Teil: Zeilen von Kopf, erster Anweisung und end merken.
/// </summary>
procedure TDUnitXScanner.ReadBody;
var
  mLine, mCandidate, mTest, mBeginLine, mEndLine: Integer;
  mClassName, mMethod: string;
begin
  mLine := Token.Line;
  Inc(FIndex);
  if (FIndex + 2 >= FCount) or (Token.Kind <> TTokenKind.Ident) or not IsSym(Peek(1), '.') or
    (Peek(2).Kind <> TTokenKind.Ident) then
  begin
    Exit;
  end;
  mClassName := Token.Text;
  mMethod := Peek(2).Text;
  Inc(FIndex, 3);
  if not MarkBody(mClassName, mMethod, mLine, mCandidate, mTest) then
  begin
    Exit;
  end;
  // Rumpf des Tests: Haltepunkt und Bereich für „Test am Cursor“ (#585).
  SkipHeader;
  ReadRoutine(0, mBeginLine, mEndLine);
  FCandidates[mCandidate].Fixture.Tests[mTest].BeginLine := mBeginLine;
  FCandidates[mCandidate].Fixture.Tests[mTest].EndLine := mEndLine;
end;

function TDUnitXScanner.IsUnitHeader: Boolean;
begin
  Result := (FIndex = 0) and (FUnitName = '') and (IsWord(Token, 'unit') or IsWord(Token, 'program'));
end;

function TDUnitXScanner.StartsAttributeList: Boolean;
begin
  Result := IsSym(Token, '[') and (IsSym(Peek(-1), ';') or IsSym(Peek(-1), ']') or IsWord(Peek(-1), 'type'));
end;

// RegisterTestFixture(TFoo)
function TDUnitXScanner.IsRegistration: Boolean;
begin
  Result := IsWord(Token, 'RegisterTestFixture') and IsSym(Peek(1), '(') and (Peek(2).Kind = TTokenKind.Ident);
end;

// TFoo = class …
function TDUnitXScanner.IsClassStart: Boolean;
begin
  Result := (Token.Kind = TTokenKind.Ident) and IsSym(Peek(1), '=') and IsWord(Peek(2), 'class');
end;

function TDUnitXScanner.IsBodyStart: Boolean;
begin
  Result := FInImplementation and IsMethodWord(Token) and not IsWord(Peek(-1), 'class');
end;

procedure TDUnitXScanner.ReadTopLevel;
begin
  if IsUnitHeader then
  begin
    Inc(FIndex);
    FUnitName := DottedName;
  end
  else if IsWord(Token, 'implementation') then
  begin
    FInImplementation := True;
    FPending := nil;
    Inc(FIndex);
  end
  else if StartsAttributeList then
  begin
    ReadAttributes;
  end
  else if IsRegistration then
  begin
    FRegistered := FRegistered + [Peek(2).Text];
    Inc(FIndex, 3);
  end
  else if IsClassStart then
  begin
    ReadClass;
  end
  else if IsBodyStart then
  begin
    ReadBody;
    FPending := nil;
  end
  else
  begin
    // Generische Fixtures (TFoo<T> = class) und alles andere: Attribute gelten nicht mehr.
    if not IsWord(Token, 'type') then
    begin
      FPending := nil;
    end;
    Inc(FIndex);
  end;
end;

function TDUnitXScanner.IsRegisteredName(const AName: string): Boolean;
var
  mName: string;
begin
  for mName in FRegistered do
  begin
    if SameText(mName, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TDUnitXScanner.Fixtures: TArray<TDUnitXFixture>;
var
  mCandidate: TCandidate;
begin
  Result := nil;
  for mCandidate in FCandidates do
  begin
    if mCandidate.HasFixtureAttribute or IsRegisteredName(mCandidate.Fixture.Name) then
    begin
      Result := Result + [mCandidate.Fixture];
    end;
  end;
end;

function TDUnitXScanner.Run(const ALines: TArray<string>): TDUnitXUnit;
begin
  FTokens := Tokenize(ALines);
  FCount := Length(FTokens);
  FIndex := 0;
  while FIndex < FCount do
  begin
    ReadTopLevel;
  end;
  Result := Default(TDUnitXUnit);
  Result.UnitName := FUnitName;
  Result.Fixtures := Fixtures;
end;

class function TDUnitXSource.Scan(const ALines: TArray<string>): TDUnitXUnit;
var
  mScanner: TDUnitXScanner;
begin
  mScanner := TDUnitXScanner.Create;
  try
    Result := mScanner.Run(ALines);
  finally
    mScanner.Free;
  end;
end;

{ TDUnitXCommandLine }

class function TDUnitXCommandLine.TestName(const AUnitName, AFixture, AMethod: string): string;
begin
  Result := AFixture;
  if AUnitName <> '' then
  begin
    Result := AUnitName + '.' + Result;
  end;
  if AMethod <> '' then
  begin
    Result := Result + '.' + AMethod;
  end;
end;

class function TDUnitXCommandLine.CaseName(const AUnitName, AFixture, AMethod, ACase: string): string;
begin
  Result := TestName(AUnitName, AFixture, AMethod);
  // TDUnitXTestCase.GetName: „Methode(1,2)“ bei AutoNameTestCase, sonst „Methode.Fall“.
  if ACase = '' then
  begin
    Exit;
  end;
  if ACase[1] = '(' then
  begin
    Result := Result + ACase;
  end
  else
  begin
    Result := Result + '.' + ACase;
  end;
end;

class function TDUnitXCommandLine.RunNames(const AUnit: TDUnitXUnit; AFixtureIndex, ATestIndex,
  ACaseIndex: Integer): TArray<string>;
var
  mFixture: TDUnitXFixture;
  mTest: TDUnitXTest;
  mIndex: Integer;
  mName: string;
  mShadowed: Boolean;
  mNames: TArray<string>;

  procedure Add(const AName: string);
  var
    mKnown: string;
  begin
    for mKnown in mNames do
    begin
      if SameText(mKnown, AName) then
      begin
        Exit;
      end;
    end;
    mNames := mNames + [AName];
  end;

  procedure AddTest(const ATest: TDUnitXTest; ACase: Integer);
  var
    mCaseIndex: Integer;
  begin
    // Ohne Fälle oder mit [Ignore] (DUnitX führt sie dann als einen Test): der Name der Methode.
    if (Length(ATest.Cases) = 0) or ATest.Ignored then
    begin
      Add(TestName(AUnit.UnitName, mFixture.Name, ATest.Method));
    end
    else if (ACase >= 0) and (ACase <= High(ATest.Cases)) then
    begin
      Add(CaseName(AUnit.UnitName, mFixture.Name, ATest.Method, ATest.Cases[ACase]));
    end
    else
    begin
      for mCaseIndex := 0 to High(ATest.Cases) do
      begin
        Add(CaseName(AUnit.UnitName, mFixture.Name, ATest.Method, ATest.Cases[mCaseIndex]));
      end;
    end;
  end;

begin
  Result := nil;
  mNames := nil;
  if (AFixtureIndex < 0) or (AFixtureIndex > High(AUnit.Fixtures)) then
  begin
    Exit;
  end;
  mFixture := AUnit.Fixtures[AFixtureIndex];
  if ATestIndex >= 0 then
  begin
    if ATestIndex > High(mFixture.Tests) then
    begin
      Exit;
    end;
    mTest := mFixture.Tests[ATestIndex];
    AddTest(mTest, ACaseIndex);
    Exit(mNames);
  end;
  // Die ganze Fixture: Unit.Fixture, außer eine andere Fixture der Unit beginnt mit demselben Namen.
  mShadowed := False;
  for mIndex := 0 to High(AUnit.Fixtures) do
  begin
    mName := AUnit.Fixtures[mIndex].Name;
    if (mIndex <> AFixtureIndex) and (Length(mName) > Length(mFixture.Name)) and
      SameText(Copy(mName, 1, Length(mFixture.Name)), mFixture.Name) then
    begin
      mShadowed := True;
    end;
  end;
  if not mShadowed then
  begin
    Result := [TestName(AUnit.UnitName, mFixture.Name, '')];
    Exit;
  end;
  for mTest in mFixture.Tests do
  begin
    AddTest(mTest, -1);
  end;
  Result := mNames;
end;

class function TDUnitXCommandLine.Arguments(const AResultFile: string; const ATests: TArray<string>): TArray<string>;
var
  mRun: string;
  mTest: string;
begin
  // Nur Optionen, die alle DUnitX-Fassungen seit RAD Studio 10 kennen; eine unbekannte Option lässt das
  // Testprogramm ohne Lauf enden (TDUnitX.CheckCommandLine).
  Result := ['--exitbehavior:Continue', '--xmlfile:' + AResultFile];
  mRun := '';
  for mTest in ATests do
  begin
    if mTest <> '' then
    begin
      if mRun <> '' then
      begin
        mRun := mRun + ',';
      end;
      mRun := mRun + mTest;
    end;
  end;
  if (mRun <> '') and (Length(mRun) <= cMaxRunLength) then
  begin
    Result := Result + ['--run:' + mRun];
  end;
end;

end.
