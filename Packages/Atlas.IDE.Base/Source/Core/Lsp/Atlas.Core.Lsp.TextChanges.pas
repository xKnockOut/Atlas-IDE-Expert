unit Atlas.Core.Lsp.TextChanges;

// Inkrementelles didChange (#395): Statt des ganzen Textes geht nur der
// geänderte Bereich an den Server. Gleicher Anfang und gleiches Ende der
// beiden Texte fallen weg; der Rest ist ein Bereich im alten Text (Zeile und
// Zeichen 0-basiert in UTF-16-Einheiten) und sein neuer Inhalt.
// Zeilenumbrüche wie beim Server: CR, LF und CRLF. Eine Grenze liegt nie
// zwischen CR und LF und nie mitten in einem Surrogatpaar, sonst würde der
// Server die Position anders deuten. Zeilen und Positionen rechnet
// TLineTable aus Atlas.Text, dieselbe Tabelle wie beim Server (ADR 0012).

interface

uses
  System.SysUtils,
  Atlas.Text.Lines;

type
  TLspTextPosition = record
    Line: Integer;
    Character: Integer;
    class function Create(ALine, ACharacter: Integer): TLspTextPosition; static;
    /// <summary>Negativ, 0 oder positiv wie CompareText.</summary>
    class function Compare(const A, B: TLspTextPosition): Integer; static;
  end;

  /// <summary>Bereich im Text, Ende ausschließlich (#399).</summary>
  TLspRange = record
    StartPos: TLspTextPosition;
    EndPos: TLspTextPosition;
    class function Create(AStartLine, AStartCharacter, AEndLine, AEndCharacter: Integer): TLspRange; static;
    function IsEmpty: Boolean;
    function Same(const AOther: TLspRange): Boolean;
    /// <summary>AOther liegt ganz in diesem Bereich (gleiche Grenzen eingeschlossen).</summary>
    function Contains(const AOther: TLspRange): Boolean;
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
    /// <summary>Position zum Zeichenindex (0-basiert) in AText; ein Index zwischen CR und LF zählt
    /// zum Zeilenende.</summary>
    class function PositionOf(const AText: string; AOffset: Integer): TLspTextPosition; overload; static;
    /// <summary>Wie oben mit einer schon gebauten Zeilentabelle (mehrere Abfragen auf einem Text).</summary>
    class function PositionOf(const ALines: TLineTable; AOffset: Integer): TLspTextPosition; overload; static;
    /// <summary>Zeichenindex (0-basiert) zur Position; hinter dem Zeilenende das Zeilenende, hinter der
    /// letzten Zeile das Textende.</summary>
    class function OffsetOf(const AText: string; const APosition: TLspTextPosition): Integer; overload; static;
    class function OffsetOf(const ALines: TLineTable; const APosition: TLspTextPosition): Integer; overload;
      static;
  end;

implementation

{ TLspTextPosition }

class function TLspTextPosition.Create(ALine, ACharacter: Integer): TLspTextPosition;
begin
  Result.Line := ALine;
  Result.Character := ACharacter;
end;

class function TLspTextPosition.Compare(const A, B: TLspTextPosition): Integer;
begin
  Result := A.Line - B.Line;
  if Result = 0 then
    Result := A.Character - B.Character;
end;

{ TLspRange }

class function TLspRange.Create(AStartLine, AStartCharacter, AEndLine, AEndCharacter: Integer): TLspRange;
begin
  Result.StartPos := TLspTextPosition.Create(AStartLine, AStartCharacter);
  Result.EndPos := TLspTextPosition.Create(AEndLine, AEndCharacter);
end;

function TLspRange.IsEmpty: Boolean;
begin
  Result := TLspTextPosition.Compare(StartPos, EndPos) >= 0;
end;

function TLspRange.Same(const AOther: TLspRange): Boolean;
begin
  Result := (TLspTextPosition.Compare(StartPos, AOther.StartPos) = 0) and
    (TLspTextPosition.Compare(EndPos, AOther.EndPos) = 0);
end;

function TLspRange.Contains(const AOther: TLspRange): Boolean;
begin
  Result := (TLspTextPosition.Compare(StartPos, AOther.StartPos) <= 0) and
    (TLspTextPosition.Compare(AOther.EndPos, EndPos) <= 0);
end;

function IsHighSurrogate(AChar: Char): Boolean;
begin
  Result := (Ord(AChar) >= $D800) and (Ord(AChar) <= $DBFF);
end;

function IsLowSurrogate(AChar: Char): Boolean;
begin
  Result := (Ord(AChar) >= $DC00) and (Ord(AChar) <= $DFFF);
end;

class function TLspTextChanges.PositionOf(const ALines: TLineTable; AOffset: Integer): TLspTextPosition;
var
  Position: TTextPosition;
begin
  Position := ALines.PositionAt(AOffset);
  Result := TLspTextPosition.Create(Position.Line, Position.Character);
end;

class function TLspTextChanges.PositionOf(const AText: string; AOffset: Integer): TLspTextPosition;
begin
  Result := PositionOf(TLineTable.Build(AText), AOffset);
end;

class function TLspTextChanges.OffsetOf(const ALines: TLineTable; const APosition: TLspTextPosition): Integer;
begin
  Result := ALines.OffsetAt(TTextPosition.Create(APosition.Line, APosition.Character));
end;

class function TLspTextChanges.OffsetOf(const AText: string; const APosition: TLspTextPosition): Integer;
begin
  Result := OffsetOf(TLineTable.Build(AText), APosition);
end;

class function TLspTextChanges.Between(const AOld, ANew: string): TLspTextChange;
var
  Prefix, Suffix, MaxSuffix: Integer;
  Lines: TLineTable;
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
  Lines := TLineTable.Build(AOld);
  Result.StartPos := PositionOf(Lines, Prefix);
  Result.EndPos := PositionOf(Lines, Length(AOld) - Suffix);
  Result.Text := Copy(ANew, Prefix + 1, Length(ANew) - Prefix - Suffix);
end;

end.
