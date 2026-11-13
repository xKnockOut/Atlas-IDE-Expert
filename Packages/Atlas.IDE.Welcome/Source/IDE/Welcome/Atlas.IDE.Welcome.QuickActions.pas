unit Atlas.IDE.Welcome.QuickActions;

// Schnellaktionen je Projekt auf der Willkommensseite in der IDE (#764):
// Quelle der Knopfleiste (IAtlasQuickActionsSource) in den Bereichen
// „Projekte“ (#592) und „Weiterarbeiten“ (#755).
// - „Öffnen und bauen“: öffnet das Projekt bzw. die Projektgruppe wie die
//   IDE (eine neue Gruppe fragt nach dem Speichern der offenen) und baut über
//   den Läufer der Builds auf Auftrag (#261, Auftraggeber "welcome", Haken
//   OnBuild) mit der gewählten bzw. zuletzt benutzten Konfiguration und
//   Plattform; eine Gruppe baut ihre Projekte nacheinander. Der
//   Release-Wächter (#533) gilt: sein Abbruch endet als „nicht gebaut“ mit
//   Grund. Das Ergebnis zeigt die Marke „Build 0/0/0“ des Bereichs (der
//   Build zählt als Build des Benutzers).
// - „Tests“: öffnet das Projekt, nimmt das Testprojekt (Kern:
//   TestProjectFor; bei mehreren fragt die Leiste) bei Bedarf in die Gruppe
//   auf und startet den Lauf über den Haken OnTests (#69, immer mit Build
//   vorab). Das Ergebnis kommt über TestsFinished (Composition, derselbe Weg
//   wie zur Karte Testergebnisse #763); endet der Lauf ohne Ergebnis, steht
//   „Tests nicht gelaufen“ mit Verweis auf die Meldungsansicht.
// - „Startprofil ▾“: Profile über OnProfiles, Start über OnRun (#575) für das
//   Projekt bzw. das aktive Projekt der Gruppe.
// - „Pull“ bzw. „Aktualisieren“ (SVN): im Hintergrund über TAtlasIdeVcs.Run
//   mit Zeitlimit, nur vorwärts, vorher frisch auf lokale Änderungen geprüft;
//   danach fragt „Projekte“ Branch und Änderungen neu ab. Unter SVN nach
//   vcs.externals.update (#1292): mit Externals, ohne (--ignore-externals)
//   oder mit Auswahl am Knopf (AskExternals). Den Index der geholten Ordner
//   frischt die Dateiüberwachung (#395) auf, sie umfasst die Projektordner.
// - „Aufgaben ▾“ (#900): Namen über OnTaskNames, Start über OnRunTask (der
//   Aufgabenläufer des Moduls Build, im Hintergrund); das Ende meldet
//   TaskFinished (IAtlasTaskListener) mit dem Ergebnis („Delphi-12-Prüfung: 2 Fehler 14:03“). Ohne tasks.enabled bzw.
//   ohne Aufgaben im Projekt gibt es den Knopf nicht.
// - „Ordner“: Explorer wie im Kontextmenü von „Projekte“. „Konsole“:
//   welcomePage.quickActions.console im Projektordner, ohne Windows-Terminal
//   cmd.exe.
// - Stand je Projekt in dieser Sitzung (läuft seit, Ergebnis, Grund);
//   Meldungen mit Pfaden nur in die Meldungsansicht (AMessage).
// - Strg+B und Strg+T (einstellbar) nimmt die Quelle über
//   TApplicationEvents vor den Tasten der IDE ab, solange die unsichtbare
//   Tastatur-Steuerung einer Leiste den Fokus hat.
// - Nutzung: Ein Klick zählt als Aufruf per Maus (Tastenkürzel-Tipps #600,
//   Atlas.WelcomeQuickBuild bzw. Atlas.WelcomeQuickTests); die Taste zählt
//   die Beobachtung der Tastatur selbst.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Winapi.Windows,
  Vcl.ExtCtrls,
  Vcl.AppEvnts,
  Atlas.IDE.Contracts.BuildTools,
  Atlas.Core.Welcome.QuickActions,
  Atlas.UI.Welcome.QuickActions,
  Atlas.IDE.Welcome.Projects;

type
  /// <summary>Ende eines Builds: AError &lt;&gt; '' = nicht gebaut (Grund), sonst Erfolg.</summary>
  TAtlasQuickBuildDone = reference to procedure(ASucceeded: Boolean; const AError: string);
  /// <summary>Baut das offene AProject (Konfiguration und Plattform '' = wie in der IDE); False mit Grund.</summary>
  TAtlasQuickBuildFunc = reference to function(const AProject, AConfiguration, APlatform: string;
    const ADone: TAtlasQuickBuildDone; out AReason: string): Boolean;
  /// <summary>Startet die Tests des offenen Testprojekts ATestProject (mit Build vorab); False mit Grund.</summary>
  TAtlasQuickTestsFunc = reference to function(const ATestProject: string; out AReason: string): Boolean;
  /// <summary>Startprofile von AProject (Namen) und das aktive.</summary>
  TAtlasQuickProfilesFunc = reference to function(const AProject: string; out AActive: string): TArray<string>;
  /// <summary>Startet das offene AProject mit Profil AProfile ('' = ohne); False mit Grund.</summary>
  TAtlasQuickRunFunc = reference to function(const AProject, AProfile: string; out AReason: string): Boolean;
  /// <summary>Namen der Projektaufgaben von AProject (#900).</summary>
  TAtlasQuickTaskNamesFunc = reference to function(const AProject: string): TArray<string>;
  /// <summary>Startet die Projektaufgabe AName von AProject; False mit Grund.</summary>
  TAtlasQuickRunTaskFunc = reference to function(const AProject, AName: string; out AReason: string): Boolean;

  /// <summary>Haken der IDE-Schicht für die Schnellaktionen (Composition setzt sie).</summary>
  TAtlasQuickActionHooks = record
    OnBuild: TAtlasQuickBuildFunc;
    OnTests: TAtlasQuickTestsFunc;
    /// <summary>Läuft ein Testlauf (auch der Build davor)?</summary>
    OnTestsBusy: TFunc<Boolean>;
    /// <summary>Ist die IDE schon mit einem Build oder Testlauf beschäftigt (auch nicht von hier)?</summary>
    OnIdeBusy: TFunc<Boolean>;
    OnProfiles: TAtlasQuickProfilesFunc;
    OnRun: TAtlasQuickRunFunc;
    OnTaskNames: TAtlasQuickTaskNamesFunc;
    OnRunTask: TAtlasQuickRunTaskFunc;
  end;

  TAtlasIdeQuickActions = class(TInterfacedObject, IAtlasQuickActionsSource)
  public const
    /// <summary>Takt der Prüfung, ob ein Testlauf ohne Ergebnis endete.</summary>
    cWatchMs = 500;
    /// <summary>So lange nach dem Start gilt ein Testlauf ohne Busy noch nicht als beendet.</summary>
    cWatchGraceMs = 1500;
    /// <summary>So lange nach Strg+B bzw. Strg+T zählt ein Aufruf nicht als Mausklick.</summary>
    cKeyUseMs = 1000;
    cBuildCommandId = 'Atlas.WelcomeQuickBuild';
    cTestsCommandId = 'Atlas.WelcomeQuickTests';
  private type
    TRuns = record
      // Normierter Pfad → Stand der letzten Schnellaktion.
      States: TDictionary<string, TAtlasQuickActionState>;
      // Normiertes Testprojekt → Projekt der Zeile, deren Tests laufen.
      Tests: TDictionary<string, string>;
      // Normiertes Projekt → Name der gestarteten Projektaufgabe.
      Tasks: TDictionary<string, string>;
    end;
    TInput = record
      Watch: TTimer;
      Events: TApplicationEvents;
      KeyAt: UInt64;
    end;
  private
    FMessage: TProc<string>;
    FProjects: TAtlasIdeProjects;
    FStopped: Boolean;
    FRuns: TRuns;
    FInput: TInput;
    procedure Changed;
    procedure Report(const AText: string);
    procedure SetState(const AProject: string; const AState: TAtlasQuickActionState);
    procedure StartAction(const AProject: string; AAction: TAtlasQuickAction);
    procedure Finish(const AProject: string; AAction: TAtlasQuickAction; APhase: TAtlasQuickActionPhase;
      const ADetail: string);
    procedure BuildNext(const ARow: string; const AProjects: TArray<string>; AIndex: Integer;
      const AConfiguration, APlatform: string);
    procedure Pull(const AProject: string); overload;
    procedure WatchTick(Sender: TObject);
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
  public
    Hooks: TAtlasQuickActionHooks;
    /// <summary>AProjects: Quelle von „Projekte“ (Branch und Änderungen, Ordner, Neu-Abfrage nach Pull);
    /// AMessage: Zeile in die Meldungsansicht.</summary>
    constructor Create(AProjects: TAtlasIdeProjects; const AMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Tastaturbeobachtung anmelden.</summary>
    procedure Start;
    /// <summary>Alles abmelden (beim Entladen); danach wirkungslos.</summary>
    procedure Stop;
    /// <summary>Nach einer Einstellungsänderung: Bereiche neu zeichnen.</summary>
    procedure Refresh;
    /// <summary>Ein Testlauf (#69) von ATestProject ist fertig; gehört er zu einer Schnellaktion, steht das
    /// Ergebnis in deren Zeile. Hauptthread.</summary>
    procedure TestsFinished(const ATestProject: string; APassed, AFailed: Integer);
    /// <summary>Eine Projektaufgabe von AProject ist fertig; hat die Schnellaktion sie gestartet, steht das
    /// Ergebnis in deren Zeile. Hauptthread.</summary>
    procedure TaskFinished(const AProject: string; const AResult: TAtlasTaskResult);
    { IAtlasQuickActionsSource }
    function Enabled: Boolean;
    function Buttons(const AProject: string): TAtlasQuickActionButtons;
    function State(const AProject: string): TAtlasQuickActionState;
    function NowMs: UInt64;
    procedure Execute(const AProject: string; AAction: TAtlasQuickAction);
    function Targets(const AProject: string; out AConfiguration, APlatform: string): TAtlasProjectTargets;
    procedure Build(const AProject, AConfiguration, APlatform: string);
    function TestProjects(const AProject: string): TArray<string>;
    procedure RunTests(const AProject, ATestProject: string);
    function Profiles(const AProject: string; out AActive: string): TArray<string>;
    procedure Run(const AProject, AProfile: string);
    function TaskNames(const AProject: string): TArray<string>;
    procedure RunTask(const AProject, AName: string);
    procedure Pull(const AProject: string; AIgnoreExternals: Boolean); overload;
    function BuildKey: Integer;
    function TestKey: Integer;
    function ConsoleProgram: string;
  end;

implementation

uses
  Atlas.Core.Projects.Summary,
  Winapi.Messages,
  Winapi.ShellAPI,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Menus,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.Pull,
  Atlas.Core.Welcome.Sections,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Contracts.VersionControl,
  Atlas.IDE.Commands.ShortcutTips,
  Atlas.Core.Files.TextFile,
  Atlas.IDE.Projects.Summaries;

function Settings: TAtlasPluginSettings;
begin
  Result := TAtlasIdeSettings.Current;
end;

function ReadLines(const AFileName: string; out ALines: TArray<string>): Boolean;
begin
  ALines := nil;
  try
    ALines := TAtlasTextFile.LoadLines(AFileName);
    Result := True;
  except
    // Nicht lesbar: zählt wie nicht vorhanden.
    on Exception do
      Result := False;
  end;
end;

{ Hilfen }

function Key(const AProject: string): string;
begin
  Result := TAtlasProjectSummaries.NormalizedPath(AProject);
end;

function NameOf(const AProject: string): string;
begin
  Result := ChangeFileExt(ExtractFileName(AProject), '');
end;

function IdeBusy(ASelf: TAtlasIdeQuickActions; const AProject: string): Boolean;
var
  mPair: TPair<string, TAtlasQuickActionState>;
  mOwn: string;
begin
  // Die IDE öffnet immer nur ein Projekt zur Zeit: eine laufende Aktion eines anderen Projekts sperrt.
  mOwn := Key(AProject);
  for mPair in ASelf.FRuns.States do
  begin
    if (mPair.Key <> mOwn) and mPair.Value.Running and TAtlasWelcomeQuickActions.UsesIde(mPair.Value.Action) then
    begin
      Exit(True);
    end;
  end;
  Result := Assigned(ASelf.Hooks.OnIdeBusy) and ASelf.Hooks.OnIdeBusy();
end;

function ProjectOpen(const AFileName: string): Boolean;
var
  mModules: IOTAModuleServices;
begin
  Result := Supports(BorlandIDEServices, IOTAModuleServices, mModules) and (mModules.FindModule(AFileName) <> nil);
end;

function GroupMembers(const AGroup: string): TArray<string>;
var
  mModules: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
  mIndex: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mModules) or
    not Supports(mModules.FindModule(AGroup), IOTAProjectGroup, mGroup) then
  begin
    Exit;
  end;
  for mIndex := 0 to mGroup.ProjectCount - 1 do
  begin
    if (mGroup.Projects[mIndex] <> nil) and (mGroup.Projects[mIndex].FileName <> '') then
    begin
      Result := Result + [mGroup.Projects[mIndex].FileName];
    end;
  end;
end;

function ActiveProjectOf(const AGroup: string): string;
var
  mModules: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
begin
  Result := '';
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) and
    Supports(mModules.FindModule(AGroup), IOTAProjectGroup, mGroup) and (mGroup.ActiveProject <> nil) then
  begin
    Result := mGroup.ActiveProject.FileName;
  end;
end;

function EnsureOpen(const AProject: string; out AReason: string): Boolean;
var
  mActions: IOTAActionServices;
begin
  AReason := '';
  if ProjectOpen(AProject) then
  begin
    Exit(True);
  end;
  if not FileExists(AProject) then
  begin
    AReason := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickReasonMissing);
    Exit(False);
  end;
  // Wie „Öffnen“ der IDE: Eine neue Gruppe fragt nach dem Speichern der offenen; Abbrechen lässt sie offen.
  if Supports(BorlandIDEServices, IOTAActionServices, mActions) then
  begin
    TAtlasGuard.RunIde(
      procedure
      begin
        mActions.OpenProject(AProject, True);
      end);
  end;
  Result := ProjectOpen(AProject);
  if not Result then
  begin
    AReason := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickReasonNotOpened);
  end;
end;

procedure CountUse(ASelf: TAtlasIdeQuickActions; const AId: string);
begin
  // Über die Taste: zählt die Beobachtung der Tastatur (#600) schon.
  if ASelf.NowMs - ASelf.FInput.KeyAt < TAtlasIdeQuickActions.cKeyUseMs then
  begin
    Exit;
  end;
  TAtlasIdeShortcutTips.Invoked(AId);
end;

procedure OpenConsole(ASelf: TAtlasIdeQuickActions; const AProject: string);
var
  mProgram_, mDir, mFileName, mParameters: string;
  mStarted: Boolean;

  function Launch(const AProgram: string): Boolean;
  begin
    Result := TAtlasWelcomeQuickActions.ConsoleCommand(AProgram, mDir, mFileName, mParameters) and
      (ShellExecute(0, 'open', PChar(mFileName), PChar(mParameters), PChar(mDir), SW_SHOWNORMAL) > 32);
  end;

begin
  mProgram_ := ASelf.ConsoleProgram;
  mDir := ExtractFileDir(AProject);
  mStarted := DirectoryExists(mDir) and Launch(mProgram_);
  // Ohne Windows-Terminal: cmd.exe (nur für die Vorgabe; ein eigenes Programm meldet seinen Fehler).
  if not mStarted and DirectoryExists(mDir) and SameText(mProgram_, TAtlasWelcomeQuickActions.cDefaultConsole) then
  begin
    mStarted := Launch(TAtlasWelcomeQuickActions.cFallbackConsole);
  end;
  if mStarted then
  begin
    Exit;
  end;
  ASelf.SetState(AProject, TAtlasQuickActionState.Started(TAtlasQuickAction.Console, ASelf.NowMs));
  ASelf.Finish(AProject, TAtlasQuickAction.Console, TAtlasQuickActionPhase.Failed, '');
  ASelf.Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickMsgConsoleFailed, [mProgram_]));
end;

function PullFailedText(const AProject: string; AReason: TAtlasVcsOutcome; AUpdate: Boolean): string;
begin
  if AUpdate then
  begin
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickMsgUpdateFailed, [NameOf(AProject),
      AtlasVcsOutcomeName(AReason)]);
  end
  else
  begin
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickMsgPullFailed, [NameOf(AProject),
      AtlasVcsOutcomeName(AReason)]);
  end;
end;

/// <summary>Testprojekt außerhalb der Gruppe in die offene Gruppe aufnehmen (wie „Projekt hinzufügen“); Grund,
/// wenn es nicht geht, sonst ''.</summary>
function AddTestProject(const ATestProject: string): string;
var
  mActions: IOTAActionServices;
begin
  Result := '';
  if not FileExists(ATestProject) then
  begin
    Exit(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickReasonMissing));
  end;
  if Supports(BorlandIDEServices, IOTAActionServices, mActions) then
  begin
    TAtlasGuard.RunIde(
      procedure
      begin
        mActions.OpenProject(ATestProject, False);
      end);
  end;
  if not ProjectOpen(ATestProject) then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickReasonNotOpened);
  end;
end;

procedure StopWatch(ASelf: TAtlasIdeQuickActions);
begin
  if ASelf.FInput.Watch <> nil then
  begin
    ASelf.FInput.Watch.Enabled := False;
  end;
end;

/// <summary>Testläufe, die ohne Ergebnis endeten: Zeile läuft nicht mehr oder die Schonzeit ist um.</summary>
function EndedTests(ASelf: TAtlasIdeQuickActions): TArray<string>;
var
  mPair: TPair<string, string>;
begin
  Result := nil;
  for mPair in ASelf.FRuns.Tests do
  begin
    if ASelf.State(mPair.Value).TestEnded(ASelf.NowMs, TAtlasIdeQuickActions.cWatchGraceMs) then
    begin
      Result := Result + [mPair.Key];
    end;
  end;
end;

/// <summary>Stand nach einem Pull mit Meldung bei Fehlern; AUpdate: SVN („Aktualisieren“).</summary>
function PullResult(ASelf: TAtlasIdeQuickActions; const AProject: string; AOutcome: TAtlasPullOutcome;
  AReason: TAtlasVcsOutcome; AUpdate: Boolean): TAtlasQuickActionState;
var
  mNote: TAtlasPullNote;
begin
  // Was gilt, entscheidet Core (AfterPull); hier nur die Texte.
  Result := ASelf.State(AProject).AfterPull(AOutcome, AReason, mNote);
  case mNote of
    TAtlasPullNote.None:
      ;
    TAtlasPullNote.LocalChanges:
      begin
        Result.Detail := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickPullLocalChanges);
        ASelf.Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickMsgPullBlocked, [NameOf(AProject)]));
      end;
    TAtlasPullNote.NoWorkingCopy:
      Result.Detail := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickPullNoWorkingCopy);
    TAtlasPullNote.Login:
      begin
        Result.Detail := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickPullLogin);
        ASelf.Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickMsgPullLogin, [NameOf(AProject)]));
      end;
    TAtlasPullNote.Failed:
      ASelf.Report(PullFailedText(AProject, AReason, AUpdate));
  end;
end;

{ TAtlasIdeQuickActions }

constructor TAtlasIdeQuickActions.Create(AProjects: TAtlasIdeProjects; const AMessage: TProc<string>);
begin
  inherited Create;
  FProjects := AProjects;
  FMessage := AMessage;
  FRuns.States := TDictionary<string, TAtlasQuickActionState>.Create;
  FRuns.Tests := TDictionary<string, string>.Create;
  FRuns.Tasks := TDictionary<string, string>.Create;
end;

destructor TAtlasIdeQuickActions.Destroy;
begin
  Stop;
  FRuns.Tasks.Free;
  FRuns.Tests.Free;
  FRuns.States.Free;
  inherited;
end;

procedure TAtlasIdeQuickActions.Start;
begin
  FStopped := False;
  if FInput.Events = nil then
  begin
    FInput.Events := TApplicationEvents.Create(nil);
    FInput.Events.OnMessage := AppMessage;
  end;
  if FInput.Watch = nil then
  begin
    FInput.Watch := TTimer.Create(nil);
    FInput.Watch.Enabled := False;
    FInput.Watch.Interval := cWatchMs;
    FInput.Watch.OnTimer := WatchTick;
  end;
end;

procedure TAtlasIdeQuickActions.Stop;
begin
  FStopped := True;
  FreeAndNil(FInput.Events);
  FreeAndNil(FInput.Watch);
  FProjects := nil;
  Hooks := Default(TAtlasQuickActionHooks);
end;

procedure TAtlasIdeQuickActions.Refresh;
begin
  Changed;
end;

procedure TAtlasIdeQuickActions.Changed;
begin
  if FStopped then
  begin
    Exit;
  end;
  TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.cProjects);
  TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.cContinue);
end;

procedure TAtlasIdeQuickActions.Report(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

function TAtlasIdeQuickActions.NowMs: UInt64;
begin
  Result := GetTickCount64;
end;

function TAtlasIdeQuickActions.Enabled: Boolean;
begin
  Result := not FStopped and Settings.WelcomePage and Settings.WelcomePageQuickActions;
end;

function TAtlasIdeQuickActions.BuildKey: Integer;
begin
  Result := Settings.WelcomePageQuickActionsBuildKey;
end;

function TAtlasIdeQuickActions.TestKey: Integer;
begin
  Result := Settings.WelcomePageQuickActionsTestKey;
end;

function TAtlasIdeQuickActions.ConsoleProgram: string;
begin
  Result := TAtlasWelcomeQuickActions.NormalizedConsole(Settings.WelcomePageQuickActionsConsole);
end;

function TAtlasIdeQuickActions.State(const AProject: string): TAtlasQuickActionState;
begin
  if not FRuns.States.TryGetValue(Key(AProject), Result) then
  begin
    Result := TAtlasQuickActionState.Idle;
  end;
end;

procedure TAtlasIdeQuickActions.SetState(const AProject: string; const AState: TAtlasQuickActionState);
begin
  FRuns.States.AddOrSetValue(Key(AProject), AState);
end;

procedure TAtlasIdeQuickActions.StartAction(const AProject: string; AAction: TAtlasQuickAction);
begin
  SetState(AProject, TAtlasQuickActionState.Started(AAction, NowMs));
  Changed;
end;

procedure TAtlasIdeQuickActions.Finish(const AProject: string; AAction: TAtlasQuickAction;
  APhase: TAtlasQuickActionPhase; const ADetail: string);
var
  mValue: TAtlasQuickActionState;
begin
  if FStopped then
  begin
    Exit;
  end;
  mValue := State(AProject);
  mValue.Action := AAction;
  mValue.Phase := APhase;
  mValue.Detail := ADetail;
  SetState(AProject, mValue);
  Changed;
end;

function TAtlasIdeQuickActions.Buttons(const AProject: string): TAtlasQuickActionButtons;
var
  mItems: TAtlasQuickActions;
  mVcs: TAtlasProjectVcs;
begin
  Result := nil;
  if not Enabled or (FProjects = nil) then
  begin
    Exit;
  end;
  mItems := TAtlasWelcomeQuickActions.ParseItems(Settings.WelcomePageQuickActionsItems);
  // Ohne „Tests ausführen“ (#69) gibt es keinen Läufer: kein Knopf.
  if not Settings.TestRun then
  begin
    Exclude(mItems, TAtlasQuickAction.Tests);
  end;
  // „Aufgaben ▾“ nur mit eingeschalteten Projektaufgaben (#900) und Aufgaben im Projekt.
  if (TAtlasQuickAction.Tasks in mItems) and (not Settings.TasksEnabled or (Length(TaskNames(AProject)) = 0)) then
  begin
    Exclude(mItems, TAtlasQuickAction.Tasks);
  end;
  mVcs := FProjects.VcsOf(AProject);
  Result := TAtlasWelcomeQuickActions.Buttons(mItems, mVcs, State(AProject).Running, IdeBusy(Self, AProject));
  // vcs.externals.update = ask (#1292): „Aktualisieren ▾“ mit Auswahl.
  if AtlasVcsExternalsUpdateOf(Settings.VcsExternalsUpdate) = TAtlasVcsExternalsUpdate.Ask then
  begin
    TAtlasWelcomeQuickActions.AskExternals(Result);
  end;
end;

procedure TAtlasIdeQuickActions.Execute(const AProject: string; AAction: TAtlasQuickAction);
var
  mConfiguration, mPlatform: string;
  mCandidates, mNames: TArray<string>;
begin
  if FStopped or not Enabled then
  begin
    Exit;
  end;
  case AAction of
    TAtlasQuickAction.Build:
      begin
        Targets(AProject, mConfiguration, mPlatform);
        Build(AProject, mConfiguration, mPlatform);
      end;
    TAtlasQuickAction.Tests:
      begin
        mCandidates := TestProjects(AProject);
        if Length(mCandidates) = 0 then
        begin
          CountUse(Self, cTestsCommandId);
          SetState(AProject, TAtlasQuickActionState.Started(TAtlasQuickAction.Tests, NowMs));
          Finish(AProject, TAtlasQuickAction.Tests, TAtlasQuickActionPhase.Refused,
            TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickReasonNoTestProject));
          Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickMsgNoTestProject, [NameOf(AProject)]));
        end
        else
        begin
          // Mehrere: Die Leiste fragt vorher; ohne Auswahl (etwa aus dem Kontextmenü) das erste.
          RunTests(AProject, mCandidates[0]);
        end;
      end;
    TAtlasQuickAction.Run:
      Run(AProject, '');
    TAtlasQuickAction.Pull:
      Pull(AProject);
    TAtlasQuickAction.Folder:
      if FProjects <> nil then
      begin
        FProjects.OpenFolder(AProject);
      end;
    TAtlasQuickAction.Console:
      OpenConsole(Self, AProject);
    TAtlasQuickAction.Tasks:
      begin
        // Ohne Auswahl (Kontextmenü, Enter) die erste Aufgabe; die Leiste fragt sonst vorher.
        mNames := TaskNames(AProject);
        if Length(mNames) > 0 then
        begin
          RunTask(AProject, mNames[0]);
        end;
      end;
  end;
end;

function TAtlasIdeQuickActions.Targets(const AProject: string; out AConfiguration,
  APlatform: string): TAtlasProjectTargets;
var
  mSummary: TAtlasProjectSummary;
  mText: string;
begin
  Result := Default(TAtlasProjectTargets);
  AConfiguration := '';
  APlatform := '';
  // Eine Gruppe baut wie in der IDE eingestellt.
  if TAtlasWelcomeQuickActions.IsGroup(AProject) or not FileExists(AProject) then
  begin
    Exit;
  end;
  try
    mText := TAtlasTextFile.LoadText(AProject);
  except
    on Exception do
      Exit;
  end;
  Result := TAtlasWelcomeQuickActions.ReadTargets(mText);
  // Vorgabe: zuletzt benutzt (Abschnitt "build" der Zusammenfassung), wenn das Projekt sie noch kennt.
  if TAtlasProjectSummaries.Load(TAtlasIdeProjectSummaries.Folder, AProject, mSummary) and mSummary.Build.Known then
  begin
    TAtlasWelcomeQuickActions.ChooseTarget(Result, mSummary.Build.Configuration, mSummary.Build.Platform,
      AConfiguration, APlatform);
  end;
end;

procedure TAtlasIdeQuickActions.Build(const AProject, AConfiguration, APlatform: string);
var
  mReason: string;
  mList: TArray<string>;
begin
  if FStopped or not Enabled or State(AProject).Running then
  begin
    Exit;
  end;
  CountUse(Self, cBuildCommandId);
  StartAction(AProject, TAtlasQuickAction.Build);
  if not EnsureOpen(AProject, mReason) then
  begin
    Finish(AProject, TAtlasQuickAction.Build, TAtlasQuickActionPhase.Refused, mReason);
    Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickMsgBuildRefused, [NameOf(AProject), mReason]));
    Exit;
  end;
  mList := [AProject];
  if TAtlasWelcomeQuickActions.IsGroup(AProject) then
  begin
    mList := GroupMembers(AProject);
  end;
  if Length(mList) = 0 then
  begin
    Finish(AProject, TAtlasQuickAction.Build, TAtlasQuickActionPhase.Succeeded, '');
    Exit;
  end;
  BuildNext(AProject, mList, 0, AConfiguration, APlatform);
end;

procedure TAtlasIdeQuickActions.BuildNext(const ARow: string; const AProjects: TArray<string>; AIndex: Integer;
  const AConfiguration, APlatform: string);
var
  mRow, mConfiguration, mPlatform, mReason: string;
  mProjects: TArray<string>;
  mIndex: Integer;
  mKeep: IInterface;
begin
  mRow := ARow;
  mProjects := AProjects;
  mIndex := AIndex;
  mConfiguration := AConfiguration;
  mPlatform := APlatform;
  mKeep := Self;
  mReason := TAtlasStrings.Text(TAtlasTextId.TestsNoBuildRunner);
  if not Assigned(Hooks.OnBuild) or not Hooks.OnBuild(mProjects[mIndex], mConfiguration, mPlatform,
    procedure(ASucceeded: Boolean; const AError: string)
    begin
      // Keep hält die Quelle bis hierher am Leben.
      if (mKeep = nil) or FStopped then
      begin
        Exit;
      end;
      if AError <> '' then
      begin
        Finish(mRow, TAtlasQuickAction.Build, TAtlasQuickActionPhase.Refused, AError);
        Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickMsgBuildRefused,
          [NameOf(mProjects[mIndex]), AError]));
      end
      else if not ASucceeded then
      begin
        Finish(mRow, TAtlasQuickAction.Build, TAtlasQuickActionPhase.Failed, '');
      end
      else if mIndex < High(mProjects) then
      begin
        // Nächstes Projekt der Gruppe nicht im Rückruf des Läufers: Er schließt seinen Auftrag erst danach ab.
        TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
          procedure
          begin
            if (mKeep <> nil) and not FStopped then
            begin
              BuildNext(mRow, mProjects, mIndex + 1, mConfiguration, mPlatform);
            end;
          end);
      end
      else
      begin
        Finish(mRow, TAtlasQuickAction.Build, TAtlasQuickActionPhase.Succeeded, '');
      end;
    end, mReason) then
  begin
    Finish(mRow, TAtlasQuickAction.Build, TAtlasQuickActionPhase.Refused, mReason);
    Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickMsgBuildRefused,
      [NameOf(mProjects[mIndex]), mReason]));
  end;
end;

function TAtlasIdeQuickActions.TestProjects(const AProject: string): TArray<string>;
var
  mFound: string;
  mCandidates: TArray<string>;
begin
  mFound := TAtlasWelcomeQuickActions.TestProjectFor(AProject,
    function(const AFileName: string): Boolean
    begin
      Result := FileExists(AFileName);
    end,
    function(const AFileName: string; out ALines: TArray<string>): Boolean
    begin
      Result := ReadLines(AFileName, ALines);
    end, mCandidates);
  if mFound <> '' then
  begin
    Result := [mFound];
  end
  else
  begin
    Result := mCandidates;
  end;
end;

procedure TAtlasIdeQuickActions.RunTests(const AProject, ATestProject: string);
var
  mReason: string;
begin
  if FStopped or not Enabled or State(AProject).Running then
  begin
    Exit;
  end;
  CountUse(Self, cTestsCommandId);
  StartAction(AProject, TAtlasQuickAction.Tests);
  if EnsureOpen(AProject, mReason) and not ProjectOpen(ATestProject) then
  begin
    mReason := AddTestProject(ATestProject);
  end;
  if (mReason = '') and not Assigned(Hooks.OnTests) then
  begin
    mReason := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickReasonTestsOff);
  end
  else if mReason = '' then
  begin
    // Vor dem Start eintragen: Das Ergebnis (TestsFinished) findet so die Zeile in jedem Fall.
    FRuns.Tests.AddOrSetValue(Key(ATestProject), AProject);
    if not Hooks.OnTests(ATestProject, mReason) and (mReason = '') then
    begin
      mReason := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickReasonSeeMessages);
    end;
  end;
  if mReason <> '' then
  begin
    FRuns.Tests.Remove(Key(ATestProject));
    Finish(AProject, TAtlasQuickAction.Tests, TAtlasQuickActionPhase.Refused, mReason);
    Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickMsgTestsRefused, [NameOf(AProject), mReason]));
  end
  else if FInput.Watch <> nil then
  begin
    // Ohne Ergebnis endet der Lauf, wenn der Läufer nicht mehr beschäftigt ist (WatchTick).
    FInput.Watch.Enabled := FRuns.Tests.ContainsKey(Key(ATestProject));
  end;
end;

procedure TAtlasIdeQuickActions.TestsFinished(const ATestProject: string; APassed, AFailed: Integer);
var
  mRow: string;
  mValue: TAtlasQuickActionState;
begin
  if FStopped or not FRuns.Tests.TryGetValue(Key(ATestProject), mRow) then
  begin
    Exit;
  end;
  FRuns.Tests.Remove(Key(ATestProject));
  mValue := State(mRow);
  mValue.Action := TAtlasQuickAction.Tests;
  mValue.Passed := APassed;
  mValue.Failed := AFailed;
  mValue.Detail := '';
  if mValue.Failed > 0 then
  begin
    mValue.Phase := TAtlasQuickActionPhase.Failed;
  end
  else
  begin
    mValue.Phase := TAtlasQuickActionPhase.Succeeded;
  end;
  SetState(mRow, mValue);
  Changed;
end;

procedure TAtlasIdeQuickActions.WatchTick(Sender: TObject);
var
  mEnding, mRow: string;
begin
  try
    if FStopped or (FRuns.Tests.Count = 0) then
    begin
      StopWatch(Self);
      Exit;
    end;
    // Läuft nichts mehr und kam kein Ergebnis: Der Läufer hat abgelehnt oder abgebrochen (Grund in der
    // Meldungsansicht).
    if Assigned(Hooks.OnTestsBusy) and Hooks.OnTestsBusy() then
    begin
      Exit;
    end;
    for mEnding in EndedTests(Self) do
    begin
      if FRuns.Tests.TryGetValue(mEnding, mRow) and State(mRow).Running then
      begin
        Finish(mRow, TAtlasQuickAction.Tests, TAtlasQuickActionPhase.Failed,
          TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickReasonSeeMessages));
      end;
      FRuns.Tests.Remove(mEnding);
    end;
    if FRuns.Tests.Count = 0 then
    begin
      StopWatch(Self);
    end;
  except
    on E: Exception do
    begin
      StopWatch(Self);
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
    end;
  end;
end;

function TAtlasIdeQuickActions.Profiles(const AProject: string; out AActive: string): TArray<string>;
begin
  Result := nil;
  AActive := '';
  // Eine Gruppe startet ihr aktives Projekt mit dessen Auswahl (erst nach dem Öffnen bekannt).
  if TAtlasWelcomeQuickActions.IsGroup(AProject) or not Assigned(Hooks.OnProfiles) then
  begin
    Exit;
  end;
  Result := Hooks.OnProfiles(AProject, AActive);
end;

procedure TAtlasIdeQuickActions.Run(const AProject, AProfile: string);
var
  mReason, mTarget: string;
begin
  if FStopped or not Enabled or State(AProject).Running then
  begin
    Exit;
  end;
  StartAction(AProject, TAtlasQuickAction.Run);
  mTarget := '';
  if EnsureOpen(AProject, mReason) then
  begin
    mTarget := AProject;
    if TAtlasWelcomeQuickActions.IsGroup(AProject) then
    begin
      mTarget := ActiveProjectOf(AProject);
    end;
    if mTarget = '' then
    begin
      mReason := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickReasonNotOpened);
    end
    else if not Assigned(Hooks.OnRun) then
    begin
      mReason := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickReasonNotOpened);
    end
    else if not Hooks.OnRun(mTarget, AProfile, mReason) and (mReason = '') then
    begin
      mReason := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickReasonSeeMessages);
    end;
  end;
  if mReason <> '' then
  begin
    Finish(AProject, TAtlasQuickAction.Run, TAtlasQuickActionPhase.Refused, mReason);
    Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickMsgRunRefused, [NameOf(AProject), mReason]));
    Exit;
  end;
  Finish(AProject, TAtlasQuickAction.Run, TAtlasQuickActionPhase.Succeeded, '');
end;

function TAtlasIdeQuickActions.TaskNames(const AProject: string): TArray<string>;
begin
  Result := nil;
  if not FStopped and Settings.TasksEnabled and Assigned(Hooks.OnTaskNames) then
  begin
    Result := Hooks.OnTaskNames(AProject);
  end;
end;

procedure TAtlasIdeQuickActions.RunTask(const AProject, AName: string);
var
  mReason: string;
begin
  if FStopped or not Enabled or State(AProject).Running then
  begin
    Exit;
  end;
  StartAction(AProject, TAtlasQuickAction.Tasks);
  mReason := '';
  // Vor dem Start eintragen: Ein sofort scheiternder Lauf meldet sein Ende schon im Start.
  FRuns.Tasks.AddOrSetValue(Key(AProject), AName);
  if not Assigned(Hooks.OnRunTask) then
  begin
    mReason := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickReasonTasksOff);
  end
  else if not Hooks.OnRunTask(AProject, AName, mReason) and (mReason = '') then
  begin
    mReason := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickReasonSeeMessages);
  end;
  if mReason = '' then
  begin
    Exit;
  end;
  FRuns.Tasks.Remove(Key(AProject));
  Finish(AProject, TAtlasQuickAction.Tasks, TAtlasQuickActionPhase.Refused, mReason);
  Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickMsgTaskRefused, [AName, NameOf(AProject), mReason]));
end;

procedure TAtlasIdeQuickActions.TaskFinished(const AProject: string; const AResult: TAtlasTaskResult);
var
  mName: string;
  mPhase: TAtlasQuickActionPhase;
begin
  if FStopped or not FRuns.Tasks.TryGetValue(Key(AProject), mName) or not SameText(mName, AResult.Name) then
  begin
    Exit;
  end;
  FRuns.Tasks.Remove(Key(AProject));
  if AResult.Passed then
  begin
    mPhase := TAtlasQuickActionPhase.Succeeded;
  end
  else
  begin
    mPhase := TAtlasQuickActionPhase.Failed;
  end;
  Finish(AProject, TAtlasQuickAction.Tasks, mPhase,
    TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickTasksResult,
    [AResult.Name, AResult.Summary]));
end;

procedure TAtlasIdeQuickActions.Pull(const AProject: string);
begin
  // Ohne Auswahl (Taste, Kontextmenü ohne Untermenü): „ask“ holt wie „with“ samt Externals.
  Pull(AProject, AtlasVcsExternalsUpdateOf(Settings.VcsExternalsUpdate) =
    TAtlasVcsExternalsUpdate.WithoutExternals);
end;

procedure TAtlasIdeQuickActions.Pull(const AProject: string; AIgnoreExternals: Boolean);
var
  mKeep: IInterface;
  mIgnore: Boolean;
  mProject, mDir: string;
  mVcs: TAtlasProjectVcs;
  mUpdate: Boolean;
  mOutcome: TAtlasPullOutcome;
  mReason: TAtlasVcsOutcome;
begin
  if FStopped or not Enabled or State(AProject).Running or (FProjects = nil) then
  begin
    Exit;
  end;
  mVcs := FProjects.VcsOf(AProject);
  mUpdate := TAtlasWelcomeQuickActions.IsUpdate(mVcs);
  // Der Knopf ist dann gesperrt; aus dem Kontextmenü bzw. der Taste noch einmal prüfen.
  if TAtlasWelcomeQuickActions.PullBlock(mVcs) = TAtlasPullBlock.LocalChanges then
  begin
    Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickMsgPullBlocked, [NameOf(AProject)]));
    Exit;
  end;
  StartAction(AProject, TAtlasQuickAction.Pull);
  mKeep := Self;
  mProject := AProject;
  mDir := ExtractFileDir(AProject);
  mOutcome := TAtlasPullOutcome.Failed;
  mReason := TAtlasVcsOutcome.Failed;
  mIgnore := AIgnoreExternals;
  // Arbeit und Ergebnis teilen sich Outcome und Reason; das Ergebnis kommt erst nach der Arbeit.
  if not TAtlasIdeVcs.Run(
    procedure
    begin
      mOutcome := TAtlasVcsPull.Pull(TAtlasIdeVcs.ForFolder(mDir,
        TAtlasIdeVcs.AtLeast(TAtlasWelcomeQuickActions.cPullTimeoutMs)), mIgnore, mReason);
    end,
    procedure
    begin
      if (mKeep = nil) or FStopped then
      begin
        Exit;
      end;
      SetState(mProject, PullResult(Self, mProject, mOutcome, mReason, mUpdate));
      // Branch, Rückstand und Änderungen frisch abfragen; „Projekte“ meldet sich danach selbst.
      if FProjects <> nil then
      begin
        FProjects.Refresh(mProject);
      end;
      Changed;
    end) then
  begin
    Finish(AProject, TAtlasQuickAction.Pull, TAtlasQuickActionPhase.Failed,
      TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickReasonVcsNotReady));
  end;
end;

procedure TAtlasIdeQuickActions.AppMessage(var Msg: TMsg; var Handled: Boolean);
var
  mControl: TWinControl;
  mShift: TShiftState;
  mPressed: TShortCut;
begin
  if (Msg.message <> WM_KEYDOWN) and (Msg.message <> WM_SYSKEYDOWN) then
  begin
    Exit;
  end;
  try
    if FStopped or not Enabled then
    begin
      Exit;
    end;
    mControl := FindControl(Msg.hwnd);
    if not (mControl is TAtlasQuickKeySink) then
    begin
      Exit;
    end;
    mShift := KeyDataToShiftState(Msg.lParam);
    mPressed := ShortCut(Word(Msg.wParam), mShift);
    if (mPressed = 0) or ((Integer(mPressed) <> BuildKey) and (Integer(mPressed) <> TestKey)) then
    begin
      Exit;
    end;
    // Vor den Tasten der IDE (Strg+B, Strg+T im Editor): nur in der Zeile mit dem Fokus.
    FInput.KeyAt := NowMs;
    Handled := TAtlasQuickKeySink(mControl).HandleKey(Word(Msg.wParam), mShift);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
  end;
end;

end.
