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

interface

uses
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
  Atlas.Core.Editor.Guides,
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
    TGuidePart = (gpFirst, gpMiddle, gpLast);
    TLineGuide = record
      Column: Integer;
      Depth: Integer;
      Part: TGuidePart;
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
    FTabWidth: Integer;
    // Tabweite für inaktive Bereiche, je Zeichnen einmal gelesen; -1 = noch nicht.
    FDimTabWidth: Integer;
    /// <summary>Was InactiveSpans für die Zeile geliefert hat: inaktive Zweige, ungenutzte uses (#621).</summary>
    FBranchesDimmed: Boolean;
    FUsesDimmed: Boolean;
    // Besitzer mitgefärbt beim letzten Refresh (#653).
    FOwners: Boolean;
    // Hintergrund des Editors aus dem letzten Lauf; bestimmt hell/dunkel (#653).
    FBackground: TColor;
    FHasBackground: Boolean;
    // Texthöhe der Editorschrift bei 100 %, für die Linienbreite.
    FBaseTextHeight: Integer;
    function PaletteFor(const AContext: INTACodeEditorPaintContext): TAtlasColors;
    class function WithCustomPairs(const AColors: TAtlasColors): TAtlasColors; static;
    procedure BeginPaint(const Editor: TWinControl; const ForceFullRepaint: Boolean);
    procedure PaintText(const Rect: TRect; const ColNum: SmallInt; const Text: string;
      const SyntaxCode: TOTASyntaxCode; const Hilight, BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure Refresh(const Context: INTACodeEditorPaintContext);
    /// <summary>Inaktive Spalten der Zeile des Laufs (#615); nil ohne oder bei ausgeschalteter Einstellung.</summary>
    function InactiveSpans(const Context: INTACodeEditorPaintContext): TArray<TAtlasColumnSpan>;
    /// <summary>Gezeichnete Abblendung der Zeile melden (#628): Zweige und uses-Einträge getrennt.</summary>
    procedure ReportDimmed(const Context: INTACodeEditorPaintContext; ALine: Integer; const ARect: TRect);
    /// <summary>Lauf in einer Farbe selbst zeichnen (Hintergrund wie vorbereitet).</summary>
    class procedure PaintRun(const ARect: TRect; const AText: string; const AContext: INTACodeEditorPaintContext;
      AColor: TColor); static;
  public
    constructor Create;
    destructor Destroy; override;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  System.Math,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Color,
  Atlas.Core.Diagnostics.Hangs,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Elements,
  Atlas.Core.Editor.Elements,
  Atlas.IDE.Outline.StickyScroll,
  Atlas.IDE.Problems.Controller;

const
  /// <summary>Mindestkontrast einer Paarfarbe zum Hintergrund der Zeile (#1244); darunter die Farbe der IDE.</summary>
  MinPairContrast = 3.0;

{ TAtlasEditorPairs.TEvents }

function TAtlasEditorPairs.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevBeginEndPaintEvents, cevPaintTextEvents, cevPaintLineEvents];
end;

function TAtlasEditorPairs.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasEditorPairs }

constructor TAtlasEditorPairs.Create;
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FDimTabWidth := -1;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorBeginPaint := BeginPaint;
  FEvents.OnEditorPaintText := PaintText;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
end;

destructor TAtlasEditorPairs.Destroy;
var
  Services: INTACodeEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.RemoveEditorEventsNotifier(FIndex);
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
    Exit;
  try
    FCheck := True;
    FDimTabWidth := -1;
    FBaseTextHeight := 0;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Pairs, E);
  end;
end;

/// <summary>Oberste Zeile der Ansicht beim Zeichnen; 0 ohne Ansicht.</summary>
function TopRowOf(const AContext: INTACodeEditorPaintContext): Integer;
begin
  Result := 0;
  if AContext.EditView <> nil then
    Result := AContext.EditView.TopRow;
end;

/// <summary>Zeichenindex (0-basiert) in ALine als 1-basierte Editorspalte, Tabs aufgelöst.</summary>
function ColumnOf(const ALine: string; ACharacter, ATabWidth: Integer): Integer;
var
  Index: Integer;
begin
  Result := 1;
  for Index := 1 to ACharacter do
    if (Index <= Length(ALine)) and (ALine[Index] = #9) and (ATabWidth > 0) then
      Result := ((Result - 1) div ATabWidth + 1) * ATabWidth + 1
    else
      Inc(Result);
end;

procedure TAtlasEditorPairs.Refresh(const Context: INTACodeEditorPaintContext);
var
  View: IOTAEditView;
  Text: string;
  Lines: TArray<string>;
  Token: TAtlasPairToken;
  Blocks: TArray<TAtlasPairBlock>;
  Guide: TAtlasGuide;
  LineGuide: TLineGuide;
  TabWidth, Index, Line: Integer;
  Activity: IInterface;
  Owners: Boolean;
begin
  FCheck := False;
  View := Context.EditView;
  if (View = nil) or (View.Buffer = nil) then
    Exit;
  Text := TAtlasEditorBuffer.Text(View.Buffer);
  Owners := TAtlasIdeSettings.Current.PairOwners and
    not TAtlasIdeElements.FileHidden(TAtlasDrawnElement.PairOwners, Context.FileName);
  if (Text = FText) and SameText(Context.FileName, FFileName) and (FOwners = Owners) then
    Exit;
  FOwners := Owners;
  Activity := TAtlasActivity.Scope('Klammerpaare');
  FFileName := Context.FileName;
  FText := Text;
  Lines := Text.Split([#10]);
  FLines := nil;
  SetLength(FLines, Length(Lines));
  SetLength(FDisplay, Length(Lines));
  FGuides := nil;
  SetLength(FGuides, Length(Lines));
  TabWidth := TAtlasEditorBuffer.TabWidth(View.Buffer);
  FTabWidth := TabWidth;
  for Index := 0 to High(Lines) do
    FDisplay[Index] := TAtlasPairs.DisplayLine(Lines[Index], TabWidth);
  for Token in TAtlasPairs.Analyze(Text, Blocks) do
    if (Token.Line <= High(FLines)) and (FOwners or not Token.Owner) then
    begin
      // Spalte der IDE statt Zeichenindex.
      FLines[Token.Line] := FLines[Token.Line] + [Token];
      FLines[Token.Line][High(FLines[Token.Line])].Character := ColumnOf(Lines[Token.Line], Token.Character, TabWidth);
    end;
  for Guide in TAtlasGuides.FromBlocks(Lines, Blocks, TabWidth, FOwners) do
    for Line := Guide.FirstLine to Guide.LastLine do
    begin
      LineGuide.Column := Guide.Column;
      LineGuide.Depth := Guide.Depth;
      if Line = Guide.FirstLine then
        LineGuide.Part := gpFirst
      else if Line = Guide.LastLine then
        LineGuide.Part := gpLast
      else
        LineGuide.Part := gpMiddle;
      FGuides[Line] := FGuides[Line] + [LineGuide];
    end;
end;

function TAtlasEditorPairs.PaletteFor(const AContext: INTACodeEditorPaintContext): TAtlasColors;
begin
  // Der vorbereitete Pinsel ist der Hintergrund des Editor-Farbschemas.
  if (AContext <> nil) and (AContext.Canvas <> nil) then
  begin
    FBackground := AContext.Canvas.Brush.Color;
    FHasBackground := True;
  end;
  if FHasBackground then
    Result := TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(FBackground)))
  else
    Result := TAtlasIdeStyle.Colors;
  Result := WithCustomPairs(Result);
end;

class function TAtlasEditorPairs.WithCustomPairs(const AColors: TAtlasColors): TAtlasColors;
var
  Settings: TAtlasPluginSettings;
begin
  // Eigene Paarfarben je Thema aus den Optionen.
  Settings := TAtlasIdeSettings.Current;
  if AColors.IsDark then
    Result := AColors.WithPairs(Settings.PairColorsDark)
  else
    Result := AColors.WithPairs(Settings.PairColorsLight);
end;

function TAtlasEditorPairs.InactiveSpans(const Context: INTACodeEditorPaintContext): TArray<TAtlasColumnSpan>;
var
  Settings: TAtlasPluginSettings;
  Store: TAtlasProblemStore;
  View: IOTAEditView;
  Branches, UnusedUses: Boolean;
  EntrySpans: TArray<TAtlasColumnSpan>;
begin
  Result := nil;
  FBranchesDimmed := False;
  FUsesDimmed := False;
  Settings := TAtlasIdeSettings.Current;
  Store := TAtlasProblemsController.Current;
  if not Settings.Enabled or (Store = nil) then
    Exit;
  // Inaktive Zweige (#615) und ungenutzte uses-Einträge (#621) dimmen gleich, mit eigenem Schalter.
  Branches := Settings.InactiveDim and (Length(Store.Inactive(Context.FileName)) > 0) and
    not TAtlasIdeElements.FileHidden(TAtlasDrawnElement.InactiveDim, Context.FileName);
  UnusedUses := Settings.DimUnusedUses and (Length(Store.UnusedUses(Context.FileName)) > 0) and
    not TAtlasIdeElements.FileHidden(TAtlasDrawnElement.UnusedUses, Context.FileName);
  if not (Branches or UnusedUses) then
    Exit;
  if FDimTabWidth < 0 then
  begin
    View := Context.EditView;
    if (View <> nil) and (View.Buffer <> nil) then
      FDimTabWidth := TAtlasEditorBuffer.TabWidth(View.Buffer)
    else
      FDimTabWidth := 8;
  end;
  if Branches then
  begin
    Result := Store.InactiveSpans(Context.FileName, Context.LogicalLineNum - 1, FDimTabWidth);
    FBranchesDimmed := Length(Result) > 0;
  end;
  if UnusedUses then
  begin
    EntrySpans := Store.UsesSpans(Context.FileName, Context.LogicalLineNum - 1, FDimTabWidth);
    FUsesDimmed := Length(EntrySpans) > 0;
    Result := Result + EntrySpans;
  end;
end;

procedure TAtlasEditorPairs.ReportDimmed(const Context: INTACodeEditorPaintContext; ALine: Integer;
  const ARect: TRect);
begin
  if FBranchesDimmed then
    TAtlasIdeElements.Painted(TAtlasDrawnElement.InactiveDim, Context.FileName, ALine, '', ARect,
      TopRowOf(Context), ARect.Height);
  if FUsesDimmed then
    TAtlasIdeElements.Painted(TAtlasDrawnElement.UnusedUses, Context.FileName, ALine, '', ARect,
      TopRowOf(Context), ARect.Height);
end;

class procedure TAtlasEditorPairs.PaintRun(const ARect: TRect; const AText: string;
  const AContext: INTACodeEditorPaintContext; AColor: TColor);
var
  Canvas: TCanvas;
  Cell, Top, Index, Saved: Integer;
  DC: HDC;
begin
  Canvas := AContext.Canvas;
  Cell := AContext.CellSize.cx;
  if Cell <= 0 then
    Cell := Canvas.TextWidth('W');
  Top := ARect.Top + (ARect.Height - Canvas.TextHeight('Wg')) div 2;
  Canvas.FillRect(ARect);
  DC := Canvas.Handle;
  Saved := SaveDC(DC);
  try
    SetBkMode(DC, TRANSPARENT);
    SetTextColor(DC, ColorToRGB(AColor));
    for Index := 0 to Length(AText) - 1 do
      Winapi.Windows.TextOut(DC, ARect.Left + Index * Cell, Top, PChar(AText) + Index, 1);
  finally
    RestoreDC(DC, Saved);
  end;
end;

procedure TAtlasEditorPairs.PaintText(const Rect: TRect; const ColNum: SmallInt; const Text: string;
  const SyntaxCode: TOTASyntaxCode; const Hilight, BeforeEvent: Boolean; var AllowDefaultPainting: Boolean;
  const Context: INTACodeEditorPaintContext);
var
  Line, Index, Column, Cell, Top: Integer;
  Tokens: TLineTokens;
  Token: TAtlasPairToken;
  Colors: TAtlasColors;
  Canvas: TCanvas;
  Original: TColor;
  CharColors: TArray<TColor>;
  Unpaired: TArray<Boolean>;
  Found: Boolean;
  Back: TRect;
  Pen, Old: HGDIOBJ;
  Brush: HBRUSH;
  DC: HDC;
  Saved: Integer;
  Spans: TArray<TAtlasColumnSpan>;
  Dimmed: TArray<Boolean>;
  Dim: TColor;
  LineText: string;
  ColorsOn, Colored, OwnerColored: Boolean;
begin
  // Durch die Sicherung abgeschaltet (#493).
  if TAtlasGuard.Disabled(TAtlasFeature.Pairs) then
    Exit;
  if not BeforeEvent or Hilight or (Text = '') or (Context = nil) then
    Exit;
  try
    Line := Context.LogicalLineNum - 1;
    // Inaktive {$IFDEF}-Zweige (#615): ganze Läufe gleich, Teile zeichenweise.
    Spans := InactiveSpans(Context);
    ColorsOn := TAtlasIdeSettings.Current.PairColors and
      not TAtlasIdeElements.FileHidden(TAtlasDrawnElement.PairColors, Context.FileName);
    if (Length(Spans) = 0) and not ColorsOn then
      Exit;
    Colored := False;
    OwnerColored := False;
    Canvas := Context.Canvas;
    Original := Canvas.Font.Color;
    SetLength(CharColors, Length(Text));
    SetLength(Unpaired, Length(Text));
    SetLength(Dimmed, Length(Text));
    for Index := 0 to High(CharColors) do
      CharColors[Index] := Original;
    Found := False;
    Colors := PaletteFor(Context);
    if Length(Spans) > 0 then
    begin
      Dim := TColor(TAtlasColorMath.Mix(TAtlasColor(ColorToRGB(Canvas.Font.Color)),
        TAtlasColor(ColorToRGB(Canvas.Brush.Color)), 0.45));
      if TAtlasColumnSpan.Covers(Spans, ColNum, Length(Text)) then
      begin
        PaintRun(Rect, Text, Context, Dim);
        AllowDefaultPainting := False;
        ReportDimmed(Context, Line, Rect);
        Exit;
      end;
      // Teile einer Zeile nur, wenn der Lauf dort im Text der Diagnosen steht (wie bei den Paaren).
      if (TAtlasProblemsController.Current <> nil) and
        TAtlasProblemsController.Current.LineText(Context.FileName, Line, LineText) and
        TAtlasPairs.RunMatches(TAtlasPairs.DisplayLine(LineText, FDimTabWidth), Text, ColNum) then
        for Index := 0 to High(CharColors) do
          if TAtlasColumnSpan.Contains(Spans, ColNum + Index) then
          begin
            CharColors[Index] := Dim;
            Dimmed[Index] := True;
            Found := True;
          end;
    end;
    if ColorsOn then
    begin
      if FCheck or not SameText(Context.FileName, FFileName) then
        Refresh(Context);
      // Nur einfärben, wenn der Lauf in der analysierten Zeile an dieser Stelle steht.
      // Die IDE meldet beim Neuzeichnen von Teilbereichen nicht immer die Zeile des
      // Laufs; sonst landeten Paarfarben mitten in Bezeichnern anderer Zeilen.
      if (Line >= 0) and (Line <= High(FLines)) and (Length(FLines[Line]) > 0) and (Line <= High(FDisplay)) and
        TAtlasPairs.RunMatches(FDisplay[Line], Text, ColNum) then
      begin
        Tokens := FLines[Line];
        for Token in Tokens do
          for Column := Token.Character to Token.Character + Token.Length - 1 do
            if (Column >= ColNum) and (Column < ColNum + Length(Text)) and not Dimmed[Column - ColNum] then
            begin
              Found := True;
              if Token.Owner then
                OwnerColored := True
              else
                Colored := True;
              if Token.Unpaired then
              begin
                CharColors[Column - ColNum] := TColor(Colors.Error);
                Unpaired[Column - ColNum] := True;
              end
              else
                CharColors[Column - ColNum] := TColor(Colors.Pairs[Token.Depth mod Length(Colors.Pairs)]);
            end;
      end;
    end;
    if not Found then
      Exit;
    // Zeilen mit eigenem Hintergrund (Haltepunkt, Ausführungspunkt, Fehlerzeile, #1244): Eine Paarfarbe, die dort zu
    // wenig absticht, weicht der Schriftfarbe, die die IDE für die Zeile vorbereitet hat.
    for Index := 0 to High(CharColors) do
      if (CharColors[Index] <> Original) and not Dimmed[Index] and
        (TAtlasColorMath.Contrast(TAtlasColor(ColorToRGB(CharColors[Index])),
        TAtlasColor(ColorToRGB(Canvas.Brush.Color))) < MinPairContrast) then
        CharColors[Index] := Original;
    // Gezeichnete Elemente der Zeile (#628).
    if Colored then
      TAtlasIdeElements.Painted(TAtlasDrawnElement.PairColors, Context.FileName, Line, '', Rect,
        TopRowOf(Context), Rect.Height);
    if OwnerColored then
      TAtlasIdeElements.Painted(TAtlasDrawnElement.PairOwners, Context.FileName, Line, '', Rect,
        TopRowOf(Context), Rect.Height);
    if Length(Spans) > 0 then
      for Index := 0 to High(Dimmed) do
        if Dimmed[Index] then
        begin
          ReportDimmed(Context, Line, Rect);
          Break;
        end;
    // Lauf selbst zeichnen: Hintergrund wie vorbereitet, Zeichen in fester Zellbreite.
    // Direkt im DC und mit gesichertem Zustand: Die IDE setzt die Textfarbe nur
    // beim Wechsel des Attributs; eine stehengebliebene Paarfarbe färbte sonst
    // Teile späterer Läufe ein (z. B. nach dem Neuzeichnen unter einem Tooltip).
    AllowDefaultPainting := False;
    Cell := Context.CellSize.cx;
    if Cell <= 0 then
      Cell := Canvas.TextWidth('W');
    Top := Rect.Top + (Rect.Height - Canvas.TextHeight('Wg')) div 2;
    Canvas.FillRect(Rect);
    DC := Canvas.Handle;
    Saved := SaveDC(DC);
    try
      SetBkMode(DC, TRANSPARENT);
      for Index := 0 to High(CharColors) do
      begin
        // Unpaarig: blassroter Grund mit roter Unterkante, unabhängig von den Paarfarben.
        if Unpaired[Index] then
        begin
          Back := TRect.Create(Rect.Left + Index * Cell, Rect.Top, Rect.Left + (Index + 1) * Cell, Rect.Bottom);
          // Fehlerfarbe zu 25 % über dem Editorhintergrund: deutlich, aber die Klammer bleibt lesbar.
          Brush := CreateSolidBrush(ColorToRGB(TColor(TAtlasColorMath.Mix(Colors.Error,
            TAtlasColor(ColorToRGB(Canvas.Brush.Color)), 0.25))));
          try
            Winapi.Windows.FillRect(DC, Back, Brush);
          finally
            DeleteObject(Brush);
          end;
          Pen := CreatePen(PS_SOLID, Max(1, Rect.Height div 8), ColorToRGB(TColor(Colors.Error)));
          Old := SelectObject(DC, Pen);
          try
            MoveToEx(DC, Back.Left, Back.Bottom - Max(1, Rect.Height div 16) - 1, nil);
            LineTo(DC, Back.Right, Back.Bottom - Max(1, Rect.Height div 16) - 1);
          finally
            SelectObject(DC, Old);
            DeleteObject(Pen);
          end;
        end;
        SetTextColor(DC, ColorToRGB(CharColors[Index]));
        Winapi.Windows.TextOut(DC, Rect.Left + Index * Cell, Top, PChar(Text) + Index, 1);
      end;
    finally
      RestoreDC(DC, Saved);
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

procedure TAtlasEditorPairs.PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
const
  // Pixel, die die Linie vor Spalte 1 in den Rand ragen darf.
  GuideMargin = 4;
var
  Settings: TAtlasPluginSettings;
  LineState: INTACodeEditorLineState;
  Line, X, Top, Bottom, Tick, Width: Integer;
  LineColor: TAtlasColor;
  Guide: TLineGuide;
  Colors: TAtlasColors;
  Cell, Code: TRect;
  DC: HDC;
  Saved: Integer;
  Pen, Old: HGDIOBJ;
begin
  // Durch die Sicherung abgeschaltet (#493).
  if TAtlasGuard.Disabled(TAtlasFeature.Pairs) then
    Exit;
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) then
    Exit;
  try
    Settings := TAtlasIdeSettings.Current;
    if not (Settings.PairColors and Settings.PairGuides) then
      Exit;
    if TAtlasIdeElements.FileHidden(TAtlasDrawnElement.PairGuides, Context.FileName) then
      Exit;
    if FCheck or not SameText(Context.FileName, FFileName) then
      Refresh(Context);
    Line := Context.LogicalLineNum - 1;
    if (Line < 0) or (Line > High(FGuides)) or (Length(FGuides[Line]) = 0) then
      Exit;
    // Unter dem mitlaufenden Kopf zeichnet der Kopf die Linien selbst, jede erst unter ihrem Element.
    if (Rect.Height > 0) and
      ((Rect.Top + Rect.Height div 2) div Rect.Height < TAtlasIdeStickyScroll.CoveredRows(Context.FileName)) then
      Exit;
    // Wie bei den Läufen: nur, wenn die Zeile zur Analyse passt.
    LineState := Context.LineState;
    if (LineState = nil) or
      (TrimRight(TAtlasPairs.DisplayLine(LineState.Text, FTabWidth)) <> TrimRight(FDisplay[Line])) then
      Exit;
    // Hintergrund aus den Textläufen: Beim Zeichnen der Zeile ist der Pinsel nicht sicher der des Editors.
    if FHasBackground then
      Colors := TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(FBackground)))
    else
      Colors := TAtlasIdeStyle.Colors;
    Colors := WithCustomPairs(Colors);
    if FBaseTextHeight <= 0 then
      FBaseTextHeight := TAtlasIdeStyle.BaseTextHeight;
    Width := TAtlasGuides.PenWidth(Settings.PairGuideWidth, Context.CellSize.cy, FBaseTextHeight);
    Code := LineState.CodeRect;
    DC := Context.Canvas.Handle;
    Saved := SaveDC(DC);
    try
      // Nicht in den Rand zeichnen; nur die Linie vor Spalte 1 darf ein paar Pixel hineinragen.
      if Code.Right > Code.Left then
        IntersectClipRect(DC, Code.Left - GuideMargin, Rect.Top, Rect.Right, Rect.Bottom);
      for Guide in FGuides[Line] do
      begin
        Cell := Context.EditorState.GetCharacterPosPx(Guide.Column, Context.EditorLineNum);
        Tick := Max(3, Cell.Width div 2);
        X := Cell.Left - Max(2, Cell.Width div 3) - (Width - 1) div 2;
        // Blöcke ab Spalte 1 (procedure … end): Linie knapp links vom Text, nicht durch das erste Zeichen.
        if (Code.Right > Code.Left) and (X < Code.Left - GuideMargin + Width div 2) then
          X := Code.Left - GuideMargin + Width div 2;
        Top := Rect.Top;
        Bottom := Rect.Bottom;
        if Guide.Part = gpFirst then
          Top := Rect.Top + 2;
        if Guide.Part = gpLast then
          Bottom := Rect.Bottom - 3;
        // Deckkraft: Linie mit dem Hintergrund gemischt, damit sie zurücktritt.
        LineColor := Colors.Pairs[Guide.Depth mod Length(Colors.Pairs)];
        if FHasBackground and (Settings.PairGuideOpacity < 100) then
          LineColor := TAtlasColorMath.Mix(LineColor, TAtlasColor(ColorToRGB(FBackground)),
            Settings.PairGuideOpacity / 100);
        Pen := CreatePen(PS_SOLID, Width, ColorToRGB(TColor(LineColor)));
        Old := SelectObject(DC, Pen);
        try
          MoveToEx(DC, X, Top, nil);
          LineTo(DC, X, Bottom + 1);
          if Guide.Part = gpFirst then
          begin
            MoveToEx(DC, X, Top, nil);
            LineTo(DC, X + Tick, Top);
          end;
          if Guide.Part = gpLast then
          begin
            MoveToEx(DC, X, Bottom, nil);
            LineTo(DC, X + Tick, Bottom);
          end;
        finally
          SelectObject(DC, Old);
          DeleteObject(Pen);
        end;
      end;
    finally
      RestoreDC(DC, Saved);
    end;
    TAtlasIdeElements.Painted(TAtlasDrawnElement.PairGuides, Context.FileName, Line, '', Code,
      TopRowOf(Context), Rect.Height);
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
    begin
      FGuides := nil;
      TAtlasGuard.Report(TAtlasFeature.Pairs, E);
    end;
  end;
end;

end.
