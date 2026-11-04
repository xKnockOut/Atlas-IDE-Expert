unit Atlas.UI.Architecture.Assignment;

// Zuordnung einer Unit im Fenster „Atlas-Architektur“ (#1368), reine VCL:
// Kopf („Teilsystem X, weil die meisten Kanten dorthin gehen:“), je
// Teilsystem eine Zeile mit Farbpunkt, „n × interface“, „n × impl.“ und
// Summe bzw. „zählt nicht“ (Kanten zum Fundament), darunter die Knapp-Zeile
// in Warnfarbe, wie im Steckbrief des HTML-Berichts. Dieselbe Zeichnung
// dient dem Hinweis auf der Karte (TAtlasArchitectureMap) und dem Steckbrief
// unter der Karte. Texte aus TAtlasStrings, Daten aus
// TAtlasArchitectureModel (ohne architecture.explainAssignment leer, dann
// zeichnet nichts). Dazu die Markierung „knapp“ für den Reiter „Teilsysteme“
// und die Erklärung hinter dessen Fragezeichen.

interface

uses
  System.SysUtils,
  System.Types,
  Vcl.Graphics,
  Atlas.Core.Style.Palette,
  Atlas.Core.Architecture.Model;

type
  TAtlasArchitectureAssignment = class
  public const
    /// <summary>Innenabstand und Abstand der Spalten in Bildpunkten bei 96 dpi.</summary>
    cPadding = 8;
    cColumnGap = 12;
    cDotSize = 9;
  public
    /// <summary>Die Unit hat eine Zuordnung zum Zeigen.</summary>
    class function Available(const AModel: TAtlasArchitectureModel; AUnit: Integer): Boolean; static;
    class function Head(const AModel: TAtlasArchitectureModel; AUnit: Integer): string; static;
    /// <summary>Vier Zellen der Zeile ARow: Teilsystem, interface, implementation, Summe bzw. „zählt nicht“.
    /// </summary>
    class function Cells(const AModel: TAtlasArchitectureModel; AUnit, ARow: Integer): TArray<string>; static;
    /// <summary>„Knapp: Mit 3 weiteren Kanten zu X läge sie dort.“; '' bei klarer Zuordnung.</summary>
    class function CloseLine(const AModel: TAtlasArchitectureModel; AUnit: Integer): string; static;
    /// <summary>Kurzform für den Baum „Teilsysteme“: „knapp, 3 Kanten fehlen zu X“; '' bei klarer Zuordnung.
    /// </summary>
    class function CloseMark(const AModel: TAtlasArchitectureModel; AUnit: Integer): string; static;
    /// <summary>Wie Atlas die Teilsysteme bildet, mit den Einstellungen aus AModel.</summary>
    class function Explanation(const AModel: TAtlasArchitectureModel): string; static;
    /// <summary>Größe der Zeichnung mit der Schrift von ACanvas, APpi für die Abstände.</summary>
    class function Measure(ACanvas: TCanvas; const AModel: TAtlasArchitectureModel; AUnit, APpi: Integer): TSize;
      static;
    /// <summary>Zeichnet in ARect (Größe aus Measure) mit Hintergrund und Rand.</summary>
    class procedure Draw(ACanvas: TCanvas; const ARect: TRect; const AModel: TAtlasArchitectureModel;
      AUnit, APpi: Integer; const AColors: TAtlasColors); static;
  end;

implementation

uses
  System.Math,
  System.UITypes,
  Winapi.Windows,
  Atlas.UI.Strings,
  Atlas.UI.Analysis.Strings;

class function TAtlasArchitectureAssignment.Available(const AModel: TAtlasArchitectureModel;
  AUnit: Integer): Boolean;
begin
  Result := (AUnit >= 0) and (AUnit < Length(AModel.Units)) and (Length(AModel.Units[AUnit].Assignment) > 0);
end;

class function TAtlasArchitectureAssignment.Head(const AModel: TAtlasArchitectureModel; AUnit: Integer): string;
begin
  Result := '';
  if not Available(AModel, AUnit) then
  begin
    Exit;
  end;
  // Hat ein anderes Teilsystem schon gleich viele Kanten, entschied Louvain über das ganze Teilsystem.
  if AModel.Units[AUnit].Close and (AModel.Units[AUnit].Missing = 0) then
  begin
    Result := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureAssignmentHeadTie,
      [AModel.SubsystemName(AModel.Units[AUnit].Subsystem)]);
  end
  else
  begin
    Result := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureAssignmentHead,
      [AModel.SubsystemName(AModel.Units[AUnit].Subsystem)]);
  end;
end;

class function TAtlasArchitectureAssignment.Cells(const AModel: TAtlasArchitectureModel;
  AUnit, ARow: Integer): TArray<string>;
var
  mRow: TAtlasArchAssignmentRow;
  mLast: string;
begin
  Result := nil;
  if not Available(AModel, AUnit) or (ARow < 0) or (ARow > High(AModel.Units[AUnit].Assignment)) then
  begin
    Exit;
  end;
  mRow := AModel.Units[AUnit].Assignment[ARow];
  if mRow.Counts then
  begin
    mLast := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureAssignmentSum, [mRow.Sum]);
  end
  else
  begin
    mLast := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureAssignmentNotCounted);
  end;
  Result := TArray<string>.Create(AModel.SubsystemName(mRow.Subsystem),
    TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureAssignmentInterface, [mRow.Interfaces]),
    TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureAssignmentImplementation, [mRow.Implementations]),
      mLast);
end;

class function TAtlasArchitectureAssignment.CloseLine(const AModel: TAtlasArchitectureModel;
  AUnit: Integer): string;
var
  mRival, mOwn: Integer;
  mName: string;
begin
  Result := '';
  if not Available(AModel, AUnit) or not AModel.Units[AUnit].Close then
  begin
    Exit;
  end;
  mRival := AModel.RivalRow(AUnit);
  mOwn := AModel.OwnRow(AUnit);
  if (mRival < 0) or (mOwn < 0) then
  begin
    Exit;
  end;
  mName := AModel.SubsystemName(AModel.Units[AUnit].Assignment[mRival].Subsystem);
  case AModel.Units[AUnit].Missing of
    0:
      Result := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureAssignmentCloseTie, [mName,
        AModel.Units[AUnit].Assignment[mRival].Sum, AModel.Units[AUnit].Assignment[mOwn].Sum]);
    1:
      Result := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureAssignmentCloseOne, [mName]);
  else
    Result := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureAssignmentClose,
      [AModel.Units[AUnit].Missing, mName]);
  end;
end;

class function TAtlasArchitectureAssignment.CloseMark(const AModel: TAtlasArchitectureModel;
  AUnit: Integer): string;
var
  mRival: Integer;
  mName: string;
begin
  Result := '';
  if not Available(AModel, AUnit) or not AModel.Units[AUnit].Close then
  begin
    Exit;
  end;
  mRival := AModel.RivalRow(AUnit);
  if mRival < 0 then
  begin
    Exit;
  end;
  mName := AModel.SubsystemName(AModel.Units[AUnit].Assignment[mRival].Subsystem);
  case AModel.Units[AUnit].Missing of
    0:
      Result := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureCloseMarkTie, [mName]);
    1:
      Result := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureCloseMarkOne, [mName]);
  else
    Result := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureCloseMark,
      [AModel.Units[AUnit].Missing, mName]);
  end;
end;

class function TAtlasArchitectureAssignment.Explanation(const AModel: TAtlasArchitectureModel): string;
var
  mShare, mCohesion, mFoundations: string;
begin
  if AModel.MaxShare > 0 then
  begin
    mShare := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureSplitShare, [Round(AModel.MaxShare * 100)]);
  end
  else
  begin
    mShare := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureSettingOff);
  end;
  if AModel.MinCohesion > 0 then
  begin
    mCohesion := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureSplitCohesion,
      [TAtlasArchResolution.Text(AModel.MinCohesion, FormatSettings)]);
  end
  else
  begin
    mCohesion := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureSettingOff);
  end;
  if AModel.Foundations = 'group' then
  begin
    mFoundations := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureFoundationsGroup);
  end
  else if AModel.Foundations = 'attach' then
  begin
    mFoundations := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureFoundationsAttach);
  end
  else
  begin
    mFoundations := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureFoundationsSeparate);
  end;
  Result := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.ArchitectureExplanation) + sLineBreak +
    TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.ArchitectureExplanationSettings,
      [TAtlasArchResolution.Text(AModel.Resolution,
    FormatSettings), mShare, mCohesion, mFoundations]);
end;

/// <summary>Spaltenbreiten der Tabelle (erste mit Farbpunkt) und Zeilenhöhe.</summary>
procedure Columns(ACanvas: TCanvas; const AModel: TAtlasArchitectureModel; AUnit, APpi: Integer;
  out AWidths: TArray<Integer>; out ALine: Integer);
var
  mRow, mCell: Integer;
  mCells: TArray<string>;
begin
  SetLength(AWidths, 4);
  ALine := ACanvas.TextHeight('Ag') + MulDiv(2, APpi, 96);
  for mRow := 0 to High(AModel.Units[AUnit].Assignment) do
  begin
    mCells := TAtlasArchitectureAssignment.Cells(AModel, AUnit, mRow);
    for mCell := 0 to High(mCells) do
    begin
      AWidths[mCell] := Max(AWidths[mCell], ACanvas.TextWidth(mCells[mCell]));
    end;
  end;
  Inc(AWidths[0], MulDiv(TAtlasArchitectureAssignment.cDotSize + 6, APpi, 96));
end;

class function TAtlasArchitectureAssignment.Measure(ACanvas: TCanvas; const AModel: TAtlasArchitectureModel;
  AUnit, APpi: Integer): TSize;
var
  mWidths: TArray<Integer>;
  mLine, mWidth, mPadding, mGap: Integer;
  mStyle: TFontStyles;
begin
  Result := TSize.Create(0, 0);
  if not Available(AModel, AUnit) then
  begin
    Exit;
  end;
  Columns(ACanvas, AModel, AUnit, APpi, mWidths, mLine);
  mPadding := MulDiv(cPadding, APpi, 96);
  mGap := MulDiv(cColumnGap, APpi, 96);
  mWidth := mWidths[0] + mWidths[1] + mWidths[2] + mWidths[3] + 3 * mGap;
  mStyle := ACanvas.Font.Style;
  ACanvas.Font.Style := mStyle + [fsBold];
  mWidth := Max(mWidth, ACanvas.TextWidth(AModel.Units[AUnit].Name));
  ACanvas.Font.Style := mStyle;
  mWidth := Max(mWidth, ACanvas.TextWidth(Head(AModel, AUnit)));
  mWidth := Max(mWidth, ACanvas.TextWidth(CloseLine(AModel, AUnit)));
  // Name, Kopf, Zeilen, Knapp-Zeile.
  Result.cy := 2 * mPadding + (2 + Length(AModel.Units[AUnit].Assignment)) * mLine;
  if CloseLine(AModel, AUnit) <> '' then
  begin
    Inc(Result.cy, mLine);
  end;
  Result.cx := mWidth + 2 * mPadding;
end;

type
  /// <summary>Was das Zeichnen einer Tabellenzeile braucht.</summary>
  TAssignmentTable = record
    Canvas: TCanvas;
    Widths: TArray<Integer>;
    Line: Integer;
    Gap: Integer;
    Dot: Integer;
    Ppi: Integer;
    Colors: TAtlasColors;
  end;

/// <summary>Zeile ARow der Zuordnung bei (AX, AY): Farbpunkt des Teilsystems wie in Karte und Legende, Name, Zahlen
/// rechtsbündig.</summary>
procedure DrawRow(const ATable: TAssignmentTable; const AModel: TAtlasArchitectureModel; AUnit, ARow, AX,
  AY: Integer);
var
  mCells: TArray<string>;
  mLeft, mCell: Integer;
  mCanvas: TCanvas;
begin
  mCanvas := ATable.Canvas;
  mCells := TAtlasArchitectureAssignment.Cells(AModel, AUnit, ARow);
  mCanvas.Brush.Style := bsSolid;
  mCanvas.Brush.Color := TColor(AModel.SubsystemColor(AModel.Units[AUnit].Assignment[ARow].Subsystem,
    ATable.Colors.IsDark));
  mCanvas.Pen.Color := mCanvas.Brush.Color;
  mCanvas.Ellipse(AX, AY + (ATable.Line - ATable.Dot) div 2, AX + ATable.Dot,
    AY + (ATable.Line - ATable.Dot) div 2 + ATable.Dot);
  mCanvas.Brush.Style := bsClear;
  if AModel.Units[AUnit].Assignment[ARow].Counts then
  begin
    mCanvas.Font.Color := TColor(ATable.Colors.Text);
  end
  else
  begin
    mCanvas.Font.Color := TColor(ATable.Colors.Muted);
  end;
  mCanvas.TextOut(AX + ATable.Dot + MulDiv(6, ATable.Ppi, 96), AY, mCells[0]);
  mLeft := AX + ATable.Widths[0];
  for mCell := 1 to 3 do
  begin
    mCanvas.TextOut(mLeft + ATable.Gap + ATable.Widths[mCell] - mCanvas.TextWidth(mCells[mCell]), AY,
      mCells[mCell]);
    Inc(mLeft, ATable.Gap + ATable.Widths[mCell]);
  end;
end;

/// <summary>Hintergrund und Rand.</summary>
procedure DrawFrame(ACanvas: TCanvas; const ARect: TRect; const AColors: TAtlasColors);
begin
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := TColor(AColors.Surface);
  ACanvas.Pen.Style := psSolid;
  ACanvas.Pen.Width := 1;
  ACanvas.Pen.Color := TColor(AColors.Line);
  ACanvas.Rectangle(ARect);
  ACanvas.Brush.Style := bsClear;
end;

class procedure TAtlasArchitectureAssignment.Draw(ACanvas: TCanvas; const ARect: TRect;
  const AModel: TAtlasArchitectureModel; AUnit, APpi: Integer; const AColors: TAtlasColors);
var
  mTable: TAssignmentTable;
  mPadding, mX, mY, mRow: Integer;
  mClose: string;
  mStyle: TFontStyles;
begin
  if not Available(AModel, AUnit) then
  begin
    Exit;
  end;
  mTable.Canvas := ACanvas;
  Columns(ACanvas, AModel, AUnit, APpi, mTable.Widths, mTable.Line);
  mTable.Gap := MulDiv(cColumnGap, APpi, 96);
  mTable.Dot := MulDiv(cDotSize, APpi, 96);
  mTable.Ppi := APpi;
  mTable.Colors := AColors;
  mPadding := MulDiv(cPadding, APpi, 96);
  DrawFrame(ACanvas, ARect, AColors);
  mX := ARect.Left + mPadding;
  mY := ARect.Top + mPadding;
  ACanvas.Font.Color := TColor(AColors.Text);
  mStyle := ACanvas.Font.Style;
  ACanvas.Font.Style := mStyle + [fsBold];
  ACanvas.TextOut(mX, mY, AModel.Units[AUnit].Name);
  ACanvas.Font.Style := mStyle;
  Inc(mY, mTable.Line);
  ACanvas.Font.Color := TColor(AColors.Muted);
  ACanvas.TextOut(mX, mY, Head(AModel, AUnit));
  Inc(mY, mTable.Line);
  for mRow := 0 to High(AModel.Units[AUnit].Assignment) do
  begin
    DrawRow(mTable, AModel, AUnit, mRow, mX, mY);
    Inc(mY, mTable.Line);
  end;
  mClose := CloseLine(AModel, AUnit);
  if mClose <> '' then
  begin
    ACanvas.Font.Color := TColor(AColors.Warn);
    ACanvas.TextOut(mX, mY, mClose);
  end;
  ACanvas.Font.Color := TColor(AColors.Text);
end;

end.
