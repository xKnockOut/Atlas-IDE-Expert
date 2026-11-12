unit Atlas.Core.Settings.Plugin.Issues;

// Einstellungen des IDE-Plugins, Bereich Issue-Tracker (issues.*) (#227):
// Felder, Vorgaben, Grenzen, Lesen und Schreiben. TAtlasPluginSettings (Atlas.Core.Settings.Plugin)
// fasst die Bereiche zusammen und reicht die Felder als Eigenschaften durch.

interface

uses
  Atlas.Core.Settings.Plugin.Store;

const
  /// <summary>Grenzen und Vorgabe von issues.attach.maxImageWidth (#1276), wie TAtlasAttachImage.</summary>
  cMinAttachImageWidth = 320;
  cMaxAttachImageWidth = 7680;
  cDefaultAttachImageWidth = 1920;
  /// <summary>Werte von issues.start (#765); wie TAtlasMyIssues.StartName.</summary>
  cIssuesStartBranch = 'branch';
  cIssuesStartRemember = 'remember';
  /// <summary>Vorgabe für issues.commitPattern (#765); wie TAtlasTrackerNaming.cCommitPattern.
  /// </summary>
  cDefaultIssuesCommitPattern = '{kennung} ';
  /// <summary>Grenzen und Vorgabe von issues.blameLinks.maxRevisions (#1275).</summary>
  cMinIssuesBlameMaxRevisions = 1;
  cMaxIssuesBlameMaxRevisions = 5000;
  cDefaultIssuesBlameMaxRevisions = 200;
  /// <summary>Zeilen je Gruppe in „Alle Tracker-Projekte“ (#1928, issues.allProjects.perGroup).</summary>
  cMinIssuesAllProjectsPerGroup = 1;
  cMaxIssuesAllProjectsPerGroup = 20;
  cDefaultIssuesAllProjectsPerGroup = 5;
  /// <summary>Vorgaben für Zustand und Kommentar (#1266); wie TAtlasTrackerWorkflow.</summary>
  cDefaultIssuesStateField = 'State';
  cDefaultIssuesAssigneeField = 'Assignee';
  cDefaultIssuesEndComment = 'Erledigt in {branch}.\n{commits}';
  /// <summary>Vorgabe der Kommentarvorlage beim Prüfen (#2126); wie TAtlasTrackerReview.</summary>
  cDefaultIssuesReviewComment = 'Geprüft: {build}, {tests}.'; // german-ok: Vorgabe der Einstellung
  /// <summary>Vorgabe von issues.commentSnippets (#1278), wie TAtlasCommentSnippets.Defaults.</summary>
  cDefaultIssuesCommentSnippets = '[{"name":"Bitte mit aktuellem Build prüfen","text":"Bitte mit dem aktuellen Build ' +
    'prüfen."},{"name":"Behoben in {commit}","text":"Behoben in {commit}."}]';
  /// <summary>Höchstlänge der Kommentarvorlagen und der Liste der Zielzustände (#1266).</summary>
  cMaxIssuesTemplate = 2000;
  /// <summary>Grenzen und Vorgaben der Zeiterfassung (#1267, issues.idleMinutes, issues.timeRounding); wie
  /// TAtlasTimeClock bzw. TAtlasTimeRounding.</summary>
  cMinIssuesIdleMinutes = 1;
  cMaxIssuesIdleMinutes = 120;
  cDefaultIssuesIdleMinutes = 10;
  cMinIssuesTimeRounding = 1;
  cMaxIssuesTimeRounding = 60;
  cDefaultIssuesTimeRounding = 5;
  /// <summary>Grenzen und Vorgabe von issues.notify.intervalMinutes (#1271); wie TAtlasTrackerNotify.cMinInterval
  /// und DefaultInterval (Test prüft Gleichheit).</summary>
  cMinIssuesNotifyMinutes = 2;
  cMaxIssuesNotifyMinutes = 1440;
  cDefaultIssuesNotifyMinutes = 10;
  /// <summary>Grenzen und Vorgaben der Ablauf-Karte (#2125, issues.flowMap.days, issues.flowMap.stuckDays).
  /// </summary>
  cMinIssuesFlowMapDays = 7;
  cMaxIssuesFlowMapDays = 365;
  cDefaultIssuesFlowMapDays = 90;
  cMinIssuesFlowMapStuckDays = 1;
  cMaxIssuesFlowMapStuckDays = 90;
  cDefaultIssuesFlowMapStuckDays = 5;
  /// <summary>Werte von issues.notify.scope (#1271); wie TAtlasTrackerNotify.ScopeName.</summary>
  cIssuesNotifyAssigned = 'assigned';
  cIssuesNotifyAssignedOrCreated = 'assignedOrCreated';
  cIssuesNotifyWatched = 'watched';
  /// <summary>Werte von issues.sprintOnStart (#2128): fragen, ohne Frage aufnehmen, nie.</summary>
  cIssuesSprintAsk = 'ask';
  cIssuesSprintAlways = 'always';
  cIssuesSprintNever = 'never';

type
  /// <summary>Plugin-Einstellungen: Verbindungen, Abfragen und Arbeitsablauf des Issue-Trackers.</summary>
  TAtlasPluginIssuesSettings = record
    /// <summary>Modul-Schalter issues.enabled (#1454): Issue-Tracker und Build-Server; aus = die wirksamen Werte aller
    /// Einstellungen des Moduls sind
    /// „aus“ (TAtlasModuleSwitches), gespeichert bleiben sie.</summary>
    IssuesEnabled: Boolean;
    /// <summary>Tracker (#765, issues.tracker): '' = aus der .atlas, "github" oder "youtrack".</summary>
    IssuesTracker: string;
    /// <summary>„Beginnen“ (#765, issues.start): "branch" legt einen Branch an und checkt ihn aus,
    /// "remember" merkt nur das Issue.</summary>
    IssuesStart: string;
    /// <summary>Muster für den Branch (#765, issues.branchPattern) mit {kennung}, {nummer},
    /// {kurztitel}; '' = Git feature/{kennung}-{kurztitel}, SVN {kennung}-{kurztitel} unter ^/branches/.</summary>
    IssuesBranchPattern: string;
    /// <summary>Basis des Branchs (#765, issues.branchBase); '' = Git main (sonst master), SVN trunk.
    /// </summary>
    IssuesBranchBase: string;
    /// <summary>Anfang der Commit-Nachricht, solange ein Issue aktiv ist (#765, issues.commitPattern);
    /// '' = aus. Nicht gekürzt: das Leerzeichen der Vorgabe "{kennung} " bleibt.</summary>
    IssuesCommitPattern: string;
    /// <summary>Befehl „Zugang zum Issue-Tracker hinterlegen …“ (#765, issues.login, Atlas.TrackerLogin) in der
    /// Befehlspalette und im Kontextmenü des Bereichs; aus = der Befehl und sein Tipp verschwinden.</summary>
    TrackerLogin: Boolean;
    /// <summary>Persönliche Tracker-Verbindungen (#1260, issues.connections) als JSON-Liste mit name, provider und
    /// url; liegt in settings.json (TAtlasRoutedSettingsStore), gelesen mit TAtlasTrackerConnections. '[]' = keine.
    /// Nie ein Token.</summary>
    IssuesConnections: string;
    /// <summary>Persönliche Zuordnung Delphi-Projekt → Tracker-Projekt (#1261, issues.projects) als JSON-Liste mit
    /// match, connection und project; liegt in settings.json, gelesen mit TAtlasTrackerProjects. '[]' = keine.
    /// </summary>
    IssuesProjects: string;
    /// <summary>Benannte Abfragen für „Meine Issues“ (#1262, issues.queries) als JSON-Liste mit name, query und
    /// optional connection und project; liegt in settings.json, gelesen mit TAtlasTrackerQueries. '[]' = keine,
    /// dann gilt je Anbieter „Mir zugewiesen“. Ersetzt issues.query (wird einmal zur Abfrage „Standard“).
    /// </summary>
    IssuesQueries: string;
    /// <summary>Klappliste der Abfragen im Bereich „Meine Issues“ (#1262, issues.queryPicker); aus = keine
    /// Klappliste, es gilt die erste passende Abfrage.</summary>
    IssuesQueryPicker: Boolean;
    /// <summary>Klappliste „Tracker-Projekt“ im Bereich „Meine Issues“ (#1927, issues.projectPicker); aus = keine
    /// Klappliste, das Tracker-Projekt folgt dem Delphi-Projekt wie vorher.</summary>
    IssuesProjectPicker: Boolean;
    /// <summary>In „Meine Issues“ gewähltes Tracker-Projekt (#1927, issues.welcomeProject): '' = automatisch nach
    /// dem Delphi-Projekt, „projekt@verbindung“ = fest, "*" = alle (#1928).</summary>
    IssuesWelcomeProject: string;
    /// <summary>Eintrag „Alle Tracker-Projekte“ in der Klappliste (#1928, issues.allProjects).</summary>
    IssuesAllProjects: Boolean;
    /// <summary>Zeilen je Gruppe in „Alle Tracker-Projekte“ (#1928, issues.allProjects.perGroup, 1–20).</summary>
    IssuesAllProjectsPerGroup: Integer;
    /// <summary>Knopf „Vorschlagen …“ bei den Arbeitskopien eines Tracker-Projekts (#1929, issues.suggestPaths).
    /// </summary>
    IssuesSuggestPaths: Boolean;
    /// <summary>Tracker beim Beginnen und Beenden nachführen (#1266, issues.syncState): Zustand, Zuweisung und
    /// Kommentar beim Beginnen, Dialog „… beenden“ mit Zielzustand und Kommentar, Kommentarfeld in der Vorschau;
    /// aus = „Beginnen“ und „Beenden“ ändern im Tracker nichts.</summary>
    IssuesSyncState: Boolean;
    /// <summary>Name des Zustandsfeldes im YouTrack-Projekt (#1266, issues.stateField); '' = "State".</summary>
    IssuesStateField: string;
    /// <summary>Name des Benutzerfeldes für die Zuständigkeit (#1266, issues.assigneeField); '' = "Assignee".
    /// </summary>
    IssuesAssigneeField: string;
    /// <summary>Zustand beim Beginnen (#1266, issues.startState); '' = nicht ändern. GitHub: Label.</summary>
    IssuesStartState: string;
    /// <summary>Beim Beginnen mir zuweisen (#1266, issues.assignOnStart).</summary>
    IssuesAssignOnStart: Boolean;
    /// <summary>Kommentarvorlage beim Beginnen (#1266, issues.startComment); '' = kein Kommentar.</summary>
    IssuesStartComment: string;
    /// <summary>Zielzustände im Beenden-Dialog (#1266, issues.endStates), mit Komma getrennt; '' = nur „Zustand
    /// nicht ändern“.</summary>
    IssuesEndStates: string;
    /// <summary>Kommentarvorlage beim Beenden (#1266, issues.endComment) mit {branch}, {commits}, {pr}, {time};
    /// "\n" = neue Zeile.</summary>
    IssuesEndComment: string;
    /// <summary>Felder im Beenden-Dialog (#2123, issues.endFields), mit Komma getrennt; '' = keine.</summary>
    IssuesEndFields: string;
    /// <summary>Erfasste Zeit im Beenden-Dialog buchen (#2123, issues.endTime) statt im Zeitdialog danach.
    /// </summary>
    IssuesEndTime: Boolean;
    /// <summary>Prüfzustände (#2126, #2127, issues.reviewStates), mit Komma getrennt: Ein Issue darin wartet auf
    /// die Prüfung; zurück in einen offenen Zustand gilt es als wieder offen. '' = keine.</summary>
    IssuesReviewStates: string;
    /// <summary>Kommentarvorlage beim Prüfen (#2126, issues.reviewComment) mit {build}, {tests}, {branch} und
    /// {kennung}; "\n" = neue Zeile.</summary>
    IssuesReviewComment: string;
    /// <summary>Vorgaben.</summary>
    class function Defaults: TAtlasPluginIssuesSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TAtlasSettingsExchange);
  end;

  /// <summary>Plugin-Einstellungen: Vorschau, Board, Benachrichtigung, Anhänge und Zeiterfassung von Issues.</summary>
  TAtlasPluginIssueWorkSettings = record
    /// <summary>Issue-Vorschau (#1264, issues.preview): Klick auf ein Issue öffnet das Fenster „Atlas-Issue“ statt
    /// des Browsers, dazu der Befehl „Issue anzeigen …“; aus = Browser wie bisher.</summary>
    IssuesPreview: Boolean;
    /// <summary>Kommentare in der Vorschau laden und zeigen (#1264, issues.preview.comments); aus = nicht abgefragt.
    /// </summary>
    IssuesPreviewComments: Boolean;
    /// <summary>Issue-Kennungen im Code (#1265, issues.codeLinks): Kennungen wie ATL-123 oder #42 in Kommentaren
    /// unterstreichen, Hover mit Kurzvorschau, Strg+Klick und Kontextmenü; aus = keine Erkennung, keine Abfrage.
    /// </summary>
    IssuesCodeLinks: Boolean;
    /// <summary>Issues in der Zeilenhistorie (#1275, issues.blameLinks): Kennungen aus der Commit-Nachricht am
    /// Rand, Hover mit Titel und Zustand, Strg+Klick und Befehl „Issues zu dieser Methode“; aus = Zeilenhistorie
    /// wie bisher, kein Befehl.</summary>
    IssuesBlameLinks: Boolean;
    /// <summary>Höchstzahl durchsuchter Revisionen für „Issues zu dieser Methode“ (#1275,
    /// issues.blameLinks.maxRevisions).</summary>
    IssuesBlameMaxRevisions: Integer;
    /// <summary>„Issue anlegen …“ im Editor und bei Befunden (#1268, issues.create).</summary>
    IssuesCreate: Boolean;
    /// <summary>Codeausschnitt in der Beschreibung vorschlagen (#1268, issues.create.includeCode).</summary>
    IssuesCreateIncludeCode: Boolean;
    /// <summary>Zeit für das aktuelle Issue erfassen und Buchen anbieten (#1267, issues.timeTracking); aus = weder
    /// Anzeige noch Datei noch Dialog.</summary>
    IssuesTimeTracking: Boolean;
    /// <summary>Minuten ohne Eingabe, nach denen die Uhr anhält (#1267, issues.idleMinutes, 1–120).</summary>
    IssuesIdleMinutes: Integer;
    /// <summary>Rundung der vorgeschlagenen Dauer in Minuten (#1267, issues.timeRounding, 1–60).</summary>
    IssuesTimeRounding: Integer;
    /// <summary>Checklisten in der Vorschau als Häkchen, Abhaken schreibt die Beschreibung zurück (#1273,
    /// issues.preview.checklists); aus = Liste als Text, nichts wird geschrieben.</summary>
    IssuesPreviewChecklists: Boolean;
    /// <summary>Fortschritt der Checkliste des aktuellen Issues im Statusfeld (#1273, issues.checklistStatus); aus =
    /// keine Zeile.</summary>
    IssuesChecklistStatus: Boolean;
    /// <summary>Zustand des aktuellen Issues im Statusfeld mit Menü der erlaubten Übergänge und Einträgen in der
    /// Befehlspalette (#2124, issues.statusState); aus = nur die Zeit.</summary>
    IssuesStatusState: Boolean;
    /// <summary>Beim Beginnen in den laufenden Sprint des Boards aufnehmen (#2128, issues.sprintOnStart):
    /// IssuesSprintAsk (Vorgabe), IssuesSprintAlways oder IssuesSprintNever.</summary>
    IssuesSprintOnStart: string;
    /// <summary>Verknüpfungen der Vorschau als Baum (#1279, issues.preview.links): hängt ab von, blockiert,
    /// Unteraufgaben mit Fortschritt, eingeklappt Duplikate und „bezieht sich auf“; dazu „Unteraufgabe anlegen …“
    /// und „Verknüpfen …“. Aus = flache Liste wie in #1264.</summary>
    IssuesPreviewLinks: Boolean;
    /// <summary>Warnung beim Beginnen (#1279, issues.warnBlocked), wenn ein „hängt ab von“-Issue noch offen ist.
    /// </summary>
    IssuesWarnBlocked: Boolean;
    /// <summary>Dockfenster „Atlas-Board“ mit Spalten und Karten (#1272, issues.board): Menü Ansicht › Atlas ›
    /// Board und Befehl Atlas.Board; aus = kein Menüeintrag, kein Befehl, keine Abfrage.</summary>
    IssuesBoard: Boolean;
    /// <summary>Beim Ziehen einer Karte nachfragen (#1272, issues.board.confirmMove); aus = sofort verschieben.
    /// „Nicht mehr fragen“ im Dialog schaltet es ab.</summary>
    IssuesBoardConfirmMove: Boolean;
    /// <summary>Board öffnet mit dem Filter „Nur meine“ (#1272, issues.board.onlyMine); aus = alle Karten.</summary>
    IssuesBoardOnlyMine: Boolean;
    /// <summary>Issue-Fenster und Board in den Farben des IDE-Themas (#2131, issues.ideColors); aus = feste
    /// Atlas-Palette.</summary>
    IssuesIdeColors: Boolean;
    /// <summary>Dockfenster „Atlas-Ablauf“ (#2125, issues.flowMap): Ablauf-Karte aus der Historie von YouTrack,
    /// Menü Ansicht › Atlas › Ablauf und Befehl Atlas.FlowMap; aus = kein Menüeintrag, kein Befehl, kein Abruf.
    /// </summary>
    IssuesFlowMap: Boolean;
    /// <summary>Zeitraum der Ablauf-Karte in Tagen (#2125, issues.flowMap.days), cMinIssuesFlowMapDays bis
    /// cMaxIssuesFlowMapDays.</summary>
    IssuesFlowMapDays: Integer;
    /// <summary>Ab so vielen Tagen im selben Zustand „liegt lange“ (#2125, issues.flowMap.stuckDays).</summary>
    IssuesFlowMapStuckDays: Integer;
    /// <summary>Burndown-Linie in der Sprint-Kachel (#1277, issues.sprint.burndown); aus = nur Kopf und Zahlen.
    /// </summary>
    IssuesSprintBurndown: Boolean;
    /// <summary>Vergleich mit dem vorherigen Sprint und Velocity der letzten drei (#1277, issues.sprint.compare);
    /// aus = kein früherer Sprint wird gefragt.</summary>
    IssuesSprintCompare: Boolean;
    /// <summary>Issues in der Befehlspalette suchen (#1270, issues.paletteSearch): „#“ bzw. Projektkürzel mit „-“
    /// sucht im Tracker; aus = nur Befehle, ohne Netzzugriff.</summary>
    IssuesPaletteSearch: Boolean;
    /// <summary>Kommentar-Editor (#1278, issues.commentEditor): Vorschläge für @ und #, Textbausteine, Vorschau und
    /// Entwürfe; aus = einfaches Textfeld, Strg+Enter sendet.</summary>
    IssuesCommentEditor: Boolean;
    /// <summary>Textbausteine für Kommentare (#1278, issues.commentSnippets) als JSON-Liste [{"name",
    /// "text"}].</summary>
    IssuesCommentSnippets: string;
    /// <summary>Reiter „Entwicklung“ in der Vorschau (#1269, issues.preview.development): Branches, Commits, Pull
    /// Requests und geänderte Units zum Issue; aus = Reiter fehlt, kein Log wird abgefragt.</summary>
    IssuesPreviewDevelopment: Boolean;
    /// <summary>Änderungen an meinen Issues melden (#1271, issues.notify): Atlas fragt jede Tracker-Verbindung alle
    /// IssuesNotifyIntervalMinutes und meldet neue Kommentare, Zuweisungen und Zustandswechsel in der
    /// Benachrichtigungszentrale; aus (Vorgabe) = keine Abfrage.</summary>
    IssuesNotify: Boolean;
    /// <summary>Abstand der Abfrage in Minuten (#1271, issues.notify.intervalMinutes), MinIssuesNotifyMinutes bis
    /// MaxIssuesNotifyMinutes.</summary>
    IssuesNotifyIntervalMinutes: Integer;
    /// <summary>Beobachtete Issues (#1271, issues.notify.scope): IssuesNotifyAssigned, IssuesNotifyAssignedOrCreated
    /// (Vorgabe) oder IssuesNotifyWatched.</summary>
    IssuesNotifyScope: string;
    /// <summary>Wieder geöffnete Issues hervorheben (#2127, issues.reopened): Marke „wieder offen“ in „Meine
    /// Issues“ mit dem neuesten Kommentar und „Weiterarbeiten“ auf dem alten Branch, Grund in der Meldung; aus =
    /// wie bisher.</summary>
    IssuesReopened: Boolean;
    /// <summary>Beim Prüfen bauen und die betroffenen Tests laufen lassen (#2126, issues.reviewBuild); aus = nur
    /// Branch wechseln und entscheiden.</summary>
    IssuesReviewBuild: Boolean;
    /// <summary>„An Issue anhängen …“ (#1276, issues.attach): Bildschirmfoto, Formular, Log, Debug-Notiz und
    /// Exception-Verlauf an ein Issue hängen; aus = der Befehl fehlt überall.</summary>
    IssuesAttach: Boolean;
    /// <summary>Vorgeschlagene Logdateien (#1276, issues.attach.logFiles), getrennt durch „;“, mit $(ProjectDir)
    /// und * (TAtlasAttachLog.Candidates); '' = keine.</summary>
    IssuesAttachLogFiles: string;
    /// <summary>Bilder höchstens so breit (#1276, issues.attach.maxImageWidth, MinAttachImageWidth bis
    /// MaxAttachImageWidth).</summary>
    IssuesAttachMaxImageWidth: Integer;
    /// <summary>„Per Klick wählen“ holt das debuggte Programm nach vorn (issues.attach.raiseProgram).</summary>
    IssuesAttachRaiseProgram: Boolean;
    /// <summary>Vorgaben.</summary>
    class function Defaults: TAtlasPluginIssueWorkSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TAtlasSettingsExchange);
  end;

implementation

uses
  System.Math,
  System.SysUtils;

/// <summary>"github", "youtrack" oder '' (aus der .atlas).</summary>
function NormalizedIssuesTracker(const AText: string): string;
begin
  Result := LowerCase(Trim(AText));
  if (Result <> 'github') and (Result <> 'youtrack') then
  begin
    Result := '';
  end;
end;

/// <summary>issues.sprintOnStart (#2128): bekannter Wert, sonst IssuesSprintAsk.</summary>
function NormalizedIssuesSprintOnStart(const AText: string): string;
begin
  Result := cIssuesSprintAsk;
  if SameText(Trim(AText), cIssuesSprintAlways) then
  begin
    Result := cIssuesSprintAlways;
  end
  else if SameText(Trim(AText), cIssuesSprintNever) then
  begin
    Result := cIssuesSprintNever;
  end;
end;

/// <summary>issues.notify.scope (#1271): bekannter Wert, sonst IssuesNotifyAssignedOrCreated.</summary>
function NormalizedIssuesNotifyScope(const AText: string): string;
begin
  if SameText(Trim(AText), cIssuesNotifyAssigned) then
  begin
    Result := cIssuesNotifyAssigned;
  end
  else if SameText(Trim(AText), cIssuesNotifyWatched) then
  begin
    Result := cIssuesNotifyWatched;
  end
  else
  begin
    Result := cIssuesNotifyAssignedOrCreated;
  end;
end;

/// <summary>issues.start (#765): bekannter Wert, sonst IssuesStartBranch.</summary>
function NormalizedIssuesStart(const AText: string): string;
begin
  if SameText(Trim(AText), cIssuesStartRemember) then
  begin
    Result := cIssuesStartRemember;
  end
  else
  begin
    Result := cIssuesStartBranch;
  end;
end;

/// <summary>Kommentarvorlage bzw. Liste (#1266): einzeilig (Zeilenumbruch als "\n"), außen ohne Leerraum,
/// höchstens MaxIssuesTemplate Zeichen.</summary>
function NormalizedIssuesTemplate(const AText: string): string;
var
  mIndex: Integer;
begin
  Result := StringReplace(StringReplace(AText, #13#10, '\n', [rfReplaceAll]), #10, '\n', [rfReplaceAll]);
  for mIndex := 1 to Length(Result) do
  begin
    if Ord(Result[mIndex]) < 32 then
    begin
      Result[mIndex] := ' ';
    end;
  end;
  Result := Trim(Result);
  if Length(Result) > cMaxIssuesTemplate then
  begin
    Result := Copy(Result, 1, cMaxIssuesTemplate);
  end;
end;

{ TAtlasPluginIssuesSettings }

class function TAtlasPluginIssuesSettings.Defaults: TAtlasPluginIssuesSettings;
begin
  Result.IssuesEnabled := True;
  Result.IssuesTracker := '';
  Result.IssuesStart := cIssuesStartBranch;
  Result.IssuesBranchPattern := '';
  Result.IssuesBranchBase := '';
  Result.IssuesCommitPattern := cDefaultIssuesCommitPattern;
  Result.TrackerLogin := True;
  Result.IssuesConnections := '[]';
  Result.IssuesProjects := '[]';
  Result.IssuesQueries := '[]';
  Result.IssuesQueryPicker := True;
  Result.IssuesProjectPicker := True;
  Result.IssuesWelcomeProject := '';
  Result.IssuesAllProjects := True;
  Result.IssuesAllProjectsPerGroup := cDefaultIssuesAllProjectsPerGroup;
  Result.IssuesSuggestPaths := True;
  Result.IssuesSyncState := True;
  Result.IssuesStateField := cDefaultIssuesStateField;
  Result.IssuesAssigneeField := cDefaultIssuesAssigneeField;
  Result.IssuesStartState := '';
  Result.IssuesAssignOnStart := False;
  Result.IssuesStartComment := '';
  Result.IssuesEndStates := '';
  Result.IssuesReviewStates := '';
  Result.IssuesEndComment := cDefaultIssuesEndComment;
  Result.IssuesReviewComment := cDefaultIssuesReviewComment;
  Result.IssuesEndFields := '';
  Result.IssuesEndTime := True;
end;

procedure TAtlasPluginIssuesSettings.Normalize;
begin
  IssuesTracker := NormalizedIssuesTracker(IssuesTracker);
  IssuesStart := NormalizedIssuesStart(IssuesStart);
  IssuesBranchPattern := NormalizedIssuesText(IssuesBranchPattern, True);
  IssuesBranchBase := NormalizedIssuesText(IssuesBranchBase, True);
  // Leerraum am Ende gehört zum Muster ("{kennung} ").
  IssuesCommitPattern := NormalizedIssuesText(IssuesCommitPattern, False);
  IssuesConnections := Trim(IssuesConnections);
  if IssuesConnections = '' then
  begin
    IssuesConnections := '[]';
  end;
  IssuesProjects := Trim(IssuesProjects);
  if IssuesProjects = '' then
  begin
    IssuesProjects := '[]';
  end;
  IssuesQueries := Trim(IssuesQueries);
  if IssuesQueries = '' then
  begin
    IssuesQueries := '[]';
  end;
  IssuesWelcomeProject := Trim(IssuesWelcomeProject);
  IssuesAllProjectsPerGroup := EnsureRange(IssuesAllProjectsPerGroup, cMinIssuesAllProjectsPerGroup,
    cMaxIssuesAllProjectsPerGroup);
  IssuesStateField := NormalizedIssuesText(IssuesStateField, True);
  if IssuesStateField = '' then
  begin
    IssuesStateField := cDefaultIssuesStateField;
  end;
  IssuesAssigneeField := NormalizedIssuesText(IssuesAssigneeField, True);
  if IssuesAssigneeField = '' then
  begin
    IssuesAssigneeField := cDefaultIssuesAssigneeField;
  end;
  IssuesStartState := NormalizedIssuesText(IssuesStartState, True);
  IssuesStartComment := NormalizedIssuesTemplate(IssuesStartComment);
  IssuesEndStates := NormalizedIssuesTemplate(IssuesEndStates);
  IssuesReviewStates := NormalizedIssuesTemplate(IssuesReviewStates);
  IssuesEndComment := NormalizedIssuesTemplate(IssuesEndComment);
  IssuesReviewComment := NormalizedIssuesTemplate(IssuesReviewComment);
  IssuesEndFields := NormalizedIssuesTemplate(IssuesEndFields);
end;

procedure TAtlasPluginIssuesSettings.Exchange(const AIo: TAtlasSettingsExchange);
begin
  AIo.Flag('IssuesEnabled', IssuesEnabled);
  AIo.Text('IssuesTracker', IssuesTracker);
  AIo.Text('IssuesStart', IssuesStart);
  AIo.Text('IssuesBranchPattern', IssuesBranchPattern);
  AIo.Text('IssuesBranchBase', IssuesBranchBase);
  AIo.Text('IssuesCommitPattern', IssuesCommitPattern);
  AIo.Flag('TrackerLogin', TrackerLogin);
  AIo.Text('IssuesConnections', IssuesConnections);
  AIo.Text('IssuesProjects', IssuesProjects);
  AIo.Text('IssuesQueries', IssuesQueries);
  AIo.Flag('IssuesQueryPicker', IssuesQueryPicker);
  AIo.Flag('IssuesProjectPicker', IssuesProjectPicker);
  AIo.Text('IssuesWelcomeProject', IssuesWelcomeProject);
  AIo.Flag('IssuesAllProjects', IssuesAllProjects);
  AIo.Number('IssuesAllProjectsPerGroup', IssuesAllProjectsPerGroup);
  AIo.Flag('IssuesSuggestPaths', IssuesSuggestPaths);
  AIo.Flag('IssuesSyncState', IssuesSyncState);
  AIo.Text('IssuesStateField', IssuesStateField);
  AIo.Text('IssuesAssigneeField', IssuesAssigneeField);
  AIo.Text('IssuesStartState', IssuesStartState);
  AIo.Flag('IssuesAssignOnStart', IssuesAssignOnStart);
  AIo.Text('IssuesStartComment', IssuesStartComment);
  AIo.Text('IssuesEndStates', IssuesEndStates);
  AIo.Text('IssuesEndComment', IssuesEndComment);
  AIo.Text('IssuesEndFields', IssuesEndFields);
  AIo.Flag('IssuesEndTime', IssuesEndTime);
  AIo.Text('IssuesReviewStates', IssuesReviewStates);
  AIo.Text('IssuesReviewComment', IssuesReviewComment);
end;

{ TAtlasPluginIssueWorkSettings }

class function TAtlasPluginIssueWorkSettings.Defaults: TAtlasPluginIssueWorkSettings;
begin
  Result.IssuesPreview := True;
  Result.IssuesPreviewComments := True;
  Result.IssuesCodeLinks := True;
  Result.IssuesBlameLinks := True;
  Result.IssuesBlameMaxRevisions := cDefaultIssuesBlameMaxRevisions;
  Result.IssuesCreate := True;
  Result.IssuesCreateIncludeCode := True;
  Result.IssuesTimeTracking := False;
  Result.IssuesIdleMinutes := cDefaultIssuesIdleMinutes;
  Result.IssuesTimeRounding := cDefaultIssuesTimeRounding;
  Result.IssuesPreviewChecklists := True;
  Result.IssuesChecklistStatus := True;
  Result.IssuesStatusState := True;
  Result.IssuesSprintOnStart := cIssuesSprintAsk;
  Result.IssuesPreviewLinks := True;
  Result.IssuesWarnBlocked := True;
  Result.IssuesBoard := True;
  Result.IssuesBoardConfirmMove := True;
  Result.IssuesBoardOnlyMine := True;
  Result.IssuesIdeColors := True;
  Result.IssuesFlowMap := False;
  Result.IssuesFlowMapDays := cDefaultIssuesFlowMapDays;
  Result.IssuesFlowMapStuckDays := cDefaultIssuesFlowMapStuckDays;
  Result.IssuesSprintBurndown := True;
  Result.IssuesSprintCompare := True;
  Result.IssuesPaletteSearch := True;
  Result.IssuesCommentEditor := True;
  Result.IssuesCommentSnippets := cDefaultIssuesCommentSnippets;
  Result.IssuesPreviewDevelopment := True;
  Result.IssuesNotify := False;
  Result.IssuesNotifyIntervalMinutes := cDefaultIssuesNotifyMinutes;
  Result.IssuesNotifyScope := cIssuesNotifyAssignedOrCreated;
  Result.IssuesReopened := True;
  Result.IssuesReviewBuild := True;
  Result.IssuesAttach := True;
  Result.IssuesAttachLogFiles := '';
  Result.IssuesAttachMaxImageWidth := cDefaultAttachImageWidth;
  Result.IssuesAttachRaiseProgram := True;
end;

procedure TAtlasPluginIssueWorkSettings.Normalize;
begin
  IssuesAttachLogFiles := Trim(IssuesAttachLogFiles);
  IssuesAttachMaxImageWidth := EnsureRange(IssuesAttachMaxImageWidth, cMinAttachImageWidth, cMaxAttachImageWidth);
  IssuesBlameMaxRevisions := EnsureRange(IssuesBlameMaxRevisions, cMinIssuesBlameMaxRevisions,
    cMaxIssuesBlameMaxRevisions);
  IssuesIdleMinutes := EnsureRange(IssuesIdleMinutes, cMinIssuesIdleMinutes, cMaxIssuesIdleMinutes);
  IssuesTimeRounding := EnsureRange(IssuesTimeRounding, cMinIssuesTimeRounding, cMaxIssuesTimeRounding);
  // Leer heißt: keine Textbausteine (die Vorgaben kommen nur, wenn der Wert fehlt).
  IssuesCommentSnippets := Trim(IssuesCommentSnippets);
  if IssuesCommentSnippets = '' then
  begin
    IssuesCommentSnippets := '[]';
  end;
  IssuesNotifyIntervalMinutes := EnsureRange(IssuesNotifyIntervalMinutes, cMinIssuesNotifyMinutes,
    cMaxIssuesNotifyMinutes);
  IssuesNotifyScope := NormalizedIssuesNotifyScope(IssuesNotifyScope);
  IssuesSprintOnStart := NormalizedIssuesSprintOnStart(IssuesSprintOnStart);
  IssuesFlowMapDays := EnsureRange(IssuesFlowMapDays, cMinIssuesFlowMapDays, cMaxIssuesFlowMapDays);
  IssuesFlowMapStuckDays := EnsureRange(IssuesFlowMapStuckDays, cMinIssuesFlowMapStuckDays,
    cMaxIssuesFlowMapStuckDays);
end;

procedure TAtlasPluginIssueWorkSettings.Exchange(const AIo: TAtlasSettingsExchange);
begin
  AIo.Flag('IssuesPreview', IssuesPreview);
  AIo.Flag('IssuesPreviewComments', IssuesPreviewComments);
  AIo.Flag('IssuesCodeLinks', IssuesCodeLinks);
  AIo.Flag('IssuesBlameLinks', IssuesBlameLinks);
  AIo.Number('IssuesBlameMaxRevisions', IssuesBlameMaxRevisions);
  AIo.Flag('IssuesCreate', IssuesCreate);
  AIo.Flag('IssuesCreateIncludeCode', IssuesCreateIncludeCode);
  AIo.Flag('IssuesTimeTracking', IssuesTimeTracking);
  AIo.Number('IssuesIdleMinutes', IssuesIdleMinutes);
  AIo.Number('IssuesTimeRounding', IssuesTimeRounding);
  AIo.Flag('IssuesPreviewChecklists', IssuesPreviewChecklists);
  AIo.Flag('IssuesChecklistStatus', IssuesChecklistStatus);
  AIo.Flag('IssuesStatusState', IssuesStatusState);
  AIo.Text('IssuesSprintOnStart', IssuesSprintOnStart);
  AIo.Flag('IssuesPreviewLinks', IssuesPreviewLinks);
  AIo.Flag('IssuesWarnBlocked', IssuesWarnBlocked);
  AIo.Flag('IssuesBoard', IssuesBoard);
  AIo.Flag('IssuesBoardConfirmMove', IssuesBoardConfirmMove);
  AIo.Flag('IssuesBoardOnlyMine', IssuesBoardOnlyMine);
  AIo.Flag('IssuesIdeColors', IssuesIdeColors);
  AIo.Flag('IssuesFlowMap', IssuesFlowMap);
  AIo.Number('IssuesFlowMapDays', IssuesFlowMapDays);
  AIo.Number('IssuesFlowMapStuckDays', IssuesFlowMapStuckDays);
  AIo.Flag('IssuesSprintBurndown', IssuesSprintBurndown);
  AIo.Flag('IssuesSprintCompare', IssuesSprintCompare);
  AIo.Flag('IssuesPaletteSearch', IssuesPaletteSearch);
  AIo.Flag('IssuesCommentEditor', IssuesCommentEditor);
  AIo.Text('IssuesCommentSnippets', IssuesCommentSnippets);
  AIo.Flag('IssuesPreviewDevelopment', IssuesPreviewDevelopment);
  AIo.Flag('IssuesNotify', IssuesNotify);
  AIo.Number('IssuesNotifyIntervalMinutes', IssuesNotifyIntervalMinutes);
  AIo.Text('IssuesNotifyScope', IssuesNotifyScope);
  AIo.Flag('IssuesReopened', IssuesReopened);
  AIo.Flag('IssuesReviewBuild', IssuesReviewBuild);
  AIo.Flag('IssuesAttach', IssuesAttach);
  AIo.Text('IssuesAttachLogFiles', IssuesAttachLogFiles);
  AIo.Number('IssuesAttachMaxImageWidth', IssuesAttachMaxImageWidth);
  AIo.Flag('IssuesAttachRaiseProgram', IssuesAttachRaiseProgram);
end;

end.
