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
//   Doppelklick auf den Status öffnet das Fenster „Atlas-Server“ (#1356,
//   nur mit server.statusWindow).
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
// - Anlegen je Editorfenster, Wächter, Freigabe nach der Sperre durch die
//   IDE, Protokoll des Sperrenden und Abbau übernimmt TAtlasEditorBarHost
//   (#1248); hier stehen nur Einordnen (Place) und Inhalt.
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
  Atlas.UI.StatusBar.Bar,
  Atlas.IDE.Foundation.EditorBarHost,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Outline.Cache,
  Atlas.IDE.Problems.Controller,
  Atlas.IDE.Problems.Service,
  Atlas.IDE.Status.ServerWindow;

const
  TickMs = 250;
  LogPrefix = 'Atlas-Statusleiste: ';

type
  TStatusBarState = class
  private
    FTimer: TTimer;
    FHost: TAtlasEditorBarHost;
    FWanted: Boolean;
    // Methode der obersten Leiste beim letzten Takt: Ziel des Klicks.
    FMethodFile: string;
    FMethod: TAtlasStatusMethod;
    procedure Tick(Sender: TObject);
    function CreateBar: TAtlasEditorStatusBar;
    procedure Place(ABar: TAtlasEditorStatusBar; AHost: TWinControl);
    procedure Want(AOn: Boolean);
    procedure StatusInto(var AView: TAtlasStatusBarView);
    function ViewFor(const AView: IOTAEditView; const AItems: TArray<string>): TAtlasStatusBarView;
    procedure Later(const AAction: TProc);
    procedure RefreshField;
  public
    constructor Create;
    destructor Destroy; override;
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
  begin
    Result := TAtlasIdeStyle.ChromeColors;
  end
  else
  begin
    Result := TAtlasIdeStyle.Colors;
  end;
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
  Result.ProjectDone := TAtlasStrings.Text(TAtlasTextId.StatusBarProjectDone);
  Result.ProjectPaused := TAtlasStrings.Text(TAtlasTextId.StatusBarProjectPaused);
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
  begin
    Exit;
  end;
  Cursor := AView.CursorPos;
  if Cursor.Line < 1 then
  begin
    Exit;
  end;
  ALine := Cursor.Line - 1;
  ACharacter := TLspSession.ColumnToIndex(TAtlasEditorBuffer.LineText(AView, Cursor.Line), Cursor.Col,
    TAtlasEditorBuffer.TabWidth(AView.Buffer));
  Result := True;
end;

{ TStatusBarState }

constructor TStatusBarState.Create;
begin
  inherited Create;
  FHost := TAtlasEditorBarHost.Create('Atlas-Statusleiste', TAtlasFeature.StatusBar,
    function(AEditorParent: TWinControl): TControl
    begin
      Result := CreateBar;
    end,
    procedure(ABar: TControl; AEditorParent: TWinControl)
    begin
      Place(TAtlasEditorStatusBar(ABar), AEditorParent);
    end);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := TickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TStatusBarState.Destroy;
begin
  FTimer.Free;
  Want(False);
  FHost.Free;
  inherited Destroy;
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
  begin
    Field := TAtlasIdeStatusBar.FHooks.Field();
  end;
  if Field <> nil then
  begin
    Field.RequestRefresh;
  end;
end;

procedure TStatusBarState.ApplyTheme;
var
  Colors: TAtlasColors;
begin
  Colors := BarColors;
  FHost.ForEach(
    procedure(ABar: TControl)
    begin
      TAtlasEditorStatusBar(ABar).SetColors(Colors);
    end);
end;

procedure TStatusBarState.Want(AOn: Boolean);
begin
  if AOn = FWanted then
  begin
    Exit;
  end;
  FWanted := AOn;
  if Assigned(TAtlasIdeStatusBar.FHooks.WantMetrics) then
  begin
    TAtlasIdeStatusBar.FHooks.WantMetrics(AOn);
  end;
end;

function TStatusBarState.TopBar: TAtlasEditorStatusBar;
begin
  Result := TAtlasEditorStatusBar(FHost.ActiveBar);
end;

/// <summary>Eigene Methode: Jede Leiste braucht ihre eigene gefangene Variable. Einordnen und Wächter: Host.</summary>
function TStatusBarState.CreateBar: TAtlasEditorStatusBar;
var
  Bar: TAtlasEditorStatusBar;
  Host: TAtlasEditorBarHost;
begin
  Bar := TAtlasEditorStatusBar.Create(nil);
  Host := FHost;
  Bar.SetColors(BarColors);
  Bar.OnDisabled :=
    procedure(ASender: TObject)
    begin
      Host.Disabled(ASender);
    end;
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
          begin
            Field := TAtlasIdeStatusBar.FHooks.Field();
          end;
          if Field <> nil then
          begin
            Field.OpenWindowAt(Corner);
          end;
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
          begin
            Field := TAtlasIdeStatusBar.FHooks.Field();
          end;
          if Field <> nil then
          begin
            Field.ContextAt(Corner);
          end;
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
          begin
            Field := TAtlasIdeStatusBar.FHooks.Field();
          end;
          if Field <> nil then
          begin
            Field.ClickBadge(Corner);
          end;
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
  Bar.OnStatusOpen :=
    procedure
    begin
      // Fenster „Atlas-Server“ (#1356); mit server.statusWindow aus tut der Doppelklick nichts.
      if not TAtlasIdeServerWindow.Enabled then
      begin
        Exit;
      end;
      TAtlasGuard.Log(LogPrefix + 'Doppelklick auf Status');
      Later(
        procedure
        begin
          TAtlasIdeServerWindow.Show;
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
  Result := Bar;
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

procedure TStatusBarState.StatusInto(var AView: TAtlasStatusBarView);
var
  Field: TAtlasStatusField;
  Text: string;
begin
  Field := nil;
  if Assigned(TAtlasIdeStatusBar.FHooks.Field) then
  begin
    Field := TAtlasIdeStatusBar.FHooks.Field();
  end;
  if Field = nil then
  begin
    AView.StatusText := TAtlasStatusSummary.FieldCaption;
    AView.StatusHint := '';
    AView.StatusState := TAtlasStatusState.Neutral;
    Exit;
  end;
  Text := Field.Text;
  if Text = '' then
  begin
    Text := TAtlasStatusSummary.FieldCaption;
  end;
  // Mehr Platz als in der Statuszeile: „Atlas · bereit“ statt nur „Atlas“.
  if (Field.State = TAtlasStatusState.Green) and SameText(Text, TAtlasStatusSummary.FieldCaption) then
  begin
    Text := Text + TAtlasStatusSummary.Separator + TAtlasStrings.Text(TAtlasTextId.StatusBarReady);
  end;
  AView.StatusText := Text;
  AView.StatusHint := Field.Tooltip + sLineBreak + TAtlasStrings.Text(TAtlasTextId.StatusBarStatusClicks);
  if TAtlasIdeServerWindow.Enabled then
  begin
    AView.StatusHint := AView.StatusHint + sLineBreak + TAtlasStrings.Text(TAtlasTextId.StatusBarStatusServer);
  end;
  AView.StatusState := Field.State;
  // Plakette der Benachrichtigungen (#1234): Das umgezogene Feld ist 0 breit, die Leiste zeigt sie.
  AView.BadgeCount := Field.BadgeCount;
  AView.BadgeState := Field.BadgeState;
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
  Run: TLspWorkspaceRun;
  FinishedAgo: UInt64;
begin
  Result := Default(TAtlasStatusBarView);
  Checked := 0;
  Total := 0;
  Result.Items := AItems;
  Settings := TAtlasIdeSettings.Current;
  StatusInto(Result);
  FileName := '';
  if (AView <> nil) and (AView.Buffer <> nil) then
  begin
    FileName := AView.Buffer.FileName;
  end;
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
    begin
      Problems := TAtlasProblemsController.Current.ForFile(FileName);
    end;
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
    begin
      CheckedAt := Check.At;
    end;
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
    // Lauf der Projektprüfung des Servers (#1247): Fortschritt, Pause beim Kompilieren, danach „fertig“.
    if ProblemsOn(Settings) and TAtlasProblemsController.ProjectRun(Run, FinishedAgo) then
    begin
      Checked := Run.Done;
      Total := Run.Total;
      Result.LiveText := Result.LiveText + TAtlasStatusBarContent.RunText(Run.Active, Run.Done, Run.Total,
        Run.Paused, FinishedAgo, LiveTexts);
    end
    else
    // Ältere Server ohne Laufstand: Fortschritt aus den Befunden (#1232), solange Units fehlen.
    if ProblemsOn(Settings) and TAtlasIdeProblems.ProjectProgress(Checked, Total) then
    begin
      Result.LiveText := Result.LiveText + TAtlasStatusBarContent.ProgressText(Checked, Total, LiveTexts);
    end;
    if Settings.ProblemsLive then
    begin
      Result.LiveHint := TAtlasStrings.Text(TAtlasTextId.StatusBarLiveOnHint);
    end
    else
    begin
      Result.LiveHint := TAtlasStrings.Text(TAtlasTextId.StatusBarLiveOffHint);
    end;
    if ProblemsOn(Settings) then
    begin
      Result.LiveHint := Result.LiveHint + sLineBreak + TAtlasStrings.Text(TAtlasTextId.StatusBarRecheckClick);
    end;
    if Check.FileName <> '' then
    begin
      Result.LiveHint := Result.LiveHint + sLineBreak + TAtlasStrings.Fmt(TAtlasTextId.StatusBarLastCheck,
        [ExtractFileName(Check.FileName), Check.DurationMs, FormatDateTime('hh:nn:ss', Check.At)]);
    end;
    if Total > 0 then
    begin
      Result.LiveHint := Result.LiveHint + sLineBreak + TAtlasStrings.Fmt(TAtlasTextId.ProblemsStatusProject,
        [Checked, Total]);
    end;
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
        begin
          Metrics := Default(TAtlasFileMetrics);
        end;
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
    begin
      Result.MethodName := TAtlasStrings.Text(TAtlasTextId.StatusBarNoMethod);
    end;
  end;
end;

procedure TStatusBarState.Tick(Sender: TObject);
var
  On_, WasHidden: Boolean;
begin
  On_ := TAtlasIdeStatusBar.Enabled;
  WasHidden := FHost.Hidden;
  if not FHost.Guard then
  begin
    // Sicherung ausgelöst: Leisten weg (Host), das Atlas-Feld zurück in die Statuszeile.
    if not WasHidden then
    begin
      Want(False);
      RefreshField;
    end;
    Exit;
  end;
  if WasHidden then
  begin
    RefreshField;
  end;
  if not On_ then
  begin
    Want(False);
    if FHost.Count > 0 then
    begin
      FHost.Clear;
    end;
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.StatusBar,
    procedure
    var
      Items: TArray<string>;
      Top, Bar: TAtlasEditorStatusBar;
      Control: TControl;
      View: TAtlasStatusBarView;
    begin
      Items := TAtlasStatusBarItems.Parse(TAtlasIdeSettings.Current.EditorStatusBarItems);
      Want(TAtlasStatusBarItems.Contains(Items, TAtlasStatusBarItems.Method));
      // Ensure gibt auch die von der IDE gesperrten Leisten frei, sobald ein Editor aktiv ist.
      FHost.Ensure;
      Top := TopBar;
      for Control in FHost.Bars do
      begin
        Bar := TAtlasEditorStatusBar(Control);
        if Bar = Top then
        begin
          Continue;
        end;
        // Andere Fenster: nur Status und Belegung, der Rest bleibt vom letzten Mal, als sie oben waren.
        View := Bar.View;
        View.Items := Items;
        StatusInto(View);
        Bar.SetView(View);
      end;
      if Top <> nil then
      begin
        Top.SetView(ViewFor(TAtlasEditorBuffer.ActiveView, Items));
      end;
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
      begin
        Exit;
      end;
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
  begin
    Exit;
  end;
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
  begin
    Exit;
  end;
  TAtlasIdeNavigation.GoToLocation(FMethodFile, FMethod.Line, FMethod.Character);
end;

procedure TStatusBarState.Recheck;
begin
  // Der Server verwirft alle Ergebnis-Ids; geöffnete Units holt der Controller nach dem refresh neu, die übrigen
  // liefert workspace/diagnostic nach und nach.
  if not ProblemsOn(TAtlasIdeSettings.Current) or not Assigned(TAtlasIdeStatusBar.FHooks.Recheck) then
  begin
    Exit;
  end;
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
  begin
    FHooks.Message(AText);
  end;
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
  begin
    State.Reset;
  end;
end;

class procedure TAtlasIdeStatusBar.ThemeChanged;
begin
  if FState <> nil then
  begin
    State.ApplyTheme;
  end;
end;

class function TAtlasIdeStatusBar.Anchor(out APoint: TPoint): Boolean;
var
  Bar: TAtlasEditorStatusBar;
  Area: TRect;
begin
  APoint := Point(0, 0);
  Result := False;
  if FState = nil then
  begin
    Exit;
  end;
  Bar := State.TopBar;
  if (Bar = nil) or not Bar.Visible or not Bar.HandleAllocated then
  begin
    Exit;
  end;
  Area := Bar.PartRect(TAtlasStatusBarPart.Status);
  if Area.IsEmpty then
  begin
    Exit;
  end;
  APoint := Bar.ClientToScreen(Point(Area.Left, Area.Top));
  Result := True;
end;

end.
