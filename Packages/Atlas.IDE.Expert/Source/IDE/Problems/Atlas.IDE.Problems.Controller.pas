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
// Inaktive {$IFDEF}-Zweige (#615) und Hinweise zu uses-Einträgen (#621) kommen
// mit denselben Diagnosen. Darum holt der Controller auch bei ausgeschalteten
// Problemen, solange eins der Abblenden an ist; dann ohne Projekt-Thread,
// Wellenlinien und Meldungsliste. Nebenbei
// meldet er Konfiguration, Plattform und Defines der IDE an den Server
// (Atlas.IDE.Build.Target).
// Zähler für die Statusleiste (#509): nach jeder Änderung des Speichers gehen
// Fehler, Warnungen und Hinweise wie in der Liste „Atlas-Probleme“ (ohne
// Compilermeldungen) an OnCounts; mit problems.statusCounter aus einmal
// AShow = False.
// Laufende Prüfung (#909, problems.live): an = 400 ms nach der letzten
// Änderung holen; aus = erst, wenn der Puffer wieder ungeändert ist (nach
// dem Speichern). Die letzte Prüfung einer Datei (Datei, Dauer, Zeitpunkt)
// steht in LastCheck für die Statuszeile des Fensters „Atlas-Prüfung“;
// Checking meldet eine laufende Anfrage für die Atlas-Statusleiste (#1155).
// Fallen Projekte weg (Projektgruppe geschlossen oder gewechselt,
// TLspSession.ProjectsRemoved), verwirft der Controller alle Befunde und holt
// neu: Pull-Diagnosen melden Dateien, die nicht mehr dazugehören, nie wieder.
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
  Atlas.Core.Problems.InlineHints,
  Atlas.IDE.Problems.Painter,
  Atlas.IDE.Problems.MessageList,
  Atlas.IDE.Build.Target;

type
  /// <summary>Sitzung, auf Wunsch gestartet; nil, wenn keine läuft bzw. der Start scheitert.</summary>
  TAtlasProblemsSessionFunc = reference to function(AStart: Boolean): TLspSession;
  TAtlasProblemsLogProc = reference to procedure(const AMessage: string);
  /// <summary>Zähler für die Statusleiste (#509); AShow False = Feld entfernen.</summary>
  TAtlasProblemCountsProc = reference to procedure(AShow: Boolean; const ACounts: TAtlasProblemCounts);

  /// <summary>Letzte Prüfung einer Datei für die Statuszeile (#909); FileName '' = noch keine.</summary>
  TAtlasProblemsCheck = record
    FileName: string;
    DurationMs: Cardinal;
    At: TDateTime;
  end;

  TAtlasProblemsController = class
  private type
    TPull = record
      FileName: string;
      Text: string;
      PreviousId: string;
      ReplaceCompiler: Boolean;
      /// <summary>Dauer der Anfrage; setzt der Thread.</summary>
      DurationMs: Cardinal;
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
    // Zähler (#509): zuletzt gemeldeter Stand.
    FCountsShown: Boolean;
    FCountsVersion: Integer;
    // Zuletzt gesehener Zähler weggefallener Projekte der Sitzung.
    FProjectsRemoved: Integer;
    class var FOnCounts: TAtlasProblemCountsProc;
    class var FLastCheck: TAtlasProblemsCheck;
    procedure PublishCounts;
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
    /// „Inaktiv: Bedingung … nicht erfüllt“ eines inaktiven Zweigs (#615) und mit DimUnusedUses der Grund eines
    /// auffälligen uses-Eintrags (#621).</summary>
    function ProblemsAt(const AFileName: string; ALine, ACharacter: Integer): TArray<TAtlasProblem>;
    /// <summary>Text zum uses-Hinweis in der Sprache des Plugins („Aus Vcl.Grids wird nichts verwendet“).</summary>
    class function UsesHint(const AProblem: TAtlasProblem): string; static;
    property Store: TAtlasProblemStore read FStore;
    /// <summary>Speicher des laufenden Controllers für andere Zeichner (inaktive Zweige, #615); nil ohne.</summary>
    class function Current: TAtlasProblemStore; static;
    /// <summary>Zähler aller Befunde in AStore wie in der Liste (#509).</summary>
    class function CountsOf(AStore: TAtlasProblemStore): TAtlasProblemCounts; static;
    /// <summary>Empfänger der Zähler (#509); setzt die Composition, nil = keiner. Im Hauptthread.</summary>
    class property OnCounts: TAtlasProblemCountsProc read FOnCounts write FOnCounts;
    /// <summary>Letzte Prüfung einer Datei (#909); im Hauptthread.</summary>
    class property LastCheck: TAtlasProblemsCheck read FLastCheck;
    /// <summary>Läuft gerade eine Prüfung (textDocument/diagnostic) des laufenden Controllers? (#1155)</summary>
    class function Checking: Boolean; static;
    /// <summary>Läuft ein Programm im Debugger? Dann ruht die Prüfung (#1241).</summary>
    class function Paused: Boolean; static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Winapi.Windows,
  Vcl.Forms,
  ToolsAPI,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.Settings;

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
  System.TMonitor.Enter(FLock);
  try
    FJobs := FJobs + APulls;
  finally
    System.TMonitor.Exit(FLock);
  end;
  FWake.SetEvent;
end;

function TAtlasProblemsController.TDocumentWorker.Idle: Boolean;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := (Length(FJobs) = 0) and (FBusy = 0);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TAtlasProblemsController.TDocumentWorker.Deliver(const APull: TPull; const AReport: TLspDiagnosticReport);
var
  Work: TThreadProcedure;
begin
  // Eigener Rahmen je Aufruf: Die Closure fängt diese Werte, nicht die Schleifenvariable.
  Work :=
    procedure
    begin
      FDeliver(APull, AReport);
    end;
  Queue(Work);
end;

procedure TAtlasProblemsController.TDocumentWorker.LogLater(const AMessage: string);
var
  Work: TThreadProcedure;
begin
  Work :=
    procedure
    begin
      FLog(AMessage);
    end;
  Queue(Work);
end;

procedure TAtlasProblemsController.TDocumentWorker.Execute;
var
  Jobs: TArray<TPull>;
  Job, Done: TPull;
  Report: TLspDiagnosticReport;
  Started: Cardinal;
begin
  while not Terminated do
  begin
    FWake.WaitFor(1000);
    System.TMonitor.Enter(FLock);
    try
      Jobs := FJobs;
      FJobs := nil;
      if Length(Jobs) > 0 then
        FBusy := 1;
    finally
      System.TMonitor.Exit(FLock);
    end;
    for Job in Jobs do
    begin
      if Terminated then
        Break;
      try
        Started := TThread.GetTickCount;
        Report := FSession.DocumentDiagnostics(Job.FileName, Job.PreviousId, DocumentTimeoutMs);
        // Kopie: Die Schleifenvariable ist nicht zuweisbar.
        Done := Job;
        Done.DurationMs := TThread.GetTickCount - Started;
        Deliver(Done, Report);
      except
        on E: Exception do
          LogLater('Probleme: ' + ExtractFileName(Job.FileName) + ': ' + E.Message);
      end;
    end;
    System.TMonitor.Enter(FLock);
    try
      FBusy := 0;
    finally
      System.TMonitor.Exit(FLock);
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
var
  Work: TThreadProcedure;
begin
  Work :=
    procedure
    begin
      FDeliver(AReports);
    end;
  Queue(Work);
end;

procedure TAtlasProblemsController.TWorkspaceWorker.LogLater(const AMessage: string);
var
  Work: TThreadProcedure;
begin
  Work :=
    procedure
    begin
      FLog(AMessage);
    end;
  Queue(Work);
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
  // Laufender Controller für Checking (#1155).
  CurrentController: TAtlasProblemsController = nil;

constructor TAtlasProblemsController.Create(const ASession: TAtlasProblemsSessionFunc;
  const ALog: TAtlasProblemsLogProc);
begin
  inherited Create;
  FSession := ASession;
  FLog := ALog;
  FStore := TAtlasProblemStore.Create;
  CurrentStore := FStore;
  CurrentController := Self;
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

class function TAtlasProblemsController.Checking: Boolean;
begin
  Result := (CurrentController <> nil) and (CurrentController.FDocuments <> nil) and
    not CurrentController.FDocuments.Idle;
end;

class function TAtlasProblemsController.Paused: Boolean;
var
  Debugger: IOTADebuggerServices;
begin
  Result := Supports(BorlandIDEServices, IOTADebuggerServices, Debugger) and (Debugger.ProcessCount > 0);
end;

destructor TAtlasProblemsController.Destroy;
begin
  if CurrentStore = FStore then
    CurrentStore := nil;
  if CurrentController = Self then
    CurrentController := nil;
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
  Result := Settings.Enabled and (Settings.Problems or Settings.InactiveDim or Settings.DimUnusedUses);
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
    // Bestätigte Compilermeldungen zusammenführen (problems.compilerMerge, #1024); ändert nur bei Wechsel.
    FStore.CompilerMerge := not SameText(TAtlasIdeSettings.Current.ProblemsCompilerMerge, 'both');
    // Während des Debuggens ruht die Prüfung (#1241): keine Anfragen, keine Hintergrundprüfung; danach geht es weiter.
    if Paused then
    begin
      if (FDocuments <> nil) or (FWorkspace <> nil) then
        StopWorkers(False);
      Exit;
    end;
    // Projektgruppe geschlossen oder gewechselt: Pull-Diagnosen melden weggefallene Dateien nie mehr, ihre
    // Befunde blieben sonst im Speicher und im Fenster „Atlas-Prüfung“. Alles verwerfen und neu holen.
    Session := FSession(False);
    if (Session <> nil) and (Session.ProjectsRemoved <> FProjectsRemoved) then
    begin
      FProjectsRemoved := Session.ProjectsRemoved;
      FLog('Projekte weggefallen: Befunde verworfen, Prüfung neu');
      StopWorkers(False);
      FStore.Clear;
      FTexts.Clear;
      FVersions.Clear;
      FPulled.Clear;
      Publish;
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
        // Ohne laufende Prüfung erst nach dem Speichern (Puffer wieder ungeändert).
        if Changed and not TAtlasIdeSettings.Current.ProblemsLive and View.Buffer.IsModified then
          Changed := False;
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

class function TAtlasProblemsController.CountsOf(AStore: TAtlasProblemStore): TAtlasProblemCounts;
var
  FileName: string;
  All: TArray<TAtlasProblem>;
begin
  All := nil;
  if AStore <> nil then
    for FileName in AStore.Files do
      All := All + AStore.ForFile(FileName);
  Result := TAtlasInlineDiagnostics.Counts(All);
end;

procedure TAtlasProblemsController.PublishCounts;
var
  Show: Boolean;
begin
  if not Assigned(FOnCounts) then
    Exit;
  Show := Active and TAtlasIdeSettings.ProblemsStatusCounterOn;
  if (Show = FCountsShown) and (not Show or (FCountsVersion = FStore.Version)) then
    Exit;
  FCountsShown := Show;
  FCountsVersion := FStore.Version;
  if Show then
    FOnCounts(True, CountsOf(FStore))
  else
    FOnCounts(False, Default(TAtlasProblemCounts));
end;

procedure TAtlasProblemsController.Publish;
var
  Show: Boolean;
begin
  PublishCounts;
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
  if not Active then
    Exit;
  FLastCheck.FileName := APull.FileName;
  FLastCheck.DurationMs := APull.DurationMs;
  FLastCheck.At := Now;
  if AReport.Unchanged then
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
  Unused: Integer;
begin
  Result := nil;
  if ShowProblems then
    Result := FStore.At(AFileName, ALine, ACharacter);
  if ShowInactive then
    for Problem in FStore.InactiveAt(AFileName, ALine, ACharacter) do
    begin
      Result := Result + [Problem];
      // Hinweis in der Sprache des Plugins statt der Meldung des Servers.
      Result[High(Result)].Message := Problem.InactiveHint(TAtlasStrings.Text(TAtlasTextId.InactiveCondition),
        TAtlasStrings.Text(TAtlasTextId.InactiveTarget), TAtlasStrings.Text(TAtlasTextId.InactiveRegion));
    end;
  // uses-Einträge (#621): Grund in der Sprache des Plugins, Zahl der ungenutzten für „Alle entfernen“.
  if not TAtlasIdeSettings.DimUnusedUsesOn then
    Exit;
  Unused := Length(FStore.UnusedUses(AFileName));
  for Problem in FStore.UsesAt(AFileName, ALine, ACharacter) do
  begin
    Result := Result + [Problem];
    Result[High(Result)].Message := UsesHint(Problem);
    Result[High(Result)].UsesUnusedCount := Unused;
  end;
end;

class function TAtlasProblemsController.UsesHint(const AProblem: TAtlasProblem): string;
var
  Id: TAtlasTextId;
begin
  if AProblem.UsesState = TAtlasProblem.UsesInitialization then
    Id := TAtlasTextId.UsesInitializationHint
  else if AProblem.UsesState = TAtlasProblem.UsesAllowlist then
    Id := TAtlasTextId.UsesAllowlistHint
  else if AProblem.UsesState = TAtlasProblem.UsesImplementation then
    Id := TAtlasTextId.UsesImplementationHint
  else
    Id := TAtlasTextId.UsesUnusedHint;
  Result := TAtlasStrings.Fmt(Id, [AProblem.UsesUnit]);
end;

end.
