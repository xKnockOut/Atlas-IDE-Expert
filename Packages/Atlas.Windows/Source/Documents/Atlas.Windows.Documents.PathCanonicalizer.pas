unit Atlas.Windows.Documents.PathCanonicalizer;

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
  cFinalPathFlags = $0;

function FinalPathNameByHandle(AHFile: THandle; ALpszFilePath: PWideChar; ACchFilePath: DWORD;
  ADwFlags: DWORD): DWORD; stdcall; external kernel32 name 'GetFinalPathNameByHandleW';

function LongPathForApi(const APath: string): string;
begin
  if (Length(APath) < MAX_PATH) or (Copy(APath, 1, 4) = '\\?\') then
  begin
    Result := APath;
  end
  else if Copy(APath, 1, 2) = '\\' then
  begin
    Result := '\\?\UNC\' + Copy(APath, 3, MaxInt);
  end
  else
  begin
    Result := '\\?\' + APath;
  end;
end;

class function TWindowsPathCanonicalizer.Canonicalize(const APath: string): string;
var
  mHandle: THandle;
  mBuffer: string;
  mLen: DWORD;
begin
  Result := APath;
  if APath = '' then
  begin
    Exit;
  end;
  // FILE_FLAG_BACKUP_SEMANTICS erlaubt auch Ordner.
  mHandle := CreateFile(PChar(LongPathForApi(APath)), 0,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS, 0);
  if mHandle = INVALID_HANDLE_VALUE then
  begin
    Exit;
  end;
  try
    SetLength(mBuffer, MAX_PATH);
    mLen := FinalPathNameByHandle(mHandle, PWideChar(mBuffer), Length(mBuffer),
      cFinalPathFlags);
    if mLen >= DWORD(Length(mBuffer)) then
    begin
      SetLength(mBuffer, mLen + 1);
      mLen := FinalPathNameByHandle(mHandle, PWideChar(mBuffer), Length(mBuffer),
        cFinalPathFlags);
    end;
    if (mLen = 0) or (mLen >= DWORD(Length(mBuffer))) then
    begin
      Exit;
    end;
    SetLength(mBuffer, mLen);
    // \\?\C:\... bzw. \\?\UNC\server\... zurück in die gewohnte Form
    if SameText(Copy(mBuffer, 1, 8), '\\?\UNC\') then
    begin
      Result := '\\' + Copy(mBuffer, 9, MaxInt);
    end
    else if Copy(mBuffer, 1, 4) = '\\?\' then
    begin
      Result := Copy(mBuffer, 5, MaxInt);
    end
    else
    begin
      Result := mBuffer;
    end;
  finally
    CloseHandle(mHandle);
  end;
end;

end.
