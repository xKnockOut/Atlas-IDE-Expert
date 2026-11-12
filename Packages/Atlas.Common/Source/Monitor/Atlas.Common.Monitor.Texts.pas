unit Atlas.Common.Monitor.Texts;

// Texte der Oberfläche von AtlasMonitor (#1900, #1901) in Deutsch und Englisch: Fenster, Reiter „Server“,
// Kontextmenü des Symbols im Infobereich, Reiter „Prüfen“ und „Bericht“, Rückfragen und Meldungen. Die Sprache wählt TMonitorSettings.LanguageOf beim Start.

interface

type
  {$SCOPEDENUMS ON}
  TMonitorText = (Caption, TabServers, StopServer, OpenLog, OpenLogFolder, ClearCache, OpenWindow, StopAllServers,
    StartWithWindows, TrayIcon, ExitProgram, MenuFile, MenuSettings, NoServers, SelectServer, ConfirmStop,
    ConfirmStopAll, StopFailed, CacheCleared, AutostartFailed, SaveFailed, CloseToTray,
    TabCheck, TabReport, AddFolder, AddFile, RemoveTarget, SaveList, LoadList, ColumnTarget, ColumnKind, ColumnState,
    Command, Severity, SeverityAll, Rules, Profile, Units, Changed, DiffRef, IncludeUncommitted, ChangedLines,
    Baseline, UpdateBaseline, NoIndex, Timings, FixRules, AffectedBase, Query, ArchitectureFile, ReplayFile, Editor,
    Run, Cancel, CopyCall, Export, Filter, CallCopied, NoTargets, ConfirmWrite, ServerMissing, StartFailed, Exported,
    MissingInput, BrowserFailed, FilterFindings, FilterTargets, FilterReport, FilterText, FilterAddFile, FilterJson,
    ConfirmQuitRunning, Options, ChooseFolder);
  {$SCOPEDENUMS OFF}

  TMonitorTexts = record
  public
    class function Text(AText: TMonitorText): string; static;
    class function Fmt(AText: TMonitorText; const AArgs: array of const): string; static;
  end;

implementation

uses
  Atlas.Common.Localization.Texts;

const
  cTexts: array[TMonitorText] of TAtlasText = (
    (De: 'Atlas Monitor'; En: 'Atlas Monitor'),
    (De: 'Server'; En: 'Servers'),
    (De: 'Server beenden'; En: 'Stop server'),
    (De: 'Protokoll öffnen'; En: 'Open log'),
    (De: 'Protokollordner öffnen'; En: 'Open log folder'),
    (De: 'Index-Cache leeren'; En: 'Clear index cache'),
    (De: 'Fenster öffnen'; En: 'Open window'),
    (De: 'Alle Server beenden'; En: 'Stop all servers'),
    (De: 'Mit Windows starten'; En: 'Start with Windows'),
    (De: 'Symbol im Infobereich'; En: 'Icon in the notification area'),
    (De: 'Beenden'; En: 'Exit'),
    (De: '&Datei'; En: '&File'),
    (De: '&Einstellungen'; En: '&Settings'),
    (De: 'Keine laufenden Server'; En: 'No running servers'),
    (De: 'Einen Server in der Liste wählen.'; En: 'Select a server in the list.'),
    (De: 'Server %d beenden? Die IDE startet ihren Server bei Bedarf neu.';
     En: 'Stop server %d? The IDE restarts its server when needed.'),
    (De: 'Alle %d Atlas-Server beenden?'; En: 'Stop all %d Atlas servers?'),
    (De: 'Server %d ließ sich nicht beenden.'; En: 'Could not stop server %d.'),
    (De: '%d Index-Caches gelöscht; Caches laufender Server bleiben.';
     En: '%d index caches deleted; caches of running servers remain.'),
    (De: 'Der Start mit Windows ließ sich nicht ändern.'; En: 'Could not change the start with Windows.'),
    (De: 'Die Einstellungen ließen sich nicht speichern (%s).'; En: 'Could not save the settings (%s).'),
    (De: 'Atlas Monitor läuft im Infobereich weiter.'; En: 'Atlas Monitor keeps running in the notification area.'),
    (De: 'Prüfen'; En: 'Check'),
    (De: 'Bericht'; En: 'Report'),
    (De: 'Ordner hinzufügen …'; En: 'Add folder …'),
    (De: 'Datei hinzufügen …'; En: 'Add file …'),
    (De: 'Entfernen'; En: 'Remove'),
    (De: 'Liste speichern …'; En: 'Save list …'),
    (De: 'Liste laden …'; En: 'Load list …'),
    (De: 'Ziel'; En: 'Target'),
    (De: 'Art'; En: 'Kind'),
    (De: 'Stand'; En: 'Status'),
    (De: 'Befehl'; En: 'Command'),
    (De: 'Schwere ab'; En: 'Minimum severity'),
    (De: 'alle'; En: 'all'),
    (De: 'Regeln (Komma)'; En: 'Rules (comma)'),
    (De: 'Profil'; En: 'Profile'),
    (De: 'Units (Name oder Muster)'; En: 'Units (name or pattern)'),
    (De: 'Nur geänderte Dateien seit Zweig'; En: 'Only files changed since branch'),
    (De: 'Vergleich mit Ref (--diff)'; En: 'Compare with ref (--diff)'),
    (De: 'Mit nicht eingecheckten Änderungen'; En: 'Include uncommitted changes'),
    (De: 'Nur geänderte Zeilen'; En: 'Only changed lines'),
    (De: 'Baseline-Datei'; En: 'Baseline file'),
    (De: 'Baseline neu schreiben'; En: 'Rewrite baseline'),
    (De: 'Ohne Symbolindex'; En: 'Without symbol index'),
    (De: 'Zeitprofil'; En: 'Timing profile'),
    (De: 'Regeln der Sammelkorrektur'; En: 'Rules of the bulk fix'),
    (De: 'Basis der betroffenen Tests'; En: 'Base of the affected tests'),
    (De: 'Code-Abfrage oder @Name'; En: 'Code query or @name'),
    (De: 'Architektur-Stand (.json)'; En: 'Architecture state (.json)'),
    (De: 'Absturzfall (anfrage.json)'; En: 'Crash case (anfrage.json)'),
    (De: 'Editor (%file%, %line%, %column%)'; En: 'Editor (%file%, %line%, %column%)'),
    (De: 'Ausführen'; En: 'Run'),
    (De: 'Abbrechen'; En: 'Cancel'),
    (De: 'Aufruf kopieren'; En: 'Copy command line'),
    (De: 'Exportieren …'; En: 'Export …'),
    (De: 'Filter'; En: 'Filter'),
    (De: 'Aufruf in die Zwischenablage kopiert.'; En: 'Command line copied to the clipboard.'),
    (De: 'Kein Ziel eingeschaltet.'; En: 'No target is switched on.'),
    (De: '„%s“ ändert Dateien in %d Zielen. Fortfahren?'; En: '"%s" changes files in %d targets. Continue?'),
    (De: 'AtlasServer.exe fehlt neben AtlasMonitor (%s).'; En: 'AtlasServer.exe is missing next to AtlasMonitor (%s).'),
    (De: 'Start gescheitert: %s'; En: 'Start failed: %s'),
    (De: 'Gespeichert: %s'; En: 'Saved: %s'),
    (De: 'Bitte zuerst „%s“ angeben.'; En: 'Please fill in "%s" first.'),
    (De: 'Der eingebettete Browser (WebView2) fehlt; die Seite öffnet sich im Standardbrowser.';
     En: 'The embedded browser (WebView2) is missing; the page opens in the default browser.'),
    (De: 'HTML-Seite (*.html)|*.html|SARIF (*.sarif)|*.sarif'; En: 'HTML page (*.html)|*.html|SARIF (*.sarif)|*.sarif'),
    (De: 'Zielliste (*.atlastargets)|*.atlastargets'; En: 'Target list (*.atlastargets)|*.atlastargets'),
    (De: 'HTML-Seite (*.html)|*.html|Markdown (*.md)|*.md|JSON (*.json)|*.json';
     En: 'HTML page (*.html)|*.html|Markdown (*.md)|*.md|JSON (*.json)|*.json'),
    (De: 'Text (*.txt;*.md;*.diff)|*.txt;*.md;*.diff'; En: 'Text (*.txt;*.md;*.diff)|*.txt;*.md;*.diff'),
    (De: 'Projekte und Dateien|*.dproj;*.groupproj;*.dpk;*.dpr;*.pas|Alle Dateien|*.*';
     En: 'Projects and files|*.dproj;*.groupproj;*.dpk;*.dpr;*.pas|All files|*.*'),
    (De: 'JSON (*.json)|*.json'; En: 'JSON (*.json)|*.json'),
    (De: 'Es laufen noch Befehle. Abbrechen und beenden?'; En: 'Commands are still running. Cancel and exit?'),
    (De: 'Optionen'; En: 'Options'),
    (De: 'Ordner wählen'; En: 'Choose folder'));

class function TMonitorTexts.Text(AText: TMonitorText): string;
begin
  Result := cTexts[AText].Text;
end;

class function TMonitorTexts.Fmt(AText: TMonitorText; const AArgs: array of const): string;
begin
  Result := cTexts[AText].Fmt(AArgs);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Monitor.Texts', cTexts);

end.
