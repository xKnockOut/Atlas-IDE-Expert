unit Atlas.UI.Debug.Stepping.Strings;

// Texte zum Schrittbetrieb: Hineinspringen in ein Ziel, Schrittfilter, Stellen ohne Quelltext und Ausführen bis hier,
// auf Deutsch und Englisch (#1455). Die Sprache bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasSteppingTextId = (
    StepIntoTargetFooter, StepIntoTargetGetter, StepIntoTargetSetter, StepIntoTargetConstructor,
    StepIntoTargetInherited, StepIntoTargetNoSource, StepIntoTargetLibrary, StepIntoTargetCandidate,
    StepIntoTargetNotStopped, StepIntoTargetNoSourceAt, StepIntoTargetFailed, StepIntoTargetNotCalled,
    StepIntoTargetOff, StepIntoTargetElsewhere, StepIntoTargetNothing, RunToTipTitle, RunToTipText, RunToNotStopped,
    RunToNoEditor, RunToNoCode, RunToNoBreakpoint, RunToRestored, RunToOnceSet, RunToOnceExists, RunToOnceRemoved,
    StepFilterCaption, StepFilterOff, StepFilterNotStopped, StepFilterNoRoutine, StepFilterFailed, StepFilterAdded,
    StepFilterAlready, StepFilterRemoved, StepFilterStillByPattern, StepFilterStillByKind, StepFilterNotSkipped,
    StepFilterEnabled, StepFilterKindsHeader, StepFilterPatternsHeader, StepFilterColumnPattern, StepFilterColumnHits,
    StepFilterPatternHint, StepFilterAdd, StepFilterRemove, StepFilterRefresh, StepFilterCounting, StepFilterSummary,
    StepFilterTruncated, StepFilterNoCounts, StepFilterSession, StepFilterLast, StepFilterShiftHint,
    StepFilterByPattern, StepFilterInactive, NoSourceTitle, NoSourcePlace, NoSourceUnit, NoSourceUnknown,
    NoSourceDebugDcusOff, NoSourceNoDebugInfo, NoSourceDcuOnly, NoSourceNotInPath, NoSourceSystem, NoSourceEnableDcus,
    NoSourceReturn, NoSourceFind, NoSourceKeepCpu, NoSourceIgnore, NoSourceFindTitle, NoSourceFound, NoSourceNotFound,
    NoSourceIgnored, NoSourceReturning,
    StepFilterKindGetters, StepFilterKindSetters, StepFilterKindTrivial, StepFilterKindOperators,
    StepFilterKindEmptyConstructors);

  TAtlasSteppingStrings = class
  public
    class function Text(AId: TAtlasSteppingTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasSteppingTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasSteppingTextId] of string = (
    ('↑/↓ und Enter oder 1–9 wählen  ·  Esc schließt',
     'Getter',
     'Setter',
     'Konstruktor',
     'inherited',
     'ohne Quelltext',
     'ohne Debug-DCUs',
     'Überschreibung',
     'Gezielt hineinspringen geht nur, solange das Programm angehalten ist.',
     'Gezielt hineinspringen: Am Ausführungspunkt steht kein Quelltext.',
     'Gezielt hineinspringen: %s',
     'Gezielt hineinspringen: %s wurde nicht aufgerufen; angehalten bei der Folgeanweisung (Zeile %d).',
     'Gezielt hineinspringen ist ausgeschaltet (Tools › Optionen › Atlas › Debuggen).',
     'Gezielt hineinspringen: Das Programm hielt vorher an einer anderen Stelle (%s:%d); die vorübergehenden Haltepunkte sind entfernt.',
     'Gezielt hineinspringen: Kein wählbarer Aufruf in dieser Anweisung; Schritt wie F7.',
     'Bis hier ausführen',
     'Klick: bis Zeile %d ausführen.'#13#10 +
     'Strg+Klick: ohne Halt an anderen Haltepunkten.'#13#10 +
     'Rechtsklick: weitere Befehle.',
     'Bis hier: Das Programm ist nicht angehalten.',
     'Bis hier: Kein Quelltext im Editor.',
     'Bis hier: Zeile %d hat keinen ausführbaren Code.',
     'Bis hier: In Zeile %d lässt sich kein Haltepunkt setzen.',
     'Bis hier: %d Haltepunkte wieder im alten Zustand.',
     'Einmaliger Haltepunkt in Zeile %d gesetzt.',
     'In Zeile %d steht schon ein Haltepunkt.',
     'Einmaliger Haltepunkt %s:%d nach dem Halt entfernt.',
     'Schrittfilter',
     'Schrittfilter sind aus (debug.stepFilters).',
     'Trotzdem hineinspringen: Das Programm ist nicht angehalten.',
     'Schrittfilter: An der Schreibmarke steht keine Methode.',
     'Schrittfilter: Die Anfrage an den Server ist gescheitert (%s).',
     'Schrittfilter: %s wird beim Hineinspringen übersprungen.',
     'Schrittfilter: %s wird schon übersprungen (%s).',
     'Schrittfilter: %s wird nicht mehr übersprungen.',
     'Schrittfilter: %s wird weiter über das Muster %s übersprungen; entfernen im Fenster „Schrittfilter“.',
     'Schrittfilter: %s wird weiter übersprungen (%s); die Art im Fenster „Schrittfilter“ abwählen.',
     'Schrittfilter: %s wird nicht übersprungen.',
     'Schrittfilter an',
     'Arten eigener Routinen',
     'Muster',
     'Muster',
     'Treffer',
     'Unit.Klasse.Methode, * als Platzhalter (*.Log*, TBasisForm.*)',
     'Hinzufügen',
     'Entfernen',
     'Neu zählen',
     'Zähle im Index …',
     '%d Routinen in %d Dateien des Projekts',
     ' (nur die ersten %d Dateien)',
     'Treffer gibt es erst mit laufendem Server.',
     'In dieser Debug-Sitzung übersprungen: %d',
     ' · zuletzt %s (%s)',
     'Umschalt+F7 springt einmal ohne Filter hinein; ein Haltepunkt in einer übersprungenen Routine greift wie gewohnt.',
     'Muster %s',
     'Der Ablauf ist aus: debug.stepFilters einschalten oder Atlas nicht abgesichert starten.',
     'Kein Quelltext: %s',
     'Modul %s · Adresse %s',
     'Unit %s',
     'unbekannt',
     'Debug-DCUs aus: Die Bibliothek von Delphi ist ohne Zeilennummern übersetzt.',
     'Die Unit ist ohne Debug-Informationen übersetzt ({$D-}).',
     'Die Bibliothek ist nur als DCU/BPL vorhanden, ohne Quelltext.',
     'Der Quelltext liegt nicht im Suchpfad des Debuggers.',
     'Systemcode (Windows): dazu gibt es keinen Quelltext.',
     'Debug-DCUs einschalten und neu bauen',
     'Zurück zum eigenen Code',
     'Quelltext suchen …',
     'CPU-Fenster behalten',
     'Für diese Unit nicht mehr zeigen',
     'Ordner mit %s',
     'Atlas: Quelltext gefunden, der Ordner gilt ab jetzt für das Projekt: %s',
     'Atlas: %s liegt nicht im Ordner %s.',
     'Atlas: Fenster „Kein Quelltext“ für %s abgeschaltet (Liste unter debug.noSourcePage.ignoredUnits).',
     'Atlas: Läuft bis zur Rückkehr in eigenen Code …',
     'Getter von Eigenschaften (eine Anweisung)',
     'Setter von Eigenschaften (eine Anweisung)',
     'Triviale Routinen (nur eine Zuweisung an Result oder ein Feld)',
     'Klassen-Operatoren (class operator)',
     'Konstruktoren und Destruktoren, die nur inherited aufrufen'),
    ('↑/↓ and Enter or 1–9 to choose  ·  Esc closes',
     'getter',
     'setter',
     'constructor',
     'inherited',
     'no source',
     'no debug DCUs',
     'override',
     'Step into specific call works only while the program is paused.',
     'Step into specific call: there is no source at the execution point.',
     'Step into specific call: %s',
     'Step into specific call: %s was not called; stopped at the next statement (line %d).',
     'Step into specific call is turned off (Tools › Options › Atlas › Debugging).',
     'Step into specific call: the program stopped elsewhere first (%s:%d); the temporary breakpoints are removed.',
     'Step into specific call: no call to choose in this statement; stepping like F7.',
     'Run to here',
     'Click: run to line %d.'#13#10 +
     'Ctrl+click: do not stop at other breakpoints.'#13#10 +
     'Right-click: more commands.',
     'Run to here: the program is not paused.',
     'Run to here: no source file in the editor.',
     'Run to here: line %d has no executable code.',
     'Run to here: a breakpoint cannot be set at line %d.',
     'Run to here: %d breakpoints restored.',
     'One-time breakpoint set at line %d.',
     'Line %d already has a breakpoint.',
     'One-time breakpoint %s:%d removed after the stop.',
     'Step filters',
     'Step filters are off (debug.stepFilters).',
     'Step into anyway: the program is not paused.',
     'Step filters: there is no method at the cursor.',
     'Step filters: the request to the server failed (%s).',
     'Step filters: %s is skipped when stepping into.',
     'Step filters: %s is already skipped (%s).',
     'Step filters: %s is no longer skipped.',
     'Step filters: %s is still skipped by the pattern %s; remove it in the Step filters window.',
     'Step filters: %s is still skipped (%s); clear that kind in the Step filters window.',
     'Step filters: %s is not skipped.',
     'Step filters on',
     'Kinds of own routines',
     'Patterns',
     'Pattern',
     'Matches',
     'Unit.Class.Method, * as wildcard (*.Log*, TBaseForm.*)',
     'Add',
     'Remove',
     'Count again',
     'Counting in the index …',
     '%d routines in %d project files',
     ' (first %d files only)',
     'Matches need a running server.',
     'Skipped in this debug session: %d',
     ' · last %s (%s)',
     'Shift+F7 steps in once without filters; a breakpoint in a skipped routine stops as usual.',
     'pattern %s',
     'Not active: turn on debug.stepFilters or start Atlas in normal mode.',
     'No source: %s',
     'Module %s · address %s',
     'Unit %s',
     'unknown',
     'Debug DCUs off: the Delphi library is compiled without line numbers.',
     'The unit is compiled without debug information ({$D-}).',
     'The library is only available as DCU/BPL, without source.',
     'The source is not in the debugger''s search path.',
     'System code (Windows): there is no source for it.',
     'Turn on debug DCUs and rebuild',
     'Back to my code',
     'Find source …',
     'Keep CPU window',
     'Do not show for this unit again',
     'Folder containing %s',
     'Atlas: Source found, the folder now applies to the project: %s',
     'Atlas: %s is not in folder %s.',
     'Atlas: “No source” window turned off for %s (list under debug.noSourcePage.ignoredUnits).',
     'Atlas: Running until it returns to my code …',
     'Property getters (one statement)',
     'Property setters (one statement)',
     'Trivial routines (one assignment to Result or a field)',
     'Class operators (class operator)',
     'Constructors and destructors that only call inherited'));

{ TAtlasSteppingStrings }

class function TAtlasSteppingStrings.Text(AId: TAtlasSteppingTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasSteppingStrings.Fmt(AId: TAtlasSteppingTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
