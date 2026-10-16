unit Atlas.IDE.CodeInsight.Composition;

// Meldet den Code Insight-Manager, die Optionsseite "Atlas" (#227), die
// Compile-Ereignisse (#527), den Einfrier-Wächter (#501), das Neuladen
// extern geänderter Dateien (#536), die Befehlspalette (#502), die farbigen
// Klammerpaare (#514), das Ergebnisfenster (#400), die Editorbefehle samt
// Tastenkürzeln und Kontextmenü (#399), den Abgleich offener Formulare (#402),
// das Atlas-Statusfeld (#591), die Schnellschalter (#604), das
// dateiübergreifende Zurücknehmen von Atlas-Änderungen (#721), die
// Versionsverwaltung (#571), den Diagnosemodus (#479) und die Einrichtung mit
// Prüfliste (#625) beim Laden des
// Packages an und beim Entladen in umgekehrter Reihenfolge wieder ab
// (ADR 0006). Zuerst entscheidet der abgesicherte Start
// (#722), was angemeldet wird; RegisterFeatures holt den Rest nach, sobald
// ein Schnellschalter oder „Normal weiterarbeiten“ es erlaubt.

interface

procedure Register;

implementation

uses
  Winapi.Windows,
  Winapi.ShellAPI,
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Win.Registry,
  System.JSON,
  System.IOUtils,
  System.UITypes,
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
  Atlas.IDE.Settings.Store,
  Atlas.IDE.Diagnostics.Watchdog,
  Atlas.IDE.Diagnostics.Export,
  Atlas.IDE.Diagnostics.BugReport,
  Atlas.IDE.Diagnostics.Timing,
  Atlas.IDE.Setup.Checklist,
  Atlas.IDE.Files.Reloader,
  Atlas.IDE.Commands.Palette,
  Atlas.IDE.Editor.Pairs,
  Atlas.IDE.Editor.Structure,
  Atlas.IDE.Files.DirtyExport,
  Atlas.IDE.Files.EditInbox,
  Atlas.IDE.Build.CheckOnSave,
  Atlas.IDE.Settings.Project,
  Atlas.IDE.Commands.MainMenu,
  Atlas.IDE.Editor.Rename,
  Atlas.Core.Results.Model,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Commands.Editor,
  Atlas.IDE.UnitSearch.Commands,
  Atlas.IDE.Generate.Commands,
  Atlas.Core.Completion.Snippets,
  Atlas.IDE.Commands.Bindings,
  Atlas.IDE.Forms.Designer,
  Atlas.Core.Status.Registry,
  Atlas.Core.Status.Lines,
  Atlas.IDE.Status.Field,
  Atlas.IDE.Status.Lines,
  Atlas.IDE.Settings.QuickToggles,
  Atlas.Core.Diagnostics.SafeMode,
  Atlas.IDE.Diagnostics.SafeMode,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Diagnostics.TimeLimit,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.IDE.Commands.Keys,
  Atlas.IDE.Commands.KeyMap,
  Atlas.IDE.Commands.Usage,
  Atlas.IDE.Commands.ShortcutTips,
  Atlas.Core.Commands.ShortcutTips,
  Atlas.IDE.Undo.Changes,
  Atlas.Core.Updates.Check,
  Atlas.Core.Updates.Adapters.HttpSource,
  Atlas.IDE.Updates.Check,
  Atlas.IDE.Results.Window,
  Atlas.IDE.Style.Symbol,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.WhatsNew,
  Atlas.UI.Welcome.Frame,
  Atlas.Core.Commands.Palette,
  Atlas.IDE.Welcome.Search,
  Atlas.IDE.Welcome.WhatsNew,
  Atlas.IDE.Welcome.Projects,
  Atlas.IDE.Welcome.Trends,
  Atlas.Core.Editor.Metrics,
  Atlas.Core.Projects.Todos,
  Atlas.Core.Projects.Baseline,
  Atlas.UI.Todos.Dialog,
  Atlas.IDE.Welcome.Unsaved,
  Atlas.IDE.Welcome.Continue,
  Atlas.IDE.Welcome.State,
  Atlas.IDE.Welcome.Discover,
  Atlas.IDE.Welcome.Help,
  Atlas.IDE.Welcome.Commands,
  Atlas.IDE.Vcs.Service,
  Atlas.IDE.Notes.Service,
  Atlas.IDE.Notes.Gutter,
  Atlas.IDE.Bookmarks.Service,
  Atlas.IDE.Bookmarks.Gutter,
  Atlas.IDE.Editor.GutterMarks,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.IDE.Editor.TestUnitLens,
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
  Atlas.Core.Diagnostics.FeatureTable;

var
  ManagerIndex: Integer = -1;
  // Gehört der IDE (Schnittstellenzähler); gültig, solange er angemeldet ist.
  Manager: TAtlasCodeInsightManager;
  Compile: TAtlasIdeCompileEvents;
  Watchdog: TAtlasWatchdog;
  Hangs: TAtlasHangMonitor;
  Reloader: TAtlasFileReloader;
  Palette: TAtlasIdePalette;
  Pairs: TAtlasEditorPairs;
  // Markierungen in der Rinne: persönliche Notizen (#545) und benannte Lesezeichen (#622).
  GutterMarks: TAtlasIdeGutterMarks;
  // Ungespeicherte Dateien für schreibende MCP-Werkzeuge (#61).
  DirtyExport: TAtlasDirtyExport;
  // Schreibende MCP-Werkzeuge ändern offene Dateien über das Plugin (#397).
  EditInbox: TAtlasIdeEditInbox;
  CheckOnSave: TAtlasIdeCheckOnSave;
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
  // Zeitpunkt des Ladens (TAtlasWatchdog.Timestamp) für Wächter und Ladezeit.
  LoadedAt: Int64;
  // Laden abgeschlossen: Später angemeldete Teile messen ab dann.
  StartupDone: Boolean;
  // Paketbeobachtung und Meldung fremder Vervollständigung angemeldet (#494).
  KeysWatched: Boolean;
  // Atlas-Bereiche auf der Willkommensseite und Fenster „Atlas-Start“ (#753).
  Welcome: TAtlasIdeWelcome;
  // Dienste für Notizen (#545) und Lesezeichen (#622) gestartet.
  NotesStarted: Boolean;
  BookmarksStarted: Boolean;
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
    function(const ACommand, AArgumentsJson: string): TJSONValue
    begin
      if Manager <> nil then
        Result := Manager.RunServerCommand(ACommand, AArgumentsJson, 10000)
      else
        Result := nil;
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
end;

/// <summary>„Baseline des Projekts aktualisieren“ (#97): nennt vorher die Einträge ohne Datei und fragt nach, lässt
/// den Server (atlas.updateBaseline) im Hintergrund alle Dateien prüfen und die Baseline schreiben, meldet die
/// Zähler und schreibt den Abschnitt "baseline" der Projekt-Zusammenfassung.</summary>
procedure UpdateBaseline;
var
  Project: IOTAProject;
  FileName: string;
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
  if Manager.RunCommandAsync(TAtlasProjectBaselines.Command,
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
                Exit;
              end;
              if (Welcome <> nil) and (Welcome.Projects <> nil) then
                Welcome.Projects.RecordBaseline(FileName, After, Update, TAtlasIdeProjects.StampUtc);
            end);
        end);
    end) then
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.BaselineUpdateRunning))
  else
    // Ein Befehl im Hintergrund läuft schon (etwa die Werte nach einem Build): später noch einmal.
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.BaselineUpdateBusy));
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

// Sichtbarkeit von Palettenbefehlen nach Einstellung.
function BaselineUpdateVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.BaselineUpdate;
end;

function BookmarksNamedVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.BookmarksNamed;
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

function NotesVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Notes;
end;

function TodoListVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TodoList;
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
  Add('Atlas.Callers', TAtlasTextId.MenuIncoming, Hierarchy(TAtlasHierarchyDirection.Incoming));
  Add('Atlas.Calls', TAtlasTextId.MenuOutgoing, Hierarchy(TAtlasHierarchyDirection.Outgoing));
  Add('Atlas.Supertypes', TAtlasTextId.MenuSupertypes, Hierarchy(TAtlasHierarchyDirection.Supertypes));
  Add('Atlas.Subtypes', TAtlasTextId.MenuSubtypes, Hierarchy(TAtlasHierarchyDirection.Subtypes));
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
    Guarded(TAtlasFeature.Bookmarks, TAtlasIdeBookmarks.ShowWindow), BookmarksNamedVisible);
  // Erzeugen-Menü (#719); nur sichtbar, solange keys.generateMenu an ist.
  Add('Atlas.GenerateMenu', TAtlasTextId.GenerateMenuCommand,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.EditorCommands,
        procedure
        begin
          TAtlasIdeGenerate.Show;
        end);
    end, GenerateMenuVisible);
  // Editorbefehle (#399).
  Add('Atlas.CodeActions', TAtlasTextId.EditorActions, TAtlasIdeEditorCommands.CodeActions);
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
  Add('Atlas.UnitSearchIde', TAtlasTextId.UnitSearchIdeDialog, TAtlasIdeUnitSearch.ShowIdeDialog);
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
  // Karte „Neu in Atlas“ (#756): wie das Kontextmenü; zeigt die Willkommensseite bzw. „Atlas-Start“.
  Add('Atlas.WhatsNew', TAtlasTextId.WelcomeNewsShowCurrent,
    procedure
    begin
      if (Welcome <> nil) and (Welcome.WhatsNew <> nil) and TAtlasIdeSettings.Current.WelcomePage then
        Welcome.ShowWhatsNew(TAtlasWhatsNewView.Current);
    end);
  Add('Atlas.WhatsNewAll', TAtlasTextId.WelcomeNewsShowAllCommand,
    procedure
    begin
      if (Welcome <> nil) and (Welcome.WhatsNew <> nil) and TAtlasIdeSettings.Current.WelcomePage then
        Welcome.ShowWhatsNew(TAtlasWhatsNewView.All);
    end);
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
end;

procedure UnregisterStatusField;
begin
  if Manager <> nil then
    Manager.OnServerChanged := nil;
  FreeAndNil(StatusField);
  FreeAndNil(StatusLines);
  TAtlasStatusRegistry.ReleaseDefault;
end;

procedure RegisterWatchdog(ALoadedAt: Int64);
begin
  Hangs := TAtlasHangMonitor.Create(TAtlasIdeSettings.Current.HangThresholdMs);
  Watchdog := TAtlasWatchdog.Create(ALoadedAt,
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.HangThresholdMs;
    end);
  Watchdog.OnHang := ReportHang;
  Watchdog.OnStartup :=
    procedure(AMilliseconds: Int64)
    begin
      if Manager <> nil then
        Manager.Log(Format('Start: Laden des Packages bis zur freien Nachrichtenschleife %d ms', [AMilliseconds]));
    end;
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
    function(ACommand: string): TJSONValue
    begin
      if Manager <> nil then
        Result := Manager.ExecuteServerCommand(ACommand)
      else
        Result := nil;
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
        // Die aktive Sitzung startet den Server, wenn er noch nicht läuft.
        Result := Manager.ActiveSession <> nil;
    end;
  Hooks.ServerCommand :=
    function(ACommand: string): TJSONValue
    begin
      if Manager <> nil then
        Result := Manager.ExecuteServerCommand(ACommand)
      else
        Result := nil;
    end;
  Hooks.ServerPath :=
    function: string
    var
      Arguments: string;
    begin
      Result := TAtlasCodeInsightManager.ServerPath(Arguments);
    end;
  Setup := TAtlasIdeSetupChecklist.Create(TAtlasStatusRegistry.Default, Hooks);
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
    function(ACommand: string): TJSONValue
    begin
      // Kennzahlen, „Index neu aufbauen“ und „Index löschen“ der Einstellungsseite (#492).
      if Manager <> nil then
        Result := Manager.ExecuteServerCommand(ACommand)
      else
        Result := nil;
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
    ManagerIndex := Services.AddCodeInsightManager(Manager);
  end;
end;

procedure StopManager;
var
  Services: IOTACodeInsightServices;
begin
  if (ManagerIndex >= 0) and Supports(BorlandIDEServices, IOTACodeInsightServices, Services) then
    Services.RemoveCodeInsightManager(ManagerIndex);
  ManagerIndex := -1;
  Manager := nil;
end;

procedure StartWatchdog;
begin
  // Später angemeldet (Schnellschalter) misst der Wächter ab jetzt, beim Laden ab dem Laden.
  if StartupDone then
    RegisterWatchdog(TAtlasWatchdog.Timestamp)
  else
    RegisterWatchdog(LoadedAt);
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
  // Klick auf die Testunit-Lens (#189); die Lens kennt die Editorbefehle nicht (A-09).
  TAtlasEditorTestUnitLens.OnSwitchTestUnit :=
    procedure
    begin
      TAtlasIdeEditorCommands.SwitchTestUnit;
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
end;

procedure StopCommands;
begin
  TAtlasIdeUnitSearch.Uninstall;
  TAtlasIdeGenerate.Uninstall;
  TAtlasEditorTestUnitLens.OnSwitchTestUnit := nil;
  TAtlasIdeEditorCommands.Uninstall;
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
    end);
  BookmarksStarted := True;
end;

procedure StopBookmarks;
begin
  TAtlasIdeBookmarks.Release;
  BookmarksStarted := False;
end;

procedure StartGutterMarks;
begin
  GutterMarks := TAtlasIdeGutterMarks.Create;
  GutterMarks.Add(TAtlasIdeNotesGutter.Create);
  GutterMarks.Add(TAtlasIdeBookmarksGutter.Create);
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
  // Bereich „Nicht gesichert“ (#762): nicht Gesichertes je Projekt über die VCS-Schnittstelle (#571).
  Welcome.Unsaved := TAtlasIdeUnsaved.Create(
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end);
  // Bereich „Weiterarbeiten“ (#755): Arbeitsstand beim Schließen, eingehende Commits (#571) und „Gemerkt“.
  Welcome.ContinueWork := TAtlasIdeContinue.Create(
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end);
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
end;

procedure StopWelcome;
begin
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
  Features.Add('Compile',
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
      FreeAndNil(Compile);
    end);
  Features.Add('Watchdog', TAtlasSafeLevel.Normal,
    function: Boolean
    begin
      Result := Watchdog <> nil;
    end,
    StartWatchdog, UnregisterWatchdog);
  Features.Add('CheckOnSave',
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
  Features.Add('Setup',
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
  Features.Add('ShortcutTips',
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
  // Editor-Zeichnungen.
  Features.Add('Pairs',
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
  // Nach Notizen und Lesezeichen, Abbau davor: Die Rinne liest deren Listen (#545, #622).
  Features.Add('GutterMarks',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel <> TAtlasSafeLevel.Minimal) and ((ALevel = TAtlasSafeLevel.Normal) or
        TAtlasIdeSettings.Current.Notes or TAtlasIdeSettings.Current.BookmarksNamed);
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
  Features.Add('CompletionKey',
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
  Features.Add('SignatureKey',
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
  Features.Add('Welcome',
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := (ALevel <> TAtlasSafeLevel.Minimal) and (StatusLines <> nil);
    end,
    function: Boolean
    begin
      Result := Welcome <> nil;
    end,
    StartWelcome, StopWelcome);
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
  Features.StartWanted(Level);
  if Welcome <> nil then
    Welcome.Sync;
  if MainMenu <> nil then
  begin
    MainMenu.UpdateWelcome;
    MainMenu.UpdateKeyMap;
  end;
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

procedure Register;
begin
  LoadedAt := TAtlasWatchdog.Timestamp;
  StartupDone := False;
  // Abbruchsignal eines früheren Entladens in derselben Sitzung zurücknehmen (#493).
  TAtlasShutdown.Reset;
  // Einreihen in den Hauptthread wieder annehmen (nach einem früheren Unregister, Code-Review A-02).
  TAtlasMainThread.Start;
  TAtlasTimeLimit.LimitMs := TAtlasIdeSettings.Current.ProviderTimeLimitMs;
  TAtlasGuard.OnWarning := GuardWarning;
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
      TAtlasIdeResultsWindow.UpdateIcon;
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
  RegisterFeatures;
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
  // Ladezeit bis zur freien Nachrichtenschleife: zu lange zählt beim nächsten Start wie ein Absturz (#722).
  TAtlasMainThread.ForceQueue(TAtlasFeature.Settings,
    procedure
    begin
      StartupDone := True;
      if SafeMode <> nil then
        SafeMode.Loaded(TAtlasWatchdog.Timestamp - LoadedAt);
      // Prüfliste beim ersten Start bzw. solange ein Punkt fest gelb oder rot ist (#625).
      if Setup <> nil then
        Setup.Start;
      // Eigene Tasten prüfen, sobald die übrigen Packages ihre Tasten angemeldet haben (#520).
      if KeyMap <> nil then
        KeyMap.CheckAtStart;
    end);
end;

procedure Unregister;
var
  StartedAt: UInt64;
  Stopped: Boolean;
begin
  // Zuerst das gemeinsame Abbruchsignal: Jeder Hintergrund-Thread hört auf zu warten (#493).
  StartedAt := TThread.GetTickCount64;
  TAtlasShutdown.Signal;
  // Vor allem anderen: Was jetzt noch wartet oder während des Abbaus eingereiht wird, liefe nach dem Entladen
  // in nicht mehr geladenem Code (Code-Review A-02). Queue im Hauptthread läuft weiter sofort.
  TAtlasMainThread.Stop;
  TAtlasIdeVcs.Stop;
  TAtlasGuard.OnWarning := nil;
  TAtlasGuard.OnFailure := nil;
  TAtlasIdeSettings.OnChanged := nil;
  // Sauberes Ende: Startmarke löschen, Absturzzähler zurück (#722).
  if SafeMode <> nil then
    SafeMode.Stop;
  FreeAndNil(SafeMode);
  // Rückwärts zur Startreihenfolge (Code-Review S-03): Palette vor den Teilen, deren Befehle sie hält,
  // Tastenkürzel-Tipps und Willkommensseite vor der Zählung, Rinne vor Notizen und Lesezeichen, Prüfung beim
  // Speichern vor den Compiler-Ereignissen, der Manager zuletzt. Alles vor dem Statusfeld: Diagnosemodus,
  // Einrichtung, Update-Prüfung und Willkommensseite haben Zeilen in dessen Registry (#479, #625, #754).
  if Features <> nil then
    Features.StopAll;
  FreeAndNil(QuickToggles);
  UnregisterStatusField;
  TAtlasOptionsRegistration.Unregister;
  TAtlasProjectSettings.Command := nil;
  TAtlasIdeHistory.Release;
  TAtlasIdeFavorites.Release;
  TAtlasIdeSymbol.Unregister;
  TAtlasIdeSettings.Release;
  Stopped := TAtlasTimeLimit.StopAll(TAtlasShutdown.StopMs);
  FreeAndNil(Features);
  TAtlasGuard.Log(Format('Atlas entladen in %d ms; Hintergrund-Threads beendet: %s',
    [TThread.GetTickCount64 - StartedAt, BoolToStr(Stopped, True)]));
end;

initialization

finalization
  Unregister;

end.
