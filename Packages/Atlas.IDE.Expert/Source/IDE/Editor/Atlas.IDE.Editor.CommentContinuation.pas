unit Atlas.IDE.Editor.CommentContinuation;

// Kommentar beim Enter fortsetzen (#696) im Editor. Was sich ändert, rechnet
// Atlas.Core.Editor.CommentContinuation aus; hier bleiben Erkennen, Puffer und
// Cursor.
// - Atlas bindet Enter nicht (die Taste gehört der IDE: Vervollständigung,
//   Vorlagen, Einzug). Application.OnMessage sieht das WM_KEYDOWN, bevor die
//   IDE es verarbeitet, lässt es durch und merkt sich Datei und Zeilenzahl.
//   Kommt die nächste Änderung derselben Datei kurz danach mit genau einer
//   Zeile mehr und steht der Cursor am Zeilenanfang (davor nur Leerraum), war
//   es ein Zeilenumbruch. Einfügen aus der Zwischenablage zählt so nicht.
// - Danach (in die Warteschlange des Hauptthreads, nie im Notifier) schreibt
//   Atlas das Präfix als eigenen Schreiber (CreateUndoableWriter): Strg+Z nimmt
//   nur das Präfix zurück, der Zeilenumbruch bleibt.
// Nur im Hauptthread.

interface

uses
  Winapi.Windows,
  Vcl.AppEvnts,
  ToolsAPI;

type
  TAtlasIdeCommentContinuation = class
  private const
    /// <summary>So lange nach dem Tastendruck gilt eine Änderung als sein Zeilenumbruch.</summary>
    PendingMs = 1000;
  private class var
    FInstance: TAtlasIdeCommentContinuation;
  private
    FEvents: TApplicationEvents;
    FPendingFile: string;
    FPendingLines: Integer;
    FPendingAt: UInt64;
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
    class procedure Run(const AView: IOTAEditView); static;
  public
    constructor Create;
    destructor Destroy; override;
    class procedure Install; static;
    class procedure Uninstall; static;
    /// <summary>editor.continueComments an (und Atlas an)?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Aus EditorViewModified: war die Änderung ein Enter, wird das Präfix eingereiht.</summary>
    class procedure EditorModified(const AView: IOTAEditView); static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Winapi.Messages,
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.LineMove,
  Atlas.Core.Editor.CommentContinuation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot;

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

constructor TAtlasIdeCommentContinuation.Create;
begin
  inherited Create;
  FEvents := TApplicationEvents.Create(nil);
  FEvents.OnMessage := AppMessage;
end;

destructor TAtlasIdeCommentContinuation.Destroy;
begin
  // Erst abmelden, dann freigeben (#493).
  FreeAndNil(FEvents);
  inherited;
end;

class procedure TAtlasIdeCommentContinuation.Install;
begin
  if FInstance = nil then
    FInstance := TAtlasIdeCommentContinuation.Create;
end;

class procedure TAtlasIdeCommentContinuation.Uninstall;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeCommentContinuation.Enabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Enabled and TAtlasIdeSettings.Current.ContinueComments;
end;

procedure TAtlasIdeCommentContinuation.AppMessage(var Msg: TMsg; var Handled: Boolean);
var
  View: IOTAEditView;
begin
  if (Msg.message <> WM_KEYDOWN) or (Msg.wParam <> VK_RETURN) then
    Exit;
  try
    FPendingFile := '';
    // Strg+Enter und Alt+Enter sind Befehle, kein Zeilenumbruch; nur im Editor selbst.
    if not Enabled or (GetKeyState(VK_CONTROL) < 0) or (GetKeyState(VK_MENU) < 0) or
      (Screen.ActiveControl = nil) or not Screen.ActiveControl.ClassNameIs('TEditControl') then
      Exit;
    View := TAtlasEditorBuffer.ActiveView;
    if (View = nil) or (View.Buffer = nil) then
      Exit;
    FPendingFile := View.Buffer.FileName;
    FPendingLines := View.Buffer.GetLinesInBuffer;
    FPendingAt := TThread.GetTickCount64;
  except
    // Die Taste geht in jedem Fall an die IDE (Handled bleibt False).
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.EditorCommands, E);
  end;
end;

class procedure TAtlasIdeCommentContinuation.EditorModified(const AView: IOTAEditView);
var
  FileName, LineText: string;
  Cursor: TOTAEditPos;
  View: IOTAEditView;
begin
  if (FInstance = nil) or (FInstance.FPendingFile = '') then
    Exit;
  FileName := FInstance.FPendingFile;
  // Nur die erste Änderung nach dem Tastendruck zählt.
  FInstance.FPendingFile := '';
  if not Enabled or (AView = nil) or (AView.Buffer = nil) or not SameText(FileName, AView.Buffer.FileName) or
    (TThread.GetTickCount64 - FInstance.FPendingAt > PendingMs) or
    (AView.Buffer.GetLinesInBuffer <> FInstance.FPendingLines + 1) then
    Exit;
  Cursor := AView.CursorPos;
  if Cursor.Line <= 1 then
    Exit;
  LineText := TAtlasEditorBuffer.LineText(AView, Cursor.Line);
  if Trim(Copy(LineText, 1, TLspSession.ColumnToIndex(LineText, Cursor.Col,
    TAtlasEditorBuffer.TabWidth(AView.Buffer)))) <> '' then
    Exit;
  // Erst nach der Änderung, wenn die IDE den Cursor gesetzt hat.
  View := AView;
  TAtlasMainThread.ForceQueue(TAtlasFeature.EditorCommands,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.EditorCommands,
        procedure
        begin
          Run(View);
        end);
    end);
end;

class procedure TAtlasIdeCommentContinuation.Run(const AView: IOTAEditView);
var
  Buffer: IOTAEditBuffer;
  Text, LineBreak, NewText, Insert, LineText: string;
  Lines, NewLines: TArray<string>;
  Cursor, Target: TOTAEditPos;
  TabWidth, Line, Character, Start, OldLength, Index: Integer;
  Edit: TAtlasCommentEdit;
begin
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
end;

end.
