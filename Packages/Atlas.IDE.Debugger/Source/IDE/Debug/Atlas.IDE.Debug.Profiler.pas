unit Atlas.IDE.Debug.Profiler;

// Stichproben-Profiler (#2057) in der IDE. Gemessen wird im Server (Win64,
// sieht auch 64-Bit-Programme); das Plugin startet und beendet die Messung
// und zeigt die Läufe:
//   - „Mit Profil ausführen“ (RunWithProfile): aktives Projekt bei Bedarf
//     übersetzen, ohne Debugger mit seinen Startoptionen starten
//     (TAtlasIdeLaunchProcesses) und atlas.server.profilerStart mit der Kennung.
//   - „Profil starten/beenden“ (Toggle): während eines Laufs
//     atlas.server.profilerStop, sonst atlas.server.profilerStart für das gerade debuggte
//     Programm.
//   - Solange ein Lauf geht, fragt ein Zeitgeber einmal je Sekunde
//     atlas.server.profilerStatus. Endet das Programm, schreibt der Server die Datei
//     selbst; das Fenster zeigt sie dann.
//   - Fenster „Atlas: Profil“: die letzten fünf Läufe aus dem Ordner von
//     TAtlasProfileStore (die Datei liest das Plugin selbst), Methoden mit
//     Eigen- und Gesamtanteil, „Nur eigener Code“, Vergleich mit dem vorigen
//     Lauf, Doppelklick öffnet Datei und Zeile.
// Antworten des Servers kommen über TAtlasIdeHost nur, solange der Scope des
// Moduls offen ist (Regel 3). Nach Release misst ein laufendes Profil weiter,
// bis das Programm endet; der Server schreibt die Datei dann selbst.
// Gesichert über TAtlasFeature.Debugger. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls,
  Atlas.Core.Modules.Contract,
  Atlas.Text.Profile,
  Atlas.Core.Debug.Profiler,
  Atlas.UI.Debug.ProfileFrame;

type
  TAtlasIdeDebugProfiler = class
  public const
    cStatusIntervalMs = 1000;
    cRequestTimeoutMs = 15000;
  private type
    /// <summary>Besitzer des Zeitgebers (OnTimer braucht eine Methode eines Objekts).</summary>
    TTicker = class
    public
      procedure Tick(Sender: TObject);
    end;
    TRunState = record
      Running: Boolean;
      /// <summary>Eine Anfrage ist unterwegs; keine zweite.</summary>
      Busy: Boolean;
      ProcessId: Cardinal;
    end;
    TLoaded = record
      Path: string;
      Profile: TAtlasProfile;
    end;
  private class var
    FScopeOf: TFunc<IAtlasModuleScope>;
    FMessage: TProc<string>;
    FTicker: TTicker;
    FTimer: TTimer;
    FRun: TRunState;
    FRuns: TArray<string>;
    FCurrent: TLoaded;
    FPrevious: TLoaded;
    class procedure Say(const AText: string); static;
    class function Request(const ACommand, AArguments: string; const ADone: TProc<string>): Boolean; static;
    class procedure StartFor(const ATarget: TAtlasProfilerTarget); static;
    class procedure StartAnswered(const AJson: string; AProcessId: Cardinal); static;
    class procedure Stop; static;
    class procedure Stopped(const AJson: string); static;
    class procedure PollStatus; static;
    class procedure StatusArrived(const AJson: string); static;
    class procedure Finished(const AFile: string); static;
    class procedure SetRunning(ARunning: Boolean); static;
    class function TargetOfActiveProject(out ATarget: TAtlasProfilerTarget): Boolean; static;
    /// <summary>Aktives Projekt bei Bedarf übersetzen und ohne Debugger starten; False mit Meldung.</summary>
    class function LaunchActiveProject(out ATarget: TAtlasProfilerTarget): Boolean; static;
    class function Load(const APath: string; var ALoaded: TLoaded): Boolean; static;
    class procedure WireFrame(AFrame: TAtlasDebugProfileFrame); static;
    class procedure ShowRun; static;
    class procedure OpenRow(const ARow: TAtlasProfileRow); static;
  public
    /// <summary>AScopeOf: Scope des Moduls für Antworten des Servers; AMessage: Zeile für die Meldungsansicht.
    /// </summary>
    class procedure Start(const AScopeOf: TFunc<IAtlasModuleScope>; const AMessage: TProc<string>); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
    /// <summary>Fenster „Atlas: Profil“ zeigen; ohne debug.profiler nur ein Hinweis.</summary>
    class procedure ShowWindow; static;
    class procedure RunWithProfile; static;
    class procedure Toggle; static;
    /// <summary>Läufe neu einlesen und ASelect (Pfad oder Dateiname; '' = neuester) zeigen.</summary>
    class procedure Reload(const ASelect: string); static;
    /// <summary>Ordner der Profildateien (wie im Server: Atlas-Cache unter %LOCALAPPDATA%).</summary>
    class function Folder: string; static;
  end;

implementation

uses
  System.Math,
  System.IOUtils,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.StartProfiles.Store,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.StartOptions,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.Sources,
  Atlas.IDE.Debug.LaunchProbe,
  Atlas.IDE.Debug.ProfileWindow,
  Atlas.UI.Debug.Profile.Strings;

{ TAtlasIdeDebugProfiler.TTicker }

procedure TAtlasIdeDebugProfiler.TTicker.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugProfiler.PollStatus);
end;

{ TAtlasIdeDebugProfiler }

class procedure TAtlasIdeDebugProfiler.Start(const AScopeOf: TFunc<IAtlasModuleScope>;
  const AMessage: TProc<string>);
begin
  FScopeOf := AScopeOf;
  FMessage := AMessage;
  if FTimer = nil then
  begin
    FTicker := TTicker.Create;
    FTimer := TTimer.Create(nil);
    FTimer.Enabled := False;
    FTimer.Interval := cStatusIntervalMs;
    FTimer.OnTimer := FTicker.Tick;
  end;
  TAtlasIdeDebugProfileWindow.OnFrame :=
    procedure(AFrame: TAtlasDebugProfileFrame)
    begin
      WireFrame(AFrame);
    end;
  TAtlasIdeDebugProfileWindow.Prepare;
end;

class procedure TAtlasIdeDebugProfiler.Release;
var
  mFrame: TAtlasDebugProfileFrame;
begin
  // Zuerst der Zeitgeber: Nach dem Abmelden darf keine Anfrage mehr gehen.
  FreeAndNil(FTimer);
  FreeAndNil(FTicker);
  // Der Frame kann das Abmelden überleben (angedocktes Fenster): Ereignisse lösen.
  mFrame := TAtlasIdeDebugProfileWindow.ExistingFrame;
  if mFrame <> nil then
  begin
    mFrame.OnRunChange := nil;
    mFrame.OnOptionsChange := nil;
    mFrame.OnToggle := nil;
    mFrame.OnReload := nil;
    mFrame.OnOpen := nil;
  end;
  TAtlasIdeDebugProfileWindow.OnFrame := nil;
  TAtlasIdeDebugProfileWindow.Release;
  FRun := Default(TRunState);
  FRuns := nil;
  FCurrent := Default(TLoaded);
  FPrevious := Default(TLoaded);
  FScopeOf := nil;
  FMessage := nil;
end;

class function TAtlasIdeDebugProfiler.Started: Boolean;
begin
  Result := FTimer <> nil;
end;

class procedure TAtlasIdeDebugProfiler.ApplySettings;
begin
  if not TAtlasIdeSettings.Current.DebugProfiler then
  begin
    TAtlasIdeDebugProfileWindow.Hide;
  end;
end;

class procedure TAtlasIdeDebugProfiler.ThemeChanged;
begin
  TAtlasIdeDebugProfileWindow.ApplyTheme;
end;

class procedure TAtlasIdeDebugProfiler.Say(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

class function TAtlasIdeDebugProfiler.Folder: string;
begin
  Result := TAtlasProfileStore.Folder(TPath.Combine(TPath.GetCachePath, 'Atlas'));
end;

class function TAtlasIdeDebugProfiler.Request(const ACommand, AArguments: string;
  const ADone: TProc<string>): Boolean;
begin
  // Nebenläufig zu anderen Befehlen: Der Zeitgeber fragt den Status, während andere Fenster den Server fragen.
  Result := Assigned(FScopeOf) and TAtlasIdeHost.RunServerCommandAsync(FScopeOf(), TAtlasFeature.Debugger,
    ACommand, AArguments, cRequestTimeoutMs, ADone);
end;

class procedure TAtlasIdeDebugProfiler.ShowWindow;
begin
  if not (Started and TAtlasIdeSettings.Current.DebugProfiler) then
  begin
    Say(TAtlasProfileStrings.Text(TAtlasProfileTextId.ProfileOff));
    Exit;
  end;
  WireFrame(TAtlasIdeDebugProfileWindow.Show);
  Reload(FCurrent.Path);
end;

class procedure TAtlasIdeDebugProfiler.WireFrame(AFrame: TAtlasDebugProfileFrame);
begin
  if AFrame = nil then
  begin
    Exit;
  end;
  AFrame.OnRunChange := ShowRun;
  AFrame.OnOptionsChange := ShowRun;
  AFrame.OnToggle := Toggle;
  AFrame.OnReload :=
    procedure
    begin
      Reload(FCurrent.Path);
    end;
  // Eigene anonyme Methode: OpenRow nimmt die Zeile als const, TProc<T> ohne (E2010 in Delphi).
  AFrame.OnOpen :=
    procedure(ARow: TAtlasProfileRow)
    begin
      OpenRow(ARow);
    end;
  AFrame.SetRunning(FRun.Running);
end;

{ Messung }

class function TAtlasIdeDebugProfiler.TargetOfActiveProject(out ATarget: TAtlasProfilerTarget): Boolean;
var
  mProject: IOTAProject;
begin
  ATarget := Default(TAtlasProfilerTarget);
  ATarget.IntervalMs := TAtlasIdeSettings.Current.DebugProfilerIntervalMs;
  mProject := TAtlasIdeStartOptions.ActiveProject;
  Result := (mProject <> nil) and (mProject.ProjectOptions <> nil);
  if Result then
  begin
    ATarget.ProgramName := mProject.ProjectOptions.TargetName;
    ATarget.Project := mProject.FileName;
    ATarget.Platform := mProject.CurrentPlatform;
  end;
end;

class procedure TAtlasIdeDebugProfiler.RunWithProfile;
var
  mTarget: TAtlasProfilerTarget;
begin
  if FRun.Running or FRun.Busy then
  begin
    Toggle;
  end
  else if LaunchActiveProject(mTarget) then
  begin
    StartFor(mTarget);
  end;
end;

class function TAtlasIdeDebugProfiler.LaunchActiveProject(out ATarget: TAtlasProfilerTarget): Boolean;
var
  mProject: IOTAProject;
  mOptions: TAtlasStartOptions;
begin
  Result := False;
  if not TargetOfActiveProject(ATarget) then
  begin
    Say(TAtlasProfileStrings.Text(TAtlasProfileTextId.ProfileNoProject));
    Exit;
  end;
  mProject := TAtlasIdeStartOptions.ActiveProject;
  if (mProject.ProjectBuilder <> nil) and mProject.ProjectBuilder.ShouldBuild and
    not mProject.ProjectBuilder.BuildProject(cmOTAMake, True, True) then
  begin
    Say(TAtlasProfileStrings.Fmt(TAtlasProfileTextId.ProfileBuildFailed, [ExtractFileName(ATarget.Project)]));
    Exit;
  end;
  if not FileExists(ATarget.ProgramName) then
  begin
    Say(TAtlasProfileStrings.Fmt(TAtlasProfileTextId.ProfileNoExe, [ATarget.ProgramName]));
    Exit;
  end;
  // Ohne Konfiguration startet das Programm ohne Parameter im Ordner der EXE.
  if not TAtlasIdeStartOptions.ReadOptions(mProject, mOptions) then
  begin
    mOptions := Default(TAtlasStartOptions);
  end;
  ATarget.ProcessId := TAtlasIdeLaunchProcesses.Start(ATarget.ProgramName, mOptions.Parameters, mOptions.WorkingDir,
    TAtlasStartProfiles.DecodeEnvironment(mOptions.Environment));
  Result := ATarget.ProcessId <> 0;
  if not Result then
  begin
    Say(TAtlasProfileStrings.Fmt(TAtlasProfileTextId.ProfileStartFailed, [ExtractFileName(ATarget.ProgramName)]));
  end;
end;

class procedure TAtlasIdeDebugProfiler.Toggle;
var
  mTarget: TAtlasProfilerTarget;
  mProcess: IOTAProcess;
begin
  if FRun.Busy then
  begin
    Exit;
  end;
  if FRun.Running then
  begin
    Stop;
    Exit;
  end;
  mProcess := nil;
  if TAtlasIdeDebugSession.Active then
  begin
    mProcess := TAtlasIdeDebugSession.Process;
  end;
  if (mProcess = nil) or (mProcess.ProcessId = 0) then
  begin
    Say(TAtlasProfileStrings.Text(TAtlasProfileTextId.ProfileNoProcess));
    Exit;
  end;
  TargetOfActiveProject(mTarget);
  mTarget.ProcessId := mProcess.ProcessId;
  StartFor(mTarget);
end;

class procedure TAtlasIdeDebugProfiler.StartFor(const ATarget: TAtlasProfilerTarget);
var
  mPid: Cardinal;
begin
  // Der Server misst; läuft er noch nicht, startet ihn ActiveSession.
  if TAtlasIdeHost.ActiveSession = nil then
  begin
    Say(TAtlasProfileStrings.Text(TAtlasProfileTextId.ProfileServerFailed));
    Exit;
  end;
  mPid := ATarget.ProcessId;
  FRun.Busy := Request(TAtlasProfilerProtocol.cStartCommand, TAtlasProfilerProtocol.StartArguments(ATarget),
    procedure(AJson: string)
    begin
      StartAnswered(AJson, mPid);
    end);
  if not FRun.Busy then
  begin
    Say(TAtlasProfileStrings.Text(TAtlasProfileTextId.ProfileServerFailed));
  end;
end;

class procedure TAtlasIdeDebugProfiler.StartAnswered(const AJson: string; AProcessId: Cardinal);
var
  mAnswer: TAtlasProfilerStartAnswer;
begin
  FRun.Busy := False;
  if not TAtlasProfilerProtocol.ReadStart(AJson, mAnswer) then
  begin
    Say(TAtlasProfileStrings.Text(TAtlasProfileTextId.ProfileServerFailed));
    Exit;
  end;
  FRun.ProcessId := AProcessId;
  Say(TAtlasProfileStrings.Fmt(TAtlasProfileTextId.ProfileStarted, [AProcessId,
    TAtlasIdeSettings.Current.DebugProfilerIntervalMs]));
  if mAnswer.Routines = 0 then
  begin
    Say(TAtlasProfileStrings.Text(TAtlasProfileTextId.ProfileNoMap));
  end;
  SetRunning(True);
end;

class procedure TAtlasIdeDebugProfiler.Stop;
begin
  FRun.Busy := Request(TAtlasProfilerProtocol.cStopCommand, TAtlasProfilerProtocol.cEmptyArguments,
    procedure(AJson: string)
    begin
      Stopped(AJson);
    end);
  if not FRun.Busy then
  begin
    Say(TAtlasProfileStrings.Text(TAtlasProfileTextId.ProfileServerFailed));
  end;
end;

class procedure TAtlasIdeDebugProfiler.Stopped(const AJson: string);
var
  mAnswer: TAtlasProfilerStopAnswer;
begin
  FRun.Busy := False;
  if not TAtlasProfilerProtocol.ReadStop(AJson, mAnswer) then
  begin
    // Das Programm kann gerade geendet haben; dann kennt der Status die Datei.
    PollStatus;
    Exit;
  end;
  Say(TAtlasProfileStrings.Fmt(TAtlasProfileTextId.ProfileStopped, [mAnswer.FileName, mAnswer.Samples]));
  SetRunning(False);
  if mAnswer.Path <> '' then
  begin
    Finished(mAnswer.Path);
  end
  else
  begin
    Finished(mAnswer.FileName);
  end;
end;

class procedure TAtlasIdeDebugProfiler.PollStatus;
begin
  if FRun.Busy then
  begin
    Exit;
  end;
  FRun.Busy := Request(TAtlasProfilerProtocol.cStatusCommand, TAtlasProfilerProtocol.cEmptyArguments,
    procedure(AJson: string)
    begin
      StatusArrived(AJson);
    end);
end;

class procedure TAtlasIdeDebugProfiler.StatusArrived(const AJson: string);
var
  mAnswer: TAtlasProfilerStatusAnswer;
  mFrame: TAtlasDebugProfileFrame;
begin
  FRun.Busy := False;
  if not TAtlasProfilerProtocol.ReadStatus(AJson, mAnswer) then
  begin
    Exit;
  end;
  if mAnswer.Running then
  begin
    mFrame := TAtlasIdeDebugProfileWindow.ExistingFrame;
    if mFrame <> nil then
    begin
      mFrame.SetSummary(TAtlasProfileStrings.Fmt(TAtlasProfileTextId.ProfileRunning, [mAnswer.ProcessId,
        FormatFloat('0.0', mAnswer.ElapsedMs / 1000, FormatSettings), mAnswer.Samples]));
    end;
    Exit;
  end;
  // Das Programm ist geendet; der Server hat die Datei schon geschrieben.
  SetRunning(False);
  Finished(mAnswer.LastFile);
end;

class procedure TAtlasIdeDebugProfiler.SetRunning(ARunning: Boolean);
var
  mFrame: TAtlasDebugProfileFrame;
begin
  FRun.Running := ARunning;
  if FTimer <> nil then
  begin
    FTimer.Enabled := ARunning;
  end;
  mFrame := TAtlasIdeDebugProfileWindow.ExistingFrame;
  if mFrame <> nil then
  begin
    mFrame.SetRunning(ARunning);
  end;
end;

class procedure TAtlasIdeDebugProfiler.Finished(const AFile: string);
begin
  if AFile = '' then
  begin
    Exit;
  end;
  if TAtlasIdeSettings.Current.DebugProfiler then
  begin
    TAtlasIdeDebugProfileWindow.Show;
  end;
  Reload(AFile);
end;

{ Anzeige }

class procedure TAtlasIdeDebugProfiler.Reload(const ASelect: string);
var
  mFrame: TAtlasDebugProfileFrame;
  mFiles, mTitles: TArray<string>;
  mIndex, mSelected: Integer;
begin
  mFrame := TAtlasIdeDebugProfileWindow.ExistingFrame;
  if mFrame = nil then
  begin
    Exit;
  end;
  mFiles := nil;
  if TDirectory.Exists(Folder) then
  begin
    mFiles := TDirectory.GetFiles(Folder, TAtlasProfileStore.cPrefix + '*.json');
  end;
  FRuns := TAtlasProfileStore.Newest(mFiles);
  SetLength(mTitles, Length(FRuns));
  mSelected := Min(0, High(FRuns));
  for mIndex := 0 to High(FRuns) do
  begin
    mTitles[mIndex] := TAtlasProfileTable.RunTitle(FRuns[mIndex]);
    if (ASelect <> '') and SameText(ExtractFileName(FRuns[mIndex]), ExtractFileName(ASelect)) then
    begin
      mSelected := mIndex;
    end;
  end;
  mFrame.SetRuns(mTitles, mSelected);
  // Neu einlesen: Eine Datei gleichen Namens kann neu geschrieben sein.
  FCurrent := Default(TLoaded);
  FPrevious := Default(TLoaded);
  ShowRun;
end;

class function TAtlasIdeDebugProfiler.Load(const APath: string; var ALoaded: TLoaded): Boolean;
begin
  Result := SameText(ALoaded.Path, APath) and (APath <> '');
  if Result then
  begin
    Exit;
  end;
  ALoaded := Default(TLoaded);
  Result := FileExists(APath) and TAtlasProfileJson.TryParse(TFile.ReadAllText(APath, TEncoding.UTF8),
    ALoaded.Profile);
  if Result then
  begin
    ALoaded.Path := APath;
  end
  else
  begin
    Say(TAtlasProfileStrings.Fmt(TAtlasProfileTextId.ProfileUnreadable, [ExtractFileName(APath)]));
  end;
end;

/// <summary>„App.exe · 980 Proben · 12,5 s · alle 10 ms“.</summary>
function SummaryOf(const AProfile: TAtlasProfile): string;
begin
  Result := TAtlasProfileStrings.Fmt(TAtlasProfileTextId.ProfileSummary, [ExtractFileName(AProfile.ProgramName),
    AProfile.Samples, FormatFloat('0.0', AProfile.DurationMs / 1000, FormatSettings), AProfile.IntervalMs]);
end;

class procedure TAtlasIdeDebugProfiler.ShowRun;
var
  mFrame: TAtlasDebugProfileFrame;
  mPrevious: string;
begin
  mFrame := TAtlasIdeDebugProfileWindow.ExistingFrame;
  if mFrame = nil then
  begin
    Exit;
  end;
  if (mFrame.RunIndex < 0) or (mFrame.RunIndex > High(FRuns)) or not Load(FRuns[mFrame.RunIndex], FCurrent) then
  begin
    mFrame.ShowRows(nil, False);
    mFrame.SetSummary(TAtlasProfileStrings.Text(TAtlasProfileTextId.ProfileEmpty));
    Exit;
  end;
  mPrevious := '';
  if mFrame.CompareWanted then
  begin
    mPrevious := TAtlasProfileTable.PreviousRun(FRuns, FCurrent.Path);
  end;
  if (mPrevious <> '') and Load(mPrevious, FPrevious) then
  begin
    mFrame.ShowRows(TAtlasProfileTable.CompareRows(FPrevious.Profile, FCurrent.Profile, mFrame.OwnOnly,
      FormatSettings), True);
    mFrame.SetSummary(TAtlasProfileStrings.Fmt(TAtlasProfileTextId.ProfileCompareSummary,
      [TAtlasProfileTable.RunTitle(FPrevious.Path), TAtlasProfileTable.RunTitle(FCurrent.Path)]));
    Exit;
  end;
  mFrame.ShowRows(TAtlasProfileTable.MethodRows(FCurrent.Profile, mFrame.OwnOnly, FormatSettings), False);
  if mFrame.CompareWanted then
  begin
    mFrame.SetSummary(TAtlasProfileStrings.Text(TAtlasProfileTextId.ProfileNoPrevious));
  end
  else
  begin
    mFrame.SetSummary(SummaryOf(FCurrent.Profile));
  end;
end;

class procedure TAtlasIdeDebugProfiler.OpenRow(const ARow: TAtlasProfileRow);
var
  mPath: string;
begin
  if ARow.FileName = '' then
  begin
    Exit;
  end;
  mPath := TAtlasIdeDebugSources.Resolve(ARow.FileName);
  if mPath = '' then
  begin
    Say(TAtlasProfileStrings.Fmt(TAtlasProfileTextId.ProfileNoSource, [ARow.FileName]));
    Exit;
  end;
  TAtlasIdeNavigation.GoToLocation(mPath, Max(ARow.Line - 1, 0), 0);
end;

end.
