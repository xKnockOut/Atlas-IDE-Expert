unit Atlas.IDE.CodeInsight.Composition.IdeAdapters;

// Adapter der IDE-Features von Base für die Kompositionswurzel: Einstellungsspeicher in der Registry, aktiver
// Editor und offene Puffer, Sicht des Planers, Puffer der Editoransicht, Palette als Befehlsziel, Einrichtung und
// Schattentext aus dem Index. Nur diese Unit erzeugt sie; die Features bekommen sie über Fabriken an ihrer Wurzel,
// über TAtlasIdeHost oder als Parameter. Die Fenster als Ansichten der Controller setzt
// Atlas.IDE.CodeInsight.Composition.UiAdapters ein.

interface

uses
  System.SysUtils,
  Atlas.Core.Setup.Checklist,
  Atlas.Core.Files.Contract,
  Atlas.Core.Commands.Palette,
  Atlas.IDE.Contracts.GhostSuggestions,
  Atlas.IDE.Commands.Palette,
  Atlas.IDE.Setup.Checklist,
  Atlas.Core.Commands.Contract,
  Atlas.Core.Setup.Contract;

/// <summary>Fabriken der IDE-Adapter einsetzen: Einstellungsspeicher in der Registry, Sicht des Planers, Puffer
/// der Editoransicht, dazu die Fenster-Adapter (InstallUiAdapters). Ab der Unit-Initialisierung, vor dem ersten
/// Lesen der Einstellungen.</summary>
procedure InstallIdeAdapters;
/// <summary>Aktiver Editor für TAtlasIdeHost.</summary>
function ActiveEditorAdapter: IAtlasActiveEditor;
/// <summary>Puffer der offenen Dateien für TAtlasIdeHost.</summary>
function EditorFilesAdapter: IAtlasEditorFiles;
/// <summary>Die Palette als Ziel der Befehle der Teile.</summary>
function PaletteRegistry(APalette: TAtlasIdePalette): IAtlasCommandRegistry;
/// <summary>Vorschläge aus dem Index des Servers für den Schattentext (#1890).</summary>
function LearnedGhostProvider: IAtlasGhostProvider;
/// <summary>Was die Knöpfe der Einrichtung tun; AForgetKeys liest die Tasten beim nächsten Snapshot neu.</summary>
function SetupEnvironment(const AHooks: TAtlasSetupHooks; out AForgetKeys: TProc;
  out ASnapshot: TAtlasSetupSnapshot): IAtlasSetupEnvironment;

implementation

uses
  ToolsAPI,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Undo.Contract,
  Atlas.Core.Editor.EditSurface,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Adapters.ActiveEditor,
  Atlas.IDE.Foundation.Adapters.EditorFiles,
  Atlas.IDE.Foundation.Adapters.RegistryStore,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Editor.Surfaces,
  Atlas.IDE.Editor.Adapters.EditEnvironment,
  Atlas.IDE.Editor.Adapters.EditSurface,
  Atlas.IDE.Editor.Adapters.LearnedGhost,
  Atlas.IDE.Commands.Adapters.PaletteRegistry,
  Atlas.IDE.Setup.Adapters.Environment,
  Atlas.IDE.CodeInsight.Composition.UiAdapters,
  Atlas.Core.Editor.Contract;

procedure InstallIdeAdapters;
begin
  TAtlasIdeSettings.StoreFactory :=
    function(AWrite: Boolean): IAtlasSettingsStore
    begin
      Result := TAtlasRegistrySettingsStore.Create(AWrite);
    end;
  TAtlasIdeWorkspaceEdit.EnvironmentFactory :=
    function(const ATarget: IAtlasUndoTarget): IAtlasEditEnvironment
    begin
      Result := TAtlasIdeEditEnvironment.Create(ATarget);
    end;
  TAtlasIdeEditSurfaces.Factory :=
    function(const AView: IOTAEditView): IAtlasEditSurface
    begin
      Result := TAtlasIdeEditSurface.Create(AView);
    end;
  InstallUiAdapters;
end;

function ActiveEditorAdapter: IAtlasActiveEditor;
begin
  Result := TAtlasIdeActiveEditor.Create;
end;

function EditorFilesAdapter: IAtlasEditorFiles;
begin
  Result := TAtlasIdeEditorFiles.Create;
end;

function PaletteRegistry(APalette: TAtlasIdePalette): IAtlasCommandRegistry;
begin
  Result := TAtlasPaletteCommandRegistry.Create(APalette);
end;

function LearnedGhostProvider: IAtlasGhostProvider;
begin
  Result := TAtlasLearnedGhostProvider.Create;
end;

/// <summary>Eigene Routine: Die Methodenreferenz fängt nur AEnvironment ein.</summary>
function ForgetKeysOf(AEnvironment: TAtlasIdeSetupEnvironment): TProc;
begin
  Result :=
    procedure
    begin
      AEnvironment.ForgetKeys;
    end;
end;

/// <summary>Eigene Routine: Die Methodenreferenz fängt nur AEnvironment ein.</summary>
function SnapshotOf(AEnvironment: TAtlasIdeSetupEnvironment): TAtlasSetupSnapshot;
begin
  Result :=
    function: TAtlasSetupInput
    begin
      Result := AEnvironment.Snapshot;
    end;
end;

function SetupEnvironment(const AHooks: TAtlasSetupHooks; out AForgetKeys: TProc;
  out ASnapshot: TAtlasSetupSnapshot): IAtlasSetupEnvironment;
var
  mEnvironment: TAtlasIdeSetupEnvironment;
begin
  mEnvironment := TAtlasIdeSetupEnvironment.Create(AHooks);
  Result := mEnvironment;
  AForgetKeys := ForgetKeysOf(mEnvironment);
  ASnapshot := SnapshotOf(mEnvironment);
end;

end.
