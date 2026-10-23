unit Atlas.IDE.Bookmarks.QuickColumn;

// Spalte der schnellen Lesezeichen (#1104) direkt links der Zeilennummern:
// eine eigene Spalte der Rinne über INTACodeEditorServices280.RequestGutterColumn
// (gclBeforeLineNumbers, wie die Atlas-Spalte #768 rechts der Zahlen).
// Haltepunkte, Faltung und Änderungsbalken bleiben in den Spalten der IDE.
// - Marker: Band in der Warnfarbe wie bei #622, bei nummerierten mit der
//   Ziffer; mehrere an einer Zeile: kleinste Nummer vorn (ColumnMarks), eine
//   Ecke zeigt, dass es mehr sind. Die Zeilennummer einer Zeile mit Marker
//   wird hell nachgezeichnet: in der Stufe, deren Rechteck rechts an die
//   Spalte grenzt (die Zeilennummern; welche Stufe das ist, beim ersten Bau
//   prüfen).
// - Linksklick (bookmarks.quick.gutterClick): Die Nachricht wird vor dem
//   Editor abgefangen (TApplicationEvents.OnMessage), die IDE bekommt den
//   Klick also nicht und setzt keinen Haltepunkt; freier Platz setzt ein
//   unnummeriertes Lesezeichen, ein Marker entfernt die Marker der Zeile.
// - Überfahren: gestrichelter Umriss auf freiem Platz, nach HoverMs ein
//   Tooltip mit Nummer, Name bzw. Methode und Sprungtaste aller Marker.
// - Rechtsklick: Menü „Nummer vergeben ›“ (belegte Nummern mit Ziel),
//   „Namen geben …“, „Lesezeichen entfernen“, „Alle Lesezeichen der Datei
//   entfernen“, „Fenster ‚Lesezeichen‘ öffnen“.
// - Der Zeitgeber führt außerdem die Liste der Datei im oberen Editor nach
//   (Wiederfinden nach einer Tipp-Pause, auch ohne benannte Lesezeichen),
//   übernimmt beim ersten Öffnen die IDE-Lesezeichen 1–9 (ImportIde) und
//   nimmt Hinweise im Statusfeld wieder weg.
// Abschaltbar über bookmarks.quick und bookmarks.quick.gutter, ausblendbar am
// Element (#628). Sicherung über TAtlasFeature.QuickBookmarks (#493). Nur im
// Hauptthread.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Types,
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.ExtCtrls,
  Vcl.AppEvnts,
  Vcl.Menus,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Bookmarks.Store,
  Atlas.UI.Notes.Tip;

type
  TAtlasIdeQuickColumn = class
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedGutterStages: TPaintGutterStages; override;
    end;
    /// <summary>Gezeichnete Zeile der Spalte (Koordinaten des Editors).</summary>
    TRow = record
      Wnd: HWND;
      FileName: string;
      /// <summary>0-basiert.</summary>
      Line: Integer;
      Rect: TRect;
      TopRow: Integer;
      Marks: TArray<TAtlasBookmark>;
    end;
  private const
    HoverMs = 400;
    /// <summary>Tipp-Pause, bevor die Lesezeichen der Datei wiedergefunden werden.</summary>
    QuietMs = 600;
    MenuName = 20;
    MenuRemove = 21;
    MenuRemoveFile = 22;
    MenuWindow = 23;
  private
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FColumn: Integer;
    FWidth: Integer;
    FWantedWidth: Integer;
    FTimer: TTimer;
    FTip: TAtlasNoteTip;
    FAppEvents: TApplicationEvents;
    FMenu: TPopupMenu;
    FMenuRow: TRow;
    FRows: TDictionary<Integer, TRow>;
    /// <summary>Nach einem geschluckten Drücken auch das Loslassen schlucken (WM_LBUTTONUP, WM_RBUTTONUP).
    /// </summary>
    FSwallowUp: Cardinal;
    // Oberer Editor und Tipp-Pause.
    FFileName: string;
    FText: string;
    FChangedAt: UInt64;
    FTracked: Boolean;
    // Überfahren.
    FHover: TRow;
    FHovering: Boolean;
    FHoverSince: UInt64;
    FHoverScreen: TRect;
    function Active: Boolean;
    function Shown: Boolean;
    function TopView: IOTAEditView;
    function Services: INTACodeEditorServices280;
    procedure EnsureColumn;
    procedure DropColumn;
    procedure Tick(Sender: TObject);
    procedure Track;
    function RowAt(AWnd: HWND; X, Y: Integer; out ARow: TRow): Boolean;
    procedure PaintMarks(ACanvas: TCanvas; const ARow: TRow; const AColors: TAtlasColors; ABack: TAtlasColor);
    procedure PaintFree(ACanvas: TCanvas; const ARect: TRect; const AColors: TAtlasColors);
    procedure PaintLineNumber(ACanvas: TCanvas; const ARect: TRect; ALine: Integer; const AColors: TAtlasColors);
    procedure PaintGutter(const Rect: TRect; const Stage: TPaintGutterStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
    procedure CheckHover;
    procedure HideTip;
    procedure SetHover(const ARow: TRow; AOn: Boolean);
    procedure ShowTip(const ARow: TRow);
    procedure ShowMenu(const ARow: TRow; const APoint: TPoint);
    procedure MenuClick(Sender: TObject);
    function AddMenuItem(AParent: TMenuItem; const ACaption: string; ATag: Integer): TMenuItem;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Text des Tooltips zu den Markern einer Zeile; AJumpKey: Grundtaste für Strg+1 (0 = keine).
    /// </summary>
    class procedure TipText(const AMarks: TArray<TAtlasBookmark>; AJumpKey: Word; out ATitle, AText: string); static;
  end;

implementation

uses
  System.Math,
  Vcl.Forms,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Editor.LineAnchor,
  Atlas.Core.Bookmarks.Quick,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Bookmarks.Service;

procedure InvalidateTop;
var
  Editors: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Editors) then
    Editors.InvalidateTopEditor;
end;

function SampleBack(ACanvas: TCanvas; const ARect: TRect): TAtlasColor;
var
  Sample: COLORREF;
begin
  // Farben aus dem Grund der Rinne: hell oder dunkel wie das Thema der IDE.
  Sample := GetPixel(ACanvas.Handle, ARect.Left + 1, ARect.Top + 1);
  if Sample = CLR_INVALID then
    Result := TAtlasColor(ColorToRGB(ACanvas.Brush.Color))
  else
    Result := TAtlasColor(Sample);
end;

{ TAtlasIdeQuickColumn.TEvents }

function TAtlasIdeQuickColumn.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintGutterEvents, cevMouseEvents];
end;

function TAtlasIdeQuickColumn.TEvents.AllowedGutterStages: TPaintGutterStages;
begin
  // Alle Stufen: die letzte für die Marker, die der Zeilennummern zum Aufhellen.
  Result := [Low(TPaintGutterStage)..High(TPaintGutterStage)];
end;

{ TAtlasIdeQuickColumn }

constructor TAtlasIdeQuickColumn.Create;
var
  Editors: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FColumn := -1;
  FRows := TDictionary<Integer, TRow>.Create;
  FTip := TAtlasNoteTip.Create(nil);
  FTip.GuardFeature := TAtlasFeature.QuickBookmarks;
  FMenu := TPopupMenu.Create(nil);
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintGutter := PaintGutter;
  FEvents.OnEditorMouseMove := EditorMouseMove;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Editors) then
    FIndex := Editors.AddEditorEventsNotifier(FEventsRef);
  FAppEvents := TApplicationEvents.Create(nil);
  FAppEvents.OnMessage := AppMessage;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 100;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasIdeQuickColumn.Destroy;
var
  Editors: INTACodeEditorServices;
begin
  FTimer.Free;
  if FAppEvents <> nil then
  begin
    FAppEvents.OnMessage := nil;
    FAppEvents.Free;
  end;
  // Erst Spalte und Notifier abmelden, dann freigeben (#493).
  DropColumn;
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Editors) then
    Editors.RemoveEditorEventsNotifier(FIndex);
  if FEvents <> nil then
  begin
    FEvents.OnEditorPaintGutter := nil;
    FEvents.OnEditorMouseMove := nil;
  end;
  FEventsRef := nil;
  FMenu.Free;
  FTip.Free;
  FRows.Free;
  FMenuRow := Default(TRow);
  FHover := Default(TRow);
  inherited Destroy;
end;

function TAtlasIdeQuickColumn.Services: INTACodeEditorServices280;
begin
  if not Supports(BorlandIDEServices, INTACodeEditorServices280, Result) then
    Result := nil;
end;

function TAtlasIdeQuickColumn.Active: Boolean;
begin
  Result := (FIndex >= 0) and not TAtlasGuard.Disabled(TAtlasFeature.QuickBookmarks) and
    TAtlasIdeSettings.Current.QuickBookmarks;
end;

function TAtlasIdeQuickColumn.Shown: Boolean;
begin
  Result := Active and TAtlasIdeSettings.Current.QuickBookmarksGutter and (FColumn >= 0);
end;

function TAtlasIdeQuickColumn.TopView: IOTAEditView;
var
  Editors: IOTAEditorServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    Result := Editors.TopView;
end;

procedure TAtlasIdeQuickColumn.EnsureColumn;
var
  Editors: INTACodeEditorServices280;
begin
  if FWantedWidth <= 0 then
    FWantedWidth := TAtlasQuickBookmarks.ColumnWidth(MulDiv(20, Screen.PixelsPerInch, 96));
  if (FColumn >= 0) and (FWidth = FWantedWidth) then
    Exit;
  Editors := Services;
  if Editors = nil then
    Exit;
  DropColumn;
  // Vor den Zeilennummern: Die Spalte steht direkt links der Zahlen (beim ersten Bau prüfen).
  FColumn := Editors.RequestGutterColumn(FIndex, FWantedWidth, gclBeforeLineNumbers);
  FWidth := FWantedWidth;
  FRows.Clear;
  Editors.InvalidateTopEditor;
end;

procedure TAtlasIdeQuickColumn.DropColumn;
var
  Editors: INTACodeEditorServices280;
begin
  if FColumn < 0 then
    Exit;
  Editors := Services;
  if Editors <> nil then
  begin
    Editors.RemoveGutterColumn(FColumn);
    Editors.InvalidateTopEditor;
  end;
  FColumn := -1;
  FRows.Clear;
end;

procedure TAtlasIdeQuickColumn.Tick(Sender: TObject);
begin
  try
    TAtlasIdeBookmarks.ExpireStatus;
    if not Active then
    begin
      SetHover(Default(TRow), False);
      DropColumn;
      FFileName := '';
      FText := '';
      Exit;
    end;
    Track;
    if TAtlasIdeSettings.Current.QuickBookmarksGutter then
      EnsureColumn
    else
    begin
      SetHover(Default(TRow), False);
      DropColumn;
    end;
    CheckHover;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.QuickBookmarks, E);
  end;
end;

procedure TAtlasIdeQuickColumn.Track;
var
  View: IOTAEditView;
  Text: string;
begin
  View := TopView;
  if (View = nil) or (View.Buffer = nil) or (View.Buffer.FileName = '') then
    Exit;
  Text := TAtlasEditorBuffer.Text(View.Buffer);
  if not SameText(FFileName, View.Buffer.FileName) then
  begin
    // Neue Datei vorn: gleich wiederfinden und einmal je Sitzung die IDE-Lesezeichen übernehmen.
    FFileName := View.Buffer.FileName;
    FText := Text;
    FRows.Clear;
    TAtlasIdeBookmarks.Track(FFileName, FText);
    TAtlasIdeBookmarks.ImportIde(FFileName);
    FTracked := True;
    InvalidateTop;
    Exit;
  end;
  if FText <> Text then
  begin
    FText := Text;
    FChangedAt := TThread.GetTickCount64;
    FTracked := False;
    Exit;
  end;
  if FTracked or (TThread.GetTickCount64 - FChangedAt < QuietMs) then
    Exit;
  FTracked := True;
  if TAtlasIdeBookmarks.Track(FFileName, FText) then
    InvalidateTop;
end;

class procedure TAtlasIdeQuickColumn.TipText(const AMarks: TArray<TAtlasBookmark>; AJumpKey: Word;
  out ATitle, AText: string);
var
  Mark: TAtlasBookmark;
  Line: string;
  Key: Word;
begin
  ATitle := '';
  AText := '';
  if Length(AMarks) = 0 then
    Exit;
  if Length(AMarks) > 1 then
    ATitle := TAtlasStrings.Fmt(TAtlasTextId.QuickBookmarkTipMore, [Length(AMarks)])
  else if AMarks[0].Number > 0 then
    ATitle := TAtlasStrings.Fmt(TAtlasTextId.QuickBookmarkTipTitle, [AMarks[0].Number])
  else
    ATitle := TAtlasStrings.Text(TAtlasTextId.QuickBookmarkTipUnnumbered);
  for Mark in AMarks do
  begin
    Line := Mark.DisplayName;
    if Mark.Number > 0 then
    begin
      Line := IntToStr(Mark.Number) + ' · ' + Line;
      Key := TAtlasQuickBookmarks.KeyFor(AJumpKey, Mark.Number);
      if Key <> 0 then
        Line := Line + ' — ' + TAtlasStrings.Fmt(TAtlasTextId.QuickBookmarkTipJump, [ShortCutToText(TShortCut(Key))]);
    end;
    if AText <> '' then
      AText := AText + #10;
    AText := AText + Line;
  end;
end;

procedure TAtlasIdeQuickColumn.PaintMarks(ACanvas: TCanvas; const ARow: TRow; const AColors: TAtlasColors;
  ABack: TAtlasColor);
var
  Band: TRect;
  Notch, Corner: Integer;
  Digit: string;
  Size: TSize;
  OldFont: TFont;
begin
  // Band mit Kerbe unten wie bei den benannten Lesezeichen (#622), etwas breiter für die Ziffer.
  Band := ARow.Rect;
  InflateRect(Band, -1, -1);
  Notch := Max(2, Band.Height div 5);
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := TColor(TAtlasColorMath.Mix(AColors.Warn, ABack, 0.85));
  ACanvas.Pen.Color := TColor(AColors.Warn);
  ACanvas.Pen.Style := psSolid;
  ACanvas.Pen.Width := 1;
  ACanvas.Polygon([Point(Band.Left, Band.Top), Point(Band.Right - 1, Band.Top), Point(Band.Right - 1, Band.Bottom - 1),
    Point((Band.Left + Band.Right) div 2, Band.Bottom - 1 - Notch), Point(Band.Left, Band.Bottom - 1)]);
  // Mehr als ein Marker: gefüllte Ecke oben rechts.
  if Length(ARow.Marks) > 1 then
  begin
    Corner := Max(3, Band.Width div 3);
    ACanvas.Brush.Color := TColor(AColors.Warn);
    ACanvas.Polygon([Point(Band.Right - 1 - Corner, Band.Top), Point(Band.Right - 1, Band.Top),
      Point(Band.Right - 1, Band.Top + Corner)]);
  end;
  if ARow.Marks[0].Number <= 0 then
    Exit;
  Digit := IntToStr(ARow.Marks[0].Number);
  OldFont := TFont.Create;
  try
    OldFont.Assign(ACanvas.Font);
    ACanvas.Font.Style := [fsBold];
    ACanvas.Font.Height := -Max(7, (Band.Height - Notch) * 4 div 5);
    ACanvas.Font.Color := TColor(TAtlasColorMath.Mix(AColors.Text, AColors.Warn, 0.85));
    ACanvas.Brush.Style := bsClear;
    Size := ACanvas.TextExtent(Digit);
    ACanvas.TextOut(Band.Left + (Band.Width - Size.cx) div 2, Band.Top + Max(0, (Band.Height - Notch - Size.cy) div 2),
      Digit);
  finally
    ACanvas.Font.Assign(OldFont);
    OldFont.Free;
  end;
end;

procedure TAtlasIdeQuickColumn.PaintFree(ACanvas: TCanvas; const ARect: TRect; const AColors: TAtlasColors);
var
  Outline: TRect;
begin
  // Gestrichelter Umriss: Hier setzt ein Klick ein Lesezeichen.
  Outline := ARect;
  InflateRect(Outline, -1, -1);
  ACanvas.Brush.Style := bsClear;
  ACanvas.Pen.Color := TColor(AColors.Muted);
  ACanvas.Pen.Width := 1;
  ACanvas.Pen.Style := psDot;
  ACanvas.Rectangle(Outline);
  ACanvas.Pen.Style := psSolid;
end;

procedure TAtlasIdeQuickColumn.PaintLineNumber(ACanvas: TCanvas; const ARect: TRect; ALine: Integer;
  const AColors: TAtlasColors);
var
  Number: string;
  Area: TRect;
begin
  // Zahl hell auf dem Grund der Rinne neu zeichnen; Schrift ist die, mit der die IDE die Zahlen zeichnet.
  Number := IntToStr(ALine + 1);
  if ACanvas.TextWidth(Number) > ARect.Width then
    Exit;
  Area := ARect;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := TColor(AColors.Gutter);
  ACanvas.FillRect(Area);
  ACanvas.Brush.Style := bsClear;
  ACanvas.Font.Color := TColor(AColors.Text);
  Dec(Area.Right, 2);
  DrawText(ACanvas.Handle, PChar(Number), Length(Number), Area, DT_RIGHT or DT_VCENTER or DT_SINGLELINE or
    DT_NOPREFIX);
end;

procedure TAtlasIdeQuickColumn.PaintGutter(const Rect: TRect; const Stage: TPaintGutterStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  Row: TRow;
  LineState: INTACodeEditorLineState;
  LineText: string;
  HasText: Boolean;
  Canvas: TCanvas;
  Back: TAtlasColor;
  Colors: TAtlasColors;
  OldBrush: TBrush;
  OldPen: TPen;
  OldFont: TFont;
  Marks: TArray<TAtlasBookmark>;
  ColumnRect: TRect;
begin
  if BeforeEvent or (FColumn < 0) or (Context = nil) or (Context.EditView = nil) or
    (Context.EditorState = nil) or (Context.EditControl = nil) then
    Exit;
  try
    if not Shown then
      Exit;
    ColumnRect := Context.EditorState.GetGutterColumnRect(Context.EditControl, Context.EditorLineNum, FColumn);
    if ColumnRect.IsEmpty or (Context.LogicalLineNum <= 0) then
      Exit;
    LineState := Context.LineState;
    HasText := LineState <> nil;
    LineText := '';
    if HasText then
      LineText := LineState.Text;
    Marks := TAtlasIdeBookmarks.ColumnMarksAt(Context.FileName, Context.LogicalLineNum - 1);
    // Nur, wenn die Zeile im Editor noch zum Anker passt; nach dem Tippen folgt das Wiederfinden.
    if (Length(Marks) > 0) and HasText and (TAtlasLineAnchors.Normalize(LineText) <> Marks[0].Anchor.Text) then
      Marks := nil;
    // In .atlas ausgeblendet (#628): ganze Datei oder diese Codezeile.
    if (Length(Marks) > 0) and
      TAtlasIdeElements.Hidden(TAtlasDrawnElement.QuickBookmarks, Context.FileName, LineText) then
      Marks := nil;
    Canvas := Context.Canvas;
    if Stage <> High(TPaintGutterStage) then
    begin
      // Zeilennummern: die Stufe, deren Rechteck rechts an die Spalte grenzt.
      if (Length(Marks) > 0) and (Stage <> Low(TPaintGutterStage)) and (Rect.Left >= ColumnRect.Right - 1) and
        (Rect.Left <= ColumnRect.Right + 2) and (Rect.Width > 0) then
      begin
        OldBrush := TBrush.Create;
        OldFont := TFont.Create;
        try
          OldBrush.Assign(Canvas.Brush);
          OldFont.Assign(Canvas.Font);
          Back := SampleBack(Canvas, Rect);
          Colors := TAtlasColors.ForBackground(Back);
          Colors.Gutter := Back;
          PaintLineNumber(Canvas, Rect, Context.LogicalLineNum - 1, Colors);
        finally
          Canvas.Brush.Assign(OldBrush);
          Canvas.Font.Assign(OldFont);
          OldFont.Free;
          OldBrush.Free;
        end;
      end;
      Exit;
    end;
    Row := Default(TRow);
    Row.Wnd := Context.EditControl.Handle;
    Row.FileName := Context.FileName;
    Row.Line := Context.LogicalLineNum - 1;
    Row.TopRow := Context.EditView.TopRow;
    Row.Rect := ColumnRect;
    Row.Marks := Marks;
    FRows.AddOrSetValue(Context.EditorLineNum, Row);
    if (Length(Marks) = 0) and not (FHovering and TAtlasIdeSettings.Current.QuickBookmarksGutterClick and
      (FHover.Wnd = Row.Wnd) and (FHover.Line = Row.Line) and SameText(FHover.FileName, Row.FileName)) then
      Exit;
    Back := SampleBack(Canvas, Row.Rect);
    Colors := TAtlasColors.ForBackground(Back);
    OldBrush := TBrush.Create;
    OldPen := TPen.Create;
    try
      OldBrush.Assign(Canvas.Brush);
      OldPen.Assign(Canvas.Pen);
      if Length(Marks) > 0 then
        PaintMarks(Canvas, Row, Colors, Back)
      else
        PaintFree(Canvas, Row.Rect, Colors);
    finally
      Canvas.Brush.Assign(OldBrush);
      Canvas.Pen.Assign(OldPen);
      OldPen.Free;
      OldBrush.Free;
    end;
    if Length(Marks) > 0 then
      TAtlasIdeElements.Painted(TAtlasDrawnElement.QuickBookmarks, Context.FileName, Row.Line, LineText, Row.Rect,
        Row.TopRow, Row.Rect.Height);
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.QuickBookmarks, E);
  end;
end;

function TAtlasIdeQuickColumn.RowAt(AWnd: HWND; X, Y: Integer; out ARow: TRow): Boolean;
var
  Row: TRow;
  View: IOTAEditView;
begin
  ARow := Default(TRow);
  Result := False;
  View := TopView;
  if (View = nil) or (View.Buffer = nil) then
    Exit;
  for Row in FRows.Values do
    if (Row.Wnd = AWnd) and PtInRect(Row.Rect, Point(X, Y)) then
    begin
      // Nur, wenn die Zeile noch dort steht: gleiche Datei, nicht gescrollt.
      if not SameText(Row.FileName, View.Buffer.FileName) or (Row.TopRow <> View.TopRow) then
        Exit;
      ARow := Row;
      Exit(True);
    end;
end;

procedure TAtlasIdeQuickColumn.SetHover(const ARow: TRow; AOn: Boolean);
var
  Changed: Boolean;
begin
  Changed := AOn <> FHovering;
  if AOn and FHovering then
    Changed := (ARow.Wnd <> FHover.Wnd) or (ARow.Line <> FHover.Line) or not SameText(ARow.FileName, FHover.FileName);
  if not Changed then
    Exit;
  HideTip;
  FHovering := AOn;
  FHover := ARow;
  FHoverSince := TThread.GetTickCount64;
  // Umriss auf freiem Platz folgt der Maus.
  InvalidateTop;
end;

procedure TAtlasIdeQuickColumn.EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
var
  Row: TRow;
begin
  try
    if not Shown or (Editor = nil) or not Editor.HandleAllocated or not RowAt(Editor.Handle, X, Y, Row) then
    begin
      SetHover(Default(TRow), False);
      Exit;
    end;
    SetHover(Row, True);
    FHoverScreen := TRect.Create(Editor.ClientToScreen(Row.Rect.TopLeft), Editor.ClientToScreen(Row.Rect.BottomRight));
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.QuickBookmarks, E);
  end;
end;

procedure TAtlasIdeQuickColumn.CheckHover;
begin
  if not FHovering then
    Exit;
  // Maus hat die Spalte verlassen, ohne dass der Editor es gemeldet hat (anderes Fenster).
  if not PtInRect(FHoverScreen, Mouse.CursorPos) and not (FTip.IsShown and PtInRect(FTip.BoundsRect,
    Mouse.CursorPos)) then
  begin
    SetHover(Default(TRow), False);
    Exit;
  end;
  if not FTip.IsShown and (TThread.GetTickCount64 - FHoverSince >= HoverMs) then
    ShowTip(FHover);
end;

procedure TAtlasIdeQuickColumn.HideTip;
begin
  if (FTip <> nil) and FTip.IsShown then
    FTip.HidePopup;
end;

procedure TAtlasIdeQuickColumn.ShowTip(const ARow: TRow);
var
  Title, Text: string;
  JumpKey: Word;
begin
  JumpKey := 0;
  if TAtlasIdeSettings.Current.QuickBookmarksNumberedKeys then
    JumpKey := Word(TAtlasIdeSettings.Current.QuickBookmarkJumpKey);
  TipText(ARow.Marks, JumpKey, Title, Text);
  if Length(ARow.Marks) = 0 then
  begin
    if not TAtlasIdeSettings.Current.QuickBookmarksGutterClick then
      Exit;
    Text := TAtlasStrings.Text(TAtlasTextId.QuickBookmarkTipFree);
  end;
  FTip.ShowNote(Title, Text, Point(FHoverScreen.Right + 4, FHoverScreen.Bottom + 2));
end;

procedure TAtlasIdeQuickColumn.AppMessage(var Msg: TMsg; var Handled: Boolean);
var
  Row: TRow;
  Where: TPoint;
  FileName: string;
  Line: Integer;
begin
  try
    if (Msg.message = FSwallowUp) and (FSwallowUp <> 0) then
    begin
      // Loslassen zum geschluckten Drücken: Ohne Drücken darf auch es nicht an den Editor.
      FSwallowUp := 0;
      Handled := True;
      if GetCapture = Msg.hwnd then
        ReleaseCapture;
      if Msg.message = WM_RBUTTONUP then
      begin
        Row := FMenuRow;
        Where := Mouse.CursorPos;
        TAtlasMainThread.ForceQueue(TAtlasFeature.QuickBookmarks,
          procedure
          begin
            TAtlasGuard.Run(TAtlasFeature.QuickBookmarks,
              procedure
              begin
                ShowMenu(Row, Where);
              end);
          end);
      end;
      Exit;
    end;
    if not ((Msg.message = WM_LBUTTONDOWN) or (Msg.message = WM_LBUTTONDBLCLK) or
      (Msg.message = WM_RBUTTONDOWN)) then
      Exit;
    if not Shown or (FRows.Count = 0) then
      Exit;
    if not RowAt(Msg.hwnd, SmallInt(LoWord(Msg.lParam)), SmallInt(HiWord(Msg.lParam)), Row) then
      Exit;
    if Msg.message = WM_RBUTTONDOWN then
    begin
      // Das eigene Menü ersetzt das Kontextmenü der IDE; es öffnet beim Loslassen.
      Handled := True;
      FSwallowUp := WM_RBUTTONUP;
      FMenuRow := Row;
      HideTip;
      Exit;
    end;
    // Linksklick nur mit bookmarks.quick.gutterClick; sonst bekommt ihn die IDE wie bisher.
    if not TAtlasIdeSettings.Current.QuickBookmarksGutterClick then
      Exit;
    Handled := True;
    FSwallowUp := WM_LBUTTONUP;
    HideTip;
    FileName := Row.FileName;
    Line := Row.Line;
    TAtlasMainThread.ForceQueue(TAtlasFeature.QuickBookmarks,
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.QuickBookmarks,
          procedure
          begin
            TAtlasIdeBookmarks.ColumnClick(FileName, Line);
          end);
      end);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.QuickBookmarks, E);
  end;
end;

function TAtlasIdeQuickColumn.AddMenuItem(AParent: TMenuItem; const ACaption: string; ATag: Integer): TMenuItem;
begin
  Result := TMenuItem.Create(FMenu);
  Result.Caption := ACaption;
  Result.Tag := ATag;
  Result.OnClick := MenuClick;
  AParent.Add(Result);
end;

procedure TAtlasIdeQuickColumn.ShowMenu(const ARow: TRow; const APoint: TPoint);
var
  Numbers, Item: TMenuItem;
  Targets: TArray<string>;
  Number, Current: Integer;
begin
  FMenu.Items.Clear;
  FMenuRow := ARow;
  Current := 0;
  if Length(ARow.Marks) > 0 then
    Current := ARow.Marks[0].Number;
  Targets := TAtlasIdeBookmarks.NumberTargets(ARow.FileName);
  Numbers := AddMenuItem(FMenu.Items, TAtlasStrings.Text(TAtlasTextId.QuickBookmarkMenuNumber), 0);
  Numbers.OnClick := nil;
  for Number := 1 to TAtlasQuickBookmarks.MaxNumber do
  begin
    // Belegte Nummern zeigen ihr Ziel; die eigene ist abgehakt (Klick nimmt sie weg).
    if (Number < Length(Targets)) and (Targets[Number] <> '') and (Number <> Current) then
      Item := AddMenuItem(Numbers, TAtlasStrings.Fmt(TAtlasTextId.QuickBookmarkMenuNumberUsed,
        [Number, Targets[Number]]), Number)
    else
      Item := AddMenuItem(Numbers, '&' + IntToStr(Number), Number);
    Item.Checked := Number = Current;
  end;
  AddMenuItem(FMenu.Items, TAtlasStrings.Text(TAtlasTextId.QuickBookmarkMenuName), MenuName);
  Item := AddMenuItem(FMenu.Items, TAtlasStrings.Text(TAtlasTextId.QuickBookmarkMenuRemove), MenuRemove);
  Item.Enabled := Length(ARow.Marks) > 0;
  Item := AddMenuItem(FMenu.Items, TAtlasStrings.Text(TAtlasTextId.QuickBookmarkMenuRemoveFile), MenuRemoveFile);
  Item.Enabled := TAtlasIdeBookmarks.HasColumnMarks(ARow.FileName);
  AddMenuItem(FMenu.Items, '-', -1).OnClick := nil;
  AddMenuItem(FMenu.Items, TAtlasStrings.Text(TAtlasTextId.QuickBookmarkMenuWindow), MenuWindow);
  FMenu.Popup(APoint.X, APoint.Y);
end;

procedure TAtlasIdeQuickColumn.MenuClick(Sender: TObject);
var
  Command: Integer;
  Row: TRow;
begin
  Command := TMenuItem(Sender).Tag;
  Row := FMenuRow;
  TAtlasGuard.Run(TAtlasFeature.QuickBookmarks,
    procedure
    begin
      case Command of
        1..TAtlasQuickBookmarks.MaxNumber:
          TAtlasIdeBookmarks.ColumnAssign(Row.FileName, Row.Line, Command);
        MenuName:
          TAtlasIdeBookmarks.ColumnName(Row.FileName, Row.Line);
        MenuRemove:
          TAtlasIdeBookmarks.ColumnRemove(Row.FileName, Row.Line);
        MenuRemoveFile:
          TAtlasIdeBookmarks.ColumnRemoveFile(Row.FileName);
        MenuWindow:
          TAtlasIdeBookmarks.ShowWindow;
      end;
    end);
end;

end.
