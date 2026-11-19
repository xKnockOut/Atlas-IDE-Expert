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
    DebugBarPauseHint, DebugBarResumeHint, DebugBarTakeOverHint,
    // Anzeige „KI-Assistent aktiv“ mit Pause (#1906).
    SettingsBanner, BannerBuilding, BannerEdited, BannerPaused, BannerHintActive, BannerHintPaused,
    PauseOn, PauseOff, RefusedPaused, PauseCommandOn, PauseCommandOff, PauseCommandHint,
    // IDE-Zustand für KI-Assistenten (#2050).
    SettingsContext, SettingsContextSelection, SettingsContextSelectionMax, ContextKind,
    // Anweisungsdateien für KI-Assistenten (#2615).
    InstructionsCommand, InstructionsWritten, InstructionsCurrent, InstructionsFailed, InstructionsNoAnswer,
    InstructionsNoFiles, InstructionsStale, SettingsInstructionsHint);

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
     'Sitzung selbst weiterführen; der KI-Assistent ist getrennt, seine Haltepunkte bleiben',
     'Anzeige „KI-Assistent aktiv“ im Statusfeld mit Pause für KI-Assistenten',
     'KI-Assistent aktiv%s · baut %s',
     'KI-Assistent aktiv%s · %s geändert',
     'KI-Assistenten pausiert',
     'Klick: Pause für KI-Assistenten. Neue Builds und Änderungen an offenen Dateien lehnt die IDE dann ab; ' +
       'ein laufender Build läuft zu Ende.',
     'Klick: Pause aufheben. KI-Assistenten dürfen wieder über die IDE bauen und offene Dateien ändern.',
     'Atlas: Pause für KI-Assistenten. Neue Aufträge lehnt die IDE ab, bis die Pause aufgehoben ist.',
     'Atlas: Pause für KI-Assistenten aufgehoben.',
     'Pause für KI: Der Benutzer hat KI-Assistenten in der IDE angehalten. Nicht erneut senden, sondern warten ' +
       'oder nachfragen.',
     'Pause für KI-Assistenten',
     'Pause für KI-Assistenten aufheben',
     'Hält KI-Assistenten (MCP-Clients) an: Neue Builds und Änderungen an offenen Dateien lehnt die IDE mit Grund ' +
       'ab, bis die Pause aufgehoben ist.',
     'IDE-Zustand für KI-Assistenten bereitstellen (Datei, Cursor, Methode, Projekt, Build; get_ide_context)',
     'Markierten Text mitgeben',
     'Höchstens Zeichen der Auswahl',
     'IDE-Zustand für KI-Assistenten',
     'Anweisungen für KI-Assistenten aktualisieren',
     'Atlas: Anweisungen für KI-Assistenten in %s geschrieben:',
     'Atlas: Anweisungen für KI-Assistenten in %s sind aktuell.',
     'Atlas: Anweisungen für KI-Assistenten in %s nicht geschrieben (%s).',
     'Atlas: Anweisungen für KI-Assistenten: Der Server hat nicht geantwortet.',
     'Atlas: Keine Anweisungsdatei in assistants.instructions.file.',
     'Atlas: Anweisungen für KI-Assistenten in %s veraltet; aktualisieren über Atlas › Anweisungen für ' +
       'KI-Assistenten aktualisieren.',
     'Hinweis, wenn die Anweisungen für KI-Assistenten nach einer Änderung an atlas.json veraltet sind'),
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
     'Continue the session yourself; the AI assistant is disconnected, its breakpoints stay',
     '“AI assistant active” display in the status field with pause for AI assistants',
     'AI assistant active%s · building %s',
     'AI assistant active%s · changed %s',
     'AI assistants paused',
     'Click: pause AI assistants. The IDE then refuses new builds and changes to open files; a running build ' +
       'finishes.',
     'Click: end the pause. AI assistants may build through the IDE and change open files again.',
     'Atlas: AI assistants paused. The IDE refuses new requests until the pause ends.',
     'Atlas: pause for AI assistants ended.',
     'Paused for AI: the user has paused AI assistants in the IDE. Do not send again; wait or ask.',
     'Pause AI assistants',
     'End pause for AI assistants',
     'Pauses AI assistants (MCP clients): the IDE refuses new builds and changes to open files with a reason ' +
       'until the pause ends.',
     'Provide the IDE state to AI assistants (file, cursor, method, project, build; get_ide_context)',
     'Include the selected text',
     'At most characters of the selection',
     'IDE state for AI assistants',
     'Update instructions for AI assistants',
     'Atlas: instructions for AI assistants written to %s:',
     'Atlas: instructions for AI assistants in %s are up to date.',
     'Atlas: instructions for AI assistants in %s not written (%s).',
     'Atlas: instructions for AI assistants: the server did not answer.',
     'Atlas: no instruction file in assistants.instructions.file.',
     'Atlas: instructions for AI assistants in %s are out of date; update with Atlas › Update instructions ' +
       'for AI assistants.',
     'Hint when the instructions for AI assistants are out of date after a change to atlas.json'));

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
