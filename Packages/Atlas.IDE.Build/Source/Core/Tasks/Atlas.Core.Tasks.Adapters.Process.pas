unit Atlas.Core.Tasks.Adapters.Process;

// Prozess einer Projektaufgabe (#900), ohne VCL und Open Tools API:
// - Programm über TAtlasTaskCommands.FindProgram; ohne Treffer endet der Lauf
//   mit ProgramMissing (Error = Befehl).
// - Run startet unsichtbar (CREATE_NO_WINDOW), stdin ist NUL, stdout und
//   stderr gehen in eine gemeinsame Pipe (Reihenfolge wie in der Konsole).
//   Gelesen wird im Takt von 10 ms; jede fertige Zeile geht sofort an
//   AOnLine (TAtlasTaskLines: UTF-8, sonst OEM-Codepage).
// - Der Prozess läuft in einem Job-Objekt mit „beim Schließen beenden“:
//   Zeitlimit, Abbruch (ACancelled, Ende des Threads) und Entladen beenden
//   so auch Kindprozesse (pwsh startet dcc, msbuild startet Knoten).
// - Im Hauptthread abgelehnt (StartFailed): Die IDE bleibt bedienbar.

interface

uses
  System.SysUtils,
  Atlas.Core.Tasks.Definitions,
  Atlas.Core.Tasks.Runs;

type
  /// <summary>Umsetzung von TAtlasTaskProcessRun (Atlas.IDE.Tasks.Runner); die Kompositionswurzel reicht Run
  /// hinein.</summary>
  TAtlasTaskProcess = class
  public const
    cSliceMs = 10;
  public
    /// <summary>Führt die (mit Variablen eingesetzte) Aufgabe aus, nicht im Hauptthread. ACancelled wird im Takt
    /// gefragt; ACodePage für Ausgaben, die kein UTF-8 sind (0 = GetOEMCP).</summary>
    class function Run(const ATask: TAtlasTaskDefinition; ACodePage: Integer; const ACancelled: TFunc<Boolean>;
      const AOnLine: TAtlasTaskLineProc): TAtlasTaskProcessResult; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Classes,
  Atlas.WinBase.Process,
  Atlas.Core.Tasks.Matchers,
  Atlas.Core.Tasks.Commands;

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

function CreateJob(AAttributes: Pointer; AName: PWideChar): THandle; stdcall;
  external kernel32 name 'CreateJobObjectW';
function SetJobInformation(AJob: THandle; AClass: Integer; AInfo: Pointer; ALength: DWORD): BOOL; stdcall;
  external kernel32 name 'SetInformationJobObject';
function AssignToJob(AJob, AProcess: THandle): BOOL; stdcall;
  external kernel32 name 'AssignProcessToJobObject';

function CurrentEnvironment: TArray<string>;
var
  mBlock, mCursor: PWideChar;
  mItem: string;
begin
  Result := nil;
  mBlock := GetEnvironmentStringsW;
  if mBlock = nil then
  begin
    Exit;
  end;
  try
    mCursor := mBlock;
    while mCursor^ <> #0 do
    begin
      mItem := mCursor;
      Result := Result + [mItem];
      Inc(mCursor, Length(mItem) + 1);
    end;
  finally
    FreeEnvironmentStringsW(mBlock);
  end;
end;

function FileExistsProc: TAtlasTaskFileExists;
begin
  Result :=
    function(const AFileName: string): Boolean
    begin
      Result := FileExists(AFileName);
    end;
end;

type
  /// <summary>Programm, Befehlszeile und Umgebungsblock für TAtlasProcessLauncher.</summary>
  TLaunch = record
    ProgramPath: string;
    CommandLine: string;
    Environment: string;
  end;

  /// <summary>Handles eines Laufs; 0 bzw. INVALID_HANDLE_VALUE (NullInput) = nicht offen.</summary>
  THandles = record
    OutRead: THandle;
    OutWrite: THandle;
    NullInput: THandle;
    Job: THandle;
    Process: TProcessInformation;
  end;

/// <summary>Programm, Befehlszeile und Umgebung; False mit Result.Error (und Outcome), wenn nicht startbar.</summary>
function PrepareLaunch(const ATask: TAtlasTaskDefinition; out ALaunch: TLaunch;
  var AResult: TAtlasTaskProcessResult): Boolean;
var
  mBatch: Boolean;
begin
  ALaunch := Default(TLaunch);
  Result := False;
  if GetCurrentThreadId = MainThreadID then
  begin
    AResult.Error := 'main thread';
    Exit;
  end;
  ALaunch.ProgramPath := TAtlasTaskCommands.FindProgram(ATask.Command, ATask.Cwd, GetEnvironmentVariable('PATH'),
    GetEnvironmentVariable('PATHEXT'), FileExistsProc());
  if ALaunch.ProgramPath = '' then
  begin
    AResult.Outcome := TAtlasTaskOutcome.ProgramMissing;
    AResult.Error := ATask.Command;
    Exit;
  end;
  if (ATask.Cwd <> '') and not DirectoryExists(ATask.Cwd) then
  begin
    AResult.Error := ATask.Cwd;
    Exit;
  end;
  mBatch := TAtlasTaskCommands.IsBatch(ALaunch.ProgramPath);
  ALaunch.CommandLine := TAtlasTaskCommands.BuildCommandLine(ALaunch.ProgramPath, ATask.Args, mBatch);
  if mBatch then
  begin
    ALaunch.ProgramPath := GetEnvironmentVariable('ComSpec');
    if ALaunch.ProgramPath = '' then
    begin
      ALaunch.ProgramPath := 'cmd.exe';
    end;
  end;
  ALaunch.Environment := string.Join(#0, TAtlasTaskCommands.MergeEnvironment(CurrentEnvironment, ATask.EnvNames,
    ATask.EnvValues)) + #0#0;
  Result := True;
end;

function NoHandles: THandles;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.NullInput := INVALID_HANDLE_VALUE;
end;

/// <summary>Pipe für stdout/stderr, NUL als stdin und Job mit „beim Schließen beenden“.</summary>
function OpenHandles(var AHandles: THandles; var AResult: TAtlasTaskProcessResult): Boolean;
var
  mLimits: TJobExtendedLimits;
begin
  // Nicht vererbbar: Schreibende und NUL erbt der Prozess gezielt über TAtlasProcessLauncher (R-101).
  Result := CreatePipe(AHandles.OutRead, AHandles.OutWrite, nil, 0);
  if not Result then
  begin
    AResult.Error := SysErrorMessage(GetLastError);
    Exit;
  end;
  AHandles.NullInput := CreateFile('NUL', GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE, nil, OPEN_EXISTING, 0,
    0);
  AHandles.Job := CreateJob(nil, nil);
  if AHandles.Job <> 0 then
  begin
    FillChar(mLimits, SizeOf(mLimits), 0);
    mLimits.Basic.LimitFlags := cJobKillOnClose;
    SetJobInformation(AHandles.Job, cJobExtendedLimitClass, @mLimits, SizeOf(mLimits));
  end;
end;

/// <summary>Prozess unsichtbar starten, in den Job legen und laufen lassen.</summary>
function StartProcess(const ALaunch: TLaunch; const ACwd: string; var AHandles: THandles;
  var AResult: TAtlasTaskProcessResult): Boolean;
var
  mLaunch: TAtlasProcessLaunch;
  mInput: THandle;
begin
  mInput := 0;
  if AHandles.NullInput <> INVALID_HANDLE_VALUE then
  begin
    mInput := AHandles.NullInput;
  end;
  mLaunch := TAtlasProcessLaunch.Create(ALaunch.ProgramPath, ALaunch.CommandLine, ACwd, mInput, AHandles.OutWrite,
    AHandles.OutWrite);
  mLaunch.Hidden := True;
  mLaunch.Environment := ALaunch.Environment;
  // Angehalten starten, damit der Prozess im Job ist, bevor er Kinder startet.
  mLaunch.Flags := CREATE_NO_WINDOW or CREATE_SUSPENDED;
  Result := TAtlasProcessLauncher.Launch(mLaunch, AHandles.Process);
  if not Result then
  begin
    AResult.Error := SysErrorMessage(GetLastError);
    Exit;
  end;
  if AHandles.Job <> 0 then
  begin
    AssignToJob(AHandles.Job, AHandles.Process.hProcess);
  end;
  ResumeThread(AHandles.Process.hThread);
  CloseHandle(AHandles.OutWrite);
  AHandles.OutWrite := 0;
end;

function IsCancelled(const ACancelled: TFunc<Boolean>): Boolean;
begin
  Result := (not TThread.CurrentThread.ExternalThread and TThread.CheckTerminated) or
    (Assigned(ACancelled) and ACancelled());
end;

/// <summary>Alles Verfügbare aus der Pipe lesen und fertige Zeilen weitergeben.</summary>
procedure Drain(AOutRead: THandle; ALines: TAtlasTaskLines; var AChunk: TBytes; const AOnLine: TAtlasTaskLineProc);
var
  mAvailable, mBytesRead: DWORD;
  mText: string;
begin
  while PeekNamedPipe(AOutRead, nil, 0, nil, @mAvailable, nil) and (mAvailable > 0) do
  begin
    if mAvailable > DWORD(Length(AChunk)) then
    begin
      mAvailable := Length(AChunk);
    end;
    if not ReadFile(AOutRead, AChunk[0], mAvailable, mBytesRead, nil) or (mBytesRead = 0) then
    begin
      Exit;
    end;
    for mText in ALines.Feed(AChunk, Integer(mBytesRead)) do
    begin
      AOnLine(mText);
    end;
  end;
end;

/// <summary>Prozessbaum beenden: Job schließen beendet den ganzen Baum; ohne Job wenigstens den Prozess.</summary>
procedure StopProcess(var AHandles: THandles);
begin
  if AHandles.Job <> 0 then
  begin
    CloseHandle(AHandles.Job);
    AHandles.Job := 0;
  end
  else
  begin
    TerminateProcess(AHandles.Process.hProcess, 1);
  end;
  WaitForSingleObject(AHandles.Process.hProcess, 1000);
end;

function DeadlineOf(ATimeoutSec: Integer): UInt64;
begin
  Result := High(UInt64);
  if ATimeoutSec > 0 then
  begin
    Result := TThread.GetTickCount64 + UInt64(ATimeoutSec) * 1000;
  end;
end;

/// <summary>Im Takt lesen, bis der Prozess endet, abgebrochen wird oder die Zeit abläuft; danach den Rest.</summary>
function Watch(ATimeoutSec: Integer; var AHandles: THandles; ALines: TAtlasTaskLines;
  const ACancelled: TFunc<Boolean>; const AOnLine: TAtlasTaskLineProc): TAtlasTaskOutcome;
var
  mChunk: TBytes;
  mDeadline: UInt64;
  mLine: string;
begin
  SetLength(mChunk, 16384);
  Result := TAtlasTaskOutcome.Finished;
  mDeadline := DeadlineOf(ATimeoutSec);
  repeat
    Drain(AHandles.OutRead, ALines, mChunk, AOnLine);
    if WaitForSingleObject(AHandles.Process.hProcess, TAtlasTaskProcess.cSliceMs) = WAIT_OBJECT_0 then
    begin
      Break;
    end;
    if IsCancelled(ACancelled) then
    begin
      Result := TAtlasTaskOutcome.Cancelled;
    end
    else if TThread.GetTickCount64 >= mDeadline then
    begin
      Result := TAtlasTaskOutcome.TimedOut;
    end;
  until Result <> TAtlasTaskOutcome.Finished;
  if Result <> TAtlasTaskOutcome.Finished then
  begin
    StopProcess(AHandles);
  end;
  Drain(AHandles.OutRead, ALines, mChunk, AOnLine);
  for mLine in ALines.Flush do
  begin
    AOnLine(mLine);
  end;
end;

function ProcessExitCode(AProcess: THandle): Integer;
var
  mExitCode: DWORD;
begin
  if not GetExitCodeProcess(AProcess, mExitCode) then
  begin
    mExitCode := $FFFFFFFF;
  end;
  Result := Integer(mExitCode);
end;

procedure CloseIf(AHandle: THandle);
begin
  if AHandle <> 0 then
  begin
    CloseHandle(AHandle);
  end;
end;

procedure CloseHandles(const AHandles: THandles);
begin
  CloseIf(AHandles.Process.hThread);
  CloseIf(AHandles.Process.hProcess);
  // Enkelprozesse, die noch laufen, enden mit dem Job.
  CloseIf(AHandles.Job);
  if AHandles.NullInput <> INVALID_HANDLE_VALUE then
  begin
    CloseHandle(AHandles.NullInput);
  end;
  CloseIf(AHandles.OutRead);
  CloseIf(AHandles.OutWrite);
end;

class function TAtlasTaskProcess.Run(const ATask: TAtlasTaskDefinition; ACodePage: Integer;
  const ACancelled: TFunc<Boolean>; const AOnLine: TAtlasTaskLineProc): TAtlasTaskProcessResult;
var
  mLaunch: TLaunch;
  mHandles: THandles;
  mLines: TAtlasTaskLines;
begin
  Result := Default(TAtlasTaskProcessResult);
  Result.Outcome := TAtlasTaskOutcome.StartFailed;
  Result.ExitCode := -1;
  if not PrepareLaunch(ATask, mLaunch, Result) then
  begin
    Exit;
  end;
  if ACodePage = 0 then
  begin
    ACodePage := Integer(GetOEMCP);
  end;
  mHandles := NoHandles;
  mLines := TAtlasTaskLines.Create(ACodePage);
  try
    if OpenHandles(mHandles, Result) and StartProcess(mLaunch, ATask.Cwd, mHandles, Result) then
    begin
      Result.Outcome := Watch(ATask.TimeoutSec, mHandles, mLines, ACancelled, AOnLine);
      Result.ExitCode := ProcessExitCode(mHandles.Process.hProcess);
    end;
  finally
    mLines.Free;
    CloseHandles(mHandles);
  end;
end;

end.
