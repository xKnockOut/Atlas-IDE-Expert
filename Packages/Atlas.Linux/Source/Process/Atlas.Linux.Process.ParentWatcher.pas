unit Atlas.Linux.Process.ParentWatcher;

// Platform-Feature "Process" für Linux (#1109): Gegenstück zu
// Atlas.Windows.Process.ParentWatcher. Linux kennt kein Warten auf einen
// fremden Prozess über ein Handle; der Beobachter fragt deshalb alle PollMs
// mit kill(pid, 0) nach. ESRCH heißt: der Prozess ist beendet. Fehlt das Recht
// (EPERM), läuft er noch.

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs;

type
  /// <summary>Ruft AOnExited einmal auf, sobald der Prozess AProcessId endet (im Beobachter-Thread).</summary>
  TParentWatcher = class
  public const
    PollMs = 500;
  private
    FStop: TEvent;
    FThread: TThread;
  public
    constructor Create(AProcessId: Cardinal; const AOnExited: TProc);
    destructor Destroy; override;
    function Watching: Boolean;
    class function CurrentProcessId: Cardinal; static;
    /// <summary>True, solange der Prozess APid läuft.</summary>
    class function Running(APid: Cardinal): Boolean; static;
  end;

implementation

uses
  BaseUnix;

{ TParentWatcher }

class function TParentWatcher.Running(APid: Cardinal): Boolean;
begin
  if APid = 0 then
    Exit(False);
  Result := (FpKill(TPid(APid), 0) = 0) or (FpGetErrno = ESysEPERM);
end;

constructor TParentWatcher.Create(AProcessId: Cardinal; const AOnExited: TProc);
var
  Stop: TEvent;
  OnExited: TProc;
  ProcessId: Cardinal;
begin
  inherited Create;
  if not Running(AProcessId) then
  begin
    AOnExited();
    Exit;
  end;
  FStop := TEvent.Create(nil, True, False, '');
  Stop := FStop;
  OnExited := AOnExited;
  ProcessId := AProcessId;
  FThread := TThread.CreateAnonymousThread(
    procedure
    begin
      while Stop.WaitFor(PollMs) = wrTimeout do
        if not TParentWatcher.Running(ProcessId) then
        begin
          OnExited();
          Exit;
        end;
    end);
  FThread.FreeOnTerminate := False;
  FThread.Start;
end;

destructor TParentWatcher.Destroy;
begin
  if FThread <> nil then
  begin
    FStop.SetEvent;
    FThread.WaitFor;
    FThread.Free;
  end;
  FStop.Free;
  inherited;
end;

class function TParentWatcher.CurrentProcessId: Cardinal;
begin
  Result := Cardinal(FpGetPid);
end;

function TParentWatcher.Watching: Boolean;
begin
  Result := FThread <> nil;
end;

end.
