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
  Token: TPascalToken;
begin
  Result := nil;
  for Token in TPascalLexer.Tokenize(AText) do
  begin
    if Token.Kind <> TPascalTokenKind.Comment then
    begin
      Result := Result + [Token];
    end;
  end;
end;

/// <summary>Stehen ab AIndex die Tokens von AName (mit Punkten)? AIndex zeigt danach hinter den Namen.</summary>
function MatchName(const ATokens: TTokens; var AIndex: Integer; const AName: string): Boolean;
var
  Rest, Part: string;
  Index, Dot: Integer;
begin
  Index := AIndex;
  Rest := AName + '.';
  Dot := Pos('.', Rest);
  while Dot > 0 do
  begin
    Part := Copy(Rest, 1, Dot - 1);
    Delete(Rest, 1, Dot);
    if (Index > High(ATokens)) or not SameText(ATokens[Index].Text, Part) then
    begin
      Exit(False);
    end;
    Inc(Index);
    if Rest <> '' then
    begin
      if (Index > High(ATokens)) or (ATokens[Index].Text <> '.') then
      begin
        Exit(False);
      end;
      Inc(Index);
    end;
    Dot := Pos('.', Rest);
  end;
  // Kein Teil eines längeren Namens wie DM.Q oder Q2.
  if (AIndex > 0) and (ATokens[AIndex - 1].Text = '.') then
  begin
    Exit(False);
  end;
  AIndex := Index;
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
  Depth: Integer;
begin
  Result := '';
  Depth := 0;
  while AIndex <= High(ATokens) do
  begin
    if (Depth = 0) and (ATokens[AIndex].Text = AStop) then
    begin
      Exit;
    end;
    if ATokens[AIndex].Text = '(' then
    begin
      Inc(Depth);
    end
    else if ATokens[AIndex].Text = ')' then
    begin
      Dec(Depth);
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
  Child: TDfmObject;
begin
  if SameText(AObject.Name, AName) then
  begin
    Exit(AObject);
  end;
  for Child in AObject.Children do
  begin
    Result := FindObject(Child, AName);
    if Result <> nil then
    begin
      Exit;
    end;
  end;
  Result := nil;
end;

class function TSqlText.FormValue(const AValue: string; out AText: string): Boolean;
var
  Value, Line, Plain, Rest: string;
  Continued: Boolean;
  Separator: Integer;
begin
  AText := '';
  Value := Trim(AValue);
  if StartsStr('(', Value) and EndsStr(')', Value) then
  begin
    Value := Copy(Value, 2, Length(Value) - 2);
  end;
  Continued := True;
  Rest := StringReplace(Value, #13#10, #10, [rfReplaceAll]) + #10;
  Separator := Pos(#10, Rest);
  while Separator > 0 do
  begin
    Line := Trim(Copy(Rest, 1, Separator - 1));
    Delete(Rest, 1, Separator);
    Separator := Pos(#10, Rest);
    if Line = '' then
    begin
      Continue;
    end;
    if not TStringLiterals.PlainText(Line, Plain) then
    begin
      AText := '';
      Exit(False);
    end;
    if not Continued then
    begin
      AText := AText + #13#10;
    end;
    AText := AText + Plain;
    // Lange DFM-Zeilen setzen sich mit "+" in der nächsten fort.
    Continued := EndsStr('+', Line);
  end;
  Result := True;
end;

class function TSqlText.FromForm(const AFormText, AName: string): string;
var
  Document: TDfmDocument;
  Found: TDfmObject;
  Prop: TDfmProperty;
begin
  Result := '';
  // Name ohne Datenmodul-Präfix: DM.Q steht in der DFM als Q.
  Document := TDfmParser.Parse(AFormText);
  try
    if Document.Root = nil then
    begin
      Exit;
    end;
    Found := FindObject(Document.Root, Copy(AName, LastDelimiter('.', AName) + 1, MaxInt));
    if Found = nil then
    begin
      Exit;
    end;
    for Prop in Found.Properties do
    begin
      if SameText(Prop.Name, 'SQL.Strings') or SameText(Prop.Name, 'CommandText') then
      begin
        FormValue(Prop.Value, Result);
        Exit;
      end;
    end;
  finally
    Document.Free;
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
  Tokens: TTokens;
  Index, Cursor: Integer;
  Name: string;
begin
  Result := nil;
  Tokens := CodeTokens(AText);
  for Index := 0 to High(Tokens) do
  begin
    Cursor := Index;
    if not (MatchName(Tokens, Cursor, AName) and Take(Tokens, Cursor, '.')) then
    begin
      Continue;
    end;
    if (Take(Tokens, Cursor, 'Params') or Take(Tokens, Cursor, 'Parameters')) and not Take(Tokens, Cursor, '.') then
    begin
      Continue;
    end;
    if Take(Tokens, Cursor, 'ParamByName') and Take(Tokens, Cursor, '(') and LiteralAt(Tokens, Cursor, Name) and
      not Contains(Result, Name) then
    begin
      Result := Result + [Name];
    end;
  end;
end;

class function TSqlText.Missing(const AItems, AOf: TArray<string>): TArray<string>;
var
  Item: string;
begin
  Result := nil;
  for Item in AItems do
  begin
    if not Contains(AOf, Item) then
    begin
      Result := Result + [Item];
    end;
  end;
end;

end.
