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
    begin
      FRunning.Add(AProcess);
    end;
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
    begin
      Running.Terminate(CancelledExitCode);
    end;
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
    begin
      SetLength(Line, Length(Line) - 1);
    end;
    if Assigned(AOnLine) then
    begin
      AOnLine(Line);
    end;
  end;

begin
  if WasCancelled then
  begin
    raise ECompilerCancelled.CreateFmt('%s: abgebrochen', [ExtractFileName(ARequest.Executable)]);
  end;
  Child := TProcess.Create(nil);
  try
    Child.Executable := ARequest.Executable;
    for Argument in ARequest.Arguments do
    begin
      Child.Parameters.Add(Argument);
    end;
    if ARequest.WorkingDir <> '' then
    begin
      Child.CurrentDirectory := ARequest.WorkingDir;
    end;
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
    begin
      Child.Terminate(CancelledExitCode);
    end;
    try
      Pending := nil;
      repeat
        BytesRead := Child.Output.Read(Buffer, SizeOf(Buffer));
        if BytesRead <= 0 then
        begin
          Break;
        end;
        Start := Length(Pending);
        SetLength(Pending, Start + BytesRead);
        Move(Buffer[0], Pending[Start], BytesRead);
        Start := 0;
        for LineEnd := 0 to High(Pending) do
        begin
          if Pending[LineEnd] = 10 then
          begin
            EmitLine(Start, LineEnd - Start);
            Start := LineEnd + 1;
          end;
        end;
        Pending := Copy(Pending, Start, MaxInt);
      until False;
      if Length(Pending) > 0 then
      begin
        EmitLine(0, Length(Pending));
      end;
      Child.WaitOnExit;
      Result := Child.ExitCode;
    finally
      Untrack(Child);
    end;
    if WasCancelled then
    begin
      raise ECompilerCancelled.CreateFmt('%s: abgebrochen', [ExtractFileName(ARequest.Executable)]);
    end;
  finally
    Child.Free;
  end;
end;

end.
