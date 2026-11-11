unit Atlas.UI.Popup.CrumbCard;

// Kennzahlen-Karte an Gliedern der Brotkrumenleiste (#1787): oben die
// Kopfzeile der Methode bzw. des Typs, darunter je Kennzahl Beschriftung
// (gedämpft) und Wert. Werte über der Grenze aus atlas.json stehen in der
// Warnfarbe mit der Grenze, etwa „86 (Grenze 60)“. Ohne Kennzahlen steht unter
// der Kopfzeile nur „Kennzahlen noch nicht verfügbar“. Ohne Fokus wie alle
// Atlas-Fenster (TAtlasPopupWindow), Schrift der Oberfläche.

interface

uses
  System.Classes,
  System.Types,
  Atlas.Core.Editor.CrumbCard,
  Atlas.UI.Popup.Window;

type
  TAtlasCrumbCardTip = class(TAtlasPopupWindow)
  public const
    /// <summary>Höchstbreite der Kopfzeile in logischen Pixeln (96 dpi); länger mit „…“.</summary>
    cMaxWidth = 520;
    cPadding = 9;
    /// <summary>Abstand zwischen Beschriftung und Wert.</summary>
    cGap = 16;
  private
    FCard: TAtlasCrumbCard;
    FCaptions: TArray<string>;
    FValues: TArray<string>;
    FCaptionWidth: Integer;
    function LineHeight: Integer;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Karte mit der linken oberen Ecke an APoint (Bildschirmkoordinaten).</summary>
    procedure ShowCard(const ACard: TAtlasCrumbCard; const APoint: TPoint);
    /// <summary>Größe der Karte (ohne zu zeigen), für Tests.</summary>
    function Measure(const ACard: TAtlasCrumbCard): TSize;
    /// <summary>Text der Zeile ARow, wie er in der Karte steht.</summary>
    class function RowCaption(const ARow: TAtlasCardRow): string; static;
    class function RowValue(const ARow: TAtlasCardRow): string; static;
    property Card: TAtlasCrumbCard read FCard;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Math,
  Vcl.Graphics,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Popup.Accessibility,
  Atlas.UI.Strings;

{ TAtlasCrumbCardTip }

constructor TAtlasCrumbCardTip.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  GuardFeature := TAtlasFeature.Breadcrumbs;
end;

class function TAtlasCrumbCardTip.RowCaption(const ARow: TAtlasCardRow): string;
const
  cIds: array[TAtlasCardMetric] of TAtlasTextId = (TAtlasTextId.BreadcrumbsMetricsLines,
    TAtlasTextId.BreadcrumbsMetricsCyclomatic, TAtlasTextId.BreadcrumbsMetricsNesting,
    TAtlasTextId.BreadcrumbsMetricsParameters, TAtlasTextId.BreadcrumbsMetricsMembers,
    TAtlasTextId.BreadcrumbsMetricsInheritance);
begin
  Result := TAtlasStrings.Text(cIds[ARow.Metric]);
end;

class function TAtlasCrumbCardTip.RowValue(const ARow: TAtlasCardRow): string;
begin
  Result := ARow.ValueText;
  if ARow.Over then
  begin
    Result := Format(TAtlasStrings.Text(TAtlasTextId.BreadcrumbsMetricsLimit), [Result, ARow.Limit]);
  end;
end;

function TAtlasCrumbCardTip.LineHeight: Integer;
begin
  Canvas.Font := UIFont;
  Result := Canvas.TextHeight('Wg') + Scale(2);
end;

function TAtlasCrumbCardTip.Measure(const ACard: TAtlasCrumbCard): TSize;
var
  mIndex, mWidth, mValueWidth: Integer;
begin
  FCard := ACard;
  SetLength(FCaptions, Length(ACard.Rows));
  SetLength(FValues, Length(ACard.Rows));
  for mIndex := 0 to High(ACard.Rows) do
  begin
    FCaptions[mIndex] := RowCaption(ACard.Rows[mIndex]);
    FValues[mIndex] := RowValue(ACard.Rows[mIndex]);
  end;
  if not ACard.Available then
  begin
    FCaptions := [TAtlasStrings.Text(TAtlasTextId.BreadcrumbsMetricsMissing)];
    FValues := [''];
  end;
  Canvas.Font := UIFont;
  FCaptionWidth := 0;
  mValueWidth := 0;
  for mIndex := 0 to High(FCaptions) do
  begin
    FCaptionWidth := Max(FCaptionWidth, Canvas.TextWidth(FCaptions[mIndex]));
    mValueWidth := Max(mValueWidth, Canvas.TextWidth(FValues[mIndex]));
  end;
  mWidth := FCaptionWidth;
  if mValueWidth > 0 then
  begin
    mWidth := FCaptionWidth + Scale(cGap) + mValueWidth;
  end;
  mWidth := Min(Max(mWidth, Canvas.TextWidth(ACard.Title)), Scale(cMaxWidth));
  Result.cx := mWidth + 2 * Scale(cPadding);
  // Kopfzeile, Abstand 4, je Zeile eine Höhe, Padding unten.
  Result.cy := Scale(cPadding) + LineHeight + Scale(4) + Length(FCaptions) * LineHeight + Scale(cPadding);
end;

procedure TAtlasCrumbCardTip.ShowCard(const ACard: TAtlasCrumbCard; const APoint: TPoint);
var
  mArea, mBounds: TRect;
  mSize: TSize;
  mIndex: Integer;
  mSpoken: string;
begin
  mSize := Measure(ACard);
  mArea := WorkAreaAt(APoint);
  mSize.cx := Min(mSize.cx, mArea.Width);
  mSize.cy := Min(mSize.cy, mArea.Height);
  mBounds := TRect.Create(APoint, mSize.cx, mSize.cy);
  if mBounds.Right > mArea.Right then
  begin
    mBounds.SetLocation(Max(mArea.Left, mArea.Right - mSize.cx), mBounds.Top);
  end;
  if mBounds.Bottom > mArea.Bottom then
  begin
    mBounds.SetLocation(mBounds.Left, Max(mArea.Top, mArea.Bottom - mSize.cy));
  end;
  SetAccessible(cUiaToolTipControlType, ACard.Title);
  ShowAt(mBounds);
  Invalidate;
  mSpoken := ACard.Title;
  for mIndex := 0 to High(FCaptions) do
  begin
    mSpoken := Trim(mSpoken + '. ' + FCaptions[mIndex] + ' ' + FValues[mIndex]);
  end;
  Announce(mSpoken);
end;

procedure TAtlasCrumbCardTip.Paint;
var
  mArea: TRect;
  mTop, mIndex, mLine, mValueLeft: Integer;
  mOver: Boolean;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  mLine := LineHeight;
  Canvas.Font := UIFont;
  Canvas.Brush.Style := bsClear;
  mTop := Scale(cPadding);
  mArea := Rect(Scale(cPadding), mTop, ClientWidth - Scale(cPadding), mTop + mLine);
  Canvas.Font.Color := ToColor(Colors.Text);
  DrawText(Canvas.Handle, PChar(FCard.Title), -1, mArea, DT_LEFT or DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS);
  Inc(mTop, mLine + Scale(4));
  mValueLeft := Scale(cPadding) + FCaptionWidth + Scale(cGap);
  for mIndex := 0 to High(FCaptions) do
  begin
    mArea := Rect(Scale(cPadding), mTop, Min(ClientWidth - Scale(cPadding), Scale(cPadding) + FCaptionWidth),
      mTop + mLine);
    Canvas.Font.Color := ToColor(Colors.Muted);
    DrawText(Canvas.Handle, PChar(FCaptions[mIndex]), -1, mArea, DT_LEFT or DT_SINGLELINE or DT_NOPREFIX or
      DT_END_ELLIPSIS);
    mOver := FCard.Available and (mIndex <= High(FCard.Rows)) and FCard.Rows[mIndex].Over;
    if mOver then
    begin
      Canvas.Font.Color := ToColor(Colors.Warn);
    end
    else
    begin
      Canvas.Font.Color := ToColor(Colors.Text);
    end;
    mArea := Rect(mValueLeft, mTop, ClientWidth - Scale(cPadding), mTop + mLine);
    DrawText(Canvas.Handle, PChar(FValues[mIndex]), -1, mArea, DT_LEFT or DT_SINGLELINE or DT_NOPREFIX or
      DT_END_ELLIPSIS);
    Inc(mTop, mLine);
  end;
  Canvas.Brush.Style := bsSolid;
  PaintBorder;
end;

end.
