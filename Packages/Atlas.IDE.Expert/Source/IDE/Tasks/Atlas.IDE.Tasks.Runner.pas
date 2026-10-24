unit Atlas.IDE.Tasks.Runner;

// Projektaufgaben (#900) in der IDE:
// - Definitionen aus dem Abschnitt „tasks“ von atlas.json neben der .dproj
//   und der globalen %APPDATA%\Atlas\settings.json (Projekt vor global). Ein
//   Zeitgeber merkt Projektwechsel und geänderte Dateien und lädt neu; dann
//   werden Tasten und Statuszeilen neu angelegt. Verworfene Einträge stehen
//   einmal in der Meldungsansicht (Gruppe Atlas).
// - Start über Befehlspalette (Choose), Menü Atlas › Aufgaben (FillMenu),
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

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.Menus,
  Vcl.ExtCtrls,
  Atlas.Core.Build.Events,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Registry,
  Atlas.Core.Tasks.Definitions,
  Atlas.Core.Tasks.Matchers,
  Atlas.Core.Tasks.Runs,
  Atlas.Core.Tasks.PreBuild,
  Atlas.IDE.Foundation.Keys,
  Atlas.IDE.Tasks.Output;

type
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

    /// <summary>Abbruch eines Laufs; der Thread fragt Cancelled im Takt.</summary>
    TFlag = class(TInterfacedObject)
    public
      Cancelled: Boolean;
    end;

    TWorker = class(TThread)
    private
      FOwner: TAtlasIdeTasks;
      FAlive: TAlive;
      FKeep: IInterface;
      FFlag: TFlag;
      FFlagRef: IInterface;
      FId: Integer;
      FTask: TAtlasTaskDefinition;
      FProcess: TAtlasTaskProcessRun;
      FProjectFiles: TArray<string>;
      FSearchPath: TArray<string>;
      FPendingLines: TArray<string>;
      FPendingFindings: TAtlasTaskFindings;
      procedure Deliver;
      procedure Finish(const ARun: TAtlasTaskRun);
    protected
      procedure Execute; override;
    public
      constructor Create(AOwner: TAtlasIdeTasks; AId: Integer; const ATask: TAtlasTaskDefinition;
        const AProjectFiles, ASearchPath: TArray<string>);
      destructor Destroy; override;
      procedure Cancel;
    end;

    TJob = class
      Id: Integer;
      Name: string;
      Project: string;
      Worker: TWorker;
      /// <summary>Lauf gehört zu einer Reihe (Batch); 0 = einzeln.</summary>
      Batch: Integer;
      Mode: TAtlasTaskBeforeBuild;
      Done: Boolean;
      destructor Destroy; override;
    end;

    /// <summary>Mehrere Läufe: „Alle Prüfungen“ bzw. vor dem Build; nacheinander oder gleichzeitig.</summary>
    TBatch = class
      Id: Integer;
      Project: string;
      PreBuild: Boolean;
      Waiting: TAtlasTaskDefinitions;
      WaitingModes: TArray<TAtlasTaskBeforeBuild>;
      Running: Integer;
      Entries: TArray<TAtlasTaskGateEntry>;
    end;
  private
    FProcess: TAtlasTaskProcessRun;
    FAlive: TAlive;
    FAliveRef: IInterface;
    FOutput: TAtlasIdeTaskOutput;
    FHistory: TAtlasTaskHistory;
    FHistoryKept: Boolean;
    FPreBuild: TAtlasTaskPreBuild;
    FJobs: TObjectList<TJob>;
    FBatches: TObjectList<TBatch>;
    FKeys: TObjectList<TAtlasIdeKeyBinding>;
    FStatus: TArray<TAtlasStatusLine>;
    FStatusRefs: TArray<IAtlasStatusItem>;
    FTimer: TTimer;
    FNextId: Integer;
    FProject: string;
    FSignature: string;
    FTasks: TAtlasTaskDefinitions;
    FIssuesShown: string;
    FLastName: string;
    FLastProject: string;
    FOnRebuild: TAtlasTasksRebuildFunc;
    FOnFinished: TAtlasTasksFinishedProc;
    /// <summary>Namen der Einträge im Untermenü Aufgaben, je Tag.</summary>
    FMenuNames: TArray<string>;
    /// <summary>TaskNamesOf: Projekt (klein) → Stand der Dateien und Namen, damit die Willkommensseite nicht bei
    /// jedem Neuaufbau die atlas.json liest.</summary>
    FNameSignatures: TDictionary<string, string>;
    FNames: TDictionary<string, TArray<string>>;
    class function HistoryFile: string; static;
    class function ActiveProject: string; static;
    class function SignatureOf(const AProject: string): string; static;
    class function ProjectFilesOf(const AProject: string; out ASearchPath: TArray<string>): TArray<string>; static;
    class function VariablesOf(const AProject: string): TAtlasTaskVariables; static;
    class procedure SaveModified; static;
    class procedure Say(const AText: string; AShow: Boolean); static;
    procedure LoadHistory;
    procedure SaveHistory;
    procedure Tick(Sender: TObject);
    procedure Refresh(AForce: Boolean);
    procedure Rebuild;
    procedure ClearKeysAndStatus;
    function KeyAction(const AName: string): TProc;
    function StatusAction(const AName: string): TProc;
    procedure UpdateStatus(const AName: string);
    function StatusId(const AName: string): string;
    function IsRunning(const AProject, AName: string): Boolean;
    function Start(const AProject: string; const ATask: TAtlasTaskDefinition; ABatch: Integer;
      AMode: TAtlasTaskBeforeBuild; AShow: Boolean): Boolean;
    procedure StartBatch(const AProject: string; const ATasks: TAtlasTaskDefinitions;
      const AModes: TArray<TAtlasTaskBeforeBuild>; APreBuild: Boolean);
    procedure StartNextOf(ABatch: TBatch);
    function FindBatch(AId: Integer): TBatch;
    procedure BatchDone(ABatch: TBatch);
    procedure WorkerLines(AId: Integer; const ALines: TArray<string>; const AFindings: TAtlasTaskFindings);
    procedure WorkerFinished(AId: Integer; const ARun: TAtlasTaskRun);
    procedure ApplyProblems(const ARun: TAtlasTaskRun; const AProject: string);
    function LastText(const AProject, AName: string): string;
    procedure MenuItemClick(Sender: TObject);
  public
    /// <summary>AProcess startet den Prozess einer Aufgabe (Kompositionswurzel: TAtlasTaskProcess.Run).</summary>
    constructor Create(const AProcess: TAtlasTaskProcessRun);
    destructor Destroy; override;
    /// <summary>Aufgaben des aktiven Projekts (lädt neu, wenn sich etwas geändert hat).</summary>
    function Definitions: TAtlasTaskDefinitions;
    /// <summary>Aufgaben des Projekts AProject (.dproj; '' = nur global).</summary>
    class function DefinitionsOf(const AProject: string; out AIssues: TArray<string>): TAtlasTaskDefinitions;
      static;
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
    /// <summary>Untermenü Atlas › Aufgaben neu füllen.</summary>
    procedure FillMenu(AMenu: TMenuItem);
    /// <summary>Vor einem Compile (Compile-Ereignisse): True bricht ab, AReason für das Meldungsfenster.</summary>
    function BeforeCompile(const AProject: TAtlasCompileProject; out AReason: string): Boolean;
    /// <summary>Einstellungen übernehmen (tasks.onlyFindings, Tasten).</summary>
    procedure ApplySettings;
    /// <summary>Läuft eine Aufgabe?</summary>
    function Busy: Boolean;
    /// <summary>Teilnehmer der Compile-Ereignisse, der an AGet() weitergibt (nil = nichts).</summary>
    class function CreateParticipant(const AGet: TFunc<TAtlasIdeTasks>): TAtlasCompileParticipant; static;
    property OnRebuild: TAtlasTasksRebuildFunc read FOnRebuild write FOnRebuild;
    property OnFinished: TAtlasTasksFinishedProc read FOnFinished write FOnFinished;
  end;

implementation

uses
  System.IOUtils,
  System.Types,
  Vcl.Forms,
  ToolsAPI,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Problems.Store,
  Atlas.Core.Projects.Contract,
  Atlas.Core.Settings.Layers,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Tasks.Reports,
  Atlas.Text.Lines,
  Atlas.UI.Strings,
  Atlas.UI.Commands.Palette,
  Atlas.UI.Tasks.Texts,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Problems.Controller,
  Atlas.IDE.Projects.Context,
  Atlas.IDE.Settings.Project;

const
  MessageGroup = 'Atlas';
  RefreshMs = 2000;
  FlushMs = 100;
  StatusOrder = 40;
  NoProject = '(global)';

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
  Tasks: TAtlasIdeTasks;
begin
  AReason := '';
  Tasks := FGet();
  Result := (Tasks <> nil) and Tasks.BeforeCompile(AProject, AReason);
end;

function ProjectByFile(const AFileName: string): IOTAProject;
var
  Services: IOTAModuleServices;
begin
  Result := nil;
  if (AFileName <> '') and Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Supports(Services.FindModule(AFileName), IOTAProject, Result);
end;

function ReadLines(const AFileName: string; out ALines: TArray<string>): Boolean;
var
  Buffer: IOTAEditBuffer;
  Text: string;
begin
  ALines := nil;
  Buffer := TAtlasIdeFiles.BufferOf(AFileName);
  if Buffer <> nil then
    Text := TAtlasEditorBuffer.Text(Buffer)
  else
  begin
    if not FileExists(AFileName) then
      Exit(False);
    try
      Text := TAtlasTextFile.Load(AFileName).Text;
    except
      on Exception do
        Exit(False);
    end;
  end;
  ALines := TTextLines.SplitLines(Text);
  Result := True;
end;

function ExistsProc: TAtlasTaskFileExists;
begin
  Result :=
    function(const AFileName: string): Boolean
    begin
      Result := FileExists(AFileName);
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
  FKeep := AOwner.FAliveRef;
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
  FKeep := nil;
  FProcess := nil;
  inherited Destroy;
end;

procedure TAtlasIdeTasks.TWorker.Cancel;
begin
  FFlag.Cancelled := True;
  Terminate;
end;

procedure TAtlasIdeTasks.TWorker.Deliver;
var
  Lines: TArray<string>;
  Findings: TAtlasTaskFindings;
  Owner: TAtlasIdeTasks;
  Alive: TAlive;
  Keep: IInterface;
  Id: Integer;
begin
  if (Length(FPendingLines) = 0) and (Length(FPendingFindings) = 0) then
    Exit;
  Lines := FPendingLines;
  Findings := FPendingFindings;
  FPendingLines := nil;
  FPendingFindings := nil;
  Owner := FOwner;
  Alive := FAlive;
  Keep := FKeep;
  Id := FId;
  TAtlasMainThread.Queue(TAtlasFeature.Tasks,
    procedure
    begin
      if (Keep = nil) or not Alive.Alive then
        Exit;
      Owner.WorkerLines(Id, Lines, Findings);
    end);
end;

procedure TAtlasIdeTasks.TWorker.Finish(const ARun: TAtlasTaskRun);
var
  Run: TAtlasTaskRun;
  Owner: TAtlasIdeTasks;
  Alive: TAlive;
  Keep: IInterface;
  Id: Integer;
begin
  Run := ARun;
  Owner := FOwner;
  Alive := FAlive;
  Keep := FKeep;
  Id := FId;
  TAtlasMainThread.Queue(TAtlasFeature.Tasks,
    procedure
    begin
      if (Keep = nil) or not Alive.Alive then
        Exit;
      Owner.WorkerFinished(Id, Run);
    end);
end;

procedure TAtlasIdeTasks.TWorker.Execute;
var
  Matcher: TAtlasTaskLineMatcher;
  Run: TAtlasTaskRun;
  Outcome: TAtlasTaskProcessResult;
  Started, LastFlush: UInt64;
  Flag: TFlag;
  Exists: TAtlasTaskFileExists;
  LineCount: Integer;
begin
  Run := Default(TAtlasTaskRun);
  Run.Name := FTask.Name;
  Run.CommandLine := FTask.CommandLine;
  Run.Cwd := FTask.Cwd;
  Started := TThread.GetTickCount64;
  LastFlush := Started;
  Flag := FFlag;
  Exists := ExistsProc;
  LineCount := 0;
  try
    Matcher := TAtlasTaskLineMatcher.Create(FTask.Matcher);
    try
      Outcome := FProcess(FTask, 0,
        function: Boolean
        begin
          Result := Flag.Cancelled or TAtlasShutdown.Signalled;
        end,
        procedure(const ALine: string)
        var
          Finding: TAtlasTaskFinding;
        begin
          if Matcher.Match(ALine, Finding) then
          begin
            Finding.OutputLine := LineCount;
            if Finding.FileName <> '' then
              Finding.FileName := TAtlasTaskPaths.Resolve(Finding.FileName, FTask.Cwd, FProjectFiles, FSearchPath,
                Exists);
            Run.Findings := Run.Findings + [Finding];
            FPendingFindings := FPendingFindings + [Finding];
          end;
          // Die Anzeige kappt selbst; gemerkt werden höchstens so viele Zeilen wie dort.
          if LineCount < TAtlasIdeTaskOutput.MaxLines then
            Run.Lines := Run.Lines + [ALine];
          Inc(LineCount);
          FPendingLines := FPendingLines + [ALine];
          if TThread.GetTickCount64 - LastFlush >= FlushMs then
          begin
            Deliver;
            LastFlush := TThread.GetTickCount64;
          end;
        end);
      // Ungültiges eigenes Muster: Die Ausgabe läuft ohne Befunde, der Grund steht darunter.
      if Matcher.Error <> '' then
        FPendingLines := FPendingLines + [Matcher.Error];
    finally
      Matcher.Free;
    end;
    Deliver;
    Run.Outcome := Outcome.Outcome;
    Run.ExitCode := Outcome.ExitCode;
    Run.Error := Outcome.Error;
  except
    on E: Exception do
    begin
      Run.Outcome := TAtlasTaskOutcome.StartFailed;
      Run.ExitCode := -1;
      Run.Error := E.Message;
    end;
  end;
  Run.DurationMs := Int64(TThread.GetTickCount64 - Started);
  Run.FinishedAt := Now;
  Finish(Run);
end;

{ TAtlasIdeTasks.TJob }

destructor TAtlasIdeTasks.TJob.Destroy;
begin
  if Worker <> nil then
  begin
    Worker.Cancel;
    Worker.WaitFor;
    FreeAndNil(Worker);
  end;
  inherited Destroy;
end;

{ TAtlasIdeTasks }

constructor TAtlasIdeTasks.Create(const AProcess: TAtlasTaskProcessRun);
begin
  inherited Create;
  FProcess := AProcess;
  FAlive := TAlive.Create;
  FAlive.Alive := True;
  FAliveRef := FAlive;
  FOutput := TAtlasIdeTaskOutput.Create;
  FOutput.OnlyFindings := TAtlasIdeSettings.Current.TasksOnlyFindings;
  FHistory := TAtlasTaskHistory.Create;
  FPreBuild := TAtlasTaskPreBuild.Create;
  FJobs := TObjectList<TJob>.Create(True);
  FBatches := TObjectList<TBatch>.Create(True);
  FKeys := TObjectList<TAtlasIdeKeyBinding>.Create(True);
  FNameSignatures := TDictionary<string, string>.Create;
  FNames := TDictionary<string, TArray<string>>.Create;
  LoadHistory;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := RefreshMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
  Refresh(True);
end;

destructor TAtlasIdeTasks.Destroy;
begin
  FAlive.Alive := False;
  FreeAndNil(FTimer);
  // Laufende Aufgaben beenden (Job-Objekt) und auf ihre Threads warten.
  FreeAndNil(FJobs);
  FreeAndNil(FBatches);
  FPreBuild.Abandon;
  ClearKeysAndStatus;
  FreeAndNil(FKeys);
  FreeAndNil(FNames);
  FreeAndNil(FNameSignatures);
  FreeAndNil(FPreBuild);
  FreeAndNil(FHistory);
  if FOutput <> nil then
    FOutput.Clear;
  FreeAndNil(FOutput);
  FAliveRef := nil;
  inherited Destroy;
end;

class function TAtlasIdeTasks.CreateParticipant(const AGet: TFunc<TAtlasIdeTasks>): TAtlasCompileParticipant;
begin
  Result := TParticipant.Create(AGet);
end;

class function TAtlasIdeTasks.HistoryFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('APPDATA'), 'Atlas'), TAtlasTaskHistory.FileName);
end;

class function TAtlasIdeTasks.ActiveProject: string;
begin
  Result := TAtlasProjectSettings.ActiveProject;
end;

class procedure TAtlasIdeTasks.Say(const AText: string; AShow: Boolean);
var
  Messages: IOTAMessageServices;
  Group: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Exit;
  Group := Messages.GetGroup(MessageGroup);
  if Group = nil then
    Group := Messages.AddMessageGroup(MessageGroup);
  Messages.AddTitleMessage(AText, Group);
  if AShow then
    Messages.ShowMessageView(Group);
end;

procedure TAtlasIdeTasks.LoadHistory;
var
  History: TAtlasTaskHistory;
begin
  History := FHistory;
  FHistoryKept := not TAtlasDataFile.Writable(TAtlasDataFile.Load(HistoryFile, 'Verlauf der Projektaufgaben',
    function(const AText: string): Boolean
    begin
      Result := History.FromJson(AText);
    end));
end;

procedure TAtlasIdeTasks.SaveHistory;
begin
  // Gesperrt gelesene Datei nicht mit dem Stand dieser Sitzung überschreiben (Bericht N3).
  if FHistoryKept then
    Exit;
  try
    TAtlasDataFile.Write(HistoryFile, FHistory.ToJson);
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten('Verlauf der Projektaufgaben', E);
  end;
end;

class function TAtlasIdeTasks.SignatureOf(const AProject: string): string;

  function Stamp(const AFileName: string): string;
  var
    Age: TDateTime;
  begin
    if (AFileName <> '') and FileAge(AFileName, Age) then
      Result := FloatToStr(Age)
    else
      Result := '-';
  end;

var
  ProjectFile: string;
begin
  ProjectFile := '';
  if AProject <> '' then
    ProjectFile := TPath.Combine(ExtractFileDir(AProject), TAtlasSettingsFiles.ProjectName);
  Result := AnsiLowerCase(AProject) + '|' + Stamp(ProjectFile) + '|' + Stamp(TAtlasProjectSettings.GlobalFile);
end;

class function TAtlasIdeTasks.DefinitionsOf(const AProject: string; out AIssues: TArray<string>):
  TAtlasTaskDefinitions;
var
  HasBom: Boolean;
  Own, Global: TAtlasTaskDefinitions;
begin
  AIssues := nil;
  Own := nil;
  if AProject <> '' then
    Own := TAtlasTasks.Parse(TAtlasProjectSettings.ReadText(TPath.Combine(ExtractFileDir(AProject),
      TAtlasSettingsFiles.ProjectName), HasBom), False, AIssues);
  Global := TAtlasTasks.Parse(TAtlasProjectSettings.ReadText(TAtlasProjectSettings.GlobalFile, HasBom), True,
    AIssues);
  Result := TAtlasTasks.Merge(Own, Global);
end;

function TAtlasIdeTasks.TaskNamesOf(const AProject: string): TArray<string>;
var
  Key, Signature, Known: string;
  Issues: TArray<string>;
  Task: TAtlasTaskDefinition;
begin
  Key := AnsiLowerCase(AProject);
  Signature := SignatureOf(AProject);
  if FNameSignatures.TryGetValue(Key, Known) and (Known = Signature) and FNames.TryGetValue(Key, Result) then
    Exit;
  Result := nil;
  for Task in DefinitionsOf(AProject, Issues) do
    Result := Result + [Task.Name];
  FNameSignatures.AddOrSetValue(Key, Signature);
  FNames.AddOrSetValue(Key, Result);
end;

function TAtlasIdeTasks.Definitions: TAtlasTaskDefinitions;
begin
  Refresh(False);
  Result := FTasks;
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
  Project, Signature, Shown: string;
  Issues: TArray<string>;
  Issue: string;
begin
  Project := ActiveProject;
  Signature := SignatureOf(Project);
  if not AForce and (Signature = FSignature) then
    Exit;
  FSignature := Signature;
  FProject := Project;
  FTasks := DefinitionsOf(Project, Issues);
  // Verworfene Einträge einmal je Stand melden.
  Shown := string.Join(#10, Issues);
  if (Shown <> '') and (Shown <> FIssuesShown) then
    for Issue in Issues do
      Say(TAtlasStrings.Fmt(TAtlasTextId.TasksIssue, [ExtractFileName(Project), Issue]), False);
  FIssuesShown := Shown;
  Rebuild;
end;

procedure TAtlasIdeTasks.ClearKeysAndStatus;
var
  Line: TAtlasStatusLine;
begin
  if FKeys <> nil then
    FKeys.Clear;
  for Line in FStatus do
  begin
    Line.Detach;
    TAtlasStatusRegistry.Default.Remove(Line.Id);
  end;
  FStatus := nil;
  FStatusRefs := nil;
end;

function TAtlasIdeTasks.KeyAction(const AName: string): TProc;
var
  Owner: TAtlasIdeTasks;
  Name: string;
begin
  Owner := Self;
  Name := AName;
  Result :=
    procedure
    var
      Reason: string;
    begin
      if not Owner.RunByName(Name, Reason) and (Reason <> '') then
        Say(Reason, True);
    end;
end;

function TAtlasIdeTasks.StatusAction(const AName: string): TProc;
var
  Alive: TAlive;
  Keep: IInterface;
  Owner: TAtlasIdeTasks;
  Name: string;
begin
  Alive := FAlive;
  Keep := FAliveRef;
  Owner := Self;
  Name := AName;
  Result :=
    procedure
    var
      Reason: string;
    begin
      if (Keep = nil) or not Alive.Alive then
        Exit;
      TAtlasGuard.Run(TAtlasFeature.Tasks,
        procedure
        begin
          if not Owner.RunByName(Name, Reason) and (Reason <> '') then
            Say(Reason, True);
        end);
    end;
end;

function TAtlasIdeTasks.StatusId(const AName: string): string;
begin
  Result := 'atlas.task.' + AnsiLowerCase(AName);
end;

procedure TAtlasIdeTasks.Rebuild;
var
  Index: Integer;
  Task: TAtlasTaskDefinition;
  Binding: TAtlasIdeKeyBinding;
  Line: TAtlasStatusLine;
begin
  ClearKeysAndStatus;
  for Index := 0 to High(FTasks) do
  begin
    Task := FTasks[Index];
    if Task.Key <> 0 then
    begin
      Binding := TAtlasIdeKeyBinding.Create('Atlas.Task' + IntToStr(Index),
        TAtlasStrings.Fmt(TAtlasTextId.TasksKeyWhat, [Task.Name]), TAtlasFeature.Tasks, KeyAction(Task.Name));
      FKeys.Add(Binding);
      Binding.Rebind(Task.Key, False, TAtlasStrings.Fmt(TAtlasTextId.TasksKeyWhat, [Task.Name]));
    end;
    Line := TAtlasStatusLine.Create(TAtlasStatusRegistry.Default, StatusId(Task.Name), StatusOrder + Index,
      StatusAction(Task.Name));
    FStatus := FStatus + [Line];
    FStatusRefs := FStatusRefs + [Line as IAtlasStatusItem];
    TAtlasStatusRegistry.Default.Add(Line);
    UpdateStatus(Task.Name);
  end;
end;

procedure TAtlasIdeTasks.ApplySettings;
begin
  FOutput.OnlyFindings := TAtlasIdeSettings.Current.TasksOnlyFindings;
  Refresh(True);
end;

function TAtlasIdeTasks.LastText(const AProject, AName: string): string;
var
  Last: TAtlasTaskLastRun;
  Has: Boolean;
begin
  if IsRunning(AProject, AName) then
    Exit(TAtlasStrings.Text(TAtlasTextId.TasksRunningShort));
  Has := FHistory.LastRun(AProject, AName, Last);
  Result := TAtlasTaskTexts.LastResult(Last, Has);
end;

procedure TAtlasIdeTasks.UpdateStatus(const AName: string);
var
  Line: TAtlasStatusLine;
  Last: TAtlasTaskLastRun;
  State: TAtlasStatusState;
  Key: string;
begin
  Key := FProject;
  if Key = '' then
    Key := NoProject;
  for Line in FStatus do
    if SameText(Line.Id, StatusId(AName)) then
    begin
      State := TAtlasStatusState.Neutral;
      if not IsRunning(Key, AName) and FHistory.LastRun(Key, AName, Last) then
        if Last.Passed then
          State := TAtlasStatusState.Green
        else
          State := TAtlasStatusState.Red;
      Line.Update(AName + ': ' + LastText(Key, AName), State, '', AName, LastText(Key, AName));
    end;
end;

function TAtlasIdeTasks.IsRunning(const AProject, AName: string): Boolean;
var
  Job: TJob;
begin
  for Job in FJobs do
    if not Job.Done and SameText(Job.Name, AName) and SameText(Job.Project, AProject) then
      Exit(True);
  Result := False;
end;

function TAtlasIdeTasks.Busy: Boolean;
var
  Job: TJob;
begin
  for Job in FJobs do
    if not Job.Done then
      Exit(True);
  Result := False;
end;

class function TAtlasIdeTasks.ProjectFilesOf(const AProject: string; out ASearchPath: TArray<string>):
  TArray<string>;
var
  Project: IOTAProject;
  Index: Integer;
  Context: TAtlasProjectContext;
  Folder, Entry: string;
begin
  Result := nil;
  ASearchPath := nil;
  Project := ProjectByFile(AProject);
  if Project = nil then
    Exit;
  for Index := 0 to Project.GetModuleCount - 1 do
    if Project.GetModule(Index).FileName <> '' then
      Result := Result + [Project.GetModule(Index).FileName];
  Context := TAtlasIdeProjectContext.Read(Project);
  Folder := ExtractFileDir(AProject);
  for Entry in Context.SearchPaths do
    // Makros wie $(BDS) setzt der Suchpfad nicht ein; solche Einträge bleiben weg.
    if (Entry <> '') and (Pos('$(', Entry) = 0) then
      if TPath.IsPathRooted(Entry) then
        ASearchPath := ASearchPath + [Entry]
      else
        ASearchPath := ASearchPath + [TPath.Combine(Folder, Entry)];
end;

class function TAtlasIdeTasks.VariablesOf(const AProject: string): TAtlasTaskVariables;
var
  Services: IOTAModuleServices;
  Editors: IOTAEditorServices;
  Project: IOTAProject;
begin
  Result := Default(TAtlasTaskVariables);
  Result.ProjectDir := ExtractFileDir(AProject);
  Result.GroupDir := Result.ProjectDir;
  if Supports(BorlandIDEServices, IOTAModuleServices, Services) and (Services.MainProjectGroup <> nil) and
    (Services.MainProjectGroup.FileName <> '') then
    Result.GroupDir := ExtractFileDir(Services.MainProjectGroup.FileName);
  if Supports(BorlandIDEServices, IOTAEditorServices, Editors) and (Editors.TopBuffer <> nil) then
    Result.FileName := Editors.TopBuffer.FileName;
  Project := ProjectByFile(AProject);
  if Project <> nil then
  begin
    Result.Config := Project.CurrentConfiguration;
    Result.Platform := Project.CurrentPlatform;
  end;
  Result.Bds := GetEnvironmentVariable('BDS');
end;

class procedure TAtlasIdeTasks.SaveModified;
var
  Services: IOTAModuleServices;
  Module: IOTAModule;
  Index, Editor: Integer;
begin
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Exit;
  for Index := 0 to Services.ModuleCount - 1 do
  begin
    Module := Services.Modules[Index];
    // Projekte und Gruppen nicht: Ihr Speichern fragt nach Namen bzw. ändert die .dproj.
    if (Module = nil) or Supports(Module, IOTAProject) or Supports(Module, IOTAProjectGroup) then
      Continue;
    for Editor := 0 to Module.ModuleFileCount - 1 do
      if (Module.ModuleFileEditors[Editor] <> nil) and Module.ModuleFileEditors[Editor].Modified then
      begin
        Module.Save(False, True);
        Break;
      end;
  end;
end;

function TAtlasIdeTasks.Start(const AProject: string; const ATask: TAtlasTaskDefinition; ABatch: Integer;
  AMode: TAtlasTaskBeforeBuild; AShow: Boolean): Boolean;
var
  Job: TJob;
  Task: TAtlasTaskDefinition;
  ProjectFiles, SearchPath: TArray<string>;
  Key: string;
begin
  Key := AProject;
  if Key = '' then
    Key := NoProject;
  if IsRunning(Key, ATask.Name) then
    Exit(False);
  // Fertige Läufe abräumen (ihr Thread ist zu Ende).
  for Job in FJobs.ToArray do
    if Job.Done then
      FJobs.Remove(Job);
  Task := TAtlasTasks.Expand(ATask, VariablesOf(AProject));
  ProjectFiles := ProjectFilesOf(AProject, SearchPath);
  Inc(FNextId);
  Job := TJob.Create;
  Job.Id := FNextId;
  Job.Name := ATask.Name;
  Job.Project := Key;
  Job.Batch := ABatch;
  Job.Mode := AMode;
  FJobs.Add(Job);
  FOutput.Started(Job.Id, Task.Name, Task.CommandLine, Task.TimeoutSec, AShow);
  Job.Worker := TWorker.Create(Self, Job.Id, Task, ProjectFiles, SearchPath);
  Job.Worker.Start;
  if ABatch = 0 then
  begin
    FLastName := ATask.Name;
    FLastProject := AProject;
  end;
  UpdateStatus(ATask.Name);
  Result := True;
end;

function TAtlasIdeTasks.RunInProject(const AProject, AName: string; out AReason: string): Boolean;
var
  Tasks: TAtlasTaskDefinitions;
  Issues: TArray<string>;
  Index: Integer;
begin
  AReason := '';
  Result := False;
  if not TAtlasIdeSettings.Current.TasksEnabled then
  begin
    AReason := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickReasonTasksOff);
    Exit;
  end;
  if SameText(AProject, FProject) then
    Tasks := Definitions
  else
    Tasks := DefinitionsOf(AProject, Issues);
  Index := TAtlasTasks.IndexOf(Tasks, AName);
  if Index < 0 then
  begin
    AReason := TAtlasStrings.Text(TAtlasTextId.TasksNone);
    Exit;
  end;
  if TAtlasIdeSettings.Current.TasksSaveBeforeRun then
    SaveModified;
  Result := Start(AProject, Tasks[Index], 0, TAtlasTaskBeforeBuild.Off, True);
  if not Result then
    AReason := TAtlasStrings.Fmt(TAtlasTextId.TasksAlreadyRunning, [AName]);
end;

function TAtlasIdeTasks.RunByName(const AName: string; out AReason: string): Boolean;
begin
  Refresh(False);
  Result := RunInProject(FProject, AName, AReason);
end;

procedure TAtlasIdeTasks.RepeatLast;
var
  Reason: string;
begin
  if FLastName = '' then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.TasksNoLast), True);
    Exit;
  end;
  if not RunInProject(FLastProject, FLastName, Reason) and (Reason <> '') then
    Say(Reason, True);
end;

procedure TAtlasIdeTasks.RunChecks;
var
  Checks: TAtlasTaskDefinitions;
  Modes: TArray<TAtlasTaskBeforeBuild>;
  Index: Integer;
begin
  if not TAtlasIdeSettings.Current.TasksEnabled then
    Exit;
  Checks := TAtlasTasks.OfGroup(Definitions, TAtlasTaskGroup.Check);
  if Length(Checks) = 0 then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.TasksNoChecks), True);
    Exit;
  end;
  if TAtlasIdeSettings.Current.TasksSaveBeforeRun then
    SaveModified;
  SetLength(Modes, Length(Checks));
  for Index := 0 to High(Modes) do
    Modes[Index] := TAtlasTaskBeforeBuild.Off;
  StartBatch(FProject, Checks, Modes, False);
end;

procedure TAtlasIdeTasks.StartBatch(const AProject: string; const ATasks: TAtlasTaskDefinitions;
  const AModes: TArray<TAtlasTaskBeforeBuild>; APreBuild: Boolean);
var
  Batch: TBatch;
begin
  Inc(FNextId);
  Batch := TBatch.Create;
  Batch.Id := FNextId;
  Batch.Project := AProject;
  Batch.PreBuild := APreBuild;
  Batch.Waiting := ATasks;
  Batch.WaitingModes := AModes;
  FBatches.Add(Batch);
  StartNextOf(Batch);
end;

procedure TAtlasIdeTasks.StartNextOf(ABatch: TBatch);
var
  Task: TAtlasTaskDefinition;
  Mode: TAtlasTaskBeforeBuild;
  Parallel: Boolean;
begin
  Parallel := TAtlasIdeSettings.Current.TasksRunChecksParallel;
  while Length(ABatch.Waiting) > 0 do
  begin
    Task := ABatch.Waiting[0];
    Mode := ABatch.WaitingModes[0];
    Delete(ABatch.Waiting, 0, 1);
    Delete(ABatch.WaitingModes, 0, 1);
    if Start(ABatch.Project, Task, ABatch.Id, Mode, not ABatch.PreBuild) then
    begin
      Inc(ABatch.Running);
      if not Parallel then
        Exit;
    end;
  end;
  if ABatch.Running = 0 then
    BatchDone(ABatch);
end;

function TAtlasIdeTasks.FindBatch(AId: Integer): TBatch;
var
  Batch: TBatch;
begin
  for Batch in FBatches do
    if Batch.Id = AId then
      Exit(Batch);
  Result := nil;
end;

procedure TAtlasIdeTasks.BatchDone(ABatch: TBatch);
var
  Decision: TAtlasTaskGateDecision;
  Run: TAtlasTaskRun;
  Project: TAtlasCompileProject;
  Reason: string;
  Alive: TAlive;
  Keep: IInterface;
  Rebuild: TAtlasTasksRebuildFunc;
begin
  if not ABatch.PreBuild then
  begin
    FBatches.Remove(ABatch);
    Exit;
  end;
  Decision := TAtlasTaskGate.Decide(ABatch.Entries);
  FBatches.Remove(ABatch);
  for Run in Decision.Blocking do
    Say(TAtlasTaskTexts.Blocked(Run), True);
  for Run in Decision.Warnings do
    Say(TAtlasTaskTexts.Header(Run, 0), False);
  Project := FPreBuild.Project;
  if not FPreBuild.Finish(not Decision.Block, TThread.GetTickCount64) then
    Exit;
  // Bestanden: neu bauen, nicht aus dem laufenden Rückruf heraus.
  Rebuild := FOnRebuild;
  if not Assigned(Rebuild) then
  begin
    Say(TAtlasStrings.Fmt(TAtlasTextId.TasksGateRebuild, [ExtractFileName(Project.FileName)]), True);
    Exit;
  end;
  Alive := FAlive;
  Keep := FAliveRef;
  TAtlasMainThread.ForceQueue(TAtlasFeature.Tasks,
    procedure
    begin
      if (Keep = nil) or not Alive.Alive then
        Exit;
      Say(TAtlasStrings.Fmt(TAtlasTextId.TasksGatePassed, [ExtractFileName(Project.FileName)]), False);
      if not Rebuild(Project, Reason) then
        Say(TAtlasStrings.Fmt(TAtlasTextId.TasksGateRebuild, [Reason]), True);
    end);
end;

procedure TAtlasIdeTasks.WorkerLines(AId: Integer; const ALines: TArray<string>;
  const AFindings: TAtlasTaskFindings);
begin
  FOutput.Lines(AId, ALines, AFindings);
end;

procedure TAtlasIdeTasks.ApplyProblems(const ARun: TAtlasTaskRun; const AProject: string);
var
  Store: TAtlasProblemStore;
  Cache: TDictionary<string, TArray<string>>;
begin
  Store := TAtlasProblemsController.Current;
  if Store = nil then
    Exit;
  if not TAtlasIdeSettings.Current.TasksProblemsFromOutput then
  begin
    Store.ClearTask(ARun.Name);
    Exit;
  end;
  // Abgebrochen: die Befunde des vorigen Laufs bleiben stehen.
  if ARun.Outcome = TAtlasTaskOutcome.Cancelled then
    Exit;
  Cache := TDictionary<string, TArray<string>>.Create;
  try
    Store.SetTaskProblems(ARun.Name, TAtlasTaskReports.Problems(ARun.Name, ARun.Findings,
      function(const AFileName: string; ALine: Integer; out AText: string): Boolean
      var
        Lines: TArray<string>;
        Key: string;
      begin
        AText := '';
        Key := AnsiLowerCase(AFileName);
        if not Cache.TryGetValue(Key, Lines) then
        begin
          if not ReadLines(AFileName, Lines) then
            Lines := nil;
          Cache.Add(Key, Lines);
        end;
        Result := (ALine >= 0) and (ALine <= High(Lines));
        if Result then
          AText := Lines[ALine];
      end));
    Store.SetTaskHidden(ARun.Name, FHistory.IsHidden(AProject, ARun.Name));
  finally
    Cache.Free;
  end;
end;

procedure TAtlasIdeTasks.WorkerFinished(AId: Integer; const ARun: TAtlasTaskRun);
var
  Job, Item: TJob;
  Batch: TBatch;
  Entry: TAtlasTaskGateEntry;
  Project: string;
begin
  Job := nil;
  for Item in FJobs do
    if Item.Id = AId then
      Job := Item;
  if Job = nil then
    Exit;
  Job.Done := True;
  // Der Thread hat nach diesem Eintrag nichts mehr zu tun.
  if Job.Worker <> nil then
  begin
    Job.Worker.WaitFor;
    FreeAndNil(Job.Worker);
  end;
  FOutput.Finished(AId, ARun);
  FHistory.Remember(Job.Project, ARun);
  SaveHistory;
  ApplyProblems(ARun, Job.Project);
  if SameText(Job.Project, FProject) or ((FProject = '') and (Job.Project = NoProject)) then
    UpdateStatus(ARun.Name);
  Project := Job.Project;
  if Project = NoProject then
    Project := '';
  if Assigned(FOnFinished) then
    FOnFinished(Project, ARun);
  if Job.Batch = 0 then
    Exit;
  Batch := FindBatch(Job.Batch);
  if Batch = nil then
    Exit;
  Entry.Mode := Job.Mode;
  Entry.Run := ARun;
  Batch.Entries := Batch.Entries + [Entry];
  Dec(Batch.Running);
  StartNextOf(Batch);
end;

function TAtlasIdeTasks.BeforeCompile(const AProject: TAtlasCompileProject; out AReason: string): Boolean;
var
  Global, Mode: TAtlasTaskBeforeBuild;
  Tasks: TAtlasTaskDefinitions;
  Modes: TArray<TAtlasTaskBeforeBuild>;
  Task: TAtlasTaskDefinition;
  Issues: TArray<string>;
  HasBlock, HasWarn: Boolean;
  Names: string;
begin
  AReason := '';
  Result := False;
  if not TAtlasIdeSettings.Current.TasksEnabled or not TAtlasTaskPreBuild.Applies(AProject) then
    Exit;
  TAtlasTasks.TryBeforeBuild(TAtlasIdeSettings.Current.TasksBeforeBuild, Global);
  if SameText(AProject.FileName, FProject) then
    Tasks := TAtlasTasks.BeforeBuild(Definitions, Global)
  else
    Tasks := TAtlasTasks.BeforeBuild(DefinitionsOf(AProject.FileName, Issues), Global);
  HasBlock := False;
  HasWarn := False;
  Modes := nil;
  Names := '';
  for Task in Tasks do
  begin
    Mode := Task.BeforeBuildFor(Global);
    Modes := Modes + [Mode];
    if Mode = TAtlasTaskBeforeBuild.Block then
      HasBlock := True
    else
      HasWarn := True;
    if Names <> '' then
      Names := Names + ', ';
    Names := Names + Task.Name;
  end;
  case FPreBuild.Decide(AProject, HasBlock, HasWarn, TThread.GetTickCount64) of
    TAtlasTaskPreBuildAction.StartWarn:
      begin
        if TAtlasIdeSettings.Current.TasksSaveBeforeRun then
          SaveModified;
        StartBatch(AProject.FileName, Tasks, Modes, True);
      end;
    TAtlasTaskPreBuildAction.StartAndCancel:
      begin
        if TAtlasIdeSettings.Current.TasksSaveBeforeRun then
          SaveModified;
        AReason := TAtlasStrings.Fmt(TAtlasTextId.TasksGateRunning, [Names]);
        Result := True;
        StartBatch(AProject.FileName, Tasks, Modes, True);
      end;
    TAtlasTaskPreBuildAction.Busy:
      begin
        AReason := TAtlasStrings.Text(TAtlasTextId.TasksGateBusy);
        Result := True;
      end;
  end;
end;

procedure TAtlasIdeTasks.CancelAll;
var
  Job: TJob;
  Count: Integer;
begin
  Count := 0;
  for Job in FJobs do
    if not Job.Done and (Job.Worker <> nil) then
    begin
      Job.Worker.Cancel;
      Inc(Count);
    end;
  // Wartende Aufgaben einer Reihe starten nicht mehr; ein abgebrochener Lauf vor dem Build baut nicht neu.
  for Job in FJobs do
    if not Job.Done and (Job.Batch <> 0) and (FindBatch(Job.Batch) <> nil) then
    begin
      FindBatch(Job.Batch).Waiting := nil;
      FindBatch(Job.Batch).WaitingModes := nil;
    end;
  if FPreBuild.Running then
    FPreBuild.Abandon;
  if Count = 0 then
    Say(TAtlasStrings.Text(TAtlasTextId.TasksNothingRunning), True)
  else
    Say(TAtlasStrings.Fmt(TAtlasTextId.TasksCancelledAll, [Count]), False);
end;

procedure TAtlasIdeTasks.ToggleOutput;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Stored;
  Settings.TasksOnlyFindings := not FOutput.OnlyFindings;
  TAtlasIdeSettings.Update(Settings);
  FOutput.OnlyFindings := Settings.TasksOnlyFindings;
  if FOutput.OnlyFindings then
    Say(TAtlasStrings.Text(TAtlasTextId.TasksOutputOnlyFindings), False)
  else
    Say(TAtlasStrings.Text(TAtlasTextId.TasksOutputAll), False);
end;

function PaletteArea: TRect;
begin
  if Screen.ActiveForm <> nil then
    Result := Screen.ActiveForm.BoundsRect
  else if Application.MainForm <> nil then
    Result := Application.MainForm.BoundsRect
  else
    Result := Screen.WorkAreaRect;
end;

procedure TAtlasIdeTasks.Choose;
var
  Tasks: TAtlasTaskDefinitions;
  Commands: TArray<TAtlasCommand>;
  Command: TAtlasCommand;
  Task: TAtlasTaskDefinition;
  Window: TAtlasPaletteWindow;
  Alive: TAlive;
  Keep: IInterface;
  Owner: TAtlasIdeTasks;
  Key: string;
begin
  Tasks := Definitions;
  if Length(Tasks) = 0 then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.TasksNone), True);
    Exit;
  end;
  Key := FProject;
  if Key = '' then
    Key := NoProject;
  Commands := nil;
  for Task in Tasks do
  begin
    Command := Default(TAtlasCommand);
    Command.Id := Task.Name;
    Command.Caption := Task.Name;
    Command.Path := TAtlasTaskTexts.GroupName(Task.Group);
    Command.ShortCut := Task.KeyText;
    Command.Description := TAtlasTaskTexts.Description(Task, LastText(Key, Task.Name));
    Commands := Commands + [Command];
  end;
  Alive := FAlive;
  Keep := FAliveRef;
  Owner := Self;
  Window := TAtlasPaletteWindow.CreatePalette(Application, Commands, nil, TAtlasIdeStyle.Colors);
  Window.KeepOrder := True;
  Window.Prompt := TAtlasStrings.Text(TAtlasTextId.TasksChoosePrompt);
  Window.OnExecute :=
    procedure(ACommand: TAtlasCommand)
    begin
      if (Keep = nil) or not Alive.Alive then
        Exit;
      TAtlasGuard.Run(TAtlasFeature.Tasks,
        procedure
        var
          Reason: string;
        begin
          if not Owner.RunByName(ACommand.Id, Reason) and (Reason <> '') then
            Say(Reason, True);
        end);
    end;
  Window.ShowOver(PaletteArea);
end;

procedure TAtlasIdeTasks.ChooseFindings;
var
  Tasks: TAtlasTaskDefinitions;
  Commands: TArray<TAtlasCommand>;
  Command: TAtlasCommand;
  Task: TAtlasTaskDefinition;
  Window: TAtlasPaletteWindow;
  Alive: TAlive;
  Keep: IInterface;
  Owner: TAtlasIdeTasks;
  Key: string;
begin
  Tasks := Definitions;
  if Length(Tasks) = 0 then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.TasksNone), True);
    Exit;
  end;
  Key := FProject;
  if Key = '' then
    Key := NoProject;
  Commands := nil;
  for Task in Tasks do
  begin
    Command := Default(TAtlasCommand);
    Command.Id := Task.Name;
    if FHistory.IsHidden(Key, Task.Name) then
      Command.Caption := TAtlasStrings.Fmt(TAtlasTextId.TasksFindingsHidden, [Task.Name])
    else
      Command.Caption := TAtlasStrings.Fmt(TAtlasTextId.TasksFindingsShown, [Task.Name]);
    Command.Path := TAtlasTaskTexts.GroupName(Task.Group);
    Commands := Commands + [Command];
  end;
  Alive := FAlive;
  Keep := FAliveRef;
  Owner := Self;
  Window := TAtlasPaletteWindow.CreatePalette(Application, Commands, nil, TAtlasIdeStyle.Colors);
  Window.KeepOrder := True;
  Window.Prompt := TAtlasStrings.Text(TAtlasTextId.TasksFindingsPrompt);
  Window.OnExecute :=
    procedure(ACommand: TAtlasCommand)
    begin
      if (Keep = nil) or not Alive.Alive then
        Exit;
      TAtlasGuard.Run(TAtlasFeature.Tasks,
        procedure
        var
          Hidden: Boolean;
          Store: TAtlasProblemStore;
        begin
          Hidden := not Owner.FHistory.IsHidden(Key, ACommand.Id);
          Owner.FHistory.SetHidden(Key, ACommand.Id, Hidden);
          Owner.SaveHistory;
          Store := TAtlasProblemsController.Current;
          if Store <> nil then
            Store.SetTaskHidden(ACommand.Id, Hidden);
        end);
    end;
  Window.ShowOver(PaletteArea);
end;

procedure TAtlasIdeTasks.MenuItemClick(Sender: TObject);
var
  Index: Integer;
  Reason: string;
begin
  Index := TMenuItem(Sender).Tag;
  if (Index < 0) or (Index > High(FMenuNames)) then
    Exit;
  TAtlasGuard.Run(TAtlasFeature.Tasks,
    procedure
    begin
      if not RunByName(FMenuNames[Index], Reason) and (Reason <> '') then
        Say(Reason, True);
    end);
end;

procedure TAtlasIdeTasks.FillMenu(AMenu: TMenuItem);
var
  Tasks: TAtlasTaskDefinitions;
  Task: TAtlasTaskDefinition;
  Item: TMenuItem;
  Key: string;
begin
  AMenu.Clear;
  Tasks := Definitions;
  Key := FProject;
  if Key = '' then
    Key := NoProject;
  FMenuNames := nil;
  for Task in Tasks do
  begin
    // Ohne ShortCut am Eintrag: Die Taste belegt TAtlasIdeKeyBinding (Konfliktmeldung), hier steht sie nur.
    Item := TMenuItem.Create(AMenu);
    Item.Caption := TAtlasTaskTexts.GroupName(Task.Group) + ': ' + Task.Name + ' (' + LastText(Key, Task.Name) +
      ')';
    if Task.KeyText <> '' then
      Item.Caption := Item.Caption + #9 + Task.KeyText;
    Item.Tag := Length(FMenuNames);
    Item.OnClick := MenuItemClick;
    FMenuNames := FMenuNames + [Task.Name];
    AMenu.Add(Item);
  end;
  if Length(Tasks) = 0 then
  begin
    Item := TMenuItem.Create(AMenu);
    Item.Caption := TAtlasStrings.Text(TAtlasTextId.TasksMenuEmpty);
    Item.Enabled := False;
    AMenu.Add(Item);
  end;
end;

end.
