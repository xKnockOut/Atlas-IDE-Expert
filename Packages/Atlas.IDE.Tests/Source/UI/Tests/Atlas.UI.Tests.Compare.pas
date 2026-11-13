unit Atlas.UI.Tests.Compare;

// Fenster „Erwartet und erhalten vergleichen“ (#1779): zwei Spalten in
// Festbreitenschrift, Zeilen nach Atlas.Core.Tests.Compare einander
// zugeordnet. Abweichende Zeichen rot (erwartet) bzw. grün (erhalten)
// hinterlegt, Zeilen nur einer Seite ganz, gegenüber eine graue Lücke;
// sichtbarer Leerraum (·, →, ↵, ␍) gedämpft. Über den Spalten „Erwartet“ und
// „Erhalten“, bei gekürzten Werten mit „(gekürzt)“, dazu die Zahl der
// abweichenden Zeilen und ob JSON bzw. XML eingerückt wurde. Knöpfe
// „Erhalten kopieren“ (Zwischenablage, roher Wert) und „Schließen“; Esc
// schließt. Farben aus der Palette (helles und dunkles Thema), Größen in
// logischen Pixeln. Reine VCL.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Atlas.Core.Tests.Compare,
  Atlas.UI.Foundation.Dialog;

type
  /// <summary>Zeichnet die Zeilen eines Vergleichs in zwei Spalten; Größe nach Inhalt (in einer TScrollBox).
  /// </summary>
  TAtlasTestsCompareView = class(TGraphicControl)
  private type
    /// <summary>Eine Seite einer Zeile: vorhanden, Text und abweichender Bereich (0-basiert).</summary>
    TSide = record
      Has: Boolean;
      Text: string;
      Start: Integer;
      Length: Integer;
    end;
  private
    FResult: TAtlasCompareResult;
    FColumn: Integer;
    FRowHeight: Integer;
    /// <summary>AWhole: ganze Zeile in AMark (nur auf dieser Seite vorhanden).</summary>
    procedure PaintSide(const ARect: TRect; const ASide: TSide; AWhole: Boolean; AMark: TColor);
    procedure PaintText(AX, AY: Integer; const ASide: TSide; AMark: TColor);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Vergleich übernehmen und Breite und Höhe nach dem Inhalt setzen (misst ohne Fenster).</summary>
    procedure ShowResult(const AResult: TAtlasCompareResult);
    /// <summary>Breite einer Spalte und Höhe einer Zeile in Gerätepixeln.</summary>
    property ColumnWidth: Integer read FColumn;
    property RowHeight: Integer read FRowHeight;
  end;

  TAtlasTestsCompareDialog = class(TAtlasDialog)
  public const
    cDialogWidth = 900;
    cViewHeight = 420;
  private
    FActual: string;
    FExpectedLabel: TLabel;
    FActualLabel: TLabel;
    FSummary: TLabel;
    FScroll: TScrollBox;
    FView: TAtlasTestsCompareView;
    FCopy: TButton;
    FClose: TButton;
    procedure CopyClick(Sender: TObject);
  protected
    procedure ThemeChanged; override;
  public
    /// <summary>Vergleich von AExpected und AActual des Tests ATest; AFormat rückt JSON bzw. XML ein.</summary>
    constructor CreateDialog(AOwner: TComponent; const ATest, AExpected, AActual: string; AFormat: Boolean);
    /// <summary>Modal zeigen.</summary>
    class procedure Execute(const ATest, AExpected, AActual: string; AFormat: Boolean); static;
    property View: TAtlasTestsCompareView read FView;
    property SummaryLabel: TLabel read FSummary;
    property CopyButton: TButton read FCopy;
  end;

implementation

uses
  System.Math,
  Vcl.Clipbrd,
  Atlas.Core.Style.Palette,
  Atlas.UI.Foundation.Theme,
  Atlas.UI.Tests.Strings;

const
  // Mindestbreite einer Spalte in Zeichen.
  cMinColumnChars = 20;
  cTextGap = 4;
  cFontName = 'Consolas';
  cFontSize = 10;
  cHeaderHeight = 22;

function IsMarker(AChar: Char): Boolean;
begin
  Result := (AChar = TAtlasTestCompare.cTrailingSpace) or (AChar = TAtlasTestCompare.cTab) or
    (AChar = TAtlasTestCompare.cLineFeed) or (AChar = TAtlasTestCompare.cCarriageReturn);
end;

{ TAtlasTestsCompareView }

constructor TAtlasTestsCompareView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Font.Name := cFontName;
  Font.Size := cFontSize;
end;

procedure TAtlasTestsCompareView.ShowResult(const AResult: TAtlasCompareResult);
var
  mBitmap: TBitmap;
  mRow: TAtlasCompareRow;
  mWidest: Integer;
begin
  FResult := AResult;
  // Messen über eine Bitmap: Das Steuerelement hat noch kein Fenster seines Formulars.
  mBitmap := TBitmap.Create;
  try
    mBitmap.Canvas.Font := Font;
    FRowHeight := mBitmap.Canvas.TextHeight('Ag') + 2;
    mWidest := mBitmap.Canvas.TextWidth('W') * cMinColumnChars;
    for mRow in AResult.Rows do
    begin
      mWidest := Max(mWidest, Max(mBitmap.Canvas.TextWidth(mRow.Left), mBitmap.Canvas.TextWidth(mRow.Right)));
    end;
  finally
    mBitmap.Free;
  end;
  FColumn := mWidest + 2 * MulDiv(cTextGap, Font.PixelsPerInch, 96);
  SetBounds(0, 0, 2 * FColumn + 1, Max(1, Length(AResult.Rows)) * FRowHeight);
  Invalidate;
end;

function InSpan(AIndex, AStart, ALength: Integer): Boolean;
begin
  Result := (AIndex - 1 >= AStart) and (AIndex - 1 < AStart + ALength);
end;

procedure TAtlasTestsCompareView.PaintText(AX, AY: Integer; const ASide: TSide; AMark: TColor);
var
  mColors: TAtlasColors;
  mIndex, mFrom: Integer;
  mInSpan, mMarker: Boolean;
  mRun, mText: string;
begin
  mText := ASide.Text;
  mColors := TAtlasUiTheme.Colors;
  mIndex := 1;
  while mIndex <= Length(mText) do
  begin
    // Lauf gleicher Art: im abweichenden Bereich oder nicht, sichtbarer Leerraum oder Text.
    mFrom := mIndex;
    mInSpan := InSpan(mIndex, ASide.Start, ASide.Length);
    mMarker := IsMarker(mText[mIndex]);
    while (mIndex <= Length(mText)) and (InSpan(mIndex, ASide.Start, ASide.Length) = mInSpan) and
      (IsMarker(mText[mIndex]) = mMarker) do
    begin
      Inc(mIndex);
    end;
    mRun := Copy(mText, mFrom, mIndex - mFrom);
    Canvas.Brush.Style := bsClear;
    if mInSpan then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := AMark;
    end;
    Canvas.Font.Color := TColor(mColors.Text);
    if mMarker then
    begin
      Canvas.Font.Color := TColor(mColors.Muted);
    end;
    Canvas.TextOut(AX, AY, mRun);
    Inc(AX, Canvas.TextWidth(mRun));
  end;
end;

procedure TAtlasTestsCompareView.PaintSide(const ARect: TRect; const ASide: TSide; AWhole: Boolean; AMark: TColor);
var
  mColors: TAtlasColors;
begin
  mColors := TAtlasUiTheme.Colors;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := TColor(mColors.Surface);
  if not ASide.Has then
  begin
    // Lücke gegenüber einer Zeile, die es nur auf der anderen Seite gibt.
    Canvas.Brush.Color := TColor(mColors.Gutter);
  end
  else if AWhole then
  begin
    Canvas.Brush.Color := AMark;
  end;
  Canvas.FillRect(ARect);
  if ASide.Has then
  begin
    PaintText(ARect.Left + MulDiv(cTextGap, Font.PixelsPerInch, 96), ARect.Top + 1, ASide, AMark);
  end;
end;

procedure TAtlasTestsCompareView.Paint;
var
  mColors: TAtlasColors;
  mIndex, mFirst, mLast, mTop: Integer;
  mRow: TAtlasCompareRow;
  mClip: TRect;
  mLeft, mRight: TSide;
begin
  mColors := TAtlasUiTheme.Colors;
  Canvas.Font := Font;
  mClip := Canvas.ClipRect;
  if FRowHeight <= 0 then
  begin
    Exit;
  end;
  // Nur die sichtbaren Zeilen (lange Werte haben viele).
  mFirst := Max(0, mClip.Top div FRowHeight);
  mLast := Min(High(FResult.Rows), mClip.Bottom div FRowHeight);
  for mIndex := mFirst to mLast do
  begin
    mRow := FResult.Rows[mIndex];
    mTop := mIndex * FRowHeight;
    mLeft.Has := mRow.HasLeft;
    mLeft.Text := mRow.Left;
    mLeft.Start := mRow.LeftStart;
    mLeft.Length := mRow.LeftLength;
    mRight.Has := mRow.HasRight;
    mRight.Text := mRow.Right;
    mRight.Start := mRow.RightStart;
    mRight.Length := mRow.RightLength;
    PaintSide(TRect.Create(0, mTop, FColumn, mTop + FRowHeight), mLeft, mRow.Kind = TAtlasCompareKind.Removed,
      TColor(mColors.ErrorSoft));
    PaintSide(TRect.Create(FColumn + 1, mTop, 2 * FColumn + 1, mTop + FRowHeight), mRight,
      mRow.Kind = TAtlasCompareKind.Added, TColor(mColors.AddSoft));
  end;
  Canvas.Pen.Color := TColor(mColors.Line);
  Canvas.MoveTo(FColumn, mClip.Top);
  Canvas.LineTo(FColumn, mClip.Bottom);
end;

{ TAtlasTestsCompareDialog }

/// <summary>Spaltenkopf: „Erwartet“ bzw. „Erhalten“, gekürzt mit Zusatz.</summary>
function SideCaption(AId: TAtlasTestsTextId; ATruncated: Boolean): string;
begin
  Result := TAtlasTestsStrings.Text(AId);
  if ATruncated then
  begin
    Result := Result + ' ' + TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsCompareTruncated);
  end;
end;

/// <summary>Zeile über dem Vergleich: Zahl der abweichenden Zeilen und ob eingerückt wurde.</summary>
function SummaryOf(const AResult: TAtlasCompareResult): string;
begin
  Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsCompareSummary, [AResult.Differences]);
  case AResult.Format of
    TAtlasCompareFormat.Plain:
      ;
    TAtlasCompareFormat.Json:
      Result := Result + ' ' + TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsCompareJson);
    TAtlasCompareFormat.Xml:
      Result := Result + ' ' + TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsCompareXml);
  end;
end;

constructor TAtlasTestsCompareDialog.CreateDialog(AOwner: TComponent; const ATest, AExpected, AActual: string;
  AFormat: Boolean);
var
  mResult: TAtlasCompareResult;
  mRow, mHeader: TPanel;
  mButtons: TAtlasButtonRow;
begin
  inherited CreateDialog(AOwner, TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsCompareTitle, [ATest]), cDialogWidth);
  KeyPreview := True;
  FActual := AActual;
  mResult := TAtlasTestCompare.Build(AExpected, AActual, AFormat);

  FSummary := AddLabel(AddRow(cHeaderHeight), SummaryOf(mResult));
  mHeader := AddRow(cHeaderHeight);
  FExpectedLabel := AddLabel(mHeader, SideCaption(TAtlasTestsTextId.TestsCompareExpected, mResult.ExpectedTruncated));
  FActualLabel := AddLabel(mHeader, SideCaption(TAtlasTestsTextId.TestsCompareActual, mResult.ActualTruncated));
  FActualLabel.Left := ScaleValue(cDialogWidth div 2);

  mRow := AddRow(cViewHeight);
  FScroll := TScrollBox.Create(Self);
  FScroll.Parent := mRow;
  FScroll.Align := alClient;
  FScroll.HorzScrollBar.Tracking := True;
  FScroll.VertScrollBar.Tracking := True;
  FView := TAtlasTestsCompareView.Create(Self);
  FView.Parent := FScroll;
  FView.ShowResult(mResult);

  mButtons := AddButtonRow;
  FCopy := mButtons.AddButton(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsCompareCopyActual));
  FCopy.OnClick := CopyClick;
  FClose := mButtons.AddButton(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsCompareClose),
    TAtlasButtonKind.Cancel);
  ActiveControl := FClose;
  FitHeight;
  AllowResize(mRow);
end;

procedure TAtlasTestsCompareDialog.CopyClick(Sender: TObject);
begin
  Clipboard.AsText := FActual;
end;

procedure TAtlasTestsCompareDialog.ThemeChanged;
begin
  inherited;
  // Die Farben der Spalten kommen beim Zeichnen aus der Palette.
  FView.Invalidate;
end;

class procedure TAtlasTestsCompareDialog.Execute(const ATest, AExpected, AActual: string; AFormat: Boolean);
var
  mDialog: TAtlasTestsCompareDialog;
begin
  mDialog := TAtlasTestsCompareDialog.CreateDialog(nil, ATest, AExpected, AActual, AFormat);
  try
    mDialog.ShowModal;
  finally
    mDialog.Free;
  end;
end;

end.
