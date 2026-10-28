unit Atlas.IDE.Outline.StickyScroll;

// Mitlaufender Kopf (#506, experimentell) im Editor. Welche Kopfzeilen oben
// stehen, rechnet Atlas.Core.Outline.StickyScroll; hier bleiben Gliederung,
// Zeichnen und Klick.
// - Ein Zeitgeber (100 ms) holt für die aktive Ansicht den Stand von
//   TAtlasIdeOutlineCache (gemeinsam mit Gliederungsfenster und
//   Brotkrumenleiste, keine eigene Serveranfrage). Ändern sich Datei oder
//   Stand, zeichnet der Editor neu.
// - Zeichnen per PaintLine (plsEndPaint): Die ersten Bildschirmzeilen des
//   Codebereichs werden mit der Hintergrundfarbe des Editors übermalt, darauf
//   die Köpfe in seiner Schrift mit ihrer Einrückung; unter der letzten Zeile
//   eine Trennlinie.
// - Farben (#1229): Klammern und Blockwörter des Kopfs wie im Editor in der
//   Farbe ihrer Tiefe (PairColors, eigene Paarfarben je Hell/Dunkel), Besitzer
//   wie procedure/function nur mit PairOwners; unpaarige in der Fehlerfarbe.
//   Die Paaranalyse läuft je neuem Stand der Gliederung einmal.
// - if/else-Blöcke (#1230, editor.stickyScrollBlocks): Blöcke der Paaranalyse,
//   deren erstes Besitzerwort if oder else ist und die mindestens
//   editor.stickyScrollBlockMinLines Zeilen lang sind, stehen als eigene Zeile
//   im Kopf.
// - Bildlauf (#1228): Der Editor verschiebt beim Bildlauf die schon gemalten
//   Pixel (ScrollDC) und malt nur die neuen Zeilen; der alte Kopf wanderte so
//   als Rest mit. Solange der Kopf an ist, schaltet UIOptions das Verschieben
//   ab (ceoDisableScrollDC), und EditorScrolled zeichnet sofort ganz neu.
//   Zeitgeber und PaintLine fangen Bildläufe ohne Ereignis weiter ab.
// - Klick (links, ohne Umschalttasten) auf eine Kopfzeile springt nach dem
//   Mausereignis zum Namen im Kopf.
// - Die oberste Zeile ist View.TopRow; zugeklappte Bereiche darunter zählt
//   der Kopf wie offene.
// editor.stickyScroll aus: nichts wird gezeichnet, kein Klick abgefangen.
// Nur im Hauptthread.

interface

type
  TAtlasIdeStickyScroll = class
  private class var
    FState: TObject;
  public
    /// <summary>Den Server fragt TAtlasIdeOutlineCache (vorher installieren).</summary>
    class procedure Install; static;
    class procedure Uninstall; static;
    /// <summary>Einstellung geändert: Editor neu zeichnen.</summary>
    class procedure ApplySettings; static;
    class function Enabled: Boolean; static;
    /// <summary>Zeilen, die der Kopf oben im Editor zu AFileName verdeckt; 0 ohne Kopf. Die Blocklinien des
    /// Editors bleiben dort weg, der Kopf zeichnet sie selbst.</summary>
    class function CoveredRows(const AFileName: string): Integer; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Math,
  System.Win.Registry,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.ExtCtrls,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Text.Lines,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Outline.Model,
  Atlas.Core.Outline.StickyScroll,
  Atlas.Core.Editor.Pairs,
  Atlas.Core.Editor.Guides,
  Atlas.Core.Editor.Elements,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Outline.Cache;

const
  TickMs = 100;

var
  /// <summary>Neuzeichnen eingereiht; außerhalb des Zustands, weil der Eintrag ihn nicht kennen soll.</summary>
  InvalidatePending: Boolean;
  /// <summary>Kopf an: Der Editor soll beim Bildlauf nicht verschieben (UIOptions, #1228).</summary>
  StickyShown: Boolean;

type
  TEvents = class(TNTACodeEditorNotifier)
  protected
    function AllowedEvents: TCodeEditorEvents; override;
    function AllowedLineStages: TPaintLineStages; override;
    // ceoDisableScrollDC ist für Delphi 13 belegt; unter Delphi 12 bleiben EditorScrolled und Zeitgeber.
    {$IF CompilerVersion >= 37.0}
    function UIOptions: TCodeEditorUIOptions; override;
    {$IFEND}
  end;

  /// <summary>Darstellung eines Elements aus dem Farbschema des Editors.</summary>
  TSyntaxStyle = record
    Color: TColor;
    /// <summary>False: Vorgabefarbe des Editors (Default Foreground), dann die Textfarbe des Kopfs.</summary>
    HasColor: Boolean;
    Style: TFontStyles;
  end;

  TStickyState = class
  private
    FTimer: TTimer;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FOn: Boolean;
    FMaxLines: Integer;
    FFileName: string;
    FStamp: Cardinal;
    FNodes: TAtlasOutlineNodes;
    FLines: TArray<string>;
    /// <summary>Paar-Token je Zeile von FLines (#1229).</summary>
    FPairs: TArray<TArray<TAtlasPairToken>>;
    /// <summary>if/else-Blöcke mit begin … end (#1230), alle Längen; gefiltert wird beim Zeichnen.</summary>
    FBranches: TArray<TAtlasStickyBlock>;
    /// <summary>Blöcke der Paaranalyse und daraus die Blocklinien (je Tabulatorbreite und Besitzer-Schalter).</summary>
    FBlocks: TArray<TAtlasPairBlock>;
    FGuides: TArray<TAtlasGuide>;
    FGuidesKey: string;
    /// <summary>Farbschema des Editors je Art (Editor\Highlight), gelesen mit jedem neuen Stand.</summary>
    FSyntax: array[TAtlasStickySyntax] of TSyntaxStyle;
    /// <summary>Köpfe für die oberste Zeile FRowsTop (0-basiert, -1 = neu rechnen).</summary>
    FRows: TAtlasStickyRows;
    FRowsTop: Integer;
    FRowsMax: Integer;
    /// <summary>Zuletzt gezeichnet: Zeilenhöhe, linker Rand des Codebereichs, oberste Zeile.</summary>
    FRowHeight: Integer;
    FCodeLeft: Integer;
    FPaintedTop: Integer;
    FPaintedRows: Integer;
    /// <summary>Hintergrund des Editors aus einer nicht übermalten Zeile.</summary>
    FBack: TAtlasColor;
    FBackKnown: Boolean;
    /// <summary>Hintergrund aus dem Farbschema (Plain text); vor dem Abtasten, das bei markierten oder
    /// hervorgehobenen Zeilen deren Farbe träfe (#1245).</summary>
    FSchemeBack: TAtlasColor;
    FSchemeBackKnown: Boolean;
    procedure Tick(Sender: TObject);
    procedure Clear;
    procedure Update;
    procedure AnalyzePairs(const AText: string);
    procedure ReadSyntax;
    procedure QueueInvalidate;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure PaintRow(const ARect: TRect; ARowIndex: Integer; const Context: INTACodeEditorPaintContext);
    /// <summary>Blocklinien im Kopf: Jede beginnt unter der Kopfzeile ihres Elements.</summary>
    procedure DrawGuides(const ARect: TRect; ARowIndex: Integer; const Context: INTACodeEditorPaintContext;
      ABack: TAtlasColor);
    /// <summary>Kopftext ab ALeft; Klammern und Blockwörter in der Farbe ihrer Tiefe (#1229).</summary>
    procedure DrawHeader(ACanvas: TCanvas; ALeft, ATop: Integer; const ARow: TAtlasStickyRow;
      const AColors: TAtlasColors; ATextColor: TColor);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure EditorScrolled(const Editor: TWinControl; const Direction: TCodeEditorScrollDirection);
  public
    constructor Create;
    destructor Destroy; override;
    procedure ApplySettings;
  end;

procedure InvalidateEditor;
var
  Services: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.InvalidateTopEditor;
end;

{ TEvents }

function TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents, cevMouseEvents, cevWindowEvents];
end;

function TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{$IF CompilerVersion >= 37.0}
function TEvents.UIOptions: TCodeEditorUIOptions;
begin
  // Ohne Kopf verschiebt der Editor wie gewohnt (schneller).
  if StickyShown then
    Result := [ceoDisableScrollDC]
  else
    Result := [];
end;
{$IFEND}

{ TStickyState }

constructor TStickyState.Create;
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FRowsTop := -1;
  FPaintedTop := -1;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  FEvents.OnEditorMouseDown := EditorMouseDown;
  FEvents.OnEditorScrolled := EditorScrolled;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
  ApplySettings;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := TickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TStickyState.Destroy;
var
  Services: INTACodeEditorServices;
  Shown: Boolean;
begin
  FTimer.Free;
  Shown := FPaintedRows > 0;
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.RemoveEditorEventsNotifier(FIndex);
  FEvents.OnEditorPaintLine := nil;
  FEvents.OnEditorMouseDown := nil;
  FEvents.OnEditorScrolled := nil;
  FEventsRef := nil;
  StickyShown := False;
  if Shown then
    InvalidateEditor;
  inherited Destroy;
end;

procedure TStickyState.ApplySettings;
var
  Settings: TAtlasPluginSettings;
  Was: Boolean;
begin
  Settings := TAtlasIdeSettings.Current;
  Was := FOn;
  FOn := Settings.Enabled and Settings.StickyScroll and not TAtlasGuard.Disabled(TAtlasFeature.StickyScroll);
  FMaxLines := TAtlasStickyScroll.ClampLines(Settings.StickyScrollMaxLines);
  StickyShown := FOn;
  // Paarfarben an oder aus: beim nächsten Takt neu analysieren.
  FStamp := 0;
  FRowsTop := -1;
  if not FOn then
    Clear;
  if Was or FOn then
    InvalidateEditor;
end;

procedure TStickyState.Clear;
begin
  FFileName := '';
  FStamp := 0;
  FNodes := nil;
  FLines := nil;
  FPairs := nil;
  FBranches := nil;
  FRows := nil;
  FRowsTop := -1;
  FPaintedRows := 0;
end;

procedure TStickyState.QueueInvalidate;
begin
  if InvalidatePending then
    Exit;
  InvalidatePending := True;
  // Nicht während des Malens: nach dem laufenden Ereignis.
  TAtlasMainThread.ForceQueue(TAtlasFeature.StickyScroll,
    procedure
    begin
      InvalidatePending := False;
      InvalidateEditor;
    end);
end;

procedure TStickyState.Tick(Sender: TObject);
begin
  try
    Update;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.StickyScroll, E);
  end;
end;

procedure TStickyState.Update;
var
  View: IOTAEditView;
  Snapshot: TAtlasOutlineSnapshot;
  Shown: Boolean;
begin
  // Schnellschalter und Schutzschalter wirken ohne eigenes Ereignis.
  if (TAtlasIdeStickyScroll.Enabled and not TAtlasGuard.Disabled(TAtlasFeature.StickyScroll)) <> FOn then
    ApplySettings;
  if not FOn then
    Exit;
  View := TAtlasEditorBuffer.ActiveView;
  if (View = nil) or (View.Buffer = nil) then
    Exit;
  Snapshot := TAtlasIdeOutlineCache.Refresh(View);
  case Snapshot.Status of
    TAtlasOutlineStatus.Waiting:
      Exit;
    TAtlasOutlineStatus.NoFile, TAtlasOutlineStatus.NoServer:
      begin
        Shown := FPaintedRows > 0;
        Clear;
        if Shown then
          InvalidateEditor;
        Exit;
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
  if not SameText(Snapshot.FileName, FFileName) or (Snapshot.Stamp <> FStamp) then
  begin
    FFileName := Snapshot.FileName;
    FStamp := Snapshot.Stamp;
    FNodes := Snapshot.Nodes;
    FLines := TTextLines.SplitLines(Snapshot.Text);
    AnalyzePairs(Snapshot.Text);
    ReadSyntax;
    FRowsTop := -1;
    InvalidateEditor;
  end
  else if (View.TopRow - 1 <> FPaintedTop) and ((FPaintedRows > 0) or (Length(FNodes) > 0)) then
    // Bildlauf ohne Malen der oberen Zeilen (z. B. per Rollrad): ganz neu zeichnen.
    InvalidateEditor;
end;

/// <summary>Wort ab AIndex (0-basiert) in ALine, klein.</summary>
function WordAt(const ALine: string; AIndex: Integer): string;
var
  Stop: Integer;
begin
  Stop := AIndex + 1;
  while (Stop <= Length(ALine)) and CharInSet(ALine[Stop], ['A'..'Z', 'a'..'z']) do
    Inc(Stop);
  Result := LowerCase(Copy(ALine, AIndex + 1, Stop - AIndex - 1));
end;

procedure TStickyState.AnalyzePairs(const AText: string);
var
  Settings: TAtlasPluginSettings;
  Token: TAtlasPairToken;
  Tokens: TArray<TAtlasPairToken>;
  Blocks: TArray<TAtlasPairBlock>;
  Block: TAtlasPairBlock;
  Owner: string;
begin
  FPairs := nil;
  FBranches := nil;
  FBlocks := nil;
  FGuidesKey := '';
  Settings := TAtlasIdeSettings.Current;
  if not (Settings.PairColors or Settings.StickyScrollBlocks) then
    Exit;
  Tokens := TAtlasPairs.Analyze(AText, Blocks);
  FBlocks := Blocks;
  if Settings.PairColors then
  begin
    SetLength(FPairs, Length(FLines));
    for Token in Tokens do
      if (Token.Line >= 0) and (Token.Line <= High(FPairs)) then
        FPairs[Token.Line] := FPairs[Token.Line] + [Token];
  end;
  if not Settings.StickyScrollBlocks then
    Exit;
  // Blöcke, deren erstes Besitzerwort if oder else ist (#1230); Routinen und Klassen liefert die Gliederung.
  for Block in Blocks do
  begin
    if (Block.OwnerLine < 0) or (Block.OwnerLine > High(FLines)) then
      Continue;
    Owner := WordAt(FLines[Block.OwnerLine], Block.OwnerCharacter);
    if (Owner = 'if') or (Owner = 'else') then
      FBranches := FBranches + [TAtlasStickyBlock.Create(Block.OwnerLine, Block.OwnerCharacter, Block.CloseLine)];
  end;
end;

/// <summary>if/else-Blöcke ab AMinLines Zeilen (vom Kopf bis zum end).</summary>
function LongBranches(const ABranches: TArray<TAtlasStickyBlock>; AMinLines: Integer): TArray<TAtlasStickyBlock>;
var
  Block: TAtlasStickyBlock;
begin
  Result := nil;
  for Block in ABranches do
    if Block.EndLine - Block.Line + 1 >= AMinLines then
      Result := Result + [Block];
end;

procedure TStickyState.PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  View: IOTAEditView;
  Top, Row, Height: Integer;
  Sample: COLORREF;
  Branches: TArray<TAtlasStickyBlock>;
begin
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or not FOn or (FFileName = '') then
    Exit;
  try
    View := Context.EditView;
    if (View = nil) or (View.Buffer = nil) or not SameText(Context.FileName, FFileName) then
      Exit;
    Height := Rect.Bottom - Rect.Top;
    if Height <= 0 then
      Exit;
    Top := View.TopRow - 1;
    if (Top <> FRowsTop) or (FMaxLines <> FRowsMax) then
    begin
      Branches := nil;
      if TAtlasIdeSettings.Current.StickyScrollBlocks then
        Branches := LongBranches(FBranches, TAtlasIdeSettings.Current.StickyScrollBlockMinLines);
      FRows := TAtlasStickyScroll.Rows(FNodes, FLines, Branches, Top, FMaxLines,
        TAtlasEditorBuffer.TabWidth(View.Buffer));
      FRowsTop := Top;
      FRowsMax := FMaxLines;
    end;
    // Hat der Editor beim Bildlauf nur einen Teil gemalt, stehen alte Köpfe verschoben: ganz neu zeichnen.
    if (FPaintedTop >= 0) and (Top <> FPaintedTop) and ((FPaintedRows > 0) or (Length(FRows) > 0)) then
      QueueInvalidate;
    FPaintedTop := Top;
    FPaintedRows := Length(FRows);
    FRowHeight := Height;
    Row := (Rect.Top + Height div 2) div Height;
    if Row >= Length(FRows) then
    begin
      // Nicht übermalte Zeile: deren Hintergrund ist der des Editors.
      Sample := GetPixel(Context.Canvas.Handle, Rect.Right - 2, Rect.Top + 1);
      if not FSchemeBackKnown and (Sample <> CLR_INVALID) then
      begin
        FBack := TAtlasColor(Sample);
        FBackKnown := True;
      end;
      Exit;
    end;
    PaintRow(Rect, Row, Context);
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.StickyScroll, E);
  end;
end;

procedure TStickyState.DrawGuides(const ARect: TRect; ARowIndex: Integer; const Context: INTACodeEditorPaintContext;
  ABack: TAtlasColor);
const
  // Wie die Blocklinien des Editors (Atlas.IDE.Editor.Pairs).
  GuideMargin = 4;
var
  Settings: TAtlasPluginSettings;
  Owners: Boolean;
  Key: string;
  TabWidth, Below, Start, Index, Width, X: Integer;
  Guide: TAtlasGuide;
  Colors: TAtlasColors;
  LineColor: TAtlasColor;
  Cell, Code: TRect;
  DC: HDC;
  Saved: Integer;
  Pen, Old: HGDIOBJ;
begin
  Settings := TAtlasIdeSettings.Current;
  if not (Settings.PairColors and Settings.PairGuides) or (Length(FBlocks) = 0) or (Context.LineState = nil) or
    (Context.EditView = nil) or (Context.EditView.Buffer = nil) or
    TAtlasIdeElements.FileHidden(TAtlasDrawnElement.PairGuides, FFileName) then
    Exit;
  TabWidth := TAtlasEditorBuffer.TabWidth(Context.EditView.Buffer);
  Owners := Settings.PairOwners and not TAtlasIdeElements.FileHidden(TAtlasDrawnElement.PairOwners, FFileName);
  Key := IntToStr(TabWidth) + BoolToStr(Owners, True);
  if Key <> FGuidesKey then
  begin
    FGuides := TAtlasGuides.FromBlocks(FLines, FBlocks, TabWidth, Owners);
    FGuidesKey := Key;
  end;
  // Erste Zeile unter dem Kopf: Nur Linien, die dort weiterlaufen, reichen in den Kopf.
  Below := FRowsTop + Length(FRows);
  Colors := TAtlasColors.ForBackground(ABack);
  if Colors.IsDark then
    Colors := Colors.WithPairs(Settings.PairColorsDark)
  else
    Colors := Colors.WithPairs(Settings.PairColorsLight);
  Width := TAtlasGuides.PenWidth(Settings.PairGuideWidth, Context.CellSize.cy, TAtlasIdeStyle.BaseTextHeight);
  Code := Context.LineState.CodeRect;
  DC := Context.Canvas.Handle;
  Saved := SaveDC(DC);
  try
    if Code.Right > Code.Left then
      IntersectClipRect(DC, Code.Left - GuideMargin, ARect.Top, ARect.Right, ARect.Bottom);
    for Guide in FGuides do
    begin
      if (Guide.FirstLine >= Below) or (Guide.LastLine < Below) then
        Continue;
      // Das Element der Linie: die Kopfzeile, deren Zeile die erste der Linie ist (Anweisung bzw. Öffner).
      Start := -1;
      for Index := 0 to High(FRows) do
        if not FRows[Index].Summary and (FRows[Index].Line = Guide.FirstLine) then
          Start := Index;
      // Ab seiner Kopfzeile (dort mit Haken wie im Editor); ohne Kopfzeile beginnt die Linie unter dem Kopf.
      if (Start < 0) or (ARowIndex < Start) then
        Continue;
      Cell := Context.EditorState.GetCharacterPosPx(Guide.Column, Context.EditorLineNum);
      X := Cell.Left - Max(2, Cell.Width div 3) - (Width - 1) div 2;
      if (Code.Right > Code.Left) and (X < Code.Left - GuideMargin + Width div 2) then
        X := Code.Left - GuideMargin + Width div 2;
      LineColor := Colors.Pairs[Guide.Depth mod Length(Colors.Pairs)];
      if Settings.PairGuideOpacity < 100 then
        LineColor := TAtlasColorMath.Mix(LineColor, ABack, Settings.PairGuideOpacity / 100);
      Pen := CreatePen(PS_SOLID, Width, ColorToRGB(TColor(LineColor)));
      Old := SelectObject(DC, Pen);
      try
        if ARowIndex = Start then
        begin
          MoveToEx(DC, X, ARect.Top + 2, nil);
          LineTo(DC, X, ARect.Bottom);
          MoveToEx(DC, X, ARect.Top + 2, nil);
          LineTo(DC, X + Max(3, Cell.Width div 2), ARect.Top + 2);
        end
        else
        begin
          MoveToEx(DC, X, ARect.Top, nil);
          LineTo(DC, X, ARect.Bottom);
        end;
      finally
        SelectObject(DC, Old);
        DeleteObject(Pen);
      end;
    end;
  finally
    RestoreDC(DC, Saved);
  end;
end;

procedure TStickyState.ReadSyntax;
const
  Elements: array[TAtlasStickySyntax] of string = ('Whitespace', 'Reserved word', 'Identifier', 'Number', 'String',
    'Character', 'Comment', 'Symbol', 'Preprocessor');
var
  Services: IOTAServices;
  Registry: TRegistry;
  Kind: TAtlasStickySyntax;
  Style: TSyntaxStyle;
begin
  for Kind := Low(TAtlasStickySyntax) to High(TAtlasStickySyntax) do
    FSyntax[Kind] := Default(TSyntaxStyle);
  if not Supports(BorlandIDEServices, IOTAServices, Services) then
    Exit;
  Registry := TRegistry.Create(KEY_READ);
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    for Kind := Low(TAtlasStickySyntax) to High(TAtlasStickySyntax) do
    begin
      Style := Default(TSyntaxStyle);
      try
        if Registry.OpenKeyReadOnly(Services.GetBaseRegistryKey + '\Editor\Highlight\' + Elements[Kind]) then
        begin
          if Registry.ValueExists('Bold') and SameText(Registry.ReadString('Bold'), 'True') then
            Include(Style.Style, fsBold);
          if Registry.ValueExists('Italic') and SameText(Registry.ReadString('Italic'), 'True') then
            Include(Style.Style, fsItalic);
          // „$00BCE0FF“ oder „clMaroon“; mit Default Foreground die Vorgabefarbe des Editors.
          if Registry.ValueExists('Foreground Color New') and not (Registry.ValueExists('Default Foreground') and
            SameText(Registry.ReadString('Default Foreground'), 'True')) then
          begin
            Style.Color := StringToColor(Registry.ReadString('Foreground Color New'));
            Style.HasColor := True;
          end;
          Registry.CloseKey;
        end;
      except
        // Unlesbarer Eintrag: diese Art ohne Hervorhebung.
        on Exception do
          Style := Default(TSyntaxStyle);
      end;
      FSyntax[Kind] := Style;
    end;
    // Hintergrund des Editors (#1245); mit Default Background bleibt das Abtasten.
    FSchemeBackKnown := False;
    try
      if Registry.OpenKeyReadOnly(Services.GetBaseRegistryKey + '\Editor\Highlight\Plain text') then
      begin
        if Registry.ValueExists('Background Color New') and not (Registry.ValueExists('Default Background') and
          SameText(Registry.ReadString('Default Background'), 'True')) then
        begin
          FSchemeBack := TAtlasColor(ColorToRGB(StringToColor(Registry.ReadString('Background Color New'))));
          FSchemeBackKnown := True;
        end;
        Registry.CloseKey;
      end;
    except
      on Exception do
        FSchemeBackKnown := False;
    end;
  finally
    Registry.Free;
  end;
end;

procedure TStickyState.DrawHeader(ACanvas: TCanvas; ALeft, ATop: Integer; const ARow: TAtlasStickyRow;
  const AColors: TAtlasColors; ATextColor: TColor);
var
  Settings: TAtlasPluginSettings;
  Pairs: TAtlasColors;
  Spans: TArray<TAtlasPairSpan>;
  Span: TAtlasPairSpan;
  Token: TAtlasStickyToken;
  CharColors: TArray<TColor>;
  CharStyles: TArray<TFontStyles>;
  Index, Stop, X: Integer;
  Style: TSyntaxStyle;
begin
  X := ALeft;
  if ARow.Summary or (ARow.Text = '') then
  begin
    // Zusammenfassung „A › B“: gedämpft wie bisher, ohne Hervorhebung.
    ACanvas.Font.Color := ATextColor;
    ACanvas.TextOut(X, ATop, ARow.Text);
    Exit;
  end;
  // Hervorhebung wie im Editor (Farbschema, fett, kursiv), je Zeichen.
  SetLength(CharColors, Length(ARow.Text));
  SetLength(CharStyles, Length(ARow.Text));
  for Index := 0 to High(CharColors) do
  begin
    CharColors[Index] := ATextColor;
    CharStyles[Index] := [];
  end;
  for Token in TAtlasStickyScroll.Syntax(ARow.Text) do
  begin
    Style := FSyntax[Token.Kind];
    for Index := Token.Start - 1 to Min(High(CharColors), Token.Start + Token.Length - 2) do
    begin
      if Style.HasColor then
        CharColors[Index] := Style.Color;
      CharStyles[Index] := Style.Style;
    end;
  end;
  // Paarfarben wie im Editor (#1229): nur mit PairColors und nicht in dieser Datei ausgeblendet; die Farbe ersetzt
  // die des Farbschemas, fett und kursiv bleiben.
  Settings := TAtlasIdeSettings.Current;
  Spans := nil;
  if (ARow.Line >= 0) and (ARow.Line <= High(FPairs)) and (ARow.Line <= High(FLines)) and Settings.PairColors and
    not TAtlasIdeElements.FileHidden(TAtlasDrawnElement.PairColors, FFileName) then
    Spans := TAtlasPairs.Spans(ARow.Text, FLines[ARow.Line], FPairs[ARow.Line],
      Settings.PairOwners and not TAtlasIdeElements.FileHidden(TAtlasDrawnElement.PairOwners, FFileName));
  if Length(Spans) > 0 then
  begin
    if AColors.IsDark then
      Pairs := AColors.WithPairs(Settings.PairColorsDark)
    else
      Pairs := AColors.WithPairs(Settings.PairColorsLight);
    for Span in Spans do
      for Index := Span.Start - 1 to Min(High(CharColors), Span.Start + Span.Length - 2) do
        if Span.Unpaired then
          CharColors[Index] := TColor(Pairs.Error)
        else
          CharColors[Index] := TColor(Pairs.Pairs[Span.Depth mod Length(Pairs.Pairs)]);
  end;
  // Läufe gleicher Farbe und Schrift am Stück.
  Index := 0;
  while Index <= High(CharColors) do
  begin
    Stop := Index;
    while (Stop < High(CharColors)) and (CharColors[Stop + 1] = CharColors[Index]) and
      (CharStyles[Stop + 1] = CharStyles[Index]) do
      Inc(Stop);
    ACanvas.Font.Color := CharColors[Index];
    ACanvas.Font.Style := CharStyles[Index];
    ACanvas.TextOut(X, ATop, Copy(ARow.Text, Index + 1, Stop - Index + 1));
    Inc(X, ACanvas.TextWidth(Copy(ARow.Text, Index + 1, Stop - Index + 1)));
    Index := Stop + 1;
  end;
end;

procedure TStickyState.PaintRow(const ARect: TRect; ARowIndex: Integer; const Context: INTACodeEditorPaintContext);
var
  ARow: TAtlasStickyRow;
  ALast: Boolean;
  Canvas: TCanvas;
  LineState: INTACodeEditorLineState;
  Code, Area, Cell: TRect;
  Colors: TAtlasColors;
  Back: TAtlasColor;
  Sample: COLORREF;
  Saved, Left, TextTop: Integer;
  OldFont: TFont;
  OldBrush: TBrush;
  OldPen: TPen;
begin
  ARow := FRows[ARowIndex];
  ALast := ARowIndex = High(FRows);
  Canvas := Context.Canvas;
  LineState := Context.LineState;
  Left := ARect.Left;
  if LineState <> nil then
  begin
    Code := LineState.CodeRect;
    if Code.Right > Code.Left then
      Left := Code.Left;
  end;
  FCodeLeft := Left;
  Area := TRect.Create(Left, ARect.Top, ARect.Right, ARect.Bottom);
  if FSchemeBackKnown then
    Back := FSchemeBack
  else if FBackKnown then
    Back := FBack
  else
  begin
    Sample := GetPixel(Canvas.Handle, ARect.Right - 2, ARect.Top + 1);
    if Sample = CLR_INVALID then
      Back := TAtlasColor(ColorToRGB(Canvas.Brush.Color))
    else
      Back := TAtlasColor(Sample);
  end;
  Colors := TAtlasColors.ForBackground(Back);
  OldFont := TFont.Create;
  OldBrush := TBrush.Create;
  OldPen := TPen.Create;
  OldFont.Assign(Canvas.Font);
  OldBrush.Assign(Canvas.Brush);
  OldPen.Assign(Canvas.Pen);
  Saved := SaveDC(Canvas.Handle);
  try
    IntersectClipRect(Canvas.Handle, Area.Left, Area.Top, Area.Right, Area.Bottom);
    Canvas.Brush.Style := bsSolid;
    // Leichte Abgrenzung: Hintergrund des Editors, eine Spur zur Schrift hin.
    Canvas.Brush.Color := TColor(TAtlasColorMath.Mix(Colors.Text, Back, 0.04));
    Canvas.FillRect(Area);
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Style := [];
    if ARow.Summary then
      Canvas.Font.Color := TColor(Colors.Muted)
    else
      Canvas.Font.Color := TColor(Colors.Text);
    Cell := Context.EditorState.GetCharacterPosPx(ARow.Indent + 1, Context.EditorLineNum);
    TextTop := ARect.Top + Max(0, (ARect.Bottom - ARect.Top - Canvas.TextHeight('Xg')) div 2);
    DrawHeader(Canvas, Max(Left, Cell.Left), TextTop, ARow, Colors, Canvas.Font.Color);
    if ALast then
    begin
      Canvas.Pen.Style := psSolid;
      Canvas.Pen.Width := 1;
      Canvas.Pen.Color := TColor(Colors.Line);
      Canvas.MoveTo(Area.Left, Area.Bottom - 1);
      Canvas.LineTo(Area.Right, Area.Bottom - 1);
    end;
  finally
    RestoreDC(Canvas.Handle, Saved);
    DrawGuides(ARect, ARowIndex, Context, Back);
    Canvas.Font.Assign(OldFont);
    Canvas.Brush.Assign(OldBrush);
    Canvas.Pen.Assign(OldPen);
    OldPen.Free;
    OldBrush.Free;
    OldFont.Free;
  end;
end;

procedure TStickyState.EditorScrolled(const Editor: TWinControl; const Direction: TCodeEditorScrollDirection);
begin
  try
    // Senkrecht verschiebt sich der Kopf; waagerecht seine Einrückung. Beides sofort ganz neu, nicht erst im Takt.
    if not FOn or ((FPaintedRows = 0) and (Length(FNodes) = 0)) then
      Exit;
    if Editor <> nil then
      Editor.Invalidate
    else
      InvalidateEditor;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.StickyScroll, E);
  end;
end;

procedure TStickyState.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  View: IOTAEditView;
  Row: Integer;
  Target: TAtlasStickyRow;
  FileName: string;
begin
  try
    if not FOn or (Button <> mbLeft) or (Shift * [ssShift, ssCtrl, ssAlt] <> []) or (FPaintedRows = 0) or
      (FRowHeight <= 0) or (Y < 0) or (X < FCodeLeft) then
      Exit;
    Row := Y div FRowHeight;
    if (Row >= FPaintedRows) or (Row > High(FRows)) then
      Exit;
    // Nur, wenn die Köpfe noch so stehen: gleiche Datei, nicht gescrollt.
    View := TAtlasEditorBuffer.ActiveView;
    if (View = nil) or (View.Buffer = nil) or not SameText(View.Buffer.FileName, FFileName) or
      (View.TopRow - 1 <> FPaintedTop) then
      Exit;
    Target := FRows[Row];
    FileName := FFileName;
    // Erst nach dem Mausereignis: der Editor setzt sonst den Cursor auf die angeklickte Stelle.
    TAtlasMainThread.ForceQueue(TAtlasFeature.StickyScroll,
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.StickyScroll,
          procedure
          begin
            TAtlasIdeNavigation.GoToLocation(FileName, Target.Line, Target.Character);
          end);
      end);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.StickyScroll, E);
  end;
end;

{ TAtlasIdeStickyScroll }

class procedure TAtlasIdeStickyScroll.Install;
begin
  if FState = nil then
    FState := TStickyState.Create;
end;

class procedure TAtlasIdeStickyScroll.Uninstall;
begin
  FreeAndNil(FState);
end;

class procedure TAtlasIdeStickyScroll.ApplySettings;
begin
  if FState <> nil then
    TStickyState(FState).ApplySettings;
end;

class function TAtlasIdeStickyScroll.CoveredRows(const AFileName: string): Integer;
var
  State: TStickyState;
begin
  Result := 0;
  if FState = nil then
    Exit;
  State := TStickyState(FState);
  if State.FOn and SameText(State.FFileName, AFileName) then
    Result := State.FPaintedRows;
end;

class function TAtlasIdeStickyScroll.Enabled: Boolean;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := Settings.Enabled and Settings.StickyScroll;
end;

end.
