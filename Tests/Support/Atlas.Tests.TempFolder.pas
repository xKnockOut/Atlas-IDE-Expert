unit Atlas.Tests.TempFolder;

// Testhilfe: Ordner unter dem Temp-Pfad, den ein Test anlegt und im TearDown wieder entfernt. Viele Testklassen
// hatten dafür denselben TearDown.

interface

type
  TTestTempFolder = record
  public
    /// <summary>Löscht den Ordner samt Inhalt, falls es ihn gibt, und leert die Variable (Leckmonitor).</summary>
    class procedure Remove(var AFolder: string); static;
  end;

implementation

uses
  System.IOUtils;

{ TTestTempFolder }

class procedure TTestTempFolder.Remove(var AFolder: string);
begin
  if (AFolder <> '') and TDirectory.Exists(AFolder) then
  begin
    TDirectory.Delete(AFolder, True);
  end;
  AFolder := '';
end;

end.
