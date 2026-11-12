unit Atlas.IDE.Editor.Pairs;

// Klammer- und Blockpaare farbig (#514). Die Analyse (TAtlasPairs) läuft je
// Datei einmal, wenn sich der Puffer geändert hat; geprüft wird zu Beginn
// jedes Zeichnens. Gezeichnet wird über OnEditorPaintText: Enthält ein
// Textlauf eine Klammer oder ein Blockwort, zeichnet Atlas den Lauf selbst
// (Pinsel und Schrift hat die IDE vorbereitet), die Paare in der Farbe ihrer
// Tiefe, unpaarige in der Fehlerfarbe. Markierter Text bleibt der IDE.
// Strings und Kommentare zählen nicht (eigener Lexer). Abschaltbar.
// Blocklinien (eigene Einstellung): Nach dem Zeichnen jeder Zeile senkrechte
// Linien der Blöcke über mehrere Zeilen in den Paarfarben, mit Haken an Öffner
// und Schließer; die Strukturhervorhebung der IDE ist dann aus
// (Atlas.IDE.Foundation.StructureSwitch).
// Inaktive {$IFDEF}-Zweige (#615): Text darin zeichnet Atlas in einer
// Farbe zwischen Text und Hintergrund, ganze Zeilen und Teile von Zeilen
// ({$IFDEF X} a {$ENDIF}); die Direktiven selbst bleiben normal. Die Bereiche
// liefert der Server mit den Diagnosen (Tag Unnecessary). Hier statt in einem
// eigenen Notifier, damit nicht zwei Zeichner denselben Lauf übermalen.
// #653: Besitzer-Schlüsselwörter (if, then, else, for, do, procedure …) in der
// Farbe ihres Blocks und Blocklinien ab der Anweisung (Einstellung
// PairOwners); Linienbreite PairGuideWidth (1–3 px bei 100 %, skaliert mit
// Monitor und Zoom). Hell oder dunkel nach dem Hintergrund, den die IDE für
// den Lauf vorbereitet hat (Editor-Farbschema), nicht nach dem IDE-Thema.
// Ausblenden am Element (#628): Klammerfarben, Blocklinien, mitgefärbte
// Anweisungen und ausgegraute Zweige lassen sich je Datei über .atlas
// abschalten („In dieser Datei ausblenden“); was gezeichnet ist, meldet sich
// je Zeile bei TAtlasIdeElements.
// Ungenutzte uses-Einträge (#621, DimUnusedUses) dimmen wie inaktive Zweige,
// mit eigenem Schalter und eigenem Element.
// Lokale Routinen (#1788, NestedRoutines): Farbe aus Tiefe und Verschachtelung der Routine
// (TAtlasRoutineNesting), gestrichelte Linien in eigener Farbe; mit NestedRoutineBand werden die Zeilen
// lokaler Routinen nach dem Zeichnen schwach in ihrer Farbe überblendet.
// Ränder beim Bildlauf: Wo eine Linie am unteren Rand oder unter dem Kopf spitz ausläuft (oder im Rest darunter
// fehlt), hängt der Strich an der Position im Fenster. Verschiebt der Editor beim Bildlauf die gemalten Pixel
// (ScrollDC), wanderten diese Zeilen als Bruchstücke mit. Solche Zeilen werden gemerkt und nach einem Bildlauf
// neu gezeichnet.

interface

uses
  Atlas.Core.Style.Color,
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Pairs,
  Atlas.Core.Editor.RoutineNesting,
  Atlas.Core.Problems.Store;

type
  TAtlasEditorPairs = class
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;
    TLineTokens = TArray<TAtlasPairToken>;
    /// <summary>Blocklinie in einer Zeile; First = Zeile des Öffners, Last = Zeile des Schließers.</summary>
    TLineGuide = record
      Column: Integer;
      Depth: Integer;
      Routine: Integer;
      First: Boolean;
      Last: Boolean;
    end;
    /// <summary>Ein Textlauf mit der Farbe je Zeichen, wie Atlas ihn selbst zeichnet.</summary>
    TPairRun = record
      Rect: TRect;
      Column: Integer;
      Text: string;
      Context: INTACodeEditorPaintContext;
      Line: Integer;
      Original: TColor;
      Colors: TArray<TColor>;
      Unpaired: TArray<Boolean>;
      Dimmed: TArray<Boolean>;
      Found: Boolean;
      Colored: Boolean;
      OwnerColored: Boolean;
      constructor Create(const ARect: TRect; AColumn: Integer; const AText: string;
        const AContext: INTACodeEditorPaintContext);
      /// <summary>Alle Zeichen in AColor.</summary>
      procedure Fill(AColor: TColor);
      /// <summary>Zeichen AIndex in der Farbe des Paars AToken.</summary>
      procedure Mark(AIndex: Integer; const AToken: TAtlasPairToken; const APalette: TAtlasColors;
        const ANesting: TAtlasRoutineNesting);
      /// <summary>Paarfarben mit zu wenig Kontrast zum Hintergrund weichen der Schriftfarbe (#1244).</summary>
      procedure KeepContrast;
      function AnyDimmed: Boolean;
      /// <summary>Lauf zeichnen: Hintergrund wie vorbereitet, Zeichen in fester Zellbreite.</summary>
      procedure Draw(AError: TAtlasColor);
    end;
    /// <summary>Hintergrund des Editors aus dem letzten Lauf; bestimmt hell/dunkel (#653).</summary>
    TBackdrop = record
      Color: TColor;
      Known: Boolean;
      /// <summary>Palette zum Hintergrund des Laufs AContext (merkt ihn sich).</summary>
      function PaletteFor(const AContext: INTACodeEditorPaintContext): TAtlasColors;
      /// <summary>Palette zum zuletzt gemerkten Hintergrund, mit eigenen Paarfarben.</summary>
      function Palette: TAtlasColors;
    end;
    /// <summary>Logische Zeilen (1-basiert), deren Linien beim Zeichnen von der Fensterposition abhingen, und die
    /// oberste Zeile dabei: Nach einem Bildlauf stehen sie verschoben da und werden neu gezeichnet.</summary>
    TEdges = record
      Lines: TArray<Integer>;
      Top: Integer;
      /// <summary>Nach einem Bildlauf die gemerkten Zeilen neu zeichnen lassen.</summary>
      procedure RepaintMoved(const AContext: INTACodeEditorPaintContext);
      /// <summary>Zeile von AContext merken: Ihre Linien hängen an der Fensterposition.</summary>
      procedure Remember(const AContext: INTACodeEditorPaintContext);
    end;
  private
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FFileName: string;
    FText: string;
    FCheck: Boolean;
    // Je 0-basierter Zeile die Paare, Character als 1-basierte Editorspalte (Tabs aufgelöst).
    FLines: TArray<TLineTokens>;
    // Je 0-basierter Zeile der Text wie im Editor (Tabs aufgelöst), zum Abgleich der Läufe.
    FDisplay: TArray<string>;
    // Je 0-basierter Zeile die Blocklinien, die sie kreuzen.
    FGuides: TArray<TArray<TLineGuide>>;
    // Färbung lokaler Routinen beim letzten Refresh (#1788), ihre Bänder und je Zeile das innerste (-1 = keins).
    FNesting: TAtlasRoutineNesting;
    FBands: TArray<TAtlasRoutineBand>;
    FBandOf: TArray<Integer>;
    FTabWidth: Integer;
    // Tabweite für inaktive Bereiche, je Zeichnen einmal gelesen; -1 = noch nicht.
    FDimTabWidth: Integer;
    /// <summary>Was InactiveSpans für die Zeile geliefert hat: inaktive Zweige, ungenutzte uses (#621).</summary>
    FBranchesDimmed: Boolean;
    FUsesDimmed: Boolean;
    // Besitzer mitgefärbt beim letzten Refresh (#653).
    FOwners: Boolean;
    FBackdrop: TBackdrop;
    // Texthöhe der Editorschrift bei 100 %, für die Linienbreite.
    FBaseTextHeight: Integer;
    FEdges: TEdges;
    procedure BeginPaint(const Editor: TWinControl; const ForceFullRepaint: Boolean);
    procedure PaintText(const Rect: TRect; const ColNum: SmallInt; const Text: string;
      const SyntaxCode: TOTASyntaxCode; const Hilight, BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure Refresh(const AContext: INTACodeEditorPaintContext);
    /// <summary>Paare je Zeile aus ATokens, Spalten wie in der IDE.</summary>
    procedure AddTokens(const ALines: TArray<string>; const ATokens: TArray<TAtlasPairToken>);
    /// <summary>Blocklinien je Zeile aus ABlocks.</summary>
    procedure AddGuides(const ALines: TArray<string>; const ABlocks: TArray<TAtlasPairBlock>);
    /// <summary>Inaktive Spalten der Zeile des Laufs (#615); nil ohne oder bei ausgeschalteter Einstellung.</summary>
    function InactiveSpans(const AContext: INTACodeEditorPaintContext): TArray<TAtlasColumnSpan>;
    /// <summary>Gezeichnete Abblendung der Zeile melden (#628): Zweige und uses-Einträge getrennt.</summary>
    procedure ReportDimmed(const AContext: INTACodeEditorPaintContext; ALine: Integer; const ARect: TRect);
    /// <summary>Lauf ARun färben und zeichnen; False = die IDE zeichnet ihn.</summary>
    function ColorRun(var ARun: TPairRun): Boolean;
    /// <summary>Inaktive Teile des Laufs abblenden; True = der ganze Lauf ist inaktiv und schon gezeichnet.</summary>
    function DimRun(var ARun: TPairRun; const ASpans: TArray<TAtlasColumnSpan>): Boolean;
    /// <summary>Klammern und Blockwörter des Laufs in ihrer Paarfarbe.</summary>
    procedure ColorPairs(var ARun: TPairRun; const APalette: TAtlasColors);
    /// <summary>Gezeichnete Elemente des Laufs melden (#628).</summary>
    procedure ReportRun(const ARun: TPairRun; const ASpans: TArray<TAtlasColumnSpan>);
    /// <summary>True, wenn in der Zeile von AContext Blocklinien zu zeichnen sind; ALine und ACode der Zeile.</summary>
    function GuidesLine(const ARect: TRect; const AContext: INTACodeEditorPaintContext; out ALine: Integer;
      out ACode: TRect): Boolean;
    procedure PaintGuides(const ARect: TRect; const AContext: INTACodeEditorPaintContext; ALine: Integer;
      const ACode: TRect);
    /// <summary>Zeile einer lokalen Routine schwach in ihrer Farbe überblenden (#1788).</summary>
    procedure PaintBand(const ARect: TRect; const AContext: INTACodeEditorPaintContext);
    /// <summary>True, wenn die Zeile von AContext zur Analyse passt; ACode ist ihr Codebereich.</summary>
    function LineMatches(const AContext: INTACodeEditorPaintContext; ALine: Integer; out ACode: TRect): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
  end;

implementation

uses
  Atlas.Core.Editor.Guides,
  Atlas.Core.Diagnostics.Guard,
  System.Math,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Diagnostics.Hangs,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorRefresh,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Elements,
  Atlas.Core.Editor.Elements,
  Atlas.IDE.Outline.StickyScroll,
  Atlas.IDE.Problems.Controller;

const
  /// <summary>Mindestkontrast einer Paarfarbe zum Hintergrund der Zeile (#1244); darunter die Farbe der IDE.</summary>
  cMinPairContrast = 3.0;
  /// <summary>Pixel, die die Blocklinie vor Spalte 1 in den Rand ragen darf.</summary>
  cGuideMargin = 4;
  /// <summary>Deckkraft des Bands lokaler Routinen (0–255, #1788): etwa 11 %, der Text bleibt lesbar.</summary>
  cBandAlpha = 28;

type
  /// <summary>Wie eine Blocklinie in einer Zeile endet: als Linie, spitz von oben (unter dem mitlaufenden Kopf),
  /// spitz nach unten (letzte sichtbare Zeile) oder gar nicht (Rest unter der letzten Zeile).</summary>
  TGuideEnd = (geLine, geTaperTop, geTaperBottom, geSkip);

  /// <summary>Strich einer Blocklinie in einer Zeile.</summary>
  TGuideStroke = record
    X: Integer;
    Rect: TRect;
    Width: Integer;
    Color: TAtlasColor;
    Back: TAtlasColor;
    HasBack: Boolean;
    /// <summary>Gestrichelt: Linie einer lokalen Routine in eigener Farbe (#1788).</summary>
    Dashed: Boolean;
  end;

  /// <summary>Was alle Blocklinien einer Zeile gemeinsam haben.</summary>
  TGuidePaint = record
    DC: HDC;
    Rect: TRect;
    Code: TRect;
    Width: Integer;
    Palette: TAtlasColors;
    Opacity: Integer;
    Context: INTACodeEditorPaintContext;
    Covered: Integer;
    Back: TAtlasColor;
    HasBack: Boolean;
    Nesting: TAtlasRoutineNesting;
  end;

{ TAtlasEditorPairs.TEvents }

function TAtlasEditorPairs.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevBeginEndPaintEvents, cevPaintTextEvents, cevPaintLineEvents];
end;

function TAtlasEditorPairs.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

/// <summary>Oberste Zeile der Ansicht beim Zeichnen; 0 ohne Ansicht.</summary>
function TopRowOf(const AContext: INTACodeEditorPaintContext): Integer;
begin
  Result := 0;
  if AContext.EditView <> nil then
  begin
    Result := AContext.EditView.TopRow;
  end;
end;

/// <summary>Bildschirmzeile (0-basiert) von ARect; -1 ohne Höhe.</summary>
function RowIndex(const ARect: TRect): Integer;
begin
  Result := -1;
  if ARect.Height > 0 then
  begin
    Result := (ARect.Top + ARect.Height div 2) div ARect.Height;
  end;
end;

/// <summary>Zeile ARect liegt unter dem mitlaufenden Kopf von AFileName (TAtlasIdeStickyScroll).</summary>
function UnderStickyHeader(const ARect: TRect; const AFileName: string): Boolean;
begin
  Result := (RowIndex(ARect) >= 0) and (RowIndex(ARect) < TAtlasIdeStickyScroll.CoveredRows(AFileName));
end;

/// <summary>Zeichenindex (0-basiert) in ALine als 1-basierte Editorspalte, Tabs aufgelöst.</summary>
function ColumnOf(const ALine: string; ACharacter, ATabWidth: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := 1;
  for mIndex := 1 to ACharacter do
  begin
    if (mIndex <= Length(ALine)) and (ALine[mIndex] = #9) and (ATabWidth > 0) then
    begin
      Result := ((Result - 1) div ATabWidth + 1) * ATabWidth + 1;
    end
    else
    begin
      Inc(Result);
    end;
  end;
end;

/// <summary>Rechteck ARect zu AAlpha/255 mit AColor überblenden (#1788).</summary>
procedure BlendRect(ADC: HDC; const ARect: TRect; AColor: TAtlasColor; AAlpha: Byte);
var
  mMemory: HDC;
  mBitmap, mOld: HGDIOBJ;
  mBlend: TBlendFunction;
begin
  if (ARect.Width <= 0) or (ARect.Height <= 0) then
  begin
    Exit;
  end;
  mMemory := CreateCompatibleDC(ADC);
  try
    mBitmap := CreateCompatibleBitmap(ADC, 1, 1);
    mOld := SelectObject(mMemory, mBitmap);
    try
      SetPixel(mMemory, 0, 0, ColorToRGB(TColor(AColor)));
      mBlend.BlendOp := AC_SRC_OVER;
      mBlend.BlendFlags := 0;
      mBlend.SourceConstantAlpha := AAlpha;
      mBlend.AlphaFormat := 0;
      Winapi.Windows.AlphaBlend(ADC, ARect.Left, ARect.Top, ARect.Width, ARect.Height, mMemory, 0, 0, 1, 1, mBlend);
    finally
      SelectObject(mMemory, mOld);
      DeleteObject(mBitmap);
    end;
  finally
    DeleteDC(mMemory);
  end;
end;

/// <summary>Stift der Blocklinie: durchgezogen oder gestrichelt (lokale Routine in eigener Farbe, #1788).</summary>
function GuidePen(const AStroke: TGuideStroke): HPEN;
var
  mBrush: TLogBrush;
begin
  if not AStroke.Dashed then
  begin
    Exit(CreatePen(PS_SOLID, AStroke.Width, ColorToRGB(TColor(AStroke.Color))));
  end;
  mBrush.lbStyle := BS_SOLID;
  mBrush.lbColor := ColorToRGB(TColor(AStroke.Color));
  mBrush.lbHatch := 0;
  Result := ExtCreatePen(PS_GEOMETRIC or PS_DASH or PS_ENDCAP_FLAT, AStroke.Width, mBrush, 0, nil);
end;

/// <summary>Unpaariges Zeichen in ABack: blassroter Grund mit roter Unterkante, unabhängig von Paarfarben.</summary>
procedure MarkUnpaired(ADC: HDC; const ABack: TRect; AError, ABackground: TAtlasColor);
var
  mBrush: HBRUSH;
  mPen, mOld: HGDIOBJ;
  mY: Integer;
begin
  // Fehlerfarbe zu 25 % über dem Editorhintergrund: deutlich, aber die Klammer bleibt lesbar.
  mBrush := CreateSolidBrush(ColorToRGB(TColor(TAtlasColorMath.Mix(AError, ABackground, 0.25))));
  try
    Winapi.Windows.FillRect(ADC, ABack, mBrush);
  finally
    DeleteObject(mBrush);
  end;
  mPen := CreatePen(PS_SOLID, Max(1, ABack.Height div 8), ColorToRGB(TColor(AError)));
  mOld := SelectObject(ADC, mPen);
  try
    mY := ABack.Bottom - Max(1, ABack.Height div 16) - 1;
    MoveToEx(ADC, ABack.Left, mY, nil);
    LineTo(ADC, ABack.Right, mY);
  finally
    SelectObject(ADC, mOld);
    DeleteObject(mPen);
  end;
end;

/// <summary>Blocklinie über die Zeile, spitz zulaufend (oben, mit ADown unten): je Pixelzeile ein Streifen, der
/// zur Spitze hin auf 1 Pixel schrumpft und (mit bekanntem Hintergrund) in dessen Farbe ausläuft.</summary>
procedure PaintTaper(ADC: HDC; const AStroke: TGuideStroke; ADown: Boolean);
var
  mOffset, mHeight, mThick, mDistance, mLeft: Integer;
  mColor: TAtlasColor;
  mBrush: HBRUSH;
begin
  mHeight := Max(1, AStroke.Rect.Height);
  for mOffset := 0 to mHeight - 1 do
  begin
    // Abstand von der Spitze: oben bzw. unten 0.
    mDistance := mOffset;
    if ADown then
    begin
      mDistance := mHeight - 1 - mOffset;
    end;
    mThick := Max(1, MulDiv(AStroke.Width, mDistance + 1, mHeight));
    mColor := AStroke.Color;
    if AStroke.HasBack then
    begin
      mColor := TAtlasColorMath.Mix(AStroke.Color, AStroke.Back, Sqr((mDistance + 1) / mHeight));
    end;
    mLeft := AStroke.X - (mThick - 1) div 2;
    mBrush := CreateSolidBrush(ColorToRGB(TColor(mColor)));
    try
      FillRect(ADC, TRect.Create(mLeft, AStroke.Rect.Top + mOffset, mLeft + mThick, AStroke.Rect.Top + mOffset + 1),
        mBrush);
    finally
      DeleteObject(mBrush);
    end;
  end;
end;

/// <summary>Blocklinie als Strich, mit Haken an Öffner (oben) und Schließer (unten).</summary>
procedure PaintStroke(ADC: HDC; const AStroke: TGuideStroke; const AGuide: TAtlasEditorPairs.TLineGuide;
  ATick: Integer);
var
  mTop, mBottom: Integer;
  mPen, mOld: HGDIOBJ;
begin
  mTop := AStroke.Rect.Top;
  mBottom := AStroke.Rect.Bottom;
  if AGuide.First then
  begin
    mTop := AStroke.Rect.Top + 2;
  end;
  if AGuide.Last then
  begin
    mBottom := AStroke.Rect.Bottom - 3;
  end;
  mPen := GuidePen(AStroke);
  mOld := SelectObject(ADC, mPen);
  try
    MoveToEx(ADC, AStroke.X, mTop, nil);
    LineTo(ADC, AStroke.X, mBottom + 1);
    if AGuide.First then
    begin
      MoveToEx(ADC, AStroke.X, mTop, nil);
      LineTo(ADC, AStroke.X + ATick, mTop);
    end;
    if AGuide.Last then
    begin
      MoveToEx(ADC, AStroke.X, mBottom, nil);
      LineTo(ADC, AStroke.X + ATick, mBottom);
    end;
  finally
    SelectObject(ADC, mOld);
    DeleteObject(mPen);
  end;
end;

/// <summary>Wie die Blocklinie AGuide in der Zeile von APaint endet.</summary>
function GuideEnd(const APaint: TGuidePaint; const AGuide: TAtlasEditorPairs.TLineGuide): TGuideEnd;
var
  mClient, mHalf: Integer;
begin
  Result := geLine;
  if AGuide.First then
  begin
    Exit;
  end;
  mHalf := APaint.Rect.Height div 2;
  mClient := MaxInt;
  if APaint.Context.EditControl <> nil then
  begin
    mClient := APaint.Context.EditControl.ClientHeight;
  end;
  // Erste Zeile unter dem mitlaufenden Kopf: Ist das Element der Linie dahinter verschwunden und läge ihre
  // Spitze im Text der letzten Kopfzeile, beginnt sie hier spitz und eingeblendet.
  if (RowIndex(APaint.Rect) >= 0) and (RowIndex(APaint.Rect) = APaint.Covered) and
    TAtlasIdeStickyScroll.TaperBelow(APaint.Context.FileName, AGuide.Column) then
  begin
    Result := geTaperTop;
  end
  // Letzte sichtbare Zeile: Läuft die Linie darunter weiter (ihr end ist nicht zu sehen), endet sie hier spitz
  // wie oben unter dem Kopf. Genau eine Zeile läuft aus: die angeschnittene letzte, wenn
  // mindestens die Hälfte zu sehen ist (bis zum Rand), sonst die vorletzte; im Rest darunter dann nichts, sonst
  // begänne die Linie dort wieder breit. Der Rest gilt auch für das Ende der Linie: Steht ihr end dort, lief sie
  // in der Zeile darüber schon aus.
  else if mClient - APaint.Rect.Top < mHalf then
  begin
    Result := geSkip;
  end
  else if not AGuide.Last and (APaint.Rect.Bottom + mHalf > mClient) then
  begin
    Result := geTaperBottom;
  end;
end;

/// <summary>Eine Blocklinie in der Zeile von APaint; liefert, wie sie endet.</summary>
function PaintGuide(const APaint: TGuidePaint; const AGuide: TAtlasEditorPairs.TLineGuide): TGuideEnd;
var
  mCell: TRect;
  mStroke: TGuideStroke;
  mMinX: Integer;
begin
  mCell := APaint.Context.EditorState.GetCharacterPosPx(AGuide.Column, APaint.Context.EditorLineNum);
  mStroke.Rect := APaint.Rect;
  mStroke.Width := APaint.Width;
  mStroke.Back := APaint.Back;
  mStroke.HasBack := APaint.HasBack;
  mStroke.X := mCell.Left - Max(2, mCell.Width div 3) - (APaint.Width - 1) div 2;
  // Blöcke ab Spalte 1 (procedure … end): Linie knapp links vom Text, nicht durch das erste Zeichen.
  mMinX := APaint.Code.Left - cGuideMargin + APaint.Width div 2;
  if (APaint.Code.Right > APaint.Code.Left) and (mStroke.X < mMinX) then
  begin
    mStroke.X := mMinX;
  end;
  // Deckkraft: Linie mit dem Hintergrund gemischt, damit sie zurücktritt.
  mStroke.Color := APaint.Nesting.Color(APaint.Palette, AGuide.Depth, AGuide.Routine);
  mStroke.Dashed := APaint.Nesting.OwnColor(AGuide.Routine);
  if APaint.HasBack and (APaint.Opacity < 100) then
  begin
    mStroke.Color := TAtlasColorMath.Mix(mStroke.Color, APaint.Back, APaint.Opacity / 100);
  end;
  Result := GuideEnd(APaint, AGuide);
  case Result of
    geTaperTop:
      PaintTaper(APaint.DC, mStroke, False);
    geTaperBottom:
      begin
        mStroke.Rect.Bottom := APaint.Rect.Top + Min(APaint.Context.EditControl.ClientHeight - APaint.Rect.Top,
          APaint.Rect.Height);
        PaintTaper(APaint.DC, mStroke, True);
      end;
    geLine:
      PaintStroke(APaint.DC, mStroke, AGuide, Max(3, mCell.Width div 2));
    geSkip:
      begin
        // Rest unter der letzten Zeile: keine Linie.
      end;
  end;
end;

{ TAtlasEditorPairs.TPairRun }

constructor TAtlasEditorPairs.TPairRun.Create(const ARect: TRect; AColumn: Integer; const AText: string;
  const AContext: INTACodeEditorPaintContext);
begin
  Rect := ARect;
  Column := AColumn;
  Text := AText;
  Context := AContext;
  Line := AContext.LogicalLineNum - 1;
  Original := AContext.Canvas.Font.Color;
  Colors := nil;
  SetLength(Colors, Length(AText));
  Unpaired := nil;
  SetLength(Unpaired, Length(AText));
  Dimmed := nil;
  SetLength(Dimmed, Length(AText));
  Found := False;
  Colored := False;
  OwnerColored := False;
  Fill(Original);
end;

procedure TAtlasEditorPairs.TPairRun.Fill(AColor: TColor);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Colors) do
  begin
    Colors[mIndex] := AColor;
  end;
end;

procedure TAtlasEditorPairs.TPairRun.Mark(AIndex: Integer; const AToken: TAtlasPairToken;
  const APalette: TAtlasColors; const ANesting: TAtlasRoutineNesting);
begin
  Found := True;
  if AToken.Owner then
  begin
    OwnerColored := True;
  end
  else
  begin
    Colored := True;
  end;
  if AToken.Unpaired then
  begin
    Colors[AIndex] := TColor(APalette.Error);
    Unpaired[AIndex] := True;
  end
  else
  begin
    Colors[AIndex] := TColor(ANesting.Color(APalette, AToken.Depth, AToken.Routine));
  end;
end;

procedure TAtlasEditorPairs.TPairRun.KeepContrast;
var
  mIndex: Integer;
  mBack: TAtlasColor;
begin
  // Zeilen mit eigenem Hintergrund (Haltepunkt, Ausführungspunkt, Fehlerzeile): Eine Paarfarbe, die dort zu
  // wenig absticht, weicht der Schriftfarbe, die die IDE für die Zeile vorbereitet hat.
  mBack := TAtlasColor(ColorToRGB(Context.Canvas.Brush.Color));
  for mIndex := 0 to High(Colors) do
  begin
    if (Colors[mIndex] <> Original) and not Dimmed[mIndex] and
      (TAtlasColorMath.Contrast(TAtlasColor(ColorToRGB(Colors[mIndex])), mBack) < cMinPairContrast) then
    begin
      Colors[mIndex] := Original;
    end;
  end;
end;

function TAtlasEditorPairs.TPairRun.AnyDimmed: Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to High(Dimmed) do
  begin
    Result := Result or Dimmed[mIndex];
  end;
end;

procedure TAtlasEditorPairs.TPairRun.Draw(AError: TAtlasColor);
var
  mCanvas: TCanvas;
  mCell, mTop, mIndex, mSaved: Integer;
  mDC: HDC;
begin
  // Direkt im DC und mit gesichertem Zustand: Die IDE setzt die Textfarbe nur beim Wechsel des Attributs; eine
  // stehengebliebene Paarfarbe färbte sonst Teile späterer Läufe ein (z. B. nach dem Neuzeichnen unter einem
  // Tooltip).
  mCanvas := Context.Canvas;
  mCell := Context.CellSize.cx;
  if mCell <= 0 then
  begin
    mCell := mCanvas.TextWidth('W');
  end;
  mTop := Rect.Top + (Rect.Height - mCanvas.TextHeight('Wg')) div 2;
  mCanvas.FillRect(Rect);
  mDC := mCanvas.Handle;
  mSaved := SaveDC(mDC);
  try
    SetBkMode(mDC, TRANSPARENT);
    for mIndex := 0 to High(Colors) do
    begin
      if Unpaired[mIndex] then
      begin
        MarkUnpaired(mDC, TRect.Create(Rect.Left + mIndex * mCell, Rect.Top, Rect.Left + (mIndex + 1) * mCell,
          Rect.Bottom), AError, TAtlasColor(ColorToRGB(mCanvas.Brush.Color)));
      end;
      SetTextColor(mDC, ColorToRGB(Colors[mIndex]));
      Winapi.Windows.TextOut(mDC, Rect.Left + mIndex * mCell, mTop, PChar(Text) + mIndex, 1);
    end;
  finally
    RestoreDC(mDC, mSaved);
  end;
end;

{ TAtlasEditorPairs }

constructor TAtlasEditorPairs.Create;
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FDimTabWidth := -1;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorBeginPaint := BeginPaint;
  FEvents.OnEditorPaintText := PaintText;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
end;

destructor TAtlasEditorPairs.Destroy;
var
  mServices: INTACodeEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    mServices.RemoveEditorEventsNotifier(FIndex);
  end;
  FEvents.OnEditorBeginPaint := nil;
  FEvents.OnEditorPaintText := nil;
  FEvents.OnEditorPaintLine := nil;
  FEventsRef := nil;
  inherited Destroy;
end;

procedure TAtlasEditorPairs.BeginPaint(const Editor: TWinControl; const ForceFullRepaint: Boolean);
begin
  // Durch die Sicherung abgeschaltet (#493).
  if TAtlasGuard.Disabled(TAtlasFeature.Pairs) then
  begin
    Exit;
  end;
  try
    FCheck := True;
    FDimTabWidth := -1;
    FBaseTextHeight := 0;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Pairs, E);
  end;
end;

procedure TAtlasEditorPairs.Refresh(const AContext: INTACodeEditorPaintContext);
var
  mView: IOTAEditView;
  mText: string;
  mLines: TArray<string>;
  mBlocks: TArray<TAtlasPairBlock>;
  mIndex: Integer;
  mActivity: IInterface;
  mOwners: Boolean;
  mNesting: TAtlasRoutineNesting;
begin
  FCheck := False;
  mView := AContext.EditView;
  if (mView = nil) or (mView.Buffer = nil) then
  begin
    Exit;
  end;
  mText := TAtlasEditorBuffer.Text(mView.Buffer);
  mOwners := TAtlasIdeSettings.Current.PairOwners and
    not TAtlasIdeElements.FileHidden(TAtlasDrawnElement.PairOwners, AContext.FileName);
  mNesting := TAtlasRoutineNesting.FromSettings(TAtlasIdeSettings.Current);
  if (mText = FText) and SameText(AContext.FileName, FFileName) and (FOwners = mOwners) and
    (FNesting.Style = mNesting.Style) and (FNesting.Band = mNesting.Band) then
  begin
    Exit;
  end;
  FOwners := mOwners;
  FNesting := mNesting;
  mActivity := TAtlasActivity.Scope('Klammerpaare');
  FFileName := AContext.FileName;
  FText := mText;
  mLines := mText.Split([#10]);
  FTabWidth := TAtlasEditorBuffer.TabWidth(mView.Buffer);
  FDisplay := nil;
  SetLength(FDisplay, Length(mLines));
  for mIndex := 0 to High(mLines) do
  begin
    FDisplay[mIndex] := TAtlasPairs.DisplayLine(mLines[mIndex], FTabWidth);
  end;
  AddTokens(mLines, TAtlasPairs.Analyze(mText, mBlocks));
  AddGuides(mLines, mBlocks);
  FBands := FNesting.Bands(mBlocks);
  FBandOf := TAtlasRoutineNesting.BandOfLines(FBands, Length(mLines));
end;

procedure TAtlasEditorPairs.AddTokens(const ALines: TArray<string>; const ATokens: TArray<TAtlasPairToken>);
var
  mToken: TAtlasPairToken;
begin
  FLines := nil;
  SetLength(FLines, Length(ALines));
  for mToken in ATokens do
  begin
    if (mToken.Line <= High(FLines)) and (FOwners or not mToken.Owner) then
    begin
      // Spalte der IDE statt Zeichenindex.
      FLines[mToken.Line] := FLines[mToken.Line] + [mToken];
      FLines[mToken.Line][High(FLines[mToken.Line])].Character :=
        ColumnOf(ALines[mToken.Line], mToken.Character, FTabWidth);
    end;
  end;
end;

procedure TAtlasEditorPairs.AddGuides(const ALines: TArray<string>; const ABlocks: TArray<TAtlasPairBlock>);
var
  mGuide: TAtlasGuide;
  mLineGuide: TLineGuide;
  mLine: Integer;
begin
  FGuides := nil;
  SetLength(FGuides, Length(ALines));
  for mGuide in TAtlasGuides.FromBlocks(ALines, ABlocks, FTabWidth, FOwners) do
  begin
    for mLine := mGuide.FirstLine to mGuide.LastLine do
    begin
      mLineGuide.Column := mGuide.Column;
      mLineGuide.Depth := mGuide.Depth;
      mLineGuide.Routine := mGuide.Routine;
      mLineGuide.First := mLine = mGuide.FirstLine;
      mLineGuide.Last := (mLine = mGuide.LastLine) and not mLineGuide.First;
      FGuides[mLine] := FGuides[mLine] + [mLineGuide];
    end;
  end;
end;

{ TAtlasEditorPairs.TBackdrop }

function TAtlasEditorPairs.TBackdrop.PaletteFor(const AContext: INTACodeEditorPaintContext): TAtlasColors;
begin
  // Der vorbereitete Pinsel ist der Hintergrund des Editor-Farbschemas.
  if (AContext <> nil) and (AContext.Canvas <> nil) then
  begin
    Color := AContext.Canvas.Brush.Color;
    Known := True;
  end;
  Result := Palette;
end;

function TAtlasEditorPairs.TBackdrop.Palette: TAtlasColors;
begin
  if Known then
  begin
    Result := TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(Color)));
  end
  else
  begin
    Result := TAtlasIdeStyle.Colors;
  end;
  Result := TAtlasRoutineNesting.PairPalette(Result, TAtlasIdeSettings.Current);
end;

function TAtlasEditorPairs.InactiveSpans(const AContext: INTACodeEditorPaintContext): TArray<TAtlasColumnSpan>;
var
  mSettings: TAtlasPluginSettings;
  mStore: TAtlasProblemStore;
  mView: IOTAEditView;
  mBranches, mUnusedUses: Boolean;
  mEntrySpans: TArray<TAtlasColumnSpan>;
begin
  Result := nil;
  FBranchesDimmed := False;
  FUsesDimmed := False;
  mSettings := TAtlasIdeSettings.Current;
  mStore := TAtlasProblemsController.Current;
  if not mSettings.Enabled or (mStore = nil) then
  begin
    Exit;
  end;
  // Inaktive Zweige (#615) und ungenutzte uses-Einträge (#621) dimmen gleich, mit eigenem Schalter.
  mBranches := mSettings.InactiveDim and (Length(mStore.Inactive(AContext.FileName)) > 0) and
    not TAtlasIdeElements.FileHidden(TAtlasDrawnElement.InactiveDim, AContext.FileName);
  mUnusedUses := mSettings.DimUnusedUses and (Length(mStore.UnusedUses(AContext.FileName)) > 0) and
    not TAtlasIdeElements.FileHidden(TAtlasDrawnElement.UnusedUses, AContext.FileName);
  if not (mBranches or mUnusedUses) then
  begin
    Exit;
  end;
  if FDimTabWidth < 0 then
  begin
    mView := AContext.EditView;
    if (mView <> nil) and (mView.Buffer <> nil) then
    begin
      FDimTabWidth := TAtlasEditorBuffer.TabWidth(mView.Buffer);
    end
    else
    begin
      FDimTabWidth := 8;
    end;
  end;
  if mBranches then
  begin
    Result := mStore.InactiveSpans(AContext.FileName, AContext.LogicalLineNum - 1, FDimTabWidth);
    FBranchesDimmed := Length(Result) > 0;
  end;
  if mUnusedUses then
  begin
    mEntrySpans := mStore.UsesSpans(AContext.FileName, AContext.LogicalLineNum - 1, FDimTabWidth);
    FUsesDimmed := Length(mEntrySpans) > 0;
    Result := Result + mEntrySpans;
  end;
end;

procedure TAtlasEditorPairs.ReportDimmed(const AContext: INTACodeEditorPaintContext; ALine: Integer;
  const ARect: TRect);
begin
  if FBranchesDimmed then
  begin
    TAtlasIdeElements.Painted(TAtlasIdeElements.Target(TAtlasDrawnElement.InactiveDim, AContext.FileName, ALine, ''),
      ARect, TopRowOf(AContext), ARect.Height);
  end;
  if FUsesDimmed then
  begin
    TAtlasIdeElements.Painted(TAtlasIdeElements.Target(TAtlasDrawnElement.UnusedUses, AContext.FileName, ALine, ''),
      ARect, TopRowOf(AContext), ARect.Height);
  end;
end;

// Die Signatur gibt das Ereignis OnEditorPaintText der Open Tools API vor; die Arbeit macht ColorRun.
// lsp-ignore: metric-parameter-count
procedure TAtlasEditorPairs.PaintText(const Rect: TRect; const ColNum: SmallInt; const Text: string;
  const SyntaxCode: TOTASyntaxCode; const Hilight, BeforeEvent: Boolean; var AllowDefaultPainting: Boolean;
  const Context: INTACodeEditorPaintContext);
var
  mRun: TPairRun;
begin
  // Durch die Sicherung abgeschaltet (#493); markierten Text zeichnet die IDE.
  if TAtlasGuard.Disabled(TAtlasFeature.Pairs) or not BeforeEvent or Hilight or (Text = '') or (Context = nil) then
  begin
    Exit;
  end;
  try
    mRun := TPairRun.Create(Rect, ColNum, Text, Context);
    if ColorRun(mRun) then
    begin
      AllowDefaultPainting := False;
    end;
  except
    // Zeichnen darf die IDE nie stören; die IDE zeichnet dann selbst.
    on E: Exception do
    begin
      AllowDefaultPainting := True;
      TAtlasGuard.Report(TAtlasFeature.Pairs, E);
    end;
  end;
end;

function TAtlasEditorPairs.ColorRun(var ARun: TPairRun): Boolean;
var
  mSpans: TArray<TAtlasColumnSpan>;
  mColorsOn: Boolean;
  mPalette: TAtlasColors;
begin
  Result := False;
  // Inaktive {$IFDEF}-Zweige (#615): ganze Läufe gleich, Teile zeichenweise.
  mSpans := InactiveSpans(ARun.Context);
  mColorsOn := TAtlasIdeSettings.Current.PairColors and
    not TAtlasIdeElements.FileHidden(TAtlasDrawnElement.PairColors, ARun.Context.FileName);
  if (Length(mSpans) = 0) and not mColorsOn then
  begin
    Exit;
  end;
  mPalette := FBackdrop.PaletteFor(ARun.Context);
  if (Length(mSpans) > 0) and DimRun(ARun, mSpans) then
  begin
    Exit(True);
  end;
  if mColorsOn then
  begin
    ColorPairs(ARun, mPalette);
  end;
  if ARun.Found then
  begin
    ARun.KeepContrast;
    ReportRun(ARun, mSpans);
    ARun.Draw(mPalette.Error);
    Result := True;
  end;
end;

function TAtlasEditorPairs.DimRun(var ARun: TPairRun; const ASpans: TArray<TAtlasColumnSpan>): Boolean;
var
  mDim: TColor;
  mLineText: string;
  mIndex: Integer;
begin
  Result := TAtlasColumnSpan.Covers(ASpans, ARun.Column, Length(ARun.Text));
  mDim := TColor(TAtlasColorMath.Mix(TAtlasColor(ColorToRGB(ARun.Context.Canvas.Font.Color)),
    TAtlasColor(ColorToRGB(ARun.Context.Canvas.Brush.Color)), 0.45));
  if Result then
  begin
    ARun.Fill(mDim);
    ARun.Draw(0);
    ReportDimmed(ARun.Context, ARun.Line, ARun.Rect);
    Exit;
  end;
  // Teile einer Zeile nur, wenn der Lauf dort im Text der Diagnosen steht (wie bei den Paaren).
  if (TAtlasProblemsController.Current = nil) or
    not TAtlasProblemsController.Current.LineText(ARun.Context.FileName, ARun.Line, mLineText) or
    not TAtlasPairs.RunMatches(TAtlasPairs.DisplayLine(mLineText, FDimTabWidth), ARun.Text, ARun.Column) then
  begin
    Exit;
  end;
  for mIndex := 0 to High(ARun.Colors) do
  begin
    if TAtlasColumnSpan.Contains(ASpans, ARun.Column + mIndex) then
    begin
      ARun.Colors[mIndex] := mDim;
      ARun.Dimmed[mIndex] := True;
      ARun.Found := True;
    end;
  end;
end;

procedure TAtlasEditorPairs.ColorPairs(var ARun: TPairRun; const APalette: TAtlasColors);
var
  mToken: TAtlasPairToken;
  mColumn, mIndex: Integer;
begin
  if FCheck or not SameText(ARun.Context.FileName, FFileName) then
  begin
    Refresh(ARun.Context);
  end;
  // Nur einfärben, wenn der Lauf in der analysierten Zeile an dieser Stelle steht. Die IDE meldet beim Neuzeichnen
  // von Teilbereichen nicht immer die Zeile des Laufs; sonst landeten Paarfarben mitten in Bezeichnern anderer
  // Zeilen.
  if (ARun.Line < 0) or (ARun.Line > High(FLines)) or (ARun.Line > High(FDisplay)) or
    not TAtlasPairs.RunMatches(FDisplay[ARun.Line], ARun.Text, ARun.Column) then
  begin
    Exit;
  end;
  for mToken in FLines[ARun.Line] do
  begin
    for mColumn := mToken.Character to mToken.Character + mToken.Length - 1 do
    begin
      mIndex := mColumn - ARun.Column;
      if (mIndex >= 0) and (mIndex < Length(ARun.Text)) and not ARun.Dimmed[mIndex] then
      begin
        ARun.Mark(mIndex, mToken, APalette, FNesting);
      end;
    end;
  end;
end;

procedure TAtlasEditorPairs.ReportRun(const ARun: TPairRun; const ASpans: TArray<TAtlasColumnSpan>);
begin
  if ARun.Colored then
  begin
    TAtlasIdeElements.Painted(TAtlasIdeElements.Target(TAtlasDrawnElement.PairColors, ARun.Context.FileName,
      ARun.Line, ''), ARun.Rect, TopRowOf(ARun.Context), ARun.Rect.Height);
  end;
  if ARun.OwnerColored then
  begin
    TAtlasIdeElements.Painted(TAtlasIdeElements.Target(TAtlasDrawnElement.PairOwners, ARun.Context.FileName,
      ARun.Line, ''), ARun.Rect, TopRowOf(ARun.Context), ARun.Rect.Height);
  end;
  if (Length(ASpans) > 0) and ARun.AnyDimmed then
  begin
    ReportDimmed(ARun.Context, ARun.Line, ARun.Rect);
  end;
end;

procedure TAtlasEditorPairs.PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mLine: Integer;
  mCode: TRect;
begin
  // Durch die Sicherung abgeschaltet (#493).
  if TAtlasGuard.Disabled(TAtlasFeature.Pairs) or BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) then
  begin
    Exit;
  end;
  try
    FEdges.RepaintMoved(Context);
    PaintBand(Rect, Context);
    if GuidesLine(Rect, Context, mLine, mCode) then
    begin
      PaintGuides(Rect, Context, mLine, mCode);
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
    begin
      FGuides := nil;
      TAtlasGuard.Report(TAtlasFeature.Pairs, E);
    end;
  end;
end;

function TAtlasEditorPairs.GuidesLine(const ARect: TRect; const AContext: INTACodeEditorPaintContext;
  out ALine: Integer; out ACode: TRect): Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  Result := False;
  ALine := AContext.LogicalLineNum - 1;
  ACode := TRect.Empty;
  mSettings := TAtlasIdeSettings.Current;
  if not (mSettings.PairColors and mSettings.PairGuides) or
    TAtlasIdeElements.FileHidden(TAtlasDrawnElement.PairGuides, AContext.FileName) then
  begin
    Exit;
  end;
  if FCheck or not SameText(AContext.FileName, FFileName) then
  begin
    Refresh(AContext);
  end;
  // Unter dem mitlaufenden Kopf zeichnet der Kopf die Linien selbst, jede erst unter ihrem Element.
  if (ALine < 0) or (ALine > High(FGuides)) or (Length(FGuides[ALine]) = 0) or
    (RowIndex(ARect) >= 0) and (RowIndex(ARect) < TAtlasIdeStickyScroll.CoveredRows(AContext.FileName)) then
  begin
    Exit;
  end;
  Result := LineMatches(AContext, ALine, ACode);
end;

function TAtlasEditorPairs.LineMatches(const AContext: INTACodeEditorPaintContext; ALine: Integer;
  out ACode: TRect): Boolean;
var
  mState: INTACodeEditorLineState;
begin
  // Wie bei den Läufen: nur, wenn die Zeile zur Analyse passt.
  ACode := TRect.Empty;
  mState := AContext.LineState;
  Result := (mState <> nil) and (ALine >= 0) and (ALine <= High(FDisplay)) and
    (TrimRight(TAtlasPairs.DisplayLine(mState.Text, FTabWidth)) = TrimRight(FDisplay[ALine]));
  if Result then
  begin
    ACode := mState.CodeRect;
  end;
end;

procedure TAtlasEditorPairs.PaintBand(const ARect: TRect; const AContext: INTACodeEditorPaintContext);
var
  mSettings: TAtlasPluginSettings;
  mLine: Integer;
  mCode: TRect;
  mBand: TAtlasRoutineBand;
begin
  mSettings := TAtlasIdeSettings.Current;
  if not (mSettings.PairColors and mSettings.NestedRoutineBand) or
    TAtlasIdeElements.FileHidden(TAtlasDrawnElement.PairColors, AContext.FileName) then
  begin
    Exit;
  end;
  if FCheck or not SameText(AContext.FileName, FFileName) then
  begin
    Refresh(AContext);
  end;
  mLine := AContext.LogicalLineNum - 1;
  // Unter dem mitlaufenden Kopf nicht: der Kopf deckt die Zeile ab.
  if (mLine < 0) or (mLine > High(FBandOf)) or (FBandOf[mLine] < 0) or UnderStickyHeader(ARect, AContext.FileName) or
    not LineMatches(AContext, mLine, mCode) then
  begin
    Exit;
  end;
  mBand := FBands[FBandOf[mLine]];
  BlendRect(AContext.Canvas.Handle, TRect.Create(Max(ARect.Left, mCode.Left), ARect.Top, ARect.Right, ARect.Bottom),
    FNesting.Color(FBackdrop.Palette, mBand.Depth, mBand.Routine), cBandAlpha);
end;

procedure TAtlasEditorPairs.PaintGuides(const ARect: TRect; const AContext: INTACodeEditorPaintContext;
  ALine: Integer; const ACode: TRect);
var
  mPaint: TGuidePaint;
  mGuide: TLineGuide;
  mSaved: Integer;
  mEdge: Boolean;
begin
  if FBaseTextHeight <= 0 then
  begin
    FBaseTextHeight := TAtlasIdeStyle.BaseTextHeight;
  end;
  // Hintergrund aus den Textläufen: Beim Zeichnen der Zeile ist der Pinsel nicht sicher der des Editors.
  mPaint.Palette := FBackdrop.Palette;
  mPaint.Rect := ARect;
  mPaint.Code := ACode;
  mPaint.Context := AContext;
  mPaint.Opacity := TAtlasIdeSettings.Current.PairGuideOpacity;
  mPaint.Width := TAtlasGuides.PenWidth(TAtlasIdeSettings.Current.PairGuideWidth, AContext.CellSize.cy,
    FBaseTextHeight);
  mPaint.Covered := TAtlasIdeStickyScroll.CoveredRows(AContext.FileName);
  mPaint.Back := TAtlasColor(ColorToRGB(FBackdrop.Color));
  mPaint.HasBack := FBackdrop.Known;
  mPaint.Nesting := FNesting;
  mPaint.DC := AContext.Canvas.Handle;
  mSaved := SaveDC(mPaint.DC);
  try
    // Nicht in den Rand zeichnen; nur die Linie vor Spalte 1 darf ein paar Pixel hineinragen.
    if ACode.Right > ACode.Left then
    begin
      IntersectClipRect(mPaint.DC, ACode.Left - cGuideMargin, ARect.Top, ARect.Right, ARect.Bottom);
    end;
    mEdge := False;
    for mGuide in FGuides[ALine] do
    begin
      mEdge := (PaintGuide(mPaint, mGuide) <> geLine) or mEdge;
    end;
    if mEdge then
    begin
      FEdges.Remember(AContext);
    end;
  finally
    RestoreDC(mPaint.DC, mSaved);
  end;
  TAtlasIdeElements.Painted(TAtlasIdeElements.Target(TAtlasDrawnElement.PairGuides, AContext.FileName, ALine, ''),
    ACode, TopRowOf(AContext), ARect.Height);
end;

{ TAtlasEditorPairs.TEdges }

procedure TAtlasEditorPairs.TEdges.RepaintMoved(const AContext: INTACodeEditorPaintContext);
var
  mServices: INTACodeEditorServices;
  mLine: Integer;
begin
  if (Length(Lines) = 0) or (TopRowOf(AContext) = Top) then
  begin
    Exit;
  end;
  // Danach leeren: Die neu gezeichneten Zeilen merken sich mit der neuen obersten Zeile selbst wieder.
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    for mLine in Lines do
    begin
      TAtlasIdeEditorRefresh.InvalidateTopLine(mServices, mLine);
    end;
  end;
  Lines := nil;
end;

procedure TAtlasEditorPairs.TEdges.Remember(const AContext: INTACodeEditorPaintContext);
var
  mLine: Integer;
begin
  if TopRowOf(AContext) <> Top then
  begin
    Lines := nil;
    Top := TopRowOf(AContext);
  end;
  for mLine in Lines do
  begin
    if mLine = AContext.LogicalLineNum then
    begin
      Exit;
    end;
  end;
  Lines := Lines + [AContext.LogicalLineNum];
end;

end.
