unit BDLsp.Common.Dfm.ImagePreview;

// Bildvorschau im Hover für Binärdaten einer Text-DFM (#271): Picture.Data,
// Glyph.Data, Bitmap = {…}. Die Hex-Daten werden dekodiert, ein Klassen-
// Präfix (TPngImage, TBitmap, TJPEGImage) und ein Längenfeld übersprungen und
// das Bild als data:-URL im Markdown ausgegeben. BMP wird nach PNG
// umgewandelt (unkomprimiert, ohne zlib); PNG, JPEG und GIF bleiben, wie sie
// sind. Größere Bilder als MaxSide zeigen nur ihre Abmessungen.

interface

uses
  System.SysUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Dfm.Contract;

type
  {$SCOPEDENUMS ON}
  TDfmImageFormat = (None, Png, Bmp, Jpeg, Gif);
  {$SCOPEDENUMS OFF}

  /// <summary>Erkanntes Bild in Binärdaten.</summary>
  TDfmImage = record
    Format: TDfmImageFormat;
    /// <summary>Klasse aus dem Präfix, z. B. TPngImage; '' ohne.</summary>
    ClassName: string;
    Width: Integer;
    Height: Integer;
    /// <summary>Bilddaten ohne Präfix und Längenfeld.</summary>
    Data: TBytes;
  end;

  TDfmImagePreview = class
  public
    const MaxSide = 256;
    /// <summary>Hex-Text "{ 0A0B … }" als Bytes; Zeichen außer Hexziffern werden übergangen.</summary>
    class function DecodeHex(const AValue: string): TBytes; static;
    /// <summary>Bild in den Binärdaten einer Eigenschaft; Format None, wenn keines erkannt wird.</summary>
    class function Detect(const AData: TBytes): TDfmImage; static;
    /// <summary>BMP (1, 4, 8, 24, 32 Bit, unkomprimiert) als PNG; nil bei anderen Formen.</summary>
    class function BmpToPng(const ABmp: TBytes): TBytes; static;
    class function Base64(const AData: TBytes): string; static;
    /// <summary>Markdown für den Hover über Binärdaten an APosition; '' ohne Bild.</summary>
    class function HoverAt(const AFormText: string; const APosition: TTextPosition): string; static;
  end;

implementation

uses
  BDLsp.Common.Dfm.Parser;

function ReadInt32(const AData: TBytes; AOffset: Integer): Integer;
begin
  Result := Integer(Cardinal(AData[AOffset]) or (Cardinal(AData[AOffset + 1]) shl 8) or
    (Cardinal(AData[AOffset + 2]) shl 16) or (Cardinal(AData[AOffset + 3]) shl 24));
end;

function ReadWord(const AData: TBytes; AOffset: Integer): Integer;
begin
  Result := AData[AOffset] or (AData[AOffset + 1] shl 8);
end;

function ReadBigInt32(const AData: TBytes; AOffset: Integer): Integer;
begin
  Result := Integer((Cardinal(AData[AOffset]) shl 24) or (Cardinal(AData[AOffset + 1]) shl 16) or
    (Cardinal(AData[AOffset + 2]) shl 8) or Cardinal(AData[AOffset + 3]));
end;

function HexValue(AChar: Char): Integer;
begin
  case AChar of
    '0'..'9': Result := Ord(AChar) - Ord('0');
    'A'..'F': Result := Ord(AChar) - Ord('A') + 10;
    'a'..'f': Result := Ord(AChar) - Ord('a') + 10;
  else
    Result := -1;
  end;
end;

{ TDfmImagePreview }

class function TDfmImagePreview.DecodeHex(const AValue: string): TBytes;
var
  Index, Count, High4, Digit: Integer;
begin
  SetLength(Result, Length(AValue) div 2);
  Count := 0;
  High4 := -1;
  for Index := 1 to Length(AValue) do
  begin
    Digit := HexValue(AValue[Index]);
    if Digit < 0 then
      Continue;
    if High4 < 0 then
      High4 := Digit
    else
    begin
      Result[Count] := Byte(High4 shl 4 or Digit);
      Inc(Count);
      High4 := -1;
    end;
  end;
  SetLength(Result, Count);
end;

function FormatAt(const AData: TBytes; AOffset: Integer): TDfmImageFormat;
begin
  Result := TDfmImageFormat.None;
  if AOffset + 8 > Length(AData) then
    Exit;
  if (AData[AOffset] = $89) and (AData[AOffset + 1] = Ord('P')) and (AData[AOffset + 2] = Ord('N')) and
    (AData[AOffset + 3] = Ord('G')) then
    Result := TDfmImageFormat.Png
  else if (AData[AOffset] = Ord('B')) and (AData[AOffset + 1] = Ord('M')) then
    Result := TDfmImageFormat.Bmp
  else if (AData[AOffset] = $FF) and (AData[AOffset + 1] = $D8) then
    Result := TDfmImageFormat.Jpeg
  else if (AData[AOffset] = Ord('G')) and (AData[AOffset + 1] = Ord('I')) and (AData[AOffset + 2] = Ord('F')) then
    Result := TDfmImageFormat.Gif;
end;

procedure ReadSize(var AImage: TDfmImage);
var
  Data: TBytes;
  Index: Integer;
begin
  Data := AImage.Data;
  case AImage.Format of
    TDfmImageFormat.Png:
      if Length(Data) >= 24 then
      begin
        AImage.Width := ReadBigInt32(Data, 16);
        AImage.Height := ReadBigInt32(Data, 20);
      end;
    TDfmImageFormat.Bmp:
      if Length(Data) >= 26 then
      begin
        AImage.Width := ReadInt32(Data, 18);
        AImage.Height := Abs(ReadInt32(Data, 22));
      end;
    TDfmImageFormat.Gif:
      if Length(Data) >= 10 then
      begin
        AImage.Width := ReadWord(Data, 6);
        AImage.Height := ReadWord(Data, 8);
      end;
    TDfmImageFormat.Jpeg:
      begin
        // SOF0..SOF3: FF C0..C3, Länge, Präzision, Höhe, Breite (big endian).
        Index := 2;
        while Index + 9 < Length(Data) do
        begin
          if Data[Index] <> $FF then
            Break;
          if Data[Index + 1] in [$C0..$C3] then
          begin
            AImage.Height := (Data[Index + 5] shl 8) or Data[Index + 6];
            AImage.Width := (Data[Index + 7] shl 8) or Data[Index + 8];
            Break;
          end;
          Inc(Index, 2 + ((Data[Index + 2] shl 8) or Data[Index + 3]));
        end;
      end;
  end;
end;

class function TDfmImagePreview.Detect(const AData: TBytes): TDfmImage;
var
  Offset, NameLength, Index: Integer;
  Name: string;
begin
  Result := Default(TDfmImage);
  Offset := 0;
  // Präfix aus TPicture: Länge und Klassenname, z. B. #9'TPngImage'.
  if Length(AData) > 2 then
  begin
    NameLength := AData[0];
    if (NameLength > 1) and (NameLength < 64) and (NameLength < Length(AData)) and (AData[1] = Ord('T')) then
    begin
      Name := '';
      for Index := 1 to NameLength do
        if CharInSet(Char(AData[Index]), ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
          Name := Name + Char(AData[Index])
        else
        begin
          Name := '';
          Break;
        end;
      if Name <> '' then
      begin
        Result.ClassName := Name;
        Offset := NameLength + 1;
      end;
    end;
  end;
  // TBitmap und TJPEGImage schreiben vor den Daten ein Längenfeld (Int32).
  Result.Format := FormatAt(AData, Offset);
  if Result.Format = TDfmImageFormat.None then
  begin
    Result.Format := FormatAt(AData, Offset + 4);
    if Result.Format <> TDfmImageFormat.None then
      Inc(Offset, 4);
  end;
  if Result.Format = TDfmImageFormat.None then
    Exit;
  Result.Data := Copy(AData, Offset, MaxInt);
  ReadSize(Result);
end;

var
  CrcTable: array[0..255] of Cardinal;

procedure InitCrcTable;
var
  Index, Bit: Integer;
  Value: Cardinal;
begin
  for Index := 0 to 255 do
  begin
    Value := Index;
    for Bit := 0 to 7 do
      if Value and 1 <> 0 then
        Value := $EDB88320 xor (Value shr 1)
      else
        Value := Value shr 1;
    CrcTable[Index] := Value;
  end;
end;

function Crc32(const AData: TBytes; AStart, ACount: Integer): Cardinal;
var
  Index: Integer;
begin
  Result := $FFFFFFFF;
  for Index := AStart to AStart + ACount - 1 do
    Result := CrcTable[(Result xor AData[Index]) and $FF] xor (Result shr 8);
  Result := Result xor $FFFFFFFF;
end;

procedure PutBig(var AData: TBytes; var APos: Integer; AValue: Cardinal);
begin
  AData[APos] := Byte(AValue shr 24);
  AData[APos + 1] := Byte(AValue shr 16);
  AData[APos + 2] := Byte(AValue shr 8);
  AData[APos + 3] := Byte(AValue);
  Inc(APos, 4);
end;

procedure AddChunk(var APng: TBytes; var APos: Integer; const AType: string; const AData: TBytes);
var
  Start, Index: Integer;
begin
  PutBig(APng, APos, Length(AData));
  Start := APos;
  for Index := 1 to 4 do
    APng[APos + Index - 1] := Ord(AType[Index]);
  Inc(APos, 4);
  if Length(AData) > 0 then
    Move(AData[0], APng[APos], Length(AData));
  Inc(APos, Length(AData));
  PutBig(APng, APos, Crc32(APng, Start, 4 + Length(AData)));
end;

/// <summary>zlib-Strom aus unkomprimierten Deflate-Blöcken.</summary>
function StoredZlib(const ARaw: TBytes): TBytes;
const
  BlockSize = 65535;
var
  Pos, Done, Size, Index: Integer;
  A, B: Cardinal;
begin
  SetLength(Result, 2 + Length(ARaw) + 5 * (Length(ARaw) div BlockSize + 1) + 4);
  Result[0] := $78;
  Result[1] := $01;
  Pos := 2;
  Done := 0;
  repeat
    Size := Length(ARaw) - Done;
    if Size > BlockSize then
      Size := BlockSize;
    if Done + Size >= Length(ARaw) then
      Result[Pos] := 1
    else
      Result[Pos] := 0;
    Result[Pos + 1] := Byte(Size);
    Result[Pos + 2] := Byte(Size shr 8);
    Result[Pos + 3] := Byte(not Size);
    Result[Pos + 4] := Byte((not Size) shr 8);
    Inc(Pos, 5);
    if Size > 0 then
      Move(ARaw[Done], Result[Pos], Size);
    Inc(Pos, Size);
    Inc(Done, Size);
  until Done >= Length(ARaw);
  A := 1;
  B := 0;
  for Index := 0 to High(ARaw) do
  begin
    A := (A + ARaw[Index]) mod 65521;
    B := (B + A) mod 65521;
  end;
  PutBig(Result, Pos, (B shl 16) or A);
  SetLength(Result, Pos);
end;

class function TDfmImagePreview.BmpToPng(const ABmp: TBytes): TBytes;
var
  DataOffset, HeaderSize, Width, Height, Bits, Compression, Colors, Stride: Integer;
  TopDown: Boolean;
  Palette: array of Cardinal;
  Raw, Header: TBytes;
  X, Y, Row, Source, Target, Value, Pos: Integer;
  Color: Cardinal;
begin
  Result := nil;
  if (Length(ABmp) < 54) or (ABmp[0] <> Ord('B')) or (ABmp[1] <> Ord('M')) then
    Exit;
  DataOffset := ReadInt32(ABmp, 10);
  HeaderSize := ReadInt32(ABmp, 14);
  Width := ReadInt32(ABmp, 18);
  Height := ReadInt32(ABmp, 22);
  Bits := ReadWord(ABmp, 28);
  Compression := ReadInt32(ABmp, 30);
  TopDown := Height < 0;
  Height := Abs(Height);
  // 0 = BI_RGB; 3 = BI_BITFIELDS bei 32 Bit mit Standardmasken.
  if (Width <= 0) or (Height <= 0) or not ((Compression = 0) or ((Compression = 3) and (Bits = 32))) or
    not (Bits in [1, 4, 8, 24, 32]) then
    Exit;
  Stride := ((Width * Bits + 31) div 32) * 4;
  if DataOffset + Stride * Height > Length(ABmp) then
    Exit;
  if Bits <= 8 then
  begin
    Colors := ReadInt32(ABmp, 46);
    if Colors = 0 then
      Colors := 1 shl Bits;
    SetLength(Palette, Colors);
    for X := 0 to Colors - 1 do
      if 14 + HeaderSize + X * 4 + 3 < Length(ABmp) then
        Palette[X] := Cardinal(ReadInt32(ABmp, 14 + HeaderSize + X * 4));
  end;
  // Zeilen mit Filterbyte 0, Pixel als RGBA.
  SetLength(Raw, Height * (1 + Width * 4));
  Target := 0;
  for Y := 0 to Height - 1 do
  begin
    if TopDown then
      Row := Y
    else
      Row := Height - 1 - Y;
    Source := DataOffset + Row * Stride;
    Raw[Target] := 0;
    Inc(Target);
    for X := 0 to Width - 1 do
    begin
      case Bits of
        1, 4, 8:
          begin
            Value := ABmp[Source + (X * Bits) div 8];
            Value := (Value shr (8 - Bits - (X * Bits) mod 8)) and ((1 shl Bits) - 1);
            if Value < Length(Palette) then
              Color := Palette[Value]
            else
              Color := 0;
          end;
        24:
          Color := Cardinal(ABmp[Source + X * 3]) or (Cardinal(ABmp[Source + X * 3 + 1]) shl 8) or
            (Cardinal(ABmp[Source + X * 3 + 2]) shl 16);
      else
        Color := Cardinal(ReadInt32(ABmp, Source + X * 4)) and $FFFFFF;
      end;
      Raw[Target] := Byte(Color shr 16);
      Raw[Target + 1] := Byte(Color shr 8);
      Raw[Target + 2] := Byte(Color);
      Raw[Target + 3] := $FF;
      Inc(Target, 4);
    end;
  end;
  SetLength(Header, 13);
  Pos := 0;
  PutBig(Header, Pos, Width);
  PutBig(Header, Pos, Height);
  Header[8] := 8;
  Header[9] := 6;
  Header[10] := 0;
  Header[11] := 0;
  Header[12] := 0;
  Raw := StoredZlib(Raw);
  SetLength(Result, 8 + 25 + 12 + Length(Raw) + 12);
  Result[0] := $89;
  Result[1] := Ord('P');
  Result[2] := Ord('N');
  Result[3] := Ord('G');
  Result[4] := $0D;
  Result[5] := $0A;
  Result[6] := $1A;
  Result[7] := $0A;
  Pos := 8;
  AddChunk(Result, Pos, 'IHDR', Header);
  AddChunk(Result, Pos, 'IDAT', Raw);
  AddChunk(Result, Pos, 'IEND', nil);
end;

class function TDfmImagePreview.Base64(const AData: TBytes): string;
const
  Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
var
  Index, Pos: Integer;
  Value: Cardinal;
  Builder: TStringBuilder;
begin
  Builder := TStringBuilder.Create((Length(AData) + 2) div 3 * 4);
  try
    Index := 0;
    while Index < Length(AData) do
    begin
      Value := Cardinal(AData[Index]) shl 16;
      if Index + 1 < Length(AData) then
        Value := Value or (Cardinal(AData[Index + 1]) shl 8);
      if Index + 2 < Length(AData) then
        Value := Value or AData[Index + 2];
      for Pos := 0 to 3 do
        if Index + Pos - 1 < Length(AData) then
          Builder.Append(Alphabet[((Value shr (18 - 6 * Pos)) and $3F) + 1])
        else
          Builder.Append('=');
      Inc(Index, 3);
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

/// <summary>Eigenschaft mit Binärdaten, deren Name oder Wert APosition umfasst.</summary>
function FindBinary(AObject: TDfmObject; const APosition: TTextPosition; out AProperty: TDfmProperty): Boolean;
var
  Item: TDfmProperty;
  Child: TDfmObject;
begin
  for Item in AObject.Properties do
    if (Item.Value <> '') and (TrimLeft(Item.Value)[1] = '{') and
      (APosition.Line >= Item.NameRange.StartPos.Line) and (APosition.Line <= Item.ValueRange.EndPos.Line) then
    begin
      AProperty := Item;
      Exit(True);
    end;
  for Child in AObject.Children do
    if FindBinary(Child, APosition, AProperty) then
      Exit(True);
  Result := False;
end;

class function TDfmImagePreview.HoverAt(const AFormText: string; const APosition: TTextPosition): string;
const
  Names: array[TDfmImageFormat] of string = ('', 'PNG', 'BMP', 'JPEG', 'GIF');
  Mime: array[TDfmImageFormat] of string = ('', 'image/png', 'image/png', 'image/jpeg', 'image/gif');
var
  Document: TDfmDocument;
  Item: TDfmProperty;
  Image: TDfmImage;
  Data: TBytes;
  Title: string;
begin
  Result := '';
  Document := TDfmParser.Parse(AFormText);
  try
    if (Document.Root = nil) or not FindBinary(Document.Root, APosition, Item) then
      Exit;
  finally
    Document.Free;
  end;
  Image := Detect(DecodeHex(Item.Value));
  if Image.Format = TDfmImageFormat.None then
    Exit;
  Title := Format('**%s**: %s, %d × %d', [Item.Name, Names[Image.Format], Image.Width, Image.Height]);
  if Image.ClassName <> '' then
    Title := Title + Format(' (%s)', [Image.ClassName]);
  if (Image.Width > MaxSide) or (Image.Height > MaxSide) then
    Exit(Title + #10#10 + Format('Zu groß für die Vorschau (höchstens %d × %d).', [MaxSide, MaxSide]));
  if Image.Format = TDfmImageFormat.Bmp then
    Data := BmpToPng(Image.Data)
  else
    Data := Image.Data;
  if Data = nil then
    Exit(Title + #10#10'Dieses BMP-Format kann die Vorschau nicht anzeigen.');
  Result := Title + #10#10 + Format('![%s](data:%s;base64,%s)', [Item.Name, Mime[Image.Format], Base64(Data)]);
end;

initialization
  InitCrcTable;

end.
