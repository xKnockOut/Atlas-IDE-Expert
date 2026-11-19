unit Atlas.IDE.Debug.DataBreak;

// Anhalten bei Datenzugriff (#870) im Debugger der IDE. Wo das Projekt auf
// Datenbanken und HTTP zugreift, rechnet der Server
// (atlas.server.dataAccessSites); Klassen, Ausdrücke und Entscheidung liegen in
// Atlas.Core.Debug.DataBreak(Watch), Dialog und Leiste in
// Atlas.UI.Debug.DataBreak. Hier bleiben:
// - Eintrag „Anhalten bei Datenzugriff …“ im Menü Start (RunMenu) und der
//   Befehl Atlas.BreakOnDataAccess; sichtbar nach debug.dataBreaks. Geht vor
//   dem Start und während des Laufs; ein zweiter Aufruf während der
//   Beobachtung beendet sie.
// - Je Haltestelle (Startzeile der Anweisung) ein vorübergehender Haltepunkt
//   in der Gruppe Atlas.Datenzugriff; Haltepunkte des Benutzers bleiben, wie
//   sie sind.
// - Hält das Programm an einer Haltestelle, wertet Atlas SQL-Text bzw.
//   Methode und URL aus: passt das Muster nicht, läuft das Programm still
//   weiter; „Nur protokollieren“ schreibt eine Zeile in die Meldungen und läuft
//   weiter; sonst bleibt es stehen, und die Leiste bietet „Weiter beobachten“,
//   „Nur protokollieren“ und „Beenden“. Hält es woanders, tut Atlas nichts.
// - Programmende oder ausgeschaltete Einstellung: Haltepunkte entfernen.
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
  Atlas.Core.Debug.DataBreak,
  Atlas.Core.Debug.DataBreakWatch,
  Atlas.UI.Debug.DataBreak,
  Atlas.Core.Notifications.MessageSink;

type
  TAtlasDataBreakSessionFunc = reference to function: TLspSession;

  TAtlasIdeDataBreak = class
  private const
    /// <summary>Der Server liest dafür alle Units des Projekts.</summary>
    cTimeoutMs = 30000;
    cEvaluateMs = 1500;
    cTickMs = 100;
  private class var
    FInstance: TAtlasIdeDataBreak;
  private
    FSession: TAtlasDataBreakSessionFunc;
    FMessage: TAtlasMessageSink;
    FTimer: TTimer;
    FMenuItem: TMenuItem;
    FBar: TAtlasDataBreakBar;
    FChoice: TAtlasDataChoice;
    FClasses: TArray<TAtlasDataClass>;
    FAnswer: TAtlasDataAnswer;
    FLocations: TArray<TAtlasDataLocation>;
    FBreaks: TArray<IOTABreakpoint>;
    FWatch: TAtlasDataWatch;
    /// <summary>Lief während der Beobachtung schon ein Programm? Dann beendet sein Ende die Beobachtung.</summary>
    FSeenProcess: Boolean;
    procedure MenuClick(Sender: TObject);
    procedure Tick(Sender: TObject);
    procedure Execute;
    /// <summary>Klassen aus der Einstellung und Server fragen; False mit Meldung.</summary>
    function Query: Boolean;
    function CountText(const AChoice: TAtlasDataChoice): string;
    procedure Arm;
    procedure Step;
    procedure StepStopped(const AProcess: IOTAProcess);
    procedure Stopped(const AProcess: IOTAProcess; const AFileName: string; ALine, ALocation: Integer);
    procedure Resume(const AProcess: IOTAProcess; const AFileName: string; ALine: Integer);
    procedure ShowBar(const APlace, ADetail: string);
    procedure BarAction(AAction: TAtlasDataBreakAction);
    procedure KeepWatching;
    procedure LogOnly;
    procedure Finish;
    procedure HideBar;
    procedure UpdateMenu;
    class function Evaluate(const AExpression: string; out AValue: string): Boolean; static;
  public
    constructor Create(const ASession: TAtlasDataBreakSessionFunc; const AMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>ASession liefert die laufende Sitzung (nil ohne), AMessage schreibt eine Zeile in die
    /// Meldungsansicht.</summary>
    class procedure Install(const ASession: TAtlasDataBreakSessionFunc; const AMessage: TProc<string>); static;
    class procedure Uninstall; static;
    /// <summary>debug.dataBreaks an und Atlas an?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Befehl Atlas.BreakOnDataAccess (Menü Start, Palette); während der Beobachtung beendet er sie.
    /// </summary>
    class procedure Run; static;
    /// <summary>Sichtbarkeit des Menüeintrags nach geänderten Einstellungen.</summary>
    class procedure ApplySettings; static;
  end;

implementation

uses
  System.JSON,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.Deadline,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.DataBreakClasses,
  Atlas.Core.Settings.VisualizerKinds,
  Atlas.Core.Lsp.Client,
  Atlas.UI.Debug.Commands.Strings,
  Atlas.UI.Debug.DataBreak.Strings,
  Atlas.UI.Popup.Window,
  Atlas.UI.Debug.StopBar,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Caret,
  Atlas.IDE.Debug.Evaluator,
  Atlas.IDE.Debug.Breakpoints,
  Atlas.IDE.Debug.RunMenu;

const
  cMenuItemName = 'AtlasBreakOnDataAccessItem';
  cBreakpointGroup = 'Atlas.Datenzugriff';

{ TAtlasIdeDataBreak }

constructor TAtlasIdeDataBreak.Create(const ASession: TAtlasDataBreakSessionFunc; const AMessage: TProc<string>);
begin
  inherited Create;
  FSession := ASession;
  FMessage := TAtlasMessageSink.Create(AMessage);
  FChoice := TAtlasDataChoice.Defaults;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := Tick;
  FMenuItem := TAtlasIdeRunMenu.AddItem(cMenuItemName,
    TAtlasDebugCommandsStrings.Text(TAtlasDebugCommandsTextId.DataBreakCommand), MenuClick);
  UpdateMenu;
end;

destructor TAtlasIdeDataBreak.Destroy;
begin
  FreeAndNil(FTimer);
  // Beim Entladen mitten in der Beobachtung: keine Haltepunkte zurücklassen.
  TAtlasIdeBreakpoints.RemoveAll(FBreaks);
  FreeAndNil(FBar);
  FreeAndNil(FMenuItem);
  FLocations := nil;
  FClasses := nil;
  FAnswer := Default(TAtlasDataAnswer);
  inherited;
end;

procedure TAtlasIdeDataBreak.MenuClick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, Run);
end;

procedure TAtlasIdeDataBreak.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, Step);
end;

procedure TAtlasIdeDataBreak.Execute;
var
  mChoice: TAtlasDataChoice;
begin
  HideBar;
  // Zweiter Aufruf: Beobachtung beenden.
  if FWatch.Active then
  begin
    Finish;
    FMessage.Say(TAtlasDataBreakStrings.Text(TAtlasDataBreakTextId.DataBreakCancelled));
    Exit;
  end;
  if not Query then
  begin
    Exit;
  end;
  mChoice := FChoice;
  if not TAtlasDataBreakDialog.Execute(mChoice, TAtlasDataBreak.CountOf(FAnswer.Sites, TAtlasDataKind.Sql),
    TAtlasDataBreak.CountOf(FAnswer.Sites, TAtlasDataKind.Http),
    function(const AChoice: TAtlasDataChoice): string
    begin
      Result := CountText(AChoice);
    end) then
  begin
    Exit;
  end;
  FChoice := mChoice;
  if FAnswer.Unresolved > 0 then
  begin
    FMessage.Say(TAtlasDataBreakStrings.Fmt(TAtlasDataBreakTextId.DataBreakUnresolved, [FAnswer.Unresolved]));
  end;
  Arm;
end;

function TAtlasIdeDataBreak.Query: Boolean;
var
  mSession: TLspSession;
  mSkipped: TArray<string>;
  mAnswer: TJSONValue;
begin
  Result := False;
  FClasses := TAtlasDataBreak.Classes(
    TAtlasDataBreakSettings.Entries(TAtlasIdeSettings.Current.DebugDataBreaksClasses), mSkipped);
  if Length(mSkipped) > 0 then
  begin
    FMessage.Say(TAtlasDataBreakStrings.Fmt(TAtlasDataBreakTextId.DataBreakSkipped, [string.Join(', ', mSkipped)]));
  end;
  if Length(FClasses) = 0 then
  begin
    FMessage.Say(TAtlasDataBreakStrings.Text(TAtlasDataBreakTextId.DataBreakNoClasses));
    Exit;
  end;
  mSession := nil;
  if Assigned(FSession) then
  begin
    mSession := FSession();
  end;
  if mSession = nil then
  begin
    FMessage.Say(TAtlasDataBreakStrings.Text(TAtlasDataBreakTextId.DataBreakNoServer));
    Exit;
  end;
  try
    mAnswer := mSession.RunCommand(TAtlasDataBreak.cCommand,
      TAtlasDataBreak.Arguments(TLspSession.PathToUri(TAtlasIdeFiles.ActiveProjectFile), FClasses), cTimeoutMs);
    try
      if not TAtlasDataBreak.ReadAnswer(mAnswer, FAnswer) then
      begin
        FAnswer := Default(TAtlasDataAnswer);
      end;
    finally
      mAnswer.Free;
    end;
  except
    on E: ELspClientError do
    begin
      FMessage.Say(TAtlasDataBreakStrings.Fmt(TAtlasDataBreakTextId.DataBreakFailed, [E.Message]));
      Exit;
    end;
  end;
  Result := Length(FAnswer.Sites) > 0;
  if not Result then
  begin
    FMessage.Say(TAtlasDataBreakStrings.Text(TAtlasDataBreakTextId.DataBreakNoSites));
  end;
end;

function TAtlasIdeDataBreak.CountText(const AChoice: TAtlasDataChoice): string;
var
  mCount: Integer;
  mKind: TAtlasDataKind;
begin
  mCount := 0;
  for mKind in AChoice.Kinds do
  begin
    Inc(mCount, TAtlasDataBreak.CountOf(FAnswer.Sites, mKind));
  end;
  Result := TAtlasDataBreakStrings.Fmt(TAtlasDataBreakTextId.DataBreakCount,
    [mCount, Length(TAtlasDataBreak.Locations(FAnswer.Sites, AChoice.Kinds))]);
end;

procedure TAtlasIdeDataBreak.Arm;
var
  mLocation: TAtlasDataLocation;
  mBreakpoint: IOTABreakpoint;
  mProcess: IOTAProcess;
  mFileName: string;
  mLine: Integer;
begin
  FLocations := TAtlasDataBreak.Locations(FAnswer.Sites, FChoice.Kinds);
  if Length(FLocations) = 0 then
  begin
    FMessage.Say(TAtlasDataBreakStrings.Text(TAtlasDataBreakTextId.DataBreakNoSites));
    Exit;
  end;
  if Length(FLocations) > TAtlasDataBreak.cManyBreakpoints then
  begin
    FMessage.Say(TAtlasDataBreakStrings.Fmt(TAtlasDataBreakTextId.DataBreakMany, [Length(FLocations)]));
  end;
  TAtlasIdeBreakpoints.RemoveAll(FBreaks);
  for mLocation in FLocations do
  begin
    mBreakpoint := TAtlasIdeBreakpoints.Add(mLocation.FileName, mLocation.Line, cBreakpointGroup);
    if mBreakpoint <> nil then
    begin
      FBreaks := FBreaks + [mBreakpoint];
    end;
  end;
  // Steht das Programm schon, zählt die Stelle erst nach dem Weiterlaufen; Atlas lässt es nicht selbst laufen.
  mProcess := TAtlasIdeBreakpoints.CurrentProcess;
  FSeenProcess := mProcess <> nil;
  mFileName := '';
  mLine := -1;
  if TAtlasIdeBreakpoints.IsStopped(mProcess) then
  begin
    TAtlasIdeBreakpoints.Position(mProcess.CurrentThread, mFileName, mLine);
    FWatch.Start(mFileName, mLine);
    FMessage.Say(TAtlasDataBreakStrings.Fmt(TAtlasDataBreakTextId.DataBreakWatchingStopped, [Length(FBreaks)]));
  end
  else
  begin
    FWatch.Start('', -1);
    FMessage.Say(TAtlasDataBreakStrings.Fmt(TAtlasDataBreakTextId.DataBreakWatching, [Length(FBreaks)]));
  end;
  FTimer.Enabled := True;
end;

procedure TAtlasIdeDataBreak.Step;
var
  mProcess: IOTAProcess;
begin
  mProcess := TAtlasIdeBreakpoints.CurrentProcess;
  if mProcess = nil then
  begin
    // Vor dem Start warten; nach dem Ende aufräumen.
    if FSeenProcess then
    begin
      HideBar;
      Finish;
      FMessage.Say(TAtlasDataBreakStrings.Text(TAtlasDataBreakTextId.DataBreakEnded));
    end;
    Exit;
  end;
  FSeenProcess := True;
  if TAtlasIdeBreakpoints.IsStopped(mProcess) then
  begin
    StepStopped(mProcess);
  end
  else
  begin
    // Leiste zu, sobald das Programm wieder läuft.
    FWatch.Running;
    HideBar;
  end;
end;

procedure TAtlasIdeDataBreak.StepStopped(const AProcess: IOTAProcess);
var
  mFileName: string;
  mLine, mFound: Integer;
begin
  if not TAtlasIdeBreakpoints.Position(AProcess.CurrentThread, mFileName, mLine) or
    not FWatch.StoppedAnew(mFileName, mLine, TAtlasTicks.Now) then
  begin
    Exit;
  end;
  mFound := TAtlasDataBreak.LocationAt(FLocations, mFileName, mLine);
  if mFound < 0 then
  begin
    // Haltepunkt des Benutzers, Pause, Schritt: stehen lassen.
    FWatch.Held(mFileName, mLine);
    Exit;
  end;
  Stopped(AProcess, mFileName, mLine, mFound);
end;

procedure TAtlasIdeDataBreak.Stopped(const AProcess: IOTAProcess; const AFileName: string; ALine, ALocation: Integer);
var
  mVerdict: TAtlasDataVerdict;
  mNotEvaluated: string;
begin
  mVerdict := TAtlasDataBreakWatch.Judge(FChoice, FAnswer.Sites, FClasses, FLocations[ALocation],
    function(const AExpression: string; out AValue: string): Boolean
    begin
      Result := Evaluate(AExpression, AValue);
    end);
  mNotEvaluated := TAtlasDataBreakStrings.Text(TAtlasDataBreakTextId.DataBreakNotEvaluated);
  case mVerdict.Outcome of
    TAtlasDataOutcome.Continue:
      Resume(AProcess, AFileName, ALine);
    TAtlasDataOutcome.Log:
      begin
        FMessage.Say(TAtlasDataBreak.LogLine(FAnswer.Sites[mVerdict.Site], mVerdict.Values, mNotEvaluated));
        Resume(AProcess, AFileName, ALine);
      end;
  else
    FWatch.Held(AFileName, ALine);
    FMessage.Say(TAtlasDataBreakStrings.Fmt(TAtlasDataBreakTextId.DataBreakStopped,
      [TAtlasDataBreak.LogLine(FAnswer.Sites[mVerdict.Site], mVerdict.Values, mNotEvaluated)]));
    ShowBar(TAtlasDataBreak.Place(FAnswer.Sites[mVerdict.Site]),
      TAtlasDataBreak.Detail(FAnswer.Sites[mVerdict.Site], mVerdict.Values, mNotEvaluated));
  end;
end;

procedure TAtlasIdeDataBreak.Resume(const AProcess: IOTAProcess; const AFileName: string; ALine: Integer);
begin
  FWatch.Resumed(AFileName, ALine, TAtlasTicks.Now);
  AProcess.Run(ormRun);
end;

procedure TAtlasIdeDataBreak.ShowBar(const APlace, ADetail: string);
var
  mPoint: TPoint;
begin
  if FBar = nil then
  begin
    FBar := TAtlasDataBreakBar.Create(nil);
    FBar.OnAction :=
      procedure(AAction: TAtlasDataBreakAction)
      begin
        TAtlasGuard.Run(TAtlasFeature.Debugger,
          procedure
          begin
            if FInstance <> nil then
            begin
              FInstance.BarAction(AAction);
            end;
          end);
      end;
  end;
  // Unter der Zeile mit der Schreibmarke: Die IDE setzt sie beim Halt auf den Ausführungspunkt.
  mPoint := TAtlasIdeCaret.BelowLine;
  FBar.Colors := TAtlasIdeStyle.Colors;
  FBar.SetScaling(TAtlasPopupWindow.MonitorPPI(mPoint), 1, '', 10);
  FBar.ShowFor(APlace, ADetail, mPoint);
end;

procedure TAtlasIdeDataBreak.BarAction(AAction: TAtlasDataBreakAction);
begin
  case AAction of
    TAtlasDataBreakAction.KeepWatching:
      KeepWatching;
    TAtlasDataBreakAction.LogOnly:
      LogOnly;
  else
    Finish;
    FMessage.Say(TAtlasDataBreakStrings.Text(TAtlasDataBreakTextId.DataBreakCancelled));
  end;
end;

procedure TAtlasIdeDataBreak.KeepWatching;
var
  mProcess: IOTAProcess;
begin
  HideBar;
  mProcess := TAtlasIdeBreakpoints.CurrentProcess;
  if mProcess = nil then
  begin
    Exit;
  end;
  if TAtlasIdeBreakpoints.IsStopped(mProcess) then
  begin
    Resume(mProcess, FWatch.LastFile, FWatch.LastLine);
  end;
end;

procedure TAtlasIdeDataBreak.LogOnly;
begin
  FChoice.Mode := TAtlasDataMode.Log;
  FMessage.Say(TAtlasDataBreakStrings.Text(TAtlasDataBreakTextId.DataBreakLogging));
  KeepWatching;
end;

procedure TAtlasIdeDataBreak.Finish;
begin
  FTimer.Enabled := False;
  FWatch := Default(TAtlasDataWatch);
  FSeenProcess := False;
  TAtlasIdeBreakpoints.RemoveAll(FBreaks);
end;

procedure TAtlasIdeDataBreak.HideBar;
begin
  TAtlasStopBar.Hide(FBar);
end;

procedure TAtlasIdeDataBreak.UpdateMenu;
begin
  TAtlasIdeRunMenu.ShowItem(FMenuItem, Enabled);
end;

class function TAtlasIdeDataBreak.Evaluate(const AExpression: string; out AValue: string): Boolean;
begin
  // SQL.Text, GetFullRequestURL und Params[i] sind Aufrufe: erlauben.
  Result := TAtlasIdeDebugEvaluator.Evaluate(AExpression, TAtlasVisualizerEvaluation.Calls, cEvaluateMs, AValue);
end;

class procedure TAtlasIdeDataBreak.Install(const ASession: TAtlasDataBreakSessionFunc;
  const AMessage: TProc<string>);
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeDataBreak.Create(ASession, AMessage);
  end;
end;

class procedure TAtlasIdeDataBreak.Uninstall;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeDataBreak.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.DebugDataBreaks;
end;

class procedure TAtlasIdeDataBreak.Run;
begin
  if FInstance = nil then
  begin
    Exit;
  end;
  if not Enabled then
  begin
    FInstance.FMessage.Say(TAtlasDataBreakStrings.Text(TAtlasDataBreakTextId.DataBreakOff));
    Exit;
  end;
  FInstance.Execute;
end;

class procedure TAtlasIdeDataBreak.ApplySettings;
begin
  if FInstance = nil then
  begin
    Exit;
  end;
  FInstance.UpdateMenu;
  // Ausgeschaltet während der Beobachtung: Haltepunkte gleich entfernen.
  if not Enabled and FInstance.FWatch.Active then
  begin
    FInstance.HideBar;
    FInstance.Finish;
  end;
end;

end.
