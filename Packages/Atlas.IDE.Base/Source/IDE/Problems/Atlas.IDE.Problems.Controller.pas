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
// Angeforderte Dateien (#1817, „Mit Atlas prüfen“ in der Projektverwaltung)
// gleicht der nächste Takt mit dem Text aus Editor bzw. Platte ab und holt sie,
// auch ohne offenen Editor.
// Projektprüfung (#1247): Der Server prüft als begrenzten Lauf; seinen Stand
// (erledigt/gesamt, Pause, Ende) liefert jede Antwort auf workspace/diagnostic,
// ProjectRun gibt ihn an die Statusleiste. Beginn und Ende des Debuggens gehen
// als atlas/workspaceCheck/pause an den Server, damit sein Lauf ruht.
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
  ToolsAPI,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Store,
  Atlas.Core.Problems.InlineHints,
  Atlas.IDE.Problems.Painter,
  Atlas.IDE.Problems.MessageList,
  Atlas.IDE.Build.Target,
  Atlas.Core.Diagnostics.Deadline;

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

  /// <summary>Abgleich mit dem Server: Threads für textDocument/diagnostic und workspace/diagnostic, gelieferte
  /// Diagnosen im Speicher. Grundlage von TAtlasProblemsController.</summary>
  TAtlasProblemsSync = class
  protected type
    TPull = record
      FileName: string;
      Text: string;
      PreviousId: string;
      ReplaceCompiler: Boolean;
      /// <summary>Dauer der Anfrage; setzt der Thread.</summary>
      DurationMs: Cardinal;
    end;
    TDocumentProc = reference to procedure(const APull: TPull; const AReport: TLspDiagnosticReport);
    TWorkspaceProc = reference to procedure(const AReports: TArray<TLspDiagnosticReport>;
      const ARun: TLspWorkspaceRun);

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
      procedure Deliver(const AReports: TArray<TLspDiagnosticReport>; const ARun: TLspWorkspaceRun);
      procedure LogLater(const AMessage: string);
      /// <summary>Stände von AReports merken; geändert gelieferte zurück.</summary>
      function Remember(const AReports: TArray<TLspDiagnosticReport>): TArray<TLspDiagnosticReport>;
    protected
      procedure Execute; override;
      procedure TerminatedSet; override;
    public
      constructor Create(ASession: TLspSession; const ADeliver: TWorkspaceProc; const ALog: TAtlasProblemsLogProc);
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
    cTickMs = 250;
    /// <summary>Abstand der Suche nach in der IDE geschlossenen, noch abgeglichenen Dateien.</summary>
    cClosedCheckMs = 5000;
    /// <summary>Nach gescheitertem Serverstart so lange warten.</summary>
    cStartRetryMs = 30000;
    /// <summary>Meldungsliste erst so lange nach der letzten Änderung des Speichers neu aufbauen.</summary>
    cListDelayMs = 800;
  protected
    FSession: TAtlasProblemsSessionFunc;
    FLog: TAtlasProblemsLogProc;
    FStore: TAtlasProblemStore;
    FWorkerSession: TLspSession;
    FDocuments: TDocumentWorker;
    FWorkspace: TWorkspaceWorker;
    // Angehaltene Threads, die noch auf eine Antwort warten; frei, sobald fertig.
    FRetired: TObjectList<TThread>;
    // Letzter gesehener bzw. zuletzt geholter Editortext je Datei (Schlüssel klein).
    FTexts: TDictionary<string, string>;
    // Version des Pufferstands je Datei (P-04): Vergleich statt des ganzen Textes.
    FVersions: TDictionary<string, Cardinal>;
    FPulled: TDictionary<string, string>;
    FRefreshSeen: Integer;
    FBuildTarget: TAtlasIdeBuildTarget;
    // Zuletzt dem Server gemeldete Debug-Pause (#1247).
    FDebugPauseSent: Boolean;
    // Stand der Projektprüfung des Servers (#1247) und wann der letzte Lauf endete (GetTickCount64, 0 = nie).
    class var FRun: TLspWorkspaceRun;
    class var FRunFinishedAt: UInt64;
    class var FLastCheck: TAtlasProblemsCheck;
    procedure EnsureWorkers(ASession: TLspSession);
    procedure StopWorkers(AWait: Boolean);
    procedure FreeFinished;
    procedure DeliverDocument(const APull: TPull; const AReport: TLspDiagnosticReport);
    procedure DeliverWorkspace(const AReports: TArray<TLspDiagnosticReport>; const ARun: TLspWorkspaceRun);
    /// <summary>Meldet dem Server Beginn und Ende des Debuggens (#1247): Die Projektprüfung ruht solange.</summary>
    procedure ReportDebugPause(APaused: Boolean);
    procedure CloseUnopened(ASession: TLspSession);
  public
    constructor Create(const ASession: TAtlasProblemsSessionFunc; const ALog: TAtlasProblemsLogProc);
    destructor Destroy; override;
    /// <summary>Threads anhalten (Teil 1); danach die Verbindung schließen und WaitShutdown aufrufen.</summary>
    procedure BeginShutdown;
    /// <summary>Auf die Threads warten (Teil 2); danach darf die Sitzung enden.</summary>
    procedure WaitShutdown;
    /// <summary>Letzte Prüfung einer Datei (#909); im Hauptthread.</summary>
    class property LastCheck: TAtlasProblemsCheck read FLastCheck;
    /// <summary>Läuft ein Programm im Debugger? Dann ruht die Prüfung (#1241).</summary>
    class function Paused: Boolean; static;
    /// <summary>Stand der Projektprüfung des Servers (#1247); AFinishedAgoMs = Zeit seit dem Ende des letzten Laufs
    /// (High(UInt64) ohne). False, solange der Server keinen Stand gemeldet hat. Im Hauptthread.</summary>
    class function ProjectRun(out ARun: TLspWorkspaceRun; out AFinishedAgoMs: UInt64): Boolean; static;
  end;

  TAtlasProblemsController = class(TAtlasProblemsSync)
  private
    FPainter: TAtlasProblemsPainter;
    FList: TAtlasProblemsList;
    FTimer: TTimer;
    // Zuletzt aktiver Editor: beim Wechsel seinen Stand sofort an den Server (Index, #492).
    FLastFile: string;
    FChangedAt: UInt64;
    FPaintedVersion: Integer;
    FListedVersion: Integer;
    // Stand des Schalters ProblemsMessageList beim letzten Aufbau der Liste.
    FListShown: Boolean;
    FListDue: TAtlasDeadline;
    FClosedCheckAt: UInt64;
    // Nach gescheitertem Serverstart erst später wieder versuchen.
    FRetryAt: TAtlasDeadline;
    // Zähler (#509): zuletzt gemeldeter Stand.
    FCountsShown: Boolean;
    FCountsVersion: Integer;
    // Zuletzt gesehener Zähler weggefallener Projekte der Sitzung.
    FProjectsRemoved: Integer;
    class var FOnCounts: TAtlasProblemCountsProc;
    procedure PublishCounts;
    procedure Tick(Sender: TObject);
    procedure Publish;
    /// <summary>Speicher und Stände verwerfen und veröffentlichen.</summary>
    procedure DropAll;
    /// <summary>Abgeschaltet oder Debugger aktiv: Threads anhalten; True, dann ruht der Takt.</summary>
    function Halted: Boolean;
    /// <summary>Projektgruppe geschlossen oder gewechselt: alles verwerfen und neu holen.</summary>
    procedure CheckProjectsRemoved;
    /// <summary>Pufferstand von AView merken; Markierungen wandern mit. Liefert den Text.</summary>
    function TrackEdit(const AView: IOTAEditView): string;
    /// <summary>Datei AKey mit Text AText jetzt holen (problems.update, Anforderung)?</summary>
    function PullDue(const AKey, AText: string; AModified: Boolean): Boolean;
    procedure Serve(ASession: TLspSession; const AView: IOTAEditView; const AFileName, AText: string);
    /// <summary>Editor gewechselt: Getipptes der vorigen Unit sofort senden (#492).</summary>
    procedure SyncPrevious(ASession: TLspSession; const AFileName: string);
    /// <summary>Diagnosen der Datei holen, wenn der Server neu gebaut hat oder die Tipp-Pause um ist.</summary>
    procedure PullIfDue(ASession: TLspSession; const AView: IOTAEditView; const AFileName, AText: string);
    /// <summary>Alle anderen abgeglichenen Dateien: Ihre Compilermeldungen können neu sein.</summary>
    function OtherPulls(ASession: TLspSession; const AFileName: string): TArray<TAtlasProblemsSync.TPull>;
    /// <summary>Angeforderte Dateien (#1817, TAtlasProblemsCheckRequest.RequestFiles) mit dem Text aus Editor bzw.
    /// Platte abgleichen und holen.</summary>
    procedure PullRequestedFiles;
  public
    constructor Create(const ASession: TAtlasProblemsSessionFunc; const ALog: TAtlasProblemsLogProc);
    destructor Destroy; override;
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
    /// <summary>Läuft gerade eine Prüfung (textDocument/diagnostic) des laufenden Controllers? (#1155)</summary>
    class function Checking: Boolean; static;
  end;

implementation

uses
  Atlas.Core.Problems.Refresh,
  Atlas.Core.Settings.ProblemsUpdate,
  System.JSON,
  Atlas.Core.Diagnostics.Guard,
  Winapi.Windows,
  Vcl.Forms,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Strings,
  Atlas.Core.Files.TextFile,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.Settings;

/// <summary>Diagnosen holen: für Probleme oder für das Abblenden inaktiver Zweige.</summary>
function ProblemsActive: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and (mSettings.Problems or mSettings.InactiveDim or mSettings.DimUnusedUses);
end;

function ShowProblems: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.Problems;
end;

function ShowInactive: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.InactiveDim;
end;

function IsSource(const AFileName: string): Boolean;
var
  mExtension: string;
begin
  mExtension := LowerCase(ExtractFileExt(AFileName));
  Result := (mExtension = '.pas') or (mExtension = '.dpr') or (mExtension = '.dpk') or (mExtension = '.inc') or
    (mExtension = '.lpr');
end;

function IsOpenInIde(const AFileName: string): Boolean;
var
  mModules: IOTAModuleServices;
begin
  Result := Supports(BorlandIDEServices, IOTAModuleServices, mModules) and (mModules.FindModule(AFileName) <> nil);
end;

{ TAtlasProblemsSync.TDocumentWorker }

constructor TAtlasProblemsSync.TDocumentWorker.Create(ASession: TLspSession; const ADeliver: TDocumentProc;
  const ALog: TAtlasProblemsLogProc);
begin
  FSession := ASession;
  FDeliver := ADeliver;
  FLog := ALog;
  FLock := TObject.Create;
  FWake := TEvent.Create(nil, False, False, '');
  inherited Create(False);
end;

destructor TAtlasProblemsSync.TDocumentWorker.Destroy;
begin
  inherited Destroy;
  FWake.Free;
  FLock.Free;
end;

procedure TAtlasProblemsSync.TDocumentWorker.TerminatedSet;
begin
  inherited;
  FWake.SetEvent;
end;

procedure TAtlasProblemsSync.TDocumentWorker.Add(const APulls: TArray<TPull>);
begin
  System.TMonitor.Enter(FLock);
  try
    FJobs := FJobs + APulls;
  finally
    System.TMonitor.Exit(FLock);
  end;
  FWake.SetEvent;
end;

function TAtlasProblemsSync.TDocumentWorker.Idle: Boolean;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := (Length(FJobs) = 0) and (FBusy = 0);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TAtlasProblemsSync.TDocumentWorker.Deliver(const APull: TPull; const AReport: TLspDiagnosticReport);
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

procedure TAtlasProblemsSync.TDocumentWorker.LogLater(const AMessage: string);
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

procedure TAtlasProblemsSync.TDocumentWorker.Execute;
var
  mJobs: TArray<TPull>;
  mJob, mDone: TPull;
  mReport: TLspDiagnosticReport;
  mStarted: UInt64;
begin
  while not Terminated do
  begin
    FWake.WaitFor(cDocumentWakeMs);
    System.TMonitor.Enter(FLock);
    try
      mJobs := FJobs;
      FJobs := nil;
      if Length(mJobs) > 0 then
      begin
        FBusy := 1;
      end;
    finally
      System.TMonitor.Exit(FLock);
    end;
    for mJob in mJobs do
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
    System.TMonitor.Enter(FLock);
    try
      FBusy := 0;
    finally
      System.TMonitor.Exit(FLock);
    end;
  end;
end;

{ TAtlasProblemsSync.TWorkspaceWorker }

constructor TAtlasProblemsSync.TWorkspaceWorker.Create(ASession: TLspSession; const ADeliver: TWorkspaceProc;
  const ALog: TAtlasProblemsLogProc);
begin
  FSession := ASession;
  FDeliver := ADeliver;
  FLog := ALog;
  FKnown := TDictionary<string, TLspDiagnosticReport>.Create;
  FStop := TEvent.Create(nil, True, False, '');
  inherited Create(False);
end;

destructor TAtlasProblemsSync.TWorkspaceWorker.Destroy;
begin
  inherited Destroy;
  FStop.Free;
  FKnown.Free;
end;

procedure TAtlasProblemsSync.TWorkspaceWorker.TerminatedSet;
begin
  inherited;
  FStop.SetEvent;
end;

procedure TAtlasProblemsSync.TWorkspaceWorker.Deliver(const AReports: TArray<TLspDiagnosticReport>;
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

procedure TAtlasProblemsSync.TWorkspaceWorker.LogLater(const AMessage: string);
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

function TAtlasProblemsSync.TWorkspaceWorker.Remember(
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

procedure TAtlasProblemsSync.TWorkspaceWorker.Execute;
var
  mChanged: TArray<TLspDiagnosticReport>;
  mStarted: UInt64;
  mRun: TLspWorkspaceRun;
begin
  while not Terminated do
  begin
    mStarted := TAtlasTicks.Now;
    try
      mChanged := Remember(FSession.WorkspaceDiagnostics(FKnown.Values.ToArray, cWorkspaceTimeoutMs, mRun));
      // Auch ohne neue Befunde: Fortschritt, Pause und Ende des Laufs für die Statusleiste (#1247).
      if (Length(mChanged) > 0) or mRun.Known then
      begin
        Deliver(mChanged, mRun);
      end;
      // Antwortet der Server sofort ohne Neues, nicht im Kreis fragen.
      if (Length(mChanged) = 0) and (TAtlasTicks.Since(mStarted) < cWorkspaceQuietMs) then
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
end;

var
  // Speicher des laufenden Controllers (#615).
  CurrentStore: TAtlasProblemStore = nil;
  // Laufender Controller für Checking (#1155).
  CurrentController: TAtlasProblemsController = nil;

{ TAtlasProblemsSync }

constructor TAtlasProblemsSync.Create(const ASession: TAtlasProblemsSessionFunc; const ALog: TAtlasProblemsLogProc);
begin
  inherited Create;
  FSession := ASession;
  FLog := ALog;
  FStore := TAtlasProblemStore.Create;
  FRetired := TObjectList<TThread>.Create(True);
  FTexts := TDictionary<string, string>.Create;
  FVersions := TDictionary<string, Cardinal>.Create;
  FPulled := TDictionary<string, string>.Create;
  FBuildTarget := TAtlasIdeBuildTarget.Create(
    procedure(const AMessage: string)
    begin
      FLog(AMessage);
    end);
end;

destructor TAtlasProblemsSync.Destroy;
begin
  BeginShutdown;
  WaitShutdown;
  FRetired.Free;
  FBuildTarget.Free;
  FPulled.Free;
  FTexts.Free;
  FVersions.Free;
  FStore.Free;
  inherited Destroy;
end;

{ TAtlasProblemsController }

constructor TAtlasProblemsController.Create(const ASession: TAtlasProblemsSessionFunc;
  const ALog: TAtlasProblemsLogProc);
begin
  inherited Create(ASession, ALog);
  CurrentStore := FStore;
  CurrentController := Self;
  FPainter := TAtlasProblemsPainter.Create(FStore);
  FList := TAtlasProblemsList.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMs;
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

class function TAtlasProblemsSync.ProjectRun(out ARun: TLspWorkspaceRun; out AFinishedAgoMs: UInt64): Boolean;
begin
  ARun := FRun;
  AFinishedAgoMs := High(UInt64);
  if FRunFinishedAt > 0 then
  begin
    AFinishedAgoMs := TThread.GetTickCount64 - FRunFinishedAt;
  end;
  Result := (CurrentController <> nil) and FRun.Known;
end;

procedure TAtlasProblemsSync.ReportDebugPause(APaused: Boolean);
var
  mSession: TLspSession;
begin
  if FDebugPauseSent = APaused then
  begin
    Exit;
  end;
  mSession := FSession(False);
  if mSession = nil then
  begin
    Exit;
  end;
  mSession.Notify('atlas/workspaceCheck/pause', TJSONObject.Create.AddPair('reason', 'debug')
    .AddPair('paused', TJSONBool.Create(APaused)));
  FDebugPauseSent := APaused;
end;

class function TAtlasProblemsSync.Paused: Boolean;
var
  mDebugger: IOTADebuggerServices;
begin
  Result := Supports(BorlandIDEServices, IOTADebuggerServices, mDebugger) and (mDebugger.ProcessCount > 0);
end;

destructor TAtlasProblemsController.Destroy;
begin
  if CurrentStore = FStore then
  begin
    CurrentStore := nil;
  end;
  if CurrentController = Self then
  begin
    CurrentController := nil;
  end;
  FTimer.Free;
  BeginShutdown;
  WaitShutdown;
  FList.Free;
  FPainter.Free;
  inherited Destroy;
end;

procedure TAtlasProblemsSync.BeginShutdown;
begin
  StopWorkers(False);
end;

procedure TAtlasProblemsSync.WaitShutdown;
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
  // Die nächste Sitzung beginnt ohne Stände der alten.
  FPulled.Clear;
  FRefreshSeen := 0;
end;

procedure TAtlasProblemsSync.StopWorkers(AWait: Boolean);
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
  begin
    WaitShutdown;
  end;
end;

procedure TAtlasProblemsSync.FreeFinished;
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

procedure TAtlasProblemsSync.EnsureWorkers(ASession: TLspSession);
begin
  if (FWorkerSession <> nil) and (FWorkerSession <> ASession) then
  begin
    StopWorkers(False);
  end;
  // Neue Sitzung, etwa nach einem Serverneustart (#393): Diagnosen aller Dateien neu holen.
  if FWorkerSession <> ASession then
  begin
    FPulled.Clear;
  end;
  if FDocuments = nil then
  begin
    FDocuments := TDocumentWorker.Create(ASession, DeliverDocument, FLog);
  end;
  // Andere Projektdateien nur für die Probleme; das Abblenden braucht nur geöffnete.
  if (FWorkspace = nil) and ShowProblems then
  begin
    FWorkspace := TWorkspaceWorker.Create(ASession, DeliverWorkspace, FLog);
  end
  else if (FWorkspace <> nil) and not ShowProblems then
  begin
    FWorkspace.Terminate;
    FRetired.Add(FWorkspace);
    FWorkspace := nil;
  end;
  FWorkerSession := ASession;
end;

procedure TAtlasProblemsController.DropAll;
begin
  FStore.Clear;
  FTexts.Clear;
  FVersions.Clear;
  FPulled.Clear;
  Publish;
end;

function TAtlasProblemsController.Halted: Boolean;
begin
  Result := not ProblemsActive;
  if Result then
  begin
    if (FDocuments <> nil) or (FWorkspace <> nil) then
    begin
      StopWorkers(False);
    end;
    DropAll;
    Exit;
  end;
  // Bestätigte Compilermeldungen zusammenführen (problems.compilerMerge, #1024); ändert nur bei Wechsel.
  FStore.CompilerMerge := not SameText(TAtlasIdeSettings.Current.ProblemsCompilerMerge, 'both');
  // Meldungen gelöschter Zeilen fallen weg statt blass auf die Folgezeile zu rutschen (#1818, editor.trackLines).
  FStore.DropDeletedLines := TAtlasIdeSettings.TrackLinesOn;
  // Während des Debuggens ruht die Prüfung (#1241): keine Anfragen, keine Hintergrundprüfung; danach geht es weiter.
  // Die Projektprüfung des Servers erfährt es eigens (#1247), sonst liefe ihr Lauf weiter.
  Result := Paused;
  ReportDebugPause(Result);
  if Result and ((FDocuments <> nil) or (FWorkspace <> nil)) then
  begin
    StopWorkers(False);
  end;
end;

procedure TAtlasProblemsController.CheckProjectsRemoved;
var
  mSession: TLspSession;
begin
  // Pull-Diagnosen melden weggefallene Dateien nie mehr, ihre Befunde blieben sonst im Speicher und im Fenster
  // „Atlas-Prüfung“.
  mSession := FSession(False);
  if (mSession = nil) or (mSession.ProjectsRemoved = FProjectsRemoved) then
  begin
    Exit;
  end;
  FProjectsRemoved := mSession.ProjectsRemoved;
  FLog('Projekte weggefallen: Befunde verworfen, Prüfung neu');
  StopWorkers(False);
  DropAll;
end;

/// <summary>Oberer Editor mit einer Quelldatei; nil ohne. Ohne Fokus ändert sich der Puffer nur über Neuladen, das
/// den Stand ohnehin als veraltet markiert: dann weder Puffer lesen noch abgleichen (P-04).</summary>
function TopSourceView: IOTAEditView;
var
  mEditors: IOTAEditorServices;
begin
  Result := nil;
  if Application.Active and Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    Result := mEditors.TopView;
  end;
  if (Result <> nil) and ((Result.Buffer = nil) or not IsSource(Result.Buffer.FileName)) then
  begin
    Result := nil;
  end;
end;

function TAtlasProblemsController.TrackEdit(const AView: IOTAEditView): string;
var
  mFileName, mKey: string;
  mSnapshot: TAtlasEditorSnapshot;
  mKnownVersion: Cardinal;
begin
  mFileName := AView.Buffer.FileName;
  mKey := TAtlasProblemStore.Key(mFileName);
  // Gemeinsamer Pufferstand (P-04): gelesen nur nach einer Änderung.
  mSnapshot := TAtlasEditorSnapshots.Get(AView);
  Result := mSnapshot.Text;
  // Markierungen wandern mit, bevor neue Diagnosen da sind.
  if not FVersions.TryGetValue(mKey, mKnownVersion) or (mKnownVersion <> mSnapshot.Version) then
  begin
    FVersions.AddOrSetValue(mKey, mSnapshot.Version);
    FTexts.AddOrSetValue(mKey, Result);
    FStore.Edit(mFileName, Result);
    FChangedAt := TAtlasTicks.Now;
  end;
end;

procedure TAtlasProblemsController.SyncPrevious(ASession: TLspSession; const AFileName: string);
var
  mOtherText: string;
begin
  // Sonst fehlt eine neue Deklaration in der anderen Unit (Index nach der Tipp-Pause, #492).
  if (FLastFile = '') or SameText(FLastFile, AFileName) then
  begin
    FLastFile := AFileName;
    Exit;
  end;
  if not FDocuments.Idle then
  begin
    Exit;
  end;
  if FTexts.TryGetValue(TAtlasProblemStore.Key(FLastFile), mOtherText) then
  begin
    ASession.Sync(FLastFile, mOtherText);
  end;
  FLastFile := AFileName;
end;

function TAtlasProblemsController.OtherPulls(ASession: TLspSession;
  const AFileName: string): TArray<TAtlasProblemsSync.TPull>;
var
  mOther, mOtherText: string;
  mPull: TPull;
begin
  Result := nil;
  for mOther in ASession.SyncedFiles do
  begin
    if not SameText(mOther, AFileName) and ASession.SyncedText(mOther, mOtherText) then
    begin
      mPull := Default(TPull);
      mPull.FileName := mOther;
      mPull.Text := mOtherText;
      mPull.ReplaceCompiler := True;
      Result := Result + [mPull];
    end;
  end;
end;

procedure TAtlasProblemsController.PullIfDue(ASession: TLspSession; const AView: IOTAEditView;
  const AFileName, AText: string);
var
  mKey: string;
  mRefresh, mChanged: Boolean;
  mPull: TPull;
  mPulls: TArray<TPull>;
begin
  mKey := TAtlasProblemStore.Key(AFileName);
  mRefresh := ASession.RefreshCount <> FRefreshSeen;
  mChanged := PullDue(mKey, AText, AView.Buffer.IsModified);
  if not (mRefresh or mChanged) or not FDocuments.Idle then
  begin
    Exit;
  end;
  TAtlasProblemsCheckRequest.Clear;
  ASession.Sync(AFileName, AText);
  FPulled.AddOrSetValue(mKey, AText);
  mPull := Default(TPull);
  mPull.FileName := AFileName;
  mPull.Text := AText;
  mPull.ReplaceCompiler := mRefresh or not FStore.Contains(AFileName);
  if not mPull.ReplaceCompiler then
  begin
    mPull.PreviousId := FStore.ResultId(AFileName);
  end;
  mPulls := TArray<TPull>.Create(mPull);
  if mRefresh then
  begin
    FRefreshSeen := ASession.RefreshCount;
    mPulls := mPulls + OtherPulls(ASession, AFileName);
  end;
  FDocuments.Add(mPulls);
end;

/// <summary>Text von AFileName: aus dem Puffer, wenn die Datei in der IDE offen ist, sonst von der Platte. False,
/// wenn sie sich nicht lesen lässt.</summary>
function RequestedText(const AFileName: string; out AText: string): Boolean;
var
  mModules: IOTAModuleServices;
  mModule: IOTAModule;
  mBuffer: IOTAEditBuffer;
  mIndex: Integer;
begin
  AText := '';
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    mModule := mModules.FindModule(AFileName);
  end;
  if mModule <> nil then
  begin
    for mIndex := 0 to mModule.ModuleFileCount - 1 do
    begin
      if Supports(mModule.ModuleFileEditors[mIndex], IOTAEditBuffer, mBuffer) and
        SameText(mBuffer.FileName, AFileName) then
      begin
        AText := TAtlasEditorBuffer.Text(mBuffer);
        Exit(True);
      end;
    end;
  end;
  try
    AText := TAtlasTextFile.LoadText(AFileName);
    Result := True;
  except
    // Fehlt oder gesperrt: Die Datei bleibt ungeprüft, die übrigen nicht.
    on EStreamError do
      Result := False;
  end;
end;

procedure TAtlasProblemsController.PullRequestedFiles;
var
  mFiles: TArray<string>;
  mSession: TLspSession;
  mFile, mText: string;
  mPull: TPull;
  mPulls: TArray<TPull>;
begin
  mFiles := TAtlasProblemsCheckRequest.TakeFiles;
  if Length(mFiles) = 0 then
  begin
    Exit;
  end;
  mSession := FSession(True);
  if mSession = nil then
  begin
    FLog('Problems: requested check dropped, no server');
    Exit;
  end;
  EnsureWorkers(mSession);
  mPulls := nil;
  for mFile in mFiles do
  begin
    if not IsSource(mFile) or not RequestedText(mFile, mText) then
    begin
      Continue;
    end;
    // Ungeöffnete Dateien schließt CloseUnopened später wieder; ihre Befunde liefert dann workspace/diagnostic.
    mSession.Sync(mFile, mText);
    FPulled.AddOrSetValue(TAtlasProblemStore.Key(mFile), mText);
    mPull := Default(TPull);
    mPull.FileName := mFile;
    mPull.Text := mText;
    mPull.ReplaceCompiler := not FStore.Contains(mFile);
    mPulls := mPulls + [mPull];
  end;
  FDocuments.Add(mPulls);
end;

function TAtlasProblemsController.PullDue(const AKey, AText: string; AModified: Boolean): Boolean;
var
  mState: TAtlasProblemsRefreshState;
  mKnown: string;
  mDelay: Integer;
begin
  mState := Default(TAtlasProblemsRefreshState);
  mState.CheckedBefore := FPulled.TryGetValue(AKey, mKnown);
  mState.Changed := not mState.CheckedBefore or (mKnown <> AText);
  mState.Modified := AModified;
  mState.QuietMs := TAtlasTicks.SinceMs(FChangedAt);
  mState.Requested := TAtlasProblemsCheckRequest.Pending;
  mDelay := TAtlasIdeSettings.Current.ProblemsLiveDelayMs;
  // Kürzere Verzögerung als der Takt: öfter nachsehen.
  FTimer.Interval := TAtlasProblemsRefresh.TickMs(mDelay);
  Result := TAtlasProblemsRefresh.Due(TAtlasProblemsUpdateSetting.Parse(TAtlasIdeSettings.Current.ProblemsUpdate),
    mState, mDelay);
end;

procedure TAtlasProblemsController.Serve(ASession: TLspSession; const AView: IOTAEditView;
  const AFileName, AText: string);
begin
  EnsureWorkers(ASession);
  // Konfiguration oder Plattform gewechselt, Defines geändert (#615).
  FBuildTarget.Tick(ASession, TAtlasTicks.Now);
  SyncPrevious(ASession, AFileName);
  PullIfDue(ASession, AView, AFileName, AText);
  if TAtlasTicks.Since(FClosedCheckAt) >= cClosedCheckMs then
  begin
    FClosedCheckAt := TAtlasTicks.Now;
    CloseUnopened(ASession);
  end;
end;

procedure TAtlasProblemsController.Tick(Sender: TObject);
var
  mView: IOTAEditView;
  mSession: TLspSession;
  mText: string;
begin
  // Durch die Sicherung abgeschaltet (#493).
  if TAtlasGuard.Disabled(TAtlasFeature.Problems) then
  begin
    Exit;
  end;
  try
    FreeFinished;
    if Halted then
    begin
      Exit;
    end;
    CheckProjectsRemoved;
    PullRequestedFiles;
    mView := TopSourceView;
    if mView <> nil then
    begin
      mText := TrackEdit(mView);
      mSession := FSession(FRetryAt.Reached);
      if mSession = nil then
      begin
        FRetryAt := TAtlasDeadline.After(cStartRetryMs);
      end
      else
      begin
        Serve(mSession, mView, mView.Buffer.FileName, mText);
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

procedure TAtlasProblemsSync.CloseUnopened(ASession: TLspSession);
var
  mFileName: string;
begin
  for mFileName in ASession.SyncedFiles do
  begin
    if not IsOpenInIde(mFileName) then
    begin
      ASession.Close(mFileName);
      FTexts.Remove(TAtlasProblemStore.Key(mFileName));
      FVersions.Remove(TAtlasProblemStore.Key(mFileName));
      FPulled.Remove(TAtlasProblemStore.Key(mFileName));
    end;
  end;
end;

class function TAtlasProblemsController.CountsOf(AStore: TAtlasProblemStore): TAtlasProblemCounts;
var
  mFileName: string;
  mAll: TArray<TAtlasProblem>;
begin
  mAll := nil;
  if AStore <> nil then
  begin
    for mFileName in AStore.Files do
    begin
      mAll := mAll + AStore.ForFile(mFileName);
    end;
  end;
  Result := TAtlasInlineDiagnostics.Counts(mAll);
end;

procedure TAtlasProblemsController.PublishCounts;
var
  mShow: Boolean;
begin
  if not Assigned(FOnCounts) then
  begin
    Exit;
  end;
  mShow := ProblemsActive and TAtlasIdeSettings.ProblemsStatusCounterOn;
  if (mShow = FCountsShown) and (not mShow or (FCountsVersion = FStore.Version)) then
  begin
    Exit;
  end;
  FCountsShown := mShow;
  FCountsVersion := FStore.Version;
  if mShow then
  begin
    FOnCounts(True, CountsOf(FStore));
  end
  else
  begin
    FOnCounts(False, Default(TAtlasProblemCounts));
  end;
end;

procedure TAtlasProblemsController.Publish;
var
  mShow: Boolean;
begin
  PublishCounts;
  if FStore.Version <> FPaintedVersion then
  begin
    FPaintedVersion := FStore.Version;
    TAtlasProblemsPainter.Invalidate;
    FListDue := TAtlasDeadline.After(cListDelayMs);
  end;
  mShow := ProblemsActive and TAtlasIdeSettings.Current.ProblemsMessageList;
  if (mShow <> FListShown) or ((FListedVersion <> FStore.Version) and FListDue.Reached) then
  begin
    FListedVersion := FStore.Version;
    FListShown := mShow;
    if mShow then
    begin
      FList.Update(FStore);
    end
    else
    begin
      FList.Clear;
    end;
  end;
end;

procedure TAtlasProblemsSync.DeliverDocument(const APull: TPull; const AReport: TLspDiagnosticReport);
var
  mCurrent: string;
begin
  if not ProblemsActive then
  begin
    Exit;
  end;
  FLastCheck.FileName := APull.FileName;
  FLastCheck.DurationMs := APull.DurationMs;
  FLastCheck.At := Now;
  if AReport.Unchanged then
  begin
    Exit;
  end;
  FStore.Update(APull.FileName, APull.Text, True, AReport.Problems, AReport.ResultId, APull.ReplaceCompiler);
  // Inzwischen weitergetippt: Positionen auf den aktuellen Text bringen.
  if FTexts.TryGetValue(TAtlasProblemStore.Key(APull.FileName), mCurrent) and (mCurrent <> APull.Text) then
  begin
    FStore.Edit(APull.FileName, mCurrent);
  end;
end;

procedure TAtlasProblemsSync.DeliverWorkspace(const AReports: TArray<TLspDiagnosticReport>;
  const ARun: TLspWorkspaceRun);
var
  mReport: TLspDiagnosticReport;
begin
  if not ShowProblems then
  begin
    Exit;
  end;
  if ARun.Known then
  begin
    // Ende des Laufs merken: Die Statusleiste meldet eine Weile „fertig“.
    if FRun.Active and not ARun.Active then
    begin
      FRunFinishedAt := TThread.GetTickCount64;
    end;
    FRun := ARun;
  end;
  for mReport in AReports do
  begin
    // Abgeglichene Dateien kommen über textDocument/diagnostic.
    if not FTexts.ContainsKey(TAtlasProblemStore.Key(mReport.FileName)) then
    begin
      FStore.Update(mReport.FileName, '', False, mReport.Problems, mReport.ResultId, True);
    end;
  end;
end;

function TAtlasProblemsController.ProblemsAt(const AFileName: string; ALine,
  ACharacter: Integer): TArray<TAtlasProblem>;
var
  mProblem: TAtlasProblem;
  mUnused: Integer;
begin
  Result := nil;
  if ShowProblems then
  begin
    Result := FStore.At(AFileName, ALine, ACharacter);
  end;
  if ShowInactive then
  begin
    for mProblem in FStore.InactiveAt(AFileName, ALine, ACharacter) do
    begin
      Result := Result + [mProblem];
      // Hinweis in der Sprache des Plugins statt der Meldung des Servers.
      Result[High(Result)].Message := mProblem.InactiveHint(TAtlasStrings.Text(TAtlasTextId.InactiveCondition),
        TAtlasStrings.Text(TAtlasTextId.InactiveTarget), TAtlasStrings.Text(TAtlasTextId.InactiveRegion));
    end;
  end;
  // uses-Einträge (#621): Grund in der Sprache des Plugins, Zahl der ungenutzten für „Alle entfernen“.
  if not TAtlasIdeSettings.DimUnusedUsesOn then
  begin
    Exit;
  end;
  mUnused := Length(FStore.UnusedUses(AFileName));
  for mProblem in FStore.UsesAt(AFileName, ALine, ACharacter) do
  begin
    Result := Result + [mProblem];
    Result[High(Result)].Message := UsesHint(mProblem);
    Result[High(Result)].UsesUnusedCount := mUnused;
  end;
end;

class function TAtlasProblemsController.UsesHint(const AProblem: TAtlasProblem): string;
var
  mId: TAtlasTextId;
begin
  if AProblem.UsesState = TAtlasProblem.cUsesInitialization then
  begin
    mId := TAtlasTextId.UsesInitializationHint;
  end
  else if AProblem.UsesState = TAtlasProblem.cUsesAllowlist then
  begin
    mId := TAtlasTextId.UsesAllowlistHint;
  end
  else if AProblem.UsesState = TAtlasProblem.cUsesImplementation then
  begin
    mId := TAtlasTextId.UsesImplementationHint;
  end
  else
  begin
    mId := TAtlasTextId.UsesUnusedHint;
  end;
  Result := TAtlasStrings.Fmt(mId, [AProblem.UsesUnit]);
end;

end.
