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
// - Mit eingeschalteten Benachrichtigungen steht immer eine Plakette mit der
//   Zahl der ungelesenen (auch 0) hinter dem Status (#1234, aus dem
//   Atlas-Feld, das dann 0 breit ist); Klick öffnet die Liste.
//   Dahinter stehen die Zusatzfelder des Atlas-Felds (z. B. „interface-Änderung“
//   der Unit-Beziehungen); ein Klick ruft dort ihren Klick, in der Statuszeile
//   stehen sie dann nicht.
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
  Atlas.IDE.Status.Field,
  Atlas.IDE.StatusBar.View;

type
  TAtlasIdeStatusBar = class
  public type
    THooks = record
      /// <summary>Atlas-Feld der Statuszeile; nil ohne.</summary>
      Field: TFunc<TAtlasStatusField>;
      /// <summary>Metriken aus atlas.server.metrics (Abruf in Atlas.IDE.Editor.MetricsSource, #66).</summary>
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
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.StatusBarItems,
  Atlas.Core.Style.Palette,
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
  Atlas.IDE.Problems.Controller,
  Atlas.IDE.Problems.Service,
  Atlas.IDE.Status.ServerWindow;

const
  TickMs = 250;
  LogPrefix = 'Atlas-Statusleiste: ';

type
  TFieldAction = reference to procedure(AField: TAtlasStatusField; const APoint: TPoint);

  TStatusBarState = class
  private
    FTimer: TTimer;
    FHost: TAtlasEditorBarHost;
    FWanted: Boolean;
    // Methode der obersten Leiste beim letzten Takt: Ziel des Klicks.
    FTarget: TAtlasStatusBarMethodTarget;
    procedure Tick(Sender: TObject);
    function CreateBar: TAtlasEditorStatusBar;
    /// <summary>Klicks auf Status (auch doppelt, Fenster „Atlas-Server“), Schnellschalter und Plakette.</summary>
    procedure WireStatus(ABar: TAtlasEditorStatusBar);
    /// <summary>Klicks auf Zähler, Live-Prüfung, Methode und das Menü „Leiste anpassen“.</summary>
    procedure WireItems(ABar: TAtlasEditorStatusBar);
    procedure Place(ABar: TAtlasEditorStatusBar; AHost: TWinControl);
    procedure Want(AOn: Boolean);
    procedure Later(const AAction: TProc);
    /// <summary>Klick auf ein Element des Atlas-Felds: AAction mit dem Feld nach dem Klick; ALog ins Protokoll.
    /// </summary>
    function FieldClick(const ALog: string; const AAction: TFieldAction): TProc<TPoint>;
    /// <summary>Klick auf ein Zusatzfeld: dessen Klick am Atlas-Feld nach dem Klick.</summary>
    function ExtraClick: TAtlasStatusBarExtraEvent;
    /// <summary>AAction nach dem Klick; ALog ('' = nichts) ins Protokoll.</summary>
    function Deferred(const ALog: string; const AAction: TProc): TProc;
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

function ItemCaptions: TArray<string>;
begin
  // Reihenfolge wie TAtlasStatusBarItems.All.
  Result := TArray<string>.Create(TAtlasStrings.Text(TAtlasTextId.StatusBarItemStatus),
    TAtlasStrings.Text(TAtlasTextId.StatusBarItemFindings), TAtlasStrings.Text(TAtlasTextId.StatusBarItemLiveCheck),
    TAtlasStrings.Text(TAtlasTextId.StatusBarItemMethod));
end;

/// <summary>Atlas-Feld der Statuszeile; nil ohne.</summary>
function CurrentField: TAtlasStatusField;
begin
  Result := nil;
  if Assigned(TAtlasIdeStatusBar.FHooks.Field) then
  begin
    Result := TAtlasIdeStatusBar.FHooks.Field();
  end;
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
  Field := CurrentField;
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
  Bar.Texts := TAtlasStatusBarTexts.Create(ItemCaptions,
    TAtlasStrings.Text(TAtlasTextId.StatusBarCustomize), TAtlasStrings.Text(TAtlasTextId.StatusBarHide));
  WireStatus(Bar);
  WireItems(Bar);
  Result := Bar;
end;

procedure TStatusBarState.WireStatus(ABar: TAtlasEditorStatusBar);
begin
  ABar.OnStatus := FieldClick('Klick auf Status',
    procedure(AField: TAtlasStatusField; const APoint: TPoint)
    begin
      AField.OpenWindowAt(APoint);
    end);
  ABar.OnStatusContext := FieldClick('',
    procedure(AField: TAtlasStatusField; const APoint: TPoint)
    begin
      AField.ContextAt(APoint);
    end);
  ABar.OnBadge := FieldClick('Klick auf Benachrichtigungen',
    procedure(AField: TAtlasStatusField; const APoint: TPoint)
    begin
      AField.ClickBadge(APoint);
    end);
  ABar.OnExtra := ExtraClick;
  ABar.OnStatusOpen :=
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
end;

procedure TStatusBarState.WireItems(ABar: TAtlasEditorStatusBar);
begin
  ABar.OnFinding :=
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
  ABar.OnFindingsOpen := Deferred('',
    procedure
    begin
      TAtlasIdeProblems.ShowCurrentFile;
    end);
  ABar.OnLiveCheck := Deferred('Klick auf Live-Prüfung',
    procedure
    begin
      Recheck;
    end);
  ABar.OnMethod := Deferred('Klick auf Methode',
    procedure
    begin
      JumpToMethod;
    end);
  ABar.OnToggleItem :=
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
  ABar.OnHide := Deferred('',
    procedure
    begin
      HideBar;
    end);
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
        TAtlasStatusBarViews.StatusInto(CurrentField, View);
        Bar.SetView(View);
      end;
      if Top <> nil then
      begin
        Top.SetView(TAtlasStatusBarViews.ViewFor(TAtlasEditorBuffer.ActiveView, Items, CurrentField,
          TAtlasIdeStatusBar.FHooks.Metrics, FTarget));
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

function TStatusBarState.FieldClick(const ALog: string; const AAction: TFieldAction): TProc<TPoint>;
var
  mOwner: TStatusBarState;
  mLog: string;
  mAction: TFieldAction;
begin
  mOwner := Self;
  mLog := ALog;
  mAction := AAction;
  Result :=
    procedure(APoint: TPoint)
    var
      mCorner: TPoint;
    begin
      mCorner := APoint;
      if mLog <> '' then
      begin
        TAtlasGuard.Log(LogPrefix + mLog);
      end;
      mOwner.Later(
        procedure
        var
          mField: TAtlasStatusField;
        begin
          mField := CurrentField;
          if mField <> nil then
          begin
            mAction(mField, mCorner);
          end;
        end);
    end;
end;

function TStatusBarState.ExtraClick: TAtlasStatusBarExtraEvent;
var
  mOwner: TStatusBarState;
begin
  mOwner := Self;
  Result :=
    procedure(const AId: string; const APoint: TPoint)
    var
      mId: string;
      mClick: TProc<TPoint>;
    begin
      mId := AId;
      TAtlasGuard.Log(LogPrefix + 'Klick auf Zusatzfeld ' + mId);
      mClick := mOwner.FieldClick('',
        procedure(AField: TAtlasStatusField; const ACorner: TPoint)
        begin
          AField.ClickExtra(mId, ACorner);
        end);
      mClick(APoint);
    end;
end;

function TStatusBarState.Deferred(const ALog: string; const AAction: TProc): TProc;
var
  mOwner: TStatusBarState;
  mLog: string;
  mAction: TProc;
begin
  mOwner := Self;
  mLog := ALog;
  mAction := AAction;
  Result :=
    procedure
    begin
      if mLog <> '' then
      begin
        TAtlasGuard.Log(LogPrefix + mLog);
      end;
      mOwner.Later(mAction);
    end;
end;

procedure TStatusBarState.JumpToFinding(AKind: TAtlasFindingKind);
var
  View: IOTAEditView;
  Line, Character: Integer;
  Target: TAtlasProblem;
  FileName: string;
begin
  View := TAtlasEditorBuffer.ActiveView;
  if not TAtlasStatusBarViews.CaretOf(View, Line, Character) or
    not TAtlasStatusBarViews.ProblemsOn(TAtlasIdeSettings.Current) then
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
  if (FTarget.FileName = '') or not FTarget.Method.Found then
  begin
    Exit;
  end;
  TAtlasIdeNavigation.GoToLocation(FTarget.FileName, FTarget.Method.Line, FTarget.Method.Character);
end;

procedure TStatusBarState.Recheck;
begin
  // Der Server verwirft alle Ergebnis-Ids; geöffnete Units holt der Controller nach dem refresh neu, die übrigen
  // liefert workspace/diagnostic nach und nach.
  if not TAtlasStatusBarViews.ProblemsOn(TAtlasIdeSettings.Current) then
  begin
    Exit;
  end;
  // Ohne Live-Prüfung prüft der Klick nur die offene Datei: Wer selbst bestimmt, wann geprüft wird, will nicht alle
  // Units neu prüfen lassen.
  if TAtlasStatusBarContent.ClickChecksFile(TAtlasIdeProblems.UpdateMode) then
  begin
    TAtlasIdeProblems.CheckFileNow;
    Exit;
  end;
  if not Assigned(TAtlasIdeStatusBar.FHooks.Recheck) then
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
