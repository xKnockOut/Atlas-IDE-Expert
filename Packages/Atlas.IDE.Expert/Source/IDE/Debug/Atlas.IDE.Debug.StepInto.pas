unit Atlas.IDE.Debug.StepInto;

// Gezielt hineinspringen (#836) im Debugger der IDE. Welche Aufrufe die
// Anweisung am Ausführungspunkt hat, rechnet der Server
// (atlas.server.stepTargets); die Zeilen baut Atlas.Core.Debug.StepInto, die
// Liste zeichnet Atlas.UI.Debug.StepInto. Hier bleiben Anfrage, Tasten und
// der Sprung:
// - Strg+Alt+F7 (debug.stepIntoTarget.key), Kontextmenü und Befehlspalette,
//   nur im angehaltenen Zustand; sonst geht die Taste an die IDE.
// - Ausführungspunkt aus dem angehaltenen Thread (CurrentFile/CurrentLine).
//   Der Text der Datei geht vorher an den Server.
// - Virtuelle Aufrufe: Laufzeittyp über eine Auswertung (Empfänger.ClassName),
//   nur wenn der Empfänger dabei nichts aufruft.
// - Ausgegraut: ohne Quelltext und Bibliothekscode unter $(BDS)\source, solange
//   das aktive Projekt ohne Debug-DCUs (DCC_DebugDCUs) übersetzt.
// - Höchstens ein Aufruf: wie F7 (ormStmtStepInto), ohne Liste.
// - Sprung: vorübergehender Haltepunkt auf das begin der gewählten Routine und
//   einer auf die Folgeanweisung, dann Weiter (ormRun). Beim nächsten Halt
//   entfernt Atlas beide, gleich wer gegriffen hat; hält das Programm an der
//   Folgeanweisung, meldet Atlas „nicht aufgerufen“. Steht dort schon ein
//   Haltepunkt des Benutzers, legt Atlas keinen zweiten an. Vorhandene
//   Haltepunkte bleiben aktiv und können vorher greifen.
// - Esc, jede andere Taste oder ein Klick daneben schließt die Liste.
// Gesichert über TAtlasFeature.Debugger (#493). Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Winapi.Windows,
  Winapi.Messages,
  Vcl.AppEvnts,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Debug.StepInto,
  Atlas.UI.Debug.StepInto;

type
  TAtlasStepIntoSessionFunc = reference to function: TLspSession;

  TAtlasIdeStepInto = class
  private const
    /// <summary>Die Namensauflösung je Aufruf braucht etwas länger als eine einfache Anfrage.</summary>
    TimeoutMs = 10000;
    /// <summary>Zeitlimit je Auswertung des Laufzeittyps.</summary>
    EvaluateMs = 1500;
    TickMs = 100;
  private class var
    FInstance: TAtlasIdeStepInto;
  private
    FSession: TAtlasStepIntoSessionFunc;
    FMessage: TProc<string>;
    FMessages: TApplicationEvents;
    FWindow: TAtlasStepIntoWindow;
    FTimer: TTimer;
    // Offene Liste: Datei des Ausführungspunkts, Antwort und Zeilen.
    FFileName: string;
    FAnswer: TAtlasStepAnswer;
    FRows: TArray<TAtlasStepRow>;
    // Laufender Sprung.
    FRunning: Boolean;
    FSeenRunning: Boolean;
    FStartFile: string;
    FStartLine: Integer;
    FCaption: string;
    FTarget: TAtlasStepTarget;
    FFollowLine: Integer;
    FTargetBreak: IOTABreakpoint;
    FFollowBreak: IOTABreakpoint;
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
    procedure KeyDown(const Msg: TMsg; var Handled: Boolean);
    procedure Tick(Sender: TObject);
    function Execute: Boolean;
    procedure Accept(AIndex: Integer);
    procedure Launch(const ARow: TAtlasStepRow);
    procedure StepInto;
    procedure Close;
    procedure Finish;
    procedure RemoveBreakpoints;
    procedure Report(const AText: string);
    function SourceText(const AFileName: string; out AText: string): Boolean;
    class function Debugger: IOTADebuggerServices; static;
    class function StoppedProcess: IOTAProcess; static;
    class function Position(const AThread: IOTAThread; out AFileName: string; out ALine: Integer): Boolean; static;
    class function NewBreakpoint(const AFileName: string; ALine: Integer): IOTABreakpoint; static;
    class function CanBreak(const AFileName: string): Boolean; static;
    class function Evaluate(const AExpression: string; out AValue: string): Boolean; static;
  public
    constructor Create(const ASession: TAtlasStepIntoSessionFunc; const AMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>ASession liefert die laufende Sitzung (nil ohne), AMessage schreibt eine Zeile in die
    /// Meldungsansicht.</summary>
    class procedure Install(const ASession: TAtlasStepIntoSessionFunc; const AMessage: TProc<string>); static;
    class procedure Uninstall; static;
    /// <summary>debug.stepIntoTarget an und Atlas an?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Hält das Programm gerade an?</summary>
    class function Stopped: Boolean; static;
    /// <summary>Ist die Liste offen?</summary>
    class function Active: Boolean; static;
    /// <summary>Befehl Atlas.StepIntoTarget (Palette, Kontextmenü): ohne angehaltenes Programm eine Meldung.</summary>
    class procedure Run; static;
    /// <summary>Für die Taste: False, wenn das Programm nicht angehalten ist (die Taste geht dann an die IDE).
    /// </summary>
    class function TryRun: Boolean; static;
    class procedure Dismiss; static;
  end;

implementation

uses
  System.Math,
  System.JSON,
  Vcl.Controls,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Debug.Visualizers,
  Atlas.UI.Strings,
  Atlas.UI.Popup.Window,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Projects.Context,
  Atlas.IDE.Debug.Evaluator;

function IsEditorWindow(AWnd: HWND): Boolean;
var
  Control: TWinControl;
begin
  Control := FindControl(AWnd);
  Result := (Control <> nil) and Control.ClassNameIs('TEditControl');
end;

/// <summary>Bildschirmstelle unter der Zeile mit der Schreibmarke (die IDE setzt sie beim Halt auf den
/// Ausführungspunkt).</summary>
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

{ TAtlasIdeStepInto }

constructor TAtlasIdeStepInto.Create(const ASession: TAtlasStepIntoSessionFunc; const AMessage: TProc<string>);
begin
  inherited Create;
  FSession := ASession;
  FMessage := AMessage;
  FFollowLine := -1;
  FMessages := TApplicationEvents.Create(nil);
  FMessages.OnMessage := AppMessage;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := TickMs;
  FTimer.OnTimer := Tick;
end;

destructor TAtlasIdeStepInto.Destroy;
begin
  FreeAndNil(FMessages);
  FreeAndNil(FTimer);
  // Beim Entladen mitten im Sprung: keine Haltepunkte zurücklassen.
  RemoveBreakpoints;
  FreeAndNil(FWindow);
  FRows := nil;
  FAnswer := Default(TAtlasStepAnswer);
  inherited;
end;

class procedure TAtlasIdeStepInto.Install(const ASession: TAtlasStepIntoSessionFunc; const AMessage: TProc<string>);
begin
  if FInstance = nil then
    FInstance := TAtlasIdeStepInto.Create(ASession, AMessage);
end;

class procedure TAtlasIdeStepInto.Uninstall;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeStepInto.Enabled: Boolean;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := Settings.Enabled and Settings.DebugStepIntoTarget;
end;

class function TAtlasIdeStepInto.Debugger: IOTADebuggerServices;
begin
  if not Supports(BorlandIDEServices, IOTADebuggerServices, Result) then
    Result := nil;
end;

class function TAtlasIdeStepInto.StoppedProcess: IOTAProcess;
var
  Services: IOTADebuggerServices;
begin
  Result := nil;
  Services := Debugger;
  if (Services = nil) or (Services.ProcessCount = 0) then
    Exit;
  Result := Services.CurrentProcess;
  if (Result <> nil) and not (Result.ProcessState in [psStopped, psFault, psException]) then
    Result := nil;
end;

class function TAtlasIdeStepInto.Stopped: Boolean;
begin
  Result := StoppedProcess <> nil;
end;

class function TAtlasIdeStepInto.Active: Boolean;
begin
  Result := (FInstance <> nil) and (FInstance.FWindow <> nil) and FInstance.FWindow.IsShown;
end;

class procedure TAtlasIdeStepInto.Run;
begin
  if FInstance = nil then
    Exit;
  if not Enabled then
  begin
    FInstance.Report(TAtlasStrings.Text(TAtlasTextId.StepIntoTargetOff));
    Exit;
  end;
  if not Stopped then
  begin
    FInstance.Report(TAtlasStrings.Text(TAtlasTextId.StepIntoTargetNotStopped));
    Exit;
  end;
  FInstance.Execute;
end;

class function TAtlasIdeStepInto.TryRun: Boolean;
begin
  Result := (FInstance <> nil) and Enabled and Stopped;
  if Result then
    FInstance.Execute;
end;

class procedure TAtlasIdeStepInto.Dismiss;
begin
  if FInstance <> nil then
    FInstance.Close;
end;

procedure TAtlasIdeStepInto.Report(const AText: string);
begin
  if Assigned(FMessage) then
    FMessage(AText);
end;

class function TAtlasIdeStepInto.Position(const AThread: IOTAThread; out AFileName: string;
  out ALine: Integer): Boolean;
begin
  AFileName := '';
  ALine := -1;
  if AThread = nil then
    Exit(False);
  AFileName := AThread.CurrentFile;
  ALine := Integer(AThread.CurrentLine) - 1;
  Result := (AFileName <> '') and (ALine >= 0);
end;

function TAtlasIdeStepInto.SourceText(const AFileName: string; out AText: string): Boolean;
var
  Buffer: IOTAEditBuffer;
begin
  Buffer := TAtlasIdeFiles.BufferOf(AFileName);
  if Buffer <> nil then
  begin
    AText := TAtlasEditorBuffer.Text(Buffer);
    Exit(True);
  end;
  try
    AText := TAtlasTextFile.Load(AFileName).Text;
    Result := True;
  except
    on E: EInOutError do
      Result := False;
    on E: EAtlasTextFileError do
      Result := False;
  end;
end;

class function TAtlasIdeStepInto.CanBreak(const AFileName: string): Boolean;
var
  Services: IOTAServices;
  Modules: IOTAModuleServices;
  Project: IOTAProject;
  Root, Value: string;
begin
  Result := True;
  if not Supports(BorlandIDEServices, IOTAServices, Services) then
    Exit;
  Root := Services.GetRootDirectory;
  if not TAtlasStepInto.IsLibraryFile(AFileName, Root) then
    Exit;
  // RTL, VCL und FMX: Haltepunkte greifen nur mit Debug-DCUs.
  Result := False;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  Project := Modules.GetActiveProject;
  if Project = nil then
    Exit;
  Value := TAtlasIdeProjectContext.ConfigurationValue(Project, Project.CurrentConfiguration, Project.CurrentPlatform,
    'DCC_DebugDCUs');
  Result := SameText(Trim(Value), 'true');
end;

class function TAtlasIdeStepInto.Evaluate(const AExpression: string; out AValue: string): Boolean;
begin
  // ClassName ist eine Klassenfunktion: Aufrufe erlauben. Der Empfänger selbst ruft nichts auf (receiverSimple).
  Result := TAtlasIdeDebugEvaluator.Evaluate(AExpression, TAtlasVisualizerEvaluation.Calls, EvaluateMs, AValue);
end;

function TAtlasIdeStepInto.Execute: Boolean;
var
  Process: IOTAProcess;
  Session: TLspSession;
  Line: Integer;
  Text: string;
  Answer: TJSONValue;
  Point: TPoint;
begin
  Result := True;
  Close;
  if FRunning then
    Exit;
  Process := StoppedProcess;
  if Process = nil then
  begin
    Report(TAtlasStrings.Text(TAtlasTextId.StepIntoTargetNotStopped));
    Exit;
  end;
  if not Position(Process.CurrentThread, FFileName, Line) or not SourceText(FFileName, Text) then
  begin
    Report(TAtlasStrings.Text(TAtlasTextId.StepIntoTargetNoSourceAt));
    Exit;
  end;
  Session := nil;
  if Assigned(FSession) then
    Session := FSession();
  if Session = nil then
  begin
    Report(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  try
    Session.Sync(FFileName, Text);
    Answer := Session.RunCommand(TAtlasStepInto.Command,
      TAtlasStepInto.Arguments(TLspSession.PathToUri(FFileName), Line), TimeoutMs);
    try
      if not TAtlasStepInto.ReadAnswer(Answer, FAnswer) then
        FAnswer := Default(TAtlasStepAnswer);
    finally
      Answer.Free;
    end;
  except
    on E: ELspClientError do
    begin
      Report(TAtlasStrings.Fmt(TAtlasTextId.StepIntoTargetFailed, [E.Message]));
      Exit;
    end;
  end;
  FRows := TAtlasStepInto.Rows(FAnswer,
    function(const AExpression: string; out AValue: string): Boolean
    begin
      Result := Evaluate(AExpression, AValue);
    end,
    function(const AFileName: string): Boolean
    begin
      Result := CanBreak(AFileName);
    end);
  // Höchstens ein Aufruf: wie F7.
  if TAtlasStepInto.ActsLikeStepInto(FRows) then
  begin
    StepInto;
    Exit;
  end;
  if TAtlasStepInto.NextAvailable(FRows, 0, 1) < 0 then
  begin
    Report(TAtlasStrings.Text(TAtlasTextId.StepIntoTargetNothing));
    StepInto;
    Exit;
  end;
  if FWindow = nil then
  begin
    FWindow := TAtlasStepIntoWindow.Create(nil);
    FWindow.OnAccept :=
      procedure(AIndex: Integer)
      begin
        TAtlasGuard.Run(TAtlasFeature.Debugger,
          procedure
          begin
            if FInstance <> nil then
              FInstance.Accept(AIndex);
          end);
      end;
    FWindow.OnCancel :=
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.Debugger,
          procedure
          begin
            if FInstance <> nil then
              FInstance.Close;
          end);
      end;
  end;
  Point := CaretPoint;
  FWindow.Colors := TAtlasIdeStyle.Colors;
  FWindow.SetScaling(TAtlasPopupWindow.MonitorPPI(Point), 1, '', 10);
  FWindow.ShowFor(FRows, Point);
end;

procedure TAtlasIdeStepInto.StepInto;
var
  Process: IOTAProcess;
begin
  Process := StoppedProcess;
  if Process <> nil then
    Process.Run(ormStmtStepInto);
end;

procedure TAtlasIdeStepInto.Close;
begin
  if (FWindow <> nil) and FWindow.IsShown then
    FWindow.Dismiss;
end;

procedure TAtlasIdeStepInto.Accept(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FRows)) or not FRows[AIndex].Available then
  begin
    Close;
    Exit;
  end;
  Close;
  Launch(FRows[AIndex]);
end;

class function TAtlasIdeStepInto.NewBreakpoint(const AFileName: string; ALine: Integer): IOTABreakpoint;
var
  Services: IOTADebuggerServices;
  Index: Integer;
  Existing: IOTASourceBreakpoint;
begin
  Result := nil;
  Services := Debugger;
  if (Services = nil) or (AFileName = '') or (ALine < 0) then
    Exit;
  // Ein Haltepunkt des Benutzers an derselben Stelle bleibt, wie er ist, und hält ohnehin.
  for Index := 0 to Services.SourceBkptCount - 1 do
  begin
    Existing := Services.SourceBkpts[Index];
    if (Existing <> nil) and SameText(Existing.FileName, AFileName) and (Existing.LineNumber = ALine + 1) then
      Exit;
  end;
  try
    Result := Services.NewSourceBreakpoint(AFileName, ALine + 1, nil);
  except
    on Exception do
      Result := nil;
  end;
end;

procedure TAtlasIdeStepInto.Launch(const ARow: TAtlasStepRow);
var
  Process: IOTAProcess;
begin
  Process := StoppedProcess;
  if Process = nil then
  begin
    Report(TAtlasStrings.Text(TAtlasTextId.StepIntoTargetNotStopped));
    Exit;
  end;
  Position(Process.CurrentThread, FStartFile, FStartLine);
  FTarget := ARow.Target;
  FCaption := ARow.Caption;
  FFollowLine := FAnswer.FollowLine;
  FTargetBreak := NewBreakpoint(FTarget.FileName, FTarget.Line);
  // Hält das Programm zuerst an der Folgeanweisung, ist der Aufruf nicht erfolgt.
  if (FFollowLine >= 0) and not (SameText(FTarget.FileName, FFileName) and (FTarget.Line = FFollowLine)) then
    FFollowBreak := NewBreakpoint(FFileName, FFollowLine);
  FRunning := True;
  FSeenRunning := False;
  FTimer.Enabled := True;
  Process.Run(ormRun);
end;

procedure TAtlasIdeStepInto.RemoveBreakpoints;
var
  Services: IOTADebuggerServices;
begin
  Services := Debugger;
  try
    if Services <> nil then
    begin
      if FTargetBreak <> nil then
        Services.RemoveBreakpoint(FTargetBreak);
      if FFollowBreak <> nil then
        Services.RemoveBreakpoint(FFollowBreak);
    end;
  finally
    FTargetBreak := nil;
    FFollowBreak := nil;
  end;
end;

procedure TAtlasIdeStepInto.Finish;
begin
  FTimer.Enabled := False;
  FRunning := False;
  RemoveBreakpoints;
end;

procedure TAtlasIdeStepInto.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger,
    procedure
    var
      Services: IOTADebuggerServices;
      Process: IOTAProcess;
      FileName: string;
      Line: Integer;
    begin
      if not FRunning then
      begin
        FTimer.Enabled := False;
        Exit;
      end;
      Services := Debugger;
      // Programm beendet: nur aufräumen.
      if (Services = nil) or (Services.ProcessCount = 0) then
      begin
        Finish;
        Exit;
      end;
      Process := Services.CurrentProcess;
      if Process = nil then
        Exit;
      if not (Process.ProcessState in [psStopped, psFault, psException]) then
      begin
        FSeenRunning := True;
        Exit;
      end;
      // Noch am Start und nie gelaufen: Run ist noch nicht angekommen.
      Position(Process.CurrentThread, FileName, Line);
      if not FSeenRunning and SameText(FileName, FStartFile) and (Line = FStartLine) then
        Exit;
      Finish;
      if SameText(FileName, FTarget.FileName) and (Line = FTarget.Line) then
        Exit;
      if SameText(FileName, FFileName) and (Line = FFollowLine) then
        Report(TAtlasStrings.Fmt(TAtlasTextId.StepIntoTargetNotCalled, [FCaption, FFollowLine + 1]))
      else if Process.ProcessState = psStopped then
        Report(TAtlasStrings.Fmt(TAtlasTextId.StepIntoTargetElsewhere, [ExtractFileName(FileName), Line + 1]));
    end);
end;

procedure TAtlasIdeStepInto.KeyDown(const Msg: TMsg; var Handled: Boolean);
var
  Key: Word;
begin
  if (FWindow = nil) or not FWindow.IsShown then
    Exit;
  Key := Word(Msg.wParam);
  if (Key = VK_SHIFT) or (Key = VK_CONTROL) or (Key = VK_MENU) then
    Exit;
  if (GetKeyState(VK_CONTROL) >= 0) and (GetKeyState(VK_MENU) >= 0) then
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
        begin
          FWindow.MoveRow(-1);
          Handled := True;
          Exit;
        end;
      VK_DOWN:
        begin
          FWindow.MoveRow(1);
          Handled := True;
          Exit;
        end;
      Ord('1')..Ord('9'):
        begin
          // Nicht wählbare Ziffer: Liste bleibt offen, die Taste geht nicht in den Editor.
          FWindow.AcceptDigit(Key - Ord('0'));
          Handled := True;
          Exit;
        end;
      VK_NUMPAD1..VK_NUMPAD9:
        begin
          FWindow.AcceptDigit(Key - VK_NUMPAD0);
          Handled := True;
          Exit;
        end;
    end;
  // Jede andere Taste schließt ohne Sprung und geht an den Editor.
  Close;
end;

procedure TAtlasIdeStepInto.AppMessage(var Msg: TMsg; var Handled: Boolean);
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Debugger) or (FWindow = nil) or not FWindow.IsShown then
    Exit;
  try
    case Msg.message of
      WM_KEYDOWN, WM_SYSKEYDOWN:
        if IsEditorWindow(Msg.hwnd) then
          KeyDown(Msg, Handled);
      WM_LBUTTONDOWN, WM_RBUTTONDOWN, WM_MBUTTONDOWN, WM_NCLBUTTONDOWN:
        if not FWindow.HandleAllocated or (Msg.hwnd <> FWindow.Handle) then
          Close;
    end;
  except
    // Keine Exception an die IDE (#493); die Nachricht geht dann normal weiter.
    on E: Exception do
    begin
      Handled := False;
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
    end;
  end;
end;

end.
