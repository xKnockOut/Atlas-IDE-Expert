unit Atlas.UI.Debug.DataBreak.Strings;

// Texte von „Anhalten bei Datenzugriff“ (#870), auf Deutsch und Englisch. Die Sprache bestimmt Base
// (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasDataBreakTextId = (
    DataBreakTitle, DataBreakSql, DataBreakSqlHint, DataBreakHttp, DataBreakHttpHint, DataBreakIgnoreCase,
    DataBreakOnMatch, DataBreakModeStop, DataBreakModeLog, DataBreakOk, DataBreakCancel, DataBreakCount,
    DataBreakNoServer, DataBreakOff, DataBreakNoSites, DataBreakNoClasses, DataBreakSkipped, DataBreakFailed,
    DataBreakMany, DataBreakWatching, DataBreakWatchingStopped, DataBreakUnresolved, DataBreakStopped,
    DataBreakNotEvaluated, DataBreakEnded, DataBreakCancelled, DataBreakContinue, DataBreakLogOnly, DataBreakFinish,
    DataBreakLogging);

  TAtlasDataBreakStrings = class
  public
    class function Text(AId: TAtlasDataBreakTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasDataBreakTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasDataBreakTextId] of string = (
    ('Anhalten bei Datenzugriff',
     'SQL (%d Stellen)',
     'Muster für den SQL-Text, z. B. *FROM Kunden WHERE* (leer = jeder)',
     'HTTP (%d Stellen)',
     'Muster für Methode und URL, z. B. POST */api/auftrag* (leer = jeder)',
     'Groß-/Kleinschreibung nicht beachten',
     'Bei passendem Zugriff',
     'Anhalten',
     'Nur protokollieren und weiterlaufen',
     'Beobachten',
     'Abbrechen',
     '%d Aufrufe an %d Stellen beobachten; * steht für beliebigen Text, das Muster muss den ganzen Text treffen.',
     'Anhalten bei Datenzugriff: Der Atlas-Server läuft nicht.',
     'Anhalten bei Datenzugriff ist ausgeschaltet (Tools › Optionen › Atlas › Debuggen).',
     'Anhalten bei Datenzugriff: Im Projekt gibt es keine Aufrufe der beobachteten Klassen.',
     'Anhalten bei Datenzugriff: Keine beobachteten Klassen (Tools › Optionen › Atlas › Debuggen).',
     'Anhalten bei Datenzugriff: Unbekannte Klassen ohne Art (=sql oder =http) übersprungen: %s',
     'Anhalten bei Datenzugriff: %s',
     'Anhalten bei Datenzugriff: %d Haltepunkte; das Setzen kann einige Sekunden dauern.',
     'Anhalten bei Datenzugriff: %d Haltepunkte gesetzt (Gruppe Atlas.Datenzugriff), warte auf den nächsten Zugriff.',
     'Anhalten bei Datenzugriff: %d Haltepunkte gesetzt (Gruppe Atlas.Datenzugriff); das Programm steht noch, ' +
       'weiter mit F9.',
     'Anhalten bei Datenzugriff: %d Aufrufe, deren Typ sich nicht bestimmen ließ, bleiben unbeobachtet.',
     'Angehalten bei Datenzugriff: %s',
     '(Text nicht auswertbar)',
     'Anhalten bei Datenzugriff: Das Programm ist beendet; die Haltepunkte sind entfernt.',
     'Anhalten bei Datenzugriff: Beobachtung beendet, Haltepunkte entfernt.',
     'Weiter beobachten',
     'Nur protokollieren',
     'Beenden',
     'Anhalten bei Datenzugriff: Ab jetzt nur protokollieren.'),
    ('Break on data access',
     'SQL (%d places)',
     'Pattern for the SQL text, e.g. *FROM Customers WHERE* (empty = any)',
     'HTTP (%d places)',
     'Pattern for method and URL, e.g. POST */api/order* (empty = any)',
     'Ignore case',
     'When an access matches',
     'Break',
     'Only log and keep running',
     'Watch',
     'Cancel',
     'Watch %d calls at %d places; * stands for any text, the pattern must match the whole text.',
     'Break on data access: the Atlas server is not running.',
     'Break on data access is turned off (Tools › Options › Atlas › Debugging).',
     'Break on data access: the project has no calls of the watched classes.',
     'Break on data access: no watched classes (Tools › Options › Atlas › Debugging).',
     'Break on data access: unknown classes without a kind (=sql or =http) skipped: %s',
     'Break on data access: %s',
     'Break on data access: %d breakpoints; setting them can take a few seconds.',
     'Break on data access: %d breakpoints set (group Atlas.Datenzugriff), waiting for the next access.',
     'Break on data access: %d breakpoints set (group Atlas.Datenzugriff); the program is still stopped, ' +
       'continue with F9.',
     'Break on data access: %d calls whose type could not be determined stay unwatched.',
     'Stopped on data access: %s',
     '(text could not be evaluated)',
     'Break on data access: the program ended; the breakpoints are removed.',
     'Break on data access: watching ended, breakpoints removed.',
     'Keep watching',
     'Only log',
     'Stop watching',
     'Break on data access: only logging from now on.'));

{ TAtlasDataBreakStrings }

class function TAtlasDataBreakStrings.Text(AId: TAtlasDataBreakTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasDataBreakStrings.Fmt(AId: TAtlasDataBreakTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
