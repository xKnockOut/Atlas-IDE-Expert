unit Atlas.Core.Settings.Plugin.Issues;

// Einstellungen des IDE-Plugins, Bereich Issue-Tracker (issues.*) (#227, ADR 0017):
// Felder, Vorgaben, Grenzen, Lesen und Schreiben. TAtlasPluginSettings (Atlas.Core.Settings.Plugin)
// fasst die Bereiche zusammen und reicht die Felder als Eigenschaften durch.

interface

uses
  Atlas.Core.Settings.Plugin.Store;

const
  /// <summary>Grenzen und Vorgabe von issues.attach.maxImageWidth (#1276), wie TAtlasAttachImage.</summary>
  MinAttachImageWidth = 320;
  MaxAttachImageWidth = 7680;
  DefaultAttachImageWidth = 1920;
  /// <summary>Werte von issues.start (#765); wie TAtlasMyIssues.StartName.</summary>
  IssuesStartBranch = 'branch';
  IssuesStartRemember = 'remember';
  /// <summary>Vorgabe für issues.commitPattern (#765); wie TAtlasTrackerNaming.CommitPattern.
  /// </summary>
  DefaultIssuesCommitPattern = '{kennung} ';
  /// <summary>Grenzen und Vorgabe von issues.blameLinks.maxRevisions (#1275).</summary>
  MinIssuesBlameMaxRevisions = 1;
  MaxIssuesBlameMaxRevisions = 5000;
  DefaultIssuesBlameMaxRevisions = 200;
  /// <summary>Vorgaben für Zustand und Kommentar (#1266); wie TAtlasTrackerWorkflow.</summary>
  DefaultIssuesStateField = 'State';
  DefaultIssuesAssigneeField = 'Assignee';
  DefaultIssuesEndComment = 'Erledigt in {branch}.\n{commits}';
  /// <summary>Vorgabe von issues.commentSnippets (#1278), wie TAtlasCommentSnippets.Defaults.</summary>
  DefaultIssuesCommentSnippets = '[{"name":"Bitte mit aktuellem Build prüfen","text":"Bitte mit dem aktuellen Build ' +
    'prüfen."},{"name":"Behoben in {commit}","text":"Behoben in {commit}."}]';
  /// <summary>Höchstlänge der Kommentarvorlagen und der Liste der Zielzustände (#1266).</summary>
  MaxIssuesTemplate = 2000;
  /// <summary>Grenzen und Vorgaben der Zeiterfassung (#1267, issues.idleMinutes, issues.timeRounding); wie
  /// TAtlasTimeClock bzw. TAtlasTimeRounding.</summary>
  MinIssuesIdleMinutes = 1;
  MaxIssuesIdleMinutes = 120;
  DefaultIssuesIdleMinutes = 10;
  MinIssuesTimeRounding = 1;
  MaxIssuesTimeRounding = 60;
  DefaultIssuesTimeRounding = 5;
  /// <summary>Grenzen und Vorgabe von issues.notify.intervalMinutes (#1271); wie TAtlasTrackerNotify.MinInterval
  /// und DefaultInterval (Test prüft Gleichheit).</summary>
  MinIssuesNotifyMinutes = 2;
  MaxIssuesNotifyMinutes = 1440;
  DefaultIssuesNotifyMinutes = 10;
  /// <summary>Werte von issues.notify.scope (#1271); wie TAtlasTrackerNotify.ScopeName.</summary>
  IssuesNotifyAssigned = 'assigned';
  IssuesNotifyAssignedOrCreated = 'assignedOrCreated';
  IssuesNotifyWatched = 'watched';

type
  /// <summary>Plugin-Einstellungen: Verbindungen, Abfragen und Arbeitsablauf des Issue-Trackers.</summary>
  TAtlasPluginIssuesSettings = record
    /// <summary>Modul-Schalter issues.enabled (#1454): Issue-Tracker und Build-Server; aus = die wirksamen Werte aller Einstellungen des Moduls sind
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
    /// <summary>Textbausteine für Kommentare (#1278, issues.commentSnippets) als JSON-Liste [{"name", "text"}].</summary>
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
    /// <summary>„An Issue anhängen …“ (#1276, issues.attach): Bildschirmfoto, Formular, Log, Debug-Notiz und
    /// Exception-Verlauf an ein Issue hängen; aus = der Befehl fehlt überall.</summary>
    IssuesAttach: Boolean;
    /// <summary>Vorgeschlagene Logdateien (#1276, issues.attach.logFiles), getrennt durch „;“, mit $(ProjectDir)
    /// und * (TAtlasAttachLog.Candidates); '' = keine.</summary>
    IssuesAttachLogFiles: string;
    /// <summary>Bilder höchstens so breit (#1276, issues.attach.maxImageWidth, MinAttachImageWidth bis
    /// MaxAttachImageWidth).</summary>
    IssuesAttachMaxImageWidth: Integer;
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

/// <summary>issues.notify.scope (#1271): bekannter Wert, sonst IssuesNotifyAssignedOrCreated.</summary>
function NormalizedIssuesNotifyScope(const AText: string): string;
begin
  if SameText(Trim(AText), IssuesNotifyAssigned) then
  begin
    Result := IssuesNotifyAssigned;
  end
  else if SameText(Trim(AText), IssuesNotifyWatched) then
  begin
    Result := IssuesNotifyWatched;
  end
  else
  begin
    Result := IssuesNotifyAssignedOrCreated;
  end;
end;

/// <summary>issues.start (#765): bekannter Wert, sonst IssuesStartBranch.</summary>
function NormalizedIssuesStart(const AText: string): string;
begin
  if SameText(Trim(AText), IssuesStartRemember) then
  begin
    Result := IssuesStartRemember;
  end
  else
  begin
    Result := IssuesStartBranch;
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
  if Length(Result) > MaxIssuesTemplate then
  begin
    Result := Copy(Result, 1, MaxIssuesTemplate);
  end;
end;

{ TAtlasPluginIssuesSettings }

class function TAtlasPluginIssuesSettings.Defaults: TAtlasPluginIssuesSettings;
begin
  Result.IssuesEnabled := True;
  Result.IssuesTracker := '';
  Result.IssuesStart := IssuesStartBranch;
  Result.IssuesBranchPattern := '';
  Result.IssuesBranchBase := '';
  Result.IssuesCommitPattern := DefaultIssuesCommitPattern;
  Result.TrackerLogin := True;
  Result.IssuesConnections := '[]';
  Result.IssuesProjects := '[]';
  Result.IssuesQueries := '[]';
  Result.IssuesQueryPicker := True;
  Result.IssuesSyncState := True;
  Result.IssuesStateField := DefaultIssuesStateField;
  Result.IssuesAssigneeField := DefaultIssuesAssigneeField;
  Result.IssuesStartState := '';
  Result.IssuesAssignOnStart := False;
  Result.IssuesStartComment := '';
  Result.IssuesEndStates := '';
  Result.IssuesEndComment := DefaultIssuesEndComment;
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
  IssuesStateField := NormalizedIssuesText(IssuesStateField, True);
  if IssuesStateField = '' then
  begin
    IssuesStateField := DefaultIssuesStateField;
  end;
  IssuesAssigneeField := NormalizedIssuesText(IssuesAssigneeField, True);
  if IssuesAssigneeField = '' then
  begin
    IssuesAssigneeField := DefaultIssuesAssigneeField;
  end;
  IssuesStartState := NormalizedIssuesText(IssuesStartState, True);
  IssuesStartComment := NormalizedIssuesTemplate(IssuesStartComment);
  IssuesEndStates := NormalizedIssuesTemplate(IssuesEndStates);
  IssuesEndComment := NormalizedIssuesTemplate(IssuesEndComment);
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
  AIo.Flag('IssuesSyncState', IssuesSyncState);
  AIo.Text('IssuesStateField', IssuesStateField);
  AIo.Text('IssuesAssigneeField', IssuesAssigneeField);
  AIo.Text('IssuesStartState', IssuesStartState);
  AIo.Flag('IssuesAssignOnStart', IssuesAssignOnStart);
  AIo.Text('IssuesStartComment', IssuesStartComment);
  AIo.Text('IssuesEndStates', IssuesEndStates);
  AIo.Text('IssuesEndComment', IssuesEndComment);
end;

{ TAtlasPluginIssueWorkSettings }

class function TAtlasPluginIssueWorkSettings.Defaults: TAtlasPluginIssueWorkSettings;
begin
  Result.IssuesPreview := True;
  Result.IssuesPreviewComments := True;
  Result.IssuesCodeLinks := True;
  Result.IssuesBlameLinks := True;
  Result.IssuesBlameMaxRevisions := DefaultIssuesBlameMaxRevisions;
  Result.IssuesCreate := True;
  Result.IssuesCreateIncludeCode := True;
  Result.IssuesTimeTracking := False;
  Result.IssuesIdleMinutes := DefaultIssuesIdleMinutes;
  Result.IssuesTimeRounding := DefaultIssuesTimeRounding;
  Result.IssuesPreviewChecklists := True;
  Result.IssuesChecklistStatus := True;
  Result.IssuesPreviewLinks := True;
  Result.IssuesWarnBlocked := True;
  Result.IssuesBoard := True;
  Result.IssuesBoardConfirmMove := True;
  Result.IssuesBoardOnlyMine := True;
  Result.IssuesSprintBurndown := True;
  Result.IssuesSprintCompare := True;
  Result.IssuesPaletteSearch := True;
  Result.IssuesCommentEditor := True;
  Result.IssuesCommentSnippets := DefaultIssuesCommentSnippets;
  Result.IssuesPreviewDevelopment := True;
  Result.IssuesNotify := False;
  Result.IssuesNotifyIntervalMinutes := DefaultIssuesNotifyMinutes;
  Result.IssuesNotifyScope := IssuesNotifyAssignedOrCreated;
  Result.IssuesAttach := True;
  Result.IssuesAttachLogFiles := '';
  Result.IssuesAttachMaxImageWidth := DefaultAttachImageWidth;
end;

procedure TAtlasPluginIssueWorkSettings.Normalize;
begin
  IssuesAttachLogFiles := Trim(IssuesAttachLogFiles);
  IssuesAttachMaxImageWidth := EnsureRange(IssuesAttachMaxImageWidth, MinAttachImageWidth, MaxAttachImageWidth);
  IssuesBlameMaxRevisions := EnsureRange(IssuesBlameMaxRevisions, MinIssuesBlameMaxRevisions,
    MaxIssuesBlameMaxRevisions);
  IssuesIdleMinutes := EnsureRange(IssuesIdleMinutes, MinIssuesIdleMinutes, MaxIssuesIdleMinutes);
  IssuesTimeRounding := EnsureRange(IssuesTimeRounding, MinIssuesTimeRounding, MaxIssuesTimeRounding);
  // Leer heißt: keine Textbausteine (die Vorgaben kommen nur, wenn der Wert fehlt).
  IssuesCommentSnippets := Trim(IssuesCommentSnippets);
  if IssuesCommentSnippets = '' then
  begin
    IssuesCommentSnippets := '[]';
  end;
  IssuesNotifyIntervalMinutes := EnsureRange(IssuesNotifyIntervalMinutes, MinIssuesNotifyMinutes,
    MaxIssuesNotifyMinutes);
  IssuesNotifyScope := NormalizedIssuesNotifyScope(IssuesNotifyScope);
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
  AIo.Flag('IssuesPreviewLinks', IssuesPreviewLinks);
  AIo.Flag('IssuesWarnBlocked', IssuesWarnBlocked);
  AIo.Flag('IssuesBoard', IssuesBoard);
  AIo.Flag('IssuesBoardConfirmMove', IssuesBoardConfirmMove);
  AIo.Flag('IssuesBoardOnlyMine', IssuesBoardOnlyMine);
  AIo.Flag('IssuesSprintBurndown', IssuesSprintBurndown);
  AIo.Flag('IssuesSprintCompare', IssuesSprintCompare);
  AIo.Flag('IssuesPaletteSearch', IssuesPaletteSearch);
  AIo.Flag('IssuesCommentEditor', IssuesCommentEditor);
  AIo.Text('IssuesCommentSnippets', IssuesCommentSnippets);
  AIo.Flag('IssuesPreviewDevelopment', IssuesPreviewDevelopment);
  AIo.Flag('IssuesNotify', IssuesNotify);
  AIo.Number('IssuesNotifyIntervalMinutes', IssuesNotifyIntervalMinutes);
  AIo.Text('IssuesNotifyScope', IssuesNotifyScope);
  AIo.Flag('IssuesAttach', IssuesAttach);
  AIo.Text('IssuesAttachLogFiles', IssuesAttachLogFiles);
  AIo.Number('IssuesAttachMaxImageWidth', IssuesAttachMaxImageWidth);
end;

end.
