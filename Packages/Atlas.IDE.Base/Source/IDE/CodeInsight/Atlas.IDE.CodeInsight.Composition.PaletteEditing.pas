unit Atlas.IDE.CodeInsight.Composition.PaletteEditing;

// Befehle der Palette (#502) zum Bearbeiten im Editor: Sprung zum Gegenstück (#635), Änderungen (#507), Zeilen
// verschieben (#634), Anweisung vervollständigen (#697), Formatieren (#43), Blockkommentar (#703), neue Zeile
// (#700), Umschließung entfernen (#657), Ausdruckstyp (#689), Methodenreihenfolge (#660), sicher löschen (#716) und
// mehrere Einfügemarken (#589). Jeder nur sichtbar, solange seine Einstellung an ist.

interface

uses
  Atlas.IDE.Commands.Palette;

/// <summary>Bearbeitungsbefehle in Startreihenfolge an APalette.</summary>
procedure AddEditingCommands(APalette: TAtlasIdePalette);

implementation

uses
  Atlas.UI.Strings,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Editor.LineMove,
  Atlas.Core.Editor.NewLine,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Commands.Editor,
  Atlas.IDE.Editor.LineChanges,
  Atlas.IDE.Editor.LineMove,
  Atlas.IDE.Editor.StatementCompletion,
  Atlas.IDE.Editor.BlockComment,
  Atlas.IDE.Editor.NewLine,
  Atlas.IDE.Editor.Unwrap,
  Atlas.IDE.Editor.ExpressionType,
  Atlas.IDE.Editor.MethodPlacement,
  Atlas.IDE.Editor.MultiCursor,
  Atlas.IDE.CodeInsight.Composition.Session;

function JumpToMatchVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.JumpToMatch;
end;

procedure JumpToMatch;
begin
  TAtlasIdeEditorCommands.JumpToMatch(False);
end;

procedure SelectToMatch;
begin
  TAtlasIdeEditorCommands.JumpToMatch(True);
end;

function ChangesVisible: Boolean;
begin
  Result := TAtlasIdeLineChanges.Enabled;
end;

procedure NextChange;
begin
  TAtlasIdeLineChanges.GoToChange(True);
end;

procedure PreviousChange;
begin
  TAtlasIdeLineChanges.GoToChange(False);
end;

function MoveLinesVisible: Boolean;
begin
  Result := TAtlasIdeLineMove.Enabled;
end;

procedure MoveLinesUp;
begin
  TAtlasIdeLineMove.Run(TAtlasLineMoveKind.MoveUp);
end;

procedure MoveLinesDown;
begin
  TAtlasIdeLineMove.Run(TAtlasLineMoveKind.MoveDown);
end;

procedure DuplicateLinesUp;
begin
  TAtlasIdeLineMove.Run(TAtlasLineMoveKind.DuplicateUp);
end;

procedure DuplicateLinesDown;
begin
  TAtlasIdeLineMove.Run(TAtlasLineMoveKind.DuplicateDown);
end;

function CompleteStatementVisible: Boolean;
begin
  Result := TAtlasIdeStatementCompletion.Enabled;
end;

procedure CompleteStatement;
begin
  TAtlasIdeStatementCompletion.Run;
end;

function FormatCodeVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.FormatCode;
end;

procedure FormatCode;
begin
  TAtlasIdeEditorCommands.FormatCode;
end;

function ToggleBlockCommentVisible: Boolean;
begin
  Result := TAtlasIdeBlockComment.Enabled;
end;

procedure ToggleBlockComment;
begin
  TAtlasIdeBlockComment.Run;
end;

function NewLineAroundVisible: Boolean;
begin
  Result := TAtlasIdeNewLine.Enabled;
end;

procedure NewLineBelow;
begin
  TAtlasIdeNewLine.Run(TAtlasNewLineDirection.Below);
end;

procedure NewLineAbove;
begin
  TAtlasIdeNewLine.Run(TAtlasNewLineDirection.Above);
end;

function UnwrapVisible: Boolean;
begin
  Result := TAtlasIdeUnwrap.Enabled;
end;

procedure Unwrap;
begin
  TAtlasIdeUnwrap.Run;
end;

function ExpressionTypeVisible: Boolean;
begin
  Result := TAtlasIdeExpressionType.Enabled;
end;

procedure ShowExpressionType;
begin
  TAtlasIdeExpressionType.Run;
end;

function MethodOrderVisible: Boolean;
begin
  Result := TAtlasIdeMethodPlacement.Enabled;
end;

procedure ArrangeMethods;
begin
  TAtlasIdeMethodPlacement.Run;
end;

function SafeDeleteVisible: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.SafeDelete;
end;

procedure SafeDelete;
begin
  TAtlasIdeEditorCommands.SafeDelete;
end;

function MultiCursorVisible: Boolean;
begin
  Result := TAtlasIdeMultiCursor.Enabled;
end;

procedure MultiCursorNext;
begin
  TAtlasIdeMultiCursor.TryNext;
end;

procedure MultiCursorLineEnds;
begin
  TAtlasIdeMultiCursor.TryLineEnds;
end;

procedure MultiCursorAbove;
begin
  TAtlasIdeMultiCursor.TryVertical(True);
end;

procedure MultiCursorBelow;
begin
  TAtlasIdeMultiCursor.TryVertical(False);
end;

/// <summary>Sprung zum Gegenstück (#635), Änderungen (#507) und Zeilen verschieben und duplizieren (#634).</summary>
procedure AddLineCommands(APalette: TAtlasIdePalette);
begin
  AddCommand(APalette, 'Atlas.JumpToMatch', TAtlasTextId.JumpToMatchCommand,
    Guarded(TAtlasFeature.EditorCommands, JumpToMatch), JumpToMatchVisible);
  AddCommand(APalette, 'Atlas.JumpToMatchSelect', TAtlasTextId.JumpToMatchSelectCommand,
    Guarded(TAtlasFeature.EditorCommands, SelectToMatch), JumpToMatchVisible);
  AddCommand(APalette, 'Atlas.NextChange', TAtlasTextId.NextChangeCommand,
    Guarded(TAtlasFeature.LineChanges, NextChange), ChangesVisible);
  AddCommand(APalette, 'Atlas.PreviousChange', TAtlasTextId.PreviousChangeCommand,
    Guarded(TAtlasFeature.LineChanges, PreviousChange), ChangesVisible);
  AddCommand(APalette, 'Atlas.MoveLinesUp', TAtlasTextId.MoveLinesUpCommand,
    Guarded(TAtlasFeature.EditorCommands, MoveLinesUp), MoveLinesVisible);
  AddCommand(APalette, 'Atlas.MoveLinesDown', TAtlasTextId.MoveLinesDownCommand,
    Guarded(TAtlasFeature.EditorCommands, MoveLinesDown), MoveLinesVisible);
  AddCommand(APalette, 'Atlas.DuplicateLinesUp', TAtlasTextId.DuplicateLinesUpCommand,
    Guarded(TAtlasFeature.EditorCommands, DuplicateLinesUp), MoveLinesVisible);
  AddCommand(APalette, 'Atlas.DuplicateLinesDown', TAtlasTextId.DuplicateLinesDownCommand,
    Guarded(TAtlasFeature.EditorCommands, DuplicateLinesDown), MoveLinesVisible);
end;

/// <summary>Anweisung vervollständigen (#697), Formatieren (#43), Blockkommentar (#703), neue Zeile (#700),
/// Umschließung entfernen (#657), Ausdruckstyp (#689), Methodenreihenfolge (#660) und sicher löschen (#716).
/// </summary>
procedure AddCodeCommands(APalette: TAtlasIdePalette);
begin
  AddCommand(APalette, 'Atlas.CompleteStatement', TAtlasTextId.CompleteStatementCommand,
    Guarded(TAtlasFeature.EditorCommands, CompleteStatement), CompleteStatementVisible);
  AddCommand(APalette, 'Atlas.FormatCode', TAtlasTextId.FormatCodeCommand,
    Guarded(TAtlasFeature.EditorCommands, FormatCode), FormatCodeVisible);
  AddCommand(APalette, 'Atlas.ToggleBlockComment', TAtlasTextId.ToggleBlockCommentCommand,
    Guarded(TAtlasFeature.EditorCommands, ToggleBlockComment), ToggleBlockCommentVisible);
  AddCommand(APalette, 'Atlas.NewLineBelow', TAtlasTextId.NewLineBelowCommand,
    Guarded(TAtlasFeature.EditorCommands, NewLineBelow), NewLineAroundVisible);
  AddCommand(APalette, 'Atlas.NewLineAbove', TAtlasTextId.NewLineAboveCommand,
    Guarded(TAtlasFeature.EditorCommands, NewLineAbove), NewLineAroundVisible);
  AddCommand(APalette, 'Atlas.Unwrap', TAtlasTextId.UnwrapCommand, Guarded(TAtlasFeature.Unwrap, Unwrap),
    UnwrapVisible);
  AddCommand(APalette, 'Atlas.ExpressionType', TAtlasTextId.ExpressionTypeCommand,
    Guarded(TAtlasFeature.ExpressionType, ShowExpressionType), ExpressionTypeVisible);
  AddCommand(APalette, 'Atlas.MethodOrder', TAtlasTextId.MethodOrderCommand,
    Guarded(TAtlasFeature.MethodPlacement, ArrangeMethods), MethodOrderVisible);
  AddCommand(APalette, 'Atlas.SafeDelete', TAtlasTextId.SafeDeleteCommand,
    Guarded(TAtlasFeature.EditorCommands, SafeDelete), SafeDeleteVisible);
end;

/// <summary>Mehrere Einfügemarken (#589).</summary>
procedure AddMultiCursorCommands(APalette: TAtlasIdePalette);
begin
  AddCommand(APalette, 'Atlas.MultiCursorNext', TAtlasTextId.MultiCursorNextCommand,
    Guarded(TAtlasFeature.MultiCursor, MultiCursorNext), MultiCursorVisible);
  AddCommand(APalette, 'Atlas.MultiCursorLineEnds', TAtlasTextId.MultiCursorLineEndsCommand,
    Guarded(TAtlasFeature.MultiCursor, MultiCursorLineEnds), MultiCursorVisible);
  AddCommand(APalette, 'Atlas.MultiCursorAbove', TAtlasTextId.MultiCursorAboveCommand,
    Guarded(TAtlasFeature.MultiCursor, MultiCursorAbove), MultiCursorVisible);
  AddCommand(APalette, 'Atlas.MultiCursorBelow', TAtlasTextId.MultiCursorBelowCommand,
    Guarded(TAtlasFeature.MultiCursor, MultiCursorBelow), MultiCursorVisible);
end;

procedure AddEditingCommands(APalette: TAtlasIdePalette);
begin
  AddLineCommands(APalette);
  AddCodeCommands(APalette);
  AddMultiCursorCommands(APalette);
end;

end.
