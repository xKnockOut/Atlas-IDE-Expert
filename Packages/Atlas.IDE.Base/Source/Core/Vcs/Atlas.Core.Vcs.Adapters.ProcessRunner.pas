unit Atlas.Core.Vcs.Adapters.ProcessRunner;

// Startet git bzw. svn für die Versionsverwaltung (#571):
//   - unsichtbar: CREATE_NO_WINDOW und SW_HIDE, kein Konsolenfenster blitzt auf
//   - stdout und stderr über getrennte Pipes, gelesen mit PeekNamedPipe im
//     Takt von 10 ms; so blockiert weder eine volle Pipe noch ein Enkelprozess,
//     der die Pipe offen hält
//   - Zeitlimit: danach wird der Prozess beendet (Outcome TimedOut)
//   - Abbruch: endet der aufrufende Thread (TThread.Terminate, z. B.
//     TAtlasVcsWorker.Stop) oder meldet ACancelled True (Entladen der IDE), wird
//     der Prozess sofort beendet (Outcome Cancelled)
//   - im Hauptthread abgelehnt (Outcome MainThread), außer der Aufrufer erlaubt
//     es ausdrücklich (Server auf der Kommandozeile, Tests)
// stdin ist NUL: svn und git fragen nie nach. Dazu bekommt jeder Prozess die
// Umgebung der IDE mit GIT_TERMINAL_PROMPT=0 und GCM_INTERACTIVE=never
// (#1287): Auch Git Credential Manager öffnet kein Fenster; fehlt die
// Anmeldung, erkennt Atlas das am Fehler (Atlas.Core.Vcs.ServerAccess).

interface

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract;

type
  TAtlasVcsProcessRunner = class(TInterfacedObject, IAtlasVcsRunner)
  public const
    /// <summary>Mehr Ausgabe gilt als Fehler (Failed); schützt vor riesigen Dateien bei FileAt.</summary>
    MaxOutputBytes = 64 * 1024 * 1024;
  private
    FAllowMainThread: Boolean;
    FCancelled: TFunc<Boolean>;
    function IsCancelled: Boolean;
  public
    /// <summary>Lehnt den Hauptthread ab; Abbruch nur über das Ende des aufrufenden Threads.</summary>
    constructor Create; overload;
    /// <summary>AAllowMainThread: Hauptthread erlauben (Kommandozeile, Tests). ACancelled: zusätzlicher
    /// Abbruch, z. B. TAtlasShutdown.Signalled; nil = keiner.</summary>
    constructor Create(AAllowMainThread: Boolean; const ACancelled: TFunc<Boolean>); overload;
    function Run(const AExecutable: string; const AArguments: TArray<string>; const AWorkingDir: string;
      ATimeoutMs: Cardinal): TAtlasVcsRunResult;
    /// <summary>Argument nach den Regeln von CommandLineToArgvW.</summary>
    class function QuoteArgument(const AArgument: string): string; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Core.Vcs.ServerAccess;

const
  SliceMs = 10;
  MaxErrorBytes = 4096;

type
  TPipeBuffer = record
    Data: TBytes;
    Count: Integer;
    procedure Append(const ABuffer; ACount: Integer);
    function Bytes: TBytes;
  end;

procedure TPipeBuffer.Append(const ABuffer; ACount: Integer);
var
  Capacity: Integer;
begin
  if ACount <= 0 then
  begin
    Exit;
  end;
  Capacity := Length(Data);
  if Count + ACount > Capacity then
  begin
    if Capacity < 4096 then
    begin
      Capacity := 4096;
    end;
    while Capacity < Count + ACount do
    begin
      Capacity := Capacity * 2;
    end;
    SetLength(Data, Capacity);
  end;
  Move(ABuffer, Data[Count], ACount);
  Inc(Count, ACount);
end;

function TPipeBuffer.Bytes: TBytes;
begin
  Result := Copy(Data, 0, Count);
end;

/// <summary>Liest, was in der Pipe bereitliegt, ohne zu blockieren; False, wenn die Pipe geschlossen ist.</summary>
function Drain(APipe: THandle; var ABuffer: TPipeBuffer; ALimit: Integer): Boolean;
var
  Available, BytesRead: DWORD;
  Chunk: array[0..16383] of Byte;
  ToRead: DWORD;
begin
  Result := True;
  while True do
  begin
    Available := 0;
    if not PeekNamedPipe(APipe, nil, 0, nil, @Available, nil) then
    begin
      Exit(False);
    end;
    if Available = 0 then
    begin
      Exit;
    end;
    ToRead := Available;
    if ToRead > SizeOf(Chunk) then
    begin
      ToRead := SizeOf(Chunk);
    end;
    if not ReadFile(APipe, Chunk, ToRead, BytesRead, nil) or (BytesRead = 0) then
    begin
      Exit(False);
    end;
    // Über der Grenze weiterlesen, aber verwerfen: Der Prozess soll nicht an einer vollen Pipe hängen.
    if ABuffer.Count < ALimit then
    begin
      ABuffer.Append(Chunk, Integer(BytesRead));
    end;
  end;
end;

/// <summary>Umgebung des eigenen Prozesses als Einträge NAME=Wert.</summary>
function CurrentEnvironment: TArray<string>;
var
  mBlock, mEntry: PChar;
begin
  Result := nil;
  mBlock := GetEnvironmentStrings;
  if mBlock = nil then
  begin
    Exit;
  end;
  try
    mEntry := mBlock;
    while mEntry^ <> #0 do
    begin
      Result := Result + [string(mEntry)];
      Inc(mEntry, StrLen(mEntry) + 1);
    end;
  finally
    FreeEnvironmentStrings(mBlock);
  end;
end;

/// <summary>Umgebungsblock für CreateProcess (CREATE_UNICODE_ENVIRONMENT): ohne Rückfrage nach Zugangsdaten,
/// nach Namen sortiert (ohne Rücksicht auf Groß-/Kleinschreibung), Einträge mit #0 getrennt, am Ende #0#0.</summary>
function NoPromptBlock: string;
var
  mEntries: TArray<string>;
  mEntry: string;
begin
  mEntries := TAtlasVcsServerAccess.NoPromptEnvironment(CurrentEnvironment);
  // Namen sind eindeutig; bei Gleichstand (nur Einträge ohne Namen) nach dem ganzen Text.
  TArray.Sort<string>(mEntries, TComparer<string>.Construct(
    function(const ALeft, ARight: string): Integer
    begin
      Result := CompareText(TAtlasVcsServerAccess.VariableName(ALeft), TAtlasVcsServerAccess.VariableName(ARight));
      if Result = 0 then
      begin
        Result := CompareStr(ALeft, ARight);
      end;
    end));
  Result := '';
  for mEntry in mEntries do
  begin
    Result := Result + mEntry + #0;
  end;
  Result := Result + #0;
end;

{ TAtlasVcsProcessRunner }

constructor TAtlasVcsProcessRunner.Create;
begin
  Create(False, nil);
end;

constructor TAtlasVcsProcessRunner.Create(AAllowMainThread: Boolean; const ACancelled: TFunc<Boolean>);
begin
  inherited Create;
  FAllowMainThread := AAllowMainThread;
  FCancelled := ACancelled;
end;

function TAtlasVcsProcessRunner.IsCancelled: Boolean;
begin
  // CheckTerminated wirft im Hauptthread und in fremden Threads; dort gibt es nichts abzubrechen.
  Result := not TThread.CurrentThread.ExternalThread and TThread.CheckTerminated;
  if not Result and Assigned(FCancelled) then
  begin
    Result := FCancelled();
  end;
end;

class function TAtlasVcsProcessRunner.QuoteArgument(const AArgument: string): string;
var
  Index, Backslashes: Integer;
begin
  if (AArgument <> '') and (LastDelimiter(' '#9'"', AArgument) = 0) then
  begin
    Exit(AArgument);
  end;
  Result := '"';
  Backslashes := 0;
  for Index := 1 to Length(AArgument) do
  begin
    if AArgument[Index] = '\' then
    begin
      Inc(Backslashes);
    end
    else
    begin
      if AArgument[Index] = '"' then
      begin
        Result := Result + StringOfChar('\', Backslashes + 1);
      end;
      Backslashes := 0;
    end;
    Result := Result + AArgument[Index];
  end;
  Result := Result + StringOfChar('\', Backslashes) + '"';
end;

function TAtlasVcsProcessRunner.Run(const AExecutable: string; const AArguments: TArray<string>;
  const AWorkingDir: string; ATimeoutMs: Cardinal): TAtlasVcsRunResult;
var
  Security: TSecurityAttributes;
  OutRead, OutWrite, ErrRead, ErrWrite, NullInput: THandle;
  Startup: TStartupInfo;
  Process: TProcessInformation;
  CommandLine, Argument: string;
  WorkingDir: PChar;
  Output, Errors: TPipeBuffer;
  Deadline: UInt64;
  ExitCode: DWORD;
  Outcome: TAtlasVcsOutcome;
  Environment: string;
begin
  Result := TAtlasVcsRunResult.Make(TAtlasVcsOutcome.Failed, -1, nil);
  if not FAllowMainThread and (GetCurrentThreadId = MainThreadID) then
  begin
    Exit(TAtlasVcsRunResult.Make(TAtlasVcsOutcome.MainThread, -1, nil));
  end;
  if (AExecutable = '') or not FileExists(AExecutable) then
  begin
    Exit(TAtlasVcsRunResult.Make(TAtlasVcsOutcome.ToolMissing, -1, nil));
  end;
  if IsCancelled then
  begin
    Exit(TAtlasVcsRunResult.Make(TAtlasVcsOutcome.Cancelled, -1, nil));
  end;

  Security.nLength := SizeOf(Security);
  Security.lpSecurityDescriptor := nil;
  Security.bInheritHandle := True;
  OutRead := 0;
  OutWrite := 0;
  ErrRead := 0;
  ErrWrite := 0;
  NullInput := INVALID_HANDLE_VALUE;
  FillChar(Process, SizeOf(Process), 0);
  try
    if not CreatePipe(OutRead, OutWrite, @Security, 0) or not CreatePipe(ErrRead, ErrWrite, @Security, 0) then
    begin
      Exit;
    end;
    // Nur die Schreibenden erbt der Kindprozess.
    SetHandleInformation(OutRead, HANDLE_FLAG_INHERIT, 0);
    SetHandleInformation(ErrRead, HANDLE_FLAG_INHERIT, 0);
    NullInput := CreateFile('NUL', GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE, @Security, OPEN_EXISTING, 0, 0);

    FillChar(Startup, SizeOf(Startup), 0);
    Startup.cb := SizeOf(Startup);
    Startup.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    Startup.wShowWindow := SW_HIDE;
    if NullInput <> INVALID_HANDLE_VALUE then
    begin
      Startup.hStdInput := NullInput;
    end;
    Startup.hStdOutput := OutWrite;
    Startup.hStdError := ErrWrite;
    CommandLine := QuoteArgument(AExecutable);
    for Argument in AArguments do
    begin
      CommandLine := CommandLine + ' ' + QuoteArgument(Argument);
    end;
    UniqueString(CommandLine);
    if AWorkingDir <> '' then
    begin
      WorkingDir := PChar(AWorkingDir);
    end
    else
    begin
      WorkingDir := nil;
    end;
    Environment := NoPromptBlock;
    if not CreateProcess(PChar(AExecutable), PChar(CommandLine), nil, nil, True,
      CREATE_NO_WINDOW or CREATE_UNICODE_ENVIRONMENT, PChar(Environment), WorkingDir, Startup, Process) then
    begin
      // Programm verschwunden oder nicht ausführbar: wie nicht installiert.
      Result.Outcome := TAtlasVcsOutcome.ToolMissing;
      Exit;
    end;
    // Eigene Schreibenden schließen, damit die Pipes mit dem Prozess enden.
    CloseHandle(OutWrite);
    OutWrite := 0;
    CloseHandle(ErrWrite);
    ErrWrite := 0;

    Output := Default(TPipeBuffer);
    Errors := Default(TPipeBuffer);
    Deadline := TThread.GetTickCount64 + ATimeoutMs;
    Outcome := TAtlasVcsOutcome.Ok;
    while True do
    begin
      Drain(OutRead, Output, MaxOutputBytes + 1);
      Drain(ErrRead, Errors, MaxErrorBytes);
      if WaitForSingleObject(Process.hProcess, SliceMs) = WAIT_OBJECT_0 then
      begin
        Break;
      end;
      if IsCancelled then
      begin
        Outcome := TAtlasVcsOutcome.Cancelled;
      end
      else if TThread.GetTickCount64 >= Deadline then
      begin
        Outcome := TAtlasVcsOutcome.TimedOut;
      end;
      if Outcome <> TAtlasVcsOutcome.Ok then
      begin
        TerminateProcess(Process.hProcess, 1);
        WaitForSingleObject(Process.hProcess, 1000);
        Break;
      end;
    end;
    // Rest nach dem Ende; ein Enkelprozess mit offener Pipe hält hier nicht auf.
    Drain(OutRead, Output, MaxOutputBytes + 1);
    Drain(ErrRead, Errors, MaxErrorBytes);
    if not GetExitCodeProcess(Process.hProcess, ExitCode) then
    begin
      ExitCode := $FFFFFFFF;
    end;
    if (Outcome = TAtlasVcsOutcome.Ok) and (Output.Count > MaxOutputBytes) then
    begin
      Outcome := TAtlasVcsOutcome.Failed;
    end;
    Result := TAtlasVcsRunResult.Make(Outcome, Integer(ExitCode), nil);
    if Outcome = TAtlasVcsOutcome.Ok then
    begin
      Result.Output := Output.Bytes;
    end;
    if Errors.Count > 0 then
    begin
      Result.ErrorText := Trim(TEncoding.UTF8.GetString(Errors.Data, 0, Errors.Count));
    end;
  finally
    if Process.hThread <> 0 then
    begin
      CloseHandle(Process.hThread);
    end;
    if Process.hProcess <> 0 then
    begin
      CloseHandle(Process.hProcess);
    end;
    if NullInput <> INVALID_HANDLE_VALUE then
    begin
      CloseHandle(NullInput);
    end;
    if OutRead <> 0 then
    begin
      CloseHandle(OutRead);
    end;
    if OutWrite <> 0 then
    begin
      CloseHandle(OutWrite);
    end;
    if ErrRead <> 0 then
    begin
      CloseHandle(ErrRead);
    end;
    if ErrWrite <> 0 then
    begin
      CloseHandle(ErrWrite);
    end;
  end;
end;

end.
