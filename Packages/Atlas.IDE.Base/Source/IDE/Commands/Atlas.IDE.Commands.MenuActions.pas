unit Atlas.IDE.Commands.MenuActions;

// Was die Einträge des Hauptmenüs „Atlas“ ausführen, ausgelagert aus
// Atlas.IDE.Commands.MainMenu: Ergebnisfenster (#400), Editorbefehle (#399),
// Abschnittssprünge der Editorleiste (#1101), Atlas-Änderungen (#721) und
// „Prozesse am Projekt…“ (#62). Der Tag des Menüeintrags wählt den Befehl; jeder
// Befehl mit einer Kennung der Befehlspalette meldet sich vorher bei den
// Tastenkürzel-Tipps (#600) als Aufruf per Menü.

interface

uses
  System.SysUtils,
  System.JSON;

type
  /// <summary>Befehle der Einträge im Atlas-Menü, je Gruppe über den Tag des Eintrags.</summary>
  TAtlasMenuActions = record
  public
    /// <summary>Ergebnisfenster (#400): 0 Referenzen, 1 Implementierungen, 2 Symbolsuche, 3–6 Hierarchien,
    /// 7 Fenster, 8 Aufrufdiagramm, 9 Auswirkungen, 10/11 Datenfluss.</summary>
    class procedure RunResults(ACommand: Integer); static;
    /// <summary>Editorbefehle (#399): 0 Code-Aktionen, 1/2 Auswahl, 3 Typdefinition, 4/5 qualifizierter Name,
    /// 6 Methode, 7 Testunit, 10 Erzeugen, 11 Formatieren, 12 Methodenreihenfolge.</summary>
    class procedure RunEditor(ACommand: Integer); static;
    /// <summary>Abschnittssprünge der Editorleiste (#1101): 0 interface, 1 implementation, 2 uses,
    /// 3 initialization, 4 zurück, 5 Methode suchen.</summary>
    class procedure RunSection(ACommand: Integer); static;
    /// <summary>Atlas-Änderungen (#721): 0 zurücknehmen, 1 wiederherstellen, 2 Liste.</summary>
    class procedure RunUndo(ACommand: Integer); static;
    /// <summary>„Prozesse am Projekt…“ (#62); ACommand führt den Serverbefehl im Hintergrund aus (nil ohne Server).
    /// </summary>
    class procedure ShowProcesses(const ACommand: TProc<string, TProc<TJSONValue>>); static;
  end;

implementation

uses
  Vcl.Clipbrd,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.Processes,
  Atlas.Core.Results.Model,
  Atlas.Core.Lsp.DataFlow,
  Atlas.UI.Diagnostics.ProcessesDialog,
  Atlas.IDE.Files.DirtyExport,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Results.Impact,
  Atlas.IDE.Undo.Changes,
  Atlas.IDE.EditorToolbar.Service,
  Atlas.IDE.Commands.Editor,
  Atlas.IDE.Editor.MethodPlacement,
  Atlas.IDE.Generate.Commands,
  Atlas.IDE.Commands.ShortcutTips;

const
  // Kennungen der Befehlspalette für die Tastenkürzel-Tipps (#600), je Tag der Einträge.
  EditorIds: array[0..12] of string = ('Atlas.CodeActions', 'Atlas.ExpandSelection', 'Atlas.ShrinkSelection',
    'Atlas.TypeDefinition', 'Atlas.CopyQualifiedName', 'Atlas.CopyQualifiedNameParams', 'Atlas.ToggleMethod',
    'Atlas.SwitchTestUnit', '', '', 'Atlas.GenerateMenu', 'Atlas.FormatCode',
    'Atlas.MethodOrder');
  ResultsIds: array[0..11] of string = ('Atlas.References', 'Atlas.Implementations', 'Atlas.SymbolSearch',
    'Atlas.Callers', 'Atlas.Calls', 'Atlas.Supertypes', 'Atlas.Subtypes', 'Atlas.ResultsWindow', 'Atlas.CallDiagram',
    'Atlas.Impact', 'Atlas.DataFlowSources', 'Atlas.DataFlowTargets');
  // Editorleiste (#1101), je Tag von RunSection.
  SectionIds: array[0..5] of string = ('Atlas.GotoInterface', 'Atlas.GotoImplementation', 'Atlas.GotoUses',
    'Atlas.GotoInitialization', 'Atlas.ReturnFromSection', 'Atlas.FindMethod');
  UndoIds: array[0..2] of string = ('Atlas.UndoChange', 'Atlas.RedoChange', 'Atlas.ChangeList');

/// <summary>Meldet AIds[ACommand] bei den Tastenkürzel-Tipps, wenn es den Tag dort gibt.</summary>
procedure Invoked(const AIds: array of string; ACommand: Integer);
begin
  if (ACommand >= Low(AIds)) and (ACommand <= High(AIds)) then
  begin
    TAtlasIdeShortcutTips.Invoked(AIds[ACommand]);
  end;
end;

/// <summary>Befehl ACommand des Ergebnisfensters; im Schutz von TAtlasFeature.Results.</summary>
procedure ResultsCommand(ACommand: Integer);
begin
  case ACommand of
    0: TAtlasIdeResults.FindReferences;
    1: TAtlasIdeResults.FindImplementations;
    2: TAtlasIdeResults.SearchSymbol;
    3: TAtlasIdeResults.ShowHierarchy(TAtlasHierarchyDirection.Incoming);
    4: TAtlasIdeResults.ShowHierarchy(TAtlasHierarchyDirection.Outgoing);
    5: TAtlasIdeResults.ShowHierarchy(TAtlasHierarchyDirection.Supertypes);
    6: TAtlasIdeResults.ShowHierarchy(TAtlasHierarchyDirection.Subtypes);
    8: TAtlasIdeResults.ShowCallDiagram;
    9: TAtlasIdeImpact.ShowAtCursor;
    10: TAtlasIdeResults.ShowDataFlow(TAtlasDataFlowDirection.Sources);
    11: TAtlasIdeResults.ShowDataFlow(TAtlasDataFlowDirection.Targets);
  else
    TAtlasIdeResults.ShowWindow;
  end;
end;

/// <summary>Editorbefehl ACommand; im Schutz von TAtlasFeature.EditorCommands.</summary>
procedure EditorCommand(ACommand: Integer);
begin
  case ACommand of
    0: TAtlasIdeEditorCommands.CodeActions;
    1: TAtlasIdeEditorCommands.ExpandSelection;
    2: TAtlasIdeEditorCommands.ShrinkSelection;
    3: TAtlasIdeEditorCommands.GoToTypeDefinition;
    4: TAtlasIdeEditorCommands.CopyQualifiedName(False);
    6: TAtlasIdeEditorCommands.ToggleMethod;
    7: TAtlasIdeEditorCommands.SwitchTestUnit;
    10: TAtlasIdeGenerate.Show;
    11: TAtlasIdeEditorCommands.FormatCode;
    12: TAtlasGuard.Run(TAtlasFeature.MethodPlacement, TAtlasIdeMethodPlacement.Run);
  else
    TAtlasIdeEditorCommands.CopyQualifiedName(True);
  end;
end;

/// <summary>Abschnittssprung ACommand; im Schutz von TAtlasFeature.EditorToolbar.</summary>
procedure SectionCommand(ACommand: Integer);
begin
  case ACommand of
    0: TAtlasIdeEditorToolbar.GotoInterface;
    1: TAtlasIdeEditorToolbar.GotoImplementation;
    2: TAtlasIdeEditorToolbar.GotoUses;
    3: TAtlasIdeEditorToolbar.GotoInitialization;
    4: TAtlasIdeEditorToolbar.ReturnFromSection;
  else
    TAtlasIdeEditorToolbar.FindMethod;
  end;
end;

/// <summary>Befehl ACommand der Atlas-Änderungen; im Schutz von TAtlasFeature.EditorCommands.</summary>
procedure UndoCommand(ACommand: Integer);
begin
  case ACommand of
    0: TAtlasIdeUndo.UndoLast;
    1: TAtlasIdeUndo.RedoLast;
  else
    TAtlasIdeUndo.ShowList;
  end;
end;

/// <summary>Was der Dialog „Prozesse am Projekt…“ (#62) braucht.</summary>
function ProcessesActions(const ACommand: TProc<string, TProc<TJSONValue>>): TAtlasProcessesActions;
begin
  Result := Default(TAtlasProcessesActions);
  // Im Hintergrund wie der Index-Status (#874); die Antwort kommt im Hauptthread.
  Result.Fetch :=
    procedure(ADone: TProc<TJSONValue>)
    begin
      if Assigned(ACommand) then
      begin
        ACommand(TAtlasProcessesView.Command, ADone);
      end
      else
      begin
        ADone(nil);
      end;
    end;
  Result.ModifiedFiles :=
    function: TArray<string>
    begin
      Result := TAtlasDirtyExport.ModifiedFiles;
    end;
  Result.CopyText :=
    procedure(AText: string)
    begin
      Clipboard.AsText := AText;
    end;
end;

{ TAtlasMenuActions }

class procedure TAtlasMenuActions.RunResults(ACommand: Integer);
begin
  Invoked(ResultsIds, ACommand);
  TAtlasGuard.Run(TAtlasFeature.Results,
    procedure
    begin
      ResultsCommand(ACommand);
    end);
end;

class procedure TAtlasMenuActions.RunEditor(ACommand: Integer);
begin
  Invoked(EditorIds, ACommand);
  TAtlasGuard.Run(TAtlasFeature.EditorCommands,
    procedure
    begin
      EditorCommand(ACommand);
    end);
end;

class procedure TAtlasMenuActions.RunSection(ACommand: Integer);
begin
  Invoked(SectionIds, ACommand);
  TAtlasGuard.Run(TAtlasFeature.EditorToolbar,
    procedure
    begin
      SectionCommand(ACommand);
    end);
end;

class procedure TAtlasMenuActions.RunUndo(ACommand: Integer);
begin
  Invoked(UndoIds, ACommand);
  TAtlasGuard.Run(TAtlasFeature.EditorCommands,
    procedure
    begin
      UndoCommand(ACommand);
    end);
end;

class procedure TAtlasMenuActions.ShowProcesses(const ACommand: TProc<string, TProc<TJSONValue>>);
begin
  TAtlasGuard.Run(TAtlasFeature.Menu,
    procedure
    begin
      TAtlasProcessesDialog.Execute(ProcessesActions(ACommand));
    end);
end;

end.
