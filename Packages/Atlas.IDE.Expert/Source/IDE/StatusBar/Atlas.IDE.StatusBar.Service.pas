unit Atlas.IDE.StatusBar.Service;

// Atlas-Statusleiste (#1155) in der IDE:
// - Unten im Eltern-Steuerelement des Editors jedes Editorfensters steht eine
//   Leiste (TAtlasEditorStatusBar), direkt über der Statuszeile der IDE und
//   unter einer offenen Atlas-Suchleiste (#878); Fenster, die später aufgehen,
//   bekommen sie beim nächsten Takt.
// - Ein Zeitgeber (250 ms) setzt den Inhalt: Status aus dem Atlas-Feld
//   (TAtlasStatusField, Text, Zustand, Tooltip), Meldungen dieser Unit aus dem
//   Speicher der Probleme (TAtlasProblemsController.Current), Live-Prüfung
//   (problems.live, Checking, LastCheck) und die Methode am Cursor aus der
//   Gliederung (TAtlasIdeOutlineCache) mit Zeilen und CC aus
//   atlas.server.metrics (Hook Metrics; die Leiste meldet über WantMetrics,
//   dass sie Metriken braucht). Die oberste Leiste bekommt alles, die anderen
//   nur den Status.
// - Zeigt die Leiste das Element status, ist das Atlas-Feld der Statuszeile
//   0 breit (TAtlasStatusField.Relocated); Klick und Rechtsklick öffnen dort
//   wie bisher Statusfenster und Schnellschalter, nur über der Leiste.
// - Ungelesene Benachrichtigungen (#1234) stehen als Plakette hinter dem
//   Status (aus dem Atlas-Feld, das dann 0 breit ist); Klick öffnet die Liste.
// - Klick auf einen Zähler springt zum nächsten Befund dieser Art in der
//   Unit (Umlauf), Doppelklick öffnet „Atlas-Prüfung“ für die Unit, Klick auf
//   die Live-Prüfung prüft alle Units neu (Hook Recheck, atlas.server.recheck,
//   #1231), Klick auf die Methode springt zum Methodenkopf. Aktionen laufen
//   erst nach dem Klick
//   (die IDE holt den Fokus in den Editor), wie bei der Editorleiste.
// - Menü „Leiste anpassen“: Elemente ein- und ausblenden
//   (editor.statusBar.items), „Statusleiste ausblenden“ (editor.statusBar).
// - Eigene Sicherung TAtlasFeature.StatusBar: Löst sie aus, verschwinden die
//   Leisten (mit Zeile im Protokoll, den Aufrufer nennt der Bericht der
//   Sicherung), und das Atlas-Feld kehrt in die Statuszeile zurück.
// - editor.statusBar aus: Leisten weg, das Atlas-Feld bleibt in der
//   Statuszeile; Elemente gelten ohne Neustart.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Types,
  Atlas.Core.Editor.Metrics,
  Atlas.IDE.Status.Field;

type
  /// <summary>Letzte Metriken der Datei; False ohne.</summary>
  TAtlasStatusMetricsFunc = reference to function(const AFileName: string; out AMetrics: TAtlasFileMetrics): Boolean;

  TAtlasIdeStatusBar = class
  public type
    THooks = record
      /// <summary>Atlas-Feld der Statuszeile; nil ohne.</summary>
      Field: TFunc<TAtlasStatusField>;
      /// <summary>Metriken aus atlas.server.metrics (Lens-Abruf, #66).</summary>
      Metrics: TAtlasStatusMetricsFunc;
      /// <summary>Metriken auch ohne Lens holen (True) bzw. nicht mehr (False).</summary>
      WantMetrics: TProc<Boolean>;
      /// <summary>Zeile in der Meldungsansicht.</summary>
      Message: TProc<string>;
      /// <summary>Alle Units neu prüfen lassen (atlas.server.recheck, #1231); im Hintergrund.</summary>
      Recheck: TProc;
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
    /// <summary>Linke Oberkante des Elements status in der Leiste des obersten Editorfensters (Bildschirm).
    /// </summary>
    class function Anchor(out APoint: TPoint): Boolean; static;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.StatusBarItems,
  Atlas.Core.Style.Palette,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Registry,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Findings,
  Atlas.Core.Problems.Store,
  Atlas.Core.StatusBar.Content,
  Atlas.UI.Strings,
  Atlas.UI.Status.Window,
  Atlas.UI.StatusBar.Bar,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Outline.Cache,
  Atlas.IDE.Problems.Controller,
  Atlas.IDE.Problems.Service;

const
  TickMs = 250;
  LogPrefix = 'Atlas-Statusleiste: ';

type
  TStatusBarState = class;

  /// <summary>Erfährt, wenn die IDE eine Leiste mit ihrem Fenster freigibt.</summary>
  TStatusBarWatcher = class(TComponent)
  private
    FState: TStatusBarState;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  end;

  TStatusBarState = class
  private
    FTimer: TTimer;
    FWatcher: TStatusBarWatcher;
    FBars: TList<TAtlasEditorStatusBar>;
    /// <summary>Eltern-Steuerelement des Editors je Leiste (gleicher Index wie FBars).</summary>
    FHosts: TList<TWinControl>;
    FHidden: Boolean;
    FWanted: Boolean;
    // Methode der obersten Leiste beim letzten Takt: Ziel des Klicks.
    FMethodFile: string;
    FMethod: TAtlasStatusMethod;
    procedure Tick(Sender: TObject);
    function EditorOf(const AWindow: INTAEditWindow): TWinControl;
    function BarOf(AHost: TWinControl): TAtlasEditorStatusBar;
    procedure EnsureBars;
    procedure CreateBar(AHost: TWinControl);
    procedure Place(ABar: TAtlasEditorStatusBar; AHost: TWinControl);
    procedure RemoveBars;
    procedure ShowBars(AShown: Boolean);
    /// <summary>Gibt gesperrte Leisten frei, sobald wieder ein Editor aktiv ist. Beim Schließen aller Editoren
    /// (Projektwechsel) sperrt die IDE jedes Steuerelement im Editor-Panel (Aufrufer laut Protokoll coreide370) und
    /// gibt danach nur ihre eigenen wieder frei; ohne Abgleich blieben die Leisten bis zum Neustart taub.</summary>
    procedure EnableBars;
    procedure Want(AOn: Boolean);
    procedure StatusInto(var AView: TAtlasStatusBarView);
    function ViewFor(const AView: IOTAEditView; const AItems: TArray<string>): TAtlasStatusBarView;
    procedure Later(const AAction: TProc);
    procedure RefreshField;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Removed(ABar: TAtlasEditorStatusBar);
    procedure Reset;
    procedure ApplyTheme;
    function TopBar: TAtlasEditorStatusBar;
    procedure JumpToFinding(AKind: TAtlasFindingKind);
    procedure JumpToMethod;
    procedure Recheck;
    procedure ToggleItem(const AId: string);
    procedure HideBar;
  end;

function State: TStatusBarState;
begin
  Result := TStatusBarState(TAtlasIdeStatusBar.FState);
end;

function BarColors: TAtlasColors;
begin
  // Wie Brotkrumen- und Editorleiste.
  if TAtlasIdeSettings.Current.BreadcrumbsIdeColors then
    Result := TAtlasIdeStyle.ChromeColors
  else
    Result := TAtlasIdeStyle.Colors;
end;

function LiveTexts: TAtlasStatusLiveTexts;
begin
  Result.Live := TAtlasStrings.Text(TAtlasTextId.StatusBarLive);
  Result.OnSave := TAtlasStrings.Text(TAtlasTextId.StatusBarOnSave);
  Result.Checking := TAtlasStrings.Text(TAtlasTextId.StatusBarChecking);
  Result.CheckedAgo := TAtlasStrings.Text(TAtlasTextId.StatusBarCheckedAgo);
  Result.Seconds := TAtlasStrings.Text(TAtlasTextId.StatusBarSeconds);
  Result.Minutes := TAtlasStrings.Text(TAtlasTextId.StatusBarMinutes);
  Result.Hours := TAtlasStrings.Text(TAtlasTextId.StatusBarHours);
  Result.Separator := TAtlasStatusSummary.Separator;
  Result.ProjectProgress := TAtlasStrings.Text(TAtlasTextId.StatusBarProjectProgress);
end;

function ItemCaptions: TArray<string>;
begin
  // Reihenfolge wie TAtlasStatusBarItems.All.
  Result := TArray<string>.Create(TAtlasStrings.Text(TAtlasTextId.StatusBarItemStatus),
    TAtlasStrings.Text(TAtlasTextId.StatusBarItemFindings), TAtlasStrings.Text(TAtlasTextId.StatusBarItemLiveCheck),
    TAtlasStrings.Text(TAtlasTextId.StatusBarItemMethod));
end;

/// <summary>Probleme an (wie Wellenlinien und „Atlas-Prüfung“)?</summary>
function ProblemsOn(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.Enabled and ASettings.Problems and (TAtlasProblemsController.Current <> nil) and
    not TAtlasGuard.Disabled(TAtlasFeature.Problems);
end;

/// <summary>Caret der Ansicht als 0-basierte Zeile und Zeichenindex; False ohne Ansicht.</summary>
function CaretOf(const AView: IOTAEditView; out ALine, ACharacter: Integer): Boolean;
var
  Cursor: TOTAEditPos;
begin
  Result := False;
  ALine := -1;
  ACharacter := -1;
  if (AView = nil) or (AView.Buffer = nil) then
    Exit;
  Cursor := AView.CursorPos;
  if Cursor.Line < 1 then
    Exit;
  ALine := Cursor.Line - 1;
  ACharacter := TLspSession.ColumnToIndex(TAtlasEditorBuffer.LineText(AView, Cursor.Line), Cursor.Col,
    TAtlasEditorBuffer.TabWidth(AView.Buffer));
  Result := True;
end;

{ TStatusBarWatcher }

procedure TStatusBarWatcher.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent is TAtlasEditorStatusBar) and (FState <> nil) then
    FState.Removed(TAtlasEditorStatusBar(AComponent));
end;

{ TStatusBarState }

constructor TStatusBarState.Create;
begin
  inherited Create;
  FBars := TList<TAtlasEditorStatusBar>.Create;
  FHosts := TList<TWinControl>.Create;
  FWatcher := TStatusBarWatcher.Create(nil);
  FWatcher.FState := Self;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := TickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TStatusBarState.Destroy;
begin
  FTimer.Free;
  Want(False);
  RemoveBars;
  FWatcher.Free;
  FHosts.Free;
  FBars.Free;
  inherited Destroy;
end;

procedure TStatusBarState.RemoveBars;
var
  Bar: TAtlasEditorStatusBar;
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

procedure TStatusBarState.Removed(ABar: TAtlasEditorStatusBar);
var
  Index: Integer;
begin
  Index := FBars.IndexOf(ABar);
  if Index < 0 then
    Exit;
  FBars.Delete(Index);
  FHosts.Delete(Index);
end;

procedure TStatusBarState.Reset;
begin
  ApplyTheme;
  // Umzug des Atlas-Felds folgt editor.statusBar und dem Element status.
  RefreshField;
end;

procedure TStatusBarState.RefreshField;
var
  Field: TAtlasStatusField;
begin
  Field := nil;
  if Assigned(TAtlasIdeStatusBar.FHooks.Field) then
    Field := TAtlasIdeStatusBar.FHooks.Field();
  if Field <> nil then
    Field.RequestRefresh;
end;

procedure TStatusBarState.ApplyTheme;
var
  Bar: TAtlasEditorStatusBar;
  Colors: TAtlasColors;
begin
  Colors := BarColors;
  for Bar in FBars do
    Bar.SetColors(Colors);
end;

procedure TStatusBarState.Want(AOn: Boolean);
begin
  if AOn = FWanted then
    Exit;
  FWanted := AOn;
  if Assigned(TAtlasIdeStatusBar.FHooks.WantMetrics) then
    TAtlasIdeStatusBar.FHooks.WantMetrics(AOn);
end;

function TStatusBarState.EditorOf(const AWindow: INTAEditWindow): TWinControl;
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

function TStatusBarState.BarOf(AHost: TWinControl): TAtlasEditorStatusBar;
var
  Index: Integer;
begin
  for Index := 0 to FHosts.Count - 1 do
    if FHosts[Index] = AHost then
      Exit(FBars[Index]);
  Result := nil;
end;

function TStatusBarState.TopBar: TAtlasEditorStatusBar;
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

procedure TStatusBarState.EnsureBars;
var
  Services: INTAEditorServices;
  Index: Integer;
  Editor: TWinControl;
  Bar: TAtlasEditorStatusBar;
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
procedure TStatusBarState.CreateBar(AHost: TWinControl);
var
  Bar: TAtlasEditorStatusBar;
begin
  Bar := TAtlasEditorStatusBar.Create(nil);
  Bar.FreeNotification(FWatcher);
  FBars.Add(Bar);
  FHosts.Add(AHost);
  Bar.SetColors(BarColors);
  Bar.ItemCaptions := ItemCaptions;
  Bar.CustomizeCaption := TAtlasStrings.Text(TAtlasTextId.StatusBarCustomize);
  Bar.HideCaption := TAtlasStrings.Text(TAtlasTextId.StatusBarHide);
  Bar.OnStatus :=
    procedure(APoint: TPoint)
    var
      Corner: TPoint;
    begin
      Corner := APoint;
      TAtlasGuard.Log(LogPrefix + 'Klick auf Status');
      Later(
        procedure
        var
          Field: TAtlasStatusField;
        begin
          Field := nil;
          if Assigned(TAtlasIdeStatusBar.FHooks.Field) then
            Field := TAtlasIdeStatusBar.FHooks.Field();
          if Field <> nil then
            Field.OpenWindowAt(Corner);
        end);
    end;
  Bar.OnStatusContext :=
    procedure(APoint: TPoint)
    var
      Corner: TPoint;
    begin
      Corner := APoint;
      Later(
        procedure
        var
          Field: TAtlasStatusField;
        begin
          Field := nil;
          if Assigned(TAtlasIdeStatusBar.FHooks.Field) then
            Field := TAtlasIdeStatusBar.FHooks.Field();
          if Field <> nil then
            Field.ContextAt(Corner);
        end);
    end;
  Bar.OnBadge :=
    procedure(APoint: TPoint)
    var
      Corner: TPoint;
    begin
      Corner := APoint;
      TAtlasGuard.Log(LogPrefix + 'Klick auf Benachrichtigungen');
      Later(
        procedure
        var
          Field: TAtlasStatusField;
        begin
          Field := nil;
          if Assigned(TAtlasIdeStatusBar.FHooks.Field) then
            Field := TAtlasIdeStatusBar.FHooks.Field();
          if Field <> nil then
            Field.ClickBadge(Corner);
        end);
    end;
  Bar.OnFinding :=
    procedure(AKind: TAtlasFindingKind)
    var
      Kind: TAtlasFindingKind;
    begin
      Kind := AKind;
      TAtlasGuard.Log(LogPrefix + 'Klick auf Zähler ' + IntToStr(Ord(Kind)));
      Later(
        procedure
        begin
          JumpToFinding(Kind);
        end);
    end;
  Bar.OnFindingsOpen :=
    procedure
    begin
      Later(
        procedure
        begin
          TAtlasIdeProblems.ShowCurrentFile;
        end);
    end;
  Bar.OnLiveCheck :=
    procedure
    begin
      TAtlasGuard.Log(LogPrefix + 'Klick auf Live-Prüfung');
      Later(
        procedure
        begin
          Recheck;
        end);
    end;
  Bar.OnMethod :=
    procedure
    begin
      TAtlasGuard.Log(LogPrefix + 'Klick auf Methode');
      Later(
        procedure
        begin
          JumpToMethod;
        end);
    end;
  Bar.OnToggleItem :=
    procedure(const AId: string)
    var
      Id: string;
    begin
      Id := AId;
      Later(
        procedure
        begin
          ToggleItem(Id);
        end);
    end;
  Bar.OnHide :=
    procedure
    begin
      Later(
        procedure
        begin
          HideBar;
        end);
    end;
  Place(Bar, AHost);
end;

/// <summary>Ganz unten im Eltern-Steuerelement des Editors: unter einer Atlas-Suchleiste (alBottom ordnet nach
/// Top, größer steht weiter unten). Die Suchleiste kann später kommen; jeder Takt prüft die Reihenfolge.</summary>
procedure TStatusBarState.Place(ABar: TAtlasEditorStatusBar; AHost: TWinControl);
var
  Index: Integer;
  Control: TControl;
begin
  if ABar.Parent <> AHost then
  begin
    ABar.Parent := nil;
    ABar.Align := alNone;
    ABar.Top := AHost.ClientHeight;
    ABar.Align := alBottom;
    ABar.Parent := AHost;
    Exit;
  end;
  for Index := 0 to AHost.ControlCount - 1 do
  begin
    Control := AHost.Controls[Index];
    if (Control <> ABar) and Control.Visible and (Control.Align = alBottom) and (Control.Top > ABar.Top) then
    begin
      ABar.Top := AHost.ClientHeight + 1;
      Exit;
    end;
  end;
end;

procedure TStatusBarState.EnableBars;
var
  Bar: TAtlasEditorStatusBar;
begin
  for Bar in FBars do
    if not Bar.Enabled then
    begin
      Bar.Enabled := True;
      TAtlasGuard.Log(LogPrefix + 'wieder freigegeben, ein Editor ist aktiv');
    end;
end;

procedure TStatusBarState.ShowBars(AShown: Boolean);
var
  Bar: TAtlasEditorStatusBar;
begin
  for Bar in FBars do
    if Bar.Visible <> AShown then
      Bar.Visible := AShown;
end;

procedure TStatusBarState.StatusInto(var AView: TAtlasStatusBarView);
var
  Field: TAtlasStatusField;
  Text: string;
begin
  Field := nil;
  if Assigned(TAtlasIdeStatusBar.FHooks.Field) then
    Field := TAtlasIdeStatusBar.FHooks.Field();
  if Field = nil then
  begin
    AView.StatusText := TAtlasStatusSummary.FieldCaption;
    AView.StatusHint := '';
    AView.StatusColor := TAtlasStatusWindow.StateColor(TAtlasIdeStyle.Colors, TAtlasStatusState.Neutral);
    Exit;
  end;
  Text := Field.Text;
  if Text = '' then
    Text := TAtlasStatusSummary.FieldCaption;
  // Mehr Platz als in der Statuszeile: „Atlas · bereit“ statt nur „Atlas“.
  if (Field.State = TAtlasStatusState.Green) and SameText(Text, TAtlasStatusSummary.FieldCaption) then
    Text := Text + TAtlasStatusSummary.Separator + TAtlasStrings.Text(TAtlasTextId.StatusBarReady);
  AView.StatusText := Text;
  AView.StatusHint := Field.Tooltip + sLineBreak + TAtlasStrings.Text(TAtlasTextId.StatusBarStatusClicks);
  AView.StatusColor := TAtlasStatusWindow.StateColor(TAtlasIdeStyle.Colors, Field.State);
  // Plakette der Benachrichtigungen (#1234): Das umgezogene Feld ist 0 breit, die Leiste zeigt sie.
  AView.BadgeCount := Field.BadgeCount;
  AView.BadgeColor := TAtlasStatusWindow.StateColor(TAtlasIdeStyle.Colors, Field.BadgeState);
  AView.BadgeHint := Field.BadgeHint;
end;

function TStatusBarState.ViewFor(const AView: IOTAEditView; const AItems: TArray<string>): TAtlasStatusBarView;
var
  Settings: TAtlasPluginSettings;
  FileName: string;
  Line, Character: Integer;
  Problems: TArray<TAtlasProblem>;
  Check: TAtlasProblemsCheck;
  CheckedAt: TDateTime;
  Snapshot: TAtlasOutlineSnapshot;
  Metrics: TAtlasFileMetrics;
  Known: Boolean;
  Method: TAtlasStatusMethod;
  Checked, Total: Integer;
begin
  Result := Default(TAtlasStatusBarView);
  Checked := 0;
  Total := 0;
  Result.Items := AItems;
  Settings := TAtlasIdeSettings.Current;
  StatusInto(Result);
  FileName := '';
  if (AView <> nil) and (AView.Buffer <> nil) then
    FileName := AView.Buffer.FileName;
  if not CaretOf(AView, Line, Character) then
  begin
    Line := -1;
    Character := -1;
  end;
  if TAtlasStatusBarItems.Contains(AItems, TAtlasStatusBarItems.Findings) and ProblemsOn(Settings) then
  begin
    Result.FindingsShown := True;
    Problems := nil;
    if FileName <> '' then
      Problems := TAtlasProblemsController.Current.ForFile(FileName);
    Result.Counts := TAtlasStatusBarContent.CountsOf(Problems, Settings.ProblemsWindowCompiler);
    Result.FindingsHint := TAtlasStrings.Fmt(TAtlasTextId.StatusBarFindingsHint,
      [Result.Counts[TAtlasFindingKind.Error], Result.Counts[TAtlasFindingKind.Warning],
      Result.Counts[TAtlasFindingKind.Info]]);
  end;
  if TAtlasStatusBarItems.Contains(AItems, TAtlasStatusBarItems.LiveCheck) then
  begin
    Check := TAtlasProblemsController.LastCheck;
    CheckedAt := 0;
    if (FileName <> '') and SameText(Check.FileName, FileName) then
      CheckedAt := Check.At;
    Result.LiveBusy := ProblemsOn(Settings) and TAtlasProblemsController.Checking;
    Result.LiveText := TAtlasStatusBarContent.LiveText(Settings.ProblemsLive, Result.LiveBusy, CheckedAt, Now,
      LiveTexts);
    // Während des Debuggens ruht die Prüfung (#1241).
    if ProblemsOn(Settings) and TAtlasProblemsController.Paused then
    begin
      Result.LiveBusy := False;
      Result.LiveText := TAtlasStrings.Text(TAtlasTextId.StatusBarPausedDebugger);
    end
    else
    // Fortschritt der Projektprüfung (#1232), solange Units fehlen.
    if ProblemsOn(Settings) and TAtlasIdeProblems.ProjectProgress(Checked, Total) then
      Result.LiveText := Result.LiveText + TAtlasStatusBarContent.ProgressText(Checked, Total, LiveTexts);
    if Settings.ProblemsLive then
      Result.LiveHint := TAtlasStrings.Text(TAtlasTextId.StatusBarLiveOnHint)
    else
      Result.LiveHint := TAtlasStrings.Text(TAtlasTextId.StatusBarLiveOffHint);
    if ProblemsOn(Settings) then
      Result.LiveHint := Result.LiveHint + sLineBreak + TAtlasStrings.Text(TAtlasTextId.StatusBarRecheckClick);
    if Check.FileName <> '' then
      Result.LiveHint := Result.LiveHint + sLineBreak + TAtlasStrings.Fmt(TAtlasTextId.StatusBarLastCheck,
        [ExtractFileName(Check.FileName), Check.DurationMs, FormatDateTime('hh:nn:ss', Check.At)]);
    if Total > 0 then
      Result.LiveHint := Result.LiveHint + sLineBreak + TAtlasStrings.Fmt(TAtlasTextId.ProblemsStatusProject,
        [Checked, Total]);
  end;
  FMethodFile := '';
  FMethod := Default(TAtlasStatusMethod);
  if TAtlasStatusBarItems.Contains(AItems, TAtlasStatusBarItems.Method) then
  begin
    Method := Default(TAtlasStatusMethod);
    if (AView <> nil) and TAtlasIdeOutlineCache.IsPascal(FileName) then
    begin
      Snapshot := TAtlasIdeOutlineCache.Refresh(AView);
      if (Snapshot.Status = TAtlasOutlineStatus.Ready) and SameText(Snapshot.FileName, FileName) then
      begin
        Known := Assigned(TAtlasIdeStatusBar.FHooks.Metrics) and TAtlasIdeStatusBar.FHooks.Metrics(FileName,
          Metrics);
        if not Known then
          Metrics := Default(TAtlasFileMetrics);
        Method := TAtlasStatusBarContent.MethodAt(Snapshot.Nodes, Line, Metrics, Known);
      end;
    end;
    Result.MethodFound := Method.Found;
    if Method.Found then
    begin
      Result.MethodName := Method.Name;
      Result.MethodDetail := TAtlasStatusBarContent.MethodDetail(Method,
        TAtlasStrings.Text(TAtlasTextId.StatusBarLines), TAtlasStrings.Text(TAtlasTextId.StatusBarCyclomatic),
        TAtlasStatusSummary.Separator);
      Result.MethodOver := Method.Over;
      Result.MethodHint := Method.Name + sLineBreak + TAtlasStatusBarContent.MethodLimits(Method,
        TAtlasStrings.Text(TAtlasTextId.StatusBarLines), TAtlasStrings.Text(TAtlasTextId.StatusBarCyclomatic),
        TAtlasStrings.Text(TAtlasTextId.StatusBarLimit), TAtlasStatusSummary.Separator) + sLineBreak +
        TAtlasStrings.Text(TAtlasTextId.StatusBarMethodJump);
      FMethodFile := FileName;
      FMethod := Method;
    end
    else
      Result.MethodName := TAtlasStrings.Text(TAtlasTextId.StatusBarNoMethod);
  end;
end;

procedure TStatusBarState.Tick(Sender: TObject);
var
  On_: Boolean;
begin
  On_ := TAtlasIdeStatusBar.Enabled;
  if TAtlasGuard.Disabled(TAtlasFeature.StatusBar) then
  begin
    // Sicherung ausgelöst: Leisten weg, das Atlas-Feld zurück in die Statuszeile.
    if not FHidden then
    begin
      FHidden := True;
      TAtlasGuard.Log(LogPrefix + 'durch die Sicherung abgeschaltet');
      Want(False);
      try
        ShowBars(False);
      except
        on E: Exception do
          TAtlasGuard.Log(LogPrefix + 'nicht ausgeblendet: ' + TAtlasGuard.SafeMessage(E.Message));
      end;
      RefreshField;
    end;
    Exit;
  end;
  if FHidden then
  begin
    FHidden := False;
    ShowBars(True);
    RefreshField;
  end;
  if not On_ then
  begin
    Want(False);
    if FBars.Count > 0 then
      RemoveBars;
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.StatusBar,
    procedure
    var
      Items: TArray<string>;
      Top, Bar: TAtlasEditorStatusBar;
      View: TAtlasStatusBarView;
    begin
      Items := TAtlasStatusBarItems.Parse(TAtlasIdeSettings.Current.EditorStatusBarItems);
      Want(TAtlasStatusBarItems.Contains(Items, TAtlasStatusBarItems.Method));
      EnsureBars;
      if TAtlasEditorBuffer.ActiveView <> nil then
        EnableBars;
      Top := TopBar;
      for Bar in FBars do
      begin
        if Bar = Top then
          Continue;
        // Andere Fenster: nur Status und Belegung, der Rest bleibt vom letzten Mal, als sie oben waren.
        View := Bar.View;
        View.Items := Items;
        StatusInto(View);
        Bar.SetView(View);
      end;
      if Top <> nil then
        Top.SetView(ViewFor(TAtlasEditorBuffer.ActiveView, Items));
    end);
end;

/// <summary>Erst nach dem Klick ausführen; nur, wenn der Zustand dann noch lebt.</summary>
procedure TStatusBarState.Later(const AAction: TProc);
var
  Owner: TStatusBarState;
  Action: TProc;
begin
  Owner := Self;
  Action := AAction;
  TAtlasMainThread.ForceQueue(TAtlasFeature.StatusBar,
    procedure
    begin
      if TAtlasIdeStatusBar.FState <> Owner then
        Exit;
      TAtlasGuard.Run(TAtlasFeature.StatusBar, Action);
    end);
end;

procedure TStatusBarState.JumpToFinding(AKind: TAtlasFindingKind);
var
  View: IOTAEditView;
  Line, Character: Integer;
  Target: TAtlasProblem;
  FileName: string;
begin
  View := TAtlasEditorBuffer.ActiveView;
  if not CaretOf(View, Line, Character) or not ProblemsOn(TAtlasIdeSettings.Current) then
    Exit;
  FileName := View.Buffer.FileName;
  if not TAtlasStatusBarContent.NextOf(TAtlasProblemsController.Current.ForFile(FileName), AKind,
    TAtlasIdeSettings.Current.ProblemsWindowCompiler, Line, Character, Target) then
  begin
    TAtlasIdeStatusBar.Say(TAtlasStrings.Text(TAtlasTextId.StatusBarNoFindingOfKind));
    Exit;
  end;
  TAtlasIdeNavigation.GoToLocation(FileName, Target.StartLine, Target.StartCharacter);
end;

procedure TStatusBarState.JumpToMethod;
begin
  if (FMethodFile = '') or not FMethod.Found then
    Exit;
  TAtlasIdeNavigation.GoToLocation(FMethodFile, FMethod.Line, FMethod.Character);
end;

procedure TStatusBarState.Recheck;
begin
  // Der Server verwirft alle Ergebnis-Ids; geöffnete Units holt der Controller nach dem refresh neu, die übrigen
  // liefert workspace/diagnostic nach und nach.
  if not ProblemsOn(TAtlasIdeSettings.Current) or not Assigned(TAtlasIdeStatusBar.FHooks.Recheck) then
    Exit;
  TAtlasIdeStatusBar.Say(TAtlasStrings.Text(TAtlasTextId.StatusBarRechecking));
  TAtlasIdeStatusBar.FHooks.Recheck();
end;

procedure TStatusBarState.ToggleItem(const AId: string);
var
  Next: TAtlasPluginSettings;
begin
  Next := TAtlasIdeSettings.Stored;
  Next.EditorStatusBarItems := TAtlasStatusBarItems.Format(TAtlasStatusBarItems.Toggle(
    TAtlasStatusBarItems.Parse(Next.EditorStatusBarItems), AId));
  TAtlasIdeSettings.Update(Next);
  RefreshField;
end;

procedure TStatusBarState.HideBar;
var
  Next: TAtlasPluginSettings;
begin
  Next := TAtlasIdeSettings.Stored;
  Next.EditorStatusBar := False;
  TAtlasIdeSettings.Update(Next);
  RefreshField;
end;

{ TAtlasIdeStatusBar }

class procedure TAtlasIdeStatusBar.Say(const AText: string);
begin
  if Assigned(FHooks.Message) then
    FHooks.Message(AText);
end;

class function TAtlasIdeStatusBar.Enabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.EditorStatusBar;
end;

class procedure TAtlasIdeStatusBar.Install(const AHooks: THooks);
begin
  FreeAndNil(FState);
  FHooks := AHooks;
  FState := TStatusBarState.Create;
  State.Reset;
end;

class procedure TAtlasIdeStatusBar.Uninstall;
begin
  FreeAndNil(FState);
  FHooks := Default(THooks);
end;

class procedure TAtlasIdeStatusBar.ApplySettings;
begin
  if FState <> nil then
    State.Reset;
end;

class procedure TAtlasIdeStatusBar.ThemeChanged;
begin
  if FState <> nil then
    State.ApplyTheme;
end;

class function TAtlasIdeStatusBar.Anchor(out APoint: TPoint): Boolean;
var
  Bar: TAtlasEditorStatusBar;
  Area: TRect;
begin
  APoint := Point(0, 0);
  Result := False;
  if FState = nil then
    Exit;
  Bar := State.TopBar;
  if (Bar = nil) or not Bar.Visible or not Bar.HandleAllocated then
    Exit;
  Area := Bar.PartRect(TAtlasStatusBarPart.Status);
  if Area.IsEmpty then
    Exit;
  APoint := Bar.ClientToScreen(Point(Area.Left, Area.Top));
  Result := True;
end;

end.
