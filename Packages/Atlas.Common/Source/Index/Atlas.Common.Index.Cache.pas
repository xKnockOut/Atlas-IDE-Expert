unit Atlas.Common.Index.Cache;

// Festplatten-Cache des Symbolindex. Je Unit stehen Zeitstempel und Hash
// darin; beim Start werden nur geänderte Dateien neu eingelesen. Ein Cache
// mit anderer Formatversion (auch die früheren Text- und JSON-Formate) wird
// verworfen.
//
// Format 11 (#617, Schritt 4): binär mit String-Tabelle.
// Format 12: gleiches Layout; nur neu einlesen, weil Vorwärtsdeklarationen
// vollständig deklarierter Typen nicht mehr im Index stehen.
// - Jeder Text steht genau einmal in der Tabelle; Units und Symbole
//   verweisen per Nummer darauf. Nach dem Laden teilen sich gleiche Texte
//   (Container, Typnamen, Dateinamen) eine Instanz, das spart Speicher.
// - Die Symbole jeder Unit stehen in einem eigenen Block mit Länge. ReadEntries
//   liest nur die Köpfe und überspringt die Blöcke; Expand dekodiert die
//   Symbole einer Unit erst, wenn der Builder sie wirklich übernimmt. Units
//   des gemeinsamen Bibliotheks-Caches, die das Projekt nicht braucht, kosten
//   so beim Start fast nichts.
//
// Aufbau (alle Zahlen als Varint, vorzeichenbehaftete per ZigZag):
//   Kopf:    'ATLASIDX' Version
//   Texte:   Anzahl, je Text Bytelänge und UTF-8-Bytes (Nummer 0 = '')
//   Units:   Anzahl, je Unit:
//            Name Datei Zeitstempel Hash Merker uses(interface) uses(implementation)
//            Include-Dateien Include-Zeitstempel Symbolzahl Zahl-nicht-verfügbar Blocklänge Block
//            Merker: 1 = Bibliothek, 2 = kompakt, 4 = initialization/finalization
//   Symbol:  Name Container Art L1 C1 L2 C2 SL1 SC1 SL2 SC2 Merker Vorfahren Typ
//            Typargumente Vorfahr-Typargumente Typparameter Sichtbarkeit MinArgs MaxArgs
//            Parametertypen Include-Datei Bedingung
//            Merker: 1 = InInterface, 2 = Default, 4 = Virtuell, 8 = NichtVerfügbar
// Listen: Anzahl, dann die Einträge. Der Dateiname der Cache-Datei bleibt index-*.json.

interface

uses
  System.SysUtils,
  Atlas.Common.Index.Contract;

type
  /// <summary>Unit aus einem geladenen Cache. Header enthält alles außer den Symbolen;
  /// TIndexCache.Expand dekodiert sie bei Bedarf.</summary>
  TIndexCacheEntry = record
    Header: TUnitIndex;
    /// <summary>Header ist schon vollständig (aus einem TUnitIndex übernommen).</summary>
    Expanded: Boolean;
    Data: TBytes;
    Strings: TArray<string>;
    SymbolOffset: Integer;
    SymbolEnd: Integer;
    SymbolCount: Integer;
    UnavailableCount: Integer;
    class function FromUnit(const AUnit: TUnitIndex): TIndexCacheEntry; static;
  end;

  TIndexCache = class
  public
    // 13: Mitglieder aus nicht geltenden Zweigen in Unavailable (#476).
    // 14: dazu Routinen aus nicht geltenden Zweigen im implementation-Teil.
    const FormatVersion = 14;
    class function Serialize(const AUnits: TArray<TUnitIndex>): TBytes; static;
    /// <summary>Liest nur die Köpfe; bei falscher Version oder fremdem Inhalt leer.</summary>
    class function ReadEntries(const AData: TBytes): TArray<TIndexCacheEntry>; static;
    /// <summary>Unit mit Symbolen; False, wenn der Block beschädigt ist.</summary>
    class function Expand(const AEntry: TIndexCacheEntry; out AUnit: TUnitIndex): Boolean; static;
    /// <summary>Liest den ganzen Cache; bei falscher Version oder fremdem Inhalt leer.</summary>
    class function Deserialize(const AData: TBytes): TArray<TUnitIndex>; static;
    /// <summary>Hash eines Dateiinhalts.</summary>
    class function HashOf(const AText: string): string; static;
  end;

implementation

uses
  System.Hash,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract;

const
  Magic: array[0..7] of Byte = (Ord('A'), Ord('T'), Ord('L'), Ord('A'), Ord('S'), Ord('I'), Ord('D'), Ord('X'));
  FlagLibrary = 1;
  FlagCompact = 2;
  FlagInitialization = 4;
  SymbolInInterface = 1;
  SymbolDefault = 2;
  SymbolVirtual = 4;
  SymbolUnavailable = 8;

type
  ECacheFormat = class(Exception);

  /// <summary>Wachsender Bytepuffer.</summary>
  TCacheWriter = class
  private
    FData: TBytes;
    FLength: Integer;
    procedure Grow(ACount: Integer);
  public
    constructor Create(ACapacity: Integer);
    procedure WriteByte(AValue: Byte);
    procedure WriteBytes(const AValue: TBytes; AIndex, ACount: Integer);
    procedure WriteVar(AValue: UInt64);
    procedure WriteInt(AValue: Int64);
    function ToBytes: TBytes;
    property Length_: Integer read FLength;
  end;

  /// <summary>Liest Werte aus einem Bytepuffer; jede Überschreitung löst ECacheFormat aus.</summary>
  TCacheReader = record
    Data: TBytes;
    Position: Integer;
    Limit: Integer;
    function ReadByte: Byte;
    function ReadVar: UInt64;
    function ReadCount: Integer;
    function ReadInt: Int64;
    function ReadInt32: Integer;
    function ReadString(const AStrings: TArray<string>): string;
    function ReadList(const AStrings: TArray<string>): TArray<string>;
  end;

  /// <summary>Sammelt beim Schreiben die String-Tabelle.</summary>
  TStringTable = class
  private
    FIndex: TDictionary<string, Integer>;
    FItems: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    function IndexOf(const AValue: string): Integer;
    property Items: TList<string> read FItems;
  end;

procedure Fail;
begin
  raise ECacheFormat.Create('Index-Cache beschädigt');
end;

{ TCacheWriter }

constructor TCacheWriter.Create(ACapacity: Integer);
begin
  inherited Create;
  SetLength(FData, ACapacity);
end;

procedure TCacheWriter.Grow(ACount: Integer);
var
  Needed, Capacity: Integer;
begin
  Needed := FLength + ACount;
  Capacity := Length(FData);
  if Needed <= Capacity then
    Exit;
  if Capacity < 1024 then
    Capacity := 1024;
  while Capacity < Needed do
    Capacity := Capacity * 2;
  SetLength(FData, Capacity);
end;

procedure TCacheWriter.WriteByte(AValue: Byte);
begin
  Grow(1);
  FData[FLength] := AValue;
  Inc(FLength);
end;

procedure TCacheWriter.WriteBytes(const AValue: TBytes; AIndex, ACount: Integer);
begin
  if ACount <= 0 then
    Exit;
  Grow(ACount);
  Move(AValue[AIndex], FData[FLength], ACount);
  Inc(FLength, ACount);
end;

procedure TCacheWriter.WriteVar(AValue: UInt64);
begin
  while AValue >= $80 do
  begin
    WriteByte(Byte(AValue and $7F) or $80);
    AValue := AValue shr 7;
  end;
  WriteByte(Byte(AValue));
end;

procedure TCacheWriter.WriteInt(AValue: Int64);
var
  Encoded: UInt64;
begin
  // ZigZag: kleine negative Zahlen (-1) bleiben kurz.
  if AValue < 0 then
    Encoded := (UInt64(not AValue) shl 1) or 1
  else
    Encoded := UInt64(AValue) shl 1;
  WriteVar(Encoded);
end;

function TCacheWriter.ToBytes: TBytes;
begin
  Result := Copy(FData, 0, FLength);
end;

{ TCacheReader }

function TCacheReader.ReadByte: Byte;
begin
  if Position >= Limit then
    Fail;
  Result := Data[Position];
  Inc(Position);
end;

function TCacheReader.ReadVar: UInt64;
var
  Shift: Integer;
  Value: Byte;
begin
  Result := 0;
  Shift := 0;
  repeat
    if Shift > 63 then
      Fail;
    Value := ReadByte;
    Result := Result or (UInt64(Value and $7F) shl Shift);
    Inc(Shift, 7);
  until Value < $80;
end;

function TCacheReader.ReadCount: Integer;
var
  Value: UInt64;
begin
  Value := ReadVar;
  // Mehr Einträge als Bytes kann es nicht geben.
  if Value > UInt64(Limit) then
    Fail;
  Result := Integer(Value);
end;

function TCacheReader.ReadInt: Int64;
var
  Value: UInt64;
begin
  Value := ReadVar;
  if (Value and 1) <> 0 then
    Result := not Int64(Value shr 1)
  else
    Result := Int64(Value shr 1);
end;

function TCacheReader.ReadInt32: Integer;
var
  Value: Int64;
begin
  Value := ReadInt;
  if (Value < Low(Integer)) or (Value > High(Integer)) then
    Fail;
  Result := Integer(Value);
end;

function TCacheReader.ReadString(const AStrings: TArray<string>): string;
var
  Index: UInt64;
begin
  Index := ReadVar;
  if Index >= UInt64(Length(AStrings)) then
    Fail;
  Result := AStrings[Integer(Index)];
end;

function TCacheReader.ReadList(const AStrings: TArray<string>): TArray<string>;
var
  Index, Count: Integer;
begin
  Count := ReadCount;
  SetLength(Result, Count);
  for Index := 0 to Count - 1 do
    Result[Index] := ReadString(AStrings);
end;

{ TStringTable }

constructor TStringTable.Create;
begin
  inherited Create;
  FIndex := TDictionary<string, Integer>.Create;
  FItems := TList<string>.Create;
  IndexOf('');
end;

destructor TStringTable.Destroy;
begin
  FItems.Free;
  FIndex.Free;
  inherited;
end;

function TStringTable.IndexOf(const AValue: string): Integer;
begin
  if FIndex.TryGetValue(AValue, Result) then
    Exit;
  Result := FItems.Add(AValue);
  FIndex.Add(AValue, Result);
end;

{ TIndexCacheEntry }

class function TIndexCacheEntry.FromUnit(const AUnit: TUnitIndex): TIndexCacheEntry;
begin
  Result := Default(TIndexCacheEntry);
  Result.Header := AUnit;
  Result.Expanded := True;
end;

{ Schreiben }

procedure WriteList(AWriter: TCacheWriter; ATable: TStringTable; const AValues: TArray<string>);
var
  Value: string;
begin
  AWriter.WriteVar(Length(AValues));
  for Value in AValues do
    AWriter.WriteVar(ATable.IndexOf(Value));
end;

procedure WriteSymbol(AWriter: TCacheWriter; ATable: TStringTable; const ASymbol: TIndexSymbol);
var
  Flags: Integer;
begin
  AWriter.WriteVar(ATable.IndexOf(ASymbol.Name));
  AWriter.WriteVar(ATable.IndexOf(ASymbol.Container));
  AWriter.WriteVar(Ord(ASymbol.Kind));
  AWriter.WriteInt(ASymbol.Range.StartPos.Line);
  AWriter.WriteInt(ASymbol.Range.StartPos.Character);
  AWriter.WriteInt(ASymbol.Range.EndPos.Line);
  AWriter.WriteInt(ASymbol.Range.EndPos.Character);
  AWriter.WriteInt(ASymbol.SelectionRange.StartPos.Line);
  AWriter.WriteInt(ASymbol.SelectionRange.StartPos.Character);
  AWriter.WriteInt(ASymbol.SelectionRange.EndPos.Line);
  AWriter.WriteInt(ASymbol.SelectionRange.EndPos.Character);
  Flags := 0;
  if ASymbol.InInterface then
    Flags := Flags or SymbolInInterface;
  if ASymbol.IsDefault then
    Flags := Flags or SymbolDefault;
  if ASymbol.IsVirtual then
    Flags := Flags or SymbolVirtual;
  if ASymbol.Unavailable then
    Flags := Flags or SymbolUnavailable;
  AWriter.WriteVar(Flags);
  WriteList(AWriter, ATable, ASymbol.Ancestors);
  AWriter.WriteVar(ATable.IndexOf(ASymbol.TypeName));
  AWriter.WriteVar(ATable.IndexOf(ASymbol.TypeArgs));
  AWriter.WriteVar(ATable.IndexOf(ASymbol.AncestorArgs));
  AWriter.WriteVar(ATable.IndexOf(ASymbol.TypeParams));
  AWriter.WriteVar(Ord(ASymbol.Visibility));
  AWriter.WriteInt(ASymbol.MinArgs);
  AWriter.WriteInt(ASymbol.MaxArgs);
  WriteList(AWriter, ATable, ASymbol.ParamTypes);
  AWriter.WriteVar(ATable.IndexOf(ASymbol.FileName));
  AWriter.WriteVar(ATable.IndexOf(ASymbol.Condition));
end;

class function TIndexCache.Serialize(const AUnits: TArray<TUnitIndex>): TBytes;
var
  Table: TStringTable;
  Body, Block, Output: TCacheWriter;
  UnitIndex: TUnitIndex;
  Symbol: TIndexSymbol;
  Flags, MagicIndex: Integer;
  Stamp: Int64;
  Value: string;
  Bytes: TBytes;
begin
  Table := TStringTable.Create;
  Body := TCacheWriter.Create(1024 * 1024);
  Block := TCacheWriter.Create(64 * 1024);
  Output := nil;
  try
    Body.WriteVar(Length(AUnits));
    for UnitIndex in AUnits do
    begin
      Flags := 0;
      if UnitIndex.Library_ then
        Flags := Flags or FlagLibrary;
      if UnitIndex.Compact then
        Flags := Flags or FlagCompact;
      if UnitIndex.HasInitialization then
        Flags := Flags or FlagInitialization;
      Body.WriteVar(Table.IndexOf(UnitIndex.UnitName));
      Body.WriteVar(Table.IndexOf(UnitIndex.FileName));
      Body.WriteInt(UnitIndex.Stamp);
      Body.WriteVar(Table.IndexOf(UnitIndex.Hash));
      Body.WriteVar(Flags);
      WriteList(Body, Table, UnitIndex.InterfaceUses);
      WriteList(Body, Table, UnitIndex.ImplementationUses);
      WriteList(Body, Table, UnitIndex.Includes);
      Body.WriteVar(Length(UnitIndex.IncludeStamps));
      for Stamp in UnitIndex.IncludeStamps do
        Body.WriteInt(Stamp);
      Body.WriteVar(Length(UnitIndex.Symbols));
      Body.WriteVar(Length(UnitIndex.Unavailable));
      // Block erst sammeln, damit seine Länge davor stehen kann.
      Block.FLength := 0;
      for Symbol in UnitIndex.Symbols do
        WriteSymbol(Block, Table, Symbol);
      for Symbol in UnitIndex.Unavailable do
        WriteSymbol(Block, Table, Symbol);
      Body.WriteVar(Block.Length_);
      Body.WriteBytes(Block.FData, 0, Block.Length_);
    end;
    Output := TCacheWriter.Create(Body.Length_ + 64 * 1024);
    for MagicIndex := Low(Magic) to High(Magic) do
      Output.WriteByte(Magic[MagicIndex]);
    Output.WriteVar(FormatVersion);
    Output.WriteVar(Table.Items.Count);
    for Value in Table.Items do
    begin
      Bytes := TEncoding.UTF8.GetBytes(Value);
      Output.WriteVar(Length(Bytes));
      Output.WriteBytes(Bytes, 0, Length(Bytes));
    end;
    Output.WriteBytes(Body.FData, 0, Body.Length_);
    Result := Output.ToBytes;
  finally
    Output.Free;
    Block.Free;
    Body.Free;
    Table.Free;
  end;
end;

{ Lesen }

function ReadSymbol(var AReader: TCacheReader; const AStrings: TArray<string>): TIndexSymbol;
var
  Kind: UInt64;
  Flags: Integer;
  L1, C1, L2, C2: Integer;
begin
  Result := Default(TIndexSymbol);
  Result.Name := AReader.ReadString(AStrings);
  Result.Container := AReader.ReadString(AStrings);
  Kind := AReader.ReadVar;
  if Kind > UInt64(Ord(High(TIndexSymbolKind))) then
    Fail;
  Result.Kind := TIndexSymbolKind(Integer(Kind));
  L1 := AReader.ReadInt32;
  C1 := AReader.ReadInt32;
  L2 := AReader.ReadInt32;
  C2 := AReader.ReadInt32;
  Result.Range := TTextRange.Create(TTextPosition.Create(L1, C1), TTextPosition.Create(L2, C2));
  L1 := AReader.ReadInt32;
  C1 := AReader.ReadInt32;
  L2 := AReader.ReadInt32;
  C2 := AReader.ReadInt32;
  Result.SelectionRange := TTextRange.Create(TTextPosition.Create(L1, C1), TTextPosition.Create(L2, C2));
  Flags := AReader.ReadCount;
  Result.InInterface := (Flags and SymbolInInterface) <> 0;
  Result.IsDefault := (Flags and SymbolDefault) <> 0;
  Result.IsVirtual := (Flags and SymbolVirtual) <> 0;
  Result.Unavailable := (Flags and SymbolUnavailable) <> 0;
  Result.Ancestors := AReader.ReadList(AStrings);
  Result.TypeName := AReader.ReadString(AStrings);
  Result.TypeArgs := AReader.ReadString(AStrings);
  Result.AncestorArgs := AReader.ReadString(AStrings);
  Result.TypeParams := AReader.ReadString(AStrings);
  Kind := AReader.ReadVar;
  if Kind > UInt64(Ord(High(TIndexVisibility))) then
    Fail;
  Result.Visibility := TIndexVisibility(Integer(Kind));
  Result.MinArgs := AReader.ReadInt32;
  Result.MaxArgs := AReader.ReadInt32;
  Result.ParamTypes := AReader.ReadList(AStrings);
  Result.FileName := AReader.ReadString(AStrings);
  Result.Condition := AReader.ReadString(AStrings);
end;

class function TIndexCache.ReadEntries(const AData: TBytes): TArray<TIndexCacheEntry>;
var
  Reader: TCacheReader;
  Strings: TArray<string>;
  Index, Count, StampIndex, Flags, Size: Integer;
  Entry: TIndexCacheEntry;
begin
  Result := nil;
  if Length(AData) < Length(Magic) then
    Exit;
  for Index := Low(Magic) to High(Magic) do
    if AData[Index] <> Magic[Index] then
      Exit;
  Reader.Data := AData;
  Reader.Position := Length(Magic);
  Reader.Limit := Length(AData);
  try
    if Reader.ReadVar <> FormatVersion then
      Exit;
    Count := Reader.ReadCount;
    SetLength(Strings, Count);
    for Index := 0 to Count - 1 do
    begin
      Size := Reader.ReadCount;
      if Reader.Position + Size > Reader.Limit then
        Fail;
      Strings[Index] := TEncoding.UTF8.GetString(AData, Reader.Position, Size);
      Inc(Reader.Position, Size);
    end;
    Count := Reader.ReadCount;
    SetLength(Result, Count);
    for Index := 0 to Count - 1 do
    begin
      Entry := Default(TIndexCacheEntry);
      Entry.Header.UnitName := Reader.ReadString(Strings);
      Entry.Header.FileName := Reader.ReadString(Strings);
      Entry.Header.Stamp := Reader.ReadInt;
      Entry.Header.Hash := Reader.ReadString(Strings);
      Flags := Reader.ReadCount;
      Entry.Header.Library_ := (Flags and FlagLibrary) <> 0;
      Entry.Header.Compact := (Flags and FlagCompact) <> 0;
      Entry.Header.HasInitialization := (Flags and FlagInitialization) <> 0;
      Entry.Header.InterfaceUses := Reader.ReadList(Strings);
      Entry.Header.ImplementationUses := Reader.ReadList(Strings);
      Entry.Header.Includes := Reader.ReadList(Strings);
      SetLength(Entry.Header.IncludeStamps, Reader.ReadCount);
      for StampIndex := 0 to High(Entry.Header.IncludeStamps) do
        Entry.Header.IncludeStamps[StampIndex] := Reader.ReadInt;
      Entry.SymbolCount := Reader.ReadCount;
      Entry.UnavailableCount := Reader.ReadCount;
      Size := Reader.ReadCount;
      if Reader.Position + Size > Reader.Limit then
        Fail;
      Entry.Data := AData;
      Entry.Strings := Strings;
      Entry.SymbolOffset := Reader.Position;
      Entry.SymbolEnd := Reader.Position + Size;
      Inc(Reader.Position, Size);
      if Entry.Header.FileName = '' then
        Fail;
      Result[Index] := Entry;
    end;
  except
    on ECacheFormat do
      Result := nil;
  end;
end;

class function TIndexCache.Expand(const AEntry: TIndexCacheEntry; out AUnit: TUnitIndex): Boolean;
var
  Reader: TCacheReader;
  Index: Integer;
begin
  AUnit := AEntry.Header;
  if AEntry.Expanded then
    Exit(True);
  Reader.Data := AEntry.Data;
  Reader.Position := AEntry.SymbolOffset;
  Reader.Limit := AEntry.SymbolEnd;
  try
    SetLength(AUnit.Symbols, AEntry.SymbolCount);
    for Index := 0 to AEntry.SymbolCount - 1 do
      AUnit.Symbols[Index] := ReadSymbol(Reader, AEntry.Strings);
    SetLength(AUnit.Unavailable, AEntry.UnavailableCount);
    for Index := 0 to AEntry.UnavailableCount - 1 do
      AUnit.Unavailable[Index] := ReadSymbol(Reader, AEntry.Strings);
    Result := Reader.Position = Reader.Limit;
  except
    on ECacheFormat do
      Result := False;
  end;
  if not Result then
    AUnit := AEntry.Header;
end;

class function TIndexCache.Deserialize(const AData: TBytes): TArray<TUnitIndex>;
var
  Entries: TArray<TIndexCacheEntry>;
  Index: Integer;
begin
  Entries := ReadEntries(AData);
  SetLength(Result, Length(Entries));
  for Index := 0 to High(Entries) do
    if not Expand(Entries[Index], Result[Index]) then
      Exit(nil);
end;

class function TIndexCache.HashOf(const AText: string): string;
begin
  Result := THashFNV1a32.GetHashString(AText) + IntToHex(Length(AText), 1);
end;

end.
