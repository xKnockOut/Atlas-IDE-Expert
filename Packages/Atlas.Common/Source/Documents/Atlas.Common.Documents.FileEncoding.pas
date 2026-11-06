unit Atlas.Common.Documents.FileEncoding;

// Kodierung und Zeilenenden von Quelldateien erkennen und beim Schreiben
// erhalten. Ältere Units liegen oft in ANSI (Windows-1252), neuere in UTF-8
// mit oder ohne BOM. Wer eine Datei ändert (Umbenennen, Code-Aktionen,
// Formatierung), liest sie mit Decode und schreibt sie mit Encode und dem
// erkannten TFileFormat zurück; so bleiben Umlaute und CRLF erhalten.
//
// Erkennung: BOM (UTF-8, UTF-16 LE/BE) hat Vorrang. Ohne BOM gilt eine Datei
// nur als UTF-8, wenn sie ganz gültiges UTF-8 mit mindestens einem
// Nicht-ASCII-Zeichen ist; sonst als Windows-1252, wie dcc sie liest. Reines
// ASCII ist in beiden gleich; dann gilt die Vorgabe (z. B. aus der
// Projekteinstellung). Server und Plugin entscheiden das über
// TTextEncodingProbe.IsValidUtf8 gleich (#1327).
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
//
// Lesen ohne Sperre (Bericht M5): LoadFromFile und ReadAllBytes lesen über
// Reader. Die Plattform setzt dort einen Leser ein, der die Datei auch zum
// Löschen teilt (unter Windows Atlas.Windows.Documents.SharedRead). Sonst kann
// das Plugin settings.json, atlas.json oder eine Unit nicht atomar durch die
// neue Fassung ersetzen, solange der Server sie gerade liest, und das Speichern
// der IDE scheitert, solange der Server nur Lesen teilt.

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
      ACodePage: Integer): TFileFormat; overload; static;
    /// <summary>Wie oben mit ACodePage = 1252.</summary>
    class function Create(AEncoding: TFileEncodingKind; ALineBreak: TLineBreakStyle): TFileFormat; overload; static;
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

  /// <summary>Liest eine ganze Datei; EFOpenError, wenn sie fehlt oder gesperrt ist (Bericht M5).</summary>
  TFileBytesReader = reference to function(const AFileName: string): TBytes;

  TFileEncoding = class
  public const
    cUtf8CodePage = 65001;
  private
    class var FReader: TFileBytesReader;
  public
    /// <summary>Erkennt die Kodierung; ADefault gilt für reines ASCII.</summary>
    class function DetectEncoding(const ABytes: TBytes;
      ADefault: TFileEncodingKind): TFileEncodingKind; overload; static;
    /// <summary>Wie oben mit ADefault = Utf8.</summary>
    class function DetectEncoding(const ABytes: TBytes): TFileEncodingKind; overload; static;
    /// <summary>Häufigster Zeilenumbruch; ohne Umbruch ADefault.</summary>
    class function DetectLineBreak(const AText: string; out AMixed: Boolean;
      ADefault: TLineBreakStyle): TLineBreakStyle; overload; static;
    /// <summary>Wie oben mit ADefault = CRLF.</summary>
    class function DetectLineBreak(const AText: string; out AMixed: Boolean): TLineBreakStyle; overload; static;
    /// <summary>Liest Bytes als Text und liefert das erkannte Format.</summary>
    class function Decode(const ABytes: TBytes; out AFormat: TFileFormat;
      ADefault: TFileEncodingKind): string; overload; static;
    /// <summary>Wie oben mit ADefault = Utf8.</summary>
    class function Decode(const ABytes: TBytes; out AFormat: TFileFormat): string; overload; static;
    /// <summary>Wie Decode, aber mit Vorgabe-Codepage (#121): 65001 = UTF-8 wie Decode; sonst gilt die Codepage
    /// für reines ASCII und ungültiges UTF-8.</summary>
    class function DecodeWithCodePage(const ABytes: TBytes; out AFormat: TFileFormat;
      ACodePage: Integer): string; static;
    /// <summary>"utf-8", "utf8" bzw. "65001" → 65001; "1250", "cp1250", "windows-1250" → 1250, sofern die Codepage ein
    /// Byte je Zeichen hat und bekannt ist. False sonst.</summary>
    class function ParseCodePage(const AText: string; out ACodePage: Integer): Boolean; static;
    /// <summary>Binäres Formular (beginnt mit TPF0 bzw. der Ressourcen-Kennung).</summary>
    class function IsBinaryForm(const ABytes: TBytes): Boolean; static;
    /// <summary>Beginnt mit der BOM von UTF-32 LE (FF FE 00 00) oder BE (00 00 FE FF)? Der Compiler liest diese
    /// Kodierung nicht (F2438, #1085); DetectEncoding hält UTF-32 LE sonst für UTF-16 LE.</summary>
    class function HasUtf32Bom(const ABytes: TBytes): Boolean; static;
    /// <summary>
    /// Fehlstellen in UTF-8 (#150), je eine für eine zu kurze oder ungültige Folge, mit Stelle im Text, den
    /// Decode mit AFormat liefert: bei UTF-8 dort ein U+FFFD, bei ANSI ein Zeichen je Byte. Eine ANSI-Datei
    /// gilt nur dann als beschädigtes UTF-8, wenn ihre gültigen Mehrbytefolgen die Fehlstellen überwiegen
    /// (#1327); sonst ist sie echtes ANSI, wie dcc sie liest, und liefert nichts. UTF-16 ebenso.
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
    /// <summary>Wie Encode, lässt aber jeden Zeilenumbruch, wie er in AText steht (#1358): Formatieren ändert
    /// Zeilenenden nur nach format.endOfLine, auch in Dateien mit gemischten Umbrüchen.</summary>
    class function EncodeKeepingLineBreaks(const AText: string; const AFormat: TFileFormat): TBytes; static;
    /// <summary>Ersetzt alle Zeilenumbrüche durch AStyle.</summary>
    class function NormalizeLineBreaks(const AText: string; AStyle: TLineBreakStyle): string; static;
    /// <summary>
    /// Liest die ganze Datei über Reader. Ohne Reader liest die RTL und teilt Lesen und Schreiben, aber nicht
    /// Löschen. EFOpenError, wenn die Datei fehlt oder gesperrt ist.
    /// </summary>
    class function ReadAllBytes(const AFileName: string): TBytes; static;
    /// <summary>Von der Plattform gesetzt: öffnet so, dass ein anderer Prozess die Datei während des Lesens
    /// atomar ersetzen kann (unter Windows mit FILE_SHARE_DELETE). Nur beim Start setzen.</summary>
    class property Reader: TFileBytesReader read FReader write FReader;
    /// <summary>Liest mit der Vorgabe aus TFileEncodingDefaults für den Ordner der Datei.</summary>
    class function LoadFromFile(const AFileName: string; out AFormat: TFileFormat): string; overload; static;
    class function LoadFromFile(const AFileName: string; out AFormat: TFileFormat;
      ADefault: TFileEncodingKind): string; overload; static;
    /// <summary>Wie LoadFromFile, wenn nur gelesen wird (Projekt, Gruppe, Quelltext, Protokoll): erkennt BOM,
    /// UTF-8 und ANSI statt wie TFile.ReadAllText ohne BOM immer ANSI anzunehmen (#1109).</summary>
    class function LoadText(const AFileName: string): string; static;
    /// <summary>LoadText in Zeilen; ein Umbruch am Ende ergibt wie bei TFile.ReadAllLines keine leere letzte
    /// Zeile.</summary>
    class function LoadLines(const AFileName: string): TArray<string>; static;
    /// <summary>Schreibt AText; ein vorhandenes binäres Formular wird nie überschrieben (EFileEncodingError).</summary>
    class procedure SaveToFile(const AFileName, AText: string; const AFormat: TFileFormat); static;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Text.Encoding,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TFileEncodingText = (FileIn, AFormStoredAsBinary, FilesIn, PlainASCII);

const
  cTexts: array[TFileEncodingText] of TAtlasText = (
    (De: '1 Datei in '; En: '1 file in '),
    (De: 'Binär gespeichertes Formular wird nicht geändert; zuerst in Text umwandeln.';
     En: 'A form stored as binary is not changed; convert it to text first.'),
    (De: '%d Dateien in %s'; En: '%d files in %s'),
    (De: 'reinem ASCII'; En: 'plain ASCII'));

{$SCOPEDENUMS OFF}

var
  DefaultsLock: TObject;
  DefaultFolders: TDictionary<string, Integer>;

{ TFileFormat }

class function TFileFormat.Create(AEncoding: TFileEncodingKind; ALineBreak: TLineBreakStyle): TFileFormat;
begin
  Result := Create(AEncoding, ALineBreak, 1252);
end;

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
  mName: string;
  mPair: TPair<string, Integer>;
  mBest: Integer;
begin
  Result := TFileEncoding.cUtf8CodePage;
  TMonitor.Enter(DefaultsLock);
  try
    if DefaultFolders.Count = 0 then
    begin
      Exit;
    end;
    mName := AnsiUpperCase(ExpandFileName(AFileName));
    mBest := 0;
    for mPair in DefaultFolders do
    begin
      if (Length(mPair.Key) > mBest) and (Copy(mName, 1, Length(mPair.Key)) = mPair.Key) then
      begin
        mBest := Length(mPair.Key);
        Result := mPair.Value;
      end;
    end;
  finally
    TMonitor.Exit(DefaultsLock);
  end;
end;

{ TEncodingSurvey }

procedure TEncodingSurvey.Add(const ABytes: TBytes);
var
  mHasNonAscii: Boolean;
begin
  if TFileEncoding.IsBinaryForm(ABytes) then
  begin
    Exit;
  end;
  if TTextEncodingProbe.HasPrefix(ABytes, [$EF, $BB, $BF]) then
  begin
    Inc(Utf8);
  end
  else if TTextEncodingProbe.HasPrefix(ABytes, [$FF, $FE]) or TTextEncodingProbe.HasPrefix(ABytes, [$FE, $FF]) then
  begin
    Inc(Utf16);
  end
  else if not TTextEncodingProbe.IsValidUtf8(ABytes, 0, mHasNonAscii) then
  begin
    Inc(Ansi);
  end
  else if mHasNonAscii then
  begin
    Inc(Utf8);
  end
  else
  begin
    Inc(Ascii);
  end;
end;

function TEncodingSurvey.IsMixed: Boolean;
begin
  Result := (Ansi > 0) and (Utf8 + Utf16 > 0);
end;

function TEncodingSurvey.Describe: string;

  procedure Append(ACount: Integer; const AName: string);
  begin
    if ACount = 0 then
    begin
      Exit;
    end;
    if Result = '' then
    begin
      if ACount = 1 then
      begin
        Result := cTexts[TFileEncodingText.FileIn].Text + AName;
      end
      else
      begin
        Result := cTexts[TFileEncodingText.FilesIn].Fmt([ACount, AName]);
      end;
    end
    else
    begin
      Result := Result + Format(', %d in %s', [ACount, AName]);
    end;
  end;

begin
  Result := '';
  // Mit Vorgabe UTF-8 liest der Server ungültiges UTF-8 als Windows-1252.
  if (AnsiCodePage = 0) or (AnsiCodePage = TFileEncoding.cUtf8CodePage) then
  begin
    Append(Ansi, 'Windows-1252');
  end
  else
  begin
    Append(Ansi, 'Windows-' + IntToStr(AnsiCodePage));
  end;
  Append(Utf8, 'UTF-8');
  Append(Utf16, 'UTF-16');
  Append(Ascii, cTexts[TFileEncodingText.PlainASCII].Text);
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
  mEncoding: TEncoding;
begin
  if (ACodePage = 0) or (ACodePage = 1252) then
  begin
    Exit(DecodeCp1252(ABytes));
  end;
  mEncoding := TEncoding.GetEncoding(ACodePage);
  try
    Result := mEncoding.GetString(ABytes);
  finally
    mEncoding.Free;
  end;
end;

function EncodeAnsi(const AText: string; ACodePage: Integer): TBytes;
var
  mEncoding: TEncoding;
begin
  if (ACodePage = 0) or (ACodePage = 1252) then
  begin
    Exit(EncodeCp1252(AText));
  end;
  mEncoding := TEncoding.GetEncoding(ACodePage);
  try
    Result := mEncoding.GetBytes(AText);
  finally
    mEncoding.Free;
  end;
end;

/// <summary>Länge der Folge nach dem Startbyte ALead (0 bei ASCII oder ungültigem Startbyte) und seine Bits.
/// </summary>
procedure Utf8Lead(ALead: Byte; out ACount: Integer; out ACodePoint: Cardinal);
begin
  ACount := 0;
  ACodePoint := 0;
  if (ALead >= $C2) and (ALead <= $DF) then
  begin
    ACount := 1;
    ACodePoint := ALead and $1F;
  end
  else if (ALead >= $E0) and (ALead <= $EF) then
  begin
    ACount := 2;
    ACodePoint := ALead and $0F;
  end
  else if (ALead >= $F0) and (ALead <= $F4) then
  begin
    ACount := 3;
    ACodePoint := ALead and $07;
  end;
end;

/// <summary>ACodePoint aus ACount Folgebytes ist kürzest kodiert, kein Surrogat und höchstens U+10FFFF.</summary>
function IsValidUtf8CodePoint(ACount: Integer; ACodePoint: Cardinal): Boolean;
begin
  Result := not ((ACount = 2) and (ACodePoint < $800)) and not ((ACount = 3) and (ACodePoint < $10000)) and
    (ACodePoint <= $10FFFF) and not ((ACodePoint >= $D800) and (ACodePoint <= $DFFF));
end;

/// <summary>Liest die Mehrbytefolge, die an AIndex beginnt: ACount Folgebytes laut Startbyte, davon AValid
/// gültige, ACodePoint der Wert. True, wenn die Folge vollständig und gültig ist.</summary>
function ReadUtf8Sequence(const ABytes: TBytes; AIndex: Integer; out ACount, AValid: Integer;
  out ACodePoint: Cardinal): Boolean;
begin
  Utf8Lead(ABytes[AIndex], ACount, ACodePoint);
  // Gültige Folgebytes zählen; eine zu kurze Folge ist eine Fehlstelle samt ihrer Folgebytes.
  AValid := 0;
  while (AValid < ACount) and (AIndex + AValid + 1 < Length(ABytes)) and
    ((ABytes[AIndex + AValid + 1] and $C0) = $80) do
  begin
    ACodePoint := (ACodePoint shl 6) or (ABytes[AIndex + AValid + 1] and $3F);
    Inc(AValid);
  end;
  Result := (ACount > 0) and (AValid = ACount) and IsValidUtf8CodePoint(ACount, ACodePoint);
end;

/// <summary>Hängt ACodePoint (als Surrogatpaar ab U+10000) an AText an; ALen ist die belegte Länge.</summary>
procedure PutCodePoint(var AText: string; var ALen: Integer; ACodePoint: Cardinal);
begin
  if ACodePoint >= $10000 then
  begin
    Dec(ACodePoint, $10000);
    Inc(ALen);
    AText[ALen] := Char($D800 + (ACodePoint shr 10));
    Inc(ALen);
    AText[ALen] := Char($DC00 + (ACodePoint and $3FF));
  end
  else
  begin
    Inc(ALen);
    AText[ALen] := Char(ACodePoint);
  end;
end;

/// <summary>
/// UTF-8 ab AStart, tolerant: TEncoding.UTF8 wirft unter Delphi bei ungültigen Bytes (EEncodingError). Jede
/// ungültige oder zu kurze Folge wird zu genau einem U+FFFD, wie InvalidUtf8 sie zählt.
/// </summary>
function DecodeUtf8(const ABytes: TBytes; AStart: Integer): string;
var
  mIndex, mCount, mValid, mLen: Integer;
  mCodePoint: Cardinal;
begin
  if TTextEncodingProbe.IsValidUtf8(ABytes, AStart) then
  begin
    Exit(TEncoding.UTF8.GetString(ABytes, AStart, Length(ABytes) - AStart));
  end;
  SetLength(Result, 2 * (Length(ABytes) - AStart));
  mLen := 0;
  mIndex := AStart;
  while mIndex < Length(ABytes) do
  begin
    if ABytes[mIndex] < $80 then
    begin
      PutCodePoint(Result, mLen, ABytes[mIndex]);
      Inc(mIndex);
    end
    else if ReadUtf8Sequence(ABytes, mIndex, mCount, mValid, mCodePoint) then
    begin
      PutCodePoint(Result, mLen, mCodePoint);
      Inc(mIndex, mCount + 1);
    end
    else
    begin
      // Fehlstelle samt ihrer gültigen Folgebytes: ein Ersatzzeichen.
      PutCodePoint(Result, mLen, $FFFD);
      Inc(mIndex, mValid + 1);
    end;
  end;
  SetLength(Result, mLen);
end;

function DecodeUtf16(const ABytes: TBytes; AStart: Integer; ABigEndian: Boolean): string;
var
  mCount: Integer;
  mIndex: Integer;
  mFirst, mSecond: Byte;
begin
  mCount := (Length(ABytes) - AStart) div 2;
  SetLength(Result, mCount);
  for mIndex := 0 to mCount - 1 do
  begin
    mFirst := ABytes[AStart + 2 * mIndex];
    mSecond := ABytes[AStart + 2 * mIndex + 1];
    if ABigEndian then
    begin
      Result[mIndex + 1] := Char((mFirst shl 8) or mSecond);
    end
    else
    begin
      Result[mIndex + 1] := Char((mSecond shl 8) or mFirst);
    end;
  end;
end;

function EncodeUtf16(const AText: string; ABigEndian: Boolean): TBytes;
var
  mIndex: Integer;
  mCode: Word;
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
  for mIndex := 1 to Length(AText) do
  begin
    mCode := Ord(AText[mIndex]);
    if ABigEndian then
    begin
      Result[2 * mIndex] := mCode shr 8;
      Result[2 * mIndex + 1] := mCode and $FF;
    end
    else
    begin
      Result[2 * mIndex] := mCode and $FF;
      Result[2 * mIndex + 1] := mCode shr 8;
    end;
  end;
end;

{ TFileEncoding }

class function TFileEncoding.DetectEncoding(const ABytes: TBytes): TFileEncodingKind;
begin
  Result := DetectEncoding(ABytes, TFileEncodingKind.Utf8);
end;

class function TFileEncoding.DetectLineBreak(const AText: string; out AMixed: Boolean): TLineBreakStyle;
begin
  Result := DetectLineBreak(AText, AMixed, TLineBreakStyle.CRLF);
end;

class function TFileEncoding.Decode(const ABytes: TBytes; out AFormat: TFileFormat): string;
begin
  Result := Decode(ABytes, AFormat, TFileEncodingKind.Utf8);
end;

class function TFileEncoding.DetectEncoding(const ABytes: TBytes; ADefault: TFileEncodingKind): TFileEncodingKind;
var
  mHasNonAscii: Boolean;
begin
  if TTextEncodingProbe.HasPrefix(ABytes, [$EF, $BB, $BF]) then
  begin
    Result := TFileEncodingKind.Utf8Bom;
  end
  else if TTextEncodingProbe.HasPrefix(ABytes, [$FF, $FE]) then
  begin
    Result := TFileEncodingKind.Utf16LE;
  end
  else if TTextEncodingProbe.HasPrefix(ABytes, [$FE, $FF]) then
  begin
    Result := TFileEncodingKind.Utf16BE;
  end
  else if not TTextEncodingProbe.IsValidUtf8(ABytes, 0, mHasNonAscii) then
  begin
    Result := TFileEncodingKind.Ansi1252;
  end
  // Reines ASCII: Utf8Bom oder UTF-16 als Vorgabe heißt nur „UTF-8“, eine BOM fehlt ja.
  else if mHasNonAscii or (ADefault in [TFileEncodingKind.Utf8Bom, TFileEncodingKind.Utf16LE,
    TFileEncodingKind.Utf16BE]) then
  begin
    Result := TFileEncodingKind.Utf8;
  end
  else
  begin
    Result := ADefault;
  end;
end;

class function TFileEncoding.DetectLineBreak(const AText: string; out AMixed: Boolean;
  ADefault: TLineBreakStyle): TLineBreakStyle;
const
  cToText: array[TLineBreakStyle] of TTextLineBreak = (TTextLineBreak.CRLF, TTextLineBreak.LF, TTextLineBreak.CR);
begin
  // Bei Gleichstand gewinnt ADefault, sofern er vorkommt; sonst CRLF vor LF vor CR.
  case TTextLines.DominantOf(AText, cToText[ADefault], AMixed) of
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
  mMixed: Boolean;
begin
  AFormat.Encoding := DetectEncoding(ABytes, ADefault);
  case AFormat.Encoding of
    TFileEncodingKind.Utf8Bom:
      Result := DecodeUtf8(ABytes, 3);
    TFileEncodingKind.Utf8:
      Result := DecodeUtf8(ABytes, 0);
    TFileEncodingKind.Utf16LE:
      Result := DecodeUtf16(ABytes, 2, False);
    TFileEncodingKind.Utf16BE:
      Result := DecodeUtf16(ABytes, 2, True);
  else
    Result := DecodeCp1252(ABytes);
  end;
  AFormat.CodePage := 1252;
  AFormat.LineBreak := DetectLineBreak(Result, mMixed);
  AFormat.MixedLineBreaks := mMixed;
end;

class function TFileEncoding.DecodeWithCodePage(const ABytes: TBytes; out AFormat: TFileFormat;
  ACodePage: Integer): string;
var
  mHasNonAscii, mMixed: Boolean;
begin
  if (ACodePage = cUtf8CodePage) or (ACodePage = 0) then
  begin
    Exit(Decode(ABytes, AFormat));
  end;
  AFormat.Encoding := DetectEncoding(ABytes);
  // Reines ASCII gilt bei einer ANSI-Vorgabe als ANSI: Eingefügte Umlaute landen dann in der Codepage.
  if (AFormat.Encoding = TFileEncodingKind.Utf8) and TTextEncodingProbe.IsValidUtf8(ABytes, 0, mHasNonAscii) and
    not mHasNonAscii then
  begin
    AFormat.Encoding := TFileEncodingKind.Ansi1252;
  end;
  case AFormat.Encoding of
    TFileEncodingKind.Utf8Bom:
      Result := DecodeUtf8(ABytes, 3);
    TFileEncodingKind.Utf8:
      Result := DecodeUtf8(ABytes, 0);
    TFileEncodingKind.Utf16LE:
      Result := DecodeUtf16(ABytes, 2, False);
    TFileEncodingKind.Utf16BE:
      Result := DecodeUtf16(ABytes, 2, True);
  else
    Result := DecodeAnsi(ABytes, ACodePage);
  end;
  AFormat.CodePage := ACodePage;
  AFormat.LineBreak := DetectLineBreak(Result, mMixed);
  AFormat.MixedLineBreaks := mMixed;
end;

class function TFileEncoding.ParseCodePage(const AText: string; out ACodePage: Integer): Boolean;
begin
  Result := TTextEncodingProbe.ParseCodePage(AText, ACodePage);
end;

/// <summary>Spalten, die ein Zeichen aus 1 + ACount Bytes belegt: im ANSI-Text eines je Byte, im UTF-8-Text eines
/// bzw. ein Surrogatpaar.</summary>
function Utf8Columns(AAnsi: Boolean; ACount: Integer; ACodePoint: Cardinal): Integer;
begin
  if AAnsi then
  begin
    Result := ACount + 1;
  end
  else if ACodePoint >= $10000 then
  begin
    Result := 2;
  end
  else
  begin
    Result := 1;
  end;
end;

/// <summary>Rückt Zeile und Spalte über das ASCII-Byte AByte vor.</summary>
procedure AdvanceAscii(AByte: Byte; var ALine, AColumn: Integer);
begin
  if AByte = 10 then
  begin
    Inc(ALine);
    AColumn := 0;
  end
  else
  begin
    Inc(AColumn);
  end;
end;

class function TFileEncoding.InvalidUtf8(const ABytes: TBytes; const AFormat: TFileFormat): TArray<TInvalidUtf8>;
var
  mIndex, mCount, mValid, mLine, mColumn, mMultibyteCount: Integer;
  mCodePoint: Cardinal;
  mItem: TInvalidUtf8;
  mAnsi: Boolean;
begin
  Result := nil;
  if AFormat.Encoding in [TFileEncodingKind.Utf16LE, TFileEncodingKind.Utf16BE] then
  begin
    Exit;
  end;
  mAnsi := AFormat.Encoding = TFileEncodingKind.Ansi1252;
  mIndex := 0;
  if AFormat.Encoding = TFileEncodingKind.Utf8Bom then
  begin
    mIndex := 3;
  end;
  mLine := 0;
  mColumn := 0;
  mMultibyteCount := 0;
  while mIndex < Length(ABytes) do
  begin
    if ABytes[mIndex] < $80 then
    begin
      AdvanceAscii(ABytes[mIndex], mLine, mColumn);
      Inc(mIndex);
    end
    else if ReadUtf8Sequence(ABytes, mIndex, mCount, mValid, mCodePoint) then
    begin
      Inc(mMultibyteCount);
      Inc(mColumn, Utf8Columns(mAnsi, mCount, mCodePoint));
      Inc(mIndex, mCount + 1);
    end
    else
    begin
      mItem.Value := ABytes[mIndex];
      mItem.ByteOffset := mIndex;
      mItem.Position := TTextPosition.Create(mLine, mColumn);
      Result := Result + [mItem];
      // Im ANSI-Text belegt die Fehlstelle samt Folgebytes je Byte eine Spalte, im UTF-8-Text ein Ersatzzeichen.
      Inc(mColumn, Utf8Columns(mAnsi, mValid, 0));
      Inc(mIndex, mValid + 1);
    end;
  end;
  // Ohne BOM liest dcc jede Datei, die nicht ganz gültiges UTF-8 ist, als ANSI. Beschädigtes UTF-8 ist sie nur,
  // wenn die gültigen Folgen überwiegen (ein eingestreutes ANSI-Byte in einer UTF-8-Datei). Ein zufällig
  // gültiges Paar wie "Â°" in einer ANSI-Datei mit Umlauten macht deren Umlaute nicht zu Fehlstellen (#1327).
  if mAnsi and (mMultibyteCount <= Length(Result)) then
  begin
    Result := nil;
  end;
end;

class function TFileEncoding.IsBinaryForm(const ABytes: TBytes): Boolean;
begin
  Result := TTextEncodingProbe.IsBinaryForm(ABytes);
end;

class function TFileEncoding.HasUtf32Bom(const ABytes: TBytes): Boolean;
begin
  Result := (Length(ABytes) >= 4) and
    (((ABytes[0] = $FF) and (ABytes[1] = $FE) and (ABytes[2] = 0) and (ABytes[3] = 0)) or
    ((ABytes[0] = 0) and (ABytes[1] = 0) and (ABytes[2] = $FE) and (ABytes[3] = $FF)));
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
begin
  Result := EncodeKeepingLineBreaks(NormalizeLineBreaks(AText, AFormat.LineBreak), AFormat);
end;

class function TFileEncoding.EncodeKeepingLineBreaks(const AText: string; const AFormat: TFileFormat): TBytes;
var
  mText: string;
  mBody: TBytes;
begin
  mText := AText;
  case AFormat.Encoding of
    TFileEncodingKind.Utf8:
      Result := TEncoding.UTF8.GetBytes(mText);
    TFileEncodingKind.Utf8Bom:
      begin
        mBody := TEncoding.UTF8.GetBytes(mText);
        SetLength(Result, 3 + Length(mBody));
        Result[0] := $EF;
        Result[1] := $BB;
        Result[2] := $BF;
        if Length(mBody) > 0 then
        begin
          Move(mBody[0], Result[3], Length(mBody));
        end;
      end;
    TFileEncodingKind.Utf16LE:
      Result := EncodeUtf16(mText, False);
    TFileEncodingKind.Utf16BE:
      Result := EncodeUtf16(mText, True);
  else
    Result := EncodeAnsi(mText, AFormat.CodePage);
  end;
end;

class function TFileEncoding.ReadAllBytes(const AFileName: string): TBytes;
var
  mCustom: TFileBytesReader;
  mStream: TFileStream;
begin
  mCustom := FReader;
  if Assigned(mCustom) then
  begin
    Exit(mCustom(AFileName));
  end;
  // Schreiben teilen: Wer die Datei gerade schreibt (die IDE beim Speichern), scheitert nicht an diesem Leser.
  mStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, mStream.Size);
    if Length(Result) > 0 then
    begin
      mStream.ReadBuffer(Result[0], Length(Result));
    end;
  finally
    mStream.Free;
  end;
end;

class function TFileEncoding.LoadFromFile(const AFileName: string; out AFormat: TFileFormat): string;
begin
  Result := DecodeWithCodePage(ReadAllBytes(AFileName), AFormat, TFileEncodingDefaults.CodePageFor(AFileName));
end;

class function TFileEncoding.LoadFromFile(const AFileName: string; out AFormat: TFileFormat;
  ADefault: TFileEncodingKind): string;
begin
  Result := Decode(ReadAllBytes(AFileName), AFormat, ADefault);
end;

class function TFileEncoding.LoadText(const AFileName: string): string;
var
  mFormat: TFileFormat;
begin
  Result := LoadFromFile(AFileName, mFormat);
end;

class function TFileEncoding.LoadLines(const AFileName: string): TArray<string>;
begin
  Result := TTextLines.SplitLines(LoadText(AFileName));
  if (Length(Result) > 0) and (Result[High(Result)] = '') then
  begin
    SetLength(Result, Length(Result) - 1);
  end;
end;

class function TFileEncoding.IsBinaryFormFile(const AFileName: string): Boolean;
var
  mStream: TFileStream;
  mHead: TBytes;
begin
  Result := False;
  if not FileExists(AFileName) then
  begin
    Exit;
  end;
  try
    mStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      SetLength(mHead, mStream.Size);
      if Length(mHead) > 4 then
      begin
        SetLength(mHead, 4);
      end;
      if Length(mHead) > 0 then
      begin
        mStream.ReadBuffer(mHead[0], Length(mHead));
      end;
    finally
      mStream.Free;
    end;
  except
    on EStreamError do
      Exit;
  end;
  Result := IsBinaryForm(mHead);
end;

class procedure TFileEncoding.SaveToFile(const AFileName, AText: string; const AFormat: TFileFormat);
var
  mStream: TFileStream;
  mBytes: TBytes;
begin
  // Binäre Formulare nie überschreiben (#121): Positionen und Text passen nicht zur Datei.
  if IsBinaryFormFile(AFileName) then
  begin
    // Ohne Dateinamen (#647): die Meldung kann im Diagnoseprotokoll landen.
    raise EFileEncodingError.Create(cTexts[TFileEncodingText.AFormStoredAsBinary].Text);
  end;
  mBytes := Encode(AText, AFormat);
  mStream := TFileStream.Create(AFileName, fmCreate);
  try
    if Length(mBytes) > 0 then
    begin
      mStream.WriteBuffer(mBytes[0], Length(mBytes));
    end;
  finally
    mStream.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Documents.FileEncoding', cTexts);
  DefaultsLock := TObject.Create;
  DefaultFolders := TDictionary<string, Integer>.Create;

finalization
  DefaultFolders.Free;
  DefaultsLock.Free;

end.
