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
    Utf8CodePage = 65001;
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
  SingleByteCodePages: array[0..33] of Integer = (437, 737, 775, 850, 852, 855, 857, 858, 860, 861, 862, 863, 864,
    865, 866, 869, 874, 1250, 1251, 1252, 1253, 1254, 1255, 1256, 1257, 1258, 20866, 21866, 28591, 28592, 28595,
    28597, 28605, 28603);

  // Zeichen 0x80..0x9F in Windows-1252; nicht belegte Werte bleiben gleich.
  Cp1252High: array[$80..$9F] of Word = (
    $20AC, $0081, $201A, $0192, $201E, $2026, $2020, $2021,
    $02C6, $2030, $0160, $2039, $0152, $008D, $017D, $008F,
    $0090, $2018, $2019, $201C, $201D, $2022, $2013, $2014,
    $02DC, $2122, $0161, $203A, $0153, $009D, $017E, $0178);

{ TTextEncodingProbe }

class function TTextEncodingProbe.HasPrefix(const ABytes: TBytes; const APrefix: array of Byte): Boolean;
var
  Index: Integer;
begin
  if Length(ABytes) < Length(APrefix) then
    Exit(False);
  for Index := 0 to High(APrefix) do
    if ABytes[Index] <> APrefix[Index] then
      Exit(False);
  Result := True;
end;

class function TTextEncodingProbe.BomOf(const ABytes: TBytes): TTextBom;
begin
  if HasPrefix(ABytes, [$EF, $BB, $BF]) then
    Result := TTextBom.Utf8
  else if HasPrefix(ABytes, [$FF, $FE]) then
    Result := TTextBom.Utf16LE
  else if HasPrefix(ABytes, [$FE, $FF]) then
    Result := TTextBom.Utf16BE
  else
    Result := TTextBom.None;
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

class function TTextEncodingProbe.IsValidUtf8(const ABytes: TBytes; AStart: Integer;
  out AHasNonAscii: Boolean): Boolean;
var
  Index, Count, Next: Integer;
  Lead: Byte;
  CodePoint: Cardinal;
begin
  AHasNonAscii := False;
  Index := AStart;
  while Index < Length(ABytes) do
  begin
    Lead := ABytes[Index];
    if Lead < $80 then
    begin
      Inc(Index);
      Continue;
    end;
    AHasNonAscii := True;
    if (Lead >= $C2) and (Lead <= $DF) then
    begin
      Count := 1;
      CodePoint := Lead and $1F;
    end
    else if (Lead >= $E0) and (Lead <= $EF) then
    begin
      Count := 2;
      CodePoint := Lead and $0F;
    end
    else if (Lead >= $F0) and (Lead <= $F4) then
    begin
      Count := 3;
      CodePoint := Lead and $07;
    end
    else
      Exit(False);
    if Index + Count > High(ABytes) then
      Exit(False);
    for Next := Index + 1 to Index + Count do
    begin
      if (ABytes[Next] and $C0) <> $80 then
        Exit(False);
      CodePoint := (CodePoint shl 6) or (ABytes[Next] and $3F);
    end;
    // Überlange Formen, Surrogate und Werte über U+10FFFF sind kein gültiges UTF-8.
    if ((Count = 2) and (CodePoint < $800)) or ((Count = 3) and (CodePoint < $10000)) or
      (CodePoint > $10FFFF) or ((CodePoint >= $D800) and (CodePoint <= $DFFF)) then
      Exit(False);
    Inc(Index, Count + 1);
  end;
  Result := True;
end;

class function TTextEncodingProbe.IsValidUtf8(const ABytes: TBytes; AStart: Integer): Boolean;
var
  HasNonAscii: Boolean;
begin
  Result := IsValidUtf8(ABytes, AStart, HasNonAscii);
end;

class function TTextEncodingProbe.IsAscii(const ABytes: TBytes): Boolean;
var
  Value: Byte;
begin
  for Value in ABytes do
    if Value >= $80 then
      Exit(False);
  Result := True;
end;

class function TTextEncodingProbe.IsBinaryForm(const ABytes: TBytes): Boolean;
begin
  Result := HasPrefix(ABytes, [Ord('T'), Ord('P'), Ord('F'), Ord('0')]) or HasPrefix(ABytes, [$FF, $0A, $00]);
end;

class function TTextEncodingProbe.IsSingleByteCodePage(ACodePage: Integer): Boolean;
var
  Known: Integer;
begin
  for Known in SingleByteCodePages do
    if Known = ACodePage then
      Exit(True);
  Result := False;
end;

class function TTextEncodingProbe.ParseCodePage(const AText: string; out ACodePage: Integer): Boolean;
var
  Text: string;
begin
  Result := False;
  ACodePage := 0;
  Text := LowerCase(Trim(AText));
  if (Text = 'utf-8') or (Text = 'utf8') then
  begin
    ACodePage := Utf8CodePage;
    Exit(True);
  end;
  if Copy(Text, 1, 8) = 'windows-' then
    Delete(Text, 1, 8)
  else if Copy(Text, 1, 2) = 'cp' then
    Delete(Text, 1, 2);
  if not TryStrToInt(Text, ACodePage) then
  begin
    ACodePage := 0;
    Exit;
  end;
  if (ACodePage = Utf8CodePage) or IsSingleByteCodePage(ACodePage) then
    Exit(True);
  ACodePage := 0;
end;

class function TTextEncodingProbe.DecodeCp1252(const ABytes: TBytes; AStart: Integer): string;
var
  Index: Integer;
  Value: Byte;
begin
  if AStart < 0 then
    AStart := 0;
  if AStart >= Length(ABytes) then
    Exit('');
  SetLength(Result, Length(ABytes) - AStart);
  for Index := AStart to High(ABytes) do
  begin
    Value := ABytes[Index];
    if (Value >= $80) and (Value <= $9F) then
      Result[Index - AStart + 1] := Char(Cp1252High[Value])
    else
      Result[Index - AStart + 1] := Char(Value);
  end;
end;

class function TTextEncodingProbe.EncodeCp1252(const AText: string): TBytes;
var
  Index, High1252: Integer;
  Code: Word;
  Value: Byte;
begin
  Result := nil;
  SetLength(Result, Length(AText));
  for Index := 1 to Length(AText) do
  begin
    Code := Ord(AText[Index]);
    Value := Ord('?');
    if (Code < $80) or ((Code >= $A0) and (Code <= $FF)) then
      Value := Code
    else
      for High1252 := Low(Cp1252High) to High(Cp1252High) do
        if Cp1252High[High1252] = Code then
        begin
          Value := High1252;
          Break;
        end;
    Result[Index - 1] := Value;
  end;
end;

end.
