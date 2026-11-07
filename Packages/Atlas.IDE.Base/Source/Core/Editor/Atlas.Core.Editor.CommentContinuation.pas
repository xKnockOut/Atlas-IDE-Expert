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
  mIndex: Integer;
begin
  Result := AText.Split([#10]);
  for mIndex := 0 to High(Result) do
  begin
    if Result[mIndex].EndsWith(#13) then
    begin
      Result[mIndex] := Copy(Result[mIndex], 1, Length(Result[mIndex]) - 1);
    end;
  end;
end;

function LeadingSpace(const ALine: string): string;
var
  mIndex: Integer;
begin
  mIndex := 1;
  while (mIndex <= Length(ALine)) and CharInSet(ALine[mIndex], [' ', #9]) do
  begin
    Inc(mIndex);
  end;
  Result := Copy(ALine, 1, mIndex - 1);
end;

function CharAt(const AText: string; AIndex: Integer): Char;
begin
  Result := #0;
  if (AIndex >= 1) and (AIndex <= Length(AText)) then
  begin
    Result := AText[AIndex];
  end;
end;

procedure OpenComment(var AState: TLineState; AKind: TLexState; ALine, ACharacter: Integer);
begin
  AState.State := AKind;
  AState.OpenLine := ALine;
  AState.OpenCharacter := ACharacter;
end;

/// <summary>String ab dem Hochkomma an AIndex bis hinter das schließende ('' ist ein Hochkomma im String).
/// </summary>
function SkipString(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= Length(AText)) and (AText[Result] <> '''') do
  begin
    Inc(Result);
  end;
  Inc(Result);
end;

/// <summary>Direktive ab AIndex bis hinter "}"; Direktiven enden in derselben Zeile und zählen wie Code.</summary>
function SkipDirective(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= Length(AText)) and (AText[Result] <> '}') do
  begin
    Inc(Result);
  end;
  Inc(Result);
end;

/// <summary>Ein Schritt im Code ab AIndex; Ergebnis: nächste Stelle.</summary>
function StepCode(const AText: string; AIndex, ALine: Integer; var AState: TLineState): Integer;
var
  mNext: Char;
begin
  mNext := CharAt(AText, AIndex + 1);
  Result := AIndex + 1;
  if AText[AIndex] = '''' then
  begin
    Result := SkipString(AText, AIndex);
  end
  else if (AText[AIndex] = '/') and (mNext = '/') then
  begin
    Result := Length(AText) + 1;
  end
  else if (AText[AIndex] = '{') and (mNext = '$') then
  begin
    Result := SkipDirective(AText, AIndex);
  end
  else if AText[AIndex] = '{' then
  begin
    OpenComment(AState, TLexState.Brace, ALine, AIndex - 1);
  end
  else if (AText[AIndex] = '(') and (mNext = '*') then
  begin
    OpenComment(AState, TLexState.ParenStar, ALine, AIndex - 1);
    Result := AIndex + 2;
  end;
end;

/// <summary>Ein Schritt im offenen Blockkommentar ab AIndex; Ergebnis: nächste Stelle.</summary>
function StepComment(const AText: string; AIndex: Integer; var AState: TLineState): Integer;
begin
  Result := AIndex + 1;
  if (AState.State = TLexState.Brace) and (AText[AIndex] = '}') then
  begin
    AState.State := TLexState.Code;
  end
  else if (AState.State = TLexState.ParenStar) and (AText[AIndex] = '*') and (CharAt(AText, AIndex + 1) = ')') then
  begin
    AState.State := TLexState.Code;
    Result := AIndex + 2;
  end;
end;

/// <summary>Zustand am Anfang von ALast + 1, gelesen ab Zeile 0.</summary>
function StateAfter(const ALines: TArray<string>; ALast: Integer): TLineState;
var
  mLine, mIndex: Integer;
  mText: string;
begin
  Result.State := TLexState.Code;
  Result.OpenLine := -1;
  Result.OpenCharacter := -1;
  for mLine := 0 to ALast do
  begin
    mText := ALines[mLine];
    mIndex := 1;
    while mIndex <= Length(mText) do
    begin
      if Result.State = TLexState.Code then
      begin
        mIndex := StepCode(mText, mIndex, mLine, Result);
      end
      else
      begin
        mIndex := StepComment(mText, mIndex, Result);
      end;
    end;
  end;
end;

/// <summary>"1." bzw. "1)" an AIndex mit Leerzeichen oder am Ende; höchstens drei Ziffern davor (keine Jahreszahl
/// wie "2026. ").</summary>
function IsNumberMarker(const AContent: string; AIndex: Integer): Boolean;
begin
  Result := (AIndex > 1) and (AIndex <= 4) and CharInSet(CharAt(AContent, AIndex), ['.', ')']) and
    CharInSet(CharAt(AContent, AIndex + 1), [' ', #0]);
end;

/// <summary>Neue Zeile ALine wird ANewLine, der Cursor steht an ACursor.</summary>
procedure SetCurrent(ALine: Integer; const ANewLine: string; ACursor: Integer; var AEdit: TAtlasCommentEdit);
begin
  AEdit.StartLine := ALine;
  AEdit.OldCount := 1;
  AEdit.Lines := [ANewLine];
  AEdit.CursorLine := ALine;
  AEdit.CursorCharacter := ACursor;
end;

/// <summary>Zeile über ALine wird ANewLine plus ARest, die neue Zeile fällt weg; Cursor hinter ANewLine.</summary>
procedure JoinLines(ALine: Integer; const ANewLine, ARest: string; var AEdit: TAtlasCommentEdit);
begin
  AEdit.StartLine := ALine - 1;
  AEdit.OldCount := 2;
  AEdit.Lines := [ANewLine + ARest];
  AEdit.CursorLine := ALine - 1;
  AEdit.CursorCharacter := Length(ANewLine);
end;

/// <summary>"///" (XMLDoc, nicht "////") oder "//" am Anfang von ABody.</summary>
function CommentMarker(const ABody: string): string;
begin
  Result := '//';
  if ABody.StartsWith('///') and not ABody.StartsWith('////') then
  begin
    Result := '///';
  end;
end;

/// <summary>Zeile darüber ist ein "//"-Kommentar: fortsetzen, beenden (nur Präfix) oder das leere
/// Aufzählungszeichen entfernen. False, wenn "//"-Zeilen nicht fortgesetzt werden.</summary>
function ContinueLineComment(const APrevious: string; ALine: Integer; const ARest: string;
  const AOptions: TAtlasCommentOptions; var AEdit: TAtlasCommentEdit): Boolean;
var
  mIndent, mBody, mMarker, mAfter, mSpace, mContent, mBullet, mNext, mPrefix: string;
begin
  mIndent := LeadingSpace(APrevious);
  mBody := TrimLeft(APrevious);
  mMarker := CommentMarker(mBody);
  Result := (mMarker = '///') or AOptions.LineComments;
  if Result then
  begin
    mAfter := Copy(mBody, Length(mMarker) + 1, MaxInt);
    mSpace := LeadingSpace(mAfter);
    mContent := Copy(mAfter, Length(mSpace) + 1, MaxInt);
    mNext := '';
    if Trim(mContent) = '' then
    begin
      // Nur das Präfix: Kommentar beenden.
      JoinLines(ALine, mIndent, ARest, AEdit);
    end
    else if AOptions.Lists and TAtlasCommentContinuation.ListItem(mContent, mBullet, mNext) and
      (Trim(Copy(mContent, Length(mBullet) + 1, MaxInt)) = '') then
    begin
      // Nur das Aufzählungszeichen: Es fällt weg, der Kommentar bleibt.
      JoinLines(ALine, mIndent + mMarker + mSpace, ARest, AEdit);
    end
    else
    begin
      if mSpace = '' then
      begin
        mSpace := ' ';
      end;
      mPrefix := mIndent + mMarker + mSpace + mNext;
      SetCurrent(ALine, mPrefix + ARest, Length(mPrefix), AEdit);
    end;
  end;
end;

/// <summary>Mit BlockPrefix: Einrückung ABase der öffnenden Zeile plus Präfix; vor dem Schließer ohne Präfix.
/// </summary>
function PrefixedIndent(const ABase, ARest, ABlockPrefix: string): string;
begin
  if ARest.StartsWith('*)') then
  begin
    Result := ABase + ' ';
  end
  else if ARest.StartsWith('}') then
  begin
    Result := ABase;
  end
  else
  begin
    Result := ABase + ABlockPrefix;
  end;
end;

/// <summary>Direkt unter der öffnenden Zeile: unter den Text hinter der Klammer; Tabulatoren davor bleiben.
/// </summary>
function OpenerIndent(const APrevious, ABase: string; const AState: TLineState): string;
var
  mOpenerLength: Integer;
  mAfter: string;
begin
  mOpenerLength := 1;
  if AState.State = TLexState.ParenStar then
  begin
    mOpenerLength := 2;
  end;
  mAfter := Copy(APrevious, AState.OpenCharacter + mOpenerLength + 1, MaxInt);
  if Trim(mAfter) = '' then
  begin
    Result := ABase + '  ';
  end
  else
  begin
    Result := Copy(APrevious, 1, AState.OpenCharacter + mOpenerLength) + LeadingSpace(mAfter);
    Result := ABase + StringOfChar(' ', Length(Result) - Length(ABase));
  end;
end;

/// <summary>In einem offenen Blockkommentar: Einrückung (und Präfix). False außerhalb oder ohne Änderung.</summary>
function ContinueBlock(const ALines: TArray<string>; ALine: Integer; const ARest: string;
  const AOptions: TAtlasCommentOptions; var AEdit: TAtlasCommentEdit): Boolean;
var
  mState: TLineState;
  mPrevious, mBase, mPrefix: string;
begin
  mState := StateAfter(ALines, ALine - 1);
  Result := mState.State <> TLexState.Code;
  if Result then
  begin
    mPrevious := ALines[ALine - 1];
    mBase := LeadingSpace(ALines[mState.OpenLine]);
    mPrefix := '';
    if AOptions.BlockPrefix <> '' then
    begin
      mPrefix := PrefixedIndent(mBase, ARest, AOptions.BlockPrefix);
    end
    else if mState.OpenLine = ALine - 1 then
    begin
      mPrefix := OpenerIndent(mPrevious, mBase, mState);
    end
    else if Trim(mPrevious) <> '' then
    begin
      mPrefix := LeadingSpace(mPrevious);
    end
    else
    begin
      Result := False;
    end;
    Result := Result and (mPrefix + ARest <> ALines[ALine]);
    if Result then
    begin
      SetCurrent(ALine, mPrefix + ARest, Length(mPrefix), AEdit);
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
  mIndex, mNumber: Integer;
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
    begin
      ANext := AMarker;
    end;
    Exit(True);
  end;
  mIndex := 1;
  while (mIndex <= Length(AContent)) and CharInSet(AContent[mIndex], ['0'..'9']) do
  begin
    Inc(mIndex);
  end;
  if not IsNumberMarker(AContent, mIndex) then
  begin
    Exit;
  end;
  mNumber := StrToInt(Copy(AContent, 1, mIndex - 1));
  AMarker := Copy(AContent, 1, mIndex) + LeadingSpace(Copy(AContent, mIndex + 1, MaxInt));
  ANext := IntToStr(mNumber + 1) + AContent[mIndex] + Copy(AMarker, mIndex + 1, MaxInt);
  if Length(ANext) = Length(IntToStr(mNumber + 1)) + 1 then
  begin
    ANext := ANext + ' ';
  end;
  Result := True;
end;

class function TAtlasCommentContinuation.OnEnter(const AText: string; ALine, ACharacter: Integer;
  const AOptions: TAtlasCommentOptions; out AEdit: TAtlasCommentEdit): Boolean;
var
  mLines: TArray<string>;
  mRest: string;
begin
  AEdit := Default(TAtlasCommentEdit);
  Result := False;
  mLines := LinesOf(AText);
  if (ALine >= 1) and (ALine <= High(mLines)) and (Trim(Copy(mLines[ALine], 1, ACharacter)) = '') then
  begin
    mRest := TrimLeft(mLines[ALine]);
    // Zustand am Anfang der Zeile darüber: Nur dann ist ein "//" am Zeilenanfang ein Zeilenkommentar.
    if (StateAfter(mLines, ALine - 2).State = TLexState.Code) and TrimLeft(mLines[ALine - 1]).StartsWith('//') then
    begin
      Result := ContinueLineComment(mLines[ALine - 1], ALine, mRest, AOptions, AEdit);
    end
    else
    begin
      Result := ContinueBlock(mLines, ALine, mRest, AOptions, AEdit);
    end;
  end;
end;

end.
