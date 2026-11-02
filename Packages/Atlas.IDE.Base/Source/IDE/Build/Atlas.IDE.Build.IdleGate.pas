unit Atlas.IDE.Build.IdleGate;

// Anbindung von TAtlasBuildIdleGate an die IDE: ein eigener
// IOTACompileNotifier (unabhängig vom Feature „Compile“, das abgeschaltet sein
// kann) und ein Zeitgeber, der wartende Aufträge ausführt, sobald Ruhe ist.
// Run reiht einen Auftrag ein, etwa das automatische Öffnen eines
// Dockfensters; Destroy meldet den Notifier ab und verwirft offene Aufträge.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Build.IdleGate;

type
  TAtlasIdeBuildIdleGate = class
  private type
    TNotifier = class(TInterfacedObject, IOTACompileNotifier)
    private
      FOwner: TAtlasIdeBuildIdleGate;
    public
      procedure ProjectCompileStarted(const Project: IOTAProject; Mode: TOTACompileMode);
      procedure ProjectCompileFinished(const Project: IOTAProject; Result: TOTACompileResult);
      procedure ProjectGroupCompileStarted(Mode: TOTACompileMode);
      procedure ProjectGroupCompileFinished(Result: TOTACompileResult);
    end;
  public const
    TickMs = 250;
  private
    FGate: TAtlasBuildIdleGate;
    FNotifier: TNotifier;
    FNotifierRef: IOTACompileNotifier;
    FNotifierIndex: Integer;
    FTimer: TTimer;
    FFeature: TAtlasFeature;
    FPending: TList<TProc>;
    procedure TimerTick(Sender: TObject);
    class function Now: UInt64; static;
  public
    /// <summary>AFeature: unter diesem Feature laufen die Aufträge (Fehler meldet TAtlasGuard).</summary>
    constructor Create(AFeature: TAtlasFeature);
    destructor Destroy; override;
    /// <summary>AProc ausführen, sobald kein Compile läuft und Ruhe ist (im Hauptthread).</summary>
    procedure Run(const AProc: TProc);
  end;

implementation

uses
  System.Classes;

{ TAtlasIdeBuildIdleGate.TNotifier }

procedure TAtlasIdeBuildIdleGate.TNotifier.ProjectCompileStarted(const Project: IOTAProject; Mode: TOTACompileMode);
begin
  if FOwner <> nil then
    FOwner.FGate.ProjectStarted(TAtlasIdeBuildIdleGate.Now);
end;

procedure TAtlasIdeBuildIdleGate.TNotifier.ProjectCompileFinished(const Project: IOTAProject;
  Result: TOTACompileResult);
begin
  if FOwner <> nil then
    FOwner.FGate.ProjectFinished(TAtlasIdeBuildIdleGate.Now);
end;

procedure TAtlasIdeBuildIdleGate.TNotifier.ProjectGroupCompileStarted(Mode: TOTACompileMode);
begin
  if FOwner <> nil then
    FOwner.FGate.GroupStarted(TAtlasIdeBuildIdleGate.Now);
end;

procedure TAtlasIdeBuildIdleGate.TNotifier.ProjectGroupCompileFinished(Result: TOTACompileResult);
begin
  if FOwner <> nil then
    FOwner.FGate.GroupFinished(TAtlasIdeBuildIdleGate.Now);
end;

{ TAtlasIdeBuildIdleGate }

constructor TAtlasIdeBuildIdleGate.Create(AFeature: TAtlasFeature);
var
  Services: IOTACompileServices;
begin
  inherited Create;
  FFeature := AFeature;
  FGate := TAtlasBuildIdleGate.Create(Now);
  FPending := TList<TProc>.Create;
  FNotifierIndex := -1;
  if Supports(BorlandIDEServices, IOTACompileServices, Services) then
  begin
    FNotifier := TNotifier.Create;
    FNotifier.FOwner := Self;
    FNotifierRef := FNotifier;
    FNotifierIndex := Services.AddNotifier(FNotifierRef);
  end;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := TickMs;
  FTimer.OnTimer := TimerTick;
end;

destructor TAtlasIdeBuildIdleGate.Destroy;
var
  Services: IOTACompileServices;
begin
  // Erst abmelden, dann freigeben (#493); die IDE hält den Notifier evtl. noch.
  FreeAndNil(FTimer);
  if FNotifier <> nil then
    FNotifier.FOwner := nil;
  if (FNotifierIndex >= 0) and Supports(BorlandIDEServices, IOTACompileServices, Services) then
    Services.RemoveNotifier(FNotifierIndex);
  FNotifierRef := nil;
  FPending.Free;
  FGate.Free;
  inherited;
end;

class function TAtlasIdeBuildIdleGate.Now: UInt64;
begin
  Result := TThread.GetTickCount64;
end;

procedure TAtlasIdeBuildIdleGate.Run(const AProc: TProc);
begin
  FPending.Add(AProc);
  FTimer.Enabled := True;
end;

procedure TAtlasIdeBuildIdleGate.TimerTick(Sender: TObject);
var
  Procs: TArray<TProc>;
  Proc: TProc;
begin
  if not FGate.Idle(Now) then
    Exit;
  FTimer.Enabled := False;
  Procs := FPending.ToArray;
  FPending.Clear;
  for Proc in Procs do
    TAtlasGuard.Run(FFeature, Proc);
end;

end.
