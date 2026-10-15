unit Atlas.Text.Jsonc;

// JSON mit Kommentaren (atlas.json, settings.json), gemeinsam für Server und
// Plugin (ADR 0012): Leerraum und Kommentare überspringen, Kommentare
// entfernen. Zeilenkommentare (//) enden an #10 oder #13, Blockkommentare
// (/* */) an "*/". Ein offener Blockkommentar läuft bis zum Textende; ob das
// ein Fehler ist, entscheidet der Aufrufer (Server: Meldung, Plugin: tolerant).

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

end.
