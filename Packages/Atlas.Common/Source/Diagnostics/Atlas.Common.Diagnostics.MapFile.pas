unit Atlas.Common.Diagnostics.MapFile;

// Liest die detaillierte Map-Datei des Linkers (DCC_MapFile=3, #282) und löst
// Adressen aus Stacktraces ("AtlasServer.exe+$1A2B3C") in Unit, Routine
// und Zeile auf. Ausgewertet werden
// - der Kopf mit der Startadresse des Codesegments (z. B. 0001:00401000),
// - "Publics by Value" (Routinen nach Adresse),
// - "Line numbers for Unit(Datei.pas) segment .text".
// Adressen in der Map sind relativ zum Segmentanfang; im Stacktrace stehen
// Offsets relativ zur Modulbasis, das Codesegment beginnt dort bei $1000.

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
    FSymbols: TList<TSymbol>;
    FLines: TList<TLineEntry>;
    procedure Parse(const AText: string);
    function GetSymbolCount: Integer;
  public
    constructor Create(const AText: string);
    destructor Destroy; override;
    /// <summary>Offset relativ zur Modulbasis wie in "Modul+$Offset".</summary>
    function Resolve(AModuleOffset: UInt64): TMapLocation;
    /// <summary>Ersetzt in AStackTrace jede Zeile "AModule+$Offset" durch die aufgelöste Stelle dahinter.</summary>
    function Symbolize(const AStackTrace, AModule: string): string;
    /// <summary>Anzahl der Routinen; 0, wenn der Text keine Map war.</summary>
    property SymbolCount: Integer read GetSymbolCount;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Defaults;

const
  // Linker legt das Codesegment an die Modulbasis + $1000.
  DefaultCodeOffset = $1000;
  DefaultImageBase = $400000;

function TMapLocation.ToString: string;
begin
  if not Found then
    Exit('');
  Result := Routine;
  if Line > 0 then
    Result := Result + Format(' (%s:%d)', [FileName, Line]);
end;

/// <summary>Liest "0001:00ABCDEF"; False bei anderem Segment oder Format.</summary>
function ReadAddress(const AText: string; out ASegment: Integer; out AAddress: UInt64): Boolean;
var
  Colon: Integer;
  Value: Int64;
begin
  Colon := Pos(':', AText);
  Result := (Colon = 5) and TryStrToInt('$' + Copy(AText, 1, 4), ASegment) and
    TryStrToInt64('$' + Copy(AText, Colon + 1, MaxInt), Value);
  if Result then
    AAddress := UInt64(Value);
end;

/// <summary>Teile einer Zeile, durch Leerzeichen getrennt.</summary>
function Words(const ALine: string): TArray<string>;
var
  Index, Start: Integer;
begin
  Result := nil;
  Index := 1;
  while Index <= Length(ALine) do
  begin
    while (Index <= Length(ALine)) and CharInSet(ALine[Index], [' ', #9]) do
      Inc(Index);
    Start := Index;
    while (Index <= Length(ALine)) and not CharInSet(ALine[Index], [' ', #9]) do
      Inc(Index);
    if Index > Start then
      Result := Result + [Copy(ALine, Start, Index - Start)];
  end;
end;

{ TMapFile }

constructor TMapFile.Create(const AText: string);
begin
  inherited Create;
  FSymbols := TList<TSymbol>.Create;
  FLines := TList<TLineEntry>.Create;
  FCodeStart := DefaultCodeOffset;
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

procedure TMapFile.Parse(const AText: string);
type
  TSection = (Header, Segments, Publics, Lines, Other);
var
  Section: TSection;
  Line, CurrentUnit, CurrentFile, Inside: string;
  Parts: TArray<string>;
  Segment, Index, Open, Close, Number: Integer;
  Address: UInt64;
  HeaderDone: Boolean;
  Symbol: TSymbol;
  Entry: TLineEntry;
begin
  Section := TSection.Header;
  HeaderDone := False;
  for Line in StringReplace(AText, #13, '', [rfReplaceAll]).Split([#10]) do
  begin
    if Trim(Line) = '' then
      Continue;
    if StartsText('Detailed map of segments', Trim(Line)) then
      Section := TSection.Segments
    else if ContainsText(Line, 'Publics by Value') then
      Section := TSection.Publics
    else if ContainsText(Line, 'Publics by Name') or StartsText('Bound resource files', Trim(Line)) or
      StartsText('Program entry point', Trim(Line)) then
      Section := TSection.Other
    else if StartsText('Line numbers for ', Line) then
    begin
      // Line numbers for System(System.pas) segment .text
      Section := TSection.Lines;
      Inside := Copy(Line, Length('Line numbers for ') + 1, MaxInt);
      Open := Pos('(', Inside);
      Close := Pos(')', Inside);
      CurrentUnit := Copy(Inside, 1, Open - 1);
      CurrentFile := Copy(Inside, Open + 1, Close - Open - 1);
      // Nur Codesegment .text zählt.
      if not ContainsText(Copy(Inside, Close + 1, MaxInt), '.text') then
        Section := TSection.Other;
    end
    else
    begin
      Parts := Words(Line);
      case Section of
        TSection.Header:
          // 0001:00401000 0012345H .text CODE
          if not HeaderDone and (Length(Parts) >= 3) and ReadAddress(Parts[0], Segment, Address) and
            (Segment = 1) then
          begin
            if Address >= DefaultImageBase then
              FCodeStart := Address - DefaultImageBase
            else if Address > 0 then
              FCodeStart := Address;
            HeaderDone := True;
          end;
        TSection.Publics:
          if (Length(Parts) >= 2) and ReadAddress(Parts[0], Segment, Address) and (Segment = 1) then
          begin
            Symbol.Address := Address;
            Symbol.Name := Parts[High(Parts)];
            FSymbols.Add(Symbol);
          end;
        TSection.Lines:
          begin
            // Paare "Zeile Adresse".
            Index := 0;
            while Index + 1 <= High(Parts) do
            begin
              if TryStrToInt(Parts[Index], Number) and ReadAddress(Parts[Index + 1], Segment, Address) and
                (Segment = 1) then
              begin
                Entry.Address := Address;
                Entry.Line := Number;
                Entry.UnitName := CurrentUnit;
                Entry.FileName := CurrentFile;
                FLines.Add(Entry);
              end;
              Inc(Index, 2);
            end;
          end;
      end;
    end;
  end;
  FSymbols.Sort(TComparer<TSymbol>.Construct(
    function(const ALeft, ARight: TSymbol): Integer
    begin
      if ALeft.Address < ARight.Address then
        Result := -1
      else if ALeft.Address > ARight.Address then
        Result := 1
      else
        Result := 0;
    end));
  FLines.Sort(TComparer<TLineEntry>.Construct(
    function(const ALeft, ARight: TLineEntry): Integer
    begin
      if ALeft.Address < ARight.Address then
        Result := -1
      else if ALeft.Address > ARight.Address then
        Result := 1
      else
        Result := 0;
    end));
end;

function TMapFile.Resolve(AModuleOffset: UInt64): TMapLocation;
var
  Address: UInt64;
  Left, Right, Middle, Found: Integer;
  Dot: Integer;
begin
  Result := Default(TMapLocation);
  if (AModuleOffset < FCodeStart) or (FSymbols.Count = 0) then
    Exit;
  Address := AModuleOffset - FCodeStart;
  // Letztes Symbol mit Adresse <= Address.
  Left := 0;
  Right := FSymbols.Count - 1;
  Found := -1;
  while Left <= Right do
  begin
    Middle := (Left + Right) div 2;
    if FSymbols[Middle].Address <= Address then
    begin
      Found := Middle;
      Left := Middle + 1;
    end
    else
      Right := Middle - 1;
  end;
  if Found < 0 then
    Exit;
  Result.Found := True;
  Result.Routine := FSymbols[Found].Name;
  Dot := Pos('.', Result.Routine);
  if Dot > 0 then
    Result.UnitName := Copy(Result.Routine, 1, Dot - 1);
  // Zeile: letzte Zeilenangabe <= Address, nicht vor dem Anfang der Routine.
  Left := 0;
  Right := FLines.Count - 1;
  Found := -1;
  while Left <= Right do
  begin
    Middle := (Left + Right) div 2;
    if FLines[Middle].Address <= Address then
    begin
      Found := Middle;
      Left := Middle + 1;
    end
    else
      Right := Middle - 1;
  end;
  if (Found >= 0) and (FLines[Found].Address >= FSymbols[0].Address) then
  begin
    Result.Line := FLines[Found].Line;
    Result.FileName := FLines[Found].FileName;
    Result.UnitName := FLines[Found].UnitName;
  end;
end;

function TMapFile.Symbolize(const AStackTrace, AModule: string): string;
var
  Line, Prefix: string;
  Offset: Int64;
  Location: TMapLocation;
  Builder: TStringBuilder;
begin
  Prefix := AModule + '+$';
  Builder := TStringBuilder.Create;
  try
    for Line in StringReplace(AStackTrace, #13, '', [rfReplaceAll]).Split([#10]) do
    begin
      if Line = '' then
        Continue;
      Builder.Append(Line);
      if StartsText(Prefix, Trim(Line)) and
        TryStrToInt64('$' + Copy(Trim(Line), Length(Prefix) + 1, MaxInt), Offset) then
      begin
        Location := Resolve(UInt64(Offset));
        if Location.Found then
          Builder.Append(' ').Append(Location.ToString);
      end;
      Builder.Append(sLineBreak);
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

end.
