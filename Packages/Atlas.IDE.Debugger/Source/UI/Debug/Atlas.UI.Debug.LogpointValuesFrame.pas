unit Atlas.UI.Debug.LogpointValuesFrame;

// Inhalt des Fensters „Logpunkt-Verlauf“ (#2552), reine VCL, im Code
// aufgebaut: oben die Wahl der Reihe (Name und Ort) und des Threads, rechts
// „CSV kopieren“; in der Mitte die Linie (TAtlasDebugValueChart auf dem
// gemeinsamen Zeitdiagramm TAtlasDebugTimeChart), Text-Werte als Lücke;
// unten Treffer, Minimum, Maximum und letzter Wert, der angeklickte Treffer
// und ein Hinweis zur Bedienung. Die Reihen besitzt die IDE-Schicht
// (Atlas.IDE.Debug.LogpointValues); sie meldet neue Treffer mit Refresh und
// reagiert auf OnCopyCsv und OnPoint (Sprung ins Ereignisprotokoll).

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Atlas.Core.Debug.ValueSeries,
  Atlas.UI.Debug.TimeChart;

type
  /// <summary>Linie einer Reihe aus Logpunkten; Punkte als Kopie (gefiltert nach Thread).</summary>
  TAtlasDebugValueChart = class(TAtlasDebugTimeChart)
  private
    FPoints: TArray<TAtlasValuePoint>;
    procedure SetPoints(const AValue: TArray<TAtlasValuePoint>);
  protected
    function PointCount: Integer; override;
    function PointAtMs(AIndex: Integer): Int64; override;
    function PointValue(AIndex: Integer; out AValue: Double): Boolean; override;
    procedure ValueRange(out ALow, AHigh: Double); override;
    function ValueText(AValue: Double): string; override;
    function HoverOf(AIndex: Integer; const ASeconds: string): string; override;
  public
    /// <summary>„312,4 s · Thread 7 · Wert 48“ (Wert „keine Zahl“ bei einer Lücke).</summary>
    class function PointText(const APoint: TAtlasValuePoint): string; static;
    property Points: TArray<TAtlasValuePoint> read FPoints write SetPoints;
  end;

  /// <summary>Reihe ASeries (Ort) gefiltert nach AThread ('' = alle).</summary>
  TAtlasValuesCsvEvent = reference to procedure(const APlace, AThread: string);
  TAtlasValuesPointEvent = reference to procedure(const APoint: TAtlasValuePoint);

  TAtlasDebugLogpointValuesFrame = class(TFrame)
  private type
    TControls = record
      SeriesBox: TComboBox;
      ThreadBox: TComboBox;
      CopyCsv: TButton;
      Chart: TAtlasDebugValueChart;
      StatsLabel: TLabel;
      PointLabel: TLabel;
    end;
  private
    FControls: TControls;
    FSet: TAtlasValueSeriesSet;
    FPlaces: TArray<string>;
    FThreads: TArray<string>;
    FOnCopyCsv: TAtlasValuesCsvEvent;
    FOnPoint: TAtlasValuesPointEvent;
    procedure BuildTopBar;
    function AddBottomText(AOrder: Integer): TLabel;
    function Current: TAtlasValueSeries;
    function CurrentThread: string;
    procedure FillSeries;
    procedure FillThreads;
    procedure ShowCurrent;
    procedure SeriesChange(Sender: TObject);
    procedure ThreadChange(Sender: TObject);
    procedure CopyCsvClick(Sender: TObject);
    procedure ChartPointClick(Sender: TObject; AIndex: Integer);
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Reihen zeigen (nicht im Besitz; nil = leer).</summary>
    procedure SetSeries(ASet: TAtlasValueSeriesSet);
    /// <summary>Neue Treffer oder Reihen: Auswahl, Linie und Zahlen neu.</summary>
    procedure Refresh;
    property Chart: TAtlasDebugValueChart read FControls.Chart;
    property SeriesBox: TComboBox read FControls.SeriesBox;
    property ThreadBox: TComboBox read FControls.ThreadBox;
    property StatsLabel: TLabel read FControls.StatsLabel;
    property PointLabel: TLabel read FControls.PointLabel;
    property OnCopyCsv: TAtlasValuesCsvEvent read FOnCopyCsv write FOnCopyCsv;
    property OnPoint: TAtlasValuesPointEvent read FOnPoint write FOnPoint;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.Graphics,
  Atlas.Core.Debug.TimeChart,
  Atlas.UI.Debug.Logpoints.Strings,
  Atlas.UI.Foundation.WrapLabel;

{$R *.dfm}

const
  /// <summary>Leiste oben, Breiten der Auswahl und des Knopfs, logische Pixel.</summary>
  cBarHeight = 32;
  cSeriesWidth = 260;
  cThreadWidth = 150;
  cButtonWidth = 110;
  /// <summary>Reihenfolge der Beschriftungen unten (alBottom: größeres Top liegt weiter unten).</summary>
  cOrderStats = 10000;
  cOrderPoint = 20000;
  cOrderHint = 30000;

{ TAtlasDebugValueChart }

procedure TAtlasDebugValueChart.SetPoints(const AValue: TArray<TAtlasValuePoint>);
begin
  FPoints := AValue;
  Invalidate;
end;

function TAtlasDebugValueChart.PointCount: Integer;
begin
  Result := Length(FPoints);
end;

function TAtlasDebugValueChart.PointAtMs(AIndex: Integer): Int64;
begin
  Result := FPoints[AIndex].AtMs;
end;

function TAtlasDebugValueChart.PointValue(AIndex: Integer; out AValue: Double): Boolean;
begin
  AValue := FPoints[AIndex].Value;
  Result := not FPoints[AIndex].IsGap;
end;

procedure TAtlasDebugValueChart.ValueRange(out ALow, AHigh: Double);
var
  mPoint: TAtlasValuePoint;
  mMin, mMax: Double;
  mAny: Boolean;
begin
  mMin := 0;
  mMax := 0;
  mAny := False;
  for mPoint in FPoints do
  begin
    if mPoint.IsGap then
    begin
      Continue;
    end;
    if not mAny or (mPoint.Value < mMin) then
    begin
      mMin := mPoint.Value;
    end;
    if not mAny or (mPoint.Value > mMax) then
    begin
      mMax := mPoint.Value;
    end;
    mAny := True;
  end;
  TAtlasTimeChartScale.NiceRange(mMin, mMax, ALow, AHigh);
end;

function TAtlasDebugValueChart.ValueText(AValue: Double): string;
begin
  Result := TAtlasValueText.Text(AValue, FormatSettings);
end;

class function TAtlasDebugValueChart.PointText(const APoint: TAtlasValuePoint): string;
var
  mValue: string;
begin
  mValue := TAtlasLogpointsStrings.Text(TAtlasLogpointsTextId.ValuesGap);
  if not APoint.IsGap then
  begin
    mValue := TAtlasValueText.Text(APoint.Value, FormatSettings);
  end;
  Result := TAtlasLogpointsStrings.Fmt(TAtlasLogpointsTextId.ValuesPoint, [Seconds(APoint.AtMs), APoint.Thread,
    mValue]);
end;

function TAtlasDebugValueChart.HoverOf(AIndex: Integer; const ASeconds: string): string;
begin
  Result := PointText(FPoints[AIndex]);
end;

{ TAtlasDebugLogpointValuesFrame }

constructor TAtlasDebugLogpointValuesFrame.Create(AOwner: TComponent);
var
  mHint: TLabel;
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  BuildTopBar;
  mHint := AddBottomText(cOrderHint);
  mHint.Caption := TAtlasLogpointsStrings.Text(TAtlasLogpointsTextId.ValuesClickHint);
  mHint.Font.Color := clGrayText;
  FControls.PointLabel := AddBottomText(cOrderPoint);
  FControls.StatsLabel := AddBottomText(cOrderStats);
  FControls.Chart := TAtlasDebugValueChart.Create(Self);
  FControls.Chart.Parent := Self;
  FControls.Chart.Align := alClient;
  FControls.Chart.AlignWithMargins := True;
  FControls.Chart.EmptyText := TAtlasLogpointsStrings.Text(TAtlasLogpointsTextId.ValuesEmpty);
  FControls.Chart.OnPointClick := ChartPointClick;
end;

procedure TAtlasDebugLogpointValuesFrame.BuildTopBar;
var
  mBar: TPanel;
begin
  mBar := TPanel.Create(Self);
  mBar.Height := MulDiv(cBarHeight, CurrentPPI, 96);
  mBar.Align := alTop;
  mBar.Parent := Self;
  mBar.BevelOuter := bvNone;
  mBar.ShowCaption := False;
  mBar.ParentBackground := True;
  FControls.CopyCsv := TButton.Create(Self);
  FControls.CopyCsv.Parent := mBar;
  FControls.CopyCsv.Align := alRight;
  FControls.CopyCsv.AlignWithMargins := True;
  FControls.CopyCsv.Width := MulDiv(cButtonWidth, CurrentPPI, 96);
  FControls.CopyCsv.Caption := TAtlasLogpointsStrings.Text(TAtlasLogpointsTextId.ValuesCopyCsv);
  FControls.CopyCsv.OnClick := CopyCsvClick;
  FControls.SeriesBox := TComboBox.Create(Self);
  FControls.SeriesBox.Parent := mBar;
  FControls.SeriesBox.Align := alLeft;
  FControls.SeriesBox.AlignWithMargins := True;
  FControls.SeriesBox.Style := csDropDownList;
  FControls.SeriesBox.Width := MulDiv(cSeriesWidth, CurrentPPI, 96);
  FControls.SeriesBox.OnChange := SeriesChange;
  FControls.ThreadBox := TComboBox.Create(Self);
  FControls.ThreadBox.Left := FControls.SeriesBox.Left + FControls.SeriesBox.Width + 1;
  FControls.ThreadBox.Parent := mBar;
  FControls.ThreadBox.Align := alLeft;
  FControls.ThreadBox.AlignWithMargins := True;
  FControls.ThreadBox.Style := csDropDownList;
  FControls.ThreadBox.Width := MulDiv(cThreadWidth, CurrentPPI, 96);
  FControls.ThreadBox.OnChange := ThreadChange;
end;

function TAtlasDebugLogpointValuesFrame.AddBottomText(AOrder: Integer): TLabel;
begin
  Result := TAtlasWrapLabel.Create(Self);
  Result.Top := AOrder;
  Result.Align := alBottom;
  Result.Parent := Self;
  Result.AlignWithMargins := True;
  Result.ShowAccelChar := False;
  Result.Caption := '';
end;

procedure TAtlasDebugLogpointValuesFrame.CreateWnd;
begin
  inherited CreateWnd;
  // TComboBox.Items braucht ein Fenster.
  Refresh;
end;

function TAtlasDebugLogpointValuesFrame.Current: TAtlasValueSeries;
var
  mIndex: Integer;
begin
  Result := nil;
  mIndex := FControls.SeriesBox.ItemIndex;
  if (FSet <> nil) and (mIndex >= 0) and (mIndex <= High(FPlaces)) then
  begin
    Result := FSet.Find(FPlaces[mIndex]);
  end;
end;

function TAtlasDebugLogpointValuesFrame.CurrentThread: string;
var
  mIndex: Integer;
begin
  Result := '';
  // Eintrag 0 ist „alle“.
  mIndex := FControls.ThreadBox.ItemIndex - 1;
  if (mIndex >= 0) and (mIndex <= High(FThreads)) then
  begin
    Result := FThreads[mIndex];
  end;
end;

procedure TAtlasDebugLogpointValuesFrame.FillSeries;
var
  mKept: string;
  mIndex: Integer;
  mPlaces: TArray<string>;
begin
  mKept := '';
  if (FControls.SeriesBox.ItemIndex >= 0) and (FControls.SeriesBox.ItemIndex <= High(FPlaces)) then
  begin
    mKept := FPlaces[FControls.SeriesBox.ItemIndex];
  end;
  mPlaces := nil;
  if FSet <> nil then
  begin
    SetLength(mPlaces, FSet.Count);
    for mIndex := 0 to FSet.Count - 1 do
    begin
      mPlaces[mIndex] := FSet[mIndex].Place;
    end;
  end;
  if (Length(mPlaces) = Length(FPlaces)) and (FControls.SeriesBox.Items.Count = Length(mPlaces)) and
    (string.Join('|', mPlaces) = string.Join('|', FPlaces)) then
  begin
    Exit;
  end;
  FPlaces := mPlaces;
  FControls.SeriesBox.Items.BeginUpdate;
  try
    FControls.SeriesBox.Items.Clear;
    for mIndex := 0 to High(FPlaces) do
    begin
      FControls.SeriesBox.Items.Add(TAtlasLogpointsStrings.Fmt(TAtlasLogpointsTextId.ValuesSeriesItem,
        [FSet[mIndex].Name, FSet[mIndex].Place]));
    end;
  finally
    FControls.SeriesBox.Items.EndUpdate;
  end;
  FControls.SeriesBox.ItemIndex := 0;
  for mIndex := 0 to High(FPlaces) do
  begin
    if SameText(FPlaces[mIndex], mKept) then
    begin
      FControls.SeriesBox.ItemIndex := mIndex;
    end;
  end;
  if FPlaces = nil then
  begin
    FControls.SeriesBox.ItemIndex := -1;
  end;
end;

procedure TAtlasDebugLogpointValuesFrame.FillThreads;
var
  mSeries: TAtlasValueSeries;
  mThreads: TArray<string>;
  mKept: string;
  mThread: string;
  mIndex: Integer;
begin
  mSeries := Current;
  mThreads := nil;
  if mSeries <> nil then
  begin
    mThreads := mSeries.Threads;
  end;
  if (FControls.ThreadBox.Items.Count = Length(mThreads) + 1) and
    (string.Join('|', mThreads) = string.Join('|', FThreads)) then
  begin
    Exit;
  end;
  mKept := CurrentThread;
  FThreads := mThreads;
  FControls.ThreadBox.Items.BeginUpdate;
  try
    FControls.ThreadBox.Items.Clear;
    FControls.ThreadBox.Items.Add(TAtlasLogpointsStrings.Text(TAtlasLogpointsTextId.ValuesAllThreads));
    for mThread in FThreads do
    begin
      FControls.ThreadBox.Items.Add(TAtlasLogpointsStrings.Fmt(TAtlasLogpointsTextId.ValuesThread, [mThread]));
    end;
  finally
    FControls.ThreadBox.Items.EndUpdate;
  end;
  FControls.ThreadBox.ItemIndex := 0;
  for mIndex := 0 to High(FThreads) do
  begin
    if (mKept <> '') and (FThreads[mIndex] = mKept) then
    begin
      FControls.ThreadBox.ItemIndex := mIndex + 1;
    end;
  end;
end;

procedure TAtlasDebugLogpointValuesFrame.ShowCurrent;
var
  mSeries: TAtlasValueSeries;
  mStats: TAtlasValueStats;
begin
  mSeries := Current;
  FControls.StatsLabel.Caption := '';
  FControls.CopyCsv.Enabled := (mSeries <> nil) and (mSeries.Count > 0);
  if mSeries = nil then
  begin
    FControls.Chart.Points := nil;
    FControls.PointLabel.Caption := '';
    Exit;
  end;
  FControls.Chart.Points := mSeries.PointsOf(CurrentThread);
  mStats := mSeries.Stats(CurrentThread);
  if mStats.Numbers > 0 then
  begin
    FControls.StatsLabel.Caption := TAtlasLogpointsStrings.Fmt(TAtlasLogpointsTextId.ValuesStats, [mStats.Count,
      TAtlasValueText.Text(mStats.Min, FormatSettings), TAtlasValueText.Text(mStats.Max, FormatSettings),
      TAtlasValueText.Text(mStats.Last, FormatSettings)]);
  end
  else if mStats.Count > 0 then
  begin
    FControls.StatsLabel.Caption := TAtlasLogpointsStrings.Fmt(TAtlasLogpointsTextId.ValuesStatsNone,
      [mStats.Count]);
  end;
end;

procedure TAtlasDebugLogpointValuesFrame.SetSeries(ASet: TAtlasValueSeriesSet);
begin
  FSet := ASet;
  FPlaces := nil;
  Refresh;
end;

procedure TAtlasDebugLogpointValuesFrame.Refresh;
begin
  // Ohne Fenster haben die Auswahllisten keine Einträge; CreateWnd ruft erneut.
  if not HandleAllocated then
  begin
    Exit;
  end;
  FillSeries;
  FillThreads;
  ShowCurrent;
end;

procedure TAtlasDebugLogpointValuesFrame.SeriesChange(Sender: TObject);
begin
  FThreads := nil;
  FControls.PointLabel.Caption := '';
  FillThreads;
  ShowCurrent;
end;

procedure TAtlasDebugLogpointValuesFrame.ThreadChange(Sender: TObject);
begin
  FControls.PointLabel.Caption := '';
  ShowCurrent;
end;

procedure TAtlasDebugLogpointValuesFrame.CopyCsvClick(Sender: TObject);
var
  mSeries: TAtlasValueSeries;
begin
  mSeries := Current;
  if (mSeries <> nil) and Assigned(FOnCopyCsv) then
  begin
    FOnCopyCsv(mSeries.Place, CurrentThread);
  end;
end;

procedure TAtlasDebugLogpointValuesFrame.ChartPointClick(Sender: TObject; AIndex: Integer);
var
  mPoint: TAtlasValuePoint;
begin
  if (AIndex < 0) or (AIndex >= Length(FControls.Chart.Points)) then
  begin
    Exit;
  end;
  mPoint := FControls.Chart.Points[AIndex];
  FControls.PointLabel.Caption := TAtlasDebugValueChart.PointText(mPoint) + ' → ' +
    TAtlasLogpointsStrings.Text(TAtlasLogpointsTextId.ValuesCaption);
  if Assigned(FOnPoint) then
  begin
    FOnPoint(mPoint);
  end;
end;

end.
