unit Atlas.Core.Settings.Plugin.Welcome;

// Einstellungen des IDE-Plugins, Bereich Willkommensseite (welcomePage.*) (#227):
// Felder, Vorgaben, Grenzen, Lesen und Schreiben. TAtlasPluginSettings (Atlas.Core.Settings.Plugin)
// fasst die Bereiche zusammen und reicht die Felder als Eigenschaften durch.

interface

uses
  Atlas.Core.Settings.Plugin.Store;

const
  /// <summary>Grenzen für welcomePage.maxProjects (#592); wie TAtlasWelcomeProjects.cMinMax/cMaxMax.</summary>
  cMinWelcomeProjects = 1;
  cMaxWelcomeProjects = 30;
  /// <summary>Spalten der Willkommensseite (#767, welcomePage.columns).</summary>
  cMinWelcomeColumns = 1;
  cMaxWelcomeColumns = 3;
  /// <summary>Name des Layouts, das Atlas anlegt (#767, welcomePage.activeLayout).</summary>
  cDefaultWelcomeLayoutName = 'Standard';
  /// <summary>Grenzen der Stunden für welcomePage.unsaved.* (#762); wie TAtlasWelcomeUnsaved.cMaxHours.</summary>
  cMinUnsavedHours = 0;
  cMaxUnsavedHours = 8760;
  /// <summary>Grenzen für welcomePage.continue.count (#755); wie TAtlasWelcomeContinue.cMinCount/cMaxCount.</summary>
  cMinContinueCount = 1;
  cMaxContinueCount = 20;
  /// <summary>Grenzen für welcomePage.trends.points (#758); wie TAtlasProjectTrendLog.cMinPoints/MaxPoints.</summary>
  cMinTrendPoints = 2;
  cMaxTrendPoints = 100;
  /// <summary>Grenzen für welcomePage.tests.maxFailures und welcomePage.tests.ci.intervalMinutes (#763); wie
  /// TAtlasTestResults (Test prüft Gleichheit).</summary>
  cMinTestFailures = 1;
  cMaxTestFailures = 50;
  cMinCiIntervalMinutes = 1;
  cMaxCiIntervalMinutes = 1440;
  /// <summary>Vorgabe für welcomePage.tests.ci.provider (#763).</summary>
  cDefaultCiProvider = 'jenkins';
  /// <summary>Vorgabe für welcomePage.trends.series (#758): alle Reihen, Namen wie
  /// TAtlasProjectSummaries.cTrendKeys.</summary>
  cDefaultTrendSeries = 'warnings,ruleHits,todos,duration,methodLength';
  /// <summary>Vorgabe für welcomePage.help.reportUrl (#766): Seite für neue Issues des Atlas-Repositorys.
  /// </summary>
  cDefaultHelpReportUrl = 'https://github.com/xKnockOut/Atlas-IDE-Expert/issues/new';
  /// <summary>Reihen des Projektverlaufs (#758) wie TAtlasProjectSummaries.cTrendKeys
  /// (Test prüft Gleichheit).</summary>
  cTrendSeriesNames: array[0..4] of string = ('warnings', 'ruleHits', 'todos', 'duration', 'methodLength');
  // Bekannte CI-Anbieter für welcomePage.tests.ci.provider (#763).
  cCiProviders: array[0..0] of string = ('jenkins');
  /// <summary>Knöpfe der Schnellaktionen (#764) wie TAtlasWelcomeQuickActions.cNames (Test prüft Gleichheit; die
  /// Einstellungen kennen die Willkommensseite nicht).</summary>
  cQuickActionNames: array[0..6] of string = ('build', 'tests', 'run', 'pull', 'folder', 'console', 'tasks');
  cQuickActionsDefaultConsole = 'wt.exe';

type
  /// <summary>Plugin-Einstellungen: Aufbau und Verhalten der Willkommensseite.</summary>
  TAtlasPluginWelcomeSettings = record
    /// <summary>Hauptschalter der Atlas-Willkommensseite (#753, welcomePage.enabled): Atlas-Bereiche auf der
    /// Willkommensseite der IDE und Fenster „Atlas-Start“.</summary>
    WelcomePage: Boolean;
    /// <summary>Atlas-Bereiche auf der Willkommensseite der IDE (welcomePage.ideWelcomePage, #761); unabhängig
    /// vom Fenster „Atlas-Start“. Ohne Schnittstelle der IDE wirkungslos.</summary>
    WelcomePageIdePage: Boolean;
    /// <summary>off oder atlas (welcomePage.layout); setzt der Befehl „Atlas-Layout anwenden“. Gilt nur auf
    /// der Willkommensseite der IDE.</summary>
    WelcomePageLayout: string;
    /// <summary>Fenster „Atlas-Start“ beim Start der IDE öffnen (welcomePage.openOnStart, #1114); sonst nur
    /// über Menü, Palette und Desktop.</summary>
    WelcomePageOpenOnStart: Boolean;
    /// <summary>Fenster „Atlas-Start“ öffnen, sobald das letzte Projekt geschlossen ist
    /// (welcomePage.openWhenNoProject, #1114).</summary>
    WelcomePageOpenWhenNoProject: Boolean;
    /// <summary>Kopf mit Symbol und Version (welcomePage.header) und Grußzeile darin (welcomePage.greeting).</summary>
    WelcomePageHeader: Boolean;
    WelcomePageGreeting: Boolean;
    /// <summary>Karte „Neu in Atlas“ (#756, welcomePage.whatsNew): off, afterUpdate (einmalig nach einem
    /// Versionswechsel) oder always.</summary>
    WelcomePageWhatsNew: string;
    /// <summary>Zuletzt gesehene Version der Karte „Neu in Atlas“ (#756); kein Schlüssel in atlas.json, nur
    /// Zustand des Plugins. '' vor dem ersten Start.</summary>
    WhatsNewSeen: string;
    /// <summary>Nutzung je Befehl lokal zählen (#757, tips.usageTracking; %LOCALAPPDATA%\Atlas\usage.json); aus =
    /// Tipps der Reihe nach ohne Bezug zur Nutzung, auch für die Tastenkürzel-Tipps (#600).</summary>
    TipsUsageTracking: Boolean;
    /// <summary>Willkommensseite frei anordnen (#767, welcomePage.customLayout): Bearbeitungsleiste „Seite
    /// anpassen“, Rechtsklick „Ausblenden“ und Befehl Atlas.WelcomeCustomize; aus = festes Atlas-Layout.</summary>
    WelcomePageCustomLayout: Boolean;
    /// <summary>Spalten des aktiven Layouts (#767, welcomePage.columns, 1–3).</summary>
    WelcomePageColumns: Integer;
    /// <summary>Gespeicherte Layouts als JSON-Liste (#767, welcomePage.layouts); '' = nur das Layout „Standard“
    /// mit den Plätzen von Atlas.</summary>
    WelcomePageLayouts: string;
    /// <summary>Name des aktiven Layouts (#767, welcomePage.activeLayout); unbekannt = das erste Layout.</summary>
    WelcomePageActiveLayout: string;
    /// <summary>Vorgaben.</summary>
    class function Defaults: TAtlasPluginWelcomeSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TAtlasSettingsExchange);
  end;

  /// <summary>Plugin-Einstellungen: Kacheln der Willkommensseite.</summary>
  TAtlasPluginWelcomeTilesSettings = record
    /// <summary>Suchfeld im Kopf (#760, welcomePage.search) und dessen Gruppe „Symbole“ (welcomePage.search.symbols,
    /// braucht laufenden Server).</summary>
    WelcomePageSearch: Boolean;
    WelcomePageSearchSymbols: Boolean;
    /// <summary>Bereich „Projekte“ mit Zustand je Projekt (#592, welcomePage.projectStatus).</summary>
    WelcomePageProjectStatus: Boolean;
    /// <summary>Anzahl der gezeigten Projekte (#592, welcomePage.maxProjects, 1–30).</summary>
    WelcomePageMaxProjects: Integer;
    /// <summary>Branch und Änderungen beim Anzeigen frisch abfragen (#592, welcomePage.refreshVcs); sonst gilt
    /// der gespeicherte Stand.</summary>
    WelcomePageRefreshVcs: Boolean;
    /// <summary>Bereich „Nicht gesichert“ (#762, welcomePage.unsaved).</summary>
    WelcomePageUnsaved: Boolean;
    /// <summary>Nicht Gesichertes erst ab diesem Alter zeigen (#762, welcomePage.unsaved.minAgeHours,
    /// 0–8760).</summary>
    WelcomePageUnsavedMinAgeHours: Integer;
    /// <summary>Ab diesem Alter gelb (#762, welcomePage.unsaved.warnHours, 0–8760).</summary>
    WelcomePageUnsavedWarnHours: Integer;
    /// <summary>Ab diesem Alter rot (#762, welcomePage.unsaved.alertHours, 0–8760, nie unter warnHours).</summary>
    WelcomePageUnsavedAlertHours: Integer;
    /// <summary>Bereich ausblenden, wenn nichts zu zeigen ist (#762, welcomePage.unsaved.hideWhenClean).</summary>
    WelcomePageUnsavedHideWhenClean: Boolean;
    /// <summary>Zustandskachel „Atlas“ (#754, welcomePage.statusTile).</summary>
    WelcomePageStatusTile: Boolean;
    /// <summary>Zustandskachel nur zeigen, wenn eine Zeile gelb oder rot ist (#754,
    /// welcomePage.statusTile.onlyProblems).</summary>
    WelcomePageStatusTileOnlyProblems: Boolean;
    /// <summary>Karte „Atlas entdecken“ (#757, welcomePage.discover).</summary>
    WelcomePageDiscover: Boolean;
    /// <summary>Bereich „Hilfe und Rückmeldung“ (#766, welcomePage.help): Atlas-Doku, Tastenkürzel, Problem
    /// melden.</summary>
    WelcomePageHelp: Boolean;
    /// <summary>Ziel für „Issue-Seite öffnen“ (#766, welcomePage.help.reportUrl); nur http:// und https://, sonst
    /// die Vorgabe.</summary>
    WelcomePageHelpReportUrl: string;
    /// <summary>Ordner für das Diagnosepaket (#766, welcomePage.help.reportFolder); '' = Desktop.</summary>
    WelcomePageHelpReportFolder: string;
    /// <summary>Karte „Projekt für Atlas einrichten“ und Befehl Atlas.ProjectSetup (#759,
    /// welcomePage.projectSetup); aus = kein Bereich, auch keine Knöpfe „Neu mit Atlas“.</summary>
    WelcomePageProjectSetup: Boolean;
    /// <summary>Knöpfe „Neu mit Atlas“ (Unit, Formular, Testklasse) unter der Karte (#759,
    /// welcomePage.newFromTemplate).</summary>
    WelcomePageNewFromTemplate: Boolean;
    /// <summary>Bereich „Weiterarbeiten“ (#755, welcomePage.continue): Arbeitsstände merken und fortsetzen.
    /// </summary>
    WelcomePageContinue: Boolean;
    /// <summary>Anzahl der Arbeitsstände (#755, welcomePage.continue.count, 1–20).</summary>
    WelcomePageContinueCount: Integer;
    /// <summary>„Neu seit deinem letzten Öffnen“: eingehende Commits (#755, welcomePage.continue.incoming).</summary>
    WelcomePageContinueIncoming: Boolean;
    /// <summary>Vor dem Anzeigen im Hintergrund fetch ausführen (#755, welcomePage.continue.fetch).</summary>
    WelcomePageContinueFetch: Boolean;
    /// <summary>Reiter „Gemerkt“ mit Notizen, Lesezeichen und Favoriten (#755, welcomePage.saved).</summary>
    WelcomePageSaved: Boolean;
    /// <summary>Bereich „Projektverlauf“ (#758, welcomePage.trends): Messpunkte je Build mitschreiben und als
    /// Linien zeigen; aus = kein Bereich, nichts wird mitgeschrieben.</summary>
    WelcomePageTrends: Boolean;
    /// <summary>Gespeicherte Builds je Projekt (#758, welcomePage.trends.points, 2–100).</summary>
    WelcomePageTrendsPoints: Integer;
    /// <summary>Gezeigte Reihen (#758, welcomePage.trends.series): Namen durch Komma getrennt, in der Reihenfolge
    /// warnings, ruleHits, todos, duration, methodLength; '' = keine.</summary>
    WelcomePageTrendsSeries: string;
    /// <summary>Bereich „Testergebnisse“ (#763, welcomePage.tests): letzter Testlauf je Projekt mit den
    /// fehlgeschlagenen Tests; aus = kein Bereich.</summary>
    WelcomePageTests: Boolean;
    /// <summary>Höchstens so viele fehlgeschlagene Tests in der Liste (#763, welcomePage.tests.maxFailures, 1–50).
    /// </summary>
    WelcomePageTestsMaxFailures: Integer;
    /// <summary>Build-Server abfragen (#763, welcomePage.tests.ci); aus = kein Netzzugriff. Server und Job stehen
    /// in .atlas (ci.url, ci.job).</summary>
    WelcomePageTestsCi: Boolean;
    /// <summary>Anbieter, wenn .atlas keinen nennt (#763, welcomePage.tests.ci.provider): "jenkins".</summary>
    WelcomePageTestsCiProvider: string;
    /// <summary>Höchstens alle so viele Minuten fragen (#763, welcomePage.tests.ci.intervalMinutes, 1–1440).
    /// </summary>
    WelcomePageTestsCiIntervalMinutes: Integer;
    /// <summary>Hinweis in der Benachrichtigungszentrale, wenn der Build auf dem Server rot wird (#763,
    /// welcomePage.tests.ci.notify).</summary>
    WelcomePageTestsCiNotify: Boolean;
    /// <summary>Schnellaktionen je Projekt in „Projekte“ und „Weiterarbeiten“ (#764, welcomePage.quickActions):
    /// Knöpfe in der Zeile unter der Maus bzw. mit dem Fokus; aus = keine Knöpfe, keine Tasten.</summary>
    WelcomePageQuickActions: Boolean;
    /// <summary>Gezeigte Knöpfe (#764, welcomePage.quickActions.items): Namen durch Komma getrennt, in der
    /// Reihenfolge build, tests, run, pull, folder, console, tasks (#900); '' = keiner.</summary>
    WelcomePageQuickActionsItems: string;
    /// <summary>Programm für „Konsole“ (#764, welcomePage.quickActions.console): wt.exe (Vorgabe), cmd.exe,
    /// powershell.exe, pwsh.exe oder ein anderes; ohne Windows-Terminal nimmt Atlas cmd.exe.</summary>
    WelcomePageQuickActionsConsole: string;
    /// <summary>Befehl „Zugang zum Build-Server hinterlegen …“ (#763, Atlas.CiLogin) in der Befehlspalette und im
    /// Kontextmenü des Bereichs; aus = der Befehl und sein Tipp verschwinden.</summary>
    CiLogin: Boolean;
    /// <summary>Bereich „Meine Issues“ (#765, welcomePage.issues): offene Issues aus dem Tracker der .atlas
    /// (Abschnitt tracker) mit „Beginnen“; aus = kein Bereich, keine Abfrage, kein Netzzugriff.</summary>
    WelcomePageIssues: Boolean;
    /// <summary>Bereich „Sprint“ (#1277, welcomePage.sprint): aktueller Sprint des Boards (#1272) mit Resttagen,
    /// eigenen Zahlen und Burndown; aus = kein Bereich, keine Abfrage.</summary>
    WelcomePageSprint: Boolean;
    /// <summary>Vorgaben.</summary>
    class function Defaults: TAtlasPluginWelcomeTilesSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TAtlasSettingsExchange);
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.SysUtils;

/// <summary>Bekannte Knöpfe aus AText (Komma, Semikolon, Leerzeichen; Groß-/Kleinschreibung egal) in fester
/// Reihenfolge, jeder einmal; '' = keiner.</summary>
function NormalizedQuickActionItems(const AText: string): string;
var
  mPart: string;
  mIndex: Integer;
  mWanted: array[Low(cQuickActionNames)..High(cQuickActionNames)] of Boolean;
begin
  for mIndex := Low(mWanted) to High(mWanted) do
  begin
    mWanted[mIndex] := False;
  end;
  for mPart in AText.Split([',', ';', ' ']) do
  begin
    for mIndex := Low(cQuickActionNames) to High(cQuickActionNames) do
    begin
      if SameText(Trim(mPart), cQuickActionNames[mIndex]) then
      begin
        mWanted[mIndex] := True;
      end;
    end;
  end;
  Result := '';
  for mIndex := Low(cQuickActionNames) to High(cQuickActionNames) do
  begin
    if mWanted[mIndex] then
    begin
      if Result <> '' then
      begin
        Result := Result + ',';
      end;
      Result := Result + cQuickActionNames[mIndex];
    end;
  end;
end;

/// <summary>Programm für „Konsole“ getrimmt; leer = wt.exe.</summary>
function NormalizedQuickActionConsole(const AText: string): string;
begin
  Result := Trim(AText);
  if Result = '' then
  begin
    Result := cQuickActionsDefaultConsole;
  end;
end;

/// <summary>Bekannter CI-Anbieter in Kleinbuchstaben; sonst die Vorgabe.</summary>
function NormalizedCiProvider(const AText: string): string;
var
  mName: string;
begin
  for mName in cCiProviders do
  begin
    if SameText(Trim(AText), mName) then
    begin
      Exit(mName);
    end;
  end;
  Result := cDefaultCiProvider;
end;

/// <summary>Bekannte Reihen aus AText (Komma, Semikolon, Leerzeichen; Groß-/Kleinschreibung egal) in fester
/// Reihenfolge, jede einmal.</summary>
function NormalizedTrendSeries(const AText: string): string;
var
  mParts: TArray<string>;
  mPart: string;
  mIndex: Integer;
  mWanted: array[0..4] of Boolean;
begin
  for mIndex := Low(mWanted) to High(mWanted) do
  begin
    mWanted[mIndex] := False;
  end;
  mParts := AText.Split([',', ';', ' ']);
  for mPart in mParts do
  begin
    for mIndex := Low(cTrendSeriesNames) to High(cTrendSeriesNames) do
    begin
      if SameText(Trim(mPart), cTrendSeriesNames[mIndex]) then
      begin
        mWanted[mIndex] := True;
      end;
    end;
  end;
  Result := '';
  for mIndex := Low(cTrendSeriesNames) to High(cTrendSeriesNames) do
  begin
    if mWanted[mIndex] then
    begin
      if Result <> '' then
      begin
        Result := Result + ',';
      end;
      Result := Result + cTrendSeriesNames[mIndex];
    end;
  end;
end;

/// <summary>http:// oder https:// mit etwas danach, ohne Leer- und Steuerzeichen (#766).</summary>
function IsWebAddress(const AValue: string): Boolean;
var
  mIndex: Integer;
begin
  Result := (StartsText('https://', AValue) and (Length(AValue) > 8)) or
    (StartsText('http://', AValue) and (Length(AValue) > 7));
  if not Result then
  begin
    Exit;
  end;
  for mIndex := 1 to Length(AValue) do
  begin
    if Ord(AValue[mIndex]) <= 32 then
    begin
      Exit(False);
    end;
  end;
end;

{ TAtlasPluginWelcomeSettings }

class function TAtlasPluginWelcomeSettings.Defaults: TAtlasPluginWelcomeSettings;
begin
  Result.WelcomePage := True;
  Result.WelcomePageIdePage := True;
  Result.WelcomePageLayout := 'off';
  Result.WelcomePageOpenOnStart := False;
  Result.WelcomePageOpenWhenNoProject := True;
  Result.WelcomePageHeader := True;
  Result.WelcomePageGreeting := True;
  Result.WelcomePageWhatsNew := 'afterUpdate';
  Result.WhatsNewSeen := '';
  Result.TipsUsageTracking := True;
  Result.WelcomePageCustomLayout := True;
  Result.WelcomePageColumns := 2;
  Result.WelcomePageLayouts := '';
  Result.WelcomePageActiveLayout := cDefaultWelcomeLayoutName;
end;

procedure TAtlasPluginWelcomeSettings.Normalize;
begin
  WelcomePageColumns := EnsureRange(WelcomePageColumns, cMinWelcomeColumns, cMaxWelcomeColumns);
  WelcomePageLayouts := Trim(WelcomePageLayouts);
  WelcomePageActiveLayout := Trim(WelcomePageActiveLayout);
  if WelcomePageActiveLayout = '' then
  begin
    WelcomePageActiveLayout := cDefaultWelcomeLayoutName;
  end;
  if SameText(Trim(WelcomePageLayout), 'atlas') then
  begin
    WelcomePageLayout := 'atlas';
  end
  else
  begin
    WelcomePageLayout := 'off';
  end;
  if SameText(Trim(WelcomePageWhatsNew), 'off') then
  begin
    WelcomePageWhatsNew := 'off';
  end
  else if SameText(Trim(WelcomePageWhatsNew), 'always') then
  begin
    WelcomePageWhatsNew := 'always';
  end
  else
  begin
    WelcomePageWhatsNew := 'afterUpdate';
  end;
  WhatsNewSeen := Trim(WhatsNewSeen);
end;

procedure TAtlasPluginWelcomeSettings.Exchange(const AIo: TAtlasSettingsExchange);
begin
  AIo.Flag('WelcomePage', WelcomePage);
  AIo.Flag('WelcomePageIdePage', WelcomePageIdePage);
  AIo.Text('WelcomePageLayout', WelcomePageLayout);
  AIo.Flag('WelcomePageOpenOnStart', WelcomePageOpenOnStart);
  AIo.Flag('WelcomePageOpenWhenNoProject', WelcomePageOpenWhenNoProject);
  AIo.Flag('WelcomePageHeader', WelcomePageHeader);
  AIo.Flag('WelcomePageGreeting', WelcomePageGreeting);
  AIo.Text('WelcomePageWhatsNew', WelcomePageWhatsNew);
  AIo.Text('WhatsNewSeen', WhatsNewSeen);
  AIo.Flag('TipsUsageTracking', TipsUsageTracking);
  AIo.Flag('WelcomePageCustomLayout', WelcomePageCustomLayout);
  AIo.Number('WelcomePageColumns', WelcomePageColumns);
  AIo.Text('WelcomePageLayouts', WelcomePageLayouts);
  AIo.Text('WelcomePageActiveLayout', WelcomePageActiveLayout);
end;

{ TAtlasPluginWelcomeTilesSettings }

class function TAtlasPluginWelcomeTilesSettings.Defaults: TAtlasPluginWelcomeTilesSettings;
begin
  Result.WelcomePageSearch := True;
  Result.WelcomePageSearchSymbols := True;
  Result.WelcomePageProjectStatus := True;
  Result.WelcomePageMaxProjects := 8;
  Result.WelcomePageRefreshVcs := True;
  Result.WelcomePageUnsaved := True;
  Result.WelcomePageUnsavedMinAgeHours := 0;
  Result.WelcomePageUnsavedWarnHours := 24;
  Result.WelcomePageUnsavedAlertHours := 72;
  Result.WelcomePageUnsavedHideWhenClean := False;
  Result.WelcomePageStatusTile := True;
  Result.WelcomePageStatusTileOnlyProblems := False;
  Result.WelcomePageDiscover := True;
  Result.WelcomePageHelp := True;
  Result.WelcomePageHelpReportUrl := cDefaultHelpReportUrl;
  Result.WelcomePageHelpReportFolder := '';
  Result.WelcomePageProjectSetup := True;
  Result.WelcomePageNewFromTemplate := True;
  Result.WelcomePageContinue := True;
  Result.WelcomePageContinueCount := 5;
  Result.WelcomePageTrends := True;
  Result.WelcomePageTrendsPoints := 30;
  Result.WelcomePageTrendsSeries := cDefaultTrendSeries;
  Result.WelcomePageTests := True;
  Result.WelcomePageTestsMaxFailures := 5;
  Result.WelcomePageTestsCi := False;
  Result.WelcomePageTestsCiProvider := cDefaultCiProvider;
  Result.WelcomePageTestsCiIntervalMinutes := 10;
  Result.WelcomePageTestsCiNotify := True;
  Result.CiLogin := True;
  Result.WelcomePageQuickActions := True;
  Result.WelcomePageQuickActionsItems := string.Join(',', cQuickActionNames);
  Result.WelcomePageQuickActionsConsole := cQuickActionsDefaultConsole;
  Result.WelcomePageIssues := False;
  Result.WelcomePageSprint := True;
  Result.WelcomePageContinueIncoming := True;
  Result.WelcomePageContinueFetch := False;
  Result.WelcomePageSaved := True;
end;

procedure TAtlasPluginWelcomeTilesSettings.Normalize;
begin
  WelcomePageMaxProjects := EnsureRange(WelcomePageMaxProjects, cMinWelcomeProjects, cMaxWelcomeProjects);
  WelcomePageUnsavedMinAgeHours := EnsureRange(WelcomePageUnsavedMinAgeHours, cMinUnsavedHours, cMaxUnsavedHours);
  WelcomePageUnsavedWarnHours := EnsureRange(WelcomePageUnsavedWarnHours, cMinUnsavedHours, cMaxUnsavedHours);
  // Rot nie vor gelb.
  WelcomePageUnsavedAlertHours := EnsureRange(WelcomePageUnsavedAlertHours, WelcomePageUnsavedWarnHours,
    cMaxUnsavedHours);
  WelcomePageContinueCount := EnsureRange(WelcomePageContinueCount, cMinContinueCount, cMaxContinueCount);
  WelcomePageTrendsPoints := EnsureRange(WelcomePageTrendsPoints, cMinTrendPoints, cMaxTrendPoints);
  WelcomePageTrendsSeries := NormalizedTrendSeries(WelcomePageTrendsSeries);
  WelcomePageTestsMaxFailures := EnsureRange(WelcomePageTestsMaxFailures, cMinTestFailures, cMaxTestFailures);
  WelcomePageTestsCiIntervalMinutes := EnsureRange(WelcomePageTestsCiIntervalMinutes, cMinCiIntervalMinutes,
    cMaxCiIntervalMinutes);
  WelcomePageTestsCiProvider := NormalizedCiProvider(WelcomePageTestsCiProvider);
  WelcomePageQuickActionsItems := NormalizedQuickActionItems(WelcomePageQuickActionsItems);
  WelcomePageQuickActionsConsole := NormalizedQuickActionConsole(WelcomePageQuickActionsConsole);
  // Nur Webadressen: „Issue-Seite öffnen“ übergibt das Ziel dem Browser (#766).
  WelcomePageHelpReportUrl := Trim(WelcomePageHelpReportUrl);
  if not IsWebAddress(WelcomePageHelpReportUrl) then
  begin
    WelcomePageHelpReportUrl := cDefaultHelpReportUrl;
  end;
  WelcomePageHelpReportFolder := Trim(WelcomePageHelpReportFolder);
end;

procedure TAtlasPluginWelcomeTilesSettings.Exchange(const AIo: TAtlasSettingsExchange);
begin
  AIo.Flag('WelcomePageSearch', WelcomePageSearch);
  AIo.Flag('WelcomePageSearchSymbols', WelcomePageSearchSymbols);
  AIo.Flag('WelcomePageProjectStatus', WelcomePageProjectStatus);
  AIo.Number('WelcomePageMaxProjects', WelcomePageMaxProjects);
  AIo.Flag('WelcomePageRefreshVcs', WelcomePageRefreshVcs);
  AIo.Flag('WelcomePageUnsaved', WelcomePageUnsaved);
  AIo.Number('WelcomePageUnsavedMinAgeHours', WelcomePageUnsavedMinAgeHours);
  AIo.Number('WelcomePageUnsavedWarnHours', WelcomePageUnsavedWarnHours);
  AIo.Number('WelcomePageUnsavedAlertHours', WelcomePageUnsavedAlertHours);
  AIo.Flag('WelcomePageUnsavedHideWhenClean', WelcomePageUnsavedHideWhenClean);
  AIo.Flag('WelcomePageStatusTile', WelcomePageStatusTile);
  AIo.Flag('WelcomePageStatusTileOnlyProblems', WelcomePageStatusTileOnlyProblems);
  AIo.Flag('WelcomePageDiscover', WelcomePageDiscover);
  AIo.Flag('WelcomePageHelp', WelcomePageHelp);
  AIo.Text('WelcomePageHelpReportUrl', WelcomePageHelpReportUrl);
  AIo.Text('WelcomePageHelpReportFolder', WelcomePageHelpReportFolder);
  AIo.Flag('WelcomePageProjectSetup', WelcomePageProjectSetup);
  AIo.Flag('WelcomePageNewFromTemplate', WelcomePageNewFromTemplate);
  AIo.Flag('WelcomePageContinue', WelcomePageContinue);
  AIo.Number('WelcomePageContinueCount', WelcomePageContinueCount);
  AIo.Flag('WelcomePageContinueIncoming', WelcomePageContinueIncoming);
  AIo.Flag('WelcomePageContinueFetch', WelcomePageContinueFetch);
  AIo.Flag('WelcomePageSaved', WelcomePageSaved);
  AIo.Flag('WelcomePageTrends', WelcomePageTrends);
  AIo.Number('WelcomePageTrendsPoints', WelcomePageTrendsPoints);
  AIo.Text('WelcomePageTrendsSeries', WelcomePageTrendsSeries);
  AIo.Flag('WelcomePageTests', WelcomePageTests);
  AIo.Number('WelcomePageTestsMaxFailures', WelcomePageTestsMaxFailures);
  AIo.Flag('WelcomePageTestsCi', WelcomePageTestsCi);
  AIo.Text('WelcomePageTestsCiProvider', WelcomePageTestsCiProvider);
  AIo.Number('WelcomePageTestsCiIntervalMinutes', WelcomePageTestsCiIntervalMinutes);
  AIo.Flag('WelcomePageTestsCiNotify', WelcomePageTestsCiNotify);
  AIo.Flag('WelcomePageQuickActions', WelcomePageQuickActions);
  AIo.Text('WelcomePageQuickActionsItems', WelcomePageQuickActionsItems);
  AIo.Text('WelcomePageQuickActionsConsole', WelcomePageQuickActionsConsole);
  AIo.Flag('CiLogin', CiLogin);
  AIo.Flag('WelcomePageIssues', WelcomePageIssues);
  AIo.Flag('WelcomePageSprint', WelcomePageSprint);
end;

end.
