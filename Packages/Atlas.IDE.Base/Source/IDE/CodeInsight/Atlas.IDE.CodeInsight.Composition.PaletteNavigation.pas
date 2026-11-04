unit Atlas.IDE.CodeInsight.Composition.PaletteNavigation;

// Befehle der Palette (#502) zum Suchen und Springen: Ergebnisfenster (#400), Auswirkungsanalyse (#1120),
// Schnell öffnen (#503), Navigationsverlauf (#504), Einblenden (#505), Gliederung (#537), Brotkrumen (#590),
// Atlas-Editorleiste (#1101), Hierarchien und Datenfluss (#690, #1122), Änderungsprotokoll (#721), Fenster
// „Atlas-Prüfung“ (#909) und die Editorbefehle (#399, #509, #628).

interface

uses
  Atlas.IDE.Commands.Palette;

/// <summary>Suchen, Verlauf, Einblenden, Gliederung und Editorleiste an APalette.</summary>
procedure AddNavigationCommands(APalette: TAtlasIdePalette);
/// <summary>Hierarchien, Datenfluss, Ergebnisfenster, Änderungsprotokoll und Fenster „Atlas-Prüfung“.</summary>
procedure AddHierarchyCommands(APalette: TAtlasIdePalette);
/// <summary>Editorbefehle (#399): Code-Aktionen, Ausblenden, Befunde, Auswahl, Typ, Methode, Namen, Testunit.
/// </summary>
procedure AddEditorCommands(APalette: TAtlasIdePalette);

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Lsp.DataFlow,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.CodeInsight.Manager.Paths,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Results.Impact,
  Atlas.IDE.Commands.QuickOpen,
  Atlas.IDE.Commands.Editor,
  Atlas.IDE.Editor.NavHistory,
  Atlas.IDE.Results.Peek,
  Atlas.IDE.Outline.Service,
  Atlas.IDE.Outline.Breadcrumbs,
  Atlas.IDE.EditorToolbar.Service,
  Atlas.IDE.Undo.Changes,
  Atlas.IDE.Problems.Service,
  Atlas.IDE.Editor.Hide,
  Atlas.IDE.CodeInsight.Composition.Session,
  Atlas.IDE.CodeInsight.Composition.Tools;

function ImpactVisible: Boolean;
begin
  Result := TAtlasIdeImpact.Enabled;
end;

function QuickOpenVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.QuickOpen;
end;

function NavHistoryVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.NavHistory;
end;

function PeekVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Peek;
end;

function OutlineVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Outline;
end;

function BreadcrumbsVisible: Boolean;
begin
  Result := TAtlasIdeBreadcrumbs.Enabled;
end;

function DataFlowVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DataFlow;
end;

/// <summary>Befehl „Aufrufdiagramm“ (#1122) sichtbar?</summary>
function CallDiagramVisible: Boolean;
begin
  Result := TAtlasIdeResults.CallDiagramAllowed;
end;

function ProblemsWindowVisible: Boolean;
begin
  Result := TAtlasIdeProblems.Enabled;
end;

function Hierarchy(ADirection: TAtlasHierarchyDirection): TProc;
var
  mDirection: TAtlasHierarchyDirection;
begin
  mDirection := ADirection;
  Result :=
    procedure
    begin
      TAtlasIdeResults.ShowHierarchy(mDirection);
    end;
end;

function DataFlow(ADirection: TAtlasDataFlowDirection): TProc;
var
  mDirection: TAtlasDataFlowDirection;
begin
  mDirection := ADirection;
  Result :=
    procedure
    begin
      TAtlasIdeResults.ShowDataFlow(mDirection);
    end;
end;

/// <summary>Atlas-Editorleiste (#1101): Abschnittssprünge, Rücksprung und „Methode suchen“ auch ohne Leiste.
/// </summary>
procedure AddToolbarCommands(APalette: TAtlasIdePalette);
begin
  AddCommand(APalette, 'Atlas.GotoInterface', TAtlasTextId.GotoInterfaceCommand,
    Guarded(TAtlasFeature.EditorToolbar, TAtlasIdeEditorToolbar.GotoInterface));
  AddCommand(APalette, 'Atlas.GotoImplementation', TAtlasTextId.GotoImplementationCommand,
    Guarded(TAtlasFeature.EditorToolbar, TAtlasIdeEditorToolbar.GotoImplementation));
  AddCommand(APalette, 'Atlas.GotoUses', TAtlasTextId.GotoUsesCommand,
    Guarded(TAtlasFeature.EditorToolbar, TAtlasIdeEditorToolbar.GotoUses));
  AddCommand(APalette, 'Atlas.GotoInitialization', TAtlasTextId.GotoInitializationCommand,
    Guarded(TAtlasFeature.EditorToolbar, TAtlasIdeEditorToolbar.GotoInitialization));
  AddCommand(APalette, 'Atlas.ReturnFromSection', TAtlasTextId.ReturnFromSectionCommand,
    Guarded(TAtlasFeature.EditorToolbar, TAtlasIdeEditorToolbar.ReturnFromSection));
  AddCommand(APalette, 'Atlas.FindMethod', TAtlasTextId.FindMethodCommand,
    Guarded(TAtlasFeature.EditorToolbar, TAtlasIdeEditorToolbar.FindMethod));
  AddCommand(APalette, 'Atlas.EditorToolbarCustomize', TAtlasTextId.EditorToolbarCustomizeCommand,
    Guarded(TAtlasFeature.EditorToolbar, TAtlasIdeEditorToolbar.Customize));
end;

/// <summary>Navigationsverlauf über Dateien (#504) und Einblenden (#505).</summary>
procedure AddHistoryCommands(APalette: TAtlasIdePalette);
begin
  AddCommand(APalette, 'Atlas.NavBack', TAtlasTextId.NavBackCommand,
    Guarded(TAtlasFeature.NavHistory, TAtlasIdeNavHistory.GoBack), NavHistoryVisible);
  AddCommand(APalette, 'Atlas.NavForward', TAtlasTextId.NavForwardCommand,
    Guarded(TAtlasFeature.NavHistory, TAtlasIdeNavHistory.GoForward), NavHistoryVisible);
  AddCommand(APalette, 'Atlas.LastEdit', TAtlasTextId.NavLastEditCommand,
    Guarded(TAtlasFeature.NavHistory, TAtlasIdeNavHistory.GoLastEdit), NavHistoryVisible);
  AddCommand(APalette, 'Atlas.NavList', TAtlasTextId.NavListCommand,
    Guarded(TAtlasFeature.NavHistory, TAtlasIdeNavHistory.ShowList), NavHistoryVisible);
  AddCommand(APalette, 'Atlas.PeekDefinition', TAtlasTextId.PeekDefinitionCommand,
    Guarded(TAtlasFeature.Peek, TAtlasIdePeek.PeekDefinition), PeekVisible);
  AddCommand(APalette, 'Atlas.PeekReferences', TAtlasTextId.PeekReferencesCommand,
    Guarded(TAtlasFeature.Peek, TAtlasIdePeek.PeekReferences), PeekVisible);
end;

/// <summary>Protokoll öffnen aus der Palette: nur das Diagnoseprotokoll.</summary>
procedure OpenDiagnoseLog;
begin
  OpenInEditor(TAtlasCodeInsightPaths.DiagnoseLog);
end;

procedure AddNavigationCommands(APalette: TAtlasIdePalette);
begin
  AddCommand(APalette, 'Atlas.Log', TAtlasTextId.PaletteLog, OpenDiagnoseLog);
  AddCommand(APalette, 'Atlas.Rename', TAtlasTextId.RenameMenu, RenameSymbol);
  // Ergebnisfenster (#400).
  AddCommand(APalette, 'Atlas.References', TAtlasTextId.MenuReferences, TAtlasIdeResults.FindReferences);
  AddCommand(APalette, 'Atlas.Implementations', TAtlasTextId.MenuImplementations,
    TAtlasIdeResults.FindImplementations);
  AddCommand(APalette, 'Atlas.SymbolSearch', TAtlasTextId.MenuSymbolSearch, TAtlasIdeResults.SearchSymbol);
  // Auswirkungsanalyse (#1120); nur sichtbar, solange navigation.impact an ist.
  AddCommand(APalette, 'Atlas.Impact', TAtlasTextId.ImpactCommand,
    Guarded(TAtlasFeature.Results, TAtlasIdeImpact.ShowAtCursor), ImpactVisible);
  // Schnell öffnen (#503); nur sichtbar, solange quickOpen.enabled an ist.
  AddCommand(APalette, 'Atlas.QuickOpen', TAtlasTextId.QuickOpenTitle,
    Guarded(TAtlasFeature.Palette, TAtlasIdeQuickOpen.Show), QuickOpenVisible);
  AddHistoryCommands(APalette);
  // Gliederungsfenster (#537); nur sichtbar, solange outline.enabled an ist.
  AddCommand(APalette, 'Atlas.Outline', TAtlasTextId.OutlineCommand,
    Guarded(TAtlasFeature.Outline, TAtlasIdeOutline.ShowWindow), OutlineVisible);
  // Brotkrumenleiste (#590): Fokus auf das letzte Glied; nur sichtbar, solange editor.breadcrumbs an ist.
  AddCommand(APalette, 'Atlas.Breadcrumbs', TAtlasTextId.BreadcrumbsCommand,
    Guarded(TAtlasFeature.Breadcrumbs, TAtlasIdeBreadcrumbs.Focus), BreadcrumbsVisible);
  AddToolbarCommands(APalette);
end;

procedure AddHierarchyCommands(APalette: TAtlasIdePalette);
begin
  AddCommand(APalette, 'Atlas.Callers', TAtlasTextId.MenuIncoming, Hierarchy(TAtlasHierarchyDirection.Incoming));
  AddCommand(APalette, 'Atlas.Calls', TAtlasTextId.MenuOutgoing, Hierarchy(TAtlasHierarchyDirection.Outgoing));
  // Aufrufdiagramm (#1122); nur sichtbar, solange callHierarchy.diagram an ist.
  AddCommand(APalette, 'Atlas.CallDiagram', TAtlasTextId.CallDiagramCommand,
    Guarded(TAtlasFeature.Results, TAtlasIdeResults.ShowCallDiagram), CallDiagramVisible);
  AddCommand(APalette, 'Atlas.Supertypes', TAtlasTextId.MenuSupertypes,
    Hierarchy(TAtlasHierarchyDirection.Supertypes));
  AddCommand(APalette, 'Atlas.Subtypes', TAtlasTextId.MenuSubtypes, Hierarchy(TAtlasHierarchyDirection.Subtypes));
  // Datenfluss (#690); nur sichtbar, solange navigation.dataFlow an ist.
  AddCommand(APalette, 'Atlas.DataFlowSources', TAtlasTextId.MenuDataFlowSources,
    Guarded(TAtlasFeature.Results, DataFlow(TAtlasDataFlowDirection.Sources)), DataFlowVisible);
  AddCommand(APalette, 'Atlas.DataFlowTargets', TAtlasTextId.MenuDataFlowTargets,
    Guarded(TAtlasFeature.Results, DataFlow(TAtlasDataFlowDirection.Targets)), DataFlowVisible);
  AddCommand(APalette, 'Atlas.ResultsWindow', TAtlasTextId.MenuResultsWindow, TAtlasIdeResults.ShowWindow);
  // Atlas-Änderungen über mehrere Dateien (#721).
  AddCommand(APalette, 'Atlas.UndoChange', TAtlasTextId.UndoMenu, TAtlasIdeUndo.UndoLast);
  AddCommand(APalette, 'Atlas.RedoChange', TAtlasTextId.RedoMenu, TAtlasIdeUndo.RedoLast);
  AddCommand(APalette, 'Atlas.ChangeList', TAtlasTextId.UndoListMenu, TAtlasIdeUndo.ShowList);
  // Befehle der Module (Debugger u. a., #1455) fragt die Palette selbst bei der Registry.
  // Fenster „Atlas-Prüfung“ (#909); nur sichtbar, solange problems.window an ist.
  AddCommand(APalette, 'Atlas.ProblemsWindow', TAtlasTextId.ProblemsWindowCommand,
    Guarded(TAtlasFeature.Problems, TAtlasIdeProblems.ShowWindow), ProblemsWindowVisible);
end;

procedure NextProblem;
begin
  TAtlasIdeEditorCommands.StepProblem(True);
end;

procedure PreviousProblem;
begin
  TAtlasIdeEditorCommands.StepProblem(False);
end;

procedure CopyQualifiedName;
begin
  TAtlasIdeEditorCommands.CopyQualifiedName(False);
end;

procedure CopyQualifiedNameParams;
begin
  TAtlasIdeEditorCommands.CopyQualifiedName(True);
end;

procedure AddEditorCommands(APalette: TAtlasIdePalette);
begin
  AddCommand(APalette, 'Atlas.CodeActions', TAtlasTextId.EditorActions, TAtlasIdeEditorCommands.CodeActions);
  // Ausblenden am Element (#628).
  AddCommand(APalette, 'Atlas.HideElement', TAtlasTextId.HideElementCommand,
    Guarded(TAtlasFeature.Hide, TAtlasIdeHide.ShowForCommand));
  // Nächster/vorheriger Befund (#509).
  AddCommand(APalette, 'Atlas.NextProblem', TAtlasTextId.ProblemNextCommand, NextProblem);
  AddCommand(APalette, 'Atlas.PreviousProblem', TAtlasTextId.ProblemPreviousCommand, PreviousProblem);
  AddCommand(APalette, 'Atlas.ExpandSelection', TAtlasTextId.EditorExpand, TAtlasIdeEditorCommands.ExpandSelection);
  AddCommand(APalette, 'Atlas.ShrinkSelection', TAtlasTextId.EditorShrink, TAtlasIdeEditorCommands.ShrinkSelection);
  AddCommand(APalette, 'Atlas.TypeDefinition', TAtlasTextId.EditorTypeDefinition,
    TAtlasIdeEditorCommands.GoToTypeDefinition);
  AddCommand(APalette, 'Atlas.ToggleMethod', TAtlasTextId.EditorMethodToggle, TAtlasIdeEditorCommands.ToggleMethod);
  AddCommand(APalette, 'Atlas.CopyQualifiedName', TAtlasTextId.EditorCopyQualified, CopyQualifiedName);
  AddCommand(APalette, 'Atlas.CopyQualifiedNameParams', TAtlasTextId.EditorCopyQualifiedParams,
    CopyQualifiedNameParams);
  AddCommand(APalette, 'Atlas.SwitchTestUnit', TAtlasTextId.EditorTestUnit, TAtlasIdeEditorCommands.SwitchTestUnit);
end;

end.
