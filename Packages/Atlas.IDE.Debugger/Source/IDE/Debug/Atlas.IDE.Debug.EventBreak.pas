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
    cTimeoutMs = 30000;
    cEvaluateMs = 1500;
    cTickMs = 100;
    /// <summary>So lange wartet Atlas nach Pause auf den Halt (für die sichtbaren Formulare).</summary>
    cPauseWaitMs = 3000;
  private type
    TPhase = (Idle, Pausing, Watching);
    TWatchState = record
      Phase: TPhase;
      PauseStarted: Cardinal;
      SeenRunning: Boolean;
      StartFile: string;
      StartLine: Integer;
    end;
    /// <summary>Gesetzte Haltepunkte und die Orte dazu (bleiben für „Weiter beobachten“).</summary>
    TArmedState = record
      Locations: TArray<TAtlasEventLocation>;
      Breaks: TArray<IOTABreakpoint>;
    end;
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
    FWatch: TWatchState;
    FArmed: TArmedState;
    procedure MenuClick(Sender: TObject);
    procedure Tick(Sender: TObject);
    procedure Execute;
    /// <summary>Server fragen und Auswahl im Dialog; False bei Abbruch oder ohne Prozess.</summary>
    function Choose(out AProcess: IOTAProcess): Boolean;
    /// <summary>Haltepunkte nach FChoice setzen; laufendes Programm erst anhalten.</summary>
    procedure ArmFor(const AProcess: IOTAProcess);
    procedure ArmVisibleForms;
    procedure Step;
    procedure ShowBar(const ACaption: string);
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
    procedure Report(AText: string);
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
  Atlas.UI.Debug.Strings,
  Atlas.UI.Popup.Window,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.IDE.Debug.Evaluator,
  Atlas.IDE.Debug.Breakpoints;

const
  cMenuItemName = 'AtlasBreakOnNextEventItem';
  cBreakpointGroup = 'Atlas.Ereignis';

/// <summary>Bildschirmstelle unter der Zeile mit der Schreibmarke (die IDE setzt sie beim Halt auf den
/// Ausführungspunkt).</summary>
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

function RunMenu: TMenuItem;
var
  mServices: INTAServices;
  mIndex: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, INTAServices, mServices) or (mServices.MainMenu = nil) then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.MainMenu.Items.Count - 1 do
  begin
    if SameText(mServices.MainMenu.Items[mIndex].Name, 'RunMenu') then
    begin
      Exit(mServices.MainMenu.Items[mIndex]);
    end;
  end;
end;

/// <summary>Laufender Prozess; ohne ihn eine Meldung an AReport.</summary>
function CurrentProcess(out AProcess: IOTAProcess; const AReport: TProc<string>): Boolean;
begin
  AProcess := TAtlasIdeBreakpoints.CurrentProcess;
  Result := AProcess <> nil;
  if not Result then
  begin
    AReport(TAtlasDebugStrings.Text(TAtlasDebugTextId.EventBreakNoProcess));
  end;
end;

/// <summary>Behandler am Halt in ALocation; bei mehreren nach Sender.Name, -1 wenn nicht bestimmbar.</summary>
function IdentifyHandler(const AAnswer: TAtlasEventAnswer; const ALocation: TAtlasEventLocation): Integer;
var
  mSender: string;
begin
  Result := -1;
  if Length(ALocation.Handlers) <= 1 then
  begin
    Result := ALocation.Handlers[0];
  end
  else if TAtlasIdeEventBreak.Evaluate('Sender.Name', mSender) then
  begin
    Result := TAtlasEventBreak.Identify(AAnswer.Handlers, ALocation, TAtlasEventBreak.Unquote(mSender));
  end;
end;

type
  /// <summary>Stand nach Pause: noch warten, hält, oder PauseWaitMs ohne Halt vorbei.</summary>
  TPauseOutcome = (Waiting, Stopped, TimedOut);

function PauseOutcome(const AProcess: IOTAProcess; AStarted: Cardinal): TPauseOutcome;
begin
  Result := TPauseOutcome.Waiting;
  if TAtlasIdeBreakpoints.IsStopped(AProcess) then
  begin
    Result := TPauseOutcome.Stopped;
  end
  else if GetTickCount - AStarted >= TAtlasIdeEventBreak.cPauseWaitMs then
  begin
    Result := TPauseOutcome.TimedOut;
  end;
end;

/// <summary>Hält das Programm an einem neuen Ort? Noch am Start und nie gelaufen: Run ist noch nicht angekommen.
/// </summary>
function StoppedAnew(const AProcess: IOTAProcess; var AWatch: TAtlasIdeEventBreak.TWatchState): Boolean;
var
  mFileName: string;
  mLine: Integer;
begin
  Result := False;
  if not TAtlasIdeBreakpoints.IsStopped(AProcess) then
  begin
    AWatch.SeenRunning := True;
    Exit;
  end;
  TAtlasIdeBreakpoints.Position(AProcess.CurrentThread, mFileName, mLine);
  Result := AWatch.SeenRunning or not SameText(mFileName, AWatch.StartFile) or (mLine <> AWatch.StartLine);
end;

{ TAtlasIdeEventBreak }

constructor TAtlasIdeEventBreak.Create(const ASession: TAtlasEventBreakSessionFunc; const AMessage: TProc<string>);
begin
  inherited Create;
  FSession := ASession;
  FMessage := AMessage;
  FChoice := TAtlasEventChoice.Defaults;
  FWatch.StartLine := -1;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := Tick;
  InstallMenu;
end;

destructor TAtlasIdeEventBreak.Destroy;
begin
  FreeAndNil(FTimer);
  // Beim Entladen mitten in der Beobachtung: keine Haltepunkte zurücklassen.
  TAtlasIdeBreakpoints.RemoveAll(FArmed.Breaks);
  FreeAndNil(FBar);
  FreeAndNil(FMenuItem);
  FArmed.Locations := nil;
  FAnswer := Default(TAtlasEventAnswer);
  inherited;
end;

class procedure TAtlasIdeEventBreak.Install(const ASession: TAtlasEventBreakSessionFunc;
  const AMessage: TProc<string>);
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeEventBreak.Create(ASession, AMessage);
  end;
end;

class procedure TAtlasIdeEventBreak.Uninstall;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeEventBreak.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.DebugBreakOnNextEvent;
end;

class procedure TAtlasIdeEventBreak.Run;
begin
  if FInstance = nil then
  begin
    Exit;
  end;
  if not Enabled then
  begin
    FInstance.Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.EventBreakOff));
    Exit;
  end;
  FInstance.Execute;
end;

class procedure TAtlasIdeEventBreak.ApplySettings;
begin
  if FInstance = nil then
  begin
    Exit;
  end;
  FInstance.UpdateMenu;
  // Ausgeschaltet während der Beobachtung: Haltepunkte gleich entfernen.
  if not Enabled and (FInstance.FWatch.Phase <> TPhase.Idle) then
  begin
    FInstance.Finish;
  end;
end;

procedure TAtlasIdeEventBreak.InstallMenu;
var
  mParent: TMenuItem;
begin
  mParent := RunMenu;
  if mParent = nil then
  begin
    Exit;
  end;
  FMenuItem := TMenuItem.Create(nil);
  FMenuItem.Name := cMenuItemName;
  FMenuItem.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.EventBreakCommand);
  FMenuItem.OnClick := MenuClick;
  mParent.Add(FMenuItem);
  UpdateMenu;
end;

procedure TAtlasIdeEventBreak.UpdateMenu;
begin
  if FMenuItem <> nil then
  begin
    FMenuItem.Visible := Enabled;
  end;
end;

procedure TAtlasIdeEventBreak.MenuClick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger,
    procedure
    begin
      Run;
    end);
end;

procedure TAtlasIdeEventBreak.Report(AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

class function TAtlasIdeEventBreak.Evaluate(const AExpression: string; out AValue: string): Boolean;
begin
  // ClassName und die Eigenschaften von Screen sind Aufrufe: erlauben.
  Result := TAtlasIdeDebugEvaluator.Evaluate(AExpression, TAtlasVisualizerEvaluation.Calls, cEvaluateMs, AValue);
end;

function TAtlasIdeEventBreak.Query: Boolean;
var
  mSession: TLspSession;
  mProject: string;
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
  mProject := TAtlasIdeTeamFile.ActiveProject;
  try
    mAnswer := mSession.RunCommand(TAtlasEventBreak.cCommand,
      TAtlasEventBreak.Arguments(TLspSession.PathToUri(mProject)),
      cTimeoutMs);
    try
      if not TAtlasEventBreak.ReadAnswer(mAnswer, FAnswer) then
      begin
        FAnswer := Default(TAtlasEventAnswer);
      end;
    finally
      mAnswer.Free;
    end;
  except
    on E: ELspClientError do
    begin
      Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.EventBreakFailed, [E.Message]));
      Exit;
    end;
  end;
  if Length(FAnswer.Handlers) = 0 then
  begin
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.EventBreakNoHandlers));
    Exit;
  end;
  Result := True;
end;

function TAtlasIdeEventBreak.CountText(const AChoice: TAtlasEventChoice): string;
var
  mChoice: TAtlasEventChoice;
  mSelected: TArray<Integer>;
begin
  // Welche Formulare sichtbar sind, steht erst beim Start fest: bis dahin zählen alle.
  mChoice := AChoice;
  if mChoice.Scope = TAtlasEventScope.VisibleForms then
  begin
    mChoice.Scope := TAtlasEventScope.AllForms;
  end;
  mSelected := TAtlasEventBreak.Select(FAnswer.Handlers, mChoice,
    TAtlasEventBreakSettings.ExcludedList(TAtlasIdeSettings.Current.DebugBreakOnNextEventExcluded), nil);
  Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.EventBreakCount,
    [Length(mSelected), Length(TAtlasEventBreak.Locations(FAnswer.Handlers, mSelected))]);
end;

procedure TAtlasIdeEventBreak.Execute;
var
  mProcess: IOTAProcess;
begin
  HideBar;
  // Zweiter Aufruf: Beobachtung beenden.
  if FWatch.Phase <> TPhase.Idle then
  begin
    Finish;
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.EventBreakCancelled));
  end
  else if Choose(mProcess) then
  begin
    ArmFor(mProcess);
  end;
end;

function TAtlasIdeEventBreak.Choose(out AProcess: IOTAProcess): Boolean;
var
  mChoice: TAtlasEventChoice;
begin
  Result := False;
  if not CurrentProcess(AProcess, Report) or not Query then
  begin
    Exit;
  end;
  mChoice := FChoice;
  if not TAtlasEventBreakDialog.Execute(mChoice, TAtlasEventBreak.Forms(FAnswer.Handlers),
    TAtlasIdeSettings.Current.DebugBreakOnNextEventExcluded,
    function(const AChoice: TAtlasEventChoice): string
    begin
      Result := CountText(AChoice);
    end) then
  begin
    Exit;
  end;
  FChoice := mChoice;
  if FAnswer.Unresolved > 0 then
  begin
    Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.EventBreakUnresolved, [FAnswer.Unresolved]));
  end;
  // Der Dialog war modal: Das Programm kann inzwischen beendet sein.
  Result := CurrentProcess(AProcess, Report);
end;

procedure TAtlasIdeEventBreak.ArmFor(const AProcess: IOTAProcess);
begin
  if FChoice.Scope <> TAtlasEventScope.VisibleForms then
  begin
    Arm(FChoice, nil);
  end
  else if TAtlasIdeBreakpoints.IsStopped(AProcess) then
  begin
    ArmVisibleForms;
  end
  else
  begin
    // Programm läuft: kurz anhalten, im Takt auf den Halt warten, dann Formulare lesen.
    FWatch.Phase := TPhase.Pausing;
    FWatch.PauseStarted := GetTickCount;
    FTimer.Enabled := True;
    try
      AProcess.Pause;
    except
      on E: Exception do
      begin
        FWatch.Phase := TPhase.Idle;
        ArmAllForms;
      end;
    end;
  end;
end;

procedure TAtlasIdeEventBreak.ArmVisibleForms;
var
  mForms: TArray<string>;
begin
  if VisibleForms(mForms) then
  begin
    Arm(FChoice, mForms);
  end
  else
  begin
    ArmAllForms;
  end;
end;

function TAtlasIdeEventBreak.VisibleForms(out AForms: TArray<string>): Boolean;
var
  mValue: string;
  mCount, mIndex: Integer;
begin
  AForms := nil;
  Result := Evaluate(TAtlasEventBreak.FormCountExpression, mValue) and TryStrToInt(Trim(mValue), mCount) and
    (mCount >= 0);
  if not Result then
  begin
    Exit;
  end;
  for mIndex := 0 to mCount - 1 do
  begin
    if not Evaluate(TAtlasEventBreak.FormVisibleExpression(mIndex), mValue) then
    begin
      Exit(False);
    end;
    if not SameText(Trim(mValue), 'True') then
    begin
      Continue;
    end;
    if not Evaluate(TAtlasEventBreak.FormClassExpression(mIndex), mValue) then
    begin
      Exit(False);
    end;
    AForms := AForms + [TAtlasEventBreak.Unquote(mValue)];
  end;
end;

procedure TAtlasIdeEventBreak.ArmAllForms;
var
  mChoice: TAtlasEventChoice;
begin
  Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.EventBreakVisibleUnknown));
  // Nur für diese Beobachtung; die Wahl im Dialog bleibt „sichtbare Formulare“.
  mChoice := FChoice;
  mChoice.Scope := TAtlasEventScope.AllForms;
  Arm(mChoice, nil);
end;

procedure TAtlasIdeEventBreak.Arm(const AChoice: TAtlasEventChoice; const AVisibleForms: TArray<string>);
var
  mSelected: TArray<Integer>;
begin
  FWatch.Phase := TPhase.Idle;
  mSelected := TAtlasEventBreak.Select(FAnswer.Handlers, AChoice,
    TAtlasEventBreakSettings.ExcludedList(TAtlasIdeSettings.Current.DebugBreakOnNextEventExcluded), AVisibleForms);
  FArmed.Locations := TAtlasEventBreak.Locations(FAnswer.Handlers, mSelected);
  if Length(FArmed.Locations) = 0 then
  begin
    FTimer.Enabled := False;
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.EventBreakNoHandlers));
    Exit;
  end;
  if Length(FArmed.Locations) > TAtlasEventBreak.cManyBreakpoints then
  begin
    Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.EventBreakMany, [Length(FArmed.Locations)]));
  end;
  Watch;
  Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.EventBreakWatching, [Length(FArmed.Locations)]));
end;

procedure TAtlasIdeEventBreak.Watch;
var
  mProcess: IOTAProcess;
  mLocation: TAtlasEventLocation;
  mBreakpoint: IOTABreakpoint;
begin
  TAtlasIdeBreakpoints.RemoveAll(FArmed.Breaks);
  for mLocation in FArmed.Locations do
  begin
    mBreakpoint := TAtlasIdeBreakpoints.Add(mLocation.FileName, mLocation.Line, cBreakpointGroup);
    if mBreakpoint <> nil then
    begin
      FArmed.Breaks := FArmed.Breaks + [mBreakpoint];
    end;
  end;
  FWatch.Phase := TPhase.Watching;
  FWatch.SeenRunning := False;
  FWatch.StartFile := '';
  FWatch.StartLine := -1;
  FTimer.Enabled := True;
  mProcess := TAtlasIdeBreakpoints.CurrentProcess;
  if TAtlasIdeBreakpoints.IsStopped(mProcess) then
  begin
    TAtlasIdeBreakpoints.Position(mProcess.CurrentThread, FWatch.StartFile, FWatch.StartLine);
    mProcess.Run(ormRun);
  end
  else
  begin
    FWatch.SeenRunning := True;
  end;
end;

procedure TAtlasIdeEventBreak.KeepWatching;
begin
  HideBar;
  if TAtlasIdeBreakpoints.CurrentProcess = nil then
  begin
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.EventBreakEnded));
    Exit;
  end;
  if Length(FArmed.Locations) > 0 then
  begin
    Watch;
  end;
end;

procedure TAtlasIdeEventBreak.Finish;
begin
  FTimer.Enabled := False;
  FWatch.Phase := TPhase.Idle;
  TAtlasIdeBreakpoints.RemoveAll(FArmed.Breaks);
end;

procedure TAtlasIdeEventBreak.HideBar;
begin
  if (FBar <> nil) and FBar.IsShown then
  begin
    FBar.Dismiss;
  end;
end;

procedure TAtlasIdeEventBreak.Stopped(const AProcess: IOTAProcess);
var
  mFileName, mCaption: string;
  mLine, mFound: Integer;
begin
  TAtlasIdeBreakpoints.Position(AProcess.CurrentThread, mFileName, mLine);
  // Erster Halt, gleich wo: eigene Haltepunkte entfernen (FArmed.Locations bleibt für „Weiter beobachten“).
  Finish;
  mFound := TAtlasEventBreak.LocationAt(FArmed.Locations, mFileName, mLine);
  if mFound < 0 then
  begin
    if AProcess.ProcessState = psStopped then
    begin
      Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.EventBreakElsewhere, [ExtractFileName(mFileName),
        mLine + 1]));
    end;
    Exit;
  end;
  mCaption := TAtlasEventBreak.Caption(FAnswer.Handlers, FArmed.Locations[mFound],
    IdentifyHandler(FAnswer, FArmed.Locations[mFound]));
  Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.EventBreakStopped, [mCaption]));
  ShowBar(mCaption);
  // Im Takt bleiben, um die Leiste zu schließen, sobald das Programm weiterläuft.
  FTimer.Enabled := True;
end;

procedure TAtlasIdeEventBreak.ShowBar(const ACaption: string);
var
  mPoint: TPoint;
begin
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
            begin
              FInstance.KeepWatching;
            end;
          end);
      end;
    FBar.OnClose :=
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.Debugger,
          procedure
          begin
            if FInstance <> nil then
            begin
              FInstance.HideBar;
            end;
          end);
      end;
  end;
  mPoint := CaretPoint;
  FBar.Colors := TAtlasIdeStyle.Colors;
  FBar.SetScaling(TAtlasPopupWindow.MonitorPPI(mPoint), 1, '', 10);
  FBar.ShowFor(ACaption, mPoint);
end;

procedure TAtlasIdeEventBreak.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger,
    procedure
    begin
      Step;
    end);
end;

procedure TAtlasIdeEventBreak.Step;
var
  mProcess: IOTAProcess;
  mOutcome: TPauseOutcome;
begin
  mProcess := TAtlasIdeBreakpoints.CurrentProcess;
  if mProcess = nil then
  begin
    // Programm beendet: aufräumen.
    HideBar;
    if FWatch.Phase <> TPhase.Idle then
    begin
      Finish;
      Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.EventBreakEnded));
    end;
    FTimer.Enabled := False;
  end
  else if FWatch.Phase = TPhase.Pausing then
  begin
    mOutcome := PauseOutcome(mProcess, FWatch.PauseStarted);
    if mOutcome = TPauseOutcome.Stopped then
    begin
      ArmVisibleForms;
    end
    else if mOutcome = TPauseOutcome.TimedOut then
    begin
      // Kein Halt nach Pause: alle Formulare.
      ArmAllForms;
    end;
  end
  else if FWatch.Phase = TPhase.Watching then
  begin
    if StoppedAnew(mProcess, FWatch) then
    begin
      Stopped(mProcess);
    end;
  end
  else if not TAtlasIdeBreakpoints.IsStopped(mProcess) then
  begin
    // Leiste zu, sobald das Programm wieder läuft.
    HideBar;
    FTimer.Enabled := False;
  end;
end;

end.
