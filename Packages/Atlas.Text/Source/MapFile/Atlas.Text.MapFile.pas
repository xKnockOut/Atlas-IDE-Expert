unit Atlas.Text.MapFile;

// Liest die detaillierte Map-Datei des Linkers (DCC_MapFile=3, #282) und löst
// Adressen aus Stacktraces ("AtlasServer.exe+$1A2B3C") in Unit, Routine
// und Zeile auf. Ausgewertet werden
// - der Kopf mit der Startadresse des Codesegments (z. B. 0001:00401000),
// - "Publics by Value" (Routinen nach Adresse),
// - "Line numbers for Unit(Datei.pas) segment .text".
// Adressen in der Map sind relativ zum Segmentanfang; im Stacktrace stehen
// Offsets relativ zur Modulbasis, das Codesegment beginnt dort bei $1000.
// Absolute Adressen (Absturzberichte, #74) gehen über die Basisadresse des
// Moduls; Kopf und Einsprungpunkt („Program entry point at …“) liefern
// Vorzugsbasis, Länge des Codes und Einsprungpunkt für den Vergleich mit der
// EXE (Atlas.Text.PeImage).
// In Atlas.Text, weil Server (Atlas.Windows.Diagnostics.StackTrace) und
// IDE-Plugin (Atlas.IDE.Diagnostics.StackCapture) dieselbe Auflösung nutzen.

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  /// <summary>Aufgelöste Adresse; Found = False, wenn sie in keiner Routine liegt.</summary>
  TMapLocation = record
    Found: Boolean;
    UnitName: string;
    /// <summary>Voller Name aus der Map, z. B. Shell.Composition.TComposition.Run.</summary>
    Routine: string;
    FileName: string;
    /// <summary>Zeile ab 1; 0 ohne Zeilennummer.</summary>
    Line: Integer;
    function ToString: string;
  end;

  TMapFile = class
  private type
    TSection = (Header, Segments, Publics, Lines, Other);
    TSymbol = record
      Address: UInt64;
      Name: string;
    end;
    TLineEntry = record
      Address: UInt64;
      Line: Integer;
      UnitName: string;
      FileName: string;
    end;
  private
    FCodeStart: UInt64;
    FImageBase: UInt64;
    FCodeSize: UInt64;
    FEntryPoint: UInt64;
    FSymbols: TList<TSymbol>;
    FLines: TList<TLineEntry>;
    // Zustand nur während Parse.
    FSection: TSection;
    FHeaderDone: Boolean;
    FCurrentUnit: string;
    FCurrentFile: string;
    procedure Parse(const AText: string);
    /// <summary>True, wenn ALine einen Abschnitt beginnt (und FSection umstellt).</summary>
    function StartsSection(const ALine: string): Boolean;
    procedure StartLineSection(const ALine: string);
    procedure ReadEntryPoint(const ALine: string);
    procedure ReadHeader(const AParts: TArray<string>);
    procedure ReadPublic(const AParts: TArray<string>);
    procedure ReadLineNumbers(const AParts: TArray<string>);
    procedure SortEntries;
    function GetSymbolCount: Integer;
  public
    constructor Create(const AText: string);
    destructor Destroy; override;
    /// <summary>Offset relativ zur Modulbasis wie in "Modul+$Offset"; nicht gefunden außerhalb des Codes.</summary>
    function Resolve(AModuleOffset: UInt64): TMapLocation;
    /// <summary>Absolute Adresse eines Moduls mit Basisadresse ABase; nicht gefunden unterhalb von ABase.</summary>
    function ResolveAddress(AAddress, ABase: UInt64): TMapLocation;
    /// <summary>Ersetzt in AStackTrace jede Zeile "AModule+$Offset" durch die aufgelöste Stelle dahinter.</summary>
    function Symbolize(const AStackTrace, AModule: string): string;
    /// <summary>Anzahl der Routinen; 0, wenn der Text keine Map war.</summary>
    property SymbolCount: Integer read GetSymbolCount;
    /// <summary>Vorzugsbasis des Moduls aus dem Kopf (z. B. $400000); 0, wenn der Kopf keine nennt.</summary>
    property ImageBase: UInt64 read FImageBase;
    /// <summary>Anfang des Codesegments relativ zur Modulbasis (meist $1000).</summary>
    property CodeStart: UInt64 read FCodeStart;
    /// <summary>Länge des Codesegments laut Kopf; 0 unbekannt.</summary>
    property CodeSize: UInt64 read FCodeSize;
    /// <summary>Einsprungpunkt relativ zur Modulbasis (wie AddressOfEntryPoint der EXE); 0 unbekannt.</summary>
    property EntryPoint: UInt64 read FEntryPoint;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Defaults;

const
  // Linker legt das Codesegment an die Modulbasis + $1000.
  cDefaultCodeOffset = $1000;
  // Modulbasen sind auf 64 KB ausgerichtet: die unteren 16 Bit gehören zum Abstand des Segments.
  cImageBaseAlignment = $10000;
  cLengthSuffix = 'H';
  cEntryPointText = 'Program entry point at';

function TMapLocation.ToString: string;
begin
  if not Found then
  begin
    Exit('');
  end;
  Result := Routine;
  if Line > 0 then
  begin
    Result := Result + Format(' (%s:%d)', [FileName, Line]);
  end;
end;

/// <summary>Liest "0001:00ABCDEF"; False bei anderem Segment oder Format.</summary>
function ReadAddress(const AText: string; out ASegment: Integer; out AAddress: UInt64): Boolean;
var
  mColon: Integer;
  mValue: Int64;
begin
  mColon := Pos(':', AText);
  Result := (mColon = 5) and TryStrToInt('$' + Copy(AText, 1, 4), ASegment) and
    TryStrToInt64('$' + Copy(AText, mColon + 1, MaxInt), mValue);
  if Result then
  begin
    AAddress := UInt64(mValue);
  end;
end;

/// <summary>Teile einer Zeile, durch Leerzeichen getrennt.</summary>
function Words(const ALine: string): TArray<string>;
var
  mIndex, mStart: Integer;
begin
  Result := nil;
  mIndex := 1;
  while mIndex <= Length(ALine) do
  begin
    while (mIndex <= Length(ALine)) and CharInSet(ALine[mIndex], [' ', #9]) do
    begin
      Inc(mIndex);
    end;
    mStart := mIndex;
    while (mIndex <= Length(ALine)) and not CharInSet(ALine[mIndex], [' ', #9]) do
    begin
      Inc(mIndex);
    end;
    if mIndex > mStart then
    begin
      Result := Result + [Copy(ALine, mStart, mIndex - mStart)];
    end;
  end;
end;

/// <summary>Adresse im Codesegment 0001; False bei anderem Segment oder Format.</summary>
function ReadCodeAddress(const AText: string; out AAddress: UInt64): Boolean;
var
  mSegment: Integer;
begin
  Result := ReadAddress(AText, mSegment, AAddress) and (mSegment = 1);
end;

function CompareAddress(ALeft, ARight: UInt64): Integer;
begin
  Result := 0;
  if ALeft < ARight then
  begin
    Result := -1;
  end
  else if ALeft > ARight then
  begin
    Result := 1;
  end;
end;

/// <summary>Letzter Index mit Adresse &lt;= AAddress in einer nach Adresse sortierten Folge; -1 ohne.</summary>
function LastAtOrBefore(ACount: Integer; const AAddressOf: TFunc<Integer, UInt64>; AAddress: UInt64): Integer;
var
  mLeft, mRight, mMiddle: Integer;
begin
  Result := -1;
  mLeft := 0;
  mRight := ACount - 1;
  while mLeft <= mRight do
  begin
    mMiddle := (mLeft + mRight) div 2;
    if AAddressOf(mMiddle) <= AAddress then
    begin
      Result := mMiddle;
      mLeft := mMiddle + 1;
    end
    else
    begin
      mRight := mMiddle - 1;
    end;
  end;
end;

{ TMapFile }

constructor TMapFile.Create(const AText: string);
begin
  inherited Create;
  FSymbols := TList<TSymbol>.Create;
  FLines := TList<TLineEntry>.Create;
  FCodeStart := cDefaultCodeOffset;
  Parse(AText);
end;

destructor TMapFile.Destroy;
begin
  FLines.Free;
  FSymbols.Free;
  inherited;
end;

function TMapFile.GetSymbolCount: Integer;
begin
  Result := FSymbols.Count;
end;

procedure TMapFile.StartLineSection(const ALine: string);
var
  mInside: string;
  mOpen, mClose: Integer;
begin
  // Line numbers for System(System.pas) segment .text
  mInside := Copy(ALine, Length('Line numbers for ') + 1, MaxInt);
  mOpen := Pos('(', mInside);
  mClose := Pos(')', mInside);
  FCurrentUnit := Copy(mInside, 1, mOpen - 1);
  FCurrentFile := Copy(mInside, mOpen + 1, mClose - mOpen - 1);
  // Nur Codesegment .text zählt.
  FSection := TSection.Other;
  if ContainsText(Copy(mInside, mClose + 1, MaxInt), '.text') then
  begin
    FSection := TSection.Lines;
  end;
end;

function TMapFile.StartsSection(const ALine: string): Boolean;
var
  mTrimmed: string;
begin
  Result := True;
  mTrimmed := Trim(ALine);
  if StartsText('Detailed map of segments', mTrimmed) then
  begin
    FSection := TSection.Segments;
  end
  else if ContainsText(ALine, 'Publics by Value') then
  begin
    FSection := TSection.Publics;
  end
  else if StartsText(cEntryPointText, mTrimmed) then
  begin
    ReadEntryPoint(mTrimmed);
    FSection := TSection.Other;
  end
  else if ContainsText(ALine, 'Publics by Name') or StartsText('Bound resource files', mTrimmed) then
  begin
    FSection := TSection.Other;
  end
  else if StartsText('Line numbers for ', ALine) then
  begin
    StartLineSection(ALine);
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>Länge „0000A000H“ aus dem Kopf; False bei anderem Text.</summary>
function ReadLength(const AText: string; out ALength: UInt64): Boolean;
var
  mValue: Int64;
begin
  Result := EndsText(cLengthSuffix, AText) and
    TryStrToInt64('$' + Copy(AText, 1, Length(AText) - Length(cLengthSuffix)), mValue) and (mValue >= 0);
  ALength := 0;
  if Result then
  begin
    ALength := UInt64(mValue);
  end;
end;

procedure TMapFile.ReadHeader(const AParts: TArray<string>);
var
  mAddress: UInt64;
begin
  // 0001:00401000 0012345H .text CODE
  if FHeaderDone or (Length(AParts) < 3) or not ReadCodeAddress(AParts[0], mAddress) then
  begin
    Exit;
  end;
  // Die Vorzugsbasis ist auf 64 KB ausgerichtet, der Rest ist der Abstand des Codesegments ($401000 → $400000
  // und $1000, bei Packages z. B. $50001000 → $50000000).
  FImageBase := mAddress - mAddress mod cImageBaseAlignment;
  if mAddress mod cImageBaseAlignment > 0 then
  begin
    FCodeStart := mAddress mod cImageBaseAlignment;
  end;
  ReadLength(AParts[1], FCodeSize);
  FHeaderDone := True;
end;

procedure TMapFile.ReadEntryPoint(const ALine: string);
var
  mParts: TArray<string>;
  mAddress: UInt64;
begin
  // Program entry point at 0001:00000180 (relativ zum Codesegment); erst nach dem Kopf bekannt.
  mParts := Words(ALine);
  if (Length(mParts) > 0) and ReadCodeAddress(mParts[High(mParts)], mAddress) then
  begin
    FEntryPoint := mAddress;
  end;
end;

procedure TMapFile.ReadPublic(const AParts: TArray<string>);
var
  mSymbol: TSymbol;
begin
  if (Length(AParts) >= 2) and ReadCodeAddress(AParts[0], mSymbol.Address) then
  begin
    mSymbol.Name := AParts[High(AParts)];
    FSymbols.Add(mSymbol);
  end;
end;

procedure TMapFile.ReadLineNumbers(const AParts: TArray<string>);
var
  mIndex: Integer;
  mEntry: TLineEntry;
begin
  // Paare "Zeile Adresse".
  mIndex := 0;
  while mIndex + 1 <= High(AParts) do
  begin
    if TryStrToInt(AParts[mIndex], mEntry.Line) and ReadCodeAddress(AParts[mIndex + 1], mEntry.Address) then
    begin
      mEntry.UnitName := FCurrentUnit;
      mEntry.FileName := FCurrentFile;
      FLines.Add(mEntry);
    end;
    Inc(mIndex, 2);
  end;
end;

procedure TMapFile.SortEntries;
begin
  FSymbols.Sort(TComparer<TSymbol>.Construct(
    function(const ALeft, ARight: TSymbol): Integer
    begin
      Result := CompareAddress(ALeft.Address, ARight.Address);
    end));
  FLines.Sort(TComparer<TLineEntry>.Construct(
    function(const ALeft, ARight: TLineEntry): Integer
    begin
      Result := CompareAddress(ALeft.Address, ARight.Address);
    end));
end;

procedure TMapFile.Parse(const AText: string);
var
  mLine: string;
  mParts: TArray<string>;
begin
  FSection := TSection.Header;
  FHeaderDone := False;
  for mLine in StringReplace(AText, #13, '', [rfReplaceAll]).Split([#10]) do
  begin
    if (Trim(mLine) = '') or StartsSection(mLine) then
    begin
      Continue;
    end;
    mParts := Words(mLine);
    case FSection of
      TSection.Header:
        ReadHeader(mParts);
      TSection.Publics:
        ReadPublic(mParts);
      TSection.Lines:
        ReadLineNumbers(mParts);
    end;
  end;
  FCurrentUnit := '';
  FCurrentFile := '';
  if FEntryPoint > 0 then
  begin
    FEntryPoint := FEntryPoint + FCodeStart;
  end;
  SortEntries;
end;

function TMapFile.Resolve(AModuleOffset: UInt64): TMapLocation;
var
  mAddress: UInt64;
  mFound, mDot: Integer;
begin
  Result := Default(TMapLocation);
  if (AModuleOffset < FCodeStart) or (FSymbols.Count = 0) then
  begin
    Exit;
  end;
  mAddress := AModuleOffset - FCodeStart;
  // Hinter dem Code liegt nichts aus dieser Map (Adressen anderer Module, Daten).
  if (FCodeSize > 0) and (mAddress >= FCodeSize) then
  begin
    Exit;
  end;
  mFound := LastAtOrBefore(FSymbols.Count,
    function(AIndex: Integer): UInt64
    begin
      Result := FSymbols[AIndex].Address;
    end, mAddress);
  if mFound < 0 then
  begin
    Exit;
  end;
  Result.Found := True;
  Result.Routine := FSymbols[mFound].Name;
  mDot := Pos('.', Result.Routine);
  if mDot > 0 then
  begin
    Result.UnitName := Copy(Result.Routine, 1, mDot - 1);
  end;
  // Zeile: letzte Zeilenangabe <= Address, nicht vor dem Anfang der Routine.
  mFound := LastAtOrBefore(FLines.Count,
    function(AIndex: Integer): UInt64
    begin
      Result := FLines[AIndex].Address;
    end, mAddress);
  if (mFound >= 0) and (FLines[mFound].Address >= FSymbols[0].Address) then
  begin
    Result.Line := FLines[mFound].Line;
    Result.FileName := FLines[mFound].FileName;
    Result.UnitName := FLines[mFound].UnitName;
  end;
end;

function TMapFile.ResolveAddress(AAddress, ABase: UInt64): TMapLocation;
begin
  Result := Default(TMapLocation);
  if AAddress >= ABase then
  begin
    Result := Resolve(AAddress - ABase);
  end;
end;

function TMapFile.Symbolize(const AStackTrace, AModule: string): string;
var
  mLine, mPrefix: string;
  mOffset: Int64;
  mLocation: TMapLocation;
  mBuilder: TStringBuilder;
begin
  mPrefix := AModule + '+$';
  mBuilder := TStringBuilder.Create;
  try
    for mLine in StringReplace(AStackTrace, #13, '', [rfReplaceAll]).Split([#10]) do
    begin
      if mLine = '' then
      begin
        Continue;
      end;
      mBuilder.Append(mLine);
      if StartsText(mPrefix, Trim(mLine)) and
        TryStrToInt64('$' + Copy(Trim(mLine), Length(mPrefix) + 1, MaxInt), mOffset) then
      begin
        mLocation := Resolve(UInt64(mOffset));
        if mLocation.Found then
        begin
          mBuilder.Append(' ').Append(mLocation.ToString);
        end;
      end;
      mBuilder.Append(sLineBreak);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

end.
