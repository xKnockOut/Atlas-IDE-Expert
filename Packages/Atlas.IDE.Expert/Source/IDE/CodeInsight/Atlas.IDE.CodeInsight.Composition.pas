unit Atlas.IDE.CodeInsight.Composition;

// Meldet den Code Insight-Manager, die Optionsseite "Atlas" (#227), die
// Compile-Ereignisse (#527), den Einfrier-Wächter (#501), das Neuladen
// extern geänderter Dateien (#536), die Befehlspalette (#502), die farbigen
// Klammerpaare (#514), das Ergebnisfenster (#400), die Editorbefehle samt
// Tastenkürzeln und Kontextmenü (#399), den Abgleich offener Formulare (#402),
// das Atlas-Statusfeld (#591), die Schnellschalter (#604), das
// dateiübergreifende Zurücknehmen von Atlas-Änderungen (#721), die
// Versionsverwaltung (#571), den Diagnosemodus (#479) und die Einrichtung mit
// Prüfliste (#625), das Ausführen der DUnitX-Tests (#69) und die Startprofile
// samt Feld in der Statusleiste (#575), den Release-Build-Wächter (#533) beim Laden des Packages an und beim Entladen in umgekehrter Reihenfolge wieder ab
// (ADR 0006). Zuerst entscheidet der abgesicherte Start
// (#722), was angemeldet wird; RegisterFeatures holt den Rest nach, sobald
// ein Schnellschalter oder „Normal weiterarbeiten“ es erlaubt.

interface

procedure Register;

implementation

uses
  // Vorn, damit die folgenden Units gleichnamige Bezeichner aus Vcl.Menus verdecken; gebraucht wird nur TMenuItem
  // (#900).
  Vcl.Menus,
  Winapi.Windows,
  Winapi.ShellAPI,
  System.SysUtils,
  System.StrUtils,
  System.Classes,
  System.Types,
  System.Win.Registry,
  System.JSON,
  System.IOUtils,
  System.Generics.Collections,
  System.UITypes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Dialogs,
  ToolsAPI,
  Atlas.UI.Strings,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.Messages,
  Atlas.IDE.CodeInsight.Manager,
  Atlas.Core.Lsp.Session,
  Atlas.IDE.Settings.Options,
  Atlas.IDE.Completion.History,
  Atlas.IDE.Completion.Favorites,
  Atlas.IDE.Build.Notifier,
  Atlas.IDE.Build.MessageView,
  Atlas.Core.Diagnostics.Hangs,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Diagnostics.Watchdog,
  Atlas.IDE.Diagnostics.Export,
  Atlas.IDE.Diagnostics.BugReport,
  Atlas.IDE.Diagnostics.Timing,
  Atlas.IDE.Setup.Checklist,
  Atlas.IDE.Files.Reloader,
  Atlas.IDE.Commands.Palette,
  Atlas.IDE.Editor.Pairs,
  Atlas.IDE.Foundation.StructureSwitch,
  Atlas.IDE.Files.DirtyExport,
  Atlas.IDE.Files.EditInbox,
  Atlas.IDE.Build.CheckOnSave,
  Atlas.IDE.Build.Runner,
  Atlas.IDE.Build.Inbox,
  Atlas.IDE.Build.ReleaseGuard,
  Atlas.IDE.Build.Gate,
  Atlas.IDE.Build.Summary,
  Atlas.IDE.Build.OpenBuild,
  Atlas.IDE.Editor.UnitRename,
  Atlas.IDE.Settings.Project,
  Atlas.IDE.Commands.MainMenu,
  Atlas.IDE.Editor.Rename,
  Atlas.IDE.Editor.DfmPropertyRules,
  Atlas.Core.Results.Model,
  Atlas.Core.Lsp.DataFlow,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Results.Impact,
  Atlas.IDE.Commands.Editor,
  Atlas.IDE.Commands.QuickOpen,
  Atlas.IDE.Editor.NavHistory,
  Atlas.IDE.Results.Peek,
  Atlas.IDE.Outline.Cache,
  Atlas.IDE.Outline.Service,
  Atlas.IDE.Architecture.Service,
  Atlas.IDE.Hotspots.Service,
  Atlas.IDE.UnitRelations.Service,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.SymbolPath.Service,
  Atlas.IDE.Outline.Breadcrumbs,
  Atlas.IDE.EditorToolbar.Service,
  Atlas.UI.EditorToolbar.Customize,
  Atlas.IDE.StatusBar.Service,
  Atlas.IDE.Editor.MetricsLens,
  Atlas.IDE.Outline.StickyScroll,
  Atlas.IDE.Editor.LineChanges,
  Atlas.Core.Editor.LineMove,
  Atlas.IDE.Editor.LineMove,
  Atlas.IDE.Editor.BlockComment,
  Atlas.Core.Editor.NewLine,
  Atlas.IDE.Editor.NewLine,
  Atlas.IDE.Editor.Unwrap,
  Atlas.IDE.Editor.ExpressionType,
  Atlas.IDE.Editor.MethodPlacement,
  Atlas.IDE.Editor.WrapSelection,
  Atlas.IDE.Editor.CommentContinuation,
  Atlas.IDE.Editor.PatternContinuation,
  Atlas.IDE.Editor.MultiCursor,
  Atlas.IDE.Editor.LinkedEditing,
  Atlas.IDE.Editor.SmartPaste,
  Atlas.IDE.Editor.StatementCompletion,
  Atlas.IDE.Editor.OverviewRuler,
  Atlas.IDE.Editor.Minimap,
  Atlas.IDE.UnitSearch.Commands,
  Atlas.IDE.Search.Commands,
  Atlas.IDE.Generate.Commands,
  Atlas.IDE.Generate.NewFile,
  Atlas.Core.Generate.FileTemplates,
  Atlas.Core.Completion.Snippets,
  Atlas.IDE.Commands.Bindings,
  Atlas.IDE.Forms.Designer,
  Atlas.Core.Status.Registry,
  Atlas.Core.Status.Lines,
  Atlas.IDE.Status.Field,
  Atlas.IDE.Status.Lines,
  Atlas.IDE.Settings.QuickToggles,
  Atlas.IDE.Settings.Transfer,
  Atlas.IDE.Settings.Experimental,
  Atlas.Core.Status.Contract,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Sources,
  Atlas.IDE.Notifications.Service,
  Atlas.Core.Diagnostics.SafeMode,
  Atlas.IDE.Diagnostics.SafeMode,
  Atlas.IDE.Diagnostics.StackCapture,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Diagnostics.TimeLimit,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.IDE.Foundation.Keys,
  Atlas.IDE.Commands.KeyMap,
  Atlas.IDE.Commands.Usage,
  Atlas.IDE.Commands.ShortcutTips,
  Atlas.Core.Commands.ShortcutTips,
  Atlas.IDE.Undo.Changes,
  Atlas.Core.Updates.Check,
  Atlas.Core.Updates.Adapters.HttpSource,
  Atlas.IDE.Updates.Check,
  Atlas.IDE.Foundation.ResultsWindow,
  Atlas.IDE.Foundation.Symbol,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.WhatsNew,
  Atlas.Core.Welcome.QuickActions,
  Atlas.Core.StartProfiles.Store,
  Atlas.UI.Welcome.Frame,
  Atlas.Core.Commands.Palette,
  Atlas.IDE.Welcome.Search,
  Atlas.IDE.Welcome.WhatsNew,
  Atlas.IDE.Welcome.Projects,
  Atlas.IDE.Welcome.Trends,
  Atlas.IDE.Welcome.TestResults,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Ci.Providers.Jenkins,
  Atlas.Core.Ci.Adapters.Http,
  Atlas.Core.Ci.Adapters.Credentials,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.Providers.GitHub,
  Atlas.Core.Tracker.Providers.YouTrack,
  Atlas.IDE.Welcome.Issues,
  Atlas.IDE.Welcome.NewIssue,
  Atlas.Core.Tracker.NewIssue,
  Atlas.Core.Problems.Findings,
  Atlas.IDE.Tracker.IssuePreview,
  Atlas.IDE.Tracker.CodeLinks,
  Atlas.IDE.Tracker.BlameLinks,
  Atlas.UI.Welcome.TestResults,
  Atlas.UI.Welcome.Projects,
  Atlas.Core.Editor.Metrics,
  Atlas.Core.Projects.Todos,
  Atlas.Core.Projects.Baseline,
  Atlas.UI.Todos.Dialog,
  Atlas.IDE.Welcome.Unsaved,
  Atlas.IDE.Welcome.Continue,
  Atlas.IDE.Welcome.QuickActions,
  Atlas.IDE.Welcome.State,
  Atlas.IDE.Welcome.Discover,
  Atlas.IDE.Welcome.Help,
  Atlas.IDE.Welcome.Setup,
  Atlas.IDE.Welcome.Commands,
  Atlas.IDE.Welcome.Layouts,
  Atlas.IDE.Vcs.Branching,
  Atlas.IDE.Vcs.WorkingCopies,
  Atlas.IDE.Vcs.Service,
  Atlas.IDE.Notes.Service,
  Atlas.IDE.Notes.Gutter,
  Atlas.IDE.Editor.RecursionGutter,
  Atlas.IDE.Editor.GutterColumn,
  Atlas.IDE.Bookmarks.QuickColumn,
  Atlas.Core.Bookmarks.Store,
  Atlas.Core.Editor.Overview,
  Atlas.IDE.Bookmarks.QuickChord,
  Atlas.IDE.Editor.SelectionMatches,
  Atlas.IDE.Editor.ExitPoints,
  Atlas.IDE.Editor.Reassigned,
  Atlas.IDE.Bookmarks.Service,
  Atlas.IDE.Problems.Service,
  Atlas.IDE.Bookmarks.Gutter,
  Atlas.IDE.Debug.Exceptions,
  Atlas.IDE.Debug.OwnCode,
  Atlas.IDE.Debug.ExceptionBar,
  Atlas.IDE.Debug.InlineValues,
  Atlas.IDE.Debug.Unavailable,
  Atlas.IDE.Debug.DialogCompletion,
  Atlas.IDE.Debug.Evaluate,
  Atlas.IDE.Debug.AccessViolation,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Providers.Expression,
  Atlas.IDE.Build.CompilerSwitches,
  Atlas.IDE.Foundation.GutterMarks,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Editor.Hide,
  Atlas.IDE.StartProfiles.Service,
  Atlas.IDE.Debug.Visualizers,
  Atlas.IDE.Debug.DisplayRules,
  Atlas.IDE.Debug.StepInto,
  Atlas.IDE.Debug.EventBreak,
  Atlas.IDE.Debug.Trace,
  Atlas.IDE.Debug.StepFilter,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.IDE.Editor.TestUnitLens,
  Atlas.IDE.Hover.Editor,
  Atlas.IDE.Hover.DebugValue,
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Lsp.TextChanges,
  Atlas.IDE.Completion.Editor,
  Atlas.Core.Undo.Contract,
  Atlas.Core.Undo.Adapters.DiskTarget,
  Atlas.Core.Undo.Adapters.FileStore,
  Atlas.IDE.Undo.Target,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Composition,
  Atlas.Core.Vcs.Tools,
  Atlas.Core.Vcs.Adapters.ProcessRunner,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.Adapters.ServerProcess,
  Atlas.Core.Files.WatchedChanges,
  Atlas.Core.Files.Adapters.FolderWatcher,
  Atlas.Core.Signature.Contract,
  Atlas.Core.Signature.Providers.Server,
  Atlas.Core.Completion.Providers.Server,
  Atlas.Core.Completion.Providers.Snippets,
  Atlas.Core.Completion.Providers.XmlDoc,
  Atlas.Core.Diagnostics.FeatureTable,
  Atlas.Core.Diagnostics.StartTimes,
  Atlas.Core.Diagnostics.Teardown,
  Atlas.Core.Build.Inbox,
  Atlas.Core.Build.ReleaseGuard,
  Atlas.Core.Build.Gate,
  Atlas.Core.Build.Verdict,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.InlineHints,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Tests.Run,
  Atlas.Core.Tests.Debug,
  Atlas.IDE.Problems.Controller,
  Atlas.IDE.Problems.MessageList,
  Atlas.IDE.Tests.Runner,
  Atlas.IDE.Tasks.Runner,
  Atlas.Core.Tasks.Definitions,
  Atlas.Core.Tasks.Runs,
  Atlas.Core.Tasks.Adapters.Process,
  Atlas.IDE.Tests.Debug,
  Atlas.IDE.Tests.Lens;

var
  ManagerIndex: Integer = -1;
  // Gehört der IDE (Schnittstellenzähler); gültig, solange er angemeldet ist.
  Manager: TAtlasCodeInsightManager;
  // Eigene Referenz (#886): StopManager baut den Manager selbst ab, auch wenn die IDE ihn noch hält.
  ManagerRef: IInterface;
  Compile: TAtlasIdeCompileEvents;
  Watchdog: TAtlasWatchdog;
  Hangs: TAtlasHangMonitor;
  Reloader: TAtlasFileReloader;
  Palette: TAtlasIdePalette;
  Pairs: TAtlasEditorPairs;
  // Markierungen in der Rinne: persönliche Notizen (#545) und benannte Lesezeichen (#622).
  GutterMarks: TAtlasIdeGutterMarks;
  // Atlas-Spalte in der Zeilenleiste (#768).
  GutterColumn: TAtlasIdeGutterColumn;
  QuickColumn: TAtlasIdeQuickColumn;
  // Gleichen Text wie die Markierung hervorheben (#709).
  SelectionMatches: TAtlasIdeSelectionMatches;
  // Issue-Kennungen im Code (#1265), über „Meine Issues“.
  IssueLinks: TAtlasIdeCodeLinks;
  // Issues in der Zeilenhistorie (#1275), über „Meine Issues“ und die Zeilenhistorie.
  BlameIssues: TAtlasIdeBlameLinks;
  // Ungespeicherte Dateien für schreibende MCP-Werkzeuge (#61).
  DirtyExport: TAtlasDirtyExport;
  // Schreibende MCP-Werkzeuge ändern offene Dateien über das Plugin (#397).
  EditInbox: TAtlasIdeEditInbox;
  CheckOnSave: TAtlasIdeCheckOnSave;
  // Bauen auf Auftrag über IOTAProjectBuilder (#261), z. B. für Claude Code; lebt mit den Compile-Ereignissen.
  BuildRunner: TAtlasIdeBuildRunner;
  // Zusammenfassung und letzte Meldungen je Projekt (#530); lebt mit den Compile-Ereignissen.
  BuildSummary: TAtlasIdeBuildSummary;
  // Eingang des MCP-Werkzeugs build_project (#261), abschaltbar über McpBuild.
  BuildInbox: TAtlasIdeBuildInbox;
  // Beim Öffnen eines Projekts oder einer Projektgruppe einmal bauen (build.onOpen); lebt mit den
  // Compile-Ereignissen.
  OpenBuild: TAtlasIdeOpenBuild;
  UnitRename: TAtlasIdeUnitRename;
  // DUnitX-Tests ausführen samt Code Lens (#69), abschaltbar über TestRun bzw. CodeLensTests.
  Tests: TAtlasIdeTests;
  // Einzelnen Test ausführen bzw. im Debugger starten (#585), lebt mit Tests; abschaltbar über TestDebug.
  TestDebugger: TAtlasIdeTestDebugger;
  TestsLens: TAtlasIdeTestsLens;
  // Projektaufgaben aus atlas.json (#900), abschaltbar über tasks.enabled.
  ProjectTasks: TAtlasIdeTasks;
  // Hauptmenü Atlas mit Schnellschaltern und Einstellungen (#227).
  MainMenu: TAtlasMainMenu;
  // Tastenkürzel der Editorbefehle (#399).
  EditorKeys: TAtlasIdeEditorKeys;
  // Offene Formulare an den Server (#402).
  Forms: TAtlasIdeForms;
  // Ergebnisfenster (#400) und Editorbefehle (#399) angemeldet.
  CommandsInstalled: Boolean;
  // Atlas-Statusfeld mit Server, Index und Datei (#591).
  StatusField: TAtlasStatusField;
  StatusLines: TAtlasIdeStatusLines;
  // Eigene Tasten für Vervollständigung und Parameter-Hint (#494); ohne Einstellung keine.
  CompletionKey: TAtlasIdeKeyBinding;
  SignatureKey: TAtlasIdeKeyBinding;
  // Schnellschalter mit Fenster, Taste und Befehlen in der Palette (#604).
  QuickToggles: TAtlasIdeQuickToggles;
  // Benachrichtigungszentrale mit Liste, Plakette im Statusfeld und Build-Einträgen (#601).
  Notifications: TAtlasIdeNotifications;
  // Diagnosemodus mit Fenster, Taste und Statuszeile (#479).
  DiagnosticMode: TAtlasIdeDiagnosticMode;
  // Einrichtung mit Prüfliste und Statuszeile (#625).
  Setup: TAtlasIdeSetupChecklist;
  // Tastenkürzel-Übersicht mit Prüfung beim Start (#520).
  KeyMap: TAtlasIdeKeyMap;
  // Gemeinsame Zählung je Befehl und Tippquelle (#600, #757); auch abgesichert (liest und schreibt nur
  // lokale Dateien).
  CommandUsage: TAtlasIdeCommandUsage;
  // Tastenkürzel-Tipps, zählen in CommandUsage (#600); nur im normalen Start.
  ShortcutTips: TAtlasIdeShortcutTips;
  // Abgesicherter Start nach einem Absturz (#722).
  SafeMode: TAtlasIdeSafeMode;
  // Rückfrage und tägliche Update-Prüfung (#495).
  Updates: TAtlasIdeUpdates;
  // Zeitpunkt des Ladens (TAtlasWatchdog.Timestamp) für Ladezeit und Startanteile.
  LoadedAt: Int64;
  // Startanteile von Atlas bis zur freien Nachrichtenschleife (Bericht N4); danach nil.
  StartTimes: TAtlasStartTimes;
  // Paketbeobachtung und Meldung fremder Vervollständigung angemeldet (#494).
  KeysWatched: Boolean;
  // Atlas-Bereiche auf der Willkommensseite und Fenster „Atlas-Start“ (#753).
  Welcome: TAtlasIdeWelcome;
  // Dienste für Notizen (#545) und Lesezeichen (#622) gestartet.
  NotesStarted: Boolean;
  BookmarksStarted: Boolean;
  // Fenster „Atlas-Prüfung“ (#909) gestartet.
  ProblemsWindowStarted: Boolean;
  HideStarted: Boolean;
  // Teile des Plugins in Startreihenfolge (Code-Review S-03); gefüllt beim ersten RegisterFeatures.
  Features: TAtlasFeatureTable;

const
  // Ab dieser Dauer ein Hinweis im Meldungsfenster (#501).
  HangHintMs = 2000;

/// <summary>Alle Tasten von Atlas nach den Einstellungen neu belegen; bei Konflikt nur mit Vorrang (#494).</summary>
procedure RebindKeys;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  if Palette <> nil then
    Palette.Rebind;
  if CheckOnSave <> nil then
    CheckOnSave.Rebind;
  if EditorKeys <> nil then
    EditorKeys.Rebind;
  if CompletionKey <> nil then
    CompletionKey.Rebind(Word(Settings.CompletionKey), Settings.CompletionKeyPriority,
      TAtlasStrings.Text(TAtlasTextId.SettingsCompletionKey));
  if SignatureKey <> nil then
    SignatureKey.Rebind(Word(Settings.SignatureKey), Settings.SignatureKeyPriority,
      TAtlasStrings.Text(TAtlasTextId.SettingsSignatureKey));
  if QuickToggles <> nil then
    QuickToggles.Rebind;
  if DiagnosticMode <> nil then
    DiagnosticMode.Rebind;
end;

procedure ReportHang(const AHang: TAtlasHang);
var
  Hang: TAtlasHang;
  Text, Activity: string;
  Messages: IOTAMessageServices;
  Group: IOTAMessageGroup;
begin
  if (Hangs = nil) or (Manager = nil) then
    Exit;
  Hang := AHang;
  if Compile <> nil then
  begin
    Hang.CodeInsightCount := Compile.Events.CodeInsightCount;
    Hang.CodeInsightMs := Compile.Events.CodeInsightMs;
  end;
  Hangs.ThresholdMs := TAtlasIdeSettings.Current.HangThresholdMs;
  Text := Hangs.Finish(Hang);
  if Text = '' then
    Exit;
  Manager.Report(Text);
  if not TAtlasIdeSettings.Current.HangHint or (Hang.DurationMs < HangHintMs) or
    not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Exit;
  Activity := '';
  if Hang.Activity <> '' then
    Activity := ' (' + Hang.Activity + ')';
  Group := Messages.GetGroup('Atlas');
  if Group = nil then
    Group := Messages.AddMessageGroup('Atlas');
  // Nie als Dialog und ohne das Meldungsfenster nach vorn zu holen.
  Messages.AddTitleMessage(TAtlasStrings.Fmt(TAtlasTextId.HangHint, [Hang.DurationMs, Activity]), Group);
end;

/// <summary>Warnung der Sicherung (#493): Meldungsansicht und Plugin-Protokoll, nie als Dialog.</summary>
procedure GuardWarning(const AText: string);
var
  Messages: IOTAMessageServices;
  Group: IOTAMessageGroup;
begin
  if Manager <> nil then
    Manager.Report(AText);
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Exit;
  Group := Messages.GetGroup('Atlas');
  if Group = nil then
    Group := Messages.AddMessageGroup('Atlas');
  Messages.AddTitleMessage(AText, Group);
end;

/// <summary>Zeile in der Meldungsansicht, ohne Plugin-Protokoll (z. B. Hinweis auf eine neue Version, #495).</summary>
procedure MessageLine(const AText: string);
var
  Messages: IOTAMessageServices;
  Group: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Exit;
  Group := Messages.GetGroup('Atlas');
  if Group = nil then
    Group := Messages.AddMessageGroup('Atlas');
  Messages.AddTitleMessage(AText, Group);
end;

/// <summary>„Fehlerbericht erstellen…“ (#108) aus Menü, Palette und dem Fenster des abgesicherten Starts.</summary>
// Serverprozess, Ordnerbeobachter und Quellen von Vervollständigung und
// Parameter-Hint aus dem Kern (A-09).
function CodeInsightAdapters: TAtlasCodeInsightAdapters;
begin
  Result.NewServer :=
    function(AExeName, AArguments: string): IAtlasLspServer
    begin
      Result := TLspServerProcess.Create(AExeName, AArguments);
    end;
  Result.NewFolderWatcher :=
    function(AChanges: TAtlasWatchedChanges): IAtlasFolderWatcher
    begin
      Result := TAtlasFolderWatcher.Create(AChanges);
    end;
  Result.NewSignatureSource :=
    function(ASession: TAtlasSessionFunc): IAtlasSignatureSource
    begin
      Result := TAtlasServerSignatureProvider.Create(ASession);
    end;
  Result.NewCompletionSources :=
    function(const ASession: TAtlasSessionFunc; const ALog: TAtlasLogProc): TAtlasCompletionSources
    var
      Server: TAtlasServerCompletionProvider;
      Snippets: TAtlasSnippetCompletionProvider;
    begin
      Server := TAtlasServerCompletionProvider.Create(ASession);
      Server.OnLog :=
        procedure(const AMessage: string)
        begin
          ALog(AMessage);
        end;
      Snippets := TAtlasSnippetCompletionProvider.Create(TAtlasSnippets.BuiltIn);
      // Die Schnittstellen halten die Quellen; die Funktionen greifen über die Objekte zu.
      Result.Server := Server;
      Result.XmlDoc := TAtlasXmlDocCompletionProvider.Create;
      Result.Snippets := Snippets;
      Result.Shutdown :=
        procedure
        begin
          Server.Shutdown;
          Snippets.Shutdown;
        end;
      Result.SetSnippetsEnabled :=
        procedure(AEnabled: Boolean)
        begin
          Snippets.Enabled := AEnabled;
          Server.Snippets := AEnabled;
        end;
      Result.SetSnippetList :=
        procedure(AList: TAtlasSnippetList)
        begin
          Snippets.SetSnippets(AList);
        end;
      Result.SnippetList :=
        function: TAtlasSnippetList
        begin
          Result := Snippets.Snippets;
        end;
    end;
end;

// Versionsverwaltung: Prozessläufer und Auswahl des Kerns (A-09).
function VcsBackend: TAtlasIdeVcsBackend;
begin
  Result.NewRunner :=
    function(ACancelled: TFunc<Boolean>): IAtlasVcsRunner
    begin
      Result := TAtlasVcsProcessRunner.Create(False, ACancelled);
    end;
  Result.Open :=
    function(const AFolder: string; AProvider: TAtlasVcsProvider; const ARunner: IAtlasVcsRunner;
      ATimeoutMs: Cardinal): IAtlasVersionControl
    begin
      if ATimeoutMs = 0 then
        Exit(TAtlasVersionControl.Open(AFolder, AProvider, ARunner));
      Result := TAtlasVersionControl.Open(AFolder, AProvider, ARunner,
        function(AKind: TAtlasVcsKind): string
        begin
          Result := TAtlasVcsTools.Find(AKind);
        end,
        ATimeoutMs);
    end;
  Result.SetToolMissing :=
    procedure(AHandler: TProc<TAtlasVcsKind>)
    begin
      TAtlasVcsNotices.OnToolMissing := AHandler;
    end;
end;

procedure CreateBugReport;
begin
  TAtlasIdeBugReport.Execute(
    procedure(const ACommand, AArgumentsJson: string; const ADone: TProc<TJSONValue>)
    begin
      // Im Hintergrund (#874): Der Server antwortet auch während des Indexierens sofort, das Plugin wartet nicht.
      if Manager <> nil then
        Manager.RunServerCommandAsync(ACommand, AArgumentsJson, 10000, ADone)
      else
        ADone(nil);
    end,
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end);
end;

const
  MetricsCommand = 'atlas.server.metrics';
  TodosCommand = 'atlas.server.todos';

function MetricsArguments(const AProject, AMode: string): string;
var
  Arguments: TJSONArray;
begin
  Arguments := TJSONArray.Create;
  try
    Arguments.Add(TLspSession.PathToUri(AProject));
    Arguments.Add(AMode);
    Result := Arguments.ToJSON;
  finally
    Arguments.Free;
  end;
end;

/// <summary>Stand der Baseline (#97) im Ordner AFolder; liest nur lokale Dateien, auch im Hintergrund.</summary>
function BaselineState(const AFolder: string): TAtlasBaselineState;
begin
  Result := TAtlasProjectBaselines.StateOf(AFolder,
    function(const AFileName: string): Boolean
    begin
      Result := FileExists(AFileName);
    end,
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := '';
      try
        AText := TFile.ReadAllText(AFileName, TEncoding.UTF8);
        Result := True;
      except
        on Exception do
          Result := False;
      end;
    end);
end;

/// <summary>Code-Metriken (#66), TODO-Übersicht (#68) und Stand der Baseline (#97) nach einem Build für die
/// Projekt-Zusammenfassung (Projektverlauf #758, Einrichtung #759): in einem Hintergrundlauf vom laufenden Server
/// (startet ihn nicht), Zeitpunkt AStampUtc der des Builds: Damit kommen die Werte in seinen Messpunkt.</summary>
procedure RecordProjectMetrics(const AProject: string; AStampUtc: TDateTime);
var
  Project: string;
  Stamp: TDateTime;
begin
  if (Manager = nil) or (Welcome = nil) or (Welcome.Projects = nil) or (AProject = '') or
    not TAtlasIdeSettings.Current.Enabled then
    Exit;
  Project := AProject;
  Stamp := AStampUtc;
  Manager.RunCommandsAsync([MetricsCommand, TodosCommand],
    [MetricsArguments(Project, 'summary'), MetricsArguments(Project, 'summary')], 60000,
    procedure(AAnswers: TArray<string>)
    var
      Answers: TArray<string>;
      Baseline: TAtlasBaselineState;
    begin
      Answers := AAnswers;
      // Die Baseline-Datei hier im Hintergrund lesen: Bei Altprojekten prüft das viele Pfade.
      Baseline := BaselineState(ExtractFileDir(Project));
      TAtlasMainThread.Queue(TAtlasFeature.WelcomePage,
        procedure
        begin
          if (Welcome <> nil) and (Welcome.Projects <> nil) then
            TAtlasGuard.Run(TAtlasFeature.WelcomePage,
              procedure
              begin
                // Leere oder ungültige Antworten lassen die Zusammenfassung unverändert.
                Welcome.Projects.RecordMetrics(Project, Answers[0], Stamp);
                Welcome.Projects.RecordTodos(Project, Answers[1], Stamp);
                Welcome.Projects.RecordBaseline(Project, Baseline, Stamp);
              end);
        end);
    end);
end;

/// <summary>Metrikbericht des aktiven Projekts (#66): Markdown vom Server (startet ihn bei Bedarf) im
/// Hintergrund, gespeichert unter %LOCALAPPDATA%\Atlas\Berichte und im Editor geöffnet.</summary>
procedure MetricsReport;
var
  Project: IOTAProject;
  FileName: string;
begin
  // Abgeschaltet: auch über Tastenkürzel oder „Ausprobieren“ nichts tun.
  if (Manager = nil) or not TAtlasIdeSettings.Current.MetricsReport then
    Exit;
  Project := GetActiveProject;
  if (Project = nil) or (Project.FileName = '') then
  begin
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.MetricsReportNoProject));
    Exit;
  end;
  FileName := TAtlasMetricsReportFile.FileName(
    TAtlasMetricsReportFile.Folder(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas')), Project.FileName);
  if Manager.ActiveSession = nil then
  begin
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.MetricsReportFailed));
    Exit;
  end;
  if Manager.RunCommandAsync(MetricsCommand, MetricsArguments(Project.FileName, 'markdown'), 120000,
    procedure(AAnswer: string)
    var
      Answer: string;
    begin
      Answer := AAnswer;
      TAtlasMainThread.Queue(TAtlasFeature.Menu,
        procedure
        begin
          TAtlasGuard.Run(TAtlasFeature.Palette,
            procedure
            var
              Text: string;
              Actions: IOTAActionServices;
            begin
              if not TAtlasMetricsReportFile.MarkdownFrom(Answer, Text) then
              begin
                GuardWarning(TAtlasStrings.Text(TAtlasTextId.MetricsReportFailed));
                Exit;
              end;
              ForceDirectories(ExtractFileDir(FileName));
              TFile.WriteAllText(FileName, Text, TEncoding.UTF8);
              if Supports(BorlandIDEServices, IOTAActionServices, Actions) then
                Actions.OpenFile(FileName);
            end);
        end);
    end) then
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.MetricsReportRunning))
  else
    // Ein Befehl im Hintergrund läuft schon (etwa die Metriken nach einem Build): später noch einmal.
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.MetricsReportBusy));
end;

const
  /// <summary>Höchstens so viele Pfade in Rückfrage und Meldung; der Rest als „… und n weitere“.</summary>
  BaselineOrphanLines = 15;

/// <summary>Einträge ohne Datei (#97) als Zeilen „Pfad (n Treffer)“, höchstens BaselineOrphanLines.</summary>
function BaselineOrphanText(const AOrphans: TArray<TAtlasBaselineOrphan>): TArray<string>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to High(AOrphans) do
  begin
    if Index = BaselineOrphanLines then
    begin
      Result := Result + [TAtlasStrings.Fmt(TAtlasTextId.BaselineUpdateOrphansMore, [Length(AOrphans) - Index])];
      Break;
    end;
    Result := Result + [TAtlasStrings.Fmt(TAtlasTextId.BaselineUpdateOrphanLine, [AOrphans[Index].Path,
      AOrphans[Index].Count])];
  end;
end;

/// <summary>Ergebnis von atlas.updateBaseline (#97) in der Meldungsansicht: zuerst die entfernten Einträge ohne
/// Datei mit Pfaden, dann die Zähler. Nur dort, nicht im Plugin-Protokoll: Es enthält Pfade.</summary>
procedure ReportBaselineUpdate(const AUpdate: TAtlasBaselineUpdate);
var
  Line: string;
begin
  if AUpdate.OrphanCount > 0 then
  begin
    MessageLine(TAtlasStrings.Fmt(TAtlasTextId.BaselineUpdateOrphans, [AUpdate.OrphanCount]));
    for Line in BaselineOrphanText(AUpdate.Orphans) do
      MessageLine(Line);
  end;
  MessageLine(TAtlasStrings.Fmt(TAtlasTextId.BaselineUpdateDone, [AUpdate.FileName, AUpdate.Total, AUpdate.Files,
    AUpdate.Added, AUpdate.Removed, AUpdate.Unchanged]));
  if AUpdate.Completed > 0 then
    MessageLine(TAtlasStrings.Fmt(TAtlasTextId.BaselineUpdateCompleted, [AUpdate.Completed]));
  // Bericht N3: Die unbrauchbare bisherige Datei wurde nicht still ersetzt.
  if AUpdate.SetAside <> '' then
    MessageLine(TAtlasStrings.Fmt(TAtlasTextId.BaselineUpdateSetAside, [AUpdate.SetAside]));
end;

/// <summary>Lässt den Server (atlas.updateBaseline, #97) im Hintergrund alle Dateien von AFileName prüfen und die
/// Baseline schreiben, meldet die Zähler und schreibt den Abschnitt "baseline" der Projekt-Zusammenfassung. ADone
/// (darf nil sein) bekommt im Hauptthread das Ergebnis (Einrichtung #759). '' = gestartet, sonst der Grund.</summary>
function StartBaselineUpdate(const AFileName: string; const ADone: TAtlasSetupBaselineDone): string;
var
  FileName: string;
  Done: TAtlasSetupBaselineDone;
begin
  Result := '';
  if Manager = nil then
    Exit(TAtlasStrings.Text(TAtlasTextId.BaselineUpdateFailed));
  if Manager.ActiveSession = nil then
    Exit(TAtlasStrings.Text(TAtlasTextId.BaselineUpdateFailed));
  FileName := AFileName;
  Done := ADone;
  if not Manager.RunCommandAsync(TAtlasProjectBaselines.Command,
    TAtlasProjectBaselines.Arguments(TLspSession.PathToUri(FileName)), TAtlasProjectBaselines.TimeoutMs,
    procedure(AAnswer: string)
    var
      Answer: string;
      Update: TAtlasBaselineUpdate;
      Valid, Elsewhere: Boolean;
      After: TAtlasBaselineState;
    begin
      Answer := AAnswer;
      After := Default(TAtlasBaselineState);
      // Im Hintergrund: Antwort lesen und die neue Datei zählen.
      Valid := TAtlasProjectBaselines.FromServer(Answer, Update);
      // Nicht im Projektordner geschrieben (#758): Verlauf und Einrichtung lesen weiter dort.
      Elsewhere := Valid and TAtlasProjectBaselines.WrittenElsewhere(FileName, Update.FileName);
      if Elsewhere then
        After := BaselineState(ExtractFileDir(FileName))
      else if Valid then
        After := BaselineState(ExtractFileDir(Update.FileName));
      TAtlasMainThread.Queue(TAtlasFeature.Menu,
        procedure
        begin
          TAtlasGuard.Run(TAtlasFeature.Palette,
            procedure
            begin
              if not Valid then
              begin
                GuardWarning(TAtlasStrings.Text(TAtlasTextId.BaselineUpdateFailed));
                if Assigned(Done) then
                  Done(False, 0, 0, TAtlasStrings.Text(TAtlasTextId.BaselineUpdateFailed));
                Exit;
              end;
              ReportBaselineUpdate(Update);
              if Elsewhere then
              begin
                MessageLine(TAtlasStrings.Fmt(TAtlasTextId.BaselineUpdateElsewhere, [ExtractFileDir(Update.FileName),
                  ExtractFileDir(FileName)]));
                // Zähler des Servers gehören zur anderen Datei: nur den Stand im Projektordner eintragen.
                if (Welcome <> nil) and (Welcome.Projects <> nil) then
                  Welcome.Projects.RecordBaseline(FileName, After, TAtlasIdeProjects.StampUtc);
                if Assigned(Done) then
                  Done(False, 0, 0, TAtlasStrings.Text(TAtlasTextId.WelcomeSetupBaselineElsewhere));
                Exit;
              end;
              if (Welcome <> nil) and (Welcome.Projects <> nil) then
                Welcome.Projects.RecordBaseline(FileName, After, Update, TAtlasIdeProjects.StampUtc);
              if Assigned(Done) then
                Done(True, Update.Total, Update.Files, '');
            end);
        end);
    end) then
    // Ein Befehl im Hintergrund läuft schon (etwa die Werte nach einem Build): später noch einmal.
    Result := TAtlasStrings.Text(TAtlasTextId.BaselineUpdateBusy);
end;

/// <summary>„Baseline des Projekts aktualisieren“ (#97): nennt vorher die Einträge ohne Datei und fragt nach, dann
/// StartBaselineUpdate für das aktive Projekt.</summary>
procedure UpdateBaseline;
var
  Project: IOTAProject;
  FileName, Reason: string;
  State: TAtlasBaselineState;
begin
  // Abgeschaltet: auch über Tastenkürzel oder „Ausprobieren“ nichts tun.
  if (Manager = nil) or not TAtlasIdeSettings.Current.BaselineUpdate then
    Exit;
  Project := GetActiveProject;
  if (Project = nil) or (Project.FileName = '') then
  begin
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.BaselineUpdateNoProject));
    Exit;
  end;
  if Manager.ActiveSession = nil then
  begin
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.BaselineUpdateFailed));
    Exit;
  end;
  FileName := Project.FileName;
  // Einträge ohne Datei nennen, bevor das Aktualisieren sie entfernt (umbenannte oder verschobene Dateien).
  State := BaselineState(ExtractFileDir(FileName));
  if (State.OrphanCount > 0) and (MessageDlg(TAtlasStrings.Fmt(TAtlasTextId.BaselineUpdateConfirm,
    [State.OrphanCount, sLineBreak + string.Join(sLineBreak, BaselineOrphanText(State.Orphans)) + sLineBreak +
    sLineBreak]), mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then
    Exit;
  Reason := StartBaselineUpdate(FileName, nil);
  if Reason = '' then
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.BaselineUpdateRunning))
  else
    GuardWarning(Reason);
end;

/// <summary>Antwort von atlas.baselineCompilerMessages (#530) in der Meldungsansicht.</summary>
procedure ReportCompilerBaseline(AAnswer: TJSONValue);
var
  Added: TAtlasCompilerBaselineAdd;
begin
  if not TAtlasCompilerBaselineAdd.FromServer(AAnswer, Added) then
  begin
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.CompilerBaselineFailed));
    Exit;
  end;
  MessageLine(TAtlasStrings.Fmt(TAtlasTextId.CompilerBaselineDone, [Added.FileName, Added.Total, Added.Added,
    Added.Removed, Added.Unchanged]));
  if Added.Skipped > 0 then
    MessageLine(TAtlasStrings.Fmt(TAtlasTextId.CompilerBaselineSkipped, [Added.Skipped]));
end;

/// <summary>„Aktuelle Compilermeldungen in die Basislinie“ (#530): Warnungen und Hinweise des letzten Builds des
/// aktiven Projekts über den Server in atlas-baseline.json; danach zählen nur neue Meldungen. Gehört zur Baseline
/// (#97) und ist mit ihr abschaltbar (BaselineUpdate).</summary>
procedure AddCompilerMessagesToBaseline;
var
  Project: IOTAProject;
  Messages: TArray<TAtlasCompilerMessage>;
begin
  if (Manager = nil) or (BuildSummary = nil) or not TAtlasIdeSettings.Current.BaselineUpdate then
    Exit;
  Project := GetActiveProject;
  if (Project = nil) or (Project.FileName = '') then
  begin
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.CompilerBaselineNoProject));
    Exit;
  end;
  Messages := BuildSummary.Baselinable(Project.FileName);
  if Length(Messages) = 0 then
  begin
    GuardWarning(TAtlasStrings.Fmt(TAtlasTextId.CompilerBaselineNone, [ExtractFileName(Project.FileName)]));
    Exit;
  end;
  // Startet den Server bei Bedarf; der Befehl selbst läuft im Hintergrund.
  if Manager.ActiveSession = nil then
  begin
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.CompilerBaselineFailed));
    Exit;
  end;
  Manager.RunServerCommandAsync(TAtlasBuildVerdicts.AddCommand,
    TAtlasBuildVerdicts.Arguments(TLspSession.PathToUri(Project.FileName), Messages),
    TAtlasBuildVerdicts.AddTimeoutMs, ReportCompilerBaseline);
end;

var
  /// <summary>Letzter Filter der TODO-Liste (#68) in dieser Sitzung; Vorgabe für den Filterdialog.</summary>
  TodoFilter: TAtlasTodoFilter;
  /// <summary>Vorschläge für den Filterdialog aus der letzten Liste.</summary>
  TodoChoices: TAtlasTodoChoices;

/// <summary>Argumente für atlas.server.todos im Modus json: [uri, "json", filter].</summary>
function TodoArguments(const AProject: string; const AFilter: TAtlasTodoFilter): string;
var
  Arguments: TJSONArray;
begin
  Arguments := TJSONArray.Create;
  try
    Arguments.Add(TLspSession.PathToUri(AProject));
    Arguments.Add('json');
    Arguments.AddElement(TJSONObject.ParseJSONValue(AFilter.ToJson));
    Result := Arguments.ToJSON;
  finally
    Arguments.Free;
  end;
end;

/// <summary>TODO-Liste des aktiven Projekts (#68) im Ergebnisfenster: Daten vom Server (startet ihn bei Bedarf) im
/// Hintergrund mit dem Filter AFilter (Filter des Servers), nach Unit gruppiert; Doppelklick springt zum
/// Kommentar.</summary>
procedure ProjectTodos(const AFilter: TAtlasTodoFilter);
var
  Project: IOTAProject;
  Name, Described: string;
  Filter: TAtlasTodoFilter;
begin
  // Abgeschaltet: auch über Tastenkürzel oder „Ausprobieren“ nichts tun.
  if (Manager = nil) or not TAtlasIdeSettings.Current.TodoList then
    Exit;
  Project := GetActiveProject;
  if (Project = nil) or (Project.FileName = '') then
  begin
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.TodoListNoProject));
    Exit;
  end;
  Name := ChangeFileExt(ExtractFileName(Project.FileName), '');
  Filter := AFilter.Trimmed;
  Described := Filter.Describe;
  if Manager.ActiveSession = nil then
  begin
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.TodoListFailed));
    Exit;
  end;
  if not Manager.RunCommandAsync(TodosCommand, TodoArguments(Project.FileName, Filter), 120000,
    procedure(AAnswer: string)
    var
      Answer: string;
    begin
      Answer := AAnswer;
      TAtlasMainThread.Queue(TAtlasFeature.Menu,
        procedure
        begin
          TAtlasGuard.Run(TAtlasFeature.Palette,
            procedure
            var
              Entries: TArray<TAtlasResultEntry>;
              Choices: TAtlasTodoChoices;
            begin
              if not TAtlasTodoList.Entries(Answer, Entries) then
              begin
                GuardWarning(TAtlasStrings.Text(TAtlasTextId.TodoListFailed));
                Exit;
              end;
              // Vorschläge nur aus der ungefilterten Liste: sonst schrumpfen sie mit jedem Filter.
              if Filter.IsEmpty and TAtlasTodoList.Choices(Answer, Choices) then
                TodoChoices := Choices;
              if (Length(Entries) = 0) and (Described = '') then
                GuardWarning(TAtlasStrings.Fmt(TAtlasTextId.TodoListEmpty, [Name]))
              else if Length(Entries) = 0 then
                GuardWarning(TAtlasStrings.Fmt(TAtlasTextId.TodoListNoMatch, [Name, Described]))
              else if Described = '' then
                TAtlasIdeResultsWindow.ShowEntries(TAtlasStrings.Fmt(TAtlasTextId.TodoListTitle,
                  [Name, Length(Entries)]), Entries)
              else
                TAtlasIdeResultsWindow.ShowEntries(TAtlasStrings.Fmt(TAtlasTextId.TodoListFilteredTitle,
                  [Name, Described, Length(Entries)]), Entries);
            end);
        end);
    end) then
    // Ein Befehl im Hintergrund läuft schon (etwa die Werte nach einem Build): später noch einmal.
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.TodoListBusy));
end;

/// <summary>Filterdialog der TODO-Liste (#68) mit dem letzten Filter; „Anzeigen“ fragt mit dem neuen Filter.</summary>
procedure FilterProjectTodos;
var
  Filter: TAtlasTodoFilter;
begin
  if not TAtlasIdeSettings.Current.TodoList then
    Exit;
  Filter := TodoFilter;
  if not TAtlasTodoFilterDialog.Execute(TodoChoices, Filter) then
    Exit;
  TodoFilter := Filter;
  ProjectTodos(Filter);
end;

/// <summary>„Symbol umbenennen…“ (#397) aus Menü und Palette.</summary>
procedure RenameSymbol;
begin
  if Manager = nil then
    Exit;
  TAtlasIdeRename.Execute(Manager.ActiveSession,
    TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits),
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end);
end;

/// <summary>„Eigenschaftsregeln anwenden“ (#309) für Formular, Projekt oder Projektgruppe.</summary>
procedure ApplyDfmPropertyRules(AScope: TAtlasDfmRulesScope);
begin
  if (Manager = nil) or not TAtlasIdeSettings.Current.DfmPropertyRules then
    Exit;
  TAtlasIdeDfmPropertyRules.Execute(Manager.ActiveSession, AScope,
    TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits),
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end);
end;

function DfmPropertyRulesVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DfmPropertyRules;
end;

// Sichtbarkeit von Palettenbefehlen nach Einstellung.
function BaselineUpdateVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.BaselineUpdate;
end;

function BookmarksNamedVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.BookmarksNamed;
end;

function QuickBookmarksVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.QuickBookmarks;
end;

function BookmarksWindowVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.BookmarksNamed or TAtlasIdeSettings.Current.QuickBookmarks;
end;

function CompilerSwitchesVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.BuildCompilerSwitches;
end;

function DebugExceptionsVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugExceptionHistory;
end;

function DebugEvaluateVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugEvaluateWindow;
end;

function DataFlowVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DataFlow;
end;

function DebugExceptionBarVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugExceptionHistory and TAtlasIdeSettings.Current.DebugExceptionBanner;
end;

function ProblemsWindowVisible: Boolean;
begin
  Result := TAtlasIdeProblems.Enabled;
end;

function QuickOpenVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.QuickOpen;
end;

function NavHistoryVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.NavHistory;
end;

function ImpactVisible: Boolean;
begin
  Result := TAtlasIdeImpact.Enabled;
end;

function PeekVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Peek;
end;

function OutlineVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Outline;
end;

/// <summary>Antwort von RunServerCommandAsync als JSON-Text ('' ohne Antwort) an ADone; eigene Routine, damit die
/// anonyme Methode nur ADone einfängt.</summary>
function HotspotsAnswer(const ADone: TProc<string>): TProc<TJSONValue>;
var
  mDone: TProc<string>;
begin
  mDone := ADone;
  Result :=
    procedure(AValue: TJSONValue)
    begin
      if AValue = nil then
        mDone('')
      else
        mDone(AValue.ToJSON);
    end;
end;

function ArchitectureVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.ArchitectureEnabled;
end;

function HotspotsVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.HotspotsEnabled;
end;

function UnitRelationsVisible: Boolean;
begin
  Result := TAtlasIdeUnitRelations.Enabled;
end;

function SymbolPathVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.SymbolPath;
end;

function JumpToMatchVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.JumpToMatch;
end;

procedure JumpToMatch;
begin
  TAtlasIdeEditorCommands.JumpToMatch(False);
end;

procedure SelectToMatch;
begin
  TAtlasIdeEditorCommands.JumpToMatch(True);
end;

function ChangesVisible: Boolean;
begin
  Result := TAtlasIdeLineChanges.Enabled;
end;

procedure NextChange;
begin
  TAtlasIdeLineChanges.GoToChange(True);
end;

procedure PreviousChange;
begin
  TAtlasIdeLineChanges.GoToChange(False);
end;

function MoveLinesVisible: Boolean;
begin
  Result := TAtlasIdeLineMove.Enabled;
end;

procedure MoveLinesUp;
begin
  TAtlasIdeLineMove.Run(TAtlasLineMoveKind.MoveUp);
end;

procedure MoveLinesDown;
begin
  TAtlasIdeLineMove.Run(TAtlasLineMoveKind.MoveDown);
end;

procedure DuplicateLinesUp;
begin
  TAtlasIdeLineMove.Run(TAtlasLineMoveKind.DuplicateUp);
end;

procedure DuplicateLinesDown;
begin
  TAtlasIdeLineMove.Run(TAtlasLineMoveKind.DuplicateDown);
end;

function CompleteStatementVisible: Boolean;
begin
  Result := TAtlasIdeStatementCompletion.Enabled;
end;

function FormatCodeVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.FormatCode;
end;

procedure FormatCode;
begin
  TAtlasIdeEditorCommands.FormatCode;
end;

function ToggleBlockCommentVisible: Boolean;
begin
  Result := TAtlasIdeBlockComment.Enabled;
end;

procedure ToggleBlockComment;
begin
  TAtlasIdeBlockComment.Run;
end;

function NewLineAroundVisible: Boolean;
begin
  Result := TAtlasIdeNewLine.Enabled;
end;

procedure NewLineBelow;
begin
  TAtlasIdeNewLine.Run(TAtlasNewLineDirection.Below);
end;

procedure NewLineAbove;
begin
  TAtlasIdeNewLine.Run(TAtlasNewLineDirection.Above);
end;

function UnwrapVisible: Boolean;
begin
  Result := TAtlasIdeUnwrap.Enabled;
end;

procedure Unwrap;
begin
  TAtlasIdeUnwrap.Run;
end;

function StepIntoTargetVisible: Boolean;
begin
  Result := TAtlasIdeStepInto.Enabled;
end;

procedure StepIntoTarget;
begin
  TAtlasIdeStepInto.Run;
end;

function BreakOnNextEventVisible: Boolean;
begin
  Result := TAtlasIdeEventBreak.Enabled;
end;

procedure BreakOnNextEvent;
begin
  TAtlasIdeEventBreak.Run;
end;

function StepFilterRunning: Boolean;
begin
  Result := TAtlasIdeDebugStepFilter.Started;
end;

function ExpressionTypeVisible: Boolean;
begin
  Result := TAtlasIdeExpressionType.Enabled;
end;

procedure ShowExpressionType;
begin
  TAtlasIdeExpressionType.Run;
end;

function MethodOrderVisible: Boolean;
begin
  Result := TAtlasIdeMethodPlacement.Enabled;
end;

procedure ArrangeMethods;
begin
  TAtlasIdeMethodPlacement.Run;
end;

function SafeDeleteVisible: Boolean;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := Settings.Enabled and Settings.SafeDelete;
end;

procedure SafeDelete;
begin
  TAtlasIdeEditorCommands.SafeDelete;
end;

procedure CompleteStatement;
begin
  TAtlasIdeStatementCompletion.Run;
end;

function MultiCursorVisible: Boolean;
begin
  Result := TAtlasIdeMultiCursor.Enabled;
end;

procedure MultiCursorNext;
begin
  TAtlasIdeMultiCursor.TryNext;
end;

procedure MultiCursorLineEnds;
begin
  TAtlasIdeMultiCursor.TryLineEnds;
end;

procedure MultiCursorAbove;
begin
  TAtlasIdeMultiCursor.TryVertical(True);
end;

procedure MultiCursorBelow;
begin
  TAtlasIdeMultiCursor.TryVertical(False);
end;

function BreadcrumbsVisible: Boolean;
begin
  Result := TAtlasIdeBreadcrumbs.Enabled;
end;

function DiagnosticModeVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DiagnosticMode;
end;

function GenerateMenuVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.GenerateMenu;
end;

function SearchReplaceVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.SearchReplace;
end;

function MetricsReportVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.MetricsReport;
end;

function NotesVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Notes;
end;

/// <summary>Befehl „Aufrufdiagramm“ (#1122) sichtbar?</summary>
function CallDiagramVisible: Boolean;
begin
  Result := TAtlasIdeResults.CallDiagramAllowed;
end;

/// <summary>Export, Import und Zurücksetzen der Einstellungen (#723): settings.exportImport.</summary>
function SettingsTransferVisible: Boolean;
begin
  Result := TAtlasIdeSettingsTransfer.Visible;
end;

function TodoListVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TodoList;
end;

function NotificationsVisible: Boolean;
begin
  Result := TAtlasIdeNotifications.Active;
end;

function TeamFileVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TeamFile;
end;

/// <summary>Einstellungen des Release-Build-Wächters (#533) aus den aktuellen Plugin-Einstellungen.</summary>
function ReleaseSettings: TAtlasReleaseSettings;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := TAtlasReleaseSettings.Create(Settings.ReleaseGuard, Settings.BuildGate, Settings.ReleaseConfigs,
    Settings.ReleaseChecks);
end;

/// <summary>Einstellungen der Prüfung vor dem Kompilieren (#529) aus den aktuellen Plugin-Einstellungen.</summary>
function GateSettings: TAtlasGateSettings;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := TAtlasGateSettings.Create(Settings.BuildGate, Settings.BuildGateTimeoutMs);
end;

/// <summary>Fragt den laufenden Server (#530), welche Meldungen eines Builds von AProjectFile in der Basislinie
/// stehen; ohne laufenden Server nicht (False), dann zählt alles.</summary>
function BaselineClassifier(const AProjectFile: string): TAtlasBuildClassify;
var
  FileName: string;
begin
  FileName := AProjectFile;
  Result :=
    function(const AMessages: TArray<TAtlasCompilerMessage>; const ADone: TAtlasBuildBaselined): Boolean
    var
      Count: Integer;
      Done: TAtlasBuildBaselined;
    begin
      // Den Server startet Atlas dafür nicht (#874).
      Result := (Manager <> nil) and (Manager.RunningSession <> nil);
      if not Result then
        Exit;
      Count := Length(AMessages);
      Done := ADone;
      Manager.RunServerCommandAsync(TAtlasBuildVerdicts.ClassifyCommand,
        TAtlasBuildVerdicts.Arguments(TLspSession.PathToUri(FileName), AMessages),
        TAtlasBuildVerdicts.ClassifyTimeoutMs,
        procedure(AAnswer: TJSONValue)
        begin
          // nil (Zeitlimit, älterer Server): BaselinedOf liefert nil, dann zählt alles.
          Done(TAtlasBuildVerdicts.BaselinedOf(AAnswer, Count));
        end);
    end;
end;

/// <summary>Folgen eines bewerteten Builds (#530): Zusammenfassung, Eintrag der Benachrichtigungszentrale (#601) und
/// Tests nach dem Build (#69), alle nach derselben Bewertung.</summary>
procedure BuildEvaluated(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
  const AVerdict: TAtlasBuildVerdict);
var
  Messages: TArray<TAtlasCompilerMessage>;
  Project: TAtlasCompileProject;
  Verdict: TAtlasBuildVerdict;
begin
  Messages := AMessages;
  Project := AProject;
  Verdict := AVerdict;
  TAtlasGuard.Run(TAtlasFeature.Build,
    procedure
    begin
      TAtlasIdeBuildSummary.Report(Messages, Project, Verdict, TAtlasIdeSettings.Current.BuildSummary);
    end);
  if Notifications <> nil then
    TAtlasGuard.Run(TAtlasFeature.Notifications,
      procedure
      begin
        Notifications.BuildEvaluated(Messages, Project, Verdict);
      end);
  if Tests <> nil then
    TAtlasGuard.Run(TAtlasFeature.Build,
      procedure
      begin
        Tests.BuildFinished(Project, Verdict.Effective);
      end);
end;

/// <summary>Bewertet einen Build des Benutzers mit lesbaren Meldungen (#530): Basislinie über den Server,
/// build.zeroHints und build.warningsAsErrors; dann BuildEvaluated (bei Server-Frage später im Hauptthread).
/// </summary>
procedure EvaluateBuild(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
  ASucceeded: Boolean);
var
  Settings: TAtlasPluginSettings;
  Messages: TArray<TAtlasCompilerMessage>;
  Project: TAtlasCompileProject;
begin
  Settings := TAtlasIdeSettings.Current;
  if BuildSummary <> nil then
    BuildSummary.Remember(AProject.FileName, AMessages);
  Messages := AMessages;
  Project := AProject;
  TAtlasBuildVerdicts.Run(Messages, ASucceeded,
    TAtlasBuildVerdictSettings.Create(Settings.BuildZeroHints, Settings.BuildWarningsAsErrors),
    BaselineClassifier(Project.FileName),
    procedure(const AVerdict: TAtlasBuildVerdict)
    begin
      BuildEvaluated(Messages, Project, AVerdict);
    end);
end;

function ReleaseGuardVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.ReleaseGuard;
end;

/// <summary>Befehle der Tests (#69) sichtbar?</summary>
function TestsVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TestRun and (Tests <> nil);
end;

/// <summary>Befehl „Test am Cursor debuggen“ (#585) sichtbar?</summary>
function TestDebugVisible: Boolean;
begin
  Result := TAtlasTestDebug.DebugWanted(TAtlasIdeSettings.Current) and (TestDebugger <> nil);
end;

/// <summary>Befehl „Startprofil: …“ (#575) sichtbar?</summary>
function StartProfilesVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.StartProfiles and TAtlasIdeStartProfiles.Started;
end;

/// <summary>Befehle der Projektaufgaben (#900) sichtbar?</summary>
function TasksVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TasksEnabled and (ProjectTasks <> nil);
end;

/// <summary>AProc der Projektaufgaben (#900), abgesichert; ohne Läufer nichts.</summary>
function TasksCommand(const AProc: TProc<TAtlasIdeTasks>): TProc;
begin
  Result :=
    procedure
    begin
      if ProjectTasks <> nil then
        TAtlasGuard.Run(TAtlasFeature.Tasks,
          procedure
          begin
            AProc(ProjectTasks);
          end);
    end;
end;

procedure ToggleDebugJustMyCode;
begin
  TAtlasIdeDebugOwnCode.ToggleSetting(
    procedure(AText: string)
    begin
      MessageLine(AText);
    end);
end;

procedure RegisterPalette;

  procedure Add(const AId: string; ATextId: TAtlasTextId; const AProc: TProc); overload;
  begin
    Palette.RegisterCommand(AId, TAtlasStrings.Text(ATextId), '', AProc);
  end;

  /// <summary>Befehl nur sichtbar, solange AVisible True liefert (#520).</summary>
  procedure Add(const AId: string; ATextId: TAtlasTextId; const AProc: TProc; const AVisible: TFunc<Boolean>);
    overload;
  begin
    Palette.RegisterCommand(AId, TAtlasStrings.Text(ATextId), '', AProc, AVisible);
  end;

  function Hierarchy(ADirection: TAtlasHierarchyDirection): TProc;
  begin
    Result :=
      procedure
      begin
        TAtlasIdeResults.ShowHierarchy(ADirection);
      end;
  end;

  function DataFlow(ADirection: TAtlasDataFlowDirection): TProc;
  begin
    Result :=
      procedure
      begin
        TAtlasIdeResults.ShowDataFlow(ADirection);
      end;
  end;

  /// <summary>AProc abgesichert je Feature (#493).</summary>
  function Guarded(AFeature: TAtlasFeature; const AProc: TProc): TProc;
  begin
    Result :=
      procedure
      begin
        TAtlasGuard.Run(AFeature, AProc);
      end;
  end;

begin
  Palette := TAtlasIdePalette.Create;
  Add('Atlas.Log', TAtlasTextId.PaletteLog,
    procedure
    var
      Actions: IOTAActionServices;
    begin
      if Supports(BorlandIDEServices, IOTAActionServices, Actions) and FileExists(TAtlasCodeInsightManager.DiagnoseLog) then
        Actions.OpenFile(TAtlasCodeInsightManager.DiagnoseLog);
    end);
  Add('Atlas.Rename', TAtlasTextId.RenameMenu, RenameSymbol);
  // Ergebnisfenster (#400).
  Add('Atlas.References', TAtlasTextId.MenuReferences, TAtlasIdeResults.FindReferences);
  Add('Atlas.Implementations', TAtlasTextId.MenuImplementations, TAtlasIdeResults.FindImplementations);
  Add('Atlas.SymbolSearch', TAtlasTextId.MenuSymbolSearch, TAtlasIdeResults.SearchSymbol);
  // Auswirkungsanalyse (#1120); nur sichtbar, solange navigation.impact an ist.
  Add('Atlas.Impact', TAtlasTextId.ImpactCommand, Guarded(TAtlasFeature.Results, TAtlasIdeImpact.ShowAtCursor),
    ImpactVisible);
  // Schnell öffnen (#503); nur sichtbar, solange quickOpen.enabled an ist.
  Add('Atlas.QuickOpen', TAtlasTextId.QuickOpenTitle, Guarded(TAtlasFeature.Palette, TAtlasIdeQuickOpen.Show),
    QuickOpenVisible);
  // Navigationsverlauf über Dateien (#504); nur sichtbar, solange navHistory.enabled an ist.
  Add('Atlas.NavBack', TAtlasTextId.NavBackCommand, Guarded(TAtlasFeature.NavHistory, TAtlasIdeNavHistory.GoBack),
    NavHistoryVisible);
  Add('Atlas.NavForward', TAtlasTextId.NavForwardCommand,
    Guarded(TAtlasFeature.NavHistory, TAtlasIdeNavHistory.GoForward), NavHistoryVisible);
  Add('Atlas.LastEdit', TAtlasTextId.NavLastEditCommand,
    Guarded(TAtlasFeature.NavHistory, TAtlasIdeNavHistory.GoLastEdit), NavHistoryVisible);
  Add('Atlas.NavList', TAtlasTextId.NavListCommand,
    Guarded(TAtlasFeature.NavHistory, TAtlasIdeNavHistory.ShowList), NavHistoryVisible);
  Add('Atlas.PeekDefinition', TAtlasTextId.PeekDefinitionCommand,
    Guarded(TAtlasFeature.Peek, TAtlasIdePeek.PeekDefinition), PeekVisible);
  Add('Atlas.PeekReferences', TAtlasTextId.PeekReferencesCommand,
    Guarded(TAtlasFeature.Peek, TAtlasIdePeek.PeekReferences), PeekVisible);
  // Gliederungsfenster (#537); nur sichtbar, solange outline.enabled an ist.
  Add('Atlas.Outline', TAtlasTextId.OutlineCommand,
    Guarded(TAtlasFeature.Outline, TAtlasIdeOutline.ShowWindow), OutlineVisible);
  // Architekturübersicht (#1118); nur sichtbar, solange architecture.enabled an ist.
  Add('Atlas.Architecture', TAtlasTextId.ArchitectureCommand,
    Guarded(TAtlasFeature.Architecture, TAtlasIdeArchitecture.ShowWindow), ArchitectureVisible);
  // Hotspots (#1354); nur sichtbar, solange hotspots.enabled an ist.
  Add('Atlas.Hotspots', TAtlasTextId.HotspotsCommand,
    Guarded(TAtlasFeature.Hotspots, TAtlasIdeHotspots.ShowWindow), HotspotsVisible);
  // Unit-Beziehungen (#593); am selben Schalter wie die Architektur (derselbe Uses-Graph).
  Add('Atlas.UnitRelations', TAtlasTextId.UnitRelationsCommand,
    Guarded(TAtlasFeature.UnitRelations, TAtlasIdeUnitRelations.ShowWindow), UnitRelationsVisible);
  // Kosten einer interface-Änderung (#554): Verwender nach Abschnitt und verschiebbare uses der Unit im Editor,
  // dazu die teuersten Units in der Architekturübersicht.
  Add('Atlas.UnitDependencies', TAtlasTextId.UnitDependenciesCommand,
    Guarded(TAtlasFeature.UnitRelations, TAtlasIdeUnitRelations.ShowCurrent), UnitRelationsVisible);
  Add('Atlas.InterfaceCostRanking', TAtlasTextId.InterfaceCostRankingCommand,
    Guarded(TAtlasFeature.Architecture, TAtlasIdeArchitecture.ShowRanking), ArchitectureVisible);
  // Weg zwischen Symbolen (#1117); nur sichtbar, solange navigation.symbolPath an ist.
  Add('Atlas.SymbolPath', TAtlasTextId.SymbolPathCommand,
    Guarded(TAtlasFeature.SymbolPath, TAtlasIdeSymbolPath.ShowDialog), SymbolPathVisible);
  // Brotkrumenleiste (#590): Fokus auf das letzte Glied; nur sichtbar, solange editor.breadcrumbs an ist.
  Add('Atlas.Breadcrumbs', TAtlasTextId.BreadcrumbsCommand,
    Guarded(TAtlasFeature.Breadcrumbs, TAtlasIdeBreadcrumbs.Focus), BreadcrumbsVisible);
  // Atlas-Editorleiste (#1101): Abschnittssprünge, Rücksprung und „Methode suchen“ auch ohne Leiste.
  Add('Atlas.GotoInterface', TAtlasTextId.GotoInterfaceCommand,
    Guarded(TAtlasFeature.EditorToolbar, TAtlasIdeEditorToolbar.GotoInterface));
  Add('Atlas.GotoImplementation', TAtlasTextId.GotoImplementationCommand,
    Guarded(TAtlasFeature.EditorToolbar, TAtlasIdeEditorToolbar.GotoImplementation));
  Add('Atlas.GotoUses', TAtlasTextId.GotoUsesCommand,
    Guarded(TAtlasFeature.EditorToolbar, TAtlasIdeEditorToolbar.GotoUses));
  Add('Atlas.GotoInitialization', TAtlasTextId.GotoInitializationCommand,
    Guarded(TAtlasFeature.EditorToolbar, TAtlasIdeEditorToolbar.GotoInitialization));
  Add('Atlas.ReturnFromSection', TAtlasTextId.ReturnFromSectionCommand,
    Guarded(TAtlasFeature.EditorToolbar, TAtlasIdeEditorToolbar.ReturnFromSection));
  Add('Atlas.FindMethod', TAtlasTextId.FindMethodCommand,
    Guarded(TAtlasFeature.EditorToolbar, TAtlasIdeEditorToolbar.FindMethod));
  Add('Atlas.EditorToolbarCustomize', TAtlasTextId.EditorToolbarCustomizeCommand,
    Guarded(TAtlasFeature.EditorToolbar, TAtlasIdeEditorToolbar.Customize));
  // Sprung zum Gegenstück (#635); nur sichtbar, solange keys.jumpToMatch an ist.
  Add('Atlas.JumpToMatch', TAtlasTextId.JumpToMatchCommand, Guarded(TAtlasFeature.EditorCommands, JumpToMatch),
    JumpToMatchVisible);
  Add('Atlas.JumpToMatchSelect', TAtlasTextId.JumpToMatchSelectCommand,
    Guarded(TAtlasFeature.EditorCommands, SelectToMatch), JumpToMatchVisible);
  // Nächste/vorherige Änderung gegenüber dem Repository (#507); nur sichtbar, solange editor.gitGutter an ist.
  Add('Atlas.NextChange', TAtlasTextId.NextChangeCommand, Guarded(TAtlasFeature.LineChanges, NextChange),
    ChangesVisible);
  Add('Atlas.PreviousChange', TAtlasTextId.PreviousChangeCommand,
    Guarded(TAtlasFeature.LineChanges, PreviousChange), ChangesVisible);
  // Zeilen verschieben und duplizieren (#634); nur sichtbar, solange keys.moveLines an ist.
  Add('Atlas.MoveLinesUp', TAtlasTextId.MoveLinesUpCommand, Guarded(TAtlasFeature.EditorCommands, MoveLinesUp),
    MoveLinesVisible);
  Add('Atlas.MoveLinesDown', TAtlasTextId.MoveLinesDownCommand,
    Guarded(TAtlasFeature.EditorCommands, MoveLinesDown), MoveLinesVisible);
  Add('Atlas.DuplicateLinesUp', TAtlasTextId.DuplicateLinesUpCommand,
    Guarded(TAtlasFeature.EditorCommands, DuplicateLinesUp), MoveLinesVisible);
  Add('Atlas.DuplicateLinesDown', TAtlasTextId.DuplicateLinesDownCommand,
    Guarded(TAtlasFeature.EditorCommands, DuplicateLinesDown), MoveLinesVisible);
  // Anweisung vervollständigen (#697).
  Add('Atlas.CompleteStatement', TAtlasTextId.CompleteStatementCommand,
    Guarded(TAtlasFeature.EditorCommands, CompleteStatement), CompleteStatementVisible);
  // Formatieren (#43): ganze Datei bzw. Auswahl.
  Add('Atlas.FormatCode', TAtlasTextId.FormatCodeCommand, Guarded(TAtlasFeature.EditorCommands, FormatCode),
    FormatCodeVisible);
  // Blockkommentar umschalten (#703); nur sichtbar, solange keys.toggleBlockComment an ist.
  Add('Atlas.ToggleBlockComment', TAtlasTextId.ToggleBlockCommentCommand,
    Guarded(TAtlasFeature.EditorCommands, ToggleBlockComment), ToggleBlockCommentVisible);
  // Neue Zeile ober- oder unterhalb (#700); nur sichtbar, solange keys.newLineAround an ist.
  Add('Atlas.NewLineBelow', TAtlasTextId.NewLineBelowCommand, Guarded(TAtlasFeature.EditorCommands, NewLineBelow),
    NewLineAroundVisible);
  Add('Atlas.NewLineAbove', TAtlasTextId.NewLineAboveCommand, Guarded(TAtlasFeature.EditorCommands, NewLineAbove),
    NewLineAroundVisible);
  // Umschließung entfernen (#657); nur sichtbar, solange keys.unwrap an ist.
  Add('Atlas.Unwrap', TAtlasTextId.UnwrapCommand, Guarded(TAtlasFeature.Unwrap, Unwrap), UnwrapVisible);
  // Gezielt hineinspringen (#836); nur sichtbar, solange debug.stepIntoTarget an ist.
  Add('Atlas.StepIntoTarget', TAtlasTextId.StepIntoTargetCommand,
    Guarded(TAtlasFeature.Debugger, StepIntoTarget), StepIntoTargetVisible);
  // Beim nächsten Ereignis anhalten (#856); nur sichtbar, solange debug.breakOnNextEvent an ist.
  Add('Atlas.BreakOnNextEvent', TAtlasTextId.EventBreakCommand,
    Guarded(TAtlasFeature.Debugger, BreakOnNextEvent), BreakOnNextEventVisible);
  // Schrittfilter (#850): Das Fenster schaltet debug.stepFilters selbst, deshalb immer sichtbar; „Trotzdem
  // hineinspringen“ nur, solange der Ablauf läuft.
  Add('Atlas.StepFilters', TAtlasTextId.StepFilterWindowCommand,
    Guarded(TAtlasFeature.Debugger, TAtlasIdeDebugStepFilter.ShowWindow));
  Add('Atlas.StepIntoAnyway', TAtlasTextId.StepFilterStepIntoAnywayCommand,
    Guarded(TAtlasFeature.Debugger, TAtlasIdeDebugStepFilter.StepIntoAnyway), StepFilterRunning);
  Add('Atlas.ExpressionType', TAtlasTextId.ExpressionTypeCommand,
    Guarded(TAtlasFeature.ExpressionType, ShowExpressionType), ExpressionTypeVisible);
  Add('Atlas.MethodOrder', TAtlasTextId.MethodOrderCommand, Guarded(TAtlasFeature.MethodPlacement, ArrangeMethods),
    MethodOrderVisible);
  // Sicher löschen (#716); nur sichtbar, solange keys.safeDelete an ist.
  Add('Atlas.SafeDelete', TAtlasTextId.SafeDeleteCommand, Guarded(TAtlasFeature.EditorCommands, SafeDelete),
    SafeDeleteVisible);
  // Mehrere Einfügemarken (#589).
  Add('Atlas.MultiCursorNext', TAtlasTextId.MultiCursorNextCommand,
    Guarded(TAtlasFeature.MultiCursor, MultiCursorNext), MultiCursorVisible);
  Add('Atlas.MultiCursorLineEnds', TAtlasTextId.MultiCursorLineEndsCommand,
    Guarded(TAtlasFeature.MultiCursor, MultiCursorLineEnds), MultiCursorVisible);
  Add('Atlas.MultiCursorAbove', TAtlasTextId.MultiCursorAboveCommand,
    Guarded(TAtlasFeature.MultiCursor, MultiCursorAbove), MultiCursorVisible);
  Add('Atlas.MultiCursorBelow', TAtlasTextId.MultiCursorBelowCommand,
    Guarded(TAtlasFeature.MultiCursor, MultiCursorBelow), MultiCursorVisible);
  Add('Atlas.Callers', TAtlasTextId.MenuIncoming, Hierarchy(TAtlasHierarchyDirection.Incoming));
  Add('Atlas.Calls', TAtlasTextId.MenuOutgoing, Hierarchy(TAtlasHierarchyDirection.Outgoing));
  // Aufrufdiagramm (#1122); nur sichtbar, solange callHierarchy.diagram an ist.
  Add('Atlas.CallDiagram', TAtlasTextId.CallDiagramCommand,
    Guarded(TAtlasFeature.Results, TAtlasIdeResults.ShowCallDiagram), CallDiagramVisible);
  Add('Atlas.Supertypes', TAtlasTextId.MenuSupertypes, Hierarchy(TAtlasHierarchyDirection.Supertypes));
  Add('Atlas.Subtypes', TAtlasTextId.MenuSubtypes, Hierarchy(TAtlasHierarchyDirection.Subtypes));
  // Datenfluss (#690); nur sichtbar, solange navigation.dataFlow an ist.
  Add('Atlas.DataFlowSources', TAtlasTextId.MenuDataFlowSources,
    Guarded(TAtlasFeature.Results, DataFlow(TAtlasDataFlowDirection.Sources)), DataFlowVisible);
  Add('Atlas.DataFlowTargets', TAtlasTextId.MenuDataFlowTargets,
    Guarded(TAtlasFeature.Results, DataFlow(TAtlasDataFlowDirection.Targets)), DataFlowVisible);
  Add('Atlas.ResultsWindow', TAtlasTextId.MenuResultsWindow, TAtlasIdeResults.ShowWindow);
  // Atlas-Änderungen über mehrere Dateien (#721).
  Add('Atlas.UndoChange', TAtlasTextId.UndoMenu, TAtlasIdeUndo.UndoLast);
  Add('Atlas.RedoChange', TAtlasTextId.RedoMenu, TAtlasIdeUndo.RedoLast);
  Add('Atlas.ChangeList', TAtlasTextId.UndoListMenu, TAtlasIdeUndo.ShowList);
  // Persönliche Notizen (#545); nur sichtbar, solange die Einstellung an ist.
  Add('Atlas.NoteAdd', TAtlasTextId.NotesMenuAdd,
    Guarded(TAtlasFeature.Notes, TAtlasIdeNotes.AddOrEdit), NotesVisible);
  Add('Atlas.NoteDelete', TAtlasTextId.NotesMenuDelete,
    Guarded(TAtlasFeature.Notes, TAtlasIdeNotes.DeleteAtLine), NotesVisible);
  Add('Atlas.NoteList', TAtlasTextId.NotesMenuList,
    Guarded(TAtlasFeature.Notes, TAtlasIdeNotes.ShowList), NotesVisible);
  // Benannte Lesezeichen (#622); nur sichtbar, solange bookmarks.named an ist.
  Add('Atlas.BookmarkAdd', TAtlasTextId.BookmarksMenuAdd,
    Guarded(TAtlasFeature.Bookmarks, TAtlasIdeBookmarks.AddBookmark), BookmarksNamedVisible);
  Add('Atlas.BookmarkGoTo', TAtlasTextId.BookmarksMenuGoTo,
    Guarded(TAtlasFeature.Bookmarks, TAtlasIdeBookmarks.GoToBookmark), BookmarksNamedVisible);
  Add('Atlas.BookmarkWindow', TAtlasTextId.BookmarksMenuWindow,
    Guarded(TAtlasFeature.Bookmarks, TAtlasIdeBookmarks.ShowWindow), BookmarksWindowVisible);
  // Schnelle Lesezeichen (#1104); nur sichtbar, solange bookmarks.quick an ist.
  Add('Atlas.QuickBookmarkToggle', TAtlasTextId.QuickBookmarkToggleCommand,
    Guarded(TAtlasFeature.QuickBookmarks, TAtlasIdeBookmarks.QuickToggle), QuickBookmarksVisible);
  Add('Atlas.NextBookmark', TAtlasTextId.NextBookmarkCommand,
    Guarded(TAtlasFeature.QuickBookmarks, TAtlasIdeBookmarks.NextBookmark), QuickBookmarksVisible);
  Add('Atlas.PreviousBookmark', TAtlasTextId.PreviousBookmarkCommand,
    Guarded(TAtlasFeature.QuickBookmarks, TAtlasIdeBookmarks.PreviousBookmark), QuickBookmarksVisible);
  // Wirksame Compiler-Schalter (#558); nur sichtbar, solange build.compilerSwitches an ist.
  Add('Atlas.CompilerSwitches', TAtlasTextId.CompilerSwitchesCommand,
    Guarded(TAtlasFeature.Build, TAtlasIdeCompilerSwitches.ShowWindow), CompilerSwitchesVisible);
  // Exception-Verlauf beim Debuggen (#517); nur sichtbar, solange debug.exceptionHistory an ist.
  Add('Atlas.DebugExceptions', TAtlasTextId.DebugExceptionsCommand,
    Guarded(TAtlasFeature.Debugger, TAtlasIdeDebugExceptions.ShowWindow), DebugExceptionsVisible);
  // Fenster „Auswerten“ (#784) und der Dialog der IDE daneben; nur sichtbar, solange debug.evaluateWindow an ist.
  Add('Atlas.DebugEvaluate', TAtlasTextId.DebugEvaluateCommand,
    Guarded(TAtlasFeature.Debugger, TAtlasIdeDebugEvaluate.ShowWindow), DebugEvaluateVisible);
  Add('Atlas.DebugEvaluateIdeDialog', TAtlasTextId.DebugEvaluateIdeDialogCommand,
    Guarded(TAtlasFeature.Debugger, TAtlasIdeDebugEvaluate.OpenIdeDialog), DebugEvaluateVisible);
  // Nur eigener Code beim Debuggen (#578): schaltet debug.justMyCode um, deshalb immer sichtbar.
  Add('Atlas.DebugJustMyCode', TAtlasTextId.DebugJustMyCodeCommand,
    Guarded(TAtlasFeature.Debugger, ToggleDebugJustMyCode));
  // Exception-Leiste (#783): Dialog der IDE für die laufende Debug-Sitzung; nur mit debug.exceptionBanner.
  Add('Atlas.DebugExceptionIdeDialog', TAtlasTextId.DebugBannerIdeDialogCommand,
    Guarded(TAtlasFeature.Debugger, TAtlasIdeDebugExceptionBar.ToggleIdeDialog), DebugExceptionBarVisible);
  // Fenster „Atlas-Prüfung“ (#909); nur sichtbar, solange problems.window an ist.
  Add('Atlas.ProblemsWindow', TAtlasTextId.ProblemsWindowCommand,
    Guarded(TAtlasFeature.Problems, TAtlasIdeProblems.ShowWindow), ProblemsWindowVisible);
  // Erzeugen-Menü (#719); nur sichtbar, solange keys.generateMenu an ist.
  Add('Atlas.GenerateMenu', TAtlasTextId.GenerateMenuCommand,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Generate,
        procedure
        begin
          TAtlasIdeGenerate.Show;
        end);
    end, GenerateMenuVisible);
  // Einstellungen exportieren, importieren und zurücksetzen (#723); nur sichtbar mit settings.exportImport.
  Add('Atlas.SettingsExport', TAtlasTextId.SettingsExportCommand,
    Guarded(TAtlasFeature.Settings, TAtlasIdeSettingsTransfer.ExportCommand), SettingsTransferVisible);
  Add('Atlas.SettingsImport', TAtlasTextId.SettingsImportCommand,
    Guarded(TAtlasFeature.Settings, TAtlasIdeSettingsTransfer.ImportCommand), SettingsTransferVisible);
  Add('Atlas.SettingsProfile', TAtlasTextId.SettingsProfileCommand,
    Guarded(TAtlasFeature.Settings, TAtlasIdeSettingsTransfer.ProfileCommand), SettingsTransferVisible);
  Add('Atlas.SettingsReset', TAtlasTextId.SettingsResetCommand,
    Guarded(TAtlasFeature.Settings, TAtlasIdeSettingsTransfer.ResetCommand), SettingsTransferVisible);
  // Editorbefehle (#399).
  Add('Atlas.CodeActions', TAtlasTextId.EditorActions, TAtlasIdeEditorCommands.CodeActions);
  // Ausblenden am Element (#628).
  Add('Atlas.HideElement', TAtlasTextId.HideElementCommand,
    Guarded(TAtlasFeature.Hide, TAtlasIdeHide.ShowForCommand));
  // Nächster/vorheriger Befund (#509).
  Add('Atlas.NextProblem', TAtlasTextId.ProblemNextCommand,
    procedure
    begin
      TAtlasIdeEditorCommands.StepProblem(True);
    end);
  Add('Atlas.PreviousProblem', TAtlasTextId.ProblemPreviousCommand,
    procedure
    begin
      TAtlasIdeEditorCommands.StepProblem(False);
    end);
  Add('Atlas.ExpandSelection', TAtlasTextId.EditorExpand, TAtlasIdeEditorCommands.ExpandSelection);
  Add('Atlas.ShrinkSelection', TAtlasTextId.EditorShrink, TAtlasIdeEditorCommands.ShrinkSelection);
  Add('Atlas.TypeDefinition', TAtlasTextId.EditorTypeDefinition, TAtlasIdeEditorCommands.GoToTypeDefinition);
  Add('Atlas.ToggleMethod', TAtlasTextId.EditorMethodToggle, TAtlasIdeEditorCommands.ToggleMethod);
  Add('Atlas.CopyQualifiedName', TAtlasTextId.EditorCopyQualified,
    procedure
    begin
      TAtlasIdeEditorCommands.CopyQualifiedName(False);
    end);
  Add('Atlas.CopyQualifiedNameParams', TAtlasTextId.EditorCopyQualifiedParams,
    procedure
    begin
      TAtlasIdeEditorCommands.CopyQualifiedName(True);
    end);
  Add('Atlas.SwitchTestUnit', TAtlasTextId.EditorTestUnit, TAtlasIdeEditorCommands.SwitchTestUnit);
  Add('Atlas.UnitSearch', TAtlasTextId.UnitSearchTitle,
    procedure
    begin
      TAtlasIdeUnitSearch.Show;
    end);
  Add('Atlas.UnitSearchIde', TAtlasTextId.UnitSearchIdeDialog,
    procedure
    begin
      TAtlasIdeUnitSearch.ShowIdeDialog;
    end);
  // Unit verwenden und Formulare suchen (#786), mit den Dialogen der IDE als Ausweg.
  Add('Atlas.UseUnit', TAtlasTextId.UseUnitCommand, TAtlasIdeUnitSearch.ShowUseUnit);
  Add('Atlas.UseUnitIde', TAtlasTextId.UseUnitIdeDialog, TAtlasIdeUnitSearch.ShowUseUnitIdeDialog);
  Add('Atlas.Forms', TAtlasTextId.FormsCommand, TAtlasIdeUnitSearch.ShowForms);
  Add('Atlas.FormsIde', TAtlasTextId.FormsIdeDialog, TAtlasIdeUnitSearch.ShowFormsIdeDialog);
  // Atlas-Suche (#877, #878).
  Add('Atlas.Search', TAtlasTextId.SearchCommand, TAtlasIdeSearch.Show);
  Add('Atlas.SearchInMethod', TAtlasTextId.SearchInMethodCommand, TAtlasIdeSearch.ShowInMethod);
  // Ersetzen (#893); nur sichtbar, solange search.replace an ist.
  Add('Atlas.SearchReplace', TAtlasTextId.SearchReplaceCommand, TAtlasIdeSearch.ShowReplace, SearchReplaceVisible);
  Add('Atlas.SearchNext', TAtlasTextId.SearchNextCommand, TAtlasIdeSearch.FindNext);
  Add('Atlas.SearchPrevious', TAtlasTextId.SearchPreviousCommand, TAtlasIdeSearch.FindPrevious);
  Add('Atlas.SearchClear', TAtlasTextId.SearchClearCommand, TAtlasIdeSearch.ClearHighlights);
  Add('Atlas.ResetHistory', TAtlasTextId.PaletteResetHistory, TAtlasIdeHistory.Reset);
  // Metrikbericht des Projekts (#66); nur sichtbar, solange die Einstellung MetricsReport an ist.
  Add('Atlas.MetricsReport', TAtlasTextId.MetricsReportCommand, MetricsReport, MetricsReportVisible);
  // TODO-Liste des Projekts (#68): ohne Filter (alle offenen) und mit Filterdialog; nur sichtbar, solange die
  // Einstellung TodoList an ist.
  Add('Atlas.TodoList', TAtlasTextId.TodoListCommand,
    procedure
    begin
      ProjectTodos(Default(TAtlasTodoFilter));
    end, TodoListVisible);
  Add('Atlas.TodoListFilter', TAtlasTextId.TodoFilterCommand, FilterProjectTodos, TodoListVisible);
  // Baseline des Projekts aktualisieren (#97); nur sichtbar, solange die Einstellung BaselineUpdate an ist.
  Add('Atlas.UpdateBaseline', TAtlasTextId.BaselineUpdateCommand, UpdateBaseline, BaselineUpdateVisible);
  // Compilermeldungen des letzten Builds in die Baseline (#530); mit derselben Einstellung abschaltbar.
  Add('Atlas.CompilerBaseline', TAtlasTextId.CompilerBaselineCommand, AddCompilerMessagesToBaseline,
    BaselineUpdateVisible);
  // Eigenschaftsregeln anwenden (#309); nur sichtbar, solange die Einstellung DfmPropertyRules an ist.
  Add('Atlas.ApplyDfmRulesForm', TAtlasTextId.DfmRulesFormCommand,
    procedure
    begin
      ApplyDfmPropertyRules(TAtlasDfmRulesScope.Form);
    end, DfmPropertyRulesVisible);
  Add('Atlas.ApplyDfmRulesProject', TAtlasTextId.DfmRulesProjectCommand,
    procedure
    begin
      ApplyDfmPropertyRules(TAtlasDfmRulesScope.Project);
    end, DfmPropertyRulesVisible);
  Add('Atlas.ApplyDfmRulesGroup', TAtlasTextId.DfmRulesGroupCommand,
    procedure
    begin
      ApplyDfmPropertyRules(TAtlasDfmRulesScope.Group);
    end, DfmPropertyRulesVisible);
  // Projektdatei .atlas (#486) anlegen bzw. öffnen; nur sichtbar, solange die Einstellung TeamFile an ist.
  Add('Atlas.TeamFile', TAtlasTextId.TeamFileCommand, TAtlasIdeTeamFile.OpenInEditor, TeamFileVisible);
  // Liste der Benachrichtigungen (#601); nur sichtbar, solange die Zentrale an ist.
  Add('Atlas.Notifications', TAtlasTextId.NotificationsCommand,
    Guarded(TAtlasFeature.Notifications, TAtlasIdeNotifications.ShowList), NotificationsVisible);
  // Release-Build prüfen (#533) ohne Build; nur sichtbar, solange die Einstellung ReleaseGuard an ist.
  Add('Atlas.CheckRelease', TAtlasTextId.ReleaseCheckCommand, Guarded(TAtlasFeature.Build,
    procedure
    begin
      TAtlasIdeReleaseGuard.CheckActive(TAtlasIdeProjects.Folder, ReleaseSettings());
    end), ReleaseGuardVisible);
  Add('Atlas.CheckNow', TAtlasTextId.PaletteCheckNow,
    procedure
    begin
      if CheckOnSave <> nil then
        CheckOnSave.CheckNow;
    end);
  Add('Atlas.ExportDiagnostics', TAtlasTextId.DiagExportMenu,
    procedure
    begin
      TAtlasIdeDiagnosticExport.Execute(
        procedure(AText: string)
        begin
          GuardWarning(AText);
        end);
    end);
  Add('Atlas.BugReport', TAtlasTextId.BugReportMenu, CreateBugReport);
  Add('Atlas.ProjectSettings', TAtlasTextId.ProjectSettingsTitle, TAtlasProjectSettings.Execute);
  Add('Atlas.WelcomeStart', TAtlasTextId.MenuWelcomeStart,
    procedure
    begin
      if (Welcome <> nil) and TAtlasIdeSettings.Current.WelcomePage then
        Welcome.ShowStart;
    end);
  Add('Atlas.WelcomeApply', TAtlasTextId.MenuWelcomeApply,
    procedure
    begin
      if (Welcome <> nil) and TAtlasIdeSettings.Current.WelcomePage then
        Welcome.ApplyLayout;
    end);
  Add('Atlas.WelcomeReset', TAtlasTextId.MenuWelcomeReset,
    procedure
    begin
      if Welcome <> nil then
        Welcome.ResetLayout;
    end);
  // Seite anpassen (#767): Bearbeitungsmodus der Willkommensseite bzw. von „Atlas-Start“; sichtbar mit
  // welcomePage.customLayout.
  Add(TAtlasIdeWelcomeLayouts.CommandId, TAtlasTextId.CommandWelcomeCustomize,
    procedure
    begin
      if Welcome <> nil then
        Welcome.Customize;
    end,
    function: Boolean
    begin
      Result := (Welcome <> nil) and Welcome.Layouts.CanCustomize;
    end);
  // Karte „Neu in Atlas“ (#756): wie das Kontextmenü; zeigt die Willkommensseite bzw. „Atlas-Start“.
  Add('Atlas.WhatsNew', TAtlasTextId.WelcomeNewsShowCurrent,
    procedure
    begin
      if (Welcome <> nil) and (Welcome.WhatsNew <> nil) and TAtlasIdeSettings.Current.WelcomePage then
        Welcome.ShowWhatsNew(TAtlasWhatsNewView.Current);
    end);
  // Projekt für Atlas einrichten (#759): hebt „nicht mehr fragen“ auf und zeigt die Karte in „Atlas-Start“.
  Add('Atlas.ProjectSetup', TAtlasTextId.WelcomeSetupCommand,
    procedure
    begin
      if (Welcome = nil) or (Welcome.Setup = nil) or not TAtlasIdeSetup.Active then
        Exit;
      Welcome.Setup.Ask;
      Welcome.ShowStart;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeSetup.Active;
    end);
  Add('Atlas.WhatsNewAll', TAtlasTextId.WelcomeNewsShowAllCommand,
    procedure
    begin
      if (Welcome <> nil) and (Welcome.WhatsNew <> nil) and TAtlasIdeSettings.Current.WelcomePage then
        Welcome.ShowWhatsNew(TAtlasWhatsNewView.All);
    end);
  // Zugang zum Build-Server (#763): für die .atlas des aktiven Projekts; sichtbar mit CiLogin.
  Add('Atlas.CiLogin', TAtlasTextId.CiLoginCommand,
    procedure
    begin
      if (Welcome <> nil) and (Welcome.TestResults <> nil) then
        Welcome.TestResults.EnterCredentialsForActive;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeSettings.Current.CiLogin and (Welcome <> nil) and (Welcome.TestResults <> nil);
    end);
  // Zugang zum Issue-Tracker (#765): für die .atlas des aktiven Projekts; sichtbar mit TrackerLogin.
  Add('Atlas.TrackerLogin', TAtlasTextId.TrackerLoginCommand,
    procedure
    begin
      if (Welcome <> nil) and (Welcome.Issues <> nil) then
        Welcome.Issues.EnterCredentialsForActive;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeSettings.Current.TrackerLogin and (Welcome <> nil) and (Welcome.Issues <> nil);
    end);
  // Issue anlegen (#1268): aus Auswahl bzw. TODO im Editor; sichtbar mit issues.create.
  Add('Atlas.CreateIssue', TAtlasTextId.CreateIssueCommand,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.WelcomePage, TAtlasIdeNewIssue.FromEditor);
    end,
    function: Boolean
    begin
      Result := TAtlasIdeNewIssue.Enabled;
    end);
  // Branch anlegen (#1288): Dialog für die Arbeitskopie des aktiven Projekts, ohne Issue; immer mit Dialog.
  Add('Atlas.CreateBranch', TAtlasTextId.VcsBranchCommand,
    procedure
    var
      mProject: string;
    begin
      mProject := TAtlasIdeProjects.ProjectFileOf(TAtlasIdeTeamFile.ActiveProject);
      if mProject = '' then
      begin
        TAtlasIdeVcs.Report(TAtlasStrings.Text(TAtlasTextId.VcsBranchNoVcs));
        Exit;
      end;
      TAtlasIdeBranching.CreateFor(mProject,
        procedure
        begin
          if (Welcome <> nil) and (Welcome.Projects <> nil) then
            Welcome.Projects.Refresh(mProject);
        end);
    end);
  // Arbeitskopien (#1292): Wurzel, Externals bzw. Submodule des aktiven Projekts; sichtbar mit vcs.externals.show.
  Add('Atlas.WorkingCopies', TAtlasTextId.VcsWorkingCopiesCommand,
    procedure
    var
      mProject: string;
    begin
      mProject := TAtlasIdeProjects.ProjectFileOf(TAtlasIdeTeamFile.ActiveProject);
      if mProject = '' then
      begin
        TAtlasIdeVcs.Report(TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesNoVcs));
        Exit;
      end;
      TAtlasIdeWorkingCopies.ShowFor(mProject,
        procedure
        begin
          if (Welcome <> nil) and (Welcome.Projects <> nil) then
            Welcome.Projects.Refresh(mProject);
        end);
    end,
    function: Boolean
    begin
      Result := TAtlasIdeSettings.Current.VcsExternalsShow;
    end);
  // Issue-Vorschau (#1264): Kennung abfragen und das Issue in „Atlas-Issue“ zeigen; sichtbar mit issues.preview.
  Add('Atlas.IssueShow', TAtlasTextId.IssuePreviewCommand,
    procedure
    begin
      if (Welcome <> nil) and (Welcome.Issues <> nil) then
        Welcome.Issues.ShowPreviewPrompt;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeSettings.Current.IssuesPreview and (Welcome <> nil) and (Welcome.Issues <> nil);
    end);
  // Issues zu dieser Methode (#1275): Issues aus der Zeilenhistorie der Methode bzw. Unit am Cursor; sichtbar mit
  // issues.blameLinks.
  Add('Atlas.BlameIssues', TAtlasTextId.BlameIssuesCommand,
    procedure
    begin
      if BlameIssues <> nil then
        TAtlasGuard.Run(TAtlasFeature.BlameIssues, BlameIssues.ShowScope);
    end,
    function: Boolean
    begin
      Result := TAtlasIdeBlameLinks.Enabled and (BlameIssues <> nil);
    end);
  // Offene Zeitbuchungen (#1267): sichtbar mit issues.timeTracking.
  Add('Atlas.IssueTimeOpen', TAtlasTextId.TimeMenuOpen,
    procedure
    begin
      if (Welcome <> nil) and (Welcome.Issues <> nil) then
        Welcome.Issues.ShowTimeOpen;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeSettings.Current.IssuesTimeTracking and (Welcome <> nil) and (Welcome.Issues <> nil);
    end);
  // Atlas-Board (#1272): Sprint als Spalten nach Zustand; sichtbar mit issues.board.
  Add('Atlas.Board', TAtlasTextId.BoardCommand,
    procedure
    begin
      if (Welcome <> nil) and (Welcome.Issues <> nil) and (Welcome.Issues.Board <> nil) then
        Welcome.Issues.Board.Show;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeSettings.Current.IssuesBoard and (Welcome <> nil) and (Welcome.Issues <> nil);
    end);
  // An Issue anhängen (#1276): Bildschirmfoto, Formular, Log, Debug-Notiz; sichtbar mit issues.attach.
  Add('Atlas.IssueAttach', TAtlasTextId.AttachCommand,
    procedure
    begin
      if (Welcome <> nil) and (Welcome.Issues <> nil) then
        Welcome.Issues.AttachPrompt;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeSettings.Current.IssuesAttach and (Welcome <> nil) and (Welcome.Issues <> nil);
    end);
  // DUnitX-Tests (#69): sichtbar, solange TestRun an ist und der Läufer läuft (auch später gestartet).
  Add('Atlas.RunTests', TAtlasTextId.TestsRunCommand,
    procedure
    begin
      if Tests <> nil then
        TAtlasGuard.Run(TAtlasFeature.Build, Tests.RunAll);
    end, TestsVisible);
  Add('Atlas.RunFailedTests', TAtlasTextId.TestsRunFailedCommand,
    procedure
    begin
      if Tests <> nil then
        TAtlasGuard.Run(TAtlasFeature.Build, Tests.RunFailed);
    end, TestsVisible);
  // Einzelner Test am Cursor (#585): ausführen (mit TestRun) und im Debugger (mit TestDebug).
  Add('Atlas.RunTest', TAtlasTextId.TestsRunHereCommand,
    procedure
    begin
      if TestDebugger <> nil then
        TAtlasGuard.Run(TAtlasFeature.Build, TestDebugger.RunAtCursor);
    end, TestsVisible);
  Add('Atlas.DebugTest', TAtlasTextId.TestsDebugCommand,
    procedure
    begin
      if TestDebugger <> nil then
        TAtlasGuard.Run(TAtlasFeature.Build, TestDebugger.DebugAtCursor);
    end, TestDebugVisible);
  // Projektaufgaben (#900): sichtbar, solange tasks.enabled an ist und der Läufer läuft.
  Add('Atlas.RunTask', TAtlasTextId.TasksRunCommand,
    TasksCommand(
      procedure(ATasks: TAtlasIdeTasks)
      begin
        ATasks.Choose;
      end), TasksVisible);
  Add('Atlas.RunChecks', TAtlasTextId.TasksRunChecksCommand,
    TasksCommand(
      procedure(ATasks: TAtlasIdeTasks)
      begin
        ATasks.RunChecks;
      end), TasksVisible);
  Add('Atlas.RepeatTask', TAtlasTextId.TasksRepeatCommand,
    TasksCommand(
      procedure(ATasks: TAtlasIdeTasks)
      begin
        ATasks.RepeatLast;
      end), TasksVisible);
  Add('Atlas.CancelTasks', TAtlasTextId.TasksCancelCommand,
    TasksCommand(
      procedure(ATasks: TAtlasIdeTasks)
      begin
        ATasks.CancelAll;
      end), TasksVisible);
  Add('Atlas.TasksOutput', TAtlasTextId.TasksOutputCommand,
    TasksCommand(
      procedure(ATasks: TAtlasIdeTasks)
      begin
        ATasks.ToggleOutput;
      end), TasksVisible);
  Add('Atlas.TasksFindings', TAtlasTextId.TasksFindingsCommand,
    TasksCommand(
      procedure(ATasks: TAtlasIdeTasks)
      begin
        ATasks.ChooseFindings;
      end), TasksVisible);
  // Startprofile (#575): Auswahl für das aktive Projekt; sichtbar, solange StartProfiles an ist.
  Add('Atlas.StartProfile', TAtlasTextId.StartProfilesCommand,
    Guarded(TAtlasFeature.Build, TAtlasIdeStartProfiles.ShowPicker), StartProfilesVisible);
  // Künstlicher Hänger für den Einfrier-Wächter (#501): nur im Diagnosemodus (#479, Code-Review S-07).
  // Bereich „Weiterarbeiten“ (#755): obersten Arbeitsstand fortsetzen.
  Add('Atlas.Continue', TAtlasTextId.WelcomeContinueCommand,
    procedure
    begin
      if (Welcome <> nil) and (Welcome.ContinueWork <> nil) then
        Welcome.ContinueWork.ResumeLatest;
    end);
  Add('Atlas.HangTest', TAtlasTextId.SettingsHangTest,
    procedure
    var
      Activity: IInterface;
    begin
      // Auch über Verlauf oder Taste nicht außerhalb des Diagnosemodus.
      if not TAtlasIdeSettings.Current.DiagnosticMode then
        Exit;
      Activity := TAtlasActivity.Scope('Wächter-Test');
      Sleep(1000);
    end, DiagnosticModeVisible);
end;

/// <summary>„Protokoll öffnen“ (#591): Diagnoseprotokoll, sonst das Protokoll der Sicherung.</summary>
procedure OpenLog;
var
  Actions: IOTAActionServices;
  FileName: string;
begin
  FileName := TAtlasCodeInsightManager.DiagnoseLog;
  if not FileExists(FileName) and (TAtlasGuard.RotatingLog <> nil) then
    FileName := TAtlasGuard.RotatingLog.FileName;
  if FileExists(FileName) and Supports(BorlandIDEServices, IOTAActionServices, Actions) then
    Actions.OpenFile(FileName);
end;

/// <summary>Ausgelöste Sicherung (#493) als Eintrag in der Benachrichtigungszentrale mit „Wieder einschalten“ und
/// „Protokoll öffnen“ (atlas.log mit Stacktrace): Der Fehler soll auffallen und behoben werden, statt still eine
/// Funktion zu kosten. Aus jedem Thread; die Aktionen laufen im Hauptthread.</summary>
procedure GuardTripped(AFeature: TAtlasFeature; const AMessage: string);
var
  Feature: TAtlasFeature;
  Enable, Log: TAtlasNotificationAction;
begin
  Feature := AFeature;
  Enable.Caption := TAtlasStrings.Text(TAtlasTextId.FuseTrippedEnable);
  Enable.Run :=
    procedure
    begin
      TAtlasGuard.Enable(Feature);
      TAtlasGuard.Log(TAtlasGuard.FeatureName(Feature) + ': aus der Benachrichtigung wieder eingeschaltet');
    end;
  Log.Caption := TAtlasStrings.Text(TAtlasTextId.FuseTrippedOpenLog);
  Log.Run :=
    procedure
    var
      Actions: IOTAActionServices;
    begin
      if (TAtlasGuard.RotatingLog <> nil) and FileExists(TAtlasGuard.RotatingLog.FileName) and
        Supports(BorlandIDEServices, IOTAActionServices, Actions) then
        Actions.OpenFile(TAtlasGuard.RotatingLog.FileName);
    end;
  TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.Fuse, TAtlasNotificationSeverity.Error,
    TAtlasStrings.Fmt(TAtlasTextId.FuseTrippedTitle, [TAtlasGuard.FeatureName(Feature)]), AMessage, [Enable, Log]);
end;

/// <summary>Atlas-Protokoll gestört (Bericht M4), aus dem Thread des Schreibers: über OutputDebugString (DebugView
/// zeigt es, auch wenn atlas.log nichts mehr annimmt) und als Benachrichtigung; '' = schreibt wieder.</summary>
procedure LogError(const AMessage: string);
var
  Reason, Text, Detail: string;
begin
  if AMessage = '' then
  begin
    OutputDebugString(PChar('Atlas: Protokoll schreibt wieder'));
    Exit;
  end;
  Reason := TAtlasGuard.SafeMessage(AMessage);
  OutputDebugString(PChar('Atlas: Protokoll gestört: ' + Reason));
  Text := TAtlasStrings.Text(TAtlasTextId.LogBrokenTitle);
  Detail := TAtlasStrings.Fmt(TAtlasTextId.LogBrokenText, [TAtlasGuard.RotatingLog.FileName, Reason]);
  if TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.Fuse, TAtlasNotificationSeverity.Warning,
    Text, Detail) <> TAtlasNotificationMode.Show then
    Exit;
  Text := Text + ': ' + Detail;
  TAtlasMainThread.Queue(TAtlasFeature.Status,
    procedure
    begin
      MessageLine(Text);
    end);
end;

/// <summary>„Einstellungen“ der Zustandskachel (#754): Optionsseite „Atlas“ (#227) wie Menü Atlas › Einstellungen.</summary>
procedure OpenAtlasOptions;
var
  Options: IOTAEnvironmentOptions140;
  Services: IOTAServices;
begin
  if Supports(BorlandIDEServices, IOTAServices, Services) and
    Supports(Services.GetEnvironmentOptions, IOTAEnvironmentOptions140, Options) then
    Options.EditOptions('', 'Atlas');
end;

/// <summary>„Log-Ordner öffnen“ der Zustandskachel (#754): %LOCALAPPDATA%\Atlas\Logs im Explorer.</summary>
procedure OpenLogFolder;
var
  Folder: string;
begin
  Folder := TAtlasRotatingLog.DefaultFolder;
  ForceDirectories(Folder);
  ShellExecute(0, 'open', PChar(Folder), nil, nil, SW_SHOWNORMAL);
end;

/// <summary>Zustandskachel „Atlas“ (#754): Zeilen aus dem Statusfeld, Knöpfe über den Manager und die Update-Prüfung.</summary>
function CreateWelcomeState: TAtlasIdeWelcomeState;
var
  Actions: TAtlasStateActions;
begin
  Actions.Restart :=
    procedure
    begin
      if Manager <> nil then
        Manager.RestartServer;
      if StatusField <> nil then
        StatusField.RequestRefresh;
    end;
  Actions.Settings := OpenAtlasOptions;
  Actions.LogFolder := OpenLogFolder;
  Actions.Update :=
    procedure
    begin
      if Updates <> nil then
        Updates.OpenUpdate;
    end;
  Result := TAtlasIdeWelcomeState.Create(TAtlasStatusRegistry.Default, Actions);
end;

const
  ProblemCountsExtra = 'problemCounts';
  /// <summary>Kosten einer interface-Änderung (#554).</summary>
  InterfaceCostExtra = 'interfaceCost';

procedure RegisterStatusField;
begin
  StatusLines := TAtlasIdeStatusLines.Create(TAtlasStatusRegistry.Default,
    function: TAtlasServerInfo
    begin
      if Manager <> nil then
        Result := Manager.ServerInfo
      else
        Result := Default(TAtlasServerInfo);
    end,
    function(out APercent: Integer): Boolean
    begin
      APercent := -1;
      Result := (Manager <> nil) and Manager.ServerIndexing(APercent);
    end,
    function(const ADone: TProc<string>): Boolean
    begin
      Result := (Manager <> nil) and Manager.QueryStatusAsync(ADone);
    end,
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end);
  StatusField := TAtlasStatusField.Create(TAtlasStatusRegistry.Default);
  StatusField.OnRefresh :=
    procedure
    begin
      if StatusLines <> nil then
        StatusLines.Refresh;
    end;
  StatusField.OnOpenLog := OpenLog;
  // Zeigt die Atlas-Statusleiste das Element status, öffnen Statusfenster und Schnellschalter dort (#1155).
  StatusField.OnRelocatedAnchor := TAtlasIdeStatusBar.Anchor;
  // Rechtsklick auf das Feld: Schnellschalter (#604).
  StatusField.OnContext :=
    procedure(APoint: TPoint)
    begin
      if QuickToggles <> nil then
        QuickToggles.Show(APoint);
    end;
  StatusField.OnRestart :=
    procedure
    begin
      if Manager <> nil then
        Manager.RestartServer;
    end;
  // Fehlerzähler (#509) als Zusatzfeld; ein Klick öffnet die Liste „Atlas-Probleme“.
  TAtlasProblemsController.OnCounts :=
    procedure(AShow: Boolean; const ACounts: TAtlasProblemCounts)
    begin
      if StatusField = nil then
        Exit;
      if not AShow then
      begin
        StatusField.SetExtra(ProblemCountsExtra, '', '', nil);
        Exit;
      end;
      StatusField.SetExtra(ProblemCountsExtra, TAtlasStrings.Fmt(TAtlasTextId.ProblemCounterText,
        [ACounts.Errors, ACounts.Warnings, ACounts.Hints]), TAtlasStrings.Fmt(TAtlasTextId.ProblemCounterHint,
        [ACounts.Errors, ACounts.Warnings, ACounts.Hints]),
        procedure(APoint: TPoint)
        begin
          // Mit dem Fenster „Atlas-Prüfung“ (#909) dorthin, sonst in die Meldungsliste.
          if TAtlasIdeProblems.Enabled then
            TAtlasIdeProblems.ShowWindow
          else
            TAtlasProblemsList.ShowList;
        end);
    end;
end;

/// <summary>Farbe der Plakette (#601): Info neutral, Warnung gelb, Fehler rot.</summary>
function BadgeState(ASeverity: TAtlasNotificationSeverity): TAtlasStatusState;
begin
  case ASeverity of
    TAtlasNotificationSeverity.Warning:
      Result := TAtlasStatusState.Yellow;
    TAtlasNotificationSeverity.Error:
      Result := TAtlasStatusState.Red;
  else
    Result := TAtlasStatusState.Neutral;
  end;
end;

/// <summary>Benachrichtigungszentrale (#601): immer, auch abgesichert; an oder aus nach notifications.enabled.
/// </summary>
procedure StartNotifications;
begin
  Notifications := TAtlasIdeNotifications.Create(nil);
  Notifications.OnAnchor :=
    function: TPoint
    begin
      if (StatusField = nil) or not StatusField.Anchor(Result) then
        Result := Point(MaxInt, MaxInt);
    end;
  Notifications.OnBadge :=
    procedure(AUnread: Integer; AWorst: TAtlasNotificationSeverity)
    begin
      if StatusField <> nil then
        StatusField.SetBadge(AUnread, BadgeState(AWorst),
          TAtlasStrings.Fmt(TAtlasTextId.NotificationsBadgeHint, [AUnread]),
          procedure(APoint: TPoint)
          begin
            if Notifications <> nil then
              Notifications.Show(APoint);
          end);
    end;
  // Erst jetzt erreicht die Plakette das Feld.
  Notifications.ApplySettings;
end;

procedure UnregisterStatusField;
begin
  TAtlasProblemsController.OnCounts := nil;
  if Manager <> nil then
    Manager.OnServerChanged := nil;
  FreeAndNil(StatusField);
  FreeAndNil(StatusLines);
  TAtlasStatusRegistry.ReleaseDefault;
end;

procedure RegisterWatchdog;
begin
  Hangs := TAtlasHangMonitor.Create(TAtlasIdeSettings.Current.HangThresholdMs);
  Watchdog := TAtlasWatchdog.Create(
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.HangThresholdMs;
    end);
  Watchdog.OnHang := ReportHang;
end;

procedure UnregisterWatchdog;
begin
  FreeAndNil(Watchdog);
  if (Hangs <> nil) and (Hangs.Count > 0) and (Manager <> nil) then
    Manager.Report(Hangs.Summary);
  FreeAndNil(Hangs);
end;

procedure LogLine(const AText: string);
begin
  if Manager <> nil then
    Manager.Log(AText);
end;

/// <summary>Dateien, die die IDE kennt: offene Module und die Module des Projekts (für Meldungen ohne Pfad).</summary>
function KnownFiles(const AProjectFile: string): TArray<string>;
var
  Modules: IOTAModuleServices;
  Project: IOTAProject;
  Index: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  for Index := 0 to Modules.ModuleCount - 1 do
    Result := Result + [Modules.Modules[Index].FileName];
  if (AProjectFile <> '') and Supports(Modules.FindModule(AProjectFile), IOTAProject, Project) then
    for Index := 0 to Project.GetModuleCount - 1 do
      if Project.GetModule(Index).FileName <> '' then
        Result := Result + [Project.GetModule(Index).FileName];
end;

procedure RegisterCompileEvents;
var
  Events: TAtlasCompileEvents;
begin
  Events := TAtlasCompileEvents.Create;
  Events.OnNotify :=
    procedure(const AMethod: string; AParams: TJSONObject)
    begin
      if Manager <> nil then
        Manager.NotifyServer(AMethod, AParams)
      else
        AParams.Free;
    end;
  Events.OnLog := LogLine;
  Events.Add(TAtlasCompileLog.Create(Events, LogLine));
  // Release-Build-Wächter (#533): prüft vor make und build in einer Release-Konfiguration, auch für Aufträge des
  // Läufers (#261, #764); mit build.gate = block bricht er ab.
  Events.Add(TAtlasIdeReleaseGuard.CreateParticipant(TAtlasIdeProjects.Folder,
    function: TAtlasReleaseSettings
    begin
      Result := ReleaseSettings();
    end));
  // Projektaufgaben vor dem Build (#900, tasks.beforeBuild); ohne Läufer (tasks.enabled aus) nichts.
  Events.Add(TAtlasIdeTasks.CreateParticipant(
    function: TAtlasIdeTasks
    begin
      Result := ProjectTasks;
    end));
  // Prüfung vor dem Kompilieren (#529): geänderte Units über den laufenden Server, nur Builds des Benutzers.
  Events.Add(TAtlasIdeBuildGate.CreateParticipant(
    function: TAtlasGateSettings
    begin
      Result := GateSettings();
    end,
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.RunningSession;
    end));
  // Compilermeldungen aus dem Reiter „Build“ an den Server (#528).
  Events.Add(TAtlasMessageViewReader.Create(
    procedure(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      ASucceeded: Boolean; const AInfo: string; AReadable: Boolean)
    var
      Messages: TArray<TAtlasCompilerMessage>;
      Project: TAtlasCompileProject;
      Succeeded, Readable: Boolean;
      Stamp: TDateTime;
    begin
      Messages := TAtlasCompilerMessages.Resolve(AMessages, AProject.FileName, KnownFiles(AProject.FileName));
      // Projekt-Zusammenfassung für die Willkommensseite (#592): letzter Build bzw. letzte Hintergrundprüfung.
      Project := AProject;
      Succeeded := ASucceeded;
      Readable := AReadable;
      // Ein Zeitpunkt je Build: Metriken, TODOs und Baseline kommen damit in den Messpunkt des Builds (#758).
      Stamp := TAtlasIdeProjects.StampUtc;
      if (Welcome <> nil) and (Welcome.Projects <> nil) then
        TAtlasGuard.Run(TAtlasFeature.WelcomePage,
          procedure
          begin
            Welcome.Projects.Recorded(Messages, Project, Succeeded, Readable, Stamp);
          end);
      // Code-Metriken und TODOs nach einem Build, nicht nach einer Hintergrundprüfung (#66, #68, #758).
      if AReadable and not AProject.Background then
        TAtlasGuard.Run(TAtlasFeature.WelcomePage,
          procedure
          begin
            RecordProjectMetrics(Project.FileName, Stamp);
          end);
      // Builds auf Auftrag (#261) warten auf ihre Meldungen.
      if BuildRunner <> nil then
        TAtlasGuard.Run(TAtlasFeature.Build,
          procedure
          begin
            BuildRunner.MessagesRead(Messages, Project);
          end);
      // Build des Benutzers mit lesbaren Meldungen (#530): erst bewerten (Basislinie, build.zeroHints,
      // build.warningsAsErrors), dann Zusammenfassung, Benachrichtigung (#601) und Tests nach dem Build (#69).
      if AReadable and not AProject.Background then
        TAtlasGuard.Run(TAtlasFeature.Build,
          procedure
          begin
            EvaluateBuild(Messages, Project, Succeeded);
          end)
      // Hintergrundprüfung bzw. Build ohne lesbare Meldungen: Eintrag in der Benachrichtigungszentrale (#601).
      else if Notifications <> nil then
        TAtlasGuard.Run(TAtlasFeature.Notifications,
          procedure
          begin
            Notifications.BuildFinished(Messages, Project, Succeeded, Readable);
          end);
      if Manager = nil then
        Exit;
      if Length(Messages) > 0 then
        Manager.Report(Format('Meldungsfenster: %s (z. B. %s, Zeile %d)', [AInfo, Messages[0].FileName,
          Messages[0].Line]))
      else
        Manager.Report('Meldungsfenster: ' + AInfo);
      Manager.NotifyServer('atlas/compilerMessages',
        TAtlasCompilerMessages.ToJson(Messages, AProject.FileName, AProject.Platform, ASucceeded,
        AProject.Background));
    end));
  Compile := TAtlasIdeCompileEvents.Create(Events);
  BuildRunner := TAtlasIdeBuildRunner.Create(Events);
  BuildSummary := TAtlasIdeBuildSummary.Create;
end;

/// <summary>Sprache der IDE (#446): Eintrag für bds.exe unter HKCU\Software\Embarcadero\Locales (von
/// BDSSetLang), sonst Sprache der Windows-Oberfläche; Rückfall Englisch.</summary>
function IdeLanguage: TAtlasLanguage;
var
  Registry: TRegistry;
  Names: TStringList;
  Name, Code: string;
begin
  Code := '';
  Registry := TRegistry.Create(KEY_READ);
  Names := TStringList.Create;
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    if Registry.OpenKeyReadOnly('Software\Embarcadero\Locales') then
    begin
      Registry.GetValueNames(Names);
      for Name in Names do
        if SameText(Name, ParamStr(0)) and (Registry.GetDataType(Name) = rdString) then
          Code := Registry.ReadString(Name);
    end;
  finally
    Names.Free;
    Registry.Free;
  end;
  if Code = '' then
    if (GetUserDefaultUILanguage and $3FF) = LANG_GERMAN then
      Code := 'DE';
  if SameText(Code, 'DE') then
    Result := TAtlasLanguage.German
  else
    Result := TAtlasLanguage.English;
end;

/// <summary>Stufe des abgesicherten Starts (#722); ohne Sicherung normal.</summary>
function Level: TAtlasSafeLevel;
begin
  if SafeMode <> nil then
    Result := SafeMode.Level
  else
    Result := TAtlasSafeLevel.Normal;
end;

procedure CreateReloader;
begin
  Reloader := TAtlasFileReloader.Create(
    procedure(AText: string)
    begin
      if Manager <> nil then
        Manager.Report(AText);
    end);
  // Gespeichert: Compilerprüfung vormerken (#548).
  Reloader.OnSaved :=
    procedure(AFileName: string)
    begin
      // Prüfung des Servers mit dcc (#40); die Prüfung in der IDE nur, wenn eingeschaltet (#548).
      if Manager <> nil then
        Manager.NotifySaved(AFileName);
      if CheckOnSave <> nil then
        CheckOnSave.Saved(AFileName);
      // Gewählte Kodierung und Zeilenenden schreiben (#591).
      if StatusLines <> nil then
        StatusLines.Saved(AFileName);
    end;
end;

procedure CreateMainMenu;
begin
  MainMenu := TAtlasMainMenu.Create(
    function: string
    begin
      // Fortschritt im Menütitel nur, wenn er nicht ins Statusfeld gehört (IndexProgressPlace).
      if (Manager <> nil) and TAtlasIdeSettings.Current.IndexProgressInMenu then
        Result := Manager.ServerProgress
      else
        Result := '';
    end,
    procedure(ACommand: string; ADone: TProc<TJSONValue>)
    begin
      if Manager <> nil then
        Manager.ExecuteServerCommandAsync(ACommand, 30000, ADone)
      else
        ADone(nil);
    end,
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end);
  MainMenu.OnBugReport := CreateBugReport;
end;

/// <summary>Einrichtung mit Prüfliste (#625); Zustand des Servers über den Manager und das Statusfeld.</summary>
procedure CreateSetup;
var
  Hooks: TAtlasSetupHooks;
begin
  Hooks.ServerInfo :=
    function: TAtlasServerInfo
    begin
      if Manager <> nil then
        Result := Manager.ServerInfo
      else
        Result := Default(TAtlasServerInfo);
    end;
  Hooks.Indexing :=
    function(out APercent: Integer): Boolean
    begin
      APercent := -1;
      Result := (Manager <> nil) and Manager.ServerIndexing(APercent);
    end;
  Hooks.StatusJson :=
    function: string
    begin
      Result := '';
      if StatusLines <> nil then
        Result := StatusLines.StatusJson;
    end;
  Hooks.StartServer :=
    function(ARestart: Boolean): Boolean
    begin
      Result := False;
      if Manager = nil then
        Exit;
      if ARestart then
        Result := Manager.RestartServer
      else
      begin
        // Von Hand: auch nach zwei gleichen Abstürzen (Bericht H5). Die aktive Sitzung startet den Server,
        // wenn er noch nicht läuft.
        Manager.AllowStart;
        Result := Manager.ActiveSession <> nil;
      end;
    end;
  Hooks.ServerCommand :=
    function(ACommand: string): Boolean
    begin
      // Nur abschicken (#874): Den Fortschritt zeigt die Prüfliste über Indexing.
      Result := (Manager <> nil) and (Manager.ActiveSession <> nil);
      if Result then
        Manager.ExecuteServerCommandAsync(ACommand, 30000, nil);
    end;
  // Derselbe Weg nach einem Branch mit geänderten Externals (#1291).
  TAtlasIdeBranching.ServerCommand := Hooks.ServerCommand;
  Hooks.ServerPath :=
    function: string
    var
      Arguments: string;
    begin
      Result := TAtlasCodeInsightManager.ServerPath(Arguments);
    end;
  Setup := TAtlasIdeSetupChecklist.Create(TAtlasStatusRegistry.Default, Hooks);
end;

type
  /// <summary>Anbieter, Token und Transport des Issue-Trackers (#765, #1260) für „Meine Issues“ und die Seite
  /// Issue-Tracker: Token im Anmeldespeicher von Windows (Ziel "Atlas:tracker:&lt;Server&gt;", Benutzer =
  /// Anbieter), verdeckter Dialog, „Authorization: Bearer“ nur über https an die API des Trackers. Meldungen
  /// anonym, ohne Server und Token.</summary>
  TAtlasComposedTrackerAccess = class(TInterfacedObject, IAtlasTrackerAccess)
  public
    function Providers: TArray<IAtlasTrackerProvider>;
    function Provider(const AName: string): IAtlasTrackerProvider;
    function HasToken(const ATarget: TAtlasTrackerTarget): Boolean;
    function EnterToken(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): Boolean;
    function RemoveToken(const ATarget: TAtlasTrackerTarget): Boolean;
    function Transport(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): IAtlasCiTransport;
  end;

var
  TrackerAccessInstance: IAtlasTrackerAccess;

function TrackerAccess: IAtlasTrackerAccess;
begin
  if TrackerAccessInstance = nil then
    TrackerAccessInstance := TAtlasComposedTrackerAccess.Create;
  Result := TrackerAccessInstance;
end;

function TAtlasComposedTrackerAccess.Providers: TArray<IAtlasTrackerProvider>;
begin
  // Tracker-Anbieter: YouTrack und GitHub; weitere kommen ohne Änderung an Bereich und Optionsseite dazu.
  Result := [TAtlasYouTrackTracker.Create as IAtlasTrackerProvider, TAtlasGitHubTracker.Create as IAtlasTrackerProvider];
end;

function TAtlasComposedTrackerAccess.Provider(const AName: string): IAtlasTrackerProvider;
var
  mProvider: IAtlasTrackerProvider;
begin
  for mProvider in Providers do
    if SameText(mProvider.Name, Trim(AName)) then
      Exit(mProvider);
  Result := nil;
end;

function TAtlasComposedTrackerAccess.HasToken(const ATarget: TAtlasTrackerTarget): Boolean;
var
  mUser, mToken: string;
begin
  Result := False;
  if ATarget.CredentialTarget = '' then
    Exit;
  mUser := '';
  mToken := '';
  Result := TAtlasCiCredentials.Read(ATarget.CredentialTarget, mUser, mToken) and (mToken <> '');
  UniqueString(mToken);
  FillChar(PChar(mToken)^, Length(mToken) * SizeOf(Char), 0);
end;

function TAtlasComposedTrackerAccess.EnterToken(const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget): Boolean;
var
  mToken: string;
  mOk: Boolean;
begin
  Result := False;
  // Das Token geht nur über https an den eingetragenen Server; ohne https gar nicht erst speichern.
  if not ATarget.Secure then
  begin
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.TrackerLoginInsecure));
    Exit;
  end;
  mToken := '';
  if not TAtlasCiLoginPrompt.AskToken(TAtlasStrings.Fmt(TAtlasTextId.TrackerLoginTitle, [AProvider.Caption,
    ATarget.Server]), TAtlasStrings.Text(TAtlasTextId.TrackerLoginToken), mToken) then
    Exit;
  if mToken = '' then
  begin
    mOk := TAtlasCiCredentials.Delete(ATarget.CredentialTarget);
    if mOk then
      GuardWarning(TAtlasStrings.Text(TAtlasTextId.TrackerLoginRemoved))
    else
      GuardWarning(TAtlasStrings.Text(TAtlasTextId.TrackerLoginFailed));
    Exit(mOk);
  end;
  mOk := TAtlasCiCredentials.Write(ATarget.CredentialTarget, AProvider.Name, mToken, 'Atlas: Issue-Tracker');
  UniqueString(mToken);
  FillChar(PChar(mToken)^, Length(mToken) * SizeOf(Char), 0);
  // Anonym: weder Server noch Projekt.
  if mOk then
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.TrackerLoginSaved))
  else
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.TrackerLoginFailed));
  Result := mOk;
end;

function TAtlasComposedTrackerAccess.RemoveToken(const ATarget: TAtlasTrackerTarget): Boolean;
begin
  Result := True;
  if ATarget.CredentialTarget = '' then
    Exit;
  Result := TAtlasCiCredentials.Delete(ATarget.CredentialTarget);
  if Result then
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.TrackerLoginRemoved))
  else
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.TrackerLoginFailed));
end;

function TAtlasComposedTrackerAccess.Transport(const AProvider: IAtlasTrackerProvider;
  const ATarget: TAtlasTrackerTarget): IAtlasCiTransport;
var
  mUser, mToken: string;
begin
  Result := nil;
  if (AProvider = nil) or not ATarget.Secure then
    Exit;
  mUser := '';
  mToken := '';
  if not TAtlasCiCredentials.Read(ATarget.CredentialTarget, mUser, mToken) or (mToken = '') then
    Exit;
  // „Authorization: Bearer“ nur über https an die Programmierschnittstelle des Trackers.
  Result := TAtlasCiHttpTransport.CreateBearer(AProvider.ApiServer(ATarget), mToken);
  UniqueString(mToken);
  FillChar(PChar(mToken)^, Length(mToken) * SizeOf(Char), 0);
end;

/// <summary>Optionsseiten (#227) mit ihren Haken (A-09): Die Seiten importieren die Features nicht, die sie
/// bedienen.</summary>
procedure RegisterOptions;
var
  Hooks: TAtlasOptionsHooks;
begin
  Hooks := Default(TAtlasOptionsHooks);
  Hooks.ResetHistory :=
    procedure
    begin
      TAtlasIdeHistory.Reset;
    end;
  Hooks.Command :=
    procedure(ACommand: string; ADone: TProc<TJSONValue>)
    begin
      // Kennzahlen, „Index neu aufbauen“ und „Index löschen“ der Einstellungsseite (#492), im Hintergrund (#874).
      if Manager <> nil then
        Manager.ExecuteServerCommandAsync(ACommand, 30000, ADone)
      else
        ADone(nil);
    end;
  Hooks.ResetUsage :=
    procedure
    begin
      TAtlasIdeCommandUsage.ResetCounts;
    end;
  Hooks.UnblockTips :=
    procedure
    begin
      TAtlasIdeDiscover.UnblockAll;
    end;
  Hooks.ToolbarCommands :=
    function: TArray<TAtlasToolbarCommandInfo>
    begin
      Result := TAtlasIdeEditorToolbar.CommandInfos;
    end;
  Hooks.ServerPath :=
    function: string
    var
      Arguments: string;
    begin
      Result := TAtlasCodeInsightManager.ServerPath(Arguments);
    end;
  Hooks.DefaultServerPath :=
    function: string
    begin
      Result := TAtlasCodeInsightManager.DefaultServerPath;
    end;
  Hooks.IdeTemplateFolder :=
    function: string
    begin
      Result := TAtlasEditorCompletion.IdeTemplateFolder;
    end;
  Hooks.SnippetFolder :=
    function: string
    begin
      Result := TAtlasEditorCompletion.SnippetFolder;
    end;
  // Seite Issue-Tracker (#1260): Anbieter, Token und „Verbindung prüfen“.
  Hooks.Tracker := TrackerAccess;
  TAtlasOptionsRegistration.Register(Hooks);
end;

/// <summary>Meldet an, was die Stufe des abgesicherten Starts (#722) und die Einstellungen erlauben; mehrfach
/// aufrufbar. Normal: alles. Abgesichert: Serververbindung, Statusfeld, Einstellungen, Palette und Menü; dazu,
/// was ein Schnellschalter wieder einschaltet. Minimal: nur Einstellungsseite und Statusfeld.</summary>
procedure StartManager;
var
  Services: IOTACodeInsightServices;
begin
  if Supports(BorlandIDEServices, IOTACodeInsightServices, Services) then
  begin
    Manager := TAtlasCodeInsightManager.Create(CodeInsightAdapters);
    ManagerRef := Manager;
    // „Protokoll öffnen“ an den Einträgen des Servers in der Benachrichtigungszentrale (#601).
    Manager.OnOpenLog := OpenLog;
    // Nach zwei gleichen Abstürzen des Servers bietet die Meldung den Fehlerbericht an (Bericht H5).
    Manager.OnBugReport := CreateBugReport;
    ManagerIndex := Services.AddCodeInsightManager(Manager);
  end;
end;

procedure StopManager;
var
  Services: IOTACodeInsightServices;
begin
  try
    if (ManagerIndex >= 0) and Supports(BorlandIDEServices, IOTACodeInsightServices, Services) then
      Services.RemoveCodeInsightManager(ManagerIndex);
    ManagerIndex := -1;
    if Manager <> nil then
    begin
      // Nicht auf Destroy warten (#886): Hält die IDE den Manager noch (etwa wenn sie Atlas mitten im
      // Gruppen-Build entlädt), liefen sonst Sitzung, Server, Threads und Editor-Anbindungen nach dem Entladen weiter.
      Manager.Shutdown;
      if Manager.RefCount > 1 then
        TAtlasGuard.Log(Format('Code-Insight-Manager wird nach dem Abmelden noch %d-mal von der IDE gehalten',
          [Manager.RefCount - 1]));
    end;
  finally
    Manager := nil;
    ManagerRef := nil;
  end;
end;

procedure StartCheckOnSave;
begin
  CheckOnSave := TAtlasIdeCheckOnSave.Create(Compile.Events,
    procedure(AText: string)
    begin
      if Manager <> nil then
        Manager.Report(AText);
    end);
end;

procedure StartUnitRename;
begin
  UnitRename := TAtlasIdeUnitRename.Create(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.ActiveSession;
    end,
    procedure(AText: string)
    begin
      if Manager <> nil then
        Manager.Report(AText);
    end);
end;

procedure StartOpenBuild;
begin
  OpenBuild := TAtlasIdeOpenBuild.Create(Compile.Events,
    procedure(AText: string)
    begin
      if Manager <> nil then
        Manager.Report(AText);
    end);
end;

/// <summary>Atlas-Editorleiste (#1101): Palette, Befunde, Verlauf und Meldungen über Hooks (kein Feature-Zyklus).
/// Die Palette entsteht später (StartPalette); die Hooks fragen sie erst beim Aufruf.</summary>
procedure StartEditorToolbar;
var
  Hooks: TAtlasIdeEditorToolbar.THooks;
begin
  Hooks := Default(TAtlasIdeEditorToolbar.THooks);
  Hooks.Commands :=
    function: TArray<TAtlasCommand>
    begin
      Result := nil;
      if Palette <> nil then
        Result := Palette.AtlasCommands;
    end;
  Hooks.Execute :=
    procedure(AId: string)
    begin
      if Palette <> nil then
        Palette.Execute(AId);
    end;
  Hooks.ShowPalette :=
    procedure
    begin
      if Palette <> nil then
        Palette.Show;
    end;
  Hooks.ShortCutOf :=
    function(AId: string): string
    begin
      Result := TAtlasIdeKeyMap.AtlasShortCut(AId);
    end;
  Hooks.FindingsOf :=
    function(AFileName: string): Integer
    begin
      Result := 0;
      if TAtlasProblemsController.Current <> nil then
        Result := Length(TAtlasProblemsController.Current.ForFile(AFileName));
    end;
  Hooks.CanGoBack :=
    function: Boolean
    begin
      Result := (TAtlasIdeNavHistory.History <> nil) and (TAtlasIdeNavHistory.History.BackCount > 0);
    end;
  Hooks.CanGoForward :=
    function: Boolean
    begin
      Result := (TAtlasIdeNavHistory.History <> nil) and (TAtlasIdeNavHistory.History.ForwardCount > 0);
    end;
  Hooks.Message :=
    procedure(AText: string)
    begin
      MessageLine(AText);
    end;
  TAtlasIdeEditorToolbar.Install(Hooks);
end;

/// <summary>Atlas-Statusleiste (#1155): Atlas-Feld, Metriken aus dem Lens-Abruf (#66) und Meldungen über Hooks.
/// Zeigt die Leiste das Element status, öffnet das Feld Statusfenster und Schnellschalter an der Leiste.</summary>
procedure StartStatusBar;
var
  Hooks: TAtlasIdeStatusBar.THooks;
begin
  Hooks := Default(TAtlasIdeStatusBar.THooks);
  Hooks.Field :=
    function: TAtlasStatusField
    begin
      Result := StatusField;
    end;
  Hooks.Metrics :=
    function(const AFileName: string; out AMetrics: TAtlasFileMetrics): Boolean
    begin
      Result := TAtlasEditorMetricsLens.Latest(AFileName, AMetrics);
    end;
  Hooks.WantMetrics :=
    procedure(AOn: Boolean)
    begin
      TAtlasEditorMetricsLens.Want(AOn);
    end;
  Hooks.Message :=
    procedure(AText: string)
    begin
      MessageLine(AText);
    end;
  Hooks.Recheck :=
    procedure
    begin
      // Klick auf die Live-Prüfung (#1231); startet keinen Server.
      if Manager <> nil then
        Manager.RunServerCommandAsync('atlas.server.recheck', '[]', 10000, nil);
    end;
  TAtlasIdeStatusBar.Install(Hooks);
  if StatusField <> nil then
    StatusField.RequestRefresh;
end;

procedure StartCommands;
begin
  CommandsInstalled := True;
  TAtlasIdeResults.Install(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.ActiveSession;
    end,
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end);
  TAtlasIdeEditorCommands.Install(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.ActiveSession;
    end,
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end);
  // Auswirkungsanalyse (#1120): „Betroffene Tests ausführen“ über den Testläufer (#69).
  TAtlasIdeImpact.Install(
    procedure(const AFileName: string; const ATests: TArray<string>)
    begin
      if Tests <> nil then
        Tests.RunTests(AFileName, ATests)
      else
        GuardWarning(TAtlasStrings.Text(TAtlasTextId.TestsRunOff));
    end);
  // Klick auf die Testunit-Lens (#189); die Lens kennt die Editorbefehle nicht (A-09).
  TAtlasEditorTestUnitLens.OnSwitchTestUnit :=
    procedure
    begin
      TAtlasIdeEditorCommands.SwitchTestUnit;
    end;
  // Aktionen unter uses-Hinweisen (#621) und Regelbefunden (#909) im Tooltip: über die Code-Aktionen mit
  // Kennung; „Regel einstellen…“ öffnet die Einstellungsseite auf der Regel.
  TAtlasEditorHover.OnProblemAction :=
    procedure(const AProblem: TAtlasProblem; const ATag: string)
    var
      Item: Integer;
    begin
      if ATag = 'rule.configure' then
      begin
        TAtlasOptionsRegistration.ShowRule(AProblem.Code);
        Exit;
      end;
      // Unit-Zyklus (#896): Unit im Pfad springt an ihren uses-Eintrag, „Graph zeigen“ öffnet die
      // Unit-Beziehungen der Unit im Editor.
      if StartsStr('related:', ATag) then
      begin
        Item := StrToIntDef(Copy(ATag, Length('related:') + 1, MaxInt), -1);
        if (Item >= 0) and (Item <= High(AProblem.Related)) then
          TAtlasIdeNavigation.GoToLocation(TLspSession.UriToPath(AProblem.Related[Item].Uri),
            AProblem.Related[Item].Line, AProblem.Related[Item].Character);
        Exit;
      end;
      if ATag = 'cycle.showGraph' then
      begin
        TAtlasGuard.Run(TAtlasFeature.UnitRelations, TAtlasIdeUnitRelations.ShowCurrent);
        Exit;
      end;
      TAtlasIdeEditorCommands.ApplyTagged(TLspRange.Create(AProblem.StartLine, AProblem.StartCharacter,
        AProblem.EndLine, AProblem.EndCharacter), ATag);
    end;
  // Werte im Tooltip (#835, #854): eigene Regel des Typs vor den Visualisierern für Bibliothekstypen; beide
  // liefern '', solange ihr Teil nicht läuft. Der Tooltip kennt die Debug-Schicht nicht (A-09).
  TAtlasEditorHover.OnVisualize :=
    function(const AExpression: string; const ATypeChain: TArray<string>; const AText: string): string
    begin
      Result := TAtlasIdeDisplayRules.HoverText(AExpression, ATypeChain);
      if Result = '' then
        Result := TAtlasIdeVisualizers.HoverText(AExpression, ATypeChain, AText);
    end;
  // Nächster/vorheriger Befund (#509): alle Befunde der Datei aus dem Problemspeicher.
  TAtlasIdeEditorCommands.OnProblemsOf :=
    function(const AFileName: string): TArray<TAtlasProblem>
    begin
      Result := nil;
      if TAtlasProblemsController.Current <> nil then
        Result := TAtlasProblemsController.Current.ForFile(AFileName);
    end;
  // Schnellkorrektur „Signaturhilfe öffnen“ (#1007): nach dem Sprung der Parameter-Hint wie mit der Taste.
  // „Graph zeigen“ als Code-Aktion an einem Unit-Zyklus (#896, atlas.showUnitRelations).
  TAtlasIdeEditorCommands.OnUnitRelations :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.UnitRelations, TAtlasIdeUnitRelations.ShowCurrent);
    end;
  // „Issue anlegen …“ im Editor-Kontextmenü und auf der Taste (#1268).
  TAtlasIdeEditorCommands.OnCreateIssue :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.WelcomePage, TAtlasIdeNewIssue.FromEditor);
    end;
  TAtlasIdeEditorCommands.CreateIssueAvailable :=
    function: Boolean
    begin
      Result := TAtlasIdeNewIssue.Enabled;
    end;
  TAtlasIdeEditorCommands.OnSignatureHelp :=
    procedure
    begin
      if Manager <> nil then
        Manager.OpenSignature;
    end;
  // ///-Gerüst (#88): Tab springt durch die Beschreibungen, wie bei Code-Vorlagen.
  TAtlasIdeEditorCommands.OnPlaceholders :=
    procedure(const AView: IOTAEditView; const ABefore: string; AOffset: Integer;
      const AExpansion: TAtlasSnippetExpansion)
    begin
      if (Manager <> nil) and (Manager.Completion <> nil) then
        Manager.Completion.StartPlaceholders(AView, ABefore, AOffset, AExpansion);
    end;
  // Erzeugen-Menü (#719): Vorlagen und ihr Einsetzen mit Platzhaltern kommen aus der Vervollständigung.
  TAtlasIdeGenerate.Install(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.ActiveSession;
    end,
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end,
    function: TAtlasSnippetList
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.Completion.Snippets;
    end,
    procedure(AView: IOTAEditView; ASnippet: TAtlasSnippet)
    begin
      if Manager <> nil then
        Manager.Completion.InsertSnippet(AView, ASnippet);
    end,
    procedure(AAction: TLspCodeAction)
    begin
      TAtlasIdeEditorCommands.ApplyAction(AAction);
    end);
  // Navigationsverlauf (#504): Sprünge und Bearbeitungsstellen der Sitzung.
  TAtlasIdeNavHistory.Install;
  // Definition und Referenzen einblenden (#505).
  TAtlasIdePeek.Install;
  // Gemeinsamer Stand der Gliederung, Gliederungsfenster (#537) und Brotkrumenleiste (#590).
  TAtlasIdeOutlineCache.Install(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.ActiveSession;
    end);
  TAtlasIdeOutline.Install;
  // Fenster „Atlas-Architektur“ (#1118): fragt den Server über RunCommandAsync.
  TAtlasIdeArchitecture.Install(
    function(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal; const ADone: TProc<string>): Boolean
    begin
      Result := (Manager <> nil) and (Manager.ActiveSession <> nil) and
        Manager.RunCommandAsync(ACommand, AArgumentsJson, ATimeoutMs, ADone);
    end);
  // Fenster „Unit-Beziehungen“ (#593): fragt regelmäßig nach, daher nicht über den einen Hintergrundbefehl von
  // RunCommandAsync (der bliebe sonst für Architektur und Co. belegt), und startet keinen Server.
  TAtlasIdeUnitRelations.Install(
    function(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal; const ADone: TProc<TJSONValue>): Boolean
    begin
      Result := (Manager <> nil) and (Manager.RunningSession <> nil);
      if Result then
        Manager.RunServerCommandAsync(ACommand, AArgumentsJson, ATimeoutMs, ADone);
    end);
  // Kosten einer interface-Änderung (#554) im Zusatzfeld der Statusleiste; Klick zeigt die Abhängigkeiten.
  TAtlasIdeUnitRelations.SetCostHandler(
    procedure(const AText, AHint: string)
    begin
      if StatusField = nil then
        Exit;
      if AText = '' then
        StatusField.SetExtra(InterfaceCostExtra, '', '', nil)
      else
        StatusField.SetExtra(InterfaceCostExtra, AText, AHint,
          procedure(APoint: TPoint)
          begin
            TAtlasGuard.Run(TAtlasFeature.UnitRelations, TAtlasIdeUnitRelations.ShowCurrent);
          end);
    end);
  // Fenster „Atlas-Hotspots“ (#1354): nebenläufig zu anderen Befehlen, weil es nachfragt, solange der Server im
  // Hintergrund rechnet; startet den Server bei Bedarf.
  TAtlasIdeHotspots.Install(
    function(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal; const ADone: TProc<string>): Boolean
    begin
      Result := (Manager <> nil) and (Manager.ActiveSession <> nil);
      if Result then
        Manager.RunServerCommandAsync(ACommand, AArgumentsJson, ATimeoutMs, HotspotsAnswer(ADone));
    end);
  // „Auswirkungen anzeigen“ im Hotspot-Fenster (#1120) auf der Methode, auf die das Fenster den Cursor setzt.
  TAtlasIdeHotspots.OnImpact :=
    procedure
    begin
      TAtlasIdeImpact.ShowAtCursor;
    end;
  // Strg+Doppelklick in der Architekturkarte zeigt die Unit dort.
  TAtlasIdeArchitecture.OnUnitRelations :=
    procedure(AFileName: string)
    begin
      TAtlasIdeUnitRelations.ShowFor(AFileName);
    end;
  // Weg zwischen Symbolen (#1117): Suche über RunCommandAsync, Vorschläge aus der Symbolsuche.
  TAtlasIdeSymbolPath.Install(
    function(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal; const ADone: TProc<string>): Boolean
    begin
      Result := (Manager <> nil) and (Manager.ActiveSession <> nil) and
        Manager.RunCommandAsync(ACommand, AArgumentsJson, ATimeoutMs, ADone);
    end,
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.ActiveSession;
    end);
  TAtlasIdeBreadcrumbs.Install;
  // Atlas-Editorleiste (#1101) nach den Brotkrumen (Position „in der Brotkrumenzeile“).
  StartEditorToolbar;
  StartStatusBar;
  // Mitlaufender Kopf (#506) aus demselben Gliederungsstand.
  TAtlasIdeStickyScroll.Install;
  // Änderungsmarken und Zeilenhistorie (#507).
  TAtlasIdeLineChanges.Install(
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end);
  // Zeilen verschieben und duplizieren (#634): Meldung ohne Nachbarmethode.
  TAtlasIdeLineMove.Install(
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end);
  // Blockkommentar umschalten (#703): Meldung beim Ablehnen.
  TAtlasIdeBlockComment.Install(
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end);
  // Anweisung vervollständigen (#697): Rumpf und case-Zweige vom Server.
  TAtlasIdeStatementCompletion.Install(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.ActiveSession;
    end,
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end);
  // Kommentar beim Enter fortsetzen (#696): beobachtet Enter, ohne die Taste zu binden.
  TAtlasIdeCommentContinuation.Install;
  // Muster fortsetzen (#671): nach dem Kommentar, nie bei offener Vervollständigung.
  TAtlasIdePatternContinuation.Install(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.RunningSession;
    end,
    function: Boolean
    begin
      Result := (Manager <> nil) and Manager.CompletionVisible;
    end);
  // Mehrere Einfügemarken (#589, experimentell): nie bei offener Vervollständigung, im Platzhalter-Modus oder
  // während Bezeichner mitgezogen werden (#658).
  TAtlasIdeMultiCursor.Install(
    function: Boolean
    begin
      Result := ((Manager <> nil) and (Manager.CompletionVisible or Manager.PlaceholdersActive)) or
        TAtlasIdeLinkedEditing.Active;
    end,
    procedure(const AText, AHint: string)
    begin
      if StatusField <> nil then
        StatusField.SetExtra('multiCursor', AText, AHint, nil);
    end);
  // Bezeichner live mitziehen (#658, experimentell): ebenso nie neben Vervollständigung, Platzhaltern und
  // mehreren Einfügemarken.
  TAtlasIdeLinkedEditing.Install(
    function: Boolean
    begin
      Result := ((Manager <> nil) and (Manager.CompletionVisible or Manager.PlaceholdersActive)) or
        TAtlasIdeMultiCursor.Active;
    end,
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.RunningSession;
    end,
    procedure(const AText, AHint: string)
    begin
      if StatusField <> nil then
        StatusField.SetExtra('linkedEditing', AText, AHint, nil);
    end);
  // Markierung beim Tippen umschließen (#672): nie neben Vervollständigung, Platzhaltern, mehreren
  // Einfügemarken (die umschließen selbst) und dem Mitziehen von Bezeichnern.
  TAtlasIdeWrapSelection.Install(
    function: Boolean
    begin
      Result := ((Manager <> nil) and (Manager.CompletionVisible or Manager.PlaceholdersActive)) or
        TAtlasIdeMultiCursor.Active or TAtlasIdeLinkedEditing.Active;
    end);
  // Einfügen mit uses-Ergänzung (#515, experimentell): nie neben Vervollständigung, Platzhaltern, mehreren
  // Einfügemarken und dem Mitziehen von Bezeichnern; Ergebnis nur in der Meldungsansicht.
  TAtlasIdeSmartPaste.Install(
    function: Boolean
    begin
      Result := ((Manager <> nil) and (Manager.CompletionVisible or Manager.PlaceholdersActive)) or
        TAtlasIdeMultiCursor.Active or TAtlasIdeLinkedEditing.Active;
    end,
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.RunningSession;
    end,
    procedure(AText: string)
    begin
      MessageLine(AText);
    end);
  // Umschließung entfernen (#657): Liste und Vorschau; Ergebnis in der Meldungsansicht.
  TAtlasIdeUnwrap.Install(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.RunningSession;
    end,
    procedure(AText: string)
    begin
      MessageLine(AText);
    end);
  // Gezielt hineinspringen (#836): Liste der Aufrufe am Ausführungspunkt; Meldungen in der Meldungsansicht.
  TAtlasIdeStepInto.Install(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.RunningSession;
    end,
    procedure(AText: string)
    begin
      MessageLine(AText);
    end);
  // Beim nächsten Ereignis anhalten (#856): Eintrag im Menü Start; Meldungen in der Meldungsansicht.
  TAtlasIdeEventBreak.Install(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.RunningSession;
    end,
    procedure(AText: string)
    begin
      MessageLine(AText);
    end);
  // Schrittfilter (#850): Fenster und Befehle; den Ablauf startet Features (debug.stepFilters).
  TAtlasIdeDebugStepFilter.Install(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.RunningSession;
    end,
    procedure(AText: string)
    begin
      MessageLine(AText);
    end);
  // Typ des markierten Ausdrucks (#689): Tooltip und Hervorhebung; Fehler in der Meldungsansicht.
  TAtlasIdeExpressionType.Install(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.RunningSession;
    end,
    procedure(AText: string)
    begin
      MessageLine(AText);
    end);
  // Methodenrümpfe in Deklarationsreihenfolge (#660): neue Rümpfe an ihre Stelle, Befehl mit Vorschau.
  TAtlasIdeMethodPlacement.Install(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.RunningSession;
    end,
    procedure(AText: string)
    begin
      MessageLine(AText);
    end,
    function: TAtlasUnopenedPolicy
    begin
      Result := TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits);
    end);
  // Übersichtsleiste an der Scrollleiste (#519).
  // Mit schnellen Lesezeichen (#1104) zeigt die Art „bookmarks“ die Lesezeichen von Atlas.
  TAtlasIdeOverviewRuler.Bookmarks :=
    function(const AFileName: string; out AMarks: TAtlasOverviewMarks): Boolean
    var
      Marks: TArray<TAtlasBookmark>;
      Mark: TAtlasBookmark;
    begin
      AMarks := nil;
      Result := TAtlasIdeBookmarks.OverviewMarks(AFileName, Marks);
      for Mark in Marks do
        AMarks := AMarks + [TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Bookmark, Mark.Line, 1, Mark.DisplayName)];
    end;
  TAtlasIdeOverviewRuler.Install;
  // Minimap neben der Scrollleiste (#873, experimentell); fragt die Gliederung über TAtlasIdeOutlineCache.
  TAtlasIdeMinimap.Install;
  // Schnell öffnen (#503): Dateiliste im Hintergrund, zuletzt geöffnete Dateien zählen.
  TAtlasIdeQuickOpen.Install(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.ActiveSession;
    end);
  // Units suchen (#777): übernimmt Strg+F12, solange die Einstellungen es wollen.
  TAtlasIdeUnitSearch.Install(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.ActiveSession;
    end,
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end);
  // Atlas-Suche (#877, #878): Hervorhebung der Treffer und Meldungen.
  TAtlasIdeSearch.Install(
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end);
end;

procedure StopCommands;
begin
  TAtlasIdeQuickOpen.Uninstall;
  TAtlasIdePeek.Uninstall;
  TAtlasIdeStickyScroll.Uninstall;
  TAtlasIdeEditorToolbar.Uninstall;
  TAtlasIdeStatusBar.Uninstall;
  TAtlasIdeBreadcrumbs.Uninstall;
  TAtlasIdeMinimap.Uninstall;
  TAtlasIdeOverviewRuler.Uninstall;
  TAtlasIdeOverviewRuler.Bookmarks := nil;
  TAtlasIdeLineChanges.Uninstall;
  TAtlasIdeLineMove.Uninstall;
  TAtlasIdeBlockComment.Uninstall;
  TAtlasIdeUnwrap.Uninstall;
  TAtlasIdeStepInto.Uninstall;
  TAtlasIdeEventBreak.Uninstall;
  TAtlasIdeDebugStepFilter.Uninstall;
  TAtlasIdeExpressionType.Uninstall;
  TAtlasIdeMethodPlacement.Uninstall;
  TAtlasIdeSmartPaste.Uninstall;
  TAtlasIdeWrapSelection.Uninstall;
  TAtlasIdeLinkedEditing.Uninstall;
  TAtlasIdeMultiCursor.Uninstall;
  TAtlasIdePatternContinuation.Uninstall;
  TAtlasIdeCommentContinuation.Uninstall;
  TAtlasIdeStatementCompletion.Uninstall;
  TAtlasIdeOutline.Uninstall;
  TAtlasIdeSymbolPath.Uninstall;
  TAtlasIdeArchitecture.Uninstall;
  TAtlasIdeHotspots.Uninstall;
  TAtlasIdeUnitRelations.Uninstall;
  TAtlasIdeOutlineCache.Uninstall;
  TAtlasIdeNavHistory.Uninstall;
  TAtlasIdeSearch.Uninstall;
  TAtlasIdeUnitSearch.Uninstall;
  TAtlasIdeGenerate.Uninstall;
  TAtlasEditorTestUnitLens.OnSwitchTestUnit := nil;
  TAtlasEditorHover.OnProblemAction := nil;
  TAtlasEditorHover.OnVisualize := nil;
  TAtlasIdeEditorCommands.Uninstall;
  TAtlasIdeImpact.Uninstall;
  TAtlasIdeResults.Uninstall;
  CommandsInstalled := False;
end;

procedure StartUndo;
begin
  // Adapter des Kerns setzt nur die Kompositionswurzel ein (A-09).
  TAtlasIdeUndoTarget.DiskFactory :=
    function(const AHooks: TAtlasUndoDiskHooks): IAtlasUndoTarget
    var
      Disk: TAtlasUndoDiskTarget;
    begin
      Disk := TAtlasUndoDiskTarget.Create;
      Disk.OnAddToProject := AHooks.OnAddToProject;
      Disk.OnRemoveFromProject := AHooks.OnRemoveFromProject;
      Disk.OnRecycle := AHooks.OnRecycle;
      Result := Disk;
    end;
  TAtlasIdeUndo.StoreFactory :=
    function(const AFolder: string; AMaxBytes: Int64): IAtlasUndoStore
    begin
      Result := TAtlasUndoFileStore.Create(AFolder, AMaxBytes);
    end;
  TAtlasIdeUndo.Start(
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end,
    procedure(AText: string)
    begin
      TAtlasGuard.Log(AText);
    end);
end;

procedure StartUpdates;
begin
  Updates := TAtlasIdeUpdates.Create(nil);
  Updates.Start(TAtlasUpdates.StateFile, TAtlasHttpVersionSource.Create,
    procedure(AText: string)
    begin
      MessageLine(AText);
    end,
    procedure(AText: string)
    begin
      TAtlasGuard.Log(AText);
    end);
  // Zeile „Version“ im Statusfeld und in der Zustandskachel (#754).
  Updates.ShowStatus(TAtlasStatusRegistry.Default);
end;

procedure StartForms;
begin
  Forms := TAtlasIdeForms.Create(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.RunningSession;
    end,
    procedure(AText: string)
    begin
      if Manager <> nil then
        Manager.Report(AText);
    end);
end;

procedure StartCommandUsage;
begin
  CommandUsage := TAtlasIdeCommandUsage.Create;
  // Nach „Zählung zurücksetzen“: „Noch nie benutzt“ auf der Karte sofort.
  CommandUsage.OnReset :=
    procedure
    begin
      if (Welcome <> nil) and (Welcome.Discover <> nil) then
        Welcome.Discover.Refresh;
    end;
end;

procedure StartShortcutTips;
begin
  ShortcutTips := TAtlasIdeShortcutTips.Create(CommandUsage);
  ShortcutTips.CountAlways := TAtlasIdeSettings.Current.WelcomePage and TAtlasIdeSettings.Current.WelcomePageDiscover and
    TAtlasIdeSettings.Current.TipsUsageTracking;
end;

/// <summary>DUnitX-Tests (#69): Läufer mit dem Prozessläufer der Versionsverwaltung und Haken zu Build,
/// Problemen und Willkommensseite (A-09), dazu die Code Lens.</summary>
procedure StartTests;
begin
  Tests := TAtlasIdeTests.Create(
    function(ACancelled: TFunc<Boolean>): IAtlasVcsRunner
    begin
      Result := TAtlasVcsProcessRunner.Create(False, ACancelled);
    end);
  // Vor den Tests bauen: über den Läufer der Builds auf Auftrag (#261), Auftraggeber "tests".
  Tests.OnBuild :=
    function(const AProject: string; const ADone: TAtlasTestsBuildDone; out AReason: string): Boolean
    var
      Request: TAtlasBuildRequest;
    begin
      if BuildRunner = nil then
      begin
        AReason := TAtlasStrings.Text(TAtlasTextId.TestsNoBuildRunner);
        Exit(False);
      end;
      Request := Default(TAtlasBuildRequest);
      Request.Project := AProject;
      Request.Kind := TAtlasCompileKind.Make;
      Result := BuildRunner.Start(Request, TAtlasTestRun.RequestedBy,
        procedure(const AReport: TAtlasBuildReport; const AError: string)
        begin
          ADone(AReport.Succeeded, AReport.Project.OutputFile, AError);
        end, AReason);
    end;
  Tests.OnProblems :=
    procedure(const AProblems: TArray<TPair<string, TAtlasProblem>>)
    begin
      if TAtlasProblemsController.Current <> nil then
        TAtlasProblemsController.Current.SetTests(AProblems);
    end;
  Tests.OnFinished :=
    procedure(const AProject: string; const ATests: TAtlasProjectTests)
    begin
      if (Welcome <> nil) and (Welcome.Projects <> nil) then
        TAtlasGuard.Run(TAtlasFeature.WelcomePage,
          procedure
          begin
            Welcome.Projects.RecordTests(AProject, ATests);
            // Schnellaktion „Tests“ (#764): Ergebnis in der Zeile des Projekts.
            if Welcome.QuickActions <> nil then
              Welcome.QuickActions.TestsFinished(AProject, ATests);
          end);
    end;
  Tests.OnLastFailed :=
    function(AProject: string): TArray<string>
    begin
      Result := TAtlasIdeProjects.LastFailedTests(AProject);
    end;
  // Einzelner Test ausführen bzw. debuggen (#585), auch aus dem Kontextmenü (A-09: Haken der Editorbefehle).
  TestDebugger := TAtlasIdeTestDebugger.Create(Tests);
  TAtlasIdeEditorCommands.OnRunTest :=
    procedure
    begin
      if TestDebugger <> nil then
        TAtlasGuard.Run(TAtlasFeature.Build, TestDebugger.RunAtCursor);
    end;
  TAtlasIdeEditorCommands.OnDebugTest :=
    procedure
    begin
      if TestDebugger <> nil then
        TAtlasGuard.Run(TAtlasFeature.Build, TestDebugger.DebugAtCursor);
    end;
  TestsLens := TAtlasIdeTestsLens.Create(Tests, TestDebugger);
end;

procedure StopTests;
begin
  // Erst die Lens (sie zeigt auf Läufer und Debugger-Teil), dann der Debugger-Teil (stellt eine laufende Sitzung
  // zurück), dann der Läufer; seine Probleme verschwinden mit ihm.
  TAtlasIdeEditorCommands.OnRunTest := nil;
  TAtlasIdeEditorCommands.OnDebugTest := nil;
  FreeAndNil(TestsLens);
  FreeAndNil(TestDebugger);
  FreeAndNil(Tests);
  if TAtlasProblemsController.Current <> nil then
    TAtlasProblemsController.Current.ClearTests;
end;

/// <summary>Prozessstart der Projektaufgaben (Adapter, #900); eigene Routine, damit die Referenz nichts aus
/// StartTasks einfängt.</summary>
function TaskProcess: TAtlasTaskProcessRun;
begin
  Result :=
    function(const ATask: TAtlasTaskDefinition; ACodePage: Integer; const ACancelled: TFunc<Boolean>;
      const AOnLine: TAtlasTaskLineProc): TAtlasTaskProcessResult
    begin
      Result := TAtlasTaskProcess.Run(ATask, ACodePage, ACancelled, AOnLine);
    end;
end;

/// <summary>Projektaufgaben (#900): Läufer mit Neubau nach bestandener Prüfung über den Build-Läufer (#261) und
/// Ergebnis für die Schnellaktion „Aufgaben“ (#764).</summary>
procedure StartTasks;
begin
  ProjectTasks := TAtlasIdeTasks.Create(TaskProcess());
  ProjectTasks.OnRebuild :=
    function(const AProject: TAtlasCompileProject; out AReason: string): Boolean
    var
      Request: TAtlasBuildRequest;
    begin
      if BuildRunner = nil then
      begin
        AReason := TAtlasStrings.Text(TAtlasTextId.TestsNoBuildRunner);
        Exit(False);
      end;
      Request := Default(TAtlasBuildRequest);
      Request.Project := AProject.FileName;
      Request.Kind := AProject.Kind;
      // Auftraggeber '' wie ein Build des Benutzers: Tests nach dem Build und die übrigen Teilnehmer laufen mit.
      Result := BuildRunner.Start(Request, '',
        procedure(const AReport: TAtlasBuildReport; const AError: string)
        begin
        end, AReason);
    end;
  ProjectTasks.OnFinished :=
    procedure(const AProject: string; const ARun: TAtlasTaskRun)
    begin
      if (Welcome <> nil) and (Welcome.QuickActions <> nil) and (AProject <> '') then
        TAtlasGuard.Run(TAtlasFeature.WelcomePage,
          procedure
          begin
            Welcome.QuickActions.TaskFinished(AProject, ARun);
          end);
    end;
end;

procedure StopTasks;
begin
  // Laufende Aufgaben enden mit dem Läufer; ihre Befunde verschwinden mit ihm. Schutznetz: Die Befunde
  // gehen auch dann weg, wenn der Abbau des Läufers scheitert.
  try
    FreeAndNil(ProjectTasks);
  finally
    if TAtlasProblemsController.Current <> nil then
      TAtlasProblemsController.Current.ClearTasks;
  end;
end;

const
  StartProfileExtra = 'startProfile';

/// <summary>Startprofil im Zusatzfeld der Statusleiste (#575); ohne startProfiles.statusField kein Feld.</summary>
procedure ShowStartProfileStatus(const AText, AHint: string);
begin
  if StatusField = nil then
    Exit;
  if (AText = '') or not TAtlasIdeSettings.Current.StartProfilesStatusField then
  begin
    StatusField.SetExtra(StartProfileExtra, '', '', nil);
    Exit;
  end;
  StatusField.SetExtra(StartProfileExtra, AText, AHint,
    procedure(APoint: TPoint)
    begin
      TAtlasIdeStartProfiles.ShowPicker;
    end);
end;

procedure StartStartProfiles;
begin
  TAtlasIdeStartProfiles.SetStatusHandler(ShowStartProfileStatus);
  TAtlasIdeStartProfiles.Start;
end;

procedure StartDisplayRules;
begin
  // Nur eine laufende Sitzung; die Regeln warten sonst auf den nächsten Versuch.
  TAtlasIdeDisplayRules.Start(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.RunningSession;
    end);
end;

procedure StopStartProfiles;
begin
  // Stop meldet noch Text '' und entfernt so das Feld; danach kein Empfänger mehr.
  TAtlasIdeStartProfiles.Stop;
  TAtlasIdeStartProfiles.SetStatusHandler(nil);
end;

procedure StartPalette;
begin
  RegisterPalette;
  // Atlas-Befehle zeigen ihre Taste (#520).
  Palette.ShortCutOf :=
    function(AId: string): string
    begin
      Result := TAtlasIdeKeyMap.AtlasShortCut(AId);
    end;
  if QuickToggles <> nil then
    QuickToggles.RegisterCommands(Palette);
  if DiagnosticMode <> nil then
    DiagnosticMode.RegisterCommands(Palette);
  if Setup <> nil then
    Setup.RegisterCommands(Palette);
  if KeyMap <> nil then
    KeyMap.RegisterCommands(Palette);
  // Issues in der Palette (#1270): die Quelle aus „Meine Issues“, erst beim Öffnen gefragt (Willkommensseite
  // entsteht ggf. später, Stop löst sie).
  Palette.SourceOf :=
    function: IAtlasPaletteSource
    begin
      Result := nil;
      if (Welcome <> nil) and (Welcome.Issues <> nil) then
        Result := Welcome.Issues.PaletteSearch;
    end;
end;

procedure StartNotes;
begin
  TAtlasIdeNotes.Start(
    procedure(AText: string)
    begin
      MessageLine(AText);
    end);
  NotesStarted := True;
end;

procedure StopNotes;
begin
  TAtlasIdeNotes.Release;
  NotesStarted := False;
end;

procedure StartBookmarks;
begin
  TAtlasIdeBookmarks.Start(
    procedure(AText: string)
    begin
      MessageLine(AText);
    end,
    // Hinweise der schnellen Lesezeichen (#1104) im Statusfeld.
    procedure(AText: string)
    begin
      if StatusField <> nil then
        StatusField.SetExtra('quickBookmarks', AText, '', nil);
    end);
  BookmarksStarted := True;
end;

procedure StopBookmarks;
begin
  TAtlasIdeBookmarks.Release;
  BookmarksStarted := False;
end;

procedure StartDebugExceptions;
begin
  TAtlasIdeDebugExceptions.Start(
    procedure(AText: string)
    begin
      MessageLine(AText);
    end);
end;

procedure StartDebugOwnCode;
begin
  TAtlasIdeDebugOwnCode.Start(
    procedure(AText: string)
    begin
      MessageLine(AText);
    end);
end;

procedure StartDebugExceptionBar;
begin
  TAtlasIdeDebugExceptionBar.Start(
    procedure(AText: string)
    begin
      MessageLine(AText);
    end, TAtlasStatusRegistry.Default);
end;

procedure StartDebugInlineValues;
begin
  // Fragt den Server nur, wenn er ohnehin läuft.
  TAtlasIdeDebugInlineValues.Start(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.RunningSession;
    end);
end;

/// <summary>„kein Zugriff auf Wert“ erklären (#840): Erklärung und Korrekturen im Hover; der Tooltip kennt die
/// Debug-Schicht nicht (A-09).</summary>
procedure StartDebugUnavailable;
begin
  // Fragt den Server nur, wenn er ohnehin läuft.
  TAtlasIdeDebugUnavailable.Start(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.RunningSession;
    end,
    procedure(AText: string)
    begin
      MessageLine(AText);
    end);
  TAtlasEditorHover.OnExplain :=
    function(const AValue: TAtlasDebugValue; const ADone: TAtlasDebugValueEvent): TAtlasDebugValue
    begin
      Result := TAtlasIdeDebugUnavailable.Explain(AValue, ADone);
    end;
  TAtlasEditorHover.OnDebugFix :=
    procedure(const AValue: TAtlasDebugValue; AFix: Integer)
    begin
      TAtlasIdeDebugUnavailable.Fix(AValue, AFix);
    end;
end;

procedure StartDebugDialogCompletion;
begin
  // Fragt den Server nur, wenn er ohnehin läuft.
  TAtlasIdeDebugDialogCompletion.Start(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.RunningSession;
    end,
    procedure(AText: string)
    begin
      LogLine(AText);
    end,
    function(const AHistory: TFunc<TArray<string>>): IAtlasCompletionProvider
    var
      Provider: TAtlasExpressionCompletionProvider;
    begin
      Provider := TAtlasExpressionCompletionProvider.Create(
        function: TLspSession
        begin
          Result := nil;
          if Manager <> nil then
            Result := Manager.RunningSession;
        end, AHistory,
        function(AResponse: TJSONValue): TAtlasCompletionItems
        begin
          Result := TAtlasServerCompletionProvider.ItemsFromLsp(AResponse);
        end, TAtlasExpressionCompletionProvider.DefaultTimeoutMs);
      Provider.HistoryCaption := TAtlasStrings.Text(TAtlasTextId.DebugExpressionHistory);
      Result := Provider;
    end);
  TAtlasIdeDebugDialogCompletion.ApplySettings;
end;

procedure StartDebugEvaluate;
begin
  // Fragt den Server nur, wenn er ohnehin läuft.
  TAtlasIdeDebugEvaluate.Start(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.RunningSession;
    end);
end;

/// <summary>Zugriffsverletzung erklären (#865): Knöpfe der Leiste über den Datenfluss (#690) und das Fenster
/// „Auswerten“ (#784); die Debug-Schicht kennt beide nicht.</summary>
procedure StartDebugAccessViolation;
begin
  // Fragt den Server nur, wenn er ohnehin läuft.
  TAtlasIdeDebugAccessViolation.Start(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.RunningSession;
    end,
    procedure(AText: string)
    begin
      MessageLine(AText);
    end);
  TAtlasIdeDebugAccessViolation.SetWhereAssigned(
    procedure(const AFileName: string; ALine, ACharacter: Integer; const AName: string)
    begin
      TAtlasIdeResults.ShowDataFlow(TAtlasDataFlowDirection.Sources, AFileName, ALine, ACharacter, AName);
    end);
  TAtlasIdeDebugAccessViolation.SetEvaluate(
    procedure(const AExpression: string)
    begin
      TAtlasIdeDebugEvaluate.ShowWindow(AExpression);
    end);
end;

procedure ReleaseDebugUnavailable;
begin
  TAtlasEditorHover.OnExplain := nil;
  TAtlasEditorHover.OnDebugFix := nil;
  TAtlasIdeDebugUnavailable.Release;
end;

const
  CompilerSwitchesExtra = 'compilerSwitches';

/// <summary>Wirksame Compiler-Schalter (#558): Fenster und Zusatzfeld der Statusleiste mit den Abweichungen.
/// </summary>
procedure StartCompilerSwitches;
begin
  // Fragt den Server nur, wenn er ohnehin läuft.
  TAtlasIdeCompilerSwitches.Start(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.RunningSession;
    end,
    procedure(const AText, AHint: string)
    begin
      if StatusField = nil then
        Exit;
      if AText = '' then
      begin
        StatusField.SetExtra(CompilerSwitchesExtra, '', '', nil);
        Exit;
      end;
      StatusField.SetExtra(CompilerSwitchesExtra, AText, AHint,
        procedure(APoint: TPoint)
        begin
          TAtlasIdeCompilerSwitches.ShowWindow;
        end);
    end);
end;

/// <summary>Fenster „Atlas-Prüfung“ (#909): Code-Aktionen, Optionsseite, Serverbefehle und Meldungen über
/// Haken; F8/Umschalt+F8 gehen bei sichtbarem Fenster durch dessen Liste.</summary>
procedure StartProblemsWindow;
var
  Hooks: TAtlasIdeProblemsHooks;
begin
  Hooks.ApplyTagged :=
    procedure(AProblem: TAtlasProblem; ATag: string)
    begin
      TAtlasIdeEditorCommands.ApplyTagged(TLspRange.Create(AProblem.StartLine, AProblem.StartCharacter,
        AProblem.EndLine, AProblem.EndCharacter), ATag);
    end;
  Hooks.ConfigureRule :=
    procedure(ARule: string)
    begin
      TAtlasGuard.Run(TAtlasFeature.Settings,
        procedure
        begin
          TAtlasOptionsRegistration.ShowRule(ARule);
        end);
    end;
  Hooks.Command :=
    procedure(const ACommand, AArgumentsJson: string; const ADone: TProc<TJSONValue>)
    begin
      // Im Hintergrund (#874).
      if Manager <> nil then
        Manager.RunServerCommandAsync(ACommand, AArgumentsJson, 10000, ADone)
      else
        ADone(nil);
    end;
  Hooks.Message :=
    procedure(AText: string)
    begin
      MessageLine(AText);
    end;
  Hooks.Indexing :=
    function(out APercent: Integer): Boolean
    begin
      APercent := -1;
      Result := (Manager <> nil) and Manager.ServerIndexing(APercent);
    end;
  // „Für diesen Befund ein Issue anlegen …“ (#1268): Regel, Meldung, Fundstelle und Zeile je Befund.
  Hooks.CreateIssue :=
    procedure(AFindings: TArray<TAtlasFinding>)
    var
      mItems: TArray<TAtlasNewIssueFinding>;
      mFinding: TAtlasFinding;
    begin
      mItems := nil;
      for mFinding in AFindings do
        mItems := mItems + [TAtlasNewIssueFinding.Create(mFinding.Rule,
          mFinding.MessageText(TAtlasIdeSettings.Current.ProblemsShowCompilerCode), mFinding.Location,
          mFinding.LineText)];
      TAtlasGuard.Run(TAtlasFeature.WelcomePage,
        procedure
        begin
          TAtlasIdeNewIssue.FromFindings(mItems);
        end);
    end;
  Hooks.CanCreateIssue :=
    function: Boolean
    begin
      Result := TAtlasIdeNewIssue.Enabled;
    end;
  TAtlasIdeProblems.Start(Hooks);
  TAtlasIdeEditorCommands.OnStepList :=
    function(AForward: Boolean): Boolean
    begin
      Result := TAtlasIdeProblems.StepWindow(AForward);
    end;
  ProblemsWindowStarted := True;
end;

procedure StopProblemsWindow;
begin
  TAtlasIdeEditorCommands.OnStepList := nil;
  TAtlasIdeProblems.Release;
  ProblemsWindowStarted := False;
end;

/// <summary>Gezeichnete Elemente und Ausblenden am Element (#628); „Einstellungen dazu …“ öffnet die
/// Optionsseite.</summary>
procedure StartHide;
begin
  TAtlasIdeElements.Start;
  TAtlasIdeHide.Start;
  TAtlasIdeHide.OnShowSetting :=
    procedure(AKey: string)
    begin
      TAtlasGuard.Run(TAtlasFeature.Settings,
        procedure
        begin
          TAtlasOptionsRegistration.ShowSetting(AKey);
        end);
    end;
  HideStarted := True;
end;

procedure StopHide;
begin
  TAtlasIdeHide.OnShowSetting := nil;
  TAtlasIdeHide.Stop;
  TAtlasIdeElements.Stop;
  HideStarted := False;
end;

procedure StartGutterMarks;
begin
  GutterMarks := TAtlasIdeGutterMarks.Create;
  GutterMarks.Add(TAtlasIdeNotesGutter.Create);
  GutterMarks.Add(TAtlasIdeBookmarksGutter.Create);
  // Rekursionssymbole (#623); fragt den Server nur, wenn er ohnehin läuft.
  GutterMarks.Add(TAtlasIdeRecursionGutter.Create(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.RunningSession;
    end));
end;

procedure StartGutterColumn;
begin
  // Fragt den Server nur, wenn er ohnehin läuft.
  GutterColumn := TAtlasIdeGutterColumn.Create(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.RunningSession;
    end,
    procedure
    begin
      TAtlasIdeEditorCommands.CodeActions;
    end,
    procedure(const AAction: TLspCodeAction)
    begin
      TAtlasIdeEditorCommands.ApplyAction(AAction);
    end);
end;

procedure StartQuickColumn;
begin
  QuickColumn := TAtlasIdeQuickColumn.Create;
end;

procedure StopQuickColumn;
begin
  TAtlasIdeQuickChord.Release;
  FreeAndNil(QuickColumn);
end;

procedure StartSelectionMatches;
begin
  SelectionMatches := TAtlasIdeSelectionMatches.Create;
end;

procedure StartExitPoints;
begin
  // Fragt den Server nur, wenn er ohnehin läuft.
  TAtlasIdeExitPoints.Install(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.RunningSession;
    end);
end;

procedure StopExitPoints;
begin
  TAtlasIdeExitPoints.Uninstall;
end;

procedure StartReassigned;
begin
  // Fragt den Server nur, wenn er ohnehin läuft.
  TAtlasIdeReassigned.Install(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
        Result := Manager.RunningSession;
    end);
end;

procedure StopReassigned;
begin
  TAtlasIdeReassigned.Uninstall;
end;

procedure StartCompletionKey;
begin
  CompletionKey := TAtlasIdeKeyBinding.Create('Atlas.Completion', 'Atlas-Vervollständigung',
    TAtlasFeature.Completion,
    procedure
    begin
      if Manager <> nil then
        Manager.OpenCompletion;
    end);
end;

procedure StartSignatureKey;
begin
  SignatureKey := TAtlasIdeKeyBinding.Create('Atlas.Signature', 'Atlas-Parameter-Hint',
    TAtlasFeature.Signature,
    procedure
    begin
      if Manager <> nil then
        Manager.OpenSignature;
    end);
end;

procedure WatchKeys;
begin
  KeysWatched := True;
  TAtlasMainThread.ForceQueue(TAtlasFeature.Settings,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Settings,
        procedure
        begin
          TAtlasIdeKeys.ReportForeignCompletion;
        end);
    end);
  // Neue Packages können Tasten belegen oder eine eigene Vervollständigung mitbringen (#494).
  TAtlasIdeKeys.WatchPackages(
    procedure
    begin
      RebindKeys;
      TAtlasIdeKeys.ReportForeignCompletion;
      // Neue Belegungen anderer Erweiterungen gegen die Atlas-Tasten prüfen (#520).
      if KeyMap <> nil then
        KeyMap.CheckNow;
      // Neue Aktionen und Tasten für die Tastenkürzel-Tipps (#600).
      if ShortcutTips <> nil then
        ShortcutTips.KeysChanged;
    end);
end;

procedure UnwatchKeys;
begin
  TAtlasIdeKeys.UnwatchPackages;
  KeysWatched := False;
end;

/// <summary>Zugang zum Build-Server für AJob abfragen und im Anmeldespeicher von Windows ablegen (#763); beide
/// Felder leer entfernt ihn. True, wenn sich etwas geändert hat.</summary>
function EnterCiCredentials(const AJob: TAtlasCiJob): Boolean;
var
  User, Token, Stored: string;
  Ok: Boolean;
begin
  Result := False;
  User := '';
  Stored := '';
  TAtlasCiCredentials.Read(AJob.CredentialTarget, User, Stored);
  // Nur der Benutzer wird vorbelegt; das gespeicherte Token wird nie angezeigt.
  if Stored <> '' then
  begin
    UniqueString(Stored);
    FillChar(PChar(Stored)^, Length(Stored) * SizeOf(Char), 0);
  end;
  Stored := '';
  Token := '';
  if not TAtlasCiLoginPrompt.Ask(AJob.Server, User, Token) then
    Exit;
  if (User = '') and (Token = '') then
  begin
    Ok := TAtlasCiCredentials.Delete(AJob.CredentialTarget);
    if Ok then
      GuardWarning(TAtlasStrings.Text(TAtlasTextId.CiLoginRemoved))
    else
      GuardWarning(TAtlasStrings.Text(TAtlasTextId.CiLoginFailed));
    Exit(Ok);
  end;
  if (User = '') or (Token = '') then
  begin
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.CiLoginIncomplete));
    Exit;
  end;
  Ok := TAtlasCiCredentials.Write(AJob.CredentialTarget, User, Token);
  UniqueString(Token);
  FillChar(PChar(Token)^, Length(Token) * SizeOf(Char), 0);
  // Anonym: weder Server noch Benutzer.
  if Ok then
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.CiLoginSaved))
  else
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.CiLoginFailed));
  Result := Ok;
end;

function CreateWelcomeTestResults(const AProjects: IAtlasProjectsSource): TAtlasIdeTestResults;
begin
  Result := TAtlasIdeTestResults.Create(AProjects,
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end);
  // „Fehlgeschlagene erneut ausführen“: der Läufer aus #69 (sichtbar nur mit TestRun).
  Result.OnRunTests :=
    procedure(const AProject: string; const ATests: TArray<string>)
    begin
      if Tests <> nil then
        Tests.RunTests(AProject, ATests);
    end;
  // „Im Debugger“: #585.
  Result.OnDebugTest :=
    function(const AProject, AFullName: string; out AReason: string): Boolean
    begin
      AReason := '';
      Result := False;
      if TestDebugger <> nil then
        Result := TestDebugger.DebugByName(AProject, AFullName, AReason);
    end;
  Result.OnLocateTest :=
    function(const AProject, AFullName: string; out AFileName: string; out ALine: Integer): Boolean
    begin
      Result := TAtlasIdeTestDebugger.LocateByName(AProject, AFullName, AFileName, ALine);
    end;
  // CI-Anbieter: Jenkins als erster Adapter.
  Result.ProviderFactory :=
    function(const AName: string): IAtlasCiProvider
    begin
      Result := nil;
      if SameText(AName, TAtlasJenkinsProvider.ProviderName) then
        Result := TAtlasJenkinsProvider.Create;
    end;
  // Im Hintergrund-Thread: Zugang aus dem Anmeldespeicher, ohne Dialog.
  Result.TransportFactory :=
    function(const AJob: TAtlasCiJob): IAtlasCiTransport
    var
      User, Token: string;
    begin
      User := '';
      Token := '';
      TAtlasCiCredentials.Read(AJob.CredentialTarget, User, Token);
      Result := TAtlasCiHttpTransport.Create(AJob.Server, User, Token);
      if Length(Token) > 0 then
      begin
        UniqueString(Token);
        FillChar(PChar(Token)^, Length(Token) * SizeOf(Char), 0);
      end;
    end;
  Result.OnCredentials := EnterCiCredentials;
end;

const
  IssueTimeExtra = 'issueTime';

function CreateWelcomeIssues(AProjects: TAtlasIdeProjects): TAtlasIdeIssues;
begin
  Result := TAtlasIdeIssues.Create(AProjects,
    procedure(AText: string)
    begin
      // Nur Meldungsansicht: Die Zeilen können Branch-Namen enthalten.
      MessageLine(AText);
    end);
  // Anbieter, Transport und Zugang wie auf der Optionsseite (#1260): dieselbe Umsetzung (TrackerAccess).
  Result.ProviderFactory :=
    function(const AName: string): IAtlasTrackerProvider
    begin
      Result := TrackerAccess.Provider(AName);
    end;
  // Im Hintergrund-Thread: Token aus dem Anmeldespeicher, ohne Dialog; ohne Token kein Transport (kein Netz).
  Result.TransportFactory :=
    function(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): IAtlasCiTransport
    begin
      Result := TrackerAccess.Transport(AProvider, ATarget);
    end;
  Result.OnCredentials :=
    function(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget): Boolean
    begin
      Result := TrackerAccess.EnterToken(AProvider, ATarget);
    end;
  // Zeiterfassung (#1267): „ATL-123 · 1:25“ als Zusatzfeld im Statusfeld, Klick öffnet das Menü der Uhr.
  Result.OnTimeStatus :=
    procedure(const AText, AHint: string; const AOnClick: TProc<TPoint>)
    begin
      if StatusField <> nil then
        StatusField.SetExtra(IssueTimeExtra, AText, AHint, AOnClick);
    end;
  // Knopf „Tracker-Einstellungen …“ der Issue-Vorschau (#1264).
  Result.OnSettings :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Settings,
        procedure
        begin
          TAtlasOptionsRegistration.ShowSetting('IssuesConnections');
        end);
    end;
  // „zuordnen …“ (#1261): Seite Issue-Tracker mit vorbefüllter Zeile der Tabelle Projekte.
  Result.OnAssignProject :=
    procedure(AMatch: string)
    begin
      TAtlasOptionsRegistration.ShowTrackerProject(AMatch);
    end;
  // „Abfragen bearbeiten …“ (#1262): Seite Issue-Tracker bei der Tabelle Abfragen.
  Result.OnEditQueries :=
    procedure
    begin
      TAtlasOptionsRegistration.ShowSetting('IssuesQueries');
    end;
end;

procedure StartWelcome;
begin
  Welcome := TAtlasIdeWelcome.Create(
    function: TAtlasServerInfo
    begin
      if Manager <> nil then
        Result := Manager.ServerInfo
      else
        Result := Default(TAtlasServerInfo);
    end,
    function(out APercent: Integer): Boolean
    begin
      APercent := -1;
      Result := (Manager <> nil) and Manager.ServerIndexing(APercent);
    end,
    function: Integer
    begin
      Result := -1;
      if StatusLines <> nil then
        Result := StatusLines.Units;
    end,
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end);
  // Suchfeld im Kopf (#760): Befehle aus der Palette, sobald es sie gibt.
  Welcome.Search := TAtlasIdeWelcomeSearch.Create(
    function: TArray<TAtlasCommand>
    begin
      Result := nil;
      if Palette <> nil then
        Result := Palette.AtlasCommands;
    end,
    procedure(AId: string)
    begin
      if Palette <> nil then
        Palette.Execute(AId);
    end);
  // Karte „Neu in Atlas“ (#756): „Ausprobieren“ führt Atlas-Befehle der Palette aus.
  Welcome.WhatsNew := TAtlasIdeWhatsNew.Create(
    function(AId: string): Boolean
    var
      Command: TAtlasCommand;
    begin
      Result := False;
      if Palette <> nil then
        for Command in Palette.AtlasCommands do
          if SameText(Command.Id, AId) then
            Exit(True);
    end,
    procedure(AId: string)
    begin
      if Palette <> nil then
        Palette.Execute(AId);
    end,
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end);
  // Bereich „Projekte“ (#592): Zustand je Projekt aus den Projekt-Zusammenfassungen.
  Welcome.Projects := TAtlasIdeProjects.Create(
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end);
  // Bereich „Projektverlauf“ (#758): Linien über die letzten Builds des in „Projekte“ gewählten Projekts.
  Welcome.Trends := TAtlasIdeTrends.Create(Welcome.Projects);
  // Bereich „Testergebnisse“ (#763): letzter Testlauf (#69) und letzter Build des Build-Servers je Projekt.
  Welcome.TestResults := CreateWelcomeTestResults(Welcome.Projects);
  // Bereich „Meine Issues“ (#765): offene Issues aus GitHub bzw. YouTrack (Tracker aus .atlas), „Beginnen“ über die
  // VCS-Schnittstelle (#571), aktuelles Issue im Statusfeld (#591); Token im Anmeldespeicher wie #763.
  Welcome.Issues := CreateWelcomeIssues(Welcome.Projects);
  // „Issue anlegen …“ (#1268): Tracker, Transport und „Beginnen“ wie „Meine Issues“.
  TAtlasIdeNewIssue.Start(Welcome.Issues,
    procedure(AText: string)
    begin
      MessageLine(AText);
    end);
  // Bereich „Nicht gesichert“ (#762): nicht Gesichertes je Projekt über die VCS-Schnittstelle (#571).
  Welcome.Unsaved := TAtlasIdeUnsaved.Create(
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end);
  // Schnellaktionen je Projekt (#764) in „Projekte“ und „Weiterarbeiten“: bauen über den Läufer der Builds auf
  // Auftrag (#261, Release-Wächter #533), Tests über #69, Startprofile über #575. Meldungen tragen Pfade und gehen
  // deshalb nur in die Meldungsansicht.
  Welcome.QuickActions := TAtlasIdeQuickActions.Create(Welcome.Projects,
    procedure(AText: string)
    begin
      MessageLine(AText);
    end);
  Welcome.QuickActions.OnBuild :=
    function(const AProject, AConfiguration, APlatform: string; const ADone: TAtlasQuickBuildDone;
      out AReason: string): Boolean
    var
      Request: TAtlasBuildRequest;
    begin
      if BuildRunner = nil then
      begin
        AReason := TAtlasStrings.Text(TAtlasTextId.TestsNoBuildRunner);
        Exit(False);
      end;
      Request := Default(TAtlasBuildRequest);
      Request.Project := AProject;
      Request.Kind := TAtlasCompileKind.Build;
      Request.Configuration := AConfiguration;
      Request.Platform := APlatform;
      Result := BuildRunner.Start(Request, TAtlasWelcomeQuickActions.RequestedBy,
        procedure(const AReport: TAtlasBuildReport; const AError: string)
        begin
          ADone(AReport.Succeeded, AError);
        end, AReason);
    end;
  Welcome.QuickActions.OnTests :=
    function(const ATestProject: string; out AReason: string): Boolean
    begin
      if Tests = nil then
      begin
        AReason := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickReasonTestsOff);
        Exit(False);
      end;
      Result := Tests.RunProject(ATestProject, AReason);
    end;
  Welcome.QuickActions.OnTestsBusy :=
    function: Boolean
    begin
      Result := (Tests <> nil) and Tests.Busy;
    end;
  Welcome.QuickActions.OnIdeBusy :=
    function: Boolean
    begin
      Result := ((BuildRunner <> nil) and BuildRunner.Busy) or ((Tests <> nil) and Tests.Busy);
    end;
  Welcome.QuickActions.OnProfiles :=
    function(const AProject: string; out AActive: string): TArray<string>
    var
      Entry: TAtlasStartProfileEntry;
    begin
      Result := nil;
      for Entry in TAtlasIdeStartProfiles.Profiles(AProject) do
        Result := Result + [Entry.Profile.Name];
      AActive := TAtlasIdeStartProfiles.ActiveName(AProject);
    end;
  Welcome.QuickActions.OnRun :=
    function(const AProject, AProfile: string; out AReason: string): Boolean
    begin
      Result := TAtlasIdeStartProfiles.Run(AProject, AProfile, True, AReason);
    end;
  // Knopf „Aufgaben ▾“ (#900): Projektaufgaben aus der atlas.json des Projekts über den Aufgabenläufer.
  Welcome.QuickActions.OnTaskNames :=
    function(const AProject: string): TArray<string>
    begin
      Result := nil;
      if TasksVisible then
        Result := ProjectTasks.TaskNamesOf(AProject);
    end;
  Welcome.QuickActions.OnRunTask :=
    function(const AProject, AName: string; out AReason: string): Boolean
    begin
      AReason := '';
      if not TasksVisible then
      begin
        AReason := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickReasonTasksOff);
        Exit(False);
      end;
      Result := ProjectTasks.RunInProject(AProject, AName, AReason);
    end;
  // Bereich „Weiterarbeiten“ (#755): Arbeitsstand beim Schließen, eingehende Commits (#571) und „Gemerkt“.
  Welcome.ContinueWork := TAtlasIdeContinue.Create(
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end);
  // „Anmeldung am Server nötig – prüfen …“ (#1287): Seite Versionsverwaltung, Zeile des Ordners prüfen.
  Welcome.ContinueWork.OnServerAccess :=
    procedure(AFolder: string)
    begin
      TAtlasOptionsRegistration.ShowVcsServer(AFolder);
    end;
  // Zustandskachel „Atlas“ (#754): dieselben Zeilen wie das Statusfeld (#591).
  Welcome.State := CreateWelcomeState;
  // Karte „Atlas entdecken“ (#757): Befehle und Tasten aus der Palette, „Ausprobieren“ führt sie aus.
  Welcome.Discover := TAtlasIdeDiscover.Create(
    function: TArray<TAtlasCommand>
    begin
      Result := nil;
      if Palette <> nil then
        Result := Palette.AtlasCommands;
    end,
    procedure(AId: string)
    begin
      if Palette = nil then
        Exit;
      // Tipp zur Befehlspalette: „Ausprobieren“ öffnet sie.
      if SameText(AId, TAtlasShortcutTips.PaletteCommandId) then
        Palette.Show
      else
        Palette.Execute(AId);
    end,
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end);
  // Bereich „Hilfe und Rückmeldung“ (#766): „Tastenkürzel“ zeigt die Übersicht aus #520 mit allen Kürzeln.
  Welcome.Help := TAtlasIdeHelp.Create(
    procedure
    begin
      if KeyMap <> nil then
        KeyMap.ShowAll;
    end);
  // Bereich „Projekt für Atlas einrichten“ (#759): atlas.json, Baseline (#97), Suchpfade und „Neu mit Atlas“.
  Welcome.Setup := TAtlasIdeSetup.Create(
    procedure(AText: string)
    begin
      // Nur Meldungsansicht: Die Zeilen enthalten Pfade.
      MessageLine(AText);
    end,
    function(const AProject: string; const ADone: TAtlasSetupBaselineDone): string
    begin
      Result := StartBaselineUpdate(AProject, ADone);
    end,
    procedure(AKind: TAtlasNewFileKind)
    var
      User: TAtlasSnippetList;
    begin
      User := nil;
      if (Manager <> nil) and (Manager.Completion <> nil) then
        User := Manager.Completion.FileSnippets;
      TAtlasIdeNewFile.Show(AKind, User,
        procedure(AText: string)
        begin
          MessageLine(AText);
        end);
    end);
  // Seite anpassen (#767): Rechtsklick „Ausblenden“ über den Weg von #628 (mit „Rückgängig“), „Einstellungen
  // dazu …“ auf der Optionsseite.
  Welcome.Layouts.OnHideSetting :=
    function(AKey: string; APoint: TPoint): Boolean
    begin
      Result := HideStarted and TAtlasIdeHide.HideSetting(AKey, APoint);
    end;
  Welcome.Layouts.OnShowSetting :=
    procedure(AKey: string)
    begin
      TAtlasGuard.Run(TAtlasFeature.Settings,
        procedure
        begin
          TAtlasOptionsRegistration.ShowSetting(AKey);
        end);
    end;
end;

function IssueHooks: TAtlasCodeLinksHooks;
var
  mHooks: TAtlasCodeLinksHooks;
begin
  // Alles über „Meine Issues“ (Tracker wie dort, Zwischenspeicher der Vorschau); ohne den Bereich wirkungslos.
  mHooks := Default(TAtlasCodeLinksHooks);
  mHooks.Target :=
    function(out ATarget: TAtlasTrackerTarget): Boolean
    begin
      ATarget := TAtlasTrackerTarget.Create('', '', '', '');
      Result := (Welcome <> nil) and (Welcome.Issues <> nil) and Welcome.Issues.CodeTarget(ATarget);
    end;
  mHooks.CommitPattern :=
    function: string
    begin
      Result := TAtlasIdeSettings.Current.IssuesCommitPattern;
    end;
  mHooks.Preview :=
    function: TAtlasIdeIssuePreview
    begin
      Result := nil;
      if (Welcome <> nil) and (Welcome.Issues <> nil) then
        Result := Welcome.Issues.IssuePreview;
    end;
  mHooks.Show :=
    procedure(const ATarget: TAtlasTrackerTarget; const AKey: string)
    begin
      if (Welcome <> nil) and (Welcome.Issues <> nil) then
        Welcome.Issues.ShowIssue(ATarget, AKey);
    end;
  mHooks.Browse :=
    procedure(const ATarget: TAtlasTrackerTarget; const AKey: string)
    begin
      if (Welcome <> nil) and (Welcome.Issues <> nil) then
        Welcome.Issues.BrowseIssue(ATarget, AKey);
    end;
  mHooks.Start :=
    procedure(const ATarget: TAtlasTrackerTarget; const AKey: string)
    begin
      if (Welcome <> nil) and (Welcome.Issues <> nil) then
        Welcome.Issues.StartIssue(ATarget, AKey);
    end;
  mHooks.CanStart :=
    function: Boolean
    begin
      Result := (Welcome <> nil) and (Welcome.Issues <> nil) and Welcome.Issues.CanStartIssue;
    end;
  Result := mHooks;
end;

procedure StartIssueLinks;
begin
  IssueLinks := TAtlasIdeCodeLinks.Create(IssueHooks);
end;

procedure StartBlameIssues;
begin
  // Dieselben Haken wie die Kennungen im Code; die Zeilenhistorie bekommt ihre Ergänzungen (kein Zyklus).
  BlameIssues := TAtlasIdeBlameLinks.Create(IssueHooks);
  TAtlasIdeLineChanges.SetBlameHooks(BlameIssues.LineHooks);
end;

procedure StopBlameIssues;
begin
  TAtlasIdeLineChanges.SetBlameHooks(Default(TAtlasBlameHooks));
  FreeAndNil(BlameIssues);
end;

procedure StopWelcome;
begin
  // Vor dem Bereich „Meine Issues“: wartet auf laufende Anfragen.
  TAtlasIdeNewIssue.Stop;
  FreeAndNil(Welcome);
  TAtlasWelcomeViews.Release;
  TAtlasWelcomeSections.ReleaseDefault;
end;

procedure StartMainMenu;
begin
  CreateMainMenu;
  MainMenu.OnRename := RenameSymbol;
  MainMenu.OnSetup :=
    procedure
    begin
      if Setup <> nil then
        Setup.ShowWindow;
    end;
  MainMenu.OnKeyMap :=
    procedure
    begin
      if KeyMap <> nil then
        KeyMap.ShowWindow;
    end;
  // Untermenü Aufgaben (#900): ohne Läufer bzw. mit tasks.enabled aus ausgeblendet.
  MainMenu.OnTasksMenu :=
    procedure(AMenu: TMenuItem)
    begin
      AMenu.Visible := TasksVisible;
      if AMenu.Visible then
        TAtlasGuard.Run(TAtlasFeature.Tasks,
          procedure
          begin
            ProjectTasks.FillMenu(AMenu);
          end);
    end;
  MainMenu.OnWelcome :=
    procedure(ACommand: TAtlasWelcomeCommand)
    begin
      if Welcome = nil then
        Exit;
      case ACommand of
        TAtlasWelcomeCommand.Start:
          Welcome.ShowStart;
        TAtlasWelcomeCommand.Apply:
          Welcome.ApplyLayout;
      else
        Welcome.ResetLayout;
      end;
    end;
  // Ansicht › Atlas › Board (#1272).
  MainMenu.OnBoard :=
    procedure
    begin
      if (Welcome <> nil) and (Welcome.Issues <> nil) and (Welcome.Issues.Board <> nil) then
        Welcome.Issues.Board.Show;
    end;
  MainMenu.OnIssueAttach :=
    procedure
    begin
      if (Welcome <> nil) and (Welcome.Issues <> nil) then
        Welcome.Issues.AttachPrompt;
    end;
end;

procedure StartEditInbox;
begin
  EditInbox := TAtlasIdeEditInbox.Create(
    procedure(const AText: string)
    begin
      GuardWarning(AText);
    end);
end;

/// <summary>Teile des Plugins in Startreihenfolge (Code-Review S-03); StopAll baut sie rückwärts ab.
/// Normal = nur im normalen Start, Safe = auch abgesichert, Minimal = immer (#722).</summary>
procedure AddFeatures;
begin
  Features := TAtlasFeatureTable.Create;
  Features.Add('Manager', TAtlasSafeLevel.Safe,
    function: Boolean
    begin
      Result := ManagerIndex >= 0;
    end,
    StartManager, StopManager);
  // Notifier und Hintergrundaufgaben nur im normalen Betrieb bzw. wenn ihr Schalter wieder an ist.
  Features.AddWanted('Compile',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel = TAtlasSafeLevel.Normal) or TAtlasIdeSettings.Current.CheckOnSave;
    end,
    function: Boolean
    begin
      Result := Compile <> nil;
    end,
    RegisterCompileEvents,
    procedure
    begin
      // Läufer und Bauen beim Öffnen melden sich bei den Ereignissen von Compile an; vorher gehen.
      FreeAndNil(OpenBuild);
      FreeAndNil(BuildInbox);
      FreeAndNil(BuildRunner);
      FreeAndNil(Compile);
      FreeAndNil(BuildSummary);
    end);
  Features.Add('Watchdog', TAtlasSafeLevel.Normal,
    function: Boolean
    begin
      Result := Watchdog <> nil;
    end,
    RegisterWatchdog, UnregisterWatchdog);
  Features.AddWanted('CheckOnSave',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := Compile <> nil;
    end,
    function: Boolean
    begin
      Result := CheckOnSave <> nil;
    end,
    StartCheckOnSave,
    procedure
    begin
      FreeAndNil(CheckOnSave);
    end);
  Features.Add('Commands', TAtlasSafeLevel.Safe,
    function: Boolean
    begin
      Result := CommandsInstalled;
    end,
    StartCommands, StopCommands);
  // Projektdatei .atlas (#486): in jeder Stufe, solange die Einstellung TeamFile an ist (abgesichert erst nach dem
  // Schnellschalter); liest nur eine Datei.
  Features.AddWanted('TeamFile',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := TAtlasIdeSettings.Current.TeamFile;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeTeamFile.Started;
    end,
    TAtlasIdeTeamFile.Start, TAtlasIdeTeamFile.Stop);
  // Builds für Claude Code (#261): nur im normalen Start, mit den Compile-Ereignissen und solange McpBuild an ist.
  Features.AddWanted('McpBuild',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.McpBuild and (BuildRunner <> nil);
    end,
    function: Boolean
    begin
      Result := BuildInbox <> nil;
    end,
    procedure
    begin
      BuildInbox := TAtlasIdeBuildInbox.Create(BuildRunner,
        procedure(const AText: string)
        begin
          GuardWarning(AText);
        end);
    end,
    procedure
    begin
      FreeAndNil(BuildInbox);
    end);
  // Beim Öffnen bauen: nur im normalen Start, mit den Compile-Ereignissen und solange BuildOnOpen an ist.
  Features.AddWanted('OpenBuild',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.BuildOnOpen and (Compile <> nil);
    end,
    function: Boolean
    begin
      Result := OpenBuild <> nil;
    end,
    StartOpenBuild,
    procedure
    begin
      FreeAndNil(OpenBuild);
    end);
  // uses nachziehen nach dem Umbenennen einer Unit (#512): ob es angeboten wird, entscheidet der Server
  // (refactoring.unitRenameFollowUp).
  Features.Add('UnitRename', TAtlasSafeLevel.Normal,
    function: Boolean
    begin
      Result := UnitRename <> nil;
    end,
    StartUnitRename,
    procedure
    begin
      FreeAndNil(UnitRename);
    end);
  // DUnitX-Tests (#69): nur im normalen Start und solange TestRun an ist; baut über BuildRunner, wenn er läuft.
  Features.AddWanted('Tests',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.TestRun;
    end,
    function: Boolean
    begin
      Result := Tests <> nil;
    end,
    StartTests, StopTests);
  // Projektaufgaben (#900): nur im normalen Start und solange tasks.enabled an ist.
  Features.AddWanted('Tasks',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.TasksEnabled;
    end,
    function: Boolean
    begin
      Result := ProjectTasks <> nil;
    end,
    StartTasks, StopTasks);
  // Startprofile (#575): nur im normalen Start und solange StartProfiles an ist; liest .atlas über TeamFile.
  Features.AddWanted('StartProfiles',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.StartProfiles;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeStartProfiles.Started;
    end,
    StartStartProfiles, StopStartProfiles);
  // Visualisierer für häufige Typen (#835): nur im normalen Start und solange debug.visualizers an ist.
  Features.AddWanted('Visualizers',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.DebugVisualizers;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeVisualizers.Started;
    end,
    procedure
    begin
      TAtlasIdeVisualizers.Start;
    end,
    procedure
    begin
      TAtlasIdeVisualizers.Stop;
    end);
  // Eigene Wertdarstellungen (#854): nur im normalen Start und solange debug.displayRules an ist.
  Features.AddWanted('DisplayRules',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.DebugDisplayRules;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeDisplayRules.Started;
    end,
    StartDisplayRules,
    procedure
    begin
      TAtlasIdeDisplayRules.Stop;
    end);
  // Änderungsprotokoll vor den Tasten: Strg+Alt+Z braucht es (#721).
  Features.Add('Undo', TAtlasSafeLevel.Safe,
    function: Boolean
    begin
      Result := TAtlasIdeUndo.Journal <> nil;
    end,
    StartUndo, TAtlasIdeUndo.Stop);
  // Update-Prüfung nur nach Zustimmung und höchstens einmal täglich (#495).
  Features.Add('Updates', TAtlasSafeLevel.Safe,
    function: Boolean
    begin
      Result := Updates <> nil;
    end,
    StartUpdates,
    procedure
    begin
      FreeAndNil(Updates);
    end);
  Features.Add('EditorKeys', TAtlasSafeLevel.Safe,
    function: Boolean
    begin
      Result := EditorKeys <> nil;
    end,
    procedure
    begin
      EditorKeys := TAtlasIdeEditorKeys.Create;
    end,
    procedure
    begin
      FreeAndNil(EditorKeys);
    end);
  // Designer-Notifier nur im normalen Betrieb (#722).
  Features.Add('Forms', TAtlasSafeLevel.Normal,
    function: Boolean
    begin
      Result := Forms <> nil;
    end,
    StartForms,
    procedure
    begin
      FreeAndNil(Forms);
    end);
  // Diagnosemodus (#479): ohne Einstellung nur Taste und Befehl, keine Messung.
  Features.Add('DiagnosticMode', TAtlasSafeLevel.Safe,
    function: Boolean
    begin
      Result := DiagnosticMode <> nil;
    end,
    procedure
    begin
      DiagnosticMode := TAtlasIdeDiagnosticMode.Create(TAtlasStatusRegistry.Default);
    end,
    procedure
    begin
      FreeAndNil(DiagnosticMode);
    end);
  // Einrichtung (#625): auch abgesichert, sie fragt den Server nie selbst und startet ihn nur auf Knopfdruck.
  Features.AddWanted('Setup',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel <> TAtlasSafeLevel.Minimal) and (StatusLines <> nil);
    end,
    function: Boolean
    begin
      Result := Setup <> nil;
    end,
    CreateSetup,
    procedure
    begin
      FreeAndNil(Setup);
    end);
  // Tastenkürzel-Übersicht (#520): auch abgesichert, sie liest nur die Belegungen der IDE.
  Features.Add('KeyMap', TAtlasSafeLevel.Safe,
    function: Boolean
    begin
      Result := KeyMap <> nil;
    end,
    procedure
    begin
      KeyMap := TAtlasIdeKeyMap.Create;
    end,
    procedure
    begin
      FreeAndNil(KeyMap);
    end);
  // Gemeinsame Zählung (#757): vor den Tastenkürzel-Tipps und der Willkommensseite, die sie nutzen; Abbau
  // danach, er speichert die Zählung.
  Features.Add('CommandUsage', TAtlasSafeLevel.Safe,
    function: Boolean
    begin
      Result := CommandUsage <> nil;
    end,
    StartCommandUsage,
    procedure
    begin
      FreeAndNil(CommandUsage);
    end);
  // Tastenkürzel-Tipps (#600): Beobachtung an oder aus nach shortcutTips.enabled (ApplySettings); zählt auch
  // für „Atlas entdecken“ (#757), solange die Karte und die Zählung an sind.
  Features.AddWanted('ShortcutTips',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel = TAtlasSafeLevel.Normal) and (CommandUsage <> nil);
    end,
    function: Boolean
    begin
      Result := ShortcutTips <> nil;
    end,
    StartShortcutTips,
    procedure
    begin
      FreeAndNil(ShortcutTips);
    end);
  Features.Add('Palette', TAtlasSafeLevel.Safe,
    function: Boolean
    begin
      Result := Palette <> nil;
    end,
    StartPalette,
    procedure
    begin
      FreeAndNil(Palette);
    end);
  // Gezeichnete Elemente und Ausblenden am Element (#628): vor den Zeichnern, Abbau nach ihnen.
  Features.AddWanted('Hide',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := ALevel <> TAtlasSafeLevel.Minimal;
    end,
    function: Boolean
    begin
      Result := HideStarted;
    end,
    StartHide, StopHide);
  // Editor-Zeichnungen.
  Features.AddWanted('Pairs',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel = TAtlasSafeLevel.Normal) or TAtlasIdeSettings.Current.PairColors or
        TAtlasIdeSettings.Current.PairGuides or TAtlasIdeSettings.Current.InactiveDim;
    end,
    function: Boolean
    begin
      Result := Pairs <> nil;
    end,
    procedure
    begin
      Pairs := TAtlasEditorPairs.Create;
    end,
    procedure
    begin
      FreeAndNil(Pairs);
    end);
  // Persönliche Notizen (#545): Befehle auch abgesichert (nur lokale Dateien), die Rinne wie die übrigen
  // Zeichnungen nur im normalen Start oder mit eingeschalteter Einstellung.
  Features.Add('Notes', TAtlasSafeLevel.Safe,
    function: Boolean
    begin
      Result := NotesStarted;
    end,
    StartNotes, StopNotes);
  // Benannte Lesezeichen (#622): Befehle auch abgesichert; die Rinne teilt sich die Zeichenschicht mit den
  // Notizen, jede Schicht folgt ihrer Einstellung.
  Features.Add('Bookmarks', TAtlasSafeLevel.Safe,
    function: Boolean
    begin
      Result := BookmarksStarted;
    end,
    StartBookmarks, StopBookmarks);
  // Fenster „Atlas-Prüfung“ (#909): liest den Problemspeicher des Managers.
  Features.Add('ProblemsWindow', TAtlasSafeLevel.Normal,
    function: Boolean
    begin
      Result := ProblemsWindowStarted;
    end,
    StartProblemsWindow, StopProblemsWindow);
  // Nach Notizen und Lesezeichen, Abbau davor: Die Rinne liest deren Listen (#545, #622); dazu die
  // Rekursionssymbole (#623).
  Features.AddWanted('GutterMarks',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel <> TAtlasSafeLevel.Minimal) and ((ALevel = TAtlasSafeLevel.Normal) or
        TAtlasIdeSettings.Current.Notes or TAtlasIdeSettings.Current.BookmarksNamed or
        TAtlasIdeSettings.Current.RecursionMarkers);
    end,
    function: Boolean
    begin
      Result := GutterMarks <> nil;
    end,
    StartGutterMarks,
    procedure
    begin
      FreeAndNil(GutterMarks);
    end);
  // Atlas-Spalte in der Zeilenleiste (#768): eigene Spalte, nur im normalen Start oder mit Einstellung.
  Features.AddWanted('GutterColumn',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel <> TAtlasSafeLevel.Minimal) and ((ALevel = TAtlasSafeLevel.Normal) or
        TAtlasIdeSettings.Current.GutterColumn);
    end,
    function: Boolean
    begin
      Result := GutterColumn <> nil;
    end,
    StartGutterColumn,
    procedure
    begin
      FreeAndNil(GutterColumn);
    end);
  // Schnelle Lesezeichen (#1104): Spalte links der Zeilennummern, Wiederfinden und Übernahme der IDE-Lesezeichen;
  // nach den Lesezeichen (#622), deren Listen sie liest.
  Features.AddWanted('QuickBookmarks',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel <> TAtlasSafeLevel.Minimal) and ((ALevel = TAtlasSafeLevel.Normal) or
        TAtlasIdeSettings.Current.QuickBookmarks);
    end,
    function: Boolean
    begin
      Result := QuickColumn <> nil;
    end,
    StartQuickColumn, StopQuickColumn);
  // Exception-Verlauf beim Debuggen (#517): Zuhörer der Debug-Sitzung; aus = kein Notifier beim Debugger.
  Features.AddWanted('DebugExceptions',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel <> TAtlasSafeLevel.Minimal) and TAtlasIdeSettings.Current.DebugExceptionHistory;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeDebugExceptions.Started;
    end,
    StartDebugExceptions, TAtlasIdeDebugExceptions.Release);
  // Nur eigener Code beim Debuggen (#578): Zuhörer der Debug-Sitzung und Haken an „Einzelne Anweisung“ (F7).
  Features.AddWanted('DebugOwnCode',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel <> TAtlasSafeLevel.Minimal) and TAtlasIdeSettings.Current.DebugJustMyCode;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeDebugOwnCode.Started;
    end,
    StartDebugOwnCode, TAtlasIdeDebugOwnCode.Release);
  // Exception-Leiste (#783): baut auf dem Exception-Verlauf auf; aus = Dialog der IDE unverändert.
  Features.AddWanted('DebugExceptionBar',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel <> TAtlasSafeLevel.Minimal) and DebugExceptionBarVisible;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeDebugExceptionBar.Started;
    end,
    StartDebugExceptionBar, TAtlasIdeDebugExceptionBar.Release);
  // Werte im Editor beim Debuggen (#508): Zuhörer der Debug-Sitzung und Zeichner; aus = nichts angemeldet.
  Features.AddWanted('DebugInlineValues',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel <> TAtlasSafeLevel.Minimal) and TAtlasIdeSettings.Current.DebugInlineValues;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeDebugInlineValues.Started;
    end,
    StartDebugInlineValues, TAtlasIdeDebugInlineValues.Release);
  // „kein Zugriff auf Wert“ erklären (#840): Hover und Werte im Editor; aus = Fehler wie bisher ausgeblendet.
  Features.AddWanted('DebugUnavailable',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel <> TAtlasSafeLevel.Minimal) and TAtlasIdeSettings.Current.DebugExplainUnavailable;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeDebugUnavailable.Started;
    end,
    StartDebugUnavailable, ReleaseDebugUnavailable);
  // Zugriffsverletzung erklären (#865): Zuhörer des Exception-Verlaufs und Zeichner; aus = nur die Meldung.
  Features.AddWanted('DebugAccessViolation',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel <> TAtlasSafeLevel.Minimal) and TAtlasIdeSettings.Current.DebugExplainAccessViolation;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeDebugAccessViolation.Started;
    end,
    StartDebugAccessViolation, TAtlasIdeDebugAccessViolation.Release);
  // Vervollständigung in Debugger-Dialogen (#538): aus = kein Zeitgeber, kein Tastatur-Hook.
  Features.AddWanted('DebugDialogCompletion',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel <> TAtlasSafeLevel.Minimal) and TAtlasIdeSettings.Current.DebugCompletionInDialogs;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeDebugDialogCompletion.Started;
    end,
    StartDebugDialogCompletion, TAtlasIdeDebugDialogCompletion.Release);
  // Fenster „Auswerten“ (#784): aus = kein Fenster, kein Zuhörer, Strg+F7 bleibt bei der IDE.
  Features.AddWanted('DebugEvaluate',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel <> TAtlasSafeLevel.Minimal) and TAtlasIdeSettings.Current.DebugEvaluateWindow;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeDebugEvaluate.Started;
    end,
    StartDebugEvaluate, TAtlasIdeDebugEvaluate.Release);
  // Schrittfilter beim Hineinspringen (#850): Zuhörer der Debug-Sitzung und Empfänger von F7; aus = F7 wie bisher.
  Features.AddWanted('DebugStepFilter',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel <> TAtlasSafeLevel.Minimal) and TAtlasIdeSettings.Current.DebugStepFilters;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeDebugStepFilter.Started;
    end,
    TAtlasIdeDebugStepFilter.Start, TAtlasIdeDebugStepFilter.Release);
  // Wirksame Compiler-Schalter an der Cursorposition (#558): Fenster, Befehl und Statusfeld; aus = kein Zeitgeber.
  Features.AddWanted('CompilerSwitches',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel <> TAtlasSafeLevel.Minimal) and TAtlasIdeSettings.Current.BuildCompilerSwitches;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeCompilerSwitches.Started;
    end,
    StartCompilerSwitches, TAtlasIdeCompilerSwitches.Release);
  // Gleichen Text wie die Markierung hervorheben (#709): nur im normalen Start oder mit Einstellung.
  Features.AddWanted('SelectionMatches',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel <> TAtlasSafeLevel.Minimal) and ((ALevel = TAtlasSafeLevel.Normal) or
        TAtlasIdeSettings.Current.SelectionMatches);
    end,
    function: Boolean
    begin
      Result := SelectionMatches <> nil;
    end,
    StartSelectionMatches,
    procedure
    begin
      FreeAndNil(SelectionMatches);
    end);
  // Austrittspunkte hervorheben (#698): nur im normalen Start oder mit Einstellung.
  Features.AddWanted('ExitPoints',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel <> TAtlasSafeLevel.Minimal) and ((ALevel = TAtlasSafeLevel.Normal) or
        TAtlasIdeSettings.Current.ExitPoints);
    end,
    function: Boolean
    begin
      Result := TAtlasIdeExitPoints.Installed;
    end,
    StartExitPoints, StopExitPoints);
  // Neu zugewiesene Variablen unterstreichen (#712): nur im normalen Start oder mit Einstellung.
  Features.AddWanted('Reassigned',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel <> TAtlasSafeLevel.Minimal) and ((ALevel = TAtlasSafeLevel.Normal) or
        TAtlasIdeSettings.Current.Reassigned);
    end,
    function: Boolean
    begin
      Result := TAtlasIdeReassigned.Installed;
    end,
    StartReassigned, StopReassigned);
  Features.AddWanted('CompletionKey',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel <> TAtlasSafeLevel.Minimal) and ((ALevel = TAtlasSafeLevel.Normal) or
        TAtlasIdeSettings.Current.Enabled);
    end,
    function: Boolean
    begin
      Result := CompletionKey <> nil;
    end,
    StartCompletionKey,
    procedure
    begin
      FreeAndNil(CompletionKey);
    end);
  Features.AddWanted('SignatureKey',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel <> TAtlasSafeLevel.Minimal) and ((ALevel = TAtlasSafeLevel.Normal) or
        TAtlasIdeSettings.Current.Enabled);
    end,
    function: Boolean
    begin
      Result := SignatureKey <> nil;
    end,
    StartSignatureKey,
    procedure
    begin
      FreeAndNil(SignatureKey);
    end);
  Features.Add('KeysWatched', TAtlasSafeLevel.Safe,
    function: Boolean
    begin
      Result := KeysWatched;
    end,
    WatchKeys, UnwatchKeys);
  // Willkommensseite (#753): auch abgesichert, sie startet keinen Server und liest nur lokale Daten. Abbau
  // vor dem Statusfeld, dessen Registry sie beobachtet.
  Features.AddWanted('Welcome',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel <> TAtlasSafeLevel.Minimal) and (StatusLines <> nil);
    end,
    function: Boolean
    begin
      Result := Welcome <> nil;
    end,
    StartWelcome, StopWelcome);
  // Issue-Kennungen im Code (#1265): nach „Meine Issues“ (Tracker und Vorschau), Abbau davor. issues.codeLinks
  // prüft der Zeitgeber selbst (Schnellschalter ohne Neustart).
  Features.AddWanted('IssueLinks',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel <> TAtlasSafeLevel.Minimal) and (Welcome <> nil) and (Welcome.Issues <> nil);
    end,
    function: Boolean
    begin
      Result := IssueLinks <> nil;
    end,
    StartIssueLinks,
    procedure
    begin
      FreeAndNil(IssueLinks);
    end);
  // Issues in der Zeilenhistorie (#1275): nach „Meine Issues“; issues.blameLinks prüfen die Haken selbst
  // (Schnellschalter ohne Neustart).
  Features.AddWanted('BlameIssues',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel <> TAtlasSafeLevel.Minimal) and (Welcome <> nil) and (Welcome.Issues <> nil);
    end,
    function: Boolean
    begin
      Result := BlameIssues <> nil;
    end,
    StartBlameIssues, StopBlameIssues);
  Features.Add('MainMenu', TAtlasSafeLevel.Safe,
    function: Boolean
    begin
      Result := MainMenu <> nil;
    end,
    StartMainMenu,
    procedure
    begin
      FreeAndNil(MainMenu);
    end);
  Features.Add('DirtyExport', TAtlasSafeLevel.Normal,
    function: Boolean
    begin
      Result := DirtyExport <> nil;
    end,
    procedure
    begin
      DirtyExport := TAtlasDirtyExport.Create;
    end,
    procedure
    begin
      FreeAndNil(DirtyExport);
    end);
  Features.Add('EditInbox', TAtlasSafeLevel.Normal,
    function: Boolean
    begin
      Result := EditInbox <> nil;
    end,
    StartEditInbox,
    procedure
    begin
      FreeAndNil(EditInbox);
    end);
  Features.Add('Reloader', TAtlasSafeLevel.Normal,
    function: Boolean
    begin
      Result := Reloader <> nil;
    end,
    CreateReloader,
    procedure
    begin
      FreeAndNil(Reloader);
    end);
end;

/// <summary>Gewünschte, noch fehlende Teile starten (beim Laden und nach jeder Einstellungsänderung).</summary>
procedure RegisterFeatures;
begin
  if Features = nil then
    AddFeatures;
  // Bis zur freien Nachrichtenschleife zählt jedes Teil zu den Startanteilen (Bericht N4).
  Features.Times := StartTimes;
  Features.StartWanted(Level);
  if Welcome <> nil then
    Welcome.Sync;
  if MainMenu <> nil then
  begin
    MainMenu.UpdateWelcome;
    MainMenu.UpdateKeyMap;
  end;
  // Abschaltbare Einträge im Kontextmenü des Editors (#1120).
  TAtlasIdeEditorCommands.UpdateContextMenus;
  // Phase und Fortschritt des Servers melden sich aus jedem Thread; gezeichnet wird gesammelt.
  if (Manager <> nil) and (StatusField <> nil) then
    Manager.OnServerChanged :=
      procedure
      begin
        if StatusField <> nil then
          StatusField.RequestRefresh;
      end;
  // Eigene Blocklinien: Strukturhervorhebung der IDE abgleichen (#514).
  TAtlasIdeStructureSwitch.Sync;
  RebindKeys;
end;

/// <summary>Hinweis des abgesicherten Starts (#722) samt Statuszeile; die Stufe bestimmt RegisterFeatures.</summary>
procedure StartSafeMode;
begin
  SafeMode := TAtlasIdeSafeMode.Create(nil);
  SafeMode.OnShowToggles :=
    procedure
    begin
      if QuickToggles <> nil then
        QuickToggles.Show;
    end;
  SafeMode.OnExportLog :=
    procedure
    begin
      TAtlasIdeDiagnosticExport.Execute(
        procedure(AText: string)
        begin
          GuardWarning(AText);
        end);
    end;
  SafeMode.OnBugReport := CreateBugReport;
  SafeMode.Start(TAtlasIdeSafeMode.DefaultFolder, TAtlasStatusRegistry.Default);
  // Fehler je Feature (#493) in die Startmarke.
  TAtlasGuard.OnFailure :=
    procedure(AFeature: TAtlasFeature)
    begin
      if SafeMode <> nil then
        SafeMode.RecordFailure(AFeature);
    end;
end;

/// <summary>Startanteile beenden (Bericht N4): Danach zählen weder Aktionen noch Teile mit.</summary>
procedure EndStartTimes;
begin
  TAtlasActivity.TimeInto(nil);
  if Features <> nil then
    Features.Times := nil;
  FreeAndNil(StartTimes);
end;

/// <summary>Nachrichtenschleife frei nach ALoadMs: Ladezeit in die Startmarke (#722), Startanteile ins Protokoll
/// und bei einem langsamen Start (safeMode.startupTimeoutMs) eine Zeile im Meldungsfenster (abschaltbar mit
/// robustness.hangHint). Bericht N4: Ein langsamer Start zählt nicht mehr wie ein Absturz und schaltet beim
/// nächsten Start nichts ab; er nennt, was Atlas daran hatte, damit sich die Ursache beheben lässt.</summary>
procedure ReportStartup(ALoadMs: Int64);
var
  Limit: Integer;
  Line, Parts: string;
begin
  if SafeMode <> nil then
    SafeMode.Loaded(ALoadMs);
  if StartTimes = nil then
    Exit;
  try
    // Erst anhalten, dann lesen: Keine Aktion zählt mehr mit.
    TAtlasActivity.TimeInto(nil);
    Limit := TAtlasIdeSettings.Current.SafeStartupTimeoutMs;
    Line := StartTimes.LogLine(ALoadMs, Limit);
    TAtlasGuard.Log(Line);
    if Manager <> nil then
      Manager.Log(Line);
    if TAtlasStartTimes.IsSlow(ALoadMs, Limit) and TAtlasIdeSettings.Current.HangHint then
    begin
      Parts := StartTimes.SlowestText;
      if Parts <> '' then
        Parts := ': ' + Parts;
      MessageLine(TAtlasStrings.Fmt(TAtlasTextId.StartSlow, [ALoadMs, Limit, StartTimes.Total, Parts]));
    end;
  finally
    EndStartTimes;
  end;
end;

procedure Register;
begin
  LoadedAt := TAtlasWatchdog.Timestamp;
  // Startanteile (Bericht N4): ab dem Laden jedes Teil, nach der Anmeldung die Atlas-Aktionen.
  EndStartTimes;
  StartTimes := TAtlasStartTimes.Create;
  // Abbruchsignal eines früheren Entladens in derselben Sitzung zurücknehmen (#493).
  TAtlasShutdown.Reset;
  // Einreihen in den Hauptthread wieder annehmen (nach einem früheren Unregister, Code-Review A-02).
  TAtlasMainThread.Start;
  TAtlasTimeLimit.LimitMs := TAtlasIdeSettings.Current.ProviderTimeLimitMs;
  TAtlasGuard.OnWarning := GuardWarning;
  TAtlasGuard.OnTripped := GuardTripped;
  TAtlasGuard.RotatingLog.OnError := LogError;
  // Stacktraces für jede Fehlerzeile der Sicherung: ohne sie lässt sich kein Fehler bis zur Codezeile verfolgen.
  TAtlasIdeStackCapture.Install;
  TAtlasStrings.Language := IdeLanguage;
  // Versionsverwaltung (#571): Aufrufe im Hintergrund; fehlt git bzw. svn, einmal eine Zeile.
  TAtlasIdeVcs.Start(MessageLine, VcsBackend);
  // Atlas-Symbol (#751): Startbildschirm, Info-Dialog und Bildliste immer, auch abgesichert.
  TAtlasIdeSymbol.Register;
  TAtlasIdeSymbol.OnThemeChanged :=
    procedure
    begin
      if MainMenu <> nil then
        MainMenu.UpdateImage;
      if StatusField <> nil then
        StatusField.RequestRefresh;
      TAtlasIdeResultsWindow.ApplyTheme;
      if Welcome <> nil then
        Welcome.ThemeChanged;
      if DiagnosticMode <> nil then
        DiagnosticMode.ThemeChanged;
      if Setup <> nil then
        Setup.ThemeChanged;
      if KeyMap <> nil then
        KeyMap.ThemeChanged;
      if ShortcutTips <> nil then
        ShortcutTips.ThemeChanged;
      TAtlasIdeBookmarks.ThemeChanged;
      TAtlasIdeProblems.ThemeChanged;
      TAtlasIdeOutline.ThemeChanged;
      TAtlasIdeArchitecture.ThemeChanged;
      TAtlasIdeHotspots.ThemeChanged;
      TAtlasIdeUnitRelations.ThemeChanged;
      TAtlasIdeBreadcrumbs.ThemeChanged;
      TAtlasIdeEditorToolbar.ThemeChanged;
      TAtlasIdeStatusBar.ThemeChanged;
      TAtlasIdeSearch.ThemeChanged;
      TAtlasIdeLineChanges.ThemeChanged;
      TAtlasIdeOverviewRuler.ThemeChanged;
      TAtlasIdeMinimap.ThemeChanged;
      TAtlasIdeDebugExceptions.ThemeChanged;
      TAtlasIdeCompilerSwitches.ThemeChanged;
      TAtlasIdeDebugExceptionBar.ThemeChanged;
      TAtlasIdeDebugEvaluate.ThemeChanged;
      TAtlasIdeDebugStepFilter.ThemeChanged;
    end;
  // Zuerst entscheiden, ob Atlas abgesichert startet (#722): Davon hängt ab, was angemeldet wird.
  if SafeMode = nil then
    StartSafeMode;
  // Immer: Statusfeld, Schnellschalter und Einstellungsseite.
  if StatusField = nil then
    RegisterStatusField;
  if QuickToggles = nil then
  begin
    QuickToggles := TAtlasIdeQuickToggles.Create(nil);
    QuickToggles.OnAnchor :=
      function: TPoint
      begin
        if (StatusField = nil) or not StatusField.Anchor(Result) then
          Result := Point(MaxInt, MaxInt);
      end;
  end;
  if Notifications = nil then
    StartNotifications;
  RegisterFeatures;
  TAtlasIdeExperimental.ApplySettings;
  // Geänderte Tastenkürzel sofort neu belegen; fremde Vervollständigung melden (#494).
  TAtlasIdeSettings.OnChanged :=
    procedure
    begin
      // Ein Schnellschalter oder „Normal weiterarbeiten“ im abgesicherten Start meldet nach (#722).
      RegisterFeatures;
      if SafeMode <> nil then
        SafeMode.UpdateFeatures;
      // undo.multiFile* (#721).
      TAtlasIdeUndo.ApplySettings;
      // updates.check (#495).
      if Updates <> nil then
        Updates.ApplySettings;
      // diagnosticMode.enabled (#479).
      if DiagnosticMode <> nil then
        DiagnosticMode.ApplySettings;
      // bookmarks.named und bookmarks.shared (#622).
      TAtlasIdeBookmarks.ApplySettings;
      // problems.window* (#909).
      TAtlasIdeProblems.ApplySettings;
      // outline.* (#537).
      TAtlasIdeOutline.ApplySettings;
      // architecture.* (#1118).
      TAtlasIdeArchitecture.ApplySettings;
      // hotspots.* (#1354).
      TAtlasIdeHotspots.ApplySettings;
      TAtlasIdeUnitRelations.ApplySettings;
      // callHierarchy.diagram (#1122).
      TAtlasIdeResultsWindow.ApplySettings;
      // navigation.symbolPath (#1117): Kontextmenü „Weg von hier nach …“.
      TAtlasIdeEditorCommands.ApplySettings;
      // editor.breadcrumbs* (#590).
      TAtlasIdeBreadcrumbs.ApplySettings;
      // editor.toolbar* (#1101).
      TAtlasIdeEditorToolbar.ApplySettings;
      // editor.statusBar* (#1155); das Atlas-Feld zieht um oder zurück (RequestRefresh unten).
      TAtlasIdeStatusBar.ApplySettings;
      // debug.breakOnNextEvent (#856).
      TAtlasIdeEventBreak.ApplySettings;
      // search.resultsInMessages (#878).
      TAtlasIdeSearch.ApplySettings;
      // tasks.onlyFindings und Tasten der Projektaufgaben (#900).
      if ProjectTasks <> nil then
        ProjectTasks.ApplySettings;
      // editor.stickyScroll* (#506).
      TAtlasIdeStickyScroll.ApplySettings;
      // debug.exceptionHistory (#517).
      TAtlasIdeDebugExceptions.ApplySettings;
      // build.compilerSwitches, build.showSwitchesInStatusBar (#558).
      TAtlasIdeCompilerSwitches.ApplySettings;
      // debug.exceptionBanner* (#783).
      TAtlasIdeDebugExceptionBar.ApplySettings;
      // debug.explainUnavailable (#840): Ergänzungen der Fehlertexte neu lesen.
      TAtlasIdeDebugUnavailable.ApplySettings;
      // debug.completionInDialogs (#538): Breiten des Popups.
      TAtlasIdeDebugDialogCompletion.ApplySettings;
      // debug.evaluateWindow.replaceCtrlF7 (#784): Strg+F7 an- bzw. abhängen.
      TAtlasIdeDebugEvaluate.ApplySettings;
      // debug.stepFilters* (#850): Fenster mit dem gespeicherten Stand, Treffer neuer Muster zählen.
      TAtlasIdeDebugStepFilter.ApplySettings;
      // editor.gitGutter, editor.gitBlame (#507).
      TAtlasIdeLineChanges.ApplySettings;
      // editor.overviewRuler, editor.overviewRulerKinds (#519).
      TAtlasIdeOverviewRuler.ApplySettings;
      // editor.minimap* (#873, experimentell).
      TAtlasIdeMinimap.ApplySettings;
      // notifications.* (#601): an oder aus, Höchstzahl, Verhalten je Quelle.
      if Notifications <> nil then
        Notifications.ApplySettings;
      // Projektdatei .atlas an oder aus (#486).
      TAtlasIdeTeamFile.Refresh;
      // Wirksame experimentelle Funktionen im Statusfeld und im Protokoll (#834).
      TAtlasIdeExperimental.ApplySettings;
      // debug.visualizers aus: abmelden; Arten geändert: neu anmelden (#835).
      TAtlasIdeVisualizers.ApplySettings;
      // debug.displayRules aus: abmelden; an: Regeln beim nächsten Takt neu lesen (#854).
      TAtlasIdeDisplayRules.ApplySettings;
      // startProfiles.enabled aus: Zeitgeber und Feld weg (RegisterFeatures startet sie wieder);
      // startProfiles.statusField oder .atlas geändert: Feld neu melden (#575).
      if not TAtlasIdeSettings.Current.StartProfiles then
        StopStartProfiles
      else
        TAtlasIdeStartProfiles.Refresh;
      // tips.usageTracking (#757).
      if CommandUsage <> nil then
        CommandUsage.ApplySettings;
      // shortcutTips.* und neu belegte Tasten (#600); Zählung für „Atlas entdecken“ (#757).
      if ShortcutTips <> nil then
      begin
        ShortcutTips.CountAlways := TAtlasIdeSettings.Current.WelcomePage and
          TAtlasIdeSettings.Current.WelcomePageDiscover and TAtlasIdeSettings.Current.TipsUsageTracking;
        ShortcutTips.ApplySettings;
      end;
      TAtlasTimeLimit.LimitMs := TAtlasIdeSettings.Current.ProviderTimeLimitMs;
      // Index-Optionen schreibt der Optionsdialog nach settings.json; der Server beobachtet die Datei (#652).
      // Statusfeld an, aus, Kurztext oder ausgeblendete Zeilen geändert (#591).
      if StatusField <> nil then
        StatusField.RequestRefresh;
    end;
  // Prüfung und Regelkatalog des Einstellungsdialogs (#227): nur ein laufender Server, keiner wird gestartet.
  TAtlasProjectSettings.Command :=
    function(const ACommand, AArgumentsJson: string): TJSONValue
    begin
      if Manager <> nil then
        Result := Manager.RunServerCommand(ACommand, AArgumentsJson, 5000)
      else
        Result := nil;
    end;
  RegisterOptions;
  if StartTimes <> nil then
  begin
    // Die übrige Anmeldung ohne die schon einzeln gezählten Teile.
    StartTimes.Add('Anmeldung', TAtlasWatchdog.Timestamp - LoadedAt - StartTimes.Total);
    // Bis zur freien Nachrichtenschleife laden IDE, übrige Packages und Projekt; Atlas ist dann nur mit Aktionen
    // dabei (etwa Bauen beim Öffnen).
    TAtlasActivity.TimeInto(StartTimes);
  end;
  // Ladezeit bis zur freien Nachrichtenschleife (#722) und Startanteile (Bericht N4).
  TAtlasMainThread.ForceQueue(TAtlasFeature.Settings,
    procedure
    begin
      ReportStartup(TAtlasWatchdog.Timestamp - LoadedAt);
      // Prüfliste beim ersten Start bzw. solange ein Punkt fest gelb oder rot ist (#625).
      if Setup <> nil then
        Setup.Start;
      // Eigene Tasten prüfen, sobald die übrigen Packages ihre Tasten angemeldet haben (#520).
      if KeyMap <> nil then
        KeyMap.CheckAtStart;
    end);
end;

/// <summary>Stammt die Klasse von AObject aus diesem Package?</summary>
function OwnClass(AObject: TObject): Boolean;
begin
  Result := (AObject <> nil) and (FindClassHInstance(AObject.ClassType) = HInstance);
end;

/// <summary>„TEditWindow EditWindow_0 › TPanel EditorPanel“: Owner- bzw. Elternkette für das Protokoll.</summary>
function ChainOf(AComponent: TComponent): string;
var
  Item: TComponent;
begin
  Result := '';
  Item := AComponent;
  while Item <> nil do
  begin
    if Result <> '' then
      Result := ' › ' + Result;
    Result := Item.ClassName + ' ' + Item.Name + Result;
    if Item.Owner <> nil then
      Item := Item.Owner
    else if (Item is TControl) and (TControl(Item).Parent <> nil) then
      Item := TControl(Item).Parent
    else
      Item := nil;
  end;
end;

/// <summary>Atlas-Komponenten, die nach dem Abbau noch einem Objekt der IDE gehören oder in einem ihrer Fenster
/// liegen (#1233). Die IDE gibt sie erst nach dem Entladen frei und rief dabei Notification bzw. den Destruktor in
/// nicht mehr geladenem Code auf (Zugriffsverletzung in TComponent.Notification beim Beenden). Nur die obersten:
/// Ihre eigenen Kinder gehen mit ihnen.</summary>
procedure CollectLeftovers(AComponent: TComponent; AFound: TList<TComponent>);
var
  Index: Integer;
  Control: TWinControl;
begin
  for Index := 0 to AComponent.ComponentCount - 1 do
    if OwnClass(AComponent.Components[Index]) then
    begin
      if not AFound.Contains(AComponent.Components[Index]) then
        AFound.Add(AComponent.Components[Index]);
    end
    else
      CollectLeftovers(AComponent.Components[Index], AFound);
  if not (AComponent is TWinControl) then
    Exit;
  Control := TWinControl(AComponent);
  for Index := 0 to Control.ControlCount - 1 do
    if OwnClass(Control.Controls[Index]) then
    begin
      if not AFound.Contains(Control.Controls[Index]) then
        AFound.Add(Control.Controls[Index]);
    end
    // Fremde Kinder ohne eigenen Owner-Baum hier (der kommt über Components).
    else if (Control.Controls[Index] is TWinControl) and (Control.Controls[Index].Owner <> AComponent) then
      CollectLeftovers(Control.Controls[Index], AFound);
end;

type
  /// <summary>Streicht Funde, die beim Freigeben eines anderen Fundes mit frei werden.</summary>
  TLeftoverTracker = class(TComponent)
  public
    Found: TList<TComponent>;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  end;

procedure TLeftoverTracker.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (Found <> nil) then
    Found.Remove(AComponent);
end;

/// <summary>Modul einer Klasse ('' = unbekannt), für das Protokoll.</summary>
function ModuleOf(AClass: TClass): string;
var
  Buffer: array[0..MAX_PATH] of Char;
begin
  Result := '';
  if GetModuleFileName(FindClassHInstance(AClass), Buffer, MAX_PATH) > 0 then
    Result := ExtractFileName(Buffer);
end;

/// <summary>Komponenten der Editorfenster mit Modul ihrer Klasse ins Protokoll (#1233): Beim Beenden ruft die IDE
/// Notification einer Komponente eines Editorfensters auf, deren Code schon entladen ist.</summary>
procedure LogEditorComponents;
var
  FormIndex, Index: Integer;
  Form: TCustomForm;
  Module: string;
begin
  for FormIndex := 0 to Screen.FormCount - 1 do
  begin
    Form := Screen.Forms[FormIndex];
    if not SameText(Form.ClassName, 'TEditWindow') then
      Continue;
    for Index := 0 to Form.ComponentCount - 1 do
    begin
      Module := ModuleOf(Form.Components[Index].ClassType);
      // Nur, was nicht aus der IDE selbst stammt.
      if not (StartsText('coreide', Module) or StartsText('vcl', Module) or StartsText('rtl', Module) or
        SameText(Module, 'bds.exe')) then
        TAtlasGuard.Log(Format('Beim Entladen in %s: %s "%s" aus %s', [Form.Name,
          Form.Components[Index].ClassName, Form.Components[Index].Name, Module]));
    end;
  end;
end;

procedure FreeLeftovers;
var
  Tracker: TLeftoverTracker;
  Item: TComponent;
  Index: Integer;
begin
  LogEditorComponents;
  Tracker := TLeftoverTracker.Create(nil);
  try
    Tracker.Found := TList<TComponent>.Create;
    for Index := 0 to Screen.FormCount - 1 do
      if OwnClass(Screen.Forms[Index]) then
        Tracker.Found.Add(Screen.Forms[Index])
      else
        CollectLeftovers(Screen.Forms[Index], Tracker.Found);
    for Index := 0 to Screen.DataModuleCount - 1 do
      if not OwnClass(Screen.DataModules[Index]) then
        CollectLeftovers(Screen.DataModules[Index], Tracker.Found);
    CollectLeftovers(Application, Tracker.Found);
    for Item in Tracker.Found do
      Item.FreeNotification(Tracker);
    while Tracker.Found.Count > 0 do
    begin
      Item := Tracker.Found.Last;
      TAtlasGuard.Log('Atlas-Komponente nach dem Abbau noch vorhanden, wird freigegeben: ' + ChainOf(Item));
      try
        Item.Free;
      except
        on E: Exception do
          TAtlasGuard.Log('Freigeben fehlgeschlagen: ' + E.ClassName);
      end;
      // Ohne Benachrichtigung (Ausnahme im Destruktor) nicht endlos.
      Tracker.Found.Remove(Item);
    end;
  finally
    Tracker.Found.Free;
    Tracker.Found := nil;
    Tracker.Free;
  end;
end;

procedure Unregister;
var
  StartedAt: UInt64;
  Stopped: Boolean;
  Teardown: TAtlasTeardown;
begin
  // Zuerst das gemeinsame Abbruchsignal: Jeder Hintergrund-Thread hört auf zu warten (#493).
  StartedAt := TThread.GetTickCount64;
  Stopped := False;
  // Jeder Schritt für sich (#886): Eine Ausnahme, etwa beim Entladen mitten im Gruppen-Build, ließ früher alle
  // folgenden Schritte aus. Notifier, Fenster-Hooks und Threads der alten Instanz blieben dann angemeldet, und die
  // IDE stürzte beim Beenden in nicht mehr geladenem Code ab. Die Zeile „Atlas entladen“ steht jetzt immer im
  // Protokoll, mit den fehlgeschlagenen Schritten (nur Name und Ausnahmeklasse).
  Teardown := TAtlasTeardown.Create;
  try
    TAtlasShutdown.Signal;
    // Vor allem anderen: Was jetzt noch wartet oder während des Abbaus eingereiht wird, liefe nach dem Entladen
    // in nicht mehr geladenem Code (Code-Review A-02). Queue im Hauptthread läuft weiter sofort.
    Teardown.Step('MainThread',
      procedure
      begin
        TAtlasMainThread.Stop;
      end);
    Teardown.Step('Vcs',
      procedure
      begin
        TAtlasIdeBranching.ServerCommand := nil;
        TAtlasIdeVcs.Stop;
      end);
    Teardown.Step('Experimental',
      procedure
      begin
        TAtlasIdeExperimental.Stop;
      end);
    TAtlasGuard.OnWarning := nil;
    TAtlasGuard.OnTripped := nil;
    TAtlasGuard.OnFailure := nil;
    TAtlasGuard.RotatingLog.OnError := nil;
    TAtlasIdeSettings.OnChanged := nil;
    // Entladen vor der freien Nachrichtenschleife: Die Startanteile hängen noch an Aktionen und Teilen.
    Teardown.Step('StartTimes',
      procedure
      begin
        EndStartTimes;
      end);
    // Sauberes Ende: Startmarke löschen, Absturzzähler zurück (#722).
    Teardown.Step('SafeMode',
      procedure
      begin
        if SafeMode <> nil then
          SafeMode.Stop;
        FreeAndNil(SafeMode);
      end);
    // Rückwärts zur Startreihenfolge (Code-Review S-03): Palette vor den Teilen, deren Befehle sie hält,
    // Tastenkürzel-Tipps und Willkommensseite vor der Zählung, Rinne vor Notizen und Lesezeichen, Prüfung beim
    // Speichern vor den Compiler-Ereignissen, der Manager zuletzt. Alles vor dem Statusfeld: Diagnosemodus,
    // Einrichtung, Update-Prüfung und Willkommensseite haben Zeilen in dessen Registry (#479, #625, #754).
    if Features <> nil then
      Teardown.AddFailures(Features.StopAll);
    // Nach den Debugger-Funktionen: Sie melden sich dort ab; was übrig bleibt, hängt Atlas hier von F7 ab (#850).
    Teardown.Step('DebugTrace',
      procedure
      begin
        TAtlasIdeDebugTrace.Release;
      end);
    Teardown.Step('QuickToggles',
      procedure
      begin
        FreeAndNil(QuickToggles);
      end);
    Teardown.Step('SettingsTransfer',
      procedure
      begin
        TAtlasIdeSettingsTransfer.Release;
      end);
    // Nach den Quellen, vor dem Statusfeld: Die Einträge halten Aktionen mit Code des Plugins (#601).
    Teardown.Step('Notifications',
      procedure
      begin
        FreeAndNil(Notifications);
        TAtlasNotificationCenter.ReleaseDefault;
      end);
    Teardown.Step('StatusField',
      procedure
      begin
        UnregisterStatusField;
      end);
    Teardown.Step('Options',
      procedure
      begin
        TAtlasOptionsRegistration.Unregister;
      end);
    TAtlasProjectSettings.Command := nil;
    Teardown.Step('History',
      procedure
      begin
        TAtlasIdeHistory.Release;
      end);
    Teardown.Step('Favorites',
      procedure
      begin
        TAtlasIdeFavorites.Release;
      end);
    Teardown.Step('Symbol',
      procedure
      begin
        TAtlasIdeSymbol.Unregister;
      end);
    Teardown.Step('Settings',
      procedure
      begin
        TAtlasIdeSettings.Release;
      end);
    Teardown.Step('Threads',
      procedure
      begin
        Stopped := TAtlasTimeLimit.StopAll(TAtlasShutdown.StopMs);
      end);
    Teardown.Step('Features',
      procedure
      begin
        FreeAndNil(Features);
      end);
    Teardown.Step('StackCapture',
      procedure
      begin
        TAtlasIdeStackCapture.Uninstall;
      end);
    // Zuletzt (#1233): Was jetzt noch an der IDE hängt, gäbe die IDE nach dem Entladen frei.
    Teardown.Step('Leftovers',
      procedure
      begin
        FreeLeftovers;
      end);
  finally
    TAtlasGuard.Log(Format('Atlas entladen in %d ms; Hintergrund-Threads beendet: %s; Fehler beim Abbau: %s',
      [TThread.GetTickCount64 - StartedAt, BoolToStr(Stopped, True), Teardown.Summary]));
  end;
end;

initialization

finalization
  Unregister;

end.
