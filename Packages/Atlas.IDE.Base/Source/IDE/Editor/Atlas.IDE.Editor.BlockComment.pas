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
  begin
    Writer.Insert(PAnsiChar(UTF8Encode(AInsert)));
  end;
  Writer := nil;
  TAtlasEditorSnapshots.Invalidate(ABuffer.FileName);
end;

function EditPos(const ALines: TArray<string>; const APosition: TLspTextPosition; ATabWidth: Integer): TOTAEditPos;
var
  LineText: string;
begin
  LineText := '';
  if (APosition.Line >= 0) and (APosition.Line < Length(ALines)) then
  begin
    LineText := ALines[APosition.Line];
  end;
  Result.Line := APosition.Line + 1;
  Result.Col := TLspSession.IndexToColumn(LineText, APosition.Character, ATabWidth);
end;

function PositionOf(const ALines: TArray<string>; ARow, AColumn, ATabWidth: Integer): TLspTextPosition;
var
  LineText: string;
begin
  LineText := '';
  if (ARow >= 1) and (ARow <= Length(ALines)) then
  begin
    LineText := ALines[ARow - 1];
  end;
  Result := TLspTextPosition.Create(ARow - 1, TLspSession.ColumnToIndex(LineText, AColumn, ATabWidth));
end;

type
  // Text und Markierung des oberen Editors vor dem Umschalten.
  TBlockCommentSource = record
    View: IOTAEditView;
    Text: string;
    LineBreak: string;
    Lines: TArray<string>;
    TabWidth: Integer;
    SelectionStart: TLspTextPosition;
    SelectionEnd: TLspTextPosition;
    HasSelection: Boolean;
  end;

/// <summary>AView hat einen beschreibbaren Puffer.</summary>
function Writable(const AView: IOTAEditView): Boolean;
begin
  Result := (AView <> nil) and (AView.Buffer <> nil) and not AView.Buffer.IsReadOnly;
end;

/// <summary>Text, Zeilen und Markierung (ohne Markierung der Cursor) aus AView.</summary>
function ReadSource(const AView: IOTAEditView): TBlockCommentSource;
var
  mCursor: TOTAEditPos;
  mBlock: IOTAEditBlock;
begin
  Result.View := AView;
  Result.Text := TAtlasEditorBuffer.Text(AView.Buffer);
  Result.LineBreak := #10;
  if Pos(#13#10, Result.Text) > 0 then
  begin
    Result.LineBreak := #13#10;
  end;
  Result.Lines := Result.Text.Split([#13#10, #10]);
  Result.TabWidth := TAtlasEditorBuffer.TabWidth(AView.Buffer);
  mCursor := AView.CursorPos;
  Result.SelectionStart := PositionOf(Result.Lines, mCursor.Line, mCursor.Col, Result.TabWidth);
  Result.SelectionEnd := Result.SelectionStart;
  mBlock := AView.Block;
  Result.HasSelection := (mBlock <> nil) and mBlock.IsValid and (mBlock.Size > 0);
  if Result.HasSelection then
  begin
    Result.SelectionStart := PositionOf(Result.Lines, mBlock.StartingRow, mBlock.StartingColumn, Result.TabWidth);
    Result.SelectionEnd := PositionOf(Result.Lines, mBlock.EndingRow, mBlock.EndingColumn, Result.TabWidth);
  end;
end;

/// <summary>Schreibt AToggled in den Puffer von ASource; Markierung bzw. Cursor wandern mit dem Text.</summary>
procedure WriteToggled(const ASource: TBlockCommentSource; const AToggled: TAtlasBlockCommentResult);
var
  mView: IOTAEditView;
  mStart, mOldLength: Integer;
  mInsert: string;
begin
  mView := ASource.View;
  if TAtlasLineMover.Difference(ASource.Text, string.Join(ASource.LineBreak, AToggled.Lines), mStart, mOldLength,
    mInsert) then
  begin
    WriteBuffer(mView.Buffer, ASource.Text, mStart, mOldLength, mInsert);
  end;
  if ASource.HasSelection then
  begin
    mView.Block.Style := btNonInclusive;
    mView.CursorPos := EditPos(AToggled.Lines, AToggled.SelectionStart, ASource.TabWidth);
    mView.Block.BeginBlock;
    mView.CursorPos := EditPos(AToggled.Lines, AToggled.SelectionEnd, ASource.TabWidth);
    mView.Block.EndBlock;
  end
  else
  begin
    mView.CursorPos := EditPos(AToggled.Lines, AToggled.SelectionStart, ASource.TabWidth);
  end;
  mView.MoveViewToCursor;
  mView.Paint;
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
  mView: IOTAEditView;
  mSource: TBlockCommentSource;
  mToggled: TAtlasBlockCommentResult;
begin
  if not Enabled then
  begin
    Exit;
  end;
  mView := TAtlasEditorBuffer.ActiveView;
  if not Writable(mView) then
  begin
    Exit;
  end;
  mSource := ReadSource(mView);
  mToggled := TAtlasBlockComment.Toggle(mSource.Lines, mSource.SelectionStart, mSource.SelectionEnd, Options);
  if mToggled.Kind = TAtlasBlockCommentKind.Refused then
  begin
    if Assigned(FMessage) then
    begin
      FMessage(TAtlasStrings.Text(TAtlasTextId.ToggleBlockCommentRefused));
    end;
  end
  else if mToggled.Kind <> TAtlasBlockCommentKind.None then
  begin
    WriteToggled(mSource, mToggled);
  end;
end;

end.
