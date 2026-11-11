unit Atlas.IDE.Editor.CommentContinuation;

// Kommentar beim Enter fortsetzen (#696) im Editor. Was sich ändert, rechnet
// Atlas.Core.Editor.CommentContinuation aus; hier bleiben Puffer und Cursor.
// - Den Zeilenumbruch erkennt Atlas.IDE.Editor.EnterWatch, ohne Enter zu
//   binden; dieser Handler läuft dort als erster.
// - Atlas schreibt das Präfix als eigenen Schreiber (CreateUndoableWriter):
//   Strg+Z nimmt nur das Präfix zurück, der Zeilenumbruch bleibt.
// Nur im Hauptthread.

interface

uses
  ToolsAPI,
  Atlas.Core.Editor.CommentContinuation;

type
  TAtlasIdeCommentContinuation = class
  private
    /// <summary>True, wenn Atlas die neue Zeile fortgesetzt hat.</summary>
    class function Run(const AView: IOTAEditView): Boolean; static;
  public
    class procedure Install; static;
    class procedure Uninstall; static;
    /// <summary>editor.continueComments an (und Atlas an)?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Optionen aus den Einstellungen (auch für „Neue Zeile ober-/unterhalb“, #700).</summary>
    class function Options: TAtlasCommentOptions; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.LineMove,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Editor.EnterWatch;

const
  cHandlerName = 'CommentContinuation';

/// <summary>ALines mit den Zeilen von AEdit an Stelle der ersetzten.</summary>
function ReplacedLines(const ALines: TArray<string>; const AEdit: TAtlasCommentEdit): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(ALines) - AEdit.OldCount + Length(AEdit.Lines));
  for mIndex := 0 to AEdit.StartLine - 1 do
  begin
    Result[mIndex] := ALines[mIndex];
  end;
  for mIndex := 0 to High(AEdit.Lines) do
  begin
    Result[AEdit.StartLine + mIndex] := AEdit.Lines[mIndex];
  end;
  for mIndex := AEdit.StartLine + AEdit.OldCount to High(ALines) do
  begin
    Result[mIndex - AEdit.OldCount + Length(AEdit.Lines)] := ALines[mIndex];
  end;
end;

/// <summary>Schreibt nur den Unterschied von AText zu ANewText in den Puffer von AView.</summary>
procedure WriteLines(const AView: IOTAEditView; const AText, ANewText: string);
var
  mStart, mOldLength: Integer;
  mInsert: string;
begin
  if TAtlasLineMover.Difference(AText, ANewText, mStart, mOldLength, mInsert) then
  begin
    TAtlasEditorSnapshots.ReplaceText(AView.Buffer, AText, mStart, mOldLength, mInsert);
  end;
end;

class function TAtlasIdeCommentContinuation.Options: TAtlasCommentOptions;
begin
  Result := TAtlasCommentOptions.Defaults;
  Result.LineComments := TAtlasIdeSettings.Current.ContinueCommentsLineComments;
  Result.Lists := TAtlasIdeSettings.Current.ContinueCommentsLists;
  Result.BlockPrefix := TAtlasIdeSettings.Current.ContinueCommentsBlockPrefix;
end;

{ TAtlasIdeCommentContinuation }

class procedure TAtlasIdeCommentContinuation.Install;
begin
  TAtlasEnterWatch.Add(cHandlerName,
    function: Boolean
    begin
      Result := Enabled;
    end,
    function(const AView: IOTAEditView): Boolean
    begin
      Result := Run(AView);
    end);
end;

class procedure TAtlasIdeCommentContinuation.Uninstall;
begin
  TAtlasEnterWatch.Remove(cHandlerName);
end;

class function TAtlasIdeCommentContinuation.Enabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Enabled and TAtlasIdeSettings.Current.ContinueComments;
end;

class function TAtlasIdeCommentContinuation.Run(const AView: IOTAEditView): Boolean;
var
  mBuffer: IOTAEditBuffer;
  mText, mLineBreak: string;
  mLines, mNewLines: TArray<string>;
  mCursor, mTarget: TOTAEditPos;
  mTabWidth, mLine, mCharacter: Integer;
  mEdit: TAtlasCommentEdit;
begin
  Result := False;
  if not Enabled or (AView = nil) or (AView.Buffer = nil) then
  begin
    Exit;
  end;
  mBuffer := AView.Buffer;
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
  mCursor := AView.CursorPos;
  mLine := mCursor.Line - 1;
  if (mLine < 1) or (mLine > High(mLines)) then
  begin
    Exit;
  end;
  mCharacter := TLspSession.ColumnToIndex(mLines[mLine], mCursor.Col, mTabWidth);
  if not TAtlasCommentContinuation.OnEnter(mText, mLine, mCharacter, Options, mEdit) then
  begin
    Exit;
  end;
  mNewLines := ReplacedLines(mLines, mEdit);
  WriteLines(AView, mText, string.Join(mLineBreak, mNewLines));
  mTarget.Line := mEdit.CursorLine + 1;
  mTarget.Col := TLspSession.IndexToColumn(mNewLines[mEdit.CursorLine], mEdit.CursorCharacter, mTabWidth);
  AView.CursorPos := mTarget;
  AView.MoveViewToCursor;
  AView.Paint;
  Result := True;
end;

end.
