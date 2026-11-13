unit Atlas.Text.PeImage;

// Liest den Kopf einer EXE, DLL oder BPL (Format PE/PE32+) aus ihren Bytes und
// vergleicht ihn mit einer Map-Datei (#74): Passen Einsprungpunkt bzw. Länge
// des Codes nicht zusammen, gehört die Map zu einem anderen Build, und eine
// aufgelöste Absturzadresse wäre falsch. Ohne Windows-API, damit Server (MCP
// resolve_address unter Linux) und Plugin denselben Vergleich nutzen.

interface

uses
  System.SysUtils,
  Atlas.Text.MapFile;

type
  TPeImage = record
    Valid: Boolean;
    /// <summary>PE32+ (64 Bit).</summary>
    Is64: Boolean;
    ImageBase: UInt64;
    /// <summary>Einsprungpunkt relativ zur Modulbasis; 0 ohne.</summary>
    EntryPoint: UInt64;
    /// <summary>Zeitstempel des Linkers (Sekunden seit 1970).</summary>
    TimeStamp: Cardinal;
    /// <summary>Anfang und Länge des Codeabschnitts (.text bzw. CODE) relativ zur Modulbasis; 0 ohne.</summary>
    CodeStart: UInt64;
    CodeSize: UInt64;
    /// <summary>Kopf aus den ersten Bytes der Datei; Valid = False, wenn es keine PE-Datei ist.</summary>
    class function Read(const ABytes: TBytes): TPeImage; static;
  end;

{$SCOPEDENUMS ON}
  /// <summary>Ergebnis des Vergleichs von Map-Datei und EXE.</summary>
  TMapImageMatch = (Unknown, Matches, EntryPointDiffers, CodeSizeDiffers);
{$SCOPEDENUMS OFF}

  TMapImageCheck = class
  public
    /// <summary>Gehört AMap zu AImage? Zuerst über den Einsprungpunkt, ohne ihn über die Länge des Codes;
    /// Unknown, wenn eine Seite keinen der beiden Werte hat.</summary>
    class function Compare(AMap: TMapFile; const AImage: TPeImage): TMapImageMatch; static;
  end;

implementation

const
  cDosSignature = $5A4D;
  cPeSignature = $00004550;
  cLfanewOffset = $3C;
  // Felder des COFF-Kopfs relativ zur Signatur „PE\0\0“.
  cCoffSectionCountField = 6;
  cCoffTimeStampField = 8;
  cCoffOptionalSizeField = 20;
  cCoffSize = 20;
  cMagicPe32 = $10B;
  cMagicPe32Plus = $20B;
  // Felder relativ zum Anfang des optionalen Kopfs.
  cEntryPointField = 16;
  cImageBase32Field = 28;
  cImageBase64Field = 24;
  // Abschnittstabelle: je Eintrag 40 Bytes.
  cSectionSize = 40;
  cSectionNameSize = 8;
  cSectionVirtualSize = 8;
  cSectionVirtualAddress = 12;
  cSectionCharacteristics = 36;
  cSectionCode = $20;
  cBitsPerByte = 8;

/// <summary>Zahl aus ASize Bytes ab AOffset (little endian); False außerhalb der Daten.</summary>
function TryReadNumber(const ABytes: TBytes; AOffset, ASize: Integer; out AValue: UInt64): Boolean;
var
  mIndex: Integer;
begin
  AValue := 0;
  Result := (AOffset >= 0) and (AOffset + ASize <= Length(ABytes));
  if not Result then
  begin
    Exit;
  end;
  for mIndex := ASize - 1 downto 0 do
  begin
    AValue := (AValue shl cBitsPerByte) or ABytes[AOffset + mIndex];
  end;
end;

function NumberAt(const ABytes: TBytes; AOffset, ASize: Integer): UInt64;
begin
  if not TryReadNumber(ABytes, AOffset, ASize, Result) then
  begin
    Result := 0;
  end;
end;

function SectionName(const ABytes: TBytes; AOffset: Integer): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := AOffset to AOffset + cSectionNameSize - 1 do
  begin
    if (mIndex >= Length(ABytes)) or (ABytes[mIndex] = 0) then
    begin
      Break;
    end;
    Result := Result + Char(ABytes[mIndex]);
  end;
end;

/// <summary>Codeabschnitt: .text oder CODE, sonst der erste mit Code-Kennzeichen.</summary>
procedure ReadCodeSection(const ABytes: TBytes; ATable, ACount: Integer; var AImage: TPeImage);
var
  mIndex, mAt, mFallback: Integer;
  mName: string;
begin
  mFallback := -1;
  for mIndex := 0 to ACount - 1 do
  begin
    mAt := ATable + mIndex * cSectionSize;
    mName := SectionName(ABytes, mAt);
    if SameText(mName, '.text') or SameText(mName, 'CODE') then
    begin
      mFallback := mAt;
      Break;
    end;
    if (mFallback < 0) and
      (NumberAt(ABytes, mAt + cSectionCharacteristics, SizeOf(Cardinal)) and cSectionCode <> 0) then
    begin
      mFallback := mAt;
    end;
  end;
  if mFallback >= 0 then
  begin
    AImage.CodeSize := NumberAt(ABytes, mFallback + cSectionVirtualSize, SizeOf(Cardinal));
    AImage.CodeStart := NumberAt(ABytes, mFallback + cSectionVirtualAddress, SizeOf(Cardinal));
  end;
end;

/// <summary>Anfang des PE-Kopfs („PE\0\0“); -1, wenn ABytes keine PE-Datei ist.</summary>
function PeHeaderOf(const ABytes: TBytes): Integer;
var
  mValue: UInt64;
begin
  Result := -1;
  if (NumberAt(ABytes, 0, SizeOf(Word)) = cDosSignature) and
    TryReadNumber(ABytes, cLfanewOffset, SizeOf(Cardinal), mValue) and (mValue < UInt64(Length(ABytes))) and
    (NumberAt(ABytes, Integer(mValue), SizeOf(Cardinal)) = cPeSignature) then
  begin
    Result := Integer(mValue);
  end;
end;

class function TPeImage.Read(const ABytes: TBytes): TPeImage;
var
  mHeader, mOptional, mSections, mCount: Integer;
  mMagic: UInt64;
begin
  Result := Default(TPeImage);
  mHeader := PeHeaderOf(ABytes);
  if mHeader < 0 then
  begin
    Exit;
  end;
  mCount := Integer(NumberAt(ABytes, mHeader + cCoffSectionCountField, SizeOf(Word)));
  Result.TimeStamp := Cardinal(NumberAt(ABytes, mHeader + cCoffTimeStampField, SizeOf(Cardinal)));
  mOptional := mHeader + SizeOf(Cardinal) + cCoffSize;
  mSections := mOptional + Integer(NumberAt(ABytes, mHeader + cCoffOptionalSizeField, SizeOf(Word)));
  mMagic := NumberAt(ABytes, mOptional, SizeOf(Word));
  Result.Is64 := mMagic = cMagicPe32Plus;
  Result.Valid := (mMagic = cMagicPe32) or Result.Is64;
  if not Result.Valid then
  begin
    Exit;
  end;
  Result.EntryPoint := NumberAt(ABytes, mOptional + cEntryPointField, SizeOf(Cardinal));
  if Result.Is64 then
  begin
    Result.ImageBase := NumberAt(ABytes, mOptional + cImageBase64Field, SizeOf(UInt64));
  end
  else
  begin
    Result.ImageBase := NumberAt(ABytes, mOptional + cImageBase32Field, SizeOf(Cardinal));
  end;
  ReadCodeSection(ABytes, mSections, mCount, Result);
end;

{ TMapImageCheck }

class function TMapImageCheck.Compare(AMap: TMapFile; const AImage: TPeImage): TMapImageMatch;
begin
  Result := TMapImageMatch.Unknown;
  if (AMap = nil) or not AImage.Valid then
  begin
    Exit;
  end;
  if (AMap.EntryPoint > 0) and (AImage.EntryPoint > 0) then
  begin
    Result := TMapImageMatch.EntryPointDiffers;
    if AMap.EntryPoint = AImage.EntryPoint then
    begin
      Result := TMapImageMatch.Matches;
    end;
  end
  else if (AMap.CodeSize > 0) and (AImage.CodeSize > 0) then
  begin
    Result := TMapImageMatch.CodeSizeDiffers;
    if AMap.CodeSize = AImage.CodeSize then
    begin
      Result := TMapImageMatch.Matches;
    end;
  end;
end;

end.
