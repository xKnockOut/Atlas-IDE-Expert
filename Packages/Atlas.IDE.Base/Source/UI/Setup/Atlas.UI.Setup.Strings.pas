unit Atlas.UI.Setup.Strings;

// Oberflächentexte des Features Einrichtung auf Deutsch und Englisch. Die Sprache bestimmt
// `TAtlasStrings.Language`; jeder Aufruf liest sie neu. Eigene Unit, damit ein neuer Text des Features nicht
// `Atlas.UI.Strings` ändert, die fast der ganze Kern verwendet; dort bleiben gemeinsame Texte.

interface

{$SCOPEDENUMS ON}

type
  TAtlasSetupTextId = (
    SetupTitle, SetupProgress, SetupStatusLine, SetupStatusComplete, SetupStatusSummary, SetupTryIt, SetupCopy,
    SetupCopied, SetupRecheck, SetupClose, SetupShowAtStart, SetupFixChoosePath, SetupFixStart, SetupFixRestart,
    SetupFixRebuild, SetupFixBuildLibrary, SetupFixDisableErrorInsight, SetupFixEnableErrorInsight, SetupFixKeys,
    SetupFixExplain, SetupChooseTitle, SetupServerVersion, SetupDelphiPlatform, SetupIndexPercent, SetupProjectLine,
    SetupProjectDone, SetupProjectBuilding, SetupProjectMissing, SetupStageProjectFiles, SetupStageSearchPaths,
    SetupStageLibrary, SetupStageWaiting, SetupLibrarySize, SetupWhyServerStarting, SetupWhyServerVersion,
    SetupWhyDelphiNoProject, SetupWhyDelphiUnknown, SetupWhyIndexBuilding, SetupWhyIndexNoProjects,
    SetupWhyLibraryPending, SetupWhyErrorInsightRestart, SetupServerReady, SetupServerMissing, SetupServerNotStarted,
    SetupServerStarting, SetupServerStopped, SetupServerFailed, SetupServerVersionUnknown, SetupServerVersionMismatch,
    SetupDelphiReady, SetupDelphiNoProject, SetupDelphiUnknown, SetupIndexReady, SetupIndexReadyUnits,
    SetupIndexBuilding, SetupIndexIncomplete, SetupIndexNoServer, SetupIndexNoProjects, SetupLibraryReady,
    SetupLibraryMissing, SetupLibraryPending, SetupLibraryUnknown, SetupErrorInsightAtlas, SetupErrorInsightIde,
    SetupErrorInsightDuplicate, SetupErrorInsightNone, SetupErrorInsightRestart, SetupKeysReady, SetupKeysReadyWins,
    SetupKeysConflict);

  TAtlasSetupStrings = class
  public
    class function Text(AId: TAtlasSetupTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasSetupTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasSetupTextId] of string = (
    ('Atlas-Einrichtung',
     '%d von %d erledigt',
     'Einrichtung: %d von %d erledigt',
     'Einrichtung: vollständig (%d von %d)',
     'Einrichtung %d/%d',
     'Probier es aus: %s in einer Methode',
     'Bericht kopieren',
     'Bericht in der Zwischenablage (ohne Pfade und Namen).',
     'Erneut prüfen',
     'Schließen',
     'Beim Start zeigen, solange nicht alles erledigt ist',
     'Server-Pfad wählen…',
     'Server starten',
     'Server neu starten',
     'Index neu aufbauen',
     'Jetzt aufbauen',
     'Error Insight abschalten',
     'Error Insight einschalten',
     'Tastenkonflikte öffnen',
     'Warum?',
     'AtlasServer.exe wählen',
     'AtlasServer %s',
     'Plattform %s',
     '%s %%',
     '%s: %s',
     'fertig',
     'wird aufgebaut',
     'fehlt im Index',
     'Projektdateien',
     'Suchpfade',
     'Bibliothek',
     'wartet',
     '%s MB',
     'Atlas startet AtlasServer.exe und wartet auf die Antwort auf initialize. Das dauert meist nur Sekunden; der Punkt wird danach von selbst grün.',
     'Die Version meldet der Server in der Antwort auf initialize; sie kommt kurz nach dem Start.',
     'Die Plattform (Win32, Win64 …) kommt aus dem aktiven Projekt. Öffne ein Projekt, dann wird der Punkt grün.',
     'Atlas konnte die Version der IDE nicht aus ihrem Registry-Schlüssel lesen. Kopiere den Bericht und erstelle einen Fehlerbericht (Menü Atlas).',
     'Der Server liest die Units der Projekte nacheinander ein, das aktive zuerst. Vervollständigung und Hover arbeiten schon währenddessen.',
     'Ohne geöffnetes Projekt gibt es nichts zu indizieren. Öffne ein Projekt oder eine Projektgruppe.',
     'RTL und VCL liest der erste Indexlauf einmal je Delphi-Version und Plattform ein und legt sie im Bibliotheks-Cache ab; alle Projekte teilen ihn.',
     'Die IDE liest diese Einstellung nur beim Start. Nach dem nächsten Start der IDE ist der Punkt grün.',
     'Server gefunden, gestartet, Version passt',
     'AtlasServer.exe nicht gefunden',
     'Server gefunden, noch nicht gestartet',
     'Server wird gestartet…',
     'Server gestoppt',
     'Server-Start fehlgeschlagen',
     'Server läuft, Version noch unbekannt',
     'Server %s passt nicht zum Plugin %s',
     '%s erkannt',
     '%s erkannt, Plattform erst mit einem Projekt',
     'Delphi-Version nicht erkannt',
     'Projektgruppe: %s Projekte indiziert',
     'Projektgruppe: %s Projekte, %s Units',
     'Projektgruppe wird indiziert: %s von %s Projekten fertig',
     'Projektgruppe: %s von %s Projekten nicht im Index (%s)',
     'Index: Server läuft nicht',
     'Index: kein Projekt geöffnet',
     'Bibliotheks-Cache vorhanden',
     'Bibliotheks-Cache fehlt, erster Start dauert länger',
     'Bibliotheks-Cache entsteht beim ersten Indexlauf',
     'Bibliotheks-Cache: Server läuft nicht',
     'Error Insight der IDE aus, Atlas zeigt die Probleme',
     'Error Insight der IDE an, Atlas-Probleme aus',
     'Error Insight der IDE ist noch an (doppelte Meldungen)',
     'Weder Error Insight noch Atlas zeigen Fehler im Editor',
     'Error Insight umgeschaltet, wirkt nach dem Neustart der IDE',
     'Tastenkürzel ohne Konflikt',
     'Tastenkürzel ohne Konflikt (%s mit Vorrang für Atlas)',
     '%s Tastenkürzel anders belegt, z. B. %s von „%s“'),
    ('Atlas setup',
     '%d of %d done',
     'Setup: %d of %d done',
     'Setup: complete (%d of %d)',
     'Setup %d/%d',
     'Try it: %s inside a method',
     'Copy report',
     'Report copied to the clipboard (no paths or names).',
     'Check again',
     'Close',
     'Show at startup until everything is done',
     'Choose server path…',
     'Start server',
     'Restart server',
     'Rebuild index',
     'Build now',
     'Turn off Error Insight',
     'Turn on Error Insight',
     'Open key conflicts',
     'Why?',
     'Choose AtlasServer.exe',
     'AtlasServer %s',
     'Platform %s',
     '%s %%',
     '%s: %s',
     'done',
     'indexing',
     'not in the index',
     'project files',
     'search paths',
     'library',
     'waiting',
     '%s MB',
     'Atlas starts AtlasServer.exe and waits for its answer to initialize. This usually takes seconds; the point turns green by itself.',
     'The server reports its version in the answer to initialize; it arrives shortly after the start.',
     'The platform (Win32, Win64 …) comes from the active project. Open a project and the point turns green.',
     'Atlas could not read the IDE version from its registry key. Copy the report and create a bug report (Atlas menu).',
     'The server reads the units of the projects one after another, the active one first. Completion and hover already work meanwhile.',
     'Without an open project there is nothing to index. Open a project or a project group.',
     'The first indexing run reads RTL and VCL once per Delphi version and platform into the library cache; all projects share it.',
     'The IDE reads this setting only at startup. After the next IDE start the point is green.',
     'Server found, running, version matches',
     'AtlasServer.exe not found',
     'Server found, not started yet',
     'Server is starting…',
     'Server stopped',
     'Server failed to start',
     'Server running, version not known yet',
     'Server %s does not match plugin %s',
     '%s detected',
     '%s detected, platform needs an open project',
     'Delphi version not detected',
     'Project group: %s projects indexed',
     'Project group: %s projects, %s units',
     'Indexing project group: %s of %s projects done',
     'Project group: %s of %s projects not indexed (%s)',
     'Index: server not running',
     'Index: no project open',
     'Library cache present',
     'Library cache missing, first start takes longer',
     'Library cache is created by the first indexing run',
     'Library cache: server not running',
     'IDE Error Insight off, Atlas shows the problems',
     'IDE Error Insight on, Atlas problems off',
     'IDE Error Insight is still on (duplicate messages)',
     'Neither Error Insight nor Atlas shows errors in the editor',
     'Error Insight switched, takes effect after restarting the IDE',
     'Shortcuts without conflict',
     'Shortcuts without conflict (%s with priority for Atlas)',
     '%s shortcuts taken by others, e.g. %s by "%s"'));

{ TAtlasSetupStrings }

class function TAtlasSetupStrings.Text(AId: TAtlasSetupTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasSetupStrings.Fmt(AId: TAtlasSetupTextId; const AArgs: array of const): string;
begin
  Result := Format(Text(AId), AArgs);
end;

end.
