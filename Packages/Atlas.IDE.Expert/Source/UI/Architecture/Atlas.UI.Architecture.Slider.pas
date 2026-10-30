unit Atlas.UI.Architecture.Slider;

// Regler „Feinheit“ des Fensters „Atlas-Architektur“ (#1366), reine VCL:
// waagrechte Schiene von grob (links, γ 0,2) bis fein (rechts, γ 5,0),
// logarithmisch (TAtlasArchResolution), Marke in der Mitte bei 1,0.
// - Ziehen oder Klicken setzt die Stellung; OnTracking meldet sie laufend
//   (Anzeige des Werts), OnChange erst beim Loslassen (neu rechnen).
// - Doppelklick setzt 1,0 (OnChange).
// - Tasten: Pfeile ±1 Schritt, Bild auf/ab ±10, Pos1/Ende an die Enden;
//   jede Taste gilt sofort (OnChange).
// Farben aus dem IDE-Thema (TAtlasColors), hell und dunkel.

interface

uses
  System.SysUtils,
  System.Classes,
  Winapi.Messages,
  Vcl.Controls,
  Vcl.Graphics;

type
  TAtlasResolutionSlider = class(TCustomControl)
  private
    FPosition: Integer;
    /// <summary>Stellung beim letzten OnChange; Loslassen ohne Änderung meldet nichts.</summary>
    FCommitted: Integer;
    FDragging: Boolean;
    FOnChange: TProc<Double>;
    FOnTracking: TProc<Double>;
    function GetValue: Double;
    procedure SetValue(AValue: Double);
    function TrackLeft: Integer;
    function TrackRight: Integer;
    function PositionAt(AX: Integer): Integer;
    function ThumbX: Integer;
    procedure WMGetDlgCode(var AMessage: TWMGetDlgCode); message WM_GETDLGCODE;
  protected
    procedure Paint; override;
    procedure MouseDown(AButton: TMouseButton; AShift: TShiftState; AX, AY: Integer); override;
    procedure MouseMove(AShift: TShiftState; AX, AY: Integer); override;
    procedure MouseUp(AButton: TMouseButton; AShift: TShiftState; AX, AY: Integer); override;
    procedure DblClick; override;
    procedure KeyDown(var AKey: Word; AShift: TShiftState); override;
    procedure DoEnter; override;
    procedure DoExit; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Stellung setzen (begrenzt); OnTracking, mit ACommit auch OnChange, wenn sie sich seit dem letzten
    /// OnChange geändert hat.</summary>
    procedure MoveTo(APosition: Integer; ACommit: Boolean);
    /// <summary>Wie Doppelklick: 1,0 und OnChange.</summary>
    procedure Reset;
    /// <summary>Stellung 0..TAtlasArchResolution.Steps.</summary>
    property Position: Integer read FPosition;
    /// <summary>Wert der Stellung; Setzen meldet nichts (Wert aus den Einstellungen).</summary>
    property Value: Double read GetValue write SetValue;
    /// <summary>Losgelassen, Doppelklick oder Taste: neuer Wert.</summary>
    property OnChange: TProc<Double> read FOnChange write FOnChange;
    /// <summary>Beim Ziehen: Wert unter der Maus (noch nicht übernommen).</summary>
    property OnTracking: TProc<Double> read FOnTracking write FOnTracking;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Vcl.Themes,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Architecture.Model;

const
  /// <summary>Halbe Breite des Griffs in logischen Pixeln (96 dpi).</summary>
  cThumbRadius = 6;
  /// <summary>Breite der Schiene in logischen Pixeln.</summary>
  cTrackWidth = 3;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

{ TAtlasResolutionSlider }

constructor TAtlasResolutionSlider.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csDoubleClicks, csOpaque];
  TabStop := True;
  Width := 140;
  Height := 22;
  FPosition := TAtlasArchResolution.PositionOf(1);
  FCommitted := FPosition;
end;

function TAtlasResolutionSlider.GetValue: Double;
begin
  Result := TAtlasArchResolution.ValueAt(FPosition);
end;

procedure TAtlasResolutionSlider.SetValue(AValue: Double);
begin
  FPosition := TAtlasArchResolution.PositionOf(AValue);
  FCommitted := FPosition;
  Invalidate;
end;

function TAtlasResolutionSlider.TrackLeft: Integer;
begin
  Result := MulDiv(cThumbRadius + 2, CurrentPPI, 96);
end;

function TAtlasResolutionSlider.TrackRight: Integer;
begin
  Result := Max(TrackLeft + 1, ClientWidth - TrackLeft);
end;

function TAtlasResolutionSlider.PositionAt(AX: Integer): Integer;
begin
  Result := Round((AX - TrackLeft) / (TrackRight - TrackLeft) * TAtlasArchResolution.Steps);
  Result := EnsureRange(Result, 0, TAtlasArchResolution.Steps);
end;

function TAtlasResolutionSlider.ThumbX: Integer;
begin
  Result := TrackLeft + MulDiv(TrackRight - TrackLeft, FPosition, TAtlasArchResolution.Steps);
end;

procedure TAtlasResolutionSlider.MoveTo(APosition: Integer; ACommit: Boolean);
var
  mPosition: Integer;
begin
  mPosition := EnsureRange(APosition, 0, TAtlasArchResolution.Steps);
  if mPosition <> FPosition then
  begin
    FPosition := mPosition;
    Invalidate;
    if Assigned(FOnTracking) then
      FOnTracking(GetValue);
  end;
  if ACommit and (FPosition <> FCommitted) then
  begin
    FCommitted := FPosition;
    if Assigned(FOnChange) then
      FOnChange(GetValue);
  end;
end;

procedure TAtlasResolutionSlider.Reset;
begin
  MoveTo(TAtlasArchResolution.PositionOf(1), True);
end;

procedure TAtlasResolutionSlider.WMGetDlgCode(var AMessage: TWMGetDlgCode);
begin
  inherited;
  AMessage.Result := AMessage.Result or DLGC_WANTARROWS;
end;

procedure TAtlasResolutionSlider.MouseDown(AButton: TMouseButton; AShift: TShiftState; AX, AY: Integer);
begin
  inherited MouseDown(AButton, AShift, AX, AY);
  // Der zweite Druck eines Doppelklicks gehört DblClick.
  if (AButton <> mbLeft) or (ssDouble in AShift) then
    Exit;
  if CanFocus and Showing then
    SetFocus;
  FDragging := True;
  MoveTo(PositionAt(AX), False);
end;

procedure TAtlasResolutionSlider.MouseMove(AShift: TShiftState; AX, AY: Integer);
begin
  inherited MouseMove(AShift, AX, AY);
  if FDragging then
    MoveTo(PositionAt(AX), False);
end;

procedure TAtlasResolutionSlider.MouseUp(AButton: TMouseButton; AShift: TShiftState; AX, AY: Integer);
begin
  inherited MouseUp(AButton, AShift, AX, AY);
  if not FDragging or (AButton <> mbLeft) then
    Exit;
  FDragging := False;
  MoveTo(PositionAt(AX), True);
end;

procedure TAtlasResolutionSlider.DblClick;
begin
  inherited DblClick;
  FDragging := False;
  Reset;
end;

procedure TAtlasResolutionSlider.KeyDown(var AKey: Word; AShift: TShiftState);
begin
  case AKey of
    VK_LEFT, VK_DOWN:
      MoveTo(FPosition - 1, True);
    VK_RIGHT, VK_UP:
      MoveTo(FPosition + 1, True);
    VK_PRIOR:
      MoveTo(FPosition + 10, True);
    VK_NEXT:
      MoveTo(FPosition - 10, True);
    VK_HOME:
      MoveTo(0, True);
    VK_END:
      MoveTo(TAtlasArchResolution.Steps, True);
  else
    begin
      inherited KeyDown(AKey, AShift);
      Exit;
    end;
  end;
  AKey := 0;
end;

procedure TAtlasResolutionSlider.DoEnter;
begin
  inherited DoEnter;
  Invalidate;
end;

procedure TAtlasResolutionSlider.DoExit;
begin
  inherited DoExit;
  Invalidate;
end;

procedure TAtlasResolutionSlider.Paint;
var
  mColors: TAtlasColors;
  mMiddle, mCenter, mRadius, mTick: Integer;
begin
  mColors := TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(StyleServices(Self).GetSystemColor(clBtnFace))));
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(TAtlasColor(ColorToRGB(StyleServices(Self).GetSystemColor(clBtnFace))));
  Canvas.FillRect(ClientRect);
  mMiddle := ClientHeight div 2;
  // Schiene, links bis zum Griff im Akzent.
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := Max(1, MulDiv(cTrackWidth, CurrentPPI, 96));
  Canvas.Pen.Color := ToColor(mColors.Line);
  Canvas.MoveTo(TrackLeft, mMiddle);
  Canvas.LineTo(TrackRight, mMiddle);
  mCenter := ThumbX;
  Canvas.Pen.Color := ToColor(mColors.AccentSoft);
  Canvas.MoveTo(TrackLeft, mMiddle);
  Canvas.LineTo(mCenter, mMiddle);
  // Marke bei 1,0 (Verhalten wie ohne Regler).
  mTick := TrackLeft + MulDiv(TrackRight - TrackLeft, TAtlasArchResolution.PositionOf(1), TAtlasArchResolution.Steps);
  Canvas.Pen.Width := 1;
  Canvas.Pen.Color := ToColor(mColors.Muted);
  Canvas.MoveTo(mTick, mMiddle - MulDiv(5, CurrentPPI, 96));
  Canvas.LineTo(mTick, mMiddle + MulDiv(6, CurrentPPI, 96));
  // Griff; mit Fokus mit Rand in Textfarbe.
  mRadius := MulDiv(cThumbRadius, CurrentPPI, 96);
  Canvas.Brush.Color := ToColor(mColors.Accent);
  if Focused then
  begin
    Canvas.Pen.Width := 2;
    Canvas.Pen.Color := ToColor(mColors.Text);
  end
  else
    Canvas.Pen.Color := ToColor(mColors.Accent);
  Canvas.Ellipse(mCenter - mRadius, mMiddle - mRadius, mCenter + mRadius + 1, mMiddle + mRadius + 1);
end;

end.
