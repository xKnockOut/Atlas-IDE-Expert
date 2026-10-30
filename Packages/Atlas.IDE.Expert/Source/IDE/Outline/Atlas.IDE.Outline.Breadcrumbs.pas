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
//   setzt den Unit-Namen als erstes Glied.
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
  TickMs = 150;
  MenuWidth = 380;

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
    function CreateBar(AParent: TWinControl): TAtlasBreadcrumbBar;
    procedure Place(ABar: TAtlasBreadcrumbBar; AParent: TWinControl);
    procedure OpenMenu(ABar: TAtlasBreadcrumbBar; AIndex: Integer; const APoint: TPoint);
    procedure OpenChildren(ABar: TAtlasBreadcrumbBar; AIndex: Integer; const APoint: TPoint);
    procedure OpenList(ABar: TAtlasBreadcrumbBar; const APrompt: string; const AItems: TArray<Integer>;
      ACurrent: Integer; const APoint: TPoint);
    procedure Jump(ABar: TAtlasBreadcrumbBar; AIndex: Integer; ADeclaration: Boolean);
    procedure Later(ABar: TAtlasBreadcrumbBar; const AAction: TProc);
    procedure ApplyToolbar(AParent: TWinControl);
    procedure Leave(ABar: TAtlasBreadcrumbBar);
    function CommandsOf(const ANodes: TAtlasOutlineNodes; const AIndices: TArray<Integer>;
      ACurrent: Integer): TArray<TAtlasCommand>;
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
      Result := CreateBar(AEditorParent);
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
  FTimer.Interval := TickMs;
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
  Hide: Boolean;
begin
  FFileName := '';
  FStamp := 0;
  FShown := False;
  FLine := -1;
  FCharacter := -1;
  // Farben und Navigationsleiste der IDE nach geänderten Einstellungen. Die Leiste blendet die IDE über ihre
  // Option aus (Bericht M3); umgehängt wird nur ohne diese Option (Netz).
  ApplyTheme;
  Hide := TAtlasIdeSettings.Current.BreadcrumbsHideIdeToolbar;
  FToolbarByIde := TAtlasIdeNavigationOption.Apply(Hide);
  if FToolbarByIde or not Hide then
    FToolbars.RestoreAll;
end;

function BarColors: TAtlasColors;
begin
  if TAtlasIdeSettings.Current.BreadcrumbsIdeColors then
    Result := TAtlasIdeStyle.ChromeColors
  else
    Result := TAtlasIdeStyle.Colors;
end;

procedure TBreadcrumbsState.ApplyTheme;
var
  Colors: TAtlasColors;
begin
  Colors := BarColors;
  FHost.ForEach(
    procedure(ABar: TControl)
    begin
      TAtlasBreadcrumbBar(ABar).SetColors(Colors);
    end);
end;

/// <summary>Netz, nur ohne Option der IDE (siehe Reset): Navigationsleiste in ein eigenes Panel umhängen.</summary>
procedure TBreadcrumbsState.ApplyToolbar(AParent: TWinControl);
begin
  if FToolbarByIde then
    Exit;
  if TAtlasIdeSettings.Current.BreadcrumbsHideIdeToolbar then
    FToolbars.Apply(AParent, True);
end;

procedure TBreadcrumbsState.EnsureBars;
var
  Services: INTAEditorServices;
  Index: Integer;
begin
  FHost.Ensure;
  if not Supports(BorlandIDEServices, INTAEditorServices, Services) then
    Exit;
  // Die IDE legt die Navigationsleiste je Fenster an; neue Fenster beim nächsten Takt.
  for Index := 0 to Services.EditWindowCount - 1 do
    if TAtlasEditorBarHost.EditorOf(Services.EditWindow[Index]) <> nil then
      ApplyToolbar(Services.EditWindow[Index].Form);
end;

/// <summary>Eigene Methode: Jede Leiste braucht ihre eigene gefangene Variable. Einordnen und Wächter: Host.</summary>
function TBreadcrumbsState.CreateBar(AParent: TWinControl): TAtlasBreadcrumbBar;
var
  Bar: TAtlasBreadcrumbBar;
  Host: TAtlasEditorBarHost;
begin
  Bar := TAtlasBreadcrumbBar.Create(nil);
  Host := FHost;
  Bar.SetColors(BarColors);
  Bar.EmptyText := TAtlasStrings.Text(TAtlasTextId.BreadcrumbsEmpty);
  Bar.CrumbHint := TAtlasStrings.Text(TAtlasTextId.BreadcrumbsCrumbHint);
  Bar.SeparatorHint := TAtlasStrings.Text(TAtlasTextId.BreadcrumbsChildrenHint);
  Bar.OnOpenMenu :=
    procedure(AIndex: Integer; const APoint: TPoint)
    var
      At: TPoint;
    begin
      At := APoint;
      Later(Bar,
        procedure
        begin
          OpenMenu(Bar, AIndex, At);
        end);
    end;
  Bar.OnOpenChildren :=
    procedure(AIndex: Integer; const APoint: TPoint)
    var
      At: TPoint;
    begin
      At := APoint;
      Later(Bar,
        procedure
        begin
          OpenChildren(Bar, AIndex, At);
        end);
    end;
  Bar.OnJump :=
    procedure(AIndex: Integer; ADeclaration: Boolean)
    begin
      TAtlasGuard.Run(TAtlasFeature.Breadcrumbs,
        procedure
        begin
          Jump(Bar, AIndex, ADeclaration);
        end);
    end;
  Bar.OnLeave :=
    procedure
    begin
      Leave(Bar);
    end;
  Bar.OnDisabled :=
    procedure(ASender: TObject)
    begin
      Host.Disabled(ASender);
    end;
  Result := Bar;
end;

procedure TBreadcrumbsState.Place(ABar: TAtlasBreadcrumbBar; AParent: TWinControl);
begin
  if ABar.Parent = AParent then
    Exit;
  // Über dem Editor: zuerst ganz oben einhängen, dann oben ausrichten.
  ABar.Top := 0;
  ABar.Align := alTop;
  ABar.Parent := AParent;
end;

function TBreadcrumbsState.ActiveBar: TAtlasBreadcrumbBar;
begin
  Result := TAtlasBreadcrumbBar(FHost.ActiveBar);
end;

procedure TBreadcrumbsState.Update;
var
  Bar: TAtlasBreadcrumbBar;
  View: IOTAEditView;
  Snapshot: TAtlasOutlineSnapshot;
  Cursor: TOTAEditPos;
  Character: Integer;
  ShowUnit, Changed: Boolean;
begin
  EnsureBars;
  Bar := ActiveBar;
  if Bar = nil then
    Exit;
  View := TAtlasEditorBuffer.ActiveView;
  Snapshot := TAtlasIdeOutlineCache.Refresh(View);
  ShowUnit := TAtlasIdeSettings.Current.BreadcrumbsShowUnit;
  Changed := not FShown or (Bar <> FActiveBar) or (Snapshot.Status <> FStatus) or
    not SameText(Snapshot.FileName, FFileName) or (Snapshot.Stamp <> FStamp) or (ShowUnit <> FShowUnit);
  if Changed and (Snapshot.Stamp <> FStamp) then
    FLines := TTextLines.SplitLines(Snapshot.Text);
  FShown := True;
  FActiveBar := Bar;
  FStatus := Snapshot.Status;
  FFileName := Snapshot.FileName;
  FStamp := Snapshot.Stamp;
  FShowUnit := ShowUnit;
  FNodes := Snapshot.Nodes;
  case Snapshot.Status of
    TAtlasOutlineStatus.NoFile:
      begin
        Bar.EmptyText := TAtlasStrings.Text(TAtlasTextId.BreadcrumbsEmpty);
        Bar.SetCrumbs(nil);
        Exit;
      end;
    TAtlasOutlineStatus.NoServer:
      begin
        Bar.EmptyText := TAtlasStrings.Text(TAtlasTextId.OutlineNoServer);
        Bar.SetCrumbs(nil);
        Exit;
      end;
    TAtlasOutlineStatus.Waiting:
      Exit;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
  Cursor := View.CursorPos;
  if Cursor.Line < 1 then
    Exit;
  Character := TLspSession.ColumnToIndex(TAtlasEditorBuffer.LineText(View, Cursor.Line), Cursor.Col,
    TAtlasEditorBuffer.TabWidth(View.Buffer));
  if not Changed and (Cursor.Line - 1 = FLine) and (Character = FCharacter) then
    Exit;
  FLine := Cursor.Line - 1;
  FCharacter := Character;
  Bar.EmptyText := TAtlasStrings.Text(TAtlasTextId.BreadcrumbsEmpty);
  Bar.SetCrumbs(TAtlasBreadcrumbs.Path(FNodes, FLines, FLine, FCharacter,
    ChangeFileExt(ExtractFileName(FFileName), ''), FShowUnit));
end;

function TBreadcrumbsState.CommandsOf(const ANodes: TAtlasOutlineNodes; const AIndices: TArray<Integer>;
  ACurrent: Integer): TArray<TAtlasCommand>;
var
  Node: Integer;
  Command: TAtlasCommand;
begin
  Result := nil;
  for Node in AIndices do
  begin
    Command := Default(TAtlasCommand);
    Command.Id := IntToStr(Node);
    Command.Caption := TAtlasBreadcrumbs.ShortName(ANodes[Node].Name);
    Command.Path := ANodes[Node].Detail;
    if Node = ACurrent then
      Command.ShortCut := TAtlasStrings.Text(TAtlasTextId.BreadcrumbsCurrent);
    Result := Result + [Command];
  end;
end;

procedure TBreadcrumbsState.OpenMenu(ABar: TAtlasBreadcrumbBar; AIndex: Integer; const APoint: TPoint);
var
  Crumb: TAtlasCrumb;
begin
  if (ABar <> FActiveBar) or (AIndex < 0) or (AIndex > High(ABar.Crumbs)) then
    Exit;
  Crumb := ABar.Crumbs[AIndex];
  OpenList(ABar, Crumb.Text, Crumb.Siblings, Crumb.Node, APoint);
end;

procedure TBreadcrumbsState.OpenChildren(ABar: TAtlasBreadcrumbBar; AIndex: Integer; const APoint: TPoint);
var
  Crumb: TAtlasCrumb;
  Current: Integer;
begin
  if (ABar <> FActiveBar) or (AIndex < 0) or (AIndex > High(ABar.Crumbs)) then
    Exit;
  Crumb := ABar.Crumbs[AIndex];
  // Vorgewählt ist das Kind, in dem der Caret steht (das nächste Glied).
  Current := -1;
  if AIndex < High(ABar.Crumbs) then
    Current := ABar.Crumbs[AIndex + 1].Node;
  OpenList(ABar, Crumb.Text + ' ›', Crumb.Children, Current, APoint);
end;

procedure TBreadcrumbsState.OpenList(ABar: TAtlasBreadcrumbBar; const APrompt: string;
  const AItems: TArray<Integer>; ACurrent: Integer; const APoint: TPoint);
var
  Items: TArray<Integer>;
  Nodes: TAtlasOutlineNodes;
  FileName: string;
  Window: TAtlasPaletteWindow;
begin
  if (Length(AItems) = 0) or (FFileName = '') then
  begin
    TAtlasGuard.Log(Format('Brotkrumen: kein Menü (Einträge %d, Datei %s)', [Length(AItems),
      BoolToStr(FFileName <> '', True)]));
    Exit;
  end;
  // Kopien: Das Menü lebt länger als der aktuelle Stand.
  Items := AItems;
  Nodes := FNodes;
  FileName := FFileName;
  Window := TAtlasPaletteWindow.CreatePalette(Application, CommandsOf(Nodes, Items, ACurrent), nil,
    TAtlasIdeStyle.Colors);
  Window.Prompt := APrompt;
  Window.Presorted := True;
  Window.QueryDelay := 0;
  if ACurrent >= 0 then
    Window.InitialId := IntToStr(ACurrent);
  Window.OnQuery :=
    function(APattern: string): TArray<TAtlasCommand>
    begin
      Result := CommandsOf(Nodes, TAtlasBreadcrumbs.Filter(Nodes, Items, APattern), ACurrent);
    end;
  Window.OnExecuteShift :=
    procedure(ACommand: TAtlasCommand; AShifted: Boolean)
    var
      Node, Target: Integer;
    begin
      Node := StrToIntDef(ACommand.Id, -1);
      if (Node < 0) or (Node > High(Nodes)) then
        Exit;
      // Enter zur Implementierung, Umschalt+Enter zur Deklaration.
      Target := TAtlasBreadcrumbs.Target(Nodes, Node, not AShifted);
      if Target < 0 then
        Exit;
      TAtlasIdeNavigation.GoToLocation(FileName, Nodes[Target].NameLine, Nodes[Target].NameCharacter);
    end;
  Window.ShowAt(APoint, MulDiv(MenuWidth, ABar.CurrentPPI, 96));
end;

procedure TBreadcrumbsState.Jump(ABar: TAtlasBreadcrumbBar; AIndex: Integer; ADeclaration: Boolean);
var
  Crumb: TAtlasCrumb;
  Target: Integer;
begin
  if (ABar <> FActiveBar) or (AIndex < 0) or (AIndex > High(ABar.Crumbs)) or (FFileName = '') then
    Exit;
  Crumb := ABar.Crumbs[AIndex];
  TAtlasGuard.Log(Format('Brotkrumen: Sprung zu Glied %d', [AIndex]));
  if Crumb.Node < 0 then
  begin
    // Unit-Glied: an den Anfang der Datei.
    if Crumb.Badge.Kind = TAtlasBadgeKind.Unit_ then
      TAtlasIdeNavigation.GoToLocation(FFileName, 0, 0);
    Exit;
  end;
  Target := TAtlasBreadcrumbs.Target(FNodes, Crumb.Node, not ADeclaration);
  if Target < 0 then
    Exit;
  TAtlasIdeNavigation.GoToLocation(FFileName, FNodes[Target].NameLine, FNodes[Target].NameCharacter);
end;

/// <summary>Menü erst nach dem Klick öffnen: Die IDE holt den Fokus in den Editor zurück; ein sofort geöffnetes
/// Menü verlöre die Aktivierung und ginge gleich wieder zu. Läuft nur, wenn Zustand und Leiste dann noch leben.</summary>
procedure TBreadcrumbsState.Later(ABar: TAtlasBreadcrumbBar; const AAction: TProc);
var
  State: TBreadcrumbsState;
  Bar: TAtlasBreadcrumbBar;
  Action: TProc;
begin
  TAtlasGuard.Log('Brotkrumen: Klick, Menü folgt');
  State := Self;
  Bar := ABar;
  Action := AAction;
  TAtlasMainThread.ForceQueue(TAtlasFeature.Breadcrumbs,
    procedure
    begin
      if (TAtlasIdeBreadcrumbs.FState <> State) or not State.FHost.Contains(Bar) then
        Exit;
      Action();
    end);
end;

procedure TBreadcrumbsState.Leave(ABar: TAtlasBreadcrumbBar);
begin
  TAtlasEditorBarHost.FocusEditor(ABar);
end;

procedure TBreadcrumbsState.Tick(Sender: TObject);
begin
  if not TAtlasIdeSettings.Current.Breadcrumbs then
    Exit;
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
    Exit;
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
  Depth: Integer;
begin
  Result := '';
  Depth := 0;
  while (AControl <> nil) and (Depth < 8) do
  begin
    if Result <> '' then
      Result := Result + ' < ';
    Result := Result + AControl.ClassName + ' ' + AControl.Name;
    AControl := AControl.Parent;
    Inc(Depth);
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
  Bar: TAtlasBreadcrumbBar;
  Cursor: TPoint;
  Window: HWND;
  WindowClass: array[0..255] of Char;
  Control: TWinControl;
  Problem, Name, Relation, Cause: string;
  Ancestor: Boolean;
begin
  Bar := FActiveBar;
  if (Bar = nil) or not Bar.HandleAllocated or not Bar.Showing then
    Exit;
  Problem := Bar.WindowProblem;
  if Problem <> FProblem then
  begin
    FProblem := Problem;
    if Problem <> '' then
      TAtlasGuard.Log(Format('Brotkrumen: %s (in %s)', [Problem, ControlChain(Bar.Parent)]));
  end;
  if Problem <> '' then
  begin
    // Netz (siehe oben). Ein Fenster eines fremden Threads lässt sich von hier nicht zerstören (DestroyWindow
    // schlägt fehl); nur protokollieren, damit die Ursache feststeht.
    if GetWindowThreadProcessId(Bar.Handle, nil) <> MainThreadID then
      Exit;
    if (Bar.Parent = nil) or not Bar.Parent.HandleAllocated or (GetParent(Bar.Handle) <> Bar.Parent.Handle) then
    begin
      Bar.Free;
      Exit;
    end;
    if not IsWindowEnabled(Bar.Handle) then
    begin
      Bar.Enabled := True;
      EnableWindow(Bar.Handle, True);
    end;
    if GetWindowLongPtr(Bar.Handle, GWL_STYLE) and WS_VISIBLE = 0 then
      ShowWindow(Bar.Handle, SW_SHOWNA);
    Exit;
  end;
  if not GetCursorPos(Cursor) or not PtInRect(Bar.ClientRect, Bar.ScreenToClient(Cursor)) then
  begin
    // Maus weg: Liegt beim nächsten Mal dasselbe Fenster darüber, wird es wieder protokolliert und behoben.
    FProbed := 0;
    Exit;
  end;
  Window := WindowFromPoint(Cursor);
  if Window = FProbed then
    Exit;
  FProbed := Window;
  if Window = Bar.Handle then
  begin
    TAtlasGuard.Log('Brotkrumen: Maus kommt an der Leiste an');
    Exit;
  end;
  // Ein Fenster eines anderen Formulars (Dialog, Popup) liegt zu Recht darüber.
  if GetAncestor(Window, GA_ROOT) <> GetAncestor(Bar.Handle, GA_ROOT) then
    Exit;
  WindowClass[0] := #0;
  GetClassName(Window, WindowClass, Length(WindowClass));
  Control := FindControl(Window);
  Name := '';
  if Control <> nil then
    Name := ControlChain(Control);
  Ancestor := IsChild(Window, Bar.Handle);
  if Ancestor then
    Relation := 'Vorfahr der Leiste; lege die Leiste neu an'
  else
    Relation := 'kein Vorfahr; hole die Leiste nach vorn';
  Cause := Bar.HitProblem(Cursor);
  if Cause = '' then
    Cause := 'am Fenster der Leiste keine erkennbar';
  TAtlasGuard.Log(Format('Brotkrumen: Maus landet bei %s (%s, %s) statt bei der Leiste (in %s); Ursache: %s',
    [string(WindowClass), Name, Relation, ControlChain(Bar.Parent), Cause]));
  // Netz (siehe oben).
  if Ancestor then
  begin
    Bar.Free;
    Exit;
  end;
  Bar.BringToFront;
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
    FState := TBreadcrumbsState.Create
  else
    // Hatte Atlas die Navigationsleiste ausgeblendet und die IDE endete ohne Entladen: wieder zeigen.
    TAtlasIdeNavigationOption.Apply(False);
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
    FState := TBreadcrumbsState.Create
  else
    TBreadcrumbsState(FState).Reset;
end;

class procedure TAtlasIdeBreadcrumbs.ThemeChanged;
begin
  if FState <> nil then
    TBreadcrumbsState(FState).ApplyTheme;
end;

class procedure TAtlasIdeBreadcrumbs.Focus;
var
  Bar: TAtlasBreadcrumbBar;
begin
  if (FState = nil) or not Active then
    Exit;
  TBreadcrumbsState(FState).Update;
  Bar := TBreadcrumbsState(FState).ActiveBar;
  if Bar <> nil then
    Bar.FocusLast;
end;

end.
