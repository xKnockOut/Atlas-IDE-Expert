unit Atlas.UI.Debug.Memory.Strings;

// Oberflächentexte des Speicherverlaufs (#858) im Modul Debugger, auf Deutsch und Englisch: Fenster „Atlas:
// Speicher“ samt Objektzählung, Befehl, Meldungen und Einstellungen. Eigene Unit, weil Atlas.UI.Debug.Strings
// die Längengrenze erreicht. Die Sprache bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasMemoryTextId = (
    MemoryCommand, MemoryCaption, MemorySeriesPrivateBytes, MemorySeriesWorkingSet, MemorySeriesHandles,
    MemorySeriesGdiObjects, MemorySeriesUserObjects, MemoryMark, MemoryCopyCsv, MemoryClear, MemoryEmpty, MemoryNow,
    MemoryRange, MemoryRangeHint, MemoryMarkName, MemoryMarkStop, MemoryMarkException, MemoryCopied, MemoryOff,
    MemoryNoAccess, MemoryHover, SettingsDebugMemoryTimeline, SettingsDebugMemoryTimelineInterval,
    ObjectCountButton, ObjectCountFilter, ObjectCountColumnClass, ObjectCountColumnCount, ObjectCountColumnDelta,
    ObjectCountColumnBytes, ObjectCountSummary, ObjectCountCompared, ObjectCountHint, ObjectCountNotStopped,
    ObjectCountNoAccess, SettingsDebugMemoryTimelineObjectCount);

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
     'Abstand der Messungen in ms:',
     'Objekte zählen',
     'Klasse filtern',
     'Klasse',
     'Anzahl',
     'Zuwachs',
     'Größe',
     '%d Objekte in %d Klassen, %s Speicher gelesen.',
     'Zuwachs gegenüber der vorigen Zählung.',
     'Experimentell: zählt Verweise auf Klassen im Speicher des angehaltenen Programms (Näherung). Jede ' +
       'Zählung wird mit der vorigen verglichen.',
     'Objekte zählen geht nur, solange das Programm angehalten ist.',
     'Der Speicher des Prozesses %d ist nicht lesbar (%s).',
     'Objekte je Klasse zählen und vergleichen (experimentell)'),
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
     'Interval between samples in ms:',
     'Count objects',
     'Filter classes',
     'Class',
     'Count',
     'Change',
     'Size',
     '%d objects in %d classes, %s of memory read.',
     'Change against the previous count.',
     'Experimental: counts references to classes in the memory of the paused program (approximation). Each ' +
       'count is compared with the previous one.',
     'Counting objects only works while the program is paused.',
     'The memory of process %d cannot be read (%s).',
     'Count and compare objects per class (experimental)'));

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
