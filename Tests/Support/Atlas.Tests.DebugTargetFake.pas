unit Atlas.Tests.DebugTargetFake;

// Fälschung für IAtlasDebugTarget: spielt den Debugger der IDE für TAtlasDebugPhases. Tests starten Prozesse,
// halten sie in einem Thread an, lassen sie weiterlaufen und beenden sie; die Fälschung ändert ihren Zustand
// und meldet das Ereignis an die verbundenen Phasen wie der Notifier der IDE. Den Tick nach der
// Benachrichtigung des Debuggers löst der Test selbst aus (Tick), Zuhörer laufen ohne Sicherung, ihre
// Fehler zählt Errors. Dazu ein Zuhörer, der die Ereignisse als Text mitschreibt.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Debug.Phases;

type
  TAtlasDebugTargetFake = class(TInterfacedObject, IAtlasDebugTarget)
  private
    FPhases: TAtlasDebugPhases;
    FProcesses: Integer;
    FState: TAtlasDebugProcessState;
    FThread: Cardinal;
    FTickRequests: Integer;
    FTickPending: Boolean;
    FErrors: Integer;
  public
    /// <summary>Ereignisse an APhases melden (nicht besessen); nil = keine.</summary>
    procedure Connect(APhases: TAtlasDebugPhases);
    /// <summary>Neuer Prozess, läuft.</summary>
    procedure Launch;
    /// <summary>Aktueller Prozess hält in Thread AThread an (0 = ohne aktuellen Thread); AState: Stopped,
    /// Exception oder Fault.</summary>
    procedure Stop(AState: TAtlasDebugProcessState; AThread: Cardinal);
    /// <summary>Anderen Thread des angehaltenen Prozesses wählen; der Debugger meldet dazu nichts.</summary>
    procedure SelectThread(AThread: Cardinal);
    /// <summary>Aktueller Prozess läuft weiter.</summary>
    procedure Resume;
    /// <summary>Ein Prozess endet; der letzte lässt den Zustand auf Other.</summary>
    procedure Terminate;
    /// <summary>Zustand ohne Meldung setzen (Stand, bevor der Notifier angemeldet wird).</summary>
    procedure Preset(AProcesses: Integer; AState: TAtlasDebugProcessState; AThread: Cardinal);
    /// <summary>Zeitgeber der IDE: TAtlasDebugPhases.Tick, wenn seit dem letzten Tick einer angefordert ist;
    /// mehrere Anforderungen ergeben einen Tick.</summary>
    procedure Tick;
    /// <summary>Wie oft die Phasen einen Tick angefordert haben.</summary>
    function TickRequests: Integer;
    /// <summary>Fehler in Zuhörern und Filter.</summary>
    function Errors: Integer;
    { IAtlasDebugTarget }
    function ProcessCount: Integer;
    function CurrentState: TAtlasDebugProcessState;
    function HasStoppedThread: Boolean;
    procedure RequestTick;
    procedure Run(const AProc: TProc);
  end;

  /// <summary>Schreibt jedes Ereignis als Zeile mit: Started, Stopped:Paused|Exception|Fault, Resumed, Ended.
  /// </summary>
  TAtlasDebugListenerLog = class(TInterfacedObject, IAtlasDebugListener)
  private
    FLines: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Alle Zeilen, mit Komma getrennt; '' ohne Ereignis.</summary>
    function Text: string;
    procedure DebugStarted; virtual;
    procedure DebugStopped(AStop: TAtlasDebugStop); virtual;
    procedure DebugResumed; virtual;
    procedure DebugEnded; virtual;
  end;

implementation

{ TAtlasDebugTargetFake }

procedure TAtlasDebugTargetFake.Connect(APhases: TAtlasDebugPhases);
begin
  FPhases := APhases;
end;

procedure TAtlasDebugTargetFake.Launch;
begin
  Inc(FProcesses);
  FState := TAtlasDebugProcessState.Running;
  FThread := 0;
  if FPhases <> nil then
  begin
    FPhases.ProcessCreated;
  end;
end;

procedure TAtlasDebugTargetFake.Stop(AState: TAtlasDebugProcessState; AThread: Cardinal);
begin
  FState := AState;
  FThread := AThread;
  if FPhases <> nil then
  begin
    FPhases.StateChanged(AState);
  end;
end;

procedure TAtlasDebugTargetFake.SelectThread(AThread: Cardinal);
begin
  FThread := AThread;
end;

procedure TAtlasDebugTargetFake.Resume;
begin
  FState := TAtlasDebugProcessState.Running;
  FThread := 0;
  if FPhases <> nil then
  begin
    FPhases.StateChanged(FState);
  end;
end;

procedure TAtlasDebugTargetFake.Terminate;
begin
  if FProcesses > 0 then
  begin
    Dec(FProcesses);
  end;
  if FProcesses = 0 then
  begin
    FState := TAtlasDebugProcessState.Other;
    FThread := 0;
  end;
  if FPhases <> nil then
  begin
    FPhases.ProcessDestroyed;
  end;
end;

procedure TAtlasDebugTargetFake.Preset(AProcesses: Integer; AState: TAtlasDebugProcessState; AThread: Cardinal);
begin
  FProcesses := AProcesses;
  FState := AState;
  FThread := AThread;
end;

procedure TAtlasDebugTargetFake.Tick;
begin
  if not FTickPending then
  begin
    Exit;
  end;
  FTickPending := False;
  if FPhases <> nil then
  begin
    FPhases.Tick;
  end;
end;

function TAtlasDebugTargetFake.TickRequests: Integer;
begin
  Result := FTickRequests;
end;

function TAtlasDebugTargetFake.Errors: Integer;
begin
  Result := FErrors;
end;

function TAtlasDebugTargetFake.ProcessCount: Integer;
begin
  Result := FProcesses;
end;

function TAtlasDebugTargetFake.CurrentState: TAtlasDebugProcessState;
begin
  Result := FState;
end;

function TAtlasDebugTargetFake.HasStoppedThread: Boolean;
begin
  Result := TAtlasDebugPhases.IsStop(FState) and (FThread <> 0);
end;

procedure TAtlasDebugTargetFake.RequestTick;
begin
  Inc(FTickRequests);
  FTickPending := True;
end;

procedure TAtlasDebugTargetFake.Run(const AProc: TProc);
begin
  try
    AProc();
  except
    on Exception do
      Inc(FErrors);
  end;
end;

{ TAtlasDebugListenerLog }

constructor TAtlasDebugListenerLog.Create;
begin
  inherited Create;
  FLines := TStringList.Create;
end;

destructor TAtlasDebugListenerLog.Destroy;
begin
  FLines.Free;
  inherited Destroy;
end;

function TAtlasDebugListenerLog.Text: string;
begin
  FLines.Delimiter := ',';
  FLines.StrictDelimiter := True;
  Result := FLines.DelimitedText;
end;

procedure TAtlasDebugListenerLog.DebugStarted;
begin
  FLines.Add('Started');
end;

procedure TAtlasDebugListenerLog.DebugStopped(AStop: TAtlasDebugStop);
const
  cNames: array[TAtlasDebugStop] of string = ('Paused', 'Exception', 'Fault');
begin
  FLines.Add('Stopped:' + cNames[AStop]);
end;

procedure TAtlasDebugListenerLog.DebugResumed;
begin
  FLines.Add('Resumed');
end;

procedure TAtlasDebugListenerLog.DebugEnded;
begin
  FLines.Add('Ended');
end;

end.
