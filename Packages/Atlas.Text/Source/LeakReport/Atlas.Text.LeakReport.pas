unit Atlas.Text.LeakReport;

// Liest Leckberichte beim Programmende (#1875, #74):
// - das Meldungsfenster von ReportMemoryLeaksOnShutdown (Speichermanager der
//   RTL): Zeilen „13 - 20 bytes: TKunde x 3, UnicodeString x 5“ und die
//   Größen der mittleren und großen Blöcke,
// - die Logdatei von FastMM4 und FastMM5: Einträge zwischen Trennzeilen
//   „-----…-----“, je geleaktem Block Größe, Klasse und (FullDebugMode)
//   Aufrufstapel „4068F6 [System.pas][System][@GetMem$qqri][4843]“, dazu
//   die Zusammenfassung wie im Meldungsfenster.
// Die Texte erkennt der Leser vor allem am Aufbau (Trennzeilen, „Name x Anzahl“,
// Zahl hinter dem letzten Doppelpunkt, Stapelzeilen); nur die Klasse eines
// Blocks und die Zeile der großen Blöcke suchen auch deutsche Wörter. Hängt
// FastMM mehrere Läufe an dieselbe Datei, zählt nur der letzte.
// In Atlas.Text, weil das Plugin (Meldungsfenster, Logdatei) und der Server
// (Kandidaten, MCP) denselben Leser brauchen.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  /// <summary>Art eines Lecks: Objekt einer Klasse, String oder unbekannter Block (Arrays, GetMem).</summary>
  TLeakKind = (Instance, Text, Unknown);
{$SCOPEDENUMS OFF}

  /// <summary>Eine Zeile des Aufrufstapels; ohne Debug-Informationen nur die Adresse.</summary>
  TLeakFrame = record
    Address: UInt64;
    FileName: string;
    UnitName: string;
    Routine: string;
    /// <summary>Zeile ab 1; 0 ohne Zeilennummer.</summary>
    Line: Integer;
  end;

  /// <summary>Zahl der Lecks eines Namens über alle Größenklassen.</summary>
  TLeakCount = record
    Name: string;
    Kind: TLeakKind;
    Count: Integer;
    MinSize: Integer;
    MaxSize: Integer;
  end;

  /// <summary>Ein geleakter Block aus der Logdatei (nur FastMM).</summary>
  TLeakBlock = record
    Size: Integer;
    Name: string;
    Kind: TLeakKind;
    Frames: TArray<TLeakFrame>;
  end;

  /// <summary>Gleichartige Blöcke: gleicher Name und gleicher Aufrufstapel.</summary>
  TLeakGroup = record
    Name: string;
    Kind: TLeakKind;
    Count: Integer;
    TotalSize: Int64;
    Frames: TArray<TLeakFrame>;
    /// <summary>Index der Erzeugungsstelle in Frames (erste Zeile außerhalb von RTL und FastMM); -1 ohne.</summary>
    Site: Integer;
  end;

  TLeakReport = record
    /// <summary>Je Name zusammengefasst, nach Anzahl absteigend.</summary>
    Counts: TArray<TLeakCount>;
    /// <summary>Größen der mittleren und großen Blöcke in Byte.</summary>
    LargeSizes: TArray<Int64>;
    Blocks: TArray<TLeakBlock>;
    function IsEmpty: Boolean;
    /// <summary>Hat mindestens ein Block einen Aufrufstapel (FullDebugMode)?</summary>
    function HasStacks: Boolean;
    /// <summary>Anzahl der Lecks mit dem Namen AName; 0 ohne.</summary>
    function CountOf(const AName: string): Integer;
    /// <summary>Blöcke nach Name und Stapel zusammengefasst, nach Anzahl absteigend.</summary>
    function Groups: TArray<TLeakGroup>;
  end;

  TLeakReports = class
  public
    /// <summary>Bericht aus dem Text des Meldungsfensters oder der Logdatei; leer, wenn keiner darin steht.</summary>
    class function Parse(const AText: string): TLeakReport; static;
    /// <summary>Zeile des Aufrufstapels; False bei anderem Text (auch Speicherauszug).</summary>
    class function ParseFrame(const ALine: string; out AFrame: TLeakFrame): Boolean; static;
    /// <summary>Art zu einem Namen aus dem Bericht.</summary>
    class function KindOf(const AName: string): TLeakKind; static;
    /// <summary>Erste Zeile mit Unit außerhalb von System, SysInit und FastMM; -1 ohne.</summary>
    class function SiteOf(const AFrames: TArray<TLeakFrame>): Integer; static;
  end;

implementation

uses
  Atlas.Text.Lines;

const
  cSeparatorStart = '-----';
  cMinAddressDigits = 6;
  cMaxAddressDigits = 16;
  cBitsPerHexDigit = 4;
  // Felder einer Stapelzeile „[Datei][Unit][Routine][Zeile]“.
  cFieldFile = 0;
  cFieldUnit = 1;
  cFieldRoutine = 2;
  cFieldLine = 3;
  // „Name x Anzahl“ in der Zusammenfassung.
  cCountMark = ' x ';
  cSystemPrefix = 'system.';
  cFastMMPrefix = 'fastmm';
  cTextNames: array[0..4] of string = ('UnicodeString', 'AnsiString', 'WideString', 'RawByteString', 'String');
  cUnknownNames: array[0..1] of string = ('Unknown', 'Unbekannt');

type
  TLeakLines = TArray<string>;

function IsHexDigit(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['0'..'9', 'A'..'F', 'a'..'f']);
end;

function IsDigits(const AText: string): Boolean;
var
  mIndex: Integer;
begin
  Result := AText <> '';
  for mIndex := 1 to Length(AText) do
  begin
    if not CharInSet(AText[mIndex], ['0'..'9']) then
    begin
      Exit(False);
    end;
  end;
end;

function HexValue(const AText: string): UInt64;
var
  mIndex: Integer;
  mDigit: Integer;
begin
  Result := 0;
  for mIndex := 1 to Length(AText) do
  begin
    mDigit := Pos(UpCase(AText[mIndex]), '0123456789ABCDEF') - 1;
    Result := (Result shl cBitsPerHexDigit) or UInt64(mDigit);
  end;
end;

function IsSeparator(const ALine: string): Boolean;
begin
  Result := Copy(Trim(ALine), 1, Length(cSeparatorStart)) = cSeparatorStart;
end;

/// <summary>Text hinter dem letzten Doppelpunkt; '' ohne.</summary>
function AfterLastColon(const ALine: string): string;
begin
  Result := '';
  if LastDelimiter(':', ALine) > 0 then
  begin
    Result := Trim(Copy(ALine, LastDelimiter(':', ALine) + 1, MaxInt));
  end;
end;

/// <summary>„40100, 80000“ als Zahlen; False, wenn ein Teil keine Zahl ist.</summary>
function ReadSizes(const AText: string; out ASizes: TArray<Int64>): Boolean;
var
  mRest, mPart: string;
  mComma, mIndex: Integer;
begin
  ASizes := nil;
  Result := AText <> '';
  if not Result then
  begin
    Exit;
  end;
  // Länge vorab: ein Teil mehr als Kommas.
  SetLength(ASizes, Length(AText) - Length(StringReplace(AText, ',', '', [rfReplaceAll])) + 1);
  mRest := AText;
  for mIndex := 0 to High(ASizes) do
  begin
    mComma := Pos(',', mRest);
    if mComma = 0 then
    begin
      mComma := Length(mRest) + 1;
    end;
    mPart := Trim(Copy(mRest, 1, mComma - 1));
    mRest := Copy(mRest, mComma + 1, MaxInt);
    if not (IsDigits(mPart) and TryStrToInt64(mPart, ASizes[mIndex])) then
    begin
      ASizes := nil;
      Exit(False);
    end;
  end;
end;

{ Zusammenfassung }

type
  TLeakSummary = record
    Counts: TArray<TLeakCount>;
    LargeSizes: TArray<Int64>;
    procedure Add(const AName: string; ACount, AMinSize, AMaxSize: Integer);
    /// <summary>„13 - 20 bytes: TKunde x 3, UnicodeString x 5“ bzw. „20 bytes: …“.</summary>
    function ReadBucket(const ALine: string): Boolean;
    /// <summary>„… medium and large blocks are: 40100, 80000“.</summary>
    function ReadLarge(const ALine: string): Boolean;
  end;

procedure TLeakSummary.Add(const AName: string; ACount, AMinSize, AMaxSize: Integer);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Counts) do
  begin
    if SameText(Counts[mIndex].Name, AName) then
    begin
      Inc(Counts[mIndex].Count, ACount);
      if AMinSize < Counts[mIndex].MinSize then
      begin
        Counts[mIndex].MinSize := AMinSize;
      end;
      if AMaxSize > Counts[mIndex].MaxSize then
      begin
        Counts[mIndex].MaxSize := AMaxSize;
      end;
      Exit;
    end;
  end;
  SetLength(Counts, Length(Counts) + 1);
  mIndex := High(Counts);
  Counts[mIndex].Name := AName;
  Counts[mIndex].Kind := TLeakReports.KindOf(AName);
  Counts[mIndex].Count := ACount;
  Counts[mIndex].MinSize := AMinSize;
  Counts[mIndex].MaxSize := AMaxSize;
end;

/// <summary>„TKunde x 3“; False bei anderem Text.</summary>
function ReadItem(const AText: string; out AName: string; out ACount: Integer): Boolean;
var
  mText: string;
  mAt: Integer;
begin
  mText := Trim(AText);
  mAt := Length(mText);
  while (mAt > 0) and (mText[mAt] <> ' ') do
  begin
    Dec(mAt);
  end;
  AName := '';
  ACount := 0;
  // Vor der Zahl steht cCountMark; mAt zeigt auf dessen letztes Zeichen.
  mAt := mAt - Length(cCountMark) + 1;
  Result := (mAt > 1) and (Copy(mText, mAt, Length(cCountMark)) = cCountMark) and
    TryStrToInt(Copy(mText, mAt + Length(cCountMark), MaxInt), ACount);
  if Result then
  begin
    AName := Trim(Copy(mText, 1, mAt - 1));
    Result := AName <> '';
  end;
end;

/// <summary>„13 - 20“ oder „20“ vor „bytes“; False bei anderem Text.</summary>
function ReadSizeRange(const AText: string; out AMin, AMax: Integer): Boolean;
var
  mDash: Integer;
begin
  mDash := Pos('-', AText);
  if mDash = 0 then
  begin
    Result := TryStrToInt(Trim(AText), AMax);
    AMin := AMax;
  end
  else
  begin
    Result := TryStrToInt(Trim(Copy(AText, 1, mDash - 1)), AMin) and
      TryStrToInt(Trim(Copy(AText, mDash + 1, MaxInt)), AMax);
  end;
end;

function TLeakSummary.ReadBucket(const ALine: string): Boolean;
var
  mColon, mSpace, mMin, mMax, mCount, mComma: Integer;
  mHead, mItems, mItem, mName: string;
begin
  mColon := Pos(':', ALine);
  Result := mColon > 0;
  if not Result then
  begin
    Exit;
  end;
  // Kopf „13 - 20 bytes“: Zahlen, dann ein Wort für die Einheit.
  mHead := Trim(Copy(ALine, 1, mColon - 1));
  mSpace := LastDelimiter(' ', mHead);
  Result := (mSpace > 0) and ReadSizeRange(Copy(mHead, 1, mSpace - 1), mMin, mMax);
  if not Result then
  begin
    Exit;
  end;
  mItems := Copy(ALine, mColon + 1, MaxInt);
  while Trim(mItems) <> '' do
  begin
    mComma := Pos(',', mItems);
    if mComma = 0 then
    begin
      mComma := Length(mItems) + 1;
    end;
    mItem := Copy(mItems, 1, mComma - 1);
    mItems := Copy(mItems, mComma + 1, MaxInt);
    if ReadItem(mItem, mName, mCount) then
    begin
      Add(mName, mCount, mMin, mMax);
    end;
  end;
end;

function TLeakSummary.ReadLarge(const ALine: string): Boolean;
var
  mSizes: TArray<Int64>;
begin
  Result := (Pos(':', ALine) > 0) and ReadSizes(AfterLastColon(ALine), mSizes);
  if Result then
  begin
    LargeSizes := LargeSizes + mSizes;
  end;
end;

{ Einträge }

/// <summary>Größe aus der ersten nicht leeren Zeile („A memory block has been leaked. The size is: 20“);
/// AStart ist ihr Index. Fehlermeldungen von FastMM („… detected an error during a FreeMem operation …“) haben
/// dort keine Größe.</summary>
function ReadBlockSize(const ALines: TLeakLines; out AStart, ASize: Integer): Boolean;
var
  mSizes: TArray<Int64>;
begin
  AStart := 0;
  ASize := 0;
  while (AStart < Length(ALines)) and (Trim(ALines[AStart]) = '') do
  begin
    Inc(AStart);
  end;
  Result := (AStart < Length(ALines)) and ReadSizes(AfterLastColon(ALines[AStart]), mSizes) and
    (Length(mSizes) = 1);
  if Result then
  begin
    ASize := mSizes[0];
  end;
end;

function IsClassLine(const ALine: string): Boolean;
var
  mLower: string;
begin
  mLower := LowerCase(ALine);
  Result := (Pos('class', mLower) > 0) or (Pos('klasse', mLower) > 0);
end;

/// <summary>Eine Zeile nach der Größe: Stapelzeile oder Klasse. Nur der erste Stapel gehört zur Erzeugung.</summary>
procedure TakeBlockLine(const ALine: string; var ABlock: TLeakBlock; var AFramesDone: Boolean);
var
  mFrame: TLeakFrame;
begin
  if TLeakReports.ParseFrame(ALine, mFrame) then
  begin
    if not AFramesDone then
    begin
      ABlock.Frames := ABlock.Frames + [mFrame];
    end;
    Exit;
  end;
  AFramesDone := AFramesDone or (ABlock.Frames <> nil);
  if (ABlock.Name = '') and IsClassLine(ALine) then
  begin
    ABlock.Name := AfterLastColon(ALine);
  end;
end;

/// <summary>Block aus einem Eintrag der Logdatei; False, wenn der Eintrag keinen Block beschreibt.</summary>
function ReadBlock(const ALines: TLeakLines; out ABlock: TLeakBlock): Boolean;
var
  mStart, mIndex: Integer;
  mFramesDone: Boolean;
begin
  ABlock := Default(TLeakBlock);
  if not ReadBlockSize(ALines, mStart, ABlock.Size) then
  begin
    Exit(False);
  end;
  mFramesDone := False;
  for mIndex := mStart + 1 to High(ALines) do
  begin
    if Trim(ALines[mIndex]) <> '' then
    begin
      TakeBlockLine(ALines[mIndex], ABlock, mFramesDone);
    end;
  end;
  Result := (ABlock.Name <> '') or (ABlock.Frames <> nil);
  if Result then
  begin
    if ABlock.Name = '' then
    begin
      ABlock.Name := cUnknownNames[0];
    end;
    ABlock.Kind := TLeakReports.KindOf(ABlock.Name);
  end;
end;

function IsLargeLine(const ALine: string): Boolean;
var
  mLower: string;
begin
  mLower := LowerCase(ALine);
  Result := (Pos('large', mLower) > 0) or (Pos('gross', mLower) > 0);
  Result := Result or (Pos('groß', mLower) > 0); // german-ok: Wort im Bericht
end;

/// <summary>Eintrag als Zusammenfassung lesen; False ohne Zeile mit Größenklasse.</summary>
function ReadSummary(const ALines: TLeakLines; out ASummary: TLeakSummary): Boolean;
var
  mLine: string;
  mBucket: Boolean;
begin
  ASummary := Default(TLeakSummary);
  Result := False;
  for mLine in ALines do
  begin
    mBucket := ASummary.ReadBucket(mLine);
    Result := Result or mBucket;
    if not mBucket and Result then
    begin
      // Große Blöcke stehen hinter den kleinen.
      ASummary.ReadLarge(mLine);
    end;
  end;
  if not Result then
  begin
    // Nur mittlere und große Blöcke („… medium and large blocks are: 40100“).
    for mLine in ALines do
    begin
      if IsLargeLine(mLine) and ASummary.ReadLarge(mLine) then
      begin
        Result := True;
      end;
    end;
  end;
end;

{ TLeakReport }

function TLeakReport.IsEmpty: Boolean;
begin
  Result := (Counts = nil) and (LargeSizes = nil) and (Blocks = nil);
end;

function TLeakReport.HasStacks: Boolean;
var
  mBlock: TLeakBlock;
begin
  for mBlock in Blocks do
  begin
    if mBlock.Frames <> nil then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TLeakReport.CountOf(const AName: string): Integer;
var
  mCount: TLeakCount;
begin
  Result := 0;
  for mCount in Counts do
  begin
    if SameText(mCount.Name, AName) then
    begin
      Inc(Result, mCount.Count);
    end;
  end;
end;

function SameFrames(const A, B: TArray<TLeakFrame>): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(A) = Length(B);
  mIndex := 0;
  while Result and (mIndex < Length(A)) do
  begin
    Result := A[mIndex].Address = B[mIndex].Address;
    Inc(mIndex);
  end;
end;

/// <summary>Kommt AGroup vor AOther? Anzahl absteigend, dann Name, dann erste Adresse.</summary>
function GroupBefore(const AGroup, AOther: TLeakGroup): Boolean;
begin
  if AGroup.Count <> AOther.Count then
  begin
    Exit(AGroup.Count > AOther.Count);
  end;
  if not SameText(AGroup.Name, AOther.Name) then
  begin
    Exit(CompareText(AGroup.Name, AOther.Name) < 0);
  end;
  Result := (AGroup.Frames <> nil) and ((AOther.Frames = nil) or (AGroup.Frames[0].Address < AOther.Frames[0].Address));
end;

/// <summary>Index der Gruppe mit Name und Stapel von ABlock unter den ersten ACount; -1 ohne.</summary>
function IndexOfGroup(const AGroups: TArray<TLeakGroup>; ACount: Integer; const ABlock: TLeakBlock): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ACount - 1 do
  begin
    if SameText(AGroups[mIndex].Name, ABlock.Name) and SameFrames(AGroups[mIndex].Frames, ABlock.Frames) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function NewGroup(const ABlock: TLeakBlock): TLeakGroup;
begin
  Result := Default(TLeakGroup);
  Result.Name := ABlock.Name;
  Result.Kind := ABlock.Kind;
  Result.Frames := ABlock.Frames;
  Result.Site := TLeakReports.SiteOf(ABlock.Frames);
end;

/// <summary>Einfügen sortiert stabil und braucht keinen Vergleicher.</summary>
procedure SortGroups(var AGroups: TArray<TLeakGroup>);
var
  mIndex, mAt: Integer;
  mGroup: TLeakGroup;
begin
  for mIndex := 1 to High(AGroups) do
  begin
    mGroup := AGroups[mIndex];
    mAt := mIndex - 1;
    while (mAt >= 0) and GroupBefore(mGroup, AGroups[mAt]) do
    begin
      AGroups[mAt + 1] := AGroups[mAt];
      Dec(mAt);
    end;
    AGroups[mAt + 1] := mGroup;
  end;
end;

function TLeakReport.Groups: TArray<TLeakGroup>;
var
  mBlock: TLeakBlock;
  mCount, mFound: Integer;
begin
  // Höchstens eine Gruppe je Block; am Ende auf die Zahl der Gruppen kürzen.
  SetLength(Result, Length(Blocks));
  mCount := 0;
  for mBlock in Blocks do
  begin
    mFound := IndexOfGroup(Result, mCount, mBlock);
    if mFound < 0 then
    begin
      mFound := mCount;
      Result[mFound] := NewGroup(mBlock);
      Inc(mCount);
    end;
    Inc(Result[mFound].Count);
    Inc(Result[mFound].TotalSize, mBlock.Size);
  end;
  SetLength(Result, mCount);
  SortGroups(Result);
end;

{ TLeakReports }

class function TLeakReports.KindOf(const AName: string): TLeakKind;
var
  mName: string;
begin
  for mName in cTextNames do
  begin
    if SameText(mName, AName) then
    begin
      Exit(TLeakKind.Text);
    end;
  end;
  for mName in cUnknownNames do
  begin
    if SameText(mName, AName) then
    begin
      Exit(TLeakKind.Unknown);
    end;
  end;
  Result := TLeakKind.Instance;
end;

class function TLeakReports.ParseFrame(const ALine: string; out AFrame: TLeakFrame): Boolean;
var
  mText, mRest, mPart: string;
  mDigits, mClose, mField, mLine: Integer;
begin
  AFrame := Default(TLeakFrame);
  mText := Trim(ALine);
  mDigits := 0;
  while (mDigits < Length(mText)) and IsHexDigit(mText[mDigits + 1]) do
  begin
    Inc(mDigits);
  end;
  mRest := Trim(Copy(mText, mDigits + 1, MaxInt));
  // Speicherauszug („B8 4F 40 00 …“) hat kurze Hexzahlen; Stapelzeilen haben eine volle Adresse.
  Result := (mDigits >= cMinAddressDigits) and (mDigits <= cMaxAddressDigits) and
    ((mRest = '') or (mRest[1] = '['));
  if not Result then
  begin
    Exit;
  end;
  AFrame.Address := HexValue(Copy(mText, 1, mDigits));
  // „[Datei][Unit][Routine][Zeile]“
  mField := 0;
  while (mRest <> '') and (mRest[1] = '[') do
  begin
    mClose := Pos(']', mRest);
    if mClose = 0 then
    begin
      Break;
    end;
    mPart := Trim(Copy(mRest, 2, mClose - 2));
    mRest := Trim(Copy(mRest, mClose + 1, MaxInt));
    case mField of
      cFieldFile:
        AFrame.FileName := mPart;
      cFieldUnit:
        AFrame.UnitName := mPart;
      cFieldRoutine:
        AFrame.Routine := mPart;
      cFieldLine:
        if TryStrToInt(mPart, mLine) then
        begin
          AFrame.Line := mLine;
        end;
    end;
    Inc(mField);
  end;
end;

/// <summary>Unit der RTL oder von FastMM (dort entsteht jeder Block, die Stelle liegt dahinter)?</summary>
function IsMemoryUnit(const AUnitName: string): Boolean;
var
  mLower: string;
begin
  mLower := LowerCase(AUnitName);
  Result := (mLower = 'system') or (mLower = 'sysinit') or
    (Copy(mLower, 1, Length(cSystemPrefix)) = cSystemPrefix) or
    (Copy(mLower, 1, Length(cFastMMPrefix)) = cFastMMPrefix);
end;

class function TLeakReports.SiteOf(const AFrames: TArray<TLeakFrame>): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AFrames) do
  begin
    if (AFrames[mIndex].UnitName <> '') and not IsMemoryUnit(AFrames[mIndex].UnitName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Zählung aus den Blöcken, wenn die Logdatei keine Zusammenfassung hat.</summary>
procedure CountBlocks(var AReport: TLeakReport);
var
  mSummary: TLeakSummary;
  mBlock: TLeakBlock;
begin
  mSummary := Default(TLeakSummary);
  for mBlock in AReport.Blocks do
  begin
    mSummary.Add(mBlock.Name, 1, mBlock.Size, mBlock.Size);
  end;
  AReport.Counts := mSummary.Counts;
end;

procedure SortCounts(var ACounts: TArray<TLeakCount>);
var
  mIndex, mAt: Integer;
  mCount: TLeakCount;
begin
  for mIndex := 1 to High(ACounts) do
  begin
    mCount := ACounts[mIndex];
    mAt := mIndex - 1;
    while (mAt >= 0) and ((mCount.Count > ACounts[mAt].Count) or ((mCount.Count = ACounts[mAt].Count) and
      (CompareText(mCount.Name, ACounts[mAt].Name) < 0))) do
    begin
      ACounts[mAt + 1] := ACounts[mAt];
      Dec(mAt);
    end;
    ACounts[mAt + 1] := mCount;
  end;
end;

/// <summary>Einen Eintrag (Zeilen zwischen zwei Trennzeilen) in den Bericht übernehmen.</summary>
procedure TakeEntry(const ALines: TLeakLines; var AReport: TLeakReport; var AHasSummary: Boolean);
var
  mBlock: TLeakBlock;
  mSummary: TLeakSummary;
begin
  if ReadBlock(ALines, mBlock) then
  begin
    // Neuer Lauf in derselben Datei: der vorige ist mit seiner Zusammenfassung abgeschlossen.
    if AHasSummary then
    begin
      AReport := Default(TLeakReport);
      AHasSummary := False;
    end;
    AReport.Blocks := AReport.Blocks + [mBlock];
  end
  else if ReadSummary(ALines, mSummary) then
  begin
    if AHasSummary then
    begin
      AReport := Default(TLeakReport);
    end;
    AReport.Counts := mSummary.Counts;
    AReport.LargeSizes := mSummary.LargeSizes;
    AHasSummary := True;
  end;
end;

class function TLeakReports.Parse(const AText: string): TLeakReport;
var
  mLines, mEntry: TLeakLines;
  mLine: string;
  mHasSummary: Boolean;
begin
  Result := Default(TLeakReport);
  mHasSummary := False;
  mLines := TTextLines.SplitLines(AText);
  mEntry := nil;
  for mLine in mLines do
  begin
    if IsSeparator(mLine) then
    begin
      TakeEntry(mEntry, Result, mHasSummary);
      mEntry := nil;
    end
    else
    begin
      mEntry := mEntry + [mLine];
    end;
  end;
  TakeEntry(mEntry, Result, mHasSummary);
  if (Result.Counts = nil) and (Result.Blocks <> nil) then
  begin
    CountBlocks(Result);
  end;
  SortCounts(Result.Counts);
end;

end.
