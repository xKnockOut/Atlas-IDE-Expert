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
// - Der Fortschritt des Symbol-Index (Zeile atlas.index) steht mit
//   IndexProgressPlace = 'statusField' immer im Feld, auch ohne Kurztext und
//   neben einer wichtigeren Zeile („Atlas · Server langsam · Index 45 %“).
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
// - Zusatzfelder (SetExtra, z. B. das Startprofil #575): einfache Textpanels
//   rechts vom Atlas-Feld mit eigenem Tooltip; ein Linksklick ruft ihr
//   OnClick mit der linken Oberkante des Panels. Sie erscheinen auch bei
//   ausgeschaltetem Atlas-Feld (StatusField); das Atlas-Panel ist dann 0 breit.
// - Plakette der Benachrichtigungszentrale (#601, SetBadge): rechts im
//   Atlas-Feld die Zahl der ungelesenen Einträge in der Farbe des schwersten;
//   ein Linksklick darauf ruft ihr OnClick (Liste) statt des Statusfensters.
//   Der Tooltip des Felds nennt die Zahl. Nur mit eingeschaltetem Atlas-Feld.
// - Die Panels gehören der Leiste, und die IDE löscht sie unter Umständen
//   selbst (Delphi 12: Absturz in PanelRect über ein freigegebenes Panel).
//   Deshalb sind sie vom eigenen Typ TFieldPanel und melden ihre Freigabe dem
//   Haken; der vergisst sie, und das nächste Refresh legt sie neu an.

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
    /// <summary>Eigenes Panel: meldet seine Freigabe über OnGone, auch wenn die IDE es löscht.</summary>
    TFieldPanel = class(TStatusPanel)
    public
      OnGone: TNotifyEvent;
      destructor Destroy; override;
    end;

    TExtra = record
      Id: string;
      Text: string;
      Hint: string;
      OnClick: TProc<TPoint>;
    end;

    THook = class
    public
      Field: TAtlasStatusField;
      Bar: TStatusBar;
      /// <summary>Panel des Atlas-Felds; nil, wenn die IDE es gelöscht hat (bis zum nächsten Refresh).</summary>
      Panel: TFieldPanel;
      /// <summary>Panels der Zusatzfelder in der Reihenfolge von FExtras; gehören der Leiste. Ein von der IDE
      /// gelöschtes steht als nil darin, damit die Zuordnung zu FExtras stimmt.</summary>
      Extras: TList<TFieldPanel>;
      OldDraw: TDrawPanelEvent;
      OldMouseUp: TMouseEvent;
      OldMouseMove: TMouseMoveEvent;
      OldWndProc: TWndMethod;
      OldHint: string;
      OldShowHint: Boolean;
      /// <summary>Panel unter der Maus, dessen Tooltip gilt: -1 keins, 0 Atlas-Feld, ab 1 Zusatzfeld.</summary>
      Zone: Integer;
      /// <summary>Das Loslassen nach einem Doppelklick auf das Feld nicht als Klick werten.</summary>
      SkipUp: Boolean;
      constructor Create;
      destructor Destroy; override;
      procedure WndProc(var Message: TMessage);
      /// <summary>Neues eigenes Panel am Ende der Leiste.</summary>
      function NewPanel(AStyle: TStatusPanelStyle): TFieldPanel;
      /// <summary>APanel aus der Leiste entfernen, ohne PanelGone auszulösen.</summary>
      procedure DropPanel(APanel: TFieldPanel);
      /// <summary>OnGone der Panels: Ein freigegebenes Panel vergessen.</summary>
      procedure PanelGone(Sender: TObject);
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
    FExtras: TArray<TExtra>;
    FBadgeCount: Integer;
    FBadgeState: TAtlasStatusState;
    FBadgeHint: string;
    FOnBadge: TProc<TPoint>;
    function BadgeText: string;
    /// <summary>Breite der Plakette samt Abstand in Gerätepixeln; 0 ohne.</summary>
    function BadgeWidth(ABar: TStatusBar): Integer;
    procedure WndProc(var Message: TMessage);
    procedure TimerTick(Sender: TObject);
    procedure Refresh;
    function HookOf(ABar: TStatusBar): THook;
    procedure HookBar(ABar: TStatusBar);
    procedure Unhook(AHook: THook; ARestore: Boolean);
    procedure UnhookAll;
    function PanelRect(AHook: THook): TRect; overload;
    function PanelRect(AHook: THook; APanel: TStatusPanel): TRect; overload;
    function ZoneAt(AHook: THook; X, Y: Integer): Integer;
    function HintOf(AZone: Integer): string;
    procedure SyncExtras(AHook: THook);
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
    /// <summary>Zusatzfeld AId setzen (Text, Tooltip, Linksklick mit der linken Oberkante des Panels); AText ''
    /// entfernt es. Nur im Hauptthread.</summary>
    procedure SetExtra(const AId, AText, AHint: string; const AOnClick: TProc<TPoint>);
    /// <summary>Plakette der Benachrichtigungen (#601): ACount ungelesene (0 = keine Plakette), Farbe nach
    /// AState, AHint im Tooltip; Linksklick auf die Plakette ruft AOnClick mit der linken Oberkante des Felds.
    /// Nur im Hauptthread.</summary>
    procedure SetBadge(ACount: Integer; AState: TAtlasStatusState; const AHint: string;
      const AOnClick: TProc<TPoint>);
  end;

implementation

uses
  Vcl.Forms,
  Vcl.Graphics,
  Vcl.Themes,
  DockForm,
  ToolsAPI,
  Atlas.Core.Status.Registry,
  Atlas.Core.Status.Lines,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.Core.Style.Symbol,
  Atlas.UI.Style.Symbol,
  Atlas.IDE.Foundation.Symbol;

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
  Hook.Panel := Hook.NewPanel(psOwnerDraw);
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
  Index: Integer;
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
  if AHook.Zone >= 0 then
  begin
    Bar.Hint := AHook.OldHint;
    Bar.ShowHint := AHook.OldShowHint;
  end;
  for Index := AHook.Extras.Count - 1 downto 0 do
    AHook.DropPanel(AHook.Extras[Index]);
  AHook.Extras.Clear;
  AHook.DropPanel(AHook.Panel);
  AHook.Panel := nil;
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

constructor TAtlasStatusField.THook.Create;
begin
  inherited Create;
  Extras := TList<TFieldPanel>.Create;
  Zone := -1;
end;

destructor TAtlasStatusField.THook.Destroy;
var
  Item: TFieldPanel;
begin
  // Noch lebende Panels dürfen den freigegebenen Haken nicht mehr rufen.
  if Panel <> nil then
    Panel.OnGone := nil;
  for Item in Extras do
    if Item <> nil then
      Item.OnGone := nil;
  Extras.Free;
  inherited Destroy;
end;

function TAtlasStatusField.THook.NewPanel(AStyle: TStatusPanelStyle): TFieldPanel;
begin
  Result := TFieldPanel.Create(Bar.Panels);
  Result.Style := AStyle;
  Result.Bevel := pbNone;
  Result.OnGone := PanelGone;
end;

procedure TAtlasStatusField.THook.DropPanel(APanel: TFieldPanel);
var
  Index: Integer;
begin
  if APanel = nil then
    Exit;
  APanel.OnGone := nil;
  // Nur über Zeigervergleich suchen: APanel.Index liest schon die Sammlung.
  for Index := Bar.Panels.Count - 1 downto 0 do
    if Bar.Panels[Index] = APanel then
    begin
      Bar.Panels.Delete(Index);
      Exit;
    end;
end;

procedure TAtlasStatusField.THook.PanelGone(Sender: TObject);
var
  Index: Integer;
begin
  if Sender = Panel then
    Panel := nil;
  for Index := 0 to Extras.Count - 1 do
    if Extras[Index] = Sender then
      Extras[Index] := nil;
  // Das nächste Refresh legt das Panel neu an.
  if Field <> nil then
    Field.RequestRefresh;
end;

{ TAtlasStatusField.TFieldPanel }

destructor TAtlasStatusField.TFieldPanel.Destroy;
begin
  if Assigned(OnGone) then
    OnGone(Self);
  inherited Destroy;
end;

procedure TAtlasStatusField.THook.WndProc(var Message: TMessage);
begin
  if Field <> nil then
    Field.BarMessage(Self, Message)
  else
    OldWndProc(Message);
end;

function TAtlasStatusField.PanelRect(AHook: THook; APanel: TStatusPanel): TRect;
begin
  Result := Rect(0, 0, 0, 0);
  if (APanel = nil) or not AHook.Bar.HandleAllocated or (APanel.Width <= 0) then
    Exit;
  SendMessage(AHook.Bar.Handle, SB_GETRECT, APanel.Index, LPARAM(@Result));
end;

function TAtlasStatusField.PanelRect(AHook: THook): TRect;
begin
  Result := PanelRect(AHook, AHook.Panel);
end;

function TAtlasStatusField.ZoneAt(AHook: THook; X, Y: Integer): Integer;
var
  Index: Integer;
begin
  if PtInRect(PanelRect(AHook), Point(X, Y)) then
    Exit(0);
  for Index := 0 to AHook.Extras.Count - 1 do
    if PtInRect(PanelRect(AHook, AHook.Extras[Index]), Point(X, Y)) then
      Exit(Index + 1);
  Result := -1;
end;

function TAtlasStatusField.HintOf(AZone: Integer): string;
begin
  Result := '';
  if AZone = 0 then
    Result := FTooltip
  else if (AZone > 0) and (AZone <= Length(FExtras)) then
    Result := FExtras[AZone - 1].Hint;
end;

procedure TAtlasStatusField.SyncExtras(AHook: THook);
var
  Index: Integer;
  Panel: TFieldPanel;
begin
  while AHook.Extras.Count > Length(FExtras) do
  begin
    AHook.DropPanel(AHook.Extras.Last);
    AHook.Extras.Delete(AHook.Extras.Count - 1);
  end;
  while AHook.Extras.Count < Length(FExtras) do
    AHook.Extras.Add(nil);
  for Index := 0 to AHook.Extras.Count - 1 do
  begin
    // Neu oder von der IDE gelöscht.
    if AHook.Extras[Index] = nil then
      AHook.Extras[Index] := AHook.NewPanel(psText);
    Panel := AHook.Extras[Index];
    Panel.Text := FExtras[Index].Text;
    Panel.Width := AHook.Bar.Canvas.TextWidth(FExtras[Index].Text) + MulDiv(16, AHook.Bar.CurrentPPI, 96);
  end;
end;

procedure TAtlasStatusField.SetExtra(const AId, AText, AHint: string; const AOnClick: TProc<TPoint>);
var
  Index, Found: Integer;
  Extra: TExtra;
begin
  Found := -1;
  for Index := 0 to High(FExtras) do
    if FExtras[Index].Id = AId then
      Found := Index;
  if AText = '' then
  begin
    if Found >= 0 then
      Delete(FExtras, Found, 1);
  end
  else
  begin
    Extra.Id := AId;
    Extra.Text := AText;
    Extra.Hint := AHint;
    Extra.OnClick := AOnClick;
    if Found >= 0 then
      FExtras[Found] := Extra
    else
      FExtras := FExtras + [Extra];
  end;
  RequestRefresh;
end;

procedure TAtlasStatusField.SetBadge(ACount: Integer; AState: TAtlasStatusState; const AHint: string;
  const AOnClick: TProc<TPoint>);
begin
  if ACount < 0 then
    ACount := 0;
  FOnBadge := AOnClick;
  // Unverändert: nicht neu zeichnen (die Zentrale meldet auch Änderungen ohne Wirkung auf die Plakette).
  if (ACount = FBadgeCount) and (AState = FBadgeState) and (AHint = FBadgeHint) then
    Exit;
  FBadgeCount := ACount;
  FBadgeState := AState;
  FBadgeHint := AHint;
  RequestRefresh;
end;

function TAtlasStatusField.BadgeText: string;
begin
  if FBadgeCount > 99 then
    Result := '99+'
  else
    Result := IntToStr(FBadgeCount);
end;

function TAtlasStatusField.BadgeWidth(ABar: TStatusBar): Integer;
begin
  Result := 0;
  if (FBadgeCount <= 0) or (ABar = nil) then
    Exit;
  ABar.Canvas.Font := ABar.Font;
  Result := ABar.Canvas.TextWidth(BadgeText) + MulDiv(18, ABar.CurrentPPI, 96);
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
  ProgressId: string;
begin
  if Assigned(FOnRefresh) then
    FOnRefresh();
  Settings := TAtlasIdeSettings.Current;
  FItems := TAtlasStatusSummary.Visible(FRegistry.Items, TAtlasStatusSummary.ParseIds(Settings.StatusFieldHidden));
  FState := TAtlasStatusSummary.Overall(FItems);
  ProgressId := '';
  if Settings.IndexProgressInField then
    ProgressId := TAtlasStatusLines.IndexId;
  FText := TAtlasStatusSummary.FieldText(FItems, Settings.StatusFieldSummary, ProgressId);
  FTooltip := TAtlasStatusSummary.Tooltip(FItems);
  if (FBadgeCount > 0) and (FBadgeHint <> '') then
  begin
    if FTooltip <> '' then
      FTooltip := FTooltip + sLineBreak;
    FTooltip := FTooltip + FBadgeHint;
  end;
  if FWindow <> nil then
    FWindow.SetItems(FItems);
  // Ohne Atlas-Feld bleiben die Leisten nur für Zusatzfelder eingehängt (#575).
  if not Settings.StatusField and (Length(FExtras) = 0) then
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
      // Von der IDE gelöscht (PanelGone): neu anlegen.
      if Hook.Panel = nil then
        Hook.Panel := Hook.NewPanel(psOwnerDraw);
      Hook.Bar.Canvas.Font := Hook.Bar.Font;
      Width_ := 0;
      if Settings.StatusField then
        Width_ := Hook.Bar.Canvas.TextWidth(FText) + MulDiv(30, Hook.Bar.CurrentPPI, 96) +
          SymbolWidth(Hook.Bar.CurrentPPI) + BadgeWidth(Hook.Bar);
      // Text nur zum Erkennen und für Screenreader; gezeichnet wird in DrawPanel.
      if Width_ > 0 then
        Hook.Panel.Text := FText
      else
        Hook.Panel.Text := '';
      Hook.Panel.Width := Width_;
      SyncExtras(Hook);
      // Zusatzfeld verschwunden oder Feld aus: Tooltip des Panels unter der Maus neu bestimmen.
      if Hook.Zone >= 0 then
        Hook.Bar.Hint := HintOf(Hook.Zone);
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
  Part, Badge: TRect;
  Text: string;
  Inset: Integer;
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
    // Plakette der Benachrichtigungen (#601) ganz rechts, der Text endet davor.
    if FBadgeCount > 0 then
    begin
      Part.Right := Part.Right - BadgeWidth(StatusBar);
      Inset := MulDiv(3, StatusBar.CurrentPPI, 96);
      Badge.Left := Part.Right + Inset;
      Badge.Top := Rect.Top + Inset;
      Badge.Right := Rect.Right - Inset;
      Badge.Bottom := Rect.Bottom - Inset;
      Dot := TColor(TAtlasStatusWindow.StateColor(TAtlasIdeStyle.Colors, FBadgeState));
      Canvas.Pen.Color := Dot;
      Canvas.Brush.Color := Dot;
      Canvas.Brush.Style := bsSolid;
      Canvas.RoundRect(Badge.Left, Badge.Top, Badge.Right, Badge.Bottom, Badge.Height, Badge.Height);
      Canvas.Brush.Style := bsClear;
      // Auf Gelb dunkle Schrift, sonst weiße.
      if FBadgeState = TAtlasStatusState.Yellow then
        Canvas.Font.Color := clBlack
      else
        Canvas.Font.Color := clWhite;
      Text := BadgeText;
      DrawText(Canvas.Handle, PChar(Text), -1, Badge, DT_SINGLELINE or DT_CENTER or DT_VCENTER or DT_NOPREFIX);
      Canvas.Font.Color := StyleServices.GetSystemColor(clBtnText);
    end;
    Text := FText;
    Canvas.Brush.Style := bsClear;
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
  Zone: Integer;
  OnClick: TProc<TPoint>;
  Area: TRect;
  Corner: TPoint;
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
  Zone := -1;
  if Button = mbLeft then
    Zone := ZoneAt(Hook, X, Y);
  // Klick auf die Plakette (#601): Liste der Benachrichtigungen statt Statusfenster.
  if (Zone = 0) and (FBadgeCount > 0) and Assigned(FOnBadge) and
    (X >= PanelRect(Hook).Right - BadgeWidth(Hook.Bar)) then
  begin
    OnClick := FOnBadge;
    Area := PanelRect(Hook);
    Corner := Hook.Bar.ClientToScreen(Point(Area.Left, Area.Top));
    if FWindow <> nil then
      FWindow.Dismiss;
    TAtlasGuard.Run(TAtlasFeature.Status,
      procedure
      begin
        OnClick(Corner);
      end);
    Exit;
  end;
  if Zone = 0 then
  begin
    TAtlasGuard.Run(TAtlasFeature.Status,
      procedure
      begin
        OpenWindow(Hook);
      end);
    Exit;
  end;
  if (Zone > 0) and (Zone <= Length(FExtras)) then
  begin
    OnClick := FExtras[Zone - 1].OnClick;
    Area := PanelRect(Hook, Hook.Extras[Zone - 1]);
    Corner := Hook.Bar.ClientToScreen(Point(Area.Left, Area.Top));
    if Assigned(OnClick) then
      TAtlasGuard.Run(TAtlasFeature.Status,
        procedure
        begin
          OnClick(Corner);
        end);
    Exit;
  end;
  if Assigned(Hook.OldMouseUp) then
    Hook.OldMouseUp(Sender, Button, Shift, X, Y);
end;

procedure TAtlasStatusField.BarMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  Hook: THook;
  Zone: Integer;
begin
  Hook := HookOf(Sender as TStatusBar);
  if Hook = nil then
    Exit;
  Zone := ZoneAt(Hook, X, Y);
  if Zone <> Hook.Zone then
  begin
    if Zone >= 0 then
    begin
      // Erst beim Betreten eines unserer Panels den Tooltip der Leiste merken.
      if Hook.Zone < 0 then
      begin
        Hook.OldHint := Hook.Bar.Hint;
        Hook.OldShowHint := Hook.Bar.ShowHint;
      end;
      Hook.Bar.Hint := HintOf(Zone);
      Hook.Bar.ShowHint := True;
    end
    else
    begin
      Hook.Bar.Hint := Hook.OldHint;
      Hook.Bar.ShowHint := Hook.OldShowHint;
    end;
    Application.CancelHint;
    Hook.Zone := Zone;
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
