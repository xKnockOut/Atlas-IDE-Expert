unit Atlas.IDE.Commands.KeysEditing;

// Tasten der Editorbefehle zum Bearbeiten und Springen im Quelltext, ausgelagert
// aus TAtlasIdeEditorKeys.Rebind (Atlas.IDE.Commands.Bindings, Beschreibung dort):
// Code-Aktionen, Auswahl, Implementierung, Typdefinition, Deklaration ⇄
// Implementierung (#775), Ausblenden (#628), Befunde (#509, #909), Testunit
// (#189), Abschnittssprünge (#1101), Formatieren (#43), Blockkommentar (#703),
// neue Zeile (#700), Umschließung entfernen (#657), F3/Umschalt+F3 (#698),
// Typ des Ausdrucks (#689), Sicher löschen (#716), Zeilen verschieben (#634),
// Anweisung vervollständigen (#697), Mehrfachmarken (#589) und
// Atlas-Änderungen (#721). Die Reihenfolge der Gruppen bestimmt Rebind.

interface

uses
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Commands.KeyList;

type
  /// <summary>Tasten der Editorbefehle zum Bearbeiten, je Gruppe.</summary>
  TAtlasEditingKeys = record
  public
    /// <summary>Code-Aktionen, Auswahl, Implementierung, Typdefinition, Testunit und Abschnittssprünge.</summary>
    class procedure AddBasics(AKeys: TAtlasEditorKeyList; const ASettings: TAtlasPluginSettings); static;
    /// <summary>Deklaration ⇄ Implementierung, Ausblenden am Element und die Befunde.</summary>
    class procedure AddChecks(AKeys: TAtlasEditorKeyList; const ASettings: TAtlasPluginSettings); static;
    /// <summary>Formatieren, Blockkommentar, neue Zeile ober- oder unterhalb, Umschließung entfernen.</summary>
    class procedure AddTextEdits(AKeys: TAtlasEditorKeyList; const ASettings: TAtlasPluginSettings); static;
    /// <summary>F3/Umschalt+F3 (Austrittspunkte, Markierung suchen), Typ des Ausdrucks, Sicher löschen. Nach den
    /// Tasten der Module: Belegt die Suche (#878) F3, gilt deren Versuch.</summary>
    class procedure AddSearch(AKeys: TAtlasEditorKeyList; const ASettings: TAtlasPluginSettings); static;
    /// <summary>Zeilen verschieben und duplizieren, Anweisung vervollständigen.</summary>
    class procedure AddLineEdits(AKeys: TAtlasEditorKeyList; const ASettings: TAtlasPluginSettings); static;
    /// <summary>Mehrfachmarken und Atlas-Änderungen zurücknehmen bzw. wiederherstellen.</summary>
    class procedure AddCursorAndUndo(AKeys: TAtlasEditorKeyList; const ASettings: TAtlasPluginSettings); static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  Vcl.Menus,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Strings,
  Atlas.IDE.Commands.Editor,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Problems.Service,
  Atlas.IDE.Undo.Changes,
  Atlas.IDE.Editor.Hide,
  Atlas.IDE.Editor.ExitPoints,
  Atlas.IDE.EditorToolbar.Service,
  Atlas.Core.Editor.LineMove,
  Atlas.IDE.Editor.LineMove,
  Atlas.IDE.Editor.StatementCompletion,
  Atlas.IDE.Editor.MultiCursor,
  Atlas.IDE.Editor.BlockComment,
  Atlas.Core.Editor.NewLine,
  Atlas.IDE.Editor.NewLine,
  Atlas.IDE.Editor.Unwrap,
  Atlas.IDE.Editor.ExpressionType;

function Text(AId: TAtlasTextId): string;
begin
  Result := TAtlasStrings.Text(AId);
end;

/// <summary>Zeilen verschieben bzw. duplizieren (#634).</summary>
function LineMove(AKind: TAtlasLineMoveKind): TProc;
begin
  Result :=
    procedure
    begin
      TAtlasIdeLineMove.Run(AKind);
    end;
end;

/// <summary>Neue Zeile ober- oder unterhalb (#700).</summary>
function NewLine(ADirection: TAtlasNewLineDirection): TProc;
begin
  Result :=
    procedure
    begin
      TAtlasIdeNewLine.Run(ADirection);
    end;
end;

/// <summary>Einfügemarke über bzw. unter der Zeile (#589); False gibt die Taste an die IDE.</summary>
function Vertical(AUp: Boolean): TFunc<Boolean>;
begin
  Result :=
    function: Boolean
    begin
      Result := TAtlasIdeMultiCursor.TryVertical(AUp);
    end;
end;

/// <summary>Austrittspunkte (#698), sonst Markierung suchen; False gibt die Taste an „Erneut suchen“ der IDE.
/// </summary>
function FindNext(ABackward: Boolean): TFunc<Boolean>;
begin
  Result :=
    function: Boolean
    begin
      Result := TAtlasIdeExitPoints.TryJump(ABackward) or TAtlasIdeEditorCommands.TryFindSelection(ABackward);
    end;
end;

/// <summary>Nächster bzw. vorheriger Befund (#509).</summary>
function StepProblem(AForward: Boolean): TProc;
begin
  Result :=
    procedure
    begin
      TAtlasIdeEditorCommands.StepProblem(AForward);
    end;
end;

/// <summary>Ausblenden am Element (#628); ohne Element behält die IDE die Taste.</summary>
function HideAtCaret: Boolean;
begin
  Result := False;
  try
    Result := TAtlasIdeHide.ShowForCaret;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hide, E);
  end;
end;

{ TAtlasEditingKeys }

class procedure TAtlasEditingKeys.AddBasics(AKeys: TAtlasEditorKeyList; const ASettings: TAtlasPluginSettings);
begin
  AKeys.AddKey(TAtlasFeature.EditorCommands, ASettings.ActionsKey, Text(TAtlasTextId.EditorActions),
    TAtlasIdeEditorCommands.CodeActions);
  AKeys.AddKey(TAtlasFeature.EditorCommands, ASettings.ExpandKey, Text(TAtlasTextId.EditorExpand),
    TAtlasIdeEditorCommands.ExpandSelection);
  AKeys.AddKey(TAtlasFeature.EditorCommands, ASettings.ShrinkKey, Text(TAtlasTextId.EditorShrink),
    TAtlasIdeEditorCommands.ShrinkSelection);
  AKeys.AddKey(TAtlasFeature.EditorCommands, ASettings.ImplementationKey, Text(TAtlasTextId.MenuImplementations),
    TAtlasIdeResults.FindImplementations);
  AKeys.AddKey(TAtlasFeature.EditorCommands, ASettings.TypeDefinitionKey, Text(TAtlasTextId.EditorTypeDefinition),
    TAtlasIdeEditorCommands.GoToTypeDefinition);
end;

class procedure TAtlasEditingKeys.AddChecks(AKeys: TAtlasEditorKeyList; const ASettings: TAtlasPluginSettings);
begin
  // Deklaration ⇄ Implementierung (#775): aus = Taste bleibt bei der Klassennavigation der IDE.
  if ASettings.MethodToggle then
  begin
    AKeys.AddAttemptKey(TAtlasFeature.EditorCommands, ASettings.MethodToggleUpKey,
      Text(TAtlasTextId.EditorMethodToggle), TAtlasIdeEditorCommands.TryToggleMethod);
    AKeys.AddAttemptKey(TAtlasFeature.EditorCommands, ASettings.MethodToggleDownKey,
      Text(TAtlasTextId.EditorMethodToggle), TAtlasIdeEditorCommands.TryToggleMethod);
  end;
  // Ausblenden am Element (#628): mit Rückfall, ohne Element behält die IDE die Taste (Strg+. = IDE Insight).
  if ASettings.HideElementKey <> 0 then
  begin
    AKeys.AddAttemptKey(TAtlasFeature.Hide, ASettings.HideElementKey, Text(TAtlasTextId.HideElementCommand),
      HideAtCaret, False);
  end;
  // Nächster/vorheriger Befund (#509): nur mit Problemen im Editor.
  if ASettings.Problems then
  begin
    AKeys.AddKey(TAtlasFeature.EditorCommands, ASettings.NextProblemKey, Text(TAtlasTextId.ProblemNextCommand),
      StepProblem(True));
    AKeys.AddKey(TAtlasFeature.EditorCommands, ASettings.PreviousProblemKey,
      Text(TAtlasTextId.ProblemPreviousCommand), StepProblem(False));
  end;
  // Fenster „Atlas-Prüfung“ (#909): aus = das Kürzel gehört der IDE.
  if ASettings.Problems and ASettings.ProblemsWindow then
  begin
    AKeys.AddKey(TAtlasFeature.Problems, ASettings.ProblemsWindowKey, Text(TAtlasTextId.ProblemsWindowCommand),
      TAtlasIdeProblems.ShowWindow);
  end;
  AKeys.AddKey(TAtlasFeature.EditorCommands, ASettings.TestUnitKey, Text(TAtlasTextId.EditorTestUnit),
    TAtlasIdeEditorCommands.SwitchTestUnit);
  // Abschnittssprünge der Editorleiste (#1101); Vorgabe ohne Taste, auch ohne die Leiste.
  AKeys.AddKey(TAtlasFeature.EditorToolbar, ASettings.GotoInterfaceKey, Text(TAtlasTextId.GotoInterfaceCommand),
    TAtlasIdeEditorToolbar.GotoInterface);
  AKeys.AddKey(TAtlasFeature.EditorToolbar, ASettings.GotoImplementationKey,
    Text(TAtlasTextId.GotoImplementationCommand), TAtlasIdeEditorToolbar.GotoImplementation);
end;

class procedure TAtlasEditingKeys.AddTextEdits(AKeys: TAtlasEditorKeyList; const ASettings: TAtlasPluginSettings);
begin
  // Formatieren (#43): aus = keine Taste.
  if ASettings.FormatCode then
  begin
    AKeys.AddKey(TAtlasFeature.EditorCommands, ASettings.FormatCodeKey, Text(TAtlasTextId.FormatCodeCommand),
      TAtlasIdeEditorCommands.FormatCode);
  end;
  // Blockkommentar umschalten (#703): aus = Kürzel frei.
  if ASettings.ToggleBlockComment then
  begin
    AKeys.AddKey(TAtlasFeature.EditorCommands, ASettings.ToggleBlockCommentKey,
      Text(TAtlasTextId.ToggleBlockCommentCommand), TAtlasIdeBlockComment.Run);
  end;
  // Neue Zeile ober- oder unterhalb (#700): aus = die Tasten gehören der IDE.
  if ASettings.NewLineAround then
  begin
    AKeys.AddKey(TAtlasFeature.EditorCommands, ASettings.NewLineBelowKey, Text(TAtlasTextId.NewLineBelowCommand),
      NewLine(TAtlasNewLineDirection.Below));
    AKeys.AddKey(TAtlasFeature.EditorCommands, ASettings.NewLineAboveKey, Text(TAtlasTextId.NewLineAboveCommand),
      NewLine(TAtlasNewLineDirection.Above));
  end;
  // Umschließung entfernen (#657): aus = das Kürzel gehört der IDE.
  if ASettings.Unwrap then
  begin
    AKeys.AddKey(TAtlasFeature.Unwrap, ASettings.UnwrapKey, Text(TAtlasTextId.UnwrapCommand), TAtlasIdeUnwrap.Run);
  end;
end;

class procedure TAtlasEditingKeys.AddSearch(AKeys: TAtlasEditorKeyList; const ASettings: TAtlasPluginSettings);
begin
  // Austrittspunkte (#698): F3 bzw. Umschalt+F3 springt reihum, solange die Hervorhebung steht und der Cursor auf
  // einer ihrer Stellen liegt (dann gibt es keine Markierung). Markierung suchen: mit einzeiliger Markierung; sonst
  // „Erneut suchen“ der IDE.
  AKeys.AddAttemptKey(TAtlasFeature.EditorCommands, ShortCut(VK_F3, []), 'F3', FindNext(False), False);
  AKeys.AddAttemptKey(TAtlasFeature.EditorCommands, ShortCut(VK_F3, [ssShift]), 'Umschalt+F3', FindNext(True),
    False);
  // Typ des markierten Ausdrucks (#689): Strg+Umschalt+T ist in der IDE „To-Do-Eintrag hinzufügen“; mit Vorrang
  // übernommen. Aus = das Kürzel gehört der IDE.
  if ASettings.ExpressionType then
  begin
    AKeys.AddPriorityKey(TAtlasFeature.ExpressionType, ASettings.ExpressionTypeKey,
      Text(TAtlasTextId.ExpressionTypeCommand), TAtlasIdeExpressionType.Run, True);
  end;
  // Sicher löschen (#716): aus = das Kürzel gehört der IDE.
  if ASettings.SafeDelete then
  begin
    AKeys.AddKey(TAtlasFeature.EditorCommands, ASettings.SafeDeleteKey, Text(TAtlasTextId.SafeDeleteCommand),
      TAtlasIdeEditorCommands.SafeDelete);
  end;
end;

class procedure TAtlasEditingKeys.AddLineEdits(AKeys: TAtlasEditorKeyList; const ASettings: TAtlasPluginSettings);
begin
  // Zeilen verschieben und duplizieren (#634): Die Tasten gehören in der IDE dem Code-Browsing und der
  // Spaltenmarkierung; bewusst übernommen, darum mit Vorrang. Aus = die IDE behält sie.
  if ASettings.MoveLines then
  begin
    AKeys.AddPriorityKey(TAtlasFeature.EditorCommands, ASettings.MoveLinesUpKey,
      Text(TAtlasTextId.MoveLinesUpCommand), LineMove(TAtlasLineMoveKind.MoveUp), True);
    AKeys.AddPriorityKey(TAtlasFeature.EditorCommands, ASettings.MoveLinesDownKey,
      Text(TAtlasTextId.MoveLinesDownCommand), LineMove(TAtlasLineMoveKind.MoveDown), True);
    AKeys.AddPriorityKey(TAtlasFeature.EditorCommands, ASettings.DuplicateLinesUpKey,
      Text(TAtlasTextId.DuplicateLinesUpCommand), LineMove(TAtlasLineMoveKind.DuplicateUp), True);
    AKeys.AddPriorityKey(TAtlasFeature.EditorCommands, ASettings.DuplicateLinesDownKey,
      Text(TAtlasTextId.DuplicateLinesDownCommand), LineMove(TAtlasLineMoveKind.DuplicateDown), True);
  end;
  // Anweisung vervollständigen (#697): Strg+Umschalt+Enter sucht in der IDE Referenzen; mit Vorrang übernommen.
  if ASettings.CompleteStatement then
  begin
    AKeys.AddPriorityKey(TAtlasFeature.EditorCommands, ASettings.CompleteStatementKey,
      Text(TAtlasTextId.CompleteStatementCommand), TAtlasIdeStatementCompletion.Run, True);
  end;
end;

class procedure TAtlasEditingKeys.AddCursorAndUndo(AKeys: TAtlasEditorKeyList;
  const ASettings: TAtlasPluginSettings);
begin
  // Mehrere Einfügemarken (#589, experimentell): mit Rückfall, ohne Treffer behält die IDE die Taste (Strg+D =
  // Quelltext formatieren). Bewusst eingeschaltet, darum ohne Konfliktprüfung.
  if ASettings.MultiCursor then
  begin
    AKeys.AddAttemptKey(TAtlasFeature.MultiCursor, ASettings.MultiCursorNextKey,
      Text(TAtlasTextId.MultiCursorNextCommand), TAtlasIdeMultiCursor.TryNext, False);
    AKeys.AddAttemptKey(TAtlasFeature.MultiCursor, ASettings.MultiCursorLineEndsKey,
      Text(TAtlasTextId.MultiCursorLineEndsCommand), TAtlasIdeMultiCursor.TryLineEnds, False);
    AKeys.AddAttemptKey(TAtlasFeature.MultiCursor, ASettings.MultiCursorAboveKey,
      Text(TAtlasTextId.MultiCursorAboveCommand), Vertical(True), False);
    AKeys.AddAttemptKey(TAtlasFeature.MultiCursor, ASettings.MultiCursorBelowKey,
      Text(TAtlasTextId.MultiCursorBelowCommand), Vertical(False), False);
  end;
  AKeys.AddKey(TAtlasFeature.EditorCommands, ASettings.UndoKey, Text(TAtlasTextId.UndoMenu), TAtlasIdeUndo.UndoLast);
  AKeys.AddKey(TAtlasFeature.EditorCommands, ASettings.RedoKey, Text(TAtlasTextId.RedoMenu), TAtlasIdeUndo.RedoLast);
end;

end.
