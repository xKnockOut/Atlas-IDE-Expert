unit Atlas.Windows.Compiler.Adapters.ProcessRunner;

// Startet den Compiler unsichtbar und liest stdout und stderr über eine Pipe
// (#40). Der Server spricht über die eigenen Standardkanäle mit dem Editor;
// der Kindprozess bekommt deshalb keine Eingabe und schreibt nur in die Pipe.
// Die Ausgabe von dcc32/dcc64 ist im ANSI-Zeichensatz des Systems kodiert.
// Cancel beendet laufende Prozesse per TerminateProcess:
// Damit schließt sich das Schreibende der Pipe, ReadFile endet, und Run löst
// ECompilerCancelled aus.

interface

uses
  System.SysUtils,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Compiler.ProcessRuns;

type
  TProcessRunner = class(TInterfacedObject, ICompilerProcess)
  private
    /// <summary>Laufende Prozesse für Cancel.</summary>
    FProcesses: TCompilerProcessList<THandle>;
    /// <summary>Verfolgt den gestarteten Prozess AProcess für Cancel, liest seine Ausgabe aus AReadPipe und
    /// liefert den Exit-Code; ECompilerCancelled nach Cancel.</summary>
    function Supervise(const ARequest: TCompilerRequest; AReadPipe, AProcess: THandle;
      const AOnLine: TCompilerLineEvent): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    function Run(const ARequest: TCompilerRequest; const AOnLine: TCompilerLineEvent): Integer;
    procedure Cancel;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.WinBase.Process,
  Atlas.Text.CommandLine;

const
  /// <summary>Exit-Code eines über Cancel beendeten Prozesses.</summary>
  cCancelledExitCode = 1;

{ TProcessRunner }

constructor TProcessRunner.Create;
begin
  inherited Create;
  FProcesses := TCompilerProcessList<THandle>.Create;
end;

destructor TProcessRunner.Destroy;
begin
  FProcesses.Free;
  inherited;
end;

procedure TProcessRunner.Cancel;
begin
  FProcesses.Cancel(
    procedure(const AProcess: THandle)
    begin
      TerminateProcess(AProcess, cCancelledExitCode);
    end);
end;

procedure RaiseCancelled(const ARequest: TCompilerRequest);
begin
  raise ECompilerCancelled.CreateFmt('%s: abgebrochen', [ExtractFileName(ARequest.Executable)]);
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
    TCompilerOutputLines.EmitComplete(mPending, TEncoding.ANSI, AOnLine);
  end;
  if Length(mPending) > 0 then
  begin
    TCompilerOutputLines.Emit(mPending, 0, Length(mPending), TEncoding.ANSI, AOnLine);
  end;
end;

function CommandLineOf(const ARequest: TCompilerRequest): string;
begin
  Result := TTextCommandLine.Join(ARequest.Executable, ARequest.Arguments);
end;

/// <summary>Startet den Prozess unsichtbar, ohne Eingabe, stdout und stderr in AWritePipe; nur dieses Handle erbt
/// er.</summary>
procedure StartProcess(const ARequest: TCompilerRequest; AWritePipe: THandle;
  out AProcessInfo: TProcessInformation);
var
  mLaunch: TAtlasProcessLaunch;
begin
  mLaunch := TAtlasProcessLaunch.Create(ARequest.Executable, CommandLineOf(ARequest), ARequest.WorkingDir, 0,
    AWritePipe, AWritePipe);
  mLaunch.Hidden := True;
  if not TAtlasProcessLauncher.Launch(mLaunch, AProcessInfo) then
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
  if not FProcesses.Track(AProcess) then
  begin
    TerminateProcess(AProcess, cCancelledExitCode);
  end;
  try
    ReadOutput(AReadPipe, AOnLine);
    Result := WaitForExitCode(AProcess);
  finally
    // Vor CloseHandle: Cancel darf nie ein geschlossenes Handle beenden.
    FProcesses.Untrack(AProcess);
  end;
  if FProcesses.WasCancelled then
  begin
    RaiseCancelled(ARequest);
  end;
end;

function TProcessRunner.Run(const ARequest: TCompilerRequest; const AOnLine: TCompilerLineEvent): Integer;
var
  mReadPipe, mWritePipe: THandle;
  mProcessInfo: TProcessInformation;
begin
  if FProcesses.WasCancelled then
  begin
    RaiseCancelled(ARequest);
  end;
  // Nicht vererbbar: Das Schreibende vererbt TAtlasProcessLauncher gezielt an den Compiler.
  if not CreatePipe(mReadPipe, mWritePipe, nil, 0) then
  begin
    RaiseLastOSError;
  end;
  try
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
