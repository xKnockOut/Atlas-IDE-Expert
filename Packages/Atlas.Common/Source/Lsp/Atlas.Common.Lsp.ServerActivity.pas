unit Atlas.Common.Lsp.ServerActivity;

// Was der Server gerade tut, für seine Statusdatei (#1901): Art, Befehl und Ziel des Prozesses, laufende Anfragen
// mit Dauer (über TServerActivityObserver am Verteiler), Fortschritt eines Kommandozeilenlaufs, Zähler für
// Zeitüberschreitungen und Fehler. Der LSP-Server meldet zusätzlich eine Funktion für seinen ausführlichen Status
// (SetDetails). Ein Prozess hat genau eine Aktivität (Shared); TServerStatusHeartbeat liest sie alle paar Sekunden.
// Alle Methoden sind threadsicher.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Classes,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Lsp.StatusFile;

type
  /// <summary>Ausführlicher Status des LSP-Servers: Wurzeln der Arbeitsbereiche, Status (gehört dem Aufrufer, nil
  /// ohne) und Zustand (loading, ready, checking; '' = aus der Aktivität).</summary>
  TServerDetails = record
    Roots: TArray<string>;
    Status: TJSONObject;
    State: string;
  end;

  TServerDetailsFunc = reference to function: TServerDetails;

  TServerActivity = class
  private type
    TRun = record
      Method: string;
      StartTicks: UInt64;
    end;
  private
    FLock: TObject;
    /// <summary>Eigene Sperre für SetDetails und Details: Das Abmelden wartet, bis eine laufende Abfrage fertig ist.
    /// </summary>
    FDetailsLock: TObject;
    FRuns: TDictionary<TThreadID, TRun>;
    FKind: string;
    FCommand: string;
    FTarget: string;
    FLogFile: string;
    FStarted: TDateTime;
    FDone: Integer;
    FTotal: Integer;
    FTimeouts: Integer;
    FErrors: Integer;
    FEnabled: Boolean;
    FDetails: TServerDetailsFunc;
    function GetEnabled: Boolean;
    procedure SetEnabled(AValue: Boolean);
    /// <summary>Die am längsten laufende Anfrage; nur unter FLock.</summary>
    procedure AddLongestRun(var AEntry: TServerStatusEntry; ANowTicks: UInt64);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Art (TServerStatusEntry.cKind*), Befehl und Ziel des Prozesses.</summary>
    procedure Describe(const AKind, ACommand, ATarget: string);
    /// <summary>Protokolldatei aus --log, damit AtlasMonitor sie öffnen kann.</summary>
    procedure SetLogFile(const AFileName: string);
    /// <summary>Eine Anfrage beginnt im aufrufenden Thread zum Zeitpunkt ATicks (TThread.GetTickCount64).</summary>
    procedure RequestStarted(const AMethod: string; ATicks: UInt64);
    /// <summary>Die Anfrage des aufrufenden Threads ist fertig; AFailed zählt sie als Fehler.</summary>
    procedure RequestFinished(AFailed: Boolean);
    /// <summary>Eine Anfrage hat das Zeitlimit überschritten.</summary>
    procedure CountTimeout;
    /// <summary>Fortschritt eines Laufs: ADone von ATotal (ATotal = 0: kein Fortschritt).</summary>
    procedure SetProgress(ADone, ATotal: Integer);
    /// <summary>Meldet die Funktion für den ausführlichen Status an bzw. mit nil ab; das Abmelden wartet auf eine
    /// laufende Abfrage.</summary>
    procedure SetDetails(const ADetails: TServerDetailsFunc);
    /// <summary>Ausführlicher Status; Roots = [Ziel] und Status = nil ohne angemeldete Funktion. Fehler der Funktion
    /// geben ebenfalls nur das Ziel.</summary>
    function Details: TServerDetails;
    /// <summary>Stand für die Statusdatei zum Zeitpunkt ANowTicks, ohne pid, Version, Speicher und Details.</summary>
    function Snapshot(ANowTicks: UInt64): TServerStatusEntry;
    /// <summary>server.statusFile: False, wenn der Prozess keine Statusdatei schreiben soll.</summary>
    property Enabled: Boolean read GetEnabled write SetEnabled;
    /// <summary>Die Aktivität dieses Prozesses.</summary>
    class function Shared: TServerActivity; static;
  end;

  /// <summary>Beobachter am Verteiler: meldet Beginn und Ende jeder Anfrage an die Aktivität und reicht beides an
  /// ANext weiter (nil = keiner).</summary>
  TServerActivityObserver = class(TInterfacedObject, IJsonRpcRequestObserver)
  private
    FActivity: TServerActivity;
    FNext: IJsonRpcRequestObserver;
  public
    constructor Create(AActivity: TServerActivity; const ANext: IJsonRpcRequestObserver);
    procedure Started(const AMethod: string);
    procedure Finished(const AMethod: string; const AParams, AResult: TJSONValue; const AError: Exception;
      AQueueMs, AElapsedMs: Int64);
  end;

implementation

var
  /// <summary>Die Aktivität des Prozesses; lebt von der Initialisierung bis zur Finalisierung der Unit.</summary>
  GShared: TServerActivity;

{ TServerActivity }

constructor TServerActivity.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FDetailsLock := TObject.Create;
  FRuns := TDictionary<TThreadID, TRun>.Create;
  FStarted := Now;
  FEnabled := True;
  // TMonitor legt seinen Datensatz beim ersten Enter an und hält ihn bis zur Freigabe: gleich hier anlegen, damit
  // er bei Shared zur Unit-Initialisierung gehört und nicht der ersten Anfrage (bzw. dem ersten Test) zufällt.
  System.TMonitor.Enter(FLock);
  System.TMonitor.Exit(FLock);
  System.TMonitor.Enter(FDetailsLock);
  System.TMonitor.Exit(FDetailsLock);
end;

destructor TServerActivity.Destroy;
begin
  FRuns.Free;
  FDetailsLock.Free;
  FLock.Free;
  inherited;
end;

class function TServerActivity.Shared: TServerActivity;
begin
  Result := GShared;
end;

function TServerActivity.GetEnabled: Boolean;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FEnabled;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TServerActivity.SetEnabled(AValue: Boolean);
begin
  System.TMonitor.Enter(FLock);
  try
    FEnabled := AValue;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TServerActivity.Describe(const AKind, ACommand, ATarget: string);
begin
  System.TMonitor.Enter(FLock);
  try
    FKind := AKind;
    FCommand := ACommand;
    FTarget := ATarget;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TServerActivity.SetLogFile(const AFileName: string);
begin
  System.TMonitor.Enter(FLock);
  try
    FLogFile := AFileName;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TServerActivity.RequestStarted(const AMethod: string; ATicks: UInt64);
var
  mRun: TRun;
begin
  mRun.Method := AMethod;
  mRun.StartTicks := ATicks;
  System.TMonitor.Enter(FLock);
  try
    FRuns.AddOrSetValue(TThread.CurrentThread.ThreadID, mRun);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TServerActivity.RequestFinished(AFailed: Boolean);
begin
  System.TMonitor.Enter(FLock);
  try
    FRuns.Remove(TThread.CurrentThread.ThreadID);
    if AFailed then
    begin
      Inc(FErrors);
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TServerActivity.CountTimeout;
begin
  System.TMonitor.Enter(FLock);
  try
    Inc(FTimeouts);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TServerActivity.SetProgress(ADone, ATotal: Integer);
begin
  System.TMonitor.Enter(FLock);
  try
    FDone := ADone;
    FTotal := ATotal;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TServerActivity.SetDetails(const ADetails: TServerDetailsFunc);
begin
  System.TMonitor.Enter(FDetailsLock);
  try
    FDetails := ADetails;
  finally
    System.TMonitor.Exit(FDetailsLock);
  end;
end;

function TServerActivity.Details: TServerDetails;
var
  mTarget: string;
begin
  Result := Default(TServerDetails);
  System.TMonitor.Enter(FDetailsLock);
  try
    if Assigned(FDetails) then
    try
      Result := FDetails();
    except
      // lsp-ignore: catch-all-without-raise -- Statusdatei nach Kräften; der Server arbeitet weiter
      on Exception do
        Result := Default(TServerDetails);
    end;
  finally
    System.TMonitor.Exit(FDetailsLock);
  end;
  if Result.Roots = nil then
  begin
    System.TMonitor.Enter(FLock);
    try
      mTarget := FTarget;
    finally
      System.TMonitor.Exit(FLock);
    end;
    if mTarget <> '' then
    begin
      Result.Roots := TArray<string>.Create(mTarget);
    end;
  end;
end;

procedure TServerActivity.AddLongestRun(var AEntry: TServerStatusEntry; ANowTicks: UInt64);
var
  mRun: TRun;
  mElapsed: Int64;
begin
  for mRun in FRuns.Values do
  begin
    Inc(AEntry.Running);
    mElapsed := 0;
    if ANowTicks > mRun.StartTicks then
    begin
      mElapsed := Int64(ANowTicks - mRun.StartTicks);
    end;
    // Bei gleicher Dauer entscheidet der Name, damit das Ergebnis nicht von der Reihenfolge abhängt.
    if (AEntry.Running = 1) or (mElapsed > AEntry.RunningMs) or
      ((mElapsed = AEntry.RunningMs) and (CompareStr(mRun.Method, AEntry.RunningMethod) < 0)) then
    begin
      AEntry.RunningMs := mElapsed;
      AEntry.RunningMethod := mRun.Method;
    end;
  end;
end;

function TServerActivity.Snapshot(ANowTicks: UInt64): TServerStatusEntry;
begin
  Result := Default(TServerStatusEntry);
  System.TMonitor.Enter(FLock);
  try
    Result.Kind := FKind;
    Result.Command := FCommand;
    Result.Target := FTarget;
    Result.LogFile := FLogFile;
    Result.Started := FStarted;
    Result.Done := FDone;
    Result.Total := FTotal;
    Result.Timeouts := FTimeouts;
    Result.Errors := FErrors;
    AddLongestRun(Result, ANowTicks);
  finally
    System.TMonitor.Exit(FLock);
  end;
  Result.State := TServerStatusEntry.cStateReady;
  if (Result.Running > 0) or ((Result.Total > 0) and (Result.Done < Result.Total)) then
  begin
    Result.State := TServerStatusEntry.cStateWorking;
  end;
end;

{ TServerActivityObserver }

constructor TServerActivityObserver.Create(AActivity: TServerActivity; const ANext: IJsonRpcRequestObserver);
begin
  inherited Create;
  FActivity := AActivity;
  FNext := ANext;
end;

procedure TServerActivityObserver.Started(const AMethod: string);
begin
  FActivity.RequestStarted(AMethod, TThread.GetTickCount64);
  if FNext <> nil then
  begin
    FNext.Started(AMethod);
  end;
end;

procedure TServerActivityObserver.Finished(const AMethod: string; const AParams, AResult: TJSONValue;
  const AError: Exception; AQueueMs, AElapsedMs: Int64);
begin
  FActivity.RequestFinished(AError <> nil);
  if FNext <> nil then
  begin
    FNext.Finished(AMethod, AParams, AResult, AError, AQueueMs, AElapsedMs);
  end;
end;

initialization
  GShared := TServerActivity.Create;

finalization
  FreeAndNil(GShared);

end.
