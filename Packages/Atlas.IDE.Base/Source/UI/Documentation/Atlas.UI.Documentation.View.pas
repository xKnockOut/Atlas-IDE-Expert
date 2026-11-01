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
  Atlas.Core.Documentation.Layout;

type
  TAtlasDocView = class
  private
    FLayout: TAtlasDocLayout;
    FMono: TFont;
    FUI: TFont;
    FFonts: array[TAtlasDocFont, Boolean, Boolean, Boolean] of TFont;
    FDoc: TAtlasDoc;
    FSignature: TAtlasDocSignature;
    FLabels: TAtlasDocLabels;
    FExpanded: Boolean;
    FMetrics: TAtlasDocMetrics;
    FMonoHeight: Integer;
    FUIHeight: Integer;
    FSmallHeight: Integer;
    FPPI: Integer;
    FWidth: Integer;
    FViewport: Integer;
    FScroll: Integer;
    FAnchor: Integer;
    FCaret: Integer;
    FSelecting: Boolean;
    FHotLink: Integer;
    function FontOf(const AFace: TAtlasDocFace): TFont;
    function FaceHeight(const AFace: TAtlasDocFace): Integer;
    function TextWidth(ACanvas: TCanvas; const AText: string; const AFace: TAtlasDocFace): Integer;
    function MeasureOn(ACanvas: TCanvas): TAtlasDocMeasure;
    function Scale(AValue: Integer): Integer;
    procedure FreeFonts;
    procedure ClampScroll;
    procedure Relayout(ACanvas: TCanvas);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Setzt ADoc für die Breite AWidth; AMono ist die Editorschrift, AUI die der Beschriftungen,
    /// ASignature ordnet die Parameter, AExpanded = aufgeklappt. Danach zeigt der Ausschnitt alles
    /// (Height = volle Höhe), bis FitHeight ihn begrenzt.</summary>
    procedure Build(ACanvas: TCanvas; const ADoc: TAtlasDoc; AWidth: Integer; AMono, AUI: TFont; APPI: Integer;
      const ALabels: TAtlasDocLabels; const ASignature: TAtlasDocSignature; AExpanded: Boolean);
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
    property Expanded: Boolean read FExpanded;
    property Width: Integer read FWidth;
    /// <summary>Höhe des Ausschnitts.</summary>
    property Height: Integer read FViewport;
    property Scroll: Integer read FScroll;
    property Selecting: Boolean read FSelecting;
    /// <summary>Hervorgehobener Link (Maus darüber); -1 ohne.</summary>
    property HotLink: Integer read FHotLink write FHotLink;
  end;

implementation

uses
  Atlas.UI.Popup.Draw,
  System.SysUtils,
  System.Math,
  Atlas.UI.Popup.Window;

{ TAtlasDocView }

constructor TAtlasDocView.Create;
begin
  inherited Create;
  FMono := TFont.Create;
  FUI := TFont.Create;
  FPPI := 96;
  FAnchor := -1;
  FCaret := -1;
  FHotLink := -1;
end;

destructor TAtlasDocView.Destroy;
begin
  FreeFonts;
  FMono.Free;
  FUI.Free;
  inherited Destroy;
end;

procedure TAtlasDocView.FreeFonts;
var
  Font: TAtlasDocFont;
  Bold, Italic, Small: Boolean;
begin
  for Font := Low(TAtlasDocFont) to High(TAtlasDocFont) do
    for Bold := False to True do
      for Italic := False to True do
        for Small := False to True do
          FreeAndNil(FFonts[Font, Bold, Italic, Small]);
end;

function TAtlasDocView.Scale(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, FPPI, 96);
end;

function TAtlasDocView.FontOf(const AFace: TAtlasDocFace): TFont;
var
  Style: TFontStyles;
begin
  Result := FFonts[AFace.Font, AFace.Bold, AFace.Italic, AFace.Small];
  if Result <> nil then
    Exit;
  Result := TFont.Create;
  if AFace.Font = TAtlasDocFont.Mono then
    Result.Assign(FMono)
  else
    Result.Assign(FUI);
  Style := [];
  if AFace.Bold then
    Include(Style, fsBold);
  if AFace.Italic then
    Include(Style, fsItalic);
  Result.Style := Style;
  // Überschriften in Kapitälchen: Großbuchstaben etwas kleiner.
  if AFace.Small then
    Result.Height := MulDiv(Result.Height, 85, 100);
  FFonts[AFace.Font, AFace.Bold, AFace.Italic, AFace.Small] := Result;
end;

function TAtlasDocView.FaceHeight(const AFace: TAtlasDocFace): Integer;
begin
  if AFace.Font = TAtlasDocFont.Mono then
    Result := FMonoHeight
  else if AFace.Small then
    Result := FSmallHeight
  else
    Result := FUIHeight;
end;

function TAtlasDocView.TextWidth(ACanvas: TCanvas; const AText: string; const AFace: TAtlasDocFace): Integer;
var
  Size: TSize;
  Old: HGDIOBJ;
begin
  if AText = '' then
    Exit(0);
  Old := SelectObject(ACanvas.Handle, FontOf(AFace).Handle);
  try
    GetTextExtentPoint32(ACanvas.Handle, PChar(AText), Length(AText), Size);
  finally
    SelectObject(ACanvas.Handle, Old);
  end;
  Result := Size.cx;
end;

function TAtlasDocView.MeasureOn(ACanvas: TCanvas): TAtlasDocMeasure;
var
  View: TAtlasDocView;
  Canvas: TCanvas;
begin
  View := Self;
  Canvas := ACanvas;
  Result :=
    function(const AText: string; const AFace: TAtlasDocFace): Integer
    begin
      Result := View.TextWidth(Canvas, AText, AFace);
    end;
end;

procedure TAtlasDocView.Build(ACanvas: TCanvas; const ADoc: TAtlasDoc; AWidth: Integer; AMono, AUI: TFont;
  APPI: Integer; const ALabels: TAtlasDocLabels; const ASignature: TAtlasDocSignature; AExpanded: Boolean);
var
  Size: TSize;
  Old: HGDIOBJ;
begin
  FreeFonts;
  FMono.Assign(AMono);
  FUI.Assign(AUI);
  FPPI := Max(APPI, 1);
  FWidth := Max(AWidth, 1);
  // Zeilenhöhen aus den Schriften selbst.
  Old := SelectObject(ACanvas.Handle, FontOf(TAtlasDocFace.Create(TAtlasDocFont.Mono)).Handle);
  GetTextExtentPoint32(ACanvas.Handle, 'Wg', 2, Size);
  FMonoHeight := Size.cy;
  SelectObject(ACanvas.Handle, FontOf(TAtlasDocFace.Create(TAtlasDocFont.UI)).Handle);
  GetTextExtentPoint32(ACanvas.Handle, 'Wg', 2, Size);
  FUIHeight := Size.cy;
  SelectObject(ACanvas.Handle, FontOf(TAtlasDocFace.Heading).Handle);
  GetTextExtentPoint32(ACanvas.Handle, 'Wg', 2, Size);
  FSmallHeight := Size.cy;
  SelectObject(ACanvas.Handle, Old);
  FMetrics := TAtlasDocMetrics.Create(FUIHeight + Scale(2), FMonoHeight + Scale(2), FPPI / 96);
  FDoc := ADoc;
  FSignature := ASignature;
  FLabels := ALabels;
  FExpanded := AExpanded;
  Relayout(ACanvas);
  FScroll := 0;
end;

procedure TAtlasDocView.Relayout(ACanvas: TCanvas);
begin
  FLayout := TAtlasDocLayout.Build(FDoc, FWidth, FMetrics, MeasureOn(ACanvas), FLabels, FSignature, FExpanded);
  FViewport := FLayout.Height;
  ClampScroll;
  FAnchor := -1;
  FCaret := -1;
  FSelecting := False;
  FHotLink := -1;
end;

function TAtlasDocView.Toggle(ACanvas: TCanvas): Boolean;
begin
  FExpanded := not FLayout.Expanded;
  Relayout(ACanvas);
  Result := FExpanded;
end;

procedure TAtlasDocView.Clear;
begin
  FLayout := Default(TAtlasDocLayout);
  FDoc := Default(TAtlasDoc);
  FSignature := Default(TAtlasDocSignature);
  FViewport := 0;
  FScroll := 0;
  FAnchor := -1;
  FCaret := -1;
  FSelecting := False;
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
    FViewport := Min(FViewport, FLayout.HeightOfLines(AMaxLines));
  if AMaxHeight > 0 then
    FViewport := Min(FViewport, Max(AMaxHeight, FLayout.HeightOfLines(3)));
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
  Result := 3 * (FUIHeight + Scale(2));
end;

function TAtlasDocView.ScrollBy(ADelta: Integer): Boolean;
var
  Old: Integer;
begin
  Old := FScroll;
  Inc(FScroll, ADelta);
  ClampScroll;
  Result := FScroll <> Old;
end;

function TAtlasDocView.LinkAt(AX, AY: Integer): Integer;
begin
  if (AY < 0) or (AY >= FViewport) or (AX < 0) or (AX >= FWidth) then
    Exit(-1);
  Result := FLayout.LinkAt(AX, AY + FScroll);
end;

function TAtlasDocView.Link(AIndex: Integer): TAtlasDocLink;
begin
  Result := FLayout.Links[AIndex];
end;

procedure TAtlasDocView.StartSelection(ACanvas: TCanvas; AX, AY: Integer);
begin
  FAnchor := FLayout.PositionAt(AX, AY + FScroll, MeasureOn(ACanvas));
  FCaret := FAnchor;
  FSelecting := True;
end;

procedure TAtlasDocView.ExtendSelection(ACanvas: TCanvas; AX, AY: Integer);
begin
  if not FSelecting then
    Exit;
  if AY < 0 then
    ScrollBy(-(FUIHeight + Scale(2)))
  else if AY >= FViewport then
    ScrollBy(FUIHeight + Scale(2));
  FCaret := FLayout.PositionAt(AX, AY + FScroll, MeasureOn(ACanvas));
end;

procedure TAtlasDocView.EndSelection;
begin
  FSelecting := False;
end;

procedure TAtlasDocView.ClearSelection;
begin
  FAnchor := -1;
  FCaret := -1;
  FSelecting := False;
end;

function TAtlasDocView.HasSelection: Boolean;
begin
  Result := (FAnchor >= 0) and (FCaret >= 0) and (FAnchor <> FCaret);
end;

function TAtlasDocView.SelectedText: string;
begin
  if HasSelection then
    Result := FLayout.Selected(FAnchor, FCaret)
  else
    Result := '';
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

procedure TAtlasDocView.Paint(ACanvas: TCanvas; const AColors: TAtlasColors; ALeft, ATop: Integer);
var
  Saved, Y, SpanTop, From, Till, SelLeft, SelRight, Track, Thumb, ThumbTop, Index, Pad, ShadeTop,
    ShadeBottom: Integer;
  Line: TAtlasDocLine;
  FirstShaded, LastShaded: Boolean;
  Span: TAtlasDocSpan;
  Measure: TAtlasDocMeasure;
  Selected: Boolean;
begin
  if FLayout.IsEmpty or (FViewport <= 0) then
    Exit;
  Measure := MeasureOn(ACanvas);
  Selected := HasSelection;
  From := Min(FAnchor, FCaret);
  Till := Max(FAnchor, FCaret);
  Saved := SaveDC(ACanvas.Handle);
  try
    IntersectClipRect(ACanvas.Handle, ALeft, ATop, ALeft + FWidth + Scale(2), ATop + FViewport);
    Pad := Scale(3);
    for Index := 0 to High(FLayout.Lines) do
    begin
      Line := FLayout.Lines[Index];
      Y := ATop + Line.Top - FScroll;
      if (Y + Line.Height + Pad < ATop) or (Y - Pad > ATop + FViewport) then
        Continue;
      // Codefläche: schattiert und gerahmt über aufeinanderfolgende Codezeilen.
      if Line.Shaded then
      begin
        FirstShaded := (Index = 0) or not FLayout.Lines[Index - 1].Shaded;
        LastShaded := (Index = High(FLayout.Lines)) or not FLayout.Lines[Index + 1].Shaded;
        ShadeTop := Y;
        if FirstShaded then
          Dec(ShadeTop, Pad);
        ShadeBottom := Y + Line.Height;
        if LastShaded then
          Inc(ShadeBottom, Pad)
        else
          ShadeBottom := ATop + FLayout.Lines[Index + 1].Top - FScroll;
        ACanvas.Brush.Style := bsSolid;
        ACanvas.Brush.Color := ToColor(AColors.Gutter);
        ACanvas.FillRect(Rect(ALeft + Line.ShadeLeft, ShadeTop, ALeft + FWidth, ShadeBottom));
        ACanvas.Pen.Style := psSolid;
        ACanvas.Pen.Width := 1;
        ACanvas.Pen.Color := ToColor(AColors.Line);
        ACanvas.MoveTo(ALeft + Line.ShadeLeft, ShadeTop);
        ACanvas.LineTo(ALeft + Line.ShadeLeft, ShadeBottom);
        ACanvas.MoveTo(ALeft + FWidth - 1, ShadeTop);
        ACanvas.LineTo(ALeft + FWidth - 1, ShadeBottom);
        if FirstShaded then
        begin
          ACanvas.MoveTo(ALeft + Line.ShadeLeft, ShadeTop);
          ACanvas.LineTo(ALeft + FWidth, ShadeTop);
        end;
        if LastShaded then
        begin
          ACanvas.MoveTo(ALeft + Line.ShadeLeft, ShadeBottom - 1);
          ACanvas.LineTo(ALeft + FWidth, ShadeBottom - 1);
        end;
      end;
      // Überschrift: Linie von hinter dem Text bis zum rechten Rand.
      if Line.Rule and (Line.RuleFrom < FWidth) then
      begin
        ACanvas.Pen.Style := psSolid;
        ACanvas.Pen.Width := 1;
        ACanvas.Pen.Color := ToColor(AColors.Line);
        ACanvas.MoveTo(ALeft + Line.RuleFrom, Y + Line.Height div 2);
        ACanvas.LineTo(ALeft + FWidth, Y + Line.Height div 2);
      end;
      for Span in Line.Spans do
      begin
        SpanTop := Y + (Line.Height - FaceHeight(Span.Face)) div 2;
        if Span.Pill then
        begin
          ACanvas.Brush.Style := bsSolid;
          ACanvas.Brush.Color := ToColor(AColors.AccentSoft);
          ACanvas.Pen.Style := psClear;
          ACanvas.RoundRect(ALeft + Span.Left, SpanTop, ALeft + Span.Right, SpanTop + FaceHeight(Span.Face),
            Scale(6), Scale(6));
          ACanvas.Pen.Style := psSolid;
        end;
        if Selected and FLayout.SpanRange(Span, From, Till, Measure, SelLeft, SelRight) then
        begin
          ACanvas.Brush.Style := bsSolid;
          ACanvas.Brush.Color := ToColor(AColors.Selection);
          ACanvas.FillRect(Rect(ALeft + SelLeft, Y, ALeft + SelRight, Y + Line.Height));
        end;
        ACanvas.Font := FontOf(Span.Face);
        ACanvas.Font.Color := ToColor(ColorOf(AColors, Span.Color));
        ACanvas.Brush.Style := bsClear;
        ACanvas.TextOut(ALeft + Span.Left + Span.Pad, SpanTop, Span.Text);
        if Span.Underline or ((Span.Link >= 0) and (Span.Link = FHotLink)) then
        begin
          ACanvas.Pen.Style := psSolid;
          ACanvas.Pen.Color := ToColor(ColorOf(AColors, Span.Color));
          if (Span.Link >= 0) and (Span.Link = FHotLink) then
            ACanvas.Pen.Width := Max(2, Scale(2))
          else
            ACanvas.Pen.Width := 1;
          ACanvas.MoveTo(ALeft + Span.Left, SpanTop + FaceHeight(Span.Face));
          ACanvas.LineTo(ALeft + Span.Right, SpanTop + FaceHeight(Span.Face));
          ACanvas.Pen.Width := 1;
        end;
      end;
    end;
  finally
    RestoreDC(ACanvas.Handle, Saved);
    // RestoreDC wählt die alten Objekte; TCanvas soll Schrift, Stift und Pinsel neu wählen.
    ACanvas.Refresh;
  end;
  // Lage im Text: schmaler Balken rechts neben dem Ausschnitt.
  if CanScroll then
  begin
    Track := FViewport;
    Thumb := Max(Scale(16), MulDiv(Track, FViewport, FLayout.Height));
    ThumbTop := ATop + MulDiv(Track - Thumb, FScroll, Max(1, FLayout.Height - FViewport));
    TAtlasDraw.Thumb(ACanvas, Rect(ALeft + FWidth + Scale(4), ThumbTop, ALeft + FWidth + Scale(7), ThumbTop + Thumb),
      AColors, 0);
  end;
  ACanvas.Brush.Style := bsSolid;
end;

end.
