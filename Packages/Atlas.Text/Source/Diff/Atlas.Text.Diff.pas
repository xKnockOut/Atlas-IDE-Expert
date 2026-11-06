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
    class procedure CommonPrefixSuffix(const AOld, ANew: TArray<string>; out APrefix, ASuffix: Integer); overload;
      static;
    /// <summary>Wie oben für die durch LF getrennten Zeilen von AOld und ANew, ohne die Texte in Zeilen zu
    /// zerlegen (große Units: bei jeder Änderung). AOldCount und ANewCount: Zeilen, also LF + 1.</summary>
    class procedure CommonPrefixSuffix(const AOld, ANew: string; out APrefix, ASuffix, AOldCount,
      ANewCount: Integer); overload; static;
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
  begin
    Inc(APrefix);
  end;
  ASuffix := 0;
  while (ASuffix < Length(AOld) - APrefix) and (ASuffix < Length(ANew) - APrefix) and
    (AOld[High(AOld) - ASuffix] = ANew[High(ANew) - ASuffix]) do
  begin
    Inc(ASuffix);
  end;
end;

/// <summary>Anzahl LF in AText[AFrom..ATo] (1-basiert, einschließlich).</summary>
function CountLineFeeds(const AText: string; AFrom, ATo: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := AFrom to ATo do
  begin
    if AText[mIndex] = #10 then
    begin
      Inc(Result);
    end;
  end;
end;

/// <summary>Endet bei AIndex (1-basiert, letztes Zeichen davor) eine Zeile: Textende oder LF dahinter?</summary>
function LineEndsAfter(const AText: string; AIndex: Integer): Boolean;
begin
  Result := (AIndex >= Length(AText)) or (AText[AIndex + 1] = #10);
end;

/// <summary>Beginnt bei AIndex (1-basiert) eine Zeile: Textanfang oder LF davor?</summary>
function LineStartsAt(const AText: string; AIndex: Integer): Boolean;
begin
  Result := (AIndex <= 1) or (AText[AIndex - 1] = #10);
end;

class procedure TTextDiff.CommonPrefixSuffix(const AOld, ANew: string; out APrefix, ASuffix, AOldCount,
  ANewCount: Integer);
var
  mSame, mTail, mLimit: Integer;
begin
  AOldCount := CountLineFeeds(AOld, 1, Length(AOld)) + 1;
  ANewCount := CountLineFeeds(ANew, 1, Length(ANew)) + 1;
  // Gleiche Zeichen am Anfang: Jedes LF darin schließt eine gleiche Zeile; die angefangene ist gleich, wenn
  // sie in beiden Texten hier endet.
  mLimit := Min(Length(AOld), Length(ANew));
  mSame := 0;
  while (mSame < mLimit) and (AOld[mSame + 1] = ANew[mSame + 1]) do
  begin
    Inc(mSame);
  end;
  APrefix := CountLineFeeds(AOld, 1, mSame);
  if LineEndsAfter(AOld, mSame) and LineEndsAfter(ANew, mSame) then
  begin
    Inc(APrefix);
  end;
  APrefix := Min(APrefix, Min(AOldCount, ANewCount));
  // Gleiche Zeichen am Ende entsprechend, ohne Überlappung mit dem Anfang in Zeilen.
  mTail := 0;
  while (mTail < mLimit) and (AOld[Length(AOld) - mTail] = ANew[Length(ANew) - mTail]) do
  begin
    Inc(mTail);
  end;
  ASuffix := CountLineFeeds(AOld, Length(AOld) - mTail + 1, Length(AOld));
  if LineStartsAt(AOld, Length(AOld) - mTail + 1) and LineStartsAt(ANew, Length(ANew) - mTail + 1) then
  begin
    Inc(ASuffix);
  end;
  ASuffix := Min(ASuffix, Min(AOldCount - APrefix, ANewCount - APrefix));
end;

type
  /// <summary>Schritt auf dem Weg durch die Mitte: gleiche Zeile, Zeile nur alt, Zeile nur neu.</summary>
  TDiffStep = (Same, OldOnly, NewOnly);

  /// <summary>Längste gemeinsame Teilfolge der Mitte (ohne gleichen Anfang und gleiches Ende).</summary>
  TDiffMiddle = record
    OldLines, NewLines: TArray<string>;
    Prefix, OldCount, NewCount: Integer;
    /// <summary>Von hinten: Table[Row * (NewCount + 1) + Column] für OldLines[Row..] und NewLines[Column..].</summary>
    Table: TArray<Integer>;
    procedure Build;
    function Cell(ARow, AColumn: Integer): Integer;
    function Step(ARow, AColumn: Integer): TDiffStep;
  end;

  /// <summary>Sammelt die Blöcke beim Weg durch die Mitte.</summary>
  THunkCollector = record
    Hunks: TArray<TTextLineHunk>;
    Hunk: TTextLineHunk;
    Open: Boolean;
    procedure Flush;
    procedure Touch(AOldLine, ANewLine: Integer);
  end;

{ TDiffMiddle }

function TDiffMiddle.Cell(ARow, AColumn: Integer): Integer;
begin
  Result := Table[ARow * (NewCount + 1) + AColumn];
end;

procedure TDiffMiddle.Build;
var
  mRow, mColumn: Integer;
begin
  Table := nil;
  SetLength(Table, (OldCount + 1) * (NewCount + 1));
  for mRow := OldCount - 1 downto 0 do
  begin
    for mColumn := NewCount - 1 downto 0 do
    begin
      if OldLines[Prefix + mRow] = NewLines[Prefix + mColumn] then
      begin
        Table[mRow * (NewCount + 1) + mColumn] := Cell(mRow + 1, mColumn + 1) + 1;
      end
      else
      begin
        Table[mRow * (NewCount + 1) + mColumn] := Max(Cell(mRow + 1, mColumn), Cell(mRow, mColumn + 1));
      end;
    end;
  end;
end;

function TDiffMiddle.Step(ARow, AColumn: Integer): TDiffStep;
begin
  if (ARow < OldCount) and (AColumn < NewCount) and (OldLines[Prefix + ARow] = NewLines[Prefix + AColumn]) then
  begin
    Result := TDiffStep.Same;
  end
  else if (AColumn = NewCount) or ((ARow < OldCount) and (Cell(ARow + 1, AColumn) >= Cell(ARow, AColumn + 1))) then
  begin
    Result := TDiffStep.OldOnly;
  end
  else
  begin
    Result := TDiffStep.NewOnly;
  end;
end;

{ THunkCollector }

procedure THunkCollector.Flush;
begin
  if Open then
  begin
    Hunks := Hunks + [Hunk];
  end;
  Open := False;
end;

procedure THunkCollector.Touch(AOldLine, ANewLine: Integer);
begin
  if Open then
  begin
    Exit;
  end;
  Open := True;
  Hunk.OldStart := AOldLine;
  Hunk.NewStart := ANewLine;
  Hunk.OldCount := 0;
  Hunk.NewCount := 0;
end;

// Nur auf einer Seite etwas oder zu groß für den genauen Vergleich: ein Block.
function IsSingleHunk(AOldCount, ANewCount: Integer): Boolean;
begin
  Result := (AOldCount = 0) or (ANewCount = 0) or (Int64(AOldCount + 1) * (ANewCount + 1) > TTextDiff.MaxCells);
end;

class function TTextDiff.Hunks(const AOld, ANew: TArray<string>): TArray<TTextLineHunk>;
var
  mMiddle: TDiffMiddle;
  mCollector: THunkCollector;
  mSuffix, mRow, mColumn: Integer;
begin
  Result := nil;
  mMiddle := Default(TDiffMiddle);
  mMiddle.OldLines := AOld;
  mMiddle.NewLines := ANew;
  CommonPrefixSuffix(AOld, ANew, mMiddle.Prefix, mSuffix);
  mMiddle.OldCount := Length(AOld) - mMiddle.Prefix - mSuffix;
  mMiddle.NewCount := Length(ANew) - mMiddle.Prefix - mSuffix;
  if (mMiddle.OldCount = 0) and (mMiddle.NewCount = 0) then
  begin
    Exit;
  end;
  mCollector := Default(THunkCollector);
  if IsSingleHunk(mMiddle.OldCount, mMiddle.NewCount) then
  begin
    mCollector.Touch(mMiddle.Prefix, mMiddle.Prefix);
    mCollector.Hunk.OldCount := mMiddle.OldCount;
    mCollector.Hunk.NewCount := mMiddle.NewCount;
    mCollector.Flush;
    Exit(mCollector.Hunks);
  end;
  mMiddle.Build;
  mRow := 0;
  mColumn := 0;
  while (mRow < mMiddle.OldCount) or (mColumn < mMiddle.NewCount) do
  begin
    case mMiddle.Step(mRow, mColumn) of
      TDiffStep.Same:
        begin
          mCollector.Flush;
          Inc(mRow);
          Inc(mColumn);
        end;
      TDiffStep.OldOnly:
        begin
          mCollector.Touch(mMiddle.Prefix + mRow, mMiddle.Prefix + mColumn);
          Inc(mCollector.Hunk.OldCount);
          Inc(mRow);
        end;
      TDiffStep.NewOnly:
        begin
          mCollector.Touch(mMiddle.Prefix + mRow, mMiddle.Prefix + mColumn);
          Inc(mCollector.Hunk.NewCount);
          Inc(mColumn);
        end;
    end;
  end;
  mCollector.Flush;
  Result := mCollector.Hunks;
end;

class function TTextDiff.ChangedLines(const AOld, ANew: TArray<string>; AMaxLines: Integer): TArray<string>;
var
  Prefix, Suffix, Index, Count: Integer;
  Full: Boolean;

  procedure Add(const AText: string);
  begin
    if Full then
    begin
      Exit;
    end;
    if (AMaxLines >= 0) and (Count >= AMaxLines) then
    begin
      // Begrenzung erreicht: einmal "…", danach nichts mehr.
      Full := True;
      if Count = Length(Result) then
      begin
        SetLength(Result, Count * 2 + 1);
      end;
      Result[Count] := '…';
      Inc(Count);
      Exit;
    end;
    if Count = Length(Result) then
    begin
      SetLength(Result, Count * 2 + 8);
    end;
    Result[Count] := AText;
    Inc(Count);
  end;

begin
  Result := nil;
  Count := 0;
  Full := False;
  CommonPrefixSuffix(AOld, ANew, Prefix, Suffix);
  if (Prefix = Length(AOld)) and (Prefix = Length(ANew)) then
  begin
    Exit;
  end;
  if Length(AOld) = Length(ANew) then
  begin
    // Gleiche Zeilenzahl (z. B. Umbenennen): nur die geänderten Zeilen.
    for Index := Prefix to High(AOld) - Suffix do
    begin
      if AOld[Index] <> ANew[Index] then
      begin
        Add(Format('Zeile %d:', [Index + 1]));
        Add('- ' + AOld[Index]);
        Add('+ ' + ANew[Index]);
      end;
    end;
  end
  else
  begin
    Add(Format('ab Zeile %d:', [Prefix + 1]));
    for Index := Prefix to High(AOld) - Suffix do
    begin
      Add('- ' + AOld[Index]);
    end;
    for Index := Prefix to High(ANew) - Suffix do
    begin
      Add('+ ' + ANew[Index]);
    end;
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
  begin
    Result := Format('%d,0', [AStart]);
  end
  else if ACount = 1 then
  begin
    Result := IntToStr(AStart + 1);
  end
  else
  begin
    Result := Format('%d,%d', [AStart + 1, ACount]);
  end;
end;

// Hängt ALines[AFrom..ATo - 1] mit Kennzeichen AMark an; Ergebnis ist die Zahl der Zeilen.
function AppendLines(var ABlock: TArray<string>; const AMark: string; const ALines: TArray<string>;
  AFrom, ATo: Integer): Integer;
var
  mLine: Integer;
begin
  for mLine := AFrom to ATo - 1 do
  begin
    ABlock := ABlock + [AMark + ALines[mLine]];
  end;
  Result := Max(ATo - AFrom, 0);
end;

// Letzter Block des Abschnitts ab AFirst: Folgeblöcke, deren Umgebung an die des vorigen stößt, gehören dazu.
function SectionEnd(const AHunks: TArray<TTextLineHunk>; AFirst, AContext: Integer): Integer;
begin
  Result := AFirst;
  while (Result < High(AHunks)) and
    (AHunks[Result + 1].OldStart - (AHunks[Result].OldStart + AHunks[Result].OldCount) <= 2 * AContext) do
  begin
    Inc(Result);
  end;
end;

class function TTextDiff.Unified(const AOldName, ANewName: string; const AOld, ANew: TArray<string>;
  AContext: Integer): TArray<string>;
var
  mHunks: TArray<TTextLineHunk>;
  mFirst, mLast, mIndex, mOldStart, mOldStop, mNewStart, mOldLine, mNewLine, mContext, mCount: Integer;
  mBlock: TArray<string>;
begin
  Result := nil;
  mHunks := Hunks(AOld, ANew);
  if Length(mHunks) = 0 then
  begin
    Exit;
  end;
  mContext := Max(AContext, 0);
  Result := ['--- ' + AOldName, '+++ ' + ANewName];
  mFirst := 0;
  while mFirst <= High(mHunks) do
  begin
    mLast := SectionEnd(mHunks, mFirst, mContext);
    mOldStart := Max(mHunks[mFirst].OldStart - mContext, 0);
    mNewStart := mHunks[mFirst].NewStart - (mHunks[mFirst].OldStart - mOldStart);
    mOldStop := Min(mHunks[mLast].OldStart + mHunks[mLast].OldCount + mContext, Length(AOld));
    mBlock := nil;
    mOldLine := mOldStart;
    mNewLine := mNewStart;
    for mIndex := mFirst to mLast do
    begin
      mCount := AppendLines(mBlock, ' ', AOld, mOldLine, mHunks[mIndex].OldStart);
      Inc(mOldLine, mCount);
      Inc(mNewLine, mCount);
      Inc(mOldLine, AppendLines(mBlock, '-', AOld, mOldLine, mHunks[mIndex].OldStart + mHunks[mIndex].OldCount));
      Inc(mNewLine, AppendLines(mBlock, '+', ANew, mNewLine, mHunks[mIndex].NewStart + mHunks[mIndex].NewCount));
    end;
    mCount := AppendLines(mBlock, ' ', AOld, mOldLine, mOldStop);
    Inc(mNewLine, mCount);
    Result := Result + [Format('@@ -%s +%s @@', [UnifiedRange(mOldStart, mOldStop - mOldStart),
      UnifiedRange(mNewStart, mNewLine - mNewStart)])] + mBlock;
    mFirst := mLast + 1;
  end;
end;

end.
