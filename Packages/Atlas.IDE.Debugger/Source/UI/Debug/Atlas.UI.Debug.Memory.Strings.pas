unit Atlas.UI.Debug.Memory.Strings;

// Oberflächentexte des Speicherverlaufs (#858) im Modul Debugger, auf Deutsch und Englisch: Fenster „Atlas:
// Speicher“, Befehl, Meldungen und Einstellungen. Eigene Unit, weil Atlas.UI.Debug.Strings die Längengrenze
// erreicht. Die Sprache bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasMemoryTextId = (
    MemoryCommand, MemoryCaption, MemorySeriesPrivateBytes, MemorySeriesWorkingSet, MemorySeriesHandles,
    MemorySeriesGdiObjects, MemorySeriesUserObjects, MemoryMark, MemoryCopyCsv, MemoryClear, MemoryEmpty, MemoryNow,
    MemoryRange, MemoryRangeHint, MemoryMarkName, MemoryMarkStop, MemoryMarkException, MemoryCopied, MemoryOff,
    MemoryNoAccess, MemoryHover, SettingsDebugMemoryTimeline, SettingsDebugMemoryTimelineInterval);

  TAtlasMemoryStrings = class
  public
    class function Text(AId: TAtlasMemoryTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasMemoryTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasMemoryTextId] of string = (
    ('Speicherverlauf',
     'Atlas: Speicher',
     'Privater Speicher',
     'Arbeitssatz',
     'Handles',
     'GDI-Objekte',
     'USER-Objekte',
     'Marke setzen',
     'CSV kopieren',
     'Leeren',
     'Noch keine Messung. Der Verlauf beginnt mit der nächsten Debug-Sitzung.',
     'Jetzt: %s',
     'Bereich %s s bis %s s (%s s): %s',
     'Ziehen wählt einen Bereich und zeigt den Zuwachs; Doppelklick hebt die Wahl auf.',
     'Marke %d',
     'Halt',
     'Exception',
     'Atlas: Speicherverlauf als CSV kopiert (%d Messungen).',
     'Der Speicherverlauf ist ausgeschaltet (Tools › Optionen › Atlas › Debuggen).',
     'Atlas: Die Speicherwerte des Prozesses %d sind nicht lesbar (%s).',
     '%s s: %s',
     'Speicherverlauf beim Debuggen (Fenster „Atlas: Speicher“)',
     'Abstand der Messungen in ms:'),
    ('Memory timeline',
     'Atlas: Memory',
     'Private bytes',
     'Working set',
     'Handles',
     'GDI objects',
     'USER objects',
     'Add mark',
     'Copy CSV',
     'Clear',
     'No samples yet. The timeline starts with the next debug session.',
     'Now: %s',
     'Range %s s to %s s (%s s): %s',
     'Drag to select a range and see the growth; double-click clears the selection.',
     'Mark %d',
     'Stop',
     'Exception',
     'Atlas: Memory timeline copied as CSV (%d samples).',
     'The memory timeline is turned off (Tools › Options › Atlas › Debugging).',
     'Atlas: The memory values of process %d cannot be read (%s).',
     '%s s: %s',
     'Memory timeline while debugging (window “Atlas: Memory”)',
     'Interval between samples in ms:'));

{ TAtlasMemoryStrings }

class function TAtlasMemoryStrings.Text(AId: TAtlasMemoryTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasMemoryStrings.Fmt(AId: TAtlasMemoryTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
