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

  /// <summary>Knopfleiste, Stand und Tastatur für die Zeilen eines Bereichs. Der Bereich meldet Zeilen
  /// (Projekte), Maus und Zeichnen; die Leiste ruft die Quelle.</summary>
  TAtlasQuickActionsBar = class(TComponent)
  public const
    ButtonHeight = 20;
    ButtonPadding = 8;
    ButtonGap = 4;
    LineGap = 2;
    /// <summary>Breite des Teils ▾ von „Öffnen und bauen“.</summary>
    MenuPart = 16;
    TickMs = 1000;
  private type
    TChoiceKind = (Target, Profile, TestProject, Task, Update);
    TChoice = record
      Kind: TChoiceKind;
      Project: string;
      A: string;
      B: string;
    end;
  private
    FBox: TAtlasWelcomeCanvas;
    FSink: TAtlasQuickKeySink;
    FSource: IAtlasQuickActionsSource;
    FTimer: TTimer;
    FMenu: TPopupMenu;
    FScale: TAtlasQuickScale;
    FProjects: TArray<string>;
    FButtons: TArray<TAtlasQuickActionButtons>;
    FStates: TArray<TAtlasQuickActionState>;
    FRects: TArray<TArray<TRect>>;
    FChoices: TArray<TChoice>;
    FHoverRow: Integer;
    FHoverButton: Integer;
    FKeyRow: Integer;
    FKeyButton: Integer;
    // Letzte Eingabe kam von der Tastatur: Die gewählte Zeile ist die aktive, nicht die unter der Maus.
    FUseKey: Boolean;
    FNowMs: UInt64;
    FOnOpenRow: TAtlasQuickRowProc;
    FOnRowMenu: TAtlasQuickRowProc;
    FOnSelectRow: TAtlasQuickRowProc;
    FContextItems: TArray<TMenuItem>;
    FContextActions: TArray<TAtlasQuickAction>;
    FBuildWithItem: TMenuItem;
    FRunWithItem: TMenuItem;
    FTasksItem: TMenuItem;
    FContextSeparator: TMenuItem;
    FContextRow: Integer;
    procedure SetSource(const AValue: IAtlasQuickActionsSource);
    procedure TimerTick(Sender: TObject);
    procedure SinkFocusChange(Sender: TObject);
    function SinkKey(AKey: Word; AShift: TShiftState): Boolean;
    procedure ChoiceClick(Sender: TObject);
    procedure ContextClick(Sender: TObject);
    function Scale(AValue: Integer): Integer;
    function ValidRow(ARow: Integer): Boolean;
    function ItemsOf(ARow: Integer): TAtlasQuickActions;
    procedure Queue(const AProc: TProc);
    procedure AddChoice(AParent: TMenuItem; const ACaption: string; const AChoice: TChoice; ADefault: Boolean);
    procedure AddTitle(AParent: TMenuItem; AId: TAtlasWelcomeTextId);
    procedure FillTargets(AParent: TMenuItem; const AProject: string);
    procedure FillProfiles(AParent: TMenuItem; const AProject: string);
    procedure FillTestProjects(AParent: TMenuItem; const AProject: string; const ACandidates: TArray<string>);
    procedure FillTasks(AParent: TMenuItem; const AProject: string);
    procedure FillUpdate(AParent: TMenuItem; const AProject: string);
    procedure PopupAt(ARow, AIndex: Integer);
    procedure UpdateTimer;
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
    /// <summary>Hat die Tastatur des Bereichs den Fokus?</summary>
    function Focused: Boolean;
    /// <summary>Maus über ARow (-1 = keine Zeile) an X, Y; zeichnet bei Wechsel neu.</summary>
    procedure MouseMove(ARow, X, Y: Integer);
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
    function HitTest(X, Y: Integer; out ARow, AIndex: Integer; out AMenu: Boolean): Boolean;
    /// <summary>Klick an X, Y: True, wenn ein Knopf getroffen war (dann klickt der Bereich nicht).</summary>
    function ClickAt(X, Y: Integer): Boolean;
    /// <summary>Knopf AIndex der Zeile ARow wie geklickt; AMenu: Teil ▾.</summary>
    procedure Activate(ARow, AIndex: Integer; AMenu: Boolean);
    /// <summary>Tooltip des Knopfs an X, Y; False ohne Knopf.</summary>
    function HintAt(X, Y: Integer; out AHint: string): Boolean;
    /// <summary>Taste wie in der Tastatur des Bereichs gedrückt.</summary>
    function HandleKey(AKey: Word; AShift: TShiftState): Boolean;
    /// <summary>Auswahl zu Knopf AIndex der Zeile ARow füllen (Konfiguration × Plattform, Startprofile bzw.
    /// Testprojekte bzw. Projektaufgaben) in AParent; False, wenn es keine Auswahl gibt.</summary>
    function FillChoices(AParent: TMenuItem; ARow, AIndex: Integer): Boolean;
    /// <summary>Einträge der Schnellaktionen unten an AMenu anhängen (Kontextmenü eines Bereichs).</summary>
    procedure AttachMenu(AMenu: TPopupMenu);
    /// <summary>Einträge für ARow sichtbar, gesperrt und Untermenüs gefüllt (vor dem Öffnen des Kontextmenüs).
    /// </summary>
    procedure PrepareMenu(ARow: Integer);
    /// <summary>Beschriftung des Knopfs; während seine Aktion läuft „baut … 12 s“.</summary>
    class function Caption(const AButton: TAtlasQuickActionButton; const AState: TAtlasQuickActionState;
      ANowMs: UInt64): string; static;
    /// <summary>Stand als Text der Marke; '' = keine Marke (etwa nach einem Build: die Build-Marke zeigt ihn).
    /// AUpdate: SVN („aktualisiert …“).</summary>
    class function StateText(const AState: TAtlasQuickActionState; ANowMs: UInt64; AUpdate: Boolean): string;
      static;
    class function StateColor(const AState: TAtlasQuickActionState): TColor; static;
    /// <summary>Tooltip eines Knopfs; AKey: Taste der Aktion (0 = keine), AConsole: Programm der Konsole.</summary>
    class function ButtonHint(const AButton: TAtlasQuickActionButton; ARunning: Boolean; AKey: Integer;
      const AConsole: string): string; static;
    property Source: IAtlasQuickActionsSource read FSource write SetSource;
    property Sink: TAtlasQuickKeySink read FSink;
    property Menu: TPopupMenu read FMenu;
    property Timer: TTimer read FTimer;
    /// <summary>Zeitpunkt der letzten Aktualisierung (ms); 0 ohne Quelle.</summary>
    property NowMs: UInt64 read FNowMs;
    property HoverRow: Integer read FHoverRow;
    property KeyRow: Integer read FKeyRow write FKeyRow;
    property KeyButton: Integer read FKeyButton write FKeyButton;
    property OnScale: TAtlasQuickScale read FScale write FScale;
    /// <summary>Enter ohne gewählten Knopf: Zeile öffnen bzw. fortsetzen.</summary>
    property OnOpenRow: TAtlasQuickRowProc read FOnOpenRow write FOnOpenRow;
    /// <summary>Kontextmenütaste: Kontextmenü der Zeile öffnen.</summary>
    property OnRowMenu: TAtlasQuickRowProc read FOnRowMenu write FOnRowMenu;
    /// <summary>Pfeil auf/ab hat die Zeile gewechselt.</summary>
    property OnSelectRow: TAtlasQuickRowProc read FOnSelectRow write FOnSelectRow;
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

/// <summary>Beschriftung der Aktion AAction (Knopf, Kontextmenü, Optionsdialog) ohne Zustand.</summary>
function QuickActionTitle(AAction: TAtlasQuickAction): string;

implementation

uses
  Vcl.Forms,
  Vcl.Themes,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Vcs.Pull;

const
  Separator = ' · ';
  MenuArrow = #$25BE;

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
  Result := TAtlasQuickActionsBar.StateText(ABar.StateOf(ARow), ABar.NowMs, IsUpdateRow(ABar, ARow));
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

{ TAtlasQuickActionsBar }

constructor TAtlasQuickActionsBar.Create(AOwner: TComponent; ABox: TAtlasWelcomeCanvas; AParent: TWinControl);
begin
  inherited Create(AOwner);
  FBox := ABox;
  FHoverRow := -1;
  FHoverButton := -1;
  FKeyRow := -1;
  FKeyButton := -1;
  FContextRow := -1;
  FSink := TAtlasQuickKeySink.Create(Self);
  FSink.Parent := AParent;
  FSink.OnKey := SinkKey;
  FSink.OnFocusChange := SinkFocusChange;
  FTimer := TTimer.Create(Self);
  FTimer.Interval := TickMs;
  FTimer.Enabled := False;
  FTimer.OnTimer := TimerTick;
  FMenu := TPopupMenu.Create(Self);
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

function TAtlasQuickActionsBar.Scale(AValue: Integer): Integer;
begin
  Result := AValue;
  if Assigned(FScale) then
  begin
    Result := FScale(AValue);
  end;
end;

procedure TAtlasQuickActionsBar.SetSource(const AValue: IAtlasQuickActionsSource);
begin
  FSource := AValue;
  SetRows(FProjects);
end;

function TAtlasQuickActionsBar.Active: Boolean;
begin
  Result := (FSource <> nil) and FSource.Enabled;
end;

function TAtlasQuickActionsBar.ValidRow(ARow: Integer): Boolean;
begin
  Result := (ARow >= 0) and (ARow <= High(FProjects));
end;

procedure TAtlasQuickActionsBar.SetRows(const AProjects: TArray<string>);
var
  Row: Integer;
  On: Boolean;
begin
  FProjects := AProjects;
  On := Active;
  SetLength(FButtons, Length(FProjects));
  SetLength(FStates, Length(FProjects));
  SetLength(FRects, Length(FProjects));
  for Row := 0 to High(FProjects) do
  begin
    FButtons[Row] := nil;
    FStates[Row] := TAtlasQuickActionState.Idle;
    FRects[Row] := nil;
    if FSource = nil then
    begin
      Continue;
    end;
    // Der Stand gilt auch ohne Knöpfe (Ergebnis einer Aktion vor dem Ausschalten).
    FStates[Row] := FSource.State(FProjects[Row]);
    if On then
    begin
      FButtons[Row] := FSource.Buttons(FProjects[Row]);
    end;
  end;
  if FSource <> nil then
  begin
    FNowMs := FSource.NowMs;
  end;
  if FKeyRow > High(FProjects) then
  begin
    FKeyRow := High(FProjects);
  end;
  if FHoverRow > High(FProjects) then
  begin
    FHoverRow := -1;
  end;
  if ValidRow(FKeyRow) and (FKeyButton > High(FButtons[FKeyRow])) then
  begin
    FKeyButton := -1;
  end;
  FHoverButton := -1;
  FSink.TabStop := On and (Length(FProjects) > 0);
  UpdateTimer;
  if FBox <> nil then
  begin
    FBox.Invalidate;
  end;
end;

procedure TAtlasQuickActionsBar.UpdateTimer;
var
  State: TAtlasQuickActionState;
  Running: Boolean;
begin
  Running := False;
  for State in FStates do
  begin
    if State.Running then
    begin
      Running := True;
    end;
  end;
  FTimer.Enabled := Running;
end;

procedure TAtlasQuickActionsBar.TimerTick(Sender: TObject);
var
  Row: Integer;
begin
  try
    // „baut … 12 s“ weiterzählen; Ende und Ergebnis meldet die Quelle über den Bereich.
    if FSource = nil then
    begin
      FTimer.Enabled := False;
      Exit;
    end;
    FNowMs := FSource.NowMs;
    for Row := 0 to High(FProjects) do
    begin
      FStates[Row] := FSource.State(FProjects[Row]);
    end;
    UpdateTimer;
    if FBox <> nil then
    begin
      FBox.Invalidate;
    end;
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
  if ValidRow(ARow) and Active then
  begin
    Result := FButtons[ARow];
  end;
end;

function TAtlasQuickActionsBar.StateOf(ARow: Integer): TAtlasQuickActionState;
begin
  Result := TAtlasQuickActionState.Idle;
  if ValidRow(ARow) then
  begin
    Result := FStates[ARow];
  end;
end;

function TAtlasQuickActionsBar.ItemsOf(ARow: Integer): TAtlasQuickActions;
var
  Button: TAtlasQuickActionButton;
begin
  Result := [];
  for Button in ButtonsOf(ARow) do
  begin
    Include(Result, Button.Action);
  end;
end;

function TAtlasQuickActionsBar.Focused: Boolean;
begin
  Result := FSink.Focused;
end;

function TAtlasQuickActionsBar.ActiveRow: Integer;
begin
  Result := -1;
  if not Active or (Length(FProjects) = 0) then
  begin
    Exit;
  end;
  if FUseKey and Focused and ValidRow(FKeyRow) then
  begin
    Result := FKeyRow;
  end
  else if ValidRow(FHoverRow) then
  begin
    Result := FHoverRow;
  end
  else if Focused and ValidRow(FKeyRow) then
  begin
    Result := FKeyRow;
  end;
  if (Result >= 0) and (Length(FButtons[Result]) = 0) then
  begin
    Result := -1;
  end;
end;

procedure TAtlasQuickActionsBar.SinkFocusChange(Sender: TObject);
begin
  // Mit dem Fokus kommt eine Zeile; ohne gewählte die erste.
  if Focused and not ValidRow(FKeyRow) and (Length(FProjects) > 0) then
  begin
    FKeyRow := 0;
  end;
  if FBox <> nil then
  begin
    FBox.Invalidate;
  end;
end;

procedure TAtlasQuickActionsBar.MouseMove(ARow, X, Y: Integer);
var
  Row, Index, OldButton: Integer;
  mMenu, Changed: Boolean;
begin
  Changed := ARow <> FHoverRow;
  // Maus in eine andere Zeile: Sie wird die aktive.
  if Changed then
  begin
    FUseKey := False;
  end;
  FHoverRow := ARow;
  OldButton := FHoverButton;
  if not HitTest(X, Y, Row, Index, mMenu) or (Row <> ARow) then
  begin
    Index := -1;
  end;
  FHoverButton := Index;
  if (Changed or (OldButton <> Index)) and (FBox <> nil) then
  begin
    FBox.Invalidate;
  end;
end;

procedure TAtlasQuickActionsBar.MouseLeave;
begin
  if (FHoverRow < 0) and (FHoverButton < 0) then
  begin
    Exit;
  end;
  FHoverRow := -1;
  FHoverButton := -1;
  if FBox <> nil then
  begin
    FBox.Invalidate;
  end;
end;

procedure TAtlasQuickActionsBar.MouseDown(ARow: Integer);
begin
  if not Active then
  begin
    Exit;
  end;
  if ValidRow(ARow) then
  begin
    FKeyRow := ARow;
    FKeyButton := -1;
  end;
  FUseKey := False;
  if FSink.CanFocus and not FSink.Focused and (GetParentForm(FSink) <> nil) and GetParentForm(FSink).Visible then
  begin
    FSink.SetFocus;
  end;
end;

function TAtlasQuickActionsBar.LayoutRow(ACanvas: TCanvas; ARow: Integer; const AArea: TRect): Integer;
var
  Buttons: TAtlasQuickActionButtons;
  Widths: TArray<Integer>;
  Rects: TArray<TRect>;
  Index, Total, Gap, Height, Split, First, Second, Top, Right, LineHeight: Integer;

  function Span(AFrom, ATo: Integer): Integer;
  var
    I: Integer;
  begin
    Result := 0;
    for I := AFrom to ATo do
    begin
      Inc(Result, Widths[I]);
    end;
    if ATo > AFrom then
    begin
      Inc(Result, (ATo - AFrom) * Gap);
    end;
  end;

  procedure Place(AFrom, ATo, ATop, AHeight: Integer);
  var
    I: Integer;
  begin
    Right := AArea.Right;
    for I := ATo downto AFrom do
    begin
      Rects[I] := Rect(Right - Widths[I], ATop, Right, ATop + AHeight);
      Dec(Right, Widths[I] + Gap);
    end;
  end;

begin
  Result := AArea.Right;
  Buttons := ButtonsOf(ARow);
  if not ValidRow(ARow) then
  begin
    Exit;
  end;
  FRects[ARow] := nil;
  if Length(Buttons) = 0 then
  begin
    Exit;
  end;
  SetLength(Widths, Length(Buttons));
  SetLength(Rects, Length(Buttons));
  for Index := 0 to High(Buttons) do
  begin
    Widths[Index] := ACanvas.TextWidth(Caption(Buttons[Index], FStates[ARow], FNowMs)) + 2 * Scale(ButtonPadding);
    if Buttons[Index].Action = TAtlasQuickAction.Build then
    begin
      Inc(Widths[Index], Scale(MenuPart));
    end;
  end;
  Gap := Scale(ButtonGap);
  Height := Scale(ButtonHeight);
  Total := Span(0, High(Buttons));
  if (Total <= AArea.Width) or (Length(Buttons) < 2) then
  begin
    Place(0, High(Buttons), AArea.Top + (AArea.Height - Height) div 2, Height);
  end
  else
  begin
    // Zwei Zeilen in der Zeilenhöhe: vorne die ersten Knöpfe, so gleichmäßig wie möglich.
    Split := Length(Buttons) div 2;
    for Index := 1 to High(Buttons) do
    begin
      if (Span(0, Index - 1) <= AArea.Width) and (Span(Index, High(Buttons)) <= AArea.Width) then
      begin
        Split := Index;
        Break;
      end;
    end;
    LineHeight := (AArea.Height - Scale(LineGap)) div 2;
    if LineHeight > Height then
    begin
      LineHeight := Height;
    end;
    Top := AArea.Top + (AArea.Height - 2 * LineHeight - Scale(LineGap)) div 2;
    First := Split - 1;
    Second := Split;
    Place(0, First, Top, LineHeight);
    Place(Second, High(Buttons), Top + LineHeight + Scale(LineGap), LineHeight);
  end;
  for Index := 0 to High(Rects) do
  begin
    if Rects[Index].Left < Result then
    begin
      Result := Rects[Index].Left;
    end;
  end;
  FRects[ARow] := Rects;
end;

procedure TAtlasQuickActionsBar.PaintBackground(ACanvas: TCanvas; ARow: Integer; const ARowRect: TRect);
var
  Focus: TRect;
begin
  if ARow = ActiveRow then
  begin
    // Wie im Mockup: Die aktive Zeile ist hinterlegt.
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := StyleServices(FBox).GetSystemColor(clBtnFace);
    ACanvas.FillRect(ARowRect);
    ACanvas.Brush.Style := bsClear;
  end;
  if Focused and (ARow = FKeyRow) and (FKeyButton < 0) then
  begin
    Focus := ARowRect;
    InflateRect(Focus, -1, -1);
    ACanvas.Brush.Style := bsSolid;
    ACanvas.DrawFocusRect(Focus);
    ACanvas.Brush.Style := bsClear;
  end;
end;

procedure TAtlasQuickActionsBar.PaintRow(ACanvas: TCanvas; ARow: Integer);
var
  Buttons: TAtlasQuickActionButtons;
  Rects: TArray<TRect>;
  Index, Radius, Part: Integer;
  Area, Focus: TRect;
  Button: TAtlasQuickActionButton;
  Text: string;
  TextColor, MutedColor, LineColor, AccentColor, AccentText: TColor;
  Primary: Boolean;
begin
  if not ValidRow(ARow) then
  begin
    Exit;
  end;
  Buttons := ButtonsOf(ARow);
  Rects := FRects[ARow];
  if Length(Rects) <> Length(Buttons) then
  begin
    Exit;
  end;
  TextColor := StyleServices(FBox).GetSystemColor(clWindowText);
  MutedColor := StyleServices(FBox).GetSystemColor(clGrayText);
  LineColor := StyleServices(FBox).GetSystemColor(clBtnShadow);
  AccentColor := StyleServices(FBox).GetSystemColor(clHighlight);
  AccentText := StyleServices(FBox).GetSystemColor(clHighlightText);
  Radius := Scale(6);
  Part := Scale(MenuPart);
  for Index := 0 to High(Buttons) do
  begin
    Button := Buttons[Index];
    Area := Rects[Index];
    // „Öffnen und bauen“ ist der Hauptknopf (gefüllt), solange er nutzbar ist.
    Primary := (Button.Action = TAtlasQuickAction.Build) and Button.Enabled;
    if Primary then
    begin
      ACanvas.Brush.Style := bsSolid;
      ACanvas.Brush.Color := AccentColor;
      ACanvas.Pen.Color := AccentColor;
      ACanvas.RoundRect(Area.Left, Area.Top, Area.Right, Area.Bottom, Radius, Radius);
      ACanvas.Font.Color := AccentText;
    end
    else
    begin
      ACanvas.Brush.Style := bsClear;
      if (Index = FHoverButton) and (ARow = FHoverRow) and Button.Enabled then
      begin
        ACanvas.Pen.Color := AccentColor;
      end
      else
      begin
        ACanvas.Pen.Color := LineColor;
      end;
      ACanvas.RoundRect(Area.Left, Area.Top, Area.Right, Area.Bottom, Radius, Radius);
      if Button.Enabled then
      begin
        ACanvas.Font.Color := TextColor;
      end
      else
      begin
        ACanvas.Font.Color := MutedColor;
      end;
    end;
    ACanvas.Brush.Style := bsClear;
    Text := Caption(Button, FStates[ARow], FNowMs);
    if Button.Action = TAtlasQuickAction.Build then
    begin
      // Teil ▾ rechts, durch einen Strich getrennt.
      ACanvas.TextOut(Area.Left + (Area.Width - Part - ACanvas.TextWidth(Text)) div 2,
        Area.Top + (Area.Height - ACanvas.TextHeight(Text)) div 2, Text);
      ACanvas.Pen.Color := ACanvas.Font.Color;
      ACanvas.MoveTo(Area.Right - Part, Area.Top + Scale(4));
      ACanvas.LineTo(Area.Right - Part, Area.Bottom - Scale(4));
      ACanvas.TextOut(Area.Right - Part + (Part - ACanvas.TextWidth(MenuArrow)) div 2,
        Area.Top + (Area.Height - ACanvas.TextHeight(MenuArrow)) div 2, MenuArrow);
    end
    else
    begin
      ACanvas.TextOut(Area.Left + (Area.Width - ACanvas.TextWidth(Text)) div 2,
        Area.Top + (Area.Height - ACanvas.TextHeight(Text)) div 2, Text);
    end;
    if Focused and (ARow = FKeyRow) and (Index = FKeyButton) then
    begin
      Focus := Area;
      InflateRect(Focus, -2, -2);
      ACanvas.Brush.Style := bsSolid;
      ACanvas.DrawFocusRect(Focus);
      ACanvas.Brush.Style := bsClear;
    end;
  end;
end;

function TAtlasQuickActionsBar.HitTest(X, Y: Integer; out ARow, AIndex: Integer; out AMenu: Boolean): Boolean;
var
  Rects: TArray<TRect>;
  Index: Integer;
begin
  ARow := ActiveRow;
  AIndex := -1;
  AMenu := False;
  Result := False;
  if not ValidRow(ARow) then
  begin
    Exit;
  end;
  Rects := FRects[ARow];
  if Length(Rects) <> Length(FButtons[ARow]) then
  begin
    Exit;
  end;
  for Index := 0 to High(Rects) do
  begin
    if Rects[Index].Contains(Point(X, Y)) then
    begin
      AIndex := Index;
      AMenu := (FButtons[ARow][Index].Action = TAtlasQuickAction.Build) and
        (X >= Rects[Index].Right - Scale(MenuPart));
      Exit(True);
    end;
  end;
end;

function TAtlasQuickActionsBar.ClickAt(X, Y: Integer): Boolean;
var
  Row, Index: Integer;
  mMenu: Boolean;
begin
  Result := HitTest(X, Y, Row, Index, mMenu);
  if Result then
  begin
    Activate(Row, Index, mMenu);
  end;
end;

procedure TAtlasQuickActionsBar.Queue(const AProc: TProc);
var
  Proc: TProc;
begin
  Proc := AProc;
  // Die Quelle füllt die Bereiche danach neu: nicht im eigenen Maus- bzw. Tastenereignis.
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      Proc();
    end);
end;

procedure TAtlasQuickActionsBar.Activate(ARow, AIndex: Integer; AMenu: Boolean);
var
  mSource: IAtlasQuickActionsSource;
  Button: TAtlasQuickActionButton;
  mName: string;
  Candidates: TArray<string>;
begin
  if (FSource = nil) or not ValidRow(ARow) or (AIndex < 0) or (AIndex > High(ButtonsOf(ARow))) then
  begin
    Exit;
  end;
  Button := FButtons[ARow][AIndex];
  if not Button.Enabled then
  begin
    Exit;
  end;
  mSource := FSource;
  mName := FProjects[ARow];
  case Button.Action of
    TAtlasQuickAction.Build:
      if AMenu then
      begin
        PopupAt(ARow, AIndex);
        Exit;
      end;
    TAtlasQuickAction.Run, TAtlasQuickAction.Tasks:
      begin
        // „Startprofil ▾“ fragt immer nach dem Profil, „Aufgaben ▾“ nach der Aufgabe.
        PopupAt(ARow, AIndex);
        Exit;
      end;
    TAtlasQuickAction.Tests:
      begin
        Candidates := mSource.TestProjects(mName);
        if Length(Candidates) > 1 then
        begin
          PopupAt(ARow, AIndex);
          Exit;
        end;
      end;
    TAtlasQuickAction.Pull:
      // vcs.externals.update = ask (#1292): erst „mit Externals“ oder „ohne Externals“ wählen.
      if Button.AskExternals then
      begin
        PopupAt(ARow, AIndex);
        Exit;
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
  Queue(
    procedure
    begin
      mSource.Execute(mName, Button.Action);
    end);
end;

procedure TAtlasQuickActionsBar.PopupAt(ARow, AIndex: Integer);
var
  Area: TRect;
  Position: TPoint;
begin
  if not FillChoices(FMenu.Items, ARow, AIndex) then
  begin
    Exit;
  end;
  Area := Rect(0, 0, 0, 0);
  if (ARow <= High(FRects)) and (AIndex <= High(FRects[ARow])) then
  begin
    Area := FRects[ARow][AIndex];
  end;
  Position := Point(Area.Left, Area.Bottom);
  if FBox <> nil then
  begin
    Position := FBox.ClientToScreen(Position);
  end;
  FMenu.Popup(Position.X, Position.Y);
end;

procedure TAtlasQuickActionsBar.AddChoice(AParent: TMenuItem; const ACaption: string; const AChoice: TChoice;
  ADefault: Boolean);
var
  Item: TMenuItem;
begin
  FChoices := FChoices + [AChoice];
  Item := TMenuItem.Create(FMenu);
  Item.Caption := ACaption;
  Item.Tag := High(FChoices);
  Item.Default := ADefault;
  Item.OnClick := ChoiceClick;
  AParent.Add(Item);
end;

procedure TAtlasQuickActionsBar.FillTargets(AParent: TMenuItem; const AProject: string);
var
  Targets: TAtlasProjectTargets;
  Configuration, Platform, Wanted, WantedPlatform: string;
  Choice: TChoice;
  Text: string;
begin
  Targets := FSource.Targets(AProject, Wanted, WantedPlatform);
  Choice := Default(TChoice);
  Choice.Kind := TChoiceKind.Target;
  Choice.Project := AProject;
  // Erst „wie in der IDE“, dann jede Konfiguration je Plattform; die Vorgabe (zuletzt benutzt) ist fett.
  AddChoice(AParent, TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickTargetsIde), Choice,
    (Wanted = '') and (WantedPlatform = ''));
  for Configuration in Targets.Configurations do
  begin
    if Length(Targets.Platforms) = 0 then
    begin
      Choice.A := Configuration;
      Choice.B := '';
      Text := Configuration;
      if SameText(Configuration, Wanted) then
      begin
        Text := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickTargetLast, [Text]);
      end;
      AddChoice(AParent, Text, Choice, SameText(Configuration, Wanted));
      Continue;
    end;
    for Platform in Targets.Platforms do
    begin
      Choice.A := Configuration;
      Choice.B := Platform;
      Text := Configuration + Separator + Platform;
      if SameText(Configuration, Wanted) and SameText(Platform, WantedPlatform) then
      begin
        Text := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickTargetLast, [Text]);
      end;
      AddChoice(AParent, Text, Choice, SameText(Configuration, Wanted) and SameText(Platform, WantedPlatform));
    end;
  end;
end;

procedure TAtlasQuickActionsBar.FillProfiles(AParent: TMenuItem; const AProject: string);
var
  Names: TArray<string>;
  mName, Active, Text: string;
  Choice: TChoice;
begin
  Names := FSource.Profiles(AProject, Active);
  Choice := Default(TChoice);
  Choice.Kind := TChoiceKind.Profile;
  Choice.Project := AProject;
  for mName in Names do
  begin
    Choice.A := mName;
    Text := mName;
    if SameText(mName, Active) then
    begin
      Text := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickProfileActive, [mName]);
    end;
    AddChoice(AParent, Text, Choice, SameText(mName, Active));
  end;
  Choice.A := '';
  AddChoice(AParent, TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickProfileNone), Choice, Active = '');
end;

procedure TAtlasQuickActionsBar.FillTestProjects(AParent: TMenuItem; const AProject: string;
  const ACandidates: TArray<string>);
var
  Candidate: string;
  Choice: TChoice;
begin
  Choice := Default(TChoice);
  Choice.Kind := TChoiceKind.TestProject;
  Choice.Project := AProject;
  for Candidate in ACandidates do
  begin
    Choice.A := Candidate;
    AddChoice(AParent, ChangeFileExt(ExtractFileName(Candidate), ''), Choice, False);
  end;
end;

procedure TAtlasQuickActionsBar.FillTasks(AParent: TMenuItem; const AProject: string);
var
  Name: string;
  Choice: TChoice;
begin
  Choice := Default(TChoice);
  Choice.Kind := TChoiceKind.Task;
  Choice.Project := AProject;
  for Name in FSource.TaskNames(AProject) do
  begin
    Choice.A := Name;
    AddChoice(AParent, Name, Choice, False);
  end;
end;

procedure TAtlasQuickActionsBar.FillUpdate(AParent: TMenuItem; const AProject: string);
var
  Choice: TChoice;
begin
  Choice := Default(TChoice);
  Choice.Kind := TChoiceKind.Update;
  Choice.Project := AProject;
  Choice.A := 'with';
  AddChoice(AParent, TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickUpdateWithExternals), Choice, True);
  Choice.A := 'without';
  AddChoice(AParent, TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickUpdateWithoutExternals), Choice, False);
end;

procedure TAtlasQuickActionsBar.AddTitle(AParent: TMenuItem; AId: TAtlasWelcomeTextId);
var
  Item: TMenuItem;
begin
  // Überschrift der aufgeklappten Auswahl (nicht im Untermenü des Kontextmenüs).
  if AParent <> FMenu.Items then
  begin
    Exit;
  end;
  Item := TMenuItem.Create(FMenu);
  Item.Caption := TAtlasWelcomeStrings.Text(AId);
  Item.Enabled := False;
  AParent.Add(Item);
  Item := TMenuItem.Create(FMenu);
  Item.Caption := '-';
  AParent.Add(Item);
end;

function TAtlasQuickActionsBar.FillChoices(AParent: TMenuItem; ARow, AIndex: Integer): Boolean;
var
  Buttons: TAtlasQuickActionButtons;
  mName: string;
  Candidates: TArray<string>;
begin
  Result := False;
  Buttons := ButtonsOf(ARow);
  if (FSource = nil) or (AIndex < 0) or (AIndex > High(Buttons)) or not Buttons[AIndex].Enabled then
  begin
    Exit;
  end;
  AParent.Clear;
  if AParent = FMenu.Items then
  begin
    FChoices := nil;
  end;
  mName := FProjects[ARow];
  case Buttons[AIndex].Action of
    TAtlasQuickAction.Build:
      begin
        AddTitle(AParent, TAtlasWelcomeTextId.WelcomeQuickTargetsTitle);
        FillTargets(AParent, mName);
      end;
    TAtlasQuickAction.Run:
      begin
        AddTitle(AParent, TAtlasWelcomeTextId.WelcomeQuickProfilesTitle);
        FillProfiles(AParent, mName);
      end;
    TAtlasQuickAction.Tests:
      begin
        Candidates := FSource.TestProjects(mName);
        if Length(Candidates) < 2 then
        begin
          Exit;
        end;
        AddTitle(AParent, TAtlasWelcomeTextId.WelcomeQuickTestsChoose);
        FillTestProjects(AParent, mName, Candidates);
      end;
    TAtlasQuickAction.Tasks:
      begin
        if Length(FSource.TaskNames(mName)) = 0 then
        begin
          Exit;
        end;
        AddTitle(AParent, TAtlasWelcomeTextId.WelcomeQuickTasksTitle);
        FillTasks(AParent, mName);
      end;
    TAtlasQuickAction.Pull:
      begin
        if not Buttons[AIndex].AskExternals then
        begin
          Exit;
        end;
        AddTitle(AParent, TAtlasWelcomeTextId.WelcomeQuickUpdate);
        FillUpdate(AParent, mName);
      end;
  else
    Exit;
  end;
  Result := AParent.Count > 0;
end;

procedure TAtlasQuickActionsBar.ChoiceClick(Sender: TObject);
var
  Choice: TChoice;
  mSource: IAtlasQuickActionsSource;
  Index: Integer;
begin
  Index := TMenuItem(Sender).Tag;
  if (FSource = nil) or (Index < 0) or (Index > High(FChoices)) then
  begin
    Exit;
  end;
  Choice := FChoices[Index];
  mSource := FSource;
  Queue(
    procedure
    begin
      case Choice.Kind of
        TChoiceKind.Target:
          mSource.Build(Choice.Project, Choice.A, Choice.B);
        TChoiceKind.Profile:
          mSource.Run(Choice.Project, Choice.A);
        TChoiceKind.Task:
          mSource.RunTask(Choice.Project, Choice.A);
        TChoiceKind.Update:
          mSource.Pull(Choice.Project, Choice.A = 'without');
      else
        mSource.RunTests(Choice.Project, Choice.A);
      end;
    end);
end;

procedure TAtlasQuickActionsBar.AttachMenu(AMenu: TPopupMenu);

  function Add(AParent: TMenuItem; AAction: TAtlasQuickAction; const ACaption: string): TMenuItem;
  begin
    Result := TMenuItem.Create(AMenu);
    Result.Caption := ACaption;
    Result.Tag := Length(FContextItems);
    Result.OnClick := ContextClick;
    FContextItems := FContextItems + [Result];
    FContextActions := FContextActions + [AAction];
    AParent.Add(Result);
  end;

begin
  FContextSeparator := TMenuItem.Create(AMenu);
  FContextSeparator.Caption := '-';
  AMenu.Items.Add(FContextSeparator);
  Add(AMenu.Items, TAtlasQuickAction.Build, QuickActionTitle(TAtlasQuickAction.Build));
  FBuildWithItem := TMenuItem.Create(AMenu);
  FBuildWithItem.Caption := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickMenuBuildWith);
  AMenu.Items.Add(FBuildWithItem);
  Add(AMenu.Items, TAtlasQuickAction.Tests, QuickActionTitle(TAtlasQuickAction.Tests));
  FRunWithItem := TMenuItem.Create(AMenu);
  FRunWithItem.Caption := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickMenuRunWith);
  AMenu.Items.Add(FRunWithItem);
  Add(AMenu.Items, TAtlasQuickAction.Pull, QuickActionTitle(TAtlasQuickAction.Pull));
  Add(AMenu.Items, TAtlasQuickAction.Console, TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickMenuConsole));
  FTasksItem := TMenuItem.Create(AMenu);
  FTasksItem.Caption := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickMenuTasks);
  AMenu.Items.Add(FTasksItem);
end;

procedure TAtlasQuickActionsBar.PrepareMenu(ARow: Integer);
var
  Buttons: TAtlasQuickActionButtons;
  Index, Found: Integer;
  Item: TMenuItem;
  Any: Boolean;
begin
  FContextRow := ARow;
  Buttons := ButtonsOf(ARow);
  Any := False;
  FChoices := nil;
  for Index := 0 to High(FContextItems) do
  begin
    Item := FContextItems[Index];
    Found := TAtlasWelcomeQuickActions.IndexOf(Buttons, FContextActions[Index]);
    Item.Visible := Found >= 0;
    Item.Enabled := (Found >= 0) and Buttons[Found].Enabled;
    if (Found >= 0) and (FContextActions[Index] = TAtlasQuickAction.Pull) then
    begin
      if Buttons[Found].Update then
      begin
        Item.Caption := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickUpdate);
      end
      else
      begin
        Item.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickPull);
      end;
      // Untermenü „mit Externals“/„ohne Externals“ (#1292); ohne Auswahl ein einfacher Eintrag.
      if not (Buttons[Found].Enabled and Buttons[Found].AskExternals and FillChoices(Item, ARow, Found)) then
      begin
        Item.Clear;
      end;
    end
    else if FContextActions[Index] = TAtlasQuickAction.Pull then
    begin
      Item.Clear;
    end;
    Any := Any or Item.Visible;
  end;
  // Untermenüs „Bauen mit“ und „Starten mit“ mit der Auswahl der Zeile.
  if FBuildWithItem <> nil then
  begin
    Found := TAtlasWelcomeQuickActions.IndexOf(Buttons, TAtlasQuickAction.Build);
    FBuildWithItem.Visible := (Found >= 0) and FillChoices(FBuildWithItem, ARow, Found);
    FBuildWithItem.Enabled := FBuildWithItem.Visible;
  end;
  if FRunWithItem <> nil then
  begin
    Found := TAtlasWelcomeQuickActions.IndexOf(Buttons, TAtlasQuickAction.Run);
    FRunWithItem.Visible := (Found >= 0) and FillChoices(FRunWithItem, ARow, Found);
    FRunWithItem.Enabled := FRunWithItem.Visible;
  end;
  // Untermenü „Aufgabe ausführen“ mit den Projektaufgaben (#900).
  if FTasksItem <> nil then
  begin
    Found := TAtlasWelcomeQuickActions.IndexOf(Buttons, TAtlasQuickAction.Tasks);
    FTasksItem.Visible := (Found >= 0) and FillChoices(FTasksItem, ARow, Found);
    FTasksItem.Enabled := FTasksItem.Visible;
    Any := Any or FTasksItem.Visible;
  end;
  if FContextSeparator <> nil then
  begin
    FContextSeparator.Visible := Any;
  end;
end;

procedure TAtlasQuickActionsBar.ContextClick(Sender: TObject);
var
  Index, Found: Integer;
begin
  Index := TMenuItem(Sender).Tag;
  if (Index < 0) or (Index > High(FContextActions)) then
  begin
    Exit;
  end;
  Found := TAtlasWelcomeQuickActions.IndexOf(ButtonsOf(FContextRow), FContextActions[Index]);
  if Found >= 0 then
  begin
    Activate(FContextRow, Found, False);
  end;
end;

function TAtlasQuickActionsBar.HintAt(X, Y: Integer; out AHint: string): Boolean;
var
  Row, Index, Key: Integer;
  mMenu: Boolean;
  Button: TAtlasQuickActionButton;
  Console: string;
begin
  AHint := '';
  Result := HitTest(X, Y, Row, Index, mMenu);
  if not Result then
  begin
    Exit;
  end;
  Button := FButtons[Row][Index];
  Key := 0;
  Console := '';
  if FSource <> nil then
  begin
    if Button.Action = TAtlasQuickAction.Build then
    begin
      Key := FSource.BuildKey;
    end
    else if Button.Action = TAtlasQuickAction.Tests then
    begin
      Key := FSource.TestKey;
    end;
    Console := FSource.ConsoleProgram;
  end;
  AHint := ButtonHint(Button, FStates[Row].Running, Key, Console);
end;

function TAtlasQuickActionsBar.SinkKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := HandleKey(AKey, AShift);
end;

function TAtlasQuickActionsBar.HandleKey(AKey: Word; AShift: TShiftState): Boolean;
var
  Row, Index: Integer;
  Action: TAtlasQuickAction;
  Buttons: TAtlasQuickActionButtons;
  Shift: TShiftState;
begin
  Result := False;
  if not Active or (Length(FProjects) = 0) then
  begin
    Exit;
  end;
  if not ValidRow(FKeyRow) then
  begin
    FKeyRow := 0;
  end;
  Row := FKeyRow;
  Buttons := ButtonsOf(Row);
  Shift := AShift * [ssShift, ssAlt, ssCtrl];
  // Strg+B, Strg+T (#399: einstellbar) auf der gewählten Zeile.
  if (FSource <> nil) and TAtlasWelcomeQuickActions.ActionForKey(Integer(ShortCut(AKey, Shift)), FSource.BuildKey,
    FSource.TestKey, ItemsOf(Row), Action) then
  begin
    Index := TAtlasWelcomeQuickActions.IndexOf(Buttons, Action);
    FUseKey := True;
    if Index >= 0 then
    begin
      FKeyButton := Index;
      Activate(Row, Index, False);
    end;
    if FBox <> nil then
    begin
      FBox.Invalidate;
    end;
    Exit(True);
  end;
  case AKey of
    VK_UP, VK_DOWN:
      if (ssAlt in Shift) and (AKey = VK_DOWN) then
      begin
        // Alt+↓: Auswahl des gewählten Knopfs, sonst die von „Öffnen und bauen“.
        Index := FKeyButton;
        if (Index < 0) or (Index > High(Buttons)) or not Buttons[Index].HasMenu then
        begin
          Index := TAtlasWelcomeQuickActions.IndexOf(Buttons, TAtlasQuickAction.Build);
        end;
        if Index >= 0 then
        begin
          PopupAt(Row, Index);
        end;
        Result := True;
      end
      else if Shift = [] then
      begin
        if AKey = VK_UP then
        begin
          FKeyRow := TAtlasWelcomeQuickActions.MoveRow(FKeyRow, -1, Length(FProjects));
        end
        else
        begin
          FKeyRow := TAtlasWelcomeQuickActions.MoveRow(FKeyRow, 1, Length(FProjects));
        end;
        FKeyButton := -1;
        FUseKey := True;
        if (FKeyRow <> Row) and Assigned(FOnSelectRow) then
        begin
          FOnSelectRow(FKeyRow);
        end;
        Result := True;
      end;
    VK_LEFT, VK_RIGHT:
      if Shift = [] then
      begin
        if AKey = VK_LEFT then
        begin
          FKeyButton := TAtlasWelcomeQuickActions.MoveButton(Buttons, FKeyButton, -1);
        end
        else
        begin
          FKeyButton := TAtlasWelcomeQuickActions.MoveButton(Buttons, FKeyButton, 1);
        end;
        FUseKey := True;
        Result := True;
      end;
    VK_HOME:
      if Shift = [] then
      begin
        FKeyButton := -1;
        FUseKey := True;
        Result := True;
      end;
    VK_RETURN, VK_SPACE:
      if Shift = [] then
      begin
        FUseKey := True;
        if (FKeyButton >= 0) and (FKeyButton <= High(Buttons)) then
        begin
          Activate(Row, FKeyButton, False);
        end
        else if Assigned(FOnOpenRow) then
        begin
          FOnOpenRow(Row);
        end;
        Result := True;
      end;
    VK_ESCAPE:
      if FKeyButton >= 0 then
      begin
        FKeyButton := -1;
        Result := True;
      end;
    VK_APPS, VK_F10:
      if ((AKey = VK_APPS) or (Shift = [ssShift])) and Assigned(FOnRowMenu) then
      begin
        FOnRowMenu(Row);
        Result := True;
      end;
  end;
  if Result and (FBox <> nil) then
  begin
    FBox.Invalidate;
  end;
end;

class function TAtlasQuickActionsBar.Caption(const AButton: TAtlasQuickActionButton;
  const AState: TAtlasQuickActionState; ANowMs: UInt64): string;
begin
  if AState.Running and (AState.Action = AButton.Action) then
  begin
    Exit(StateText(AState, ANowMs, AButton.Update));
  end;
  if AButton.Action = TAtlasQuickAction.Pull then
  begin
    if AButton.Update then
    begin
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickUpdate);
    end
    else
    begin
      Result := QuickActionTitle(TAtlasQuickAction.Pull);
    end;
    if AButton.AskExternals then
    begin
      Result := Result + ' ' + MenuArrow;
    end;
  end
  else
  begin
    Result := QuickActionTitle(AButton.Action);
  end;
end;

function QuickActionTitle(AAction: TAtlasQuickAction): string;
begin
  case AAction of
    TAtlasQuickAction.Build:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickBuild);
    TAtlasQuickAction.Tests:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickTests);
    TAtlasQuickAction.Run:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickRun);
    TAtlasQuickAction.Pull:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickPull);
    TAtlasQuickAction.Folder:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickFolder);
    TAtlasQuickAction.Tasks:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickTasks);
  else
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickConsole);
  end;
end;

class function TAtlasQuickActionsBar.StateText(const AState: TAtlasQuickActionState; ANowMs: UInt64;
  AUpdate: Boolean): string;
var
  Seconds: Integer;
begin
  Result := '';
  if AState.Running then
  begin
    Seconds := AState.ElapsedSeconds(ANowMs);
    case AState.Action of
      TAtlasQuickAction.Build:
        Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickBuilding, [Seconds]);
      TAtlasQuickAction.Tests:
        Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickTesting, [Seconds]);
      TAtlasQuickAction.Run:
        Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickStarting, [Seconds]);
      TAtlasQuickAction.Pull:
        if AUpdate then
        begin
          Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickUpdating, [Seconds]);
        end
        else
        begin
          Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickPulling, [Seconds]);
        end;
      TAtlasQuickAction.Tasks:
        Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickTasking, [Seconds]);
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
    Exit;
  end;
  if AState.Phase = TAtlasQuickActionPhase.Idle then
  begin
    Exit;
  end;
  case AState.Action of
    TAtlasQuickAction.Build:
      // Gebaut: Die Marke „Build 0/0/0“ des Bereichs zeigt das Ergebnis.
      if AState.Phase = TAtlasQuickActionPhase.Refused then
      begin
        Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickBuildRefused);
      end
      else if AState.Phase = TAtlasQuickActionPhase.Failed then
      begin
        Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickBuildFailed);
      end;
    TAtlasQuickAction.Tests:
      if AState.Phase = TAtlasQuickActionPhase.Succeeded then
      begin
        Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickTestsPassed, [AState.Passed]);
      end
      else if (AState.Phase = TAtlasQuickActionPhase.Failed) and (AState.Failed > 0) then
      begin
        Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickTestsFailed, [AState.Failed]);
      end
      else
      begin
        Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickTestsNotRun);
      end;
    TAtlasQuickAction.Run:
      if AState.Phase = TAtlasQuickActionPhase.Succeeded then
      begin
        Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickRunStarted);
      end
      else
      begin
        Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickRunRefused);
      end;
    TAtlasQuickAction.Pull:
      if AState.Phase = TAtlasQuickActionPhase.Succeeded then
      begin
        if AState.Pull = TAtlasPullOutcome.Updated then
        begin
          Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickPullUpdated);
        end
        else
        begin
          Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickPullUpToDate);
        end;
      end
      else if AState.Pull = TAtlasPullOutcome.Blocked then
      begin
        Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickPullBlocked);
      end
      else if AUpdate then
      begin
        Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickUpdateFailed);
      end
      else
      begin
        Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickPullFailed);
      end;
    TAtlasQuickAction.Console:
      if AState.Phase <> TAtlasQuickActionPhase.Succeeded then
      begin
        Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickConsoleFailed);
      end;
    TAtlasQuickAction.Tasks:
      // Fertig: Aufgabe und Ergebnis als Text der IDE-Schicht („Delphi-12-Prüfung: 2 Fehler 14:03“).
      if (AState.Phase = TAtlasQuickActionPhase.Refused) or (AState.Detail = '') then
      begin
        Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickTasksRefused);
      end
      else
      begin
        Result := AState.Detail;
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

class function TAtlasQuickActionsBar.StateColor(const AState: TAtlasQuickActionState): TColor;
begin
  // Farben wie die Marken des Bereichs „Projekte“ (#592): grau, grün, gelb, rot.
  case AState.Phase of
    TAtlasQuickActionPhase.Succeeded:
      Result := TColor($0043A02E);
    TAtlasQuickActionPhase.Refused:
      Result := TColor($001A8CC9);
    TAtlasQuickActionPhase.Failed:
      if (AState.Action = TAtlasQuickAction.Pull) and (AState.Pull = TAtlasPullOutcome.Blocked) then
      begin
        Result := TColor($001A8CC9);
      end
      else
      begin
        Result := TColor($002E22CF);
      end;
  else
    Result := TColor($00817666);
  end;
end;

class function TAtlasQuickActionsBar.ButtonHint(const AButton: TAtlasQuickActionButton; ARunning: Boolean;
  AKey: Integer; const AConsole: string): string;
begin
  case AButton.Block of
    TAtlasPullBlock.LocalChanges:
      Exit(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickPullLocalChanges));
    TAtlasPullBlock.NoWorkingCopy:
      Exit(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickPullNoWorkingCopy));
    TAtlasPullBlock.Busy:
      Exit(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickBusy));
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
  if not AButton.Enabled then
  begin
    if ARunning then
    begin
      Exit(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickBusy));
    end;
    Exit(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickIdeBusy));
  end;
  case AButton.Action of
    TAtlasQuickAction.Build:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickHintBuild);
    TAtlasQuickAction.Tests:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickHintTests);
    TAtlasQuickAction.Run:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickHintRun);
    TAtlasQuickAction.Pull:
      if AButton.Update then
      begin
        Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickHintUpdate);
      end
      else
      begin
        Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickHintPull);
      end;
    TAtlasQuickAction.Folder:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickHintFolder);
    TAtlasQuickAction.Tasks:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickHintTasks);
  else
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickHintConsole,
      [TAtlasWelcomeQuickActions.NormalizedConsole(AConsole)]);
  end;
  if AKey <> 0 then
  begin
    Result := Result + sLineBreak + TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickHintKey,
      [ShortCutToText(TShortCut(AKey))]);
  end;
end;

end.
