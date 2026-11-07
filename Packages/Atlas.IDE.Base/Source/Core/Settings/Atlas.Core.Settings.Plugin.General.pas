unit Atlas.Core.Settings.Plugin.General;

// Einstellungen des IDE-Plugins, Bereich Allgemein (Statusfeld, Server, Index, Robustheit) (#227, ADR 0017):
// Felder, Vorgaben, Grenzen, Lesen und Schreiben. TAtlasPluginSettings (Atlas.Core.Settings.Plugin)
// fasst die Bereiche zusammen und reicht die Felder als Eigenschaften durch.

interface

uses
  Atlas.Core.Settings.Plugin.Store;

const
  cMinHangThreshold = 100;
  cMaxHangThreshold = 10000;
  /// <summary>Wie TAtlasTimeLimit.cMinMs/MaxMs (#493).</summary>
  cMinProviderTimeLimit = 50;
  cMaxProviderTimeLimit = 5000;
  /// <summary>Speichergrenze des Symbolindex im Server (#492); 0 = unbegrenzt.</summary>
  cMaxMemoryBudgetMb = 65536;
  /// <summary>Grenzen für safeMode.startupTimeoutMs und safeMode.keepSettingsHistory (#722).</summary>
  cMinSafeStartupTimeout = 1000;
  cMaxSafeStartupTimeout = 120000;
  cMaxSafeSettingsHistory = 50;
  /// <summary>Grenzen für notifications.maxEntries (#601); wie TAtlasNotificationCenter.cMinEntries/MaxMaxEntries
  /// (Test prüft Gleichheit).</summary>
  cMinNotificationEntries = 10;
  cMaxNotificationEntries = 1000;

type
  /// <summary>Plugin-Einstellungen: Server, Index, sicherer Modus, Architektur und Hotspots.</summary>
  TAtlasPluginGeneralServerSettings = record
    /// <summary>Ab so vielen Millisekunden ohne Antwort gilt die IDE als hängend (#501).</summary>
    HangThresholdMs: Integer;
    /// <summary>Zeitlimit für Aufrufe von Datenquellen aus dem Hauptthread (#493); länger gilt als Fehler.</summary>
    ProviderTimeLimitMs: Integer;
    /// <summary>Hinweis im Meldungsfenster nach langen Hängern (ab 2 s, #501).</summary>
    HangHint: Boolean;
    /// <summary>Pfad zu AtlasServer.exe; leer: neben dem Plugin bzw. Output\Win64\Debug\Bin.</summary>
    ServerPath: string;
    /// <summary>Projektdatei .atlas lesen (#486): Einstellungen für alle im Team aus dem Repository, Vorrang vor
    /// den persönlichen; dazu der Befehl „Projektdatei .atlas öffnen“ (Atlas.TeamFile) mit Tipp. Aus = nur die
    /// persönlichen Einstellungen gelten, Befehl und Tipp verschwinden.</summary>
    TeamFile: Boolean;
    /// <summary>Umfang des Symbolindex für alle Projekte (#652, index.* in settings.json).</summary>
    IndexProjectGroup: Boolean;
    IndexSearchPaths: Boolean;
    IndexLibraryPaths: Boolean;
    /// <summary>Verwendungen der Bezeichner mit indizieren (#492, index.usages).</summary>
    IndexUsages: Boolean;
    /// <summary>Speichergrenze des Symbolindex in MB (#492, memoryBudgetMb); darüber lagert der Server
    /// zuerst die Verwendungen aus. 0 = unbegrenzt.</summary>
    MemoryBudgetMb: Integer;
    /// <summary>Diagnosemodus (#479, diagnosticMode.enabled): Diagnosefenster mit Zeitmessung je Abfrage der
    /// Vervollständigung; Vorgabe aus. Aus heißt: keine Messung, kein Fenster, keine Statuszeile.</summary>
    DiagnosticMode: Boolean;
    /// <summary>Zeiten des Plugins im Diagnosefenster (diagnosticMode.pluginTimings): Hauptthread je
    /// Funktion, Server-Anfragen, Quellen im Hintergrund, Hänger; Vorgabe an, wirkt nur im Diagnosemodus.</summary>
    DiagnosticPluginTimings: Boolean;
    /// <summary>Ab so vielen ms eigener Zeit gilt ein Aufruf als langsam (diagnosticMode.slowThresholdMs,
    /// 1 bis 1000); Vorgabe 16, ein Bild bei 60 Hz.</summary>
    DiagnosticSlowMs: Integer;
    /// <summary>Menüeintrag „Prozesse am Projekt…“ (#62, diagnostics.processes): Index-Cache, Sperre und
    /// angemeldete LSP- und MCP-Prozesse; Vorgabe an.</summary>
    DiagnosticsProcesses: Boolean;
    /// <summary>Fenster „Atlas-Server“ (#1356, server.statusWindow): Speicher, langsamste Units, Regeln und
    /// Anfragen, Diagnosepaket; Befehl Atlas.ServerStatus und Klick in Statusfenster und Statusleiste; Vorgabe an.
    /// </summary>
    ServerStatusWindow: Boolean;
    /// <summary>Architekturübersicht (#1118, architecture.enabled in settings.json): Fenster „Atlas-Architektur“,
    /// Bericht und get_architecture; Vorgabe an.</summary>
    ArchitectureEnabled: Boolean;
    /// <summary>Code-Abfragen (#1351, query.enabled in settings.json): Fenster „Atlas-Abfrage“, Befehl und
    /// query_code; Vorgabe an.</summary>
    QueryEnabled: Boolean;
    /// <summary>Umfang der Übersicht (architecture.scope): 'project' oder 'projectGroup' (Vorgabe).</summary>
    ArchitectureScope: string;
    /// <summary>Bibliotheks-Units (RTL, VCL, Fremdbibliotheken) mitzählen (architecture.includeLibraryUnits).
    /// </summary>
    ArchitectureIncludeLibraryUnits: Boolean;
    /// <summary>So viele zentrale Units (architecture.centralUnits, 5–100, Vorgabe 15).</summary>
    ArchitectureCentralUnits: Integer;
    /// <summary>Hotspots (#1354, hotspots.enabled in settings.json): Fenster „Atlas-Hotspots“, Bericht
    /// (--hotspots) und get_hotspots; Vorgabe an.</summary>
    HotspotsEnabled: Boolean;
    /// <summary>Ausgewerteter Zeitraum in Monaten (hotspots.months, 1–60, Vorgabe 12).</summary>
    HotspotsMonths: Integer;
    /// <summary>Mindestzahl gemeinsamer Commits der Änderungskopplung (hotspots.coupling.minCommits, 2–1000,
    /// Vorgabe 5).</summary>
    HotspotsCouplingMinCommits: Integer;
    /// <summary>Hauptschalter der experimentellen Funktionen (#834, experimental.enabled, liegt in settings.json):
    /// aus = keine Einstellung mit x-experimental wirkt, auch wenn sie an ist; Vorgabe aus.</summary>
    ExperimentalEnabled: Boolean;
    /// <summary>Abgesicherter Start (#722): nach einem Absturz fragen (safeMode.askAfterCrash).</summary>
    SafeAskAfterCrash: Boolean;
    /// <summary>Nach zwei Abstürzen kurz hintereinander ohne Rückfrage abgesichert
    /// (safeMode.autoAfterRepeatedCrash).</summary>
    SafeAutoAfterRepeatedCrash: Boolean;
    /// <summary>Taste beim Laden für den abgesicherten Start: shift, ctrl, none (safeMode.startupKey).</summary>
    SafeStartupKey: string;
    /// <summary>Langsamer Start ab dieser Zeit bis zur freien Nachrichtenschleife: Atlas nennt seine Startanteile
    /// im Meldungsfenster; kein Absturz, abgesichert startet Atlas deshalb nicht (safeMode.startupTimeoutMs,
    /// Bericht N4).</summary>
    SafeStartupTimeoutMs: Integer;
    /// <summary>Gemerkte Einstellungsstände zum Zurücksetzen (safeMode.keepSettingsHistory).</summary>
    SafeKeepSettingsHistory: Integer;
    /// <summary>Fehlerbericht anonymisieren (#108, diagnostics.bugReport.anonymize): Pfade, Benutzername und
    /// Bezeichner ersetzen; Vorgabe an.</summary>
    BugReportAnonymize: Boolean;
    /// <summary>Protokoll atlas.log mit Klarnamen (#1478, diagnostics.log.names); Vorgabe aus: Namen, Pfade und
    /// Meldungen stehen als name#N, datei#N, text#N.</summary>
    LogNames: Boolean;
    /// <summary>Modul-Schalter analysis.enabled (#1454): Analysefenster (Architektur, Unit-Beziehungen, Symbolpfad,
    /// Hotspots); aus = die wirksamen Werte aller Einstellungen des Moduls sind
    /// „aus“ (TAtlasModuleSwitches), gespeichert bleiben sie.</summary>
    AnalysisEnabled: Boolean;
    /// <summary>Vorgaben.</summary>
    class function Defaults: TAtlasPluginGeneralServerSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TAtlasSettingsExchange);
  end;

  /// <summary>Plugin-Einstellungen: Oberfläche, Statusfeld, Benachrichtigungen und Einstellungsübertragung.</summary>
  TAtlasPluginGeneralSettings = record
    /// <summary>Atlas-Feld in der Statusleiste (#591, statusField.enabled).</summary>
    StatusField: Boolean;
    /// <summary>Kennungen der Zeilen, die im Fenster des Felds nicht erscheinen, durch Komma getrennt
    /// (#591, statusField.hidden).</summary>
    StatusFieldHidden: string;
    /// <summary>Kurztext neben „Atlas“ (#591, statusField.showSummary).</summary>
    StatusFieldSummary: Boolean;
    /// <summary>Womit das Feld die Schnellschalter öffnet: 'both' (Rechts- und Doppelklick, Vorgabe),
    /// 'rightClick' oder 'doubleClick' (statusField.openToggles).</summary>
    StatusFieldToggles: string;
    /// <summary>Wo der Fortschritt beim Aufbau des Symbol-Index steht: 'statusField' (Vorgabe; mit
    /// abgeschaltetem Statusfeld im Menütitel), 'menu' (Titel des Menüs Atlas) oder 'off'
    /// (statusField.indexProgress).</summary>
    IndexProgressPlace: string;
    /// <summary>Zustand: Das Fenster „Atlas-Architektur“ wurde einmal rechts neben die Projektverwaltung
    /// gelegt (ui.architectureWindowPlaced); danach gilt die Lage aus dem Desktop der IDE.</summary>
    ArchitectureWindowPlaced: Boolean;
    /// <summary>Zustand: Das Fenster „Unit-Beziehungen“ (#593) wurde einmal rechts neben die Projektverwaltung
    /// gelegt (ui.unitRelationsWindowPlaced); danach gilt die Lage aus dem Desktop der IDE.</summary>
    UnitRelationsWindowPlaced: Boolean;
    /// <summary>Zustand: Das Fenster „Atlas-Hotspots“ wurde einmal rechts neben die Projektverwaltung gelegt
    /// (ui.hotspotsWindowPlaced); danach gilt die Lage aus dem Desktop der IDE.</summary>
    HotspotsWindowPlaced: Boolean;
    /// <summary>Prüfliste „Atlas-Einrichtung“ beim IDE-Start zeigen, solange nicht alles grün ist (#625,
    /// ui.setupChecklist); aus: nur auf Abruf (Menü Atlas, Befehlspalette, Statusfeld).</summary>
    SetupChecklist: Boolean;
    /// <summary>Die Prüfliste war schon einmal offen (#625); vorher öffnet sie beim Start in jedem Fall. Kein
    /// Schlüssel in atlas.json, nur Zustand des Plugins.</summary>
    SetupChecklistSeen: Boolean;
    /// <summary>Tastenkürzel-Tipps (#600, shortcutTips.enabled): nach einem Aufruf per Maus kurz das Kürzel
    /// zeigen; aus: Atlas beobachtet keine Aufrufe und zählt nichts.</summary>
    ShortcutTips: Boolean;
    /// <summary>atlas (nur Befehle von Atlas) oder all (auch die der IDE und anderer Erweiterungen,
    /// shortcutTips.scope).</summary>
    ShortcutTipsScope: string;
    /// <summary>Einmal täglich nach einer neuen Version sehen (#495, updates.check); Vorgabe aus, beim ersten
    /// Start wird gefragt.</summary>
    UpdatesCheck: Boolean;
    /// <summary>Updates installieren (#1519, updates.install): off (nur Hinweis wie #495), ask (Vorgabe: auf Klick
    /// laden und beim Beenden installieren) oder auto (gleich laden, beim Beenden installieren). Wirkt nur mit
    /// UpdatesCheck.</summary>
    UpdatesInstall: string;
    /// <summary>stable (Vorgabe) oder prerelease (auch Vorabversionen, #1519, updates.channel).</summary>
    UpdatesChannel: string;
    /// <summary>Neue Module eines Updates (#1519, updates.newModules): ask (Vorgabe, Auswahl zeigen), install oder
    /// skip.</summary>
    UpdatesNewModules: string;
    /// <summary>Benachrichtigungszentrale (#601, notifications.enabled): Hinweise sammeln, Zähler im
    /// Atlas-Statusfeld, Liste und Befehl Atlas.Notifications; aus = jede Funktion zeigt ihre Einblendung wie
    /// vor #601, nichts wird gesammelt.</summary>
    Notifications: Boolean;
    /// <summary>Verhalten je Quelle (#601, notifications.sources): "quelle=verhalten" mit Komma getrennt,
    /// verhalten show, collect oder off; nicht genannte Quellen zeigen (show).</summary>
    NotificationsSources: string;
    /// <summary>Höchstens so viele Einträge in der Liste (#601, notifications.maxEntries, 10–1000).</summary>
    NotificationsMaxEntries: Integer;
    /// <summary>Einstellungen exportieren, importieren und zurücksetzen (#723, settings.exportImport): Befehle der
    /// Befehlspalette, Knöpfe der Optionsseite und Kontextmenü „Auf Standard zurücksetzen“; aus = alles davon
    /// verschwindet samt Tipps.</summary>
    SettingsExportImport: Boolean;
    /// <summary>Geänderte Werte auf der Optionsseite mit einem Punkt vor der Beschriftung markieren (#723,
    /// settings.markModified).</summary>
    SettingsMarkModified: Boolean;
    /// <summary>Vor jedem Import und vor „Alles zurücksetzen“ den aktuellen Stand als Datei sichern (#723,
    /// settings.backupBeforeImport; %APPDATA%\Atlas\Backups).</summary>
    SettingsBackupBeforeImport: Boolean;
    /// <summary>Zugangsdaten beim Export (#723, settings.exportSecrets): "omit" lässt sie aus, "placeholder"
    /// schreibt den Platzhalter.</summary>
    SettingsExportSecrets: string;
    /// <summary>Vorgaben.</summary>
    class function Defaults: TAtlasPluginGeneralSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TAtlasSettingsExchange);
  end;

implementation

uses
  System.Math,
  System.SysUtils,
  Atlas.Core.Notifications.Sources;

{ TAtlasPluginGeneralServerSettings }

class function TAtlasPluginGeneralServerSettings.Defaults: TAtlasPluginGeneralServerSettings;
begin
  Result.HangThresholdMs := 500;
  Result.ProviderTimeLimitMs := 200;
  Result.HangHint := True;
  Result.ServerPath := '';
  Result.TeamFile := True;
  // Wie die Vorgaben im Schema (atlas.schema.json, index).
  Result.IndexProjectGroup := True;
  Result.IndexSearchPaths := True;
  Result.IndexLibraryPaths := False;
  Result.IndexUsages := True;
  Result.MemoryBudgetMb := 768;
  Result.DiagnosticMode := False;
  Result.DiagnosticPluginTimings := True;
  Result.DiagnosticSlowMs := 16;
  Result.DiagnosticsProcesses := True;
  Result.ServerStatusWindow := True;
  // Wie die Vorgaben im Schema (atlas.schema.json, architecture).
  Result.ArchitectureEnabled := True;
  Result.QueryEnabled := True;
  Result.ArchitectureScope := 'projectGroup';
  Result.ArchitectureIncludeLibraryUnits := False;
  Result.ArchitectureCentralUnits := 15;
  // Wie die Vorgaben im Schema (atlas.schema.json, hotspots).
  Result.HotspotsEnabled := True;
  Result.HotspotsMonths := 12;
  Result.HotspotsCouplingMinCommits := 5;
  Result.ExperimentalEnabled := False;
  Result.SafeAskAfterCrash := True;
  Result.SafeAutoAfterRepeatedCrash := True;
  Result.SafeStartupKey := 'shift';
  // Gemessen bis zur freien Nachrichtenschleife, mit Desktop, übrigen Packages und Projekt (#874).
  Result.SafeStartupTimeoutMs := 30000;
  Result.SafeKeepSettingsHistory := 5;
  Result.BugReportAnonymize := True;
  Result.LogNames := False;
  Result.AnalysisEnabled := True;
end;

procedure TAtlasPluginGeneralServerSettings.Normalize;
begin
  DiagnosticSlowMs := EnsureRange(DiagnosticSlowMs, 1, 1000);
  HangThresholdMs := EnsureRange(HangThresholdMs, cMinHangThreshold, cMaxHangThreshold);
  ProviderTimeLimitMs := EnsureRange(ProviderTimeLimitMs, cMinProviderTimeLimit, cMaxProviderTimeLimit);
  MemoryBudgetMb := EnsureRange(MemoryBudgetMb, 0, cMaxMemoryBudgetMb);
  ArchitectureScope := Choice(ArchitectureScope, ['projectGroup', 'project']);
  ArchitectureCentralUnits := EnsureRange(ArchitectureCentralUnits, 5, 100);
  HotspotsMonths := EnsureRange(HotspotsMonths, 1, 60);
  HotspotsCouplingMinCommits := EnsureRange(HotspotsCouplingMinCommits, 2, 1000);
  SafeStartupTimeoutMs := EnsureRange(SafeStartupTimeoutMs, cMinSafeStartupTimeout, cMaxSafeStartupTimeout);
  SafeKeepSettingsHistory := EnsureRange(SafeKeepSettingsHistory, 0, cMaxSafeSettingsHistory);
  SafeStartupKey := LowerCase(Trim(SafeStartupKey));
  if (SafeStartupKey <> 'shift') and (SafeStartupKey <> 'ctrl') and (SafeStartupKey <> 'none') then
  begin
    SafeStartupKey := 'shift';
  end;
end;

procedure TAtlasPluginGeneralServerSettings.Exchange(const AIo: TAtlasSettingsExchange);
begin
  AIo.Number('HangThresholdMs', HangThresholdMs);
  AIo.Number('ProviderTimeLimitMs', ProviderTimeLimitMs);
  AIo.Flag('HangHint', HangHint);
  AIo.TrimmedText('ServerPath', ServerPath);
  AIo.Flag('TeamFile', TeamFile);
  AIo.Flag('IndexProjectGroup', IndexProjectGroup);
  AIo.Flag('IndexSearchPaths', IndexSearchPaths);
  AIo.Flag('IndexLibraryPaths', IndexLibraryPaths);
  AIo.Flag('IndexUsages', IndexUsages);
  AIo.Number('MemoryBudgetMb', MemoryBudgetMb);
  AIo.Flag('DiagnosticMode', DiagnosticMode);
  AIo.Flag('DiagnosticPluginTimings', DiagnosticPluginTimings);
  AIo.Number('DiagnosticSlowMs', DiagnosticSlowMs);
  AIo.Flag('DiagnosticsProcesses', DiagnosticsProcesses);
  AIo.Flag('ServerStatusWindow', ServerStatusWindow);
  AIo.Flag('ArchitectureEnabled', ArchitectureEnabled);
  AIo.Flag('QueryEnabled', QueryEnabled);
  AIo.Text('ArchitectureScope', ArchitectureScope);
  AIo.Flag('ArchitectureIncludeLibraryUnits', ArchitectureIncludeLibraryUnits);
  AIo.Number('ArchitectureCentralUnits', ArchitectureCentralUnits);
  AIo.Flag('HotspotsEnabled', HotspotsEnabled);
  AIo.Number('HotspotsMonths', HotspotsMonths);
  AIo.Number('HotspotsCouplingMinCommits', HotspotsCouplingMinCommits);
  AIo.Flag('ExperimentalEnabled', ExperimentalEnabled);
  AIo.Flag('SafeAskAfterCrash', SafeAskAfterCrash);
  AIo.Flag('SafeAutoAfterRepeatedCrash', SafeAutoAfterRepeatedCrash);
  AIo.Text('SafeStartupKey', SafeStartupKey);
  AIo.Number('SafeStartupTimeoutMs', SafeStartupTimeoutMs);
  AIo.Number('SafeKeepSettingsHistory', SafeKeepSettingsHistory);
  AIo.Flag('BugReportAnonymize', BugReportAnonymize);
  AIo.Flag('LogNames', LogNames);
  AIo.Flag('AnalysisEnabled', AnalysisEnabled);
end;

{ TAtlasPluginGeneralSettings }

class function TAtlasPluginGeneralSettings.Defaults: TAtlasPluginGeneralSettings;
begin
  Result.StatusField := True;
  Result.StatusFieldHidden := '';
  Result.StatusFieldSummary := True;
  Result.StatusFieldToggles := 'both';
  Result.IndexProgressPlace := 'statusField';
  Result.ArchitectureWindowPlaced := False;
  Result.UnitRelationsWindowPlaced := False;
  Result.HotspotsWindowPlaced := False;
  Result.SetupChecklist := True;
  Result.SetupChecklistSeen := False;
  Result.ShortcutTips := True;
  Result.ShortcutTipsScope := 'all';
  Result.UpdatesCheck := False;
  Result.UpdatesInstall := 'ask';
  Result.UpdatesChannel := 'stable';
  Result.UpdatesNewModules := 'ask';
  Result.Notifications := True;
  Result.NotificationsSources := '';
  Result.NotificationsMaxEntries := 200;
  Result.SettingsExportImport := True;
  Result.SettingsMarkModified := True;
  Result.SettingsBackupBeforeImport := True;
  Result.SettingsExportSecrets := 'omit';
end;

procedure TAtlasPluginGeneralSettings.Normalize;
begin
  if SameText(Trim(StatusFieldToggles), 'rightClick') then
  begin
    StatusFieldToggles := 'rightClick';
  end
  else if SameText(Trim(StatusFieldToggles), 'doubleClick') then
  begin
    StatusFieldToggles := 'doubleClick';
  end
  else
  begin
    StatusFieldToggles := 'both';
  end;
  if SameText(Trim(IndexProgressPlace), 'menu') then
  begin
    IndexProgressPlace := 'menu';
  end
  else if SameText(Trim(IndexProgressPlace), 'off') then
  begin
    IndexProgressPlace := 'off';
  end
  else
  begin
    IndexProgressPlace := 'statusField';
  end;
  if SameText(Trim(ShortcutTipsScope), 'atlas') then
  begin
    ShortcutTipsScope := 'atlas';
  end
  else
  begin
    ShortcutTipsScope := 'all';
  end;
  NotificationsSources := TAtlasNotificationSources.Normalize(NotificationsSources);
  NotificationsMaxEntries := EnsureRange(NotificationsMaxEntries, cMinNotificationEntries, cMaxNotificationEntries);
  SettingsExportSecrets := Choice(SettingsExportSecrets, ['omit', 'placeholder']);
  UpdatesInstall := Choice(UpdatesInstall, ['ask', 'off', 'auto']);
  UpdatesChannel := Choice(UpdatesChannel, ['stable', 'prerelease']);
  UpdatesNewModules := Choice(UpdatesNewModules, ['ask', 'install', 'skip']);
end;

procedure TAtlasPluginGeneralSettings.Exchange(const AIo: TAtlasSettingsExchange);
begin
  AIo.Flag('StatusField', StatusField);
  AIo.TrimmedText('StatusFieldHidden', StatusFieldHidden);
  AIo.Flag('StatusFieldSummary', StatusFieldSummary);
  AIo.Text('StatusFieldToggles', StatusFieldToggles);
  AIo.Text('IndexProgressPlace', IndexProgressPlace);
  AIo.Flag('ArchitectureWindowPlaced', ArchitectureWindowPlaced);
  AIo.Flag('UnitRelationsWindowPlaced', UnitRelationsWindowPlaced);
  AIo.Flag('HotspotsWindowPlaced', HotspotsWindowPlaced);
  AIo.Flag('SetupChecklist', SetupChecklist);
  AIo.Flag('SetupChecklistSeen', SetupChecklistSeen);
  AIo.Flag('ShortcutTips', ShortcutTips);
  AIo.Text('ShortcutTipsScope', ShortcutTipsScope);
  AIo.Flag('UpdatesCheck', UpdatesCheck);
  AIo.Text('UpdatesInstall', UpdatesInstall);
  AIo.Text('UpdatesChannel', UpdatesChannel);
  AIo.Text('UpdatesNewModules', UpdatesNewModules);
  AIo.Flag('Notifications', Notifications);
  AIo.Text('NotificationsSources', NotificationsSources);
  AIo.Number('NotificationsMaxEntries', NotificationsMaxEntries);
  AIo.Flag('SettingsExportImport', SettingsExportImport);
  AIo.Flag('SettingsMarkModified', SettingsMarkModified);
  AIo.Flag('SettingsBackupBeforeImport', SettingsBackupBeforeImport);
  AIo.Text('SettingsExportSecrets', SettingsExportSecrets);
end;

end.
