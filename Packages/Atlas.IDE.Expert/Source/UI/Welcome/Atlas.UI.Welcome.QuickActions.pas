unit Atlas.UI.Welcome.QuickActions;

// Schnellaktionen je Projekt auf der Willkommensseite (#764, Mockup #ws10),
// Teil mit VCL ohne Open Tools API. Die Bereiche „Projekte“ (#592) und
// „Weiterarbeiten“ (#755) zeigen in der Zeile unter der Maus bzw. in der mit
// der Tastatur gewählten Zeile eine Knopfleiste statt der Marken:
//   [Öffnen und bauen ▾] [Tests] [Startprofil ▾] [Pull] [Ordner] [Konsole]
// rechtsbündig, bei wenig Platz in zwei Zeilen (die Zeilenhöhe bleibt).
// - „Öffnen und bauen“ baut mit der zuletzt benutzten Konfiguration und
//   Plattform; der Teil ▾ öffnet die Auswahl. „Startprofil ▾“ öffnet die
//   Profile. „Tests“ fragt bei mehreren Testprojekten nach dem Testprojekt.
// - Gesperrter Pull zeigt im Tooltip den Grund („Erst lokale Änderungen
//   sichern“). Während eine Aktion läuft, zeigt ihr Knopf „baut … 12 s“,
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
  Atlas.UI.Strings;

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
    TChoiceKind = (Target, Profile, TestProject);
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
    procedure AddTitle(AParent: TMenuItem; ATextId: TAtlasTextId);
    procedure FillTargets(AParent: TMenuItem; const AProject: string);
    procedure FillProfiles(AParent: TMenuItem; const AProject: string);
    procedure FillTestProjects(AParent: TMenuItem; const AProject: string; const ACandidates: TArray<string>);
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
    /// Testprojekte) in AParent; False, wenn es keine Auswahl gibt.</summary>
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

implementation

uses
  Vcl.Forms,
  Vcl.Themes,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard;

const
  Separator = ' · ';
  MenuArrow = #$25BE;

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
    FOnFocusChange(Self);
end;

procedure TAtlasQuickKeySink.DoExit;
begin
  inherited;
  if Assigned(FOnFocusChange) then
    FOnFocusChange(Self);
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
  FTimer.Enabled := False;
  FSource := nil;
  inherited;
end;

function TAtlasQuickActionsBar.Scale(AValue: Integer): Integer;
begin
  Result := AValue;
  if Assigned(FScale) then
    Result := FScale(AValue);
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
      Continue;
    // Der Stand gilt auch ohne Knöpfe (Ergebnis einer Aktion vor dem Ausschalten).
    FStates[Row] := FSource.State(FProjects[Row]);
    if On then
      FButtons[Row] := FSource.Buttons(FProjects[Row]);
  end;
  if FSource <> nil then
    FNowMs := FSource.NowMs;
  if FKeyRow > High(FProjects) then
    FKeyRow := High(FProjects);
  if FHoverRow > High(FProjects) then
    FHoverRow := -1;
  if ValidRow(FKeyRow) and (FKeyButton > High(FButtons[FKeyRow])) then
    FKeyButton := -1;
  FHoverButton := -1;
  FSink.TabStop := On and (Length(FProjects) > 0);
  UpdateTimer;
  if FBox <> nil then
    FBox.Invalidate;
end;

procedure TAtlasQuickActionsBar.UpdateTimer;
var
  State: TAtlasQuickActionState;
  Running: Boolean;
begin
  Running := False;
  for State in FStates do
    if State.Running then
      Running := True;
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
      FStates[Row] := FSource.State(FProjects[Row]);
    UpdateTimer;
    if FBox <> nil then
      FBox.Invalidate;
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
    Result := FButtons[ARow];
end;

function TAtlasQuickActionsBar.StateOf(ARow: Integer): TAtlasQuickActionState;
begin
  Result := TAtlasQuickActionState.Idle;
  if ValidRow(ARow) then
    Result := FStates[ARow];
end;

function TAtlasQuickActionsBar.ItemsOf(ARow: Integer): TAtlasQuickActions;
var
  Button: TAtlasQuickActionButton;
begin
  Result := [];
  for Button in ButtonsOf(ARow) do
    Include(Result, Button.Action);
end;

function TAtlasQuickActionsBar.Focused: Boolean;
begin
  Result := FSink.Focused;
end;

function TAtlasQuickActionsBar.ActiveRow: Integer;
begin
  Result := -1;
  if not Active or (Length(FProjects) = 0) then
    Exit;
  if FUseKey and Focused and ValidRow(FKeyRow) then
    Result := FKeyRow
  else if ValidRow(FHoverRow) then
    Result := FHoverRow
  else if Focused and ValidRow(FKeyRow) then
    Result := FKeyRow;
  if (Result >= 0) and (Length(FButtons[Result]) = 0) then
    Result := -1;
end;

procedure TAtlasQuickActionsBar.SinkFocusChange(Sender: TObject);
begin
  // Mit dem Fokus kommt eine Zeile; ohne gewählte die erste.
  if Focused and not ValidRow(FKeyRow) and (Length(FProjects) > 0) then
    FKeyRow := 0;
  if FBox <> nil then
    FBox.Invalidate;
end;

procedure TAtlasQuickActionsBar.MouseMove(ARow, X, Y: Integer);
var
  Row, Index, OldButton: Integer;
  Menu, Changed: Boolean;
begin
  Changed := ARow <> FHoverRow;
  // Maus in eine andere Zeile: Sie wird die aktive.
  if Changed then
    FUseKey := False;
  FHoverRow := ARow;
  OldButton := FHoverButton;
  if not HitTest(X, Y, Row, Index, Menu) or (Row <> ARow) then
    Index := -1;
  FHoverButton := Index;
  if (Changed or (OldButton <> Index)) and (FBox <> nil) then
    FBox.Invalidate;
end;

procedure TAtlasQuickActionsBar.MouseLeave;
begin
  if (FHoverRow < 0) and (FHoverButton < 0) then
    Exit;
  FHoverRow := -1;
  FHoverButton := -1;
  if FBox <> nil then
    FBox.Invalidate;
end;

procedure TAtlasQuickActionsBar.MouseDown(ARow: Integer);
begin
  if not Active then
    Exit;
  if ValidRow(ARow) then
  begin
    FKeyRow := ARow;
    FKeyButton := -1;
  end;
  FUseKey := False;
  if FSink.CanFocus and not FSink.Focused then
    FSink.SetFocus;
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
      Inc(Result, Widths[I]);
    if ATo > AFrom then
      Inc(Result, (ATo - AFrom) * Gap);
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
    Exit;
  FRects[ARow] := nil;
  if Length(Buttons) = 0 then
    Exit;
  SetLength(Widths, Length(Buttons));
  SetLength(Rects, Length(Buttons));
  for Index := 0 to High(Buttons) do
  begin
    Widths[Index] := ACanvas.TextWidth(Caption(Buttons[Index], FStates[ARow], FNowMs)) + 2 * Scale(ButtonPadding);
    if Buttons[Index].Action = TAtlasQuickAction.Build then
      Inc(Widths[Index], Scale(MenuPart));
  end;
  Gap := Scale(ButtonGap);
  Height := Scale(ButtonHeight);
  Total := Span(0, High(Buttons));
  if (Total <= AArea.Width) or (Length(Buttons) < 2) then
    Place(0, High(Buttons), AArea.Top + (AArea.Height - Height) div 2, Height)
  else
  begin
    // Zwei Zeilen in der Zeilenhöhe: vorne die ersten Knöpfe, so gleichmäßig wie möglich.
    Split := Length(Buttons) div 2;
    for Index := 1 to High(Buttons) do
      if (Span(0, Index - 1) <= AArea.Width) and (Span(Index, High(Buttons)) <= AArea.Width) then
      begin
        Split := Index;
        Break;
      end;
    LineHeight := (AArea.Height - Scale(LineGap)) div 2;
    if LineHeight > Height then
      LineHeight := Height;
    Top := AArea.Top + (AArea.Height - 2 * LineHeight - Scale(LineGap)) div 2;
    First := Split - 1;
    Second := Split;
    Place(0, First, Top, LineHeight);
    Place(Second, High(Buttons), Top + LineHeight + Scale(LineGap), LineHeight);
  end;
  for Index := 0 to High(Rects) do
    if Rects[Index].Left < Result then
      Result := Rects[Index].Left;
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
    Exit;
  Buttons := ButtonsOf(ARow);
  Rects := FRects[ARow];
  if Length(Rects) <> Length(Buttons) then
    Exit;
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
        ACanvas.Pen.Color := AccentColor
      else
        ACanvas.Pen.Color := LineColor;
      ACanvas.RoundRect(Area.Left, Area.Top, Area.Right, Area.Bottom, Radius, Radius);
      if Button.Enabled then
        ACanvas.Font.Color := TextColor
      else
        ACanvas.Font.Color := MutedColor;
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
      ACanvas.TextOut(Area.Left + (Area.Width - ACanvas.TextWidth(Text)) div 2,
        Area.Top + (Area.Height - ACanvas.TextHeight(Text)) div 2, Text);
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
    Exit;
  Rects := FRects[ARow];
  if Length(Rects) <> Length(FButtons[ARow]) then
    Exit;
  for Index := 0 to High(Rects) do
    if Rects[Index].Contains(Point(X, Y)) then
    begin
      AIndex := Index;
      AMenu := (FButtons[ARow][Index].Action = TAtlasQuickAction.Build) and
        (X >= Rects[Index].Right - Scale(MenuPart));
      Exit(True);
    end;
end;

function TAtlasQuickActionsBar.ClickAt(X, Y: Integer): Boolean;
var
  Row, Index: Integer;
  Menu: Boolean;
begin
  Result := HitTest(X, Y, Row, Index, Menu);
  if Result then
    Activate(Row, Index, Menu);
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
  Source: IAtlasQuickActionsSource;
  Button: TAtlasQuickActionButton;
  Name: string;
  Candidates: TArray<string>;
begin
  if (FSource = nil) or not ValidRow(ARow) or (AIndex < 0) or (AIndex > High(ButtonsOf(ARow))) then
    Exit;
  Button := FButtons[ARow][AIndex];
  if not Button.Enabled then
    Exit;
  Source := FSource;
  Name := FProjects[ARow];
  case Button.Action of
    TAtlasQuickAction.Build:
      if AMenu then
      begin
        PopupAt(ARow, AIndex);
        Exit;
      end;
    TAtlasQuickAction.Run:
      begin
        // „Startprofil ▾“ fragt immer nach dem Profil.
        PopupAt(ARow, AIndex);
        Exit;
      end;
    TAtlasQuickAction.Tests:
      begin
        Candidates := Source.TestProjects(Name);
        if Length(Candidates) > 1 then
        begin
          PopupAt(ARow, AIndex);
          Exit;
        end;
      end;
  end;
  Queue(
    procedure
    begin
      Source.Execute(Name, Button.Action);
    end);
end;

procedure TAtlasQuickActionsBar.PopupAt(ARow, AIndex: Integer);
var
  Area: TRect;
  Position: TPoint;
begin
  if not FillChoices(FMenu.Items, ARow, AIndex) then
    Exit;
  Area := Rect(0, 0, 0, 0);
  if (ARow <= High(FRects)) and (AIndex <= High(FRects[ARow])) then
    Area := FRects[ARow][AIndex];
  Position := Point(Area.Left, Area.Bottom);
  if FBox <> nil then
    Position := FBox.ClientToScreen(Position);
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
  AddChoice(AParent, TAtlasStrings.Text(TAtlasTextId.WelcomeQuickTargetsIde), Choice,
    (Wanted = '') and (WantedPlatform = ''));
  for Configuration in Targets.Configurations do
  begin
    if Length(Targets.Platforms) = 0 then
    begin
      Choice.A := Configuration;
      Choice.B := '';
      Text := Configuration;
      if SameText(Configuration, Wanted) then
        Text := TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickTargetLast, [Text]);
      AddChoice(AParent, Text, Choice, SameText(Configuration, Wanted));
      Continue;
    end;
    for Platform in Targets.Platforms do
    begin
      Choice.A := Configuration;
      Choice.B := Platform;
      Text := Configuration + Separator + Platform;
      if SameText(Configuration, Wanted) and SameText(Platform, WantedPlatform) then
        Text := TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickTargetLast, [Text]);
      AddChoice(AParent, Text, Choice, SameText(Configuration, Wanted) and SameText(Platform, WantedPlatform));
    end;
  end;
end;

procedure TAtlasQuickActionsBar.FillProfiles(AParent: TMenuItem; const AProject: string);
var
  Names: TArray<string>;
  Name, Active, Text: string;
  Choice: TChoice;
begin
  Names := FSource.Profiles(AProject, Active);
  Choice := Default(TChoice);
  Choice.Kind := TChoiceKind.Profile;
  Choice.Project := AProject;
  for Name in Names do
  begin
    Choice.A := Name;
    Text := Name;
    if SameText(Name, Active) then
      Text := TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickProfileActive, [Name]);
    AddChoice(AParent, Text, Choice, SameText(Name, Active));
  end;
  Choice.A := '';
  AddChoice(AParent, TAtlasStrings.Text(TAtlasTextId.WelcomeQuickProfileNone), Choice, Active = '');
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

procedure TAtlasQuickActionsBar.AddTitle(AParent: TMenuItem; ATextId: TAtlasTextId);
var
  Item: TMenuItem;
begin
  // Überschrift der aufgeklappten Auswahl (nicht im Untermenü des Kontextmenüs).
  if AParent <> FMenu.Items then
    Exit;
  Item := TMenuItem.Create(FMenu);
  Item.Caption := TAtlasStrings.Text(ATextId);
  Item.Enabled := False;
  AParent.Add(Item);
  Item := TMenuItem.Create(FMenu);
  Item.Caption := '-';
  AParent.Add(Item);
end;

function TAtlasQuickActionsBar.FillChoices(AParent: TMenuItem; ARow, AIndex: Integer): Boolean;
var
  Buttons: TAtlasQuickActionButtons;
  Name: string;
  Candidates: TArray<string>;
begin
  Result := False;
  Buttons := ButtonsOf(ARow);
  if (FSource = nil) or (AIndex < 0) or (AIndex > High(Buttons)) or not Buttons[AIndex].Enabled then
    Exit;
  AParent.Clear;
  if AParent = FMenu.Items then
    FChoices := nil;
  Name := FProjects[ARow];
  case Buttons[AIndex].Action of
    TAtlasQuickAction.Build:
      begin
        AddTitle(AParent, TAtlasTextId.WelcomeQuickTargetsTitle);
        FillTargets(AParent, Name);
      end;
    TAtlasQuickAction.Run:
      begin
        AddTitle(AParent, TAtlasTextId.WelcomeQuickProfilesTitle);
        FillProfiles(AParent, Name);
      end;
    TAtlasQuickAction.Tests:
      begin
        Candidates := FSource.TestProjects(Name);
        if Length(Candidates) < 2 then
          Exit;
        AddTitle(AParent, TAtlasTextId.WelcomeQuickTestsChoose);
        FillTestProjects(AParent, Name, Candidates);
      end;
  else
    Exit;
  end;
  Result := AParent.Count > 0;
end;

procedure TAtlasQuickActionsBar.ChoiceClick(Sender: TObject);
var
  Choice: TChoice;
  Source: IAtlasQuickActionsSource;
  Index: Integer;
begin
  Index := TMenuItem(Sender).Tag;
  if (FSource = nil) or (Index < 0) or (Index > High(FChoices)) then
    Exit;
  Choice := FChoices[Index];
  Source := FSource;
  Queue(
    procedure
    begin
      case Choice.Kind of
        TChoiceKind.Target:
          Source.Build(Choice.Project, Choice.A, Choice.B);
        TChoiceKind.Profile:
          Source.Run(Choice.Project, Choice.A);
      else
        Source.RunTests(Choice.Project, Choice.A);
      end;
    end);
end;

procedure TAtlasQuickActionsBar.AttachMenu(AMenu: TPopupMenu);

  function Add(AParent: TMenuItem; AAction: TAtlasQuickAction; ATextId: TAtlasTextId): TMenuItem;
  begin
    Result := TMenuItem.Create(AMenu);
    Result.Caption := TAtlasStrings.Text(ATextId);
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
  Add(AMenu.Items, TAtlasQuickAction.Build, TAtlasTextId.WelcomeQuickBuild);
  FBuildWithItem := TMenuItem.Create(AMenu);
  FBuildWithItem.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickMenuBuildWith);
  AMenu.Items.Add(FBuildWithItem);
  Add(AMenu.Items, TAtlasQuickAction.Tests, TAtlasTextId.WelcomeQuickTests);
  FRunWithItem := TMenuItem.Create(AMenu);
  FRunWithItem.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickMenuRunWith);
  AMenu.Items.Add(FRunWithItem);
  Add(AMenu.Items, TAtlasQuickAction.Pull, TAtlasTextId.WelcomeQuickPull);
  Add(AMenu.Items, TAtlasQuickAction.Console, TAtlasTextId.WelcomeQuickMenuConsole);
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
      if Buttons[Found].Update then
        Item.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickUpdate)
      else
        Item.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickPull);
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
  if FContextSeparator <> nil then
    FContextSeparator.Visible := Any;
end;

procedure TAtlasQuickActionsBar.ContextClick(Sender: TObject);
var
  Index, Found: Integer;
begin
  Index := TMenuItem(Sender).Tag;
  if (Index < 0) or (Index > High(FContextActions)) then
    Exit;
  Found := TAtlasWelcomeQuickActions.IndexOf(ButtonsOf(FContextRow), FContextActions[Index]);
  if Found >= 0 then
    Activate(FContextRow, Found, False);
end;

function TAtlasQuickActionsBar.HintAt(X, Y: Integer; out AHint: string): Boolean;
var
  Row, Index, Key: Integer;
  Menu: Boolean;
  Button: TAtlasQuickActionButton;
  Console: string;
begin
  AHint := '';
  Result := HitTest(X, Y, Row, Index, Menu);
  if not Result then
    Exit;
  Button := FButtons[Row][Index];
  Key := 0;
  Console := '';
  if FSource <> nil then
  begin
    if Button.Action = TAtlasQuickAction.Build then
      Key := FSource.BuildKey
    else if Button.Action = TAtlasQuickAction.Tests then
      Key := FSource.TestKey;
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
    Exit;
  if not ValidRow(FKeyRow) then
    FKeyRow := 0;
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
      FBox.Invalidate;
    Exit(True);
  end;
  case AKey of
    VK_UP, VK_DOWN:
      if (ssAlt in Shift) and (AKey = VK_DOWN) then
      begin
        // Alt+↓: Auswahl des gewählten Knopfs, sonst die von „Öffnen und bauen“.
        Index := FKeyButton;
        if (Index < 0) or (Index > High(Buttons)) or not Buttons[Index].HasMenu then
          Index := TAtlasWelcomeQuickActions.IndexOf(Buttons, TAtlasQuickAction.Build);
        if Index >= 0 then
          PopupAt(Row, Index);
        Result := True;
      end
      else if Shift = [] then
      begin
        if AKey = VK_UP then
          FKeyRow := TAtlasWelcomeQuickActions.MoveRow(FKeyRow, -1, Length(FProjects))
        else
          FKeyRow := TAtlasWelcomeQuickActions.MoveRow(FKeyRow, 1, Length(FProjects));
        FKeyButton := -1;
        FUseKey := True;
        if (FKeyRow <> Row) and Assigned(FOnSelectRow) then
          FOnSelectRow(FKeyRow);
        Result := True;
      end;
    VK_LEFT, VK_RIGHT:
      if Shift = [] then
      begin
        if AKey = VK_LEFT then
          FKeyButton := TAtlasWelcomeQuickActions.MoveButton(Buttons, FKeyButton, -1)
        else
          FKeyButton := TAtlasWelcomeQuickActions.MoveButton(Buttons, FKeyButton, 1);
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
          Activate(Row, FKeyButton, False)
        else if Assigned(FOnOpenRow) then
          FOnOpenRow(Row);
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
    FBox.Invalidate;
end;

class function TAtlasQuickActionsBar.Caption(const AButton: TAtlasQuickActionButton;
  const AState: TAtlasQuickActionState; ANowMs: UInt64): string;
begin
  if AState.Running and (AState.Action = AButton.Action) then
    Exit(StateText(AState, ANowMs, AButton.Update));
  case AButton.Action of
    TAtlasQuickAction.Build:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickBuild);
    TAtlasQuickAction.Tests:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickTests);
    TAtlasQuickAction.Run:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickRun);
    TAtlasQuickAction.Pull:
      if AButton.Update then
        Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickUpdate)
      else
        Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickPull);
    TAtlasQuickAction.Folder:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickFolder);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickConsole);
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
        Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickBuilding, [Seconds]);
      TAtlasQuickAction.Tests:
        Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickTesting, [Seconds]);
      TAtlasQuickAction.Run:
        Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickStarting, [Seconds]);
      TAtlasQuickAction.Pull:
        if AUpdate then
          Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickUpdating, [Seconds])
        else
          Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickPulling, [Seconds]);
    end;
    Exit;
  end;
  if AState.Phase = TAtlasQuickActionPhase.Idle then
    Exit;
  case AState.Action of
    TAtlasQuickAction.Build:
      // Gebaut: Die Marke „Build 0/0/0“ des Bereichs zeigt das Ergebnis.
      if AState.Phase = TAtlasQuickActionPhase.Refused then
        Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickBuildRefused)
      else if AState.Phase = TAtlasQuickActionPhase.Failed then
        Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickBuildFailed);
    TAtlasQuickAction.Tests:
      if AState.Phase = TAtlasQuickActionPhase.Succeeded then
        Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickTestsPassed, [AState.Passed])
      else if (AState.Phase = TAtlasQuickActionPhase.Failed) and (AState.Failed > 0) then
        Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickTestsFailed, [AState.Failed])
      else
        Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickTestsNotRun);
    TAtlasQuickAction.Run:
      if AState.Phase = TAtlasQuickActionPhase.Succeeded then
        Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickRunStarted)
      else
        Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickRunRefused);
    TAtlasQuickAction.Pull:
      if AState.Phase = TAtlasQuickActionPhase.Succeeded then
      begin
        if AState.Pull = TAtlasPullOutcome.Updated then
          Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickPullUpdated)
        else
          Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickPullUpToDate);
      end
      else if AState.Pull = TAtlasPullOutcome.Blocked then
        Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickPullBlocked)
      else if AUpdate then
        Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickUpdateFailed)
      else
        Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickPullFailed);
    TAtlasQuickAction.Console:
      if AState.Phase <> TAtlasQuickActionPhase.Succeeded then
        Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickConsoleFailed);
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
        Result := TColor($001A8CC9)
      else
        Result := TColor($002E22CF);
  else
    Result := TColor($00817666);
  end;
end;

class function TAtlasQuickActionsBar.ButtonHint(const AButton: TAtlasQuickActionButton; ARunning: Boolean;
  AKey: Integer; const AConsole: string): string;
begin
  case AButton.Block of
    TAtlasPullBlock.LocalChanges:
      Exit(TAtlasStrings.Text(TAtlasTextId.WelcomeQuickPullLocalChanges));
    TAtlasPullBlock.NoWorkingCopy:
      Exit(TAtlasStrings.Text(TAtlasTextId.WelcomeQuickPullNoWorkingCopy));
    TAtlasPullBlock.Busy:
      Exit(TAtlasStrings.Text(TAtlasTextId.WelcomeQuickBusy));
  end;
  if not AButton.Enabled then
  begin
    if ARunning then
      Exit(TAtlasStrings.Text(TAtlasTextId.WelcomeQuickBusy));
    Exit(TAtlasStrings.Text(TAtlasTextId.WelcomeQuickIdeBusy));
  end;
  case AButton.Action of
    TAtlasQuickAction.Build:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickHintBuild);
    TAtlasQuickAction.Tests:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickHintTests);
    TAtlasQuickAction.Run:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickHintRun);
    TAtlasQuickAction.Pull:
      if AButton.Update then
        Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickHintUpdate)
      else
        Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickHintPull);
    TAtlasQuickAction.Folder:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickHintFolder);
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickHintConsole,
      [TAtlasWelcomeQuickActions.NormalizedConsole(AConsole)]);
  end;
  if AKey <> 0 then
    Result := Result + sLineBreak + TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickHintKey,
      [ShortCutToText(TShortCut(AKey))]);
end;

end.
