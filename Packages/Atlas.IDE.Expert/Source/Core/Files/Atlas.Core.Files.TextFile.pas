unit Atlas.Core.Files.TextFile;

// Quelltext auf der Platte ändern, ohne die Kodierung zu wechseln (#397):
// Änderungen des Servers an Dateien, die in der IDE nicht offen sind, wenn
// sie nicht im Editor geöffnet werden sollen. Erkannt werden UTF-8 mit BOM,
// UTF-16 LE/BE mit BOM, UTF-8 ohne BOM (gültige Bytefolge) und sonst ANSI.
// Zeilenenden bleiben, wie sie sind. Geschrieben wird erst in eine
// Nachbardatei, die dann die alte ersetzt.
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
    Utf8CodePage = 65001;
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
    /// <summary>Löst EAtlasTextFileError für ein binäres Formular aus.</summary>
    class function Load(const AFileName: string; ADefaultCodePage: Integer): TAtlasTextFileContent; overload;
      static;
    class function Load(const AFileName: string): TAtlasTextFileContent; overload; static;
    /// <summary>Überschreibt nie ein binäres Formular (EAtlasTextFileError).</summary>
    class procedure Save(const AFileName: string; const AContent: TAtlasTextFileContent); static;
  end;

implementation

uses
  System.IOUtils,
  Atlas.Text.Encoding;

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
  Result := (ACodePage > 0) and (ACodePage <> TAtlasTextFile.Utf8CodePage);
end;

function AnsiText(const ABytes: TBytes; ACodePage: Integer): string;
var
  Encoding: TEncoding;
begin
  if ACodePage <= 0 then
    Exit(TEncoding.ANSI.GetString(ABytes));
  Encoding := TEncoding.GetEncoding(ACodePage);
  try
    Result := Encoding.GetString(ABytes);
  finally
    Encoding.Free;
  end;
end;

function AnsiBytes(const AText: string; ACodePage: Integer): TBytes;
var
  Encoding: TEncoding;
begin
  if ACodePage <= 0 then
    Exit(TEncoding.ANSI.GetBytes(AText));
  Encoding := TEncoding.GetEncoding(ACodePage);
  try
    Result := Encoding.GetBytes(AText);
  finally
    Encoding.Free;
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
  Count: Integer;
  Bom: TTextBom;
begin
  Result.CodePage := 0;
  Count := Length(ABytes);
  Bom := TTextEncodingProbe.BomOf(ABytes);
  if Bom = TTextBom.Utf8 then
  begin
    Result.Encoding := TAtlasTextEncoding.Utf8Bom;
    Result.Text := TEncoding.UTF8.GetString(ABytes, 3, Count - 3);
  end
  else if Bom = TTextBom.Utf16LE then
  begin
    Result.Encoding := TAtlasTextEncoding.Utf16LE;
    Result.Text := TEncoding.Unicode.GetString(ABytes, 2, Count - 2);
  end
  else if Bom = TTextBom.Utf16BE then
  begin
    Result.Encoding := TAtlasTextEncoding.Utf16BE;
    Result.Text := TEncoding.BigEndianUnicode.GetString(ABytes, 2, Count - 2);
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
      Result.CodePage := ADefaultCodePage;
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
  Bytes: TBytes;
begin
  Bytes := TFile.ReadAllBytes(AFileName);
  if IsBinaryForm(Bytes) then
    raise EAtlasTextFileError.Create('binär gespeichertes Formular; bitte in der IDE als Text speichern');
  Result := Decode(Bytes, ADefaultCodePage);
end;

class function TAtlasTextFile.Load(const AFileName: string): TAtlasTextFileContent;
begin
  Result := Load(AFileName, 0);
end;

class procedure TAtlasTextFile.Save(const AFileName: string; const AContent: TAtlasTextFileContent);
var
  Temporary: string;
begin
  if TFile.Exists(AFileName) and IsBinaryForm(TFile.ReadAllBytes(AFileName)) then
    raise EAtlasTextFileError.Create('binär gespeichertes Formular wird nicht überschrieben');
  // Erst vollständig daneben schreiben: Ein Abbruch hinterlässt nie eine halbe Datei.
  Temporary := AFileName + '.atlas-tmp';
  TFile.WriteAllBytes(Temporary, Encode(AContent));
  try
    if TFile.Exists(AFileName) then
      TFile.Delete(AFileName);
    TFile.Move(Temporary, AFileName);
  except
    if TFile.Exists(Temporary) then
      TFile.Delete(Temporary);
    raise;
  end;
end;

end.
