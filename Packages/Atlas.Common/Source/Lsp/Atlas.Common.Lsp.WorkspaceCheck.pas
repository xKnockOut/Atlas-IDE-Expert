unit Atlas.Common.Lsp.WorkspaceCheck;

// Projektprüfung als begrenzter Lauf (#1247). Früher rechnete jede Anfrage
// workspace/diagnostic selbst, mit Budget und Long-Polling, und hörte nie
// richtig auf: Jede Index- oder Compileränderung hob die Generation, und alle
// Units veralteten. Jetzt:
//
// - Ein eigener Thread mit niedriger Priorität prüft eine Warteschlange von
//   Dateien. Ein Lauf hat Anfang und Ende: Start (Projekt geöffnet, Index
//   fertig, Einstellungen, Klick auf „neu prüfen“) stellt alle Projektdateien
//   ein, Affected nur die betroffenen (gespeicherte Unit und die Units, die
//   sie in uses haben; nach einem Build die Dateien mit geänderten
//   Compilermeldungen). Ist die Schlange leer, ruht der Thread.
// - Run meldet Fortschritt (erledigt/gesamt) und Pausengrund für die
//   Statusleiste; workspace/diagnostic liefert nur noch gespeicherte Befunde.
// - Vorrang hat der Benutzer: Beim Tippen (TypingQuietMs nach der letzten
//   Änderung) und während textDocument/diagnostic (Foreground) beginnt keine
//   neue Datei; eine laufende Prüfung bricht ab und kommt wieder vorn in die
//   Schlange. Während des Indexaufbaus (Busy) wartet der Lauf (#647).
// - Pause: Kompilieren (atlas/compileStarted … Finished) und Debuggen
//   (atlas/workspaceCheck/pause vom Plugin, #1241). Eine Pause mit Frist
//   endet spätestens nach ihr; das ist ein Sicherheitsnetz für verlorene
//   Ende-Meldungen, keine Steuerung.
// - Jede Datei hat beim ersten Versuch eine Frist (FileLimitMs, #1220); läuft
//   sie ab, kommt die Datei ans Ende der Schlange und wird dann ohne Frist und
//   ohne Unterbrechung zu Ende geprüft. Scheitert eine Datei mit einer
//   Ausnahme, gilt sie mit leeren Befunden als geprüft (#1094); das Log nennt
//   nur ihr anonymes Kennzeichen.
//
// Zeitprofil (#1356): Jeder Lauf führt ein TCheckProfiler mit der Dauer je
// Unit (alle Versuche zusammen) und, über die Messung der Regel-Engine, je
// Regel. Profile liefert die langsamsten, Queue die wartenden Dateien und die
// älteste Wartezeit für das Fenster „Atlas-Server“.
//
// Ergebnis-Ids: "w<Sitzung>.<Nummer>:t<Zeitstempel>". Jede Berechnung bekommt
// eine neue Nummer; eine unveränderte Datei (gleicher Zeitstempel, nicht
// erzwungen) behält ihre Id und kostet nichts.

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Diagnostics,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Diagnostics.CheckProfile;

type
  /// <summary>Dateien des Projekts, die die Projektprüfung kennt.</summary>
  TWorkspaceCheckFiles = reference to function: TArray<string>;
  /// <summary>Zeitstempel einer Datei; False, wenn sie fehlt.</summary>
  TWorkspaceCheckStamp = reference to function(const AFileName: string; out AStamp: Int64): Boolean;
  /// <summary>Text einer Datei von der Platte.</summary>
  TWorkspaceCheckRead = reference to function(const AFileName: string; out AText: string): Boolean;
  /// <summary>Ist die Datei im Editor geöffnet? Dann meldet textDocument/diagnostic sie.</summary>
  TWorkspaceCheckOpen = reference to function(const AUri: string): Boolean;
  /// <summary>Befunde eines Dokuments; bricht beim Signal von ACancellation ab.</summary>
  TWorkspaceCheckDiagnose = reference to function(const ADocument: ITextDocument;
    const ACancellation: IJsonRpcCancellationToken): TJSONArray;
  /// <summary>True, solange der Symbolindex aufgebaut wird.</summary>
  TWorkspaceCheckBusy = reference to function: Boolean;
  /// <summary>Dateien, die von AFileName abhängen (uses bzw. $I).</summary>
  TWorkspaceCheckDependents = reference to function(const AFileName: string): TArray<string>;
  /// <summary>Anonymes Kennzeichen einer Datei für das Log, nie Pfad oder Name.</summary>
  TWorkspaceCheckLabel = reference to function(const AFileName: string): string;
  TWorkspaceCheckLog = reference to procedure(const AMessage: string);

  /// <summary>Stand des Laufs für Statusleiste und Diagnoselog.</summary>
  TWorkspaceCheckRun = record
    /// <summary>Nummer des Laufs; 0 = noch keiner.</summary>
    Serial: Integer;
    Active: Boolean;
    Done: Integer;
    Total: Integer;
    /// <summary>Im Lauf übersprungene Dateien (#1094).</summary>
    Skipped: Integer;
    /// <summary>Grund einer Pause: "compile", "debug", "index"; '' = keine.</summary>
    Paused: string;
    /// <summary>Dauer des laufenden bzw. letzten Laufs.</summary>
    ElapsedMs: Int64;
    function ToJson: TJSONObject;
    /// <summary>Unterscheidet sich der Stand für die Anzeige (ohne Done)?</summary>
    function StateDiffers(const AOther: TWorkspaceCheckRun): Boolean;
  end;

  /// <summary>Warteschlange der Projektprüfung für den Status (#1356).</summary>
  TWorkspaceCheckQueue = record
    /// <summary>Dateien, die noch drankommen.</summary>
    Waiting: Integer;
    /// <summary>1, während eine Datei geprüft wird, sonst 0.</summary>
    Running: Integer;
    /// <summary>Wartezeit der ältesten wartenden Datei; 0 ohne.</summary>
    OldestWaitMs: Int64;
  end;

  TLspWorkspaceCheck = class
  public const
    cDefaultFileLimitMs = 3000;
    cDefaultTypingQuietMs = 1500;
    /// <summary>Takt, in dem der Thread Hindernisse und Abbruch neu prüft.</summary>
    cSliceMs = 100;
    /// <summary>Ruhender Thread ohne Arbeit; Einreihen weckt sofort.</summary>
    cIdleWaitMs = 1000;
    cPauseCompile = 'compile';
    cPauseDebug = 'debug';
    cPauseIndex = 'index';
  private type
    TEntry = record
      FileName: string;
      /// <summary>Auch bei unverändertem Zeitstempel neu prüfen.</summary>
      Forced: Boolean;
      /// <summary>Zweiter Versuch nach abgelaufener Frist: ohne Frist, ohne Unterbrechung.</summary>
      Unlimited: Boolean;
      /// <summary>Eingereiht zu diesem Zeitpunkt auf FClock (#1356); bleibt beim erneuten Einreihen.</summary>
      Queued: Int64;
    end;

    /// <summary>Gespeicherter Befund, den Collect ausliefern will.</summary>
    TCollected = record
      Uri: string;
      Id: string;
      Items: TBytes;
    end;

    /// <summary>Rückrufe des Servers und Frist je Datei.</summary>
    THooks = record
      Files: TWorkspaceCheckFiles;
      Stamp: TWorkspaceCheckStamp;
      ReadText: TWorkspaceCheckRead;
      IsOpen: TWorkspaceCheckOpen;
      Diagnose: TWorkspaceCheckDiagnose;
      Busy: TWorkspaceCheckBusy;
      Dependents: TWorkspaceCheckDependents;
      FileLabel: TWorkspaceCheckLabel;
      Log: TWorkspaceCheckLog;
      FileLimitMs: Cardinal;
    end;

    /// <summary>Warteschlange, Projektdateien und laufende Datei. Nur unter der Sperre des Besitzers.</summary>
    TSchedule = class
    private
      FQueue: TList<TEntry>;
      FQueued: TDictionary<string, Boolean>;
      // Projektdateien des letzten Start; Affected stellt nur diese ein.
      FProject: TDictionary<string, Boolean>;
      // Datei, die der Thread gerade prüft; FInterrupt bricht sie ab.
      FCurrent: string;
      FInterrupt: Boolean;
      // Erst die erste Anfrage workspace/diagnostic startet die Prüfung; ohne Projektprüfung im Client ruht sie.
      FWanted: Boolean;
      procedure ForceQueued(const AKey: string);
    public
      constructor Create;
      destructor Destroy; override;
      /// <summary>Leert die Schlange und bricht die laufende Datei ab (erzwungener Neustart).</summary>
      procedure Restart;
      /// <summary>Bricht die laufende Datei ab; sie kommt wieder vorn in die Schlange.</summary>
      procedure InterruptCurrent;
      procedure ClearProject;
      /// <summary>False, wenn AFileName schon zum Projekt gehört.</summary>
      function AddToProject(const AFileName: string): Boolean;
      function InProject(const AFileName: string): Boolean;
      /// <summary>Stellt AFileName ein; True, wenn sie neu in der Schlange steht. Eine wartende Datei wird
      /// höchstens auf erzwungen gehoben.</summary>
      function Add(const AFileName: string; AForced: Boolean; ANow: Int64): Boolean;
      /// <summary>Nimmt den ersten Eintrag und macht ihn zur laufenden Datei.</summary>
      function TakeFirst: TEntry;
      /// <summary>Die laufende Datei ist erledigt.</summary>
      procedure Release;
      function IsQueued(const AFileName: string): Boolean;
      procedure Put(const AEntry: TEntry; AFront: Boolean);
      function Count: Integer;
      function Running: Boolean;
      function OldestWaitMs(ANow: Int64): Int64;
      property Interrupt: Boolean read FInterrupt;
      property Wanted: Boolean read FWanted write FWanted;
    end;

    /// <summary>Gespeicherte Befunde je Uri, kompakt als JSON-Text (#1237). Nur unter der Sperre des
    /// Besitzers.</summary>
    TReports = class
    private
      FReports: TDictionary<string, TBytes>;
      FIds: TDictionary<string, string>;
      FStamps: TDictionary<string, Int64>;
      FSession: Integer;
      FSerial: Integer;
    public
      constructor Create;
      destructor Destroy; override;
      procedure Put(const AUri: string; AStamp: Int64; const APacked: TBytes);
      /// <summary>True, wenn für AUri Befunde mit dem Zeitstempel AStamp gespeichert sind.</summary>
      function Unchanged(const AUri: string; AStamp: Int64): Boolean;
      /// <summary>Nicht mehr zum Projekt gehörende Dateien melden sich nie wieder; ihre Befunde verwerfen.
      /// </summary>
      procedure DropStale(ASchedule: TSchedule);
      /// <summary>Befunde, deren Id sich von APrevious unterscheidet (Referenzen, keine Kopien).</summary>
      function NewerThan(const APrevious: TDictionary<string, string>): TArray<TCollected>;
    end;

    /// <summary>Stand des Laufs und Zählerstände. Nur unter der Sperre des Besitzers.</summary>
    TProgress = record
      Run: TWorkspaceCheckRun;
      Clock: TStopwatch;
      RunComputed: Integer;
      Computed: Integer;
      Skipped: Integer;
      // Zeitprofil des Laufs (#1356); sperrt selbst.
      Profiler: TCheckProfiler;
      /// <summary>Eine Datei kommt hinzu; ohne aktiven Lauf beginnt einer.</summary>
      procedure Added;
      procedure BeginRun;
      /// <summary>Beendet einen aktiven Lauf; liefert die Zeile fürs Log, sonst ''.</summary>
      function Finish: string;
      /// <summary>Datei ohne neue Befunde erledigt.</summary>
      procedure Settle;
      procedure Stored(AFailed: Boolean);
      function Snapshot: TWorkspaceCheckRun;
      /// <summary>Dauer des laufenden Laufs, -1 ohne.</summary>
      function RunningMs: Int64;
    end;

    /// <summary>Pausen und Vorrang des Benutzers. Nur unter der Sperre des Besitzers.</summary>
    TPauses = record
      // Pausengrund -> Ende in ms auf FClock (High(Int64) = ohne Frist).
      Reasons: TDictionary<string, Int64>;
      TypedAt: Int64;
      Foreground: Integer;
      QuietMs: Cardinal;
      procedure Switch(const AReason: string; AOn: Boolean; ALimitMs: Cardinal; ANow: Int64);
      /// <summary>Erste aktive Pause; abgelaufene Pausen entfallen mit Logzeile.</summary>
      function ActivePause(ANow: Int64; const ALog: TWorkspaceCheckLog): string;
      /// <summary>Grund, jetzt keine Datei zu beginnen, '' = keiner. AShown: der Grund für die Statusleiste.
      /// </summary>
      function Hindrance(ABusy: Boolean; ANow: Int64; const ALog: TWorkspaceCheckLog; out AShown: string): string;
    end;

    /// <summary>Prüft die Schlange Datei für Datei.</summary>
    TWorker = class(TThread)
    private
      FOwner: TLspWorkspaceCheck;
      function NextEntry(out AEntry: TEntry): Boolean;
      function WaitLocked: string;
      procedure Process(const AEntry: TEntry);
      function Prepare(const AEntry: TEntry; out AUri: string; out AStamp: Int64; out AText: string): Boolean;
      function Diagnose(const AEntry: TEntry; const AUri, AText: string): TJSONArray;
      procedure Fail(const AEntry: TEntry; const AUri: string; AStamp: Int64; AError: Exception);
      procedure Requeue(const AEntry: TEntry; AFront: Boolean);
      procedure Settle;
      procedure Store(const AUri: string; AStamp: Int64; AItems: TJSONArray; AFailed: Boolean);
      function LabelOf(const AFileName: string): string;
      procedure Log(const AMessage: string);
    protected
      procedure Execute; override;
    public
      constructor Create(AOwner: TLspWorkspaceCheck);
    end;
  private
    FHooks: THooks;
    // Alles Folgende unter FLock; TMonitor.PulseAll(FLock) weckt Thread und Wartende.
    FLock: TObject;
    FClock: TStopwatch;
    FWorker: TWorker;
    FStopping: Boolean;
    // Steigt bei jeder Änderung, die Wartende sehen sollen.
    FChange: Integer;
    FSchedule: TSchedule;
    FReports: TReports;
    FProgress: TProgress;
    FPauses: TPauses;
    procedure Changed;
    procedure EnsureWorker;
    function Interrupted(AInterruptible: Boolean): Boolean;
  public
    constructor Create(const AFiles: TWorkspaceCheckFiles; const AStamp: TWorkspaceCheckStamp;
      const AReadText: TWorkspaceCheckRead; const AIsOpen: TWorkspaceCheckOpen;
      const ADiagnose: TWorkspaceCheckDiagnose);
    destructor Destroy; override;
    /// <summary>Lauf über alle Projektdateien. AForce: auch unveränderte neu prüfen (Einstellungen, Index,
    /// „neu prüfen“). Ohne Anfrage workspace/diagnostic (Want) ohne Wirkung.</summary>
    procedure Start(AForce: Boolean);
    /// <summary>Nur AFiles neu prüfen, mit AWithDependents auch die Units, die sie in uses haben bzw. die sie
    /// mit $I einbinden. Dateien außerhalb des Projekts entfallen.</summary>
    procedure Affected(const AFiles: TArray<string>; AWithDependents: Boolean);
    /// <summary>Der Client fragt nach Projektbefunden; beim ersten Mal startet der Lauf.</summary>
    procedure Want;
    /// <summary>Pause ein oder aus, ohne Frist (Debuggen).</summary>
    procedure Pause(const AReason: string; AOn: Boolean); overload;
    /// <summary>Pause mit Frist ALimitMs als Sicherheitsnetz, falls das Ende nie gemeldet wird (Kompilieren).
    /// </summary>
    procedure Pause(const AReason: string; AOn: Boolean; ALimitMs: Cardinal); overload;
    /// <summary>Der Benutzer tippt: keine neue Datei bis TypingQuietMs danach, laufende abbrechen.</summary>
    procedure Typed;
    /// <summary>Eine Vordergrundprüfung (textDocument/diagnostic) beginnt bzw. endet.</summary>
    procedure EnterForeground;
    procedure LeaveForeground;
    /// <summary>Befunde, deren Id sich von APrevious (Uri -> Id) unterscheidet, höchstens AMax; geöffnete
    /// Dateien entfallen. Gehört dem Aufrufer.</summary>
    function Collect(const APrevious: TDictionary<string, string>; AMax: Integer): TJSONArray;
    /// <summary>Wartet höchstens AWaitMs, solange ChangeCount = AChange; liefert den neuen Zähler.</summary>
    function WaitForChange(AChange: Integer; AWaitMs: Cardinal): Integer;
    function ChangeCount: Integer;
    function Run: TWorkspaceCheckRun;
    /// <summary>Zeitprofil des laufenden bzw. letzten Laufs mit den ACount langsamsten Units und Regeln.</summary>
    function Profile(ACount: Integer): TCheckRunProfile;
    /// <summary>Wartende und laufende Datei, älteste Wartezeit.</summary>
    function Queue: TWorkspaceCheckQueue;
    /// <summary>Wartet, bis die Schlange leer ist und kein Lauf mehr aktiv ist (Tests).</summary>
    function WaitIdle(ATimeoutMs: Cardinal): Boolean;
    /// <summary>Dateien unter AUnits, die von AFileName abhängen: bei .inc die einbindenden Units, sonst die
    /// Projekt-Units mit dem Unit-Namen in uses. Ohne AFileName selbst.</summary>
    class function DependentsOf(const AUnits: TArray<TUnitIndex>; const AFileName: string): TArray<string>; static;
    property Busy: TWorkspaceCheckBusy read FHooks.Busy write FHooks.Busy;
    property Dependents: TWorkspaceCheckDependents read FHooks.Dependents write FHooks.Dependents;
    property FileLabel: TWorkspaceCheckLabel read FHooks.FileLabel write FHooks.FileLabel;
    property OnLog: TWorkspaceCheckLog read FHooks.Log write FHooks.Log;
    property FileLimitMs: Cardinal read FHooks.FileLimitMs write FHooks.FileLimitMs;
    property TypingQuietMs: Cardinal read FPauses.QuietMs write FPauses.QuietMs;
    /// <summary>Tatsächlich berechnete Dateibefunde.</summary>
    property Computed: Integer read FProgress.Computed;
    /// <summary>Nach einem Fehler übersprungene Dateien (#1094).</summary>
    property Skipped: Integer read FProgress.Skipped;
  end;

  /// <summary>Entscheidet, wann ein Indexaufbau die Projektprüfung neu startet. Nach der Projektstufe sind alle
  /// Units indiziert, die das Projekt über uses erreicht; die Prüfung läuft ab da. Das Ende des Aufbaus
  /// (Suchpfade, Bibliothek) startet sie nur, wenn die Projektstufe es nicht schon getan hat. Früher begann
  /// der Lauf am Ende erzwungen von vorn und warf alles weg, was er während der Bibliotheksstufe geprüft
  /// hatte (Diagnose-Log 29.10.2026: 630 Units in 3 Minuten verworfen). Threadsicher.</summary>
  TWorkspaceCheckIndexGate = class
  private
    // 1, sobald dieser Aufbau die Prüfung neu gestartet hat.
    FStarted: Integer;
  public
    /// <summary>Ein neuer Indexaufbau beginnt.</summary>
    procedure IndexStarted;
    /// <summary>True, wenn die Prüfung jetzt neu starten soll: immer nach der Projektstufe, am Ende des
    /// Aufbaus nur, wenn die Projektstufe sie nicht gestartet hat.</summary>
    function Recheck(AProjectStage: Boolean): Boolean;
  end;

implementation

uses
  System.SyncObjs,
  Atlas.Common.Diagnostics.StackGuard,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.TextDocument,
  Atlas.Common.Lsp.CompactJson,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TWorkspaceCheckText = (ProjectCheckInterrupted, DeadlineOfTheFileExpired, ProjectCheckFinishedUnitsIn,
    ProjectCheckPauseEndedAfter, ProjectCheckLowPriorityNot, ProjectCheckEndedAfterError, ProjectCheckSkipped);

const
  cTexts: array[TWorkspaceCheckText] of TAtlasText = (
    (De: 'Projektprüfung unterbrochen'; En: 'Project check interrupted'),
    (De: 'Frist der Datei abgelaufen'; En: 'Deadline of the file expired'),
    (De: 'Projektprüfung fertig: %d Units in %d ms, %d neu geprüft, %d übersprungen';
     En: 'Project check finished: %d units in %d ms, %d checked anew, %d skipped'),
    (De: 'Projektprüfung: Pause "%s" nach Frist beendet (Sicherheitsnetz)';
     En: 'Project check: pause "%s" ended after deadline (safety net)'),
    (De: 'Projektprüfung: niedrige Priorität nicht gesetzt'; En: 'Project check: low priority not set'),
    (De: 'Projektprüfung beendet nach Fehler: '; En: 'Project check ended after error: '),
    (De: 'Projektprüfung: %s übersprungen (%s)'; En: 'Project check: %s skipped (%s)'));

{$SCOPEDENUMS OFF}

type
  /// <summary>Frist der Datei abgelaufen (#1220): Die Datei kommt ans Ende der Schlange.</summary>
  EWorkspaceCheckDeadline = class(Exception);
  /// <summary>Der Benutzer tippt, eine Pause beginnt oder der Server endet: Die Datei kommt wieder vorn hin.
  /// </summary>
  EWorkspaceCheckInterrupted = class(Exception);

  TCheckToken = class(TInterfacedObject, IJsonRpcCancellationToken)
  private
    FOwner: TLspWorkspaceCheck;
    FClock: TStopwatch;
    FLimitMs: Int64;
    FInterruptible: Boolean;
    function Expired: Boolean;
  public
    constructor Create(AOwner: TLspWorkspaceCheck; ALimitMs: Int64; AInterruptible: Boolean);
    function IsCancellationRequested: Boolean;
    procedure ThrowIfCancellationRequested;
  end;

constructor TCheckToken.Create(AOwner: TLspWorkspaceCheck; ALimitMs: Int64; AInterruptible: Boolean);
begin
  inherited Create;
  FOwner := AOwner;
  FLimitMs := ALimitMs;
  FInterruptible := AInterruptible;
  FClock := TStopwatch.StartNew;
end;

function TCheckToken.Expired: Boolean;
begin
  Result := (FLimitMs > 0) and (FClock.ElapsedMilliseconds > FLimitMs);
end;

function TCheckToken.IsCancellationRequested: Boolean;
begin
  Result := FOwner.Interrupted(FInterruptible) or Expired;
end;

procedure TCheckToken.ThrowIfCancellationRequested;
begin
  if FOwner.Interrupted(FInterruptible) then
  begin
    raise EWorkspaceCheckInterrupted.Create(cTexts[TWorkspaceCheckText.ProjectCheckInterrupted].Text);
  end;
  if Expired then
  begin
    raise EWorkspaceCheckDeadline.Create(cTexts[TWorkspaceCheckText.DeadlineOfTheFileExpired].Text);
  end;
end;

{ TWorkspaceCheckRun }

function TWorkspaceCheckRun.ToJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('serial', TJSONNumber.Create(Serial));
  Result.AddPair('active', TJSONBool.Create(Active));
  Result.AddPair('done', TJSONNumber.Create(Done));
  Result.AddPair('total', TJSONNumber.Create(Total));
  Result.AddPair('skipped', TJSONNumber.Create(Skipped));
  Result.AddPair('paused', Paused);
  Result.AddPair('elapsedMs', TJSONNumber.Create(ElapsedMs));
end;

function TWorkspaceCheckRun.StateDiffers(const AOther: TWorkspaceCheckRun): Boolean;
begin
  Result := (Serial <> AOther.Serial) or (Active <> AOther.Active) or (Total <> AOther.Total) or
    (Paused <> AOther.Paused);
end;

/// <summary>Schlüssel einer Datei in Schlange und Projekt.</summary>
function KeyOf(const AFileName: string): string;
begin
  Result := AnsiLowerCase(AFileName);
end;

/// <summary>True, wenn AUnit die Datei AFileName mit $I einbindet.</summary>
function IncludesFile(const AUnit: TUnitIndex; const AFileName: string): Boolean;
var
  mInclude: string;
begin
  for mInclude in AUnit.Includes do
  begin
    if SameFileName(mInclude, AFileName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>True, wenn AUnit die Unit AName in uses hat.</summary>
function UsesUnit(const AUnit: TUnitIndex; const AName: string): Boolean;
var
  mUsed: string;
begin
  for mUsed in AUnit.InterfaceUses + AUnit.ImplementationUses do
  begin
    if SameText(mUsed, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TLspWorkspaceCheck.TSchedule }

constructor TLspWorkspaceCheck.TSchedule.Create;
begin
  inherited Create;
  FQueue := TList<TEntry>.Create;
  FQueued := TDictionary<string, Boolean>.Create;
  FProject := TDictionary<string, Boolean>.Create;
end;

destructor TLspWorkspaceCheck.TSchedule.Destroy;
begin
  FProject.Free;
  FQueued.Free;
  FQueue.Free;
  inherited;
end;

procedure TLspWorkspaceCheck.TSchedule.Restart;
begin
  FQueue.Clear;
  FQueued.Clear;
  InterruptCurrent;
end;

procedure TLspWorkspaceCheck.TSchedule.InterruptCurrent;
begin
  if FCurrent <> '' then
  begin
    FInterrupt := True;
  end;
end;

procedure TLspWorkspaceCheck.TSchedule.ClearProject;
begin
  FProject.Clear;
end;

function TLspWorkspaceCheck.TSchedule.AddToProject(const AFileName: string): Boolean;
var
  mKey: string;
begin
  mKey := KeyOf(AFileName);
  Result := not FProject.ContainsKey(mKey);
  if Result then
  begin
    FProject.Add(mKey, True);
  end;
end;

function TLspWorkspaceCheck.TSchedule.InProject(const AFileName: string): Boolean;
begin
  Result := FProject.ContainsKey(KeyOf(AFileName));
end;

procedure TLspWorkspaceCheck.TSchedule.ForceQueued(const AKey: string);
var
  mIndex: Integer;
  mEntry: TEntry;
begin
  FQueued[AKey] := True;
  for mIndex := 0 to FQueue.Count - 1 do
  begin
    if KeyOf(FQueue[mIndex].FileName) = AKey then
    begin
      mEntry := FQueue[mIndex];
      mEntry.Forced := True;
      FQueue[mIndex] := mEntry;
      Exit;
    end;
  end;
end;

function TLspWorkspaceCheck.TSchedule.Add(const AFileName: string; AForced: Boolean; ANow: Int64): Boolean;
var
  mKey: string;
  mEntry: TEntry;
  mForced: Boolean;
begin
  mKey := KeyOf(AFileName);
  if FQueued.TryGetValue(mKey, mForced) then
  begin
    if AForced and not mForced then
    begin
      ForceQueued(mKey);
    end;
    Exit(False);
  end;
  mEntry := Default(TEntry);
  mEntry.FileName := AFileName;
  mEntry.Forced := AForced;
  mEntry.Queued := ANow;
  FQueue.Add(mEntry);
  FQueued.Add(mKey, AForced);
  Result := True;
end;

function TLspWorkspaceCheck.TSchedule.TakeFirst: TEntry;
begin
  Result := FQueue[0];
  FQueue.Delete(0);
  FQueued.Remove(KeyOf(Result.FileName));
  FCurrent := Result.FileName;
  FInterrupt := False;
end;

procedure TLspWorkspaceCheck.TSchedule.Release;
begin
  FCurrent := '';
end;

function TLspWorkspaceCheck.TSchedule.IsQueued(const AFileName: string): Boolean;
begin
  Result := FQueued.ContainsKey(KeyOf(AFileName));
end;

procedure TLspWorkspaceCheck.TSchedule.Put(const AEntry: TEntry; AFront: Boolean);
begin
  if AFront then
  begin
    FQueue.Insert(0, AEntry);
  end
  else
  begin
    FQueue.Add(AEntry);
  end;
  FQueued.Add(KeyOf(AEntry.FileName), AEntry.Forced);
end;

function TLspWorkspaceCheck.TSchedule.Count: Integer;
begin
  Result := FQueue.Count;
end;

function TLspWorkspaceCheck.TSchedule.Running: Boolean;
begin
  Result := FCurrent <> '';
end;

function TLspWorkspaceCheck.TSchedule.OldestWaitMs(ANow: Int64): Int64;
var
  mEntry: TEntry;
begin
  Result := 0;
  for mEntry in FQueue do
  begin
    if ANow - mEntry.Queued > Result then
    begin
      Result := ANow - mEntry.Queued;
    end;
  end;
end;

{ TLspWorkspaceCheck.TReports }

constructor TLspWorkspaceCheck.TReports.Create;
begin
  inherited Create;
  FReports := TDictionary<string, TBytes>.Create;
  FIds := TDictionary<string, string>.Create;
  FStamps := TDictionary<string, Int64>.Create;
  // Ids einer früheren Sitzung sollen nie zufällig passen.
  FSession := Integer(TThread.GetTickCount64 and $7FFFFFFF);
end;

destructor TLspWorkspaceCheck.TReports.Destroy;
begin
  FStamps.Free;
  FIds.Free;
  FReports.Free;
  inherited;
end;

procedure TLspWorkspaceCheck.TReports.Put(const AUri: string; AStamp: Int64; const APacked: TBytes);
begin
  Inc(FSerial);
  FReports.AddOrSetValue(AUri, APacked);
  FIds.AddOrSetValue(AUri, Format('w%d.%d:t%d', [FSession, FSerial, AStamp]));
  FStamps.AddOrSetValue(AUri, AStamp);
end;

function TLspWorkspaceCheck.TReports.Unchanged(const AUri: string; AStamp: Int64): Boolean;
var
  mKnown: Int64;
begin
  Result := FStamps.TryGetValue(AUri, mKnown) and (mKnown = AStamp);
end;

procedure TLspWorkspaceCheck.TReports.DropStale(ASchedule: TSchedule);
var
  mStale: TList<string>;
  mUri: string;
begin
  mStale := TList<string>.Create;
  try
    for mUri in FIds.Keys do
    begin
      if not ASchedule.InProject(TDocumentUris.ToPath(mUri)) then
      begin
        mStale.Add(mUri);
      end;
    end;
    for mUri in mStale do
    begin
      FIds.Remove(mUri);
      FReports.Remove(mUri);
      FStamps.Remove(mUri);
    end;
  finally
    mStale.Free;
  end;
end;

function TLspWorkspaceCheck.TReports.NewerThan(const APrevious: TDictionary<string, string>): TArray<TCollected>;
var
  mPair: TPair<string, string>;
  mKnown: string;
  mCandidate: TCollected;
  mCandidates: TList<TCollected>;
begin
  mCandidates := TList<TCollected>.Create;
  try
    for mPair in FIds do
    begin
      if (APrevious.TryGetValue(mPair.Key, mKnown) and (mKnown = mPair.Value)) or
        not FReports.TryGetValue(mPair.Key, mCandidate.Items) then
      begin
        Continue;
      end;
      mCandidate.Uri := mPair.Key;
      mCandidate.Id := mPair.Value;
      mCandidates.Add(mCandidate);
    end;
    Result := mCandidates.ToArray;
  finally
    mCandidates.Free;
  end;
end;

{ TLspWorkspaceCheck.TProgress }

procedure TLspWorkspaceCheck.TProgress.Added;
begin
  BeginRun;
  Inc(Run.Total);
end;

procedure TLspWorkspaceCheck.TProgress.BeginRun;
begin
  if Run.Active then
  begin
    Exit;
  end;
  Inc(Run.Serial);
  Run.Active := True;
  Run.Done := 0;
  Run.Total := 0;
  Run.Skipped := 0;
  Run.ElapsedMs := 0;
  RunComputed := 0;
  Clock := TStopwatch.StartNew;
  Profiler.BeginRun(Now);
end;

function TLspWorkspaceCheck.TProgress.Finish: string;
begin
  Result := '';
  if not Run.Active then
  begin
    Exit;
  end;
  Run.Active := False;
  Run.ElapsedMs := Clock.ElapsedMilliseconds;
  Profiler.FinishRun(Run.ElapsedMs);
  Result := cTexts[TWorkspaceCheckText.ProjectCheckFinishedUnitsIn].Fmt([Run.Total, Run.ElapsedMs, RunComputed,
    Run.Skipped]);
end;

procedure TLspWorkspaceCheck.TProgress.Settle;
begin
  // Höchstens Total: Eine nicht unterbrechbare Datei kann nach einem Neustart noch im alten Lauf enden.
  if Run.Active and (Run.Done < Run.Total) then
  begin
    Inc(Run.Done);
  end;
end;

procedure TLspWorkspaceCheck.TProgress.Stored(AFailed: Boolean);
begin
  Inc(Computed);
  if Run.Active and (Run.Done < Run.Total) then
  begin
    Inc(Run.Done);
    Inc(RunComputed);
    if AFailed then
    begin
      Inc(Run.Skipped);
    end;
  end;
  if AFailed then
  begin
    Inc(Skipped);
  end;
end;

function TLspWorkspaceCheck.TProgress.Snapshot: TWorkspaceCheckRun;
begin
  Result := Run;
  if Run.Active then
  begin
    Result.ElapsedMs := Clock.ElapsedMilliseconds;
  end;
end;

function TLspWorkspaceCheck.TProgress.RunningMs: Int64;
begin
  Result := -1;
  if Run.Active then
  begin
    Result := Clock.ElapsedMilliseconds;
  end;
end;

{ TLspWorkspaceCheck.TPauses }

procedure TLspWorkspaceCheck.TPauses.Switch(const AReason: string; AOn: Boolean; ALimitMs: Cardinal; ANow: Int64);
begin
  if not AOn then
  begin
    Reasons.Remove(AReason);
  end
  else if ALimitMs = 0 then
  begin
    Reasons.AddOrSetValue(AReason, High(Int64));
  end
  else
  begin
    Reasons.AddOrSetValue(AReason, ANow + ALimitMs);
  end;
end;

function TLspWorkspaceCheck.TPauses.ActivePause(ANow: Int64; const ALog: TWorkspaceCheckLog): string;
var
  mPair: TPair<string, Int64>;
  mExpired: TList<string>;
  mReason: string;
begin
  Result := '';
  mExpired := TList<string>.Create;
  try
    for mPair in Reasons do
    begin
      if mPair.Value < ANow then
      begin
        mExpired.Add(mPair.Key);
      end
      else if (Result = '') or (mPair.Key < Result) then
      begin
        Result := mPair.Key;
      end;
    end;
    // Sicherheitsnetz: Das Ende der Pause kam nie an.
    for mReason in mExpired do
    begin
      Reasons.Remove(mReason);
      if Assigned(ALog) then
      begin
        ALog(cTexts[TWorkspaceCheckText.ProjectCheckPauseEndedAfter].Fmt([mReason]));
      end;
    end;
  finally
    mExpired.Free;
  end;
end;

function TLspWorkspaceCheck.TPauses.Hindrance(ABusy: Boolean; ANow: Int64; const ALog: TWorkspaceCheckLog;
  out AShown: string): string;
begin
  Result := ActivePause(ANow, ALog);
  if (Result = '') and ABusy then
  begin
    Result := TLspWorkspaceCheck.cPauseIndex;
  end;
  AShown := Result;
  if Result <> '' then
  begin
    Exit;
  end;
  // Vorrang des Benutzers: kurz, darum nicht in der Statusleiste.
  if Foreground > 0 then
  begin
    Result := 'foreground';
  end
  else if (TypedAt >= 0) and (ANow - TypedAt < QuietMs) then
  begin
    Result := 'typing';
  end;
end;

{ TLspWorkspaceCheck.TWorker }

constructor TLspWorkspaceCheck.TWorker.Create(AOwner: TLspWorkspaceCheck);
begin
  FOwner := AOwner;
  inherited Create(True);
  FreeOnTerminate := False;
  // Niedrige Priorität (#1236): Editor und Vordergrundanfragen gehen vor. Nicht jede Plattform erlaubt das.
  try
    Priority := tpLower;
  except
    // lsp-ignore: catch-all-without-raise -- Fehlergrenze des Prüf-Threads; Fehler wird protokolliert
    on Exception do
      Log(cTexts[TWorkspaceCheckText.ProjectCheckLowPriorityNot].Text);
  end;
end;

procedure TLspWorkspaceCheck.TWorker.Execute;
var
  mEntry: TEntry;
begin
  try
    while NextEntry(mEntry) do
    begin
      Process(mEntry);
    end;
  except
    // Ein Fehler außerhalb einer Datei beendet nur die Projektprüfung, nicht den Server.
    // lsp-ignore: catch-all-without-raise -- Fehlergrenze des Prüf-Threads; Fehler wird protokolliert
    on E: Exception do
      Log(cTexts[TWorkspaceCheckText.ProjectCheckEndedAfterError].Text + E.ClassName);
  end;
end;

procedure TLspWorkspaceCheck.TWorker.Log(const AMessage: string);
begin
  if Assigned(FOwner.FHooks.Log) then
  begin
    FOwner.FHooks.Log(AMessage);
  end;
end;

function TLspWorkspaceCheck.TWorker.LabelOf(const AFileName: string): string;
begin
  Result := 'unit';
  if Assigned(FOwner.FHooks.FileLabel) then
  begin
    Result := FOwner.FHooks.FileLabel(AFileName);
  end;
end;

function TLspWorkspaceCheck.TWorker.NextEntry(out AEntry: TEntry): Boolean;
var
  mBusy: Boolean;
  mReason, mShown, mFinished: string;
begin
  while True do
  begin
    // Außerhalb der Sperre: Der Anbieter sperrt selbst (Arbeitsbereiche).
    mBusy := Assigned(FOwner.FHooks.Busy) and FOwner.FHooks.Busy();
    TMonitor.Enter(FOwner.FLock);
    try
      if FOwner.FStopping then
      begin
        Exit(False);
      end;
      mReason := FOwner.FPauses.Hindrance(mBusy, FOwner.FClock.ElapsedMilliseconds, FOwner.FHooks.Log, mShown);
      if mShown <> FOwner.FProgress.Run.Paused then
      begin
        FOwner.FProgress.Run.Paused := mShown;
        FOwner.Changed;
      end;
      if (mReason = '') and (FOwner.FSchedule.Count > 0) then
      begin
        AEntry := FOwner.FSchedule.TakeFirst;
        Exit(True);
      end;
      mFinished := WaitLocked;
    finally
      TMonitor.Exit(FOwner.FLock);
    end;
    if mFinished <> '' then
    begin
      Log(mFinished);
    end;
  end;
end;

function TLspWorkspaceCheck.TWorker.WaitLocked: string;
begin
  // Bei leerer Schlange endet erst der Lauf, sonst ein Takt.
  Result := '';
  if FOwner.FSchedule.Count > 0 then
  begin
    TMonitor.Wait(FOwner.FLock, TLspWorkspaceCheck.cSliceMs);
    Exit;
  end;
  Result := FOwner.FProgress.Finish;
  if Result = '' then
  begin
    TMonitor.Wait(FOwner.FLock, TLspWorkspaceCheck.cIdleWaitMs);
  end
  else
  begin
    FOwner.Changed;
  end;
end;

procedure TLspWorkspaceCheck.TWorker.Process(const AEntry: TEntry);
var
  mUri, mText: string;
  mStamp: Int64;
  mItems: TJSONArray;
begin
  if not Prepare(AEntry, mUri, mStamp, mText) then
  begin
    Settle;
    Exit;
  end;
  try
    mItems := Diagnose(AEntry, mUri, mText);
  except
    // lsp-ignore: catch-all-without-raise -- Fehlergrenze des Prüf-Threads; Fehler wird protokolliert
    on E: Exception do
    begin
      Fail(AEntry, mUri, mStamp, E);
      Exit;
    end;
  end;
  Store(mUri, mStamp, mItems, False);
end;

function TLspWorkspaceCheck.TWorker.Prepare(const AEntry: TEntry; out AUri: string; out AStamp: Int64;
  out AText: string): Boolean;
var
  mUnchanged: Boolean;
begin
  AUri := TDocumentUris.FromPath(AEntry.FileName);
  AStamp := 0;
  AText := '';
  // Geöffnete Dateien prüft textDocument/diagnostic mit dem Editortext.
  if (Assigned(FOwner.FHooks.IsOpen) and FOwner.FHooks.IsOpen(AUri)) or
    not FOwner.FHooks.Stamp(AEntry.FileName, AStamp) then
  begin
    Exit(False);
  end;
  TMonitor.Enter(FOwner.FLock);
  try
    mUnchanged := not AEntry.Forced and FOwner.FReports.Unchanged(AUri, AStamp);
  finally
    TMonitor.Exit(FOwner.FLock);
  end;
  Result := not mUnchanged and FOwner.FHooks.ReadText(AEntry.FileName, AText);
end;

function TLspWorkspaceCheck.TWorker.Diagnose(const AEntry: TEntry; const AUri, AText: string): TJSONArray;
var
  mDocument: ITextDocument;
  mToken: IJsonRpcCancellationToken;
  mLimit: Int64;
  mPrevious: TCheckProfiler;
  mWatch: TStopwatch;
begin
  // Erst in Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben (beim Token je Datei 88 Byte).
  mDocument := TTextDocument.Create(AUri, 'objectpascal', 0, AText);
  mLimit := FOwner.FHooks.FileLimitMs;
  if AEntry.Unlimited then
  begin
    mLimit := 0;
  end;
  mToken := TCheckToken.Create(FOwner, mLimit, not AEntry.Unlimited);
  // Zeitprofil (#1356): Die Engine meldet ihre Regelzeiten an den Profiler dieses Threads.
  mPrevious := TCheckProfiler.Attach(FOwner.FProgress.Profiler);
  mWatch := TStopwatch.StartNew;
  try
    Result := FOwner.FHooks.Diagnose(mDocument, mToken);
  finally
    TCheckProfiler.Attach(mPrevious);
    FOwner.FProgress.Profiler.AddUnit(AEntry.FileName, TCheckProfiler.TicksToMicroseconds(mWatch.ElapsedTicks,
      TStopwatch.Frequency));
  end;
end;

procedure TLspWorkspaceCheck.TWorker.Fail(const AEntry: TEntry; const AUri: string; AStamp: Int64;
  AError: Exception);
var
  mRetry: TEntry;
begin
  if AError is EWorkspaceCheckInterrupted then
  begin
    Requeue(AEntry, True);
  end
  else if AError is EWorkspaceCheckDeadline then
  begin
    // Zu langsam für den ersten Durchgang (#1220): am Ende ohne Frist zu Ende prüfen.
    mRetry := AEntry;
    mRetry.Unlimited := True;
    mRetry.Forced := True;
    mRetry.Queued := FOwner.FClock.ElapsedMilliseconds;
    Requeue(mRetry, False);
  end
  else if FOwner.Interrupted(False) then
  begin
    Requeue(AEntry, True);
  end
  else
  begin
    // Datei überspringen (#1094): leer bis zur nächsten Änderung, die übrigen weiter prüfen.
    TStackGuard.AfterError(AError);
    Log(cTexts[TWorkspaceCheckText.ProjectCheckSkipped].Fmt([LabelOf(AEntry.FileName), AError.ClassName]));
    Store(AUri, AStamp, TJSONArray.Create, True);
  end;
end;

procedure TLspWorkspaceCheck.TWorker.Requeue(const AEntry: TEntry; AFront: Boolean);
begin
  TMonitor.Enter(FOwner.FLock);
  try
    FOwner.FSchedule.Release;
    // Inzwischen neu eingestellt (Start, Affected): der neue Eintrag genügt.
    if FOwner.FStopping or FOwner.FSchedule.IsQueued(AEntry.FileName) then
    begin
      Exit;
    end;
    // Ein erzwungener Neustart hat den Lauf beendet; die Datei gehört in den neuen.
    if not FOwner.FProgress.Run.Active then
    begin
      FOwner.FProgress.Added;
    end;
    FOwner.FSchedule.Put(AEntry, AFront);
  finally
    TMonitor.Exit(FOwner.FLock);
  end;
end;

procedure TLspWorkspaceCheck.TWorker.Settle;
begin
  // Datei ohne neue Befunde erledigt (geöffnet, unverändert, fehlt).
  TMonitor.Enter(FOwner.FLock);
  try
    FOwner.FSchedule.Release;
    FOwner.FProgress.Settle;
    FOwner.Changed;
  finally
    TMonitor.Exit(FOwner.FLock);
  end;
end;

procedure TLspWorkspaceCheck.TWorker.Store(const AUri: string; AStamp: Int64; AItems: TJSONArray;
  AFailed: Boolean);
var
  mPacked: TBytes;
begin
  // Außerhalb der Sperre packen; der Baum wird danach nicht mehr gebraucht.
  try
    mPacked := TCompactJson.Pack(AItems);
  finally
    AItems.Free;
  end;
  TMonitor.Enter(FOwner.FLock);
  try
    FOwner.FSchedule.Release;
    if FOwner.FStopping then
    begin
      Exit;
    end;
    FOwner.FReports.Put(AUri, AStamp, mPacked);
    FOwner.FProgress.Stored(AFailed);
    FOwner.Changed;
  finally
    TMonitor.Exit(FOwner.FLock);
  end;
end;

{ TLspWorkspaceCheck }

constructor TLspWorkspaceCheck.Create(const AFiles: TWorkspaceCheckFiles; const AStamp: TWorkspaceCheckStamp;
  const AReadText: TWorkspaceCheckRead; const AIsOpen: TWorkspaceCheckOpen;
  const ADiagnose: TWorkspaceCheckDiagnose);
begin
  inherited Create;
  FHooks.Files := AFiles;
  FHooks.Stamp := AStamp;
  FHooks.ReadText := AReadText;
  FHooks.IsOpen := AIsOpen;
  FHooks.Diagnose := ADiagnose;
  FHooks.FileLimitMs := cDefaultFileLimitMs;
  FLock := TObject.Create;
  FClock := TStopwatch.StartNew;
  FSchedule := TSchedule.Create;
  FReports := TReports.Create;
  FProgress.Profiler := TCheckProfiler.Create;
  FPauses.Reasons := TDictionary<string, Int64>.Create;
  FPauses.TypedAt := -1;
  FPauses.QuietMs := cDefaultTypingQuietMs;
end;

destructor TLspWorkspaceCheck.Destroy;
begin
  TMonitor.Enter(FLock);
  try
    FStopping := True;
    TMonitor.PulseAll(FLock);
  finally
    TMonitor.Exit(FLock);
  end;
  if FWorker <> nil then
  begin
    FWorker.WaitFor;
    FWorker.Free;
  end;
  FPauses.Reasons.Free;
  FProgress.Profiler.Free;
  FReports.Free;
  FSchedule.Free;
  FLock.Free;
  inherited;
end;

procedure TLspWorkspaceCheck.Changed;
begin
  // Unter FLock aufgerufen.
  Inc(FChange);
  TMonitor.PulseAll(FLock);
end;

procedure TLspWorkspaceCheck.EnsureWorker;
begin
  // Unter FLock aufgerufen.
  if (FWorker <> nil) or FStopping then
  begin
    Exit;
  end;
  FWorker := TWorker.Create(Self);
  FWorker.Start;
end;

function TLspWorkspaceCheck.Interrupted(AInterruptible: Boolean): Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := FStopping or (AInterruptible and FSchedule.Interrupt);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLspWorkspaceCheck.Want;
var
  mFirst: Boolean;
begin
  TMonitor.Enter(FLock);
  try
    mFirst := not FSchedule.Wanted;
    FSchedule.Wanted := True;
  finally
    TMonitor.Exit(FLock);
  end;
  if mFirst then
  begin
    Start(False);
  end;
end;

procedure TLspWorkspaceCheck.Start(AForce: Boolean);
var
  mFiles: TArray<string>;
  mFileName: string;
begin
  if not Assigned(FHooks.Files) then
  begin
    Exit;
  end;
  TMonitor.Enter(FLock);
  try
    if not FSchedule.Wanted or FStopping then
    begin
      Exit;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  // Außerhalb der Sperre: Der Anbieter sperrt selbst (Arbeitsbereiche).
  mFiles := FHooks.Files();
  TMonitor.Enter(FLock);
  try
    // Erzwungen: Der Lauf beginnt von vorn, damit Fortschritt und Ende stimmen. Die laufende Datei bricht ab;
    // sie steht ohnehin wieder in der Schlange.
    if AForce then
    begin
      FSchedule.Restart;
      FProgress.Run.Active := False;
    end;
    FSchedule.ClearProject;
    for mFileName in mFiles do
    begin
      if FSchedule.AddToProject(mFileName) and FSchedule.Add(mFileName, AForce, FClock.ElapsedMilliseconds) then
      begin
        FProgress.Added;
      end;
    end;
    FReports.DropStale(FSchedule);
    EnsureWorker;
    Changed;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLspWorkspaceCheck.Affected(const AFiles: TArray<string>; AWithDependents: Boolean);
var
  mFiles: TArray<string>;
  mFileName: string;
begin
  TMonitor.Enter(FLock);
  try
    if not FSchedule.Wanted or FStopping then
    begin
      Exit;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  mFiles := AFiles;
  if AWithDependents and Assigned(FHooks.Dependents) then
  begin
    for mFileName in AFiles do
    begin
      mFiles := mFiles + FHooks.Dependents(mFileName);
    end;
  end;
  TMonitor.Enter(FLock);
  try
    for mFileName in mFiles do
    begin
      if FSchedule.InProject(mFileName) and FSchedule.Add(mFileName, True, FClock.ElapsedMilliseconds) then
      begin
        FProgress.Added;
      end;
    end;
    EnsureWorker;
    Changed;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLspWorkspaceCheck.Pause(const AReason: string; AOn: Boolean);
begin
  Pause(AReason, AOn, 0);
end;

procedure TLspWorkspaceCheck.Pause(const AReason: string; AOn: Boolean; ALimitMs: Cardinal);
begin
  TMonitor.Enter(FLock);
  try
    FPauses.Switch(AReason, AOn, ALimitMs, FClock.ElapsedMilliseconds);
    if AOn then
    begin
      FSchedule.InterruptCurrent;
    end;
    TMonitor.PulseAll(FLock);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLspWorkspaceCheck.Typed;
begin
  TMonitor.Enter(FLock);
  try
    FPauses.TypedAt := FClock.ElapsedMilliseconds;
    FSchedule.InterruptCurrent;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLspWorkspaceCheck.EnterForeground;
begin
  TMonitor.Enter(FLock);
  try
    Inc(FPauses.Foreground);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLspWorkspaceCheck.LeaveForeground;
begin
  TMonitor.Enter(FLock);
  try
    if FPauses.Foreground > 0 then
    begin
      Dec(FPauses.Foreground);
    end;
    TMonitor.PulseAll(FLock);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TLspWorkspaceCheck.Collect(const APrevious: TDictionary<string, string>; AMax: Integer): TJSONArray;
var
  mCandidates: TArray<TCollected>;
  mCandidate: TCollected;
  mReport: TJSONObject;
begin
  // Unter der Sperre nur die gepackten Befunde einsammeln (Referenzen, keine Kopien).
  TMonitor.Enter(FLock);
  try
    mCandidates := FReports.NewerThan(APrevious);
  finally
    TMonitor.Exit(FLock);
  end;
  Result := TJSONArray.Create;
  // Außerhalb der Sperre: Der Dokumentspeicher sperrt selbst. Entpackt wird nur, was die Antwort enthält.
  for mCandidate in mCandidates do
  begin
    if Result.Count >= AMax then
    begin
      Break;
    end;
    if Assigned(FHooks.IsOpen) and FHooks.IsOpen(mCandidate.Uri) then
    begin
      Continue;
    end;
    mReport := TJSONObject.Create;
    mReport.AddPair('uri', mCandidate.Uri);
    mReport.AddPair('version', TJSONNull.Create);
    mReport.AddPair('kind', 'full');
    mReport.AddPair('resultId', mCandidate.Id);
    mReport.AddPair('items', TCompactJson.UnpackArray(mCandidate.Items));
    Result.AddElement(mReport);
  end;
end;

function TLspWorkspaceCheck.ChangeCount: Integer;
begin
  TMonitor.Enter(FLock);
  try
    Result := FChange;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TLspWorkspaceCheck.WaitForChange(AChange: Integer; AWaitMs: Cardinal): Integer;
begin
  TMonitor.Enter(FLock);
  try
    // Unter der Sperre prüfen: Eine Änderung zwischen Prüfung und Wait geht nicht verloren.
    if (FChange = AChange) and not FStopping then
    begin
      TMonitor.Wait(FLock, AWaitMs);
    end;
    Result := FChange;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TLspWorkspaceCheck.Run: TWorkspaceCheckRun;
begin
  TMonitor.Enter(FLock);
  try
    Result := FProgress.Snapshot;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TLspWorkspaceCheck.Profile(ACount: Integer): TCheckRunProfile;
var
  mRunning: Int64;
begin
  TMonitor.Enter(FLock);
  try
    mRunning := FProgress.RunningMs;
  finally
    TMonitor.Exit(FLock);
  end;
  Result := FProgress.Profiler.Snapshot(ACount, mRunning);
end;

function TLspWorkspaceCheck.Queue: TWorkspaceCheckQueue;
begin
  Result := Default(TWorkspaceCheckQueue);
  TMonitor.Enter(FLock);
  try
    Result.Waiting := FSchedule.Count;
    if FSchedule.Running then
    begin
      Result.Running := 1;
    end;
    Result.OldestWaitMs := FSchedule.OldestWaitMs(FClock.ElapsedMilliseconds);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TLspWorkspaceCheck.WaitIdle(ATimeoutMs: Cardinal): Boolean;
var
  mClock: TStopwatch;
begin
  mClock := TStopwatch.StartNew;
  TMonitor.Enter(FLock);
  try
    while (FProgress.Run.Active or (FSchedule.Count > 0) or FSchedule.Running) and
      (mClock.ElapsedMilliseconds < Int64(ATimeoutMs)) do
    begin
      TMonitor.Wait(FLock, cSliceMs);
    end;
    Result := not (FProgress.Run.Active or (FSchedule.Count > 0) or FSchedule.Running);
  finally
    TMonitor.Exit(FLock);
  end;
end;

class function TLspWorkspaceCheck.DependentsOf(const AUnits: TArray<TUnitIndex>;
  const AFileName: string): TArray<string>;
var
  mUnit: TUnitIndex;
  mName: string;
  mIsInclude: Boolean;
begin
  Result := nil;
  mIsInclude := SameText(ExtractFileExt(AFileName), '.inc');
  mName := ChangeFileExt(ExtractFileName(AFileName), '');
  for mUnit in AUnits do
  begin
    if mUnit.Library_ or (mUnit.FileName = '') or SameFileName(mUnit.FileName, AFileName) then
    begin
      Continue;
    end;
    if (mIsInclude and IncludesFile(mUnit, AFileName)) or (not mIsInclude and UsesUnit(mUnit, mName)) then
    begin
      Result := Result + [mUnit.FileName];
    end;
  end;
end;

{ TWorkspaceCheckIndexGate }

procedure TWorkspaceCheckIndexGate.IndexStarted;
begin
  TInterlocked.Exchange(FStarted, 0);
end;

function TWorkspaceCheckIndexGate.Recheck(AProjectStage: Boolean): Boolean;
begin
  if AProjectStage then
  begin
    TInterlocked.Exchange(FStarted, 1);
    Exit(True);
  end;
  Result := TInterlocked.Exchange(FStarted, 1) = 0;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.WorkspaceCheck', cTexts);

end.
