unit Atlas.Core.Lsp.TextChanges;

// Inkrementelles didChange (#395): Statt des ganzen Textes geht nur der
// geänderte Bereich an den Server. Gleicher Anfang und gleiches Ende der
// beiden Texte fallen weg; der Rest ist ein Bereich im alten Text (Zeile und
// Zeichen 0-basiert in UTF-16-Einheiten) und sein neuer Inhalt.
// Zeilenumbrüche wie beim Server: CR, LF und CRLF. Eine Grenze liegt nie
// zwischen CR und LF und nie mitten in einem Surrogatpaar, sonst würde der
// Server die Position anders deuten.

interface

uses
  System.SysUtils;

type
  TLspTextPosition = record
    Line: Integer;
    Character: Integer;
  end;

  TLspTextChange = record
    StartPos: TLspTextPosition;
    EndPos: TLspTextPosition;
    /// <summary>Neuer Inhalt des Bereichs.</summary>
    Text: string;
  end;

  TLspTextChanges = class
  public
    /// <summary>Kleinster zusammenhängender Bereich, der AOld in ANew überführt.
    /// Bei gleichen Texten ein leerer Bereich am Textende mit leerem Text.</summary>
    class function Between(const AOld, ANew: string): TLspTextChange; static;
    /// <summary>Position zum Zeichenindex (0-basiert) in AText.</summary>
    class function PositionOf(const AText: string; AOffset: Integer): TLspTextPosition; static;
    /// <summary>Zeichenindex (0-basiert) zur Position; hinter dem Zeilenende das Zeilenende.</summary>
    class function OffsetOf(const AText: string; const APosition: TLspTextPosition): Integer; static;
  end;

implementation

function IsHighSurrogate(AChar: Char): Boolean;
begin
  Result := (Ord(AChar) >= $D800) and (Ord(AChar) <= $DBFF);
end;

function IsLowSurrogate(AChar: Char): Boolean;
begin
  Result := (Ord(AChar) >= $DC00) and (Ord(AChar) <= $DFFF);
end;

class function TLspTextChanges.PositionOf(const AText: string; AOffset: Integer): TLspTextPosition;
var
  Index, LineStart: Integer;
begin
  Result.Line := 0;
  LineStart := 0;
  Index := 0;
  while Index < AOffset do
  begin
    // AText ist 1-basiert, Index 0-basiert.
    if AText[Index + 1] = #13 then
    begin
      if (Index + 1 < AOffset) and (AText[Index + 2] = #10) then
        Inc(Index);
      Inc(Result.Line);
      LineStart := Index + 1;
    end
    else if AText[Index + 1] = #10 then
    begin
      Inc(Result.Line);
      LineStart := Index + 1;
    end;
    Inc(Index);
  end;
  Result.Character := AOffset - LineStart;
end;

class function TLspTextChanges.OffsetOf(const AText: string; const APosition: TLspTextPosition): Integer;
var
  Line, LineEnd: Integer;
begin
  Result := 0;
  Line := 0;
  while (Line < APosition.Line) and (Result < Length(AText)) do
  begin
    if AText[Result + 1] = #13 then
    begin
      if (Result + 1 < Length(AText)) and (AText[Result + 2] = #10) then
        Inc(Result);
      Inc(Line);
    end
    else if AText[Result + 1] = #10 then
      Inc(Line);
    Inc(Result);
  end;
  // Hinter dem Zeilenende zählt das Zeilenende, wie beim Server (LSP).
  LineEnd := Result;
  while (LineEnd < Length(AText)) and (AText[LineEnd + 1] <> #13) and (AText[LineEnd + 1] <> #10) do
    Inc(LineEnd);
  Inc(Result, APosition.Character);
  if Result > LineEnd then
    Result := LineEnd;
end;

class function TLspTextChanges.Between(const AOld, ANew: string): TLspTextChange;
var
  Prefix, Suffix, MaxSuffix: Integer;
begin
  Prefix := 0;
  while (Prefix < Length(AOld)) and (Prefix < Length(ANew)) and (AOld[Prefix + 1] = ANew[Prefix + 1]) do
    Inc(Prefix);
  // Nicht zwischen CR und LF und nicht hinter einem hohen Surrogat enden.
  if (Prefix > 0) and ((AOld[Prefix] = #13) or IsHighSurrogate(AOld[Prefix])) then
    Dec(Prefix);
  Suffix := 0;
  MaxSuffix := Length(AOld) - Prefix;
  if Length(ANew) - Prefix < MaxSuffix then
    MaxSuffix := Length(ANew) - Prefix;
  while (Suffix < MaxSuffix) and (AOld[Length(AOld) - Suffix] = ANew[Length(ANew) - Suffix]) do
    Inc(Suffix);
  // Das gleiche Ende darf nicht mit LF hinter einem CR des Bereichs beginnen und nicht mit
  // einem tiefen Surrogat.
  if Suffix > 0 then
  begin
    if (AOld[Length(AOld) - Suffix + 1] = #10) and (Length(AOld) - Suffix > 0) and
      (AOld[Length(AOld) - Suffix] = #13) then
      Dec(Suffix)
    else if IsLowSurrogate(AOld[Length(AOld) - Suffix + 1]) then
      Dec(Suffix);
  end;
  Result.StartPos := PositionOf(AOld, Prefix);
  Result.EndPos := PositionOf(AOld, Length(AOld) - Suffix);
  Result.Text := Copy(ANew, Prefix + 1, Length(ANew) - Prefix - Suffix);
end;

end.
