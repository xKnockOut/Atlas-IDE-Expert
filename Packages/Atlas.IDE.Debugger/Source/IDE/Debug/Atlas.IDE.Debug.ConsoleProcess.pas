unit Atlas.IDE.Debug.ConsoleProcess;

// Konsolenprogramm mit umgeleiteter Ein- und Ausgabe (#581), Adapter zu Windows:
// - Start legt drei Pipes an (stdin, stdout, stderr; getrennt, damit stderr
//   seine eigene Farbe bekommt) und startet über TAtlasProcessLauncher, der nur
//   diese drei Handles vererbt. CREATE_NO_WINDOW: kein leeres Konsolenfenster;
//   Writeln und Readln eines Delphi-Programms gehen über die Standard-Handles.
//   Mit ASuspended (Start mit Debugger) steht der erste Thread, bis Resume
//   ihn freigibt; dazwischen hängt sich der Debugger der IDE an.
// - Ein Lesethread holt im Takt von cSliceMs alles Verfügbare aus stdout und
//   stderr (PeekNamedPipe, blockiert nie) und legt es als Stücke ab. Endet der
//   Prozess, liest er den Rest und merkt den Exit-Code. Der Hauptthread holt
//   die Stücke mit TakeChunks (Zeitgeber der IDE-Schicht); nichts reiht sich
//   in den Hauptthread ein.
// - Send schreibt eine Zeile (mit CRLF) in der Codepage des Programms nach
//   stdin; CloseInput schließt stdin (Ende der Datei für Readln).
// - Free beendet den Lesethread und schließt die Handles, beendet aber nicht
//   das Programm (läuft es im Debugger, gehört es der IDE).

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections,
  Atlas.Core.Debug.ConsoleCapture;

type
  /// <summary>Gelesene Bytes aus stdout (Output) bzw. stderr (Error).</summary>
  TAtlasConsoleChunk = record
    Stream: TAtlasConsoleStream;
    Data: TBytes;
  end;

  /// <summary>Was gestartet wird; WorkingDir '' = Ordner der EXE, Environment '' = Umgebung der IDE.</summary>
  TAtlasConsoleStart = record
    Exe: string;
    Arguments: string;
    WorkingDir: string;
    /// <summary>Umgebungsblock (Name=Wert#0…#0#0) oder ''.</summary>
    Environment: string;
    /// <summary>Erster Thread angehalten, bis Resume (zum Anhängen des Debuggers).</summary>
    Suspended: Boolean;
  end;

  TAtlasIdeConsoleProcess = class
  public const
    cSliceMs = 10;
    cChunkBytes = 16384;
    cPipeBytes = 65536;
  private type
    TReader = class(TThread)
    private
      FOwner: TAtlasIdeConsoleProcess;
    protected
      procedure Execute; override;
    public
      constructor Create(AOwner: TAtlasIdeConsoleProcess);
    end;
  private
    FCodePage: Integer;
    FProcess: THandle;
    FThread: THandle;
    FPid: Cardinal;
    FInput: THandle;
    FOutput: THandle;
    FError: THandle;
    FLock: TCriticalSection;
    FChunks: TList<TAtlasConsoleChunk>;
    FEnded: Boolean;
    FExitCode: Cardinal;
    FReader: TReader;
    /// <summary>Alles Verfügbare aus AHandle lesen; True, wenn etwas kam.</summary>
    function Drain(AHandle: THandle; AStream: TAtlasConsoleStream; var ABuffer: TBytes): Boolean;
    /// <summary>Im Lesethread AReader bis zum Ende des Prozesses bzw. von AReader.</summary>
    procedure Read(AReader: TReader);
    procedure MarkEnded;
    function OpenPipes(out AChildInput, AChildOutput, AChildError: THandle): Boolean;
  public
    /// <summary>ACodePage: Codepage, in der Send schreibt (die des Programms ohne Konsole: GetACP).</summary>
    constructor Create(ACodePage: Integer);
    destructor Destroy; override;
    /// <summary>Starten; False mit dem Windows-Fehler in AError.</summary>
    function Start(const AStart: TAtlasConsoleStart; out AError: Cardinal): Boolean;
    /// <summary>Angehaltenen ersten Thread fortsetzen (nur nach Start mit Suspended, einmal).</summary>
    function Resume: Boolean;
    /// <summary>Bisher gelesene Stücke in Reihenfolge; danach ist die Ablage leer.</summary>
    function TakeChunks: TArray<TAtlasConsoleChunk>;
    /// <summary>Prozess beendet und alles gelesen; AExitCode wie GetExitCodeProcess.</summary>
    function Ended(out AExitCode: Cardinal): Boolean;
    /// <summary>Eine Zeile an stdin; False, wenn stdin zu ist oder das Programm nicht mehr liest.</summary>
    function Send(const AText: string): Boolean;
    procedure CloseInput;
    /// <summary>Programm hart beenden (TerminateProcess).</summary>
    function Terminate: Boolean;
    property Pid: Cardinal read FPid;
    property ProcessHandle: THandle read FProcess;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.WinBase.Process,
  Atlas.Plugin.Diagnostics.Guard;

const
  cStartFailedCode = $FFFFFFFF;
  cResumeFailed = $FFFFFFFF;

/// <summary>AHandle schließen, falls offen, und auf 0 setzen.</summary>
procedure CloseOpen(var AHandle: THandle);
begin
  if AHandle <> 0 then
  begin
    CloseHandle(AHandle);
    AHandle := 0;
  end;
end;

{ TAtlasIdeConsoleProcess.TReader }

constructor TAtlasIdeConsoleProcess.TReader.Create(AOwner: TAtlasIdeConsoleProcess);
begin
  FOwner := AOwner;
  inherited Create(False);
end;

procedure TAtlasIdeConsoleProcess.TReader.Execute;
begin
  // Ein Fehler beim Lesen wird protokolliert; das Fenster zeigt dann nur bis dahin.
  try
    FOwner.Read(Self);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

{ TAtlasIdeConsoleProcess }

constructor TAtlasIdeConsoleProcess.Create(ACodePage: Integer);
begin
  inherited Create;
  FCodePage := ACodePage;
  FLock := TCriticalSection.Create;
  FChunks := TList<TAtlasConsoleChunk>.Create;
end;

destructor TAtlasIdeConsoleProcess.Destroy;
begin
  if FReader <> nil then
  begin
    FReader.Terminate;
    FReader.WaitFor;
    FreeAndNil(FReader);
  end;
  CloseOpen(FThread);
  CloseOpen(FProcess);
  CloseOpen(FInput);
  CloseOpen(FOutput);
  CloseOpen(FError);
  FChunks.Free;
  FLock.Free;
  inherited Destroy;
end;

function TAtlasIdeConsoleProcess.OpenPipes(out AChildInput, AChildOutput, AChildError: THandle): Boolean;
begin
  // Nicht vererbbar anlegen: TAtlasProcessLauncher macht nur die Enden des Kindes kurz vererbbar.
  AChildInput := 0;
  AChildOutput := 0;
  AChildError := 0;
  Result := CreatePipe(AChildInput, FInput, nil, cPipeBytes) and CreatePipe(FOutput, AChildOutput, nil, cPipeBytes)
    and CreatePipe(FError, AChildError, nil, cPipeBytes);
end;

function TAtlasIdeConsoleProcess.Start(const AStart: TAtlasConsoleStart; out AError: Cardinal): Boolean;
var
  mLaunch: TAtlasProcessLaunch;
  mInfo: TProcessInformation;
  mChildInput, mChildOutput, mChildError: THandle;
begin
  AError := 0;
  Result := OpenPipes(mChildInput, mChildOutput, mChildError);
  if Result then
  begin
    mLaunch := TAtlasProcessLaunch.Create(AStart.Exe, '"' + AStart.Exe + '" ' + AStart.Arguments, AStart.WorkingDir,
      mChildInput, mChildOutput, mChildError);
    if mLaunch.WorkingDir = '' then
    begin
      mLaunch.WorkingDir := ExtractFileDir(AStart.Exe);
    end;
    mLaunch.Environment := AStart.Environment;
    if AStart.Suspended then
    begin
      mLaunch.Flags := mLaunch.Flags or CREATE_SUSPENDED;
    end;
    Result := TAtlasProcessLauncher.Launch(mLaunch, mInfo);
  end;
  if not Result then
  begin
    AError := GetLastError;
    if AError = 0 then
    begin
      AError := cStartFailedCode;
    end;
  end;
  // Die Enden des Kindes gehören jetzt ihm; offen im Elternprozess kämen Ende der Datei und Leseende nie an.
  CloseOpen(mChildInput);
  CloseOpen(mChildOutput);
  CloseOpen(mChildError);
  if not Result then
  begin
    Exit;
  end;
  FProcess := mInfo.hProcess;
  FPid := mInfo.dwProcessId;
  FThread := mInfo.hThread;
  if not AStart.Suspended then
  begin
    CloseOpen(FThread);
  end;
  FReader := TReader.Create(Self);
end;

function TAtlasIdeConsoleProcess.Resume: Boolean;
begin
  Result := (FThread <> 0) and (ResumeThread(FThread) <> cResumeFailed);
  CloseOpen(FThread);
end;

function TAtlasIdeConsoleProcess.Drain(AHandle: THandle; AStream: TAtlasConsoleStream; var ABuffer: TBytes): Boolean;
var
  mAvailable, mRead: DWORD;
  mChunk: TAtlasConsoleChunk;
begin
  Result := False;
  while PeekNamedPipe(AHandle, nil, 0, nil, @mAvailable, nil) and (mAvailable > 0) do
  begin
    if mAvailable > DWORD(Length(ABuffer)) then
    begin
      mAvailable := Length(ABuffer);
    end;
    if not ReadFile(AHandle, ABuffer[0], mAvailable, mRead, nil) or (mRead = 0) then
    begin
      Exit;
    end;
    mChunk.Stream := AStream;
    mChunk.Data := Copy(ABuffer, 0, mRead);
    FLock.Enter;
    try
      FChunks.Add(mChunk);
    finally
      FLock.Leave;
    end;
    Result := True;
  end;
end;

procedure TAtlasIdeConsoleProcess.Read(AReader: TReader);
var
  mBuffer: TBytes;
  mOutput, mError: Boolean;
begin
  SetLength(mBuffer, cChunkBytes);
  // AReader statt FReader: Der Thread läuft schon, bevor Start FReader setzt.
  while not AReader.Terminated do
  begin
    Drain(FOutput, TAtlasConsoleStream.Output, mBuffer);
    Drain(FError, TAtlasConsoleStream.Error, mBuffer);
    if WaitForSingleObject(FProcess, cSliceMs) <> WAIT_OBJECT_0 then
    begin
      Continue;
    end;
    // Beendet: den Rest aus beiden Pipes, bis keine mehr etwas hat.
    repeat
      mOutput := Drain(FOutput, TAtlasConsoleStream.Output, mBuffer);
      mError := Drain(FError, TAtlasConsoleStream.Error, mBuffer);
    until not (mOutput or mError);
    MarkEnded;
    Exit;
  end;
end;

procedure TAtlasIdeConsoleProcess.MarkEnded;
var
  mCode: DWORD;
begin
  if not GetExitCodeProcess(FProcess, mCode) then
  begin
    mCode := cStartFailedCode;
  end;
  FLock.Enter;
  try
    FExitCode := mCode;
    FEnded := True;
  finally
    FLock.Leave;
  end;
end;

function TAtlasIdeConsoleProcess.TakeChunks: TArray<TAtlasConsoleChunk>;
begin
  FLock.Enter;
  try
    Result := FChunks.ToArray;
    FChunks.Clear;
  finally
    FLock.Leave;
  end;
end;

function TAtlasIdeConsoleProcess.Ended(out AExitCode: Cardinal): Boolean;
begin
  FLock.Enter;
  try
    // Erst wenn auch die letzten Stücke abgeholt sind, gilt der Lauf als zu Ende.
    Result := FEnded and (FChunks.Count = 0);
    AExitCode := FExitCode;
  finally
    FLock.Leave;
  end;
end;

function TAtlasIdeConsoleProcess.Send(const AText: string): Boolean;
var
  mEncoding: TEncoding;
  mBytes: TBytes;
  mWritten: DWORD;
begin
  Result := False;
  if FInput = 0 then
  begin
    Exit;
  end;
  mEncoding := TEncoding.GetEncoding(FCodePage);
  try
    mBytes := mEncoding.GetBytes(AText + #13#10);
  finally
    mEncoding.Free;
  end;
  Result := WriteFile(FInput, mBytes[0], Length(mBytes), mWritten, nil) and (Integer(mWritten) = Length(mBytes));
end;

procedure TAtlasIdeConsoleProcess.CloseInput;
begin
  CloseOpen(FInput);
end;

function TAtlasIdeConsoleProcess.Terminate: Boolean;
begin
  Result := (FProcess <> 0) and TerminateProcess(FProcess, 1);
end;

end.
