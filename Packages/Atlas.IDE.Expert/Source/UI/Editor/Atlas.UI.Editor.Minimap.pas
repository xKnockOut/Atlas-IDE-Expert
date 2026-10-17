unit Atlas.UI.Editor.Minimap;

// Minimap (#873, experimentell), Darstellung: ein Streifen neben dem Editor
// mit der verkleinerten Datei. Die Rechnung (Zeile ↔ Pixel, Faltung,
// Stauchung, Schieber, Überschriften, Marken) macht Atlas.Core.Editor.Minimap.
// - Der Code liegt in einem Bitmap: Je Zeile die Balken der Wörter (blocks)
//   bzw. winzige Zeichen (characters) in den Farben der Syntaxfärbung aus dem
//   Thema (#411). Neuer Inhalt zeichnet nur die geänderten Zeilen neu, solange
//   Maße, Faltung und Stauchung gleich bleiben.
// - Darüber: die Routine am Cursor leicht hinterlegt, Befunde und Suchtreffer
//   als Zeilenband, Änderungen als Streifen am linken Rand, die
//   Überschriften und der halbtransparente Schieber (immer oder nur beim
//   Überfahren).
// - Ziehen am Schieber meldet die neue oberste Zeile (OnScroll); ein Klick
//   daneben springt (OnJump) oder scrollt nur (OnScroll, Zeile in der Mitte)
//   und zieht danach weiter.

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
  Atlas.Core.Style.Syntax,
  Atlas.Core.Outline.Model,
  Atlas.Core.Editor.Overview,
  Atlas.Core.Editor.Minimap,
  Atlas.UI.Editor.OverviewRuler;

type
  TAtlasMinimapView = class(TCustomControl)
  private
    FOptions: TAtlasMinimapOptions;
    FColors: TAtlasColors;
    FLines: TArray<string>;
    FRuns: TAtlasMinimapLines;
    FTabWidth: Integer;
    FFolds: TAtlasMinimapFolds;
    FNodes: TAtlasOutlineNodes;
    FMarks: TAtlasOverviewMarks;
    FTopLine: Integer;
    FBottomLine: Integer;
    FCursorLine: Integer;
    FMap: TAtlasMinimapMap;
    FMapValid: Boolean;
    FCode: TBitmap;
    FCodeValid: Boolean;
    /// <summary>Maße, zu denen das Bitmap gehört.</summary>
    FCodeWidth: Integer;
    FCodeHeight: Integer;
    FCodeRows: Integer;
    FCodeRowHeight: Integer;
    FCodeFolds: TAtlasMinimapFolds;
    FDirty: TArray<Integer>;
    FHeaders: TAtlasMinimapHeaders;
    FHeadersValid: Boolean;
    FBars: TAtlasOverviewBars;
    FBarsValid: Boolean;
    FHot: Boolean;
    FDragging: Boolean;
    FGrab: Integer;
    FLastScroll: Integer;
    FOnScroll: TProc<Integer>;
    FOnJump: TProc<Integer>;
    function Scale(AValue: Integer): Integer;
    function RowHeight: Integer;
    function LabelHeight: Integer;
    procedure ApplyWidth;
    procedure InvalidateLayout;
    procedure EnsureMap;
    procedure EnsureCode;
    procedure PaintRow(ACanvas: TCanvas; ARow, ATop, AHeight: Integer);
    procedure PaintOverlays;
    procedure Scroll(ATopLine: Integer);
    procedure CMMouseEnter(var Message: TMessage); message CM_MOUSEENTER;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
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
    function Headers: TAtlasMinimapHeaders;
    /// <summary>Farbe eines Tokens aus den Farben des Themas.</summary>
    class function TokenColor(const AColors: TAtlasColors; AKind: TAtlasTokenKind): TAtlasColor; static;
    /// <summary>Breite bei APPI.</summary>
    class function ViewWidth(const AOptions: TAtlasMinimapOptions; APPI: Integer): Integer; static;
    property Options: TAtlasMinimapOptions read FOptions;
    property Dragging: Boolean read FDragging;
    /// <summary>Neue oberste Zeile (0-basiert) beim Ziehen und bei einem Klick ohne Springen.</summary>
    property OnScroll: TProc<Integer> read FOnScroll write FOnScroll;
    /// <summary>Klick springt zur Zeile (0-basiert).</summary>
    property OnJump: TProc<Integer> read FOnJump write FOnJump;
  end;

implementation

uses
  System.Math;

const
  /// <summary>Deckkraft (0–255) von Methodenband, Zeilenband und Schieber.</summary>
  MethodAlpha = 28;
  BandAlpha = 80;
  SliderAlpha = 48;
  /// <summary>Mindesthöhe von Schieber und Marke bei 96 DPI.</summary>
  BaseMinSlider = 6;
  BaseMinMark = 2;
  /// <summary>Breite des Änderungsstreifens links bei 96 DPI.</summary>
  BaseChangeWidth = 3;
  BaseLabelHeight = 11;

/// <summary>ARect mit AColor überziehen, Deckkraft AAlpha.</summary>
procedure Blend(ACanvas: TCanvas; const ARect: TRect; AColor: TAtlasColor; AAlpha: Byte);
var
  Memory: HDC;
  Bitmap, Old: HBITMAP;
  Func: TBlendFunction;
begin
  if (ARect.Right <= ARect.Left) or (ARect.Bottom <= ARect.Top) then
    Exit;
  Memory := CreateCompatibleDC(ACanvas.Handle);
  Bitmap := CreateCompatibleBitmap(ACanvas.Handle, 1, 1);
  Old := SelectObject(Memory, Bitmap);
  try
    SetPixel(Memory, 0, 0, COLORREF(AColor));
    Func.BlendOp := AC_SRC_OVER;
    Func.BlendFlags := 0;
    Func.SourceConstantAlpha := AAlpha;
    Func.AlphaFormat := 0;
    AlphaBlend(ACanvas.Handle, ARect.Left, ARect.Top, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top, Memory, 0,
      0, 1, 1, Func);
  finally
    SelectObject(Memory, Old);
    DeleteObject(Bitmap);
    DeleteDC(Memory);
  end;
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
  FTabWidth := 4;
  FCursorLine := -1;
  FBottomLine := -1;
  FLastScroll := -1;
  FCode := TBitmap.Create;
  FCode.PixelFormat := pf24bit;
  ApplyWidth;
end;

destructor TAtlasMinimapView.Destroy;
begin
  FCode.Free;
  inherited Destroy;
end;

class function TAtlasMinimapView.ViewWidth(const AOptions: TAtlasMinimapOptions; APPI: Integer): Integer;
begin
  Result := MulDiv(TAtlasMinimap.ClampWidth(AOptions.Width), Max(APPI, 96), 96);
end;

class function TAtlasMinimapView.TokenColor(const AColors: TAtlasColors; AKind: TAtlasTokenKind): TAtlasColor;
begin
  case AKind of
    TAtlasTokenKind.Keyword:
      Result := AColors.Keyword;
    TAtlasTokenKind.StringLiteral:
      Result := AColors.StringLiteral;
    TAtlasTokenKind.Comment:
      Result := AColors.Comment;
    TAtlasTokenKind.Number:
      Result := AColors.Accent;
  else
    Result := TAtlasColorMath.Mix(AColors.Text, AColors.Surface, 0.7);
  end;
end;

function TAtlasMinimapView.Scale(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, Max(CurrentPPI, 96), 96);
end;

function TAtlasMinimapView.RowHeight: Integer;
begin
  Result := Max(1, Scale(FOptions.RowHeight));
end;

function TAtlasMinimapView.LabelHeight: Integer;
begin
  Result := Scale(BaseLabelHeight);
end;

procedure TAtlasMinimapView.ApplyWidth;
begin
  Constraints.MinWidth := 0;
  Constraints.MaxWidth := 0;
  Width := ViewWidth(FOptions, CurrentPPI);
  Constraints.MinWidth := Width;
  Constraints.MaxWidth := Width;
end;

procedure TAtlasMinimapView.ChangeScale(M, D: Integer; isDpiChange: Boolean);
begin
  Constraints.MinWidth := 0;
  Constraints.MaxWidth := 0;
  inherited ChangeScale(M, D, isDpiChange);
  ApplyWidth;
  InvalidateLayout;
end;

procedure TAtlasMinimapView.InvalidateLayout;
begin
  FMapValid := False;
  FCodeValid := False;
  FHeadersValid := False;
  FBarsValid := False;
  Invalidate;
end;

procedure TAtlasMinimapView.SetOptions(const AOptions: TAtlasMinimapOptions);
begin
  FOptions := AOptions;
  ApplyWidth;
  InvalidateLayout;
end;

procedure TAtlasMinimapView.SetColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  FCodeValid := False;
  Invalidate;
end;

procedure TAtlasMinimapView.SetContent(const ALines: TArray<string>; const ARuns: TAtlasMinimapLines;
  ATabWidth: Integer);
begin
  if (Length(ARuns) = Length(FRuns)) and (ATabWidth = FTabWidth) then
    FDirty := FDirty + TAtlasMinimap.ChangedLines(FRuns, ARuns)
  else
    FCodeValid := False;
  FLines := ALines;
  FRuns := ARuns;
  FTabWidth := Max(1, ATabWidth);
  if FMap.LineCount <> Length(ARuns) then
  begin
    FMapValid := False;
    FCodeValid := False;
    FHeadersValid := False;
    FBarsValid := False;
  end;
  Invalidate;
end;

procedure TAtlasMinimapView.SetFolds(const AFolds: TAtlasMinimapFolds);
begin
  if TAtlasMinimap.SameFolds(AFolds, FFolds) then
    Exit;
  FFolds := AFolds;
  InvalidateLayout;
end;

procedure TAtlasMinimapView.SetView(ATopLine, ABottomLine, ACursorLine: Integer);
begin
  if (ATopLine = FTopLine) and (ABottomLine = FBottomLine) and (ACursorLine = FCursorLine) then
    Exit;
  FTopLine := ATopLine;
  FBottomLine := ABottomLine;
  FCursorLine := ACursorLine;
  Invalidate;
end;

procedure TAtlasMinimapView.SetOutline(const ANodes: TAtlasOutlineNodes);
begin
  FNodes := ANodes;
  FHeadersValid := False;
  Invalidate;
end;

procedure TAtlasMinimapView.SetMarks(const AMarks: TAtlasOverviewMarks);
begin
  if TAtlasOverview.Same(AMarks, FMarks) then
    Exit;
  FMarks := AMarks;
  FBarsValid := False;
  Invalidate;
end;

procedure TAtlasMinimapView.EnsureMap;
begin
  if FMapValid then
    Exit;
  FMap := TAtlasMinimapMap.Create(Length(FRuns), FFolds, RowHeight, ClientHeight);
  FMapValid := True;
end;

function TAtlasMinimapView.Map: TAtlasMinimapMap;
begin
  EnsureMap;
  Result := FMap;
end;

function TAtlasMinimapView.SliderSpan: TAtlasMinimapSpan;
begin
  EnsureMap;
  Result := FMap.Slider(FTopLine, Max(FTopLine, FBottomLine), Scale(BaseMinSlider));
end;

function TAtlasMinimapView.SliderVisible: Boolean;
begin
  Result := (FOptions.Slider = TAtlasMinimapSlider.Always) or FHot or FDragging;
end;

function TAtlasMinimapView.Headers: TAtlasMinimapHeaders;
begin
  EnsureMap;
  if not FHeadersValid then
  begin
    FHeaders := nil;
    if FOptions.SectionHeaders then
      FHeaders := TAtlasMinimap.Headers(FNodes, FMap, LabelHeight);
    FHeadersValid := True;
  end;
  Result := FHeaders;
end;

procedure TAtlasMinimapView.Resize;
begin
  inherited Resize;
  InvalidateLayout;
end;

procedure TAtlasMinimapView.PaintRow(ACanvas: TCanvas; ARow, ATop, AHeight: Integer);
var
  Line, Index, Column, Left, Right, Height: Integer;
  Run: TAtlasMinimapRun;
  Text: string;
  Color: TAtlasColor;
begin
  Line := FMap.LineOf(ARow);
  if (Line < 0) or (Line > High(FRuns)) then
    Exit;
  if FOptions.Render = TAtlasMinimapRender.Characters then
  begin
    if Line <= High(FLines) then
      Text := TAtlasMinimap.Expand(FLines[Line], FOptions.MaxColumn, FTabWidth)
    else
      Text := '';
    for Run in FRuns[Line] do
    begin
      ACanvas.Brush.Color := TColor(TokenColor(FColors, Run.Kind));
      for Column := Run.Start to Min(Run.Stop, Length(Text)) - 1 do
      begin
        Height := TAtlasMinimap.GlyphHeight(Text[Column + 1], AHeight);
        if Height <= 0 then
          Continue;
        Left := FOptions.ColumnX(Column, ClientWidth);
        Right := Max(Left + 1, FOptions.ColumnX(Column + 1, ClientWidth));
        // Zeichen stehen auf der Grundlinie; eine Lücke trennt Nachbarn.
        if Right - Left > 1 then
          Dec(Right);
        ACanvas.FillRect(TRect.Create(Left, ATop + AHeight - Height, Right, ATop + AHeight));
      end;
    end;
    Exit;
  end;
  // Balken je Wort, eine Spur dünner als die Zeile.
  Height := Max(1, AHeight - AHeight div 3);
  for Index := 0 to High(FRuns[Line]) do
  begin
    Run := FRuns[Line][Index];
    Color := TAtlasColorMath.Mix(TokenColor(FColors, Run.Kind), FColors.Surface, 0.8);
    ACanvas.Brush.Color := TColor(Color);
    Left := FOptions.ColumnX(Run.Start, ClientWidth);
    Right := Max(Left + 1, FOptions.ColumnX(Run.Stop, ClientWidth));
    ACanvas.FillRect(TRect.Create(Left, ATop, Right, ATop + Height));
  end;
end;

procedure TAtlasMinimapView.EnsureCode;
var
  Row, Top, Bottom, Line: Integer;
  Same: Boolean;
begin
  EnsureMap;
  Same := FCodeValid and (FCodeWidth = ClientWidth) and (FCodeHeight = ClientHeight) and
    (FCodeRows = FMap.RowCount) and (FCodeRowHeight = FMap.RowHeight) and TAtlasMinimap.SameFolds(FCodeFolds,
    FMap.Folds);
  if Same and (FDirty = nil) then
    Exit;
  FCode.Canvas.Brush.Style := bsSolid;
  // Gestaucht teilen sich Zeilen ein Pixel: dann immer alles neu.
  if Same and not FMap.Compressed then
  begin
    for Line in FDirty do
    begin
      if (Line < 0) or (Line >= FMap.LineCount) or (FMap.LineOf(FMap.RowOf(Line)) <> Line) then
        Continue;
      Row := FMap.RowOf(Line);
      Top := FMap.PixelOfRow(Row);
      Bottom := FMap.PixelOfRow(Row + 1);
      FCode.Canvas.Brush.Color := TColor(FColors.Surface);
      FCode.Canvas.FillRect(TRect.Create(0, Top, FCode.Width, Bottom));
      PaintRow(FCode.Canvas, Row, Top, Bottom - Top);
    end;
    FDirty := nil;
    Exit;
  end;
  FDirty := nil;
  FCode.SetSize(Max(1, ClientWidth), Max(1, ClientHeight));
  FCode.Canvas.Brush.Color := TColor(FColors.Surface);
  FCode.Canvas.FillRect(TRect.Create(0, 0, FCode.Width, FCode.Height));
  for Row := 0 to FMap.RowCount - 1 do
  begin
    Top := FMap.PixelOfRow(Row);
    Bottom := Max(Top + 1, FMap.PixelOfRow(Row + 1));
    PaintRow(FCode.Canvas, Row, Top, Bottom - Top);
  end;
  FCodeValid := True;
  FCodeWidth := ClientWidth;
  FCodeHeight := ClientHeight;
  FCodeRows := FMap.RowCount;
  FCodeRowHeight := FMap.RowHeight;
  FCodeFolds := FMap.Folds;
end;

procedure TAtlasMinimapView.PaintOverlays;
var
  First, Last, Top, Bottom: Integer;
  Bar: TAtlasOverviewBar;
  Header: TAtlasMinimapHeader;
  Span: TAtlasMinimapSpan;
  Area: TRect;
begin
  // Routine am Cursor.
  if FOptions.HighlightMethod and (FCursorLine >= 0) and TAtlasMinimap.MethodAt(FNodes, FCursorLine, First, Last) then
  begin
    Top := FMap.PixelOfLine(First);
    Bottom := Max(Top + 1, FMap.PixelOfRow(FMap.RowOf(Last) + 1));
    Blend(Canvas, TRect.Create(0, Top, ClientWidth, Bottom), FColors.Accent, MethodAlpha);
  end;
  // Marken: Zeilenband bzw. Streifen am linken Rand.
  if FOptions.Markers then
  begin
    if not FBarsValid then
    begin
      FBars := TAtlasMinimap.MarkerBars(FMarks, FMap, Scale(BaseMinMark));
      FBarsValid := True;
    end;
    for Bar in FBars do
      if Bar.Lane = TAtlasOverviewLane.Left then
      begin
        Canvas.Brush.Color := TColor(TAtlasOverviewRuler.ColorOf(FColors, Bar.Kind));
        Canvas.FillRect(TRect.Create(0, Bar.Top, Scale(BaseChangeWidth), Bar.Bottom));
      end
      else
        Blend(Canvas, TRect.Create(0, Bar.Top, ClientWidth, Bar.Bottom),
          TAtlasOverviewRuler.ColorOf(FColors, Bar.Kind), BandAlpha);
  end;
  // Überschriften.
  if FOptions.SectionHeaders then
  begin
    Canvas.Font.Height := -Scale(8);
    Canvas.Font.Style := [fsBold];
    for Header in Headers do
    begin
      Area := TRect.Create(Scale(BaseChangeWidth) + 1, Header.Top, ClientWidth, Header.Top + LabelHeight);
      Blend(Canvas, TRect.Create(Area.Left, Area.Top, Min(ClientWidth, Area.Left + Canvas.TextWidth(Header.Text) +
        Scale(4)), Area.Bottom), FColors.Surface, 200);
      Canvas.Brush.Style := bsClear;
      if Header.IsType then
        Canvas.Font.Color := TColor(FColors.Keyword)
      else
        Canvas.Font.Color := TColor(FColors.Text);
      Canvas.TextRect(Area, Area.Left + Scale(2), Area.Top, Header.Text);
      Canvas.Brush.Style := bsSolid;
    end;
  end;
  // Schieber.
  if SliderVisible and (FMap.RowCount > 0) then
  begin
    Span := SliderSpan;
    Blend(Canvas, TRect.Create(0, Span.Top, ClientWidth, Span.Bottom), FColors.Text, SliderAlpha);
  end;
end;

procedure TAtlasMinimapView.Paint;
begin
  EnsureCode;
  Canvas.Draw(0, 0, FCode);
  if FCode.Height < ClientHeight then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := TColor(FColors.Surface);
    Canvas.FillRect(TRect.Create(0, FCode.Height, ClientWidth, ClientHeight));
  end;
  PaintOverlays;
end;

procedure TAtlasMinimapView.Scroll(ATopLine: Integer);
begin
  if ATopLine = FLastScroll then
    Exit;
  FLastScroll := ATopLine;
  if Assigned(FOnScroll) then
    FOnScroll(ATopLine);
end;

procedure TAtlasMinimapView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Span: TAtlasMinimapSpan;
begin
  inherited MouseDown(Button, Shift, X, Y);
  EnsureMap;
  if (Button <> mbLeft) or (FMap.RowCount <= 0) then
    Exit;
  Span := SliderSpan;
  FLastScroll := -1;
  if (Y >= Span.Top) and (Y < Span.Bottom) then
    FGrab := Y - Span.Top
  else
  begin
    if FOptions.ClickJumps then
    begin
      if Assigned(FOnJump) then
        FOnJump(FMap.LineAt(Y));
      FLastScroll := FMap.ClickTop(Y, FMap.VisibleRows(FTopLine, FBottomLine));
    end
    else
      Scroll(FMap.ClickTop(Y, FMap.VisibleRows(FTopLine, FBottomLine)));
    // Weiter ziehen: gegriffen in der Mitte des Schiebers.
    FGrab := (Span.Bottom - Span.Top) div 2;
  end;
  FDragging := True;
  Invalidate;
end;

procedure TAtlasMinimapView.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if not FDragging then
    Exit;
  if not (ssLeft in Shift) then
  begin
    FDragging := False;
    Invalidate;
    Exit;
  end;
  EnsureMap;
  Scroll(FMap.DragTop(Y, FGrab, FMap.VisibleRows(FTopLine, FBottomLine)));
end;

procedure TAtlasMinimapView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FDragging := False;
    Invalidate;
  end;
end;

procedure TAtlasMinimapView.CMMouseEnter(var Message: TMessage);
begin
  inherited;
  FHot := True;
  if FOptions.Slider = TAtlasMinimapSlider.MouseOver then
    Invalidate;
end;

procedure TAtlasMinimapView.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  FHot := False;
  if FOptions.Slider = TAtlasMinimapSlider.MouseOver then
    Invalidate;
end;

end.
