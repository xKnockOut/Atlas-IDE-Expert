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
  Atlas.Core.Editor.TestUnit,
  Atlas.IDE.Editor.Lens;

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
    /// <summary>Abruf; FPoll.FetchedText ist der Textstand, zu dem FInfo gehört.</summary>
    FPoll: TAtlasLensPoll;
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
  Atlas.Core.Diagnostics.MainThread,
  System.JSON,
  Vcl.Graphics,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.UI.Strings,
  Atlas.Core.Editor.Elements,
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
  begin
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
  end;
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
  begin
    Services.RemoveEditorEventsNotifier(FIndex);
  end;
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
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(Services);
  end;
end;

function Wanted(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.Enabled and ASettings.CodeLensTestUnit and
    not TAtlasGuard.Disabled(TAtlasFeature.CodeLens);
end;

procedure TAtlasEditorTestUnitLens.Clear;
begin
  FInfo := Default(TAtlasTestUnitInfo);
  FPoll.Forget;
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
  mView: IOTAEditView;
begin
  try
    if not Wanted(TAtlasIdeSettings.Current) then
    begin
      Clear;
      Exit;
    end;
    mView := TAtlasLensPoll.TopView;
    // Gleicher Stand schon gefragt: nur ab und zu neu (Testunit inzwischen angelegt).
    if (mView <> nil) and (mView.Buffer <> nil) and SameText(ExtractFileExt(mView.Buffer.FileName), '.pas') and
      FPoll.Due(mView, QuietMs, RefreshMs) then
    begin
      Fetch;
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.CodeLens, E);
  end;
end;

procedure TAtlasEditorTestUnitLens.Fetch;
var
  mAnswer: TJSONValue;
  mInfo: TAtlasTestUnitInfo;
  mLine: Integer;
begin
  mLine := TAtlasTestUnits.UnitLine(FPoll.Text.Replace(#13#10, #10).Split([#10]));
  if mLine < 0 then
  begin
    Clear;
    FPoll.Fetched;
    Exit;
  end;
  if not FPoll.Ask(FSession(), TestUnitCommand, FPoll.UriLineArguments(mLine), TimeoutMs, RetryMs, mAnswer) then
  begin
    Exit;
  end;
  try
    mInfo := TAtlasTestUnitInfo.FromJson(mAnswer,
      function(AUri: string): string
      begin
        Result := TLspSession.UriToPath(AUri);
      end);
  finally
    mAnswer.Free;
  end;
  FPoll.Fetched;
  if (mInfo.Lens = FInfo.Lens) and (mInfo.Counterpart = FInfo.Counterpart) and (mLine = FLine) then
  begin
    Exit;
  end;
  FInfo := mInfo;
  FLine := mLine;
  FShowing := mInfo.Lens <> TAtlasTestUnitLens.None;
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
  mText, mLine: string;
  mCell: TRect;
  mBack: TAtlasColor;
begin
  if not FShowing or not TAtlasLensPill.Ready(Stage, BeforeEvent, Context, FPoll.FetchedFile) then
  begin
    Exit;
  end;
  try
    if not Wanted(TAtlasIdeSettings.Current) or (Context.LogicalLineNum - 1 <> FLine) then
    begin
      Exit;
    end;
    // In dieser Datei ausgeblendet (#628): keine Marke, kein Klickziel.
    if TAtlasIdeElements.FileHidden(TAtlasDrawnElement.CodeLensTestUnit, Context.FileName) then
    begin
      FLensRect := TRect.Empty;
      Exit;
    end;
    mText := Caption;
    mLine := Context.LineState.Text;
    // Nur über einer echten Zeile „unit …“ (Text kann seit dem Abruf verschoben sein).
    if (mText = '') or (TAtlasTestUnits.UnitLine([mLine]) <> 0) then
    begin
      Exit;
    end;
    mCell := TAtlasLensPill.CellAfter(Context, mLine);
    mBack := TAtlasLensPill.BackAt(Context.Canvas, mCell.Left, Rect.Top + 1);
    FLensRect := TAtlasLensPill.Paint(Context.Canvas, Rect, mCell.Left, mText,
      TAtlasLensPillStyle.Create(TAtlasColors.ForBackground(mBack).Accent, mBack, 0.35, 0.12, [fsUnderline]));
    FLensTopRow := Context.EditView.TopRow;
    TAtlasIdeElements.Painted(TAtlasIdeElements.Target(TAtlasDrawnElement.CodeLensTestUnit, Context.FileName,
      FLine, ''), FLensRect, FLensTopRow, Rect.Height);
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.CodeLens, E);
  end;
end;

procedure TAtlasEditorTestUnitLens.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  View: IOTAEditView;
begin
  if (Button <> mbLeft) or (Shift * [ssShift, ssCtrl, ssAlt] <> []) or not FShowing or
    not PtInRect(FLensRect, Point(X, Y)) then
  begin
    Exit;
  end;
  // Nur, wenn die Marke noch dort steht: gleiche Datei, nicht gescrollt.
  View := TAtlasLensPoll.TopView;
  if (View = nil) or (View.Buffer = nil) or not SameText(View.Buffer.FileName, FPoll.FetchedFile) or
    (View.TopRow <> FLensTopRow) then
  begin
    Exit;
  end;
  // Erst nach dem Mausereignis: der Editor setzt sonst den Cursor nach dem Wechsel.
  TAtlasMainThread.ForceQueue(TAtlasFeature.CodeLens,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.CodeLens,
        procedure
        begin
          if Assigned(FOnSwitchTestUnit) then
          begin
            FOnSwitchTestUnit();
          end;
        end);
      // Neu fragen: eine angelegte Testunit ändert die Lens.
      FPoll.FetchedAt := 0;
    end);
end;

end.
