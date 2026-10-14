unit Atlas.IDE.CodeInsight.Composition;

// Meldet den Code Insight-Manager, die Optionsseite "Atlas" (#227), die
// Compile-Ereignisse (#527), den Einfrier-Wächter (#501), das Neuladen
// extern geänderter Dateien (#536), die Befehlspalette (#502), die farbigen
// Klammerpaare (#514), das Ergebnisfenster (#400), die Editorbefehle samt
// Tastenkürzeln und Kontextmenü (#399), den Abgleich offener Formulare (#402),
// das Atlas-Statusfeld (#591) und die Schnellschalter (#604) beim Laden des
// Packages an und beim Entladen in umgekehrter Reihenfolge wieder ab
// (ADR 0006). Zuerst entscheidet der abgesicherte Start
// (#722), was angemeldet wird; RegisterFeatures holt den Rest nach, sobald
// ein Schnellschalter oder „Normal weiterarbeiten“ es erlaubt.

interface

procedure Register;

implementation

uses
  Winapi.Windows,
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
  Atlas.IDE.Build.Notifier,
  Atlas.IDE.Build.MessageView,
  Atlas.Core.Diagnostics.Hangs,
  Atlas.IDE.Settings.Store,
  Atlas.IDE.Diagnostics.Watchdog,
  Atlas.IDE.Diagnostics.Export,
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
  Atlas.IDE.Commands.Keys;

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
  // Abgesicherter Start nach einem Absturz (#722).
  SafeMode: TAtlasIdeSafeMode;
  // Zeitpunkt des Ladens (TAtlasWatchdog.Timestamp) für Wächter und Ladezeit.
  LoadedAt: Int64;
  // Laden abgeschlossen: Später angemeldete Teile messen ab dann.
  StartupDone: Boolean;
  // Paketbeobachtung und Meldung fremder Vervollständigung angemeldet (#494).
  KeysWatched: Boolean;

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

/// <summary>„Symbol umbenennen…“ (#397) aus Menü und Palette.</summary>
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
  Palette.RegisterCommand('Atlas.ProjectSettings', TAtlasStrings.Text(TAtlasTextId.ProjectSettingsTitle), '',
    procedure
    begin
      TAtlasProjectSettings.Execute;
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
      ASucceeded: Boolean; const AInfo: string)
    var
      Messages: TArray<TAtlasCompilerMessage>;
    begin
      if Manager = nil then
        Exit;
      Messages := TAtlasCompilerMessages.Resolve(AMessages, AProject.FileName, KnownFiles(AProject.FileName));
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
      if Manager <> nil then
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
  if Basic and (Palette = nil) then
  begin
    RegisterPalette;
    if QuickToggles <> nil then
      QuickToggles.RegisterCommands(Palette);
  end;
  // Editor-Zeichnungen.
  if (Pairs = nil) and (Full or Settings.PairColors or Settings.PairGuides or Settings.InactiveDim) then
    Pairs := TAtlasEditorPairs.Create;
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
      end);
  end;
  if Basic and (MainMenu = nil) then
  begin
    CreateMainMenu;
    MainMenu.OnRename := RenameSymbol;
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
      TAtlasTimeLimit.LimitMs := TAtlasIdeSettings.Current.ProviderTimeLimitMs;
      // Index-Optionen an den laufenden Server; er baut neu auf, wenn sich der Umfang ändert (#652).
      if Manager <> nil then
        Manager.NotifyServer('workspace/didChangeConfiguration',
          TLspSession.SettingsParams(TAtlasIdeSettings.Current.ServerSettingsJson));
      // Statusfeld an, aus, Kurztext oder ausgeblendete Zeilen geändert (#591).
      if StatusField <> nil then
        StatusField.RequestRefresh;
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
  FreeAndNil(QuickToggles);
  FreeAndNil(SignatureKey);
  FreeAndNil(CompletionKey);
  FreeAndNil(EditInbox);
  FreeAndNil(DirtyExport);
  UnregisterStatusField;
  FreeAndNil(MainMenu);
  FreeAndNil(Forms);
  FreeAndNil(EditorKeys);
  if CommandsInstalled then
  begin
    TAtlasIdeEditorCommands.Uninstall;
    TAtlasIdeResults.Uninstall;
  end;
  CommandsInstalled := False;
  FreeAndNil(Pairs);
  FreeAndNil(CheckOnSave);
  FreeAndNil(Palette);
  FreeAndNil(Reloader);
  UnregisterWatchdog;
  FreeAndNil(Compile);
  TAtlasOptionsRegistration.Unregister;
  TAtlasIdeHistory.Release;
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
