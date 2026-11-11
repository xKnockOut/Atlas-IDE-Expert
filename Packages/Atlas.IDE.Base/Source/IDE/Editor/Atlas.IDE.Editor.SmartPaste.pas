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
//   Die Spalte der ersten Zeile kommt vom Server (Blockstruktur wie nach
//   Enter, #1832, kurz im Hauptthread); ohne Antwort gilt die Heuristik.
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
  Winapi.Windows,
  Winapi.Messages,
  Vcl.ExtCtrls,
  Vcl.AppEvnts,
  ToolsAPI,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Editor.SmartPaste,
  Atlas.UI.Editor.SmartPaste,
  Atlas.Core.Diagnostics.WorkerSlot;

type
  TAtlasSmartPasteSessionFunc = reference to function: TLspSession;

  TAtlasIdeSmartPaste = class
  private const
    /// <summary>Wartezeit nach der Änderung, bis die IDE den Cursor gesetzt hat.</summary>
    cDelayMs = 30;
    cTimeoutMs = 5000;
  private class var
    FInstance: TAtlasIdeSmartPaste;
  private
    FBusy: TFunc<Boolean>;
    FSession: TAtlasSmartPasteSessionFunc;
    FMessage: TProc<string>;
    FTimer: TTimer;
    FMessages: TApplicationEvents;
    FWindow: TAtlasSmartPasteWindow;
    FWorkers: TAtlasWorkerSlot;
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
    procedure KeyDown(const AMsg: TMsg; var AHandled: Boolean);
    procedure TimerTick(Sender: TObject);
    /// <summary>Zwischenablage lesen, wenn sie sich geändert hat; False ohne Text.</summary>
    function ReadClipboard: Boolean;
    procedure Check;
    /// <summary>Block in den Zeilen ab AStartLine einrücken (ein Schreiber); setzt den Cursor ans Ende.</summary>
    procedure Indent(const AView: IOTAEditView; AStartLine: Integer; var AStartCharacter, AEndCharacter: Integer);
    procedure Ask(const AView: IOTAEditView);
    procedure Answered(ARequest: Integer; const AAnalysis: TAtlasPasteAnalysis);
    procedure Accept;
    function FetchUses(ASession: TLspSession; const AUnits: TArray<string>; out AEdit: TLspWorkspaceEdit;
      out AAdded, AMoved: TArray<string>): Boolean;
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
    class procedure EditorModified; static;
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
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.UI.Strings,
  Atlas.UI.Popup.Window,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Editor.SmartIndent;

function IsEditorWindow(AWnd: HWND): Boolean;
var
  mControl: TWinControl;
begin
  mControl := FindControl(AWnd);
  Result := (mControl <> nil) and mControl.ClassNameIs('TEditControl');
end;

function IsPascal(const AFileName: string): Boolean;
var
  mExt: string;
begin
  mExt := LowerCase(ExtractFileExt(AFileName));
  Result := (mExt = '.pas') or (mExt = '.dpr') or (mExt = '.dpk') or (mExt = '.inc');
end;

/// <summary>uses gibt es nur in Units und Programmen.</summary>
function HasUses(const AFileName: string): Boolean;
var
  mExt: string;
begin
  mExt := LowerCase(ExtractFileExt(AFileName));
  Result := (mExt = '.pas') or (mExt = '.dpr');
end;

/// <summary>Bildschirmstelle unter der Zeile mit der Schreibmarke.</summary>
function CaretPoint: TPoint;
var
  mFocus: HWND;
begin
  Result := Mouse.CursorPos;
  mFocus := GetFocus;
  if (mFocus <> 0) and GetCaretPos(Result) then
  begin
    Inc(Result.Y, 16);
    Winapi.Windows.ClientToScreen(mFocus, Result);
  end;
end;

function ReadNames(AValue: TJSONValue): TArray<string>;
var
  mItem: TJSONValue;
begin
  Result := nil;
  if AValue is TJSONArray then
  begin
    for mItem in TJSONArray(AValue) do
    begin
      if mItem is TJSONString then
      begin
        Result := Result + [mItem.Value];
      end;
    end;
  end;
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
  FWorkers := TAtlasWorkerSlot.Create(HInstance);
  FMessages := TApplicationEvents.Create(nil);
  FMessages.OnMessage := AppMessage;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := cDelayMs;
  FTimer.OnTimer := TimerTick;
end;

destructor TAtlasIdeSmartPaste.Destroy;
begin
  FreeAndNil(FMessages);
  FreeAndNil(FTimer);
  // Laufende Anfragen halten die Sitzung als rohen Zeiger: bis zu ihrem Ende abwarten (sie haben eine eigene
  // Zeitgrenze), nicht nur bis cStopMs.
  if FWorkers <> nil then
  begin
    FWorkers.Stop(TAtlasWorkerSlot.cWaitForever);
  end;
  FreeAndNil(FWorkers);
  FreeAndNil(FWindow);
  FClipLines := nil;
  inherited;
end;

class procedure TAtlasIdeSmartPaste.Install(const ABusy: TFunc<Boolean>; const ASession: TAtlasSmartPasteSessionFunc;
  const AMessage: TProc<string>);
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeSmartPaste.Create(ABusy, ASession, AMessage);
  end;
end;

class procedure TAtlasIdeSmartPaste.Uninstall;
begin
  FreeAndNil(FInstance);
end;

function WantedMode: TAtlasPasteMode;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := TAtlasPasteMode.Off;
  if mSettings.Enabled then
  begin
    Result := TAtlasSmartPaste.ModeOf(mSettings.SmartPaste);
  end;
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
  begin
    Exit;
  end;
  Inc(FInstance.FRequest);
  FInstance.FArmed := True;
  if FInstance.FWindow <> nil then
  begin
    FInstance.FWindow.Dismiss;
  end;
end;

class procedure TAtlasIdeSmartPaste.EditorModified;
begin
  if (FInstance = nil) or FInstance.FWriting then
  begin
    Exit;
  end;
  // Jede Änderung verwirft ein offenes Fenster und eine laufende Anfrage.
  Inc(FInstance.FRequest);
  if FInstance.FWindow <> nil then
  begin
    FInstance.FWindow.Dismiss;
  end;
  if not FInstance.FArmed or not Enabled then
  begin
    Exit;
  end;
  FInstance.FTimer.Enabled := False;
  FInstance.FTimer.Enabled := True;
end;

function TAtlasIdeSmartPaste.IsBusy: Boolean;
begin
  Result := Assigned(FBusy) and FBusy();
end;

procedure TAtlasIdeSmartPaste.TimerTick(Sender: TObject);
begin
  FTimer.Enabled := False;
  TAtlasGuard.Run(TAtlasFeature.SmartPaste,
    procedure
    begin
      Check;
    end);
end;

function TAtlasIdeSmartPaste.ReadClipboard: Boolean;
var
  mSequence: DWORD;
begin
  mSequence := GetClipboardSequenceNumber;
  if mSequence <> FClipSequence then
  begin
    FClipSequence := mSequence;
    FClipText := '';
    try
      if Clipboard.HasFormat(CF_UNICODETEXT) then
      begin
        FClipText := Clipboard.AsText;
      end;
    except
      // Zwischenablage gerade von einem anderen Programm gesperrt: beim nächsten Mal.
      FClipSequence := 0;
      FClipText := '';
    end;
    FClipLines := TTextLines.SplitLines(FClipText);
  end;
  Result := (FClipText <> '') and TAtlasSmartPaste.Qualifies(FClipText);
end;

/// <summary>Beschreibbare Pascal-Datei vorn?</summary>
function Pastable(const AView: IOTAEditView): Boolean;
begin
  Result := (AView <> nil) and (AView.Buffer <> nil) and not AView.Buffer.IsReadOnly and
    IsPascal(AView.Buffer.FileName);
end;

/// <summary>Steht AClipLines direkt vor dem Cursor von AView? ALine: Zeile des Cursors (ab 0), ACharacter: Zeichen
/// des Cursors, AStart: Zeichen, an dem der Block in der ersten Zeile beginnt.</summary>
function PastedAt(const AView: IOTAEditView; const AClipLines: TArray<string>; out ALine, ACharacter,
  AStart: Integer): Boolean;
var
  mCursor: TOTAEditPos;
  mIndex: Integer;
  mLines: TArray<string>;
  mCaretLine: string;
begin
  mCursor := AView.CursorPos;
  ALine := mCursor.Line - 1;
  ACharacter := 0;
  AStart := 0;
  Result := ALine + 1 >= Length(AClipLines);
  if not Result then
  begin
    Exit;
  end;
  mCaretLine := TAtlasEditorBuffer.LineText(AView, ALine + 1);
  ACharacter := Min(TLspSession.ColumnToIndex(mCaretLine, mCursor.Col, TAtlasEditorBuffer.TabWidth(AView.Buffer)),
    Length(mCaretLine));
  SetLength(mLines, Length(AClipLines));
  for mIndex := 0 to High(mLines) do
  begin
    mLines[mIndex] := TAtlasEditorBuffer.LineText(AView, ALine - High(mLines) + mIndex + 1);
  end;
  Result := TAtlasSmartPaste.Match(mLines, ACharacter, AClipLines, AStart);
end;

procedure TAtlasIdeSmartPaste.Check;
var
  mMode: TAtlasPasteMode;
  mView: IOTAEditView;
  mLine, mCharacter, mStart: Integer;
begin
  mMode := WantedMode;
  if (mMode = TAtlasPasteMode.Off) or not FArmed or IsBusy then
  begin
    Exit;
  end;
  mView := TAtlasEditorBuffer.ActiveView;
  if not Pastable(mView) or not ReadClipboard or not PastedAt(mView, FClipLines, mLine, mCharacter, mStart) then
  begin
    Exit;
  end;
  // Behandelt: Eigene Änderungen und der Cursor danach zählen nicht noch einmal.
  FArmed := False;
  FFileName := mView.Buffer.FileName;
  FStartLine := mLine - High(FClipLines);
  FStartCharacter := mStart;
  FEndLine := mLine;
  FEndCharacter := mCharacter;
  if TAtlasSmartPaste.WantsIndent(mMode) then
  begin
    Indent(mView, FStartLine, FStartCharacter, FEndCharacter);
  end;
  if TAtlasSmartPaste.WantsUses(mMode) and HasUses(FFileName) then
  begin
    Ask(mView);
  end;
end;

/// <summary>Nächste nicht leere Zeile über AStartLine ('' ohne).</summary>
function LineAbove(const AView: IOTAEditView; AStartLine: Integer): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := AStartLine - 1 downto 0 do
  begin
    Result := TAtlasEditorBuffer.LineText(AView, mIndex + 1);
    if Trim(Result) <> '' then
    begin
      Break;
    end;
  end;
end;

/// <summary>Ein Schreiber: ein Rückgängig-Schritt, nur der Leerraum am Zeilenanfang der Zeilen ab AStartLine.
/// </summary>
procedure WriteIndents(const ABuffer: IOTAEditBuffer; AStartLine: Integer; const AEdits: TArray<TAtlasIndentEdit>);
var
  mText: string;
  mEdit: TAtlasIndentEdit;
  mWriter: IOTAEditWriter;
  mUtf8: UTF8String;
begin
  mText := TAtlasEditorBuffer.Text(ABuffer);
  mWriter := ABuffer.CreateUndoableWriter;
  for mEdit in AEdits do
  begin
    mWriter.CopyTo(TAtlasEditorBuffer.ByteOffset(mText, AStartLine + mEdit.Line, 0));
    mWriter.DeleteTo(TAtlasEditorBuffer.ByteOffset(mText, AStartLine + mEdit.Line, mEdit.Remove));
    mUtf8 := UTF8Encode(mEdit.Indent);
    if mUtf8 <> '' then
    begin
      mWriter.Insert(PAnsiChar(mUtf8));
    end;
  end;
  mWriter := nil;
  TAtlasEditorSnapshots.Invalidate(ABuffer.FileName);
end;

/// <summary>Cursor in Zeile ALine (ab 0) an Zeichen ACharacter (höchstens ans Zeilenende).</summary>
procedure PlaceCursor(const AView: IOTAEditView; ALine: Integer; var ACharacter: Integer);
var
  mLastLine: string;
  mPosition: TOTAEditPos;
begin
  mLastLine := TAtlasEditorBuffer.LineText(AView, ALine + 1);
  ACharacter := Max(0, Min(ACharacter, Length(mLastLine)));
  AView.Block.Reset;
  mPosition.Line := ALine + 1;
  mPosition.Col := TLspSession.IndexToColumn(mLastLine, ACharacter, TAtlasEditorBuffer.TabWidth(AView.Buffer));
  AView.CursorPos := mPosition;
  AView.MoveViewToCursor;
  AView.Paint;
end;

/// <summary>Spalte der ersten eingefügten Zeile AStartLine (0-basiert) nach der Blockstruktur vom Server (#1832);
/// NoColumn, wenn vor der Einfügestelle Code steht oder der Server sie nicht bestimmt.</summary>
function ServerColumn(const AView: IOTAEditView; AStartLine: Integer; const APrefix: string): Integer;
begin
  if (Trim(APrefix) <> '') or not TAtlasIdeSmartIndent.ColumnAt(AView.Buffer, TAtlasEditorBuffer.Text(AView.Buffer),
    AStartLine, Result) then
  begin
    Result := TAtlasSmartPaste.cNoColumn;
  end;
end;

procedure TAtlasIdeSmartPaste.Indent(const AView: IOTAEditView; AStartLine: Integer; var AStartCharacter,
  AEndCharacter: Integer);
var
  mEdits: TArray<TAtlasIndentEdit>;
  mEdit: TAtlasIndentEdit;
  mPrefix: string;
begin
  mPrefix := Copy(TAtlasEditorBuffer.LineText(AView, AStartLine + 1), 1, AStartCharacter);
  if not TAtlasSmartPaste.Reindent(mPrefix, LineAbove(AView, AStartLine), FClipLines,
    TAtlasPasteIndent.Create(TAtlasEditorBuffer.TabWidth(AView.Buffer), TAtlasEditorBuffer.BlockIndent(AView.Buffer),
    ServerColumn(AView, AStartLine, mPrefix)), mEdits) then
  begin
    Exit;
  end;
  FWriting := True;
  try
    WriteIndents(AView.Buffer, AStartLine, mEdits);
  finally
    FWriting := False;
  end;
  for mEdit in mEdits do
  begin
    if mEdit.Line = 0 then
    begin
      AStartCharacter := Length(mEdit.Indent);
    end;
    if mEdit.Line = High(FClipLines) then
    begin
      AEndCharacter := AEndCharacter + Length(mEdit.Indent) - mEdit.Remove;
    end;
  end;
  // Cursor ans Ende des eingefügten Blocks.
  PlaceCursor(AView, AStartLine + High(FClipLines), AEndCharacter);
end;

procedure TAtlasIdeSmartPaste.Ask(const AView: IOTAEditView);
var
  mSession: TLspSession;
  mArguments: string;
  mRequest: Integer;
  mWorker: TThread;
begin
  if not Assigned(FSession) then
  begin
    Exit;
  end;
  mSession := FSession();
  if mSession = nil then
  begin
    Exit;
  end;
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  FText := TAtlasEditorBuffer.Text(AView.Buffer);
  mSession.Sync(FFileName, FText);
  mArguments := TAtlasSmartPaste.Arguments(TLspSession.PathToUri(FFileName), FStartLine, FStartCharacter, FEndLine,
    FEndCharacter);
  FWorkers.Prune;
  Inc(FRequest);
  mRequest := FRequest;
  mWorker := TThread.CreateAnonymousThread(
    procedure
    var
      Answer: TJSONValue;
      Analysis: TAtlasPasteAnalysis;
    begin
      Analysis := Default(TAtlasPasteAnalysis);
      try
        Answer := mSession.RunCommand(TAtlasSmartPaste.cCommand, mArguments, cTimeoutMs);
        try
          Analysis := TAtlasSmartPaste.ReadAnalysis(Answer);
        finally
          Answer.Free;
        end;
      except
        // Server langsam oder weg: kein Fenster, das Einfügen bleibt, wie es ist.
        Analysis := Default(TAtlasPasteAnalysis);
      end;
      // Atlas gehört der Eintrag: beim Entladen verworfen.
      TAtlasMainThread.Queue(TAtlasFeature.SmartPaste,
        procedure
        begin
          if FInstance <> nil then
          begin
            TAtlasGuard.Run(TAtlasFeature.SmartPaste,
              procedure
              begin
                if FInstance <> nil then
                begin
                  FInstance.Answered(mRequest, Analysis);
                end;
              end);
          end;
        end);
    end);
  FWorkers.Start(mWorker);
end;

procedure TAtlasIdeSmartPaste.Answered(ARequest: Integer; const AAnalysis: TAtlasPasteAnalysis);
var
  mView: IOTAEditView;
  mPoint: TPoint;
begin
  // Nur die jüngste Antwort zählt; jede Änderung dazwischen hat sie verworfen.
  if (ARequest <> FRequest) or not AAnalysis.Valid or
    ((Length(AAnalysis.Units) = 0) and (Length(AAnalysis.Choices) = 0)) or IsBusy then
  begin
    Exit;
  end;
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView = nil) or (mView.Buffer = nil) or not SameText(mView.Buffer.FileName, FFileName) then
  begin
    Exit;
  end;
  if FWindow = nil then
  begin
    FWindow := TAtlasSmartPasteWindow.Create(nil);
    FWindow.OnAccept :=
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.SmartPaste,
          procedure
          begin
            if FInstance <> nil then
            begin
              FInstance.Accept;
            end;
          end);
      end;
  end;
  mPoint := CaretPoint;
  FWindow.Colors := TAtlasIdeStyle.Colors;
  FWindow.SetScaling(TAtlasPopupWindow.MonitorPPI(mPoint), 1, '', 10);
  FWindow.ShowFor(AAnalysis, mPoint);
end;

/// <summary>Fragt mit den gewählten Units AUnits nach der Änderung; False mit Meldung, wenn der Server scheitert.
/// </summary>
function TAtlasIdeSmartPaste.FetchUses(ASession: TLspSession; const AUnits: TArray<string>;
  out AEdit: TLspWorkspaceEdit; out AAdded, AMoved: TArray<string>): Boolean;
var
  mAnswer: TJSONValue;
begin
  Result := False;
  AEdit := TLspWorkspaceEdit.FromJson(nil);
  AAdded := nil;
  AMoved := nil;
  try
    ASession.Sync(FFileName, FText);
    mAnswer := ASession.RunCommand(TAtlasSmartPaste.cCommand, TAtlasSmartPaste.Arguments(
      TLspSession.PathToUri(FFileName), FStartLine, FStartCharacter, FEndLine, FEndCharacter, AUnits), cTimeoutMs);
    try
      if mAnswer is TJSONObject then
      begin
        AEdit := TLspWorkspaceEdit.FromJson(TJSONObject(mAnswer).GetValue('edit'));
        AAdded := ReadNames(TJSONObject(mAnswer).GetValue('added'));
        AMoved := ReadNames(TJSONObject(mAnswer).GetValue('toImplementation'));
      end;
    finally
      mAnswer.Free;
    end;
    Result := True;
  except
    on E: Exception do
    begin
      if Assigned(FMessage) then
      begin
        FMessage(TAtlasStrings.Fmt(TAtlasTextId.SmartPasteFailed, [E.Message]));
      end;
    end;
  end;
end;

/// <summary>Zeigt AView noch den Stand AText von AFileName?</summary>
function SameState(const AView: IOTAEditView; const AFileName, AText: string): Boolean;
begin
  Result := (AView <> nil) and (AView.Buffer <> nil) and SameText(AView.Buffer.FileName, AFileName) and
    (TAtlasEditorBuffer.Text(AView.Buffer) = AText);
end;

procedure TAtlasIdeSmartPaste.Accept;
var
  mSession: TLspSession;
  mUnits, mAdded, mMoved: TArray<string>;
  mEdit: TLspWorkspaceEdit;
  mOutcome: TAtlasWorkspaceEditResult;
begin
  mUnits := TAtlasSmartPaste.Selected(FWindow.Analysis);
  mSession := nil;
  if Assigned(FSession) then
  begin
    mSession := FSession();
  end;
  // Nur auf den Stand, für den die Antwort gilt.
  if (Length(mUnits) = 0) or (mSession = nil) or not SameState(TAtlasEditorBuffer.ActiveView, FFileName, FText) or
    not FetchUses(mSession, mUnits, mEdit, mAdded, mMoved) or mEdit.IsEmpty then
  begin
    Exit;
  end;
  FWriting := True;
  try
    mOutcome := TAtlasIdeWorkspaceEdit.Apply(mEdit, TAtlasUnopenedPolicy.OpenInEditor,
      TAtlasStrings.Text(TAtlasTextId.SmartPasteUsesTitle));
  finally
    FWriting := False;
  end;
  if not Assigned(FMessage) then
  begin
    Exit;
  end;
  if mOutcome.Error <> '' then
  begin
    FMessage(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [mOutcome.Error]));
    Exit;
  end;
  FMessage(TAtlasStrings.Fmt(TAtlasTextId.SmartPasteDone, [string.Join(', ', mAdded)]));
  if Length(mMoved) > 0 then
  begin
    FMessage(TAtlasStrings.Fmt(TAtlasTextId.SmartPasteImplementation, [string.Join(', ', mMoved)]));
  end;
end;

/// <summary>Taste AKey im offenen Fenster (ohne Strg/Alt): Enter übernimmt, Esc verwirft, Pfeile wählen; False,
/// wenn sie das Fenster nicht betrifft.</summary>
function WindowKey(AWindow: TAtlasSmartPasteWindow; AKey: Word): Boolean;
begin
  Result := (AWindow <> nil) and AWindow.IsShown and (GetKeyState(VK_CONTROL) >= 0) and (GetKeyState(VK_MENU) >= 0);
  if not Result then
  begin
    Exit;
  end;
  case AKey of
    VK_RETURN:
      AWindow.Accept;
    VK_ESCAPE:
      AWindow.Cancel;
    VK_UP:
      Result := AWindow.MoveRow(-1);
    VK_DOWN:
      Result := AWindow.MoveRow(1);
    VK_LEFT:
      Result := AWindow.MoveChoice(-1);
    VK_RIGHT:
      Result := AWindow.MoveChoice(1);
  else
    Result := False;
  end;
end;

procedure TAtlasIdeSmartPaste.KeyDown(const AMsg: TMsg; var AHandled: Boolean);
var
  mKey: Word;
begin
  mKey := Word(AMsg.wParam);
  if (mKey = VK_SHIFT) or (mKey = VK_CONTROL) or (mKey = VK_MENU) then
  begin
    Exit;
  end;
  if WindowKey(FWindow, mKey) then
  begin
    AHandled := True;
    Exit;
  end;
  // Jede andere Taste schließt das Fenster und erlaubt das nächste Einfügen.
  if FWindow <> nil then
  begin
    FWindow.Dismiss;
  end;
  FArmed := True;
end;

procedure TAtlasIdeSmartPaste.AppMessage(var Msg: TMsg; var Handled: Boolean);
begin
  if TAtlasGuard.Disabled(TAtlasFeature.SmartPaste) then
  begin
    Exit;
  end;
  try
    case Msg.message of
      WM_KEYDOWN, WM_SYSKEYDOWN:
        if IsEditorWindow(Msg.hwnd) then
        begin
          KeyDown(Msg, Handled);
        end;
      WM_LBUTTONDOWN, WM_RBUTTONDOWN, WM_MBUTTONDOWN, WM_NCLBUTTONDOWN:
        if (FWindow = nil) or not FWindow.HandleAllocated or (Msg.hwnd <> FWindow.Handle) then
        begin
          if FWindow <> nil then
          begin
            FWindow.Dismiss;
          end;
          if IsEditorWindow(Msg.hwnd) then
          begin
            FArmed := True;
          end;
        end;
    end;
  except
    // Keine Exception an die IDE (#493); die Nachricht geht dann normal weiter.
    on E: Exception do
    begin
      Handled := False;
      TAtlasGuard.Report(TAtlasFeature.SmartPaste, E);
    end;
  end;
end;

end.
