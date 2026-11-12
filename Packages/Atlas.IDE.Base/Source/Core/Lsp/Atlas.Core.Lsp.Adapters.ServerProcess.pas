unit Atlas.Core.Lsp.Adapters.ServerProcess;

// Startet Atlas als Kindprozess mit umgeleitetem stdin/stdout und
// verbindet ihn mit einem TLspClient. Ein Lese-Thread reicht die
// Ausgabe an TLspClient.Receive weiter; endet der Prozess, wird der Client
// geschlossen, mit Exit-Code, Laufzeit und Zeilen auf stderr
// (TLspClient.CloseWith).
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
    cExitWaitMs = 1000;
  private
    FProcess: THandle;
    FInputWrite: THandle;
    FOutputRead: THandle;
    FReader: TThread;
    FWriter: TThread;
    // Schützt FWriter: Der Lese-Thread antwortet über Write noch, während Destroy den Schreib-Thread abbaut.
    FWriterLock: TObject;
    FClient: TLspClient;
    FStarted: UInt64;
    // stderr-Datei und ihre Größe nach der Kopfzeile dieses Starts; '' = NUL.
    FStderrFile: string;
    FStderrStart: Int64;
    procedure Write(const ABytes: TBytes);
    /// <summary>Öffnet server-stderr.log zum Anhängen und schreibt die Kopfzeile; sonst NUL. Nicht vererbbar: Das
    /// macht erst TAtlasProcessLauncher für den Start.</summary>
    function OpenStderr: THandle;
    procedure CreatePipes(var AInputRead, AOutputWrite: THandle);
    procedure StopWriter(AWriterMs, ACancelMs: Cardinal);
    procedure StopProcess(AProcessMs: Cardinal);
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
  Atlas.WinBase.Process,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Lsp.Crashes;

const
  // FILE_APPEND_DATA: Jedes WriteFile landet am Ende, auch wenn mehrere Server dieselbe Datei offen haben.
  cAppendData = $0004;
  // Puffergröße der Pipe zum Server: 1 MiB.
  cPipeBufferBits = 20;

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
    function TakeQueue: TArray<TBytes>;
    function WriteAll(const ABytes: TBytes): Boolean;
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

/// <summary>Holt alle wartenden Nachrichten und leert die Warteschlange.</summary>
function TWriterThread.TakeQueue: TArray<TBytes>;
begin
  TMonitor.Enter(FLock);
  try
    Result := FQueue;
    FQueue := nil;
  finally
    TMonitor.Exit(FLock);
  end;
end;

/// <summary>Schreibt ABytes ganz in die Pipe; False, wenn der Server nichts mehr annimmt oder der Thread
/// endet.</summary>
function TWriterThread.WriteAll(const ABytes: TBytes): Boolean;
var
  mWritten: DWORD;
  mOffset: Integer;
begin
  Result := True;
  mOffset := 0;
  while Result and (mOffset < Length(ABytes)) do
  begin
    Result := not Terminated and WriteFile(FHandle, ABytes[mOffset], Length(ABytes) - mOffset, mWritten, nil);
    if Result then
    begin
      Inc(mOffset, Integer(mWritten));
    end;
  end;
  // Server nimmt nichts mehr an: Wartende Anfragen sollen nicht bis zum Zeitlimit hängen.
  if not Result and not Terminated and (FClient <> nil) and (FOwner <> nil) then
  begin
    FClient.CloseWith(FOwner.EndInfo);
  end;
end;

procedure TWriterThread.Execute;
var
  mBytes: TBytes;
begin
  while not Terminated do
  begin
    FWake.WaitFor(INFINITE);
    for mBytes in TakeQueue do
    begin
      if not WriteAll(mBytes) then
      begin
        Exit;
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
  mBuffer: TBytes;
  mRead: DWORD;
begin
  SetLength(mBuffer, 65536);
  try
    try
      while not Terminated do
      begin
        if not ReadFile(FHandle, mBuffer[0], Length(mBuffer), mRead, nil) or (mRead = 0) then
        begin
          Break;
        end;
        FClient.Receive(mBuffer, Integer(mRead));
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

/// <summary>Startet AExeName mit den Kindenden der Pipes und ohne Fenster; nur diese erbt der Server (R-101).
/// Löst bei einem Fehler EOSError aus.</summary>
function LaunchProcess(const AExeName, AArguments: string; AInput, AOutput, AError: THandle): TProcessInformation;
begin
  if not TAtlasProcessLauncher.Launch(TAtlasProcessLaunch.Create('', '"' + AExeName + '" ' + AArguments,
    ExtractFileDir(AExeName), AInput, AOutput, AError), Result) then
  begin
    RaiseLastOSError;
  end;
end;

/// <summary>Schließt AHandle, wenn es gesetzt ist (0 bzw. INVALID_HANDLE_VALUE bleiben unberührt).</summary>
procedure CloseIfOpen(AHandle: THandle);
begin
  if (AHandle <> 0) and (AHandle <> INVALID_HANDLE_VALUE) then
  begin
    CloseHandle(AHandle);
  end;
end;

constructor TLspServerProcess.Create(const AExeName, AArguments: string);
var
  mInputRead, mOutputWrite, mErrorHandle: THandle;
  mInfo: TProcessInformation;
begin
  inherited Create;
  FWriterLock := TObject.Create;
  mInputRead := 0;
  mOutputWrite := 0;
  mErrorHandle := INVALID_HANDLE_VALUE;
  // Die Enden des Kindprozesses schließt das finally auf jedem Weg, auch wenn die zweite Pipe oder CreateProcess
  // scheitert; die eigenen Enden (FInputWrite, FOutputRead) schließt Destroy.
  try
    CreatePipes(mInputRead, mOutputWrite);
    mErrorHandle := OpenStderr;
    mInfo := LaunchProcess(AExeName, AArguments, mInputRead, mOutputWrite, mErrorHandle);
  finally
    CloseIfOpen(mInputRead);
    CloseIfOpen(mOutputWrite);
    CloseIfOpen(mErrorHandle);
  end;
  CloseHandle(mInfo.hThread);
  FProcess := mInfo.hProcess;
  FStarted := TThread.GetTickCount64;
  FWriter := TWriterThread.Create(FInputWrite);
  FClient := TLspClient.Create(Write);
  TWriterThread(FWriter).Client := FClient;
  TWriterThread(FWriter).Owner := Self;
  FReader := TReaderThread.Create(FOutputRead, FClient, Self);
end;

procedure TLspServerProcess.CreatePipes(var AInputRead, AOutputWrite: THandle);
begin
  // Alle Enden nicht vererbbar; die Kindenden vererbt TAtlasProcessLauncher gezielt (R-101).
  // Großer Puffer: Ein ganzer Unit-Text passt meist hinein, ohne auf den Server zu warten.
  if not CreatePipe(AInputRead, FInputWrite, nil, 1 shl cPipeBufferBits) then
  begin
    RaiseLastOSError;
  end;
  if not CreatePipe(FOutputRead, AOutputWrite, nil, 0) then
  begin
    RaiseLastOSError;
  end;
end;

function TLspServerProcess.OpenStderr: THandle;
var
  mFolder, mOld: string;
  mHeader: TBytes;
  mWritten: DWORD;
begin
  FStderrFile := '';
  FStderrStart := 0;
  Result := INVALID_HANDLE_VALUE;
  try
    mFolder := TAtlasGuard.RotatingLog.Folder;
    ForceDirectories(mFolder);
    FStderrFile := TAtlasServerExits.StderrFileName(mFolder);
    // Zu groß: beiseitelegen. Hält ein anderer Server sie offen, gelingt das wegen FILE_SHARE_DELETE trotzdem.
    if TFile.Exists(FStderrFile) and (TFile.GetSize(FStderrFile) > TAtlasServerExits.cStderrMaxBytes) then
    begin
      mOld := TAtlasServerExits.StderrOldFileName(mFolder);
      MoveFileEx(PChar(FStderrFile), PChar(mOld), MOVEFILE_REPLACE_EXISTING);
    end;
    Result := CreateFile(PChar(FStderrFile), cAppendData, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
      nil, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
    if Result = INVALID_HANDLE_VALUE then
    begin
      RaiseLastOSError;
    end;
    mHeader := TEncoding.UTF8.GetBytes(Format('---- %s Serverstart ----'#13#10,
      [FormatDateTime('yyyy"-"mm"-"dd hh":"nn":"ss', Now)]));
    WriteFile(Result, mHeader[0], Length(mHeader), mWritten, nil);
    FStderrStart := TFile.GetSize(FStderrFile);
  except
    on E: Exception do
    begin
      if Result <> INVALID_HANDLE_VALUE then
      begin
        CloseHandle(Result);
      end;
      TAtlasGuard.Log('stderr des Servers bleibt bei NUL: ' + TAtlasGuard.MessageText(E.Message));
      FStderrFile := '';
      Result := CreateFile('NUL', GENERIC_WRITE, FILE_SHARE_READ or FILE_SHARE_WRITE, nil, OPEN_EXISTING, 0, 0);
    end;
  end;
end;

function TLspServerProcess.StderrLines: Integer;
const
  cMaxBytes = 4 * 1024 * 1024;
var
  mStream: TFileStream;
  mBytes: TBytes;
  mCount, mIndex: Integer;
begin
  Result := 0;
  if FStderrFile = '' then
  begin
    Exit;
  end;
  try
    mStream := TFileStream.Create(FStderrFile, fmOpenRead or fmShareDenyNone);
    try
      if mStream.Size <= FStderrStart then
      begin
        Exit;
      end;
      mStream.Position := FStderrStart;
      mCount := cMaxBytes;
      if mStream.Size - FStderrStart < mCount then
      begin
        mCount := Integer(mStream.Size - FStderrStart);
      end;
      SetLength(mBytes, mCount);
      mStream.ReadBuffer(mBytes[0], mCount);
    finally
      mStream.Free;
    end;
    for mIndex := 0 to mCount - 1 do
    begin
      if mBytes[mIndex] = 10 then
      begin
        Inc(Result);
      end;
    end;
    // Letzte Zeile ohne Zeilenende zählt mit.
    if (mCount > 0) and (mBytes[mCount - 1] <> 10) then
    begin
      Inc(Result);
    end;
  except
    // Nur eine Zahl fürs Protokoll; ohne Datei bleibt sie 0.
    on Exception do
      Result := 0;
  end;
end;

function TLspServerProcess.EndInfo: TLspCloseInfo;
var
  mCode: DWORD;
  mWaitMs: Cardinal;
begin
  Result := Default(TLspCloseInfo);
  // Atlas beendet den Server selbst (Destroy schließt den Client vorher): kein Absturz, nichts zu warten.
  if (FClient = nil) or FClient.Closed then
  begin
    Exit;
  end;
  Result.RuntimeMs := Int64(TThread.GetTickCount64 - FStarted);
  mWaitMs := cExitWaitMs;
  if TAtlasShutdown.Signalled then
  begin
    mWaitMs := 0;
  end;
  if (WaitForSingleObject(FProcess, mWaitMs) = WAIT_OBJECT_0) and GetExitCodeProcess(FProcess, mCode) then
  begin
    Result.ExitKnown := True;
    Result.ExitCode := mCode;
  end;
  Result.ErrorLines := StderrLines;
end;

procedure TLspServerProcess.StopWriter(AWriterMs, ACancelMs: Cardinal);
var
  mWriter: TThread;
begin
  if FWriter = nil then
  begin
    Exit;
  end;
  FWriter.Terminate;
  if WaitForSingleObject(FWriter.Handle, AWriterMs) <> WAIT_OBJECT_0 then
  begin
    CancelSynchronousIoOf(FWriter.Handle);
    if (FProcess <> 0) and (WaitForSingleObject(FWriter.Handle, ACancelMs) <> WAIT_OBJECT_0) then
    begin
      TerminateProcess(FProcess, 1);
    end;
  end;
  FWriter.WaitFor;
  // Erst aus dem Zugriff nehmen, dann freigeben: Antworten des Lese-Threads fallen danach weg.
  System.TMonitor.Enter(FWriterLock);
  try
    mWriter := FWriter;
    FWriter := nil;
  finally
    System.TMonitor.Exit(FWriterLock);
  end;
  mWriter.Free;
end;

procedure TLspServerProcess.StopProcess(AProcessMs: Cardinal);
begin
  // stdin schließen: Der Server sieht das Ende der Eingabe und beendet sich.
  CloseIfOpen(FInputWrite);
  if (FProcess <> 0) and (WaitForSingleObject(FProcess, AProcessMs) <> WAIT_OBJECT_0) then
  begin
    TerminateProcess(FProcess, 1);
  end;
  if FReader <> nil then
  begin
    FReader.WaitFor;
    FReader.Free;
  end;
  // Erst nach dem Lese-Thread: Der fragt beim Ende den Exit-Code über dieses Handle ab (EndInfo).
  CloseIfOpen(FProcess);
  CloseIfOpen(FOutputRead);
end;

destructor TLspServerProcess.Destroy;
begin
  if FClient <> nil then
  begin
    FClient.Close;
  end;
  // Schreib-Thread beenden; hängt er an einem Server, der nicht liest, den Server beenden.
  // Beim Entladen bzw. Schließen der IDE (#493): alles zusammen unter TAtlasShutdown.cStopMs.
  if TAtlasShutdown.Signalled then
  begin
    StopWriter(300, 150);
    StopProcess(400);
  end
  else
  begin
    StopWriter(1000, 500);
    StopProcess(2000);
  end;
  FClient.Free;
  FWriterLock.Free;
  inherited;
end;

procedure TLspServerProcess.Write(const ABytes: TBytes);
begin
  System.TMonitor.Enter(FWriterLock);
  try
    // nil: Destroy hat den Schreib-Thread schon abgebaut (Antwort des Lese-Threads beim Beenden).
    if FWriter <> nil then
    begin
      TWriterThread(FWriter).Add(ABytes);
    end;
  finally
    System.TMonitor.Exit(FWriterLock);
  end;
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
