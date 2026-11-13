unit Atlas.UI.Tracker.TestResults.Strings;

// Oberflächentexte des Trackers für Testergebnisse aus der CI und CI-Anmeldung, auf Deutsch und Englisch
// (#1455). Die Sprache bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasTestResultsTextId = (WelcomeProjectsMissing, WelcomeTestsTitle, WelcomeTestsQueryNow,
    WelcomeTestsOpenProject, WelcomeTestsFailed, WelcomeTestsAllPassed, WelcomeTestsNonePassed,
    WelcomeTestsNoLocalRun, WelcomeTestsYesterday, WelcomeTestsJustNow, WelcomeTestsMinutesAgo,
    WelcomeTestsHoursAgo, WelcomeTestsDaysAgo, WelcomeTestsPassed, WelcomeTestsSkipped, WelcomeTestsBuildSuccess,
    WelcomeTestsBuildFailure, WelcomeTestsBuildUnstable, WelcomeTestsBuildAborted, WelcomeTestsBuildNotBuilt,
    WelcomeTestsBuildUnknown, WelcomeTestsCiUnauthorized, WelcomeTestsCiNotFound, WelcomeTestsCiQuerying,
    WelcomeTestsLocalGreenServerRed, WelcomeTestsLocalRedServerGreen, WelcomeTestsEmpty, WelcomeTestsRerun,
    WelcomeTestsDebug, WelcomeTestsBrowse, WelcomeTestsServerTag, WelcomeTestsHintLocal, WelcomeTestsHintJob,
    WelcomeTestsHintAttempt, WelcomeTestsHintClick, WelcomeTestsHintFailure, WelcomeTestsMore, WelcomeTestsNotFound,
    CiLoginTitle, CiLoginUser, CiLoginToken, CiLoginNoServer, NotificationsBuildServerRed, WelcomeTestsCiTimeout,
    WelcomeTestsCiServerError, WelcomeTestsCiUnknownProvider, WelcomeTestsCiNotQueried, WelcomeTestsCiUnreachable,
    WelcomeTestsStale, CiLoginSaved, CiLoginRemoved, CiLoginFailed, CiLoginIncomplete, WelcomeTestsSlowest);

  TAtlasTestResultsStrings = class
  public
    class function Text(AId: TAtlasTestResultsTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasTestResultsTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasTestResultsTextId] of string = (
    ('Projekt nicht gefunden: %s',
     'Testergebnisse',
     'Build-Server jetzt abfragen',
     'Projekt öffnen',
     '%d fehlgeschlagen',
     'alle %d ok',
     'keine Tests gelaufen',
     'noch kein Lauf',
     'gestern',
     'gerade eben',
     'vor %d Min.',
     'vor %d Std.',
     'vor %d Tagen',
     '%d ok',
     '%d übersprungen',
     'erfolgreich',
     'Build fehlgeschlagen',
     'instabil',
     'abgebrochen',
     'nicht gebaut',
     'Ergebnis unbekannt',
     'Anmeldung abgelehnt (Zugang hinterlegen)',
     'Job nicht gefunden',
     'wird abgefragt …',
     'lokal grün, Server rot',
     'lokal rot, Server grün',
     'Noch kein Testlauf. „Tests ausführen“ in der Befehlspalette zeigt das Ergebnis hier.',
     'Fehlgeschlagene erneut ausführen',
     'Im Debugger',
     'Im Browser',
     'Server',
     'Letzter Lauf: %d ok, %d fehlgeschlagen, %d übersprungen %s',
     '%s-Job: %s',
     'Letzte Abfrage: %s',
     'Klick wählt das Projekt, Doppelklick öffnet es',
     'Doppelklick öffnet den Test',
     '… %d weitere',
     'Testergebnisse: Test nicht gefunden: %s',
     'Build-Server %s',
     'Benutzer:',
     'API-Token (beide Felder leer = Zugang entfernen):',
     'Build-Server: Das aktive Projekt nennt in seiner .atlas keinen Server (Abschnitt „ci“, „url“).',
     '%s #%d rot: %s',
     'keine Antwort in 5 s',
     'Antwort nicht lesbar',
     'Anbieter unbekannt',
     'noch nicht abgefragt',
     'nicht erreichbar',
     'Stand vom %s',
     'Build-Server: Zugang im Anmeldespeicher von Windows gespeichert.',
     'Build-Server: Zugang aus dem Anmeldespeicher von Windows entfernt.',
     'Build-Server: Der Anmeldespeicher von Windows hat den Zugang nicht übernommen.',
     'Build-Server: Benutzer und API-Token angeben (beide leer entfernt den Zugang).',
     'Langsamste Tests'),
    ('Project not found: %s',
     'Test results',
     'Query build server now',
     'Open project',
     '%d failed',
     'all %d passed',
     'no tests ran',
     'no run yet',
     'yesterday',
     'just now',
     '%d min ago',
     '%d h ago',
     '%d days ago',
     '%d passed',
     '%d skipped',
     'succeeded',
     'build failed',
     'unstable',
     'aborted',
     'not built',
     'result unknown',
     'sign-in refused (store access)',
     'job not found',
     'querying …',
     'green locally, red on the server',
     'red locally, green on the server',
     'No test run yet. “Run tests” in the command palette shows the result here.',
     'Re-run failed',
     'In debugger',
     'In browser',
     'Server',
     'Last run: %d passed, %d failed, %d skipped %s',
     '%s job: %s',
     'Last query: %s',
     'Click selects the project, double-click opens it',
     'Double-click opens the test',
     '… %d more',
     'Test results: test not found: %s',
     'Build server %s',
     'User:',
     'API token (both fields empty = remove access):',
     'Build server: the active project names no server in its .atlas (section “ci”, “url”).',
     '%s #%d red: %s',
     'no answer within 5 s',
     'answer not readable',
     'unknown provider',
     'not queried yet',
     'not reachable',
     'as of %s',
     'Build server: access stored in the Windows Credential Manager.',
     'Build server: access removed from the Windows Credential Manager.',
     'Build server: the Windows Credential Manager did not accept the access.',
     'Build server: enter user and API token (both empty removes the access).',
     'Slowest tests'));

{ TAtlasTestResultsStrings }

class function TAtlasTestResultsStrings.Text(AId: TAtlasTestResultsTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasTestResultsStrings.Fmt(AId: TAtlasTestResultsTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
