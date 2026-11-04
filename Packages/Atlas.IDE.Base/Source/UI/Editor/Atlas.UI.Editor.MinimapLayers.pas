unit Atlas.UI.Editor.MinimapLayers;

// Ebenen der Minimap (#873), gezeichnet für TAtlasMinimapView:
// - TAtlasMinimapCode: der Code als Bitmap. Je Zeile die Balken der Wörter
//   (blocks) bzw. winzige Zeichen (characters) in den Farben der
//   Syntaxfärbung aus dem Thema (#411). Neuer Inhalt zeichnet nur die
//   geänderten Zeilen neu, solange Maße, Faltung und Stauchung gleich bleiben.
// - TAtlasMinimapOverlays: darüber die Routine am Cursor leicht hinterlegt,
//   Befunde und Suchtreffer als Zeilenband, Änderungen als Streifen am linken
//   Rand, die Überschriften und der halbtransparente Schieber.

interface

uses
  System.Types,
  Vcl.Graphics,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Style.Syntax,
  Atlas.Core.Outline.Model,
  Atlas.Core.Editor.Overview,
  Atlas.Core.Editor.Minimap;

type
  /// <summary>Sichtbare Zeilen und Cursorzeile im Editor (0-basiert).</summary>
  TAtlasMinimapViewport = record
    Top: Integer;
    Bottom: Integer;
    Cursor: Integer;
  end;

  /// <summary>Was die Überlagerung vom Streifen braucht.</summary>
  TAtlasMinimapFrame = record
    Options: TAtlasMinimapOptions;
    Colors: TAtlasColors;
    PPI: Integer;
    Width: Integer;
    Viewport: TAtlasMinimapViewport;
    SliderVisible: Boolean;
    Slider: TAtlasMinimapSpan;
  end;

  TAtlasMinimapCode = class
  private
    FBitmap: TBitmap;
    FLines: TArray<string>;
    FRuns: TAtlasMinimapLines;
    FTabWidth: Integer;
    FDirty: TArray<Integer>;
    FOptions: TAtlasMinimapOptions;
    FColors: TAtlasColors;
    FValid: Boolean;
    // Maße, Faltung und Offset der Abbildung (Mitscrollen), zu denen das Bitmap gehört.
    FWidth: Integer;
    FHeight: Integer;
    FRows: Integer;
    FRowHeight: Integer;
    FFolds: TAtlasMinimapFolds;
    FOffset: Integer;
    function Matches(const AMap: TAtlasMinimapMap; AWidth, AHeight: Integer): Boolean;
    procedure RepaintDirty(const AMap: TAtlasMinimapMap);
    procedure RepaintAll(const AMap: TAtlasMinimapMap; AWidth, AHeight: Integer);
    procedure PaintRow(const AMap: TAtlasMinimapMap; ARow, ATop, AHeight: Integer);
    procedure PaintCharacters(ALine, ATop, AHeight: Integer);
    procedure PaintBlocks(ALine, ATop, AHeight: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Farbe eines Tokens aus den Farben des Themas.</summary>
    class function TokenColor(const AColors: TAtlasColors; AKind: TAtlasTokenKind): TAtlasColor; static;
    /// <summary>Text (für „characters“) und Balken der Zeilen; ATabWidth klappt Tabulatoren aus.</summary>
    procedure SetContent(const ALines: TArray<string>; const ARuns: TAtlasMinimapLines; ATabWidth: Integer);
    /// <summary>Beim nächsten Ensure alles neu zeichnen.</summary>
    procedure Invalidate;
    /// <summary>Bitmap für AMap in AWidth × AHeight auf den Stand bringen.</summary>
    procedure Ensure(const AMap: TAtlasMinimapMap; const AOptions: TAtlasMinimapOptions;
      const AColors: TAtlasColors; AWidth, AHeight: Integer);
    function LineCount: Integer;
    property TabWidth: Integer read FTabWidth;
    property Bitmap: TBitmap read FBitmap;
  end;

  TAtlasMinimapOverlays = class
  private
    FNodes: TAtlasOutlineNodes;
    FMarks: TAtlasOverviewMarks;
    FHeaders: TAtlasMinimapHeaders;
    FHeadersValid: Boolean;
    FBars: TAtlasOverviewBars;
    FBarsValid: Boolean;
    procedure PaintMethod(ACanvas: TCanvas; const AMap: TAtlasMinimapMap; const AFrame: TAtlasMinimapFrame);
    procedure PaintMarkers(ACanvas: TCanvas; const AMap: TAtlasMinimapMap; const AFrame: TAtlasMinimapFrame);
    procedure PaintHeaders(ACanvas: TCanvas; const AMap: TAtlasMinimapMap; const AFrame: TAtlasMinimapFrame);
  public
    /// <summary>AValue (bei 96 DPI) für APPI.</summary>
    class function Scaled(AValue, APPI: Integer): Integer; static;
    /// <summary>Gliederung: Überschriften und Routine am Cursor.</summary>
    procedure SetNodes(const ANodes: TAtlasOutlineNodes);
    /// <summary>Neue Marken; False, wenn sie gleich sind.</summary>
    function SetMarks(const AMarks: TAtlasOverviewMarks): Boolean;
    /// <summary>Überschriften und Marken liegen an anderer Stelle (Maße, Faltung, Mitscrollen).</summary>
    procedure Invalidate;
    procedure Paint(ACanvas: TCanvas; const AMap: TAtlasMinimapMap; const AFrame: TAtlasMinimapFrame);
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Atlas.UI.Editor.OverviewRuler;

const
  /// <summary>Deckkraft (0–255) von Methodenband, Zeilenband und Schieber.</summary>
  MethodAlpha = 28;
  /// <summary>Breite des Akzentstrichs der Routine am Cursor (96 DPI).</summary>
  MethodBarWidth = 2;
  BandAlpha = 80;
  // Nur ein Schatten: Bei 48 überdeckte der Schieber im dunklen Thema die Zeichen darunter.
  SliderAlpha = 20;
  /// <summary>Mindesthöhe einer Marke bei 96 DPI.</summary>
  BaseMinMark = 2;
  /// <summary>Breite des Änderungsstreifens links bei 96 DPI.</summary>
  BaseChangeWidth = 3;
  BaseLabelHeight = 11;

/// <summary>ARect mit AColor überziehen, Deckkraft AAlpha.</summary>
procedure Blend(ACanvas: TCanvas; const ARect: TRect; AColor: TAtlasColor; AAlpha: Byte);
var
  mMemory: HDC;
  mBitmap, mOld: HBITMAP;
  mFunc: TBlendFunction;
begin
  if (ARect.Right <= ARect.Left) or (ARect.Bottom <= ARect.Top) then
  begin
    Exit;
  end;
  mMemory := CreateCompatibleDC(ACanvas.Handle);
  mBitmap := CreateCompatibleBitmap(ACanvas.Handle, 1, 1);
  mOld := SelectObject(mMemory, mBitmap);
  try
    SetPixel(mMemory, 0, 0, COLORREF(AColor));
    mFunc.BlendOp := AC_SRC_OVER;
    mFunc.BlendFlags := 0;
    mFunc.SourceConstantAlpha := AAlpha;
    mFunc.AlphaFormat := 0;
    AlphaBlend(ACanvas.Handle, ARect.Left, ARect.Top, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top, mMemory, 0,
      0, 1, 1, mFunc);
  finally
    SelectObject(mMemory, mOld);
    DeleteObject(mBitmap);
    DeleteDC(mMemory);
  end;
end;

{ TAtlasMinimapCode }

constructor TAtlasMinimapCode.Create;
begin
  inherited Create;
  FTabWidth := 4;
  FBitmap := TBitmap.Create;
  FBitmap.PixelFormat := pf24bit;
end;

destructor TAtlasMinimapCode.Destroy;
begin
  FBitmap.Free;
  inherited Destroy;
end;

class function TAtlasMinimapCode.TokenColor(const AColors: TAtlasColors; AKind: TAtlasTokenKind): TAtlasColor;
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
    // Kräftig wie in VS Code: Bezeichner sind der Großteil des Codes und müssen auf einen Blick lesbar sein.
    Result := TAtlasColorMath.Mix(AColors.Text, AColors.Surface, 0.85);
  end;
end;

procedure TAtlasMinimapCode.SetContent(const ALines: TArray<string>; const ARuns: TAtlasMinimapLines;
  ATabWidth: Integer);
begin
  if (Length(ARuns) = Length(FRuns)) and (ATabWidth = FTabWidth) then
  begin
    FDirty := FDirty + TAtlasMinimap.ChangedLines(FRuns, ARuns);
  end
  else
  begin
    FValid := False;
  end;
  FLines := ALines;
  FRuns := ARuns;
  FTabWidth := Max(1, ATabWidth);
end;

procedure TAtlasMinimapCode.Invalidate;
begin
  FValid := False;
end;

function TAtlasMinimapCode.LineCount: Integer;
begin
  Result := Length(FRuns);
end;

function TAtlasMinimapCode.Matches(const AMap: TAtlasMinimapMap; AWidth, AHeight: Integer): Boolean;
begin
  Result := (FWidth = AWidth) and (FHeight = AHeight) and (FRows = AMap.RowCount) and
    (FRowHeight = AMap.RowHeight);
  Result := Result and (FOffset = AMap.Offset) and TAtlasMinimap.SameFolds(FFolds, AMap.Folds);
end;

procedure TAtlasMinimapCode.Ensure(const AMap: TAtlasMinimapMap; const AOptions: TAtlasMinimapOptions;
  const AColors: TAtlasColors; AWidth, AHeight: Integer);
var
  mSame: Boolean;
begin
  FOptions := AOptions;
  FColors := AColors;
  mSame := FValid and Matches(AMap, AWidth, AHeight);
  if mSame and (FDirty = nil) then
  begin
    Exit;
  end;
  FBitmap.Canvas.Brush.Style := bsSolid;
  // Gestaucht teilen sich Zeilen ein Pixel: dann immer alles neu.
  if mSame and not AMap.Compressed then
  begin
    RepaintDirty(AMap);
  end
  else
  begin
    RepaintAll(AMap, AWidth, AHeight);
  end;
  FDirty := nil;
end;

procedure TAtlasMinimapCode.RepaintDirty(const AMap: TAtlasMinimapMap);
var
  mLine, mRow, mTop, mBottom: Integer;
begin
  for mLine in FDirty do
  begin
    if (mLine < 0) or (mLine >= AMap.LineCount) or (AMap.LineOf(AMap.RowOf(mLine)) <> mLine) then
    begin
      Continue;
    end;
    mRow := AMap.RowOf(mLine);
    mTop := AMap.PixelOfRow(mRow);
    mBottom := AMap.PixelOfRow(mRow + 1);
    FBitmap.Canvas.Brush.Color := TColor(FColors.Surface);
    FBitmap.Canvas.FillRect(TRect.Create(0, mTop, FBitmap.Width, mBottom));
    PaintRow(AMap, mRow, mTop, mBottom - mTop);
  end;
end;

procedure TAtlasMinimapCode.RepaintAll(const AMap: TAtlasMinimapMap; AWidth, AHeight: Integer);
var
  mRow, mTop, mBottom: Integer;
begin
  FWidth := AWidth;
  FHeight := AHeight;
  FBitmap.SetSize(Max(1, AWidth), Max(1, AHeight));
  FBitmap.Canvas.Brush.Color := TColor(FColors.Surface);
  FBitmap.Canvas.FillRect(TRect.Create(0, 0, FBitmap.Width, FBitmap.Height));
  // Nur die sichtbaren Zeilen: Beim Mitscrollen liegt der Rest außerhalb.
  for mRow := AMap.RowAt(0) to Min(AMap.RowCount - 1, AMap.RowAt(Max(0, AHeight - 1)) + 1) do
  begin
    mTop := AMap.PixelOfRow(mRow);
    mBottom := Max(mTop + 1, AMap.PixelOfRow(mRow + 1));
    PaintRow(AMap, mRow, mTop, mBottom - mTop);
  end;
  FValid := True;
  FOffset := AMap.Offset;
  FRows := AMap.RowCount;
  FRowHeight := AMap.RowHeight;
  FFolds := AMap.Folds;
end;

procedure TAtlasMinimapCode.PaintRow(const AMap: TAtlasMinimapMap; ARow, ATop, AHeight: Integer);
var
  mLine: Integer;
begin
  mLine := AMap.LineOf(ARow);
  if (mLine < 0) or (mLine > High(FRuns)) then
  begin
    Exit;
  end;
  if FOptions.Render = TAtlasMinimapRender.Characters then
  begin
    PaintCharacters(mLine, ATop, AHeight);
  end
  else
  begin
    PaintBlocks(mLine, ATop, AHeight);
  end;
end;

procedure TAtlasMinimapCode.PaintCharacters(ALine, ATop, AHeight: Integer);
var
  mText: string;
  mRun: TAtlasMinimapRun;
  mColumn, mHeight, mLeft, mRight: Integer;
begin
  mText := '';
  if ALine <= High(FLines) then
  begin
    mText := TAtlasMinimap.Expand(FLines[ALine], FOptions.MaxColumn, FTabWidth);
  end;
  for mRun in FRuns[ALine] do
  begin
    FBitmap.Canvas.Brush.Color := TColor(TokenColor(FColors, mRun.Kind));
    for mColumn := mRun.Start to Min(mRun.Stop, Length(mText)) - 1 do
    begin
      mHeight := TAtlasMinimap.GlyphHeight(mText[mColumn + 1], AHeight);
      if mHeight > 0 then
      begin
        mLeft := FOptions.ColumnX(mColumn, FWidth);
        mRight := Max(mLeft + 1, FOptions.ColumnX(mColumn + 1, FWidth));
        // Zeichen stehen auf der Grundlinie; eine Lücke trennt Nachbarn.
        if mRight - mLeft > 1 then
        begin
          Dec(mRight);
        end;
        FBitmap.Canvas.FillRect(TRect.Create(mLeft, ATop + AHeight - mHeight, mRight, ATop + AHeight));
      end;
    end;
  end;
end;

procedure TAtlasMinimapCode.PaintBlocks(ALine, ATop, AHeight: Integer);
var
  mRun: TAtlasMinimapRun;
  mHeight, mLeft, mRight: Integer;
begin
  // Balken je Wort, eine Spur dünner als die Zeile.
  mHeight := Max(1, AHeight - AHeight div 3);
  for mRun in FRuns[ALine] do
  begin
    FBitmap.Canvas.Brush.Color := TColor(TAtlasColorMath.Mix(TokenColor(FColors, mRun.Kind), FColors.Surface, 0.8));
    mLeft := FOptions.ColumnX(mRun.Start, FWidth);
    mRight := Max(mLeft + 1, FOptions.ColumnX(mRun.Stop, FWidth));
    FBitmap.Canvas.FillRect(TRect.Create(mLeft, ATop, mRight, ATop + mHeight));
  end;
end;

{ TAtlasMinimapOverlays }

class function TAtlasMinimapOverlays.Scaled(AValue, APPI: Integer): Integer;
begin
  Result := MulDiv(AValue, Max(APPI, 96), 96);
end;

procedure TAtlasMinimapOverlays.SetNodes(const ANodes: TAtlasOutlineNodes);
begin
  FNodes := ANodes;
  FHeadersValid := False;
end;

function TAtlasMinimapOverlays.SetMarks(const AMarks: TAtlasOverviewMarks): Boolean;
begin
  Result := not TAtlasOverview.Same(AMarks, FMarks);
  if Result then
  begin
    FMarks := AMarks;
    FBarsValid := False;
  end;
end;

procedure TAtlasMinimapOverlays.Invalidate;
begin
  FHeadersValid := False;
  FBarsValid := False;
end;

procedure TAtlasMinimapOverlays.PaintMethod(ACanvas: TCanvas; const AMap: TAtlasMinimapMap;
  const AFrame: TAtlasMinimapFrame);
var
  mFirst, mLast, mTop, mBottom: Integer;
begin
  if not AFrame.Options.HighlightMethod or (AFrame.Viewport.Cursor < 0) or
    not TAtlasMinimap.MethodAt(FNodes, AFrame.Viewport.Cursor, mFirst, mLast) then
  begin
    Exit;
  end;
  mTop := AMap.PixelOfLine(mFirst);
  mBottom := Max(mTop + 1, AMap.PixelOfRow(AMap.RowOf(mLast) + 1));
  Blend(ACanvas, TRect.Create(0, mTop, AFrame.Width, mBottom), AFrame.Colors.Accent, MethodAlpha);
  // Akzentstrich am linken Rand: Die leichte Hinterlegung allein ging im dunklen Thema unter.
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := TColor(AFrame.Colors.Accent);
  ACanvas.FillRect(TRect.Create(0, mTop, Scaled(MethodBarWidth, AFrame.PPI), mBottom));
end;

procedure TAtlasMinimapOverlays.PaintMarkers(ACanvas: TCanvas; const AMap: TAtlasMinimapMap;
  const AFrame: TAtlasMinimapFrame);
var
  mBar: TAtlasOverviewBar;
begin
  if not FBarsValid then
  begin
    FBars := TAtlasMinimap.MarkerBars(FMarks, AMap, Scaled(BaseMinMark, AFrame.PPI));
    FBarsValid := True;
  end;
  for mBar in FBars do
  begin
    if mBar.Lane = TAtlasOverviewLane.Left then
    begin
      ACanvas.Brush.Color := TColor(TAtlasOverviewRuler.ColorOf(AFrame.Colors, mBar.Kind));
      ACanvas.FillRect(TRect.Create(0, mBar.Top, Scaled(BaseChangeWidth, AFrame.PPI), mBar.Bottom));
    end
    else
    begin
      Blend(ACanvas, TRect.Create(0, mBar.Top, AFrame.Width, mBar.Bottom),
        TAtlasOverviewRuler.ColorOf(AFrame.Colors, mBar.Kind), BandAlpha);
    end;
  end;
end;

procedure TAtlasMinimapOverlays.PaintHeaders(ACanvas: TCanvas; const AMap: TAtlasMinimapMap;
  const AFrame: TAtlasMinimapFrame);
var
  mHeader: TAtlasMinimapHeader;
  mArea: TRect;
  mLabelHeight: Integer;
begin
  mLabelHeight := Scaled(BaseLabelHeight, AFrame.PPI);
  if not FHeadersValid then
  begin
    FHeaders := TAtlasMinimap.Headers(FNodes, AMap, mLabelHeight);
    FHeadersValid := True;
  end;
  ACanvas.Font.Height := -Scaled(8, AFrame.PPI);
  ACanvas.Font.Style := [fsBold];
  for mHeader in FHeaders do
  begin
    mArea := TRect.Create(Scaled(BaseChangeWidth, AFrame.PPI) + 1, mHeader.Top, AFrame.Width,
      mHeader.Top + mLabelHeight);
    Blend(ACanvas, TRect.Create(mArea.Left, mArea.Top, Min(AFrame.Width, mArea.Left +
      ACanvas.TextWidth(mHeader.Text) + Scaled(4, AFrame.PPI)), mArea.Bottom), AFrame.Colors.Surface, 200);
    ACanvas.Brush.Style := bsClear;
    ACanvas.Font.Color := TColor(AFrame.Colors.Text);
    if mHeader.IsType then
    begin
      ACanvas.Font.Color := TColor(AFrame.Colors.Keyword);
    end;
    ACanvas.TextRect(mArea, mArea.Left + Scaled(2, AFrame.PPI), mArea.Top, mHeader.Text);
    ACanvas.Brush.Style := bsSolid;
  end;
end;

procedure TAtlasMinimapOverlays.Paint(ACanvas: TCanvas; const AMap: TAtlasMinimapMap;
  const AFrame: TAtlasMinimapFrame);
begin
  // Routine am Cursor.
  PaintMethod(ACanvas, AMap, AFrame);
  // Marken: Zeilenband bzw. Streifen am linken Rand.
  if AFrame.Options.Markers then
  begin
    PaintMarkers(ACanvas, AMap, AFrame);
  end;
  if AFrame.Options.SectionHeaders then
  begin
    PaintHeaders(ACanvas, AMap, AFrame);
  end;
  // Schieber.
  if AFrame.SliderVisible and (AMap.RowCount > 0) then
  begin
    Blend(ACanvas, TRect.Create(0, AFrame.Slider.Top, AFrame.Width, AFrame.Slider.Bottom), AFrame.Colors.Text,
      SliderAlpha);
  end;
end;

end.
