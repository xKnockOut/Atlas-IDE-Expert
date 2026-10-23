unit Shell.Platform.VcsRunner;

// Prozessläufer für git und svn unter Linux (#1109): Gegenstück zu
// Atlas.Core.Vcs.Adapters.ProcessRunner, das Windows-Pipes nutzt und im
// Windows-Bau bleibt. Gleiches Verhalten: stdout und stderr getrennt, im Takt
// von SliceMs gelesen, damit keine volle Pipe den Prozess anhält; Zeitlimit und
// Abbruch beenden den Prozess; stdin ist leer, git und svn fragen nie nach.
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
  Process;

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
      Exit;
    if Available > SizeOf(Chunk) then
      Available := SizeOf(Chunk);
    BytesRead := AStream.Read(Chunk, Available);
    if BytesRead <= 0 then
      Exit;
    if ACount < ALimit then
    begin
      if ACount + BytesRead > Length(ABuffer) then
        SetLength(ABuffer, (ACount + BytesRead) * 2);
      Move(Chunk[0], ABuffer[ACount], BytesRead);
      Inc(ACount, BytesRead);
    end;
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
    Result := FCancelled();
end;

function TLinuxVcsRunner.Run(const AExecutable: string; const AArguments: TArray<string>;
  const AWorkingDir: string; ATimeoutMs: Cardinal): TAtlasVcsRunResult;
var
  Child: TProcess;
  Argument: string;
  Output, Errors: TBytes;
  OutputCount, ErrorCount: Integer;
  Deadline: UInt64;
  Outcome: TAtlasVcsOutcome;
begin
  if not FAllowMainThread and (TThread.CurrentThread.ThreadID = MainThreadID) then
    Exit(TAtlasVcsRunResult.Make(TAtlasVcsOutcome.MainThread, -1, nil));
  if (AExecutable = '') or not FileExists(AExecutable) then
    Exit(TAtlasVcsRunResult.Make(TAtlasVcsOutcome.ToolMissing, -1, nil));
  if IsCancelled then
    Exit(TAtlasVcsRunResult.Make(TAtlasVcsOutcome.Cancelled, -1, nil));
  Child := TProcess.Create(nil);
  try
    Child.Executable := AExecutable;
    for Argument in AArguments do
      Child.Parameters.Add(Argument);
    if AWorkingDir <> '' then
      Child.CurrentDirectory := AWorkingDir;
    Child.Options := [poUsePipes, poNoConsole];
    try
      Child.Execute;
    except
      on EProcess do
        // Programm verschwunden oder nicht ausführbar: wie nicht installiert.
        Exit(TAtlasVcsRunResult.Make(TAtlasVcsOutcome.ToolMissing, -1, nil));
    end;
    Child.CloseInput;
    Output := nil;
    Errors := nil;
    OutputCount := 0;
    ErrorCount := 0;
    Deadline := TThread.GetTickCount64 + ATimeoutMs;
    Outcome := TAtlasVcsOutcome.Ok;
    while Child.Running do
    begin
      Drain(Child.Output, Output, OutputCount, MaxOutputBytes + 1);
      Drain(Child.Stderr, Errors, ErrorCount, MaxErrorBytes);
      if IsCancelled then
        Outcome := TAtlasVcsOutcome.Cancelled
      else if TThread.GetTickCount64 >= Deadline then
        Outcome := TAtlasVcsOutcome.TimedOut;
      if Outcome <> TAtlasVcsOutcome.Ok then
      begin
        Child.Terminate(1);
        Break;
      end;
      Sleep(SliceMs);
    end;
    // Rest nach dem Ende.
    Drain(Child.Output, Output, OutputCount, MaxOutputBytes + 1);
    Drain(Child.Stderr, Errors, ErrorCount, MaxErrorBytes);
    Child.WaitOnExit;
    if (Outcome = TAtlasVcsOutcome.Ok) and (OutputCount > MaxOutputBytes) then
      Outcome := TAtlasVcsOutcome.Failed;
    Result := TAtlasVcsRunResult.Make(Outcome, Child.ExitCode, nil);
    if Outcome = TAtlasVcsOutcome.Ok then
      Result.Output := Copy(Output, 0, OutputCount);
    if ErrorCount > 0 then
      Result.ErrorText := Trim(TEncoding.UTF8.GetString(Errors, 0, ErrorCount));
  finally
    Child.Free;
  end;
end;

end.
