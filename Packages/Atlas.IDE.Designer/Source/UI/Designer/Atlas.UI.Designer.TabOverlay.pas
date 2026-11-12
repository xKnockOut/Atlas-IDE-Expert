unit Atlas.UI.Designer.TabOverlay;

// Tab-Reihenfolge im Designer (#1442, #603): durchsichtiges Fenster über dem
// Formular, das an jedem Steuerelement mit TabOrder oben rechts eine kleine
// runde Marke zeigt (Zahl oder Pfad „2.1“). Auffällige Marken (Rücksprung,
// Lücke, Doppelte) stehen in Fehlerfarbe, Steuerelemente ohne TabStop grau
// mit „–“, im Modus „Reihenfolge klicken“ schon vergebene in Grün. Mit
// Farbgruppen (Group >= 0) trägt eine Marke die Farbe ihres Containers, und
// jeder Container mit Kindern bekommt einen gestrichelten Rahmen in seiner
// Farbe (SetFrames); Farben aus TAtlasColors.Placeholders. Steht die
// Maus auf einer Marke, nennt ein Hinweis den Grund (UpdateHint, vom Takt
// der Leiste aufgerufen, weil das Fenster ohne Klicken keine Maus sieht).
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
{$SCOPEDENUMS ON}
  /// <summary>Normal = Akzentfarbe, Warn = auffällig, Muted = ohne TabStop, Picked = schon geklickt.</summary>
  TAtlasTabBadgeStyle = (Normal, Warn, Muted, Picked);
{$SCOPEDENUMS OFF}

  TAtlasTabBadge = record
    Name: string;
    /// <summary>Text der Marke: TabOrder, Pfad oder „–“.</summary>
    Text: string;
    Style: TAtlasTabBadgeStyle;
    /// <summary>Hinweis, wenn die Maus auf der Marke steht; '' ohne.</summary>
    Hint: string;
    /// <summary>Oben rechts des Steuerelements im Client des Fensters.</summary>
    Anchor: TPoint;
    /// <summary>Farbgruppe für Style = Normal; -1 = Akzentfarbe.</summary>
    Group: Integer;
    class function Create(const AName, AText: string; AStyle: TAtlasTabBadgeStyle;
      const AAnchor: TPoint): TAtlasTabBadge; static;
    function SameAs(const AOther: TAtlasTabBadge): Boolean;
  end;

  /// <summary>Gestrichelter Rahmen eines Containers in der Farbe seiner Gruppe.</summary>
  TAtlasTabFrame = record
    /// <summary>Fläche des Containers im Client des Fensters.</summary>
    Bounds: TRect;
    Group: Integer;
    class function Create(const ABounds: TRect; AGroup: Integer): TAtlasTabFrame; static;
  end;

  TAtlasTabOrderOverlay = class(TForm)
  private const
    cKeyColor = TColor($00FF00FF);
  private
    FColors: TAtlasColors;
    FBadges: TArray<TAtlasTabBadge>;
    FFrames: TArray<TAtlasTabFrame>;
    FClickable: Boolean;
    FOwnerWindow: HWND;
    FShown: Boolean;
    FHintWindow: THintWindow;
    FHintIndex: Integer;
    FOnBadgeClick: TProc<string>;
    function S(AValue: Integer): Integer;
    procedure ApplyExStyle;
    procedure PaintFrames;
    procedure WMMouseActivate(var Message: TWMMouseActivate); message WM_MOUSEACTIVATE;
  protected
    function GroupColor(AGroup: Integer): TColor;
    /// <summary>Füllung der Marke: Zustand vor Farbgruppe vor Akzent.</summary>
    function BadgeColor(const ABadge: TAtlasTabBadge): TColor;
    procedure CreateParams(var Params: TCreateParams); override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    /// <summary>AOwnerWindow: Hauptfenster der IDE.</summary>
    constructor CreateOverlay(AOwner: TComponent; AOwnerWindow: HWND; const AColors: TAtlasColors);
    destructor Destroy; override;
    procedure ApplyColors(const AColors: TAtlasColors);
    /// <summary>Marken setzen; gleiche zeichnen nicht neu.</summary>
    procedure SetBadges(const ABadges: TArray<TAtlasTabBadge>);
    /// <summary>Rahmen der Container setzen; gleiche zeichnen nicht neu.</summary>
    procedure SetFrames(const AFrames: TArray<TAtlasTabFrame>);
    /// <summary>Zahl der Farbgruppen (Länge von TAtlasColors.Placeholders).</summary>
    class function GroupCount: Integer; static;
    /// <summary>Fläche der Marke AIndex im Client.</summary>
    function BadgeRect(AIndex: Integer): TRect;
    /// <summary>Marke unter dem Punkt (Client); -1 = keine.</summary>
    function BadgeAt(AX, AY: Integer): Integer;
    /// <summary>Über AScreen zeigen, ohne den Fokus zu nehmen.</summary>
    procedure ShowAt(const AScreen: TRect);
    procedure HideOverlay;
    /// <summary>Hinweis zur Marke unter ACursor (Bildschirm) zeigen, sonst ausblenden.</summary>
    procedure UpdateHint(const ACursor: TPoint);
    property Badges: TArray<TAtlasTabBadge> read FBadges;
    property Frames: TArray<TAtlasTabFrame> read FFrames;
    property Shown: Boolean read FShown;
    /// <summary>Klicks auf die Marken annehmen (Tab-Reihenfolge per Klick, experimentell).</summary>
    property Clickable: Boolean read FClickable write FClickable;
    property OnBadgeClick: TProc<string> read FOnBadgeClick write FOnBadgeClick;
  end;

implementation

uses
  System.Math;

{ TAtlasTabBadge }

class function TAtlasTabBadge.Create(const AName, AText: string; AStyle: TAtlasTabBadgeStyle;
  const AAnchor: TPoint): TAtlasTabBadge;
begin
  Result.Name := AName;
  Result.Text := AText;
  Result.Style := AStyle;
  Result.Hint := '';
  Result.Anchor := AAnchor;
  Result.Group := -1;
end;

function TAtlasTabBadge.SameAs(const AOther: TAtlasTabBadge): Boolean;
begin
  Result := (Name = AOther.Name) and (Text = AOther.Text) and (Style = AOther.Style) and (Hint = AOther.Hint) and
    (Anchor = AOther.Anchor) and (Group = AOther.Group);
end;

{ TAtlasTabFrame }

class function TAtlasTabFrame.Create(const ABounds: TRect; AGroup: Integer): TAtlasTabFrame;
begin
  Result.Bounds := ABounds;
  Result.Group := AGroup;
end;

{ TAtlasTabOrderOverlay }

constructor TAtlasTabOrderOverlay.CreateOverlay(AOwner: TComponent; AOwnerWindow: HWND;
  const AColors: TAtlasColors);
begin
  FOwnerWindow := AOwnerWindow;
  inherited CreateNew(AOwner);
  FColors := AColors;
  BorderStyle := bsNone;
  Color := cKeyColor;
  TransparentColor := True;
  TransparentColorValue := cKeyColor;
  DoubleBuffered := True;
  Font.Name := 'Segoe UI';
  Font.Size := 8;
  Font.Style := [fsBold];
  FHintIndex := -1;
end;

destructor TAtlasTabOrderOverlay.Destroy;
begin
  FHintWindow.Free;
  inherited Destroy;
end;

procedure TAtlasTabOrderOverlay.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.Style := WS_POPUP;
  Params.ExStyle := Params.ExStyle or WS_EX_NOACTIVATE or WS_EX_TOOLWINDOW;
  if FOwnerWindow <> 0 then
  begin
    Params.WndParent := FOwnerWindow;
  end;
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
  begin
    Exit;
  end;
  mStyle := GetWindowLongPtr(Handle, GWL_EXSTYLE);
  if FClickable then
  begin
    mStyle := mStyle and not WS_EX_TRANSPARENT;
  end
  else
  begin
    mStyle := mStyle or WS_EX_TRANSPARENT;
  end;
  SetWindowLongPtr(Handle, GWL_EXSTYLE, mStyle);
end;

procedure TAtlasTabOrderOverlay.SetBadges(const ABadges: TArray<TAtlasTabBadge>);
var
  mIndex: Integer;
  mSame: Boolean;
begin
  mSame := Length(ABadges) = Length(FBadges);
  if mSame then
  begin
    for mIndex := 0 to High(ABadges) do
    begin
      if not ABadges[mIndex].SameAs(FBadges[mIndex]) then
      begin
        mSame := False;
        Break;
      end;
    end;
  end;
  if mSame then
  begin
    Exit;
  end;
  FBadges := Copy(ABadges);
  Invalidate;
end;

procedure TAtlasTabOrderOverlay.SetFrames(const AFrames: TArray<TAtlasTabFrame>);
var
  mIndex: Integer;
begin
  if Length(AFrames) = Length(FFrames) then
  begin
    mIndex := 0;
    while (mIndex <= High(AFrames)) and (AFrames[mIndex].Bounds = FFrames[mIndex].Bounds) and
      (AFrames[mIndex].Group = FFrames[mIndex].Group) do
    begin
      Inc(mIndex);
    end;
    if mIndex > High(AFrames) then
    begin
      Exit;
    end;
  end;
  FFrames := Copy(AFrames);
  Invalidate;
end;

class function TAtlasTabOrderOverlay.GroupCount: Integer;
begin
  Result := High(TAtlasPlaceholderColors) - Low(TAtlasPlaceholderColors) + 1;
end;

function TAtlasTabOrderOverlay.GroupColor(AGroup: Integer): TColor;
begin
  Result := TColor(FColors.Placeholders[AGroup mod GroupCount]);
end;

function TAtlasTabOrderOverlay.BadgeColor(const ABadge: TAtlasTabBadge): TColor;
begin
  case ABadge.Style of
    TAtlasTabBadgeStyle.Warn:
      Result := TColor(FColors.Error);
    TAtlasTabBadgeStyle.Muted:
      Result := TColor(FColors.Muted);
    TAtlasTabBadgeStyle.Picked:
      Result := TColor(FColors.Add);
  else
    if ABadge.Group >= 0 then
    begin
      Result := GroupColor(ABadge.Group);
    end
    else
    begin
      Result := TColor(FColors.Accent);
    end;
  end;
end;

procedure TAtlasTabOrderOverlay.PaintFrames;
var
  mFrame: TAtlasTabFrame;
  mRect: TRect;
begin
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Style := psDash;
  Canvas.Pen.Width := 1;
  for mFrame in FFrames do
  begin
    // Etwas nach innen, damit verschachtelte Rahmen nicht auf einer Linie liegen.
    mRect := mFrame.Bounds;
    mRect.Inflate(-S(2), -S(2));
    Canvas.Pen.Color := GroupColor(mFrame.Group);
    Canvas.Rectangle(mRect);
  end;
  Canvas.Pen.Style := psSolid;
  Canvas.Brush.Style := bsSolid;
end;

function TAtlasTabOrderOverlay.BadgeRect(AIndex: Integer): TRect;
var
  mWidth: Integer;
  mAnchor: TPoint;
begin
  mAnchor := FBadges[AIndex].Anchor;
  // Breite nach Zeichen statt Textmaß: braucht kein Fenster. Rund bis zwei Zeichen, länger als Pille.
  mWidth := Max(S(16), S(4) + S(6) * Length(FBadges[AIndex].Text));
  Result := Rect(mAnchor.X - S(2) - mWidth, mAnchor.Y + S(2), mAnchor.X - S(2), mAnchor.Y + S(18));
end;

function TAtlasTabOrderOverlay.BadgeAt(AX, AY: Integer): Integer;
var
  mIndex: Integer;
begin
  // Rückwärts: Später gezeichnete Marken liegen oben.
  for mIndex := High(FBadges) downto 0 do
  begin
    if BadgeRect(mIndex).Contains(Point(AX, AY)) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure TAtlasTabOrderOverlay.Paint;
var
  mIndex: Integer;
  mRect: TRect;
  mText: string;
  mBack: TColor;
begin
  Canvas.Brush.Color := cKeyColor;
  Canvas.FillRect(ClientRect);
  PaintFrames;
  Canvas.Font.Assign(Font);
  for mIndex := 0 to High(FBadges) do
  begin
    mRect := BadgeRect(mIndex);
    mBack := BadgeColor(FBadges[mIndex]);
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := mBack;
    Canvas.Pen.Color := mBack;
    Canvas.RoundRect(mRect.Left, mRect.Top, mRect.Right, mRect.Bottom, mRect.Height, mRect.Height);
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := TColor(FColors.Surface);
    mText := FBadges[mIndex].Text;
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
  begin
    Exit;
  end;
  mIndex := BadgeAt(X, Y);
  if (mIndex >= 0) and Assigned(FOnBadgeClick) then
  begin
    FOnBadgeClick(FBadges[mIndex].Name);
  end;
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
  UpdateHint(Point(-MaxInt div 2, -MaxInt div 2));
  if FShown and HandleAllocated then
  begin
    ShowWindow(Handle, SW_HIDE);
  end;
  FShown := False;
end;

procedure TAtlasTabOrderOverlay.UpdateHint(const ACursor: TPoint);
var
  mIndex: Integer;
  mClient: TPoint;
  mRect: TRect;
begin
  mIndex := -1;
  if FShown and HandleAllocated then
  begin
    mClient := ScreenToClient(ACursor);
    mIndex := BadgeAt(mClient.X, mClient.Y);
  end;
  if (mIndex >= 0) and (FBadges[mIndex].Hint = '') then
  begin
    mIndex := -1;
  end;
  if mIndex = FHintIndex then
  begin
    Exit;
  end;
  FHintIndex := mIndex;
  if mIndex < 0 then
  begin
    if (FHintWindow <> nil) and FHintWindow.HandleAllocated then
    begin
      FHintWindow.ReleaseHandle;
    end;
    Exit;
  end;
  if FHintWindow = nil then
  begin
    FHintWindow := THintWindow.Create(nil);
  end;
  mRect := FHintWindow.CalcHintRect(S(400), FBadges[mIndex].Hint, nil);
  mRect.Offset(ACursor.X, ACursor.Y + S(20));
  FHintWindow.ActivateHint(mRect, FBadges[mIndex].Hint);
end;

end.
