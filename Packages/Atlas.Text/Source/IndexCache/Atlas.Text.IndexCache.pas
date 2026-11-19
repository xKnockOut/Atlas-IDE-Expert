unit Atlas.Text.IndexCache;

// Grundbausteine des Index-Caches des Servers (Format und Schreiben in
// Atlas.Common.Index.Cache), gemeinsam für Server und Plugin: Die
// Willkommensseite liest die Units eines Caches ohne laufenden Server.
// Kopf: Kennung "ATLASIDX", Formatversion, 4 Byte Prüfsumme (FNV-1a, 32 Bit,
// über alles dahinter, niederwertiges Byte zuerst). Werte: Zahlen mit
// variabler Länge (7 Bit je Byte), Verweise in die Texttabelle, Listen als
// Anzahl und Einträge. Jede Überschreitung löst EIndexCacheFormat aus; der
// Aufrufer fängt sie und nennt den Grund selbst.

interface

uses
  System.SysUtils;

const
  cIndexCacheMagic: array[0..7] of Byte = (Ord('A'), Ord('T'), Ord('L'), Ord('A'), Ord('S'), Ord('I'), Ord('D'),
    Ord('X'));
  cIndexCacheChecksumSize = 4;

type
  EIndexCacheFormat = class(Exception);

  /// <summary>Liest Werte aus Data zwischen Position und Limit.</summary>
  TIndexCacheReader = record
    Data: TBytes;
    Position: Integer;
    Limit: Integer;
    /// <summary>Beginnt AData mit der Kennung cIndexCacheMagic?</summary>
    class function HasMagic(const AData: TBytes): Boolean; static;
    /// <summary>FNV-1a (32 Bit) über AData von AFrom bis vor ATo.</summary>
    class function Checksum(const AData: TBytes; AFrom, ATo: Integer): Cardinal; static;
    /// <summary>Löst EIndexCacheFormat aus.</summary>
    class procedure Fail; static;
    function ReadByte: Byte;
    function ReadVar: UInt64;
    /// <summary>Anzahl; mehr als Limit Einträge kann es nicht geben.</summary>
    function ReadCount: Integer;
    /// <summary>Nicht negative Zahl bis High(Integer), unabhängig von der Dateigröße.</summary>
    function ReadNumber: Integer;
    /// <summary>Ganzzahl mit Vorzeichen im niedrigsten Bit.</summary>
    function ReadInt: Int64;
    function ReadInt32: Integer;
    /// <summary>Eintrag der Texttabelle AStrings.</summary>
    function ReadString(const AStrings: TArray<string>): string;
    function ReadList(const AStrings: TArray<string>): TArray<string>;
    procedure Skip(ACount: Integer);
    /// <summary>Liste von Zahlen bzw. Textverweisen überspringen.</summary>
    procedure SkipList;
    /// <summary>Gespeicherte Prüfsumme an Position lesen und mit der über den Rest von Data vergleichen.</summary>
    function ChecksumMatches: Boolean;
  end;

implementation

{ TIndexCacheReader }

class function TIndexCacheReader.HasMagic(const AData: TBytes): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(AData) >= Length(cIndexCacheMagic);
  mIndex := Low(cIndexCacheMagic);
  while Result and (mIndex <= High(cIndexCacheMagic)) do
  begin
    Result := AData[mIndex] = cIndexCacheMagic[mIndex];
    Inc(mIndex);
  end;
end;

class function TIndexCacheReader.Checksum(const AData: TBytes; AFrom, ATo: Integer): Cardinal;
var
  mIndex: Integer;
begin
  Result := 2166136261;
  for mIndex := AFrom to ATo - 1 do
  begin
    Result := Cardinal(UInt64(Result xor AData[mIndex]) * 16777619);
  end;
end;

class procedure TIndexCacheReader.Fail;
begin
  raise EIndexCacheFormat.Create('Index cache damaged');
end;

function TIndexCacheReader.ReadByte: Byte;
begin
  if Position >= Limit then
  begin
    Fail;
  end;
  Result := Data[Position];
  Inc(Position);
end;

function TIndexCacheReader.ReadVar: UInt64;
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

function TIndexCacheReader.ReadCount: Integer;
var
  mValue: UInt64;
begin
  mValue := ReadVar;
  if mValue > UInt64(Limit) then
  begin
    Fail;
  end;
  Result := Integer(mValue);
end;

function TIndexCacheReader.ReadNumber: Integer;
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

function TIndexCacheReader.ReadInt: Int64;
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

function TIndexCacheReader.ReadInt32: Integer;
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

function TIndexCacheReader.ReadString(const AStrings: TArray<string>): string;
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

function TIndexCacheReader.ReadList(const AStrings: TArray<string>): TArray<string>;
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

procedure TIndexCacheReader.Skip(ACount: Integer);
begin
  if (ACount < 0) or (Position + ACount > Limit) then
  begin
    Fail;
  end;
  Inc(Position, ACount);
end;

procedure TIndexCacheReader.SkipList;
var
  mCount, mIndex: Integer;
begin
  mCount := ReadCount;
  for mIndex := 1 to mCount do
  begin
    ReadVar;
  end;
end;

function TIndexCacheReader.ChecksumMatches: Boolean;
var
  mIndex: Integer;
  mStored: Cardinal;
begin
  if Position + cIndexCacheChecksumSize > Limit then
  begin
    Fail;
  end;
  mStored := 0;
  for mIndex := cIndexCacheChecksumSize - 1 downto 0 do
  begin
    mStored := (mStored shl 8) or Data[Position + mIndex];
  end;
  Inc(Position, cIndexCacheChecksumSize);
  Result := mStored = Checksum(Data, Position, Length(Data));
end;

end.
