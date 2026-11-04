unit Atlas.Core.SavedPlaces.Contract;

// Gemerkte Stellen als allgemeiner Vertrag von Base (#1456, ADR 0017 Regel 6):
// Ein Modul, das gemerkte Stellen kennt (Lesezeichen und Notizen), stellt
// über seinen Scope eine IAtlasSavedPlacesSource bereit; der Reiter
// „Gemerkt“ der Willkommensseite (#755) fragt sie über die Registry und kommt
// ohne das Modul aus (dann nur mit den Favoriten von Base). Liegt unter
// Core/SavedPlaces statt bei den Verträgen unter Source/Contracts, weil die
// Kern-Units beider Module die Einträge als Daten verwenden (wie
// Atlas.Core.CiBuild.Contract). Nur
// Interfaces und Records, kein Code.

interface

type
{$SCOPEDENUMS ON}
  /// <summary>Art einer gemerkten Stelle: persönliche Notiz (#545) oder benanntes Lesezeichen (#622).</summary>
  TAtlasSavedPlaceKind = (Note, Bookmark);
{$SCOPEDENUMS OFF}

  /// <summary>Eine gemerkte Stelle in einer Datei eines Projekts.</summary>
  TAtlasSavedPlace = record
    Kind: TAtlasSavedPlaceKind;
    /// <summary>Kennung der Notiz bzw. des Lesezeichens.</summary>
    Id: string;
    /// <summary>Titel der Notiz bzw. Name des Lesezeichens.</summary>
    Text: string;
    /// <summary>Vollständiger Pfad der Datei.</summary>
    FileName: string;
    /// <summary>Zeile, 0-basiert.</summary>
    Line: Integer;
    /// <summary>Pfad der Projektdatei.</summary>
    Project: string;
    /// <summary>Lesezeichen: Methode; Notiz: alle Zeilen in einer, wenn sie mehrere hat; sonst ''.</summary>
    Detail: string;
    /// <summary>Notiz verwaist bzw. Lesezeichen nicht gefunden (letzte bekannte Zeile).</summary>
    Lost: Boolean;
  end;

  TAtlasSavedPlaces = TArray<TAtlasSavedPlace>;

  /// <summary>Gemerkte Stellen aller Projekte. Alle Aufrufe im Hauptthread der IDE.</summary>
  IAtlasSavedPlacesSource = interface
    ['{BCF59E72-4ABC-4CFE-806F-A1D32EBDD745}']
    /// <summary>Notizen aller Notizbücher und Lesezeichen neben den Projekten AProjects (.dproj; Projektgruppen
    /// zählen nicht, ihre Projekte stehen selbst in der Liste); dieselbe Datei zählt einmal. Liest nur Dateien,
    /// ohne Server; Fehler beim Lesen lassen den Teil aus.</summary>
    function Places(const AProjects: TArray<string>): TAtlasSavedPlaces;
    /// <summary>Springt zum Lesezeichen AId von AProject und findet die Stelle vorher wieder (#622); False, wenn
    /// das Modul das gerade nicht kann (benannte Lesezeichen aus): dann öffnet der Aufrufer Datei und Zeile.
    /// </summary>
    function OpenBookmark(const AProject, AId: string): Boolean;
  end;

implementation

end.
