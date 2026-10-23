unit Atlas.IDE.EditorToolbar.Service;

// Atlas-Editorleiste (#1101) in der IDE:
// - Über dem Editor jedes Editorfensters steht eine Leiste
//   (TAtlasEditorToolbar) mit den Befehlen aus editor.toolbar.items; Fenster,
//   die später aufgehen, bekommen sie beim nächsten Takt. Position nach
//   editor.toolbar.position: unter bzw. über der Brotkrumenleiste (alTop im
//   Eltern-Steuerelement des Editors) oder rechts in der Brotkrumenzeile
//   (alRight in TAtlasBreadcrumbBar); ohne Brotkrumen steht sie oben.
// - Ein Zeitgeber (150 ms) setzt für die aktive Ansicht den hervorgehobenen
//   Abschnitt, gesperrte Abschnittsknöpfe (Datei ohne interface/
//   implementation), den Punkt an „Probleme“ (Befunde der Datei), „Vor“ nur
//   mit Vorwärts-Verlauf und den Rücksprung-Knopf „↩ 214“. Abschnitte liest
//   TAtlasSectionScanner direkt aus dem Editortext (ohne Server).
// - Abschnittssprünge (GotoInterface, GotoImplementation, GotoUses,
//   GotoInitialization) setzen die Zielzeile ins obere Drittel und merken die
//   Ausgangszeile (TAtlasReturnPoints, erster Ausgangspunkt bleibt); Zeilen
//   darüber verschieben sie, Rückkehr auf die Zeile (Knopf, Alt+← oder
//   von Hand) erledigt sie. Die Befehle arbeiten auch ohne Leiste (Palette,
//   Menü, Tasten).
// - FindMethod: Atlas-Popup mit den Routinen der Datei aus der Gliederung
//   (TAtlasIdeOutlineCache), Enter zur Implementierung, Umschalt+Enter zur
//   Deklaration.
// - Customize: Dialog „Leiste anpassen“; übernimmt Belegung, Text neben den
//   Symbolen und Position in die Einstellungen.
// - Alles, was anderen Features gehört (Palette, Befunde, Verlauf,
//   Meldungsansicht), kommt über THooks von der Composition; so entsteht kein
//   Feature-Zyklus (A-09).
// - Eigene Sicherung TAtlasFeature.EditorToolbar: Löst sie aus, verschwinden
//   die Leisten, bis „Abgeschaltete Funktionen einschalten“.
// - editor.toolbar aus: Leisten weg, der Editor bekommt seine Höhe zurück;
//   Position, Text neben den Symbolen und Belegung gelten ohne Neustart.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Commands.Palette,
  Atlas.Core.EditorToolbar.Sections,
  Atlas.UI.EditorToolbar.Customize;

type
  TAtlasIdeEditorToolbar = class
  public type
    THooks = record
      /// <summary>Sichtbare Atlas-Befehle der Palette (mit Taste).</summary>
      Commands: TFunc<TArray<TAtlasCommand>>;
      /// <summary>Atlas-Befehl ausführen wie aus der Palette (Verlauf, Tipps).</summary>
      Execute: TProc<string>;
      /// <summary>Befehlspalette öffnen.</summary>
      ShowPalette: TProc;
      /// <summary>Taste eines Befehls als Text ('' ohne).</summary>
      ShortCutOf: TFunc<string, string>;
      /// <summary>Zahl der Befunde in der Datei.</summary>
      FindingsOf: TFunc<string, Integer>;
      CanGoBack: TFunc<Boolean>;
      CanGoForward: TFunc<Boolean>;
      /// <summary>Zeile in der Meldungsansicht.</summary>
      Message: TProc<string>;
    end;
  private class var
    FState: TObject;
    FHooks: THooks;
    class procedure Say(const AText: string); static;
  public
    class procedure Install(const AHooks: THooks); static;
    class procedure Uninstall; static;
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
    /// <summary>Ist die Leiste eingeschaltet?</summary>
    class function Enabled: Boolean; static;
    class procedure GoToSection(ATarget: TAtlasSectionTarget); static;
    class procedure GotoInterface; static;
    class procedure GotoImplementation; static;
    class procedure GotoUses; static;
    class procedure GotoInitialization; static;
    /// <summary>Zurück zum Ausgangspunkt des letzten Abschnittssprungs in der aktiven Datei.</summary>
    class procedure ReturnFromSection; static;
    class procedure FindMethod; static;
    class procedure Customize; static;
    /// <summary>Befehle, die in die Leiste können: Atlas-Befehle der Palette und die Palette selbst.</summary>
    class function CommandInfos: TArray<TAtlasToolbarCommandInfo>; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.Types,
  System.Math,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Text.Lines,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Palette,
  Atlas.Core.Outline.Model,
  Atlas.Core.Outline.Breadcrumbs,
  Atlas.Core.Settings.ToolbarItems,
  Atlas.Core.EditorToolbar.Icons,
  Atlas.Core.EditorToolbar.ReturnPoint,
  Atlas.UI.Strings,
  Atlas.UI.Commands.Palette,
  Atlas.UI.Outline.Breadcrumbs,
  Atlas.UI.EditorToolbar.Bar,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Outline.Cache;

const
  TickMs = 150;
  /// <summary>Befehlsliste und offene Dateien nur alle so viele Takte neu lesen (etwa 2 s).</summary>
  SlowTicks = 13;
  PositionBelow = 'belowBreadcrumbs';
  PositionAbove = 'aboveBreadcrumbs';
  PositionInline = 'inBreadcrumbs';
  AtlasPrefix = 'Atlas: ';
  ProblemsId = 'Atlas.ProblemsWindow';
  BackId = 'Atlas.NavBack';
  ForwardId = 'Atlas.NavForward';

type
  TToolbarState = class;

  /// <summary>Erfährt, wenn die IDE eine Leiste mit ihrem Fenster (bzw. der Brotkrumenleiste) freigibt.</summary>
  TToolbarWatcher = class(TComponent)
  private
    FState: TToolbarState;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  end;

  TToolbarState = class
  private
    FTimer: TTimer;
    FWatcher: TToolbarWatcher;
    FBars: TList<TAtlasEditorToolbar>;
    /// <summary>Eltern-Steuerelement des Editors je Leiste (gleicher Index wie FBars).</summary>
    FHosts: TList<TWinControl>;
    FPoints: TAtlasReturnPoints;
    FCommands: TArray<TAtlasCommand>;
    FSlow: Integer;
    FHidden: Boolean;
    // Abschnitte der zuletzt gelesenen Datei.
    FSectionsFile: string;
    FSectionsVersion: Cardinal;
    FSections: TAtlasUnitSections;
    // Zeilenzahl je Datei für das Verschieben der Rücksprungpunkte.
    FLineCounts: TDictionary<string, Integer>;
    FLastFile: string;
    FLastLine: Integer;
    procedure Tick(Sender: TObject);
    function ToolbarOn: Boolean;
    function EditorOf(const AWindow: INTAEditWindow): TWinControl;
    function BarOf(AHost: TWinControl): TAtlasEditorToolbar;
    function CrumbsOf(AHost: TWinControl): TAtlasBreadcrumbBar;
    procedure EnsureBars;
    procedure CreateBar(AHost: TWinControl);
    procedure Place(ABar: TAtlasEditorToolbar; AHost: TWinControl);
    procedure RemoveBars;
    procedure ShowBars(AShown: Boolean);
    procedure Track(const AView: IOTAEditView; const AFileName: string; ALine: Integer);
    procedure UpdateBar(ABar: TAtlasEditorToolbar; const AFileName: string;
      ALine, ACharacter: Integer);
    function ButtonsFor(const AFileName: string; ALine, ACharacter: Integer): TArray<TAtlasToolbarButton>;
    function CommandOf(const AId: string; out ACommand: TAtlasCommand): Boolean;
    procedure ForgetClosedFiles;
    procedure Later(const AAction: TProc);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Removed(ABar: TAtlasEditorToolbar);
    /// <summary>Nach geänderten Einstellungen: Leisten neu anlegen (Position, Belegung), Befehle neu lesen.</summary>
    procedure Reset;
    procedure ApplyTheme;
    /// <summary>Abschnitte der Datei aus dem aktuellen Editortext.</summary>
    function SectionsOf(const AView: IOTAEditView; out AFileName: string): TAtlasUnitSections;
    property Points: TAtlasReturnPoints read FPoints;
  end;

function State: TToolbarState;
begin
  Result := TToolbarState(TAtlasIdeEditorToolbar.FState);
end;

function PlainCaption(const ACaption: string): string;
begin
  Result := ACaption;
  if Result.StartsWith(AtlasPrefix) then
    Result := Copy(Result, Length(AtlasPrefix) + 1, MaxInt);
end;

function BarColors: TAtlasColors;
begin
  if TAtlasIdeSettings.Current.BreadcrumbsIdeColors then
    Result := TAtlasIdeStyle.ChromeColors
  else
    Result := TAtlasIdeStyle.Colors;
end;

function SectionCaption(ATarget: TAtlasSectionTarget): string;
begin
  case ATarget of
    TAtlasSectionTarget.InterfacePart:
      Result := TAtlasStrings.Text(TAtlasTextId.GotoInterfaceCommand);
    TAtlasSectionTarget.ImplementationPart:
      Result := TAtlasStrings.Text(TAtlasTextId.GotoImplementationCommand);
    TAtlasSectionTarget.UsesClause:
      Result := TAtlasStrings.Text(TAtlasTextId.GotoUsesCommand);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.GotoInitializationCommand);
  end;
end;

/// <summary>Sprungziel eines Abschnittsbefehls; False für andere Kennungen.</summary>
function SectionTargetOf(const AId: string; out ATarget: TAtlasSectionTarget): Boolean;
begin
  Result := True;
  if SameText(AId, TAtlasToolbarItems.GotoInterface) then
    ATarget := TAtlasSectionTarget.InterfacePart
  else if SameText(AId, TAtlasToolbarItems.GotoImplementation) then
    ATarget := TAtlasSectionTarget.ImplementationPart
  else if SameText(AId, TAtlasToolbarItems.GotoUses) then
    ATarget := TAtlasSectionTarget.UsesClause
  else if SameText(AId, TAtlasToolbarItems.GotoInitialization) then
    ATarget := TAtlasSectionTarget.Initialization_
  else
    Result := False;
end;

/// <summary>Hervorgehoben, wenn der Caret in diesem Abschnitt steht (finalization zählt zu initialization).</summary>
function SectionPressed(ATarget: TAtlasSectionTarget; ASection: TAtlasCodeSection): Boolean;
begin
  case ATarget of
    TAtlasSectionTarget.InterfacePart:
      Result := ASection = TAtlasCodeSection.InterfacePart;
    TAtlasSectionTarget.ImplementationPart:
      Result := ASection = TAtlasCodeSection.ImplementationPart;
    TAtlasSectionTarget.UsesClause:
      Result := ASection = TAtlasCodeSection.UsesClause;
  else
    Result := (ASection = TAtlasCodeSection.Initialization_) or (ASection = TAtlasCodeSection.Finalization_);
  end;
end;

/// <summary>Caret der Ansicht als 0-basierte Zeile und Zeichenindex; False ohne Ansicht.</summary>
function CaretOf(const AView: IOTAEditView; out ALine, ACharacter: Integer): Boolean;
var
  Cursor: TOTAEditPos;
begin
  Result := False;
  ALine := -1;
  ACharacter := -1;
  if AView = nil then
    Exit;
  Cursor := AView.CursorPos;
  if Cursor.Line < 1 then
    Exit;
  ALine := Cursor.Line - 1;
  ACharacter := TLspSession.ColumnToIndex(TAtlasEditorBuffer.LineText(AView, Cursor.Line), Cursor.Col,
    TAtlasEditorBuffer.TabWidth(AView.Buffer));
  Result := True;
end;

{ TToolbarWatcher }

procedure TToolbarWatcher.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent is TAtlasEditorToolbar) and (FState <> nil) then
    FState.Removed(TAtlasEditorToolbar(AComponent));
end;

{ TToolbarState }

constructor TToolbarState.Create;
begin
  inherited Create;
  FBars := TList<TAtlasEditorToolbar>.Create;
  FHosts := TList<TWinControl>.Create;
  FPoints := TAtlasReturnPoints.Create;
  FLineCounts := TDictionary<string, Integer>.Create;
  FWatcher := TToolbarWatcher.Create(nil);
  FWatcher.FState := Self;
  FLastLine := -1;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := TickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
  Reset;
end;

destructor TToolbarState.Destroy;
begin
  FTimer.Free;
  RemoveBars;
  FWatcher.Free;
  FLineCounts.Free;
  FPoints.Free;
  FHosts.Free;
  FBars.Free;
  inherited Destroy;
end;

procedure TToolbarState.RemoveBars;
var
  Bar: TAtlasEditorToolbar;
begin
  // Leisten selbst freigeben; der Wächter darf dabei nicht mehr zurückschreiben.
  FWatcher.FState := nil;
  try
    for Bar in FBars.ToArray do
    begin
      Bar.RemoveFreeNotification(FWatcher);
      Bar.Free;
    end;
  finally
    FBars.Clear;
    FHosts.Clear;
    FWatcher.FState := Self;
  end;
end;

procedure TToolbarState.Removed(ABar: TAtlasEditorToolbar);
var
  Index: Integer;
begin
  Index := FBars.IndexOf(ABar);
  if Index < 0 then
    Exit;
  FBars.Delete(Index);
  FHosts.Delete(Index);
end;

function TToolbarState.ToolbarOn: Boolean;
begin
  Result := TAtlasIdeSettings.Current.EditorToolbar;
end;

procedure TToolbarState.Reset;
var
  Bar: TAtlasEditorToolbar;
begin
  FSlow := 0;
  FSectionsFile := '';
  // Die Position stellt Place beim nächsten Takt um, die Knöpfe UpdateBar; hier nur, was alle Leisten betrifft.
  for Bar in FBars do
    Bar.Labels := TAtlasIdeSettings.Current.EditorToolbarLabels;
  ApplyTheme;
  if Assigned(TAtlasIdeEditorToolbar.FHooks.Commands) then
    FCommands := TAtlasIdeEditorToolbar.FHooks.Commands()
  else
    FCommands := nil;
end;

procedure TToolbarState.ApplyTheme;
var
  Bar: TAtlasEditorToolbar;
  Colors: TAtlasColors;
begin
  Colors := BarColors;
  for Bar in FBars do
    Bar.SetColors(Colors);
end;

function TToolbarState.EditorOf(const AWindow: INTAEditWindow): TWinControl;
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

function TToolbarState.BarOf(AHost: TWinControl): TAtlasEditorToolbar;
var
  Index: Integer;
begin
  for Index := 0 to FHosts.Count - 1 do
    if FHosts[Index] = AHost then
      Exit(FBars[Index]);
  Result := nil;
end;

function TToolbarState.CrumbsOf(AHost: TWinControl): TAtlasBreadcrumbBar;
var
  Index: Integer;
begin
  for Index := 0 to AHost.ControlCount - 1 do
    if AHost.Controls[Index] is TAtlasBreadcrumbBar then
      Exit(TAtlasBreadcrumbBar(AHost.Controls[Index]));
  Result := nil;
end;

procedure TToolbarState.EnsureBars;
var
  Services: INTAEditorServices;
  Index: Integer;
  Editor: TWinControl;
  Bar: TAtlasEditorToolbar;
begin
  if not Supports(BorlandIDEServices, INTAEditorServices, Services) then
    Exit;
  for Index := 0 to Services.EditWindowCount - 1 do
  begin
    Editor := EditorOf(Services.EditWindow[Index]);
    if Editor = nil then
      Continue;
    Bar := BarOf(Editor.Parent);
    if Bar = nil then
      CreateBar(Editor.Parent)
    else
      Place(Bar, Editor.Parent);
  end;
end;

/// <summary>Eigene Methode: Jede Leiste braucht ihre eigene gefangene Variable.</summary>
procedure TToolbarState.CreateBar(AHost: TWinControl);
var
  Bar: TAtlasEditorToolbar;
begin
  Bar := TAtlasEditorToolbar.Create(nil);
  Bar.FreeNotification(FWatcher);
  FBars.Add(Bar);
  FHosts.Add(AHost);
  Bar.SetColors(BarColors);
  Bar.Labels := TAtlasIdeSettings.Current.EditorToolbarLabels;
  Bar.MoreHint := TAtlasStrings.Text(TAtlasTextId.EditorToolbarMore);
  Bar.GearHint := TAtlasStrings.Text(TAtlasTextId.EditorToolbarCustomizeCommand);
  Bar.CustomizeCaption := TAtlasStrings.Text(TAtlasTextId.EditorToolbarCustomizeCommand);
  Bar.OnCommand :=
    procedure(const AId: string)
    var
      Id: string;
    begin
      Id := AId;
      // Im Protokoll: Der Klick kam an (Handtest zu „Klick ohne Wirkung“).
      TAtlasGuard.Log('Editorleiste: Klick auf ' + Id);
      // Nach dem Klick: Die IDE holt den Fokus in den Editor; Popups und Dialoge erst danach.
      Later(
        procedure
        begin
          if SameText(Id, TAtlasToolbarItems.CommandPalette) then
          begin
            if Assigned(TAtlasIdeEditorToolbar.FHooks.ShowPalette) then
              TAtlasIdeEditorToolbar.FHooks.ShowPalette();
          end
          else if Assigned(TAtlasIdeEditorToolbar.FHooks.Execute) then
            TAtlasIdeEditorToolbar.FHooks.Execute(Id);
        end);
    end;
  Bar.OnReturn :=
    procedure
    begin
      TAtlasGuard.Log('Editorleiste: Klick auf Rücksprung');
      Later(
        procedure
        begin
          TAtlasIdeEditorToolbar.ReturnFromSection;
        end);
    end;
  Bar.OnCustomize :=
    procedure
    begin
      TAtlasGuard.Log('Editorleiste: Klick auf Leiste anpassen');
      Later(
        procedure
        begin
          TAtlasIdeEditorToolbar.Customize;
        end);
    end;
  Place(Bar, AHost);
end;

/// <summary>Leiste an ihre Stelle: rechts in der Brotkrumenzeile oder oben, unter bzw. über den Brotkrumen. Die
/// Brotkrumenleiste kann später kommen oder gehen; jeder Takt prüft die Reihenfolge.</summary>
procedure TToolbarState.Place(ABar: TAtlasEditorToolbar; AHost: TWinControl);
var
  Crumbs: TAtlasBreadcrumbBar;
  Position: string;
  Width_: Integer;
begin
  Crumbs := CrumbsOf(AHost);
  Position := TAtlasIdeSettings.Current.EditorToolbarPosition;
  if SameText(Position, PositionInline) and (Crumbs <> nil) then
  begin
    if ABar.Parent <> Crumbs then
    begin
      ABar.Parent := nil;
      ABar.InlineMode := True;
      ABar.Align := alRight;
      ABar.Parent := Crumbs;
    end;
    // So breit wie nötig, höchstens die halbe Zeile; der Rest geht ins ».
    Width_ := Min(ABar.PreferredWidth, Max(MulDiv(120, Crumbs.CurrentPPI, 96), Crumbs.ClientWidth div 2));
    if ABar.Width <> Width_ then
      ABar.Width := Width_;
    Exit;
  end;
  if ABar.Parent <> AHost then
  begin
    ABar.Parent := nil;
    ABar.InlineMode := False;
    ABar.Align := alNone;
    ABar.Top := 0;
    if (Crumbs <> nil) and not SameText(Position, PositionAbove) then
      ABar.Top := Crumbs.Top + Crumbs.Height;
    ABar.Align := alTop;
    ABar.Parent := AHost;
  end;
  if Crumbs = nil then
    Exit;
  // alTop ordnet nach Top: kleiner steht weiter oben.
  if SameText(Position, PositionAbove) then
  begin
    if ABar.Top > Crumbs.Top then
      ABar.Top := Crumbs.Top - 1;
  end
  else if ABar.Top < Crumbs.Top then
    ABar.Top := Crumbs.Top + Crumbs.Height;
end;

procedure TToolbarState.ShowBars(AShown: Boolean);
var
  Bar: TAtlasEditorToolbar;
begin
  for Bar in FBars do
    if Bar.Visible <> AShown then
      Bar.Visible := AShown;
end;

function TToolbarState.SectionsOf(const AView: IOTAEditView; out AFileName: string): TAtlasUnitSections;
var
  Snapshot: TAtlasEditorSnapshot;
begin
  Snapshot := TAtlasEditorSnapshots.Get(AView);
  AFileName := Snapshot.FileName;
  if (Snapshot.Version <> FSectionsVersion) or not SameText(Snapshot.FileName, FSectionsFile) then
  begin
    FSections := TAtlasSectionScanner.Scan(TTextLines.SplitLines(Snapshot.Text));
    FSectionsVersion := Snapshot.Version;
    FSectionsFile := Snapshot.FileName;
  end;
  Result := FSections;
end;

function TToolbarState.CommandOf(const AId: string; out ACommand: TAtlasCommand): Boolean;
var
  Command: TAtlasCommand;
begin
  for Command in FCommands do
    if SameText(Command.Id, AId) then
    begin
      ACommand := Command;
      Exit(True);
    end;
  ACommand := Default(TAtlasCommand);
  Result := False;
end;

function TToolbarState.ButtonsFor(const AFileName: string; ALine, ACharacter: Integer): TArray<TAtlasToolbarButton>;
var
  Items: TArray<string>;
  Id, Caption, Key, Hint: string;
  Command: TAtlasCommand;
  Button: TAtlasToolbarButton;
  Target: TAtlasSectionTarget;
  Mark: TAtlasSectionMark;
  Section: TAtlasCodeSection;
  Findings, Pinned, Index: Integer;
  Hooks: TAtlasIdeEditorToolbar.THooks;
begin
  Result := nil;
  Hooks := TAtlasIdeEditorToolbar.FHooks;
  Items := TAtlasToolbarItems.Parse(TAtlasIdeSettings.Current.EditorToolbarItems);
  Pinned := TAtlasToolbarItems.PinnedCount(Items);
  Section := FSections.SectionAt(ALine, ACharacter);
  for Index := 0 to High(Items) do
  begin
    Id := Items[Index];
    if TAtlasToolbarItems.IsSeparator(Id) then
    begin
      Result := Result + [TAtlasToolbarButton.Separator];
      Continue;
    end;
    // Die Palette selbst ist kein Palettenbefehl; abgeschaltete Funktionen fehlen in der Palette und in der Leiste.
    if SameText(Id, TAtlasToolbarItems.CommandPalette) then
      Caption := TAtlasStrings.Text(TAtlasTextId.CommandPaletteCommand)
    else if CommandOf(Id, Command) then
      Caption := PlainCaption(Command.Caption)
    else
      Continue;
    Key := '';
    if Assigned(Hooks.ShortCutOf) then
      Key := Hooks.ShortCutOf(Id);
    Hint := Caption;
    if Key <> '' then
      Hint := Hint + ' (' + Key + ')';
    Button := TAtlasToolbarButton.Create(Id, Caption, Hint, TAtlasToolbarIcons.IconOf(Id));
    Button.Pinned := Index < Pinned;
    if SectionTargetOf(Id, Target) then
    begin
      Button.Enabled := (FSectionsFile <> '') and FSections.Target(Target, ALine, ACharacter, Mark);
      Button.Pressed := Button.Enabled and SectionPressed(Target, Section);
      if not Button.Enabled then
      begin
        if Target in [TAtlasSectionTarget.InterfacePart, TAtlasSectionTarget.ImplementationPart] then
          Button.Hint := TAtlasStrings.Text(TAtlasTextId.EditorToolbarNoParts)
        else
          Button.Hint := Format(TAtlasStrings.Text(TAtlasTextId.EditorToolbarNoSection), [Caption]);
      end;
    end
    else if SameText(Id, ProblemsId) and Assigned(Hooks.FindingsOf) and (AFileName <> '') then
    begin
      Findings := Hooks.FindingsOf(AFileName);
      Button.Dot := Findings > 0;
      if Findings > 0 then
        Button.Hint := Format(TAtlasStrings.Text(TAtlasTextId.EditorToolbarFindings), [Hint, Findings]);
    end
    else if SameText(Id, BackId) and Assigned(Hooks.CanGoBack) then
      Button.Enabled := Hooks.CanGoBack()
    else if SameText(Id, ForwardId) and Assigned(Hooks.CanGoForward) then
      Button.Enabled := Hooks.CanGoForward();
    Result := Result + [Button];
  end;
end;

procedure TToolbarState.UpdateBar(ABar: TAtlasEditorToolbar; const AFileName: string;
  ALine, ACharacter: Integer);
var
  Point: TAtlasReturnPoint;
  Hint: string;
begin
  ABar.Labels := TAtlasIdeSettings.Current.EditorToolbarLabels;
  ABar.SetButtons(ButtonsFor(AFileName, ALine, ACharacter));
  if TAtlasIdeSettings.Current.EditorToolbarReturnButton and FPoints.Find(AFileName, Point) then
  begin
    if Point.Context <> '' then
      Hint := Format(TAtlasStrings.Text(TAtlasTextId.EditorToolbarReturnLineIn), [Point.Line + 1, Point.Context])
    else
      Hint := Format(TAtlasStrings.Text(TAtlasTextId.EditorToolbarReturnLine), [Point.Line + 1]);
    ABar.SetReturn(True, IntToStr(Point.Line + 1), Hint);
  end
  else
    ABar.SetReturn(False, '', '');
end;

/// <summary>Rücksprungpunkte mit eingefügten bzw. gelöschten Zeilen verschieben (wie der Navigationsverlauf) und
/// erledigen, wenn der Caret auf die Zeile zurückkommt.</summary>
procedure TToolbarState.Track(const AView: IOTAEditView; const AFileName: string; ALine: Integer);
var
  Key: string;
  Count, Known, Anchor: Integer;
begin
  if FPoints.Count = 0 then
  begin
    FLineCounts.Clear;
    Exit;
  end;
  Key := AnsiUpperCase(AFileName);
  Count := AView.Buffer.GetLinesInBuffer;
  if FLineCounts.TryGetValue(Key, Known) and (Known <> Count) then
  begin
    // Eingefügt bzw. gelöscht wurde an der Cursorstelle vor oder nach der Änderung.
    Anchor := ALine;
    if SameText(FLastFile, AFileName) and (FLastLine >= 0) then
      Anchor := Min(Anchor, FLastLine);
    FPoints.LinesChanged(AFileName, Anchor, Count - Known);
  end;
  FLineCounts.AddOrSetValue(Key, Count);
  FPoints.Caret(AFileName, ALine);
  FLastFile := AFileName;
  FLastLine := ALine;
end;

procedure TToolbarState.ForgetClosedFiles;
var
  Services: IOTAModuleServices;
  Files: TArray<string>;
  Index: Integer;
begin
  if (FPoints.Count = 0) or not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Exit;
  Files := nil;
  for Index := 0 to Services.ModuleCount - 1 do
    Files := Files + [Services.Modules[Index].FileName];
  FPoints.KeepOnly(Files);
end;

procedure TToolbarState.Tick(Sender: TObject);
var
  On_: Boolean;
begin
  On_ := ToolbarOn;
  if TAtlasGuard.Disabled(TAtlasFeature.EditorToolbar) then
  begin
    // Sicherung ausgelöst: Leisten weg, bis die Funktion wieder eingeschaltet ist.
    if not FHidden then
    begin
      FHidden := True;
      TAtlasGuard.Log('Editorleiste: durch die Sicherung abgeschaltet');
      try
        ShowBars(False);
      except
        on E: Exception do
          TAtlasGuard.Log('Editorleiste: nicht ausgeblendet: ' + TAtlasGuard.SafeMessage(E.Message));
      end;
    end;
    Exit;
  end;
  if FHidden then
  begin
    FHidden := False;
    ShowBars(True);
  end;
  // Ohne Leiste und ohne Rücksprungpunkte gibt es nichts zu tun.
  if not On_ and (FPoints.Count = 0) then
  begin
    if FBars.Count > 0 then
      RemoveBars;
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.EditorToolbar,
    procedure
    var
      View: IOTAEditView;
      FileName: string;
      Line, Character: Integer;
      Services: INTAEditorServices;
      Editor: TWinControl;
      Bar: TAtlasEditorToolbar;
    begin
      Inc(FSlow);
      if FSlow >= SlowTicks then
      begin
        FSlow := 0;
        if Assigned(TAtlasIdeEditorToolbar.FHooks.Commands) then
          FCommands := TAtlasIdeEditorToolbar.FHooks.Commands();
        ForgetClosedFiles;
      end;
      if On_ then
        EnsureBars
      else if FBars.Count > 0 then
        RemoveBars;
      View := TAtlasEditorBuffer.ActiveView;
      if (View = nil) or not CaretOf(View, Line, Character) then
        Exit;
      FileName := View.Buffer.FileName;
      Track(View, FileName, Line);
      if not On_ or not Supports(BorlandIDEServices, INTAEditorServices, Services) then
        Exit;
      Editor := EditorOf(Services.TopEditWindow);
      if Editor = nil then
        Exit;
      Bar := BarOf(Editor.Parent);
      if Bar = nil then
        Exit;
      SectionsOf(View, FileName);
      if FileName = '' then
        FileName := View.Buffer.FileName;
      UpdateBar(Bar, FileName, Line, Character);
    end);
end;

/// <summary>Erst nach dem Klick ausführen (siehe CreateBar); nur, wenn der Zustand dann noch lebt.</summary>
procedure TToolbarState.Later(const AAction: TProc);
var
  Owner: TToolbarState;
  Action: TProc;
begin
  Owner := Self;
  Action := AAction;
  TAtlasMainThread.ForceQueue(TAtlasFeature.EditorToolbar,
    procedure
    begin
      if TAtlasIdeEditorToolbar.FState <> Owner then
        Exit;
      TAtlasGuard.Run(TAtlasFeature.EditorToolbar, Action);
    end);
end;

{ TAtlasIdeEditorToolbar }

class procedure TAtlasIdeEditorToolbar.Say(const AText: string);
begin
  if Assigned(FHooks.Message) then
    FHooks.Message(AText);
end;

class function TAtlasIdeEditorToolbar.Enabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.EditorToolbar;
end;

class procedure TAtlasIdeEditorToolbar.Install(const AHooks: THooks);
begin
  FreeAndNil(FState);
  FHooks := AHooks;
  // Immer: Die Abschnittsbefehle samt Rücksprung arbeiten auch ohne Leiste.
  FState := TToolbarState.Create;
end;

class procedure TAtlasIdeEditorToolbar.Uninstall;
begin
  FreeAndNil(FState);
  FHooks := Default(THooks);
end;

class procedure TAtlasIdeEditorToolbar.ApplySettings;
begin
  if FState <> nil then
    State.Reset;
end;

class procedure TAtlasIdeEditorToolbar.ThemeChanged;
begin
  if FState <> nil then
    State.ApplyTheme;
end;

class procedure TAtlasIdeEditorToolbar.GoToSection(ATarget: TAtlasSectionTarget);
var
  View: IOTAEditView;
  FileName: string;
  Sections: TAtlasUnitSections;
  Mark: TAtlasSectionMark;
  Line, Character, Rows: Integer;
  Context: string;
  Outline: TAtlasOutlineSnapshot;
begin
  if FState = nil then
    Exit;
  View := TAtlasEditorBuffer.ActiveView;
  if (View = nil) or not CaretOf(View, Line, Character) then
    Exit;
  Sections := State.SectionsOf(View, FileName);
  if FileName = '' then
    FileName := View.Buffer.FileName;
  if not Sections.Target(ATarget, Line, Character, Mark) then
  begin
    Say(Format(TAtlasStrings.Text(TAtlasTextId.EditorToolbarNoSection), [SectionCaption(ATarget)]));
    Exit;
  end;
  // Methode der Ausgangszeile für den Tooltip „Zurück zu Zeile 214 · TfrmKunde.btnSpeichernClick“.
  Context := '';
  Outline := TAtlasIdeOutlineCache.Refresh(View);
  if (Outline.Status = TAtlasOutlineStatus.Ready) and SameText(Outline.FileName, FileName) then
    Context := TAtlasReturnPoints.ContextAt(Outline.Nodes, Line);
  TAtlasGuard.Log(Format('Editorleiste: Abschnittssprung %d', [Ord(ATarget)]));
  TAtlasIdeNavigation.GoToLocation(FileName, Mark.Line, Mark.Character);
  // Ziel ins obere Drittel: Darunter steht, was zum Abschnitt gehört.
  View := TAtlasEditorBuffer.ActiveView;
  if View <> nil then
  begin
    Rows := Max(1, View.ViewSize.cy);
    View.SetTopLeft(Max(1, Mark.Line + 1 - Rows div 3), View.LeftColumn);
    View.Paint;
  end;
  State.Points.Jumped(FileName, Line, Mark.Line, Context);
end;

class procedure TAtlasIdeEditorToolbar.GotoInterface;
begin
  GoToSection(TAtlasSectionTarget.InterfacePart);
end;

class procedure TAtlasIdeEditorToolbar.GotoImplementation;
begin
  GoToSection(TAtlasSectionTarget.ImplementationPart);
end;

class procedure TAtlasIdeEditorToolbar.GotoUses;
begin
  GoToSection(TAtlasSectionTarget.UsesClause);
end;

class procedure TAtlasIdeEditorToolbar.GotoInitialization;
begin
  GoToSection(TAtlasSectionTarget.Initialization_);
end;

class procedure TAtlasIdeEditorToolbar.ReturnFromSection;
var
  View: IOTAEditView;
  FileName, Text: string;
  Point: TAtlasReturnPoint;
  Character: Integer;
begin
  if FState = nil then
    Exit;
  View := TAtlasEditorBuffer.ActiveView;
  if View = nil then
    Exit;
  FileName := View.Buffer.FileName;
  if not State.Points.Find(FileName, Point) then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.EditorToolbarNoReturn));
    Exit;
  end;
  // Auf das erste Zeichen der Zeile; die Spalte merkt sich der Sprung nicht.
  Text := TAtlasEditorBuffer.LineText(View, Point.Line + 1);
  Character := Length(Text) - Length(TrimLeft(Text));
  TAtlasIdeNavigation.GoToLocation(FileName, Point.Line, Character);
  State.Points.Caret(FileName, Point.Line);
end;

class procedure TAtlasIdeEditorToolbar.FindMethod;
var
  View: IOTAEditView;
  Snapshot: TAtlasOutlineSnapshot;
  Nodes: TAtlasOutlineNodes;
  Routines: TArray<Integer>;
  Commands: TArray<TAtlasCommand>;
  Command: TAtlasCommand;
  Node, Line, Character: Integer;
  FileName, Current: string;
  Window: TAtlasPaletteWindow;
  Area: TRect;
begin
  View := TAtlasEditorBuffer.ActiveView;
  if View = nil then
    Exit;
  Snapshot := TAtlasIdeOutlineCache.Refresh(View);
  Routines := nil;
  if Snapshot.Status = TAtlasOutlineStatus.Ready then
    Routines := TAtlasBreadcrumbs.Routines(Snapshot.Nodes);
  if Length(Routines) = 0 then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.FindMethodNoOutline));
    Exit;
  end;
  // Kopien: Das Popup lebt länger als der aktuelle Stand.
  Nodes := Snapshot.Nodes;
  FileName := Snapshot.FileName;
  Current := '';
  if CaretOf(View, Line, Character) then
    Current := TAtlasReturnPoints.ContextAt(Nodes, Line);
  Commands := nil;
  for Node in Routines do
  begin
    Command := Default(TAtlasCommand);
    Command.Id := IntToStr(Node);
    Command.Caption := TAtlasBreadcrumbs.QualifiedName(Nodes, Node);
    Command.Path := Nodes[Node].Detail;
    Commands := Commands + [Command];
  end;
  Window := TAtlasPaletteWindow.CreatePalette(Application, Commands, nil, TAtlasIdeStyle.Colors);
  Window.Prompt := Format(TAtlasStrings.Text(TAtlasTextId.FindMethodPrompt), [ExtractFileName(FileName)]);
  // Ohne Eingabe in Quelltextreihenfolge, die Methode am Caret vorgewählt.
  Window.KeepOrder := True;
  for Command in Commands do
    if (Current <> '') and SameText(Command.Caption, Current) then
      Window.InitialId := Command.Id;
  Window.OnExecuteShift :=
    procedure(ACommand: TAtlasCommand; AShifted: Boolean)
    var
      Chosen, Target: Integer;
    begin
      Chosen := StrToIntDef(ACommand.Id, -1);
      if (Chosen < 0) or (Chosen > High(Nodes)) then
        Exit;
      // Enter zur Implementierung, Umschalt+Enter zur Deklaration.
      Target := TAtlasBreadcrumbs.Target(Nodes, Chosen, not AShifted);
      if Target < 0 then
        Exit;
      TAtlasIdeNavigation.GoToLocation(FileName, Nodes[Target].NameLine, Nodes[Target].NameCharacter);
    end;
  if Screen.ActiveForm <> nil then
    Area := Screen.ActiveForm.BoundsRect
  else if Application.MainForm <> nil then
    Area := Application.MainForm.BoundsRect
  else
    Area := Screen.WorkAreaRect;
  Window.ShowOver(Area);
end;

class function TAtlasIdeEditorToolbar.CommandInfos: TArray<TAtlasToolbarCommandInfo>;
var
  Command: TAtlasCommand;
begin
  Result := nil;
  if Assigned(FHooks.Commands) then
    for Command in FHooks.Commands() do
      Result := Result + [TAtlasToolbarCommandInfo.Create(Command.Id, PlainCaption(Command.Caption))];
  Result := Result + [TAtlasToolbarCommandInfo.Create(TAtlasToolbarItems.CommandPalette,
    TAtlasStrings.Text(TAtlasTextId.CommandPaletteCommand))];
end;

class procedure TAtlasIdeEditorToolbar.Customize;
var
  Config: TAtlasToolbarConfig;
  Next: TAtlasPluginSettings;
begin
  Next := TAtlasIdeSettings.Stored;
  Config.Items := TAtlasToolbarItems.Parse(Next.EditorToolbarItems);
  Config.Labels := Next.EditorToolbarLabels;
  Config.Position := Next.EditorToolbarPosition;
  if not TAtlasToolbarCustomizeDialog.Execute(CommandInfos, Config) then
    Exit;
  Next.EditorToolbarItems := TAtlasToolbarItems.Format(Config.Items);
  Next.EditorToolbarLabels := Config.Labels;
  Next.EditorToolbarPosition := Config.Position;
  TAtlasIdeSettings.Update(Next);
end;

end.
