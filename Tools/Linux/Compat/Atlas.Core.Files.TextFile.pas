{$mode delphi}{$H+}
{$modeswitch unicodestrings}{$modeswitch advancedrecords}
unit Atlas.Core.Files.TextFile;

// Ersatz für Atlas.Core.Files.TextFile im Linux-Bau der Tests. Die echte Unit
// ersetzt Dateien über die Windows-API und fällt bei Convert-ForFpc.py heraus.
// Hier nur die Teile, die plattformunabhängige Units brauchen
// (Atlas.Core.Files.DataFile): Lesen, atomar Ersetzen und Umbenennen mit
// Ersetzen. rename(2) ersetzt unter Linux in einem Schritt wie MoveFileEx mit
// MOVEFILE_REPLACE_EXISTING unter Windows.

interface

uses
  SysUtils,
  Classes;

type
  /// <summary>Wie in Atlas.Core.Files.Contract; dort Teil der echten Unit, hier eigenständig.</summary>
  EAtlasTextFileError = class(Exception);

  TAtlasTextFile = class
  public
    /// <summary>Alle Bytes von AFileName; EFOpenError, wenn die Datei fehlt.</summary>
    class function ReadAllBytes(const AFileName: string): TBytes; static;
    /// <summary>Ersetzt AFileName atomar durch ABytes: erst daneben schreiben, dann umbenennen.</summary>
    class procedure Replace(const AFileName: string; const ABytes: TBytes); static;
    /// <summary>Benennt ASource in ATarget um und ersetzt eine vorhandene ATarget in einem Schritt.</summary>
    class function MoveReplacing(const ASource, ATarget: string): Boolean; static;
    /// <summary>Wie in der echten Unit: Dateifehler oder EAtlasTextFileError.</summary>
    class function IsReadError(AE: Exception): Boolean; static;
  end;

implementation

uses
  Atlas.Text.Files;

class function TAtlasTextFile.IsReadError(AE: Exception): Boolean;
begin
  Result := TTextFiles.IsFileError(AE) or (AE is EAtlasTextFileError);
end;

class function TAtlasTextFile.ReadAllBytes(const AFileName: string): TBytes;
var
  mStream: TFileStream;
begin
  Result := nil;
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

class procedure TAtlasTextFile.Replace(const AFileName: string; const ABytes: TBytes);
var
  mTemporary: string;
  mStream: TFileStream;
begin
  mTemporary := AFileName + '.~neu';
  mStream := TFileStream.Create(mTemporary, fmCreate);
  try
    if Length(ABytes) > 0 then
    begin
      mStream.WriteBuffer(ABytes[0], Length(ABytes));
    end;
  finally
    mStream.Free;
  end;
  if not RenameFile(mTemporary, AFileName) then
  begin
    DeleteFile(mTemporary);
    raise EAtlasTextFileError.Create('Datei lässt sich nicht ersetzen');
  end;
end;

class function TAtlasTextFile.MoveReplacing(const ASource, ATarget: string): Boolean;
begin
  Result := RenameFile(ASource, ATarget);
end;

end.
