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
//   Getroffen wird über den Bildschirmpunkt der Nachricht im Fenster der
//   Spalte, nicht über hwnd und lParam (#1281: die Nachricht kann an ein
//   anderes Fenster gehen als das, in dem die IDE die Rinne zeichnet).
//   Zeile, Datei und Marker unter dem Punkt kommen aus dem Zustand des
//   Editors beim Klick (EditorState, GetGutterColumnRect, LineState), nicht
//   aus dem, was zuletzt gezeichnet wurde: Zeichnet die IDE nach dem Scrollen
//   oder in einem zweiten Editorfenster nur einen Teil der Zeilen neu, waren
//   die gemerkten Zeilen veraltet, und Klicks auf freie Zeilen gingen ins
//   Leere. Vom Zeichnen bleibt nur, wo die Spalte liegt (je Editorfenster).
//   Erreicht die Nachricht Atlas nicht (ein anderer Experte setzt
//   Application.OnMessage selbst), nimmt das Mausereignis des Editors den
//   Klick (wie die Atlas-Spalte #768); das Protokoll meldet das einmal.
// - Überfahren: gestrichelter Umriss auf freiem Platz, nach HoverMs ein
//   Tooltip mit Nummer, Name bzw. Methode und Sprungtaste aller Marker.
// - Rechtsklick: Menü „Nummer vergeben ›“ (belegte Nummern mit Ziel),
//   „Namen geben …“, „Lesezeichen entfernen“, „Alle Lesezeichen der Datei
//   entfernen“, „Fenster ‚Lesezeichen‘ öffnen“.
// - Der Zeitgeber führt außerdem die Liste der Datei im oberen Editor nach
//   (Wiederfinden nach einer Tipp-Pause, auch ohne benannte Lesezeichen),
//   übernimmt beim ersten Öffnen die IDE-Lesezeichen 1–9 (ImportIde) und
//   nimmt Hinweise im Statusfeld wieder weg.
// - Die Spalte meldet dem Dienst, ob die IDE sie wirklich zeichnet (#1281):
//   Erst dann übernimmt Atlas die IDE-Lesezeichen und überlässt ihr die
//   nummerierten benannten. Anfordern, Fehlen der Schnittstelle und eine
//   Spalte, die nach PaintWaitMs noch nie gezeichnet wurde, stehen im
//   Protokoll.
// Abschaltbar über bookmarks.quick und bookmarks.quick.gutter, ausblendbar am
// Element (#628). Sicherung über TAtlasFeature.QuickBookmarks (#493). Nur im
// Hauptthread. Tooltip und Menü stehen in Atlas.IDE.Bookmarks.QuickPopups.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Types,
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.AppEvnts,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Bookmarks.Store,
  Atlas.IDE.Bookmarks.QuickPopups;

type
  TAtlasIdeQuickColumn = class
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedGutterStages: TPaintGutterStages; override;
    end;
    /// <summary>Zeile der Spalte unter einem Punkt (Koordinaten des Editors).</summary>
    TRow = record
      Wnd: HWND;
      FileName: string;
      /// <summary>0-basiert.</summary>
      Line: Integer;
      Rect: TRect;
      TopRow: Integer;
      Marks: TArray<TAtlasBookmark>;
    end;
    /// <summary>Zuletzt gezeichnete Zeile eines Editorfensters: Lage der Spalte und Zeilenhöhe, Ausgang für
    /// die Trefferprüfung.</summary>
    TPainted = record
      /// <summary>Zeile des Editors (Context.EditorLineNum).</summary>
      EditorLine: Integer;
      Rect: TRect;
    end;
    /// <summary>Die angeforderte Spalte der Rinne.</summary>
    TSlot = record
      Column: Integer;
      Width: Integer;
      WantedWidth: Integer;
      /// <summary>Anmeldung bei TAtlasIdeGutterColumns: Spalte vor dem Abbau eines Editorfensters abgeben (#1233).
      /// </summary>
      Handle: Integer;
    end;
    /// <summary>Wo die Spalte gezeichnet wurde.</summary>
    TArea = record
      /// <summary>Je Editorfenster die zuletzt gezeichnete Zeile der Spalte.</summary>
      Rows: TDictionary<HWND, TPainted>;
      /// <summary>Kleinste und größte gezeichnete Editorzeile: Nur dazwischen fragt die Trefferprüfung die IDE.
      /// </summary>
      FirstLine: Integer;
      LastLine: Integer;
    end;
    /// <summary>Oberer Editor und Tipp-Pause.</summary>
    TTrack = record
      FileName: string;
      Text: string;
      ChangedAt: UInt64;
      Done: Boolean;
    end;
    /// <summary>Überfahrene Zeile.</summary>
    THover = record
      Row: TRow;
      Hovering: Boolean;
      Since: UInt64;
      ScreenRect: TRect;
    end;
    /// <summary>Geschlucktes Drücken: nach ihm auch das Loslassen schlucken (WM_LBUTTONUP, WM_RBUTTONUP); beim
    /// rechten öffnet dann das Menü zur Zeile.</summary>
    TPress = record
      SwallowUp: Cardinal;
      Row: TRow;
    end;
    /// <summary>Spalte wirklich gezeichnet (#1281) und was das Protokoll schon gemeldet hat.</summary>
    TLog = record
      Painted: Boolean;
      RequestedAt: UInt64;
      NoServices: Boolean;
      NotPainted: Boolean;
      /// <summary>Zeitpunkt des letzten über OnMessage genommenen Linksklicks (#1281).</summary>
      ClickedAt: UInt64;
      EditorClick: Boolean;
      Miss: Boolean;
    end;
  private const
    cHoverMs = 400;
    /// <summary>Tipp-Pause, bevor die Lesezeichen der Datei wiedergefunden werden.</summary>
    cQuietMs = 600;
    /// <summary>So lange nach dem Anfordern darf die Spalte ungezeichnet bleiben, bevor das Protokoll es meldet.
    /// </summary>
    cPaintWaitMs = 5000;
  private
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FSlot: TSlot;
    FTimer: TTimer;
    FTip: TAtlasIdeQuickTip;
    FMenu: TAtlasIdeQuickMenu;
    FAppEvents: TApplicationEvents;
    FArea: TArea;
    FTrack: TTrack;
    FHover: THover;
    FPress: TPress;
    FLog: TLog;
    function Active: Boolean;
    function Shown: Boolean;
    procedure EnsureColumn;
    procedure DropColumn;
    procedure Tick(Sender: TObject);
    procedure Track;
    procedure CheckPainted;
    /// <summary>Zeile der Spalte unter X, Y im Editorfenster AWnd, aus dem aktuellen Zustand des Editors.
    /// </summary>
    function RowAt(AWnd: HWND; AX, AY: Integer; out ARow: TRow): Boolean; overload;
    /// <summary>Zeile unter dem Bildschirmpunkt APoint einer Nachricht an AWnd: in einem Editorfenster mit
    /// gezeichneter Spalte, wenn AWnd dieses Fenster, ein Kind oder ein Vorfahr davon ist.</summary>
    function RowAt(AWnd: HWND; const APoint: TPoint; out ARow: TRow): Boolean; overload;
    procedure ClickRow(const ARow: TRow);
    /// <summary>Protokoll (einmal je Sitzung): Klick auf Höhe der Spalte, aber keine Zeile gefunden.</summary>
    procedure LogMiss(AWnd: HWND; const APoint: TPoint);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure PaintGutter(const Rect: TRect; const Stage: TPaintGutterStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    /// <summary>Eine Zeile der Spalte zeichnen und ihre Lage merken.</summary>
    procedure PaintRow(const ARect: TRect; AStage: TPaintGutterStage; const AContext: INTACodeEditorPaintContext);
    procedure EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
    /// <summary>Drücken auf die Spalte: rechts das eigene Menü, links (mit gutterClick) Lesezeichen setzen bzw.
    /// entfernen; beides an der IDE vorbei.</summary>
    procedure TakePress(var AMsg: TMsg; var AHandled: Boolean);
    procedure CheckHover;
    procedure HideTip;
    procedure SetHover(const ARow: TRow; AOn: Boolean);
  public
    constructor Create;
    destructor Destroy; override;
  end;

implementation

uses
  System.Math,
  Vcl.Forms,
  Vcl.Graphics,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Editor.LineAnchor,
  Atlas.Core.Bookmarks.Quick,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.GutterColumns,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Bookmarks.Service,
  Atlas.IDE.Bookmarks.QuickService,
  Atlas.IDE.Foundation.EditorRefresh;

type
  /// <summary>Ergebnis der Prüfung einer Editorzeile: daneben, getroffen, oder getroffen ohne gültige Zeile.
  /// </summary>
  TLineHit = (Miss, Found, Stop);
  /// <summary>Ein Editorfenster mit Zustand und Ansicht.</summary>
  TEditorPlace = record
    Control: TWinControl;
    State: INTACodeEditorState;
    View: IOTAEditView;
  end;

procedure InvalidateTop;
var
  mEditors: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, mEditors) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(mEditors);
  end;
end;

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

function SampleBack(ACanvas: TCanvas; const ARect: TRect): TAtlasColor;
var
  mSample: COLORREF;
begin
  // Farben aus dem Grund der Rinne: hell oder dunkel wie das Thema der IDE.
  mSample := GetPixel(ACanvas.Handle, ARect.Left + 1, ARect.Top + 1);
  if mSample = CLR_INVALID then
  begin
    Result := TAtlasColor(ColorToRGB(ACanvas.Brush.Color));
  end
  else
  begin
    Result := TAtlasColor(mSample);
  end;
end;

/// <summary>Ziffer auf dem Marker: Schwarz oder Weiß, je nachdem, was sich stärker von AFill abhebt.</summary>
function DigitColor(AFill: TAtlasColor): TAtlasColor;
const
  cBlack = TAtlasColor($000000);
  cWhite = TAtlasColor($FFFFFF);
begin
  Result := cBlack;
  if TAtlasColorMath.Contrast(cWhite, AFill) > TAtlasColorMath.Contrast(cBlack, AFill) then
  begin
    Result := cWhite;
  end;
end;

/// <summary>Band mit Kerbe unten wie bei den benannten Lesezeichen (#622); liefert die Höhe der Kerbe.</summary>
function PaintBand(ACanvas: TCanvas; const ABand: TRect; AFill, ALine: TAtlasColor): Integer;
begin
  Result := Max(2, ABand.Height div 5);
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := TColor(AFill);
  ACanvas.Pen.Color := TColor(ALine);
  ACanvas.Pen.Style := psSolid;
  ACanvas.Pen.Width := 1;
  ACanvas.Polygon([Point(ABand.Left, ABand.Top), Point(ABand.Right - 1, ABand.Top),
    Point(ABand.Right - 1, ABand.Bottom - 1), Point((ABand.Left + ABand.Right) div 2, ABand.Bottom - 1 - Result),
    Point(ABand.Left, ABand.Bottom - 1)]);
end;

/// <summary>Ziffer ANumber mittig über der Kerbe des Bands in AColor.</summary>
procedure PaintDigit(ACanvas: TCanvas; const ABand: TRect; ANotch, ANumber: Integer; AColor: TAtlasColor);
var
  mDigit: string;
  mSize: TSize;
  mOldFont: TFont;
begin
  mDigit := IntToStr(ANumber);
  mOldFont := TFont.Create;
  try
    mOldFont.Assign(ACanvas.Font);
    ACanvas.Font.Style := [fsBold];
    ACanvas.Font.Height := -Max(7, (ABand.Height - ANotch) * 4 div 5);
    ACanvas.Font.Color := TColor(AColor);
    ACanvas.Brush.Style := bsClear;
    mSize := ACanvas.TextExtent(mDigit);
    ACanvas.TextOut(ABand.Left + (ABand.Width - mSize.cx) div 2,
      ABand.Top + Max(0, (ABand.Height - ANotch - mSize.cy) div 2), mDigit);
  finally
    ACanvas.Font.Assign(mOldFont);
    mOldFont.Free;
  end;
end;

procedure PaintMarks(ACanvas: TCanvas; const ARow: TAtlasIdeQuickColumn.TRow; const AColors: TAtlasColors;
  ABack: TAtlasColor);
var
  mBand: TRect;
  mNotch, mCorner: Integer;
begin
  // Band mit Kerbe unten wie bei den benannten Lesezeichen (#622), etwas breiter für die Ziffer.
  mBand := ARow.Rect;
  InflateRect(mBand, -1, -1);
  mNotch := PaintBand(ACanvas, mBand, TAtlasColorMath.Mix(AColors.Warn, ABack, 0.85), AColors.Warn);
  // Mehr als ein Marker: gefüllte Ecke oben rechts.
  if Length(ARow.Marks) > 1 then
  begin
    mCorner := Max(3, mBand.Width div 3);
    ACanvas.Brush.Color := TColor(AColors.Warn);
    ACanvas.Polygon([Point(mBand.Right - 1 - mCorner, mBand.Top), Point(mBand.Right - 1, mBand.Top),
      Point(mBand.Right - 1, mBand.Top + mCorner)]);
  end;
  if ARow.Marks[0].Number > 0 then
  begin
    PaintDigit(ACanvas, mBand, mNotch, ARow.Marks[0].Number,
      DigitColor(TAtlasColorMath.Mix(AColors.Warn, ABack, 0.85)));
  end;
end;

procedure PaintFree(ACanvas: TCanvas; const ARect: TRect; const AColors: TAtlasColors; ABack: TAtlasColor;
  ANumber: Integer);
var
  mFill: TAtlasColor;
  mBand: TRect;
  mNotch: Integer;
begin
  // Vorschau (Marco 28.10.2026): blasser Marker wie PaintMarks, mit der Nummer, die ein Klick hier vergäbe; sind
  // alle neun belegt, ohne Nummer.
  mBand := ARect;
  InflateRect(mBand, -1, -1);
  mFill := TAtlasColorMath.Mix(AColors.Warn, ABack, 0.15);
  mNotch := PaintBand(ACanvas, mBand, mFill, TAtlasColorMath.Mix(AColors.Warn, ABack, 0.45));
  if ANumber > 0 then
  begin
    PaintDigit(ACanvas, mBand, mNotch, ANumber, TAtlasColorMath.Mix(DigitColor(mFill), mFill, 0.7));
  end;
end;

procedure PaintLineNumber(ACanvas: TCanvas; const ARect: TRect; ALine: Integer; const AColors: TAtlasColors);
var
  mNumber: string;
  mArea: TRect;
begin
  // Zahl hell auf dem Grund der Rinne neu zeichnen; Schrift ist die, mit der die IDE die Zahlen zeichnet.
  mNumber := IntToStr(ALine + 1);
  if ACanvas.TextWidth(mNumber) > ARect.Width then
  begin
    Exit;
  end;
  mArea := ARect;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := TColor(AColors.Gutter);
  ACanvas.FillRect(mArea);
  ACanvas.Brush.Style := bsClear;
  ACanvas.Font.Color := TColor(AColors.Text);
  Dec(mArea.Right, 2);
  DrawText(ACanvas.Handle, PChar(mNumber), Length(mNumber), mArea, DT_RIGHT or DT_VCENTER or DT_SINGLELINE or
    DT_NOPREFIX);
end;

/// <summary>Zeilennummer ALine hell nachzeichnen; Pinsel und Schrift bleiben danach wie vorher.</summary>
procedure RepaintLineNumber(ACanvas: TCanvas; const ARect: TRect; ALine: Integer);
var
  mOldBrush: TBrush;
  mOldFont: TFont;
  mBack: TAtlasColor;
  mColors: TAtlasColors;
begin
  mOldBrush := TBrush.Create;
  mOldFont := TFont.Create;
  try
    mOldBrush.Assign(ACanvas.Brush);
    mOldFont.Assign(ACanvas.Font);
    mBack := SampleBack(ACanvas, ARect);
    mColors := TAtlasColors.ForBackground(mBack);
    mColors.Gutter := mBack;
    PaintLineNumber(ACanvas, ARect, ALine, mColors);
  finally
    ACanvas.Brush.Assign(mOldBrush);
    ACanvas.Font.Assign(mOldFont);
    mOldFont.Free;
    mOldBrush.Free;
  end;
end;

/// <summary>Marker der Zeile bzw. (ohne Marker) der blasse Vorschlag; Pinsel und Stift bleiben wie vorher.
/// </summary>
procedure PaintRowMarks(ACanvas: TCanvas; const ARow: TAtlasIdeQuickColumn.TRow);
var
  mBack: TAtlasColor;
  mColors: TAtlasColors;
  mOldBrush: TBrush;
  mOldPen: TPen;
begin
  mBack := SampleBack(ACanvas, ARow.Rect);
  mColors := TAtlasColors.ForBackground(mBack);
  mOldBrush := TBrush.Create;
  mOldPen := TPen.Create;
  try
    mOldBrush.Assign(ACanvas.Brush);
    mOldPen.Assign(ACanvas.Pen);
    if Length(ARow.Marks) > 0 then
    begin
      PaintMarks(ACanvas, ARow, mColors, mBack);
    end
    else
    begin
      PaintFree(ACanvas, ARow.Rect, mColors, mBack, TAtlasIdeQuickBookmarks.NextNumber(ARow.FileName));
    end;
  finally
    ACanvas.Brush.Assign(mOldBrush);
    ACanvas.Pen.Assign(mOldPen);
    mOldPen.Free;
    mOldBrush.Free;
  end;
end;

/// <summary>Stufe der Zeilennummern: die, deren Rechteck ARect rechts an die Spalte AColumn grenzt.</summary>
function IsLineNumberStage(AStage: TPaintGutterStage; const ARect, AColumn: TRect): Boolean;
begin
  Result := (AStage <> Low(TPaintGutterStage)) and (ARect.Left >= AColumn.Right - 1) and
    (ARect.Left <= AColumn.Right + 2) and (ARect.Width > 0);
end;

/// <summary>Zeigt die Zeile ARow den blassen Vorschlag (überfahren, Klick setzt ein Lesezeichen)?</summary>
function HoverShowsFree(const AHover: TAtlasIdeQuickColumn.THover; const ARow: TAtlasIdeQuickColumn.TRow): Boolean;
begin
  Result := AHover.Hovering and TAtlasIdeSettings.Current.QuickBookmarksGutterClick and (AHover.Row.Wnd = ARow.Wnd) and
    (AHover.Row.Line = ARow.Line) and SameText(AHover.Row.FileName, ARow.FileName);
end;

/// <summary>Marker der Zeile, wie die Spalte sie zeigt: nur, solange die Zeile zum Anker passt und das
/// Element dort nicht ausgeblendet ist.</summary>
function VisibleMarks(const AFileName: string; ALine: Integer; const ALineText: string;
  AHasText: Boolean): TArray<TAtlasBookmark>;
begin
  Result := TAtlasIdeQuickBookmarks.ColumnMarksAt(AFileName, ALine);
  // Nur, wenn die Zeile im Editor noch zum Anker passt; nach dem Tippen folgt das Wiederfinden.
  if (Length(Result) > 0) and AHasText and (TAtlasLineAnchors.Normalize(ALineText) <> Result[0].Anchor.Text) then
  begin
    Result := nil;
  end;
  // In .atlas ausgeblendet (#628): ganze Datei oder diese Codezeile.
  if (Length(Result) > 0) and TAtlasIdeElements.Hidden(TAtlasDrawnElement.QuickBookmarks, AFileName, ALineText) then
  begin
    Result := nil;
  end;
end;

/// <summary>Editorzustand und Ansicht des Editorfensters AWnd; False ohne Datei.</summary>
function EditorAt(AWnd: HWND; out APlace: TEditorPlace): Boolean;
var
  mEditors: INTACodeEditorServices;
begin
  APlace := Default(TEditorPlace);
  APlace.Control := FindControl(AWnd);
  Result := (APlace.Control <> nil) and Supports(BorlandIDEServices, INTACodeEditorServices, mEditors);
  if Result then
  begin
    APlace.State := mEditors.EditorState[APlace.Control];
  end;
  if APlace.State <> nil then
  begin
    APlace.View := APlace.State.View;
  end;
  Result := Result and (APlace.View <> nil) and (APlace.View.Buffer <> nil) and (APlace.View.Buffer.FileName <> '');
end;

/// <summary>Editorzeile ALine prüfen: Liegt APoint in ihrer Spalte AColumn, steht in ARow die Zeile (ohne Wnd).
/// </summary>
function LineRow(const APlace: TEditorPlace; AColumn, ALine: Integer; const APoint: TPoint;
  out ARow: TAtlasIdeQuickColumn.TRow): TLineHit;
var
  mColumnRect: TRect;
  mLineState: INTACodeEditorLineState;
  mLogical: Integer;
begin
  ARow := Default(TAtlasIdeQuickColumn.TRow);
  mColumnRect := APlace.State.GetGutterColumnRect(APlace.Control, ALine, AColumn);
  if mColumnRect.IsEmpty or not PtInRect(mColumnRect, APoint) then
  begin
    Exit(TLineHit.Miss);
  end;
  mLineState := APlace.State.LineState[ALine];
  mLogical := 0;
  if mLineState <> nil then
  begin
    mLogical := mLineState.LogicalLineNum;
  end;
  if (mLogical <= 0) or (mLogical > APlace.View.Buffer.GetLinesInBuffer) then
  begin
    Exit(TLineHit.Stop);
  end;
  ARow.FileName := APlace.View.Buffer.FileName;
  ARow.Line := mLogical - 1;
  ARow.Rect := mColumnRect;
  ARow.TopRow := APlace.View.TopRow;
  ARow.Marks := VisibleMarks(ARow.FileName, ARow.Line, mLineState.Text, True);
  Result := TLineHit.Found;
end;

/// <summary>Gehört die Nachricht an AWnd zum Editorfenster AEditor (dasselbe, ein Kind oder ein Vorfahr)?
/// </summary>
function Related(AEditor, AWnd: HWND): Boolean;
begin
  Result := (AWnd = AEditor) or IsChild(AEditor, AWnd) or IsChild(AWnd, AEditor);
end;

/// <summary>Menü erst nach dem Loslassen öffnen (eingereiht).</summary>
procedure QueueMenu(AMenu: TAtlasIdeQuickMenu; const ARow: TAtlasIdeQuickColumn.TRow; const APoint: TPoint);
var
  mMenu: TAtlasIdeQuickMenu;
  mRow: TAtlasIdeQuickColumn.TRow;
  mPoint: TPoint;
begin
  mMenu := AMenu;
  mRow := ARow;
  mPoint := APoint;
  TAtlasMainThread.ForceQueue(TAtlasFeature.QuickBookmarks,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.QuickBookmarks,
        procedure
        begin
          mMenu.Show(mRow.FileName, mRow.Line, mRow.Marks, mPoint);
        end);
    end);
end;

function IsPress(AMessage: Cardinal): Boolean;
begin
  Result := (AMessage = WM_LBUTTONDOWN) or (AMessage = WM_LBUTTONDBLCLK) or (AMessage = WM_RBUTTONDOWN);
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
  mEditors: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FSlot.Column := -1;
  FArea.Rows := TDictionary<HWND, TPainted>.Create;
  FArea.FirstLine := MaxInt;
  FArea.LastLine := -1;
  FTip := TAtlasIdeQuickTip.Create;
  FMenu := TAtlasIdeQuickMenu.Create;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintGutter := PaintGutter;
  FEvents.OnEditorMouseMove := EditorMouseMove;
  FEvents.OnEditorMouseDown := EditorMouseDown;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mEditors) then
  begin
    FIndex := mEditors.AddEditorEventsNotifier(FEventsRef);
  end;
  if FIndex < 0 then
  begin
    TAtlasGuard.Log('Schnelle Lesezeichen: Die IDE nimmt keinen Editor-Notifier an, die Spalte bleibt aus');
  end;
  FAppEvents := TApplicationEvents.Create(nil);
  FAppEvents.OnMessage := AppMessage;
  FSlot.Handle := TAtlasIdeGutterColumns.Register(
    procedure
    begin
      DropColumn;
    end);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 100;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasIdeQuickColumn.Destroy;
var
  mEditors: INTACodeEditorServices;
begin
  FTimer.Free;
  TAtlasIdeGutterColumns.Unregister(FSlot.Handle);
  if FAppEvents <> nil then
  begin
    FAppEvents.OnMessage := nil;
    FAppEvents.Free;
  end;
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
  FMenu.Free;
  FTip.Free;
  FArea.Rows.Free;
  FPress := Default(TPress);
  FHover := Default(THover);
  inherited Destroy;
end;

function TAtlasIdeQuickColumn.Active: Boolean;
begin
  Result := (FIndex >= 0) and not TAtlasGuard.Disabled(TAtlasFeature.QuickBookmarks) and
    TAtlasIdeSettings.Current.QuickBookmarks;
end;

function TAtlasIdeQuickColumn.Shown: Boolean;
begin
  Result := Active and TAtlasIdeSettings.Current.QuickBookmarksGutter and (FSlot.Column >= 0);
end;

procedure TAtlasIdeQuickColumn.EnsureColumn;
var
  mEditors: INTACodeEditorServices280;
begin
  if FSlot.WantedWidth <= 0 then
  begin
    FSlot.WantedWidth := TAtlasQuickBookmarks.ColumnWidth(MulDiv(20, Screen.PixelsPerInch, 96));
  end;
  if (FSlot.Column >= 0) and (FSlot.Width = FSlot.WantedWidth) then
  begin
    Exit;
  end;
  mEditors := Services;
  if mEditors = nil then
  begin
    if not FLog.NoServices then
    begin
      TAtlasGuard.Log('Schnelle Lesezeichen: Die IDE bietet keine eigenen Spalten der Zeilenleiste ' +
        '(INTACodeEditorServices280), die Spalte bleibt aus');
    end;
    FLog.NoServices := True;
    Exit;
  end;
  // Kurz nach dem Abbau eines Editorfensters nicht wieder anfordern (#1233, TAtlasIdeGutterColumns).
  if not TAtlasIdeGutterColumns.Allowed then
  begin
    Exit;
  end;
  DropColumn;
  // Hinter den Haltepunkten, also weiterhin links der Zahlen. gclBeforeLineNumbers überzeichnete die IDE in
  // Delphi 13 mit den Zeilennummern; sichtbar war die Spalte nur in frisch eingefügten Zeilen (#1281).
  FSlot.Column := mEditors.RequestGutterColumn(FIndex, FSlot.WantedWidth, gclAfterBreakPoint);
  FSlot.Width := FSlot.WantedWidth;
  FLog.RequestedAt := TThread.GetTickCount64;
  FLog.NotPainted := False;
  TAtlasGuard.Log(Format('Schnelle Lesezeichen: Spalte angefordert (Spalte %d, Breite %d)',
    [FSlot.Column, FSlot.Width]));
  FArea.Rows.Clear;
  TAtlasIdeEditorRefresh.InvalidateTop(mEditors);
end;

procedure TAtlasIdeQuickColumn.DropColumn;
var
  mEditors: INTACodeEditorServices280;
begin
  if FSlot.Column < 0 then
  begin
    Exit;
  end;
  mEditors := Services;
  if mEditors <> nil then
  begin
    mEditors.RemoveGutterColumn(FSlot.Column);
    TAtlasIdeEditorRefresh.InvalidateTop(mEditors);
  end;
  FSlot.Column := -1;
  FArea.Rows.Clear;
  if FLog.Painted then
  begin
    FLog.Painted := False;
    TAtlasIdeBookmarks.ColumnPainted(False);
  end;
end;

procedure TAtlasIdeQuickColumn.CheckPainted;
begin
  // Dem Dienst melden, ob die Spalte zeichnet; erst dann übernimmt er die IDE-Lesezeichen (#1281).
  TAtlasIdeBookmarks.ColumnPainted(FLog.Painted);
  if FLog.Painted then
  begin
    TAtlasIdeQuickBookmarks.ImportIde(FTrack.FileName);
    Exit;
  end;
  if (FSlot.Column < 0) or FLog.NotPainted or (FTrack.FileName = '') or
    (TThread.GetTickCount64 - FLog.RequestedAt < cPaintWaitMs) then
  begin
    Exit;
  end;
  FLog.NotPainted := True;
  TAtlasGuard.Log(Format('Schnelle Lesezeichen: Spalte %d seit %d ms angefordert, die IDE hat sie aber noch nie ' +
    'gezeichnet', [FSlot.Column, cPaintWaitMs]));
end;

procedure TAtlasIdeQuickColumn.Tick(Sender: TObject);
begin
  try
    TAtlasIdeBookmarks.ExpireStatus;
    if not Active then
    begin
      SetHover(Default(TRow), False);
      DropColumn;
      FTrack.FileName := '';
      FTrack.Text := '';
      Exit;
    end;
    Track;
    if TAtlasIdeSettings.Current.QuickBookmarksGutter then
    begin
      EnsureColumn;
      CheckPainted;
    end
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
  mView: IOTAEditView;
  mText: string;
begin
  mView := TopView;
  if (mView = nil) or (mView.Buffer = nil) or (mView.Buffer.FileName = '') then
  begin
    Exit;
  end;
  mText := TAtlasEditorSnapshots.Get(mView).Text;
  if not SameText(FTrack.FileName, mView.Buffer.FileName) then
  begin
    // Neue Datei vorn: gleich wiederfinden und einmal je Sitzung die IDE-Lesezeichen übernehmen.
    FTrack.FileName := mView.Buffer.FileName;
    FTrack.Text := mText;
    TAtlasIdeBookmarks.Track(FTrack.FileName, FTrack.Text);
    // Die IDE-Lesezeichen übernimmt CheckPainted, sobald die Spalte zeichnet (#1281).
    FTrack.Done := True;
    InvalidateTop;
    Exit;
  end;
  if FTrack.Text <> mText then
  begin
    FTrack.Text := mText;
    FTrack.ChangedAt := TThread.GetTickCount64;
    FTrack.Done := False;
    Exit;
  end;
  if FTrack.Done or (TThread.GetTickCount64 - FTrack.ChangedAt < cQuietMs) then
  begin
    Exit;
  end;
  FTrack.Done := True;
  if TAtlasIdeBookmarks.Track(FTrack.FileName, FTrack.Text) then
  begin
    InvalidateTop;
  end;
end;

procedure TAtlasIdeQuickColumn.PaintGutter(const Rect: TRect; const Stage: TPaintGutterStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
begin
  if BeforeEvent or (FSlot.Column < 0) or (Context = nil) then
  begin
    Exit;
  end;
  try
    if (Context.EditView <> nil) and (Context.EditorState <> nil) and (Context.EditControl <> nil) and Shown then
    begin
      PaintRow(Rect, Stage, Context);
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.QuickBookmarks, E);
  end;
end;

procedure TAtlasIdeQuickColumn.PaintRow(const ARect: TRect; AStage: TPaintGutterStage;
  const AContext: INTACodeEditorPaintContext);
var
  mRow: TRow;
  mLineState: INTACodeEditorLineState;
  mLineText: string;
  mColumnRect: TRect;
  mPainted: TPainted;
begin
  mColumnRect := AContext.EditorState.GetGutterColumnRect(AContext.EditControl, AContext.EditorLineNum,
    FSlot.Column);
  if mColumnRect.IsEmpty or (AContext.LogicalLineNum <= 0) then
  begin
    Exit;
  end;
  // Die IDE zeichnet die Spalte; der Zeitgeber meldet es dem Dienst (#1281).
  FLog.Painted := True;
  mLineState := AContext.LineState;
  mLineText := '';
  if mLineState <> nil then
  begin
    mLineText := mLineState.Text;
  end;
  mRow := Default(TRow);
  mRow.Wnd := AContext.EditControl.Handle;
  mRow.FileName := AContext.FileName;
  mRow.Line := AContext.LogicalLineNum - 1;
  mRow.TopRow := AContext.EditView.TopRow;
  mRow.Rect := mColumnRect;
  mRow.Marks := VisibleMarks(AContext.FileName, mRow.Line, mLineText, mLineState <> nil);
  // Zeilennummern: die Stufe, deren Rechteck rechts an die Spalte grenzt. Nicht aussteigen: Delphi 13 übermalt
  // die Spalte in späteren Stufen; nur die zuletzt gezeichnete bleibt stehen (#1281: sichtbar und anklickbar war
  // sie nur in einzeln neu gezeichneten Zeilen).
  if (AStage <> High(TPaintGutterStage)) and (Length(mRow.Marks) > 0) and
    IsLineNumberStage(AStage, ARect, mColumnRect) then
  begin
    RepaintLineNumber(AContext.Canvas, ARect, mRow.Line);
  end;
  // Für die Trefferprüfung nur die Lage der Spalte; Zeile und Datei fragt sie beim Klick neu ab.
  mPainted.EditorLine := AContext.EditorLineNum;
  mPainted.Rect := mColumnRect;
  FArea.Rows.AddOrSetValue(mRow.Wnd, mPainted);
  FArea.FirstLine := Min(FArea.FirstLine, AContext.EditorLineNum);
  FArea.LastLine := Max(FArea.LastLine, AContext.EditorLineNum);
  if (Length(mRow.Marks) = 0) and not HoverShowsFree(FHover, mRow) then
  begin
    Exit;
  end;
  PaintRowMarks(AContext.Canvas, mRow);
  if Length(mRow.Marks) > 0 then
  begin
    TAtlasIdeElements.Painted(TAtlasIdeElements.Target(TAtlasDrawnElement.QuickBookmarks, AContext.FileName,
      mRow.Line, mLineText), mRow.Rect, mRow.TopRow, mRow.Rect.Height);
  end;
end;

function TAtlasIdeQuickColumn.RowAt(AWnd: HWND; AX, AY: Integer; out ARow: TRow): Boolean;
const
  /// <summary>Geschätzte Zeile zuerst, dann die Nachbarn (Rundung an der Zeilengrenze).</summary>
  cSteps: array[0..2] of Integer = (0, -1, 1);
var
  mPainted: TPainted;
  mPlace: TEditorPlace;
  mGuess, mStep, mCandidate: Integer;
begin
  ARow := Default(TRow);
  Result := False;
  if (FSlot.Column < 0) or not FArea.Rows.TryGetValue(AWnd, mPainted) or
    not EditorAt(AWnd, mPlace) then
  begin
    Exit;
  end;
  // Die Zeile schätzt die Zeilenhöhe der zuletzt gezeichneten; ob der Punkt wirklich in der Spalte dieser
  // Zeile liegt, sagt die IDE (auch nach dem Scrollen oder bei geänderter Breite der Rinne).
  mGuess := TAtlasQuickBookmarks.RowGuess(mPainted.EditorLine, mPainted.Rect.Top, mPainted.Rect.Height, AY);
  for mStep in cSteps do
  begin
    mCandidate := mGuess + mStep;
    if (mCandidate < FArea.FirstLine) or (mCandidate > FArea.LastLine) then
    begin
      Continue;
    end;
    case LineRow(mPlace, FSlot.Column, mCandidate, Point(AX, AY), ARow) of
      TLineHit.Miss:
        ;
      TLineHit.Found:
        begin
          ARow.Wnd := AWnd;
          Exit(True);
        end;
      TLineHit.Stop:
        begin
          ARow := Default(TRow);
          Exit;
        end;
    end;
  end;
end;

function TAtlasIdeQuickColumn.RowAt(AWnd: HWND; const APoint: TPoint; out ARow: TRow): Boolean;
var
  mWnd: HWND;
  mLocal: TPoint;
begin
  ARow := Default(TRow);
  Result := False;
  for mWnd in FArea.Rows.Keys do
  begin
    if (mWnd = 0) or not Related(mWnd, AWnd) then
    begin
      Continue;
    end;
    mLocal := APoint;
    if not Winapi.Windows.ScreenToClient(mWnd, mLocal) then
    begin
      Continue;
    end;
    if RowAt(mWnd, mLocal.X, mLocal.Y, ARow) then
    begin
      Exit(True);
    end;
  end;
end;

procedure TAtlasIdeQuickColumn.LogMiss(AWnd: HWND; const APoint: TPoint);
var
  mWnd: HWND;
  mLocal: TPoint;
  mPainted: TPainted;
begin
  if FLog.Miss then
  begin
    Exit;
  end;
  for mWnd in FArea.Rows.Keys do
  begin
    if not Related(mWnd, AWnd) then
    begin
      Continue;
    end;
    mLocal := APoint;
    if not Winapi.Windows.ScreenToClient(mWnd, mLocal) or not FArea.Rows.TryGetValue(mWnd, mPainted) or
      (mLocal.X < mPainted.Rect.Left) or (mLocal.X >= mPainted.Rect.Right) then
    begin
      Continue;
    end;
    FLog.Miss := True;
    TAtlasGuard.Log(Format('Schnelle Lesezeichen: Klick in die Spalte (%d, %d) ohne Zeile; zuletzt gezeichnet ' +
      'Editorzeile %d bei %d..%d, gezeichnet %d..%d', [mLocal.X, mLocal.Y, mPainted.EditorLine, mPainted.Rect.Top,
      mPainted.Rect.Bottom, FArea.FirstLine, FArea.LastLine]));
    Exit;
  end;
end;

procedure TAtlasIdeQuickColumn.ClickRow(const ARow: TRow);
var
  mFileName: string;
  mLine: Integer;
begin
  HideTip;
  mFileName := ARow.FileName;
  mLine := ARow.Line;
  TAtlasMainThread.ForceQueue(TAtlasFeature.QuickBookmarks,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.QuickBookmarks,
        procedure
        begin
          TAtlasIdeQuickBookmarks.ColumnClick(mFileName, mLine);
        end);
    end);
end;

procedure TAtlasIdeQuickColumn.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  mRow: TRow;
begin
  try
    if (Button <> mbLeft) or (Editor = nil) or not Editor.HandleAllocated then
    begin
      Exit;
    end;
    // Nur, wenn OnMessage den Klick nicht schon genommen hat (dann käme er hier gar nicht an).
    if not Shown or not TAtlasIdeSettings.Current.QuickBookmarksGutterClick or
      (TThread.GetTickCount64 - FLog.ClickedAt < 500) or not RowAt(Editor.Handle, X, Y, mRow) then
    begin
      Exit;
    end;
    if not FLog.EditorClick then
    begin
      TAtlasGuard.Log('Schnelle Lesezeichen: Klick in die Spalte kam nicht über Application.OnMessage, ' +
        'sondern über das Mausereignis des Editors');
    end;
    FLog.EditorClick := True;
    ClickRow(mRow);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.QuickBookmarks, E);
  end;
end;

procedure TAtlasIdeQuickColumn.SetHover(const ARow: TRow; AOn: Boolean);
var
  mChanged: Boolean;
begin
  mChanged := AOn <> FHover.Hovering;
  if AOn and FHover.Hovering then
  begin
    mChanged := (ARow.Wnd <> FHover.Row.Wnd) or (ARow.Line <> FHover.Row.Line) or
      not SameText(ARow.FileName, FHover.Row.FileName);
  end;
  if not mChanged then
  begin
    Exit;
  end;
  HideTip;
  FHover.Hovering := AOn;
  FHover.Row := ARow;
  FHover.Since := TThread.GetTickCount64;
  // Umriss auf freiem Platz folgt der Maus.
  InvalidateTop;
end;

procedure TAtlasIdeQuickColumn.EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
var
  mRow: TRow;
begin
  try
    if not Shown or (Editor = nil) or not Editor.HandleAllocated or not RowAt(Editor.Handle, X, Y, mRow) then
    begin
      SetHover(Default(TRow), False);
      Exit;
    end;
    SetHover(mRow, True);
    FHover.ScreenRect := TRect.Create(Editor.ClientToScreen(mRow.Rect.TopLeft),
      Editor.ClientToScreen(mRow.Rect.BottomRight));
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.QuickBookmarks, E);
  end;
end;

procedure TAtlasIdeQuickColumn.CheckHover;
begin
  if not FHover.Hovering then
  begin
    Exit;
  end;
  // Maus hat die Spalte verlassen, ohne dass der Editor es gemeldet hat (anderes Fenster).
  if not PtInRect(FHover.ScreenRect, Mouse.CursorPos) and not FTip.Contains(Mouse.CursorPos) then
  begin
    SetHover(Default(TRow), False);
    Exit;
  end;
  if not FTip.IsShown and (TThread.GetTickCount64 - FHover.Since >= cHoverMs) then
  begin
    FTip.Show(FHover.Row.Marks, Point(FHover.ScreenRect.Right + 4, FHover.ScreenRect.Bottom + 2));
  end;
end;

procedure TAtlasIdeQuickColumn.HideTip;
begin
  if FTip <> nil then
  begin
    FTip.Hide;
  end;
end;

procedure TAtlasIdeQuickColumn.AppMessage(var Msg: TMsg; var Handled: Boolean);
begin
  try
    if (Msg.message = FPress.SwallowUp) and (FPress.SwallowUp <> 0) then
    begin
      // Loslassen zum geschluckten Drücken: Ohne Drücken darf auch es nicht an den Editor.
      FPress.SwallowUp := 0;
      Handled := True;
      if GetCapture = Msg.hwnd then
      begin
        ReleaseCapture;
      end;
      if Msg.message = WM_RBUTTONUP then
      begin
        QueueMenu(FMenu, FPress.Row, Mouse.CursorPos);
      end;
    end
    else if IsPress(Msg.message) and Shown and (FArea.Rows.Count > 0) then
    begin
      TakePress(Msg, Handled);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.QuickBookmarks, E);
  end;
end;

procedure TAtlasIdeQuickColumn.TakePress(var AMsg: TMsg; var AHandled: Boolean);
var
  mRow: TRow;
begin
  // Bildschirmpunkt der Nachricht, nicht lParam: Die Rinne kann in einem anderen Fenster liegen (#1281).
  if not RowAt(AMsg.hwnd, AMsg.pt, mRow) then
  begin
    LogMiss(AMsg.hwnd, AMsg.pt);
    Exit;
  end;
  if AMsg.message = WM_RBUTTONDOWN then
  begin
    // Das eigene Menü ersetzt das Kontextmenü der IDE; es öffnet beim Loslassen.
    AHandled := True;
    FPress.SwallowUp := WM_RBUTTONUP;
    FPress.Row := mRow;
    HideTip;
    Exit;
  end;
  // Linksklick nur mit bookmarks.quick.gutterClick; sonst bekommt ihn die IDE wie bisher.
  if not TAtlasIdeSettings.Current.QuickBookmarksGutterClick then
  begin
    Exit;
  end;
  AHandled := True;
  FPress.SwallowUp := WM_LBUTTONUP;
  FLog.ClickedAt := TThread.GetTickCount64;
  ClickRow(mRow);
end;

end.
