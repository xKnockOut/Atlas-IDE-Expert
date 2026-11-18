unit Atlas.IDE.Outline.Breadcrumbs;

// Brotkrumenleiste (#590) in der IDE:
// - Über dem Editor jedes Editorfensters steht eine Leiste
//   (TAtlasBreadcrumbBar, alTop im Eltern-Steuerelement des Editors
//   „Editor“). Fenster, die später aufgehen, bekommen sie beim nächsten Takt.
// - Ein Zeitgeber (150 ms, nur mit offenem Quelltext-Editor laut
//   TAtlasIdeOpenWatch) rechnet für die aktive Ansicht den Pfad am Caret
//   aus dem Stand von TAtlasIdeOutlineCache (gemeinsam mit dem
//   Gliederungsfenster #537): Caret-Bewegung löst nie eine Serveranfrage
//   aus, nach Änderungen fragt der Cache erst nach einer Tipppause. Bei
//   Syntaxfehlern bleibt der letzte gültige Stand.
// - Klick auf ein Glied (bzw. ↓/Enter mit Fokus) öffnet das Sprungmenü als
//   Atlas-Popup unter dem Glied: Geschwister in Quelltextreihenfolge, das
//   aktuelle gewählt, Filter mit Wortgrenzen-Suche bei jedem Tastendruck.
//   Enter springt zur Implementierung (ohne Rumpf zur Deklaration),
//   Umschalt+Enter zur Deklaration.
// - Klick auf „›“ hinter einem Glied öffnet dasselbe Menü mit seinen Kindern
//   (Mitglieder des Typs, lokale Routinen, beim Unit-Glied alles auf
//   Unit-Ebene). Strg+Klick auf ein Glied springt zur Implementierung,
//   Strg+Umschalt+Klick zur Deklaration, beim Unit-Glied an den Anfang.
// - Focus (keys.breadcrumbs, Vorgabe Strg+Umschalt+.) setzt den Fokus auf
//   das letzte Glied der aktiven Leiste; Esc gibt ihn an den Editor zurück.
// - editor.breadcrumbs aus entfernt alle Leisten, editor.breadcrumbsShowUnit
//   setzt den Unit-Namen als erstes Glied, editor.breadcrumbsVisibility den
//   Sichtbarkeitsabschnitt hinter den Typ (#1759). Dessen Menü listet die
//   Abschnitte des Typs; Enter springt zum Schlüsselwort.
//   editor.breadcrumbsMemberBlocks setzt den Unterblock (const, type,
//   class var) dahinter (#1767).
// - Im Menü des Sichtbarkeitsglieds stehen je Abschnitt Marke und
//   Mitgliederzahl (editor.breadcrumbsSectionCounts), dahinter „Neue Zeile
//   am Ende von …“ (editor.breadcrumbsSectionAppend) und „Abschnitt
//   anlegen: …“ für fehlende Abschnitte (editor.breadcrumbsSectionCreate,
//   #1768); geändert wird über TAtlasIdeSectionEdit.
// - Rechtsklick, Menütaste oder Umschalt+F10 auf ein Glied öffnet das
//   Kontextmenü TAtlasIdeCrumbMenu (editor.breadcrumbsContextMenu, #1786):
//   kopieren, Verwendungen suchen, Umbenennen, Komponente im Designer
//   (Haken der Komposition aus Install).
// - Überladungen (editor.breadcrumbsOverloads, #1784): Das Glied trägt den
//   Zähler „(2/3)“; Klick darauf öffnet „Überladungen von …“ mit Parametern
//   und Zeile, Enter springt zur Implementierung, Umschalt+Enter zur
//   Deklaration. Im Geschwistermenü stehen Überladungen mit Parametern,
//   gekürzt; der Hinweis über der Zeile zeigt die volle Liste.
// - Interface-Marke (editor.breadcrumbsInterfaces, #1785): Methodenglieder
//   tragen „[IKunde]“ für die Interface-Methoden, die sie erfüllen. Die
//   Angaben holt TAtlasIdeOutlineCache mit der Gliederung
//   (atlas.server.interfaceMethods), nie bei Caret-Bewegung. Klick auf die
//   Marke öffnet „Erfüllt“ mit Unit und Zeile; Enter springt zur Deklaration
//   im Interface, auch in anderen Units.
// - Kennzahlen-Karte (editor.breadcrumbsMetrics, #1787): Methoden- und
//   Typglieder zeigen nach der Tooltip-Verzögerung bzw. mit Strg+I die Karte
//   aus TAtlasCrumbCards. Die Metriken kommen über TAtlasCrumbCardHooks aus
//   dem Abruf von Base (dieselben wie Metrik-Linse und Statusleiste); die
//   Leiste meldet dort nur Bedarf an und fragt nichts selbst.
// - Eigene Sicherung TAtlasFeature.Breadcrumbs: Fehler anderer Editorfunktionen
//   schalten die Leiste nicht still ab.
//   Löst die eigene Sicherung aus, sagt die Leiste das, statt stehen zu
//   bleiben; nach „Abgeschaltete Funktionen einschalten“ läuft sie weiter.
// - editor.breadcrumbsIdeColors: Fläche und Schrift wie die Werkzeugleisten
//   des IDE-Themas (TAtlasIdeStyle.ChromeColors), sonst Atlas-Palette.
// - editor.breadcrumbsHideIdeToolbar: Die Navigationsleiste der IDE („Typ
//   suchen“/„Methode suchen“) ist ausgeblendet, solange die Leiste an ist;
//   aus oder beim Entladen kommt sie zurück. Ausgeblendet wird über die
//   IDE-Option „Navigationssymbolleiste anzeigen“ (TAtlasIdeNavigationOption).
//   Nur wenn die IDE keine solche Option hat, hängt
//   TAtlasNavigationToolbar die Leiste um (Netz).
// - Anlegen je Editorfenster, Wächter, Freigabe nach der Sperre durch die
//   IDE, Protokoll des Sperrenden und Abbau übernimmt TAtlasEditorBarHost
//   (#1248). Bei ausgelöster Sicherung bleiben die Leisten stehen und sagen
//   „abgeschaltet“ (ShowDisabled), statt zu verschwinden.
// - Die Sprungmenüs selbst baut TAtlasIdeCrumbLists; hier bleiben Leisten, Stand, Sprung, Karte und Diagnose.
// Abgrenzung zum mitlaufenden Kopf (#506) und zum Gliederungsfenster (#537):
// docs/Architektur.md. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Editor.Metrics,
  Atlas.IDE.Outline.CrumbMenu;

type
  /// <summary>Letzte Metriken der Datei AFileName; False ohne.</summary>
  TAtlasCrumbMetricsFunc = reference to function(const AFileName: string; out AMetrics: TAtlasFileMetrics): Boolean;

  /// <summary>Metriken für die Kennzahlen-Karte (#1787), aus der Komposition.</summary>
  TAtlasCrumbCardHooks = record
    Metrics: TAtlasCrumbMetricsFunc;
    /// <summary>Bedarf an den Metriken an- oder abmelden.</summary>
    WantMetrics: TProc<Boolean>;
  end;

  TAtlasIdeBreadcrumbs = class
  private class var
    FState: TObject;
    FMenuHooks: TAtlasCrumbMenuHooks;
    FCardHooks: TAtlasCrumbCardHooks;
    FWantsMetrics: Boolean;
    class procedure WantMetrics; static;
  public
    /// <summary>Den Server fragt TAtlasIdeOutlineCache (vorher installieren). AMenuHooks bedienen das
    /// Kontextmenü (#1786), ACardHooks die Kennzahlen-Karte (#1787).</summary>
    class procedure Install(const AMenuHooks: TAtlasCrumbMenuHooks; const ACardHooks: TAtlasCrumbCardHooks); static;
    class procedure Uninstall; static;
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
    /// <summary>Fokus auf das letzte Glied der Leiste über dem aktiven Editor.</summary>
    class procedure Focus; static;
    /// <summary>Ist die Leiste eingeschaltet (für Palette und Tastenkürzel)?</summary>
    class function Enabled: Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Text.Lines,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Style.Palette,
  Atlas.Core.Outline.Breadcrumbs,
  Atlas.Core.Outline.CrumbPlan,
  Atlas.Core.Outline.Interfaces,
  Atlas.Core.Editor.CrumbCard,
  Atlas.UI.Outline.Strings,
  Atlas.UI.Popup.CrumbCard,
  Atlas.UI.Outline.Breadcrumbs,
  Atlas.IDE.Outline.NavigationOption,
  Atlas.IDE.Outline.NavigationHiding,
  Atlas.IDE.Outline.CrumbProbe,
  Atlas.IDE.Outline.CrumbLists,
  Atlas.IDE.Foundation.EditorBarHost,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.OpenWatch,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Outline.Cache,
  Atlas.IDE.Foundation.EditorWindows;

const
  cTickMs = 150;

type
  /// <summary>Wovon der gezeigte Pfad abhängt: Stand der Gliederung und Einstellungen der Leiste.</summary>
  TBreadcrumbsKey = record
    Status: TAtlasOutlineStatus;
    Path: TAtlasCrumbKey;
  end;

  TBreadcrumbsState = class
  private
    FTimer: TTimer;
    FHost: TAtlasEditorBarHost;
    /// <summary>Datei, Gliederung, Zeilen und Caret des gezeigten Pfads.</summary>
    FSource: TAtlasCrumbSource;
    /// <summary>Für den Pfad ausgewerteter Text, je Stand der Gliederung einmal (Remember).</summary>
    FText: TAtlasCrumbText;
    FKey: TBreadcrumbsKey;
    FInterfaces: TAtlasInterfaceMethods;
    FShown: Boolean;
    FActiveBar: TAtlasBreadcrumbBar;
    /// <summary>Navigationsleiste der IDE ausblenden, solange die Leiste an ist.</summary>
    FNavigation: TAtlasIdeNavigationHiding;
    /// <summary>Diagnose, warum die Leiste keine Maus bekommt.</summary>
    FProbe: TAtlasIdeCrumbProbe;
    /// <summary>Zeigen die Leisten gerade den Hinweis „abgeschaltet“?</summary>
    FDisabled: Boolean;
    /// <summary>Kennzahlen-Karte (#1787); erst beim ersten Zeigen angelegt.</summary>
    FCard: TAtlasCrumbCardTip;
    /// <summary>Anmeldung bei TAtlasIdeOpenWatch: ohne Quelltext-Editor ruht der Takt.</summary>
    FOpenHandle: Integer;
    procedure OpenChanged;
    function HasCard(ABar: TAtlasBreadcrumbBar; AIndex: Integer): Boolean;
    procedure ShowCard(ABar: TAtlasBreadcrumbBar; AIndex: Integer; const APoint: TPoint);
    procedure HideCard;
    procedure Tick(Sender: TObject);
    procedure ShowDisabled;
    procedure EnsureBars;
    function CreateBar: TAtlasBreadcrumbBar;
    procedure Place(ABar: TAtlasBreadcrumbBar; AParent: TWinControl);
    /// <summary>Sprungmenü AList am Glied AIndex, solange ABar die aktive Leiste ist.</summary>
    procedure Open(AList: TAtlasCrumbList; ABar: TAtlasBreadcrumbBar; AIndex: Integer; const APoint: TPoint);
    procedure ContextMenu(ABar: TAtlasBreadcrumbBar; AIndex: Integer; const APoint: TPoint);
    procedure Jump(ABar: TAtlasBreadcrumbBar; AIndex: Integer; ADeclaration: Boolean);
    procedure Later(ABar: TAtlasBreadcrumbBar; const AAction: TProc);
    procedure Leave(ABar: TAtlasBreadcrumbBar);
    function Remember(ABar: TAtlasBreadcrumbBar; const ASnapshot: TAtlasOutlineSnapshot): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Removed(ABar: TControl);
    procedure Reset;
    procedure Update;
    procedure ApplyTheme;
    function ActiveBar: TAtlasBreadcrumbBar;
  end;

function Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Breadcrumbs and not TAtlasGuard.Disabled(TAtlasFeature.Breadcrumbs);
end;

{ TBreadcrumbsState }

constructor TBreadcrumbsState.Create;
begin
  inherited Create;
  FHost := TAtlasEditorBarHost.Create('Brotkrumen', TAtlasFeature.Breadcrumbs,
    function(AEditorParent: TWinControl): TControl
    begin
      Result := CreateBar;
    end,
    procedure(ABar: TControl; AEditorParent: TWinControl)
    begin
      Place(TAtlasBreadcrumbBar(ABar), AEditorParent);
    end);
  FHost.OnRemoved := Removed;
  // Im Formular-Designer hat der Pfad des Carets keinen Nutzen; dort steht die Designer-Leiste (#1442).
  FHost.Placement.ShowIn := TAtlasEditorBarView.Code;
  FNavigation := TAtlasIdeNavigationHiding.Create;
  FProbe := TAtlasIdeCrumbProbe.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := Tick;
  // Nur mit offenem Quelltext-Editor: Die Leiste steht nur in der Code-Ansicht (ShowIn), auf der Willkommensseite
  // lief der Takt sonst ohne Arbeit weiter.
  FOpenHandle := TAtlasIdeOpenWatch.Register(OpenChanged);
  FTimer.Enabled := TAtlasIdeOpenWatch.EditorOpen;
  Reset;
end;

destructor TBreadcrumbsState.Destroy;
begin
  TAtlasIdeOpenWatch.Unregister(FOpenHandle);
  FTimer.Free;
  FCard.Free;
  FProbe.Free;
  // Navigationsleisten der IDE wieder zeigen: Option zurück, wenn Atlas sie ausgeschaltet hatte, bzw. zurückhängen.
  FNavigation.Free;
  TAtlasIdeCrumbMenu.Release;
  FHost.Free;
  inherited Destroy;
end;

function TBreadcrumbsState.HasCard(ABar: TAtlasBreadcrumbBar; AIndex: Integer): Boolean;
begin
  Result := TAtlasIdeSettings.Current.BreadcrumbsMetrics and (ABar = FActiveBar) and (AIndex >= 0) and
    (AIndex <= High(ABar.Crumbs)) and TAtlasCrumbCards.HasCard(FSource.Nodes, ABar.Crumbs[AIndex].Node);
end;

/// <summary>Karte aus den Metriken der Datei; ohne Metriken nur die Kopfzeile (#1787).</summary>
procedure TBreadcrumbsState.ShowCard(ABar: TAtlasBreadcrumbBar; AIndex: Integer; const APoint: TPoint);
var
  mMetrics: TAtlasFileMetrics;
  mHasMetrics: Boolean;
begin
  if not HasCard(ABar, AIndex) then
  begin
    Exit;
  end;
  mMetrics := Default(TAtlasFileMetrics);
  mHasMetrics := Assigned(TAtlasIdeBreadcrumbs.FCardHooks.Metrics) and
    TAtlasIdeBreadcrumbs.FCardHooks.Metrics(FSource.FileName, mMetrics);
  if FCard = nil then
  begin
    FCard := TAtlasCrumbCardTip.Create(nil);
  end;
  FCard.Colors := TAtlasIdeStyle.Colors;
  FCard.ShowCard(TAtlasCrumbCards.Build(FSource.Nodes, FSource.Lines, ABar.Crumbs[AIndex].Node, mHasMetrics,
    mMetrics), APoint);
end;

procedure TBreadcrumbsState.HideCard;
begin
  if (FCard <> nil) and FCard.IsShown then
  begin
    FCard.HidePopup;
  end;
end;

procedure TBreadcrumbsState.OpenChanged;
begin
  if TAtlasIdeOpenWatch.EditorOpen then
  begin
    FTimer.Enabled := True;
    Exit;
  end;
  // Letzter Quelltext-Editor zu: ein letzter Takt blendet die Leisten aus (Ansicht Code), danach Ruhe.
  FTimer.Enabled := False;
  HideCard;
  Tick(nil);
end;

procedure TBreadcrumbsState.Tick(Sender: TObject);
begin
  if not TAtlasIdeSettings.Current.Breadcrumbs then
  begin
    Exit;
  end;
  if TAtlasGuard.Disabled(TAtlasFeature.Breadcrumbs) then
  begin
    ShowDisabled;
    Exit;
  end;
  if FDisabled then
  begin
    // Wieder eingeschaltet: alles neu zeichnen.
    FDisabled := False;
    FShown := False;
    FSource.Line := -1;
    FSource.Character := -1;
    TAtlasGuard.Log('Brotkrumen: wieder eingeschaltet');
  end;
  TAtlasGuard.Run(TAtlasFeature.Breadcrumbs,
    procedure
    begin
      Update;
      FProbe.Check(FActiveBar);
    end);
end;

/// <summary>Nach ausgelöster Sicherung einmal den Hinweis in alle Leisten schreiben; vorher blieb die Leiste mit dem
/// letzten Pfad stehen und reagierte auf keinen Klick mehr.</summary>
procedure TBreadcrumbsState.ShowDisabled;
begin
  if FDisabled then
  begin
    Exit;
  end;
  FDisabled := True;
  TAtlasGuard.Log('Brotkrumen: durch die Sicherung abgeschaltet');
  // Je Leiste abgesichert (Host): Läuft außerhalb von TAtlasGuard.Run, nichts darf in die IDE durchschlagen.
  FHost.ForEach(
    procedure(ABar: TControl)
    begin
      TAtlasBreadcrumbBar(ABar).EmptyText := TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsDisabled);
      TAtlasBreadcrumbBar(ABar).SetCrumbs(nil);
    end);
end;

/// <summary>Hinweistexte der Leiste aus den Texten der Gliederung.</summary>
function BarTexts: TAtlasCrumbBarSetup;
begin
  Result := Default(TAtlasCrumbBarSetup);
  Result.CrumbHint := TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsCrumbHint);
  Result.SeparatorHint := TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsChildrenHint);
  Result.MarkHint := TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsMarkHint);
  Result.OverloadHint := TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsOverloadsHint);
  Result.InterfaceHint := TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsInterfacesHint);
  Result.InterfaceKeyHint := TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsInterfacesKey);
end;

/// <summary>Menü am Glied erst nach dem Klick öffnen (siehe Later); AOpen bekommt Glied und Stelle.</summary>
function Deferred(AState: TBreadcrumbsState; ABar: TAtlasBreadcrumbBar;
  const AOpen: TProc<Integer, TPoint>): TAtlasCrumbMenuEvent;
begin
  Result :=
    procedure(AIndex: Integer; const APoint: TPoint)
    var
      At: TPoint;
    begin
      At := APoint;
      AState.Later(ABar,
        procedure
        begin
          AOpen(AIndex, At);
        end);
    end;
end;

/// <summary>Sprungmenü AList am Glied, nach dem Klick geöffnet.</summary>
function ListEvent(AState: TBreadcrumbsState; ABar: TAtlasBreadcrumbBar; AList: TAtlasCrumbList): TAtlasCrumbMenuEvent;
begin
  Result := Deferred(AState, ABar,
    procedure(AIndex: Integer; APoint: TPoint)
    begin
      AState.Open(AList, ABar, AIndex, APoint);
    end);
end;

/// <summary>Kennzahlen-Karte (#1787) an den Gliedern von ABar in ASetup eintragen.</summary>
procedure AddCardEvents(AState: TBreadcrumbsState; ABar: TAtlasBreadcrumbBar; var ASetup: TAtlasCrumbBarSetup);
begin
  ASetup.HasCard :=
    function(AIndex: Integer): Boolean
    begin
      Result := AState.HasCard(ABar, AIndex);
    end;
  ASetup.OnShowCard :=
    procedure(AIndex: Integer; const APoint: TPoint)
    var
      At: TPoint;
    begin
      At := APoint;
      TAtlasGuard.Run(TAtlasFeature.Breadcrumbs,
        procedure
        begin
          AState.ShowCard(ABar, AIndex, At);
        end);
    end;
  ASetup.OnHideCard :=
    procedure
    begin
      AState.HideCard;
    end;
end;

procedure TBreadcrumbsState.EnsureBars;
var
  mServices: INTAEditorServices;
  mIndex: Integer;
begin
  FHost.Ensure;
  if not Supports(BorlandIDEServices, INTAEditorServices, mServices) then
  begin
    Exit;
  end;
  // Die IDE legt die Navigationsleiste je Fenster an; neue Fenster beim nächsten Takt.
  for mIndex := 0 to mServices.EditWindowCount - 1 do
  begin
    if TAtlasIdeEditorWindows.EditorOf(mServices.EditWindow[mIndex]) <> nil then
    begin
      FNavigation.ApplyTo(mServices.EditWindow[mIndex].Form);
    end;
  end;
end;

/// <summary>Eigene Methode: Jede Leiste braucht ihre eigene gefangene Variable. Einordnen und Wächter: Host.</summary>
function TBreadcrumbsState.CreateBar: TAtlasBreadcrumbBar;
var
  mBar: TAtlasBreadcrumbBar;
  mHost: TAtlasEditorBarHost;
  mSetup: TAtlasCrumbBarSetup;
begin
  mBar := TAtlasBreadcrumbBar.Create(nil);
  mHost := FHost;
  mBar.SetColors(TAtlasIdeStyle.BarColors);
  mBar.EmptyText := TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsEmpty);
  mSetup := BarTexts;
  mSetup.OnOpenMenu := ListEvent(Self, mBar, TAtlasCrumbList.Siblings);
  mSetup.OnOpenChildren := ListEvent(Self, mBar, TAtlasCrumbList.Children);
  mSetup.OnOpenOverloads := ListEvent(Self, mBar, TAtlasCrumbList.Overloads);
  mSetup.OnOpenInterfaces := ListEvent(Self, mBar, TAtlasCrumbList.Interfaces);
  mSetup.OnContextMenu := Deferred(Self, mBar,
    procedure(AIndex: Integer; APoint: TPoint)
    begin
      ContextMenu(mBar, AIndex, APoint);
    end);
  mSetup.OnJump :=
    procedure(AIndex: Integer; ADeclaration: Boolean)
    begin
      TAtlasGuard.Run(TAtlasFeature.Breadcrumbs,
        procedure
        begin
          Jump(mBar, AIndex, ADeclaration);
        end);
    end;
  mSetup.OnLeave :=
    procedure
    begin
      Leave(mBar);
    end;
  AddCardEvents(Self, mBar, mSetup);
  mBar.Setup := mSetup;
  mBar.OnDisabled :=
    procedure(ASender: TObject)
    begin
      mHost.Disabled(ASender);
    end;
  Result := mBar;
end;

procedure TBreadcrumbsState.Place(ABar: TAtlasBreadcrumbBar; AParent: TWinControl);
begin
  if ABar.Parent = AParent then
  begin
    Exit;
  end;
  // Über dem Editor: zuerst ganz oben einhängen, dann oben ausrichten.
  ABar.Top := 0;
  ABar.Align := alTop;
  ABar.Parent := AParent;
end;

procedure TBreadcrumbsState.Open(AList: TAtlasCrumbList; ABar: TAtlasBreadcrumbBar; AIndex: Integer;
  const APoint: TPoint);
begin
  if (ABar = FActiveBar) and (AIndex >= 0) and (AIndex <= High(ABar.Crumbs)) then
  begin
    TAtlasIdeCrumbLists.Open(AList, FSource, ABar, AIndex, APoint);
  end;
end;

/// <summary>Ob ABar beim Stand AStatus einen Pfad zeigt; sonst steht der passende Hinweis darin (beim Warten
/// bleibt der alte Pfad).</summary>
function ShowsPath(ABar: TAtlasBreadcrumbBar; AStatus: TAtlasOutlineStatus): Boolean;
begin
  Result := False;
  case AStatus of
    TAtlasOutlineStatus.NoFile:
      begin
        ABar.EmptyText := TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsEmpty);
        ABar.SetCrumbs(nil);
      end;
    TAtlasOutlineStatus.NoServer:
      begin
        ABar.EmptyText := TAtlasOutlineStrings.Text(TAtlasOutlineTextId.OutlineNoServer);
        ABar.SetCrumbs(nil);
      end;
    TAtlasOutlineStatus.Waiting:
      // Alter Pfad bleibt stehen, bis die Gliederung da ist.
      Result := False;
  else
    Result := True;
  end;
end;

/// <summary>Caret der Ansicht AView als Zeile und Zeichen (0-basiert); False ohne gültige Zeile.</summary>
function CaretOf(const AView: IOTAEditView; out ALine, ACharacter: Integer): Boolean;
var
  mCursor: TOTAEditPos;
begin
  mCursor := AView.CursorPos;
  ALine := mCursor.Line - 1;
  ACharacter := 0;
  Result := mCursor.Line >= 1;
  if Result then
  begin
    ACharacter := TLspSession.ColumnToIndex(TAtlasEditorBuffer.LineText(AView, mCursor.Line), mCursor.Col,
      TAtlasEditorBuffer.TabWidth(AView.Buffer));
  end;
end;

/// <summary>Kontextmenü am Glied AIndex (#1786); nur mit editor.breadcrumbsContextMenu.</summary>
procedure TBreadcrumbsState.ContextMenu(ABar: TAtlasBreadcrumbBar; AIndex: Integer; const APoint: TPoint);
begin
  if (ABar <> FActiveBar) or (FSource.FileName = '') or not TAtlasIdeSettings.Current.BreadcrumbsContextMenu then
  begin
    Exit;
  end;
  TAtlasIdeCrumbMenu.Show(APoint, TAtlasCrumbMenuFile.Create(FSource.FileName, FSource.Nodes, FSource.Lines),
    ABar.Crumbs, AIndex, TAtlasIdeBreadcrumbs.FMenuHooks);
end;

procedure TBreadcrumbsState.Jump(ABar: TAtlasBreadcrumbBar; AIndex: Integer; ADeclaration: Boolean);
var
  mJump: TAtlasCrumbJump;
begin
  if (ABar <> FActiveBar) or (AIndex < 0) or (AIndex > High(ABar.Crumbs)) or (FSource.FileName = '') then
  begin
    Exit;
  end;
  TAtlasGuard.Log(Format('Brotkrumen: Sprung zu Glied %d', [AIndex]));
  mJump := TAtlasCrumbPlan.Jump(FSource.Nodes, ABar.Crumbs[AIndex], ADeclaration);
  case mJump.Kind of
    TAtlasCrumbJumpKind.FileStart:
      TAtlasIdeNavigation.GoToLocation(FSource.FileName, 0, 0);
    TAtlasCrumbJumpKind.Place:
      TAtlasIdeNavigation.GoToLocation(FSource.FileName, mJump.Line, mJump.Character);
  else
    // None: kein Ziel.
  end;
end;

/// <summary>Menü erst nach dem Klick öffnen: Die IDE holt den Fokus in den Editor zurück; ein sofort geöffnetes
/// Menü verlöre die Aktivierung und ginge gleich wieder zu. Läuft nur, wenn Zustand und Leiste dann noch
/// leben.</summary>
procedure TBreadcrumbsState.Later(ABar: TAtlasBreadcrumbBar; const AAction: TProc);
var
  mState: TBreadcrumbsState;
  mBar: TAtlasBreadcrumbBar;
  mAction: TProc;
begin
  TAtlasGuard.Log('Brotkrumen: Klick, Menü folgt');
  mState := Self;
  mBar := ABar;
  mAction := AAction;
  TAtlasMainThread.ForceQueue(TAtlasFeature.Breadcrumbs,
    procedure
    begin
      if (TAtlasIdeBreadcrumbs.FState <> mState) or not mState.FHost.Contains(mBar) then
      begin
        Exit;
      end;
      mAction();
    end);
end;

procedure TBreadcrumbsState.Leave(ABar: TAtlasBreadcrumbBar);
begin
  TAtlasIdeEditorWindows.FocusEditor(ABar);
end;

/// <summary>Stand ASnapshot und Leiste ABar übernehmen; True, wenn sich gegenüber dem letzten Stand etwas
/// geändert hat (dann ist der Pfad neu zu bilden).</summary>
function TBreadcrumbsState.Remember(ABar: TAtlasBreadcrumbBar; const ASnapshot: TAtlasOutlineSnapshot): Boolean;
var
  mKey: TAtlasCrumbKey;
  mLines: TArray<string>;
begin
  mKey := TAtlasCrumbKey.Create(ASnapshot.FileName, ASnapshot.Stamp, TAtlasIdeSettings.Current);
  Result := not FShown or (ABar <> FActiveBar) or (ASnapshot.Status <> FKey.Status) or not mKey.Same(FKey.Path);
  if (ASnapshot.Stamp <> FKey.Path.Stamp) or (Pointer(ASnapshot.Nodes) <> Pointer(FSource.Nodes)) then
  begin
    mLines := FSource.Lines;
    if ASnapshot.Stamp <> FKey.Path.Stamp then
    begin
      mLines := TTextLines.SplitLines(ASnapshot.Text);
    end;
    FText := TAtlasBreadcrumbs.Prepare(ASnapshot.Nodes, mLines);
    FSource.Lines := mLines;
  end;
  FShown := True;
  FActiveBar := ABar;
  FKey.Status := ASnapshot.Status;
  FSource.FileName := ASnapshot.FileName;
  FKey.Path := mKey;
  FSource.Nodes := ASnapshot.Nodes;
  FInterfaces := ASnapshot.Interfaces;
end;

procedure TBreadcrumbsState.Removed(ABar: TControl);
begin
  if FActiveBar = ABar then
  begin
    FActiveBar := nil;
    FShown := False;
  end;
end;

procedure TBreadcrumbsState.Reset;
begin
  FSource.FileName := '';
  FKey.Path.Stamp := 0;
  FShown := False;
  HideCard;
  FSource.Line := -1;
  FSource.Character := -1;
  // Farben und Navigationsleiste der IDE nach geänderten Einstellungen.
  ApplyTheme;
  FNavigation.Apply;
end;

procedure TBreadcrumbsState.Update;
var
  mBar: TAtlasBreadcrumbBar;
  mView: IOTAEditView;
  mSnapshot: TAtlasOutlineSnapshot;
  mLine, mCharacter: Integer;
  mChanged: Boolean;
  mRequest: TAtlasCrumbRequest;
  mInterfaces: TAtlasInterfaceMethods;
begin
  EnsureBars;
  mBar := ActiveBar;
  if mBar = nil then
  begin
    Exit;
  end;
  mView := TAtlasEditorBuffer.ActiveView;
  // Interface-Marke (#1785): Der Cache holt die Angaben mit der Gliederung.
  TAtlasIdeOutlineCache.WithInterfaces := TAtlasIdeSettings.Current.BreadcrumbsInterfaces;
  mSnapshot := TAtlasIdeOutlineCache.Refresh(mView);
  mChanged := Remember(mBar, mSnapshot);
  if not ShowsPath(mBar, mSnapshot.Status) or not CaretOf(mView, mLine, mCharacter) then
  begin
    Exit;
  end;
  if not mChanged and (mLine = FSource.Line) and (mCharacter = FSource.Character) then
  begin
    Exit;
  end;
  FSource.Line := mLine;
  FSource.Character := mCharacter;
  mBar.EmptyText := TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsEmpty);
  mRequest := TAtlasCrumbRequest.Create(FSource.Line, FSource.Character,
    ChangeFileExt(ExtractFileName(FSource.FileName), ''), FKey.Path.ShowUnit, FKey.Path.Parts);
  mInterfaces := nil;
  if FKey.Path.WithInterfaces then
  begin
    mInterfaces := FInterfaces;
  end;
  mBar.SetCrumbs(TAtlasIdeCrumbLists.Prepared(TAtlasBreadcrumbs.Path(FText, mRequest),
    mInterfaces, FSource.Nodes));
end;

procedure TBreadcrumbsState.ApplyTheme;
var
  mColors: TAtlasColors;
begin
  mColors := TAtlasIdeStyle.BarColors;
  FHost.ForEach(
    procedure(ABar: TControl)
    begin
      TAtlasBreadcrumbBar(ABar).SetColors(mColors);
    end);
end;

function TBreadcrumbsState.ActiveBar: TAtlasBreadcrumbBar;
begin
  Result := TAtlasBreadcrumbBar(FHost.ActiveBar);
end;

{ TAtlasIdeBreadcrumbs }

/// <summary>Bedarf an den Metriken nur mit Leiste und Karte (#1787); meldet nur Änderungen.</summary>
class procedure TAtlasIdeBreadcrumbs.WantMetrics;
var
  mWants: Boolean;
begin
  mWants := (FState <> nil) and TAtlasIdeSettings.Current.BreadcrumbsMetrics;
  if (mWants = FWantsMetrics) or not Assigned(FCardHooks.WantMetrics) then
  begin
    Exit;
  end;
  FWantsMetrics := mWants;
  FCardHooks.WantMetrics(mWants);
end;

class procedure TAtlasIdeBreadcrumbs.Install(const AMenuHooks: TAtlasCrumbMenuHooks;
  const ACardHooks: TAtlasCrumbCardHooks);
begin
  FreeAndNil(FState);
  FMenuHooks := AMenuHooks;
  FCardHooks := ACardHooks;
  FWantsMetrics := False;
  // Auch bei ausgelöster Sicherung: Die Leiste zeigt dann den Hinweis (ShowDisabled).
  if Enabled then
  begin
    FState := TBreadcrumbsState.Create;
  end
  else
  begin
    // Hatte Atlas die Navigationsleiste ausgeblendet und die IDE endete ohne Entladen: wieder zeigen.
    TAtlasIdeNavigationOption.Apply(False);
  end;
  WantMetrics;
end;

class procedure TAtlasIdeBreadcrumbs.Uninstall;
begin
  FreeAndNil(FState);
  WantMetrics;
  FMenuHooks := Default(TAtlasCrumbMenuHooks);
  FCardHooks := Default(TAtlasCrumbCardHooks);
end;

class procedure TAtlasIdeBreadcrumbs.ApplySettings;
begin
  // Aus: alle Leisten weg, der Editor bekommt seine Höhe zurück.
  if not Enabled then
  begin
    FreeAndNil(FState);
    WantMetrics;
    Exit;
  end;
  if FState = nil then
  begin
    FState := TBreadcrumbsState.Create;
  end
  else
  begin
    TBreadcrumbsState(FState).Reset;
  end;
  WantMetrics;
end;

class procedure TAtlasIdeBreadcrumbs.ThemeChanged;
begin
  if FState <> nil then
  begin
    TBreadcrumbsState(FState).ApplyTheme;
  end;
end;

class procedure TAtlasIdeBreadcrumbs.Focus;
var
  mBar: TAtlasBreadcrumbBar;
begin
  if (FState = nil) or not Active then
  begin
    Exit;
  end;
  TBreadcrumbsState(FState).Update;
  mBar := TBreadcrumbsState(FState).ActiveBar;
  if mBar <> nil then
  begin
    mBar.FocusLast;
  end;
end;

class function TAtlasIdeBreadcrumbs.Enabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Breadcrumbs;
end;

end.
