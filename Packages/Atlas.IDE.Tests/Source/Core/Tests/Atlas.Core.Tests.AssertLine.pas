unit Atlas.Core.Tests.AssertLine;

// Zeile eines fehlgeschlagenen Tests (#1771, tests.failureAtAssert), ohne VCL
// und Open Tools API, auch unter FPC prüfbar:
// - FromStackTrace: erster Eintrag des Stacktraces im Bericht, der die
//   Testunit nennt (Unit-Name oder Dateiname), und seine Zeile. Gelesen werden
//   die Formate von JclDebug („… (Line 42, "Rechner.Tests.pas" + 3)“),
//   madExcept („… Rechner.Tests 42 +3 TRechnerTests.Addiert“) und
//   „Datei.pas:42“ bzw. „Datei.pas(42)“. Die oberen Einträge gehören zu
//   DUnitX (Assert), der erste in der Testunit ist die auslösende Anweisung.
// - FromAsserts: Rückfall ohne Zeilen im Stacktrace. Im Rumpf des Tests
//   (Zeilen ohne Kommentare und Strings) die Aufrufe Assert.Xyz(…); nennt der
//   Bericht einen erwarteten Wert, gilt der eine Aufruf, dessen erstes
//   Argument dazu passt (Zahl, String-Literal, Text); bei mehreren passenden
//   keiner. Ohne passenden Wert gilt ein Fehlschlag (kein Abbruch durch eine
//   Ausnahme) an der einzigen Assert-Zeile des Rumpfs.
// - Statement: Zeichenbereich der Anweisung in der Zeile für die Wellenlinie.
// Zeilen sind 0-basiert; -1 = keine Zeile gefunden (Methodenkopf bleibt).

interface

uses
  Atlas.Text.DUnitX,
  Atlas.Text.TestResults;

type
  TAtlasAssertLine = class
  public
    /// <summary>Zeile (0-basiert) des ersten Eintrags von AStackTrace in der Unit AUnitName bzw. Datei AFileName;
    /// -1 ohne. ALineCount: Zeilen der Datei (größere Zeilen gelten nicht).</summary>
    class function FromStackTrace(const AStackTrace, AUnitName, AFileName: string; ALineCount: Integer): Integer;
      static;
    /// <summary>Rückfall über die Assert-Aufrufe der Zeilen AFirstLine bis ALastLine: der eine, dessen erstes
    /// Argument AExpected ist (AHasValues), sonst bei AFailed die einzige Assert-Zeile; -1 ohne eindeutige.</summary>
    class function FromAsserts(const ALines: TArray<string>; AFirstLine, ALastLine: Integer;
      const AExpected: string; AHasValues, AFailed: Boolean): Integer; static;
    /// <summary>Zeile des Fehlschlags ACase im Test der Unit AUnit (Text ALines, Datei AFileName): Stacktrace, sonst
    /// Assert-Aufrufe des Rumpfs; -1 ohne.</summary>
    class function Find(const ACase: TTestCaseResult; const AUnit: TDUnitXUnit; const ALines: TArray<string>;
      const AFileName: string): Integer; static;
    /// <summary>Erstes und letztes Zeichen (0-basiert, Ende exklusiv) der Anweisung in ALine: ohne Einrückung und
    /// Kommentar am Ende.</summary>
    class procedure Statement(const ALine: string; out AStart, AEnd: Integer); static;
    /// <summary>Gleicht der Text eines Arguments (Zahl, String-Literal) dem erwarteten Wert des Berichts?</summary>
    class function MatchesExpected(const AArgument, AExpected: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Atlas.Text.Chars;

const
  // Zeilenangabe von JclDebug ("(Line 42, …") und Beginn eines Assert-Aufrufs, klein geschrieben.
  cLinePrefix = 'line ';
  cAssertPrefix = 'assert.';

function IsDigits(const AText: string): Boolean;
var
  mChar: Char;
begin
  Result := AText <> '';
  for mChar in AText do
  begin
    if not CharInSet(mChar, ['0'..'9']) then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Ziffern ab APos (1-basiert) als Zahl; 0 ohne Ziffern.</summary>
function NumberAt(const AText: string; APos: Integer): Integer;
var
  mEnd: Integer;
begin
  mEnd := APos;
  while (mEnd <= Length(AText)) and CharInSet(AText[mEnd], ['0'..'9']) do
  begin
    Inc(mEnd);
  end;
  Result := StrToIntDef(Copy(AText, APos, mEnd - APos), 0);
end;

/// <summary>Position (1-basiert) von AName in AText als ganzes Wort (davor kein Bezeichnerzeichen und kein Punkt,
/// danach kein Bezeichnerzeichen); 0 ohne.</summary>
function WordPos(const AName, AText: string): Integer;
var
  mLower, mName: string;
  mFrom, mAfter: Integer;
begin
  Result := 0;
  if AName = '' then
  begin
    Exit;
  end;
  mLower := AnsiLowerCase(AText);
  mName := AnsiLowerCase(AName);
  mFrom := 1;
  repeat
    Result := Pos(mName, mLower, mFrom);
    if Result = 0 then
    begin
      Exit;
    end;
    mAfter := Result + Length(mName);
    if ((Result = 1) or not (TTextChars.IsIdentChar(AText[Result - 1]) or (AText[Result - 1] = '.'))) and
      ((mAfter > Length(AText)) or not TTextChars.IsIdentChar(AText[mAfter])) then
    begin
      Exit;
    end;
    mFrom := Result + 1;
  until False;
end;

/// <summary>Zeile (1-basiert) eines Eintrags; 0 ohne. AUnitAt/AFileAt: Fundstellen von Unit und Datei.</summary>
function LineOfEntry(const AEntry: string; AUnitAt, AFileAt, AUnitLength, AFileLength: Integer): Integer;
var
  mPos: Integer;
  mParts: TArray<string>;
  mRest: string;
begin
  // JclDebug: "(Line 42, ..." bzw. "Line 42".
  mPos := Pos(cLinePrefix, AnsiLowerCase(AEntry));
  if mPos > 0 then
  begin
    mPos := mPos + Length(cLinePrefix);
    if (mPos <= Length(AEntry)) and CharInSet(AEntry[mPos], ['0'..'9']) then
    begin
      Exit(NumberAt(AEntry, mPos));
    end;
  end;
  // Datei.pas:42 bzw. Datei.pas(42).
  if AFileAt > 0 then
  begin
    mPos := AFileAt + AFileLength;
    if (mPos < Length(AEntry)) and CharInSet(AEntry[mPos], [':', '(']) and
      CharInSet(AEntry[mPos + 1], ['0'..'9']) then
    begin
      Exit(NumberAt(AEntry, mPos + 1));
    end;
  end;
  // madExcept: Unit-Name, dann die Zeile als eigenes Wort.
  Result := 0;
  if AUnitAt > 0 then
  begin
    mRest := Trim(Copy(AEntry, AUnitAt + AUnitLength, MaxInt));
    mParts := mRest.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
    if (Length(mParts) > 0) and IsDigits(mParts[0]) then
    begin
      Result := StrToIntDef(mParts[0], 0);
    end;
  end;
end;

class function TAtlasAssertLine.FromStackTrace(const AStackTrace, AUnitName, AFileName: string;
  ALineCount: Integer): Integer;
var
  mEntry, mFile: string;
  mUnitAt, mFileAt, mLine: Integer;
begin
  Result := -1;
  // Dateiname ohne Ordner, mit \ oder / getrennt (Bericht von Windows, Prüfung auch unter Linux).
  mFile := Copy(AFileName, LastDelimiter('\/', AFileName) + 1, MaxInt);
  for mEntry in AStackTrace.Split([#10]) do
  begin
    mUnitAt := WordPos(AUnitName, mEntry);
    mFileAt := 0;
    if mFile <> '' then
    begin
      mFileAt := Pos(AnsiLowerCase(mFile), AnsiLowerCase(mEntry));
    end;
    if (mUnitAt = 0) and (mFileAt = 0) then
    begin
      Continue;
    end;
    // Erster Eintrag in der Testunit: hat er keine Zeile, sagt der Stacktrace nichts Genaueres.
    mLine := LineOfEntry(mEntry, mUnitAt, mFileAt, Length(AUnitName), Length(mFile));
    if (mLine >= 1) and (mLine <= ALineCount) then
    begin
      Result := mLine - 1;
    end;
    Exit;
  end;
end;

/// <summary>Folgt auf ALine[AIndex] das Zeichen AChar?</summary>
function NextIs(const ALine: string; AIndex: Integer; AChar: Char): Boolean;
begin
  Result := (AIndex < Length(ALine)) and (ALine[AIndex + 1] = AChar);
end;

/// <summary>Steht AIndex in einem offenen Kommentar { bzw. (*? Dann das Zeichen verbrauchen und sein Ende
/// erkennen.</summary>
function InComment(const ALine: string; var AIndex: Integer; var AInBrace, AInParen: Boolean): Boolean;
begin
  Result := AInBrace or AInParen;
  if AInBrace then
  begin
    AInBrace := ALine[AIndex] <> '}';
  end
  else if AInParen and (ALine[AIndex] = '*') and NextIs(ALine, AIndex, ')') then
  begin
    AInParen := False;
    Inc(AIndex);
  end;
end;

/// <summary>Beginnt bei AIndex ein Kommentar ({ ohne Direktive, (*, //)? ALineComment: Rest der Zeile.</summary>
function CommentStart(const ALine: string; var AIndex: Integer; var AInBrace, AInParen,
  ALineComment: Boolean): Boolean;
begin
  Result := True;
  if (ALine[AIndex] = '/') and NextIs(ALine, AIndex, '/') then
  begin
    ALineComment := True;
  end
  else if (ALine[AIndex] = '{') and not NextIs(ALine, AIndex, '$') then
  begin
    AInBrace := True;
  end
  else if (ALine[AIndex] = '(') and NextIs(ALine, AIndex, '*') then
  begin
    AInParen := True;
    Inc(AIndex);
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>Code einer Zeile ohne Kommentare; Strings bleiben. AInBrace/AInParen: offener Kommentar { bzw. (*
/// über Zeilen.</summary>
function CodeOf(const ALine: string; var AInBrace, AInParen: Boolean): string;
var
  mIndex: Integer;
  mInString, mLineComment: Boolean;
  mChar: Char;
begin
  Result := '';
  mInString := False;
  mLineComment := False;
  mIndex := 1;
  while mIndex <= Length(ALine) do
  begin
    mChar := ALine[mIndex];
    if mInString then
    begin
      Result := Result + mChar;
      mInString := mChar <> '''';
    end
    else if not InComment(ALine, mIndex, AInBrace, AInParen) then
    begin
      if not CommentStart(ALine, mIndex, AInBrace, AInParen, mLineComment) then
      begin
        Result := Result + mChar;
        mInString := mChar = '''';
      end
      else if mLineComment then
      begin
        Break;
      end;
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Position (1-basiert) eines Aufrufs Assert.Xyz( außerhalb von Strings; 0 ohne. AArgs: Text ab der
/// Klammer.</summary>
function AssertCall(const ACode: string; out AArgs: string): Integer;
var
  mIndex, mOpen: Integer;
  mInString: Boolean;
begin
  AArgs := '';
  mInString := False;
  for mIndex := 1 to Length(ACode) do
  begin
    if ACode[mIndex] = '''' then
    begin
      mInString := not mInString;
    end
    else if not mInString and SameText(Copy(ACode, mIndex, Length(cAssertPrefix)), cAssertPrefix) and
      ((mIndex = 1) or not (TTextChars.IsIdentChar(ACode[mIndex - 1]) or (ACode[mIndex - 1] = '.'))) then
    begin
      mOpen := Pos('(', ACode, mIndex);
      if mOpen > 0 then
      begin
        AArgs := Copy(ACode, mOpen + 1, MaxInt);
      end;
      Exit(mIndex);
    end;
  end;
  Result := 0;
end;

/// <summary>Erstes Argument bis zum Komma der obersten Ebene; '' ohne Komma in der Zeile.</summary>
function FirstArgument(const AArgs: string): string;
var
  mIndex, mDepth: Integer;
  mInString: Boolean;
begin
  mDepth := 0;
  mInString := False;
  for mIndex := 1 to Length(AArgs) do
  begin
    if AArgs[mIndex] = '''' then
    begin
      mInString := not mInString;
    end
    else if not mInString then
    begin
      if CharInSet(AArgs[mIndex], ['(', '[']) then
      begin
        Inc(mDepth);
      end
      else if CharInSet(AArgs[mIndex], [')', ']']) then
      begin
        Dec(mDepth);
      end
      else if (AArgs[mIndex] = ',') and (mDepth = 0) then
      begin
        Exit(Trim(Copy(AArgs, 1, mIndex - 1)));
      end;
    end;
  end;
  Result := '';
end;

/// <summary>Text ohne umschließende Anführungszeichen; '' im Literal wird '.</summary>
function Unquoted(const AText: string): string;
begin
  Result := Trim(AText);
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
  begin
    Result := StringReplace(Copy(Result, 2, Length(Result) - 2), '''''', '''', [rfReplaceAll]);
  end
  else if (Length(Result) >= 2) and (Result[1] = '"') and (Result[Length(Result)] = '"') then
  begin
    Result := Copy(Result, 2, Length(Result) - 2);
  end;
end;

class function TAtlasAssertLine.MatchesExpected(const AArgument, AExpected: string): Boolean;
var
  mFormat: TFormatSettings;
  mLeft, mRight: string;
  mA, mB: Double;
begin
  mLeft := Unquoted(AArgument);
  mRight := Unquoted(AExpected);
  if (mLeft = '') or (mRight = '') then
  begin
    Exit(False);
  end;
  if mLeft = mRight then
  begin
    Exit(True);
  end;
  mFormat := TFormatSettings.Invariant;
  Result := TryStrToFloat(mLeft, mA, mFormat) and TryStrToFloat(StringReplace(mRight, ',', '.', []), mB, mFormat) and
    SameValue(mA, mB);
end;

class function TAtlasAssertLine.FromAsserts(const ALines: TArray<string>; AFirstLine, ALastLine: Integer;
  const AExpected: string; AHasValues, AFailed: Boolean): Integer;
var
  mLine, mMatches, mAsserts, mOnly: Integer;
  mInBrace, mInParen: Boolean;
  mArgs: string;
begin
  Result := -1;
  mMatches := 0;
  mAsserts := 0;
  mOnly := -1;
  mInBrace := False;
  mInParen := False;
  for mLine := Max(0, AFirstLine) to Min(ALastLine, High(ALines)) do
  begin
    if AssertCall(CodeOf(ALines[mLine], mInBrace, mInParen), mArgs) = 0 then
    begin
      Continue;
    end;
    Inc(mAsserts);
    mOnly := mLine;
    if AHasValues and MatchesExpected(FirstArgument(mArgs), AExpected) then
    begin
      Inc(mMatches);
      Result := mLine;
    end;
  end;
  if mMatches = 1 then
  begin
    Exit;
  end;
  Result := -1;
  if (mMatches = 0) and AFailed and (mAsserts = 1) then
  begin
    Result := mOnly;
  end;
end;

class function TAtlasAssertLine.Find(const ACase: TTestCaseResult; const AUnit: TDUnitXUnit;
  const ALines: TArray<string>; const AFileName: string): Integer;
var
  mFixture, mTest: Integer;
  mItem: TDUnitXTest;
begin
  Result := FromStackTrace(ACase.StackTrace, ACase.UnitName, AFileName, Length(ALines));
  // Find meldet eine bekannte Fixture auch ohne die Methode (ATestIndex -1).
  if (Result >= 0) or not AUnit.Find(ACase.Fixture, ACase.Method, mFixture, mTest) or (mTest < 0) then
  begin
    Exit;
  end;
  mItem := AUnit.Fixtures[mFixture].Tests[mTest];
  if mItem.BodyLine >= 0 then
  begin
    Result := FromAsserts(ALines, mItem.BodyLine, mItem.EndLine, ACase.Expected, ACase.HasValues,
      ACase.Outcome = TTestOutcome.Failed);
  end;
end;

class procedure TAtlasAssertLine.Statement(const ALine: string; out AStart, AEnd: Integer);
var
  mInBrace, mInParen: Boolean;
  mCode: string;
begin
  AStart := 0;
  while (AStart < Length(ALine)) and CharInSet(ALine[AStart + 1], [' ', #9]) do
  begin
    Inc(AStart);
  end;
  mInBrace := False;
  mInParen := False;
  // Kommentar am Ende gehört nicht zur Anweisung; ein Kommentar mitten in der Zeile verschiebt nichts davor.
  mCode := TrimRight(CodeOf(ALine, mInBrace, mInParen));
  AEnd := Length(TrimRight(ALine));
  if (mCode <> '') and (Pos(Trim(mCode), ALine) = AStart + 1) then
  begin
    AEnd := AStart + Length(Trim(mCode));
  end;
end;

end.
