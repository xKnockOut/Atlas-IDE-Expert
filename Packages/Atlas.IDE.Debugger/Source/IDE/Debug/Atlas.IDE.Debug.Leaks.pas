unit Atlas.IDE.Debug.Leaks;

// Leckbericht am Ende einer Debug-Sitzung (#1875):
//   - Beim Start merkt Atlas Zeit, Prozess und EXE. Solange das Programm läuft,
//     sieht ein Zeitgeber (cIntervalMs) nach Dialogfenstern des Prozesses und
//     liest ihre Texte (Fenster und Kindfenster über GetWindowText, kein Klick).
//     Steht darin ein Leckbericht (Meldungsfenster von
//     ReportMemoryLeaksOnShutdown), merkt Atlas ihn.
//   - Am Ende liest Atlas die FastMM-Logdatei neben der EXE, wenn sie nach dem
//     Start geschrieben wurde, und wählt (Atlas.Core.Debug.LeakCapture).
//   - Vergleich mit dem letzten Lauf (debug.leakReport.compare): Stand in
//     .atlas-local neben der .dproj je Konfiguration und Plattform; „bekannt“
//     bleibt erhalten.
//   - Ohne Aufrufstapel fragt Atlas den Server nach Kandidaten
//     (atlas.server.leakCandidates); mit Stapeln zeigt es die Gruppen des
//     Berichts mit ihrer Erzeugungsstelle.
//   - Fenster „Atlas-Lecks“ öffnet sich bei Lecks (debug.leakReport.window),
//     sonst eine Zeile im Meldungsfenster.
// Teil „DebugLeakReport“ (debug.leakReport); Release meldet den Zuhörer ab und
// gibt Zeitgeber und Fenster frei (Regel 3). Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Debug.LeakCapture,
  Atlas.Core.Debug.LeakView,
  Atlas.IDE.Debug.Session;

type
  TAtlasIdeDebugLeaks = class
  public const
    cIntervalMs = 500;
    cTimeoutMs = 30000;
    cLocalFolder = '.atlas-local';
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
    FScope: IAtlasModuleScope;
    FListener: IAtlasIdeDebugListener;
    FTicker: TTicker;
    FTimer: TTimer;
    FMessage: TProc<string>;
    FStarted: TDateTime;
    FProcessId: Cardinal;
    FExeFile: string;
    FProject: string;
    FConfiguration: string;
    FPlatform: string;
    FBox: TAtlasLeakCapture;
    FCapture: TAtlasLeakCapture;
    FEntries: TArray<TAtlasLeakEntry>;
    FPlaces: TArray<TAtlasLeakPlace>;
    FHistory: TAtlasLeakHistory;
    FStatus: string;
    class procedure Began; static;
    class procedure Ended; static;
    class procedure ScanWindows; static;
    class function ReadLogFile: TAtlasLeakCapture; static;
    class function HistoryFile: string; static;
    class procedure Present; static;
    class procedure RequestCandidates; static;
    class procedure Refresh; static;
    class procedure Open(const ARow: TAtlasLeakRow); static;
    class procedure ToggleKnown(const AName: string); static;
  public
    /// <summary>Zuhörer anmelden; Antworten des Servers über AScope, Meldungen über AMessage.</summary>
    class procedure Start(const AScope: IAtlasModuleScope; const AMessage: TProc<string>); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>Befehl Atlas.DebugLeaks: Fenster mit dem letzten Bericht zeigen.</summary>
    class procedure ShowWindow; static;
    class procedure ThemeChanged; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  System.IOUtils,
  ToolsAPI,
  Atlas.Text.LeakReport,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.LeaksWindow,
  Atlas.UI.Debug.LeaksFrame,
  Atlas.UI.Debug.Leaks,
  Atlas.UI.Debug.Strings;

const
  cDialogClass = '#32770';
  cMaxText = 8192;

function QueryFullProcessImageNameW(AProcess: THandle; AFlags: DWORD; AExeName: PWideChar;
  var ASize: DWORD): BOOL; stdcall; external kernel32 name 'QueryFullProcessImageNameW';

type
  /// <summary>Sammelt die Texte der Dialogfenster eines Prozesses.</summary>
  TWindowTexts = record
    ProcessId: Cardinal;
    Texts: TArray<string>;
  end;
  PWindowTexts = ^TWindowTexts;

function WindowText(AWindow: HWND): string;
var
  mLength: Integer;
begin
  mLength := GetWindowTextLength(AWindow);
  if mLength <= 0 then
  begin
    Exit('');
  end;
  SetLength(Result, Min(mLength, cMaxText) + 1);
  SetLength(Result, GetWindowText(AWindow, PChar(Result), Length(Result)));
end;

function CollectChild(AWindow: HWND; AData: LPARAM): BOOL; stdcall;
var
  mText: string;
begin
  mText := WindowText(AWindow);
  if mText <> '' then
  begin
    PWindowTexts(AData).Texts := PWindowTexts(AData).Texts + [mText];
  end;
  Result := True;
end;

function CollectWindow(AWindow: HWND; AData: LPARAM): BOOL; stdcall;
var
  mProcessId: DWORD;
  mClass: array[0..255] of Char;
begin
  Result := True;
  mProcessId := 0;
  GetWindowThreadProcessId(AWindow, @mProcessId);
  if (mProcessId <> PWindowTexts(AData).ProcessId) or not IsWindowVisible(AWindow) then
  begin
    Exit;
  end;
  GetClassName(AWindow, mClass, Length(mClass));
  if string(mClass) = cDialogClass then
  begin
    EnumChildWindows(AWindow, @CollectChild, AData);
  end;
end;

function ExeOfProcess(AProcessId: Cardinal): string;
var
  mProcess: THandle;
  mSize: DWORD;
begin
  Result := '';
  mProcess := OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, AProcessId);
  if mProcess = 0 then
  begin
    Exit;
  end;
  try
    mSize := MAX_PATH;
    SetLength(Result, mSize);
    if QueryFullProcessImageNameW(mProcess, 0, PWideChar(Result), mSize) then
    begin
      SetLength(Result, mSize);
    end
    else
    begin
      Result := '';
    end;
  finally
    CloseHandle(mProcess);
  end;
end;

/// <summary>Datei mit dem Namen AFileName (ohne Pfad) im Projekt AProject; '' ohne.</summary>
function ProjectFileNamed(const AProject, AFileName: string): string;
var
  mModule: IOTAModule;
  mProject: IOTAProject;
  mIndex: Integer;
begin
  Result := '';
  mModule := (BorlandIDEServices as IOTAModuleServices).FindModule(AProject);
  if not Supports(mModule, IOTAProject, mProject) then
  begin
    Exit;
  end;
  for mIndex := 0 to mProject.GetModuleCount - 1 do
  begin
    if SameText(ExtractFileName(mProject.GetModule(mIndex).FileName), ExtractFileName(AFileName)) then
    begin
      Exit(mProject.GetModule(mIndex).FileName);
    end;
  end;
end;

{ TAtlasIdeDebugLeaks.TListener }

procedure TAtlasIdeDebugLeaks.TListener.DebugStarted;
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugLeaks.Began);
end;

procedure TAtlasIdeDebugLeaks.TListener.DebugEnded;
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugLeaks.Ended);
end;

{ TAtlasIdeDebugLeaks.TTicker }

procedure TAtlasIdeDebugLeaks.TTicker.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, TAtlasIdeDebugLeaks.ScanWindows);
end;

{ TAtlasIdeDebugLeaks }

class procedure TAtlasIdeDebugLeaks.Start(const AScope: IAtlasModuleScope; const AMessage: TProc<string>);
begin
  FScope := AScope;
  FMessage := AMessage;
  if FTicker = nil then
  begin
    FTicker := TTicker.Create;
  end;
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(nil);
    FTimer.Enabled := False;
    FTimer.Interval := cIntervalMs;
    FTimer.OnTimer := FTicker.Tick;
  end;
  TAtlasIdeDebugLeaksWindow.Prepare;
  TAtlasIdeDebugLeaksWindow.OnFrame :=
    procedure(AFrame: TAtlasDebugLeaksFrame)
    begin
      AFrame.OnOpen :=
        procedure(ARow: TAtlasLeakRow)
        begin
          Open(ARow);
        end;
      AFrame.OnMarkKnown :=
        procedure(AName: string)
        begin
          ToggleKnown(AName);
        end;
      AFrame.OnFilter :=
        procedure
        begin
          Refresh;
        end;
      Refresh;
    end;
  if FListener = nil then
  begin
    FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FListener);
  end;
  TAtlasIdeDebugSession.Start;
end;

class procedure TAtlasIdeDebugLeaks.Release;
begin
  if FListener <> nil then
  begin
    TAtlasIdeDebugSession.RemoveListener(FListener);
    FListener := nil;
  end;
  FreeAndNil(FTimer);
  FreeAndNil(FTicker);
  TAtlasIdeDebugLeaksWindow.Release;
  FScope := nil;
  FMessage := nil;
  FBox := Default(TAtlasLeakCapture);
  FCapture := Default(TAtlasLeakCapture);
  FEntries := nil;
  FPlaces := nil;
  FHistory := Default(TAtlasLeakHistory);
end;

class function TAtlasIdeDebugLeaks.Started: Boolean;
begin
  Result := FListener <> nil;
end;

class procedure TAtlasIdeDebugLeaks.Began;
var
  mProcess: IOTAProcess;
begin
  FStarted := Now;
  FBox := Default(TAtlasLeakCapture);
  FProcessId := 0;
  FExeFile := '';
  mProcess := TAtlasIdeDebugSession.Process;
  if mProcess <> nil then
  begin
    FProcessId := mProcess.ProcessId;
    FExeFile := ExeOfProcess(FProcessId);
  end;
  FProject := TAtlasIdeDebugSession.LaunchProject;
  FConfiguration := TAtlasIdeDebugSession.LaunchConfiguration;
  FPlatform := TAtlasIdeDebugSession.LaunchPlatform;
  FTimer.Enabled := FProcessId <> 0;
end;

class procedure TAtlasIdeDebugLeaks.ScanWindows;
var
  mTexts: TWindowTexts;
  mCapture: TAtlasLeakCapture;
begin
  if FProcessId = 0 then
  begin
    Exit;
  end;
  mTexts := Default(TWindowTexts);
  mTexts.ProcessId := FProcessId;
  EnumWindows(@CollectWindow, LPARAM(@mTexts));
  if TAtlasLeakCaptures.FromWindowTexts(mTexts.Texts, mCapture) then
  begin
    FBox := mCapture;
  end;
end;

class function TAtlasIdeDebugLeaks.ReadLogFile: TAtlasLeakCapture;
var
  mFile: string;
  mWritten: TDateTime;
begin
  Result := Default(TAtlasLeakCapture);
  if FExeFile = '' then
  begin
    Exit;
  end;
  mFile := TAtlasLeakCaptures.LogFileOf(FExeFile);
  if not FileAge(mFile, mWritten) then
  begin
    Exit;
  end;
  try
    TAtlasLeakCaptures.FromLogFile(mFile, TFile.ReadAllText(mFile), mWritten, FStarted, Result);
  except
    on EInOutError do
    begin
      Result := Default(TAtlasLeakCapture);
    end;
    on EFileStreamError do
    begin
      Result := Default(TAtlasLeakCapture);
    end;
  end;
end;

class procedure TAtlasIdeDebugLeaks.Ended;
var
  mCapture: TAtlasLeakCapture;
begin
  FTimer.Enabled := False;
  // Letzter Blick: Das Meldungsfenster steht bis zum Klick, das Ende kommt danach.
  mCapture := TAtlasLeakCaptures.Choose(FBox, ReadLogFile);
  FBox := Default(TAtlasLeakCapture);
  if mCapture.IsEmpty then
  begin
    Exit;
  end;
  FCapture := mCapture;
  Present;
end;

class function TAtlasIdeDebugLeaks.HistoryFile: string;
begin
  Result := '';
  if FProject <> '' then
  begin
    Result := TPath.Combine(TPath.Combine(ExtractFileDir(FProject), cLocalFolder),
      TAtlasLeakCaptures.HistoryFileName(FConfiguration, FPlatform));
  end;
end;

function ReadHistory(const AFileName: string): TAtlasLeakHistory;
begin
  Result := Default(TAtlasLeakHistory);
  if (AFileName <> '') and FileExists(AFileName) then
  begin
    try
      Result := TAtlasLeakCaptures.HistoryFromText(TFile.ReadAllText(AFileName));
    except
      on EInOutError do
      begin
        Result := Default(TAtlasLeakHistory);
      end;
      on EFileStreamError do
      begin
        Result := Default(TAtlasLeakHistory);
      end;
    end;
  end;
end;

procedure WriteHistory(const AFileName: string; const AHistory: TAtlasLeakHistory);
begin
  if AFileName = '' then
  begin
    Exit;
  end;
  try
    ForceDirectories(ExtractFileDir(AFileName));
    TFile.WriteAllText(AFileName, TAtlasLeakCaptures.HistoryToText(AHistory));
  except
    // Ohne schreibbaren Ordner gibt es keinen Vergleich; der Bericht bleibt sichtbar.
    on EInOutError do
    begin
      Exit;
    end;
    on EFileStreamError do
    begin
      Exit;
    end;
  end;
end;

class procedure TAtlasIdeDebugLeaks.Present;
var
  mPrevious: TAtlasLeakHistory;
begin
  mPrevious := ReadHistory(HistoryFile);
  FHistory := mPrevious;
  if not TAtlasIdeSettings.Current.DebugLeakReportCompare then
  begin
    // Ohne Vergleich gilt jeder Name als bisher unbekannt; „bekannt“ bleibt.
    FHistory.Names := nil;
    FHistory.Counts := nil;
  end;
  FEntries := TAtlasLeakCaptures.Compare(FCapture.Report, FHistory);
  FHistory := TAtlasLeakCaptures.NextHistory(FCapture.Report, mPrevious);
  WriteHistory(HistoryFile, FHistory);
  FPlaces := nil;
  FStatus := TAtlasLeakTexts.Summary(FCapture);
  if Assigned(FMessage) then
  begin
    FMessage(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.LeaksFound, [TAtlasLeakTexts.LeakCount(FCapture)]));
  end;
  if TAtlasIdeSettings.Current.DebugLeakReportWindow then
  begin
    TAtlasIdeDebugLeaksWindow.Show;
  end;
  Refresh;
  if not FCapture.Report.HasStacks then
  begin
    RequestCandidates;
  end;
end;

class procedure TAtlasIdeDebugLeaks.RequestCandidates;
var
  mDone: TProc<string>;
begin
  if FProject = '' then
  begin
    Exit;
  end;
  mDone :=
    procedure(AAnswer: string)
    begin
      FPlaces := TAtlasLeakViews.PlacesFromJson(AAnswer);
      FStatus := TAtlasLeakTexts.Summary(FCapture);
      Refresh;
    end;
  FStatus := TAtlasLeakTexts.Summary(FCapture) + '  ·  ' + TAtlasDebugStrings.Text(TAtlasDebugTextId.LeaksSearching);
  if (TAtlasIdeHost.ActiveSession = nil) or not TAtlasIdeHost.RunServerCommandAsync(FScope, TAtlasFeature.Debugger,
    TAtlasLeakViews.cCandidatesCommand, TAtlasLeakViews.CandidateArgumentsJson(FProject, FCapture.Text), cTimeoutMs,
    mDone) then
  begin
    FStatus := TAtlasLeakTexts.Summary(FCapture) + '  ·  ' + TAtlasDebugStrings.Text(TAtlasDebugTextId.LeaksNoServer);
  end;
  Refresh;
end;

class procedure TAtlasIdeDebugLeaks.Refresh;
var
  mFrame: TAtlasDebugLeaksFrame;
begin
  mFrame := TAtlasIdeDebugLeaksWindow.ExistingFrame;
  if mFrame = nil then
  begin
    Exit;
  end;
  if FStatus = '' then
  begin
    FStatus := TAtlasLeakTexts.Summary(FCapture);
  end;
  mFrame.SetRows(TAtlasLeakViews.Rows(FEntries, FPlaces, FCapture.Report.Groups, mFrame.HideKnown), FStatus);
end;

class procedure TAtlasIdeDebugLeaks.Open(const ARow: TAtlasLeakRow);
var
  mFrame: TLeakFrame;
  mFile: string;
begin
  if ARow.Kind = TAtlasLeakRowKind.Place then
  begin
    TAtlasIdeNavigation.GoToLocation(ARow.Place.FileName, ARow.Place.Line, ARow.Place.Character);
    Exit;
  end;
  if (ARow.Kind <> TAtlasLeakRowKind.Group) or (ARow.Group.Site < 0) then
  begin
    Exit;
  end;
  mFrame := ARow.Group.Frames[ARow.Group.Site];
  mFile := mFrame.FileName;
  if not FileExists(mFile) then
  begin
    mFile := ProjectFileNamed(FProject, mFrame.FileName);
  end;
  if mFile <> '' then
  begin
    TAtlasIdeNavigation.GoToLocation(mFile, mFrame.Line - 1, 0);
  end;
end;

class procedure TAtlasIdeDebugLeaks.ToggleKnown(const AName: string);
var
  mIndex: Integer;
begin
  FHistory := TAtlasLeakCaptures.MarkKnown(FHistory, AName, not FHistory.IsKnown(AName));
  WriteHistory(HistoryFile, FHistory);
  for mIndex := 0 to High(FEntries) do
  begin
    FEntries[mIndex].Known := FHistory.IsKnown(FEntries[mIndex].Name);
  end;
  Refresh;
end;

class procedure TAtlasIdeDebugLeaks.ShowWindow;
begin
  TAtlasIdeDebugLeaksWindow.Show;
  Refresh;
end;

class procedure TAtlasIdeDebugLeaks.ThemeChanged;
begin
  TAtlasIdeDebugLeaksWindow.ApplyTheme;
end;

end.
