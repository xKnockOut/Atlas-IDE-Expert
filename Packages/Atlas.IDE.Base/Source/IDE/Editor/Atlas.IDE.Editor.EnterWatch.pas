unit Atlas.IDE.Editor.EnterWatch;

// Zeilenumbruch im Editor erkennen (#696, #671), ohne Enter zu binden: Die
// Taste gehört der IDE (Vervollständigung, Vorlagen, Einzug).
// Application.OnMessage sieht das WM_KEYDOWN, bevor die IDE es verarbeitet,
// lässt es durch und merkt sich Datei und Zeilenzahl. Kommt die nächste
// Änderung derselben Datei kurz danach mit genau einer Zeile mehr und steht der
// Cursor am Zeilenanfang (davor nur Leerraum), war es ein Zeilenumbruch.
// Einfügen aus der Zwischenablage zählt so nicht.
// Danach (in der Warteschlange des Hauptthreads, nie im Notifier) laufen die
// angemeldeten Handler in der Reihenfolge der Anmeldung; der erste, der die
// Zeile übernimmt (True), beendet die Runde: Kommentar fortsetzen vor Muster
// fortsetzen. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Winapi.Windows,
  Vcl.AppEvnts,
  ToolsAPI;

type
  /// <summary>Nach einem Zeilenumbruch in AView; True, wenn der Handler die neue Zeile übernommen hat.</summary>
  TAtlasEnterHandler = reference to function(const AView: IOTAEditView): Boolean;

  TAtlasEnterWatch = class
  private const
    /// <summary>So lange nach dem Tastendruck gilt eine Änderung als sein Zeilenumbruch.</summary>
    cPendingMs = 1000;
  private type
    THandler = record
      Name: string;
      Enabled: TFunc<Boolean>;
      Run: TAtlasEnterHandler;
    end;
  private class var
    FInstance: TAtlasEnterWatch;
    FHandlers: TArray<THandler>;
  private
    FEvents: TApplicationEvents;
    FPendingFile: string;
    FPendingLines: Integer;
    FPendingAt: UInt64;
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
    class function AnyEnabled: Boolean; static;
    class procedure Run(const AView: IOTAEditView); static;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Meldet AHandler unter AName an (ein zweites Add mit demselben Namen ersetzt ihn); AEnabled wird
    /// vor jedem Lauf gefragt.</summary>
    class procedure Add(const AName: string; const AEnabled: TFunc<Boolean>; const AHandler: TAtlasEnterHandler);
      static;
    /// <summary>Meldet AName ab; mit dem letzten Handler endet die Beobachtung.</summary>
    class procedure Remove(const AName: string); static;
    /// <summary>Aus EditorViewModified: war die Änderung ein Enter, laufen die Handler.</summary>
    class procedure EditorModified(const AView: IOTAEditView); static;
  end;

implementation

uses
  System.Classes,
  Winapi.Messages,
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Lsp.Session,
  Atlas.IDE.Foundation.EditorBuffer;

{ TAtlasEnterWatch }

constructor TAtlasEnterWatch.Create;
begin
  inherited Create;
  FEvents := TApplicationEvents.Create(nil);
  FEvents.OnMessage := AppMessage;
end;

destructor TAtlasEnterWatch.Destroy;
begin
  // Erst abmelden, dann freigeben (#493).
  FreeAndNil(FEvents);
  inherited;
end;

class procedure TAtlasEnterWatch.Add(const AName: string; const AEnabled: TFunc<Boolean>;
  const AHandler: TAtlasEnterHandler);
var
  mHandler: THandler;
  mIndex: Integer;
begin
  mHandler.Name := AName;
  mHandler.Enabled := AEnabled;
  mHandler.Run := AHandler;
  for mIndex := 0 to High(FHandlers) do
  begin
    if SameText(FHandlers[mIndex].Name, AName) then
    begin
      FHandlers[mIndex] := mHandler;
      Exit;
    end;
  end;
  FHandlers := FHandlers + [mHandler];
  if FInstance = nil then
  begin
    FInstance := TAtlasEnterWatch.Create;
  end;
end;

class procedure TAtlasEnterWatch.Remove(const AName: string);
var
  mIndex: Integer;
begin
  for mIndex := High(FHandlers) downto 0 do
  begin
    if SameText(FHandlers[mIndex].Name, AName) then
    begin
      Delete(FHandlers, mIndex, 1);
    end;
  end;
  if Length(FHandlers) = 0 then
  begin
    FHandlers := nil;
    FreeAndNil(FInstance);
  end;
end;

class function TAtlasEnterWatch.AnyEnabled: Boolean;
var
  mHandler: THandler;
begin
  Result := False;
  for mHandler in FHandlers do
  begin
    if not Assigned(mHandler.Enabled) or mHandler.Enabled() then
    begin
      Exit(True);
    end;
  end;
end;

procedure TAtlasEnterWatch.AppMessage(var Msg: TMsg; var Handled: Boolean);
var
  mView: IOTAEditView;
begin
  if (Msg.message <> WM_KEYDOWN) or (Msg.wParam <> VK_RETURN) then
  begin
    Exit;
  end;
  try
    FPendingFile := '';
    // Strg+Enter und Alt+Enter sind Befehle, kein Zeilenumbruch; nur im Editor selbst.
    if not AnyEnabled or (GetKeyState(VK_CONTROL) < 0) or (GetKeyState(VK_MENU) < 0) or
      (Screen.ActiveControl = nil) or not Screen.ActiveControl.ClassNameIs('TEditControl') then
    begin
      Exit;
    end;
    mView := TAtlasEditorBuffer.ActiveView;
    if (mView = nil) or (mView.Buffer = nil) then
    begin
      Exit;
    end;
    FPendingFile := mView.Buffer.FileName;
    FPendingLines := mView.Buffer.GetLinesInBuffer;
    FPendingAt := TThread.GetTickCount64;
  except
    // Die Taste geht in jedem Fall an die IDE (Handled bleibt False).
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.ContinueLines, E);
  end;
end;

class procedure TAtlasEnterWatch.EditorModified(const AView: IOTAEditView);
var
  mFileName, mLineText: string;
  mCursor: TOTAEditPos;
  mView: IOTAEditView;
begin
  if (FInstance = nil) or (FInstance.FPendingFile = '') then
  begin
    Exit;
  end;
  mFileName := FInstance.FPendingFile;
  // Nur die erste Änderung nach dem Tastendruck zählt.
  FInstance.FPendingFile := '';
  if (AView = nil) or (AView.Buffer = nil) or not SameText(mFileName, AView.Buffer.FileName) or
    (TThread.GetTickCount64 - FInstance.FPendingAt > cPendingMs) or
    (AView.Buffer.GetLinesInBuffer <> FInstance.FPendingLines + 1) then
  begin
    Exit;
  end;
  mCursor := AView.CursorPos;
  if mCursor.Line <= 1 then
  begin
    Exit;
  end;
  mLineText := TAtlasEditorBuffer.LineText(AView, mCursor.Line);
  if Trim(Copy(mLineText, 1, TLspSession.ColumnToIndex(mLineText, mCursor.Col,
    TAtlasEditorBuffer.TabWidth(AView.Buffer)))) <> '' then
  begin
    Exit;
  end;
  // Erst nach der Änderung, wenn die IDE den Cursor gesetzt hat.
  mView := AView;
  TAtlasMainThread.ForceQueue(TAtlasFeature.ContinueLines,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.ContinueLines,
        procedure
        begin
          Run(mView);
        end);
    end);
end;

class procedure TAtlasEnterWatch.Run(const AView: IOTAEditView);
var
  mHandlers: TArray<THandler>;
  mHandler: THandler;
begin
  // Eine Kopie: Ein Handler darf sich abmelden.
  mHandlers := Copy(FHandlers);
  for mHandler in mHandlers do
  begin
    if (not Assigned(mHandler.Enabled) or mHandler.Enabled()) and mHandler.Run(AView) then
    begin
      Exit;
    end;
  end;
end;

end.
