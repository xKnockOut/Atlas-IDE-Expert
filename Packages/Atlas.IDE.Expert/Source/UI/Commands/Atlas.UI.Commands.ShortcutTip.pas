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
    procedure TimerTick(Sender: TObject);
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
  Pad = 10;
  RowGap = 6;
  CapPadX = 6;
  CapPadY = 2;
  CapRadius = 3;
  KeyGap = 3;

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

function TAtlasShortcutTipWindow.Layout(ADraw: Boolean): TSize;
var
  X, Y, RowHeight, TextHeight, CapHeight, LineWidth, CommandWidth, Right: Integer;
  Step, Key: Integer;
  Kind: TAtlasShortcutTipLink;
  Cap, Area: TRect;
  CapText, Command: string;

  procedure PutText(const AText: string; AColor: TColor);
  var
    TextRect: TRect;
  begin
    if ADraw then
    begin
      Canvas.Font.Color := AColor;
      Canvas.Brush.Style := bsClear;
      TextRect := Rect(X, Y, X + Canvas.TextWidth(AText), Y + RowHeight);
      DrawText(Canvas.Handle, PChar(AText), -1, TextRect, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
      Canvas.Brush.Style := bsSolid;
    end;
    Inc(X, Canvas.TextWidth(AText));
  end;

  procedure PutLink(ALink: TAtlasShortcutTipLink; const AText: string);
  begin
    FLinks[ALink] := Rect(X, Y, X + Canvas.TextWidth(AText), Y + TextHeight);
    if ADraw then
    begin
      Canvas.Font.Style := [];
      if FHot = ALink then
        Canvas.Font.Style := [fsUnderline];
      Canvas.Font.Color := ToColor(Colors.Accent);
      Canvas.Brush.Style := bsClear;
      Canvas.TextOut(X, Y, AText);
      Canvas.Brush.Style := bsSolid;
      Canvas.Font.Style := [];
    end;
    Inc(X, Canvas.TextWidth(AText));
  end;

begin
  Canvas.Font := UIFont;
  TextHeight := Canvas.TextHeight('Wg');
  CapHeight := TextHeight + Scale(2 * CapPadY);
  RowHeight := CapHeight;
  for Kind := Low(TAtlasShortcutTipLink) to High(TAtlasShortcutTipLink) do
    FLinks[Kind] := TRect.Empty;
  // Erste Zeile: „Tipp:“, Tastenkappen, Befehl.
  X := Scale(Pad);
  Y := Scale(Pad);
  Canvas.Font.Style := [fsBold];
  PutText(TAtlasStrings.Text(TAtlasTextId.ShortcutTipLabel), ToColor(Colors.Text));
  Canvas.Font.Style := [];
  Inc(X, Scale(KeyGap * 2));
  for Step := 0 to High(FView.Steps) do
  begin
    if Step > 0 then
    begin
      PutText(',', ToColor(Colors.Muted));
      Inc(X, Scale(KeyGap * 2));
    end;
    for Key := 0 to High(FView.Steps[Step]) do
    begin
      if Key > 0 then
      begin
        Inc(X, Scale(KeyGap));
        PutText('+', ToColor(Colors.Muted));
        Inc(X, Scale(KeyGap));
      end;
      CapText := FView.Steps[Step][Key];
      Cap := Rect(X, Y, X + Canvas.TextWidth(CapText) + Scale(2 * CapPadX), Y + CapHeight);
      if ADraw then
      begin
        FillRounded(Cap, Colors.Gutter, CapRadius);
        FrameRounded(Cap, Colors.Line, CapRadius);
        Canvas.Font.Color := ToColor(Colors.Text);
        Canvas.Brush.Style := bsClear;
        DrawText(Canvas.Handle, PChar(CapText), -1, Cap, DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
        Canvas.Brush.Style := bsSolid;
      end;
      X := Cap.Right;
    end;
  end;
  Inc(X, Scale(KeyGap * 2));
  Command := TAtlasStrings.Fmt(TAtlasTextId.ShortcutTipCommand, [FView.Command]);
  CommandWidth := Min(Canvas.TextWidth(Command), Scale(MaxCommandWidth));
  if ADraw then
  begin
    Area := Rect(X, Y, X + CommandWidth, Y + RowHeight);
    Canvas.Font.Color := ToColor(Colors.Text);
    Canvas.Brush.Style := bsClear;
    DrawText(Canvas.Handle, PChar(Command), -1, Area, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX or
      DT_END_ELLIPSIS);
    Canvas.Brush.Style := bsSolid;
  end;
  Inc(X, CommandWidth);
  LineWidth := X;
  // Zweite Zeile: Links.
  X := Scale(Pad);
  Y := Y + RowHeight + Scale(RowGap);
  PutLink(TAtlasShortcutTipLink.Never, TAtlasStrings.Text(TAtlasTextId.ShortcutTipNever));
  if FView.ShowAllKeys then
  begin
    PutText('  ·  ', ToColor(Colors.Muted));
    PutLink(TAtlasShortcutTipLink.AllKeys, TAtlasStrings.Text(TAtlasTextId.ShortcutTipAllKeys));
  end;
  Right := Max(LineWidth, X) + Scale(Pad);
  Result.cx := Right;
  Result.cy := Y + TextHeight + Scale(Pad);
end;

procedure TAtlasShortcutTipWindow.ShowTip(const AView: TAtlasShortcutTipView; const AArea: TRect);
var
  Size: TSize;
begin
  FView := AView;
  FHot := TAtlasShortcutTipLink.None;
  HandleNeeded;
  Size := Layout(False);
  ShowAt(TAtlasShortcutTips.PlaceBottomRight(AArea, Size.cx, Size.cy, Scale(Margin)));
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
      Exit;
    Dismiss;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.ShortcutTips, E);
  end;
end;

function TAtlasShortcutTipWindow.LinkAt(AX, AY: Integer): TAtlasShortcutTipLink;
var
  Link: TAtlasShortcutTipLink;
begin
  Result := TAtlasShortcutTipLink.None;
  for Link := TAtlasShortcutTipLink.Never to TAtlasShortcutTipLink.AllKeys do
    if not FLinks[Link].IsEmpty and PtInRect(FLinks[Link], Point(AX, AY)) then
      Exit(Link);
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
        FOnNever(Self);
    TAtlasShortcutTipLink.AllKeys:
      if Assigned(FOnAllKeys) then
        FOnAllKeys(Self);
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
    ClickLink(LinkAt(X, Y));
end;

procedure TAtlasShortcutTipWindow.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Hot: TAtlasShortcutTipLink;
begin
  inherited;
  Hot := LinkAt(X, Y);
  if Hot <> TAtlasShortcutTipLink.None then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
  if Hot <> FHot then
  begin
    FHot := Hot;
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
