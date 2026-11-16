unit Atlas.UI.Debug.Session.Strings;

// Texte zur Debug-Sitzung: Neu starten, erneut anhängen und Startgruppen, auf Deutsch und Englisch (#1455). Die
// Sprache bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasSessionTextId = (
    RestartStop, RestartBuild, RestartStart, RestartReturn, RestartTitle, RestartFailedStop, RestartFailedBuild,
    RestartFailedStart, RestartReenabled, RestartNoProject, ReattachCommand, ReattachWaitMenu, ReattachPid,
    ReattachStarted, ReattachCommandLine, ReattachAttach, ReattachCancel, ReattachNothing, ReattachOfferWait,
    ReattachWaiting, ReattachWaitingSummary, ReattachAttached, ReattachFailed, ReattachEnded, ReattachStopped,
    ReattachExeFilter, ReattachChooseExe, LaunchTitle, LaunchStarting, LaunchWaiting, LaunchNoActive, LaunchNoGroups,
    LaunchNotInGroup, LaunchBuildFailed, LaunchStartFailed, LaunchTimedOut, LaunchContinue, LaunchStopAll,
    LaunchStateRunning, LaunchStatePaused, LaunchStateEnded, LaunchStoppedAt, LaunchDialogTitle, LaunchColGroup,
    LaunchColProjects, LaunchColProject, LaunchColProfile, LaunchColDebug, LaunchColWait, LaunchActivate, LaunchStart,
    LaunchEdit, LaunchClose, LaunchYes, LaunchNo, LaunchWaitSeconds, LaunchWaitPort, LaunchWaitWindow,
    LaunchActiveMark, LaunchProblems);

  TAtlasSessionStrings = class
  public
    class function Text(AId: TAtlasSessionTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasSessionTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasSessionTextId] of string = (
    ('Beenden',
     'Bauen',
     'Starten',
     'Zurück zur Stelle',
     'Neu starten',
     'Atlas: Neu starten abgebrochen: Das Programm hat sich nicht beendet.',
     'Atlas: Neu starten abgebrochen: Bauen fehlgeschlagen (siehe Meldungen).',
     'Atlas: Neu starten abgebrochen: Das Programm ist nicht gestartet.',
     'Atlas: %d Haltepunkte wieder eingeschaltet.',
     'Atlas: Kein Projekt zum Starten.',
     'Erneut an %s anhängen',
     'Anhängen, sobald gestartet …',
     'PID',
     'Gestartet',
     'Befehlszeile',
     'Anhängen',
     'Abbrechen',
     'Atlas: Noch an keinen Prozess angehängt; zuerst über „Start › An Prozess anhängen …“ oder „Anhängen, sobald gestartet …“.',
     '%s läuft nicht. Warten, bis das Programm startet, und dann anhängen?',
     'Warte auf %s … (Abbrechen)',
     'Warte auf %s',
     'Atlas: An %s (PID %d) angehängt.',
     'Atlas: Anhängen an %s (PID %d) fehlgeschlagen. Prozesse anderer Benutzer und Dienste brauchen eine IDE mit Administratorrechten.',
     '%s beendet: erneut anhängen, sobald er wieder startet',
     'Atlas: Warten auf %s beendet.',
     'Programme (*.exe)|*.exe',
     'Programm wählen, an das Atlas sich beim Start hängt',
     'Startverbund %s',
     'startet …',
     'wartet …',
     'Atlas: Kein Startverbund aktiv; „Atlas: Startverbünde …“ wählt einen.',
     'Keine Startverbünde in der Projektdatei .atlas („launchGroups“). „In .atlas bearbeiten“ legt sie an.',
     'Atlas: Startverbund angehalten: %s gehört nicht zur geöffneten Projektgruppe.',
     'Atlas: Startverbund angehalten: Bauen von %s fehlgeschlagen (siehe Meldungen).',
     'Atlas: Startverbund angehalten: %s ist nicht gestartet.',
     'Atlas: Startverbund angehalten: Wartebedingung von %s abgelaufen.',
     'Trotzdem weiter',
     'Alle beenden',
     'läuft',
     'angehalten',
     'beendet',
     'Atlas: Angehalten in %s (PID %d).',
     'Atlas: Startverbünde',
     'Verbund',
     'Projekte',
     'Projekt',
     'Startprofil',
     'Debugger',
     'Warten danach',
     'Aktiv setzen',
     'Starten',
     'In .atlas bearbeiten',
     'Schließen',
     'ja',
     'nein',
     '%d s',
     'Port %d (höchstens %d s)',
     'Hauptfenster (höchstens %d s)',
     '%s (aktiv)',
     'Atlas: Einträge in launchGroups übergangen: %s'),
    ('Stop',
     'Build',
     'Start',
     'Back to the place',
     'Restart',
     'Atlas: Restart cancelled: the program did not stop.',
     'Atlas: Restart cancelled: build failed (see messages).',
     'Atlas: Restart cancelled: the program did not start.',
     'Atlas: %d breakpoints turned on again.',
     'Atlas: No project to start.',
     'Reattach to %s',
     'Attach when started …',
     'PID',
     'Started',
     'Command line',
     'Attach',
     'Cancel',
     'Atlas: Not attached to a process yet; first use “Run › Attach to Process …” or “Attach when started …”.',
     '%s is not running. Wait until the program starts and attach then?',
     'Waiting for %s … (Cancel)',
     'Waiting for %s',
     'Atlas: Attached to %s (PID %d).',
     'Atlas: Attaching to %s (PID %d) failed. Processes of other users and services need an IDE with administrator rights.',
     '%s ended: reattach when it starts again',
     'Atlas: Stopped waiting for %s.',
     'Programs (*.exe)|*.exe',
     'Choose the program to attach to when it starts',
     'Launch group %s',
     'starting …',
     'waiting …',
     'Atlas: No launch group active; “Atlas: Launch groups …” chooses one.',
     'No launch groups in the project file .atlas (“launchGroups”). “Edit in .atlas” creates them.',
     'Atlas: Launch group halted: %s is not part of the open project group.',
     'Atlas: Launch group halted: building %s failed (see messages).',
     'Atlas: Launch group halted: %s did not start.',
     'Atlas: Launch group halted: the wait condition of %s timed out.',
     'Continue anyway',
     'Stop all',
     'running',
     'paused',
     'ended',
     'Atlas: Paused in %s (PID %d).',
     'Atlas: Launch groups',
     'Group',
     'Projects',
     'Project',
     'Start profile',
     'Debugger',
     'Wait afterwards',
     'Set active',
     'Start',
     'Edit in .atlas',
     'Close',
     'yes',
     'no',
     '%d s',
     'Port %d (at most %d s)',
     'Main window (at most %d s)',
     '%s (active)',
     'Atlas: Entries in launchGroups skipped: %s'));

{ TAtlasSessionStrings }

class function TAtlasSessionStrings.Text(AId: TAtlasSessionTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasSessionStrings.Fmt(AId: TAtlasSessionTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
