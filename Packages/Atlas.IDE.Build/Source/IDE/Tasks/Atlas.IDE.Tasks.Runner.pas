unit Atlas.IDE.Tasks.Runner;

// Projektaufgaben (#900) in der IDE:
// - Definitionen aus dem Abschnitt „tasks“ von atlas.json neben der .dproj
//   und der globalen %APPDATA%\Atlas\settings.json (Projekt vor global). Ein
//   Zeitgeber merkt Projektwechsel und geänderte Dateien und lädt neu; dann
//   werden Tasten und Statuszeilen neu angelegt. Verworfene Einträge stehen
//   einmal in der Meldungsansicht (Gruppe Atlas).
// - Start über Befehlspalette (Choose), Menü Atlas › Aufgaben (MenuItems,
//   RunFromMenu; das Modul Build baut daraus Einträge ohne Befehl, #1455),
//   Taste je Aufgabe (key; Konflikte meldet TAtlasIdeKeyBinding), „Alle
//   Prüfungen ausführen“ (Gruppe check nacheinander bzw. mit
//   tasks.runChecksParallel gleichzeitig), „Letzte Aufgabe wiederholen“,
//   Statuszeile und Schnellaktion der Willkommensseite (RunInProject).
//   Vorher speichert tasks.saveBeforeRun geänderte Dateien.
// - Jeder Lauf ist ein eigener Thread (TWorker) mit eigenem Prozess
//   (TAtlasTaskProcessRun aus der Kompositionswurzel, dort
//   TAtlasTaskProcess: Job-Objekt, Zeitlimit, Abbruch). Zeilen und erkannte
//   Fundstellen kommen gesammelt alle 100 ms über TAtlasMainThread ins
//   Register „Atlas-Aufgaben“ (TAtlasIdeTaskOutput); Pfade löst der Thread
//   gegen Arbeitsordner, Projektdateien und Suchpfad auf.
// - Ende eines Laufs: Kopfzeile grün/rot, letzter Lauf in tasks.json
//   (%APPDATA%\Atlas) und im Statusfeld, mit tasks.problemsFromOutput die
//   Befunde im Problemspeicher (Quelle = Aufgabenname; ein Abbruch lässt die
//   vorigen stehen). Ausgeblendete Aufgaben (ChooseFindings) merkt sich
//   tasks.json je Projekt.
// - Vor dem Build (BeforeCompile, über CreateParticipant an den
//   Compile-Ereignissen #527): Entscheidung in TAtlasTaskPreBuild. Mit block
//   bricht Atlas den Build ab, lässt die Prüfungen im Hintergrund laufen
//   (die IDE bleibt bedienbar) und baut nach bestandenem Lauf über OnRebuild
//   neu; ein Verstoß meldet „Name: n Fehler, Build abgebrochen“ in der Gruppe
//   Atlas, wie der Release-Wächter (#529). Mit warn läuft der Build sofort.
// - Destroy bricht laufende Aufgaben ab und wartet auf ihre Threads; was sie
//   danach noch einreihen, prüft den Merker TAlive und tut nichts.
// Nur im Hauptthread (außer TWorker.Execute).
// Projekte, Dateien und Meldungen: Atlas.IDE.Tasks.Projects; Tasten und
// Statuszeilen: Atlas.IDE.Tasks.Shortcuts; Palettenfenster:
// Atlas.IDE.Tasks.Pickers.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.ExtCtrls,
  Atlas.Core.Build.Events,
  Atlas.Core.Tasks.Definitions,
  Atlas.Core.Tasks.Matchers,
  Atlas.Core.Tasks.Runs,
  Atlas.Core.Tasks.PreBuild,
  Atlas.IDE.Tasks.Output,
  Atlas.IDE.Tasks.Projects,
  Atlas.IDE.Tasks.Shortcuts;

type
  /// <summary>Eintrag im Untermenü Atlas › Aufgaben.</summary>
  TAtlasTaskMenuItem = record
    Name: string;
    Caption: string;
  end;

  /// <summary>Führt die (mit Variablen eingesetzte) Aufgabe aus, nicht im Hauptthread. ACancelled wird im Takt
  /// gefragt; ACodePage für Ausgaben, die kein UTF-8 sind (0 = OEM-Codepage); jede Zeile geht an AOnLine. Die
  /// Kompositionswurzel reicht den Adapter (Atlas.Core.Tasks.Adapters.Process) hinein (Rollenmatrix).</summary>
  TAtlasTaskProcessRun = reference to function(const ATask: TAtlasTaskDefinition; ACodePage: Integer;
    const ACancelled: TFunc<Boolean>; const AOnLine: TAtlasTaskLineProc): TAtlasTaskProcessResult;
  /// <summary>Build nach bestandener Prüfung neu starten; False mit Grund.</summary>
  TAtlasTasksRebuildFunc = reference to function(const AProject: TAtlasCompileProject; out AReason: string): Boolean;
  /// <summary>Ein Lauf ist fertig (Projekt-.dproj, '' ohne Projekt).</summary>
  TAtlasTasksFinishedProc = reference to procedure(const AProject: string; const ARun: TAtlasTaskRun);

  TAtlasIdeTasks = class
  private type
    TAlive = class(TInterfacedObject)
    public
      Alive: Boolean;
    end;

    /// <summary>Merker, ob der Läufer noch lebt, und eine Referenz, die ihn für eingereihte Einträge hält.</summary>
    TKeepAlive = record
      Flag: TAlive;
      Ref: IInterface;
    end;

    /// <summary>Abbruch eines Laufs; der Thread fragt Cancelled im Takt.</summary>
    TFlag = class(TInterfacedObject)
    public
      Cancelled: Boolean;
    end;

    TWorker = class(TThread)
    private
      FOwner: TAtlasIdeTasks;
      FAlive: TKeepAlive;
      FFlag: TFlag;
      FFlagRef: IInterface;
      FId: Integer;
      FTask: TAtlasTaskDefinition;
      FProcess: TAtlasTaskProcessRun;
      FProjectFiles: TArray<string>;
      FSearchPath: TArray<string>;
      FPendingLines: TArray<string>;
      FPendingFindings: TAtlasTaskFindings;
      // Stand des Laufs im Thread.
      FRun: TAtlasTaskRun;
      FLineCount: Integer;
      FLastFlush: UInt64;
      FExists: TAtlasTaskFileExists;
      procedure Deliver;
      procedure Finish(const ARun: TAtlasTaskRun);
      /// <summary>Zeile der Ausgabe: Fundstelle erkennen, merken und gesammelt weitergeben.</summary>
      procedure TakeLine(AMatcher: TAtlasTaskLineMatcher; const ALine: string);
      function RunProcess: TAtlasTaskProcessResult;
    protected
      procedure Execute; override;
    public
      constructor Create(AOwner: TAtlasIdeTasks; AId: Integer; const ATask: TAtlasTaskDefinition;
        const AProjectFiles, ASearchPath: TArray<string>);
      destructor Destroy; override;
      procedure Cancel;
    end;

    TJob = class
      FId: Integer;
      FName: string;
      FProject: string;
      FWorker: TWorker;
      /// <summary>Lauf gehört zu einer Reihe (Batch); 0 = einzeln.</summary>
      FBatch: Integer;
      FMode: TAtlasTaskBeforeBuild;
      FDone: Boolean;
      destructor Destroy; override;
    end;

    /// <summary>Mehrere Läufe: „Alle Prüfungen“ bzw. vor dem Build; nacheinander oder gleichzeitig.</summary>
    TBatch = class
      FId: Integer;
      FProject: string;
      FPreBuild: Boolean;
      FWaiting: TAtlasTaskDefinitions;
      FWaitingModes: TArray<TAtlasTaskBeforeBuild>;
      FRunning: Integer;
      FEntries: TArray<TAtlasTaskGateEntry>;
    end;

    /// <summary>Laufende und fertige Läufe und Reihen.</summary>
    TRuns = record
      Jobs: TObjectList<TJob>;
      Batches: TObjectList<TBatch>;
      NextId: Integer;
    end;

    /// <summary>Geladene Aufgaben des aktiven Projekts; der Zeitgeber merkt Änderungen.</summary>
    TLoaded = record
      Project: string;
      Signature: string;
      Tasks: TAtlasTaskDefinitions;
      IssuesShown: string;
      Timer: TTimer;
      /// <summary>TaskNamesOf: Namen je Projekt, damit die Willkommensseite nicht bei jedem Neuaufbau die
      /// atlas.json liest.</summary>
      Names: TAtlasIdeTaskNames;
    end;

    /// <summary>Verlauf in tasks.json; Kept = gesperrt gelesen, nicht überschreiben (Bericht N3).</summary>
    THistory = record
      Data: TAtlasTaskHistory;
      Kept: Boolean;
    end;

    /// <summary>Letzte einzeln gestartete Aufgabe (wiederholen).</summary>
    TLast = record
      Name: string;
      Project: string;
    end;

    THandlers = record
      OnRebuild: TAtlasTasksRebuildFunc;
      OnFinished: TAtlasTasksFinishedProc;
    end;
  private
    FProcess: TAtlasTaskProcessRun;
    FAlive: TKeepAlive;
    FOutput: TAtlasIdeTaskOutput;
    FHistory: THistory;
    FPreBuild: TAtlasTaskPreBuild;
    FRuns: TRuns;
    FShortcuts: TAtlasIdeTaskShortcuts;
    FLoaded: TLoaded;
    FLast: TLast;
    FHandlers: THandlers;
    procedure Tick(Sender: TObject);
    procedure Refresh(AForce: Boolean);
    procedure UpdateStatus(const AName: string);
    function IsRunning(const AProject, AName: string): Boolean;
    function Start(const AProject: string; const ATask: TAtlasTaskDefinition; ABatch: Integer;
      AMode: TAtlasTaskBeforeBuild; AShow: Boolean): Boolean;
    procedure StartBatch(const AProject: string; const ATasks: TAtlasTaskDefinitions;
      const AModes: TArray<TAtlasTaskBeforeBuild>; APreBuild: Boolean);
    procedure StartNextOf(ABatch: TBatch);
    procedure BatchDone(ABatch: TBatch);
    procedure WorkerFinished(AId: Integer; const ARun: TAtlasTaskRun);
    function LastText(const AProject, AName: string): string;
  public
    /// <summary>AProcess startet den Prozess einer Aufgabe (Kompositionswurzel: TAtlasTaskProcess.Run).</summary>
    constructor Create(const AProcess: TAtlasTaskProcessRun);
    destructor Destroy; override;
    /// <summary>Aufgaben des aktiven Projekts (lädt neu, wenn sich etwas geändert hat).</summary>
    function Definitions: TAtlasTaskDefinitions;
    /// <summary>Namen der Aufgaben von AProject (Schnellaktion „Aufgaben ▾“); neu gelesen nur nach Änderung der
    /// atlas.json bzw. der globalen Datei.</summary>
    function TaskNamesOf(const AProject: string): TArray<string>;
    /// <summary>Palettenfenster „Aufgabe ausführen …“.</summary>
    procedure Choose;
    /// <summary>Aufgabe AName des aktiven Projekts; False mit Grund.</summary>
    function RunByName(const AName: string; out AReason: string): Boolean;
    /// <summary>Aufgabe AName des Projekts AProject (Schnellaktion, auch nicht geöffnete Projekte).</summary>
    function RunInProject(const AProject, AName: string; out AReason: string): Boolean;
    procedure RunChecks;
    procedure RepeatLast;
    procedure CancelAll;
    /// <summary>„nur Befunde“ / „ganze Ausgabe“ umschalten (tasks.onlyFindings).</summary>
    procedure ToggleOutput;
    /// <summary>Palette: Befunde je Aufgabe ein- oder ausblenden.</summary>
    procedure ChooseFindings;
    /// <summary>Einträge des Untermenüs Atlas › Aufgaben für das aktive Projekt: Name und Text („Gruppe: Name
    /// (letzter Lauf)“ mit Taste).</summary>
    function MenuItems: TArray<TAtlasTaskMenuItem>;
    /// <summary>Aufgabe AName aus dem Menü starten; ein Grund für „nicht gestartet“ erscheint in der
    /// Meldungsansicht.</summary>
    procedure RunFromMenu(const AName: string);
    /// <summary>Vor einem Compile (Compile-Ereignisse): True bricht ab, AReason für das Meldungsfenster.</summary>
    function BeforeCompile(const AProject: TAtlasCompileProject; out AReason: string): Boolean;
    /// <summary>Einstellungen übernehmen (tasks.onlyFindings, Tasten).</summary>
    procedure ApplySettings;
    /// <summary>Läuft eine Aufgabe?</summary>
    function Busy: Boolean;
    /// <summary>Teilnehmer der Compile-Ereignisse, der an AGet() weitergibt (nil = nichts).</summary>
    class function CreateParticipant(const AGet: TFunc<TAtlasIdeTasks>): TAtlasCompileParticipant; static;
    property OnRebuild: TAtlasTasksRebuildFunc read FHandlers.OnRebuild write FHandlers.OnRebuild;
    property OnFinished: TAtlasTasksFinishedProc read FHandlers.OnFinished write FHandlers.OnFinished;
  end;

implementation

uses
  Atlas.Core.Status.Contract,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Problems.Store,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Tasks.Reports,
  Atlas.UI.Strings,
  Atlas.UI.Build.Strings,
  Atlas.UI.Tasks.Texts,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Problems.Controller,
  Atlas.IDE.Tasks.Pickers;

const
  cRefreshMs = 2000;
  cFlushMs = 100;
  cHistoryWhat = 'Verlauf der Projektaufgaben';

type
  /// <summary>Gibt CancelCompile an die Aufgaben weiter (die Ereignisse besitzen den Teilnehmer).</summary>
  TParticipant = class(TAtlasCompileParticipant)
  private
    FGet: TFunc<TAtlasIdeTasks>;
  public
    constructor Create(const AGet: TFunc<TAtlasIdeTasks>);
    function CancelCompile(const AProject: TAtlasCompileProject; out AReason: string): Boolean; override;
  end;

{ TParticipant }

constructor TParticipant.Create(const AGet: TFunc<TAtlasIdeTasks>);
begin
  inherited Create;
  FGet := AGet;
end;

function TParticipant.CancelCompile(const AProject: TAtlasCompileProject; out AReason: string): Boolean;
var
  mTasks: TAtlasIdeTasks;
begin
  AReason := '';
  mTasks := FGet();
  Result := (mTasks <> nil) and mTasks.BeforeCompile(AProject, AReason);
end;

function ExistsProc: TAtlasTaskFileExists;
begin
  Result :=
    function(const AFileName: string): Boolean
    begin
      Result := FileExists(AFileName);
    end;
end;

/// <summary>Lebt der Läufer noch? Hält nur den Merker, nicht den Läufer.</summary>
function AliveCheck(const AKeep: TAtlasIdeTasks.TKeepAlive): TFunc<Boolean>;
var
  mFlag: TAtlasIdeTasks.TAlive;
  mRef: IInterface;
begin
  mFlag := AKeep.Flag;
  mRef := AKeep.Ref;
  Result :=
    function: Boolean
    begin
      Result := (mRef <> nil) and mFlag.Alive;
    end;
end;

function RunByNameOf(AOwner: TAtlasIdeTasks): TAtlasTaskRunByName;
begin
  Result :=
    function(const AName: string; out AReason: string): Boolean
    begin
      Result := AOwner.RunByName(AName, AReason);
    end;
end;

procedure LoadHistory(var AHistory: TAtlasIdeTasks.THistory);
var
  mData: TAtlasTaskHistory;
begin
  mData := AHistory.Data;
  AHistory.Kept := not TAtlasDataFile.Writable(TAtlasDataFile.Load(TAtlasIdeTaskProjects.HistoryFile, cHistoryWhat,
    function(const AText: string): Boolean
    begin
      Result := mData.FromJson(AText);
    end));
end;

procedure SaveHistory(const AHistory: TAtlasIdeTasks.THistory);
begin
  // Gesperrt gelesene Datei nicht mit dem Stand dieser Sitzung überschreiben (Bericht N3).
  if AHistory.Kept then
  begin
    Exit;
  end;
  try
    TAtlasDataFile.Write(TAtlasIdeTaskProjects.HistoryFile, AHistory.Data.ToJson);
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten(cHistoryWhat, E);
  end;
end;

{ TAtlasIdeTasks.TWorker }

constructor TAtlasIdeTasks.TWorker.Create(AOwner: TAtlasIdeTasks; AId: Integer; const ATask: TAtlasTaskDefinition;
  const AProjectFiles, ASearchPath: TArray<string>);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FOwner := AOwner;
  FAlive := AOwner.FAlive;
  FFlag := TFlag.Create;
  FFlagRef := FFlag;
  FId := AId;
  FTask := ATask;
  FProcess := AOwner.FProcess;
  FProjectFiles := AProjectFiles;
  FSearchPath := ASearchPath;
end;

destructor TAtlasIdeTasks.TWorker.Destroy;
begin
  FFlagRef := nil;
  FAlive.Ref := nil;
  FProcess := nil;
  FExists := nil;
  inherited Destroy;
end;

procedure TAtlasIdeTasks.TWorker.Cancel;
begin
  FFlag.Cancelled := True;
  Terminate;
end;

procedure TAtlasIdeTasks.TWorker.Deliver;
var
  mLines: TArray<string>;
  mFindings: TAtlasTaskFindings;
  mOwner: TAtlasIdeTasks;
  mAlive: TFunc<Boolean>;
  mId: Integer;
begin
  if (Length(FPendingLines) = 0) and (Length(FPendingFindings) = 0) then
  begin
    Exit;
  end;
  mLines := FPendingLines;
  mFindings := FPendingFindings;
  FPendingLines := nil;
  FPendingFindings := nil;
  mOwner := FOwner;
  mAlive := AliveCheck(FAlive);
  mId := FId;
  TAtlasMainThread.Queue(TAtlasFeature.Tasks,
    procedure
    begin
      if mAlive() then
      begin
        mOwner.FOutput.Lines(mId, mLines, mFindings);
      end;
    end);
end;

procedure TAtlasIdeTasks.TWorker.Finish(const ARun: TAtlasTaskRun);
var
  mRun: TAtlasTaskRun;
  mOwner: TAtlasIdeTasks;
  mAlive: TFunc<Boolean>;
  mId: Integer;
begin
  mRun := ARun;
  mOwner := FOwner;
  mAlive := AliveCheck(FAlive);
  mId := FId;
  TAtlasMainThread.Queue(TAtlasFeature.Tasks,
    procedure
    begin
      if mAlive() then
      begin
        mOwner.WorkerFinished(mId, mRun);
      end;
    end);
end;

procedure TAtlasIdeTasks.TWorker.TakeLine(AMatcher: TAtlasTaskLineMatcher; const ALine: string);
var
  mFinding: TAtlasTaskFinding;
begin
  if AMatcher.Match(ALine, mFinding) then
  begin
    mFinding.OutputLine := FLineCount;
    if mFinding.FileName <> '' then
    begin
      mFinding.FileName := TAtlasTaskPaths.Resolve(mFinding.FileName, FTask.Cwd, FProjectFiles, FSearchPath,
        FExists);
    end;
    FRun.Findings := FRun.Findings + [mFinding];
    FPendingFindings := FPendingFindings + [mFinding];
  end;
  // Die Anzeige kappt selbst; gemerkt werden höchstens so viele Zeilen wie dort.
  if FLineCount < TAtlasIdeTaskOutput.cMaxLines then
  begin
    FRun.Lines := FRun.Lines + [ALine];
  end;
  Inc(FLineCount);
  FPendingLines := FPendingLines + [ALine];
  if TThread.GetTickCount64 - FLastFlush >= cFlushMs then
  begin
    Deliver;
    FLastFlush := TThread.GetTickCount64;
  end;
end;

function TAtlasIdeTasks.TWorker.RunProcess: TAtlasTaskProcessResult;
var
  mMatcher: TAtlasTaskLineMatcher;
  mFlag: TFlag;
begin
  mFlag := FFlag;
  mMatcher := TAtlasTaskLineMatcher.Create(FTask.Matcher);
  try
    Result := FProcess(FTask, 0,
      function: Boolean
      begin
        Result := mFlag.Cancelled or TAtlasShutdown.Signalled;
      end,
      procedure(const ALine: string)
      begin
        TakeLine(mMatcher, ALine);
      end);
    // Ungültiges eigenes Muster: Die Ausgabe läuft ohne Befunde, der Grund steht darunter.
    if mMatcher.Error <> '' then
    begin
      FPendingLines := FPendingLines + [mMatcher.Error];
    end;
  finally
    mMatcher.Free;
  end;
end;

procedure TAtlasIdeTasks.TWorker.Execute;
var
  mOutcome: TAtlasTaskProcessResult;
  mStarted: UInt64;
begin
  FRun := Default(TAtlasTaskRun);
  FRun.Name := FTask.Name;
  FRun.CommandLine := FTask.CommandLine;
  FRun.Cwd := FTask.Cwd;
  mStarted := TThread.GetTickCount64;
  FLastFlush := mStarted;
  FExists := ExistsProc();
  FLineCount := 0;
  try
    mOutcome := RunProcess;
    Deliver;
    FRun.Outcome := mOutcome.Outcome;
    FRun.ExitCode := mOutcome.ExitCode;
    FRun.Error := mOutcome.Error;
  except
    on E: Exception do
    begin
      FRun.Outcome := TAtlasTaskOutcome.StartFailed;
      FRun.ExitCode := -1;
      FRun.Error := E.Message;
    end;
  end;
  FRun.DurationMs := Int64(TThread.GetTickCount64 - mStarted);
  FRun.FinishedAt := Now;
  Finish(FRun);
end;

{ TAtlasIdeTasks.TJob }

destructor TAtlasIdeTasks.TJob.Destroy;
begin
  if FWorker <> nil then
  begin
    FWorker.Cancel;
    FWorker.WaitFor;
    FreeAndNil(FWorker);
  end;
  inherited Destroy;
end;

{ TAtlasIdeTasks }

constructor TAtlasIdeTasks.Create(const AProcess: TAtlasTaskProcessRun);
begin
  inherited Create;
  FProcess := AProcess;
  FAlive.Flag := TAlive.Create;
  FAlive.Flag.Alive := True;
  FAlive.Ref := FAlive.Flag;
  FOutput := TAtlasIdeTaskOutput.Create;
  FOutput.OnlyFindings := TAtlasIdeSettings.Current.TasksOnlyFindings;
  FHistory.Data := TAtlasTaskHistory.Create;
  FPreBuild := TAtlasTaskPreBuild.Create;
  FRuns.Jobs := TObjectList<TJob>.Create(True);
  FRuns.Batches := TObjectList<TBatch>.Create(True);
  FShortcuts := TAtlasIdeTaskShortcuts.Create;
  FLoaded.Names := TAtlasIdeTaskNames.Create;
  LoadHistory(FHistory);
  FLoaded.Timer := TTimer.Create(nil);
  FLoaded.Timer.Interval := cRefreshMs;
  FLoaded.Timer.OnTimer := Tick;
  FLoaded.Timer.Enabled := True;
  Refresh(True);
end;

destructor TAtlasIdeTasks.Destroy;
begin
  FAlive.Flag.Alive := False;
  FreeAndNil(FLoaded.Timer);
  // Laufende Aufgaben beenden (Job-Objekt) und auf ihre Threads warten.
  FreeAndNil(FRuns.Jobs);
  FreeAndNil(FRuns.Batches);
  if FPreBuild <> nil then
  begin
    FPreBuild.Abandon;
  end;
  FreeAndNil(FShortcuts);
  FreeAndNil(FLoaded.Names);
  FreeAndNil(FPreBuild);
  FreeAndNil(FHistory.Data);
  // Schutznetz: Scheitert das Leeren des Registers, wird der Läufer trotzdem ganz abgebaut.
  try
    if FOutput <> nil then
    begin
      FOutput.Clear;
    end;
  finally
    FreeAndNil(FOutput);
    FAlive.Ref := nil;
    inherited Destroy;
  end;
end;

class function TAtlasIdeTasks.CreateParticipant(const AGet: TFunc<TAtlasIdeTasks>): TAtlasCompileParticipant;
begin
  Result := TParticipant.Create(AGet);
end;

function TAtlasIdeTasks.TaskNamesOf(const AProject: string): TArray<string>;
begin
  Result := FLoaded.Names.NamesOf(AProject);
end;

function TAtlasIdeTasks.Definitions: TAtlasTaskDefinitions;
begin
  Refresh(False);
  Result := FLoaded.Tasks;
end;

procedure TAtlasIdeTasks.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Tasks,
    procedure
    begin
      Refresh(False);
    end);
end;

procedure TAtlasIdeTasks.Refresh(AForce: Boolean);
var
  mProject, mSignature, mShown, mIssue: string;
  mIssues: TArray<string>;
  mTask: TAtlasTaskDefinition;
begin
  mProject := TAtlasIdeTaskProjects.ActiveProject;
  mSignature := TAtlasIdeTaskProjects.SignatureOf(mProject);
  if not AForce and (mSignature = FLoaded.Signature) then
  begin
    Exit;
  end;
  FLoaded.Signature := mSignature;
  FLoaded.Project := mProject;
  FLoaded.Tasks := TAtlasIdeTaskProjects.DefinitionsOf(mProject, mIssues);
  // Verworfene Einträge einmal je Stand melden.
  mShown := string.Join(#10, mIssues);
  if (mShown <> '') and (mShown <> FLoaded.IssuesShown) then
  begin
    for mIssue in mIssues do
    begin
      TAtlasIdeTaskProjects.Say(TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksIssue, [ExtractFileName(mProject),
        mIssue]), False);
    end;
  end;
  FLoaded.IssuesShown := mShown;
  FShortcuts.Rebuild(FLoaded.Tasks, RunByNameOf(Self), AliveCheck(FAlive));
  for mTask in FLoaded.Tasks do
  begin
    UpdateStatus(mTask.Name);
  end;
end;

procedure TAtlasIdeTasks.ApplySettings;
begin
  FOutput.OnlyFindings := TAtlasIdeSettings.Current.TasksOnlyFindings;
  Refresh(True);
end;

function TAtlasIdeTasks.LastText(const AProject, AName: string): string;
var
  mLast: TAtlasTaskLastRun;
  mHas: Boolean;
begin
  if IsRunning(AProject, AName) then
  begin
    Exit(TAtlasBuildStrings.Text(TAtlasBuildTextId.TasksRunningShort));
  end;
  mHas := FHistory.Data.LastRun(AProject, AName, mLast);
  Result := TAtlasTaskTexts.LastResult(mLast, mHas);
end;

procedure TAtlasIdeTasks.UpdateStatus(const AName: string);
var
  mLast: TAtlasTaskLastRun;
  mState: TAtlasStatusState;
  mKey: string;
begin
  mKey := TAtlasIdeTaskProjects.KeyOf(FLoaded.Project);
  mState := TAtlasStatusState.Neutral;
  if not IsRunning(mKey, AName) and FHistory.Data.LastRun(mKey, AName, mLast) then
  begin
    if mLast.Passed then
    begin
      mState := TAtlasStatusState.Green;
    end
    else
    begin
      mState := TAtlasStatusState.Red;
    end;
  end;
  FShortcuts.Update(AName, AName + ': ' + LastText(mKey, AName), mState, LastText(mKey, AName));
end;

function TAtlasIdeTasks.IsRunning(const AProject, AName: string): Boolean;
var
  mJob: TJob;
begin
  for mJob in FRuns.Jobs do
  begin
    if not mJob.FDone and SameText(mJob.FName, AName) and SameText(mJob.FProject, AProject) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAtlasIdeTasks.Busy: Boolean;
var
  mJob: TJob;
begin
  for mJob in FRuns.Jobs do
  begin
    if not mJob.FDone then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Fertige Läufe abräumen (ihr Thread ist zu Ende).</summary>
procedure SweepDone(AJobs: TObjectList<TAtlasIdeTasks.TJob>);
var
  mJob: TAtlasIdeTasks.TJob;
begin
  for mJob in AJobs.ToArray do
  begin
    if mJob.FDone then
    begin
      AJobs.Remove(mJob);
    end;
  end;
end;

function TAtlasIdeTasks.Start(const AProject: string; const ATask: TAtlasTaskDefinition; ABatch: Integer;
  AMode: TAtlasTaskBeforeBuild; AShow: Boolean): Boolean;
var
  mJob: TJob;
  mTask: TAtlasTaskDefinition;
  mProjectFiles, mSearchPath: TArray<string>;
begin
  if IsRunning(TAtlasIdeTaskProjects.KeyOf(AProject), ATask.Name) then
  begin
    Exit(False);
  end;
  SweepDone(FRuns.Jobs);
  mTask := TAtlasTasks.Expand(ATask, TAtlasIdeTaskProjects.VariablesOf(AProject));
  mProjectFiles := TAtlasIdeTaskProjects.ProjectFilesOf(AProject, mSearchPath);
  Inc(FRuns.NextId);
  mJob := TJob.Create;
  mJob.FId := FRuns.NextId;
  mJob.FName := ATask.Name;
  mJob.FProject := TAtlasIdeTaskProjects.KeyOf(AProject);
  mJob.FBatch := ABatch;
  mJob.FMode := AMode;
  FRuns.Jobs.Add(mJob);
  FOutput.Started(mJob.FId, mTask.Name, mTask.CommandLine, mTask.TimeoutSec, AShow);
  mJob.FWorker := TWorker.Create(Self, mJob.FId, mTask, mProjectFiles, mSearchPath);
  mJob.FWorker.Start;
  if ABatch = 0 then
  begin
    FLast.Name := ATask.Name;
    FLast.Project := AProject;
  end;
  UpdateStatus(ATask.Name);
  Result := True;
end;

procedure SaveBeforeRun;
begin
  if TAtlasIdeSettings.Current.TasksSaveBeforeRun then
  begin
    TAtlasIdeTaskProjects.SaveModified;
  end;
end;

function TAtlasIdeTasks.RunInProject(const AProject, AName: string; out AReason: string): Boolean;
var
  mTasks: TAtlasTaskDefinitions;
  mIssues: TArray<string>;
  mIndex: Integer;
begin
  AReason := '';
  Result := False;
  if not TAtlasIdeSettings.Current.TasksEnabled then
  begin
    AReason := TAtlasBuildStrings.Text(TAtlasBuildTextId.WelcomeQuickReasonTasksOff);
    Exit;
  end;
  if SameText(AProject, FLoaded.Project) then
  begin
    mTasks := Definitions;
  end
  else
  begin
    mTasks := TAtlasIdeTaskProjects.DefinitionsOf(AProject, mIssues);
  end;
  mIndex := TAtlasTasks.IndexOf(mTasks, AName);
  if mIndex < 0 then
  begin
    AReason := TAtlasBuildStrings.Text(TAtlasBuildTextId.TasksNone);
    Exit;
  end;
  SaveBeforeRun;
  Result := Start(AProject, mTasks[mIndex], 0, TAtlasTaskBeforeBuild.Off, True);
  if not Result then
  begin
    AReason := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksAlreadyRunning, [AName]);
  end;
end;

function TAtlasIdeTasks.RunByName(const AName: string; out AReason: string): Boolean;
begin
  Refresh(False);
  Result := RunInProject(FLoaded.Project, AName, AReason);
end;

procedure TAtlasIdeTasks.RepeatLast;
var
  mReason: string;
begin
  if FLast.Name = '' then
  begin
    TAtlasIdeTaskProjects.Say(TAtlasBuildStrings.Text(TAtlasBuildTextId.TasksNoLast), True);
    Exit;
  end;
  if not RunInProject(FLast.Project, FLast.Name, mReason) and (mReason <> '') then
  begin
    TAtlasIdeTaskProjects.Say(mReason, True);
  end;
end;

procedure TAtlasIdeTasks.RunChecks;
var
  mChecks: TAtlasTaskDefinitions;
  mModes: TArray<TAtlasTaskBeforeBuild>;
  mIndex: Integer;
begin
  if not TAtlasIdeSettings.Current.TasksEnabled then
  begin
    Exit;
  end;
  mChecks := TAtlasTasks.OfGroup(Definitions, TAtlasTaskGroup.Check);
  if Length(mChecks) = 0 then
  begin
    TAtlasIdeTaskProjects.Say(TAtlasBuildStrings.Text(TAtlasBuildTextId.TasksNoChecks), True);
    Exit;
  end;
  SaveBeforeRun;
  SetLength(mModes, Length(mChecks));
  for mIndex := 0 to High(mModes) do
  begin
    mModes[mIndex] := TAtlasTaskBeforeBuild.Off;
  end;
  StartBatch(FLoaded.Project, mChecks, mModes, False);
end;

procedure TAtlasIdeTasks.StartBatch(const AProject: string; const ATasks: TAtlasTaskDefinitions;
  const AModes: TArray<TAtlasTaskBeforeBuild>; APreBuild: Boolean);
var
  mBatch: TBatch;
begin
  Inc(FRuns.NextId);
  mBatch := TBatch.Create;
  mBatch.FId := FRuns.NextId;
  mBatch.FProject := AProject;
  mBatch.FPreBuild := APreBuild;
  mBatch.FWaiting := ATasks;
  mBatch.FWaitingModes := AModes;
  FRuns.Batches.Add(mBatch);
  StartNextOf(mBatch);
end;

procedure TAtlasIdeTasks.StartNextOf(ABatch: TBatch);
var
  mTask: TAtlasTaskDefinition;
  mMode: TAtlasTaskBeforeBuild;
  mParallel: Boolean;
begin
  mParallel := TAtlasIdeSettings.Current.TasksRunChecksParallel;
  while Length(ABatch.FWaiting) > 0 do
  begin
    mTask := ABatch.FWaiting[0];
    mMode := ABatch.FWaitingModes[0];
    Delete(ABatch.FWaiting, 0, 1);
    Delete(ABatch.FWaitingModes, 0, 1);
    if Start(ABatch.FProject, mTask, ABatch.FId, mMode, not ABatch.FPreBuild) then
    begin
      Inc(ABatch.FRunning);
      if not mParallel then
      begin
        Exit;
      end;
    end;
  end;
  if ABatch.FRunning = 0 then
  begin
    BatchDone(ABatch);
  end;
end;

function FindBatch(ABatches: TObjectList<TAtlasIdeTasks.TBatch>; AId: Integer): TAtlasIdeTasks.TBatch;
var
  mBatch: TAtlasIdeTasks.TBatch;
begin
  for mBatch in ABatches do
  begin
    if mBatch.FId = AId then
    begin
      Exit(mBatch);
    end;
  end;
  Result := nil;
end;

/// <summary>Bestanden: neu bauen, nicht aus dem laufenden Rückruf heraus.</summary>
procedure QueueRebuild(const AProject: TAtlasCompileProject; const ARebuild: TAtlasTasksRebuildFunc;
  const AAlive: TFunc<Boolean>);
begin
  TAtlasMainThread.ForceQueue(TAtlasFeature.Tasks,
    procedure
    var
      mReason: string;
    begin
      if not AAlive() then
      begin
        Exit;
      end;
      TAtlasIdeTaskProjects.Say(TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksGatePassed,
        [ExtractFileName(AProject.FileName)]), False);
      if not ARebuild(AProject, mReason) then
      begin
        TAtlasIdeTaskProjects.Say(TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksGateRebuild, [mReason]), True);
      end;
    end);
end;

procedure TAtlasIdeTasks.BatchDone(ABatch: TBatch);
var
  mDecision: TAtlasTaskGateDecision;
  mRun: TAtlasTaskRun;
  mProject: TAtlasCompileProject;
begin
  if not ABatch.FPreBuild then
  begin
    FRuns.Batches.Remove(ABatch);
    Exit;
  end;
  mDecision := TAtlasTaskGate.Decide(ABatch.FEntries);
  FRuns.Batches.Remove(ABatch);
  for mRun in mDecision.Blocking do
  begin
    TAtlasIdeTaskProjects.Say(TAtlasTaskTexts.Blocked(mRun), True);
  end;
  for mRun in mDecision.Warnings do
  begin
    TAtlasIdeTaskProjects.Say(TAtlasTaskTexts.Header(mRun, 0), False);
  end;
  mProject := FPreBuild.Project;
  if not FPreBuild.Finish(not mDecision.Block, TThread.GetTickCount64) then
  begin
    Exit;
  end;
  if Assigned(FHandlers.OnRebuild) then
  begin
    QueueRebuild(mProject, FHandlers.OnRebuild, AliveCheck(FAlive));
  end
  else
  begin
    TAtlasIdeTaskProjects.Say(TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksGateRebuild,
      [ExtractFileName(mProject.FileName)]), True);
  end;
end;

/// <summary>Zeilen der Dateien für die Bereiche der Befunde, je Datei einmal gelesen.</summary>
function CachedReadLine(ACache: TDictionary<string, TArray<string>>): TAtlasTaskReadLine;
begin
  Result :=
    function(const AFileName: string; ALine: Integer; out AText: string): Boolean
    var
      mLines: TArray<string>;
      mKey: string;
    begin
      AText := '';
      mKey := AnsiLowerCase(AFileName);
      if not ACache.TryGetValue(mKey, mLines) then
      begin
        if not TAtlasIdeTaskProjects.ReadLines(AFileName, mLines) then
        begin
          mLines := nil;
        end;
        ACache.Add(mKey, mLines);
      end;
      Result := (ALine >= 0) and (ALine <= High(mLines));
      if Result then
      begin
        AText := mLines[ALine];
      end;
    end;
end;

/// <summary>Befunde des Laufs in den Problemspeicher (tasks.problemsFromOutput).</summary>
procedure ApplyProblems(const ARun: TAtlasTaskRun; AHidden: Boolean);
var
  mStore: TAtlasProblemStore;
  mCache: TDictionary<string, TArray<string>>;
begin
  mStore := TAtlasProblemsController.Current;
  if mStore = nil then
  begin
    Exit;
  end;
  if not TAtlasIdeSettings.Current.TasksProblemsFromOutput then
  begin
    mStore.ClearTask(ARun.Name);
    Exit;
  end;
  // Abgebrochen: die Befunde des vorigen Laufs bleiben stehen.
  if ARun.Outcome = TAtlasTaskOutcome.Cancelled then
  begin
    Exit;
  end;
  mCache := TDictionary<string, TArray<string>>.Create;
  try
    mStore.SetTaskProblems(ARun.Name, TAtlasTaskReports.Problems(ARun.Name, ARun.Findings, CachedReadLine(mCache)));
    mStore.SetTaskHidden(ARun.Name, AHidden);
  finally
    mCache.Free;
  end;
end;

function FindJob(AJobs: TObjectList<TAtlasIdeTasks.TJob>; AId: Integer): TAtlasIdeTasks.TJob;
var
  mItem: TAtlasIdeTasks.TJob;
begin
  Result := nil;
  for mItem in AJobs do
  begin
    if mItem.FId = AId then
    begin
      Result := mItem;
    end;
  end;
end;

procedure TAtlasIdeTasks.WorkerFinished(AId: Integer; const ARun: TAtlasTaskRun);
var
  mJob: TJob;
  mBatch: TBatch;
  mEntry: TAtlasTaskGateEntry;
  mProject: string;
begin
  mJob := FindJob(FRuns.Jobs, AId);
  if mJob = nil then
  begin
    Exit;
  end;
  mJob.FDone := True;
  // Der Thread hat nach diesem Eintrag nichts mehr zu tun.
  if mJob.FWorker <> nil then
  begin
    mJob.FWorker.WaitFor;
    FreeAndNil(mJob.FWorker);
  end;
  FOutput.Finished(AId, ARun);
  FHistory.Data.Remember(mJob.FProject, ARun);
  SaveHistory(FHistory);
  ApplyProblems(ARun, FHistory.Data.IsHidden(mJob.FProject, ARun.Name));
  if SameText(mJob.FProject, FLoaded.Project) or ((FLoaded.Project = '') and
    (mJob.FProject = TAtlasIdeTaskProjects.cNoProject)) then
  begin
    UpdateStatus(ARun.Name);
  end;
  mProject := mJob.FProject;
  if mProject = TAtlasIdeTaskProjects.cNoProject then
  begin
    mProject := '';
  end;
  if Assigned(FHandlers.OnFinished) then
  begin
    FHandlers.OnFinished(mProject, ARun);
  end;
  mBatch := nil;
  if mJob.FBatch <> 0 then
  begin
    mBatch := FindBatch(FRuns.Batches, mJob.FBatch);
  end;
  if mBatch = nil then
  begin
    Exit;
  end;
  mEntry.Mode := mJob.FMode;
  mEntry.Run := ARun;
  mBatch.FEntries := mBatch.FEntries + [mEntry];
  Dec(mBatch.FRunning);
  StartNextOf(mBatch);
end;

/// <summary>Verhalten je Aufgabe vor dem Build, ob eine blockiert bzw. warnt, und die Namen für die Meldung.
/// </summary>
procedure PlanPreBuild(const ATasks: TAtlasTaskDefinitions; AGlobal: TAtlasTaskBeforeBuild;
  out AModes: TArray<TAtlasTaskBeforeBuild>; out AHasBlock, AHasWarn: Boolean; out ANames: string);
var
  mTask: TAtlasTaskDefinition;
  mMode: TAtlasTaskBeforeBuild;
begin
  AModes := nil;
  AHasBlock := False;
  AHasWarn := False;
  ANames := '';
  for mTask in ATasks do
  begin
    mMode := mTask.BeforeBuildFor(AGlobal);
    AModes := AModes + [mMode];
    if mMode = TAtlasTaskBeforeBuild.Block then
    begin
      AHasBlock := True;
    end
    else
    begin
      AHasWarn := True;
    end;
    if ANames <> '' then
    begin
      ANames := ANames + ', ';
    end;
    ANames := ANames + mTask.Name;
  end;
end;

function TAtlasIdeTasks.BeforeCompile(const AProject: TAtlasCompileProject; out AReason: string): Boolean;
var
  mGlobal: TAtlasTaskBeforeBuild;
  mTasks: TAtlasTaskDefinitions;
  mModes: TArray<TAtlasTaskBeforeBuild>;
  mIssues: TArray<string>;
  mHasBlock, mHasWarn: Boolean;
  mNames: string;
  mAction: TAtlasTaskPreBuildAction;
begin
  AReason := '';
  Result := False;
  if not TAtlasIdeSettings.Current.TasksEnabled or not TAtlasTaskPreBuild.Applies(AProject) then
  begin
    Exit;
  end;
  TAtlasTasks.TryBeforeBuild(TAtlasIdeSettings.Current.TasksBeforeBuild, mGlobal);
  if SameText(AProject.FileName, FLoaded.Project) then
  begin
    mTasks := TAtlasTasks.BeforeBuild(Definitions, mGlobal);
  end
  else
  begin
    mTasks := TAtlasTasks.BeforeBuild(TAtlasIdeTaskProjects.DefinitionsOf(AProject.FileName, mIssues), mGlobal);
  end;
  PlanPreBuild(mTasks, mGlobal, mModes, mHasBlock, mHasWarn, mNames);
  mAction := FPreBuild.Decide(AProject, mHasBlock, mHasWarn, TThread.GetTickCount64);
  case mAction of
    TAtlasTaskPreBuildAction.StartAndCancel:
      AReason := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksGateRunning, [mNames]);
    TAtlasTaskPreBuildAction.Busy:
      AReason := TAtlasBuildStrings.Text(TAtlasBuildTextId.TasksGateBusy);
    TAtlasTaskPreBuildAction.None, TAtlasTaskPreBuildAction.StartWarn: ;
  end;
  Result := mAction in [TAtlasTaskPreBuildAction.StartAndCancel, TAtlasTaskPreBuildAction.Busy];
  if mAction in [TAtlasTaskPreBuildAction.StartWarn, TAtlasTaskPreBuildAction.StartAndCancel] then
  begin
    SaveBeforeRun;
    StartBatch(AProject.FileName, mTasks, mModes, True);
  end;
end;

/// <summary>Wartende Aufgaben einer Reihe starten nicht mehr.</summary>
procedure StopWaiting(ABatch: TAtlasIdeTasks.TBatch);
begin
  if ABatch <> nil then
  begin
    ABatch.FWaiting := nil;
    ABatch.FWaitingModes := nil;
  end;
end;

procedure TAtlasIdeTasks.CancelAll;
var
  mJob: TJob;
  mCount: Integer;
begin
  mCount := 0;
  for mJob in FRuns.Jobs do
  begin
    if not mJob.FDone and (mJob.FWorker <> nil) then
    begin
      mJob.FWorker.Cancel;
      Inc(mCount);
    end;
  end;
  // Wartende Aufgaben einer Reihe starten nicht mehr; ein abgebrochener Lauf vor dem Build baut nicht neu.
  for mJob in FRuns.Jobs do
  begin
    if not mJob.FDone and (mJob.FBatch <> 0) then
    begin
      StopWaiting(FindBatch(FRuns.Batches, mJob.FBatch));
    end;
  end;
  if FPreBuild.Running then
  begin
    FPreBuild.Abandon;
  end;
  if mCount = 0 then
  begin
    TAtlasIdeTaskProjects.Say(TAtlasBuildStrings.Text(TAtlasBuildTextId.TasksNothingRunning), True);
  end
  else
  begin
    TAtlasIdeTaskProjects.Say(TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksCancelledAll, [mCount]), False);
  end;
end;

procedure TAtlasIdeTasks.ToggleOutput;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Stored;
  mSettings.TasksOnlyFindings := not FOutput.OnlyFindings;
  TAtlasIdeSettings.Update(mSettings);
  FOutput.OnlyFindings := mSettings.TasksOnlyFindings;
  if FOutput.OnlyFindings then
  begin
    TAtlasIdeTaskProjects.Say(TAtlasBuildStrings.Text(TAtlasBuildTextId.TasksOutputOnlyFindings), False);
  end
  else
  begin
    TAtlasIdeTaskProjects.Say(TAtlasBuildStrings.Text(TAtlasBuildTextId.TasksOutputAll), False);
  end;
end;

procedure TAtlasIdeTasks.Choose;
var
  mTasks: TAtlasTaskDefinitions;
  mKey: string;
begin
  mTasks := Definitions;
  if Length(mTasks) = 0 then
  begin
    TAtlasIdeTaskProjects.Say(TAtlasBuildStrings.Text(TAtlasBuildTextId.TasksNone), True);
    Exit;
  end;
  mKey := TAtlasIdeTaskProjects.KeyOf(FLoaded.Project);
  TAtlasIdeTaskPickers.ChooseTask(mTasks,
    function(AName: string): string
    begin
      Result := LastText(mKey, AName);
    end, RunByNameOf(Self), AliveCheck(FAlive));
end;

/// <summary>Befunde der Aufgabe AName im Projekt AKey ein- bzw. ausblenden und merken.</summary>
function FindingsToggle(AOwner: TAtlasIdeTasks; const AKey: string): TProc<string>;
begin
  Result :=
    procedure(AName: string)
    var
      mHidden: Boolean;
      mStore: TAtlasProblemStore;
    begin
      mHidden := not AOwner.FHistory.Data.IsHidden(AKey, AName);
      AOwner.FHistory.Data.SetHidden(AKey, AName, mHidden);
      SaveHistory(AOwner.FHistory);
      mStore := TAtlasProblemsController.Current;
      if mStore <> nil then
      begin
        mStore.SetTaskHidden(AName, mHidden);
      end;
    end;
end;

procedure TAtlasIdeTasks.ChooseFindings;
var
  mTasks: TAtlasTaskDefinitions;
  mKey: string;
  mHistory: TAtlasTaskHistory;
begin
  mTasks := Definitions;
  if Length(mTasks) = 0 then
  begin
    TAtlasIdeTaskProjects.Say(TAtlasBuildStrings.Text(TAtlasBuildTextId.TasksNone), True);
    Exit;
  end;
  mKey := TAtlasIdeTaskProjects.KeyOf(FLoaded.Project);
  mHistory := FHistory.Data;
  TAtlasIdeTaskPickers.ChooseFindings(mTasks,
    function(AName: string): Boolean
    begin
      Result := mHistory.IsHidden(mKey, AName);
    end, FindingsToggle(Self, mKey), AliveCheck(FAlive));
end;

procedure TAtlasIdeTasks.RunFromMenu(const AName: string);
var
  mReason: string;
begin
  if not RunByName(AName, mReason) and (mReason <> '') then
  begin
    TAtlasIdeTaskProjects.Say(mReason, True);
  end;
end;

function TAtlasIdeTasks.MenuItems: TArray<TAtlasTaskMenuItem>;
var
  mTasks: TAtlasTaskDefinitions;
  mTask: TAtlasTaskDefinition;
  mItem: TAtlasTaskMenuItem;
  mKey: string;
begin
  Result := nil;
  mTasks := Definitions;
  mKey := TAtlasIdeTaskProjects.KeyOf(FLoaded.Project);
  for mTask in mTasks do
  begin
    // Ohne ShortCut am Eintrag: Die Taste belegt TAtlasIdeKeyBinding (Konfliktmeldung), hier steht sie nur.
    mItem.Name := mTask.Name;
    mItem.Caption := TAtlasTaskTexts.GroupName(mTask.Group) + ': ' + mTask.Name + ' (' + LastText(mKey, mTask.Name) +
      ')';
    if mTask.KeyText <> '' then
    begin
      mItem.Caption := mItem.Caption + #9 + mTask.KeyText;
    end;
    Result := Result + [mItem];
  end;
end;

end.
