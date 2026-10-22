unit Atlas.Windows.Documents.SharedRead;

// Platform-Feature "Documents", Root: Dateien lesen, ohne das atomare Ersetzen
// zu blockieren (Bericht M5). Die RTL teilt beim Lesen nie FILE_SHARE_DELETE:
// TFile.ReadAllBytes teilt nur Lesen, TFileStream mit fmShareDenyNone Lesen
// und Schreiben. Solange der Server eine Datei so offen hat, kann das Plugin
// sie nicht durch ihre neue Fassung ersetzen (settings.json, atlas.json, Units
// nach dem Umbenennen), und ein zweiter Server nicht den Index-Cache.
// Install trägt ReadAllBytes in TFileEncoding.Reader ein; alle Leser über
// TFileEncoding teilen dann auch Löschen.
//
// Dieselbe Lesart hat das Plugin in TAtlasTextFile.ReadAllBytes; es bindet
// Atlas.Windows nicht ein (ADR 0012).

interface

uses
  System.SysUtils;

type
  TWindowsSharedRead = record
  public
    /// <summary>Liest die ganze Datei und teilt Lesen, Schreiben und Löschen. Ersetzt ein anderer die Datei
    /// währenddessen, liest es den alten Stand zu Ende. EFOpenError, wenn sie fehlt oder gesperrt ist;
    /// EReadError bei einem Lesefehler.</summary>
    class function ReadAllBytes(const AFileName: string): TBytes; static;
    /// <summary>Trägt ReadAllBytes in TFileEncoding.Reader ein.</summary>
    class procedure Install; static;
    /// <summary>Nimmt es wieder heraus.</summary>
    class procedure Uninstall; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.RTLConsts,
  Atlas.Common.Documents.FileEncoding;

class function TWindowsSharedRead.ReadAllBytes(const AFileName: string): TBytes;
var
  Handle: THandle;
  Size: Int64;
  Total, Count: Integer;
begin
  Handle := CreateFile(PChar(AFileName), GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
    nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL or FILE_FLAG_SEQUENTIAL_SCAN, 0);
  if Handle = INVALID_HANDLE_VALUE then
    raise EFOpenError.CreateResFmt(@SFOpenErrorEx, [ExpandFileName(AFileName), SysErrorMessage(GetLastError)]);
  try
    Size := FileSeek(Handle, Int64(0), 2);
    if (Size < 0) or (Size > MaxInt) or (FileSeek(Handle, Int64(0), 0) <> 0) then
      raise EReadError.CreateRes(@SReadError);
    SetLength(Result, Integer(Size));
    Total := 0;
    while Total < Length(Result) do
    begin
      Count := FileRead(Handle, Result[Total], Length(Result) - Total);
      if Count < 0 then
        raise EReadError.CreateRes(@SReadError);
      // Kürzer geworden (jemand schreibt an Ort und Stelle): lesen, was da ist.
      if Count = 0 then
        Break;
      Inc(Total, Count);
    end;
    SetLength(Result, Total);
  finally
    CloseHandle(Handle);
  end;
end;

class procedure TWindowsSharedRead.Install;
begin
  TFileEncoding.Reader :=
    function(const AFileName: string): TBytes
    begin
      Result := TWindowsSharedRead.ReadAllBytes(AFileName);
    end;
end;

class procedure TWindowsSharedRead.Uninstall;
begin
  TFileEncoding.Reader := nil;
end;

end.
