unit Argus.Common.Editing.SqlText;

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
    /// <summary>Namen aus AName.ParamByName('X'), auch über .Params bzw. .Parameters, ohne Doppelte.</summary>
    class function AssignedParams(const AText, AName: string): TArray<string>; static;
    /// <summary>Namen aus AItems, die in AOf fehlen (ohne Groß-/Kleinschreibung).</summary>
    class function Missing(const AItems, AOf: TArray<string>): TArray<string>; static;
  end;

implementation

uses
  System.StrUtils,
  Argus.Common.Pascal.Contract,
  Argus.Common.Pascal.Lexer,
  Argus.Common.Editing.StringLiterals,
  Argus.Common.Dfm.Contract,
  Argus.Common.Dfm.Parser;

type
  TTokens = TArray<TPascalToken>;

function IsWordChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (Ord(C) > 127);
end;

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
    if Token.Kind <> TPascalTokenKind.Comment then
      Result := Result + [Token];
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
      Exit(False);
    Inc(Index);
    if Rest <> '' then
    begin
      if (Index > High(ATokens)) or (ATokens[Index].Text <> '.') then
        Exit(False);
      Inc(Index);
    end;
    Dot := Pos('.', Rest);
  end;
  // Kein Teil eines längeren Namens wie DM.Q oder Q2.
  if (AIndex > 0) and (ATokens[AIndex - 1].Text = '.') then
    Exit(False);
  AIndex := Index;
  Result := True;
end;

/// <summary>Ist ATokens[AIndex] das Wort AText? Dann weiter.</summary>
function Take(const ATokens: TTokens; var AIndex: Integer; const AText: string): Boolean;
begin
  Result := (AIndex <= High(ATokens)) and SameText(ATokens[AIndex].Text, AText);
  if Result then
    Inc(AIndex);
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
      Exit;
    if ATokens[AIndex].Text = '(' then
      Inc(Depth)
    else if ATokens[AIndex].Text = ')' then
      Dec(Depth);
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
        Inc(Index);
    end
    else if (ASql[Index] = '-') and (Index < Length(ASql)) and (ASql[Index + 1] = '-') then
    begin
      while (Index <= Length(ASql)) and not CharInSet(ASql[Index], [#10, #13]) do
        Inc(Index);
    end
    else if (ASql[Index] = ':') and (Index < Length(ASql)) and (ASql[Index + 1] = ':') then
      Inc(Index)
    else if (ASql[Index] = ':') and ((Index = 1) or not IsWordChar(ASql[Index - 1])) and
      (Index < Length(ASql)) and IsWordChar(ASql[Index + 1]) then
    begin
      Start := Index + 1;
      while (Index < Length(ASql)) and IsWordChar(ASql[Index + 1]) do
        Inc(Index);
      Name := Copy(ASql, Start, Index - Start + 1);
      if not Contains(Result, Name) then
        Result := Result + [Name];
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
      Inc(Index);
    if Index > Length(Sql) then
      Break;
    Start := Index;
    while (Index <= Length(Sql)) and (Sql[Index] > ' ') do
    begin
      if CharInSet(Sql[Index], ['''', '"']) then
      begin
        Quote := Sql[Index];
        Inc(Index);
        while (Index <= Length(Sql)) and (Sql[Index] <> Quote) do
          Inc(Index);
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
      BreakHere := (Index < High(Words)) and SameText(Words[Index + 1], 'by');
    if MatchStr(Word, JoinKinds) and not ((Index > 0) and MatchText(Words[Index - 1], JoinKinds)) then
    begin
      Next := Index + 1;
      while (Next <= High(Words)) and MatchText(Words[Next], JoinKinds) do
        Inc(Next);
      BreakHere := (Next <= High(Words)) and SameText(Words[Next], 'join');
    end;
    if BreakHere and (Line <> '') then
    begin
      Result := Result + [Line];
      Line := '';
    end;
    if Line = '' then
      Line := Words[Index]
    else
      Line := Line + ' ' + Words[Index];
  end;
  if Line <> '' then
    Result := Result + [Line];
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
          Result := Plain;
      end
      else if Take(Tokens, Cursor, 'Add') and Take(Tokens, Cursor, '(') then
      begin
        if TStringLiterals.PlainText(ExpressionUntil(Tokens, Cursor, ')'), Plain) then
          if Result = '' then
            Result := Plain
          else
            Result := Result + #13#10 + Plain;
      end
      else if Take(Tokens, Cursor, 'Clear') then
        Result := '';
      Index := Cursor;
    end
    else
      Inc(Index);
  end;
end;

function FindObject(AObject: TDfmObject; const AName: string): TDfmObject;
var
  Child: TDfmObject;
begin
  if SameText(AObject.Name, AName) then
    Exit(AObject);
  for Child in AObject.Children do
  begin
    Result := FindObject(Child, AName);
    if Result <> nil then
      Exit;
  end;
  Result := nil;
end;

class function TSqlText.FromForm(const AFormText, AName: string): string;
var
  Document: TDfmDocument;
  Found: TDfmObject;
  Prop: TDfmProperty;
  Value, Line, Plain: string;
  Continued: Boolean;
  Rest: string;
  Separator: Integer;
begin
  Result := '';
  // Name ohne Datenmodul-Präfix: DM.Q steht in der DFM als Q.
  Document := TDfmParser.Parse(AFormText);
  try
    if Document.Root = nil then
      Exit;
    Found := FindObject(Document.Root, Copy(AName, LastDelimiter('.', AName) + 1, MaxInt));
    if Found = nil then
      Exit;
    for Prop in Found.Properties do
      if SameText(Prop.Name, 'SQL.Strings') or SameText(Prop.Name, 'CommandText') then
      begin
        Value := Trim(Prop.Value);
        if StartsStr('(', Value) and EndsStr(')', Value) then
          Value := Copy(Value, 2, Length(Value) - 2);
        Continued := True;
        Rest := StringReplace(Value, #13#10, #10, [rfReplaceAll]) + #10;
        Separator := Pos(#10, Rest);
        while Separator > 0 do
        begin
          Line := Trim(Copy(Rest, 1, Separator - 1));
          Delete(Rest, 1, Separator);
          Separator := Pos(#10, Rest);
          if Line = '' then
            Continue;
          if not TStringLiterals.PlainText(Line, Plain) then
            Exit('');
          if not Continued then
            Result := Result + #13#10;
          Result := Result + Plain;
          // Lange DFM-Zeilen setzen sich mit "+" in der nächsten fort.
          Continued := EndsStr('+', Line);
        end;
        Exit;
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
      Continue;
    if (Take(Tokens, Cursor, 'Params') or Take(Tokens, Cursor, 'Parameters')) and not Take(Tokens, Cursor, '.') then
      Continue;
    if Take(Tokens, Cursor, 'ParamByName') and Take(Tokens, Cursor, '(') and (Cursor <= High(Tokens)) and
      (Tokens[Cursor].Kind = TPascalTokenKind.StringLiteral) and
      TStringLiterals.PlainText(Tokens[Cursor].Text, Name) and not Contains(Result, Name) then
      Result := Result + [Name];
  end;
end;

class function TSqlText.Missing(const AItems, AOf: TArray<string>): TArray<string>;
var
  Item: string;
begin
  Result := nil;
  for Item in AItems do
    if not Contains(AOf, Item) then
      Result := Result + [Item];
end;

end.
