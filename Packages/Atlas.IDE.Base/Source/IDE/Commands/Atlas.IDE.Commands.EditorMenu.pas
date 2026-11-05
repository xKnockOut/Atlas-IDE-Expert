unit Atlas.IDE.Commands.EditorMenu;

// Einträge des Untermenüs Atlas im Kontextmenü des Editors (#399), aus
// TAtlasIdeEditorCommands.Install (Atlas.IDE.Commands.Editor, Beschreibung dort)
// ausgelagert, in der Reihenfolge des Menüs.

interface

uses
  Atlas.IDE.Commands.ContextMenu;

type
  /// <summary>Einträge des Kontextmenüs der Editorbefehle.</summary>
  TAtlasEditorMenu = record
  private
    /// <summary>Code-Aktionen, Erzeugen-Menü und Auswahl.</summary>
    class procedure AddActions(AMenu: TAtlasIdeContextMenu); static;
    /// <summary>Implementierungen, Typdefinition und Methodenwechsel.</summary>
    class procedure AddNavigation(AMenu: TAtlasIdeContextMenu); static;
    /// <summary>Abschnittssprünge und Formatieren.</summary>
    class procedure AddSections(AMenu: TAtlasIdeContextMenu); static;
    /// <summary>Einträge der Module, Methodenreihenfolge, Referenzen, Aufrufdiagramm und Auswirkungen.</summary>
    class procedure AddLookups(AMenu: TAtlasIdeContextMenu); static;
    /// <summary>Testunit, qualifizierter Name und Rückgängig.</summary>
    class procedure AddTools(AMenu: TAtlasIdeContextMenu); static;
    /// <summary>Befunde und Ausblenden.</summary>
    class procedure AddProblems(AMenu: TAtlasIdeContextMenu); static;
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
  Atlas.IDE.EditorToolbar.Service,
  Atlas.IDE.Commands.EditorActions;

const
  // Plätze im Kontextmenü für Einträge der Module (#1455): Lesezeichen 8 (mit Trennlinien), Debugger 3, Tests 2,
  // Analyse 1, Tracker 1; Reserve für Regeln und Willkommensseite. Zu wenige meldet das Log.
  cModuleSlotCount = 24;

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
end;

class procedure TAtlasEditorMenu.AddNavigation(AMenu: TAtlasIdeContextMenu);
begin
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
end;

class procedure TAtlasEditorMenu.AddSections(AMenu: TAtlasIdeContextMenu);
begin
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
end;

class procedure TAtlasEditorMenu.AddLookups(AMenu: TAtlasIdeContextMenu);
begin
  // Einträge der Module (#1455), z. B. „Gezielt hineinspringen“ und die Befehle des Schrittfilters des Debuggers.
  AMenu.AddModuleSlots(cModuleSlotCount);
  // Methodenrümpfe wie die Klasse ordnen (#660); abgeschaltet meldet der Aufruf das.
  AMenu.AddGuarded(TAtlasFeature.MethodPlacement, 'Atlas.MethodOrder',
    TAtlasStrings.Text(TAtlasTextId.MethodOrderCommand), nil,
    procedure
    begin
      TAtlasIdeMethodPlacement.Run;
    end);
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
  AMenu.Add('-', nil, nil);
end;

class procedure TAtlasEditorMenu.AddTools(AMenu: TAtlasIdeContextMenu);
begin
  AMenu.Add('Atlas.SwitchTestUnit', TAtlasStrings.Text(TAtlasTextId.EditorTestUnit),
    function: Integer
    begin
      Result := TAtlasIdeSettings.Current.TestUnitKey;
    end,
    procedure
    begin
      TAtlasEditorActionCommands.SwitchTestUnit;
    end);
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
  AMenu.Add('-', nil, nil);
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
  AddSections(AMenu);
  AddLookups(AMenu);
  AddTools(AMenu);
  AddProblems(AMenu);
end;

end.
