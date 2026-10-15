unit Atlas.IDE.Problems.Controller;

// Probleme im Editor (#398, Rest von #528/#548): holt die Diagnosen des
// Servers (Pull) und verteilt sie auf Speicher, Zeichner und Meldungsliste.
//   - Ein Timer (250 ms) liest den Text des aktiven Editors. Hat er sich
//     geändert, wandern die Markierungen im Speicher mit (Edit). 400 ms nach
//     der letzten Änderung wird der Text abgeglichen (Sync, Hauptthread) und
//     textDocument/diagnostic im Hintergrund geholt.
//   - Bittet der Server um neues Holen (workspace/diagnostic/refresh, etwa
//     nach einem Compile mit neuen dcc-Meldungen), holt Atlas alle
//     abgeglichenen Dateien neu und übernimmt dabei auch die Compilermeldungen.
//   - Ein zweiter Thread fragt workspace/diagnostic mit Long-Polling für alle
//     anderen Projektdateien (#82).
//   - In der IDE geschlossene Dateien bekommen didClose; dann liefert sie der
//     Server wieder über workspace/diagnostic.
// Inaktive {$IFDEF}-Zweige (#615) kommen mit denselben Diagnosen. Darum holt
// der Controller auch bei ausgeschalteten Problemen, solange das Abblenden an
// ist; dann ohne Projekt-Thread, Wellenlinien und Meldungsliste. Nebenbei
// meldet er Konfiguration, Plattform und Defines der IDE an den Server
// (Atlas.IDE.Build.Target).
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
  Atlas.Core.Lsp.Session,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Store,
  Atlas.IDE.Problems.Painter,
  Atlas.IDE.Problems.MessageList,
  Atlas.IDE.Build.Target;

type
  /// <summary>Sitzung, auf Wunsch gestartet; nil, wenn keine läuft bzw. der Start scheitert.</summary>
  TAtlasProblemsSessionFunc = reference to function(AStart: Boolean): TLspSession;
  TAtlasProblemsLogProc = reference to procedure(const AMessage: string);

  TAtlasProblemsController = class
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
      FLog: TAtlasProblemsLogProc;
      procedure Deliver(const APull: TPull; const AReport: TLspDiagnosticReport);
      procedure LogLater(const AMessage: string);
    protected
      procedure Execute; override;
      procedure TerminatedSet; override;
    public
      constructor Create(ASession: TLspSession; const ADeliver: TDocumentProc; const ALog: TAtlasProblemsLogProc);
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
      FLog: TAtlasProblemsLogProc;
      procedure Deliver(const AReports: TArray<TLspDiagnosticReport>);
      procedure LogLater(const AMessage: string);
    protected
      procedure Execute; override;
      procedure TerminatedSet; override;
    public
      constructor Create(ASession: TLspSession; const ADeliver: TWorkspaceProc; const ALog: TAtlasProblemsLogProc);
      destructor Destroy; override;
    end;
  public const
    QuietMs = 400;
    DocumentTimeoutMs = 8000;
    /// <summary>Länger als Zeitbudget (3 s) und Long-Polling (5 s) des Servers.</summary>
    WorkspaceTimeoutMs = 15000;
    WorkspaceRetryMs = 15000;
  private
    FSession: TAtlasProblemsSessionFunc;
    FLog: TAtlasProblemsLogProc;
    FStore: TAtlasProblemStore;
    FPainter: TAtlasProblemsPainter;
    FList: TAtlasProblemsList;
    FTimer: TTimer;
    FWorkerSession: TLspSession;
    FDocuments: TDocumentWorker;
    FWorkspace: TWorkspaceWorker;
    // Angehaltene Threads, die noch auf eine Antwort warten; frei, sobald fertig.
    FRetired: TObjectList<TThread>;
    // Letzter gesehener bzw. zuletzt geholter Editortext je Datei (Schlüssel klein).
    FTexts: TDictionary<string, string>;
    // Version des Pufferstands je Datei (P-04): Vergleich statt des ganzen Textes.
    FVersions: TDictionary<string, Cardinal>;
    // Zuletzt aktiver Editor: beim Wechsel seinen Stand sofort an den Server (Index, #492).
    FLastFile: string;
    FPulled: TDictionary<string, string>;
    FChangedAt: Cardinal;
    FRefreshSeen: Integer;
    FPaintedVersion: Integer;
    FListedVersion: Integer;
    // Stand des Schalters ProblemsList beim letzten Aufbau der Liste.
    FListShown: Boolean;
    FListDue: Cardinal;
    FClosedCheckAt: Cardinal;
    // Nach gescheitertem Serverstart erst später wieder versuchen.
    FRetryAt: Cardinal;
    FBuildTarget: TAtlasIdeBuildTarget;
    procedure Tick(Sender: TObject);
    procedure EnsureWorkers(ASession: TLspSession);
    procedure StopWorkers(AWait: Boolean);
    procedure FreeFinished;
    procedure DeliverDocument(const APull: TPull; const AReport: TLspDiagnosticReport);
    procedure DeliverWorkspace(const AReports: TArray<TLspDiagnosticReport>);
    procedure CloseUnopened(ASession: TLspSession);
    procedure Publish;
    /// <summary>Diagnosen holen: für Probleme oder für das Abblenden inaktiver Zweige.</summary>
    function Active: Boolean;
    function ShowProblems: Boolean;
    function ShowInactive: Boolean;
    class function IsSource(const AFileName: string): Boolean; static;
    class function IsOpenInIde(const AFileName: string): Boolean; static;
  public
    constructor Create(const ASession: TAtlasProblemsSessionFunc; const ALog: TAtlasProblemsLogProc);
    destructor Destroy; override;
    /// <summary>Threads anhalten (Teil 1); danach die Verbindung schließen und WaitShutdown aufrufen.</summary>
    procedure BeginShutdown;
    /// <summary>Auf die Threads warten (Teil 2); danach darf die Sitzung enden.</summary>
    procedure WaitShutdown;
    /// <summary>Probleme an der Stelle (0-basiert) für den Hover-Tooltip; mit Abblenden auch der Hinweis
    /// „Inaktiv: Bedingung … nicht erfüllt“ eines inaktiven Zweigs (#615).</summary>
    function ProblemsAt(const AFileName: string; ALine, ACharacter: Integer): TArray<TAtlasProblem>;
    property Store: TAtlasProblemStore read FStore;
    /// <summary>Speicher des laufenden Controllers für andere Zeichner (inaktive Zweige, #615); nil ohne.</summary>
    class function Current: TAtlasProblemStore; static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Winapi.Windows,
  Vcl.Forms,
  ToolsAPI,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Strings,
  Atlas.IDE.Editor.Buffer,
  Atlas.IDE.Editor.Snapshot,
  Atlas.IDE.Settings.Store;

{ TAtlasProblemsController.TDocumentWorker }

constructor TAtlasProblemsController.TDocumentWorker.Create(ASession: TLspSession; const ADeliver: TDocumentProc;
  const ALog: TAtlasProblemsLogProc);
begin
  FSession := ASession;
  FDeliver := ADeliver;
  FLog := ALog;
  FLock := TObject.Create;
  FWake := TEvent.Create(nil, False, False, '');
  inherited Create(False);
end;

destructor TAtlasProblemsController.TDocumentWorker.Destroy;
begin
  inherited Destroy;
  FWake.Free;
  FLock.Free;
end;

procedure TAtlasProblemsController.TDocumentWorker.TerminatedSet;
begin
  inherited;
  FWake.SetEvent;
end;

procedure TAtlasProblemsController.TDocumentWorker.Add(const APulls: TArray<TPull>);
begin
  TMonitor.Enter(FLock);
  try
    FJobs := FJobs + APulls;
  finally
    TMonitor.Exit(FLock);
  end;
  FWake.SetEvent;
end;

function TAtlasProblemsController.TDocumentWorker.Idle: Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := (Length(FJobs) = 0) and (FBusy = 0);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TAtlasProblemsController.TDocumentWorker.Deliver(const APull: TPull; const AReport: TLspDiagnosticReport);
begin
  // Eigener Rahmen je Aufruf: Die Closure fängt diese Werte, nicht die Schleifenvariable.
  Queue(
    procedure
    begin
      FDeliver(APull, AReport);
    end);
end;

procedure TAtlasProblemsController.TDocumentWorker.LogLater(const AMessage: string);
begin
  Queue(
    procedure
    begin
      FLog(AMessage);
    end);
end;

procedure TAtlasProblemsController.TDocumentWorker.Execute;
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

{ TAtlasProblemsController.TWorkspaceWorker }

constructor TAtlasProblemsController.TWorkspaceWorker.Create(ASession: TLspSession; const ADeliver: TWorkspaceProc;
  const ALog: TAtlasProblemsLogProc);
begin
  FSession := ASession;
  FDeliver := ADeliver;
  FLog := ALog;
  FKnown := TDictionary<string, TLspDiagnosticReport>.Create;
  FStop := TEvent.Create(nil, True, False, '');
  inherited Create(False);
end;

destructor TAtlasProblemsController.TWorkspaceWorker.Destroy;
begin
  inherited Destroy;
  FStop.Free;
  FKnown.Free;
end;

procedure TAtlasProblemsController.TWorkspaceWorker.TerminatedSet;
begin
  inherited;
  FStop.SetEvent;
end;

procedure TAtlasProblemsController.TWorkspaceWorker.Deliver(const AReports: TArray<TLspDiagnosticReport>);
begin
  Queue(
    procedure
    begin
      FDeliver(AReports);
    end);
end;

procedure TAtlasProblemsController.TWorkspaceWorker.LogLater(const AMessage: string);
begin
  Queue(
    procedure
    begin
      FLog(AMessage);
    end);
end;

procedure TAtlasProblemsController.TWorkspaceWorker.Execute;
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
        FKnown.AddOrSetValue(TAtlasProblemStore.Key(Report.FileName), Known);
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
        // Nach einem Fehler oder einer Zeitüberschreitung länger warten: Der Server ist ausgelastet.
        FStop.WaitFor(WorkspaceRetryMs);
      end;
    end;
  end;
end;

{ TAtlasProblemsController }

var
  // Speicher des laufenden Controllers (#615).
  CurrentStore: TAtlasProblemStore = nil;

constructor TAtlasProblemsController.Create(const ASession: TAtlasProblemsSessionFunc;
  const ALog: TAtlasProblemsLogProc);
begin
  inherited Create;
  FSession := ASession;
  FLog := ALog;
  FStore := TAtlasProblemStore.Create;
  CurrentStore := FStore;
  FPainter := TAtlasProblemsPainter.Create(FStore);
  FList := TAtlasProblemsList.Create;
  FRetired := TObjectList<TThread>.Create(True);
  FTexts := TDictionary<string, string>.Create;
  FVersions := TDictionary<string, Cardinal>.Create;
  FPulled := TDictionary<string, string>.Create;
  FBuildTarget := TAtlasIdeBuildTarget.Create(
    procedure(const AMessage: string)
    begin
      FLog(AMessage);
    end);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 250;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

class function TAtlasProblemsController.Current: TAtlasProblemStore;
begin
  Result := CurrentStore;
end;

destructor TAtlasProblemsController.Destroy;
begin
  if CurrentStore = FStore then
    CurrentStore := nil;
  FTimer.Free;
  BeginShutdown;
  WaitShutdown;
  FRetired.Free;
  FBuildTarget.Free;
  FPulled.Free;
  FTexts.Free;
  FVersions.Free;
  FList.Free;
  FPainter.Free;
  FStore.Free;
  inherited Destroy;
end;

procedure TAtlasProblemsController.BeginShutdown;
begin
  StopWorkers(False);
end;

procedure TAtlasProblemsController.WaitShutdown;
var
  Thread: TThread;
begin
  for Thread in FRetired do
  begin
    Thread.WaitFor;
    TThread.RemoveQueuedEvents(Thread);
  end;
  FRetired.Clear;
  FBuildTarget.Stop(True);
  // Die nächste Sitzung beginnt ohne Stände der alten.
  FPulled.Clear;
  FRefreshSeen := 0;
end;

procedure TAtlasProblemsController.StopWorkers(AWait: Boolean);
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
  FBuildTarget.Stop(False);
  if AWait then
    WaitShutdown;
end;

procedure TAtlasProblemsController.FreeFinished;
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

procedure TAtlasProblemsController.EnsureWorkers(ASession: TLspSession);
begin
  if (FWorkerSession <> nil) and (FWorkerSession <> ASession) then
    StopWorkers(False);
  // Neue Sitzung, etwa nach einem Serverneustart (#393): Diagnosen aller Dateien neu holen.
  if FWorkerSession <> ASession then
    FPulled.Clear;
  if FDocuments = nil then
    FDocuments := TDocumentWorker.Create(ASession, DeliverDocument, FLog);
  // Andere Projektdateien nur für die Probleme; das Abblenden braucht nur geöffnete.
  if (FWorkspace = nil) and ShowProblems then
    FWorkspace := TWorkspaceWorker.Create(ASession, DeliverWorkspace, FLog)
  else if (FWorkspace <> nil) and not ShowProblems then
  begin
    FWorkspace.Terminate;
    FRetired.Add(FWorkspace);
    FWorkspace := nil;
  end;
  FWorkerSession := ASession;
end;

function TAtlasProblemsController.Active: Boolean;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := Settings.Enabled and (Settings.Problems or Settings.InactiveDim);
end;

function TAtlasProblemsController.ShowProblems: Boolean;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := Settings.Enabled and Settings.Problems;
end;

function TAtlasProblemsController.ShowInactive: Boolean;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := Settings.Enabled and Settings.InactiveDim;
end;

class function TAtlasProblemsController.IsSource(const AFileName: string): Boolean;
var
  Extension: string;
begin
  Extension := LowerCase(ExtractFileExt(AFileName));
  Result := (Extension = '.pas') or (Extension = '.dpr') or (Extension = '.dpk') or (Extension = '.inc') or
    (Extension = '.lpr');
end;

class function TAtlasProblemsController.IsOpenInIde(const AFileName: string): Boolean;
var
  Modules: IOTAModuleServices;
begin
  Result := Supports(BorlandIDEServices, IOTAModuleServices, Modules) and (Modules.FindModule(AFileName) <> nil);
end;

procedure TAtlasProblemsController.Tick(Sender: TObject);
var
  Editors: IOTAEditorServices;
  View: IOTAEditView;
  Session: TLspSession;
  FileName, Key, Text, Known, Other, OtherText: string;
  Refresh, Changed: Boolean;
  Pull: TPull;
  Pulls: TArray<TPull>;
  Snapshot: TAtlasEditorSnapshot;
  KnownVersion: Cardinal;
begin
  // Durch die Sicherung abgeschaltet (#493).
  if TAtlasGuard.Disabled(TAtlasFeature.Problems) then
    Exit;
  try
    FreeFinished;
    if not Active then
    begin
      if (FDocuments <> nil) or (FWorkspace <> nil) then
        StopWorkers(False);
      FStore.Clear;
      FTexts.Clear;
      FVersions.Clear;
      FPulled.Clear;
      Publish;
      Exit;
    end;
    View := nil;
    // Ohne Fokus ändert sich der Puffer nur über Neuladen, das den Stand ohnehin als veraltet markiert:
    // dann weder Puffer lesen noch abgleichen (P-04). Freigeben, Stoppen und Veröffentlichen laufen weiter.
    if Application.Active and Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
      View := Editors.TopView;
    if (View <> nil) and (View.Buffer <> nil) and IsSource(View.Buffer.FileName) then
    begin
      FileName := View.Buffer.FileName;
      Key := TAtlasProblemStore.Key(FileName);
      // Gemeinsamer Pufferstand (P-04): gelesen nur nach einer Änderung.
      Snapshot := TAtlasEditorSnapshots.Get(View);
      Text := Snapshot.Text;
      // Markierungen wandern mit, bevor neue Diagnosen da sind.
      if not FVersions.TryGetValue(Key, KnownVersion) or (KnownVersion <> Snapshot.Version) then
      begin
        FVersions.AddOrSetValue(Key, Snapshot.Version);
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
        // Konfiguration oder Plattform gewechselt, Defines geändert (#615).
        FBuildTarget.Tick(Session, GetTickCount);
        // Editor gewechselt: Getipptes der vorigen Unit sofort senden, nicht erst bei der Rückkehr.
        // Sonst fehlt eine neue Deklaration in der anderen Unit (Index nach der Tipp-Pause, #492).
        if (FLastFile <> '') and not SameText(FLastFile, FileName) then
        begin
          if FDocuments.Idle then
          begin
            if FTexts.TryGetValue(TAtlasProblemStore.Key(FLastFile), OtherText) then
              Session.Sync(FLastFile, OtherText);
            FLastFile := FileName;
          end;
        end
        else
          FLastFile := FileName;
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
    begin
      FLog('Probleme: ' + E.Message);
      TAtlasGuard.Report(TAtlasFeature.Problems, E);
    end;
  end;
end;

procedure TAtlasProblemsController.CloseUnopened(ASession: TLspSession);
var
  FileName: string;
begin
  for FileName in ASession.SyncedFiles do
    if not IsOpenInIde(FileName) then
    begin
      ASession.Close(FileName);
      FTexts.Remove(TAtlasProblemStore.Key(FileName));
      FVersions.Remove(TAtlasProblemStore.Key(FileName));
      FPulled.Remove(TAtlasProblemStore.Key(FileName));
    end;
end;

procedure TAtlasProblemsController.Publish;
var
  Show: Boolean;
begin
  if FStore.Version <> FPaintedVersion then
  begin
    FPaintedVersion := FStore.Version;
    TAtlasProblemsPainter.Invalidate;
    FListDue := GetTickCount + 800;
  end;
  Show := Active and TAtlasIdeSettings.Current.ProblemsList;
  if (Show <> FListShown) or ((FListedVersion <> FStore.Version) and (GetTickCount >= FListDue)) then
  begin
    FListedVersion := FStore.Version;
    FListShown := Show;
    if Show then
      FList.Update(FStore)
    else
      FList.Clear;
  end;
end;

procedure TAtlasProblemsController.DeliverDocument(const APull: TPull; const AReport: TLspDiagnosticReport);
var
  Current: string;
begin
  if not Active or AReport.Unchanged then
    Exit;
  FStore.Update(APull.FileName, APull.Text, True, AReport.Problems, AReport.ResultId, APull.ReplaceCompiler);
  // Inzwischen weitergetippt: Positionen auf den aktuellen Text bringen.
  if FTexts.TryGetValue(TAtlasProblemStore.Key(APull.FileName), Current) and (Current <> APull.Text) then
    FStore.Edit(APull.FileName, Current);
end;

procedure TAtlasProblemsController.DeliverWorkspace(const AReports: TArray<TLspDiagnosticReport>);
var
  Report: TLspDiagnosticReport;
begin
  if not ShowProblems then
    Exit;
  for Report in AReports do
    // Abgeglichene Dateien kommen über textDocument/diagnostic.
    if not FTexts.ContainsKey(TAtlasProblemStore.Key(Report.FileName)) then
      FStore.Update(Report.FileName, '', False, Report.Problems, Report.ResultId, True);
end;

function TAtlasProblemsController.ProblemsAt(const AFileName: string; ALine, ACharacter: Integer): TArray<TAtlasProblem>;
var
  Problem: TAtlasProblem;
begin
  Result := nil;
  if ShowProblems then
    Result := FStore.At(AFileName, ALine, ACharacter);
  if not ShowInactive then
    Exit;
  for Problem in FStore.InactiveAt(AFileName, ALine, ACharacter) do
  begin
    Result := Result + [Problem];
    // Hinweis in der Sprache des Plugins statt der Meldung des Servers.
    Result[High(Result)].Message := Problem.InactiveHint(TAtlasStrings.Text(TAtlasTextId.InactiveCondition),
      TAtlasStrings.Text(TAtlasTextId.InactiveTarget), TAtlasStrings.Text(TAtlasTextId.InactiveRegion));
  end;
end;

end.
