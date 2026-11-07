unit Atlas.UI.Debug.StepInto;

// Gezielt hineinspringen (#836), Fensterteil (nur VCL): Liste der Aufrufe an
// der Ausführungszeile im Atlas-Stil (#410, #411).
//   Gezielt hineinspringen
//   › 1  TKunde.GetName  Getter   Kunden.pas:27
//     2  Format                   ohne Quelltext
//     3  Pruefe                   Haupt.pas:51
//     4  Speichere                Haupt.pas:12
//   ↑/↓ und Enter oder 1–9 wählen  ·  Esc schließt
// Nicht wählbare Einträge (ohne Quelltext, Bibliothek ohne Debug-DCUs) stehen
// gedämpft mit Grund da. Die IDE-Seite leitet die Tasten weiter, das Fenster
// bekommt nie den Fokus; ein Klick auf einen Eintrag wählt ihn.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  Vcl.Controls,
  Atlas.Core.Debug.StepInto,
  Atlas.UI.Popup.Window;

type
  TAtlasStepIntoIndexEvent = reference to procedure(AIndex: Integer);

  TAtlasStepIntoWindow = class(TAtlasPopupWindow)
  public const
    /// <summary>Abstand unter der Zeile, logische Pixel.</summary>
    cGap = 4;
  private
    FRows: TArray<TAtlasStepRow>;
    FRow: Integer;
    FRowRects: TArray<TRect>;
    FOnAccept: TAtlasStepIntoIndexEvent;
    FOnCancel: TProc;
    function Layout(ADraw: Boolean): TSize;
    /// <summary>Schriftfarbe der Zeile AIndex: gewählt, wählbar oder grau.</summary>
    function RowColor(AIndex: Integer): TColor;
    /// <summary>Zeile AIndex auf Höhe AY anordnen (mit ADraw auch zeichnen), Ort ab ARightX; Ergebnis: rechter Rand.
    /// </summary>
    function LayoutRow(AIndex, AY, ARightX, ATextHeight: Integer; ADraw: Boolean): Integer;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>„Getter“, „Konstruktor“ … bzw. '' bei einem einfachen Aufruf.</summary>
    class function KindText(const ARow: TAtlasStepRow): string; static;
    /// <summary>Grund, warum ein Eintrag nicht wählbar ist; '' wenn er es ist.</summary>
    class function ReasonText(const ARow: TAtlasStepRow): string; static;
    /// <summary>„1  TKunde.GetName  Getter“ ohne Ort.</summary>
    class function RowCaption(const ARows: TArray<TAtlasStepRow>; AIndex: Integer): string; static;
    /// <summary>Zeigt ARows unter APoint (Bildschirm) und wählt den ersten wählbaren Eintrag.</summary>
    procedure ShowFor(const ARows: TArray<TAtlasStepRow>; const APoint: TPoint);
    procedure Dismiss;
    /// <summary>Nächster bzw. voriger wählbarer Eintrag; False ohne solche.</summary>
    function MoveRow(ADelta: Integer): Boolean;
    /// <summary>Ziffer 1–9: Eintrag wählen und übernehmen; False, wenn er nicht wählbar ist.</summary>
    function AcceptDigit(ADigit: Integer): Boolean;
    procedure Select(AIndex: Integer);
    function RowRect(AIndex: Integer): TRect;
    /// <summary>Gewählten Eintrag übernehmen (OnAccept); ohne Wahl nichts.</summary>
    procedure Accept;
    procedure Cancel;
    property Rows: TArray<TAtlasStepRow> read FRows;
    property Row: Integer read FRow;
    property OnAccept: TAtlasStepIntoIndexEvent read FOnAccept write FOnAccept;
    property OnCancel: TProc read FOnCancel write FOnCancel;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Strings,
  Atlas.UI.Debug.Strings,
  Atlas.UI.Popup.Accessibility;

const
  cPad = 10;
  cRowGap = 4;
  cColumnGap = 16;
  cMarker = '› ';

{ TAtlasStepIntoWindow }

constructor TAtlasStepIntoWindow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  GuardFeature := TAtlasFeature.Debugger;
  FRow := -1;
  SetAccessible(UiaListControlType, TAtlasStrings.Text(TAtlasTextId.StepIntoTargetCommand));
end;

class function TAtlasStepIntoWindow.KindText(const ARow: TAtlasStepRow): string;
begin
  case ARow.Kind of
    TAtlasStepKind.Getter:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.StepIntoTargetGetter);
    TAtlasStepKind.Setter:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.StepIntoTargetSetter);
    TAtlasStepKind.Constructor_:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.StepIntoTargetConstructor);
    TAtlasStepKind.Inherited_:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.StepIntoTargetInherited);
  else
    Result := '';
  end;
  if ARow.Candidate then
  begin
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + TAtlasDebugStrings.Text(TAtlasDebugTextId.StepIntoTargetCandidate);
  end;
end;

class function TAtlasStepIntoWindow.ReasonText(const ARow: TAtlasStepRow): string;
begin
  case ARow.Unavailable of
    TAtlasStepUnavailable.NoSource:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.StepIntoTargetNoSource);
    TAtlasStepUnavailable.Library_:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.StepIntoTargetLibrary);
  else
    Result := '';
  end;
end;

class function TAtlasStepIntoWindow.RowCaption(const ARows: TArray<TAtlasStepRow>; AIndex: Integer): string;
var
  mKind: string;
begin
  Result := '';
  if (AIndex < 0) or (AIndex > High(ARows)) then
  begin
    Exit;
  end;
  Result := ARows[AIndex].Caption;
  if AIndex < TAtlasStepInto.cMaxDigit then
  begin
    Result := IntToStr(AIndex + 1) + '  ' + Result;
  end
  else
  begin
    Result := '   ' + Result;
  end;
  mKind := KindText(ARows[AIndex]);
  if mKind <> '' then
  begin
    Result := Result + '  (' + mKind + ')';
  end;
end;

/// <summary>Rechts in der Zeile: Datei:Zeile, bei nicht wählbaren Einträgen der Grund davor.</summary>
function PlaceText(const ARow: TAtlasStepRow): string;
begin
  Result := TAtlasStepIntoWindow.ReasonText(ARow);
  if Result = '' then
  begin
    Result := ARow.Location;
  end
  else if ARow.Location <> '' then
  begin
    Result := Result + '  ·  ' + ARow.Location;
  end;
end;

function TAtlasStepIntoWindow.RowColor(AIndex: Integer): TColor;
begin
  if AIndex = FRow then
  begin
    Result := ToColor(Colors.Accent);
  end
  else if FRows[AIndex].Available then
  begin
    Result := ToColor(Colors.Text);
  end
  else
  begin
    Result := ToColor(Colors.Muted);
  end;
end;

function TAtlasStepIntoWindow.LayoutRow(AIndex, AY, ARightX, ATextHeight: Integer; ADraw: Boolean): Integer;
var
  mX: Integer;
  mText, mRight: string;
begin
  mX := Scale(cPad);
  mText := RowCaption(FRows, AIndex);
  if AIndex = FRow then
  begin
    mText := cMarker + mText;
  end
  else
  begin
    mX := mX + Canvas.TextWidth(cMarker);
  end;
  mRight := PlaceText(FRows[AIndex]);
  if ADraw then
  begin
    Canvas.Font.Color := RowColor(AIndex);
    Canvas.TextOut(mX, AY, mText);
    Canvas.Font.Color := ToColor(Colors.Muted);
    Canvas.TextOut(ARightX, AY, mRight);
  end;
  Result := ARightX + Canvas.TextWidth(mRight);
  FRowRects[AIndex] := Rect(Scale(cPad), AY, Result, AY + ATextHeight);
end;

function TAtlasStepIntoWindow.Layout(ADraw: Boolean): TSize;
var
  mY, mTextHeight, mWidth, mIndex, mNameWidth, mRightX: Integer;
  mText: string;
begin
  Canvas.Font := UIFont;
  mTextHeight := Canvas.TextHeight('Wg');
  if ADraw then
  begin
    Canvas.Brush.Style := bsClear;
  end;
  mY := Scale(cPad);
  mText := TAtlasStrings.Text(TAtlasTextId.StepIntoTargetCommand);
  Canvas.Font.Style := [fsBold];
  if ADraw then
  begin
    Canvas.Font.Color := ToColor(Colors.Text);
    Canvas.TextOut(Scale(cPad), mY, mText);
  end;
  mWidth := Scale(cPad) + Canvas.TextWidth(mText);
  Canvas.Font.Style := [];
  // Spalte für den Ort: hinter dem breitesten Namen.
  mNameWidth := 0;
  for mIndex := 0 to High(FRows) do
  begin
    mNameWidth := Max(mNameWidth, Canvas.TextWidth(cMarker + RowCaption(FRows, mIndex)));
  end;
  mRightX := Scale(cPad) + mNameWidth + Scale(cColumnGap);
  SetLength(FRowRects, Length(FRows));
  for mIndex := 0 to High(FRows) do
  begin
    mY := mY + mTextHeight + Scale(cRowGap);
    mWidth := Max(mWidth, LayoutRow(mIndex, mY, mRightX, mTextHeight, ADraw));
  end;
  // Fußzeile mit den Tasten.
  mY := mY + mTextHeight + Scale(cRowGap) * 2;
  mText := TAtlasDebugStrings.Text(TAtlasDebugTextId.StepIntoTargetFooter);
  if ADraw then
  begin
    Canvas.Font.Color := ToColor(Colors.Muted);
    Canvas.TextOut(Scale(cPad), mY, mText);
    Canvas.Brush.Style := bsSolid;
  end;
  Result.cx := Max(mWidth, Scale(cPad) + Canvas.TextWidth(mText)) + Scale(cPad);
  Result.cy := mY + mTextHeight + Scale(cPad);
end;

procedure TAtlasStepIntoWindow.ShowFor(const ARows: TArray<TAtlasStepRow>; const APoint: TPoint);
var
  mSize: TSize;
  mArea: TRect;
  mLeft, mTop: Integer;
begin
  FRows := ARows;
  FRow := TAtlasStepInto.NextAvailable(FRows, 0, 1);
  HandleNeeded;
  mSize := Layout(False);
  mArea := WorkAreaAt(APoint);
  mLeft := Min(APoint.X, mArea.Right - mSize.cx);
  mTop := APoint.Y + Scale(cGap);
  if mTop + mSize.cy > mArea.Bottom then
  begin
    mTop := APoint.Y - Scale(cGap) - mSize.cy;
  end;
  ShowAt(Rect(Max(mLeft, mArea.Left), Max(mTop, mArea.Top), Max(mLeft, mArea.Left) + mSize.cx,
    Max(mTop, mArea.Top) + mSize.cy));
  Announce(TAtlasStrings.Text(TAtlasTextId.StepIntoTargetCommand));
  if FRow >= 0 then
  begin
    Announce(RowCaption(FRows, FRow));
  end;
end;

procedure TAtlasStepIntoWindow.Dismiss;
begin
  HidePopup;
end;

procedure TAtlasStepIntoWindow.Select(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FRows)) or not FRows[AIndex].Available or (AIndex = FRow) then
  begin
    Exit;
  end;
  FRow := AIndex;
  Invalidate;
  Announce(RowCaption(FRows, FRow));
end;

function TAtlasStepIntoWindow.MoveRow(ADelta: Integer): Boolean;
var
  mNext: Integer;
begin
  mNext := TAtlasStepInto.NextAvailable(FRows, FRow + ADelta, ADelta);
  Result := mNext >= 0;
  if Result then
  begin
    Select(mNext);
  end;
end;

function TAtlasStepIntoWindow.AcceptDigit(ADigit: Integer): Boolean;
var
  mIndex: Integer;
begin
  mIndex := TAtlasStepInto.DigitRow(FRows, ADigit);
  Result := mIndex >= 0;
  if not Result then
  begin
    Exit;
  end;
  Select(mIndex);
  Accept;
end;

function TAtlasStepIntoWindow.RowRect(AIndex: Integer): TRect;
begin
  Result := TRect.Empty;
  if (AIndex >= 0) and (AIndex <= High(FRowRects)) then
  begin
    Result := FRowRects[AIndex];
  end;
end;

procedure TAtlasStepIntoWindow.Accept;
var
  mChosen: Integer;
begin
  mChosen := FRow;
  if (mChosen < 0) or (mChosen > High(FRows)) or not FRows[mChosen].Available then
  begin
    Exit;
  end;
  Dismiss;
  if Assigned(FOnAccept) then
  begin
    FOnAccept(mChosen);
  end;
end;

procedure TAtlasStepIntoWindow.Cancel;
begin
  Dismiss;
  if Assigned(FOnCancel) then
  begin
    FOnCancel();
  end;
end;

procedure TAtlasStepIntoWindow.Paint;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  Layout(True);
  PaintBorder;
end;

procedure TAtlasStepIntoWindow.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mIndex: Integer;
  mPoint: TPoint;
begin
  inherited;
  if Button <> mbLeft then
  begin
    Exit;
  end;
  mPoint := TPoint.Create(X, Y);
  for mIndex := 0 to High(FRowRects) do
  begin
    if PtInRect(FRowRects[mIndex], mPoint) and FRows[mIndex].Available then
    begin
      Select(mIndex);
      Accept;
      Exit;
    end;
  end;
end;

procedure TAtlasStepIntoWindow.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mIndex: Integer;
  mHot: Boolean;
  mPoint: TPoint;
begin
  inherited;
  mPoint := TPoint.Create(X, Y);
  mHot := False;
  for mIndex := 0 to High(FRowRects) do
  begin
    if PtInRect(FRowRects[mIndex], mPoint) and FRows[mIndex].Available then
    begin
      mHot := True;
      Select(mIndex);
    end;
  end;
  if mHot then
  begin
    Cursor := crHandPoint;
  end
  else
  begin
    Cursor := crDefault;
  end;
end;

end.
