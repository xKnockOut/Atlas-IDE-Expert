unit Atlas.UI.Debug.MemoryChart;

// Linie des Speicherverlaufs (#858), reine VCL: eine Reihe (privater Speicher,
// Arbeitssatz, Handles, GDI- oder USER-Objekte) über der Zeit seit
// Sitzungsbeginn, Marken bei Halt (gedämpft), Exception (rot) und eigener
// Marke (Akzent mit Namen). Zeichnen, Bereichswahl und Hinweis übernimmt
// TAtlasDebugTimeChart; diese Ableitung liefert nur Messwerte, Marken und das
// Format der Werte (Bytes bzw. Zahl) aus Atlas.Core.Debug.MemoryTimeline.

interface

uses
  System.Classes,
  Atlas.Core.Debug.MemoryTimeline,
  Atlas.UI.Debug.TimeChart;

type
  TAtlasDebugMemoryChart = class(TAtlasDebugTimeChart)
  private
    FTimeline: TAtlasMemoryTimeline;
    FSeries: TAtlasMemorySeries;
    procedure SetSeries(AValue: TAtlasMemorySeries);
  protected
    function PointCount: Integer; override;
    function PointAtMs(AIndex: Integer): Int64; override;
    function PointValue(AIndex: Integer; out AValue: Double): Boolean; override;
    procedure ValueRange(out ALow, AHigh: Double); override;
    function ValueText(AValue: Double): string; override;
    function HoverOf(AIndex: Integer; const ASeconds: string): string; override;
    function MarkCount: Integer; override;
    function MarkAt(AIndex: Integer): TAtlasTimeChartMark; override;
  public
    /// <summary>Verlauf (nicht im Besitz); nil zeigt EmptyText.</summary>
    property Timeline: TAtlasMemoryTimeline read FTimeline write FTimeline;
    property Series: TAtlasMemorySeries read FSeries write SetSeries;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Atlas.Core.Debug.TimeChart,
  Atlas.UI.Debug.Memory.Strings;

{ TAtlasDebugMemoryChart }

procedure TAtlasDebugMemoryChart.SetSeries(AValue: TAtlasMemorySeries);
begin
  if AValue = FSeries then
  begin
    Exit;
  end;
  FSeries := AValue;
  Invalidate;
end;

function TAtlasDebugMemoryChart.PointCount: Integer;
begin
  Result := 0;
  if FTimeline <> nil then
  begin
    Result := FTimeline.Count;
  end;
end;

function TAtlasDebugMemoryChart.PointAtMs(AIndex: Integer): Int64;
begin
  Result := FTimeline[AIndex].AtMs;
end;

function TAtlasDebugMemoryChart.PointValue(AIndex: Integer; out AValue: Double): Boolean;
begin
  AValue := FTimeline[AIndex].Values[FSeries];
  Result := True;
end;

procedure TAtlasDebugMemoryChart.ValueRange(out ALow, AHigh: Double);
begin
  ALow := 0;
  AHigh := TAtlasTimeChartScale.NiceMax(Max(FTimeline.MaxOf(FSeries), 1));
end;

function TAtlasDebugMemoryChart.ValueText(AValue: Double): string;
begin
  Result := TAtlasMemoryFormat.Value(FSeries, Round(AValue), FormatSettings);
end;

function TAtlasDebugMemoryChart.HoverOf(AIndex: Integer; const ASeconds: string): string;
begin
  Result := TAtlasMemoryStrings.Fmt(TAtlasMemoryTextId.MemoryHover, [ASeconds,
    TAtlasMemoryFormat.Value(FSeries, FTimeline[AIndex].Values[FSeries], FormatSettings)]);
end;

function TAtlasDebugMemoryChart.MarkCount: Integer;
begin
  Result := 0;
  if FTimeline <> nil then
  begin
    Result := FTimeline.MarkCount;
  end;
end;

function TAtlasDebugMemoryChart.MarkAt(AIndex: Integer): TAtlasTimeChartMark;
var
  mMark: TAtlasMemoryMark;
begin
  mMark := FTimeline.Marks[AIndex];
  Result := Default(TAtlasTimeChartMark);
  Result.AtMs := mMark.AtMs;
  case mMark.Kind of
    TAtlasMemoryMarkKind.Exception:
      Result.Kind := TAtlasTimeChartMarkKind.Error;
    TAtlasMemoryMarkKind.Custom:
      begin
        Result.Kind := TAtlasTimeChartMarkKind.Accent;
        Result.Name := mMark.Name;
      end;
    TAtlasMemoryMarkKind.Stop:
      Result.Kind := TAtlasTimeChartMarkKind.Muted;
  end;
end;

end.
