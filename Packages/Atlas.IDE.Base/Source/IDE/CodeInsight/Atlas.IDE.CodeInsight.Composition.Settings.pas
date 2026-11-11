unit Atlas.IDE.CodeInsight.Composition.Settings;

// Einstellungen und Thema: Optionsseiten (#227) mit ihren Haken (A-09), Prüfung und Regelkatalog des
// Einstellungsdialogs, geänderte Einstellungen an alle Teile und Module (#1455) und das Thema der IDE (#751).

interface

/// <summary>Optionsseiten, Befehle des Einstellungsdialogs und die Reaktion auf geänderte Einstellungen und
/// Themen anmelden.</summary>
procedure InstallSettings;
/// <summary>Reaktion auf geänderte Einstellungen lösen (vor dem Abbau der Teile).</summary>
procedure DetachSettings;
/// <summary>Optionsseiten abmelden.</summary>
procedure UnregisterOptions;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.TimeLimit,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Symbol,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.IDE.Settings.Options,
  Atlas.IDE.Settings.Project,
  Atlas.IDE.Settings.Experimental,
  Atlas.IDE.Completion.History,
  Atlas.IDE.Completion.Editor,
  Atlas.IDE.EditorToolbar.Service,
  Atlas.IDE.Generate.Gallery,
  Atlas.IDE.Undo.Changes,
  Atlas.IDE.CodeInsight.Manager.Paths,
  Atlas.IDE.CodeInsight.Composition.Session,
  Atlas.IDE.CodeInsight.Composition.Status,
  Atlas.IDE.CodeInsight.Composition.Tools,
  Atlas.IDE.CodeInsight.Composition.Features,
  Atlas.IDE.CodeInsight.Composition.Startup,
  Atlas.IDE.CodeInsight.Composition.Appearance;

/// <summary>Geänderte Einstellungen an die angemeldeten Module weitergeben (#1455), z. B. debug.* des Debuggers.
/// </summary>
procedure ModulesApplySettings;
var
  mFailure: string;
begin
  for mFailure in TAtlasModuleContributions.ApplySettings(AtlasModuleRegistry) do
  begin
    TAtlasGuard.Log('Einstellungen im Modul nicht übernommen: ' + mFailure);
  end;
end;

/// <summary>Teile mit eigenen Einstellungen außerhalb der Fenster: Änderungsprotokoll, Updates, Diagnosemodus,
/// Benachrichtigungen, Projektdatei, experimentelle Funktionen, Module, Zählung und Tipps.</summary>
procedure ApplyPartSettings;
begin
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
end;

/// <summary>Benachrichtigungen, Projektdatei, experimentelle Funktionen, Module, Zählung, Tipps und Zeitlimit.
/// </summary>
procedure ApplyServiceSettings;
begin
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
  // Assistenten der Objektgalerie (#1821): generate.galleryWizards und Modulschalter.
  TAtlasIdeGallery.Refresh;
  // tips.usageTracking (#757).
  if CommandUsage <> nil then
  begin
    CommandUsage.ApplySettings;
  end;
  // shortcutTips.* und neu belegte Tasten (#600); Zählung für „Atlas entdecken“ (#757).
  if ShortcutTips <> nil then
  begin
    ApplyShortcutTipsCounting;
    ShortcutTips.ApplySettings;
  end;
  TAtlasTimeLimit.LimitMs := TAtlasIdeSettings.Current.ProviderTimeLimitMs;
  // Klarnamen in atlas.log nur ausdrücklich (#1478, diagnostics.log.names).
  TAtlasGuard.SetLogNames(TAtlasIdeSettings.Current.LogNames);
end;

/// <summary>Geänderte Tastenkürzel sofort neu belegen, fremde Vervollständigung melden (#494); ein Schnellschalter
/// oder „Normal weiterarbeiten“ im abgesicherten Start meldet nach (#722).</summary>
procedure SettingsChanged;
begin
  RegisterFeatures;
  if SafeMode <> nil then
  begin
    SafeMode.UpdateFeatures;
  end;
  ApplyPartSettings;
  ApplyWindowSettings;
  ApplyServiceSettings;
  // Index-Optionen schreibt der Optionsdialog nach settings.json; der Server beobachtet die Datei (#652).
  // Statusfeld an, aus, Kurztext oder ausgeblendete Zeilen geändert (#591).
  RequestStatusRefresh;
end;

/// <summary>Optionsseiten (#227) mit ihren Haken (A-09): Die Seiten importieren die Features nicht, die sie
/// bedienen.</summary>
procedure RegisterOptions;
var
  mHooks: TAtlasOptionsHooks;
begin
  mHooks := Default(TAtlasOptionsHooks);
  mHooks.ResetHistory := TAtlasIdeHistory.Reset;
  // Kennzahlen, „Index neu aufbauen“ und „Index löschen“ der Einstellungsseite (#492), im Hintergrund (#874).
  mHooks.Command :=
    procedure(ACommand: string; ADone: TProc<TJSONValue>)
    begin
      ExecuteServerCommand(ACommand, ADone);
    end;
  mHooks.ToolbarCommands := TAtlasIdeEditorToolbar.CommandInfos;
  mHooks.ServerPath := ServerPath;
  mHooks.DefaultServerPath := TAtlasCodeInsightPaths.DefaultServerPath;
  mHooks.IdeTemplateFolder := TAtlasEditorCompletion.IdeTemplateFolder;
  mHooks.SnippetFolder := TAtlasEditorCompletion.SnippetFolder;
  TAtlasOptionsRegistration.Register(mHooks);
end;

/// <summary>Prüfung und Regelkatalog des Einstellungsdialogs (#227): nur ein laufender Server, keiner wird
/// gestartet.</summary>
function ProjectSettingsCommand(const ACommand, AArgumentsJson: string): TJSONValue;
begin
  Result := nil;
  if Manager <> nil then
  begin
    Result := Manager.RunServerCommand(ACommand, AArgumentsJson, 5000);
  end;
end;

procedure InstallSettings;
begin
  TAtlasIdeSymbol.OnThemeChanged := ThemeChanged;
  TAtlasIdeSettings.OnChanged := SettingsChanged;
  TAtlasProjectSettings.Command := ProjectSettingsCommand;
  RegisterOptions;
end;

procedure DetachSettings;
begin
  TAtlasIdeSettings.OnChanged := nil;
end;

procedure UnregisterOptions;
begin
  TAtlasOptionsRegistration.Unregister;
  TAtlasProjectSettings.Command := nil;
end;

end.
