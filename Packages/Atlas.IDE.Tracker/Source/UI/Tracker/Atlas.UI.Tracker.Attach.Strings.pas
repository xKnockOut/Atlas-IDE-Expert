unit Atlas.UI.Tracker.Attach.Strings;

// Oberflächentexte des Trackers für Anhängen an ein Issue: Bildschirmfoto, Markierung, Protokoll, Ausnahmen,
// auf Deutsch und Englisch (#1455). Die Sprache bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest
// sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasAttachTextId = (
    AttachCommand, AttachPreviewButton, AttachCaption, AttachIssue, AttachUploadHint, AttachFallbackHint,
    AttachSources, AttachScreenshot, AttachWindowPick, AttachWindowPicking, AttachNoWindows, AttachNoProgram,
    AttachNoWindowsHint, AttachNoProgramHint, AttachWindowPickHint, AttachMarkup, AttachForm, AttachNoForm,
    AttachLog, AttachLogBrowse, AttachLogLines, AttachLogFilter, AttachLogCaption, AttachLogMissing,
    AttachDebugNote, AttachDebugNoteOff, AttachExceptions, AttachExceptionsNone, AttachComment, AttachFiles,
    AttachCommentOnly, AttachSend, AttachScreenshotName, AttachFormName, AttachExceptionsName,
    AttachExceptionsCaption, AttachDebugNoteCaption, AttachCaptureFailed, AttachSending, AttachDone,
    AttachDoneComment, AttachCommented, AttachPasteHint, AttachFailed, AttachCommentFailed, AttachBusy,
    AttachMarkupCaption, AttachMarkupRectangle, AttachMarkupArrow, AttachMarkupBlacken, AttachMarkupUndo,
    AttachMarkupApply, AttachCrashCase, AttachStatusLine, AttachStatusHint);

  TAtlasAttachStrings = class
  public
    class function Text(AId: TAtlasAttachTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasAttachTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasAttachTextId] of string = (
    ('An Issue anhängen …',
     'Anhängen …',
     'An Issue anhängen',
     'Issue:',
     'Die Dateien werden als Anhänge an das Issue in %s geladen.',
     '%s nimmt über die Schnittstelle keine Anhänge an: Bilder kommen in die Zwischenablage, Texte als '
       + 'Codeblock in einen Kommentar; danach öffnet der Browser das Issue.',
     'Was anhängen?',
     'Bildschirmfoto des laufenden Programms:',
     'Per Klick wählen',
     'Auf das Fenster klicken (Esc oder rechte Maustaste bricht ab) …',
     '(kein Fenster)',
     '(kein Programm)',
     'Das debuggte Programm hat kein sichtbares Fenster mit Titel.',
     'Es läuft kein Programm im Debugger; „Per Klick wählen“ nimmt ein beliebiges Fenster auf.',
     'Der nächste Klick nimmt das Fenster darunter auf; ein Programm im Debugger kommt dafür nach vorn. Esc oder '
       + 'rechte Maustaste bricht ab.',
     'Markieren …',
     'Formular im Designer: %s',
     'Formular im Designer (keines offen)',
     'Logdatei:',
     '…',
     'nur die letzten Zeilen:',
     'Logdateien (*.log;*.txt)|*.log;*.txt|Alle Dateien (*.*)|*.*',
     '%s (letzte %d Zeilen)',
     'nicht lesbar: %s',
     'Debug-Notiz (Ort, Aufrufstapel, letzte Exception)',
     'Debug-Notiz (nur bei angehaltenem Programm)',
     'Exception-Verlauf (%d Einträge)',
     'Exception-Verlauf (leer)',
     'Kommentar mit Verweis auf die Anhänge:',
     'Wird erst mit „Senden“ übertragen:',
     '(nur der Kommentar)',
     'Senden',
     'bildschirmfoto',
     'formular-%s',
     'exception-verlauf.txt',
     'Exception-Verlauf',
     'Debug-Notiz',
     'Bildschirmfoto nicht möglich (Fenster minimiert oder geschlossen).',
     'Anhänge an %s werden gesendet …',
     'An %s angehängt: %d Dateien.',
     'An %s angehängt: %d Dateien und ein Kommentar.',
     'Kommentar an %s geschrieben.',
     'In GitHub mit Strg+V einfügen: %d Bild(er) liegen in der Zwischenablage. Der Browser öffnet %s.',
     'Anhängen an %s fehlgeschlagen: %s',
     'Dateien an %s angehängt, der Kommentar fehlgeschlagen: %s',
     'Das Anhängen läuft noch.',
     'Bild markieren',
     'Rahmen',
     'Pfeil',
     'Schwärzen',
     'Rückgängig',
     'Übernehmen',
     'Absturzfall (%d Dateien)',
     'An %s anhängen …',
     'Bildschirmfoto, Formular, Log oder Debug-Notiz an das aktuelle Issue anhängen'),
    ('Attach to issue …',
     'Attach …',
     'Attach to issue',
     'Issue:',
     'The files are uploaded as attachments to the issue in %s.',
     '%s does not accept attachments through its API: images go to the clipboard, texts into a comment as code '
       + 'blocks; then the browser opens the issue.',
     'What to attach?',
     'Screenshot of the running program:',
     'Pick by click',
     'Click the window (Esc or right click cancels) …',
     '(no window)',
     '(no program)',
     'The debugged program has no visible window with a title.',
     'No program is running in the debugger; “Pick by click” captures any window.',
     'The next click captures the window below it; a program in the debugger is brought to the front first. Esc '
       + 'or right click cancels.',
     'Mark up …',
     'Form in designer: %s',
     'Form in designer (none open)',
     'Log file:',
     '…',
     'only the last lines:',
     'Log files (*.log;*.txt)|*.log;*.txt|All files (*.*)|*.*',
     '%s (last %d lines)',
     'not readable: %s',
     'Debug note (location, call stack, last exception)',
     'Debug note (only while the program is paused)',
     'Exception history (%d entries)',
     'Exception history (empty)',
     'Comment referencing the attachments:',
     'Sent only when you click “Send”:',
     '(comment only)',
     'Send',
     'screenshot',
     'form-%s',
     'exception-history.txt',
     'Exception history',
     'Debug note',
     'Screenshot not possible (window minimised or closed).',
     'Sending attachments to %s …',
     'Attached to %s: %d files.',
     'Attached to %s: %d files and a comment.',
     'Comment written to %s.',
     'Paste in GitHub with Ctrl+V: %d image(s) are on the clipboard. The browser opens %s.',
     'Attaching to %s failed: %s',
     'Files attached to %s, the comment failed: %s',
     'Attaching is still running.',
     'Mark up image',
     'Rectangle',
     'Arrow',
     'Blacken',
     'Undo',
     'Apply',
     'Crash case (%d files)',
     'Attach to %s …',
     'Attach a screenshot, form, log or debug note to the current issue'));

{ TAtlasAttachStrings }

class function TAtlasAttachStrings.Text(AId: TAtlasAttachTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasAttachStrings.Fmt(AId: TAtlasAttachTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
