unit Atlas.UI.Tracker.Time.Strings;

// Oberflächentexte des Trackers für Zeiterfassung: Statusleiste, Menü, Buchen, offene Zeiten, auf Deutsch und
// Englisch (#1455). Die Sprache bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasTimeTextId = (
    TimeStatusPaused, TimeStatusHint, TimeMenuPause, TimeMenuResume, TimeMenuReset, TimeMenuCorrect, TimeMenuBook,
    TimeMenuOpen, TimeResetConfirm, TimeCorrectCaption, TimeCorrectPrompt, TimeCorrectInvalid, TimeBookCaption,
    TimeBookQuestion, TimeBookDuration, TimeBookWorkType, TimeBookText, TimeBookAsComment, TimeBookComment,
    TimeBookBook, TimeBookLater, TimeBookDiscard, TimeBookSending, TimeBookOff, TimeBookInvalid, TimeBookLocalOnly,
    TimeBookDone, TimeOpenCaption, TimeOpenEmpty, TimeOpenRow, TimeOpenBook, TimeOpenDiscard, TimeOpenClose,
    TimeFileFailed);

  TAtlasTimeStrings = class
  public
    class function Text(AId: TAtlasTimeTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasTimeTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasTimeTextId] of string = (
    ('%s (Pause)',
     'Erfasste Zeit für %s: %s. Klick: Pause, Zurücksetzen, Korrigieren, Buchen',
     'Pause',
     'Weiter',
     'Zurücksetzen …',
     'Zeit korrigieren …',
     'Jetzt buchen …',
     'Offene Zeitbuchungen …',
     'Erfasste Zeit für %s (%s) verwerfen?',
     'Zeit korrigieren',
     'Zeit für %s (z. B. 1:25 oder 85 min):',
     '„%s“ ist keine gültige Dauer.',
     'Zeit buchen',
     '%s auf %s buchen?',
     'Dauer:',
     'Arbeitstyp:',
     'Beschreibung:',
     'Als Kommentar „Aufwand: …“ senden',
     'Aufwand: %s',
     'Buchen',
     'Später',
     'Verwerfen',
     'Buche …',
     'Zeiterfassung im YouTrack-Projekt aus; die Zeit bleibt lokal.',
     'Bitte eine Dauer wie 1:25 oder 85 min eingeben.',
     'GitHub kennt keine Zeiterfassung: Ohne Kommentar vermerkt Atlas die Zeit nur lokal als gebucht.',
     'Atlas: %s auf %s gebucht.',
     'Offene Zeitbuchungen',
     'Keine offene Zeit.',
     '%s · %s · %s',
     'Buchen …',
     'Verwerfen …',
     'Schließen',
     'Atlas: Zeiterfassung nicht gespeichert (%s gesperrt oder unlesbar).'),
    ('%s (paused)',
     'Tracked time for %s: %s. Click: pause, reset, correct, log',
     'Pause',
     'Resume',
     'Reset …',
     'Correct time …',
     'Log now …',
     'Pending time entries …',
     'Discard the tracked time for %s (%s)?',
     'Correct time',
     'Time for %s (e.g. 1:25 or 85 min):',
     '"%s" is not a valid duration.',
     'Log time',
     'Log %s on %s?',
     'Duration:',
     'Work type:',
     'Description:',
     'Send as comment "Effort: …"',
     'Effort: %s',
     'Log',
     'Later',
     'Discard',
     'Logging …',
     'Time tracking is off in the YouTrack project; the time stays local.',
     'Please enter a duration like 1:25 or 85 min.',
     'GitHub has no time tracking: without a comment Atlas only marks the time as logged locally.',
     'Atlas: logged %s on %s.',
     'Pending time entries',
     'No pending time.',
     '%s · %s · %s',
     'Log …',
     'Discard …',
     'Close',
     'Atlas: time not saved (%s is locked or unreadable).'));

{ TAtlasTimeStrings }

class function TAtlasTimeStrings.Text(AId: TAtlasTimeTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasTimeStrings.Fmt(AId: TAtlasTimeTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
