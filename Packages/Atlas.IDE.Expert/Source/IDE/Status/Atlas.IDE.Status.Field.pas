unit Atlas.IDE.Status.Field;

// Atlas-Feld in der Statusleiste jedes Editorfensters (#591, ersetzt das
// Indexfeld aus #492): „Atlas“ mit farbigem Punkt (Gesamtzustand der
// Registry), mit statusField.showSummary der Kurztext der wichtigsten gelben
// oder roten Zeile („Atlas · Index 45 %“). Tooltip: alle Zeilen, die nicht
// grün sind. Ein Klick öffnet TAtlasStatusWindow über dem Feld.
// - Das Feld ist ein selbst gezeichnetes Panel rechts neben denen der IDE
//   (INTAEditWindow.StatusBar). OnDrawPanel, OnMouseUp, OnMouseMove und
//   WindowProc der Leiste werden verkettet und beim Entladen zurückgesetzt;
//   geschlossene Fenster meldet FreeNotification.
// - Aktualisierung nur auf Ereignisse: Änderungen der Registry (aus jedem
//   Thread) und neue oder aktivierte Editorfenster. Sie werden gesammelt;
//   gezeichnet wird höchstens alle 250 ms im Hauptthread.
// - OnRefresh läuft vor jedem Zeichnen im Hauptthread (feste Zeilen nachführen).
// - Rechtsklick auf das Feld ruft OnContext mit der linken Oberkante des Felds
//   (Schnellschalter, #604); Anchor liefert sie für das oberste Editorfenster.
//   Die rechte Maustaste wird in WindowProc abgefangen, nicht in OnMouseUp:
//   Sonst erzeugt die Standardbehandlung von WM_RBUTTONUP vorher
//   WM_CONTEXTMENU, das an das Editorfenster der IDE weitergeht; dessen Menü
//   bzw. Fokuswechsel schloss die Schnellschalter sofort wieder. Über dem
//   Feld schluckt Atlas WM_RBUTTONDOWN, WM_RBUTTONUP und WM_CONTEXTMENU und
//   öffnet die Schnellschalter erst nach der Mausnachricht (PostMessage).
// - StatusFieldToggles wählt, ob Rechtsklick, Doppelklick oder beide (Vorgabe)
//   die Schnellschalter öffnen; eine nicht gewählte Geste bleibt bei der IDE
//   bzw. beim einfachen Klick. Beim Doppelklick schließt sich das vom ersten
//   Klick geöffnete Statusfenster; das Loslassen danach öffnet es nicht erneut.
// - Links steht das Atlas-Symbol (#751) in der Variante zum IDE-Thema und in
//   der Größe zur Pixeldichte der Leiste, dann Punkt und Text.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  Winapi.CommCtrl,
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Status.Contract,
  Atlas.UI.Status.Window;

type
  TAtlasStatusField = class(TComponent)
  public const
    RedrawMs = 250;
  private type
    THook = class
    public
      Field: TAtlasStatusField;
      Bar: TStatusBar;
      Panel: TStatusPanel;
      OldDraw: TDrawPanelEvent;
      OldMouseUp: TMouseEvent;
      OldMouseMove: TMouseMoveEvent;
      OldWndProc: TWndMethod;
      OldHint: string;
      OldShowHint: Boolean;
      InPanel: Boolean;
      /// <summary>Das Loslassen nach einem Doppelklick auf das Feld nicht als Klick werten.</summary>
      SkipUp: Boolean;
      procedure WndProc(var Message: TMessage);
    end;
  private
    FRegistry: IAtlasStatusRegistry;
    FListener: Integer;
    FHooks: TObjectList<THook>;
    // Haken geschlossener Leisten: erst mit dem Feld freigeben, die Leiste ruft im Abbau noch WindowProc auf.
    FDead: TObjectList<THook>;
    FWnd: HWND;
    FPosted: Integer;
    FTimer: TTimer;
    FWindow: TAtlasStatusWindow;
    FNotifierIndex: Integer;
    FItems: TArray<IAtlasStatusItem>;
    FText: string;
    FTooltip: string;
    FState: TAtlasStatusState;
    FOnRefresh: TProc;
    FOnOpenLog: TProc;
    FOnRestart: TProc;
    FOnContext: TProc<TPoint>;
    procedure WndProc(var Message: TMessage);
    procedure TimerTick(Sender: TObject);
    procedure Refresh;
    function HookOf(ABar: TStatusBar): THook;
    procedure HookBar(ABar: TStatusBar);
    procedure Unhook(AHook: THook; ARestore: Boolean);
    procedure UnhookAll;
    function PanelRect(AHook: THook): TRect;
    procedure DrawPanel(StatusBar: TStatusBar; Panel: TStatusPanel; const Rect: TRect);
    procedure BarMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure BarMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure BarMessage(AHook: THook; var Message: TMessage);
    procedure OpenWindow(AHook: THook);
    procedure OpenContext(AHook: THook);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(const ARegistry: IAtlasStatusRegistry); reintroduce;
    destructor Destroy; override;
    /// <summary>Neu zeichnen anfordern; aus jedem Thread, gesammelt auf höchstens alle 250 ms.</summary>
    procedure RequestRefresh;
    /// <summary>Vor jedem Zeichnen im Hauptthread.</summary>
    property OnRefresh: TProc read FOnRefresh write FOnRefresh;
    property OnOpenLog: TProc read FOnOpenLog write FOnOpenLog;
    property OnRestart: TProc read FOnRestart write FOnRestart;
    /// <summary>Rechtsklick und Doppelklick auf das Feld; Punkt = linke Oberkante des Felds (Bildschirm).</summary>
    property OnContext: TProc<TPoint> read FOnContext write FOnContext;
    /// <summary>Linke Oberkante des Felds im obersten Editorfenster (Bildschirm); False ohne Feld.</summary>
    function Anchor(out APoint: TPoint): Boolean;
  end;

implementation

uses
  Vcl.Forms,
  Vcl.Graphics,
  Vcl.Themes,
  DockForm,
  ToolsAPI,
  Atlas.Core.Status.Registry,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Settings.Store,
  Atlas.IDE.Editor.Style,
  Atlas.Core.Style.Symbol,
  Atlas.UI.Style.Symbol,
  Atlas.IDE.Style.Symbol;

const
  WM_ATLAS_STATUS = WM_USER + 591;
  // LParam = TStatusBar; erst nach der Mausnachricht ausgeführt, ein freigegebenes Feld verwirft sie mit seinem Fenster.
  WM_ATLAS_STATUS_CONTEXT = WM_USER + 592;

type
  TFieldNotifier = class(TNotifierObject, INTAEditServicesNotifier)
  private
    FField: TAtlasStatusField;
  public
    constructor Create(AField: TAtlasStatusField);
    procedure WindowShow(const EditWindow: INTAEditWindow; Show, LoadedFromDesktop: Boolean);
    procedure WindowNotification(const EditWindow: INTAEditWindow; Operation: TOperation);
    procedure WindowActivated(const EditWindow: INTAEditWindow);
    procedure WindowCommand(const EditWindow: INTAEditWindow; Command, Param: Integer; var Handled: Boolean);
    procedure EditorViewActivated(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
    procedure EditorViewModified(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
    procedure DockFormVisibleChanged(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
    procedure DockFormUpdated(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
    procedure DockFormRefresh(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
  end;

{ TFieldNotifier }

constructor TFieldNotifier.Create(AField: TAtlasStatusField);
begin
  inherited Create;
  FField := AField;
end;

procedure TFieldNotifier.WindowShow(const EditWindow: INTAEditWindow; Show, LoadedFromDesktop: Boolean);
begin
  FField.RequestRefresh;
end;

procedure TFieldNotifier.WindowNotification(const EditWindow: INTAEditWindow; Operation: TOperation);
begin
  FField.RequestRefresh;
end;

procedure TFieldNotifier.WindowActivated(const EditWindow: INTAEditWindow);
begin
  FField.RequestRefresh;
end;

procedure TFieldNotifier.WindowCommand(const EditWindow: INTAEditWindow; Command, Param: Integer;
  var Handled: Boolean);
begin
end;

procedure TFieldNotifier.EditorViewActivated(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
begin
  // Aktive Datei gewechselt: Zeile „Datei“ nachführen.
  FField.RequestRefresh;
end;

procedure TFieldNotifier.EditorViewModified(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
begin
end;

procedure TFieldNotifier.DockFormVisibleChanged(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

procedure TFieldNotifier.DockFormUpdated(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

procedure TFieldNotifier.DockFormRefresh(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

{ TAtlasStatusField }

constructor TAtlasStatusField.Create(const ARegistry: IAtlasStatusRegistry);
var
  Editor: IOTAEditorServices;
begin
  inherited Create(nil);
  FRegistry := ARegistry;
  FHooks := TObjectList<THook>.Create(True);
  FDead := TObjectList<THook>.Create(True);
  FNotifierIndex := -1;
  FWnd := AllocateHWnd(WndProc);
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := RedrawMs;
  FTimer.OnTimer := TimerTick;
  FListener := FRegistry.AddListener(
    procedure
    begin
      RequestRefresh;
    end);
  if Supports(BorlandIDEServices, IOTAEditorServices, Editor) then
    FNotifierIndex := Editor.AddNotifier(TFieldNotifier.Create(Self));
  RequestRefresh;
end;

destructor TAtlasStatusField.Destroy;
var
  Editor: IOTAEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  FRegistry.RemoveListener(FListener);
  if (FNotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAEditorServices, Editor) then
    Editor.RemoveNotifier(FNotifierIndex);
  FreeAndNil(FTimer);
  if FWnd <> 0 then
    DeallocateHWnd(FWnd);
  FWnd := 0;
  if FWindow <> nil then
  begin
    FWindow.RemoveFreeNotification(Self);
    FreeAndNil(FWindow);
  end;
  try
    UnhookAll;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Status, E);
  end;
  FreeAndNil(FHooks);
  FreeAndNil(FDead);
  inherited;
end;

procedure TAtlasStatusField.RequestRefresh;
begin
  // Nur eine Nachricht unterwegs; der Zeitgeber fasst alles in 250 ms zusammen.
  if (FWnd <> 0) and (AtomicExchange(FPosted, 1) = 0) then
    PostMessage(FWnd, WM_ATLAS_STATUS, 0, 0);
end;

procedure TAtlasStatusField.WndProc(var Message: TMessage);
var
  Hook: THook;
begin
  if Message.Msg = WM_ATLAS_STATUS then
  begin
    if (FTimer <> nil) and not FTimer.Enabled then
      FTimer.Enabled := True;
    Message.Result := 0;
  end
  else if Message.Msg = WM_ATLAS_STATUS_CONTEXT then
  begin
    // Die Leiste kann inzwischen geschlossen sein: nur bekannte Leisten.
    Hook := HookOf(TStatusBar(Message.LParam));
    if Hook <> nil then
      TAtlasGuard.Run(TAtlasFeature.Status,
        procedure
        begin
          OpenContext(Hook);
        end);
    Message.Result := 0;
  end
  else
    Message.Result := DefWindowProc(FWnd, Message.Msg, Message.WParam, Message.LParam);
end;

procedure TAtlasStatusField.TimerTick(Sender: TObject);
begin
  FTimer.Enabled := False;
  AtomicExchange(FPosted, 0);
  TAtlasGuard.Run(TAtlasFeature.Status, Refresh);
end;

procedure TAtlasStatusField.Notification(AComponent: TComponent; Operation: TOperation);
var
  Index: Integer;
begin
  inherited;
  if Operation <> opRemove then
    Exit;
  if AComponent = FWindow then
    FWindow := nil;
  if FHooks = nil then
    Exit;
  for Index := FHooks.Count - 1 downto 0 do
    if FHooks[Index].Bar = AComponent then
    begin
      FHooks[Index].Field := nil;
      FDead.Add(FHooks.Extract(FHooks[Index]));
    end;
end;

function TAtlasStatusField.HookOf(ABar: TStatusBar): THook;
var
  Hook: THook;
begin
  for Hook in FHooks do
    if Hook.Bar = ABar then
      Exit(Hook);
  Result := nil;
end;

procedure TAtlasStatusField.HookBar(ABar: TStatusBar);
var
  Hook: THook;
begin
  if (ABar = nil) or (HookOf(ABar) <> nil) then
    Exit;
  Hook := THook.Create;
  Hook.Field := Self;
  Hook.Bar := ABar;
  Hook.OldDraw := ABar.OnDrawPanel;
  Hook.OldMouseUp := ABar.OnMouseUp;
  Hook.OldMouseMove := ABar.OnMouseMove;
  Hook.OldHint := ABar.Hint;
  Hook.OldShowHint := ABar.ShowHint;
  Hook.Panel := ABar.Panels.Add;
  Hook.Panel.Style := psOwnerDraw;
  Hook.Panel.Bevel := pbNone;
  ABar.OnDrawPanel := DrawPanel;
  ABar.OnMouseUp := BarMouseUp;
  ABar.OnMouseMove := BarMouseMove;
  Hook.OldWndProc := ABar.WindowProc;
  ABar.WindowProc := Hook.WndProc;
  FHooks.Add(Hook);
  ABar.FreeNotification(Self);
end;

function SameMethod(const ALeft, ARight: TMethod): Boolean;
begin
  Result := (ALeft.Code = ARight.Code) and (ALeft.Data = ARight.Data);
end;

procedure TAtlasStatusField.Unhook(AHook: THook; ARestore: Boolean);
var
  Bar: TStatusBar;
  Draw, CurrentDraw: TDrawPanelEvent;
  MouseUp, CurrentUp: TMouseEvent;
  MouseMove, CurrentMove: TMouseMoveEvent;
  WndProc_, CurrentWndProc: TWndMethod;
begin
  Bar := AHook.Bar;
  if not ARestore or (Bar = nil) then
    Exit;
  // Fremde WindowProc darüber: Unsere bleibt in deren Kette und reicht ab jetzt nur noch durch.
  WndProc_ := AHook.WndProc;
  CurrentWndProc := Bar.WindowProc;
  if SameMethod(TMethod(CurrentWndProc), TMethod(WndProc_)) then
    Bar.WindowProc := AHook.OldWndProc
  else
    AHook.Field := nil;
  Bar.RemoveFreeNotification(Self);
  // Nur zurücksetzen, was noch unser ist: Eine andere Erweiterung kann sich danach eingehängt haben.
  Draw := DrawPanel;
  CurrentDraw := Bar.OnDrawPanel;
  if SameMethod(TMethod(CurrentDraw), TMethod(Draw)) then
    Bar.OnDrawPanel := AHook.OldDraw;
  MouseUp := BarMouseUp;
  CurrentUp := Bar.OnMouseUp;
  if SameMethod(TMethod(CurrentUp), TMethod(MouseUp)) then
    Bar.OnMouseUp := AHook.OldMouseUp;
  MouseMove := BarMouseMove;
  CurrentMove := Bar.OnMouseMove;
  if SameMethod(TMethod(CurrentMove), TMethod(MouseMove)) then
    Bar.OnMouseMove := AHook.OldMouseMove;
  if AHook.InPanel then
  begin
    Bar.Hint := AHook.OldHint;
    Bar.ShowHint := AHook.OldShowHint;
  end;
  if (AHook.Panel <> nil) and (AHook.Panel.Index < Bar.Panels.Count) and
    (Bar.Panels[AHook.Panel.Index] = AHook.Panel) then
    Bar.Panels.Delete(AHook.Panel.Index);
end;

procedure TAtlasStatusField.UnhookAll;
var
  Hook: THook;
  Index: Integer;
begin
  for Hook in FHooks do
    Unhook(Hook, True);
  // Noch in einer fremden Kette: nicht freigeben, die Leiste ruft seine WndProc weiter auf.
  for Index := FHooks.Count - 1 downto 0 do
    if FHooks[Index].Field = nil then
      FHooks.Extract(FHooks[Index]);
  FHooks.Clear;
end;

{ TAtlasStatusField.THook }

procedure TAtlasStatusField.THook.WndProc(var Message: TMessage);
begin
  if Field <> nil then
    Field.BarMessage(Self, Message)
  else
    OldWndProc(Message);
end;

function TAtlasStatusField.PanelRect(AHook: THook): TRect;
begin
  Result := Rect(0, 0, 0, 0);
  if (AHook.Panel = nil) or not AHook.Bar.HandleAllocated then
    Exit;
  SendMessage(AHook.Bar.Handle, SB_GETRECT, AHook.Panel.Index, LPARAM(@Result));
end;

/// <summary>Platz für das Symbol samt Abstand in Gerätepixeln.</summary>
function SymbolWidth(APPI: Integer): Integer;
begin
  Result := TAtlasSymbol.PixelSize(TAtlasSymbol.MenuSize + 4, APPI);
end;

procedure TAtlasStatusField.Refresh;
var
  Settings: TAtlasPluginSettings;
  Services: INTAEditorServices;
  Index, Width_: Integer;
  Window: INTAEditWindow;
  Hook: THook;
  Bars: TList<TStatusBar>;
begin
  if Assigned(FOnRefresh) then
    FOnRefresh();
  Settings := TAtlasIdeSettings.Current;
  FItems := TAtlasStatusSummary.Visible(FRegistry.Items, TAtlasStatusSummary.ParseIds(Settings.StatusFieldHidden));
  FState := TAtlasStatusSummary.Overall(FItems);
  FText := TAtlasStatusSummary.FieldText(FItems, Settings.StatusFieldSummary);
  FTooltip := TAtlasStatusSummary.Tooltip(FItems);
  if FWindow <> nil then
    FWindow.SetItems(FItems);
  if not Settings.StatusField then
  begin
    UnhookAll;
    Exit;
  end;
  // Neue Editorfenster bekommen hier ihr Feld.
  Bars := TList<TStatusBar>.Create;
  try
    if Supports(BorlandIDEServices, INTAEditorServices, Services) then
      for Index := 0 to Services.EditWindowCount - 1 do
      begin
        Window := Services.EditWindow[Index];
        if (Window <> nil) and (Window.StatusBar <> nil) then
          Bars.Add(Window.StatusBar);
      end;
    for Hook in FHooks do
      if Bars.IndexOf(Hook.Bar) < 0 then
        Bars.Add(Hook.Bar);
    for Index := 0 to Bars.Count - 1 do
    begin
      HookBar(Bars[Index]);
      Hook := HookOf(Bars[Index]);
      if Hook = nil then
        Continue;
      Hook.Bar.Canvas.Font := Hook.Bar.Font;
      Width_ := Hook.Bar.Canvas.TextWidth(FText) + MulDiv(30, Hook.Bar.CurrentPPI, 96) +
        SymbolWidth(Hook.Bar.CurrentPPI);
      // Text nur zum Erkennen und für Screenreader; gezeichnet wird in DrawPanel.
      Hook.Panel.Text := FText;
      Hook.Panel.Width := Width_;
      if Hook.InPanel then
        Hook.Bar.Hint := FTooltip;
      Hook.Bar.Invalidate;
    end;
  finally
    Bars.Free;
  end;
end;

procedure TAtlasStatusField.DrawPanel(StatusBar: TStatusBar; Panel: TStatusPanel; const Rect: TRect);
var
  Hook: THook;
  Canvas: TCanvas;
  Radius, Center, Left_, Pixels: Integer;
  Symbol: TWICImage;
  Target: TRect;
  Dot: TColor;
  Part: TRect;
  Text: string;
begin
  Hook := HookOf(StatusBar);
  if (Hook = nil) or (Panel <> Hook.Panel) then
  begin
    if (Hook <> nil) and Assigned(Hook.OldDraw) then
      Hook.OldDraw(StatusBar, Panel, Rect);
    Exit;
  end;
  try
    Canvas := StatusBar.Canvas;
    Canvas.Font := StatusBar.Font;
    Canvas.Font.Color := StyleServices.GetSystemColor(clBtnText);
    Radius := MulDiv(4, StatusBar.CurrentPPI, 96);
    Center := (Rect.Top + Rect.Bottom) div 2;
    Left_ := Rect.Left;
    Symbol := TAtlasSymbolImages.Cached(TAtlasIdeSymbol.Current, TAtlasSymbol.MenuSize, StatusBar.CurrentPPI);
    if Symbol <> nil then
    begin
      Pixels := TAtlasSymbol.PixelSize(TAtlasSymbol.MenuSize, StatusBar.CurrentPPI);
      Target := Bounds(Left_ + 2, Center - Pixels div 2, Pixels, Pixels);
      if Symbol.Width = Pixels then
        Canvas.Draw(Target.Left, Target.Top, Symbol)
      else
        Canvas.StretchDraw(Target, Symbol);
      Inc(Left_, SymbolWidth(StatusBar.CurrentPPI));
    end;
    Dot := TColor(TAtlasStatusWindow.StateColor(TAtlasIdeStyle.Colors, FState));
    Canvas.Pen.Color := Dot;
    Canvas.Brush.Color := Dot;
    Canvas.Brush.Style := bsSolid;
    Canvas.Ellipse(Left_ + 2 * Radius - Radius, Center - Radius, Left_ + 2 * Radius + Radius + 1,
      Center + Radius + 1);
    Canvas.Brush.Style := bsClear;
    Part := Rect;
    Part.Left := Left_ + 4 * Radius + 2;
    Text := FText;
    DrawText(Canvas.Handle, PChar(Text), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
    Canvas.Brush.Style := bsSolid;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Status, E);
  end;
end;

procedure TAtlasStatusField.BarMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Hook: THook;
begin
  Hook := HookOf(Sender as TStatusBar);
  if Hook = nil then
    Exit;
  if (Button = mbLeft) and Hook.SkipUp then
  begin
    // Loslassen nach dem Doppelklick: Die Schnellschalter sind schon unterwegs.
    Hook.SkipUp := False;
    Exit;
  end;
  if (Button = mbLeft) and PtInRect(PanelRect(Hook), Point(X, Y)) then
  begin
    TAtlasGuard.Run(TAtlasFeature.Status,
      procedure
      begin
        OpenWindow(Hook);
      end);
    Exit;
  end;
  if Assigned(Hook.OldMouseUp) then
    Hook.OldMouseUp(Sender, Button, Shift, X, Y);
end;

procedure TAtlasStatusField.BarMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  Hook: THook;
  Inside: Boolean;
begin
  Hook := HookOf(Sender as TStatusBar);
  if Hook = nil then
    Exit;
  Inside := PtInRect(PanelRect(Hook), Point(X, Y));
  if Inside <> Hook.InPanel then
  begin
    if Inside then
    begin
      Hook.OldHint := Hook.Bar.Hint;
      Hook.OldShowHint := Hook.Bar.ShowHint;
      Hook.Bar.Hint := FTooltip;
      Hook.Bar.ShowHint := True;
    end
    else
    begin
      Hook.Bar.Hint := Hook.OldHint;
      Hook.Bar.ShowHint := Hook.OldShowHint;
      Application.CancelHint;
    end;
    Hook.InPanel := Inside;
  end;
  if Assigned(Hook.OldMouseMove) then
    Hook.OldMouseMove(Sender, Shift, X, Y);
end;

procedure TAtlasStatusField.BarMessage(AHook: THook; var Message: TMessage);
var
  Position: TPoint;
  Inside: Boolean;
begin
  Inside := False;
  case Message.Msg of
    WM_LBUTTONDOWN:
      // Ging das Loslassen nach einem Doppelklick verloren, gilt der nächste Klick wieder.
      AHook.SkipUp := False;
    WM_RBUTTONDOWN, WM_RBUTTONUP:
      Inside := Assigned(FOnContext) and TAtlasIdeSettings.Current.StatusTogglesOnRightClick and
        PtInRect(PanelRect(AHook), SmallPointToPoint(TWMMouse(Message).Pos));
    WM_LBUTTONDBLCLK:
      Inside := Assigned(FOnContext) and TAtlasIdeSettings.Current.StatusTogglesOnDoubleClick and
        PtInRect(PanelRect(AHook), SmallPointToPoint(TWMMouse(Message).Pos));
    WM_CONTEXTMENU:
      // -1/-1 kommt von der Tastatur (Umschalt+F10): der IDE überlassen.
      if (TWMContextMenu(Message).XPos <> -1) or (TWMContextMenu(Message).YPos <> -1) then
      begin
        Position := AHook.Bar.ScreenToClient(SmallPointToPoint(TWMContextMenu(Message).Pos));
        Inside := Assigned(FOnContext) and TAtlasIdeSettings.Current.StatusTogglesOnRightClick and
          PtInRect(PanelRect(AHook), Position);
      end;
  end;
  if not Inside then
  begin
    AHook.OldWndProc(Message);
    Exit;
  end;
  // Über dem Feld weder die Standardbehandlung (erzeugt WM_CONTEXTMENU) noch die IDE.
  if Message.Msg = WM_LBUTTONDBLCLK then
    AHook.SkipUp := True;
  if (Message.Msg = WM_RBUTTONUP) or (Message.Msg = WM_LBUTTONDBLCLK) then
    PostMessage(FWnd, WM_ATLAS_STATUS_CONTEXT, 0, LPARAM(AHook.Bar));
  Message.Result := 0;
end;

procedure TAtlasStatusField.OpenContext(AHook: THook);
var
  Area: TRect;
begin
  if not Assigned(FOnContext) then
    Exit;
  if FWindow <> nil then
    FWindow.Dismiss;
  Area := PanelRect(AHook);
  FOnContext(AHook.Bar.ClientToScreen(Point(Area.Left, Area.Top)));
end;

function TAtlasStatusField.Anchor(out APoint: TPoint): Boolean;
var
  Services: INTAEditorServices;
  Window: INTAEditWindow;
  Hook: THook;
  Area: TRect;
begin
  APoint := Point(0, 0);
  Result := False;
  if not Supports(BorlandIDEServices, INTAEditorServices, Services) then
    Exit;
  Window := Services.TopEditWindow;
  if (Window = nil) or (Window.StatusBar = nil) then
    Exit;
  Hook := HookOf(Window.StatusBar);
  if (Hook = nil) or not Hook.Bar.Visible then
    Exit;
  Area := PanelRect(Hook);
  if Area.IsEmpty then
    Exit;
  APoint := Hook.Bar.ClientToScreen(Point(Area.Left, Area.Top));
  Result := True;
end;

procedure TAtlasStatusField.OpenWindow(AHook: THook);
var
  Area: TRect;
begin
  // Zweiter Klick schließt.
  if FWindow <> nil then
  begin
    FWindow.Dismiss;
    Exit;
  end;
  Refresh;
  FWindow := TAtlasStatusWindow.CreateStatus(Application, TAtlasIdeStyle.Colors);
  FWindow.FreeNotification(Self);
  FWindow.OnOpenLog := FOnOpenLog;
  FWindow.OnRestart := FOnRestart;
  FWindow.SetItems(FItems);
  Area := PanelRect(AHook);
  FWindow.ShowAbove(AHook.Bar.ClientToScreen(Point(Area.Left, Area.Top)));
end;

end.
