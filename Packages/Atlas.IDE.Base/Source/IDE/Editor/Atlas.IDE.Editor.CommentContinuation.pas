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
  begin
    Writer.Insert(PAnsiChar(UTF8Encode(AInsert)));
  end;
  Writer := nil;
  TAtlasEditorSnapshots.Invalidate(ABuffer.FileName);
end;

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
    WriteBuffer(AView.Buffer, AText, mStart, mOldLength, mInsert);
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
  Text, LineBreak: string;
  Lines, NewLines: TArray<string>;
  Cursor, Target: TOTAEditPos;
  TabWidth, Line, Character: Integer;
  Edit: TAtlasCommentEdit;
begin
  Result := False;
  if not Enabled or (AView = nil) or (AView.Buffer = nil) then
  begin
    Exit;
  end;
  Buffer := AView.Buffer;
  if Buffer.IsReadOnly then
  begin
    Exit;
  end;
  Text := TAtlasEditorBuffer.Text(Buffer);
  LineBreak := #10;
  if Pos(#13#10, Text) > 0 then
  begin
    LineBreak := #13#10;
  end;
  Lines := Text.Split([#13#10, #10]);
  TabWidth := TAtlasEditorBuffer.TabWidth(Buffer);
  Cursor := AView.CursorPos;
  Line := Cursor.Line - 1;
  if (Line < 1) or (Line > High(Lines)) then
  begin
    Exit;
  end;
  Character := TLspSession.ColumnToIndex(Lines[Line], Cursor.Col, TabWidth);
  if not TAtlasCommentContinuation.OnEnter(Text, Line, Character, Options, Edit) then
  begin
    Exit;
  end;
  NewLines := ReplacedLines(Lines, Edit);
  WriteLines(AView, Text, string.Join(LineBreak, NewLines));
  Target.Line := Edit.CursorLine + 1;
  Target.Col := TLspSession.IndexToColumn(NewLines[Edit.CursorLine], Edit.CursorCharacter, TabWidth);
  AView.CursorPos := Target;
  AView.MoveViewToCursor;
  AView.Paint;
  Result := True;
end;

end.
