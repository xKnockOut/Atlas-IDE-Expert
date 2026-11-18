unit Atlas.IDE.Debug.StopColumn;

// Schmale Spalte im Rand des Editors, solange das Programm angehalten ist: gemeinsamer Teil von „Bis hier
// ausführen“ (#851, Atlas.IDE.Debug.RunToColumn) und „Ausführungspfeil ziehen“ (#871,
// Atlas.IDE.Debug.NextStatementColumn).
// - Spalte über INTACodeEditorServices280.RequestGutterColumn rechts der Zeilennummern; ein Zeitgeber fordert sie
//   an, solange Wanted gilt, und gibt sie sonst zurück (auch beim Abbau eines Editorfensters, #1233).
// - Beim Zeichnen merkt sich die Spalte jede Zeile (Datei, Zeile ab 0, Rechteck) für die Maus; PaintRow zeichnet
//   den Inhalt einer Zeile.
// - Mausereignisse des Editors gehen an die virtuellen Methoden der Ableitung.
// Gesichert über TAtlasFeature.Debugger. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Types,
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.Graphics,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Debug.RunToColumnFlow,
  Atlas.UI.Popup.TitledTip;

type
  /// <summary>Gezeichnete Zeile der Spalte (Datei, Zeile ab 0, Rechteck in Koordinaten des Editors).</summary>
  TAtlasDebugStopRow = TAtlasRunToRow;

  TAtlasIdeDebugStopColumn = class
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedGutterStages: TPaintGutterStages; override;
    end;
  private const
    cTickMs = 100;
  private
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FColumn: Integer;
    FWidth: Integer;
    FWantedWidth: Integer;
    FColumnsHandle: Integer;
    FTimer: TTimer;
    FTip: TAtlasTitledTip;
    FRows: TDictionary<Integer, TAtlasDebugStopRow>;
    procedure EnsureColumn;
    procedure DropColumn;
    procedure TimerTick(Sender: TObject);
    procedure PaintGutter(const Rect: TRect; const Stage: TPaintGutterStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure MouseDown(const AEditor: TWinControl; AButton: TMouseButton; AShift: TShiftState; AX, AY: Integer);
    procedure MouseMove(const AEditor: TWinControl; AShift: TShiftState; AX, AY: Integer);
    procedure MouseUp(const AEditor: TWinControl; AButton: TMouseButton; AShift: TShiftState; AX, AY: Integer);
  protected
    /// <summary>Soll die Spalte stehen? Ohne Notifier nie.</summary>
    function Wanted: Boolean; virtual; abstract;
    /// <summary>Takt mit Spalte (alle cTickMs).</summary>
    procedure Tick; virtual;
    /// <summary>Takt, in dem die Spalte nicht gewollt ist; danach wird sie zurückgegeben.</summary>
    procedure Idle; virtual;
    /// <summary>Inhalt der Zeile ARow zeichnen (Rechteck nicht leer).</summary>
    procedure PaintRow(ACanvas: TCanvas; const ARow: TAtlasDebugStopRow); virtual; abstract;
    procedure EditorMouseDown(const AEditor: TWinControl; AButton: TMouseButton; AShift: TShiftState;
      AX, AY: Integer); virtual;
    procedure EditorMouseMove(const AEditor: TWinControl; AShift: TShiftState; AX, AY: Integer); virtual;
    procedure EditorMouseUp(const AEditor: TWinControl; AButton: TMouseButton; AShift: TShiftState;
      AX, AY: Integer); virtual;
    /// <summary>Notifier angemeldet?</summary>
    function Registered: Boolean;
    /// <summary>Gezeichnete Zeile unter AX/AY, wenn sie noch dort steht (gleiche Datei, nicht gescrollt);
    /// AAnyX: nur die Höhe zählt (beim Ziehen darf die Maus die Spalte verlassen).</summary>
    function RowAt(AX, AY: Integer; AAnyX: Boolean; out ARow: TAtlasDebugStopRow): Boolean;
    /// <summary>Rechteck von ARow auf dem Bildschirm.</summary>
    function ScreenRect(const AEditor: TWinControl; const ARow: TAtlasDebugStopRow): TRect;
    procedure HideTip;
    /// <summary>Editor neu zeichnen.</summary>
    class procedure Invalidate; static;
    /// <summary>Pfeil in ARect, Farbe aus dem Grund der Spalte: AWarn = Warnfarbe, sonst Akzent; Pinsel und Stift
    /// der IDE bleiben erhalten.</summary>
    class procedure PaintArrow(ACanvas: TCanvas; const ARect: TRect; AWarn: Boolean); static;
    property Tip: TAtlasTitledTip read FTip;
  public
    constructor Create;
    destructor Destroy; override;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.GutterColumn,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorRefresh,
  Atlas.IDE.Foundation.GutterColumns;

const
  /// <summary>Kleinste Kantenlänge des Pfeils und Abstand zum Rand der Zelle (Pixel).</summary>
  cMinArrow = 6;
  cArrowPad = 4;

function Services: INTACodeEditorServices280;
begin
  if not Supports(BorlandIDEServices, INTACodeEditorServices280, Result) then
  begin
    Result := nil;
  end;
end;

{ TAtlasIdeDebugStopColumn.TEvents }

function TAtlasIdeDebugStopColumn.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintGutterEvents, cevMouseEvents];
end;

function TAtlasIdeDebugStopColumn.TEvents.AllowedGutterStages: TPaintGutterStages;
begin
  // Nur die letzte Stufe: Die Spalte ist dann schon vom Grund der Rinne gefüllt.
  Result := [High(TPaintGutterStage)];
end;

{ TAtlasIdeDebugStopColumn }

constructor TAtlasIdeDebugStopColumn.Create;
var
  mEditors: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FColumn := -1;
  FRows := TDictionary<Integer, TAtlasDebugStopRow>.Create;
  FTip := TAtlasTitledTip.Create(nil);
  FTip.GuardFeature := TAtlasFeature.Debugger;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintGutter := PaintGutter;
  FEvents.OnEditorMouseDown := MouseDown;
  FEvents.OnEditorMouseMove := MouseMove;
  FEvents.OnEditorMouseUp := MouseUp;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mEditors) then
  begin
    FIndex := mEditors.AddEditorEventsNotifier(FEventsRef);
  end;
  FColumnsHandle := TAtlasIdeGutterColumns.Register(
    procedure
    begin
      DropColumn;
    end);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := TimerTick;
  FTimer.Enabled := True;
end;

destructor TAtlasIdeDebugStopColumn.Destroy;
var
  mEditors: INTACodeEditorServices;
begin
  FTimer.Free;
  TAtlasIdeGutterColumns.Unregister(FColumnsHandle);
  // Erst Spalte und Notifier abmelden, dann freigeben (#493).
  DropColumn;
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mEditors) then
  begin
    mEditors.RemoveEditorEventsNotifier(FIndex);
  end;
  if FEvents <> nil then
  begin
    FEvents.OnEditorPaintGutter := nil;
    FEvents.OnEditorMouseDown := nil;
    FEvents.OnEditorMouseMove := nil;
    FEvents.OnEditorMouseUp := nil;
  end;
  FEventsRef := nil;
  FTip.Free;
  FRows.Free;
  inherited Destroy;
end;

function TAtlasIdeDebugStopColumn.Registered: Boolean;
begin
  Result := FIndex >= 0;
end;

procedure TAtlasIdeDebugStopColumn.EnsureColumn;
var
  mEditors: INTACodeEditorServices280;
begin
  if FWantedWidth <= 0 then
  begin
    FWantedWidth := TAtlasGutterColumn.Width(MulDiv(TAtlasGutterColumn.cBaseWidth, Screen.PixelsPerInch, 96));
  end;
  if not TAtlasRunToColumnFlow.NeedsColumn(FColumn, FWidth, FWantedWidth) then
  begin
    Exit;
  end;
  mEditors := Services;
  // Kurz nach dem Abbau eines Editorfensters nicht wieder anfordern (#1233).
  if (mEditors = nil) or not TAtlasIdeGutterColumns.Allowed then
  begin
    Exit;
  end;
  DropColumn;
  FColumn := mEditors.RequestGutterColumn(FIndex, FWantedWidth, gclAfterLineNumbers);
  FWidth := FWantedWidth;
  FRows.Clear;
  TAtlasIdeEditorRefresh.InvalidateTop(mEditors);
end;

procedure TAtlasIdeDebugStopColumn.DropColumn;
var
  mEditors: INTACodeEditorServices280;
begin
  if FColumn < 0 then
  begin
    Exit;
  end;
  mEditors := Services;
  if mEditors <> nil then
  begin
    mEditors.RemoveGutterColumn(FColumn);
    TAtlasIdeEditorRefresh.InvalidateTop(mEditors);
  end;
  FColumn := -1;
  FRows.Clear;
end;

procedure TAtlasIdeDebugStopColumn.TimerTick(Sender: TObject);
begin
  try
    if not Wanted then
    begin
      Idle;
      DropColumn;
      Exit;
    end;
    EnsureColumn;
    Tick;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

procedure TAtlasIdeDebugStopColumn.Tick;
begin
end;

procedure TAtlasIdeDebugStopColumn.Idle;
begin
end;

/// <summary>Liegt AX/AY in ARow? AAnyX: nur die Höhe zählt.</summary>
function Hit(const ARow: TAtlasRunToRow; AX, AY: Integer; AAnyX: Boolean): Boolean;
begin
  Result := (ARow.Line >= 0) and (AY >= ARow.Rect.Top) and (AY < ARow.Rect.Bottom);
  if Result and not AAnyX then
  begin
    Result := (AX >= ARow.Rect.Left) and (AX < ARow.Rect.Right);
  end;
end;

function TAtlasIdeDebugStopColumn.RowAt(AX, AY: Integer; AAnyX: Boolean; out ARow: TAtlasDebugStopRow): Boolean;
var
  mRow: TAtlasRunToRow;
  mView: IOTAEditView;
begin
  ARow := Default(TAtlasDebugStopRow);
  Result := False;
  mView := TAtlasEditorBuffer.TopView;
  if (mView = nil) or (mView.Buffer = nil) then
  begin
    Exit;
  end;
  for mRow in FRows.Values do
  begin
    if Hit(mRow, AX, AY, AAnyX) then
    begin
      // Nur, wenn die Zeile noch dort steht: gleiche Datei, nicht gescrollt.
      Result := TAtlasRunToColumnFlow.StillThere(mRow, mView.Buffer.FileName, mView.TopRow);
      ARow := mRow;
      Exit;
    end;
  end;
end;

function TAtlasIdeDebugStopColumn.ScreenRect(const AEditor: TWinControl; const ARow: TAtlasDebugStopRow): TRect;
begin
  Result := TRect.Create(AEditor.ClientToScreen(ARow.Rect.TopLeft), AEditor.ClientToScreen(ARow.Rect.BottomRight));
end;

procedure TAtlasIdeDebugStopColumn.PaintGutter(const Rect: TRect; const Stage: TPaintGutterStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mRow: TAtlasRunToRow;
begin
  if BeforeEvent or (Stage <> High(TPaintGutterStage)) or (FColumn < 0) or (Context = nil) then
  begin
    Exit;
  end;
  try
    if (Context.EditView = nil) or (Context.EditorState = nil) or not Wanted then
    begin
      Exit;
    end;
    // Schrift oder Skalierung geändert: Der Zeitgeber fordert die Spalte neu an.
    if Context.CellSize.cy > 0 then
    begin
      FWantedWidth := TAtlasGutterColumn.Width(Context.CellSize.cy);
    end;
    mRow := Default(TAtlasDebugStopRow);
    mRow.FileName := Context.FileName;
    mRow.Line := Context.LogicalLineNum - 1;
    mRow.TopRow := Context.EditView.TopRow;
    mRow.Rect := Context.EditorState.GetGutterColumnRect(Context.EditControl, Context.EditorLineNum, FColumn);
    FRows.AddOrSetValue(Context.EditorLineNum, mRow);
    if not mRow.Rect.IsEmpty then
    begin
      PaintRow(Context.Canvas, mRow);
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

procedure TAtlasIdeDebugStopColumn.MouseDown(const AEditor: TWinControl; AButton: TMouseButton;
  AShift: TShiftState; AX, AY: Integer);
begin
  try
    EditorMouseDown(AEditor, AButton, AShift, AX, AY);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

procedure TAtlasIdeDebugStopColumn.MouseMove(const AEditor: TWinControl; AShift: TShiftState; AX, AY: Integer);
begin
  try
    EditorMouseMove(AEditor, AShift, AX, AY);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

procedure TAtlasIdeDebugStopColumn.MouseUp(const AEditor: TWinControl; AButton: TMouseButton;
  AShift: TShiftState; AX, AY: Integer);
begin
  try
    EditorMouseUp(AEditor, AButton, AShift, AX, AY);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

procedure TAtlasIdeDebugStopColumn.EditorMouseDown(const AEditor: TWinControl; AButton: TMouseButton;
  AShift: TShiftState; AX, AY: Integer);
begin
end;

procedure TAtlasIdeDebugStopColumn.EditorMouseMove(const AEditor: TWinControl; AShift: TShiftState; AX, AY: Integer);
begin
end;

procedure TAtlasIdeDebugStopColumn.EditorMouseUp(const AEditor: TWinControl; AButton: TMouseButton;
  AShift: TShiftState; AX, AY: Integer);
begin
end;

procedure TAtlasIdeDebugStopColumn.HideTip;
begin
  if (FTip <> nil) and FTip.IsShown then
  begin
    FTip.HidePopup;
  end;
end;

class procedure TAtlasIdeDebugStopColumn.Invalidate;
begin
  TAtlasIdeEditorRefresh.InvalidateTop(Services);
end;

class procedure TAtlasIdeDebugStopColumn.PaintArrow(ACanvas: TCanvas; const ARect: TRect; AWarn: Boolean);
var
  mSample: COLORREF;
  mBack: TAtlasColor;
  mColors: TAtlasColors;
  mOldBrush: TBrush;
  mOldPen: TPen;
begin
  mSample := GetPixel(ACanvas.Handle, ARect.Left + 1, ARect.Top + 1);
  mBack := TAtlasColor(mSample);
  if mSample = CLR_INVALID then
  begin
    mBack := TAtlasColor(ColorToRGB(ACanvas.Brush.Color));
  end;
  mColors := TAtlasColors.ForBackground(mBack);
  mOldBrush := TBrush.Create;
  mOldPen := TPen.Create;
  try
    mOldBrush.Assign(ACanvas.Brush);
    mOldPen.Assign(ACanvas.Pen);
    ACanvas.Pen.Width := 1;
    ACanvas.Pen.Color := TColor(mColors.Accent);
    if AWarn then
    begin
      ACanvas.Pen.Color := TColor(mColors.Warn);
    end;
    ACanvas.Brush.Color := ACanvas.Pen.Color;
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Polygon(TAtlasRunToColumnFlow.Arrow(ARect, cMinArrow, cArrowPad));
  finally
    ACanvas.Brush.Assign(mOldBrush);
    ACanvas.Pen.Assign(mOldPen);
    mOldPen.Free;
    mOldBrush.Free;
  end;
end;

end.
