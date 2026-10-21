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
    Exit;
  for Word in AWords do
    if AToken.Text = Word then
      Exit(True);
end;

function IsWord(const AToken: TAtlasCodeToken; const AWord: string): Boolean;
begin
  Result := AToken.IsWord and (AToken.Text = AWord);
end;

/// <summary>Kopf eines Typs, der einen Block öffnet: "record", "= class", "= interface", "packed object" …,
/// nicht "= class;", "= class(TBase);" (Vorwärtsdeklaration, kurze Klasse) und "= class of".</summary>
function IsTypeOpener(const ATokens: TCodeTokens; AIndex: Integer): Boolean;
var
  Word: string;
  Next, Depth: Integer;
begin
  Result := False;
  if not ATokens[AIndex].IsWord then
    Exit;
  Word := ATokens[AIndex].Text;
  if Word = 'record' then
    Exit(True);
  if (Word <> 'class') and (Word <> 'interface') and (Word <> 'dispinterface') and (Word <> 'object') then
    Exit;
  if (AIndex = 0) or not ((ATokens[AIndex - 1].Text = '=') or IsWord(ATokens[AIndex - 1], 'packed')) then
    Exit;
  Next := AIndex + 1;
  if (Next <= High(ATokens)) and (ATokens[Next].Text = '(') then
  begin
    Depth := 0;
    while Next <= High(ATokens) do
    begin
      if ATokens[Next].Text = '(' then
        Inc(Depth)
      else if ATokens[Next].Text = ')' then
        Dec(Depth);
      Inc(Next);
      if Depth = 0 then
        Break;
    end;
  end;
  Result := (Next > High(ATokens)) or not ((ATokens[Next].Text = ';') or IsWord(ATokens[Next], 'of'));
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
      Depth := Max(0, Depth - 1);
    Result[Index] := Depth;
    if (ATokens[Index].Text = '(') or (ATokens[Index].Text = '[') then
      Inc(Depth);
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
    if ATokens[Index].StartPos.Line = ALine then
    begin
      if AFirst < 0 then
        AFirst := Index;
      ALast := Index;
    end
    else if ATokens[Index].StartPos.Line > ALine then
      Break;
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
    Dec(AStart);
  AStop := High(ATokens);
  for Index := AIndex to High(ATokens) do
  begin
    if ADepths[Index] > 0 then
      Continue;
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
    Inc(Index);
  Result := Copy(ALine, 1, Index - 1);
end;

/// <summary>Unterhalb von ALine eine Ebene tiefer?</summary>
function IndentsBelow(const ATokens: TCodeTokens; ALine: Integer): Boolean;
var
  First, Last, Index: Integer;
begin
  Result := False;
  if not LineTokens(ATokens, ALine, First, Last) then
    Exit;
  if InList(ATokens[Last], IndentOpeners) then
    Exit(True);
  if IsWord(ATokens[Last], 'of') then
  begin
    for Index := First to Last do
      if IsWord(ATokens[Index], 'case') then
        Exit(True);
    Exit;
  end;
  if ATokens[Last].Text = ';' then
    Exit;
  for Index := First to Last do
    if IsTypeOpener(ATokens, Index) then
      Exit(True);
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
    if (Span.Kind in [TAtlasCommentSpanKind.BraceComment, TAtlasCommentSpanKind.ParenComment]) and
      (Span.StartPos.Line < ALine) and (Span.EndPos.Line >= ALine) then
      Exit(True);
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
    Exit;
  Index := 1;
  while (Index <= Length(Rest)) and (Rest[Index] = '/') do
    Inc(Index);
  while (Index <= Length(Rest)) and CharInSet(Rest[Index], [' ', #9]) do
    Inc(Index);
  APrefix := Indent + Copy(Rest, 1, Index - 1);
end;

function InsertLine(const ALines: TArray<string>; AIndex: Integer; const AText: string): TArray<string>;
begin
  Result := Copy(ALines, 0, AIndex) + [AText] + Copy(ALines, AIndex, MaxInt);
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
    Exit;
  if ADirection = TAtlasNewLineDirection.Below then
    Extent(Tokens, DepthsOf(Tokens), Last, Start, Stop)
  else
    Extent(Tokens, DepthsOf(Tokens), First, Start, Stop);
  AFirstLine := Tokens[Start].StartPos.Line;
  ALastLine := Tokens[Stop].StartPos.Line;
end;

class function TAtlasNewLine.Insert(const ALines: TArray<string>; ALine: Integer;
  ADirection: TAtlasNewLineDirection; const AOptions: TAtlasNewLineOptions): TAtlasNewLineResult;
var
  Lines, Probe: TArray<string>;
  Tokens: TCodeTokens;
  Line, RefLine, BaseLine, Target, Character, First, Last: Integer;
  Text, Prefix: string;
  Edit: TAtlasCommentEdit;
  HasCode, Done: Boolean;
begin
  Lines := ALines;
  if Length(Lines) = 0 then
    Lines := [''];
  Line := EnsureRange(ALine, 0, High(Lines));
  Tokens := TAtlasBlockComment.Tokens(Lines);
  RefLine := Line;
  BaseLine := Line;
  HasCode := LineTokens(Tokens, Line, First, Last);
  if HasCode and AOptions.StatementAware then
    StatementLines(Lines, Line, ADirection, BaseLine, RefLine);
  if ADirection = TAtlasNewLineDirection.Above then
    RefLine := BaseLine;
  Done := False;
  Character := -1;
  if ADirection = TAtlasNewLineDirection.Below then
  begin
    Target := RefLine + 1;
    if AOptions.ContinueComments then
    begin
      // Wie Enter am Ende der Bezugszeile, nur die neue Zeile darf sich ändern.
      Probe := InsertLine(Lines, Target, '');
      Done := TAtlasCommentContinuation.OnEnter(string.Join(#10, Probe), Target, 0, AOptions.Comments, Edit) and
        (Edit.StartLine = Target) and (Edit.OldCount = 1) and (Length(Edit.Lines) = 1) and
        (Edit.CursorLine = Target);
      if Done then
      begin
        Text := Edit.Lines[0];
        Character := Edit.CursorCharacter;
      end;
    end;
    if not Done then
    begin
      Text := LeadingWhitespace(Lines[BaseLine]);
      if IndentsBelow(Tokens, RefLine) then
        Text := Text + StringOfChar(' ', Max(0, AOptions.IndentWidth));
    end;
  end
  else
  begin
    Target := RefLine;
    if AOptions.ContinueComments and not HasCode then
    begin
      Done := LineCommentPrefix(Lines[RefLine], AOptions.Comments.LineComments, Prefix);
      if Done then
        Text := Prefix
      else if InsideBlockComment(Lines, RefLine) then
      begin
        Text := LeadingWhitespace(Lines[RefLine]);
        Done := True;
      end;
    end;
    if not Done then
    begin
      Text := LeadingWhitespace(Lines[RefLine]);
      if IndentsAbove(Tokens, RefLine) then
        Text := Text + StringOfChar(' ', Max(0, AOptions.IndentWidth));
    end;
  end;
  if Character < 0 then
    Character := Length(Text);
  Result.Lines := InsertLine(Lines, Target, Text);
  Result.Line := Target;
  Result.Text := Text;
  Result.Cursor := TLspTextPosition.Create(Target, Character);
end;

end.
