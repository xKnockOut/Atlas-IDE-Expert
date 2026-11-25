unit Atlas.Common.Compiler.ProcessRuns;

// Gemeinsame Teile der Prozessläufer unter Windows und Linux (ICompilerProcess):
// laufende Prozesse für Cancel verfolgen und die Ausgabe zeilenweise weiterreichen.
// Was einen Prozess startet, liest und beendet, bleibt beim Läufer der Plattform.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Compiler.Contract;

type
  /// <summary>Beendet einen laufenden Prozess (Handle bzw. Objekt der Plattform).</summary>
  TCompilerProcessStop<T> = reference to procedure(const AProcess: T);

  /// <summary>Laufende Prozesse eines Läufers; threadsicher. Cancel beendet alle (mehrere Run gleichzeitig, z. B.
  /// Compilerlauf und git status).</summary>
  TCompilerProcessList<T> = class
  private
    FLock: TObject;
    FRunning: TList<T>;
    FCancelled: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Merkt sich AProcess für Cancel; False, wenn Cancel schon lief (der Aufrufer beendet den Prozess
    /// dann selbst).</summary>
    function Track(const AProcess: T): Boolean;
    procedure Untrack(const AProcess: T);
    function WasCancelled: Boolean;
    /// <summary>Merkt den Abbruch und ruft AStop für jeden laufenden Prozess, unter der Sperre: Run entfernt einen
    /// Prozess erst (Untrack), bevor es ihn freigibt.</summary>
    procedure Cancel(const AStop: TCompilerProcessStop<T>);
  end;

  TCompilerOutputLines = record
  public
    /// <summary>Zeile ABytes[AFrom .. AFrom + ACount - 1] in AEncoding, ohne #13 am Ende, an AOnLine.</summary>
    class procedure Emit(const ABytes: TBytes; AFrom, ACount: Integer; AEncoding: TEncoding;
      const AOnLine: TCompilerLineEvent); static;
    /// <summary>Alle vollständigen Zeilen aus APending ausgeben; der angefangene Rest bleibt in APending.</summary>
    class procedure EmitComplete(var APending: TBytes; AEncoding: TEncoding;
      const AOnLine: TCompilerLineEvent); static;
  end;

implementation

{ TCompilerProcessList<T> }

constructor TCompilerProcessList<T>.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FRunning := TList<T>.Create;
end;

destructor TCompilerProcessList<T>.Destroy;
begin
  FRunning.Free;
  FLock.Free;
  inherited;
end;

function TCompilerProcessList<T>.Track(const AProcess: T): Boolean;
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

procedure TCompilerProcessList<T>.Untrack(const AProcess: T);
begin
  TMonitor.Enter(FLock);
  try
    FRunning.Remove(AProcess);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TCompilerProcessList<T>.WasCancelled: Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := FCancelled;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TCompilerProcessList<T>.Cancel(const AStop: TCompilerProcessStop<T>);
var
  mProcess: T;
begin
  TMonitor.Enter(FLock);
  try
    FCancelled := True;
    for mProcess in FRunning do
    begin
      AStop(mProcess);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

{ TCompilerOutputLines }

class procedure TCompilerOutputLines.Emit(const ABytes: TBytes; AFrom, ACount: Integer; AEncoding: TEncoding;
  const AOnLine: TCompilerLineEvent);
var
  mLine: string;
begin
  mLine := AEncoding.GetString(ABytes, AFrom, ACount);
  if (mLine <> '') and (mLine[Length(mLine)] = #13) then
  begin
    SetLength(mLine, Length(mLine) - 1);
  end;
  if Assigned(AOnLine) then
  begin
    AOnLine(mLine);
  end;
end;

class procedure TCompilerOutputLines.EmitComplete(var APending: TBytes; AEncoding: TEncoding;
  const AOnLine: TCompilerLineEvent);
var
  mStart, mLineEnd: Integer;
begin
  mStart := 0;
  for mLineEnd := 0 to High(APending) do
  begin
    if APending[mLineEnd] = 10 then
    begin
      Emit(APending, mStart, mLineEnd - mStart, AEncoding, AOnLine);
      mStart := mLineEnd + 1;
    end;
  end;
  APending := Copy(APending, mStart, MaxInt);
end;

end.
