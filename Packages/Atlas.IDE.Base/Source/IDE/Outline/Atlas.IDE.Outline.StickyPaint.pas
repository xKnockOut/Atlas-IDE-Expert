unit Atlas.IDE.Outline.StickyPaint;

// Zeichenhilfen des mitlaufenden Kopfs (#506) im Editor: Farbschema des
// Editors aus der Registrierung lesen (#1245), Kopfzeile füllen, Text in
// Läufen gleicher Farbe und Schrift zeichnen, Paarfarben (#1229) und
// Blocklinien im Kopf (Haken, eingeblendete Spitze). Welche Zeilen der Kopf
// zeigt und wann er neu zeichnet, entscheiden Atlas.Core.Outline.StickyScroll
// und Atlas.Core.Editor.StickyPlan; Zustand und Ereignisse bleiben in
// Atlas.IDE.Outline.StickyScroll. Nur im Hauptthread.

interface

uses
  Winapi.Windows,
  System.Types,
  Vcl.Graphics,
  ToolsAPI.Editor,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Outline.StickyScroll,
  Atlas.Core.Editor.Pairs,
  Atlas.Core.Editor.Guides,
  Atlas.Core.Editor.RoutineNesting;

type
  /// <summary>Darstellung eines Elements aus dem Farbschema des Editors.</summary>
  TAtlasStickySyntaxStyle = record
    Color: TColor;
    /// <summary>False: Vorgabefarbe des Editors (Default Foreground), dann die Textfarbe des Kopfs.</summary>
    HasColor: Boolean;
    Style: TFontStyles;
  end;

  /// <summary>Was alle Blocklinien einer Kopfzeile teilen: Gerät, Zeile, Codebereich, Stiftbreite, Farben.</summary>
  TAtlasStickyGuidePaint = record
    Context: INTACodeEditorPaintContext;
    DC: HDC;
    Rect: TRect;
    Code: TRect;
    Width: Integer;
    Opacity: Integer;
    Colors: TAtlasColors;
    Back: TAtlasColor;
    /// <summary>Hintergrund des Kopfs: Dort beginnt die Spitze eingeblendeter Linien.</summary>
    HeadBack: TAtlasColor;
    /// <summary>Färbung lokaler Routinen wie im Editor (#1788).</summary>
    Nesting: TAtlasRoutineNesting;
  end;

  /// <summary>Werkzeuge der Leinwand, vor dem Zeichnen gesichert und danach zurückgesetzt.</summary>
  TAtlasStickySavedTools = record
    Font: TFont;
    Brush: TBrush;
    Pen: TPen;
    class function Save(ACanvas: TCanvas): TAtlasStickySavedTools; static;
    /// <summary>Zurücksetzen und die Sicherung freigeben.</summary>
    procedure Restore(ACanvas: TCanvas);
  end;

  TAtlasStickySyntaxStyles = array[TAtlasStickySyntax] of TAtlasStickySyntaxStyle;

  TAtlasStickyPaint = record
  public
    /// <summary>Hintergrund des Kopfs: der des Editors, eine Spur zur Schrift hin (leichte Abgrenzung).</summary>
    class function HeaderBack(const AColors: TAtlasColors; ABack: TAtlasColor): TAtlasColor; static;
    /// <summary>Ohne Zeilenzustand, Ansicht oder Puffer gibt es keine Blocklinien.</summary>
    class function NoEditor(const AContext: INTACodeEditorPaintContext): Boolean; static;
    class function GuidePaintOf(const AContext: INTACodeEditorPaintContext; const ARect: TRect; ABack: TAtlasColor;
      const ASettings: TAtlasPluginSettings): TAtlasStickyGuidePaint; static;
    class function GuideColor(const APaint: TAtlasStickyGuidePaint; const AGuide: TAtlasGuide): TAtlasColor; static;
    /// <summary>Spitz nach oben: je Pixelzeile ein Streifen, der von 1 Pixel auf die Stiftbreite wächst und von der
    /// Kopffarbe zur Linienfarbe übergeht; bei 1–2 Pixel Stiftbreite sieht man die Spitze sonst nicht.</summary>
    class procedure DrawFade(const APaint: TAtlasStickyGuidePaint; AX: Integer; AColor: TAtlasColor); static;
    /// <summary>Senkrechter Strich bei AX durch die Zeile; mit AHook > 0 beginnt er oben mit einem Haken dieser
    /// Länge (Kopfzeile des Elements).</summary>
    class procedure DrawStroke(const APaint: TAtlasStickyGuidePaint; AX, AHook: Integer; AColor: TAtlasColor); static;
    /// <summary>Farbschema des Editors (Farbe, fett, kursiv) je Zeichen von AText.</summary>
    class procedure ApplySyntax(const AText: string; const ASyntax: TAtlasStickySyntaxStyles;
      var AColors: TArray<TColor>; var AStyles: TArray<TFontStyles>); static;
    class function SpanColor(const ASpan: TAtlasPairSpan; const APairs: TAtlasColors;
      const ANesting: TAtlasRoutineNesting): TColor; static;
    /// <summary>Paarfarben ersetzen die Farbe des Farbschemas; fett und kursiv bleiben.</summary>
    class procedure ApplySpans(const ASpans: TArray<TAtlasPairSpan>; const APairs: TAtlasColors;
      var AColors: TArray<TColor>); static;
    /// <summary>AText ab AX in Läufen gleicher Farbe und Schrift am Stück.</summary>
    class procedure DrawRuns(ACanvas: TCanvas; AX, ATop: Integer; const AText: string; const AColors: TArray<TColor>;
      const AStyles: TArray<TFontStyles>); static;
    /// <summary>Linker Rand des Codebereichs, sonst der der Zeile.</summary>
    class function CodeLeftOf(const AContext: INTACodeEditorPaintContext; const ARect: TRect): Integer; static;
    /// <summary>Hintergrund der Kopfzeile in AArea, Schrift für Text oder (ASummary) Zusammenfassung.</summary>
    class procedure FillRow(ACanvas: TCanvas; const AArea: TRect; const AColors: TAtlasColors; ABack: TAtlasColor;
      ASummary: Boolean); static;
    /// <summary>Trennlinie unter der letzten Kopfzeile.</summary>
    class procedure DrawSeparator(ACanvas: TCanvas; const AArea: TRect; const AColors: TAtlasColors); static;
    /// <summary>Farbschema des Editors je Art (Editor\Highlight) nach AStyles; Hintergrund (Plain text) nach ABack,
    /// ABackKnown sagt, ob er gilt. Ohne IOTAServices bleiben ABack und ABackKnown unverändert.</summary>
    class procedure ReadSyntax(var AStyles: TAtlasStickySyntaxStyles; var ABack: TAtlasColor;
      var ABackKnown: Boolean); static;
    /// <summary>Paarfarben der Kopfzeile in der Palette lokaler Routinen nach den Einstellungen (#1229, #1788).
    /// </summary>
    class procedure ApplyPairSpans(const ASpans: TArray<TAtlasPairSpan>; const AColors: TAtlasColors;
      var ACharColors: TArray<TColor>); static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.Win.Registry,
  ToolsAPI,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings;

const
  /// <summary>Namen im Farbschema des Editors (Editor\Highlight\…), wie die IDE sie schreibt.</summary>
  cRegTrue = 'True';
  cRegBold = 'Bold';
  cRegItalic = 'Italic';
  cRegForeground = 'Foreground Color New';
  cRegDefaultForeground = 'Default Foreground';
  cRegBackground = 'Background Color New';
  cRegDefaultBackground = 'Default Background';
  cRegHighlight = '\Editor\Highlight\';
  cRegPlainText = 'Plain text';
  /// <summary>Anteil der Schrift im Hintergrund des Kopfs (leichte Abgrenzung zum Editor).</summary>
  cHeaderTint = 0.04;

{ TAtlasStickySavedTools }

class function TAtlasStickySavedTools.Save(ACanvas: TCanvas): TAtlasStickySavedTools;
begin
  Result.Font := TFont.Create;
  Result.Brush := TBrush.Create;
  Result.Pen := TPen.Create;
  Result.Font.Assign(ACanvas.Font);
  Result.Brush.Assign(ACanvas.Brush);
  Result.Pen.Assign(ACanvas.Pen);
end;

procedure TAtlasStickySavedTools.Restore(ACanvas: TCanvas);
begin
  ACanvas.Font.Assign(Font); ACanvas.Brush.Assign(Brush); ACanvas.Pen.Assign(Pen);
  Pen.Free;
  Brush.Free;
  Font.Free;
end;

function RegistryTrue(ARegistry: TRegistry; const AName: string): Boolean;
begin
  Result := ARegistry.ValueExists(AName) and SameText(ARegistry.ReadString(AName), cRegTrue);
end;

function ReadStyle(ARegistry: TRegistry; const AKey: string): TAtlasStickySyntaxStyle;
begin
  Result := Default(TAtlasStickySyntaxStyle);
  try
    if not ARegistry.OpenKeyReadOnly(AKey) then
    begin
      Exit;
    end;
    if RegistryTrue(ARegistry, cRegBold) then
    begin
      Include(Result.Style, fsBold);
    end;
    if RegistryTrue(ARegistry, cRegItalic) then
    begin
      Include(Result.Style, fsItalic);
    end;
    // „$00BCE0FF“ oder „clMaroon“; mit Default Foreground die Vorgabefarbe des Editors.
    if ARegistry.ValueExists(cRegForeground) and not RegistryTrue(ARegistry, cRegDefaultForeground) then
    begin
      Result.Color := StringToColor(ARegistry.ReadString(cRegForeground));
      Result.HasColor := True;
    end;
    ARegistry.CloseKey;
  except
    // Unlesbarer Eintrag: diese Art ohne Hervorhebung.
    on Exception do
      Result := Default(TAtlasStickySyntaxStyle);
  end;
end;

function ReadSchemeBack(ARegistry: TRegistry; const AKey: string; out ABack: TAtlasColor): Boolean;
begin
  Result := False;
  ABack := Default(TAtlasColor);
  try
    if not ARegistry.OpenKeyReadOnly(AKey) then
    begin
      Exit;
    end;
    if ARegistry.ValueExists(cRegBackground) and not RegistryTrue(ARegistry, cRegDefaultBackground) then
    begin
      ABack := TAtlasColor(ColorToRGB(StringToColor(ARegistry.ReadString(cRegBackground))));
      Result := True;
    end;
    ARegistry.CloseKey;
  except
    on Exception do
      Result := False;
  end;
end;

{ TAtlasStickyPaint }

class function TAtlasStickyPaint.HeaderBack(const AColors: TAtlasColors; ABack: TAtlasColor): TAtlasColor;
begin
  Result := TAtlasColorMath.Mix(AColors.Text, ABack, cHeaderTint);
end;

class function TAtlasStickyPaint.NoEditor(const AContext: INTACodeEditorPaintContext): Boolean;
begin
  Result := (AContext.LineState = nil) or (AContext.EditView = nil) or (AContext.EditView.Buffer = nil);
end;

class function TAtlasStickyPaint.GuidePaintOf(const AContext: INTACodeEditorPaintContext; const ARect: TRect;
  ABack: TAtlasColor; const ASettings: TAtlasPluginSettings): TAtlasStickyGuidePaint;
begin
  Result.Context := AContext;
  Result.DC := AContext.Canvas.Handle;
  Result.Rect := ARect;
  Result.Code := AContext.LineState.CodeRect;
  Result.Width := TAtlasGuides.PenWidth(ASettings.PairGuideWidth, AContext.CellSize.cy,
    TAtlasIdeStyle.BaseTextHeight);
  Result.Opacity := ASettings.PairGuideOpacity;
  Result.Back := ABack;
  Result.Colors := TAtlasColors.ForBackground(ABack);
  // Die Spitze eingeblendeter Linien beginnt in der Farbe des Kopfs.
  Result.HeadBack := HeaderBack(Result.Colors, ABack);
  Result.Colors := TAtlasRoutineNesting.PairPalette(Result.Colors, ASettings);
  Result.Nesting := TAtlasRoutineNesting.FromSettings(ASettings);
end;

class function TAtlasStickyPaint.GuideColor(const APaint: TAtlasStickyGuidePaint;
  const AGuide: TAtlasGuide): TAtlasColor;
begin
  Result := APaint.Nesting.Color(APaint.Colors, AGuide.Depth, AGuide.Routine);
  if APaint.Opacity < 100 then
  begin
    Result := TAtlasColorMath.Mix(Result, APaint.Back, APaint.Opacity / 100);
  end;
end;

class procedure TAtlasStickyPaint.DrawFade(const APaint: TAtlasStickyGuidePaint; AX: Integer; AColor: TAtlasColor);
var
  mFadeHeight, mOffset, mThick: Integer;
  mStep: TRect;
  mBrush: HBRUSH;
begin
  mFadeHeight := APaint.Rect.Height - 2;
  for mOffset := 0 to mFadeHeight - 1 do
  begin
    mThick := Max(1, MulDiv(APaint.Width, mOffset + 1, mFadeHeight));
    mStep := TRect.Create(AX - (mThick - 1) div 2, APaint.Rect.Bottom - mFadeHeight + mOffset,
      AX - (mThick - 1) div 2 + mThick, APaint.Rect.Bottom - mFadeHeight + mOffset + 1);
    mBrush := CreateSolidBrush(ColorToRGB(TColor(TAtlasColorMath.Mix(AColor, APaint.HeadBack,
      TAtlasStickyScroll.FadeWeight(mOffset, mFadeHeight)))));
    try
      FillRect(APaint.DC, mStep, mBrush);
    finally
      DeleteObject(mBrush);
    end;
  end;
end;

class procedure TAtlasStickyPaint.DrawStroke(const APaint: TAtlasStickyGuidePaint; AX, AHook: Integer;
  AColor: TAtlasColor);
var
  mPen, mOld: HGDIOBJ;
  mTop: Integer;
begin
  mPen := CreatePen(PS_SOLID, APaint.Width, ColorToRGB(TColor(AColor)));
  mOld := SelectObject(APaint.DC, mPen);
  try
    mTop := APaint.Rect.Top;
    if AHook > 0 then
    begin
      mTop := mTop + 2;
    end;
    MoveToEx(APaint.DC, AX, mTop, nil);
    LineTo(APaint.DC, AX, APaint.Rect.Bottom);
    if AHook > 0 then
    begin
      MoveToEx(APaint.DC, AX, mTop, nil);
      LineTo(APaint.DC, AX + AHook, mTop);
    end;
  finally
    SelectObject(APaint.DC, mOld);
    DeleteObject(mPen);
  end;
end;

class procedure TAtlasStickyPaint.ApplySyntax(const AText: string; const ASyntax: TAtlasStickySyntaxStyles;
  var AColors: TArray<TColor>; var AStyles: TArray<TFontStyles>);
var
  mToken: TAtlasStickyToken;
  mStyle: TAtlasStickySyntaxStyle;
  mIndex: Integer;
begin
  for mToken in TAtlasStickyScroll.Syntax(AText) do
  begin
    mStyle := ASyntax[mToken.Kind];
    for mIndex := mToken.Start - 1 to Min(High(AColors), mToken.Start + mToken.Length - 2) do
    begin
      if mStyle.HasColor then
      begin
        AColors[mIndex] := mStyle.Color;
      end;
      AStyles[mIndex] := mStyle.Style;
    end;
  end;
end;

class function TAtlasStickyPaint.SpanColor(const ASpan: TAtlasPairSpan; const APairs: TAtlasColors;
  const ANesting: TAtlasRoutineNesting): TColor;
begin
  if ASpan.Unpaired then
  begin
    Result := TColor(APairs.Error);
  end
  else
  begin
    Result := TColor(ANesting.Color(APairs, ASpan.Depth, ASpan.Routine));
  end;
end;

class procedure TAtlasStickyPaint.ApplySpans(const ASpans: TArray<TAtlasPairSpan>; const APairs: TAtlasColors;
  var AColors: TArray<TColor>);
var
  mSpan: TAtlasPairSpan;
  mIndex: Integer;
  mNesting: TAtlasRoutineNesting;
begin
  mNesting := TAtlasRoutineNesting.FromSettings(TAtlasIdeSettings.Current);
  for mSpan in ASpans do
  begin
    for mIndex := mSpan.Start - 1 to Min(High(AColors), mSpan.Start + mSpan.Length - 2) do
    begin
      AColors[mIndex] := SpanColor(mSpan, APairs, mNesting);
    end;
  end;
end;

class procedure TAtlasStickyPaint.DrawRuns(ACanvas: TCanvas; AX, ATop: Integer; const AText: string;
  const AColors: TArray<TColor>; const AStyles: TArray<TFontStyles>);
var
  mIndex, mStop: Integer;
  mPart: string;
begin
  mIndex := 0;
  while mIndex <= High(AColors) do
  begin
    mStop := mIndex;
    while (mStop < High(AColors)) and (AColors[mStop + 1] = AColors[mIndex]) and
      (AStyles[mStop + 1] = AStyles[mIndex]) do
    begin
      Inc(mStop);
    end;
    mPart := Copy(AText, mIndex + 1, mStop - mIndex + 1);
    ACanvas.Font.Color := AColors[mIndex]; ACanvas.Font.Style := AStyles[mIndex]; ACanvas.TextOut(AX, ATop, mPart);
    Inc(AX, ACanvas.TextWidth(mPart));
    mIndex := mStop + 1;
  end;
end;

class function TAtlasStickyPaint.CodeLeftOf(const AContext: INTACodeEditorPaintContext; const ARect: TRect): Integer;
var
  mCode: TRect;
begin
  Result := ARect.Left;
  if AContext.LineState = nil then
  begin
    Exit;
  end;
  mCode := AContext.LineState.CodeRect;
  if mCode.Right > mCode.Left then
  begin
    Result := mCode.Left;
  end;
end;

class procedure TAtlasStickyPaint.FillRow(ACanvas: TCanvas; const AArea: TRect; const AColors: TAtlasColors;
  ABack: TAtlasColor; ASummary: Boolean);
begin
  ACanvas.Brush.Style := bsSolid; ACanvas.Brush.Color := TColor(HeaderBack(AColors, ABack)); ACanvas.FillRect(AArea);
  ACanvas.Brush.Style := bsClear; ACanvas.Font.Style := [];
  if ASummary then
  begin
    ACanvas.Font.Color := TColor(AColors.Muted);
  end
  else
  begin
    ACanvas.Font.Color := TColor(AColors.Text);
  end;
end;

class procedure TAtlasStickyPaint.DrawSeparator(ACanvas: TCanvas; const AArea: TRect; const AColors: TAtlasColors);
begin
  ACanvas.Pen.Style := psSolid; ACanvas.Pen.Width := 1; ACanvas.Pen.Color := TColor(AColors.Line);
  ACanvas.MoveTo(AArea.Left, AArea.Bottom - 1); ACanvas.LineTo(AArea.Right, AArea.Bottom - 1);
end;

class procedure TAtlasStickyPaint.ReadSyntax(var AStyles: TAtlasStickySyntaxStyles; var ABack: TAtlasColor;
  var ABackKnown: Boolean);
const
  cElements: array[TAtlasStickySyntax] of string = ('Whitespace', 'Reserved word', 'Identifier', 'Number', 'String',
    'Character', 'Comment', 'Symbol', 'Preprocessor');
var
  mServices: IOTAServices;
  mRegistry: TRegistry;
  mKind: TAtlasStickySyntax;
  mBase: string;
  mBack: TAtlasColor;
begin
  for mKind := Low(TAtlasStickySyntax) to High(TAtlasStickySyntax) do
  begin
    AStyles[mKind] := Default(TAtlasStickySyntaxStyle);
  end;
  if not Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    Exit;
  end;
  mBase := mServices.GetBaseRegistryKey + cRegHighlight;
  mRegistry := TRegistry.Create(KEY_READ);
  try
    mRegistry.RootKey := HKEY_CURRENT_USER;
    for mKind := Low(TAtlasStickySyntax) to High(TAtlasStickySyntax) do
    begin
      AStyles[mKind] := ReadStyle(mRegistry, mBase + cElements[mKind]);
    end;
    ABackKnown := ReadSchemeBack(mRegistry, mBase + cRegPlainText, mBack);
    if ABackKnown then
    begin
      ABack := mBack;
    end;
  finally
    mRegistry.Free;
  end;
end;

class procedure TAtlasStickyPaint.ApplyPairSpans(const ASpans: TArray<TAtlasPairSpan>; const AColors: TAtlasColors;
  var ACharColors: TArray<TColor>);
begin
  ApplySpans(ASpans, TAtlasRoutineNesting.PairPalette(AColors, TAtlasIdeSettings.Current), ACharColors);
end;

end.
