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

{ TJsoncScanner }

class function TJsoncScanner.SkipSpace(const AText: string; var APos: Integer; out AOpenComment: Integer): Boolean;
var
  Close: Integer;
begin
  AOpenComment := 0;
  while APos <= Length(AText) do
  begin
    if (AText[APos] = ' ') or (AText[APos] = #9) or (AText[APos] = #10) or (AText[APos] = #13) then
      Inc(APos)
    else if (AText[APos] = '/') and (APos < Length(AText)) and (AText[APos + 1] = '/') then
    begin
      while (APos <= Length(AText)) and (AText[APos] <> #10) and (AText[APos] <> #13) do
        Inc(APos);
    end
    else if (AText[APos] = '/') and (APos < Length(AText)) and (AText[APos + 1] = '*') then
    begin
      Close := Pos('*/', AText, APos + 2);
      if Close = 0 then
      begin
        AOpenComment := APos;
        APos := Length(AText) + 1;
        Exit(False);
      end;
      APos := Close + 2;
    end
    else
      Break;
  end;
  Result := True;
end;

class function TJsoncScanner.SkipSpace(const AText: string; var APos: Integer): Boolean;
var
  OpenComment: Integer;
begin
  Result := SkipSpace(AText, APos, OpenComment);
end;

class procedure TJsoncScanner.SkipString(const AText: string; var APos: Integer);
begin
  Inc(APos);
  while (APos <= Length(AText)) and (AText[APos] <> '"') do
  begin
    if AText[APos] = '\' then
      Inc(APos);
    Inc(APos);
  end;
  Inc(APos);
end;

class function TJsoncScanner.StripComments(const AText: string): string;
var
  Position, Start, Next, Index: Integer;
begin
  Result := AText;
  Position := 1;
  while Position <= Length(AText) do
  begin
    case AText[Position] of
      '"':
        begin
          SkipString(AText, Position);
          Continue;
        end;
      '/':
        if (Position < Length(AText)) and ((AText[Position + 1] = '/') or (AText[Position + 1] = '*')) then
        begin
          // Genau diesen Kommentar blanken; ein offener Blockkommentar reicht bis zum Textende.
          Start := Position;
          if AText[Position + 1] = '/' then
          begin
            while (Position <= Length(AText)) and (AText[Position] <> #10) and (AText[Position] <> #13) do
              Inc(Position);
          end
          else
          begin
            Next := Pos('*/', AText, Position + 2);
            if Next = 0 then
              Position := Length(AText) + 1
            else
              Position := Next + 2;
          end;
          for Index := Start to Position - 1 do
            if (Result[Index] <> #10) and (Result[Index] <> #13) then
              Result[Index] := ' ';
          Continue;
        end;
      ',':
        begin
          // Schlusskomma vor } oder ] (auch mit Kommentaren dazwischen) entfernen.
          Next := Position + 1;
          SkipSpace(AText, Next);
          if (Next <= Length(AText)) and ((AText[Next] = '}') or (AText[Next] = ']')) then
            Result[Position] := ' ';
        end;
    end;
    Inc(Position);
  end;
end;

function IsSpace(ACh: Char): Boolean;
begin
  Result := (ACh = ' ') or (ACh = #9) or (ACh = #10) or (ACh = #13);
end;

function IsDigit(ACh: Char): Boolean;
begin
  Result := (ACh >= '0') and (ACh <= '9');
end;

class function TJsoncScanner.SyntaxError(const AText: string): Integer;
var
  Text: string;
  Position, Error: Integer;

  function Fail: Boolean;
  begin
    if Error = 0 then
      Error := Position;
    Result := False;
  end;

  procedure Space;
  begin
    // Kommentare sind schon geblankt.
    while (Position <= Length(Text)) and IsSpace(Text[Position]) do
      Inc(Position);
  end;

  function Digits: Boolean;
  begin
    if (Position > Length(Text)) or not IsDigit(Text[Position]) then
      Exit(Fail);
    while (Position <= Length(Text)) and IsDigit(Text[Position]) do
      Inc(Position);
    Result := True;
  end;

  function Number: Boolean;
  begin
    if Text[Position] = '-' then
      Inc(Position);
    if not Digits then
      Exit(False);
    if (Position <= Length(Text)) and (Text[Position] = '.') then
    begin
      Inc(Position);
      if not Digits then
        Exit(False);
    end;
    if (Position <= Length(Text)) and ((Text[Position] = 'e') or (Text[Position] = 'E')) then
    begin
      Inc(Position);
      if (Position <= Length(Text)) and ((Text[Position] = '+') or (Text[Position] = '-')) then
        Inc(Position);
      if not Digits then
        Exit(False);
    end;
    Result := True;
  end;

  function StringValue: Boolean;
  begin
    Inc(Position);
    while Position <= Length(Text) do
    begin
      if Text[Position] = '"' then
      begin
        Inc(Position);
        Exit(True);
      end;
      // Ein Zeilenumbruch im String heißt meist: schließendes Anführungszeichen vergessen.
      if Text[Position] < ' ' then
        Exit(Fail);
      if Text[Position] = '\' then
        Inc(Position);
      Inc(Position);
    end;
    Result := Fail;
  end;

  function Literal(const AWord: string): Boolean;
  begin
    if Copy(Text, Position, Length(AWord)) <> AWord then
      Exit(Fail);
    Inc(Position, Length(AWord));
    Result := True;
  end;

  function Value: Boolean; forward;

  function Members(AClose: Char; AObject: Boolean): Boolean;
  begin
    Inc(Position);
    Space;
    if (Position <= Length(Text)) and (Text[Position] = AClose) then
    begin
      Inc(Position);
      Exit(True);
    end;
    while True do
    begin
      if AObject then
      begin
        Space;
        if (Position > Length(Text)) or (Text[Position] <> '"') or not StringValue then
          Exit(Fail);
        Space;
        if (Position > Length(Text)) or (Text[Position] <> ':') then
          Exit(Fail);
        Inc(Position);
      end;
      if not Value then
        Exit(False);
      Space;
      if Position > Length(Text) then
        Exit(Fail);
      if Text[Position] = AClose then
      begin
        Inc(Position);
        Exit(True);
      end;
      if Text[Position] <> ',' then
        Exit(Fail);
      Inc(Position);
    end;
  end;

  function Value: Boolean;
  begin
    Space;
    if Position > Length(Text) then
      Exit(Fail);
    case Text[Position] of
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
  Text := StripComments(AText);
  Position := 1;
  Error := 0;
  if Value then
  begin
    Space;
    if Position <= Length(Text) then
      Error := Position;
  end;
  Result := Error;
end;

class procedure TJsoncScanner.LineColumn(const AText: string; AOffset: Integer; out ALine, AColumn: Integer);
var
  Index, LineStart: Integer;
begin
  ALine := 1;
  LineStart := 1;
  Index := 1;
  while (Index < AOffset) and (Index <= Length(AText)) do
  begin
    if (AText[Index] = #13) and (Index < Length(AText)) and (AText[Index + 1] = #10) then
      Inc(Index);
    if (AText[Index] = #10) or (AText[Index] = #13) then
    begin
      Inc(ALine);
      LineStart := Index + 1;
    end;
    Inc(Index);
  end;
  AColumn := AOffset - LineStart + 1;
end;

end.
