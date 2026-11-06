unit Atlas.Core.Analysis.MetricsLens;

// Beschriftung der Code Lens mit Code-Metriken (#66) im Modul Analyse (#1756), ohne VCL und OTA. Die Werte liest
// Base (Atlas.Core.Editor.Metrics); hier entsteht der Text je Methode bzw. Aufbau, die Prüfung auf Grenzwerte und
// die Prüfung, ob die Zeile noch zur Methode passt. Stehen mehrere Kennzahlen des Aufbaus in einer Zeile (Member
// und Vererbungstiefe, #980), zeigt die Lens beide.

interface

uses
  Atlas.Core.Editor.Metrics;

type
  /// <summary>Formate der Beschriftung je Kennzahl mit %d, z. B. „%d Zeilen“, „Tiefe %d“.</summary>
  TAtlasMetricFormats = array[TAtlasMetric] of string;

  /// <summary>Formate der Beschriftung je Kennzahl des Aufbaus mit %d, z. B. „%d Member“.</summary>
  TAtlasStructureFormats = array[TAtlasStructureMetric] of string;

  TAtlasMetricsLens = class
  public
    /// <summary>Beschriftung, Teile mit „ · “ getrennt; ein Wert über dem Grenzwert bekommt ALimitFormat
    /// (mit %s für den Teil und %d für den Grenzwert), z. B. „zyklomatisch 17 (> 15)“.</summary>
    class function Caption(const AMethod: TAtlasMethodMetrics; const ALimits: TAtlasMetricValues;
      const AFormats: TAtlasMetricFormats; const ALimitFormat: string): string; static;
    /// <summary>Mindestens eine Kennzahl über ihrem Grenzwert.</summary>
    class function Exceeds(const AMethod: TAtlasMethodMetrics; const ALimits: TAtlasMetricValues): Boolean; static;
    /// <summary>Beschriftung einer Kennzahl des Aufbaus, über dem Grenzwert mit ALimitFormat, z. B.
    /// „87 Member (> 40)“ (#939).</summary>
    class function StructureCaption(const AItem: TAtlasStructureItem; const AFormats: TAtlasStructureFormats;
      const ALimitFormat: string): string; overload; static;
    /// <summary>Beschriftungen aller AItems mit „ · “ getrennt; Untergrenzen (AtLeast) mit AAtLeastFormat, z. B.
    /// „Vererbungstiefe mindestens %d“ (#980).</summary>
    class function StructureCaption(const AItems: TArray<TAtlasStructureItem>; const AFormats: TAtlasStructureFormats;
      const AAtLeastFormat, ALimitFormat: string): string; overload; static;
    /// <summary>True, wenn ALine den letzten Teil von AName als Bezeichner enthält (die Lens steht noch an
    /// ihrer Methode, auch wenn der Text seit dem Abruf verschoben ist).</summary>
    class function LineMatches(const ALine, AName: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Chars;

{ TAtlasMetricsLens }

class function TAtlasMetricsLens.StructureCaption(const AItem: TAtlasStructureItem;
  const AFormats: TAtlasStructureFormats; const ALimitFormat: string): string;
begin
  Result := Format(AFormats[AItem.Kind], [AItem.Value]);
  if AItem.Value > AItem.Limit then
  begin
    Result := Format(ALimitFormat, [Result, AItem.Limit]);
  end;
end;

class function TAtlasMetricsLens.StructureCaption(const AItems: TArray<TAtlasStructureItem>;
  const AFormats: TAtlasStructureFormats; const AAtLeastFormat, ALimitFormat: string): string;
var
  mItem: TAtlasStructureItem;
  mFormats: TAtlasStructureFormats;
begin
  Result := '';
  for mItem in AItems do
  begin
    mFormats := AFormats;
    if mItem.AtLeast then
    begin
      mFormats[mItem.Kind] := AAtLeastFormat;
    end;
    if Result <> '' then
    begin
      Result := Result + ' · ';
    end;
    Result := Result + StructureCaption(mItem, mFormats, ALimitFormat);
  end;
end;

class function TAtlasMetricsLens.Caption(const AMethod: TAtlasMethodMetrics; const ALimits: TAtlasMetricValues;
  const AFormats: TAtlasMetricFormats; const ALimitFormat: string): string;
var
  mMetric: TAtlasMetric;
  mPart: string;
begin
  Result := '';
  for mMetric := Low(TAtlasMetric) to High(TAtlasMetric) do
  begin
    mPart := Format(AFormats[mMetric], [AMethod.Values[mMetric]]);
    if AMethod.Values[mMetric] > ALimits[mMetric] then
    begin
      mPart := Format(ALimitFormat, [mPart, ALimits[mMetric]]);
    end;
    if Result <> '' then
    begin
      Result := Result + ' · ';
    end;
    Result := Result + mPart;
  end;
end;

class function TAtlasMetricsLens.Exceeds(const AMethod: TAtlasMethodMetrics; const ALimits: TAtlasMetricValues): Boolean;
var
  mMetric: TAtlasMetric;
begin
  for mMetric := Low(TAtlasMetric) to High(TAtlasMetric) do
  begin
    if AMethod.Values[mMetric] > ALimits[mMetric] then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Letzter Teil eines Namens mit Punkten (TFoo.Run → Run).</summary>
function LastPart(const AName: string): string;
var
  mDot: Integer;
begin
  Result := AName;
  mDot := LastDelimiter('.', Result);
  if mDot > 0 then
  begin
    Result := Copy(Result, mDot + 1, MaxInt);
  end;
end;

/// <summary>Steht ANeedle ab AStart in AText als ganzer Bezeichner?</summary>
function WholeIdentAt(const AText, ANeedle: string; AStart: Integer): Boolean;
begin
  Result := ((AStart = 1) or not TTextChars.IsIdentChar(AText[AStart - 1])) and
    ((AStart + Length(ANeedle) > Length(AText)) or not TTextChars.IsIdentChar(AText[AStart + Length(ANeedle)]));
end;

class function TAtlasMetricsLens.LineMatches(const ALine, AName: string): Boolean;
var
  mName, mLine: string;
  mStart: Integer;
begin
  Result := False;
  mName := UpperCase(LastPart(AName));
  if mName = '' then
  begin
    Exit;
  end;
  mLine := UpperCase(ALine);
  mStart := Pos(mName, mLine);
  while mStart > 0 do
  begin
    if WholeIdentAt(mLine, mName, mStart) then
    begin
      Exit(True);
    end;
    mStart := Pos(mName, mLine, mStart + 1);
  end;
end;

end.
