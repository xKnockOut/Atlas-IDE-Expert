unit Atlas.UI.Designer.TabOverlay;

// Tab-Reihenfolge im Designer (#1442): durchsichtiges Fenster über dem
// Formular, das an jedem fokussierbaren Steuerelement oben links seine
// TabOrder als kleine Marke zeigt. Marken, zu denen die Reihenfolge gegen die
// Lesereihenfolge zurückspringt, stehen in Warnfarbe.
// - Das Fenster gehört dem Hauptfenster der IDE (liegt damit über dem
//   Designer), nimmt nie den Fokus und erscheint nicht in der Taskleiste.
// - Durchsichtig über eine Schlüsselfarbe: Klicks daneben gehen an den
//   Designer. Ohne Klicken (Clickable = False, Vorgabe) gehen alle Klicks
//   durch (WS_EX_TRANSPARENT); mit Klicken (experimentell) meldet ein Klick auf
//   eine Marke OnBadgeClick.
// Lage, Marken und Sichtbarkeit setzt Atlas.IDE.Designer.Bar.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Forms,
  Atlas.Core.Style.Palette;

type
  TAtlasTabBadge = record
    Name: string;
    Number: Integer;
    /// <summary>Sprung gegen die Lesereihenfolge.</summary>
    Warn: Boolean;
    /// <summary>Oben links des Steuerelements im Client des Fensters.</summary>
    Anchor: TPoint;
    class function Create(const AName: string; ANumber: Integer; AWarn: Boolean;
      const AAnchor: TPoint): TAtlasTabBadge; static;
  end;

  TAtlasTabOrderOverlay = class(TForm)
  private const
    KeyColor = TColor($00FF00FF);
  private
    FColors: TAtlasColors;
    FBadges: TArray<TAtlasTabBadge>;
    FClickable: Boolean;
    FOwnerWindow: HWND;
    FShown: Boolean;
    FOnBadgeClick: TProc<string>;
    function S(AValue: Integer): Integer;
    procedure ApplyExStyle;
    procedure WMMouseActivate(var Message: TWMMouseActivate); message WM_MOUSEACTIVATE;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    /// <summary>AOwnerWindow: Hauptfenster der IDE.</summary>
    constructor CreateOverlay(AOwner: TComponent; AOwnerWindow: HWND; const AColors: TAtlasColors);
    procedure ApplyColors(const AColors: TAtlasColors);
    /// <summary>Marken setzen; gleiche zeichnen nicht neu.</summary>
    procedure SetBadges(const ABadges: TArray<TAtlasTabBadge>);
    /// <summary>Fläche der Marke AIndex im Client.</summary>
    function BadgeRect(AIndex: Integer): TRect;
    /// <summary>Marke unter dem Punkt (Client); -1 = keine.</summary>
    function BadgeAt(X, Y: Integer): Integer;
    /// <summary>Über AScreen zeigen, ohne den Fokus zu nehmen.</summary>
    procedure ShowAt(const AScreen: TRect);
    procedure HideOverlay;
    property Badges: TArray<TAtlasTabBadge> read FBadges;
    property Shown: Boolean read FShown;
    /// <summary>Klicks auf die Marken annehmen (Tab-Reihenfolge per Klick, experimentell).</summary>
    property Clickable: Boolean read FClickable write FClickable;
    property OnBadgeClick: TProc<string> read FOnBadgeClick write FOnBadgeClick;
  end;

implementation

uses
  System.Math;

{ TAtlasTabBadge }

class function TAtlasTabBadge.Create(const AName: string; ANumber: Integer; AWarn: Boolean;
  const AAnchor: TPoint): TAtlasTabBadge;
begin
  Result.Name := AName;
  Result.Number := ANumber;
  Result.Warn := AWarn;
  Result.Anchor := AAnchor;
end;

{ TAtlasTabOrderOverlay }

constructor TAtlasTabOrderOverlay.CreateOverlay(AOwner: TComponent; AOwnerWindow: HWND;
  const AColors: TAtlasColors);
begin
  FOwnerWindow := AOwnerWindow;
  inherited CreateNew(AOwner);
  FColors := AColors;
  BorderStyle := bsNone;
  Color := KeyColor;
  TransparentColor := True;
  TransparentColorValue := KeyColor;
  DoubleBuffered := True;
  Font.Name := 'Segoe UI';
  Font.Size := 8;
  Font.Style := [fsBold];
end;

procedure TAtlasTabOrderOverlay.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.Style := WS_POPUP;
  Params.ExStyle := Params.ExStyle or WS_EX_NOACTIVATE or WS_EX_TOOLWINDOW;
  if FOwnerWindow <> 0 then
    Params.WndParent := FOwnerWindow;
end;

procedure TAtlasTabOrderOverlay.WMMouseActivate(var Message: TWMMouseActivate);
begin
  // Klick auf eine Marke: Fokus bleibt im Designer.
  Message.Result := MA_NOACTIVATE;
end;

function TAtlasTabOrderOverlay.S(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, Screen.PixelsPerInch, 96);
end;

procedure TAtlasTabOrderOverlay.ApplyColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  Invalidate;
end;

procedure TAtlasTabOrderOverlay.ApplyExStyle;
var
  mStyle: NativeInt;
begin
  if not HandleAllocated then
    Exit;
  mStyle := GetWindowLongPtr(Handle, GWL_EXSTYLE);
  if FClickable then
    mStyle := mStyle and not WS_EX_TRANSPARENT
  else
    mStyle := mStyle or WS_EX_TRANSPARENT;
  SetWindowLongPtr(Handle, GWL_EXSTYLE, mStyle);
end;

procedure TAtlasTabOrderOverlay.SetBadges(const ABadges: TArray<TAtlasTabBadge>);
var
  mIndex: Integer;
  mSame: Boolean;
begin
  mSame := Length(ABadges) = Length(FBadges);
  if mSame then
    for mIndex := 0 to High(ABadges) do
      if (ABadges[mIndex].Name <> FBadges[mIndex].Name) or (ABadges[mIndex].Number <> FBadges[mIndex].Number) or
        (ABadges[mIndex].Warn <> FBadges[mIndex].Warn) or (ABadges[mIndex].Anchor <> FBadges[mIndex].Anchor) then
      begin
        mSame := False;
        Break;
      end;
  if mSame then
    Exit;
  FBadges := Copy(ABadges);
  Invalidate;
end;

function TAtlasTabOrderOverlay.BadgeRect(AIndex: Integer): TRect;
var
  mWidth: Integer;
  mAnchor: TPoint;
begin
  mAnchor := FBadges[AIndex].Anchor;
  // Breite nach Stellen statt Textmaß: braucht kein Fenster.
  mWidth := S(8) + S(7) * Length(IntToStr(FBadges[AIndex].Number));
  Result := Rect(mAnchor.X + S(2), mAnchor.Y + S(2), mAnchor.X + S(2) + Max(S(16), mWidth), mAnchor.Y + S(18));
end;

function TAtlasTabOrderOverlay.BadgeAt(X, Y: Integer): Integer;
var
  mIndex: Integer;
begin
  // Rückwärts: Später gezeichnete Marken liegen oben.
  for mIndex := High(FBadges) downto 0 do
    if BadgeRect(mIndex).Contains(Point(X, Y)) then
      Exit(mIndex);
  Result := -1;
end;

procedure TAtlasTabOrderOverlay.Paint; // lsp-ignore: component-missing-inherited -- zeichnet die ganze Fläche
var
  mIndex: Integer;
  mRect: TRect;
  mText: string;
  mBack: TColor;
begin
  Canvas.Brush.Color := KeyColor;
  Canvas.FillRect(ClientRect);
  Canvas.Font.Assign(Font);
  for mIndex := 0 to High(FBadges) do
  begin
    mRect := BadgeRect(mIndex);
    if FBadges[mIndex].Warn then
      mBack := TColor(FColors.Warn)
    else
      mBack := TColor(FColors.Accent);
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := mBack;
    Canvas.Pen.Color := mBack;
    Canvas.RoundRect(mRect.Left, mRect.Top, mRect.Right, mRect.Bottom, S(6), S(6));
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := TColor(FColors.Surface);
    mText := IntToStr(FBadges[mIndex].Number);
    DrawText(Canvas.Handle, PChar(mText), -1, mRect, DT_SINGLELINE or DT_VCENTER or DT_CENTER or DT_NOPREFIX);
  end;
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasTabOrderOverlay.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mIndex: Integer;
begin
  inherited;
  if not FClickable or (Button <> mbLeft) then
    Exit;
  mIndex := BadgeAt(X, Y);
  if (mIndex >= 0) and Assigned(FOnBadgeClick) then
    FOnBadgeClick(FBadges[mIndex].Name);
end;

procedure TAtlasTabOrderOverlay.ShowAt(const AScreen: TRect);
begin
  if AScreen.IsEmpty then
  begin
    HideOverlay;
    Exit;
  end;
  HandleNeeded;
  ApplyExStyle;
  SetWindowPos(Handle, HWND_TOP, AScreen.Left, AScreen.Top, AScreen.Width, AScreen.Height,
    SWP_NOACTIVATE or SWP_SHOWWINDOW);
  FShown := True;
end;

procedure TAtlasTabOrderOverlay.HideOverlay;
begin
  if FShown and HandleAllocated then
    ShowWindow(Handle, SW_HIDE);
  FShown := False;
end;

end.
