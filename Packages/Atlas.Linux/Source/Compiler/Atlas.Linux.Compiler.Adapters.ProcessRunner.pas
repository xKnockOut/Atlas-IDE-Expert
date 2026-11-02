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

procedure RaiseCancelled(const ARequest: TCompilerRequest);
begin
  raise ECompilerCancelled.CreateFmt('%s: abgebrochen', [ExtractFileName(ARequest.Executable)]);
end;

/// <summary>Zeile ABytes[AFrom .. AFrom + ACount - 1] (UTF-8, ohne #13 am Ende) an AOnLine.</summary>
procedure EmitLine(const ABytes: TBytes; AFrom, ACount: Integer; const AOnLine: TCompilerLineEvent);
var
  mLine: string;
begin
  mLine := TEncoding.UTF8.GetString(ABytes, AFrom, ACount);
  if (mLine <> '') and (mLine[Length(mLine)] = #13) then
  begin
    SetLength(mLine, Length(mLine) - 1);
  end;
  if Assigned(AOnLine) then
  begin
    AOnLine(mLine);
  end;
end;

/// <summary>Alle vollständigen Zeilen aus APending ausgeben; der angefangene Rest bleibt in APending.</summary>
procedure EmitCompleteLines(var APending: TBytes; const AOnLine: TCompilerLineEvent);
var
  mStart, mLineEnd: Integer;
begin
  mStart := 0;
  for mLineEnd := 0 to High(APending) do
  begin
    if APending[mLineEnd] = 10 then
    begin
      EmitLine(APending, mStart, mLineEnd - mStart, AOnLine);
      mStart := mLineEnd + 1;
    end;
  end;
  APending := Copy(APending, mStart, MaxInt);
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
    EmitCompleteLines(mPending, AOnLine);
  until False;
  if Length(mPending) > 0 then
  begin
    EmitLine(mPending, 0, Length(mPending), AOnLine);
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
  if WasCancelled then
  begin
    RaiseCancelled(ARequest);
  end;
  mChild := TProcess.Create(nil);
  try
    StartChild(mChild, ARequest);
    if not Track(mChild) then
    begin
      mChild.Terminate(CancelledExitCode);
    end;
    try
      ReadOutput(mChild, AOnLine);
      mChild.WaitOnExit;
      Result := mChild.ExitCode;
    finally
      Untrack(mChild);
    end;
    if WasCancelled then
    begin
      RaiseCancelled(ARequest);
    end;
  finally
    mChild.Free;
  end;
end;

end.
