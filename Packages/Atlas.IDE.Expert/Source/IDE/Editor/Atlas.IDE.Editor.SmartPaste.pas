unit Atlas.IDE.Editor.SmartPaste;

// Einfügen mit uses-Ergänzung (#515, experimentell) im Editor. Erkennen,
// Einrücken und die Antwort lesen rechnet Atlas.Core.Editor.SmartPaste, das
// Fenster zeichnet Atlas.UI.Editor.SmartPaste; hier bleiben Puffer, Tasten
// und die Anfrage an den Server.
// - Nach jeder Änderung im Editor (EditorViewModified) prüft ein kurzer
//   Zeitgeber, ob der Text der Zwischenablage direkt vor dem Cursor steht.
//   So zählt jedes Einfügen: Strg+V, Umschalt+Einfg, Kontextmenü. Nach einem
//   behandelten Einfügen prüft Atlas erst wieder nach einer Taste oder einem
//   Klick im Editor, damit eigene Änderungen kein zweites Mal zählen.
// - Einrücken (indent, both): ein eigener Schreiber, also ein eigener
//   Rückgängig-Schritt; der Cursor bleibt am Ende des Blocks.
// - uses ergänzen (uses, both): Der Server (atlas.server.pasteUses) nennt
//   fehlende Units und mehrdeutige Bezeichner. Gibt es welche, zeigt Atlas
//   das Fenster an der Einfügestelle: Enter übernimmt, Esc verwirft, ↑/↓ und
//   ←/→ wählen bei mehrdeutigen Bezeichnern. Jede andere Taste, ein Klick
//   daneben oder eine Änderung schließt es. Übernehmen ist ein zweiter
//   Rückgängig-Schritt und steht in der Meldungsansicht.
// - Nie bei offener Vervollständigung, im Platzhalter-Modus, mit mehreren
//   Einfügemarken oder beim Mitziehen von Bezeichnern.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Generics.Collections,
  Winapi.Windows,
  Winapi.Messages,
  Vcl.ExtCtrls,
  Vcl.AppEvnts,
  ToolsAPI,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.SmartPaste,
  Atlas.UI.Editor.SmartPaste;

type
  TAtlasSmartPasteSessionFunc = reference to function: TLspSession;

  TAtlasIdeSmartPaste = class
  private const
    /// <summary>Wartezeit nach der Änderung, bis die IDE den Cursor gesetzt hat.</summary>
    DelayMs = 30;
    TimeoutMs = 5000;
  private class var
    FInstance: TAtlasIdeSmartPaste;
  private
    FBusy: TFunc<Boolean>;
    FSession: TAtlasSmartPasteSessionFunc;
    FMessage: TProc<string>;
    FTimer: TTimer;
    FMessages: TApplicationEvents;
    FWindow: TAtlasSmartPasteWindow;
    FWorkers: TList<TThread>;
    FRequest: Integer;
    // Zwischenablage nach ihrer Folgenummer zwischengespeichert.
    FClipSequence: DWORD;
    FClipText: string;
    FClipLines: TArray<string>;
    /// <summary>False nach einem behandelten Einfügen bis zur nächsten Taste oder dem nächsten Klick.</summary>
    FArmed: Boolean;
    FWriting: Boolean;
    // Offene Anfrage: Datei, Text beim Fragen, Bereich des eingefügten Blocks (0-basiert).
    FFileName: string;
    FText: string;
    FStartLine: Integer;
    FStartCharacter: Integer;
    FEndLine: Integer;
    FEndCharacter: Integer;
    function IsBusy: Boolean;
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
    procedure KeyDown(const Msg: TMsg; var Handled: Boolean);
    procedure TimerTick(Sender: TObject);
    /// <summary>Zwischenablage lesen, wenn sie sich geändert hat; False ohne Text.</summary>
    function ReadClipboard: Boolean;
    procedure Check;
    /// <summary>Block in den Zeilen ab AStartLine einrücken (ein Schreiber); setzt den Cursor ans Ende.</summary>
    procedure Indent(const AView: IOTAEditView; AStartLine: Integer; var AStartCharacter, AEndCharacter: Integer);
    procedure Ask(const AView: IOTAEditView);
    procedure Answered(ARequest: Integer; const AAnalysis: TAtlasPasteAnalysis);
    procedure Accept;
    procedure ReapWorkers(AWait: Boolean);
    class function WantedMode: TAtlasPasteMode; static;
  public
    constructor Create(const ABusy: TFunc<Boolean>; const ASession: TAtlasSmartPasteSessionFunc;
      const AMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>ABusy: Vervollständigung, Platzhalter, Mehrfachmarken oder Mitziehen aktiv? ASession liefert die
    /// laufende Sitzung (nil ohne), AMessage schreibt eine Zeile in die Meldungsansicht.</summary>
    class procedure Install(const ABusy: TFunc<Boolean>; const ASession: TAtlasSmartPasteSessionFunc;
      const AMessage: TProc<string>); static;
    class procedure Uninstall; static;
    /// <summary>editor.smartPaste nicht off (experimentell, also nur mit experimental.enabled) und Atlas an?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Ist das Fenster offen?</summary>
    class function Active: Boolean; static;
    /// <summary>Fenster schließen (Ansicht gewechselt).</summary>
    class procedure Dismiss; static;
    /// <summary>Aus EditorViewModified: Fenster schließen und nach einem Einfügen sehen.</summary>
    class procedure EditorModified(const AView: IOTAEditView); static;
  end;

implementation

uses
  System.Math,
  System.JSON,
  Vcl.Controls,
  Vcl.Clipbrd,
  Atlas.Text.Lines,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.UI.Strings,
  Atlas.UI.Popup.Window,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Editor.WorkspaceEdit;

function IsEditorWindow(AWnd: HWND): Boolean;
var
  Control: TWinControl;
begin
  Control := FindControl(AWnd);
  Result := (Control <> nil) and Control.ClassNameIs('TEditControl');
end;

function IsPascal(const AFileName: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(AFileName));
  Result := (Ext = '.pas') or (Ext = '.dpr') or (Ext = '.dpk') or (Ext = '.inc');
end;

/// <summary>uses gibt es nur in Units und Programmen.</summary>
function HasUses(const AFileName: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(AFileName));
  Result := (Ext = '.pas') or (Ext = '.dpr');
end;

/// <summary>Bildschirmstelle unter der Zeile mit der Schreibmarke.</summary>
function CaretPoint: TPoint;
var
  Focus: HWND;
begin
  Result := Mouse.CursorPos;
  Focus := GetFocus;
  if (Focus <> 0) and GetCaretPos(Result) then
  begin
    Inc(Result.Y, 16);
    Winapi.Windows.ClientToScreen(Focus, Result);
  end;
end;

function ReadNames(AValue: TJSONValue): TArray<string>;
var
  Item: TJSONValue;
begin
  Result := nil;
  if AValue is TJSONArray then
    for Item in TJSONArray(AValue) do
      if Item is TJSONString then
        Result := Result + [Item.Value];
end;

{ TAtlasIdeSmartPaste }

constructor TAtlasIdeSmartPaste.Create(const ABusy: TFunc<Boolean>; const ASession: TAtlasSmartPasteSessionFunc;
  const AMessage: TProc<string>);
begin
  inherited Create;
  FBusy := ABusy;
  FSession := ASession;
  FMessage := AMessage;
  FArmed := True;
  FWorkers := TList<TThread>.Create;
  FMessages := TApplicationEvents.Create(nil);
  FMessages.OnMessage := AppMessage;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := DelayMs;
  FTimer.OnTimer := TimerTick;
end;

destructor TAtlasIdeSmartPaste.Destroy;
begin
  FreeAndNil(FMessages);
  FreeAndNil(FTimer);
  // Laufende Anfragen halten die Sitzung als rohen Zeiger: abwarten.
  ReapWorkers(True);
  FreeAndNil(FWorkers);
  FreeAndNil(FWindow);
  FClipLines := nil;
  inherited;
end;

class procedure TAtlasIdeSmartPaste.Install(const ABusy: TFunc<Boolean>; const ASession: TAtlasSmartPasteSessionFunc;
  const AMessage: TProc<string>);
begin
  if FInstance = nil then
    FInstance := TAtlasIdeSmartPaste.Create(ABusy, ASession, AMessage);
end;

class procedure TAtlasIdeSmartPaste.Uninstall;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeSmartPaste.WantedMode: TAtlasPasteMode;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := TAtlasPasteMode.Off;
  if Settings.Enabled then
    Result := TAtlasSmartPaste.ModeOf(Settings.SmartPaste);
end;

class function TAtlasIdeSmartPaste.Enabled: Boolean;
begin
  Result := WantedMode <> TAtlasPasteMode.Off;
end;

class function TAtlasIdeSmartPaste.Active: Boolean;
begin
  Result := (FInstance <> nil) and (FInstance.FWindow <> nil) and FInstance.FWindow.IsShown;
end;

class procedure TAtlasIdeSmartPaste.Dismiss;
begin
  if FInstance = nil then
    Exit;
  Inc(FInstance.FRequest);
  FInstance.FArmed := True;
  if FInstance.FWindow <> nil then
    FInstance.FWindow.Dismiss;
end;

class procedure TAtlasIdeSmartPaste.EditorModified(const AView: IOTAEditView);
begin
  if (FInstance = nil) or FInstance.FWriting then
    Exit;
  // Jede Änderung verwirft ein offenes Fenster und eine laufende Anfrage.
  Inc(FInstance.FRequest);
  if FInstance.FWindow <> nil then
    FInstance.FWindow.Dismiss;
  if not FInstance.FArmed or not Enabled then
    Exit;
  FInstance.FTimer.Enabled := False;
  FInstance.FTimer.Enabled := True;
end;

function TAtlasIdeSmartPaste.IsBusy: Boolean;
begin
  Result := Assigned(FBusy) and FBusy();
end;

procedure TAtlasIdeSmartPaste.ReapWorkers(AWait: Boolean);
var
  Index: Integer;
begin
  if FWorkers = nil then
    Exit;
  for Index := FWorkers.Count - 1 downto 0 do
    if AWait or FWorkers[Index].Finished then
    begin
      FWorkers[Index].WaitFor;
      FWorkers[Index].Free;
      FWorkers.Delete(Index);
    end;
end;

procedure TAtlasIdeSmartPaste.TimerTick(Sender: TObject);
begin
  FTimer.Enabled := False;
  TAtlasGuard.Run(TAtlasFeature.EditorCommands,
    procedure
    begin
      Check;
    end);
end;

function TAtlasIdeSmartPaste.ReadClipboard: Boolean;
var
  Sequence: DWORD;
begin
  Sequence := GetClipboardSequenceNumber;
  if Sequence <> FClipSequence then
  begin
    FClipSequence := Sequence;
    FClipText := '';
    try
      if Clipboard.HasFormat(CF_UNICODETEXT) then
        FClipText := Clipboard.AsText;
    except
      // Zwischenablage gerade von einem anderen Programm gesperrt: beim nächsten Mal.
      FClipSequence := 0;
      FClipText := '';
    end;
    FClipLines := TTextLines.SplitLines(FClipText);
  end;
  Result := (FClipText <> '') and TAtlasSmartPaste.Qualifies(FClipText);
end;

procedure TAtlasIdeSmartPaste.Check;
var
  Mode: TAtlasPasteMode;
  View: IOTAEditView;
  Cursor: TOTAEditPos;
  Line, Character, Index, Start, Tab: Integer;
  Lines: TArray<string>;
  CaretLine: string;
begin
  Mode := WantedMode;
  if (Mode = TAtlasPasteMode.Off) or not FArmed or IsBusy then
    Exit;
  View := TAtlasEditorBuffer.ActiveView;
  if (View = nil) or (View.Buffer = nil) or View.Buffer.IsReadOnly or not IsPascal(View.Buffer.FileName) then
    Exit;
  if not ReadClipboard then
    Exit;
  Cursor := View.CursorPos;
  Line := Cursor.Line - 1;
  if Line + 1 < Length(FClipLines) then
    Exit;
  Tab := TAtlasEditorBuffer.TabWidth(View.Buffer);
  CaretLine := TAtlasEditorBuffer.LineText(View, Line + 1);
  Character := Min(TLspSession.ColumnToIndex(CaretLine, Cursor.Col, Tab), Length(CaretLine));
  SetLength(Lines, Length(FClipLines));
  for Index := 0 to High(Lines) do
    Lines[Index] := TAtlasEditorBuffer.LineText(View, Line - High(Lines) + Index + 1);
  if not TAtlasSmartPaste.Match(Lines, Character, FClipLines, Start) then
    Exit;
  // Behandelt: Eigene Änderungen und der Cursor danach zählen nicht noch einmal.
  FArmed := False;
  FFileName := View.Buffer.FileName;
  FStartLine := Line - High(Lines);
  FStartCharacter := Start;
  FEndLine := Line;
  FEndCharacter := Character;
  if TAtlasSmartPaste.WantsIndent(Mode) then
    Indent(View, FStartLine, FStartCharacter, FEndCharacter);
  if TAtlasSmartPaste.WantsUses(Mode) and HasUses(FFileName) then
    Ask(View);
end;

procedure TAtlasIdeSmartPaste.Indent(const AView: IOTAEditView; AStartLine: Integer; var AStartCharacter,
  AEndCharacter: Integer);
var
  Buffer: IOTAEditBuffer;
  Text, Prefix, Above, LastLine: string;
  Edits: TArray<TAtlasIndentEdit>;
  Edit: TAtlasIndentEdit;
  Writer: IOTAEditWriter;
  Utf8: UTF8String;
  Index, Tab: Integer;
  Position: TOTAEditPos;
begin
  Buffer := AView.Buffer;
  Tab := TAtlasEditorBuffer.TabWidth(Buffer);
  Prefix := Copy(TAtlasEditorBuffer.LineText(AView, AStartLine + 1), 1, AStartCharacter);
  Above := '';
  for Index := AStartLine - 1 downto 0 do
  begin
    Above := TAtlasEditorBuffer.LineText(AView, Index + 1);
    if Trim(Above) <> '' then
      Break;
  end;
  if not TAtlasSmartPaste.Reindent(Prefix, Above, FClipLines, Tab, TAtlasEditorBuffer.BlockIndent(Buffer), Edits) then
    Exit;
  Text := TAtlasEditorBuffer.Text(Buffer);
  FWriting := True;
  try
    // Ein Schreiber: ein Rückgängig-Schritt, nur der Leerraum am Zeilenanfang.
    Writer := Buffer.CreateUndoableWriter;
    for Edit in Edits do
    begin
      Writer.CopyTo(TAtlasEditorBuffer.ByteOffset(Text, AStartLine + Edit.Line, 0));
      Writer.DeleteTo(TAtlasEditorBuffer.ByteOffset(Text, AStartLine + Edit.Line, Edit.Remove));
      Utf8 := UTF8Encode(Edit.Indent);
      if Utf8 <> '' then
        Writer.Insert(PAnsiChar(Utf8));
    end;
    Writer := nil;
  finally
    FWriting := False;
  end;
  TAtlasEditorSnapshots.Invalidate(Buffer.FileName);
  for Edit in Edits do
  begin
    if Edit.Line = 0 then
      AStartCharacter := Length(Edit.Indent);
    if Edit.Line = High(FClipLines) then
      AEndCharacter := AEndCharacter + Length(Edit.Indent) - Edit.Remove;
  end;
  // Cursor ans Ende des eingefügten Blocks.
  LastLine := TAtlasEditorBuffer.LineText(AView, AStartLine + High(FClipLines) + 1);
  AEndCharacter := Max(0, Min(AEndCharacter, Length(LastLine)));
  AView.Block.Reset;
  Position.Line := AStartLine + High(FClipLines) + 1;
  Position.Col := TLspSession.IndexToColumn(LastLine, AEndCharacter, Tab);
  AView.CursorPos := Position;
  AView.MoveViewToCursor;
  AView.Paint;
end;

procedure TAtlasIdeSmartPaste.Ask(const AView: IOTAEditView);
var
  Session: TLspSession;
  Arguments: string;
  Request: Integer;
  Worker: TThread;
begin
  if not Assigned(FSession) then
    Exit;
  Session := FSession();
  if Session = nil then
    Exit;
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  FText := TAtlasEditorBuffer.Text(AView.Buffer);
  Session.Sync(FFileName, FText);
  Arguments := TAtlasSmartPaste.Arguments(TLspSession.PathToUri(FFileName), FStartLine, FStartCharacter, FEndLine,
    FEndCharacter);
  ReapWorkers(False);
  Inc(FRequest);
  Request := FRequest;
  Worker := TThread.CreateAnonymousThread(
    procedure
    var
      Answer: TJSONValue;
      Analysis: TAtlasPasteAnalysis;
    begin
      Analysis := Default(TAtlasPasteAnalysis);
      try
        Answer := Session.RunCommand(TAtlasSmartPaste.Command, Arguments, TimeoutMs);
        try
          Analysis := TAtlasSmartPaste.ReadAnalysis(Answer);
        finally
          Answer.Free;
        end;
      except
        // Server langsam oder weg: kein Fenster, das Einfügen bleibt, wie es ist.
        Analysis := Default(TAtlasPasteAnalysis);
      end;
      // Atlas gehört der Eintrag: beim Entladen verworfen (Code-Review A-02).
      TAtlasMainThread.Queue(TAtlasFeature.EditorCommands,
        procedure
        begin
          if FInstance <> nil then
            TAtlasGuard.Run(TAtlasFeature.EditorCommands,
              procedure
              begin
                if FInstance <> nil then
                  FInstance.Answered(Request, Analysis);
              end);
        end);
    end);
  Worker.FreeOnTerminate := False;
  FWorkers.Add(Worker);
  Worker.Start;
end;

procedure TAtlasIdeSmartPaste.Answered(ARequest: Integer; const AAnalysis: TAtlasPasteAnalysis);
var
  View: IOTAEditView;
  Point: TPoint;
begin
  // Nur die jüngste Antwort zählt; jede Änderung dazwischen hat sie verworfen.
  if (ARequest <> FRequest) or not AAnalysis.Valid or
    ((Length(AAnalysis.Units) = 0) and (Length(AAnalysis.Choices) = 0)) or IsBusy then
    Exit;
  View := TAtlasEditorBuffer.ActiveView;
  if (View = nil) or (View.Buffer = nil) or not SameText(View.Buffer.FileName, FFileName) then
    Exit;
  if FWindow = nil then
  begin
    FWindow := TAtlasSmartPasteWindow.Create(nil);
    FWindow.OnAccept :=
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.EditorCommands,
          procedure
          begin
            if FInstance <> nil then
              FInstance.Accept;
          end);
      end;
  end;
  Point := CaretPoint;
  FWindow.Colors := TAtlasIdeStyle.Colors;
  FWindow.SetScaling(TAtlasPopupWindow.MonitorPPI(Point), 1, '', 10);
  FWindow.ShowFor(AAnalysis, Point);
end;

procedure TAtlasIdeSmartPaste.Accept;
var
  Session: TLspSession;
  View: IOTAEditView;
  Units, Added, Moved: TArray<string>;
  Answer: TJSONValue;
  Edit: TLspWorkspaceEdit;
  Outcome: TAtlasWorkspaceEditResult;
begin
  Units := TAtlasSmartPaste.Selected(FWindow.Analysis);
  if Length(Units) = 0 then
    Exit;
  View := TAtlasEditorBuffer.ActiveView;
  Session := nil;
  if Assigned(FSession) then
    Session := FSession();
  // Nur auf den Stand, für den die Antwort gilt.
  if (Session = nil) or (View = nil) or (View.Buffer = nil) or not SameText(View.Buffer.FileName, FFileName) or
    (TAtlasEditorBuffer.Text(View.Buffer) <> FText) then
    Exit;
  Edit := TLspWorkspaceEdit.FromJson(nil);
  Added := nil;
  Moved := nil;
  try
    Session.Sync(FFileName, FText);
    Answer := Session.RunCommand(TAtlasSmartPaste.Command, TAtlasSmartPaste.Arguments(
      TLspSession.PathToUri(FFileName), FStartLine, FStartCharacter, FEndLine, FEndCharacter, Units), TimeoutMs);
    try
      if Answer is TJSONObject then
      begin
        Edit := TLspWorkspaceEdit.FromJson(TJSONObject(Answer).GetValue('edit'));
        Added := ReadNames(TJSONObject(Answer).GetValue('added'));
        Moved := ReadNames(TJSONObject(Answer).GetValue('toImplementation'));
      end;
    finally
      Answer.Free;
    end;
  except
    on E: Exception do
    begin
      if Assigned(FMessage) then
        FMessage(TAtlasStrings.Fmt(TAtlasTextId.SmartPasteFailed, [E.Message]));
      Exit;
    end;
  end;
  if Edit.IsEmpty then
    Exit;
  FWriting := True;
  try
    Outcome := TAtlasIdeWorkspaceEdit.Apply(Edit, TAtlasUnopenedPolicy.OpenInEditor,
      TAtlasStrings.Text(TAtlasTextId.SmartPasteUsesTitle));
  finally
    FWriting := False;
  end;
  if not Assigned(FMessage) then
    Exit;
  if Outcome.Error <> '' then
  begin
    FMessage(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Outcome.Error]));
    Exit;
  end;
  FMessage(TAtlasStrings.Fmt(TAtlasTextId.SmartPasteDone, [string.Join(', ', Added)]));
  if Length(Moved) > 0 then
    FMessage(TAtlasStrings.Fmt(TAtlasTextId.SmartPasteImplementation, [string.Join(', ', Moved)]));
end;

procedure TAtlasIdeSmartPaste.KeyDown(const Msg: TMsg; var Handled: Boolean);
var
  Key: Word;
begin
  Key := Word(Msg.wParam);
  if (Key = VK_SHIFT) or (Key = VK_CONTROL) or (Key = VK_MENU) then
    Exit;
  if (FWindow <> nil) and FWindow.IsShown and (GetKeyState(VK_CONTROL) >= 0) and (GetKeyState(VK_MENU) >= 0) then
    case Key of
      VK_RETURN:
        begin
          FWindow.Accept;
          Handled := True;
          Exit;
        end;
      VK_ESCAPE:
        begin
          FWindow.Cancel;
          Handled := True;
          Exit;
        end;
      VK_UP:
        if FWindow.MoveRow(-1) then
        begin
          Handled := True;
          Exit;
        end;
      VK_DOWN:
        if FWindow.MoveRow(1) then
        begin
          Handled := True;
          Exit;
        end;
      VK_LEFT:
        if FWindow.MoveChoice(-1) then
        begin
          Handled := True;
          Exit;
        end;
      VK_RIGHT:
        if FWindow.MoveChoice(1) then
        begin
          Handled := True;
          Exit;
        end;
    end;
  // Jede andere Taste schließt das Fenster und erlaubt das nächste Einfügen.
  if FWindow <> nil then
    FWindow.Dismiss;
  FArmed := True;
end;

procedure TAtlasIdeSmartPaste.AppMessage(var Msg: TMsg; var Handled: Boolean);
begin
  if TAtlasGuard.Disabled(TAtlasFeature.EditorCommands) then
    Exit;
  try
    case Msg.message of
      WM_KEYDOWN, WM_SYSKEYDOWN:
        if IsEditorWindow(Msg.hwnd) then
          KeyDown(Msg, Handled);
      WM_LBUTTONDOWN, WM_RBUTTONDOWN, WM_MBUTTONDOWN, WM_NCLBUTTONDOWN:
        if (FWindow = nil) or not FWindow.HandleAllocated or (Msg.hwnd <> FWindow.Handle) then
        begin
          if FWindow <> nil then
            FWindow.Dismiss;
          if IsEditorWindow(Msg.hwnd) then
            FArmed := True;
        end;
    end;
  except
    // Keine Exception an die IDE (#493); die Nachricht geht dann normal weiter.
    on E: Exception do
    begin
      Handled := False;
      TAtlasGuard.Report(TAtlasFeature.EditorCommands, E);
    end;
  end;
end;

end.
