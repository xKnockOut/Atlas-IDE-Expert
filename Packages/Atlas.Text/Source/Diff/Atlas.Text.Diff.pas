unit Atlas.Text.Diff;

// Zeilenvergleich (gemeinsam für Server und Plugin, ADR 0012): gleicher Anfang
// und gleiches Ende, geänderte Blöcke über die längste gemeinsame Teilfolge
// und eine lesbare Ausgabe „Zeile n:“ bzw. „ab Zeile n:“ mit "- " alt und
// "+ " neu. Wer die Zeilen wie trennt, entscheidet der Aufrufer
// (TTextLines.SplitLines oder SplitKeepingBreaks). Unified liefert dieselben
// Blöcke als vereinigten Diff wie "diff -u" (#1358).

interface

type
  /// <summary>Geänderter Zeilenblock: im alten Text ab OldStart OldCount Zeilen, im neuen ab NewStart
  /// NewCount Zeilen (0-basiert).</summary>
  TTextLineHunk = record
    OldStart: Integer;
    OldCount: Integer;
    NewStart: Integer;
    NewCount: Integer;
  end;

  TTextDiff = class
  public const
    /// <summary>Größte Fläche (Zeilen alt × neu) für den genauen Vergleich der Mitte.</summary>
    MaxCells = 4000000;
  public
    /// <summary>Anzahl gleicher Zeilen am Anfang und (ohne Überlappung mit dem Anfang) am Ende.</summary>
    class procedure CommonPrefixSuffix(const AOld, ANew: TArray<string>; out APrefix, ASuffix: Integer); static;
    /// <summary>Geänderte Blöcke von AOld nach ANew, aufsteigend (LCS der Mitte; ist sie größer als
    /// MaxCells, ein Block).</summary>
    class function Hunks(const AOld, ANew: TArray<string>): TArray<TTextLineHunk>; static;
    /// <summary>Bei gleicher Zeilenzahl je geänderte Zeile "Zeile n:", "- alt", "+ neu"; sonst
    /// "ab Zeile n:" und der geänderte Block. Höchstens AMaxLines Einträge, dann "…". Leer, wenn gleich.</summary>
    class function ChangedLines(const AOld, ANew: TArray<string>; AMaxLines: Integer): TArray<string>;
      overload; static;
    /// <summary>Wie oben, ohne Begrenzung.</summary>
    class function ChangedLines(const AOld, ANew: TArray<string>): TArray<string>; overload; static;
    /// <summary>Vereinigter Diff (#1358): "--- AOldName", "+++ ANewName" und je Block "@@ -a,b +c,d @@" mit
    /// AContext Zeilen Umgebung; Blöcke, deren Umgebung sich berührt, werden zusammengefasst. Leer, wenn gleich.
    /// </summary>
    class function Unified(const AOldName, ANewName: string; const AOld, ANew: TArray<string>;
      AContext: Integer): TArray<string>; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

{ TTextDiff }

class procedure TTextDiff.CommonPrefixSuffix(const AOld, ANew: TArray<string>; out APrefix, ASuffix: Integer);
begin
  APrefix := 0;
  while (APrefix < Length(AOld)) and (APrefix < Length(ANew)) and (AOld[APrefix] = ANew[APrefix]) do
    Inc(APrefix);
  ASuffix := 0;
  while (ASuffix < Length(AOld) - APrefix) and (ASuffix < Length(ANew) - APrefix) and
    (AOld[High(AOld) - ASuffix] = ANew[High(ANew) - ASuffix]) do
    Inc(ASuffix);
end;

class function TTextDiff.Hunks(const AOld, ANew: TArray<string>): TArray<TTextLineHunk>;
var
  Prefix, Suffix, OldCount, NewCount, Row, Column, Width: Integer;
  Table: TArray<Integer>;
  Hunk: TTextLineHunk;
  Open: Boolean;

  procedure Flush;
  begin
    if Open then
      Result := Result + [Hunk];
    Open := False;
  end;

  procedure Touch(AOldLine, ANewLine: Integer);
  begin
    if Open then
      Exit;
    Open := True;
    Hunk.OldStart := AOldLine;
    Hunk.NewStart := ANewLine;
    Hunk.OldCount := 0;
    Hunk.NewCount := 0;
  end;

begin
  Result := nil;
  CommonPrefixSuffix(AOld, ANew, Prefix, Suffix);
  OldCount := Length(AOld) - Prefix - Suffix;
  NewCount := Length(ANew) - Prefix - Suffix;
  if (OldCount = 0) and (NewCount = 0) then
    Exit;
  Hunk := Default(TTextLineHunk);
  if (OldCount = 0) or (NewCount = 0) or (Int64(OldCount + 1) * (NewCount + 1) > MaxCells) then
  begin
    // Nur auf einer Seite etwas oder zu groß: ein Block.
    Hunk.OldStart := Prefix;
    Hunk.OldCount := OldCount;
    Hunk.NewStart := Prefix;
    Hunk.NewCount := NewCount;
    Result := [Hunk];
    Exit;
  end;
  // Längste gemeinsame Teilfolge der Mitte, von hinten: Table[Row, Column] für AOld[Row..] und ANew[Column..].
  Width := NewCount + 1;
  Table := nil;
  SetLength(Table, (OldCount + 1) * Width);
  for Row := OldCount - 1 downto 0 do
    for Column := NewCount - 1 downto 0 do
      if AOld[Prefix + Row] = ANew[Prefix + Column] then
        Table[Row * Width + Column] := Table[(Row + 1) * Width + Column + 1] + 1
      else
        Table[Row * Width + Column] := Max(Table[(Row + 1) * Width + Column], Table[Row * Width + Column + 1]);
  Open := False;
  Row := 0;
  Column := 0;
  while (Row < OldCount) or (Column < NewCount) do
  begin
    if (Row < OldCount) and (Column < NewCount) and (AOld[Prefix + Row] = ANew[Prefix + Column]) then
    begin
      Flush;
      Inc(Row);
      Inc(Column);
    end
    else if (Column = NewCount) or ((Row < OldCount) and
      (Table[(Row + 1) * Width + Column] >= Table[Row * Width + Column + 1])) then
    begin
      Touch(Prefix + Row, Prefix + Column);
      Inc(Hunk.OldCount);
      Inc(Row);
    end
    else
    begin
      Touch(Prefix + Row, Prefix + Column);
      Inc(Hunk.NewCount);
      Inc(Column);
    end;
  end;
  Flush;
end;

class function TTextDiff.ChangedLines(const AOld, ANew: TArray<string>; AMaxLines: Integer): TArray<string>;
var
  Prefix, Suffix, Index, Count: Integer;
  Full: Boolean;

  procedure Add(const AText: string);
  begin
    if Full then
      Exit;
    if (AMaxLines >= 0) and (Count >= AMaxLines) then
    begin
      // Begrenzung erreicht: einmal "…", danach nichts mehr.
      Full := True;
      if Count = Length(Result) then
        SetLength(Result, Count * 2 + 1);
      Result[Count] := '…';
      Inc(Count);
      Exit;
    end;
    if Count = Length(Result) then
      SetLength(Result, Count * 2 + 8);
    Result[Count] := AText;
    Inc(Count);
  end;

begin
  Result := nil;
  Count := 0;
  Full := False;
  CommonPrefixSuffix(AOld, ANew, Prefix, Suffix);
  if (Prefix = Length(AOld)) and (Prefix = Length(ANew)) then
    Exit;
  if Length(AOld) = Length(ANew) then
  begin
    // Gleiche Zeilenzahl (z. B. Umbenennen): nur die geänderten Zeilen.
    for Index := Prefix to High(AOld) - Suffix do
      if AOld[Index] <> ANew[Index] then
      begin
        Add(Format('Zeile %d:', [Index + 1]));
        Add('- ' + AOld[Index]);
        Add('+ ' + ANew[Index]);
      end;
  end
  else
  begin
    Add(Format('ab Zeile %d:', [Prefix + 1]));
    for Index := Prefix to High(AOld) - Suffix do
      Add('- ' + AOld[Index]);
    for Index := Prefix to High(ANew) - Suffix do
      Add('+ ' + ANew[Index]);
  end;
  SetLength(Result, Count);
end;

class function TTextDiff.ChangedLines(const AOld, ANew: TArray<string>): TArray<string>;
begin
  Result := ChangedLines(AOld, ANew, -1);
end;

/// <summary>Bereich im Kopf eines Blocks: Start ab 1 und Anzahl; ein leerer Bereich nennt die Zeile davor.</summary>
function UnifiedRange(AStart, ACount: Integer): string;
begin
  if ACount = 0 then
    Result := Format('%d,0', [AStart])
  else if ACount = 1 then
    Result := IntToStr(AStart + 1)
  else
    Result := Format('%d,%d', [AStart + 1, ACount]);
end;

class function TTextDiff.Unified(const AOldName, ANewName: string; const AOld, ANew: TArray<string>;
  AContext: Integer): TArray<string>;
var
  mHunks: TArray<TTextLineHunk>;
  mFirst, mLast, mIndex, mOldStart, mOldStop, mNewStart, mOldLine, mNewLine, mContext: Integer;
  mBlock: TArray<string>;
begin
  Result := nil;
  mHunks := Hunks(AOld, ANew);
  if Length(mHunks) = 0 then
    Exit;
  mContext := Max(AContext, 0);
  Result := ['--- ' + AOldName, '+++ ' + ANewName];
  mFirst := 0;
  while mFirst <= High(mHunks) do
  begin
    // Folgeblöcke, deren Umgebung an die des vorigen stößt, gehören in denselben Abschnitt.
    mLast := mFirst;
    while (mLast < High(mHunks)) and (mHunks[mLast + 1].OldStart - (mHunks[mLast].OldStart +
      mHunks[mLast].OldCount) <= 2 * mContext) do
      Inc(mLast);
    mOldStart := Max(mHunks[mFirst].OldStart - mContext, 0);
    mNewStart := mHunks[mFirst].NewStart - (mHunks[mFirst].OldStart - mOldStart);
    mOldStop := Min(mHunks[mLast].OldStart + mHunks[mLast].OldCount + mContext, Length(AOld));
    mBlock := nil;
    mOldLine := mOldStart;
    mNewLine := mNewStart;
    for mIndex := mFirst to mLast do
    begin
      while mOldLine < mHunks[mIndex].OldStart do
      begin
        mBlock := mBlock + [' ' + AOld[mOldLine]];
        Inc(mOldLine);
        Inc(mNewLine);
      end;
      while mOldLine < mHunks[mIndex].OldStart + mHunks[mIndex].OldCount do
      begin
        mBlock := mBlock + ['-' + AOld[mOldLine]];
        Inc(mOldLine);
      end;
      while mNewLine < mHunks[mIndex].NewStart + mHunks[mIndex].NewCount do
      begin
        mBlock := mBlock + ['+' + ANew[mNewLine]];
        Inc(mNewLine);
      end;
    end;
    while mOldLine < mOldStop do
    begin
      mBlock := mBlock + [' ' + AOld[mOldLine]];
      Inc(mOldLine);
      Inc(mNewLine);
    end;
    Result := Result + [Format('@@ -%s +%s @@', [UnifiedRange(mOldStart, mOldStop - mOldStart),
      UnifiedRange(mNewStart, mNewLine - mNewStart)])] + mBlock;
    mFirst := mLast + 1;
  end;
end;

end.
