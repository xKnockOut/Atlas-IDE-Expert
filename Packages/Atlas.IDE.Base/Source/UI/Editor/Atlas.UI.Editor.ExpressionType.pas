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
    Gap = 4;
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
  Pad = 10;
  RowGap = 3;

{ TAtlasExpressionTypeTip }

constructor TAtlasExpressionTypeTip.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  GuardFeature := TAtlasFeature.ExpressionType;
  SetAccessible(UiaToolTipControlType, TAtlasStrings.Text(TAtlasTextId.ExpressionTypeCommand));
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
  Index: Integer;
begin
  Result := -1;
  for Index := 0 to High(FRows) do
  begin
    if FRows[Index].Link then
    begin
      Exit(Index);
    end;
  end;
end;

function TAtlasExpressionTypeTip.Layout(ADraw: Boolean): TSize;
var
  Index, Y, Width, Height: Integer;
  Item: TAtlasExpressionTypeRow;
begin
  if ADraw then
  begin
    Canvas.Brush.Style := bsClear;
  end;
  Y := Scale(Pad);
  Width := 0;
  SetLength(FRowRects, Length(FRows));
  for Index := 0 to High(FRows) do
  begin
    Item := FRows[Index];
    ApplyFont(Item.Kind);
    if Item.Link then
    begin
      Canvas.Font.Style := Canvas.Font.Style + [fsUnderline];
    end;
    // Die Erweitern-Zeile setzt sich mit etwas Abstand ab.
    if (Item.Kind = TAtlasExpressionTypeRowKind.Hint) and (Index > 0) then
    begin
      Inc(Y, Scale(RowGap));
    end;
    Height := Canvas.TextHeight('Wg');
    FRowRects[Index] := Rect(Scale(Pad), Y, Scale(Pad) + Canvas.TextWidth(Item.Text), Y + Height);
    if ADraw then
    begin
      case Item.Kind of
        TAtlasExpressionTypeRowKind.Expression, TAtlasExpressionTypeRowKind.Hint:
          Canvas.Font.Color := ToColor(Colors.Muted);
        TAtlasExpressionTypeRowKind.TypeName:
          Canvas.Font.Color := ToColor(Colors.Accent);
        TAtlasExpressionTypeRowKind.Error:
          Canvas.Font.Color := ToColor(Colors.Error);
      else
        Canvas.Font.Color := ToColor(Colors.Text);
      end;
      Canvas.TextOut(FRowRects[Index].Left, Y, Item.Text);
    end;
    Width := Max(Width, FRowRects[Index].Right);
    Y := Y + Height + Scale(RowGap);
  end;
  if ADraw then
  begin
    Canvas.Brush.Style := bsSolid;
  end;
  Result.cx := Width + Scale(Pad);
  Result.cy := Y - Scale(RowGap) + Scale(Pad);
end;

procedure TAtlasExpressionTypeTip.ShowFor(const ARows: TArray<TAtlasExpressionTypeRow>; const APoint: TPoint);
var
  Size: TSize;
  Area: TRect;
  Left, Top: Integer;
  Row: TAtlasExpressionTypeRow;
  Spoken: string;
begin
  FRows := ARows;
  HandleNeeded;
  Size := Layout(False);
  Area := WorkAreaAt(APoint);
  Size.cx := Min(Size.cx, Area.Width);
  Left := Min(APoint.X, Area.Right - Size.cx);
  Top := APoint.Y + Scale(Gap);
  if Top + Size.cy > Area.Bottom then
  begin
    Top := APoint.Y - Scale(Gap) - Size.cy;
  end;
  ShowAt(Rect(Max(Left, Area.Left), Max(Top, Area.Top), Max(Left, Area.Left) + Size.cx,
    Max(Top, Area.Top) + Size.cy));
  Invalidate;
  Spoken := '';
  for Row in FRows do
  begin
    if Row.Kind <> TAtlasExpressionTypeRowKind.Hint then
    begin
      Spoken := Spoken + Row.Text + '. ';
    end;
  end;
  Announce(Trim(Spoken));
end;

procedure TAtlasExpressionTypeTip.Dismiss;
begin
  HidePopup;
end;

function TAtlasExpressionTypeTip.LinkRect: TRect;
var
  Index: Integer;
begin
  Result := TRect.Empty;
  Index := LinkIndex;
  if (Index >= 0) and (Index <= High(FRowRects)) then
  begin
    Result := FRowRects[Index];
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
  Hot: Boolean;
begin
  inherited;
  Hot := PtInRect(LinkRect, TPoint.Create(X, Y));
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
