unit Atlas.UI.Debug.Settings.Strings;

// Texte der Einstellungsseite „Debugger“: Abschnitte, Schalter und Felder aller Debugger-Funktionen, auf Deutsch und
// Englisch (#1455). Die Sprache bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasDebugSettingsTextId = (
    SettingsDebugDataBreakpoints, SettingsDebugMethodBreakpoints, SettingsDebugInstanceBreakpoints,
    SettingsDebugCheckBreakpoints, SettingsDebugBreakpointSetPerBranch, SettingsDebugRunToClick,
    SettingsDebugBreakpointsWindow, SettingsDebugBreakpointAnchors, SettingsDebugBreakpointRules,
    SettingsDebugHoverValues, SettingsDebugVisualizers, SettingsDebugVisualizerNameFields,
    SettingsDebugVisualizerMaxLength, SettingsDebugVisualizerTimeout, SettingsDebugVisualizerMaxImagePixels,
    SettingsDebugVisualizerEvaluation, SettingsDebugDisplayRules, SettingsDebugDisplayRulesAllowCalls,
    SettingsDebugStepIntoTarget, SettingsDebugBreakOnNextEvent, SettingsDebugBreakOnNextEventExcluded,
    SettingsDebugExceptionHistory, SettingsDebugJustMyCode, SettingsDebugOwnCodeFolders, SettingsDebugExceptionBanner,
    SettingsDebugExceptionBannerIgnoreAtLocation, SettingsDebugInlineValues, SettingsDebugInlineValuesPerLine,
    SettingsDebugExplainUnavailable, SettingsDebugCompletionInDialogs, SettingsDebugEvaluateWindow,
    SettingsDebugEvaluateReplaceCtrlF7, SettingsDebugExplainAccessViolation,
    SettingsDebugExplainAccessViolationAllowCalls, SettingsDebugModuleOfAddress, SettingsDebugDeadlocks,
    SettingsDebugParallelStacks, SettingsDebugParallelStacksWaitRoutines, SettingsDebugParallelStacksMaxThreads,
    SettingsDebugCallStackWindow, SettingsDebugCallStackWindowEvaluateParams, SettingsDebugThreadsInSource,
    SettingsDebugThreadFreeze, SettingsDebugAsyncOrigin, SettingsDebugAsyncOriginMaxPerSite, SettingsDebugStepFilters,
    SettingsDebugStepFilterPatterns, SettingsDebugWhyHere, SettingsDebugWhyHereDepth, SettingsDebugPredict,
    SettingsDebugPredictDim, SettingsDebugPredictLines, SettingsDebugEditValues, SettingsDebugEventLog,
    SettingsDebugEventLogColors, SettingsDebugLogpoints, SettingsDebugLogpointPrefix, SettingsDebugNoSourcePage,
    SettingsDebugNoSourceIgnored, SettingsDebugRestart, SettingsDebugRestartReenable, SettingsDebugReattach,
    SettingsDebugReattachKey, SettingsDebugReattachWait, SettingsDebugLaunchGroups, SettingsDebugPinnedValues,
    SettingsDebugHoverExpand, SettingsDebugHoverChanges, SettingsDebugHoverMaxChildren,
    SettingsDebugExceptionMessageRules, SettingsDebugExceptionRules);

  TAtlasDebugSettingsStrings = class
  public
    class function Text(AId: TAtlasDebugSettingsTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasDebugSettingsTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasDebugSettingsTextId] of string = (
    ('Anhalten, wenn sich ein Feld ändert (Kontextmenü des Editors)',
     'Haltepunkte auf Methoden nach Muster',
     'Haltepunkt nur für ein Objekt oder einen Feldwert (Kontextmenü des Editors)',
     'Haltepunkte vor dem Start prüfen (Zeile ohne Code, inaktiver Zweig, $D-)',
     'Haltepunkt-Satz beim Branch-Wechsel mitwechseln',
     'Bis hier ausführen per Klick im Rand (▶) und Befehle „Bis hier“',
     'Haltepunktfenster mit Suche, Etiketten und Trefferzahlen',
     'Haltepunkte nach Änderungen von außen nachziehen',
     'Abhängige Haltepunkte, Trefferbedingungen und Thread-Filter',
     'Variablenwerte im Hover beim Debuggen',
     'Visualisierer für häufige Typen',
     'Namensfelder für Objekte in Listen',
     'Höchstlänge des Ersatztexts (Zeichen)',
     'Zeitlimit je Auswertung (ms)',
     'Größtes Bild im Ansichtsfenster (Pixel)',
     'Auswertung im Programm',
     'Eigene Wertdarstellungen (// atlas-debug:, [AtlasDebugDisplay], Projektdatei)',
     'Getter und Funktionsaufrufe in Vorlagen erlauben',
     'Gezielt hineinspringen (Strg+Alt+F7: einen Aufruf der Anweisung wählen)',
     'Beim nächsten Ereignis anhalten (Menü Start und Befehlspalette)',
     'Häufige Ereignisse, nur auf ausdrückliche Wahl (kommagetrennt)',
     'Exception-Verlauf beim Debuggen (Fenster „Atlas: Exceptions“)',
     'Nur eigener Code beim Debuggen (Sprung in eigenen Code, F7 überspringt Code ohne Quelltext)',
     'Weitere Ordner mit eigenem Code (durch ; getrennt):',
     'Exception-Meldung als Leiste am Editor statt als Dialog (Delphi 12 und 13)',
     'Knopf „Nur an dieser Stelle ignorieren“',
     'Werte im Editor beim Debuggen (am Zeilenende, solange der Prozess angehalten ist)',
     'Höchstens Werte je Zeile:',
     '„kein Zugriff“ beim Debuggen erklären (Ursache und Korrekturen)',
     'Vervollständigung in Debugger-Dialogen (Auswerten, Überwachung, Haltepunkt)',
     'Fenster „Auswerten“ (mehrere Ausdrücke, Baum, Ansichten, Ändern)',
     'Strg+F7 öffnet das Atlas-Fenster statt „Auswerten/Ändern“',
     'Zugriffsverletzungen erklären (welcher Teil war nil)',
     'Getter und Funktionsaufrufe bei der Auswertung erlauben',
     'Modul der Fehleradresse nennen (Programm, RTL/VCL, Windows, Fremd-DLL)',
     'Befehl „Was wartet worauf?“: Wartepunkte aller Threads und Verklemmungen',
     'Fenster „Parallele Aufrufstapel“ (Stapel aller Threads als Baum)',
     'Warte-Routinen (durch ; getrennt, leer = Vorgabe):',
     'Ab so vielen Threads Stapel abschnittsweise lesen:',
     'Fenster „Atlas-Aufrufstapel“ (Parameter, Suche, Kopieren, Vergleich mit dem letzten Halt)',
     'Parameter einzeln auswerten (sonst die Werte aus dem Aufrufstack der IDE)',
     'Threads im Quelltext (andere Threads im Rand, Threads markieren)',
     'Threads einfrieren und auftauen (experimentell)',
     'Herkunft eingereihter Methoden merken (experimentell)',
     'Gemerkte Einreihungen je Aufrufstelle',
     'Schrittfilter beim Hineinspringen (F7)',
     'Weitere Methoden überspringen (Unit.Klasse.Methode, * als Platzhalter, durch ; getrennt):',
     '„Warum bin ich hier?“: Werte der umgebenden Bedingungen beim Halt',
     'Umgebende Blöcke (1 bis 10)',
     'Bedingungen vorausschauen: vorhergesagtes Ergebnis der kommenden if, while und case',
     'Übersprungene Zweige blass zeichnen',
     'Zeilen voraus (1 bis 200)',
     'Werte im Hover und im Editor ändern („Ändern …“, F2)',
     'Ereignisprotokoll beim Debuggen',
     'Farben im Ereignisprotokoll (Muster=Farbe; …)',
     'Logpunkte (Umschalt+F5)',
     'Präfix der Logpunkte',
     'Fenster „Kein Quelltext“',
     'Units ohne Fenster „Kein Quelltext“',
     'Neu starten (Strg+Umschalt+F2)',
     'Abgeschaltete Haltepunkte wieder einschalten',
     'Erneut an Prozess anhängen',
     'Erneut anhängen',
     'Abstand der Abfragen beim Warten (ms)',
     'Startverbünde (F9 startet den aktiven Verbund)',
     'Werte aus dem Hover anheften',
     'Werte im Debug-Hover aufklappbar',
     'Seit dem letzten Halt geänderte Werte markieren',
     'Höchstzahl Kinder je Ebene',
     'Exceptions nach Meldungstext anhalten oder fortsetzen',
     'Exception-Regeln nach Klasse und Ort'),
    ('Break when a field changes (editor context menu)',
     'Breakpoints on methods by pattern',
     'Breakpoint only for one object or field value (editor context menu)',
     'Check breakpoints before starting (line without code, inactive branch, $D-)',
     'Switch the breakpoint set together with the branch',
     'Run to here by clicking the margin (▶) and "Run to here" commands',
     'Breakpoints window with search, tags and hit counts',
     'Move breakpoints along after outside changes',
     'Dependent breakpoints, hit conditions and thread filters',
     'Variable values in the hover while debugging',
     'Visualizers for common types',
     'Name fields for objects in lists',
     'Maximum length of the replacement text (characters)',
     'Time limit per evaluation (ms)',
     'Largest image in the viewer (pixels)',
     'Evaluation in the program',
     'Custom value display (// atlas-debug:, [AtlasDebugDisplay], project file)',
     'Allow getters and function calls in templates',
     'Step into specific call (Ctrl+Alt+F7: choose a call of the statement)',
     'Break on next event (Run menu and command palette)',
     'Frequent events, only when chosen explicitly (comma-separated)',
     'Exception history while debugging (window “Atlas: Exceptions”)',
     'Just my code while debugging (jump to own code, F7 skips code without source)',
     'More folders with own code (separated by ;):',
     'Exception message as a bar on the editor instead of a dialog (Delphi 12 and 13)',
     'Button “Ignore only here”',
     'Inline values while debugging (at the end of the line while the process is stopped)',
     'At most values per line:',
     'Explain "no access" while debugging (cause and fixes)',
     'Completion in debugger dialogs (evaluate, watch, breakpoint)',
     'Evaluate window (several expressions, tree, views, modify)',
     'Ctrl+F7 opens the Atlas window instead of Evaluate/Modify',
     'Explain access violations (which part was nil)',
     'Allow getters and function calls during evaluation',
     'Name the module of the fault address (program, RTL/VCL, Windows, third-party DLL)',
     'Command “What is waiting for what?”: wait points of all threads and deadlocks',
     'Window “Parallel Stacks” (call stacks of all threads as a tree)',
     'Wait routines (separated by ;, empty = default):',
     'Read call stacks in portions from this many threads:',
     'Window “Atlas Call Stack” (parameters, search, copy, compare with the last stop)',
     'Evaluate parameters one by one (otherwise the values from the IDE call stack)',
     'Threads in source (other threads in the gutter, flag threads)',
     'Freeze and thaw threads (experimental)',
     'Remember the origin of queued methods (experimental)',
     'Remembered calls per call site',
     'Step filters when stepping into (F7)',
     'Also skip methods (Unit.Class.Method, * as wildcard, separated by ;):',
     '“Why am I here?”: values of the enclosing conditions when stopped',
     'Enclosing blocks (1 to 10)',
     'Predict upcoming conditions: forecast result of the next if, while and case',
     'Dim skipped branches',
     'Lines ahead (1 to 200)',
     'Change values in the hover and in the editor (“Change …”, F2)',
     'Event log while debugging',
     'Event log colors (pattern=color; …)',
     'Logpoints (Shift+F5)',
     'Logpoint prefix',
     '“No source” window',
     'Units without “No source” window',
     'Restart (Ctrl+Shift+F2)',
     'Turn disabled breakpoints on again',
     'Reattach to process',
     'Reattach',
     'Polling interval while waiting (ms)',
     'Launch groups (F9 starts the active group)',
     'Pin values from the hover',
     'Expandable values in the debug hover',
     'Mark values changed since the last stop',
     'Maximum children per level',
     'Stop or continue exceptions by message text',
     'Exception rules by class and place'));

{ TAtlasDebugSettingsStrings }

class function TAtlasDebugSettingsStrings.Text(AId: TAtlasDebugSettingsTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasDebugSettingsStrings.Fmt(AId: TAtlasDebugSettingsTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
