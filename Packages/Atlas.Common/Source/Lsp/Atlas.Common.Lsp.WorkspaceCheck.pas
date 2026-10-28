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
  Atlas.Common.Index.Contract;

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
    end;

    TWorker = class(TThread)
    private
      FOwner: TLspWorkspaceCheck;
    protected
      procedure Execute; override;
    public
      constructor Create(AOwner: TLspWorkspaceCheck);
    end;
  private
    FFiles: TWorkspaceCheckFiles;
    FStamp: TWorkspaceCheckStamp;
    FReadText: TWorkspaceCheckRead;
    FIsOpen: TWorkspaceCheckOpen;
    FDiagnose: TWorkspaceCheckDiagnose;
    FBusy: TWorkspaceCheckBusy;
    FDependents: TWorkspaceCheckDependents;
    FFileLabel: TWorkspaceCheckLabel;
    FLog: TWorkspaceCheckLog;
    FFileLimitMs: Cardinal;
    FTypingQuietMs: Cardinal;
    // Alles Folgende unter FLock; TMonitor.PulseAll(FLock) weckt Thread und Wartende.
    FLock: TObject;
    FClock: TStopwatch;
    FWorker: TWorker;
    FStopping: Boolean;
    // Erst die erste Anfrage workspace/diagnostic startet die Prüfung; ohne Projektprüfung im Client ruht sie.
    FWanted: Boolean;
    FQueue: TList<TEntry>;
    FQueued: TDictionary<string, Boolean>;
    // Projektdateien des letzten Start; Affected stellt nur diese ein.
    FProject: TDictionary<string, Boolean>;
    // Gespeicherte Befunde je Uri.
    FReports: TObjectDictionary<string, TJSONArray>;
    FIds: TDictionary<string, string>;
    FStamps: TDictionary<string, Int64>;
    FSession: Integer;
    FSerial: Integer;
    FRun: TWorkspaceCheckRun;
    FRunClock: TStopwatch;
    FRunComputed: Integer;
    // Steigt bei jeder Änderung, die Wartende sehen sollen.
    FChange: Integer;
    // Pausengrund -> Ende in ms auf FClock (High(Int64) = ohne Frist).
    FPauses: TDictionary<string, Int64>;
    FTypedAt: Int64;
    FForeground: Integer;
    // Datei, die der Thread gerade prüft; FInterrupt bricht sie ab.
    FCurrent: string;
    FInterrupt: Boolean;
    FComputed: Integer;
    FSkipped: Integer;
    class function KeyOf(const AFileName: string): string; static;
    function Now_: Int64;
    procedure Changed;
    procedure EnsureWorker;
    procedure BeginRunLocked;
    function FinishRunLocked: string;
    procedure EnqueueLocked(const AFileName: string; AForced: Boolean);
    function HindranceLocked(ABusy: Boolean; out AShown: string): string;
    function NextEntry(out AEntry: TEntry): Boolean;
    procedure Process(const AEntry: TEntry);
    procedure Requeue(const AEntry: TEntry; AFront: Boolean);
    procedure Store(const AUri: string; AStamp: Int64; AItems: TJSONArray; AFailed: Boolean);
    procedure Settle(const AUri: string);
    function Interrupted(AInterruptible: Boolean): Boolean;
    function LabelOf(const AFileName: string): string;
    procedure Log(const AMessage: string);
    procedure Work;
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
    /// <summary>Wartet, bis die Schlange leer ist und kein Lauf mehr aktiv ist (Tests).</summary>
    function WaitIdle(ATimeoutMs: Cardinal): Boolean;
    /// <summary>Dateien unter AUnits, die von AFileName abhängen: bei .inc die einbindenden Units, sonst die
    /// Projekt-Units mit dem Unit-Namen in uses. Ohne AFileName selbst.</summary>
    class function DependentsOf(const AUnits: TArray<TUnitIndex>; const AFileName: string): TArray<string>; static;
    property Busy: TWorkspaceCheckBusy read FBusy write FBusy;
    property Dependents: TWorkspaceCheckDependents read FDependents write FDependents;
    property FileLabel: TWorkspaceCheckLabel read FFileLabel write FFileLabel;
    property OnLog: TWorkspaceCheckLog read FLog write FLog;
    property FileLimitMs: Cardinal read FFileLimitMs write FFileLimitMs;
    property TypingQuietMs: Cardinal read FTypingQuietMs write FTypingQuietMs;
    /// <summary>Tatsächlich berechnete Dateibefunde.</summary>
    property Computed: Integer read FComputed;
    /// <summary>Nach einem Fehler übersprungene Dateien (#1094).</summary>
    property Skipped: Integer read FSkipped;
  end;

implementation

uses
  Atlas.Common.Diagnostics.StackGuard,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.TextDocument;

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
    raise EWorkspaceCheckInterrupted.Create('Projektprüfung unterbrochen');
  if Expired then
    raise EWorkspaceCheckDeadline.Create('Frist der Datei abgelaufen');
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
    on Exception do
      FOwner.Log('Projektprüfung: niedrige Priorität nicht gesetzt');
  end;
end;

procedure TLspWorkspaceCheck.TWorker.Execute;
begin
  try
    FOwner.Work;
  except
    // Ein Fehler außerhalb einer Datei beendet nur die Projektprüfung, nicht den Server.
    on E: Exception do
      FOwner.Log('Projektprüfung beendet nach Fehler: ' + E.ClassName);
  end;
end;

{ TLspWorkspaceCheck }

constructor TLspWorkspaceCheck.Create(const AFiles: TWorkspaceCheckFiles; const AStamp: TWorkspaceCheckStamp;
  const AReadText: TWorkspaceCheckRead; const AIsOpen: TWorkspaceCheckOpen;
  const ADiagnose: TWorkspaceCheckDiagnose);
begin
  inherited Create;
  FFiles := AFiles;
  FStamp := AStamp;
  FReadText := AReadText;
  FIsOpen := AIsOpen;
  FDiagnose := ADiagnose;
  FFileLimitMs := cDefaultFileLimitMs;
  FTypingQuietMs := cDefaultTypingQuietMs;
  FLock := TObject.Create;
  FClock := TStopwatch.StartNew;
  FQueue := TList<TEntry>.Create;
  FQueued := TDictionary<string, Boolean>.Create;
  FProject := TDictionary<string, Boolean>.Create;
  FReports := TObjectDictionary<string, TJSONArray>.Create([doOwnsValues]);
  FIds := TDictionary<string, string>.Create;
  FStamps := TDictionary<string, Int64>.Create;
  FPauses := TDictionary<string, Int64>.Create;
  FTypedAt := -1;
  // Ids einer früheren Sitzung sollen nie zufällig passen.
  FSession := Integer(TThread.GetTickCount64 and $7FFFFFFF);
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
  FPauses.Free;
  FStamps.Free;
  FIds.Free;
  FReports.Free;
  FProject.Free;
  FQueued.Free;
  FQueue.Free;
  FLock.Free;
  inherited;
end;

class function TLspWorkspaceCheck.KeyOf(const AFileName: string): string;
begin
  Result := AnsiLowerCase(AFileName);
end;

function TLspWorkspaceCheck.Now_: Int64;
begin
  Result := FClock.ElapsedMilliseconds;
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
    Exit;
  FWorker := TWorker.Create(Self);
  FWorker.Start;
end;

function TLspWorkspaceCheck.LabelOf(const AFileName: string): string;
begin
  Result := 'unit';
  if Assigned(FFileLabel) then
    Result := FFileLabel(AFileName);
end;

procedure TLspWorkspaceCheck.Log(const AMessage: string);
begin
  if Assigned(FLog) then
    FLog(AMessage);
end;

procedure TLspWorkspaceCheck.BeginRunLocked;
begin
  if FRun.Active then
    Exit;
  Inc(FRun.Serial);
  FRun.Active := True;
  FRun.Done := 0;
  FRun.Total := 0;
  FRun.Skipped := 0;
  FRun.ElapsedMs := 0;
  FRunComputed := 0;
  FRunClock := TStopwatch.StartNew;
end;

function TLspWorkspaceCheck.FinishRunLocked: string;
begin
  Result := '';
  if not FRun.Active then
    Exit;
  FRun.Active := False;
  FRun.ElapsedMs := FRunClock.ElapsedMilliseconds;
  Changed;
  Result := Format('Projektprüfung fertig: %d Units in %d ms, %d neu geprüft, %d übersprungen',
    [FRun.Total, FRun.ElapsedMs, FRunComputed, FRun.Skipped]);
end;

procedure TLspWorkspaceCheck.EnqueueLocked(const AFileName: string; AForced: Boolean);
var
  mKey: string;
  mEntry: TEntry;
  mIndex: Integer;
  mForced: Boolean;
begin
  mKey := KeyOf(AFileName);
  if FQueued.TryGetValue(mKey, mForced) then
  begin
    if AForced and not mForced then
    begin
      FQueued[mKey] := True;
      for mIndex := 0 to FQueue.Count - 1 do
        if KeyOf(FQueue[mIndex].FileName) = mKey then
        begin
          mEntry := FQueue[mIndex];
          mEntry.Forced := True;
          FQueue[mIndex] := mEntry;
          Break;
        end;
    end;
    Exit;
  end;
  BeginRunLocked;
  mEntry := Default(TEntry);
  mEntry.FileName := AFileName;
  mEntry.Forced := AForced;
  FQueue.Add(mEntry);
  FQueued.Add(mKey, AForced);
  Inc(FRun.Total);
end;

procedure TLspWorkspaceCheck.Want;
var
  mFirst: Boolean;
begin
  TMonitor.Enter(FLock);
  try
    mFirst := not FWanted;
    FWanted := True;
  finally
    TMonitor.Exit(FLock);
  end;
  if mFirst then
    Start(False);
end;

procedure TLspWorkspaceCheck.Start(AForce: Boolean);
var
  mFiles: TArray<string>;
  mFileName, mKey, mUri: string;
  mStale: TList<string>;
begin
  if not Assigned(FFiles) then
    Exit;
  TMonitor.Enter(FLock);
  try
    if not FWanted or FStopping then
      Exit;
  finally
    TMonitor.Exit(FLock);
  end;
  // Außerhalb der Sperre: Der Anbieter sperrt selbst (Arbeitsbereiche).
  mFiles := FFiles();
  mStale := TList<string>.Create;
  TMonitor.Enter(FLock);
  try
    // Erzwungen: Der Lauf beginnt von vorn, damit Fortschritt und Ende stimmen. Die laufende Datei bricht ab;
    // sie steht ohnehin wieder in der Schlange.
    if AForce then
    begin
      FQueue.Clear;
      FQueued.Clear;
      FRun.Active := False;
      if FCurrent <> '' then
        FInterrupt := True;
    end;
    FProject.Clear;
    for mFileName in mFiles do
    begin
      mKey := KeyOf(mFileName);
      if FProject.ContainsKey(mKey) then
        Continue;
      FProject.Add(mKey, True);
      EnqueueLocked(mFileName, AForce);
    end;
    // Nicht mehr zum Projekt gehörende Dateien melden sich nie wieder; ihre Befunde verwerfen.
    for mUri in FIds.Keys do
      if not FProject.ContainsKey(KeyOf(TDocumentUris.ToPath(mUri))) then
        mStale.Add(mUri);
    for mUri in mStale do
    begin
      FIds.Remove(mUri);
      FReports.Remove(mUri);
      FStamps.Remove(mUri);
    end;
    EnsureWorker;
    Changed;
  finally
    TMonitor.Exit(FLock);
    mStale.Free;
  end;
end;

procedure TLspWorkspaceCheck.Affected(const AFiles: TArray<string>; AWithDependents: Boolean);
var
  mFiles: TArray<string>;
  mFileName: string;
begin
  TMonitor.Enter(FLock);
  try
    if not FWanted or FStopping then
      Exit;
  finally
    TMonitor.Exit(FLock);
  end;
  mFiles := AFiles;
  if AWithDependents and Assigned(FDependents) then
    for mFileName in AFiles do
      mFiles := mFiles + FDependents(mFileName);
  TMonitor.Enter(FLock);
  try
    for mFileName in mFiles do
      if FProject.ContainsKey(KeyOf(mFileName)) then
        EnqueueLocked(mFileName, True);
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
    if AOn then
    begin
      if ALimitMs = 0 then
        FPauses.AddOrSetValue(AReason, High(Int64))
      else
        FPauses.AddOrSetValue(AReason, Now_ + ALimitMs);
      if FCurrent <> '' then
        FInterrupt := True;
    end
    else
      FPauses.Remove(AReason);
    TMonitor.PulseAll(FLock);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLspWorkspaceCheck.Typed;
begin
  TMonitor.Enter(FLock);
  try
    FTypedAt := Now_;
    if FCurrent <> '' then
      FInterrupt := True;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLspWorkspaceCheck.EnterForeground;
begin
  TMonitor.Enter(FLock);
  try
    Inc(FForeground);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLspWorkspaceCheck.LeaveForeground;
begin
  TMonitor.Enter(FLock);
  try
    if FForeground > 0 then
      Dec(FForeground);
    TMonitor.PulseAll(FLock);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TLspWorkspaceCheck.Interrupted(AInterruptible: Boolean): Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := FStopping or (AInterruptible and FInterrupt);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TLspWorkspaceCheck.HindranceLocked(ABusy: Boolean; out AShown: string): string;
var
  mPair: TPair<string, Int64>;
  mExpired: TList<string>;
  mReason: string;
begin
  Result := '';
  AShown := '';
  mExpired := TList<string>.Create;
  try
    for mPair in FPauses do
      if mPair.Value < Now_ then
        mExpired.Add(mPair.Key)
      else if (Result = '') or (mPair.Key < Result) then
        Result := mPair.Key;
    // Sicherheitsnetz: Das Ende der Pause kam nie an.
    for mReason in mExpired do
    begin
      FPauses.Remove(mReason);
      Log(Format('Projektprüfung: Pause "%s" nach Frist beendet (Sicherheitsnetz)', [mReason]));
    end;
  finally
    mExpired.Free;
  end;
  if (Result = '') and ABusy then
    Result := cPauseIndex;
  AShown := Result;
  if Result <> '' then
    Exit;
  // Vorrang des Benutzers: kurz, darum nicht in der Statusleiste.
  if FForeground > 0 then
    Exit('foreground');
  if (FTypedAt >= 0) and (Now_ - FTypedAt < FTypingQuietMs) then
    Exit('typing');
end;

function TLspWorkspaceCheck.NextEntry(out AEntry: TEntry): Boolean;
var
  mBusy: Boolean;
  mReason, mShown, mFinished: string;
begin
  while True do
  begin
    // Außerhalb der Sperre: Der Anbieter sperrt selbst (Arbeitsbereiche).
    mBusy := Assigned(FBusy) and FBusy();
    mFinished := '';
    TMonitor.Enter(FLock);
    try
      if FStopping then
        Exit(False);
      mReason := HindranceLocked(mBusy, mShown);
      if mShown <> FRun.Paused then
      begin
        FRun.Paused := mShown;
        Changed;
      end;
      if (mReason = '') and (FQueue.Count > 0) then
      begin
        AEntry := FQueue[0];
        FQueue.Delete(0);
        FQueued.Remove(KeyOf(AEntry.FileName));
        FCurrent := AEntry.FileName;
        FInterrupt := False;
        Exit(True);
      end;
      if FQueue.Count = 0 then
      begin
        mFinished := FinishRunLocked;
        if mFinished = '' then
          TMonitor.Wait(FLock, cIdleWaitMs);
      end
      else
        TMonitor.Wait(FLock, cSliceMs);
    finally
      TMonitor.Exit(FLock);
    end;
    if mFinished <> '' then
      Log(mFinished);
  end;
end;

procedure TLspWorkspaceCheck.Requeue(const AEntry: TEntry; AFront: Boolean);
begin
  TMonitor.Enter(FLock);
  try
    FCurrent := '';
    if FStopping then
      Exit;
    // Inzwischen neu eingestellt (Start, Affected): der neue Eintrag genügt.
    if FQueued.ContainsKey(KeyOf(AEntry.FileName)) then
      Exit;
    // Ein erzwungener Neustart hat den Lauf beendet; die Datei gehört in den neuen.
    if not FRun.Active then
    begin
      BeginRunLocked;
      Inc(FRun.Total);
    end;
    if AFront then
      FQueue.Insert(0, AEntry)
    else
      FQueue.Add(AEntry);
    FQueued.Add(KeyOf(AEntry.FileName), AEntry.Forced);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLspWorkspaceCheck.Settle(const AUri: string);
begin
  // Datei ohne neue Befunde erledigt (geöffnet, unverändert, fehlt).
  TMonitor.Enter(FLock);
  try
    FCurrent := '';
    // Höchstens Total: Eine nicht unterbrechbare Datei kann nach einem Neustart noch im alten Lauf enden.
    if FRun.Active and (FRun.Done < FRun.Total) then
      Inc(FRun.Done);
    Changed;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLspWorkspaceCheck.Store(const AUri: string; AStamp: Int64; AItems: TJSONArray; AFailed: Boolean);
begin
  TMonitor.Enter(FLock);
  try
    FCurrent := '';
    if FStopping then
    begin
      AItems.Free;
      Exit;
    end;
    Inc(FSerial);
    FReports.AddOrSetValue(AUri, AItems);
    FIds.AddOrSetValue(AUri, Format('w%d.%d:t%d', [FSession, FSerial, AStamp]));
    FStamps.AddOrSetValue(AUri, AStamp);
    Inc(FComputed);
    if FRun.Active and (FRun.Done < FRun.Total) then
    begin
      Inc(FRun.Done);
      Inc(FRunComputed);
      if AFailed then
        Inc(FRun.Skipped);
    end;
    if AFailed then
      Inc(FSkipped);
    Changed;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLspWorkspaceCheck.Process(const AEntry: TEntry);
var
  mUri, mText: string;
  mStamp, mKnown: Int64;
  mUnchanged: Boolean;
  mDocument: ITextDocument;
  mItems: TJSONArray;
  mRetry: TEntry;
  mLimit: Int64;
begin
  mUri := TDocumentUris.FromPath(AEntry.FileName);
  // Geöffnete Dateien prüft textDocument/diagnostic mit dem Editortext.
  if (Assigned(FIsOpen) and FIsOpen(mUri)) or not FStamp(AEntry.FileName, mStamp) then
  begin
    Settle(mUri);
    Exit;
  end;
  TMonitor.Enter(FLock);
  try
    mUnchanged := not AEntry.Forced and FStamps.TryGetValue(mUri, mKnown) and (mKnown = mStamp);
  finally
    TMonitor.Exit(FLock);
  end;
  if mUnchanged or not FReadText(AEntry.FileName, mText) then
  begin
    Settle(mUri);
    Exit;
  end;
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  mDocument := TTextDocument.Create(mUri, 'objectpascal', 0, mText);
  mLimit := FFileLimitMs;
  if AEntry.Unlimited then
    mLimit := 0;
  try
    mItems := FDiagnose(mDocument, TCheckToken.Create(Self, mLimit, not AEntry.Unlimited));
  except
    on EWorkspaceCheckInterrupted do
    begin
      Requeue(AEntry, True);
      Exit;
    end;
    on EWorkspaceCheckDeadline do
    begin
      // Zu langsam für den ersten Durchgang (#1220): am Ende ohne Frist zu Ende prüfen.
      mRetry := AEntry;
      mRetry.Unlimited := True;
      mRetry.Forced := True;
      Requeue(mRetry, False);
      Exit;
    end;
    on E: Exception do
    begin
      if Interrupted(False) then
      begin
        Requeue(AEntry, True);
        Exit;
      end;
      // Datei überspringen (#1094): leer bis zur nächsten Änderung, die übrigen weiter prüfen.
      TStackGuard.AfterError(E);
      Log(Format('Projektprüfung: %s übersprungen (%s)', [LabelOf(AEntry.FileName), E.ClassName]));
      Store(mUri, mStamp, TJSONArray.Create, True);
      Exit;
    end;
  end;
  Store(mUri, mStamp, mItems, False);
end;

procedure TLspWorkspaceCheck.Work;
var
  mEntry: TEntry;
begin
  while NextEntry(mEntry) do
    Process(mEntry);
end;

function TLspWorkspaceCheck.Collect(const APrevious: TDictionary<string, string>; AMax: Integer): TJSONArray;
var
  mPair: TPair<string, string>;
  mKnown: string;
  mItems: TJSONArray;
  mReport: TJSONObject;
  mCandidates: TList<TJSONObject>;
  mUri: string;
begin
  Result := TJSONArray.Create;
  mCandidates := TList<TJSONObject>.Create;
  try
    TMonitor.Enter(FLock);
    try
      for mPair in FIds do
      begin
        if APrevious.TryGetValue(mPair.Key, mKnown) and (mKnown = mPair.Value) then
          Continue;
        if not FReports.TryGetValue(mPair.Key, mItems) then
          Continue;
        mReport := TJSONObject.Create;
        mReport.AddPair('uri', mPair.Key);
        mReport.AddPair('version', TJSONNull.Create);
        mReport.AddPair('kind', 'full');
        mReport.AddPair('resultId', mPair.Value);
        mReport.AddPair('items', mItems.Clone as TJSONArray);
        mCandidates.Add(mReport);
      end;
    finally
      TMonitor.Exit(FLock);
    end;
    // Außerhalb der Sperre: Der Dokumentspeicher sperrt selbst.
    for mReport in mCandidates do
    begin
      mUri := mReport.GetValue<string>('uri');
      if (Result.Count < AMax) and not (Assigned(FIsOpen) and FIsOpen(mUri)) then
        Result.AddElement(mReport)
      else
        mReport.Free;
    end;
  finally
    mCandidates.Free;
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
      TMonitor.Wait(FLock, AWaitMs);
    Result := FChange;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TLspWorkspaceCheck.Run: TWorkspaceCheckRun;
begin
  TMonitor.Enter(FLock);
  try
    Result := FRun;
    if FRun.Active then
      Result.ElapsedMs := FRunClock.ElapsedMilliseconds;
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
    while (FRun.Active or (FQueue.Count > 0) or (FCurrent <> '')) and
      (mClock.ElapsedMilliseconds < Int64(ATimeoutMs)) do
      TMonitor.Wait(FLock, cSliceMs);
    Result := not (FRun.Active or (FQueue.Count > 0) or (FCurrent <> ''));
  finally
    TMonitor.Exit(FLock);
  end;
end;

class function TLspWorkspaceCheck.DependentsOf(const AUnits: TArray<TUnitIndex>;
  const AFileName: string): TArray<string>;
var
  mUnit: TUnitIndex;
  mName, mUsed, mInclude: string;
  mIsInclude: Boolean;
begin
  Result := nil;
  mIsInclude := SameText(ExtractFileExt(AFileName), '.inc');
  mName := ChangeFileExt(ExtractFileName(AFileName), '');
  for mUnit in AUnits do
  begin
    if mUnit.Library_ or (mUnit.FileName = '') or SameFileName(mUnit.FileName, AFileName) then
      Continue;
    if mIsInclude then
    begin
      for mInclude in mUnit.Includes do
        if SameFileName(mInclude, AFileName) then
        begin
          Result := Result + [mUnit.FileName];
          Break;
        end;
      Continue;
    end;
    for mUsed in mUnit.InterfaceUses + mUnit.ImplementationUses do
      if SameText(mUsed, mName) then
      begin
        Result := Result + [mUnit.FileName];
        Break;
      end;
  end;
end;

end.
