unit Atlas.UI.StatusBar.Bar;

// Atlas-Statusleiste (#1155), Darstellung: eine Zeile unten am Editor, über der
// Statuszeile der IDE. Die Höhe hängt nur von der DPI ab, nie vom Inhalt.
// - SetView setzt den Inhalt (TAtlasStatusBarView); gleicher Inhalt zeichnet
//   nicht neu. Elemente in der Reihenfolge von View.Items:
//   status: Punkt in Zustandsfarbe und Text („Atlas · bereit“);
//   findings: Zähler je Art mit den Symbolen aus „Atlas-Prüfung“;
//   liveCheck: „live · geprüft vor 2 s“, „prüft …“, „beim Speichern“;
//   method: „ƒ TFoo.Bar · 4 Zeilen · CC 2“, über der Grenze in Warnfarbe.
//   Rechts außen steht immer das Zahnrad.
// - Passt nicht alles, verteilt TAtlasStatusBarLayout die Breite: Die Methode
//   kürzt ihren Namen zuerst (mit „…“), die Kennzahlen bleiben; nichts bricht
//   um.
// - Klick (beim Loslassen über dem Element; das Verlassen der Leiste zwischen
//   Drücken und Loslassen bricht nicht ab, siehe Editorleiste #1101): Status
//   meldet OnStatus, ein Zähler OnFinding mit seiner Art, die Methode
//   OnMethod, das Zahnrad öffnet das Menü „Leiste anpassen“. Doppelklick auf
//   die Zähler meldet OnFindingsOpen. Rechtsklick auf den Status meldet
//   OnStatusContext, sonst öffnet er das Menü. WM_CONTEXTMENU behandelt die
//   Leiste selbst; es geht nicht an das Editorfenster der IDE weiter.
// - Menü „Leiste anpassen“: jedes Element mit Haken (OnToggleItem), darunter
//   „Statusleiste ausblenden“ (OnHide).
// - Tooltip je Element (View); das Zahnrad nennt „Leiste anpassen …“.

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
  Atlas.Core.Problems.Findings,
  Atlas.Core.StatusBar.Content,
  Atlas.Core.StatusBar.Layout;

type
{$SCOPEDENUMS ON}
  TAtlasStatusBarPart = (None, Status, Findings, LiveCheck, Method, Gear);
{$SCOPEDENUMS OFF}

  TAtlasStatusBarView = record
    /// <summary>Sichtbare Elemente in Reihenfolge (TAtlasStatusBarItems).</summary>
    Items: TArray<string>;
    StatusText: string;
    StatusHint: string;
    StatusColor: TAtlasColor;
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
  end;

  TAtlasStatusBarKindEvent = reference to procedure(AKind: TAtlasFindingKind);
  TAtlasStatusBarItemEvent = reference to procedure(const AId: string);

  TAtlasEditorStatusBar = class(TCustomControl)
  private
    FView: TAtlasStatusBarView;
    FColors: TAtlasColors;
    FParts: TArray<TAtlasStatusBarPart>;
    FSpans: TArray<TAtlasStatusSpan>;
    FKindSpans: TArray<TAtlasStatusSpan>;
    FGearRect: TRect;
    FLaidOut: Boolean;
    FHot: TAtlasStatusBarPart;
    FHotKind: Integer;
    FDown: TAtlasStatusBarPart;
    FSkipUp: Boolean;
    FMenu: TPopupMenu;
    FMenuIds: TArray<string>;
    FItemCaptions: TArray<string>;
    FCustomizeCaption: string;
    FHideCaption: string;
    FOnStatus: TProc<TPoint>;
    FOnStatusContext: TProc<TPoint>;
    FOnFinding: TAtlasStatusBarKindEvent;
    FOnFindingsOpen: TProc;
    FOnMethod: TProc;
    FOnToggleItem: TAtlasStatusBarItemEvent;
    FOnHide: TProc;
    function Scale(AValue: Integer): Integer;
    function Gap: Integer;
    function DotSize: Integer;
    function IconSize: Integer;
    function TextWidthOf(const AText: string; ABold: Boolean): Integer;
    function KindWidth(AKind: TAtlasFindingKind): Integer;
    function SlotOf(APart: TAtlasStatusBarPart): TAtlasStatusSlot;
    function PartsOfView: TArray<TAtlasStatusBarPart>;
    procedure Layout;
    function PartAt(X, Y: Integer): TAtlasStatusBarPart;
    function KindAt(X, Y: Integer): Integer;
    function PartHint(APart: TAtlasStatusBarPart): string;
    procedure DrawStatus(const ARect: TRect);
    procedure DrawFindings(const ARect: TRect);
    procedure DrawCycle(const ARect: TRect; AColor: TColor);
    procedure DrawLive(const ARect: TRect);
    procedure DrawMethod(const ARect: TRect);
    procedure DrawGear(const ARect: TRect);
    procedure DrawHot(const ARect: TRect);
    procedure Fire(APart: TAtlasStatusBarPart; X, Y: Integer);
    procedure ToggleClick(Sender: TObject);
    procedure HideClick(Sender: TObject);
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
    procedure CMFontChanged(var Message: TMessage); message CM_FONTCHANGED;
    procedure WMContextMenu(var Message: TWMContextMenu); message WM_CONTEXTMENU;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    procedure ChangeScale(M, D: Integer; isDpiChange: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetView(const AView: TAtlasStatusBarView);
    procedure SetColors(const AColors: TAtlasColors);
    /// <summary>Höhe der Leiste bei APPI (eine Zeile, 22 px bei 96 DPI).</summary>
    class function BarHeight(APPI: Integer): Integer; static;
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
    /// <summary>Menütexte der Elemente in der Reihenfolge von TAtlasStatusBarItems.All.</summary>
    property ItemCaptions: TArray<string> read FItemCaptions write FItemCaptions;
    property CustomizeCaption: string read FCustomizeCaption write FCustomizeCaption;
    property HideCaption: string read FHideCaption write FHideCaption;
    property OnStatus: TProc<TPoint> read FOnStatus write FOnStatus;
    property OnStatusContext: TProc<TPoint> read FOnStatusContext write FOnStatusContext;
    property OnFinding: TAtlasStatusBarKindEvent read FOnFinding write FOnFinding;
    property OnFindingsOpen: TProc read FOnFindingsOpen write FOnFindingsOpen;
    property OnMethod: TProc read FOnMethod write FOnMethod;
    property OnToggleItem: TAtlasStatusBarItemEvent read FOnToggleItem write FOnToggleItem;
    property OnHide: TProc read FOnHide write FOnHide;
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
  /// <summary>Zähler von links nach rechts; Index wie in FKindSpans.</summary>
  Kinds: array[0..2] of TAtlasFindingKind = (TAtlasFindingKind.Error, TAtlasFindingKind.Warning,
    TAtlasFindingKind.Info);

const
  /// <summary>Höhe bei 96 DPI.</summary>
  BaseHeight = 22;
  BaseGap = 13;
  BaseGear = 22;
  Margin = 4;
  Padding = 4;
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
  Kind: TAtlasFindingKind;
begin
  Result := (string.Join(',', Items) = string.Join(',', AOther.Items)) and (StatusText = AOther.StatusText) and
    (StatusHint = AOther.StatusHint) and (StatusColor = AOther.StatusColor) and
    (FindingsShown = AOther.FindingsShown) and (FindingsHint = AOther.FindingsHint) and
    (LiveText = AOther.LiveText) and (LiveHint = AOther.LiveHint) and (LiveBusy = AOther.LiveBusy) and
    (MethodFound = AOther.MethodFound) and (MethodName = AOther.MethodName) and
    (MethodDetail = AOther.MethodDetail) and (MethodHint = AOther.MethodHint) and (MethodOver = AOther.MethodOver);
  if not Result then
    Exit;
  for Kind := Low(TAtlasFindingKind) to High(TAtlasFindingKind) do
    if Counts[Kind] <> AOther.Counts[Kind] then
      Exit(False);
end;

{ TAtlasEditorStatusBar }

constructor TAtlasEditorStatusBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque] - [csSetCaption];
  DoubleBuffered := True;
  TabStop := False;
  ShowHint := True;
  FColors := TAtlasColors.Light;
  FHot := TAtlasStatusBarPart.None;
  FHotKind := -1;
  FDown := TAtlasStatusBarPart.None;
  FCustomizeCaption := '';
  FHideCaption := '';
  Height := BarHeight(96);
  Constraints.MinHeight := Height;
  Constraints.MaxHeight := Height;
end;

destructor TAtlasEditorStatusBar.Destroy;
begin
  FMenu.Free;
  inherited Destroy;
end;

class function TAtlasEditorStatusBar.BarHeight(APPI: Integer): Integer;
begin
  Result := MulDiv(BaseHeight, Max(APPI, 96), 96);
end;

procedure TAtlasEditorStatusBar.ChangeScale(M, D: Integer; isDpiChange: Boolean);
begin
  Constraints.MinHeight := 0;
  Constraints.MaxHeight := 0;
  inherited ChangeScale(M, D, isDpiChange);
  Height := BarHeight(CurrentPPI);
  Constraints.MinHeight := Height;
  Constraints.MaxHeight := Height;
  FLaidOut := False;
end;

function TAtlasEditorStatusBar.Scale(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, Max(CurrentPPI, 96), 96);
end;

function TAtlasEditorStatusBar.Gap: Integer;
begin
  Result := Scale(BaseGap);
end;

function TAtlasEditorStatusBar.DotSize: Integer;
begin
  Result := Scale(8);
end;

function TAtlasEditorStatusBar.IconSize: Integer;
begin
  Result := Scale(14);
end;

procedure TAtlasEditorStatusBar.SetView(const AView: TAtlasStatusBarView);
begin
  if AView.SameAs(FView) then
    Exit;
  FView := AView;
  FLaidOut := False;
  Invalidate;
end;

procedure TAtlasEditorStatusBar.SetColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
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

function TAtlasEditorStatusBar.TextWidthOf(const AText: string; ABold: Boolean): Integer;
begin
  Canvas.Font := Font;
  if ABold then
    Canvas.Font.Style := [fsBold];
  Result := Canvas.TextWidth(AText);
  Canvas.Font := Font;
end;

function TAtlasEditorStatusBar.KindWidth(AKind: TAtlasFindingKind): Integer;
begin
  Result := IconSize + Scale(3) + TextWidthOf(IntToStr(FView.Counts[AKind]), False) + Scale(6);
end;

function TAtlasEditorStatusBar.SlotOf(APart: TAtlasStatusBarPart): TAtlasStatusSlot;
var
  Width_, Minimum, Index: Integer;
begin
  case APart of
    TAtlasStatusBarPart.Status:
      begin
        Width_ := Scale(Padding) + DotSize + Scale(5) + TextWidthOf(FView.StatusText, False) + Scale(Padding);
        Minimum := Scale(Padding) + DotSize + Scale(5) + TextWidthOf(Ellipsis, False) + Scale(Padding);
        Result := TAtlasStatusSlot.Create(Width_, Minimum, ShrinkStatus);
      end;
    TAtlasStatusBarPart.Findings:
      begin
        Width_ := Scale(Padding);
        for Index := 0 to High(Kinds) do
          Inc(Width_, KindWidth(Kinds[Index]));
        Result := TAtlasStatusSlot.Create(Width_, Width_, ShrinkFindings);
      end;
    TAtlasStatusBarPart.LiveCheck:
      begin
        Width_ := Scale(Padding) + IconSize + Scale(4) + TextWidthOf(FView.LiveText, False) + Scale(Padding);
        Minimum := Scale(Padding) + IconSize + Scale(4) + TextWidthOf(Ellipsis, False) + Scale(Padding);
        Result := TAtlasStatusSlot.Create(Width_, Minimum, ShrinkLive);
      end;
  else
    begin
      // Methode: Zeichen, Name (kürzbar), Kennzahlen (bleiben).
      Width_ := Scale(Padding) + TextWidthOf(MethodSign, True) + Scale(4) + TextWidthOf(FView.MethodName, False) +
        Scale(Padding);
      Minimum := Scale(Padding) + TextWidthOf(MethodSign, True) + Scale(4) + TextWidthOf(Ellipsis, False) +
        Scale(Padding);
      if FView.MethodDetail <> '' then
      begin
        Inc(Width_, Scale(6) + TextWidthOf(FView.MethodDetail, False));
        Inc(Minimum, Scale(6) + TextWidthOf(FView.MethodDetail, False));
      end;
      Result := TAtlasStatusSlot.Create(Width_, Minimum, ShrinkMethod);
    end;
  end;
end;

function TAtlasEditorStatusBar.PartsOfView: TArray<TAtlasStatusBarPart>;
var
  Id: string;
begin
  Result := nil;
  for Id in FView.Items do
    if SameText(Id, TAtlasStatusBarItems.Status) then
      Result := Result + [TAtlasStatusBarPart.Status]
    else if SameText(Id, TAtlasStatusBarItems.Findings) then
    begin
      if FView.FindingsShown then
        Result := Result + [TAtlasStatusBarPart.Findings];
    end
    else if SameText(Id, TAtlasStatusBarItems.LiveCheck) then
      Result := Result + [TAtlasStatusBarPart.LiveCheck]
    else if SameText(Id, TAtlasStatusBarItems.Method) then
      Result := Result + [TAtlasStatusBarPart.Method];
end;

procedure TAtlasEditorStatusBar.Layout;
var
  Slots: TArray<TAtlasStatusSlot>;
  Widths, KindWidths: TArray<Integer>;
  Index, Kind, Available, Gear: Integer;
begin
  if FLaidOut or not HandleAllocated then
    Exit;
  FLaidOut := True;
  FParts := PartsOfView;
  SetLength(Slots, Length(FParts));
  for Index := 0 to High(FParts) do
    Slots[Index] := SlotOf(FParts[Index]);
  Gear := Scale(BaseGear);
  Available := ClientWidth - 2 * Scale(Margin) - Gear - Gap;
  Widths := TAtlasStatusBarLayout.Fit(Slots, Max(0, Available), Gap);
  FSpans := TAtlasStatusBarLayout.Place(Widths, Scale(Margin), Gap);
  FKindSpans := nil;
  for Index := 0 to High(FParts) do
    if (FParts[Index] = TAtlasStatusBarPart.Findings) and not FSpans[Index].IsEmpty then
    begin
      SetLength(KindWidths, Length(Kinds));
      for Kind := 0 to High(Kinds) do
        KindWidths[Kind] := KindWidth(Kinds[Kind]);
      FKindSpans := TAtlasStatusBarLayout.Place(KindWidths, FSpans[Index].Left + Scale(Padding), 0);
    end;
  FGearRect := Rect(ClientWidth - Scale(Margin) - Gear, 0, ClientWidth - Scale(Margin), ClientHeight);
end;

function TAtlasEditorStatusBar.PartRect(APart: TAtlasStatusBarPart): TRect;
var
  Index: Integer;
begin
  Layout;
  if APart = TAtlasStatusBarPart.Gear then
    Exit(FGearRect);
  for Index := 0 to High(FParts) do
    if (FParts[Index] = APart) and not FSpans[Index].IsEmpty then
      Exit(Rect(FSpans[Index].Left, 0, FSpans[Index].Right, ClientHeight));
  Result := TRect.Empty;
end;

function TAtlasEditorStatusBar.KindRect(AKind: TAtlasFindingKind): TRect;
var
  Index: Integer;
begin
  Layout;
  for Index := 0 to High(FKindSpans) do
    if Kinds[Index] = AKind then
      Exit(Rect(FKindSpans[Index].Left, 0, FKindSpans[Index].Right, ClientHeight));
  Result := TRect.Empty;
end;

function TAtlasEditorStatusBar.PartAt(X, Y: Integer): TAtlasStatusBarPart;
var
  Index: Integer;
begin
  Layout;
  Result := TAtlasStatusBarPart.None;
  if (Y < 0) or (Y >= ClientHeight) then
    Exit;
  if FGearRect.Contains(Point(X, Y)) then
    Exit(TAtlasStatusBarPart.Gear);
  Index := TAtlasStatusBarLayout.IndexAt(FSpans, X);
  if Index >= 0 then
    Result := FParts[Index];
end;

function TAtlasEditorStatusBar.KindAt(X, Y: Integer): Integer;
begin
  Result := -1;
  if PartAt(X, Y) = TAtlasStatusBarPart.Findings then
    Result := TAtlasStatusBarLayout.IndexAt(FKindSpans, X);
end;

function TAtlasEditorStatusBar.PartHint(APart: TAtlasStatusBarPart): string;
begin
  case APart of
    TAtlasStatusBarPart.Status:
      Result := FView.StatusHint;
    TAtlasStatusBarPart.Findings:
      Result := FView.FindingsHint;
    TAtlasStatusBarPart.LiveCheck:
      Result := FView.LiveHint;
    TAtlasStatusBarPart.Method:
      Result := FView.MethodHint;
    TAtlasStatusBarPart.Gear:
      Result := FCustomizeCaption;
  else
    Result := '';
  end;
end;

function TAtlasEditorStatusBar.HintAt(X, Y: Integer): string;
begin
  Result := PartHint(PartAt(X, Y));
end;

procedure TAtlasEditorStatusBar.DrawHot(const ARect: TRect);
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(FColors.Selection);
  Canvas.Pen.Color := ToColor(FColors.Line);
  Canvas.RoundRect(ARect.Left, ARect.Top + Scale(2), ARect.Right, ARect.Bottom - Scale(2), Scale(4), Scale(4));
end;

procedure TAtlasEditorStatusBar.DrawStatus(const ARect: TRect);
var
  Center, Left_: Integer;
  Part: TRect;
begin
  Center := (ARect.Top + ARect.Bottom) div 2;
  Left_ := ARect.Left + Scale(Padding);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(FView.StatusColor);
  Canvas.Pen.Color := ToColor(FView.StatusColor);
  Canvas.Ellipse(Left_, Center - DotSize div 2, Left_ + DotSize, Center - DotSize div 2 + DotSize);
  Canvas.Font := Font;
  Canvas.Font.Color := ToColor(FColors.Text);
  Canvas.Brush.Style := bsClear;
  Part := Rect(Left_ + DotSize + Scale(5), ARect.Top, ARect.Right - Scale(Padding), ARect.Bottom);
  DrawText(Canvas.Handle, PChar(FView.StatusText), -1, Part, DT_LEFT or DT_VCENTER or DT_SINGLELINE or
    DT_NOPREFIX or DT_END_ELLIPSIS);
end;

procedure TAtlasEditorStatusBar.DrawFindings(const ARect: TRect);
var
  Index, Top_: Integer;
  Icon, Part: TRect;
  Count: Integer;
begin
  Top_ := ARect.Top + (ARect.Height - IconSize) div 2;
  for Index := 0 to High(FKindSpans) do
  begin
    if FKindSpans[Index].IsEmpty then
      Continue;
    if (FHot = TAtlasStatusBarPart.Findings) and (FHotKind = Index) then
      DrawHot(Rect(FKindSpans[Index].Left - Scale(2), ARect.Top, FKindSpans[Index].Right - Scale(2),
        ARect.Bottom));
    Icon := Rect(FKindSpans[Index].Left, Top_, FKindSpans[Index].Left + IconSize, Top_ + IconSize);
    TAtlasFindingIcon.Draw(Canvas, Icon, Kinds[Index], TAtlasFindingIcon.KindColor(Kinds[Index]), clWhite, clBlack);
    Count := FView.Counts[Kinds[Index]];
    Canvas.Font := Font;
    // Null gedämpft: Nichts zu tun.
    if Count = 0 then
      Canvas.Font.Color := ToColor(FColors.Muted)
    else
      Canvas.Font.Color := ToColor(FColors.Text);
    Canvas.Brush.Style := bsClear;
    Part := Rect(Icon.Right + Scale(3), ARect.Top, FKindSpans[Index].Right, ARect.Bottom);
    DrawText(Canvas.Handle, PChar(IntToStr(Count)), -1, Part, DT_LEFT or DT_VCENTER or DT_SINGLELINE or
      DT_NOPREFIX);
  end;
end;

procedure TAtlasEditorStatusBar.DrawCycle(const ARect: TRect; AColor: TColor);
var
  Inset, Center, Head: Integer;
  Circle: TRect;
  Points: array[0..2] of TPoint;
begin
  // Kreispfeil: Bogen gegen den Uhrzeigersinn von oben rechts bis 3 Uhr, dort die Spitze nach oben.
  Inset := Scale(2);
  Circle := Rect(ARect.Left + Inset, ARect.Top + Inset, ARect.Right - Inset, ARect.Bottom - Inset);
  Center := (Circle.Top + Circle.Bottom) div 2;
  Canvas.Pen.Color := AColor;
  Canvas.Pen.Width := Max(1, Scale(3) div 2);
  Canvas.Brush.Style := bsClear;
  Canvas.Arc(Circle.Left, Circle.Top, Circle.Right, Circle.Bottom, Circle.Right, Circle.Top, Circle.Right, Center);
  Canvas.Pen.Width := 1;
  Head := Scale(3);
  Points[0] := Point(Circle.Right - 1 - Head, Center);
  Points[1] := Point(Circle.Right - 1 + Head, Center);
  Points[2] := Point(Circle.Right - 1, Center - Head);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := AColor;
  Canvas.Polygon(Points);
end;

procedure TAtlasEditorStatusBar.DrawLive(const ARect: TRect);
var
  Icon, Part: TRect;
  Tone: TColor;
  Top_: Integer;
begin
  Top_ := ARect.Top + (ARect.Height - IconSize) div 2;
  Icon := Rect(ARect.Left + Scale(Padding), Top_, ARect.Left + Scale(Padding) + IconSize, Top_ + IconSize);
  if FView.LiveBusy then
    Tone := ToColor(FColors.Accent)
  else
    Tone := ToColor(FColors.Muted);
  DrawCycle(Icon, Tone);
  Canvas.Font := Font;
  Canvas.Font.Color := ToColor(FColors.Text);
  Canvas.Brush.Style := bsClear;
  Part := Rect(Icon.Right + Scale(4), ARect.Top, ARect.Right - Scale(Padding), ARect.Bottom);
  DrawText(Canvas.Handle, PChar(FView.LiveText), -1, Part, DT_LEFT or DT_VCENTER or DT_SINGLELINE or
    DT_NOPREFIX or DT_END_ELLIPSIS);
end;

procedure TAtlasEditorStatusBar.DrawMethod(const ARect: TRect);
var
  Part: TRect;
  Left_, Detail: Integer;
  Tone: TColor;
begin
  if FView.MethodOver then
    Tone := ToColor(FColors.Warn)
  else if FView.MethodFound then
    Tone := ToColor(FColors.Text)
  else
    Tone := ToColor(FColors.Muted);
  Left_ := ARect.Left + Scale(Padding);
  Canvas.Brush.Style := bsClear;
  Canvas.Font := Font;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := Tone;
  Part := Rect(Left_, ARect.Top, ARect.Right, ARect.Bottom);
  DrawText(Canvas.Handle, PChar(MethodSign), -1, Part, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
  Inc(Left_, TextWidthOf(MethodSign, True) + Scale(4));
  Canvas.Font := Font;
  Canvas.Font.Color := Tone;
  Detail := 0;
  if FView.MethodDetail <> '' then
    Detail := Scale(6) + TextWidthOf(FView.MethodDetail, False);
  // Erst die Kennzahlen rechts, der Name kürzt sich davor.
  Part := Rect(Left_, ARect.Top, Max(Left_, ARect.Right - Scale(Padding) - Detail), ARect.Bottom);
  DrawText(Canvas.Handle, PChar(FView.MethodName), -1, Part, DT_LEFT or DT_VCENTER or DT_SINGLELINE or
    DT_NOPREFIX or DT_END_ELLIPSIS);
  if Detail = 0 then
    Exit;
  Canvas.Font.Color := Tone;
  if not FView.MethodOver then
    Canvas.Font.Color := ToColor(FColors.Muted);
  Part := Rect(Min(Left_ + TextWidthOf(FView.MethodName, False), Part.Right) + Scale(6), ARect.Top,
    ARect.Right - Scale(Padding), ARect.Bottom);
  DrawText(Canvas.Handle, PChar(FView.MethodDetail), -1, Part, DT_LEFT or DT_VCENTER or DT_SINGLELINE or
    DT_NOPREFIX);
end;

procedure TAtlasEditorStatusBar.DrawGear(const ARect: TRect);
var
  Icon: TRect;
  Size: Integer;
begin
  if FHot = TAtlasStatusBarPart.Gear then
    DrawHot(ARect);
  Size := Scale(16);
  Icon := Rect(ARect.Left + (ARect.Width - Size) div 2, ARect.Top + (ARect.Height - Size) div 2,
    ARect.Left + (ARect.Width - Size) div 2 + Size, ARect.Top + (ARect.Height - Size) div 2 + Size);
  TAtlasGlyphPainter.Draw(Canvas, TAtlasToolbarIcon.Gear, Icon, ToColor(FColors.Text), ToColor(FColors.Gutter), '');
end;

procedure TAtlasEditorStatusBar.Paint;
var
  Index, Middle: Integer;
  Area: TRect;
  Started: Boolean;
begin
  Layout;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(FColors.Gutter);
  Canvas.FillRect(ClientRect);
  // Obere Linie: Abschluss zum Editor.
  Canvas.Pen.Color := ToColor(FColors.Line);
  Canvas.MoveTo(0, 0);
  Canvas.LineTo(ClientWidth, 0);
  Started := False;
  for Index := 0 to High(FParts) do
  begin
    if FSpans[Index].IsEmpty then
      Continue;
    Area := Rect(FSpans[Index].Left, 0, FSpans[Index].Right, ClientHeight);
    if Started then
    begin
      // Trennstrich mitten im Abstand davor.
      Middle := Area.Left - Gap div 2;
      Canvas.Pen.Color := ToColor(FColors.Line);
      Canvas.MoveTo(Middle, Scale(5));
      Canvas.LineTo(Middle, ClientHeight - Scale(4));
    end;
    Started := True;
    if (FHot = FParts[Index]) and (FParts[Index] in [TAtlasStatusBarPart.Status, TAtlasStatusBarPart.Method]) then
      DrawHot(Area);
    case FParts[Index] of
      TAtlasStatusBarPart.Status:
        DrawStatus(Area);
      TAtlasStatusBarPart.Findings:
        DrawFindings(Area);
      TAtlasStatusBarPart.LiveCheck:
        DrawLive(Area);
      TAtlasStatusBarPart.Method:
        DrawMethod(Area);
    end;
  end;
  DrawGear(FGearRect);
end;

procedure TAtlasEditorStatusBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Hot: TAtlasStatusBarPart;
  HotKind: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  Hot := PartAt(X, Y);
  HotKind := KindAt(X, Y);
  if (Hot = FHot) and (HotKind = FHotKind) then
    Exit;
  FHot := Hot;
  FHotKind := HotKind;
  if (Hot = TAtlasStatusBarPart.None) or (Hot = TAtlasStatusBarPart.LiveCheck) or
    ((Hot = TAtlasStatusBarPart.Method) and not FView.MethodFound) then
    Cursor := crDefault
  else
    Cursor := crHandPoint;
  Application.CancelHint;
  Hint := PartHint(Hot);
  Invalidate;
end;

procedure TAtlasEditorStatusBar.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  // FDown bleibt: Das Verlassen kommt in der IDE zwischen Drücken und Loslassen jedes Klicks (#1101).
  if (FHot = TAtlasStatusBarPart.None) and (FHotKind < 0) then
    Exit;
  FHot := TAtlasStatusBarPart.None;
  FHotKind := -1;
  Invalidate;
end;

procedure TAtlasEditorStatusBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  // Das Loslassen nach einem Doppelklick ist kein zweiter Klick.
  FSkipUp := ssDouble in Shift;
  FDown := PartAt(X, Y);
end;

procedure TAtlasEditorStatusBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Released: TAtlasStatusBarPart;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  if FSkipUp then
  begin
    FSkipUp := False;
    FDown := TAtlasStatusBarPart.None;
    Exit;
  end;
  // Erst beim Loslassen; nur ein Drücken auf einem anderen Element bricht ab (#1101).
  Released := PartAt(X, Y);
  if (Released <> TAtlasStatusBarPart.None) and ((FDown = TAtlasStatusBarPart.None) or (FDown = Released)) then
    Fire(Released, X, Y);
  FDown := TAtlasStatusBarPart.None;
end;

procedure TAtlasEditorStatusBar.DblClick;
var
  Position: TPoint;
begin
  inherited DblClick;
  Position := ScreenToClient(Mouse.CursorPos);
  if (PartAt(Position.X, Position.Y) = TAtlasStatusBarPart.Findings) and Assigned(FOnFindingsOpen) then
    FOnFindingsOpen();
end;

procedure TAtlasEditorStatusBar.WMContextMenu(var Message: TWMContextMenu);
var
  Position, Corner: TPoint;
  Area: TRect;
begin
  // Nicht inherited: Sonst ginge das Kontextmenü an das Editorfenster der IDE weiter.
  Message.Result := 1;
  if (Message.XPos = -1) and (Message.YPos = -1) then
    // Von der Tastatur: am Zahnrad.
    Position := Point(FGearRect.Left, FGearRect.Top)
  else
    Position := ScreenToClient(SmallPointToPoint(Message.Pos));
  if PartAt(Position.X, Position.Y) = TAtlasStatusBarPart.Status then
  begin
    Area := PartRect(TAtlasStatusBarPart.Status);
    Corner := ClientToScreen(Point(Area.Left, Area.Top));
    if Assigned(FOnStatusContext) then
      FOnStatusContext(Corner);
    Exit;
  end;
  BuildMenu.Popup(ClientToScreen(Position).X, ClientToScreen(Position).Y);
end;

procedure TAtlasEditorStatusBar.ClickAt(X, Y: Integer);
begin
  Fire(PartAt(X, Y), X, Y);
end;

procedure TAtlasEditorStatusBar.DoubleClickAt(X, Y: Integer);
begin
  if (PartAt(X, Y) = TAtlasStatusBarPart.Findings) and Assigned(FOnFindingsOpen) then
    FOnFindingsOpen();
end;

procedure TAtlasEditorStatusBar.Fire(APart: TAtlasStatusBarPart; X, Y: Integer);
var
  Area: TRect;
  Kind: Integer;
begin
  case APart of
    TAtlasStatusBarPart.Status:
      if Assigned(FOnStatus) then
      begin
        Area := PartRect(TAtlasStatusBarPart.Status);
        FOnStatus(ClientToScreen(Point(Area.Left, Area.Top)));
      end;
    TAtlasStatusBarPart.Findings:
      begin
        Kind := KindAt(X, Y);
        if (Kind >= 0) and Assigned(FOnFinding) then
          FOnFinding(Kinds[Kind]);
      end;
    TAtlasStatusBarPart.Method:
      if FView.MethodFound and Assigned(FOnMethod) then
        FOnMethod();
    TAtlasStatusBarPart.Gear:
      BuildMenu.Popup(ClientToScreen(Point(FGearRect.Left, FGearRect.Top)).X,
        ClientToScreen(Point(FGearRect.Left, FGearRect.Top)).Y);
  end;
end;

function TAtlasEditorStatusBar.BuildMenu: TPopupMenu;
var
  Item: TMenuItem;
  Ids: TArray<string>;
  Index: Integer;
begin
  FreeAndNil(FMenu);
  FMenu := TPopupMenu.Create(nil);
  Ids := TAtlasStatusBarItems.All;
  FMenuIds := Ids;
  for Index := 0 to High(Ids) do
  begin
    Item := TMenuItem.Create(FMenu);
    if Index <= High(FItemCaptions) then
      Item.Caption := StringReplace(FItemCaptions[Index], '&', '&&', [rfReplaceAll])
    else
      Item.Caption := Ids[Index];
    Item.Checked := TAtlasStatusBarItems.Contains(FView.Items, Ids[Index]);
    Item.Tag := Index;
    Item.OnClick := ToggleClick;
    FMenu.Items.Add(Item);
  end;
  FMenu.Items.Add(NewLine);
  Item := TMenuItem.Create(FMenu);
  Item.Caption := StringReplace(FHideCaption, '&', '&&', [rfReplaceAll]);
  Item.OnClick := HideClick;
  FMenu.Items.Add(Item);
  Result := FMenu;
end;

procedure TAtlasEditorStatusBar.ToggleClick(Sender: TObject);
var
  Index: Integer;
begin
  Index := TMenuItem(Sender).Tag;
  if (Index >= 0) and (Index <= High(FMenuIds)) and Assigned(FOnToggleItem) then
    FOnToggleItem(FMenuIds[Index]);
end;

procedure TAtlasEditorStatusBar.HideClick(Sender: TObject);
begin
  if Assigned(FOnHide) then
    FOnHide();
end;

end.
