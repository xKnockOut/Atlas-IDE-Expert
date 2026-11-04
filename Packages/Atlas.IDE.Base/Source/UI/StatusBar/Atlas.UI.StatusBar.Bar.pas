unit Atlas.UI.StatusBar.Bar;

// Atlas-Statusleiste (#1155), Darstellung: eine Zeile unten am Editor, über der
// Statuszeile der IDE. Die Höhe hängt nur von der DPI ab, nie vom Inhalt.
// - SetView setzt den Inhalt (TAtlasStatusBarView); gleicher Inhalt zeichnet
//   nicht neu. Elemente in der Reihenfolge von View.Items:
//   status: Punkt in Zustandsfarbe und Text („Atlas · bereit“), dahinter mit
//   ungelesenen Benachrichtigungen deren Plakette (#1234, Klick: OnBadge);
//   findings: Zähler je Art mit den Symbolen aus „Atlas-Prüfung“;
//   liveCheck: „live · geprüft vor 2 s“, „prüft …“, „beim Speichern“;
//   method: „ƒ TFoo.Bar · 4 Zeilen · CC 2“, über der Grenze in Warnfarbe.
//   Rechts außen steht immer das Zahnrad.
// - Passt nicht alles, verteilt TAtlasStatusBarLayout die Breite: Die Methode
//   kürzt ihren Namen zuerst (mit „…“), die Kennzahlen bleiben; nichts bricht
//   um.
// - Klick (beim Loslassen über dem Element; das Verlassen der Leiste zwischen
//   Drücken und Loslassen bricht nicht ab, siehe Editorleiste #1101): Status
//   meldet OnStatus, ein Zähler OnFinding mit seiner Art, die Live-Prüfung
//   OnLiveCheck (alle Units neu prüfen, #1231), die Methode OnMethod, das
//   Zahnrad öffnet das Menü „Leiste anpassen“. Doppelklick auf
//   die Zähler meldet OnFindingsOpen, auf den Status OnStatusOpen (Fenster
//   „Atlas-Server“, #1356). Rechtsklick auf den Status meldet
//   OnStatusContext, sonst öffnet er das Menü. WM_CONTEXTMENU behandelt die
//   Leiste selbst; es geht nicht an das Editorfenster der IDE weiter.
// - Menü „Leiste anpassen“: jedes Element mit Haken (OnToggleItem), darunter
//   „Statusleiste ausblenden“ (OnHide).
// - Tooltip je Element (View); das Zahnrad nennt „Leiste anpassen …“.
// - Höhe, Farben, Hervorhebung, Klick beim Loslassen, Kontextmenü und
//   OnDisabled kommen vom Vorfahr TAtlasEditorBar (#1248). Teil im Vorfahr:
//   Ord(Element) * KindSlots + Zähler + 1 (Zähler -1 außerhalb der Zähler).

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Menus,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Style.Signal,
  Atlas.Core.Status.Contract,
  Atlas.Core.Problems.Findings,
  Atlas.Core.StatusBar.Content,
  Atlas.Core.StatusBar.Layout,
  Atlas.UI.Editor.Bar;

type
{$SCOPEDENUMS ON}
  TAtlasStatusBarPart = (None, Status, Badge, Findings, LiveCheck, Method, Gear);
{$SCOPEDENUMS OFF}

  TAtlasStatusBarView = record
    /// <summary>Sichtbare Elemente in Reihenfolge (TAtlasStatusBarItems).</summary>
    Items: TArray<string>;
    StatusText: string;
    StatusHint: string;
    /// <summary>Zustand des Punkts; die Farbe wählt die Leiste aus ihrer Palette (#1255).</summary>
    StatusState: TAtlasStatusState;
    /// <summary>Ungelesene Benachrichtigungen (#1234); 0 = keine Plakette. Zustand des schwersten Eintrags.</summary>
    BadgeCount: Integer;
    BadgeState: TAtlasStatusState;
    BadgeHint: string;
    /// <summary>Probleme an: Zähler zeigen; sonst fällt das Element weg.</summary>
    FindingsShown: Boolean;
    Counts: TAtlasStatusCounts;
    FindingsHint: string;
    LiveText: string;
    LiveHint: string;
    /// <summary>Prüfung läuft: Symbol in Akzentfarbe.</summary>
    LiveBusy: Boolean;
    MethodFound: Boolean;
    /// <summary>Qualifizierter Name; ohne Methode der gedämpfte Text „keine Methode“.</summary>
    MethodName: string;
    /// <summary>Kennzahlen, z. B. „4 Zeilen · CC 2“.</summary>
    MethodDetail: string;
    MethodHint: string;
    MethodOver: Boolean;
    function SameAs(const AOther: TAtlasStatusBarView): Boolean;
    /// <summary>Zahl auf der Plakette: bis 99, darüber „99+“.</summary>
    function BadgeText: string;
  end;

  TAtlasStatusBarKindEvent = reference to procedure(AKind: TAtlasFindingKind);
  TAtlasStatusBarItemEvent = reference to procedure(const AId: string);

  /// <summary>Lage nach dem Layout: Elemente in Reihenfolge mit ihren Spannen, die Zähler und das Zahnrad.
  /// </summary>
  TAtlasStatusBarPlaces = record
    Parts: TArray<TAtlasStatusBarPart>;
    Spans: TArray<TAtlasStatusSpan>;
    /// <summary>Zähler von links nach rechts (Fehler, Warnungen, Hinweise); leer ohne Zähler.</summary>
    KindSpans: TArray<TAtlasStatusSpan>;
    Gear: TRect;
    /// <summary>Fläche des Elements bei Höhe AHeight; leer, wenn es nicht in der Leiste steht.</summary>
    function PartRect(APart: TAtlasStatusBarPart; AHeight: Integer): TRect;
    function KindRect(AKind: TAtlasFindingKind; AHeight: Integer): TRect;
    /// <summary>Element unter APoint bei Höhe AHeight; None ohne.</summary>
    function ElementAt(const APoint: TPoint; AHeight: Integer): TAtlasStatusBarPart;
    /// <summary>Index des Zählers unter X; -1 ohne.</summary>
    function KindAt(X: Integer): Integer;
  end;

  /// <summary>Menütexte: Elemente in der Reihenfolge von TAtlasStatusBarItems.All, Tooltip des Zahnrads
  /// („Leiste anpassen …“) und „Statusleiste ausblenden“.</summary>
  TAtlasStatusBarTexts = record
    ItemCaptions: TArray<string>;
    Customize: string;
    Hide: string;
    class function Create(const AItemCaptions: TArray<string>; const ACustomize, AHide: string): TAtlasStatusBarTexts;
      static;
  end;

  TAtlasStatusBarEvents = record
    Status: TProc<TPoint>;
    StatusContext: TProc<TPoint>;
    Badge: TProc<TPoint>;
    Finding: TAtlasStatusBarKindEvent;
    FindingsOpen: TProc;
    StatusOpen: TProc;
    LiveCheck: TProc;
    Method: TProc;
    ToggleItem: TAtlasStatusBarItemEvent;
    Hide: TProc;
  end;

  TAtlasEditorStatusBar = class(TAtlasEditorBar)
  private const
    /// <summary>Teile je Element im Vorfahr: ohne Zähler und je Zähler einer.</summary>
    KindSlots = 4;
  private
    FView: TAtlasStatusBarView;
    FPlaces: TAtlasStatusBarPlaces;
    FLaidOut: Boolean;
    FMenu: TPopupMenu;
    FTexts: TAtlasStatusBarTexts;
    FEvents: TAtlasStatusBarEvents;
    procedure Layout;
    function ElementAt(X, Y: Integer): TAtlasStatusBarPart;
    procedure Fire(APart: TAtlasStatusBarPart; X: Integer);
    procedure CMFontChanged(var Message: TMessage); message CM_FONTCHANGED;
  protected
    function PartAt(X, Y: Integer): Integer; override;
    function PartHint(APart: Integer): string; override;
    function PartEnabled(APart: Integer): Boolean; override;
    procedure PartClicked(APart: Integer; AShift: TShiftState; X, Y: Integer); override;
    /// <summary>Rechtsklick auf den Status meldet OnStatusContext, sonst das Menü „Leiste anpassen“.</summary>
    procedure ContextMenu(const APoint: TPoint; APart: Integer); override;
    function KeyboardMenuPoint: TPoint; override;
    procedure Paint; override;
    procedure Resize; override;
    procedure DblClick; override;
    procedure ChangeScale(M, D: Integer; isDpiChange: Boolean); override;
  public
    procedure SetView(const AView: TAtlasStatusBarView);
    /// <summary>Fläche des Elements (Client); leer, wenn es nicht in der Leiste steht.</summary>
    function PartRect(APart: TAtlasStatusBarPart): TRect;
    /// <summary>Fläche des Zählers der Art AKind (Client); leer ohne.</summary>
    function KindRect(AKind: TAtlasFindingKind): TRect;
    /// <summary>Tooltip über dem Punkt (Client); '' = keiner.</summary>
    function HintAt(X, Y: Integer): string;
    /// <summary>Klick wie mit der Maus (für Tests).</summary>
    procedure ClickAt(X, Y: Integer);
    /// <summary>Doppelklick wie mit der Maus (für Tests).</summary>
    procedure DoubleClickAt(X, Y: Integer);
    /// <summary>Menü „Leiste anpassen“ aufbauen, ohne es zu zeigen (für Tests und Popup).</summary>
    function BuildMenu: TPopupMenu;
    property View: TAtlasStatusBarView read FView;
    /// <summary>Menütexte und Tooltip des Zahnrads.</summary>
    property Texts: TAtlasStatusBarTexts read FTexts write FTexts;
    property OnStatus: TProc<TPoint> read FEvents.Status write FEvents.Status;
    property OnStatusContext: TProc<TPoint> read FEvents.StatusContext write FEvents.StatusContext;
    /// <summary>Klick auf die Plakette (#1234): linke Oberkante der Plakette (Bildschirm).</summary>
    property OnBadge: TProc<TPoint> read FEvents.Badge write FEvents.Badge;
    property OnFinding: TAtlasStatusBarKindEvent read FEvents.Finding write FEvents.Finding;
    property OnFindingsOpen: TProc read FEvents.FindingsOpen write FEvents.FindingsOpen;
    /// <summary>Doppelklick auf den Status (#1356); nil = nichts.</summary>
    property OnStatusOpen: TProc read FEvents.StatusOpen write FEvents.StatusOpen;
    /// <summary>Klick auf die Live-Prüfung: alle Units neu prüfen (#1231).</summary>
    property OnLiveCheck: TProc read FEvents.LiveCheck write FEvents.LiveCheck;
    property OnMethod: TProc read FEvents.Method write FEvents.Method;
    property OnToggleItem: TAtlasStatusBarItemEvent read FEvents.ToggleItem write FEvents.ToggleItem;
    property OnHide: TProc read FEvents.Hide write FEvents.Hide;
  end;

implementation

uses
  System.Math,
  Vcl.Forms,
  Atlas.Core.Settings.StatusBarItems,
  Atlas.Core.EditorToolbar.Icons,
  Atlas.UI.EditorToolbar.Glyphs,
  Atlas.UI.Problems.KindIcon;

const
  /// <summary>Zähler von links nach rechts; Index wie in KindSpans.</summary>
  Kinds: array[0..2] of TAtlasFindingKind = (TAtlasFindingKind.Error, TAtlasFindingKind.Warning,
    TAtlasFindingKind.Info);

const
  BaseGap = 13;
  BaseGear = 22;
  Margin = 4;
  /// <summary>Innenabstand je Feld; eigener Name, weil TControl.Padding in den Methoden die Konstante verdeckt.</summary>
  SlotPadding = 4;
  /// <summary>Kürzstufen: die Methode zuerst, die Zähler nie.</summary>
  ShrinkMethod = 1;
  ShrinkLive = 2;
  ShrinkStatus = 3;
  ShrinkFindings = 4;
  MethodSign = #$0192;
  Ellipsis = #$2026;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

{ TAtlasStatusBarView }

function TAtlasStatusBarView.SameAs(const AOther: TAtlasStatusBarView): Boolean;
var
  mKind: TAtlasFindingKind;
begin
  Result := (string.Join(',', Items) = string.Join(',', AOther.Items)) and (StatusText = AOther.StatusText) and
    (StatusHint = AOther.StatusHint) and (StatusState = AOther.StatusState) and
    (BadgeCount = AOther.BadgeCount) and (BadgeState = AOther.BadgeState) and (BadgeHint = AOther.BadgeHint) and
    (FindingsShown = AOther.FindingsShown) and (FindingsHint = AOther.FindingsHint) and
    (LiveText = AOther.LiveText) and (LiveHint = AOther.LiveHint) and (LiveBusy = AOther.LiveBusy) and
    (MethodFound = AOther.MethodFound) and (MethodName = AOther.MethodName) and
    (MethodDetail = AOther.MethodDetail) and (MethodHint = AOther.MethodHint) and (MethodOver = AOther.MethodOver);
  if not Result then
  begin
    Exit;
  end;
  for mKind := Low(TAtlasFindingKind) to High(TAtlasFindingKind) do
  begin
    if Counts[mKind] <> AOther.Counts[mKind] then
    begin
      Exit(False);
    end;
  end;
end;

function TAtlasStatusBarView.BadgeText: string;
begin
  if BadgeCount > 99 then
  begin
    Result := '99+';
  end
  else
  begin
    Result := IntToStr(BadgeCount);
  end;
end;

{ TAtlasStatusBarPlaces }

function TAtlasStatusBarPlaces.PartRect(APart: TAtlasStatusBarPart; AHeight: Integer): TRect;
var
  mIndex: Integer;
begin
  if APart = TAtlasStatusBarPart.Gear then
  begin
    Exit(Gear);
  end;
  for mIndex := 0 to High(Parts) do
  begin
    if (Parts[mIndex] = APart) and not Spans[mIndex].IsEmpty then
    begin
      Exit(Rect(Spans[mIndex].Left, 0, Spans[mIndex].Right, AHeight));
    end;
  end;
  Result := TRect.Empty;
end;

function TAtlasStatusBarPlaces.KindRect(AKind: TAtlasFindingKind; AHeight: Integer): TRect;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(KindSpans) do
  begin
    if Kinds[mIndex] = AKind then
    begin
      Exit(Rect(KindSpans[mIndex].Left, 0, KindSpans[mIndex].Right, AHeight));
    end;
  end;
  Result := TRect.Empty;
end;

function TAtlasStatusBarPlaces.ElementAt(const APoint: TPoint; AHeight: Integer): TAtlasStatusBarPart;
var
  mIndex: Integer;
begin
  Result := TAtlasStatusBarPart.None;
  if (APoint.Y < 0) or (APoint.Y >= AHeight) then
  begin
    Exit;
  end;
  if Gear.Contains(APoint) then
  begin
    Exit(TAtlasStatusBarPart.Gear);
  end;
  mIndex := TAtlasStatusBarLayout.IndexAt(Spans, APoint.X);
  if mIndex >= 0 then
  begin
    Result := Parts[mIndex];
  end;
end;

function TAtlasStatusBarPlaces.KindAt(X: Integer): Integer;
begin
  Result := TAtlasStatusBarLayout.IndexAt(KindSpans, X);
end;

{ TAtlasStatusBarTexts }

class function TAtlasStatusBarTexts.Create(const AItemCaptions: TArray<string>; const ACustomize,
  AHide: string): TAtlasStatusBarTexts;
begin
  Result.ItemCaptions := AItemCaptions;
  Result.Customize := ACustomize;
  Result.Hide := AHide;
end;

type
  /// <summary>Breiten der Elemente in der Schrift der Leiste.</summary>
  TAtlasStatusBarMeasure = record
    Bar: TAtlasEditorStatusBar;
    function Gap: Integer;
    function DotSize: Integer;
    function IconSize: Integer;
    function TextWidthOf(const AText: string; ABold: Boolean): Integer;
    function KindWidth(AKind: TAtlasFindingKind): Integer;
    function KindWidths: TArray<Integer>;
    /// <summary>Feld mit Symbol bzw. Punkt der Breite AMark und kürzbarem Text.</summary>
    function TextSlot(AMark: Integer; const AText: string; AShrink: Integer): TAtlasStatusSlot;
    function MethodSlot: TAtlasStatusSlot;
    function SlotOf(APart: TAtlasStatusBarPart): TAtlasStatusSlot;
    function PartsOfView: TArray<TAtlasStatusBarPart>;
  end;

  /// <summary>Zeichnen der Elemente, der Hervorhebung unter der Maus und des Zahnrads.</summary>
  TAtlasStatusBarPainter = record
    Bar: TAtlasEditorStatusBar;
    Measure: TAtlasStatusBarMeasure;
    function Canvas: TCanvas;
    function Colors: TAtlasColors;
    /// <summary>Element und Zähler unter der Maus (aus Hot des Vorfahrs).</summary>
    function HotElement: TAtlasStatusBarPart;
    function HotKind: Integer;
    procedure Hot(const ARect: TRect);
    procedure Status(const ARect: TRect);
    procedure Badge(const ARect: TRect);
    procedure Findings(const ARect: TRect);
    procedure Cycle(const ARect: TRect; AColor: TColor);
    procedure Live(const ARect: TRect);
    procedure Method(const ARect: TRect);
    procedure Gear(const ARect: TRect);
    procedure Element(APart: TAtlasStatusBarPart; const ARect: TRect);
  end;

  /// <summary>Menü „Leiste anpassen“: je Element ein Haken, darunter „Statusleiste ausblenden“.</summary>
  TAtlasStatusBarMenu = class(TPopupMenu)
  private
    FBar: TAtlasEditorStatusBar;
    FIds: TArray<string>;
    procedure ToggleClick(Sender: TObject);
    procedure HideClick(Sender: TObject);
  public
    constructor CreateFor(ABar: TAtlasEditorStatusBar);
  end;

{ TAtlasStatusBarMeasure }

function TAtlasStatusBarMeasure.Gap: Integer;
begin
  Result := Bar.Scale(BaseGap);
end;

function TAtlasStatusBarMeasure.DotSize: Integer;
begin
  Result := Bar.Scale(8);
end;

function TAtlasStatusBarMeasure.IconSize: Integer;
begin
  Result := Bar.Scale(14);
end;

function TAtlasStatusBarMeasure.TextWidthOf(const AText: string; ABold: Boolean): Integer;
begin
  Bar.Canvas.Font := Bar.Font;
  if ABold then
  begin
    Bar.Canvas.Font.Style := [fsBold];
  end;
  Result := Bar.Canvas.TextWidth(AText);
  Bar.Canvas.Font := Bar.Font;
end;

function TAtlasStatusBarMeasure.KindWidth(AKind: TAtlasFindingKind): Integer;
begin
  Result := IconSize + Bar.Scale(3) + TextWidthOf(IntToStr(Bar.FView.Counts[AKind]), False) + Bar.Scale(6);
end;

function TAtlasStatusBarMeasure.KindWidths: TArray<Integer>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(Kinds));
  for mIndex := 0 to High(Kinds) do
  begin
    Result[mIndex] := KindWidth(Kinds[mIndex]);
  end;
end;

function TAtlasStatusBarMeasure.TextSlot(AMark: Integer; const AText: string; AShrink: Integer): TAtlasStatusSlot;
var
  mFixed: Integer;
begin
  mFixed := 2 * Bar.Scale(SlotPadding) + AMark;
  Result := TAtlasStatusSlot.Create(mFixed + TextWidthOf(AText, False), mFixed + TextWidthOf(Ellipsis, False),
    AShrink);
end;

function TAtlasStatusBarMeasure.MethodSlot: TAtlasStatusSlot;
var
  mFixed: Integer;
begin
  // Methode: Zeichen, Name (kürzbar), Kennzahlen (bleiben).
  mFixed := 2 * Bar.Scale(SlotPadding) + TextWidthOf(MethodSign, True) + Bar.Scale(4);
  if Bar.FView.MethodDetail <> '' then
  begin
    Inc(mFixed, Bar.Scale(6) + TextWidthOf(Bar.FView.MethodDetail, False));
  end;
  Result := TAtlasStatusSlot.Create(mFixed + TextWidthOf(Bar.FView.MethodName, False),
    mFixed + TextWidthOf(Ellipsis, False), ShrinkMethod);
end;

function TAtlasStatusBarMeasure.SlotOf(APart: TAtlasStatusBarPart): TAtlasStatusSlot;
var
  mWidth, mIndex: Integer;
begin
  case APart of
    TAtlasStatusBarPart.Status:
      Result := TextSlot(DotSize + Bar.Scale(5), Bar.FView.StatusText, ShrinkStatus);
    TAtlasStatusBarPart.Badge:
      begin
        mWidth := 2 * Bar.Scale(SlotPadding) + Max(Bar.Scale(18), TextWidthOf(Bar.FView.BadgeText, True) +
          Bar.Scale(10));
        Result := TAtlasStatusSlot.Create(mWidth, mWidth, ShrinkFindings);
      end;
    TAtlasStatusBarPart.Findings:
      begin
        mWidth := Bar.Scale(SlotPadding);
        for mIndex := 0 to High(Kinds) do
        begin
          Inc(mWidth, KindWidth(Kinds[mIndex]));
        end;
        Result := TAtlasStatusSlot.Create(mWidth, mWidth, ShrinkFindings);
      end;
    TAtlasStatusBarPart.LiveCheck:
      Result := TextSlot(IconSize + Bar.Scale(4), Bar.FView.LiveText, ShrinkLive);
  else
    Result := MethodSlot;
  end;
end;

function TAtlasStatusBarMeasure.PartsOfView: TArray<TAtlasStatusBarPart>;
var
  mId: string;
begin
  Result := nil;
  for mId in Bar.FView.Items do
  begin
    if SameText(mId, TAtlasStatusBarItems.Status) then
    begin
      Result := Result + [TAtlasStatusBarPart.Status];
      // Plakette der Benachrichtigungen (#1234) direkt hinter dem Status; das Atlas-Feld ist dann 0 breit.
      if Bar.FView.BadgeCount > 0 then
      begin
        Result := Result + [TAtlasStatusBarPart.Badge];
      end;
    end
    else if SameText(mId, TAtlasStatusBarItems.Findings) and Bar.FView.FindingsShown then
    begin
      Result := Result + [TAtlasStatusBarPart.Findings];
    end
    else if SameText(mId, TAtlasStatusBarItems.LiveCheck) then
    begin
      Result := Result + [TAtlasStatusBarPart.LiveCheck];
    end
    else if SameText(mId, TAtlasStatusBarItems.Method) then
    begin
      Result := Result + [TAtlasStatusBarPart.Method];
    end;
  end;
end;

{ TAtlasStatusBarPainter }

function TAtlasStatusBarPainter.Canvas: TCanvas;
begin
  Result := Bar.Canvas;
end;

function TAtlasStatusBarPainter.Colors: TAtlasColors;
begin
  Result := Bar.Colors;
end;

function TAtlasStatusBarPainter.HotElement: TAtlasStatusBarPart;
begin
  if Bar.Hot = TAtlasEditorBar.PartNone then
  begin
    Exit(TAtlasStatusBarPart.None);
  end;
  Result := TAtlasStatusBarPart(Bar.Hot div TAtlasEditorStatusBar.KindSlots);
end;

function TAtlasStatusBarPainter.HotKind: Integer;
begin
  if Bar.Hot = TAtlasEditorBar.PartNone then
  begin
    Exit(-1);
  end;
  Result := Bar.Hot mod TAtlasEditorStatusBar.KindSlots - 1;
end;

procedure TAtlasStatusBarPainter.Hot(const ARect: TRect);
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Selection);
  Canvas.Pen.Color := ToColor(Colors.Line);
  Canvas.RoundRect(ARect.Left, ARect.Top + Bar.Scale(2), ARect.Right, ARect.Bottom - Bar.Scale(2), Bar.Scale(4),
    Bar.Scale(4));
end;

procedure TAtlasStatusBarPainter.Status(const ARect: TRect);
var
  mCenter, mLeft, mDot: Integer;
  mPart: TRect;
begin
  mCenter := (ARect.Top + ARect.Bottom) div 2;
  mLeft := ARect.Left + Bar.Scale(SlotPadding);
  mDot := Measure.DotSize;
  Canvas.Brush.Style := bsSolid;
  // Signalfarbe der Leistenfläche mit Rand (#1255).
  Canvas.Brush.Color := ToColor(Colors.Signals.ForStatus(Bar.FView.StatusState).Fill);
  Canvas.Pen.Color := ToColor(Colors.Signals.ForStatus(Bar.FView.StatusState).Ring);
  Canvas.Ellipse(mLeft, mCenter - mDot div 2, mLeft + mDot, mCenter - mDot div 2 + mDot);
  Canvas.Font := Bar.Font;
  Canvas.Font.Color := ToColor(Colors.Text);
  Canvas.Brush.Style := bsClear;
  mPart := Rect(mLeft + mDot + Bar.Scale(5), ARect.Top, ARect.Right - Bar.Scale(SlotPadding), ARect.Bottom);
  DrawText(Canvas.Handle, PChar(Bar.FView.StatusText), -1, mPart, DT_LEFT or DT_VCENTER or DT_SINGLELINE or
    DT_NOPREFIX or DT_END_ELLIPSIS);
end;

procedure TAtlasStatusBarPainter.Findings(const ARect: TRect);
var
  mIndex, mTop, mCount: Integer;
  mIcon, mPart: TRect;
  mSpans: TArray<TAtlasStatusSpan>;
begin
  mSpans := Bar.FPlaces.KindSpans;
  mTop := ARect.Top + (ARect.Height - Measure.IconSize) div 2;
  for mIndex := 0 to High(mSpans) do
  begin
    if mSpans[mIndex].IsEmpty then
    begin
      Continue;
    end;
    if (HotElement = TAtlasStatusBarPart.Findings) and (HotKind = mIndex) then
    begin
      Hot(Rect(mSpans[mIndex].Left - Bar.Scale(2), ARect.Top, mSpans[mIndex].Right - Bar.Scale(2), ARect.Bottom));
    end;
    mIcon := Rect(mSpans[mIndex].Left, mTop, mSpans[mIndex].Left + Measure.IconSize, mTop + Measure.IconSize);
    TAtlasFindingIcon.Draw(Canvas, mIcon, Kinds[mIndex], Colors.Signals.Get(TAtlasFindingIcon.SignalOf(Kinds[mIndex])));
    mCount := Bar.FView.Counts[Kinds[mIndex]];
    Canvas.Font := Bar.Font;
    // Null gedämpft: Nichts zu tun.
    Canvas.Font.Color := ToColor(Colors.Text);
    if mCount = 0 then
    begin
      Canvas.Font.Color := ToColor(Colors.Muted);
    end;
    Canvas.Brush.Style := bsClear;
    mPart := Rect(mIcon.Right + Bar.Scale(3), ARect.Top, mSpans[mIndex].Right, ARect.Bottom);
    DrawText(Canvas.Handle, PChar(IntToStr(mCount)), -1, mPart, DT_LEFT or DT_VCENTER or DT_SINGLELINE or
      DT_NOPREFIX);
  end;
end;

procedure TAtlasStatusBarPainter.Cycle(const ARect: TRect; AColor: TColor);
var
  mInset, mCenter, mHead: Integer;
  mCircle: TRect;
  mPoints: array[0..2] of TPoint;
begin
  // Kreispfeil: Bogen gegen den Uhrzeigersinn von oben rechts bis 3 Uhr, dort die Spitze nach oben.
  mInset := Bar.Scale(2);
  mCircle := Rect(ARect.Left + mInset, ARect.Top + mInset, ARect.Right - mInset, ARect.Bottom - mInset);
  mCenter := (mCircle.Top + mCircle.Bottom) div 2;
  Canvas.Pen.Color := AColor;
  Canvas.Pen.Width := Max(1, Bar.Scale(3) div 2);
  Canvas.Brush.Style := bsClear;
  Canvas.Arc(mCircle.Left, mCircle.Top, mCircle.Right, mCircle.Bottom, mCircle.Right, mCircle.Top, mCircle.Right,
    mCenter);
  Canvas.Pen.Width := 1;
  mHead := Bar.Scale(3);
  mPoints[0] := Point(mCircle.Right - 1 - mHead, mCenter);
  mPoints[1] := Point(mCircle.Right - 1 + mHead, mCenter);
  mPoints[2] := Point(mCircle.Right - 1, mCenter - mHead);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := AColor;
  Canvas.Polygon(mPoints);
end;

procedure TAtlasStatusBarPainter.Badge(const ARect: TRect);
var
  mPill: TRect;
  mWidth, mHeight: Integer;
  mText: string;
begin
  // Runde Plakette in der Farbe des schwersten ungelesenen Eintrags, Zahl hell darauf.
  mText := Bar.FView.BadgeText;
  mHeight := Bar.Scale(16);
  mWidth := Max(mHeight, Measure.TextWidthOf(mText, True) + Bar.Scale(10));
  mPill := Rect(ARect.Left + Bar.Scale(SlotPadding), ARect.Top + (ARect.Height - mHeight) div 2,
    ARect.Left + Bar.Scale(SlotPadding) + mWidth, ARect.Top + (ARect.Height - mHeight) div 2 + mHeight);
  Canvas.Brush.Style := bsSolid;
  // Plakettenfarbe mit lesbarer Zahl darauf (#1255): hell dunkle Fläche mit Weiß, dunkel helle Fläche mit Dunkel.
  Canvas.Brush.Color := ToColor(Colors.Signals.ForStatus(Bar.FView.BadgeState).Solid);
  Canvas.Pen.Color := ToColor(Colors.Signals.ForStatus(Bar.FView.BadgeState).Solid);
  Canvas.RoundRect(mPill.Left, mPill.Top, mPill.Right, mPill.Bottom, mHeight, mHeight);
  Canvas.Font := Bar.Font;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := ToColor(Colors.Signals.ForStatus(Bar.FView.BadgeState).OnSolid);
  Canvas.Brush.Style := bsClear;
  DrawText(Canvas.Handle, PChar(mText), -1, mPill, DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
  Canvas.Font := Bar.Font;
end;

procedure TAtlasStatusBarPainter.Live(const ARect: TRect);
var
  mIcon, mPart: TRect;
  mTop: Integer;
begin
  mTop := ARect.Top + (ARect.Height - Measure.IconSize) div 2;
  mIcon := Rect(ARect.Left + Bar.Scale(SlotPadding), mTop, ARect.Left + Bar.Scale(SlotPadding) + Measure.IconSize,
    mTop + Measure.IconSize);
  if Bar.FView.LiveBusy then
  begin
    Cycle(mIcon, ToColor(Colors.Accent));
  end
  else
  begin
    Cycle(mIcon, ToColor(Colors.Muted));
  end;
  Canvas.Font := Bar.Font;
  Canvas.Font.Color := ToColor(Colors.Text);
  Canvas.Brush.Style := bsClear;
  mPart := Rect(mIcon.Right + Bar.Scale(4), ARect.Top, ARect.Right - Bar.Scale(SlotPadding), ARect.Bottom);
  DrawText(Canvas.Handle, PChar(Bar.FView.LiveText), -1, mPart, DT_LEFT or DT_VCENTER or DT_SINGLELINE or
    DT_NOPREFIX or DT_END_ELLIPSIS);
end;

procedure TAtlasStatusBarPainter.Method(const ARect: TRect);
var
  mPart: TRect;
  mLeft, mDetail: Integer;
  mTone: TColor;
begin
  mTone := ToColor(Colors.Muted);
  if Bar.FView.MethodOver then
  begin
    mTone := ToColor(Colors.Warn);
  end
  else if Bar.FView.MethodFound then
  begin
    mTone := ToColor(Colors.Text);
  end;
  mLeft := ARect.Left + Bar.Scale(SlotPadding);
  Canvas.Brush.Style := bsClear;
  Canvas.Font := Bar.Font;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := mTone;
  mPart := Rect(mLeft, ARect.Top, ARect.Right, ARect.Bottom);
  DrawText(Canvas.Handle, PChar(MethodSign), -1, mPart, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
  Inc(mLeft, Measure.TextWidthOf(MethodSign, True) + Bar.Scale(4));
  Canvas.Font := Bar.Font;
  Canvas.Font.Color := mTone;
  mDetail := 0;
  if Bar.FView.MethodDetail <> '' then
  begin
    mDetail := Bar.Scale(6) + Measure.TextWidthOf(Bar.FView.MethodDetail, False);
  end;
  // Erst die Kennzahlen rechts, der Name kürzt sich davor.
  mPart := Rect(mLeft, ARect.Top, Max(mLeft, ARect.Right - Bar.Scale(SlotPadding) - mDetail), ARect.Bottom);
  DrawText(Canvas.Handle, PChar(Bar.FView.MethodName), -1, mPart, DT_LEFT or DT_VCENTER or DT_SINGLELINE or
    DT_NOPREFIX or DT_END_ELLIPSIS);
  if mDetail = 0 then
  begin
    Exit;
  end;
  Canvas.Font.Color := mTone;
  if not Bar.FView.MethodOver then
  begin
    Canvas.Font.Color := ToColor(Colors.Muted);
  end;
  mPart := Rect(Min(mLeft + Measure.TextWidthOf(Bar.FView.MethodName, False), mPart.Right) + Bar.Scale(6),
    ARect.Top, ARect.Right - Bar.Scale(SlotPadding), ARect.Bottom);
  DrawText(Canvas.Handle, PChar(Bar.FView.MethodDetail), -1, mPart, DT_LEFT or DT_VCENTER or DT_SINGLELINE or
    DT_NOPREFIX);
end;

procedure TAtlasStatusBarPainter.Gear(const ARect: TRect);
var
  mIcon: TRect;
  mSize: Integer;
begin
  if HotElement = TAtlasStatusBarPart.Gear then
  begin
    Hot(ARect);
  end;
  mSize := Bar.Scale(16);
  mIcon := Rect(ARect.Left + (ARect.Width - mSize) div 2, ARect.Top + (ARect.Height - mSize) div 2,
    ARect.Left + (ARect.Width - mSize) div 2 + mSize, ARect.Top + (ARect.Height - mSize) div 2 + mSize);
  TAtlasGlyphPainter.Draw(Canvas, TAtlasToolbarIcon.Gear, mIcon, ToColor(Colors.Text), ToColor(Colors.Gutter), '');
end;

procedure TAtlasStatusBarPainter.Element(APart: TAtlasStatusBarPart; const ARect: TRect);
begin
  if (HotElement = APart) and (APart in [TAtlasStatusBarPart.Status, TAtlasStatusBarPart.Badge,
    TAtlasStatusBarPart.LiveCheck, TAtlasStatusBarPart.Method]) then
  begin
    Hot(ARect);
  end;
  case APart of
    TAtlasStatusBarPart.Status:
      Status(ARect);
    TAtlasStatusBarPart.Badge:
      Badge(ARect);
    TAtlasStatusBarPart.Findings:
      Findings(ARect);
    TAtlasStatusBarPart.LiveCheck:
      Live(ARect);
    TAtlasStatusBarPart.Method:
      Method(ARect);
  else
    // None und Gear zeichnet Paint nicht hier.
  end;
end;

{ TAtlasStatusBarMenu }

constructor TAtlasStatusBarMenu.CreateFor(ABar: TAtlasEditorStatusBar);
var
  mItem: TMenuItem;
  mIndex: Integer;
begin
  inherited Create(ABar);
  FBar := ABar;
  FIds := TAtlasStatusBarItems.All;
  for mIndex := 0 to High(FIds) do
  begin
    mItem := TMenuItem.Create(Self);
    mItem.Caption := FIds[mIndex];
    if mIndex <= High(ABar.FTexts.ItemCaptions) then
    begin
      mItem.Caption := StringReplace(ABar.FTexts.ItemCaptions[mIndex], '&', '&&', [rfReplaceAll]);
    end;
    mItem.Checked := TAtlasStatusBarItems.Contains(ABar.FView.Items, FIds[mIndex]);
    mItem.Tag := mIndex;
    mItem.OnClick := ToggleClick;
    Items.Add(mItem);
  end;
  Items.Add(NewLine);
  mItem := TMenuItem.Create(Self);
  mItem.Caption := StringReplace(ABar.FTexts.Hide, '&', '&&', [rfReplaceAll]);
  mItem.OnClick := HideClick;
  Items.Add(mItem);
end;

procedure TAtlasStatusBarMenu.ToggleClick(Sender: TObject);
var
  mIndex: Integer;
begin
  mIndex := TMenuItem(Sender).Tag;
  if (mIndex >= 0) and (mIndex <= High(FIds)) and Assigned(FBar.FEvents.ToggleItem) then
  begin
    FBar.FEvents.ToggleItem(FIds[mIndex]);
  end;
end;

procedure TAtlasStatusBarMenu.HideClick(Sender: TObject);
begin
  if Assigned(FBar.FEvents.Hide) then
  begin
    FBar.FEvents.Hide();
  end;
end;

{ TAtlasEditorStatusBar }

procedure TAtlasEditorStatusBar.ChangeScale(M, D: Integer; isDpiChange: Boolean);
begin
  inherited ChangeScale(M, D, isDpiChange);
  FLaidOut := False;
end;

procedure TAtlasEditorStatusBar.SetView(const AView: TAtlasStatusBarView);
begin
  if AView.SameAs(FView) then
  begin
    Exit;
  end;
  FView := AView;
  FLaidOut := False;
  Invalidate;
end;

procedure TAtlasEditorStatusBar.Resize;
begin
  inherited Resize;
  FLaidOut := False;
  Invalidate;
end;

procedure TAtlasEditorStatusBar.CMFontChanged(var Message: TMessage);
begin
  inherited;
  FLaidOut := False;
  Invalidate;
end;

procedure TAtlasEditorStatusBar.Layout;
var
  mMeasure: TAtlasStatusBarMeasure;
  mSlots: TArray<TAtlasStatusSlot>;
  mIndex, mGear: Integer;
begin
  if FLaidOut or not HandleAllocated then
  begin
    Exit;
  end;
  FLaidOut := True;
  mMeasure.Bar := Self;
  FPlaces := Default(TAtlasStatusBarPlaces);
  FPlaces.Parts := mMeasure.PartsOfView;
  SetLength(mSlots, Length(FPlaces.Parts));
  for mIndex := 0 to High(FPlaces.Parts) do
  begin
    mSlots[mIndex] := mMeasure.SlotOf(FPlaces.Parts[mIndex]);
  end;
  mGear := Scale(BaseGear);
  FPlaces.Spans := TAtlasStatusBarLayout.Place(TAtlasStatusBarLayout.Fit(mSlots,
    Max(0, ClientWidth - 2 * Scale(Margin) - mGear - mMeasure.Gap), mMeasure.Gap), Scale(Margin), mMeasure.Gap);
  for mIndex := 0 to High(FPlaces.Parts) do
  begin
    if (FPlaces.Parts[mIndex] = TAtlasStatusBarPart.Findings) and not FPlaces.Spans[mIndex].IsEmpty then
    begin
      FPlaces.KindSpans := TAtlasStatusBarLayout.Place(mMeasure.KindWidths,
        FPlaces.Spans[mIndex].Left + Scale(SlotPadding), 0);
    end;
  end;
  FPlaces.Gear := Rect(ClientWidth - Scale(Margin) - mGear, 0, ClientWidth - Scale(Margin), ClientHeight);
end;

function TAtlasEditorStatusBar.PartRect(APart: TAtlasStatusBarPart): TRect;
begin
  Layout;
  Result := FPlaces.PartRect(APart, ClientHeight);
end;

function TAtlasEditorStatusBar.KindRect(AKind: TAtlasFindingKind): TRect;
begin
  Layout;
  Result := FPlaces.KindRect(AKind, ClientHeight);
end;

function TAtlasEditorStatusBar.ElementAt(X, Y: Integer): TAtlasStatusBarPart;
begin
  Layout;
  Result := FPlaces.ElementAt(Point(X, Y), ClientHeight);
end;

/// <summary>Tooltip des Elements APart; das Zahnrad nennt ACustomize.</summary>
function ElementHint(const AView: TAtlasStatusBarView; APart: TAtlasStatusBarPart; const ACustomize: string): string;
begin
  case APart of
    TAtlasStatusBarPart.Status:
      Result := AView.StatusHint;
    TAtlasStatusBarPart.Badge:
      Result := AView.BadgeHint;
    TAtlasStatusBarPart.Findings:
      Result := AView.FindingsHint;
    TAtlasStatusBarPart.LiveCheck:
      Result := AView.LiveHint;
    TAtlasStatusBarPart.Method:
      Result := AView.MethodHint;
    TAtlasStatusBarPart.Gear:
      Result := ACustomize;
  else
    Result := '';
  end;
end;

function TAtlasEditorStatusBar.HintAt(X, Y: Integer): string;
begin
  Result := ElementHint(FView, ElementAt(X, Y), FTexts.Customize);
end;

function TAtlasEditorStatusBar.PartAt(X, Y: Integer): Integer;
var
  mElement: TAtlasStatusBarPart;
  mKind: Integer;
begin
  mElement := ElementAt(X, Y);
  if mElement = TAtlasStatusBarPart.None then
  begin
    Exit(PartNone);
  end;
  mKind := -1;
  if mElement = TAtlasStatusBarPart.Findings then
  begin
    mKind := FPlaces.KindAt(X);
  end;
  Result := Ord(mElement) * KindSlots + mKind + 1;
end;

function TAtlasEditorStatusBar.PartHint(APart: Integer): string;
begin
  if APart = PartNone then
  begin
    Exit('');
  end;
  Result := ElementHint(FView, TAtlasStatusBarPart(APart div KindSlots), FTexts.Customize);
end;

function TAtlasEditorStatusBar.PartEnabled(APart: Integer): Boolean;
var
  mElement: TAtlasStatusBarPart;
begin
  if APart = PartNone then
  begin
    Exit(False);
  end;
  mElement := TAtlasStatusBarPart(APart div KindSlots);
  Result := not ((mElement = TAtlasStatusBarPart.Method) and not FView.MethodFound);
end;

procedure TAtlasEditorStatusBar.Paint;
var
  mPainter: TAtlasStatusBarPainter;
  mIndex, mMiddle: Integer;
  mArea: TRect;
  mStarted: Boolean;
begin
  Layout;
  mPainter.Bar := Self;
  mPainter.Measure.Bar := Self;
  // Obere Linie: Abschluss zum Editor.
  PaintChrome(True);
  mStarted := False;
  for mIndex := 0 to High(FPlaces.Parts) do
  begin
    if FPlaces.Spans[mIndex].IsEmpty then
    begin
      Continue;
    end;
    mArea := Rect(FPlaces.Spans[mIndex].Left, 0, FPlaces.Spans[mIndex].Right, ClientHeight);
    if mStarted then
    begin
      // Trennstrich mitten im Abstand davor.
      mMiddle := mArea.Left - mPainter.Measure.Gap div 2;
      Canvas.Pen.Color := ToColor(Colors.Line);
      Canvas.MoveTo(mMiddle, Scale(5));
      Canvas.LineTo(mMiddle, ClientHeight - Scale(4));
    end;
    mStarted := True;
    mPainter.Element(FPlaces.Parts[mIndex], mArea);
  end;
  mPainter.Gear(FPlaces.Gear);
end;

procedure TAtlasEditorStatusBar.DblClick;
var
  mPosition: TPoint;
begin
  inherited DblClick;
  mPosition := ScreenToClient(Mouse.CursorPos);
  DoubleClickAt(mPosition.X, mPosition.Y);
end;

function TAtlasEditorStatusBar.KeyboardMenuPoint: TPoint;
begin
  // Von der Tastatur: am Zahnrad.
  Layout;
  Result := Point(FPlaces.Gear.Left, FPlaces.Gear.Top);
end;

procedure TAtlasEditorStatusBar.ContextMenu(const APoint: TPoint; APart: Integer);
var
  mArea: TRect;
begin
  if ElementAt(APoint.X, APoint.Y) = TAtlasStatusBarPart.Status then
  begin
    mArea := PartRect(TAtlasStatusBarPart.Status);
    if Assigned(FEvents.StatusContext) then
    begin
      FEvents.StatusContext(ClientToScreen(Point(mArea.Left, mArea.Top)));
    end;
    Exit;
  end;
  BuildMenu.Popup(ClientToScreen(APoint).X, ClientToScreen(APoint).Y);
end;

procedure TAtlasEditorStatusBar.ClickAt(X, Y: Integer);
begin
  Fire(ElementAt(X, Y), X);
end;

procedure TAtlasEditorStatusBar.PartClicked(APart: Integer; AShift: TShiftState; X, Y: Integer);
begin
  Fire(ElementAt(X, Y), X);
end;

procedure TAtlasEditorStatusBar.DoubleClickAt(X, Y: Integer);
begin
  if (ElementAt(X, Y) = TAtlasStatusBarPart.Findings) and Assigned(FEvents.FindingsOpen) then
  begin
    FEvents.FindingsOpen();
  end
  else if (ElementAt(X, Y) = TAtlasStatusBarPart.Status) and Assigned(FEvents.StatusOpen) then
  begin
    FEvents.StatusOpen();
  end;
end;

/// <summary>Linke Oberkante von ARect in Bildschirmkoordinaten von AControl.</summary>
function ScreenCorner(AControl: TControl; const ARect: TRect): TPoint;
begin
  Result := AControl.ClientToScreen(Point(ARect.Left, ARect.Top));
end;

procedure TAtlasEditorStatusBar.Fire(APart: TAtlasStatusBarPart; X: Integer);
var
  mKind: Integer;
begin
  case APart of
    TAtlasStatusBarPart.Status:
      if Assigned(FEvents.Status) then
      begin
        FEvents.Status(ScreenCorner(Self, PartRect(TAtlasStatusBarPart.Status)));
      end;
    TAtlasStatusBarPart.Findings:
      begin
        mKind := FPlaces.KindAt(X);
        if (mKind >= 0) and Assigned(FEvents.Finding) then
        begin
          FEvents.Finding(Kinds[mKind]);
        end;
      end;
    TAtlasStatusBarPart.Badge:
      if Assigned(FEvents.Badge) then
      begin
        FEvents.Badge(ScreenCorner(Self, PartRect(TAtlasStatusBarPart.Badge)));
      end;
    TAtlasStatusBarPart.LiveCheck:
      if Assigned(FEvents.LiveCheck) then
      begin
        FEvents.LiveCheck();
      end;
    TAtlasStatusBarPart.Method:
      if FView.MethodFound and Assigned(FEvents.Method) then
      begin
        FEvents.Method();
      end;
    TAtlasStatusBarPart.Gear:
      BuildMenu.Popup(ScreenCorner(Self, FPlaces.Gear).X, ScreenCorner(Self, FPlaces.Gear).Y);
    TAtlasStatusBarPart.None: ;
  end;
end;

function TAtlasEditorStatusBar.BuildMenu: TPopupMenu;
begin
  FreeAndNil(FMenu);
  FMenu := TAtlasStatusBarMenu.CreateFor(Self);
  Result := FMenu;
end;

end.
