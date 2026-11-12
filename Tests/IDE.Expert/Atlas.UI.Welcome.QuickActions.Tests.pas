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
  [Category('Atlas.IDE.Welcome')]
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
  Atlas.UI.Welcome.Frame,
  System.Classes,
  System.Types,
  Winapi.Windows,
  Vcl.Graphics,
  Vcl.Forms,
  Vcl.Menus,
  Vcl.ExtCtrls,
  Atlas.Core.VersionControl.Pull;

const
  cProjectOne = 'C:\P\Eins.dproj';
  cProjectTwo = 'C:\P\Zwei.dproj';

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
  begin
    TAtlasWelcomeQuickActions.AskExternals(Result);
  end;
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
  Calls := Calls + [TAtlasWelcomeQuickActions.cNames[AAction] + ' ' + AProject];
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
  Bar.SetRows([cProjectOne, cProjectTwo]);
end;

destructor TBarHost.Destroy;
begin
  Host.Free;
  inherited;
end;

function TBarHost.Center(ARow, AIndex: Integer): TPoint;
var
  mBitmap: TBitmap;
  X, mRow, mIndex: Integer;
  mMenu: Boolean;
begin
  mBitmap := TBitmap.Create;
  try
    mBitmap.SetSize(800, 100);
    Bar.LayoutRow(mBitmap.Canvas, ARow, Rect(200, ARow * 40, 790, ARow * 40 + 36));
  finally
    mBitmap.Free;
  end;
  // Linke Hälfte des Knopfs: „Öffnen und bauen“ ohne den Teil ▾.
  Result := Point(-1, -1);
  for X := 200 to 790 do
  begin
    if Bar.HitTest(X, ARow * 40 + 18, mRow, mIndex, mMenu) and (mRow = ARow) and (mIndex = AIndex) and not mMenu then
    begin
      Exit(Point(X + 2, ARow * 40 + 18));
    end;
  end;
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
  mFake: TAtlasFakeQuickActions;
  mSource: IAtlasQuickActionsSource;
  mHost: TBarHost;
  mButtons: TAtlasQuickActionButtons;
begin
  mFake := TAtlasFakeQuickActions.Create;
  mSource := mFake;
  mHost := TBarHost.Create(mSource);
  try
    Assert.IsTrue(mHost.Bar.Active);
    mButtons := mHost.Bar.ButtonsOf(0);
    Assert.AreEqual(7, Integer(Length(mButtons)), 'alle sieben Knöpfe');
    Assert.IsTrue(mButtons[0].Action = TAtlasQuickAction.Build);
    Assert.IsTrue(mButtons[5].Action = TAtlasQuickAction.Console);
    Assert.IsTrue(mButtons[6].Action = TAtlasQuickAction.Tasks);
    // items ohne console: nur dieser Knopf fehlt.
    mFake.Items := TAtlasWelcomeQuickActions.ParseItems('build,tests,run,pull,folder');
    mHost.Bar.SetRows([cProjectOne, cProjectTwo]);
    mButtons := mHost.Bar.ButtonsOf(0);
    Assert.AreEqual(5, Integer(Length(mButtons)));
    Assert.AreEqual(-1, TAtlasWelcomeQuickActions.IndexOf(mButtons, TAtlasQuickAction.Console));
    Assert.AreEqual(4, TAtlasWelcomeQuickActions.IndexOf(mButtons, TAtlasQuickAction.Folder));
    // Ausgeschaltet: keine Knöpfe, keine aktive Zeile, keine Tasten.
    mFake.IsOn := False;
    mHost.Bar.SetRows([cProjectOne, cProjectTwo]);
    Assert.IsFalse(mHost.Bar.Active);
    Assert.AreEqual(0, Integer(Length(mHost.Bar.ButtonsOf(0))));
    mHost.Bar.MouseMove(0, 10, 10);
    Assert.AreEqual(-1, mHost.Bar.ActiveRow);
    Assert.IsFalse(mHost.Bar.HandleKey(Ord('B'), [ssCtrl]), 'Strg+B bleibt bei der IDE');
    Assert.IsFalse(mHost.Bar.Sink.TabStop, 'ausgeschaltet nicht per Tab erreichbar');
    // Ohne Quelle: ebenso nichts.
    mHost.Bar.Source := nil;
    Assert.IsFalse(mHost.Bar.Active);
    Assert.AreEqual(0, Integer(Length(mHost.Bar.ButtonsOf(1))));
  finally
    mHost.Free;
  end;
end;

procedure TAtlasQuickActionsBarTests.ActiveRowFollowsMouse;
var
  mSource: IAtlasQuickActionsSource;
  mHost: TBarHost;
begin
  mSource := TAtlasFakeQuickActions.Create;
  mHost := TBarHost.Create(mSource);
  try
    Assert.AreEqual(-1, mHost.Bar.ActiveRow, 'ohne Maus und Fokus keine Knopfleiste');
    mHost.Bar.MouseMove(1, 10, 50);
    Assert.AreEqual(1, mHost.Bar.ActiveRow);
    mHost.Bar.MouseMove(0, 10, 10);
    Assert.AreEqual(0, mHost.Bar.ActiveRow);
    mHost.Bar.MouseLeave;
    Assert.AreEqual(-1, mHost.Bar.ActiveRow);
    // Klick außerhalb der Knöpfe: Die Zeile klickt selbst.
    mHost.Bar.MouseMove(0, 10, 10);
    mHost.Center(0, 0);
    Assert.IsFalse(mHost.Bar.ClickAt(10, 10));
  finally
    mHost.Free;
  end;
end;

procedure TAtlasQuickActionsBarTests.ClickReachesSourceQueued;
var
  mFake: TAtlasFakeQuickActions;
  mSource: IAtlasQuickActionsSource;
  mHost: TBarHost;
  mAt: TPoint;
begin
  mFake := TAtlasFakeQuickActions.Create;
  mSource := mFake;
  mFake.FTests := ['C:\P\Tests\Eins.Tests.dproj'];
  mHost := TBarHost.Create(mSource);
  try
    mHost.Bar.MouseMove(1, 10, 50);
    mAt := mHost.Center(1, 4);
    Assert.IsTrue(mAt.X > 0, 'Knopf „Ordner“ angeordnet');
    Assert.IsTrue(mHost.Bar.ClickAt(mAt.X, mAt.Y));
    mAt := mHost.Center(1, 0);
    Assert.IsTrue(mHost.Bar.ClickAt(mAt.X, mAt.Y), '„Öffnen und bauen“');
    mAt := mHost.Center(1, 1);
    Assert.IsTrue(mHost.Bar.ClickAt(mAt.X, mAt.Y), '„Tests“ mit einem Testprojekt');
    Assert.AreEqual(0, Integer(Length(mFake.Calls)), 'alles über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(3, Integer(Length(mFake.Calls)));
    Assert.AreEqual('folder ' + cProjectTwo, mFake.Calls[0]);
    Assert.AreEqual('build ' + cProjectTwo, mFake.Calls[1]);
    Assert.AreEqual('tests ' + cProjectTwo, mFake.Calls[2]);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasQuickActionsBarTests.BlockedPullDoesNothing;
var
  mFake: TAtlasFakeQuickActions;
  mSource: IAtlasQuickActionsSource;
  mHost: TBarHost;
  mButtons: TAtlasQuickActionButtons;
  mPull: Integer;
begin
  mFake := TAtlasFakeQuickActions.Create;
  mSource := mFake;
  mFake.Vcs.Changed := 2;
  mHost := TBarHost.Create(mSource);
  try
    mButtons := mHost.Bar.ButtonsOf(0);
    mPull := TAtlasWelcomeQuickActions.IndexOf(mButtons, TAtlasQuickAction.Pull);
    Assert.IsFalse(mButtons[mPull].Enabled, 'lokale Änderungen sperren Pull');
    mHost.Bar.Activate(0, mPull, False);
    CheckSynchronize;
    Assert.AreEqual(0, Integer(Length(mFake.Calls)));
    Assert.AreEqual('Erst lokale Änderungen sichern', TAtlasQuickActionTexts.ButtonHint(mButtons[mPull], False, 0, ''));
    // Ohne Änderungen holt Pull.
    mFake.Vcs.Changed := 0;
    mHost.Bar.SetRows([cProjectOne, cProjectTwo]);
    mHost.Bar.Activate(0, mPull, False);
    CheckSynchronize;
    Assert.AreEqual(1, Integer(Length(mFake.Calls)));
    Assert.AreEqual('pull ' + cProjectOne, mFake.Calls[0]);
    // Ein laufender Pull sperrt den Knopf ebenso.
    mFake.Busy := True;
    mHost.Bar.SetRows([cProjectOne, cProjectTwo]);
    Assert.IsFalse(mHost.Bar.ButtonsOf(0)[mPull].Enabled);
    Assert.IsTrue(mHost.Bar.ButtonsOf(0)[4].Enabled, '„Ordner“ geht weiter');
  finally
    mHost.Free;
  end;
end;

procedure TAtlasQuickActionsBarTests.KeyboardWithoutMouse;
var
  mFake: TAtlasFakeQuickActions;
  mSource: IAtlasQuickActionsSource;
  mHost: TBarHost;
begin
  mFake := TAtlasFakeQuickActions.Create;
  mSource := mFake;
  mFake.FTests := ['C:\P\Tests\Zwei.Tests.dproj'];
  mHost := TBarHost.Create(mSource);
  try
    // Pfeil ab wählt die nächste Zeile, Enter ohne Knopf öffnet sie.
    Assert.IsTrue(mHost.Bar.HandleKey(VK_DOWN, []));
    Assert.IsTrue(mHost.Bar.HandleKey(VK_DOWN, []));
    Assert.AreEqual(1, mHost.Bar.KeyRow, 'bleibt in der letzten Zeile');
    Assert.AreEqual(1, Integer(Length(mHost.Selected)), 'nur ein Wechsel');
    Assert.IsTrue(mHost.Bar.HandleKey(VK_RETURN, []));
    Assert.AreEqual(1, Integer(Length(mHost.Opened)));
    Assert.AreEqual(1, mHost.Opened[0]);
    // Strg+B und Strg+T auf der gewählten Zeile.
    Assert.IsTrue(mHost.Bar.HandleKey(Ord('B'), [ssCtrl]));
    Assert.IsTrue(mHost.Bar.HandleKey(Ord('T'), [ssCtrl]));
    // Pfeil rechts wählt Knöpfe, Enter führt aus, Pos1 geht zurück auf die Zeile.
    Assert.IsTrue(mHost.Bar.HandleKey(VK_HOME, []));
    Assert.AreEqual(-1, mHost.Bar.KeyButton);
    Assert.IsTrue(mHost.Bar.HandleKey(VK_RIGHT, []));
    Assert.IsTrue(mHost.Bar.HandleKey(VK_RIGHT, []));
    Assert.IsTrue(mHost.Bar.HandleKey(VK_RIGHT, []));
    Assert.IsTrue(mHost.Bar.HandleKey(VK_RIGHT, []));
    Assert.AreEqual(3, mHost.Bar.KeyButton, 'Pull');
    Assert.IsTrue(mHost.Bar.HandleKey(VK_RETURN, []));
    Assert.IsTrue(mHost.Bar.HandleKey(VK_ESCAPE, []));
    Assert.AreEqual(-1, mHost.Bar.KeyButton);
    Assert.IsFalse(mHost.Bar.HandleKey(VK_ESCAPE, []), 'Escape ohne Knopf bleibt beim Bereich');
    Assert.AreEqual(0, Integer(Length(mFake.Calls)), 'alles über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(3, Integer(Length(mFake.Calls)));
    Assert.AreEqual('build ' + cProjectTwo, mFake.Calls[0]);
    Assert.AreEqual('tests ' + cProjectTwo, mFake.Calls[1]);
    Assert.AreEqual('pull ' + cProjectTwo, mFake.Calls[2]);
    // Pfeil auf zurück.
    Assert.IsTrue(mHost.Bar.HandleKey(VK_UP, []));
    Assert.AreEqual(0, mHost.Bar.KeyRow);
    Assert.IsFalse(mHost.Bar.HandleKey(Ord('X'), [ssCtrl]), 'fremde Tasten bleiben bei der IDE');
  finally
    mHost.Free;
  end;
end;

procedure TAtlasQuickActionsBarTests.KeysOnlyForListedButtons;
var
  mFake: TAtlasFakeQuickActions;
  mSource: IAtlasQuickActionsSource;
  mHost: TBarHost;
begin
  mFake := TAtlasFakeQuickActions.Create;
  mSource := mFake;
  mFake.Items := TAtlasWelcomeQuickActions.ParseItems('build,folder');
  mHost := TBarHost.Create(mSource);
  try
    Assert.IsFalse(mHost.Bar.HandleKey(Ord('T'), [ssCtrl]), 'ohne Knopf „Tests“ gehört Strg+T der IDE');
    Assert.IsTrue(mHost.Bar.HandleKey(Ord('B'), [ssCtrl]));
    // Läuft in der IDE schon eine Aktion, nimmt die Leiste die Taste ab, führt aber nichts aus.
    mFake.Busy := True;
    mHost.Bar.SetRows([cProjectOne, cProjectTwo]);
    Assert.IsTrue(mHost.Bar.HandleKey(Ord('B'), [ssCtrl]));
    CheckSynchronize;
    Assert.AreEqual(1, Integer(Length(mFake.Calls)));
    Assert.AreEqual('build ' + cProjectOne, mFake.Calls[0]);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasQuickActionsBarTests.ChoicesFollowSource;
var
  mFake: TAtlasFakeQuickActions;
  mSource: IAtlasQuickActionsSource;
  mHost: TBarHost;
  mItems: TMenuItem;
begin
  mFake := TAtlasFakeQuickActions.Create;
  mSource := mFake;
  mHost := TBarHost.Create(mSource);
  try
    mItems := mHost.Bar.Menus.Popup.Items;
    // Konfiguration und Plattform: Überschrift, „wie in der IDE“, dann jede Kombination; zuletzt benutzt fett.
    Assert.IsTrue(mHost.Bar.Menus.FillChoices(mItems, 0, 0));
    Assert.AreEqual(7, Integer(mItems.Count));
    Assert.AreEqual('Konfiguration und Plattform', StripHotkey(mItems[0].Caption));
    Assert.IsFalse(mItems[0].Enabled);
    Assert.AreEqual('Wie in der IDE eingestellt', StripHotkey(mItems[2].Caption));
    Assert.AreEqual('Debug · Win64 (zuletzt)', StripHotkey(mItems[4].Caption));
    Assert.IsTrue(mItems[4].Default);
    Assert.AreEqual('Release · Win32', StripHotkey(mItems[5].Caption));
    mItems[4].Click;
    // Startprofile: das aktive markiert, „Ohne Startprofil“ zuletzt.
    Assert.IsTrue(mHost.Bar.Menus.FillChoices(mItems, 0, 2));
    Assert.AreEqual(5, Integer(mItems.Count));
    Assert.AreEqual('Startprofil', StripHotkey(mItems[0].Caption));
    Assert.AreEqual('Kunde (aktiv)', StripHotkey(mItems[2].Caption));
    Assert.AreEqual('Ohne Startprofil', StripHotkey(mItems[4].Caption));
    mItems[3].Click;
    // Testprojekte: nur bei mehreren eine Auswahl.
    mFake.FTests := ['C:\P\Tests\Eins.Tests.dproj'];
    Assert.IsFalse(mHost.Bar.Menus.FillChoices(mItems, 0, 1));
    mFake.FTests := ['C:\P\Tests\Eins.Tests.dproj', 'C:\P\Test\EinsTest.dproj'];
    Assert.IsTrue(mHost.Bar.Menus.FillChoices(mItems, 0, 1));
    Assert.AreEqual(4, Integer(mItems.Count));
    Assert.AreEqual('Testprojekt', StripHotkey(mItems[0].Caption));
    Assert.AreEqual('EinsTest', StripHotkey(mItems[3].Caption));
    mItems[3].Click;
    // Ordner hat keine Auswahl.
    Assert.IsFalse(mHost.Bar.Menus.FillChoices(mItems, 0, 4));
    Assert.AreEqual(0, Integer(Length(mFake.Calls)), 'alles über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(3, Integer(Length(mFake.Calls)));
    Assert.AreEqual('build ' + cProjectOne + ' Debug Win64', mFake.Calls[0]);
    Assert.AreEqual('run ' + cProjectOne + ' Leer', mFake.Calls[1]);
    Assert.AreEqual('tests ' + cProjectOne + ' C:\P\Test\EinsTest.dproj', mFake.Calls[2]);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasQuickActionsBarTests.CaptionsShowProgressAndResult;
var
  mButton: TAtlasQuickActionButton;
  mState: TAtlasQuickActionState;
  mHint: string;
begin
  mButton := Default(TAtlasQuickActionButton);
  mButton.Action := TAtlasQuickAction.Build;
  mButton.Enabled := True;
  mState := TAtlasQuickActionState.Started(TAtlasQuickAction.Build, 1000);
  Assert.AreEqual('Öffnen und bauen', TAtlasQuickActionTexts.Caption(mButton, TAtlasQuickActionState.Idle, 0));
  Assert.AreEqual('baut … 12 s', TAtlasQuickActionTexts.Caption(mButton, mState, 13500), 'Fortschritt im Knopf');
  Assert.AreEqual('baut … 12 s', TAtlasQuickActionTexts.StateText(mState, 13500, False));
  // Gebaut: Die Marke „Build 0/0/0“ zeigt das Ergebnis, keine eigene Marke.
  mState.Phase := TAtlasQuickActionPhase.Succeeded;
  Assert.AreEqual('', TAtlasQuickActionTexts.StateText(mState, 13500, False));
  mState.Phase := TAtlasQuickActionPhase.Refused;
  Assert.AreEqual('nicht gebaut', TAtlasQuickActionTexts.StateText(mState, 13500, False));
  mState.Action := TAtlasQuickAction.Tests;
  mState.Phase := TAtlasQuickActionPhase.Succeeded;
  mState.Passed := 412;
  Assert.AreEqual('Tests: 412 ok', TAtlasQuickActionTexts.StateText(mState, 0, False));
  mState.Phase := TAtlasQuickActionPhase.Failed;
  mState.Failed := 2;
  Assert.AreEqual('Tests: 2 fehlgeschlagen', TAtlasQuickActionTexts.StateText(mState, 0, False));
  mState.Failed := 0;
  Assert.AreEqual('Tests nicht gelaufen', TAtlasQuickActionTexts.StateText(mState, 0, False));
  mState.Action := TAtlasQuickAction.Pull;
  mState.Phase := TAtlasQuickActionPhase.Running;
  mState.StartedMs := 1000;
  Assert.AreEqual('aktualisiert … 2 s', TAtlasQuickActionTexts.StateText(mState, 3000, True), 'SVN');
  mState.Phase := TAtlasQuickActionPhase.Failed;
  mState.Pull := TAtlasPullOutcome.Blocked;
  Assert.AreEqual('Pull gesperrt', TAtlasQuickActionTexts.StateText(mState, 0, False));
  mState.Phase := TAtlasQuickActionPhase.Succeeded;
  mState.Pull := TAtlasPullOutcome.UpToDate;
  Assert.AreEqual('aktuell', TAtlasQuickActionTexts.StateText(mState, 0, False));
  mButton.Action := TAtlasQuickAction.Pull;
  mButton.Update := True;
  Assert.AreEqual('Aktualisieren', TAtlasQuickActionTexts.Caption(mButton, TAtlasQuickActionState.Idle, 0));
  // Tooltip mit Taste (Name der Taste je Windows-Sprache) bzw. Programm der Konsole.
  mButton.Action := TAtlasQuickAction.Build;
  mButton.Update := False;
  mHint := TAtlasQuickActionTexts.ButtonHint(mButton, False, $4042, '');
  Assert.IsTrue(mHint.EndsWith(sLineBreak + 'Taste: ' + ShortCutToText($4042)), mHint);
  mButton.Action := TAtlasQuickAction.Console;
  Assert.AreEqual('Konsole im Projektordner öffnen (wt.exe).', TAtlasQuickActionTexts.ButtonHint(mButton, False, 0, ''));
  mButton.Enabled := False;
  mButton.Action := TAtlasQuickAction.Tests;
  Assert.AreEqual('In der IDE läuft schon eine Schnellaktion', TAtlasQuickActionTexts.ButtonHint(mButton, False, 0, ''));
  Assert.AreEqual('Auf dem Projekt läuft schon eine Schnellaktion', TAtlasQuickActionTexts.ButtonHint(mButton, True, 0,
    ''));
end;

procedure TAtlasQuickActionsBarTests.EnglishTexts;
var
  mButton: TAtlasQuickActionButton;
  mState: TAtlasQuickActionState;
begin
  TAtlasStrings.Language := TAtlasLanguage.English;
  mButton := Default(TAtlasQuickActionButton);
  mButton.Action := TAtlasQuickAction.Build;
  Assert.AreEqual('Open and build', TAtlasQuickActionTexts.Caption(mButton, TAtlasQuickActionState.Idle, 0));
  mButton.Action := TAtlasQuickAction.Pull;
  mButton.Block := TAtlasPullBlock.LocalChanges;
  Assert.AreEqual('Save local changes first', TAtlasQuickActionTexts.ButtonHint(mButton, False, 0, ''));
  mState := TAtlasQuickActionState.Started(TAtlasQuickAction.Tests, 1000);
  Assert.AreEqual('testing … 4 s', TAtlasQuickActionTexts.StateText(mState, 5000, False));
end;

procedure TAtlasQuickActionsBarTests.ContextMenuFollowsRow;
var
  mFake: TAtlasFakeQuickActions;
  mSource: IAtlasQuickActionsSource;
  mHost: TBarHost;
  mMenu: TPopupMenu;
  mIndex: Integer;
  mVisible: TArray<string>;
begin
  mFake := TAtlasFakeQuickActions.Create;
  mSource := mFake;
  mFake.Items := TAtlasWelcomeQuickActions.ParseItems('build,run,pull,folder');
  mFake.Vcs.Kind := 'svn';
  mHost := TBarHost.Create(mSource);
  try
    mMenu := TPopupMenu.Create(mHost.Host);
    mHost.Bar.Menus.Attach(mMenu);
    mHost.Bar.Menus.Prepare(1);
    mVisible := nil;
    for mIndex := 0 to mMenu.Items.Count - 1 do
    begin
      if mMenu.Items[mIndex].Visible then
      begin
        mVisible := mVisible + [StripHotkey(mMenu.Items[mIndex].Caption)];
      end;
    end;
    // Ohne „Tests“ und „Konsole“; SVN: „Aktualisieren“.
    Assert.AreEqual(5, Integer(Length(mVisible)));
    Assert.AreEqual('-', mVisible[0]);
    Assert.AreEqual('Öffnen und bauen', mVisible[1]);
    Assert.AreEqual('Bauen mit', mVisible[2]);
    Assert.AreEqual('Starten mit', mVisible[3]);
    Assert.AreEqual('Aktualisieren', mVisible[4]);
    for mIndex := 0 to mMenu.Items.Count - 1 do
    begin
      if StripHotkey(mMenu.Items[mIndex].Caption) = 'Aktualisieren' then
      begin
        mMenu.Items[mIndex].Click;
      end;
    end;
    CheckSynchronize;
    Assert.AreEqual(1, Integer(Length(mFake.Calls)));
    Assert.AreEqual('pull ' + cProjectTwo, mFake.Calls[0]);
    // Ausgeschaltet: keine Einträge.
    mFake.IsOn := False;
    mHost.Bar.SetRows([cProjectOne, cProjectTwo]);
    mHost.Bar.Menus.Prepare(0);
    for mIndex := 0 to mMenu.Items.Count - 1 do
    begin
      Assert.IsFalse(mMenu.Items[mIndex].Visible, mMenu.Items[mIndex].Caption);
    end;
  finally
    mHost.Free;
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
    Assert.AreEqual('Aktualisieren ' + #$25BE, TAtlasQuickActionTexts.Caption(mHost.Bar.ButtonsOf(0)[mPull],
      TAtlasQuickActionState.Idle, 0));
    mItems := mHost.Bar.Menus.Popup.Items;
    Assert.IsTrue(mHost.Bar.Menus.FillChoices(mItems, 0, mPull));
    Assert.AreEqual(4, Integer(mItems.Count));
    Assert.AreEqual('Aktualisieren', StripHotkey(mItems[0].Caption));
    Assert.AreEqual('mit Externals', StripHotkey(mItems[2].Caption));
    Assert.IsTrue(mItems[2].Default);
    Assert.AreEqual('ohne Externals', StripHotkey(mItems[3].Caption));
    mItems[3].Click;
    CheckSynchronize;
    Assert.AreEqual(1, Integer(Length(mFake.Calls)));
    Assert.AreEqual('update ' + cProjectOne + ' True', mFake.Calls[0]);
    // Kontextmenü: „Aktualisieren“ als Untermenü.
    mMenu := TPopupMenu.Create(mHost.Host);
    mHost.Bar.Menus.Attach(mMenu);
    mHost.Bar.Menus.Prepare(1);
    mUpdate := nil;
    for mIndex := 0 to mMenu.Items.Count - 1 do
    begin
      if mMenu.Items[mIndex].Visible and (StripHotkey(mMenu.Items[mIndex].Caption) = 'Aktualisieren') then
      begin
        mUpdate := mMenu.Items[mIndex];
      end;
    end;
    Assert.IsNotNull(mUpdate);
    Assert.AreEqual(2, Integer(mUpdate.Count));
    mUpdate[0].Click;
    CheckSynchronize;
    Assert.AreEqual('update ' + cProjectTwo + ' False', mFake.Calls[1]);
    // Ohne ask: einfacher Eintrag, Knopf holt sofort.
    mFake.AskExternals := False;
    mHost.Bar.SetRows([cProjectOne, cProjectTwo]);
    mHost.Bar.Menus.Prepare(1);
    Assert.AreEqual(0, Integer(mUpdate.Count));
    Assert.IsFalse(mHost.Bar.Menus.FillChoices(mItems, 0, mPull));
    mHost.Bar.Activate(0, mPull, False);
    CheckSynchronize;
    Assert.AreEqual('pull ' + cProjectOne, mFake.Calls[2]);
  finally
    mHost.Free;
  end;
  mFake.Calls := nil;
end;

/// <summary>Texte: Knopf, Fortschritt, Ergebnis aus der IDE-Schicht, nicht gestartet, Tooltip.</summary>
procedure AssertTaskTexts;
var
  mButton: TAtlasQuickActionButton;
  mState: TAtlasQuickActionState;
begin
  // Texte: Knopf, Fortschritt, Ergebnis aus der IDE-Schicht, nicht gestartet, Tooltip.
  mButton := Default(TAtlasQuickActionButton);
  mButton.Action := TAtlasQuickAction.Tasks;
  mButton.Enabled := True;
  Assert.AreEqual('Aufgaben ▾', TAtlasQuickActionTexts.Caption(mButton, TAtlasQuickActionState.Idle, 0));
  mState := TAtlasQuickActionState.Started(TAtlasQuickAction.Tasks, 1000);
  Assert.AreEqual('Aufgabe … 3 s', TAtlasQuickActionTexts.Caption(mButton, mState, 4200));
  mState.Phase := TAtlasQuickActionPhase.Failed;
  mState.Detail := 'Delphi-12-Prüfung: 2 Fehler 14:03';
  Assert.AreEqual('Delphi-12-Prüfung: 2 Fehler 14:03', TAtlasQuickActionTexts.StateText(mState, 0, False));
  mState.Phase := TAtlasQuickActionPhase.Refused;
  Assert.AreEqual('Aufgabe nicht gestartet', TAtlasQuickActionTexts.StateText(mState, 0, False));
  Assert.IsTrue(TAtlasQuickActionTexts.ButtonHint(mButton, False, 0, '').Contains('Atlas-Aufgaben'));
end;

procedure TAtlasQuickActionsBarTests.TasksChooseAndShowResult;
var
  mFake: TAtlasFakeQuickActions;
  mSource: IAtlasQuickActionsSource;
  mHost: TBarHost;
  mItems: TMenuItem;
  mMenu: TPopupMenu;
  mIndex: Integer;
begin
  mFake := TAtlasFakeQuickActions.Create;
  mSource := mFake;
  mFake.Items := [TAtlasQuickAction.Folder, TAtlasQuickAction.Tasks];
  mHost := TBarHost.Create(mSource);
  try
    // „Aufgaben ▾“: Überschrift, dann die Aufgaben der atlas.json in ihrer Reihenfolge.
    mItems := mHost.Bar.Menus.Popup.Items;
    Assert.IsTrue(mHost.Bar.ButtonsOf(0)[1].HasMenu);
    Assert.IsTrue(mHost.Bar.Menus.FillChoices(mItems, 0, 1));
    Assert.AreEqual(4, Integer(mItems.Count));
    Assert.AreEqual('Projektaufgabe', StripHotkey(mItems[0].Caption));
    Assert.AreEqual('Delphi-12-Prüfung', StripHotkey(mItems[2].Caption));
    Assert.AreEqual('Konfigurationsdoku', StripHotkey(mItems[3].Caption));
    mItems[3].Click;
    CheckSynchronize;
    Assert.AreEqual(1, Integer(Length(mFake.Calls)));
    Assert.AreEqual('task ' + cProjectOne + ' Konfigurationsdoku', mFake.Calls[0]);
    // Kontextmenü: Untermenü „Aufgabe ausführen“ ohne Überschrift.
    mMenu := TPopupMenu.Create(mHost.Host);
    mHost.Bar.Menus.Attach(mMenu);
    mHost.Bar.Menus.Prepare(1);
    mItems := nil;
    for mIndex := 0 to mMenu.Items.Count - 1 do
    begin
      if StripHotkey(mMenu.Items[mIndex].Caption) = 'Aufgabe ausführen' then
      begin
        mItems := mMenu.Items[mIndex];
      end;
    end;
    Assert.IsNotNull(mItems);
    Assert.IsTrue(mItems.Visible);
    Assert.AreEqual(2, Integer(mItems.Count));
    mItems[0].Click;
    CheckSynchronize;
    Assert.AreEqual('task ' + cProjectTwo + ' Delphi-12-Prüfung', mFake.Calls[1]);
    // Ohne Aufgaben keine Auswahl.
    mFake.FTaskNames := nil;
    Assert.IsFalse(mHost.Bar.Menus.FillChoices(mHost.Bar.Menus.Popup.Items, 0, 1));
    mHost.Bar.Menus.Prepare(0);
    Assert.IsFalse(mItems.Visible);
  finally
    mHost.Free;
  end;
  AssertTaskTexts;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasQuickActionsBarTests);

end.
