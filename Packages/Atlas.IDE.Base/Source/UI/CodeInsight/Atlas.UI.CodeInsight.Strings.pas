unit Atlas.UI.CodeInsight.Strings;

// Oberflächentexte des Features Code Insight auf Deutsch und Englisch. Die Sprache bestimmt
// `TAtlasStrings.Language`; jeder Aufruf liest sie neu. Eigene Unit, damit ein neuer Text des Features nicht
// `Atlas.UI.Strings` ändert, die fast der ganze Kern verwendet; dort bleiben gemeinsame Texte.

interface

{$SCOPEDENUMS ON}

type
  TAtlasCodeInsightTextId = (
    HangHint, StartSlow, UndoActionServer, MetricsReportNoProject, MetricsReportFailed, MetricsReportRunning,
    MetricsReportBusy, NotificationsBadgeHint, NotificationsServerRestarted, NotificationsServerReopened,
    NotificationsServerCrashed, NotificationsServerError, NotificationsServerMessage, ProblemCounterText,
    ProblemCounterHint, FuseTrippedTitle, FuseTrippedEnable, FuseTrippedOpenLog, ServerCrashedCause,
    ServerHeldTitle, ServerHeldText, ServerHeldPhase, LogBrokenTitle, LogBrokenText, CrashRestartedTitle,
    CrashCaseTitle, CrashCaseText, CrashOpenCase, CrashCreateIssue, CrashHide, CrashSkipTitle, CrashSkipText,
    CrashSkipEnded, CrashRetry, CrashSkipProblem);

  TAtlasCodeInsightStrings = class
  public
    class function Text(AId: TAtlasCodeInsightTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasCodeInsightTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasCodeInsightTextId] of string = (
    ('Atlas: Die IDE hat %d ms nicht reagiert%s',
     'Atlas: Der Start der IDE dauerte %d ms (Zeitlimit %d ms); Atlas selbst brauchte davon %d ms%s.',
     'Änderung des Servers',
     'Metrikbericht: kein aktives Projekt.',
     'Metrikbericht: Der Atlas-Server hat keinen Bericht geliefert.',
     'Metrikbericht wird erstellt …',
     'Metrikbericht: Der Atlas-Server berechnet gerade Metriken; bitte gleich noch einmal versuchen.',
     '%d ungelesene Benachrichtigungen; ein Klick auf die Zahl öffnet die Liste.',
     'Server neu gestartet',
     '%d offene Dateien erneut an den Server gesendet.',
     'Der Server war beendet und läuft wieder.',
     'Server: Fehler',
     'Meldung des Servers',
     'Fehler %d · Warnungen %d · Hinweise %d',
     '%d Fehler, %d Warnungen, %d Hinweise in Atlas-Probleme. Klick öffnet die Liste.',
     '%s nach Fehlern abgeschaltet',
     'Wieder einschalten',
     'Protokoll öffnen',
     'Der Server war beendet (%s) und läuft wieder.',
     'Server wiederholt abgestürzt',
     'Der Server endete zweimal mit %s innerhalb von %d Minuten. Atlas startet ihn nicht mehr von selbst neu, ' +
     'damit der Fehler nicht in einer Schleife wiederkehrt. Der Fehlerbericht enthält das Protokoll und die ' +
     'Ausgabe des Servers auf stderr.',
     '%s; zweimal, kein automatischer Neustart',
     'Atlas-Protokoll gestört',
     'Atlas kann nicht in %s schreiben: %s. Atlas versucht es bei jeder Zeile weiter und vermerkt die Lücke im ' +
     'Protokoll, sobald es wieder geht.',
     'Atlas-Server neu gestartet',
     'Absturzfall gesichert',
     'Der Server hat die Anfrage abgebrochen: %s',
     'Fall öffnen',
     'Issue anlegen',
     'Ausblenden',
     'Übersprungen nach Absturz',
     '%s an %s wird bis zur nächsten Änderung übersprungen (%d Abstürze, %s).',
     '%s an %s wird wieder beantwortet.',
     'Erneut versuchen',
     'Übersprungen nach Absturz: %s (%d Abstürze, %s); Fall %s'),
    ('Atlas: the IDE did not respond for %d ms%s',
     'Atlas: the IDE start took %d ms (time limit %d ms); Atlas itself took %d ms of it%s.',
     'Change by the server',
     'Metrics report: no active project.',
     'Metrics report: the Atlas server returned no report.',
     'Creating metrics report …',
     'Metrics report: the Atlas server is computing metrics right now; please try again shortly.',
     '%d unread notifications; click the number to open the list.',
     'Server restarted',
     '%d open files sent to the server again.',
     'The server had stopped and is running again.',
     'Server: error',
     'Message from the server',
     'Errors %d · Warnings %d · Hints %d',
     '%d errors, %d warnings, %d hints in Atlas problems. Click opens the list.',
     '%s switched off after errors',
     'Switch on again',
     'Open log',
     'The server had stopped (%s) and is running again.',
     'Server crashed repeatedly',
     'The server ended twice with %s within %d minutes. Atlas no longer restarts it on its own, so the error ' +
     'does not recur in a loop. The bug report contains the log and the server''s output on stderr.',
     '%s; twice, no automatic restart',
     'Atlas log disrupted',
     'Atlas cannot write to %s: %s. Atlas keeps trying with every line and notes the gap in the log once writing ' +
     'works again.',
     'Atlas server restarted',
     'Crash case saved',
     'The server aborted the request: %s',
     'Open case',
     'Create issue',
     'Dismiss',
     'Skipped after crash',
     '%s on %s is skipped until the next change (%d crashes, %s).',
     '%s on %s is answered again.',
     'Retry',
     'Skipped after crash: %s (%d crashes, %s); case %s'));

{ TAtlasCodeInsightStrings }

class function TAtlasCodeInsightStrings.Text(AId: TAtlasCodeInsightTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasCodeInsightStrings.Fmt(AId: TAtlasCodeInsightTextId; const AArgs: array of const): string;
begin
  Result := Format(Text(AId), AArgs);
end;

end.
