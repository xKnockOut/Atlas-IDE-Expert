unit Atlas.IDE.Status.Adapters.FieldSurface;

// Statuszeilen der Editorfenster für das Atlas-Feld (#591): erfüllt
// IAtlasStatusFieldSurface. Was das Feld zeigt und was ein Klick auslöst,
// entscheidet TAtlasStatusFieldFlow (Atlas.Core.Status.FieldFlow); hier
// stehen nur Panels, Haken, Zeichnen und das Statusfenster.
// - Das Feld ist ein selbst gezeichnetes Panel rechts neben denen der IDE
//   (INTAEditWindow.StatusBar). OnDrawPanel, OnMouseUp, OnMouseMove und
//   WindowProc der Leiste werden verkettet und beim Aushängen zurückgesetzt;
//   geschlossene Fenster meldet FreeNotification.
// - Anforderungen (RequestTick, aus jedem Thread), neue oder aktivierte
//   Editorfenster und von der IDE gelöschte Panels werden gesammelt; OnTick
//   läuft höchstens alle 250 ms im Hauptthread.
// - Die rechte Maustaste wird in WindowProc abgefangen, nicht in OnMouseUp:
//   Sonst erzeugt die Standardbehandlung von WM_RBUTTONUP vorher
//   WM_CONTEXTMENU, das an das Editorfenster der IDE weitergeht; dessen Menü
//   bzw. Fokuswechsel schloss die Schnellschalter sofort wieder. Öffnet die
//   Geste die Schnellschalter (OpensToggles), schluckt Atlas WM_RBUTTONDOWN,
//   WM_RBUTTONUP, WM_LBUTTONDBLCLK und WM_CONTEXTMENU über dem Feld und meldet
//   OnContext erst nach der Mausnachricht (PostMessage). Beim Doppelklick
//   schließt sich das vom ersten Klick geöffnete Statusfenster; das Loslassen
//   danach öffnet es nicht erneut.
// - Links steht das Atlas-Symbol (#751) in der Variante zum IDE-Thema und in
//   der Größe zur Pixeldichte der Leiste, dann Punkt, Text und rechts die
//   Plakette der Benachrichtigungen (#601).
// - Zusatzfelder sind einfache Textpanels rechts vom Atlas-Feld; ihren
//   Tooltip und Klick liefert das Feld.
// - Die Panels gehören der Leiste, und die IDE löscht sie unter Umständen
//   selbst (Delphi 12: Absturz in PanelRect über ein freigegebenes Panel).
//   Deshalb sind sie vom eigenen Typ TFieldPanel und melden ihre Freigabe dem
//   Haken; der vergisst sie, und das nächste OnTick legt sie neu an.
// - Ein ausgeblendetes Atlas-Panel wird entfernt, nicht 0 breit gelassen: Das
//   letzte Panel einer TStatusBar reicht bis zum rechten Rand, gleich welche
//   Breite es hat.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Status.Contract,
  Atlas.UI.Foundation.WndProcHook,
  Atlas.UI.Status.Window;

type
  TAtlasIdeStatusFieldSurface = class(TInterfacedObject, IAtlasStatusFieldSurface)
  public const
    cRedrawMs = 250;
  private type
    /// <summary>Eigenes Panel: meldet seine Freigabe über OnGone, auch wenn die IDE es löscht.</summary>
    TFieldPanel = class(TStatusPanel)
    public
      OnGone: TNotifyEvent;
      destructor Destroy; override;
    end;

    /// <summary>Eine eingehängte Statusleiste: ihre Panels, die verketteten Handler und deren Behandlung.</summary>
    THook = class
    public
      /// <summary>Oberfläche des Hakens; nil, wenn die Leiste geht oder ausgehängt ist.</summary>
      Surface: TAtlasIdeStatusFieldSurface;
      Bar: TStatusBar;
      /// <summary>Panel des Atlas-Felds; nil, wenn die IDE es gelöscht hat (bis zum nächsten Show).</summary>
      Panel: TFieldPanel;
      /// <summary>Panels der Zusatzfelder in ihrer Reihenfolge; gehören der Leiste. Ein von der IDE gelöschtes
      /// steht als nil darin, damit die Zuordnung stimmt.</summary>
      Extras: TList<TFieldPanel>;
      OldDraw: TDrawPanelEvent;
      OldMouseUp: TMouseEvent;
      OldMouseMove: TMouseMoveEvent;
      /// <summary>Eingehängte WindowProc der Leiste; nil nach Restore.</summary>
      WndHook: TAtlasWndProcHook;
      OldHint: string;
      OldShowHint: Boolean;
      /// <summary>Panel unter der Maus, dessen Tooltip gilt: -1 keins, 0 Atlas-Feld, ab 1 Zusatzfeld.</summary>
      Zone: Integer;
      /// <summary>Das Loslassen nach einem Doppelklick auf das Feld nicht als Klick werten.</summary>
      SkipUp: Boolean;
      constructor Create;
      destructor Destroy; override;
      procedure WndProc(var AMessage: TMessage);
      /// <summary>Neues eigenes Panel am Ende der Leiste.</summary>
      function NewPanel(AStyle: TStatusPanelStyle): TFieldPanel;
      /// <summary>APanel aus der Leiste entfernen, ohne PanelGone auszulösen.</summary>
      procedure DropPanel(APanel: TFieldPanel);
      /// <summary>OnGone der Panels: Ein freigegebenes Panel vergessen.</summary>
      procedure PanelGone(Sender: TObject);
      /// <summary>Rechteck von APanel in der Leiste; leer ohne Fenster oder Breite.</summary>
      function PanelRect(APanel: TStatusPanel): TRect; overload;
      /// <summary>Rechteck des Atlas-Felds.</summary>
      function PanelRect: TRect; overload;
      /// <summary>Linke Oberkante von ARect (Leiste) auf dem Bildschirm.</summary>
      function ScreenCorner(const ARect: TRect): TPoint;
      function ZoneAt(AX, AY: Integer): Integer;
      function HintOf(AZone: Integer): string;
      procedure SyncExtras(const AView: TAtlasStatusFieldView);
      /// <summary>Panels nach AView anlegen, beschriften und messen.</summary>
      procedure Layout(const AView: TAtlasStatusFieldView);
      /// <summary>Handler und Tooltip der Leiste zurücksetzen, soweit sie noch unsere sind; Panels entfernen.</summary>
      procedure Restore;
      procedure DrawPanel(AStatusBar: TStatusBar; APanel: TStatusPanel; const ARect: TRect);
      procedure BarMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
      procedure BarMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
      /// <summary>Linksklick in AZone an X; False, wenn er nicht Atlas gilt.</summary>
      function Click(AZone, AX: Integer): Boolean;
      /// <summary>Mausnachricht über dem Feld für die Schnellschalter abfangen; True, wenn geschluckt.</summary>
      function Swallow(var AMessage: TMessage): Boolean;
    end;

    /// <summary>Meldet geschlossene Statusleisten und das freigegebene Statusfenster.</summary>
    TWatch = class(TComponent)
    private
      FSurface: TAtlasIdeStatusFieldSurface;
    protected
      procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    end;
  private
    FInput: TAtlasStatusFieldInput;
    FView: TAtlasStatusFieldView;
    FWatch: TWatch;
    FHooks: TObjectList<THook>;
    // Haken geschlossener Leisten: erst mit der Oberfläche freigeben, die Leiste ruft im Abbau noch WindowProc auf.
    FDead: TObjectList<THook>;
    FWnd: HWND;
    FPosted: Integer;
    FTimer: TTimer;
    FWindow: TAtlasStatusWindow;
    FNotifierIndex: Integer;
    procedure WndProc(var AMessage: TMessage);
    procedure TimerTick(Sender: TObject);
    /// <summary>FreeNotification von TWatch: Leiste oder Statusfenster ist weg.</summary>
    procedure Gone(AComponent: TComponent);
    function HookOf(ABar: TStatusBar): THook;
    /// <summary>ABar einhängen: verkettete Handler; nichts, wenn sie schon eingehängt ist.</summary>
    procedure HookBar(ABar: TStatusBar);
    /// <summary>Leisten aller Editorfenster und die schon eingehängten, ohne Doppelte.</summary>
    function EditorBars: TArray<TStatusBar>;
    procedure FreeWindow;
  public
    constructor Create;
    destructor Destroy; override;
    { IAtlasStatusFieldSurface }
    procedure Attach(const AInput: TAtlasStatusFieldInput);
    procedure Detach;
    procedure RequestTick;
    procedure Show(const AView: TAtlasStatusFieldView);
    procedure Unhook;
    function FieldCorner(out APoint: TPoint): Boolean;
    function WindowOpen: Boolean;
    procedure OpenWindow(const AItems: TArray<IAtlasStatusItem>; const APoint: TPoint;
      const AOnOpenLog, AOnRestart: TProc);
    procedure CloseWindow;
    procedure WindowItems(const AItems: TArray<IAtlasStatusItem>);
  end;

implementation

uses
  Winapi.CommCtrl,
  Vcl.Forms,
  Vcl.Graphics,
  Vcl.Themes,
  DockForm,
  ToolsAPI,
  Atlas.Core.Status.FieldPlan,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.Plugin.Style.Symbol,
  Atlas.Plugin.Style.Signal,
  Atlas.Core.Status.Signal,
  Atlas.UI.Style.Symbol,
  Atlas.IDE.Foundation.Symbol;

const
  cWM_ATLAS_STATUS = WM_USER + 591;
  // LParam = TStatusBar; erst nach der Mausnachricht ausgeführt, eine gelöste Oberfläche verwirft sie mit ihrem
  // Fenster.
  cWM_ATLAS_STATUS_CONTEXT = WM_USER + 592;

type
  TFieldNotifier = class(TNotifierObject, INTAEditServicesNotifier)
  private
    FSurface: TAtlasIdeStatusFieldSurface;
  public
    constructor Create(ASurface: TAtlasIdeStatusFieldSurface);
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

constructor TFieldNotifier.Create(ASurface: TAtlasIdeStatusFieldSurface);
begin
  inherited Create;
  FSurface := ASurface;
end;

procedure TFieldNotifier.WindowShow(const EditWindow: INTAEditWindow; Show, LoadedFromDesktop: Boolean);
begin
  TAtlasGuard.Run(TAtlasFeature.Status,
    procedure
    begin
      FSurface.RequestTick;
    end);
end;

procedure TFieldNotifier.WindowNotification(const EditWindow: INTAEditWindow; Operation: TOperation);
begin
  TAtlasGuard.Run(TAtlasFeature.Status,
    procedure
    begin
      FSurface.RequestTick;
    end);
end;

procedure TFieldNotifier.WindowActivated(const EditWindow: INTAEditWindow);
begin
  TAtlasGuard.Run(TAtlasFeature.Status,
    procedure
    begin
      FSurface.RequestTick;
    end);
end;

procedure TFieldNotifier.WindowCommand(const EditWindow: INTAEditWindow; Command, Param: Integer;
  var Handled: Boolean);
begin
end;

procedure TFieldNotifier.EditorViewActivated(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
begin
  TAtlasGuard.Run(TAtlasFeature.Status,
    procedure
    begin
      // Aktive Datei gewechselt: Zeile „Datei“ nachführen.
      FSurface.RequestTick;
    end);
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

function SameMethod(const ALeft, ARight: TMethod): Boolean;
begin
  Result := (ALeft.Code = ARight.Code) and (ALeft.Data = ARight.Data);
end;

/// <summary>Platz für das Symbol samt Abstand in Gerätepixeln.</summary>
function SymbolWidth(APPI: Integer): Integer;
const
  cIconPad = 4;
begin
  Result := TAtlasSymbol.PixelSize(TAtlasSymbol.cMenuSize + cIconPad, APPI);
end;

/// <summary>Breite der Plakette samt Abstand in Gerätepixeln; 0 ohne.</summary>
function BadgeWidth(ABar: TStatusBar; ACount: Integer): Integer;
const
  cBadgePad = 18;
begin
  Result := 0;
  if (ACount <= 0) or (ABar = nil) then
  begin
    Exit;
  end;
  ABar.Canvas.Font := ABar.Font;
  Result := ABar.Canvas.TextWidth(TAtlasStatusFieldPlan.BadgeText(ACount)) + MulDiv(cBadgePad, ABar.CurrentPPI, 96);
end;

/// <summary>Statusleiste des obersten Editorfensters; nil ohne.</summary>
function TopEditorBar: TStatusBar;
var
  mServices: INTAEditorServices;
  mWindow: INTAEditWindow;
begin
  Result := nil;
  if Supports(BorlandIDEServices, INTAEditorServices, mServices) then
  begin
    mWindow := mServices.TopEditWindow;
    if mWindow <> nil then
    begin
      Result := mWindow.StatusBar;
    end;
  end;
end;

/// <summary>Atlas-Symbol (#751) an ALeft; liefert die linke Kante dahinter.</summary>
function DrawSymbol(ACanvas: TCanvas; APPI, ALeft, ACenter: Integer): Integer;
var
  mSymbol: TWICImage;
  mPixels: Integer;
  mTarget: TRect;
begin
  Result := ALeft;
  mSymbol := TAtlasSymbolImages.Cached(TAtlasIdeSymbol.Current, TAtlasSymbol.cMenuSize, APPI);
  if mSymbol = nil then
  begin
    Exit;
  end;
  mPixels := TAtlasSymbol.PixelSize(TAtlasSymbol.cMenuSize, APPI);
  mTarget := Bounds(ALeft + 2, ACenter - mPixels div 2, mPixels, mPixels);
  if mSymbol.Width = mPixels then
  begin
    ACanvas.Draw(mTarget.Left, mTarget.Top, mSymbol);
  end
  else
  begin
    ACanvas.StretchDraw(mTarget, mSymbol);
  end;
  Result := ALeft + SymbolWidth(APPI);
end;

/// <summary>Plakette der Benachrichtigungen (#601) von ALeft bis zum rechten Rand von ARect.</summary>
procedure DrawBadge(ACanvas: TCanvas; const ARect: TRect; ALeft, APPI: Integer; const AView: TAtlasStatusFieldView;
  const ASignals: TAtlasSignals);
const
  cInset = 3;
var
  mInset: Integer;
  mBadge: TRect;
  mText: string;
begin
  mInset := MulDiv(cInset, APPI, 96);
  mBadge.Left := ALeft + mInset;
  mBadge.Top := ARect.Top + mInset;
  mBadge.Right := ARect.Right - mInset;
  mBadge.Bottom := ARect.Bottom - mInset;
  ACanvas.Pen.Color := TColor(TAtlasStatusSignal.ForState(ASignals, AView.BadgeState).Solid);
  ACanvas.Brush.Color := TColor(TAtlasStatusSignal.ForState(ASignals, AView.BadgeState).Solid);
  ACanvas.Brush.Style := bsSolid;
  ACanvas.RoundRect(mBadge.Left, mBadge.Top, mBadge.Right, mBadge.Bottom, mBadge.Height, mBadge.Height);
  ACanvas.Brush.Style := bsClear;
  ACanvas.Font.Color := TColor(TAtlasStatusSignal.ForState(ASignals, AView.BadgeState).OnSolid);
  mText := TAtlasStatusFieldPlan.BadgeText(AView.BadgeCount);
  DrawText(ACanvas.Handle, PChar(mText), -1, mBadge, DT_SINGLELINE or DT_CENTER or DT_VCENTER or DT_NOPREFIX);
  ACanvas.Font.Color := StyleServices.GetSystemColor(clBtnText);
end;

/// <summary>Atlas-Feld in ARect: Symbol, Punkt im Gesamtzustand, Kurztext und Plakette.</summary>
procedure DrawField(ABar: TStatusBar; const ARect: TRect; const AView: TAtlasStatusFieldView);
const
  cRadius = 4;
  cRadiusSteps = 4;
var
  mCanvas: TCanvas;
  mPPI, mRadius, mCenter, mLeft: Integer;
  mSignals: TAtlasSignals;
  mPart: TRect;
  mText: string;
begin
  mCanvas := ABar.Canvas;
  mPPI := ABar.CurrentPPI;
  mCanvas.Font := ABar.Font;
  mCanvas.Font.Color := StyleServices.GetSystemColor(clBtnText);
  mRadius := MulDiv(cRadius, mPPI, 96);
  mCenter := (ARect.Top + ARect.Bottom) div 2;
  mLeft := DrawSymbol(mCanvas, mPPI, ARect.Left, mCenter);
  // Signalfarben der Statusleiste der IDE (Fläche clBtnFace), nicht der Editorfläche (#1255).
  mSignals := TAtlasIdeStyle.ChromeColors.Signals;
  mCanvas.Pen.Color := TColor(TAtlasStatusSignal.ForState(mSignals, AView.State).Ring);
  mCanvas.Brush.Color := TColor(TAtlasStatusSignal.ForState(mSignals, AView.State).Fill);
  mCanvas.Brush.Style := bsSolid;
  mCanvas.Ellipse(mLeft + 2 * mRadius - mRadius, mCenter - mRadius, mLeft + 2 * mRadius + mRadius + 1,
    mCenter + mRadius + 1);
  mCanvas.Brush.Style := bsClear;
  mPart := ARect;
  mPart.Left := mLeft + cRadiusSteps * mRadius + MulDiv(2, mPPI, 96);
  // Plakette der Benachrichtigungen (#601) ganz rechts, der Text endet davor.
  if AView.BadgeCount > 0 then
  begin
    mPart.Right := mPart.Right - BadgeWidth(ABar, AView.BadgeCount);
    DrawBadge(mCanvas, ARect, mPart.Right, mPPI, AView, mSignals);
  end;
  mText := AView.Text;
  mCanvas.Brush.Style := bsClear;
  DrawText(mCanvas.Handle, PChar(mText), -1, mPart, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
  mCanvas.Brush.Style := bsSolid;
end;

{ TAtlasIdeStatusFieldSurface.TFieldPanel }

destructor TAtlasIdeStatusFieldSurface.TFieldPanel.Destroy;
begin
  if Assigned(OnGone) then
  begin
    OnGone(Self);
  end;
  inherited Destroy;
end;

{ TAtlasIdeStatusFieldSurface.THook }

constructor TAtlasIdeStatusFieldSurface.THook.Create;
begin
  inherited Create;
  Extras := TList<TFieldPanel>.Create;
  Zone := -1;
end;

destructor TAtlasIdeStatusFieldSurface.THook.Destroy;
var
  mItem: TFieldPanel;
begin
  // Noch lebende Panels dürfen den freigegebenen Haken nicht mehr rufen.
  if Panel <> nil then
  begin
    Panel.OnGone := nil;
  end;
  for mItem in Extras do
  begin
    if mItem <> nil then
    begin
      mItem.OnGone := nil;
    end;
  end;
  Extras.Free;
  // Nur noch da, wenn die Leiste schon weg ist (FDead): nichts mehr an ihr zurückzusetzen.
  TAtlasWndProcHook.Forget(WndHook);
  inherited Destroy;
end;

procedure TAtlasIdeStatusFieldSurface.THook.WndProc(var AMessage: TMessage);
begin
  if (Surface = nil) or not Swallow(AMessage) then
  begin
    WndHook.CallOld(AMessage);
  end;
end;

function TAtlasIdeStatusFieldSurface.THook.NewPanel(AStyle: TStatusPanelStyle): TFieldPanel;
begin
  Result := TFieldPanel.Create(Bar.Panels);
  Result.Style := AStyle;
  Result.Bevel := pbNone;
  Result.OnGone := PanelGone;
end;

procedure TAtlasIdeStatusFieldSurface.THook.DropPanel(APanel: TFieldPanel);
var
  mIndex: Integer;
begin
  if APanel = nil then
  begin
    Exit;
  end;
  APanel.OnGone := nil;
  // Nur über Zeigervergleich suchen: APanel.Index liest schon die Sammlung.
  for mIndex := Bar.Panels.Count - 1 downto 0 do
  begin
    if Bar.Panels[mIndex] = APanel then
    begin
      Bar.Panels.Delete(mIndex);
      Exit;
    end;
  end;
end;

procedure TAtlasIdeStatusFieldSurface.THook.PanelGone(Sender: TObject);
var
  mIndex: Integer;
begin
  if Sender = Panel then
  begin
    Panel := nil;
  end;
  for mIndex := 0 to Extras.Count - 1 do
  begin
    if Extras[mIndex] = Sender then
    begin
      Extras[mIndex] := nil;
    end;
  end;
  // Das nächste Show legt das Panel neu an.
  if Surface <> nil then
  begin
    Surface.RequestTick;
  end;
end;

function TAtlasIdeStatusFieldSurface.THook.PanelRect(APanel: TStatusPanel): TRect;
begin
  Result := Rect(0, 0, 0, 0);
  if (APanel = nil) or not Bar.HandleAllocated or (APanel.Width <= 0) then
  begin
    Exit;
  end;
  SendMessage(Bar.Handle, SB_GETRECT, APanel.Index, LPARAM(@Result));
end;

function TAtlasIdeStatusFieldSurface.THook.PanelRect: TRect;
begin
  Result := PanelRect(Panel);
end;

function TAtlasIdeStatusFieldSurface.THook.ScreenCorner(const ARect: TRect): TPoint;
begin
  Result := Bar.ClientToScreen(Point(ARect.Left, ARect.Top));
end;

function TAtlasIdeStatusFieldSurface.THook.ZoneAt(AX, AY: Integer): Integer;
var
  mIndex: Integer;
begin
  if PtInRect(PanelRect, Point(AX, AY)) then
  begin
    Exit(0);
  end;
  for mIndex := 0 to Extras.Count - 1 do
  begin
    if PtInRect(PanelRect(Extras[mIndex]), Point(AX, AY)) then
    begin
      Exit(mIndex + 1);
    end;
  end;
  Result := -1;
end;

function TAtlasIdeStatusFieldSurface.THook.HintOf(AZone: Integer): string;
begin
  Result := '';
  if (Surface <> nil) and Assigned(Surface.FInput.HintOf) then
  begin
    Result := Surface.FInput.HintOf(AZone);
  end;
end;

procedure TAtlasIdeStatusFieldSurface.THook.SyncExtras(const AView: TAtlasStatusFieldView);
const
  cItemPad = 16;
var
  mIndex: Integer;
  mItem: TFieldPanel;
begin
  while Extras.Count > Length(AView.Extras) do
  begin
    DropPanel(Extras.Last);
    Extras.Delete(Extras.Count - 1);
  end;
  while Extras.Count < Length(AView.Extras) do
  begin
    Extras.Add(nil);
  end;
  for mIndex := 0 to Extras.Count - 1 do
  begin
    // Neu oder von der IDE gelöscht.
    if Extras[mIndex] = nil then
    begin
      Extras[mIndex] := NewPanel(psText);
    end;
    mItem := Extras[mIndex];
    mItem.Text := AView.Extras[mIndex];
    mItem.Width := Bar.Canvas.TextWidth(AView.Extras[mIndex]) + MulDiv(cItemPad, Bar.CurrentPPI, 96);
  end;
end;

procedure TAtlasIdeStatusFieldSurface.THook.Layout(const AView: TAtlasStatusFieldView);
const
  cShownPad = 30;
var
  mFirst: TFieldPanel;
begin
  // Feld aus oder in die Atlas-Statusleiste umgezogen: Panel entfernen statt 0 breit lassen. Das letzte Panel
  // einer TStatusBar reicht bis zum rechten Rand, gleich welche Breite es hat; ein 0 breites Atlas-Panel am Ende
  // zeichnete das Feld sonst trotzdem (nur ohne Klick).
  Bar.Canvas.Font := Bar.Font;
  if not AView.Panel then
  begin
    DropPanel(Panel);
    Panel := nil;
  end
  else
  begin
    // Neu, nach dem Ausblenden oder von der IDE gelöscht (PanelGone): anlegen, vor den Zusatzfeldern.
    if Panel = nil then
    begin
      Panel := NewPanel(psOwnerDraw);
      for mFirst in Extras do
      begin
        if mFirst <> nil then
        begin
          Panel.Index := mFirst.Index;
          Break;
        end;
      end;
    end;
    // Text nur zum Erkennen und für Screenreader; gezeichnet wird in DrawPanel.
    Panel.Text := AView.Text;
    Panel.Width := Bar.Canvas.TextWidth(AView.Text) + MulDiv(cShownPad, Bar.CurrentPPI, 96) +
      SymbolWidth(Bar.CurrentPPI) + BadgeWidth(Bar, AView.BadgeCount);
  end;
  SyncExtras(AView);
  // Zusatzfeld verschwunden oder Feld aus: Tooltip des Panels unter der Maus neu bestimmen.
  if Zone >= 0 then
  begin
    Bar.Hint := HintOf(Zone);
  end;
  Bar.Invalidate;
end;

procedure TAtlasIdeStatusFieldSurface.THook.Restore;
var
  mOwner: TAtlasIdeStatusFieldSurface;
  mDraw, mCurrentDraw: TDrawPanelEvent;
  mMouseUp, mCurrentUp: TMouseEvent;
  mMouseMove, mCurrentMove: TMouseMoveEvent;
  mIndex: Integer;
begin
  if Bar = nil then
  begin
    Exit;
  end;
  mOwner := Surface;
  Surface := nil;
  // Fremde WindowProc darüber: Der Haken der WindowProc bleibt in deren Kette und reicht ab jetzt nur noch durch;
  // Unhook kennzeichnet das Entladen dann als unsicher (Protokoll, Diagnose, Neustart).
  TAtlasWndProcHook.Unhook(WndHook);
  if mOwner <> nil then
  begin
    Bar.RemoveFreeNotification(mOwner.FWatch);
  end;
  // Nur zurücksetzen, was noch unser ist: Eine andere Erweiterung kann sich danach eingehängt haben.
  mDraw := DrawPanel;
  mCurrentDraw := Bar.OnDrawPanel;
  if SameMethod(TMethod(mCurrentDraw), TMethod(mDraw)) then
  begin
    Bar.OnDrawPanel := OldDraw;
  end;
  mMouseUp := BarMouseUp;
  mCurrentUp := Bar.OnMouseUp;
  if SameMethod(TMethod(mCurrentUp), TMethod(mMouseUp)) then
  begin
    Bar.OnMouseUp := OldMouseUp;
  end;
  mMouseMove := BarMouseMove;
  mCurrentMove := Bar.OnMouseMove;
  if SameMethod(TMethod(mCurrentMove), TMethod(mMouseMove)) then
  begin
    Bar.OnMouseMove := OldMouseMove;
  end;
  if Zone >= 0 then
  begin
    Bar.Hint := OldHint;
    Bar.ShowHint := OldShowHint;
  end;
  for mIndex := Extras.Count - 1 downto 0 do
  begin
    DropPanel(Extras[mIndex]);
  end;
  Extras.Clear;
  DropPanel(Panel);
  Panel := nil;
end;

procedure TAtlasIdeStatusFieldSurface.THook.DrawPanel(AStatusBar: TStatusBar; APanel: TStatusPanel;
  const ARect: TRect);
begin
  if Surface = nil then
  begin
    Exit;
  end;
  if APanel <> Panel then
  begin
    if Assigned(OldDraw) then
    begin
      OldDraw(AStatusBar, APanel, ARect);
    end;
    Exit;
  end;
  try
    DrawField(AStatusBar, ARect, Surface.FView);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Status, E);
  end;
end;

procedure TAtlasIdeStatusFieldSurface.THook.BarMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  if Surface = nil then
  begin
    Exit;
  end;
  if (Button = mbLeft) and SkipUp then
  begin
    // Loslassen nach dem Doppelklick: Die Schnellschalter sind schon unterwegs.
    SkipUp := False;
    Exit;
  end;
  if (Button = mbLeft) and Click(ZoneAt(X, Y), X) then
  begin
    Exit;
  end;
  if Assigned(OldMouseUp) then
  begin
    OldMouseUp(Sender, Button, Shift, X, Y);
  end;
end;

procedure TAtlasIdeStatusFieldSurface.THook.BarMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  mZone: Integer;
begin
  if Surface = nil then
  begin
    Exit;
  end;
  mZone := ZoneAt(X, Y);
  if mZone <> Zone then
  begin
    if mZone >= 0 then
    begin
      // Erst beim Betreten eines unserer Panels den Tooltip der Leiste merken.
      if Zone < 0 then
      begin
        OldHint := Bar.Hint;
        OldShowHint := Bar.ShowHint;
      end;
      Bar.Hint := HintOf(mZone);
      Bar.ShowHint := True;
    end
    else
    begin
      Bar.Hint := OldHint;
      Bar.ShowHint := OldShowHint;
    end;
    Application.CancelHint;
    Zone := mZone;
  end;
  if Assigned(OldMouseMove) then
  begin
    OldMouseMove(Sender, Shift, X, Y);
  end;
end;

function TAtlasIdeStatusFieldSurface.THook.Click(AZone, AX: Integer): Boolean;
var
  mField, mZone: TPoint;
begin
  Result := False;
  if not Assigned(Surface.FInput.OnClick) then
  begin
    Exit;
  end;
  mField := ScreenCorner(PanelRect);
  mZone := mField;
  if (AZone > 0) and (AZone <= Extras.Count) then
  begin
    mZone := ScreenCorner(PanelRect(Extras[AZone - 1]));
  end;
  Result := Surface.FInput.OnClick(AZone, AX, PanelRect.Right - BadgeWidth(Bar, Surface.FView.BadgeCount), mField,
    mZone);
end;

function TAtlasIdeStatusFieldSurface.THook.Swallow(var AMessage: TMessage): Boolean;
var
  mPosition: TPoint;
  mKeyboard, mInPanel: Boolean;
begin
  Result := False;
  if not Assigned(Surface.FInput.OpensToggles) then
  begin
    Exit;
  end;
  case AMessage.Msg of
    WM_LBUTTONDOWN:
      // Ging das Loslassen nach einem Doppelklick verloren, gilt der nächste Klick wieder.
      SkipUp := False;
    WM_RBUTTONDOWN, WM_RBUTTONUP:
      Result := Surface.FInput.OpensToggles(TAtlasStatusFieldGesture.RightButton,
        PtInRect(PanelRect, SmallPointToPoint(TWMMouse(AMessage).Pos)), False);
    WM_LBUTTONDBLCLK:
      Result := Surface.FInput.OpensToggles(TAtlasStatusFieldGesture.DoubleClick,
        PtInRect(PanelRect, SmallPointToPoint(TWMMouse(AMessage).Pos)), False);
    WM_CONTEXTMENU:
      begin
        // -1/-1 kommt von der Tastatur (Umschalt+F10): der IDE überlassen.
        mKeyboard := (TWMContextMenu(AMessage).XPos = -1) and (TWMContextMenu(AMessage).YPos = -1);
        mInPanel := False;
        if not mKeyboard then
        begin
          mPosition := Bar.ScreenToClient(SmallPointToPoint(TWMContextMenu(AMessage).Pos));
          mInPanel := PtInRect(PanelRect, mPosition);
        end;
        Result := Surface.FInput.OpensToggles(TAtlasStatusFieldGesture.ContextMenu, mInPanel, mKeyboard);
      end;
  end;
  if not Result then
  begin
    Exit;
  end;
  // Über dem Feld weder die Standardbehandlung (erzeugt WM_CONTEXTMENU) noch die IDE.
  if AMessage.Msg = WM_LBUTTONDBLCLK then
  begin
    SkipUp := True;
  end;
  if (AMessage.Msg = WM_RBUTTONUP) or (AMessage.Msg = WM_LBUTTONDBLCLK) then
  begin
    PostMessage(Surface.FWnd, cWM_ATLAS_STATUS_CONTEXT, 0, LPARAM(Bar));
  end;
  AMessage.Result := 0;
end;

{ TAtlasIdeStatusFieldSurface.TWatch }

procedure TAtlasIdeStatusFieldSurface.TWatch.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (FSurface <> nil) then
  begin
    FSurface.Gone(AComponent);
  end;
end;

{ TAtlasIdeStatusFieldSurface }

constructor TAtlasIdeStatusFieldSurface.Create;
begin
  inherited Create;
  FHooks := TObjectList<THook>.Create(True);
  FDead := TObjectList<THook>.Create(True);
  FWatch := TWatch.Create(nil);
  FWatch.FSurface := Self;
  FNotifierIndex := -1;
end;

destructor TAtlasIdeStatusFieldSurface.Destroy;
begin
  Detach;
  FWatch.FSurface := nil;
  FreeAndNil(FWatch);
  FreeAndNil(FHooks);
  FreeAndNil(FDead);
  inherited Destroy;
end;

procedure TAtlasIdeStatusFieldSurface.Attach(const AInput: TAtlasStatusFieldInput);
var
  mEditor: IOTAEditorServices;
begin
  FInput := AInput;
  if FWnd = 0 then
  begin
    FWnd := AllocateHWnd(WndProc);
  end;
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(nil);
    FTimer.Enabled := False;
    FTimer.Interval := cRedrawMs;
    FTimer.OnTimer := TimerTick;
  end;
  if (FNotifierIndex < 0) and Supports(BorlandIDEServices, IOTAEditorServices, mEditor) then
  begin
    FNotifierIndex := mEditor.AddNotifier(TFieldNotifier.Create(Self));
  end;
end;

procedure TAtlasIdeStatusFieldSurface.Detach;
var
  mEditor: IOTAEditorServices;
begin
  FInput := Default(TAtlasStatusFieldInput);
  if (FNotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAEditorServices, mEditor) then
  begin
    mEditor.RemoveNotifier(FNotifierIndex);
  end;
  FNotifierIndex := -1;
  FreeAndNil(FTimer);
  if FWnd <> 0 then
  begin
    DeallocateHWnd(FWnd);
  end;
  FWnd := 0;
  FreeWindow;
  try
    Unhook;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Status, E);
  end;
  FView := Default(TAtlasStatusFieldView);
end;

procedure TAtlasIdeStatusFieldSurface.FreeWindow;
begin
  if FWindow = nil then
  begin
    Exit;
  end;
  FWindow.RemoveFreeNotification(FWatch);
  FreeAndNil(FWindow);
end;

procedure TAtlasIdeStatusFieldSurface.Gone(AComponent: TComponent);
var
  mIndex: Integer;
begin
  if AComponent = FWindow then
  begin
    FWindow := nil;
  end;
  if FHooks = nil then
  begin
    Exit;
  end;
  for mIndex := FHooks.Count - 1 downto 0 do
  begin
    if FHooks[mIndex].Bar = AComponent then
    begin
      FHooks[mIndex].Surface := nil;
      FDead.Add(FHooks.Extract(FHooks[mIndex]));
    end;
  end;
end;

function TAtlasIdeStatusFieldSurface.HookOf(ABar: TStatusBar): THook;
var
  mHook: THook;
begin
  Result := nil;
  if ABar = nil then
  begin
    Exit;
  end;
  for mHook in FHooks do
  begin
    if mHook.Bar = ABar then
    begin
      Exit(mHook);
    end;
  end;
end;

procedure TAtlasIdeStatusFieldSurface.HookBar(ABar: TStatusBar);
var
  mHook: THook;
begin
  if (ABar = nil) or (HookOf(ABar) <> nil) then
  begin
    Exit;
  end;
  mHook := THook.Create;
  mHook.Surface := Self;
  mHook.Bar := ABar;
  mHook.OldDraw := ABar.OnDrawPanel;
  mHook.OldMouseUp := ABar.OnMouseUp;
  mHook.OldMouseMove := ABar.OnMouseMove;
  mHook.OldHint := ABar.Hint;
  mHook.OldShowHint := ABar.ShowHint;
  // Das Atlas-Panel legt Layout an, nur wenn das Feld in der Statuszeile steht.
  mHook.Panel := nil;
  ABar.OnDrawPanel := mHook.DrawPanel;
  ABar.OnMouseUp := mHook.BarMouseUp;
  ABar.OnMouseMove := mHook.BarMouseMove;
  mHook.WndHook := TAtlasWndProcHook.Create(ABar, mHook.WndProc);
  FHooks.Add(mHook);
  ABar.FreeNotification(FWatch);
end;

function TAtlasIdeStatusFieldSurface.EditorBars: TArray<TStatusBar>;
var
  mServices: INTAEditorServices;
  mIndex: Integer;
  mWindow: INTAEditWindow;
  mHook: THook;
  mBars: TList<TStatusBar>;
begin
  mBars := TList<TStatusBar>.Create;
  try
    if Supports(BorlandIDEServices, INTAEditorServices, mServices) then
    begin
      for mIndex := 0 to mServices.EditWindowCount - 1 do
      begin
        mWindow := mServices.EditWindow[mIndex];
        if (mWindow <> nil) and (mWindow.StatusBar <> nil) then
        begin
          mBars.Add(mWindow.StatusBar);
        end;
      end;
    end;
    for mHook in FHooks do
    begin
      if mBars.IndexOf(mHook.Bar) < 0 then
      begin
        mBars.Add(mHook.Bar);
      end;
    end;
    Result := mBars.ToArray;
  finally
    mBars.Free;
  end;
end;

procedure TAtlasIdeStatusFieldSurface.WndProc(var AMessage: TMessage);
var
  mHook: THook;
begin
  if AMessage.Msg = cWM_ATLAS_STATUS then
  begin
    if (FTimer <> nil) and not FTimer.Enabled then
    begin
      FTimer.Enabled := True;
    end;
    AMessage.Result := 0;
  end
  else if AMessage.Msg = cWM_ATLAS_STATUS_CONTEXT then
  begin
    // Die Leiste kann inzwischen geschlossen sein: nur bekannte Leisten.
    mHook := HookOf(TStatusBar(AMessage.LParam));
    if (mHook <> nil) and Assigned(FInput.OnContext) then
    begin
      FInput.OnContext(mHook.ScreenCorner(mHook.PanelRect));
    end;
    AMessage.Result := 0;
  end
  else
  begin
    AMessage.Result := DefWindowProc(FWnd, AMessage.Msg, AMessage.WParam, AMessage.LParam);
  end;
end;

procedure TAtlasIdeStatusFieldSurface.TimerTick(Sender: TObject);
begin
  FTimer.Enabled := False;
  AtomicExchange(FPosted, 0);
  if Assigned(FInput.OnTick) then
  begin
    FInput.OnTick();
  end;
end;

procedure TAtlasIdeStatusFieldSurface.RequestTick;
begin
  // Nur eine Nachricht unterwegs; der Zeitgeber fasst alles in 250 ms zusammen.
  if (FWnd <> 0) and (AtomicExchange(FPosted, 1) = 0) then
  begin
    PostMessage(FWnd, cWM_ATLAS_STATUS, 0, 0);
  end;
end;

procedure TAtlasIdeStatusFieldSurface.Show(const AView: TAtlasStatusFieldView);
var
  mBar: TStatusBar;
  mHook: THook;
begin
  FView := AView;
  // Neue Editorfenster bekommen hier ihr Feld.
  for mBar in EditorBars do
  begin
    HookBar(mBar);
    mHook := HookOf(mBar);
    if mHook <> nil then
    begin
      mHook.Layout(FView);
    end;
  end;
end;

procedure TAtlasIdeStatusFieldSurface.Unhook;
var
  mHook: THook;
begin
  if FHooks = nil then
  begin
    Exit;
  end;
  for mHook in FHooks do
  begin
    mHook.Restore;
  end;
  // Liegt eine fremde WindowProc darüber, bleibt nur der kleine TAtlasWndProcHook in deren Kette; der Haken selbst
  // wird von der Leiste nicht mehr gerufen.
  FHooks.Clear;
end;

function TAtlasIdeStatusFieldSurface.FieldCorner(out APoint: TPoint): Boolean;
var
  mHook: THook;
  mArea: TRect;
begin
  APoint := Point(0, 0);
  mHook := HookOf(TopEditorBar);
  Result := (mHook <> nil) and mHook.Bar.Visible;
  if Result then
  begin
    mArea := mHook.PanelRect;
    Result := not mArea.IsEmpty;
  end;
  if Result then
  begin
    APoint := mHook.ScreenCorner(mArea);
  end;
end;

function TAtlasIdeStatusFieldSurface.WindowOpen: Boolean;
begin
  Result := FWindow <> nil;
end;

procedure TAtlasIdeStatusFieldSurface.OpenWindow(const AItems: TArray<IAtlasStatusItem>; const APoint: TPoint;
  const AOnOpenLog, AOnRestart: TProc);
begin
  FreeWindow;
  FWindow := TAtlasStatusWindow.CreateStatus(Application, TAtlasIdeStyle.Colors);
  FWindow.FreeNotification(FWatch);
  FWindow.OnOpenLog := AOnOpenLog;
  FWindow.OnRestart := AOnRestart;
  FWindow.SetItems(AItems);
  FWindow.ShowAbove(APoint);
end;

procedure TAtlasIdeStatusFieldSurface.CloseWindow;
begin
  if FWindow <> nil then
  begin
    FWindow.Dismiss;
  end;
end;

procedure TAtlasIdeStatusFieldSurface.WindowItems(const AItems: TArray<IAtlasStatusItem>);
begin
  if FWindow <> nil then
  begin
    FWindow.SetItems(AItems);
  end;
end;

end.
