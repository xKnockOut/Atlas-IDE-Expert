unit Atlas.Common.Documents.FileEncoding;

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
// Vorgabe-Kodierung (#121, "encoding" in atlas.json): Codepage für Dateien
// ohne BOM, bei denen die Heuristik nicht entscheidet. 65001 (UTF-8, Standard)
// lässt alles wie oben; eine ANSI-Codepage wie 1250 gilt für reines ASCII und
// für ungültiges UTF-8. TFileEncodingDefaults merkt sie je Ordner;
// LoadFromFile ohne Vorgabe fragt dort nach, sodass alle schreibenden Pfade
// (MCP, Code-Aktionen, Schnellbefehle) dieselbe Vorgabe nutzen.
//
// Binäre Formulare (TPF0) schreibt SaveToFile nie zurück.
//
// Die Prüfungen (UTF-8, BOM, Codepage, TPF0, Windows-1252, Zeilenenden) stehen
// in Atlas.Text und gelten gleich im Plugin (ADR 0012).
//
// TEncodingSurvey zählt die Kodierungen mehrerer Dateien, damit der Server
// auf ein Projekt mit gemischten Kodierungen hinweisen kann.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract;

type
  /// <summary>Ansi1252 heißt ANSI mit der Codepage aus TFileFormat.CodePage (Standard 1252).</summary>
  TFileEncodingKind = (Utf8, Utf8Bom, Ansi1252, Utf16LE, Utf16BE);

  EFileEncodingError = class(Exception);

  TLineBreakStyle = (CRLF, LF, CR);

  TFileFormat = record
    Encoding: TFileEncodingKind;
    LineBreak: TLineBreakStyle;
    /// <summary>Die Datei enthält verschiedene Zeilenumbrüche; LineBreak ist der häufigste.</summary>
    MixedLineBreaks: Boolean;
    /// <summary>Codepage bei Ansi1252; 0 gilt als 1252.</summary>
    CodePage: Integer;
    class function Create(AEncoding: TFileEncodingKind; ALineBreak: TLineBreakStyle;
      ACodePage: Integer = 1252): TFileFormat; static;
  end;

  /// <summary>Vorgabe-Codepage je Ordner (#121); threadsicher.</summary>
  TFileEncodingDefaults = class
  public
    /// <summary>Gilt für Dateien unter ARoot; 65001 = UTF-8.</summary>
    class procedure SetFolder(const ARoot: string; ACodePage: Integer); static;
    class procedure RemoveFolder(const ARoot: string); static;
    class procedure Clear; static;
    /// <summary>Vorgabe des tiefsten Ordners, der AFileName enthält; sonst 65001.</summary>
    class function CodePageFor(const AFileName: string): Integer; static;
  end;

  /// <summary>Zählt Kodierungen; reines ASCII passt zu jeder und zählt getrennt. Binäre
  /// Formulare haben keine Textkodierung und zählen nicht mit.</summary>
  TEncodingSurvey = record
    Ascii: Integer;
    Utf8: Integer;
    Ansi: Integer;
    Utf16: Integer;
    /// <summary>Codepage, in der ANSI-Dateien gelesen werden (Vorgabe aus atlas.json); 0 gilt als 1252.</summary>
    AnsiCodePage: Integer;
    procedure Add(const ABytes: TBytes);
    /// <summary>ANSI neben UTF-8 oder UTF-16.</summary>
    function IsMixed: Boolean;
    /// <summary>Zum Beispiel "3 Dateien in Windows-1252, 12 in UTF-8".</summary>
    function Describe: string;
  end;

  /// <summary>Ungültiges UTF-8 in einer Datei (#150): das erste Byte der Fehlstelle und seine Stelle im
  /// dekodierten Text.</summary>
  TInvalidUtf8 = record
    Value: Byte;
    /// <summary>Ab 0 in den Bytes der Datei.</summary>
    ByteOffset: Integer;
    /// <summary>Zeile und Spalte (UTF-16) im Text, den Decode mit dem Format liefert.</summary>
    Position: TTextPosition;
  end;

  TFileEncoding = class
  public const
    Utf8CodePage = 65001;
  public
    /// <summary>Erkennt die Kodierung; ADefault gilt für reines ASCII.</summary>
    class function DetectEncoding(const ABytes: TBytes; ADefault: TFileEncodingKind = TFileEncodingKind.Utf8): TFileEncodingKind; static;
    /// <summary>Häufigster Zeilenumbruch; ohne Umbruch ADefault.</summary>
    class function DetectLineBreak(const AText: string; out AMixed: Boolean;
      ADefault: TLineBreakStyle = TLineBreakStyle.CRLF): TLineBreakStyle; static;
    /// <summary>Liest Bytes als Text und liefert das erkannte Format.</summary>
    class function Decode(const ABytes: TBytes; out AFormat: TFileFormat;
      ADefault: TFileEncodingKind = TFileEncodingKind.Utf8): string; static;
    /// <summary>Wie Decode, aber mit Vorgabe-Codepage (#121): 65001 = UTF-8 wie Decode; sonst gilt die Codepage
    /// für reines ASCII und ungültiges UTF-8.</summary>
    class function DecodeWithCodePage(const ABytes: TBytes; out AFormat: TFileFormat;
      ACodePage: Integer): string; static;
    /// <summary>"utf-8", "utf8" bzw. "65001" → 65001; "1250", "cp1250", "windows-1250" → 1250, sofern die Codepage ein
    /// Byte je Zeichen hat und bekannt ist. False sonst.</summary>
    class function ParseCodePage(const AText: string; out ACodePage: Integer): Boolean; static;
    /// <summary>Binäres Formular (beginnt mit TPF0 bzw. der Ressourcen-Kennung).</summary>
    class function IsBinaryForm(const ABytes: TBytes): Boolean; static;
    /// <summary>
    /// Fehlstellen in UTF-8 (#150), je eine für eine zu kurze oder ungültige Folge, mit Stelle im Text, den
    /// Decode mit AFormat liefert: bei UTF-8 dort ein U+FFFD, bei ANSI ein Zeichen je Byte. ANSI-Dateien
    /// ohne gültige Mehrbytefolge sind echtes ANSI und liefern nichts; UTF-16 ebenso.
    /// </summary>
    class function InvalidUtf8(const ABytes: TBytes; const AFormat: TFileFormat): TArray<TInvalidUtf8>; static;
    /// <summary>Vorhandene Datei, die ein binäres Formular ist; False, wenn sie fehlt oder nicht lesbar ist.</summary>
    class function IsBinaryFormFile(const AFileName: string): Boolean; static;
    /// <summary>
    /// Schreibt Text im Format AFormat: alle Zeilenumbrüche werden zu
    /// AFormat.LineBreak, bei Utf8Bom und UTF-16 kommt die BOM davor. Zeichen,
    /// die Windows-1252 nicht kennt, werden zu '?'.
    /// </summary>
    class function Encode(const AText: string; const AFormat: TFileFormat): TBytes; static;
    /// <summary>Ersetzt alle Zeilenumbrüche durch AStyle.</summary>
    class function NormalizeLineBreaks(const AText: string; AStyle: TLineBreakStyle): string; static;
    /// <summary>Liest mit der Vorgabe aus TFileEncodingDefaults für den Ordner der Datei.</summary>
    class function LoadFromFile(const AFileName: string; out AFormat: TFileFormat): string; overload; static;
    class function LoadFromFile(const AFileName: string; out AFormat: TFileFormat;
      ADefault: TFileEncodingKind): string; overload; static;
    /// <summary>Schreibt AText; ein vorhandenes binäres Formular wird nie überschrieben (EFileEncodingError).</summary>
    class procedure SaveToFile(const AFileName, AText: string; const AFormat: TFileFormat); static;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Text.Encoding;

var
  DefaultsLock: TObject;
  DefaultFolders: TDictionary<string, Integer>;

{ TFileFormat }

class function TFileFormat.Create(AEncoding: TFileEncodingKind; ALineBreak: TLineBreakStyle;
  ACodePage: Integer): TFileFormat;
begin
  Result.Encoding := AEncoding;
  Result.LineBreak := ALineBreak;
  Result.MixedLineBreaks := False;
  Result.CodePage := ACodePage;
end;

{ TFileEncodingDefaults }

function FolderKey(const ARoot: string): string;
begin
  Result := IncludeTrailingPathDelimiter(AnsiUpperCase(ExpandFileName(ARoot)));
end;

class procedure TFileEncodingDefaults.SetFolder(const ARoot: string; ACodePage: Integer);
begin
  TMonitor.Enter(DefaultsLock);
  try
    DefaultFolders.AddOrSetValue(FolderKey(ARoot), ACodePage);
  finally
    TMonitor.Exit(DefaultsLock);
  end;
end;

class procedure TFileEncodingDefaults.RemoveFolder(const ARoot: string);
begin
  TMonitor.Enter(DefaultsLock);
  try
    DefaultFolders.Remove(FolderKey(ARoot));
  finally
    TMonitor.Exit(DefaultsLock);
  end;
end;

class procedure TFileEncodingDefaults.Clear;
begin
  TMonitor.Enter(DefaultsLock);
  try
    DefaultFolders.Clear;
  finally
    TMonitor.Exit(DefaultsLock);
  end;
end;

class function TFileEncodingDefaults.CodePageFor(const AFileName: string): Integer;
var
  Name: string;
  Pair: TPair<string, Integer>;
  Best: Integer;
begin
  Result := TFileEncoding.Utf8CodePage;
  TMonitor.Enter(DefaultsLock);
  try
    if DefaultFolders.Count = 0 then
      Exit;
    Name := AnsiUpperCase(ExpandFileName(AFileName));
    Best := 0;
    for Pair in DefaultFolders do
      if (Length(Pair.Key) > Best) and (Copy(Name, 1, Length(Pair.Key)) = Pair.Key) then
      begin
        Best := Length(Pair.Key);
        Result := Pair.Value;
      end;
  finally
    TMonitor.Exit(DefaultsLock);
  end;
end;

{ TEncodingSurvey }

procedure TEncodingSurvey.Add(const ABytes: TBytes);
var
  HasNonAscii: Boolean;
begin
  if TFileEncoding.IsBinaryForm(ABytes) then
    Exit;
  if TTextEncodingProbe.HasPrefix(ABytes, [$EF, $BB, $BF]) then
    Inc(Utf8)
  else if TTextEncodingProbe.HasPrefix(ABytes, [$FF, $FE]) or TTextEncodingProbe.HasPrefix(ABytes, [$FE, $FF]) then
    Inc(Utf16)
  else if not TTextEncodingProbe.IsValidUtf8(ABytes, 0, HasNonAscii) then
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
  // Mit Vorgabe UTF-8 liest der Server ungültiges UTF-8 als Windows-1252.
  if (AnsiCodePage = 0) or (AnsiCodePage = TFileEncoding.Utf8CodePage) then
    Append(Ansi, 'Windows-1252')
  else
    Append(Ansi, 'Windows-' + IntToStr(AnsiCodePage));
  Append(Utf8, 'UTF-8');
  Append(Utf16, 'UTF-16');
  Append(Ascii, 'reinem ASCII');
end;

function DecodeCp1252(const ABytes: TBytes): string;
begin
  Result := TTextEncodingProbe.DecodeCp1252(ABytes, 0);
end;

function EncodeCp1252(const AText: string): TBytes;
begin
  Result := TTextEncodingProbe.EncodeCp1252(AText);
end;

function DecodeAnsi(const ABytes: TBytes; ACodePage: Integer): string;
var
  Encoding: TEncoding;
begin
  if (ACodePage = 0) or (ACodePage = 1252) then
    Exit(DecodeCp1252(ABytes));
  Encoding := TEncoding.GetEncoding(ACodePage);
  try
    Result := Encoding.GetString(ABytes);
  finally
    Encoding.Free;
  end;
end;

function EncodeAnsi(const AText: string; ACodePage: Integer): TBytes;
var
  Encoding: TEncoding;
begin
  if (ACodePage = 0) or (ACodePage = 1252) then
    Exit(EncodeCp1252(AText));
  Encoding := TEncoding.GetEncoding(ACodePage);
  try
    Result := Encoding.GetBytes(AText);
  finally
    Encoding.Free;
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
  if TTextEncodingProbe.HasPrefix(ABytes, [$EF, $BB, $BF]) then
    Exit(TFileEncodingKind.Utf8Bom);
  if TTextEncodingProbe.HasPrefix(ABytes, [$FF, $FE]) then
    Exit(TFileEncodingKind.Utf16LE);
  if TTextEncodingProbe.HasPrefix(ABytes, [$FE, $FF]) then
    Exit(TFileEncodingKind.Utf16BE);
  if not TTextEncodingProbe.IsValidUtf8(ABytes, 0, HasNonAscii) then
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
const
  ToText: array[TLineBreakStyle] of TTextLineBreak = (TTextLineBreak.CRLF, TTextLineBreak.LF, TTextLineBreak.CR);
begin
  // Bei Gleichstand gewinnt ADefault, sofern er vorkommt; sonst CRLF vor LF vor CR.
  case TTextLines.DominantOf(AText, ToText[ADefault], AMixed) of
    TTextLineBreak.CRLF:
      Result := TLineBreakStyle.CRLF;
    TTextLineBreak.LF:
      Result := TLineBreakStyle.LF;
    TTextLineBreak.CR:
      Result := TLineBreakStyle.CR;
  else
    Result := ADefault;
  end;
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
  AFormat.CodePage := 1252;
  AFormat.LineBreak := DetectLineBreak(Result, Mixed);
  AFormat.MixedLineBreaks := Mixed;
end;

class function TFileEncoding.DecodeWithCodePage(const ABytes: TBytes; out AFormat: TFileFormat;
  ACodePage: Integer): string;
var
  HasNonAscii, Mixed: Boolean;
begin
  if (ACodePage = Utf8CodePage) or (ACodePage = 0) then
    Exit(Decode(ABytes, AFormat));
  AFormat.Encoding := DetectEncoding(ABytes);
  // Reines ASCII gilt bei einer ANSI-Vorgabe als ANSI: Eingefügte Umlaute landen dann in der Codepage.
  if (AFormat.Encoding = TFileEncodingKind.Utf8) and TTextEncodingProbe.IsValidUtf8(ABytes, 0, HasNonAscii) and
    not HasNonAscii then
    AFormat.Encoding := TFileEncodingKind.Ansi1252;
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
    Result := DecodeAnsi(ABytes, ACodePage);
  end;
  AFormat.CodePage := ACodePage;
  AFormat.LineBreak := DetectLineBreak(Result, Mixed);
  AFormat.MixedLineBreaks := Mixed;
end;

class function TFileEncoding.ParseCodePage(const AText: string; out ACodePage: Integer): Boolean;
begin
  Result := TTextEncodingProbe.ParseCodePage(AText, ACodePage);
end;

class function TFileEncoding.InvalidUtf8(const ABytes: TBytes; const AFormat: TFileFormat): TArray<TInvalidUtf8>;
var
  Index, Count, Valid, Line, Column: Integer;
  Lead: Byte;
  CodePoint: Cardinal;
  Item: TInvalidUtf8;
  Multibyte: Boolean;
begin
  Result := nil;
  if AFormat.Encoding in [TFileEncodingKind.Utf16LE, TFileEncodingKind.Utf16BE] then
    Exit;
  Index := 0;
  if AFormat.Encoding = TFileEncodingKind.Utf8Bom then
    Index := 3;
  Line := 0;
  Column := 0;
  Multibyte := False;
  while Index < Length(ABytes) do
  begin
    Lead := ABytes[Index];
    if Lead < $80 then
    begin
      if Lead = 10 then
      begin
        Inc(Line);
        Column := 0;
      end
      else
        Inc(Column);
      Inc(Index);
      Continue;
    end;
    Count := 0;
    CodePoint := 0;
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
    end;
    // Gültige Folgebytes zählen; eine zu kurze Folge ist eine Fehlstelle samt ihrer Folgebytes.
    Valid := 0;
    while (Valid < Count) and (Index + Valid + 1 < Length(ABytes)) and
      ((ABytes[Index + Valid + 1] and $C0) = $80) do
    begin
      CodePoint := (CodePoint shl 6) or (ABytes[Index + Valid + 1] and $3F);
      Inc(Valid);
    end;
    if (Count > 0) and (Valid = Count) and not (((Count = 2) and (CodePoint < $800)) or
      ((Count = 3) and (CodePoint < $10000)) or (CodePoint > $10FFFF) or
      ((CodePoint >= $D800) and (CodePoint <= $DFFF))) then
    begin
      Multibyte := True;
      // Im ANSI-Text ein Zeichen je Byte, im UTF-8-Text eines bzw. ein Surrogatpaar.
      if AFormat.Encoding = TFileEncodingKind.Ansi1252 then
        Inc(Column, Count + 1)
      else if CodePoint >= $10000 then
        Inc(Column, 2)
      else
        Inc(Column);
      Inc(Index, Count + 1);
      Continue;
    end;
    Item.Value := Lead;
    Item.ByteOffset := Index;
    Item.Position := TTextPosition.Create(Line, Column);
    Result := Result + [Item];
    if AFormat.Encoding = TFileEncodingKind.Ansi1252 then
      Inc(Column, Valid + 1)
    else
      Inc(Column);
    Inc(Index, Valid + 1);
  end;
  // ANSI ohne eine einzige gültige UTF-8-Folge: kein beschädigtes UTF-8, sondern ANSI.
  if (AFormat.Encoding = TFileEncodingKind.Ansi1252) and not Multibyte then
    Result := nil;
end;

class function TFileEncoding.IsBinaryForm(const ABytes: TBytes): Boolean;
begin
  Result := TTextEncodingProbe.IsBinaryForm(ABytes);
end;

class function TFileEncoding.NormalizeLineBreaks(const AText: string; AStyle: TLineBreakStyle): string;
begin
  case AStyle of
    TLineBreakStyle.LF:
      Result := TTextLines.NormalizeLineBreaks(AText, #10);
    TLineBreakStyle.CR:
      Result := TTextLines.NormalizeLineBreaks(AText, #13);
  else
    Result := TTextLines.NormalizeLineBreaks(AText, #13#10);
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
    Result := EncodeAnsi(Text, AFormat.CodePage);
  end;
end;

function ReadBytes(const AFileName: string): TBytes;
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, Stream.Size);
    if Length(Result) > 0 then
      Stream.ReadBuffer(Result[0], Length(Result));
  finally
    Stream.Free;
  end;
end;

class function TFileEncoding.LoadFromFile(const AFileName: string; out AFormat: TFileFormat): string;
begin
  Result := DecodeWithCodePage(ReadBytes(AFileName), AFormat, TFileEncodingDefaults.CodePageFor(AFileName));
end;

class function TFileEncoding.LoadFromFile(const AFileName: string; out AFormat: TFileFormat;
  ADefault: TFileEncodingKind): string;
begin
  Result := Decode(ReadBytes(AFileName), AFormat, ADefault);
end;

class function TFileEncoding.IsBinaryFormFile(const AFileName: string): Boolean;
var
  Stream: TFileStream;
  Head: TBytes;
begin
  Result := False;
  if not FileExists(AFileName) then
    Exit;
  try
    Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Head, Stream.Size);
      if Length(Head) > 4 then
        SetLength(Head, 4);
      if Length(Head) > 0 then
        Stream.ReadBuffer(Head[0], Length(Head));
    finally
      Stream.Free;
    end;
  except
    on EStreamError do
      Exit;
  end;
  Result := IsBinaryForm(Head);
end;

class procedure TFileEncoding.SaveToFile(const AFileName, AText: string; const AFormat: TFileFormat);
var
  Stream: TFileStream;
  Bytes: TBytes;
begin
  // Binäre Formulare nie überschreiben (#121): Positionen und Text passen nicht zur Datei.
  if IsBinaryFormFile(AFileName) then
    // Ohne Dateinamen (#647): die Meldung kann im Diagnoseprotokoll landen.
    raise EFileEncodingError.Create('Binär gespeichertes Formular wird nicht geändert; zuerst in Text umwandeln.');
  Bytes := Encode(AText, AFormat);
  Stream := TFileStream.Create(AFileName, fmCreate);
  try
    if Length(Bytes) > 0 then
      Stream.WriteBuffer(Bytes[0], Length(Bytes));
  finally
    Stream.Free;
  end;
end;

initialization
  DefaultsLock := TObject.Create;
  DefaultFolders := TDictionary<string, Integer>.Create;

finalization
  DefaultFolders.Free;
  DefaultsLock.Free;

end.
