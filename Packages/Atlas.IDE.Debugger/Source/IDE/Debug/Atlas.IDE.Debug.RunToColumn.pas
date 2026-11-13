unit Atlas.IDE.Debug.RunToColumn;

// Spalte „Bis hier ausführen“ im Rand (#851): Solange das Programm angehalten
// ist und debug.runToClick an ist, fordert Atlas über
// INTACodeEditorServices280.RequestGutterColumn eine schmale Spalte rechts
// der Zeilennummern an; läuft das Programm wieder, verschwindet sie.
// - Unter dem Mauszeiger zeigt die Spalte ▶, wenn die Zeile ausführbaren Code
//   hat (TAtlasRunTo.CodeLine auf dem Text des Editors).
// - Klick: bis hier ausführen; Strg+Klick: dabei andere Haltepunkte
//   überspringen (TAtlasIdeRunTo.RunToLine). Rechtsklick merkt die Zeile für
//   die Befehle im Kontextmenü (TAtlasIdeGutterMarks.RememberLine).
// - Nach kurzem Verweilen ein Tooltip mit den Tastenhinweisen.
// Gesichert über TAtlasFeature.Debugger. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Types,
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.ExtCtrls,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Editor.MethodToggle,
  Atlas.UI.Popup.TitledTip;

type
  TAtlasIdeRunToColumn = class
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedGutterStages: TPaintGutterStages; override;
    end;
    /// <summary>Gezeichnete Zeile der Spalte (Koordinaten des Editors).</summary>
    TRow = record
      FileName: string;
      /// <summary>0-basiert.</summary>
      Line: Integer;
      Rect: TRect;
      TopRow: Integer;
    end;
  private const
    cHoverMs = 400;
    cTickMs = 100;
    cTextMs = 500;
  private class var
    FInstance: TAtlasIdeRunToColumn;
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
    FRows: TDictionary<Integer, TRow>;
    FHover: TRow;
    FHovering: Boolean;
    FHoverSince: UInt64;
    FHoverScreen: TRect;
    // Text der oberen Datei für CodeLine, höchstens alle cTextMs gelesen.
    FCodeFile: string;
    FCodeText: string;
    FCodeLines: TArray<string>;
    FCodePlaces: TArray<TAtlasMethodPlace>;
    FCodeReadAt: UInt64;
    function Wanted: Boolean;
    procedure EnsureColumn;
    procedure DropColumn;
    procedure Tick(Sender: TObject);
    procedure ReadText;
    function IsCode(const AFileName: string; ALine: Integer): Boolean;
    function RowAt(AX, AY: Integer; out ARow: TRow): Boolean;
    procedure PaintGutter(const Rect: TRect; const Stage: TPaintGutterStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure CheckHover;
    procedure HideTip;
    procedure Leave;
  public
    constructor Create;
    destructor Destroy; override;
    class procedure Install; static;
    class procedure Uninstall; static;
    class function Installed: Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Vcl.Forms,
  Vcl.Graphics,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.GutterColumn,
  Atlas.Core.Editor.LineAnchor,
  Atlas.Core.Debug.RunTo,
  Atlas.UI.Debug.Strings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.EditorRefresh,
  Atlas.IDE.Foundation.GutterColumns,
  Atlas.IDE.Foundation.GutterMarks,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.RunTo;

const
  /// <summary>Kleinste Kantenlänge des ▶ und Abstand zum Rand der Zelle (Pixel).</summary>
  cMinArrow = 6;
  cArrowPad = 4;
  /// <summary>Abstand des Tooltips zur Zelle (Pixel).</summary>
  cTipGap = 4;

function Services: INTACodeEditorServices280;
begin
  if not Supports(BorlandIDEServices, INTACodeEditorServices280, Result) then
  begin
    Result := nil;
  end;
end;

function TopView: IOTAEditView;
var
  mEditors: IOTAEditorServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    Result := mEditors.TopView;
  end;
end;

/// <summary>▶ in ARect, Farbe aus dem Grund der Spalte; Pinsel und Stift der IDE bleiben erhalten.</summary>
procedure PaintArrow(ACanvas: TCanvas; const ARect: TRect);
var
  mSample: COLORREF;
  mBack: TAtlasColor;
  mOldBrush: TBrush;
  mOldPen: TPen;
  mSize, mLeft, mTop: Integer;
begin
  mSample := GetPixel(ACanvas.Handle, ARect.Left + 1, ARect.Top + 1);
  mBack := TAtlasColor(mSample);
  if mSample = CLR_INVALID then
  begin
    mBack := TAtlasColor(ColorToRGB(ACanvas.Brush.Color));
  end;
  mSize := Max(cMinArrow, Min(ARect.Width, ARect.Height) - cArrowPad);
  mLeft := ARect.Left + (ARect.Width - mSize) div 2;
  mTop := ARect.Top + (ARect.Height - mSize) div 2;
  mOldBrush := TBrush.Create;
  mOldPen := TPen.Create;
  try
    mOldBrush.Assign(ACanvas.Brush);
    mOldPen.Assign(ACanvas.Pen);
    ACanvas.Pen.Width := 1;
    ACanvas.Pen.Color := TColor(TAtlasColors.ForBackground(mBack).Accent);
    ACanvas.Brush.Color := ACanvas.Pen.Color;
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Polygon([Point(mLeft, mTop), Point(mLeft + mSize - 1, mTop + mSize div 2),
      Point(mLeft, mTop + mSize - 1)]);
  finally
    ACanvas.Brush.Assign(mOldBrush);
    ACanvas.Pen.Assign(mOldPen);
    mOldPen.Free;
    mOldBrush.Free;
  end;
end;

{ TAtlasIdeRunToColumn.TEvents }

function TAtlasIdeRunToColumn.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintGutterEvents, cevMouseEvents];
end;

function TAtlasIdeRunToColumn.TEvents.AllowedGutterStages: TPaintGutterStages;
begin
  // Nur die letzte Stufe: Die Spalte ist dann schon vom Grund der Rinne gefüllt.
  Result := [High(TPaintGutterStage)];
end;

{ TAtlasIdeRunToColumn }

class procedure TAtlasIdeRunToColumn.Install;
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeRunToColumn.Create;
  end;
end;

class procedure TAtlasIdeRunToColumn.Uninstall;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeRunToColumn.Installed: Boolean;
begin
  Result := FInstance <> nil;
end;

constructor TAtlasIdeRunToColumn.Create;
var
  mEditors: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FColumn := -1;
  FRows := TDictionary<Integer, TRow>.Create;
  FTip := TAtlasTitledTip.Create(nil);
  FTip.GuardFeature := TAtlasFeature.Debugger;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintGutter := PaintGutter;
  FEvents.OnEditorMouseMove := EditorMouseMove;
  FEvents.OnEditorMouseDown := EditorMouseDown;
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
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasIdeRunToColumn.Destroy;
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
    FEvents.OnEditorMouseMove := nil;
    FEvents.OnEditorMouseDown := nil;
  end;
  FEventsRef := nil;
  FTip.Free;
  FRows.Free;
  inherited Destroy;
end;

function TAtlasIdeRunToColumn.Wanted: Boolean;
begin
  Result := (FIndex >= 0) and not TAtlasGuard.Disabled(TAtlasFeature.Debugger) and TAtlasIdeRunTo.Enabled and
    (TAtlasIdeDebugSession.StoppedThread <> nil);
end;

procedure TAtlasIdeRunToColumn.EnsureColumn;
var
  mEditors: INTACodeEditorServices280;
begin
  if FWantedWidth <= 0 then
  begin
    FWantedWidth := TAtlasGutterColumn.Width(MulDiv(TAtlasGutterColumn.cBaseWidth, Screen.PixelsPerInch, 96));
  end;
  if (FColumn >= 0) and (FWidth = FWantedWidth) then
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

procedure TAtlasIdeRunToColumn.DropColumn;
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

procedure TAtlasIdeRunToColumn.Tick(Sender: TObject);
begin
  try
    if not Wanted then
    begin
      Leave;
      DropColumn;
      FCodeFile := '';
      Exit;
    end;
    EnsureColumn;
    ReadText;
    CheckHover;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

procedure TAtlasIdeRunToColumn.ReadText;
var
  mView: IOTAEditView;
  mText: string;
begin
  mView := TopView;
  if (mView = nil) or (mView.Buffer = nil) or
    (SameText(FCodeFile, mView.Buffer.FileName) and (TThread.GetTickCount64 - FCodeReadAt < cTextMs)) then
  begin
    Exit;
  end;
  FCodeReadAt := TThread.GetTickCount64;
  mText := TAtlasEditorBuffer.Text(mView.Buffer);
  if SameText(FCodeFile, mView.Buffer.FileName) and (mText = FCodeText) then
  begin
    Exit;
  end;
  FCodeFile := mView.Buffer.FileName;
  FCodeText := mText;
  FCodeLines := TAtlasLineAnchors.Lines(mText);
  FCodePlaces := TAtlasMethodToggle.Places(mText);
end;

function TAtlasIdeRunToColumn.IsCode(const AFileName: string; ALine: Integer): Boolean;
begin
  Result := SameText(AFileName, FCodeFile) and TAtlasRunTo.CodeLine(FCodeLines, FCodePlaces, ALine);
end;

procedure TAtlasIdeRunToColumn.PaintGutter(const Rect: TRect; const Stage: TPaintGutterStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mRow: TRow;
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
    mRow := Default(TRow);
    mRow.FileName := Context.FileName;
    mRow.Line := Context.LogicalLineNum - 1;
    mRow.TopRow := Context.EditView.TopRow;
    mRow.Rect := Context.EditorState.GetGutterColumnRect(Context.EditControl, Context.EditorLineNum, FColumn);
    FRows.AddOrSetValue(Context.EditorLineNum, mRow);
    if FHovering and SameText(FHover.FileName, mRow.FileName) and (FHover.Line = mRow.Line) and
      not mRow.Rect.IsEmpty and IsCode(mRow.FileName, mRow.Line) then
    begin
      PaintArrow(Context.Canvas, mRow.Rect);
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

function TAtlasIdeRunToColumn.RowAt(AX, AY: Integer; out ARow: TRow): Boolean;
var
  mRow: TRow;
  mView: IOTAEditView;
begin
  ARow := Default(TRow);
  Result := False;
  mView := TopView;
  if (mView = nil) or (mView.Buffer = nil) then
  begin
    Exit;
  end;
  for mRow in FRows.Values do
  begin
    if (mRow.Line >= 0) and PtInRect(mRow.Rect, Point(AX, AY)) then
    begin
      // Nur, wenn die Zeile noch dort steht: gleiche Datei, nicht gescrollt.
      Result := SameText(mRow.FileName, mView.Buffer.FileName) and (mRow.TopRow = mView.TopRow);
      ARow := mRow;
      Exit;
    end;
  end;
end;

procedure TAtlasIdeRunToColumn.EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
var
  mRow: TRow;
begin
  try
    if not Wanted or not RowAt(X, Y, mRow) or not IsCode(mRow.FileName, mRow.Line) then
    begin
      Leave;
      Exit;
    end;
    if FHovering and SameText(FHover.FileName, mRow.FileName) and (FHover.Line = mRow.Line) then
    begin
      Exit;
    end;
    HideTip;
    FHover := mRow;
    FHovering := True;
    FHoverSince := TThread.GetTickCount64;
    FHoverScreen := TRect.Create(Editor.ClientToScreen(mRow.Rect.TopLeft),
      Editor.ClientToScreen(mRow.Rect.BottomRight));
    TAtlasIdeEditorRefresh.InvalidateTop(Services);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

procedure TAtlasIdeRunToColumn.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  mRow: TRow;
begin
  try
    if not Wanted or not RowAt(X, Y, mRow) then
    begin
      Exit;
    end;
    if Button = mbRight then
    begin
      // Gilt für „Bis hier …“ und „Einmaliger Haltepunkt“ im Kontextmenü.
      TAtlasIdeGutterMarks.RememberLine(mRow.FileName, mRow.Line);
    end
    else if (Button = mbLeft) and IsCode(mRow.FileName, mRow.Line) then
    begin
      Leave;
      TAtlasIdeRunTo.RunToLine(mRow.FileName, mRow.Line, ssCtrl in Shift);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Debugger, E);
  end;
end;

procedure TAtlasIdeRunToColumn.CheckHover;
begin
  if not FHovering then
  begin
    Exit;
  end;
  // Maus hat die Zeile verlassen, ohne dass der Editor es gemeldet hat (anderes Fenster).
  if not PtInRect(FHoverScreen, Mouse.CursorPos) then
  begin
    Leave;
  end
  else if not FTip.IsShown and (TThread.GetTickCount64 - FHoverSince >= cHoverMs) then
  begin
    TAtlasIdeStyle.Apply(FTip, FHoverScreen);
    FTip.ShowNote(TAtlasDebugStrings.Text(TAtlasDebugTextId.RunToTipTitle),
      TAtlasDebugStrings.Fmt(TAtlasDebugTextId.RunToTipText, [FHover.Line + 1]),
      Point(FHoverScreen.Right + cTipGap, FHoverScreen.Bottom + cTipGap div 2));
  end;
end;

procedure TAtlasIdeRunToColumn.HideTip;
begin
  if (FTip <> nil) and FTip.IsShown then
  begin
    FTip.HidePopup;
  end;
end;

procedure TAtlasIdeRunToColumn.Leave;
begin
  HideTip;
  if FHovering then
  begin
    FHovering := False;
    TAtlasIdeEditorRefresh.InvalidateTop(Services);
  end;
end;

end.
