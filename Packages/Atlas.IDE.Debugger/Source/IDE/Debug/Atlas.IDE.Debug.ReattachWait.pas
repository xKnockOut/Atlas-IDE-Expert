unit Atlas.IDE.Debug.ReattachWait;

// Erneut anhängen (#2171): Warten auf den Start eines Programms in einem
// Hintergrundthread. Fragt alle AIntervalMs die Prozesse mit dem Namen der
// EXE ab (TAtlasIdeDebugProcesses.Named, nur Pfade) und meldet den ersten
// neuen mit passendem Pfad (TAtlasReattach.Arrival) über TAtlasMainThread an
// AOnFound; danach endet der Thread. Prozesse, die beim Anlegen schon liefen,
// zählen nicht. Terminate weckt ihn sofort; der Besitzer gibt ihn mit Free
// frei (wartet auf das Ende), bevor das Modul geht.

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs;

type
  TAtlasIdeReattachWaiter = class(TThread)
  private
    FTarget: string;
    FName: string;
    FIntervalMs: Integer;
    FKnown: TArray<Cardinal>;
    FWake: TEvent;
    FOnFound: TProc<Cardinal>;
    procedure Report(APid: Cardinal);
  protected
    procedure Execute; override;
    procedure TerminatedSet; override;
  public
    /// <summary>Wartet auf ATarget (Pfad der EXE); AOnFound bekommt im Hauptthread die Kennung.</summary>
    constructor Create(const ATarget: string; AIntervalMs: Integer; const AOnFound: TProc<Cardinal>);
    destructor Destroy; override;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Debug.Reattach,
  Atlas.IDE.Debug.Processes;

constructor TAtlasIdeReattachWaiter.Create(const ATarget: string; AIntervalMs: Integer;
  const AOnFound: TProc<Cardinal>);
begin
  FTarget := ATarget;
  FName := TAtlasReattach.NameOf(ATarget);
  FIntervalMs := AIntervalMs;
  FOnFound := AOnFound;
  FWake := TEvent.Create(nil, True, False, '');
  // Stand beim Beginn: Diese Prozesse laufen schon und zählen nicht als Start.
  FKnown := TAtlasReattach.Pids(TAtlasIdeDebugProcesses.Named(FName, False));
  inherited Create(False);
end;

destructor TAtlasIdeReattachWaiter.Destroy;
begin
  Terminate;
  inherited Destroy;
  FWake.Free;
end;

procedure TAtlasIdeReattachWaiter.TerminatedSet;
begin
  inherited;
  FWake.SetEvent;
end;

procedure TAtlasIdeReattachWaiter.Report(APid: Cardinal);
var
  mFound: TProc<Cardinal>;
begin
  mFound := FOnFound;
  TAtlasMainThread.Queue(TAtlasFeature.Debugger,
    procedure
    begin
      mFound(APid);
    end);
end;

procedure TAtlasIdeReattachWaiter.Execute;
var
  mProcess: TAtlasReattachProcess;
begin
  while not Terminated do
  begin
    if TAtlasReattach.Arrival(FTarget, TAtlasIdeDebugProcesses.Named(FName, False), FKnown, mProcess) then
    begin
      Report(mProcess.Pid);
      Exit;
    end;
    FWake.WaitFor(FIntervalMs);
  end;
end;

end.
