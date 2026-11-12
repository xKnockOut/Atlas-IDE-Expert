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
//   Ist das Feld in die Atlas-Statusleiste umgezogen (Relocated, 0 breit),
//   zeigt die Leiste die Plakette (Badge, ClickBadge, #1234),
//   bei eingeschalteten Benachrichtigungen immer, auch mit 0.
// - Die Panels gehören der Leiste, und die IDE löscht sie unter Umständen
//   selbst (Delphi 12: Absturz in PanelRect über ein freigegebenes Panel).
//   Deshalb sind sie vom eigenen Typ TFieldPanel und melden ihre Freigabe dem
//   Haken; der vergisst sie, und das nächste Refresh legt sie neu an.
// - Atlas-Statusleiste (#1155): Zeigt sie das Element status (Relocated),
//   ist das Atlas-Panel 0 breit; die Leiste liest Text, State und Tooltip und
//   öffnet über OpenWindowAt bzw. ContextAt dasselbe Statusfenster bzw. die
//   Schnellschalter. Anchor fragt dann OnRelocatedAnchor (Element der Leiste).
//   Die Zusatzfelder ziehen mit um: In der Statuszeile stehen sie dann nicht,
//   die Leiste liest sie über ExtraItems und klickt über ClickExtra.

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
  Atlas.UI.Foundation.WndProcHook,
  Atlas.UI.Status.Window;

type
  /// <summary>Linke Oberkante eines Felds (Bildschirm); False ohne.</summary>
  TAtlasStatusAnchorFunc = reference to function(out APoint: TPoint): Boolean;

  /// <summary>Plakette der Benachrichtigungen (#601).</summary>
  TAtlasStatusBadge = record
    /// <summary>Benachrichtigungen an: die Atlas-Statusleiste zeigt die Plakette auch mit 0.</summary>
    Shown: Boolean;
    Count: Integer;
    State: TAtlasStatusState;
    Hint: string;
    /// <summary>Linksklick auf die Plakette mit der linken Oberkante des Felds.</summary>
    OnClick: TProc<TPoint>;
  end;

  /// <summary>Zusatzfeld für die Atlas-Statusleiste (#1155): Kennung, Text, Tooltip und ob ein Klick etwas tut.
  /// </summary>
  TAtlasStatusExtraItem = record
    Id: string;
    Text: string;
    Hint: string;
    Clickable: Boolean;
  end;

  /// <summary>Stand des letzten Refresh: sichtbare Zeilen, Kurztext, Tooltip und Gesamtzustand.</summary>
  TAtlasStatusShown = record
    Items: TArray<IAtlasStatusItem>;
    Text: string;
    Tooltip: string;
    State: TAtlasStatusState;
  end;

  /// <summary>Ereignisse des Felds; gesetzt von der Kompositionswurzel.</summary>
  TAtlasStatusFieldEvents = record
    OnRefresh: TProc;
    OnOpenLog: TProc;
    OnRestart: TProc;
    OnContext: TProc<TPoint>;
    OnRelocatedAnchor: TAtlasStatusAnchorFunc;
  end;

  TAtlasStatusField = class(TComponent)
  public const
    cRedrawMs = 250;
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

    /// <summary>Eine eingehängte Statusleiste: ihre Panels, die verketteten Handler und deren Behandlung.</summary>
    THook = class
    public
      /// <summary>Feld des Hakens; nil, wenn die Leiste geht oder ausgehängt ist.</summary>
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
      procedure SyncExtras;
      /// <summary>Panels anlegen, beschriften und messen (Refresh); AShown: Atlas-Feld sichtbar.</summary>
      procedure Layout(AShown: Boolean);
      /// <summary>Handler und Tooltip der Leiste zurücksetzen, soweit sie noch unsere sind; Panels entfernen.</summary>
      procedure Restore;
      procedure OpenWindow;
      procedure DrawPanel(AStatusBar: TStatusBar; APanel: TStatusPanel; const ARect: TRect);
      procedure BarMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
      procedure BarMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
      /// <summary>Linksklick in AZone an X; False, wenn die Zone keins unserer Panels ist.</summary>
      function Click(AZone, AX: Integer): Boolean;
      /// <summary>Mausnachricht über dem Feld für die Schnellschalter abfangen; True, wenn geschluckt.</summary>
      function Swallow(var AMessage: TMessage): Boolean;
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
    FShown: TAtlasStatusShown;
    FEvents: TAtlasStatusFieldEvents;
    FExtras: TArray<TExtra>;
    FBadge: TAtlasStatusBadge;
    procedure WndProc(var AMessage: TMessage);
    procedure TimerTick(Sender: TObject);
    procedure Refresh;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(const ARegistry: IAtlasStatusRegistry); reintroduce;
    destructor Destroy; override;
    /// <summary>Neu zeichnen anfordern; aus jedem Thread, gesammelt auf höchstens alle 250 ms.</summary>
    procedure RequestRefresh;
    /// <summary>Vor jedem Zeichnen im Hauptthread.</summary>
    property OnRefresh: TProc read FEvents.OnRefresh write FEvents.OnRefresh;
    property OnOpenLog: TProc read FEvents.OnOpenLog write FEvents.OnOpenLog;
    property OnRestart: TProc read FEvents.OnRestart write FEvents.OnRestart;
    /// <summary>Rechtsklick und Doppelklick auf das Feld; Punkt = linke Oberkante des Felds (Bildschirm).</summary>
    property OnContext: TProc<TPoint> read FEvents.OnContext write FEvents.OnContext;
    /// <summary>Linke Oberkante des Felds im obersten Editorfenster (Bildschirm); False ohne Feld. Umgezogen:
    /// OnRelocatedAnchor.</summary>
    function Anchor(out APoint: TPoint): Boolean;
    /// <summary>Zeigt die Atlas-Statusleiste das Element status (#1155)? Dann ist das Panel 0 breit.</summary>
    class function Relocated: Boolean; static;
    /// <summary>Statusfenster über APoint (Bildschirm, linke Oberkante des Felds) öffnen; ein zweiter Aufruf
    /// schließt es.</summary>
    procedure OpenWindowAt(const APoint: TPoint);
    /// <summary>Schnellschalter über APoint wie beim Rechtsklick auf das Feld.</summary>
    procedure ContextAt(const APoint: TPoint);
    /// <summary>Kurztext, Gesamtzustand und Tooltip des letzten Refresh.</summary>
    property Text: string read FShown.Text;
    property State: TAtlasStatusState read FShown.State;
    property Tooltip: string read FShown.Tooltip;
    property OnRelocatedAnchor: TAtlasStatusAnchorFunc read FEvents.OnRelocatedAnchor
      write FEvents.OnRelocatedAnchor;
    /// <summary>Zusatzfeld AId setzen (Text, Tooltip, Linksklick mit der linken Oberkante des Panels); AText ''
    /// entfernt es. Nur im Hauptthread.</summary>
    procedure SetExtra(const AId, AText, AHint: string; const AOnClick: TProc<TPoint>);
    /// <summary>Plakette der Benachrichtigungen (#601): Count ungelesene (im Feld 0 = keine Plakette, in der
    /// Atlas-Statusleiste zählt Shown), Farbe nach State, Hint im Tooltip; Linksklick auf die Plakette ruft
    /// OnClick mit der linken Oberkante des Felds. Nur im Hauptthread.</summary>
    procedure SetBadge(const ABadge: TAtlasStatusBadge);
    /// <summary>Plakette für die Atlas-Statusleiste (#1234): Bei Relocated ist das Feld 0 breit, die Leiste zeigt
    /// sie dann selbst (Shown, Count, State, Hint).</summary>
    property Badge: TAtlasStatusBadge read FBadge;
    /// <summary>Wie ein Klick auf die Plakette, Liste mit der linken Oberkante an APoint (#1234).</summary>
    procedure ClickBadge(const APoint: TPoint);
    /// <summary>Zusatzfelder in ihrer Reihenfolge, für die Atlas-Statusleiste: Bei Relocated stehen sie nicht in
    /// der Statuszeile.</summary>
    function ExtraItems: TArray<TAtlasStatusExtraItem>;
    /// <summary>Wie ein Klick auf das Zusatzfeld AId mit der linken Oberkante an APoint; ohne Feld nichts.</summary>
    procedure ClickExtra(const AId: string; const APoint: TPoint);
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
  Atlas.Core.Settings.StatusBarItems,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.Core.Style.Symbol,
  Atlas.Core.Style.Signal,
  Atlas.UI.Style.Symbol,
  Atlas.IDE.Foundation.Symbol;

const
  cWM_ATLAS_STATUS = WM_USER + 591;
  // LParam = TStatusBar; erst nach der Mausnachricht ausgeführt, ein freigegebenes Feld verwirft sie mit seinem
  // Fenster.
  cWM_ATLAS_STATUS_CONTEXT = WM_USER + 592;

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

function SameMethod(const ALeft, ARight: TMethod): Boolean;
begin
  Result := (ALeft.Code = ARight.Code) and (ALeft.Data = ARight.Data);
end;

/// <summary>Platz für das Symbol samt Abstand in Gerätepixeln.</summary>
function SymbolWidth(APPI: Integer): Integer;
begin
  Result := TAtlasSymbol.PixelSize(TAtlasSymbol.cMenuSize + 4, APPI);
end;

function BadgeText(ACount: Integer): string;
begin
  if ACount > 99 then
  begin
    Result := '99+';
  end
  else
  begin
    Result := IntToStr(ACount);
  end;
end;

/// <summary>Breite der Plakette samt Abstand in Gerätepixeln; 0 ohne.</summary>
function BadgeWidth(ABar: TStatusBar; ACount: Integer): Integer;
begin
  Result := 0;
  if (ACount <= 0) or (ABar = nil) then
  begin
    Exit;
  end;
  ABar.Canvas.Font := ABar.Font;
  Result := ABar.Canvas.TextWidth(BadgeText(ACount)) + MulDiv(18, ABar.CurrentPPI, 96);
end;

/// <summary>Atlas-Panel in der Statuszeile zeigen: statusField.enabled und nicht in die Statusleiste umgezogen.
/// </summary>
function PanelShown: Boolean;
begin
  Result := TAtlasIdeSettings.Current.StatusField and not TAtlasStatusField.Relocated;
end;

/// <summary>Was das Feld nach den Einstellungen zeigt; der Tooltip nennt auch die Plakette.</summary>
function ShownState(const ARegistry: IAtlasStatusRegistry; const ABadge: TAtlasStatusBadge): TAtlasStatusShown;
var
  mSettings: TAtlasPluginSettings;
  mProgressId: string;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result.Items := TAtlasStatusSummary.Visible(ARegistry.Items,
    TAtlasStatusSummary.ParseIds(mSettings.StatusFieldHidden));
  Result.State := TAtlasStatusSummary.Overall(Result.Items);
  mProgressId := '';
  if mSettings.IndexProgressInField then
  begin
    mProgressId := TAtlasStatusLines.cIndexId;
  end;
  Result.Text := TAtlasStatusSummary.FieldText(Result.Items, mSettings.StatusFieldSummary, mProgressId);
  Result.Tooltip := TAtlasStatusSummary.Tooltip(Result.Items);
  if (ABadge.Count > 0) and (ABadge.Hint <> '') then
  begin
    if Result.Tooltip <> '' then
    begin
      Result.Tooltip := Result.Tooltip + sLineBreak;
    end;
    Result.Tooltip := Result.Tooltip + ABadge.Hint;
  end;
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

/// <summary>Leisten aller Editorfenster und die schon eingehängten, ohne Doppelte.</summary>
function EditorBars(AHooks: TObjectList<TAtlasStatusField.THook>): TArray<TStatusBar>;
var
  mServices: INTAEditorServices;
  mIndex: Integer;
  mWindow: INTAEditWindow;
  mHook: TAtlasStatusField.THook;
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
    for mHook in AHooks do
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

function HookOf(AHooks: TObjectList<TAtlasStatusField.THook>; ABar: TStatusBar): TAtlasStatusField.THook;
var
  mHook: TAtlasStatusField.THook;
begin
  Result := nil;
  if ABar = nil then
  begin
    Exit;
  end;
  for mHook in AHooks do
  begin
    if mHook.Bar = ABar then
    begin
      Exit(mHook);
    end;
  end;
end;

/// <summary>ABar einhängen: eigenes Panel und verkettete Handler; nichts, wenn sie schon eingehängt ist.</summary>
procedure HookBar(AField: TAtlasStatusField; ABar: TStatusBar);
var
  mHook: TAtlasStatusField.THook;
begin
  if (ABar = nil) or (HookOf(AField.FHooks, ABar) <> nil) then
  begin
    Exit;
  end;
  mHook := TAtlasStatusField.THook.Create;
  mHook.Field := AField;
  mHook.Bar := ABar;
  mHook.OldDraw := ABar.OnDrawPanel;
  mHook.OldMouseUp := ABar.OnMouseUp;
  mHook.OldMouseMove := ABar.OnMouseMove;
  mHook.OldHint := ABar.Hint;
  mHook.OldShowHint := ABar.ShowHint;
  mHook.Panel := mHook.NewPanel(psOwnerDraw);
  ABar.OnDrawPanel := mHook.DrawPanel;
  ABar.OnMouseUp := mHook.BarMouseUp;
  ABar.OnMouseMove := mHook.BarMouseMove;
  mHook.WndHook := TAtlasWndProcHook.Create(ABar, mHook.WndProc);
  AField.FHooks.Add(mHook);
  ABar.FreeNotification(AField);
end;

procedure UnhookAll(AField: TAtlasStatusField);
var
  mHook: TAtlasStatusField.THook;
begin
  for mHook in AField.FHooks do
  begin
    mHook.Restore;
  end;
  // Liegt eine fremde WindowProc darüber, bleibt nur der kleine TAtlasWndProcHook in deren Kette; der Haken selbst
  // wird von der Leiste nicht mehr gerufen.
  AField.FHooks.Clear;
end;

/// <summary>AOnClick mit APoint unter dem Wächter; nichts ohne Handler.</summary>
procedure RunClick(const AOnClick: TProc<TPoint>; const APoint: TPoint);
var
  mOnClick: TProc<TPoint>;
  mPoint: TPoint;
begin
  if not Assigned(AOnClick) then
  begin
    Exit;
  end;
  mOnClick := AOnClick;
  mPoint := APoint;
  TAtlasGuard.Run(TAtlasFeature.Status,
    procedure
    begin
      mOnClick(mPoint);
    end);
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
procedure DrawBadge(ACanvas: TCanvas; const ARect: TRect; ALeft, APPI: Integer; const ABadge: TAtlasStatusBadge;
  const ASignals: TAtlasSignals);
var
  mInset: Integer;
  mBadge: TRect;
  mText: string;
begin
  mInset := MulDiv(3, APPI, 96);
  mBadge.Left := ALeft + mInset;
  mBadge.Top := ARect.Top + mInset;
  mBadge.Right := ARect.Right - mInset;
  mBadge.Bottom := ARect.Bottom - mInset;
  ACanvas.Pen.Color := TColor(ASignals.ForStatus(ABadge.State).Solid);
  ACanvas.Brush.Color := TColor(ASignals.ForStatus(ABadge.State).Solid);
  ACanvas.Brush.Style := bsSolid;
  ACanvas.RoundRect(mBadge.Left, mBadge.Top, mBadge.Right, mBadge.Bottom, mBadge.Height, mBadge.Height);
  ACanvas.Brush.Style := bsClear;
  ACanvas.Font.Color := TColor(ASignals.ForStatus(ABadge.State).OnSolid);
  mText := BadgeText(ABadge.Count);
  DrawText(ACanvas.Handle, PChar(mText), -1, mBadge, DT_SINGLELINE or DT_CENTER or DT_VCENTER or DT_NOPREFIX);
  ACanvas.Font.Color := StyleServices.GetSystemColor(clBtnText);
end;

/// <summary>Atlas-Feld in ARect: Symbol, Punkt im Gesamtzustand, Kurztext und Plakette.</summary>
procedure DrawField(ABar: TStatusBar; const ARect: TRect; const AShown: TAtlasStatusShown;
  const ABadge: TAtlasStatusBadge);
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
  mRadius := MulDiv(4, mPPI, 96);
  mCenter := (ARect.Top + ARect.Bottom) div 2;
  mLeft := DrawSymbol(mCanvas, mPPI, ARect.Left, mCenter);
  // Signalfarben der Statusleiste der IDE (Fläche clBtnFace), nicht der Editorfläche (#1255).
  mSignals := TAtlasIdeStyle.ChromeColors.Signals;
  mCanvas.Pen.Color := TColor(mSignals.ForStatus(AShown.State).Ring);
  mCanvas.Brush.Color := TColor(mSignals.ForStatus(AShown.State).Fill);
  mCanvas.Brush.Style := bsSolid;
  mCanvas.Ellipse(mLeft + 2 * mRadius - mRadius, mCenter - mRadius, mLeft + 2 * mRadius + mRadius + 1,
    mCenter + mRadius + 1);
  mCanvas.Brush.Style := bsClear;
  mPart := ARect;
  mPart.Left := mLeft + 4 * mRadius + MulDiv(2, mPPI, 96);
  // Plakette der Benachrichtigungen (#601) ganz rechts, der Text endet davor.
  if ABadge.Count > 0 then
  begin
    mPart.Right := mPart.Right - BadgeWidth(ABar, ABadge.Count);
    DrawBadge(mCanvas, ARect, mPart.Right, mPPI, ABadge, mSignals);
  end;
  mText := AShown.Text;
  mCanvas.Brush.Style := bsClear;
  DrawText(mCanvas.Handle, PChar(mText), -1, mPart, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
  mCanvas.Brush.Style := bsSolid;
end;

{ TAtlasStatusField.TFieldPanel }

destructor TAtlasStatusField.TFieldPanel.Destroy;
begin
  if Assigned(OnGone) then
  begin
    OnGone(Self);
  end;
  inherited Destroy;
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

function TAtlasStatusField.THook.NewPanel(AStyle: TStatusPanelStyle): TFieldPanel;
begin
  Result := TFieldPanel.Create(Bar.Panels);
  Result.Style := AStyle;
  Result.Bevel := pbNone;
  Result.OnGone := PanelGone;
end;

procedure TAtlasStatusField.THook.DropPanel(APanel: TFieldPanel);
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

procedure TAtlasStatusField.THook.PanelGone(Sender: TObject);
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
  // Das nächste Refresh legt das Panel neu an.
  if Field <> nil then
  begin
    Field.RequestRefresh;
  end;
end;

procedure TAtlasStatusField.THook.WndProc(var AMessage: TMessage);
begin
  if (Field = nil) or not Swallow(AMessage) then
  begin
    WndHook.CallOld(AMessage);
  end;
end;

function TAtlasStatusField.THook.Swallow(var AMessage: TMessage): Boolean;
var
  mPosition: TPoint;
  mContext: Boolean;
begin
  Result := False;
  mContext := Assigned(Field.FEvents.OnContext);
  case AMessage.Msg of
    WM_LBUTTONDOWN:
      // Ging das Loslassen nach einem Doppelklick verloren, gilt der nächste Klick wieder.
      SkipUp := False;
    WM_RBUTTONDOWN, WM_RBUTTONUP:
      Result := mContext and TAtlasIdeSettings.Current.StatusTogglesOnRightClick and
        PtInRect(PanelRect, SmallPointToPoint(TWMMouse(AMessage).Pos));
    WM_LBUTTONDBLCLK:
      Result := mContext and TAtlasIdeSettings.Current.StatusTogglesOnDoubleClick and
        PtInRect(PanelRect, SmallPointToPoint(TWMMouse(AMessage).Pos));
    WM_CONTEXTMENU:
      // -1/-1 kommt von der Tastatur (Umschalt+F10): der IDE überlassen.
      if (TWMContextMenu(AMessage).XPos <> -1) or (TWMContextMenu(AMessage).YPos <> -1) then
      begin
        mPosition := Bar.ScreenToClient(SmallPointToPoint(TWMContextMenu(AMessage).Pos));
        Result := mContext and TAtlasIdeSettings.Current.StatusTogglesOnRightClick and
          PtInRect(PanelRect, mPosition);
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
    PostMessage(Field.FWnd, cWM_ATLAS_STATUS_CONTEXT, 0, LPARAM(Bar));
  end;
  AMessage.Result := 0;
end;

function TAtlasStatusField.THook.PanelRect(APanel: TStatusPanel): TRect;
begin
  Result := Rect(0, 0, 0, 0);
  if (APanel = nil) or not Bar.HandleAllocated or (APanel.Width <= 0) then
  begin
    Exit;
  end;
  SendMessage(Bar.Handle, SB_GETRECT, APanel.Index, LPARAM(@Result));
end;

function TAtlasStatusField.THook.PanelRect: TRect;
begin
  Result := PanelRect(Panel);
end;

function TAtlasStatusField.THook.ScreenCorner(const ARect: TRect): TPoint;
begin
  Result := Bar.ClientToScreen(Point(ARect.Left, ARect.Top));
end;

function TAtlasStatusField.THook.ZoneAt(AX, AY: Integer): Integer;
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

function TAtlasStatusField.THook.HintOf(AZone: Integer): string;
begin
  Result := '';
  if AZone = 0 then
  begin
    Result := Field.FShown.Tooltip;
  end
  else if (AZone > 0) and (AZone <= Length(Field.FExtras)) then
  begin
    Result := Field.FExtras[AZone - 1].Hint;
  end;
end;

procedure TAtlasStatusField.THook.SyncExtras;
var
  mIndex, mCount: Integer;
  mItem: TFieldPanel;
begin
  // In die Atlas-Statusleiste umgezogen: Die Zusatzfelder stehen dort hinter dem Status.
  mCount := Length(Field.FExtras);
  if TAtlasStatusField.Relocated then
  begin
    mCount := 0;
  end;
  while Extras.Count > mCount do
  begin
    DropPanel(Extras.Last);
    Extras.Delete(Extras.Count - 1);
  end;
  while Extras.Count < mCount do
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
    mItem.Text := Field.FExtras[mIndex].Text;
    mItem.Width := Bar.Canvas.TextWidth(Field.FExtras[mIndex].Text) + MulDiv(16, Bar.CurrentPPI, 96);
  end;
end;

procedure TAtlasStatusField.THook.Layout(AShown: Boolean);
var
  mWidth: Integer;
begin
  // Von der IDE gelöscht (PanelGone): neu anlegen.
  if Panel = nil then
  begin
    Panel := NewPanel(psOwnerDraw);
  end;
  Bar.Canvas.Font := Bar.Font;
  mWidth := 0;
  if AShown then
  begin
    mWidth := Bar.Canvas.TextWidth(Field.FShown.Text) + MulDiv(30, Bar.CurrentPPI, 96) +
      SymbolWidth(Bar.CurrentPPI) + BadgeWidth(Bar, Field.FBadge.Count);
  end;
  // Text nur zum Erkennen und für Screenreader; gezeichnet wird in DrawPanel.
  if mWidth > 0 then
  begin
    Panel.Text := Field.FShown.Text;
  end
  else
  begin
    Panel.Text := '';
  end;
  Panel.Width := mWidth;
  SyncExtras;
  // Zusatzfeld verschwunden oder Feld aus: Tooltip des Panels unter der Maus neu bestimmen.
  if Zone >= 0 then
  begin
    Bar.Hint := HintOf(Zone);
  end;
  Bar.Invalidate;
end;

procedure TAtlasStatusField.THook.Restore;
var
  mOwner: TAtlasStatusField;
  mDraw, mCurrentDraw: TDrawPanelEvent;
  mMouseUp, mCurrentUp: TMouseEvent;
  mMouseMove, mCurrentMove: TMouseMoveEvent;
  mIndex: Integer;
begin
  if Bar = nil then
  begin
    Exit;
  end;
  mOwner := Field;
  Field := nil;
  // Fremde WindowProc darüber: Der Haken der WindowProc bleibt in deren Kette und reicht ab jetzt nur noch durch;
  // Unhook kennzeichnet das Entladen dann als unsicher (Protokoll, Diagnose, Neustart).
  TAtlasWndProcHook.Unhook(WndHook);
  if mOwner <> nil then
  begin
    Bar.RemoveFreeNotification(mOwner);
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

procedure TAtlasStatusField.THook.OpenWindow;
begin
  Field.OpenWindowAt(ScreenCorner(PanelRect));
end;

procedure TAtlasStatusField.THook.DrawPanel(AStatusBar: TStatusBar; APanel: TStatusPanel; const ARect: TRect);
begin
  if Field = nil then
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
    DrawField(AStatusBar, ARect, Field.FShown, Field.FBadge);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Status, E);
  end;
end;

function TAtlasStatusField.THook.Click(AZone, AX: Integer): Boolean;
begin
  Result := True;
  // Klick auf die Plakette (#601): Liste der Benachrichtigungen statt Statusfenster.
  if (AZone = 0) and (Field.FBadge.Count > 0) and Assigned(Field.FBadge.OnClick) and
    (AX >= PanelRect.Right - BadgeWidth(Bar, Field.FBadge.Count)) then
  begin
    if Field.FWindow <> nil then
    begin
      Field.FWindow.Dismiss;
    end;
    RunClick(Field.FBadge.OnClick, ScreenCorner(PanelRect));
  end
  else if AZone = 0 then
  begin
    TAtlasGuard.Run(TAtlasFeature.Status,
      procedure
      begin
        OpenWindow;
      end);
  end
  else if (AZone > 0) and (AZone <= Length(Field.FExtras)) then
  begin
    RunClick(Field.FExtras[AZone - 1].OnClick, ScreenCorner(PanelRect(Extras[AZone - 1])));
  end
  else
  begin
    Result := False;
  end;
end;

procedure TAtlasStatusField.THook.BarMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  if Field = nil then
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

procedure TAtlasStatusField.THook.BarMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  mZone: Integer;
begin
  if Field = nil then
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

{ TAtlasStatusField }

constructor TAtlasStatusField.Create(const ARegistry: IAtlasStatusRegistry);
var
  mEditor: IOTAEditorServices;
begin
  inherited Create(nil);
  FRegistry := ARegistry;
  FHooks := TObjectList<THook>.Create(True);
  FDead := TObjectList<THook>.Create(True);
  FNotifierIndex := -1;
  FWnd := AllocateHWnd(WndProc);
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := cRedrawMs;
  FTimer.OnTimer := TimerTick;
  FListener := FRegistry.AddListener(
    procedure
    begin
      RequestRefresh;
    end);
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditor) then
  begin
    FNotifierIndex := mEditor.AddNotifier(TFieldNotifier.Create(Self));
  end;
  RequestRefresh;
end;

destructor TAtlasStatusField.Destroy;
var
  mEditor: IOTAEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  FRegistry.RemoveListener(FListener);
  if (FNotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAEditorServices, mEditor) then
  begin
    mEditor.RemoveNotifier(FNotifierIndex);
  end;
  FreeAndNil(FTimer);
  if FWnd <> 0 then
  begin
    DeallocateHWnd(FWnd);
  end;
  FWnd := 0;
  if FWindow <> nil then
  begin
    FWindow.RemoveFreeNotification(Self);
    FreeAndNil(FWindow);
  end;
  try
    UnhookAll(Self);
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
  begin
    PostMessage(FWnd, cWM_ATLAS_STATUS, 0, 0);
  end;
end;

procedure TAtlasStatusField.WndProc(var AMessage: TMessage);
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
    mHook := HookOf(FHooks, TStatusBar(AMessage.LParam));
    if mHook <> nil then
    begin
      TAtlasGuard.Run(TAtlasFeature.Status,
        procedure
        begin
          ContextAt(mHook.ScreenCorner(mHook.PanelRect));
        end);
    end;
    AMessage.Result := 0;
  end
  else
  begin
    AMessage.Result := DefWindowProc(FWnd, AMessage.Msg, AMessage.WParam, AMessage.LParam);
  end;
end;

procedure TAtlasStatusField.TimerTick(Sender: TObject);
begin
  FTimer.Enabled := False;
  AtomicExchange(FPosted, 0);
  TAtlasGuard.Run(TAtlasFeature.Status, Refresh);
end;

procedure TAtlasStatusField.Notification(AComponent: TComponent; Operation: TOperation);
var
  mIndex: Integer;
begin
  inherited;
  if Operation <> opRemove then
  begin
    Exit;
  end;
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
      FHooks[mIndex].Field := nil;
      FDead.Add(FHooks.Extract(FHooks[mIndex]));
    end;
  end;
end;

procedure TAtlasStatusField.SetExtra(const AId, AText, AHint: string; const AOnClick: TProc<TPoint>);
var
  mIndex, mFound: Integer;
  mExtra: TExtra;
begin
  mFound := -1;
  for mIndex := 0 to High(FExtras) do
  begin
    if FExtras[mIndex].Id = AId then
    begin
      mFound := mIndex;
    end;
  end;
  if AText = '' then
  begin
    if mFound >= 0 then
    begin
      Delete(FExtras, mFound, 1);
    end;
  end
  else
  begin
    mExtra.Id := AId;
    mExtra.Text := AText;
    mExtra.Hint := AHint;
    mExtra.OnClick := AOnClick;
    if mFound >= 0 then
    begin
      FExtras[mFound] := mExtra;
    end
    else
    begin
      FExtras := FExtras + [mExtra];
    end;
  end;
  RequestRefresh;
end;

function TAtlasStatusField.ExtraItems: TArray<TAtlasStatusExtraItem>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(FExtras));
  for mIndex := 0 to High(FExtras) do
  begin
    Result[mIndex].Id := FExtras[mIndex].Id;
    Result[mIndex].Text := FExtras[mIndex].Text;
    Result[mIndex].Hint := FExtras[mIndex].Hint;
    Result[mIndex].Clickable := Assigned(FExtras[mIndex].OnClick);
  end;
end;

procedure TAtlasStatusField.ClickExtra(const AId: string; const APoint: TPoint);
var
  mExtra: TExtra;
begin
  for mExtra in FExtras do
  begin
    if mExtra.Id = AId then
    begin
      RunClick(mExtra.OnClick, APoint);
      Exit;
    end;
  end;
end;

procedure TAtlasStatusField.ClickBadge(const APoint: TPoint);
begin
  if FBadge.Shown and Assigned(FBadge.OnClick) then
  begin
    FBadge.OnClick(APoint);
  end;
end;

procedure TAtlasStatusField.SetBadge(const ABadge: TAtlasStatusBadge);
var
  mCount: Integer;
begin
  mCount := ABadge.Count;
  if mCount < 0 then
  begin
    mCount := 0;
  end;
  FBadge.OnClick := ABadge.OnClick;
  // Unverändert: nicht neu zeichnen (die Zentrale meldet auch Änderungen ohne Wirkung auf die Plakette).
  if (ABadge.Shown = FBadge.Shown) and (mCount = FBadge.Count) and (ABadge.State = FBadge.State) and
    (ABadge.Hint = FBadge.Hint) then
  begin
    Exit;
  end;
  FBadge.Shown := ABadge.Shown;
  FBadge.Count := mCount;
  FBadge.State := ABadge.State;
  FBadge.Hint := ABadge.Hint;
  RequestRefresh;
end;

procedure TAtlasStatusField.Refresh;
var
  mShown: Boolean;
  mBar: TStatusBar;
  mHook: THook;
begin
  if Assigned(FEvents.OnRefresh) then
  begin
    FEvents.OnRefresh();
  end;
  FShown := ShownState(FRegistry, FBadge);
  if FWindow <> nil then
  begin
    FWindow.SetItems(FShown.Items);
  end;
  mShown := PanelShown;
  // Ohne Atlas-Feld bleiben die Leisten nur für Zusatzfelder eingehängt (#575).
  if not mShown and (Length(FExtras) = 0) then
  begin
    UnhookAll(Self);
    Exit;
  end;
  // Neue Editorfenster bekommen hier ihr Feld.
  for mBar in EditorBars(FHooks) do
  begin
    HookBar(Self, mBar);
    mHook := HookOf(FHooks, mBar);
    if mHook <> nil then
    begin
      mHook.Layout(mShown);
    end;
  end;
end;

class function TAtlasStatusField.Relocated: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.EditorStatusBar and TAtlasStatusBarItems.Contains(TAtlasStatusBarItems.Parse(
    mSettings.EditorStatusBarItems), TAtlasStatusBarItems.cStatus) and
    not TAtlasGuard.Disabled(TAtlasFeature.StatusBar);
end;

function TAtlasStatusField.Anchor(out APoint: TPoint): Boolean;
var
  mHook: THook;
  mArea: TRect;
begin
  APoint := Point(0, 0);
  if Relocated then
  begin
    Result := Assigned(FEvents.OnRelocatedAnchor) and FEvents.OnRelocatedAnchor(APoint);
    Exit;
  end;
  mHook := HookOf(FHooks, TopEditorBar);
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

procedure TAtlasStatusField.OpenWindowAt(const APoint: TPoint);
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
  FWindow.OnOpenLog := FEvents.OnOpenLog;
  FWindow.OnRestart := FEvents.OnRestart;
  FWindow.SetItems(FShown.Items);
  FWindow.ShowAbove(APoint);
end;

procedure TAtlasStatusField.ContextAt(const APoint: TPoint);
begin
  if not Assigned(FEvents.OnContext) then
  begin
    Exit;
  end;
  if FWindow <> nil then
  begin
    FWindow.Dismiss;
  end;
  FEvents.OnContext(APoint);
end;

end.
