unit Shell.Platform.VcsRunner;

// Prozessläufer für git und svn unter Linux (#1109): Gegenstück zu
// Atlas.Core.Vcs.Adapters.ProcessRunner, das Windows-Pipes nutzt und im
// Windows-Bau bleibt. Gleiches Verhalten: stdout und stderr getrennt, im Takt
// von SliceMs gelesen, damit keine volle Pipe den Prozess anhält; Zeitlimit und
// Abbruch beenden den Prozess; stdin ist leer, git und svn fragen nie nach
// (dazu GIT_TERMINAL_PROMPT=0 und GCM_INTERACTIVE=never in der Umgebung, #1287).
// Nur im Linux-Bau (Shell.Platform), deshalb nicht in AtlasServer.dproj.

interface

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract;

type
  TLinuxVcsRunner = class(TInterfacedObject, IAtlasVcsRunner)
  public const
    /// <summary>Mehr Ausgabe gilt als Fehler (Failed), wie im Windows-Läufer.</summary>
    MaxOutputBytes = 64 * 1024 * 1024;
  private
    FAllowMainThread: Boolean;
    FCancelled: TFunc<Boolean>;
    function IsCancelled: Boolean;
    /// <summary>Ok, wenn der Lauf beginnen darf; sonst warum nicht.</summary>
    function StartOutcome(const AExecutable: string): TAtlasVcsOutcome;
  public
    /// <summary>AAllowMainThread: Hauptthread erlauben (Kommandozeile). ACancelled: zusätzlicher Abbruch; nil =
    /// keiner.</summary>
    constructor Create(AAllowMainThread: Boolean; const ACancelled: TFunc<Boolean>);
    function Run(const AExecutable: string; const AArguments: TArray<string>; const AWorkingDir: string;
      ATimeoutMs: Cardinal): TAtlasVcsRunResult;
  end;

implementation

uses
  System.Classes,
  Pipes,
  Process,
  Atlas.Core.Vcs.ServerAccess;

const
  SliceMs = 10;
  MaxErrorBytes = 4096;

/// <summary>Liest, was im Stream bereitliegt, ohne zu blockieren; über ALimit wird verworfen.</summary>
procedure Drain(AStream: TInputPipeStream; var ABuffer: TBytes; var ACount: Integer; ALimit: Integer);
var
  Chunk: array[0..16383] of Byte;
  Available, BytesRead: Integer;
begin
  while True do
  begin
    Available := AStream.NumBytesAvailable;
    if Available <= 0 then
    begin
      Exit;
    end;
    if Available > SizeOf(Chunk) then
    begin
      Available := SizeOf(Chunk);
    end;
    BytesRead := AStream.Read(Chunk, Available);
    if BytesRead <= 0 then
    begin
      Exit;
    end;
    if ACount < ALimit then
    begin
      if ACount + BytesRead > Length(ABuffer) then
      begin
        SetLength(ABuffer, (ACount + BytesRead) * 2);
      end;
      Move(Chunk[0], ABuffer[ACount], BytesRead);
      Inc(ACount, BytesRead);
    end;
  end;
end;

type
  /// <summary>Gelesene Ausgabe eines Laufs: stdout bis MaxOutputBytes + 1, stderr bis MaxErrorBytes.</summary>
  TCapturedOutput = record
    Output: TBytes;
    Errors: TBytes;
    OutputCount: Integer;
    ErrorCount: Integer;
    procedure DrainFrom(AChild: TProcess);
  end;

procedure TCapturedOutput.DrainFrom(AChild: TProcess);
begin
  Drain(AChild.Output, Output, OutputCount, TLinuxVcsRunner.MaxOutputBytes + 1);
  Drain(AChild.Stderr, Errors, ErrorCount, MaxErrorBytes);
end;

/// <summary>Programm, Argumente, Ordner und eine eigene Umgebung ohne Rückfrage nach Zugangsdaten.</summary>
procedure Configure(AChild: TProcess; const AExecutable: string; const AArguments: TArray<string>;
  const AWorkingDir: string);
var
  mArgument: string;
  mVariables: TArray<string>;
  mIndex: Integer;
begin
  AChild.Executable := AExecutable;
  for mArgument in AArguments do
  begin
    AChild.Parameters.Add(mArgument);
  end;
  if AWorkingDir <> '' then
  begin
    AChild.CurrentDirectory := AWorkingDir;
  end;
  mVariables := nil;
  for mIndex := 1 to GetEnvironmentVariableCount do
  begin
    mVariables := mVariables + [GetEnvironmentString(mIndex)];
  end;
  for mArgument in TAtlasVcsServerAccess.NoPromptEnvironment(mVariables) do
  begin
    AChild.Environment.Add(mArgument);
  end;
  AChild.Options := [poUsePipes, poNoConsole];
end;

function ResultOf(AChild: TProcess; AOutcome: TAtlasVcsOutcome; const ACaptured: TCapturedOutput): TAtlasVcsRunResult;
begin
  if (AOutcome = TAtlasVcsOutcome.Ok) and (ACaptured.OutputCount > TLinuxVcsRunner.MaxOutputBytes) then
  begin
    AOutcome := TAtlasVcsOutcome.Failed;
  end;
  Result := TAtlasVcsRunResult.Make(AOutcome, AChild.ExitCode, nil);
  if AOutcome = TAtlasVcsOutcome.Ok then
  begin
    Result.Output := Copy(ACaptured.Output, 0, ACaptured.OutputCount);
  end;
  if ACaptured.ErrorCount > 0 then
  begin
    Result.ErrorText := Trim(TEncoding.UTF8.GetString(ACaptured.Errors, 0, ACaptured.ErrorCount));
  end;
end;

{ TLinuxVcsRunner }

constructor TLinuxVcsRunner.Create(AAllowMainThread: Boolean; const ACancelled: TFunc<Boolean>);
begin
  inherited Create;
  FAllowMainThread := AAllowMainThread;
  FCancelled := ACancelled;
end;

function TLinuxVcsRunner.IsCancelled: Boolean;
begin
  Result := not TThread.CurrentThread.ExternalThread and TThread.CheckTerminated;
  if not Result and Assigned(FCancelled) then
  begin
    Result := FCancelled();
  end;
end;

function TLinuxVcsRunner.StartOutcome(const AExecutable: string): TAtlasVcsOutcome;
begin
  Result := TAtlasVcsOutcome.Ok;
  if not FAllowMainThread and (TThread.CurrentThread.ThreadID = MainThreadID) then
  begin
    Result := TAtlasVcsOutcome.MainThread;
  end
  else if (AExecutable = '') or not FileExists(AExecutable) then
  begin
    Result := TAtlasVcsOutcome.ToolMissing;
  end
  else if IsCancelled then
  begin
    Result := TAtlasVcsOutcome.Cancelled;
  end;
end;

/// <summary>Liest bis zum Ende des Prozesses; beendet ihn bei Abbruch und Zeitablauf.</summary>
function Watch(ARunner: TLinuxVcsRunner; AChild: TProcess; ATimeoutMs: Cardinal;
  var ACaptured: TCapturedOutput): TAtlasVcsOutcome;
var
  mDeadline: UInt64;
begin
  mDeadline := TThread.GetTickCount64 + ATimeoutMs;
  Result := TAtlasVcsOutcome.Ok;
  while AChild.Running do
  begin
    ACaptured.DrainFrom(AChild);
    if ARunner.IsCancelled then
    begin
      Result := TAtlasVcsOutcome.Cancelled;
    end
    else if TThread.GetTickCount64 >= mDeadline then
    begin
      Result := TAtlasVcsOutcome.TimedOut;
    end;
    if Result <> TAtlasVcsOutcome.Ok then
    begin
      AChild.Terminate(1);
      Break;
    end;
    Sleep(SliceMs);
  end;
  // Rest nach dem Ende.
  ACaptured.DrainFrom(AChild);
  AChild.WaitOnExit;
end;

function TLinuxVcsRunner.Run(const AExecutable: string; const AArguments: TArray<string>;
  const AWorkingDir: string; ATimeoutMs: Cardinal): TAtlasVcsRunResult;
var
  mChild: TProcess;
  mCaptured: TCapturedOutput;
  mOutcome: TAtlasVcsOutcome;
begin
  mOutcome := StartOutcome(AExecutable);
  if mOutcome <> TAtlasVcsOutcome.Ok then
  begin
    Exit(TAtlasVcsRunResult.Make(mOutcome, -1, nil));
  end;
  mChild := TProcess.Create(nil);
  try
    Configure(mChild, AExecutable, AArguments, AWorkingDir);
    try
      mChild.Execute;
    except
      on EProcess do
        // Programm verschwunden oder nicht ausführbar: wie nicht installiert.
        Exit(TAtlasVcsRunResult.Make(TAtlasVcsOutcome.ToolMissing, -1, nil));
    end;
    mChild.CloseInput;
    mCaptured := Default(TCapturedOutput);
    mOutcome := Watch(Self, mChild, ATimeoutMs, mCaptured);
    Result := ResultOf(mChild, mOutcome, mCaptured);
  finally
    mChild.Free;
  end;
end;

end.
