unit Atlas.Linux.Compiler.Adapters.ProcessRunner;

// Platform-Feature "Compiler" für Linux (#1109): Gegenstück zu
// Atlas.Windows.Compiler.Adapters.ProcessRunner. Startet einen Prozess ohne
// Shell (Argumente einzeln, kein Quoting nötig), liest stdout und stderr
// gemeinsam zeilenweise (UTF-8) und liefert den Exit-Code. Cancel beendet alle
// laufenden Prozesse dieses Läufers.

interface

uses
  System.SysUtils,
  Process,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Compiler.ProcessRuns;

type
  TProcessRunner = class(TInterfacedObject, ICompilerProcess)
  private
    /// <summary>Laufende Prozesse für Cancel.</summary>
    FProcesses: TCompilerProcessList<TProcess>;
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
  cCancelledExitCode = 1;

{ TProcessRunner }

constructor TProcessRunner.Create;
begin
  inherited Create;
  FProcesses := TCompilerProcessList<TProcess>.Create;
end;

destructor TProcessRunner.Destroy;
begin
  FProcesses.Free;
  inherited;
end;

procedure TProcessRunner.Cancel;
begin
  FProcesses.Cancel(
    procedure(const AProcess: TProcess)
    begin
      AProcess.Terminate(cCancelledExitCode);
    end);
end;

procedure RaiseCancelled(const ARequest: TCompilerRequest);
begin
  raise ECompilerCancelled.CreateFmt('%s: abgebrochen', [ExtractFileName(ARequest.Executable)]);
end;

/// <summary>Liest die Ausgabe des Kindprozesses bis zum Ende und gibt sie zeilenweise an AOnLine.</summary>
procedure ReadOutput(AChild: TProcess; const AOnLine: TCompilerLineEvent);
var
  mBuffer: array[0..4095] of Byte;
  mBytesRead, mStart: Integer;
  mPending: TBytes;
begin
  mPending := nil;
  repeat
    mBytesRead := AChild.Output.Read(mBuffer, SizeOf(mBuffer));
    if mBytesRead <= 0 then
    begin
      Break;
    end;
    mStart := Length(mPending);
    SetLength(mPending, mStart + mBytesRead);
    Move(mBuffer[0], mPending[mStart], mBytesRead);
    TCompilerOutputLines.EmitComplete(mPending, TEncoding.UTF8, AOnLine);
  until False;
  if Length(mPending) > 0 then
  begin
    TCompilerOutputLines.Emit(mPending, 0, Length(mPending), TEncoding.UTF8, AOnLine);
  end;
end;

/// <summary>Richtet AChild nach ARequest ein und startet ihn ohne stdin.</summary>
procedure StartChild(AChild: TProcess; const ARequest: TCompilerRequest);
var
  mArgument: string;
begin
  AChild.Executable := ARequest.Executable;
  for mArgument in ARequest.Arguments do
  begin
    AChild.Parameters.Add(mArgument);
  end;
  if ARequest.WorkingDir <> '' then
  begin
    AChild.CurrentDirectory := ARequest.WorkingDir;
  end;
  AChild.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
  try
    AChild.Execute;
  except
    on E: EProcess do
      raise ECompilerError.CreateFmt('%s lässt sich nicht starten: %s', [ARequest.Executable, E.Message]);
  end;
  // Kein stdin: Der Kindprozess soll nie auf eine Eingabe warten.
  AChild.CloseInput;
end;

function TProcessRunner.Run(const ARequest: TCompilerRequest; const AOnLine: TCompilerLineEvent): Integer;
var
  mChild: TProcess;
begin
  if FProcesses.WasCancelled then
  begin
    RaiseCancelled(ARequest);
  end;
  mChild := TProcess.Create(nil);
  try
    StartChild(mChild, ARequest);
    if not FProcesses.Track(mChild) then
    begin
      mChild.Terminate(cCancelledExitCode);
    end;
    try
      ReadOutput(mChild, AOnLine);
      mChild.WaitOnExit;
      Result := mChild.ExitCode;
    finally
      FProcesses.Untrack(mChild);
    end;
    if FProcesses.WasCancelled then
    begin
      RaiseCancelled(ARequest);
    end;
  finally
    mChild.Free;
  end;
end;

end.
