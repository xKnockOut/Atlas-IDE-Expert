unit Atlas.UI.Documentation.View;

// Zeichnet die gesetzte XMLDoc (#654, #770) in Hover-Tooltip und Detailpanel:
// ein Ausschnitt fester Höhe, der mit dem Mausrad scrollt (rechts ein schmaler
// Balken zeigt die Lage), Überschriften mit Linie bis zum Rand, Codeblöcke auf
// schattierter, gerahmter Fläche, paramref als Pille, Verweise und Links
// unterstrichen in Akzentfarbe, Markieren mit der Maus und Kopieren des
// markierten Texts. „Mehr/Weniger anzeigen“ setzt die Doku neu (Toggle).
// Gemessen wird mit denselben Schriften, mit denen gezeichnet wird;
// Unterstreichungen sind Linien, damit sie die Breite nicht ändern.

interface

uses
  Winapi.Windows,
  System.Types,
  Vcl.Graphics,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Documentation.Contract,
  Atlas.Core.Documentation.Layout,
  Atlas.Core.Documentation.Typeset;

type
  /// <summary>Schriften der Doku: Editorschrift (Mono), Beschriftung (UI) und daraus je Art, Fett, Kursiv und
  /// Kapitälchen eine eigene Schrift; dazu die Zeilenhöhen und die DPI.</summary>
  TAtlasDocFontSet = class
  private
    FMono: TFont;
    FUI: TFont;
    FFonts: array[TAtlasDocFont, Boolean, Boolean, Boolean] of TFont;
    FMonoHeight: Integer;
    FUIHeight: Integer;
    FSmallHeight: Integer;
    FPPI: Integer;
    procedure FreeFonts;
    function HeightOf(ACanvas: TCanvas; const AFace: TAtlasDocFace): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Übernimmt AMono und AUI für APPI und misst die Zeilenhöhen auf ACanvas.</summary>
    procedure Assign(ACanvas: TCanvas; AMono, AUI: TFont; APPI: Integer);
    function FontOf(const AFace: TAtlasDocFace): TFont;
    function FaceHeight(const AFace: TAtlasDocFace): Integer;
    function TextWidth(ACanvas: TCanvas; const AText: string; const AFace: TAtlasDocFace): Integer;
    /// <summary>Messfunktion für den Satz auf ACanvas.</summary>
    function MeasureOn(ACanvas: TCanvas): TAtlasDocMeasure;
    function Scale(AValue: Integer): Integer;
    /// <summary>Höhe einer Textzeile in der Beschriftung samt Abstand.</summary>
    function LineStep: Integer;
    property PPI: Integer read FPPI;
    property MonoHeight: Integer read FMonoHeight;
  end;

  /// <summary>Schriften für TAtlasDocView.Build: Editorschrift, Beschriftung und DPI.</summary>
  TAtlasDocFonts = record
    Mono: TFont;
    UI: TFont;
    PPI: Integer;
    class function Create(AMono, AUI: TFont; APPI: Integer): TAtlasDocFonts; static;
  end;

  /// <summary>Markierung mit der Maus: Anfang und Ende als Textposition (-1 ohne), Active beim Ziehen.</summary>
  TAtlasDocSelection = record
    Anchor: Integer;
    Caret: Integer;
    Active: Boolean;
    class function None: TAtlasDocSelection; static;
  end;

  TAtlasDocView = class
  private
    FLayout: TAtlasDocLayout;
    FFonts: TAtlasDocFontSet;
    FContent: TAtlasDocContent;
    FLabels: TAtlasDocLabels;
    FMetrics: TAtlasDocMetrics;
    FWidth: Integer;
    FViewport: Integer;
    FScroll: Integer;
    FSelection: TAtlasDocSelection;
    FHotLink: Integer;
    procedure ClampScroll;
    procedure Relayout(ACanvas: TCanvas);
    procedure PaintThumb(ACanvas: TCanvas; const AColors: TAtlasColors; ALeft, ATop: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Setzt AContent (Doku, Ordnung der Parameter, aufgeklappt) für die Breite AWidth; AFonts nennt
    /// Editorschrift, Beschriftung und DPI. Danach zeigt der Ausschnitt alles (Height = volle Höhe), bis
    /// FitHeight ihn begrenzt.</summary>
    procedure Build(ACanvas: TCanvas; const AContent: TAtlasDocContent; AWidth: Integer; const AFonts: TAtlasDocFonts;
      const ALabels: TAtlasDocLabels);
    /// <summary>Klappt auf bzw. zu und setzt neu; liefert den neuen Zustand.</summary>
    function Toggle(ACanvas: TCanvas): Boolean;
    procedure Clear;
    function IsEmpty: Boolean;
    /// <summary>Begrenzt den Ausschnitt auf höchstens AMaxLines Zeilen (0 = alle) und AMaxHeight Pixel
    /// (0 = unbegrenzt), mindestens aber drei Zeilen; liefert die Höhe.</summary>
    function FitHeight(AMaxLines, AMaxHeight: Integer): Integer;
    /// <summary>Zeichnet den Ausschnitt mit linker oberer Ecke (ALeft, ATop).</summary>
    procedure Paint(ACanvas: TCanvas; const AColors: TAtlasColors; ALeft, ATop: Integer);
    /// <summary>Link unter (AX, AY) relativ zur linken oberen Ecke; -1 ohne.</summary>
    function LinkAt(AX, AY: Integer): Integer;
    function Link(AIndex: Integer): TAtlasDocLink;
    /// <summary>Verschiebt um ADelta Pixel; True, wenn sich etwas bewegt hat.</summary>
    function ScrollBy(ADelta: Integer): Boolean;
    /// <summary>Schritt für eine Rasterstufe des Mausrads (drei Zeilen).</summary>
    function WheelStep: Integer;
    function CanScroll: Boolean;
    procedure StartSelection(ACanvas: TCanvas; AX, AY: Integer);
    /// <summary>Erweitert die Markierung; über bzw. unter dem Ausschnitt scrollt sie mit.</summary>
    procedure ExtendSelection(ACanvas: TCanvas; AX, AY: Integer);
    procedure EndSelection;
    procedure ClearSelection;
    function HasSelection: Boolean;
    function SelectedText: string;
    property Layout: TAtlasDocLayout read FLayout;
    property Expanded: Boolean read FContent.Expanded;
    property Width: Integer read FWidth;
    /// <summary>Höhe des Ausschnitts.</summary>
    property Height: Integer read FViewport;
    property Scroll: Integer read FScroll;
    property Selecting: Boolean read FSelection.Active;
    /// <summary>Hervorgehobener Link (Maus darüber); -1 ohne.</summary>
    property HotLink: Integer read FHotLink write FHotLink;
  end;

implementation

uses
  Atlas.UI.Popup.Draw,
  System.SysUtils,
  System.Math,
  Atlas.UI.Popup.Window;

{ TAtlasDocFonts }

class function TAtlasDocFonts.Create(AMono, AUI: TFont; APPI: Integer): TAtlasDocFonts;
begin
  Result.Mono := AMono;
  Result.UI := AUI;
  Result.PPI := APPI;
end;

{ TAtlasDocSelection }

class function TAtlasDocSelection.None: TAtlasDocSelection;
begin
  Result.Anchor := -1;
  Result.Caret := -1;
  Result.Active := False;
end;

{ TAtlasDocFontSet }

constructor TAtlasDocFontSet.Create;
begin
  inherited Create;
  FMono := TFont.Create;
  FUI := TFont.Create;
  FPPI := 96;
end;

destructor TAtlasDocFontSet.Destroy;
begin
  FreeFonts;
  FMono.Free;
  FUI.Free;
  inherited Destroy;
end;

procedure TAtlasDocFontSet.FreeFonts;
var
  mFont: TAtlasDocFont;
  mBold, mItalic, mSmall: Boolean;
begin
  for mFont := Low(TAtlasDocFont) to High(TAtlasDocFont) do
  begin
    for mBold := False to True do
    begin
      for mItalic := False to True do
      begin
        for mSmall := False to True do
        begin
          FreeAndNil(FFonts[mFont, mBold, mItalic, mSmall]);
        end;
      end;
    end;
  end;
end;

function TAtlasDocFontSet.HeightOf(ACanvas: TCanvas; const AFace: TAtlasDocFace): Integer;
var
  mSize: TSize;
  mOld: HGDIOBJ;
begin
  mOld := SelectObject(ACanvas.Handle, FontOf(AFace).Handle);
  try
    GetTextExtentPoint32(ACanvas.Handle, 'Wg', 2, mSize);
  finally
    SelectObject(ACanvas.Handle, mOld);
  end;
  Result := mSize.cy;
end;

procedure TAtlasDocFontSet.Assign(ACanvas: TCanvas; AMono, AUI: TFont; APPI: Integer);
begin
  FreeFonts;
  FMono.Assign(AMono);
  FUI.Assign(AUI);
  FPPI := Max(APPI, 1);
  // Zeilenhöhen aus den Schriften selbst.
  FMonoHeight := HeightOf(ACanvas, TAtlasDocFace.Create(TAtlasDocFont.Mono));
  FUIHeight := HeightOf(ACanvas, TAtlasDocFace.Create(TAtlasDocFont.UI));
  FSmallHeight := HeightOf(ACanvas, TAtlasDocFace.Heading);
end;

function TAtlasDocFontSet.Scale(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, FPPI, 96);
end;

function TAtlasDocFontSet.LineStep: Integer;
begin
  Result := FUIHeight + Scale(2);
end;

function TAtlasDocFontSet.FontOf(const AFace: TAtlasDocFace): TFont;
var
  mStyle: TFontStyles;
begin
  Result := FFonts[AFace.Font, AFace.Bold, AFace.Italic, AFace.Small];
  if Result <> nil then
  begin
    Exit;
  end;
  Result := TFont.Create;
  if AFace.Font = TAtlasDocFont.Mono then
  begin
    Result.Assign(FMono);
  end
  else
  begin
    Result.Assign(FUI);
  end;
  mStyle := [];
  if AFace.Bold then
  begin
    Include(mStyle, fsBold);
  end;
  if AFace.Italic then
  begin
    Include(mStyle, fsItalic);
  end;
  Result.Style := mStyle;
  // Überschriften in Kapitälchen: Großbuchstaben etwas kleiner.
  if AFace.Small then
  begin
    Result.Height := MulDiv(Result.Height, 85, 100);
  end;
  FFonts[AFace.Font, AFace.Bold, AFace.Italic, AFace.Small] := Result;
end;

function TAtlasDocFontSet.FaceHeight(const AFace: TAtlasDocFace): Integer;
begin
  if AFace.Font = TAtlasDocFont.Mono then
  begin
    Result := FMonoHeight;
  end
  else if AFace.Small then
  begin
    Result := FSmallHeight;
  end
  else
  begin
    Result := FUIHeight;
  end;
end;

function TAtlasDocFontSet.TextWidth(ACanvas: TCanvas; const AText: string; const AFace: TAtlasDocFace): Integer;
var
  mSize: TSize;
  mOld: HGDIOBJ;
begin
  if AText = '' then
  begin
    Exit(0);
  end;
  mOld := SelectObject(ACanvas.Handle, FontOf(AFace).Handle);
  try
    GetTextExtentPoint32(ACanvas.Handle, PChar(AText), Length(AText), mSize);
  finally
    SelectObject(ACanvas.Handle, mOld);
  end;
  Result := mSize.cx;
end;

function TAtlasDocFontSet.MeasureOn(ACanvas: TCanvas): TAtlasDocMeasure;
var
  mFonts: TAtlasDocFontSet;
  mCanvas: TCanvas;
begin
  mFonts := Self;
  mCanvas := ACanvas;
  Result :=
    function(const AText: string; const AFace: TAtlasDocFace): Integer
    begin
      Result := mFonts.TextWidth(mCanvas, AText, AFace);
    end;
end;

{ TAtlasDocView }

constructor TAtlasDocView.Create;
begin
  inherited Create;
  FFonts := TAtlasDocFontSet.Create;
  FSelection := TAtlasDocSelection.None;
  FHotLink := -1;
end;

destructor TAtlasDocView.Destroy;
begin
  FFonts.Free;
  inherited Destroy;
end;

procedure TAtlasDocView.Build(ACanvas: TCanvas; const AContent: TAtlasDocContent; AWidth: Integer;
  const AFonts: TAtlasDocFonts; const ALabels: TAtlasDocLabels);
begin
  FFonts.Assign(ACanvas, AFonts.Mono, AFonts.UI, AFonts.PPI);
  FWidth := Max(AWidth, 1);
  FMetrics := TAtlasDocMetrics.Create(FFonts.LineStep, FFonts.MonoHeight + FFonts.Scale(2), FFonts.PPI / 96);
  FContent := AContent;
  FLabels := ALabels;
  Relayout(ACanvas);
  FScroll := 0;
end;

procedure TAtlasDocView.Relayout(ACanvas: TCanvas);
begin
  FLayout := TAtlasDocTypeset.Build(FContent, FWidth, FMetrics, FFonts.MeasureOn(ACanvas), FLabels);
  FViewport := FLayout.Height;
  ClampScroll;
  FSelection := TAtlasDocSelection.None;
  FHotLink := -1;
end;

function TAtlasDocView.Toggle(ACanvas: TCanvas): Boolean;
begin
  FContent.Expanded := not FLayout.Expanded;
  Relayout(ACanvas);
  Result := FContent.Expanded;
end;

procedure TAtlasDocView.Clear;
begin
  FLayout := Default(TAtlasDocLayout);
  FContent.Doc := Default(TAtlasDoc);
  FContent.Signature := Default(TAtlasDocSignature);
  FViewport := 0;
  FScroll := 0;
  FSelection := TAtlasDocSelection.None;
  FHotLink := -1;
end;

function TAtlasDocView.IsEmpty: Boolean;
begin
  Result := FLayout.IsEmpty;
end;

function TAtlasDocView.FitHeight(AMaxLines, AMaxHeight: Integer): Integer;
begin
  FViewport := FLayout.Height;
  if AMaxLines > 0 then
  begin
    FViewport := Min(FViewport, FLayout.HeightOfLines(AMaxLines));
  end;
  if AMaxHeight > 0 then
  begin
    FViewport := Min(FViewport, Max(AMaxHeight, FLayout.HeightOfLines(3)));
  end;
  ClampScroll;
  Result := FViewport;
end;

procedure TAtlasDocView.ClampScroll;
begin
  FScroll := EnsureRange(FScroll, 0, Max(0, FLayout.Height - FViewport));
end;

function TAtlasDocView.CanScroll: Boolean;
begin
  Result := FLayout.Height > FViewport;
end;

function TAtlasDocView.WheelStep: Integer;
begin
  Result := 3 * FFonts.LineStep;
end;

function TAtlasDocView.ScrollBy(ADelta: Integer): Boolean;
var
  mOld: Integer;
begin
  mOld := FScroll;
  Inc(FScroll, ADelta);
  ClampScroll;
  Result := FScroll <> mOld;
end;

function TAtlasDocView.LinkAt(AX, AY: Integer): Integer;
begin
  if (AY < 0) or (AY >= FViewport) or (AX < 0) or (AX >= FWidth) then
  begin
    Exit(-1);
  end;
  Result := FLayout.LinkAt(AX, AY + FScroll);
end;

function TAtlasDocView.Link(AIndex: Integer): TAtlasDocLink;
begin
  Result := FLayout.Links[AIndex];
end;

procedure TAtlasDocView.StartSelection(ACanvas: TCanvas; AX, AY: Integer);
begin
  FSelection.Anchor := FLayout.PositionAt(AX, AY + FScroll, FFonts.MeasureOn(ACanvas));
  FSelection.Caret := FSelection.Anchor;
  FSelection.Active := True;
end;

procedure TAtlasDocView.ExtendSelection(ACanvas: TCanvas; AX, AY: Integer);
begin
  if not FSelection.Active then
  begin
    Exit;
  end;
  if AY < 0 then
  begin
    ScrollBy(-FFonts.LineStep);
  end
  else if AY >= FViewport then
  begin
    ScrollBy(FFonts.LineStep);
  end;
  FSelection.Caret := FLayout.PositionAt(AX, AY + FScroll, FFonts.MeasureOn(ACanvas));
end;

procedure TAtlasDocView.EndSelection;
begin
  FSelection.Active := False;
end;

procedure TAtlasDocView.ClearSelection;
begin
  FSelection := TAtlasDocSelection.None;
end;

function TAtlasDocView.HasSelection: Boolean;
begin
  Result := (FSelection.Anchor >= 0) and (FSelection.Caret >= 0) and (FSelection.Anchor <> FSelection.Caret);
end;

function TAtlasDocView.SelectedText: string;
begin
  if HasSelection then
  begin
    Result := FLayout.Selected(FSelection.Anchor, FSelection.Caret);
  end
  else
  begin
    Result := '';
  end;
end;

function ColorOf(const AColors: TAtlasColors; AColor: TAtlasDocColor): TAtlasColor;
begin
  case AColor of
    TAtlasDocColor.Muted:
      Result := AColors.Muted;
    TAtlasDocColor.Accent:
      Result := AColors.Accent;
    TAtlasDocColor.Error:
      Result := AColors.Error;
    TAtlasDocColor.Keyword:
      Result := AColors.Keyword;
    TAtlasDocColor.StringLiteral:
      Result := AColors.StringLiteral;
    TAtlasDocColor.Comment:
      Result := AColors.Comment;
    TAtlasDocColor.Warn:
      Result := AColors.Warn;
  else
    Result := AColors.Text;
  end;
end;

type
  /// <summary>Zeichnen der Zeilen eines Ausschnitts: Zielfläche, Farben, Satz und Markierung.</summary>
  TAtlasDocPainter = record
    Canvas: TCanvas;
    Colors: TAtlasColors;
    Fonts: TAtlasDocFontSet;
    Layout: TAtlasDocLayout;
    Measure: TAtlasDocMeasure;
    Left: Integer;
    Top: Integer;
    Width: Integer;
    Scroll: Integer;
    /// <summary>Höhe des Ausschnitts.</summary>
    Viewport: Integer;
    Pad: Integer;
    HotLink: Integer;
    Selected: Boolean;
    From: Integer;
    Till: Integer;
    /// <summary>Codefläche: schattiert und gerahmt über aufeinanderfolgende Codezeilen.</summary>
    procedure Shade(AIndex, AY: Integer);
    /// <summary>Überschrift: Linie von hinter dem Text bis zum rechten Rand.</summary>
    procedure Rule(const ALine: TAtlasDocLine; AY: Integer);
    procedure Underline(const ASpan: TAtlasDocSpan; ASpanTop: Integer);
    procedure Span(const ASpan: TAtlasDocSpan; const ALine: TAtlasDocLine; AY: Integer);
    procedure Line(AIndex: Integer);
  end;

procedure TAtlasDocPainter.Shade(AIndex, AY: Integer);
var
  mLine: TAtlasDocLine;
  mFirst, mLast: Boolean;
  mTop, mBottom: Integer;
begin
  mLine := Layout.Lines[AIndex];
  mFirst := (AIndex = 0) or not Layout.Lines[AIndex - 1].Shaded;
  mLast := (AIndex = High(Layout.Lines)) or not Layout.Lines[AIndex + 1].Shaded;
  mTop := AY;
  if mFirst then
  begin
    Dec(mTop, Pad);
  end;
  mBottom := AY + mLine.Height + Pad;
  if not mLast then
  begin
    mBottom := Top + Layout.Lines[AIndex + 1].Top - Scroll;
  end;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Gutter);
  Canvas.FillRect(Rect(Left + mLine.ShadeLeft, mTop, Left + Width, mBottom));
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := 1;
  Canvas.Pen.Color := ToColor(Colors.Line);
  Canvas.MoveTo(Left + mLine.ShadeLeft, mTop);
  Canvas.LineTo(Left + mLine.ShadeLeft, mBottom);
  Canvas.MoveTo(Left + Width - 1, mTop);
  Canvas.LineTo(Left + Width - 1, mBottom);
  if mFirst then
  begin
    Canvas.MoveTo(Left + mLine.ShadeLeft, mTop);
    Canvas.LineTo(Left + Width, mTop);
  end;
  if mLast then
  begin
    Canvas.MoveTo(Left + mLine.ShadeLeft, mBottom - 1);
    Canvas.LineTo(Left + Width, mBottom - 1);
  end;
end;

procedure TAtlasDocPainter.Rule(const ALine: TAtlasDocLine; AY: Integer);
begin
  if not ALine.Rule or (ALine.RuleFrom >= Width) then
  begin
    Exit;
  end;
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := 1;
  Canvas.Pen.Color := ToColor(Colors.Line);
  Canvas.MoveTo(Left + ALine.RuleFrom, AY + ALine.Height div 2);
  Canvas.LineTo(Left + Width, AY + ALine.Height div 2);
end;

procedure TAtlasDocPainter.Underline(const ASpan: TAtlasDocSpan; ASpanTop: Integer);
var
  mHot: Boolean;
begin
  mHot := (ASpan.Link >= 0) and (ASpan.Link = HotLink);
  if not ASpan.Underline and not mHot then
  begin
    Exit;
  end;
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := ToColor(ColorOf(Colors, ASpan.Color));
  Canvas.Pen.Width := 1;
  if mHot then
  begin
    Canvas.Pen.Width := Max(2, Fonts.Scale(2));
  end;
  Canvas.MoveTo(Left + ASpan.Left, ASpanTop + Fonts.FaceHeight(ASpan.Face));
  Canvas.LineTo(Left + ASpan.Right, ASpanTop + Fonts.FaceHeight(ASpan.Face));
  Canvas.Pen.Width := 1;
end;

procedure TAtlasDocPainter.Span(const ASpan: TAtlasDocSpan; const ALine: TAtlasDocLine; AY: Integer);
var
  mSpanTop, mSelLeft, mSelRight: Integer;
begin
  mSpanTop := AY + (ALine.Height - Fonts.FaceHeight(ASpan.Face)) div 2;
  if ASpan.Pill then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := ToColor(Colors.AccentSoft);
    Canvas.Pen.Style := psClear;
    Canvas.RoundRect(Left + ASpan.Left, mSpanTop, Left + ASpan.Right, mSpanTop + Fonts.FaceHeight(ASpan.Face),
      Fonts.Scale(6), Fonts.Scale(6));
    Canvas.Pen.Style := psSolid;
  end;
  if Selected and Layout.SpanRange(ASpan, From, Till, Measure, mSelLeft, mSelRight) then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := ToColor(Colors.Selection);
    Canvas.FillRect(Rect(Left + mSelLeft, AY, Left + mSelRight, AY + ALine.Height));
  end;
  Canvas.Font := Fonts.FontOf(ASpan.Face);
  Canvas.Font.Color := ToColor(ColorOf(Colors, ASpan.Color));
  Canvas.Brush.Style := bsClear;
  Canvas.TextOut(Left + ASpan.Left + ASpan.Pad, mSpanTop, ASpan.Text);
  Underline(ASpan, mSpanTop);
end;

procedure TAtlasDocPainter.Line(AIndex: Integer);
var
  mLine: TAtlasDocLine;
  mSpan: TAtlasDocSpan;
  mY: Integer;
begin
  mLine := Layout.Lines[AIndex];
  mY := Top + mLine.Top - Scroll;
  if (mY + mLine.Height + Pad < Top) or (mY - Pad > Top + Viewport) then
  begin
    Exit;
  end;
  if mLine.Shaded then
  begin
    Shade(AIndex, mY);
  end;
  Rule(mLine, mY);
  for mSpan in mLine.Spans do
  begin
    Span(mSpan, mLine, mY);
  end;
end;

procedure TAtlasDocView.Paint(ACanvas: TCanvas; const AColors: TAtlasColors; ALeft, ATop: Integer);
var
  mSaved, mIndex: Integer;
  mPainter: TAtlasDocPainter;
begin
  if FLayout.IsEmpty or (FViewport <= 0) then
  begin
    Exit;
  end;
  mPainter := Default(TAtlasDocPainter);
  mPainter.Canvas := ACanvas;
  mPainter.Colors := AColors;
  mPainter.Fonts := FFonts;
  mPainter.Layout := FLayout;
  mPainter.Measure := FFonts.MeasureOn(ACanvas);
  mPainter.Left := ALeft;
  mPainter.Top := ATop;
  mPainter.Width := FWidth;
  mPainter.Scroll := FScroll;
  mPainter.Viewport := FViewport;
  mPainter.Pad := FFonts.Scale(3);
  mPainter.HotLink := FHotLink;
  mPainter.Selected := HasSelection;
  mPainter.From := Min(FSelection.Anchor, FSelection.Caret);
  mPainter.Till := Max(FSelection.Anchor, FSelection.Caret);
  mSaved := SaveDC(ACanvas.Handle);
  try
    IntersectClipRect(ACanvas.Handle, ALeft, ATop, ALeft + FWidth + FFonts.Scale(2), ATop + FViewport);
    for mIndex := 0 to High(FLayout.Lines) do
    begin
      mPainter.Line(mIndex);
    end;
  finally
    RestoreDC(ACanvas.Handle, mSaved);
    // RestoreDC wählt die alten Objekte; TCanvas soll Schrift, Stift und Pinsel neu wählen.
    ACanvas.Refresh;
  end;
  PaintThumb(ACanvas, AColors, ALeft, ATop);
  ACanvas.Brush.Style := bsSolid;
end;

procedure TAtlasDocView.PaintThumb(ACanvas: TCanvas; const AColors: TAtlasColors; ALeft, ATop: Integer);
var
  mThumb, mThumbTop: Integer;
begin
  // Lage im Text: schmaler Balken rechts neben dem Ausschnitt.
  if not CanScroll then
  begin
    Exit;
  end;
  mThumb := Max(FFonts.Scale(16), MulDiv(FViewport, FViewport, FLayout.Height));
  mThumbTop := ATop + MulDiv(FViewport - mThumb, FScroll, Max(1, FLayout.Height - FViewport));
  TAtlasDraw.Thumb(ACanvas, Rect(ALeft + FWidth + FFonts.Scale(4), mThumbTop, ALeft + FWidth + FFonts.Scale(7),
    mThumbTop + mThumb), AColors, 0);
end;

end.
