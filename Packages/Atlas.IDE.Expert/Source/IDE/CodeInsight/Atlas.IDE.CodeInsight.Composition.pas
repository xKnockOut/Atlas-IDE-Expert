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
  Atlas.IDE.Editor.GutterMarks;

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

/// <summary>„Symbol umbenennen…“ (#397) aus Menü und Palette.</summary>
/// <summary>„Fehlerbericht erstellen…“ (#108) aus Menü, Palette und dem Fenster des abgesicherten Starts.</summary>
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

procedure RenameSymbol;
begin
  if Manager = nil then
    Exit;
  TAtlasIdeRename.Execute(Manager.ActiveSession, TAtlasIdeSettings.Current.OpenForEdits,
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end);
end;

procedure RegisterPalette;
begin
  Palette := TAtlasIdePalette.Create;
  Palette.RegisterCommand('Atlas.Log', TAtlasStrings.Text(TAtlasTextId.PaletteLog), '',
    procedure
    var
      Actions: IOTAActionServices;
    begin
      if Supports(BorlandIDEServices, IOTAActionServices, Actions) and FileExists(TAtlasCodeInsightManager.DiagnoseLog) then
        Actions.OpenFile(TAtlasCodeInsightManager.DiagnoseLog);
    end);
  Palette.RegisterCommand('Atlas.Rename', TAtlasStrings.Text(TAtlasTextId.RenameMenu), '',
    procedure
    begin
      RenameSymbol;
    end);
  // Ergebnisfenster (#400).
  Palette.RegisterCommand('Atlas.References', TAtlasStrings.Text(TAtlasTextId.MenuReferences), '',
    procedure
    begin
      TAtlasIdeResults.FindReferences;
    end);
  Palette.RegisterCommand('Atlas.Implementations', TAtlasStrings.Text(TAtlasTextId.MenuImplementations), '',
    procedure
    begin
      TAtlasIdeResults.FindImplementations;
    end);
  Palette.RegisterCommand('Atlas.SymbolSearch', TAtlasStrings.Text(TAtlasTextId.MenuSymbolSearch), '',
    procedure
    begin
      TAtlasIdeResults.SearchSymbol;
    end);
  Palette.RegisterCommand('Atlas.Callers', TAtlasStrings.Text(TAtlasTextId.MenuIncoming), '',
    procedure
    begin
      TAtlasIdeResults.ShowHierarchy(TAtlasHierarchyDirection.Incoming);
    end);
  Palette.RegisterCommand('Atlas.Calls', TAtlasStrings.Text(TAtlasTextId.MenuOutgoing), '',
    procedure
    begin
      TAtlasIdeResults.ShowHierarchy(TAtlasHierarchyDirection.Outgoing);
    end);
  Palette.RegisterCommand('Atlas.Supertypes', TAtlasStrings.Text(TAtlasTextId.MenuSupertypes), '',
    procedure
    begin
      TAtlasIdeResults.ShowHierarchy(TAtlasHierarchyDirection.Supertypes);
    end);
  Palette.RegisterCommand('Atlas.Subtypes', TAtlasStrings.Text(TAtlasTextId.MenuSubtypes), '',
    procedure
    begin
      TAtlasIdeResults.ShowHierarchy(TAtlasHierarchyDirection.Subtypes);
    end);
  Palette.RegisterCommand('Atlas.ResultsWindow', TAtlasStrings.Text(TAtlasTextId.MenuResultsWindow), '',
    procedure
    begin
      TAtlasIdeResults.ShowWindow;
    end);
  // Atlas-Änderungen über mehrere Dateien (#721).
  Palette.RegisterCommand('Atlas.UndoChange', TAtlasStrings.Text(TAtlasTextId.UndoMenu), '',
    procedure
    begin
      TAtlasIdeUndo.UndoLast;
    end);
  Palette.RegisterCommand('Atlas.RedoChange', TAtlasStrings.Text(TAtlasTextId.RedoMenu), '',
    procedure
    begin
      TAtlasIdeUndo.RedoLast;
    end);
  Palette.RegisterCommand('Atlas.ChangeList', TAtlasStrings.Text(TAtlasTextId.UndoListMenu), '',
    procedure
    begin
      TAtlasIdeUndo.ShowList;
    end);
  // Persönliche Notizen (#545); nur sichtbar, solange die Einstellung an ist.
  Palette.RegisterCommand('Atlas.NoteAdd', TAtlasStrings.Text(TAtlasTextId.NotesMenuAdd), '',
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Notes,
        procedure
        begin
          TAtlasIdeNotes.AddOrEdit;
        end);
    end,
    function: Boolean
    begin
      Result := TAtlasIdeSettings.Current.Notes;
    end);
  Palette.RegisterCommand('Atlas.NoteDelete', TAtlasStrings.Text(TAtlasTextId.NotesMenuDelete), '',
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Notes,
        procedure
        begin
          TAtlasIdeNotes.DeleteAtLine;
        end);
    end,
    function: Boolean
    begin
      Result := TAtlasIdeSettings.Current.Notes;
    end);
  Palette.RegisterCommand('Atlas.NoteList', TAtlasStrings.Text(TAtlasTextId.NotesMenuList), '',
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Notes,
        procedure
        begin
          TAtlasIdeNotes.ShowList;
        end);
    end,
    function: Boolean
    begin
      Result := TAtlasIdeSettings.Current.Notes;
    end);
  // Benannte Lesezeichen (#622); nur sichtbar, solange bookmarks.named an ist.
  Palette.RegisterCommand('Atlas.BookmarkAdd', TAtlasStrings.Text(TAtlasTextId.BookmarksMenuAdd), '',
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Bookmarks,
        procedure
        begin
          TAtlasIdeBookmarks.AddBookmark;
        end);
    end,
    function: Boolean
    begin
      Result := TAtlasIdeSettings.Current.BookmarksNamed;
    end);
  Palette.RegisterCommand('Atlas.BookmarkGoTo', TAtlasStrings.Text(TAtlasTextId.BookmarksMenuGoTo), '',
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Bookmarks,
        procedure
        begin
          TAtlasIdeBookmarks.GoToBookmark;
        end);
    end,
    function: Boolean
    begin
      Result := TAtlasIdeSettings.Current.BookmarksNamed;
    end);
  Palette.RegisterCommand('Atlas.BookmarkWindow', TAtlasStrings.Text(TAtlasTextId.BookmarksMenuWindow), '',
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Bookmarks,
        procedure
        begin
          TAtlasIdeBookmarks.ShowWindow;
        end);
    end,
    function: Boolean
    begin
      Result := TAtlasIdeSettings.Current.BookmarksNamed;
    end);
  // Editorbefehle (#399).
  Palette.RegisterCommand('Atlas.CodeActions', TAtlasStrings.Text(TAtlasTextId.EditorActions), '',
    procedure
    begin
      TAtlasIdeEditorCommands.CodeActions;
    end);
  Palette.RegisterCommand('Atlas.ExpandSelection', TAtlasStrings.Text(TAtlasTextId.EditorExpand), '',
    procedure
    begin
      TAtlasIdeEditorCommands.ExpandSelection;
    end);
  Palette.RegisterCommand('Atlas.ShrinkSelection', TAtlasStrings.Text(TAtlasTextId.EditorShrink), '',
    procedure
    begin
      TAtlasIdeEditorCommands.ShrinkSelection;
    end);
  Palette.RegisterCommand('Atlas.TypeDefinition', TAtlasStrings.Text(TAtlasTextId.EditorTypeDefinition), '',
    procedure
    begin
      TAtlasIdeEditorCommands.GoToTypeDefinition;
    end);
  Palette.RegisterCommand('Atlas.ToggleMethod', TAtlasStrings.Text(TAtlasTextId.EditorMethodToggle), '',
    procedure
    begin
      TAtlasIdeEditorCommands.ToggleMethod;
    end);
  Palette.RegisterCommand('Atlas.CopyQualifiedName', TAtlasStrings.Text(TAtlasTextId.EditorCopyQualified), '',
    procedure
    begin
      TAtlasIdeEditorCommands.CopyQualifiedName(False);
    end);
  Palette.RegisterCommand('Atlas.CopyQualifiedNameParams', TAtlasStrings.Text(TAtlasTextId.EditorCopyQualifiedParams),
    '',
    procedure
    begin
      TAtlasIdeEditorCommands.CopyQualifiedName(True);
    end);
  Palette.RegisterCommand('Atlas.SwitchTestUnit', TAtlasStrings.Text(TAtlasTextId.EditorTestUnit), '',
    procedure
    begin
      TAtlasIdeEditorCommands.SwitchTestUnit;
    end);
  Palette.RegisterCommand('Atlas.UnitSearch', TAtlasStrings.Text(TAtlasTextId.UnitSearchTitle), '',
    procedure
    begin
      TAtlasIdeUnitSearch.Show;
    end);
  Palette.RegisterCommand('Atlas.UnitSearchIde', TAtlasStrings.Text(TAtlasTextId.UnitSearchIdeDialog), '',
    procedure
    begin
      TAtlasIdeUnitSearch.ShowIdeDialog;
    end);
  Palette.RegisterCommand('Atlas.ResetHistory', TAtlasStrings.Text(TAtlasTextId.PaletteResetHistory), '',
    procedure
    begin
      TAtlasIdeHistory.Reset;
    end);
  Palette.RegisterCommand('Atlas.CheckNow', TAtlasStrings.Text(TAtlasTextId.PaletteCheckNow), '',
    procedure
    begin
      if CheckOnSave <> nil then
        CheckOnSave.CheckNow;
    end);
  Palette.RegisterCommand('Atlas.ExportDiagnostics', TAtlasStrings.Text(TAtlasTextId.DiagExportMenu), '',
    procedure
    begin
      TAtlasIdeDiagnosticExport.Execute(
        procedure(AText: string)
        begin
          GuardWarning(AText);
        end);
    end);
  Palette.RegisterCommand('Atlas.BugReport', TAtlasStrings.Text(TAtlasTextId.BugReportMenu), '',
    procedure
    begin
      CreateBugReport;
    end);
  Palette.RegisterCommand('Atlas.ProjectSettings', TAtlasStrings.Text(TAtlasTextId.ProjectSettingsTitle), '',
    procedure
    begin
      TAtlasProjectSettings.Execute;
    end);
  Palette.RegisterCommand('Atlas.WelcomeStart', TAtlasStrings.Text(TAtlasTextId.MenuWelcomeStart), '',
    procedure
    begin
      if (Welcome <> nil) and TAtlasIdeSettings.Current.WelcomePage then
        Welcome.ShowStart;
    end);
  Palette.RegisterCommand('Atlas.WelcomeApply', TAtlasStrings.Text(TAtlasTextId.MenuWelcomeApply), '',
    procedure
    begin
      if (Welcome <> nil) and TAtlasIdeSettings.Current.WelcomePage then
        Welcome.ApplyLayout;
    end);
  Palette.RegisterCommand('Atlas.WelcomeReset', TAtlasStrings.Text(TAtlasTextId.MenuWelcomeReset), '',
    procedure
    begin
      if Welcome <> nil then
        Welcome.ResetLayout;
    end);
  // Karte „Neu in Atlas“ (#756): wie das Kontextmenü; zeigt die Willkommensseite bzw. „Atlas-Start“.
  Palette.RegisterCommand('Atlas.WhatsNew', TAtlasStrings.Text(TAtlasTextId.WelcomeNewsShowCurrent), '',
    procedure
    begin
      if (Welcome <> nil) and (Welcome.WhatsNew <> nil) and TAtlasIdeSettings.Current.WelcomePage then
        Welcome.ShowWhatsNew(TAtlasWhatsNewView.Current);
    end);
  Palette.RegisterCommand('Atlas.WhatsNewAll', TAtlasStrings.Text(TAtlasTextId.WelcomeNewsShowAllCommand), '',
    procedure
    begin
      if (Welcome <> nil) and (Welcome.WhatsNew <> nil) and TAtlasIdeSettings.Current.WelcomePage then
        Welcome.ShowWhatsNew(TAtlasWhatsNewView.All);
    end);
  // Bereich „Weiterarbeiten“ (#755): obersten Arbeitsstand fortsetzen.
  Palette.RegisterCommand('Atlas.Continue', TAtlasStrings.Text(TAtlasTextId.WelcomeContinueCommand), '',
    procedure
    begin
      if (Welcome <> nil) and (Welcome.ContinueWork <> nil) then
        Welcome.ContinueWork.ResumeLatest;
    end);
  Palette.RegisterCommand('Atlas.HangTest', TAtlasStrings.Text(TAtlasTextId.SettingsHangTest), '',
    procedure
    var
      Activity: IInterface;
    begin
      Activity := TAtlasActivity.Scope('Wächter-Test');
      Sleep(1000);
    end);
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
    begin
      Messages := TAtlasCompilerMessages.Resolve(AMessages, AProject.FileName, KnownFiles(AProject.FileName));
      // Projekt-Zusammenfassung für die Willkommensseite (#592): letzter Build bzw. letzte Hintergrundprüfung.
      Project := AProject;
      Succeeded := ASucceeded;
      Readable := AReadable;
      if (Welcome <> nil) and (Welcome.Projects <> nil) then
        TAtlasGuard.Run(TAtlasFeature.WelcomePage,
          procedure
          begin
            Welcome.Projects.Recorded(Messages, Project, Succeeded, Readable);
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
  Setup := TAtlasIdeSetupChecklist.Create(TAtlasStatusRegistry.Default, Hooks);
end;

/// <summary>Meldet an, was die Stufe des abgesicherten Starts (#722) und die Einstellungen erlauben; mehrfach
/// aufrufbar. Normal: alles. Abgesichert: Serververbindung, Statusfeld, Einstellungen, Palette und Menü; dazu,
/// was ein Schnellschalter wieder einschaltet. Minimal: nur Einstellungsseite und Statusfeld.</summary>
procedure RegisterFeatures;
var
  Services: IOTACodeInsightServices;
  Settings: TAtlasPluginSettings;
  Full, Basic: Boolean;
begin
  Settings := TAtlasIdeSettings.Current;
  Full := Level = TAtlasSafeLevel.Normal;
  Basic := Level <> TAtlasSafeLevel.Minimal;
  if Basic and (ManagerIndex < 0) and Supports(BorlandIDEServices, IOTACodeInsightServices, Services) then
  begin
    Manager := TAtlasCodeInsightManager.Create;
    ManagerIndex := Services.AddCodeInsightManager(Manager);
  end;
  // Notifier und Hintergrundaufgaben nur im normalen Betrieb bzw. wenn ihr Schalter wieder an ist.
  if (Compile = nil) and (Full or Settings.CheckOnSave) then
    RegisterCompileEvents;
  if (Watchdog = nil) and Full and StartupDone then
    RegisterWatchdog(TAtlasWatchdog.Timestamp)
  else if (Watchdog = nil) and Full then
    RegisterWatchdog(LoadedAt);
  if (CheckOnSave = nil) and (Compile <> nil) then
    CheckOnSave := TAtlasIdeCheckOnSave.Create(Compile.Events,
      procedure(AText: string)
      begin
        if Manager <> nil then
          Manager.Report(AText);
      end);
  if Basic and not CommandsInstalled then
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
  // Änderungsprotokoll vor den Tasten: Strg+Alt+Z braucht es (#721).
  if Basic and (TAtlasIdeUndo.Journal = nil) then
    TAtlasIdeUndo.Start(
      procedure(AText: string)
      begin
        GuardWarning(AText);
      end,
      procedure(AText: string)
      begin
        TAtlasGuard.Log(AText);
      end);
  // Update-Prüfung nur nach Zustimmung und höchstens einmal täglich (#495).
  if Basic and (Updates = nil) then
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
  if Basic and (EditorKeys = nil) then
    EditorKeys := TAtlasIdeEditorKeys.Create;
  // Designer-Notifier nur im normalen Betrieb (#722).
  if Full and (Forms = nil) then
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
  // Diagnosemodus (#479): ohne Einstellung nur Taste und Befehl, keine Messung.
  if Basic and (DiagnosticMode = nil) then
    DiagnosticMode := TAtlasIdeDiagnosticMode.Create(TAtlasStatusRegistry.Default);
  // Einrichtung (#625): auch abgesichert, sie fragt den Server nie selbst und startet ihn nur auf Knopfdruck.
  if Basic and (Setup = nil) and (StatusLines <> nil) then
    CreateSetup;
  // Tastenkürzel-Übersicht (#520): auch abgesichert, sie liest nur die Belegungen der IDE.
  if Basic and (KeyMap = nil) then
    KeyMap := TAtlasIdeKeyMap.Create;
  // Gemeinsame Zählung (#757): vor den Tastenkürzel-Tipps und der Willkommensseite, die sie nutzen.
  if Basic and (CommandUsage = nil) then
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
  // Tastenkürzel-Tipps (#600): Beobachtung an oder aus nach shortcutTips.enabled (ApplySettings); zählt auch
  // für „Atlas entdecken“ (#757), solange die Karte und die Zählung an sind.
  if Full and (ShortcutTips = nil) and (CommandUsage <> nil) then
  begin
    ShortcutTips := TAtlasIdeShortcutTips.Create(CommandUsage);
    ShortcutTips.CountAlways := Settings.WelcomePage and Settings.WelcomePageDiscover and
      Settings.TipsUsageTracking;
  end;
  if Basic and (Palette = nil) then
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
  // Editor-Zeichnungen.
  if (Pairs = nil) and (Full or Settings.PairColors or Settings.PairGuides or Settings.InactiveDim) then
    Pairs := TAtlasEditorPairs.Create;
  // Persönliche Notizen (#545): Befehle auch abgesichert (nur lokale Dateien), die Rinne wie die übrigen
  // Zeichnungen nur im normalen Start oder mit eingeschalteter Einstellung.
  if Basic then
    TAtlasIdeNotes.Start(
      procedure(AText: string)
      begin
        MessageLine(AText);
      end);
  // Benannte Lesezeichen (#622): Befehle auch abgesichert; die Rinne teilt sich die Zeichenschicht mit den
  // Notizen, jede Schicht folgt ihrer Einstellung.
  if Basic then
    TAtlasIdeBookmarks.Start(
      procedure(AText: string)
      begin
        MessageLine(AText);
      end);
  if (GutterMarks = nil) and Basic and (Full or Settings.Notes or Settings.BookmarksNamed) then
  begin
    GutterMarks := TAtlasIdeGutterMarks.Create;
    GutterMarks.Add(TAtlasIdeNotesGutter.Create);
    GutterMarks.Add(TAtlasIdeBookmarksGutter.Create);
  end;
  if (CompletionKey = nil) and Basic and (Full or Settings.Enabled) then
    CompletionKey := TAtlasIdeKeyBinding.Create('Atlas.Completion', 'Atlas-Vervollständigung',
      TAtlasFeature.Completion,
      procedure
      begin
        if Manager <> nil then
          Manager.OpenCompletion;
      end);
  if (SignatureKey = nil) and Basic and (Full or Settings.Enabled) then
    SignatureKey := TAtlasIdeKeyBinding.Create('Atlas.Signature', 'Atlas-Parameter-Hint',
      TAtlasFeature.Signature,
      procedure
      begin
        if Manager <> nil then
          Manager.OpenSignature;
      end);
  if Basic and not KeysWatched then
  begin
    KeysWatched := True;
    TThread.ForceQueue(nil,
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
  // Willkommensseite (#753): auch abgesichert, sie startet keinen Server und liest nur lokale Daten.
  if Basic and (Welcome = nil) and (StatusLines <> nil) then
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
  if Welcome <> nil then
    Welcome.Sync;
  if Basic and (MainMenu = nil) then
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
  if (DirtyExport = nil) and Full then
    DirtyExport := TAtlasDirtyExport.Create;
  if (EditInbox = nil) and Full then
    EditInbox := TAtlasIdeEditInbox.Create(
      procedure(const AText: string)
      begin
        GuardWarning(AText);
      end);
  // Eigene Blocklinien: Strukturhervorhebung der IDE abgleichen (#514).
  TAtlasIdeStructureSwitch.Sync;
  if (Reloader = nil) and Full then
    CreateReloader;
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
  TAtlasTimeLimit.LimitMs := TAtlasIdeSettings.Current.ProviderTimeLimitMs;
  TAtlasGuard.OnWarning := GuardWarning;
  TAtlasStrings.Language := IdeLanguage;
  // Versionsverwaltung (#571): Aufrufe im Hintergrund; fehlt git bzw. svn, einmal eine Zeile.
  TAtlasIdeVcs.Start(MessageLine);
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
  TAtlasOptionsRegistration.Register(
    procedure
    begin
      TAtlasIdeHistory.Reset;
    end,
    function(ACommand: string): TJSONValue
    begin
      // Kennzahlen, „Index neu aufbauen“ und „Index löschen“ der Einstellungsseite (#492).
      if Manager <> nil then
        Result := Manager.ExecuteServerCommand(ACommand)
      else
        Result := nil;
    end);
  // Ladezeit bis zur freien Nachrichtenschleife: zu lange zählt beim nächsten Start wie ein Absturz (#722).
  TThread.ForceQueue(nil,
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
  Services: IOTACodeInsightServices;
  StartedAt: UInt64;
  Stopped: Boolean;
begin
  // Zuerst das gemeinsame Abbruchsignal: Jeder Hintergrund-Thread hört auf zu warten (#493).
  StartedAt := TThread.GetTickCount64;
  TAtlasShutdown.Signal;
  TAtlasIdeVcs.Stop;
  TAtlasGuard.OnWarning := nil;
  TAtlasGuard.OnFailure := nil;
  TAtlasIdeSettings.OnChanged := nil;
  if KeysWatched then
    TAtlasIdeKeys.UnwatchPackages;
  KeysWatched := False;
  // Sauberes Ende: Startmarke löschen, Absturzzähler zurück (#722).
  if SafeMode <> nil then
    SafeMode.Stop;
  FreeAndNil(SafeMode);
  // Vor dem Statusfeld: Der Diagnosemodus hat eine Zeile in dessen Registry (#479).
  FreeAndNil(DiagnosticMode);
  // Vor dem Statusfeld: Die Einrichtung hat eine Zeile in dessen Registry und liest StatusLines (#625).
  FreeAndNil(Setup);
  // Vor der Übersicht: Der Link „Alle Kürzel“ öffnet sie (#600); speichert die Zählung.
  FreeAndNil(ShortcutTips);
  FreeAndNil(KeyMap);
  // Vor dem Statusfeld: Die Update-Prüfung hat die Zeile „Version“ in dessen Registry (#754).
  FreeAndNil(Updates);
  FreeAndNil(QuickToggles);
  FreeAndNil(SignatureKey);
  FreeAndNil(CompletionKey);
  FreeAndNil(EditInbox);
  FreeAndNil(DirtyExport);
  // Vor dem Statusfeld: Die Willkommensseite beobachtet dessen Registry.
  FreeAndNil(Welcome);
  // Nach den Tastenkürzel-Tipps und der Willkommensseite, die sie nutzen; speichert die Zählung (#757).
  FreeAndNil(CommandUsage);
  TAtlasWelcomeViews.Release;
  TAtlasWelcomeSections.ReleaseDefault;
  UnregisterStatusField;
  FreeAndNil(MainMenu);
  FreeAndNil(Forms);
  FreeAndNil(EditorKeys);
  TAtlasIdeUndo.Stop;
  if CommandsInstalled then
  begin
    TAtlasIdeUnitSearch.Uninstall;
    TAtlasIdeEditorCommands.Uninstall;
    TAtlasIdeResults.Uninstall;
  end;
  CommandsInstalled := False;
  FreeAndNil(Pairs);
  // Vor dem Notiz- und dem Lesezeichendienst: Die Rinne liest deren Listen (#545, #622).
  FreeAndNil(GutterMarks);
  TAtlasIdeNotes.Release;
  TAtlasIdeBookmarks.Release;
  FreeAndNil(CheckOnSave);
  FreeAndNil(Palette);
  FreeAndNil(Reloader);
  UnregisterWatchdog;
  FreeAndNil(Compile);
  TAtlasOptionsRegistration.Unregister;
  TAtlasProjectSettings.Command := nil;
  TAtlasIdeHistory.Release;
  TAtlasIdeFavorites.Release;
  TAtlasIdeSymbol.Unregister;
  TAtlasIdeSettings.Release;
  if (ManagerIndex >= 0) and Supports(BorlandIDEServices, IOTACodeInsightServices, Services) then
    Services.RemoveCodeInsightManager(ManagerIndex);
  ManagerIndex := -1;
  Manager := nil;
  Stopped := TAtlasTimeLimit.StopAll(TAtlasShutdown.StopMs);
  TAtlasGuard.Log(Format('Atlas entladen in %d ms; Hintergrund-Threads beendet: %s',
    [TThread.GetTickCount64 - StartedAt, BoolToStr(Stopped, True)]));
end;

initialization

finalization
  Unregister;

end.
