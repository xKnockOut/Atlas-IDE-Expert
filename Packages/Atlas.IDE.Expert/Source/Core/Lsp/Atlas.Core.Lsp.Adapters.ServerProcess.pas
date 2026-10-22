unit Atlas.Core.Lsp.Adapters.ServerProcess;

// Startet Atlas als Kindprozess mit umgeleitetem stdin/stdout und
// verbindet ihn mit einem TLspClient (ADR 0006). Ein Lese-Thread reicht die
// Ausgabe an TLspClient.Receive weiter; endet der Prozess, wird der Client
// geschlossen, mit Exit-Code, Laufzeit und Zeilen auf stderr
// (TLspClient.CloseWith, Bericht H5).
// stderr geht in die Datei server-stderr.log im Protokollordner (anhängen,
// eine Kopfzeile je Start), nicht in eine Pipe, die volllaufen und den Server
// blockieren könnte. Früher ging stderr nach NUL, und was die Laufzeit beim
// Absturz noch schrieb, war verloren. Lässt sich die Datei nicht öffnen,
// bleibt es bei NUL und das Protokoll sagt es einmal.
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
  Atlas.Core.Lsp.Client;

type
  TLspServerProcess = class(TInterfacedObject, IAtlasLspServer)
  public const
    /// <summary>So lange wartet der Lese-Thread nach dem Ende der Ausgabe auf den Exit-Code.</summary>
    ExitWaitMs = 1000;
  private
    FProcess: THandle;
    FInputWrite: THandle;
    FOutputRead: THandle;
    FReader: TThread;
    FWriter: TThread;
    FClient: TLspClient;
    FStarted: UInt64;
    // stderr-Datei und ihre Größe nach der Kopfzeile dieses Starts; '' = NUL.
    FStderrFile: string;
    FStderrStart: Int64;
    procedure Write(const ABytes: TBytes);
    /// <summary>Öffnet server-stderr.log zum Anhängen (vererbbar) und schreibt die Kopfzeile; sonst NUL.</summary>
    function OpenStderr(ASecurity: PSecurityAttributes): THandle;
    /// <summary>Zeilen, die seit dem Start dieses Servers in server-stderr.log kamen (bei mehreren IDEs auch die
    /// der anderen Server).</summary>
    function StderrLines: Integer;
    /// <summary>Exit-Code (bis ExitWaitMs gewartet), Laufzeit und stderr; leer, wenn Atlas schon geschlossen hat.
    /// Aus dem Lese- oder Schreib-Thread, bevor sie den Client schließen.</summary>
    function EndInfo: TLspCloseInfo;
  public
    /// <summary>Startet AExeName mit AArguments; löst bei Fehlern EOSError aus.</summary>
    constructor Create(const AExeName, AArguments: string);
    destructor Destroy; override;
    function Running: Boolean;
    function GetClient: TLspClient;
    property Client: TLspClient read FClient;
  end;

implementation

uses
  System.IOUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Lsp.Crashes;

const
  // FILE_APPEND_DATA: Jedes WriteFile landet am Ende, auch wenn mehrere Server dieselbe Datei offen haben.
  AppendData = $0004;

// Eigene Deklaration (Vista und neuer), unabhängig von der Delphi-Version.
function CancelSynchronousIoOf(AThread: THandle): BOOL; stdcall; external kernel32 name 'CancelSynchronousIo';

type
  TReaderThread = class(TThread)
  private
    FHandle: THandle;
    FClient: TLspClient;
    FOwner: TLspServerProcess;
  protected
    procedure Execute; override;
  public
    constructor Create(AHandle: THandle; AClient: TLspClient; AOwner: TLspServerProcess);
  end;

  TWriterThread = class(TThread)
  private
    FHandle: THandle;
    FClient: TLspClient;
    FOwner: TLspServerProcess;
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
    property Owner: TLspServerProcess read FOwner write FOwner;
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
          if not Terminated and (FClient <> nil) and (FOwner <> nil) then
            FClient.CloseWith(FOwner.EndInfo);
          Exit;
        end;
        Inc(Offset, Integer(Written));
      end;
    end;
  end;
end;

{ TReaderThread }

constructor TReaderThread.Create(AHandle: THandle; AClient: TLspClient; AOwner: TLspServerProcess);
begin
  FHandle := AHandle;
  FClient := AClient;
  FOwner := AOwner;
  inherited Create(False);
end;

procedure TReaderThread.Execute;
var
  Buffer: TBytes;
  Read: DWORD;
begin
  SetLength(Buffer, 65536);
  try
    try
      while not Terminated do
      begin
        if not ReadFile(FHandle, Buffer[0], Length(Buffer), Read, nil) or (Read = 0) then
          Break;
        FClient.Receive(Buffer, Integer(Read));
      end;
    except
      // Kein stilles Ende (#493): protokollieren; die Sitzung gilt dann als beendet.
      on E: Exception do
        TAtlasGuard.Report(TAtlasFeature.Server, E);
    end;
  finally
    // Mit Exit-Code: Der Server hat seine Ausgabe geschlossen, meist weil er endete (H5).
    FClient.CloseWith(FOwner.EndInfo);
  end;
end;

{ TLspServerProcess }

constructor TLspServerProcess.Create(const AExeName, AArguments: string);
var
  Security: TSecurityAttributes;
  InputRead, OutputWrite, ErrorHandle: THandle;
  Startup: TStartupInfo;
  Info: TProcessInformation;
  CommandLine: string;
begin
  inherited Create;
  Security := Default(TSecurityAttributes);
  Security.nLength := SizeOf(Security);
  Security.bInheritHandle := True;
  InputRead := 0;
  OutputWrite := 0;
  ErrorHandle := INVALID_HANDLE_VALUE;
  // Die Enden des Kindprozesses schließt das finally auf jedem Weg, auch wenn die zweite Pipe oder CreateProcess
  // scheitert (Code-Review S-07); die eigenen Enden (FInputWrite, FOutputRead) schließt Destroy.
  try
    // Großer Puffer: Ein ganzer Unit-Text passt meist hinein, ohne auf den Server zu warten.
    if not CreatePipe(InputRead, FInputWrite, @Security, 1 shl 20) then
      RaiseLastOSError;
    if not CreatePipe(FOutputRead, OutputWrite, @Security, 0) then
      RaiseLastOSError;
    // Die eigenen Enden dürfen nicht vererbt werden, sonst endet der Server nie.
    SetHandleInformation(FInputWrite, HANDLE_FLAG_INHERIT, 0);
    SetHandleInformation(FOutputRead, HANDLE_FLAG_INHERIT, 0);
    ErrorHandle := OpenStderr(@Security);
    Startup := Default(TStartupInfo);
    Startup.cb := SizeOf(Startup);
    Startup.dwFlags := STARTF_USESTDHANDLES;
    Startup.hStdInput := InputRead;
    Startup.hStdOutput := OutputWrite;
    Startup.hStdError := ErrorHandle;
    CommandLine := '"' + AExeName + '" ' + AArguments;
    UniqueString(CommandLine);
    if not CreateProcess(nil, PChar(CommandLine), nil, nil, True, CREATE_NO_WINDOW, nil,
      PChar(ExtractFileDir(AExeName)), Startup, Info) then
      RaiseLastOSError;
  finally
    if InputRead <> 0 then
      CloseHandle(InputRead);
    if OutputWrite <> 0 then
      CloseHandle(OutputWrite);
    if ErrorHandle <> INVALID_HANDLE_VALUE then
      CloseHandle(ErrorHandle);
  end;
  CloseHandle(Info.hThread);
  FProcess := Info.hProcess;
  FStarted := TThread.GetTickCount64;
  FWriter := TWriterThread.Create(FInputWrite);
  FClient := TLspClient.Create(Write);
  TWriterThread(FWriter).Client := FClient;
  TWriterThread(FWriter).Owner := Self;
  FReader := TReaderThread.Create(FOutputRead, FClient, Self);
end;

function TLspServerProcess.OpenStderr(ASecurity: PSecurityAttributes): THandle;
var
  Folder, Old: string;
  Header: TBytes;
  Written: DWORD;
begin
  FStderrFile := '';
  FStderrStart := 0;
  Result := INVALID_HANDLE_VALUE;
  try
    Folder := TAtlasGuard.RotatingLog.Folder;
    ForceDirectories(Folder);
    FStderrFile := TAtlasServerExits.StderrFileName(Folder);
    // Zu groß: beiseitelegen. Hält ein anderer Server sie offen, gelingt das wegen FILE_SHARE_DELETE trotzdem.
    if TFile.Exists(FStderrFile) and (TFile.GetSize(FStderrFile) > TAtlasServerExits.StderrMaxBytes) then
    begin
      Old := TAtlasServerExits.StderrOldFileName(Folder);
      MoveFileEx(PChar(FStderrFile), PChar(Old), MOVEFILE_REPLACE_EXISTING);
    end;
    Result := CreateFile(PChar(FStderrFile), AppendData, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
      ASecurity, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
    if Result = INVALID_HANDLE_VALUE then
      RaiseLastOSError;
    Header := TEncoding.UTF8.GetBytes(Format('---- %s Serverstart ----'#13#10,
      [FormatDateTime('yyyy"-"mm"-"dd hh":"nn":"ss', Now)]));
    WriteFile(Result, Header[0], Length(Header), Written, nil);
    FStderrStart := TFile.GetSize(FStderrFile);
  except
    on E: Exception do
    begin
      if Result <> INVALID_HANDLE_VALUE then
        CloseHandle(Result);
      TAtlasGuard.Log('stderr des Servers bleibt bei NUL: ' + TAtlasGuard.SafeMessage(E.Message));
      FStderrFile := '';
      Result := CreateFile('NUL', GENERIC_WRITE, FILE_SHARE_READ or FILE_SHARE_WRITE, ASecurity, OPEN_EXISTING, 0, 0);
    end;
  end;
end;

function TLspServerProcess.StderrLines: Integer;
const
  MaxBytes = 4 * 1024 * 1024;
var
  Stream: TFileStream;
  Bytes: TBytes;
  Count, Index: Integer;
begin
  Result := 0;
  if FStderrFile = '' then
    Exit;
  try
    Stream := TFileStream.Create(FStderrFile, fmOpenRead or fmShareDenyNone);
    try
      if Stream.Size <= FStderrStart then
        Exit;
      Stream.Position := FStderrStart;
      Count := MaxBytes;
      if Stream.Size - FStderrStart < Count then
        Count := Integer(Stream.Size - FStderrStart);
      SetLength(Bytes, Count);
      Stream.ReadBuffer(Bytes[0], Count);
    finally
      Stream.Free;
    end;
    for Index := 0 to Count - 1 do
      if Bytes[Index] = 10 then
        Inc(Result);
    // Letzte Zeile ohne Zeilenende zählt mit.
    if (Count > 0) and (Bytes[Count - 1] <> 10) then
      Inc(Result);
  except
    // Nur eine Zahl fürs Protokoll; ohne Datei bleibt sie 0.
    on Exception do
      Result := 0;
  end;
end;

function TLspServerProcess.EndInfo: TLspCloseInfo;
var
  Code: DWORD;
  WaitMs: Cardinal;
begin
  Result := Default(TLspCloseInfo);
  // Atlas beendet den Server selbst (Destroy schließt den Client vorher): kein Absturz, nichts zu warten.
  if (FClient = nil) or FClient.Closed then
    Exit;
  Result.RuntimeMs := Int64(TThread.GetTickCount64 - FStarted);
  WaitMs := ExitWaitMs;
  if TAtlasShutdown.Signalled then
    WaitMs := 0;
  if (WaitForSingleObject(FProcess, WaitMs) = WAIT_OBJECT_0) and GetExitCodeProcess(FProcess, Code) then
  begin
    Result.ExitKnown := True;
    Result.ExitCode := Code;
  end;
  Result.ErrorLines := StderrLines;
end;

destructor TLspServerProcess.Destroy;
var
  WriterMs, CancelMs, ProcessMs: Cardinal;
begin
  WriterMs := 1000;
  CancelMs := 500;
  ProcessMs := 2000;
  // Beim Entladen bzw. Schließen der IDE (#493): alles zusammen unter TAtlasShutdown.StopMs.
  if TAtlasShutdown.Signalled then
  begin
    WriterMs := 300;
    CancelMs := 150;
    ProcessMs := 400;
  end;
  if FClient <> nil then
    FClient.Close;
  // Schreib-Thread beenden; hängt er an einem Server, der nicht liest, den Server beenden.
  if FWriter <> nil then
  begin
    FWriter.Terminate;
    if WaitForSingleObject(FWriter.Handle, WriterMs) <> WAIT_OBJECT_0 then
    begin
      CancelSynchronousIoOf(FWriter.Handle);
      if (FProcess <> 0) and (WaitForSingleObject(FWriter.Handle, CancelMs) <> WAIT_OBJECT_0) then
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
    if WaitForSingleObject(FProcess, ProcessMs) <> WAIT_OBJECT_0 then
      TerminateProcess(FProcess, 1);
  end;
  if FReader <> nil then
  begin
    FReader.WaitFor;
    FReader.Free;
  end;
  // Erst nach dem Lese-Thread: Der fragt beim Ende den Exit-Code über dieses Handle ab (EndInfo).
  if FProcess <> 0 then
    CloseHandle(FProcess);
  if FOutputRead <> 0 then
    CloseHandle(FOutputRead);
  FClient.Free;
  inherited;
end;

procedure TLspServerProcess.Write(const ABytes: TBytes);
begin
  TWriterThread(FWriter).Add(ABytes);
end;

function TLspServerProcess.GetClient: TLspClient;
begin
  Result := FClient;
end;

function TLspServerProcess.Running: Boolean;
begin
  Result := (FProcess <> 0) and (WaitForSingleObject(FProcess, 0) = WAIT_TIMEOUT) and not FClient.Closed;
end;

end.
