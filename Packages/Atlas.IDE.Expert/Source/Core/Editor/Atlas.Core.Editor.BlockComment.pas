unit Atlas.Core.Editor.BlockComment;

// Blockkommentar umschalten (#703), ohne VCL und Open Tools API.
// - Lex zerlegt den Text in Kommentare ({ … }, (* … *), //), Direktiven
//   ({$…}, (*$…*), nie ein Kommentar), Strings und Wörter bzw. Zeichen.
// - Toggle mit Markierung: Liegt sie in einem Blockkommentar, verschwindet er
//   samt dem Leerzeichen hinter dem Anfang und vor dem Ende. Sonst kommt der
//   markierte Text ohne Leerraum am Rand in einen Kommentar: { … }, wenn er
//   kein } enthält, (* … *), wenn er kein *) enthält, bevorzugt in der Form
//   der Einstellung; enthält er beides, // je Zeile oder Ablehnen. Eine
//   Markierung, die nur eine Direktive enthält, bekommt // je Zeile.
//   Mehrzeilig wahlweise mit den Kommentarzeichen in eigenen Zeilen (ganze
//   Zeilen, Einzug der ersten). Hin und zurück ergibt denselben Text.
// - Ohne Markierung: Steht der Cursor in einem Blockkommentar, verschwindet
//   er; sonst wird die Anweisung am Cursor (StatementRange) bzw. die Zeile
//   kommentiert.
// - Die Markierung (bzw. der Cursor) wandert mit dem Text.
// Positionen: Zeile und Zeichen ab 0, UTF-16 wie im LSP; Enden ausschließlich.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.TextChanges;

type
{$SCOPEDENUMS ON}
  /// <summary>Bevorzugte Form (keys.toggleBlockComment.style).</summary>
  TAtlasBlockCommentStyle = (Braces, Parens);
  /// <summary>Wenn } und *) vorkommen (keys.toggleBlockComment.fallback).</summary>
  TAtlasBlockCommentFallback = (LineComments, Refuse);
  /// <summary>Was ohne Markierung kommentiert wird (keys.toggleBlockComment.withoutSelection).</summary>
  TAtlasBlockCommentScope = (Statement, Line);
  TAtlasBlockCommentKind = (None, Added, Removed, LineComments, Refused);
  TAtlasCommentSpanKind = (BraceComment, ParenComment, LineComment, Directive, StringLiteral);
{$SCOPEDENUMS OFF}

  TAtlasBlockCommentOptions = record
    Style: TAtlasBlockCommentStyle;
    Fallback: TAtlasBlockCommentFallback;
    /// <summary>Mehrzeilig: Kommentarzeichen in eigene Zeilen.</summary>
    OwnLines: Boolean;
    Scope: TAtlasBlockCommentScope;
    /// <summary>Vorgaben: { }, // als Rückfall, Zeichen an Anfang und Ende, Anweisung.</summary>
    class function Defaults: TAtlasBlockCommentOptions; static;
  end;

  TAtlasCommentSpan = record
    Kind: TAtlasCommentSpanKind;
    StartPos: TLspTextPosition;
    /// <summary>Ausschließlich.</summary>
    EndPos: TLspTextPosition;
  end;

  TAtlasCodeToken = record
    /// <summary>Wörter klein geschrieben, sonst der Text.</summary>
    Text: string;
    IsWord: Boolean;
    StartPos: TLspTextPosition;
    EndPos: TLspTextPosition;
  end;

  TAtlasBlockCommentResult = record
    Kind: TAtlasBlockCommentKind;
    /// <summary>Neuer Text; bei None und Refused der alte.</summary>
    Lines: TArray<string>;
    /// <summary>Markierung danach; ohne Markierung beide gleich (Cursor).</summary>
    SelectionStart: TLspTextPosition;
    SelectionEnd: TLspTextPosition;
  end;

  TAtlasBlockComment = class
  public
    /// <summary>Kommentare, Direktiven und Strings in ALines, nach Lage sortiert.</summary>
    class function Spans(const ALines: TArray<string>): TArray<TAtlasCommentSpan>; static;
    /// <summary>Wörter und Zeichen außerhalb von Kommentaren und Direktiven; Strings als ein Token.</summary>
    class function Tokens(const ALines: TArray<string>): TArray<TAtlasCodeToken>; static;
    /// <summary>Blockkommentar (keine Direktive), in dem APos liegt, Grenzen eingeschlossen.</summary>
    class function CommentAt(const ALines: TArray<string>; const APos: TLspTextPosition;
      out ASpan: TAtlasCommentSpan): Boolean; static;
    /// <summary>Anweisung am Cursor ACursor, von ihrem ersten Token bis zum Semikolon (bzw. vor end, else,
    /// until, except, finally); False ohne Token in der Cursorzeile.</summary>
    class function StatementRange(const ALines: TArray<string>; const ACursor: TLspTextPosition;
      out AStart, AEnd: TLspTextPosition): Boolean; static;
    /// <summary>Umschalten für die Markierung ASelectionStart bis ASelectionEnd; sind beide gleich, gilt das als
    /// Cursor ohne Markierung.</summary>
    class function Toggle(const ALines: TArray<string>; const ASelectionStart, ASelectionEnd: TLspTextPosition;
      const AOptions: TAtlasBlockCommentOptions): TAtlasBlockCommentResult; static;
    /// <summary>Werte der Einstellungen ("braces"/"parens", "lineComments"/"refuse", "statement"/"line").
    /// </summary>
    class function StyleOf(const AValue: string): TAtlasBlockCommentStyle; static;
    class function FallbackOf(const AValue: string): TAtlasBlockCommentFallback; static;
    class function ScopeOf(const AValue: string): TAtlasBlockCommentScope; static;
  end;

implementation

uses
  System.Math,
  Atlas.Text.Chars;

const
  // Ohne "of": in "array of", "set of" begänne sonst eine Anweisung.
  StatementStarts: array[0..14] of string = ('begin', 'then', 'else', 'do', 'try', 'finally', 'except', 'repeat',
    'asm', 'var', 'const', 'type', 'uses', 'initialization', 'finalization');

function Pos2(ALine, ACharacter: Integer): TLspTextPosition;
begin
  Result := TLspTextPosition.Create(ALine, ACharacter);
end;

function Cmp(const A, B: TLspTextPosition): Integer;
begin
  Result := TLspTextPosition.Compare(A, B);
end;

function IsStatementStart(const AToken: TAtlasCodeToken): Boolean;
var
  Word: string;
begin
  Result := AToken.Text = ';';
  if Result or not AToken.IsWord then
    Exit;
  for Word in StatementStarts do
    if AToken.Text = Word then
      Exit(True);
end;

function IsWord(const AToken: TAtlasCodeToken; const AWord: string): Boolean;
begin
  Result := AToken.IsWord and (AToken.Text = AWord);
end;

function LeadingSpace(const ALine: string): Integer;
begin
  Result := 0;
  while (Result < Length(ALine)) and CharInSet(ALine[Result + 1], [' ', #9]) do
    Inc(Result);
end;

{ Lexer }

procedure Lex(const ALines: TArray<string>; out ASpans: TArray<TAtlasCommentSpan>;
  out ATokens: TArray<TAtlasCodeToken>);
var
  Line, Index, Count, Start: Integer;
  Text: string;
  Open: TAtlasCommentSpan;
  Inside: Boolean;
  Close: string;

  procedure AddSpan(AKind: TAtlasCommentSpanKind; AStartLine, AStartChar, AEndLine, AEndChar: Integer);
  var
    Span: TAtlasCommentSpan;
  begin
    Span.Kind := AKind;
    Span.StartPos := Pos2(AStartLine, AStartChar);
    Span.EndPos := Pos2(AEndLine, AEndChar);
    ASpans := ASpans + [Span];
  end;

  procedure AddToken(const AText: string; AIsWord: Boolean; ALine, AStart, AStop: Integer);
  var
    Token: TAtlasCodeToken;
  begin
    Token.Text := AText;
    Token.IsWord := AIsWord;
    Token.StartPos := Pos2(ALine, AStart);
    Token.EndPos := Pos2(ALine, AStop);
    ATokens := ATokens + [Token];
  end;

begin
  ASpans := nil;
  ATokens := nil;
  Inside := False;
  Close := '';
  Open := Default(TAtlasCommentSpan);
  for Line := 0 to High(ALines) do
  begin
    Text := ALines[Line];
    Count := Length(Text);
    // Index ist 1-basiert.
    Index := 1;
    while Index <= Count do
    begin
      if Inside then
      begin
        Start := Pos(Close, Text, Index);
        if Start = 0 then
        begin
          Index := Count + 1;
          Continue;
        end;
        Index := Start + Length(Close);
        AddSpan(Open.Kind, Open.StartPos.Line, Open.StartPos.Character, Line, Index - 1);
        Inside := False;
        Continue;
      end;
      case Text[Index] of
        ' ', #9:
          Inc(Index);
        '{':
          begin
            Open.Kind := TAtlasCommentSpanKind.BraceComment;
            if (Index < Count) and (Text[Index + 1] = '$') then
              Open.Kind := TAtlasCommentSpanKind.Directive;
            Open.StartPos := Pos2(Line, Index - 1);
            Close := '}';
            Inside := True;
            Inc(Index);
          end;
        '/':
          if (Index < Count) and (Text[Index + 1] = '/') then
          begin
            AddSpan(TAtlasCommentSpanKind.LineComment, Line, Index - 1, Line, Count);
            Index := Count + 1;
          end
          else
          begin
            AddToken('/', False, Line, Index - 1, Index);
            Inc(Index);
          end;
        '(':
          if (Index < Count) and (Text[Index + 1] = '*') then
          begin
            Open.Kind := TAtlasCommentSpanKind.ParenComment;
            if (Index + 1 < Count) and (Text[Index + 2] = '$') then
              Open.Kind := TAtlasCommentSpanKind.Directive;
            Open.StartPos := Pos2(Line, Index - 1);
            Close := '*)';
            Inside := True;
            Inc(Index, 2);
          end
          else
          begin
            AddToken('(', False, Line, Index - 1, Index);
            Inc(Index);
          end;
        '''':
          begin
            Start := Index;
            Inc(Index);
            while Index <= Count do
            begin
              if Text[Index] = '''' then
              begin
                if (Index < Count) and (Text[Index + 1] = '''') then
                  Inc(Index, 2)
                else
                  Break;
              end
              else
                Inc(Index);
            end;
            Index := Min(Index + 1, Count + 1);
            AddSpan(TAtlasCommentSpanKind.StringLiteral, Line, Start - 1, Line, Index - 1);
            AddToken(Copy(Text, Start, Index - Start), False, Line, Start - 1, Index - 1);
          end;
      else
        if TTextChars.IsIdentStart(Text[Index]) or (Text[Index] = '&') then
        begin
          Start := Index;
          Inc(Index);
          while (Index <= Count) and TTextChars.IsIdentChar(Text[Index]) do
            Inc(Index);
          AddToken(LowerCase(Copy(Text, Start, Index - Start)), True, Line, Start - 1, Index - 1);
        end
        else
        begin
          AddToken(Text[Index], False, Line, Index - 1, Index);
          Inc(Index);
        end;
      end;
    end;
  end;
  // Nicht geschlossen: bis zum Textende.
  if Inside and (Length(ALines) > 0) then
    AddSpan(Open.Kind, Open.StartPos.Line, Open.StartPos.Character, High(ALines), Length(ALines[High(ALines)]));
end;

{ Text }

function TextOf(const ALines: TArray<string>; const AStart, AEnd: TLspTextPosition): string;
var
  Line: Integer;
begin
  Result := '';
  if Cmp(AStart, AEnd) >= 0 then
    Exit;
  if AStart.Line = AEnd.Line then
    Exit(Copy(ALines[AStart.Line], AStart.Character + 1, AEnd.Character - AStart.Character));
  Result := Copy(ALines[AStart.Line], AStart.Character + 1, MaxInt);
  for Line := AStart.Line + 1 to AEnd.Line - 1 do
    Result := Result + #10 + ALines[Line];
  Result := Result + #10 + Copy(ALines[AEnd.Line], 1, AEnd.Character);
end;

function Clamp(const ALines: TArray<string>; const APos: TLspTextPosition): TLspTextPosition;
begin
  Result := APos;
  if Length(ALines) = 0 then
    Exit(Pos2(0, 0));
  Result.Line := EnsureRange(Result.Line, 0, High(ALines));
  Result.Character := EnsureRange(Result.Character, 0, Length(ALines[Result.Line]));
end;

/// <summary>AStart/AEnd ohne Leerraum am Rand; False, wenn nichts übrig bleibt.</summary>
function TrimRange(const ALines: TArray<string>; var AStart, AEnd: TLspTextPosition): Boolean;
begin
  // Vorn: Leerraum und Zeilenenden überspringen.
  while Cmp(AStart, AEnd) < 0 do
  begin
    if AStart.Character >= Length(ALines[AStart.Line]) then
      AStart := Pos2(AStart.Line + 1, 0)
    else if CharInSet(ALines[AStart.Line][AStart.Character + 1], [' ', #9]) then
      Inc(AStart.Character)
    else
      Break;
  end;
  // Hinten ebenso rückwärts.
  while Cmp(AStart, AEnd) < 0 do
  begin
    if AEnd.Character = 0 then
      AEnd := Pos2(AEnd.Line - 1, Length(ALines[AEnd.Line - 1]))
    else if CharInSet(ALines[AEnd.Line][AEnd.Character], [' ', #9]) then
      Dec(AEnd.Character)
    else
      Break;
  end;
  Result := Cmp(AStart, AEnd) < 0;
end;

{ Verschieben von Positionen }

/// <summary>Einfügen von ALength Zeichen in ALine bei AAt: APos rückt nach, wenn sie dahinter liegt (bzw. bei
/// AAtToo auch genau dort).</summary>
function AfterInsert(const APos: TLspTextPosition; ALine, AAt, ALength: Integer; AAtToo: Boolean): TLspTextPosition;
begin
  Result := APos;
  if (APos.Line = ALine) and ((APos.Character > AAt) or (AAtToo and (APos.Character = AAt))) then
    Inc(Result.Character, ALength);
end;

/// <summary>Löschen von ALength Zeichen in ALine ab AAt.</summary>
function AfterDelete(const APos: TLspTextPosition; ALine, AAt, ALength: Integer): TLspTextPosition;
begin
  Result := APos;
  if (APos.Line <> ALine) or (APos.Character <= AAt) then
    Exit;
  Result.Character := Max(AAt, APos.Character - ALength);
end;

{ TAtlasBlockCommentOptions }

class function TAtlasBlockCommentOptions.Defaults: TAtlasBlockCommentOptions;
begin
  Result.Style := TAtlasBlockCommentStyle.Braces;
  Result.Fallback := TAtlasBlockCommentFallback.LineComments;
  Result.OwnLines := False;
  Result.Scope := TAtlasBlockCommentScope.Statement;
end;

{ TAtlasBlockComment }

class function TAtlasBlockComment.Spans(const ALines: TArray<string>): TArray<TAtlasCommentSpan>;
var
  Found: TArray<TAtlasCodeToken>;
begin
  Lex(ALines, Result, Found);
end;

class function TAtlasBlockComment.Tokens(const ALines: TArray<string>): TArray<TAtlasCodeToken>;
var
  Found: TArray<TAtlasCommentSpan>;
begin
  Lex(ALines, Found, Result);
end;

class function TAtlasBlockComment.CommentAt(const ALines: TArray<string>; const APos: TLspTextPosition;
  out ASpan: TAtlasCommentSpan): Boolean;
var
  Span: TAtlasCommentSpan;
begin
  ASpan := Default(TAtlasCommentSpan);
  for Span in Spans(ALines) do
    if (Span.Kind in [TAtlasCommentSpanKind.BraceComment, TAtlasCommentSpanKind.ParenComment]) and
      (Cmp(Span.StartPos, APos) <= 0) and (Cmp(APos, Span.EndPos) <= 0) then
    begin
      ASpan := Span;
      Exit(True);
    end;
  Result := False;
end;

class function TAtlasBlockComment.StatementRange(const ALines: TArray<string>; const ACursor: TLspTextPosition;
  out AStart, AEnd: TLspTextPosition): Boolean;
var
  List: TArray<TAtlasCodeToken>;
  Index, Current, First, Depth, Blocks, Ifs: Integer;
  Token: TAtlasCodeToken;
begin
  AStart := ACursor;
  AEnd := ACursor;
  List := Tokens(ALines);
  // Token am Cursor, sonst das nächste bzw. letzte der Cursorzeile.
  Current := -1;
  for Index := 0 to High(List) do
  begin
    Token := List[Index];
    if Token.StartPos.Line <> ACursor.Line then
      Continue;
    if Cmp(Token.StartPos, ACursor) <= 0 then
      Current := Index
    else
    begin
      if (Current < 0) or (Cmp(List[Current].EndPos, ACursor) < 0) then
        Current := Index;
      Break;
    end;
  end;
  if Current < 0 then
    Exit(False);
  // Direkt hinter dem Semikolon: die Anweisung davor.
  if (List[Current].Text = ';') and (Current > 0) and (List[Current - 1].StartPos.Line = ACursor.Line) then
    Dec(Current);
  // Rückwärts bis hinter das vorige Semikolon bzw. Schlüsselwort, Klammern übersprungen.
  First := Current;
  Depth := 0;
  while First > 0 do
  begin
    Token := List[First - 1];
    if (Token.Text = ')') or (Token.Text = ']') then
      Inc(Depth)
    else if ((Token.Text = '(') or (Token.Text = '[')) and (Depth > 0) then
      Dec(Depth)
    else if (Depth = 0) and IsStatementStart(Token) then
      Break;
    Dec(First);
  end;
  // Vorwärts bis zum Semikolon derselben Ebene.
  Depth := 0;
  Blocks := 0;
  Ifs := 0;
  Index := First;
  AStart := List[First].StartPos;
  AEnd := AStart;
  while Index <= High(List) do
  begin
    Token := List[Index];
    if (Token.Text = '(') or (Token.Text = '[') then
      Inc(Depth)
    else if ((Token.Text = ')') or (Token.Text = ']')) and (Depth > 0) then
      Dec(Depth)
    else if Depth = 0 then
    begin
      if IsWord(Token, 'begin') or IsWord(Token, 'case') or IsWord(Token, 'try') or IsWord(Token, 'asm') or
        IsWord(Token, 'record') or IsWord(Token, 'repeat') then
        Inc(Blocks)
      else if IsWord(Token, 'end') or IsWord(Token, 'until') then
      begin
        if Blocks = 0 then
          Break;
        Dec(Blocks);
      end
      else if (Blocks = 0) and IsWord(Token, 'if') then
        Inc(Ifs)
      else if (Blocks = 0) and IsWord(Token, 'else') then
      begin
        if Ifs = 0 then
          Break;
        Dec(Ifs);
      end
      else if (Blocks = 0) and (IsWord(Token, 'except') or IsWord(Token, 'finally')) then
        Break
      else if (Blocks = 0) and (Token.Text = ';') then
      begin
        AEnd := Token.EndPos;
        Break;
      end;
    end;
    AEnd := Token.EndPos;
    Inc(Index);
  end;
  Result := Cmp(AStart, AEnd) < 0;
end;

function RemoveComment(const ALines: TArray<string>; const ASpan: TAtlasCommentSpan; const AStart,
  AEnd: TLspTextPosition): TAtlasBlockCommentResult;
var
  Lines: TArray<string>;
  Size, OpenLine, OpenAt, OpenLength, CloseLine, CloseAt, CloseLength: Integer;
  Opener, Closer: string;
  SelectionStart, SelectionEnd: TLspTextPosition;
begin
  Result.Kind := TAtlasBlockCommentKind.Removed;
  Lines := Copy(ALines);
  Size := 1;
  Opener := '{';
  Closer := '}';
  if ASpan.Kind = TAtlasCommentSpanKind.ParenComment then
  begin
    Size := 2;
    Opener := '(*';
    Closer := '*)';
  end;
  SelectionStart := AStart;
  SelectionEnd := AEnd;
  OpenLine := ASpan.StartPos.Line;
  CloseLine := ASpan.EndPos.Line;
  // Eigene Zeilen: beide Zeilen entfallen.
  if (OpenLine < CloseLine) and (Trim(Lines[OpenLine]) = Opener) and (Trim(Lines[CloseLine]) = Closer) then
  begin
    Delete(Lines, CloseLine, 1);
    Delete(Lines, OpenLine, 1);
    SelectionStart.Line := SelectionStart.Line - Ord(SelectionStart.Line > OpenLine) -
      Ord(SelectionStart.Line > CloseLine);
    SelectionEnd.Line := SelectionEnd.Line - Ord(SelectionEnd.Line > OpenLine) - Ord(SelectionEnd.Line > CloseLine);
    if (AStart.Line = OpenLine) or (AStart.Line = CloseLine) then
      SelectionStart.Character := 0;
    if (AEnd.Line = OpenLine) or (AEnd.Line = CloseLine) then
      SelectionEnd.Character := 0;
    Result.Lines := Lines;
    Result.SelectionStart := Clamp(Lines, SelectionStart);
    Result.SelectionEnd := Clamp(Lines, SelectionEnd);
    Exit;
  end;
  OpenAt := ASpan.StartPos.Character;
  OpenLength := Size;
  CloseAt := ASpan.EndPos.Character - Size;
  CloseLength := Size;
  // Unser Leerzeichen hinter dem Anfang und vor dem Ende, ohne dass sich beide überschneiden.
  if (OpenAt + Size < Length(Lines[OpenLine])) and (Lines[OpenLine][OpenAt + Size + 1] = ' ') and
    ((OpenLine <> CloseLine) or (OpenAt + Size < CloseAt)) then
    Inc(OpenLength);
  if (CloseAt > 0) and (Lines[CloseLine][CloseAt] = ' ') and
    ((OpenLine <> CloseLine) or (CloseAt - 1 >= OpenAt + OpenLength)) then
  begin
    Dec(CloseAt);
    Inc(CloseLength);
  end;
  // Erst das Ende, dann der Anfang.
  Delete(Lines[CloseLine], CloseAt + 1, CloseLength);
  SelectionStart := AfterDelete(SelectionStart, CloseLine, CloseAt, CloseLength);
  SelectionEnd := AfterDelete(SelectionEnd, CloseLine, CloseAt, CloseLength);
  Delete(Lines[OpenLine], OpenAt + 1, OpenLength);
  SelectionStart := AfterDelete(SelectionStart, OpenLine, OpenAt, OpenLength);
  SelectionEnd := AfterDelete(SelectionEnd, OpenLine, OpenAt, OpenLength);
  Result.Lines := Lines;
  Result.SelectionStart := Clamp(Lines, SelectionStart);
  Result.SelectionEnd := Clamp(Lines, SelectionEnd);
end;

function AddLineComments(const ALines: TArray<string>; AFirst, ALast: Integer; const AStart,
  AEnd: TLspTextPosition): TAtlasBlockCommentResult;
var
  Lines: TArray<string>;
  Line, Indent: Integer;
begin
  Result.Kind := TAtlasBlockCommentKind.LineComments;
  Lines := Copy(ALines);
  Result.SelectionStart := AStart;
  Result.SelectionEnd := AEnd;
  for Line := AFirst to ALast do
  begin
    if Trim(Lines[Line]) = '' then
      Continue;
    Indent := LeadingSpace(Lines[Line]);
    Insert('// ', Lines[Line], Indent + 1);
    Result.SelectionStart := AfterInsert(Result.SelectionStart, Line, Indent, 3, True);
    Result.SelectionEnd := AfterInsert(Result.SelectionEnd, Line, Indent, 3, True);
  end;
  Result.Lines := Lines;
end;

function IsOnlyDirective(const ALines: TArray<string>; const AStart, AEnd: TLspTextPosition): Boolean;
var
  Span: TAtlasCommentSpan;
begin
  for Span in TAtlasBlockComment.Spans(ALines) do
    if (Span.Kind = TAtlasCommentSpanKind.Directive) and (Cmp(Span.StartPos, AStart) = 0) and
      (Cmp(Span.EndPos, AEnd) = 0) then
      Exit(True);
  Result := False;
end;

function AddComment(const ALines: TArray<string>; const AFrom, ATo, ASelectionStart,
  ASelectionEnd: TLspTextPosition; const AOptions: TAtlasBlockCommentOptions): TAtlasBlockCommentResult;
var
  Lines: TArray<string>;
  Text, Opener, Closer, Indent: string;
  CanBraces, CanParens, Braces: Boolean;
  First, Last: Integer;
  SelectionStart, SelectionEnd: TLspTextPosition;
begin
  Result.Kind := TAtlasBlockCommentKind.Refused;
  Result.Lines := ALines;
  Result.SelectionStart := ASelectionStart;
  Result.SelectionEnd := ASelectionEnd;
  First := AFrom.Line;
  Last := ATo.Line;
  // Nur eine Direktive: mit // auskommentieren, damit kein Kommentar entsteht, der wie eine Direktive aussieht.
  if IsOnlyDirective(ALines, AFrom, ATo) then
    Exit(AddLineComments(ALines, First, Last, ASelectionStart, ASelectionEnd));
  if AOptions.OwnLines and (First < Last) then
    Text := TextOf(ALines, Pos2(First, 0), Pos2(Last, Length(ALines[Last])))
  else
    Text := TextOf(ALines, AFrom, ATo);
  CanBraces := Pos('}', Text) = 0;
  CanParens := Pos('*)', Text) = 0;
  if not CanBraces and not CanParens then
  begin
    if AOptions.Fallback = TAtlasBlockCommentFallback.Refuse then
      Exit;
    Exit(AddLineComments(ALines, First, Last, ASelectionStart, ASelectionEnd));
  end;
  Braces := CanBraces and ((AOptions.Style = TAtlasBlockCommentStyle.Braces) or not CanParens);
  Opener := '(*';
  Closer := '*)';
  if Braces then
  begin
    Opener := '{';
    Closer := '}';
  end;
  Result.Kind := TAtlasBlockCommentKind.Added;
  Lines := Copy(ALines);
  SelectionStart := ASelectionStart;
  SelectionEnd := ASelectionEnd;
  if AOptions.OwnLines and (First < Last) then
  begin
    Indent := Copy(Lines[First], 1, LeadingSpace(Lines[First]));
    Insert(Indent + Closer, Lines, Last + 1);
    Insert(Indent + Opener, Lines, First);
    // Die Markierung bleibt auf den Zeilen dazwischen.
    if (SelectionEnd.Line = Last + 1) and (SelectionEnd.Character = 0) then
      SelectionEnd.Line := Last + 2
    else
      SelectionEnd.Line := SelectionEnd.Line + Ord(SelectionEnd.Line >= First) + Ord(SelectionEnd.Line > Last);
    SelectionStart.Line := SelectionStart.Line + Ord(SelectionStart.Line >= First) +
      Ord(SelectionStart.Line > Last);
  end
  else
  begin
    // Erst das Ende, dann der Anfang; je ein Leerzeichen innen.
    Insert(' ' + Closer, Lines[ATo.Line], ATo.Character + 1);
    SelectionStart := AfterInsert(SelectionStart, ATo.Line, ATo.Character, Length(Closer) + 1, False);
    SelectionEnd := AfterInsert(SelectionEnd, ATo.Line, ATo.Character, Length(Closer) + 1, False);
    Insert(Opener + ' ', Lines[AFrom.Line], AFrom.Character + 1);
    SelectionStart := AfterInsert(SelectionStart, AFrom.Line, AFrom.Character, Length(Opener) + 1, True);
    SelectionEnd := AfterInsert(SelectionEnd, AFrom.Line, AFrom.Character, Length(Opener) + 1, True);
  end;
  Result.Lines := Lines;
  Result.SelectionStart := SelectionStart;
  Result.SelectionEnd := SelectionEnd;
end;

class function TAtlasBlockComment.Toggle(const ALines: TArray<string>; const ASelectionStart,
  ASelectionEnd: TLspTextPosition; const AOptions: TAtlasBlockCommentOptions): TAtlasBlockCommentResult;
var
  SelectionStart, SelectionEnd, From, Till: TLspTextPosition;
  Span: TAtlasCommentSpan;
  HasSelection: Boolean;
  Line: string;
begin
  Result := Default(TAtlasBlockCommentResult);
  Result.Lines := ALines;
  if Length(ALines) = 0 then
    Exit;
  SelectionStart := Clamp(ALines, ASelectionStart);
  SelectionEnd := Clamp(ALines, ASelectionEnd);
  if Cmp(SelectionEnd, SelectionStart) < 0 then
  begin
    From := SelectionStart;
    SelectionStart := SelectionEnd;
    SelectionEnd := From;
  end;
  Result.SelectionStart := SelectionStart;
  Result.SelectionEnd := SelectionEnd;
  HasSelection := Cmp(SelectionStart, SelectionEnd) < 0;
  From := SelectionStart;
  Till := SelectionEnd;
  if HasSelection then
  begin
    if not TrimRange(ALines, From, Till) then
      Exit;
    // In einem Blockkommentar: ihn entfernen.
    if CommentAt(ALines, From, Span) and (Cmp(Till, Span.EndPos) <= 0) then
      Exit(RemoveComment(ALines, Span, SelectionStart, SelectionEnd));
  end
  else
  begin
    if CommentAt(ALines, SelectionStart, Span) then
      Exit(RemoveComment(ALines, Span, SelectionStart, SelectionEnd));
    if (AOptions.Scope = TAtlasBlockCommentScope.Line) or
      not StatementRange(ALines, SelectionStart, From, Till) then
    begin
      Line := ALines[SelectionStart.Line];
      From := Pos2(SelectionStart.Line, LeadingSpace(Line));
      Till := Pos2(SelectionStart.Line, Length(TrimRight(Line)));
    end;
    if not TrimRange(ALines, From, Till) then
      Exit;
  end;
  Result := AddComment(ALines, From, Till, SelectionStart, SelectionEnd, AOptions);
end;

class function TAtlasBlockComment.StyleOf(const AValue: string): TAtlasBlockCommentStyle;
begin
  Result := TAtlasBlockCommentStyle.Braces;
  if SameText(AValue, 'parens') then
    Result := TAtlasBlockCommentStyle.Parens;
end;

class function TAtlasBlockComment.FallbackOf(const AValue: string): TAtlasBlockCommentFallback;
begin
  Result := TAtlasBlockCommentFallback.LineComments;
  if SameText(AValue, 'refuse') then
    Result := TAtlasBlockCommentFallback.Refuse;
end;

class function TAtlasBlockComment.ScopeOf(const AValue: string): TAtlasBlockCommentScope;
begin
  Result := TAtlasBlockCommentScope.Statement;
  if SameText(AValue, 'line') then
    Result := TAtlasBlockCommentScope.Line;
end;

end.
