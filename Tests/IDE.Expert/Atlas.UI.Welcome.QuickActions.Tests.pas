unit Atlas.UI.Welcome.QuickActions.Tests;

// Schnellaktionen je Projekt auf der Willkommensseite (#764, Mockup #ws10):
// Knopfleiste der Bereiche „Projekte“ und „Weiterarbeiten“ mit einer
// Testquelle. Knöpfe nur in der aktiven Zeile und nur eingeschaltet, Liste
// aus welcomePage.quickActions.items, Klicks und Tasten erreichen die Quelle
// über die Nachrichtenschleife, ein gesperrter Pull tut nichts, die Auswahl
// (Konfiguration und Plattform, Startprofil, Testprojekt, Projektaufgabe
// #900), Texte von Knöpfen, Fortschritt und Ergebnis sowie das Kontextmenü.

interface

uses
  System.SysUtils,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Welcome.QuickActions,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.QuickActions,
  Atlas.UI.Welcome.Frame,
  DUnitX.TestFramework;

type
  /// <summary>Quelle der Knopfleiste für die Tests (auch für die Bereiche in Atlas.UI.Welcome.Tests); merkt sich
  /// die Aufrufe.</summary>
  TAtlasFakeQuickActions = class(TInterfacedObject, IAtlasQuickActionsSource)
  public
    IsOn: Boolean;
    Items: TAtlasQuickActions;
    Vcs: TAtlasProjectVcs;
    Busy: Boolean;
    /// <summary>vcs.externals.update = ask (#1292).</summary>
    AskExternals: Boolean;
    FState: TAtlasQuickActionState;
    FNowMs: UInt64;
    FTests: TArray<string>;
    FTaskNames: TArray<string>;
    Calls: TArray<string>;
    constructor Create;
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
    procedure Pull(const AProject: string; AIgnoreExternals: Boolean);
    function BuildKey: Integer;
    function TestKey: Integer;
    function ConsoleProgram: string;
  end;

  [TestFixture]
  TAtlasQuickActionsBarTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    /// <summary>Erste Benutzung (VCL, Menüs, Warteschlange) ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    /// <summary>Texte deutsch; danach die Sprache von vorher.</summary>
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ButtonsFollowSwitchAndItems;
    [Test]
    procedure ActiveRowFollowsMouse;
    [Test]
    procedure ClickReachesSourceQueued;
    [Test]
    procedure BlockedPullDoesNothing;
    [Test]
    procedure KeyboardWithoutMouse;
    [Test]
    procedure KeysOnlyForListedButtons;
    [Test]
    procedure ChoicesFollowSource;
    [Test]
    procedure CaptionsShowProgressAndResult;
    [Test]
    procedure EnglishTexts;
    [Test]
    procedure ContextMenuFollowsRow;
    [Test]
    procedure TasksChooseAndShowResult;
    /// <summary>#1292: „Aktualisieren ▾“ mit „mit Externals“/„ohne Externals“, im Kontextmenü als Untermenü;
    /// ohne ask wie bisher.</summary>
    [Test]
    procedure UpdateAsksForExternals;
  end;

implementation

uses
  System.Classes,
  System.Types,
  Winapi.Windows,
  Vcl.Graphics,
  Vcl.Forms,
  Vcl.Menus,
  Vcl.ExtCtrls;

const
  ProjectOne = 'C:\P\Eins.dproj';
  ProjectTwo = 'C:\P\Zwei.dproj';

{ TAtlasFakeQuickActions }

constructor TAtlasFakeQuickActions.Create;
begin
  inherited Create;
  IsOn := True;
  Items := [Low(TAtlasQuickAction)..High(TAtlasQuickAction)];
  Vcs := TAtlasProjectVcs.Empty;
  Vcs.Known := True;
  Vcs.Kind := 'git';
  Vcs.Branch := 'main';
  Vcs.Changed := 0;
  FState := TAtlasQuickActionState.Idle;
  FNowMs := 100000;
  FTaskNames := TArray<string>.Create('Delphi-12-Prüfung', 'Konfigurationsdoku');
end;

function TAtlasFakeQuickActions.Enabled: Boolean;
begin
  Result := IsOn;
end;

function TAtlasFakeQuickActions.Buttons(const AProject: string): TAtlasQuickActionButtons;
begin
  Result := TAtlasWelcomeQuickActions.Buttons(Items, Vcs, Busy);
  if AskExternals then
    TAtlasWelcomeQuickActions.AskExternals(Result);
end;

function TAtlasFakeQuickActions.State(const AProject: string): TAtlasQuickActionState;
begin
  Result := FState;
end;

function TAtlasFakeQuickActions.NowMs: UInt64;
begin
  Result := FNowMs;
end;

procedure TAtlasFakeQuickActions.Execute(const AProject: string; AAction: TAtlasQuickAction);
begin
  Calls := Calls + [TAtlasWelcomeQuickActions.Names[AAction] + ' ' + AProject];
end;

function TAtlasFakeQuickActions.Targets(const AProject: string; out AConfiguration,
  APlatform: string): TAtlasProjectTargets;
begin
  Result.Configurations := ['Debug', 'Release'];
  Result.Platforms := ['Win32', 'Win64'];
  AConfiguration := 'Debug';
  APlatform := 'Win64';
end;

procedure TAtlasFakeQuickActions.Build(const AProject, AConfiguration, APlatform: string);
begin
  Calls := Calls + ['build ' + AProject + ' ' + AConfiguration + ' ' + APlatform];
end;

function TAtlasFakeQuickActions.TestProjects(const AProject: string): TArray<string>;
begin
  Result := FTests;
end;

procedure TAtlasFakeQuickActions.RunTests(const AProject, ATestProject: string);
begin
  Calls := Calls + ['tests ' + AProject + ' ' + ATestProject];
end;

function TAtlasFakeQuickActions.Profiles(const AProject: string; out AActive: string): TArray<string>;
begin
  Result := ['Kunde', 'Leer'];
  AActive := 'Kunde';
end;

procedure TAtlasFakeQuickActions.Run(const AProject, AProfile: string);
begin
  Calls := Calls + ['run ' + AProject + ' ' + AProfile];
end;

function TAtlasFakeQuickActions.TaskNames(const AProject: string): TArray<string>;
begin
  Result := FTaskNames;
end;

procedure TAtlasFakeQuickActions.RunTask(const AProject, AName: string);
begin
  Calls := Calls + ['task ' + AProject + ' ' + AName];
end;

procedure TAtlasFakeQuickActions.Pull(const AProject: string; AIgnoreExternals: Boolean);
begin
  Calls := Calls + ['update ' + AProject + ' ' + BoolToStr(AIgnoreExternals, True)];
end;

function TAtlasFakeQuickActions.BuildKey: Integer;
begin
  Result := $4042;
end;

function TAtlasFakeQuickActions.TestKey: Integer;
begin
  Result := $4054;
end;

function TAtlasFakeQuickActions.ConsoleProgram: string;
begin
  Result := 'wt.exe';
end;

{ Hilfen }

type
  /// <summary>Leiste mit Zeichenfläche in einem Formular; gibt alles mit dem Formular frei.</summary>
  TBarHost = class
  public
    Host: TForm;
    Box: TAtlasWelcomeCanvas;
    Bar: TAtlasQuickActionsBar;
    Opened: TArray<Integer>;
    Selected: TArray<Integer>;
    constructor Create(const ASource: IAtlasQuickActionsSource);
    destructor Destroy; override;
    /// <summary>Knöpfe von ARow anordnen (wie beim Zeichnen); Mitte des Knopfs AIndex.</summary>
    function Center(ARow, AIndex: Integer): TPoint;
  end;

constructor TBarHost.Create(const ASource: IAtlasQuickActionsSource);
begin
  inherited Create;
  Host := TForm.CreateNew(nil);
  Host.SetBounds(0, 0, 800, 200);
  Box := TAtlasWelcomeCanvas.Create(Host);
  Box.Parent := Host;
  Box.SetBounds(0, 0, 800, 200);
  Bar := TAtlasQuickActionsBar.Create(Host, Box, Host);
  Bar.OnOpenRow :=
    procedure(ARow: Integer)
    begin
      Opened := Opened + [ARow];
    end;
  Bar.OnSelectRow :=
    procedure(ARow: Integer)
    begin
      Selected := Selected + [ARow];
    end;
  Bar.Source := ASource;
  Bar.SetRows([ProjectOne, ProjectTwo]);
end;

destructor TBarHost.Destroy;
begin
  Host.Free;
  inherited;
end;

function TBarHost.Center(ARow, AIndex: Integer): TPoint;
var
  Bitmap: TBitmap;
  X, Row, Index: Integer;
  Menu: Boolean;
begin
  Bitmap := TBitmap.Create;
  try
    Bitmap.SetSize(800, 100);
    Bar.LayoutRow(Bitmap.Canvas, ARow, Rect(200, ARow * 40, 790, ARow * 40 + 36));
  finally
    Bitmap.Free;
  end;
  // Linke Hälfte des Knopfs: „Öffnen und bauen“ ohne den Teil ▾.
  Result := Point(-1, -1);
  for X := 200 to 790 do
    if Bar.HitTest(X, ARow * 40 + 18, Row, Index, Menu) and (Row = ARow) and (Index = AIndex) and not Menu then
      Exit(Point(X + 2, ARow * 40 + 18));
end;

{ TAtlasQuickActionsBarTests }

procedure TAtlasQuickActionsBarTests.WarmUpFirstUse;
begin
  Setup;
  try
    try
      ButtonsFollowSwitchAndItems;
    except
      on Exception do
        ;
    end;
  finally
    TearDown;
  end;
  Setup;
  try
    try
      ActiveRowFollowsMouse;
    except
      on Exception do
        ;
    end;
  finally
    TearDown;
  end;
end;

procedure TAtlasQuickActionsBarTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasQuickActionsBarTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasQuickActionsBarTests.ButtonsFollowSwitchAndItems;
var
  Fake: TAtlasFakeQuickActions;
  Source: IAtlasQuickActionsSource;
  Host: TBarHost;
  Buttons: TAtlasQuickActionButtons;
begin
  Fake := TAtlasFakeQuickActions.Create;
  Source := Fake;
  Host := TBarHost.Create(Source);
  try
    Assert.IsTrue(Host.Bar.Active);
    Buttons := Host.Bar.ButtonsOf(0);
    Assert.AreEqual(7, Integer(Length(Buttons)), 'alle sieben Knöpfe');
    Assert.IsTrue(Buttons[0].Action = TAtlasQuickAction.Build);
    Assert.IsTrue(Buttons[5].Action = TAtlasQuickAction.Console);
    Assert.IsTrue(Buttons[6].Action = TAtlasQuickAction.Tasks);
    // items ohne console: nur dieser Knopf fehlt.
    Fake.Items := TAtlasWelcomeQuickActions.ParseItems('build,tests,run,pull,folder');
    Host.Bar.SetRows([ProjectOne, ProjectTwo]);
    Buttons := Host.Bar.ButtonsOf(0);
    Assert.AreEqual(5, Integer(Length(Buttons)));
    Assert.AreEqual(-1, TAtlasWelcomeQuickActions.IndexOf(Buttons, TAtlasQuickAction.Console));
    Assert.AreEqual(4, TAtlasWelcomeQuickActions.IndexOf(Buttons, TAtlasQuickAction.Folder));
    // Ausgeschaltet: keine Knöpfe, keine aktive Zeile, keine Tasten.
    Fake.IsOn := False;
    Host.Bar.SetRows([ProjectOne, ProjectTwo]);
    Assert.IsFalse(Host.Bar.Active);
    Assert.AreEqual(0, Integer(Length(Host.Bar.ButtonsOf(0))));
    Host.Bar.MouseMove(0, 10, 10);
    Assert.AreEqual(-1, Host.Bar.ActiveRow);
    Assert.IsFalse(Host.Bar.HandleKey(Ord('B'), [ssCtrl]), 'Strg+B bleibt bei der IDE');
    Assert.IsFalse(Host.Bar.Sink.TabStop, 'ausgeschaltet nicht per Tab erreichbar');
    // Ohne Quelle: ebenso nichts.
    Host.Bar.Source := nil;
    Assert.IsFalse(Host.Bar.Active);
    Assert.AreEqual(0, Integer(Length(Host.Bar.ButtonsOf(1))));
  finally
    Host.Free;
  end;
end;

procedure TAtlasQuickActionsBarTests.ActiveRowFollowsMouse;
var
  Source: IAtlasQuickActionsSource;
  Host: TBarHost;
begin
  Source := TAtlasFakeQuickActions.Create;
  Host := TBarHost.Create(Source);
  try
    Assert.AreEqual(-1, Host.Bar.ActiveRow, 'ohne Maus und Fokus keine Knopfleiste');
    Host.Bar.MouseMove(1, 10, 50);
    Assert.AreEqual(1, Host.Bar.ActiveRow);
    Host.Bar.MouseMove(0, 10, 10);
    Assert.AreEqual(0, Host.Bar.ActiveRow);
    Host.Bar.MouseLeave;
    Assert.AreEqual(-1, Host.Bar.ActiveRow);
    // Klick außerhalb der Knöpfe: Die Zeile klickt selbst.
    Host.Bar.MouseMove(0, 10, 10);
    Host.Center(0, 0);
    Assert.IsFalse(Host.Bar.ClickAt(10, 10));
  finally
    Host.Free;
  end;
end;

procedure TAtlasQuickActionsBarTests.ClickReachesSourceQueued;
var
  Fake: TAtlasFakeQuickActions;
  Source: IAtlasQuickActionsSource;
  Host: TBarHost;
  At: TPoint;
begin
  Fake := TAtlasFakeQuickActions.Create;
  Source := Fake;
  Fake.FTests := ['C:\P\Tests\Eins.Tests.dproj'];
  Host := TBarHost.Create(Source);
  try
    Host.Bar.MouseMove(1, 10, 50);
    At := Host.Center(1, 4);
    Assert.IsTrue(At.X > 0, 'Knopf „Ordner“ angeordnet');
    Assert.IsTrue(Host.Bar.ClickAt(At.X, At.Y));
    At := Host.Center(1, 0);
    Assert.IsTrue(Host.Bar.ClickAt(At.X, At.Y), '„Öffnen und bauen“');
    At := Host.Center(1, 1);
    Assert.IsTrue(Host.Bar.ClickAt(At.X, At.Y), '„Tests“ mit einem Testprojekt');
    Assert.AreEqual(0, Integer(Length(Fake.Calls)), 'alles über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(3, Integer(Length(Fake.Calls)));
    Assert.AreEqual('folder ' + ProjectTwo, Fake.Calls[0]);
    Assert.AreEqual('build ' + ProjectTwo, Fake.Calls[1]);
    Assert.AreEqual('tests ' + ProjectTwo, Fake.Calls[2]);
  finally
    Host.Free;
  end;
end;

procedure TAtlasQuickActionsBarTests.BlockedPullDoesNothing;
var
  Fake: TAtlasFakeQuickActions;
  Source: IAtlasQuickActionsSource;
  Host: TBarHost;
  Buttons: TAtlasQuickActionButtons;
  Pull: Integer;
begin
  Fake := TAtlasFakeQuickActions.Create;
  Source := Fake;
  Fake.Vcs.Changed := 2;
  Host := TBarHost.Create(Source);
  try
    Buttons := Host.Bar.ButtonsOf(0);
    Pull := TAtlasWelcomeQuickActions.IndexOf(Buttons, TAtlasQuickAction.Pull);
    Assert.IsFalse(Buttons[Pull].Enabled, 'lokale Änderungen sperren Pull');
    Host.Bar.Activate(0, Pull, False);
    CheckSynchronize;
    Assert.AreEqual(0, Integer(Length(Fake.Calls)));
    Assert.AreEqual('Erst lokale Änderungen sichern', TAtlasQuickActionsBar.ButtonHint(Buttons[Pull], False, 0, ''));
    // Ohne Änderungen holt Pull.
    Fake.Vcs.Changed := 0;
    Host.Bar.SetRows([ProjectOne, ProjectTwo]);
    Host.Bar.Activate(0, Pull, False);
    CheckSynchronize;
    Assert.AreEqual(1, Integer(Length(Fake.Calls)));
    Assert.AreEqual('pull ' + ProjectOne, Fake.Calls[0]);
    // Ein laufender Pull sperrt den Knopf ebenso.
    Fake.Busy := True;
    Host.Bar.SetRows([ProjectOne, ProjectTwo]);
    Assert.IsFalse(Host.Bar.ButtonsOf(0)[Pull].Enabled);
    Assert.IsTrue(Host.Bar.ButtonsOf(0)[4].Enabled, '„Ordner“ geht weiter');
  finally
    Host.Free;
  end;
end;

procedure TAtlasQuickActionsBarTests.KeyboardWithoutMouse;
var
  Fake: TAtlasFakeQuickActions;
  Source: IAtlasQuickActionsSource;
  Host: TBarHost;
begin
  Fake := TAtlasFakeQuickActions.Create;
  Source := Fake;
  Fake.FTests := ['C:\P\Tests\Zwei.Tests.dproj'];
  Host := TBarHost.Create(Source);
  try
    // Pfeil ab wählt die nächste Zeile, Enter ohne Knopf öffnet sie.
    Assert.IsTrue(Host.Bar.HandleKey(VK_DOWN, []));
    Assert.IsTrue(Host.Bar.HandleKey(VK_DOWN, []));
    Assert.AreEqual(1, Host.Bar.KeyRow, 'bleibt in der letzten Zeile');
    Assert.AreEqual(1, Integer(Length(Host.Selected)), 'nur ein Wechsel');
    Assert.IsTrue(Host.Bar.HandleKey(VK_RETURN, []));
    Assert.AreEqual(1, Integer(Length(Host.Opened)));
    Assert.AreEqual(1, Host.Opened[0]);
    // Strg+B und Strg+T auf der gewählten Zeile.
    Assert.IsTrue(Host.Bar.HandleKey(Ord('B'), [ssCtrl]));
    Assert.IsTrue(Host.Bar.HandleKey(Ord('T'), [ssCtrl]));
    // Pfeil rechts wählt Knöpfe, Enter führt aus, Pos1 geht zurück auf die Zeile.
    Assert.IsTrue(Host.Bar.HandleKey(VK_HOME, []));
    Assert.AreEqual(-1, Host.Bar.KeyButton);
    Assert.IsTrue(Host.Bar.HandleKey(VK_RIGHT, []));
    Assert.IsTrue(Host.Bar.HandleKey(VK_RIGHT, []));
    Assert.IsTrue(Host.Bar.HandleKey(VK_RIGHT, []));
    Assert.IsTrue(Host.Bar.HandleKey(VK_RIGHT, []));
    Assert.AreEqual(3, Host.Bar.KeyButton, 'Pull');
    Assert.IsTrue(Host.Bar.HandleKey(VK_RETURN, []));
    Assert.IsTrue(Host.Bar.HandleKey(VK_ESCAPE, []));
    Assert.AreEqual(-1, Host.Bar.KeyButton);
    Assert.IsFalse(Host.Bar.HandleKey(VK_ESCAPE, []), 'Escape ohne Knopf bleibt beim Bereich');
    Assert.AreEqual(0, Integer(Length(Fake.Calls)), 'alles über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(3, Integer(Length(Fake.Calls)));
    Assert.AreEqual('build ' + ProjectTwo, Fake.Calls[0]);
    Assert.AreEqual('tests ' + ProjectTwo, Fake.Calls[1]);
    Assert.AreEqual('pull ' + ProjectTwo, Fake.Calls[2]);
    // Pfeil auf zurück.
    Assert.IsTrue(Host.Bar.HandleKey(VK_UP, []));
    Assert.AreEqual(0, Host.Bar.KeyRow);
    Assert.IsFalse(Host.Bar.HandleKey(Ord('X'), [ssCtrl]), 'fremde Tasten bleiben bei der IDE');
  finally
    Host.Free;
  end;
end;

procedure TAtlasQuickActionsBarTests.KeysOnlyForListedButtons;
var
  Fake: TAtlasFakeQuickActions;
  Source: IAtlasQuickActionsSource;
  Host: TBarHost;
begin
  Fake := TAtlasFakeQuickActions.Create;
  Source := Fake;
  Fake.Items := TAtlasWelcomeQuickActions.ParseItems('build,folder');
  Host := TBarHost.Create(Source);
  try
    Assert.IsFalse(Host.Bar.HandleKey(Ord('T'), [ssCtrl]), 'ohne Knopf „Tests“ gehört Strg+T der IDE');
    Assert.IsTrue(Host.Bar.HandleKey(Ord('B'), [ssCtrl]));
    // Läuft in der IDE schon eine Aktion, nimmt die Leiste die Taste ab, führt aber nichts aus.
    Fake.Busy := True;
    Host.Bar.SetRows([ProjectOne, ProjectTwo]);
    Assert.IsTrue(Host.Bar.HandleKey(Ord('B'), [ssCtrl]));
    CheckSynchronize;
    Assert.AreEqual(1, Integer(Length(Fake.Calls)));
    Assert.AreEqual('build ' + ProjectOne, Fake.Calls[0]);
  finally
    Host.Free;
  end;
end;

procedure TAtlasQuickActionsBarTests.ChoicesFollowSource;
var
  Fake: TAtlasFakeQuickActions;
  Source: IAtlasQuickActionsSource;
  Host: TBarHost;
  Items: TMenuItem;
begin
  Fake := TAtlasFakeQuickActions.Create;
  Source := Fake;
  Host := TBarHost.Create(Source);
  try
    Items := Host.Bar.Menu.Items;
    // Konfiguration und Plattform: Überschrift, „wie in der IDE“, dann jede Kombination; zuletzt benutzt fett.
    Assert.IsTrue(Host.Bar.FillChoices(Items, 0, 0));
    Assert.AreEqual(7, Integer(Items.Count));
    Assert.AreEqual('Konfiguration und Plattform', StripHotkey(Items[0].Caption));
    Assert.IsFalse(Items[0].Enabled);
    Assert.AreEqual('Wie in der IDE eingestellt', StripHotkey(Items[2].Caption));
    Assert.AreEqual('Debug · Win64 (zuletzt)', StripHotkey(Items[4].Caption));
    Assert.IsTrue(Items[4].Default);
    Assert.AreEqual('Release · Win32', StripHotkey(Items[5].Caption));
    Items[4].Click;
    // Startprofile: das aktive markiert, „Ohne Startprofil“ zuletzt.
    Assert.IsTrue(Host.Bar.FillChoices(Items, 0, 2));
    Assert.AreEqual(5, Integer(Items.Count));
    Assert.AreEqual('Startprofil', StripHotkey(Items[0].Caption));
    Assert.AreEqual('Kunde (aktiv)', StripHotkey(Items[2].Caption));
    Assert.AreEqual('Ohne Startprofil', StripHotkey(Items[4].Caption));
    Items[3].Click;
    // Testprojekte: nur bei mehreren eine Auswahl.
    Fake.FTests := ['C:\P\Tests\Eins.Tests.dproj'];
    Assert.IsFalse(Host.Bar.FillChoices(Items, 0, 1));
    Fake.FTests := ['C:\P\Tests\Eins.Tests.dproj', 'C:\P\Test\EinsTest.dproj'];
    Assert.IsTrue(Host.Bar.FillChoices(Items, 0, 1));
    Assert.AreEqual(4, Integer(Items.Count));
    Assert.AreEqual('Testprojekt', StripHotkey(Items[0].Caption));
    Assert.AreEqual('EinsTest', StripHotkey(Items[3].Caption));
    Items[3].Click;
    // Ordner hat keine Auswahl.
    Assert.IsFalse(Host.Bar.FillChoices(Items, 0, 4));
    Assert.AreEqual(0, Integer(Length(Fake.Calls)), 'alles über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(3, Integer(Length(Fake.Calls)));
    Assert.AreEqual('build ' + ProjectOne + ' Debug Win64', Fake.Calls[0]);
    Assert.AreEqual('run ' + ProjectOne + ' Leer', Fake.Calls[1]);
    Assert.AreEqual('tests ' + ProjectOne + ' C:\P\Test\EinsTest.dproj', Fake.Calls[2]);
  finally
    Host.Free;
  end;
end;

procedure TAtlasQuickActionsBarTests.CaptionsShowProgressAndResult;
var
  Button: TAtlasQuickActionButton;
  State: TAtlasQuickActionState;
  Hint: string;
begin
  Button := Default(TAtlasQuickActionButton);
  Button.Action := TAtlasQuickAction.Build;
  Button.Enabled := True;
  State := TAtlasQuickActionState.Started(TAtlasQuickAction.Build, 1000);
  Assert.AreEqual('Öffnen und bauen', TAtlasQuickActionsBar.Caption(Button, TAtlasQuickActionState.Idle, 0));
  Assert.AreEqual('baut … 12 s', TAtlasQuickActionsBar.Caption(Button, State, 13500), 'Fortschritt im Knopf');
  Assert.AreEqual('baut … 12 s', TAtlasQuickActionsBar.StateText(State, 13500, False));
  // Gebaut: Die Marke „Build 0/0/0“ zeigt das Ergebnis, keine eigene Marke.
  State.Phase := TAtlasQuickActionPhase.Succeeded;
  Assert.AreEqual('', TAtlasQuickActionsBar.StateText(State, 13500, False));
  State.Phase := TAtlasQuickActionPhase.Refused;
  Assert.AreEqual('nicht gebaut', TAtlasQuickActionsBar.StateText(State, 13500, False));
  State.Action := TAtlasQuickAction.Tests;
  State.Phase := TAtlasQuickActionPhase.Succeeded;
  State.Passed := 412;
  Assert.AreEqual('Tests: 412 ok', TAtlasQuickActionsBar.StateText(State, 0, False));
  State.Phase := TAtlasQuickActionPhase.Failed;
  State.Failed := 2;
  Assert.AreEqual('Tests: 2 fehlgeschlagen', TAtlasQuickActionsBar.StateText(State, 0, False));
  State.Failed := 0;
  Assert.AreEqual('Tests nicht gelaufen', TAtlasQuickActionsBar.StateText(State, 0, False));
  State.Action := TAtlasQuickAction.Pull;
  State.Phase := TAtlasQuickActionPhase.Running;
  State.StartedMs := 1000;
  Assert.AreEqual('aktualisiert … 2 s', TAtlasQuickActionsBar.StateText(State, 3000, True), 'SVN');
  State.Phase := TAtlasQuickActionPhase.Failed;
  State.Pull := TAtlasPullOutcome.Blocked;
  Assert.AreEqual('Pull gesperrt', TAtlasQuickActionsBar.StateText(State, 0, False));
  State.Phase := TAtlasQuickActionPhase.Succeeded;
  State.Pull := TAtlasPullOutcome.UpToDate;
  Assert.AreEqual('aktuell', TAtlasQuickActionsBar.StateText(State, 0, False));
  Button.Action := TAtlasQuickAction.Pull;
  Button.Update := True;
  Assert.AreEqual('Aktualisieren', TAtlasQuickActionsBar.Caption(Button, TAtlasQuickActionState.Idle, 0));
  // Tooltip mit Taste (Name der Taste je Windows-Sprache) bzw. Programm der Konsole.
  Button.Action := TAtlasQuickAction.Build;
  Button.Update := False;
  Hint := TAtlasQuickActionsBar.ButtonHint(Button, False, $4042, '');
  Assert.IsTrue(Hint.EndsWith(sLineBreak + 'Taste: ' + ShortCutToText($4042)), Hint);
  Button.Action := TAtlasQuickAction.Console;
  Assert.AreEqual('Konsole im Projektordner öffnen (wt.exe).', TAtlasQuickActionsBar.ButtonHint(Button, False, 0, ''));
  Button.Enabled := False;
  Button.Action := TAtlasQuickAction.Tests;
  Assert.AreEqual('In der IDE läuft schon eine Schnellaktion', TAtlasQuickActionsBar.ButtonHint(Button, False, 0, ''));
  Assert.AreEqual('Auf dem Projekt läuft schon eine Schnellaktion', TAtlasQuickActionsBar.ButtonHint(Button, True, 0,
    ''));
end;

procedure TAtlasQuickActionsBarTests.EnglishTexts;
var
  Button: TAtlasQuickActionButton;
  State: TAtlasQuickActionState;
begin
  TAtlasStrings.Language := TAtlasLanguage.English;
  Button := Default(TAtlasQuickActionButton);
  Button.Action := TAtlasQuickAction.Build;
  Assert.AreEqual('Open and build', TAtlasQuickActionsBar.Caption(Button, TAtlasQuickActionState.Idle, 0));
  Button.Action := TAtlasQuickAction.Pull;
  Button.Block := TAtlasPullBlock.LocalChanges;
  Assert.AreEqual('Save local changes first', TAtlasQuickActionsBar.ButtonHint(Button, False, 0, ''));
  State := TAtlasQuickActionState.Started(TAtlasQuickAction.Tests, 1000);
  Assert.AreEqual('testing … 4 s', TAtlasQuickActionsBar.StateText(State, 5000, False));
end;

procedure TAtlasQuickActionsBarTests.ContextMenuFollowsRow;
var
  Fake: TAtlasFakeQuickActions;
  Source: IAtlasQuickActionsSource;
  Host: TBarHost;
  Menu: TPopupMenu;
  Index: Integer;
  Visible: TArray<string>;
begin
  Fake := TAtlasFakeQuickActions.Create;
  Source := Fake;
  Fake.Items := TAtlasWelcomeQuickActions.ParseItems('build,run,pull,folder');
  Fake.Vcs.Kind := 'svn';
  Host := TBarHost.Create(Source);
  try
    Menu := TPopupMenu.Create(Host.Host);
    Host.Bar.AttachMenu(Menu);
    Host.Bar.PrepareMenu(1);
    Visible := nil;
    for Index := 0 to Menu.Items.Count - 1 do
      if Menu.Items[Index].Visible then
        Visible := Visible + [StripHotkey(Menu.Items[Index].Caption)];
    // Ohne „Tests“ und „Konsole“; SVN: „Aktualisieren“.
    Assert.AreEqual(5, Integer(Length(Visible)));
    Assert.AreEqual('-', Visible[0]);
    Assert.AreEqual('Öffnen und bauen', Visible[1]);
    Assert.AreEqual('Bauen mit', Visible[2]);
    Assert.AreEqual('Starten mit', Visible[3]);
    Assert.AreEqual('Aktualisieren', Visible[4]);
    for Index := 0 to Menu.Items.Count - 1 do
      if StripHotkey(Menu.Items[Index].Caption) = 'Aktualisieren' then
        Menu.Items[Index].Click;
    CheckSynchronize;
    Assert.AreEqual(1, Integer(Length(Fake.Calls)));
    Assert.AreEqual('pull ' + ProjectTwo, Fake.Calls[0]);
    // Ausgeschaltet: keine Einträge.
    Fake.IsOn := False;
    Host.Bar.SetRows([ProjectOne, ProjectTwo]);
    Host.Bar.PrepareMenu(0);
    for Index := 0 to Menu.Items.Count - 1 do
      Assert.IsFalse(Menu.Items[Index].Visible, Menu.Items[Index].Caption);
  finally
    Host.Free;
  end;
end;

procedure TAtlasQuickActionsBarTests.UpdateAsksForExternals;
var
  mFake: TAtlasFakeQuickActions;
  mSource: IAtlasQuickActionsSource;
  mHost: TBarHost;
  mMenu: TPopupMenu;
  mItems, mUpdate: TMenuItem;
  mIndex, mPull: Integer;
begin
  mFake := TAtlasFakeQuickActions.Create;
  mSource := mFake;
  mFake.Items := TAtlasWelcomeQuickActions.ParseItems('pull,folder');
  mFake.Vcs.Kind := 'svn';
  mFake.AskExternals := True;
  mHost := TBarHost.Create(mSource);
  try
    mPull := TAtlasWelcomeQuickActions.IndexOf(mHost.Bar.ButtonsOf(0), TAtlasQuickAction.Pull);
    Assert.AreEqual('Aktualisieren ' + #$25BE, TAtlasQuickActionsBar.Caption(mHost.Bar.ButtonsOf(0)[mPull],
      TAtlasQuickActionState.Idle, 0));
    mItems := mHost.Bar.Menu.Items;
    Assert.IsTrue(mHost.Bar.FillChoices(mItems, 0, mPull));
    Assert.AreEqual(4, Integer(mItems.Count));
    Assert.AreEqual('Aktualisieren', StripHotkey(mItems[0].Caption));
    Assert.AreEqual('mit Externals', StripHotkey(mItems[2].Caption));
    Assert.IsTrue(mItems[2].Default);
    Assert.AreEqual('ohne Externals', StripHotkey(mItems[3].Caption));
    mItems[3].Click;
    CheckSynchronize;
    Assert.AreEqual(1, Integer(Length(mFake.Calls)));
    Assert.AreEqual('update ' + ProjectOne + ' True', mFake.Calls[0]);
    // Kontextmenü: „Aktualisieren“ als Untermenü.
    mMenu := TPopupMenu.Create(mHost.Host);
    mHost.Bar.AttachMenu(mMenu);
    mHost.Bar.PrepareMenu(1);
    mUpdate := nil;
    for mIndex := 0 to mMenu.Items.Count - 1 do
      if mMenu.Items[mIndex].Visible and (StripHotkey(mMenu.Items[mIndex].Caption) = 'Aktualisieren') then
        mUpdate := mMenu.Items[mIndex];
    Assert.IsNotNull(mUpdate);
    Assert.AreEqual(2, Integer(mUpdate.Count));
    mUpdate[0].Click;
    CheckSynchronize;
    Assert.AreEqual('update ' + ProjectTwo + ' False', mFake.Calls[1]);
    // Ohne ask: einfacher Eintrag, Knopf holt sofort.
    mFake.AskExternals := False;
    mHost.Bar.SetRows([ProjectOne, ProjectTwo]);
    mHost.Bar.PrepareMenu(1);
    Assert.AreEqual(0, Integer(mUpdate.Count));
    Assert.IsFalse(mHost.Bar.FillChoices(mItems, 0, mPull));
    mHost.Bar.Activate(0, mPull, False);
    CheckSynchronize;
    Assert.AreEqual('pull ' + ProjectOne, mFake.Calls[2]);
  finally
    mHost.Free;
  end;
  mFake.Calls := nil;
end;

procedure TAtlasQuickActionsBarTests.TasksChooseAndShowResult;
var
  Fake: TAtlasFakeQuickActions;
  Source: IAtlasQuickActionsSource;
  Host: TBarHost;
  Items: TMenuItem;
  Menu: TPopupMenu;
  Index: Integer;
  Button: TAtlasQuickActionButton;
  State: TAtlasQuickActionState;
begin
  Fake := TAtlasFakeQuickActions.Create;
  Source := Fake;
  Fake.Items := [TAtlasQuickAction.Folder, TAtlasQuickAction.Tasks];
  Host := TBarHost.Create(Source);
  try
    // „Aufgaben ▾“: Überschrift, dann die Aufgaben der atlas.json in ihrer Reihenfolge.
    Items := Host.Bar.Menu.Items;
    Assert.IsTrue(Host.Bar.ButtonsOf(0)[1].HasMenu);
    Assert.IsTrue(Host.Bar.FillChoices(Items, 0, 1));
    Assert.AreEqual(4, Integer(Items.Count));
    Assert.AreEqual('Projektaufgabe', StripHotkey(Items[0].Caption));
    Assert.AreEqual('Delphi-12-Prüfung', StripHotkey(Items[2].Caption));
    Assert.AreEqual('Konfigurationsdoku', StripHotkey(Items[3].Caption));
    Items[3].Click;
    CheckSynchronize;
    Assert.AreEqual(1, Integer(Length(Fake.Calls)));
    Assert.AreEqual('task ' + ProjectOne + ' Konfigurationsdoku', Fake.Calls[0]);
    // Kontextmenü: Untermenü „Aufgabe ausführen“ ohne Überschrift.
    Menu := TPopupMenu.Create(Host.Host);
    Host.Bar.AttachMenu(Menu);
    Host.Bar.PrepareMenu(1);
    Items := nil;
    for Index := 0 to Menu.Items.Count - 1 do
      if StripHotkey(Menu.Items[Index].Caption) = 'Aufgabe ausführen' then
        Items := Menu.Items[Index];
    Assert.IsNotNull(Items);
    Assert.IsTrue(Items.Visible);
    Assert.AreEqual(2, Integer(Items.Count));
    Items[0].Click;
    CheckSynchronize;
    Assert.AreEqual('task ' + ProjectTwo + ' Delphi-12-Prüfung', Fake.Calls[1]);
    // Ohne Aufgaben keine Auswahl.
    Fake.FTaskNames := nil;
    Assert.IsFalse(Host.Bar.FillChoices(Host.Bar.Menu.Items, 0, 1));
    Host.Bar.PrepareMenu(0);
    Assert.IsFalse(Items.Visible);
  finally
    Host.Free;
  end;
  // Texte: Knopf, Fortschritt, Ergebnis aus der IDE-Schicht, nicht gestartet, Tooltip.
  Button := Default(TAtlasQuickActionButton);
  Button.Action := TAtlasQuickAction.Tasks;
  Button.Enabled := True;
  Assert.AreEqual('Aufgaben ▾', TAtlasQuickActionsBar.Caption(Button, TAtlasQuickActionState.Idle, 0));
  State := TAtlasQuickActionState.Started(TAtlasQuickAction.Tasks, 1000);
  Assert.AreEqual('Aufgabe … 3 s', TAtlasQuickActionsBar.Caption(Button, State, 4200));
  State.Phase := TAtlasQuickActionPhase.Failed;
  State.Detail := 'Delphi-12-Prüfung: 2 Fehler 14:03';
  Assert.AreEqual('Delphi-12-Prüfung: 2 Fehler 14:03', TAtlasQuickActionsBar.StateText(State, 0, False));
  State.Phase := TAtlasQuickActionPhase.Refused;
  Assert.AreEqual('Aufgabe nicht gestartet', TAtlasQuickActionsBar.StateText(State, 0, False));
  Assert.IsTrue(TAtlasQuickActionsBar.ButtonHint(Button, False, 0, '').Contains('Atlas-Aufgaben'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasQuickActionsBarTests);

end.
