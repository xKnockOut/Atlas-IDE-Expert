unit BDLsp.IdePlugin.Lsp.Adapters.ServerProcess;

// Startet BetterDelphiLSP als Kindprozess mit umgeleitetem stdin/stdout und
// verbindet ihn mit einem TLspClient (ADR 0006). Ein Lese-Thread reicht die
// Ausgabe an TLspClient.Receive weiter; endet der Prozess, wird der Client
// geschlossen. stderr geht nach NUL, damit eine volle Pipe den Server nie
// blockiert.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  BDLsp.IdePlugin.Lsp.Client;

type
  TLspServerProcess = class
  private
    FProcess: THandle;
    FInputWrite: THandle;
    FOutputRead: THandle;
    FReader: TThread;
    FClient: TLspClient;
    FWriteLock: TObject;
    procedure Write(const ABytes: TBytes);
  public
    /// <summary>Startet AExeName mit AArguments; löst bei Fehlern EOSError aus.</summary>
    constructor Create(const AExeName, AArguments: string);
    destructor Destroy; override;
    function Running: Boolean;
    property Client: TLspClient read FClient;
  end;

implementation

type
  TReaderThread = class(TThread)
  private
    FHandle: THandle;
    FClient: TLspClient;
  protected
    procedure Execute; override;
  public
    constructor Create(AHandle: THandle; AClient: TLspClient);
  end;

{ TReaderThread }

constructor TReaderThread.Create(AHandle: THandle; AClient: TLspClient);
begin
  FHandle := AHandle;
  FClient := AClient;
  inherited Create(False);
end;

procedure TReaderThread.Execute;
var
  Buffer: TBytes;
  Read: DWORD;
begin
  SetLength(Buffer, 65536);
  while not Terminated do
  begin
    if not ReadFile(FHandle, Buffer[0], Length(Buffer), Read, nil) or (Read = 0) then
      Break;
    FClient.Receive(Buffer, Integer(Read));
  end;
  FClient.Close;
end;

{ TLspServerProcess }

constructor TLspServerProcess.Create(const AExeName, AArguments: string);
var
  Security: TSecurityAttributes;
  InputRead, OutputWrite, NulHandle: THandle;
  Startup: TStartupInfo;
  Info: TProcessInformation;
  CommandLine: string;
begin
  inherited Create;
  FWriteLock := TObject.Create;
  Security := Default(TSecurityAttributes);
  Security.nLength := SizeOf(Security);
  Security.bInheritHandle := True;
  if not CreatePipe(InputRead, FInputWrite, @Security, 0) then
    RaiseLastOSError;
  if not CreatePipe(FOutputRead, OutputWrite, @Security, 0) then
    RaiseLastOSError;
  // Die eigenen Enden dürfen nicht vererbt werden, sonst endet der Server nie.
  SetHandleInformation(FInputWrite, HANDLE_FLAG_INHERIT, 0);
  SetHandleInformation(FOutputRead, HANDLE_FLAG_INHERIT, 0);
  NulHandle := CreateFile('NUL', GENERIC_WRITE, FILE_SHARE_READ or FILE_SHARE_WRITE, @Security,
    OPEN_EXISTING, 0, 0);
  try
    Startup := Default(TStartupInfo);
    Startup.cb := SizeOf(Startup);
    Startup.dwFlags := STARTF_USESTDHANDLES;
    Startup.hStdInput := InputRead;
    Startup.hStdOutput := OutputWrite;
    Startup.hStdError := NulHandle;
    CommandLine := '"' + AExeName + '" ' + AArguments;
    UniqueString(CommandLine);
    if not CreateProcess(nil, PChar(CommandLine), nil, nil, True, CREATE_NO_WINDOW, nil,
      PChar(ExtractFileDir(AExeName)), Startup, Info) then
      RaiseLastOSError;
  finally
    CloseHandle(InputRead);
    CloseHandle(OutputWrite);
    if NulHandle <> INVALID_HANDLE_VALUE then
      CloseHandle(NulHandle);
  end;
  CloseHandle(Info.hThread);
  FProcess := Info.hProcess;
  FClient := TLspClient.Create(Write);
  FReader := TReaderThread.Create(FOutputRead, FClient);
end;

destructor TLspServerProcess.Destroy;
begin
  if FClient <> nil then
    FClient.Close;
  // stdin schließen: Der Server sieht das Ende der Eingabe und beendet sich.
  if FInputWrite <> 0 then
    CloseHandle(FInputWrite);
  if FProcess <> 0 then
  begin
    if WaitForSingleObject(FProcess, 2000) <> WAIT_OBJECT_0 then
      TerminateProcess(FProcess, 1);
    CloseHandle(FProcess);
  end;
  if FReader <> nil then
  begin
    FReader.WaitFor;
    FReader.Free;
  end;
  if FOutputRead <> 0 then
    CloseHandle(FOutputRead);
  FClient.Free;
  FWriteLock.Free;
  inherited;
end;

procedure TLspServerProcess.Write(const ABytes: TBytes);
var
  Written: DWORD;
  Offset: Integer;
begin
  TMonitor.Enter(FWriteLock);
  try
    Offset := 0;
    while Offset < Length(ABytes) do
    begin
      if not WriteFile(FInputWrite, ABytes[Offset], Length(ABytes) - Offset, Written, nil) then
        raise ELspClientError.Create('Server nimmt keine Daten mehr an');
      Inc(Offset, Integer(Written));
    end;
  finally
    TMonitor.Exit(FWriteLock);
  end;
end;

function TLspServerProcess.Running: Boolean;
begin
  Result := (FProcess <> 0) and (WaitForSingleObject(FProcess, 0) = WAIT_TIMEOUT) and not FClient.Closed;
end;

end.
