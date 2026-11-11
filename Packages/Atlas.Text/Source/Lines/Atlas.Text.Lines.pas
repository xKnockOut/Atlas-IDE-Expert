unit Atlas.Text.Lines;

// Zeilen und Positionen in Texten mit CRLF, LF oder CR (gemeinsam für Server
// und Plugin).
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
  mIndex: Integer;
begin
  Result := 0;
  mIndex := NextBreak(AText, 1);
  while mIndex <= Length(AText) do
  begin
    Inc(Result);
    mIndex := NextBreak(AText, mIndex + BreakLengthAt(AText, mIndex));
  end;
end;

{ TLineTable }

class function TLineTable.Build(const AText: string): TLineTable;
var
  mCount, mLine, mIndex, mLen: Integer;
begin
  mCount := CountBreaks(AText) + 1;
  Result.FStarts := nil;
  Result.FContentEnds := nil;
  SetLength(Result.FStarts, mCount);
  SetLength(Result.FContentEnds, mCount);
  Result.FLength := Length(AText);
  Result.FStarts[0] := 0;
  mLine := 0;
  mIndex := NextBreak(AText, 1);
  while mIndex <= Length(AText) do
  begin
    mLen := BreakLengthAt(AText, mIndex);
    // Index ist 1-basiert: Das Zeichen bei Index liegt am Offset Index - 1.
    Result.FContentEnds[mLine] := mIndex - 1;
    Inc(mLine);
    Result.FStarts[mLine] := mIndex - 1 + mLen;
    mIndex := NextBreak(AText, mIndex + mLen);
  end;
  Result.FContentEnds[mLine] := Length(AText);
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
  mFirst, mLast, mMiddle, mCharacter: Integer;
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
  mFirst := 0;
  mLast := High(FStarts);
  while mFirst < mLast do
  begin
    mMiddle := (mFirst + mLast + 1) div 2;
    if FStarts[mMiddle] <= AOffset then
    begin
      mFirst := mMiddle;
    end
    else
    begin
      mLast := mMiddle - 1;
    end;
  end;
  mCharacter := AOffset;
  if mCharacter > FContentEnds[mFirst] then
  begin
    mCharacter := FContentEnds[mFirst];
  end;
  Result := TTextPosition.Create(mFirst, mCharacter - FStarts[mFirst]);
end;

function TLineTable.OffsetAt(const APosition: TTextPosition): Integer;
var
  mCharacter: Integer;
begin
  if (FStarts = nil) or (APosition.Line < 0) then
  begin
    Exit(0);
  end;
  if APosition.Line > High(FStarts) then
  begin
    Exit(FLength);
  end;
  mCharacter := APosition.Character;
  if mCharacter < 0 then
  begin
    mCharacter := 0;
  end
  else if mCharacter > FContentEnds[APosition.Line] - FStarts[APosition.Line] then
  begin
    mCharacter := FContentEnds[APosition.Line] - FStarts[APosition.Line];
  end;
  Result := FStarts[APosition.Line] + mCharacter;
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
  mMixed: Boolean;
begin
  Result := DominantOf(AText, mMixed);
  if mMixed then
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
  mCounts: TBreakCounts;
  mKind: TTextLineBreak;
  mKinds: Integer;
begin
  mCounts := BreakCounts(AText);
  // Der bevorzugte Umbruch gewinnt Gleichstände, andere gewinnen nur mit echter Mehrheit.
  Result := TTextLineBreak.None;
  if (APreferred in [TTextLineBreak.CRLF, TTextLineBreak.LF, TTextLineBreak.CR]) and (mCounts[APreferred] > 0) then
  begin
    Result := APreferred;
  end;
  mKinds := 0;
  for mKind := TTextLineBreak.CRLF to TTextLineBreak.CR do
  begin
    if mCounts[mKind] > 0 then
    begin
      Inc(mKinds);
      if mCounts[mKind] > mCounts[Result] then
      begin
        Result := mKind;
      end;
    end;
  end;
  AMixed := mKinds > 1;
end;

class function TTextLines.SplitLines(const AText: string): TArray<string>;
var
  mIndex, mStart, mCount: Integer;
begin
  Result := nil;
  SetLength(Result, CountBreaks(AText) + 1);
  mCount := 0;
  mStart := 1;
  mIndex := NextBreak(AText, 1);
  while mIndex <= Length(AText) do
  begin
    Result[mCount] := Copy(AText, mStart, mIndex - mStart);
    Inc(mCount);
    mStart := mIndex + BreakLengthAt(AText, mIndex);
    mIndex := NextBreak(AText, mStart);
  end;
  Result[mCount] := Copy(AText, mStart, MaxInt);
end;

class function TTextLines.SplitLines(const AText: string; out ALineBreak: string): TArray<string>;
begin
  ALineBreak := LineBreakOf(AText);
  Result := SplitLines(AText);
end;

class function TTextLines.SplitKeepingBreaks(const AText: string): TArray<string>;
var
  mIndex, mStart, mCount, mLen: Integer;
begin
  Result := nil;
  if AText = '' then
  begin
    Exit;
  end;
  mCount := CountBreaks(AText);
  // Ohne Umbruch am Ende kommt die letzte Zeile ohne Umbruch dazu.
  if BreakLengthAt(AText, Length(AText)) = 0 then
  begin
    Inc(mCount);
  end;
  SetLength(Result, mCount);
  mCount := 0;
  mStart := 1;
  mIndex := NextBreak(AText, 1);
  while mIndex <= Length(AText) do
  begin
    mLen := BreakLengthAt(AText, mIndex);
    Result[mCount] := Copy(AText, mStart, mIndex - mStart + mLen);
    Inc(mCount);
    mStart := mIndex + mLen;
    mIndex := NextBreak(AText, mStart);
  end;
  if mStart <= Length(AText) then
  begin
    Result[mCount] := Copy(AText, mStart, MaxInt);
  end;
end;

class function TTextLines.JoinLines(const ALines: array of string; const ALineBreak: string): string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mIndex := 0 to High(ALines) do
    begin
      if mIndex > 0 then
      begin
        mBuilder.Append(ALineBreak);
      end;
      mBuilder.Append(ALines[mIndex]);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
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
  mTable: TLineTable;
begin
  mTable := TLineTable.Build(AText);
  if (ALine < 0) or (ALine >= mTable.LineCount) then
  begin
    Exit('');
  end;
  Result := IndentOf(Copy(AText, mTable.LineStart(ALine) + 1,
    mTable.LineContentEnd(ALine) - mTable.LineStart(ALine)));
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
  mBuilder: TStringBuilder;
  mIndex, mLen: Integer;
begin
  mBuilder := TStringBuilder.Create(Length(AText));
  try
    mIndex := 1;
    while mIndex <= Length(AText) do
    begin
      mLen := BreakLengthAt(AText, mIndex);
      if mLen > 0 then
      begin
        mBuilder.Append(ALineBreak);
        Inc(mIndex, mLen);
      end
      else
      begin
        mBuilder.Append(AText[mIndex]);
        Inc(mIndex);
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

end.
