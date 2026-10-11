unit Argus.IDE.Problems.Controller;

// Probleme im Editor (#398, Rest von #528/#548): holt die Diagnosen des
// Servers (Pull) und verteilt sie auf Speicher, Zeichner und Meldungsliste.
//   - Ein Timer (250 ms) liest den Text des aktiven Editors. Hat er sich
//     geändert, wandern die Markierungen im Speicher mit (Edit). 400 ms nach
//     der letzten Änderung wird der Text abgeglichen (Sync, Hauptthread) und
//     textDocument/diagnostic im Hintergrund geholt.
//   - Bittet der Server um neues Holen (workspace/diagnostic/refresh, etwa
//     nach einem Compile mit neuen dcc-Meldungen), holt Argus alle
//     abgeglichenen Dateien neu und übernimmt dabei auch die Compilermeldungen.
//   - Ein zweiter Thread fragt workspace/diagnostic mit Long-Polling für alle
//     anderen Projektdateien (#82).
//   - In der IDE geschlossene Dateien bekommen didClose; dann liefert sie der
//     Server wieder über workspace/diagnostic.
// Ergebnisse kommen über TThread.Queue in den Hauptthread; der Speicher wird
// nur dort benutzt. Shutdown hält die Threads an, bevor die Sitzung endet: Der
// Manager schließt dazwischen die Verbindung, damit laufende Anfragen sofort
// zurückkehren.

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections,
  Vcl.ExtCtrls,
  Argus.Core.Lsp.Session,
  Argus.Core.Problems.Contract,
  Argus.Core.Problems.Store,
  Argus.IDE.Problems.Painter,
  Argus.IDE.Problems.MessageList;

type
  /// <summary>Sitzung, auf Wunsch gestartet; nil, wenn keine läuft bzw. der Start scheitert.</summary>
  TArgusProblemsSessionFunc = reference to function(AStart: Boolean): TLspSession;
  TArgusProblemsLogProc = reference to procedure(const AMessage: string);

  TArgusProblemsController = class
  private type
    TPull = record
      FileName: string;
      Text: string;
      PreviousId: string;
      ReplaceCompiler: Boolean;
    end;
    TDocumentProc = reference to procedure(const APull: TPull; const AReport: TLspDiagnosticReport);
    TWorkspaceProc = reference to procedure(const AReports: TArray<TLspDiagnosticReport>);

    TDocumentWorker = class(TThread)
    private
      FSession: TLspSession;
      FLock: TObject;
      FJobs: TArray<TPull>;
      FWake: TEvent;
      FBusy: Integer;
      FDeliver: TDocumentProc;
      FLog: TArgusProblemsLogProc;
      procedure Deliver(const APull: TPull; const AReport: TLspDiagnosticReport);
      procedure LogLater(const AMessage: string);
    protected
      procedure Execute; override;
      procedure TerminatedSet; override;
    public
      constructor Create(ASession: TLspSession; const ADeliver: TDocumentProc; const ALog: TArgusProblemsLogProc);
      destructor Destroy; override;
      procedure Add(const APulls: TArray<TPull>);
      function Idle: Boolean;
    end;

    TWorkspaceWorker = class(TThread)
    private
      FSession: TLspSession;
      FKnown: TDictionary<string, TLspDiagnosticReport>;
      FStop: TEvent;
      FDeliver: TWorkspaceProc;
      FLog: TArgusProblemsLogProc;
      procedure Deliver(const AReports: TArray<TLspDiagnosticReport>);
      procedure LogLater(const AMessage: string);
    protected
      procedure Execute; override;
      procedure TerminatedSet; override;
    public
      constructor Create(ASession: TLspSession; const ADeliver: TWorkspaceProc; const ALog: TArgusProblemsLogProc);
      destructor Destroy; override;
    end;
  public const
    QuietMs = 400;
    DocumentTimeoutMs = 8000;
    /// <summary>Länger als Zeitbudget (3 s) und Long-Polling (5 s) des Servers.</summary>
    WorkspaceTimeoutMs = 15000;
  private
    FSession: TArgusProblemsSessionFunc;
    FLog: TArgusProblemsLogProc;
    FStore: TArgusProblemStore;
    FPainter: TArgusProblemsPainter;
    FList: TArgusProblemsList;
    FTimer: TTimer;
    FWorkerSession: TLspSession;
    FDocuments: TDocumentWorker;
    FWorkspace: TWorkspaceWorker;
    // Angehaltene Threads, die noch auf eine Antwort warten; frei, sobald fertig.
    FRetired: TObjectList<TThread>;
    // Letzter gesehener bzw. zuletzt geholter Editortext je Datei (Schlüssel klein).
    FTexts: TDictionary<string, string>;
    FPulled: TDictionary<string, string>;
    FChangedAt: Cardinal;
    FRefreshSeen: Integer;
    FPaintedVersion: Integer;
    FListedVersion: Integer;
    FListDue: Cardinal;
    FClosedCheckAt: Cardinal;
    // Nach gescheitertem Serverstart erst später wieder versuchen.
    FRetryAt: Cardinal;
    procedure Tick(Sender: TObject);
    procedure EnsureWorkers(ASession: TLspSession);
    procedure StopWorkers(AWait: Boolean);
    procedure FreeFinished;
    procedure DeliverDocument(const APull: TPull; const AReport: TLspDiagnosticReport);
    procedure DeliverWorkspace(const AReports: TArray<TLspDiagnosticReport>);
    procedure CloseUnopened(ASession: TLspSession);
    procedure Publish;
    function Active: Boolean;
    class function IsSource(const AFileName: string): Boolean; static;
    class function IsOpenInIde(const AFileName: string): Boolean; static;
  public
    constructor Create(const ASession: TArgusProblemsSessionFunc; const ALog: TArgusProblemsLogProc);
    destructor Destroy; override;
    /// <summary>Threads anhalten (Teil 1); danach die Verbindung schließen und WaitShutdown aufrufen.</summary>
    procedure BeginShutdown;
    /// <summary>Auf die Threads warten (Teil 2); danach darf die Sitzung enden.</summary>
    procedure WaitShutdown;
    /// <summary>Probleme an der Stelle (0-basiert) für den Hover-Tooltip.</summary>
    function ProblemsAt(const AFileName: string; ALine, ACharacter: Integer): TArray<TArgusProblem>;
    property Store: TArgusProblemStore read FStore;
  end;

implementation

uses
  Winapi.Windows,
  ToolsAPI,
  Argus.Core.Settings.Plugin,
  Argus.IDE.Editor.Buffer,
  Argus.IDE.Settings.Store;

{ TArgusProblemsController.TDocumentWorker }

constructor TArgusProblemsController.TDocumentWorker.Create(ASession: TLspSession; const ADeliver: TDocumentProc;
  const ALog: TArgusProblemsLogProc);
begin
  FSession := ASession;
  FDeliver := ADeliver;
  FLog := ALog;
  FLock := TObject.Create;
  FWake := TEvent.Create(nil, False, False, '');
  inherited Create(False);
end;

destructor TArgusProblemsController.TDocumentWorker.Destroy;
begin
  inherited Destroy;
  FWake.Free;
  FLock.Free;
end;

procedure TArgusProblemsController.TDocumentWorker.TerminatedSet;
begin
  inherited;
  FWake.SetEvent;
end;

procedure TArgusProblemsController.TDocumentWorker.Add(const APulls: TArray<TPull>);
begin
  TMonitor.Enter(FLock);
  try
    FJobs := FJobs + APulls;
  finally
    TMonitor.Exit(FLock);
  end;
  FWake.SetEvent;
end;

function TArgusProblemsController.TDocumentWorker.Idle: Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := (Length(FJobs) = 0) and (FBusy = 0);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TArgusProblemsController.TDocumentWorker.Deliver(const APull: TPull; const AReport: TLspDiagnosticReport);
begin
  // Eigener Rahmen je Aufruf: Die Closure fängt diese Werte, nicht die Schleifenvariable.
  Queue(
    procedure
    begin
      FDeliver(APull, AReport);
    end);
end;

procedure TArgusProblemsController.TDocumentWorker.LogLater(const AMessage: string);
begin
  Queue(
    procedure
    begin
      FLog(AMessage);
    end);
end;

procedure TArgusProblemsController.TDocumentWorker.Execute;
var
  Jobs: TArray<TPull>;
  Job: TPull;
begin
  while not Terminated do
  begin
    FWake.WaitFor(1000);
    TMonitor.Enter(FLock);
    try
      Jobs := FJobs;
      FJobs := nil;
      if Length(Jobs) > 0 then
        FBusy := 1;
    finally
      TMonitor.Exit(FLock);
    end;
    for Job in Jobs do
    begin
      if Terminated then
        Break;
      try
        Deliver(Job, FSession.DocumentDiagnostics(Job.FileName, Job.PreviousId, DocumentTimeoutMs));
      except
        on E: Exception do
          LogLater('Probleme: ' + ExtractFileName(Job.FileName) + ': ' + E.Message);
      end;
    end;
    TMonitor.Enter(FLock);
    try
      FBusy := 0;
    finally
      TMonitor.Exit(FLock);
    end;
  end;
end;

{ TArgusProblemsController.TWorkspaceWorker }

constructor TArgusProblemsController.TWorkspaceWorker.Create(ASession: TLspSession; const ADeliver: TWorkspaceProc;
  const ALog: TArgusProblemsLogProc);
begin
  FSession := ASession;
  FDeliver := ADeliver;
  FLog := ALog;
  FKnown := TDictionary<string, TLspDiagnosticReport>.Create;
  FStop := TEvent.Create(nil, True, False, '');
  inherited Create(False);
end;

destructor TArgusProblemsController.TWorkspaceWorker.Destroy;
begin
  inherited Destroy;
  FStop.Free;
  FKnown.Free;
end;

procedure TArgusProblemsController.TWorkspaceWorker.TerminatedSet;
begin
  inherited;
  FStop.SetEvent;
end;

procedure TArgusProblemsController.TWorkspaceWorker.Deliver(const AReports: TArray<TLspDiagnosticReport>);
begin
  Queue(
    procedure
    begin
      FDeliver(AReports);
    end);
end;

procedure TArgusProblemsController.TWorkspaceWorker.LogLater(const AMessage: string);
begin
  Queue(
    procedure
    begin
      FLog(AMessage);
    end);
end;

procedure TArgusProblemsController.TWorkspaceWorker.Execute;
var
  Reports, Changed: TArray<TLspDiagnosticReport>;
  Report, Known: TLspDiagnosticReport;
  Started: Cardinal;
begin
  while not Terminated do
  begin
    Started := GetTickCount;
    try
      Reports := FSession.WorkspaceDiagnostics(FKnown.Values.ToArray, WorkspaceTimeoutMs);
      Changed := nil;
      for Report in Reports do
      begin
        Known := Default(TLspDiagnosticReport);
        Known.FileName := Report.FileName;
        Known.ResultId := Report.ResultId;
        FKnown.AddOrSetValue(TArgusProblemStore.Key(Report.FileName), Known);
        if not Report.Unchanged then
          Changed := Changed + [Report];
      end;
      if Length(Changed) > 0 then
        Deliver(Changed);
      // Antwortet der Server sofort ohne Neues, nicht im Kreis fragen.
      if (Length(Changed) = 0) and (GetTickCount - Started < 1000) then
        FStop.WaitFor(1000);
    except
      on E: Exception do
      begin
        if not Terminated then
          LogLater('Probleme (Projekt): ' + E.Message);
        FStop.WaitFor(3000);
      end;
    end;
  end;
end;

{ TArgusProblemsController }

constructor TArgusProblemsController.Create(const ASession: TArgusProblemsSessionFunc;
  const ALog: TArgusProblemsLogProc);
begin
  inherited Create;
  FSession := ASession;
  FLog := ALog;
  FStore := TArgusProblemStore.Create;
  FPainter := TArgusProblemsPainter.Create(FStore);
  FList := TArgusProblemsList.Create;
  FRetired := TObjectList<TThread>.Create(True);
  FTexts := TDictionary<string, string>.Create;
  FPulled := TDictionary<string, string>.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 250;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TArgusProblemsController.Destroy;
begin
  FTimer.Free;
  BeginShutdown;
  WaitShutdown;
  FRetired.Free;
  FPulled.Free;
  FTexts.Free;
  FList.Free;
  FPainter.Free;
  FStore.Free;
  inherited Destroy;
end;

procedure TArgusProblemsController.BeginShutdown;
begin
  StopWorkers(False);
end;

procedure TArgusProblemsController.WaitShutdown;
var
  Thread: TThread;
begin
  for Thread in FRetired do
  begin
    Thread.WaitFor;
    TThread.RemoveQueuedEvents(Thread);
  end;
  FRetired.Clear;
  // Die nächste Sitzung beginnt ohne Stände der alten.
  FPulled.Clear;
  FRefreshSeen := 0;
end;

procedure TArgusProblemsController.StopWorkers(AWait: Boolean);
begin
  if FDocuments <> nil then
  begin
    FDocuments.Terminate;
    FRetired.Add(FDocuments);
    FDocuments := nil;
  end;
  if FWorkspace <> nil then
  begin
    FWorkspace.Terminate;
    FRetired.Add(FWorkspace);
    FWorkspace := nil;
  end;
  FWorkerSession := nil;
  if AWait then
    WaitShutdown;
end;

procedure TArgusProblemsController.FreeFinished;
var
  Index: Integer;
begin
  for Index := FRetired.Count - 1 downto 0 do
    if FRetired[Index].Finished then
    begin
      TThread.RemoveQueuedEvents(FRetired[Index]);
      FRetired.Delete(Index);
    end;
end;

procedure TArgusProblemsController.EnsureWorkers(ASession: TLspSession);
begin
  if (FWorkerSession <> nil) and (FWorkerSession <> ASession) then
    StopWorkers(False);
  if FDocuments = nil then
    FDocuments := TDocumentWorker.Create(ASession, DeliverDocument, FLog);
  if FWorkspace = nil then
    FWorkspace := TWorkspaceWorker.Create(ASession, DeliverWorkspace, FLog);
  FWorkerSession := ASession;
end;

function TArgusProblemsController.Active: Boolean;
var
  Settings: TArgusPluginSettings;
begin
  Settings := TArgusIdeSettings.Current;
  Result := Settings.Enabled and Settings.Problems;
end;

class function TArgusProblemsController.IsSource(const AFileName: string): Boolean;
var
  Extension: string;
begin
  Extension := LowerCase(ExtractFileExt(AFileName));
  Result := (Extension = '.pas') or (Extension = '.dpr') or (Extension = '.dpk') or (Extension = '.inc') or
    (Extension = '.lpr');
end;

class function TArgusProblemsController.IsOpenInIde(const AFileName: string): Boolean;
var
  Modules: IOTAModuleServices;
begin
  Result := Supports(BorlandIDEServices, IOTAModuleServices, Modules) and (Modules.FindModule(AFileName) <> nil);
end;

procedure TArgusProblemsController.Tick(Sender: TObject);
var
  Editors: IOTAEditorServices;
  View: IOTAEditView;
  Session: TLspSession;
  FileName, Key, Text, Known, Other, OtherText: string;
  Refresh, Changed: Boolean;
  Pull: TPull;
  Pulls: TArray<TPull>;
begin
  try
    FreeFinished;
    if not Active then
    begin
      if (FDocuments <> nil) or (FWorkspace <> nil) then
        StopWorkers(False);
      FStore.Clear;
      FTexts.Clear;
      FPulled.Clear;
      Publish;
      Exit;
    end;
    View := nil;
    if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
      View := Editors.TopView;
    if (View <> nil) and (View.Buffer <> nil) and IsSource(View.Buffer.FileName) then
    begin
      FileName := View.Buffer.FileName;
      Key := TArgusProblemStore.Key(FileName);
      Text := TArgusEditorBuffer.Text(View.Buffer);
      // Markierungen wandern mit, bevor neue Diagnosen da sind.
      if not FTexts.TryGetValue(Key, Known) or (Known <> Text) then
      begin
        FTexts.AddOrSetValue(Key, Text);
        FStore.Edit(FileName, Text);
        FChangedAt := GetTickCount;
      end;
      Session := FSession(GetTickCount >= FRetryAt);
      if Session = nil then
        FRetryAt := GetTickCount + 30000
      else
      begin
        EnsureWorkers(Session);
        Refresh := Session.RefreshCount <> FRefreshSeen;
        Changed := not FPulled.TryGetValue(Key, Known) or (Known <> Text);
        if (Refresh or (Changed and (GetTickCount - FChangedAt >= QuietMs))) and FDocuments.Idle then
        begin
          Session.Sync(FileName, Text);
          FPulled.AddOrSetValue(Key, Text);
          Pull.FileName := FileName;
          Pull.Text := Text;
          Pull.ReplaceCompiler := Refresh or not FStore.Contains(FileName);
          if Pull.ReplaceCompiler then
            Pull.PreviousId := ''
          else
            Pull.PreviousId := FStore.ResultId(FileName);
          Pulls := [Pull];
          if Refresh then
          begin
            FRefreshSeen := Session.RefreshCount;
            // Alle anderen abgeglichenen Dateien auch: Ihre Compilermeldungen können neu sein.
            for Other in Session.SyncedFiles do
              if not SameText(Other, FileName) and Session.SyncedText(Other, OtherText) then
              begin
                Pull.FileName := Other;
                Pull.Text := OtherText;
                Pull.PreviousId := '';
                Pull.ReplaceCompiler := True;
                Pulls := Pulls + [Pull];
              end;
          end;
          FDocuments.Add(Pulls);
        end;
        if GetTickCount - FClosedCheckAt >= 5000 then
        begin
          FClosedCheckAt := GetTickCount;
          CloseUnopened(Session);
        end;
      end;
    end;
    Publish;
  except
    on E: Exception do
      FLog('Probleme: ' + E.Message);
  end;
end;

procedure TArgusProblemsController.CloseUnopened(ASession: TLspSession);
var
  FileName: string;
begin
  for FileName in ASession.SyncedFiles do
    if not IsOpenInIde(FileName) then
    begin
      ASession.Close(FileName);
      FTexts.Remove(TArgusProblemStore.Key(FileName));
      FPulled.Remove(TArgusProblemStore.Key(FileName));
    end;
end;

procedure TArgusProblemsController.Publish;
begin
  if FStore.Version <> FPaintedVersion then
  begin
    FPaintedVersion := FStore.Version;
    TArgusProblemsPainter.Invalidate;
    FListDue := GetTickCount + 800;
  end;
  if (FListedVersion <> FStore.Version) and (GetTickCount >= FListDue) then
  begin
    FListedVersion := FStore.Version;
    if Active then
      FList.Update(FStore)
    else
      FList.Clear;
  end;
end;

procedure TArgusProblemsController.DeliverDocument(const APull: TPull; const AReport: TLspDiagnosticReport);
var
  Current: string;
begin
  if not Active or AReport.Unchanged then
    Exit;
  FStore.Update(APull.FileName, APull.Text, True, AReport.Problems, AReport.ResultId, APull.ReplaceCompiler);
  // Inzwischen weitergetippt: Positionen auf den aktuellen Text bringen.
  if FTexts.TryGetValue(TArgusProblemStore.Key(APull.FileName), Current) and (Current <> APull.Text) then
    FStore.Edit(APull.FileName, Current);
end;

procedure TArgusProblemsController.DeliverWorkspace(const AReports: TArray<TLspDiagnosticReport>);
var
  Report: TLspDiagnosticReport;
begin
  if not Active then
    Exit;
  for Report in AReports do
    // Abgeglichene Dateien kommen über textDocument/diagnostic.
    if not FTexts.ContainsKey(TArgusProblemStore.Key(Report.FileName)) then
      FStore.Update(Report.FileName, '', False, Report.Problems, Report.ResultId, True);
end;

function TArgusProblemsController.ProblemsAt(const AFileName: string; ALine, ACharacter: Integer): TArray<TArgusProblem>;
begin
  if Active then
    Result := FStore.At(AFileName, ALine, ACharacter)
  else
    Result := nil;
end;

end.
