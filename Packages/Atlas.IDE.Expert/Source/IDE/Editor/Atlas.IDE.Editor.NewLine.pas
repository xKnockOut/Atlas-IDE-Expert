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

function EditPos(const ALines: TArray<string>; const APosition: TLspTextPosition; ATabWidth: Integer): TOTAEditPos;
var
  LineText: string;
begin
  LineText := '';
  if (APosition.Line >= 0) and (APosition.Line < Length(ALines)) then
    LineText := ALines[APosition.Line];
  Result.Line := APosition.Line + 1;
  Result.Col := TLspSession.IndexToColumn(LineText, APosition.Character, ATabWidth);
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
  View: IOTAEditView;
  Buffer: IOTAEditBuffer;
  Text, NewText, LineBreak, Insert: string;
  Lines: TArray<string>;
  TabWidth, Start, OldLength: Integer;
  Done: TAtlasNewLineResult;
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
  Done := TAtlasNewLine.Insert(Lines, View.CursorPos.Line - 1, ADirection,
    Options(TAtlasEditorBuffer.BlockIndent(Buffer)));
  NewText := string.Join(LineBreak, Done.Lines);
  if TAtlasLineMover.Difference(Text, NewText, Start, OldLength, Insert) then
    WriteBuffer(Buffer, Text, Start, OldLength, Insert);
  View.CursorPos := EditPos(Done.Lines, Done.Cursor, TabWidth);
  View.MoveViewToCursor;
  View.Paint;
end;

end.
