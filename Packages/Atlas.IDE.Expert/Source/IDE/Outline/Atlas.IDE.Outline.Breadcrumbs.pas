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
// - editor.breadcrumbsIdeColors: Fläche und Schrift wie die Werkzeugleisten
//   des IDE-Themas (TAtlasIdeStyle.ChromeColors), sonst Atlas-Palette.
// - editor.breadcrumbsHideIdeToolbar: Die Navigationsleiste der IDE („Typ
//   suchen“/„Methode suchen“) ist ausgeblendet, solange die Leiste an ist
//   (TAtlasNavigationToolbar); aus oder beim Entladen kommt sie zurück.
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
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Outline.Cache;

const
  TickMs = 150;
  MenuWidth = 380;

type
  TBreadcrumbsState = class;

  /// <summary>Erfährt, wenn die IDE eine Leiste mit ihrem Fenster freigibt.</summary>
  TBarWatcher = class(TComponent)
  private
    FState: TBreadcrumbsState;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  end;

  TBreadcrumbsState = class
  private
    FTimer: TTimer;
    FWatcher: TBarWatcher;
    FBars: TList<TAtlasBreadcrumbBar>;
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
    /// <summary>Fenster, das zuletzt unter der Maus über der Leiste lag (Diagnose).</summary>
    FProbed: HWND;
    procedure Tick(Sender: TObject);
    procedure Probe;
    function BarOf(AParent: TWinControl): TAtlasBreadcrumbBar;
    function EditorOf(const AWindow: INTAEditWindow): TWinControl;
    procedure EnsureBars;
    procedure CreateBar(AParent: TWinControl);
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
    procedure Removed(ABar: TAtlasBreadcrumbBar);
    procedure Reset;
    procedure Update;
    procedure ApplyTheme;
    function ActiveBar: TAtlasBreadcrumbBar;
  end;

function Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Breadcrumbs and not TAtlasGuard.Disabled(TAtlasFeature.EditorCommands);
end;

{ TBarWatcher }

procedure TBarWatcher.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent is TAtlasBreadcrumbBar) and (FState <> nil) then
    FState.Removed(TAtlasBreadcrumbBar(AComponent));
end;

{ TBreadcrumbsState }

constructor TBreadcrumbsState.Create;
begin
  inherited Create;
  FBars := TList<TAtlasBreadcrumbBar>.Create;
  FWatcher := TBarWatcher.Create(nil);
  FWatcher.FState := Self;
  FToolbars := TAtlasNavigationToolbar.Create(nil);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := TickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
  Reset;
end;

destructor TBreadcrumbsState.Destroy;
var
  Bar: TAtlasBreadcrumbBar;
begin
  FTimer.Free;
  // Navigationsleisten der IDE zurückhängen.
  FToolbars.Free;
  // Leisten selbst freigeben; der Wächter darf dabei nicht mehr zurückschreiben.
  FWatcher.FState := nil;
  for Bar in FBars.ToArray do
  begin
    Bar.RemoveFreeNotification(FWatcher);
    Bar.Free;
  end;
  FBars.Free;
  FWatcher.Free;
  inherited Destroy;
end;

procedure TBreadcrumbsState.Removed(ABar: TAtlasBreadcrumbBar);
begin
  FBars.Remove(ABar);
  if FActiveBar = ABar then
  begin
    FActiveBar := nil;
    FShown := False;
  end;
end;

procedure TBreadcrumbsState.Reset;
begin
  FFileName := '';
  FStamp := 0;
  FShown := False;
  FLine := -1;
  FCharacter := -1;
  // Farben und Navigationsleiste der IDE nach geänderten Einstellungen.
  ApplyTheme;
  if not TAtlasIdeSettings.Current.BreadcrumbsHideIdeToolbar then
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
  Bar: TAtlasBreadcrumbBar;
  Colors: TAtlasColors;
begin
  Colors := BarColors;
  for Bar in FBars do
    Bar.SetColors(Colors);
end;

procedure TBreadcrumbsState.ApplyToolbar(AParent: TWinControl);
begin
  if TAtlasIdeSettings.Current.BreadcrumbsHideIdeToolbar then
    FToolbars.Apply(AParent, True);
end;

function TBreadcrumbsState.BarOf(AParent: TWinControl): TAtlasBreadcrumbBar;
var
  Bar: TAtlasBreadcrumbBar;
begin
  for Bar in FBars do
    if Bar.Parent = AParent then
      Exit(Bar);
  Result := nil;
end;

function TBreadcrumbsState.EditorOf(const AWindow: INTAEditWindow): TWinControl;
var
  Editor: TComponent;
begin
  Result := nil;
  if (AWindow = nil) or (AWindow.Form = nil) then
    Exit;
  Editor := AWindow.Form.FindComponent('Editor');
  if (Editor is TWinControl) and (TWinControl(Editor).Parent <> nil) then
    Result := TWinControl(Editor);
end;

procedure TBreadcrumbsState.EnsureBars;
var
  Services: INTAEditorServices;
  Index: Integer;
  Editor: TWinControl;
begin
  if not Supports(BorlandIDEServices, INTAEditorServices, Services) then
    Exit;
  for Index := 0 to Services.EditWindowCount - 1 do
  begin
    Editor := EditorOf(Services.EditWindow[Index]);
    if (Editor <> nil) and (BarOf(Editor.Parent) = nil) then
      CreateBar(Editor.Parent);
    // Die IDE legt die Navigationsleiste je Fenster an; neue Fenster beim nächsten Takt.
    if Editor <> nil then
      ApplyToolbar(Services.EditWindow[Index].Form);
  end;
end;

/// <summary>Eigene Methode: Jede Leiste braucht ihre eigene gefangene Variable.</summary>
procedure TBreadcrumbsState.CreateBar(AParent: TWinControl);
var
  Bar: TAtlasBreadcrumbBar;
begin
  Bar := TAtlasBreadcrumbBar.Create(nil);
  Bar.FreeNotification(FWatcher);
  FBars.Add(Bar);
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
      TAtlasGuard.Run(TAtlasFeature.EditorCommands,
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
  // Über dem Editor: zuerst ganz oben einhängen, dann oben ausrichten.
  Bar.Top := 0;
  Bar.Align := alTop;
  Bar.Parent := AParent;
end;

function TBreadcrumbsState.ActiveBar: TAtlasBreadcrumbBar;
var
  Services: INTAEditorServices;
  Editor: TWinControl;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, INTAEditorServices, Services) then
    Exit;
  Editor := EditorOf(Services.TopEditWindow);
  if Editor <> nil then
    Result := BarOf(Editor.Parent);
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
  TAtlasMainThread.ForceQueue(TAtlasFeature.EditorCommands,
    procedure
    begin
      if (TAtlasIdeBreadcrumbs.FState <> State) or not State.FBars.Contains(Bar) then
        Exit;
      Action();
    end);
end;

procedure TBreadcrumbsState.Leave(ABar: TAtlasBreadcrumbBar);
var
  Form: TCustomForm;
  Editor: TComponent;
begin
  Form := GetParentForm(ABar);
  if Form = nil then
    Exit;
  Editor := Form.FindComponent('Editor');
  if (Editor is TWinControl) and TWinControl(Editor).CanFocus then
    TWinControl(Editor).SetFocus;
end;

procedure TBreadcrumbsState.Tick(Sender: TObject);
begin
  if not Active then
    Exit;
  TAtlasGuard.Run(TAtlasFeature.EditorCommands,
    procedure
    begin
      Update;
      Probe;
    end);
end;

/// <summary>Steht die Maus über der Leiste, aber ein anderes Fenster liegt darüber, bekommt die Leiste keine
/// Mausereignisse. Das Fenster einmal je Wechsel protokollieren und die Leiste nach vorn holen.</summary>
procedure TBreadcrumbsState.Probe;
var
  Bar: TAtlasBreadcrumbBar;
  Cursor: TPoint;
  Window: HWND;
  WindowClass: array[0..255] of Char;
  Control: TWinControl;
  Name: string;
begin
  Bar := FActiveBar;
  if (Bar = nil) or not Bar.HandleAllocated or not Bar.Showing or not GetCursorPos(Cursor) then
    Exit;
  if not PtInRect(Bar.ClientRect, Bar.ScreenToClient(Cursor)) then
    Exit;
  Window := WindowFromPoint(Cursor);
  if Window = FProbed then
    Exit;
  FProbed := Window;
  if Window = Bar.Handle then
  begin
    TAtlasGuard.Log('Brotkrumen: Maus kommt an der Leiste an');
    Exit;
  end;
  WindowClass[0] := #0;
  GetClassName(Window, WindowClass, Length(WindowClass));
  Control := FindControl(Window);
  Name := '';
  if Control <> nil then
    Name := Control.ClassName + ' ' + Control.Name;
  TAtlasGuard.Log(Format('Brotkrumen: Über der Leiste liegt ein anderes Fenster (%s, %s); hole die Leiste nach vorn',
    [string(WindowClass), Name]));
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
  if Active then
    FState := TBreadcrumbsState.Create;
end;

class procedure TAtlasIdeBreadcrumbs.Uninstall;
begin
  FreeAndNil(FState);
end;

class procedure TAtlasIdeBreadcrumbs.ApplySettings;
begin
  // Aus: alle Leisten weg, der Editor bekommt seine Höhe zurück.
  if not Active then
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
