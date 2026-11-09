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
// - Eigene Sicherung TAtlasFeature.Breadcrumbs: Fehler anderer Editorfunktionen
//   (früher gemeinsam Editorbefehle) schalten die Leiste nicht mehr still ab.
//   Löst die eigene Sicherung aus, sagt die Leiste das, statt stehen zu
//   bleiben; nach „Abgeschaltete Funktionen einschalten“ läuft sie weiter.
// - editor.breadcrumbsIdeColors: Fläche und Schrift wie die Werkzeugleisten
//   des IDE-Themas (TAtlasIdeStyle.ChromeColors), sonst Atlas-Palette.
// - editor.breadcrumbsHideIdeToolbar: Die Navigationsleiste der IDE („Typ
//   suchen“/„Methode suchen“) ist ausgeblendet, solange die Leiste an ist;
//   aus oder beim Entladen kommt sie zurück. Ausgeblendet wird über die
//   IDE-Option „Navigationssymbolleiste anzeigen“ (TAtlasIdeNavigationOption,
//   Bericht M3). Nur wenn die IDE keine solche Option hat, hängt
//   TAtlasNavigationToolbar die Leiste um (Netz).
// - Anlegen je Editorfenster, Wächter, Freigabe nach der Sperre durch die
//   IDE, Protokoll des Sperrenden und Abbau übernimmt TAtlasEditorBarHost
//   (#1248). Bei ausgelöster Sicherung bleiben die Leisten stehen und sagen
//   „abgeschaltet“ (ShowDisabled), statt zu verschwinden.
// Abgrenzung zum mitlaufenden Kopf (#506) und zum Gliederungsfenster (#537):
// docs/Architektur.md. Nur im Hauptthread.

interface

type
  TAtlasIdeBreadcrumbs = class
  private class var
    FState: TObject;
  public
    /// <summary>Den Server fragt TAtlasIdeOutlineCache (vorher installieren).</summary>
    class procedure Install; static;
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
  System.SysUtils,
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
  Atlas.UI.Strings,
  Atlas.UI.Commands.Palette,
  Atlas.UI.Outline.Breadcrumbs,
  Atlas.UI.Outline.NavigationToolbar,
  Atlas.IDE.Outline.NavigationOption,
  Atlas.IDE.Foundation.EditorBarHost,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Outline.Cache;

const
  cTickMs = 150;
  cMenuWidth = 380;

type
  TBreadcrumbsState = class
  private
    FTimer: TTimer;
    FHost: TAtlasEditorBarHost;
    FFileName: string;
    FStamp: Cardinal;
    FStatus: TAtlasOutlineStatus;
    FNodes: TAtlasOutlineNodes;
    FLines: TArray<string>;
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
    procedure Tick(Sender: TObject);
    procedure Probe;
    procedure ShowDisabled;
    procedure EnsureBars;
    function CreateBar: TAtlasBreadcrumbBar;
    procedure Place(ABar: TAtlasBreadcrumbBar; AParent: TWinControl);
    procedure OpenMenu(ABar: TAtlasBreadcrumbBar; AIndex: Integer; const APoint: TPoint);
    procedure OpenChildren(ABar: TAtlasBreadcrumbBar; AIndex: Integer; const APoint: TPoint);
    procedure OpenList(ABar: TAtlasBreadcrumbBar; const APrompt: string; const AItems: TArray<Integer>;
      ACurrent: Integer; const APoint: TPoint);
    procedure OpenPlaces(ABar: TAtlasBreadcrumbBar; const ACrumb: TAtlasCrumb; const APoint: TPoint);
    procedure Jump(ABar: TAtlasBreadcrumbBar; AIndex: Integer; ADeclaration: Boolean);
    procedure Later(ABar: TAtlasBreadcrumbBar; const AAction: TProc);
    procedure ApplyToolbar(AParent: TWinControl);
    procedure Leave(ABar: TAtlasBreadcrumbBar);
    function CommandsOf(const ANodes: TAtlasOutlineNodes; const AIndices: TArray<Integer>;
      ACurrent: Integer): TArray<TAtlasCommand>;
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
  // Navigationsleisten der IDE wieder zeigen: Option zurück, wenn Atlas sie ausgeschaltet hatte, bzw. zurückhängen.
  TAtlasIdeNavigationOption.Apply(False);
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
  FLine := -1;
  FCharacter := -1;
  // Farben und Navigationsleiste der IDE nach geänderten Einstellungen. Die Leiste blendet die IDE über ihre
  // Option aus (Bericht M3); umgehängt wird nur ohne diese Option (Netz).
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
  mBar.EmptyText := TAtlasStrings.Text(TAtlasTextId.BreadcrumbsEmpty);
  mBar.CrumbHint := TAtlasStrings.Text(TAtlasTextId.BreadcrumbsCrumbHint);
  mBar.SeparatorHint := TAtlasStrings.Text(TAtlasTextId.BreadcrumbsChildrenHint);
  mBar.MarkHint := TAtlasStrings.Text(TAtlasTextId.BreadcrumbsMarkHint);
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
    Result := Format(TAtlasStrings.Text(TAtlasTextId.BreadcrumbsRegionUnnamed), [APlace.Line + 1]);
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

/// <summary>Zusätzliche Glieder nach den Einstellungen (#1759, #1767, #1765, #1766, #1763, #1764, #1769).</summary>
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
end;

/// <summary>Stand ASnapshot und Leiste ABar übernehmen; True, wenn sich gegenüber dem letzten Stand etwas
/// geändert hat (dann ist der Pfad neu zu bilden).</summary>
function TBreadcrumbsState.Remember(ABar: TAtlasBreadcrumbBar; const ASnapshot: TAtlasOutlineSnapshot): Boolean;
var
  mShowUnit: Boolean;
  mParts: TAtlasCrumbParts;
begin
  mShowUnit := TAtlasIdeSettings.Current.BreadcrumbsShowUnit;
  mParts := CrumbParts;
  Result := not FShown or (ABar <> FActiveBar) or (ASnapshot.Status <> FStatus) or
    not SameText(ASnapshot.FileName, FFileName) or (ASnapshot.Stamp <> FStamp) or (mShowUnit <> FShowUnit) or
    (mParts <> FParts);
  if Result and (ASnapshot.Stamp <> FStamp) then
  begin
    FLines := TTextLines.SplitLines(ASnapshot.Text);
  end;
  FShown := True;
  FActiveBar := ABar;
  FStatus := ASnapshot.Status;
  FFileName := ASnapshot.FileName;
  FStamp := ASnapshot.Stamp;
  FShowUnit := mShowUnit;
  FParts := mParts;
  FNodes := ASnapshot.Nodes;
end;

/// <summary>Ob ABar beim Stand AStatus einen Pfad zeigt; sonst steht der passende Hinweis darin (beim Warten
/// bleibt der alte Pfad).</summary>
function ShowsPath(ABar: TAtlasBreadcrumbBar; AStatus: TAtlasOutlineStatus): Boolean;
begin
  Result := False;
  case AStatus of
    TAtlasOutlineStatus.NoFile:
      begin
        ABar.EmptyText := TAtlasStrings.Text(TAtlasTextId.BreadcrumbsEmpty);
        ABar.SetCrumbs(nil);
      end;
    TAtlasOutlineStatus.NoServer:
      begin
        ABar.EmptyText := TAtlasStrings.Text(TAtlasTextId.OutlineNoServer);
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
  mBar.EmptyText := TAtlasStrings.Text(TAtlasTextId.BreadcrumbsEmpty);
  mBar.SetCrumbs(NamedRegions(TAtlasBreadcrumbs.Path(FNodes, FLines, FLine, FCharacter,
    ChangeFileExt(ExtractFileName(FFileName), ''), FShowUnit, FParts)));
end;

function TBreadcrumbsState.CommandsOf(const ANodes: TAtlasOutlineNodes; const AIndices: TArray<Integer>;
  ACurrent: Integer): TArray<TAtlasCommand>;
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
    if mNode = ACurrent then
    begin
      mCommand.ShortCut := TAtlasStrings.Text(TAtlasTextId.BreadcrumbsCurrent);
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
  const AItems: TArray<Integer>; ACurrent: Integer; const APoint: TPoint);
var
  mItems: TArray<Integer>;
  mNodes: TAtlasOutlineNodes;
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
  mFileName := FFileName;
  mWindow := TAtlasPaletteWindow.CreatePalette(Application, CommandsOf(mNodes, mItems, ACurrent), nil,
    TAtlasIdeStyle.Colors);
  mWindow.Prompt := APrompt;
  mWindow.Presorted := True;
  mWindow.QueryDelay := 0;
  if ACurrent >= 0 then
  begin
    mWindow.InitialId := IntToStr(ACurrent);
  end;
  mWindow.OnQuery :=
    function(APattern: string): TArray<TAtlasCommand>
    begin
      Result := CommandsOf(mNodes, TAtlasBreadcrumbs.Filter(mNodes, mItems, APattern), ACurrent);
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

function PlaceCommands(const APlaces: TArray<TAtlasCrumbPlace>; const APattern: string;
  ACurrent: Integer): TArray<TAtlasCommand>;
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
    // Zeile gedimmt, bei Deklarationsblöcken (#1766) mit dem Teil der Unit.
    if APlaces[mIndex].Group <> '' then
    begin
      mCommand.Path := Format(TAtlasStrings.Text(TAtlasTextId.BreadcrumbsPlaceLine),
        [APlaces[mIndex].Group, APlaces[mIndex].Line + 1]);
    end
    else
    begin
      mCommand.Path := Format(TAtlasStrings.Text(TAtlasTextId.BreadcrumbsPlaceLineOnly), [APlaces[mIndex].Line + 1]);
    end;
    if mIndex = ACurrent then
    begin
      mCommand.ShortCut := TAtlasStrings.Text(TAtlasTextId.BreadcrumbsCurrent);
    end;
    Result := Result + [mCommand];
  end;
end;

/// <summary>Menü der Sprungziele eines Glieds ohne Knoten (Sichtbarkeitsabschnitte des Typs, #1759).</summary>
procedure TBreadcrumbsState.OpenPlaces(ABar: TAtlasBreadcrumbBar; const ACrumb: TAtlasCrumb; const APoint: TPoint);
var
  mPlaces: TArray<TAtlasCrumbPlace>;
  mCurrent: Integer;
  mFileName: string;
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
  mWindow := TAtlasPaletteWindow.CreatePalette(Application, PlaceCommands(mPlaces, '', mCurrent), nil,
    TAtlasIdeStyle.Colors);
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
      Result := PlaceCommands(mPlaces, APattern, mCurrent);
    end;
  mWindow.OnExecuteShift :=
    procedure(ACommand: TAtlasCommand; AShifted: Boolean)
    var
      mChosen: Integer;
    begin
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
      TAtlasBreadcrumbBar(ABar).EmptyText := TAtlasStrings.Text(TAtlasTextId.BreadcrumbsDisabled);
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

/// <summary>Diagnose, warum die Leiste keine Maus bekommt (Bericht M2). Die Ursache am Fenster der Leiste
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

class procedure TAtlasIdeBreadcrumbs.Install;
begin
  FreeAndNil(FState);
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
end;

class procedure TAtlasIdeBreadcrumbs.Uninstall;
begin
  FreeAndNil(FState);
end;

class procedure TAtlasIdeBreadcrumbs.ApplySettings;
begin
  // Aus: alle Leisten weg, der Editor bekommt seine Höhe zurück.
  if not Enabled then
  begin
    FreeAndNil(FState);
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
