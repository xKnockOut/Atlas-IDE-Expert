unit Atlas.UI.Editor.Minimap;

// Minimap (#873, experimentell), Darstellung: ein Streifen neben dem Editor
// mit der verkleinerten Datei. Die Rechnung (Zeile ↔ Pixel, Faltung,
// Stauchung, Schieber, Überschriften, Marken) macht Atlas.Core.Editor.Minimap.
// - Code als Bitmap und die Überlagerung darüber zeichnet
//   Atlas.UI.Editor.MinimapLayers; den Schieber immer oder nur beim
//   Überfahren.
// - Ziehen am Schieber meldet die neue oberste Zeile (OnScroll); ein Klick
//   daneben springt (OnJump) oder scrollt nur (OnScroll, Zeile in der Mitte)
//   und zieht danach weiter.

interface

uses
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Atlas.Core.Style.Palette,
  Atlas.Core.Outline.Model,
  Atlas.Core.Editor.Overview,
  Atlas.Core.Editor.Minimap,
  Atlas.UI.Editor.MinimapLayers;

type
  /// <summary>Maus über dem Streifen: überfahren, Schieber gezogen (gegriffen bei Grab Pixeln), zuletzt gemeldete
  /// oberste Zeile.</summary>
  TAtlasMinimapPointer = record
    Hot: Boolean;
    Dragging: Boolean;
    Grab: Integer;
    LastScroll: Integer;
  end;

  TAtlasMinimapView = class(TCustomControl)
  private
    FOptions: TAtlasMinimapOptions;
    FColors: TAtlasColors;
    FFolds: TAtlasMinimapFolds;
    FViewport: TAtlasMinimapViewport;
    FMap: TAtlasMinimapMap;
    FMapValid: Boolean;
    FCode: TAtlasMinimapCode;
    FOverlays: TAtlasMinimapOverlays;
    FPointer: TAtlasMinimapPointer;
    FOnScroll: TProc<Integer>;
    FOnJump: TProc<Integer>;
    procedure InvalidateLayout;
    procedure Scroll(ATopLine: Integer);
    procedure CMMouseEnter(var Message: TMessage); message CM_MOUSEENTER;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure ChangeScale(M, D: Integer; isDpiChange: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetOptions(const AOptions: TAtlasMinimapOptions);
    procedure SetColors(const AColors: TAtlasColors);
    /// <summary>Text (für „characters“) und Balken der Zeilen; ATabWidth klappt Tabulatoren aus.</summary>
    procedure SetContent(const ALines: TArray<string>; const ARuns: TAtlasMinimapLines; ATabWidth: Integer);
    procedure SetFolds(const AFolds: TAtlasMinimapFolds);
    /// <summary>Sichtbar sind ATopLine bis ABottomLine (0-basiert), der Cursor steht in ACursorLine.</summary>
    procedure SetView(ATopLine, ABottomLine, ACursorLine: Integer);
    procedure SetOutline(const ANodes: TAtlasOutlineNodes);
    procedure SetMarks(const AMarks: TAtlasOverviewMarks);
    /// <summary>Umrechnung für die aktuellen Maße.</summary>
    function Map: TAtlasMinimapMap;
    /// <summary>Schieber in Client-Pixeln.</summary>
    function SliderSpan: TAtlasMinimapSpan;
    /// <summary>Schieber wird gezeichnet (immer oder beim Überfahren und Ziehen).</summary>
    function SliderVisible: Boolean;
    /// <summary>Breite bei APPI.</summary>
    class function ViewWidth(const AOptions: TAtlasMinimapOptions; APPI: Integer): Integer; static;
    property Options: TAtlasMinimapOptions read FOptions;
    property SliderDragging: Boolean read FPointer.Dragging;
    /// <summary>Neue oberste Zeile (0-basiert) beim Ziehen und bei einem Klick ohne Springen.</summary>
    property OnScroll: TProc<Integer> read FOnScroll write FOnScroll;
    /// <summary>Klick springt zur Zeile (0-basiert).</summary>
    property OnJump: TProc<Integer> read FOnJump write FOnJump;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Vcl.Graphics;

const
  /// <summary>Mindesthöhe des Schiebers bei 96 DPI.</summary>
  cBaseMinSlider = 6;

/// <summary>Feste Breite nach den Optionen bei der aktuellen DPI.</summary>
procedure ApplyWidth(AView: TAtlasMinimapView);
begin
  AView.Constraints.MinWidth := 0;
  AView.Constraints.MaxWidth := 0;
  AView.Width := TAtlasMinimapView.ViewWidth(AView.Options, AView.CurrentPPI);
  AView.Constraints.MinWidth := AView.Width;
  AView.Constraints.MaxWidth := AView.Width;
end;

{ TAtlasMinimapView }

constructor TAtlasMinimapView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque] - [csSetCaption];
  DoubleBuffered := True;
  TabStop := False;
  FOptions := TAtlasMinimap.Defaults;
  FColors := TAtlasColors.Light;
  FViewport.Cursor := -1;
  FViewport.Bottom := -1;
  FPointer.LastScroll := -1;
  FCode := TAtlasMinimapCode.Create;
  FOverlays := TAtlasMinimapOverlays.Create;
  ApplyWidth(Self);
end;

destructor TAtlasMinimapView.Destroy;
begin
  FOverlays.Free;
  FCode.Free;
  inherited Destroy;
end;

class function TAtlasMinimapView.ViewWidth(const AOptions: TAtlasMinimapOptions; APPI: Integer): Integer;
begin
  Result := MulDiv(TAtlasMinimap.ClampWidth(AOptions.Width), Max(APPI, 96), 96);
end;

procedure TAtlasMinimapView.ChangeScale(M, D: Integer; isDpiChange: Boolean);
begin
  Constraints.MinWidth := 0;
  Constraints.MaxWidth := 0;
  inherited ChangeScale(M, D, isDpiChange);
  ApplyWidth(Self);
  InvalidateLayout;
end;

procedure TAtlasMinimapView.InvalidateLayout;
begin
  FMapValid := False;
  FCode.Invalidate;
  FOverlays.Invalidate;
  Invalidate;
end;

procedure TAtlasMinimapView.SetOptions(const AOptions: TAtlasMinimapOptions);
begin
  FOptions := AOptions;
  ApplyWidth(Self);
  InvalidateLayout;
end;

procedure TAtlasMinimapView.SetColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  FCode.Invalidate;
  Invalidate;
end;

procedure TAtlasMinimapView.SetContent(const ALines: TArray<string>; const ARuns: TAtlasMinimapLines;
  ATabWidth: Integer);
begin
  FCode.SetContent(ALines, ARuns, ATabWidth);
  if FMap.LineCount <> Length(ARuns) then
  begin
    FMapValid := False;
    FCode.Invalidate;
    FOverlays.Invalidate;
  end;
  Invalidate;
end;

procedure TAtlasMinimapView.SetFolds(const AFolds: TAtlasMinimapFolds);
begin
  if TAtlasMinimap.SameFolds(AFolds, FFolds) then
  begin
    Exit;
  end;
  FFolds := AFolds;
  InvalidateLayout;
end;

procedure TAtlasMinimapView.SetView(ATopLine, ABottomLine, ACursorLine: Integer);
begin
  if (ATopLine = FViewport.Top) and (ABottomLine = FViewport.Bottom) and (ACursorLine = FViewport.Cursor) then
  begin
    Exit;
  end;
  FViewport.Top := ATopLine;
  FViewport.Bottom := ABottomLine;
  FViewport.Cursor := ACursorLine;
  // Mitscrollen: Ändert sich der Offset, liegen Überschriften und Marken an anderer Stelle.
  if FMapValid and FMap.Follow(FViewport.Top, Max(FViewport.Top, FViewport.Bottom)) then
  begin
    FOverlays.Invalidate;
  end;
  Invalidate;
end;

procedure TAtlasMinimapView.SetOutline(const ANodes: TAtlasOutlineNodes);
begin
  FOverlays.SetNodes(ANodes);
  Invalidate;
end;

procedure TAtlasMinimapView.SetMarks(const AMarks: TAtlasOverviewMarks);
begin
  if FOverlays.SetMarks(AMarks) then
  begin
    Invalidate;
  end;
end;

function TAtlasMinimapView.Map: TAtlasMinimapMap;
begin
  if not FMapValid then
  begin
    FMap := TAtlasMinimapMap.Create(FCode.LineCount, FFolds,
      Max(1, TAtlasMinimapOverlays.Scaled(FOptions.RowHeight, CurrentPPI)), ClientHeight);
    // Passt der Inhalt nicht, scrollt die Minimap mit der Lage im Editor mit (wie VS Code) statt zu stauchen.
    FMap.Follow(FViewport.Top, Max(FViewport.Top, FViewport.Bottom));
    FMapValid := True;
  end;
  Result := FMap;
end;

function TAtlasMinimapView.SliderSpan: TAtlasMinimapSpan;
begin
  Result := Map.Slider(FViewport.Top, Max(FViewport.Top, FViewport.Bottom),
    TAtlasMinimapOverlays.Scaled(cBaseMinSlider, CurrentPPI));
end;

function TAtlasMinimapView.SliderVisible: Boolean;
begin
  Result := (FOptions.Slider = TAtlasMinimapSlider.Always) or FPointer.Hot or FPointer.Dragging;
end;

procedure TAtlasMinimapView.Resize;
begin
  inherited Resize;
  InvalidateLayout;
end;

procedure TAtlasMinimapView.Paint;
var
  mFrame: TAtlasMinimapFrame;
begin
  FCode.Ensure(Map, FOptions, FColors, ClientWidth, ClientHeight);
  Canvas.Draw(0, 0, FCode.Bitmap);
  if FCode.Bitmap.Height < ClientHeight then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := TColor(FColors.Surface);
    Canvas.FillRect(TRect.Create(0, FCode.Bitmap.Height, ClientWidth, ClientHeight));
  end;
  mFrame.Options := FOptions;
  mFrame.Colors := FColors;
  mFrame.PPI := CurrentPPI;
  mFrame.Width := ClientWidth;
  mFrame.Viewport := FViewport;
  mFrame.SliderVisible := SliderVisible;
  mFrame.Slider := SliderSpan;
  FOverlays.Paint(Canvas, FMap, mFrame);
end;

procedure TAtlasMinimapView.Scroll(ATopLine: Integer);
begin
  if ATopLine = FPointer.LastScroll then
  begin
    Exit;
  end;
  FPointer.LastScroll := ATopLine;
  if Assigned(FOnScroll) then
  begin
    FOnScroll(ATopLine);
  end;
end;

function TAtlasMinimapView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  mLines, mTop: Integer;
begin
  // Mausrad über der Minimap scrollt den Editor wie über dem Text: Zeilen je Raste aus Windows (Vorgabe 3).
  mLines := Max(1, Mouse.WheelScrollLines);
  mTop := Max(0, FViewport.Top - (WheelDelta * mLines) div WHEEL_DELTA);
  Result := True;
  if (mTop = FViewport.Top) or not Assigned(FOnScroll) then
  begin
    Exit;
  end;
  FPointer.LastScroll := mTop;
  FOnScroll(mTop);
end;

procedure TAtlasMinimapView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mSpan: TAtlasMinimapSpan;
  mTop: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if (Button <> mbLeft) or (Map.RowCount <= 0) then
  begin
    Exit;
  end;
  mSpan := SliderSpan;
  FPointer.LastScroll := -1;
  // Neben dem Schieber: springen oder scrollen, dann weiter ziehen, gegriffen in der Mitte des Schiebers.
  FPointer.Grab := (mSpan.Bottom - mSpan.Top) div 2;
  if (Y >= mSpan.Top) and (Y < mSpan.Bottom) then
  begin
    FPointer.Grab := Y - mSpan.Top;
  end
  else if FOptions.ClickJumps then
  begin
    if Assigned(FOnJump) then
    begin
      FOnJump(FMap.LineAt(Y));
    end;
    FPointer.LastScroll := FMap.ClickTop(Y, FMap.VisibleRows(FViewport.Top, FViewport.Bottom));
  end
  else
  begin
    mTop := FMap.ClickTop(Y, FMap.VisibleRows(FViewport.Top, FViewport.Bottom));
    Scroll(mTop);
  end;
  FPointer.Dragging := True;
  Invalidate;
end;

procedure TAtlasMinimapView.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if not FPointer.Dragging then
  begin
    Exit;
  end;
  if not (ssLeft in Shift) then
  begin
    FPointer.Dragging := False;
    Invalidate;
    Exit;
  end;
  Scroll(Map.DragTop(Y, FPointer.Grab, FMap.VisibleRows(FViewport.Top, FViewport.Bottom)));
end;

procedure TAtlasMinimapView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FPointer.Dragging := False;
    Invalidate;
  end;
end;

procedure TAtlasMinimapView.CMMouseEnter(var Message: TMessage);
begin
  inherited;
  FPointer.Hot := True;
  if FOptions.Slider = TAtlasMinimapSlider.MouseOver then
  begin
    Invalidate;
  end;
end;

procedure TAtlasMinimapView.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  FPointer.Hot := False;
  if FOptions.Slider = TAtlasMinimapSlider.MouseOver then
  begin
    Invalidate;
  end;
end;

end.
