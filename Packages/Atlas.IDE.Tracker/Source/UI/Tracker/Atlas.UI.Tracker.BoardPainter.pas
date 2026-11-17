unit Atlas.UI.Tracker.BoardPainter;

// Zeichnen des Boards (#1272), reine VCL ohne Open Tools API:
//   OFFEN (3)        IN ARBEIT (2)      ZUR PRÜFUNG (1)    ERLEDIGT (4)
//   ┃ATL-123   ⛔ 3/5 MB
//   ┃Titel in zwei
//   ┃Zeilen …
// Karte: Kennung, Titel (zwei Zeilen), Zuständig als Kürzel, Priorität als
// Farbbalken links, Fortschritt der Checkliste (#1273), Schloss bei offenem
// „hängt ab von“ (#1279), Rahmen in Akzentfarbe beim aktuellen Issue (#765).
// Schmal tragen die Kopfzeilen einen Pfeil zum Auf- und Zuklappen; mit
// Swimlanes steht links je Zeile ihr Name, die eigene Zeile ist in
// Akzentfarbe markiert. Beim Ziehen ist die Zielspalte hervorgehoben, wenn der
// Workflow sie zulässt (TAtlasBoardTransitions), die Karte bleibt gepunktet an
// ihrem Platz und folgt der Maus.

interface

uses
  System.SysUtils,
  System.Types,
  Vcl.Graphics,
  Atlas.Core.Style.Palette,
  Atlas.Core.Tracker.Board,
  Atlas.Core.Tracker.BoardLayout;

type
  /// <summary>Gezogene Karte: Nummer, Zielspalte und Versatz zur Lage auf dem Board.</summary>
  TAtlasBoardPaintDrag = record
    Dragging: Boolean;
    Card: Integer;
    DropColumn: Integer;
    Offset: TPoint;
  end;

  /// <summary>Was gezeichnet wird.</summary>
  TAtlasBoardPaintInput = record
    Snapshot: TAtlasBoardSnapshot;
    Layout: TAtlasBoardLayout;
    Colors: TAtlasColors;
    /// <summary>Kennung des aktuellen Issues (#765): Rahmen in Akzentfarbe.</summary>
    ActiveKey: string;
    Folds: TAtlasBoardFolds;
    /// <summary>Beschriftung einer Spalte (Board-Nummer, -1 = ohne Spalte); nil = leer.</summary>
    ColumnName: TFunc<Integer, string>;
    Drag: TAtlasBoardPaintDrag;
    /// <summary>Pixel je Zoll der Zeichenfläche und Abstand zwischen den Spalten (schon skaliert).</summary>
    PixelsPerInch: Integer;
    Gap: Integer;
  end;

  /// <summary>Zeichnet Spalten, Swimlanes und Karten auf eine Leinwand.</summary>
  TAtlasBoardPainter = class
  private
    FCanvas: TCanvas;
    FInput: TAtlasBoardPaintInput;
    function Scaled(AValue: Integer): Integer;
    function ColumnTitle(AIndex: Integer): string;
    function LaneTitle(AIndex: Integer): string;
    procedure PaintCard(const APlace: TAtlasBoardPlace; const ABounds: TRect; AGhost: Boolean);
    procedure PaintColumn(AIndex: Integer);
    procedure PaintLane(AIndex: Integer);
    procedure PaintCorner;
  public
    constructor Create(ACanvas: TCanvas; const AInput: TAtlasBoardPaintInput);
    /// <summary>Ganze Fläche AClient: Hintergrund, Spalten, Swimlanes, Karten, zuletzt die gezogene Karte.</summary>
    procedure Paint(const AClient: TRect);
  end;

/// <summary>"#rrggbb" als Farbe; False bei anderem Text.</summary>
function TryWebColor(const AText: string; out AColor: TColor): Boolean;

implementation

uses
  System.Math,
  Winapi.Windows,
  Atlas.Core.Style.Color,
  Atlas.Core.Tracker.BoardLanes,
  Atlas.UI.Tracker.Board.Strings;

const
  /// <summary>Breite der Markierung der eigenen Swimlane bei 96 dpi.</summary>
  cLaneMark = 3;
  /// <summary>Innenabstand im Namensfeld einer Swimlane und im Kopf darüber bei 96 dpi.</summary>
  cLaneInset = 6;
  /// <summary>"#rrggbb".</summary>
  cWebColorLength = 7;
  /// <summary>Breite des Farbbalkens der Priorität links in der Karte.</summary>
  cPriorityBar = 4;
  /// <summary>Abstand zwischen den Zeichen rechts in der Kopfzeile der Karte und zu ihrem Rand.</summary>
  cMarkGap = 6;
  /// <summary>Innenabstand der Karte oben und links (rechts vom Farbbalken).</summary>
  cCardTop = 4;
  cCardLeft = 10;
  /// <summary>Titel unter der Kopfzeile: Abstand, Zeilen.</summary>
  cTitleTop = 8;
  cTitleLines = 2;
  /// <summary>Innenabstand der Spaltenköpfe bei 96 dpi.</summary>
  cHeaderInset = 6;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

function TryWebColor(const AText: string; out AColor: TColor): Boolean;
var
  mValue: Integer;
  mText: string;
begin
  AColor := clNone;
  mText := Trim(AText);
  Result := (Length(mText) = cWebColorLength) and (mText[1] = '#') and
    TryStrToInt('$' + Copy(mText, 2, cWebColorLength - 1), mValue);
  if Result then
  begin
    AColor := ToColor(TAtlasColorMath.FromHex(mText));
  end;
end;

function PriorityColor(const ACard: TAtlasBoardCard; const AColors: TAtlasColors): TColor;
begin
  if TryWebColor(ACard.PriorityColor, Result) then
  begin
    Exit;
  end;
  case TAtlasTrackerBoard.PriorityLevel(ACard.Priority) of
    TAtlasTrackerBoard.cPriorityCritical:
      Result := ToColor(AColors.Error);
    TAtlasTrackerBoard.cPriorityHigh:
      Result := ToColor(AColors.Warn);
    TAtlasTrackerBoard.cPriorityNormal:
      Result := ToColor(AColors.Accent);
    TAtlasTrackerBoard.cPriorityLow:
      Result := ToColor(AColors.Muted);
  else
    Result := ToColor(AColors.Line);
  end;
end;

/// <summary>Rahmen der Karte (aktuelles Issue in Akzentfarbe, gezogen gepunktet) und Farbbalken der Priorität.
/// </summary>
procedure PaintCardFrame(ACanvas: TCanvas; const AColors: TAtlasColors; const ABounds: TRect; AActive,
  AGhost: Boolean; APriority: TColor);
begin
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := ToColor(AColors.Surface);
  ACanvas.Pen.Color := ToColor(AColors.Line);
  ACanvas.Pen.Width := 1;
  if AActive then
  begin
    ACanvas.Pen.Color := ToColor(AColors.Accent);
    ACanvas.Pen.Width := 2;
  end;
  ACanvas.Pen.Style := psSolid;
  if AGhost then
  begin
    ACanvas.Pen.Style := psDot;
  end;
  ACanvas.Rectangle(ABounds);
  ACanvas.Pen.Style := psSolid;
  ACanvas.Pen.Width := 1;
  ACanvas.Brush.Color := APriority;
  ACanvas.FillRect(Rect(ABounds.Left + 1, ABounds.Top + 1, ABounds.Left + 1 + cPriorityBar, ABounds.Bottom - 1));
  ACanvas.Brush.Style := bsClear;
end;

/// <summary>Kürzel des Zuständigen rechts oben bis ARight; Ergebnis: neuer rechter Rand.</summary>
function PaintAssignee(ACanvas: TCanvas; const AColors: TAtlasColors; const AMark: string; ARight, ATop,
  ALine: Integer): Integer;
var
  mText: TRect;
begin
  ACanvas.Font.Style := [fsBold];
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := ToColor(AColors.AccentSoft);
  mText := Rect(ARight - ACanvas.TextWidth(AMark) - cMarkGap, ATop, ARight, ATop + ALine);
  ACanvas.FillRect(mText);
  ACanvas.Font.Color := ToColor(AColors.Text);
  DrawText(ACanvas.Handle, PChar(AMark), Length(AMark), mText, DT_CENTER or DT_SINGLELINE or DT_VCENTER);
  ACanvas.Brush.Style := bsClear;
  ACanvas.Font.Style := [];
  ACanvas.Font.Color := ToColor(AColors.Muted);
  Result := mText.Left - cMarkGap;
end;

/// <summary>Text AMark rechtsbündig bis ARight; Ergebnis: neuer rechter Rand.</summary>
function PaintMark(ACanvas: TCanvas; const AMark: string; ARight, ATop, ALine: Integer): Integer;
var
  mText: TRect;
begin
  mText := Rect(ARight - ACanvas.TextWidth(AMark), ATop, ARight, ATop + ALine);
  DrawText(ACanvas.Handle, PChar(AMark), Length(AMark), mText, DT_RIGHT or DT_SINGLELINE);
  Result := mText.Left - cMarkGap;
end;

/// <summary>Kopfzeile rechts: Kürzel, Checkliste, Schloss; Ergebnis: Platz für die Kennung bis hier.</summary>
function PaintMarks(ACanvas: TCanvas; const AColors: TAtlasColors; const ACard: TAtlasBoardCard;
  const ABounds: TRect; ALine: Integer): Integer;
var
  mMark: string;
begin
  Result := ABounds.Right - cMarkGap;
  ACanvas.Font.Style := [];
  ACanvas.Font.Color := ToColor(AColors.Muted);
  mMark := TAtlasTrackerBoard.Initials(ACard.Assignee);
  if mMark <> '' then
  begin
    Result := PaintAssignee(ACanvas, AColors, mMark, Result, ABounds.Top + cCardTop, ALine);
  end;
  if ACard.Checklist.Any then
  begin
    if ACard.Checklist.Done = ACard.Checklist.Total then
    begin
      ACanvas.Font.Color := ToColor(AColors.Add);
    end;
    Result := PaintMark(ACanvas, ACard.Checklist.Text, Result, ABounds.Top + cCardTop, ALine);
    ACanvas.Font.Color := ToColor(AColors.Muted);
  end;
  if ACard.Locked then
  begin
    Result := PaintMark(ACanvas, '⛔', Result, ABounds.Top + cCardTop, ALine);
  end;
end;

{ TAtlasBoardPainter }

constructor TAtlasBoardPainter.Create(ACanvas: TCanvas; const AInput: TAtlasBoardPaintInput);
begin
  inherited Create;
  FCanvas := ACanvas;
  FInput := AInput;
end;

function TAtlasBoardPainter.Scaled(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, FInput.PixelsPerInch, 96);
end;

procedure TAtlasBoardPainter.PaintCard(const APlace: TAtlasBoardPlace; const ABounds: TRect; AGhost: Boolean);
var
  mCard: TAtlasBoardCard;
  mText: TRect;
  mLine, mRight: Integer;
begin
  mCard := FInput.Snapshot.Cards[APlace.Card];
  mLine := FCanvas.TextHeight('Ag');
  PaintCardFrame(FCanvas, FInput.Colors, ABounds, SameText(mCard.Key, FInput.ActiveKey), AGhost,
    PriorityColor(mCard, FInput.Colors));
  // Kopfzeile: Kennung links; rechts Kürzel, Checkliste, Schloss.
  mRight := PaintMarks(FCanvas, FInput.Colors, mCard, ABounds, mLine);
  FCanvas.Font.Style := [fsBold];
  FCanvas.Font.Color := ToColor(FInput.Colors.Accent);
  mText := Rect(ABounds.Left + cCardLeft, ABounds.Top + cCardTop, Max(mRight, ABounds.Left + cCardLeft),
    ABounds.Top + cCardTop + mLine);
  DrawText(FCanvas.Handle, PChar(mCard.Key), Length(mCard.Key), mText, DT_LEFT or DT_SINGLELINE or DT_END_ELLIPSIS);
  // Titel in zwei Zeilen.
  FCanvas.Font.Style := [];
  FCanvas.Font.Color := ToColor(FInput.Colors.Text);
  mText := Rect(ABounds.Left + cCardLeft, ABounds.Top + cTitleTop + mLine, ABounds.Right - cMarkGap,
    ABounds.Top + cTitleTop + (1 + cTitleLines) * mLine);
  DrawText(FCanvas.Handle, PChar(mCard.Title), Length(mCard.Title), mText,
    DT_LEFT or DT_WORDBREAK or DT_END_ELLIPSIS or DT_EDITCONTROL or DT_NOPREFIX);
end;

/// <summary>Kopfzeile einer Spalte: „NAME (n)“, schmal mit Pfeil zum Auf- und Zuklappen.</summary>
function TAtlasBoardPainter.ColumnTitle(AIndex: Integer): string;
var
  mColumn: Integer;
  mName: string;
begin
  mColumn := FInput.Layout.Columns[AIndex];
  mName := '';
  if Assigned(FInput.ColumnName) then
  begin
    mName := FInput.ColumnName(mColumn);
  end;
  Result := TAtlasBoardStrings.Fmt(TAtlasBoardTextId.BoardColumnCount,
    [AnsiUpperCase(mName), FInput.Layout.Counts[AIndex]]);
  if not FInput.Layout.Narrow then
  begin
    Exit;
  end;
  if FInput.Folds.Collapsed(mColumn) then
  begin
    Result := '▸ ' + Result;
  end
  else
  begin
    Result := '▾ ' + Result;
  end;
end;

procedure TAtlasBoardPainter.PaintColumn(AIndex: Integer);
var
  mColumn: Integer;
  mText: string;
  mRect: TRect;
begin
  mColumn := FInput.Layout.Columns[AIndex];
  // Fläche der Spalte; Ziel beim Ziehen hervorgehoben.
  FCanvas.Brush.Color := ToColor(FInput.Colors.Gutter);
  if FInput.Drag.Dragging and (mColumn = FInput.Drag.DropColumn) and
    TAtlasBoardTransitions.Allowed(FInput.Snapshot, FInput.Drag.Card, mColumn) then
  begin
    FCanvas.Brush.Color := ToColor(FInput.Colors.Selection);
  end;
  FCanvas.FillRect(FInput.Layout.Areas[AIndex]);
  mText := ColumnTitle(AIndex);
  FCanvas.Brush.Style := bsClear;
  FCanvas.Font.Style := [fsBold];
  FCanvas.Font.Color := ToColor(FInput.Colors.Muted);
  mRect := FInput.Layout.Headers[AIndex];
  InflateRect(mRect, -Scaled(cHeaderInset), 0);
  DrawText(FCanvas.Handle, PChar(mText), Length(mText), mRect,
    DT_LEFT or DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX);
  FCanvas.Font.Style := [];
  FCanvas.Brush.Style := bsSolid;
end;

/// <summary>Beschriftung einer Swimlane: Pfeil, Name bzw. „Ohne Zuordnung“, Anzahl.</summary>
function TAtlasBoardPainter.LaneTitle(AIndex: Integer): string;
var
  mLane: TAtlasBoardLane;
  mName: string;
begin
  mLane := FInput.Layout.Lanes[AIndex];
  mName := mLane.Name;
  if mLane.Orphans then
  begin
    mName := TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardLaneNone);
  end;
  Result := TAtlasBoardStrings.Fmt(TAtlasBoardTextId.BoardColumnCount, [mName, FInput.Layout.LaneCounts[AIndex]]);
  if FInput.Folds.LaneCollapsed(TAtlasBoardLayout.LaneKey(mLane)) then
  begin
    Result := '▸ ' + Result;
  end
  else
  begin
    Result := '▾ ' + Result;
  end;
end;

procedure TAtlasBoardPainter.PaintLane(AIndex: Integer);
var
  mBox, mText: TRect;
  mTitle: string;
begin
  mBox := FInput.Layout.LaneBoxes[AIndex];
  // Trennlinie über die ganze Breite, Namensfeld links.
  FCanvas.Brush.Style := bsSolid;
  FCanvas.Brush.Color := ToColor(FInput.Colors.Line);
  FCanvas.FillRect(Rect(mBox.Left, mBox.Top, FInput.Layout.Width - FInput.Gap, mBox.Top + 1));
  FCanvas.Brush.Color := ToColor(FInput.Colors.Gutter);
  FCanvas.FillRect(Rect(mBox.Left, mBox.Top + 1, mBox.Right, mBox.Bottom));
  if TAtlasBoardLanes.Mine(FInput.Layout.Lanes[AIndex], FInput.Snapshot.Me) then
  begin
    FCanvas.Brush.Color := ToColor(FInput.Colors.Accent);
    FCanvas.FillRect(Rect(mBox.Left, mBox.Top + 1, mBox.Left + Scaled(cLaneMark), mBox.Bottom));
  end;
  mTitle := LaneTitle(AIndex);
  mText := Rect(mBox.Left + Scaled(cLaneMark + cLaneInset), mBox.Top + Scaled(cLaneInset),
    mBox.Right - Scaled(cLaneInset), mBox.Bottom);
  FCanvas.Brush.Style := bsClear;
  FCanvas.Font.Style := [fsBold];
  FCanvas.Font.Color := ToColor(FInput.Colors.Text);
  DrawText(FCanvas.Handle, PChar(mTitle), Length(mTitle), mText,
    DT_LEFT or DT_WORDBREAK or DT_END_ELLIPSIS or DT_EDITCONTROL or DT_NOPREFIX);
  FCanvas.Font.Style := [];
  FCanvas.Brush.Style := bsSolid;
end;

/// <summary>Kopf über den Namen der Swimlanes: Name des Feldes.</summary>
procedure TAtlasBoardPainter.PaintCorner;
var
  mText: string;
  mRect: TRect;
begin
  mText := AnsiUpperCase(FInput.Snapshot.Swimlanes.Caption);
  mRect := FInput.Layout.Corner;
  InflateRect(mRect, -Scaled(cLaneInset), 0);
  FCanvas.Brush.Style := bsClear;
  FCanvas.Font.Style := [fsBold];
  FCanvas.Font.Color := ToColor(FInput.Colors.Muted);
  DrawText(FCanvas.Handle, PChar(mText), Length(mText), mRect,
    DT_LEFT or DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX);
  FCanvas.Font.Style := [];
  FCanvas.Brush.Style := bsSolid;
end;

procedure TAtlasBoardPainter.Paint(const AClient: TRect);
var
  mIndex: Integer;
  mPlace: TAtlasBoardPlace;
  mRect: TRect;
begin
  FCanvas.Brush.Style := bsSolid;
  FCanvas.Brush.Color := ToColor(FInput.Colors.Surface);
  FCanvas.FillRect(AClient);
  for mIndex := 0 to High(FInput.Layout.Columns) do
  begin
    PaintColumn(mIndex);
  end;
  if Length(FInput.Layout.Lanes) > 0 then
  begin
    PaintCorner;
  end;
  for mIndex := 0 to High(FInput.Layout.Lanes) do
  begin
    PaintLane(mIndex);
  end;
  for mPlace in FInput.Layout.Places do
  begin
    PaintCard(mPlace, mPlace.Bounds, FInput.Drag.Dragging and (mPlace.Card = FInput.Drag.Card));
  end;
  // Gezogene Karte unter der Maus.
  if FInput.Drag.Dragging and FInput.Layout.PlaceOf(FInput.Drag.Card, mPlace) then
  begin
    mRect := mPlace.Bounds;
    mRect.Offset(FInput.Drag.Offset.X, FInput.Drag.Offset.Y);
    PaintCard(mPlace, mRect, False);
  end;
end;

end.
