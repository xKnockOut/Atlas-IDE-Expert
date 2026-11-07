unit Atlas.Text.Encoding;

// Erkennung von Textkodierungen (gemeinsam für Server und Plugin, ADR 0012):
// BOM, strikte UTF-8-Prüfung, Codepage-Angaben aus atlas.json und binäre
// Formulare. Server und Plugin entscheiden damit gleich, ob eine Datei ohne
// BOM UTF-8 oder ANSI ist.
// Das Dekodieren von ANSI bleibt Sache der Seite: Der Server liest
// Windows-1252 über die Tabelle hier (DecodeCp1252), damit das Ergebnis nicht
// vom Rechner abhängt; das Plugin nimmt die Codepage des Systems wie die IDE.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  /// <summary>Byte-Order-Mark am Anfang der Bytes.</summary>
  TTextBom = (None, Utf8, Utf16LE, Utf16BE);
{$SCOPEDENUMS OFF}

  TTextEncodingProbe = class
  public const
    cUtf8CodePage = 65001;
  public
    /// <summary>BOM am Anfang von ABytes; UTF-8 vor UTF-16.</summary>
    class function BomOf(const ABytes: TBytes): TTextBom; static;
    /// <summary>Länge der BOM in Bytes (0, 2 oder 3).</summary>
    class function BomLength(ABom: TTextBom): Integer; static;
    /// <summary>Gültiges UTF-8 ab AStart, strikt: keine überlangen Formen, keine Surrogate, nichts über
    /// U+10FFFF. AHasNonAscii: mindestens ein Byte ab $80.</summary>
    class function IsValidUtf8(const ABytes: TBytes; AStart: Integer; out AHasNonAscii: Boolean): Boolean;
      overload; static;
    class function IsValidUtf8(const ABytes: TBytes; AStart: Integer): Boolean; overload; static;
    /// <summary>Nur 7-Bit-Zeichen.</summary>
    class function IsAscii(const ABytes: TBytes): Boolean; static;
    class function HasPrefix(const ABytes: TBytes; const APrefix: array of Byte): Boolean; static;
    /// <summary>Binär gespeichertes Formular (TPF0, auch mit Ressourcenkopf $FF $0A $00).</summary>
    class function IsBinaryForm(const ABytes: TBytes): Boolean; static;
    /// <summary>"utf-8"/"utf8"/"65001" → 65001; "1250"/"cp1250"/"windows-1250" → 1250, sofern die
    /// Codepage ein Byte je Zeichen hat und bekannt ist. False sonst (ACodePage = 0).</summary>
    class function ParseCodePage(const AText: string; out ACodePage: Integer): Boolean; static;
    /// <summary>Bekannte Codepage mit einem Byte je Zeichen, als Vorgabe erlaubt.</summary>
    class function IsSingleByteCodePage(ACodePage: Integer): Boolean; static;
    /// <summary>Windows-1252 ab AStart ohne Systemabhängigkeit.</summary>
    class function DecodeCp1252(const ABytes: TBytes; AStart: Integer): string; static;
    /// <summary>Windows-1252; unbekannte Zeichen werden zu '?'.</summary>
    class function EncodeCp1252(const AText: string): TBytes; static;
  end;

implementation

const
  /// <summary>Codepages mit einem Byte je Zeichen, die als Vorgabe erlaubt sind.</summary>
  cSingleByteCodePages: array[0..33] of Integer = (437, 737, 775, 850, 852, 855, 857, 858, 860, 861, 862, 863, 864,
    865, 866, 869, 874, 1250, 1251, 1252, 1253, 1254, 1255, 1256, 1257, 1258, 20866, 21866, 28591, 28592, 28595,
    28597, 28605, 28603);

  // Zeichen 0x80..0x9F in Windows-1252; nicht belegte Werte bleiben gleich.
  cCp1252High: array[$80..$9F] of Word = (
    $20AC, $0081, $201A, $0192, $201E, $2026, $2020, $2021,
    $02C6, $2030, $0160, $2039, $0152, $008D, $017D, $008F,
    $0090, $2018, $2019, $201C, $201D, $2022, $2013, $2014,
    $02DC, $2122, $0161, $203A, $0153, $009D, $017E, $0178);

{ TTextEncodingProbe }

class function TTextEncodingProbe.HasPrefix(const ABytes: TBytes; const APrefix: array of Byte): Boolean;
var
  mIndex: Integer;
begin
  if Length(ABytes) < Length(APrefix) then
  begin
    Exit(False);
  end;
  for mIndex := 0 to High(APrefix) do
  begin
    if ABytes[mIndex] <> APrefix[mIndex] then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

class function TTextEncodingProbe.BomOf(const ABytes: TBytes): TTextBom;
begin
  if HasPrefix(ABytes, [$EF, $BB, $BF]) then
  begin
    Result := TTextBom.Utf8;
  end
  else if HasPrefix(ABytes, [$FF, $FE]) then
  begin
    Result := TTextBom.Utf16LE;
  end
  else if HasPrefix(ABytes, [$FE, $FF]) then
  begin
    Result := TTextBom.Utf16BE;
  end
  else
  begin
    Result := TTextBom.None;
  end;
end;

class function TTextEncodingProbe.BomLength(ABom: TTextBom): Integer;
begin
  case ABom of
    TTextBom.Utf8:
      Result := 3;
    TTextBom.Utf16LE, TTextBom.Utf16BE:
      Result := 2;
  else
    Result := 0;
  end;
end;

// Leitbyte einer Mehrbytefolge: Zahl der Folgebytes und Startwert; False bei ungültigem Leitbyte.
function Utf8Lead(ALead: Byte; out ACount: Integer; out ACodePoint: Cardinal): Boolean;
begin
  Result := True;
  case ALead of
    $C2..$DF:
      begin
        ACount := 1;
        ACodePoint := ALead and $1F;
      end;
    $E0..$EF:
      begin
        ACount := 2;
        ACodePoint := ALead and $0F;
      end;
    $F0..$F4:
      begin
        ACount := 3;
        ACodePoint := ALead and $07;
      end;
  else
    ACount := 0;
    ACodePoint := 0;
    Result := False;
  end;
end;

// Überlange Form: Der Wert hätte in weniger Bytes gepasst.
function IsOverlong(ACount: Integer; ACodePoint: Cardinal): Boolean;
begin
  Result := ((ACount = 2) and (ACodePoint < $800)) or ((ACount = 3) and (ACodePoint < $10000));
end;

// Surrogate und Werte über U+10FFFF sind kein gültiges UTF-8.
function IsAllowedCodePoint(ACount: Integer; ACodePoint: Cardinal): Boolean;
begin
  Result := not IsOverlong(ACount, ACodePoint) and (ACodePoint <= $10FFFF) and
    not ((ACodePoint >= $D800) and (ACodePoint <= $DFFF));
end;

// Gültige Mehrbytefolge ab AIndex? ACount ist die Zahl der Folgebytes.
function IsUtf8Sequence(const ABytes: TBytes; AIndex: Integer; out ACount: Integer): Boolean;
var
  mNext: Integer;
  mCodePoint: Cardinal;
begin
  if not Utf8Lead(ABytes[AIndex], ACount, mCodePoint) or (AIndex + ACount > High(ABytes)) then
  begin
    Exit(False);
  end;
  for mNext := AIndex + 1 to AIndex + ACount do
  begin
    if (ABytes[mNext] and $C0) <> $80 then
    begin
      Exit(False);
    end;
    mCodePoint := (mCodePoint shl 6) or (ABytes[mNext] and $3F);
  end;
  Result := IsAllowedCodePoint(ACount, mCodePoint);
end;

class function TTextEncodingProbe.IsValidUtf8(const ABytes: TBytes; AStart: Integer;
  out AHasNonAscii: Boolean): Boolean;
var
  mIndex, mCount: Integer;
begin
  AHasNonAscii := False;
  mIndex := AStart;
  while mIndex < Length(ABytes) do
  begin
    if ABytes[mIndex] < $80 then
    begin
      Inc(mIndex);
      Continue;
    end;
    AHasNonAscii := True;
    if not IsUtf8Sequence(ABytes, mIndex, mCount) then
    begin
      Exit(False);
    end;
    Inc(mIndex, mCount + 1);
  end;
  Result := True;
end;

class function TTextEncodingProbe.IsValidUtf8(const ABytes: TBytes; AStart: Integer): Boolean;
var
  mHasNonAscii: Boolean;
begin
  Result := IsValidUtf8(ABytes, AStart, mHasNonAscii);
end;

class function TTextEncodingProbe.IsAscii(const ABytes: TBytes): Boolean;
var
  mValue: Byte;
begin
  for mValue in ABytes do
  begin
    if mValue >= $80 then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

class function TTextEncodingProbe.IsBinaryForm(const ABytes: TBytes): Boolean;
begin
  Result := HasPrefix(ABytes, [Ord('T'), Ord('P'), Ord('F'), Ord('0')]) or HasPrefix(ABytes, [$FF, $0A, $00]);
end;

class function TTextEncodingProbe.IsSingleByteCodePage(ACodePage: Integer): Boolean;
var
  mKnown: Integer;
begin
  for mKnown in cSingleByteCodePages do
  begin
    if mKnown = ACodePage then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TTextEncodingProbe.ParseCodePage(const AText: string; out ACodePage: Integer): Boolean;
var
  mText: string;
begin
  Result := False;
  ACodePage := 0;
  mText := LowerCase(Trim(AText));
  if (mText = 'utf-8') or (mText = 'utf8') then
  begin
    ACodePage := cUtf8CodePage;
    Exit(True);
  end;
  if Copy(mText, 1, 8) = 'windows-' then
  begin
    Delete(mText, 1, 8);
  end
  else if Copy(mText, 1, 2) = 'cp' then
  begin
    Delete(mText, 1, 2);
  end;
  if not TryStrToInt(mText, ACodePage) then
  begin
    ACodePage := 0;
    Exit;
  end;
  if (ACodePage = cUtf8CodePage) or IsSingleByteCodePage(ACodePage) then
  begin
    Exit(True);
  end;
  ACodePage := 0;
end;

class function TTextEncodingProbe.DecodeCp1252(const ABytes: TBytes; AStart: Integer): string;
var
  mIndex: Integer;
  mValue: Byte;
begin
  if AStart < 0 then
  begin
    AStart := 0;
  end;
  if AStart >= Length(ABytes) then
  begin
    Exit('');
  end;
  SetLength(Result, Length(ABytes) - AStart);
  for mIndex := AStart to High(ABytes) do
  begin
    mValue := ABytes[mIndex];
    if (mValue >= $80) and (mValue <= $9F) then
    begin
      Result[mIndex - AStart + 1] := Char(cCp1252High[mValue]);
    end
    else
    begin
      Result[mIndex - AStart + 1] := Char(mValue);
    end;
  end;
end;

class function TTextEncodingProbe.EncodeCp1252(const AText: string): TBytes;
var
  mIndex, mHigh1252: Integer;
  mCode: Word;
  mValue: Byte;
begin
  Result := nil;
  SetLength(Result, Length(AText));
  for mIndex := 1 to Length(AText) do
  begin
    mCode := Ord(AText[mIndex]);
    mValue := Ord('?');
    if (mCode < $80) or ((mCode >= $A0) and (mCode <= $FF)) then
    begin
      mValue := mCode;
    end
    else
    begin
      for mHigh1252 := Low(cCp1252High) to High(cCp1252High) do
      begin
        if cCp1252High[mHigh1252] = mCode then
        begin
          mValue := mHigh1252;
          Break;
        end;
      end;
    end;
    Result[mIndex - 1] := mValue;
  end;
end;

end.
