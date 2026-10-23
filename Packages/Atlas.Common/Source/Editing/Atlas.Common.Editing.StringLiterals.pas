unit Atlas.Common.Editing.StringLiterals;

// Klartext und String-Literal umwandeln (#312), z. B. für SQL, HTML, JSON
// oder Meldungstexte:
//   - ToLiteral: Klartext wird zum Pascal-Literal, Hochkommas verdoppelt,
//     Steuerzeichen als #9 usw. Die Zeilen werden verkettet (Trenner nach
//     stringLiteral.lineBreak) oder als mehrzeiliger String ''' geschrieben
//     (ab Delphi 12, #109).
//   - PlainText: ein (auch verkettetes) Literal wird zum reinen Text ohne
//     Hochkommas, "+", sLineBreak und #13#10.
//   - LiteralAt: Bereich des verketteten Literals unter dem Cursor.
// Platzhalter wie :Nr oder %s bleiben unverändert. Dieselbe Zerlegung nutzen
// später /multiline (#303) und /sql (#302).

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract;

type
  TStringLiterals = class
  public const
    /// <summary>Zeilenende im Klartext (Zwischenablage unter Windows).</summary>
    PlainLineBreak = #13#10;
  public
    /// <summary>Mehrzeiliger String? Auto nur, wenn AVersion bekannt ist und ihn kennt.</summary>
    class function UseMultiline(AStyle: TStringLiteralStyle; const AVersion: string): Boolean; static;
    /// <summary>Eine Zeile als Literal: 'Kunde''s'#9'Wert'.</summary>
    class function Quote(const ALine: string): string; static;
    /// <summary>APlainText als Literal. Jede Ausgabezeile beginnt mit AIndent, die erste nur mit
    /// AIndentFirst. ALineEnd trennt die Ausgabezeilen.</summary>
    class function ToLiteral(const APlainText, AIndent: string; AIndentFirst, AMultiline: Boolean;
      ABreak: TStringLiteralBreak; AMaxLineLength: Integer; const ALineEnd: string): string; static;
    /// <summary>Text eines Literal-Ausdrucks; False, wenn er etwas anderes als Literale,
    /// Zeichenkonstanten, sLineBreak und + enthält.</summary>
    class function PlainText(const AExpression: string; out AText: string): Boolean; static;
    /// <summary>Bereich des (verketteten) Literals an APosition; False ohne.</summary>
    class function LiteralAt(const AText: string; const APosition: TTextPosition; out ARange: TTextRange): Boolean;
      static;
    /// <summary>Text in ARange, Zeilen mit #10 getrennt.</summary>
    class function TextOf(const AText: string; const ARange: TTextRange): string; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.LanguageFeatures,
  Atlas.Text.Lines;

{ TStringLiterals }

class function TStringLiterals.UseMultiline(AStyle: TStringLiteralStyle; const AVersion: string): Boolean;
begin
  case AStyle of
    TStringLiteralStyle.Multiline:
      Result := True;
    TStringLiteralStyle.Concat:
      Result := False;
  else
    Result := (TLanguageFeatures.ParseVersion(AVersion) > 0) and
      TLanguageFeatures.IsAvailable(TLanguageFeature.MultilineString, AVersion);
  end;
end;

class function TStringLiterals.Quote(const ALine: string): string;
var
  C: Char;
  InQuote: Boolean;
begin
  Result := '';
  InQuote := False;
  for C in ALine do
    if Ord(C) < 32 then
    begin
      if InQuote then
        Result := Result + '''';
      InQuote := False;
      Result := Result + '#' + IntToStr(Ord(C));
    end
    else
    begin
      if not InQuote then
        Result := Result + '''';
      InQuote := True;
      if C = '''' then
        Result := Result + ''''''
      else
        Result := Result + C;
    end;
  if InQuote then
    Result := Result + ''''
  else if Result = '' then
    Result := '''''';
end;

/// <summary>Mehrzeiliger String geht nur ohne ''' und ohne Steuerzeichen außer Tab.</summary>
function FitsMultiline(const ALines: TArray<string>): Boolean;
var
  Line: string;
  C: Char;
begin
  for Line in ALines do
  begin
    if Pos('''''''', Line) > 0 then
      Exit(False);
    for C in Line do
      if (Ord(C) < 32) and (C <> #9) then
        Exit(False);
  end;
  Result := True;
end;

/// <summary>ALine in Stücke, deren Literal höchstens AWidth Zeichen hat (mindestens 10 Zeichen
/// Text je Stück); getrennt wird möglichst hinter einem Leerzeichen.</summary>
function Chunks(const ALine: string; AWidth: Integer): TArray<string>;
var
  Rest: string;
  Size: Integer;
begin
  Result := nil;
  Rest := ALine;
  while (Length(Rest) > 10) and (Length(TStringLiterals.Quote(Rest)) > AWidth) do
  begin
    Size := Length(Rest) - 1;
    while (Size > 10) and (Length(TStringLiterals.Quote(Copy(Rest, 1, Size))) > AWidth) do
      Dec(Size);
    if LastDelimiter(' ', Copy(Rest, 1, Size)) > Size div 2 then
      Size := LastDelimiter(' ', Copy(Rest, 1, Size));
    Result := Result + [Copy(Rest, 1, Size)];
    Rest := Copy(Rest, Size + 1, MaxInt);
  end;
  Result := Result + [Rest];
end;

class function TStringLiterals.ToLiteral(const APlainText, AIndent: string; AIndentFirst, AMultiline: Boolean;
  ABreak: TStringLiteralBreak; AMaxLineLength: Integer; const ALineEnd: string): string;
var
  Lines, Parts, Output: TArray<string>;
  Index, Part: Integer;
  Line, Piece, Separator: string;
  Multiline: Boolean;
begin
  Lines := TTextLines.SplitLines(APlainText);
  Output := nil;
  Multiline := AMultiline and FitsMultiline(Lines);
  if Multiline then
  begin
    // Der Compiler entfernt die Einrückung der schließenden ''' aus allen Zeilen.
    Output := [''''''''];
    for Line in Lines do
      if Line = '' then
        Output := Output + ['']
      else
        Output := Output + [AIndent + '  ' + Line];
    Output := Output + [AIndent + '  ' + ''''''''];
  end
  else
    for Index := 0 to High(Lines) do
    begin
      Line := Lines[Index];
      Separator := '';
      if Index < High(Lines) then
        case ABreak of
          TStringLiteralBreak.SLineBreak:
            Separator := ' + sLineBreak';
          TStringLiteralBreak.CrLf:
            Separator := '#13#10';
          TStringLiteralBreak.Lf:
            Separator := '#10';
          TStringLiteralBreak.Space:
            Line := Line + ' ';
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
      if AMaxLineLength > 0 then
        Parts := Chunks(Line, AMaxLineLength - Length(AIndent) - Length(Separator) - 2)
      else
        Parts := [Line];
      for Part := 0 to High(Parts) do
      begin
        Piece := AIndent + Quote(Parts[Part]);
        if Part = High(Parts) then
          Piece := Piece + Separator;
        if (Part < High(Parts)) or (Index < High(Lines)) then
          Piece := Piece + ' +';
        Output := Output + [Piece];
      end;
    end;
  // Die erste Zeile steht hinter dem Text davor, z. B. hinter "SQL.Text := ".
  if AIndentFirst and Multiline then
    Output[0] := AIndent + Output[0]
  else if not AIndentFirst and not Multiline then
    Output[0] := Copy(Output[0], Length(AIndent) + 1, MaxInt);
  Result := '';
  for Index := 0 to High(Output) do
  begin
    if Index > 0 then
      Result := Result + ALineEnd;
    Result := Result + Output[Index];
  end;
end;

/// <summary>Inhalt eines mehrzeiligen Strings: Einrückung der schließenden ''' entfernt.</summary>
function MultilineText(const AToken: string): string;
var
  Lines: TArray<string>;
  Indent: Integer;
  Index: Integer;
begin
  Lines := TTextLines.SplitLines(AToken);
  Result := '';
  if Length(Lines) < 2 then
    Exit;
  Indent := Length(Lines[High(Lines)]) - Length(TrimLeft(Lines[High(Lines)]));
  for Index := 1 to High(Lines) - 1 do
  begin
    if Index > 1 then
      Result := Result + TStringLiterals.PlainLineBreak;
    Result := Result + Copy(Lines[Index], Indent + 1, MaxInt);
  end;
end;

/// <summary>Wert von #13, #$0D oder #13#10.</summary>
function CharValue(const AToken: string): string;
var
  Part: string;
  Code: Integer;
begin
  Result := '';
  for Part in SplitString(Copy(AToken, 2, MaxInt), '#') do
    if TryStrToInt(Part, Code) then
      Result := Result + Char(Code);
end;

function IsLiteralToken(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind in [TPascalTokenKind.StringLiteral, TPascalTokenKind.CharLiteral]) or
    ((AToken.Kind = TPascalTokenKind.Identifier) and SameText(AToken.Text, 'sLineBreak'));
end;

class function TStringLiterals.PlainText(const AExpression: string; out AText: string): Boolean;
var
  Token: TPascalToken;
  HasString: Boolean;
begin
  AText := '';
  HasString := False;
  for Token in TPascalLexer.Tokenize(AExpression) do
    case Token.Kind of
      TPascalTokenKind.StringLiteral:
        begin
          HasString := True;
          if StartsStr('''''''', Token.Text) then
            AText := AText + MultilineText(Token.Text)
          else
            AText := AText + StringReplace(Copy(Token.Text, 2, Length(Token.Text) - 2), '''''', '''',
              [rfReplaceAll]);
        end;
      TPascalTokenKind.CharLiteral:
        AText := AText + CharValue(Token.Text);
      TPascalTokenKind.Comment:
        ;
      TPascalTokenKind.Identifier:
        if SameText(Token.Text, 'sLineBreak') then
          AText := AText + PlainLineBreak
        else
          Exit(False);
      TPascalTokenKind.Symbol:
        if Token.Text <> '+' then
          Exit(False);
    else
      Exit(False);
    end;
  Result := HasString;
end;

function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
end;

function Joins(const AToken: TPascalToken): Boolean;
begin
  Result := IsLiteralToken(AToken) or AToken.IsSymbol('+') or (AToken.Kind = TPascalTokenKind.Comment);
end;

class function TStringLiterals.LiteralAt(const AText: string; const APosition: TTextPosition;
  out ARange: TTextRange): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Index, First, Last, Hit: Integer;
begin
  Tokens := TPascalLexer.Tokenize(AText);
  Hit := -1;
  for Index := 0 to High(Tokens) do
    if not Before(APosition, Tokens[Index].StartPos) and not Before(Tokens[Index].EndPos, APosition) and
      (IsLiteralToken(Tokens[Index]) or Tokens[Index].IsSymbol('+')) then
    begin
      Hit := Index;
      if IsLiteralToken(Tokens[Index]) then
        Break;
    end;
  if Hit < 0 then
    Exit(False);
  // Nach beiden Seiten über Literale, sLineBreak, + und Kommentare ausdehnen.
  First := Hit;
  while (First > 0) and Joins(Tokens[First - 1]) do
    Dec(First);
  Last := Hit;
  while (Last < High(Tokens)) and Joins(Tokens[Last + 1]) do
    Inc(Last);
  while (First <= Last) and not IsLiteralToken(Tokens[First]) do
    Inc(First);
  while (Last >= First) and not IsLiteralToken(Tokens[Last]) do
    Dec(Last);
  Result := False;
  for Index := First to Last do
    if Tokens[Index].Kind = TPascalTokenKind.StringLiteral then
      Result := True;
  if Result then
    ARange := TTextRange.Create(Tokens[First].StartPos.Line, Tokens[First].StartPos.Character,
      Tokens[Last].EndPos.Line, Tokens[Last].EndPos.Character);
end;

class function TStringLiterals.TextOf(const AText: string; const ARange: TTextRange): string;
var
  Lines: TArray<string>;
  Line: Integer;
begin
  Lines := TTextLines.SplitLines(AText);
  Result := '';
  for Line := ARange.StartPos.Line to ARange.EndPos.Line do
  begin
    if (Line < 0) or (Line > High(Lines)) then
      Continue;
    if Line > ARange.StartPos.Line then
      Result := Result + #10;
    if (Line = ARange.StartPos.Line) and (Line = ARange.EndPos.Line) then
      Result := Result + Copy(Lines[Line], ARange.StartPos.Character + 1, ARange.EndPos.Character -
        ARange.StartPos.Character)
    else if Line = ARange.StartPos.Line then
      Result := Result + Copy(Lines[Line], ARange.StartPos.Character + 1, MaxInt)
    else if Line = ARange.EndPos.Line then
      Result := Result + Copy(Lines[Line], 1, ARange.EndPos.Character)
    else
      Result := Result + Lines[Line];
  end;
end;

end.
