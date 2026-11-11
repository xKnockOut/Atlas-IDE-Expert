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

function EditPos(const ALines: TArray<string>; const APosition: TPosition; ATabWidth: Integer): TOTAEditPos;
var
  mLineText: string;
begin
  mLineText := '';
  if (APosition.Line >= 0) and (APosition.Line < Length(ALines)) then
  begin
    mLineText := ALines[APosition.Line];
  end;
  Result.Line := APosition.Line + 1;
  Result.Col := TLspSession.IndexToColumn(mLineText, APosition.Character, ATabWidth);
end;

function PositionOf(const ALines: TArray<string>; ARow, AColumn, ATabWidth: Integer): TPosition;
var
  mLineText: string;
begin
  mLineText := '';
  if (ARow >= 1) and (ARow <= Length(ALines)) then
  begin
    mLineText := ALines[ARow - 1];
  end;
  Result.Line := ARow - 1;
  Result.Character := TLspSession.ColumnToIndex(mLineText, AColumn, ATabWidth);
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

type
  /// <summary>Stand im Editor beim Tastendruck: Text, Cursor, Markierung und die berührten Zeilen.</summary>
  TMoveState = record
    Text: string;
    LineBreak: string;
    Lines: TArray<string>;
    TabWidth: Integer;
    Cursor: TOTAEditPos;
    CursorAt: TPosition;
    SelectionStart: TPosition;
    SelectionEnd: TPosition;
    HasSelection: Boolean;
    First: Integer;
    Last: Integer;
    /// <summary>Zeile der Methode, die ohne Markierung ganz wandert; -1 mit Markierung.</summary>
    MethodLine: Integer;
  end;

function ReadState(const AView: IOTAEditView): TMoveState;
var
  mBlock: IOTAEditBlock;
begin
  Result.Text := TAtlasEditorBuffer.Text(AView.Buffer);
  Result.LineBreak := #10;
  if Pos(#13#10, Result.Text) > 0 then
  begin
    Result.LineBreak := #13#10;
  end;
  Result.Lines := Result.Text.Split([#13#10, #10]);
  Result.TabWidth := TAtlasEditorBuffer.TabWidth(AView.Buffer);
  Result.Cursor := AView.CursorPos;
  Result.CursorAt := PositionOf(Result.Lines, Result.Cursor.Line, Result.Cursor.Col, Result.TabWidth);
  mBlock := AView.Block;
  Result.HasSelection := (mBlock <> nil) and mBlock.IsValid and (mBlock.Size > 0);
  Result.SelectionStart := Result.CursorAt;
  Result.SelectionEnd := Result.CursorAt;
  Result.MethodLine := Result.CursorAt.Line;
  if Result.HasSelection then
  begin
    Result.SelectionStart := PositionOf(Result.Lines, mBlock.StartingRow, mBlock.StartingColumn, Result.TabWidth);
    Result.SelectionEnd := PositionOf(Result.Lines, mBlock.EndingRow, mBlock.EndingColumn, Result.TabWidth);
    Result.MethodLine := -1;
  end;
  Result.First := Result.SelectionStart.Line;
  Result.Last := Result.SelectionEnd.Line;
  // Eine Markierung, die am Anfang einer Zeile endet, berührt diese Zeile nicht.
  if Result.HasSelection and (Result.Last > Result.First) and (Result.SelectionEnd.Character = 0) then
  begin
    Dec(Result.Last);
  end;
end;

/// <summary>Text, auf den der Schritt geschrieben wird. Direkt auf den vorigen Schritt: diesen zurücknehmen, damit
/// die ganze Folge ein Schritt wird. False, wenn sich der Stand danach nicht wiederherstellen lässt.</summary>
function Rewind(const ABuffer: IOTAEditBuffer; const AState: TMoveState; out ABefore: string): Boolean;
begin
  ABefore := AState.Text;
  Result := True;
  if not SameText(TAtlasIdeLineMove.FFileName, ABuffer.FileName) or (AState.Text <> TAtlasIdeLineMove.FAfter) or
    (AState.Cursor.Line <> TAtlasIdeLineMove.FCursorLine) or
    (AState.Cursor.Col <> TAtlasIdeLineMove.FCursorColumn) then
  begin
    Exit;
  end;
  if ABuffer.Undo and (TAtlasEditorBuffer.Text(ABuffer) = TAtlasIdeLineMove.FBefore) then
  begin
    ABefore := TAtlasIdeLineMove.FBefore;
    Exit;
  end;
  if TAtlasEditorBuffer.Text(ABuffer) <> AState.Text then
  begin
    ABuffer.Redo;
  end;
  // Lässt sich der Stand nicht wiederherstellen, lieber nichts ändern.
  Result := TAtlasEditorBuffer.Text(ABuffer) = AState.Text;
end;

/// <summary>Cursor und Markierung wandern mit dem Block.</summary>
procedure PlaceCursor(const AView: IOTAEditView; const AMove: TAtlasLineMove; const ANewLines: TArray<string>;
  const AState: TMoveState);
begin
  if not AState.HasSelection then
  begin
    AView.CursorPos := EditPos(ANewLines, Mapped(AMove, AState.CursorAt, AState.Last), AState.TabWidth);
    Exit;
  end;
  AView.Block.Style := btNonInclusive;
  AView.CursorPos := EditPos(ANewLines, Mapped(AMove, AState.SelectionStart, AState.Last), AState.TabWidth);
  AView.Block.BeginBlock;
  AView.CursorPos := EditPos(ANewLines, Mapped(AMove, AState.SelectionEnd, AState.Last), AState.TabWidth);
  AView.Block.EndBlock;
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
  mView: IOTAEditView;
  mState: TMoveState;
  mBefore, mInsert: string;
  mNewLines: TArray<string>;
  mStart, mOldLength: Integer;
  mMove: TAtlasLineMove;
begin
  mView := TAtlasEditorBuffer.ActiveView;
  if not Enabled or (mView = nil) or (mView.Buffer = nil) or mView.Buffer.IsReadOnly then
  begin
    Exit;
  end;
  mState := ReadState(mView);
  if not TAtlasLineMover.Compute(mState.Text, TAtlasLineSelection.Create(mState.First, mState.Last,
    mState.MethodLine), AKind, TAtlasEditorBuffer.BlockIndent(mView.Buffer), mMove) then
  begin
    if mMove.Method and Assigned(FMessage) then
    begin
      FMessage(TAtlasStrings.Text(TAtlasTextId.MoveLinesNoNeighbour));
    end;
    Exit;
  end;
  mNewLines := TAtlasLineMover.Apply(mState.Lines, mMove);
  if not Rewind(mView.Buffer, mState, mBefore) then
  begin
    FFileName := '';
    Exit;
  end;
  if TAtlasLineMover.Difference(mBefore, string.Join(mState.LineBreak, mNewLines), mStart, mOldLength, mInsert) then
  begin
    TAtlasEditorSnapshots.ReplaceText(mView.Buffer, mBefore, mStart, mOldLength, mInsert);
  end;
  PlaceCursor(mView, mMove, mNewLines, mState);
  mView.MoveViewToCursor;
  mView.Paint;
  FFileName := mView.Buffer.FileName;
  FBefore := mBefore;
  FAfter := TAtlasEditorBuffer.Text(mView.Buffer);
  FCursorLine := mView.CursorPos.Line;
  FCursorColumn := mView.CursorPos.Col;
end;

end.
