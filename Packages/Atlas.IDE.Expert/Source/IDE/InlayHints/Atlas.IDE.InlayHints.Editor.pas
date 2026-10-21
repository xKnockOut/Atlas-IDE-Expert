unit Atlas.IDE.InlayHints.Editor;

// Inlay-Hints im Editor (#401, ARG-040): Parameternamen vor Literal-Argumenten,
// standardmäßig aus (Einstellung „Inlay-Hints“).
// - Abruf: Ein Zeitgeber prüft den oberen Editor. 300 ms nach der letzten
//   Änderung gilt der neue Text; dann holt er textDocument/inlayHint nur für
//   die sichtbaren Zeilen (mit Rand), die im Zwischenspeicher noch fehlen
//   (TAtlasInlayHintStore, je Datei und Textstand). Startet keinen Server.
//   Der Abruf läuft im Hauptthread mit kurzem Zeitlimit; nach einem Fehler
//   wartet er einige Sekunden.
// - Zeichnen: nach dem Zeichnen jeder Zeile (plsEndPaint) kleine Marken mit
//   den Namen hinter dem Zeilenende, in der Reihenfolge der Argumente. Der
//   Editor kennt keinen eingeschobenen Text; so bleiben Datei, Undo und
//   Cursor unberührt. Gezeichnet wird nur, wenn die Zeile im Editor der im
//   Speicher entspricht.
// - Zeichnen ohne Objektkopien (P-10): reines GDI zwischen SaveDC und
//   RestoreDC wie im Problem-Zeichner; Schrift, Stift und Pinsel sind Felder
//   und werden nur bei geänderter Editorschrift bzw. geändertem Hintergrund
//   neu gebaut. Die Einstellung wird erst geprüft, wenn die Zeile Hinweise hat.
// - Pufferstand (P-04): über TAtlasEditorSnapshots, gelesen nur nach einer
//   Änderung; bei inaktiver IDE wird der Puffer nicht geprüft.
// - Blockende-Beschriftungen (#620, Einstellung BlockEndLabels): Die
//   Endmarkierungen des Servers (inlayHints.endMarkers, „// if …“) stehen
//   hinter dem end langer Blöcke als gedämpfter Text wie ein Kommentar, nicht
//   als Marke. Abgerufen wird, solange Inlay-Hints oder Beschriftungen an
//   sind; jede Art zeichnet nur mit ihrer Einstellung. Die Mindestlänge
//   (BlockEndLabelsMinLines, editor.blockEndLabels.minLines) geht mit jeder
//   Anfrage an den Server; ändert sie sich, wird neu geholt. Ein Linksklick
//   auf die Beschriftung springt zum Blockanfang.
// - Ausblenden am Element (#628): Inlay-Hints je Codezeile, Beschriftungen je
//   Text der Beschriftung (oder je Datei) über .atlas; jede gezeichnete Marke
//   meldet sich bei TAtlasIdeElements.
// - Typmarken (#453, Einstellung InlayTypeHints): der abgeleitete Typ von
//   var X := …, const X = … und for var X in … als „: TStringList“ in derselben
//   Pille wie die Parameternamen, hinter ihnen; ausblendbar je Codezeile.
// - Include-Symbole (#860, Einstellung InlayDefineHints): hinter {$I datei.inc}
//   „definiert COMPLIB_VCL“ in einer Pille; ausblendbar je Codezeile.
// - Steuerzeichen (#862, Einstellung InlayCharHints): hinter ^C in einer
//   Konstanten der Code „#3“ in einer Pille; ausblendbar je Codezeile.
// - Platz hinter dem Zeilenende (#509): teilt sich der Zeichner über
//   TAtlasLineTail mit dem Fehlertext am Zeilenende.

interface

uses
  System.SysUtils,
  System.Types,
  System.Classes,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.Graphics,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Lsp.Session,
  Atlas.Core.InlayHints.Store;

type
  /// <summary>Laufende Sitzung oder nil; startet keinen Server.</summary>
  TAtlasInlayHintsSessionFunc = reference to function: TLspSession;

  TAtlasEditorInlayHints = class
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;
    /// <summary>Gezeichnete Blockende-Beschriftung mit Ziel des Klicks (#620).</summary>
    TEndHit = record
      FileName: string;
      Line: Integer;
      TopRow: Integer;
      Rect: TRect;
      BlockLine: Integer;
      BlockCharacter: Integer;
    end;
  private const
    QuietMs = 300;
    TimeoutMs = 800;
    RetryMs = 5000;
    /// <summary>Mehr gemerkte Beschriftungen: alle vergessen (der Editor zeichnet sie ohnehin neu).</summary>
    MaxEndHits = 500;
  private
    FSession: TAtlasInlayHintsSessionFunc;
    FStore: TAtlasInlayHintStore;
    FTimer: TTimer;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FFileName: string;
    FText: string;
    FVersion: Cardinal;
    FChangedAt: Cardinal;
    FRetryAt: Cardinal;
    FShowing: Boolean;
    FHintFont: TFont;
    FFontKey: string;
    FBack: COLORREF;
    FBackKnown: Boolean;
    FTextColor: COLORREF;
    FPen: HGDIOBJ;
    FBrush: HGDIOBJ;
    FMinLines: Integer;
    FEndHits: TArray<TEndHit>;
    /// <summary>Baut FHintFont nur neu, wenn sich Name, Größe oder PPI der Editorschrift geändert haben.</summary>
    procedure EnsureHintFont(const AEditorFont: TFont);
    /// <summary>Stift, Pinsel und Textfarbe nur neu, wenn sich der Hintergrund geändert hat.</summary>
    procedure EnsureColors(ABack: COLORREF);
    procedure FreeColors;
    procedure Tick(Sender: TObject);
    procedure Fetch(const AView: IOTAEditView);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure RememberEnd(const AFileName: string; ALine, ATopRow: Integer; const ARect: TRect;
      const AHint: TAtlasInlayHint);
    class procedure Invalidate; static;
  public
    constructor Create(const ASession: TAtlasInlayHintsSessionFunc);
    destructor Destroy; override;
  end;

implementation

uses
  System.Math,
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Pairs,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Foundation.Navigation,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Editor.LineTail,
  Atlas.UI.Strings;

/// <summary>Zeichnet ALabels als Pillen ab AX (Höhe AHeight ab ATop) und rückt AX hinter die letzte; liefert die
/// Fläche aller Pillen, leer ohne.</summary>
function DrawPills(ADC: HDC; const ALabels: TArray<string>; ATop, AHeight: Integer; var AX: Integer): TRect;
var
  Name: string;
  Size: TSize;
  Pill: TRect;
begin
  Result := TRect.Empty;
  for Name in ALabels do
  begin
    GetTextExtentPoint32W(ADC, PChar(Name), Length(Name), Size);
    Pill := TRect.Create(AX, ATop, AX + Size.cx + 8, ATop + AHeight + 2);
    RoundRect(ADC, Pill.Left, Pill.Top, Pill.Right, Pill.Bottom, 6, 6);
    TextOutW(ADC, Pill.Left + 4, Pill.Top + 1, PChar(Name), Length(Name));
    AX := Pill.Right + 4;
    if Result.IsEmpty then
      Result := Pill
    else
      Result.Union(Pill);
  end;
end;

{ TAtlasEditorInlayHints.TEvents }

function TAtlasEditorInlayHints.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents, cevMouseEvents];
end;

function TAtlasEditorInlayHints.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasEditorInlayHints }

constructor TAtlasEditorInlayHints.Create(const ASession: TAtlasInlayHintsSessionFunc);
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FSession := ASession;
  FStore := TAtlasInlayHintStore.Create;
  FIndex := -1;
  FHintFont := TFont.Create;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  FEvents.OnEditorMouseDown := EditorMouseDown;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 150;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasEditorInlayHints.Destroy;
var
  Services: INTACodeEditorServices;
begin
  FTimer.Free;
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.RemoveEditorEventsNotifier(FIndex);
  FEvents.OnEditorPaintLine := nil;
  FEvents.OnEditorMouseDown := nil;
  FEventsRef := nil;
  FreeColors;
  FHintFont.Free;
  FStore.Free;
  inherited Destroy;
end;

class procedure TAtlasEditorInlayHints.Invalidate;
var
  Services: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.InvalidateTopEditor;
end;

function IsSource(const AFileName: string): Boolean;
var
  Extension: string;
begin
  Extension := LowerCase(ExtractFileExt(AFileName));
  Result := (Extension = '.pas') or (Extension = '.dpr') or (Extension = '.dpk') or (Extension = '.inc');
end;

procedure TAtlasEditorInlayHints.Tick(Sender: TObject);
var
  Editors: IOTAEditorServices;
  View: IOTAEditView;
  Snapshot: TAtlasEditorSnapshot;
begin
  // Durch die Sicherung abgeschaltet (#493).
  if TAtlasGuard.Disabled(TAtlasFeature.InlayHints) then
    Exit;
  try
    if not TAtlasIdeSettings.InlayHintsOn and not TAtlasIdeSettings.InlayTypeHintsOn and
      not TAtlasIdeSettings.InlayDefineHintsOn and not TAtlasIdeSettings.InlayCharHintsOn and
      not TAtlasIdeSettings.BlockEndLabelsOn then
    begin
      if FShowing then
      begin
        FStore.Clear;
        FFileName := '';
        FText := '';
        FVersion := 0;
        FShowing := False;
        Invalidate;
      end;
      Exit;
    end;
    // Andere Mindestlänge der Beschriftungen (#620): alles neu holen.
    if FMinLines <> TAtlasIdeSettings.Current.BlockEndLabelsMinLines then
    begin
      FMinLines := TAtlasIdeSettings.Current.BlockEndLabelsMinLines;
      FStore.Clear;
      FEndHits := nil;
    end;
    // Ohne Fokus ändert sich der Puffer nur über Neuladen; das markiert den Stand ohnehin als veraltet (P-04).
    if not Application.Active then
      Exit;
    View := nil;
    if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
      View := Editors.TopView;
    if (View = nil) or (View.Buffer = nil) or not IsSource(View.Buffer.FileName) then
      Exit;
    Snapshot := TAtlasEditorSnapshots.Get(View);
    if not SameText(FFileName, Snapshot.FileName) or (FVersion <> Snapshot.Version) then
    begin
      FFileName := Snapshot.FileName;
      FText := Snapshot.Text;
      FVersion := Snapshot.Version;
      FChangedAt := GetTickCount;
      Exit;
    end;
    // Erst nach der Tipp-Pause; bis dahin bleiben die Marken unveränderter Zeilen stehen.
    if (GetTickCount - FChangedAt < QuietMs) or (GetTickCount < FRetryAt) then
      Exit;
    Fetch(View);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.InlayHints, E);
  end;
end;

procedure TAtlasEditorInlayHints.Fetch(const AView: IOTAEditView);
var
  Session: TLspSession;
  First, Last, From, Till: Integer;
  Hints: TArray<TAtlasInlayHint>;
  Percent: Integer;
begin
  FStore.SetText(FFileName, FText);
  First := AView.TopRow - 1;
  Last := First + AView.ViewSize.cy;
  if not FStore.Missing(FFileName, First, Last, From, Till) then
    Exit;
  Session := FSession();
  if Session = nil then
    Exit;
  // Server indexiert: Er antwortet erst danach, der Hauptthread würde warten (#874). Später noch einmal.
  if Session.Indexing(Percent) then
  begin
    FRetryAt := GetTickCount + RetryMs;
    Exit;
  end;
  try
    Session.Sync(FFileName, FText);
    Hints := Session.InlayHints(FFileName, From, Till, FMinLines, TimeoutMs);
  except
    on E: ELspClientError do
    begin
      // Server beschäftigt oder weg: später noch einmal, ohne den Editor zu bremsen.
      FRetryAt := GetTickCount + RetryMs;
      Exit;
    end;
  end;
  FStore.Put(FFileName, FText, From, Till, Hints);
  FShowing := True;
  Invalidate;
end;

/// <summary>Editorspalte (1-basiert) zum Zeichenindex (0-basiert) in ALine; Tabs aufgelöst.</summary>
function ColumnOf(const ALine: string; ACharacter, ATabWidth: Integer): Integer;
begin
  Result := Length(TAtlasPairs.DisplayLine(Copy(ALine, 1, Max(0, ACharacter)), ATabWidth)) + 1;
end;

procedure TAtlasEditorInlayHints.FreeColors;
begin
  if FPen <> 0 then
    DeleteObject(FPen);
  if FBrush <> 0 then
    DeleteObject(FBrush);
  FPen := 0;
  FBrush := 0;
  FBackKnown := False;
end;

procedure TAtlasEditorInlayHints.EnsureColors(ABack: COLORREF);
var
  Colors: TAtlasHintColors;
begin
  if FBackKnown and (FBack = ABack) then
    Exit;
  FreeColors;
  Colors := TAtlasColors.InlayHint(TAtlasColor(ABack));
  FTextColor := COLORREF(ColorToRGB(TColor(Colors.Text)));
  FPen := CreatePen(PS_SOLID, 1, ColorToRGB(TColor(Colors.Pen)));
  FBrush := CreateSolidBrush(ColorToRGB(TColor(Colors.Fill)));
  FBack := ABack;
  FBackKnown := True;
end;

procedure TAtlasEditorInlayHints.EnsureHintFont(const AEditorFont: TFont);
var
  Key: string;
begin
  Key := AEditorFont.Name + '|' + IntToStr(AEditorFont.Size) + '|' + IntToStr(AEditorFont.PixelsPerInch);
  if Key = FFontKey then
    Exit;
  FHintFont.Assign(AEditorFont);
  FHintFont.Size := Max(6, AEditorFont.Size - 1);
  FHintFont.Style := [];
  FFontKey := Key;
end;

procedure TAtlasEditorInlayHints.PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  Names, Types, Defines, Chars: TArray<string>;
  Stored, EndText, EndLabel: string;
  EndHint: TAtlasInlayHint;
  LineState: INTACodeEditorLineState;
  Line, TabWidth, X, Height, Top: Integer;
  Canvas: TCanvas;
  Cell, Pill, Hints: TRect;
  Sample: COLORREF;
  DC: HDC;
  Saved: Integer;
  Size: TSize;
  ShowNames, ShowTypes, ShowDefines, ShowChars, ShowEnd: Boolean;
  Index: Integer;
  TailKey: string;
begin
  // Durch die Sicherung abgeschaltet (#493).
  if TAtlasGuard.Disabled(TAtlasFeature.InlayHints) then
    Exit;
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) then
    Exit;
  try
    Line := Context.LogicalLineNum - 1;
    Names := FStore.OnLine(Context.FileName, Line);
    Types := FStore.TypesOnLine(Context.FileName, Line);
    Defines := FStore.DefinesOnLine(Context.FileName, Line);
    Chars := FStore.CharsOnLine(Context.FileName, Line);
    ShowEnd := FStore.EndLabelOn(Context.FileName, Line, EndText, EndLabel, EndHint);
    if (Length(Names) = 0) and (Length(Types) = 0) and (Length(Defines) = 0) and (Length(Chars) = 0) and
      not ShowEnd then
      Exit;
    // Erst hier: die meisten Zeilen haben keine Hinweise (P-10).
    ShowNames := (Length(Names) > 0) and TAtlasIdeSettings.InlayHintsOn;
    ShowTypes := (Length(Types) > 0) and TAtlasIdeSettings.InlayTypeHintsOn;
    ShowDefines := (Length(Defines) > 0) and TAtlasIdeSettings.InlayDefineHintsOn;
    ShowChars := (Length(Chars) > 0) and TAtlasIdeSettings.InlayCharHintsOn;
    ShowEnd := ShowEnd and TAtlasIdeSettings.BlockEndLabelsOn;
    if not ShowNames and not ShowTypes and not ShowDefines and not ShowChars and not ShowEnd then
      Exit;
    LineState := Context.LineState;
    if (LineState = nil) or (Context.EditView = nil) or (Context.EditView.Buffer = nil) or
      not FStore.LineText(Context.FileName, Line, Stored) then
      Exit;
    TabWidth := TAtlasEditorBuffer.TabWidth(Context.EditView.Buffer);
    // Nur, wenn die Zeile im Editor der im Speicher entspricht.
    if TrimRight(TAtlasPairs.DisplayLine(LineState.Text, TabWidth)) <>
      TrimRight(TAtlasPairs.DisplayLine(Stored, TabWidth)) then
      Exit;
    // In .atlas ausgeblendet (#628): Inlay-Hints an dieser Codezeile, Beschriftung mit diesem Text.
    if ShowNames and TAtlasIdeElements.Hidden(TAtlasDrawnElement.InlayHints, Context.FileName, Stored) then
      ShowNames := False;
    if ShowTypes and TAtlasIdeElements.Hidden(TAtlasDrawnElement.InlayTypeHints, Context.FileName, Stored) then
      ShowTypes := False;
    if ShowDefines and TAtlasIdeElements.Hidden(TAtlasDrawnElement.InlayDefineHints, Context.FileName, Stored) then
      ShowDefines := False;
    if ShowChars and TAtlasIdeElements.Hidden(TAtlasDrawnElement.InlayCharHints, Context.FileName, Stored) then
      ShowChars := False;
    if ShowEnd and TAtlasIdeElements.Hidden(TAtlasDrawnElement.BlockEndLabels, Context.FileName, EndText) then
      ShowEnd := False;
    if not ShowNames and not ShowTypes and not ShowDefines and not ShowChars and not ShowEnd then
      Exit;
    Canvas := Context.Canvas;
    DC := Canvas.Handle;
    // Zwei Zeichen Abstand hinter dem letzten Zeichen der Zeile.
    Cell := Context.EditorState.GetCharacterPosPx(ColumnOf(Stored, Length(TrimRight(Stored)), TabWidth) + 2,
      Context.EditorLineNum);
    TailKey := TAtlasLineTail.KeyOf(Context.FileName, Context.LogicalLineNum, Context.EditorLineNum, Rect.Top);
    X := TAtlasLineTail.Start(Self, TailKey, Cell.Left);
    // Hintergrund des Editor-Farbschemas an der Stelle des Hinweises (hinter dem Zeilenende), nicht das
    // IDE-Thema: Sonst stand gedämpftes Grau auf fast gleichem Grau. Farben nur bei Abweichung neu.
    Sample := GetPixel(DC, X, Rect.Top + 1);
    if Sample = CLR_INVALID then
      Sample := COLORREF(ColorToRGB(Canvas.Brush.Color));
    EnsureColors(Sample);
    EnsureHintFont(Canvas.Font);
    // Reines GDI: Zustand der VCL-Canvas der IDE bleibt unberührt.
    Saved := SaveDC(DC);
    try
      SelectObject(DC, FHintFont.Handle);
      SelectObject(DC, FPen);
      SelectObject(DC, FBrush);
      SetTextColor(DC, FTextColor);
      SetBkMode(DC, TRANSPARENT);
      GetTextExtentPoint32W(DC, 'Xg', 2, Size);
      Height := Size.cy;
      Top := Rect.Top + Max(0, (Rect.Bottom - Rect.Top - Height - 2) div 2);
      if ShowNames then
      begin
        Hints := DrawPills(DC, Names, Top, Height, X);
        TAtlasIdeElements.Painted(TAtlasDrawnElement.InlayHints, Context.FileName, Line, Stored, Hints,
          Context.EditView.TopRow, Rect.Height);
      end;
      // Typmarken (#453): „: TStringList“ in derselben Pille.
      if ShowTypes then
      begin
        Hints := DrawPills(DC, Types, Top, Height, X);
        TAtlasIdeElements.Painted(TAtlasDrawnElement.InlayTypeHints, Context.FileName, Line, Stored, Hints,
          Context.EditView.TopRow, Rect.Height);
      end;
      // Include-Symbole (#860): „definiert COMPLIB_VCL“ in der Sprache der IDE.
      if ShowDefines then
      begin
        for Index := 0 to High(Defines) do
          Defines[Index] := TAtlasStrings.Fmt(TAtlasTextId.InlayDefinesLabel, [Defines[Index]]);
        Hints := DrawPills(DC, Defines, Top, Height, X);
        TAtlasIdeElements.Painted(TAtlasDrawnElement.InlayDefineHints, Context.FileName, Line, Stored, Hints,
          Context.EditView.TopRow, Rect.Height);
      end;
      // Steuerzeichen (#862): „#3“ hinter ^C.
      if ShowChars then
      begin
        Hints := DrawPills(DC, Chars, Top, Height, X);
        TAtlasIdeElements.Painted(TAtlasDrawnElement.InlayCharHints, Context.FileName, Line, Stored, Hints,
          Context.EditView.TopRow, Rect.Height);
      end;
      // Blockende-Beschriftung (#620): gedämpfter Text wie ein Kommentar, ohne Rahmen.
      if ShowEnd then
      begin
        GetTextExtentPoint32W(DC, PChar(EndLabel), Length(EndLabel), Size);
        Pill := TRect.Create(X, Top, X + Size.cx + 4, Top + Height + 2);
        TextOutW(DC, Pill.Left + 2, Pill.Top + 1, PChar(EndLabel), Length(EndLabel));
        TAtlasIdeElements.Painted(TAtlasDrawnElement.BlockEndLabels, Context.FileName, Line, EndText, Pill,
          Context.EditView.TopRow, Rect.Height);
        RememberEnd(Context.FileName, Line, Context.EditView.TopRow, Pill, EndHint);
        X := Pill.Right;
      end;
      TAtlasLineTail.Finish(Self, TailKey, X);
    finally
      RestoreDC(DC, Saved);
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.InlayHints, E);
  end;
end;

procedure TAtlasEditorInlayHints.RememberEnd(const AFileName: string; ALine, ATopRow: Integer; const ARect: TRect;
  const AHint: TAtlasInlayHint);
var
  Hit: TEndHit;
  Index: Integer;
begin
  if not AHint.HasBlock then
    Exit;
  Hit.FileName := AFileName;
  Hit.Line := ALine;
  Hit.TopRow := ATopRow;
  Hit.Rect := ARect;
  Hit.BlockLine := AHint.BlockLine;
  Hit.BlockCharacter := AHint.BlockCharacter;
  for Index := 0 to High(FEndHits) do
    if (FEndHits[Index].Line = ALine) and SameText(FEndHits[Index].FileName, AFileName) then
    begin
      FEndHits[Index] := Hit;
      Exit;
    end;
  if Length(FEndHits) >= MaxEndHits then
    FEndHits := nil;
  FEndHits := FEndHits + [Hit];
end;

procedure TAtlasEditorInlayHints.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  Editors: IOTAEditorServices;
  View: IOTAEditView;
  Hit: TEndHit;
  FileName: string;
  Line, Character: Integer;
begin
  if (Button <> mbLeft) or (Shift * [ssShift, ssCtrl, ssAlt] <> []) or (Length(FEndHits) = 0) or
    not TAtlasIdeSettings.BlockEndLabelsOn then
    Exit;
  try
    View := nil;
    if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
      View := Editors.TopView;
    if (View = nil) or (View.Buffer = nil) then
      Exit;
    for Hit in FEndHits do
      // Nur, wenn die Beschriftung noch dort steht: gleiche Datei, nicht gescrollt.
      if SameText(Hit.FileName, View.Buffer.FileName) and (Hit.TopRow = View.TopRow) and
        PtInRect(Hit.Rect, Point(X, Y)) then
      begin
        FileName := Hit.FileName;
        Line := Hit.BlockLine;
        Character := Hit.BlockCharacter;
        // Erst nach dem Mausereignis: der Editor setzt den Cursor sonst an die Klickstelle.
        TAtlasMainThread.ForceQueue(TAtlasFeature.InlayHints,
          procedure
          begin
            TAtlasIdeNavigation.GoToLocation(FileName, Line, Character);
          end);
        Exit;
      end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.InlayHints, E);
  end;
end;

end.
