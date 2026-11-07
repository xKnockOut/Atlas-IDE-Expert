unit Atlas.Common.Index.Cache;

// Festplatten-Cache des Symbolindex. Je Unit stehen Zeitstempel und Hash
// darin; beim Start werden nur geänderte Dateien neu eingelesen. Ein Cache
// mit anderer Formatversion (auch die früheren Text- und JSON-Formate) wird
// verworfen.
//
// Format 12 (#492): Prüfsumme über die ganze Datei; je Symbol Signatur,
// Direktiven und XMLDoc-Kurztext; je Unit die Verwendungen der Bezeichner in
// einem eigenen Block, damit sie ausgelagert bleiben können. Eine Datei mit
// falscher Prüfsumme gilt als beschädigt: ReadEntries liefert dann leer und
// nennt den Grund, der Aufbau liest alles neu, ohne Meldung an den Benutzer.
//
// Format 11 (#617, Schritt 4): binär mit String-Tabelle.
// Format 12: gleiches Layout; nur neu einlesen, weil Vorwärtsdeklarationen
// vollständig deklarierter Typen nicht mehr im Index stehen.
// Format 19 (#1001): gleiches Layout; neu einlesen, weil Klassenmitglieder
// (class var, class property, class function) die Direktive "class" tragen.
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
//   Kopf:    'ATLASIDX' Version Prüfsumme (4 Byte, FNV-1a über alles dahinter)
//   Texte:   Anzahl, je Text Bytelänge und UTF-8-Bytes (Nummer 0 = '')
//   Units:   Anzahl, je Unit:
//            Name Datei Zeitstempel Hash Merker uses(interface) uses(implementation)
//            Include-Dateien Include-Zeitstempel Symbolzahl Zahl-nicht-verfügbar Blocklänge Block
//            Verwendungszahl Verwendungsblocklänge Verwendungsblock
//            Merker: 1 = Bibliothek, 2 = kompakt, 4 = initialization/finalization,
//                    8 = Verwendungen erfasst
//   Symbol:  Name Container Art L1 C1 L2 C2 SL1 SC1 SL2 SC2 Merker Vorfahren Typ
//            Typargumente Vorfahr-Typargumente Typparameter Sichtbarkeit MinArgs MaxArgs
//            Parametertypen Include-Datei Bedingung Signatur Direktiven Kurztext
//   Verwendung: Name Anzahl, je Stelle Zeilenabstand zur vorigen und Spalte
//            Merker: 1 = InInterface, 2 = Default, 4 = Virtuell, 8 = NichtVerfügbar
// Listen: Anzahl, dann die Einträge. Die Datei heißt index.atlasidx (Ablage in
// Index.Adapters.CacheDirectory).

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
    UsageOffset: Integer;
    UsageEnd: Integer;
    UsageCount: Integer;
    class function FromUnit(const AUnit: TUnitIndex): TIndexCacheEntry; static;
  end;

  TIndexCache = class
  public
    // 13: Mitglieder aus nicht geltenden Zweigen in Unavailable (#476).
    // 14: dazu Routinen aus nicht geltenden Zweigen im implementation-Teil.
    // 15: Zusammenführung mit der Kette (Signatur, Direktiven, Kurztext je Symbol, #492).
    // 16: Zählung der Präfixe je Unit (#452).
    // 17: Grund hinter deprecated je Symbol (#38).
    // 18: Zweig varianter Record-Felder je Symbol (#846).
    // 19: Direktive class an Klassenmitgliedern (#1001).
    // 20: Verweise der Rümpfe von inline-Routinen (#1017).
    // 21: Hinweise im Unit-Kopf samt Grund hinter deprecated (#1018).
    // 22: Typparameter ohne die Typen aus Einschränkungen (<T: class, TBasis>, #1029).
    // 23: Unit-Name zählt nicht mehr als Hinweis im Unit-Kopf (Atlas.Settings.Experimental, #1018);
    // Feld Operator: string ist keine Routine mehr.
    // 24: Helfer mit Vorfahr (class helper (TBase) for T, #848), {$SCOPEDENUMS ON} je Aufzählung und Wert und
    // Mitglieder aus {$I} im Klassenrumpf (#849), Routinen hinter asm-Blöcken mit @@End (#861), Konstanten
    // hinter Steuerzeichen wie ^C (#862). Die Kette #847–#862 zählte getrennt 19–22.
    // 25: Methodenzuordnungen IFoo.Bar=Baz je Klasse statt als Mitglied (#849 mit #1000 und #1040).
    // 26: Namen ohne Escape-& (&begin → begin, &&op_Equality → &op_Equality, #1137).
    // 27: type AnsiString(Codepage) ohne Zieltyp, RawByteString/UTF8String bleiben eigene Typen (#1140).
    // 28: Begründungen (// WHY: …) je Symbol und Unit (#1123).
    // 29: Prozedurtypen über mehrere Zeilen vollständig, Merkmal "of object"/"reference to" in Directives (#1326).
    // 30: inline-Routinen ohne Verweise tragen InlineWithoutRefs statt nil (#1381).
    // 31: Typargumente je Vorfahr statt nur des ersten (class(TInterfacedObject, IComparer<TKunde>)).
    // 32: Hinweiswort vor dem Startwert (NoErrMsg: Boolean platform = False); ohne neue Version blieb System.pas
    // aus dem alten Index ohne NoErrMsg (unresolved-identifier).
    const cFormatVersion = 32;
    class function Serialize(const AUnits: TArray<TUnitIndex>): TBytes; static;
    /// <summary>Liest nur die Köpfe; bei falscher Version, falscher Prüfsumme oder fremdem Inhalt leer.</summary>
    class function ReadEntries(const AData: TBytes): TArray<TIndexCacheEntry>; overload; static;
    /// <summary>Wie oben; AReason nennt bei leerem Ergebnis den Grund ('' = gültig oder leer).</summary>
    class function ReadEntries(const AData: TBytes; out AReason: string): TArray<TIndexCacheEntry>; overload;
      static;
    /// <summary>Unit mit Symbolen und (AUsages) Verwendungen; False, wenn ein Block beschädigt ist.
    /// Ohne AUsages bleiben die Verwendungen auf der Platte: UsagesOffloaded ist dann gesetzt.</summary>
    class function Expand(const AEntry: TIndexCacheEntry; out AUnit: TUnitIndex;
      AUsages: Boolean): Boolean; overload; static;
    /// <summary>Wie oben mit AUsages = True.</summary>
    class function Expand(const AEntry: TIndexCacheEntry; out AUnit: TUnitIndex): Boolean; overload; static;
    /// <summary>Nur die Verwendungen einer Unit (Nachladen ausgelagerter Verwendungen).</summary>
    class function ExpandUsages(const AEntry: TIndexCacheEntry; out AUsages: TArray<TIndexUsage>): Boolean;
      static;
    /// <summary>Liest den ganzen Cache; bei falscher Version oder fremdem Inhalt leer.</summary>
    class function Deserialize(const AData: TBytes): TArray<TUnitIndex>; static;
    /// <summary>Hash eines Dateiinhalts.</summary>
    class function HashOf(const AText: string): string; static;
  end;

implementation

uses
  System.Hash,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Localization.Texts;

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TCacheText = (IndexCacheDamaged, IndexCacheTooLarge, IndexCacheSizeDiffersFrom, ChecksumDoesNotMatch,
    NoAtlasIndexHeaderMissing, ContentDamaged, FormatVersionInsteadOf);

const
  cTexts: array[TCacheText] of TAtlasText = (
    (De: 'Index-Cache beschädigt'; En: 'Index cache damaged'),
    (De: 'Index-Cache zu groß'; En: 'Index cache too large'),
    (De: 'Index-Cache: Größe weicht von der Vorabzählung ab'; En: 'Index cache: size differs from the pre-count'),
    (De: 'Prüfsumme stimmt nicht'; En: 'Checksum does not match'),
    (De: 'kein Atlas-Index (Kopf fehlt)'; En: 'no Atlas index (header missing)'),
    (De: 'Inhalt beschädigt'; En: 'content damaged'),
    (De: 'Formatversion %d statt %d'; En: 'Format version %d instead of %d'));

const
  cMagic: array[0..7] of Byte = (Ord('A'), Ord('T'), Ord('L'), Ord('A'), Ord('S'), Ord('I'), Ord('D'), Ord('X'));
  cFlagLibrary = 1;
  cFlagCompact = 2;
  cFlagInitialization = 4;
  cFlagUsages = 8;
  // Magic, Version (1 Byte bis 127) und 4 Byte Prüfsumme.
  cChecksumSize = 4;
  cSymbolInInterface = 1;
  cSymbolDefault = 2;
  cSymbolVirtual = 4;
  cSymbolUnavailable = 8;
  cSymbolScopedEnum = 16;

type
  ECacheFormat = class(Exception);

  /// <summary>Wachsender Bytepuffer. Ein zählender Puffer (Counter) legt nichts ab, sondern zählt nur die
  /// Bytes; Serialize misst damit vorab die genaue Größe.</summary>
  TCacheWriter = class
  private
    FData: TBytes;
    FLength: Integer;
    FCounting: Boolean;
    procedure Grow(ACount: Integer);
  public
    constructor Create(ACapacity: Integer);
    class function Counter: TCacheWriter; static;
    procedure WriteByte(AValue: Byte);
    procedure WriteBytes(const AValue: TBytes; AIndex, ACount: Integer);
    procedure WriteVar(AValue: UInt64);
    procedure WriteInt(AValue: Int64);
    /// <summary>Übergibt den Puffer ohne Kopie, wenn er genau gefüllt ist; danach ist der Schreiber leer.</summary>
    function TakeBytes: TBytes;
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
    /// <summary>Nicht negative Zahl bis High(Integer), unabhängig von der Dateigröße.</summary>
    function ReadNumber: Integer;
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
  raise ECacheFormat.Create(cTexts[TCacheText.IndexCacheDamaged].Text);
end;

/// <summary>FNV-1a (32 Bit) über AData ab AFrom.</summary>
function ChecksumOf(const AData: TBytes; AFrom, ATo: Integer): Cardinal;
var
  mIndex: Integer;
begin
  Result := 2166136261;
  for mIndex := AFrom to ATo - 1 do
  begin
    Result := Cardinal(UInt64(Result xor AData[mIndex]) * 16777619);
  end;
end;

{ TCacheWriter }

constructor TCacheWriter.Create(ACapacity: Integer);
begin
  inherited Create;
  SetLength(FData, ACapacity);
end;

class function TCacheWriter.Counter: TCacheWriter;
begin
  Result := TCacheWriter.Create(0);
  Result.FCounting := True;
end;

procedure TCacheWriter.Grow(ACount: Integer);
var
  mNeeded, mCapacity: Integer;
begin
  mNeeded := FLength + ACount;
  mCapacity := Length(FData);
  if mNeeded <= mCapacity then
  begin
    Exit;
  end;
  if mCapacity < 1024 then
  begin
    mCapacity := 1024;
  end;
  while mCapacity < mNeeded do
  begin
    mCapacity := mCapacity * 2;
  end;
  SetLength(FData, mCapacity);
end;

procedure TCacheWriter.WriteByte(AValue: Byte);
begin
  if FCounting then
  begin
    Inc(FLength);
    Exit;
  end;
  Grow(1);
  FData[FLength] := AValue;
  Inc(FLength);
end;

procedure TCacheWriter.WriteBytes(const AValue: TBytes; AIndex, ACount: Integer);
begin
  if ACount <= 0 then
  begin
    Exit;
  end;
  if FCounting then
  begin
    Inc(FLength, ACount);
    Exit;
  end;
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
  mEncoded: UInt64;
begin
  // ZigZag: kleine negative Zahlen (-1) bleiben kurz.
  if AValue < 0 then
  begin
    mEncoded := (UInt64(not AValue) shl 1) or 1;
  end
  else
  begin
    mEncoded := UInt64(AValue) shl 1;
  end;
  WriteVar(mEncoded);
end;

function TCacheWriter.TakeBytes: TBytes;
begin
  Result := FData;
  FData := nil;
  if Length(Result) <> FLength then
  begin
    SetLength(Result, FLength);
  end;
  FLength := 0;
end;

{ TCacheReader }

function TCacheReader.ReadByte: Byte;
begin
  if Position >= Limit then
  begin
    Fail;
  end;
  Result := Data[Position];
  Inc(Position);
end;

function TCacheReader.ReadVar: UInt64;
var
  mShift: Integer;
  mValue: Byte;
begin
  Result := 0;
  mShift := 0;
  repeat
    if mShift > 63 then
    begin
      Fail;
    end;
    mValue := ReadByte;
    Result := Result or (UInt64(mValue and $7F) shl mShift);
    Inc(mShift, 7);
  until mValue < $80;
end;

function TCacheReader.ReadNumber: Integer;
var
  mValue: UInt64;
begin
  mValue := ReadVar;
  if mValue > UInt64(High(Integer)) then
  begin
    Fail;
  end;
  Result := Integer(mValue);
end;

function TCacheReader.ReadCount: Integer;
var
  mValue: UInt64;
begin
  mValue := ReadVar;
  // Mehr Einträge als Bytes kann es nicht geben.
  if mValue > UInt64(Limit) then
  begin
    Fail;
  end;
  Result := Integer(mValue);
end;

function TCacheReader.ReadInt: Int64;
var
  mValue: UInt64;
begin
  mValue := ReadVar;
  if (mValue and 1) <> 0 then
  begin
    Result := not Int64(mValue shr 1);
  end
  else
  begin
    Result := Int64(mValue shr 1);
  end;
end;

function TCacheReader.ReadInt32: Integer;
var
  mValue: Int64;
begin
  mValue := ReadInt;
  if (mValue < Low(Integer)) or (mValue > High(Integer)) then
  begin
    Fail;
  end;
  Result := Integer(mValue);
end;

function TCacheReader.ReadString(const AStrings: TArray<string>): string;
var
  mIndex: UInt64;
begin
  mIndex := ReadVar;
  if mIndex >= UInt64(Length(AStrings)) then
  begin
    Fail;
  end;
  Result := AStrings[Integer(mIndex)];
end;

function TCacheReader.ReadList(const AStrings: TArray<string>): TArray<string>;
var
  mIndex, mCount: Integer;
begin
  mCount := ReadCount;
  SetLength(Result, mCount);
  for mIndex := 0 to mCount - 1 do
  begin
    Result[mIndex] := ReadString(AStrings);
  end;
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
  begin
    Exit;
  end;
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
  mValue: string;
begin
  AWriter.WriteVar(Length(AValues));
  for mValue in AValues do
  begin
    AWriter.WriteVar(ATable.IndexOf(mValue));
  end;
end;

procedure WriteSymbol(AWriter: TCacheWriter; ATable: TStringTable; const ASymbol: TIndexSymbol);
var
  mFlags: Integer;
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
  mFlags := 0;
  if ASymbol.InInterface then
  begin
    mFlags := mFlags or cSymbolInInterface;
  end;
  if ASymbol.IsDefault then
  begin
    mFlags := mFlags or cSymbolDefault;
  end;
  if ASymbol.IsVirtual then
  begin
    mFlags := mFlags or cSymbolVirtual;
  end;
  if ASymbol.Unavailable then
  begin
    mFlags := mFlags or cSymbolUnavailable;
  end;
  if ASymbol.ScopedEnum then
  begin
    mFlags := mFlags or cSymbolScopedEnum;
  end;
  AWriter.WriteVar(mFlags);
  WriteList(AWriter, ATable, ASymbol.Ancestors);
  AWriter.WriteVar(ATable.IndexOf(ASymbol.TypeName));
  AWriter.WriteVar(ATable.IndexOf(ASymbol.TypeArgs));
  WriteList(AWriter, ATable, ASymbol.AncestorArgs);
  AWriter.WriteVar(ATable.IndexOf(ASymbol.TypeParams));
  AWriter.WriteVar(Ord(ASymbol.Visibility));
  AWriter.WriteInt(ASymbol.MinArgs);
  AWriter.WriteInt(ASymbol.MaxArgs);
  WriteList(AWriter, ATable, ASymbol.ParamTypes);
  AWriter.WriteVar(ATable.IndexOf(ASymbol.FileName));
  AWriter.WriteVar(ATable.IndexOf(ASymbol.Condition));
  AWriter.WriteVar(ATable.IndexOf(ASymbol.Signature));
  WriteList(AWriter, ATable, ASymbol.Directives);
  AWriter.WriteVar(ATable.IndexOf(ASymbol.Summary));
  AWriter.WriteVar(ATable.IndexOf(ASymbol.DeprecatedText));
  AWriter.WriteVar(ATable.IndexOf(ASymbol.VariantBranch));
  WriteList(AWriter, ATable, ASymbol.InlineRefs);
  WriteList(AWriter, ATable, ASymbol.Resolutions);
  WriteList(AWriter, ATable, ASymbol.Rationale);
end;

procedure WriteUsage(AWriter: TCacheWriter; ATable: TStringTable; const AUsage: TIndexUsage);
var
  mPosition: TTextPosition;
  mLine: Integer;
begin
  AWriter.WriteVar(ATable.IndexOf(AUsage.Name));
  AWriter.WriteVar(Length(AUsage.Positions));
  // Zeilen als Abstand zur vorigen Stelle: meist 0 oder klein.
  mLine := 0;
  for mPosition in AUsage.Positions do
  begin
    AWriter.WriteInt(mPosition.Line - mLine);
    AWriter.WriteVar(Cardinal(mPosition.Character));
    mLine := mPosition.Line;
  end;
end;

/// <summary>Bytes, die WriteVar für AValue schreibt.</summary>
function VarSize(AValue: UInt64): Integer;
begin
  Result := 1;
  while AValue >= $80 do
  begin
    Inc(Result);
    AValue := AValue shr 7;
  end;
end;

function UnitFlags(const AUnit: TUnitIndex): Integer;
begin
  Result := 0;
  if AUnit.Library_ then
  begin
    Result := Result or cFlagLibrary;
  end;
  if AUnit.Compact then
  begin
    Result := Result or cFlagCompact;
  end;
  if AUnit.HasInitialization then
  begin
    Result := Result or cFlagInitialization;
  end;
  if AUnit.UsagesIndexed then
  begin
    Result := Result or cFlagUsages;
  end;
end;

/// <summary>Kopf einer Unit: Namen, Stempel, Flags, uses, Includes, Namenszählung und Hinweise.</summary>
procedure WriteUnitHeader(AWriter: TCacheWriter; ATable: TStringTable; const AUnit: TUnitIndex);
var
  mKind: TNamingKind;
  mStamp: Int64;
begin
  AWriter.WriteVar(ATable.IndexOf(AUnit.UnitName));
  AWriter.WriteVar(ATable.IndexOf(AUnit.FileName));
  AWriter.WriteInt(AUnit.Stamp);
  AWriter.WriteVar(ATable.IndexOf(AUnit.Hash));
  AWriter.WriteVar(UnitFlags(AUnit));
  WriteList(AWriter, ATable, AUnit.InterfaceUses);
  WriteList(AWriter, ATable, AUnit.ImplementationUses);
  WriteList(AWriter, ATable, AUnit.Includes);
  AWriter.WriteVar(Length(AUnit.IncludeStamps));
  for mStamp in AUnit.IncludeStamps do
  begin
    AWriter.WriteInt(mStamp);
  end;
  for mKind := Low(TNamingKind) to High(TNamingKind) do
  begin
    AWriter.WriteVar(AUnit.Naming[mKind].Total);
    AWriter.WriteVar(AUnit.Naming[mKind].Prefixed);
  end;
  WriteList(AWriter, ATable, AUnit.Directives);
  AWriter.WriteVar(ATable.IndexOf(AUnit.DeprecatedText));
  WriteList(AWriter, ATable, AUnit.Rationale);
end;

/// <summary>Symbole und Verwendungen einer Unit, jeweils als Block mit seiner Länge davor (über ABlock gesammelt).
/// </summary>
procedure WriteUnitBody(AWriter, ABlock: TCacheWriter; ATable: TStringTable; const AUnit: TUnitIndex);
var
  mSymbol: TIndexSymbol;
  mUsage: TIndexUsage;
begin
  AWriter.WriteVar(Length(AUnit.Symbols));
  AWriter.WriteVar(Length(AUnit.Unavailable));
  ABlock.FLength := 0;
  for mSymbol in AUnit.Symbols do
  begin
    WriteSymbol(ABlock, ATable, mSymbol);
  end;
  for mSymbol in AUnit.Unavailable do
  begin
    WriteSymbol(ABlock, ATable, mSymbol);
  end;
  AWriter.WriteVar(ABlock.Length_);
  AWriter.WriteBytes(ABlock.FData, 0, ABlock.Length_);
  ABlock.FLength := 0;
  for mUsage in AUnit.Usages do
  begin
    WriteUsage(ABlock, ATable, mUsage);
  end;
  AWriter.WriteVar(Length(AUnit.Usages));
  AWriter.WriteVar(ABlock.Length_);
  AWriter.WriteBytes(ABlock.FData, 0, ABlock.Length_);
end;

/// <summary>Alle Units hinter der String-Tabelle. ATable vergibt die Nummern; ein zweiter Lauf über dieselben
/// Units findet alle Texte schon vor und schreibt dieselben Nummern.</summary>
procedure WriteUnits(AWriter: TCacheWriter; ATable: TStringTable; const AUnits: TArray<TUnitIndex>);
var
  mBlock: TCacheWriter;
  mUnit: TUnitIndex;
begin
  if AWriter.FCounting then
  begin
    mBlock := TCacheWriter.Counter;
  end
  else
  begin
    mBlock := TCacheWriter.Create(64 * 1024);
  end;
  try
    AWriter.WriteVar(Length(AUnits));
    for mUnit in AUnits do
    begin
      WriteUnitHeader(AWriter, ATable, mUnit);
      // Block erst sammeln, damit seine Länge davor stehen kann.
      WriteUnitBody(AWriter, mBlock, ATable, mUnit);
    end;
  finally
    mBlock.Free;
  end;
end;

/// <summary>Größe der Datei: Kopf, String-Tabelle und die gezählten Units.</summary>
function SerializedSize(ATable: TStringTable; ACounter: TCacheWriter): Int64;
var
  mValue: string;
  mSize: Integer;
begin
  Result := Int64(Length(cMagic)) + VarSize(TIndexCache.cFormatVersion) + cChecksumSize +
    VarSize(ATable.Items.Count) + ACounter.Length_;
  for mValue in ATable.Items do
  begin
    mSize := TEncoding.UTF8.GetByteCount(mValue);
    Inc(Result, VarSize(mSize) + mSize);
  end;
end;

/// <summary>Kopf mit Platz für die Prüfsumme und die String-Tabelle; liefert die Stelle der Prüfsumme.</summary>
function WriteHead(AOutput: TCacheWriter; ATable: TStringTable): Integer;
var
  mIndex: Integer;
  mValue: string;
  mBytes: TBytes;
begin
  for mIndex := Low(cMagic) to High(cMagic) do
  begin
    AOutput.WriteByte(cMagic[mIndex]);
  end;
  AOutput.WriteVar(TIndexCache.cFormatVersion);
  // Platz für die Prüfsumme; sie wird zuletzt über alles dahinter berechnet.
  Result := AOutput.Length_;
  for mIndex := 1 to cChecksumSize do
  begin
    AOutput.WriteByte(0);
  end;
  AOutput.WriteVar(ATable.Items.Count);
  for mValue in ATable.Items do
  begin
    mBytes := TEncoding.UTF8.GetBytes(mValue);
    AOutput.WriteVar(Length(mBytes));
    AOutput.WriteBytes(mBytes, 0, Length(mBytes));
  end;
end;

procedure StoreChecksum(var AData: TBytes; AChecksumAt: Integer);
var
  mChecksum: Cardinal;
  mIndex: Integer;
begin
  mChecksum := ChecksumOf(AData, AChecksumAt + cChecksumSize, Length(AData));
  for mIndex := 0 to cChecksumSize - 1 do
  begin
    AData[AChecksumAt + mIndex] := Byte(mChecksum shr (8 * mIndex));
  end;
end;

class function TIndexCache.Serialize(const AUnits: TArray<TUnitIndex>): TBytes;
var
  mTable: TStringTable;
  mCounter, mOutput: TCacheWriter;
  mChecksumAt, mTextCount: Integer;
  mCapacity: Int64;
begin
  // Speicher (Rückmeldung 22.10.2026, 3 GB bei acht Projekten): Früher wuchs der Rumpf in einem eigenen
  // Puffer bis auf das Doppelte, wurde hinter die Tabelle kopiert und am Ende noch einmal kopiert; das
  // kostete kurzzeitig das Vier- bis Fünffache der Datei. Jetzt zählt ein erster Lauf nur die Bytes und
  // füllt die Tabelle, der zweite schreibt in einen Puffer genau passender Größe, der ohne Kopie das
  // Ergebnis wird.
  mTable := TStringTable.Create;
  mCounter := TCacheWriter.Counter;
  mOutput := nil;
  try
    WriteUnits(mCounter, mTable, AUnits);
    mTextCount := mTable.Items.Count;
    mCapacity := SerializedSize(mTable, mCounter);
    if mCapacity > MaxInt then
    begin
      raise ECacheFormat.Create(cTexts[TCacheText.IndexCacheTooLarge].Text);
    end;
    mOutput := TCacheWriter.Create(Integer(mCapacity));
    mChecksumAt := WriteHead(mOutput, mTable);
    WriteUnits(mOutput, mTable, AUnits);
    // Beide Läufe müssen dieselben Texte in derselben Reihenfolge sehen.
    if (mTable.Items.Count <> mTextCount) or (mOutput.Length_ <> mCapacity) then
    begin
      raise EInvalidOpException.Create(cTexts[TCacheText.IndexCacheSizeDiffersFrom].Text);
    end;
    Result := mOutput.TakeBytes;
    StoreChecksum(Result, mChecksumAt);
  finally
    mOutput.Free;
    mCounter.Free;
    mTable.Free;
  end;
end;

{ Lesen }

function ReadSymbol(var AReader: TCacheReader; const AStrings: TArray<string>): TIndexSymbol;
var
  mKind: UInt64;
  mFlags: Integer;
  mL1, mC1, mL2, mC2: Integer;
begin
  Result := Default(TIndexSymbol);
  Result.Name := AReader.ReadString(AStrings);
  Result.Container := AReader.ReadString(AStrings);
  mKind := AReader.ReadVar;
  if mKind > UInt64(Ord(High(TIndexSymbolKind))) then
  begin
    Fail;
  end;
  Result.Kind := TIndexSymbolKind(Integer(mKind));
  mL1 := AReader.ReadInt32;
  mC1 := AReader.ReadInt32;
  mL2 := AReader.ReadInt32;
  mC2 := AReader.ReadInt32;
  Result.Range := TTextRange.Create(TTextPosition.Create(mL1, mC1), TTextPosition.Create(mL2, mC2));
  mL1 := AReader.ReadInt32;
  mC1 := AReader.ReadInt32;
  mL2 := AReader.ReadInt32;
  mC2 := AReader.ReadInt32;
  Result.SelectionRange := TTextRange.Create(TTextPosition.Create(mL1, mC1), TTextPosition.Create(mL2, mC2));
  mFlags := AReader.ReadCount;
  Result.InInterface := (mFlags and cSymbolInInterface) <> 0;
  Result.IsDefault := (mFlags and cSymbolDefault) <> 0;
  Result.IsVirtual := (mFlags and cSymbolVirtual) <> 0;
  Result.Unavailable := (mFlags and cSymbolUnavailable) <> 0;
  Result.ScopedEnum := (mFlags and cSymbolScopedEnum) <> 0;
  Result.Ancestors := AReader.ReadList(AStrings);
  Result.TypeName := AReader.ReadString(AStrings);
  Result.TypeArgs := AReader.ReadString(AStrings);
  Result.AncestorArgs := AReader.ReadList(AStrings);
  Result.TypeParams := AReader.ReadString(AStrings);
  mKind := AReader.ReadVar;
  if mKind > UInt64(Ord(High(TIndexVisibility))) then
  begin
    Fail;
  end;
  Result.Visibility := TIndexVisibility(Integer(mKind));
  Result.MinArgs := AReader.ReadInt32;
  Result.MaxArgs := AReader.ReadInt32;
  Result.ParamTypes := AReader.ReadList(AStrings);
  Result.FileName := AReader.ReadString(AStrings);
  Result.Condition := AReader.ReadString(AStrings);
  Result.Signature := AReader.ReadString(AStrings);
  Result.Directives := AReader.ReadList(AStrings);
  Result.Summary := AReader.ReadString(AStrings);
  Result.DeprecatedText := AReader.ReadString(AStrings);
  Result.VariantBranch := AReader.ReadString(AStrings);
  Result.InlineRefs := AReader.ReadList(AStrings);
  Result.Resolutions := AReader.ReadList(AStrings);
  Result.Rationale := AReader.ReadList(AStrings);
end;

function ReadUsage(var AReader: TCacheReader; const AStrings: TArray<string>): TIndexUsage;
var
  mIndex, mLine: Integer;
begin
  Result.Name := AReader.ReadString(AStrings);
  SetLength(Result.Positions, AReader.ReadCount);
  mLine := 0;
  for mIndex := 0 to High(Result.Positions) do
  begin
    mLine := mLine + AReader.ReadInt32;
    Result.Positions[mIndex] := TTextPosition.Create(mLine, AReader.ReadInt32);
  end;
end;

class function TIndexCache.ReadEntries(const AData: TBytes): TArray<TIndexCacheEntry>;
var
  mReason: string;
begin
  Result := ReadEntries(AData, mReason);
end;

function HasMagic(const AData: TBytes): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(AData) >= Length(cMagic);
  for mIndex := Low(cMagic) to High(cMagic) do
  begin
    if not Result then
    begin
      Break;
    end;
    Result := AData[mIndex] = cMagic[mIndex];
  end;
end;

/// <summary>Liest die gespeicherte Prüfsumme und vergleicht sie mit dem Rest der Datei.</summary>
function ChecksumMatches(var AReader: TCacheReader; const AData: TBytes): Boolean;
var
  mStored: Cardinal;
  mIndex: Integer;
begin
  if AReader.Position + cChecksumSize > AReader.Limit then
  begin
    Fail;
  end;
  mStored := 0;
  for mIndex := cChecksumSize - 1 downto 0 do
  begin
    mStored := (mStored shl 8) or AData[AReader.Position + mIndex];
  end;
  Inc(AReader.Position, cChecksumSize);
  Result := mStored = ChecksumOf(AData, AReader.Position, Length(AData));
end;

/// <summary>Die Länge davor und Platz dahinter prüfen; liefert die Länge.</summary>
function ReadBlockSize(var AReader: TCacheReader): Integer;
begin
  Result := AReader.ReadCount;
  if AReader.Position + Result > AReader.Limit then
  begin
    Fail;
  end;
end;

function ReadStringTable(var AReader: TCacheReader; const AData: TBytes): TArray<string>;
var
  mIndex, mSize: Integer;
begin
  SetLength(Result, AReader.ReadCount);
  for mIndex := 0 to High(Result) do
  begin
    mSize := ReadBlockSize(AReader);
    Result[mIndex] := TEncoding.UTF8.GetString(AData, AReader.Position, mSize);
    Inc(AReader.Position, mSize);
  end;
end;

function ReadUnitHeader(var AReader: TCacheReader; const AStrings: TArray<string>): TUnitIndex;
var
  mFlags, mIndex: Integer;
  mKind: TNamingKind;
begin
  Result := Default(TUnitIndex);
  Result.UnitName := AReader.ReadString(AStrings);
  Result.FileName := AReader.ReadString(AStrings);
  Result.Stamp := AReader.ReadInt;
  Result.Hash := AReader.ReadString(AStrings);
  mFlags := AReader.ReadCount;
  Result.Library_ := (mFlags and cFlagLibrary) <> 0;
  Result.Compact := (mFlags and cFlagCompact) <> 0;
  Result.HasInitialization := (mFlags and cFlagInitialization) <> 0;
  Result.UsagesIndexed := (mFlags and cFlagUsages) <> 0;
  Result.InterfaceUses := AReader.ReadList(AStrings);
  Result.ImplementationUses := AReader.ReadList(AStrings);
  Result.Includes := AReader.ReadList(AStrings);
  SetLength(Result.IncludeStamps, AReader.ReadCount);
  for mIndex := 0 to High(Result.IncludeStamps) do
  begin
    Result.IncludeStamps[mIndex] := AReader.ReadInt;
  end;
  // Zahlen, keine Längen: ReadCount begrenzte sie auf die Dateigröße.
  for mKind := Low(TNamingKind) to High(TNamingKind) do
  begin
    Result.Naming[mKind].Total := AReader.ReadNumber;
    Result.Naming[mKind].Prefixed := AReader.ReadNumber;
  end;
  Result.Directives := AReader.ReadList(AStrings);
  Result.DeprecatedText := AReader.ReadString(AStrings);
  Result.Rationale := AReader.ReadList(AStrings);
end;

function ReadEntry(var AReader: TCacheReader; const AData: TBytes; const AStrings: TArray<string>): TIndexCacheEntry;
var
  mSize: Integer;
begin
  Result := Default(TIndexCacheEntry);
  Result.Header := ReadUnitHeader(AReader, AStrings);
  Result.SymbolCount := AReader.ReadCount;
  Result.UnavailableCount := AReader.ReadCount;
  mSize := ReadBlockSize(AReader);
  Result.Data := AData;
  Result.Strings := AStrings;
  Result.SymbolOffset := AReader.Position;
  Result.SymbolEnd := AReader.Position + mSize;
  Inc(AReader.Position, mSize);
  Result.UsageCount := AReader.ReadCount;
  mSize := ReadBlockSize(AReader);
  Result.UsageOffset := AReader.Position;
  Result.UsageEnd := AReader.Position + mSize;
  Inc(AReader.Position, mSize);
  if Result.Header.FileName = '' then
  begin
    Fail;
  end;
end;

/// <summary>Liest den Inhalt hinter Kopf und Version; '' in AReason, wenn alles stimmt.</summary>
function ReadBody(var AReader: TCacheReader; const AData: TBytes; out AReason: string): TArray<TIndexCacheEntry>;
var
  mStrings: TArray<string>;
  mIndex: Integer;
begin
  Result := nil;
  // Prüfsumme (#492): abgeschnittene oder veränderte Dateien vor dem Dekodieren erkennen.
  if not ChecksumMatches(AReader, AData) then
  begin
    AReason := cTexts[TCacheText.ChecksumDoesNotMatch].Text;
    Exit;
  end;
  mStrings := ReadStringTable(AReader, AData);
  SetLength(Result, AReader.ReadCount);
  for mIndex := 0 to High(Result) do
  begin
    Result[mIndex] := ReadEntry(AReader, AData, mStrings);
  end;
  if AReader.Position <> AReader.Limit then
  begin
    Fail;
  end;
  AReason := '';
end;

class function TIndexCache.ReadEntries(const AData: TBytes; out AReason: string): TArray<TIndexCacheEntry>;
var
  mReader: TCacheReader;
  mVersion: UInt64;
begin
  Result := nil;
  AReason := '';
  if Length(AData) = 0 then
  begin
    Exit;
  end;
  AReason := cTexts[TCacheText.NoAtlasIndexHeaderMissing].Text;
  if not HasMagic(AData) then
  begin
    Exit;
  end;
  mReader.Data := AData;
  mReader.Position := Length(cMagic);
  mReader.Limit := Length(AData);
  try
    mVersion := mReader.ReadVar;
    if mVersion <> cFormatVersion then
    begin
      AReason := cTexts[TCacheText.FormatVersionInsteadOf].Fmt([mVersion, cFormatVersion]);
    end
    else
    begin
      Result := ReadBody(mReader, AData, AReason);
    end;
  except
    on ECacheFormat do
    begin
      Result := nil;
      AReason := cTexts[TCacheText.ContentDamaged].Text;
    end;
  end;
end;

class function TIndexCache.ExpandUsages(const AEntry: TIndexCacheEntry; out AUsages: TArray<TIndexUsage>): Boolean;
var
  mReader: TCacheReader;
  mIndex: Integer;
begin
  AUsages := nil;
  if AEntry.Expanded then
  begin
    AUsages := AEntry.Header.Usages;
    Exit(True);
  end;
  mReader.Data := AEntry.Data;
  mReader.Position := AEntry.UsageOffset;
  mReader.Limit := AEntry.UsageEnd;
  try
    SetLength(AUsages, AEntry.UsageCount);
    for mIndex := 0 to AEntry.UsageCount - 1 do
    begin
      AUsages[mIndex] := ReadUsage(mReader, AEntry.Strings);
    end;
    Result := mReader.Position = mReader.Limit;
  except
    on ECacheFormat do
      Result := False;
  end;
  if not Result then
  begin
    AUsages := nil;
  end;
end;

class function TIndexCache.Expand(const AEntry: TIndexCacheEntry; out AUnit: TUnitIndex): Boolean;
begin
  Result := Expand(AEntry, AUnit, True);
end;

class function TIndexCache.Expand(const AEntry: TIndexCacheEntry; out AUnit: TUnitIndex; AUsages: Boolean): Boolean;
var
  mReader: TCacheReader;
  mIndex: Integer;
begin
  AUnit := AEntry.Header;
  if AEntry.Expanded then
  begin
    Exit(True);
  end;
  mReader.Data := AEntry.Data;
  mReader.Position := AEntry.SymbolOffset;
  mReader.Limit := AEntry.SymbolEnd;
  try
    SetLength(AUnit.Symbols, AEntry.SymbolCount);
    for mIndex := 0 to AEntry.SymbolCount - 1 do
    begin
      AUnit.Symbols[mIndex] := ReadSymbol(mReader, AEntry.Strings);
    end;
    SetLength(AUnit.Unavailable, AEntry.UnavailableCount);
    for mIndex := 0 to AEntry.UnavailableCount - 1 do
    begin
      AUnit.Unavailable[mIndex] := ReadSymbol(mReader, AEntry.Strings);
    end;
    Result := mReader.Position = mReader.Limit;
  except
    on ECacheFormat do
      Result := False;
  end;
  if Result and AEntry.Header.UsagesIndexed then
  begin
    if AUsages then
    begin
      Result := ExpandUsages(AEntry, AUnit.Usages);
    end
    else
    begin
      AUnit.UsagesOffloaded := AEntry.UsageCount > 0;
    end;
  end;
  if not Result then
  begin
    AUnit := AEntry.Header;
  end;
end;

class function TIndexCache.Deserialize(const AData: TBytes): TArray<TUnitIndex>;
var
  mEntries: TArray<TIndexCacheEntry>;
  mIndex: Integer;
begin
  mEntries := ReadEntries(AData);
  SetLength(Result, Length(mEntries));
  for mIndex := 0 to High(mEntries) do
  begin
    if not Expand(mEntries[mIndex], Result[mIndex]) then
    begin
      Exit(nil);
    end;
  end;
end;

class function TIndexCache.HashOf(const AText: string): string;
begin
  Result := THashFNV1a32.GetHashString(AText) + IntToHex(Length(AText), 1);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Index.Cache', cTexts);

end.
