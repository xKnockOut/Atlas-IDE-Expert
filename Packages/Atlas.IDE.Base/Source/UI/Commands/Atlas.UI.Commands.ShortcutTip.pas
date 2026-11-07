unit Atlas.UI.Commands.ShortcutTip;

// Tastenkürzel-Tipp (#600) als kleines Atlas-Popup (#410/#411): ohne Fokus,
// unten rechts in der übergebenen Fläche (Editorfenster). Erste Zeile
// „Tipp: [Strg]+[Umschalt]+[C] für „Klasse vervollständigen““ mit den Tasten als
// Tastenkappen, bei Kürzeln mit zwei Schritten beide („[Strg]+[K], [Strg]+[D]“);
// darunter die Links „Nicht mehr zeigen“ (OnNever, nur für diesen Befehl) und
// „Alle Kürzel“ (OnAllKeys, öffnet die Übersicht aus #520; nur, wenn die
// Übersicht eingeschaltet ist). Nach TAtlasShortcutTips.VisibleMs (4 s)
// verschwindet der Tipp von selbst, solange die Maus nicht darüber steht; die
// nächste Taste schließt ihn über die IDE-Schicht (Dismiss). Reine VCL, ohne
// Open Tools API.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Atlas.Core.Commands.ShortcutTips,
  Atlas.UI.Popup.Window;

type
  {$SCOPEDENUMS ON}
  TAtlasShortcutTipLink = (None, Never, AllKeys);
  {$SCOPEDENUMS OFF}

  TAtlasShortcutTipWindow = class(TAtlasPopupWindow)
  public const
    /// <summary>Abstand zum Rand der Fläche, logische Pixel.</summary>
    Margin = 12;
    /// <summary>Höchste Breite des Befehlsnamens, logische Pixel; länger endet mit „…“.</summary>
    MaxCommandWidth = 360;
  private
    FView: TAtlasShortcutTipView;
    FLinks: array[TAtlasShortcutTipLink] of TRect;
    FHot: TAtlasShortcutTipLink;
    FTimer: TTimer;
    FOnNever: TNotifyEvent;
    FOnAllKeys: TNotifyEvent;
    // Stand von Layout: Schreibstelle, Zeilen- und Texthöhe, zeichnen oder nur messen.
    FX: Integer;
    FY: Integer;
    FRowHeight: Integer;
    FTextHeight: Integer;
    FDraw: Boolean;
    procedure TimerTick(Sender: TObject);
    /// <summary>Text an der Schreibstelle, rückt sie weiter.</summary>
    procedure PutText(const AText: string; AColor: TColor);
    /// <summary>Link an der Schreibstelle; merkt seine Fläche.</summary>
    procedure PutLink(ALink: TAtlasShortcutTipLink; const AText: string);
    /// <summary>Tastenkappe an der Schreibstelle.</summary>
    procedure PutCap(const AText: string);
    /// <summary>Alle Schritte des Kürzels als Tastenkappen.</summary>
    procedure PutKeys;
    /// <summary>Befehlsname, höchstens MaxCommandWidth breit.</summary>
    procedure PutCommand;
    /// <summary>Misst bzw. zeichnet (ADraw) den Inhalt; setzt die Flächen der Links.</summary>
    function Layout(ADraw: Boolean): TSize;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Zeigt AView unten rechts in AArea (Bildschirmkoordinaten) und startet die Zeit bis zum
    /// Ausblenden.</summary>
    procedure ShowTip(const AView: TAtlasShortcutTipView; const AArea: TRect);
    /// <summary>Ausblenden (nächste Taste, Zeit abgelaufen, Link geklickt).</summary>
    procedure Dismiss;
    /// <summary>Link an der Stelle (Client-Koordinaten).</summary>
    function LinkAt(AX, AY: Integer): TAtlasShortcutTipLink;
    /// <summary>Fläche eines Links; leer, wenn er fehlt.</summary>
    function LinkRect(ALink: TAtlasShortcutTipLink): TRect;
    /// <summary>Wie ein Klick auf den Link: Ereignis, dann ausblenden.</summary>
    procedure ClickLink(ALink: TAtlasShortcutTipLink);
    /// <summary>Text für die Sprachausgabe: „Tipp: Strg+Umschalt+C für Klasse vervollständigen“.</summary>
    function SpokenText: string;
    property View: TAtlasShortcutTipView read FView;
    property Timer: TTimer read FTimer;
    property OnNever: TNotifyEvent read FOnNever write FOnNever;
    property OnAllKeys: TNotifyEvent read FOnAllKeys write FOnAllKeys;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Strings,
  Atlas.UI.Popup.Accessibility;

const
  cPad = 10;
  cRowGap = 6;
  cCapPadX = 6;
  cCapPadY = 2;
  cCapRadius = 3;
  cKeyGap = 3;

{ TAtlasShortcutTipWindow }

constructor TAtlasShortcutTipWindow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  GuardFeature := TAtlasFeature.ShortcutTips;
  SetAccessible(UiaToolTipControlType, TAtlasStrings.Text(TAtlasTextId.AccessShortcutTip));
  FHot := TAtlasShortcutTipLink.None;
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := TAtlasShortcutTips.VisibleMs;
  FTimer.OnTimer := TimerTick;
end;

function TAtlasShortcutTipWindow.SpokenText: string;
begin
  Result := TAtlasStrings.Fmt(TAtlasTextId.ShortcutTipSpoken, [FView.KeyText, FView.Command]);
end;

procedure TAtlasShortcutTipWindow.PutText(const AText: string; AColor: TColor);
var
  mTextRect: TRect;
begin
  if FDraw then
  begin
    Canvas.Font.Color := AColor;
    Canvas.Brush.Style := bsClear;
    mTextRect := Rect(FX, FY, FX + Canvas.TextWidth(AText), FY + FRowHeight);
    DrawText(Canvas.Handle, PChar(AText), -1, mTextRect, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
    Canvas.Brush.Style := bsSolid;
  end;
  Inc(FX, Canvas.TextWidth(AText));
end;

procedure TAtlasShortcutTipWindow.PutLink(ALink: TAtlasShortcutTipLink; const AText: string);
begin
  FLinks[ALink] := Rect(FX, FY, FX + Canvas.TextWidth(AText), FY + FTextHeight);
  if FDraw then
  begin
    Canvas.Font.Style := [];
    if FHot = ALink then
    begin
      Canvas.Font.Style := [fsUnderline];
    end;
    Canvas.Font.Color := ToColor(Colors.Accent);
    Canvas.Brush.Style := bsClear;
    Canvas.TextOut(FX, FY, AText);
    Canvas.Brush.Style := bsSolid;
    Canvas.Font.Style := [];
  end;
  Inc(FX, Canvas.TextWidth(AText));
end;

procedure TAtlasShortcutTipWindow.PutCap(const AText: string);
var
  mCap: TRect;
begin
  mCap := Rect(FX, FY, FX + Canvas.TextWidth(AText) + Scale(2 * cCapPadX), FY + FRowHeight);
  if FDraw then
  begin
    FillRounded(mCap, Colors.Gutter, cCapRadius);
    FrameRounded(mCap, Colors.Line, cCapRadius);
    Canvas.Font.Color := ToColor(Colors.Text);
    Canvas.Brush.Style := bsClear;
    DrawText(Canvas.Handle, PChar(AText), -1, mCap, DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
    Canvas.Brush.Style := bsSolid;
  end;
  FX := mCap.Right;
end;

procedure TAtlasShortcutTipWindow.PutKeys;
var
  mStep, mKey: Integer;
begin
  for mStep := 0 to High(FView.Steps) do
  begin
    if mStep > 0 then
    begin
      PutText(',', ToColor(Colors.Muted));
      Inc(FX, Scale(cKeyGap * 2));
    end;
    for mKey := 0 to High(FView.Steps[mStep]) do
    begin
      if mKey > 0 then
      begin
        Inc(FX, Scale(cKeyGap));
        PutText('+', ToColor(Colors.Muted));
        Inc(FX, Scale(cKeyGap));
      end;
      PutCap(FView.Steps[mStep][mKey]);
    end;
  end;
end;

procedure TAtlasShortcutTipWindow.PutCommand;
var
  mCommand: string;
  mWidth: Integer;
  mArea: TRect;
begin
  mCommand := TAtlasStrings.Fmt(TAtlasTextId.ShortcutTipCommand, [FView.Command]);
  mWidth := Min(Canvas.TextWidth(mCommand), Scale(MaxCommandWidth));
  if FDraw then
  begin
    mArea := Rect(FX, FY, FX + mWidth, FY + FRowHeight);
    Canvas.Font.Color := ToColor(Colors.Text);
    Canvas.Brush.Style := bsClear;
    DrawText(Canvas.Handle, PChar(mCommand), -1, mArea, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX or
      DT_END_ELLIPSIS);
    Canvas.Brush.Style := bsSolid;
  end;
  Inc(FX, mWidth);
end;

function TAtlasShortcutTipWindow.Layout(ADraw: Boolean): TSize;
var
  mLineWidth: Integer;
  mKind: TAtlasShortcutTipLink;
begin
  FDraw := ADraw;
  Canvas.Font := UIFont;
  FTextHeight := Canvas.TextHeight('Wg');
  // Zeilenhöhe = Höhe der Tastenkappen.
  FRowHeight := FTextHeight + Scale(2 * cCapPadY);
  for mKind := Low(TAtlasShortcutTipLink) to High(TAtlasShortcutTipLink) do
  begin
    FLinks[mKind] := TRect.Empty;
  end;
  // Erste Zeile: „Tipp:“, Tastenkappen, Befehl.
  FX := Scale(cPad);
  FY := Scale(cPad);
  Canvas.Font.Style := [fsBold];
  PutText(TAtlasStrings.Text(TAtlasTextId.ShortcutTipLabel), ToColor(Colors.Text));
  Canvas.Font.Style := [];
  Inc(FX, Scale(cKeyGap * 2));
  PutKeys;
  Inc(FX, Scale(cKeyGap * 2));
  PutCommand;
  mLineWidth := FX;
  // Zweite Zeile: Links.
  FX := Scale(cPad);
  FY := FY + FRowHeight + Scale(cRowGap);
  PutLink(TAtlasShortcutTipLink.Never, TAtlasStrings.Text(TAtlasTextId.ShortcutTipNever));
  if FView.ShowAllKeys then
  begin
    PutText('  ·  ', ToColor(Colors.Muted));
    PutLink(TAtlasShortcutTipLink.AllKeys, TAtlasStrings.Text(TAtlasTextId.ShortcutTipAllKeys));
  end;
  Result.cx := Max(mLineWidth, FX) + Scale(cPad);
  Result.cy := FY + FTextHeight + Scale(cPad);
end;

procedure TAtlasShortcutTipWindow.ShowTip(const AView: TAtlasShortcutTipView; const AArea: TRect);
var
  mSize: TSize;
begin
  FView := AView;
  FHot := TAtlasShortcutTipLink.None;
  HandleNeeded;
  mSize := Layout(False);
  ShowAt(TAtlasShortcutTips.PlaceBottomRight(AArea, mSize.cx, mSize.cy, Scale(Margin)));
  Announce(SpokenText);
  FTimer.Enabled := False;
  FTimer.Interval := TAtlasShortcutTips.VisibleMs;
  FTimer.Enabled := True;
end;

procedure TAtlasShortcutTipWindow.Dismiss;
begin
  FTimer.Enabled := False;
  FHot := TAtlasShortcutTipLink.None;
  HidePopup;
end;

procedure TAtlasShortcutTipWindow.TimerTick(Sender: TObject);
begin
  try
    // Wer gerade auf den Tipp zeigt, will klicken: noch einmal so lange.
    if IsShown and PtInRect(BoundsRect, Mouse.CursorPos) then
    begin
      Exit;
    end;
    Dismiss;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.ShortcutTips, E);
  end;
end;

function TAtlasShortcutTipWindow.LinkAt(AX, AY: Integer): TAtlasShortcutTipLink;
var
  mLink: TAtlasShortcutTipLink;
begin
  Result := TAtlasShortcutTipLink.None;
  for mLink := TAtlasShortcutTipLink.Never to TAtlasShortcutTipLink.AllKeys do
  begin
    if not FLinks[mLink].IsEmpty and PtInRect(FLinks[mLink], Point(AX, AY)) then
    begin
      Exit(mLink);
    end;
  end;
end;

function TAtlasShortcutTipWindow.LinkRect(ALink: TAtlasShortcutTipLink): TRect;
begin
  Result := FLinks[ALink];
end;

procedure TAtlasShortcutTipWindow.ClickLink(ALink: TAtlasShortcutTipLink);
begin
  case ALink of
    TAtlasShortcutTipLink.Never:
      if Assigned(FOnNever) then
      begin
        FOnNever(Self);
      end;
    TAtlasShortcutTipLink.AllKeys:
      if Assigned(FOnAllKeys) then
      begin
        FOnAllKeys(Self);
      end;
  else
    Exit;
  end;
  Dismiss;
end;

procedure TAtlasShortcutTipWindow.Paint;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  Layout(True);
  PaintBorder;
end;

procedure TAtlasShortcutTipWindow.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if Button = mbLeft then
  begin
    ClickLink(LinkAt(X, Y));
  end;
end;

procedure TAtlasShortcutTipWindow.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mHot: TAtlasShortcutTipLink;
begin
  inherited;
  mHot := LinkAt(X, Y);
  if mHot <> TAtlasShortcutTipLink.None then
  begin
    Cursor := crHandPoint;
  end
  else
  begin
    Cursor := crDefault;
  end;
  if mHot <> FHot then
  begin
    FHot := mHot;
    Invalidate;
  end;
end;

procedure TAtlasShortcutTipWindow.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  if FHot <> TAtlasShortcutTipLink.None then
  begin
    FHot := TAtlasShortcutTipLink.None;
    Invalidate;
  end;
end;

end.
