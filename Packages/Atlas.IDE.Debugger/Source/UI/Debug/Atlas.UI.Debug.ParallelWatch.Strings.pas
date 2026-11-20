unit Atlas.UI.Debug.ParallelWatch.Strings;

// Oberflächentexte für „Parallel auswerten“ (#866) im Modul Debugger, auf Deutsch und Englisch: Befehl, Fenster,
// Spalten, Leiste, Kontextmenü, Zustandszeile und Einstellung. Die Sprache bestimmt Base (`TAtlasStrings.Language`);
// jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasParallelWatchTextId = (
    SettingsDebugParallelWatch, ParallelWatchCaption, ParallelWatchCommand, ParallelWatchColumnThread,
    ParallelWatchColumnPlace, ParallelWatchAdd, ParallelWatchAddHint, ParallelWatchEvaluate, ParallelWatchShowAll,
    ParallelWatchRunning, ParallelWatchEmpty, ParallelWatchManual, ParallelWatchStatus, ParallelWatchEvaluating,
    ParallelWatchRename, ParallelWatchRemove, ParallelWatchFilter, ParallelWatchClearFilter, ParallelWatchRenameTitle,
    ParallelWatchRenamePrompt, ParallelWatchFilterTitle, ParallelWatchFilterPrompt, ParallelWatchFilterActive,
    ParallelWatchReading);

  TAtlasParallelWatchStrings = class
  public
    class function Text(AId: TAtlasParallelWatchTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasParallelWatchTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasParallelWatchTextId] of string = (
    ('Ausdrücke in allen Threads auswerten (Fenster „Parallel auswerten“)',
     'Parallel auswerten',
     'Parallel auswerten',
     'Thread',
     'Ort',
     'Hinzufügen',
     'Ausdruck, z. B. FAuftrag.Nr',
     'Auswerten',
     'Threads ohne eigenen Code zeigen',
     'Das Programm läuft. Werte erscheinen beim nächsten Halt.',
     'Ausdruck eingeben und „Hinzufügen“: Atlas wertet ihn in jedem Thread aus.',
     '%d Threads: Werte erst mit „Auswerten“.',
     '%d von %d Threads',
     'Werte %d von %d …',
     'Ausdruck ändern …',
     'Ausdruck entfernen',
     'Nur Zeilen mit …',
     'Filter aufheben',
     'Ausdruck ändern',
     'Ausdruck:',
     'Nur Zeilen mit …',
     'Zeilen, deren „%s“ enthält:',
     'Filter: „%s“ enthält „%s“',
     'Threads %d von %d …'),
    ('Evaluate expressions in all threads ("Parallel watch" window)',
     'Parallel watch',
     'Parallel watch',
     'Thread',
     'Location',
     'Add',
     'Expression, e.g. FOrder.No',
     'Evaluate',
     'Show threads without own code',
     'The program is running. Values appear at the next stop.',
     'Enter an expression and click "Add": Atlas evaluates it in every thread.',
     '%d threads: values only after "Evaluate".',
     '%d of %d threads',
     'Values %d of %d …',
     'Change expression …',
     'Remove expression',
     'Only rows with …',
     'Clear filter',
     'Change expression',
     'Expression:',
     'Only rows with …',
     'Rows whose "%s" contains:',
     'Filter: "%s" contains "%s"',
     'Threads %d of %d …'));

{ TAtlasParallelWatchStrings }

class function TAtlasParallelWatchStrings.Text(AId: TAtlasParallelWatchTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasParallelWatchStrings.Fmt(AId: TAtlasParallelWatchTextId; const AArgs: array of const): string;
begin
  Result := Format(Text(AId), AArgs);
end;

end.
