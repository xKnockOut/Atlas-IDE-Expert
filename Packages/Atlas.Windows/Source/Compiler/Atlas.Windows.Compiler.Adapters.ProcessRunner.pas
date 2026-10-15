unit Atlas.Windows.Compiler.Adapters.ProcessRunner;

// Startet den Compiler unsichtbar und liest stdout und stderr über eine Pipe
// (#40). Der Server spricht über die eigenen Standardkanäle mit dem Editor;
// der Kindprozess bekommt deshalb keine Eingabe und schreibt nur in die Pipe.
// Die Ausgabe von dcc32/dcc64 ist im ANSI-Zeichensatz des Systems kodiert.
// Cancel beendet laufende Prozesse per TerminateProcess (Code-Review A-05):
// Damit schließt sich das Schreibende der Pipe, ReadFile endet, und Run löst
// ECompilerCancelled aus.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Compiler.Contract;

type
  TProcessRunner = class(TInterfacedObject, ICompilerProcess)
  private
    FLock: TObject;
    /// <summary>Handles laufender Prozesse; unter FLock. Cancel beendet alle (mehrere Run gleichzeitig,
    /// z. B. Compilerlauf und git status).</summary>
    FRunning: TList<THandle>;
    /// <summary>Unter FLock.</summary>
    FCancelled: Boolean;
    /// <summary>Merkt sich AProcess für Cancel; False, wenn Cancel schon lief (der Aufrufer beendet den
    /// Prozess dann selbst).</summary>
    function Track(AProcess: THandle): Boolean;
    procedure Untrack(AProcess: THandle);
    function WasCancelled: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    function Run(const ARequest: TCompilerRequest; const AOnLine: TCompilerLineEvent): Integer;
    procedure Cancel;
    /// <summary>Kommandozeile mit Anführungszeichen nach den Regeln von CommandLineToArgvW.</summary>
    class function QuoteArgument(const AArgument: string): string; static;
  end;

implementation

uses
  Winapi.Windows;

const
  /// <summary>Exit-Code eines über Cancel beendeten Prozesses.</summary>
  CancelledExitCode = 1;

{ TProcessRunner }

constructor TProcessRunner.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FRunning := TList<THandle>.Create;
end;

destructor TProcessRunner.Destroy;
begin
  FRunning.Free;
  FLock.Free;
  inherited;
end;

function TProcessRunner.Track(AProcess: THandle): Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := not FCancelled;
    if Result then
      FRunning.Add(AProcess);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TProcessRunner.Untrack(AProcess: THandle);
begin
  TMonitor.Enter(FLock);
  try
    FRunning.Remove(AProcess);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TProcessRunner.WasCancelled: Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := FCancelled;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TProcessRunner.Cancel;
var
  Process: THandle;
begin
  TMonitor.Enter(FLock);
  try
    FCancelled := True;
    // Unter der Sperre: Run entfernt ein Handle erst (Untrack), bevor es es schließt.
    for Process in FRunning do
      TerminateProcess(Process, CancelledExitCode);
  finally
    TMonitor.Exit(FLock);
  end;
end;

class function TProcessRunner.QuoteArgument(const AArgument: string): string;
var
  Index, Backslashes: Integer;
begin
  if (AArgument <> '') and (LastDelimiter(' '#9'"', AArgument) = 0) then
    Exit(AArgument);
  Result := '"';
  Backslashes := 0;
  for Index := 1 to Length(AArgument) do
  begin
    if AArgument[Index] = '\' then
      Inc(Backslashes)
    else
    begin
      if AArgument[Index] = '"' then
        Result := Result + StringOfChar('\', Backslashes + 1);
      Backslashes := 0;
    end;
    Result := Result + AArgument[Index];
  end;
  // Backslashes vor dem schließenden Anführungszeichen verdoppeln.
  Result := Result + StringOfChar('\', Backslashes) + '"';
end;

function TProcessRunner.Run(const ARequest: TCompilerRequest; const AOnLine: TCompilerLineEvent): Integer;
var
  Security: TSecurityAttributes;
  ReadPipe, WritePipe: THandle;
  StartupInfo: TStartupInfo;
  ProcessInfo: TProcessInformation;
  CommandLine, Argument: string;
  Buffer: array[0..4095] of Byte;
  BytesRead, ProcessExitCode: DWORD;
  Pending: TBytes;
  LineEnd, Start: Integer;
  WorkingDir: PChar;

  procedure EmitLine(AFrom, ACount: Integer);
  var
    Line: string;
  begin
    Line := TEncoding.ANSI.GetString(Pending, AFrom, ACount);
    if (Line <> '') and (Line[Length(Line)] = #13) then
      SetLength(Line, Length(Line) - 1);
    if Assigned(AOnLine) then
      AOnLine(Line);
  end;

begin
  if WasCancelled then
    raise ECompilerCancelled.CreateFmt('%s: abgebrochen', [ExtractFileName(ARequest.Executable)]);
  Security.nLength := SizeOf(Security);
  Security.lpSecurityDescriptor := nil;
  Security.bInheritHandle := True;
  if not CreatePipe(ReadPipe, WritePipe, @Security, 0) then
    RaiseLastOSError;
  try
    // Nur das Schreibende erbt der Kindprozess.
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);
    FillChar(StartupInfo, SizeOf(StartupInfo), 0);
    StartupInfo.cb := SizeOf(StartupInfo);
    StartupInfo.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    StartupInfo.wShowWindow := SW_HIDE;
    StartupInfo.hStdInput := 0;
    StartupInfo.hStdOutput := WritePipe;
    StartupInfo.hStdError := WritePipe;
    CommandLine := QuoteArgument(ARequest.Executable);
    for Argument in ARequest.Arguments do
      CommandLine := CommandLine + ' ' + QuoteArgument(Argument);
    UniqueString(CommandLine);
    if ARequest.WorkingDir <> '' then
      WorkingDir := PChar(ARequest.WorkingDir)
    else
      WorkingDir := nil;
    if not CreateProcess(PChar(ARequest.Executable), PChar(CommandLine), nil, nil, True, CREATE_NO_WINDOW, nil,
      WorkingDir, StartupInfo, ProcessInfo) then
      raise ECompilerError.CreateFmt('%s lässt sich nicht starten: %s',
        [ARequest.Executable, SysErrorMessage(GetLastError)]);
    // Eigenes Schreibende schließen, damit ReadFile beim Prozessende False liefert.
    CloseHandle(WritePipe);
    WritePipe := 0;
    try
      if not Track(ProcessInfo.hProcess) then
        TerminateProcess(ProcessInfo.hProcess, CancelledExitCode);
      try
        Pending := nil;
        while ReadFile(ReadPipe, Buffer, SizeOf(Buffer), BytesRead, nil) and (BytesRead > 0) do
        begin
          Start := Length(Pending);
          SetLength(Pending, Start + Integer(BytesRead));
          Move(Buffer[0], Pending[Start], BytesRead);
          Start := 0;
          for LineEnd := 0 to High(Pending) do
            if Pending[LineEnd] = 10 then
            begin
              EmitLine(Start, LineEnd - Start);
              Start := LineEnd + 1;
            end;
          Pending := Copy(Pending, Start, MaxInt);
        end;
        if Length(Pending) > 0 then
          EmitLine(0, Length(Pending));
        WaitForSingleObject(ProcessInfo.hProcess, INFINITE);
        if not GetExitCodeProcess(ProcessInfo.hProcess, ProcessExitCode) then
          RaiseLastOSError;
        Result := Integer(ProcessExitCode);
      finally
        // Vor CloseHandle: Cancel darf nie ein geschlossenes Handle beenden.
        Untrack(ProcessInfo.hProcess);
      end;
      if WasCancelled then
        raise ECompilerCancelled.CreateFmt('%s: abgebrochen', [ExtractFileName(ARequest.Executable)]);
    finally
      CloseHandle(ProcessInfo.hThread);
      CloseHandle(ProcessInfo.hProcess);
    end;
  finally
    CloseHandle(ReadPipe);
    if WritePipe <> 0 then
      CloseHandle(WritePipe);
  end;
end;

end.
