unit Argus.Core.Lsp.Adapters.ServerProcess;

// Startet Argus als Kindprozess mit umgeleitetem stdin/stdout und
// verbindet ihn mit einem TLspClient (ADR 0006). Ein Lese-Thread reicht die
// Ausgabe an TLspClient.Receive weiter; endet der Prozess, wird der Client
// geschlossen. stderr geht nach NUL, damit eine volle Pipe den Server nie
// blockiert.
// Geschrieben wird in einem eigenen Thread: Write legt die Bytes nur in eine
// Warteschlange. Liest der Server gerade nicht (etwa beim Einlesen eines
// großen Projekts), wartet so nie der Hauptthread der IDE an der Pipe; Anfragen
// kehren nach ihrem Zeitlimit zurück, Benachrichtigungen sofort.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Argus.Core.Lsp.Client;

type
  TLspServerProcess = class
  private
    FProcess: THandle;
    FInputWrite: THandle;
    FOutputRead: THandle;
    FReader: TThread;
    FWriter: TThread;
    FClient: TLspClient;
    procedure Write(const ABytes: TBytes);
  public
    /// <summary>Startet AExeName mit AArguments; löst bei Fehlern EOSError aus.</summary>
    constructor Create(const AExeName, AArguments: string);
    destructor Destroy; override;
    function Running: Boolean;
    property Client: TLspClient read FClient;
  end;

implementation

// Eigene Deklaration (Vista und neuer), unabhängig von der Delphi-Version.
function CancelSynchronousIoOf(AThread: THandle): BOOL; stdcall; external kernel32 name 'CancelSynchronousIo';

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

  TWriterThread = class(TThread)
  private
    FHandle: THandle;
    FClient: TLspClient;
    FLock: TObject;
    FQueue: TArray<TBytes>;
    FWake: TEvent;
  protected
    procedure Execute; override;
    procedure TerminatedSet; override;
  public
    constructor Create(AHandle: THandle);
    destructor Destroy; override;
    procedure Add(const ABytes: TBytes);
    property Client: TLspClient read FClient write FClient;
  end;

{ TWriterThread }

constructor TWriterThread.Create(AHandle: THandle);
begin
  FHandle := AHandle;
  FLock := TObject.Create;
  FWake := TEvent.Create(nil, False, False, '');
  inherited Create(False);
end;

destructor TWriterThread.Destroy;
begin
  inherited Destroy;
  FWake.Free;
  FLock.Free;
end;

procedure TWriterThread.TerminatedSet;
begin
  inherited;
  FWake.SetEvent;
end;

procedure TWriterThread.Add(const ABytes: TBytes);
begin
  TMonitor.Enter(FLock);
  try
    FQueue := FQueue + [ABytes];
  finally
    TMonitor.Exit(FLock);
  end;
  FWake.SetEvent;
end;

procedure TWriterThread.Execute;
var
  Items: TArray<TBytes>;
  Bytes: TBytes;
  Written: DWORD;
  Offset: Integer;
begin
  while not Terminated do
  begin
    FWake.WaitFor(INFINITE);
    TMonitor.Enter(FLock);
    try
      Items := FQueue;
      FQueue := nil;
    finally
      TMonitor.Exit(FLock);
    end;
    for Bytes in Items do
    begin
      Offset := 0;
      while Offset < Length(Bytes) do
      begin
        if Terminated or not WriteFile(FHandle, Bytes[Offset], Length(Bytes) - Offset, Written, nil) then
        begin
          // Server nimmt nichts mehr an: Wartende Anfragen sollen nicht bis zum Zeitlimit hängen.
          if not Terminated and (FClient <> nil) then
            FClient.Close;
          Exit;
        end;
        Inc(Offset, Integer(Written));
      end;
    end;
  end;
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
  Security := Default(TSecurityAttributes);
  Security.nLength := SizeOf(Security);
  Security.bInheritHandle := True;
  // Großer Puffer: Ein ganzer Unit-Text passt meist hinein, ohne auf den Server zu warten.
  if not CreatePipe(InputRead, FInputWrite, @Security, 1 shl 20) then
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
  FWriter := TWriterThread.Create(FInputWrite);
  FClient := TLspClient.Create(Write);
  TWriterThread(FWriter).Client := FClient;
  FReader := TReaderThread.Create(FOutputRead, FClient);
end;

destructor TLspServerProcess.Destroy;
begin
  if FClient <> nil then
    FClient.Close;
  // Schreib-Thread beenden; hängt er an einem Server, der nicht liest, den Server beenden.
  if FWriter <> nil then
  begin
    FWriter.Terminate;
    if WaitForSingleObject(FWriter.Handle, 1000) <> WAIT_OBJECT_0 then
    begin
      CancelSynchronousIoOf(FWriter.Handle);
      if (FProcess <> 0) and (WaitForSingleObject(FWriter.Handle, 500) <> WAIT_OBJECT_0) then
        TerminateProcess(FProcess, 1);
    end;
    FWriter.WaitFor;
    FreeAndNil(FWriter);
  end;
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
  inherited;
end;

procedure TLspServerProcess.Write(const ABytes: TBytes);
begin
  TWriterThread(FWriter).Add(ABytes);
end;

function TLspServerProcess.Running: Boolean;
begin
  Result := (FProcess <> 0) and (WaitForSingleObject(FProcess, 0) = WAIT_TIMEOUT) and not FClient.Closed;
end;

end.
