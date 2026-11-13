unit Atlas.UI.Welcome.QuickActions;

// Schnellaktionen je Projekt auf der Willkommensseite (#764, Mockup #ws10),
// Teil mit VCL ohne Open Tools API. Die Bereiche „Projekte“ (#592) und
// „Weiterarbeiten“ (#755) zeigen in der Zeile unter der Maus bzw. in der mit
// der Tastatur gewählten Zeile eine Knopfleiste statt der Marken:
//   [Öffnen und bauen ▾] [Tests] [Startprofil ▾] [Pull] [Ordner] [Konsole]
//   [Aufgaben ▾]
// rechtsbündig, bei wenig Platz in zwei Zeilen (die Zeilenhöhe bleibt).
// - „Aufgaben ▾“ (#900) öffnet die Projektaufgaben aus atlas.json; der Stand
//   zeigt die gestartete Aufgabe mit ihrem Ergebnis.
// - „Öffnen und bauen“ baut mit der zuletzt benutzten Konfiguration und
//   Plattform; der Teil ▾ öffnet die Auswahl. „Startprofil ▾“ öffnet die
//   Profile. „Tests“ fragt bei mehreren Testprojekten nach dem Testprojekt.
// - Gesperrter Pull zeigt im Tooltip den Grund („Erst lokale Änderungen
//   sichern“). Mit vcs.externals.update = ask (#1292) heißt er
//   „Aktualisieren ▾“ und fragt „mit Externals“/„ohne Externals“, im
//   Kontextmenü als Untermenü. Während eine Aktion läuft, zeigt ihr Knopf „baut … 12 s“,
//   außerhalb der Leiste steht der Stand als Marke (Text, Farbe: StateText,
//   StateColor).
// - Tastatur über ein unsichtbares Steuerelement (TAtlasQuickKeySink), das
//   den Fokus nimmt: ↑/↓ wählen die Zeile, ←/→ den Knopf, Enter bzw.
//   Leertaste führen ihn aus (ohne Knopf: Zeile öffnen bzw. fortsetzen),
//   Alt+↓ öffnet die Auswahl, Strg+B baut, Strg+T testet (Tasten aus den
//   Einstellungen, #399), Kontextmenütaste bzw. Umschalt+F10 öffnet das
//   Kontextmenü der Zeile.
// Daten und Aktionen kommen über IAtlasQuickActionsSource aus der
// IDE-Schicht; Aufrufe gehen über die Nachrichtenschleife, weil die Quelle die
// Bereiche daraufhin neu füllt.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.Graphics,
  Vcl.Menus,
  Atlas.Core.Welcome.QuickActions,
  Atlas.UI.Welcome.Frame,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.Strings;

type
  IAtlasQuickActionsSource = interface
    ['{C7F5C025-7259-4CF4-BB0A-6D6A1251CC59}']
    /// <summary>welcomePage.quickActions; aus = keine Knöpfe, keine Tasten.</summary>
    function Enabled: Boolean;
    /// <summary>Knöpfe für AProject nach welcomePage.quickActions.items, Versionsverwaltung und laufenden
    /// Aktionen.</summary>
    function Buttons(const AProject: string): TAtlasQuickActionButtons;
    /// <summary>Stand der letzten Schnellaktion von AProject in dieser Sitzung.</summary>
    function State(const AProject: string): TAtlasQuickActionState;
    /// <summary>Jetzt als Tick in ms (wie TAtlasQuickActionState.StartedMs).</summary>
    function NowMs: UInt64;
    /// <summary>Aktion mit den Vorgaben ausführen (Bauen: zuletzt benutzte Konfiguration und Plattform; Tests: das
    /// eine Testprojekt; Start: aktives Startprofil).</summary>
    procedure Execute(const AProject: string; AAction: TAtlasQuickAction);
    /// <summary>Konfigurationen und Plattformen von AProject; AConfiguration/APlatform: Vorgabe ('' = wie in der
    /// IDE).</summary>
    function Targets(const AProject: string; out AConfiguration, APlatform: string): TAtlasProjectTargets;
    procedure Build(const AProject, AConfiguration, APlatform: string);
    /// <summary>Testprojekte zu AProject: eins = das zugeordnete, mehrere = Auswahl, keins = keins gefunden.</summary>
    function TestProjects(const AProject: string): TArray<string>;
    procedure RunTests(const AProject, ATestProject: string);
    /// <summary>Namen der Startprofile von AProject; AActive: aktives ('' = keins).</summary>
    function Profiles(const AProject: string; out AActive: string): TArray<string>;
    /// <summary>Öffnen und mit AProfile starten ('' = ohne Startprofil).</summary>
    procedure Run(const AProject, AProfile: string);
    /// <summary>Namen der Projektaufgaben von AProject (#900) in der Reihenfolge der atlas.json.</summary>
    function TaskNames(const AProject: string): TArray<string>;
    /// <summary>Projektaufgabe AName von AProject im Hintergrund starten.</summary>
    procedure RunTask(const AProject, AName: string);
    /// <summary>Aktualisieren mit bzw. ohne Externals (#1292, Auswahl bei vcs.externals.update = ask).</summary>
    procedure Pull(const AProject: string; AIgnoreExternals: Boolean);
    /// <summary>Strg+B bzw. Strg+T als TShortCut; 0 = keine Taste.</summary>
    function BuildKey: Integer;
    function TestKey: Integer;
    /// <summary>Programm für „Konsole“ (Tooltip).</summary>
    function ConsoleProgram: string;
  end;

  TAtlasQuickKeyEvent = function(AKey: Word; AShift: TShiftState): Boolean of object;

  /// <summary>Unsichtbares Steuerelement mit Fokus für die Tastatur eines Bereichs; Pfeiltasten und Enter kommen
  /// vor dem Dialog der IDE an.</summary>
  TAtlasQuickKeySink = class(TCustomControl)
  private
    FOnKey: TAtlasQuickKeyEvent;
    FOnFocusChange: TNotifyEvent;
    procedure WMGetDlgCode(var Message: TWMGetDlgCode); message WM_GETDLGCODE;
    procedure CNKeyDown(var Message: TWMKeyDown); message CN_KEYDOWN;
    procedure CNSysKeyDown(var Message: TWMKeyDown); message CN_SYSKEYDOWN;
  protected
    procedure DoEnter; override;
    procedure DoExit; override;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Taste wie gedrückt (auch für Tests und den Vorrang über die Nachrichtenschleife).</summary>
    function HandleKey(AKey: Word; AShift: TShiftState): Boolean;
    property OnKey: TAtlasQuickKeyEvent read FOnKey write FOnKey;
    property OnFocusChange: TNotifyEvent read FOnFocusChange write FOnFocusChange;
  end;

  TAtlasQuickRowProc = reference to procedure(ARow: Integer);
  TAtlasQuickScale = reference to function(AValue: Integer): Integer;

  TAtlasQuickActionsBar = class;

  /// <summary>Auswahl hinter den Knöpfen (Konfiguration × Plattform, Startprofile, Testprojekte, Projektaufgaben,
  /// Externals) und Einträge der Schnellaktionen im Kontextmenü eines Bereichs.</summary>
  TAtlasQuickActionsMenus = class(TComponent)
  private type
    TChoiceKind = (Target, Profile, TestProject, Task, Update);
    TChoice = record
      Kind: TChoiceKind;
      Project: string;
      A: string;
      B: string;
    end;
  private
    FBar: TAtlasQuickActionsBar;
    FPopup: TPopupMenu;
    FChoices: TArray<TChoice>;
    FContextItems: TArray<TMenuItem>;
    FContextActions: TArray<TAtlasQuickAction>;
    FBuildWithItem: TMenuItem;
    FRunWithItem: TMenuItem;
    FTasksItem: TMenuItem;
    FContextSeparator: TMenuItem;
    FContextRow: Integer;
    procedure ChoiceClick(Sender: TObject);
    procedure ContextClick(Sender: TObject);
    procedure AddChoice(AParent: TMenuItem; const ACaption: string; const AChoice: TChoice; ADefault: Boolean);
    procedure AddTitle(AParent: TMenuItem; AId: TAtlasWelcomeTextId);
    procedure AddContextItem(AMenu: TPopupMenu; AAction: TAtlasQuickAction; const ACaption: string);
    function AddSubmenu(AMenu: TPopupMenu; AId: TAtlasWelcomeTextId): TMenuItem;
    procedure FillTargets(AParent: TMenuItem; const AProject: string);
    procedure FillProfiles(AParent: TMenuItem; const AProject: string);
    procedure FillTestProjects(AParent: TMenuItem; const AProject: string; const ACandidates: TArray<string>);
    procedure FillTasks(AParent: TMenuItem; const AProject: string);
    procedure FillUpdate(AParent: TMenuItem; const AProject: string);
    /// <summary>Auswahl zu AButton in AParent (mit Überschrift in der aufgeklappten Auswahl); False ohne Einträge.
    /// </summary>
    function FillFor(AParent: TMenuItem; const AButton: TAtlasQuickActionButton; const AProject: string): Boolean;
    procedure PreparePull(AItem: TMenuItem; const AButtons: TAtlasQuickActionButtons; ARow, AFound: Integer);
    /// <summary>Untermenü AItem mit der Auswahl des Knopfs AAction füllen; True, wenn es sichtbar ist.</summary>
    function PrepareSubmenu(AItem: TMenuItem; const AButtons: TAtlasQuickActionButtons; ARow: Integer;
      AAction: TAtlasQuickAction): Boolean;
  public
    constructor Create(ABar: TAtlasQuickActionsBar); reintroduce;
    /// <summary>Auswahl zu Knopf AIndex der Zeile ARow unter dem Knopf aufklappen.</summary>
    procedure PopupAt(ARow, AIndex: Integer);
    /// <summary>Auswahl zu Knopf AIndex der Zeile ARow füllen (Konfiguration × Plattform, Startprofile bzw.
    /// Testprojekte bzw. Projektaufgaben) in AParent; False, wenn es keine Auswahl gibt.</summary>
    function FillChoices(AParent: TMenuItem; ARow, AIndex: Integer): Boolean;
    /// <summary>Einträge der Schnellaktionen unten an AMenu anhängen (Kontextmenü eines Bereichs).</summary>
    procedure Attach(AMenu: TPopupMenu);
    /// <summary>Einträge für ARow sichtbar, gesperrt und Untermenüs gefüllt (vor dem Öffnen des Kontextmenüs).
    /// </summary>
    procedure Prepare(ARow: Integer);
    /// <summary>Aufgeklappte Auswahl unter einem Knopf.</summary>
    property Popup: TPopupMenu read FPopup;
  end;

  /// <summary>Knopfleiste, Stand und Tastatur für die Zeilen eines Bereichs. Der Bereich meldet Zeilen
  /// (Projekte), Maus und Zeichnen; die Leiste ruft die Quelle.</summary>
  TAtlasQuickActionsBar = class(TComponent)
  public const
    cButtonHeight = 20;
    cButtonPadding = 8;
    cButtonGap = 4;
    cLineGap = 2;
    /// <summary>Breite des Teils ▾ von „Öffnen und bauen“.</summary>
    cMenuPart = 16;
    cTickMs = 1000;
  private type
    /// <summary>Projekte der Zeilen mit Knöpfen, Stand und Rechtecken der Knöpfe (entstehen beim Zeichnen).
    /// </summary>
    TRowData = record
      Projects: TArray<string>;
      Buttons: TArray<TAtlasQuickActionButtons>;
      States: TArray<TAtlasQuickActionState>;
      Rects: TArray<TArray<TRect>>;
      NowMs: UInt64;
    end;
    /// <summary>Zeile und Knopf unter der Maus bzw. mit der Tastatur gewählt.</summary>
    TSelection = record
      HoverRow: Integer;
      HoverButton: Integer;
      KeyRow: Integer;
      KeyButton: Integer;
      // Letzte Eingabe kam von der Tastatur: Die gewählte Zeile ist die aktive, nicht die unter der Maus.
      UseKey: Boolean;
    end;
    THandlers = record
      Scale: TAtlasQuickScale;
      OpenRow: TAtlasQuickRowProc;
      RowMenu: TAtlasQuickRowProc;
      SelectRow: TAtlasQuickRowProc;
    end;
  private
    FBox: TAtlasWelcomeCanvas;
    FSink: TAtlasQuickKeySink;
    FSource: IAtlasQuickActionsSource;
    FTimer: TTimer;
    FMenus: TAtlasQuickActionsMenus;
    FRows: TRowData;
    FSelection: TSelection;
    FHandlers: THandlers;
    procedure SetSource(const AValue: IAtlasQuickActionsSource);
    procedure TimerTick(Sender: TObject);
    procedure SinkFocusChange(Sender: TObject);
  public
    constructor Create(AOwner: TComponent; ABox: TAtlasWelcomeCanvas; AParent: TWinControl); reintroduce;
    destructor Destroy; override;
    /// <summary>Zeilen neu setzen (UpdateContent des Bereichs): Knöpfe und Stand je Projekt neu lesen.</summary>
    procedure SetRows(const AProjects: TArray<string>);
    /// <summary>Quelle gesetzt und welcomePage.quickActions an.</summary>
    function Active: Boolean;
    /// <summary>Knöpfe der Zeile; leer ohne Quelle, ausgeschaltet oder ohne Knöpfe.</summary>
    function ButtonsOf(ARow: Integer): TAtlasQuickActionButtons;
    function StateOf(ARow: Integer): TAtlasQuickActionState;
    /// <summary>Zeile mit Knopfleiste: unter der Maus bzw. mit der Tastatur gewählt; -1 = keine.</summary>
    function ActiveRow: Integer;
    /// <summary>Maus über ARow (-1 = keine Zeile) an X, Y; zeichnet bei Wechsel neu.</summary>
    procedure MouseMove(ARow, AX, AY: Integer);
    procedure MouseLeave;
    /// <summary>Maus gedrückt in ARow: Tastatur übernimmt die Zeile und den Fokus.</summary>
    procedure MouseDown(ARow: Integer);
    /// <summary>Knopfleiste der Zeile in AArea (rechtsbündig, Left = äußerste linke Grenze) anordnen; Ergebnis:
    /// linke Kante der Leiste. Nur beim Zeichnen.</summary>
    function LayoutRow(ACanvas: TCanvas; ARow: Integer; const AArea: TRect): Integer;
    procedure PaintRow(ACanvas: TCanvas; ARow: Integer);
    /// <summary>Hintergrund der aktiven Zeile und Fokusrahmen der Tastaturzeile.</summary>
    procedure PaintBackground(ACanvas: TCanvas; ARow: Integer; const ARowRect: TRect);
    /// <summary>Knopf an X, Y in der aktiven Zeile; AMenu: auf dem Teil ▾.</summary>
    function HitTest(AX, AY: Integer; out ARow, AIndex: Integer; out AMenu: Boolean): Boolean;
    /// <summary>Klick an X, Y: True, wenn ein Knopf getroffen war (dann klickt der Bereich nicht).</summary>
    function ClickAt(AX, AY: Integer): Boolean;
    /// <summary>Knopf AIndex der Zeile ARow wie geklickt; AMenu: Teil ▾.</summary>
    procedure Activate(ARow, AIndex: Integer; AMenu: Boolean);
    /// <summary>Tooltip des Knopfs an X, Y; False ohne Knopf.</summary>
    function HintAt(AX, AY: Integer; out AHint: string): Boolean;
    /// <summary>Taste wie in der Tastatur des Bereichs gedrückt.</summary>
    function HandleKey(AKey: Word; AShift: TShiftState): Boolean;
    property Source: IAtlasQuickActionsSource read FSource write SetSource;
    property Sink: TAtlasQuickKeySink read FSink;
    /// <summary>Auswahl der Knöpfe und Einträge im Kontextmenü des Bereichs.</summary>
    property Menus: TAtlasQuickActionsMenus read FMenus;
    /// <summary>Zeitpunkt der letzten Aktualisierung (ms); 0 ohne Quelle.</summary>
    property NowMs: UInt64 read FRows.NowMs;
    property KeyRow: Integer read FSelection.KeyRow write FSelection.KeyRow;
    property KeyButton: Integer read FSelection.KeyButton write FSelection.KeyButton;
    property OnScale: TAtlasQuickScale read FHandlers.Scale write FHandlers.Scale;
    /// <summary>Enter ohne gewählten Knopf: Zeile öffnen bzw. fortsetzen.</summary>
    property OnOpenRow: TAtlasQuickRowProc read FHandlers.OpenRow write FHandlers.OpenRow;
    /// <summary>Kontextmenütaste: Kontextmenü der Zeile öffnen.</summary>
    property OnRowMenu: TAtlasQuickRowProc read FHandlers.RowMenu write FHandlers.RowMenu;
    /// <summary>Pfeil auf/ab hat die Zeile gewechselt.</summary>
    property OnSelectRow: TAtlasQuickRowProc read FHandlers.SelectRow write FHandlers.SelectRow;
  end;

  /// <summary>Texte zu einer Zeile mit Schnellaktionen, gemeinsam für die Bereiche „Projekte“ und
  /// „Weiterarbeiten“.</summary>
  TAtlasQuickRowTexts = class
  public
    /// <summary>Pull der Zeile ist ein SVN-Update: „aktualisiert …“ statt „holt …“.</summary>
    class function IsUpdateRow(ABar: TAtlasQuickActionsBar; ARow: Integer): Boolean; static;
    /// <summary>Stand der letzten Schnellaktion der Zeile als Text der Marke; '' = keine Marke.</summary>
    class function StateText(ABar: TAtlasQuickActionsBar; ARow: Integer): string; static;
    /// <summary>Zusatz zum Tooltip der Zeile: Stand samt Grund und Hinweis auf die Tasten; '' ohne Quelle.
    /// </summary>
    class function HintSuffix(ABar: TAtlasQuickActionsBar; ARow: Integer): string; static;
  end;

implementation

uses
  Atlas.UI.Welcome.QuickActions.Texts,
  Vcl.Forms,
  Vcl.Themes,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard;

const
  cSeparator = ' · ';

type
  /// <summary>Ordnet die Knöpfe einer Zeile rechtsbündig an, bei wenig Platz in zwei Zeilen.</summary>
  TQuickRowLayout = record
    Area: TRect;
    Gap: Integer;
    Widths: TArray<Integer>;
    Rects: TArray<TRect>;
    /// <summary>Breite der Knöpfe AFrom bis ATo samt Abständen.</summary>
    function Span(AFrom, ATo: Integer): Integer;
    procedure Place(AFrom, ATo, ATop, AHeight: Integer);
    /// <summary>Erster Knopf der zweiten Zeile: vorne die ersten Knöpfe, so gleichmäßig wie möglich.</summary>
    function SplitIndex: Integer;
    procedure PlaceTwoLines(ALineGap, AHeight: Integer);
    function LeftEdge: Integer;
  end;

  TQuickButtonColors = record
    Text: TColor;
    Muted: TColor;
    Line: TColor;
    Accent: TColor;
    AccentText: TColor;
  end;

  /// <summary>Zeichnet die Knöpfe der Zeile Row in die Rechtecke aus LayoutRow.</summary>
  TQuickRowPainter = record
    Bar: TAtlasQuickActionsBar;
    Canvas: TCanvas;
    Colors: TQuickButtonColors;
    Row: Integer;
    Buttons: TAtlasQuickActionButtons;
    function Scaled(AValue: Integer): Integer;
    /// <summary>Rahmen bzw. Füllung und Schriftfarbe; „Öffnen und bauen“ ist gefüllt, solange er nutzbar ist.
    /// </summary>
    procedure PaintFrame(AIndex: Integer; const AArea: TRect);
    procedure PaintCaption(AIndex: Integer; const AArea: TRect);
    procedure PaintFocus(AIndex: Integer; const AArea: TRect);
    procedure PaintButton(AIndex: Integer);
  end;

  /// <summary>Tastatur der Zeile Row (#764, #399).</summary>
  TQuickKeys = record
    Bar: TAtlasQuickActionsBar;
    Row: Integer;
    Buttons: TAtlasQuickActionButtons;
    Shift: TShiftState;
    /// <summary>Strg+B, Strg+T (einstellbar) auf der gewählten Zeile.</summary>
    function ActionKey(AKey: Word): Boolean;
    /// <summary>Alt+↓: Auswahl des gewählten Knopfs, sonst die von „Öffnen und bauen“.</summary>
    function MenuKey: Boolean;
    function StepRow(AKey: Word): Boolean;
    function StepButton(AKey: Word): Boolean;
    function Home: Boolean;
    function Enter: Boolean;
    function Escape: Boolean;
    function ContextMenu: Boolean;
    function Handle(AKey: Word): Boolean;
  end;

function ScaleOf(ABar: TAtlasQuickActionsBar; AValue: Integer): Integer;
begin
  Result := AValue;
  if Assigned(ABar.FHandlers.Scale) then
  begin
    Result := ABar.FHandlers.Scale(AValue);
  end;
end;

function IsRow(ABar: TAtlasQuickActionsBar; ARow: Integer): Boolean;
begin
  Result := (ARow >= 0) and (ARow <= High(ABar.FRows.Projects));
end;

function HasKeyFocus(ABar: TAtlasQuickActionsBar): Boolean;
begin
  Result := ABar.FSink.Focused;
end;

function ActionsOf(ABar: TAtlasQuickActionsBar; ARow: Integer): TAtlasQuickActions;
var
  mButton: TAtlasQuickActionButton;
begin
  Result := [];
  for mButton in ABar.ButtonsOf(ARow) do
  begin
    Include(Result, mButton.Action);
  end;
end;

procedure InvalidateBox(ABar: TAtlasQuickActionsBar);
begin
  if ABar.FBox <> nil then
  begin
    ABar.FBox.Invalidate;
  end;
end;

/// <summary>Zeitgeber nur, solange eine Aktion läuft („baut … 12 s“ zählt weiter).</summary>
procedure UpdateTimer(ABar: TAtlasQuickActionsBar);
var
  mState: TAtlasQuickActionState;
  mRunning: Boolean;
begin
  mRunning := False;
  for mState in ABar.FRows.States do
  begin
    mRunning := mRunning or mState.Running;
  end;
  ABar.FTimer.Enabled := mRunning;
end;

procedure QueueOnMain(const AProc: TProc);
var
  mProc: TProc;
begin
  mProc := AProc;
  // Die Quelle füllt die Bereiche danach neu: nicht im eigenen Maus- bzw. Tastenereignis.
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      mProc();
    end);
end;

/// <summary>Fragt der Knopf erst nach einer Auswahl? „Startprofil ▾“ und „Aufgaben ▾“ immer, „Tests“ bei mehreren
/// Testprojekten, Pull bei vcs.externals.update = ask (#1292), „Öffnen und bauen“ auf dem Teil ▾.</summary>
function NeedsChoice(const AButton: TAtlasQuickActionButton; AMenu: Boolean; const ASource: IAtlasQuickActionsSource;
  const AProject: string): Boolean;
begin
  case AButton.Action of
    TAtlasQuickAction.Build:
      Result := AMenu;
    TAtlasQuickAction.Run, TAtlasQuickAction.Tasks:
      Result := True;
    TAtlasQuickAction.Tests:
      Result := Length(ASource.TestProjects(AProject)) > 1;
    TAtlasQuickAction.Pull:
      Result := AButton.AskExternals;
  else
    Result := False;
  end;
end;

{ TAtlasQuickRowTexts }

class function TAtlasQuickRowTexts.IsUpdateRow(ABar: TAtlasQuickActionsBar; ARow: Integer): Boolean;
var
  mButton: TAtlasQuickActionButton;
begin
  Result := False;
  for mButton in ABar.ButtonsOf(ARow) do
  begin
    if mButton.Action = TAtlasQuickAction.Pull then
    begin
      Result := mButton.Update;
    end;
  end;
end;

class function TAtlasQuickRowTexts.StateText(ABar: TAtlasQuickActionsBar; ARow: Integer): string;
begin
  Result := TAtlasQuickActionTexts.StateText(ABar.StateOf(ARow), ABar.NowMs, IsUpdateRow(ABar, ARow));
end;

class function TAtlasQuickRowTexts.HintSuffix(ABar: TAtlasQuickActionsBar; ARow: Integer): string;
var
  mState: string;
begin
  Result := '';
  if ABar.Source = nil then
  begin
    Exit;
  end;
  mState := StateText(ABar, ARow);
  if (mState <> '') and (ABar.StateOf(ARow).Detail <> '') then
  begin
    mState := mState + ': ' + ABar.StateOf(ARow).Detail;
  end;
  if mState <> '' then
  begin
    Result := Result + sLineBreak + TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickHintState, [mState]);
  end;
  if ABar.Active then
  begin
    Result := Result + sLineBreak + TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickHintKeys);
  end;
end;

{ TAtlasQuickKeySink }

constructor TAtlasQuickKeySink.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  ParentColor := True;
  SetBounds(0, 0, 0, 0);
end;

procedure TAtlasQuickKeySink.Paint;
begin
  // Unsichtbar: Die Bereiche zeichnen Auswahl und Fokus selbst.
end;

procedure TAtlasQuickKeySink.WMGetDlgCode(var Message: TWMGetDlgCode);
begin
  inherited;
  Message.Result := Message.Result or DLGC_WANTARROWS or DLGC_WANTALLKEYS;
end;

function TAtlasQuickKeySink.HandleKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := False;
  if Assigned(FOnKey) then
    try
      Result := FOnKey(AKey, AShift);
    except
      // Keine Exception an die IDE (#493).
      on E: Exception do
        TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
    end;
end;

procedure TAtlasQuickKeySink.CNKeyDown(var Message: TWMKeyDown);
begin
  // Vor den Tastenkürzeln des Hauptfensters: Strg+B und Strg+T gehören hier der Willkommensseite.
  if HandleKey(Message.CharCode, KeyDataToShiftState(Message.KeyData)) then
  begin
    Message.Result := 1;
    Exit;
  end;
  inherited;
end;

procedure TAtlasQuickKeySink.CNSysKeyDown(var Message: TWMKeyDown);
begin
  // Alt+↓ öffnet die Auswahl.
  if HandleKey(Message.CharCode, KeyDataToShiftState(Message.KeyData)) then
  begin
    Message.Result := 1;
    Exit;
  end;
  inherited;
end;

procedure TAtlasQuickKeySink.DoEnter;
begin
  inherited;
  if Assigned(FOnFocusChange) then
  begin
    FOnFocusChange(Self);
  end;
end;

procedure TAtlasQuickKeySink.DoExit;
begin
  inherited;
  if Assigned(FOnFocusChange) then
  begin
    FOnFocusChange(Self);
  end;
end;

{ TQuickRowLayout }

function TQuickRowLayout.Span(AFrom, ATo: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := AFrom to ATo do
  begin
    Inc(Result, Widths[mIndex]);
  end;
  if ATo > AFrom then
  begin
    Inc(Result, (ATo - AFrom) * Gap);
  end;
end;

procedure TQuickRowLayout.Place(AFrom, ATo, ATop, AHeight: Integer);
var
  mIndex, mRight: Integer;
begin
  mRight := Area.Right;
  for mIndex := ATo downto AFrom do
  begin
    Rects[mIndex] := Rect(mRight - Widths[mIndex], ATop, mRight, ATop + AHeight);
    Dec(mRight, Widths[mIndex] + Gap);
  end;
end;

function TQuickRowLayout.SplitIndex: Integer;
var
  mIndex: Integer;
begin
  Result := Length(Widths) div 2;
  for mIndex := 1 to High(Widths) do
  begin
    if (Span(0, mIndex - 1) <= Area.Width) and (Span(mIndex, High(Widths)) <= Area.Width) then
    begin
      Exit(mIndex);
    end;
  end;
end;

procedure TQuickRowLayout.PlaceTwoLines(ALineGap, AHeight: Integer);
var
  mSplit, mLineHeight, mTop: Integer;
begin
  // Zwei Zeilen in der Zeilenhöhe.
  mSplit := SplitIndex;
  mLineHeight := (Area.Height - ALineGap) div 2;
  if mLineHeight > AHeight then
  begin
    mLineHeight := AHeight;
  end;
  mTop := Area.Top + (Area.Height - 2 * mLineHeight - ALineGap) div 2;
  Place(0, mSplit - 1, mTop, mLineHeight);
  Place(mSplit, High(Widths), mTop + mLineHeight + ALineGap, mLineHeight);
end;

function TQuickRowLayout.LeftEdge: Integer;
var
  mRect: TRect;
begin
  Result := Area.Right;
  for mRect in Rects do
  begin
    if mRect.Left < Result then
    begin
      Result := mRect.Left;
    end;
  end;
end;

{ TQuickRowPainter }

function TQuickRowPainter.Scaled(AValue: Integer): Integer;
begin
  Result := ScaleOf(Bar, AValue);
end;

procedure TQuickRowPainter.PaintFrame(AIndex: Integer; const AArea: TRect);
var
  mButton: TAtlasQuickActionButton;
begin
  mButton := Buttons[AIndex];
  if (mButton.Action = TAtlasQuickAction.Build) and mButton.Enabled then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := Colors.Accent;
    Canvas.Pen.Color := Colors.Accent;
    Canvas.RoundRect(AArea.Left, AArea.Top, AArea.Right, AArea.Bottom, Scaled(6), Scaled(6));
    Canvas.Font.Color := Colors.AccentText;
    Exit;
  end;
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Color := Colors.Line;
  if (AIndex = Bar.FSelection.HoverButton) and (Row = Bar.FSelection.HoverRow) and mButton.Enabled then
  begin
    Canvas.Pen.Color := Colors.Accent;
  end;
  Canvas.RoundRect(AArea.Left, AArea.Top, AArea.Right, AArea.Bottom, Scaled(6), Scaled(6));
  Canvas.Font.Color := Colors.Muted;
  if mButton.Enabled then
  begin
    Canvas.Font.Color := Colors.Text;
  end;
end;

procedure TQuickRowPainter.PaintCaption(AIndex: Integer; const AArea: TRect);
var
  mText: string;
  mPart: Integer;
begin
  Canvas.Brush.Style := bsClear;
  mText := TAtlasQuickActionTexts.Caption(Buttons[AIndex], Bar.FRows.States[Row], Bar.FRows.NowMs);
  if Buttons[AIndex].Action <> TAtlasQuickAction.Build then
  begin
    Canvas.TextOut(AArea.Left + (AArea.Width - Canvas.TextWidth(mText)) div 2,
      AArea.Top + (AArea.Height - Canvas.TextHeight(mText)) div 2, mText);
    Exit;
  end;
  // Teil ▾ rechts, durch einen Strich getrennt.
  mPart := Scaled(TAtlasQuickActionsBar.cMenuPart);
  Canvas.TextOut(AArea.Left + (AArea.Width - mPart - Canvas.TextWidth(mText)) div 2,
    AArea.Top + (AArea.Height - Canvas.TextHeight(mText)) div 2, mText);
  Canvas.Pen.Color := Canvas.Font.Color;
  Canvas.MoveTo(AArea.Right - mPart, AArea.Top + Scaled(4));
  Canvas.LineTo(AArea.Right - mPart, AArea.Bottom - Scaled(4));
  Canvas.TextOut(AArea.Right - mPart + (mPart - Canvas.TextWidth(TAtlasQuickActionTexts.cMenuArrow)) div 2,
    AArea.Top + (AArea.Height - Canvas.TextHeight(TAtlasQuickActionTexts.cMenuArrow)) div 2,
    TAtlasQuickActionTexts.cMenuArrow);
end;

procedure TQuickRowPainter.PaintFocus(AIndex: Integer; const AArea: TRect);
var
  mFocus: TRect;
begin
  if HasKeyFocus(Bar) and (Row = Bar.FSelection.KeyRow) and (AIndex = Bar.FSelection.KeyButton) then
  begin
    mFocus := AArea;
    InflateRect(mFocus, -2, -2);
    Canvas.Brush.Style := bsSolid;
    Canvas.DrawFocusRect(mFocus);
    Canvas.Brush.Style := bsClear;
  end;
end;

procedure TQuickRowPainter.PaintButton(AIndex: Integer);
var
  mArea: TRect;
begin
  mArea := Bar.FRows.Rects[Row][AIndex];
  PaintFrame(AIndex, mArea);
  PaintCaption(AIndex, mArea);
  PaintFocus(AIndex, mArea);
end;

{ TQuickKeys }

function TQuickKeys.ActionKey(AKey: Word): Boolean;
var
  mAction: TAtlasQuickAction;
  mIndex: Integer;
begin
  Result := (Bar.FSource <> nil) and TAtlasWelcomeQuickActions.ActionForKey(Integer(Vcl.Menus.ShortCut(AKey, Shift)),
    Bar.FSource.BuildKey, Bar.FSource.TestKey, ActionsOf(Bar, Row), mAction);
  if not Result then
  begin
    Exit;
  end;
  mIndex := TAtlasWelcomeQuickActions.IndexOf(Buttons, mAction);
  Bar.FSelection.UseKey := True;
  if mIndex >= 0 then
  begin
    Bar.FSelection.KeyButton := mIndex;
    Bar.Activate(Row, mIndex, False);
  end;
end;

function TQuickKeys.MenuKey: Boolean;
var
  mIndex: Integer;
begin
  mIndex := Bar.FSelection.KeyButton;
  if (mIndex < 0) or (mIndex > High(Buttons)) or not Buttons[mIndex].HasMenu then
  begin
    mIndex := TAtlasWelcomeQuickActions.IndexOf(Buttons, TAtlasQuickAction.Build);
  end;
  if mIndex >= 0 then
  begin
    Bar.FMenus.PopupAt(Row, mIndex);
  end;
  Result := True;
end;

function TQuickKeys.StepRow(AKey: Word): Boolean;
var
  mDelta: Integer;
begin
  mDelta := 1;
  if AKey = VK_UP then
  begin
    mDelta := -1;
  end;
  Bar.FSelection.KeyRow := TAtlasWelcomeQuickActions.MoveRow(Bar.FSelection.KeyRow, mDelta,
    Length(Bar.FRows.Projects));
  Bar.FSelection.KeyButton := -1;
  Bar.FSelection.UseKey := True;
  if (Bar.FSelection.KeyRow <> Row) and Assigned(Bar.FHandlers.SelectRow) then
  begin
    Bar.FHandlers.SelectRow(Bar.FSelection.KeyRow);
  end;
  Result := True;
end;

function TQuickKeys.StepButton(AKey: Word): Boolean;
var
  mDelta: Integer;
begin
  mDelta := 1;
  if AKey = VK_LEFT then
  begin
    mDelta := -1;
  end;
  Bar.FSelection.KeyButton := TAtlasWelcomeQuickActions.MoveButton(Buttons, Bar.FSelection.KeyButton, mDelta);
  Bar.FSelection.UseKey := True;
  Result := True;
end;

function TQuickKeys.Home: Boolean;
begin
  Bar.FSelection.KeyButton := -1;
  Bar.FSelection.UseKey := True;
  Result := True;
end;

function TQuickKeys.Enter: Boolean;
begin
  Bar.FSelection.UseKey := True;
  if (Bar.FSelection.KeyButton >= 0) and (Bar.FSelection.KeyButton <= High(Buttons)) then
  begin
    Bar.Activate(Row, Bar.FSelection.KeyButton, False);
  end
  else if Assigned(Bar.FHandlers.OpenRow) then
  begin
    Bar.FHandlers.OpenRow(Row);
  end;
  Result := True;
end;

function TQuickKeys.Escape: Boolean;
begin
  Result := Bar.FSelection.KeyButton >= 0;
  if Result then
  begin
    Bar.FSelection.KeyButton := -1;
  end;
end;

function TQuickKeys.ContextMenu: Boolean;
begin
  Result := Assigned(Bar.FHandlers.RowMenu);
  if Result then
  begin
    Bar.FHandlers.RowMenu(Row);
  end;
end;

function TQuickKeys.Handle(AKey: Word): Boolean;
begin
  Result := False;
  case AKey of
    VK_UP, VK_DOWN:
      if (ssAlt in Shift) and (AKey = VK_DOWN) then
      begin
        Result := MenuKey;
      end
      else if Shift = [] then
      begin
        Result := StepRow(AKey);
      end;
    VK_LEFT, VK_RIGHT:
      Result := (Shift = []) and StepButton(AKey);
    VK_HOME:
      Result := (Shift = []) and Home;
    VK_RETURN, VK_SPACE:
      Result := (Shift = []) and Enter;
    VK_ESCAPE:
      Result := Escape;
    VK_APPS, VK_F10:
      Result := ((AKey = VK_APPS) or (Shift = [ssShift])) and ContextMenu;
  end;
end;

{ TAtlasQuickActionsMenus }

constructor TAtlasQuickActionsMenus.Create(ABar: TAtlasQuickActionsBar);
begin
  inherited Create(ABar);
  FBar := ABar;
  FContextRow := -1;
  FPopup := TPopupMenu.Create(Self);
end;

procedure TAtlasQuickActionsMenus.PopupAt(ARow, AIndex: Integer);
var
  mArea: TRect;
  mPosition: TPoint;
begin
  if not FillChoices(FPopup.Items, ARow, AIndex) then
  begin
    Exit;
  end;
  mArea := Rect(0, 0, 0, 0);
  if (ARow <= High(FBar.FRows.Rects)) and (AIndex <= High(FBar.FRows.Rects[ARow])) then
  begin
    mArea := FBar.FRows.Rects[ARow][AIndex];
  end;
  mPosition := Point(mArea.Left, mArea.Bottom);
  if FBar.FBox <> nil then
  begin
    mPosition := FBar.FBox.ClientToScreen(mPosition);
  end;
  FPopup.Popup(mPosition.X, mPosition.Y);
end;

procedure TAtlasQuickActionsMenus.AddChoice(AParent: TMenuItem; const ACaption: string; const AChoice: TChoice;
  ADefault: Boolean);
var
  mItem: TMenuItem;
begin
  FChoices := FChoices + [AChoice];
  mItem := TMenuItem.Create(FPopup);
  mItem.Caption := ACaption;
  mItem.Tag := High(FChoices);
  mItem.Default := ADefault;
  mItem.OnClick := ChoiceClick;
  AParent.Add(mItem);
end;

procedure TAtlasQuickActionsMenus.FillTargets(AParent: TMenuItem; const AProject: string);
var
  mTargets: TAtlasProjectTargets;
  mConfiguration, mPlatform, mWanted, mWantedPlatform: string;
  mChoice: TChoice;
  mText: string;
begin
  mTargets := FBar.FSource.Targets(AProject, mWanted, mWantedPlatform);
  mChoice := Default(TChoice);
  mChoice.Kind := TChoiceKind.Target;
  mChoice.Project := AProject;
  // Erst „wie in der IDE“, dann jede Konfiguration je Plattform; die Vorgabe (zuletzt benutzt) ist fett.
  AddChoice(AParent, TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickTargetsIde), mChoice,
    (mWanted = '') and (mWantedPlatform = ''));
  for mConfiguration in mTargets.Configurations do
  begin
    if Length(mTargets.Platforms) = 0 then
    begin
      mChoice.A := mConfiguration;
      mChoice.B := '';
      mText := mConfiguration;
      if SameText(mConfiguration, mWanted) then
      begin
        mText := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickTargetLast, [mText]);
      end;
      AddChoice(AParent, mText, mChoice, SameText(mConfiguration, mWanted));
      Continue;
    end;
    for mPlatform in mTargets.Platforms do
    begin
      mChoice.A := mConfiguration;
      mChoice.B := mPlatform;
      mText := mConfiguration + cSeparator + mPlatform;
      if SameText(mConfiguration, mWanted) and SameText(mPlatform, mWantedPlatform) then
      begin
        mText := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickTargetLast, [mText]);
      end;
      AddChoice(AParent, mText, mChoice, SameText(mConfiguration, mWanted) and SameText(mPlatform, mWantedPlatform));
    end;
  end;
end;

procedure TAtlasQuickActionsMenus.FillProfiles(AParent: TMenuItem; const AProject: string);
var
  mNames: TArray<string>;
  mName, mActive, mText: string;
  mChoice: TChoice;
begin
  mNames := FBar.FSource.Profiles(AProject, mActive);
  mChoice := Default(TChoice);
  mChoice.Kind := TChoiceKind.Profile;
  mChoice.Project := AProject;
  for mName in mNames do
  begin
    mChoice.A := mName;
    mText := mName;
    if SameText(mName, mActive) then
    begin
      mText := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickProfileActive, [mName]);
    end;
    AddChoice(AParent, mText, mChoice, SameText(mName, mActive));
  end;
  mChoice.A := '';
  AddChoice(AParent, TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickProfileNone), mChoice, mActive = '');
end;

procedure TAtlasQuickActionsMenus.FillTestProjects(AParent: TMenuItem; const AProject: string;
  const ACandidates: TArray<string>);
var
  mCandidate: string;
  mChoice: TChoice;
begin
  mChoice := Default(TChoice);
  mChoice.Kind := TChoiceKind.TestProject;
  mChoice.Project := AProject;
  for mCandidate in ACandidates do
  begin
    mChoice.A := mCandidate;
    AddChoice(AParent, ChangeFileExt(ExtractFileName(mCandidate), ''), mChoice, False);
  end;
end;

procedure TAtlasQuickActionsMenus.FillTasks(AParent: TMenuItem; const AProject: string);
var
  mName: string;
  mChoice: TChoice;
begin
  mChoice := Default(TChoice);
  mChoice.Kind := TChoiceKind.Task;
  mChoice.Project := AProject;
  for mName in FBar.FSource.TaskNames(AProject) do
  begin
    mChoice.A := mName;
    AddChoice(AParent, mName, mChoice, False);
  end;
end;

procedure TAtlasQuickActionsMenus.FillUpdate(AParent: TMenuItem; const AProject: string);
var
  mChoice: TChoice;
begin
  mChoice := Default(TChoice);
  mChoice.Kind := TChoiceKind.Update;
  mChoice.Project := AProject;
  mChoice.A := 'with';
  AddChoice(AParent, TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickUpdateWithExternals), mChoice, True);
  mChoice.A := 'without';
  AddChoice(AParent, TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickUpdateWithoutExternals), mChoice, False);
end;

procedure TAtlasQuickActionsMenus.AddTitle(AParent: TMenuItem; AId: TAtlasWelcomeTextId);
var
  mItem: TMenuItem;
begin
  // Überschrift der aufgeklappten Auswahl (nicht im Untermenü des Kontextmenüs).
  if AParent <> FPopup.Items then
  begin
    Exit;
  end;
  mItem := TMenuItem.Create(FPopup);
  mItem.Caption := TAtlasWelcomeStrings.Text(AId);
  mItem.Enabled := False;
  AParent.Add(mItem);
  mItem := TMenuItem.Create(FPopup);
  mItem.Caption := '-';
  AParent.Add(mItem);
end;

function TAtlasQuickActionsMenus.FillFor(AParent: TMenuItem; const AButton: TAtlasQuickActionButton;
  const AProject: string): Boolean;
var
  mCandidates: TArray<string>;
begin
  case AButton.Action of
    TAtlasQuickAction.Build:
      begin
        AddTitle(AParent, TAtlasWelcomeTextId.WelcomeQuickTargetsTitle);
        FillTargets(AParent, AProject);
      end;
    TAtlasQuickAction.Run:
      begin
        AddTitle(AParent, TAtlasWelcomeTextId.WelcomeQuickProfilesTitle);
        FillProfiles(AParent, AProject);
      end;
    TAtlasQuickAction.Tests:
      begin
        mCandidates := FBar.FSource.TestProjects(AProject);
        if Length(mCandidates) >= 2 then
        begin
          AddTitle(AParent, TAtlasWelcomeTextId.WelcomeQuickTestsChoose);
          FillTestProjects(AParent, AProject, mCandidates);
        end;
      end;
    TAtlasQuickAction.Tasks:
      if Length(FBar.FSource.TaskNames(AProject)) > 0 then
      begin
        AddTitle(AParent, TAtlasWelcomeTextId.WelcomeQuickTasksTitle);
        FillTasks(AParent, AProject);
      end;
    TAtlasQuickAction.Pull:
      if AButton.AskExternals then
      begin
        AddTitle(AParent, TAtlasWelcomeTextId.WelcomeQuickUpdate);
        FillUpdate(AParent, AProject);
      end;
  else
    // Ordner und Konsole ohne Auswahl.
  end;
  Result := AParent.Count > 0;
end;

function TAtlasQuickActionsMenus.FillChoices(AParent: TMenuItem; ARow, AIndex: Integer): Boolean;
var
  mButtons: TAtlasQuickActionButtons;
begin
  Result := False;
  mButtons := FBar.ButtonsOf(ARow);
  if (FBar.FSource = nil) or (AIndex < 0) or (AIndex > High(mButtons)) or not mButtons[AIndex].Enabled then
  begin
    Exit;
  end;
  AParent.Clear;
  if AParent = FPopup.Items then
  begin
    FChoices := nil;
  end;
  Result := FillFor(AParent, mButtons[AIndex], FBar.FRows.Projects[ARow]);
end;

procedure TAtlasQuickActionsMenus.ChoiceClick(Sender: TObject);
var
  mChoice: TChoice;
  mSource: IAtlasQuickActionsSource;
  mIndex: Integer;
begin
  mIndex := TMenuItem(Sender).Tag;
  if (FBar.FSource = nil) or (mIndex < 0) or (mIndex > High(FChoices)) then
  begin
    Exit;
  end;
  mChoice := FChoices[mIndex];
  mSource := FBar.FSource;
  QueueOnMain(
    procedure
    begin
      case mChoice.Kind of
        TChoiceKind.Target:
          mSource.Build(mChoice.Project, mChoice.A, mChoice.B);
        TChoiceKind.Profile:
          mSource.Run(mChoice.Project, mChoice.A);
        TChoiceKind.Task:
          mSource.RunTask(mChoice.Project, mChoice.A);
        TChoiceKind.Update:
          mSource.Pull(mChoice.Project, mChoice.A = 'without');
      else
        mSource.RunTests(mChoice.Project, mChoice.A);
      end;
    end);
end;

procedure TAtlasQuickActionsMenus.AddContextItem(AMenu: TPopupMenu; AAction: TAtlasQuickAction;
  const ACaption: string);
var
  mItem: TMenuItem;
begin
  mItem := TMenuItem.Create(AMenu);
  mItem.Caption := ACaption;
  mItem.Tag := Length(FContextItems);
  mItem.OnClick := ContextClick;
  FContextItems := FContextItems + [mItem];
  FContextActions := FContextActions + [AAction];
  AMenu.Items.Add(mItem);
end;

function TAtlasQuickActionsMenus.AddSubmenu(AMenu: TPopupMenu; AId: TAtlasWelcomeTextId): TMenuItem;
begin
  Result := TMenuItem.Create(AMenu);
  Result.Caption := TAtlasWelcomeStrings.Text(AId);
  AMenu.Items.Add(Result);
end;

procedure TAtlasQuickActionsMenus.Attach(AMenu: TPopupMenu);
begin
  FContextSeparator := TMenuItem.Create(AMenu);
  FContextSeparator.Caption := '-';
  AMenu.Items.Add(FContextSeparator);
  AddContextItem(AMenu, TAtlasQuickAction.Build, QuickActionTitle(TAtlasQuickAction.Build));
  FBuildWithItem := AddSubmenu(AMenu, TAtlasWelcomeTextId.WelcomeQuickMenuBuildWith);
  AddContextItem(AMenu, TAtlasQuickAction.Tests, QuickActionTitle(TAtlasQuickAction.Tests));
  FRunWithItem := AddSubmenu(AMenu, TAtlasWelcomeTextId.WelcomeQuickMenuRunWith);
  AddContextItem(AMenu, TAtlasQuickAction.Pull, QuickActionTitle(TAtlasQuickAction.Pull));
  AddContextItem(AMenu, TAtlasQuickAction.Console,
    TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickMenuConsole));
  FTasksItem := AddSubmenu(AMenu, TAtlasWelcomeTextId.WelcomeQuickMenuTasks);
end;

procedure TAtlasQuickActionsMenus.PreparePull(AItem: TMenuItem; const AButtons: TAtlasQuickActionButtons; ARow,
  AFound: Integer);
begin
  if AFound < 0 then
  begin
    AItem.Clear;
    Exit;
  end;
  if AButtons[AFound].Update then
  begin
    AItem.Caption := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickUpdate);
  end
  else
  begin
    AItem.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickPull);
  end;
  // Untermenü „mit Externals“/„ohne Externals“ (#1292); ohne Auswahl ein einfacher Eintrag.
  if not (AButtons[AFound].Enabled and AButtons[AFound].AskExternals and FillChoices(AItem, ARow, AFound)) then
  begin
    AItem.Clear;
  end;
end;

function TAtlasQuickActionsMenus.PrepareSubmenu(AItem: TMenuItem; const AButtons: TAtlasQuickActionButtons;
  ARow: Integer; AAction: TAtlasQuickAction): Boolean;
var
  mFound: Integer;
begin
  Result := False;
  if AItem = nil then
  begin
    Exit;
  end;
  mFound := TAtlasWelcomeQuickActions.IndexOf(AButtons, AAction);
  AItem.Visible := (mFound >= 0) and FillChoices(AItem, ARow, mFound);
  AItem.Enabled := AItem.Visible;
  Result := AItem.Visible;
end;

procedure TAtlasQuickActionsMenus.Prepare(ARow: Integer);
var
  mButtons: TAtlasQuickActionButtons;
  mIndex, mFound: Integer;
  mItem: TMenuItem;
  mAny: Boolean;
begin
  FContextRow := ARow;
  mButtons := FBar.ButtonsOf(ARow);
  mAny := False;
  FChoices := nil;
  for mIndex := 0 to High(FContextItems) do
  begin
    mItem := FContextItems[mIndex];
    mFound := TAtlasWelcomeQuickActions.IndexOf(mButtons, FContextActions[mIndex]);
    mItem.Visible := mFound >= 0;
    mItem.Enabled := (mFound >= 0) and mButtons[mFound].Enabled;
    if FContextActions[mIndex] = TAtlasQuickAction.Pull then
    begin
      PreparePull(mItem, mButtons, ARow, mFound);
    end;
    mAny := mAny or mItem.Visible;
  end;
  // Untermenüs „Bauen mit“ und „Starten mit“ mit der Auswahl der Zeile.
  PrepareSubmenu(FBuildWithItem, mButtons, ARow, TAtlasQuickAction.Build);
  PrepareSubmenu(FRunWithItem, mButtons, ARow, TAtlasQuickAction.Run);
  // Untermenü „Aufgabe ausführen“ mit den Projektaufgaben (#900).
  mAny := PrepareSubmenu(FTasksItem, mButtons, ARow, TAtlasQuickAction.Tasks) or mAny;
  if FContextSeparator <> nil then
  begin
    FContextSeparator.Visible := mAny;
  end;
end;

procedure TAtlasQuickActionsMenus.ContextClick(Sender: TObject);
var
  mIndex, mFound: Integer;
begin
  mIndex := TMenuItem(Sender).Tag;
  if (mIndex < 0) or (mIndex > High(FContextActions)) then
  begin
    Exit;
  end;
  mFound := TAtlasWelcomeQuickActions.IndexOf(FBar.ButtonsOf(FContextRow), FContextActions[mIndex]);
  if mFound >= 0 then
  begin
    FBar.Activate(FContextRow, mFound, False);
  end;
end;

{ TAtlasQuickActionsBar }

constructor TAtlasQuickActionsBar.Create(AOwner: TComponent; ABox: TAtlasWelcomeCanvas; AParent: TWinControl);
begin
  inherited Create(AOwner);
  FBox := ABox;
  FSelection.HoverRow := -1;
  FSelection.HoverButton := -1;
  FSelection.KeyRow := -1;
  FSelection.KeyButton := -1;
  FSink := TAtlasQuickKeySink.Create(Self);
  FSink.Parent := AParent;
  FSink.OnKey := HandleKey;
  FSink.OnFocusChange := SinkFocusChange;
  FTimer := TTimer.Create(Self);
  FTimer.Interval := cTickMs;
  FTimer.Enabled := False;
  FTimer.OnTimer := TimerTick;
  FMenus := TAtlasQuickActionsMenus.Create(Self);
end;

destructor TAtlasQuickActionsBar.Destroy;
begin
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  FSource := nil;
  inherited;
end;

procedure TAtlasQuickActionsBar.SetSource(const AValue: IAtlasQuickActionsSource);
begin
  FSource := AValue;
  SetRows(FRows.Projects);
end;

function TAtlasQuickActionsBar.Active: Boolean;
begin
  Result := (FSource <> nil) and FSource.Enabled;
end;

procedure TAtlasQuickActionsBar.SetRows(const AProjects: TArray<string>);
var
  mRow: Integer;
  mOn: Boolean;
begin
  FRows.Projects := AProjects;
  mOn := Active;
  SetLength(FRows.Buttons, Length(AProjects));
  SetLength(FRows.States, Length(AProjects));
  SetLength(FRows.Rects, Length(AProjects));
  for mRow := 0 to High(AProjects) do
  begin
    FRows.Buttons[mRow] := nil;
    FRows.States[mRow] := TAtlasQuickActionState.Idle;
    FRows.Rects[mRow] := nil;
    if FSource = nil then
    begin
      Continue;
    end;
    // Der Stand gilt auch ohne Knöpfe (Ergebnis einer Aktion vor dem Ausschalten).
    FRows.States[mRow] := FSource.State(AProjects[mRow]);
    if mOn then
    begin
      FRows.Buttons[mRow] := FSource.Buttons(AProjects[mRow]);
    end;
  end;
  if FSource <> nil then
  begin
    FRows.NowMs := FSource.NowMs;
  end;
  if FSelection.KeyRow > High(AProjects) then
  begin
    FSelection.KeyRow := High(AProjects);
  end;
  if FSelection.HoverRow > High(AProjects) then
  begin
    FSelection.HoverRow := -1;
  end;
  if IsRow(Self, FSelection.KeyRow) and (FSelection.KeyButton > High(FRows.Buttons[FSelection.KeyRow])) then
  begin
    FSelection.KeyButton := -1;
  end;
  FSelection.HoverButton := -1;
  FSink.TabStop := mOn and (Length(AProjects) > 0);
  UpdateTimer(Self);
  InvalidateBox(Self);
end;

procedure TAtlasQuickActionsBar.TimerTick(Sender: TObject);
var
  mRow: Integer;
begin
  try
    // „baut … 12 s“ weiterzählen; Ende und Ergebnis meldet die Quelle über den Bereich.
    if FSource = nil then
    begin
      FTimer.Enabled := False;
      Exit;
    end;
    FRows.NowMs := FSource.NowMs;
    for mRow := 0 to High(FRows.Projects) do
    begin
      FRows.States[mRow] := FSource.State(FRows.Projects[mRow]);
    end;
    UpdateTimer(Self);
    InvalidateBox(Self);
  except
    on E: Exception do
    begin
      FTimer.Enabled := False;
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
    end;
  end;
end;

function TAtlasQuickActionsBar.ButtonsOf(ARow: Integer): TAtlasQuickActionButtons;
begin
  Result := nil;
  if IsRow(Self, ARow) and Active then
  begin
    Result := FRows.Buttons[ARow];
  end;
end;

function TAtlasQuickActionsBar.StateOf(ARow: Integer): TAtlasQuickActionState;
begin
  Result := TAtlasQuickActionState.Idle;
  if IsRow(Self, ARow) then
  begin
    Result := FRows.States[ARow];
  end;
end;

function TAtlasQuickActionsBar.ActiveRow: Integer;
begin
  Result := -1;
  if not Active or (Length(FRows.Projects) = 0) then
  begin
    Exit;
  end;
  if FSelection.UseKey and HasKeyFocus(Self) and IsRow(Self, FSelection.KeyRow) then
  begin
    Result := FSelection.KeyRow;
  end
  else if IsRow(Self, FSelection.HoverRow) then
  begin
    Result := FSelection.HoverRow;
  end
  else if HasKeyFocus(Self) and IsRow(Self, FSelection.KeyRow) then
  begin
    Result := FSelection.KeyRow;
  end;
  if (Result >= 0) and (Length(FRows.Buttons[Result]) = 0) then
  begin
    Result := -1;
  end;
end;

procedure TAtlasQuickActionsBar.SinkFocusChange(Sender: TObject);
begin
  // Mit dem Fokus kommt eine Zeile; ohne gewählte die erste.
  if HasKeyFocus(Self) and not IsRow(Self, FSelection.KeyRow) and (Length(FRows.Projects) > 0) then
  begin
    FSelection.KeyRow := 0;
  end;
  InvalidateBox(Self);
end;

procedure TAtlasQuickActionsBar.MouseMove(ARow, AX, AY: Integer);
var
  mRow, mIndex, mOldButton: Integer;
  mMenu, mChanged: Boolean;
begin
  mChanged := ARow <> FSelection.HoverRow;
  // Maus in eine andere Zeile: Sie wird die aktive.
  if mChanged then
  begin
    FSelection.UseKey := False;
  end;
  FSelection.HoverRow := ARow;
  mOldButton := FSelection.HoverButton;
  if not HitTest(AX, AY, mRow, mIndex, mMenu) or (mRow <> ARow) then
  begin
    mIndex := -1;
  end;
  FSelection.HoverButton := mIndex;
  if mChanged or (mOldButton <> mIndex) then
  begin
    InvalidateBox(Self);
  end;
end;

procedure TAtlasQuickActionsBar.MouseLeave;
begin
  if (FSelection.HoverRow < 0) and (FSelection.HoverButton < 0) then
  begin
    Exit;
  end;
  FSelection.HoverRow := -1;
  FSelection.HoverButton := -1;
  InvalidateBox(Self);
end;

procedure TAtlasQuickActionsBar.MouseDown(ARow: Integer);
begin
  if not Active then
  begin
    Exit;
  end;
  if IsRow(Self, ARow) then
  begin
    FSelection.KeyRow := ARow;
    FSelection.KeyButton := -1;
  end;
  FSelection.UseKey := False;
  if FSink.CanFocus and not FSink.Focused and (GetParentForm(FSink) <> nil) and GetParentForm(FSink).Visible then
  begin
    FSink.SetFocus;
  end;
end;

function TAtlasQuickActionsBar.LayoutRow(ACanvas: TCanvas; ARow: Integer; const AArea: TRect): Integer;
var
  mButtons: TAtlasQuickActionButtons;
  mLayout: TQuickRowLayout;
  mIndex, mHeight: Integer;
begin
  Result := AArea.Right;
  mButtons := ButtonsOf(ARow);
  if not IsRow(Self, ARow) then
  begin
    Exit;
  end;
  FRows.Rects[ARow] := nil;
  if Length(mButtons) = 0 then
  begin
    Exit;
  end;
  mLayout.Area := AArea;
  mLayout.Gap := ScaleOf(Self, cButtonGap);
  SetLength(mLayout.Widths, Length(mButtons));
  SetLength(mLayout.Rects, Length(mButtons));
  for mIndex := 0 to High(mButtons) do
  begin
    mLayout.Widths[mIndex] := ACanvas.TextWidth(TAtlasQuickActionTexts.Caption(mButtons[mIndex], FRows.States[ARow],
      FRows.NowMs)) + 2 * ScaleOf(Self, cButtonPadding);
    if mButtons[mIndex].Action = TAtlasQuickAction.Build then
    begin
      Inc(mLayout.Widths[mIndex], ScaleOf(Self, cMenuPart));
    end;
  end;
  mHeight := ScaleOf(Self, cButtonHeight);
  if (mLayout.Span(0, High(mButtons)) <= AArea.Width) or (Length(mButtons) < 2) then
  begin
    mLayout.Place(0, High(mButtons), AArea.Top + (AArea.Height - mHeight) div 2, mHeight);
  end
  else
  begin
    mLayout.PlaceTwoLines(ScaleOf(Self, cLineGap), mHeight);
  end;
  Result := mLayout.LeftEdge;
  FRows.Rects[ARow] := mLayout.Rects;
end;

procedure TAtlasQuickActionsBar.PaintBackground(ACanvas: TCanvas; ARow: Integer; const ARowRect: TRect);
var
  mFocus: TRect;
begin
  if ARow = ActiveRow then
  begin
    // Wie im Mockup: Die aktive Zeile ist hinterlegt.
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := StyleServices(FBox).GetSystemColor(clBtnFace);
    ACanvas.FillRect(ARowRect);
    ACanvas.Brush.Style := bsClear;
  end;
  if HasKeyFocus(Self) and (ARow = FSelection.KeyRow) and (FSelection.KeyButton < 0) then
  begin
    mFocus := ARowRect;
    InflateRect(mFocus, -1, -1);
    ACanvas.Brush.Style := bsSolid;
    ACanvas.DrawFocusRect(mFocus);
    ACanvas.Brush.Style := bsClear;
  end;
end;

procedure TAtlasQuickActionsBar.PaintRow(ACanvas: TCanvas; ARow: Integer);
var
  mPainter: TQuickRowPainter;
  mIndex: Integer;
begin
  if not IsRow(Self, ARow) then
  begin
    Exit;
  end;
  mPainter.Buttons := ButtonsOf(ARow);
  if Length(FRows.Rects[ARow]) <> Length(mPainter.Buttons) then
  begin
    Exit;
  end;
  mPainter.Bar := Self;
  mPainter.Canvas := ACanvas;
  mPainter.Row := ARow;
  mPainter.Colors.Text := StyleServices(FBox).GetSystemColor(clWindowText);
  mPainter.Colors.Muted := StyleServices(FBox).GetSystemColor(clGrayText);
  mPainter.Colors.Line := StyleServices(FBox).GetSystemColor(clBtnShadow);
  mPainter.Colors.Accent := StyleServices(FBox).GetSystemColor(clHighlight);
  mPainter.Colors.AccentText := StyleServices(FBox).GetSystemColor(clHighlightText);
  for mIndex := 0 to High(mPainter.Buttons) do
  begin
    mPainter.PaintButton(mIndex);
  end;
end;

function TAtlasQuickActionsBar.HitTest(AX, AY: Integer; out ARow, AIndex: Integer; out AMenu: Boolean): Boolean;
var
  mRects: TArray<TRect>;
  mIndex: Integer;
begin
  ARow := ActiveRow;
  AIndex := -1;
  AMenu := False;
  Result := False;
  if not IsRow(Self, ARow) then
  begin
    Exit;
  end;
  mRects := FRows.Rects[ARow];
  if Length(mRects) <> Length(FRows.Buttons[ARow]) then
  begin
    Exit;
  end;
  for mIndex := 0 to High(mRects) do
  begin
    if mRects[mIndex].Contains(Point(AX, AY)) then
    begin
      AIndex := mIndex;
      AMenu := (FRows.Buttons[ARow][mIndex].Action = TAtlasQuickAction.Build) and
        (AX >= mRects[mIndex].Right - ScaleOf(Self, cMenuPart));
      Exit(True);
    end;
  end;
end;

function TAtlasQuickActionsBar.ClickAt(AX, AY: Integer): Boolean;
var
  mRow, mIndex: Integer;
  mMenu: Boolean;
begin
  Result := HitTest(AX, AY, mRow, mIndex, mMenu);
  if Result then
  begin
    Activate(mRow, mIndex, mMenu);
  end;
end;

procedure TAtlasQuickActionsBar.Activate(ARow, AIndex: Integer; AMenu: Boolean);
var
  mSource: IAtlasQuickActionsSource;
  mButton: TAtlasQuickActionButton;
  mName: string;
begin
  if (FSource = nil) or (AIndex < 0) or (AIndex > High(ButtonsOf(ARow))) or
    not FRows.Buttons[ARow][AIndex].Enabled then
  begin
    Exit;
  end;
  mButton := FRows.Buttons[ARow][AIndex];
  mSource := FSource;
  mName := FRows.Projects[ARow];
  if NeedsChoice(mButton, AMenu, mSource, mName) then
  begin
    FMenus.PopupAt(ARow, AIndex);
    Exit;
  end;
  QueueOnMain(
    procedure
    begin
      mSource.Execute(mName, mButton.Action);
    end);
end;

function TAtlasQuickActionsBar.HintAt(AX, AY: Integer; out AHint: string): Boolean;
var
  mRow, mIndex, mKey: Integer;
  mMenu: Boolean;
  mButton: TAtlasQuickActionButton;
  mConsole: string;
begin
  AHint := '';
  Result := HitTest(AX, AY, mRow, mIndex, mMenu);
  if not Result then
  begin
    Exit;
  end;
  mButton := FRows.Buttons[mRow][mIndex];
  mKey := 0;
  mConsole := '';
  if FSource <> nil then
  begin
    if mButton.Action = TAtlasQuickAction.Build then
    begin
      mKey := FSource.BuildKey;
    end
    else if mButton.Action = TAtlasQuickAction.Tests then
    begin
      mKey := FSource.TestKey;
    end;
    mConsole := FSource.ConsoleProgram;
  end;
  AHint := TAtlasQuickActionTexts.ButtonHint(mButton, FRows.States[mRow].Running, mKey, mConsole);
end;

function TAtlasQuickActionsBar.HandleKey(AKey: Word; AShift: TShiftState): Boolean;
var
  mKeys: TQuickKeys;
begin
  Result := False;
  if not Active or (Length(FRows.Projects) = 0) then
  begin
    Exit;
  end;
  if not IsRow(Self, FSelection.KeyRow) then
  begin
    FSelection.KeyRow := 0;
  end;
  mKeys.Bar := Self;
  mKeys.Row := FSelection.KeyRow;
  mKeys.Buttons := ButtonsOf(mKeys.Row);
  mKeys.Shift := AShift * [ssShift, ssAlt, ssCtrl];
  Result := mKeys.ActionKey(AKey) or mKeys.Handle(AKey);
  if Result then
  begin
    InvalidateBox(Self);
  end;
end;

end.
