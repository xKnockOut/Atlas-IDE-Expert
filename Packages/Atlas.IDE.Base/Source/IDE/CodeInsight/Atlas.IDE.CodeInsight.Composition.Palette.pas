unit Atlas.IDE.CodeInsight.Composition.Palette;

// Befehlspalette (#502) mit allen Atlas-Befehlen in Startreihenfolge, ihren Tasten (#520) und der Zusatzquelle
// der Module (#1270, #1455). Hier stehen die Befehle für Erzeugen (#719), Einstellungen (#723), Projekt (#66,
// #486), Diagnose (#108, #1356) und Versionsverwaltung (#1288, #1292); die übrigen melden die Units
// PaletteNavigation und PaletteEditing an.

interface

uses
  Atlas.Core.Commands.Palette,
  Atlas.IDE.Commands.Palette;

/// <summary>Befehlspalette; nil ohne.</summary>
function Palette: TAtlasIdePalette;
/// <summary>Atlas-Befehle der Palette; leer ohne Palette.</summary>
function PaletteCommands: TArray<TAtlasCommand>;
/// <summary>Befehl AId der Palette ausführen; ohne Palette nichts.</summary>
procedure ExecutePaletteCommand(const AId: string);
/// <summary>Palette zeigen; ohne Palette nichts.</summary>
procedure ShowPalette;
/// <summary>Palette anlegen, alle Befehle anmelden und die Tasten zeigen.</summary>
procedure StartPalette;
procedure StopPalette;
function PaletteStarted: Boolean;

implementation

uses
  Atlas.IDE.Problems.Service,
  System.SysUtils,
  Atlas.UI.Strings,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions,
  Atlas.IDE.Settings.PaletteSearch,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.Hangs,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.IDE.Generate.Commands,
  Atlas.IDE.Settings.Transfer,
  Atlas.IDE.Settings.Project,
  Atlas.IDE.Completion.History,
  Atlas.IDE.Notifications.Service,
  Atlas.IDE.Diagnostics.Export,
  Atlas.IDE.Status.ServerWindow,
  Atlas.IDE.Commands.KeyMap,
  Atlas.IDE.CodeInsight.Composition.Session,
  Atlas.IDE.CodeInsight.Composition.Status,
  Atlas.IDE.CodeInsight.Composition.Build,
  Atlas.IDE.CodeInsight.Composition.Tools,
  Atlas.IDE.CodeInsight.Composition.PaletteNavigation,
  Atlas.IDE.CodeInsight.Composition.PaletteEditing;

var
  PaletteInstance: TAtlasIdePalette;

function Palette: TAtlasIdePalette;
begin
  Result := PaletteInstance;
end;

function PaletteCommands: TArray<TAtlasCommand>;
begin
  Result := nil;
  if PaletteInstance <> nil then
  begin
    Result := PaletteInstance.AtlasCommands;
  end;
end;

procedure ExecutePaletteCommand(const AId: string);
begin
  if PaletteInstance <> nil then
  begin
    PaletteInstance.Execute(AId);
  end;
end;

procedure ShowPalette;
begin
  if PaletteInstance <> nil then
  begin
    PaletteInstance.Show;
  end;
end;

/// <summary>„Datei jetzt prüfen“ (problems.update): sichtbar, solange Atlas die offene Datei prüft.</summary>
function CheckFileVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Enabled and TAtlasIdeSettings.Current.Problems;
end;

function GenerateMenuVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.GenerateMenu;
end;

/// <summary>Export, Import und Zurücksetzen der Einstellungen (#723): settings.exportImport.</summary>
function SettingsTransferVisible: Boolean;
begin
  Result := TAtlasIdeSettingsTransfer.Visible;
end;

function MetricsReportVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.MetricsReport;
end;

function TeamFileVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TeamFile;
end;

function NotificationsVisible: Boolean;
begin
  Result := TAtlasIdeNotifications.Active;
end;

function DiagnosticModeVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DiagnosticMode;
end;

function ServerWindowVisible: Boolean;
begin
  Result := TAtlasIdeServerWindow.Enabled;
end;

procedure ShowGenerateMenu;
begin
  TAtlasGuard.Run(TAtlasFeature.Generate,
    procedure
    begin
      TAtlasIdeGenerate.Show;
    end);
end;

procedure CheckNow;
begin
  if CheckOnSave <> nil then
  begin
    CheckOnSave.CheckNow;
  end;
end;

procedure ExportDiagnostics;
begin
  TAtlasIdeDiagnosticExport.Execute(Warnings());
end;

/// <summary>Künstlicher Hänger für den Einfrier-Wächter (#501): nur im Diagnosemodus (#479, Code-Review S-07),
/// auch über Verlauf oder Taste nicht außerhalb.</summary>
procedure HangTest;
begin
  if not TAtlasIdeSettings.Current.DiagnosticMode then
  begin
    Exit;
  end;
  TAtlasActivity.HangTest;
end;

/// <summary>Erzeugen-Menü (#719) und Einstellungen exportieren, importieren und zurücksetzen (#723).</summary>
procedure AddSettingsCommands(APalette: TAtlasIdePalette);
begin
  AddCommand(APalette, 'Atlas.GenerateMenu', TAtlasTextId.GenerateMenuCommand, ShowGenerateMenu,
    GenerateMenuVisible);
  // Offene Datei jetzt prüfen, auch ungespeichert und ohne Live-Prüfung (problems.update).
  AddCommand(APalette, 'Atlas.CheckFile', TAtlasTextId.ProblemsCheckFileCommand,
    Guarded(TAtlasFeature.Problems, TAtlasIdeProblems.CheckFileNow), CheckFileVisible);
  AddCommand(APalette, 'Atlas.SettingsExport', TAtlasTextId.SettingsExportCommand,
    Guarded(TAtlasFeature.Settings, TAtlasIdeSettingsTransfer.ExportCommand), SettingsTransferVisible);
  AddCommand(APalette, 'Atlas.SettingsImport', TAtlasTextId.SettingsImportCommand,
    Guarded(TAtlasFeature.Settings, TAtlasIdeSettingsTransfer.ImportCommand), SettingsTransferVisible);
  AddCommand(APalette, 'Atlas.SettingsProfile', TAtlasTextId.SettingsProfileCommand,
    Guarded(TAtlasFeature.Settings, TAtlasIdeSettingsTransfer.ProfileCommand), SettingsTransferVisible);
  AddCommand(APalette, 'Atlas.SettingsReset', TAtlasTextId.SettingsResetCommand,
    Guarded(TAtlasFeature.Settings, TAtlasIdeSettingsTransfer.ResetCommand), SettingsTransferVisible);
end;

/// <summary>Verlauf, Projekt, Benachrichtigungen, Diagnose und Wächter-Test.</summary>
procedure AddProjectCommands(APalette: TAtlasIdePalette);
begin
  AddCommand(APalette, 'Atlas.ResetHistory', TAtlasTextId.PaletteResetHistory, TAtlasIdeHistory.Reset);
  // Metrikbericht des Projekts (#66); nur sichtbar, solange die Einstellung MetricsReport an ist.
  AddCommand(APalette, 'Atlas.MetricsReport', TAtlasTextId.MetricsReportCommand, MetricsReport, MetricsReportVisible);
  // Projektdatei .atlas (#486) anlegen bzw. öffnen; nur sichtbar, solange die Einstellung TeamFile an ist.
  AddCommand(APalette, 'Atlas.TeamFile', TAtlasTextId.TeamFileCommand, TAtlasIdeTeamFile.OpenInEditor,
    TeamFileVisible);
  // Liste der Benachrichtigungen (#601); nur sichtbar, solange die Zentrale an ist.
  AddCommand(APalette, 'Atlas.Notifications', TAtlasTextId.NotificationsCommand,
    Guarded(TAtlasFeature.Notifications, TAtlasIdeNotifications.ShowList), NotificationsVisible);
  // „Release-Build prüfen“ (#533) stellt das Modul Build-Pipeline bereit.
  AddCommand(APalette, 'Atlas.CheckNow', TAtlasTextId.PaletteCheckNow, CheckNow);
  AddCommand(APalette, 'Atlas.ExportDiagnostics', TAtlasTextId.DiagExportMenu, ExportDiagnostics);
  AddCommand(APalette, 'Atlas.BugReport', TAtlasTextId.BugReportMenu, CreateBugReport);
  // Fenster „Atlas-Server“ (#1356); nur sichtbar mit server.statusWindow.
  AddCommand(APalette, 'Atlas.ServerStatus', TAtlasTextId.ServerWindowCommand, ShowServerWindow,
    ServerWindowVisible);
  AddCommand(APalette, 'Atlas.ProjectSettings', TAtlasTextId.ProjectSettingsTitle, TAtlasProjectSettings.Execute);
  // „Branch anlegen …“ und „Arbeitskopien“ stellt das Modul Versionsverwaltung bereit (#1905).
  AddCommand(APalette, 'Atlas.HangTest', TAtlasTextId.SettingsHangTest, HangTest, DiagnosticModeVisible);
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

/// <summary>Alle Befehle von Base in der Reihenfolge, in der die Palette sie bei Gleichstand zeigt.</summary>
procedure RegisterPalette;
begin
  PaletteInstance := TAtlasIdePalette.Create;
  AddNavigationCommands(PaletteInstance);
  AddEditingCommands(PaletteInstance);
  AddHierarchyCommands(PaletteInstance);
  AddSettingsCommands(PaletteInstance);
  // Editorbefehle (#399).
  AddEditorCommands(PaletteInstance);
  AddProjectCommands(PaletteInstance);
end;

/// <summary>Befehle der Teile mit eigenem Fenster: Schnellschalter, Diagnosemodus, Einrichtung, Tasten.</summary>
procedure RegisterPartCommands;
begin
  if QuickToggles <> nil then
  begin
    QuickToggles.RegisterCommands(PaletteInstance);
  end;
  if DiagnosticMode <> nil then
  begin
    DiagnosticMode.RegisterCommands(PaletteInstance);
  end;
  if Setup <> nil then
  begin
    Setup.RegisterCommands(PaletteInstance);
  end;
  if KeyMap <> nil then
  begin
    KeyMap.RegisterCommands(PaletteInstance);
  end;
end;

procedure StartPalette;
begin
  RegisterPalette;
  // Atlas-Befehle zeigen ihre Taste (#520).
  PaletteInstance.ShortCutsOf :=
    function: TFunc<string, string>
    begin
      Result := TAtlasIdeKeyMap.AtlasShortCuts();
    end;
  RegisterPartCommands;
  // Zusatzquelle der Palette (#1270), etwa Issues aus „Meine Issues“: erst beim Öffnen gefragt, von einem
  // laufenden Modul (#1455).
  // Mit „@“ (#1884) zeigt die Palette Einstellungen statt der Quelle der Module.
  PaletteInstance.SourceOf :=
    function: IAtlasPaletteSource
    begin
      Result := TAtlasIdeSettingsPalette.Sources(PaletteSourceOfModules);
    end;
end;

procedure StopPalette;
begin
  FreeAndNil(PaletteInstance);
end;

function PaletteStarted: Boolean;
begin
  Result := PaletteInstance <> nil;
end;

end.
