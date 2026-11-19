unit Atlas.UI.Editor.OverviewRuler;

// Übersichtsleiste (#519), Darstellung: ein schmaler Streifen rechts neben
// der Scrollleiste des Editors. Er zeigt die ganze Datei: der sichtbare
// Bereich als heller Block, die Marken aus TAtlasOverview.Layout in drei
// Spuren (links Änderungen, Mitte Treffer, Lesezeichen und Haltepunkte,
// rechts Diagnosen), der Cursor als Linie quer. Farben nach Art aus den
// Farben des Themas (#411).
// - Klick springt (OnJump) zur getroffenen Marke, sonst zur Zeile an der
//   Stelle.
// - Überfahren meldet Zeile und Marke (OnHover) für die Vorschau; Verlassen
//   meldet OnHoverEnd.
// Gleiche Marken zeichnen nicht neu.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Overview;

type
  /// <summary>Maus über Zeile ALine; AMark ist die getroffene Marke (-1 ohne), APoint die Mausposition am
  /// Bildschirm.</summary>
  TAtlasOverviewHoverEvent = reference to procedure(ALine, AMark: Integer; const APoint: TPoint);

  TAtlasOverviewRuler = class(TCustomControl)
  private
    FMarks: TAtlasOverviewMarks;
    FBars: TAtlasOverviewBars;
    FLineCount: Integer;
    FFirstVisible: Integer;
    FLastVisible: Integer;
    FColors: TAtlasColors;
    FLaidOut: Boolean;
    FHoverLine: Integer;
    FHoverMark: Integer;
    FOnJump: TProc<Integer>;
    FOnHover: TAtlasOverviewHoverEvent;
    FOnHoverEnd: TProc;
    function Scale(AValue: Integer): Integer;
    procedure Layout;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure ChangeScale(M, D: Integer; isDpiChange: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Marken der Datei mit ALineCount Zeilen; sichtbar sind AFirstVisible bis ALastVisible (0-basiert).
    /// Gleicher Stand zeichnet nicht neu.</summary>
    procedure SetMarks(const AMarks: TAtlasOverviewMarks; ALineCount, AFirstVisible, ALastVisible: Integer);
    procedure SetColors(const AColors: TAtlasColors);
    /// <summary>Zeile an AY (Client).</summary>
    function LineAtY(AY: Integer): Integer;
    /// <summary>Marke an AY (Client) mit Toleranz; -1 ohne.</summary>
    function MarkAtY(AY: Integer): Integer;
    /// <summary>Ziel eines Klicks auf AY: Zeile der Marke, sonst die Zeile an der Stelle.</summary>
    function TargetAtY(AY: Integer): Integer;
    /// <summary>Farbe einer Art aus den Farben des Themas.</summary>
    class function ColorOf(const AColors: TAtlasColors; AKind: TAtlasOverviewMarkKind): TAtlasColor; static;
    /// <summary>Breite des Streifens bei APPI.</summary>
    class function RulerWidth(APPI: Integer): Integer; static;
    property Marks: TAtlasOverviewMarks read FMarks;
    property LineCount: Integer read FLineCount;
    property OnJump: TProc<Integer> read FOnJump write FOnJump;
    property OnHover: TAtlasOverviewHoverEvent read FOnHover write FOnHover;
    property OnHoverEnd: TProc read FOnHoverEnd write FOnHoverEnd;
  end;

implementation

uses
  System.Math;

const
  /// <summary>Breite bei 96 DPI.</summary>
  cBaseWidth = 14;
  /// <summary>Mindesthöhe einer Marke und Spiel beim Klick bei 96 DPI.</summary>
  cBaseMinHeight = 3;
  cBaseTolerance = 3;
  /// <summary>Bildschirmauflösung, auf die sich alle Maße beziehen.</summary>
  cDefaultPpi = 96;
  /// <summary>Mindesthöhe des sichtbaren Bereichs und Mindestbreite einer Spur bei 96 DPI; Zahl der Spuren.
  /// </summary>
  cMinVisibleHeight = 4;
  cMinInner = 3;
  cLanes = 3;
  /// <summary>Anteil der Rinnenfarbe am Hintergrund und der Textfarbe am sichtbaren Bereich.</summary>
  cGutterShare = 0.5;
  cVisibleShare = 0.1;

{ TAtlasOverviewRuler }

constructor TAtlasOverviewRuler.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque] - [csSetCaption];
  DoubleBuffered := True;
  TabStop := False;
  FColors := TAtlasColors.Light;
  FHoverLine := -1;
  FHoverMark := -1;
  FLastVisible := -1;
  Width := RulerWidth(cDefaultPpi);
  Constraints.MinWidth := Width;
  Constraints.MaxWidth := Width;
end;

procedure TAtlasOverviewRuler.Paint;
var
  mBar: TAtlasOverviewBar;
  mInner, mLane, mLeft, mRight, mTop, mBottom: Integer;
  mArea: TRect;
begin
  Layout;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := TColor(TAtlasColorMath.Mix(FColors.Gutter, FColors.Surface, cGutterShare));
  Canvas.FillRect(ClientRect);
  if FLineCount <= 0 then
  begin
    Exit;
  end;
  // Sichtbarer Bereich.
  if FLastVisible >= FFirstVisible then
  begin
    mTop := TAtlasOverview.PixelOf(FFirstVisible, FLineCount, ClientHeight);
    mBottom := Max(mTop + Scale(cMinVisibleHeight), TAtlasOverview.PixelOf(FLastVisible + 1, FLineCount, ClientHeight));
    Canvas.Brush.Color := TColor(TAtlasColorMath.Mix(FColors.Text, FColors.Surface, cVisibleShare));
    Canvas.FillRect(TRect.Create(0, mTop, ClientWidth, Min(mBottom, ClientHeight)));
  end;
  mInner := Max(Scale(cMinInner), (ClientWidth - Scale(2)) div cLanes);
  for mBar in FBars do
  begin
    mLane := Scale(1);
    case mBar.Lane of
      TAtlasOverviewLane.Left:
        begin
          mLeft := mLane;
          mRight := mLeft + mInner;
        end;
      TAtlasOverviewLane.Middle:
        begin
          mLeft := mLane + mInner;
          mRight := mLeft + mInner;
        end;
      TAtlasOverviewLane.Right:
        begin
          mLeft := mLane + 2 * mInner;
          mRight := ClientWidth - mLane;
        end;
    else
      begin
        mLeft := 0;
        mRight := ClientWidth;
      end;
    end;
    mArea := TRect.Create(mLeft, mBar.Top, mRight, mBar.Bottom);
    // Der Cursor ist eine dünne Linie über die ganze Breite.
    if mBar.Kind = TAtlasOverviewMarkKind.Cursor then
    begin
      mArea.Bottom := Min(mArea.Bottom, mArea.Top + Scale(2));
    end;
    Canvas.Brush.Color := TColor(ColorOf(FColors, mBar.Kind));
    Canvas.FillRect(mArea);
  end;
end;

procedure TAtlasOverviewRuler.Resize;
begin
  inherited Resize;
  FLaidOut := False;
  Invalidate;
end;

procedure TAtlasOverviewRuler.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if (Button <> mbLeft) or (FLineCount <= 0) then
  begin
    Exit;
  end;
  if Assigned(FOnHoverEnd) then
  begin
    FOnHoverEnd;
  end;
  FHoverLine := -1;
  if Assigned(FOnJump) then
  begin
    FOnJump(TargetAtY(Y));
  end;
end;

procedure TAtlasOverviewRuler.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mMark, mLine: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  if FLineCount <= 0 then
  begin
    Exit;
  end;
  mMark := MarkAtY(Y);
  mLine := TargetAtY(Y);
  if (mLine = FHoverLine) and (mMark = FHoverMark) then
  begin
    Exit;
  end;
  FHoverLine := mLine;
  FHoverMark := mMark;
  if Assigned(FOnHover) then
  begin
    FOnHover(mLine, mMark, ClientToScreen(Point(X, Y)));
  end;
end;

procedure TAtlasOverviewRuler.ChangeScale(M, D: Integer; isDpiChange: Boolean);
begin
  Constraints.MinWidth := 0;
  Constraints.MaxWidth := 0;
  inherited ChangeScale(M, D, isDpiChange);
  Width := RulerWidth(CurrentPPI);
  Constraints.MinWidth := Width;
  Constraints.MaxWidth := Width;
  FLaidOut := False;
end;

function TAtlasOverviewRuler.Scale(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, Max(CurrentPPI, cDefaultPpi), cDefaultPpi);
end;

procedure TAtlasOverviewRuler.Layout;
begin
  if FLaidOut then
  begin
    Exit;
  end;
  FBars := TAtlasOverview.Layout(FMarks, FLineCount, ClientHeight, Scale(cBaseMinHeight));
  FLaidOut := True;
end;

procedure TAtlasOverviewRuler.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  FHoverLine := -1;
  FHoverMark := -1;
  if Assigned(FOnHoverEnd) then
  begin
    FOnHoverEnd;
  end;
end;

procedure TAtlasOverviewRuler.SetMarks(const AMarks: TAtlasOverviewMarks; ALineCount, AFirstVisible,
  ALastVisible: Integer);
begin
  if TAtlasOverview.Same(AMarks, FMarks) and (ALineCount = FLineCount) and (AFirstVisible = FFirstVisible) and
    (ALastVisible = FLastVisible) then
  begin
    Exit;
  end;
  FMarks := AMarks;
  FLineCount := ALineCount;
  FFirstVisible := AFirstVisible;
  FLastVisible := ALastVisible;
  FLaidOut := False;
  Invalidate;
end;

procedure TAtlasOverviewRuler.SetColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  Invalidate;
end;

function TAtlasOverviewRuler.LineAtY(AY: Integer): Integer;
begin
  Result := TAtlasOverview.LineAt(AY, FLineCount, ClientHeight);
end;

function TAtlasOverviewRuler.MarkAtY(AY: Integer): Integer;
begin
  Layout;
  if not TAtlasOverview.Hit(FBars, AY, Scale(cBaseTolerance), Result) then
  begin
    Result := -1;
  end;
end;

function TAtlasOverviewRuler.TargetAtY(AY: Integer): Integer;
var
  mMark: Integer;
begin
  mMark := MarkAtY(AY);
  if mMark >= 0 then
  begin
    Result := Min(FMarks[mMark].Line, Max(0, FLineCount - 1));
  end
  else
  begin
    Result := LineAtY(AY);
  end;
end;

class function TAtlasOverviewRuler.ColorOf(const AColors: TAtlasColors; AKind: TAtlasOverviewMarkKind): TAtlasColor;
begin
  case AKind of
    TAtlasOverviewMarkKind.Cursor:
      Result := AColors.Text;
    TAtlasOverviewMarkKind.Added:
      Result := AColors.Add;
    TAtlasOverviewMarkKind.Modified:
      Result := AColors.Accent;
    TAtlasOverviewMarkKind.Deleted:
      Result := AColors.ErrorSoft;
    TAtlasOverviewMarkKind.Search:
      Result := AColors.StringLiteral;
    TAtlasOverviewMarkKind.Bookmark:
      Result := AColors.Keyword;
    TAtlasOverviewMarkKind.Breakpoint:
      Result := AColors.Error;
    TAtlasOverviewMarkKind.Info:
      Result := AColors.Muted;
    TAtlasOverviewMarkKind.Warning:
      Result := AColors.Warn;
  else
    Result := AColors.Error;
  end;
end;

class function TAtlasOverviewRuler.RulerWidth(APPI: Integer): Integer;
begin
  Result := MulDiv(cBaseWidth, Max(APPI, cDefaultPpi), cDefaultPpi);
end;

end.
