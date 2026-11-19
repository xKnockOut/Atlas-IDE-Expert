unit Atlas.UI.Debug.Commands.Strings;

// Namen der Befehle des Debuggers und ihrer Menügruppen im Editor-Kontextmenü und im Hauptmenü Atlas, auf Deutsch und
// Englisch (#1455). Die Sprache bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasDebugCommandsTextId = (
    EventBreakCommand, MethodBreakpointsCommand, MethodBreakpointsGroupsCommand, InstanceObjectCommand,
    InstanceFieldCommand, BreakpointCheckCommand, BreakpointSetSaveCommand, BreakpointSetSwitchCommand,
    BreakpointSetAddCommand, BreakpointSetDeleteCommand, RunToHereCommand, RunToSkipCommand, RunToOnceCommand,
    BreakpointsWindowCommand, BreakpointAnchorsUndoCommand, BreakpointAnchorsOrphansCommand, BreakpointRulesCommand,
    DebugExceptionsCommand, DebugExceptionRulesCommand, DebugJustMyCodeCommand, DebugBannerIdeDialogCommand,
    DebugExpressionHistory,
    DebugEvaluateCommand, DebugEvaluateIdeDialogCommand, DebugWaitsCommand, ParallelStacksCommand, CallStackCommand,
    ThreadMarksFlagCommand, ThreadMarksFreezeCommand, ThreadMarksThawCommand, ThreadMarksThawAllCommand,
    StepFilterWindowCommand, StepFilterStepIntoAnywayCommand, StepFilterSkipCommand, StepFilterUnskipCommand,
    DebugEditorMenuGroup, EditValueCommand, EditValueUndoCommand, DebugEventLogCommand, LogpointCommand,
    LogpointDisableAll, LogpointEnableAll, LogpointDeleteAll, RestartCommand, ReattachCommandPlain,
    ReattachWaitCommand, RuntimeReportPasteCommand, RuntimeReportClearCommand, LaunchCommandWindow, LaunchCommandRun,
    LaunchCommandStop,
    // Untermenü „Haltepunkte“ im Hauptmenü Atlas.
    MenuGroupBreakpoints);

  TAtlasDebugCommandsStrings = class
  public
    class function Text(AId: TAtlasDebugCommandsTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasDebugCommandsTextId; const AArgs: array of const): string; static;
    /// <summary>Name des Befehls Atlas.StepIntoTarget; der Text liegt in Base, weil ihn auch die Tastenbelegung
    /// und die Willkommensseite zeigen.</summary>
    class function StepIntoTargetCommand: string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasDebugCommandsTextId] of string = (
    ('Beim nächsten Ereignis anhalten…',
     'Haltepunkt auf Methoden …',
     'Haltepunktgruppen der Methoden …',
     'Haltepunkt nur für dieses Objekt',
     'Haltepunkt nur wenn …',
     'Haltepunkte prüfen',
     'Haltepunkte als Satz speichern …',
     'Haltepunkt-Satz wechseln …',
     'Haltepunkt-Satz hinzufügen …',
     'Haltepunkt-Satz löschen …',
     'Bis hier ausführen',
     'Bis hier, Haltepunkte überspringen',
     'Einmaliger Haltepunkt',
     'Haltepunkte (Atlas) …',
     'Haltepunkte zurück an alte Zeilen',
     'Verwaiste Haltepunkte …',
     'Haltepunkt-Regeln …',
     'Atlas: Exception-Verlauf',
     'Atlas: Exception-Regeln …',
     'Atlas: Nur eigener Code beim Debuggen umschalten',
     'Atlas: Exception-Dialog der IDE in dieser Debug-Sitzung zeigen',
     'Verlauf',
     'Atlas: Auswerten …',
     'Atlas: Auswerten/Ändern (IDE-Dialog)',
     'Was wartet worauf?',
     'Parallele Aufrufstapel',
     'Atlas-Aufrufstapel',
     'Thread markieren',
     'Thread einfrieren (experimentell)',
     'Thread auftauen',
     'Alle Threads auftauen',
     'Schrittfilter…',
     'Trotzdem hineinspringen (ohne Schrittfilter)',
     'Beim Hineinspringen überspringen',
     'Nicht mehr überspringen',
     'Debuggen',
     'Atlas: Wert ändern',
     'Atlas: Geänderten Wert zurücksetzen',
     'Atlas: Ereignisprotokoll',
     'Atlas: Logpunkt setzen',
     'Atlas: Alle Logpunkte aus',
     'Atlas: Alle Logpunkte an',
     'Atlas: Alle Logpunkte löschen',
     'Atlas: Neu starten',
     'Atlas: Erneut an Prozess anhängen',
     'Atlas: Anhängen, sobald gestartet …',
     'Absturz- oder Leckbericht einfügen …',
     'Markierungen des Laufzeitberichts entfernen',
     'Atlas: Startverbünde …',
     'Atlas: Startverbund starten',
     'Atlas: Startverbund beenden',
     'Haltepunkte'),
    ('Break on next event…',
     'Breakpoint on methods …',
     'Method breakpoint groups …',
     'Breakpoint only for this object',
     'Breakpoint only if …',
     'Check breakpoints',
     'Save breakpoints as set …',
     'Switch breakpoint set …',
     'Add breakpoint set …',
     'Delete breakpoint set …',
     'Run to here',
     'Run to here, skip breakpoints',
     'One-time breakpoint',
     'Breakpoints (Atlas) …',
     'Move breakpoints back to their old lines',
     'Orphaned breakpoints …',
     'Breakpoint rules …',
     'Atlas: Exception history',
     'Atlas: Exception rules …',
     'Atlas: Toggle just my code while debugging',
     'Atlas: Show the IDE exception dialog in this debug session',
     'History',
     'Atlas: Evaluate …',
     'Atlas: Evaluate/Modify (IDE dialog)',
     'What is waiting for what?',
     'Parallel stacks',
     'Atlas call stack',
     'Flag thread',
     'Freeze thread (experimental)',
     'Thaw thread',
     'Thaw all threads',
     'Step filters…',
     'Step into anyway (without step filters)',
     'Skip when stepping into',
     'Stop skipping',
     'Debugging',
     'Atlas: Change value',
     'Atlas: Reset changed value',
     'Atlas: Event log',
     'Atlas: Set logpoint',
     'Atlas: Disable all logpoints',
     'Atlas: Enable all logpoints',
     'Atlas: Delete all logpoints',
     'Atlas: Restart',
     'Atlas: Reattach to process',
     'Atlas: Attach when started …',
     'Paste crash or leak report …',
     'Remove runtime report markers',
     'Atlas: Launch groups …',
     'Atlas: Start launch group',
     'Atlas: Stop launch group',
     'Breakpoints'));

{ TAtlasDebugCommandsStrings }

class function TAtlasDebugCommandsStrings.Text(AId: TAtlasDebugCommandsTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasDebugCommandsStrings.Fmt(AId: TAtlasDebugCommandsTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

class function TAtlasDebugCommandsStrings.StepIntoTargetCommand: string;
begin
  Result := TAtlasStrings.Text(TAtlasTextId.StepIntoTargetCommand);
end;

end.
