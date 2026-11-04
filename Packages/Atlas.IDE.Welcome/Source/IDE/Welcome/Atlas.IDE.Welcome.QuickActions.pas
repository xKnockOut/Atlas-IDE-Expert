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
  Atlas.Core.Projects.Summary,
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
    WatchMs = 500;
    /// <summary>So lange nach dem Start gilt ein Testlauf ohne Busy noch nicht als beendet.</summary>
    WatchGraceMs = 1500;
    /// <summary>So lange nach Strg+B bzw. Strg+T zählt ein Aufruf nicht als Mausklick.</summary>
    KeyUseMs = 1000;
    BuildCommandId = 'Atlas.WelcomeQuickBuild';
    TestsCommandId = 'Atlas.WelcomeQuickTests';
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
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Pull,
  Atlas.Core.Welcome.Sections,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Vcs.Service,
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
  Pair: TPair<string, TAtlasQuickActionState>;
  Own: string;
begin
  // Die IDE öffnet immer nur ein Projekt zur Zeit: eine laufende Aktion eines anderen Projekts sperrt.
  Own := Key(AProject);
  for Pair in ASelf.FRuns.States do
  begin
    if (Pair.Key <> Own) and Pair.Value.Running and TAtlasWelcomeQuickActions.UsesIde(Pair.Value.Action) then
    begin
      Exit(True);
    end;
  end;
  Result := Assigned(ASelf.Hooks.OnIdeBusy) and ASelf.Hooks.OnIdeBusy();
end;

function ProjectOpen(const AFileName: string): Boolean;
var
  Modules: IOTAModuleServices;
begin
  Result := Supports(BorlandIDEServices, IOTAModuleServices, Modules) and (Modules.FindModule(AFileName) <> nil);
end;

function GroupMembers(const AGroup: string): TArray<string>;
var
  Modules: IOTAModuleServices;
  Group: IOTAProjectGroup;
  Index: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) or
    not Supports(Modules.FindModule(AGroup), IOTAProjectGroup, Group) then
  begin
    Exit;
  end;
  for Index := 0 to Group.ProjectCount - 1 do
  begin
    if (Group.Projects[Index] <> nil) and (Group.Projects[Index].FileName <> '') then
    begin
      Result := Result + [Group.Projects[Index].FileName];
    end;
  end;
end;

function ActiveProjectOf(const AGroup: string): string;
var
  Modules: IOTAModuleServices;
  Group: IOTAProjectGroup;
begin
  Result := '';
  if Supports(BorlandIDEServices, IOTAModuleServices, Modules) and
    Supports(Modules.FindModule(AGroup), IOTAProjectGroup, Group) and (Group.ActiveProject <> nil) then
  begin
    Result := Group.ActiveProject.FileName;
  end;
end;

function EnsureOpen(const AProject: string; out AReason: string): Boolean;
var
  Actions: IOTAActionServices;
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
  if Supports(BorlandIDEServices, IOTAActionServices, Actions) then
  begin
    Actions.OpenProject(AProject, True);
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
  if ASelf.NowMs - ASelf.FInput.KeyAt < TAtlasIdeQuickActions.KeyUseMs then
  begin
    Exit;
  end;
  TAtlasIdeShortcutTips.Invoked(AId);
end;

procedure OpenConsole(ASelf: TAtlasIdeQuickActions; const AProject: string);
var
  Program_, Dir, FileName, Parameters: string;
  Started: Boolean;

  function Launch(const AProgram: string): Boolean;
  begin
    Result := TAtlasWelcomeQuickActions.ConsoleCommand(AProgram, Dir, FileName, Parameters) and
      (ShellExecute(0, 'open', PChar(FileName), PChar(Parameters), PChar(Dir), SW_SHOWNORMAL) > 32);
  end;

begin
  Program_ := ASelf.ConsoleProgram;
  Dir := ExtractFileDir(AProject);
  Started := DirectoryExists(Dir) and Launch(Program_);
  // Ohne Windows-Terminal: cmd.exe (nur für die Vorgabe; ein eigenes Programm meldet seinen Fehler).
  if not Started and DirectoryExists(Dir) and SameText(Program_, TAtlasWelcomeQuickActions.DefaultConsole) then
  begin
    Started := Launch(TAtlasWelcomeQuickActions.FallbackConsole);
  end;
  if Started then
  begin
    Exit;
  end;
  ASelf.SetState(AProject, TAtlasQuickActionState.Started(TAtlasQuickAction.Console, ASelf.NowMs));
  ASelf.Finish(AProject, TAtlasQuickAction.Console, TAtlasQuickActionPhase.Failed, '');
  ASelf.Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickMsgConsoleFailed, [Program_]));
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
    mActions.OpenProject(ATestProject, False);
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
  mValue: TAtlasQuickActionState;
begin
  Result := nil;
  for mPair in ASelf.FRuns.Tests do
  begin
    mValue := ASelf.State(mPair.Value);
    if not mValue.Running or (ASelf.NowMs - mValue.StartedMs >= TAtlasIdeQuickActions.WatchGraceMs) then
    begin
      Result := Result + [mPair.Key];
    end;
  end;
end;

/// <summary>Stand nach einem Pull mit Meldung bei Fehlern; AUpdate: SVN („Aktualisieren“).</summary>
function PullResult(ASelf: TAtlasIdeQuickActions; const AProject: string; AOutcome: TAtlasPullOutcome;
  AReason: TAtlasVcsOutcome; AUpdate: Boolean): TAtlasQuickActionState;
begin
  Result := ASelf.State(AProject);
  Result.Action := TAtlasQuickAction.Pull;
  Result.Pull := AOutcome;
  Result.Detail := '';
  Result.Phase := TAtlasQuickActionPhase.Failed;
  case AOutcome of
    TAtlasPullOutcome.Updated, TAtlasPullOutcome.UpToDate:
      Result.Phase := TAtlasQuickActionPhase.Succeeded;
    TAtlasPullOutcome.Blocked:
      begin
        Result.Detail := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickPullLocalChanges);
        ASelf.Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickMsgPullBlocked, [NameOf(AProject)]));
      end;
    TAtlasPullOutcome.NoWorkingCopy:
      Result.Detail := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickPullNoWorkingCopy);
  else
    // Fehlende Anmeldung (#1287): Ursache und Weg zur Seite Versionsverwaltung statt eines Codes.
    if AReason = TAtlasVcsOutcome.LoginNeeded then
    begin
      Result.Detail := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickPullLogin);
      ASelf.Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickMsgPullLogin, [NameOf(AProject)]));
    end
    else
    begin
      Result.Detail := AtlasVcsOutcomeName(AReason);
      ASelf.Report(PullFailedText(AProject, AReason, AUpdate));
    end;
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
    FInput.Watch.Interval := WatchMs;
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
  TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.Projects);
  TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.Continue);
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
  Value: TAtlasQuickActionState;
begin
  if FStopped then
  begin
    Exit;
  end;
  Value := State(AProject);
  Value.Action := AAction;
  Value.Phase := APhase;
  Value.Detail := ADetail;
  SetState(AProject, Value);
  Changed;
end;

function TAtlasIdeQuickActions.Buttons(const AProject: string): TAtlasQuickActionButtons;
var
  Items: TAtlasQuickActions;
  Vcs: TAtlasProjectVcs;
begin
  Result := nil;
  if not Enabled or (FProjects = nil) then
  begin
    Exit;
  end;
  Items := TAtlasWelcomeQuickActions.ParseItems(Settings.WelcomePageQuickActionsItems);
  // Ohne „Tests ausführen“ (#69) gibt es keinen Läufer: kein Knopf.
  if not Settings.TestRun then
  begin
    Exclude(Items, TAtlasQuickAction.Tests);
  end;
  // „Aufgaben ▾“ nur mit eingeschalteten Projektaufgaben (#900) und Aufgaben im Projekt.
  if (TAtlasQuickAction.Tasks in Items) and (not Settings.TasksEnabled or (Length(TaskNames(AProject)) = 0)) then
  begin
    Exclude(Items, TAtlasQuickAction.Tasks);
  end;
  Vcs := FProjects.VcsOf(AProject);
  Result := TAtlasWelcomeQuickActions.Buttons(Items, Vcs, State(AProject).Running, IdeBusy(Self, AProject));
  // vcs.externals.update = ask (#1292): „Aktualisieren ▾“ mit Auswahl.
  if AtlasVcsExternalsUpdateOf(Settings.VcsExternalsUpdate) = TAtlasVcsExternalsUpdate.Ask then
  begin
    TAtlasWelcomeQuickActions.AskExternals(Result);
  end;
end;

procedure TAtlasIdeQuickActions.Execute(const AProject: string; AAction: TAtlasQuickAction);
var
  Configuration, Platform: string;
  Candidates, Names: TArray<string>;
begin
  if FStopped or not Enabled then
  begin
    Exit;
  end;
  case AAction of
    TAtlasQuickAction.Build:
      begin
        Targets(AProject, Configuration, Platform);
        Build(AProject, Configuration, Platform);
      end;
    TAtlasQuickAction.Tests:
      begin
        Candidates := TestProjects(AProject);
        if Length(Candidates) = 0 then
        begin
          CountUse(Self, TestsCommandId);
          SetState(AProject, TAtlasQuickActionState.Started(TAtlasQuickAction.Tests, NowMs));
          Finish(AProject, TAtlasQuickAction.Tests, TAtlasQuickActionPhase.Refused,
            TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickReasonNoTestProject));
          Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickMsgNoTestProject, [NameOf(AProject)]));
        end
        else
        begin
          // Mehrere: Die Leiste fragt vorher; ohne Auswahl (etwa aus dem Kontextmenü) das erste.
          RunTests(AProject, Candidates[0]);
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
        Names := TaskNames(AProject);
        if Length(Names) > 0 then
        begin
          RunTask(AProject, Names[0]);
        end;
      end;
  end;
end;

function TAtlasIdeQuickActions.Targets(const AProject: string; out AConfiguration,
  APlatform: string): TAtlasProjectTargets;
var
  Summary: TAtlasProjectSummary;
  Text: string;
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
    Text := TAtlasTextFile.LoadText(AProject);
  except
    on Exception do
      Exit;
  end;
  Result := TAtlasWelcomeQuickActions.ReadTargets(Text);
  // Vorgabe: zuletzt benutzt (Abschnitt "build" der Zusammenfassung), wenn das Projekt sie noch kennt.
  if TAtlasProjectSummaries.Load(TAtlasIdeProjectSummaries.Folder, AProject, Summary) and Summary.Build.Known then
  begin
    TAtlasWelcomeQuickActions.ChooseTarget(Result, Summary.Build.Configuration, Summary.Build.Platform,
      AConfiguration, APlatform);
  end;
end;

procedure TAtlasIdeQuickActions.Build(const AProject, AConfiguration, APlatform: string);
var
  Reason: string;
  List: TArray<string>;
begin
  if FStopped or not Enabled or State(AProject).Running then
  begin
    Exit;
  end;
  CountUse(Self, BuildCommandId);
  StartAction(AProject, TAtlasQuickAction.Build);
  if not EnsureOpen(AProject, Reason) then
  begin
    Finish(AProject, TAtlasQuickAction.Build, TAtlasQuickActionPhase.Refused, Reason);
    Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickMsgBuildRefused, [NameOf(AProject), Reason]));
    Exit;
  end;
  List := [AProject];
  if TAtlasWelcomeQuickActions.IsGroup(AProject) then
  begin
    List := GroupMembers(AProject);
  end;
  if Length(List) = 0 then
  begin
    Finish(AProject, TAtlasQuickAction.Build, TAtlasQuickActionPhase.Succeeded, '');
    Exit;
  end;
  BuildNext(AProject, List, 0, AConfiguration, APlatform);
end;

procedure TAtlasIdeQuickActions.BuildNext(const ARow: string; const AProjects: TArray<string>; AIndex: Integer;
  const AConfiguration, APlatform: string);
var
  Row, Configuration, Platform, Reason: string;
  Projects: TArray<string>;
  Index: Integer;
  Keep: IInterface;
begin
  Row := ARow;
  Projects := AProjects;
  Index := AIndex;
  Configuration := AConfiguration;
  Platform := APlatform;
  Keep := Self;
  Reason := TAtlasStrings.Text(TAtlasTextId.TestsNoBuildRunner);
  if not Assigned(Hooks.OnBuild) or not Hooks.OnBuild(Projects[Index], Configuration, Platform,
    procedure(ASucceeded: Boolean; const AError: string)
    begin
      // Keep hält die Quelle bis hierher am Leben.
      if (Keep = nil) or FStopped then
      begin
        Exit;
      end;
      if AError <> '' then
      begin
        Finish(Row, TAtlasQuickAction.Build, TAtlasQuickActionPhase.Refused, AError);
        Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickMsgBuildRefused,
          [NameOf(Projects[Index]), AError]));
      end
      else if not ASucceeded then
      begin
        Finish(Row, TAtlasQuickAction.Build, TAtlasQuickActionPhase.Failed, '');
      end
      else if Index < High(Projects) then
      begin
        // Nächstes Projekt der Gruppe nicht im Rückruf des Läufers: Er schließt seinen Auftrag erst danach ab.
        TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
          procedure
          begin
            if (Keep <> nil) and not FStopped then
            begin
              BuildNext(Row, Projects, Index + 1, Configuration, Platform);
            end;
          end);
      end
      else
      begin
        Finish(Row, TAtlasQuickAction.Build, TAtlasQuickActionPhase.Succeeded, '');
      end;
    end, Reason) then
  begin
    Finish(Row, TAtlasQuickAction.Build, TAtlasQuickActionPhase.Refused, Reason);
    Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickMsgBuildRefused,
      [NameOf(Projects[Index]), Reason]));
  end;
end;

function TAtlasIdeQuickActions.TestProjects(const AProject: string): TArray<string>;
var
  Found: string;
  Candidates: TArray<string>;
begin
  Found := TAtlasWelcomeQuickActions.TestProjectFor(AProject,
    function(const AFileName: string): Boolean
    begin
      Result := FileExists(AFileName);
    end,
    function(const AFileName: string; out ALines: TArray<string>): Boolean
    begin
      Result := ReadLines(AFileName, ALines);
    end, Candidates);
  if Found <> '' then
  begin
    Result := [Found];
  end
  else
  begin
    Result := Candidates;
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
  CountUse(Self, TestsCommandId);
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
  Row: string;
  Value: TAtlasQuickActionState;
begin
  if FStopped or not FRuns.Tests.TryGetValue(Key(ATestProject), Row) then
  begin
    Exit;
  end;
  FRuns.Tests.Remove(Key(ATestProject));
  Value := State(Row);
  Value.Action := TAtlasQuickAction.Tests;
  Value.Passed := APassed;
  Value.Failed := AFailed;
  Value.Detail := '';
  if Value.Failed > 0 then
  begin
    Value.Phase := TAtlasQuickActionPhase.Failed;
  end
  else
  begin
    Value.Phase := TAtlasQuickActionPhase.Succeeded;
  end;
  SetState(Row, Value);
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
  Reason, Target: string;
begin
  if FStopped or not Enabled or State(AProject).Running then
  begin
    Exit;
  end;
  StartAction(AProject, TAtlasQuickAction.Run);
  Target := '';
  if EnsureOpen(AProject, Reason) then
  begin
    Target := AProject;
    if TAtlasWelcomeQuickActions.IsGroup(AProject) then
    begin
      Target := ActiveProjectOf(AProject);
    end;
    if Target = '' then
    begin
      Reason := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickReasonNotOpened);
    end
    else if not Assigned(Hooks.OnRun) then
    begin
      Reason := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickReasonNotOpened);
    end
    else if not Hooks.OnRun(Target, AProfile, Reason) and (Reason = '') then
    begin
      Reason := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickReasonSeeMessages);
    end;
  end;
  if Reason <> '' then
  begin
    Finish(AProject, TAtlasQuickAction.Run, TAtlasQuickActionPhase.Refused, Reason);
    Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickMsgRunRefused, [NameOf(AProject), Reason]));
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
  Reason: string;
begin
  if FStopped or not Enabled or State(AProject).Running then
  begin
    Exit;
  end;
  StartAction(AProject, TAtlasQuickAction.Tasks);
  Reason := '';
  // Vor dem Start eintragen: Ein sofort scheiternder Lauf meldet sein Ende schon im Start.
  FRuns.Tasks.AddOrSetValue(Key(AProject), AName);
  if not Assigned(Hooks.OnRunTask) then
  begin
    Reason := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickReasonTasksOff);
  end
  else if not Hooks.OnRunTask(AProject, AName, Reason) and (Reason = '') then
  begin
    Reason := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickReasonSeeMessages);
  end;
  if Reason = '' then
  begin
    Exit;
  end;
  FRuns.Tasks.Remove(Key(AProject));
  Finish(AProject, TAtlasQuickAction.Tasks, TAtlasQuickActionPhase.Refused, Reason);
  Report(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickMsgTaskRefused, [AName, NameOf(AProject), Reason]));
end;

procedure TAtlasIdeQuickActions.TaskFinished(const AProject: string; const AResult: TAtlasTaskResult);
var
  Name: string;
  Phase: TAtlasQuickActionPhase;
begin
  if FStopped or not FRuns.Tasks.TryGetValue(Key(AProject), Name) or not SameText(Name, AResult.Name) then
  begin
    Exit;
  end;
  FRuns.Tasks.Remove(Key(AProject));
  if AResult.Passed then
  begin
    Phase := TAtlasQuickActionPhase.Succeeded;
  end
  else
  begin
    Phase := TAtlasQuickActionPhase.Failed;
  end;
  Finish(AProject, TAtlasQuickAction.Tasks, Phase, TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickTasksResult,
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
  Keep: IInterface;
  mIgnore: Boolean;
  Project, Dir: string;
  Vcs: TAtlasProjectVcs;
  Update: Boolean;
  Outcome: TAtlasPullOutcome;
  Reason: TAtlasVcsOutcome;
begin
  if FStopped or not Enabled or State(AProject).Running or (FProjects = nil) then
  begin
    Exit;
  end;
  Vcs := FProjects.VcsOf(AProject);
  Update := TAtlasWelcomeQuickActions.IsUpdate(Vcs);
  // Der Knopf ist dann gesperrt; aus dem Kontextmenü bzw. der Taste noch einmal prüfen.
  if TAtlasWelcomeQuickActions.PullBlock(Vcs) = TAtlasPullBlock.LocalChanges then
  begin
    Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickMsgPullBlocked, [NameOf(AProject)]));
    Exit;
  end;
  StartAction(AProject, TAtlasQuickAction.Pull);
  Keep := Self;
  Project := AProject;
  Dir := ExtractFileDir(AProject);
  Outcome := TAtlasPullOutcome.Failed;
  Reason := TAtlasVcsOutcome.Failed;
  mIgnore := AIgnoreExternals;
  // Arbeit und Ergebnis teilen sich Outcome und Reason; das Ergebnis kommt erst nach der Arbeit.
  if not TAtlasIdeVcs.Run(
    procedure
    begin
      Outcome := TAtlasVcsPull.Pull(TAtlasIdeVcs.ForFolder(Dir,
        TAtlasIdeVcs.AtLeast(TAtlasWelcomeQuickActions.PullTimeoutMs)), mIgnore, Reason);
    end,
    procedure
    begin
      if (Keep = nil) or FStopped then
      begin
        Exit;
      end;
      SetState(Project, PullResult(Self, Project, Outcome, Reason, Update));
      // Branch, Rückstand und Änderungen frisch abfragen; „Projekte“ meldet sich danach selbst.
      if FProjects <> nil then
      begin
        FProjects.Refresh(Project);
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
  Control: TWinControl;
  Shift: TShiftState;
  Pressed: TShortCut;
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
    Control := FindControl(Msg.hwnd);
    if not (Control is TAtlasQuickKeySink) then
    begin
      Exit;
    end;
    Shift := KeyDataToShiftState(Msg.lParam);
    Pressed := ShortCut(Word(Msg.wParam), Shift);
    if (Pressed = 0) or ((Integer(Pressed) <> BuildKey) and (Integer(Pressed) <> TestKey)) then
    begin
      Exit;
    end;
    // Vor den Tasten der IDE (Strg+B, Strg+T im Editor): nur in der Zeile mit dem Fokus.
    FInput.KeyAt := NowMs;
    Handled := TAtlasQuickKeySink(Control).HandleKey(Word(Msg.wParam), Shift);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
  end;
end;

end.
