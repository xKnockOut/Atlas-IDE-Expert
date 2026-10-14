unit Atlas.Core.Files.Format;

// Kodierung und Zeilenende einer Datei (#591, Daten wie #121), ohne Open
// Tools API: Erkennen aus den Bytes auf der Platte, Text für die Zeile
// „Datei“ des Atlas-Statusfelds und Umwandeln in ein anderes Format
// (UTF-8 mit/ohne BOM, ANSI; CRLF/LF).
// Erkennung: BOM zuerst (UTF-8, UTF-16 LE/BE); ohne BOM gültiges UTF-8 als
// UTF-8 ohne BOM (reines ASCII ebenso), sonst ANSI. Zeilenenden: nur CRLF,
// nur LF, nur CR, gemischt oder keine.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  TAtlasFileEncoding = (Utf8, Utf8Bom, Ansi, Utf16LE, Utf16BE);
  TAtlasLineBreak = (None, CRLF, LF, CR, Mixed);
{$SCOPEDENUMS OFF}

  TAtlasFileFormat = record
    Encoding: TAtlasFileEncoding;
    LineBreak: TAtlasLineBreak;
    class function Create(AEncoding: TAtlasFileEncoding; ALineBreak: TAtlasLineBreak): TAtlasFileFormat; static;
    /// <summary>„UTF-8 ohne BOM, LF“.</summary>
    function Text: string;
    function Equals(const AOther: TAtlasFileFormat): Boolean;
  end;

  TAtlasFileFormats = class
  public
    /// <summary>Format der Bytes einer Datei.</summary>
    class function Detect(const ABytes: TBytes): TAtlasFileFormat; static;
    /// <summary>Zeilenenden eines Texts.</summary>
    class function LineBreakOf(const AText: string): TAtlasLineBreak; static;
    /// <summary>True, wenn ABytes ab AStart gültiges UTF-8 sind.</summary>
    class function IsUtf8(const ABytes: TBytes; AStart: Integer): Boolean; static;
    /// <summary>Text der Bytes nach AEncoding, ohne BOM.</summary>
    class function Decode(const ABytes: TBytes; AEncoding: TAtlasFileEncoding): string; static;
    /// <summary>Bytes für AText im Format ATarget: Zeilenenden vereinheitlicht (None, Mixed: unverändert),
    /// BOM nach Kodierung.</summary>
    class function Encode(const AText: string; const ATarget: TAtlasFileFormat): TBytes; static;
    /// <summary>ABytes in ATarget umwandeln; Kodierung und Zeilenenden der Quelle werden erkannt.</summary>
    class function Convert(const ABytes: TBytes; const ATarget: TAtlasFileFormat): TBytes; static;
    /// <summary>True, wenn ABytes schon ATarget entsprechen. Reines ASCII ohne BOM gilt als UTF-8 ohne BOM
    /// und als ANSI; eine Datei ohne Zeilenende passt zu jedem Zeilenende.</summary>
    class function Satisfies(const ABytes: TBytes; const ATarget: TAtlasFileFormat): Boolean; static;
    /// <summary>True, wenn ABytes nur 7-Bit-Zeichen enthalten.</summary>
    class function IsAscii(const ABytes: TBytes): Boolean; static;
    /// <summary>Zeichen von AText, die ANSI (Codepage des Systems) nicht darstellen kann.</summary>
    class function AnsiLosses(const AText: string): Integer; static;
    /// <summary>Zeilenenden auf ABreak vereinheitlichen (CRLF, LF oder CR; sonst unverändert).</summary>
    class function NormalizeLineBreaks(const AText: string; ABreak: TAtlasLineBreak): string; static;
    /// <summary>Wählbare Ziele im Fenster: UTF-8 mit BOM, UTF-8 ohne BOM und ANSI, je mit CRLF und LF.</summary>
    class function Targets: TArray<TAtlasFileFormat>; static;
    class function EncodingText(AEncoding: TAtlasFileEncoding): string; static;
    class function LineBreakText(ALineBreak: TAtlasLineBreak): string; static;
  end;

implementation

{ TAtlasFileFormat }

class function TAtlasFileFormat.Create(AEncoding: TAtlasFileEncoding; ALineBreak: TAtlasLineBreak): TAtlasFileFormat;
begin
  Result.Encoding := AEncoding;
  Result.LineBreak := ALineBreak;
end;

function TAtlasFileFormat.Text: string;
begin
  Result := TAtlasFileFormats.EncodingText(Encoding) + ', ' + TAtlasFileFormats.LineBreakText(LineBreak);
end;

function TAtlasFileFormat.Equals(const AOther: TAtlasFileFormat): Boolean;
begin
  Result := (Encoding = AOther.Encoding) and (LineBreak = AOther.LineBreak);
end;

{ TAtlasFileFormats }

class function TAtlasFileFormats.EncodingText(AEncoding: TAtlasFileEncoding): string;
const
  Names: array[TAtlasFileEncoding] of string = ('UTF-8 ohne BOM', 'UTF-8 mit BOM', 'ANSI', 'UTF-16 LE',
    'UTF-16 BE');
begin
  Result := Names[AEncoding];
end;

class function TAtlasFileFormats.LineBreakText(ALineBreak: TAtlasLineBreak): string;
const
  Names: array[TAtlasLineBreak] of string = ('ohne Zeilenende', 'CRLF', 'LF', 'CR', 'gemischte Zeilenenden');
begin
  Result := Names[ALineBreak];
end;

class function TAtlasFileFormats.IsUtf8(const ABytes: TBytes; AStart: Integer): Boolean;
var
  Index, Follow, Count: Integer;
  Value: Byte;
begin
  Index := AStart;
  while Index < Length(ABytes) do
  begin
    Value := ABytes[Index];
    if Value < $80 then
      Follow := 0
    else if (Value >= $C2) and (Value <= $DF) then
      Follow := 1
    else if (Value >= $E0) and (Value <= $EF) then
      Follow := 2
    else if (Value >= $F0) and (Value <= $F4) then
      Follow := 3
    else
      Exit(False);
    if Index + Follow > High(ABytes) then
      Exit(False);
    for Count := 1 to Follow do
      if (ABytes[Index + Count] and $C0) <> $80 then
        Exit(False);
    Inc(Index, Follow + 1);
  end;
  Result := True;
end;

class function TAtlasFileFormats.LineBreakOf(const AText: string): TAtlasLineBreak;
var
  Index: Integer;
  CRLFs, LFs, CRs: Integer;
begin
  CRLFs := 0;
  LFs := 0;
  CRs := 0;
  Index := 1;
  while Index <= Length(AText) do
  begin
    if AText[Index] = #13 then
    begin
      if (Index < Length(AText)) and (AText[Index + 1] = #10) then
      begin
        Inc(CRLFs);
        Inc(Index);
      end
      else
        Inc(CRs);
    end
    else if AText[Index] = #10 then
      Inc(LFs);
    Inc(Index);
  end;
  if CRLFs + LFs + CRs = 0 then
    Result := TAtlasLineBreak.None
  else if (LFs = 0) and (CRs = 0) then
    Result := TAtlasLineBreak.CRLF
  else if (CRLFs = 0) and (CRs = 0) then
    Result := TAtlasLineBreak.LF
  else if (CRLFs = 0) and (LFs = 0) then
    Result := TAtlasLineBreak.CR
  else
    Result := TAtlasLineBreak.Mixed;
end;

class function TAtlasFileFormats.Detect(const ABytes: TBytes): TAtlasFileFormat;
begin
  if (Length(ABytes) >= 3) and (ABytes[0] = $EF) and (ABytes[1] = $BB) and (ABytes[2] = $BF) then
    Result.Encoding := TAtlasFileEncoding.Utf8Bom
  else if (Length(ABytes) >= 2) and (ABytes[0] = $FF) and (ABytes[1] = $FE) then
    Result.Encoding := TAtlasFileEncoding.Utf16LE
  else if (Length(ABytes) >= 2) and (ABytes[0] = $FE) and (ABytes[1] = $FF) then
    Result.Encoding := TAtlasFileEncoding.Utf16BE
  else if IsUtf8(ABytes, 0) then
    Result.Encoding := TAtlasFileEncoding.Utf8
  else
    Result.Encoding := TAtlasFileEncoding.Ansi;
  Result.LineBreak := LineBreakOf(Decode(ABytes, Result.Encoding));
end;

class function TAtlasFileFormats.Decode(const ABytes: TBytes; AEncoding: TAtlasFileEncoding): string;
begin
  case AEncoding of
    TAtlasFileEncoding.Utf8Bom:
      if Length(ABytes) >= 3 then
        Result := TEncoding.UTF8.GetString(ABytes, 3, Length(ABytes) - 3)
      else
        Result := '';
    TAtlasFileEncoding.Utf16LE:
      if Length(ABytes) >= 2 then
        Result := TEncoding.Unicode.GetString(ABytes, 2, Length(ABytes) - 2)
      else
        Result := '';
    TAtlasFileEncoding.Utf16BE:
      if Length(ABytes) >= 2 then
        Result := TEncoding.BigEndianUnicode.GetString(ABytes, 2, Length(ABytes) - 2)
      else
        Result := '';
    TAtlasFileEncoding.Ansi:
      Result := TEncoding.ANSI.GetString(ABytes);
  else
    Result := TEncoding.UTF8.GetString(ABytes);
  end;
end;

class function TAtlasFileFormats.NormalizeLineBreaks(const AText: string; ABreak: TAtlasLineBreak): string;
var
  Plain: string;
begin
  case ABreak of
    TAtlasLineBreak.CRLF, TAtlasLineBreak.LF, TAtlasLineBreak.CR:
      begin
        Plain := AText.Replace(#13#10, #10).Replace(#13, #10);
        case ABreak of
          TAtlasLineBreak.CRLF:
            Result := Plain.Replace(#10, #13#10);
          TAtlasLineBreak.CR:
            Result := Plain.Replace(#10, #13);
        else
          Result := Plain;
        end;
      end;
  else
    Result := AText;
  end;
end;

class function TAtlasFileFormats.Encode(const AText: string; const ATarget: TAtlasFileFormat): TBytes;
var
  Text: string;
begin
  Text := NormalizeLineBreaks(AText, ATarget.LineBreak);
  case ATarget.Encoding of
    TAtlasFileEncoding.Utf8Bom:
      Result := TEncoding.UTF8.GetPreamble + TEncoding.UTF8.GetBytes(Text);
    TAtlasFileEncoding.Ansi:
      Result := TEncoding.ANSI.GetBytes(Text);
    TAtlasFileEncoding.Utf16LE:
      Result := TEncoding.Unicode.GetPreamble + TEncoding.Unicode.GetBytes(Text);
    TAtlasFileEncoding.Utf16BE:
      Result := TEncoding.BigEndianUnicode.GetPreamble + TEncoding.BigEndianUnicode.GetBytes(Text);
  else
    Result := TEncoding.UTF8.GetBytes(Text);
  end;
end;

class function TAtlasFileFormats.Convert(const ABytes: TBytes; const ATarget: TAtlasFileFormat): TBytes;
begin
  Result := Encode(Decode(ABytes, Detect(ABytes).Encoding), ATarget);
end;

class function TAtlasFileFormats.IsAscii(const ABytes: TBytes): Boolean;
var
  Value: Byte;
begin
  for Value in ABytes do
    if Value >= $80 then
      Exit(False);
  Result := True;
end;

class function TAtlasFileFormats.Satisfies(const ABytes: TBytes; const ATarget: TAtlasFileFormat): Boolean;
var
  Actual: TAtlasFileFormat;
  SameEncoding: Boolean;
begin
  Actual := Detect(ABytes);
  SameEncoding := Actual.Encoding = ATarget.Encoding;
  if not SameEncoding and (Actual.Encoding = TAtlasFileEncoding.Utf8) and
    (ATarget.Encoding = TAtlasFileEncoding.Ansi) then
    SameEncoding := IsAscii(ABytes);
  Result := SameEncoding and ((Actual.LineBreak = ATarget.LineBreak) or (Actual.LineBreak = TAtlasLineBreak.None));
end;

class function TAtlasFileFormats.AnsiLosses(const AText: string): Integer;
var
  Back: string;
  Index: Integer;
begin
  Back := TEncoding.ANSI.GetString(TEncoding.ANSI.GetBytes(AText));
  Result := Abs(Length(Back) - Length(AText));
  for Index := 1 to Length(AText) do
    if (Index <= Length(Back)) and (Back[Index] <> AText[Index]) then
      Inc(Result);
end;

class function TAtlasFileFormats.Targets: TArray<TAtlasFileFormat>;
begin
  Result := [TAtlasFileFormat.Create(TAtlasFileEncoding.Utf8Bom, TAtlasLineBreak.CRLF),
    TAtlasFileFormat.Create(TAtlasFileEncoding.Utf8Bom, TAtlasLineBreak.LF),
    TAtlasFileFormat.Create(TAtlasFileEncoding.Utf8, TAtlasLineBreak.CRLF),
    TAtlasFileFormat.Create(TAtlasFileEncoding.Utf8, TAtlasLineBreak.LF),
    TAtlasFileFormat.Create(TAtlasFileEncoding.Ansi, TAtlasLineBreak.CRLF),
    TAtlasFileFormat.Create(TAtlasFileEncoding.Ansi, TAtlasLineBreak.LF)];
end;

end.
