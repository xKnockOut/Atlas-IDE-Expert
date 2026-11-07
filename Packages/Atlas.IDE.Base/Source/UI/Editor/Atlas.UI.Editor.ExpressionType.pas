unit Atlas.UI.Editor.ExpressionType;

// Typ des markierten Ausdrucks (#689), Fensterteil (nur VCL): kleiner Tooltip
// unter der Schreibmarke mit den Zeilen aus Atlas.Core.Editor.ExpressionType.
//   Price * Count + Shipping                     (Editorschrift, gedämpft)
//   TPreis = Currency                            (Editorschrift, fett, Akzent)
//   = 48
//   Count: Integer wird zu Currency erweitert    (UI-Schrift)
//   Überladung: function Max(A, B: Double): Double;
//   Strg+Umschalt+T erneut: umschließender Ausdruck   (gedämpft)
// Hat der Typ einen Fundort, ist seine Zeile unterstrichen; ein Klick meldet
// OnNavigate (Sprung zur Deklaration). Ein Fehler steht statt des Typs in der
// Fehlerfarbe. Das Fenster bekommt nie den Fokus; Esc und das Schließen bei
// Bewegung der Schreibmarke regelt die IDE-Seite.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  Vcl.Controls,
  Atlas.Core.Editor.ExpressionType,
  Atlas.UI.Popup.Window;

type
  TAtlasExpressionTypeTip = class(TAtlasPopupWindow)
  public const
    /// <summary>Abstand unter der Schreibmarke, logische Pixel.</summary>
    cGap = 4;
  private
    FRows: TArray<TAtlasExpressionTypeRow>;
    FRowRects: TArray<TRect>;
    FOnNavigate: TProc;
    function Layout(ADraw: Boolean): TSize;
    function LinkIndex: Integer;
    procedure ApplyFont(AKind: TAtlasExpressionTypeRowKind);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Texte des Tooltips aus Atlas.UI.Strings; AKey ist das Kürzel als Text ('' = keine Zeile zum
    /// Erweitern).</summary>
    class function Texts(const AKey: string): TAtlasExpressionTypeTexts; static;
    /// <summary>Zeigt ARows unter APoint (Bildschirm).</summary>
    procedure ShowFor(const ARows: TArray<TAtlasExpressionTypeRow>; const APoint: TPoint);
    procedure Dismiss;
    /// <summary>Fläche der anklickbaren Typzeile; leer ohne.</summary>
    function LinkRect: TRect;
    /// <summary>Klick auf den Typ: OnNavigate, danach zu.</summary>
    procedure Navigate;
    property Rows: TArray<TAtlasExpressionTypeRow> read FRows;
    property OnNavigate: TProc read FOnNavigate write FOnNavigate;
  end;

implementation

uses
  System.UITypes,
  System.Math,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Strings,
  Atlas.UI.Popup.Accessibility;

const
  cPad = 10;
  cRowGap = 3;

{ TAtlasExpressionTypeTip }

constructor TAtlasExpressionTypeTip.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  GuardFeature := TAtlasFeature.ExpressionType;
  SetAccessible(cUiaToolTipControlType, TAtlasStrings.Text(TAtlasTextId.ExpressionTypeCommand));
end;

class function TAtlasExpressionTypeTip.Texts(const AKey: string): TAtlasExpressionTypeTexts;
begin
  Result := Default(TAtlasExpressionTypeTexts);
  Result.Value := TAtlasStrings.Text(TAtlasTextId.ExpressionTypeValue);
  Result.Widen := TAtlasStrings.Text(TAtlasTextId.ExpressionTypeWiden);
  Result.Convert := TAtlasStrings.Text(TAtlasTextId.ExpressionTypeConvert);
  Result.Overload := TAtlasStrings.Text(TAtlasTextId.ExpressionTypeOverload);
  Result.NoExpression := TAtlasStrings.Text(TAtlasTextId.ExpressionTypeNoExpression);
  Result.UnknownName := TAtlasStrings.Text(TAtlasTextId.ExpressionTypeUnknownName);
  Result.OperatorMismatch := TAtlasStrings.Text(TAtlasTextId.ExpressionTypeOperator);
  Result.OperatorUnary := TAtlasStrings.Text(TAtlasTextId.ExpressionTypeOperatorUnary);
  Result.NoResult := TAtlasStrings.Text(TAtlasTextId.ExpressionTypeNoResult);
  Result.Unknown := TAtlasStrings.Text(TAtlasTextId.ExpressionTypeUnknown);
  Result.Expand := '';
  if AKey <> '' then
  begin
    Result.Expand := TAtlasStrings.Fmt(TAtlasTextId.ExpressionTypeExpand, [AKey]);
  end;
end;

procedure TAtlasExpressionTypeTip.ApplyFont(AKind: TAtlasExpressionTypeRowKind);
begin
  case AKind of
    TAtlasExpressionTypeRowKind.Expression, TAtlasExpressionTypeRowKind.TypeName,
    TAtlasExpressionTypeRowKind.Value:
      Canvas.Font := Font;
  else
    Canvas.Font := UIFont;
  end;
  if AKind = TAtlasExpressionTypeRowKind.TypeName then
  begin
    Canvas.Font.Style := [fsBold];
  end
  else
  begin
    Canvas.Font.Style := [];
  end;
end;

function TAtlasExpressionTypeTip.LinkIndex: Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(FRows) do
  begin
    if FRows[mIndex].Link then
    begin
      Exit(mIndex);
    end;
  end;
end;

function TAtlasExpressionTypeTip.Layout(ADraw: Boolean): TSize;
var
  mIndex, Y, mWidth, mHeight: Integer;
  mItem: TAtlasExpressionTypeRow;
begin
  if ADraw then
  begin
    Canvas.Brush.Style := bsClear;
  end;
  Y := Scale(cPad);
  mWidth := 0;
  SetLength(FRowRects, Length(FRows));
  for mIndex := 0 to High(FRows) do
  begin
    mItem := FRows[mIndex];
    ApplyFont(mItem.Kind);
    if mItem.Link then
    begin
      Canvas.Font.Style := Canvas.Font.Style + [fsUnderline];
    end;
    // Die Erweitern-Zeile setzt sich mit etwas Abstand ab.
    if (mItem.Kind = TAtlasExpressionTypeRowKind.Hint) and (mIndex > 0) then
    begin
      Inc(Y, Scale(cRowGap));
    end;
    mHeight := Canvas.TextHeight('Wg');
    FRowRects[mIndex] := Rect(Scale(cPad), Y, Scale(cPad) + Canvas.TextWidth(mItem.Text), Y + mHeight);
    if ADraw then
    begin
      case mItem.Kind of
        TAtlasExpressionTypeRowKind.Expression, TAtlasExpressionTypeRowKind.Hint:
          Canvas.Font.Color := ToColor(Colors.Muted);
        TAtlasExpressionTypeRowKind.TypeName:
          Canvas.Font.Color := ToColor(Colors.Accent);
        TAtlasExpressionTypeRowKind.Error:
          Canvas.Font.Color := ToColor(Colors.Error);
      else
        Canvas.Font.Color := ToColor(Colors.Text);
      end;
      Canvas.TextOut(FRowRects[mIndex].Left, Y, mItem.Text);
    end;
    mWidth := Max(mWidth, FRowRects[mIndex].Right);
    Y := Y + mHeight + Scale(cRowGap);
  end;
  if ADraw then
  begin
    Canvas.Brush.Style := bsSolid;
  end;
  Result.cx := mWidth + Scale(cPad);
  Result.cy := Y - Scale(cRowGap) + Scale(cPad);
end;

procedure TAtlasExpressionTypeTip.ShowFor(const ARows: TArray<TAtlasExpressionTypeRow>; const APoint: TPoint);
var
  mSize: TSize;
  mArea: TRect;
  mLeft, mTop: Integer;
  mRow: TAtlasExpressionTypeRow;
  mSpoken: string;
begin
  FRows := ARows;
  HandleNeeded;
  mSize := Layout(False);
  mArea := WorkAreaAt(APoint);
  mSize.cx := Min(mSize.cx, mArea.Width);
  mLeft := Min(APoint.X, mArea.Right - mSize.cx);
  mTop := APoint.Y + Scale(cGap);
  if mTop + mSize.cy > mArea.Bottom then
  begin
    mTop := APoint.Y - Scale(cGap) - mSize.cy;
  end;
  ShowAt(Rect(Max(mLeft, mArea.Left), Max(mTop, mArea.Top), Max(mLeft, mArea.Left) + mSize.cx,
    Max(mTop, mArea.Top) + mSize.cy));
  Invalidate;
  mSpoken := '';
  for mRow in FRows do
  begin
    if mRow.Kind <> TAtlasExpressionTypeRowKind.Hint then
    begin
      mSpoken := mSpoken + mRow.Text + '. ';
    end;
  end;
  Announce(Trim(mSpoken));
end;

procedure TAtlasExpressionTypeTip.Dismiss;
begin
  HidePopup;
end;

function TAtlasExpressionTypeTip.LinkRect: TRect;
var
  mIndex: Integer;
begin
  Result := TRect.Empty;
  mIndex := LinkIndex;
  if (mIndex >= 0) and (mIndex <= High(FRowRects)) then
  begin
    Result := FRowRects[mIndex];
  end;
end;

procedure TAtlasExpressionTypeTip.Navigate;
begin
  if LinkIndex < 0 then
  begin
    Exit;
  end;
  Dismiss;
  if Assigned(FOnNavigate) then
  begin
    FOnNavigate();
  end;
end;

procedure TAtlasExpressionTypeTip.Paint;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  Layout(True);
  PaintBorder;
end;

procedure TAtlasExpressionTypeTip.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if (Button = mbLeft) and PtInRect(LinkRect, TPoint.Create(X, Y)) then
  begin
    Navigate;
  end;
end;

procedure TAtlasExpressionTypeTip.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mHot: Boolean;
begin
  inherited;
  mHot := PtInRect(LinkRect, TPoint.Create(X, Y));
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
