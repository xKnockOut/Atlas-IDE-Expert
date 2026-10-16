unit Atlas.IDE.Tests.Lens;

// Code Lens „Test ausführen“ an [TestFixture] und [Test] (#69).
// - Erkennen: Ein Zeitgeber prüft den oberen Editor. Nach einer Tipp-Pause
//   liest er Fixtures und Tests der Unit mit Atlas.Text.DUnitX (lokal, ohne
//   Server; dieselbe Erkennung wie das MCP-Werkzeug run_tests und #154).
// - Zeichnen: hinter dem Ende der Attributzeile ([TestFixture], [Test],
//   [TestCase …]; ohne Attribut hinter der Deklaration) eine Marke „Test
//   ausführen“ bzw. „Tests der Klasse ausführen“, nach einem Lauf mit dem
//   Stand (bestanden grün, fehlgeschlagen in der Fehlerfarbe); während eines
//   Laufs „Tests laufen …“. Die Rechtecke werden je Zeile gemerkt.
// - Klick: Linksklick in eine Marke startet den Test bzw. alle Tests der
//   Fixture (--run Unit.Fixture[.Methode]) im Testprojekt der Unit.
// - Ändert sich der Stand der Läufe (TAtlasIdeTests.Version), zeichnet der
//   Zeitgeber den Editor neu.
// Abschaltbar über „Code Lens „Test ausführen““ (codeLens.tests, Schlüssel
// gemeinsam mit #585) und über „Tests ausführen“ (TestRun).

interface

uses
  System.SysUtils,
  System.Types,
  System.Classes,
  Vcl.Controls,
  Vcl.ExtCtrls,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Tests.Runner;

type
  TAtlasIdeTestsLens = class
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;

    /// <summary>Eine Marke: Fixture (Method = '') oder Test.</summary>
    TItem = record
      /// <summary>Zeile der Marke (0-basiert).</summary>
      Line: Integer;
      Fixture: string;
      Method: string;
      /// <summary>Gezeichnetes Rechteck (Koordinaten des Editors) und oberste sichtbare Zeile dabei.</summary>
      Rect: TRect;
      TopRow: Integer;
    end;
    /// <summary>Lebt, solange die Lens lebt; ein eingereihter Klick prüft es.</summary>
    TAlive = class(TInterfacedObject)
    public
      Alive: Boolean;
    end;
  private const
    QuietMs = 400;
  private
    FTests: TAtlasIdeTests;
    FAlive: TAlive;
    FAliveRef: IInterface;
    FTimer: TTimer;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FFileName: string;
    FText: string;
    FChangedAt: Cardinal;
    /// <summary>Stand, zu dem FItems gehört.</summary>
    FScannedFile: string;
    FScannedText: string;
    FUnitName: string;
    FItems: TArray<TItem>;
    FVersion: Integer;
    FShowing: Boolean;
    procedure Tick(Sender: TObject);
    procedure Scan;
    procedure Clear;
    function ItemAt(ALine: Integer): Integer;
    function Caption(const AItem: TItem; out AFailed, APassed: Boolean): string;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    class procedure Invalidate; static;
  public
    /// <summary>ATests gehört dem Aufrufer und lebt länger als die Lens.</summary>
    constructor Create(ATests: TAtlasIdeTests);
    destructor Destroy; override;
    /// <summary>Lens zeichnen? Einstellungen codeLens.tests und TestRun.</summary>
    class function Wanted(const ASettings: TAtlasPluginSettings): Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Vcl.Graphics,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Pairs,
  Atlas.Core.Tests.Run,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Settings,
  Atlas.Text.Lines,
  Atlas.Text.DUnitX;

{ TAtlasIdeTestsLens.TEvents }

function TAtlasIdeTestsLens.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents, cevMouseEvents];
end;

function TAtlasIdeTestsLens.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasIdeTestsLens }

constructor TAtlasIdeTestsLens.Create(ATests: TAtlasIdeTests);
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FTests := ATests;
  FAlive := TAlive.Create;
  FAlive.Alive := True;
  FAliveRef := FAlive;
  FIndex := -1;
  FVersion := -1;
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

destructor TAtlasIdeTestsLens.Destroy;
var
  Services: INTACodeEditorServices;
begin
  FAlive.Alive := False;
  FAliveRef := nil;
  FTimer.Free;
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.RemoveEditorEventsNotifier(FIndex);
  FEvents.OnEditorPaintLine := nil;
  FEvents.OnEditorMouseDown := nil;
  FEventsRef := nil;
  if FShowing then
    Invalidate;
  inherited Destroy;
end;

class procedure TAtlasIdeTestsLens.Invalidate;
var
  Services: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.InvalidateTopEditor;
end;

class function TAtlasIdeTestsLens.Wanted(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.Enabled and ASettings.CodeLensTests and ASettings.TestRun and
    not TAtlasGuard.Disabled(TAtlasFeature.EditorCommands);
end;

procedure TAtlasIdeTestsLens.Clear;
begin
  FItems := nil;
  FUnitName := '';
  FScannedFile := '';
  FScannedText := '';
  if FShowing then
  begin
    FShowing := False;
    Invalidate;
  end;
end;

procedure TAtlasIdeTestsLens.Tick(Sender: TObject);
var
  Editors: IOTAEditorServices;
  View: IOTAEditView;
  Text: string;
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
    end
    else if (GetTickCount - FChangedAt >= QuietMs) and
      (not SameText(FScannedFile, FFileName) or (FScannedText <> FText)) then
      Scan;
    // Lauf begonnen oder beendet: Stand neu zeichnen.
    if FShowing and (FTests.Version <> FVersion) then
    begin
      FVersion := FTests.Version;
      Invalidate;
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.EditorCommands, E);
  end;
end;

procedure TAtlasIdeTestsLens.Scan;
var
  Found: TDUnitXUnit;
  Fixture: TDUnitXFixture;
  Test: TDUnitXTest;
  Item: TItem;
  Items: TArray<TItem>;
begin
  Found := TDUnitXSource.Scan(TTextLines.SplitLines(FText));
  Items := nil;
  for Fixture in Found.Fixtures do
  begin
    Item := Default(TItem);
    Item.Line := Fixture.AttributeLine;
    Item.Fixture := Fixture.Name;
    Items := Items + [Item];
    for Test in Fixture.Tests do
    begin
      Item := Default(TItem);
      Item.Line := Test.AttributeLine;
      Item.Fixture := Fixture.Name;
      Item.Method := Test.Method;
      Items := Items + [Item];
    end;
  end;
  FScannedFile := FFileName;
  FScannedText := FText;
  FUnitName := Found.UnitName;
  if (Length(Items) = 0) and (Length(FItems) = 0) then
    Exit;
  FItems := Items;
  FShowing := Length(Items) > 0;
  FVersion := FTests.Version;
  Invalidate;
end;

function TAtlasIdeTestsLens.ItemAt(ALine: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(FItems) do
    if FItems[Index].Line = ALine then
      Exit(Index);
  Result := -1;
end;

function TAtlasIdeTestsLens.Caption(const AItem: TItem; out AFailed, APassed: Boolean): string;
var
  Status: TAtlasTestStatus;
begin
  AFailed := False;
  APassed := False;
  if FTests.Busy then
    Exit(TAtlasStrings.Text(TAtlasTextId.TestsLensRunning));
  if AItem.Method = '' then
    Result := TAtlasStrings.Text(TAtlasTextId.TestsLensRunFixture)
  else
    Result := TAtlasStrings.Text(TAtlasTextId.TestsLensRun);
  Status := FTests.StatusOf(FUnitName, AItem.Fixture, AItem.Method);
  if Status = TAtlasTestStatus.Failed then
  begin
    AFailed := True;
    Result := TAtlasStrings.Fmt(TAtlasTextId.TestsLensFailed, [Result]);
  end
  else if Status = TAtlasTestStatus.Passed then
  begin
    APassed := True;
    Result := TAtlasStrings.Fmt(TAtlasTextId.TestsLensPassed, [Result]);
  end;
end;

procedure TAtlasIdeTestsLens.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  Text, Line: string;
  LineState: INTACodeEditorLineState;
  TabWidth, Width, Height, Top, Column, Index: Integer;
  Colors: TAtlasColors;
  Canvas: TCanvas;
  Cell, Pill: TRect;
  OldFont: TFont;
  OldBrush: TBrush;
  OldPen: TPen;
  Back, Tone: TAtlasColor;
  Sample: COLORREF;
  Failed, Passed: Boolean;
begin
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or not FShowing then
    Exit;
  try
    if not Wanted(TAtlasIdeSettings.Current) or not SameText(Context.FileName, FScannedFile) then
      Exit;
    Index := ItemAt(Context.LogicalLineNum - 1);
    if Index < 0 then
      Exit;
    LineState := Context.LineState;
    if (LineState = nil) or (Context.EditView = nil) or (Context.EditView.Buffer = nil) then
      Exit;
    Line := LineState.Text;
    // Text seit dem Lesen verschoben: keine Marke an einer Leerzeile.
    if Trim(Line) = '' then
      Exit;
    Text := Caption(FItems[Index], Failed, Passed);
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
    Tone := Colors.Accent;
    if Failed then
      Tone := Colors.Error
    else if Passed then
      Tone := Colors.Add;
    OldFont := TFont.Create;
    OldBrush := TBrush.Create;
    OldPen := TPen.Create;
    try
      OldFont.Assign(Canvas.Font);
      OldBrush.Assign(Canvas.Brush);
      OldPen.Assign(Canvas.Pen);
      Canvas.Font.Size := Max(6, Canvas.Font.Size - 1);
      Canvas.Font.Style := [fsUnderline];
      Canvas.Font.Color := TColor(TAtlasColorMath.Mix(Tone, Back, 0.85));
      Canvas.Pen.Color := TColor(TAtlasColorMath.Mix(Tone, Back, 0.35));
      Canvas.Brush.Color := TColor(TAtlasColorMath.Mix(Tone, Back, 0.12));
      Height := Canvas.TextHeight('Xg');
      Width := Canvas.TextWidth(Text);
      Top := Rect.Top + Max(0, (Rect.Bottom - Rect.Top - Height - 2) div 2);
      Pill := TRect.Create(Cell.Left, Top, Cell.Left + Width + 10, Top + Height + 2);
      Canvas.Brush.Style := bsSolid;
      Canvas.RoundRect(Pill.Left, Pill.Top, Pill.Right, Pill.Bottom, 6, 6);
      Canvas.Brush.Style := bsClear;
      Canvas.TextOut(Pill.Left + 5, Pill.Top + 1, Text);
      FItems[Index].Rect := Pill;
      FItems[Index].TopRow := Context.EditView.TopRow;
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
      TAtlasGuard.Report(TAtlasFeature.EditorCommands, E);
  end;
end;

procedure TAtlasIdeTestsLens.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Editors: IOTAEditorServices;
  View: IOTAEditView;
  Index, Hit: Integer;
  FileName, Name: string;
  Tests: TAtlasIdeTests;
  Alive: TAlive;
  Keep: IInterface;
begin
  if (Button <> mbLeft) or (Shift * [ssShift, ssCtrl, ssAlt] <> []) or not FShowing or (FUnitName = '') then
    Exit;
  Hit := -1;
  for Index := 0 to High(FItems) do
    if not FItems[Index].Rect.IsEmpty and PtInRect(FItems[Index].Rect, Point(X, Y)) then
      Hit := Index;
  if Hit < 0 then
    Exit;
  // Nur, wenn die Marke noch dort steht: gleiche Datei, nicht gescrollt.
  View := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    View := Editors.TopView;
  if (View = nil) or (View.Buffer = nil) or not SameText(View.Buffer.FileName, FScannedFile) or
    (View.TopRow <> FItems[Hit].TopRow) then
    Exit;
  FileName := FScannedFile;
  Name := TDUnitXCommandLine.TestName(FUnitName, FItems[Hit].Fixture, FItems[Hit].Method);
  Tests := FTests;
  Alive := FAlive;
  Keep := FAliveRef;
  // Erst nach dem Mausereignis: der Editor setzt sonst den Cursor danach. Die Lens lebt kürzer als der Läufer:
  // Lebt sie noch, lebt auch er.
  TAtlasMainThread.ForceQueue(TAtlasFeature.EditorCommands,
    procedure
    begin
      if (Keep = nil) or not Alive.Alive then
        Exit;
      TAtlasGuard.Run(TAtlasFeature.Build,
        procedure
        begin
          Tests.RunTests(FileName, [Name]);
        end);
    end);
end;

end.
