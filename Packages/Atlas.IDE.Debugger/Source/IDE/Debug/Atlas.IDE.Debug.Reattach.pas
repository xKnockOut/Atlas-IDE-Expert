unit Atlas.IDE.Debug.Reattach;

// Erneut an einen Prozess anhängen und auf den Start eines Prozesses warten
// (#2171) in der IDE:
// - Merken: Startet eine Sitzung, ohne dass die IDE das Programm gestartet
//   hat (angehängt über den Dialog der IDE oder über Atlas), merkt Atlas den
//   Pfad der EXE je Projektgruppe (%LOCALAPPDATA%\Atlas\debug-reattach.json).
// - „Erneut an <Name> anhängen“ (Menü Start, Palette, Taste
//   debug.reattach.key): Entscheidung nach TAtlasReattach.Decide; sofort
//   anhängen (IOTADebuggerServices.AttachProcess), Auswahl
//   (TAtlasProcessChoiceDialog) oder Warten anbieten.
// - „Anhängen, sobald gestartet …“: EXE wählen (Vorgabe: zuletzt gemerkte,
//   sonst Ausgabedatei des aktiven Projekts), dann TAtlasIdeReattachWaiter.
//   Das Statusfeld zeigt „Warte auf … (Abbrechen)“; ein Klick bricht ab. Das
//   Warten endet mit dem Anhängen, dem Abbrechen, dem Wechsel oder Schließen
//   der Projektgruppe (geprüft jede cGroupCheckMs, dann folgt auch der
//   Menüeintrag der neuen Gruppe) und mit Release.
// - Endet eine angehängte Sitzung, bietet das Statusfeld „erneut anhängen,
//   sobald er wieder startet“ an.
// Nur lokale Prozesse. Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls,
  Vcl.Menus,
  ToolsAPI,
  Atlas.Core.Status.Contract,
  Atlas.Core.Debug.DialogCompletion,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.ReattachWait;

type
  TAtlasIdeDebugReattach = class
  public const
    cFileName = 'debug-reattach.json';
    /// <summary>Gemerkte Programme je Projektgruppe.</summary>
    cPerGroup = 5;
    cGroupCheckMs = 1000;
    cStatusId = 'atlas.debug.reattach';
    cStatusOrder = 86;
  private type
    /// <summary>Merkt angehängte Programme; ein Start der IDE meldet sich vorher über AllowLaunch.</summary>
    TListener = class(TAtlasIdeDebugListener, IAtlasIdeDebugLaunchCheck)
    private
      FLaunching: Boolean;
    public
      function AllowLaunch(const AProject: IOTAProject): Boolean;
      procedure DebugStarted; override;
      procedure DebugEnded; override;
    end;
    /// <summary>Ereignisse von Zeitgeber und Menü unter der Sicherung des Debuggers.</summary>
    THandler = class
    public
      procedure Tick(Sender: TObject);
      procedure ReattachClick(Sender: TObject);
      procedure WaitClick(Sender: TObject);
    end;
  private class var
    FListener: IAtlasIdeDebugListener;
    FHandler: THandler;
    FMessage: TProc<string>;
    FRegistry: IAtlasStatusRegistry;
    FStatus: IAtlasStatusItem;
    FHistory: TAtlasExpressionHistory;
    FHistoryKept: Boolean;
    FAttachedPath: string;
    FWaiter: TAtlasIdeReattachWaiter;
    FWaitTarget: string;
    FWaitGroup: string;
    FGeneration: Integer;
    FGroupTimer: TTimer;
    FMenuReattach: TMenuItem;
    FMenuWait: TMenuItem;
    FMenuGroup: string;
    class procedure Say(const AText: string); static;
    class function History: TAtlasExpressionHistory; static;
    class procedure Remember(const APath: string); static;
    class function CurrentGroup: string; static;
    class function ProjectTarget: string; static;
    class procedure ShowStatus(const AText, ASummary: string; const AAction: TProc); static;
    class procedure HideStatus; static;
    class procedure StopWaiter; static;
    class procedure Found(AGeneration: Integer; APid: Cardinal); static;
    class procedure CheckGroup; static;
    class procedure AttachTo(APid: Cardinal; const AName: string); static;
    class procedure OfferWait(const APath: string); static;
    class procedure InstallMenu; static;
    class procedure RemoveMenu; static;
    class procedure UpdateMenu; static;
  public
    class procedure Start(const AMessage: TProc<string>; const ARegistry: IAtlasStatusRegistry); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>Zuletzt gemerktes Programm der Projektgruppe ('' = keins).</summary>
    class function LastTarget: string; static;
    /// <summary>Befehl Atlas.Reattach.</summary>
    class procedure Execute; static;
    /// <summary>Befehl Atlas.ReattachWhenStarted: EXE wählen und warten.</summary>
    class procedure WaitForStart; static;
    /// <summary>Auf den Start von APath warten (ersetzt ein laufendes Warten).</summary>
    class procedure WaitFor(const APath: string); static;
    class procedure CancelWait; static;
    class function Waiting: Boolean; static;
  end;

implementation

uses
  System.IOUtils,
  System.Classes,
  System.UITypes,
  Vcl.Dialogs,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Status.Registry,
  Atlas.Core.Debug.Reattach,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Processes,
  Atlas.UI.Debug.ProcessChoice,
  Atlas.UI.Debug.Strings;

const
  cHistoryWhat = 'debug reattach';
  cReattachItemName = 'AtlasReattachItem';
  cWaitItemName = 'AtlasReattachWaitItem';

function HistoryFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    TAtlasIdeDebugReattach.cFileName);
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

{ TAtlasIdeDebugReattach.TListener }

function TAtlasIdeDebugReattach.TListener.AllowLaunch(const AProject: IOTAProject): Boolean;
begin
  // Die IDE startet ein Programm (Start, F9): diese Sitzung ist nicht angehängt.
  FLaunching := True;
  Result := True;
end;

procedure TAtlasIdeDebugReattach.TListener.DebugStarted;
var
  mProcess: IOTAProcess;
  mLaunched: Boolean;
begin
  FAttachedPath := '';
  mLaunched := FLaunching;
  FLaunching := False;
  if mLaunched then
  begin
    Exit;
  end;
  // Angehängt (Dialog der IDE oder Atlas): Pfad merken, das Angebot nach dem letzten Ende gilt nicht mehr.
  mProcess := TAtlasIdeDebugSession.Process;
  if mProcess <> nil then
  begin
    FAttachedPath := TAtlasIdeDebugProcesses.PathOf(mProcess.ProcessId);
  end;
  HideStatus;
  Remember(FAttachedPath);
end;

procedure TAtlasIdeDebugReattach.TListener.DebugEnded;
var
  mPath, mText: string;
begin
  mPath := FAttachedPath;
  FAttachedPath := '';
  if (mPath = '') or TAtlasIdeDebugReattach.Waiting then
  begin
    Exit;
  end;
  mText := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.ReattachEnded, [TAtlasReattach.NameOf(mPath)]);
  TAtlasIdeDebugReattach.ShowStatus(mText, mText,
    procedure
    begin
      TAtlasIdeDebugReattach.WaitFor(mPath);
    end);
end;

{ TAtlasIdeDebugReattach.THandler }

procedure TAtlasIdeDebugReattach.THandler.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugReattach.CheckGroup);
end;

procedure TAtlasIdeDebugReattach.THandler.ReattachClick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugReattach.Execute);
end;

procedure TAtlasIdeDebugReattach.THandler.WaitClick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugReattach.WaitForStart);
end;

{ TAtlasIdeDebugReattach }

class procedure TAtlasIdeDebugReattach.Start(const AMessage: TProc<string>; const ARegistry: IAtlasStatusRegistry);
begin
  FMessage := AMessage;
  FRegistry := ARegistry;
  if FHandler = nil then
  begin
    FHandler := THandler.Create;
  end;
  if FGroupTimer = nil then
  begin
    FGroupTimer := TTimer.Create(nil);
    FGroupTimer.Enabled := True;
    FGroupTimer.Interval := cGroupCheckMs;
    FGroupTimer.OnTimer := FHandler.Tick;
  end;
  if FListener = nil then
  begin
    FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FListener);
  end;
  TAtlasIdeDebugSession.Start;
  InstallMenu;
end;

class procedure TAtlasIdeDebugReattach.Release;
begin
  // Regel 3 der Module: Nach dem Abmelden erreicht nichts mehr das Modul (Thread, Zeitgeber, Menü, Statusfeld).
  StopWaiter;
  HideStatus;
  RemoveMenu;
  if FListener <> nil then
  begin
    TAtlasIdeDebugSession.RemoveListener(FListener);
  end;
  FListener := nil;
  FreeAndNil(FGroupTimer);
  FreeAndNil(FHandler);
  FreeAndNil(FHistory);
  FHistoryKept := False;
  FRegistry := nil;
  FMessage := nil;
  FAttachedPath := '';
  FWaitTarget := '';
  FWaitGroup := '';
  FMenuGroup := '';
end;

class function TAtlasIdeDebugReattach.Started: Boolean;
begin
  Result := FListener <> nil;
end;

class procedure TAtlasIdeDebugReattach.Say(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

class function TAtlasIdeDebugReattach.History: TAtlasExpressionHistory;
begin
  if FHistory = nil then
  begin
    FHistory := TAtlasExpressionHistory.Create(cPerGroup);
    FHistoryKept := not TAtlasDataFile.Writable(TAtlasDataFile.Load(HistoryFile, cHistoryWhat,
      function(const AText: string): Boolean
      begin
        Result := FHistory.LoadFromText(AText);
      end));
  end;
  Result := FHistory;
end;

class procedure TAtlasIdeDebugReattach.Remember(const APath: string);
begin
  if (APath = '') or not History.Add(CurrentGroup, APath) then
  begin
    UpdateMenu;
    Exit;
  end;
  UpdateMenu;
  if FHistoryKept then
  begin
    Exit;
  end;
  try
    TAtlasDataFile.Write(HistoryFile, FHistory.ToText);
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten(cHistoryWhat, E);
  end;
end;

class function TAtlasIdeDebugReattach.CurrentGroup: string;
var
  mModules: IOTAModuleServices;
begin
  Result := '';
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) and (mModules.MainProjectGroup <> nil) then
  begin
    Result := mModules.MainProjectGroup.FileName;
  end;
end;

class function TAtlasIdeDebugReattach.ProjectTarget: string;
var
  mProject: IOTAProject;
begin
  Result := '';
  mProject := GetActiveProject;
  if (mProject <> nil) and (mProject.ProjectOptions <> nil) then
  begin
    Result := mProject.ProjectOptions.TargetName;
  end;
end;

class function TAtlasIdeDebugReattach.LastTarget: string;
var
  mItems: TArray<string>;
begin
  Result := '';
  mItems := History.Items(CurrentGroup);
  if mItems <> nil then
  begin
    Result := mItems[0];
  end;
end;

class procedure TAtlasIdeDebugReattach.ShowStatus(const AText, ASummary: string; const AAction: TProc);
var
  mLine: TAtlasStatusLine;
begin
  HideStatus;
  if FRegistry = nil then
  begin
    Exit;
  end;
  mLine := TAtlasStatusLine.Create(FRegistry, cStatusId, cStatusOrder,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Debugger, AAction);
    end);
  FStatus := mLine;
  mLine.Update(AText, TAtlasStatusState.Yellow, ASummary);
  FRegistry.Add(FStatus);
end;

class procedure TAtlasIdeDebugReattach.HideStatus;
begin
  if (FRegistry <> nil) and (FStatus <> nil) then
  begin
    FRegistry.Remove(cStatusId);
  end;
  FStatus := nil;
end;

class procedure TAtlasIdeDebugReattach.StopWaiter;
begin
  Inc(FGeneration);
  // Free wartet auf das Ende des Threads; Terminate weckt ihn sofort.
  FreeAndNil(FWaiter);
end;

class function TAtlasIdeDebugReattach.Waiting: Boolean;
begin
  Result := FWaiter <> nil;
end;

class procedure TAtlasIdeDebugReattach.WaitFor(const APath: string);
var
  mGeneration: Integer;
begin
  StopWaiter;
  HideStatus;
  if APath = '' then
  begin
    Exit;
  end;
  FWaitTarget := APath;
  FWaitGroup := CurrentGroup;
  mGeneration := FGeneration;
  FWaiter := TAtlasIdeReattachWaiter.Create(APath, TAtlasIdeSettings.Current.DebugReattachWaitIntervalMs,
    procedure(APid: Cardinal)
    begin
      TAtlasIdeDebugReattach.Found(mGeneration, APid);
    end);
  ShowStatus(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.ReattachWaiting, [TAtlasReattach.NameOf(APath)]),
    TAtlasDebugStrings.Fmt(TAtlasDebugTextId.ReattachWaitingSummary, [TAtlasReattach.NameOf(APath)]),
    TAtlasIdeDebugReattach.CancelWait);
end;

class procedure TAtlasIdeDebugReattach.CancelWait;
begin
  if not Waiting then
  begin
    Exit;
  end;
  StopWaiter;
  HideStatus;
  Say(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.ReattachStopped, [TAtlasReattach.NameOf(FWaitTarget)]));
end;

class procedure TAtlasIdeDebugReattach.CheckGroup;
var
  mGroup: string;
begin
  mGroup := CurrentGroup;
  // Projektgruppe gewechselt oder geschlossen: Das Warten gehörte zur alten.
  if Waiting and not SameText(mGroup, FWaitGroup) then
  begin
    CancelWait;
  end;
  // Der Menüeintrag nennt das zuletzt gemerkte Programm der Gruppe.
  if not SameText(mGroup, FMenuGroup) then
  begin
    UpdateMenu;
  end;
end;

class procedure TAtlasIdeDebugReattach.Found(AGeneration: Integer; APid: Cardinal);
begin
  // Ein Treffer aus einem abgebrochenen oder ersetzten Warten zählt nicht.
  if (AGeneration <> FGeneration) or not Waiting then
  begin
    Exit;
  end;
  StopWaiter;
  HideStatus;
  AttachTo(APid, TAtlasReattach.NameOf(FWaitTarget));
end;

class procedure TAtlasIdeDebugReattach.AttachTo(APid: Cardinal; const AName: string);
var
  mServices: IOTADebuggerServices;
begin
  if not Supports(BorlandIDEServices, IOTADebuggerServices, mServices) then
  begin
    Exit;
  end;
  try
    mServices.AttachProcess(Integer(APid));
    Say(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.ReattachAttached, [AName, APid]));
  except
    // Kein Zugriff (anderer Benutzer, Dienst) oder falsche Plattform: klar melden statt still scheitern.
    Say(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.ReattachFailed, [AName, APid]));
  end;
end;

class procedure TAtlasIdeDebugReattach.OfferWait(const APath: string);
begin
  if TAtlasIdeDebugUnavailableFixes.Confirm(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.ReattachOfferWait,
    [TAtlasReattach.NameOf(APath)])) then
  begin
    WaitFor(APath);
  end;
end;

class procedure TAtlasIdeDebugReattach.Execute;
var
  mTarget: string;
  mCandidates: TAtlasReattachProcesses;
  mChosen: Integer;
begin
  mTarget := LastTarget;
  if mTarget = '' then
  begin
    Say(TAtlasDebugStrings.Text(TAtlasDebugTextId.ReattachNothing));
    Exit;
  end;
  case TAtlasReattach.Decide(mTarget, TAtlasIdeDebugProcesses.Named(TAtlasReattach.NameOf(mTarget), True),
    mCandidates) of
    TAtlasReattachDecision.Attach:
      AttachTo(mCandidates[0].Pid, mCandidates[0].Name);
    TAtlasReattachDecision.Choose:
      begin
        mChosen := TAtlasProcessChoiceDialog.Execute(TAtlasReattach.NameOf(mTarget), mCandidates);
        if mChosen >= 0 then
        begin
          AttachTo(mCandidates[mChosen].Pid, mCandidates[mChosen].Name);
        end;
      end;
    TAtlasReattachDecision.Wait:
      OfferWait(mTarget);
  end;
end;

class procedure TAtlasIdeDebugReattach.WaitForStart;
var
  mDialog: TOpenDialog;
  mDefault: string;
begin
  mDefault := LastTarget;
  if mDefault = '' then
  begin
    mDefault := ProjectTarget;
  end;
  mDialog := TOpenDialog.Create(nil);
  try
    mDialog.Title := TAtlasDebugStrings.Text(TAtlasDebugTextId.ReattachChooseExe);
    mDialog.Filter := TAtlasDebugStrings.Text(TAtlasDebugTextId.ReattachExeFilter);
    mDialog.Options := mDialog.Options + [ofFileMustExist];
    mDialog.InitialDir := ExtractFileDir(mDefault);
    mDialog.FileName := ExtractFileName(mDefault);
    if mDialog.Execute then
    begin
      WaitFor(mDialog.FileName);
    end;
  finally
    mDialog.Free;
  end;
end;

class procedure TAtlasIdeDebugReattach.InstallMenu;
var
  mParent: TMenuItem;
begin
  mParent := RunMenu;
  if (mParent = nil) or (FMenuReattach <> nil) then
  begin
    Exit;
  end;
  FMenuReattach := TMenuItem.Create(nil);
  FMenuReattach.Name := cReattachItemName;
  FMenuReattach.OnClick := FHandler.ReattachClick;
  mParent.Add(FMenuReattach);
  FMenuWait := TMenuItem.Create(nil);
  FMenuWait.Name := cWaitItemName;
  FMenuWait.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.ReattachWaitMenu);
  FMenuWait.OnClick := FHandler.WaitClick;
  mParent.Add(FMenuWait);
  UpdateMenu;
end;

class procedure TAtlasIdeDebugReattach.RemoveMenu;
begin
  FreeAndNil(FMenuReattach);
  FreeAndNil(FMenuWait);
end;

class procedure TAtlasIdeDebugReattach.UpdateMenu;
var
  mTarget: string;
begin
  if FMenuReattach = nil then
  begin
    Exit;
  end;
  FMenuGroup := CurrentGroup;
  mTarget := LastTarget;
  if mTarget = '' then
  begin
    FMenuReattach.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.SettingsDebugReattach);
    Exit;
  end;
  FMenuReattach.Caption := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.ReattachCommand,
    [TAtlasReattach.NameOf(mTarget)]);
end;

end.
