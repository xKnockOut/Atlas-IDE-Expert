unit Atlas.Core.Editor.CommentContinuation;

// Kommentar beim Enter fortsetzen (#696), ohne Open Tools API. Die IDE hat
// den Zeilenumbruch schon eingefügt; OnEnter bekommt den Text danach und die
// Cursorposition in der neuen Zeile (davor nur Leerraum) und sagt, was sich
// an den beiden Zeilen ändert:
// - "//"-Zeile darüber (nur Kommentar, kein Code davor): Die neue Zeile
//   bekommt Einrückung, "//" bzw. "///" und den Abstand dahinter wie die
//   Zeile darüber. "//" nur mit LineComments, "///" (XMLDoc) immer.
// - Aufzählungen (Lists): "- " und "* " werden übernommen, "1. " bzw. "1) "
//   hochgezählt, auch eingerückte Unterpunkte ("//   - ").
// - Enter mitten im Text: Der Rest steht schon in der neuen Zeile und bekommt
//   das Präfix davor.
// - Zeile darüber nur Präfix ("// "): Atlas entfernt sie samt Präfix wieder,
//   der Cursor steht eingerückt in ihr, der Kommentar ist zu Ende. Nur ein
//   Aufzählungszeichen ("// - "): Es fällt weg, der Kommentar bleibt.
// - In einem offenen { … }- bzw. (* … *)-Block: nur die Einrückung, unter
//   den Text hinter der öffnenden Klammer bzw. wie die Zeile darüber; mit
//   BlockPrefix (etwa " * ") Einrückung der öffnenden Zeile plus Präfix.
// Strings und Kommentare überspringt ein kleiner Lexer vom Dateianfang an;
// Direktiven ({$…}) sind keine Kommentare.

interface

uses
  System.SysUtils;

type
  TAtlasCommentOptions = record
    /// <summary>"//"-Zeilen fortsetzen ("///" immer).</summary>
    LineComments: Boolean;
    /// <summary>Aufzählungszeichen übernehmen und hochzählen.</summary>
    Lists: Boolean;
    /// <summary>Präfix in Blockkommentaren, etwa ' * '; leer = nur Einrückung.</summary>
    BlockPrefix: string;
    class function Defaults: TAtlasCommentOptions; static;
  end;

  /// <summary>Ersetzt OldCount Zeilen ab StartLine durch Lines; danach steht der Cursor in CursorLine,
  /// CursorCharacter (0-basiert).</summary>
  TAtlasCommentEdit = record
    StartLine: Integer;
    OldCount: Integer;
    Lines: TArray<string>;
    CursorLine: Integer;
    CursorCharacter: Integer;
  end;

  TAtlasCommentContinuation = class
  public
    /// <summary>Nach Enter: ALine, ACharacter ist der Cursor in der neuen Zeile. False, wenn nichts zu tun ist.
    /// </summary>
    class function OnEnter(const AText: string; ALine, ACharacter: Integer; const AOptions: TAtlasCommentOptions;
      out AEdit: TAtlasCommentEdit): Boolean; static;
    /// <summary>Text nach dem Aufzählungszeichen am Anfang von AContent ('- ', '* ', '3. ' → '4. '); False ohne.
    /// AMarker: das Zeichen samt Leerraum, wie es in AContent steht.</summary>
    class function ListItem(const AContent: string; out AMarker, ANext: string): Boolean; static;
  end;

implementation

type
  {$SCOPEDENUMS ON}
  TLexState = (Code, Brace, ParenStar);
  {$SCOPEDENUMS OFF}

  /// <summary>Zustand am Anfang einer Zeile und, wenn ein Blockkommentar offen ist, wo er begann.</summary>
  TLineState = record
    State: TLexState;
    OpenLine: Integer;
    OpenCharacter: Integer;
  end;

function LinesOf(const AText: string): TArray<string>;
var
  Index: Integer;
begin
  Result := AText.Split([#10]);
  for Index := 0 to High(Result) do
    if Result[Index].EndsWith(#13) then
      Result[Index] := Copy(Result[Index], 1, Length(Result[Index]) - 1);
end;

function LeadingSpace(const ALine: string): string;
var
  Index: Integer;
begin
  Index := 1;
  while (Index <= Length(ALine)) and CharInSet(ALine[Index], [' ', #9]) do
    Inc(Index);
  Result := Copy(ALine, 1, Index - 1);
end;

/// <summary>Zustand am Anfang von ALast + 1, gelesen ab Zeile 0.</summary>
function StateAfter(const ALines: TArray<string>; ALast: Integer): TLineState;
var
  Line, Index: Integer;
  Text: string;
begin
  Result.State := TLexState.Code;
  Result.OpenLine := -1;
  Result.OpenCharacter := -1;
  for Line := 0 to ALast do
  begin
    Text := ALines[Line];
    Index := 1;
    while Index <= Length(Text) do
      case Result.State of
        TLexState.Brace:
          begin
            if Text[Index] = '}' then
              Result.State := TLexState.Code;
            Inc(Index);
          end;
        TLexState.ParenStar:
          begin
            if (Text[Index] = '*') and (Index < Length(Text)) and (Text[Index + 1] = ')') then
            begin
              Result.State := TLexState.Code;
              Inc(Index);
            end;
            Inc(Index);
          end;
      else
        if Text[Index] = '''' then
        begin
          // String bis zum schließenden Hochkomma ('' ist ein Hochkomma im String).
          Inc(Index);
          while (Index <= Length(Text)) and (Text[Index] <> '''') do
            Inc(Index);
          Inc(Index);
        end
        else if (Text[Index] = '/') and (Index < Length(Text)) and (Text[Index + 1] = '/') then
          Index := Length(Text) + 1
        else if Text[Index] = '{' then
        begin
          // Direktiven enden in derselben Zeile; sie zählen wie Code.
          if (Index < Length(Text)) and (Text[Index + 1] = '$') then
          begin
            while (Index <= Length(Text)) and (Text[Index] <> '}') do
              Inc(Index);
            Inc(Index);
          end
          else
          begin
            Result.State := TLexState.Brace;
            Result.OpenLine := Line;
            Result.OpenCharacter := Index - 1;
            Inc(Index);
          end;
        end
        else if (Text[Index] = '(') and (Index < Length(Text)) and (Text[Index + 1] = '*') then
        begin
          Result.State := TLexState.ParenStar;
          Result.OpenLine := Line;
          Result.OpenCharacter := Index - 1;
          Inc(Index, 2);
        end
        else
          Inc(Index);
      end;
  end;
end;

{ TAtlasCommentOptions }

class function TAtlasCommentOptions.Defaults: TAtlasCommentOptions;
begin
  Result.LineComments := True;
  Result.Lists := True;
  Result.BlockPrefix := '';
end;

{ TAtlasCommentContinuation }

class function TAtlasCommentContinuation.ListItem(const AContent: string; out AMarker, ANext: string): Boolean;
var
  Index, Number: Integer;
begin
  AMarker := '';
  ANext := '';
  Result := False;
  if (Length(AContent) >= 1) and CharInSet(AContent[1], ['-', '*']) and
    ((Length(AContent) = 1) or (AContent[2] = ' ')) then
  begin
    AMarker := Copy(AContent, 1, 1) + Copy(LeadingSpace(Copy(AContent, 2, MaxInt)), 1, MaxInt);
    ANext := AContent[1] + ' ';
    if Length(AMarker) > 1 then
      ANext := AMarker;
    Exit(True);
  end;
  Index := 1;
  while (Index <= Length(AContent)) and CharInSet(AContent[Index], ['0'..'9']) do
    Inc(Index);
  // "1." bzw. "1)" mit Leerzeichen oder am Ende; höchstens drei Ziffern (keine Jahreszahl wie "2026. ").
  if (Index = 1) or (Index > 4) or (Index > Length(AContent)) or not CharInSet(AContent[Index], ['.', ')']) or
    ((Index < Length(AContent)) and (AContent[Index + 1] <> ' ')) then
    Exit;
  Number := StrToInt(Copy(AContent, 1, Index - 1));
  AMarker := Copy(AContent, 1, Index) + LeadingSpace(Copy(AContent, Index + 1, MaxInt));
  ANext := IntToStr(Number + 1) + AContent[Index] + Copy(AMarker, Index + 1, MaxInt);
  if Length(ANext) = Length(IntToStr(Number + 1)) + 1 then
    ANext := ANext + ' ';
  Result := True;
end;

class function TAtlasCommentContinuation.OnEnter(const AText: string; ALine, ACharacter: Integer;
  const AOptions: TAtlasCommentOptions; out AEdit: TAtlasCommentEdit): Boolean;
var
  Lines: TArray<string>;
  Previous, Current, Rest, Indent, Marker, After, Space, Content, Bullet, Next, Prefix, Opener, Base: string;
  State: TLineState;
  Body: string;

  procedure SetCurrent(const ANewLine: string; ACursor: Integer);
  begin
    AEdit.StartLine := ALine;
    AEdit.OldCount := 1;
    AEdit.Lines := [ANewLine];
    AEdit.CursorLine := ALine;
    AEdit.CursorCharacter := ACursor;
  end;

  /// <summary>Zeile darüber wird ANewLine, die neue Zeile fällt weg; Cursor an ihr Ende.</summary>
  procedure Join(const ANewLine: string);
  begin
    AEdit.StartLine := ALine - 1;
    AEdit.OldCount := 2;
    AEdit.Lines := [ANewLine + Rest];
    AEdit.CursorLine := ALine - 1;
    AEdit.CursorCharacter := Length(ANewLine);
  end;

begin
  AEdit := Default(TAtlasCommentEdit);
  Result := False;
  Lines := LinesOf(AText);
  if (ALine < 1) or (ALine > High(Lines)) then
    Exit;
  Previous := Lines[ALine - 1];
  Current := Lines[ALine];
  if Trim(Copy(Current, 1, ACharacter)) <> '' then
    Exit;
  Rest := TrimLeft(Current);
  // Zustand am Anfang der Zeile darüber: Nur dann ist ein "//" am Zeilenanfang ein Zeilenkommentar.
  State := StateAfter(Lines, ALine - 2);
  if (State.State = TLexState.Code) and TrimLeft(Previous).StartsWith('//') then
  begin
    Indent := LeadingSpace(Previous);
    Body := TrimLeft(Previous);
    Marker := '//';
    if Body.StartsWith('///') and not Body.StartsWith('////') then
      Marker := '///';
    if (Marker = '//') and not AOptions.LineComments then
      Exit;
    After := Copy(Body, Length(Marker) + 1, MaxInt);
    Space := LeadingSpace(After);
    Content := Copy(After, Length(Space) + 1, MaxInt);
    // Nur das Präfix: Kommentar beenden.
    if Trim(Content) = '' then
    begin
      Join(Indent);
      Exit(True);
    end;
    Next := '';
    if AOptions.Lists and ListItem(Content, Bullet, Next) then
    begin
      // Nur das Aufzählungszeichen: Es fällt weg, der Kommentar bleibt.
      if Trim(Copy(Content, Length(Bullet) + 1, MaxInt)) = '' then
      begin
        Join(Indent + Marker + Space);
        Exit(True);
      end;
    end;
    if Space = '' then
      Space := ' ';
    Prefix := Indent + Marker + Space + Next;
    SetCurrent(Prefix + Rest, Length(Prefix));
    Exit(True);
  end;
  // In einem offenen Blockkommentar: Einrückung (und Präfix).
  State := StateAfter(Lines, ALine - 1);
  if State.State = TLexState.Code then
    Exit;
  Opener := '{';
  if State.State = TLexState.ParenStar then
    Opener := '(*';
  Base := LeadingSpace(Lines[State.OpenLine]);
  if AOptions.BlockPrefix <> '' then
  begin
    if Rest.StartsWith('*)') then
      Prefix := Base + ' '
    else if Rest.StartsWith('}') then
      Prefix := Base
    else
      Prefix := Base + AOptions.BlockPrefix;
  end
  else if State.OpenLine = ALine - 1 then
  begin
    // Unter den Text hinter der öffnenden Klammer; Tabulatoren davor bleiben.
    After := Copy(Previous, State.OpenCharacter + Length(Opener) + 1, MaxInt);
    if Trim(After) = '' then
      Prefix := Base + '  '
    else
    begin
      Prefix := Copy(Previous, 1, State.OpenCharacter + Length(Opener)) + LeadingSpace(After);
      Prefix := Base + StringOfChar(' ', Length(Prefix) - Length(Base));
    end;
  end
  else if Trim(Previous) <> '' then
    Prefix := LeadingSpace(Previous)
  else
    Exit;
  if Prefix + Rest = Current then
    Exit;
  SetCurrent(Prefix + Rest, Length(Prefix));
  Result := True;
end;

end.
