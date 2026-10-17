unit Atlas.IDE.Editor.LineMove;

// Zeilen und Blöcke verschieben und duplizieren (#634) im Editor: Alt+↑/↓
// verschiebt die Cursorzeile bzw. alle von der Markierung berührten Zeilen,
// Umschalt+Alt+↑/↓ dupliziert sie darüber bzw. darunter. Auf einem
// Methodenkopf ohne Markierung wandert die ganze Methode. Was sich ändert,
// berechnet Atlas.Core.Editor.LineMove; hier bleiben Puffer, Cursor und
// Markierung.
// - Eine Änderung ist ein Schreiber der IDE (CreateUndoableWriter), also ein
//   Rückgängig-Schritt. Folgt ein Tastendruck direkt auf den vorigen (dieselbe
//   Datei, seither nichts geändert, Cursor noch dort, wo Atlas ihn hingesetzt
//   hat), nimmt Atlas den vorigen Schritt zurück und schreibt die ganze Folge
//   neu: Strg+Z nimmt sie auf einmal zurück. Stimmt der Text nach dem
//   Zurücknehmen nicht, stellt Atlas ihn wieder her und schreibt einen eigenen
//   Schritt.
// - Cursor und Markierung wandern mit dem Block, um den geänderten Einzug
//   verschoben; Einrückungsweite ist der Blockeinzug der IDE.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Editor.LineMove;

type
  TAtlasIdeLineMove = class
  private class var
    FMessage: TProc<string>;
    /// <summary>Laufende Folge: Datei, Text vor dem ersten und nach dem letzten Schritt, Cursor danach.</summary>
    FFileName: string;
    FBefore: string;
    FAfter: string;
    FCursorLine: Integer;
    FCursorColumn: Integer;
  public
    /// <summary>AMessage zeigt eine Zeile in der Meldungsansicht.</summary>
    class procedure Install(const AMessage: TProc<string>); static;
    class procedure Uninstall; static;
    /// <summary>keys.moveLines an (für Palette und Tastenkürzel)?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Verschiebt bzw. dupliziert im oberen Editor.</summary>
    class procedure Run(AKind: TAtlasLineMoveKind); static;
  end;

implementation

uses
  ToolsAPI,
  Atlas.Core.Lsp.Session,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot;

type
  TPosition = record
    Line: Integer;
    Character: Integer;
  end;

/// <summary>Ersetzt in ABuffer (Text AText) ab Zeichen AStart AOldLength Zeichen durch AInsert; ein
/// Rückgängig-Schritt.</summary>
procedure WriteBuffer(const ABuffer: IOTAEditBuffer; const AText: string; AStart, AOldLength: Integer;
  const AInsert: string);
var
  Writer: IOTAEditWriter;
begin
  Writer := ABuffer.CreateUndoableWriter;
  Writer.CopyTo(TEncoding.UTF8.GetByteCount(Copy(AText, 1, AStart)));
  Writer.DeleteTo(TEncoding.UTF8.GetByteCount(Copy(AText, 1, AStart + AOldLength)));
  if AInsert <> '' then
    Writer.Insert(PAnsiChar(UTF8Encode(AInsert)));
  Writer := nil;
  TAtlasEditorSnapshots.Invalidate(ABuffer.FileName);
end;

function EditPos(const ALines: TArray<string>; const APosition: TPosition; ATabWidth: Integer): TOTAEditPos;
var
  LineText: string;
begin
  LineText := '';
  if (APosition.Line >= 0) and (APosition.Line < Length(ALines)) then
    LineText := ALines[APosition.Line];
  Result.Line := APosition.Line + 1;
  Result.Col := TLspSession.IndexToColumn(LineText, APosition.Character, ATabWidth);
end;

function PositionOf(const ALines: TArray<string>; ARow, AColumn, ATabWidth: Integer): TPosition;
var
  LineText: string;
begin
  LineText := '';
  if (ARow >= 1) and (ARow <= Length(ALines)) then
    LineText := ALines[ARow - 1];
  Result.Line := ARow - 1;
  Result.Character := TLspSession.ColumnToIndex(LineText, AColumn, ATabWidth);
end;

/// <summary>Neue Stelle einer Markierungsgrenze: im Block mit ihm, das Ende am Zeilenanfang dahinter hinter den
/// neuen Block.</summary>
function Mapped(const AMove: TAtlasLineMove; const APosition: TPosition; ALast: Integer): TPosition;
begin
  Result := APosition;
  if APosition.Line > ALast then
  begin
    Result.Line := AMove.LastLine + 1;
    Exit;
  end;
  TAtlasLineMover.MapPosition(AMove, Result.Line, Result.Character);
end;

{ TAtlasIdeLineMove }

class procedure TAtlasIdeLineMove.Install(const AMessage: TProc<string>);
begin
  FMessage := AMessage;
end;

class procedure TAtlasIdeLineMove.Uninstall;
begin
  FMessage := nil;
  FFileName := '';
  FBefore := '';
  FAfter := '';
end;

class function TAtlasIdeLineMove.Enabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.MoveLines;
end;

class procedure TAtlasIdeLineMove.Run(AKind: TAtlasLineMoveKind);
var
  View: IOTAEditView;
  Buffer: IOTAEditBuffer;
  Block: IOTAEditBlock;
  Cursor: TOTAEditPos;
  Text, Before, NewText, LineBreak, Insert: string;
  Lines, NewLines: TArray<string>;
  TabWidth, First, Last, MethodLine, Start, OldLength: Integer;
  CursorAt, SelectionStart, SelectionEnd: TPosition;
  HasSelection, Grouped: Boolean;
  Move: TAtlasLineMove;
begin
  if not Enabled then
    Exit;
  View := TAtlasEditorBuffer.ActiveView;
  if (View = nil) or (View.Buffer = nil) then
    Exit;
  Buffer := View.Buffer;
  if Buffer.IsReadOnly then
    Exit;
  Text := TAtlasEditorBuffer.Text(Buffer);
  LineBreak := #10;
  if Pos(#13#10, Text) > 0 then
    LineBreak := #13#10;
  Lines := Text.Split([#13#10, #10]);
  TabWidth := TAtlasEditorBuffer.TabWidth(Buffer);
  Cursor := View.CursorPos;
  CursorAt := PositionOf(Lines, Cursor.Line, Cursor.Col, TabWidth);
  Block := View.Block;
  HasSelection := (Block <> nil) and Block.IsValid and (Block.Size > 0);
  SelectionStart := CursorAt;
  SelectionEnd := CursorAt;
  if HasSelection then
  begin
    SelectionStart := PositionOf(Lines, Block.StartingRow, Block.StartingColumn, TabWidth);
    SelectionEnd := PositionOf(Lines, Block.EndingRow, Block.EndingColumn, TabWidth);
  end;
  First := SelectionStart.Line;
  Last := SelectionEnd.Line;
  // Eine Markierung, die am Anfang einer Zeile endet, berührt diese Zeile nicht.
  if HasSelection and (Last > First) and (SelectionEnd.Character = 0) then
    Dec(Last);
  MethodLine := -1;
  if not HasSelection then
    MethodLine := CursorAt.Line;
  if not TAtlasLineMover.Compute(Text, First, Last, MethodLine, AKind, TAtlasEditorBuffer.BlockIndent(Buffer),
    Move) then
  begin
    if Move.Method and Assigned(FMessage) then
      FMessage(TAtlasStrings.Text(TAtlasTextId.MoveLinesNoNeighbour));
    Exit;
  end;
  NewLines := TAtlasLineMover.Apply(Lines, Move);
  NewText := string.Join(LineBreak, NewLines);
  // Direkt auf den vorigen Schritt: zurücknehmen und die ganze Folge als einen Schritt schreiben.
  Before := Text;
  Grouped := SameText(FFileName, Buffer.FileName) and (Text = FAfter) and (Cursor.Line = FCursorLine) and
    (Cursor.Col = FCursorColumn);
  if Grouped then
  begin
    if Buffer.Undo and (TAtlasEditorBuffer.Text(Buffer) = FBefore) then
      Before := FBefore
    else
    begin
      if TAtlasEditorBuffer.Text(Buffer) <> Text then
        Buffer.Redo;
      // Lässt sich der Stand nicht wiederherstellen, lieber nichts ändern.
      if TAtlasEditorBuffer.Text(Buffer) <> Text then
      begin
        FFileName := '';
        Exit;
      end;
    end;
  end;
  if TAtlasLineMover.Difference(Before, NewText, Start, OldLength, Insert) then
    WriteBuffer(Buffer, Before, Start, OldLength, Insert);
  // Cursor und Markierung mit dem Block.
  CursorAt := Mapped(Move, CursorAt, Last);
  if HasSelection then
  begin
    SelectionStart := Mapped(Move, SelectionStart, Last);
    SelectionEnd := Mapped(Move, SelectionEnd, Last);
    View.Block.Style := btNonInclusive;
    View.CursorPos := EditPos(NewLines, SelectionStart, TabWidth);
    View.Block.BeginBlock;
    View.CursorPos := EditPos(NewLines, SelectionEnd, TabWidth);
    View.Block.EndBlock;
  end
  else
    View.CursorPos := EditPos(NewLines, CursorAt, TabWidth);
  View.MoveViewToCursor;
  View.Paint;
  FFileName := Buffer.FileName;
  FBefore := Before;
  FAfter := TAtlasEditorBuffer.Text(Buffer);
  FCursorLine := View.CursorPos.Line;
  FCursorColumn := View.CursorPos.Col;
end;

end.
