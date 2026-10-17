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
  ToolsAPI;

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
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.LineMove,
  Atlas.Core.Editor.CommentContinuation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Editor.EnterWatch;

const
  HandlerName = 'CommentContinuation';

/// <summary>Ersetzt in ABuffer (Text AText) ab Zeichen AStart AOldLength Zeichen durch AInsert; ein eigener
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

function Options: TAtlasCommentOptions;
begin
  Result := TAtlasCommentOptions.Defaults;
  Result.LineComments := TAtlasIdeSettings.Current.ContinueCommentsLineComments;
  Result.Lists := TAtlasIdeSettings.Current.ContinueCommentsLists;
  Result.BlockPrefix := TAtlasIdeSettings.Current.ContinueCommentsBlockPrefix;
end;

{ TAtlasIdeCommentContinuation }

class procedure TAtlasIdeCommentContinuation.Install;
begin
  TAtlasEnterWatch.Add(HandlerName,
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
  TAtlasEnterWatch.Remove(HandlerName);
end;

class function TAtlasIdeCommentContinuation.Enabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Enabled and TAtlasIdeSettings.Current.ContinueComments;
end;

class function TAtlasIdeCommentContinuation.Run(const AView: IOTAEditView): Boolean;
var
  Buffer: IOTAEditBuffer;
  Text, LineBreak, NewText, Insert, LineText: string;
  Lines, NewLines: TArray<string>;
  Cursor, Target: TOTAEditPos;
  TabWidth, Line, Character, Start, OldLength, Index: Integer;
  Edit: TAtlasCommentEdit;
begin
  Result := False;
  if not Enabled or (AView = nil) or (AView.Buffer = nil) then
    Exit;
  Buffer := AView.Buffer;
  if Buffer.IsReadOnly then
    Exit;
  Text := TAtlasEditorBuffer.Text(Buffer);
  LineBreak := #10;
  if Pos(#13#10, Text) > 0 then
    LineBreak := #13#10;
  Lines := Text.Split([#13#10, #10]);
  TabWidth := TAtlasEditorBuffer.TabWidth(Buffer);
  Cursor := AView.CursorPos;
  Line := Cursor.Line - 1;
  if (Line < 1) or (Line > High(Lines)) then
    Exit;
  Character := TLspSession.ColumnToIndex(Lines[Line], Cursor.Col, TabWidth);
  if not TAtlasCommentContinuation.OnEnter(Text, Line, Character, Options, Edit) then
    Exit;
  SetLength(NewLines, Length(Lines) - Edit.OldCount + Length(Edit.Lines));
  for Index := 0 to Edit.StartLine - 1 do
    NewLines[Index] := Lines[Index];
  for Index := 0 to High(Edit.Lines) do
    NewLines[Edit.StartLine + Index] := Edit.Lines[Index];
  for Index := Edit.StartLine + Edit.OldCount to High(Lines) do
    NewLines[Index - Edit.OldCount + Length(Edit.Lines)] := Lines[Index];
  NewText := string.Join(LineBreak, NewLines);
  if TAtlasLineMover.Difference(Text, NewText, Start, OldLength, Insert) then
    WriteBuffer(Buffer, Text, Start, OldLength, Insert);
  LineText := NewLines[Edit.CursorLine];
  Target.Line := Edit.CursorLine + 1;
  Target.Col := TLspSession.IndexToColumn(LineText, Edit.CursorCharacter, TabWidth);
  AView.CursorPos := Target;
  AView.MoveViewToCursor;
  AView.Paint;
  Result := True;
end;

end.
