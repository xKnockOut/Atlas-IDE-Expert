unit Atlas.Windows.Documents.SharedRead;

// Platform-Feature "Documents", Root: Dateien lesen, ohne das atomare Ersetzen
// zu blockieren. Solange der Server eine Datei mit den Mitteln der RTL offen
// hat (teilt nie FILE_SHARE_DELETE), kann das Plugin sie nicht durch ihre neue
// Fassung ersetzen (settings.json, atlas.json, Units nach dem Umbenennen), und
// ein zweiter Server nicht den Index-Cache.
// Install trägt TAtlasSharedRead.ReadAllBytes (Atlas.WinBase.Files, dieselbe
// Lesart wie im Plugin) in TFileEncoding.Reader ein; alle Leser über
// TFileEncoding teilen dann auch Löschen.

interface

type
  TWindowsSharedRead = record
  public
    /// <summary>Trägt TAtlasSharedRead.ReadAllBytes in TFileEncoding.Reader ein.</summary>
    class procedure Install; static;
    /// <summary>Nimmt es wieder heraus.</summary>
    class procedure Uninstall; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.WinBase.Files,
  Atlas.Common.Documents.FileEncoding;

{ TWindowsSharedRead }

class procedure TWindowsSharedRead.Install;
begin
  TFileEncoding.Reader :=
    function(const AFileName: string): TBytes
    begin
      Result := TAtlasSharedRead.ReadAllBytes(AFileName);
    end;
end;

class procedure TWindowsSharedRead.Uninstall;
begin
  TFileEncoding.Reader := nil;
end;

end.
