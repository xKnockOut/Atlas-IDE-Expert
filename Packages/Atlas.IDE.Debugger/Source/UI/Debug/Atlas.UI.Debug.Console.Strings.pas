unit Atlas.UI.Debug.Console.Strings;

// Texte der angedockten Konsolenausgabe (#581): Fenster, Knöpfe, Zustand, Meldungen, Befehle und Einstellung, auf
// Deutsch und Englisch. Die Sprache bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasConsoleTextId = (
    Caption, InputHint, Send, CloseInput, Stop, Clear, Copy, CopyAll, OpenLocation, StateIdle, StateRunning,
    StateAttaching, StateEnded, NoteStarted, NoteStartedDebug, NoteEnded, NoteDropped, StartFailed, AttachFailed,
    AttachLate, AttachGone, Busy, BuildFailed, NoProject, NotConsole, InputClosed, CommandWindow,
    CommandRunNoDebug, MenuRunNoDebug, SettingsCaptureConsole);

  TAtlasConsoleStrings = class
  public
    class function Text(AId: TAtlasConsoleTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasConsoleTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasConsoleTextId] of string = (
    ('Atlas: Konsolenausgabe',
     'Eingabe für das Programm, Enter sendet',
     'Senden',
     'Eingabe beenden',
     'Beenden',
     'Leeren',
     'Kopieren',
     'Alles kopieren',
     'Zur Fundstelle',
     'Kein Programm',
     'Läuft: %s (PID %d)',
     'Debugger hängt sich an: %s (PID %d)',
     'Beendet: %s, Exit-Code %s',
     '▶ %s %s',
     '▶ %s %s (mit Debugger)',
     '■ Beendet mit Exit-Code %s',
     '… %d ältere Zeilen entfernt',
     'Atlas: %s ließ sich nicht starten (Windows-Fehler %d).',
     'Atlas: Der Debugger konnte sich nicht an %s (PID %d) hängen; das Programm läuft ohne Debugger weiter.',
     'Atlas: Der Debugger hat %s (PID %d) nach %d ms noch nicht übernommen; das Programm läuft weiter. ' +
       'Haltepunkte am Anfang greifen dann womöglich nicht.',
     'Atlas: %s (PID %d) endete, bevor sich der Debugger anhängen konnte.',
     'Atlas: Im Fenster „Konsolenausgabe“ läuft noch %s. Erst beenden, dann neu starten.',
     'Atlas: %s ließ sich nicht bauen; die Meldungen der IDE zeigen den Fehler.',
     'Atlas: Kein aktives Projekt.',
     'Atlas: %s ist kein Konsolenprogramm (oder noch nicht gebaut); die IDE startet es wie immer.',
     'Eingabe beendet (Ende der Datei für Readln)',
     'Konsolenausgabe',
     'Ohne Debugger mit Konsolenausgabe starten',
     'Ohne Debugger mit Konsolenausgabe starten',
     'Ausgabe von Konsolenprogrammen andocken'),
    ('Atlas: Console output',
     'Input for the program, Enter sends',
     'Send',
     'End input',
     'Stop',
     'Clear',
     'Copy',
     'Copy all',
     'Go to location',
     'No program',
     'Running: %s (PID %d)',
     'Debugger attaching: %s (PID %d)',
     'Ended: %s, exit code %s',
     '▶ %s %s',
     '▶ %s %s (with debugger)',
     '■ Ended with exit code %s',
     '… %d older lines removed',
     'Atlas: %s could not be started (Windows error %d).',
     'Atlas: The debugger could not attach to %s (PID %d); the program keeps running without the debugger.',
     'Atlas: The debugger has not taken over %s (PID %d) after %d ms; the program keeps running. ' +
       'Breakpoints at the very start may not be hit.',
     'Atlas: %s (PID %d) ended before the debugger could attach.',
     'Atlas: %s is still running in the “Console output” window. Stop it first, then start again.',
     'Atlas: %s could not be built; the IDE messages show the error.',
     'Atlas: No active project.',
     'Atlas: %s is not a console program (or not built yet); the IDE starts it as usual.',
     'Input ended (end of file for Readln)',
     'Console output',
     'Run without debugger with console output',
     'Run without debugger with console output',
     'Dock console program output'));

{ TAtlasConsoleStrings }

class function TAtlasConsoleStrings.Text(AId: TAtlasConsoleTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasConsoleStrings.Fmt(AId: TAtlasConsoleTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
