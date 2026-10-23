unit Atlas.Linux.Compiler.Adapters.ProcessRunner;

// Platform-Feature "Compiler" für Linux (#1109): Gegenstück zu
// Atlas.Windows.Compiler.Adapters.ProcessRunner. Startet einen Prozess ohne
// Shell (Argumente einzeln, kein Quoting nötig), liest stdout und stderr
// gemeinsam zeilenweise (UTF-8) und liefert den Exit-Code. Cancel beendet alle
// laufenden Prozesse dieses Läufers.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Process,
  Atlas.Common.Compiler.Contract;

type
  TProcessRunner = class(TInterfacedObject, ICompilerProcess)
  private
    FLock: TObject;
    FRunning: TList<TProcess>;
    FCancelled: Boolean;
    function Track(AProcess: TProcess): Boolean;
    procedure Untrack(AProcess: TProcess);
    function WasCancelled: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    { ICompilerProcess }
    function Run(const ARequest: TCompilerRequest; const AOnLine: TCompilerLineEvent): Integer;
    procedure Cancel;
  end;

implementation

const
  /// <summary>Exit-Code eines über Cancel beendeten Prozesses.</summary>
  CancelledExitCode = 1;

{ TProcessRunner }

constructor TProcessRunner.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FRunning := TList<TProcess>.Create;
end;

destructor TProcessRunner.Destroy;
begin
  FRunning.Free;
  FLock.Free;
  inherited;
end;

function TProcessRunner.Track(AProcess: TProcess): Boolean;
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

procedure TProcessRunner.Untrack(AProcess: TProcess);
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
  Running: TProcess;
begin
  TMonitor.Enter(FLock);
  try
    FCancelled := True;
    // Unter der Sperre: Run entfernt einen Prozess erst (Untrack), bevor es ihn freigibt.
    for Running in FRunning do
      Running.Terminate(CancelledExitCode);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TProcessRunner.Run(const ARequest: TCompilerRequest; const AOnLine: TCompilerLineEvent): Integer;
var
  Child: TProcess;
  Argument: string;
  Buffer: array[0..4095] of Byte;
  BytesRead, LineEnd, Start: Integer;
  Pending: TBytes;

  procedure EmitLine(AFrom, ACount: Integer);
  var
    Line: string;
  begin
    Line := TEncoding.UTF8.GetString(Pending, AFrom, ACount);
    if (Line <> '') and (Line[Length(Line)] = #13) then
      SetLength(Line, Length(Line) - 1);
    if Assigned(AOnLine) then
      AOnLine(Line);
  end;

begin
  if WasCancelled then
    raise ECompilerCancelled.CreateFmt('%s: abgebrochen', [ExtractFileName(ARequest.Executable)]);
  Child := TProcess.Create(nil);
  try
    Child.Executable := ARequest.Executable;
    for Argument in ARequest.Arguments do
      Child.Parameters.Add(Argument);
    if ARequest.WorkingDir <> '' then
      Child.CurrentDirectory := ARequest.WorkingDir;
    Child.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
    try
      Child.Execute;
    except
      on E: EProcess do
        raise ECompilerError.CreateFmt('%s lässt sich nicht starten: %s', [ARequest.Executable, E.Message]);
    end;
    // Kein stdin: Der Kindprozess soll nie auf eine Eingabe warten.
    Child.CloseInput;
    if not Track(Child) then
      Child.Terminate(CancelledExitCode);
    try
      Pending := nil;
      repeat
        BytesRead := Child.Output.Read(Buffer, SizeOf(Buffer));
        if BytesRead <= 0 then
          Break;
        Start := Length(Pending);
        SetLength(Pending, Start + BytesRead);
        Move(Buffer[0], Pending[Start], BytesRead);
        Start := 0;
        for LineEnd := 0 to High(Pending) do
          if Pending[LineEnd] = 10 then
          begin
            EmitLine(Start, LineEnd - Start);
            Start := LineEnd + 1;
          end;
        Pending := Copy(Pending, Start, MaxInt);
      until False;
      if Length(Pending) > 0 then
        EmitLine(0, Length(Pending));
      Child.WaitOnExit;
      Result := Child.ExitCode;
    finally
      Untrack(Child);
    end;
    if WasCancelled then
      raise ECompilerCancelled.CreateFmt('%s: abgebrochen', [ExtractFileName(ARequest.Executable)]);
  finally
    Child.Free;
  end;
end;

end.
