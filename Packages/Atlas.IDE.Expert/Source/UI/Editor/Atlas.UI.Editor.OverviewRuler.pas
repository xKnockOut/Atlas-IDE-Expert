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
  BaseWidth = 14;
  /// <summary>Mindesthöhe einer Marke und Spiel beim Klick bei 96 DPI.</summary>
  BaseMinHeight = 3;
  BaseTolerance = 3;

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
  Width := RulerWidth(96);
  Constraints.MinWidth := Width;
  Constraints.MaxWidth := Width;
end;

class function TAtlasOverviewRuler.RulerWidth(APPI: Integer): Integer;
begin
  Result := MulDiv(BaseWidth, Max(APPI, 96), 96);
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
  Result := MulDiv(AValue, Max(CurrentPPI, 96), 96);
end;

procedure TAtlasOverviewRuler.SetMarks(const AMarks: TAtlasOverviewMarks; ALineCount, AFirstVisible,
  ALastVisible: Integer);
begin
  if TAtlasOverview.Same(AMarks, FMarks) and (ALineCount = FLineCount) and (AFirstVisible = FFirstVisible) and
    (ALastVisible = FLastVisible) then
    Exit;
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

procedure TAtlasOverviewRuler.Layout;
begin
  if FLaidOut then
    Exit;
  FBars := TAtlasOverview.Layout(FMarks, FLineCount, ClientHeight, Scale(BaseMinHeight));
  FLaidOut := True;
end;

procedure TAtlasOverviewRuler.Resize;
begin
  inherited Resize;
  FLaidOut := False;
  Invalidate;
end;

function TAtlasOverviewRuler.LineAtY(AY: Integer): Integer;
begin
  Result := TAtlasOverview.LineAt(AY, FLineCount, ClientHeight);
end;

function TAtlasOverviewRuler.MarkAtY(AY: Integer): Integer;
begin
  Layout;
  if not TAtlasOverview.Hit(FBars, AY, Scale(BaseTolerance), Result) then
    Result := -1;
end;

function TAtlasOverviewRuler.TargetAtY(AY: Integer): Integer;
var
  Mark: Integer;
begin
  Mark := MarkAtY(AY);
  if Mark >= 0 then
    Result := Min(FMarks[Mark].Line, Max(0, FLineCount - 1))
  else
    Result := LineAtY(AY);
end;

procedure TAtlasOverviewRuler.Paint;
var
  Bar: TAtlasOverviewBar;
  Inner, Lane, mLeft, Right, mTop, Bottom: Integer;
  Area: TRect;
begin
  Layout;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := TColor(TAtlasColorMath.Mix(FColors.Gutter, FColors.Surface, 0.5));
  Canvas.FillRect(ClientRect);
  if FLineCount <= 0 then
    Exit;
  // Sichtbarer Bereich.
  if FLastVisible >= FFirstVisible then
  begin
    mTop := TAtlasOverview.PixelOf(FFirstVisible, FLineCount, ClientHeight);
    Bottom := Max(mTop + Scale(4), TAtlasOverview.PixelOf(FLastVisible + 1, FLineCount, ClientHeight));
    Canvas.Brush.Color := TColor(TAtlasColorMath.Mix(FColors.Text, FColors.Surface, 0.1));
    Canvas.FillRect(TRect.Create(0, mTop, ClientWidth, Min(Bottom, ClientHeight)));
  end;
  Inner := Max(Scale(3), (ClientWidth - Scale(2)) div 3);
  for Bar in FBars do
  begin
    Lane := Scale(1);
    case Bar.Lane of
      TAtlasOverviewLane.Left:
        begin
          mLeft := Lane;
          Right := mLeft + Inner;
        end;
      TAtlasOverviewLane.Middle:
        begin
          mLeft := Lane + Inner;
          Right := mLeft + Inner;
        end;
      TAtlasOverviewLane.Right:
        begin
          mLeft := Lane + 2 * Inner;
          Right := ClientWidth - Lane;
        end;
    else
      begin
        mLeft := 0;
        Right := ClientWidth;
      end;
    end;
    Area := TRect.Create(mLeft, Bar.Top, Right, Bar.Bottom);
    // Der Cursor ist eine dünne Linie über die ganze Breite.
    if Bar.Kind = TAtlasOverviewMarkKind.Cursor then
      Area.Bottom := Min(Area.Bottom, Area.Top + Scale(2));
    Canvas.Brush.Color := TColor(ColorOf(FColors, Bar.Kind));
    Canvas.FillRect(Area);
  end;
end;

procedure TAtlasOverviewRuler.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if (Button <> mbLeft) or (FLineCount <= 0) then
    Exit;
  if Assigned(FOnHoverEnd) then
    FOnHoverEnd;
  FHoverLine := -1;
  if Assigned(FOnJump) then
    FOnJump(TargetAtY(Y));
end;

procedure TAtlasOverviewRuler.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Mark, Line: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  if FLineCount <= 0 then
    Exit;
  Mark := MarkAtY(Y);
  Line := TargetAtY(Y);
  if (Line = FHoverLine) and (Mark = FHoverMark) then
    Exit;
  FHoverLine := Line;
  FHoverMark := Mark;
  if Assigned(FOnHover) then
    FOnHover(Line, Mark, ClientToScreen(Point(X, Y)));
end;

procedure TAtlasOverviewRuler.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  FHoverLine := -1;
  FHoverMark := -1;
  if Assigned(FOnHoverEnd) then
    FOnHoverEnd;
end;

end.
