unit Atlas.IDE.Editor.NewLine;

// Neue Zeile ober- oder unterhalb (#700) im Editor: Umschalt+Enter darunter,
// Strg+Alt+Enter darüber, ohne die Cursorzeile zu teilen. Zeile und Einzug
// berechnet Atlas.Core.Editor.NewLine; hier bleiben Puffer und Cursor.
// - Eine Änderung ist ein Schreiber der IDE (CreateUndoableWriter), also ein
//   Rückgängig-Schritt; die Cursorzeile bleibt Byte für Byte gleich.
// - Einzugsebene: Blockeinzug der IDE. Kommentare setzt Atlas fort, solange
//   editor.continueComments (#696) an ist, mit dessen Optionen.
// - keys.newLineAround aus: Befehle und Kürzel fehlen, die Tasten gehören der
//   IDE.
// Nur im Hauptthread.

interface

uses
  Atlas.Core.Editor.NewLine;

type
  TAtlasIdeNewLine = class
  public
    /// <summary>keys.newLineAround an (für Palette und Tastenkürzel)?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Optionen aus den Einstellungen; AIndentWidth ist der Blockeinzug der IDE.</summary>
    class function Options(AIndentWidth: Integer): TAtlasNewLineOptions; static;
    /// <summary>Fügt im oberen Editor unter bzw. über der Cursorzeile eine Zeile ein.</summary>
    class procedure Run(ADirection: TAtlasNewLineDirection); static;
  end;

implementation

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.LineMove,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Editor.CommentContinuation;

function EditPos(const ALines: TArray<string>; const APosition: TLspTextPosition; ATabWidth: Integer): TOTAEditPos;
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

{ TAtlasIdeNewLine }

class function TAtlasIdeNewLine.Enabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.NewLineAround;
end;

class function TAtlasIdeNewLine.Options(AIndentWidth: Integer): TAtlasNewLineOptions;
begin
  Result := TAtlasNewLineOptions.Defaults;
  Result.IndentWidth := AIndentWidth;
  Result.StatementAware := TAtlasIdeSettings.Current.NewLineAroundStatementAware;
  Result.ContinueComments := TAtlasIdeCommentContinuation.Enabled;
  Result.Comments := TAtlasIdeCommentContinuation.Options;
end;

class procedure TAtlasIdeNewLine.Run(ADirection: TAtlasNewLineDirection);
var
  mView: IOTAEditView;
  mBuffer: IOTAEditBuffer;
  mText, mNewText, mLineBreak, mInsert: string;
  mLines: TArray<string>;
  mTabWidth, mStart, mOldLength: Integer;
  mDone: TAtlasNewLineResult;
begin
  if not Enabled then
  begin
    Exit;
  end;
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView = nil) or (mView.Buffer = nil) then
  begin
    Exit;
  end;
  mBuffer := mView.Buffer;
  if mBuffer.IsReadOnly then
  begin
    Exit;
  end;
  mText := TAtlasEditorBuffer.Text(mBuffer);
  mLineBreak := #10;
  if Pos(#13#10, mText) > 0 then
  begin
    mLineBreak := #13#10;
  end;
  mLines := mText.Split([#13#10, #10]);
  mTabWidth := TAtlasEditorBuffer.TabWidth(mBuffer);
  mDone := TAtlasNewLine.Insert(mLines, mView.CursorPos.Line - 1, ADirection,
    Options(TAtlasEditorBuffer.BlockIndent(mBuffer)));
  mNewText := string.Join(mLineBreak, mDone.Lines);
  if TAtlasLineMover.Difference(mText, mNewText, mStart, mOldLength, mInsert) then
  begin
    TAtlasEditorSnapshots.ReplaceText(mBuffer, mText, mStart, mOldLength, mInsert);
  end;
  mView.CursorPos := EditPos(mDone.Lines, mDone.Cursor, mTabWidth);
  mView.MoveViewToCursor;
  mView.Paint;
end;

end.
