unit Atlas.IDE.Outline.Breadcrumbs;

// Brotkrumenleiste (#590) in der IDE:
// - Über dem Editor jedes Editorfensters steht eine Leiste
//   (TAtlasBreadcrumbBar, alTop im Eltern-Steuerelement des Editors
//   „Editor“). Fenster, die später aufgehen, bekommen sie beim nächsten Takt.
// - Ein Zeitgeber (150 ms) rechnet für die aktive Ansicht den Pfad am Caret
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
//   (früher gemeinsam Editorbefehle) schalten die Leiste nicht mehr still ab.
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
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Text.Lines,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Style.Palette,
  Atlas.Core.Outline.Model,
  Atlas.Core.Outline.Breadcrumbs,
  Atlas.Core.Outline.VisibilitySections,
  Atlas.Core.Outline.SectionEdit,
  Atlas.Core.Outline.Overloads,
  Atlas.Core.Outline.Interfaces,
  Atlas.Core.Editor.CrumbCard,
  Atlas.UI.Outline.Strings,
  Atlas.UI.Popup.CrumbCard,
  Atlas.UI.Commands.Palette,
  Atlas.UI.Outline.Breadcrumbs,
  Atlas.UI.Outline.NavigationToolbar,
  Atlas.IDE.Outline.NavigationOption,
  Atlas.IDE.Outline.SectionEdit,
  Atlas.IDE.Foundation.EditorBarHost,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Outline.Cache;

const
  cTickMs = 150;
  cMenuWidth = 380;
  /// <summary>Kennungen der Menüeinträge „Neue Zeile am Ende von …“ und „Abschnitt anlegen“ (#1768).</summary>
  cAppendId = 'append:';
  cCreateId = 'create:';
  /// <summary>Höchstlänge von Name und Parametern im Menü (#1784); länger mit „…“.</summary>
  cOverloadCaptionMax = 56;

type
  TBreadcrumbsState = class
  private
    FTimer: TTimer;
    FHost: TAtlasEditorBarHost;
    FFileName: string;
    FStamp: Cardinal;
    FStatus: TAtlasOutlineStatus;
    FNodes: TAtlasOutlineNodes;
    FInterfaces: TAtlasInterfaceMethods;
    FWithInterfaces: Boolean;
    /// <summary>Für den Pfad ausgewerteter Text mit seinen Zeilen, je Stand der Gliederung einmal (Remember).
    /// </summary>
    FText: TAtlasCrumbText;
    FLine: Integer;
    FCharacter: Integer;
    FShowUnit: Boolean;
    FParts: TAtlasCrumbParts;
    FShown: Boolean;
    FActiveBar: TAtlasBreadcrumbBar;
    FToolbars: TAtlasNavigationToolbar;
    /// <summary>Blendet die IDE die Navigationsleiste über ihre Option aus? Dann hängt Atlas nichts um.</summary>
    FToolbarByIde: Boolean;
    /// <summary>Fenster, das zuletzt unter der Maus über der Leiste lag (Diagnose).</summary>
    FProbed: HWND;
    /// <summary>Zeigen die Leisten gerade den Hinweis „abgeschaltet“?</summary>
    FDisabled: Boolean;
    /// <summary>Zuletzt protokollierte Ursache am Fenster der Leiste ('' = keine).</summary>
    FProblem: string;
    /// <summary>Kennzahlen-Karte (#1787); erst beim ersten Zeigen angelegt.</summary>
    FCard: TAtlasCrumbCardTip;
    function HasCard(ABar: TAtlasBreadcrumbBar; AIndex: Integer): Boolean;
    procedure ShowCard(ABar: TAtlasBreadcrumbBar; AIndex: Integer; const APoint: TPoint);
    procedure HideCard;
    procedure Tick(Sender: TObject);
    procedure Probe;
    procedure ShowDisabled;
    procedure EnsureBars;
    function CreateBar: TAtlasBreadcrumbBar;
    procedure Place(ABar: TAtlasBreadcrumbBar; AParent: TWinControl);
    procedure OpenMenu(ABar: TAtlasBreadcrumbBar; AIndex: Integer; const APoint: TPoint);
    procedure OpenChildren(ABar: TAtlasBreadcrumbBar; AIndex: Integer; const APoint: TPoint);
    procedure OpenList(ABar: TAtlasBreadcrumbBar; const APrompt: string; const AItems: TArray<Integer>;
      ACurrent: Integer; const APoint: TPoint; AOverloads: Boolean = False);
    procedure OpenOverloads(ABar: TAtlasBreadcrumbBar; AIndex: Integer; const APoint: TPoint);
    procedure OpenInterfaces(ABar: TAtlasBreadcrumbBar; AIndex: Integer; const APoint: TPoint);
    function MarkInterfaces(const ACrumbs: TAtlasCrumbs): TAtlasCrumbs;
    procedure OpenPlaces(ABar: TAtlasBreadcrumbBar; const ACrumb: TAtlasCrumb; const APoint: TPoint);
    procedure ContextMenu(ABar: TAtlasBreadcrumbBar; AIndex: Integer; const APoint: TPoint);
    procedure Jump(ABar: TAtlasBreadcrumbBar; AIndex: Integer; ADeclaration: Boolean);
    procedure Later(ABar: TAtlasBreadcrumbBar; const AAction: TProc);
    procedure ApplyToolbar(AParent: TWinControl);
    procedure Leave(ABar: TAtlasBreadcrumbBar);
    function CommandsOf(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
      const AIndices: TArray<Integer>; ACurrent: Integer; AOverloads: Boolean): TArray<TAtlasCommand>;
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
  FHost.ShowIn := TAtlasEditorBarView.Code;
  FToolbars := TAtlasNavigationToolbar.Create(nil);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
  Reset;
end;

destructor TBreadcrumbsState.Destroy;
begin
  FTimer.Free;
  FCard.Free;
  // Navigationsleisten der IDE wieder zeigen: Option zurück, wenn Atlas sie ausgeschaltet hatte, bzw. zurückhängen.
  TAtlasIdeNavigationOption.Apply(False);
  TAtlasIdeCrumbMenu.Release;
  FToolbars.Free;
  FHost.Free;
  inherited Destroy;
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
var
  mHide: Boolean;
begin
  FFileName := '';
  FStamp := 0;
  FShown := False;
  HideCard;
  FLine := -1;
  FCharacter := -1;
  // Farben und Navigationsleiste der IDE nach geänderten Einstellungen. Die Leiste blendet die IDE über ihre
  // Option aus; umgehängt wird nur ohne diese Option (Netz).
  ApplyTheme;
  mHide := TAtlasIdeSettings.Current.BreadcrumbsHideIdeToolbar;
  FToolbarByIde := TAtlasIdeNavigationOption.Apply(mHide);
  if FToolbarByIde or not mHide then
  begin
    FToolbars.RestoreAll;
  end;
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

/// <summary>Netz, nur ohne Option der IDE (siehe Reset): Navigationsleiste in ein eigenes Panel umhängen.</summary>
procedure TBreadcrumbsState.ApplyToolbar(AParent: TWinControl);
begin
  if FToolbarByIde then
  begin
    Exit;
  end;
  if TAtlasIdeSettings.Current.BreadcrumbsHideIdeToolbar then
  begin
    FToolbars.Apply(AParent, True);
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
    if TAtlasEditorBarHost.EditorOf(mServices.EditWindow[mIndex]) <> nil then
    begin
      ApplyToolbar(mServices.EditWindow[mIndex].Form);
    end;
  end;
end;

/// <summary>Eigene Methode: Jede Leiste braucht ihre eigene gefangene Variable. Einordnen und Wächter: Host.</summary>
function TBreadcrumbsState.CreateBar: TAtlasBreadcrumbBar;
var
  mBar: TAtlasBreadcrumbBar;
  mHost: TAtlasEditorBarHost;
begin
  mBar := TAtlasBreadcrumbBar.Create(nil);
  mHost := FHost;
  mBar.SetColors(TAtlasIdeStyle.BarColors);
  mBar.EmptyText := TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsEmpty);
  mBar.CrumbHint := TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsCrumbHint);
  mBar.SeparatorHint := TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsChildrenHint);
  mBar.MarkHint := TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsMarkHint);
  mBar.OverloadHint := TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsOverloadsHint);
  mBar.InterfaceHint := TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsInterfacesHint);
  mBar.InterfaceKeyHint := TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsInterfacesKey);
  mBar.OnOpenMenu :=
    procedure(AIndex: Integer; const APoint: TPoint)
    var
      At: TPoint;
    begin
      At := APoint;
      Later(mBar,
        procedure
        begin
          OpenMenu(mBar, AIndex, At);
        end);
    end;
  mBar.OnOpenChildren :=
    procedure(AIndex: Integer; const APoint: TPoint)
    var
      At: TPoint;
    begin
      At := APoint;
      Later(mBar,
        procedure
        begin
          OpenChildren(mBar, AIndex, At);
        end);
    end;
  mBar.OnOpenOverloads :=
    procedure(AIndex: Integer; const APoint: TPoint)
    var
      At: TPoint;
    begin
      At := APoint;
      Later(mBar,
        procedure
        begin
          OpenOverloads(mBar, AIndex, At);
        end);
    end;
  mBar.OnOpenInterfaces :=
    procedure(AIndex: Integer; const APoint: TPoint)
    var
      At: TPoint;
    begin
      At := APoint;
      Later(mBar,
        procedure
        begin
          OpenInterfaces(mBar, AIndex, At);
        end);
    end;
  mBar.OnContextMenu :=
    procedure(AIndex: Integer; const APoint: TPoint)
    var
      At: TPoint;
    begin
      At := APoint;
      Later(mBar,
        procedure
        begin
          ContextMenu(mBar, AIndex, At);
        end);
    end;
  mBar.OnJump :=
    procedure(AIndex: Integer; ADeclaration: Boolean)
    begin
      TAtlasGuard.Run(TAtlasFeature.Breadcrumbs,
        procedure
        begin
          Jump(mBar, AIndex, ADeclaration);
        end);
    end;
  mBar.OnLeave :=
    procedure
    begin
      Leave(mBar);
    end;
  mBar.HasCard :=
    function(AIndex: Integer): Boolean
    begin
      Result := HasCard(mBar, AIndex);
    end;
  mBar.OnShowCard :=
    procedure(AIndex: Integer; const APoint: TPoint)
    var
      At: TPoint;
    begin
      At := APoint;
      TAtlasGuard.Run(TAtlasFeature.Breadcrumbs,
        procedure
        begin
          ShowCard(mBar, AIndex, At);
        end);
    end;
  mBar.OnHideCard :=
    procedure
    begin
      HideCard;
    end;
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

function TBreadcrumbsState.ActiveBar: TAtlasBreadcrumbBar;
begin
  Result := TAtlasBreadcrumbBar(FHost.ActiveBar);
end;

/// <summary>Text eines Sprungziels; Regionen ohne Namen als „Region (Z. n)“ (#1764).</summary>
function PlaceText(const APlace: TAtlasCrumbPlace): string;
begin
  Result := APlace.Text;
  if Result = '' then
  begin
    Result := Format(TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsRegionUnnamed), [APlace.Line + 1]);
  end;
end;

/// <summary>Glieder mit Namen für Regionen ohne Text (#1764).</summary>
function NamedRegions(const ACrumbs: TAtlasCrumbs): TAtlasCrumbs;
var
  mIndex: Integer;
begin
  Result := ACrumbs;
  for mIndex := 0 to High(Result) do
  begin
    if (Result[mIndex].Text = '') and (Result[mIndex].Current >= 0) and
      (Result[mIndex].Current <= High(Result[mIndex].Places)) then
    begin
      Result[mIndex].Text := PlaceText(Result[mIndex].Places[Result[mIndex].Current]);
    end;
  end;
end;

/// <summary>Zusätzliche Glieder nach den Einstellungen (#1759, #1767, #1765, #1766, #1763, #1764, #1769, #1784).
/// </summary>
function CrumbParts: TAtlasCrumbParts;
begin
  Result := [];
  if TAtlasIdeSettings.Current.BreadcrumbsVisibility then
  begin
    Include(Result, TAtlasCrumbPart.Visibility);
  end;
  if TAtlasIdeSettings.Current.BreadcrumbsMemberBlocks then
  begin
    Include(Result, TAtlasCrumbPart.MemberBlocks);
  end;
  if TAtlasIdeSettings.Current.BreadcrumbsVisibilityMark then
  begin
    Include(Result, TAtlasCrumbPart.VisibilityMark);
  end;
  if TAtlasIdeSettings.Current.BreadcrumbsDeclarationBlocks then
  begin
    Include(Result, TAtlasCrumbPart.DeclarationBlocks);
  end;
  if TAtlasIdeSettings.Current.BreadcrumbsConditionals then
  begin
    Include(Result, TAtlasCrumbPart.Conditionals);
  end;
  if TAtlasIdeSettings.Current.BreadcrumbsRegions then
  begin
    Include(Result, TAtlasCrumbPart.Regions);
  end;
  if TAtlasIdeSettings.Current.BreadcrumbsStatements then
  begin
    Include(Result, TAtlasCrumbPart.Statements);
  end;
  if TAtlasIdeSettings.Current.BreadcrumbsOverloads then
  begin
    Include(Result, TAtlasCrumbPart.Overloads);
  end;
end;

/// <summary>Stand ASnapshot und Leiste ABar übernehmen; True, wenn sich gegenüber dem letzten Stand etwas
/// geändert hat (dann ist der Pfad neu zu bilden).</summary>
function TBreadcrumbsState.Remember(ABar: TAtlasBreadcrumbBar; const ASnapshot: TAtlasOutlineSnapshot): Boolean;
var
  mShowUnit, mWithInterfaces: Boolean;
  mParts: TAtlasCrumbParts;
  mLines: TArray<string>;
begin
  mShowUnit := TAtlasIdeSettings.Current.BreadcrumbsShowUnit;
  mWithInterfaces := TAtlasIdeSettings.Current.BreadcrumbsInterfaces;
  mParts := CrumbParts;
  Result := not FShown or (ABar <> FActiveBar) or (ASnapshot.Status <> FStatus) or
    not SameText(ASnapshot.FileName, FFileName) or (ASnapshot.Stamp <> FStamp) or (mShowUnit <> FShowUnit) or
    (mParts <> FParts) or (mWithInterfaces <> FWithInterfaces);
  if (ASnapshot.Stamp <> FStamp) or (Pointer(ASnapshot.Nodes) <> Pointer(FNodes)) then
  begin
    mLines := FText.Lines;
    if ASnapshot.Stamp <> FStamp then
    begin
      mLines := TTextLines.SplitLines(ASnapshot.Text);
    end;
    FText := TAtlasBreadcrumbs.Prepare(ASnapshot.Nodes, mLines);
  end;
  FShown := True;
  FActiveBar := ABar;
  FStatus := ASnapshot.Status;
  FFileName := ASnapshot.FileName;
  FStamp := ASnapshot.Stamp;
  FShowUnit := mShowUnit;
  FParts := mParts;
  FWithInterfaces := mWithInterfaces;
  FNodes := ASnapshot.Nodes;
  FInterfaces := ASnapshot.Interfaces;
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

procedure TBreadcrumbsState.Update;
var
  mBar: TAtlasBreadcrumbBar;
  mView: IOTAEditView;
  mSnapshot: TAtlasOutlineSnapshot;
  mLine, mCharacter: Integer;
  mChanged: Boolean;
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
  if not mChanged and (mLine = FLine) and (mCharacter = FCharacter) then
  begin
    Exit;
  end;
  FLine := mLine;
  FCharacter := mCharacter;
  mBar.EmptyText := TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsEmpty);
  mBar.SetCrumbs(MarkInterfaces(NamedRegions(TAtlasBreadcrumbs.Path(FText, FLine, FCharacter,
    ChangeFileExt(ExtractFileName(FFileName), ''), FShowUnit, FParts))));
end;

/// <summary>Erfüllte Interface-Methoden an die Methodenglieder (#1785); nur mit editor.breadcrumbsInterfaces.
/// </summary>
function TBreadcrumbsState.MarkInterfaces(const ACrumbs: TAtlasCrumbs): TAtlasCrumbs;
var
  mIndex: Integer;
begin
  Result := ACrumbs;
  if not FWithInterfaces or (Length(FInterfaces) = 0) then
  begin
    Exit;
  end;
  for mIndex := 0 to High(Result) do
  begin
    Result[mIndex].Interfaces := TAtlasOutlineInterfaces.TargetsOf(FInterfaces, FNodes, Result[mIndex].Node);
  end;
end;

function TBreadcrumbsState.CommandsOf(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
  const AIndices: TArray<Integer>; ACurrent: Integer; AOverloads: Boolean): TArray<TAtlasCommand>;
var
  mNode: Integer;
  mCommand: TAtlasCommand;
begin
  Result := nil;
  for mNode in AIndices do
  begin
    mCommand := Default(TAtlasCommand);
    mCommand.Id := IntToStr(mNode);
    mCommand.Caption := TAtlasBreadcrumbs.ShortName(ANodes[mNode].Name);
    mCommand.Path := ANodes[mNode].Detail;
    // Überladungen (#1784) mit Parametern, gekürzt; der Hinweis zeigt die volle Liste.
    if AOverloads or (TAtlasIdeSettings.Current.BreadcrumbsOverloads and
      (Length(TAtlasOverloads.Find(ANodes, mNode)) > 0)) then
    begin
      mCommand.Caption := TAtlasOverloads.Caption(ANodes, ALines, mNode, cOverloadCaptionMax);
      mCommand.Description := TAtlasOverloads.Caption(ANodes, ALines, mNode, MaxInt);
    end;
    if AOverloads then
    begin
      mCommand.Path := Format(TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsPlaceLineOnly),
        [ANodes[mNode].NameLine + 1]);
    end;
    if mNode = ACurrent then
    begin
      mCommand.ShortCut := TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsCurrent);
    end;
    Result := Result + [mCommand];
  end;
end;

procedure TBreadcrumbsState.OpenMenu(ABar: TAtlasBreadcrumbBar; AIndex: Integer; const APoint: TPoint);
var
  mCrumb: TAtlasCrumb;
begin
  if (ABar <> FActiveBar) or (AIndex < 0) or (AIndex > High(ABar.Crumbs)) then
  begin
    Exit;
  end;
  mCrumb := ABar.Crumbs[AIndex];
  if Length(mCrumb.Places) > 0 then
  begin
    OpenPlaces(ABar, mCrumb, APoint);
    Exit;
  end;
  OpenList(ABar, mCrumb.Text, mCrumb.Siblings, mCrumb.Node, APoint);
end;

/// <summary>Menü „Überladungen von …“ am Zähler des Glieds (#1784).</summary>
procedure TBreadcrumbsState.OpenOverloads(ABar: TAtlasBreadcrumbBar; AIndex: Integer; const APoint: TPoint);
var
  mCrumb: TAtlasCrumb;
begin
  if (ABar <> FActiveBar) or (AIndex < 0) or (AIndex > High(ABar.Crumbs)) then
  begin
    Exit;
  end;
  mCrumb := ABar.Crumbs[AIndex];
  OpenList(ABar, Format(TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsOverloadsPrompt), [mCrumb.Text]),
    mCrumb.Overloads, mCrumb.Node, APoint, True);
end;

/// <summary>Einträge des Menüs „Erfüllt“ (#1785), die zum Muster APattern passen: Interface-Methode, darunter
/// Datei und Zeile.</summary>
function InterfaceCommands(const ATargets: TAtlasInterfaceTargets; const APattern: string): TArray<TAtlasCommand>;
var
  mIndex: Integer;
  mCommand: TAtlasCommand;
begin
  Result := nil;
  for mIndex := 0 to High(ATargets) do
  begin
    if not TAtlasBreadcrumbs.MatchesAtWordStart(APattern, ATargets[mIndex].Name) then
    begin
      Continue;
    end;
    mCommand := Default(TAtlasCommand);
    mCommand.Id := IntToStr(mIndex);
    mCommand.Caption := ATargets[mIndex].Name;
    mCommand.Path := Format(TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsInterfacesPath),
      [ExtractFileName(ATargets[mIndex].FileName), ATargets[mIndex].Line + 1]);
    Result := Result + [mCommand];
  end;
end;

/// <summary>Menü „Erfüllt“ an der Interface-Marke des Glieds (#1785): Interface-Methoden mit Unit und Zeile; Enter
/// springt zur Deklaration im Interface.</summary>
procedure TBreadcrumbsState.OpenInterfaces(ABar: TAtlasBreadcrumbBar; AIndex: Integer; const APoint: TPoint);
var
  mTargets: TAtlasInterfaceTargets;
  mWindow: TAtlasPaletteWindow;
  mCommands: TArray<TAtlasCommand>;
begin
  if (ABar <> FActiveBar) or (AIndex < 0) or (AIndex > High(ABar.Crumbs)) then
  begin
    Exit;
  end;
  // Kopie: Das Menü lebt länger als der aktuelle Stand.
  mTargets := ABar.Crumbs[AIndex].Interfaces;
  if Length(mTargets) = 0 then
  begin
    Exit;
  end;
  mCommands := InterfaceCommands(mTargets, '');
  mWindow := TAtlasPaletteWindow.CreatePalette(Application, mCommands, nil, TAtlasIdeStyle.Colors);
  mWindow.Prompt := TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsInterfacesPrompt);
  mWindow.Presorted := True;
  mWindow.QueryDelay := 0;
  mWindow.OnQuery :=
    function(APattern: string): TArray<TAtlasCommand>
    begin
      Result := InterfaceCommands(mTargets, APattern);
    end;
  mWindow.OnExecuteShift :=
    procedure(ACommand: TAtlasCommand; AShifted: Boolean)
    var
      mChosen: Integer;
    begin
      mChosen := StrToIntDef(ACommand.Id, -1);
      if (mChosen >= 0) and (mChosen <= High(mTargets)) and (mTargets[mChosen].FileName <> '') then
      begin
        TAtlasIdeNavigation.GoToLocation(mTargets[mChosen].FileName, mTargets[mChosen].Line,
          mTargets[mChosen].Character);
      end;
    end;
  mWindow.ShowAt(APoint, MulDiv(cMenuWidth, ABar.CurrentPPI, 96));
end;

procedure TBreadcrumbsState.OpenChildren(ABar: TAtlasBreadcrumbBar; AIndex: Integer; const APoint: TPoint);
var
  mCrumb: TAtlasCrumb;
  mCurrent, mNext: Integer;
begin
  if (ABar <> FActiveBar) or (AIndex < 0) or (AIndex > High(ABar.Crumbs)) then
  begin
    Exit;
  end;
  mCrumb := ABar.Crumbs[AIndex];
  // Vorgewählt ist das Kind, in dem der Caret steht: das nächste Glied mit Knoten (ein Abschnittsglied
  // dazwischen hat keinen).
  mCurrent := -1;
  mNext := AIndex + 1;
  while (mCurrent < 0) and (mNext <= High(ABar.Crumbs)) do
  begin
    mCurrent := ABar.Crumbs[mNext].Node;
    Inc(mNext);
  end;
  OpenList(ABar, mCrumb.Text + ' ›', mCrumb.Children, mCurrent, APoint);
end;

procedure TBreadcrumbsState.OpenList(ABar: TAtlasBreadcrumbBar; const APrompt: string;
  const AItems: TArray<Integer>; ACurrent: Integer; const APoint: TPoint; AOverloads: Boolean);
var
  mItems: TArray<Integer>;
  mNodes: TAtlasOutlineNodes;
  mLines: TArray<string>;
  mFileName: string;
  mWindow: TAtlasPaletteWindow;
begin
  if (Length(AItems) = 0) or (FFileName = '') then
  begin
    TAtlasGuard.Log(Format('Brotkrumen: kein Menü (Einträge %d, Datei %s)', [Length(AItems),
      BoolToStr(FFileName <> '', True)]));
    Exit;
  end;
  // Kopien: Das Menü lebt länger als der aktuelle Stand.
  mItems := AItems;
  mNodes := FNodes;
  mLines := FText.Lines;
  mFileName := FFileName;
  mWindow := TAtlasPaletteWindow.CreatePalette(Application, CommandsOf(mNodes, mLines, mItems, ACurrent,
    AOverloads), nil, TAtlasIdeStyle.Colors);
  mWindow.Prompt := APrompt;
  mWindow.RowHints := True;
  mWindow.Presorted := True;
  mWindow.QueryDelay := 0;
  if ACurrent >= 0 then
  begin
    mWindow.InitialId := IntToStr(ACurrent);
  end;
  mWindow.OnQuery :=
    function(APattern: string): TArray<TAtlasCommand>
    begin
      Result := CommandsOf(mNodes, mLines, TAtlasBreadcrumbs.Filter(mNodes, mItems, APattern), ACurrent,
        AOverloads);
    end;
  mWindow.OnExecuteShift :=
    procedure(ACommand: TAtlasCommand; AShifted: Boolean)
    var
      Node, Target: Integer;
    begin
      Node := StrToIntDef(ACommand.Id, -1);
      if (Node < 0) or (Node > High(mNodes)) then
      begin
        Exit;
      end;
      // Enter zur Implementierung, Umschalt+Enter zur Deklaration.
      Target := TAtlasBreadcrumbs.Target(mNodes, Node, not AShifted);
      if Target < 0 then
      begin
        Exit;
      end;
      TAtlasIdeNavigation.GoToLocation(mFileName, mNodes[Target].NameLine, mNodes[Target].NameCharacter);
    end;
  mWindow.ShowAt(APoint, MulDiv(cMenuWidth, ABar.CurrentPPI, 96));
end;

/// <summary>Gedimmte Zeile eines Sprungziels: bei Sichtbarkeitsabschnitten mit Mitgliederzahl (#1768,
/// ACounts), bei Deklarationsblöcken (#1766) mit dem Teil der Unit, sonst nur die Zeile.</summary>
function PlacePath(const APlace: TAtlasCrumbPlace; ACounts: Boolean): string;
begin
  if ACounts and (APlace.Mark <> '') then
  begin
    if APlace.Count = 1 then
    begin
      Result := Format(TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsSectionCountOne), [APlace.Line + 1]);
    end
    else
    begin
      Result := Format(TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsSectionCount), [APlace.Count,
        APlace.Line + 1]);
    end;
  end
  else if APlace.Group <> '' then
  begin
    Result := Format(TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsPlaceLine), [APlace.Group,
      APlace.Line + 1]);
  end
  else
  begin
    Result := Format(TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsPlaceLineOnly), [APlace.Line + 1]);
  end;
end;

function PlaceCommands(const APlaces: TArray<TAtlasCrumbPlace>; const APattern: string;
  ACurrent: Integer; ACounts: Boolean): TArray<TAtlasCommand>;
var
  mIndex: Integer;
  mCommand: TAtlasCommand;
  mText: string;
begin
  Result := nil;
  for mIndex := 0 to High(APlaces) do
  begin
    mText := PlaceText(APlaces[mIndex]);
    if not TAtlasBreadcrumbs.MatchesAtWordStart(APattern, mText) then
    begin
      Continue;
    end;
    mCommand := Default(TAtlasCommand);
    mCommand.Id := IntToStr(mIndex);
    // Verschachtelte Regionen (#1764) eingerückt.
    mCommand.Caption := StringOfChar(' ', 4 * APlaces[mIndex].Depth) + mText;
    // Marke der Gliederung vor dem Abschnitt (#1768).
    if ACounts and (APlaces[mIndex].Mark <> '') then
    begin
      mCommand.Caption := APlaces[mIndex].Mark + ' ' + mCommand.Caption;
    end;
    mCommand.Path := PlacePath(APlaces[mIndex], ACounts);
    if mIndex = ACurrent then
    begin
      mCommand.ShortCut := TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsCurrent);
    end;
    Result := Result + [mCommand];
  end;
end;

/// <summary>Einträge „Neue Zeile am Ende von …“ je Abschnitt und „Abschnitt anlegen: …“ je fehlendem Abschnitt
/// (#1768), soweit an und zum Muster passend.</summary>
function SectionCommands(const APlaces: TArray<TAtlasCrumbPlace>; const AMissing: TArray<string>;
  const APattern: string): TArray<TAtlasCommand>;
var
  mIndex: Integer;
  mCommand: TAtlasCommand;
  mKeyword: string;
begin
  Result := nil;
  if TAtlasIdeSettings.Current.BreadcrumbsSectionAppend then
  begin
    for mIndex := 0 to High(APlaces) do
    begin
      mCommand := Default(TAtlasCommand);
      mCommand.Id := cAppendId + IntToStr(mIndex);
      mCommand.Caption := Format(TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsSectionAppend),
        [APlaces[mIndex].Text]);
      if TAtlasBreadcrumbs.MatchesAtWordStart(APattern, mCommand.Caption) then
      begin
        Result := Result + [mCommand];
      end;
    end;
  end;
  if TAtlasIdeSettings.Current.BreadcrumbsSectionCreate then
  begin
    for mKeyword in AMissing do
    begin
      mCommand := Default(TAtlasCommand);
      mCommand.Id := cCreateId + mKeyword;
      mCommand.Caption := Format(TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsSectionCreate), [mKeyword]);
      if TAtlasBreadcrumbs.MatchesAtWordStart(APattern, mCommand.Caption) then
      begin
        Result := Result + [mCommand];
      end;
    end;
  end;
end;

/// <summary>Sprungziele und, beim Sichtbarkeitsglied (AEditable), die Einträge zum Ändern (#1768).</summary>
function MenuCommands(const APlaces: TArray<TAtlasCrumbPlace>; const AMissing: TArray<string>;
  const APattern: string; ACurrent: Integer; ACounts, AEditable: Boolean): TArray<TAtlasCommand>;
begin
  Result := PlaceCommands(APlaces, APattern, ACurrent, ACounts);
  if AEditable then
  begin
    Result := Result + SectionCommands(APlaces, AMissing, APattern);
  end;
end;

/// <summary>Menü der Sprungziele eines Glieds ohne Knoten (Sichtbarkeitsabschnitte des Typs, #1759); beim
/// Sichtbarkeitsglied dahinter „Neue Zeile am Ende von …“ und „Abschnitt anlegen: …“ (#1768).</summary>
procedure TBreadcrumbsState.OpenPlaces(ABar: TAtlasBreadcrumbBar; const ACrumb: TAtlasCrumb; const APoint: TPoint);
var
  mPlaces: TArray<TAtlasCrumbPlace>;
  mMissing: TArray<string>;
  mNodes: TAtlasOutlineNodes;
  mLines: TArray<string>;
  mCurrent, mLine, mCharacter: Integer;
  mFileName: string;
  mCounts, mEditable: Boolean;
  mWindow: TAtlasPaletteWindow;
begin
  if FFileName = '' then
  begin
    Exit;
  end;
  // Kopien: Das Menü lebt länger als der aktuelle Stand.
  mPlaces := ACrumb.Places;
  mCurrent := ACrumb.Current;
  mFileName := FFileName;
  mNodes := FNodes;
  mLines := FText.Lines;
  mLine := FLine;
  mCharacter := FCharacter;
  mCounts := TAtlasIdeSettings.Current.BreadcrumbsSectionCounts;
  // Nur das Sichtbarkeitsglied bekommt die Einträge zum Ändern.
  mEditable := ACrumb.SectionType >= 0;
  mMissing := nil;
  if mEditable then
  begin
    mMissing := TAtlasSectionEditor.Missing(mNodes, TAtlasVisibilitySectionFinder.At(mNodes, mLines, mLine,
      mCharacter));
  end;
  mWindow := TAtlasPaletteWindow.CreatePalette(Application, MenuCommands(mPlaces, mMissing, '', mCurrent, mCounts,
    mEditable), nil, TAtlasIdeStyle.Colors);
  mWindow.Prompt := ACrumb.Text;
  mWindow.Presorted := True;
  mWindow.QueryDelay := 0;
  if mCurrent >= 0 then
  begin
    mWindow.InitialId := IntToStr(mCurrent);
  end;
  mWindow.OnQuery :=
    function(APattern: string): TArray<TAtlasCommand>
    begin
      Result := MenuCommands(mPlaces, mMissing, APattern, mCurrent, mCounts, mEditable);
    end;
  mWindow.OnExecuteShift :=
    procedure(ACommand: TAtlasCommand; AShifted: Boolean)
    var
      mChosen: Integer;
    begin
      if ACommand.Id.StartsWith(cAppendId) then
      begin
        TAtlasIdeSectionEdit.Append(mFileName, mNodes, mLines, mLine, mCharacter,
          StrToIntDef(ACommand.Id.Substring(Length(cAppendId)), -2));
        Exit;
      end;
      if ACommand.Id.StartsWith(cCreateId) then
      begin
        TAtlasIdeSectionEdit.Add(mFileName, mNodes, mLines, mLine, mCharacter,
          ACommand.Id.Substring(Length(cCreateId)));
        Exit;
      end;
      mChosen := StrToIntDef(ACommand.Id, -1);
      if (mChosen >= 0) and (mChosen <= High(mPlaces)) then
      begin
        TAtlasIdeNavigation.GoToLocation(mFileName, mPlaces[mChosen].Line, mPlaces[mChosen].Character);
      end;
    end;
  mWindow.ShowAt(APoint, MulDiv(cMenuWidth, ABar.CurrentPPI, 96));
end;

procedure TBreadcrumbsState.Jump(ABar: TAtlasBreadcrumbBar; AIndex: Integer; ADeclaration: Boolean);
var
  mCrumb: TAtlasCrumb;
  mTarget: Integer;
begin
  if (ABar <> FActiveBar) or (AIndex < 0) or (AIndex > High(ABar.Crumbs)) or (FFileName = '') then
  begin
    Exit;
  end;
  mCrumb := ABar.Crumbs[AIndex];
  TAtlasGuard.Log(Format('Brotkrumen: Sprung zu Glied %d', [AIndex]));
  if mCrumb.Node < 0 then
  begin
    // Unit-Glied: an den Anfang der Datei.
    if mCrumb.Badge.Kind = TAtlasBadgeKind.Unit_ then
    begin
      TAtlasIdeNavigation.GoToLocation(FFileName, 0, 0);
    end
    else if (mCrumb.Current >= 0) and (mCrumb.Current <= High(mCrumb.Places)) then
    begin
      // Abschnittsglied: zu seinem Schlüsselwort.
      TAtlasIdeNavigation.GoToLocation(FFileName, mCrumb.Places[mCrumb.Current].Line,
        mCrumb.Places[mCrumb.Current].Character);
    end;
    Exit;
  end;
  mTarget := TAtlasBreadcrumbs.Target(FNodes, mCrumb.Node, not ADeclaration);
  if mTarget < 0 then
  begin
    Exit;
  end;
  TAtlasIdeNavigation.GoToLocation(FFileName, FNodes[mTarget].NameLine, FNodes[mTarget].NameCharacter);
end;

/// <summary>Kontextmenü am Glied AIndex (#1786); nur mit editor.breadcrumbsContextMenu.</summary>
procedure TBreadcrumbsState.ContextMenu(ABar: TAtlasBreadcrumbBar; AIndex: Integer; const APoint: TPoint);
begin
  if (ABar <> FActiveBar) or (FFileName = '') or not TAtlasIdeSettings.Current.BreadcrumbsContextMenu then
  begin
    Exit;
  end;
  TAtlasIdeCrumbMenu.Show(APoint, FFileName, FNodes, FText.Lines, ABar.Crumbs, AIndex,
    TAtlasIdeBreadcrumbs.FMenuHooks);
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
  TAtlasEditorBarHost.FocusEditor(ABar);
end;

function TBreadcrumbsState.HasCard(ABar: TAtlasBreadcrumbBar; AIndex: Integer): Boolean;
begin
  Result := TAtlasIdeSettings.Current.BreadcrumbsMetrics and (ABar = FActiveBar) and (AIndex >= 0) and
    (AIndex <= High(ABar.Crumbs)) and TAtlasCrumbCards.HasCard(FNodes, ABar.Crumbs[AIndex].Node);
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
    TAtlasIdeBreadcrumbs.FCardHooks.Metrics(FFileName, mMetrics);
  if FCard = nil then
  begin
    FCard := TAtlasCrumbCardTip.Create(nil);
  end;
  FCard.Colors := TAtlasIdeStyle.Colors;
  FCard.ShowCard(TAtlasCrumbCards.Build(FNodes, FText.Lines, ABar.Crumbs[AIndex].Node, mHasMetrics, mMetrics),
    APoint);
end;

procedure TBreadcrumbsState.HideCard;
begin
  if (FCard <> nil) and FCard.IsShown then
  begin
    FCard.HidePopup;
  end;
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
    FLine := -1;
    FCharacter := -1;
    TAtlasGuard.Log('Brotkrumen: wieder eingeschaltet');
  end;
  TAtlasGuard.Run(TAtlasFeature.Breadcrumbs,
    procedure
    begin
      Update;
      Probe;
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

/// <summary>Steuerelement mit seinen Eltern bis zum Formular, für das Protokoll.</summary>
function ControlChain(AControl: TControl): string;
var
  mDepth: Integer;
begin
  Result := '';
  mDepth := 0;
  while (AControl <> nil) and (mDepth < 8) do
  begin
    if Result <> '' then
    begin
      Result := Result + ' < ';
    end;
    Result := Result + AControl.ClassName + ' ' + AControl.Name;
    AControl := AControl.Parent;
    Inc(mDepth);
  end;
end;

/// <summary>Netz (siehe Probe) für eine Ursache am Fenster der Leiste: freigeben, freischalten, zeigen. Ein
/// Fenster eines fremden Threads lässt sich von hier nicht zerstören (DestroyWindow schlägt fehl); dann nur
/// protokollieren, damit die Ursache feststeht.</summary>
procedure RepairBar(ABar: TAtlasBreadcrumbBar);
begin
  if GetWindowThreadProcessId(ABar.Handle, nil) <> MainThreadID then
  begin
    Exit;
  end;
  if (ABar.Parent = nil) or not ABar.Parent.HandleAllocated or (GetParent(ABar.Handle) <> ABar.Parent.Handle) then
  begin
    ABar.Free;
    Exit;
  end;
  if not IsWindowEnabled(ABar.Handle) then
  begin
    ABar.Enabled := True;
    EnableWindow(ABar.Handle, True);
  end;
  if GetWindowLongPtr(ABar.Handle, GWL_STYLE) and WS_VISIBLE = 0 then
  begin
    ShowWindow(ABar.Handle, SW_SHOWNA);
  end;
end;

/// <summary>Fenster AWindow liegt unter der Maus ACursor über der Leiste: Ursache protokollieren, dann Netz (siehe
/// Probe): Vorfahren legen die Leiste neu an, sonst kommt sie nach vorn.</summary>
procedure ReportCover(ABar: TAtlasBreadcrumbBar; AWindow: HWND; const ACursor: TPoint);
var
  mWindowClass: array[0..255] of Char;
  mControl: TWinControl;
  mName, mRelation, mCause: string;
  mAncestor: Boolean;
begin
  mWindowClass[0] := #0;
  GetClassName(AWindow, mWindowClass, Length(mWindowClass));
  mControl := FindControl(AWindow);
  mName := '';
  if mControl <> nil then
  begin
    mName := ControlChain(mControl);
  end;
  mAncestor := IsChild(AWindow, ABar.Handle);
  mRelation := 'kein Vorfahr; hole die Leiste nach vorn';
  if mAncestor then
  begin
    mRelation := 'Vorfahr der Leiste; lege die Leiste neu an';
  end;
  mCause := ABar.HitProblem(ACursor);
  if mCause = '' then
  begin
    mCause := 'am Fenster der Leiste keine erkennbar';
  end;
  TAtlasGuard.Log(Format('Brotkrumen: Maus landet bei %s (%s, %s) statt bei der Leiste (in %s); Ursache: %s',
    [string(mWindowClass), mName, mRelation, ControlChain(ABar.Parent), mCause]));
  if mAncestor then
  begin
    ABar.Free;
    Exit;
  end;
  ABar.BringToFront;
end;

/// <summary>Fenster unter der Maus über ABar prüfen, einmal je Wechsel (AProbed); Maus weg setzt AProbed zurück,
/// damit dasselbe Fenster beim nächsten Mal wieder protokolliert und behoben wird.</summary>
procedure ProbeMouse(ABar: TAtlasBreadcrumbBar; var AProbed: HWND);
var
  mCursor: TPoint;
  mWindow: HWND;
begin
  if not GetCursorPos(mCursor) or not PtInRect(ABar.ClientRect, ABar.ScreenToClient(mCursor)) then
  begin
    AProbed := 0;
    Exit;
  end;
  mWindow := WindowFromPoint(mCursor);
  if mWindow = AProbed then
  begin
    Exit;
  end;
  AProbed := mWindow;
  if mWindow = ABar.Handle then
  begin
    TAtlasGuard.Log('Brotkrumen: Maus kommt an der Leiste an');
  end
  // Ein Fenster eines anderen Formulars (Dialog, Popup) liegt zu Recht darüber.
  else if GetAncestor(mWindow, GA_ROOT) = GetAncestor(ABar.Handle, GA_ROOT) then
  begin
    ReportCover(ABar, mWindow, mCursor);
  end;
end;

/// <summary>Diagnose, warum die Leiste keine Maus bekommt. Die Ursache am Fenster der Leiste
/// (WindowProblem: anderer Thread, falsches Elternfenster, gesperrt, ausgeblendet) prüft jeder Takt, nicht erst
/// das Überfahren; landet die Maus über der Leiste bei einem anderen Fenster desselben Formulars, nennt HitProblem
/// die Ursache am Mauspunkt (Region, HTTRANSPARENT, Geschwister darüber). Beides einmal je Wechsel mit Eltern-
/// kette protokollieren.
/// Netz, nicht Ursache: Danach wird die Leiste wieder bedienbar gemacht (freigeben, zeigen, neu anlegen, nach vorn
/// holen), bis das Protokoll den Verursacher nennt und er an der Wurzel behoben ist. Die Einfügereihenfolge ist es
/// nicht: Im Protokoll vom 21.10. lag die Leiste mit alTop bei 0,0 und kein Geschwister darüber, die Maus landete
/// beim Elternfenster „EditorPanel“ selbst.</summary>
procedure TBreadcrumbsState.Probe;
var
  mBar: TAtlasBreadcrumbBar;
  mProblem: string;
begin
  mBar := FActiveBar;
  if (mBar = nil) or not mBar.HandleAllocated or not mBar.Showing then
  begin
    Exit;
  end;
  mProblem := mBar.WindowProblem;
  if (mProblem <> FProblem) and (mProblem <> '') then
  begin
    TAtlasGuard.Log(Format('Brotkrumen: %s (in %s)', [mProblem, ControlChain(mBar.Parent)]));
  end;
  FProblem := mProblem;
  if mProblem <> '' then
  begin
    RepairBar(mBar);
  end
  else
  begin
    ProbeMouse(mBar, FProbed);
  end;
end;

{ TAtlasIdeBreadcrumbs }

class function TAtlasIdeBreadcrumbs.Enabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Breadcrumbs;
end;

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

end.
