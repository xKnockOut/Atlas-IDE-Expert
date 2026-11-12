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
  protected
    procedure ChangeScale(AM, AD: Integer; AIsDpiChange: Boolean); override;
    procedure Resize; override;
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
  end;

implementation

uses
  Atlas.Core.Style.Scaling;

{ TAtlasListView }

constructor TAtlasListView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ViewStyle := vsReport;
  FFillColumn := -1;
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
  end;
end;

procedure TAtlasListView.Resize;
begin
  inherited;
  FitColumns;
end;

function TAtlasListView.AddColumn(const ACaption: string; AWidth96: Integer): TListColumn;
begin
  Result := AddColumn(ACaption, AWidth96, taLeftJustify);
end;

function TAtlasListView.AddColumn(const ACaption: string; AWidth96: Integer; AAlignment: TAlignment): TListColumn;
begin
  Result := Columns.Add;
  Result.Caption := ACaption;
  Result.Alignment := AAlignment;
  Result.Width := TAtlasScaling.ToDevice(AWidth96, CurrentPPI);
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

end.
