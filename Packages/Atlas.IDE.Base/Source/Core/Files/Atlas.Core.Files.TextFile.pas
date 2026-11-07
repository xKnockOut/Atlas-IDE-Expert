unit Atlas.Core.Files.TextFile;

// Quelltext auf der Platte ändern, ohne die Kodierung zu wechseln (#397):
// Änderungen des Servers an Dateien, die in der IDE nicht offen sind, wenn
// sie nicht im Editor geöffnet werden sollen. Erkannt werden UTF-8 mit BOM,
// UTF-16 LE/BE mit BOM, UTF-8 ohne BOM (gültige Bytefolge) und sonst ANSI.
// Zeilenenden bleiben, wie sie sind. Geschrieben wird erst in eine
// Nachbardatei, die dann die alte ersetzt.
//
// Atomar ersetzen (Bericht M5): Die Nachbardatei tritt mit POSIX-Semantik an
// die Stelle der alten. Das gelingt auch, solange andere die alte Datei offen
// haben, wenn sie Löschen teilen; Atlas liest darum selbst mit ReadAllBytes
// (Plugin) bzw. TWindowsSharedRead (Server). Ein halber Stand ist nie
// lesbar: Wer die alte Datei offen hat, liest sie zu Ende, wer danach öffnet,
// bekommt die neue.
//
// Vorgabe-Kodierung (#121): Dieselbe Einstellung "encoding" aus atlas.json wie
// beim Server (TAtlasEncodingDefault liest sie). Eine ANSI-Codepage als Vorgabe
// gilt für ungültiges UTF-8 und für reines ASCII; ohne Vorgabe oder mit
// "utf-8" liest ANSI die Codepage des Systems, wie die IDE.
// Binäre Formulare (TPF0) werden weder dekodiert noch überschrieben.
// Die Prüfungen (BOM, UTF-8, Codepage, TPF0) kommen aus Atlas.Text.Encoding
// und gelten gleich beim Server (ADR 0012).

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  Atlas.Core.Files.Contract;

type
  // Aliase für Bestandsnutzer; die Deklarationen stehen in Atlas.Core.Files.Contract (Code-Review A-10).
  TAtlasTextEncoding = Atlas.Core.Files.Contract.TAtlasTextEncoding;
  TAtlasTextFileContent = Atlas.Core.Files.Contract.TAtlasTextFileContent;
  EAtlasTextFileError = Atlas.Core.Files.Contract.EAtlasTextFileError;

  TAtlasTextFile = class
  public const
    cUtf8CodePage = 65001;
  public
    /// <summary>Kodierung der Bytes und Text ohne BOM. ADefaultCodePage: Vorgabe aus atlas.json
    /// (0 oder 65001 = UTF-8, sonst eine ANSI-Codepage).</summary>
    class function Decode(const ABytes: TBytes; ADefaultCodePage: Integer): TAtlasTextFileContent; overload;
      static;
    /// <summary>Wie oben ohne Vorgabe (UTF-8, ANSI mit der Codepage des Systems).</summary>
    class function Decode(const ABytes: TBytes): TAtlasTextFileContent; overload; static;
    /// <summary>Bytes in derselben Kodierung, mit BOM, wenn sie eins hat.</summary>
    class function Encode(const AContent: TAtlasTextFileContent): TBytes; static;
    /// <summary>Gültiges UTF-8 (auch reines ASCII), strikt wie beim Server: keine überlangen Formen,
    /// keine Surrogate.</summary>
    class function IsUtf8(const ABytes: TBytes; AStart: Integer): Boolean; overload; static;
    class function IsUtf8(const ABytes: TBytes): Boolean; overload; static;
    /// <summary>Binär gespeichertes Formular (TPF0, auch mit Ressourcenkopf).</summary>
    class function IsBinaryForm(const ABytes: TBytes): Boolean; static;
    /// <summary>"utf-8", "utf8", "65001", "1250", "windows-1250", "cp1250" wie beim Server;
    /// False für unbekannte Werte und Mehrbyte-Codepages.</summary>
    class function ParseCodePage(const AText: string; out ACodePage: Integer): Boolean; static;
    /// <summary>
    /// Liest die ganze Datei und teilt Lesen, Schreiben und Löschen, anders als TFile.ReadAllBytes (nur Lesen):
    /// Wer die Datei währenddessen speichert oder atomar ersetzt (Save, der Server, eine zweite IDE), scheitert
    /// nicht an diesem Leser (Bericht M5). Dieselbe Lesart hat der Server in TWindowsSharedRead. EFOpenError,
    /// wenn die Datei fehlt oder gesperrt ist; EReadError bei einem Lesefehler.
    /// </summary>
    class function ReadAllBytes(const AFileName: string): TBytes; static;
    /// <summary>Löst EAtlasTextFileError für ein binäres Formular aus.</summary>
    class function Load(const AFileName: string; ADefaultCodePage: Integer): TAtlasTextFileContent; overload;
      static;
    class function Load(const AFileName: string): TAtlasTextFileContent; overload; static;
    /// <summary>Nur der Text von Load: für Dateien, die das Plugin bloß liest (Projekt, Gruppe, .map), statt
    /// TFile.ReadAllText, das ohne BOM immer ANSI annimmt (#1109).</summary>
    class function LoadText(const AFileName: string): string; static;
    /// <summary>LoadText in Zeilen; ein Umbruch am Ende ergibt wie bei TFile.ReadAllLines keine leere letzte
    /// Zeile.</summary>
    class function LoadLines(const AFileName: string): TArray<string>; static;
    /// <summary>Überschreibt nie ein binäres Formular (EAtlasTextFileError). Ersetzt die Datei atomar;
    /// EAtlasTextFileError, wenn ein anderes Programm sie ohne FILE_SHARE_DELETE offen hält.</summary>
    class procedure Save(const AFileName: string; const AContent: TAtlasTextFileContent); static;
    /// <summary>Ersetzt AFileName atomar durch ABytes wie Save, ohne die Prüfung auf binäre Formulare: für
    /// Datendateien des Plugins (TAtlasDataFile, Bericht N3). Der Ordner muss vorhanden sein.</summary>
    class procedure Replace(const AFileName: string; const ABytes: TBytes); static;
  end;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.IOUtils,
  System.RTLConsts,
  Atlas.Text.Encoding,
  Atlas.Text.Lines,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TTextFileText = (FileIsLockedByAnother, FormSavedAsBinaryPlease, FormSavedAsBinaryIs);

const
  cTexts: array[TAtlasLanguage, TTextFileText] of string = (
    ('Datei ist von einem anderen Programm gesperrt und bleibt unverändert (%s)',
     'binär gespeichertes Formular; bitte in der IDE als Text speichern',
     'binär gespeichertes Formular wird nicht überschrieben'),
    ('File is locked by another program and stays unchanged (%s)',
     'form saved as binary; please save it as text in the IDE',
     'form saved as binary is not overwritten'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TTextFileText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

const
  /// <summary>
  /// Netz, nicht die Behebung: Versuche, solange ein fremdes Programm die Zieldatei ohne FILE_SHARE_DELETE
  /// offen hält (Virenscanner, Sicherung, Synchronisation). Atlas selbst blockiert das Ersetzen nicht mehr
  /// (Bericht M5). Danach scheitert Save, statt die Datei an Ort und Stelle zu überschreiben: Das hinterließ
  /// bei einem Abbruch eine halbe Datei und konnte Lesern einen halben Stand zeigen.
  /// </summary>
  cReplaceAttempts = 10;
  cReplaceWaitMs = 50;
  // Aus winbase.h (Windows 10 1607 und neuer); Delphis Winapi.Windows kennt sie nicht.
  cFileRenameInfoEx = 22;
  cFILE_RENAME_FLAG_REPLACE_IF_EXISTS = $00000001;
  cFILE_RENAME_FLAG_POSIX_SEMANTICS = $00000002;

type
  /// <summary>FILE_RENAME_INFO mit Flags statt ReplaceIfExists, für FileRenameInfoEx.</summary>
  TFileRenameInfoEx = record
    Flags: DWORD;
    RootDirectory: THandle;
    FileNameLength: DWORD;
    FileName: array[0..0] of WideChar;
  end;
  PFileRenameInfoEx = ^TFileRenameInfoEx;

// Mit DWORD statt der Aufzählung aus Winapi.Windows, die FileRenameInfoEx nicht enthält.
function SetFileInformation(AFile: THandle; AInformationClass: DWORD; AInformation: Pointer;
  ASize: DWORD): BOOL; stdcall; external kernel32 name 'SetFileInformationByHandle';

/// <summary>
/// Benennt ASource in ATarget um und ersetzt es mit POSIX-Semantik: Wer ATarget offen hat (und Löschen teilt),
/// liest weiter den alten Stand; wer danach öffnet, bekommt den neuen. ASource muss im selben Ordner liegen.
/// Schreibt ASource vorher auf die Platte, wie MOVEFILE_WRITE_THROUGH beim klassischen Ersetzen; scheitert
/// das, ersetzt es trotzdem (wie früher, als nie geleert wurde). False mit AError, wenn es nicht ging.
/// </summary>
function PosixReplace(const ASource, ATarget: string; out AError: DWORD): Boolean;
var
  mHandle: THandle;
  mName: string;
  mSize: Integer;
  mInfo: PFileRenameInfoEx;
begin
  Result := False;
  mHandle := CreateFile(PChar(ASource), GENERIC_WRITE or _DELETE or SYNCHRONIZE,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if mHandle = INVALID_HANDLE_VALUE then
  begin
    AError := GetLastError;
    Exit;
  end;
  try
    // Voller Pfad: Ein bloßer Name gilt hier relativ zum aktuellen Verzeichnis des Prozesses, nicht zum
    // Ordner der Datei (die Dateien landeten sonst im Arbeitsverzeichnis von bds.exe bzw. der Tests).
    mName := ExpandFileName(ATarget);
    mSize := SizeOf(TFileRenameInfoEx) + Length(mName) * SizeOf(WideChar);
    GetMem(mInfo, mSize);
    try
      FillChar(mInfo^, mSize, 0);
      mInfo^.Flags := cFILE_RENAME_FLAG_REPLACE_IF_EXISTS or cFILE_RENAME_FLAG_POSIX_SEMANTICS;
      mInfo^.RootDirectory := 0;
      mInfo^.FileNameLength := Length(mName) * SizeOf(WideChar);
      Move(PChar(mName)^, mInfo^.FileName, Length(mName) * SizeOf(WideChar));
      FlushFileBuffers(mHandle);
      Result := SetFileInformation(mHandle, cFileRenameInfoEx, mInfo, mSize);
      if not Result then
      begin
        AError := GetLastError;
      end;
    finally
      FreeMem(mInfo);
    end;
  finally
    CloseHandle(mHandle);
  end;
end;

/// <summary>Windows oder das Dateisystem kennen das POSIX-Ersetzen nicht (vor Windows 10 1607, FAT, manche
/// Netzlaufwerke).</summary>
function PosixUnsupported(AError: DWORD): Boolean;
begin
  Result := (AError = ERROR_INVALID_PARAMETER) or (AError = ERROR_NOT_SUPPORTED) or
    (AError = ERROR_INVALID_FUNCTION);
end;

/// <summary>Ein Versuch: POSIX-Ersetzen, wo Windows und das Dateisystem es können, sonst klassisch.</summary>
function TryReplace(const ASource, ATarget: string; out AError: DWORD): Boolean;
begin
  Result := PosixReplace(ASource, ATarget, AError);
  if Result or not PosixUnsupported(AError) then
  begin
    Exit;
  end;
  // Klassisch ersetzen: gelingt nur, solange niemand die Zieldatei offen hat.
  Result := MoveFileEx(PChar(ASource), PChar(ATarget), MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH);
  if not Result then
  begin
    AError := GetLastError;
  end;
end;

/// <summary>Ersetzt ATarget in einem Schritt durch ASource; EAtlasTextFileError, wenn ein fremdes Programm
/// die Zieldatei auch nach den Versuchen des Netzes noch sperrt.</summary>
procedure ReplaceWith(const ASource, ATarget: string);
var
  mAttempt: Integer;
  mError: DWORD;
begin
  mAttempt := 1;
  while not TryReplace(ASource, ATarget, mError) do
  begin
    if mAttempt >= cReplaceAttempts then
    begin
      // Ohne Dateinamen: Die Meldung kann im Protokoll landen.
      raise EAtlasTextFileError.CreateFmt(UiText(TTextFileText.FileIsLockedByAnother),
        [SysErrorMessage(mError)]);
    end;
    // Netz (siehe ReplaceAttempts).
    Inc(mAttempt);
    Sleep(cReplaceWaitMs);
  end;
end;

class function TAtlasTextFile.ReadAllBytes(const AFileName: string): TBytes;
var
  mHandle: THandle;
  mSize: Int64;
  mTotal, mCount: Integer;
begin
  mHandle := CreateFile(PChar(AFileName), GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
    nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL or FILE_FLAG_SEQUENTIAL_SCAN, 0);
  if mHandle = INVALID_HANDLE_VALUE then
  begin
    raise EFOpenError.CreateResFmt(@SFOpenErrorEx, [ExpandFileName(AFileName), SysErrorMessage(GetLastError)]);
  end;
  try
    mSize := FileSeek(mHandle, Int64(0), 2);
    if (mSize < 0) or (mSize > MaxInt) or (FileSeek(mHandle, Int64(0), 0) <> 0) then
    begin
      raise EReadError.CreateRes(@SReadError);
    end;
    SetLength(Result, Integer(mSize));
    mTotal := 0;
    while mTotal < Length(Result) do
    begin
      mCount := FileRead(mHandle, Result[mTotal], Length(Result) - mTotal);
      if mCount < 0 then
      begin
        raise EReadError.CreateRes(@SReadError);
      end;
      // Kürzer geworden (jemand schreibt an Ort und Stelle): lesen, was da ist.
      if mCount = 0 then
      begin
        Break;
      end;
      Inc(mTotal, mCount);
    end;
    SetLength(Result, mTotal);
  finally
    CloseHandle(mHandle);
  end;
end;

class function TAtlasTextFile.IsUtf8(const ABytes: TBytes; AStart: Integer): Boolean;
begin
  Result := TTextEncodingProbe.IsValidUtf8(ABytes, AStart);
end;

class function TAtlasTextFile.IsUtf8(const ABytes: TBytes): Boolean;
begin
  Result := IsUtf8(ABytes, 0);
end;

function IsAnsiDefault(ACodePage: Integer): Boolean;
begin
  Result := (ACodePage > 0) and (ACodePage <> TAtlasTextFile.cUtf8CodePage);
end;

function AnsiText(const ABytes: TBytes; ACodePage: Integer): string;
var
  mEncoding: TEncoding;
begin
  if ACodePage <= 0 then
  begin
    Exit(TEncoding.ANSI.GetString(ABytes));
  end;
  mEncoding := TEncoding.GetEncoding(ACodePage);
  try
    Result := mEncoding.GetString(ABytes);
  finally
    mEncoding.Free;
  end;
end;

function AnsiBytes(const AText: string; ACodePage: Integer): TBytes;
var
  mEncoding: TEncoding;
begin
  if ACodePage <= 0 then
  begin
    Exit(TEncoding.ANSI.GetBytes(AText));
  end;
  mEncoding := TEncoding.GetEncoding(ACodePage);
  try
    Result := mEncoding.GetBytes(AText);
  finally
    mEncoding.Free;
  end;
end;

class function TAtlasTextFile.IsBinaryForm(const ABytes: TBytes): Boolean;
begin
  Result := TTextEncodingProbe.IsBinaryForm(ABytes);
end;

class function TAtlasTextFile.ParseCodePage(const AText: string; out ACodePage: Integer): Boolean;
begin
  Result := TTextEncodingProbe.ParseCodePage(AText, ACodePage);
end;

class function TAtlasTextFile.Decode(const ABytes: TBytes; ADefaultCodePage: Integer): TAtlasTextFileContent;
var
  mCount: Integer;
  mBom: TTextBom;
begin
  Result.CodePage := 0;
  mCount := Length(ABytes);
  mBom := TTextEncodingProbe.BomOf(ABytes);
  if mBom = TTextBom.Utf8 then
  begin
    Result.Encoding := TAtlasTextEncoding.Utf8Bom;
    Result.Text := TEncoding.UTF8.GetString(ABytes, 3, mCount - 3);
  end
  else if mBom = TTextBom.Utf16LE then
  begin
    Result.Encoding := TAtlasTextEncoding.Utf16LE;
    Result.Text := TEncoding.Unicode.GetString(ABytes, 2, mCount - 2);
  end
  else if mBom = TTextBom.Utf16BE then
  begin
    Result.Encoding := TAtlasTextEncoding.Utf16BE;
    Result.Text := TEncoding.BigEndianUnicode.GetString(ABytes, 2, mCount - 2);
  end
  else if IsAnsiDefault(ADefaultCodePage) and TTextEncodingProbe.IsAscii(ABytes) then
  begin
    // Reines ASCII passt zu jeder Kodierung: Eingefügte Umlaute landen in der Vorgabe-Codepage.
    Result.Encoding := TAtlasTextEncoding.Ansi;
    Result.CodePage := ADefaultCodePage;
    Result.Text := TEncoding.ASCII.GetString(ABytes);
  end
  else if IsUtf8(ABytes) then
  begin
    Result.Encoding := TAtlasTextEncoding.Utf8;
    Result.Text := TEncoding.UTF8.GetString(ABytes);
  end
  else
  begin
    Result.Encoding := TAtlasTextEncoding.Ansi;
    if IsAnsiDefault(ADefaultCodePage) then
    begin
      Result.CodePage := ADefaultCodePage;
    end;
    Result.Text := AnsiText(ABytes, Result.CodePage);
  end;
end;

class function TAtlasTextFile.Decode(const ABytes: TBytes): TAtlasTextFileContent;
begin
  Result := Decode(ABytes, 0);
end;

class function TAtlasTextFile.Encode(const AContent: TAtlasTextFileContent): TBytes;
begin
  case AContent.Encoding of
    TAtlasTextEncoding.Utf8Bom:
      Result := TBytes.Create($EF, $BB, $BF) + TEncoding.UTF8.GetBytes(AContent.Text);
    TAtlasTextEncoding.Utf16LE:
      Result := TBytes.Create($FF, $FE) + TEncoding.Unicode.GetBytes(AContent.Text);
    TAtlasTextEncoding.Utf16BE:
      Result := TBytes.Create($FE, $FF) + TEncoding.BigEndianUnicode.GetBytes(AContent.Text);
    TAtlasTextEncoding.Utf8:
      Result := TEncoding.UTF8.GetBytes(AContent.Text);
  else
    Result := AnsiBytes(AContent.Text, AContent.CodePage);
  end;
end;

class function TAtlasTextFile.Load(const AFileName: string; ADefaultCodePage: Integer): TAtlasTextFileContent;
var
  mBytes: TBytes;
begin
  mBytes := ReadAllBytes(AFileName);
  if IsBinaryForm(mBytes) then
  begin
    raise EAtlasTextFileError.Create(UiText(TTextFileText.FormSavedAsBinaryPlease));
  end;
  Result := Decode(mBytes, ADefaultCodePage);
end;

class function TAtlasTextFile.Load(const AFileName: string): TAtlasTextFileContent;
begin
  Result := Load(AFileName, 0);
end;

class function TAtlasTextFile.LoadText(const AFileName: string): string;
begin
  Result := Load(AFileName).Text;
end;

class function TAtlasTextFile.LoadLines(const AFileName: string): TArray<string>;
begin
  Result := TTextLines.SplitLines(LoadText(AFileName));
  if (Length(Result) > 0) and (Result[High(Result)] = '') then
  begin
    SetLength(Result, Length(Result) - 1);
  end;
end;

class procedure TAtlasTextFile.Save(const AFileName: string; const AContent: TAtlasTextFileContent);
begin
  if TFile.Exists(AFileName) and IsBinaryForm(ReadAllBytes(AFileName)) then
  begin
    raise EAtlasTextFileError.Create(UiText(TTextFileText.FormSavedAsBinaryIs));
  end;
  Replace(AFileName, Encode(AContent));
end;

class procedure TAtlasTextFile.Replace(const AFileName: string; const ABytes: TBytes);
var
  mTemporary: string;
begin
  // Erst vollständig daneben schreiben: Ein Abbruch hinterlässt nie eine halbe Datei.
  mTemporary := AFileName + '.atlas-tmp';
  TFile.WriteAllBytes(mTemporary, ABytes);
  try
    ReplaceWith(mTemporary, AFileName);
  except
    if TFile.Exists(mTemporary) then
    begin
      TFile.Delete(mTemporary);
    end;
    raise;
  end;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Files.TextFile', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
