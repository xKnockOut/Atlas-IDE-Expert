unit Atlas.Windows.Monitor.Adapters.Process;

// Platform-Feature "Monitor" (#1900), Adapter: Kindprozess von AtlasMonitor für einen Lauf von AtlasServer.
// Startet unsichtbar (ohne Konsolenfenster), stdin aus NUL, stdout und stderr in eine Datei, damit keine Pipe
// volllaufen kann; das Ergebnis schreibt der Server selbst in seine Ausgabedatei. Jeder Kindprozess gehört zu einem
// Job mit „beim Schließen beenden“: Endet AtlasMonitor, auch unerwartet, schließt Windows den Job und beendet alle
// seine Läufe. Die Oberfläche fragt mit Poll nach dem Ende (Timer), Terminate bricht ab.

interface

uses
  System.SysUtils;

type
  TMonitorChildProcess = class
  private
    FProcess: THandle;
    FPid: Cardinal;
    FExitCode: Integer;
    FFinished: Boolean;
    procedure CloseProcess;
  public
    destructor Destroy; override;
    /// <summary>Startet AProgram mit AArguments im Ordner AFolder ('' = aktueller); stdout und stderr nach ALogFile.
    /// False mit AError, wenn der Start scheitert.</summary>
    function Start(const AProgram: string; const AArguments: TArray<string>; const AFolder, ALogFile: string;
      out AError: string): Boolean;
    /// <summary>True, wenn der Prozess beendet ist; ExitCode gilt dann.</summary>
    function Poll: Boolean;
    /// <summary>Beendet den Prozess hart (Abbrechen).</summary>
    procedure Terminate;
    property Pid: Cardinal read FPid;
    property ExitCode: Integer read FExitCode;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.Text.UpdateRun,
  Atlas.WinBase.Process;

type
  TJobBasicLimits = record
    PerProcessUserTimeLimit: Int64;
    PerJobUserTimeLimit: Int64;
    LimitFlags: DWORD;
    MinimumWorkingSetSize: NativeUInt;
    MaximumWorkingSetSize: NativeUInt;
    ActiveProcessLimit: DWORD;
    Affinity: NativeUInt;
    PriorityClass: DWORD;
    SchedulingClass: DWORD;
  end;

  TJobIoCounters = record
    ReadOperationCount: UInt64;
    WriteOperationCount: UInt64;
    OtherOperationCount: UInt64;
    ReadTransferCount: UInt64;
    WriteTransferCount: UInt64;
    OtherTransferCount: UInt64;
  end;

  TJobExtendedLimits = record
    Basic: TJobBasicLimits;
    IoInfo: TJobIoCounters;
    ProcessMemoryLimit: NativeUInt;
    JobMemoryLimit: NativeUInt;
    PeakProcessMemoryUsed: NativeUInt;
    PeakJobMemoryUsed: NativeUInt;
  end;

const
  /// <summary>JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE und JobObjectExtendedLimitInformation (selbst deklariert, nicht in
  /// jeder Fassung von Winapi.Windows gleich typisiert).</summary>
  cJobKillOnClose = $00002000;
  cJobExtendedLimitClass = 9;
  cCreateNoWindow = $08000000;
  /// <summary>Exit-Code eines abgebrochenen Laufs.</summary>
  cTerminatedExitCode = 1;
  /// <summary>So lange wartet Terminate, bis Windows den Prozess beendet hat.</summary>
  cTerminateWaitMs = 5000;

function CreateJob(AAttributes: Pointer; AName: PWideChar): THandle; stdcall;
  external kernel32 name 'CreateJobObjectW';
function SetJobInformation(AJob: THandle; AClass: Integer; AInfo: Pointer; ALength: DWORD): BOOL; stdcall;
  external kernel32 name 'SetInformationJobObject';
function AssignToJob(AJob, AProcess: THandle): BOOL; stdcall;
  external kernel32 name 'AssignProcessToJobObject';

var
  /// <summary>Job aller Kindprozesse des Monitors; bleibt bis zum Ende des Prozesses offen, Windows schließt ihn
  /// dann und beendet die Läufe.</summary>
  GJob: THandle;

/// <summary>Job mit „beim Schließen beenden“; 0, wenn Windows keinen anlegt (dann laufen Kinder ohne Job).</summary>
function Job: THandle;
var
  mLimits: TJobExtendedLimits;
begin
  if GJob = 0 then
  begin
    GJob := CreateJob(nil, nil);
    if GJob <> 0 then
    begin
      FillChar(mLimits, SizeOf(mLimits), 0);
      mLimits.Basic.LimitFlags := cJobKillOnClose;
      SetJobInformation(GJob, cJobExtendedLimitClass, @mLimits, SizeOf(mLimits));
    end;
  end;
  Result := GJob;
end;

/// <summary>Vererbbares Handle für AFileName (anlegen bzw. lesen); INVALID_HANDLE_VALUE bei einem Fehler.</summary>
function InheritableFile(const AFileName: string; AWrite: Boolean): THandle;
var
  mSecurity: TSecurityAttributes;
begin
  mSecurity.nLength := SizeOf(mSecurity);
  mSecurity.lpSecurityDescriptor := nil;
  // Nicht vererbbar: Vererbbar macht sie erst TAtlasProcessLauncher, nur für diesen Start.
  mSecurity.bInheritHandle := False;
  if AWrite then
  begin
    Result := CreateFile(PChar(AFileName), GENERIC_WRITE, FILE_SHARE_READ or FILE_SHARE_DELETE, @mSecurity,
      CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
  end
  else
  begin
    Result := CreateFile(PChar(AFileName), GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE, @mSecurity,
      OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  end;
end;

function CommandLineOf(const AProgram: string; const AArguments: TArray<string>): string;
var
  mArgument: string;
begin
  Result := TUpdateNames.QuoteArgument(AProgram);
  for mArgument in AArguments do
  begin
    Result := Result + ' ' + TUpdateNames.QuoteArgument(mArgument);
  end;
  UniqueString(Result);
end;

{ TMonitorChildProcess }

destructor TMonitorChildProcess.Destroy;
begin
  // Ein Lauf überlebt sein Objekt nicht.
  Terminate;
  CloseProcess;
  inherited;
end;

procedure TMonitorChildProcess.CloseProcess;
begin
  if FProcess <> 0 then
  begin
    CloseHandle(FProcess);
    FProcess := 0;
  end;
end;

/// <summary>Startet den Prozess mit AOutput als stdout/stderr und NUL als stdin.</summary>
function Launch(const ACommandLine, AFolder: string; AOutput, AInput: THandle; out AInfo: TProcessInformation;
  out AError: string): Boolean;
var
  mLaunch: TAtlasProcessLaunch;
begin
  mLaunch := TAtlasProcessLaunch.Create('', ACommandLine, AFolder, AInput, AOutput, AOutput);
  mLaunch.Flags := cCreateNoWindow or CREATE_SUSPENDED;
  mLaunch.Hidden := True;
  Result := TAtlasProcessLauncher.Launch(mLaunch, AInfo);
  if not Result then
  begin
    AError := SysErrorMessage(GetLastError);
  end;
end;

function TMonitorChildProcess.Start(const AProgram: string; const AArguments: TArray<string>; const AFolder,
  ALogFile: string; out AError: string): Boolean;
var
  mOutput, mInput: THandle;
  mInfo: TProcessInformation;
begin
  Result := False;
  AError := '';
  CloseProcess;
  FFinished := False;
  FExitCode := 0;
  mOutput := InheritableFile(ALogFile, True);
  if mOutput = INVALID_HANDLE_VALUE then
  begin
    AError := SysErrorMessage(GetLastError);
    Exit;
  end;
  mInput := InheritableFile('NUL', False);
  try
    Result := Launch(CommandLineOf(AProgram, AArguments), AFolder, mOutput, mInput, mInfo, AError);
  finally
    CloseHandle(mOutput);
    if mInput <> INVALID_HANDLE_VALUE then
    begin
      CloseHandle(mInput);
    end;
  end;
  if not Result then
  begin
    Exit;
  end;
  // Erst im Job, dann laufen lassen: So entkommt auch ein sofort startender Enkelprozess nicht.
  if Job <> 0 then
  begin
    AssignToJob(Job, mInfo.hProcess);
  end;
  ResumeThread(mInfo.hThread);
  CloseHandle(mInfo.hThread);
  FProcess := mInfo.hProcess;
  FPid := mInfo.dwProcessId;
end;

function TMonitorChildProcess.Poll: Boolean;
var
  mCode: DWORD;
begin
  if FFinished or (FProcess = 0) then
  begin
    Exit(True);
  end;
  Result := WaitForSingleObject(FProcess, 0) = WAIT_OBJECT_0;
  if Result then
  begin
    mCode := 0;
    GetExitCodeProcess(FProcess, mCode);
    FExitCode := Integer(mCode);
    FFinished := True;
    CloseProcess;
  end;
end;

procedure TMonitorChildProcess.Terminate;
begin
  if (FProcess <> 0) and not FFinished then
  begin
    TerminateProcess(FProcess, cTerminatedExitCode);
    WaitForSingleObject(FProcess, cTerminateWaitMs);
    FExitCode := cTerminatedExitCode;
    FFinished := True;
    CloseProcess;
  end;
end;

end.
