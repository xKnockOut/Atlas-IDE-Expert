unit Atlas.Core.Editor.NewLine;

// Neue Zeile ober- oder unterhalb (#700), ohne VCL und Open Tools API.
// Umschalt+Enter fügt unter der Cursorzeile eine Zeile ein, Strg+Alt+Enter
// darüber; die Cursorzeile bleibt unverändert, der Cursor steht am Ende der
// neuen Zeile.
// - Einzug unterhalb: wie die Bezugszeile, eine Ebene tiefer nach then, do,
//   begin, try, else, repeat, except, finally, asm, record, var, const,
//   type, uses, label, nach "case … of", nach private/protected/public/
//   published und nach einem Klassenkopf ("TFoo = class(TBar)").
// - Einzug oberhalb: wie die Bezugszeile, eine Ebene tiefer vor end, until,
//   except, finally, else und den Sichtbarkeiten (so tief wie der Inhalt
//   des Blocks davor).
// - StatementAware: Reicht die Anweisung über mehrere Zeilen (Aufruf mit
//   Argumenten in Folgezeilen), ist unterhalb ihre letzte Zeile die
//   Bezugszeile, oberhalb ihre erste; der Einzug kommt von ihrer ersten
//   Zeile. Ohne StatementAware gilt immer die Cursorzeile.
// - ContinueComments (#696 an): In "//"-Zeilen und offenen Blockkommentaren
//   setzt die neue Zeile den Kommentar fort; unterhalb genau wie Enter
//   (Atlas.Core.Editor.CommentContinuation), oberhalb mit Einzug und
//   "//" bzw. "///" samt Abstand der Cursorzeile.
// Anweisungsgrenzen: Semikolon und die Schlüsselwörter oben auf Klammerebene
// 0; Kommentare, Direktiven und Strings zählen nicht (Lexer aus
// Atlas.Core.Editor.BlockComment).

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Editor.CommentContinuation;

type
{$SCOPEDENUMS ON}
  TAtlasNewLineDirection = (Below, Above);
{$SCOPEDENUMS OFF}

  TAtlasNewLineOptions = record
    /// <summary>Eine Einzugsebene in Zeichen (Blockeinzug der IDE).</summary>
    IndentWidth: Integer;
    /// <summary>Mehrzeilige Anweisungen als Ganzes (keys.newLineAround.statementAware).</summary>
    StatementAware: Boolean;
    /// <summary>Kommentare fortsetzen (#696 an).</summary>
    ContinueComments: Boolean;
    Comments: TAtlasCommentOptions;
    /// <summary>Vorgaben: Einzug 2, StatementAware, Kommentare fortsetzen.</summary>
    class function Defaults: TAtlasNewLineOptions; static;
  end;

  TAtlasNewLineResult = record
    /// <summary>Text mit der neuen Zeile.</summary>
    Lines: TArray<string>;
    /// <summary>Index der neuen Zeile in Lines (0-basiert).</summary>
    Line: Integer;
    /// <summary>Inhalt der neuen Zeile (Einzug, gegebenenfalls Kommentarpräfix).</summary>
    Text: string;
    /// <summary>Cursor danach.</summary>
    Cursor: TLspTextPosition;
  end;

  TAtlasNewLine = class
  public
    /// <summary>Fügt neben der Cursorzeile ALine (0-basiert) eine Zeile ein.</summary>
    class function Insert(const ALines: TArray<string>; ALine: Integer; ADirection: TAtlasNewLineDirection;
      const AOptions: TAtlasNewLineOptions): TAtlasNewLineResult; static;
    /// <summary>Erste und letzte Zeile der Anweisung, zu der unterhalb das letzte bzw. oberhalb das erste Token
    /// der Zeile ALine gehört; False ohne Code in ALine (dann beide ALine).</summary>
    class function StatementLines(const ALines: TArray<string>; ALine: Integer; ADirection: TAtlasNewLineDirection;
      out AFirstLine, ALastLine: Integer): Boolean; static;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Editor.BlockComment;

const
  // Öffnen einen Block bzw. Abschnitt: Grenze der Anweisung (eingeschlossen) und unterhalb eine Ebene tiefer.
  IndentOpeners: array[0..20] of string = ('begin', 'then', 'else', 'do', 'try', 'finally', 'except', 'repeat',
    'asm', 'record', 'private', 'protected', 'public', 'published', 'var', 'const', 'type', 'uses', 'label',
    'resourcestring', 'threadvar');
  // Weitere Grenzen ohne eigenen Einzug.
  OtherBoundaries: array[0..5] of string = ('of', 'end', 'initialization', 'finalization', 'implementation',
    'interface');
  // Schließen den Block davor: Anweisung endet vor ihnen, oberhalb eine Ebene tiefer.
  Closers: array[0..9] of string = ('end', 'until', 'except', 'finally', 'else', 'private', 'protected', 'public',
    'published', 'strict');

type
  TCodeTokens = TArray<TAtlasCodeToken>;

function InList(const AToken: TAtlasCodeToken; const AWords: array of string): Boolean;
var
  Word: string;
begin
  Result := False;
  if not AToken.IsWord then
  begin
    Exit;
  end;
  for Word in AWords do
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

/// <summary>Hinter einer Klammergruppe ab AIndex (wenn dort "(" steht), sonst AIndex.</summary>
function SkipParens(const ATokens: TCodeTokens; AIndex: Integer): Integer;
var
  mDepth: Integer;
  mDone: Boolean;
begin
  Result := AIndex;
  if (Result <= High(ATokens)) and (ATokens[Result].Text = '(') then
  begin
    mDepth := 0;
    mDone := False;
    while not mDone and (Result <= High(ATokens)) do
    begin
      if ATokens[Result].Text = '(' then
      begin
        Inc(mDepth);
      end
      else if ATokens[Result].Text = ')' then
      begin
        Dec(mDepth);
      end;
      Inc(Result);
      mDone := mDepth = 0;
    end;
  end;
end;

/// <summary>Kopf eines Typs, der einen Block öffnet: "record", "= class", "= interface", "packed object" …,
/// nicht "= class;", "= class(TBase);" (Vorwärtsdeklaration, kurze Klasse) und "= class of".</summary>
function IsTypeOpener(const ATokens: TCodeTokens; AIndex: Integer): Boolean;
var
  mNext: Integer;
begin
  Result := False;
  if IsWord(ATokens[AIndex], 'record') then
  begin
    Result := True;
  end
  else if InList(ATokens[AIndex], ['class', 'interface', 'dispinterface', 'object']) and (AIndex > 0) and
    ((ATokens[AIndex - 1].Text = '=') or IsWord(ATokens[AIndex - 1], 'packed')) then
  begin
    mNext := SkipParens(ATokens, AIndex + 1);
    Result := (mNext > High(ATokens)) or not ((ATokens[mNext].Text = ';') or IsWord(ATokens[mNext], 'of'));
  end;
end;

function IsOpener(const ATokens: TCodeTokens; AIndex: Integer): Boolean;
begin
  Result := InList(ATokens[AIndex], IndentOpeners) or IsTypeOpener(ATokens, AIndex);
end;

function IsBoundary(const ATokens: TCodeTokens; AIndex: Integer): Boolean;
begin
  Result := (ATokens[AIndex].Text = ';') or IsOpener(ATokens, AIndex) or InList(ATokens[AIndex], OtherBoundaries);
end;

/// <summary>Klammerebene vor jedem Token; "(" und "[" haben die äußere, ")" und "]" auch.</summary>
function DepthsOf(const ATokens: TCodeTokens): TArray<Integer>;
var
  Index, Depth: Integer;
begin
  SetLength(Result, Length(ATokens));
  Depth := 0;
  for Index := 0 to High(ATokens) do
  begin
    if (ATokens[Index].Text = ')') or (ATokens[Index].Text = ']') then
    begin
      Depth := Max(0, Depth - 1);
    end;
    Result[Index] := Depth;
    if (ATokens[Index].Text = '(') or (ATokens[Index].Text = '[') then
    begin
      Inc(Depth);
    end;
  end;
end;

/// <summary>Erstes und letztes Token in ALine; False ohne.</summary>
function LineTokens(const ATokens: TCodeTokens; ALine: Integer; out AFirst, ALast: Integer): Boolean;
var
  Index: Integer;
begin
  AFirst := -1;
  ALast := -1;
  for Index := 0 to High(ATokens) do
  begin
    if ATokens[Index].StartPos.Line = ALine then
    begin
      if AFirst < 0 then
      begin
        AFirst := Index;
      end;
      ALast := Index;
    end
    else if ATokens[Index].StartPos.Line > ALine then
    begin
      Break;
    end;
  end;
  Result := AFirst >= 0;
end;

/// <summary>Anweisung um das Token AIndex: AStart nach der Grenze davor, AStop bis zur Grenze (eingeschlossen)
/// bzw. vor dem schließenden Schlüsselwort.</summary>
procedure Extent(const ATokens: TCodeTokens; const ADepths: TArray<Integer>; AIndex: Integer;
  out AStart, AStop: Integer);
var
  Index: Integer;
begin
  AStart := AIndex;
  while (AStart > 0) and not ((ADepths[AStart - 1] = 0) and IsBoundary(ATokens, AStart - 1)) do
  begin
    Dec(AStart);
  end;
  AStop := High(ATokens);
  for Index := AIndex to High(ATokens) do
  begin
    if ADepths[Index] > 0 then
    begin
      Continue;
    end;
    if (Index > AIndex) and InList(ATokens[Index], Closers) then
    begin
      AStop := Index - 1;
      Break;
    end;
    if IsBoundary(ATokens, Index) then
    begin
      AStop := Index;
      Break;
    end;
  end;
end;

function LeadingWhitespace(const ALine: string): string;
var
  Index: Integer;
begin
  Index := 1;
  while (Index <= Length(ALine)) and CharInSet(ALine[Index], [' ', #9]) do
  begin
    Inc(Index);
  end;
  Result := Copy(ALine, 1, Index - 1);
end;

/// <summary>Steht unter den Tokens AFirst..ALast das Wort AWord?</summary>
function HasWordIn(const ATokens: TCodeTokens; AFirst, ALast: Integer; const AWord: string): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := AFirst to ALast do
  begin
    Result := Result or IsWord(ATokens[mIndex], AWord);
  end;
end;

/// <summary>Öffnet eines der Tokens AFirst..ALast einen Typ?</summary>
function HasTypeOpener(const ATokens: TCodeTokens; AFirst, ALast: Integer): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := AFirst to ALast do
  begin
    Result := Result or IsTypeOpener(ATokens, mIndex);
  end;
end;

/// <summary>Unterhalb von ALine eine Ebene tiefer?</summary>
function IndentsBelow(const ATokens: TCodeTokens; ALine: Integer): Boolean;
var
  mFirst, mLast: Integer;
begin
  Result := False;
  if LineTokens(ATokens, ALine, mFirst, mLast) then
  begin
    if InList(ATokens[mLast], IndentOpeners) then
    begin
      Result := True;
    end
    else if IsWord(ATokens[mLast], 'of') then
    begin
      Result := HasWordIn(ATokens, mFirst, mLast, 'case');
    end
    else if ATokens[mLast].Text <> ';' then
    begin
      Result := HasTypeOpener(ATokens, mFirst, mLast);
    end;
  end;
end;

/// <summary>Oberhalb von ALine eine Ebene tiefer?</summary>
function IndentsAbove(const ATokens: TCodeTokens; ALine: Integer): Boolean;
var
  First, Last: Integer;
begin
  Result := LineTokens(ATokens, ALine, First, Last) and InList(ATokens[First], Closers);
end;

/// <summary>Liegt der Anfang von ALine in einem Blockkommentar, der davor beginnt?</summary>
function InsideBlockComment(const ALines: TArray<string>; ALine: Integer): Boolean;
var
  Span: TAtlasCommentSpan;
begin
  Result := False;
  for Span in TAtlasBlockComment.Spans(ALines) do
  begin
    if (Span.Kind in [TAtlasCommentSpanKind.BraceComment, TAtlasCommentSpanKind.ParenComment]) and
      (Span.StartPos.Line < ALine) and (Span.EndPos.Line >= ALine) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Präfix einer "//"-Zeile (Einzug, Schrägstriche, Abstand); False, wenn ALine keine ist oder "//"
/// nicht fortgesetzt wird ("///" immer).</summary>
function LineCommentPrefix(const ALine: string; ALineComments: Boolean; out APrefix: string): Boolean;
var
  Indent, Rest: string;
  Index: Integer;
begin
  APrefix := '';
  Indent := LeadingWhitespace(ALine);
  Rest := Copy(ALine, Length(Indent) + 1, MaxInt);
  Result := Rest.StartsWith('///') or (ALineComments and Rest.StartsWith('//'));
  if not Result then
  begin
    Exit;
  end;
  Index := 1;
  while (Index <= Length(Rest)) and (Rest[Index] = '/') do
  begin
    Inc(Index);
  end;
  while (Index <= Length(Rest)) and CharInSet(Rest[Index], [' ', #9]) do
  begin
    Inc(Index);
  end;
  APrefix := Indent + Copy(Rest, 1, Index - 1);
end;

function InsertLine(const ALines: TArray<string>; AIndex: Integer; const AText: string): TArray<string>;
begin
  Result := Copy(ALines, 0, AIndex) + [AText] + Copy(ALines, AIndex, MaxInt);
end;

/// <summary>Wie Enter am Ende der Zeile vor ATarget, nur die neue Zeile ATarget darf sich ändern. False, wenn kein
/// Kommentar fortgesetzt wird.</summary>
function ContinuedComment(const ALines: TArray<string>; ATarget: Integer; const AOptions: TAtlasNewLineOptions;
  out AText: string; out ACharacter: Integer): Boolean;
var
  mEdit: TAtlasCommentEdit;
begin
  AText := '';
  ACharacter := -1;
  Result := TAtlasCommentContinuation.OnEnter(string.Join(#10, InsertLine(ALines, ATarget, '')), ATarget, 0,
    AOptions.Comments, mEdit) and (mEdit.StartLine = ATarget) and (mEdit.OldCount = 1) and
    (Length(mEdit.Lines) = 1) and (mEdit.CursorLine = ATarget);
  if Result then
  begin
    AText := mEdit.Lines[0];
    ACharacter := mEdit.CursorCharacter;
  end;
end;

/// <summary>Neue Zeile unter ARefLine: fortgesetzter Kommentar oder Einzug von ABaseLine (eine Ebene tiefer nach
/// einem Öffner). ACharacter: Cursor, -1 = Zeilenende.</summary>
function BelowText(const ALines: TArray<string>; const ATokens: TCodeTokens; ABaseLine, ARefLine: Integer;
  const AOptions: TAtlasNewLineOptions; out ACharacter: Integer): string;
begin
  ACharacter := -1;
  Result := '';
  if not (AOptions.ContinueComments and ContinuedComment(ALines, ARefLine + 1, AOptions, Result, ACharacter)) then
  begin
    Result := LeadingWhitespace(ALines[ABaseLine]);
    if IndentsBelow(ATokens, ARefLine) then
    begin
      Result := Result + StringOfChar(' ', Max(0, AOptions.IndentWidth));
    end;
  end;
end;

/// <summary>Neue Zeile über ARefLine: Präfix einer "//"-Zeile, Einzug im Blockkommentar oder Einzug von ARefLine
/// (eine Ebene tiefer vor einem Schließer).</summary>
function AboveText(const ALines: TArray<string>; const ATokens: TCodeTokens; ARefLine: Integer; AHasCode: Boolean;
  const AOptions: TAtlasNewLineOptions): string;
var
  mDone: Boolean;
begin
  Result := '';
  mDone := False;
  if AOptions.ContinueComments and not AHasCode then
  begin
    mDone := LineCommentPrefix(ALines[ARefLine], AOptions.Comments.LineComments, Result);
    if not mDone and InsideBlockComment(ALines, ARefLine) then
    begin
      Result := LeadingWhitespace(ALines[ARefLine]);
      mDone := True;
    end;
  end;
  if not mDone then
  begin
    Result := LeadingWhitespace(ALines[ARefLine]);
    if IndentsAbove(ATokens, ARefLine) then
    begin
      Result := Result + StringOfChar(' ', Max(0, AOptions.IndentWidth));
    end;
  end;
end;

{ TAtlasNewLineOptions }

class function TAtlasNewLineOptions.Defaults: TAtlasNewLineOptions;
begin
  Result.IndentWidth := 2;
  Result.StatementAware := True;
  Result.ContinueComments := True;
  Result.Comments := TAtlasCommentOptions.Defaults;
end;

{ TAtlasNewLine }

class function TAtlasNewLine.StatementLines(const ALines: TArray<string>; ALine: Integer;
  ADirection: TAtlasNewLineDirection; out AFirstLine, ALastLine: Integer): Boolean;
var
  Tokens: TCodeTokens;
  First, Last, Start, Stop: Integer;
begin
  AFirstLine := ALine;
  ALastLine := ALine;
  Tokens := TAtlasBlockComment.Tokens(ALines);
  Result := LineTokens(Tokens, ALine, First, Last);
  if not Result then
  begin
    Exit;
  end;
  if ADirection = TAtlasNewLineDirection.Below then
  begin
    Extent(Tokens, DepthsOf(Tokens), Last, Start, Stop);
  end
  else
  begin
    Extent(Tokens, DepthsOf(Tokens), First, Start, Stop);
  end;
  AFirstLine := Tokens[Start].StartPos.Line;
  ALastLine := Tokens[Stop].StartPos.Line;
end;

class function TAtlasNewLine.Insert(const ALines: TArray<string>; ALine: Integer;
  ADirection: TAtlasNewLineDirection; const AOptions: TAtlasNewLineOptions): TAtlasNewLineResult;
var
  mLines: TArray<string>;
  mTokens: TCodeTokens;
  mLine, mRefLine, mBaseLine, mTarget, mCharacter, mFirst, mLast: Integer;
  mText: string;
  mHasCode: Boolean;
begin
  mLines := ALines;
  if Length(mLines) = 0 then
  begin
    mLines := [''];
  end;
  mLine := EnsureRange(ALine, 0, High(mLines));
  mTokens := TAtlasBlockComment.Tokens(mLines);
  mRefLine := mLine;
  mBaseLine := mLine;
  mHasCode := LineTokens(mTokens, mLine, mFirst, mLast);
  if mHasCode and AOptions.StatementAware then
  begin
    StatementLines(mLines, mLine, ADirection, mBaseLine, mRefLine);
  end;
  if ADirection = TAtlasNewLineDirection.Below then
  begin
    mTarget := mRefLine + 1;
    mText := BelowText(mLines, mTokens, mBaseLine, mRefLine, AOptions, mCharacter);
  end
  else
  begin
    mTarget := mBaseLine;
    mCharacter := -1;
    mText := AboveText(mLines, mTokens, mBaseLine, mHasCode, AOptions);
  end;
  if mCharacter < 0 then
  begin
    mCharacter := Length(mText);
  end;
  Result.Lines := InsertLine(mLines, mTarget, mText);
  Result.Line := mTarget;
  Result.Text := mText;
  Result.Cursor := TLspTextPosition.Create(mTarget, mCharacter);
end;

end.
