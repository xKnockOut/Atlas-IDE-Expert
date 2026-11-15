unit Atlas.WinBase.Files;

// Dateien lesen, ohne das atomare Ersetzen zu blockieren (gemeinsam für Server
// und Plugin). Die RTL teilt beim Lesen nie FILE_SHARE_DELETE:
// TFile.ReadAllBytes teilt nur Lesen, TFileStream mit fmShareDenyNone Lesen
// und Schreiben. Solange jemand eine Datei so offen hat, kann ein anderer sie
// nicht durch ihre neue Fassung ersetzen (settings.json, atlas.json, Units nach
// dem Umbenennen, Index-Cache). Der Server trägt ReadAllBytes über
// TWindowsSharedRead in TFileEncoding.Reader ein, das Plugin liest über
// TAtlasTextFile.ReadAllBytes.
// Fehler als Ausnahme der RTL (EFOpenError, EReadError) wie bei TFile.ReadAllBytes.

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
  end;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.RTLConsts;

class function TAtlasSharedRead.ReadAllBytes(const AFileName: string): TBytes;
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

end.
