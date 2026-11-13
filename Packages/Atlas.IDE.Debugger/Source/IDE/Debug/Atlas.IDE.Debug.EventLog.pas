unit Atlas.IDE.Debug.EventLog;

// Ereignisprotokoll beim Debuggen (#580), IDE-Schicht:
// - Quelle (vorher geprüft): Die Open Tools API meldet Ausgaben von
//   OutputDebugString und Haltepunkt-Meldungen nicht. Atlas liest sie deshalb
//   aus dem Fenster „Ereignisprotokoll“ der IDE mit: Formular, dessen Name
//   oder Klasse „EventLog“ enthält, darin die erste Liste (TCustomListBox bzw.
//   TCustomListView); neue Zeilen holt ein Zeitgeber alle cPollMs. Was Atlas
//   findet (oder nicht), steht einmal je Sitzung im Diagnoseprotokoll.
//   Module und Threads meldet ein IOTAProcessNotifier am Prozess der Sitzung;
//   gleiche Zeilen aus dem Fenster der IDE fallen dann weg.
// - Start und Ende der Sitzung (TAtlasIdeDebugSession) als Zeile „Prozess“;
//   die Zeit zählt ab dem Start. Der Inhalt bleibt bis „Leeren“.
// - Logpunkte (#583) und andere Teile schreiben über AddEntry.
// - Gemerkte Filter je Projekt in %LOCALAPPDATA%\Atlas\debug-eventlog-filters.json.
// - Sprung: Datei mit Zeile über TAtlasIdeDebugSources.Resolve, Unit.Routine
//   über die Arbeitsbereichssymbole des Servers (nur, wenn er läuft).
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Debug.EventLog,
  Atlas.Core.Debug.Logpoint,
  Atlas.Core.Debug.DialogCompletion,
  Atlas.IDE.Debug.Session,
  Atlas.UI.Debug.EventLogFrame;

type
  /// <summary>Dienste von Base für das Ereignisprotokoll (gesetzt von der Komposition).</summary>
  TAtlasEventLogServices = record
    Message: TProc<string>;
    Log: TProc<string>;
    Session: TFunc<TLspSession>;
  end;

  TAtlasIdeDebugEventLog = class
  public const
    cPollMs = 250;
    cFilterFileName = 'debug-eventlog-filters.json';
    cFiltersPerProject = 30;
  private type
    TListener = class(TAtlasIdeDebugListener)
    public
      procedure DebugStarted; override;
      procedure DebugEnded; override;
    end;
    TTicker = class
    public
      procedure Tick(Sender: TObject);
    end;
  private class var
    FServices: TAtlasEventLogServices;
    FListener: IAtlasIdeDebugListener;
    FLog: TAtlasEventLog;
    FFilters: TAtlasExpressionHistory;
    FFiltersKept: Boolean;
    FFiltersLoaded: Boolean;
    FTimer: TTimer;
    FTicker: TTicker;
    FStartTick: UInt64;
    FDirty: Boolean;
    FMerger: TAtlasLogpointMerger;
    class procedure Poll; static;
    /// <summary>Logpunkt-Zeilen zusammenführen; True, wenn die Zeile auf ihren Wert wartet (nicht anfügen).
    /// </summary>
    class function MergeLogpoint(var AKind: TAtlasEventKind; var AText: string): Boolean; static;
    class procedure Refresh; static;
    class procedure WireFrame(AFrame: TAtlasDebugEventLogFrame); static;
    class procedure OpenEntry(const AEntry: TAtlasEventEntry); static;
    class procedure SaveToFile; static;
    class function SavedFilters: TArray<string>; static;
    class procedure ChangeFilter(const AText: string; ARemember: Boolean); static;
  public
    class procedure Start(const AServices: TAtlasEventLogServices); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
    class procedure ShowWindow; static;
    /// <summary>Eintrag anfügen (Logpunkte #583 und andere); ohne laufendes Teil nichts.</summary>
    class procedure AddEntry(AKind: TAtlasEventKind; const AThread, AText: string); static;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  Vcl.Dialogs,
  ToolsAPI,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.EvaluateStore,
  Atlas.IDE.Debug.EventLogMirror,
  Atlas.IDE.Debug.EventLogWindow,
  Atlas.IDE.Debug.Sources,
  Atlas.UI.Debug.Strings;

const
  cFiltersWhat = 'Event log filters';
  cSymbolTimeoutMs = 1500;

type
  /// <summary>Module und Threads des Prozesses der Sitzung.</summary>
  TProcessWatch = class(TNotifierObject, IOTAProcessNotifier)
  public
    procedure ThreadCreated(const Thread: IOTAThread);
    procedure ThreadDestroyed(const Thread: IOTAThread);
    procedure ProcessModuleCreated(const ProcessModule: IOTAProcessModule);
    procedure ProcessModuleDestroyed(const ProcessModule: IOTAProcessModule);
    procedure Destroyed;
  end;

var
  GWatchProcess: IOTAProcess;
  GWatchIndex: Integer = -1;
  GMirror: TAtlasIdeEventLogMirror;

function FilterFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    TAtlasIdeDebugEventLog.cFilterFileName);
end;

function ThreadText(const AThread: IOTAThread): string;
begin
  Result := '';
  if AThread <> nil then
  begin
    Result := IntToStr(AThread.OSThreadID);
  end;
end;

{ TProcessWatch }

procedure TProcessWatch.ThreadCreated(const Thread: IOTAThread);
begin
  TAtlasIdeDebugEventLog.AddEntry(TAtlasEventKind.Thread, ThreadText(Thread),
    TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEventLogThreadStarted));
end;

procedure TProcessWatch.ThreadDestroyed(const Thread: IOTAThread);
begin
  TAtlasIdeDebugEventLog.AddEntry(TAtlasEventKind.Thread, ThreadText(Thread),
    TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEventLogThreadEnded));
end;

procedure TProcessWatch.ProcessModuleCreated(const ProcessModule: IOTAProcessModule);
begin
  TAtlasIdeDebugEventLog.AddEntry(TAtlasEventKind.Module, '',
    TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugEventLogModuleLoaded, [ProcessModule.FileName]));
end;

procedure TProcessWatch.ProcessModuleDestroyed(const ProcessModule: IOTAProcessModule);
begin
  TAtlasIdeDebugEventLog.AddEntry(TAtlasEventKind.Module, '',
    TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugEventLogModuleUnloaded, [ProcessModule.FileName]));
end;

procedure TProcessWatch.Destroyed;
begin
  // Der Prozess ist abgebaut; abmelden geht nicht mehr.
  GWatchIndex := -1;
  GWatchProcess := nil;
end;

procedure Unwatch;
begin
  if (GWatchProcess <> nil) and (GWatchIndex >= 0) then
  begin
    GWatchProcess.RemoveNotifier(GWatchIndex);
  end;
  GWatchIndex := -1;
  GWatchProcess := nil;
end;

procedure Watch;
begin
  Unwatch;
  GWatchProcess := TAtlasIdeDebugSession.Process;
  if GWatchProcess <> nil then
  begin
    GWatchIndex := GWatchProcess.AddNotifier(TProcessWatch.Create);
  end;
end;

{ TAtlasIdeDebugEventLog.TListener }

procedure TAtlasIdeDebugEventLog.TListener.DebugStarted;
begin
  TAtlasIdeDebugEventLog.FStartTick := GetTickCount64;
  TAtlasIdeDebugEventLog.AddEntry(TAtlasEventKind.Process, '',
    TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugEventLogSessionStarted,
    [ExtractFileName(TAtlasIdeDebugSession.LaunchProject)]));
  Watch;
  // Nur Zeilen ab jetzt; was das Fenster der IDE davor hatte, gehört zu früheren Läufen.
  GMirror.StartSession(TAtlasIdeDebugEventLog.FServices.Log);
  TAtlasIdeDebugEventLog.FTimer.Enabled := True;
end;

procedure TAtlasIdeDebugEventLog.TListener.DebugEnded;
begin
  TAtlasIdeDebugEventLog.Poll;
  Unwatch;
  TAtlasIdeDebugEventLog.AddEntry(TAtlasEventKind.Process, '',
    TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEventLogSessionEnded));
end;

{ TAtlasIdeDebugEventLog.TTicker }

procedure TAtlasIdeDebugEventLog.TTicker.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger,
    procedure
    begin
      if TAtlasIdeDebugSession.Active then
      begin
        TAtlasIdeDebugEventLog.Poll;
      end;
      TAtlasIdeDebugEventLog.Refresh;
    end);
end;

{ TAtlasIdeDebugEventLog }

class procedure TAtlasIdeDebugEventLog.Start(const AServices: TAtlasEventLogServices);
begin
  FServices := AServices;
  if FLog = nil then
  begin
    FLog := TAtlasEventLog.Create;
  end;
  if FFilters = nil then
  begin
    FFilters := TAtlasExpressionHistory.Create(cFiltersPerProject);
    FFiltersLoaded := False;
  end;
  if GMirror = nil then
  begin
    GMirror := TAtlasIdeEventLogMirror.Create(nil);
  end;
  if FTicker = nil then
  begin
    FTicker := TTicker.Create;
  end;
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(nil);
    FTimer.Interval := cPollMs;
    FTimer.OnTimer := FTicker.Tick;
  end;
  FTimer.Enabled := TAtlasIdeDebugSession.Active;
  TAtlasIdeDebugEventLogWindow.OnFrame :=
    procedure(AFrame: TAtlasDebugEventLogFrame)
    begin
      WireFrame(AFrame);
    end;
  TAtlasIdeDebugEventLogWindow.Prepare;
  if FListener = nil then
  begin
    FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FListener);
  end;
  TAtlasIdeDebugSession.Start;
end;

class procedure TAtlasIdeDebugEventLog.Release;
begin
  if FListener <> nil then
  begin
    TAtlasIdeDebugSession.RemoveListener(FListener);
  end;
  FListener := nil;
  Unwatch;
  TAtlasIdeDebugEventLogWindow.Release;
  FreeAndNil(FTimer);
  FreeAndNil(FTicker);
  FreeAndNil(GMirror);
  FreeAndNil(FFilters);
  FreeAndNil(FLog);
  FreeAndNil(FMerger);
  FServices := Default(TAtlasEventLogServices);
end;

class function TAtlasIdeDebugEventLog.Started: Boolean;
begin
  Result := FListener <> nil;
end;

class procedure TAtlasIdeDebugEventLog.ApplySettings;
begin
  if not Started then
  begin
    Exit;
  end;
  if not TAtlasIdeSettings.Current.DebugEventLog then
  begin
    TAtlasIdeDebugEventLogWindow.Hide;
    Exit;
  end;
  // debug.eventLogColors geändert: neu zeichnen.
  FDirty := True;
  Refresh;
end;

class procedure TAtlasIdeDebugEventLog.ThemeChanged;
begin
  TAtlasIdeDebugEventLogWindow.ApplyTheme;
end;

class procedure TAtlasIdeDebugEventLog.ShowWindow;
var
  mFrame: TAtlasDebugEventLogFrame;
begin
  if not Started then
  begin
    Exit;
  end;
  mFrame := TAtlasIdeDebugEventLogWindow.Show;
  if mFrame <> nil then
  begin
    WireFrame(mFrame);
    mFrame.SetLog(FLog, TAtlasEventColors.Parse(TAtlasIdeSettings.Current.DebugEventLogColors), SavedFilters);
  end;
end;

class procedure TAtlasIdeDebugEventLog.AddEntry(AKind: TAtlasEventKind; const AThread, AText: string);
var
  mElapsed: Int64;
begin
  if FLog = nil then
  begin
    Exit;
  end;
  mElapsed := 0;
  if FStartTick > 0 then
  begin
    mElapsed := Int64(GetTickCount64 - FStartTick);
  end;
  FLog.Add(TAtlasEventEntry.Create(mElapsed, AKind, AThread, AText));
  FDirty := True;
  if (FTimer <> nil) and not FTimer.Enabled then
  begin
    FTimer.Enabled := True;
  end;
end;

class procedure TAtlasIdeDebugEventLog.Poll;
var
  mLine, mText, mThread: string;
  mKind: TAtlasEventKind;
begin
  if GMirror = nil then
  begin
    Exit;
  end;
  for mLine in GMirror.NewLines do
  begin
    mKind := TAtlasEventLog.Classify(mLine, mText, mThread);
    // Module, Threads und Prozess meldet der Notifier; aus dem Fenster nur, wenn er fehlt.
    if (GWatchIndex >= 0) and (mKind in [TAtlasEventKind.Module, TAtlasEventKind.Thread,
      TAtlasEventKind.Process]) then
    begin
      Continue;
    end;
    if not MergeLogpoint(mKind, mText) then
    begin
      AddEntry(mKind, mThread, mText);
    end;
  end;
end;

class function TAtlasIdeDebugEventLog.MergeLogpoint(var AKind: TAtlasEventKind; var AText: string): Boolean;
var
  mPrefix, mOutput: string;
  mIsLogpoint: Boolean;
begin
  Result := False;
  if not TAtlasIdeSettings.Current.DebugLogpoints then
  begin
    Exit;
  end;
  mPrefix := TAtlasIdeSettings.Current.DebugLogpointPrefix;
  if (FMerger = nil) or (FMerger.Prefix <> mPrefix) then
  begin
    FreeAndNil(FMerger);
    FMerger := TAtlasLogpointMerger.Create(mPrefix);
  end;
  // Logpunkte (#583): Meldung mit „{0}“ wartet auf die Zeile mit dem Wert.
  if (AKind <> TAtlasEventKind.Breakpoint) and not FMerger.Pending then
  begin
    Exit;
  end;
  if FMerger.Feed(AText, mOutput, mIsLogpoint) then
  begin
    AKind := TAtlasEventKind.Logpoint;
    AText := mOutput;
    Exit(False);
  end;
  Result := mIsLogpoint;
end;

class procedure TAtlasIdeDebugEventLog.Refresh;
var
  mFrame: TAtlasDebugEventLogFrame;
begin
  if not FDirty then
  begin
    if not TAtlasIdeDebugSession.Active and (FTimer <> nil) then
    begin
      FTimer.Enabled := False;
    end;
    Exit;
  end;
  FDirty := False;
  mFrame := TAtlasIdeDebugEventLogWindow.ExistingFrame;
  if (mFrame <> nil) and TAtlasIdeDebugEventLogWindow.Visible then
  begin
    mFrame.SetLog(FLog, TAtlasEventColors.Parse(TAtlasIdeSettings.Current.DebugEventLogColors), SavedFilters);
  end;
end;

class function TAtlasIdeDebugEventLog.SavedFilters: TArray<string>;
begin
  Result := nil;
  if FFilters = nil then
  begin
    Exit;
  end;
  if not FFiltersLoaded then
  begin
    FFiltersLoaded := True;
    // Gesperrt: leer beginnen und die Datei nicht überschreiben.
    FFiltersKept := not TAtlasDataFile.Writable(TAtlasDataFile.Load(FilterFile, cFiltersWhat,
      function(const AText: string): Boolean
      begin
        Result := FFilters.LoadFromText(AText);
      end));
  end;
  Result := FFilters.Items(TAtlasIdeEvaluateStore.CurrentProject);
end;

class procedure TAtlasIdeDebugEventLog.ChangeFilter(const AText: string; ARemember: Boolean);
var
  mChanged: Boolean;
  mFrame: TAtlasDebugEventLogFrame;
begin
  SavedFilters;
  if ARemember then
  begin
    mChanged := FFilters.Add(TAtlasIdeEvaluateStore.CurrentProject, AText);
  end
  else
  begin
    mChanged := FFilters.Remove(TAtlasIdeEvaluateStore.CurrentProject, AText);
  end;
  if mChanged and not FFiltersKept then
  begin
    try
      TAtlasDataFile.Write(FilterFile, FFilters.ToText);
    except
      on E: Exception do
        TAtlasDataFile.ReportNotWritten(cFiltersWhat, E);
    end;
  end;
  mFrame := TAtlasIdeDebugEventLogWindow.ExistingFrame;
  if mFrame <> nil then
  begin
    mFrame.SetLog(FLog, TAtlasEventColors.Parse(TAtlasIdeSettings.Current.DebugEventLogColors), SavedFilters);
  end;
end;

class procedure TAtlasIdeDebugEventLog.WireFrame(AFrame: TAtlasDebugEventLogFrame);
begin
  AFrame.OnOpen :=
    procedure(AEntry: TAtlasEventEntry)
    begin
      OpenEntry(AEntry);
    end;
  AFrame.OnSave :=
    procedure
    begin
      SaveToFile;
    end;
  AFrame.OnClear :=
    procedure
    begin
      FLog.Clear;
      FDirty := True;
      Refresh;
    end;
  AFrame.OnRememberFilter :=
    procedure(AText: string)
    begin
      ChangeFilter(AText, True);
    end;
  AFrame.OnForgetFilter :=
    procedure(AText: string)
    begin
      ChangeFilter(AText, False);
    end;
end;

/// <summary>Symbol, dessen Name und Container zu ASymbol ("Unit.Routine", "Klasse.Methode") passen.</summary>
function TryFindSymbol(const ASession: TLspSession; const ASymbol: string; out AFound: TAtlasSymbol): Boolean;
var
  mName: string;
  mCandidate: TAtlasSymbol;
  mSymbols: TArray<TAtlasSymbol>;
begin
  Result := False;
  AFound := Default(TAtlasSymbol);
  mName := ASymbol.Substring(ASymbol.LastIndexOf('.') + 1);
  try
    mSymbols := ASession.WorkspaceSymbols(mName, cSymbolTimeoutMs);
  except
    on ELspClientError do
      Exit;
  end;
  for mCandidate in mSymbols do
  begin
    if SameText(mCandidate.Name, mName) and (mCandidate.FileName <> '') then
    begin
      // Ganzer Name gleich am Ende ("TForm1.Button1Click" passt zu "Main.TForm1.Button1Click") gewinnt.
      if ASymbol.ToUpper.EndsWith((mCandidate.Container + '.' + mCandidate.Name).ToUpper) or not Result then
      begin
        AFound := mCandidate;
        Result := True;
      end;
    end;
  end;
end;

class procedure TAtlasIdeDebugEventLog.OpenEntry(const AEntry: TAtlasEventEntry);
var
  mJump: TAtlasEventJump;
  mPath: string;
  mSession: TLspSession;
  mSymbol: TAtlasSymbol;
begin
  mJump := TAtlasEventJump.Find(AEntry.Text);
  case mJump.Kind of
    TAtlasEventJumpKind.None:
      Exit;
    TAtlasEventJumpKind.FileLine:
      begin
        mPath := TAtlasIdeDebugSources.Resolve(mJump.FileName.Replace('/', PathDelim));
        if mPath <> '' then
        begin
          TAtlasIdeNavigation.GoToLocation(mPath, mJump.Line - 1, 0);
          Exit;
        end;
      end;
    TAtlasEventJumpKind.Symbol:
      begin
        mSession := nil;
        if Assigned(FServices.Session) then
        begin
          mSession := FServices.Session();
        end;
        if (mSession <> nil) and TryFindSymbol(mSession, mJump.Symbol, mSymbol) then
        begin
          TAtlasIdeNavigation.GoToLocation(mSymbol.FileName, mSymbol.Line, mSymbol.Character);
          Exit;
        end;
      end;
  end;
  if Assigned(FServices.Message) then
  begin
    FServices.Message(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugEventLogNotFound,
      [mJump.FileName + mJump.Symbol]));
  end;
end;

class procedure TAtlasIdeDebugEventLog.SaveToFile;
var
  mDialog: TSaveDialog;
begin
  mDialog := TSaveDialog.Create(nil);
  try
    mDialog.Filter := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEventLogFileTypes);
    mDialog.DefaultExt := 'txt';
    mDialog.FileName := ChangeFileExt(ExtractFileName(TAtlasIdeEvaluateStore.CurrentProject), '') + '-events.txt';
    mDialog.Options := mDialog.Options + [ofOverwritePrompt];
    if not mDialog.Execute then
    begin
      Exit;
    end;
    TFile.WriteAllText(mDialog.FileName, FLog.ToText, TEncoding.UTF8);
    if Assigned(FServices.Message) then
    begin
      FServices.Message(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugEventLogSaved, [mDialog.FileName]));
    end;
  finally
    mDialog.Free;
  end;
end;

end.
