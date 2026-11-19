unit Atlas.IDE.Debug.Adapters.SessionTarget;

// Der Debugger der IDE für die Phasen der Debug-Sitzung (IAtlasDebugTarget aus
// Atlas.Core.Debug.Contract): Prozesse und Zustand über IOTADebuggerServices,
// der Tick über den Zeitgeber der Sitzung, Zuhörer und Filter unter der
// Sicherung (Feature Debugger, #493). Erzeugt nur die Komposition des Moduls,
// die das Ziel mit TAtlasIdeDebugSession.UseAdapters setzt. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Debug.Contract;

type
  TAtlasIdeDebugTarget = class(TInterfacedObject, IAtlasDebugTarget)
  public
    function ProcessCount: Integer;
    function CurrentState: TAtlasDebugProcessState;
    function HasStoppedThread: Boolean;
    procedure RequestTick;
    procedure Run(const AProc: TProc);
  end;

implementation

uses
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Foundation.Debugger,
  Atlas.IDE.Debug.Session;

{ TAtlasIdeDebugTarget }

function TAtlasIdeDebugTarget.ProcessCount: Integer;
var
  mServices: IOTADebuggerServices;
begin
  Result := 0;
  mServices := TAtlasIdeDebugger.Services;
  if mServices <> nil then
  begin
    Result := mServices.ProcessCount;
  end;
end;

function TAtlasIdeDebugTarget.CurrentState: TAtlasDebugProcessState;
var
  mCurrent: IOTAProcess;
begin
  Result := TAtlasDebugProcessState.Other;
  mCurrent := TAtlasIdeDebugSession.Process;
  if mCurrent <> nil then
  begin
    Result := TAtlasIdeDebugSession.PhaseState(mCurrent.ProcessState);
  end;
end;

function TAtlasIdeDebugTarget.HasStoppedThread: Boolean;
begin
  Result := TAtlasIdeDebugSession.StoppedThread <> nil;
end;

procedure TAtlasIdeDebugTarget.RequestTick;
begin
  TAtlasIdeDebugSession.RequestTick;
end;

procedure TAtlasIdeDebugTarget.Run(const AProc: TProc);
begin
  TAtlasGuard.Run(TAtlasFeature.Debugger, AProc);
end;

end.
