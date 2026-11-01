unit Atlas.IDE.Completion.Favorites;

// Angeheftete Favoriten (#458) für die IDE: eine Instanz für das ganze Plugin, gelesen aus
// %APPDATA%\Atlas\favorites.json beim ersten Zugriff (neben usage.json der lernenden Gewichtung, #418) und
// nach jeder Änderung sofort gespeichert, damit ein Absturz der IDE keinen Favoriten kostet. Eine unbrauchbare
// Datei legt TAtlasDataFile als favorites.json.defekt beiseite, eine gesperrte bleibt unverändert (Bericht N3). Die
// Einstellungsseite listet und entfernt sie über Items und Remove. Andere Teile des Plugins (etwa der Reiter
// „Gemerkt“ der Willkommensseite, #755) lesen die Datei über FileName und TAtlasFavorites.LoadFromFile, ohne
// Server.

interface

uses
  Atlas.Core.Completion.Favorites;

type
  TAtlasIdeFavorites = class
  private class var
    FFavorites: TAtlasFavorites;
  public
    /// <summary>%APPDATA%\Atlas\favorites.json.</summary>
    class function FileName: string; static;
    class function Instance: TAtlasFavorites; static;
    /// <summary>Speichert, wenn sich etwas geändert hat; Fehler stören die IDE nie.</summary>
    class procedure Save; static;
    /// <summary>Alle Favoriten in der Reihenfolge des Anheftens.</summary>
    class function Items: TArray<TAtlasFavorite>; static;
    /// <summary>Löst die Favoriten mit den Schlüsseln AKeys und speichert.</summary>
    class procedure Remove(const AKeys: TArray<string>); static;
    class procedure Release; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Core.Files.DataFile;

{ TAtlasIdeFavorites }

class function TAtlasIdeFavorites.FileName: string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.GetHomePath, 'Atlas'), 'favorites.json');
end;

class function TAtlasIdeFavorites.Instance: TAtlasFavorites;
begin
  if FFavorites = nil then
  begin
    FFavorites := TAtlasFavorites.Create;
    // Fehlt, unbrauchbar oder gesperrt: leer beginnen; TAtlasDataFile legt Unbrauchbares beiseite und
    // protokolliert, eine gesperrte Datei schreibt Save nicht.
    FFavorites.LoadFromFile(FileName);
  end;
  Result := FFavorites;
end;

class procedure TAtlasIdeFavorites.Save;
begin
  if (FFavorites = nil) or not FFavorites.Changed then
    Exit;
  try
    FFavorites.SaveToFile(FileName);
  except
    // Speichern darf die IDE nie stören; der Grund steht einmal im Protokoll, Changed bleibt gesetzt.
    on E: Exception do
      TAtlasDataFile.ReportNotWritten('Favoriten', E);
  end;
end;

class function TAtlasIdeFavorites.Items: TArray<TAtlasFavorite>;
begin
  Result := Instance.Items;
end;

class procedure TAtlasIdeFavorites.Remove(const AKeys: TArray<string>);
var
  Key: string;
begin
  for Key in AKeys do
    Instance.Remove(Key);
  Save;
end;

class procedure TAtlasIdeFavorites.Release;
begin
  Save;
  FreeAndNil(FFavorites);
end;

end.
