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
    SliceMs = 10;
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
  JobKillOnClose = $00002000;
  JobExtendedLimitClass = 9;
  CreateUnicodeEnvironment = $00000400;

function CreateJob(AAttributes: Pointer; AName: PWideChar): THandle; stdcall;
  external kernel32 name 'CreateJobObjectW';
function SetJobInformation(AJob: THandle; AClass: Integer; AInfo: Pointer; ALength: DWORD): BOOL; stdcall;
  external kernel32 name 'SetInformationJobObject';
function AssignToJob(AJob, AProcess: THandle): BOOL; stdcall;
  external kernel32 name 'AssignProcessToJobObject';

function CurrentEnvironment: TArray<string>;
var
  Block, Cursor: PWideChar;
  Item: string;
begin
  Result := nil;
  Block := GetEnvironmentStringsW;
  if Block = nil then
    Exit;
  try
    Cursor := Block;
    while Cursor^ <> #0 do
    begin
      Item := Cursor;
      Result := Result + [Item];
      Inc(Cursor, Length(Item) + 1);
    end;
  finally
    FreeEnvironmentStringsW(Block);
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

class function TAtlasTaskProcess.Run(const ATask: TAtlasTaskDefinition; ACodePage: Integer;
  const ACancelled: TFunc<Boolean>; const AOnLine: TAtlasTaskLineProc): TAtlasTaskProcessResult;
var
  Security: TSecurityAttributes;
  OutRead, OutWrite, NullInput, Job: THandle;
  Startup: TStartupInfo;
  Process: TProcessInformation;
  Limits: TJobExtendedLimits;
  ProgramPath, CommandLine, Environment, ComSpec: string;
  Batch: Boolean;
  WorkingDir: PChar;
  Lines: TAtlasTaskLines;
  Chunk: TBytes;
  Available, BytesRead, ExitCode: DWORD;
  Deadline: UInt64;
  Line: string;

  function Cancelled: Boolean;
  begin
    Result := (not TThread.CurrentThread.ExternalThread and TThread.CheckTerminated) or
      (Assigned(ACancelled) and ACancelled());
  end;

  procedure Drain;
  var
    Text: string;
  begin
    while PeekNamedPipe(OutRead, nil, 0, nil, @Available, nil) and (Available > 0) do
    begin
      if Available > DWORD(Length(Chunk)) then
        Available := Length(Chunk);
      if not ReadFile(OutRead, Chunk[0], Available, BytesRead, nil) or (BytesRead = 0) then
        Exit;
      for Text in Lines.Feed(Chunk, Integer(BytesRead)) do
        AOnLine(Text);
    end;
  end;

begin
  Result := Default(TAtlasTaskProcessResult);
  Result.Outcome := TAtlasTaskOutcome.StartFailed;
  Result.ExitCode := -1;
  if GetCurrentThreadId = MainThreadID then
  begin
    Result.Error := 'main thread';
    Exit;
  end;
  ProgramPath := TAtlasTaskCommands.FindProgram(ATask.Command, ATask.Cwd, GetEnvironmentVariable('PATH'),
    GetEnvironmentVariable('PATHEXT'), FileExistsProc);
  if ProgramPath = '' then
  begin
    Result.Outcome := TAtlasTaskOutcome.ProgramMissing;
    Result.Error := ATask.Command;
    Exit;
  end;
  if (ATask.Cwd <> '') and not DirectoryExists(ATask.Cwd) then
  begin
    Result.Error := ATask.Cwd;
    Exit;
  end;
  Batch := TAtlasTaskCommands.IsBatch(ProgramPath);
  CommandLine := TAtlasTaskCommands.BuildCommandLine(ProgramPath, ATask.Args, Batch);
  if Batch then
  begin
    ComSpec := GetEnvironmentVariable('ComSpec');
    if ComSpec = '' then
      ComSpec := 'cmd.exe';
    ProgramPath := ComSpec;
  end;
  UniqueString(CommandLine);
  Environment := string.Join(#0, TAtlasTaskCommands.MergeEnvironment(CurrentEnvironment, ATask.EnvNames,
    ATask.EnvValues)) + #0#0;
  if ACodePage = 0 then
    ACodePage := Integer(GetOEMCP);

  Security.nLength := SizeOf(Security);
  Security.lpSecurityDescriptor := nil;
  Security.bInheritHandle := True;
  OutRead := 0;
  OutWrite := 0;
  Job := 0;
  NullInput := INVALID_HANDLE_VALUE;
  FillChar(Process, SizeOf(Process), 0);
  Lines := TAtlasTaskLines.Create(ACodePage);
  try
    if not CreatePipe(OutRead, OutWrite, @Security, 0) then
    begin
      Result.Error := SysErrorMessage(GetLastError);
      Exit;
    end;
    SetHandleInformation(OutRead, HANDLE_FLAG_INHERIT, 0);
    NullInput := CreateFile('NUL', GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE, @Security, OPEN_EXISTING, 0, 0);
    Job := CreateJob(nil, nil);
    if Job <> 0 then
    begin
      FillChar(Limits, SizeOf(Limits), 0);
      Limits.Basic.LimitFlags := JobKillOnClose;
      SetJobInformation(Job, JobExtendedLimitClass, @Limits, SizeOf(Limits));
    end;

    FillChar(Startup, SizeOf(Startup), 0);
    Startup.cb := SizeOf(Startup);
    Startup.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    Startup.wShowWindow := SW_HIDE;
    if NullInput <> INVALID_HANDLE_VALUE then
      Startup.hStdInput := NullInput;
    Startup.hStdOutput := OutWrite;
    Startup.hStdError := OutWrite;
    if ATask.Cwd <> '' then
      WorkingDir := PChar(ATask.Cwd)
    else
      WorkingDir := nil;
    // Angehalten starten, damit der Prozess im Job ist, bevor er Kinder startet.
    if not CreateProcess(PChar(ProgramPath), PChar(CommandLine), nil, nil, True,
      CREATE_NO_WINDOW or CREATE_SUSPENDED or CreateUnicodeEnvironment, PChar(Environment), WorkingDir, Startup,
      Process) then
    begin
      Result.Error := SysErrorMessage(GetLastError);
      Exit;
    end;
    if Job <> 0 then
      AssignToJob(Job, Process.hProcess);
    ResumeThread(Process.hThread);
    CloseHandle(OutWrite);
    OutWrite := 0;

    SetLength(Chunk, 16384);
    Result.Outcome := TAtlasTaskOutcome.Finished;
    if ATask.TimeoutSec > 0 then
      Deadline := TThread.GetTickCount64 + UInt64(ATask.TimeoutSec) * 1000
    else
      Deadline := High(UInt64);
    while True do
    begin
      Drain;
      if WaitForSingleObject(Process.hProcess, TAtlasTaskProcess.SliceMs) = WAIT_OBJECT_0 then
        Break;
      if Cancelled then
        Result.Outcome := TAtlasTaskOutcome.Cancelled
      else if TThread.GetTickCount64 >= Deadline then
        Result.Outcome := TAtlasTaskOutcome.TimedOut;
      if Result.Outcome <> TAtlasTaskOutcome.Finished then
      begin
        // Job schließen beendet den ganzen Baum; ohne Job wenigstens den Prozess.
        if Job <> 0 then
        begin
          CloseHandle(Job);
          Job := 0;
        end
        else
          TerminateProcess(Process.hProcess, 1);
        WaitForSingleObject(Process.hProcess, 1000);
        Break;
      end;
    end;
    Drain;
    for Line in Lines.Flush do
      AOnLine(Line);
    if not GetExitCodeProcess(Process.hProcess, ExitCode) then
      ExitCode := $FFFFFFFF;
    Result.ExitCode := Integer(ExitCode);
  finally
    Lines.Free;
    if Process.hThread <> 0 then
      CloseHandle(Process.hThread);
    if Process.hProcess <> 0 then
      CloseHandle(Process.hProcess);
    // Enkelprozesse, die noch laufen, enden mit dem Job.
    if Job <> 0 then
      CloseHandle(Job);
    if NullInput <> INVALID_HANDLE_VALUE then
      CloseHandle(NullInput);
    if OutRead <> 0 then
      CloseHandle(OutRead);
    if OutWrite <> 0 then
      CloseHandle(OutWrite);
  end;
end;

end.
