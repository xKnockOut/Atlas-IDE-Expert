unit Atlas.IDE.Debug.CursorExpression;

// Ausdruck unter dem Cursor des obersten Editors für das Fenster „Auswerten“
// (Strg+F7, #784): eine einzeilige Markierung, sonst der Ausdruck an der
// Schreibmarke (TAtlasEvalText.ExpressionAt). Nur im Hauptthread verwenden.

interface

type
  TAtlasIdeDebugCursorExpression = class
  public
    /// <summary>Markierung bzw. Ausdruck unter dem Cursor; '' ohne Editor.</summary>
    class function Current: string; static;
  end;

implementation

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Debug.Evaluate,
  Atlas.ToolsApi.Editor.Buffer;

{ TAtlasIdeDebugCursorExpression }

class function TAtlasIdeDebugCursorExpression.Current: string;
var
  mView: IOTAEditView;
  mBlock: IOTAEditBlock;
  mCursor: TOTAEditPos;
  mLine: string;
begin
  Result := '';
  mView := TAtlasEditorBuffer.ActiveView;
  if mView = nil then
  begin
    Exit;
  end;
  mBlock := mView.Block;
  if (mBlock <> nil) and mBlock.IsValid and (mBlock.Size > 0) and (mBlock.StartingRow = mBlock.EndingRow) then
  begin
    Result := Trim(mBlock.Text);
    if Result <> '' then
    begin
      Exit;
    end;
  end;
  mCursor := mView.CursorPos;
  mLine := TAtlasEditorBuffer.LineText(mView, mCursor.Line);
  Result := TAtlasEvalText.ExpressionAt(mLine, TLspSession.ColumnToIndex(mLine, mCursor.Col,
    TAtlasEditorBuffer.TabWidth(mView.Buffer)));
end;

end.
