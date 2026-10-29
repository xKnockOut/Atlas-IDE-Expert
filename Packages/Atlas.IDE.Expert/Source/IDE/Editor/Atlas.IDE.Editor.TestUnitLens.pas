unit Atlas.IDE.Editor.TestUnitLens;

// Code Lens „→ Testunit …“ über der Zeile „unit …;“ (#189).
// - Abruf: Ein Zeitgeber prüft den oberen Editor. Nach einer Tipp-Pause fragt
//   er atlas.server.testUnit für die Datei (nur, wenn der Server ohnehin
//   läuft) und merkt sich die Antwort je Datei und Textstand. Ohne Änderung
//   fragt er alle RefreshMs neu, damit eine inzwischen angelegte Testunit
//   erscheint.
// - Zeichnen: hinter dem Ende der Zeile „unit …;“ (plsEndPaint) eine Marke
//   mit dem Text der Lens; ihr Rechteck wird gemerkt.
// - Klick: Linksklick in die Marke wechselt wie der Befehl „Zur Testunit
//   wechseln“ (nach dem Mausereignis, über die Warteschlange).
// Abschaltbar über die Einstellung „Code Lens Testunit“, je Datei über
// „In dieser Datei ausblenden“ (#628, Eintrag in .atlas).

interface

uses
  System.SysUtils,
  System.Types,
  System.Classes,
  Vcl.Controls,
  Vcl.ExtCtrls,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.TestUnit;

type
  /// <summary>Laufende Sitzung oder nil; startet keinen Server.</summary>
  TAtlasTestUnitLensSessionFunc = reference to function: TLspSession;

  TAtlasEditorTestUnitLens = class
  private class var
    FOnSwitchTestUnit: TProc;
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;
  private const
    QuietMs = 500;
    TimeoutMs = 800;
    RetryMs = 5000;
    RefreshMs = 10000;
  private
    FSession: TAtlasTestUnitLensSessionFunc;
    FTimer: TTimer;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FFileName: string;
    FText: string;
    FChangedAt: Cardinal;
    FFetchedAt: Cardinal;
    FRetryAt: Cardinal;
    /// <summary>Textstand, zu dem FInfo gehört; '' wenn keiner.</summary>
    FFetchedText: string;
    FFetchedFile: string;
    FInfo: TAtlasTestUnitInfo;
    FLine: Integer;
    FShowing: Boolean;
    /// <summary>Gezeichnete Marke (Koordinaten des Editors) und die oberste sichtbare Zeile dabei.</summary>
    FLensRect: TRect;
    FLensTopRow: Integer;
    procedure Tick(Sender: TObject);
    procedure Fetch;
    procedure Clear;
    function Caption: string;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    class procedure Invalidate; static;
  public
    constructor Create(const ASession: TAtlasTestUnitLensSessionFunc);
    destructor Destroy; override;
    /// <summary>Klick auf die Lens: zwischen Unit und Testunit wechseln (Editorbefehle). Setzt die Composition
    /// (A-09: die Lens importiert die Editorbefehle nicht); nil = Klick ohne Wirkung.</summary>
    class property OnSwitchTestUnit: TProc read FOnSwitchTestUnit write FOnSwitchTestUnit;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Core.Diagnostics.MainThread,
  Winapi.Windows,
  System.Math,
  System.JSON,
  Vcl.Graphics,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Pairs,
  Atlas.UI.Strings,
  Atlas.Core.Editor.Elements,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Foundation.EditorRefresh;

const
  TestUnitCommand = 'atlas.server.testUnit';

{ TAtlasEditorTestUnitLens.TEvents }

function TAtlasEditorTestUnitLens.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents, cevMouseEvents];
end;

function TAtlasEditorTestUnitLens.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasEditorTestUnitLens }

constructor TAtlasEditorTestUnitLens.Create(const ASession: TAtlasTestUnitLensSessionFunc);
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FSession := ASession;
  FIndex := -1;
  FLine := -1;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  FEvents.OnEditorMouseDown := EditorMouseDown;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 250;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasEditorTestUnitLens.Destroy;
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
  inherited Destroy;
end;

class procedure TAtlasEditorTestUnitLens.Invalidate;
var
  Services: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    TAtlasIdeEditorRefresh.InvalidateTop(Services);
end;

function Wanted(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.Enabled and ASettings.CodeLensTestUnit and
    not TAtlasGuard.Disabled(TAtlasFeature.CodeLens);
end;

procedure TAtlasEditorTestUnitLens.Clear;
begin
  FInfo := Default(TAtlasTestUnitInfo);
  FFetchedText := '';
  FFetchedFile := '';
  FLine := -1;
  FLensRect := TRect.Empty;
  if FShowing then
  begin
    FShowing := False;
    Invalidate;
  end;
end;

procedure TAtlasEditorTestUnitLens.Tick(Sender: TObject);
var
  Editors: IOTAEditorServices;
  View: IOTAEditView;
  Text: string;
  Moment: Cardinal;
begin
  try
    if not Wanted(TAtlasIdeSettings.Current) then
    begin
      Clear;
      Exit;
    end;
    View := nil;
    if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
      View := Editors.TopView;
    if (View = nil) or (View.Buffer = nil) or not SameText(ExtractFileExt(View.Buffer.FileName), '.pas') then
      Exit;
    Text := TAtlasEditorBuffer.Text(View.Buffer);
    if not SameText(FFileName, View.Buffer.FileName) or (FText <> Text) then
    begin
      FFileName := View.Buffer.FileName;
      FText := Text;
      FChangedAt := GetTickCount;
      Exit;
    end;
    Moment := GetTickCount;
    if (Moment - FChangedAt < QuietMs) or (Moment < FRetryAt) then
      Exit;
    // Gleicher Stand schon gefragt: nur ab und zu neu (Testunit inzwischen angelegt).
    if SameText(FFetchedFile, FFileName) and (FFetchedText = FText) and (Moment - FFetchedAt < RefreshMs) then
      Exit;
    Fetch;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.CodeLens, E);
  end;
end;

procedure TAtlasEditorTestUnitLens.Fetch;
var
  Session: TLspSession;
  Values: TJSONArray;
  Arguments: string;
  Answer: TJSONValue;
  Info: TAtlasTestUnitInfo;
  Line: Integer;
  Percent: Integer;
begin
  Line := TAtlasTestUnits.UnitLine(FText.Replace(#13#10, #10).Split([#10]));
  if Line < 0 then
  begin
    Clear;
    FFetchedFile := FFileName;
    FFetchedText := FText;
    FFetchedAt := GetTickCount;
    Exit;
  end;
  Session := FSession();
  if Session = nil then
    Exit;
  // Server indexiert: Er antwortet erst danach, der Hauptthread würde warten (#874). Später noch einmal.
  if Session.Indexing(Percent) then
  begin
    FRetryAt := GetTickCount + RetryMs;
    Exit;
  end;
  Values := TJSONArray.Create;
  try
    Values.Add(TLspSession.PathToUri(FFileName));
    Values.Add(Line);
    Arguments := Values.ToJSON;
  finally
    Values.Free;
  end;
  try
    Session.Sync(FFileName, FText);
    Answer := Session.RunCommand(TestUnitCommand, Arguments, TimeoutMs);
  except
    on E: ELspClientError do
    begin
      // Server beschäftigt oder weg: später noch einmal, ohne den Editor zu bremsen.
      FRetryAt := GetTickCount + RetryMs;
      Exit;
    end;
  end;
  try
    Info := TAtlasTestUnitInfo.FromJson(Answer,
      function(AUri: string): string
      begin
        Result := TLspSession.UriToPath(AUri);
      end);
  finally
    Answer.Free;
  end;
  FFetchedFile := FFileName;
  FFetchedText := FText;
  FFetchedAt := GetTickCount;
  if (Info.Lens = FInfo.Lens) and (Info.Counterpart = FInfo.Counterpart) and (Line = FLine) then
    Exit;
  FInfo := Info;
  FLine := Line;
  FShowing := Info.Lens <> TAtlasTestUnitLens.None;
  Invalidate;
end;

function TAtlasEditorTestUnitLens.Caption: string;
begin
  case FInfo.Lens of
    TAtlasTestUnitLens.ToTest:
      Result := TAtlasStrings.Fmt(TAtlasTextId.TestUnitLensTest, [FInfo.Counterpart]);
    TAtlasTestUnitLens.ToUnit:
      Result := TAtlasStrings.Fmt(TAtlasTextId.TestUnitLensUnit, [FInfo.Counterpart]);
    TAtlasTestUnitLens.CreateTest:
      Result := TAtlasStrings.Fmt(TAtlasTextId.TestUnitLensCreate, [FInfo.Counterpart]);
  else
    Result := '';
  end;
end;

procedure TAtlasEditorTestUnitLens.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  Text, Line: string;
  LineState: INTACodeEditorLineState;
  TabWidth, Width, Height, Top, Column: Integer;
  Colors: TAtlasColors;
  Canvas: TCanvas;
  Cell, Pill: TRect;
  OldFont: TFont;
  OldBrush: TBrush;
  OldPen: TPen;
  Back: TAtlasColor;
  Sample: COLORREF;
begin
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or not FShowing then
    Exit;
  try
    if not Wanted(TAtlasIdeSettings.Current) then
      Exit;
    if (Context.LogicalLineNum - 1 <> FLine) or not SameText(Context.FileName, FFetchedFile) then
      Exit;
    // In dieser Datei ausgeblendet (#628): keine Marke, kein Klickziel.
    if TAtlasIdeElements.FileHidden(TAtlasDrawnElement.CodeLensTestUnit, Context.FileName) then
    begin
      FLensRect := TRect.Empty;
      Exit;
    end;
    Text := Caption;
    LineState := Context.LineState;
    if (Text = '') or (LineState = nil) or (Context.EditView = nil) or (Context.EditView.Buffer = nil) then
      Exit;
    Line := LineState.Text;
    // Nur über einer echten Zeile „unit …“ (Text kann seit dem Abruf verschoben sein).
    if TAtlasTestUnits.UnitLine([Line]) <> 0 then
      Exit;
    TabWidth := TAtlasEditorBuffer.TabWidth(Context.EditView.Buffer);
    Column := Length(TrimRight(TAtlasPairs.DisplayLine(Line, TabWidth))) + 1;
    Cell := Context.EditorState.GetCharacterPosPx(Column + 3, Context.EditorLineNum);
    Canvas := Context.Canvas;
    Sample := GetPixel(Canvas.Handle, Cell.Left, Rect.Top + 1);
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
      Canvas.Font.Style := [fsUnderline];
      Canvas.Font.Color := TColor(TAtlasColorMath.Mix(Colors.Accent, Back, 0.85));
      Canvas.Pen.Color := TColor(TAtlasColorMath.Mix(Colors.Accent, Back, 0.35));
      Canvas.Brush.Color := TColor(TAtlasColorMath.Mix(Colors.Accent, Back, 0.12));
      Height := Canvas.TextHeight('Xg');
      Width := Canvas.TextWidth(Text);
      Top := Rect.Top + Max(0, (Rect.Bottom - Rect.Top - Height - 2) div 2);
      Pill := TRect.Create(Cell.Left, Top, Cell.Left + Width + 10, Top + Height + 2);
      Canvas.Brush.Style := bsSolid;
      Canvas.RoundRect(Pill.Left, Pill.Top, Pill.Right, Pill.Bottom, 6, 6);
      Canvas.Brush.Style := bsClear;
      Canvas.TextOut(Pill.Left + 5, Pill.Top + 1, Text);
      FLensRect := Pill;
      FLensTopRow := Context.EditView.TopRow;
      TAtlasIdeElements.Painted(TAtlasDrawnElement.CodeLensTestUnit, Context.FileName, FLine, '', Pill,
        FLensTopRow, Rect.Height);
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
      TAtlasGuard.Report(TAtlasFeature.CodeLens, E);
  end;
end;

procedure TAtlasEditorTestUnitLens.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Editors: IOTAEditorServices;
  View: IOTAEditView;
begin
  if (Button <> mbLeft) or (Shift * [ssShift, ssCtrl, ssAlt] <> []) or not FShowing or
    not PtInRect(FLensRect, Point(X, Y)) then
    Exit;
  // Nur, wenn die Marke noch dort steht: gleiche Datei, nicht gescrollt.
  View := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    View := Editors.TopView;
  if (View = nil) or (View.Buffer = nil) or not SameText(View.Buffer.FileName, FFetchedFile) or
    (View.TopRow <> FLensTopRow) then
    Exit;
  // Erst nach dem Mausereignis: der Editor setzt sonst den Cursor nach dem Wechsel.
  TAtlasMainThread.ForceQueue(TAtlasFeature.CodeLens,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.CodeLens,
        procedure
        begin
          if Assigned(FOnSwitchTestUnit) then
            FOnSwitchTestUnit();
        end);
      // Neu fragen: eine angelegte Testunit ändert die Lens.
      FFetchedAt := 0;
    end);
end;

end.
