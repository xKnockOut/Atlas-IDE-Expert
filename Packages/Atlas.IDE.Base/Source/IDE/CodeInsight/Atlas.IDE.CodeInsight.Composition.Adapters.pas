unit Atlas.IDE.CodeInsight.Composition.Adapters;

// Adapters, Providers und Compositions der Core-Features für die Kompositionswurzel: Serverprozess,
// Ordnerbeobachter, Quellen von Vervollständigung und Parameter-Hint, Code-Aktionen für den Klick auf eine Marke,
// Ziel und Sicherung des Änderungsprotokolls, die Update-Quelle und die Adapter der IDE-Features
// (Einstellungsspeicher, Editoransichten, Fenster als Ansichten der Controller, Palette, Einrichtung, Schattentext).
// Nur diese Unit erzeugt sie; die Features bekommen sie über Schnittstellen und Fabriken.

interface

uses
  System.SysUtils,
  Atlas.Core.Updates.Contract,
  Atlas.Core.Setup.Checklist,
  Atlas.Core.Files.Contract,
  Atlas.Core.Commands.Palette,
  Atlas.IDE.Contracts.GhostSuggestions,
  Atlas.IDE.Commands.Palette,
  Atlas.IDE.Setup.Checklist,
  Atlas.IDE.CodeInsight.Manager.State;

/// <summary>Serverprozess, Ordnerbeobachter und Quellen von Vervollständigung und Parameter-Hint aus dem Kern,
/// Code-Aktionen für den Klick auf die Marke „braucht kein Self“.</summary>
function CodeInsightAdapters: TAtlasCodeInsightAdapters;
/// <summary>Ziel auf der Platte und Sicherung des Änderungsprotokolls (#721) in TAtlasIdeUndoTarget und
/// TAtlasIdeUndo einsetzen.</summary>
procedure InstallUndoAdapters;
/// <summary>Quelle der Update-Prüfung (#495) über HTTP.</summary>
function UpdateSource: IAtlasVersionSource;
/// <summary>Fabriken der IDE-Adapter einsetzen: Einstellungsspeicher in der Registry, Sicht des Planers, Puffer
/// der Editoransicht, Fenster von Vervollständigung, Parameter-Hint und Tooltip. Ab der Unit-Initialisierung, vor
/// dem ersten Lesen der Einstellungen.</summary>
procedure InstallIdeAdapters;
/// <summary>Aktiver Editor und Puffer der offenen Dateien für TAtlasIdeHost.</summary>
function ActiveEditorAdapter: IAtlasActiveEditor;
function EditorFilesAdapter: IAtlasEditorFiles;
/// <summary>Die Palette als Ziel der Befehle der Teile.</summary>
function PaletteRegistry(APalette: TAtlasIdePalette): IAtlasCommandRegistry;
/// <summary>Vorschläge aus dem Index des Servers für den Schattentext (#1890).</summary>
function LearnedGhostProvider: IAtlasGhostProvider;
/// <summary>Was die Knöpfe der Einrichtung tun; AForgetKeys liest die Tasten beim nächsten Snapshot neu.</summary>
function SetupEnvironment(const AHooks: TAtlasSetupHooks; out AForgetKeys: TProc): IAtlasSetupEnvironment;

implementation

uses
  ToolsAPI,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.Adapters.ServerProcess,
  Atlas.Core.Files.WatchedChanges,
  Atlas.Core.Files.Adapters.FolderWatcher,
  Atlas.Core.Signature.Contract,
  Atlas.Core.Signature.Providers.Server,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Completion.Providers.Server,
  Atlas.Core.Completion.Providers.Snippets,
  Atlas.Core.Completion.Providers.XmlDoc,
  Atlas.Core.Undo.Contract,
  Atlas.Core.Undo.Adapters.DiskTarget,
  Atlas.Core.Undo.Adapters.FileStore,
  Atlas.Core.Updates.Adapters.HttpSource,
  Atlas.IDE.Completion.Editor,
  Atlas.IDE.Commands.Editor,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Editor.EditSurface,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.Core.Completion.Controller,
  Atlas.Core.Signature.Controller,
  Atlas.Core.Hover.Layout.Contract,
  Atlas.IDE.Undo.Changes,
  Atlas.IDE.Undo.Adapters.Target,
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
  Atlas.UI.Completion.Popup,
  Atlas.UI.Completion.Adapters.PopupView,
  Atlas.UI.Signature.Hint,
  Atlas.UI.Signature.Adapters.HintView,
  Atlas.UI.Hover.Tip,
  Atlas.UI.Hover.Adapters.TipMeasure;

/// <summary>Quellen der Vervollständigung: Server, XML-Doku und Snippets, mit Abbau und Schaltern.</summary>
function CompletionSources(const ASession: TAtlasSessionFunc; const ALog: TAtlasLogProc): TAtlasCompletionSources;
var
  mServer: TAtlasServerCompletionProvider;
  mSnippets: TAtlasSnippetCompletionProvider;
begin
  mServer := TAtlasServerCompletionProvider.Create(ASession);
  mServer.OnLog :=
    procedure(const AMessage: string)
    begin
      ALog(AMessage);
    end;
  mSnippets := TAtlasSnippetCompletionProvider.Create(TAtlasSnippets.BuiltIn);
  // Die Schnittstellen halten die Quellen; die Funktionen greifen über die Objekte zu.
  Result.Server := mServer;
  Result.XmlDoc := TAtlasXmlDocCompletionProvider.Create;
  Result.Snippets := mSnippets;
  Result.Shutdown :=
    procedure
    begin
      mServer.Shutdown;
      mSnippets.Shutdown;
    end;
  Result.SetSnippetsEnabled :=
    procedure(AEnabled: Boolean)
    begin
      mSnippets.Enabled := AEnabled;
      mServer.Snippets := AEnabled;
    end;
  Result.SetSnippetList :=
    procedure(AList: TAtlasSnippetList)
    begin
      mSnippets.SetSnippets(AList);
    end;
  Result.SnippetList :=
    function: TAtlasSnippetList
    begin
      Result := mSnippets.Snippets;
    end;
end;

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
    begin
      Result := CompletionSources(ASession, ALog);
    end;
  // Klick auf die Marke „braucht kein Self“ (#686): dieselbe Auswahl wie Strg+.
  Result.OpenCodeActions :=
    procedure
    begin
      TAtlasIdeEditorCommands.CodeActions;
    end;
  // Enter auf einem nicht sichtbaren Mitglied der Vervollständigung (#2108): Sichtbarkeit anheben, Eigenschaft
  // anlegen.
  Result.OfferActions :=
    procedure(const AActions: TArray<TLspCodeAction>)
    begin
      TAtlasIdeEditorCommands.OfferActions(AActions);
    end;
end;

procedure InstallUndoAdapters;
begin
  TAtlasIdeUndoTarget.DiskFactory :=
    function(const AHooks: TAtlasUndoDiskHooks): IAtlasUndoTarget
    var
      mDisk: TAtlasUndoDiskTarget;
    begin
      mDisk := TAtlasUndoDiskTarget.Create;
      mDisk.OnAddToProject := AHooks.OnAddToProject;
      mDisk.OnRemoveFromProject := AHooks.OnRemoveFromProject;
      mDisk.OnRecycle := AHooks.OnRecycle;
      Result := mDisk;
    end;
  TAtlasIdeUndo.TargetFactory :=
    function: IAtlasUndoTarget
    begin
      Result := TAtlasIdeUndoTarget.Create;
    end;
  TAtlasIdeUndo.StoreFactory :=
    function(const AFolder: string; AMaxBytes: Int64): IAtlasUndoStore
    begin
      Result := TAtlasUndoFileStore.Create(AFolder, AMaxBytes);
    end;
end;

function UpdateSource: IAtlasVersionSource;
begin
  Result := TAtlasHttpVersionSource.Create;
end;


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
  TAtlasCompletionPopup.ViewFactory :=
    function(APopup: TAtlasCompletionPopup): IAtlasCompletionView
    begin
      Result := TAtlasCompletionPopupView.Create(APopup);
    end;
  TAtlasSignatureHint.ViewFactory :=
    function(AHint: TAtlasSignatureHint): IAtlasSignatureView
    begin
      Result := TAtlasSignatureHintView.Create(AHint);
    end;
  TAtlasHoverTipView.MeasureFactory :=
    function(ATip: TAtlasHoverTipView): IAtlasHoverMeasure
    begin
      Result := TAtlasHoverTipMeasure.Create(ATip);
    end;
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

function SetupEnvironment(const AHooks: TAtlasSetupHooks; out AForgetKeys: TProc): IAtlasSetupEnvironment;
var
  mEnvironment: TAtlasIdeSetupEnvironment;
begin
  mEnvironment := TAtlasIdeSetupEnvironment.Create(AHooks);
  Result := mEnvironment;
  AForgetKeys := ForgetKeysOf(mEnvironment);
end;

end.
