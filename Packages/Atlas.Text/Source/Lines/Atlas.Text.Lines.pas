unit Atlas.Text.Lines;

// Zeilen und Positionen in Texten mit CRLF, LF oder CR (gemeinsam für Server
// und Plugin, ADR 0012).
// Zeilenmodell wie LSP und TTextDocument: n Zeilenumbrüche ergeben n + 1
// Zeilen; ein Text, der mit einem Umbruch endet, hat eine leere letzte Zeile;
// CRLF zählt als ein Umbruch. Positionen sind 0-basiert, Zeichen in
// UTF-16-Einheiten.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  /// <summary>Art der Zeilenenden eines Texts.</summary>
  TTextLineBreak = (None, CRLF, LF, CR, Mixed);
{$SCOPEDENUMS OFF}

  /// <summary>Zeile und Zeichen, 0-basiert, Zeichen in UTF-16-Einheiten (LSP).</summary>
  TTextPosition = record
    Line: Integer;
    Character: Integer;
    constructor Create(ALine, ACharacter: Integer);
    class operator Equal(const A, B: TTextPosition): Boolean;
    class operator NotEqual(const A, B: TTextPosition): Boolean;
  end;

  /// <summary>Zeilenanfänge eines Texts; PositionAt sucht binär, OffsetAt in O(1).</summary>
  TLineTable = record
  private
    /// <summary>0-basierte Offsets der Zeilenanfänge; nach Build immer mindestens ein Eintrag.</summary>
    FStarts: TArray<Integer>;
    /// <summary>0-basiertes Ende jeder Zeile ohne Zeilenumbruch.</summary>
    FContentEnds: TArray<Integer>;
    FLength: Integer;
  public
    class function Build(const AText: string): TLineTable; static;
    function LineCount: Integer;
    /// <summary>Offset (0-basiert), an dem ALine beginnt; außerhalb geklemmt.</summary>
    function LineStart(ALine: Integer): Integer;
    /// <summary>Offset (0-basiert) hinter dem letzten Zeichen von ALine, ohne Umbruch; außerhalb geklemmt.</summary>
    function LineContentEnd(ALine: Integer): Integer;
    /// <summary>Position zum Offset; geklemmt auf 0..Länge. Ein Offset im Umbruch zählt zum Zeilenende.</summary>
    function PositionAt(AOffset: Integer): TTextPosition;
    /// <summary>Offset (0-basiert) zur Position; Zeichen hinter dem Zeilenende → Zeilenende,
    /// negative Zeile → 0, Zeile hinter der letzten → Länge.</summary>
    function OffsetAt(const APosition: TTextPosition): Integer;
    /// <summary>Länge des Texts, für den die Tabelle gebaut wurde.</summary>
    property TextLength: Integer read FLength;
  end;

  TTextLines = class
  public
    /// <summary>#13#10, wenn AText irgendwo CRLF enthält, sonst #10.</summary>
    class function LineBreakOf(const AText: string): string; static;
    /// <summary>Art der Zeilenenden: None, CRLF, LF, CR oder Mixed.</summary>
    class function KindOf(const AText: string): TTextLineBreak; static;
    /// <summary>Häufigster Umbruch (bei Gleichstand CRLF vor LF vor CR); AMixed, wenn mehrere Arten
    /// vorkommen. Ohne Umbruch TTextLineBreak.None.</summary>
    class function DominantOf(const AText: string; out AMixed: Boolean): TTextLineBreak; overload; static;
    /// <summary>Wie oben; bei Gleichstand gewinnt APreferred, sofern er vorkommt.</summary>
    class function DominantOf(const AText: string; APreferred: TTextLineBreak;
      out AMixed: Boolean): TTextLineBreak; overload; static;
    /// <summary>Zeilen ohne Umbruch (CRLF, LF, CR); immer Anzahl Umbrüche + 1 Einträge.</summary>
    class function SplitLines(const AText: string): TArray<string>; overload; static;
    /// <summary>Wie oben, dazu ALineBreak = LineBreakOf(AText).</summary>
    class function SplitLines(const AText: string; out ALineBreak: string): TArray<string>; overload; static;
    /// <summary>Zeilen samt Umbruch; die letzte ohne, wenn AText nicht mit einem endet; leerer Text →
    /// leeres Array.</summary>
    class function SplitKeepingBreaks(const AText: string): TArray<string>; static;
    /// <summary>Zeilen mit ALineBreak dazwischen (nicht dahinter).</summary>
    class function JoinLines(const ALines: array of string; const ALineBreak: string): string; static;
    /// <summary>Führende Leerzeichen und Tabs.</summary>
    class function IndentOf(const ALine: string): string; overload; static;
    /// <summary>Einrückung der Zeile ALine (0-basiert) von AText; '' außerhalb.</summary>
    class function IndentOf(const AText: string; ALine: Integer): string; overload; static;
    /// <summary>Anzahl führender Leerzeichen und Tabs.</summary>
    class function IndentLength(const ALine: string): Integer; static;
    /// <summary>ALine ohne ein abschließendes #13.</summary>
    class function StripTrailingCr(const ALine: string): string; static;
    /// <summary>Alle Umbrüche (CRLF, LF, CR) durch ALineBreak ersetzen.</summary>
    class function NormalizeLineBreaks(const AText, ALineBreak: string): string; static;
  end;

implementation

{ TTextPosition }

constructor TTextPosition.Create(ALine, ACharacter: Integer);
begin
  Line := ALine;
  Character := ACharacter;
end;

class operator TTextPosition.Equal(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line = B.Line) and (A.Character = B.Character);
end;

class operator TTextPosition.NotEqual(const A, B: TTextPosition): Boolean;
begin
  Result := not (A = B);
end;

/// <summary>Länge des Umbruchs, der bei AIndex (1-basiert) beginnt: 2 für CRLF, 1 für LF oder CR, sonst 0.</summary>
function BreakLengthAt(const AText: string; AIndex: Integer): Integer;
begin
  if AText[AIndex] = #13 then
  begin
    if (AIndex < Length(AText)) and (AText[AIndex + 1] = #10) then
    begin
      Exit(2);
    end;
    Exit(1);
  end;
  if AText[AIndex] = #10 then
  begin
    Exit(1);
  end;
  Result := 0;
end;

/// <summary>Index (1-basiert) des nächsten CR oder LF ab AIndex, sonst Length(AText) + 1. Eine enge Schleife
/// ohne Aufruf je Zeichen: Große Units haben über eine Million Zeichen.</summary>
function NextBreak(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= Length(AText)) and ((AText[Result] > #13) or not CharInSet(AText[Result], [#10, #13])) do
  begin
    Inc(Result);
  end;
end;

function CountBreaks(const AText: string): Integer;
var
  Index: Integer;
begin
  Result := 0;
  Index := NextBreak(AText, 1);
  while Index <= Length(AText) do
  begin
    Inc(Result);
    Index := NextBreak(AText, Index + BreakLengthAt(AText, Index));
  end;
end;

{ TLineTable }

class function TLineTable.Build(const AText: string): TLineTable;
var
  Count, Line, Index, Len: Integer;
begin
  Count := CountBreaks(AText) + 1;
  Result.FStarts := nil;
  Result.FContentEnds := nil;
  SetLength(Result.FStarts, Count);
  SetLength(Result.FContentEnds, Count);
  Result.FLength := Length(AText);
  Result.FStarts[0] := 0;
  Line := 0;
  Index := NextBreak(AText, 1);
  while Index <= Length(AText) do
  begin
    Len := BreakLengthAt(AText, Index);
    // Index ist 1-basiert: Das Zeichen bei Index liegt am Offset Index - 1.
    Result.FContentEnds[Line] := Index - 1;
    Inc(Line);
    Result.FStarts[Line] := Index - 1 + Len;
    Index := NextBreak(AText, Index + Len);
  end;
  Result.FContentEnds[Line] := Length(AText);
end;

function TLineTable.LineCount: Integer;
begin
  Result := Length(FStarts);
end;

function TLineTable.LineStart(ALine: Integer): Integer;
begin
  if FStarts = nil then
  begin
    Exit(0);
  end;
  if ALine < 0 then
  begin
    ALine := 0;
  end
  else if ALine > High(FStarts) then
  begin
    ALine := High(FStarts);
  end;
  Result := FStarts[ALine];
end;

function TLineTable.LineContentEnd(ALine: Integer): Integer;
begin
  if FContentEnds = nil then
  begin
    Exit(0);
  end;
  if ALine < 0 then
  begin
    ALine := 0;
  end
  else if ALine > High(FContentEnds) then
  begin
    ALine := High(FContentEnds);
  end;
  Result := FContentEnds[ALine];
end;

function TLineTable.PositionAt(AOffset: Integer): TTextPosition;
var
  First, Last, Middle, Character: Integer;
begin
  if FStarts = nil then
  begin
    Exit(TTextPosition.Create(0, 0));
  end;
  if AOffset < 0 then
  begin
    AOffset := 0;
  end
  else if AOffset > FLength then
  begin
    AOffset := FLength;
  end;
  // Letzte Zeile, deren Anfang nicht hinter AOffset liegt.
  First := 0;
  Last := High(FStarts);
  while First < Last do
  begin
    Middle := (First + Last + 1) div 2;
    if FStarts[Middle] <= AOffset then
    begin
      First := Middle;
    end
    else
    begin
      Last := Middle - 1;
    end;
  end;
  Character := AOffset;
  if Character > FContentEnds[First] then
  begin
    Character := FContentEnds[First];
  end;
  Result := TTextPosition.Create(First, Character - FStarts[First]);
end;

function TLineTable.OffsetAt(const APosition: TTextPosition): Integer;
var
  Character: Integer;
begin
  if (FStarts = nil) or (APosition.Line < 0) then
  begin
    Exit(0);
  end;
  if APosition.Line > High(FStarts) then
  begin
    Exit(FLength);
  end;
  Character := APosition.Character;
  if Character < 0 then
  begin
    Character := 0;
  end
  else if Character > FContentEnds[APosition.Line] - FStarts[APosition.Line] then
  begin
    Character := FContentEnds[APosition.Line] - FStarts[APosition.Line];
  end;
  Result := FStarts[APosition.Line] + Character;
end;

{ TTextLines }

class function TTextLines.LineBreakOf(const AText: string): string;
begin
  if Pos(#13#10, AText) > 0 then
  begin
    Result := #13#10;
  end
  else
  begin
    Result := #10;
  end;
end;

class function TTextLines.KindOf(const AText: string): TTextLineBreak;
var
  Mixed: Boolean;
begin
  Result := DominantOf(AText, Mixed);
  if Mixed then
  begin
    Result := TTextLineBreak.Mixed;
  end;
end;

class function TTextLines.DominantOf(const AText: string; out AMixed: Boolean): TTextLineBreak;
begin
  Result := DominantOf(AText, TTextLineBreak.CRLF, AMixed);
end;

type
  TBreakCounts = array[TTextLineBreak] of Integer;

// Anzahl je Umbruchart; CR LF zählt als ein CRLF.
function BreakCounts(const AText: string): TBreakCounts;
var
  mKind: TTextLineBreak;
  mIndex: Integer;
begin
  for mKind := Low(TTextLineBreak) to High(TTextLineBreak) do
  begin
    Result[mKind] := 0;
  end;
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    if (AText[mIndex] = #13) and (mIndex < Length(AText)) and (AText[mIndex + 1] = #10) then
    begin
      Inc(Result[TTextLineBreak.CRLF]);
      Inc(mIndex);
    end
    else if AText[mIndex] = #13 then
    begin
      Inc(Result[TTextLineBreak.CR]);
    end
    else if AText[mIndex] = #10 then
    begin
      Inc(Result[TTextLineBreak.LF]);
    end;
    Inc(mIndex);
  end;
end;

class function TTextLines.DominantOf(const AText: string; APreferred: TTextLineBreak;
  out AMixed: Boolean): TTextLineBreak;
var
  Counts: TBreakCounts;
  Kind: TTextLineBreak;
  Kinds: Integer;
begin
  Counts := BreakCounts(AText);
  // Der bevorzugte Umbruch gewinnt Gleichstände, andere gewinnen nur mit echter Mehrheit.
  Result := TTextLineBreak.None;
  if (APreferred in [TTextLineBreak.CRLF, TTextLineBreak.LF, TTextLineBreak.CR]) and (Counts[APreferred] > 0) then
  begin
    Result := APreferred;
  end;
  Kinds := 0;
  for Kind := TTextLineBreak.CRLF to TTextLineBreak.CR do
  begin
    if Counts[Kind] > 0 then
    begin
      Inc(Kinds);
      if Counts[Kind] > Counts[Result] then
      begin
        Result := Kind;
      end;
    end;
  end;
  AMixed := Kinds > 1;
end;

class function TTextLines.SplitLines(const AText: string): TArray<string>;
var
  Index, Start, Count: Integer;
begin
  Result := nil;
  SetLength(Result, CountBreaks(AText) + 1);
  Count := 0;
  Start := 1;
  Index := NextBreak(AText, 1);
  while Index <= Length(AText) do
  begin
    Result[Count] := Copy(AText, Start, Index - Start);
    Inc(Count);
    Start := Index + BreakLengthAt(AText, Index);
    Index := NextBreak(AText, Start);
  end;
  Result[Count] := Copy(AText, Start, MaxInt);
end;

class function TTextLines.SplitLines(const AText: string; out ALineBreak: string): TArray<string>;
begin
  ALineBreak := LineBreakOf(AText);
  Result := SplitLines(AText);
end;

class function TTextLines.SplitKeepingBreaks(const AText: string): TArray<string>;
var
  Index, Start, Count, Len: Integer;
begin
  Result := nil;
  if AText = '' then
  begin
    Exit;
  end;
  Count := CountBreaks(AText);
  // Ohne Umbruch am Ende kommt die letzte Zeile ohne Umbruch dazu.
  if BreakLengthAt(AText, Length(AText)) = 0 then
  begin
    Inc(Count);
  end;
  SetLength(Result, Count);
  Count := 0;
  Start := 1;
  Index := NextBreak(AText, 1);
  while Index <= Length(AText) do
  begin
    Len := BreakLengthAt(AText, Index);
    Result[Count] := Copy(AText, Start, Index - Start + Len);
    Inc(Count);
    Start := Index + Len;
    Index := NextBreak(AText, Start);
  end;
  if Start <= Length(AText) then
  begin
    Result[Count] := Copy(AText, Start, MaxInt);
  end;
end;

class function TTextLines.JoinLines(const ALines: array of string; const ALineBreak: string): string;
var
  Builder: TStringBuilder;
  Index: Integer;
begin
  Builder := TStringBuilder.Create;
  try
    for Index := 0 to High(ALines) do
    begin
      if Index > 0 then
      begin
        Builder.Append(ALineBreak);
      end;
      Builder.Append(ALines[Index]);
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TTextLines.IndentLength(const ALine: string): Integer;
begin
  Result := 0;
  while (Result < Length(ALine)) and ((ALine[Result + 1] = ' ') or (ALine[Result + 1] = #9)) do
  begin
    Inc(Result);
  end;
end;

class function TTextLines.IndentOf(const ALine: string): string;
begin
  Result := Copy(ALine, 1, IndentLength(ALine));
end;

class function TTextLines.IndentOf(const AText: string; ALine: Integer): string;
var
  Table: TLineTable;
begin
  Table := TLineTable.Build(AText);
  if (ALine < 0) or (ALine >= Table.LineCount) then
  begin
    Exit('');
  end;
  Result := IndentOf(Copy(AText, Table.LineStart(ALine) + 1,
    Table.LineContentEnd(ALine) - Table.LineStart(ALine)));
end;

class function TTextLines.StripTrailingCr(const ALine: string): string;
begin
  if (ALine <> '') and (ALine[Length(ALine)] = #13) then
  begin
    Result := Copy(ALine, 1, Length(ALine) - 1);
  end
  else
  begin
    Result := ALine;
  end;
end;

class function TTextLines.NormalizeLineBreaks(const AText, ALineBreak: string): string;
var
  Builder: TStringBuilder;
  Index, Len: Integer;
begin
  Builder := TStringBuilder.Create(Length(AText));
  try
    Index := 1;
    while Index <= Length(AText) do
    begin
      Len := BreakLengthAt(AText, Index);
      if Len > 0 then
      begin
        Builder.Append(ALineBreak);
        Inc(Index, Len);
      end
      else
      begin
        Builder.Append(AText[Index]);
        Inc(Index);
      end;
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

end.
