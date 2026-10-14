unit Atlas.IDE.CodeInsight.Composition;

// Meldet den Code Insight-Manager, die Optionsseite "Atlas" (#227), die
// Compile-Ereignisse (#527), den Einfrier-Wächter (#501), das Neuladen
// extern geänderter Dateien (#536), die Befehlspalette (#502), die farbigen
// Klammerpaare (#514), das Atlas-Statusfeld (#591) und die Schnellschalter
// (#604) beim Laden des
// Packages an und beim Entladen in umgekehrter Reihenfolge wieder ab (ADR 0006).

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
  Atlas.IDE.Build.CheckOnSave,
  Atlas.IDE.Settings.Project,
  Atlas.IDE.Commands.MainMenu,
  Atlas.Core.Status.Registry,
  Atlas.Core.Status.Lines,
  Atlas.IDE.Status.Field,
  Atlas.IDE.Status.Lines,
  Atlas.IDE.Settings.QuickToggles,
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
  CheckOnSave: TAtlasIdeCheckOnSave;
  // Hauptmenü Atlas mit Schnellschaltern und Einstellungen (#227).
  MainMenu: TAtlasMainMenu;
  // Atlas-Statusfeld mit Server, Index und Datei (#591).
  StatusField: TAtlasStatusField;
  StatusLines: TAtlasIdeStatusLines;
  // Eigene Tasten für Vervollständigung und Parameter-Hint (#494); ohne Einstellung keine.
  CompletionKey: TAtlasIdeKeyBinding;
  SignatureKey: TAtlasIdeKeyBinding;
  // Schnellschalter mit Fenster, Taste und Befehlen in der Palette (#604).
  QuickToggles: TAtlasIdeQuickToggles;

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
  // Phase und Fortschritt des Servers melden sich aus jedem Thread; gezeichnet wird gesammelt.
  if Manager <> nil then
    Manager.OnServerChanged :=
      procedure
      begin
        if StatusField <> nil then
          StatusField.RequestRefresh;
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

procedure Register;
var
  Services: IOTACodeInsightServices;
  LoadedAt: Int64;
begin
  LoadedAt := TAtlasWatchdog.Timestamp;
  // Abbruchsignal eines früheren Entladens in derselben Sitzung zurücknehmen (#493).
  TAtlasShutdown.Reset;
  TAtlasTimeLimit.LimitMs := TAtlasIdeSettings.Current.ProviderTimeLimitMs;
  TAtlasGuard.OnWarning := GuardWarning;
  TAtlasStrings.Language := IdeLanguage;
  if (ManagerIndex < 0) and Supports(BorlandIDEServices, IOTACodeInsightServices, Services) then
  begin
    Manager := TAtlasCodeInsightManager.Create;
    ManagerIndex := Services.AddCodeInsightManager(Manager);
  end;
  if Compile = nil then
    RegisterCompileEvents;
  if Watchdog = nil then
    RegisterWatchdog(LoadedAt);
  if (CheckOnSave = nil) and (Compile <> nil) then
    CheckOnSave := TAtlasIdeCheckOnSave.Create(Compile.Events,
      procedure(AText: string)
      begin
        if Manager <> nil then
          Manager.Report(AText);
      end);
  if Palette = nil then
    RegisterPalette;
  if Pairs = nil then
    Pairs := TAtlasEditorPairs.Create;
  if CompletionKey = nil then
    CompletionKey := TAtlasIdeKeyBinding.Create('Atlas.Completion', 'Atlas-Vervollständigung',
      TAtlasFeature.Completion,
      procedure
      begin
        if Manager <> nil then
          Manager.OpenCompletion;
      end);
  if SignatureKey = nil then
    SignatureKey := TAtlasIdeKeyBinding.Create('Atlas.Signature', 'Atlas-Parameter-Hint',
      TAtlasFeature.Signature,
      procedure
      begin
        if Manager <> nil then
          Manager.OpenSignature;
      end);
  if QuickToggles = nil then
  begin
    QuickToggles := TAtlasIdeQuickToggles.Create(nil);
    QuickToggles.OnAnchor :=
      function: TPoint
      begin
        if (StatusField = nil) or not StatusField.Anchor(Result) then
          Result := Point(MaxInt, MaxInt);
      end;
    if Palette <> nil then
      QuickToggles.RegisterCommands(Palette);
  end;
  RebindKeys;
  // Geänderte Tastenkürzel sofort neu belegen; fremde Vervollständigung melden (#494).
  TAtlasIdeSettings.OnChanged :=
    procedure
    begin
      RebindKeys;
      TAtlasTimeLimit.LimitMs := TAtlasIdeSettings.Current.ProviderTimeLimitMs;
      // Index-Optionen an den laufenden Server; er baut neu auf, wenn sich der Umfang ändert (#652).
      if Manager <> nil then
        Manager.NotifyServer('workspace/didChangeConfiguration',
          TLspSession.SettingsParams(TAtlasIdeSettings.Current.ServerSettingsJson));
      // Statusfeld an, aus, Kurztext oder ausgeblendete Zeilen geändert (#591).
      if StatusField <> nil then
        StatusField.RequestRefresh;
    end;
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
  if MainMenu = nil then
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
  if StatusField = nil then
    RegisterStatusField;
  if DirtyExport = nil then
    DirtyExport := TAtlasDirtyExport.Create;
  // Eigene Blocklinien: Strukturhervorhebung der IDE abgleichen (#514).
  TAtlasIdeStructureSwitch.Sync;
  if Reloader = nil then
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
  TAtlasIdeSettings.OnChanged := nil;
  TAtlasIdeKeys.UnwatchPackages;
  FreeAndNil(QuickToggles);
  FreeAndNil(SignatureKey);
  FreeAndNil(CompletionKey);
  FreeAndNil(DirtyExport);
  UnregisterStatusField;
  FreeAndNil(MainMenu);
  FreeAndNil(Pairs);
  FreeAndNil(CheckOnSave);
  FreeAndNil(Palette);
  FreeAndNil(Reloader);
  UnregisterWatchdog;
  FreeAndNil(Compile);
  TAtlasOptionsRegistration.Unregister;
  TAtlasIdeHistory.Release;
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
