unit Atlas.IDE.Updates.Install;

// Update installieren in der IDE (#1519), gesteuert von TAtlasIdeUpdates:
// - Prepare startet „AtlasUpdate.exe prepare“ unsichtbar (ohne Konsole);
//   ein Takt liest state.json, bis das Update bereit oder gescheitert ist,
//   und meldet den Stand für die Zeile „Version“. Danach eine Zeile in der
//   Meldungsansicht.
// - ApplyOnExit startet beim Schließen der IDE „apply“ aus dem
//   vorbereiteten Ordner (die neue AtlasUpdate.exe) in einer sichtbaren
//   Konsole; sie wartet, bis die IDE beendet ist.
// - ReportOutcome meldet beim nächsten Start result.json und räumt die
//   Ordner alter Updates weg.
// - Discard löscht ein vorbereitetes Update, Choose speichert die Auswahl
//   der Module in state.json.
// Läuft beim Entladen noch eine Vorbereitung, läuft sie zu Ende; das Ergebnis
// liest der nächste Start.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  Atlas.Text.UpdateRun,
  Atlas.Core.Updates.Install;

type
  TAtlasIdeUpdateInstaller = class(TComponent)
  public const
    cPollMs = 1000;
  private
    FEnvironment: TAtlasUpdateEnvironment;
    FRoot: string;
    FProcess: THandle;
    FPreparing: string;
    FTimer: TTimer;
    FOnChange: TProc;
    FOnMessage: TProc<string>;
    FOnLog: TProc<string>;
    procedure Poll(Sender: TObject);
    procedure Prepared(const AStage: TUpdateStage);
    procedure ClosePreparation;
    function Launch(const AExe: string; const AArgs: TUpdateArguments; AVisible: Boolean): THandle;
    procedure Say(const AText: string);
    procedure DeleteFolder(const ADir: string);
    procedure Log(const AText: string);
    function StateFile(const AVersion: string): string;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>AMessage: Meldungsansicht; ALog: Plugin-Protokoll; AChange: Stand geändert (Zeile „Version“).
    /// </summary>
    procedure Start(const AEnvironment: TAtlasUpdateEnvironment; const ARoot: string; const AMessage,
      ALog: TProc<string>; const AChange: TProc);
    function Blocked: TAtlasUpdateBlock;
    /// <summary>Stand der Vorbereitung von AVersion; False ohne.</summary>
    function TryStage(const AVersion: string; out AStage: TUpdateStage): Boolean;
    function Preparing: Boolean;
    procedure Prepare(const AVersion, AManifestUrl, ANewModules: string);
    procedure Choose(const AVersion: string; const AChosen: TArray<string>);
    procedure Discard(const AVersion: string);
    /// <summary>Beim Schließen der IDE: „apply“ starten, wenn AVersion bereit ist.</summary>
    procedure ApplyOnExit(const AVersion: string);
    /// <summary>Ergebnis des letzten „apply“ melden; danach result.json und Ordner alter Updates weg.</summary>
    procedure ReportOutcome;
    procedure Stop;
    property Environment: TAtlasUpdateEnvironment read FEnvironment;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  Atlas.Text.Updates,
  Atlas.Core.Files.DataFile,
  Atlas.UI.Updates.Strings,
  Atlas.UI.Updates.Texts;

{ TAtlasIdeUpdateInstaller }

constructor TAtlasIdeUpdateInstaller.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := cPollMs;
  FTimer.OnTimer := Poll;
end;

destructor TAtlasIdeUpdateInstaller.Destroy;
begin
  Stop;
  inherited;
end;

procedure TAtlasIdeUpdateInstaller.Say(const AText: string);
begin
  if Assigned(FOnMessage) then
  begin
    FOnMessage(AText);
  end;
end;

procedure TAtlasIdeUpdateInstaller.Log(const AText: string);
begin
  if Assigned(FOnLog) then
  begin
    FOnLog(AText);
  end;
end;

procedure TAtlasIdeUpdateInstaller.Start(const AEnvironment: TAtlasUpdateEnvironment; const ARoot: string;
  const AMessage, ALog: TProc<string>; const AChange: TProc);
begin
  FEnvironment := AEnvironment;
  FRoot := ARoot;
  FOnMessage := AMessage;
  FOnLog := ALog;
  FOnChange := AChange;
end;

procedure TAtlasIdeUpdateInstaller.DeleteFolder(const ADir: string);
begin
  // Gesperrte Dateien (Virenscanner, offenes Protokoll): beim nächsten Start wieder versuchen.
  try
    if TDirectory.Exists(ADir) then
    begin
      TDirectory.Delete(ADir, True);
    end;
  except
    on E: Exception do
    begin
      Log('Update folder not deleted: ' + E.ClassName);
    end;
  end;
end;

function TAtlasIdeUpdateInstaller.Blocked: TAtlasUpdateBlock;
begin
  Result := TAtlasUpdateInstall.Blocked(FEnvironment);
end;

function TAtlasIdeUpdateInstaller.StateFile(const AVersion: string): string;
begin
  Result := TUpdateLayout.Join(TAtlasUpdateInstall.StagingDir(FRoot, AVersion), TUpdateLayout.cStateFile);
end;

function TAtlasIdeUpdateInstaller.TryStage(const AVersion: string; out AStage: TUpdateStage): Boolean;
var
  mText: string;
begin
  AStage := Default(TUpdateStage);
  Result := (AVersion <> '') and TAtlasDataFile.TryRead(StateFile(AVersion), mText);
  if Result then
  begin
    AStage := TUpdateStage.FromJson(mText);
    // Ein anderer Stand im Ordner (von Hand kopiert, halb geschrieben) gilt nicht.
    Result := AStage.Version = AVersion;
  end;
end;

function TAtlasIdeUpdateInstaller.Preparing: Boolean;
begin
  Result := FProcess <> 0;
end;

function TAtlasIdeUpdateInstaller.Launch(const AExe: string; const AArgs: TUpdateArguments;
  AVisible: Boolean): THandle;
var
  mStartup: TStartupInfo;
  mProcess: TProcessInformation;
  mCommand: string;
  mFlags: DWORD;
begin
  Result := 0;
  mStartup := Default(TStartupInfo);
  mStartup.cb := SizeOf(mStartup);
  mCommand := TUpdateNames.QuoteArgument(AExe) + ' ' + AArgs.CommandLine;
  UniqueString(mCommand);
  mFlags := CREATE_NO_WINDOW;
  if AVisible then
  begin
    mFlags := CREATE_NEW_CONSOLE;
  end;
  if not CreateProcess(PChar(AExe), PChar(mCommand), nil, nil, False, mFlags, nil, PChar(ExtractFileDir(AExe)),
    mStartup, mProcess) then
  begin
    Log('AtlasUpdate not started: ' + SysErrorMessage(GetLastError));
    Exit;
  end;
  CloseHandle(mProcess.hThread);
  Result := mProcess.hProcess;
end;

procedure TAtlasIdeUpdateInstaller.Prepare(const AVersion, AManifestUrl, ANewModules: string);
var
  mArgs: TUpdateArguments;
begin
  if Preparing or (Blocked <> TAtlasUpdateBlock.None) then
  begin
    Exit;
  end;
  mArgs := TAtlasUpdateInstall.PrepareArgs(FEnvironment, FRoot, AVersion, AManifestUrl, ANewModules);
  FProcess := Launch(TAtlasUpdateInstall.UpdaterOf(FEnvironment.PluginDir), mArgs, False);
  if FProcess = 0 then
  begin
    Say(TAtlasUpdatesStrings.Fmt(TAtlasUpdatesTextId.UpdatesPrepareFailedMessage, [AVersion,
      TAtlasUpdateTexts.ErrorText(TAtlasUpdateInstall.cStartFailed, ''), TUpdateChannels.cReleasesUrl]));
    Exit;
  end;
  FPreparing := AVersion;
  Log('Update ' + AVersion + ': prepare started');
  FTimer.Enabled := True;
end;

procedure TAtlasIdeUpdateInstaller.ClosePreparation;
begin
  FTimer.Enabled := False;
  if FProcess <> 0 then
  begin
    CloseHandle(FProcess);
  end;
  FProcess := 0;
  FPreparing := '';
end;

procedure TAtlasIdeUpdateInstaller.Poll(Sender: TObject);
var
  mStage: TUpdateStage;
  mExited, mFound: Boolean;
begin
  mExited := WaitForSingleObject(FProcess, 0) = WAIT_OBJECT_0;
  mFound := TryStage(FPreparing, mStage);
  if mExited and not (mFound and TAtlasUpdateInstall.IsFinished(mStage)) then
  begin
    // Beendet ohne fertigen Stand (abgestürzt, beendet): als Fehler melden.
    mStage.Version := FPreparing;
    mStage.Phase := TUpdatePhase.Failed;
    mStage.Error := TUpdateErrors.cUnexpected;
  end;
  if mExited or TAtlasUpdateInstall.IsFinished(mStage) then
  begin
    ClosePreparation;
    Prepared(mStage);
  end;
  if Assigned(FOnChange) then
  begin
    FOnChange();
  end;
end;

procedure TAtlasIdeUpdateInstaller.Prepared(const AStage: TUpdateStage);
begin
  if AStage.Phase = TUpdatePhase.Failed then
  begin
    Log('Update ' + AStage.Version + ' not prepared: ' + AStage.Error);
    Say(TAtlasUpdatesStrings.Fmt(TAtlasUpdatesTextId.UpdatesPrepareFailedMessage, [AStage.Version,
      TAtlasUpdateTexts.ErrorText(AStage.Error, AStage.Detail), TUpdateChannels.cReleasesUrl]));
  end
  else if AStage.AskSelection then
  begin
    Log('Update ' + AStage.Version + ' ready, new modules to choose');
    Say(TAtlasUpdatesStrings.Fmt(TAtlasUpdatesTextId.UpdatesChooseMessage, [AStage.Version]));
  end
  else
  begin
    Log('Update ' + AStage.Version + ' ready');
    Say(TAtlasUpdatesStrings.Fmt(TAtlasUpdatesTextId.UpdatesPreparedMessage, [AStage.Version]));
  end;
end;

procedure TAtlasIdeUpdateInstaller.Choose(const AVersion: string; const AChosen: TArray<string>);
var
  mStage: TUpdateStage;
begin
  if not TryStage(AVersion, mStage) or (mStage.Phase <> TUpdatePhase.Ready) then
  begin
    Exit;
  end;
  TAtlasDataFile.Write(StateFile(AVersion), TAtlasUpdateInstall.Choose(mStage, AChosen).ToJson);
  Log('Update ' + AVersion + ': modules chosen: ' + string.Join(', ', AChosen));
end;

procedure TAtlasIdeUpdateInstaller.Discard(const AVersion: string);
begin
  if (AVersion = '') or (AVersion = FPreparing) then
  begin
    Exit;
  end;
  DeleteFolder(TAtlasUpdateInstall.StagingDir(FRoot, AVersion));
  Log('Update ' + AVersion + ': discarded');
end;

procedure TAtlasIdeUpdateInstaller.ApplyOnExit(const AVersion: string);
var
  mStage: TUpdateStage;
  mExe: string;
  mProcess: THandle;
begin
  if (Blocked <> TAtlasUpdateBlock.None) or not TryStage(AVersion, mStage) or
    (mStage.Phase <> TUpdatePhase.Ready) or (TUpdateVersions.Compare(AVersion, FEnvironment.Installed) <= 0) then
  begin
    Exit;
  end;
  // Die neue AtlasUpdate.exe aus dem vorbereiteten Ordner: Die alte im Atlas-Ordner wird dabei ersetzt.
  mExe := mStage.Updater;
  if (mExe = '') or not FileExists(mExe) then
  begin
    mExe := TAtlasUpdateInstall.UpdaterOf(FEnvironment.PluginDir);
  end;
  mProcess := Launch(mExe, TAtlasUpdateInstall.ApplyArgs(FEnvironment, FRoot, mStage, GetCurrentProcessId), True);
  if mProcess <> 0 then
  begin
    CloseHandle(mProcess);
    Log('Update ' + AVersion + ': apply started for after exit');
  end;
end;

procedure TAtlasIdeUpdateInstaller.ReportOutcome;
var
  mFile, mText, mDir, mName: string;
  mOutcome: TUpdateOutcome;
begin
  mFile := TUpdateLayout.Join(FRoot, TUpdateLayout.cResultFile);
  if TAtlasDataFile.TryRead(mFile, mText) then
  begin
    mOutcome := TUpdateOutcome.FromJson(mText);
    Log('Update ' + mOutcome.Version + ': ' + TUpdateNames.OutcomeName(mOutcome.Kind) + ' ' + mOutcome.Reason);
    Say(TAtlasUpdateTexts.OutcomeText(mOutcome));
    System.SysUtils.DeleteFile(mFile);
  end;
  if not TDirectory.Exists(FRoot) then
  begin
    Exit;
  end;
  // Ordner eingespielter und älterer Updates; ein neueres bleibt für das nächste Schließen.
  for mDir in TDirectory.GetDirectories(FRoot) do
  begin
    mName := ExtractFileName(mDir);
    if TUpdateVersions.IsValidVersion(mName) and (TUpdateVersions.Compare(mName, FEnvironment.Installed) <= 0) then
    begin
      DeleteFolder(mDir);
    end;
  end;
end;

procedure TAtlasIdeUpdateInstaller.Stop;
begin
  // Die Vorbereitung läuft weiter; nur das Handle und der Takt gehören dem Plugin.
  ClosePreparation;
  FOnChange := nil;
  FOnMessage := nil;
  FOnLog := nil;
end;

end.
