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

interface

uses
  System.SysUtils,
  System.Types,
  Winapi.Windows,
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
  private const
    QuietMs = 300;
    TimeoutMs = 800;
    RetryMs = 5000;
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
    /// <summary>Baut FHintFont nur neu, wenn sich Name, Größe oder PPI der Editorschrift geändert haben.</summary>
    procedure EnsureHintFont(const AEditorFont: TFont);
    /// <summary>Stift, Pinsel und Textfarbe nur neu, wenn sich der Hintergrund geändert hat.</summary>
    procedure EnsureColors(ABack: COLORREF);
    procedure FreeColors;
    procedure Tick(Sender: TObject);
    procedure Fetch(const AView: IOTAEditView);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
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
  Atlas.IDE.Editor.Buffer,
  Atlas.IDE.Editor.Snapshot,
  Atlas.IDE.Editor.Style,
  Atlas.IDE.Settings.Store;

{ TAtlasEditorInlayHints.TEvents }

function TAtlasEditorInlayHints.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
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
    if not TAtlasIdeSettings.InlayHintsOn then
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
begin
  FStore.SetText(FFileName, FText);
  First := AView.TopRow - 1;
  Last := First + AView.ViewSize.cy;
  if not FStore.Missing(FFileName, First, Last, From, Till) then
    Exit;
  Session := FSession();
  if Session = nil then
    Exit;
  try
    Session.Sync(FFileName, FText);
    Hints := Session.InlayHints(FFileName, From, Till, TimeoutMs);
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
  Names: TArray<string>;
  Name, Stored: string;
  LineState: INTACodeEditorLineState;
  Line, TabWidth, X, Height, Top: Integer;
  Canvas: TCanvas;
  Cell, Pill: TRect;
  Sample: COLORREF;
  DC: HDC;
  Saved: Integer;
  Size: TSize;
begin
  // Durch die Sicherung abgeschaltet (#493).
  if TAtlasGuard.Disabled(TAtlasFeature.InlayHints) then
    Exit;
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) then
    Exit;
  try
    Line := Context.LogicalLineNum - 1;
    Names := FStore.OnLine(Context.FileName, Line);
    if Length(Names) = 0 then
      Exit;
    // Erst hier: die meisten Zeilen haben keine Hinweise (P-10).
    if not TAtlasIdeSettings.InlayHintsOn then
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
    Canvas := Context.Canvas;
    DC := Canvas.Handle;
    // Zwei Zeichen Abstand hinter dem letzten Zeichen der Zeile.
    Cell := Context.EditorState.GetCharacterPosPx(ColumnOf(Stored, Length(TrimRight(Stored)), TabWidth) + 2,
      Context.EditorLineNum);
    X := Cell.Left;
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
      for Name in Names do
      begin
        GetTextExtentPoint32W(DC, PChar(Name), Length(Name), Size);
        Pill := TRect.Create(X, Top, X + Size.cx + 8, Top + Height + 2);
        RoundRect(DC, Pill.Left, Pill.Top, Pill.Right, Pill.Bottom, 6, 6);
        TextOutW(DC, Pill.Left + 4, Pill.Top + 1, PChar(Name), Length(Name));
        X := Pill.Right + 4;
      end;
    finally
      RestoreDC(DC, Saved);
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.InlayHints, E);
  end;
end;

end.
