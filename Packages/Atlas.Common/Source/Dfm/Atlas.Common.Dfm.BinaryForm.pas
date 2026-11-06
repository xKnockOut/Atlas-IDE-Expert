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
    cLineLength = 64;
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
  System.IOUtils,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TBinaryFormText = (SignatureTPF0Missing, UnexpectedEndOfFile, UnknownValueType, IntegerExpected, EndOfListExpected,
    CollectionItemExpected);

const
  cTexts: array[TBinaryFormText] of TAtlasText = (
    (De: 'Signatur TPF0 fehlt'; En: 'Signature TPF0 missing'),
    (De: 'Unerwartetes Dateiende'; En: 'Unexpected end of file'),
    (De: 'Unbekannter Werttyp %d'; En: 'Unknown value type %d'),
    (De: 'Ganzzahl erwartet'; En: 'Integer expected'),
    (De: 'Listenende erwartet'; En: 'End of list expected'),
    (De: 'Collection-Eintrag erwartet'; En: 'Collection item expected'));

{$SCOPEDENUMS OFF}

const
  cVaNull = 0;
  cVaList = 1;
  cVaInt8 = 2;
  cVaInt16 = 3;
  cVaInt32 = 4;
  cVaExtended = 5;
  cVaString = 6;
  cVaIdent = 7;
  cVaFalse = 8;
  cVaTrue = 9;
  cVaBinary = 10;
  cVaSet = 11;
  cVaLString = 12;
  cVaNil = 13;
  cVaCollection = 14;
  cVaSingle = 15;
  cVaCurrency = 16;
  cVaDate = 17;
  cVaWString = 18;
  cVaInt64 = 19;
  cVaUTF8String = 20;
  cVaDouble = 21;

  cFfInherited = 1;
  cFfChildPos = 2;
  cFfInline = 4;

  cCrLf = #13#10;

  cCp1252High: array[$80..$9F] of Word = (
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
  mSettings: TFormatSettings;
begin
  mSettings := TFormatSettings.Create;
  mSettings.DecimalSeparator := '.';
  Result := FloatToStr(AValue, mSettings);
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
    raise EBinaryForm.Create(cTexts[TBinaryFormText.UnexpectedEndOfFile].Text);
  end;
  Result := FBytes[FPos];
  Inc(FPos);
end;

function TConverter.NextByte: Byte;
begin
  if FPos >= Length(FBytes) then
  begin
    raise EBinaryForm.Create(cTexts[TBinaryFormText.UnexpectedEndOfFile].Text);
  end;
  Result := FBytes[FPos];
end;

function TConverter.ReadBytes(ACount: Integer): TBytes;
begin
  if (ACount < 0) or (FPos + ACount > Length(FBytes)) then
  begin
    raise EBinaryForm.Create(cTexts[TBinaryFormText.UnexpectedEndOfFile].Text);
  end;
  Result := Copy(FBytes, FPos, ACount);
  Inc(FPos, ACount);
end;

function TConverter.ReadInt16: SmallInt;
var
  mBytes: TBytes;
begin
  mBytes := ReadBytes(2);
  Result := SmallInt(mBytes[0] or (mBytes[1] shl 8));
end;

function TConverter.ReadInt32: Integer;
var
  mBytes: TBytes;
begin
  mBytes := ReadBytes(4);
  Result := Integer(Cardinal(mBytes[0]) or (Cardinal(mBytes[1]) shl 8) or (Cardinal(mBytes[2]) shl 16) or
    (Cardinal(mBytes[3]) shl 24));
end;

function TConverter.ReadInt64: Int64;
var
  mLow, mHigh: Cardinal;
begin
  mLow := Cardinal(ReadInt32);
  mHigh := Cardinal(ReadInt32);
  Result := Int64(UInt64(mLow) or (UInt64(mHigh) shl 32));
end;

function TConverter.ReadDouble: Double;
var
  mBits: Int64;
begin
  mBits := ReadInt64;
  Move(mBits, Result, SizeOf(Result));
end;

function TConverter.ReadSingle: Single;
var
  mBits: Integer;
begin
  mBits := ReadInt32;
  Move(mBits, Result, SizeOf(Result));
end;

function TConverter.ReadExtended: Double;
var
  mMantissa: UInt64;
  mExponent: Integer;
  mNegative: Boolean;
  mBytes: TBytes;
  mIndex: Integer;
begin
  // 80-Bit-Extended: 64 Bit Mantisse mit explizitem Eins-Bit, 15 Bit Exponent, Vorzeichen.
  mBytes := ReadBytes(10);
  mMantissa := 0;
  for mIndex := 7 downto 0 do
  begin
    mMantissa := (mMantissa shl 8) or mBytes[mIndex];
  end;
  mExponent := (mBytes[8] or (mBytes[9] shl 8)) and $7FFF;
  mNegative := (mBytes[9] and $80) <> 0;
  if (mMantissa = 0) and (mExponent = 0) then
  begin
    Result := 0;
  end
  else
  begin
    Result := Ldexp(mMantissa, mExponent - 16383 - 63);
  end;
  if mNegative then
  begin
    Result := -Result;
  end;
end;

function TConverter.ReadStr: string;
var
  mCount: Integer;
begin
  mCount := ReadByte;
  Result := TEncoding.UTF8.GetString(ReadBytes(mCount));
end;

function TConverter.ReadInteger: Int64;
begin
  case ReadByte of
    cVaInt8: Result := ShortInt(ReadByte);
    cVaInt16: Result := ReadInt16;
    cVaInt32: Result := ReadInt32;
    cVaInt64: Result := ReadInt64;
  else
    raise EBinaryForm.Create(cTexts[TBinaryFormText.IntegerExpected].Text);
  end;
end;

function TConverter.EndOfList: Boolean;
begin
  Result := NextByte = cVaNull;
end;

procedure TConverter.ReadListEnd;
begin
  if ReadByte <> cVaNull then
  begin
    raise EBinaryForm.Create(cTexts[TBinaryFormText.EndOfListExpected].Text);
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
  Emit(cCrLf);
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
    (Result - ALineStart >= TDfmBinary.cLineLength);
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
    if Length(AText) > TDfmBinary.cLineLength then
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
      if (mIndex - mLineStart >= TDfmBinary.cLineLength) and (mIndex <= Length(AText)) then
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
  cHexDigits = '0123456789ABCDEF';
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
      mLine := mLine + cHexDigits[mBytes[mIndex] shr 4 + 1] + cHexDigits[mBytes[mIndex] and $F + 1];
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
  if NextByte in [cVaInt8, cVaInt16, cVaInt32] then
  begin
    Emit(' [');
    ConvertValue;
    Emit(']');
  end;
  Emit(cCrLf);
  if ReadByte <> cVaList then
  begin
    raise EBinaryForm.Create(cTexts[TBinaryFormText.CollectionItemExpected].Text);
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
    cVaLString:
      Result := TEncoding.ANSI.GetString(ReadBytes(ReadInt32));
    cVaWString:
      Result := TEncoding.Unicode.GetString(ReadBytes(ReadInt32 * 2));
    cVaUTF8String:
      Result := TEncoding.UTF8.GetString(ReadBytes(ReadInt32));
  else
    Result := ReadStr;
  end;
end;

function TConverter.ScalarText(AKind: Byte): string;
begin
  if AKind in [cVaInt8, cVaInt16, cVaInt32, cVaInt64] then
  begin
    Exit(IntToStr(ReadInteger));
  end;
  ReadByte;
  case AKind of
    cVaExtended:
      Result := FloatText(ReadExtended);
    cVaDouble:
      Result := FloatText(ReadDouble);
    cVaSingle:
      Result := FloatText(ReadSingle) + 's';
    cVaCurrency:
      Result := FloatText(ReadInt64 / 10000) + 'c';
    cVaDate:
      Result := FloatText(ReadDouble) + 'd';
    cVaIdent:
      Result := ReadStr;
    cVaFalse:
      Result := 'False';
    cVaTrue:
      Result := 'True';
    cVaNil:
      Result := 'nil';
    cVaNull:
      Result := 'Null';
  else
    raise EBinaryForm.CreateFmt(cTexts[TBinaryFormText.UnknownValueType].Text, [AKind]);
  end;
end;

procedure TConverter.ConvertValue;
var
  mKind: Byte;
begin
  mKind := NextByte;
  case mKind of
    cVaList:
      ConvertList;
    cVaBinary:
      ConvertBinary;
    cVaSet:
      ConvertSet;
    cVaCollection:
      ConvertCollection;
    cVaString, cVaLString, cVaWString, cVaUTF8String:
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
  Emit(cCrLf);
end;

procedure TConverter.ConvertObject;
var
  mFlags: Byte;
  mPosition: Int64;
  mClassName, mObjectName: string;
begin
  mFlags := 0;
  mPosition := 0;
  if (NextByte and $F0) = $F0 then
  begin
    mFlags := ReadByte and $0F;
    if (mFlags and cFfChildPos) <> 0 then
    begin
      mPosition := ReadInteger;
    end;
  end;
  mClassName := ReadStr;
  mObjectName := ReadStr;
  WriteIndent;
  if (mFlags and cFfInherited) <> 0 then
  begin
    Emit('inherited ');
  end
  else if (mFlags and cFfInline) <> 0 then
  begin
    Emit('inline ');
  end
  else
  begin
    Emit('object ');
  end;
  if mObjectName <> '' then
  begin
    Emit(mObjectName + ': ');
  end;
  Emit(mClassName);
  if (mFlags and cFfChildPos) <> 0 then
  begin
    Emit(' [' + IntToStr(mPosition) + ']');
  end;
  Emit(cCrLf);
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
  Emit('end' + cCrLf);
end;

function TConverter.Run: string;
begin
  if (ReadByte <> Ord('T')) or (ReadByte <> Ord('P')) or (ReadByte <> Ord('F')) or (ReadByte <> Ord('0')) then
  begin
    raise EBinaryForm.Create(cTexts[TBinaryFormText.SignatureTPF0Missing].Text);
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
  mStart: Integer;
  mConverter: TConverter;
begin
  AText := '';
  if not IsBinary(ABytes) then
  begin
    Exit(False);
  end;
  mStart := 0;
  if ABytes[0] = $FF then
  begin
    // Ressourcen-Kopf: FF 0A 00, Name mit Null-Ende, 2 Byte Flags, 4 Byte Größe.
    mStart := 3;
    while (mStart < Length(ABytes)) and (ABytes[mStart] <> 0) do
    begin
      Inc(mStart);
    end;
    Inc(mStart, 1 + 2 + 4);
  end;
  mConverter := TConverter.Create(ABytes, mStart);
  try
    try
      AText := mConverter.Run;
      Result := True;
    except
      on EBinaryForm do
        Result := False;
    end;
  finally
    mConverter.Free;
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
    if cCp1252High[mHigh] = ACode then
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
  mFolder, mParent: string;
begin
  mFolder := ExtractFileDir(ExpandFileName(AFileName));
  while mFolder <> '' do
  begin
    if DirectoryExists(TPath.Combine(mFolder, '.git')) or FileExists(TPath.Combine(mFolder, '.git')) or
      DirectoryExists(TPath.Combine(mFolder, '.svn')) or DirectoryExists(TPath.Combine(mFolder, '.hg')) then
    begin
      Exit(True);
    end;
    mParent := ExtractFileDir(mFolder);
    if mParent = mFolder then
    begin
      Break;
    end;
    mFolder := mParent;
  end;
  Result := False;
end;

class function TDfmBinary.ConvertFile(const AFileName: string; out ABackup: string): Boolean;
var
  mBytes: TBytes;
  mText: string;
begin
  ABackup := '';
  if not FileExists(AFileName) then
  begin
    Exit(False);
  end;
  mBytes := TFile.ReadAllBytes(AFileName);
  if not ToText(mBytes, mText) then
  begin
    Exit(False);
  end;
  if not UnderVersionControl(AFileName) then
  begin
    ABackup := AFileName + '.bak';
    TFile.WriteAllBytes(ABackup, mBytes);
  end;
  // Strings stehen mit #nnn im Text; UTF-8 ohne BOM betrifft nur Bezeichner außerhalb von ASCII.
  TFile.WriteAllBytes(AFileName, TEncoding.UTF8.GetBytes(mText));
  Result := True;
end;

class function TDfmBinary.FromDecodedText(const AText: string; out AFormText: string): Boolean;
var
  mBytes: TBytes;
begin
  // Erst als Windows-1252 (ungültiges UTF-8), dann als UTF-8 zurückwandeln.
  Result := Cp1252Bytes(AText, mBytes) and ToText(mBytes, AFormText);
  if not Result then
  begin
    Result := ToText(TEncoding.UTF8.GetBytes(AText), AFormText);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Dfm.BinaryForm', cTexts);

end.
