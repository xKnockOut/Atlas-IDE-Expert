unit Atlas.IDE.Editor.BlockComment;

// Blockkommentar umschalten (#703) im Editor, Umschalt+Alt+A. Was sich
// ändert, berechnet Atlas.Core.Editor.BlockComment; hier bleiben Puffer,
// Cursor und Markierung.
// - Eine Änderung ist ein Schreiber der IDE (CreateUndoableWriter), also ein
//   Rückgängig-Schritt; geschrieben wird nur der geänderte Ausschnitt.
// - Die Markierung bleibt auf demselben Text, ohne Markierung wandert der
//   Cursor mit.
// - Lehnt Atlas ab (} und *) in der Markierung, Rückfall „refuse“), steht eine
//   Zeile in der Meldungsansicht.
// - keys.toggleBlockComment aus: Befehl und Kürzel fehlen.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Editor.BlockComment;

type
  TAtlasIdeBlockComment = class
  private class var
    FMessage: TProc<string>;
  public
    /// <summary>AMessage zeigt eine Zeile in der Meldungsansicht.</summary>
    class procedure Install(const AMessage: TProc<string>); static;
    class procedure Uninstall; static;
    /// <summary>keys.toggleBlockComment an (für Palette und Tastenkürzel)?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Optionen aus den Einstellungen.</summary>
    class function Options: TAtlasBlockCommentOptions; static;
    /// <summary>Schaltet im oberen Editor um.</summary>
    class procedure Run; static;
  end;

implementation

uses
  ToolsAPI,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Editor.LineMove,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot;

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

function PositionOf(const ALines: TArray<string>; ARow, AColumn, ATabWidth: Integer): TLspTextPosition;
var
  LineText: string;
begin
  LineText := '';
  if (ARow >= 1) and (ARow <= Length(ALines)) then
    LineText := ALines[ARow - 1];
  Result := TLspTextPosition.Create(ARow - 1, TLspSession.ColumnToIndex(LineText, AColumn, ATabWidth));
end;

{ TAtlasIdeBlockComment }

class procedure TAtlasIdeBlockComment.Install(const AMessage: TProc<string>);
begin
  FMessage := AMessage;
end;

class procedure TAtlasIdeBlockComment.Uninstall;
begin
  FMessage := nil;
end;

class function TAtlasIdeBlockComment.Enabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.ToggleBlockComment;
end;

class function TAtlasIdeBlockComment.Options: TAtlasBlockCommentOptions;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result.Style := TAtlasBlockComment.StyleOf(Settings.ToggleBlockCommentStyle);
  Result.Fallback := TAtlasBlockComment.FallbackOf(Settings.ToggleBlockCommentFallback);
  Result.OwnLines := Settings.ToggleBlockCommentOwnLines;
  Result.Scope := TAtlasBlockComment.ScopeOf(Settings.ToggleBlockCommentWithoutSelection);
end;

class procedure TAtlasIdeBlockComment.Run;
var
  View: IOTAEditView;
  Buffer: IOTAEditBuffer;
  Block: IOTAEditBlock;
  Cursor: TOTAEditPos;
  Text, NewText, LineBreak, Insert: string;
  Lines: TArray<string>;
  TabWidth, Start, OldLength: Integer;
  SelectionStart, SelectionEnd: TLspTextPosition;
  HasSelection: Boolean;
  Toggled: TAtlasBlockCommentResult;
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
  SelectionStart := PositionOf(Lines, Cursor.Line, Cursor.Col, TabWidth);
  SelectionEnd := SelectionStart;
  Block := View.Block;
  HasSelection := (Block <> nil) and Block.IsValid and (Block.Size > 0);
  if HasSelection then
  begin
    SelectionStart := PositionOf(Lines, Block.StartingRow, Block.StartingColumn, TabWidth);
    SelectionEnd := PositionOf(Lines, Block.EndingRow, Block.EndingColumn, TabWidth);
  end;
  Toggled := TAtlasBlockComment.Toggle(Lines, SelectionStart, SelectionEnd, Options);
  case Toggled.Kind of
    TAtlasBlockCommentKind.None:
      Exit;
    TAtlasBlockCommentKind.Refused:
      begin
        if Assigned(FMessage) then
          FMessage(TAtlasStrings.Text(TAtlasTextId.ToggleBlockCommentRefused));
        Exit;
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
  NewText := string.Join(LineBreak, Toggled.Lines);
  if TAtlasLineMover.Difference(Text, NewText, Start, OldLength, Insert) then
    WriteBuffer(Buffer, Text, Start, OldLength, Insert);
  // Markierung bzw. Cursor mit dem Text.
  if HasSelection then
  begin
    View.Block.Style := btNonInclusive;
    View.CursorPos := EditPos(Toggled.Lines, Toggled.SelectionStart, TabWidth);
    View.Block.BeginBlock;
    View.CursorPos := EditPos(Toggled.Lines, Toggled.SelectionEnd, TabWidth);
    View.Block.EndBlock;
  end
  else
    View.CursorPos := EditPos(Toggled.Lines, Toggled.SelectionStart, TabWidth);
  View.MoveViewToCursor;
  View.Paint;
end;

end.
