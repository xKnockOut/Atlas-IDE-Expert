unit Atlas.UI.Debug.MemoryFrame;

// Inhalt des Fensters „Atlas: Speicher“ (#858): oben die Wahl der Reihe und
// die Knöpfe „Marke setzen“, „CSV kopieren“ und „Leeren“, in der Mitte die
// Linie (TAtlasDebugMemoryChart), unten die aktuellen Werte, der Zuwachs im
// gewählten Bereich und ein Hinweis zur Bedienung. Den Verlauf besitzt die
// IDE-Schicht (Atlas.IDE.Debug.MemoryTimeline); sie meldet neue Messungen mit
// Refresh und reagiert auf OnMark, OnCopyCsv und OnClear.
// Mit debug.memoryTimeline.objectCount (experimentell) steht unter der Linie
// der Bereich „Objekte zählen“ (TAtlasDebugObjectCountPanel, ShowObjectCount).

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Atlas.Core.Debug.MemoryTimeline,
  Atlas.UI.Debug.MemoryChart,
  Atlas.UI.Debug.ObjectCountPanel;

type
  /// <summary>Texte des Fensters „Atlas: Speicher“.</summary>
  TAtlasMemoryTexts = class
  public
    class function SeriesName(ASeries: TAtlasMemorySeries): string; static;
    /// <summary>„Jetzt: Privater Speicher 120,3 MB · … · USER-Objekte 30“.</summary>
    class function NowText(const AValues: TAtlasMemoryValues): string; static;
    /// <summary>„Bereich 4,0 s bis 64,0 s (60,0 s): Privater Speicher +38,0 MB · …“; '' ohne gültigen Bereich.
    /// </summary>
    class function RangeText(const AGrowth: TAtlasMemoryGrowth): string; static;
  end;

  TAtlasDebugMemoryFrame = class(TFrame)
  private type
    TControls = record
      SeriesBox: TComboBox;
      Mark: TButton;
      CopyCsv: TButton;
      Clear: TButton;
      Chart: TAtlasDebugMemoryChart;
      NowLabel: TLabel;
      RangeLabel: TLabel;
      ObjectCount: TAtlasDebugObjectCountPanel;
      ObjectCountSplitter: TSplitter;
    end;
    TEvents = record
      Mark: TProc;
      CopyCsv: TProc;
      Clear: TProc;
    end;
  private
    FControls: TControls;
    FEvents: TEvents;
    FTimeline: TAtlasMemoryTimeline;
    procedure FillSeries;
    procedure UpdateLabels;
    procedure SeriesChange(Sender: TObject);
    procedure MarkClick(Sender: TObject);
    procedure CopyCsvClick(Sender: TObject);
    procedure ClearClick(Sender: TObject);
    procedure ChartSelection(Sender: TObject);
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Verlauf zeigen (nicht im Besitz; nil = leer).</summary>
    procedure SetTimeline(ATimeline: TAtlasMemoryTimeline);
    /// <summary>Neue Messung oder Marke: Linie und Werte neu.</summary>
    procedure Refresh;
    /// <summary>Bereich „Objekte zählen“ zeigen oder verbergen (debug.memoryTimeline.objectCount).</summary>
    procedure ShowObjectCount(AVisible: Boolean);
    property Chart: TAtlasDebugMemoryChart read FControls.Chart;
    property SeriesBox: TComboBox read FControls.SeriesBox;
    property MarkButton: TButton read FControls.Mark;
    property CopyCsvButton: TButton read FControls.CopyCsv;
    property ClearButton: TButton read FControls.Clear;
    property NowLabel: TLabel read FControls.NowLabel;
    property RangeLabel: TLabel read FControls.RangeLabel;
    property ObjectCount: TAtlasDebugObjectCountPanel read FControls.ObjectCount;
    property OnMark: TProc read FEvents.Mark write FEvents.Mark;
    property OnCopyCsv: TProc read FEvents.CopyCsv write FEvents.CopyCsv;
    property OnClear: TProc read FEvents.Clear write FEvents.Clear;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.UI.Debug.Memory.Strings;

{$R *.dfm}

const
  cSeriesTexts: array[TAtlasMemorySeries] of TAtlasMemoryTextId = (TAtlasMemoryTextId.MemorySeriesPrivateBytes,
    TAtlasMemoryTextId.MemorySeriesWorkingSet, TAtlasMemoryTextId.MemorySeriesHandles,
    TAtlasMemoryTextId.MemorySeriesGdiObjects, TAtlasMemoryTextId.MemorySeriesUserObjects);
  cSeparator = ' · ';
  /// <summary>Höhe der Leiste oben und Breite der Wahl der Reihe, logische Pixel.</summary>
  cBarHeight = 32;
  cSeriesWidth = 170;
  cButtonWidth = 96;
  /// <summary>Reihenfolge der Beschriftungen unten (alBottom: größeres Top liegt weiter unten).</summary>
  cOrderHint = 30000;
  cOrderRange = 20000;
  cOrderNow = 10000;
  /// <summary>Objektzählung ganz unten unter den Beschriftungen, die Trennleiste darüber.</summary>
  cOrderObjectCount = 50000;
  cOrderSplitter = 40000;
  cObjectCountHeight = 220;

function Seconds(AMs: Int64): string;
begin
  Result := FormatFloat('0.0', AMs / 1000, FormatSettings);
end;

{ TAtlasMemoryTexts }

class function TAtlasMemoryTexts.SeriesName(ASeries: TAtlasMemorySeries): string;
begin
  Result := TAtlasMemoryStrings.Text(cSeriesTexts[ASeries]);
end;

class function TAtlasMemoryTexts.NowText(const AValues: TAtlasMemoryValues): string;
var
  mSeries: TAtlasMemorySeries;
  mParts: TArray<string>;
begin
  SetLength(mParts, Ord(High(TAtlasMemorySeries)) + 1);
  for mSeries := Low(TAtlasMemorySeries) to High(TAtlasMemorySeries) do
  begin
    mParts[Ord(mSeries)] := SeriesName(mSeries) + ' ' + TAtlasMemoryFormat.Value(mSeries, AValues[mSeries],
      FormatSettings);
  end;
  Result := TAtlasMemoryStrings.Fmt(TAtlasMemoryTextId.MemoryNow, [string.Join(cSeparator, mParts)]);
end;

class function TAtlasMemoryTexts.RangeText(const AGrowth: TAtlasMemoryGrowth): string;
var
  mSeries: TAtlasMemorySeries;
  mParts: TArray<string>;
begin
  Result := '';
  if not AGrowth.Valid then
  begin
    Exit;
  end;
  SetLength(mParts, Ord(High(TAtlasMemorySeries)) + 1);
  for mSeries := Low(TAtlasMemorySeries) to High(TAtlasMemorySeries) do
  begin
    mParts[Ord(mSeries)] := SeriesName(mSeries) + ' ' + TAtlasMemoryFormat.Signed(mSeries,
      AGrowth.Deltas[mSeries], FormatSettings);
  end;
  Result := TAtlasMemoryStrings.Fmt(TAtlasMemoryTextId.MemoryRange, [Seconds(AGrowth.FromMs), Seconds(AGrowth.ToMs),
    Seconds(AGrowth.DurationMs), string.Join(cSeparator, mParts)]);
end;

{ Aufbau }

/// <summary>Knopf rechts in AParent (Besitzer AFrame).</summary>
function AddButton(AFrame: TAtlasDebugMemoryFrame; AParent: TWinControl; const ACaption: string;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(AFrame);
  Result.Parent := AParent;
  Result.Align := alRight;
  Result.AlignWithMargins := True;
  Result.Width := MulDiv(cButtonWidth, AFrame.CurrentPPI, 96);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
end;

/// <summary>Umbrechende Beschriftung unten in AFrame; größeres ATop liegt weiter unten.</summary>
function AddBottomLabel(AFrame: TAtlasDebugMemoryFrame; ATop: Integer; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(AFrame);
  Result.Top := ATop;
  Result.Align := alBottom;
  Result.Parent := AFrame;
  Result.AlignWithMargins := True;
  Result.ShowAccelChar := False;
  Result.WordWrap := True;
  Result.Caption := ACaption;
end;

/// <summary>Leiste oben: Wahl der Reihe links, Knöpfe rechts.</summary>
procedure CreateTopBar(AFrame: TAtlasDebugMemoryFrame);
var
  mBar: TPanel;
begin
  mBar := TPanel.Create(AFrame);
  mBar.Height := MulDiv(cBarHeight, AFrame.CurrentPPI, 96);
  mBar.Align := alTop;
  mBar.Parent := AFrame;
  mBar.BevelOuter := bvNone;
  mBar.ShowCaption := False;
  mBar.ParentBackground := True;
  AFrame.FControls.Clear := AddButton(AFrame, mBar, TAtlasMemoryStrings.Text(TAtlasMemoryTextId.MemoryClear),
    AFrame.ClearClick);
  AFrame.FControls.CopyCsv := AddButton(AFrame, mBar, TAtlasMemoryStrings.Text(TAtlasMemoryTextId.MemoryCopyCsv),
    AFrame.CopyCsvClick);
  AFrame.FControls.Mark := AddButton(AFrame, mBar, TAtlasMemoryStrings.Text(TAtlasMemoryTextId.MemoryMark),
    AFrame.MarkClick);
  AFrame.FControls.SeriesBox := TComboBox.Create(AFrame);
  AFrame.FControls.SeriesBox.Parent := mBar;
  AFrame.FControls.SeriesBox.Align := alLeft;
  AFrame.FControls.SeriesBox.AlignWithMargins := True;
  AFrame.FControls.SeriesBox.Style := csDropDownList;
  AFrame.FControls.SeriesBox.Width := MulDiv(cSeriesWidth, AFrame.CurrentPPI, 96);
  AFrame.FControls.SeriesBox.OnChange := AFrame.SeriesChange;
end;

/// <summary>Bereich „Objekte zählen“ samt Trennleiste, zunächst verborgen.</summary>
procedure CreateObjectCount(AFrame: TAtlasDebugMemoryFrame);
begin
  AFrame.FControls.ObjectCount := TAtlasDebugObjectCountPanel.Create(AFrame);
  AFrame.FControls.ObjectCount.Visible := False;
  AFrame.FControls.ObjectCount.Top := cOrderObjectCount;
  AFrame.FControls.ObjectCount.Height := MulDiv(cObjectCountHeight, AFrame.CurrentPPI, 96);
  AFrame.FControls.ObjectCount.Align := alBottom;
  AFrame.FControls.ObjectCount.Parent := AFrame;
  AFrame.FControls.ObjectCountSplitter := TSplitter.Create(AFrame);
  AFrame.FControls.ObjectCountSplitter.Visible := False;
  AFrame.FControls.ObjectCountSplitter.Top := cOrderSplitter;
  AFrame.FControls.ObjectCountSplitter.Align := alBottom;
  AFrame.FControls.ObjectCountSplitter.Parent := AFrame;
end;

{ TAtlasDebugMemoryFrame }

constructor TAtlasDebugMemoryFrame.Create(AOwner: TComponent);
var
  mHint: TLabel;
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  CreateTopBar(Self);
  mHint := AddBottomLabel(Self, cOrderHint, TAtlasMemoryStrings.Text(TAtlasMemoryTextId.MemoryRangeHint));
  mHint.Font.Color := clGrayText;
  FControls.RangeLabel := AddBottomLabel(Self, cOrderRange, '');
  FControls.NowLabel := AddBottomLabel(Self, cOrderNow, '');
  CreateObjectCount(Self);
  FControls.Chart := TAtlasDebugMemoryChart.Create(Self);
  FControls.Chart.Parent := Self;
  FControls.Chart.Align := alClient;
  FControls.Chart.AlignWithMargins := True;
  FControls.Chart.EmptyText := TAtlasMemoryStrings.Text(TAtlasMemoryTextId.MemoryEmpty);
  FControls.Chart.OnSelection := ChartSelection;
  UpdateLabels;
end;

procedure TAtlasDebugMemoryFrame.CreateWnd;
begin
  inherited CreateWnd;
  // TComboBox.Items braucht ein Fenster.
  FillSeries;
end;

procedure TAtlasDebugMemoryFrame.FillSeries;
var
  mSeries: TAtlasMemorySeries;
begin
  if not FControls.SeriesBox.HandleAllocated then
  begin
    if not HandleAllocated then
    begin
      Exit;
    end;
    FControls.SeriesBox.HandleNeeded;
  end;
  if FControls.SeriesBox.Items.Count > 0 then
  begin
    Exit;
  end;
  FControls.SeriesBox.Items.BeginUpdate;
  try
    for mSeries := Low(TAtlasMemorySeries) to High(TAtlasMemorySeries) do
    begin
      FControls.SeriesBox.Items.Add(TAtlasMemoryTexts.SeriesName(mSeries));
    end;
  finally
    FControls.SeriesBox.Items.EndUpdate;
  end;
  FControls.SeriesBox.ItemIndex := Ord(FControls.Chart.Series);
end;

procedure TAtlasDebugMemoryFrame.SetTimeline(ATimeline: TAtlasMemoryTimeline);
begin
  FTimeline := ATimeline;
  FControls.Chart.Timeline := ATimeline;
  Refresh;
end;

procedure TAtlasDebugMemoryFrame.Refresh;
begin
  FControls.Chart.Invalidate;
  UpdateLabels;
end;

procedure TAtlasDebugMemoryFrame.ShowObjectCount(AVisible: Boolean);
begin
  if FControls.ObjectCount.Visible = AVisible then
  begin
    Exit;
  end;
  // Ganz nach unten (unter die Beschriftungen), die Trennleiste direkt darüber.
  FControls.ObjectCount.Top := ClientHeight + cOrderObjectCount;
  FControls.ObjectCount.Visible := AVisible;
  FControls.ObjectCountSplitter.Top := FControls.ObjectCount.Top - 1;
  FControls.ObjectCountSplitter.Visible := AVisible;
end;

procedure TAtlasDebugMemoryFrame.UpdateLabels;
var
  mHas: Boolean;
begin
  mHas := (FTimeline <> nil) and (FTimeline.Count > 0);
  if mHas then
  begin
    FControls.NowLabel.Caption := TAtlasMemoryTexts.NowText(FTimeline[FTimeline.Count - 1].Values);
  end
  else
  begin
    FControls.NowLabel.Caption := '';
  end;
  FControls.RangeLabel.Caption := '';
  if mHas and FControls.Chart.HasSelection then
  begin
    FControls.RangeLabel.Caption := TAtlasMemoryTexts.RangeText(FTimeline.Growth(FControls.Chart.SelectionFromMs,
      FControls.Chart.SelectionToMs));
  end;
  FControls.CopyCsv.Enabled := mHas;
  FControls.Clear.Enabled := mHas;
  FControls.Mark.Enabled := mHas;
end;

procedure TAtlasDebugMemoryFrame.SeriesChange(Sender: TObject);
begin
  if FControls.SeriesBox.ItemIndex >= 0 then
  begin
    FControls.Chart.Series := TAtlasMemorySeries(FControls.SeriesBox.ItemIndex);
  end;
end;

procedure TAtlasDebugMemoryFrame.MarkClick(Sender: TObject);
begin
  if Assigned(FEvents.Mark) then
  begin
    FEvents.Mark();
  end;
end;

procedure TAtlasDebugMemoryFrame.CopyCsvClick(Sender: TObject);
begin
  if Assigned(FEvents.CopyCsv) then
  begin
    FEvents.CopyCsv();
  end;
end;

procedure TAtlasDebugMemoryFrame.ClearClick(Sender: TObject);
begin
  FControls.Chart.ClearSelection;
  if Assigned(FEvents.Clear) then
  begin
    FEvents.Clear();
  end;
end;

procedure TAtlasDebugMemoryFrame.ChartSelection(Sender: TObject);
begin
  UpdateLabels;
end;

end.
