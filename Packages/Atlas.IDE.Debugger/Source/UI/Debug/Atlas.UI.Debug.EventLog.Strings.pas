unit Atlas.UI.Debug.EventLog.Strings;

// Texte des Ereignisprotokolls von Atlas, auf Deutsch und Englisch (#1455). Die Sprache bestimmt Base
// (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasEventLogTextId = (
    DebugEventLogCaption, DebugEventLogFilterHint, DebugEventLogKindAll, DebugEventLogKindOutput,
    DebugEventLogKindBreakpoint, DebugEventLogKindModule, DebugEventLogKindThread, DebugEventLogKindProcess,
    DebugEventLogKindLogpoint, DebugEventLogKindOther, DebugEventLogColumnTime, DebugEventLogColumnKind,
    DebugEventLogColumnThread, DebugEventLogColumnText, DebugEventLogGoTo, DebugEventLogCopy, DebugEventLogSave,
    DebugEventLogClear, DebugEventLogRememberFilter, DebugEventLogForgetFilter, DebugEventLogEmpty,
    DebugEventLogSummary, DebugEventLogInvalidRegex, DebugEventLogNotFound, DebugEventLogFileTypes,
    DebugEventLogSessionStarted, DebugEventLogSessionEnded, DebugEventLogModuleLoaded, DebugEventLogModuleUnloaded,
    DebugEventLogThreadStarted, DebugEventLogThreadEnded, DebugEventLogSaved);

  TAtlasEventLogStrings = class
  public
    class function Text(AId: TAtlasEventLogTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasEventLogTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasEventLogTextId] of string = (
    ('Atlas: Ereignisprotokoll',
     'Filtern: Wörter oder /Ausdruck/',
     'Alle Arten',
     'Ausgabe',
     'Haltepunkt',
     'Modul',
     'Thread',
     'Prozess',
     'Logpunkt',
     'Sonstiges',
     'Zeit',
     'Art',
     'Thread',
     'Text',
     'Zum Quelltext springen',
     'Zeile kopieren',
     'Als Textdatei speichern …',
     'Leeren',
     'Filter merken',
     'Gemerkten Filter entfernen',
     'Noch keine Ereignisse. Ausgaben (OutputDebugString), Module, Threads und Logpunkte der nächsten Debug-Sitzung erscheinen hier.',
     '%d von %d Einträgen',
     'Ungültiger Ausdruck: alle Einträge gezeigt',
     'Atlas: Sprungziel „%s“ nicht gefunden.',
     'Textdateien (*.txt)|*.txt|Alle Dateien (*.*)|*.*',
     'Sitzung gestartet: %s',
     'Sitzung beendet',
     'Modul geladen: %s',
     'Modul entladen: %s',
     'Thread gestartet',
     'Thread beendet',
     'Atlas: Ereignisprotokoll gespeichert: %s'),
    ('Atlas: Event log',
     'Filter: words or /expression/',
     'All kinds',
     'Output',
     'Breakpoint',
     'Module',
     'Thread',
     'Process',
     'Logpoint',
     'Other',
     'Time',
     'Kind',
     'Thread',
     'Text',
     'Go to source',
     'Copy line',
     'Save as text file …',
     'Clear',
     'Remember filter',
     'Forget remembered filter',
     'No events yet. Output (OutputDebugString), modules, threads and logpoints of the next debug session appear here.',
     '%d of %d entries',
     'Invalid expression: showing all entries',
     'Atlas: Jump target "%s" not found.',
     'Text files (*.txt)|*.txt|All files (*.*)|*.*',
     'Session started: %s',
     'Session ended',
     'Module loaded: %s',
     'Module unloaded: %s',
     'Thread started',
     'Thread ended',
     'Atlas: Event log saved: %s'));

{ TAtlasEventLogStrings }

class function TAtlasEventLogStrings.Text(AId: TAtlasEventLogTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasEventLogStrings.Fmt(AId: TAtlasEventLogTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
