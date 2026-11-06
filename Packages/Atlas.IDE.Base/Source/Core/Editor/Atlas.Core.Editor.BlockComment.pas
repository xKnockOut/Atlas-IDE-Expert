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
  begin
    Exit;
  end;
  for Word in StatementStarts do
  begin
    if AToken.Text = Word then
    begin
      Exit(True);
    end;
  end;
end;

function IsWord(const AToken: TAtlasCodeToken; const AWord: string): Boolean;
begin
  Result := AToken.IsWord and (AToken.Text = AWord);
end;

function LeadingSpace(const ALine: string): Integer;
begin
  Result := 0;
  while (Result < Length(ALine)) and CharInSet(ALine[Result + 1], [' ', #9]) do
  begin
    Inc(Result);
  end;
end;

function IsOneOf(const AText: string; const AWords: array of string): Boolean;
var
  mWord: string;
begin
  Result := False;
  for mWord in AWords do
  begin
    Result := Result or (mWord = AText);
  end;
end;

{ Lexer }

type
  /// <summary>Kommentare, Direktiven und Strings als Bereiche, der Rest als Token; Zeile für Zeile.</summary>
  TCommentLexer = class
  private
    FSpans: TArray<TAtlasCommentSpan>;
    FTokens: TArray<TAtlasCodeToken>;
    FText: string;
    FCount: Integer;
    FLine: Integer;
    /// <summary>1-basiert.</summary>
    FIndex: Integer;
    FInside: Boolean;
    FClose: string;
    FOpen: TAtlasCommentSpan;
    function CharAt(AIndex: Integer): Char;
    procedure AddSpan(AKind: TAtlasCommentSpanKind; AStartLine, AStartChar, AEndLine, AEndChar: Integer);
    procedure AddToken(const AText: string; AIsWord: Boolean; AStart, AStop: Integer);
    procedure ScanInside;
    procedure OpenComment(AKind: TAtlasCommentSpanKind; const AClose: string; ALength: Integer);
    procedure LexBrace;
    procedure LexSlash;
    procedure LexParen;
    procedure LexString;
    procedure LexOther;
    procedure Step;
  public
    procedure Run(const ALines: TArray<string>; out ASpans: TArray<TAtlasCommentSpan>;
      out ATokens: TArray<TAtlasCodeToken>);
  end;

function TCommentLexer.CharAt(AIndex: Integer): Char;
begin
  Result := #0;
  if (AIndex >= 1) and (AIndex <= FCount) then
  begin
    Result := FText[AIndex];
  end;
end;

procedure TCommentLexer.AddSpan(AKind: TAtlasCommentSpanKind; AStartLine, AStartChar, AEndLine, AEndChar: Integer);
var
  mSpan: TAtlasCommentSpan;
begin
  mSpan.Kind := AKind;
  mSpan.StartPos := Pos2(AStartLine, AStartChar);
  mSpan.EndPos := Pos2(AEndLine, AEndChar);
  FSpans := FSpans + [mSpan];
end;

procedure TCommentLexer.AddToken(const AText: string; AIsWord: Boolean; AStart, AStop: Integer);
var
  mToken: TAtlasCodeToken;
begin
  mToken.Text := AText;
  mToken.IsWord := AIsWord;
  mToken.StartPos := Pos2(FLine, AStart);
  mToken.EndPos := Pos2(FLine, AStop);
  FTokens := FTokens + [mToken];
end;

procedure TCommentLexer.ScanInside;
var
  mStart: Integer;
begin
  mStart := Pos(FClose, FText, FIndex);
  if mStart = 0 then
  begin
    FIndex := FCount + 1;
    Exit;
  end;
  FIndex := mStart + Length(FClose);
  AddSpan(FOpen.Kind, FOpen.StartPos.Line, FOpen.StartPos.Character, FLine, FIndex - 1);
  FInside := False;
end;

procedure TCommentLexer.OpenComment(AKind: TAtlasCommentSpanKind; const AClose: string; ALength: Integer);
begin
  FOpen.Kind := AKind;
  FOpen.StartPos := Pos2(FLine, FIndex - 1);
  FClose := AClose;
  FInside := True;
  Inc(FIndex, ALength);
end;

procedure TCommentLexer.LexBrace;
begin
  if CharAt(FIndex + 1) = '$' then
  begin
    OpenComment(TAtlasCommentSpanKind.Directive, '}', 1);
  end
  else
  begin
    OpenComment(TAtlasCommentSpanKind.BraceComment, '}', 1);
  end;
end;

procedure TCommentLexer.LexSlash;
begin
  if CharAt(FIndex + 1) = '/' then
  begin
    AddSpan(TAtlasCommentSpanKind.LineComment, FLine, FIndex - 1, FLine, FCount);
    FIndex := FCount + 1;
  end
  else
  begin
    AddToken('/', False, FIndex - 1, FIndex);
    Inc(FIndex);
  end;
end;

procedure TCommentLexer.LexParen;
begin
  if CharAt(FIndex + 1) <> '*' then
  begin
    AddToken('(', False, FIndex - 1, FIndex);
    Inc(FIndex);
  end
  else if CharAt(FIndex + 2) = '$' then
  begin
    OpenComment(TAtlasCommentSpanKind.Directive, '*)', 2);
  end
  else
  begin
    OpenComment(TAtlasCommentSpanKind.ParenComment, '*)', 2);
  end;
end;

procedure TCommentLexer.LexString;
var
  mStart: Integer;
  mDone: Boolean;
begin
  mStart := FIndex;
  Inc(FIndex);
  mDone := False;
  while not mDone and (FIndex <= FCount) do
  begin
    if (FText[FIndex] = '''') and (CharAt(FIndex + 1) = '''') then
    begin
      Inc(FIndex, 2);
    end
    else if FText[FIndex] = '''' then
    begin
      mDone := True;
    end
    else
    begin
      Inc(FIndex);
    end;
  end;
  FIndex := Min(FIndex + 1, FCount + 1);
  AddSpan(TAtlasCommentSpanKind.StringLiteral, FLine, mStart - 1, FLine, FIndex - 1);
  AddToken(Copy(FText, mStart, FIndex - mStart), False, mStart - 1, FIndex - 1);
end;

procedure TCommentLexer.LexOther;
var
  mStart: Integer;
begin
  if not (TTextChars.IsIdentStart(FText[FIndex]) or (FText[FIndex] = '&')) then
  begin
    AddToken(FText[FIndex], False, FIndex - 1, FIndex);
    Inc(FIndex);
    Exit;
  end;
  mStart := FIndex;
  Inc(FIndex);
  while (FIndex <= FCount) and TTextChars.IsIdentChar(FText[FIndex]) do
  begin
    Inc(FIndex);
  end;
  AddToken(LowerCase(Copy(FText, mStart, FIndex - mStart)), True, mStart - 1, FIndex - 1);
end;

procedure TCommentLexer.Step;
begin
  case FText[FIndex] of
    ' ', #9:
      begin
        Inc(FIndex);
      end;
    '{':
      begin
        LexBrace;
      end;
    '/':
      begin
        LexSlash;
      end;
    '(':
      begin
        LexParen;
      end;
    '''':
      begin
        LexString;
      end;
  else
    begin
      LexOther;
    end;
  end;
end;

procedure TCommentLexer.Run(const ALines: TArray<string>; out ASpans: TArray<TAtlasCommentSpan>;
  out ATokens: TArray<TAtlasCodeToken>);
var
  mLine: Integer;
begin
  FSpans := nil;
  FTokens := nil;
  FInside := False;
  FClose := '';
  FOpen := Default(TAtlasCommentSpan);
  for mLine := 0 to High(ALines) do
  begin
    FLine := mLine;
    FText := ALines[mLine];
    FCount := Length(FText);
    FIndex := 1;
    while FIndex <= FCount do
    begin
      if FInside then
      begin
        ScanInside;
      end
      else
      begin
        Step;
      end;
    end;
  end;
  // Nicht geschlossen: bis zum Textende.
  if FInside and (Length(ALines) > 0) then
  begin
    AddSpan(FOpen.Kind, FOpen.StartPos.Line, FOpen.StartPos.Character, High(ALines), Length(ALines[High(ALines)]));
  end;
  ASpans := FSpans;
  ATokens := FTokens;
end;

procedure Lex(const ALines: TArray<string>; out ASpans: TArray<TAtlasCommentSpan>;
  out ATokens: TArray<TAtlasCodeToken>);
var
  mLexer: TCommentLexer;
begin
  mLexer := TCommentLexer.Create;
  try
    mLexer.Run(ALines, ASpans, ATokens);
  finally
    mLexer.Free;
  end;
end;

{ Text }

function TextOf(const ALines: TArray<string>; const AStart, AEnd: TLspTextPosition): string;
var
  Line: Integer;
begin
  Result := '';
  if Cmp(AStart, AEnd) >= 0 then
  begin
    Exit;
  end;
  if AStart.Line = AEnd.Line then
  begin
    Exit(Copy(ALines[AStart.Line], AStart.Character + 1, AEnd.Character - AStart.Character));
  end;
  Result := Copy(ALines[AStart.Line], AStart.Character + 1, MaxInt);
  for Line := AStart.Line + 1 to AEnd.Line - 1 do
  begin
    Result := Result + #10 + ALines[Line];
  end;
  Result := Result + #10 + Copy(ALines[AEnd.Line], 1, AEnd.Character);
end;

function Clamp(const ALines: TArray<string>; const APos: TLspTextPosition): TLspTextPosition;
begin
  Result := APos;
  if Length(ALines) = 0 then
  begin
    Exit(Pos2(0, 0));
  end;
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
    begin
      AStart := Pos2(AStart.Line + 1, 0);
    end
    else if CharInSet(ALines[AStart.Line][AStart.Character + 1], [' ', #9]) then
    begin
      Inc(AStart.Character);
    end
    else
    begin
      Break;
    end;
  end;
  // Hinten ebenso rückwärts.
  while Cmp(AStart, AEnd) < 0 do
  begin
    if AEnd.Character = 0 then
    begin
      AEnd := Pos2(AEnd.Line - 1, Length(ALines[AEnd.Line - 1]));
    end
    else if CharInSet(ALines[AEnd.Line][AEnd.Character], [' ', #9]) then
    begin
      Dec(AEnd.Character);
    end
    else
    begin
      Break;
    end;
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
  begin
    Inc(Result.Character, ALength);
  end;
end;

/// <summary>Löschen von ALength Zeichen in ALine ab AAt.</summary>
function AfterDelete(const APos: TLspTextPosition; ALine, AAt, ALength: Integer): TLspTextPosition;
begin
  Result := APos;
  if (APos.Line <> ALine) or (APos.Character <= AAt) then
  begin
    Exit;
  end;
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
  begin
    if (Span.Kind in [TAtlasCommentSpanKind.BraceComment, TAtlasCommentSpanKind.ParenComment]) and
      (Cmp(Span.StartPos, APos) <= 0) and (Cmp(APos, Span.EndPos) <= 0) then
    begin
      ASpan := Span;
      Exit(True);
    end;
  end;
  Result := False;
end;

type
  TStatementStep = (Include, StopBefore, StopAfter);

  /// <summary>Vorwärts bis zum Semikolon derselben Ebene: Klammern, Blöcke und if … else.</summary>
  TStatementScan = record
    Depth: Integer;
    Blocks: Integer;
    Ifs: Integer;
    function OuterStep(const AToken: TAtlasCodeToken): TStatementStep;
    function LevelStep(const AToken: TAtlasCodeToken): TStatementStep;
    function Step(const AToken: TAtlasCodeToken): TStatementStep;
  end;

function TStatementScan.OuterStep(const AToken: TAtlasCodeToken): TStatementStep;
begin
  Result := TStatementStep.Include;
  if IsWord(AToken, 'if') then
  begin
    Inc(Ifs);
  end
  else if IsWord(AToken, 'else') and (Ifs > 0) then
  begin
    Dec(Ifs);
  end
  else if IsWord(AToken, 'else') or IsWord(AToken, 'except') or IsWord(AToken, 'finally') then
  begin
    Result := TStatementStep.StopBefore;
  end
  else if AToken.Text = ';' then
  begin
    Result := TStatementStep.StopAfter;
  end;
end;

function TStatementScan.LevelStep(const AToken: TAtlasCodeToken): TStatementStep;
begin
  Result := TStatementStep.Include;
  if AToken.IsWord and IsOneOf(AToken.Text, ['begin', 'case', 'try', 'asm', 'record', 'repeat']) then
  begin
    Inc(Blocks);
  end
  else if IsWord(AToken, 'end') or IsWord(AToken, 'until') then
  begin
    if Blocks = 0 then
    begin
      Result := TStatementStep.StopBefore;
    end
    else
    begin
      Dec(Blocks);
    end;
  end
  else if Blocks = 0 then
  begin
    Result := OuterStep(AToken);
  end;
end;

function TStatementScan.Step(const AToken: TAtlasCodeToken): TStatementStep;
begin
  Result := TStatementStep.Include;
  if IsOneOf(AToken.Text, ['(', '[']) then
  begin
    Inc(Depth);
  end
  else if IsOneOf(AToken.Text, [')', ']']) then
  begin
    Depth := Max(Depth - 1, 0);
  end
  else if Depth = 0 then
  begin
    Result := LevelStep(AToken);
  end;
end;

/// <summary>Token am Cursor, sonst das nächste bzw. letzte der Cursorzeile; -1 ohne.</summary>
function TokenAtCursor(const AList: TArray<TAtlasCodeToken>; const ACursor: TLspTextPosition): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(AList) do
  begin
    if AList[mIndex].StartPos.Line <> ACursor.Line then
    begin
      Continue;
    end;
    if Cmp(AList[mIndex].StartPos, ACursor) > 0 then
    begin
      if (Result < 0) or (Cmp(AList[Result].EndPos, ACursor) < 0) then
      begin
        Result := mIndex;
      end;
      Break;
    end;
    Result := mIndex;
  end;
end;

/// <summary>Rückwärts bis hinter das vorige Semikolon bzw. Schlüsselwort, Klammern übersprungen.</summary>
function StatementFirst(const AList: TArray<TAtlasCodeToken>; ACurrent: Integer): Integer;
var
  mDepth: Integer;
  mToken: TAtlasCodeToken;
begin
  Result := ACurrent;
  mDepth := 0;
  while Result > 0 do
  begin
    mToken := AList[Result - 1];
    if IsOneOf(mToken.Text, [')', ']']) then
    begin
      Inc(mDepth);
    end
    else if IsOneOf(mToken.Text, ['(', '[']) and (mDepth > 0) then
    begin
      Dec(mDepth);
    end
    else if (mDepth = 0) and IsStatementStart(mToken) then
    begin
      Break;
    end;
    Dec(Result);
  end;
end;

/// <summary>Ende der Anweisung ab AFirst (Anfang AStart).</summary>
function StatementEnd(const AList: TArray<TAtlasCodeToken>; AFirst: Integer;
  const AStart: TLspTextPosition): TLspTextPosition;
var
  mScan: TStatementScan;
  mStep: TStatementStep;
  mIndex: Integer;
begin
  Result := AStart;
  mScan := Default(TStatementScan);
  mIndex := AFirst;
  mStep := TStatementStep.Include;
  while (mStep = TStatementStep.Include) and (mIndex <= High(AList)) do
  begin
    mStep := mScan.Step(AList[mIndex]);
    if mStep <> TStatementStep.StopBefore then
    begin
      Result := AList[mIndex].EndPos;
    end;
    Inc(mIndex);
  end;
end;

class function TAtlasBlockComment.StatementRange(const ALines: TArray<string>; const ACursor: TLspTextPosition;
  out AStart, AEnd: TLspTextPosition): Boolean;
var
  mList: TArray<TAtlasCodeToken>;
  mCurrent, mFirst: Integer;
begin
  AStart := ACursor;
  AEnd := ACursor;
  mList := Tokens(ALines);
  mCurrent := TokenAtCursor(mList, ACursor);
  if mCurrent < 0 then
  begin
    Exit(False);
  end;
  // Direkt hinter dem Semikolon: die Anweisung davor.
  if (mList[mCurrent].Text = ';') and (mCurrent > 0) and (mList[mCurrent - 1].StartPos.Line = ACursor.Line) then
  begin
    Dec(mCurrent);
  end;
  mFirst := StatementFirst(mList, mCurrent);
  AStart := mList[mFirst].StartPos;
  AEnd := StatementEnd(mList, mFirst, AStart);
  Result := Cmp(AStart, AEnd) < 0;
end;

/// <summary>Anfang und Ende eines Blockkommentars dieser Art; Ergebnis: Länge der Zeichen.</summary>
function Delimiters(AKind: TAtlasCommentSpanKind; out AOpener, ACloser: string): Integer;
begin
  Result := 1;
  AOpener := '{';
  ACloser := '}';
  if AKind = TAtlasCommentSpanKind.ParenComment then
  begin
    Result := 2;
    AOpener := '(*';
    ACloser := '*)';
  end;
end;

/// <summary>APos nach dem Löschen der Zeilen AOpenLine und ACloseLine.</summary>
function AfterLineRemoval(const APos: TLspTextPosition; AOpenLine, ACloseLine: Integer): TLspTextPosition;
begin
  Result := APos;
  Result.Line := APos.Line - Ord(APos.Line > AOpenLine) - Ord(APos.Line > ACloseLine);
  if (APos.Line = AOpenLine) or (APos.Line = ACloseLine) then
  begin
    Result.Character := 0;
  end;
end;

/// <summary>Eigene Zeilen: beide Zeilen entfallen.</summary>
function RemoveOwnLines(const ALines: TArray<string>; AOpenLine, ACloseLine: Integer; const AStart,
  AEnd: TLspTextPosition): TAtlasBlockCommentResult;
var
  mLines: TArray<string>;
begin
  mLines := Copy(ALines);
  Delete(mLines, ACloseLine, 1);
  Delete(mLines, AOpenLine, 1);
  Result.Kind := TAtlasBlockCommentKind.Removed;
  Result.Lines := mLines;
  Result.SelectionStart := Clamp(mLines, AfterLineRemoval(AStart, AOpenLine, ACloseLine));
  Result.SelectionEnd := Clamp(mLines, AfterLineRemoval(AEnd, AOpenLine, ACloseLine));
end;

/// <summary>Anfang und Ende des Kommentars samt unserem Leerzeichen innen entfernen.</summary>
function RemoveDelimiters(const ALines: TArray<string>; const ASpan: TAtlasCommentSpan; ASize: Integer;
  const AStart, AEnd: TLspTextPosition): TAtlasBlockCommentResult;
var
  mLines: TArray<string>;
  mOpenLine, mOpenAt, mOpenLength, mCloseLine, mCloseAt, mCloseLength: Integer;
  mStart, mEnd: TLspTextPosition;
begin
  mLines := Copy(ALines);
  mOpenLine := ASpan.StartPos.Line;
  mCloseLine := ASpan.EndPos.Line;
  mOpenAt := ASpan.StartPos.Character;
  mOpenLength := ASize;
  mCloseAt := ASpan.EndPos.Character - ASize;
  mCloseLength := ASize;
  // Unser Leerzeichen hinter dem Anfang und vor dem Ende, ohne dass sich beide überschneiden.
  if (mOpenAt + ASize < Length(mLines[mOpenLine])) and (mLines[mOpenLine][mOpenAt + ASize + 1] = ' ') and
    ((mOpenLine <> mCloseLine) or (mOpenAt + ASize < mCloseAt)) then
  begin
    Inc(mOpenLength);
  end;
  if (mCloseAt > 0) and (mLines[mCloseLine][mCloseAt] = ' ') and
    ((mOpenLine <> mCloseLine) or (mCloseAt - 1 >= mOpenAt + mOpenLength)) then
  begin
    Dec(mCloseAt);
    Inc(mCloseLength);
  end;
  // Erst das Ende, dann der Anfang.
  Delete(mLines[mCloseLine], mCloseAt + 1, mCloseLength);
  mStart := AfterDelete(AStart, mCloseLine, mCloseAt, mCloseLength);
  mEnd := AfterDelete(AEnd, mCloseLine, mCloseAt, mCloseLength);
  Delete(mLines[mOpenLine], mOpenAt + 1, mOpenLength);
  mStart := AfterDelete(mStart, mOpenLine, mOpenAt, mOpenLength);
  mEnd := AfterDelete(mEnd, mOpenLine, mOpenAt, mOpenLength);
  Result.Kind := TAtlasBlockCommentKind.Removed;
  Result.Lines := mLines;
  Result.SelectionStart := Clamp(mLines, mStart);
  Result.SelectionEnd := Clamp(mLines, mEnd);
end;

function RemoveComment(const ALines: TArray<string>; const ASpan: TAtlasCommentSpan; const AStart,
  AEnd: TLspTextPosition): TAtlasBlockCommentResult;
var
  mSize, mOpenLine, mCloseLine: Integer;
  mOpener, mCloser: string;
begin
  mSize := Delimiters(ASpan.Kind, mOpener, mCloser);
  mOpenLine := ASpan.StartPos.Line;
  mCloseLine := ASpan.EndPos.Line;
  if (mOpenLine < mCloseLine) and (Trim(ALines[mOpenLine]) = mOpener) and (Trim(ALines[mCloseLine]) = mCloser) then
  begin
    Result := RemoveOwnLines(ALines, mOpenLine, mCloseLine, AStart, AEnd);
  end
  else
  begin
    Result := RemoveDelimiters(ALines, ASpan, mSize, AStart, AEnd);
  end;
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
    begin
      Continue;
    end;
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
  begin
    if (Span.Kind = TAtlasCommentSpanKind.Directive) and (Cmp(Span.StartPos, AStart) = 0) and
      (Cmp(Span.EndPos, AEnd) = 0) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Text, der in den Kommentar kommt: bei eigenen Zeilen die ganzen Zeilen.</summary>
function CommentText(const ALines: TArray<string>; const AFrom, ATo: TLspTextPosition; AOwnLines: Boolean): string;
begin
  if AOwnLines then
  begin
    Result := TextOf(ALines, Pos2(AFrom.Line, 0), Pos2(ATo.Line, Length(ALines[ATo.Line])));
  end
  else
  begin
    Result := TextOf(ALines, AFrom, ATo);
  end;
end;

/// <summary>Kommentarzeichen, die im Text AText nicht vorkommen; False, wenn beide Arten vorkommen.</summary>
function ChooseDelimiters(const AText: string; const AOptions: TAtlasBlockCommentOptions;
  out AOpener, ACloser: string): Boolean;
var
  mCanBraces, mCanParens: Boolean;
begin
  mCanBraces := Pos('}', AText) = 0;
  mCanParens := Pos('*)', AText) = 0;
  Result := mCanBraces or mCanParens;
  AOpener := '(*';
  ACloser := '*)';
  if mCanBraces and ((AOptions.Style = TAtlasBlockCommentStyle.Braces) or not mCanParens) then
  begin
    AOpener := '{';
    ACloser := '}';
  end;
end;

/// <summary>Anfang und Ende auf eigenen Zeilen um AFirst bis ALast; die Markierung bleibt auf den Zeilen dazwischen.
/// </summary>
procedure WrapOwnLines(var AResult: TAtlasBlockCommentResult; AFirst, ALast: Integer;
  const AOpener, ACloser: string);
var
  mIndent: string;
begin
  mIndent := Copy(AResult.Lines[AFirst], 1, LeadingSpace(AResult.Lines[AFirst]));
  Insert(mIndent + ACloser, AResult.Lines, ALast + 1);
  Insert(mIndent + AOpener, AResult.Lines, AFirst);
  if (AResult.SelectionEnd.Line = ALast + 1) and (AResult.SelectionEnd.Character = 0) then
  begin
    AResult.SelectionEnd.Line := ALast + 2;
  end
  else
  begin
    AResult.SelectionEnd.Line := AResult.SelectionEnd.Line + Ord(AResult.SelectionEnd.Line >= AFirst) +
      Ord(AResult.SelectionEnd.Line > ALast);
  end;
  AResult.SelectionStart.Line := AResult.SelectionStart.Line + Ord(AResult.SelectionStart.Line >= AFirst) +
    Ord(AResult.SelectionStart.Line > ALast);
end;

/// <summary>Erst das Ende, dann der Anfang; je ein Leerzeichen innen.</summary>
procedure WrapInline(var AResult: TAtlasBlockCommentResult; const AFrom, ATo: TLspTextPosition; const AOpener,
  ACloser: string);
begin
  Insert(' ' + ACloser, AResult.Lines[ATo.Line], ATo.Character + 1);
  AResult.SelectionStart := AfterInsert(AResult.SelectionStart, ATo.Line, ATo.Character, Length(ACloser) + 1, False);
  AResult.SelectionEnd := AfterInsert(AResult.SelectionEnd, ATo.Line, ATo.Character, Length(ACloser) + 1, False);
  Insert(AOpener + ' ', AResult.Lines[AFrom.Line], AFrom.Character + 1);
  AResult.SelectionStart := AfterInsert(AResult.SelectionStart, AFrom.Line, AFrom.Character, Length(AOpener) + 1,
    True);
  AResult.SelectionEnd := AfterInsert(AResult.SelectionEnd, AFrom.Line, AFrom.Character, Length(AOpener) + 1, True);
end;

function AddComment(const ALines: TArray<string>; const AFrom, ATo, ASelectionStart,
  ASelectionEnd: TLspTextPosition; const AOptions: TAtlasBlockCommentOptions): TAtlasBlockCommentResult;
var
  mOpener, mCloser: string;
  mOwnLines: Boolean;
begin
  Result.Kind := TAtlasBlockCommentKind.Refused;
  Result.Lines := ALines;
  Result.SelectionStart := ASelectionStart;
  Result.SelectionEnd := ASelectionEnd;
  mOwnLines := AOptions.OwnLines and (AFrom.Line < ATo.Line);
  // Nur eine Direktive: mit // auskommentieren, damit kein Kommentar entsteht, der wie eine Direktive aussieht.
  if IsOnlyDirective(ALines, AFrom, ATo) or
    not ChooseDelimiters(CommentText(ALines, AFrom, ATo, mOwnLines), AOptions, mOpener, mCloser) then
  begin
    if IsOnlyDirective(ALines, AFrom, ATo) or (AOptions.Fallback <> TAtlasBlockCommentFallback.Refuse) then
    begin
      Result := AddLineComments(ALines, AFrom.Line, ATo.Line, ASelectionStart, ASelectionEnd);
    end;
    Exit;
  end;
  Result.Kind := TAtlasBlockCommentKind.Added;
  Result.Lines := Copy(ALines);
  if mOwnLines then
  begin
    WrapOwnLines(Result, AFrom.Line, ATo.Line, mOpener, mCloser);
  end
  else
  begin
    WrapInline(Result, AFrom, ATo, mOpener, mCloser);
  end;
end;

/// <summary>Bereich für den Cursor ohne Markierung: die Anweisung bzw. die Zeile, ohne Leerraum am Rand.</summary>
function CursorRange(const ALines: TArray<string>; const ACursor: TLspTextPosition;
  const AOptions: TAtlasBlockCommentOptions; out AFrom, ATill: TLspTextPosition): Boolean;
var
  mLine: string;
begin
  if (AOptions.Scope = TAtlasBlockCommentScope.Line) or
    not TAtlasBlockComment.StatementRange(ALines, ACursor, AFrom, ATill) then
  begin
    mLine := ALines[ACursor.Line];
    AFrom := Pos2(ACursor.Line, LeadingSpace(mLine));
    ATill := Pos2(ACursor.Line, Length(TrimRight(mLine)));
  end;
  Result := TrimRange(ALines, AFrom, ATill);
end;

/// <summary>Markierung innerhalb von ALines, Anfang vor Ende.</summary>
procedure OrderSelection(const ALines: TArray<string>; const ASelectionStart, ASelectionEnd: TLspTextPosition;
  out AStart, AEnd: TLspTextPosition);
begin
  AStart := Clamp(ALines, ASelectionStart);
  AEnd := Clamp(ALines, ASelectionEnd);
  if Cmp(AEnd, AStart) < 0 then
  begin
    AStart := Clamp(ALines, ASelectionEnd);
    AEnd := Clamp(ALines, ASelectionStart);
  end;
end;

class function TAtlasBlockComment.Toggle(const ALines: TArray<string>; const ASelectionStart,
  ASelectionEnd: TLspTextPosition; const AOptions: TAtlasBlockCommentOptions): TAtlasBlockCommentResult;
var
  mStart, mEnd, mFrom, mTill: TLspTextPosition;
  mSpan: TAtlasCommentSpan;
  mInComment, mFound: Boolean;
begin
  Result := Default(TAtlasBlockCommentResult);
  Result.Lines := ALines;
  if Length(ALines) = 0 then
  begin
    Exit;
  end;
  OrderSelection(ALines, ASelectionStart, ASelectionEnd, mStart, mEnd);
  Result.SelectionStart := mStart;
  Result.SelectionEnd := mEnd;
  mFrom := mStart;
  mTill := mEnd;
  if Cmp(mStart, mEnd) < 0 then
  begin
    mFound := TrimRange(ALines, mFrom, mTill);
    // In einem Blockkommentar: ihn entfernen.
    mInComment := mFound and CommentAt(ALines, mFrom, mSpan) and (Cmp(mTill, mSpan.EndPos) <= 0);
  end
  else
  begin
    mInComment := CommentAt(ALines, mStart, mSpan);
    mFound := mInComment or CursorRange(ALines, mStart, AOptions, mFrom, mTill);
  end;
  if mInComment then
  begin
    Result := RemoveComment(ALines, mSpan, mStart, mEnd);
  end
  else if mFound then
  begin
    Result := AddComment(ALines, mFrom, mTill, mStart, mEnd, AOptions);
  end;
end;

class function TAtlasBlockComment.StyleOf(const AValue: string): TAtlasBlockCommentStyle;
begin
  Result := TAtlasBlockCommentStyle.Braces;
  if SameText(AValue, 'parens') then
  begin
    Result := TAtlasBlockCommentStyle.Parens;
  end;
end;

class function TAtlasBlockComment.FallbackOf(const AValue: string): TAtlasBlockCommentFallback;
begin
  Result := TAtlasBlockCommentFallback.LineComments;
  if SameText(AValue, 'refuse') then
  begin
    Result := TAtlasBlockCommentFallback.Refuse;
  end;
end;

class function TAtlasBlockComment.ScopeOf(const AValue: string): TAtlasBlockCommentScope;
begin
  Result := TAtlasBlockCommentScope.Statement;
  if SameText(AValue, 'line') then
  begin
    Result := TAtlasBlockCommentScope.Line;
  end;
end;

end.
