unit Atlas.IDE.Commands.EditorMenu;

// Einträge des Untermenüs Atlas im Kontextmenü des Editors (#399), aus
// TAtlasIdeEditorCommands.Install (Atlas.IDE.Commands.Editor, Beschreibung dort)
// ausgelagert, in der Reihenfolge des Menüs. Oben die häufigsten Befehle
// (Code-Aktionen, Erzeugen), danach Untermenüs Navigation, Bearbeiten, Suchen
// und analysieren, Befunde (mit der Zahl der Befunde der Datei), dann die
// Einträge der Module (eigene Untermenüs nach Section) und „Element
// ausblenden“. Alles in einer Ebene war höher als der Bildschirm. Regionen
// zu-/aufklappen nur in Units mit Regionen (TAtlasIdeMenuContext).

interface

uses
  Atlas.IDE.Commands.ContextMenu;

type
  /// <summary>Einträge des Kontextmenüs der Editorbefehle.</summary>
  TAtlasEditorMenu = record
  private
    /// <summary>Code-Aktionen und Erzeugen-Menü.</summary>
    class procedure AddActions(AMenu: TAtlasIdeContextMenu); static;
    /// <summary>Untermenü Navigation: Implementierungen, Typdefinition, Methodenwechsel, Abschnitte, Testunit.
    /// </summary>
    class procedure AddNavigation(AMenu: TAtlasIdeContextMenu); static;
    /// <summary>Alle Regionen zu- bzw. aufklappen (#1814, in Navigation).</summary>
    class procedure AddRegions(AMenu: TAtlasIdeContextMenu); static;
    /// <summary>Abschnittssprünge und Testunit (in Navigation).</summary>
    class procedure AddSections(AMenu: TAtlasIdeContextMenu); static;
    /// <summary>Untermenü Bearbeiten: Auswahl, Formatieren, Methodenreihenfolge.</summary>
    class procedure AddEditing(AMenu: TAtlasIdeContextMenu); static;
    /// <summary>Qualifizierten Namen kopieren und Atlas-Änderungen (in Bearbeiten).</summary>
    class procedure AddTools(AMenu: TAtlasIdeContextMenu); static;
    /// <summary>Untermenü Suchen und analysieren: Referenzen, Aufrufdiagramm, Auswirkungen.</summary>
    class procedure AddLookups(AMenu: TAtlasIdeContextMenu); static;
    /// <summary>Untermenü Befunde.</summary>
    class procedure AddProblems(AMenu: TAtlasIdeContextMenu); static;
    /// <summary>Einträge der Module und Ausblenden.</summary>
    class procedure AddModules(AMenu: TAtlasIdeContextMenu); static;
  public
    /// <summary>Alle Einträge in AMenu aufnehmen.</summary>
    class procedure Fill(AMenu: TAtlasIdeContextMenu); static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Results.Impact,
  Atlas.IDE.Undo.Changes,
  Atlas.IDE.Generate.Commands,
  Atlas.IDE.Editor.Hide,
  Atlas.IDE.Problems.Service,
  Atlas.IDE.Editor.MethodPlacement,
  Atlas.IDE.Editor.RegionFolds,
  Atlas.UI.Editor.RegionFolds,
  Atlas.IDE.Editor.LearnedSuggestions,
  Atlas.UI.Editor.LearnedSuggestions,
  Atlas.IDE.EditorToolbar.Service,
  Atlas.IDE.Commands.EditorActions,
  Atlas.IDE.Commands.MenuContext,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Settings.ContextMenuGroups,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Namen der Untermenüs (#1458).</summary>
  TEditorMenuText = (Edit, Analysis, Findings);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TEditorMenuText] of string = (
    ('Bearbeiten', 'Suchen und analysieren', 'Befunde'),
    ('Edit', 'Search and analyze', 'Findings'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TEditorMenuText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

/// <summary>Hat die Unit Regionen?</summary>
function UnitHasRegions(const AContext: TAtlasMenuContext): Boolean;
begin
  Result := AContext.HasRegions;
end;

/// <summary>Regionen zu-/aufklappen (#1814) sichtbar, solange editor.regionFolds nicht off ist und die Unit
/// Regionen hat.</summary>
function RegionFoldsVisible: Boolean;
begin
  Result := TAtlasIdeRegionFolds.Enabled and TAtlasIdeMenuContext.Applies(UnitHasRegions);
end;

/// <summary>Kennung eines Untermenüs für commands.editorContextMenu.groups.</summary>
function GroupKey(AGroup: TAtlasContextMenuGroup): string;
begin
  Result := TAtlasContextMenuGroupNames.Name(AGroup);
end;

/// <summary>„Gelernte Vorschläge anzeigen …“ (#1890) sichtbar mit suggestions.learned.</summary>
function LearnedSuggestionsVisible: Boolean;
begin
  Result := TAtlasIdeLearnedSuggestions.Enabled;
end;

const
  // Plätze im Kontextmenü für Einträge der Module (#1455). Untermenüs nach Section: Notizen und Lesezeichen 7,
  // Debuggen 3, Tests 2; direkt: Analyse 1, Tracker 1. Reserve für Regeln und Willkommensseite. Zu wenige meldet
  // das Log.
  cModuleTopSlots = 8;
  cModuleGroups = 4;
  cModuleGroupSlots = 10;

{ TAtlasEditorMenu }

class procedure TAtlasEditorMenu.AddActions(AMenu: TAtlasIdeContextMenu);
begin
  AMenu.Add('Atlas.CodeActions', TAtlasStrings.Text(TAtlasTextId.EditorActions),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.ActionsKey;
    end,
    procedure
    begin
      TAtlasEditorActionCommands.CodeActions;
    end);
  // Erzeugen-Menü (#719); aus = ohne Kürzel, der Aufruf meldet, dass es abgeschaltet ist.
  AMenu.AddGuarded(TAtlasFeature.Generate, 'Atlas.GenerateMenu',
    TAtlasStrings.Text(TAtlasTextId.GenerateMenuCommand),
    function: Integer
    begin
      Result := 0;
      if TAtlasIdeSettings.Current.GenerateMenu then
      begin
        Result := TAtlasIdeSettings.Current.GenerateMenuKey;
      end;
    end,
    procedure
    begin
      TAtlasIdeGenerate.Show;
    end);
  AMenu.Add('-', nil, nil);
end;

class procedure TAtlasEditorMenu.AddEditing(AMenu: TAtlasIdeContextMenu);
begin
  AMenu.BeginGroup(UiText(TEditorMenuText.Edit), GroupKey(TAtlasContextMenuGroup.Edit), nil);
  AMenu.Add('Atlas.ExpandSelection', TAtlasStrings.Text(TAtlasTextId.EditorExpand),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.ExpandKey;
    end,
    procedure
    begin
      TAtlasEditorActionCommands.ExpandSelection;
    end);
  AMenu.Add('Atlas.ShrinkSelection', TAtlasStrings.Text(TAtlasTextId.EditorShrink),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.ShrinkKey;
    end,
    procedure
    begin
      TAtlasEditorActionCommands.ShrinkSelection;
    end);
  AMenu.Add('-', nil, nil);
  // Formatieren (#43); aus = ohne Kürzel, der Aufruf meldet, dass es abgeschaltet ist.
  AMenu.Add('Atlas.FormatCode', TAtlasStrings.Text(TAtlasTextId.FormatCodeCommand),
    function: Integer
    begin
      Result := 0;
      if TAtlasIdeSettings.Current.FormatCode then
      begin
        Result := TAtlasIdeSettings.Current.FormatCodeKey;
      end;
    end,
    procedure
    begin
      TAtlasEditorActionCommands.FormatCode;
    end);
  // Methodenrümpfe wie die Klasse ordnen (#660); abgeschaltet meldet der Aufruf das.
  AMenu.AddGuarded(TAtlasFeature.MethodPlacement, 'Atlas.MethodOrder',
    TAtlasStrings.Text(TAtlasTextId.MethodOrderCommand), nil,
    procedure
    begin
      TAtlasIdeMethodPlacement.Run;
    end);
  AddTools(AMenu);
  AMenu.EndGroup;
end;

class procedure TAtlasEditorMenu.AddNavigation(AMenu: TAtlasIdeContextMenu);
begin
  AMenu.BeginGroup(TAtlasStrings.Text(TAtlasTextId.MenuGroupNavigation), GroupKey(TAtlasContextMenuGroup.Navigation),
    nil);
  AMenu.Add('Atlas.Implementations', TAtlasStrings.Text(TAtlasTextId.MenuImplementations),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.ImplementationKey;
    end,
    procedure
    begin
      // Über das Ergebnisfenster (#400): eine einzige Implementierung springt direkt.
      TAtlasIdeResults.FindImplementations;
    end);
  AMenu.Add('Atlas.TypeDefinition', TAtlasStrings.Text(TAtlasTextId.EditorTypeDefinition),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.TypeDefinitionKey;
    end,
    procedure
    begin
      TAtlasEditorActionCommands.GoToTypeDefinition;
    end);
  AMenu.Add('Atlas.ToggleMethod', TAtlasStrings.Text(TAtlasTextId.EditorMethodToggle),
    function: Integer
    begin
      Result := 0;
      if TAtlasIdeSettings.Current.MethodToggle then
      begin
        Result := TAtlasIdeSettings.Current.MethodToggleUpKey;
      end;
    end,
    procedure
    begin
      TAtlasEditorActionCommands.ToggleMethod;
    end);
  AddRegions(AMenu);
  AddSections(AMenu);
  AMenu.EndGroup;
end;

class procedure TAtlasEditorMenu.AddRegions(AMenu: TAtlasIdeContextMenu);
begin
  AMenu.AddWhen(TAtlasFeature.RegionFolds, 'Atlas.CollapseRegions',
    TAtlasRegionFoldsTexts.Text(TAtlasRegionFoldsText.CollapseCommand), nil,
    procedure
    begin
      TAtlasIdeRegionFolds.CollapseAll;
    end, RegionFoldsVisible);
  AMenu.AddWhen(TAtlasFeature.RegionFolds, 'Atlas.ExpandRegions',
    TAtlasRegionFoldsTexts.Text(TAtlasRegionFoldsText.ExpandCommand), nil,
    procedure
    begin
      TAtlasIdeRegionFolds.ExpandAll;
    end, RegionFoldsVisible);
  AMenu.AddWhen(TAtlasFeature.LearnedSuggestions, 'Atlas.LearnedSuggestions',
    TAtlasLearnedTexts.Text(TAtlasLearnedText.Command), nil,
    procedure
    begin
      TAtlasIdeLearnedSuggestions.ShowPatterns;
    end, LearnedSuggestionsVisible);
end;

class procedure TAtlasEditorMenu.AddSections(AMenu: TAtlasIdeContextMenu);
begin
  AMenu.Add('-', nil, nil);
  // Abschnittssprünge der Editorleiste (#1101), auch ohne die Leiste.
  AMenu.Add('Atlas.GotoInterface', TAtlasStrings.Text(TAtlasTextId.GotoInterfaceCommand),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.GotoInterfaceKey;
    end,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.EditorToolbar, TAtlasIdeEditorToolbar.GotoInterface);
    end);
  AMenu.Add('Atlas.GotoImplementation', TAtlasStrings.Text(TAtlasTextId.GotoImplementationCommand),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.GotoImplementationKey;
    end,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.EditorToolbar, TAtlasIdeEditorToolbar.GotoImplementation);
    end);
  AMenu.Add('-', nil, nil);
  AMenu.Add('Atlas.SwitchTestUnit', TAtlasStrings.Text(TAtlasTextId.EditorTestUnit),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.TestUnitKey;
    end,
    procedure
    begin
      TAtlasEditorActionCommands.SwitchTestUnit;
    end);
end;

class procedure TAtlasEditorMenu.AddLookups(AMenu: TAtlasIdeContextMenu);
begin
  AMenu.BeginGroup(UiText(TEditorMenuText.Analysis), GroupKey(TAtlasContextMenuGroup.Analysis), nil);
  AMenu.Add('Atlas.References', TAtlasStrings.Text(TAtlasTextId.MenuReferences), nil,
    procedure
    begin
      TAtlasIdeResults.FindReferences;
    end);
  // Aufrufdiagramm (#1122): Das Kontextmenü entsteht einmal, deshalb gilt callHierarchy.diagram hier ab dem
  // nächsten Start; Palette und Menü Atlas folgen sofort.
  if TAtlasIdeResults.CallDiagramAllowed then
  begin
    AMenu.AddGuarded(TAtlasFeature.Results, 'Atlas.CallDiagram',
      TAtlasStrings.Text(TAtlasTextId.CallDiagramCommand), nil,
      procedure
      begin
        TAtlasIdeResults.ShowCallDiagram;
      end);
  end;
  // Auswirkungen anzeigen (#1120), nur mit navigation.impact.
  AMenu.AddWhen(TAtlasFeature.Results, 'Atlas.Impact', TAtlasStrings.Text(TAtlasTextId.ImpactCommand), nil,
    procedure
    begin
      TAtlasIdeImpact.ShowAtCursor;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeImpact.Enabled;
    end);
  AMenu.EndGroup;
end;

class procedure TAtlasEditorMenu.AddTools(AMenu: TAtlasIdeContextMenu);
begin
  AMenu.Add('-', nil, nil);
  AMenu.Add('Atlas.CopyQualifiedName', TAtlasStrings.Text(TAtlasTextId.EditorCopyQualified), nil,
    procedure
    begin
      TAtlasEditorActionCommands.CopyQualifiedName(False);
    end);
  AMenu.Add('Atlas.CopyQualifiedNameParams', TAtlasStrings.Text(TAtlasTextId.EditorCopyQualifiedParams), nil,
    procedure
    begin
      TAtlasEditorActionCommands.CopyQualifiedName(True);
    end);
  // Atlas-Änderungen über mehrere Dateien (#721).
  AMenu.Add('-', nil, nil);
  AMenu.Add('Atlas.UndoChange', TAtlasStrings.Text(TAtlasTextId.UndoMenu),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.UndoKey;
    end,
    procedure
    begin
      TAtlasIdeUndo.UndoLast;
    end);
  AMenu.Add('Atlas.RedoChange', TAtlasStrings.Text(TAtlasTextId.RedoMenu),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.RedoKey;
    end,
    procedure
    begin
      TAtlasIdeUndo.RedoLast;
    end);
end;

class procedure TAtlasEditorMenu.AddProblems(AMenu: TAtlasIdeContextMenu);
begin
  // Nächster/vorheriger Befund (#509).
  // Mit der Zahl der Befunde der Datei, etwa „Befunde (3)“.
  AMenu.BeginGroup(UiText(TEditorMenuText.Findings), GroupKey(TAtlasContextMenuGroup.Findings),
    function: Integer
    begin
      Result := TAtlasIdeMenuContext.ProblemCount;
    end);
  AMenu.Add('Atlas.NextProblem', TAtlasStrings.Text(TAtlasTextId.ProblemNextCommand),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.NextProblemKey;
    end,
    procedure
    begin
      TAtlasEditorActionCommands.StepProblem(True);
    end);
  AMenu.Add('Atlas.PreviousProblem', TAtlasStrings.Text(TAtlasTextId.ProblemPreviousCommand),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.PreviousProblemKey;
    end,
    procedure
    begin
      TAtlasEditorActionCommands.StepProblem(False);
    end);
  // Datei jetzt prüfen (#1744): nur mit Prüfregeln.
  AMenu.AddWhen(TAtlasFeature.Problems, 'Atlas.CheckFile',
    TAtlasStrings.Text(TAtlasTextId.ProblemsCheckFileCommand),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.CheckFileKey;
    end,
    procedure
    begin
      TAtlasIdeProblems.CheckFileNow;
    end,
    function: Boolean
    begin
      Result := TAtlasIdeSettings.Current.Problems;
    end);
  AMenu.EndGroup;
end;

class procedure TAtlasEditorMenu.AddModules(AMenu: TAtlasIdeContextMenu);
begin
  // Einträge der Module (#1455), z. B. „Gezielt hineinspringen“ und die Befehle des Schrittfilters des Debuggers.
  AMenu.Add('-', nil, nil);
  AMenu.AddModuleSlots(cModuleTopSlots, cModuleGroups, cModuleGroupSlots);
  // Ausblenden am Element (#628): nach einem Rechtsklick auf ein Element im Text oder in der Rinne für dieses.
  AMenu.Add('-', nil, nil);
  AMenu.AddGuarded(TAtlasFeature.Hide, 'Atlas.HideElement', TAtlasStrings.Text(TAtlasTextId.HideElementCommand),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.HideElementKey;
    end,
    procedure
    begin
      TAtlasIdeHide.ShowForCommand;
    end);
end;

class procedure TAtlasEditorMenu.Fill(AMenu: TAtlasIdeContextMenu);
begin
  AddActions(AMenu);
  AddNavigation(AMenu);
  AddEditing(AMenu);
  AddLookups(AMenu);
  AddProblems(AMenu);
  AddModules(AMenu);
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.IDE.Commands.EditorMenu', cTexts[TAtlasLanguage.German],
    cTexts[TAtlasLanguage.English]);

end.
