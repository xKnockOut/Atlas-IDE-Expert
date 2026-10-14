unit Atlas.Core.Files.TextFile;

// Quelltext auf der Platte ändern, ohne die Kodierung zu wechseln (#397):
// Änderungen des Servers an Dateien, die in der IDE nicht offen sind, wenn
// sie nicht im Editor geöffnet werden sollen. Erkannt werden UTF-8 mit BOM,
// UTF-16 LE/BE mit BOM, UTF-8 ohne BOM (gültige Bytefolge) und sonst die
// ANSI-Codepage des Systems, wie die IDE sie liest. Zeilenenden bleiben, wie
// sie sind. Geschrieben wird erst in eine Nachbardatei, die dann die alte
// ersetzt.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils;

type
  TAtlasTextEncoding = (Utf8Bom, Utf8, Utf16LE, Utf16BE, Ansi);

  TAtlasTextFileContent = record
    Text: string;
    Encoding: TAtlasTextEncoding;
  end;

  TAtlasTextFile = class
  public
    /// <summary>Kodierung der Bytes und Text ohne BOM.</summary>
    class function Decode(const ABytes: TBytes): TAtlasTextFileContent; static;
    /// <summary>Bytes in derselben Kodierung, mit BOM, wenn sie eins hat.</summary>
    class function Encode(const AContent: TAtlasTextFileContent): TBytes; static;
    /// <summary>Gültiges UTF-8 (auch reines ASCII).</summary>
    class function IsUtf8(const ABytes: TBytes; AStart: Integer = 0): Boolean; static;
    class function Load(const AFileName: string): TAtlasTextFileContent; static;
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

class function TAtlasTextFile.Decode(const ABytes: TBytes): TAtlasTextFileContent;
var
  Count: Integer;
begin
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
  else if IsUtf8(ABytes) then
  begin
    Result.Encoding := TAtlasTextEncoding.Utf8;
    Result.Text := TEncoding.UTF8.GetString(ABytes);
  end
  else
  begin
    Result.Encoding := TAtlasTextEncoding.Ansi;
    Result.Text := TEncoding.ANSI.GetString(ABytes);
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
    Result := TEncoding.ANSI.GetBytes(AContent.Text);
  end;
end;

class function TAtlasTextFile.Load(const AFileName: string): TAtlasTextFileContent;
begin
  Result := Decode(TFile.ReadAllBytes(AFileName));
end;

class procedure TAtlasTextFile.Save(const AFileName: string; const AContent: TAtlasTextFileContent);
var
  Temporary: string;
begin
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
