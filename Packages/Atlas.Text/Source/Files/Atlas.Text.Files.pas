unit Atlas.Text.Files;

// Kleine Dateiaktionen ohne Fehlermeldung (gemeinsam für Server und Plugin):
// für Austausch- und Statusdateien, die ein anderer Prozess schon gelöscht
// oder gerade offen haben kann.

interface

type
  TTextFiles = class
  public
    /// <summary>Löscht AFileName, wenn es sie gibt; Fehler bleiben still.</summary>
    class procedure DeleteQuietly(const AFileName: string); static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils;

{ TTextFiles }

class procedure TTextFiles.DeleteQuietly(const AFileName: string);
begin
  try
    if TFile.Exists(AFileName) then
    begin
      TFile.Delete(AFileName);
    end;
  except
    // lsp-ignore: catch-all-without-raise -- Austausch- und Statusdateien nach Kräften
    on Exception do
      ;
  end;
end;

end.
