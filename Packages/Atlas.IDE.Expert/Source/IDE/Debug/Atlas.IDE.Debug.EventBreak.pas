unit Atlas.IDE.Debug.EventBreak;

// Beim nächsten Ereignis anhalten (#856) im Debugger der IDE. Welche Handler
// das Projekt hat, rechnet der Server (atlas.server.eventHandlers: Formulare
// und Zuweisungen im Code); die Auswahl trifft Atlas.Core.Debug.EventBreak,
// Dialog und Leiste zeichnet Atlas.UI.Debug.EventBreak. Hier bleiben:
// - Eintrag „Beim nächsten Ereignis anhalten…“ im Menü Start (RunMenu) und
//   der Befehl Atlas.BreakOnNextEvent; sichtbar nach debug.breakOnNextEvent.
//   Nur mit laufendem oder angehaltenem Programm.
// - Ein zweiter Aufruf während der Beobachtung beendet sie.
// - Je Stelle (erste Anweisung des Handlers) ein vorübergehender Haltepunkt
//   in der Gruppe Atlas.Ereignis;
//   Haltepunkte des Benutzers bleiben, wie sie sind. Ab 500 Stellen eine
//   Meldung, dass das Setzen dauern kann.
// - „Nur sichtbare Formulare“: Atlas hält das Programm kurz an (Pause), liest
//   Screen.Forms über Auswertungen und lässt es weiterlaufen. Geht das nicht,
//   gelten alle Formulare (Meldung).
// - Beim ersten Halt entfernt Atlas alle eigenen Haltepunkte. Hält das
//   Programm an einem Handler, nennt die Leiste Komponente, Ereignis und
//   Handler; teilen sich mehrere Komponenten den Handler, entscheidet
//   Sender.Name. „Weiter beobachten“ setzt dieselben Stellen neu und lässt das
//   Programm weiterlaufen. Hält es woanders, endet die Beobachtung mit einer
//   Meldung.
// - Die Wahl im Dialog gilt bis zum Neustart der IDE.
// Gesichert über TAtlasFeature.Debugger (#493). Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Menus,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Debug.EventBreak,
  Atlas.UI.Debug.EventBreak;

type
  TAtlasEventBreakSessionFunc = reference to function: TLspSession;

  TAtlasIdeEventBreak = class
  private const
    /// <summary>Der Server liest dafür alle Units und Formulare des Projekts.</summary>
    TimeoutMs = 30000;
    EvaluateMs = 1500;
    TickMs = 100;
    /// <summary>So lange wartet Atlas nach Pause auf den Halt (für die sichtbaren Formulare).</summary>
    PauseWaitMs = 3000;
  private type
    TPhase = (Idle, Pausing, Watching);
  private class var
    FInstance: TAtlasIdeEventBreak;
  private
    FSession: TAtlasEventBreakSessionFunc;
    FMessage: TProc<string>;
    FTimer: TTimer;
    FMenuItem: TMenuItem;
    FBar: TAtlasEventBreakBar;
    FChoice: TAtlasEventChoice;
    FAnswer: TAtlasEventAnswer;
    FPhase: TPhase;
    FPauseStarted: Cardinal;
    FLocations: TArray<TAtlasEventLocation>;
    FBreaks: TArray<IOTABreakpoint>;
    FSeenRunning: Boolean;
    FStartFile: string;
    FStartLine: Integer;
    procedure MenuClick(Sender: TObject);
    procedure Tick(Sender: TObject);
    procedure Execute;
    function Query: Boolean;
    function CountText(const AChoice: TAtlasEventChoice): string;
    function VisibleForms(out AForms: TArray<string>): Boolean;
    procedure Arm(const AChoice: TAtlasEventChoice; const AVisibleForms: TArray<string>);
    /// <summary>Sichtbare Formulare unbekannt: Meldung, dann alle Formulare.</summary>
    procedure ArmAllForms;
    procedure Watch;
    procedure Stopped(const AProcess: IOTAProcess);
    procedure KeepWatching;
    procedure Finish;
    procedure HideBar;
    procedure Report(const AText: string);
    procedure InstallMenu;
    procedure UpdateMenu;
    class function Evaluate(const AExpression: string; out AValue: string): Boolean; static;
  public
    constructor Create(const ASession: TAtlasEventBreakSessionFunc; const AMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>ASession liefert die laufende Sitzung (nil ohne), AMessage schreibt eine Zeile in die
    /// Meldungsansicht.</summary>
    class procedure Install(const ASession: TAtlasEventBreakSessionFunc; const AMessage: TProc<string>); static;
    class procedure Uninstall; static;
    /// <summary>debug.breakOnNextEvent an und Atlas an?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Läuft eine Beobachtung?</summary>
    class function Watching: Boolean; static;
    /// <summary>Befehl Atlas.BreakOnNextEvent (Menü Start, Palette); während der Beobachtung beendet er sie.
    /// </summary>
    class procedure Run; static;
    /// <summary>Sichtbarkeit des Menüeintrags nach geänderten Einstellungen.</summary>
    class procedure ApplySettings; static;
  end;

implementation

uses
  Winapi.Windows,
  System.JSON,
  Vcl.Controls,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.EventBreakNames,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Settings.VisualizerKinds,
  Atlas.UI.Strings,
  Atlas.UI.Popup.Window,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.IDE.Debug.Evaluator,
  Atlas.IDE.Debug.Breakpoints;

const
  MenuItemName = 'AtlasBreakOnNextEventItem';
  BreakpointGroup = 'Atlas.Ereignis';

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

function RunMenu: TMenuItem;
var
  Services: INTAServices;
  Index: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, INTAServices, Services) or (Services.MainMenu = nil) then
    Exit;
  for Index := 0 to Services.MainMenu.Items.Count - 1 do
    if SameText(Services.MainMenu.Items[Index].Name, 'RunMenu') then
      Exit(Services.MainMenu.Items[Index]);
end;

{ TAtlasIdeEventBreak }

constructor TAtlasIdeEventBreak.Create(const ASession: TAtlasEventBreakSessionFunc; const AMessage: TProc<string>);
begin
  inherited Create;
  FSession := ASession;
  FMessage := AMessage;
  FChoice := TAtlasEventChoice.Defaults;
  FStartLine := -1;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := TickMs;
  FTimer.OnTimer := Tick;
  InstallMenu;
end;

destructor TAtlasIdeEventBreak.Destroy;
begin
  FreeAndNil(FTimer);
  // Beim Entladen mitten in der Beobachtung: keine Haltepunkte zurücklassen.
  TAtlasIdeBreakpoints.RemoveAll(FBreaks);
  FreeAndNil(FBar);
  FreeAndNil(FMenuItem);
  FLocations := nil;
  FAnswer := Default(TAtlasEventAnswer);
  inherited;
end;

class procedure TAtlasIdeEventBreak.Install(const ASession: TAtlasEventBreakSessionFunc;
  const AMessage: TProc<string>);
begin
  if FInstance = nil then
    FInstance := TAtlasIdeEventBreak.Create(ASession, AMessage);
end;

class procedure TAtlasIdeEventBreak.Uninstall;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeEventBreak.Enabled: Boolean;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := Settings.Enabled and Settings.DebugBreakOnNextEvent;
end;

class function TAtlasIdeEventBreak.Watching: Boolean;
begin
  Result := (FInstance <> nil) and (FInstance.FPhase <> TPhase.Idle);
end;

class procedure TAtlasIdeEventBreak.Run;
begin
  if FInstance = nil then
    Exit;
  if not Enabled then
  begin
    FInstance.Report(TAtlasStrings.Text(TAtlasTextId.EventBreakOff));
    Exit;
  end;
  FInstance.Execute;
end;

class procedure TAtlasIdeEventBreak.ApplySettings;
begin
  if FInstance = nil then
    Exit;
  FInstance.UpdateMenu;
  // Ausgeschaltet während der Beobachtung: Haltepunkte gleich entfernen.
  if not Enabled and (FInstance.FPhase <> TPhase.Idle) then
    FInstance.Finish;
end;

procedure TAtlasIdeEventBreak.InstallMenu;
var
  Parent: TMenuItem;
begin
  Parent := RunMenu;
  if Parent = nil then
    Exit;
  FMenuItem := TMenuItem.Create(nil);
  FMenuItem.Name := MenuItemName;
  FMenuItem.Caption := TAtlasStrings.Text(TAtlasTextId.EventBreakCommand);
  FMenuItem.OnClick := MenuClick;
  Parent.Add(FMenuItem);
  UpdateMenu;
end;

procedure TAtlasIdeEventBreak.UpdateMenu;
begin
  if FMenuItem <> nil then
    FMenuItem.Visible := Enabled;
end;

procedure TAtlasIdeEventBreak.MenuClick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger,
    procedure
    begin
      Run;
    end);
end;

procedure TAtlasIdeEventBreak.Report(const AText: string);
begin
  if Assigned(FMessage) then
    FMessage(AText);
end;

class function TAtlasIdeEventBreak.Evaluate(const AExpression: string; out AValue: string): Boolean;
begin
  // ClassName und die Eigenschaften von Screen sind Aufrufe: erlauben.
  Result := TAtlasIdeDebugEvaluator.Evaluate(AExpression, TAtlasVisualizerEvaluation.Calls, EvaluateMs, AValue);
end;

function TAtlasIdeEventBreak.Query: Boolean;
var
  Session: TLspSession;
  Project: string;
  Answer: TJSONValue;
begin
  Result := False;
  Session := nil;
  if Assigned(FSession) then
    Session := FSession();
  if Session = nil then
  begin
    Report(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  Project := TAtlasIdeTeamFile.ActiveProject;
  try
    Answer := Session.RunCommand(TAtlasEventBreak.Command, TAtlasEventBreak.Arguments(TLspSession.PathToUri(Project)),
      TimeoutMs);
    try
      if not TAtlasEventBreak.ReadAnswer(Answer, FAnswer) then
        FAnswer := Default(TAtlasEventAnswer);
    finally
      Answer.Free;
    end;
  except
    on E: ELspClientError do
    begin
      Report(TAtlasStrings.Fmt(TAtlasTextId.EventBreakFailed, [E.Message]));
      Exit;
    end;
  end;
  if Length(FAnswer.Handlers) = 0 then
  begin
    Report(TAtlasStrings.Text(TAtlasTextId.EventBreakNoHandlers));
    Exit;
  end;
  Result := True;
end;

function TAtlasIdeEventBreak.CountText(const AChoice: TAtlasEventChoice): string;
var
  Choice: TAtlasEventChoice;
  Selected: TArray<Integer>;
begin
  // Welche Formulare sichtbar sind, steht erst beim Start fest: bis dahin zählen alle.
  Choice := AChoice;
  if Choice.Scope = TAtlasEventScope.VisibleForms then
    Choice.Scope := TAtlasEventScope.AllForms;
  Selected := TAtlasEventBreak.Select(FAnswer.Handlers, Choice,
    TAtlasEventBreakSettings.ExcludedList(TAtlasIdeSettings.Current.DebugBreakOnNextEventExcluded), nil);
  Result := TAtlasStrings.Fmt(TAtlasTextId.EventBreakCount,
    [Length(Selected), Length(TAtlasEventBreak.Locations(FAnswer.Handlers, Selected))]);
end;

procedure TAtlasIdeEventBreak.Execute;
var
  Process: IOTAProcess;
  Choice: TAtlasEventChoice;
  Forms: TArray<string>;
begin
  HideBar;
  // Zweiter Aufruf: Beobachtung beenden.
  if FPhase <> TPhase.Idle then
  begin
    Finish;
    Report(TAtlasStrings.Text(TAtlasTextId.EventBreakCancelled));
    Exit;
  end;
  Process := TAtlasIdeBreakpoints.CurrentProcess;
  if Process = nil then
  begin
    Report(TAtlasStrings.Text(TAtlasTextId.EventBreakNoProcess));
    Exit;
  end;
  if not Query then
    Exit;
  Choice := FChoice;
  if not TAtlasEventBreakDialog.Execute(Choice, TAtlasEventBreak.Forms(FAnswer.Handlers),
    TAtlasIdeSettings.Current.DebugBreakOnNextEventExcluded,
    function(const AChoice: TAtlasEventChoice): string
    begin
      Result := CountText(AChoice);
    end) then
    Exit;
  FChoice := Choice;
  if FAnswer.Unresolved > 0 then
    Report(TAtlasStrings.Fmt(TAtlasTextId.EventBreakUnresolved, [FAnswer.Unresolved]));
  // Der Dialog war modal: Das Programm kann inzwischen beendet sein.
  Process := TAtlasIdeBreakpoints.CurrentProcess;
  if Process = nil then
  begin
    Report(TAtlasStrings.Text(TAtlasTextId.EventBreakNoProcess));
    Exit;
  end;
  if FChoice.Scope <> TAtlasEventScope.VisibleForms then
  begin
    Arm(FChoice, nil);
    Exit;
  end;
  if TAtlasIdeBreakpoints.IsStopped(Process) then
  begin
    if VisibleForms(Forms) then
      Arm(FChoice, Forms)
    else
      ArmAllForms;
    Exit;
  end;
  // Programm läuft: kurz anhalten, im Takt auf den Halt warten, dann Formulare lesen.
  FPhase := TPhase.Pausing;
  FPauseStarted := GetTickCount;
  FTimer.Enabled := True;
  try
    Process.Pause;
  except
    on E: Exception do
    begin
      FPhase := TPhase.Idle;
      ArmAllForms;
    end;
  end;
end;

function TAtlasIdeEventBreak.VisibleForms(out AForms: TArray<string>): Boolean;
var
  Value: string;
  Count, Index: Integer;
begin
  AForms := nil;
  Result := Evaluate(TAtlasEventBreak.FormCountExpression, Value) and TryStrToInt(Trim(Value), Count) and
    (Count >= 0);
  if not Result then
    Exit;
  for Index := 0 to Count - 1 do
  begin
    if not Evaluate(TAtlasEventBreak.FormVisibleExpression(Index), Value) then
      Exit(False);
    if not SameText(Trim(Value), 'True') then
      Continue;
    if not Evaluate(TAtlasEventBreak.FormClassExpression(Index), Value) then
      Exit(False);
    AForms := AForms + [TAtlasEventBreak.Unquote(Value)];
  end;
end;

procedure TAtlasIdeEventBreak.ArmAllForms;
var
  Choice: TAtlasEventChoice;
begin
  Report(TAtlasStrings.Text(TAtlasTextId.EventBreakVisibleUnknown));
  // Nur für diese Beobachtung; die Wahl im Dialog bleibt „sichtbare Formulare“.
  Choice := FChoice;
  Choice.Scope := TAtlasEventScope.AllForms;
  Arm(Choice, nil);
end;

procedure TAtlasIdeEventBreak.Arm(const AChoice: TAtlasEventChoice; const AVisibleForms: TArray<string>);
var
  Selected: TArray<Integer>;
begin
  FPhase := TPhase.Idle;
  Selected := TAtlasEventBreak.Select(FAnswer.Handlers, AChoice,
    TAtlasEventBreakSettings.ExcludedList(TAtlasIdeSettings.Current.DebugBreakOnNextEventExcluded), AVisibleForms);
  FLocations := TAtlasEventBreak.Locations(FAnswer.Handlers, Selected);
  if Length(FLocations) = 0 then
  begin
    FTimer.Enabled := False;
    Report(TAtlasStrings.Text(TAtlasTextId.EventBreakNoHandlers));
    Exit;
  end;
  if Length(FLocations) > TAtlasEventBreak.ManyBreakpoints then
    Report(TAtlasStrings.Fmt(TAtlasTextId.EventBreakMany, [Length(FLocations)]));
  Watch;
  Report(TAtlasStrings.Fmt(TAtlasTextId.EventBreakWatching, [Length(FLocations)]));
end;

procedure TAtlasIdeEventBreak.Watch;
var
  Process: IOTAProcess;
  Location: TAtlasEventLocation;
  Breakpoint: IOTABreakpoint;
begin
  TAtlasIdeBreakpoints.RemoveAll(FBreaks);
  for Location in FLocations do
  begin
    Breakpoint := TAtlasIdeBreakpoints.Add(Location.FileName, Location.Line, BreakpointGroup);
    if Breakpoint <> nil then
      FBreaks := FBreaks + [Breakpoint];
  end;
  FPhase := TPhase.Watching;
  FSeenRunning := False;
  FStartFile := '';
  FStartLine := -1;
  FTimer.Enabled := True;
  Process := TAtlasIdeBreakpoints.CurrentProcess;
  if TAtlasIdeBreakpoints.IsStopped(Process) then
  begin
    TAtlasIdeBreakpoints.Position(Process.CurrentThread, FStartFile, FStartLine);
    Process.Run(ormRun);
  end
  else
    FSeenRunning := True;
end;

procedure TAtlasIdeEventBreak.KeepWatching;
begin
  HideBar;
  if TAtlasIdeBreakpoints.CurrentProcess = nil then
  begin
    Report(TAtlasStrings.Text(TAtlasTextId.EventBreakEnded));
    Exit;
  end;
  if Length(FLocations) > 0 then
    Watch;
end;

procedure TAtlasIdeEventBreak.Finish;
begin
  FTimer.Enabled := False;
  FPhase := TPhase.Idle;
  TAtlasIdeBreakpoints.RemoveAll(FBreaks);
end;

procedure TAtlasIdeEventBreak.HideBar;
begin
  if (FBar <> nil) and FBar.IsShown then
    FBar.Dismiss;
end;

procedure TAtlasIdeEventBreak.Stopped(const AProcess: IOTAProcess);
var
  FileName, Sender: string;
  Line, Found, Identified: Integer;
  Point: TPoint;
begin
  TAtlasIdeBreakpoints.Position(AProcess.CurrentThread, FileName, Line);
  // Erster Halt, gleich wo: eigene Haltepunkte entfernen (FLocations bleibt für „Weiter beobachten“).
  Finish;
  Found := TAtlasEventBreak.LocationAt(FLocations, FileName, Line);
  if Found < 0 then
  begin
    if AProcess.ProcessState = psStopped then
      Report(TAtlasStrings.Fmt(TAtlasTextId.EventBreakElsewhere, [ExtractFileName(FileName), Line + 1]));
    Exit;
  end;
  Identified := -1;
  if Length(FLocations[Found].Handlers) > 1 then
  begin
    if Evaluate('Sender.Name', Sender) then
      Identified := TAtlasEventBreak.Identify(FAnswer.Handlers, FLocations[Found], TAtlasEventBreak.Unquote(Sender));
  end
  else
    Identified := FLocations[Found].Handlers[0];
  Report(TAtlasStrings.Fmt(TAtlasTextId.EventBreakStopped,
    [TAtlasEventBreak.Caption(FAnswer.Handlers, FLocations[Found], Identified)]));
  if FBar = nil then
  begin
    FBar := TAtlasEventBreakBar.Create(nil);
    FBar.OnContinue :=
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.Debugger,
          procedure
          begin
            if FInstance <> nil then
              FInstance.KeepWatching;
          end);
      end;
    FBar.OnClose :=
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.Debugger,
          procedure
          begin
            if FInstance <> nil then
              FInstance.HideBar;
          end);
      end;
  end;
  Point := CaretPoint;
  FBar.Colors := TAtlasIdeStyle.Colors;
  FBar.SetScaling(TAtlasPopupWindow.MonitorPPI(Point), 1, '', 10);
  FBar.ShowFor(TAtlasEventBreak.Caption(FAnswer.Handlers, FLocations[Found], Identified), Point);
  // Im Takt bleiben, um die Leiste zu schließen, sobald das Programm weiterläuft.
  FTimer.Enabled := True;
end;

procedure TAtlasIdeEventBreak.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger,
    procedure
    var
      Process: IOTAProcess;
      Forms: TArray<string>;
      FileName: string;
      Line: Integer;
    begin
      Process := TAtlasIdeBreakpoints.CurrentProcess;
      // Programm beendet: aufräumen.
      if Process = nil then
      begin
        HideBar;
        if FPhase <> TPhase.Idle then
        begin
          Finish;
          Report(TAtlasStrings.Text(TAtlasTextId.EventBreakEnded));
        end;
        FTimer.Enabled := False;
        Exit;
      end;
      case FPhase of
        TPhase.Pausing:
          begin
            if not TAtlasIdeBreakpoints.IsStopped(Process) then
            begin
              if GetTickCount - FPauseStarted < PauseWaitMs then
                Exit;
              // Kein Halt nach Pause: alle Formulare.
              ArmAllForms;
              Exit;
            end;
            if VisibleForms(Forms) then
              Arm(FChoice, Forms)
            else
              ArmAllForms;
          end;
        TPhase.Watching:
          begin
            if not TAtlasIdeBreakpoints.IsStopped(Process) then
            begin
              FSeenRunning := True;
              Exit;
            end;
            // Noch am Start und nie gelaufen: Run ist noch nicht angekommen.
            TAtlasIdeBreakpoints.Position(Process.CurrentThread, FileName, Line);
            if not FSeenRunning and SameText(FileName, FStartFile) and (Line = FStartLine) then
              Exit;
            Stopped(Process);
          end;
      else
        // Leiste zu, sobald das Programm wieder läuft.
        if not TAtlasIdeBreakpoints.IsStopped(Process) then
        begin
          HideBar;
          FTimer.Enabled := False;
        end;
      end;
    end);
end;

end.
