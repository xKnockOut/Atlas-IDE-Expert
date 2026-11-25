unit Atlas.IDE.Foundation.Adapters.ActiveEditor;

// IAtlasActiveEditor über die Open Tools API: Datei und Schreibmarke der oberen Editoransicht (#1967).
// Dünner Adapter ohne eigene Entscheidung; die Spalte des Editors (Tabulatoren ausgedehnt) wird zum
// Zeichenindex wie beim Server. Erzeugt nur die Kompositionswurzel; die Features fragen TAtlasIdeHost.ActiveEditor.

interface

uses
  Atlas.Plugin.Files.Contract;

type
  TAtlasIdeActiveEditor = class(TInterfacedObject, IAtlasActiveEditor)
  public
    function Caret: TAtlasActiveEditorPos;
  end;

implementation

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Plugin.Lsp.Session.Json,
  Atlas.ToolsApi.Editor.Buffer;

{ TAtlasIdeActiveEditor }

function TAtlasIdeActiveEditor.Caret: TAtlasActiveEditorPos;
var
  mEditors: IOTAEditorServices;
  mView: IOTAEditView;
  mCursor: TOTAEditPos;
begin
  Result := TAtlasActiveEditorPos.None;
  if not Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    Exit;
  end;
  mView := mEditors.TopView;
  if (mView = nil) or (mView.Buffer = nil) then
  begin
    Exit;
  end;
  mCursor := mView.CursorPos;
  if mCursor.Line < 1 then
  begin
    Exit;
  end;
  Result := TAtlasActiveEditorPos.At(mView.Buffer.FileName, mCursor.Line - 1,
    TLspSessionJson.ColumnToIndex(TAtlasEditorBuffer.LineText(mView, mCursor.Line), mCursor.Col,
    TAtlasEditorBuffer.TabWidth(mView.Buffer)));
end;

end.
