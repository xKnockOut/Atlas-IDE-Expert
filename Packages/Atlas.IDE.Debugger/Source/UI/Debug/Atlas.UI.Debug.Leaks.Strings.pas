unit Atlas.UI.Debug.Leaks.Strings;

// Oberflächentexte des Fensters „Atlas-Lecks“ (#1875) im Modul Debugger, auf Deutsch und Englisch: Fenster,
// Befehl, Bewertungen der Erzeugungsstellen, Meldungen und Einstellungen. Die Sprache bestimmt Base
// (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasLeaksTextId = (
    SettingsDebugLeakReport, SettingsDebugLeakReportCompare, SettingsDebugLeakReportWindow, LeaksCaption, LeaksCommand,
    LeaksHideKnown, LeaksMarkKnown, LeaksUnmarkKnown, LeaksEmpty, LeaksSummary, LeaksFromMessageBox, LeaksFromLogFile,
    LeaksSearching, LeaksNoServer, LeaksNameLine, LeaksNew, LeaksMore, LeaksKnownMark, LeaksNoPlaces,
    LeaksFollowsFromObjects, LeaksPlaceLine, LeaksGroupLine, LeaksGroupNoSite, LeaksRatingNeverFreed,
    LeaksRatingReturned, LeaksRatingPassed, LeaksRatingFieldFreed, LeaksRatingOwned, LeaksRatingLocalFreed,
    LeaksRatingNotInProgram, LeaksFooter, LeaksFound);

  TAtlasLeaksStrings = class
  public
    class function Text(AId: TAtlasLeaksTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasLeaksTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasLeaksTextId] of string = (
    ('Leckbericht am Programmende auswerten (Fenster „Atlas-Lecks“)',
     'Mit dem letzten Lauf vergleichen',
     'Fenster bei Lecks öffnen',
     'Atlas-Lecks',
     'Atlas-Lecks',
     'Bekannte ausblenden',
     'Als bekannt markieren',
     'Nicht mehr als bekannt markieren',
     'Kein Leckbericht aus dem letzten Lauf.',
     '%d Lecks unter %d Namen · %s',
     'Meldungsfenster',
     'Logdatei %s',
     'Suche Erzeugungsstellen …',
     'Kein Atlas-Server: Erzeugungsstellen fehlen.',
     '%s ×%d',
     'neu',
     '+%d seit dem letzten Lauf',
     'bekannt',
     'keine Erzeugungsstelle im Projekt gefunden',
     'folgt meist aus geleakten Objekten mit solchen Feldern',
     '%s:%d  %s  ·  %s',
     '%s:%d  %s  ×%d',
     'Stapel ohne eigene Stelle ×%d',
     'nie freigegeben',
     'Rückgabe an den Aufrufer',
     'als Argument weitergereicht',
     'Feld, frei im Destruktor',
     'Owner',
     'lokal freigegeben',
     'nicht im Programm',
     'Enter oder Doppelklick springt zur Stelle',
     'Atlas: Leckbericht mit %d Lecks (Fenster „Atlas-Lecks“).'),
    ('Evaluate the leak report at program end (window “Atlas Leaks”)',
     'Compare with the last run',
     'Open the window when there are leaks',
     'Atlas Leaks',
     'Atlas Leaks',
     'Hide known',
     'Mark as known',
     'Unmark as known',
     'No leak report from the last run.',
     '%d leaks under %d names · %s',
     'message box',
     'log file %s',
     'Looking for creation sites …',
     'No Atlas server: creation sites are missing.',
     '%s ×%d',
     'new',
     '+%d since the last run',
     'known',
     'no creation site found in the project',
     'usually follows from leaked objects with such fields',
     '%s:%d  %s  ·  %s',
     '%s:%d  %s  ×%d',
     'Stack without own site ×%d',
     'never freed',
     'returned to the caller',
     'passed as argument',
     'field, freed in the destructor',
     'owner',
     'freed locally',
     'not in the program',
     'Enter or double-click jumps to the site',
     'Atlas: Leak report with %d leaks (window “Atlas Leaks”).'));

{ TAtlasLeaksStrings }

class function TAtlasLeaksStrings.Text(AId: TAtlasLeaksTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasLeaksStrings.Fmt(AId: TAtlasLeaksTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
