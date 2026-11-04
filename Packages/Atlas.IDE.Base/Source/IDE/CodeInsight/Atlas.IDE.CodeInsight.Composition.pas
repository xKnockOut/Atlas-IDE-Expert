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
  Atlas.Core.Lsp.CrashCases,
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
  Atlas.IDE.Diagnostics.ServerPackage,
  Atlas.IDE.Diagnostics.Timing,
  Atlas.IDE.Setup.Checklist,
  Atlas.IDE.Files.Reloader,
  Atlas.IDE.Commands.Palette,
  Atlas.IDE.Editor.Pairs,
  Atlas.IDE.Foundation.StructureSwitch,
  Atlas.IDE.Files.DirtyExport,
  Atlas.IDE.Files.EditInbox,
  Atlas.IDE.Build.CheckOnSave,
  Atlas.IDE.Build.LastMessages,
  Atlas.IDE.Editor.UnitRename,
  Atlas.IDE.Settings.Project,
  Atlas.IDE.Commands.MainMenu,
  Atlas.IDE.Editor.Rename,
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
  Atlas.IDE.Foundation.Navigation,
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
  Atlas.IDE.Generate.Commands,
  Atlas.Core.Completion.Snippets,
  Atlas.IDE.Commands.Bindings,
  Atlas.IDE.Forms.Designer,
  Atlas.Core.Status.Registry,
  Atlas.Core.Status.Lines,
  Atlas.Core.Status.Server,
  Atlas.IDE.Status.Field,
  Atlas.IDE.Status.Lines,
  Atlas.IDE.Status.ServerWindow,
  Atlas.IDE.Settings.QuickToggles,
  Atlas.IDE.Settings.Transfer,
  Atlas.IDE.Settings.Experimental,
  Atlas.IDE.Settings.RuleChecksNotice,
  Atlas.Core.Status.Contract,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Sources,
  Atlas.IDE.Notifications.Service,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Diagnostics.ModuleHosting,
  Atlas.Core.Modules.Contributions,
  Atlas.IDE.Foundation.Host,
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
  Atlas.IDE.Undo.Changes,
  Atlas.Core.Updates.Check,
  Atlas.Core.Updates.Adapters.HttpSource,
  Atlas.IDE.Updates.Check,
  Atlas.IDE.Foundation.ResultsWindow,
  Atlas.IDE.Foundation.Symbol,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Commands.Usage,
  Atlas.IDE.Projects.Summaries,
  Atlas.Core.Problems.Findings,
  Atlas.Core.Editor.Metrics,
  Atlas.Core.Projects.Baseline,
  Atlas.IDE.Vcs.Branching,
  Atlas.IDE.Vcs.WorkingCopies,
  Atlas.IDE.Vcs.Service,
  Atlas.IDE.Editor.RecursionGutter,
  Atlas.IDE.Editor.GutterColumn,
  Atlas.IDE.Editor.SelectionMatches,
  Atlas.IDE.Editor.ExitPoints,
  Atlas.IDE.Editor.Reassigned,
  Atlas.IDE.Problems.Service,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Providers.Expression,
  Atlas.IDE.Foundation.GutterMarks,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Editor.Hide,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Editor.TestUnitLens,
  Atlas.IDE.Hover.Editor,
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
  Atlas.Core.Lsp.Contract,
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
  Atlas.Core.Build.Pipeline,
  Atlas.Core.Build.Verdict,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Store,
  Atlas.Core.Problems.InlineHints,
  Atlas.IDE.Problems.Controller,
  Atlas.IDE.Problems.MessageList;

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
  // Gleichen Text wie die Markierung hervorheben (#709).
  SelectionMatches: TAtlasIdeSelectionMatches;
  // Ungespeicherte Dateien für schreibende MCP-Werkzeuge (#61).
  DirtyExport: TAtlasDirtyExport;
  // Schreibende MCP-Werkzeuge ändern offene Dateien über das Plugin (#397).
  EditInbox: TAtlasIdeEditInbox;
  CheckOnSave: TAtlasIdeCheckOnSave;
  // Meldungen des letzten Builds je Projekt (#530) für Atlas.CompilerBaseline; lebt mit den Compile-Ereignissen.
  LastBuildMessages: TAtlasIdeLastBuildMessages;
  // Bewertung eines Builds (#530) an die Benachrichtigungszentrale (#601); lebt mit den Compile-Ereignissen.
  NotificationsVerdict: IAtlasRegistration;
  // Projekt-Zusammenfassungen (#592, #1455): schreibt Base, auch ohne Willkommensseite.
  ProjectSummaries: TAtlasIdeProjectSummaries;
  // Beim Öffnen eines Projekts oder einer Projektgruppe einmal bauen (build.onOpen); lebt mit den
  // Compile-Ereignissen.
  UnitRename: TAtlasIdeUnitRename;
  // Hinweis „Prüfregeln sind aus“ (#1454): Kern, meldet sich gerade bei ausgeschaltetem Modul Prüfregeln.
  RuleChecksNotice: TAtlasIdeRuleChecksNotice;
  // Angemeldete Module als Teile der Feature-Tabelle (#1455, ADR 0017 Regeln 1, 2); lebt mit Features.
  ModuleHosting: TAtlasModuleHosting;
  // Projektaufgaben aus atlas.json (#900), abschaltbar über tasks.enabled.
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
  // Dienste für Notizen (#545) und Lesezeichen (#622) gestartet.
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
  begin
    Palette.Rebind;
  end;
  if CheckOnSave <> nil then
  begin
    CheckOnSave.Rebind;
  end;
  if EditorKeys <> nil then
  begin
    EditorKeys.Rebind;
  end;
  if CompletionKey <> nil then
  begin
    CompletionKey.Rebind(Word(Settings.CompletionKey), Settings.CompletionKeyPriority,
      TAtlasStrings.Text(TAtlasTextId.SettingsCompletionKey));
  end;
  if SignatureKey <> nil then
  begin
    SignatureKey.Rebind(Word(Settings.SignatureKey), Settings.SignatureKeyPriority,
      TAtlasStrings.Text(TAtlasTextId.SettingsSignatureKey));
  end;
  if QuickToggles <> nil then
  begin
    QuickToggles.Rebind;
  end;
  if DiagnosticMode <> nil then
  begin
    DiagnosticMode.Rebind;
  end;
end;

procedure ReportHang(const AHang: TAtlasHang);
var
  Hang: TAtlasHang;
  Text, Activity: string;
  Messages: IOTAMessageServices;
  Group: IOTAMessageGroup;
begin
  if (Hangs = nil) or (Manager = nil) then
  begin
    Exit;
  end;
  Hang := AHang;
  if Compile <> nil then
  begin
    Hang.CodeInsightCount := Compile.Events.CodeInsightCount;
    Hang.CodeInsightMs := Compile.Events.CodeInsightMs;
  end;
  Hangs.ThresholdMs := TAtlasIdeSettings.Current.HangThresholdMs;
  Text := Hangs.Finish(Hang);
  if Text = '' then
  begin
    Exit;
  end;
  Manager.Report(Text);
  if not TAtlasIdeSettings.Current.HangHint or (Hang.DurationMs < HangHintMs) or
    not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
  begin
    Exit;
  end;
  Activity := '';
  if Hang.Activity <> '' then
  begin
    Activity := ' (' + Hang.Activity + ')';
  end;
  Group := Messages.GetGroup('Atlas');
  if Group = nil then
  begin
    Group := Messages.AddMessageGroup('Atlas');
  end;
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
  begin
    Manager.Report(AText);
  end;
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
  begin
    Exit;
  end;
  Group := Messages.GetGroup('Atlas');
  if Group = nil then
  begin
    Group := Messages.AddMessageGroup('Atlas');
  end;
  Messages.AddTitleMessage(AText, Group);
end;

/// <summary>Zeile in der Meldungsansicht, ohne Plugin-Protokoll (z. B. Hinweis auf eine neue Version, #495).</summary>
procedure MessageLine(const AText: string);
var
  Messages: IOTAMessageServices;
  Group: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
  begin
    Exit;
  end;
  Group := Messages.GetGroup('Atlas');
  if Group = nil then
  begin
    Group := Messages.AddMessageGroup('Atlas');
  end;
  Messages.AddTitleMessage(AText, Group);
end;

/// <summary>Meldungsansicht mit der Gruppe Atlas nach vorn holen: für Ergebnisse eines Befehls, den der Benutzer
/// gerade ausgelöst hat (sonst sieht es aus, als passiere nichts).</summary>
procedure ShowAtlasMessages;
var
  Messages: IOTAMessageServices;
  Group: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
  begin
    Exit;
  end;
  Group := Messages.GetGroup('Atlas');
  if Group <> nil then
  begin
    Messages.ShowMessageView(Group);
  end;
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
      begin
        Exit(TAtlasVersionControl.Open(AFolder, AProvider, ARunner));
      end;
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
      begin
        Manager.RunServerCommandAsync(ACommand, AArgumentsJson, 10000, ADone);
      end
      else
      begin
        ADone(nil);
      end;
    end,
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end);
end;

/// <summary>„Issue anlegen“ des Moduls Tracker (#1268, #1455); False ohne laufendes Modul.</summary>
function IssueCreation(out ACreation: IAtlasIssueCreation): Boolean;
var
  mItem: IInterface;
begin
  ACreation := nil;
  Result := False;
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasIssueCreation) do
  begin
    if Supports(mItem, IAtlasIssueCreation, ACreation) then
    begin
      Result := True;
      Break;
    end;
  end;
end;

/// <summary>Befunde des Fensters „Atlas-Prüfung“ für „Issue anlegen“: Regel, Meldung, Fundstelle und Zeile.
/// </summary>
function IssueFindings(const AFindings: TArray<TAtlasFinding>): TArray<TAtlasIssueFinding>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AFindings));
  for mIndex := 0 to High(AFindings) do
  begin
    Result[mIndex].Rule := AFindings[mIndex].Rule;
    Result[mIndex].Message := AFindings[mIndex].MessageText(TAtlasIdeSettings.Current.ProblemsShowCompilerCode);
    Result[mIndex].Location := AFindings[mIndex].Location;
    Result[mIndex].LineText := AFindings[mIndex].LineText;
  end;
end;

/// <summary>„Für diesen Befund ein Issue anlegen …“ (#1268) über das Modul Tracker; ohne Modul nichts.</summary>
procedure CreateIssueFromFindings(const AFindings: TArray<TAtlasIssueFinding>);
var
  mCreation: IAtlasIssueCreation;
begin
  if IssueCreation(mCreation) then
  begin
    mCreation.FromFindings(AFindings);
  end;
end;

function CanCreateIssue: Boolean;
var
  mCreation: IAtlasIssueCreation;
begin
  Result := IssueCreation(mCreation) and mCreation.Enabled;
end;

/// <summary>„Issue anlegen“ zu einem Absturzfall des Servers (#1355): Dialog aus #1268, danach die Dateien des
/// Falls über „An Issue anhängen“ (#1276). Ohne Tracker bzw. mit issues.create aus öffnet der Ordner des Falls.
/// </summary>
procedure CreateCrashIssue(ACase: TAtlasCrashCase);
var
  mFiles: TArray<TAtlasIssueTextFile>;
  mCaseFiles: TArray<TAtlasCrashCaseFile>;
  mIndex: Integer;
  mCreation: IAtlasIssueCreation;
begin
  if not IssueCreation(mCreation) or not mCreation.Enabled then
  begin
    MessageLine(TAtlasStrings.Text(TAtlasTextId.CrashCaseTitle) + ': ' + ACase.Folder);
    Exit;
  end;
  mCaseFiles := TAtlasCrashCases.AttachFiles(ACase.Folder);
  SetLength(mFiles, Length(mCaseFiles));
  for mIndex := 0 to High(mCaseFiles) do
  begin
    mFiles[mIndex].Name := mCaseFiles[mIndex].Name;
    mFiles[mIndex].Text := mCaseFiles[mIndex].Text;
  end;
  mCreation.FromCrash(TAtlasCrashCases.IssueTitle(ACase), TAtlasCrashCases.IssueDescription(ACase), mFiles);
end;

/// <summary>Fenster „Atlas-Server“ (#1356) zeigen; abgeschaltet nichts.</summary>
procedure ShowServerWindow;
begin
  TAtlasIdeServerWindow.Show;
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

/// <summary>Code-Metriken (#66), TODO-Übersicht (#68) und Stand der Baseline (#97) nach einem Build für die
/// Projekt-Zusammenfassung (Projektverlauf #758, Einrichtung #759): in einem Hintergrundlauf vom laufenden Server
/// (startet ihn nicht), Zeitpunkt AStampUtc der des Builds: Damit kommen die Werte in seinen Messpunkt.</summary>
procedure RecordProjectMetrics(const AProject: string; AStampUtc: TDateTime);
var
  Project: string;
  Stamp: TDateTime;
begin
  if (Manager = nil) or (TAtlasIdeProjectSummaries.Current = nil) or (AProject = '') or
    not TAtlasIdeSettings.Current.Enabled then
  begin
    Exit;
  end;
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
      Baseline := TAtlasProjectBaselines.StateOnDisk(ExtractFileDir(Project));
      TAtlasMainThread.Queue(TAtlasFeature.WelcomePage,
        procedure
        begin
          if TAtlasIdeProjectSummaries.Current <> nil then
          begin
            TAtlasGuard.Run(TAtlasFeature.WelcomePage,
              procedure
              begin
                // Leere oder ungültige Antworten lassen die Zusammenfassung unverändert.
                TAtlasIdeProjectSummaries.Current.RecordMetrics(Project, Answers[0], Stamp);
                TAtlasIdeProjectSummaries.Current.RecordTodos(Project, Answers[1], Stamp);
                TAtlasIdeProjectSummaries.Current.RecordBaseline(Project, Baseline, Stamp);
              end);
          end;
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
  begin
    Exit;
  end;
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
              begin
                Actions.OpenFile(FileName);
              end;
            end);
        end);
    end) then
  begin
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.MetricsReportRunning));
  end
  else
  begin
    // Ein Befehl im Hintergrund läuft schon (etwa die Metriken nach einem Build): später noch einmal.
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.MetricsReportBusy));
  end;
end;

/// <summary>„Symbol umbenennen…“ (#397) aus Menü und Palette.</summary>
procedure RenameSymbol;
begin
  if Manager = nil then
  begin
    Exit;
  end;
  TAtlasIdeRename.Execute(Manager.ActiveSession,
    TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits),
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end);
end;

function DataFlowVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DataFlow;
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

/// <summary>Antwort als JSON-Text an ADone ('' ohne Antwort); der Manager gibt den Wert nach dem Aufruf frei.
/// </summary>
function AnswerText(const ADone: TProc<string>): TProc<TJSONValue>;
begin
  Result :=
    procedure(AValue: TJSONValue)
    begin
      if AValue = nil then
      begin
        ADone('');
      end
      else
      begin
        ADone(AValue.ToJSON([]));
      end;
    end;
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

function MetricsReportVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.MetricsReport;
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

function NotificationsVisible: Boolean;
begin
  Result := TAtlasIdeNotifications.Active;
end;

function TeamFileVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TeamFile;
end;

type
  /// <summary>Bewertung eines Builds (#530) aus dem Modul Build-Pipeline bzw. nur nach dem Compiler (Modul aus) an
  /// die Benachrichtigungszentrale (#601).</summary>
  TNotificationsVerdictListener = class(TInterfacedObject, IAtlasBuildVerdictListener)
  public
    procedure BuildEvaluated(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      const AVerdict: TAtlasBuildVerdict);
  end;

procedure TNotificationsVerdictListener.BuildEvaluated(const AMessages: TArray<TAtlasCompilerMessage>;
  const AProject: TAtlasCompileProject; const AVerdict: TAtlasBuildVerdict);
var
  mMessages: TArray<TAtlasCompilerMessage>;
  mProject: TAtlasCompileProject;
  mVerdict: TAtlasBuildVerdict;
begin
  if Notifications = nil then
  begin
    Exit;
  end;
  mMessages := AMessages;
  mProject := AProject;
  mVerdict := AVerdict;
  TAtlasGuard.Run(TAtlasFeature.Notifications,
    procedure
    begin
      Notifications.BuildEvaluated(mMessages, mProject, mVerdict);
    end);
end;

/// <summary>Build des Benutzers mit lesbaren Meldungen (#530): Meldungen merken, dann bewerten lassen. Übernimmt das
/// Modul Build-Pipeline die Bewertung nicht (aus), bewertet Base nur nach dem Compiler; die Folgen
/// (Benachrichtigung, Tests nach dem Build) gehen in beiden Fällen an jeden IAtlasBuildVerdictListener.</summary>
procedure EvaluateBuild(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
  ASucceeded: Boolean);
var
  mFailures: TArray<string>;
  mFailure: string;
begin
  if LastBuildMessages <> nil then
  begin
    LastBuildMessages.Remember(AProject.FileName, AMessages);
  end;
  if not TAtlasBuildPipeline.Evaluate(AMessages, AProject, ASucceeded, mFailures) then
  begin
    mFailures := mFailures + TAtlasBuildPipeline.Announce(AMessages, AProject,
      TAtlasBuildPipeline.CompilerVerdict(AMessages, ASucceeded));
  end;
  for mFailure in mFailures do
  begin
    TAtlasGuard.Log('Bewertung des Builds: ' + mFailure);
  end;
end;

/// <summary>Testläufer des Moduls Tests (#69, #1455); False ohne laufendes Modul.</summary>
function TestRunner(out ARunner: IAtlasTestRunner): Boolean;
var
  mItem: IInterface;
begin
  ARunner := nil;
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasTestRunner) do
  begin
    if Supports(mItem, IAtlasTestRunner, ARunner) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Tests ausführen über das Modul Tests; ohne Modul der Hinweis, dass die Tests aus sind.</summary>
procedure RunTestsOfModule(const AFileName: string; const ATests: TArray<string>);
var
  mRunner: IAtlasTestRunner;
begin
  if TestRunner(mRunner) then
  begin
    mRunner.RunTests(AFileName, ATests);
  end
  else
  begin
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.TestsRunOff));
  end;
end;

const
  /// <summary>Befehl des Moduls Analyse (#1455): Abhängigkeiten der Unit im Editor (#554, #593).</summary>
  UnitDependenciesCommandId = 'Atlas.UnitDependencies';

/// <summary>Befehl AId eines laufenden Moduls ausführen (Base kennt die Module nicht, Regel 9); ohne Modul nichts.
/// </summary>
procedure RunModuleCommand(const AId: string);
var
  mCommand: TAtlasModuleCommand;
begin
  if TAtlasModuleContributions.FindCommand(AtlasModuleRegistry, AId, mCommand) and Assigned(mCommand.Run) and
    TAtlasModuleContributions.IsVisible(mCommand) then
  begin
    TAtlasGuard.Run(TAtlasFeature.EditorCommands, mCommand.Run);
  end;
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
      begin
        Actions.OpenFile(TAtlasCodeInsightManager.DiagnoseLog);
      end;
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
  // Befehle der Module (Debugger u. a., #1455) fragt die Palette selbst bei der Registry.
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
  Add('Atlas.ResetHistory', TAtlasTextId.PaletteResetHistory, TAtlasIdeHistory.Reset);
  // Metrikbericht des Projekts (#66); nur sichtbar, solange die Einstellung MetricsReport an ist.
  Add('Atlas.MetricsReport', TAtlasTextId.MetricsReportCommand, MetricsReport, MetricsReportVisible);
  // Projektdatei .atlas (#486) anlegen bzw. öffnen; nur sichtbar, solange die Einstellung TeamFile an ist.
  Add('Atlas.TeamFile', TAtlasTextId.TeamFileCommand, TAtlasIdeTeamFile.OpenInEditor, TeamFileVisible);
  // Liste der Benachrichtigungen (#601); nur sichtbar, solange die Zentrale an ist.
  Add('Atlas.Notifications', TAtlasTextId.NotificationsCommand,
    Guarded(TAtlasFeature.Notifications, TAtlasIdeNotifications.ShowList), NotificationsVisible);
  // „Release-Build prüfen“ (#533) stellt das Modul Build-Pipeline bereit.
  Add('Atlas.CheckNow', TAtlasTextId.PaletteCheckNow,
    procedure
    begin
      if CheckOnSave <> nil then
      begin
        CheckOnSave.CheckNow;
      end;
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
  // Fenster „Atlas-Server“ (#1356); nur sichtbar mit server.statusWindow.
  Add('Atlas.ServerStatus', TAtlasTextId.ServerWindowCommand, ShowServerWindow,
    function: Boolean
    begin
      Result := TAtlasIdeServerWindow.Enabled;
    end);
  Add('Atlas.ProjectSettings', TAtlasTextId.ProjectSettingsTitle, TAtlasProjectSettings.Execute);
  // Branch anlegen (#1288): Dialog für die Arbeitskopie des aktiven Projekts, ohne Issue; immer mit Dialog.
  Add('Atlas.CreateBranch', TAtlasTextId.VcsBranchCommand,
    procedure
    var
      mProject: string;
    begin
      mProject := TAtlasIdeProjectSummaries.ProjectFileOf(TAtlasIdeTeamFile.ActiveProject);
      if mProject = '' then
      begin
        TAtlasIdeVcs.Report(TAtlasStrings.Text(TAtlasTextId.VcsBranchNoVcs));
        Exit;
      end;
      TAtlasIdeBranching.CreateFor(mProject,
        procedure
        begin
          if TAtlasIdeProjectSummaries.Current <> nil then
          begin
            TAtlasIdeProjectSummaries.Current.Refresh(mProject);
          end;
        end);
    end);
  // Arbeitskopien (#1292): Wurzel, Externals bzw. Submodule des aktiven Projekts; sichtbar mit vcs.externals.show.
  Add('Atlas.WorkingCopies', TAtlasTextId.VcsWorkingCopiesCommand,
    procedure
    var
      mProject: string;
    begin
      mProject := TAtlasIdeProjectSummaries.ProjectFileOf(TAtlasIdeTeamFile.ActiveProject);
      if mProject = '' then
      begin
        TAtlasIdeVcs.Report(TAtlasStrings.Text(TAtlasTextId.VcsWorkingCopiesNoVcs));
        Exit;
      end;
      TAtlasIdeWorkingCopies.ShowFor(mProject,
        procedure
        begin
          if TAtlasIdeProjectSummaries.Current <> nil then
          begin
            TAtlasIdeProjectSummaries.Current.Refresh(mProject);
          end;
        end);
    end,
    function: Boolean
    begin
      Result := TAtlasIdeSettings.Current.VcsExternalsShow;
    end);
  // Künstlicher Hänger für den Einfrier-Wächter (#501): nur im Diagnosemodus (#479, Code-Review S-07).
  Add('Atlas.HangTest', TAtlasTextId.SettingsHangTest,
    procedure
    var
      Activity: IInterface;
    begin
      // Auch über Verlauf oder Taste nicht außerhalb des Diagnosemodus.
      if not TAtlasIdeSettings.Current.DiagnosticMode then
      begin
        Exit;
      end;
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
  begin
    FileName := TAtlasGuard.RotatingLog.FileName;
  end;
  if FileExists(FileName) and Supports(BorlandIDEServices, IOTAActionServices, Actions) then
  begin
    Actions.OpenFile(FileName);
  end;
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
      begin
        Actions.OpenFile(TAtlasGuard.RotatingLog.FileName);
      end;
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
  begin
    Exit;
  end;
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
  begin
    Options.EditOptions('', 'Atlas');
  end;
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

const
  ProblemCountsExtra = 'problemCounts';

/// <summary>Diagnosepaket des Fensters „Atlas-Server“ (#1356): Bericht und Dateien des laufenden Servers im
/// Hintergrund.</summary>
procedure CreateServerPackage;
begin
  TAtlasIdeServerPackage.Execute(
    procedure(const ACommand, AArgumentsJson: string; const ADone: TProc<TJSONValue>)
    begin
      if Manager <> nil then
      begin
        Manager.RunServerCommandAsync(ACommand, AArgumentsJson, 30000, ADone);
      end
      else
      begin
        ADone(nil);
      end;
    end,
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end);
end;

/// <summary>Fenster „Atlas-Server“ (#1356): liest die Antwort der Statuszeilen, fragt selbst nicht ab.</summary>
procedure InstallServerWindow;
var
  mHooks: TAtlasIdeServerWindow.THooks;
begin
  mHooks := Default(TAtlasIdeServerWindow.THooks);
  mHooks.StatusJson :=
    function: string
    begin
      Result := '';
      if StatusLines <> nil then
      begin
        Result := StatusLines.StatusJson;
      end;
    end;
  mHooks.Running :=
    function: Boolean
    begin
      Result := (Manager <> nil) and (Manager.ServerInfo.Phase = TAtlasServerPhase.Running);
    end;
  mHooks.Restarts :=
    function: Integer
    begin
      Result := 0;
      if Manager <> nil then
      begin
        Result := Manager.ServerRestarts;
      end;
    end;
  mHooks.QueryNow :=
    function(ADone: TProc): Boolean
    begin
      Result := (StatusLines <> nil) and StatusLines.QueryNow(ADone);
    end;
  mHooks.Rebuild :=
    procedure
    begin
      if Manager = nil then
      begin
        Exit;
      end;
      Manager.ExecuteServerCommandAsync('atlas.server.rebuildIndex', 30000,
        procedure(AAnswer: TJSONValue)
        begin
          if AAnswer = nil then
          begin
            GuardWarning(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
          end
          else
          begin
            GuardWarning(TAtlasStrings.Text(TAtlasTextId.MenuIndexRebuilding));
          end;
        end);
    end;
  mHooks.Package := CreateServerPackage;
  mHooks.OpenUnit :=
    procedure(AUnit: TAtlasServerSlowUnit)
    var
      mActions: IOTAActionServices;
    begin
      // Ohne Pfad (ältere Antwort) oder gelöscht: nichts zu öffnen.
      if (AUnit.FileName = '') or not FileExists(AUnit.FileName) then
      begin
        Exit;
      end;
      if Supports(BorlandIDEServices, IOTAActionServices, mActions) then
      begin
        mActions.OpenFile(AUnit.FileName);
      end;
    end;
  mHooks.OpenRule :=
    procedure(ARule: string)
    begin
      TAtlasOptionsRegistration.ShowRule(ARule);
    end;
  TAtlasIdeServerWindow.Install(mHooks);
end;

procedure RegisterStatusField;
begin
  StatusLines := TAtlasIdeStatusLines.Create(TAtlasStatusRegistry.Default,
    function: TAtlasServerInfo
    begin
      if Manager <> nil then
      begin
        Result := Manager.ServerInfo;
      end
      else
      begin
        Result := Default(TAtlasServerInfo);
      end;
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
    end,
    // Klick auf die Zeile „Server“: Fenster „Atlas-Server“ (#1356), nur mit server.statusWindow.
    ShowServerWindow,
    function: Boolean
    begin
      Result := TAtlasIdeServerWindow.Enabled;
    end);
  InstallServerWindow;
  StatusField := TAtlasStatusField.Create(TAtlasStatusRegistry.Default);
  StatusField.OnRefresh :=
    procedure
    begin
      if StatusLines <> nil then
      begin
        StatusLines.Refresh;
      end;
    end;
  StatusField.OnOpenLog := OpenLog;
  // Zeigt die Atlas-Statusleiste das Element status, öffnen Statusfenster und Schnellschalter dort (#1155).
  StatusField.OnRelocatedAnchor := TAtlasIdeStatusBar.Anchor;
  // Rechtsklick auf das Feld: Schnellschalter (#604).
  StatusField.OnContext :=
    procedure(APoint: TPoint)
    begin
      if QuickToggles <> nil then
      begin
        QuickToggles.Show(APoint);
      end;
    end;
  StatusField.OnRestart :=
    procedure
    begin
      if Manager <> nil then
      begin
        Manager.RestartServer;
      end;
    end;
  // Fehlerzähler (#509) als Zusatzfeld; ein Klick öffnet die Liste „Atlas-Probleme“.
  TAtlasProblemsController.OnCounts :=
    procedure(AShow: Boolean; const ACounts: TAtlasProblemCounts)
    begin
      if StatusField = nil then
      begin
        Exit;
      end;
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
          begin
            TAtlasIdeProblems.ShowWindow;
          end
          else
          begin
            TAtlasProblemsList.ShowList;
          end;
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
      begin
        Result := Point(MaxInt, MaxInt);
      end;
    end;
  Notifications.OnBadge :=
    procedure(AUnread: Integer; AWorst: TAtlasNotificationSeverity)
    begin
      if StatusField <> nil then
      begin
        StatusField.SetBadge(AUnread, BadgeState(AWorst),
          TAtlasStrings.Fmt(TAtlasTextId.NotificationsBadgeHint, [AUnread]),
          procedure(APoint: TPoint)
          begin
            if Notifications <> nil then
            begin
              Notifications.Show(APoint);
            end;
          end);
      end;
    end;
  // Erst jetzt erreicht die Plakette das Feld.
  Notifications.ApplySettings;
end;

procedure UnregisterStatusField;
begin
  TAtlasIdeServerWindow.Release;
  TAtlasProblemsController.OnCounts := nil;
  if Manager <> nil then
  begin
    Manager.OnServerChanged := nil;
  end;
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
  begin
    Manager.Report(Hangs.Summary);
  end;
  FreeAndNil(Hangs);
end;

procedure LogLine(const AText: string);
begin
  if Manager <> nil then
  begin
    Manager.Log(AText);
  end;
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
  begin
    Exit;
  end;
  for Index := 0 to Modules.ModuleCount - 1 do
  begin
    Result := Result + [Modules.Modules[Index].FileName];
  end;
  if (AProjectFile <> '') and Supports(Modules.FindModule(AProjectFile), IOTAProject, Project) then
  begin
    for Index := 0 to Project.GetModuleCount - 1 do
    begin
      if Project.GetModule(Index).FileName <> '' then
      begin
        Result := Result + [Project.GetModule(Index).FileName];
      end;
    end;
  end;
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
      begin
        Manager.NotifyServer(AMethod, AParams);
      end
      else
      begin
        AParams.Free;
      end;
    end;
  Events.OnLog := LogLine;
  Events.Add(TAtlasCompileLog.Create(Events, LogLine));
  // Release-Build-Wächter (#533), Prüfung vor dem Kompilieren (#529) und Läufer der Builds auf Auftrag (#261)
  // meldet das Modul Build-Pipeline an und ab, die Projektaufgaben vor dem Build (#900) das Modul Build (#1455).
  // Compilermeldungen aus dem Reiter „Build“ an den Server (#528).
  Events.Add(TAtlasMessageViewReader.Create(
    procedure(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      ASucceeded: Boolean; const AInfo: string; AReadable: Boolean)
    var
      Messages: TArray<TAtlasCompilerMessage>;
      Project: TAtlasCompileProject;
      Succeeded, Readable: Boolean;
      Stamp: TDateTime;
      Failure: string;
    begin
      Messages := TAtlasCompilerMessages.Resolve(AMessages, AProject.FileName, KnownFiles(AProject.FileName));
      // Projekt-Zusammenfassung (#592, Base): letzter Build bzw. letzte Hintergrundprüfung.
      Project := AProject;
      Succeeded := ASucceeded;
      Readable := AReadable;
      // Ein Zeitpunkt je Build: Metriken, TODOs und Baseline kommen damit in den Messpunkt des Builds (#758).
      Stamp := TAtlasIdeProjectSummaries.StampUtc;
      if TAtlasIdeProjectSummaries.Current <> nil then
      begin
        TAtlasGuard.Run(TAtlasFeature.WelcomePage,
          procedure
          begin
            TAtlasIdeProjectSummaries.Current.Recorded(Messages, Project, Succeeded, Readable, Stamp);
          end);
      end;
      // Code-Metriken und TODOs nach einem Build, nicht nach einer Hintergrundprüfung (#66, #68, #758).
      if AReadable and not AProject.Background then
      begin
        TAtlasGuard.Run(TAtlasFeature.WelcomePage,
          procedure
          begin
            RecordProjectMetrics(Project.FileName, Stamp);
          end);
      end;
      // Gelesene Meldungen an die Module, etwa die Builds auf Auftrag (#261) der Build-Pipeline.
      for Failure in TAtlasBuildPipeline.MessagesRead(Messages, Project) do
      begin
        TAtlasGuard.Log('Compilermeldungen: ' + Failure);
      end;
      // Build des Benutzers mit lesbaren Meldungen (#530): erst bewerten (Modul Build-Pipeline: Basislinie,
      // build.zeroHints, build.warningsAsErrors, Zusammenfassung), dann Benachrichtigung (#601) und Tests nach dem
      // Build (#69).
      if AReadable and not AProject.Background then
      begin
        TAtlasGuard.Run(TAtlasFeature.Build,
          procedure
          begin
            EvaluateBuild(Messages, Project, Succeeded);
          end);
      end
      // Hintergrundprüfung bzw. Build ohne lesbare Meldungen: Eintrag in der Benachrichtigungszentrale (#601).
      else if Notifications <> nil then
      begin
        TAtlasGuard.Run(TAtlasFeature.Notifications,
          procedure
          begin
            Notifications.BuildFinished(Messages, Project, Succeeded, Readable);
          end);
      end;
      if Manager = nil then
      begin
        Exit;
      end;
      if Length(Messages) > 0 then
      begin
        Manager.Report(Format('Meldungsfenster: %s (z. B. %s, Zeile %d)', [AInfo, Messages[0].FileName,
          Messages[0].Line]));
      end
      else
      begin
        Manager.Report('Meldungsfenster: ' + AInfo);
      end;
      Manager.NotifyServer('atlas/compilerMessages',
        TAtlasCompilerMessages.ToJson(Messages, AProject.FileName, AProject.Platform, ASucceeded,
        AProject.Background));
    end));
  Compile := TAtlasIdeCompileEvents.Create(Events);
  LastBuildMessages := TAtlasIdeLastBuildMessages.Create;
  NotificationsVerdict := AtlasModuleRegistry.Provide(IAtlasBuildVerdictListener,
    TNotificationsVerdictListener.Create as IAtlasBuildVerdictListener);
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
      begin
        if SameText(Name, ParamStr(0)) and (Registry.GetDataType(Name) = rdString) then
        begin
          Code := Registry.ReadString(Name);
        end;
      end;
    end;
  finally
    Names.Free;
    Registry.Free;
  end;
  if Code = '' then
  begin
    if (GetUserDefaultUILanguage and $3FF) = LANG_GERMAN then
    begin
      Code := 'DE';
    end;
  end;
  if SameText(Code, 'DE') then
  begin
    Result := TAtlasLanguage.German;
  end
  else
  begin
    Result := TAtlasLanguage.English;
  end;
end;

/// <summary>Stufe des abgesicherten Starts (#722); ohne Sicherung normal.</summary>
function Level: TAtlasSafeLevel;
begin
  if SafeMode <> nil then
  begin
    Result := SafeMode.Level;
  end
  else
  begin
    Result := TAtlasSafeLevel.Normal;
  end;
end;

procedure CreateReloader;
begin
  Reloader := TAtlasFileReloader.Create(
    procedure(AText: string)
    begin
      if Manager <> nil then
      begin
        Manager.Report(AText);
      end;
    end);
  // Gespeichert: Compilerprüfung vormerken (#548).
  Reloader.OnSaved :=
    procedure(AFileName: string)
    begin
      // Prüfung des Servers mit dcc (#40); die Prüfung in der IDE nur, wenn eingeschaltet (#548).
      if Manager <> nil then
      begin
        Manager.NotifySaved(AFileName);
      end;
      if CheckOnSave <> nil then
      begin
        CheckOnSave.Saved(AFileName);
      end;
      // Gewählte Kodierung und Zeilenenden schreiben (#591).
      if StatusLines <> nil then
      begin
        StatusLines.Saved(AFileName);
      end;
    end;
end;

procedure CreateMainMenu;
begin
  MainMenu := TAtlasMainMenu.Create(
    function: string
    begin
      // Fortschritt im Menütitel nur, wenn er nicht ins Statusfeld gehört (IndexProgressPlace).
      if (Manager <> nil) and TAtlasIdeSettings.Current.IndexProgressInMenu then
      begin
        Result := Manager.ServerProgress;
      end
      else
      begin
        Result := '';
      end;
    end,
    procedure(ACommand: string; ADone: TProc<TJSONValue>)
    begin
      if Manager <> nil then
      begin
        Manager.ExecuteServerCommandAsync(ACommand, 30000, ADone);
      end
      else
      begin
        ADone(nil);
      end;
    end,
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end);
  MainMenu.OnBugReport := CreateBugReport;
  MainMenu.OnServerStatus := ShowServerWindow;
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
      begin
        Result := Manager.ServerInfo;
      end
      else
      begin
        Result := Default(TAtlasServerInfo);
      end;
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
      begin
        Result := StatusLines.StatusJson;
      end;
    end;
  Hooks.StartServer :=
    function(ARestart: Boolean): Boolean
    begin
      Result := False;
      if Manager = nil then
      begin
        Exit;
      end;
      if ARestart then
      begin
        Result := Manager.RestartServer;
      end
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
      begin
        Manager.ExecuteServerCommandAsync(ACommand, 30000, nil);
      end;
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

/// <summary>Zählung zurückgesetzt (#757): an jeden IAtlasCommandUsageListener der laufenden Module.</summary>
procedure UsageResetInModules;
var
  mItem: IInterface;
  mListener: IAtlasCommandUsageListener;
begin
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasCommandUsageListener) do
  begin
    if Supports(mItem, IAtlasCommandUsageListener, mListener) then
    begin
      TAtlasGuard.Run(TAtlasFeature.Palette,
        procedure
        begin
          mListener.UsageReset;
        end);
    end;
  end;
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
      begin
        Manager.ExecuteServerCommandAsync(ACommand, 30000, ADone);
      end
      else
      begin
        ADone(nil);
      end;
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
    // Absturzfälle des Servers (#1355): „Issue anlegen“ in der Meldung.
    Manager.OnCrashIssue := CreateCrashIssue;
    ManagerIndex := Services.AddCodeInsightManager(Manager);
  end;
end;

procedure StopManager;
var
  Services: IOTACodeInsightServices;
begin
  try
    if (ManagerIndex >= 0) and Supports(BorlandIDEServices, IOTACodeInsightServices, Services) then
    begin
      Services.RemoveCodeInsightManager(ManagerIndex);
    end;
    ManagerIndex := -1;
    if Manager <> nil then
    begin
      // Nicht auf Destroy warten (#886): Hält die IDE den Manager noch (etwa wenn sie Atlas mitten im
      // Gruppen-Build entlädt), liefen sonst Sitzung, Server, Threads und Editor-Anbindungen nach dem Entladen weiter.
      Manager.Shutdown;
      if Manager.RefCount > 1 then
      begin
        TAtlasGuard.Log(Format('Code-Insight-Manager wird nach dem Abmelden noch %d-mal von der IDE gehalten',
          [Manager.RefCount - 1]));
      end;
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
      begin
        Manager.Report(AText);
      end;
    end);
end;

procedure StartUnitRename;
begin
  UnitRename := TAtlasIdeUnitRename.Create(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
      begin
        Result := Manager.ActiveSession;
      end;
    end,
    procedure(AText: string)
    begin
      if Manager <> nil then
      begin
        Manager.Report(AText);
      end;
    end);
end;

procedure StartRuleChecksNotice;
begin
  RuleChecksNotice := TAtlasIdeRuleChecksNotice.Create;
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
      begin
        Result := Palette.AtlasCommands;
      end;
    end;
  Hooks.Execute :=
    procedure(AId: string)
    begin
      if Palette <> nil then
      begin
        Palette.Execute(AId);
      end;
    end;
  Hooks.ShowPalette :=
    procedure
    begin
      if Palette <> nil then
      begin
        Palette.Show;
      end;
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
      begin
        Result := Length(TAtlasProblemsController.Current.ForFile(AFileName));
      end;
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
      begin
        Manager.RunServerCommandAsync('atlas.server.recheck', '[]', 10000, nil);
      end;
    end;
  TAtlasIdeStatusBar.Install(Hooks);
  if StatusField <> nil then
  begin
    StatusField.RequestRefresh;
  end;
end;

procedure StartCommands;
begin
  CommandsInstalled := True;
  TAtlasIdeResults.Install(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
      begin
        Result := Manager.ActiveSession;
      end;
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
      begin
        Result := Manager.ActiveSession;
      end;
    end,
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end);
  // Auswirkungsanalyse (#1120): „Betroffene Tests ausführen“ über den Testläufer des Moduls Tests (#69, #1455).
  TAtlasIdeImpact.Install(RunTestsOfModule);
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
        begin
          TAtlasIdeNavigation.GoToLocation(TLspSession.UriToPath(AProblem.Related[Item].Uri),
            AProblem.Related[Item].Line, AProblem.Related[Item].Character);
        end;
        Exit;
      end;
      if ATag = 'cycle.showGraph' then
      begin
        RunModuleCommand(UnitDependenciesCommandId);
        Exit;
      end;
      TAtlasIdeEditorCommands.ApplyTagged(TLspRange.Create(AProblem.StartLine, AProblem.StartCharacter,
        AProblem.EndLine, AProblem.EndCharacter), ATag);
    end;
  // Werte im Tooltip (#835, #854): Beiträge der Module (IAtlasHoverValueSource, z. B. Darstellungen und
  // Visualisierer des Debuggers); '' ohne. Der Tooltip kennt die Module nicht (A-09, #1455).
  TAtlasEditorHover.OnVisualize :=
    function(const AExpression: string; const ATypeChain: TArray<string>; const AText: string): string
    begin
      Result := TAtlasModuleContributions.HoverValue(AtlasModuleRegistry, AExpression, ATypeChain, AText);
    end;
  // Nächster/vorheriger Befund (#509): alle Befunde der Datei aus dem Problemspeicher.
  TAtlasIdeEditorCommands.OnProblemsOf :=
    function(const AFileName: string): TArray<TAtlasProblem>
    begin
      Result := nil;
      if TAtlasProblemsController.Current <> nil then
      begin
        Result := TAtlasProblemsController.Current.ForFile(AFileName);
      end;
    end;
  // Schnellkorrektur „Signaturhilfe öffnen“ (#1007): nach dem Sprung der Parameter-Hint wie mit der Taste.
  // „Graph zeigen“ als Code-Aktion an einem Unit-Zyklus (#896, atlas.showUnitRelations).
  TAtlasIdeEditorCommands.OnUnitRelations :=
    procedure
    begin
      RunModuleCommand(UnitDependenciesCommandId);
    end;
  TAtlasIdeEditorCommands.OnSignatureHelp :=
    procedure
    begin
      if Manager <> nil then
      begin
        Manager.OpenSignature;
      end;
    end;
  // ///-Gerüst (#88): Tab springt durch die Beschreibungen, wie bei Code-Vorlagen.
  TAtlasIdeEditorCommands.OnPlaceholders :=
    procedure(const AView: IOTAEditView; const ABefore: string; AOffset: Integer;
      const AExpansion: TAtlasSnippetExpansion)
    begin
      if (Manager <> nil) and (Manager.Completion <> nil) then
      begin
        Manager.Completion.StartPlaceholders(AView, ABefore, AOffset, AExpansion);
      end;
    end;
  // Erzeugen-Menü (#719): Vorlagen und ihr Einsetzen mit Platzhaltern kommen aus der Vervollständigung.
  TAtlasIdeGenerate.Install(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
      begin
        Result := Manager.ActiveSession;
      end;
    end,
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end,
    function: TAtlasSnippetList
    begin
      Result := nil;
      if Manager <> nil then
      begin
        Result := Manager.Completion.Snippets;
      end;
    end,
    procedure(AView: IOTAEditView; ASnippet: TAtlasSnippet)
    begin
      if Manager <> nil then
      begin
        Manager.Completion.InsertSnippet(AView, ASnippet);
      end;
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
      begin
        Result := Manager.ActiveSession;
      end;
    end);
  TAtlasIdeOutline.Install;
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
      begin
        Result := Manager.ActiveSession;
      end;
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
      begin
        Result := Manager.RunningSession;
      end;
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
      begin
        StatusField.SetExtra('multiCursor', AText, AHint, nil);
      end;
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
      begin
        Result := Manager.RunningSession;
      end;
    end,
    procedure(const AText, AHint: string)
    begin
      if StatusField <> nil then
      begin
        StatusField.SetExtra('linkedEditing', AText, AHint, nil);
      end;
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
      begin
        Result := Manager.RunningSession;
      end;
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
      begin
        Result := Manager.RunningSession;
      end;
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
      begin
        Result := Manager.RunningSession;
      end;
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
      begin
        Result := Manager.RunningSession;
      end;
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
  TAtlasIdeOverviewRuler.Install;
  // Minimap neben der Scrollleiste (#873, experimentell); fragt die Gliederung über TAtlasIdeOutlineCache.
  TAtlasIdeMinimap.Install;
  // Schnell öffnen (#503): Dateiliste im Hintergrund, zuletzt geöffnete Dateien zählen.
  TAtlasIdeQuickOpen.Install(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
      begin
        Result := Manager.ActiveSession;
      end;
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
  TAtlasIdeLineChanges.Uninstall;
  TAtlasIdeLineMove.Uninstall;
  TAtlasIdeBlockComment.Uninstall;
  TAtlasIdeUnwrap.Uninstall;
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
  TAtlasIdeOutlineCache.Uninstall;
  TAtlasIdeNavHistory.Uninstall;
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
      begin
        Result := Manager.RunningSession;
      end;
    end,
    procedure(AText: string)
    begin
      if Manager <> nil then
      begin
        Manager.Report(AText);
      end;
    end);
end;

procedure StartCommandUsage;
begin
  CommandUsage := TAtlasIdeCommandUsage.Create;
  // Nach „Zählung zurücksetzen“: „Noch nie benutzt“ auf der Karte eines Moduls sofort.
  CommandUsage.OnReset := UsageResetInModules;
end;

procedure StartShortcutTips;
begin
  ShortcutTips := TAtlasIdeShortcutTips.Create(CommandUsage);
  ShortcutTips.CountAlways := TAtlasIdeSettings.Current.WelcomePage and TAtlasIdeSettings.Current.WelcomePageDiscover and
    TAtlasIdeSettings.Current.TipsUsageTracking;
end;


/// <summary>Erste Zusatzquelle der laufenden Module für die Palette; nil ohne.</summary>
function PaletteSourceOfModules: IAtlasPaletteSource;
var
  mItem: IInterface;
  mProvider: IAtlasPaletteSourceProvider;
begin
  Result := nil;
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasPaletteSourceProvider) do
  begin
    if Supports(mItem, IAtlasPaletteSourceProvider, mProvider) then
    begin
      Result := mProvider.PaletteSource;
      if Result <> nil then
      begin
        Exit;
      end;
    end;
  end;
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
  begin
    QuickToggles.RegisterCommands(Palette);
  end;
  if DiagnosticMode <> nil then
  begin
    DiagnosticMode.RegisterCommands(Palette);
  end;
  if Setup <> nil then
  begin
    Setup.RegisterCommands(Palette);
  end;
  if KeyMap <> nil then
  begin
    KeyMap.RegisterCommands(Palette);
  end;
  // Zusatzquelle der Palette (#1270), etwa Issues aus „Meine Issues“: erst beim Öffnen gefragt, von einem
  // laufenden Modul (#1455).
  Palette.SourceOf := PaletteSourceOfModules;
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
      begin
        Manager.RunServerCommandAsync(ACommand, AArgumentsJson, 10000, ADone);
      end
      else
      begin
        ADone(nil);
      end;
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
  // „Für diesen Befund ein Issue anlegen …“ (#1268): über IAtlasIssueCreation des Moduls Tracker.
  Hooks.CreateIssue :=
    procedure(AFindings: TArray<TAtlasFinding>)
    var
      mItems: TArray<TAtlasIssueFinding>;
    begin
      mItems := IssueFindings(AFindings);
      TAtlasGuard.Run(TAtlasFeature.WelcomePage,
        procedure
        begin
          CreateIssueFromFindings(mItems);
        end);
    end;
  Hooks.CanCreateIssue :=
    function: Boolean
    begin
      Result := CanCreateIssue;
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
  // Rekursionssymbole (#623); fragt den Server nur, wenn er ohnehin läuft.
  GutterMarks.Add(TAtlasIdeRecursionGutter.Create(
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
      begin
        Result := Manager.RunningSession;
      end;
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
      begin
        Result := Manager.RunningSession;
      end;
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
      begin
        Result := Manager.RunningSession;
      end;
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
      begin
        Result := Manager.RunningSession;
      end;
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
      begin
        Manager.OpenCompletion;
      end;
    end);
end;

procedure StartSignatureKey;
begin
  SignatureKey := TAtlasIdeKeyBinding.Create('Atlas.Signature', 'Atlas-Parameter-Hint',
    TAtlasFeature.Signature,
    procedure
    begin
      if Manager <> nil then
      begin
        Manager.OpenSignature;
      end;
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
      begin
        KeyMap.CheckNow;
      end;
      // Neue Aktionen und Tasten für die Tastenkürzel-Tipps (#600).
      if ShortcutTips <> nil then
      begin
        ShortcutTips.KeysChanged;
      end;
    end);
end;

procedure UnwatchKeys;
begin
  TAtlasIdeKeys.UnwatchPackages;
  KeysWatched := False;
end;

procedure StartMainMenu;
begin
  CreateMainMenu;
  MainMenu.OnRename := RenameSymbol;
  MainMenu.OnSetup :=
    procedure
    begin
      if Setup <> nil then
      begin
        Setup.ShowWindow;
      end;
    end;
  MainMenu.OnKeyMap :=
    procedure
    begin
      if KeyMap <> nil then
      begin
        KeyMap.ShowWindow;
      end;
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

/// <summary>Modul-Schalter (#1454) für die Feature-Tabelle; eigene Routine statt anonymer Methode.</summary>
function ModuleOn(const AModule: string): Boolean;
begin
  Result := TAtlasIdeSettings.ModuleOn(AModule);
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
  // Projekt-Zusammenfassungen (#592, #1455): vor Compile, damit Builds sie finden; gehen nach Compile.
  Features.Add('ProjectSummaries', TAtlasSafeLevel.Normal,
    function: Boolean
    begin
      Result := ProjectSummaries <> nil;
    end,
    procedure
    begin
      ProjectSummaries := TAtlasIdeProjectSummaries.Create(
        function: TAtlasProblemStore
        begin
          Result := TAtlasProblemsController.Current;
        end);
      ProjectSummaries.Start;
    end,
    procedure
    begin
      FreeAndNil(ProjectSummaries);
    end);
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
      // Läufer, Wächter und Prüfung (Modul Build-Pipeline) und Bauen beim Öffnen (Modul Build) stoppen mit ihren
      // Modulen vorher.
      if NotificationsVerdict <> nil then
      begin
        NotificationsVerdict.Revoke;
      end;
      NotificationsVerdict := nil;
      FreeAndNil(Compile);
      FreeAndNil(LastBuildMessages);
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
  // Builds für Claude Code (#261, McpBuild) startet das Modul Build-Pipeline.
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
  // Hinweis „Prüfregeln sind aus“ (#1454): je atlas.json mit Regeln einmal, solange das Modul aus ist.
  Features.Add('RuleChecksNotice', TAtlasSafeLevel.Normal,
    function: Boolean
    begin
      Result := RuleChecksNotice <> nil;
    end,
    StartRuleChecksNotice,
    procedure
    begin
      FreeAndNil(RuleChecksNotice);
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
  // Fenster „Atlas-Prüfung“ (#909): liest den Problemspeicher des Managers.
  Features.Add('ProblemsWindow', TAtlasSafeLevel.Normal,
    function: Boolean
    begin
      Result := ProblemsWindowStarted;
    end,
    StartProblemsWindow, StopProblemsWindow);
  // Gemeinsame Zeichenschicht der Rinne: Rekursionssymbole (#623) und die Schichten der Module (Notizen und
  // Lesezeichen, #545, #622, #1455), die sie über die Registry findet.
  Features.AddWanted('GutterMarks',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel <> TAtlasSafeLevel.Minimal) and ((ALevel = TAtlasSafeLevel.Normal) or
        TAtlasIdeSettings.Current.RecursionMarkers or TAtlasIdeGutterMarks.ModuleLayersWanted);
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
  // Module (#1454): Ist der Modul-Schalter aus, startet keines dieser Teile, laufende stoppt RegisterFeatures.
  // Die übrigen Teile eines Moduls folgen ihren eigenen Einstellungen, die bei ausgeschaltetem Modul „aus“
  // liefern (TAtlasModuleSwitches). Angemeldete Module (Debugger, #1455) bringen ihren Schalter selbst mit.
  Features.ModuleOn := ModuleOn;
  // Module zuletzt: Sie bauen auf den Teilen von Base auf und gehen beim Abbau zuerst (#1455).
  ModuleHosting := TAtlasModuleHosting.Create(AtlasModuleRegistry, Features);
end;

/// <summary>Gewünschte, noch fehlende Teile starten (beim Laden und nach jeder Einstellungsänderung); zuvor die
/// laufenden Teile ausgeschalteter Module stoppen (#1454).</summary>
procedure RegisterFeatures;
var
  mFailure: string;
begin
  if Features = nil then
  begin
    AddFeatures;
  end;
  // Ein Modul, das sich nach dem Start anmeldet, startet über denselben Weg (Regel 2).
  if (ModuleHosting <> nil) and not Assigned(ModuleHosting.OnChanged) then
  begin
    ModuleHosting.OnChanged := RegisterFeatures;
  end;
  for mFailure in Features.StopOffModules do
  begin
    TAtlasGuard.Log('Modul ausgeschaltet, Teil nicht sauber gestoppt: ' + mFailure);
  end;
  // Bis zur freien Nachrichtenschleife zählt jedes Teil zu den Startanteilen (Bericht N4).
  Features.Times := StartTimes;
  Features.StartWanted(Level);
  if MainMenu <> nil then
  begin
    MainMenu.UpdateKeyMap;
  end;
  // Abschaltbare Einträge im Kontextmenü des Editors (#1120).
  TAtlasIdeEditorCommands.UpdateContextMenus;
  // Phase und Fortschritt des Servers melden sich aus jedem Thread; gezeichnet wird gesammelt.
  if (Manager <> nil) and (StatusField <> nil) then
  begin
    Manager.OnServerChanged :=
      procedure
      begin
        if StatusField <> nil then
        begin
          StatusField.RequestRefresh;
        end;
      end;
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
      begin
        QuickToggles.Show;
      end;
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
      begin
        SafeMode.RecordFailure(AFeature);
      end;
    end;
end;

/// <summary>Startanteile beenden (Bericht N4): Danach zählen weder Aktionen noch Teile mit.</summary>
procedure EndStartTimes;
begin
  TAtlasActivity.TimeInto(nil);
  if Features <> nil then
  begin
    Features.Times := nil;
  end;
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
  begin
    SafeMode.Loaded(ALoadMs);
  end;
  if StartTimes = nil then
  begin
    Exit;
  end;
  try
    // Erst anhalten, dann lesen: Keine Aktion zählt mehr mit.
    TAtlasActivity.TimeInto(nil);
    Limit := TAtlasIdeSettings.Current.SafeStartupTimeoutMs;
    Line := StartTimes.LogLine(ALoadMs, Limit);
    TAtlasGuard.Log(Line);
    if Manager <> nil then
    begin
      Manager.Log(Line);
    end;
    if TAtlasStartTimes.IsSlow(ALoadMs, Limit) and TAtlasIdeSettings.Current.HangHint then
    begin
      Parts := StartTimes.SlowestText;
      if Parts <> '' then
      begin
        Parts := ': ' + Parts;
      end;
      MessageLine(TAtlasStrings.Fmt(TAtlasTextId.StartSlow, [ALoadMs, Limit, StartTimes.Total, Parts]));
    end;
  finally
    EndStartTimes;
  end;
end;

/// <summary>Dienste von Base für Bereiche wie die Willkommensseite (#1455): Zustand des Servers, Palette,
/// Tastenübersicht, Ausblenden, Snippets und die Knöpfe der Zustandskachel. Fragt die Quellen bei jedem Aufruf neu.
/// </summary>
procedure InstallServerServices(var AServices: TAtlasHostServices);
begin
  AServices.ServerInfo :=
    function: TAtlasServerInfo
    begin
      Result := Default(TAtlasServerInfo);
      if Manager <> nil then
      begin
        Result := Manager.ServerInfo;
      end;
    end;
  AServices.ServerIndexing :=
    function(out APercent: Integer): Boolean
    begin
      APercent := -1;
      Result := (Manager <> nil) and Manager.ServerIndexing(APercent);
    end;
  AServices.IndexedUnits :=
    function: Integer
    begin
      Result := -1;
      if StatusLines <> nil then
      begin
        Result := StatusLines.Units;
      end;
    end;
  AServices.RestartServer :=
    procedure
    begin
      if Manager <> nil then
      begin
        Manager.RestartServer;
      end;
      if StatusField <> nil then
      begin
        StatusField.RequestRefresh;
      end;
    end;
end;

/// <summary>Palette, Tastenübersicht und Ausblenden über das Kontextmenü (#628) für die Module.</summary>
procedure InstallPaletteServices(var AServices: TAtlasHostServices);
begin
  AServices.PaletteCommands :=
    function: TArray<TAtlasCommand>
    begin
      Result := nil;
      if Palette <> nil then
      begin
        Result := Palette.AtlasCommands;
      end;
    end;
  AServices.ExecuteCommand :=
    procedure(AId: string)
    begin
      if Palette <> nil then
      begin
        Palette.Execute(AId);
      end;
    end;
  AServices.ShowPalette :=
    procedure
    begin
      if Palette <> nil then
      begin
        Palette.Show;
      end;
    end;
  AServices.ShowKeyMap :=
    procedure
    begin
      if KeyMap <> nil then
      begin
        KeyMap.ShowAll;
      end;
    end;
  AServices.HideSetting :=
    function(const AKey: string; APoint: TPoint): Boolean
    begin
      Result := HideStarted and TAtlasIdeHide.HideSetting(AKey, APoint);
    end;
end;

/// <summary>Snippets, Optionen, Logordner, Update und Meldungsansicht für die Module.</summary>
procedure InstallShellServices(var AServices: TAtlasHostServices);
begin
  InstallServerServices(AServices);
  InstallPaletteServices(AServices);
  AServices.FileSnippets :=
    function: TAtlasSnippetList
    begin
      Result := nil;
      if (Manager <> nil) and (Manager.Completion <> nil) then
      begin
        Result := Manager.Completion.FileSnippets;
      end;
    end;
  AServices.OpenOptions := OpenAtlasOptions;
  AServices.OpenLogFolder := OpenLogFolder;
  AServices.OpenUpdate :=
    procedure
    begin
      if Updates <> nil then
      begin
        Updates.OpenUpdate;
      end;
    end;
  AServices.ShowMessages := ShowAtlasMessages;
  // Zustandskachel der Willkommensseite (#754): beobachtet die Zeilen des Statusfelds.
  AServices.StatusLinesReady :=
    function: Boolean
    begin
      Result := StatusLines <> nil;
    end;
end;

/// <summary>Dienste von Base für die Module (#1455): laufende Sitzung des Managers und dessen Diagnoselog.</summary>
procedure InstallHost;
var
  mServices: TAtlasHostServices;
begin
  mServices := Default(TAtlasHostServices);
  mServices.Session :=
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
      begin
        Result := Manager.RunningSession;
      end;
    end;
  mServices.ActiveSession :=
    function: TLspSession
    begin
      Result := nil;
      if Manager <> nil then
      begin
        Result := Manager.ActiveSession;
      end;
    end;
  mServices.Log :=
    procedure(AText: string)
    begin
      LogLine(AText);
    end;
  mServices.Warning :=
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end;
  // Anfragen der Module, etwa der Abfrage (#1351): abbrechbar, nur an den laufenden Server.
  mServices.RunRequest :=
    function(const AMethod, AParamsJson: string; ATimeoutMs: Cardinal; const ACancelled: TFunc<Boolean>;
      const ADone: TProc<string>): Boolean
    begin
      Result := (Manager <> nil) and (Manager.RunningSession <> nil);
      if Result then
      begin
        Manager.RunServerRequestAsync(AMethod, AParamsJson, ATimeoutMs, ACancelled, AnswerText(ADone));
      end;
    end;
  mServices.RunCommand :=
    function(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal; const ADone: TProc<string>): Boolean
    begin
      Result := (Manager <> nil) and Manager.RunCommandAsync(ACommand, AArgumentsJson, ATimeoutMs, ADone);
    end;
  // Nebenläufig zu RunCommand (#1455): Fenster, die regelmäßig nachfragen (Unit-Beziehungen, Hotspots), belegen
  // nicht den einen Hintergrundbefehl.
  mServices.RunServerCommand :=
    function(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal; const ADone: TProc<string>): Boolean
    begin
      Result := (Manager <> nil) and (Manager.RunningSession <> nil);
      if Result then
      begin
        Manager.RunServerCommandAsync(ACommand, AArgumentsJson, ATimeoutMs, AnswerText(ADone));
      end;
    end;
  mServices.Report :=
    procedure(AText: string)
    begin
      if Manager <> nil then
      begin
        Manager.Report(AText);
      end;
    end;
  // Felder der Module im Atlas-Statusfeld, etwa Hinweise der schnellen Lesezeichen (#1104).
  mServices.StatusExtra :=
    procedure(const AId, AText, AHint: string; const AOnClick: TProc<TPoint>)
    begin
      if StatusField <> nil then
      begin
        StatusField.SetExtra(AId, AText, AHint, AOnClick);
      end;
    end;
  mServices.CompileEvents :=
    function: TAtlasCompileEvents
    begin
      Result := nil;
      if Compile <> nil then
      begin
        Result := Compile.Events;
      end;
    end;
  InstallShellServices(mServices);
  TAtlasIdeHost.Install(mServices);
end;

/// <summary>Thema an die angemeldeten Module weitergeben (#1455); Fehler eines Moduls ins Protokoll.</summary>
procedure ModulesThemeChanged;
var
  mFailure: string;
begin
  for mFailure in TAtlasModuleContributions.ThemeChanged(AtlasModuleRegistry) do
  begin
    TAtlasGuard.Log('Thema im Modul nicht übernommen: ' + mFailure);
  end;
end;

/// <summary>Geänderte Einstellungen an die angemeldeten Module weitergeben (#1455), z. B. debug.* des Debuggers.</summary>
procedure ModulesApplySettings;
var
  mFailure: string;
begin
  for mFailure in TAtlasModuleContributions.ApplySettings(AtlasModuleRegistry) do
  begin
    TAtlasGuard.Log('Einstellungen im Modul nicht übernommen: ' + mFailure);
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
  // Vor den Modulen: Sie fragen Sitzung und Protokoll über TAtlasIdeHost (#1455).
  InstallHost;
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
      begin
        MainMenu.UpdateImage;
      end;
      if StatusField <> nil then
      begin
        StatusField.RequestRefresh;
      end;
      TAtlasIdeResultsWindow.ApplyTheme;
      TAtlasIdeServerWindow.ApplyTheme;
      if DiagnosticMode <> nil then
      begin
        DiagnosticMode.ThemeChanged;
      end;
      if Setup <> nil then
      begin
        Setup.ThemeChanged;
      end;
      if KeyMap <> nil then
      begin
        KeyMap.ThemeChanged;
      end;
      if ShortcutTips <> nil then
      begin
        ShortcutTips.ThemeChanged;
      end;
      TAtlasIdeProblems.ThemeChanged;
      TAtlasIdeOutline.ThemeChanged;
      TAtlasIdeBreadcrumbs.ThemeChanged;
      TAtlasIdeEditorToolbar.ThemeChanged;
      TAtlasIdeStatusBar.ThemeChanged;
      TAtlasIdeLineChanges.ThemeChanged;
      TAtlasIdeOverviewRuler.ThemeChanged;
      TAtlasIdeMinimap.ThemeChanged;
      // Fenster der Module (#1455).
      ModulesThemeChanged;
    end;
  // Zuerst entscheiden, ob Atlas abgesichert startet (#722): Davon hängt ab, was angemeldet wird.
  if SafeMode = nil then
  begin
    StartSafeMode;
  end;
  // Immer: Statusfeld, Schnellschalter und Einstellungsseite.
  if StatusField = nil then
  begin
    RegisterStatusField;
  end;
  if QuickToggles = nil then
  begin
    QuickToggles := TAtlasIdeQuickToggles.Create(nil);
    QuickToggles.OnAnchor :=
      function: TPoint
      begin
        if (StatusField = nil) or not StatusField.Anchor(Result) then
        begin
          Result := Point(MaxInt, MaxInt);
        end;
      end;
  end;
  if Notifications = nil then
  begin
    StartNotifications;
  end;
  RegisterFeatures;
  TAtlasIdeExperimental.ApplySettings;
  // Geänderte Tastenkürzel sofort neu belegen; fremde Vervollständigung melden (#494).
  TAtlasIdeSettings.OnChanged :=
    procedure
    begin
      // Ein Schnellschalter oder „Normal weiterarbeiten“ im abgesicherten Start meldet nach (#722).
      RegisterFeatures;
      if SafeMode <> nil then
      begin
        SafeMode.UpdateFeatures;
      end;
      // undo.multiFile* (#721).
      TAtlasIdeUndo.ApplySettings;
      // updates.check (#495).
      if Updates <> nil then
      begin
        Updates.ApplySettings;
      end;
      // diagnosticMode.enabled (#479).
      if DiagnosticMode <> nil then
      begin
        DiagnosticMode.ApplySettings;
      end;
      // problems.window* (#909).
      TAtlasIdeProblems.ApplySettings;
      // outline.* (#537).
      TAtlasIdeOutline.ApplySettings;
      // callHierarchy.diagram (#1122).
      TAtlasIdeResultsWindow.ApplySettings;
      // server.statusWindow (#1356).
      TAtlasIdeServerWindow.ApplySettings;
      // navigation.symbolPath (#1117): Kontextmenü „Weg von hier nach …“.
      TAtlasIdeEditorCommands.ApplySettings;
      // editor.breadcrumbs* (#590).
      TAtlasIdeBreadcrumbs.ApplySettings;
      // editor.toolbar* (#1101).
      TAtlasIdeEditorToolbar.ApplySettings;
      // editor.statusBar* (#1155); das Atlas-Feld zieht um oder zurück (RequestRefresh unten).
      TAtlasIdeStatusBar.ApplySettings;
      // editor.stickyScroll* (#506).
      TAtlasIdeStickyScroll.ApplySettings;
      // editor.gitGutter, editor.gitBlame (#507).
      TAtlasIdeLineChanges.ApplySettings;
      // editor.overviewRuler, editor.overviewRulerKinds (#519).
      TAtlasIdeOverviewRuler.ApplySettings;
      // editor.minimap* (#873, experimentell).
      TAtlasIdeMinimap.ApplySettings;
      // notifications.* (#601): an oder aus, Höchstzahl, Verhalten je Quelle.
      if Notifications <> nil then
      begin
        Notifications.ApplySettings;
      end;
      // Projektdatei .atlas an oder aus (#486).
      TAtlasIdeTeamFile.Refresh;
      // Wirksame experimentelle Funktionen im Statusfeld und im Protokoll (#834).
      TAtlasIdeExperimental.ApplySettings;
      // Einstellungen der Module (#1455), z. B. debug.* des Debuggers.
      ModulesApplySettings;
      // tips.usageTracking (#757).
      if CommandUsage <> nil then
      begin
        CommandUsage.ApplySettings;
      end;
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
      begin
        StatusField.RequestRefresh;
      end;
    end;
  // Prüfung und Regelkatalog des Einstellungsdialogs (#227): nur ein laufender Server, keiner wird gestartet.
  TAtlasProjectSettings.Command :=
    function(const ACommand, AArgumentsJson: string): TJSONValue
    begin
      if Manager <> nil then
      begin
        Result := Manager.RunServerCommand(ACommand, AArgumentsJson, 5000);
      end
      else
      begin
        Result := nil;
      end;
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
      begin
        Setup.Start;
      end;
      // Eigene Tasten prüfen, sobald die übrigen Packages ihre Tasten angemeldet haben (#520).
      if KeyMap <> nil then
      begin
        KeyMap.CheckAtStart;
      end;
    end);
end;

/// <summary>Stammt die Klasse von AObject aus Base oder einem angemeldeten Modul (Regel 8, #1456)?</summary>
function OwnClass(AObject: TObject): Boolean;
var
  mModule: NativeUInt;
begin
  Result := False;
  if AObject = nil then
  begin
    Exit;
  end;
  mModule := NativeUInt(FindClassHInstance(AObject.ClassType));
  Result := (mModule = NativeUInt(HInstance)) or
    ((AtlasModuleRegistry <> nil) and AtlasModuleRegistry.IsModuleHandle(mModule));
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
    begin
      Result := ' › ' + Result;
    end;
    Result := Item.ClassName + ' ' + Item.Name + Result;
    if Item.Owner <> nil then
    begin
      Item := Item.Owner;
    end
    else if (Item is TControl) and (TControl(Item).Parent <> nil) then
    begin
      Item := TControl(Item).Parent;
    end
    else
    begin
      Item := nil;
    end;
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
  begin
    if OwnClass(AComponent.Components[Index]) then
    begin
      if not AFound.Contains(AComponent.Components[Index]) then
      begin
        AFound.Add(AComponent.Components[Index]);
      end;
    end
    else
    begin
      CollectLeftovers(AComponent.Components[Index], AFound);
    end;
  end;
  if not (AComponent is TWinControl) then
  begin
    Exit;
  end;
  Control := TWinControl(AComponent);
  for Index := 0 to Control.ControlCount - 1 do
  begin
    if OwnClass(Control.Controls[Index]) then
    begin
      if not AFound.Contains(Control.Controls[Index]) then
      begin
        AFound.Add(Control.Controls[Index]);
      end;
    end
    // Fremde Kinder ohne eigenen Owner-Baum hier (der kommt über Components).
    else if (Control.Controls[Index] is TWinControl) and (Control.Controls[Index].Owner <> AComponent) then
    begin
      CollectLeftovers(Control.Controls[Index], AFound);
    end;
  end;
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
  begin
    Found.Remove(AComponent);
  end;
end;

/// <summary>Modul einer Klasse ('' = unbekannt), für das Protokoll.</summary>
function ModuleOf(AClass: TClass): string;
var
  Buffer: array[0..MAX_PATH] of Char;
begin
  Result := '';
  if GetModuleFileName(FindClassHInstance(AClass), Buffer, MAX_PATH) > 0 then
  begin
    Result := ExtractFileName(Buffer);
  end;
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
    begin
      Continue;
    end;
    for Index := 0 to Form.ComponentCount - 1 do
    begin
      Module := ModuleOf(Form.Components[Index].ClassType);
      // Nur, was nicht aus der IDE selbst stammt.
      if not (StartsText('coreide', Module) or StartsText('vcl', Module) or StartsText('rtl', Module) or
        SameText(Module, 'bds.exe')) then
      begin
        TAtlasGuard.Log(Format('Beim Entladen in %s: %s "%s" aus %s', [Form.Name,
          Form.Components[Index].ClassName, Form.Components[Index].Name, Module]));
      end;
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
    begin
      if OwnClass(Screen.Forms[Index]) then
      begin
        Tracker.Found.Add(Screen.Forms[Index]);
      end
      else
      begin
        CollectLeftovers(Screen.Forms[Index], Tracker.Found);
      end;
    end;
    for Index := 0 to Screen.DataModuleCount - 1 do
    begin
      if not OwnClass(Screen.DataModules[Index]) then
      begin
        CollectLeftovers(Screen.DataModules[Index], Tracker.Found);
      end;
    end;
    CollectLeftovers(Application, Tracker.Found);
    for Item in Tracker.Found do
    begin
      Item.FreeNotification(Tracker);
    end;
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
        begin
          SafeMode.Stop;
        end;
        FreeAndNil(SafeMode);
      end);
    // Rückwärts zur Startreihenfolge (Code-Review S-03): Palette vor den Teilen, deren Befehle sie hält,
    // Tastenkürzel-Tipps und Willkommensseite vor der Zählung, Rinne vor Notizen und Lesezeichen, Prüfung beim
    // Speichern vor den Compiler-Ereignissen, der Manager zuletzt. Alles vor dem Statusfeld: Diagnosemodus,
    // Einrichtung, Update-Prüfung und Willkommensseite haben Zeilen in dessen Registry (#479, #625, #754).
    // Regel 5 (ADR 0017): zuerst alle Module stoppen und abmelden, dann die Teile von Base.
    Teardown.Step('ModuleHosting',
      procedure
      begin
        if ModuleHosting <> nil then
        begin
          ModuleHosting.OnChanged := nil;
        end;
      end);
    Teardown.Step('Modules',
      procedure
      begin
        if AtlasModuleRegistryInstance <> nil then
        begin
          Teardown.AddFailures(AtlasModuleRegistryInstance.ShutDown);
        end;
      end);
    // Erst nach den Modulen: Bis zu ihrem Stopp dürfen sie Sitzung und Protokoll von Base fragen.
    Teardown.Step('Host',
      procedure
      begin
        TAtlasIdeHost.Uninstall;
      end);
    if Features <> nil then
    begin
      Teardown.AddFailures(Features.StopAll);
    end;
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
        FreeAndNil(ModuleHosting);
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
