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

{ TSqlText }

class function TSqlText.Params(const ASql: string): TArray<string>;
var
  Index, Start: Integer;
  Quote: Char;
  Name: string;
begin
  Result := nil;
  Index := 1;
  while Index <= Length(ASql) do
  begin
    if CharInSet(ASql[Index], ['''', '"']) then
    begin
      Quote := ASql[Index];
      Inc(Index);
      while (Index <= Length(ASql)) and (ASql[Index] <> Quote) do
      begin
        Inc(Index);
      end;
    end
    else if (ASql[Index] = '-') and (Index < Length(ASql)) and (ASql[Index + 1] = '-') then
    begin
      while (Index <= Length(ASql)) and not CharInSet(ASql[Index], [#10, #13]) do
      begin
        Inc(Index);
      end;
    end
    else if (ASql[Index] = ':') and (Index < Length(ASql)) and (ASql[Index + 1] = ':') then
    begin
      Inc(Index);
    end
    else if (ASql[Index] = ':') and ((Index = 1) or not TTextChars.IsIdentChar(ASql[Index - 1])) and
      (Index < Length(ASql)) and TTextChars.IsIdentChar(ASql[Index + 1]) then
    begin
      Start := Index + 1;
      while (Index < Length(ASql)) and TTextChars.IsIdentChar(ASql[Index + 1]) do
      begin
        Inc(Index);
      end;
      Name := Copy(ASql, Start, Index - Start + 1);
      if not Contains(Result, Name) then
      begin
        Result := Result + [Name];
      end;
    end;
    Inc(Index);
  end;
end;

class function TSqlText.Layout(const ASql: string; AMaxLength: Integer): TArray<string>;
const
  Breaks: array[0..8] of string = ('from', 'where', 'and', 'or', 'having', 'union', 'values', 'set', 'join');
  JoinKinds: array[0..5] of string = ('inner', 'left', 'right', 'full', 'cross', 'outer');
var
  Words: TArray<string>;
  Index, Next: Integer;
  Word, Line, Sql: string;
  Quote: Char;
  Start: Integer;
  BreakHere: Boolean;
begin
  Sql := Trim(ASql);
  if Length(Sql) <= AMaxLength then
  begin
    Result := [Sql];
    Exit;
  end;
  // In Wörter teilen; Strings bleiben ein Wort.
  Words := nil;
  Index := 1;
  while Index <= Length(Sql) do
  begin
    while (Index <= Length(Sql)) and (Sql[Index] <= ' ') do
    begin
      Inc(Index);
    end;
    if Index > Length(Sql) then
    begin
      Break;
    end;
    Start := Index;
    while (Index <= Length(Sql)) and (Sql[Index] > ' ') do
    begin
      if CharInSet(Sql[Index], ['''', '"']) then
      begin
        Quote := Sql[Index];
        Inc(Index);
        while (Index <= Length(Sql)) and (Sql[Index] <> Quote) do
        begin
          Inc(Index);
        end;
      end;
      Inc(Index);
    end;
    Words := Words + [Copy(Sql, Start, Index - Start)];
  end;
  Result := nil;
  Line := '';
  for Index := 0 to High(Words) do
  begin
    Word := LowerCase(Words[Index]);
    BreakHere := MatchStr(Word, Breaks) and not ((Word = 'join') and (Index > 0) and
      MatchText(Words[Index - 1], JoinKinds));
    if MatchStr(Word, ['order', 'group']) then
    begin
      BreakHere := (Index < High(Words)) and SameText(Words[Index + 1], 'by');
    end;
    if MatchStr(Word, JoinKinds) and not ((Index > 0) and MatchText(Words[Index - 1], JoinKinds)) then
    begin
      Next := Index + 1;
      while (Next <= High(Words)) and MatchText(Words[Next], JoinKinds) do
      begin
        Inc(Next);
      end;
      BreakHere := (Next <= High(Words)) and SameText(Words[Next], 'join');
    end;
    if BreakHere and (Line <> '') then
    begin
      Result := Result + [Line];
      Line := '';
    end;
    if Line = '' then
    begin
      Line := Words[Index];
    end
    else
    begin
      Line := Line + ' ' + Words[Index];
    end;
  end;
  if Line <> '' then
  begin
    Result := Result + [Line];
  end;
end;

class function TSqlText.FromSource(const AText, AName: string): string;
var
  Tokens: TTokens;
  Index, Cursor: Integer;
  Plain: string;
begin
  Result := '';
  Tokens := CodeTokens(AText);
  Index := 0;
  while Index <= High(Tokens) do
  begin
    Cursor := Index;
    if MatchName(Tokens, Cursor, AName) and Take(Tokens, Cursor, '.') and Take(Tokens, Cursor, 'SQL') and
      Take(Tokens, Cursor, '.') then
    begin
      if Take(Tokens, Cursor, 'Text') and Take(Tokens, Cursor, ':=') then
      begin
        if TStringLiterals.PlainText(ExpressionUntil(Tokens, Cursor, ';'), Plain) then
        begin
          Result := Plain;
        end;
      end
      else if Take(Tokens, Cursor, 'Add') and Take(Tokens, Cursor, '(') then
      begin
        if TStringLiterals.PlainText(ExpressionUntil(Tokens, Cursor, ')'), Plain) then
        begin
          if Result = '' then
          begin
            Result := Plain;
          end
          else
          begin
            Result := Result + #13#10 + Plain;
          end;
        end;
      end
      else if Take(Tokens, Cursor, 'Clear') then
      begin
        Result := '';
      end;
      Index := Cursor;
    end
    else
    begin
      Inc(Index);
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
    if Take(Tokens, Cursor, 'ParamByName') and Take(Tokens, Cursor, '(') and (Cursor <= High(Tokens)) and
      (Tokens[Cursor].Kind = TPascalTokenKind.StringLiteral) and
      TStringLiterals.PlainText(Tokens[Cursor].Text, Name) and not Contains(Result, Name) then
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
