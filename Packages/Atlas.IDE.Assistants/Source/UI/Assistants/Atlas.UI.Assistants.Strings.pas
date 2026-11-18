unit Atlas.UI.Assistants.Strings;

// Oberflächentexte des Moduls KI-Assistenten auf Deutsch und Englisch (#1888, Muster der Module). Die Sprache
// bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu. Kerntexte bleiben in `Atlas.UI.Strings`.

interface

{$SCOPEDENUMS ON}

type
  TAtlasAssistantsTextId = (
    BuildStarted, BuildFinished, BuildRefused, RequestUnreadable, RequestNoProject, RequestUnknownMode,
    NoBuildPipeline, SettingsEdit, SettingsMcpBuild,
    McpEditApplied, UndoActionMcp,
    DebugUnknownCommand, DebugRefusedPaused, DebugRefusedUserSession, DebugRefusedRunning, DebugRefusedNoProgram,
    DebugRefusedNotStopped, DebugRefusedSideEffects, DebugRefusedModify, DebugNoDebugger, DebugSwitchedOff,
    DebugTakenOver, DebugNeedsSideEffects, DebugNoBreakpoint, DebugStarted,
    SettingsDebugMcp, SettingsDebugSideEffects, SettingsDebugModify, SettingsDebugAttach, SettingsDebugBanner,
    DebugBarText, DebugBarPausedText, DebugBarClient, DebugBarPause, DebugBarResume, DebugBarTakeOver,
    DebugBarPauseHint, DebugBarResumeHint, DebugBarTakeOverHint);

  TAtlasAssistantsStrings = class
  public
    class function Text(AId: TAtlasAssistantsTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasAssistantsTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasAssistantsTextId] of string = (
    ('Ein KI-Assistent baut %s in der IDE …',
     'Build für den KI-Assistenten beendet: %s, %d Fehler',
     'Build für den KI-Assistenten abgelehnt: %s (%s)',
     'Auftrag nicht lesbar',
     'Auftrag ohne Projekt',
     'Unbekannte Art "%s"; erlaubt sind make, build und check',
     'Das Modul Build-Pipeline ist nicht geladen oder abgeschaltet',
     'KI-Assistenten dürfen in offene Dateien schreiben (über den Editorpuffer)',
     'Builds für KI-Assistenten (MCP) über diese IDE erlauben (build_project)',
     'Atlas: MCP-Änderung in %s übernommen (Strg+Z macht sie rückgängig).',
     'Änderung über MCP',
     'Unbekannter Debug-Auftrag "%s"',
     'Der Benutzer hat „Pause für KI“ gedrückt; Aufträge werden abgelehnt, bis er „Fortsetzen“ wählt.',
     'Der Benutzer debuggt selbst. Ein KI-Assistent übernimmt seine Sitzung nur, wenn die Einstellung ' +
       '„Laufende Sitzung des Benutzers übernehmen“ an ist.',
     'Es läuft schon ein Programm im Debugger; mit debug_state lesen oder mit debug_stop beenden.',
     'Kein Programm im Debugger; zuerst debug_start.',
     'Das Programm läuft; erst bei einem Halt (debug_continue oder debug_state abwarten).',
     'Ausdrücke mit Aufrufen hat der Benutzer nicht erlaubt (Einstellung „Ausdrücke mit Aufrufen“); ohne ' +
       'sideEffects auswerten oder den Benutzer fragen.',
     'Werte ändern hat der Benutzer nicht erlaubt (Einstellung „Werte ändern“); den Benutzer fragen.',
     'Das Modul Debugger ist nicht geladen oder abgeschaltet.',
     'Debuggen durch KI-Assistenten wurde in der IDE abgeschaltet.',
     'Der Benutzer hat die Debug-Sitzung übernommen.',
     'Ohne sideEffects wertet der Debugger keine Aufrufe aus.',
     'Einen Haltepunkt %d des KI-Assistenten gibt es nicht.',
     'Ein KI-Assistent debuggt %s …',
     'Debuggen durch KI-Assistenten (MCP) erlauben (debug_start, debug_step, debug_evaluate …)',
     'Ausdrücke mit Aufrufen (Getter, Funktionen) erlauben',
     'Werte ändern erlauben (Zuweisungen in debug_evaluate)',
     'Laufende Sitzung des Benutzers übernehmen',
     'Leiste zeigen, solange ein KI-Assistent den Debugger steuert',
     '%s debuggt · %d Aufträge · zuletzt %s',
     'Pause für KI: Aufträge von KI-Assistenten werden abgelehnt.',
     'Ein KI-Assistent',
     'Pause für KI',
     'Fortsetzen',
     'Übernehmen',
     'Aufträge von KI-Assistenten ablehnen, bis „Fortsetzen“ gedrückt wird',
     'Aufträge von KI-Assistenten wieder annehmen',
     'Sitzung selbst weiterführen; der KI-Assistent ist getrennt, seine Haltepunkte bleiben'),
    ('An AI assistant is building %s in the IDE …',
     'Build for the AI assistant finished: %s, %d errors',
     'Build for the AI assistant refused: %s (%s)',
     'Request not readable',
     'Request without project',
     'Unknown mode "%s"; allowed are make, build and check',
     'The build pipeline module is not loaded or switched off',
     'AI assistants may write to open files (through the editor buffer)',
     'Allow builds for AI assistants (MCP) in this IDE (build_project)',
     'Atlas: MCP change applied to %s (Ctrl+Z undoes it).',
     'Change through MCP',
     'Unknown debug request "%s"',
     'The user pressed "Pause for AI"; requests are refused until they choose "Resume".',
     'The user is debugging. An AI assistant takes over their session only if the setting "Take over the user''s ' +
       'running session" is on.',
     'A program is already running in the debugger; read it with debug_state or end it with debug_stop.',
     'No program in the debugger; call debug_start first.',
     'The program is running; only when it stops (wait with debug_continue or debug_state).',
     'The user has not allowed expressions with calls (setting "Expressions with calls"); evaluate without ' +
       'sideEffects or ask the user.',
     'The user has not allowed changing values (setting "Change values"); ask the user.',
     'The debugger module is not loaded or switched off.',
     'Debugging by AI assistants was switched off in the IDE.',
     'The user has taken over the debug session.',
     'Without sideEffects the debugger does not evaluate calls.',
     'There is no breakpoint %d of the AI assistant.',
     'An AI assistant is debugging %s …',
     'Allow debugging by AI assistants (MCP) (debug_start, debug_step, debug_evaluate …)',
     'Allow expressions with calls (getters, functions)',
     'Allow changing values (assignments in debug_evaluate)',
     'Take over the user''s running session',
     'Show the bar while an AI assistant controls the debugger',
     '%s is debugging · %d requests · last %s',
     'Pause for AI: requests from AI assistants are refused.',
     'An AI assistant',
     'Pause for AI',
     'Resume',
     'Take over',
     'Refuse requests from AI assistants until "Resume" is pressed',
     'Accept requests from AI assistants again',
     'Continue the session yourself; the AI assistant is disconnected, its breakpoints stay'));

{ TAtlasAssistantsStrings }

class function TAtlasAssistantsStrings.Text(AId: TAtlasAssistantsTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasAssistantsStrings.Fmt(AId: TAtlasAssistantsTextId; const AArgs: array of const): string;
begin
  Result := Format(Text(AId), AArgs);
end;

end.
