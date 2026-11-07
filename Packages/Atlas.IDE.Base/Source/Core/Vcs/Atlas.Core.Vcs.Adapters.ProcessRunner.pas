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
    /// <summary>True, wenn gar nicht gestartet wird (Hauptthread, Programm fehlt, Abbruch); AOutcome sagt warum.</summary>
    function Refused(const AExecutable: string; out AOutcome: TAtlasVcsOutcome): Boolean;
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
  cSliceMs = 10;
  cMaxErrorBytes = 4096;

type
  TPipeBuffer = record
    Data: TBytes;
    Count: Integer;
    procedure Append(const ABuffer; ACount: Integer);
    function Bytes: TBytes;
  end;

procedure TPipeBuffer.Append(const ABuffer; ACount: Integer);
var
  mCapacity: Integer;
begin
  if ACount <= 0 then
  begin
    Exit;
  end;
  mCapacity := Length(Data);
  if Count + ACount > mCapacity then
  begin
    if mCapacity < 4096 then
    begin
      mCapacity := 4096;
    end;
    while mCapacity < Count + ACount do
    begin
      mCapacity := mCapacity * 2;
    end;
    SetLength(Data, mCapacity);
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
  mAvailable, mBytesRead: DWORD;
  mChunk: array[0..16383] of Byte;
  mToRead: DWORD;
begin
  Result := True;
  while True do
  begin
    mAvailable := 0;
    if not PeekNamedPipe(APipe, nil, 0, nil, @mAvailable, nil) then
    begin
      Exit(False);
    end;
    if mAvailable = 0 then
    begin
      Exit;
    end;
    mToRead := mAvailable;
    if mToRead > SizeOf(mChunk) then
    begin
      mToRead := SizeOf(mChunk);
    end;
    if not ReadFile(APipe, mChunk, mToRead, mBytesRead, nil) or (mBytesRead = 0) then
    begin
      Exit(False);
    end;
    // Über der Grenze weiterlesen, aber verwerfen: Der Prozess soll nicht an einer vollen Pipe hängen.
    if ABuffer.Count < ALimit then
    begin
      ABuffer.Append(mChunk, Integer(mBytesRead));
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
  mIndex, mBackslashes: Integer;
begin
  if (AArgument <> '') and (LastDelimiter(' '#9'"', AArgument) = 0) then
  begin
    Exit(AArgument);
  end;
  Result := '"';
  mBackslashes := 0;
  for mIndex := 1 to Length(AArgument) do
  begin
    if AArgument[mIndex] = '\' then
    begin
      Inc(mBackslashes);
    end
    else
    begin
      if AArgument[mIndex] = '"' then
      begin
        Result := Result + StringOfChar('\', mBackslashes + 1);
      end;
      mBackslashes := 0;
    end;
    Result := Result + AArgument[mIndex];
  end;
  Result := Result + StringOfChar('\', mBackslashes) + '"';
end;

function TAtlasVcsProcessRunner.Refused(const AExecutable: string; out AOutcome: TAtlasVcsOutcome): Boolean;
begin
  AOutcome := TAtlasVcsOutcome.Ok;
  if not FAllowMainThread and (GetCurrentThreadId = MainThreadID) then
  begin
    AOutcome := TAtlasVcsOutcome.MainThread;
  end
  else if (AExecutable = '') or not FileExists(AExecutable) then
  begin
    AOutcome := TAtlasVcsOutcome.ToolMissing;
  end
  else if IsCancelled then
  begin
    AOutcome := TAtlasVcsOutcome.Cancelled;
  end;
  Result := AOutcome <> TAtlasVcsOutcome.Ok;
end;

type
  /// <summary>Ein Kindprozess mit seinen Pipes; der Destruktor schließt alle Handles.</summary>
  TChildProcess = class
  private
    FOutRead: THandle;
    FOutWrite: THandle;
    FErrRead: THandle;
    FErrWrite: THandle;
    FNullInput: THandle;
    FProcess: TProcessInformation;
    FOutput: TPipeBuffer;
    FErrors: TPipeBuffer;
    function OpenPipes: Boolean;
    function StartupInfo: TStartupInfo;
    function Start(const AExecutable, ACommandLine, AWorkingDir: string): Boolean;
    procedure DrainAll;
    function Wait(ARunner: TAtlasVcsProcessRunner; ATimeoutMs: Cardinal): TAtlasVcsOutcome;
    function Finish(AOutcome: TAtlasVcsOutcome): TAtlasVcsRunResult;
  public
    constructor Create;
    destructor Destroy; override;
    function Execute(ARunner: TAtlasVcsProcessRunner; const AExecutable, ACommandLine, AWorkingDir: string;
      ATimeoutMs: Cardinal): TAtlasVcsRunResult;
  end;

procedure CloseHandleOf(var AHandle: THandle; AEmpty: THandle);
begin
  if AHandle <> AEmpty then
  begin
    CloseHandle(AHandle);
    AHandle := AEmpty;
  end;
end;

function CommandLineOf(const AExecutable: string; const AArguments: TArray<string>): string;
var
  mArgument: string;
begin
  Result := TAtlasVcsProcessRunner.QuoteArgument(AExecutable);
  for mArgument in AArguments do
  begin
    Result := Result + ' ' + TAtlasVcsProcessRunner.QuoteArgument(mArgument);
  end;
end;

/// <summary>Abbruch oder Zeitlimit während der Prozess läuft; sonst Ok.</summary>
function Interruption(ARunner: TAtlasVcsProcessRunner; ADeadline: UInt64): TAtlasVcsOutcome;
begin
  Result := TAtlasVcsOutcome.Ok;
  if ARunner.IsCancelled then
  begin
    Result := TAtlasVcsOutcome.Cancelled;
  end
  else if TThread.GetTickCount64 >= ADeadline then
  begin
    Result := TAtlasVcsOutcome.TimedOut;
  end;
end;

constructor TChildProcess.Create;
begin
  inherited Create;
  FNullInput := INVALID_HANDLE_VALUE;
end;

destructor TChildProcess.Destroy;
begin
  CloseHandleOf(FProcess.hThread, 0);
  CloseHandleOf(FProcess.hProcess, 0);
  CloseHandleOf(FNullInput, INVALID_HANDLE_VALUE);
  CloseHandleOf(FOutRead, 0);
  CloseHandleOf(FOutWrite, 0);
  CloseHandleOf(FErrRead, 0);
  CloseHandleOf(FErrWrite, 0);
  inherited;
end;

function TChildProcess.OpenPipes: Boolean;
var
  mSecurity: TSecurityAttributes;
begin
  mSecurity.nLength := SizeOf(mSecurity);
  mSecurity.lpSecurityDescriptor := nil;
  mSecurity.bInheritHandle := True;
  Result := CreatePipe(FOutRead, FOutWrite, @mSecurity, 0) and CreatePipe(FErrRead, FErrWrite, @mSecurity, 0);
  if Result then
  begin
    // Nur die Schreibenden erbt der Kindprozess.
    SetHandleInformation(FOutRead, HANDLE_FLAG_INHERIT, 0);
    SetHandleInformation(FErrRead, HANDLE_FLAG_INHERIT, 0);
    FNullInput := CreateFile('NUL', GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE, @mSecurity, OPEN_EXISTING, 0,
      0);
  end;
end;

function TChildProcess.StartupInfo: TStartupInfo;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.cb := SizeOf(Result);
  Result.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
  Result.wShowWindow := SW_HIDE;
  if FNullInput <> INVALID_HANDLE_VALUE then
  begin
    Result.hStdInput := FNullInput;
  end;
  Result.hStdOutput := FOutWrite;
  Result.hStdError := FErrWrite;
end;

function TChildProcess.Start(const AExecutable, ACommandLine, AWorkingDir: string): Boolean;
var
  mStartup: TStartupInfo;
  mCommandLine, mEnvironment: string;
  mWorkingDir: PChar;
begin
  mStartup := StartupInfo;
  mCommandLine := ACommandLine;
  UniqueString(mCommandLine);
  mWorkingDir := nil;
  if AWorkingDir <> '' then
  begin
    mWorkingDir := PChar(AWorkingDir);
  end;
  mEnvironment := NoPromptBlock;
  Result := CreateProcess(PChar(AExecutable), PChar(mCommandLine), nil, nil, True,
    CREATE_NO_WINDOW or CREATE_UNICODE_ENVIRONMENT, PChar(mEnvironment), mWorkingDir, mStartup, FProcess);
  if Result then
  begin
    // Eigene Schreibenden schließen, damit die Pipes mit dem Prozess enden.
    CloseHandleOf(FOutWrite, 0);
    CloseHandleOf(FErrWrite, 0);
  end;
end;

procedure TChildProcess.DrainAll;
begin
  Drain(FOutRead, FOutput, TAtlasVcsProcessRunner.MaxOutputBytes + 1);
  Drain(FErrRead, FErrors, cMaxErrorBytes);
end;

function TChildProcess.Wait(ARunner: TAtlasVcsProcessRunner; ATimeoutMs: Cardinal): TAtlasVcsOutcome;
var
  mDeadline: UInt64;
begin
  mDeadline := TThread.GetTickCount64 + ATimeoutMs;
  repeat
    DrainAll;
    if WaitForSingleObject(FProcess.hProcess, cSliceMs) = WAIT_OBJECT_0 then
    begin
      Result := TAtlasVcsOutcome.Ok;
      Break;
    end;
    Result := Interruption(ARunner, mDeadline);
  until Result <> TAtlasVcsOutcome.Ok;
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    TerminateProcess(FProcess.hProcess, 1);
    WaitForSingleObject(FProcess.hProcess, 1000);
  end;
  // Rest nach dem Ende; ein Enkelprozess mit offener Pipe hält hier nicht auf.
  DrainAll;
end;

function TChildProcess.Finish(AOutcome: TAtlasVcsOutcome): TAtlasVcsRunResult;
var
  mExitCode: DWORD;
  mOutcome: TAtlasVcsOutcome;
begin
  if not GetExitCodeProcess(FProcess.hProcess, mExitCode) then
  begin
    mExitCode := $FFFFFFFF;
  end;
  mOutcome := AOutcome;
  if (mOutcome = TAtlasVcsOutcome.Ok) and (FOutput.Count > TAtlasVcsProcessRunner.MaxOutputBytes) then
  begin
    mOutcome := TAtlasVcsOutcome.Failed;
  end;
  Result := TAtlasVcsRunResult.Make(mOutcome, Integer(mExitCode), nil);
  if mOutcome = TAtlasVcsOutcome.Ok then
  begin
    Result.Output := FOutput.Bytes;
  end;
  if FErrors.Count > 0 then
  begin
    Result.ErrorText := Trim(TEncoding.UTF8.GetString(FErrors.Data, 0, FErrors.Count));
  end;
end;

function TChildProcess.Execute(ARunner: TAtlasVcsProcessRunner; const AExecutable, ACommandLine,
  AWorkingDir: string; ATimeoutMs: Cardinal): TAtlasVcsRunResult;
begin
  Result := TAtlasVcsRunResult.Make(TAtlasVcsOutcome.Failed, -1, nil);
  if not OpenPipes then
  begin
    Exit;
  end;
  if not Start(AExecutable, ACommandLine, AWorkingDir) then
  begin
    // Programm verschwunden oder nicht ausführbar: wie nicht installiert.
    Result.Outcome := TAtlasVcsOutcome.ToolMissing;
    Exit;
  end;
  Result := Finish(Wait(ARunner, ATimeoutMs));
end;

function TAtlasVcsProcessRunner.Run(const AExecutable: string; const AArguments: TArray<string>;
  const AWorkingDir: string; ATimeoutMs: Cardinal): TAtlasVcsRunResult;
var
  mOutcome: TAtlasVcsOutcome;
  mChild: TChildProcess;
begin
  if Refused(AExecutable, mOutcome) then
  begin
    Exit(TAtlasVcsRunResult.Make(mOutcome, -1, nil));
  end;
  mChild := TChildProcess.Create;
  try
    Result := mChild.Execute(Self, AExecutable, CommandLineOf(AExecutable, AArguments), AWorkingDir, ATimeoutMs);
  finally
    mChild.Free;
  end;
end;

end.
