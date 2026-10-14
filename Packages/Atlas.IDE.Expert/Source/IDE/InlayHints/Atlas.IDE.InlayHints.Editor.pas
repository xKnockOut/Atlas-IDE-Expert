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

interface

uses
  System.SysUtils,
  System.Types,
  Vcl.ExtCtrls,
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
    FChangedAt: Cardinal;
    FRetryAt: Cardinal;
    FShowing: Boolean;
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
  Winapi.Windows,
  System.Math,
  Vcl.Graphics,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Pairs,
  Atlas.IDE.Editor.Buffer,
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
  Settings: TAtlasPluginSettings;
  Editors: IOTAEditorServices;
  View: IOTAEditView;
  Text: string;
begin
  // Durch die Sicherung abgeschaltet (#493).
  if TAtlasGuard.Disabled(TAtlasFeature.InlayHints) then
    Exit;
  try
    Settings := TAtlasIdeSettings.Current;
    if not (Settings.Enabled and Settings.InlayHints) then
    begin
      if FShowing then
      begin
        FStore.Clear;
        FFileName := '';
        FText := '';
        FShowing := False;
        Invalidate;
      end;
      Exit;
    end;
    View := nil;
    if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
      View := Editors.TopView;
    if (View = nil) or (View.Buffer = nil) or not IsSource(View.Buffer.FileName) then
      Exit;
    Text := TAtlasEditorBuffer.Text(View.Buffer);
    if not SameText(FFileName, View.Buffer.FileName) or (FText <> Text) then
    begin
      FFileName := View.Buffer.FileName;
      FText := Text;
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

procedure TAtlasEditorInlayHints.PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  Settings: TAtlasPluginSettings;
  Names: TArray<string>;
  Name, Stored: string;
  LineState: INTACodeEditorLineState;
  Line, TabWidth, X, Width, Height, Top: Integer;
  Colors: TAtlasColors;
  Canvas: TCanvas;
  Cell, Pill: TRect;
  OldFont: TFont;
  OldBrush: TBrush;
  OldPen: TPen;
  Back: TAtlasColor;
  Sample: COLORREF;
begin
  // Durch die Sicherung abgeschaltet (#493).
  if TAtlasGuard.Disabled(TAtlasFeature.InlayHints) then
    Exit;
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) then
    Exit;
  try
    Settings := TAtlasIdeSettings.Current;
    if not (Settings.Enabled and Settings.InlayHints) then
      Exit;
    Line := Context.LogicalLineNum - 1;
    Names := FStore.OnLine(Context.FileName, Line);
    if Length(Names) = 0 then
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
    // Zwei Zeichen Abstand hinter dem letzten Zeichen der Zeile.
    Cell := Context.EditorState.GetCharacterPosPx(ColumnOf(Stored, Length(TrimRight(Stored)), TabWidth) + 2,
      Context.EditorLineNum);
    X := Cell.Left;
    // Hintergrund des Editor-Farbschemas an der Stelle des Hinweises (hinter dem Zeilenende), nicht das
    // IDE-Thema: Sonst stand gedämpftes Grau auf fast gleichem Grau.
    Sample := GetPixel(Canvas.Handle, X, Rect.Top + 1);
    if Sample = CLR_INVALID then
      Back := TAtlasColor(ColorToRGB(Canvas.Brush.Color))
    else
      Back := TAtlasColor(Sample);
    Colors := TAtlasColors.ForBackground(Back);
    OldFont := TFont.Create;
    OldBrush := TBrush.Create;
    OldPen := TPen.Create;
    try
      OldFont.Assign(Canvas.Font);
      OldBrush.Assign(Canvas.Brush);
      OldPen.Assign(Canvas.Pen);
      Canvas.Font.Size := Max(6, Canvas.Font.Size - 1);
      Canvas.Font.Style := [];
      // Text deutlich lesbar, Fläche leicht im Akzent abgesetzt.
      Canvas.Font.Color := TColor(TAtlasColorMath.Mix(Colors.Text, Back, 0.8));
      Canvas.Pen.Color := TColor(TAtlasColorMath.Mix(Colors.Accent, Back, 0.45));
      Canvas.Brush.Color := TColor(TAtlasColorMath.Mix(Colors.Accent, Back, 0.2));
      Height := Canvas.TextHeight('Xg');
      Top := Rect.Top + Max(0, (Rect.Bottom - Rect.Top - Height - 2) div 2);
      for Name in Names do
      begin
        Width := Canvas.TextWidth(Name);
        Pill := TRect.Create(X, Top, X + Width + 8, Top + Height + 2);
        Canvas.Brush.Style := bsSolid;
        Canvas.RoundRect(Pill.Left, Pill.Top, Pill.Right, Pill.Bottom, 6, 6);
        Canvas.Brush.Style := bsClear;
        Canvas.TextOut(Pill.Left + 4, Pill.Top + 1, Name);
        X := Pill.Right + 4;
      end;
    finally
      Canvas.Font.Assign(OldFont);
      Canvas.Brush.Assign(OldBrush);
      Canvas.Pen.Assign(OldPen);
      OldPen.Free;
      OldBrush.Free;
      OldFont.Free;
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.InlayHints, E);
  end;
end;

end.
