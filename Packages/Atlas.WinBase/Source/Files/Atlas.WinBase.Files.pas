unit Atlas.WinBase.Files;

// Dateien lesen, ohne das atomare Ersetzen zu blockieren (gemeinsam für Server
// und Plugin). Die RTL teilt beim Lesen nie FILE_SHARE_DELETE:
// TFile.ReadAllBytes teilt nur Lesen, TFileStream mit fmShareDenyNone Lesen
// und Schreiben. Solange jemand eine Datei so offen hat, kann ein anderer sie
// nicht durch ihre neue Fassung ersetzen (settings.json, atlas.json, Units nach
// dem Umbenennen, Index-Cache). Der Server trägt ReadAllBytes über
// TWindowsSharedRead in TFileEncoding.Reader ein, das Plugin liest über
// TAtlasTextFile.ReadAllBytes.
// Fehler als Ausnahme der RTL (EFOpenError, EReadError) wie bei TFile.ReadAllBytes;
// TryReadAllBytes meldet sie ohne Ausnahme. Wer mit fehlenden oder gesperrten
// Dateien rechnet (Datendateien von Atlas während eines Builds), nimmt TryReadAllBytes:
// In der IDE kostet jede Ausnahme Hunderte Millisekunden (exceptiondiag sammelt den Stapel).

interface

uses
  System.SysUtils;

type
  TAtlasSharedRead = record
  public
    /// <summary>Liest die ganze Datei und teilt Lesen, Schreiben und Löschen. Ersetzt ein anderer die Datei
    /// währenddessen, liest es den alten Stand zu Ende; wird sie an Ort und Stelle kürzer, das, was da ist.
    /// EFOpenError, wenn sie fehlt oder gesperrt ist; EReadError bei einem Lesefehler.</summary>
    class function ReadAllBytes(const AFileName: string): TBytes; static;
    /// <summary>Wie ReadAllBytes, aber ohne Ausnahme: False (ABytes leer), wenn die Datei fehlt, gesperrt oder
    /// nicht lesbar ist.</summary>
    class function TryReadAllBytes(const AFileName: string; out ABytes: TBytes): Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.RTLConsts;

function OpenShared(const AFileName: string): THandle;
begin
  Result := CreateFile(PChar(AFileName), GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
    nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL or FILE_FLAG_SEQUENTIAL_SCAN, 0);
end;

/// <summary>Liest die offene Datei AHandle ganz; False (ABytes leer) bei einem Lesefehler. Schließt AHandle nicht.
/// </summary>
function ReadOpened(AHandle: THandle; out ABytes: TBytes): Boolean;
var
  mSize: Int64;
  mTotal, mCount: Integer;
begin
  ABytes := nil;
  Result := False;
  mSize := FileSeek(AHandle, Int64(0), 2);
  if (mSize < 0) or (mSize > MaxInt) or (FileSeek(AHandle, Int64(0), 0) <> 0) then
  begin
    Exit;
  end;
  SetLength(ABytes, Integer(mSize));
  mTotal := 0;
  while mTotal < Length(ABytes) do
  begin
    mCount := FileRead(AHandle, ABytes[mTotal], Length(ABytes) - mTotal);
    if mCount < 0 then
    begin
      ABytes := nil;
      Exit;
    end;
    // Kürzer geworden (jemand schreibt an Ort und Stelle): lesen, was da ist.
    if mCount = 0 then
    begin
      Break;
    end;
    Inc(mTotal, mCount);
  end;
  SetLength(ABytes, mTotal);
  Result := True;
end;

class function TAtlasSharedRead.ReadAllBytes(const AFileName: string): TBytes;
var
  mHandle: THandle;
  mRead: Boolean;
begin
  mHandle := OpenShared(AFileName);
  if mHandle = INVALID_HANDLE_VALUE then
  begin
    raise EFOpenError.CreateResFmt(@SFOpenErrorEx, [ExpandFileName(AFileName), SysErrorMessage(GetLastError)]);
  end;
  try
    mRead := ReadOpened(mHandle, Result);
  finally
    CloseHandle(mHandle);
  end;
  if not mRead then
  begin
    raise EReadError.CreateRes(@SReadError);
  end;
end;

class function TAtlasSharedRead.TryReadAllBytes(const AFileName: string; out ABytes: TBytes): Boolean;
var
  mHandle: THandle;
begin
  ABytes := nil;
  mHandle := OpenShared(AFileName);
  if mHandle = INVALID_HANDLE_VALUE then
  begin
    Exit(False);
  end;
  try
    Result := ReadOpened(mHandle, ABytes);
  finally
    CloseHandle(mHandle);
  end;
end;

end.
