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
    Gap = 4;
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
  Pad = 10;
  RowGap = 4;
  ColumnGap = 16;
  Marker = '› ';

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
  Kind: string;
begin
  Result := '';
  if (AIndex < 0) or (AIndex > High(ARows)) then
  begin
    Exit;
  end;
  Result := ARows[AIndex].Caption;
  if AIndex < TAtlasStepInto.MaxDigit then
  begin
    Result := IntToStr(AIndex + 1) + '  ' + Result;
  end
  else
  begin
    Result := '   ' + Result;
  end;
  Kind := KindText(ARows[AIndex]);
  if Kind <> '' then
  begin
    Result := Result + '  (' + Kind + ')';
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
  mX := Scale(Pad);
  mText := RowCaption(FRows, AIndex);
  if AIndex = FRow then
  begin
    mText := Marker + mText;
  end
  else
  begin
    mX := mX + Canvas.TextWidth(Marker);
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
  FRowRects[AIndex] := Rect(Scale(Pad), AY, Result, AY + ATextHeight);
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
  mY := Scale(Pad);
  mText := TAtlasStrings.Text(TAtlasTextId.StepIntoTargetCommand);
  Canvas.Font.Style := [fsBold];
  if ADraw then
  begin
    Canvas.Font.Color := ToColor(Colors.Text);
    Canvas.TextOut(Scale(Pad), mY, mText);
  end;
  mWidth := Scale(Pad) + Canvas.TextWidth(mText);
  Canvas.Font.Style := [];
  // Spalte für den Ort: hinter dem breitesten Namen.
  mNameWidth := 0;
  for mIndex := 0 to High(FRows) do
  begin
    mNameWidth := Max(mNameWidth, Canvas.TextWidth(Marker + RowCaption(FRows, mIndex)));
  end;
  mRightX := Scale(Pad) + mNameWidth + Scale(ColumnGap);
  SetLength(FRowRects, Length(FRows));
  for mIndex := 0 to High(FRows) do
  begin
    mY := mY + mTextHeight + Scale(RowGap);
    mWidth := Max(mWidth, LayoutRow(mIndex, mY, mRightX, mTextHeight, ADraw));
  end;
  // Fußzeile mit den Tasten.
  mY := mY + mTextHeight + Scale(RowGap) * 2;
  mText := TAtlasDebugStrings.Text(TAtlasDebugTextId.StepIntoTargetFooter);
  if ADraw then
  begin
    Canvas.Font.Color := ToColor(Colors.Muted);
    Canvas.TextOut(Scale(Pad), mY, mText);
    Canvas.Brush.Style := bsSolid;
  end;
  Result.cx := Max(mWidth, Scale(Pad) + Canvas.TextWidth(mText)) + Scale(Pad);
  Result.cy := mY + mTextHeight + Scale(Pad);
end;

procedure TAtlasStepIntoWindow.ShowFor(const ARows: TArray<TAtlasStepRow>; const APoint: TPoint);
var
  Size: TSize;
  Area: TRect;
  Left, Top: Integer;
begin
  FRows := ARows;
  FRow := TAtlasStepInto.NextAvailable(FRows, 0, 1);
  HandleNeeded;
  Size := Layout(False);
  Area := WorkAreaAt(APoint);
  Left := Min(APoint.X, Area.Right - Size.cx);
  Top := APoint.Y + Scale(Gap);
  if Top + Size.cy > Area.Bottom then
  begin
    Top := APoint.Y - Scale(Gap) - Size.cy;
  end;
  ShowAt(Rect(Max(Left, Area.Left), Max(Top, Area.Top), Max(Left, Area.Left) + Size.cx,
    Max(Top, Area.Top) + Size.cy));
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
  Next: Integer;
begin
  Next := TAtlasStepInto.NextAvailable(FRows, FRow + ADelta, ADelta);
  Result := Next >= 0;
  if Result then
  begin
    Select(Next);
  end;
end;

function TAtlasStepIntoWindow.AcceptDigit(ADigit: Integer): Boolean;
var
  Index: Integer;
begin
  Index := TAtlasStepInto.DigitRow(FRows, ADigit);
  Result := Index >= 0;
  if not Result then
  begin
    Exit;
  end;
  Select(Index);
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
  Chosen: Integer;
begin
  Chosen := FRow;
  if (Chosen < 0) or (Chosen > High(FRows)) or not FRows[Chosen].Available then
  begin
    Exit;
  end;
  Dismiss;
  if Assigned(FOnAccept) then
  begin
    FOnAccept(Chosen);
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
  Index: Integer;
  Point: TPoint;
begin
  inherited;
  if Button <> mbLeft then
  begin
    Exit;
  end;
  Point := TPoint.Create(X, Y);
  for Index := 0 to High(FRowRects) do
  begin
    if PtInRect(FRowRects[Index], Point) and FRows[Index].Available then
    begin
      Select(Index);
      Accept;
      Exit;
    end;
  end;
end;

procedure TAtlasStepIntoWindow.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Index: Integer;
  Hot: Boolean;
  Point: TPoint;
begin
  inherited;
  Point := TPoint.Create(X, Y);
  Hot := False;
  for Index := 0 to High(FRowRects) do
  begin
    if PtInRect(FRowRects[Index], Point) and FRows[Index].Available then
    begin
      Hot := True;
      Select(Index);
    end;
  end;
  if Hot then
  begin
    Cursor := crHandPoint;
  end
  else
  begin
    Cursor := crDefault;
  end;
end;

end.
