unit Atlas.UI.Foundation.ListView;

// Liste der im Code gebauten Atlas-Fenster (#2063). Spaltenbreiten gingen als
// Gerätepixel an eigene AddColumn-Helfer und blieben bei 150 % zu schmal
// (#1982, #2060); feste Farben an Listen brauchten in ApplyIdeTheme einen
// Notbehelf (ResetColors).
// - AddColumn nimmt die Breite in logischen Pixeln (96 dpi) und skaliert sie
//   über die Pixeldichte der Liste.
// - Bei einem DPI-Wechsel (anderer Monitor) setzt ChangeScale die Breiten aus
//   den Werten vor dem Wechsel neu, ob die VCL die Spalten selbst schon
//   skaliert hat oder nicht; so wird nichts doppelt skaliert. Vom Benutzer
//   gezogene Breiten bleiben im Verhältnis erhalten.
// - Keine eigenen Farben: Grund und Schrift kommen aus dem Stil der Wurzel.
// - FillColumn: eine Spalte (meist die letzte, ein Hinweis) nimmt die übrige
//   Breite der Liste und wächst mit dem Fenster, statt rechts abgeschnitten
//   zu werden; sie wird nie schmaler als ihre Mindestbreite.
// - FitColumnsToContent: die übrigen Spalten so breit wie Überschrift und
//   längster Eintrag (gemessen in der Schrift der Liste, höchstens eine
//   Obergrenze), statt fester Breiten, die bei längeren Werten abschneiden.
// - Sortable: Klick auf den Spaltenkopf sortiert nach dieser Spalte, ein
//   zweiter Klick kehrt um; Zahlen im Text zählen als Zahlen („9 %“ vor
//   „15 %“). Der Pfeil im Kopf zeigt Spalte und Richtung. Gleichstand
//   entscheiden die anderen Spalten, dann Data (die Sortierung von Windows ist
//   nicht stabil). Nicht für virtuelle Listen (OwnerData).
// Für DFM-Frames bleibt TListView (kein Design-Time-Package).

interface

uses
  System.Classes,
  Vcl.ComCtrls;

type
  TAtlasListView = class(TListView)
  private
    FFillColumn: Integer;
    FFillMinWidth96: Integer;
    FSortable: Boolean;
    FSortColumn: Integer;
    FSortDescending: Boolean;
    class function CellText(AItem: TListItem; AColumn: Integer): string; static;
    /// <summary>Position hinter der Ziffernfolge ab AFrom.</summary>
    class function DigitsEnd(const AText: string; AFrom: Integer): Integer; static;
    /// <summary>Ziffernfolgen als Zahlen vergleichen (führende Nullen zählen nicht, ohne Überlauf).</summary>
    class function CompareDigits(const ALeft, ARight: string): Integer; static;
    function CompareCells(AItem1, AItem2: TListItem): Integer;
    procedure CompareRows(Sender: TObject; Item1, Item2: TListItem; Data: Integer; var Compare: Integer);
    procedure ShowSortMark;
  protected
    procedure ChangeScale(AM, AD: Integer; AIsDpiChange: Boolean); override;
    procedure Resize; override;
    procedure ColClick(Field: TListColumn); override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Spalte AIndex nimmt die übrige Breite der Liste, mindestens AMinWidth96 (logische Pixel);
    /// AIndex -1 schaltet das ab.</summary>
    procedure FillColumn(AIndex, AMinWidth96: Integer);
    /// <summary>Breite der füllenden Spalte neu setzen (nach Größenwechsel, neuen Zeilen oder Bildlaufleiste).
    /// </summary>
    procedure FitColumns;
    /// <summary>Spalte mit Überschrift ACaption und Breite AWidth96 in logischen Pixeln anfügen; negative
    /// Breiten (LVSCW_AUTOSIZE, LVSCW_AUTOSIZE_USEHEADER) bleiben unverändert.</summary>
    function AddColumn(const ACaption: string; AWidth96: Integer; AAlignment: TAlignment): TListColumn; overload;
    /// <summary>Linksbündige Spalte anfügen.</summary>
    function AddColumn(const ACaption: string; AWidth96: Integer): TListColumn; overload;
    /// <summary>Breite in Gerätepixeln, die Überschrift und längster Eintrag der Spalte AColumn brauchen.</summary>
    function ContentWidth(AColumn: Integer): Integer;
    /// <summary>Alle Spalten außer der füllenden nach ContentWidth, höchstens AMaxWidth96 (logische Pixel);
    /// danach nimmt die füllende den Rest.</summary>
    procedure FitColumnsToContent(AMaxWidth96: Integer);
    /// <summary>Nach Spalte AColumn sortieren (-1: nicht sortiert) und den Pfeil im Kopf setzen.</summary>
    procedure SortBy(AColumn: Integer; ADescending: Boolean);
    /// <summary>Vergleich wie im Explorer: Ziffernfolgen als Zahlen, sonst ohne Groß-/Kleinschreibung.</summary>
    class function CompareNatural(const ALeft, ARight: string): Integer; static;
    /// <summary>Klick auf den Spaltenkopf sortiert (zweiter Klick kehrt um).</summary>
    property Sortable: Boolean read FSortable write FSortable;
    property SortColumn: Integer read FSortColumn;
    property SortDescending: Boolean read FSortDescending;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.CommCtrl,
  System.SysUtils,
  System.Math,
  Vcl.Graphics,
  Atlas.Core.Style.Scaling;

const
  /// <summary>Rand links und rechts des Texts einer Zelle, logische Pixel.</summary>
  cCellPadding96 = 16;
  /// <summary>Rand des Spaltenkopfs samt Platz für den Sortierpfeil, logische Pixel.</summary>
  cHeaderPadding96 = 28;
  /// <summary>Kästchen vor der ersten Spalte (Checkboxes), logische Pixel.</summary>
  cCheckBox96 = 22;

{ TAtlasListView }

constructor TAtlasListView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ViewStyle := vsReport;
  FFillColumn := -1;
  FSortColumn := -1;
end;

procedure TAtlasListView.ChangeScale(AM, AD: Integer; AIsDpiChange: Boolean);
var
  mWidths: TArray<Integer>;
  mIndex: Integer;
begin
  SetLength(mWidths, Columns.Count);
  for mIndex := 0 to Columns.Count - 1 do
  begin
    mWidths[mIndex] := Columns[mIndex].Width;
  end;
  inherited ChangeScale(AM, AD, AIsDpiChange);
  if (AD <= 0) or (AM = AD) then
  begin
    Exit;
  end;
  for mIndex := 0 to High(mWidths) do
  begin
    if (mIndex < Columns.Count) and (mWidths[mIndex] > 0) then
    begin
      Columns[mIndex].Width := (mWidths[mIndex] * AM + AD div 2) div AD;
    end;
  end;
  FitColumns;
end;

procedure TAtlasListView.Resize;
begin
  inherited;
  FitColumns;
end;

procedure TAtlasListView.FillColumn(AIndex, AMinWidth96: Integer);
begin
  FFillColumn := AIndex;
  FFillMinWidth96 := AMinWidth96;
  FitColumns;
end;

procedure TAtlasListView.FitColumns;
var
  mRest, mMin, mIndex: Integer;
begin
  if (FFillColumn < 0) or (FFillColumn >= Columns.Count) then
  begin
    Exit;
  end;
  mRest := ClientWidth;
  for mIndex := 0 to Columns.Count - 1 do
  begin
    if mIndex <> FFillColumn then
    begin
      Dec(mRest, Columns[mIndex].Width);
    end;
  end;
  mMin := TAtlasScaling.ToDevice(FFillMinWidth96, CurrentPPI);
  if mRest < mMin then
  begin
    mRest := mMin;
  end;
  if Columns[FFillColumn].Width <> mRest then
  begin
    Columns[FFillColumn].Width := mRest;
    // Die VCL setzt beim Ändern einer Spalte deren Format neu und löscht damit den Pfeil.
    ShowSortMark;
  end;
end;

function TAtlasListView.AddColumn(const ACaption: string; AWidth96: Integer; AAlignment: TAlignment): TListColumn;
begin
  Result := Columns.Add;
  Result.Caption := ACaption;
  Result.Alignment := AAlignment;
  Result.Width := TAtlasScaling.ToDevice(AWidth96, CurrentPPI);
end;

function TAtlasListView.AddColumn(const ACaption: string; AWidth96: Integer): TListColumn;
begin
  Result := AddColumn(ACaption, AWidth96, taLeftJustify);
end;

function TAtlasListView.ContentWidth(AColumn: Integer): Integer;
var
  mBitmap: TBitmap;
  mIndex: Integer;
begin
  mBitmap := TBitmap.Create;
  try
    // Font.Height ist schon in Gerätepixeln der Liste.
    mBitmap.Canvas.Font.Assign(Font);
    Result := mBitmap.Canvas.TextWidth(Columns[AColumn].Caption) + TAtlasScaling.ToDevice(cHeaderPadding96,
      CurrentPPI);
    for mIndex := 0 to Items.Count - 1 do
    begin
      Result := Max(Result, mBitmap.Canvas.TextWidth(CellText(Items[mIndex], AColumn)) +
        TAtlasScaling.ToDevice(cCellPadding96, CurrentPPI));
    end;
  finally
    mBitmap.Free;
  end;
  if (AColumn = 0) and Checkboxes then
  begin
    Inc(Result, TAtlasScaling.ToDevice(cCheckBox96, CurrentPPI));
  end;
end;

procedure TAtlasListView.FitColumnsToContent(AMaxWidth96: Integer);
var
  mIndex, mMax: Integer;
begin
  mMax := TAtlasScaling.ToDevice(AMaxWidth96, CurrentPPI);
  Columns.BeginUpdate;
  try
    for mIndex := 0 to Columns.Count - 1 do
    begin
      if mIndex <> FFillColumn then
      begin
        Columns[mIndex].Width := Min(ContentWidth(mIndex), mMax);
      end;
    end;
  finally
    Columns.EndUpdate;
  end;
  FitColumns;
  ShowSortMark;
end;

class function TAtlasListView.CellText(AItem: TListItem; AColumn: Integer): string;
begin
  Result := '';
  if AColumn = 0 then
  begin
    Result := AItem.Caption;
  end
  else if (AColumn > 0) and (AColumn <= AItem.SubItems.Count) then
  begin
    Result := AItem.SubItems[AColumn - 1];
  end;
end;

class function TAtlasListView.DigitsEnd(const AText: string; AFrom: Integer): Integer;
begin
  Result := AFrom;
  while (Result <= Length(AText)) and CharInSet(AText[Result], ['0'..'9']) do
  begin
    Inc(Result);
  end;
end;

class function TAtlasListView.CompareDigits(const ALeft, ARight: string): Integer;
var
  mLeft, mRight: string;
begin
  // Die längere Ziffernfolge ist die größere Zahl.
  mLeft := ALeft.TrimLeft(['0']);
  mRight := ARight.TrimLeft(['0']);
  Result := CompareValue(Length(mLeft), Length(mRight));
  if Result = 0 then
  begin
    Result := CompareStr(mLeft, mRight);
  end;
end;

class function TAtlasListView.CompareNatural(const ALeft, ARight: string): Integer;
var
  mLeft, mRight, mLeftEnd, mRightEnd: Integer;
begin
  Result := 0;
  mLeft := 1;
  mRight := 1;
  while (Result = 0) and (mLeft <= Length(ALeft)) and (mRight <= Length(ARight)) do
  begin
    mLeftEnd := DigitsEnd(ALeft, mLeft);
    mRightEnd := DigitsEnd(ARight, mRight);
    if (mLeftEnd > mLeft) and (mRightEnd > mRight) then
    begin
      Result := CompareDigits(Copy(ALeft, mLeft, mLeftEnd - mLeft), Copy(ARight, mRight, mRightEnd - mRight));
      mLeft := mLeftEnd;
      mRight := mRightEnd;
    end
    else
    begin
      Result := AnsiCompareText(ALeft[mLeft], ARight[mRight]);
      Inc(mLeft);
      Inc(mRight);
    end;
  end;
  if Result = 0 then
  begin
    Result := CompareValue(Length(ALeft) - mLeft, Length(ARight) - mRight);
  end;
end;

function TAtlasListView.CompareCells(AItem1, AItem2: TListItem): Integer;
var
  mIndex: Integer;
begin
  Result := CompareNatural(CellText(AItem1, FSortColumn), CellText(AItem2, FSortColumn));
  mIndex := 0;
  while (Result = 0) and (mIndex < Columns.Count) do
  begin
    if mIndex <> FSortColumn then
    begin
      Result := CompareNatural(CellText(AItem1, mIndex), CellText(AItem2, mIndex));
    end;
    Inc(mIndex);
  end;
  if Result = 0 then
  begin
    Result := CompareValue(NativeInt(AItem1.Data), NativeInt(AItem2.Data));
  end;
end;

procedure TAtlasListView.CompareRows(Sender: TObject; Item1, Item2: TListItem; Data: Integer; var Compare: Integer);
begin
  Compare := CompareCells(Item1, Item2);
  if FSortDescending then
  begin
    Compare := -Compare;
  end;
end;

procedure TAtlasListView.SortBy(AColumn: Integer; ADescending: Boolean);
begin
  FSortColumn := AColumn;
  FSortDescending := ADescending;
  if (AColumn >= 0) and (AColumn < Columns.Count) and not OwnerData then
  begin
    OnCompare := CompareRows;
    AlphaSort;
    if Selected <> nil then
    begin
      Selected.MakeVisible(False);
    end;
  end;
  ShowSortMark;
end;

procedure TAtlasListView.ColClick(Field: TListColumn);
begin
  inherited ColClick(Field);
  if not FSortable then
  begin
    Exit;
  end;
  SortBy(Field.Index, (Field.Index = FSortColumn) and not FSortDescending);
end;

procedure TAtlasListView.ShowSortMark;
var
  mHeader: HWND;
  mItem: THDItem;
  mIndex: Integer;
begin
  if not HandleAllocated then
  begin
    Exit;
  end;
  mHeader := ListView_GetHeader(Handle);
  for mIndex := 0 to Columns.Count - 1 do
  begin
    mItem := Default(THDItem);
    mItem.Mask := HDI_FORMAT;
    Header_GetItem(mHeader, mIndex, mItem);
    mItem.fmt := mItem.fmt and not (HDF_SORTUP or HDF_SORTDOWN);
    if (mIndex = FSortColumn) and FSortDescending then
    begin
      mItem.fmt := mItem.fmt or HDF_SORTDOWN;
    end
    else if mIndex = FSortColumn then
    begin
      mItem.fmt := mItem.fmt or HDF_SORTUP;
    end;
    Header_SetItem(mHeader, mIndex, mItem);
  end;
end;

end.
