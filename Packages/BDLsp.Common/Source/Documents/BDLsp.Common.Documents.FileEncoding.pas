unit BDLsp.Common.Documents.FileEncoding;

// Kodierung und Zeilenenden von Quelldateien erkennen und beim Schreiben
// erhalten. Ältere Units liegen oft in ANSI (Windows-1252), neuere in UTF-8
// mit oder ohne BOM. Wer eine Datei ändert (Umbenennen, Code-Aktionen,
// Formatierung), liest sie mit Decode und schreibt sie mit Encode und dem
// erkannten TFileFormat zurück; so bleiben Umlaute und CRLF erhalten.
//
// Erkennung: BOM (UTF-8, UTF-16 LE/BE) hat Vorrang. Ohne BOM gilt gültiges
// UTF-8 mit mindestens einem Nicht-ASCII-Zeichen als UTF-8, ungültiges als
// Windows-1252. Reines ASCII ist in beiden gleich; dann gilt die Vorgabe
// (z. B. aus der Projekteinstellung).
//
// Windows-1252 wird über eine eigene Tabelle umgesetzt, damit das Ergebnis
// nicht von der Codepage des Systems abhängt.
//
// TEncodingSurvey zählt die Kodierungen mehrerer Dateien, damit der Server
// auf ein Projekt mit gemischten Kodierungen hinweisen kann.

interface

uses
  System.SysUtils;

type
  TFileEncodingKind = (Utf8, Utf8Bom, Ansi1252, Utf16LE, Utf16BE);

  TLineBreakStyle = (CRLF, LF, CR);

  TFileFormat = record
    Encoding: TFileEncodingKind;
    LineBreak: TLineBreakStyle;
    /// <summary>Die Datei enthält verschiedene Zeilenumbrüche; LineBreak ist der häufigste.</summary>
    MixedLineBreaks: Boolean;
    class function Create(AEncoding: TFileEncodingKind; ALineBreak: TLineBreakStyle): TFileFormat; static;
  end;

  /// <summary>Zählt Kodierungen; reines ASCII passt zu jeder und zählt getrennt.</summary>
  TEncodingSurvey = record
    Ascii: Integer;
    Utf8: Integer;
    Ansi: Integer;
    Utf16: Integer;
    procedure Add(const ABytes: TBytes);
    /// <summary>Windows-1252 neben UTF-8 oder UTF-16.</summary>
    function IsMixed: Boolean;
    /// <summary>Zum Beispiel "3 Dateien in Windows-1252, 12 in UTF-8".</summary>
    function Describe: string;
  end;

  TFileEncoding = class
  public
    /// <summary>Erkennt die Kodierung; ADefault gilt für reines ASCII.</summary>
    class function DetectEncoding(const ABytes: TBytes; ADefault: TFileEncodingKind = TFileEncodingKind.Utf8): TFileEncodingKind; static;
    /// <summary>Häufigster Zeilenumbruch; ohne Umbruch ADefault.</summary>
    class function DetectLineBreak(const AText: string; out AMixed: Boolean;
      ADefault: TLineBreakStyle = TLineBreakStyle.CRLF): TLineBreakStyle; static;
    /// <summary>Liest Bytes als Text und liefert das erkannte Format.</summary>
    class function Decode(const ABytes: TBytes; out AFormat: TFileFormat;
      ADefault: TFileEncodingKind = TFileEncodingKind.Utf8): string; static;
    /// <summary>
    /// Schreibt Text im Format AFormat: alle Zeilenumbrüche werden zu
    /// AFormat.LineBreak, bei Utf8Bom und UTF-16 kommt die BOM davor. Zeichen,
    /// die Windows-1252 nicht kennt, werden zu '?'.
    /// </summary>
    class function Encode(const AText: string; const AFormat: TFileFormat): TBytes; static;
    /// <summary>Ersetzt alle Zeilenumbrüche durch AStyle.</summary>
    class function NormalizeLineBreaks(const AText: string; AStyle: TLineBreakStyle): string; static;
    class function LoadFromFile(const AFileName: string; out AFormat: TFileFormat;
      ADefault: TFileEncodingKind = TFileEncodingKind.Utf8): string; static;
    class procedure SaveToFile(const AFileName, AText: string; const AFormat: TFileFormat); static;
  end;

implementation

uses
  System.Classes;

const
  // Zeichen 0x80..0x9F in Windows-1252; nicht belegte Werte bleiben gleich.
  Cp1252High: array[$80..$9F] of Word = (
    $20AC, $0081, $201A, $0192, $201E, $2026, $2020, $2021,
    $02C6, $2030, $0160, $2039, $0152, $008D, $017D, $008F,
    $0090, $2018, $2019, $201C, $201D, $2022, $2013, $2014,
    $02DC, $2122, $0161, $203A, $0153, $009D, $017E, $0178);

{ TFileFormat }

class function TFileFormat.Create(AEncoding: TFileEncodingKind; ALineBreak: TLineBreakStyle): TFileFormat;
begin
  Result.Encoding := AEncoding;
  Result.LineBreak := ALineBreak;
  Result.MixedLineBreaks := False;
end;

// Prüft strikt: keine überlangen Formen, keine Surrogate, höchstens U+10FFFF.
function CheckUtf8(const ABytes: TBytes; AStart: Integer; out AHasNonAscii: Boolean): Boolean;
var
  Index: Integer;
  Lead: Byte;
  Count: Integer;
  CodePoint: Cardinal;
  Next: Integer;
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
    if ((Count = 2) and (CodePoint < $800)) or ((Count = 3) and (CodePoint < $10000)) or
      (CodePoint > $10FFFF) or ((CodePoint >= $D800) and (CodePoint <= $DFFF)) then
      Exit(False);
    Inc(Index, Count + 1);
  end;
  Result := True;
end;

function HasPrefix(const ABytes: TBytes; const APrefix: array of Byte): Boolean;
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

{ TEncodingSurvey }

procedure TEncodingSurvey.Add(const ABytes: TBytes);
var
  HasNonAscii: Boolean;
begin
  if HasPrefix(ABytes, [$EF, $BB, $BF]) then
    Inc(Utf8)
  else if HasPrefix(ABytes, [$FF, $FE]) or HasPrefix(ABytes, [$FE, $FF]) then
    Inc(Utf16)
  else if not CheckUtf8(ABytes, 0, HasNonAscii) then
    Inc(Ansi)
  else if HasNonAscii then
    Inc(Utf8)
  else
    Inc(Ascii);
end;

function TEncodingSurvey.IsMixed: Boolean;
begin
  Result := (Ansi > 0) and (Utf8 + Utf16 > 0);
end;

function TEncodingSurvey.Describe: string;

  procedure Append(ACount: Integer; const AName: string);
  begin
    if ACount = 0 then
      Exit;
    if Result = '' then
    begin
      if ACount = 1 then
        Result := '1 Datei in ' + AName
      else
        Result := Format('%d Dateien in %s', [ACount, AName]);
    end
    else
      Result := Result + Format(', %d in %s', [ACount, AName]);
  end;

begin
  Result := '';
  Append(Ansi, 'Windows-1252');
  Append(Utf8, 'UTF-8');
  Append(Utf16, 'UTF-16');
  Append(Ascii, 'reinem ASCII');
end;

function DecodeCp1252(const ABytes: TBytes): string;
var
  Index: Integer;
  Value: Byte;
begin
  SetLength(Result, Length(ABytes));
  for Index := 0 to High(ABytes) do
  begin
    Value := ABytes[Index];
    if (Value >= $80) and (Value <= $9F) then
      Result[Index + 1] := Char(Cp1252High[Value])
    else
      Result[Index + 1] := Char(Value);
  end;
end;

function EncodeCp1252(const AText: string): TBytes;
var
  Index: Integer;
  Code: Word;
  High1252: Integer;
  Value: Byte;
begin
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

function DecodeUtf16(const ABytes: TBytes; AStart: Integer; ABigEndian: Boolean): string;
var
  Count: Integer;
  Index: Integer;
  First, Second: Byte;
begin
  Count := (Length(ABytes) - AStart) div 2;
  SetLength(Result, Count);
  for Index := 0 to Count - 1 do
  begin
    First := ABytes[AStart + 2 * Index];
    Second := ABytes[AStart + 2 * Index + 1];
    if ABigEndian then
      Result[Index + 1] := Char((First shl 8) or Second)
    else
      Result[Index + 1] := Char((Second shl 8) or First);
  end;
end;

function EncodeUtf16(const AText: string; ABigEndian: Boolean): TBytes;
var
  Index: Integer;
  Code: Word;
begin
  SetLength(Result, 2 + 2 * Length(AText));
  if ABigEndian then
  begin
    Result[0] := $FE;
    Result[1] := $FF;
  end
  else
  begin
    Result[0] := $FF;
    Result[1] := $FE;
  end;
  for Index := 1 to Length(AText) do
  begin
    Code := Ord(AText[Index]);
    if ABigEndian then
    begin
      Result[2 * Index] := Code shr 8;
      Result[2 * Index + 1] := Code and $FF;
    end
    else
    begin
      Result[2 * Index] := Code and $FF;
      Result[2 * Index + 1] := Code shr 8;
    end;
  end;
end;

{ TFileEncoding }

class function TFileEncoding.DetectEncoding(const ABytes: TBytes; ADefault: TFileEncodingKind): TFileEncodingKind;
var
  HasNonAscii: Boolean;
begin
  if HasPrefix(ABytes, [$EF, $BB, $BF]) then
    Exit(TFileEncodingKind.Utf8Bom);
  if HasPrefix(ABytes, [$FF, $FE]) then
    Exit(TFileEncodingKind.Utf16LE);
  if HasPrefix(ABytes, [$FE, $FF]) then
    Exit(TFileEncodingKind.Utf16BE);
  if not CheckUtf8(ABytes, 0, HasNonAscii) then
    Exit(TFileEncodingKind.Ansi1252);
  if HasNonAscii then
    Exit(TFileEncodingKind.Utf8);
  // Reines ASCII: Utf8Bom als Vorgabe heißt nur „UTF-8“, eine BOM fehlt ja.
  if ADefault = TFileEncodingKind.Utf8Bom then
    Result := TFileEncodingKind.Utf8
  else if ADefault in [TFileEncodingKind.Utf16LE, TFileEncodingKind.Utf16BE] then
    Result := TFileEncodingKind.Utf8
  else
    Result := ADefault;
end;

class function TFileEncoding.DetectLineBreak(const AText: string; out AMixed: Boolean;
  ADefault: TLineBreakStyle): TLineBreakStyle;
var
  Counts: array[TLineBreakStyle] of Integer;
  Index: Integer;
  Style: TLineBreakStyle;
  Kinds: Integer;
begin
  Counts[TLineBreakStyle.CRLF] := 0;
  Counts[TLineBreakStyle.LF] := 0;
  Counts[TLineBreakStyle.CR] := 0;
  Index := 1;
  while Index <= Length(AText) do
  begin
    if AText[Index] = #13 then
    begin
      if (Index < Length(AText)) and (AText[Index + 1] = #10) then
      begin
        Inc(Counts[TLineBreakStyle.CRLF]);
        Inc(Index);
      end
      else
        Inc(Counts[TLineBreakStyle.CR]);
    end
    else if AText[Index] = #10 then
      Inc(Counts[TLineBreakStyle.LF]);
    Inc(Index);
  end;
  Result := ADefault;
  Kinds := 0;
  for Style := Low(TLineBreakStyle) to High(TLineBreakStyle) do
    if Counts[Style] > 0 then
    begin
      Inc(Kinds);
      if (Counts[Result] < Counts[Style]) or (Counts[Result] = 0) then
        Result := Style;
    end;
  AMixed := Kinds > 1;
end;

class function TFileEncoding.Decode(const ABytes: TBytes; out AFormat: TFileFormat;
  ADefault: TFileEncodingKind): string;
var
  Mixed: Boolean;
begin
  AFormat.Encoding := DetectEncoding(ABytes, ADefault);
  case AFormat.Encoding of
    TFileEncodingKind.Utf8Bom:
      Result := TEncoding.UTF8.GetString(ABytes, 3, Length(ABytes) - 3);
    TFileEncodingKind.Utf8:
      Result := TEncoding.UTF8.GetString(ABytes);
    TFileEncodingKind.Utf16LE:
      Result := DecodeUtf16(ABytes, 2, False);
    TFileEncodingKind.Utf16BE:
      Result := DecodeUtf16(ABytes, 2, True);
  else
    Result := DecodeCp1252(ABytes);
  end;
  AFormat.LineBreak := DetectLineBreak(Result, Mixed);
  AFormat.MixedLineBreaks := Mixed;
end;

class function TFileEncoding.NormalizeLineBreaks(const AText: string; AStyle: TLineBreakStyle): string;
var
  Builder: TStringBuilder;
  Index: Integer;
  LineBreak: string;
begin
  case AStyle of
    TLineBreakStyle.LF: LineBreak := #10;
    TLineBreakStyle.CR: LineBreak := #13;
  else
    LineBreak := #13#10;
  end;
  Builder := TStringBuilder.Create(Length(AText));
  try
    Index := 1;
    while Index <= Length(AText) do
    begin
      if AText[Index] = #13 then
      begin
        Builder.Append(LineBreak);
        if (Index < Length(AText)) and (AText[Index + 1] = #10) then
          Inc(Index);
      end
      else if AText[Index] = #10 then
        Builder.Append(LineBreak)
      else
        Builder.Append(AText[Index]);
      Inc(Index);
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TFileEncoding.Encode(const AText: string; const AFormat: TFileFormat): TBytes;
var
  Text: string;
  Body: TBytes;
begin
  Text := NormalizeLineBreaks(AText, AFormat.LineBreak);
  case AFormat.Encoding of
    TFileEncodingKind.Utf8:
      Result := TEncoding.UTF8.GetBytes(Text);
    TFileEncodingKind.Utf8Bom:
      begin
        Body := TEncoding.UTF8.GetBytes(Text);
        SetLength(Result, 3 + Length(Body));
        Result[0] := $EF;
        Result[1] := $BB;
        Result[2] := $BF;
        if Length(Body) > 0 then
          Move(Body[0], Result[3], Length(Body));
      end;
    TFileEncodingKind.Utf16LE:
      Result := EncodeUtf16(Text, False);
    TFileEncodingKind.Utf16BE:
      Result := EncodeUtf16(Text, True);
  else
    Result := EncodeCp1252(Text);
  end;
end;

class function TFileEncoding.LoadFromFile(const AFileName: string; out AFormat: TFileFormat;
  ADefault: TFileEncodingKind): string;
var
  Stream: TFileStream;
  Bytes: TBytes;
begin
  Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Bytes, Stream.Size);
    if Length(Bytes) > 0 then
      Stream.ReadBuffer(Bytes[0], Length(Bytes));
  finally
    Stream.Free;
  end;
  Result := Decode(Bytes, AFormat, ADefault);
end;

class procedure TFileEncoding.SaveToFile(const AFileName, AText: string; const AFormat: TFileFormat);
var
  Stream: TFileStream;
  Bytes: TBytes;
begin
  Bytes := Encode(AText, AFormat);
  Stream := TFileStream.Create(AFileName, fmCreate);
  try
    if Length(Bytes) > 0 then
      Stream.WriteBuffer(Bytes[0], Length(Bytes));
  finally
    Stream.Free;
  end;
end;

end.
