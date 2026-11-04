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
  private type
    TJumpState = record
      Running: Boolean;
      SeenRunning: Boolean;
      StartFile: string;
      StartLine: Integer;
      Caption: string;
      Target: TAtlasStepTarget;
      FollowLine: Integer;
    end;
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
    FJump: TJumpState;
    /// <summary>Vorübergehende Haltepunkte auf Ziel und Folgeanweisung.</summary>
    FBreaks: TArray<IOTABreakpoint>;
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
    procedure KeyDown(const Msg: TMsg; var Handled: Boolean);
    procedure Tick(Sender: TObject);
    function Execute: Boolean;
    /// <summary>Aufrufe der Zeile ALine von FFileName (Text AText) beim Server erfragen; False mit Meldung.</summary>
    function Query(ALine: Integer; const AText: string): Boolean;
    /// <summary>Zeilen bilden; bei höchstens einem Ziel wie F7, sonst die Liste zeigen.</summary>
    procedure Offer;
    procedure ShowWindow;
    procedure Step;
    /// <summary>Halt nach dem Sprung: Ziel erreicht, Folgeanweisung oder anderswo.</summary>
    procedure Arrived(const AProcess: IOTAProcess);
    procedure Accept(AIndex: Integer);
    procedure Launch(const ARow: TAtlasStepRow);
    procedure StepInto;
    procedure Close;
    procedure Finish;
    procedure RemoveBreakpoints;
    procedure Report(const AText: string);
    function SourceText(const AFileName: string; out AText: string): Boolean;
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
  Atlas.Core.Settings.VisualizerKinds,
  Atlas.UI.Strings,
  Atlas.UI.Debug.Strings,
  Atlas.UI.Popup.Window,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Projects.Context,
  Atlas.IDE.Debug.Evaluator,
  Atlas.IDE.Debug.Breakpoints;

function IsEditorWindow(AWnd: HWND): Boolean;
var
  Control: TWinControl;
begin
  Control := FindControl(AWnd);
  Result := (Control <> nil) and Control.ClassNameIs('TEditControl');
end;

/// <summary>Taste AKey in der offenen Liste ausführen; False, wenn die Liste sie nicht kennt.</summary>
function ListKey(AWindow: TAtlasStepIntoWindow; AKey: Word): Boolean;
begin
  Result := True;
  case AKey of
    VK_RETURN:
      AWindow.Accept;
    VK_ESCAPE:
      AWindow.Cancel;
    VK_UP:
      AWindow.MoveRow(-1);
    VK_DOWN:
      AWindow.MoveRow(1);
    // Nicht wählbare Ziffer: Liste bleibt offen, die Taste geht nicht in den Editor.
    Ord('1')..Ord('9'):
      AWindow.AcceptDigit(AKey - Ord('0'));
    VK_NUMPAD1..VK_NUMPAD9:
      AWindow.AcceptDigit(AKey - VK_NUMPAD0);
  else
    Result := False;
  end;
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
  FJump.FollowLine := -1;
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
  begin
    FInstance := TAtlasIdeStepInto.Create(ASession, AMessage);
  end;
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

class function TAtlasIdeStepInto.Stopped: Boolean;
begin
  Result := TAtlasIdeBreakpoints.StoppedProcess <> nil;
end;

class function TAtlasIdeStepInto.Active: Boolean;
begin
  Result := (FInstance <> nil) and (FInstance.FWindow <> nil) and FInstance.FWindow.IsShown;
end;

class procedure TAtlasIdeStepInto.Run;
begin
  if FInstance = nil then
  begin
    Exit;
  end;
  if not Enabled then
  begin
    FInstance.Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.StepIntoTargetOff));
    Exit;
  end;
  if not Stopped then
  begin
    FInstance.Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.StepIntoTargetNotStopped));
    Exit;
  end;
  FInstance.Execute;
end;

class function TAtlasIdeStepInto.TryRun: Boolean;
begin
  Result := (FInstance <> nil) and Enabled and Stopped;
  if Result then
  begin
    FInstance.Execute;
  end;
end;

class procedure TAtlasIdeStepInto.Dismiss;
begin
  if FInstance <> nil then
  begin
    FInstance.Close;
  end;
end;

procedure TAtlasIdeStepInto.Report(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
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
  begin
    Exit;
  end;
  Root := Services.GetRootDirectory;
  if not TAtlasStepInto.IsLibraryFile(AFileName, Root) then
  begin
    Exit;
  end;
  // RTL, VCL und FMX: Haltepunkte greifen nur mit Debug-DCUs.
  Result := False;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
  begin
    Exit;
  end;
  Project := Modules.GetActiveProject;
  if Project = nil then
  begin
    Exit;
  end;
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
  mProcess: IOTAProcess;
  mLine: Integer;
  mText: string;
begin
  Result := True;
  Close;
  if FJump.Running then
  begin
    Exit;
  end;
  mProcess := TAtlasIdeBreakpoints.StoppedProcess;
  if mProcess = nil then
  begin
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.StepIntoTargetNotStopped));
  end
  else if not TAtlasIdeBreakpoints.Position(mProcess.CurrentThread, FFileName, mLine) or
    not SourceText(FFileName, mText) then
  begin
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.StepIntoTargetNoSourceAt));
  end
  else if Query(mLine, mText) then
  begin
    Offer;
  end;
end;

function TAtlasIdeStepInto.Query(ALine: Integer; const AText: string): Boolean;
var
  mSession: TLspSession;
  mAnswer: TJSONValue;
begin
  Result := False;
  mSession := nil;
  if Assigned(FSession) then
  begin
    mSession := FSession();
  end;
  if mSession = nil then
  begin
    Report(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  try
    mSession.Sync(FFileName, AText);
    mAnswer := mSession.RunCommand(TAtlasStepInto.Command,
      TAtlasStepInto.Arguments(TLspSession.PathToUri(FFileName), ALine), TimeoutMs);
    try
      if not TAtlasStepInto.ReadAnswer(mAnswer, FAnswer) then
      begin
        FAnswer := Default(TAtlasStepAnswer);
      end;
    finally
      mAnswer.Free;
    end;
    Result := True;
  except
    on E: ELspClientError do
    begin
      Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.StepIntoTargetFailed, [E.Message]));
    end;
  end;
end;

procedure TAtlasIdeStepInto.Offer;
begin
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
  end
  else if TAtlasStepInto.NextAvailable(FRows, 0, 1) < 0 then
  begin
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.StepIntoTargetNothing));
    StepInto;
  end
  else
  begin
    ShowWindow;
  end;
end;

procedure TAtlasIdeStepInto.ShowWindow;
var
  mPoint: TPoint;
begin
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
            begin
              FInstance.Accept(AIndex);
            end;
          end);
      end;
    FWindow.OnCancel :=
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.Debugger,
          procedure
          begin
            if FInstance <> nil then
            begin
              FInstance.Close;
            end;
          end);
      end;
  end;
  mPoint := CaretPoint;
  FWindow.Colors := TAtlasIdeStyle.Colors;
  FWindow.SetScaling(TAtlasPopupWindow.MonitorPPI(mPoint), 1, '', 10);
  FWindow.ShowFor(FRows, mPoint);
end;

procedure TAtlasIdeStepInto.StepInto;
var
  Process: IOTAProcess;
begin
  Process := TAtlasIdeBreakpoints.StoppedProcess;
  if Process <> nil then
  begin
    Process.Run(ormStmtStepInto);
  end;
end;

procedure TAtlasIdeStepInto.Close;
begin
  if (FWindow <> nil) and FWindow.IsShown then
  begin
    FWindow.Dismiss;
  end;
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

procedure TAtlasIdeStepInto.Launch(const ARow: TAtlasStepRow);
var
  Process: IOTAProcess;
begin
  Process := TAtlasIdeBreakpoints.StoppedProcess;
  if Process = nil then
  begin
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.StepIntoTargetNotStopped));
    Exit;
  end;
  TAtlasIdeBreakpoints.Position(Process.CurrentThread, FJump.StartFile, FJump.StartLine);
  FJump.Target := ARow.Target;
  FJump.Caption := ARow.Caption;
  FJump.FollowLine := FAnswer.FollowLine;
  FBreaks := [TAtlasIdeBreakpoints.Add(FJump.Target.FileName, FJump.Target.Line)];
  // Hält das Programm zuerst an der Folgeanweisung, ist der Aufruf nicht erfolgt.
  if (FJump.FollowLine >= 0) and
    not (SameText(FJump.Target.FileName, FFileName) and (FJump.Target.Line = FJump.FollowLine)) then
  begin
    FBreaks := FBreaks + [TAtlasIdeBreakpoints.Add(FFileName, FJump.FollowLine)];
  end;
  FJump.Running := True;
  FJump.SeenRunning := False;
  FTimer.Enabled := True;
  Process.Run(ormRun);
end;

procedure TAtlasIdeStepInto.RemoveBreakpoints;
begin
  TAtlasIdeBreakpoints.RemoveAll(FBreaks);
end;

procedure TAtlasIdeStepInto.Finish;
begin
  FTimer.Enabled := False;
  FJump.Running := False;
  RemoveBreakpoints;
end;

procedure TAtlasIdeStepInto.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger,
    procedure
    begin
      Step;
    end);
end;

procedure TAtlasIdeStepInto.Step;
var
  mServices: IOTADebuggerServices;
  mProcess: IOTAProcess;
begin
  if not FJump.Running then
  begin
    FTimer.Enabled := False;
    Exit;
  end;
  mServices := TAtlasIdeBreakpoints.Debugger;
  if (mServices = nil) or (mServices.ProcessCount = 0) then
  begin
    // Programm beendet: nur aufräumen.
    Finish;
    Exit;
  end;
  mProcess := mServices.CurrentProcess;
  if mProcess = nil then
  begin
    Exit;
  end;
  if not (mProcess.ProcessState in [psStopped, psFault, psException]) then
  begin
    FJump.SeenRunning := True;
  end
  else
  begin
    Arrived(mProcess);
  end;
end;

procedure TAtlasIdeStepInto.Arrived(const AProcess: IOTAProcess);
var
  mFileName: string;
  mLine: Integer;
begin
  // Noch am Start und nie gelaufen: Run ist noch nicht angekommen.
  TAtlasIdeBreakpoints.Position(AProcess.CurrentThread, mFileName, mLine);
  if not FJump.SeenRunning and SameText(mFileName, FJump.StartFile) and (mLine = FJump.StartLine) then
  begin
    Exit;
  end;
  Finish;
  if SameText(mFileName, FJump.Target.FileName) and (mLine = FJump.Target.Line) then
  begin
    Exit;
  end;
  if SameText(mFileName, FFileName) and (mLine = FJump.FollowLine) then
  begin
    Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.StepIntoTargetNotCalled, [FJump.Caption,
      FJump.FollowLine + 1]));
  end
  else if AProcess.ProcessState = psStopped then
  begin
    Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.StepIntoTargetElsewhere,
      [ExtractFileName(mFileName), mLine + 1]));
  end;
end;

procedure TAtlasIdeStepInto.KeyDown(const Msg: TMsg; var Handled: Boolean);
var
  mKey: Word;
begin
  if (FWindow = nil) or not FWindow.IsShown then
  begin
    Exit;
  end;
  mKey := Word(Msg.wParam);
  if (mKey = VK_SHIFT) or (mKey = VK_CONTROL) or (mKey = VK_MENU) then
  begin
    Exit;
  end;
  if (GetKeyState(VK_CONTROL) >= 0) and (GetKeyState(VK_MENU) >= 0) and ListKey(FWindow, mKey) then
  begin
    Handled := True;
  end
  else
  begin
    // Jede andere Taste schließt ohne Sprung und geht an den Editor.
    Close;
  end;
end;

procedure TAtlasIdeStepInto.AppMessage(var Msg: TMsg; var Handled: Boolean);
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Debugger) or (FWindow = nil) or not FWindow.IsShown then
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
        if not FWindow.HandleAllocated or (Msg.hwnd <> FWindow.Handle) then
        begin
          Close;
        end;
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
