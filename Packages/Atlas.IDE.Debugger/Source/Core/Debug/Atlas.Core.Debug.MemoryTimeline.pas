unit Atlas.Core.Debug.MemoryTimeline;

// Speicherverlauf beim Debuggen (#858), Kern ohne VCL und ohne Windows:
// - TAtlasMemoryTimeline hält die Messwerte der Sitzung (privater Speicher, Arbeitssatz, Handles, GDI- und
//   USER-Objekte, je mit Zeit seit Sitzungsbeginn) und die Marken (Halt, Exception, eigene Marke mit Namen).
//   Höchstens cMaxSamples Werte; ältere fallen weg, Marken davor ebenso.
// - Growth rechnet den Zuwachs je Wert zwischen zwei Zeitpunkten (gewählter Bereich im Fenster).
// - ToCsv liefert den Verlauf zum Kopieren; Marken stehen bei der ersten Messung danach.
// - TAtlasMemoryChartScale bildet Zeit und Wert auf die Zeichenfläche ab und zurück.
// Gemessen wird in Atlas.IDE.Debug.MemoryTimeline, gezeichnet in Atlas.UI.Debug.MemoryFrame.

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  {$SCOPEDENUMS ON}
  TAtlasMemorySeries = (PrivateBytes, WorkingSet, Handles, GdiObjects, UserObjects);
  TAtlasMemoryMarkKind = (Stop, Exception, Custom);
  {$SCOPEDENUMS OFF}

  TAtlasMemoryValues = array[TAtlasMemorySeries] of Int64;

  TAtlasMemorySample = record
    /// <summary>Millisekunden seit Beginn der Sitzung.</summary>
    AtMs: Int64;
    Values: TAtlasMemoryValues;
  end;

  TAtlasMemoryMark = record
    AtMs: Int64;
    Kind: TAtlasMemoryMarkKind;
    Name: string;
  end;

  TAtlasMemoryGrowth = record
    /// <summary>False, wenn im Bereich weniger als zwei Messungen liegen.</summary>
    Valid: Boolean;
    FromMs: Int64;
    ToMs: Int64;
    Deltas: TAtlasMemoryValues;
    function DurationMs: Int64;
  end;

  TAtlasMemoryTimeline = class
  public const
    /// <summary>Einen Tag lang je Sekunde.</summary>
    cMaxSamples = 86400;
  private
    FSamples: TList<TAtlasMemorySample>;
    FMarks: TList<TAtlasMemoryMark>;
    FMaxSamples: Integer;
    function GetCount: Integer;
    function GetSample(AIndex: Integer): TAtlasMemorySample;
    function GetMarkCount: Integer;
    function GetMark(AIndex: Integer): TAtlasMemoryMark;
    procedure DropOldest;
    /// <summary>Index der ersten Messung ab AAtMs; Count, wenn keine.</summary>
    function FirstAtOrAfter(AAtMs: Int64): Integer;
    /// <summary>Index der letzten Messung bis AAtMs; -1, wenn keine.</summary>
    function LastAtOrBefore(AAtMs: Int64): Integer;
    function MarksText(AFromMs, AToMs: Int64): string;
  public
    constructor Create; overload;
    constructor Create(AMaxSamples: Integer); overload;
    destructor Destroy; override;
    procedure Clear;
    procedure AddSample(const ASample: TAtlasMemorySample);
    procedure AddMark(AAtMs: Int64; AKind: TAtlasMemoryMarkKind; const AName: string);
    /// <summary>Zuwachs zwischen der ersten Messung ab AFromMs und der letzten bis AToMs (Reihenfolge egal).
    /// </summary>
    function Growth(AFromMs, AToMs: Int64): TAtlasMemoryGrowth;
    /// <summary>Größter Wert der Reihe; 0 ohne Messung.</summary>
    function MaxOf(ASeries: TAtlasMemorySeries): Int64;
    /// <summary>Verlauf als CSV (Komma, Punkt als Dezimaltrenner) mit Kopfzeile.</summary>
    function ToCsv: string;
    property Count: Integer read GetCount;
    property Samples[AIndex: Integer]: TAtlasMemorySample read GetSample; default;
    property MarkCount: Integer read GetMarkCount;
    property Marks[AIndex: Integer]: TAtlasMemoryMark read GetMark;
  end;

  TAtlasMemoryFormat = record
  public
    /// <summary>Bytes als B, KB, MB oder GB mit einer Nachkommastelle ab KB.</summary>
    class function Bytes(AValue: Int64; const AFormat: TFormatSettings): string; static;
    /// <summary>Wert der Reihe: Speicher als Bytes, sonst als Zahl.</summary>
    class function Value(ASeries: TAtlasMemorySeries; AValue: Int64; const AFormat: TFormatSettings): string;
      static;
    /// <summary>Wie Value, mit Vorzeichen („+38,0 MB“, „-3“, „+0“).</summary>
    class function Signed(ASeries: TAtlasMemorySeries; AValue: Int64; const AFormat: TFormatSettings): string;
      static;
    class function IsBytes(ASeries: TAtlasMemorySeries): Boolean; static;
  end;

  /// <summary>Abbildung zwischen Zeit bzw. Wert und Pixeln der Zeichenfläche.</summary>
  TAtlasMemoryChartScale = record
    FromMs: Int64;
    ToMs: Int64;
    MaxValue: Int64;
    Width: Integer;
    Height: Integer;
    class function Make(AFromMs, AToMs, AMaxValue: Int64; AWidth, AHeight: Integer): TAtlasMemoryChartScale; static;
    /// <summary>Glatte Obergrenze über AValue (1, 2 oder 5 mal Zehnerpotenz bzw. Bytes in 1-2-5-Schritten).
    /// </summary>
    class function NiceMax(AValue: Int64): Int64; static;
    function XOf(AAtMs: Int64): Integer;
    function YOf(AValue: Int64): Integer;
    function AtOf(AX: Integer): Int64;
  end;

implementation

uses
  System.Math;

{ TAtlasMemoryGrowth }

function TAtlasMemoryGrowth.DurationMs: Int64;
begin
  Result := ToMs - FromMs;
end;

{ TAtlasMemoryTimeline }

constructor TAtlasMemoryTimeline.Create;
begin
  Create(cMaxSamples);
end;

constructor TAtlasMemoryTimeline.Create(AMaxSamples: Integer);
begin
  inherited Create;
  FMaxSamples := Max(AMaxSamples, 2);
  FSamples := TList<TAtlasMemorySample>.Create;
  FMarks := TList<TAtlasMemoryMark>.Create;
end;

destructor TAtlasMemoryTimeline.Destroy;
begin
  FMarks.Free;
  FSamples.Free;
  inherited;
end;

procedure TAtlasMemoryTimeline.Clear;
begin
  FSamples.Clear;
  FMarks.Clear;
end;

function TAtlasMemoryTimeline.GetCount: Integer;
begin
  Result := FSamples.Count;
end;

function TAtlasMemoryTimeline.GetSample(AIndex: Integer): TAtlasMemorySample;
begin
  Result := FSamples[AIndex];
end;

function TAtlasMemoryTimeline.GetMarkCount: Integer;
begin
  Result := FMarks.Count;
end;

function TAtlasMemoryTimeline.GetMark(AIndex: Integer): TAtlasMemoryMark;
begin
  Result := FMarks[AIndex];
end;

procedure TAtlasMemoryTimeline.DropOldest;
var
  mDrop: Integer;
begin
  mDrop := FSamples.Count - FMaxSamples;
  if mDrop <= 0 then
  begin
    Exit;
  end;
  FSamples.DeleteRange(0, mDrop);
  while (FMarks.Count > 0) and (FMarks[0].AtMs < FSamples[0].AtMs) do
  begin
    FMarks.Delete(0);
  end;
end;

procedure TAtlasMemoryTimeline.AddSample(const ASample: TAtlasMemorySample);
begin
  FSamples.Add(ASample);
  DropOldest;
end;

procedure TAtlasMemoryTimeline.AddMark(AAtMs: Int64; AKind: TAtlasMemoryMarkKind; const AName: string);
var
  mMark: TAtlasMemoryMark;
begin
  mMark.AtMs := AAtMs;
  mMark.Kind := AKind;
  mMark.Name := AName;
  FMarks.Add(mMark);
end;

function TAtlasMemoryTimeline.FirstAtOrAfter(AAtMs: Int64): Integer;
begin
  Result := 0;
  while (Result < FSamples.Count) and (FSamples[Result].AtMs < AAtMs) do
  begin
    Inc(Result);
  end;
end;

function TAtlasMemoryTimeline.LastAtOrBefore(AAtMs: Int64): Integer;
begin
  Result := FSamples.Count - 1;
  while (Result >= 0) and (FSamples[Result].AtMs > AAtMs) do
  begin
    Dec(Result);
  end;
end;

function TAtlasMemoryTimeline.Growth(AFromMs, AToMs: Int64): TAtlasMemoryGrowth;
var
  mFirst, mLast: Integer;
  mSeries: TAtlasMemorySeries;
begin
  Result := Default(TAtlasMemoryGrowth);
  mFirst := FirstAtOrAfter(Min(AFromMs, AToMs));
  mLast := LastAtOrBefore(Max(AFromMs, AToMs));
  if mLast <= mFirst then
  begin
    Exit;
  end;
  Result.Valid := True;
  Result.FromMs := FSamples[mFirst].AtMs;
  Result.ToMs := FSamples[mLast].AtMs;
  for mSeries := Low(TAtlasMemorySeries) to High(TAtlasMemorySeries) do
  begin
    Result.Deltas[mSeries] := FSamples[mLast].Values[mSeries] - FSamples[mFirst].Values[mSeries];
  end;
end;

function TAtlasMemoryTimeline.MaxOf(ASeries: TAtlasMemorySeries): Int64;
var
  mSample: TAtlasMemorySample;
begin
  Result := 0;
  for mSample in FSamples do
  begin
    Result := Max(Result, mSample.Values[ASeries]);
  end;
end;

function TAtlasMemoryTimeline.MarksText(AFromMs, AToMs: Int64): string;
var
  mMark: TAtlasMemoryMark;
begin
  Result := '';
  for mMark in FMarks do
  begin
    if (mMark.AtMs > AFromMs) and (mMark.AtMs <= AToMs) then
    begin
      if Result <> '' then
      begin
        Result := Result + ' / ';
      end;
      Result := Result + mMark.Name;
    end;
  end;
end;

function CsvText(const AText: string): string;
begin
  Result := AText;
  if (Pos(',', AText) > 0) or (Pos('"', AText) > 0) then
  begin
    Result := '"' + AText.Replace('"', '""') + '"';
  end;
end;

function TAtlasMemoryTimeline.ToCsv: string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
  mPrevious: Int64;
  mSample: TAtlasMemorySample;
  mSeries: TAtlasMemorySeries;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('seconds,private_bytes,working_set,handles,gdi_objects,user_objects,marks').Append(sLineBreak);
    mPrevious := Low(Int64);
    for mIndex := 0 to FSamples.Count - 1 do
    begin
      mSample := FSamples[mIndex];
      mBuilder.Append(FormatFloat('0.000', mSample.AtMs / 1000, TFormatSettings.Invariant));
      for mSeries := Low(TAtlasMemorySeries) to High(TAtlasMemorySeries) do
      begin
        mBuilder.Append(',').Append(IntToStr(mSample.Values[mSeries]));
      end;
      mBuilder.Append(',').Append(CsvText(MarksText(mPrevious, mSample.AtMs))).Append(sLineBreak);
      mPrevious := mSample.AtMs;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

{ TAtlasMemoryFormat }

class function TAtlasMemoryFormat.IsBytes(ASeries: TAtlasMemorySeries): Boolean;
begin
  Result := ASeries in [TAtlasMemorySeries.PrivateBytes, TAtlasMemorySeries.WorkingSet];
end;

class function TAtlasMemoryFormat.Bytes(AValue: Int64; const AFormat: TFormatSettings): string;
const
  cUnits: array[0..3] of string = ('B', 'KB', 'MB', 'GB');
  cStep = 1024;
var
  mValue: Double;
  mUnit: Integer;
begin
  mValue := Abs(AValue);
  mUnit := 0;
  while (mValue >= cStep) and (mUnit < High(cUnits)) do
  begin
    mValue := mValue / cStep;
    Inc(mUnit);
  end;
  if AValue < 0 then
  begin
    mValue := -mValue;
  end;
  if mUnit = 0 then
  begin
    Exit(IntToStr(AValue) + ' ' + cUnits[0]);
  end;
  Result := FormatFloat('0.0', mValue, AFormat) + ' ' + cUnits[mUnit];
end;

class function TAtlasMemoryFormat.Value(ASeries: TAtlasMemorySeries; AValue: Int64;
  const AFormat: TFormatSettings): string;
begin
  if IsBytes(ASeries) then
  begin
    Exit(Bytes(AValue, AFormat));
  end;
  Result := IntToStr(AValue);
end;

class function TAtlasMemoryFormat.Signed(ASeries: TAtlasMemorySeries; AValue: Int64;
  const AFormat: TFormatSettings): string;
begin
  Result := Value(ASeries, AValue, AFormat);
  if AValue >= 0 then
  begin
    Result := '+' + Result;
  end;
end;

{ TAtlasMemoryChartScale }

class function TAtlasMemoryChartScale.Make(AFromMs, AToMs, AMaxValue: Int64; AWidth,
  AHeight: Integer): TAtlasMemoryChartScale;
begin
  Result.FromMs := AFromMs;
  Result.ToMs := Max(AToMs, AFromMs + 1);
  Result.MaxValue := Max(AMaxValue, 1);
  Result.Width := Max(AWidth, 1);
  Result.Height := Max(AHeight, 1);
end;

class function TAtlasMemoryChartScale.NiceMax(AValue: Int64): Int64;
const
  cSteps: array[0..2] of Int64 = (1, 2, 5);
var
  mPower: Int64;
  mStep: Int64;
begin
  mPower := 1;
  while True do
  begin
    for mStep in cSteps do
    begin
      if mStep * mPower >= AValue then
      begin
        Exit(mStep * mPower);
      end;
    end;
    mPower := mPower * 10;
  end;
end;

function TAtlasMemoryChartScale.XOf(AAtMs: Int64): Integer;
begin
  Result := Round((AAtMs - FromMs) / (ToMs - FromMs) * (Width - 1));
end;

function TAtlasMemoryChartScale.YOf(AValue: Int64): Integer;
begin
  Result := (Height - 1) - Round(EnsureRange(AValue, 0, MaxValue) / MaxValue * (Height - 1));
end;

function TAtlasMemoryChartScale.AtOf(AX: Integer): Int64;
begin
  Result := FromMs + Round(EnsureRange(AX, 0, Width - 1) / Max(Width - 1, 1) * (ToMs - FromMs));
end;

end.
