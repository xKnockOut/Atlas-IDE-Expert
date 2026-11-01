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
    /// <summary>Verfolgt den gestarteten Prozess AProcess für Cancel, liest seine Ausgabe aus AReadPipe und
    /// liefert den Exit-Code; ECompilerCancelled nach Cancel.</summary>
    function Supervise(const ARequest: TCompilerRequest; AReadPipe, AProcess: THandle;
      const AOnLine: TCompilerLineEvent): Integer;
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
    begin
      FRunning.Add(AProcess);
    end;
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
    begin
      TerminateProcess(Process, CancelledExitCode);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class function TProcessRunner.QuoteArgument(const AArgument: string): string;
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
  // Backslashes vor dem schließenden Anführungszeichen verdoppeln.
  Result := Result + StringOfChar('\', Backslashes) + '"';
end;

procedure RaiseCancelled(const ARequest: TCompilerRequest);
begin
  raise ECompilerCancelled.CreateFmt('%s: abgebrochen', [ExtractFileName(ARequest.Executable)]);
end;

/// <summary>Zeile ABytes[AFrom .. AFrom + ACount - 1] (ANSI, ohne #13 am Ende) an AOnLine.</summary>
procedure EmitLine(const ABytes: TBytes; AFrom, ACount: Integer; const AOnLine: TCompilerLineEvent);
var
  mLine: string;
begin
  mLine := TEncoding.ANSI.GetString(ABytes, AFrom, ACount);
  if (mLine <> '') and (mLine[Length(mLine)] = #13) then
  begin
    SetLength(mLine, Length(mLine) - 1);
  end;
  if Assigned(AOnLine) then
  begin
    AOnLine(mLine);
  end;
end;

/// <summary>Alle vollständigen Zeilen aus APending ausgeben; der angefangene Rest bleibt in APending.</summary>
procedure EmitCompleteLines(var APending: TBytes; const AOnLine: TCompilerLineEvent);
var
  mStart, mLineEnd: Integer;
begin
  mStart := 0;
  for mLineEnd := 0 to High(APending) do
  begin
    if APending[mLineEnd] = 10 then
    begin
      EmitLine(APending, mStart, mLineEnd - mStart, AOnLine);
      mStart := mLineEnd + 1;
    end;
  end;
  APending := Copy(APending, mStart, MaxInt);
end;

/// <summary>Liest die Pipe bis zum Ende und gibt die Ausgabe zeilenweise an AOnLine.</summary>
procedure ReadOutput(AReadPipe: THandle; const AOnLine: TCompilerLineEvent);
var
  mBuffer: array[0..4095] of Byte;
  mBytesRead: DWORD;
  mStart: Integer;
  mPending: TBytes;
begin
  mPending := nil;
  while ReadFile(AReadPipe, mBuffer, SizeOf(mBuffer), mBytesRead, nil) and (mBytesRead > 0) do
  begin
    mStart := Length(mPending);
    SetLength(mPending, mStart + Integer(mBytesRead));
    Move(mBuffer[0], mPending[mStart], mBytesRead);
    EmitCompleteLines(mPending, AOnLine);
  end;
  if Length(mPending) > 0 then
  begin
    EmitLine(mPending, 0, Length(mPending), AOnLine);
  end;
end;

function CommandLineOf(const ARequest: TCompilerRequest): string;
var
  mArgument: string;
begin
  Result := TProcessRunner.QuoteArgument(ARequest.Executable);
  for mArgument in ARequest.Arguments do
  begin
    Result := Result + ' ' + TProcessRunner.QuoteArgument(mArgument);
  end;
end;

/// <summary>Startet den Prozess unsichtbar, ohne Eingabe, stdout und stderr in AWritePipe.</summary>
procedure StartProcess(const ARequest: TCompilerRequest; AWritePipe: THandle;
  out AProcessInfo: TProcessInformation);
var
  mStartupInfo: TStartupInfo;
  mCommandLine: string;
  mWorkingDir: PChar;
begin
  FillChar(mStartupInfo, SizeOf(mStartupInfo), 0);
  mStartupInfo.cb := SizeOf(mStartupInfo);
  mStartupInfo.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
  mStartupInfo.wShowWindow := SW_HIDE;
  mStartupInfo.hStdInput := 0;
  mStartupInfo.hStdOutput := AWritePipe;
  mStartupInfo.hStdError := AWritePipe;
  mCommandLine := CommandLineOf(ARequest);
  UniqueString(mCommandLine);
  mWorkingDir := nil;
  if ARequest.WorkingDir <> '' then
  begin
    mWorkingDir := PChar(ARequest.WorkingDir);
  end;
  if not CreateProcess(PChar(ARequest.Executable), PChar(mCommandLine), nil, nil, True, CREATE_NO_WINDOW, nil,
    mWorkingDir, mStartupInfo, AProcessInfo) then
  begin
    raise ECompilerError.CreateFmt('%s lässt sich nicht starten: %s',
      [ARequest.Executable, SysErrorMessage(GetLastError)]);
  end;
end;

function WaitForExitCode(AProcess: THandle): Integer;
var
  mExitCode: DWORD;
begin
  WaitForSingleObject(AProcess, INFINITE);
  if not GetExitCodeProcess(AProcess, mExitCode) then
  begin
    RaiseLastOSError;
  end;
  Result := Integer(mExitCode);
end;

function TProcessRunner.Supervise(const ARequest: TCompilerRequest; AReadPipe, AProcess: THandle;
  const AOnLine: TCompilerLineEvent): Integer;
begin
  if not Track(AProcess) then
  begin
    TerminateProcess(AProcess, CancelledExitCode);
  end;
  try
    ReadOutput(AReadPipe, AOnLine);
    Result := WaitForExitCode(AProcess);
  finally
    // Vor CloseHandle: Cancel darf nie ein geschlossenes Handle beenden.
    Untrack(AProcess);
  end;
  if WasCancelled then
  begin
    RaiseCancelled(ARequest);
  end;
end;

function TProcessRunner.Run(const ARequest: TCompilerRequest; const AOnLine: TCompilerLineEvent): Integer;
var
  mSecurity: TSecurityAttributes;
  mReadPipe, mWritePipe: THandle;
  mProcessInfo: TProcessInformation;
begin
  if WasCancelled then
  begin
    RaiseCancelled(ARequest);
  end;
  mSecurity.nLength := SizeOf(mSecurity);
  mSecurity.lpSecurityDescriptor := nil;
  mSecurity.bInheritHandle := True;
  if not CreatePipe(mReadPipe, mWritePipe, @mSecurity, 0) then
  begin
    RaiseLastOSError;
  end;
  try
    // Nur das Schreibende erbt der Kindprozess.
    SetHandleInformation(mReadPipe, HANDLE_FLAG_INHERIT, 0);
    StartProcess(ARequest, mWritePipe, mProcessInfo);
    // Eigenes Schreibende schließen, damit ReadFile beim Prozessende False liefert.
    CloseHandle(mWritePipe);
    mWritePipe := 0;
    try
      Result := Supervise(ARequest, mReadPipe, mProcessInfo.hProcess, AOnLine);
    finally
      CloseHandle(mProcessInfo.hThread);
      CloseHandle(mProcessInfo.hProcess);
    end;
  finally
    CloseHandle(mReadPipe);
    if mWritePipe <> 0 then
    begin
      CloseHandle(mWritePipe);
    end;
  end;
end;

end.
