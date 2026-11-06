unit Atlas.Common.Editing.SqlText;

// SQL-Text für die Datenbank-Schnellbefehle (#302), ohne Befehlsbezug:
// Parameter (:Name) finden, lange Abfragen auf Zeilen verteilen, den SQL-Text
// einer Query aus Unit oder Formulardatei lesen und vorhandene
// ParamByName-Aufrufe sammeln.

interface

uses
  System.SysUtils;

type
  TSqlText = class
  public
    /// <summary>Parameter (:Name) in Reihenfolge, ohne Doppelte; nicht in Strings, Kommentaren
    /// und bei "::" (Typumwandlung in PostgreSQL).</summary>
    class function Params(const ASql: string): TArray<string>; static;
    /// <summary>ASql in Zeilen vor from, where, and, join, order by usw.; bis AMaxLength eine Zeile.</summary>
    class function Layout(const ASql: string; AMaxLength: Integer): TArray<string>; static;
    /// <summary>SQL, das AText AName zuweist (AName.SQL.Text := … und AName.SQL.Add(…)); '' ohne.</summary>
    class function FromSource(const AText, AName: string): string; static;
    /// <summary>SQL.Strings bzw. CommandText der Komponente AName in der Formulardatei; '' ohne.</summary>
    class function FromForm(const AFormText, AName: string): string; static;
    /// <summary>Text eines SQL-Werts der Formulardatei: ('Zeile' 'Zeile') bzw. 'Text', lange Zeilen mit "+"
    /// fortgesetzt; False, wenn der Wert etwas anderes als Literale enthält.</summary>
    class function FormValue(const AValue: string; out AText: string): Boolean; static;
    /// <summary>Namen aus AName.ParamByName('X'), auch über .Params bzw. .Parameters, ohne Doppelte.</summary>
    class function AssignedParams(const AText, AName: string): TArray<string>; static;
    /// <summary>Namen aus AItems, die in AOf fehlen (ohne Groß-/Kleinschreibung).</summary>
    class function Missing(const AItems, AOf: TArray<string>): TArray<string>; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.StringLiterals,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Text.Chars;

type
  TTokens = TArray<TPascalToken>;

function Contains(const AItems: TArray<string>; const AName: string): Boolean;
begin
  Result := IndexText(AName, AItems) >= 0;
end;

/// <summary>Tokens ohne Kommentare.</summary>
function CodeTokens(const AText: string): TTokens;
var
  mToken: TPascalToken;
begin
  Result := nil;
  for mToken in TPascalLexer.Tokenize(AText) do
  begin
    if mToken.Kind <> TPascalTokenKind.Comment then
    begin
      Result := Result + [mToken];
    end;
  end;
end;

/// <summary>Stehen ab AIndex die Tokens von AName (mit Punkten)? AIndex zeigt danach hinter den Namen.</summary>
function MatchName(const ATokens: TTokens; var AIndex: Integer; const AName: string): Boolean;
var
  mRest, mPart: string;
  mIndex, mDot: Integer;
begin
  mIndex := AIndex;
  mRest := AName + '.';
  mDot := Pos('.', mRest);
  while mDot > 0 do
  begin
    mPart := Copy(mRest, 1, mDot - 1);
    Delete(mRest, 1, mDot);
    if (mIndex > High(ATokens)) or not SameText(ATokens[mIndex].Text, mPart) then
    begin
      Exit(False);
    end;
    Inc(mIndex);
    if mRest <> '' then
    begin
      if (mIndex > High(ATokens)) or (ATokens[mIndex].Text <> '.') then
      begin
        Exit(False);
      end;
      Inc(mIndex);
    end;
    mDot := Pos('.', mRest);
  end;
  // Kein Teil eines längeren Namens wie DM.Q oder Q2.
  if (AIndex > 0) and (ATokens[AIndex - 1].Text = '.') then
  begin
    Exit(False);
  end;
  AIndex := mIndex;
  Result := True;
end;

/// <summary>Ist ATokens[AIndex] das Wort AText? Dann weiter.</summary>
function Take(const ATokens: TTokens; var AIndex: Integer; const AText: string): Boolean;
begin
  Result := (AIndex <= High(ATokens)) and SameText(ATokens[AIndex].Text, AText);
  if Result then
  begin
    Inc(AIndex);
  end;
end;

/// <summary>Text der Tokens ab AIndex bis vor ein Token AStop auf Klammerebene 0.</summary>
function ExpressionUntil(const ATokens: TTokens; var AIndex: Integer; const AStop: string): string;
var
  mDepth: Integer;
begin
  Result := '';
  mDepth := 0;
  while AIndex <= High(ATokens) do
  begin
    if (mDepth = 0) and (ATokens[AIndex].Text = AStop) then
    begin
      Exit;
    end;
    if ATokens[AIndex].Text = '(' then
    begin
      Inc(mDepth);
    end
    else if ATokens[AIndex].Text = ')' then
    begin
      Dec(mDepth);
    end;
    Result := Result + ' ' + ATokens[AIndex].Text;
    Inc(AIndex);
  end;
end;

/// <summary>Steht an AIndex ein Anführungszeichen, geht AIndex auf das schließende (bzw. hinter das Ende).
/// </summary>
procedure SkipQuoted(const ASql: string; var AIndex: Integer);
var
  mQuote: Char;
begin
  if not CharInSet(ASql[AIndex], ['''', '"']) then
  begin
    Exit;
  end;
  mQuote := ASql[AIndex];
  Inc(AIndex);
  while (AIndex <= Length(ASql)) and (ASql[AIndex] <> mQuote) do
  begin
    Inc(AIndex);
  end;
end;

/// <summary>Stehen an AIndex zwei gleiche Zeichen AChar (-- bzw. ::)?</summary>
function IsDouble(const ASql: string; AIndex: Integer; AChar: Char): Boolean;
begin
  Result := (ASql[AIndex] = AChar) and (AIndex < Length(ASql)) and (ASql[AIndex + 1] = AChar);
end;

/// <summary>Beginnt an AIndex ein Parameter :Name (nicht mitten in einem Bezeichner)?</summary>
function IsParamStart(const ASql: string; AIndex: Integer): Boolean;
begin
  Result := (ASql[AIndex] = ':') and ((AIndex = 1) or not TTextChars.IsIdentChar(ASql[AIndex - 1])) and
    (AIndex < Length(ASql)) and TTextChars.IsIdentChar(ASql[AIndex + 1]);
end;

/// <summary>Name des Parameters, dessen Doppelpunkt an AIndex steht; AIndex steht danach auf dem letzten Zeichen.
/// </summary>
function ReadParam(const ASql: string; var AIndex: Integer): string;
var
  mStart: Integer;
begin
  mStart := AIndex + 1;
  while (AIndex < Length(ASql)) and TTextChars.IsIdentChar(ASql[AIndex + 1]) do
  begin
    Inc(AIndex);
  end;
  Result := Copy(ASql, mStart, AIndex - mStart + 1);
end;

{ TSqlText }

class function TSqlText.Params(const ASql: string): TArray<string>;
var
  mIndex: Integer;
  mName: string;
begin
  Result := nil;
  mIndex := 1;
  while mIndex <= Length(ASql) do
  begin
    if CharInSet(ASql[mIndex], ['''', '"']) then
    begin
      SkipQuoted(ASql, mIndex);
    end
    else if IsDouble(ASql, mIndex, '-') then
    begin
      while (mIndex <= Length(ASql)) and not CharInSet(ASql[mIndex], [#10, #13]) do
      begin
        Inc(mIndex);
      end;
    end
    else if IsDouble(ASql, mIndex, ':') then
    begin
      Inc(mIndex);
    end
    else if IsParamStart(ASql, mIndex) then
    begin
      mName := ReadParam(ASql, mIndex);
      if not Contains(Result, mName) then
      begin
        Result := Result + [mName];
      end;
    end;
    Inc(mIndex);
  end;
end;

/// <summary>ASql in Wörter teilen; Strings bleiben ein Wort.</summary>
function SqlWords(const ASql: string): TArray<string>;
var
  mIndex, mStart: Integer;
begin
  Result := nil;
  mIndex := 1;
  while mIndex <= Length(ASql) do
  begin
    while (mIndex <= Length(ASql)) and (ASql[mIndex] <= ' ') do
    begin
      Inc(mIndex);
    end;
    if mIndex > Length(ASql) then
    begin
      Break;
    end;
    mStart := mIndex;
    while (mIndex <= Length(ASql)) and (ASql[mIndex] > ' ') do
    begin
      SkipQuoted(ASql, mIndex);
      Inc(mIndex);
    end;
    Result := Result + [Copy(ASql, mStart, mIndex - mStart)];
  end;
end;

const
  cSqlBreaks: array[0..8] of string = ('from', 'where', 'and', 'or', 'having', 'union', 'values', 'set', 'join');
  cJoinKinds: array[0..5] of string = ('inner', 'left', 'right', 'full', 'cross', 'outer');

/// <summary>Folgt auf die Join-Art an AIndex (inner, left outer …) ein join?</summary>
function JoinFollows(const AWords: TArray<string>; AIndex: Integer): Boolean;
var
  mNext: Integer;
begin
  mNext := AIndex + 1;
  while (mNext <= High(AWords)) and MatchText(AWords[mNext], cJoinKinds) do
  begin
    Inc(mNext);
  end;
  Result := (mNext <= High(AWords)) and SameText(AWords[mNext], 'join');
end;

/// <summary>Beginnt mit dem Wort an AIndex eine neue Zeile (from, where, order by, left join …)?</summary>
function BreaksBefore(const AWords: TArray<string>; AIndex: Integer): Boolean;
var
  mWord: string;
  mAfterJoinKind: Boolean;
begin
  mWord := LowerCase(AWords[AIndex]);
  mAfterJoinKind := (AIndex > 0) and MatchText(AWords[AIndex - 1], cJoinKinds);
  Result := MatchStr(mWord, cSqlBreaks) and not ((mWord = 'join') and mAfterJoinKind);
  if MatchStr(mWord, ['order', 'group']) then
  begin
    Result := (AIndex < High(AWords)) and SameText(AWords[AIndex + 1], 'by');
  end;
  if MatchStr(mWord, cJoinKinds) and not mAfterJoinKind then
  begin
    Result := JoinFollows(AWords, AIndex);
  end;
end;

class function TSqlText.Layout(const ASql: string; AMaxLength: Integer): TArray<string>;
var
  mWords: TArray<string>;
  mIndex: Integer;
  mLine, mSql: string;
begin
  mSql := Trim(ASql);
  if Length(mSql) <= AMaxLength then
  begin
    Result := [mSql];
    Exit;
  end;
  mWords := SqlWords(mSql);
  Result := nil;
  mLine := '';
  for mIndex := 0 to High(mWords) do
  begin
    if BreaksBefore(mWords, mIndex) and (mLine <> '') then
    begin
      Result := Result + [mLine];
      mLine := '';
    end;
    if mLine <> '' then
    begin
      mLine := mLine + ' ';
    end;
    mLine := mLine + mWords[mIndex];
  end;
  if mLine <> '' then
  begin
    Result := Result + [mLine];
  end;
end;

/// <summary>Wertet die Anweisung hinter "Name.SQL." ab ACursor aus: Text := …, Add(…) oder Clear.</summary>
procedure ApplySqlCall(const ATokens: TTokens; var ACursor: Integer; var AResult: string);
var
  mPlain: string;
begin
  if Take(ATokens, ACursor, 'Text') and Take(ATokens, ACursor, ':=') then
  begin
    if TStringLiterals.PlainText(ExpressionUntil(ATokens, ACursor, ';'), mPlain) then
    begin
      AResult := mPlain;
    end;
  end
  else if Take(ATokens, ACursor, 'Add') and Take(ATokens, ACursor, '(') then
  begin
    if TStringLiterals.PlainText(ExpressionUntil(ATokens, ACursor, ')'), mPlain) then
    begin
      if AResult <> '' then
      begin
        AResult := AResult + #13#10;
      end;
      AResult := AResult + mPlain;
    end;
  end
  else if Take(ATokens, ACursor, 'Clear') then
  begin
    AResult := '';
  end;
end;

class function TSqlText.FromSource(const AText, AName: string): string;
var
  mTokens: TTokens;
  mIndex, mCursor: Integer;
begin
  Result := '';
  mTokens := CodeTokens(AText);
  mIndex := 0;
  while mIndex <= High(mTokens) do
  begin
    mCursor := mIndex;
    if MatchName(mTokens, mCursor, AName) and Take(mTokens, mCursor, '.') and Take(mTokens, mCursor, 'SQL') and
      Take(mTokens, mCursor, '.') then
    begin
      ApplySqlCall(mTokens, mCursor, Result);
      mIndex := mCursor;
    end
    else
    begin
      Inc(mIndex);
    end;
  end;
end;

function FindObject(AObject: TDfmObject; const AName: string): TDfmObject;
var
  mChild: TDfmObject;
begin
  if SameText(AObject.Name, AName) then
  begin
    Exit(AObject);
  end;
  for mChild in AObject.Children do
  begin
    Result := FindObject(mChild, AName);
    if Result <> nil then
    begin
      Exit;
    end;
  end;
  Result := nil;
end;

class function TSqlText.FormValue(const AValue: string; out AText: string): Boolean;
var
  mValue, mLine, mPlain, mRest: string;
  mContinued: Boolean;
  mSeparator: Integer;
begin
  AText := '';
  mValue := Trim(AValue);
  if StartsStr('(', mValue) and EndsStr(')', mValue) then
  begin
    mValue := Copy(mValue, 2, Length(mValue) - 2);
  end;
  mContinued := True;
  mRest := StringReplace(mValue, #13#10, #10, [rfReplaceAll]) + #10;
  mSeparator := Pos(#10, mRest);
  while mSeparator > 0 do
  begin
    mLine := Trim(Copy(mRest, 1, mSeparator - 1));
    Delete(mRest, 1, mSeparator);
    mSeparator := Pos(#10, mRest);
    if mLine = '' then
    begin
      Continue;
    end;
    if not TStringLiterals.PlainText(mLine, mPlain) then
    begin
      AText := '';
      Exit(False);
    end;
    if not mContinued then
    begin
      AText := AText + #13#10;
    end;
    AText := AText + mPlain;
    // Lange DFM-Zeilen setzen sich mit "+" in der nächsten fort.
    mContinued := EndsStr('+', mLine);
  end;
  Result := True;
end;

class function TSqlText.FromForm(const AFormText, AName: string): string;
var
  mDocument: TDfmDocument;
  mFound: TDfmObject;
  mProp: TDfmProperty;
begin
  Result := '';
  // Name ohne Datenmodul-Präfix: DM.Q steht in der DFM als Q.
  mDocument := TDfmParser.Parse(AFormText);
  try
    if mDocument.Root = nil then
    begin
      Exit;
    end;
    mFound := FindObject(mDocument.Root, Copy(AName, LastDelimiter('.', AName) + 1, MaxInt));
    if mFound = nil then
    begin
      Exit;
    end;
    for mProp in mFound.Properties do
    begin
      if SameText(mProp.Name, 'SQL.Strings') or SameText(mProp.Name, 'CommandText') then
      begin
        FormValue(mProp.Value, Result);
        Exit;
      end;
    end;
  finally
    mDocument.Free;
  end;
end;

/// <summary>Text des String-Literals an AIndex; False, wenn dort keines steht.</summary>
function LiteralAt(const ATokens: TTokens; AIndex: Integer; out AText: string): Boolean;
begin
  AText := '';
  Result := (AIndex <= High(ATokens)) and (ATokens[AIndex].Kind = TPascalTokenKind.StringLiteral) and
    TStringLiterals.PlainText(ATokens[AIndex].Text, AText);
end;

class function TSqlText.AssignedParams(const AText, AName: string): TArray<string>;
var
  mTokens: TTokens;
  mIndex, mCursor: Integer;
  mName: string;
begin
  Result := nil;
  mTokens := CodeTokens(AText);
  for mIndex := 0 to High(mTokens) do
  begin
    mCursor := mIndex;
    if not (MatchName(mTokens, mCursor, AName) and Take(mTokens, mCursor, '.')) then
    begin
      Continue;
    end;
    if (Take(mTokens, mCursor, 'Params') or Take(mTokens, mCursor, 'Parameters')) and not Take(mTokens, mCursor, '.') then
    begin
      Continue;
    end;
    if Take(mTokens, mCursor, 'ParamByName') and Take(mTokens, mCursor, '(') and LiteralAt(mTokens, mCursor, mName) and
      not Contains(Result, mName) then
    begin
      Result := Result + [mName];
    end;
  end;
end;

class function TSqlText.Missing(const AItems, AOf: TArray<string>): TArray<string>;
var
  mItem: string;
begin
  Result := nil;
  for mItem in AItems do
  begin
    if not Contains(AOf, mItem) then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

end.
