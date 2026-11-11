unit Atlas.Common.Lsp.StatusHeartbeat;

// Schreibt die Statusdatei des Prozesses (#1901) sofort und danach alle AIntervalMs aus der Aktivität
// (TServerActivity) in einem eigenen Thread, unabhängig davon, ob jemand den Status abfragt. Mit
// server.statusFile = false (TServerActivity.Enabled) löscht er die Datei stattdessen. Beim Freigeben hält er den
// Thread an und löscht die Datei. AtlasMonitor erkennt an einer Datei, die nicht mehr nachkommt, einen hängenden
// Server.

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Atlas.Common.Lsp.ServerActivity;

type
  TServerStatusHeartbeat = class
  public const
    cIntervalMs = 5000;
  private
    FRoot: string;
    FPid: Cardinal;
    FActivity: TServerActivity;
    FIntervalMs: Cardinal;
    FStop: TEvent;
    FThread: TThread;
    procedure Execute;
  public
    /// <summary>Startet den Thread; AIntervalMs = 0 schreibt nur auf Beat.</summary>
    constructor Create(const ARoot: string; APid: Cardinal; AActivity: TServerActivity; AIntervalMs: Cardinal);
    destructor Destroy; override;
    /// <summary>Schreibt bzw. löscht die Datei jetzt (auch für Tests).</summary>
    procedure Beat;
  end;

implementation

uses
  Atlas.Common.Product.Version,
  Atlas.Common.Diagnostics.ShutdownLeaks,
  Atlas.Common.Lsp.StatusFile;

constructor TServerStatusHeartbeat.Create(const ARoot: string; APid: Cardinal; AActivity: TServerActivity;
  AIntervalMs: Cardinal);
begin
  inherited Create;
  FRoot := ARoot;
  FPid := APid;
  FActivity := AActivity;
  FIntervalMs := AIntervalMs;
  FStop := TEvent.Create(nil, True, False, '');
  if FIntervalMs > 0 then
  begin
    FThread := TThread.CreateAnonymousThread(Execute);
    FThread.FreeOnTerminate := False;
    FThread.Start;
  end;
end;

destructor TServerStatusHeartbeat.Destroy;
begin
  FStop.SetEvent;
  if FThread <> nil then
  begin
    FThread.WaitFor;
    FThread.Free;
  end;
  FStop.Free;
  TServerStatusFile.Delete(FRoot, FPid);
  inherited;
end;

procedure TServerStatusHeartbeat.Execute;
begin
  repeat
    Beat;
  until FStop.WaitFor(FIntervalMs) <> wrTimeout;
end;

procedure TServerStatusHeartbeat.Beat;
var
  mEntry: TServerStatusEntry;
  mDetails: TServerDetails;
begin
  if not FActivity.Enabled then
  begin
    TServerStatusFile.Delete(FRoot, FPid);
    Exit;
  end;
  mEntry := FActivity.Snapshot(TThread.GetTickCount64);
  mEntry.Pid := FPid;
  mEntry.Version := TProductVersion.cVersion;
  mEntry.MemoryBytes := TShutdownLeaks.AllocatedBytes;
  mDetails := FActivity.Details;
  try
    mEntry.Roots := mDetails.Roots;
    // Laufende Anfragen zählen als Arbeit, auch wenn der Status des Servers „bereit“ sagt.
    if (mDetails.State <> '') and (mEntry.State = TServerStatusEntry.cStateReady) then
    begin
      mEntry.State := mDetails.State;
    end;
    TServerStatusFile.Write(FRoot, mEntry, mDetails.Status, Now);
  finally
    mDetails.Status.Free;
  end;
end;

end.
