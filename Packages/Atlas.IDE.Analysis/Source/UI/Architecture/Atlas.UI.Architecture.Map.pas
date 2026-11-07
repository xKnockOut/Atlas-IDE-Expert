unit Atlas.UI.Architecture.Map;

// Karte des Fensters „Atlas-Architektur“ (#1118), reine VCL: Teilsysteme als
// Kreise mit Namen, Units als Punkte in der Farbe ihres Teilsystems (Größe
// nach „gesamt abhängig“), uses-Kanten als Linien (implementation
// gestrichelt), Ausreißer mit Ring in Warnfarbe. Lage aus den Daten des
// Servers (TArchitectureLayouter), Farben aus dem IDE-Thema (TAtlasColors) und
// der Palette der HTML-Karte. Was die Karte zeigt, steht in State
// (TAtlasArchitectureMapState, getestet im Kern): Schalter (TAtlasArchMapFlag:
// Namen, implementation-uses, Zyklen markieren, Änderungen zum Stand #1121,
// Fundament-Kanten, Zuordnung #1368), ausgeblendete Teilsysteme, Filter,
// Auswahl und der Weg (Umschalt+Klick: kürzester Weg über uses von der
// gewählten Unit zur angeklickten; ShowRoute: fester Weg aus „Weg zwischen
// Symbolen“ #1117; Esc hebt ihn auf). Die Karte zeichnet nur und setzt
// Maus und Tasten in Aufrufe an State und View um.
// Bedienung sonst: Mausrad zoomt um den Mauszeiger, Ziehen verschiebt, Klick
// wählt eine Unit (OnSelect; ihre Kanten werden hervorgehoben), Doppelklick
// oder Enter öffnet sie (OnOpen), + und − zoomen, 0 passt ein. Namen
// erscheinen erst ab einer lesbaren Größe, zentrale, gewählte, gefilterte und
// die des Wegs immer. Umrechnung und Treffer: TAtlasArchitectureView
// (getestet im Kern).

interface

uses
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Atlas.Core.Architecture.Model,
  Atlas.Core.Architecture.View,
  Atlas.Core.Architecture.MapState;

type
  TAtlasArchitectureMap = class(TCustomControl)
  private type
    /// <summary>Ziehen mit der Maus.</summary>
    TDrag = record
      Dragging: Boolean;
      Moved: Boolean;
      X: Integer;
      Y: Integer;
    end;

    THandlers = record
      OnSelect: TProc<Integer>;
      OnOpen: TProc<Integer>;
    end;
  private
    FState: TAtlasArchitectureMapState;
    FView: TAtlasArchitectureView;
    FFitted: Boolean;
    FDrag: TDrag;
    FHandlers: THandlers;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Neue Daten (TAtlasArchitectureMapState.SetModel) und einpassen.</summary>
    procedure SetModel(const AModel: TAtlasArchitectureModel);
    /// <summary>Alle Teilsysteme einpassen.</summary>
    procedure FitView;
    procedure ZoomBy(AFactor: Double);
    /// <summary>Unit wählen (-1 = keine); ACenter verschiebt die Karte zu ihr.</summary>
    procedure SelectUnit(AUnit: Integer; ACenter: Boolean);
    /// <summary>Daten, Auswahl, Filter, Schalter, ausgeblendete Teilsysteme und Weg; Änderungen zeichnen die
    /// Karte neu.</summary>
    property State: TAtlasArchitectureMapState read FState;
    property View: TAtlasArchitectureView read FView;
    property OnSelect: TProc<Integer> read FHandlers.OnSelect write FHandlers.OnSelect;
    property OnOpen: TProc<Integer> read FHandlers.OnOpen write FHandlers.OnOpen;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Vcl.Themes,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.UI.Architecture.Assignment;

const
  /// <summary>Ab dieser Vergrößerung stehen alle Namen da (darunter überdecken sie sich).</summary>
  cAllNamesScale = 0.9;
  /// <summary>Bildpunkte, ab denen ein Mausdruck als Ziehen gilt.</summary>
  cDragThreshold = 3;
  /// <summary>Anteil der eigenen Farbe bei Units, die hinter einem Weg oder Filter zurücktreten.</summary>
  cDimAlpha = 0.3;

type
  /// <summary>Was die Teile der Zeichnung brauchen.</summary>
  TMapPaint = record
    Canvas: TCanvas;
    State: TAtlasArchitectureMapState;
    View: TAtlasArchitectureView;
    Colors: TAtlasColors;
    /// <summary>ScaleValue(2) und ScaleValue(3) der Karte.</summary>
    Thick: Integer;
    Thicker: Integer;
    Pathing: Boolean;
    Changes: Boolean;
  end;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

function Px(AValue: Double): Integer;
begin
  Result := Round(AValue);
end;

procedure DrawEdge(const APaint: TMapPaint; const AEdge: TAtlasArchEdge);
var
  mSource, mTarget: TAtlasArchUnit;
begin
  mSource := APaint.State.Model.Units[AEdge.Source];
  mTarget := APaint.State.Model.Units[AEdge.Target];
  APaint.Canvas.MoveTo(Px(APaint.View.ScreenX(mSource.X)), Px(APaint.View.ScreenY(mSource.Y)));
  APaint.Canvas.LineTo(Px(APaint.View.ScreenX(mTarget.X)), Px(APaint.View.ScreenY(mTarget.Y)));
end;

/// <summary>Teilsystem AIndex: gestrichelter Kreis in seiner Farbe, Name oben; das Fundament (#1365) deutlicher
/// gestrichelt.</summary>
procedure PaintSubsystem(const APaint: TMapPaint; AIndex, AMinRadius: Integer);
var
  mSubsystem: TAtlasArchSubsystem;
  mX, mY, mRadius: Integer;
  mSize: TSize;
  mCanvas: TCanvas;
begin
  mCanvas := APaint.Canvas;
  mSubsystem := APaint.State.Model.Subsystems[AIndex];
  mX := Px(APaint.View.ScreenX(mSubsystem.X));
  mY := Px(APaint.View.ScreenY(mSubsystem.Y));
  mRadius := Max(AMinRadius, Px(mSubsystem.R * APaint.View.Scale));
  if mSubsystem.Foundation then
  begin
    mCanvas.Pen.Style := psDash;
    mCanvas.Pen.Width := APaint.Thick;
  end
  else
  begin
    mCanvas.Pen.Style := psDot;
    mCanvas.Pen.Width := 1;
  end;
  mCanvas.Pen.Color := TColor(APaint.State.Model.SubsystemColor(AIndex, APaint.Colors.IsDark));
  mCanvas.Brush.Style := bsClear;
  mCanvas.Ellipse(mX - mRadius, mY - mRadius, mX + mRadius + 1, mY + mRadius + 1);
  mSize := mCanvas.TextExtent(mSubsystem.Name);
  mCanvas.Font.Color := TColor(APaint.State.Model.SubsystemColor(AIndex, APaint.Colors.IsDark));
  mCanvas.Font.Style := [fsBold];
  mCanvas.TextOut(mX - mSize.cx div 2, mY - mRadius - mSize.cy - APaint.Thick, mSubsystem.Name);
  mCanvas.Font.Style := [];
end;

/// <summary>Kante wird gezeichnet: beide Units sichtbar, implementation-uses nur mit Schalter.</summary>
function EdgeShown(const APaint: TMapPaint; const AEdge: TAtlasArchEdge): Boolean;
begin
  Result := APaint.State.EdgeVisible(AEdge)
    and (AEdge.Interface_ or APaint.State.Has(TAtlasArchMapFlag.ShowImplementation));
end;

/// <summary>Kante AIndex berührt die gewählte Unit (nicht, solange ein Weg gezeigt wird).</summary>
function TouchesSelected(const APaint: TMapPaint; const AEdge: TAtlasArchEdge): Boolean;
var
  mSelected: Integer;
begin
  mSelected := APaint.State.Selected;
  Result := not APaint.Pathing and (mSelected >= 0) and ((AEdge.Source = mSelected) or (AEdge.Target = mSelected));
end;

/// <summary>Kante AIndex wird hervorgehoben: Zyklus, gewählte Unit oder neu gegenüber dem Stand.</summary>
function Emphasized(const APaint: TMapPaint; AIndex: Integer; const AEdge: TAtlasArchEdge): Boolean;
begin
  Result := APaint.State.MarksCycle(AEdge) or TouchesSelected(APaint, AEdge)
    or (APaint.Changes and APaint.State.IsAdded(AIndex));
end;

/// <summary>Gewöhnliche Kante; Kanten zum Fundament (#1365) blass und gepunktet, abschaltbar.</summary>
procedure PaintPlainEdge(const APaint: TMapPaint; const AEdge: TAtlasArchEdge);
var
  mCanvas: TCanvas;
begin
  mCanvas := APaint.Canvas;
  mCanvas.Pen.Width := 1;
  if APaint.State.Model.TouchesFoundation(AEdge) then
  begin
    if not APaint.State.Has(TAtlasArchMapFlag.ShowFoundationEdges) then
    begin
      Exit;
    end;
    mCanvas.Pen.Style := psDot;
    mCanvas.Pen.Color := ToColor(TAtlasColorMath.Mix(APaint.Colors.Line, APaint.Colors.Surface, 0.4));
  end
  else
  begin
    if AEdge.Interface_ then
    begin
      mCanvas.Pen.Style := psSolid;
    end
    else
    begin
      mCanvas.Pen.Style := psDot;
    end;
    mCanvas.Pen.Color := ToColor(APaint.Colors.Line);
  end;
  DrawEdge(APaint, AEdge);
end;

/// <summary>Hervorgehobene Kante; wie die HTML-Karte: Zyklus vor gewählt vor neu.</summary>
procedure PaintEmphasizedEdge(const APaint: TMapPaint; const AEdge: TAtlasArchEdge);
var
  mCanvas: TCanvas;
begin
  mCanvas := APaint.Canvas;
  mCanvas.Pen.Style := psSolid;
  mCanvas.Pen.Width := APaint.Thick;
  if APaint.State.MarksCycle(AEdge) then
  begin
    mCanvas.Pen.Color := ToColor(APaint.Colors.Error);
  end
  else if TouchesSelected(APaint, AEdge) then
  begin
    mCanvas.Pen.Color := ToColor(APaint.Colors.Accent);
  end
  else
  begin
    mCanvas.Pen.Color := ToColor(APaint.Colors.Add);
  end;
  DrawEdge(APaint, AEdge);
end;

/// <summary>Kanten: zuerst die gewöhnlichen (AEmphasized False), darüber Zyklen, die Kanten der gewählten Unit und
/// neue; Kanten des Wegs zeichnet PaintPath.</summary>
procedure PaintEdges(const APaint: TMapPaint; AEmphasized: Boolean);
var
  mIndex: Integer;
  mEdge: TAtlasArchEdge;
begin
  for mIndex := 0 to High(APaint.State.Model.Edges) do
  begin
    mEdge := APaint.State.Model.Edges[mIndex];
    if not EdgeShown(APaint, mEdge) or (APaint.Pathing and APaint.State.Path.IsEdge(mIndex))
      or (Emphasized(APaint, mIndex, mEdge) <> AEmphasized) then
    begin
      Continue;
    end;
    if AEmphasized then
    begin
      PaintEmphasizedEdge(APaint, mEdge);
    end
    else
    begin
      PaintPlainEdge(APaint, mEdge);
    end;
  end;
end;

/// <summary>Entfernte Kanten gibt es in Edges nicht mehr: rot gestrichelt zwischen den Units, die noch da sind.
/// </summary>
procedure PaintDroppedEdges(const APaint: TMapPaint);
var
  mEdge: TAtlasArchEdge;
begin
  if not APaint.Changes then
  begin
    Exit;
  end;
  for mEdge in APaint.State.Model.Comparison.DroppedEdges do
  begin
    if EdgeShown(APaint, mEdge) then
    begin
      APaint.Canvas.Pen.Style := psDash;
      APaint.Canvas.Pen.Width := 1;
      APaint.Canvas.Pen.Color := ToColor(APaint.Colors.Error);
      DrawEdge(APaint, mEdge);
    end;
  end;
end;

procedure PaintPath(const APaint: TMapPaint; AWidth: Integer);
var
  mIndex: Integer;
  mEdge: TAtlasArchEdge;
begin
  if not APaint.Pathing then
  begin
    Exit;
  end;
  for mIndex in APaint.State.Path.Edges do
  begin
    mEdge := APaint.State.Model.Edges[mIndex];
    if mEdge.Interface_ then
    begin
      APaint.Canvas.Pen.Style := psSolid;
    end
    else
    begin
      APaint.Canvas.Pen.Style := psDash;
    end;
    APaint.Canvas.Pen.Width := AWidth;
    APaint.Canvas.Pen.Color := ToColor(APaint.Colors.Accent);
    DrawEdge(APaint, mEdge);
  end;
end;

/// <summary>Rand der Unit: Ausreißer in Warnfarbe, Zyklus in Fehlerfarbe, gewählte und Enden des Wegs kräftig.
/// </summary>
procedure SetUnitPen(const APaint: TMapPaint; AIndex, AWidest: Integer);
var
  mItem: TAtlasArchUnit;
  mPen: TPen;
begin
  mItem := APaint.State.Model.Units[AIndex];
  mPen := APaint.Canvas.Pen;
  mPen.Width := 1;
  mPen.Color := ToColor(APaint.Colors.Surface);
  if mItem.Outlier then
  begin
    mPen.Width := APaint.Thick;
    mPen.Color := ToColor(APaint.Colors.Warn);
  end;
  if APaint.State.Has(TAtlasArchMapFlag.MarkCycles) and mItem.OnCycle then
  begin
    mPen.Width := APaint.Thick;
    mPen.Color := ToColor(APaint.Colors.Error);
  end;
  if (AIndex = APaint.State.Selected)
    or (APaint.Pathing and ((AIndex = APaint.State.Path.From) or (AIndex = APaint.State.Path.To_))) then
  begin
    mPen.Width := AWidest;
    mPen.Color := ToColor(APaint.Colors.Text);
  end;
end;

procedure PaintUnits(const APaint: TMapPaint; AWidest: Integer);
var
  mIndex, mX, mY, mRadius: Integer;
  mItem: TAtlasArchUnit;
  mFill: TAtlasColor;
begin
  APaint.Canvas.Pen.Style := psSolid;
  for mIndex := 0 to High(APaint.State.Model.Units) do
  begin
    if not APaint.State.UnitVisible(mIndex) then
    begin
      Continue;
    end;
    mItem := APaint.State.Model.Units[mIndex];
    mX := Px(APaint.View.ScreenX(mItem.X));
    mY := Px(APaint.View.ScreenY(mItem.Y));
    mRadius := Max(APaint.Thick, Px(APaint.State.Model.NodeRadius(mIndex) * APaint.View.Scale));
    mFill := TAtlasColor(APaint.State.Model.SubsystemColor(mItem.Subsystem, APaint.Colors.IsDark));
    if not APaint.State.Highlighted(mIndex) then
    begin
      mFill := TAtlasColorMath.Mix(mFill, APaint.Colors.Surface, cDimAlpha);
    end;
    APaint.Canvas.Brush.Style := bsSolid;
    APaint.Canvas.Brush.Color := ToColor(mFill);
    SetUnitPen(APaint, mIndex, AWidest);
    APaint.Canvas.Ellipse(mX - mRadius, mY - mRadius, mX + mRadius + 1, mY + mRadius + 1);
  end;
end;

/// <summary>Namen erscheinen erst ab einer lesbaren Größe; zentrale, gewählte, gefilterte und die des Wegs
/// immer.</summary>
function NameShown(const APaint: TMapPaint; AIndex: Integer; AFiltered: Boolean): Boolean;
var
  mHighlighted, mMajor: Boolean;
begin
  mHighlighted := APaint.State.Highlighted(AIndex);
  mMajor := APaint.State.IsCentral(AIndex) or (AIndex = APaint.State.Selected)
    or ((APaint.Pathing or AFiltered) and mHighlighted);
  Result := mMajor or ((APaint.View.Scale >= cAllNamesScale) and mHighlighted);
end;

procedure PaintNames(const APaint: TMapPaint);
var
  mIndex, mRadius: Integer;
  mItem: TAtlasArchUnit;
  mFiltered: Boolean;
begin
  APaint.Canvas.Brush.Style := bsClear;
  mFiltered := Trim(APaint.State.Filter) <> '';
  for mIndex := 0 to High(APaint.State.Model.Units) do
  begin
    if not APaint.State.UnitVisible(mIndex) or not NameShown(APaint, mIndex, mFiltered) then
    begin
      Continue;
    end;
    mItem := APaint.State.Model.Units[mIndex];
    if APaint.State.Highlighted(mIndex) then
    begin
      APaint.Canvas.Font.Color := ToColor(APaint.Colors.Text);
    end
    else
    begin
      APaint.Canvas.Font.Color := ToColor(APaint.Colors.Muted);
    end;
    mRadius := Max(2, Px(APaint.State.Model.NodeRadius(mIndex) * APaint.View.Scale));
    APaint.Canvas.TextOut(Px(APaint.View.ScreenX(mItem.X)) + mRadius + 3,
      Px(APaint.View.ScreenY(mItem.Y)) - APaint.Canvas.TextHeight('Ag') div 2, mItem.Name);
  end;
end;

/// <summary>Hinweis mit der Zuordnung (#1368) rechts unter der Unit, am Rand der Karte nach innen geklappt.
/// </summary>
procedure PaintHover(const APaint: TMapPaint; const AClient: TRect; APpi: Integer);
var
  mSize: TSize;
  mX, mY, mRadius, mHover: Integer;
  mItem: TAtlasArchUnit;
begin
  mHover := APaint.State.Hover;
  mSize := TAtlasArchitectureAssignment.Measure(APaint.Canvas, APaint.State.Model, mHover, APpi);
  mItem := APaint.State.Model.Units[mHover];
  mRadius := Max(2, Px(APaint.State.Model.NodeRadius(mHover) * APaint.View.Scale));
  mX := Px(APaint.View.ScreenX(mItem.X)) + mRadius + 4;
  mY := Px(APaint.View.ScreenY(mItem.Y)) + mRadius + 4;
  if mX + mSize.cx > AClient.Right then
  begin
    mX := Px(APaint.View.ScreenX(mItem.X)) - mRadius - 4 - mSize.cx;
  end;
  if mY + mSize.cy > AClient.Bottom then
  begin
    mY := Px(APaint.View.ScreenY(mItem.Y)) - mRadius - 4 - mSize.cy;
  end;
  mX := Max(0, mX);
  mY := Max(0, mY);
  TAtlasArchitectureAssignment.Draw(APaint.Canvas, Rect(mX, mY, mX + mSize.cx, mY + mSize.cy),
    APaint.State.Model, mHover, APpi, APaint.Colors);
end;

{ TAtlasArchitectureMap }

/// <summary>Neu zeichnen, wenn sich der Zustand ändert.</summary>
function InvalidateHandler(AMap: TAtlasArchitectureMap): TProc;
begin
  Result :=
    procedure
    begin
      AMap.Invalidate;
    end;
end;

constructor TAtlasArchitectureMap.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  TabStop := True;
  FState := TAtlasArchitectureMapState.Create;
  FState.OnChange := InvalidateHandler(Self);
  FView := Default(TAtlasArchitectureView);
  FView.Scale := 1;
end;

destructor TAtlasArchitectureMap.Destroy;
begin
  FState.Free;
  inherited Destroy;
end;

procedure TAtlasArchitectureMap.SetModel(const AModel: TAtlasArchitectureModel);
begin
  FFitted := False;
  FState.SetModel(AModel);
  if (ClientWidth > 0) and (ClientHeight > 0) then
  begin
    FitView;
  end;
end;

procedure TAtlasArchitectureMap.FitView;
begin
  FView.Fit(FState.Model, ClientWidth, ClientHeight);
  FFitted := Length(FState.Model.Subsystems) > 0;
  Invalidate;
end;

procedure TAtlasArchitectureMap.ZoomBy(AFactor: Double);
begin
  FView.ZoomAt(AFactor, ClientWidth / 2, ClientHeight / 2);
  Invalidate;
end;

procedure TAtlasArchitectureMap.SelectUnit(AUnit: Integer; ACenter: Boolean);
var
  mUnit: Integer;
begin
  FState.SelectUnit(AUnit);
  mUnit := FState.Selected;
  if ACenter and (mUnit >= 0) then
  begin
    FView.Pan(ClientWidth / 2 - FView.ScreenX(FState.Model.Units[mUnit].X),
      ClientHeight / 2 - FView.ScreenY(FState.Model.Units[mUnit].Y));
    Invalidate;
  end;
end;

procedure TAtlasArchitectureMap.Resize;
begin
  inherited Resize;
  if not FFitted and (ClientWidth > 0) and (ClientHeight > 0) then
  begin
    FitView;
  end;
end;

procedure TAtlasArchitectureMap.Paint;
var
  mPaint: TMapPaint;
  mIndex: Integer;
begin
  mPaint.Canvas := Canvas;
  mPaint.State := FState;
  mPaint.View := FView;
  mPaint.Colors := TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(StyleServices(Self).GetSystemColor(clWindow))));
  mPaint.Thick := ScaleValue(2);
  mPaint.Thicker := ScaleValue(3);
  mPaint.Pathing := FState.Path.Shown;
  mPaint.Changes := FState.HasChanges and not mPaint.Pathing;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(mPaint.Colors.Surface);
  Canvas.FillRect(ClientRect);
  Canvas.Font.Assign(Font);
  Canvas.Font.Color := ToColor(mPaint.Colors.Text);
  for mIndex := 0 to High(FState.Model.Subsystems) do
  begin
    if FState.SubsystemVisible[mIndex] then
    begin
      PaintSubsystem(mPaint, mIndex, mPaint.Thick);
    end;
  end;
  PaintEdges(mPaint, False);
  PaintEdges(mPaint, True);
  PaintDroppedEdges(mPaint);
  PaintPath(mPaint, mPaint.Thicker);
  PaintUnits(mPaint, mPaint.Thicker);
  // Namen zuletzt, damit keine Linie sie durchstreicht; darüber der Hinweis (#1368).
  if FState.Has(TAtlasArchMapFlag.ShowNames) then
  begin
    PaintNames(mPaint);
  end;
  if FState.Has(TAtlasArchMapFlag.ShowAssignment) and not FDrag.Dragging
    and TAtlasArchitectureAssignment.Available(FState.Model, FState.Hover) then
  begin
    Canvas.Font.Assign(Font);
    PaintHover(mPaint, ClientRect, CurrentPPI);
  end;
end;

procedure TAtlasArchitectureMap.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  FState.SetHover(-1);
end;

procedure TAtlasArchitectureMap.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if CanFocus then
  begin
    SetFocus;
  end;
  if Button <> mbLeft then
  begin
    Exit;
  end;
  FDrag.Dragging := True;
  FDrag.Moved := False;
  FDrag.X := X;
  FDrag.Y := Y;
end;

procedure TAtlasArchitectureMap.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if not FDrag.Dragging then
  begin
    FState.SetHover(FView.UnitAt(FState.Model, X, Y, FState.Hidden));
    Exit;
  end;
  if not FDrag.Moved and (Abs(X - FDrag.X) <= cDragThreshold) and (Abs(Y - FDrag.Y) <= cDragThreshold) then
  begin
    Exit;
  end;
  FDrag.Moved := True;
  FView.Pan(X - FDrag.X, Y - FDrag.Y);
  FDrag.X := X;
  FDrag.Y := Y;
  Invalidate;
end;

procedure TAtlasArchitectureMap.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mHit: Integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if (Button <> mbLeft) or not FDrag.Dragging then
  begin
    Exit;
  end;
  FDrag.Dragging := False;
  if FDrag.Moved then
  begin
    Exit;
  end;
  mHit := FView.UnitAt(FState.Model, X, Y, FState.Hidden);
  // Umschalt+Klick: Weg von der gewählten Unit hierher (wie die HTML-Karte).
  if (ssShift in Shift) and (FState.Selected >= 0) and (mHit >= 0) and (mHit <> FState.Selected) then
  begin
    FState.ShowPath(FState.Selected, mHit);
    Exit;
  end;
  SelectUnit(mHit, False);
  if Assigned(FHandlers.OnSelect) then
  begin
    FHandlers.OnSelect(mHit);
  end;
end;

procedure TAtlasArchitectureMap.DblClick;
begin
  inherited DblClick;
  if (FState.Selected >= 0) and Assigned(FHandlers.OnOpen) then
  begin
    FHandlers.OnOpen(FState.Selected);
  end;
end;

procedure TAtlasArchitectureMap.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  case Key of
    VK_ADD, VK_OEM_PLUS:
      ZoomBy(1.25);
    VK_SUBTRACT, VK_OEM_MINUS:
      ZoomBy(1 / 1.25);
    Ord('0'), VK_NUMPAD0:
      FitView;
    VK_RETURN:
      if (FState.Selected >= 0) and Assigned(FHandlers.OnOpen) then
      begin
        FHandlers.OnOpen(FState.Selected);
      end;
    VK_ESCAPE:
      if FState.Path.From >= 0 then
      begin
        FState.ClearPath;
      end
      else
      begin
        Exit;
      end;
  else
    Exit;
  end;
  Key := 0;
end;

function TAtlasArchitectureMap.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  mLocal: TPoint;
begin
  Result := True;
  mLocal := ScreenToClient(MousePos);
  if WheelDelta > 0 then
  begin
    FView.ZoomAt(1.15, mLocal.X, mLocal.Y);
  end
  else
  begin
    FView.ZoomAt(1 / 1.15, mLocal.X, mLocal.Y);
  end;
  Invalidate;
end;

end.
