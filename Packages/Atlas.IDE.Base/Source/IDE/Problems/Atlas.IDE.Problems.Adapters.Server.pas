unit Atlas.IDE.Problems.Adapters.Server;

// Der Server für den Ablauf der Probleme (IAtlasProblemsServer, #398): die
// Sitzung des Plugins und zwei Threads.
//   - Der Dokument-Thread arbeitet die Aufträge an textDocument/diagnostic ab.
//   - Der Projekt-Thread fragt workspace/diagnostic mit Long-Polling für alle
//     anderen Projektdateien (#82) und liefert auch ohne neue Befunde den Stand
//     der Projektprüfung des Servers (#1247).
// Antworten kommen über TThread.Queue des jeweiligen Threads in den
// Hauptthread; beim Anhalten verwirft RemoveQueuedEvents, was noch wartet.
// Angehaltene Threads warten oft noch auf eine Antwort: Sie bleiben, bis sie
// fertig sind (Collect) bzw. bis WaitStopped auf sie wartet. Der Manager
// schließt dazwischen die Verbindung, damit laufende Anfragen sofort
// zurückkehren. Nebenbei meldet UpdateTarget Konfiguration, Plattform und
// Defines der IDE an den Server (Atlas.IDE.Build.Target).
// Nur die Kompositionswurzel legt den Adapter an
// (Atlas.IDE.CodeInsight.Composition.IdeAdapters).

interface

uses
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Problems.Contract.Sync,
  Atlas.IDE.Build.Target,
  Atlas.IDE.Problems.Controller;

type
  TAtlasIdeProblemsServer = class(TInterfacedObject, IAtlasProblemsServer)
  private type
    TDocumentWorker = class(TThread)
    private
      FSession: TLspSession;
      FLock: TObject;
      FJobs: TAtlasProblemsPulls;
      FWake: TEvent;
      FBusy: Integer;
      FDeliver: TAtlasProblemsDocumentProc;
      FLog: TAtlasProblemsLogProc;
      procedure Deliver(const APull: TAtlasProblemsPull; const AReport: TLspDiagnosticReport);
      procedure LogLater(const AMessage: string);
      /// <summary>Wartende Aufträge übernehmen; setzt dabei „in Arbeit“.</summary>
      function TakeJobs: TAtlasProblemsPulls;
      procedure SetIdle;
    protected
      procedure Execute; override;
      procedure TerminatedSet; override;
    public
      constructor Create(ASession: TLspSession; const ADeliver: TAtlasProblemsDocumentProc;
        const ALog: TAtlasProblemsLogProc);
      destructor Destroy; override;
      procedure Add(const APulls: TAtlasProblemsPulls);
      function Idle: Boolean;
    end;

    TWorkspaceWorker = class(TThread)
    private
      FSession: TLspSession;
      FKnown: TDictionary<string, TLspDiagnosticReport>;
      FStop: TEvent;
      FDeliver: TAtlasProblemsWorkspaceProc;
      FLog: TAtlasProblemsLogProc;
      procedure Deliver(const AReports: TArray<TLspDiagnosticReport>; const ARun: TLspWorkspaceRun);
      procedure LogLater(const AMessage: string);
      /// <summary>Stände von AReports merken; geändert gelieferte zurück.</summary>
      function Remember(const AReports: TArray<TLspDiagnosticReport>): TArray<TLspDiagnosticReport>;
      /// <summary>Eine Frage an den Server; liefert, ob Neues kam.</summary>
      function Ask: Boolean;
    protected
      procedure Execute; override;
      procedure TerminatedSet; override;
    public
      constructor Create(ASession: TLspSession; const ADeliver: TAtlasProblemsWorkspaceProc;
        const ALog: TAtlasProblemsLogProc);
      destructor Destroy; override;
    end;
  public const
    cDocumentTimeoutMs = 8000;
    /// <summary>Länger als Zeitbudget (3 s) und Long-Polling (5 s) des Servers.</summary>
    cWorkspaceTimeoutMs = 15000;
    cWorkspaceRetryMs = 15000;
    /// <summary>Höchste Wartezeit des Holthreads auf neue Aufträge; danach sieht er nach, ob er enden soll.</summary>
    cDocumentWakeMs = 1000;
    /// <summary>Antwortet der Server schneller ohne Neues, wartet der Projektthread so lange vor der nächsten Frage.
    /// </summary>
    cWorkspaceQuietMs = 1000;
  private
    FSessionFunc: TAtlasProblemsSessionFunc;
    FDeliverDocument: TAtlasProblemsDocumentProc;
    FDeliverWorkspace: TAtlasProblemsWorkspaceProc;
    FLog: TAtlasProblemsLogProc;
    // Sitzung des letzten Connect und ihre Kennung (wechselt mit dem Objekt).
    FSession: TLspSession;
    FSessionId: Integer;
    FDocuments: TDocumentWorker;
    FWorkspace: TWorkspaceWorker;
    // Angehaltene Threads, die noch auf eine Antwort warten; frei, sobald fertig.
    FRetired: TObjectList<TThread>;
    FBuildTarget: TAtlasIdeBuildTarget;
    procedure Retire(AThread: TThread);
  public
    /// <summary>ASession liefert die Sitzung des Plugins; Antworten gehen an ADeliverDocument bzw.
    /// ADeliverWorkspace, Fehler der Threads an ALog (alles im Hauptthread).</summary>
    constructor Create(const ASession: TAtlasProblemsSessionFunc; const ADeliverDocument: TAtlasProblemsDocumentProc;
      const ADeliverWorkspace: TAtlasProblemsWorkspaceProc; const ALog: TAtlasProblemsLogProc);
    destructor Destroy; override;
    function Connect(AStart: Boolean): Integer;
    procedure Sync(const AFileName, AText: string);
    procedure Close(const AFileName: string);
    function SyncedFiles: TArray<string>;
    function SyncedText(const AFileName: string; out AText: string): Boolean;
    function RefreshCount: Integer;
    function ProjectsRemoved: Integer;
    procedure PauseProjectCheck(APaused: Boolean);
    procedure UpdateTarget;
    procedure StartPulls(AWorkspace: Boolean);
    procedure StopPulls;
    function Pulling: Boolean;
    procedure Pull(const APulls: TAtlasProblemsPulls);
    function Idle: Boolean;
    procedure Collect;
    procedure WaitStopped;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Diagnostics.Deadline,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.Core.Problems.Store;

{ TAtlasIdeProblemsServer.TDocumentWorker }

procedure TAtlasIdeProblemsServer.TDocumentWorker.Deliver(const APull: TAtlasProblemsPull;
  const AReport: TLspDiagnosticReport);
var
  mWork: TThreadProcedure;
begin
  // Eigener Rahmen je Aufruf: Die Closure fängt diese Werte, nicht die Schleifenvariable.
  mWork :=
    procedure
    begin
      FDeliver(APull, AReport);
    end;
  Queue(mWork);
end;

procedure TAtlasIdeProblemsServer.TDocumentWorker.LogLater(const AMessage: string);
var
  mWork: TThreadProcedure;
begin
  mWork :=
    procedure
    begin
      FLog(AMessage);
    end;
  Queue(mWork);
end;

function TAtlasIdeProblemsServer.TDocumentWorker.TakeJobs: TAtlasProblemsPulls;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FJobs;
    FJobs := nil;
    if Length(Result) > 0 then
    begin
      FBusy := 1;
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TAtlasIdeProblemsServer.TDocumentWorker.SetIdle;
begin
  System.TMonitor.Enter(FLock);
  try
    FBusy := 0;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TAtlasIdeProblemsServer.TDocumentWorker.Execute;
var
  mJob, mDone: TAtlasProblemsPull;
  mReport: TLspDiagnosticReport;
  mStarted: UInt64;
begin
  try
    while not Terminated do
    begin
      FWake.WaitFor(cDocumentWakeMs);
      for mJob in TakeJobs do
      begin
        if Terminated then
        begin
          Break;
        end;
        try
          mStarted := TAtlasTicks.Now;
          mReport := FSession.DocumentDiagnostics(mJob.FileName, mJob.PreviousId, cDocumentTimeoutMs);
          // Kopie: Die Schleifenvariable ist nicht zuweisbar.
          mDone := mJob;
          mDone.DurationMs := TAtlasTicks.SinceMs(mStarted);
          Deliver(mDone, mReport);
        except
          on E: Exception do
            LogLater('Probleme: ' + ExtractFileName(mJob.FileName) + ': ' + E.Message);
        end;
      end;
      SetIdle;
    end;
  except
    on E: Exception do
    begin
      TAtlasGuard.Report(TAtlasFeature.Problems, E);
    end;
  end;
end;

procedure TAtlasIdeProblemsServer.TDocumentWorker.TerminatedSet;
begin
  inherited;
  FWake.SetEvent;
end;

constructor TAtlasIdeProblemsServer.TDocumentWorker.Create(ASession: TLspSession;
  const ADeliver: TAtlasProblemsDocumentProc; const ALog: TAtlasProblemsLogProc);
begin
  FSession := ASession;
  FDeliver := ADeliver;
  FLog := ALog;
  FLock := TObject.Create;
  FWake := TEvent.Create(nil, False, False, '');
  inherited Create(False);
end;

destructor TAtlasIdeProblemsServer.TDocumentWorker.Destroy;
begin
  inherited Destroy;
  FWake.Free;
  FLock.Free;
end;

procedure TAtlasIdeProblemsServer.TDocumentWorker.Add(const APulls: TAtlasProblemsPulls);
begin
  System.TMonitor.Enter(FLock);
  try
    FJobs := FJobs + APulls;
  finally
    System.TMonitor.Exit(FLock);
  end;
  FWake.SetEvent;
end;

function TAtlasIdeProblemsServer.TDocumentWorker.Idle: Boolean;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := (Length(FJobs) = 0) and (FBusy = 0);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

{ TAtlasIdeProblemsServer.TWorkspaceWorker }

procedure TAtlasIdeProblemsServer.TWorkspaceWorker.Deliver(const AReports: TArray<TLspDiagnosticReport>;
  const ARun: TLspWorkspaceRun);
var
  mWork: TThreadProcedure;
begin
  mWork :=
    procedure
    begin
      FDeliver(AReports, ARun);
    end;
  Queue(mWork);
end;

procedure TAtlasIdeProblemsServer.TWorkspaceWorker.LogLater(const AMessage: string);
var
  mWork: TThreadProcedure;
begin
  mWork :=
    procedure
    begin
      FLog(AMessage);
    end;
  Queue(mWork);
end;

function TAtlasIdeProblemsServer.TWorkspaceWorker.Remember(
  const AReports: TArray<TLspDiagnosticReport>): TArray<TLspDiagnosticReport>;
var
  mReport, mKnown: TLspDiagnosticReport;
begin
  Result := nil;
  for mReport in AReports do
  begin
    mKnown := Default(TLspDiagnosticReport);
    mKnown.FileName := mReport.FileName;
    mKnown.ResultId := mReport.ResultId;
    FKnown.AddOrSetValue(TAtlasProblemStore.Key(mReport.FileName), mKnown);
    if not mReport.Unchanged then
    begin
      Result := Result + [mReport];
    end;
  end;
end;

function TAtlasIdeProblemsServer.TWorkspaceWorker.Ask: Boolean;
var
  mChanged: TArray<TLspDiagnosticReport>;
  mRun: TLspWorkspaceRun;
begin
  mChanged := Remember(FSession.WorkspaceDiagnostics(FKnown.Values.ToArray, cWorkspaceTimeoutMs, mRun));
  // Auch ohne neue Befunde: Fortschritt, Pause und Ende des Laufs für die Statusleiste (#1247).
  if (Length(mChanged) > 0) or mRun.Known then
  begin
    Deliver(mChanged, mRun);
  end;
  Result := Length(mChanged) > 0;
end;

procedure TAtlasIdeProblemsServer.TWorkspaceWorker.Execute;
var
  mStarted: UInt64;
begin
  try
    while not Terminated do
    begin
      mStarted := TAtlasTicks.Now;
      try
        // Antwortet der Server sofort ohne Neues, nicht im Kreis fragen.
        if not Ask and (TAtlasTicks.Since(mStarted) < cWorkspaceQuietMs) then
        begin
          FStop.WaitFor(cWorkspaceQuietMs);
        end;
      except
        on E: Exception do
        begin
          if not Terminated then
          begin
            LogLater('Probleme (Projekt): ' + E.Message);
          end;
          // Nach einem Fehler oder einer Zeitüberschreitung länger warten: Der Server ist ausgelastet.
          FStop.WaitFor(cWorkspaceRetryMs);
        end;
      end;
    end;
  except
    on E: Exception do
    begin
      TAtlasGuard.Report(TAtlasFeature.Problems, E);
    end;
  end;
end;

procedure TAtlasIdeProblemsServer.TWorkspaceWorker.TerminatedSet;
begin
  inherited;
  FStop.SetEvent;
end;

constructor TAtlasIdeProblemsServer.TWorkspaceWorker.Create(ASession: TLspSession;
  const ADeliver: TAtlasProblemsWorkspaceProc; const ALog: TAtlasProblemsLogProc);
begin
  FSession := ASession;
  FDeliver := ADeliver;
  FLog := ALog;
  FKnown := TDictionary<string, TLspDiagnosticReport>.Create;
  FStop := TEvent.Create(nil, True, False, '');
  inherited Create(False);
end;

destructor TAtlasIdeProblemsServer.TWorkspaceWorker.Destroy;
begin
  inherited Destroy;
  FStop.Free;
  FKnown.Free;
end;

{ TAtlasIdeProblemsServer }

procedure TAtlasIdeProblemsServer.Retire(AThread: TThread);
begin
  AThread.Terminate;
  FRetired.Add(AThread);
end;

constructor TAtlasIdeProblemsServer.Create(const ASession: TAtlasProblemsSessionFunc;
  const ADeliverDocument: TAtlasProblemsDocumentProc; const ADeliverWorkspace: TAtlasProblemsWorkspaceProc;
  const ALog: TAtlasProblemsLogProc);
begin
  inherited Create;
  FSessionFunc := ASession;
  FDeliverDocument := ADeliverDocument;
  FDeliverWorkspace := ADeliverWorkspace;
  FLog := ALog;
  FRetired := TObjectList<TThread>.Create(True);
  FBuildTarget := TAtlasIdeBuildTarget.Create(
    procedure(const AMessage: string)
    begin
      FLog(AMessage);
    end);
end;

destructor TAtlasIdeProblemsServer.Destroy;
begin
  StopPulls;
  WaitStopped;
  FRetired.Free;
  FBuildTarget.Free;
  inherited Destroy;
end;

function TAtlasIdeProblemsServer.Connect(AStart: Boolean): Integer;
var
  mSession: TLspSession;
begin
  mSession := FSessionFunc(AStart);
  if mSession = nil then
  begin
    FSession := nil;
    Exit(0);
  end;
  if mSession <> FSession then
  begin
    FSession := mSession;
    Inc(FSessionId);
  end;
  Result := FSessionId;
end;

procedure TAtlasIdeProblemsServer.Sync(const AFileName, AText: string);
begin
  FSession.Sync(AFileName, AText);
end;

procedure TAtlasIdeProblemsServer.Close(const AFileName: string);
begin
  FSession.Close(AFileName);
end;

function TAtlasIdeProblemsServer.SyncedFiles: TArray<string>;
begin
  Result := FSession.SyncedFiles;
end;

function TAtlasIdeProblemsServer.SyncedText(const AFileName: string; out AText: string): Boolean;
begin
  Result := FSession.SyncedText(AFileName, AText);
end;

function TAtlasIdeProblemsServer.RefreshCount: Integer;
begin
  Result := FSession.RefreshCount;
end;

function TAtlasIdeProblemsServer.ProjectsRemoved: Integer;
begin
  Result := FSession.ProjectsRemoved;
end;

procedure TAtlasIdeProblemsServer.PauseProjectCheck(APaused: Boolean);
begin
  FSession.Notify('atlas/workspaceCheck/pause', TJSONObject.Create.AddPair('reason', 'debug')
    .AddPair('paused', TJSONBool.Create(APaused)));
end;

procedure TAtlasIdeProblemsServer.UpdateTarget;
begin
  FBuildTarget.Tick(FSession, TAtlasTicks.Now);
end;

procedure TAtlasIdeProblemsServer.StartPulls(AWorkspace: Boolean);
begin
  if FDocuments = nil then
  begin
    FDocuments := TDocumentWorker.Create(FSession, FDeliverDocument, FLog);
  end;
  if (FWorkspace = nil) and AWorkspace then
  begin
    FWorkspace := TWorkspaceWorker.Create(FSession, FDeliverWorkspace, FLog);
  end
  else if (FWorkspace <> nil) and not AWorkspace then
  begin
    Retire(FWorkspace);
    FWorkspace := nil;
  end;
end;

procedure TAtlasIdeProblemsServer.StopPulls;
begin
  if FDocuments <> nil then
  begin
    Retire(FDocuments);
    FDocuments := nil;
  end;
  if FWorkspace <> nil then
  begin
    Retire(FWorkspace);
    FWorkspace := nil;
  end;
  FBuildTarget.Stop(False);
end;

function TAtlasIdeProblemsServer.Pulling: Boolean;
begin
  Result := (FDocuments <> nil) or (FWorkspace <> nil);
end;

procedure TAtlasIdeProblemsServer.Pull(const APulls: TAtlasProblemsPulls);
begin
  FDocuments.Add(APulls);
end;

function TAtlasIdeProblemsServer.Idle: Boolean;
begin
  Result := (FDocuments = nil) or FDocuments.Idle;
end;

procedure TAtlasIdeProblemsServer.Collect;
var
  mIndex: Integer;
begin
  for mIndex := FRetired.Count - 1 downto 0 do
  begin
    if FRetired[mIndex].Finished then
    begin
      TThread.RemoveQueuedEvents(FRetired[mIndex]);
      FRetired.Delete(mIndex);
    end;
  end;
end;

procedure TAtlasIdeProblemsServer.WaitStopped;
var
  mThread: TThread;
begin
  for mThread in FRetired do
  begin
    mThread.WaitFor;
    TThread.RemoveQueuedEvents(mThread);
  end;
  FRetired.Clear;
  FBuildTarget.Stop(True);
end;

end.
