unit Atlas.UI.Debug.Note.Strings;

// Texte zur Debug-Notiz (#582): Befehl „Debug-Zustand festhalten“, Meldungen, Überschriften der Notiz und
// Einstellungen, auf Deutsch und Englisch (#1455). Die Sprache bestimmt Base (`TAtlasStrings.Language`); jeder
// Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasNoteTextId = (
    NoteCommand, NoteNotStopped, NoteBusy, NoteCopied, NoteSaved, NoteSaveFailed, NoteFolder, NoteLocals,
    NoteWatches, NoteEvents, NoteUnavailable, NotePending, SettingsNote, SettingsNoteSaveFile);

  TAtlasNoteStrings = class
  public
    class function Text(AId: TAtlasNoteTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasNoteTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasNoteTextId] of string = (
    ('Debug-Zustand festhalten',
     'Atlas: Debug-Zustand festhalten geht nur, solange das Programm angehalten ist.',
     'Atlas: Die Debug-Notiz entsteht noch.',
     'Atlas: Debug-Notiz in der Zwischenablage.',
     'Atlas: Debug-Notiz in der Zwischenablage und gespeichert unter %s',
     'Atlas: Debug-Notiz in der Zwischenablage; Speichern unter %s fehlgeschlagen: %s',
     'debug-notizen',
     'Lokale Variablen',
     'Überwachte Ausdrücke',
     'Ereignisprotokoll',
     'nicht auswertbar',
     'nicht ausgewertet',
     'Debug-Zustand als Notiz festhalten',
     'Notiz auch als Datei neben dem Projekt speichern (Ordner debug-notizen)'),
    ('Capture debug state',
     'Atlas: Capturing the debug state only works while the program is paused.',
     'Atlas: The debug note is still being written.',
     'Atlas: Debug note copied to the clipboard.',
     'Atlas: Debug note copied to the clipboard and saved as %s',
     'Atlas: Debug note copied to the clipboard; saving as %s failed: %s',
     'debug-notes',
     'Local variables',
     'Watches',
     'Event log',
     'not available',
     'not evaluated',
     'Capture the debug state as a note',
     'Also save the note as a file next to the project (folder debug-notes)'));

{ TAtlasNoteStrings }

class function TAtlasNoteStrings.Text(AId: TAtlasNoteTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasNoteStrings.Fmt(AId: TAtlasNoteTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
