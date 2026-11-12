unit Atlas.IDE.CodeInsight.Composition.Tools;

// Werkzeuge mit eigenem Fenster oder Menü: Hauptmenü Atlas (#227), Einrichtung mit Prüfliste (#625),
// Diagnosemodus (#479), Tastenkürzel-Übersicht (#520), gemeinsame Zählung je Befehl (#600, #757),
// Tastenkürzel-Tipps (#600), Update-Prüfung (#495), Änderungsprotokoll über mehrere Dateien (#721) und
// „Symbol umbenennen…“ (#397); Untermenü Atlas in der Projektverwaltung (#1817).

interface

uses
  Atlas.IDE.Commands.MainMenu,
  Atlas.IDE.Setup.Checklist,
  Atlas.IDE.Diagnostics.Timing,
  Atlas.IDE.Commands.KeyMap,
  Atlas.IDE.Commands.Usage,
  Atlas.IDE.Commands.ShortcutTips,
  Atlas.IDE.Updates.Check;

/// <summary>Hauptmenü Atlas mit Schnellschaltern und Einstellungen; nil ohne.</summary>
function MainMenu: TAtlasMainMenu;
/// <summary>Einrichtung mit Prüfliste und Statuszeile; nil ohne.</summary>
function Setup: TAtlasIdeSetupChecklist;
/// <summary>Diagnosemodus mit Fenster, Taste und Statuszeile; nil ohne.</summary>
function DiagnosticMode: TAtlasIdeDiagnosticMode;
/// <summary>Tastenkürzel-Übersicht mit Prüfung beim Start; nil ohne.</summary>
function KeyMap: TAtlasIdeKeyMap;
/// <summary>Gemeinsame Zählung je Befehl und Tippquelle; auch abgesichert (liest und schreibt nur lokale Dateien).
/// </summary>
function CommandUsage: TAtlasIdeCommandUsage;
/// <summary>Tastenkürzel-Tipps, zählen in CommandUsage; nur im normalen Start.</summary>
function ShortcutTips: TAtlasIdeShortcutTips;
/// <summary>Rückfrage und tägliche Update-Prüfung; nil ohne.</summary>
function Updates: TAtlasIdeUpdates;
/// <summary>„Symbol umbenennen…“ (#397) aus Menü und Palette.</summary>
procedure RenameSymbol;
procedure StartMainMenu;
procedure StopMainMenu;
function MainMenuStarted: Boolean;
/// <summary>Untermenü Atlas im Kontextmenü der Projektverwaltung (#1817); „Mit Atlas prüfen“ geht an das Fenster
/// „Atlas-Prüfung“.</summary>
procedure StartProjectMenu;
procedure StopProjectMenu;
function ProjectMenuStarted: Boolean;
/// <summary>Einrichtung mit Prüfliste (#625); Zustand des Servers über den Manager und das Statusfeld.</summary>
procedure StartSetup;
procedure StopSetup;
function SetupStarted: Boolean;
procedure StartDiagnosticMode;
procedure StopDiagnosticMode;
function DiagnosticModeStarted: Boolean;
procedure StartKeyMap;
procedure StopKeyMap;
function KeyMapStarted: Boolean;
procedure StartCommandUsage;
procedure StopCommandUsage;
function CommandUsageStarted: Boolean;
procedure StartShortcutTips;
procedure StopShortcutTips;
function ShortcutTipsStarted: Boolean;
/// <summary>Tipps zählen auch für „Atlas entdecken“ (#757), solange die Karte und die Zählung an sind.</summary>
procedure ApplyShortcutTipsCounting;
procedure StartUpdates;
procedure StopUpdates;
function UpdatesStarted: Boolean;
/// <summary>Änderungsprotokoll (#721) mit Ziel und Sicherung aus dem Kern.</summary>
procedure StartUndo;
function UndoStarted: Boolean;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Updates.Check,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions,
  Atlas.Core.Commands.Usage,
  Atlas.Core.Status.Registry,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Editor.Rename,
  Atlas.IDE.Undo.Changes,
  Atlas.IDE.Commands.ProjectMenu,
  Atlas.IDE.Problems.Service,
  Atlas.IDE.CodeInsight.Composition.Adapters,
  Atlas.IDE.CodeInsight.Composition.Session,
  Atlas.IDE.CodeInsight.Composition.Status;

const
  /// <summary>Zeitlimit eines Serverbefehls aus dem Menü ohne Antwortverarbeitung.</summary>
  cServerCommandTimeoutMs = 30000;

var
  MainMenuInstance: TAtlasMainMenu;
  SetupInstance: TAtlasIdeSetupChecklist;
  DiagnosticModeInstance: TAtlasIdeDiagnosticMode;
  KeyMapInstance: TAtlasIdeKeyMap;
  CommandUsageInstance: TAtlasIdeCommandUsage;
  ShortcutTipsInstance: TAtlasIdeShortcutTips;
  UpdatesInstance: TAtlasIdeUpdates;

function MainMenu: TAtlasMainMenu;
begin
  Result := MainMenuInstance;
end;

function Setup: TAtlasIdeSetupChecklist;
begin
  Result := SetupInstance;
end;

function DiagnosticMode: TAtlasIdeDiagnosticMode;
begin
  Result := DiagnosticModeInstance;
end;

function KeyMap: TAtlasIdeKeyMap;
begin
  Result := KeyMapInstance;
end;

function CommandUsage: TAtlasIdeCommandUsage;
begin
  Result := CommandUsageInstance;
end;

function ShortcutTips: TAtlasIdeShortcutTips;
begin
  Result := ShortcutTipsInstance;
end;

function Updates: TAtlasIdeUpdates;
begin
  Result := UpdatesInstance;
end;

procedure RenameSymbol;
begin
  if Manager = nil then
  begin
    Exit;
  end;
  TAtlasIdeRename.Execute(Manager.ActiveSession,
    TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits), Warnings());
end;

/// <summary>Fortschritt im Menütitel nur, wenn er nicht ins Statusfeld gehört (IndexProgressPlace).</summary>
function MenuProgress: string;
begin
  Result := '';
  if (Manager <> nil) and TAtlasIdeSettings.Current.IndexProgressInMenu then
  begin
    Result := Manager.ServerProgress;
  end;
end;

procedure StartMainMenu;
begin
  MainMenuInstance := TAtlasMainMenu.Create(MenuProgress,
    procedure(ACommand: string; ADone: TProc<TJSONValue>)
    begin
      ExecuteServerCommand(ACommand, ADone);
    end,
    Warnings());
  MainMenuInstance.OnBugReport := CreateBugReport;
  MainMenuInstance.OnServerStatus := ShowServerWindow;
  MainMenuInstance.OnRename := RenameSymbol;
  MainMenuInstance.OnSetup :=
    procedure
    begin
      if SetupInstance <> nil then
      begin
        SetupInstance.ShowWindow;
      end;
    end;
  MainMenuInstance.OnKeyMap :=
    procedure
    begin
      if KeyMapInstance <> nil then
      begin
        KeyMapInstance.ShowWindow;
      end;
    end;
end;

procedure StopMainMenu;
begin
  FreeAndNil(MainMenuInstance);
end;

function MainMenuStarted: Boolean;
begin
  Result := MainMenuInstance <> nil;
end;

procedure CheckProjectFiles(AFiles: TArray<string>);
begin
  TAtlasGuard.Run(TAtlasFeature.Problems,
    procedure
    begin
      TAtlasIdeProblems.CheckFiles(AFiles);
    end);
end;

function ProjectCheckVisible: Boolean;
begin
  Result := TAtlasIdeProblems.Enabled and not TAtlasGuard.Disabled(TAtlasFeature.Problems);
end;

procedure StartProjectMenu;
begin
  TAtlasIdeProjectMenu.Install(CheckProjectFiles, ProjectCheckVisible);
end;

procedure StopProjectMenu;
begin
  TAtlasIdeProjectMenu.Uninstall;
end;

function ProjectMenuStarted: Boolean;
begin
  Result := TAtlasIdeProjectMenu.Installed;
end;

/// <summary>Server starten bzw. neu starten aus der Prüfliste; False ohne Manager.</summary>
function StartServer(ARestart: Boolean): Boolean;
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
    // Von Hand: auch nach zwei gleichen Abstürzen. Die aktive Sitzung startet den Server,
    // wenn er noch nicht läuft.
    Manager.AllowStart;
    Result := Manager.ActiveSession <> nil;
  end;
end;

/// <summary>Befehl nur abschicken (#874): Den Fortschritt zeigt die Prüfliste über Indexing.</summary>
function SendServerCommand(ACommand: string): Boolean;
begin
  Result := (Manager <> nil) and (Manager.ActiveSession <> nil);
  if Result then
  begin
    Manager.ExecuteServerCommandAsync(ACommand, cServerCommandTimeoutMs, nil);
  end;
end;

procedure StartSetup;
var
  mHooks: TAtlasSetupHooks;
begin
  mHooks.ServerInfo := ServerInfo;
  mHooks.Indexing := ServerIndexing;
  mHooks.IndexingOf := ServerIndexingOf;
  mHooks.StatusJson := StatusJson;
  mHooks.StartServer := StartServer;
  mHooks.ServerCommand := SendServerCommand;
  mHooks.ServerPath := ServerPath;
  SetupInstance := TAtlasIdeSetupChecklist.Create(TAtlasStatusRegistry.Default, mHooks);
end;

procedure StopSetup;
begin
  FreeAndNil(SetupInstance);
end;

function SetupStarted: Boolean;
begin
  Result := SetupInstance <> nil;
end;

procedure StartDiagnosticMode;
begin
  DiagnosticModeInstance := TAtlasIdeDiagnosticMode.Create(TAtlasStatusRegistry.Default);
end;

procedure StopDiagnosticMode;
begin
  FreeAndNil(DiagnosticModeInstance);
end;

function DiagnosticModeStarted: Boolean;
begin
  Result := DiagnosticModeInstance <> nil;
end;

procedure StartKeyMap;
begin
  KeyMapInstance := TAtlasIdeKeyMap.Create;
end;

procedure StopKeyMap;
begin
  FreeAndNil(KeyMapInstance);
end;

function KeyMapStarted: Boolean;
begin
  Result := KeyMapInstance <> nil;
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

procedure StartCommandUsage;
begin
  CommandUsageInstance := TAtlasIdeCommandUsage.Create;
  // Nach „Zählung zurücksetzen“: „Noch nie benutzt“ auf der Karte eines Moduls sofort.
  CommandUsageInstance.OnReset := UsageResetInModules;
end;

procedure StopCommandUsage;
begin
  FreeAndNil(CommandUsageInstance);
end;

function CommandUsageStarted: Boolean;
begin
  Result := CommandUsageInstance <> nil;
end;

procedure ApplyShortcutTipsCounting;
begin
  if ShortcutTipsInstance <> nil then
  begin
    ShortcutTipsInstance.CountAlways := TAtlasIdeSettings.Current.WelcomePage and
      TAtlasIdeSettings.Current.WelcomePageDiscover and TAtlasIdeSettings.Current.TipsUsageTracking;
  end;
end;

procedure StartShortcutTips;
begin
  ShortcutTipsInstance := TAtlasIdeShortcutTips.Create(CommandUsageInstance);
  ApplyShortcutTipsCounting;
end;

procedure StopShortcutTips;
begin
  FreeAndNil(ShortcutTipsInstance);
end;

function ShortcutTipsStarted: Boolean;
begin
  Result := ShortcutTipsInstance <> nil;
end;

procedure StartUpdates;
begin
  UpdatesInstance := TAtlasIdeUpdates.Create(nil);
  UpdatesInstance.Start(TAtlasUpdates.StateFile, UpdateSource, MessageLines(), GuardLogs());
  // Zeile „Version“ im Statusfeld und in der Zustandskachel (#754).
  UpdatesInstance.ShowStatus(TAtlasStatusRegistry.Default);
end;

procedure StopUpdates;
begin
  FreeAndNil(UpdatesInstance);
end;

function UpdatesStarted: Boolean;
begin
  Result := UpdatesInstance <> nil;
end;

procedure StartUndo;
begin
  // Adapter des Kerns setzt nur die Kompositionswurzel ein.
  InstallUndoAdapters;
  TAtlasIdeUndo.Start(Warnings(), GuardLogs());
end;

function UndoStarted: Boolean;
begin
  Result := TAtlasIdeUndo.Journal <> nil;
end;

end.
