unit Atlas.Core.Editor.Pairs;

// Klammer- und Blockpaare (#514), ohne Open Tools API: Ein kleiner Lexer
// überspringt Strings, Kommentare und Direktiven und liefert für jede Klammer
// und jedes Blockwort die Verschachtelungstiefe; unpaarige sind markiert.
// - Klammern ( ) [ ] und Blockwörter haben je eine eigene Tiefe.
// - Öffnen: begin, try, case, repeat, asm; class, record, object, interface
//   nur als Typdeklaration (nach "=", record auch nach ":", "of", "packed").
//   class/interface ohne Rumpf (TFoo = class; TFoo = class(TBase);) öffnen nicht,
//   "class function", "procedure of object" ebenso nicht; case im record
//   (variante Teile) teilt sich das end des records.
// - Schließen: end (nicht repeat), until (nur repeat); finally/except
//   bekommen die Tiefe ihres try. "end." ohne Öffner ist das Ende der Unit.
// - Escapte Bezeichner (&begin) und Mitglieder hinter "." sind keine Schlüsselwörter.

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TAtlasPairToken = record
    /// <summary>0-basierte Zeile und Zeichenindex in der Zeile.</summary>
    Line: Integer;
    Character: Integer;
    Length: Integer;
    Depth: Integer;
    Unpaired: Boolean;
    IsWord: Boolean;
  end;

  /// <summary>Gepaarter Block (begin … end, repeat … until, class … end …), 0-basiert.</summary>
  TAtlasPairBlock = record
    OpenLine: Integer;
    OpenCharacter: Integer;
    CloseLine: Integer;
    CloseCharacter: Integer;
    Depth: Integer;
  end;

  TAtlasPairs = class
  public
    /// <summary>Klammern und Blockwörter in AText, nach Position sortiert.</summary>
    class function Analyze(const AText: string): TArray<TAtlasPairToken>; overload; static;
    /// <summary>Wie Analyze; ABlocks erhält zusätzlich die gepaarten Blöcke in der Reihenfolge ihres Endes.</summary>
    class function Analyze(const AText: string; out ABlocks: TArray<TAtlasPairBlock>): TArray<TAtlasPairToken>;
      overload; static;
    /// <summary>Zeile wie im Editor: Tabs bis zur nächsten Tabstelle als Leerzeichen, ohne #13.</summary>
    class function DisplayLine(const ALine: string; ATabWidth: Integer): string; static;
    /// <summary>True, wenn der Textlauf ARun ab der 1-basierten Spalte AColumn in ADisplayLine steht.</summary>
    class function RunMatches(const ADisplayLine, ARun: string; AColumn: Integer): Boolean; static;
    /// <summary>Zeichenindex (0-basiert) in ALine als 1-basierte Editorspalte, Tabs aufgelöst.</summary>
    class function ColumnOf(const ALine: string; ACharacter, ATabWidth: Integer): Integer; static;
  end;

implementation

uses
  System.Generics.Defaults;

type
  TLexToken = record
    Text: string;
    Line: Integer;
    Character: Integer;
    IsWord: Boolean;
    /// <summary>Bezeichner mit & oder hinter einem Punkt: kein Schlüsselwort.</summary>
    Plain: Boolean;
  end;

  TOpen = record
    Word: string;
    Index: Integer;
  end;

function Lex(const AText: string): TArray<TLexToken>;
var
  List: TList<TLexToken>;
  Index, Line, LineStart, Start: Integer;
  Token: TLexToken;
  Escaped: Boolean;

  procedure Add(AStart, ALength: Integer; AIsWord, APlain: Boolean);
  begin
    Token.Text := Copy(AText, AStart, ALength);
    Token.Line := Line;
    Token.Character := AStart - LineStart;
    Token.IsWord := AIsWord;
    Token.Plain := APlain;
    List.Add(Token);
  end;

  procedure NewLine;
  begin
    Inc(Line);
    LineStart := Index + 1;
  end;

begin
  List := TList<TLexToken>.Create;
  try
    Index := 1;
    Line := 0;
    LineStart := 1;
    while Index <= Length(AText) do
    begin
      case AText[Index] of
        #10:
          NewLine;
        '{':
          begin
            while (Index <= Length(AText)) and (AText[Index] <> '}') do
            begin
              if AText[Index] = #10 then
                NewLine;
              Inc(Index);
            end;
          end;
        '/':
          if (Index < Length(AText)) and (AText[Index + 1] = '/') then
          begin
            while (Index < Length(AText)) and (AText[Index + 1] <> #10) do
              Inc(Index);
          end
          else
            Add(Index, 1, False, False);
        '(':
          if (Index < Length(AText)) and (AText[Index + 1] = '*') then
          begin
            Inc(Index, 2);
            while (Index < Length(AText)) and not ((AText[Index] = '*') and (AText[Index + 1] = ')')) do
            begin
              if AText[Index] = #10 then
                NewLine;
              Inc(Index);
            end;
            Inc(Index);
          end
          else
            Add(Index, 1, False, False);
        '''':
          begin
            Inc(Index);
            while (Index <= Length(AText)) and (AText[Index] <> '''') and (AText[Index] <> #10) do
              Inc(Index);
            if (Index <= Length(AText)) and (AText[Index] = #10) then
              Continue;
          end;
        'A'..'Z', 'a'..'z', '_', '&':
          begin
            Escaped := AText[Index] = '&';
            Start := Index;
            if Escaped then
              Inc(Index);
            while (Index <= Length(AText)) and CharInSet(AText[Index], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
              Inc(Index);
            Add(Start, Index - Start, True,
              Escaped or (List.Count > 0) and (List.Last.Text = '.') and (List.Last.Line = Line));
            Continue;
          end;
        '0'..'9', '$', '#':
          begin
            while (Index < Length(AText)) and CharInSet(AText[Index + 1], ['0'..'9', 'A'..'F', 'a'..'f', '$']) do
              Inc(Index);
          end;
        ' ', #9, #13:
          ;
      else
        Add(Index, 1, False, False);
      end;
      Inc(Index);
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function IsKeyword(const AToken: TLexToken; const AWord: string): Boolean;
begin
  Result := AToken.IsWord and not AToken.Plain and SameText(AToken.Text, AWord);
end;

class function TAtlasPairs.DisplayLine(const ALine: string; ATabWidth: Integer): string;
var
  Builder: TStringBuilder;
  Ch: Char;
begin
  Builder := TStringBuilder.Create;
  try
    for Ch in ALine do
      if (Ch = #9) and (ATabWidth > 0) then
        Builder.Append(' ', ATabWidth - Builder.Length mod ATabWidth)
      else if Ch <> #13 then
        Builder.Append(Ch);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TAtlasPairs.RunMatches(const ADisplayLine, ARun: string; AColumn: Integer): Boolean;
begin
  Result := (ARun <> '') and (AColumn >= 1) and (Copy(ADisplayLine, AColumn, Length(ARun)) = ARun);
end;

class function TAtlasPairs.ColumnOf(const ALine: string; ACharacter, ATabWidth: Integer): Integer;
var
  Index: Integer;
begin
  Result := 1;
  for Index := 1 to ACharacter do
    if (Index <= Length(ALine)) and (ALine[Index] = #9) and (ATabWidth > 0) then
      Result := ((Result - 1) div ATabWidth + 1) * ATabWidth + 1
    else
      Inc(Result);
end;

class function TAtlasPairs.Analyze(const AText: string): TArray<TAtlasPairToken>;
var
  Blocks: TArray<TAtlasPairBlock>;
begin
  Result := Analyze(AText, Blocks);
end;

class function TAtlasPairs.Analyze(const AText: string; out ABlocks: TArray<TAtlasPairBlock>): TArray<TAtlasPairToken>;
var
  Tokens: TArray<TLexToken>;
  Results: TList<TAtlasPairToken>;
  Blocks, Brackets: TList<TOpen>;
  Closed: TList<TAtlasPairBlock>;
  Index: Integer;
  Token: TLexToken;
  Word, Previous, Next: string;
  Open: TOpen;

  function Emit(AIndex, ADepth: Integer; AUnpaired: Boolean): Integer;
  var
    Pair: TAtlasPairToken;
  begin
    Pair.Line := Tokens[AIndex].Line;
    Pair.Character := Tokens[AIndex].Character;
    Pair.Length := Length(Tokens[AIndex].Text);
    Pair.Depth := ADepth;
    Pair.Unpaired := AUnpaired;
    Pair.IsWord := Tokens[AIndex].IsWord;
    Result := Results.Add(Pair);
  end;

  function TextAt(AIndex: Integer): string;
  begin
    if (AIndex >= 0) and (AIndex <= High(Tokens)) and not Tokens[AIndex].Plain then
      Result := LowerCase(Tokens[AIndex].Text)
    else
      Result := '';
  end;

  /// <summary>Nach "class(TBase)" bzw. "interface(IBase)": Token hinter der Klammer.</summary>
  function AfterParens(AIndex: Integer): string;
  var
    Depth: Integer;
  begin
    if TextAt(AIndex) <> '(' then
      Exit(TextAt(AIndex));
    Depth := 0;
    while AIndex <= High(Tokens) do
    begin
      if Tokens[AIndex].Text = '(' then
        Inc(Depth)
      else if Tokens[AIndex].Text = ')' then
      begin
        Dec(Depth);
        if Depth = 0 then
          Exit(TextAt(AIndex + 1));
      end;
      Inc(AIndex);
    end;
    Result := '';
  end;

  // Der oberste offene Block endet am Token AIndex.
  procedure CloseBlock(AIndex: Integer);
  var
    Block: TAtlasPairBlock;
  begin
    Block.OpenLine := Results.List[Blocks.Last.Index].Line;
    Block.OpenCharacter := Results.List[Blocks.Last.Index].Character;
    Blocks.Delete(Blocks.Count - 1);
    Block.CloseLine := Tokens[AIndex].Line;
    Block.CloseCharacter := Tokens[AIndex].Character;
    Block.Depth := Blocks.Count;
    Closed.Add(Block);
    Emit(AIndex, Blocks.Count, False);
  end;

  function InRecord: Boolean;
  begin
    Result := (Blocks.Count > 0) and ((Blocks.Last.Word = 'record') or (Blocks.Last.Word = 'class') or
      (Blocks.Last.Word = 'object'));
  end;

  function Opens: Boolean;
  begin
    Previous := TextAt(Index - 1);
    Next := TextAt(Index + 1);
    if (Word = 'begin') or (Word = 'try') or (Word = 'repeat') or (Word = 'asm') then
      Exit(True);
    if Word = 'case' then
      Exit(not InRecord);
    if Word = 'record' then
      Exit((Previous = '=') or (Previous = ':') or (Previous = 'of') or (Previous = 'packed'));
    if (Word = 'class') or (Word = 'interface') or (Word = 'dispinterface') then
      Exit(((Previous = '=') or (Previous = 'packed')) and (Next <> 'of') and (AfterParens(Index + 1) <> ';'));
    if Word = 'object' then
      Exit(Previous = '=');
    Result := False;
  end;

begin
  Tokens := Lex(AText);
  Results := TList<TAtlasPairToken>.Create;
  Blocks := TList<TOpen>.Create;
  Brackets := TList<TOpen>.Create;
  Closed := TList<TAtlasPairBlock>.Create;
  try
    for Index := 0 to High(Tokens) do
    begin
      Token := Tokens[Index];
      if not Token.IsWord then
      begin
        if (Token.Text = '(') or (Token.Text = '[') then
        begin
          Open.Word := Token.Text;
          Open.Index := Emit(Index, Brackets.Count, False);
          Brackets.Add(Open);
        end
        else if (Token.Text = ')') or (Token.Text = ']') then
        begin
          if (Brackets.Count > 0) and ((Brackets.Last.Word = '(') = (Token.Text = ')')) then
          begin
            Brackets.Delete(Brackets.Count - 1);
            Emit(Index, Brackets.Count, False);
          end
          else
            Emit(Index, 0, True);
        end;
        Continue;
      end;
      if Token.Plain then
        Continue;
      Word := LowerCase(Token.Text);
      if Opens then
      begin
        Open.Word := Word;
        Open.Index := Emit(Index, Blocks.Count, False);
        Blocks.Add(Open);
      end
      else if Word = 'end' then
      begin
        if (Blocks.Count > 0) and (Blocks.Last.Word <> 'repeat') then
          CloseBlock(Index)
        else if (Blocks.Count = 0) and (TextAt(Index + 1) = '.') then
          // Ende der Unit bzw. des Programms.
        else
          Emit(Index, 0, True);
      end
      else if Word = 'until' then
      begin
        if (Blocks.Count > 0) and (Blocks.Last.Word = 'repeat') then
          CloseBlock(Index)
        else
          Emit(Index, 0, True);
      end
      else if ((Word = 'finally') or (Word = 'except')) and (Blocks.Count > 0) and (Blocks.Last.Word = 'try') then
        Emit(Index, Blocks.Count - 1, False);
    end;
    // Offen geblieben: unpaarig.
    for Open in Blocks do
      Results.List[Open.Index].Unpaired := True;
    for Open in Brackets do
      Results.List[Open.Index].Unpaired := True;
    Results.Sort(TComparer<TAtlasPairToken>.Construct(
      function(const A, B: TAtlasPairToken): Integer
      begin
        Result := A.Line - B.Line;
        if Result = 0 then
          Result := A.Character - B.Character;
      end));
    Result := Results.ToArray;
    ABlocks := Closed.ToArray;
  finally
    Closed.Free;
    Brackets.Free;
    Blocks.Free;
    Results.Free;
  end;
end;

end.