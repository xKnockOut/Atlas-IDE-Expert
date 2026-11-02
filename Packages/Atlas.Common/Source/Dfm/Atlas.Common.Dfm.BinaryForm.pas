unit Atlas.Common.Dfm.BinaryForm;

// Binäre Formulardateien (#122). Wandelt das Binärformat (Signatur TPF0,
// optional mit Ressourcen-Kopf FF 0A 00) im Speicher in Text um, so wie
// ObjectBinaryToText aus System.Classes: zwei Leerzeichen Einzug je Ebene,
// CRLF, Zeichen außerhalb von ASCII und das Hochkomma in Strings als #nnn,
// lange Strings nach 64 Zeichen mit " +" umbrochen. Komponentenklassen werden
// nicht gebraucht. Der Text-Parser (#44) liest das Ergebnis wie eine Text-DFM.
//
// Erhält der Server den Inhalt schon als Text (Windows-1252 bzw. UTF-8
// dekodiert), stellt FromDecodedText die Bytes wieder her.

interface

uses
  System.SysUtils;

type
  TDfmBinary = class
  public const
    /// <summary>Zeichen je Stringstück, wie LineLength in System.Classes.</summary>
    LineLength = 64;
  public
    /// <summary>Beginnt mit TPF0 oder dem Ressourcen-Kopf FF 0A 00?</summary>
    class function IsBinary(const ABytes: TBytes): Boolean; static;
    /// <summary>Text-DFM mit CRLF; False bei beschädigten Daten.</summary>
    class function ToText(const ABytes: TBytes; out AText: string): Boolean; static;
    /// <summary>Wie ToText für den schon dekodierten Dateiinhalt.</summary>
    class function FromDecodedText(const AText: string; out AFormText: string): Boolean; static;
    /// <summary>Liegt AFileName in einem Ordner unter Versionskontrolle (.git, .svn, .hg)?</summary>
    class function UnderVersionControl(const AFileName: string): Boolean; static;
    /// <summary>Schreibt die binäre Formulardatei als Text (UTF-8 ohne BOM, CRLF). Ohne Versionskontrolle
    /// wird vorher AFileName + '.bak' angelegt (ABackup, sonst ''). False, wenn die Datei nicht
    /// binär oder nicht lesbar ist.</summary>
    class function ConvertFile(const AFileName: string; out ABackup: string): Boolean; static;
  end;

implementation

uses
  System.Math,
  System.IOUtils;

const
  vaNull = 0;
  vaList = 1;
  vaInt8 = 2;
  vaInt16 = 3;
  vaInt32 = 4;
  vaExtended = 5;
  vaString = 6;
  vaIdent = 7;
  vaFalse = 8;
  vaTrue = 9;
  vaBinary = 10;
  vaSet = 11;
  vaLString = 12;
  vaNil = 13;
  vaCollection = 14;
  vaSingle = 15;
  vaCurrency = 16;
  vaDate = 17;
  vaWString = 18;
  vaInt64 = 19;
  vaUTF8String = 20;
  vaDouble = 21;

  ffInherited = 1;
  ffChildPos = 2;
  ffInline = 4;

  CrLf = #13#10;

  Cp1252High: array[$80..$9F] of Word = (
    $20AC, $0081, $201A, $0192, $201E, $2026, $2020, $2021,
    $02C6, $2030, $0160, $2039, $0152, $008D, $017D, $008F,
    $0090, $2018, $2019, $201C, $201D, $2022, $2013, $2014,
    $02DC, $2122, $0161, $203A, $0153, $009D, $017E, $0178);

type
  EBinaryForm = class(Exception);

  TConverter = class
  private
    FBytes: TBytes;
    FPos: Integer;
    FOut: TStringBuilder;
    FNesting: Integer;
    function ReadByte: Byte;
    function NextByte: Byte;
    function ReadBytes(ACount: Integer): TBytes;
    function ReadInt16: SmallInt;
    function ReadInt32: Integer;
    function ReadInt64: Int64;
    function ReadDouble: Double;
    function ReadSingle: Single;
    function ReadExtended: Double;
    function ReadStr: string;
    function ReadInteger: Int64;
    function EndOfList: Boolean;
    procedure ReadListEnd;
    procedure Emit(const AText: string);
    procedure WriteIndent;
    procedure NewLine;
    procedure WriteString(const AText: string);
    procedure ConvertList;
    procedure ConvertBinary;
    procedure ConvertSet;
    procedure ConvertCollectionItem;
    procedure ConvertCollection;
    /// <summary>Text eines Werts vaString, vaLString, vaWString oder vaUTF8String.</summary>
    function ReadText(AKind: Byte): string;
    /// <summary>Text eines einfachen Werts (Zahl, Bezeichner, True, nil …); EBinaryForm bei unbekanntem.</summary>
    function ScalarText(AKind: Byte): string;
    procedure ConvertValue;
    procedure ConvertProperty;
    procedure ConvertObject;
  public
    constructor Create(const ABytes: TBytes; AStart: Integer);
    destructor Destroy; override;
    function Run: string;
  end;

function FloatText(AValue: Double): string;
var
  Settings: TFormatSettings;
begin
  Settings := TFormatSettings.Create;
  Settings.DecimalSeparator := '.';
  Result := FloatToStr(AValue, Settings);
end;

{ TConverter }

constructor TConverter.Create(const ABytes: TBytes; AStart: Integer);
begin
  inherited Create;
  FBytes := ABytes;
  FPos := AStart;
  FOut := TStringBuilder.Create;
end;

destructor TConverter.Destroy;
begin
  FOut.Free;
  inherited;
end;

function TConverter.ReadByte: Byte;
begin
  if FPos >= Length(FBytes) then
  begin
    raise EBinaryForm.Create('Unerwartetes Dateiende');
  end;
  Result := FBytes[FPos];
  Inc(FPos);
end;

function TConverter.NextByte: Byte;
begin
  if FPos >= Length(FBytes) then
  begin
    raise EBinaryForm.Create('Unerwartetes Dateiende');
  end;
  Result := FBytes[FPos];
end;

function TConverter.ReadBytes(ACount: Integer): TBytes;
begin
  if (ACount < 0) or (FPos + ACount > Length(FBytes)) then
  begin
    raise EBinaryForm.Create('Unerwartetes Dateiende');
  end;
  Result := Copy(FBytes, FPos, ACount);
  Inc(FPos, ACount);
end;

function TConverter.ReadInt16: SmallInt;
var
  Bytes: TBytes;
begin
  Bytes := ReadBytes(2);
  Result := SmallInt(Bytes[0] or (Bytes[1] shl 8));
end;

function TConverter.ReadInt32: Integer;
var
  Bytes: TBytes;
begin
  Bytes := ReadBytes(4);
  Result := Integer(Cardinal(Bytes[0]) or (Cardinal(Bytes[1]) shl 8) or (Cardinal(Bytes[2]) shl 16) or
    (Cardinal(Bytes[3]) shl 24));
end;

function TConverter.ReadInt64: Int64;
var
  Low, High: Cardinal;
begin
  Low := Cardinal(ReadInt32);
  High := Cardinal(ReadInt32);
  Result := Int64(UInt64(Low) or (UInt64(High) shl 32));
end;

function TConverter.ReadDouble: Double;
var
  Bits: Int64;
begin
  Bits := ReadInt64;
  Move(Bits, Result, SizeOf(Result));
end;

function TConverter.ReadSingle: Single;
var
  Bits: Integer;
begin
  Bits := ReadInt32;
  Move(Bits, Result, SizeOf(Result));
end;

function TConverter.ReadExtended: Double;
var
  Mantissa: UInt64;
  Exponent: Integer;
  Negative: Boolean;
  Bytes: TBytes;
  Index: Integer;
begin
  // 80-Bit-Extended: 64 Bit Mantisse mit explizitem Eins-Bit, 15 Bit Exponent, Vorzeichen.
  Bytes := ReadBytes(10);
  Mantissa := 0;
  for Index := 7 downto 0 do
  begin
    Mantissa := (Mantissa shl 8) or Bytes[Index];
  end;
  Exponent := (Bytes[8] or (Bytes[9] shl 8)) and $7FFF;
  Negative := (Bytes[9] and $80) <> 0;
  if (Mantissa = 0) and (Exponent = 0) then
  begin
    Result := 0;
  end
  else
  begin
    Result := Ldexp(Mantissa, Exponent - 16383 - 63);
  end;
  if Negative then
  begin
    Result := -Result;
  end;
end;

function TConverter.ReadStr: string;
var
  Count: Integer;
begin
  Count := ReadByte;
  Result := TEncoding.UTF8.GetString(ReadBytes(Count));
end;

function TConverter.ReadInteger: Int64;
begin
  case ReadByte of
    vaInt8: Result := ShortInt(ReadByte);
    vaInt16: Result := ReadInt16;
    vaInt32: Result := ReadInt32;
    vaInt64: Result := ReadInt64;
  else
    raise EBinaryForm.Create('Ganzzahl erwartet');
  end;
end;

function TConverter.EndOfList: Boolean;
begin
  Result := NextByte = vaNull;
end;

procedure TConverter.ReadListEnd;
begin
  if ReadByte <> vaNull then
  begin
    raise EBinaryForm.Create('Listenende erwartet');
  end;
end;

procedure TConverter.Emit(const AText: string);
begin
  FOut.Append(AText);
end;

procedure TConverter.WriteIndent;
begin
  FOut.Append(StringOfChar(' ', FNesting * 2));
end;

procedure TConverter.NewLine;
begin
  Emit(CrLf);
  WriteIndent;
end;

/// <summary>Zeichen, das in einem Text in Hochkommas stehen darf (druckbares ASCII ohne Hochkomma).</summary>
function IsPlainChar(ACh: Char): Boolean;
begin
  Result := (ACh >= ' ') and (ACh <> '''') and (Ord(ACh) <= 127);
end;

/// <summary>Ende des Laufs druckbarer Zeichen ab AIndex, höchstens bis zur Zeilenlänge ab ALineStart.</summary>
function PlainRunEnd(const AText: string; AIndex, ALineStart: Integer): Integer;
begin
  Result := AIndex;
  repeat
    Inc(Result);
  until (Result > Length(AText)) or not IsPlainChar(AText[Result]) or
    (Result - ALineStart >= TDfmBinary.LineLength);
end;

procedure TConverter.WriteString(const AText: string);
var
  mIndex, mStart, mLineStart: Integer;
begin
  if AText = '' then
  begin
    Emit('''''');
    Exit;
  end;
  mIndex := 1;
  Inc(FNesting);
  try
    if Length(AText) > TDfmBinary.LineLength then
    begin
      NewLine;
    end;
    mLineStart := mIndex;
    repeat
      if IsPlainChar(AText[mIndex]) then
      begin
        mStart := mIndex;
        mIndex := PlainRunEnd(AText, mIndex, mLineStart);
        Emit('''' + Copy(AText, mStart, mIndex - mStart) + '''');
      end
      else
      begin
        Emit('#' + IntToStr(Ord(AText[mIndex])));
        Inc(mIndex);
      end;
      if (mIndex - mLineStart >= TDfmBinary.LineLength) and (mIndex <= Length(AText)) then
      begin
        Emit(' +');
        NewLine;
        mLineStart := mIndex;
      end;
    until mIndex > Length(AText);
  finally
    Dec(FNesting);
  end;
end;

procedure TConverter.ConvertList;
begin
  ReadByte;
  Emit('(');
  Inc(FNesting);
  while not EndOfList do
  begin
    NewLine;
    ConvertValue;
  end;
  ReadListEnd;
  Dec(FNesting);
  Emit(')');
end;

procedure TConverter.ConvertBinary;
const
  HexDigits = '0123456789ABCDEF';
var
  mCount, mIndex, mChunk: Integer;
  mBytes: TBytes;
  mLine: string;
begin
  ReadByte;
  mCount := ReadInt32;
  mBytes := ReadBytes(mCount);
  Emit('{');
  Inc(FNesting);
  mIndex := 0;
  while mIndex < mCount do
  begin
    NewLine;
    mChunk := Min(32, mCount - mIndex);
    mLine := '';
    while mChunk > 0 do
    begin
      mLine := mLine + HexDigits[mBytes[mIndex] shr 4 + 1] + HexDigits[mBytes[mIndex] and $F + 1];
      Inc(mIndex);
      Dec(mChunk);
    end;
    Emit(mLine);
  end;
  Dec(FNesting);
  Emit('}');
end;

procedure TConverter.ConvertSet;
var
  mName: string;
  mFirst: Boolean;
begin
  ReadByte;
  Emit('[');
  mFirst := True;
  mName := ReadStr;
  while mName <> '' do
  begin
    if not mFirst then
    begin
      Emit(', ');
    end;
    Emit(mName);
    mFirst := False;
    mName := ReadStr;
  end;
  Emit(']');
end;

procedure TConverter.ConvertCollectionItem;
begin
  NewLine;
  Emit('item');
  if NextByte in [vaInt8, vaInt16, vaInt32] then
  begin
    Emit(' [');
    ConvertValue;
    Emit(']');
  end;
  Emit(CrLf);
  if ReadByte <> vaList then
  begin
    raise EBinaryForm.Create('Collection-Eintrag erwartet');
  end;
  Inc(FNesting);
  while not EndOfList do
  begin
    ConvertProperty;
  end;
  ReadListEnd;
  Dec(FNesting);
  WriteIndent;
  Emit('end');
end;

procedure TConverter.ConvertCollection;
begin
  ReadByte;
  Emit('<');
  Inc(FNesting);
  while not EndOfList do
  begin
    ConvertCollectionItem;
  end;
  ReadListEnd;
  Dec(FNesting);
  Emit('>');
end;

function TConverter.ReadText(AKind: Byte): string;
begin
  ReadByte;
  case AKind of
    vaLString:
      Result := TEncoding.ANSI.GetString(ReadBytes(ReadInt32));
    vaWString:
      Result := TEncoding.Unicode.GetString(ReadBytes(ReadInt32 * 2));
    vaUTF8String:
      Result := TEncoding.UTF8.GetString(ReadBytes(ReadInt32));
  else
    Result := ReadStr;
  end;
end;

function TConverter.ScalarText(AKind: Byte): string;
begin
  if AKind in [vaInt8, vaInt16, vaInt32, vaInt64] then
  begin
    Exit(IntToStr(ReadInteger));
  end;
  ReadByte;
  case AKind of
    vaExtended:
      Result := FloatText(ReadExtended);
    vaDouble:
      Result := FloatText(ReadDouble);
    vaSingle:
      Result := FloatText(ReadSingle) + 's';
    vaCurrency:
      Result := FloatText(ReadInt64 / 10000) + 'c';
    vaDate:
      Result := FloatText(ReadDouble) + 'd';
    vaIdent:
      Result := ReadStr;
    vaFalse:
      Result := 'False';
    vaTrue:
      Result := 'True';
    vaNil:
      Result := 'nil';
    vaNull:
      Result := 'Null';
  else
    raise EBinaryForm.CreateFmt('Unbekannter Werttyp %d', [AKind]);
  end;
end;

procedure TConverter.ConvertValue;
var
  mKind: Byte;
begin
  mKind := NextByte;
  case mKind of
    vaList:
      ConvertList;
    vaBinary:
      ConvertBinary;
    vaSet:
      ConvertSet;
    vaCollection:
      ConvertCollection;
    vaString, vaLString, vaWString, vaUTF8String:
      WriteString(ReadText(mKind));
  else
    Emit(ScalarText(mKind));
  end;
end;

procedure TConverter.ConvertProperty;
begin
  WriteIndent;
  Emit(ReadStr + ' = ');
  ConvertValue;
  Emit(CrLf);
end;

procedure TConverter.ConvertObject;
var
  Flags: Byte;
  Position: Int64;
  ClassName, ObjectName: string;
begin
  Flags := 0;
  Position := 0;
  if (NextByte and $F0) = $F0 then
  begin
    Flags := ReadByte and $0F;
    if (Flags and ffChildPos) <> 0 then
    begin
      Position := ReadInteger;
    end;
  end;
  ClassName := ReadStr;
  ObjectName := ReadStr;
  WriteIndent;
  if (Flags and ffInherited) <> 0 then
  begin
    Emit('inherited ');
  end
  else if (Flags and ffInline) <> 0 then
  begin
    Emit('inline ');
  end
  else
  begin
    Emit('object ');
  end;
  if ObjectName <> '' then
  begin
    Emit(ObjectName + ': ');
  end;
  Emit(ClassName);
  if (Flags and ffChildPos) <> 0 then
  begin
    Emit(' [' + IntToStr(Position) + ']');
  end;
  Emit(CrLf);
  Inc(FNesting);
  while not EndOfList do
  begin
    ConvertProperty;
  end;
  ReadListEnd;
  while not EndOfList do
  begin
    ConvertObject;
  end;
  ReadListEnd;
  Dec(FNesting);
  WriteIndent;
  Emit('end' + CrLf);
end;

function TConverter.Run: string;
begin
  if (ReadByte <> Ord('T')) or (ReadByte <> Ord('P')) or (ReadByte <> Ord('F')) or (ReadByte <> Ord('0')) then
  begin
    raise EBinaryForm.Create('Signatur TPF0 fehlt');
  end;
  ConvertObject;
  Result := FOut.ToString;
end;

{ TDfmBinary }

class function TDfmBinary.IsBinary(const ABytes: TBytes): Boolean;
begin
  Result := ((Length(ABytes) >= 4) and (ABytes[0] = Ord('T')) and (ABytes[1] = Ord('P')) and
    (ABytes[2] = Ord('F')) and (ABytes[3] = Ord('0'))) or
    ((Length(ABytes) >= 3) and (ABytes[0] = $FF) and (ABytes[1] = $0A) and (ABytes[2] = $00));
end;

class function TDfmBinary.ToText(const ABytes: TBytes; out AText: string): Boolean;
var
  Start: Integer;
  Converter: TConverter;
begin
  AText := '';
  if not IsBinary(ABytes) then
  begin
    Exit(False);
  end;
  Start := 0;
  if ABytes[0] = $FF then
  begin
    // Ressourcen-Kopf: FF 0A 00, Name mit Null-Ende, 2 Byte Flags, 4 Byte Größe.
    Start := 3;
    while (Start < Length(ABytes)) and (ABytes[Start] <> 0) do
    begin
      Inc(Start);
    end;
    Inc(Start, 1 + 2 + 4);
  end;
  Converter := TConverter.Create(ABytes, Start);
  try
    try
      AText := Converter.Run;
      Result := True;
    except
      on EBinaryForm do
        Result := False;
    end;
  finally
    Converter.Free;
  end;
end;

/// <summary>Byte zu ACode in Windows-1252; 0, wenn das Zeichen dort fehlt.</summary>
function Cp1252Byte(ACode: Integer): Byte;
var
  mHigh: Integer;
begin
  if (ACode < $80) or ((ACode >= $A0) and (ACode <= $FF)) then
  begin
    Exit(ACode);
  end;
  for mHigh := $80 to $9F do
  begin
    if Cp1252High[mHigh] = ACode then
    begin
      Exit(mHigh);
    end;
  end;
  Result := 0;
end;

/// <summary>Bytes zum Text, der als Windows-1252 dekodiert wurde; False bei fremden Zeichen.</summary>
function Cp1252Bytes(const AText: string; out ABytes: TBytes): Boolean;
var
  mIndex: Integer;
begin
  SetLength(ABytes, Length(AText));
  for mIndex := 1 to Length(AText) do
  begin
    ABytes[mIndex - 1] := Cp1252Byte(Ord(AText[mIndex]));
    if (ABytes[mIndex - 1] = 0) and (AText[mIndex] <> #0) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

class function TDfmBinary.UnderVersionControl(const AFileName: string): Boolean;
var
  Folder, Parent: string;
begin
  Folder := ExtractFileDir(ExpandFileName(AFileName));
  while Folder <> '' do
  begin
    if DirectoryExists(TPath.Combine(Folder, '.git')) or FileExists(TPath.Combine(Folder, '.git')) or
      DirectoryExists(TPath.Combine(Folder, '.svn')) or DirectoryExists(TPath.Combine(Folder, '.hg')) then
    begin
      Exit(True);
    end;
    Parent := ExtractFileDir(Folder);
    if Parent = Folder then
    begin
      Break;
    end;
    Folder := Parent;
  end;
  Result := False;
end;

class function TDfmBinary.ConvertFile(const AFileName: string; out ABackup: string): Boolean;
var
  Bytes: TBytes;
  Text: string;
begin
  ABackup := '';
  if not FileExists(AFileName) then
  begin
    Exit(False);
  end;
  Bytes := TFile.ReadAllBytes(AFileName);
  if not ToText(Bytes, Text) then
  begin
    Exit(False);
  end;
  if not UnderVersionControl(AFileName) then
  begin
    ABackup := AFileName + '.bak';
    TFile.WriteAllBytes(ABackup, Bytes);
  end;
  // Strings stehen mit #nnn im Text; UTF-8 ohne BOM betrifft nur Bezeichner außerhalb von ASCII.
  TFile.WriteAllBytes(AFileName, TEncoding.UTF8.GetBytes(Text));
  Result := True;
end;

class function TDfmBinary.FromDecodedText(const AText: string; out AFormText: string): Boolean;
var
  Bytes: TBytes;
begin
  // Erst als Windows-1252 (ungültiges UTF-8), dann als UTF-8 zurückwandeln.
  Result := Cp1252Bytes(AText, Bytes) and ToText(Bytes, AFormText);
  if not Result then
  begin
    Result := ToText(TEncoding.UTF8.GetBytes(AText), AFormText);
  end;
end;

end.
