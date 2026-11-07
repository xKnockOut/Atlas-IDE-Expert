unit Atlas.Text.Jsonc;

// JSON mit Kommentaren (atlas.json, settings.json), gemeinsam für Server und
// Plugin (ADR 0012): Leerraum und Kommentare überspringen, Kommentare
// entfernen. Zeilenkommentare (//) enden an #10 oder #13, Blockkommentare
// (/* */) an "*/". Ein offener Blockkommentar läuft bis zum Textende; ob das
// ein Fehler ist, entscheidet der Aufrufer (Server: Meldung, Plugin: tolerant).
// SyntaxError und LineColumn nennen die erste fehlerhafte Stelle, damit eine
// Meldung Zeile und Spalte zeigen kann (Projektdatei .atlas).

interface

type
  TJsoncScanner = class
  public
    /// <summary>Überspringt ab APos (1-basiert) Leerraum, // bis #10 oder #13 und /* … */. False bei einem
    /// offenen Blockkommentar; APos steht dann hinter dem Text.</summary>
    class function SkipSpace(const AText: string; var APos: Integer): Boolean; overload; static;
    /// <summary>Wie oben; AOpenComment ist bei False die Position des offenen "/*", sonst 0.</summary>
    class function SkipSpace(const AText: string; var APos: Integer; out AOpenComment: Integer): Boolean;
      overload; static;
    /// <summary>Überspringt einen String ab dem öffnenden Anführungszeichen bei APos; APos steht danach
    /// hinter dem schließenden (oder hinter dem Text).</summary>
    class procedure SkipString(const AText: string; var APos: Integer); static;
    /// <summary>Kommentare durch Leerzeichen ersetzen (Zeilenumbrüche bleiben, Positionen stimmen weiter),
    /// Strings beachten; ein Schlusskomma vor } oder ] wird zum Leerzeichen.</summary>
    class function StripComments(const AText: string): string; static;
    /// <summary>Erste Stelle (1-basiert), an der AText kein gültiger JSON-Wert ist; Kommentare und Schlusskommas
    /// sind erlaubt (wie StripComments). Length(AText) + 1, wenn der Text vorher endet; 0 ohne Fehler.</summary>
    class function SyntaxError(const AText: string): Integer; static;
    /// <summary>Zeile und Spalte (ab 1) der Stelle AOffset; #13#10, #10 und #13 beenden eine Zeile.</summary>
    class procedure LineColumn(const AText: string; AOffset: Integer; out ALine, AColumn: Integer); static;
  end;

implementation

function IsSpace(ACh: Char): Boolean;
begin
  Result := (ACh = ' ') or (ACh = #9) or (ACh = #10) or (ACh = #13);
end;

// Beginnt bei APos ein Kommentar "/" + AKind ("//" bzw. "/*")?
function StartsComment(const AText: string; APos: Integer; AKind: Char): Boolean;
begin
  Result := (AText[APos] = '/') and (APos < Length(AText)) and (AText[APos + 1] = AKind);
end;

// Erste Stelle ab APos, an der ein Zeilenkommentar endet (#10, #13 oder hinter dem Text).
function LineCommentEnd(const AText: string; APos: Integer): Integer;
begin
  Result := APos;
  while (Result <= Length(AText)) and (AText[Result] <> #10) and (AText[Result] <> #13) do
  begin
    Inc(Result);
  end;
end;

// Stelle hinter dem "*/" des Blockkommentars bei APos; 0, wenn er offen bleibt.
function BlockCommentEnd(const AText: string; APos: Integer): Integer;
begin
  Result := Pos('*/', AText, APos + 2);
  if Result > 0 then
  begin
    Inc(Result, 2);
  end;
end;

// Ersetzt AText[AFrom..ATo - 1] durch Leerzeichen; Zeilenumbrüche bleiben.
procedure Blank(var AText: string; AFrom, ATo: Integer);
var
  mIndex: Integer;
begin
  for mIndex := AFrom to ATo - 1 do
  begin
    if (AText[mIndex] <> #10) and (AText[mIndex] <> #13) then
    begin
      AText[mIndex] := ' ';
    end;
  end;
end;

{ TJsoncScanner }

class function TJsoncScanner.SkipSpace(const AText: string; var APos: Integer; out AOpenComment: Integer): Boolean;
var
  mClose: Integer;
begin
  AOpenComment := 0;
  while APos <= Length(AText) do
  begin
    if IsSpace(AText[APos]) then
    begin
      Inc(APos);
    end
    else if StartsComment(AText, APos, '/') then
    begin
      APos := LineCommentEnd(AText, APos);
    end
    else if StartsComment(AText, APos, '*') then
    begin
      mClose := BlockCommentEnd(AText, APos);
      if mClose = 0 then
      begin
        AOpenComment := APos;
        APos := Length(AText) + 1;
        Exit(False);
      end;
      APos := mClose;
    end
    else
    begin
      Break;
    end;
  end;
  Result := True;
end;

class function TJsoncScanner.SkipSpace(const AText: string; var APos: Integer): Boolean;
var
  mOpenComment: Integer;
begin
  Result := SkipSpace(AText, APos, mOpenComment);
end;

class procedure TJsoncScanner.SkipString(const AText: string; var APos: Integer);
begin
  Inc(APos);
  while (APos <= Length(AText)) and (AText[APos] <> '"') do
  begin
    if AText[APos] = '\' then
    begin
      Inc(APos);
    end;
    Inc(APos);
  end;
  Inc(APos);
end;

// Stelle hinter dem Kommentar bei APos; ein offener Blockkommentar reicht bis zum Textende.
function CommentEnd(const AText: string; APos: Integer): Integer;
begin
  if AText[APos + 1] = '/' then
  begin
    Exit(LineCommentEnd(AText, APos));
  end;
  Result := BlockCommentEnd(AText, APos);
  if Result = 0 then
  begin
    Result := Length(AText) + 1;
  end;
end;

// Schlusskomma bei APos: vor } oder ] (auch mit Kommentaren dazwischen)?
function IsTrailingComma(const AText: string; APos: Integer): Boolean;
var
  mNext: Integer;
begin
  mNext := APos + 1;
  TJsoncScanner.SkipSpace(AText, mNext);
  Result := (mNext <= Length(AText)) and ((AText[mNext] = '}') or (AText[mNext] = ']'));
end;

class function TJsoncScanner.StripComments(const AText: string): string;
var
  mPosition, mEnd: Integer;
begin
  Result := AText;
  mPosition := 1;
  while mPosition <= Length(AText) do
  begin
    if AText[mPosition] = '"' then
    begin
      SkipString(AText, mPosition);
    end
    else if StartsComment(AText, mPosition, '/') or StartsComment(AText, mPosition, '*') then
    begin
      // Genau diesen Kommentar blanken.
      mEnd := CommentEnd(AText, mPosition);
      Blank(Result, mPosition, mEnd);
      mPosition := mEnd;
    end
    else
    begin
      if (AText[mPosition] = ',') and IsTrailingComma(AText, mPosition) then
      begin
        Result[mPosition] := ' ';
      end;
      Inc(mPosition);
    end;
  end;
end;

function IsDigit(ACh: Char): Boolean;
begin
  Result := (ACh >= '0') and (ACh <= '9');
end;

class function TJsoncScanner.SyntaxError(const AText: string): Integer;
var
  mText: string;
  mPosition, mError: Integer;

  function Fail: Boolean;
  begin
    if mError = 0 then
    begin
      mError := mPosition;
    end;
    Result := False;
  end;

  procedure Space;
  begin
    // Kommentare sind schon geblankt.
    while (mPosition <= Length(mText)) and IsSpace(mText[mPosition]) do
    begin
      Inc(mPosition);
    end;
  end;

  function Digits: Boolean;
  begin
    if (mPosition > Length(mText)) or not IsDigit(mText[mPosition]) then
    begin
      Exit(Fail);
    end;
    while (mPosition <= Length(mText)) and IsDigit(mText[mPosition]) do
    begin
      Inc(mPosition);
    end;
    Result := True;
  end;

  function Number: Boolean;
  begin
    if mText[mPosition] = '-' then
    begin
      Inc(mPosition);
    end;
    if not Digits then
    begin
      Exit(False);
    end;
    if (mPosition <= Length(mText)) and (mText[mPosition] = '.') then
    begin
      Inc(mPosition);
      if not Digits then
      begin
        Exit(False);
      end;
    end;
    if (mPosition <= Length(mText)) and ((mText[mPosition] = 'e') or (mText[mPosition] = 'E')) then
    begin
      Inc(mPosition);
      if (mPosition <= Length(mText)) and ((mText[mPosition] = '+') or (mText[mPosition] = '-')) then
      begin
        Inc(mPosition);
      end;
      if not Digits then
      begin
        Exit(False);
      end;
    end;
    Result := True;
  end;

  function StringValue: Boolean;
  begin
    Inc(mPosition);
    while mPosition <= Length(mText) do
    begin
      if mText[mPosition] = '"' then
      begin
        Inc(mPosition);
        Exit(True);
      end;
      // Ein Zeilenumbruch im String heißt meist: schließendes Anführungszeichen vergessen.
      if mText[mPosition] < ' ' then
      begin
        Exit(Fail);
      end;
      if mText[mPosition] = '\' then
      begin
        Inc(mPosition);
      end;
      Inc(mPosition);
    end;
    Result := Fail;
  end;

  function Literal(const AWord: string): Boolean;
  begin
    if Copy(mText, mPosition, Length(AWord)) <> AWord then
    begin
      Exit(Fail);
    end;
    Inc(mPosition, Length(AWord));
    Result := True;
  end;

  function Value: Boolean; forward;

  // Steht nach Leerraum das Zeichen AChar? Dann geht es dahinter weiter.
  function Next(AChar: Char): Boolean;
  begin
    Space;
    Result := (mPosition <= Length(mText)) and (mText[mPosition] = AChar);
    if Result then
    begin
      Inc(mPosition);
    end;
  end;

  // Schlüssel eines Objekts samt Doppelpunkt.
  function Key: Boolean;
  begin
    Space;
    if (mPosition > Length(mText)) or (mText[mPosition] <> '"') or not StringValue then
    begin
      Exit(Fail);
    end;
    Result := Next(':') or Fail;
  end;

  function Members(AClose: Char; AObject: Boolean): Boolean;
  begin
    Inc(mPosition);
    if Next(AClose) then
    begin
      Exit(True);
    end;
    repeat
      if (AObject and not Key) or not Value then
      begin
        Exit(False);
      end;
      if Next(AClose) then
      begin
        Exit(True);
      end;
    until not Next(',');
    Result := Fail;
  end;

  function Value: Boolean;
  begin
    Space;
    if mPosition > Length(mText) then
    begin
      Exit(Fail);
    end;
    case mText[mPosition] of
      '{':
        Result := Members('}', True);
      '[':
        Result := Members(']', False);
      '"':
        Result := StringValue;
      '-', '0'..'9':
        Result := Number;
      't':
        Result := Literal('true');
      'f':
        Result := Literal('false');
      'n':
        Result := Literal('null');
    else
      Result := Fail;
    end;
  end;

begin
  mText := StripComments(AText);
  mPosition := 1;
  mError := 0;
  if Value then
  begin
    Space;
    if mPosition <= Length(mText) then
    begin
      mError := mPosition;
    end;
  end;
  Result := mError;
end;

class procedure TJsoncScanner.LineColumn(const AText: string; AOffset: Integer; out ALine, AColumn: Integer);
var
  mIndex, mLineStart: Integer;
begin
  ALine := 1;
  mLineStart := 1;
  mIndex := 1;
  while (mIndex < AOffset) and (mIndex <= Length(AText)) do
  begin
    if (AText[mIndex] = #13) and (mIndex < Length(AText)) and (AText[mIndex + 1] = #10) then
    begin
      Inc(mIndex);
    end;
    if (AText[mIndex] = #10) or (AText[mIndex] = #13) then
    begin
      Inc(ALine);
      mLineStart := mIndex + 1;
    end;
    Inc(mIndex);
  end;
  AColumn := AOffset - mLineStart + 1;
end;

end.
