unit Atlas.Text.DUnitX;

// DUnitX-Tests im Quelltext erkennen, gemeinsam für Server und Plugin
// (ADR 0012, #69, #154, #585): Attribute nach dem Namen ([TestFixture],
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
// - die Zeile des Methodenkopfs im implementation-Teil.
// Zeilen sind 0-basiert. Der volle Name eines Tests in DUnitX ist
// Unit.Fixture.Methode (bei [TestCase] mit .Fall dahinter); so filtert auch
// --run.

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
    /// <summary>Namen der Testfälle aus [TestCase('Name', …)], in Reihenfolge.</summary>
    Cases: TArray<string>;
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
    MaxRunLength = 24000;
  public
    /// <summary>Voller Name für --run: Unit.Fixture bzw. Unit.Fixture.Methode (AMethod = '').</summary>
    class function TestName(const AUnitName, AFixture, AMethod: string): string; static;
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

function Tokenize(const ALines: TArray<string>): TArray<TToken>;
var
  Count: Integer;
  LineIndex, Index, Start: Integer;
  Line, Value: string;
  InBrace, InParen: Boolean;

  procedure Add(AKind: TTokenKind; const AText: string; ALine: Integer);
  begin
    if Count = Length(Result) then
      SetLength(Result, Count * 2 + 64);
    Result[Count].Kind := AKind;
    Result[Count].Text := AText;
    Result[Count].Line := ALine;
    Inc(Count);
  end;

begin
  Result := nil;
  Count := 0;
  InBrace := False;
  InParen := False;
  for LineIndex := 0 to High(ALines) do
  begin
    Line := ALines[LineIndex];
    Index := 1;
    while Index <= Length(Line) do
    begin
      if InBrace then
      begin
        if Line[Index] = '}' then
          InBrace := False;
        Inc(Index);
        Continue;
      end;
      if InParen then
      begin
        if (Line[Index] = '*') and (Index < Length(Line)) and (Line[Index + 1] = ')') then
        begin
          InParen := False;
          Inc(Index);
        end;
        Inc(Index);
        Continue;
      end;
      case Line[Index] of
        ' ', #9, #13, #10:
          Inc(Index);
        '{':
          begin
            InBrace := True;
            Inc(Index);
          end;
        '/':
          if (Index < Length(Line)) and (Line[Index + 1] = '/') then
            Index := Length(Line) + 1
          else
          begin
            Add(TTokenKind.Sym, '/', LineIndex);
            Inc(Index);
          end;
        '(':
          if (Index < Length(Line)) and (Line[Index + 1] = '*') then
          begin
            InParen := True;
            Inc(Index, 2);
          end
          else
          begin
            Add(TTokenKind.Sym, '(', LineIndex);
            Inc(Index);
          end;
        '''', '#':
          begin
            // Zeichenkette samt #13-Teilen als ein Token; nur der Text in Anführungszeichen zählt.
            Value := '';
            while (Index <= Length(Line)) and ((Line[Index] = '''') or (Line[Index] = '#')) do
              if Line[Index] = '#' then
              begin
                Inc(Index);
                while (Index <= Length(Line)) and (CharInSet(Line[Index], ['0'..'9', '$', 'A'..'F', 'a'..'f'])) do
                  Inc(Index);
              end
              else
              begin
                Inc(Index);
                while Index <= Length(Line) do
                begin
                  if Line[Index] = '''' then
                  begin
                    if (Index < Length(Line)) and (Line[Index + 1] = '''') then
                    begin
                      Value := Value + '''';
                      Inc(Index, 2);
                      Continue;
                    end;
                    Inc(Index);
                    Break;
                  end;
                  Value := Value + Line[Index];
                  Inc(Index);
                end;
              end;
            Add(TTokenKind.Str, Value, LineIndex);
          end;
        '0'..'9', '$':
          begin
            Start := Index;
            Inc(Index);
            while (Index <= Length(Line)) and TTextChars.IsIdentChar(Line[Index]) do
              Inc(Index);
            Add(TTokenKind.Num, Copy(Line, Start, Index - Start), LineIndex);
          end;
      else
        if (Line[Index] = '&') and (Index < Length(Line)) and TTextChars.IsIdentStart(Line[Index + 1]) then
          Inc(Index);
        if TTextChars.IsIdentStart(Line[Index]) then
        begin
          Start := Index;
          Inc(Index);
          while (Index <= Length(Line)) and TTextChars.IsIdentChar(Line[Index]) do
            Inc(Index);
          Add(TTokenKind.Ident, Copy(Line, Start, Index - Start), LineIndex);
        end
        else
        begin
          Add(TTokenKind.Sym, Line[Index], LineIndex);
          Inc(Index);
        end;
      end;
    end;
  end;
  SetLength(Result, Count);
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
  Fixture: TDUnitXFixture;
begin
  Result := 0;
  for Fixture in Fixtures do
    Inc(Result, Length(Fixture.Tests));
end;

function TDUnitXUnit.Find(const AFixture, AMethod: string; out AFixtureIndex, ATestIndex: Integer): Boolean;
var
  Index: Integer;
begin
  AFixtureIndex := -1;
  ATestIndex := -1;
  for Index := 0 to High(Fixtures) do
    if SameText(Fixtures[Index].Name, AFixture) then
    begin
      AFixtureIndex := Index;
      Break;
    end;
  Result := AFixtureIndex >= 0;
  if not Result or (AMethod = '') then
    Exit;
  for Index := 0 to High(Fixtures[AFixtureIndex].Tests) do
    if SameText(Fixtures[AFixtureIndex].Tests[Index].Method, AMethod) then
    begin
      ATestIndex := Index;
      Exit;
    end;
end;

function TDUnitXUnit.AtLine(ALine: Integer; out AFixtureIndex, ATestIndex: Integer): Boolean;
var
  FixtureIndex, TestIndex: Integer;
begin
  AFixtureIndex := -1;
  ATestIndex := -1;
  for FixtureIndex := 0 to High(Fixtures) do
  begin
    if (Fixtures[FixtureIndex].AttributeLine = ALine) or (Fixtures[FixtureIndex].Line = ALine) then
    begin
      AFixtureIndex := FixtureIndex;
      Exit(True);
    end;
    for TestIndex := 0 to High(Fixtures[FixtureIndex].Tests) do
      if (Fixtures[FixtureIndex].Tests[TestIndex].AttributeLine = ALine) or
        (Fixtures[FixtureIndex].Tests[TestIndex].Line = ALine) then
      begin
        AFixtureIndex := FixtureIndex;
        ATestIndex := TestIndex;
        Exit(True);
      end;
  end;
  Result := False;
end;

function TDUnitXUnit.LineOf(const AFixture, AMethod: string): Integer;
var
  FixtureIndex, TestIndex: Integer;
begin
  if not Find(AFixture, AMethod, FixtureIndex, TestIndex) then
    Exit(-1);
  if TestIndex < 0 then
    Exit(Fixtures[FixtureIndex].Line);
  Result := Fixtures[FixtureIndex].Tests[TestIndex].BodyLine;
  if Result < 0 then
    Result := Fixtures[FixtureIndex].Tests[TestIndex].Line;
end;

{ TDUnitXSource }

class function TDUnitXSource.AttributeOf(const AName: string): TDUnitXAttribute;
const
  Names: array[TDUnitXAttribute] of string = ('', 'TestFixture', 'Test', 'TestCase', 'Ignore', 'Category', 'Setup',
    'TearDown', 'SetupFixture', 'TearDownFixture');
var
  Name: string;
  Kind: TDUnitXAttribute;
begin
  Name := Trim(AName);
  // Qualifiziert (DUnitX.Attributes.TestFixture): nur der letzte Teil zählt.
  if LastDelimiter('.', Name) > 0 then
    Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
  if (Length(Name) > Length('Attribute')) and SameText(Copy(Name, Length(Name) - 8, 9), 'Attribute') then
    SetLength(Name, Length(Name) - 9);
  for Kind := Succ(TDUnitXAttribute.None) to High(TDUnitXAttribute) do
    if SameText(Name, Names[Kind]) then
      Exit(Kind);
  Result := TDUnitXAttribute.None;
end;

class function TDUnitXSource.UsesDUnitX(const ALines: TArray<string>): Boolean;
var
  Tokens: TArray<TToken>;
  Index: Integer;
begin
  Tokens := Tokenize(ALines);
  for Index := 0 to High(Tokens) - 4 do
    if IsWord(Tokens[Index], 'DUnitX') and IsSym(Tokens[Index + 1], '.') and
      IsWord(Tokens[Index + 2], 'TestFramework') and
      (IsSym(Tokens[Index + 3], ',') or IsSym(Tokens[Index + 3], ';') or IsWord(Tokens[Index + 3], 'in')) then
      Exit(True);
  Result := False;
end;

class function TDUnitXSource.Scan(const ALines: TArray<string>): TDUnitXUnit;
type
  TCandidate = record
    Fixture: TDUnitXFixture;
    HasFixtureAttribute: Boolean;
  end;
var
  Tokens: TArray<TToken>;
  Candidates: TArray<TCandidate>;
  Registered: TArray<string>;
  Pending: TArray<TPendingAttribute>;
  Index, Count: Integer;
  InImplementation: Boolean;

  function Peek(AOffset: Integer): TToken;
  begin
    if (Index + AOffset >= 0) and (Index + AOffset < Count) then
      Result := Tokens[Index + AOffset]
    else
    begin
      Result.Kind := TTokenKind.Sym;
      Result.Text := '';
      Result.Line := -1;
    end;
  end;

  /// <summary>Punktname ab Index (A.B.C); Index steht danach hinter dem Namen.</summary>
  function DottedName: string;
  begin
    Result := '';
    while (Index < Count) and (Tokens[Index].Kind = TTokenKind.Ident) do
    begin
      Result := Result + Tokens[Index].Text;
      Inc(Index);
      if (Index < Count - 1) and IsSym(Tokens[Index], '.') and (Tokens[Index + 1].Kind = TTokenKind.Ident) then
      begin
        Result := Result + '.';
        Inc(Index);
      end
      else
        Break;
    end;
  end;

  /// <summary>Überspringt bis zur passenden schließenden Klammer; Index steht danach dahinter.</summary>
  procedure SkipGroup(const AOpen, AClose: string);
  var
    Depth: Integer;
  begin
    Depth := 0;
    while Index < Count do
    begin
      if IsSym(Tokens[Index], AOpen) then
        Inc(Depth)
      else if IsSym(Tokens[Index], AClose) then
      begin
        Dec(Depth);
        if Depth = 0 then
        begin
          Inc(Index);
          Exit;
        end;
      end;
      Inc(Index);
    end;
  end;

  /// <summary>Liest „[A, B('x')]“ ab Index (auf „[“) in Pending.</summary>
  procedure ReadAttributes;
  var
    Attribute: TPendingAttribute;
    Name: string;
  begin
    Inc(Index);
    while (Index < Count) and not IsSym(Tokens[Index], ']') do
    begin
      if Tokens[Index].Kind = TTokenKind.Ident then
      begin
        Attribute := Default(TPendingAttribute);
        Attribute.Line := Tokens[Index].Line;
        Name := DottedName;
        Attribute.Kind := AttributeOf(Name);
        if (Index < Count) and IsSym(Tokens[Index], '(') then
        begin
          if Index + 1 < Count then
            Attribute.FirstArgument := Tokens[Index + 1].Text;
          SkipGroup('(', ')');
        end;
        Pending := Pending + [Attribute];
      end
      else
        Inc(Index);
    end;
    if Index < Count then
      Inc(Index);
  end;

  function FirstPendingLine(ADefault: Integer): Integer;
  begin
    if Length(Pending) > 0 then
      Result := Pending[0].Line
    else
      Result := ADefault;
  end;

  function HasPending(AKind: TDUnitXAttribute): Boolean;
  var
    Attribute: TPendingAttribute;
  begin
    for Attribute in Pending do
      if Attribute.Kind = AKind then
        Exit(True);
    Result := False;
  end;

  /// <summary>Methode in einer Fixture: Index steht auf procedure/function.</summary>
  procedure ReadMethod(var AFixture: TDUnitXFixture; APublished: Boolean);
  var
    Test: TDUnitXTest;
    Attribute: TPendingAttribute;
    IsTest, NotTest: Boolean;
  begin
    Test := Default(TDUnitXTest);
    Test.Line := Tokens[Index].Line;
    Test.AttributeLine := FirstPendingLine(Test.Line);
    Test.BodyLine := -1;
    Inc(Index);
    if (Index >= Count) or (Tokens[Index].Kind <> TTokenKind.Ident) then
      Exit;
    Test.Method := Tokens[Index].Text;
    Inc(Index);
    IsTest := False;
    NotTest := False;
    for Attribute in Pending do
      case Attribute.Kind of
        TDUnitXAttribute.Test:
          // [Test(False)] schaltet den Test ab.
          if SameText(Attribute.FirstArgument, 'False') then
            NotTest := True
          else
            IsTest := True;
        TDUnitXAttribute.TestCase:
          begin
            IsTest := True;
            Test.Cases := Test.Cases + [Attribute.FirstArgument];
          end;
        TDUnitXAttribute.Ignore:
          Test.Ignored := True;
        TDUnitXAttribute.Setup, TDUnitXAttribute.TearDown, TDUnitXAttribute.SetupFixture,
        TDUnitXAttribute.TearDownFixture:
          NotTest := True;
      end;
    if APublished and (Length(Pending) = 0) then
      IsTest := True;
    if IsTest and not NotTest then
      AFixture.Tests := AFixture.Tests + [Test];
  end;

  /// <summary>Klasse ab Index (auf „class“ hinter „Name =“); liest bis zum passenden end.</summary>
  procedure ReadClass(const AName: string; ANameLine: Integer);
  var
    Candidate: TCandidate;
    Depth: Integer;
    Published, AfterClassWord: Boolean;
  begin
    Candidate := Default(TCandidate);
    Candidate.Fixture.Name := AName;
    Candidate.Fixture.Line := ANameLine;
    Candidate.Fixture.AttributeLine := FirstPendingLine(ANameLine);
    Candidate.HasFixtureAttribute := HasPending(TDUnitXAttribute.TestFixture);
    Pending := nil;
    Inc(Index);
    // Vorwärtsdeklaration, Klassenreferenz, class helper ohne Rumpf.
    if (Index < Count) and (IsSym(Tokens[Index], ';') or IsWord(Tokens[Index], 'of')) then
      Exit;
    while (Index < Count) and (IsWord(Tokens[Index], 'sealed') or IsWord(Tokens[Index], 'abstract')) do
      Inc(Index);
    if (Index < Count) and IsSym(Tokens[Index], '(') then
      SkipGroup('(', ')');
    // „TFoo = class(TBar);“ ohne Rumpf.
    if (Index < Count) and IsSym(Tokens[Index], ';') then
      Exit;
    // Ohne Sichtbarkeit sind Methoden mit {$M+} published; DUnitX-Fixtures haben das selten: wie public.
    Published := False;
    Depth := 1;
    AfterClassWord := False;
    while (Index < Count) and (Depth > 0) do
    begin
      if IsSym(Tokens[Index], '[') then
      begin
        ReadAttributes;
        Continue;
      end;
      if IsWord(Tokens[Index], 'end') then
      begin
        Dec(Depth);
        Pending := nil;
        Inc(Index);
        Continue;
      end;
      if IsWord(Tokens[Index], 'record') or
        (IsSym(Peek(-1), '=') and (IsWord(Tokens[Index], 'class') or IsWord(Tokens[Index], 'interface')) and
        not IsSym(Peek(1), ';') and not IsWord(Peek(1), 'of')) then
      begin
        Inc(Depth);
        Inc(Index);
        Continue;
      end;
      if (Depth = 1) and IsVisibility(Tokens[Index]) then
      begin
        Published := IsWord(Tokens[Index], 'published');
        Pending := nil;
        Inc(Index);
        Continue;
      end;
      if (Depth = 1) and IsWord(Tokens[Index], 'class') then
      begin
        // class procedure/function: Klassenmethoden sind keine Tests.
        AfterClassWord := True;
        Inc(Index);
        Continue;
      end;
      if (Depth = 1) and (IsWord(Tokens[Index], 'procedure') or IsWord(Tokens[Index], 'function')) then
      begin
        if AfterClassWord then
          Inc(Index)
        else
          ReadMethod(Candidate.Fixture, Published);
        AfterClassWord := False;
        Pending := nil;
        Continue;
      end;
      // Alles andere zwischen Attribut und Methode (Feld, Eigenschaft, Parameter): die Attribute gehören nicht
      // zu einer Methode.
      AfterClassWord := False;
      Pending := nil;
      Inc(Index);
    end;
    Candidates := Candidates + [Candidate];
  end;

  /// <summary>„procedure TFoo.Bar“ im implementation-Teil: Zeile merken.</summary>
  procedure ReadBody;
  var
    Line, CandidateIndex, TestIndex: Integer;
    ClassName, Method: string;
  begin
    Line := Tokens[Index].Line;
    Inc(Index);
    if (Index + 2 >= Count) or (Tokens[Index].Kind <> TTokenKind.Ident) or not IsSym(Tokens[Index + 1], '.') or
      (Tokens[Index + 2].Kind <> TTokenKind.Ident) then
      Exit;
    ClassName := Tokens[Index].Text;
    Method := Tokens[Index + 2].Text;
    Inc(Index, 3);
    for CandidateIndex := 0 to High(Candidates) do
      if SameText(Candidates[CandidateIndex].Fixture.Name, ClassName) then
        for TestIndex := 0 to High(Candidates[CandidateIndex].Fixture.Tests) do
          if SameText(Candidates[CandidateIndex].Fixture.Tests[TestIndex].Method, Method) and
            (Candidates[CandidateIndex].Fixture.Tests[TestIndex].BodyLine < 0) then
            Candidates[CandidateIndex].Fixture.Tests[TestIndex].BodyLine := Line;
  end;

var
  Candidate: TCandidate;
  Name: string;
  NameLine: Integer;
  IsRegistered: Boolean;
begin
  Result := Default(TDUnitXUnit);
  Result.Fixtures := nil;
  Tokens := Tokenize(ALines);
  Count := Length(Tokens);
  Candidates := nil;
  Registered := nil;
  Pending := nil;
  InImplementation := False;
  Index := 0;
  while Index < Count do
  begin
    if (Result.UnitName = '') and (IsWord(Tokens[Index], 'unit') or IsWord(Tokens[Index], 'program')) and
      (Index = 0) then
    begin
      Inc(Index);
      Result.UnitName := DottedName;
      Continue;
    end;
    if IsWord(Tokens[Index], 'implementation') then
    begin
      InImplementation := True;
      Pending := nil;
      Inc(Index);
      Continue;
    end;
    if IsSym(Tokens[Index], '[') and (IsSym(Peek(-1), ';') or IsSym(Peek(-1), ']') or IsWord(Peek(-1), 'type')) then
    begin
      ReadAttributes;
      Continue;
    end;
    // RegisterTestFixture(TFoo)
    if IsWord(Tokens[Index], 'RegisterTestFixture') and IsSym(Peek(1), '(') and
      (Peek(2).Kind = TTokenKind.Ident) then
    begin
      Registered := Registered + [Peek(2).Text];
      Inc(Index, 3);
      Continue;
    end;
    // TFoo = class …
    if (Tokens[Index].Kind = TTokenKind.Ident) and IsSym(Peek(1), '=') and IsWord(Peek(2), 'class') then
    begin
      Name := Tokens[Index].Text;
      NameLine := Tokens[Index].Line;
      Inc(Index, 2);
      ReadClass(Name, NameLine);
      Continue;
    end;
    if InImplementation and (IsWord(Tokens[Index], 'procedure') or IsWord(Tokens[Index], 'function')) and
      not IsWord(Peek(-1), 'class') then
    begin
      ReadBody;
      Pending := nil;
      Continue;
    end;
    // Generische Fixtures (TFoo<T> = class) und alles andere: Attribute gelten nicht mehr.
    if not IsWord(Tokens[Index], 'type') then
      Pending := nil;
    Inc(Index);
  end;
  for Candidate in Candidates do
  begin
    IsRegistered := False;
    for Name in Registered do
      if SameText(Name, Candidate.Fixture.Name) then
        IsRegistered := True;
    if Candidate.HasFixtureAttribute or IsRegistered then
      Result.Fixtures := Result.Fixtures + [Candidate.Fixture];
  end;
end;

{ TDUnitXCommandLine }

class function TDUnitXCommandLine.TestName(const AUnitName, AFixture, AMethod: string): string;
begin
  Result := AFixture;
  if AUnitName <> '' then
    Result := AUnitName + '.' + Result;
  if AMethod <> '' then
    Result := Result + '.' + AMethod;
end;

class function TDUnitXCommandLine.Arguments(const AResultFile: string; const ATests: TArray<string>): TArray<string>;
var
  Run: string;
  Test: string;
begin
  // Nur Optionen, die alle DUnitX-Fassungen seit RAD Studio 10 kennen; eine unbekannte Option lässt das
  // Testprogramm ohne Lauf enden (TDUnitX.CheckCommandLine).
  Result := ['--exitbehavior:Continue', '--xmlfile:' + AResultFile];
  Run := '';
  for Test in ATests do
    if Test <> '' then
    begin
      if Run <> '' then
        Run := Run + ',';
      Run := Run + Test;
    end;
  if (Run <> '') and (Length(Run) <= MaxRunLength) then
    Result := Result + ['--run:' + Run];
end;

end.
