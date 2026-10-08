unit BDLsp.Windows.Documents.PathCanonicalizer;

// Kanonische Pfade unter Windows: löst Junctions, Symlinks, subst-Laufwerke
// und 8.3-Kurznamen über GetFinalPathNameByHandle auf. Pfade über 260
// Zeichen werden mit "\\?\" geöffnet. Existiert die Datei nicht oder
// schlägt etwas fehl, bleibt der Pfad unverändert.

interface

uses
  System.SysUtils;

type
  TWindowsPathCanonicalizer = class
  public
    class function Canonicalize(const APath: string): string; static;
  end;

implementation

uses
  Winapi.Windows;

const
  // FILE_NAME_NORMALIZED or VOLUME_NAME_DOS
  FinalPathFlags = $0;

function FinalPathNameByHandle(hFile: THandle; lpszFilePath: PWideChar; cchFilePath: DWORD;
  dwFlags: DWORD): DWORD; stdcall; external kernel32 name 'GetFinalPathNameByHandleW';

function LongPathForApi(const APath: string): string;
begin
  if (Length(APath) < MAX_PATH) or (Copy(APath, 1, 4) = '\\?\') then
    Result := APath
  else if Copy(APath, 1, 2) = '\\' then
    Result := '\\?\UNC\' + Copy(APath, 3, MaxInt)
  else
    Result := '\\?\' + APath;
end;

class function TWindowsPathCanonicalizer.Canonicalize(const APath: string): string;
var
  Handle: THandle;
  Buffer: string;
  Len: DWORD;
begin
  Result := APath;
  if APath = '' then
    Exit;
  // FILE_FLAG_BACKUP_SEMANTICS erlaubt auch Ordner.
  Handle := CreateFile(PChar(LongPathForApi(APath)), 0,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS, 0);
  if Handle = INVALID_HANDLE_VALUE then
    Exit;
  try
    SetLength(Buffer, MAX_PATH);
    Len := FinalPathNameByHandle(Handle, PWideChar(Buffer), Length(Buffer),
      FinalPathFlags);
    if Len >= DWORD(Length(Buffer)) then
    begin
      SetLength(Buffer, Len + 1);
      Len := FinalPathNameByHandle(Handle, PWideChar(Buffer), Length(Buffer),
        FinalPathFlags);
    end;
    if (Len = 0) or (Len >= DWORD(Length(Buffer))) then
      Exit;
    SetLength(Buffer, Len);
    // \\?\C:\... bzw. \\?\UNC\server\... zurück in die gewohnte Form
    if SameText(Copy(Buffer, 1, 8), '\\?\UNC\') then
      Result := '\\' + Copy(Buffer, 9, MaxInt)
    else if Copy(Buffer, 1, 4) = '\\?\' then
      Result := Copy(Buffer, 5, MaxInt)
    else
      Result := Buffer;
  finally
    CloseHandle(Handle);
  end;
end;

end.
