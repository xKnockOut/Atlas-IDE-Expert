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
// - Läufe und Reihen führt TAtlasTaskFlow (Kern); jeder Lauf ist ein
//   eigener Thread mit eigenem Prozess (TAtlasIdeTaskLauncher mit
//   TAtlasTaskProcessRun aus der Kompositionswurzel, dort
//   TAtlasTaskProcess: Job-Objekt, Zeitlimit, Abbruch). Zeilen und erkannte
//   Fundstellen kommen gesammelt alle 100 ms über TAtlasMainThread ins
//   Register „Atlas-Aufgaben“ (TAtlasIdeTaskOutput).
// - Ende eines Laufs: Kopfzeile grün/rot, letzter Lauf in tasks.json
//   (%APPDATA%\Atlas) und im Statusfeld, mit tasks.problemsFromOutput die
//   Befunde im Problemspeicher (Quelle = Aufgabenname; ein Abbruch lässt die
//   vorigen stehen). Ausgeblendete Aufgaben (ChooseFindings) merkt sich
//   tasks.json je Projekt.
// - Vor dem Build (BeforeCompile, über CreateParticipant an den
//   Compile-Ereignissen #527): Entscheidung in TAtlasTaskPreBuild des
//   Ablaufs. Mit block
//   bricht Atlas den Build ab, lässt die Prüfungen im Hintergrund laufen
//   (die IDE bleibt bedienbar) und baut nach bestandenem Lauf über OnRebuild
//   neu; ein Verstoß meldet „Name: n Fehler, Build abgebrochen“ in der Gruppe
//   Atlas, wie der Release-Wächter (#529). Mit warn läuft der Build sofort.
// - Destroy bricht laufende Aufgaben ab und wartet auf ihre Threads; was sie
//   danach noch einreihen, prüft den Merker TAlive und tut nichts.
// Nur im Hauptthread.
// Projekte, Dateien und Meldungen: Atlas.IDE.Tasks.Projects; Tasten und
// Statuszeilen: Atlas.IDE.Tasks.Shortcuts; Palettenfenster:
// Atlas.IDE.Tasks.Pickers.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  Atlas.Core.Build.Events,
  Atlas.Core.Tasks.Definitions,
  Atlas.Core.Tasks.Runs,
  Atlas.Core.Tasks.RunFlow,
  Atlas.IDE.Tasks.Output,
  Atlas.IDE.Tasks.Projects,
  Atlas.IDE.Tasks.Shortcuts;

type
  /// <summary>Eintrag im Untermenü Atlas › Aufgaben.</summary>
  TAtlasTaskMenuItem = record
    Name: string;
    Caption: string;
  end;

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

    /// <summary>Verlauf in tasks.json; Kept = gesperrt gelesen, nicht überschreiben.</summary>
    THistory = record
      Data: TAtlasTaskHistory;
      Kept: Boolean;
    end;

    THandlers = record
      OnRebuild: TAtlasTasksRebuildFunc;
      OnFinished: TAtlasTasksFinishedProc;
    end;
  private
    FAlive: TKeepAlive;
    FOutput: TAtlasIdeTaskOutput;
    FHistory: THistory;
    FFlow: TAtlasTaskFlow;
    FShortcuts: TAtlasIdeTaskShortcuts;
    FLoaded: TLoaded;
    FHandlers: THandlers;
    procedure Tick(Sender: TObject);
    procedure Refresh(AForce: Boolean);
    procedure UpdateStatus(const AName: string);
    procedure StartBatch(const AProject: string; const ATasks: TAtlasTaskDefinitions;
      const AModes: TArray<TAtlasTaskBeforeBuild>; APreBuild: Boolean);
    /// <summary>Meldung des Ablaufs: Status, Texte, Ende eines Laufs, Neubau.</summary>
    procedure Noted(const ANote: TAtlasTaskFlowNote);
    /// <summary>Lauf AId im Projekt AKey ist fertig: Ausgabe, Verlauf, Probleme, Status, OnFinished.</summary>
    procedure RunEnded(AId: Integer; const AKey: string; const ARun: TAtlasTaskRun);
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
  System.Generics.Collections,
  Atlas.Core.Status.Contract,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Problems.Store,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Tasks.Plan,
  Atlas.Core.Tasks.PreBuild,
  Atlas.Core.Tasks.Reports,
  Atlas.UI.Strings,
  Atlas.UI.Build.Strings,
  Atlas.UI.Tasks.Texts,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Problems.Controller,
  Atlas.IDE.Tasks.Launcher,
  Atlas.IDE.Tasks.Pickers,
  Atlas.IDE.Foundation.Files;

const
  cRefreshMs = 2000;
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
  // Gesperrt gelesene Datei nicht mit dem Stand dieser Sitzung überschreiben.
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

{ TAtlasIdeTasks }

/// <summary>Ende eines Laufs an den Ablauf; eigene Routine, damit die Referenz nur AOwner einfängt.</summary>
function EndedOf(AOwner: TAtlasIdeTasks): TAtlasTaskRunEnded;
begin
  Result :=
    procedure(AId: Integer; const ARun: TAtlasTaskRun)
    begin
      AOwner.FFlow.Finished(AId, ARun);
    end;
end;

function NotedOf(AOwner: TAtlasIdeTasks): TAtlasTaskFlowNoted;
begin
  Result :=
    procedure(const ANote: TAtlasTaskFlowNote)
    begin
      AOwner.Noted(ANote);
    end;
end;

constructor TAtlasIdeTasks.Create(const AProcess: TAtlasTaskProcessRun);
var
  mLauncher: IAtlasTaskLauncher;
begin
  inherited Create;
  FAlive.Flag := TAlive.Create;
  FAlive.Flag.Alive := True;
  FAlive.Ref := FAlive.Flag;
  FOutput := TAtlasIdeTaskOutput.Create;
  FOutput.OnlyFindings := TAtlasIdeSettings.Current.TasksOnlyFindings;
  FHistory.Data := TAtlasTaskHistory.Create;
  mLauncher := TAtlasIdeTaskLauncher.Create(AProcess, FOutput, EndedOf(Self), AliveCheck(FAlive));
  FFlow := TAtlasTaskFlow.Create(mLauncher, NotedOf(Self));
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
  // Laufende Aufgaben beenden (Job-Objekt) und auf ihre Threads warten; der Starter gehört dem Ablauf.
  FreeAndNil(FFlow);
  FreeAndNil(FShortcuts);
  FreeAndNil(FLoaded.Names);
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
  mProject := TAtlasIdeFiles.ActiveProjectFile;
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

procedure TAtlasIdeTasks.UpdateStatus(const AName: string);
var
  mLast: TAtlasTaskLastRun;
  mState: TAtlasStatusState;
  mKey: string;
  mRunning: Boolean;
begin
  mKey := TAtlasIdeTaskProjects.KeyOf(FLoaded.Project);
  mLast := Default(TAtlasTaskLastRun);
  mRunning := FFlow.IsRunning(mKey, AName);
  mState := TAtlasTaskPlan.StatusState(mRunning, not mRunning and FHistory.Data.LastRun(mKey, AName, mLast), mLast);
  FShortcuts.Update(AName, AName + ': ' + LastText(mKey, AName), mState, LastText(mKey, AName));
end;

/// <summary>Projekt AProject mit seinem Schlüssel für Verlauf und „läuft schon“.</summary>
function TargetOf(const AProject: string): TAtlasTaskTarget;
begin
  Result := TAtlasTaskTarget.Create(AProject, TAtlasIdeTaskProjects.KeyOf(AProject));
end;

procedure TAtlasIdeTasks.StartBatch(const AProject: string; const ATasks: TAtlasTaskDefinitions;
  const AModes: TArray<TAtlasTaskBeforeBuild>; APreBuild: Boolean);
begin
  FFlow.RunBatch(TargetOf(AProject), ATasks, AModes, APreBuild, TAtlasIdeSettings.Current.TasksRunChecksParallel);
end;

function TAtlasIdeTasks.LastText(const AProject, AName: string): string;
var
  mLast: TAtlasTaskLastRun;
  mHas: Boolean;
begin
  if FFlow.IsRunning(AProject, AName) then
  begin
    Exit(TAtlasBuildStrings.Text(TAtlasBuildTextId.TasksRunningShort));
  end;
  mHas := FHistory.Data.LastRun(AProject, AName, mLast);
  Result := TAtlasTaskTexts.LastResult(mLast, mHas);
end;

function TAtlasIdeTasks.Definitions: TAtlasTaskDefinitions;
begin
  Refresh(False);
  Result := FLoaded.Tasks;
end;

function TAtlasIdeTasks.TaskNamesOf(const AProject: string): TArray<string>;
begin
  Result := FLoaded.Names.NamesOf(AProject);
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

function TAtlasIdeTasks.RunByName(const AName: string; out AReason: string): Boolean;
begin
  Refresh(False);
  Result := RunInProject(FLoaded.Project, AName, AReason);
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
  if TAtlasIdeTaskLauncher.NeedsMissingCompiler(mTasks[mIndex], AReason) then
  begin
    Exit;
  end;
  SaveBeforeRun;
  Result := FFlow.Run(TargetOf(AProject), mTasks[mIndex]);
  if not Result then
  begin
    AReason := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksAlreadyRunning, [AName]);
  end;
end;

procedure TAtlasIdeTasks.RunChecks;
var
  mChecks: TAtlasTaskDefinitions;
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
  StartBatch(FLoaded.Project, mChecks, TAtlasTaskPlan.OffModes(Length(mChecks)), False);
end;

procedure TAtlasIdeTasks.RepeatLast;
var
  mReason: string;
begin
  if FFlow.LastName = '' then
  begin
    TAtlasIdeTaskProjects.Say(TAtlasBuildStrings.Text(TAtlasBuildTextId.TasksNoLast), True);
    Exit;
  end;
  if not RunInProject(FFlow.LastTarget.Project, FFlow.LastName, mReason) and (mReason <> '') then
  begin
    TAtlasIdeTaskProjects.Say(mReason, True);
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
    mItem.Caption := TAtlasTaskPlan.MenuCaption(TAtlasTaskTexts.GroupName(mTask.Group), mTask.Name,
      LastText(mKey, mTask.Name), mTask.KeyText);
    Result := Result + [mItem];
  end;
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

procedure TAtlasIdeTasks.Noted(const ANote: TAtlasTaskFlowNote);
begin
  case ANote.Kind of
    TAtlasTaskFlowNoteKind.Started:
      UpdateStatus(ANote.Name);
    TAtlasTaskFlowNoteKind.Skipped:
      TAtlasIdeTaskProjects.Say(ANote.Text, ANote.Loud);
    TAtlasTaskFlowNoteKind.Ended:
      RunEnded(ANote.Id, ANote.Key, ANote.Run);
    TAtlasTaskFlowNoteKind.Blocked:
      TAtlasIdeTaskProjects.Say(TAtlasTaskTexts.Blocked(ANote.Run), True);
    TAtlasTaskFlowNoteKind.Warned:
      TAtlasIdeTaskProjects.Say(TAtlasTaskTexts.Header(ANote.Run, 0), False);
    TAtlasTaskFlowNoteKind.Passed:
      if Assigned(FHandlers.OnRebuild) then
      begin
        QueueRebuild(ANote.Compile, FHandlers.OnRebuild, AliveCheck(FAlive));
      end
      else
      begin
        TAtlasIdeTaskProjects.Say(TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksGateRebuild,
          [ExtractFileName(ANote.Compile.FileName)]), True);
      end;
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
        if not TAtlasIdeFiles.ReadLines(AFileName, mLines) then
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

procedure TAtlasIdeTasks.RunEnded(AId: Integer; const AKey: string; const ARun: TAtlasTaskRun);
begin
  FOutput.Finished(AId, ARun);
  FHistory.Data.Remember(AKey, ARun);
  SaveHistory(FHistory);
  ApplyProblems(ARun, FHistory.Data.IsHidden(AKey, ARun.Name));
  if TAtlasTaskPlan.IsLoadedProject(AKey, FLoaded.Project, TAtlasIdeTaskProjects.cNoProject) then
  begin
    UpdateStatus(ARun.Name);
  end;
  if Assigned(FHandlers.OnFinished) then
  begin
    FHandlers.OnFinished(TAtlasTaskPlan.ReportedProject(AKey, TAtlasIdeTaskProjects.cNoProject), ARun);
  end;
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

procedure TAtlasIdeTasks.CancelAll;
var
  mCount: Integer;
begin
  mCount := FFlow.CancelAll;
  if mCount = 0 then
  begin
    TAtlasIdeTaskProjects.Say(TAtlasBuildStrings.Text(TAtlasBuildTextId.TasksNothingRunning), True);
  end
  else
  begin
    TAtlasIdeTaskProjects.Say(TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksCancelledAll, [mCount]), False);
  end;
end;

function TAtlasIdeTasks.BeforeCompile(const AProject: TAtlasCompileProject; out AReason: string): Boolean;
var
  mGlobal: TAtlasTaskBeforeBuild;
  mTasks: TAtlasTaskDefinitions;
  mIssues: TArray<string>;
  mPlan: TAtlasTaskPreBuildPlan;
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
  mPlan := TAtlasTaskPlan.PreBuild(mTasks, mGlobal);
  mAction := FFlow.PreBuild.Decide(AProject, mPlan.HasBlock, mPlan.HasWarn, TThread.GetTickCount64);
  case mAction of
    TAtlasTaskPreBuildAction.StartAndCancel:
      AReason := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksGateRunning, [mPlan.Names]);
    TAtlasTaskPreBuildAction.Busy:
      AReason := TAtlasBuildStrings.Text(TAtlasBuildTextId.TasksGateBusy);
    TAtlasTaskPreBuildAction.None, TAtlasTaskPreBuildAction.StartWarn: ;
  end;
  Result := TAtlasTaskPlan.CancelsCompile(mAction);
  if TAtlasTaskPlan.StartsRun(mAction) then
  begin
    SaveBeforeRun;
    StartBatch(AProject.FileName, mTasks, mPlan.Modes, True);
  end;
end;

procedure TAtlasIdeTasks.ApplySettings;
begin
  FOutput.OnlyFindings := TAtlasIdeSettings.Current.TasksOnlyFindings;
  Refresh(True);
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

function TAtlasIdeTasks.Busy: Boolean;
begin
  Result := FFlow.Busy;
end;

class function TAtlasIdeTasks.CreateParticipant(const AGet: TFunc<TAtlasIdeTasks>): TAtlasCompileParticipant;
begin
  Result := TParticipant.Create(AGet);
end;

end.
