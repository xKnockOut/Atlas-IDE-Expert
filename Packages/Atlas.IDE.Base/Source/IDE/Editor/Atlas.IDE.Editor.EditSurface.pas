unit Atlas.IDE.Editor.EditSurface;

// IAtlasEditSurface über eine Ansicht der IDE (IOTAEditView und ihr
// IOTAEditBuffer): Text und Cursor lesen, Cursor setzen, Ersetzungen mit
// einem Schreiber (ein Rückgängig-Schritt) schreiben, Rückgängig und
// Wiederholen des Puffers. Zeichen werden mit der Tabulatorweite des Puffers
// in Spalten der IDE umgerechnet. Nur im Hauptthread.

interface

uses
  ToolsAPI,
  Atlas.Core.Editor.EditSurface;

type
  TAtlasIdeEditSurface = class(TInterfacedObject, IAtlasEditSurface)
  private
    FView: IOTAEditView;
  public
    constructor Create(const AView: IOTAEditView);
    /// <summary>Puffer der Ansicht AView; nil ohne Ansicht oder Puffer.</summary>
    class function Wrap(const AView: IOTAEditView): IAtlasEditSurface; static;
    function FileName: string;
    function IsReadOnly: Boolean;
    function Text: string;
    function LineText(ALine: Integer): string;
    function HasSelection: Boolean;
    procedure ReadCaret(out ALine, ACharacter: Integer);
    procedure WriteCaret(ALine, ACharacter: Integer);
    procedure Write(const ABase: string; const AEdits: TAtlasTextEdits);
    function Undo: Boolean;
    function Redo: Boolean;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Atlas.Core.Lsp.Session,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot;

{ TAtlasIdeEditSurface }

constructor TAtlasIdeEditSurface.Create(const AView: IOTAEditView);
begin
  inherited Create;
  FView := AView;
end;

class function TAtlasIdeEditSurface.Wrap(const AView: IOTAEditView): IAtlasEditSurface;
begin
  Result := nil;
  if (AView <> nil) and (AView.Buffer <> nil) then
  begin
    Result := TAtlasIdeEditSurface.Create(AView);
  end;
end;

function TAtlasIdeEditSurface.FileName: string;
begin
  Result := FView.Buffer.FileName;
end;

function TAtlasIdeEditSurface.IsReadOnly: Boolean;
begin
  Result := FView.Buffer.IsReadOnly;
end;

function TAtlasIdeEditSurface.Text: string;
begin
  Result := TAtlasEditorBuffer.Text(FView.Buffer);
end;

function TAtlasIdeEditSurface.LineText(ALine: Integer): string;
begin
  Result := TAtlasEditorBuffer.LineText(FView, ALine + 1);
end;

function TAtlasIdeEditSurface.HasSelection: Boolean;
var
  mBlock: IOTAEditBlock;
begin
  mBlock := FView.Block;
  Result := (mBlock <> nil) and mBlock.IsValid and (mBlock.Size > 0);
end;

procedure TAtlasIdeEditSurface.ReadCaret(out ALine, ACharacter: Integer);
var
  mCursor: TOTAEditPos;
  mLineText: string;
begin
  mCursor := FView.CursorPos;
  ALine := Max(0, mCursor.Line - 1);
  mLineText := LineText(ALine);
  ACharacter := Min(TLspSession.ColumnToIndex(mLineText, mCursor.Col, TAtlasEditorBuffer.TabWidth(FView.Buffer)),
    Length(mLineText));
end;

procedure TAtlasIdeEditSurface.WriteCaret(ALine, ACharacter: Integer);
var
  mPosition: TOTAEditPos;
begin
  FView.Block.Reset;
  mPosition.Line := ALine + 1;
  mPosition.Col := TLspSession.IndexToColumn(LineText(ALine), ACharacter, TAtlasEditorBuffer.TabWidth(FView.Buffer));
  FView.CursorPos := mPosition;
  FView.MoveViewToCursor;
  FView.Paint;
end;

procedure TAtlasIdeEditSurface.Write(const ABase: string; const AEdits: TAtlasTextEdits);
var
  mWriter: IOTAEditWriter;
  mEdit: TAtlasTextEdit;
  mUtf8: UTF8String;
begin
  // Ein Schreiber: ein Rückgängig-Schritt; der Text zwischen den Ersetzungen bleibt unberührt.
  mWriter := FView.Buffer.CreateUndoableWriter;
  for mEdit in AEdits do
  begin
    mWriter.CopyTo(TEncoding.UTF8.GetByteCount(Copy(ABase, 1, mEdit.Start)));
    mWriter.DeleteTo(TEncoding.UTF8.GetByteCount(Copy(ABase, 1, mEdit.Start + mEdit.Count)));
    if mEdit.Insert <> '' then
    begin
      mUtf8 := UTF8Encode(mEdit.Insert);
      mWriter.Insert(PAnsiChar(mUtf8));
    end;
  end;
  mWriter := nil;
  TAtlasEditorSnapshots.Invalidate(FView.Buffer.FileName);
end;

function TAtlasIdeEditSurface.Undo: Boolean;
begin
  Result := FView.Buffer.Undo;
end;

function TAtlasIdeEditSurface.Redo: Boolean;
begin
  Result := FView.Buffer.Redo;
end;

end.
