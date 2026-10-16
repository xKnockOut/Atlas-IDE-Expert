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
//   danach fragt „Projekte“ Branch und Änderungen neu ab.
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
  private
    FMessage: TProc<string>;
    FProjects: TAtlasIdeProjects;
    FStopped: Boolean;
    // Normierter Pfad → Stand der letzten Schnellaktion.
    FStates: TDictionary<string, TAtlasQuickActionState>;
    // Normiertes Testprojekt → Projekt der Zeile, deren Tests laufen.
    FTests: TDictionary<string, string>;
    FWatch: TTimer;
    FEvents: TApplicationEvents;
    FKeyAt: UInt64;
    FOnBuild: TAtlasQuickBuildFunc;
    FOnTests: TAtlasQuickTestsFunc;
    FOnTestsBusy: TFunc<Boolean>;
    FOnIdeBusy: TFunc<Boolean>;
    FOnProfiles: TAtlasQuickProfilesFunc;
    FOnRun: TAtlasQuickRunFunc;
    procedure Changed;
    procedure Report(const AText: string);
    function Key(const AProject: string): string;
    procedure SetState(const AProject: string; const AState: TAtlasQuickActionState);
    procedure StartAction(const AProject: string; AAction: TAtlasQuickAction);
    procedure Finish(const AProject: string; AAction: TAtlasQuickAction; APhase: TAtlasQuickActionPhase;
      const ADetail: string);
    function IdeBusy(const AProject: string): Boolean;
    function EnsureOpen(const AProject: string; out AReason: string): Boolean;
    procedure BuildNext(const ARow: string; const AProjects: TArray<string>; AIndex: Integer;
      const AConfiguration, APlatform: string);
    procedure Pull(const AProject: string);
    procedure OpenConsole(const AProject: string);
    procedure CountUse(const AId: string);
    procedure WatchTick(Sender: TObject);
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
    class function NameOf(const AProject: string): string; static;
    class function ProjectOpen(const AFileName: string): Boolean; static;
    class function GroupMembers(const AGroup: string): TArray<string>; static;
    class function ActiveProjectOf(const AGroup: string): string; static;
  public
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
    procedure TestsFinished(const ATestProject: string; const ATests: TAtlasProjectTests);
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
    function BuildKey: Integer;
    function TestKey: Integer;
    function ConsoleProgram: string;
    property OnBuild: TAtlasQuickBuildFunc read FOnBuild write FOnBuild;
    property OnTests: TAtlasQuickTestsFunc read FOnTests write FOnTests;
    /// <summary>Läuft ein Testlauf (auch der Build davor)?</summary>
    property OnTestsBusy: TFunc<Boolean> read FOnTestsBusy write FOnTestsBusy;
    /// <summary>Ist die IDE schon mit einem Build oder Testlauf beschäftigt (auch nicht von hier)?</summary>
    property OnIdeBusy: TFunc<Boolean> read FOnIdeBusy write FOnIdeBusy;
    property OnProfiles: TAtlasQuickProfilesFunc read FOnProfiles write FOnProfiles;
    property OnRun: TAtlasQuickRunFunc read FOnRun write FOnRun;
  end;

implementation

uses
  Winapi.Messages,
  Winapi.ShellAPI,
  System.Classes,
  System.IOUtils,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Menus,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Welcome.Sections,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Vcs.Service,
  Atlas.IDE.Commands.ShortcutTips;

function Settings: TAtlasPluginSettings;
begin
  Result := TAtlasIdeSettings.Current;
end;

function ReadLines(const AFileName: string; out ALines: TArray<string>): Boolean;
begin
  ALines := nil;
  try
    ALines := TFile.ReadAllLines(AFileName);
    Result := True;
  except
    // Nicht lesbar: zählt wie nicht vorhanden.
    on Exception do
      Result := False;
  end;
end;

{ TAtlasIdeQuickActions }

constructor TAtlasIdeQuickActions.Create(AProjects: TAtlasIdeProjects; const AMessage: TProc<string>);
begin
  inherited Create;
  FProjects := AProjects;
  FMessage := AMessage;
  FStates := TDictionary<string, TAtlasQuickActionState>.Create;
  FTests := TDictionary<string, string>.Create;
end;

destructor TAtlasIdeQuickActions.Destroy;
begin
  Stop;
  FTests.Free;
  FStates.Free;
  inherited;
end;

procedure TAtlasIdeQuickActions.Start;
begin
  FStopped := False;
  if FEvents = nil then
  begin
    FEvents := TApplicationEvents.Create(nil);
    FEvents.OnMessage := AppMessage;
  end;
  if FWatch = nil then
  begin
    FWatch := TTimer.Create(nil);
    FWatch.Enabled := False;
    FWatch.Interval := WatchMs;
    FWatch.OnTimer := WatchTick;
  end;
end;

procedure TAtlasIdeQuickActions.Stop;
begin
  FStopped := True;
  FreeAndNil(FEvents);
  FreeAndNil(FWatch);
  FProjects := nil;
  FOnBuild := nil;
  FOnTests := nil;
  FOnTestsBusy := nil;
  FOnIdeBusy := nil;
  FOnProfiles := nil;
  FOnRun := nil;
end;

procedure TAtlasIdeQuickActions.Refresh;
begin
  Changed;
end;

procedure TAtlasIdeQuickActions.Changed;
begin
  if FStopped then
    Exit;
  TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.Projects);
  TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.Continue);
end;

procedure TAtlasIdeQuickActions.Report(const AText: string);
begin
  if Assigned(FMessage) then
    FMessage(AText);
end;

function TAtlasIdeQuickActions.Key(const AProject: string): string;
begin
  Result := TAtlasProjectSummaries.NormalizedPath(AProject);
end;

class function TAtlasIdeQuickActions.NameOf(const AProject: string): string;
begin
  Result := ChangeFileExt(ExtractFileName(AProject), '');
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
  if not FStates.TryGetValue(Key(AProject), Result) then
    Result := TAtlasQuickActionState.Idle;
end;

procedure TAtlasIdeQuickActions.SetState(const AProject: string; const AState: TAtlasQuickActionState);
begin
  FStates.AddOrSetValue(Key(AProject), AState);
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
    Exit;
  Value := State(AProject);
  Value.Action := AAction;
  Value.Phase := APhase;
  Value.Detail := ADetail;
  SetState(AProject, Value);
  Changed;
end;

function TAtlasIdeQuickActions.IdeBusy(const AProject: string): Boolean;
var
  Pair: TPair<string, TAtlasQuickActionState>;
  Own: string;
begin
  // Die IDE öffnet immer nur ein Projekt zur Zeit: eine laufende Aktion eines anderen Projekts sperrt.
  Own := Key(AProject);
  for Pair in FStates do
    if (Pair.Key <> Own) and Pair.Value.Running and TAtlasWelcomeQuickActions.UsesIde(Pair.Value.Action) then
      Exit(True);
  Result := Assigned(FOnIdeBusy) and FOnIdeBusy();
end;

function TAtlasIdeQuickActions.Buttons(const AProject: string): TAtlasQuickActionButtons;
var
  Items: TAtlasQuickActions;
  Vcs: TAtlasProjectVcs;
begin
  Result := nil;
  if not Enabled or (FProjects = nil) then
    Exit;
  Items := TAtlasWelcomeQuickActions.ParseItems(Settings.WelcomePageQuickActionsItems);
  // Ohne „Tests ausführen“ (#69) gibt es keinen Läufer: kein Knopf.
  if not Settings.TestRun then
    Exclude(Items, TAtlasQuickAction.Tests);
  Vcs := FProjects.VcsOf(AProject);
  Result := TAtlasWelcomeQuickActions.Buttons(Items, Vcs, State(AProject).Running, IdeBusy(AProject));
end;

class function TAtlasIdeQuickActions.ProjectOpen(const AFileName: string): Boolean;
var
  Modules: IOTAModuleServices;
begin
  Result := Supports(BorlandIDEServices, IOTAModuleServices, Modules) and (Modules.FindModule(AFileName) <> nil);
end;

class function TAtlasIdeQuickActions.GroupMembers(const AGroup: string): TArray<string>;
var
  Modules: IOTAModuleServices;
  Group: IOTAProjectGroup;
  Index: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) or
    not Supports(Modules.FindModule(AGroup), IOTAProjectGroup, Group) then
    Exit;
  for Index := 0 to Group.ProjectCount - 1 do
    if (Group.Projects[Index] <> nil) and (Group.Projects[Index].FileName <> '') then
      Result := Result + [Group.Projects[Index].FileName];
end;

class function TAtlasIdeQuickActions.ActiveProjectOf(const AGroup: string): string;
var
  Modules: IOTAModuleServices;
  Group: IOTAProjectGroup;
begin
  Result := '';
  if Supports(BorlandIDEServices, IOTAModuleServices, Modules) and
    Supports(Modules.FindModule(AGroup), IOTAProjectGroup, Group) and (Group.ActiveProject <> nil) then
    Result := Group.ActiveProject.FileName;
end;

function TAtlasIdeQuickActions.EnsureOpen(const AProject: string; out AReason: string): Boolean;
var
  Actions: IOTAActionServices;
begin
  AReason := '';
  if ProjectOpen(AProject) then
    Exit(True);
  if not FileExists(AProject) then
  begin
    AReason := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickReasonMissing);
    Exit(False);
  end;
  // Wie „Öffnen“ der IDE: Eine neue Gruppe fragt nach dem Speichern der offenen; Abbrechen lässt sie offen.
  if Supports(BorlandIDEServices, IOTAActionServices, Actions) then
    Actions.OpenProject(AProject, True);
  Result := ProjectOpen(AProject);
  if not Result then
    AReason := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickReasonNotOpened);
end;

procedure TAtlasIdeQuickActions.CountUse(const AId: string);
begin
  // Über die Taste: zählt die Beobachtung der Tastatur (#600) schon.
  if NowMs - FKeyAt < KeyUseMs then
    Exit;
  TAtlasIdeShortcutTips.Invoked(AId);
end;

procedure TAtlasIdeQuickActions.Execute(const AProject: string; AAction: TAtlasQuickAction);
var
  Configuration, Platform: string;
  Candidates: TArray<string>;
begin
  if FStopped or not Enabled then
    Exit;
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
          CountUse(TestsCommandId);
          SetState(AProject, TAtlasQuickActionState.Started(TAtlasQuickAction.Tests, NowMs));
          Finish(AProject, TAtlasQuickAction.Tests, TAtlasQuickActionPhase.Refused,
            TAtlasStrings.Text(TAtlasTextId.WelcomeQuickReasonNoTestProject));
          Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickMsgNoTestProject, [NameOf(AProject)]));
        end
        else
          // Mehrere: Die Leiste fragt vorher; ohne Auswahl (etwa aus dem Kontextmenü) das erste.
          RunTests(AProject, Candidates[0]);
      end;
    TAtlasQuickAction.Run:
      Run(AProject, '');
    TAtlasQuickAction.Pull:
      Pull(AProject);
    TAtlasQuickAction.Folder:
      if FProjects <> nil then
        FProjects.OpenFolder(AProject);
    TAtlasQuickAction.Console:
      OpenConsole(AProject);
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
    Exit;
  try
    Text := TFile.ReadAllText(AProject);
  except
    on Exception do
      Exit;
  end;
  Result := TAtlasWelcomeQuickActions.ReadTargets(Text);
  // Vorgabe: zuletzt benutzt (Abschnitt "build" der Zusammenfassung), wenn das Projekt sie noch kennt.
  if TAtlasProjectSummaries.Load(TAtlasIdeProjects.Folder, AProject, Summary) and Summary.Build.Known then
    TAtlasWelcomeQuickActions.ChooseTarget(Result, Summary.Build.Configuration, Summary.Build.Platform,
      AConfiguration, APlatform);
end;

procedure TAtlasIdeQuickActions.Build(const AProject, AConfiguration, APlatform: string);
var
  Reason: string;
  List: TArray<string>;
begin
  if FStopped or not Enabled or State(AProject).Running then
    Exit;
  CountUse(BuildCommandId);
  StartAction(AProject, TAtlasQuickAction.Build);
  if not EnsureOpen(AProject, Reason) then
  begin
    Finish(AProject, TAtlasQuickAction.Build, TAtlasQuickActionPhase.Refused, Reason);
    Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickMsgBuildRefused, [NameOf(AProject), Reason]));
    Exit;
  end;
  List := [AProject];
  if TAtlasWelcomeQuickActions.IsGroup(AProject) then
    List := GroupMembers(AProject);
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
  if not Assigned(FOnBuild) or not FOnBuild(Projects[Index], Configuration, Platform,
    procedure(ASucceeded: Boolean; const AError: string)
    begin
      // Keep hält die Quelle bis hierher am Leben.
      if (Keep = nil) or FStopped then
        Exit;
      if AError <> '' then
      begin
        Finish(Row, TAtlasQuickAction.Build, TAtlasQuickActionPhase.Refused, AError);
        Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickMsgBuildRefused, [NameOf(Projects[Index]), AError]));
      end
      else if not ASucceeded then
        Finish(Row, TAtlasQuickAction.Build, TAtlasQuickActionPhase.Failed, '')
      else if Index < High(Projects) then
        // Nächstes Projekt der Gruppe nicht im Rückruf des Läufers: Er schließt seinen Auftrag erst danach ab.
        TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
          procedure
          begin
            if (Keep <> nil) and not FStopped then
              BuildNext(Row, Projects, Index + 1, Configuration, Platform);
          end)
      else
        Finish(Row, TAtlasQuickAction.Build, TAtlasQuickActionPhase.Succeeded, '');
    end, Reason) then
  begin
    Finish(Row, TAtlasQuickAction.Build, TAtlasQuickActionPhase.Refused, Reason);
    Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickMsgBuildRefused, [NameOf(Projects[Index]), Reason]));
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
    Result := [Found]
  else
    Result := Candidates;
end;

procedure TAtlasIdeQuickActions.RunTests(const AProject, ATestProject: string);
var
  Reason: string;
  Actions: IOTAActionServices;
begin
  if FStopped or not Enabled or State(AProject).Running then
    Exit;
  CountUse(TestsCommandId);
  StartAction(AProject, TAtlasQuickAction.Tests);
  Reason := '';
  if EnsureOpen(AProject, Reason) and not ProjectOpen(ATestProject) then
  begin
    // Testprojekt außerhalb der Gruppe: in die offene Gruppe aufnehmen (wie „Projekt hinzufügen“).
    if not FileExists(ATestProject) then
      Reason := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickReasonMissing)
    else
    begin
      if Supports(BorlandIDEServices, IOTAActionServices, Actions) then
        Actions.OpenProject(ATestProject, False);
      if not ProjectOpen(ATestProject) then
        Reason := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickReasonNotOpened);
    end;
  end;
  if (Reason = '') and not Assigned(FOnTests) then
    Reason := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickReasonTestsOff);
  // Vor dem Start eintragen: Das Ergebnis (TestsFinished) findet so die Zeile in jedem Fall.
  if Reason = '' then
    FTests.AddOrSetValue(Key(ATestProject), AProject);
  if (Reason = '') and not FOnTests(ATestProject, Reason) and (Reason = '') then
    Reason := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickReasonSeeMessages);
  if Reason <> '' then
  begin
    FTests.Remove(Key(ATestProject));
    Finish(AProject, TAtlasQuickAction.Tests, TAtlasQuickActionPhase.Refused, Reason);
    Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickMsgTestsRefused, [NameOf(AProject), Reason]));
    Exit;
  end;
  // Ohne Ergebnis endet der Lauf, wenn der Läufer nicht mehr beschäftigt ist (WatchTick).
  if FTests.ContainsKey(Key(ATestProject)) and (FWatch <> nil) then
    FWatch.Enabled := True;
end;

procedure TAtlasIdeQuickActions.TestsFinished(const ATestProject: string; const ATests: TAtlasProjectTests);
var
  Row: string;
  Value: TAtlasQuickActionState;
begin
  if FStopped or not FTests.TryGetValue(Key(ATestProject), Row) then
    Exit;
  FTests.Remove(Key(ATestProject));
  Value := State(Row);
  Value.Action := TAtlasQuickAction.Tests;
  Value.Passed := ATests.Passed;
  Value.Failed := ATests.Failed + ATests.Errors;
  Value.Detail := '';
  if Value.Failed > 0 then
    Value.Phase := TAtlasQuickActionPhase.Failed
  else
    Value.Phase := TAtlasQuickActionPhase.Succeeded;
  SetState(Row, Value);
  Changed;
end;

procedure TAtlasIdeQuickActions.WatchTick(Sender: TObject);
var
  Pair: TPair<string, string>;
  Ended: TArray<string>;
  Ending, Row: string;
  Value: TAtlasQuickActionState;
begin
  try
    if FStopped or (FTests.Count = 0) then
    begin
      if FWatch <> nil then
        FWatch.Enabled := False;
      Exit;
    end;
    // Läuft nichts mehr und kam kein Ergebnis: Der Läufer hat abgelehnt oder abgebrochen (Grund in der
    // Meldungsansicht).
    if Assigned(FOnTestsBusy) and FOnTestsBusy() then
      Exit;
    Ended := nil;
    for Pair in FTests do
    begin
      Value := State(Pair.Value);
      if not Value.Running or (NowMs - Value.StartedMs >= WatchGraceMs) then
        Ended := Ended + [Pair.Key];
    end;
    for Ending in Ended do
    begin
      if FTests.TryGetValue(Ending, Row) and State(Row).Running then
        Finish(Row, TAtlasQuickAction.Tests, TAtlasQuickActionPhase.Failed,
          TAtlasStrings.Text(TAtlasTextId.WelcomeQuickReasonSeeMessages));
      FTests.Remove(Ending);
    end;
    if (FTests.Count = 0) and (FWatch <> nil) then
      FWatch.Enabled := False;
  except
    on E: Exception do
    begin
      if FWatch <> nil then
        FWatch.Enabled := False;
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
    end;
  end;
end;

function TAtlasIdeQuickActions.Profiles(const AProject: string; out AActive: string): TArray<string>;
begin
  Result := nil;
  AActive := '';
  // Eine Gruppe startet ihr aktives Projekt mit dessen Auswahl (erst nach dem Öffnen bekannt).
  if TAtlasWelcomeQuickActions.IsGroup(AProject) or not Assigned(FOnProfiles) then
    Exit;
  Result := FOnProfiles(AProject, AActive);
end;

procedure TAtlasIdeQuickActions.Run(const AProject, AProfile: string);
var
  Reason, Target: string;
begin
  if FStopped or not Enabled or State(AProject).Running then
    Exit;
  StartAction(AProject, TAtlasQuickAction.Run);
  Target := '';
  if EnsureOpen(AProject, Reason) then
  begin
    Target := AProject;
    if TAtlasWelcomeQuickActions.IsGroup(AProject) then
      Target := ActiveProjectOf(AProject);
    if Target = '' then
      Reason := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickReasonNotOpened)
    else if not Assigned(FOnRun) then
      Reason := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickReasonNotOpened)
    else if not FOnRun(Target, AProfile, Reason) and (Reason = '') then
      Reason := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickReasonSeeMessages);
  end;
  if Reason <> '' then
  begin
    Finish(AProject, TAtlasQuickAction.Run, TAtlasQuickActionPhase.Refused, Reason);
    Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickMsgRunRefused, [NameOf(AProject), Reason]));
    Exit;
  end;
  Finish(AProject, TAtlasQuickAction.Run, TAtlasQuickActionPhase.Succeeded, '');
end;

procedure TAtlasIdeQuickActions.Pull(const AProject: string);
var
  Keep: IInterface;
  Project, Dir: string;
  Vcs: TAtlasProjectVcs;
  Update: Boolean;
  Outcome: TAtlasPullOutcome;
  Reason: TAtlasVcsOutcome;
begin
  if FStopped or not Enabled or State(AProject).Running or (FProjects = nil) then
    Exit;
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
  // Arbeit und Ergebnis teilen sich Outcome und Reason; das Ergebnis kommt erst nach der Arbeit.
  if not TAtlasIdeVcs.Run(
    procedure
    begin
      Outcome := TAtlasWelcomeQuickActions.Pull(TAtlasIdeVcs.ForFolder(Dir,
        TAtlasWelcomeQuickActions.PullTimeoutMs), Reason);
    end,
    procedure
    var
      Value: TAtlasQuickActionState;
    begin
      if (Keep = nil) or FStopped then
        Exit;
      Value := State(Project);
      Value.Action := TAtlasQuickAction.Pull;
      Value.Pull := Outcome;
      Value.Detail := '';
      case Outcome of
        TAtlasPullOutcome.Updated, TAtlasPullOutcome.UpToDate:
          Value.Phase := TAtlasQuickActionPhase.Succeeded;
        TAtlasPullOutcome.Blocked:
          begin
            Value.Phase := TAtlasQuickActionPhase.Failed;
            Value.Detail := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickPullLocalChanges);
            Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickMsgPullBlocked, [NameOf(Project)]));
          end;
        TAtlasPullOutcome.NoWorkingCopy:
          begin
            Value.Phase := TAtlasQuickActionPhase.Failed;
            Value.Detail := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickPullNoWorkingCopy);
          end;
      else
        begin
          Value.Phase := TAtlasQuickActionPhase.Failed;
          Value.Detail := AtlasVcsOutcomeName(Reason);
          if Update then
            Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickMsgUpdateFailed, [NameOf(Project),
              AtlasVcsOutcomeName(Reason)]))
          else
            Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickMsgPullFailed, [NameOf(Project),
              AtlasVcsOutcomeName(Reason)]));
        end;
      end;
      SetState(Project, Value);
      // Branch, Rückstand und Änderungen frisch abfragen; „Projekte“ meldet sich danach selbst.
      if FProjects <> nil then
        FProjects.Refresh(Project);
      Changed;
    end) then
    Finish(AProject, TAtlasQuickAction.Pull, TAtlasQuickActionPhase.Failed,
      TAtlasStrings.Text(TAtlasTextId.WelcomeQuickReasonVcsNotReady));
end;

procedure TAtlasIdeQuickActions.OpenConsole(const AProject: string);
var
  Program_, Dir, FileName, Parameters: string;
  Started: Boolean;

  function Launch(const AProgram: string): Boolean;
  begin
    Result := TAtlasWelcomeQuickActions.ConsoleCommand(AProgram, Dir, FileName, Parameters) and
      (ShellExecute(0, 'open', PChar(FileName), PChar(Parameters), PChar(Dir), SW_SHOWNORMAL) > 32);
  end;

begin
  Program_ := ConsoleProgram;
  Dir := ExtractFileDir(AProject);
  Started := DirectoryExists(Dir) and Launch(Program_);
  // Ohne Windows-Terminal: cmd.exe (nur für die Vorgabe; ein eigenes Programm meldet seinen Fehler).
  if not Started and DirectoryExists(Dir) and SameText(Program_, TAtlasWelcomeQuickActions.DefaultConsole) then
    Started := Launch(TAtlasWelcomeQuickActions.FallbackConsole);
  if Started then
    Exit;
  SetState(AProject, TAtlasQuickActionState.Started(TAtlasQuickAction.Console, NowMs));
  Finish(AProject, TAtlasQuickAction.Console, TAtlasQuickActionPhase.Failed, '');
  Report(TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickMsgConsoleFailed, [Program_]));
end;

procedure TAtlasIdeQuickActions.AppMessage(var Msg: TMsg; var Handled: Boolean);
var
  Control: TWinControl;
  Shift: TShiftState;
  Pressed: TShortCut;
begin
  if (Msg.message <> WM_KEYDOWN) and (Msg.message <> WM_SYSKEYDOWN) then
    Exit;
  try
    if FStopped or not Enabled then
      Exit;
    Control := FindControl(Msg.hwnd);
    if not (Control is TAtlasQuickKeySink) then
      Exit;
    Shift := KeyDataToShiftState(Msg.lParam);
    Pressed := ShortCut(Word(Msg.wParam), Shift);
    if (Pressed = 0) or ((Integer(Pressed) <> BuildKey) and (Integer(Pressed) <> TestKey)) then
      Exit;
    // Vor den Tasten der IDE (Strg+B, Strg+T im Editor): nur in der Zeile mit dem Fokus.
    FKeyAt := NowMs;
    Handled := TAtlasQuickKeySink(Control).HandleKey(Word(Msg.wParam), Shift);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
  end;
end;

end.
