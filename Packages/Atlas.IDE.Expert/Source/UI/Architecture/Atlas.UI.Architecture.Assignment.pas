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
  Atlas.UI.Strings;

class function TAtlasArchitectureAssignment.Available(const AModel: TAtlasArchitectureModel;
  AUnit: Integer): Boolean;
begin
  Result := (AUnit >= 0) and (AUnit < Length(AModel.Units)) and (Length(AModel.Units[AUnit].Assignment) > 0);
end;

class function TAtlasArchitectureAssignment.Head(const AModel: TAtlasArchitectureModel; AUnit: Integer): string;
begin
  Result := '';
  if not Available(AModel, AUnit) then
    Exit;
  // Hat ein anderes Teilsystem schon gleich viele Kanten, entschied Louvain über das ganze Teilsystem.
  if AModel.Units[AUnit].Close and (AModel.Units[AUnit].Missing = 0) then
    Result := TAtlasStrings.Fmt(TAtlasTextId.ArchitectureAssignmentHeadTie,
      [AModel.SubsystemName(AModel.Units[AUnit].Subsystem)])
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.ArchitectureAssignmentHead,
      [AModel.SubsystemName(AModel.Units[AUnit].Subsystem)]);
end;

class function TAtlasArchitectureAssignment.Cells(const AModel: TAtlasArchitectureModel;
  AUnit, ARow: Integer): TArray<string>;
var
  mRow: TAtlasArchAssignmentRow;
  mLast: string;
begin
  Result := nil;
  if not Available(AModel, AUnit) or (ARow < 0) or (ARow > High(AModel.Units[AUnit].Assignment)) then
    Exit;
  mRow := AModel.Units[AUnit].Assignment[ARow];
  if mRow.Counts then
    mLast := TAtlasStrings.Fmt(TAtlasTextId.ArchitectureAssignmentSum, [mRow.Sum])
  else
    mLast := TAtlasStrings.Text(TAtlasTextId.ArchitectureAssignmentNotCounted);
  Result := TArray<string>.Create(AModel.SubsystemName(mRow.Subsystem),
    TAtlasStrings.Fmt(TAtlasTextId.ArchitectureAssignmentInterface, [mRow.Interfaces]),
    TAtlasStrings.Fmt(TAtlasTextId.ArchitectureAssignmentImplementation, [mRow.Implementations]), mLast);
end;

class function TAtlasArchitectureAssignment.CloseLine(const AModel: TAtlasArchitectureModel;
  AUnit: Integer): string;
var
  mRival, mOwn: Integer;
  mName: string;
begin
  Result := '';
  if not Available(AModel, AUnit) or not AModel.Units[AUnit].Close then
    Exit;
  mRival := AModel.RivalRow(AUnit);
  mOwn := AModel.OwnRow(AUnit);
  if (mRival < 0) or (mOwn < 0) then
    Exit;
  mName := AModel.SubsystemName(AModel.Units[AUnit].Assignment[mRival].Subsystem);
  case AModel.Units[AUnit].Missing of
    0:
      Result := TAtlasStrings.Fmt(TAtlasTextId.ArchitectureAssignmentCloseTie, [mName,
        AModel.Units[AUnit].Assignment[mRival].Sum, AModel.Units[AUnit].Assignment[mOwn].Sum]);
    1:
      Result := TAtlasStrings.Fmt(TAtlasTextId.ArchitectureAssignmentCloseOne, [mName]);
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.ArchitectureAssignmentClose, [AModel.Units[AUnit].Missing, mName]);
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
    Exit;
  mRival := AModel.RivalRow(AUnit);
  if mRival < 0 then
    Exit;
  mName := AModel.SubsystemName(AModel.Units[AUnit].Assignment[mRival].Subsystem);
  case AModel.Units[AUnit].Missing of
    0:
      Result := TAtlasStrings.Fmt(TAtlasTextId.ArchitectureCloseMarkTie, [mName]);
    1:
      Result := TAtlasStrings.Fmt(TAtlasTextId.ArchitectureCloseMarkOne, [mName]);
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.ArchitectureCloseMark, [AModel.Units[AUnit].Missing, mName]);
  end;
end;

class function TAtlasArchitectureAssignment.Explanation(const AModel: TAtlasArchitectureModel): string;
var
  mShare, mCohesion, mFoundations: string;
begin
  if AModel.MaxShare > 0 then
    mShare := TAtlasStrings.Fmt(TAtlasTextId.ArchitectureSplitShare, [Round(AModel.MaxShare * 100)])
  else
    mShare := TAtlasStrings.Text(TAtlasTextId.ArchitectureSettingOff);
  if AModel.MinCohesion > 0 then
    mCohesion := TAtlasStrings.Fmt(TAtlasTextId.ArchitectureSplitCohesion,
      [TAtlasArchResolution.Text(AModel.MinCohesion, FormatSettings)])
  else
    mCohesion := TAtlasStrings.Text(TAtlasTextId.ArchitectureSettingOff);
  if AModel.Foundations = 'group' then
    mFoundations := TAtlasStrings.Text(TAtlasTextId.ArchitectureFoundationsGroup)
  else if AModel.Foundations = 'attach' then
    mFoundations := TAtlasStrings.Text(TAtlasTextId.ArchitectureFoundationsAttach)
  else
    mFoundations := TAtlasStrings.Text(TAtlasTextId.ArchitectureFoundationsSeparate);
  Result := TAtlasStrings.Text(TAtlasTextId.ArchitectureExplanation) + sLineBreak +
    TAtlasStrings.Fmt(TAtlasTextId.ArchitectureExplanationSettings, [TAtlasArchResolution.Text(AModel.Resolution,
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
      AWidths[mCell] := Max(AWidths[mCell], ACanvas.TextWidth(mCells[mCell]));
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
    Exit;
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
    Inc(Result.cy, mLine);
  Result.cx := mWidth + 2 * mPadding;
end;

class procedure TAtlasArchitectureAssignment.Draw(ACanvas: TCanvas; const ARect: TRect;
  const AModel: TAtlasArchitectureModel; AUnit, APpi: Integer; const AColors: TAtlasColors);
var
  mWidths: TArray<Integer>;
  mLine, mPadding, mGap, mX, mY, mRow, mLeft, mDot: Integer;
  mCells: TArray<string>;
  mClose: string;
  mStyle: TFontStyles;
begin
  if not Available(AModel, AUnit) then
    Exit;
  Columns(ACanvas, AModel, AUnit, APpi, mWidths, mLine);
  mPadding := MulDiv(cPadding, APpi, 96);
  mGap := MulDiv(cColumnGap, APpi, 96);
  mDot := MulDiv(cDotSize, APpi, 96);
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := TColor(AColors.Surface);
  ACanvas.Pen.Style := psSolid;
  ACanvas.Pen.Width := 1;
  ACanvas.Pen.Color := TColor(AColors.Line);
  ACanvas.Rectangle(ARect);
  ACanvas.Brush.Style := bsClear;
  mX := ARect.Left + mPadding;
  mY := ARect.Top + mPadding;
  ACanvas.Font.Color := TColor(AColors.Text);
  mStyle := ACanvas.Font.Style;
  ACanvas.Font.Style := mStyle + [fsBold];
  ACanvas.TextOut(mX, mY, AModel.Units[AUnit].Name);
  ACanvas.Font.Style := mStyle;
  Inc(mY, mLine);
  ACanvas.Font.Color := TColor(AColors.Muted);
  ACanvas.TextOut(mX, mY, Head(AModel, AUnit));
  Inc(mY, mLine);
  for mRow := 0 to High(AModel.Units[AUnit].Assignment) do
  begin
    mCells := Cells(AModel, AUnit, mRow);
    // Farbpunkt des Teilsystems wie in Karte und Legende.
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := TColor(AModel.SubsystemColor(AModel.Units[AUnit].Assignment[mRow].Subsystem,
      AColors.IsDark));
    ACanvas.Pen.Color := ACanvas.Brush.Color;
    ACanvas.Ellipse(mX, mY + (mLine - mDot) div 2, mX + mDot, mY + (mLine - mDot) div 2 + mDot);
    ACanvas.Brush.Style := bsClear;
    if AModel.Units[AUnit].Assignment[mRow].Counts then
      ACanvas.Font.Color := TColor(AColors.Text)
    else
      ACanvas.Font.Color := TColor(AColors.Muted);
    ACanvas.TextOut(mX + mDot + MulDiv(6, APpi, 96), mY, mCells[0]);
    // Zahlen rechtsbündig.
    mLeft := mX + mWidths[0];
    ACanvas.TextOut(mLeft + mGap + mWidths[1] - ACanvas.TextWidth(mCells[1]), mY, mCells[1]);
    Inc(mLeft, mGap + mWidths[1]);
    ACanvas.TextOut(mLeft + mGap + mWidths[2] - ACanvas.TextWidth(mCells[2]), mY, mCells[2]);
    Inc(mLeft, mGap + mWidths[2]);
    ACanvas.TextOut(mLeft + mGap + mWidths[3] - ACanvas.TextWidth(mCells[3]), mY, mCells[3]);
    Inc(mY, mLine);
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
