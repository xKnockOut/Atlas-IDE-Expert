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

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils;

type
  TAtlasTextEncoding = (Utf8Bom, Utf8, Utf16LE, Utf16BE, Ansi);

  TAtlasTextFileContent = record
    Text: string;
    Encoding: TAtlasTextEncoding;
    /// <summary>Codepage bei Ansi; 0 = ANSI-Codepage des Systems.</summary>
    CodePage: Integer;
  end;

  EAtlasTextFileError = class(Exception);

  TAtlasTextFile = class
  public const
    Utf8CodePage = 65001;
  public
    /// <summary>Kodierung der Bytes und Text ohne BOM. ADefaultCodePage: Vorgabe aus atlas.json
    /// (0 oder 65001 = UTF-8, sonst eine ANSI-Codepage).</summary>
    class function Decode(const ABytes: TBytes; ADefaultCodePage: Integer = 0): TAtlasTextFileContent; static;
    /// <summary>Bytes in derselben Kodierung, mit BOM, wenn sie eins hat.</summary>
    class function Encode(const AContent: TAtlasTextFileContent): TBytes; static;
    /// <summary>Gültiges UTF-8 (auch reines ASCII).</summary>
    class function IsUtf8(const ABytes: TBytes; AStart: Integer = 0): Boolean; static;
    /// <summary>Binär gespeichertes Formular (TPF0, auch mit Ressourcenkopf).</summary>
    class function IsBinaryForm(const ABytes: TBytes): Boolean; static;
    /// <summary>"utf-8", "utf8", "65001", "1250", "windows-1250", "cp1250" wie beim Server;
    /// False für unbekannte Werte und Mehrbyte-Codepages.</summary>
    class function ParseCodePage(const AText: string; out ACodePage: Integer): Boolean; static;
    /// <summary>Löst EAtlasTextFileError für ein binäres Formular aus.</summary>
    class function Load(const AFileName: string; ADefaultCodePage: Integer = 0): TAtlasTextFileContent; static;
    /// <summary>Überschreibt nie ein binäres Formular (EAtlasTextFileError).</summary>
    class procedure Save(const AFileName: string; const AContent: TAtlasTextFileContent); static;
  end;

implementation

uses
  System.IOUtils;

class function TAtlasTextFile.IsUtf8(const ABytes: TBytes; AStart: Integer): Boolean;
var
  Index, Follow, Count: Integer;
  Lead: Byte;
begin
  Index := AStart;
  Count := Length(ABytes);
  while Index < Count do
  begin
    Lead := ABytes[Index];
    if Lead < $80 then
      Follow := 0
    else if (Lead >= $C2) and (Lead <= $DF) then
      Follow := 1
    else if (Lead >= $E0) and (Lead <= $EF) then
      Follow := 2
    else if (Lead >= $F0) and (Lead <= $F4) then
      Follow := 3
    else
      Exit(False);
    if Index + Follow >= Count then
      Exit(False);
    Inc(Index);
    while Follow > 0 do
    begin
      if (ABytes[Index] and $C0) <> $80 then
        Exit(False);
      Inc(Index);
      Dec(Follow);
    end;
  end;
  Result := True;
end;

const
  // Einbyte-Codepages, die der Server als Vorgabe annimmt (Atlas.Common.Documents.FileEncoding).
  SingleByteCodePages: array[0..33] of Integer = (437, 737, 775, 850, 852, 855, 857, 858, 860, 861, 862, 863, 864,
    865, 866, 869, 874, 1250, 1251, 1252, 1253, 1254, 1255, 1256, 1257, 1258, 20866, 21866, 28591, 28592, 28595,
    28597, 28605, 28603);

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

function IsAscii(const ABytes: TBytes): Boolean;
var
  Value: Byte;
begin
  for Value in ABytes do
    if Value >= $80 then
      Exit(False);
  Result := True;
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
  Result := HasPrefix(ABytes, [Ord('T'), Ord('P'), Ord('F'), Ord('0')]) or HasPrefix(ABytes, [$FF, $0A, $00]);
end;

class function TAtlasTextFile.ParseCodePage(const AText: string; out ACodePage: Integer): Boolean;
var
  Text: string;
  Known: Integer;
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
    Exit;
  if ACodePage = Utf8CodePage then
    Exit(True);
  for Known in SingleByteCodePages do
    if Known = ACodePage then
      Exit(True);
  ACodePage := 0;
end;

class function TAtlasTextFile.Decode(const ABytes: TBytes; ADefaultCodePage: Integer): TAtlasTextFileContent;
var
  Count: Integer;
begin
  Result.CodePage := 0;
  Count := Length(ABytes);
  if (Count >= 3) and (ABytes[0] = $EF) and (ABytes[1] = $BB) and (ABytes[2] = $BF) then
  begin
    Result.Encoding := TAtlasTextEncoding.Utf8Bom;
    Result.Text := TEncoding.UTF8.GetString(ABytes, 3, Count - 3);
  end
  else if (Count >= 2) and (ABytes[0] = $FF) and (ABytes[1] = $FE) then
  begin
    Result.Encoding := TAtlasTextEncoding.Utf16LE;
    Result.Text := TEncoding.Unicode.GetString(ABytes, 2, Count - 2);
  end
  else if (Count >= 2) and (ABytes[0] = $FE) and (ABytes[1] = $FF) then
  begin
    Result.Encoding := TAtlasTextEncoding.Utf16BE;
    Result.Text := TEncoding.BigEndianUnicode.GetString(ABytes, 2, Count - 2);
  end
  else if IsAnsiDefault(ADefaultCodePage) and IsAscii(ABytes) then
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
