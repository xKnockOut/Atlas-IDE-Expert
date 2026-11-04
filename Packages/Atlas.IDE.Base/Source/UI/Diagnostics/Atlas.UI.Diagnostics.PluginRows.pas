unit Atlas.UI.Diagnostics.PluginRows;

// Spalten und Zeilen der Tabellen im Diagnose-Fenster (Reiter Hauptthread,
// Server, Hintergrund, Hänger), ohne Steuerelemente: macht aus den geordneten
// Werten von TAtlasPluginRows die Zellen von TAtlasDiagnosticGrid. Werte ab
// der Schwelle stehen in Warnfarbe, ab dem Zehnfachen in Fehlerfarbe;
// Zeitüberschreitungen und zu langsame Quellen in Warnfarbe, Fehler und
// Hänger in Fehlerfarbe.

interface

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.PluginTimings,
  Atlas.Core.Diagnostics.PluginReport,
  Atlas.UI.Diagnostics.Grid;

type
  TAtlasPluginGridRows = record
  public const
    /// <summary>Ab dem Zehnfachen der Schwelle Fehlerfarbe.</summary>
    cBadFactor = 10;
  public
    class function Mark(AMs: Double; AThresholdMs: Integer): TAtlasGridMark; static;
    class function FeatureColumns: TArray<TAtlasGridColumn>; static;
    class function SlowColumns: TArray<TAtlasGridColumn>; static;
    class function RequestColumns: TArray<TAtlasGridColumn>; static;
    class function SourceColumns: TArray<TAtlasGridColumn>; static;
    class function HangColumns: TArray<TAtlasGridColumn>; static;
    class function Features(const ARows: TArray<TAtlasFeatureRow>; AThresholdMs: Integer): TArray<TAtlasGridRow>;
      static;
    class function Slow(const ACalls: TArray<TAtlasSlowCall>; AThresholdMs: Integer): TArray<TAtlasGridRow>; static;
    class function Requests(const ARequests: TArray<TAtlasRequestTiming>;
      AThresholdMs: Integer): TArray<TAtlasGridRow>; static;
    class function Sources(const ASources: TArray<TAtlasSourceTiming>): TArray<TAtlasGridRow>; static;
    class function Hangs(const AHangs: TArray<TAtlasHangEntry>): TArray<TAtlasGridRow>; static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Strings;

const
  cNoValue = '–';

function Cells(const AValues: array of string): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AValues));
  for mIndex := 0 to High(AValues) do
  begin
    Result[mIndex] := AValues[mIndex];
  end;
end;

function Plain(ACount: Integer): TArray<TAtlasGridMark>;
var
  mIndex: Integer;
begin
  SetLength(Result, ACount);
  for mIndex := 0 to ACount - 1 do
  begin
    Result[mIndex] := TAtlasGridMark.None;
  end;
end;

function Column(AId: TAtlasTextId; AWidth: Integer; ARight: Boolean): TAtlasGridColumn;
begin
  Result := TAtlasGridColumn.Make(TAtlasStrings.Text(AId), AWidth, ARight);
end;

function TextOrDash(const AText: string): string;
begin
  Result := AText;
  if Result = '' then
  begin
    Result := cNoValue;
  end;
end;

function WarnIf(ACondition: Boolean; AMark: TAtlasGridMark): TAtlasGridMark;
begin
  Result := TAtlasGridMark.None;
  if ACondition then
  begin
    Result := AMark;
  end;
end;

{ TAtlasPluginGridRows }

class function TAtlasPluginGridRows.Mark(AMs: Double; AThresholdMs: Integer): TAtlasGridMark;
begin
  Result := TAtlasGridMark.None;
  if AThresholdMs <= 0 then
  begin
    Exit;
  end;
  if AMs >= AThresholdMs * cBadFactor then
  begin
    Result := TAtlasGridMark.Bad;
  end
  else if AMs >= AThresholdMs then
  begin
    Result := TAtlasGridMark.Warn;
  end;
end;

class function TAtlasPluginGridRows.FeatureColumns: TArray<TAtlasGridColumn>;
begin
  Result := TArray<TAtlasGridColumn>.Create(Column(TAtlasTextId.DiagColFeature, 0, False),
    Column(TAtlasTextId.DiagColCalls, 64, True), Column(TAtlasTextId.DiagColTotal, 80, True),
    Column(TAtlasTextId.DiagColMean, 72, True), Column(TAtlasTextId.DiagColMax, 72, True),
    Column(TAtlasTextId.DiagColSlow, 80, True), Column(TAtlasTextId.DiagColShare, 96, True));
end;

class function TAtlasPluginGridRows.SlowColumns: TArray<TAtlasGridColumn>;
begin
  Result := TArray<TAtlasGridColumn>.Create(Column(TAtlasTextId.DiagColFeature, 0, False),
    Column(TAtlasTextId.DiagColTime, 96, False), Column(TAtlasTextId.DiagColAction, 200, False),
    Column(TAtlasTextId.DiagColDuration, 80, True));
end;

class function TAtlasPluginGridRows.RequestColumns: TArray<TAtlasGridColumn>;
begin
  Result := TArray<TAtlasGridColumn>.Create(Column(TAtlasTextId.DiagColRequest, 0, False),
    Column(TAtlasTextId.DiagColCount, 64, True), Column(TAtlasTextId.DiagColMean, 72, True),
    Column(TAtlasTextId.DiagColMax, 72, True), Column(TAtlasTextId.DiagColWaited, 150, True),
    Column(TAtlasTextId.DiagColTimedOut, 120, True), Column(TAtlasTextId.DiagColCancelled, 90, True),
    Column(TAtlasTextId.DiagColFailed, 60, True));
end;

class function TAtlasPluginGridRows.SourceColumns: TArray<TAtlasGridColumn>;
begin
  Result := TArray<TAtlasGridColumn>.Create(Column(TAtlasTextId.DiagColSource, 0, False),
    Column(TAtlasTextId.DiagColCalls, 64, True), Column(TAtlasTextId.DiagColMean, 72, True),
    Column(TAtlasTextId.DiagColMax, 72, True), Column(TAtlasTextId.DiagColTooSlow, 90, True));
end;

class function TAtlasPluginGridRows.HangColumns: TArray<TAtlasGridColumn>;
begin
  Result := TArray<TAtlasGridColumn>.Create(Column(TAtlasTextId.DiagColAction, 0, False),
    Column(TAtlasTextId.DiagColTime, 96, False), Column(TAtlasTextId.DiagColDuration, 80, True),
    Column(TAtlasTextId.DiagColWithAtlas, 110, True));
end;

class function TAtlasPluginGridRows.Features(const ARows: TArray<TAtlasFeatureRow>;
  AThresholdMs: Integer): TArray<TAtlasGridRow>;
var
  mIndex: Integer;
  mRow: TAtlasFeatureRow;
begin
  SetLength(Result, Length(ARows));
  for mIndex := 0 to High(ARows) do
  begin
    mRow := ARows[mIndex];
    Result[mIndex].Cells := Cells([mRow.Name, IntToStr(mRow.Stat.Calls), TAtlasPluginRows.Ms(mRow.Stat.TotalMs),
      TAtlasPluginRows.Ms(mRow.Stat.MeanMs), TAtlasPluginRows.Ms(mRow.Stat.MaxMs), IntToStr(mRow.Stat.SlowCalls),
      TAtlasPluginRows.Percent(mRow.Share * 100)]);
    Result[mIndex].Marks := Plain(7);
    Result[mIndex].Marks[3] := Mark(mRow.Stat.MeanMs, AThresholdMs);
    Result[mIndex].Marks[4] := Mark(mRow.Stat.MaxMs, AThresholdMs);
    Result[mIndex].Marks[5] := WarnIf(mRow.Stat.SlowCalls > 0, TAtlasGridMark.Warn);
    Result[mIndex].Bar := mRow.Share;
  end;
end;

class function TAtlasPluginGridRows.Slow(const ACalls: TArray<TAtlasSlowCall>;
  AThresholdMs: Integer): TArray<TAtlasGridRow>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(ACalls));
  for mIndex := 0 to High(ACalls) do
  begin
    Result[mIndex].Cells := Cells([TAtlasGuard.FeatureName(ACalls[mIndex].Feature),
      TAtlasPluginRows.Clock(ACalls[mIndex].At), TextOrDash(ACalls[mIndex].Activity),
      TAtlasPluginRows.Ms(ACalls[mIndex].Ms)]);
    Result[mIndex].Marks := Plain(4);
    Result[mIndex].Marks[3] := Mark(ACalls[mIndex].Ms, AThresholdMs);
    Result[mIndex].Bar := -1;
  end;
end;

class function TAtlasPluginGridRows.Requests(const ARequests: TArray<TAtlasRequestTiming>;
  AThresholdMs: Integer): TArray<TAtlasGridRow>;
var
  mIndex: Integer;
  mRequest: TAtlasRequestTiming;
begin
  SetLength(Result, Length(ARequests));
  for mIndex := 0 to High(ARequests) do
  begin
    mRequest := ARequests[mIndex];
    Result[mIndex].Cells := Cells([mRequest.Method, IntToStr(mRequest.Stat.Calls),
      TAtlasPluginRows.Ms(mRequest.Stat.MeanMs), TAtlasPluginRows.Ms(mRequest.Stat.MaxMs),
      TAtlasPluginRows.Ms(mRequest.WaitedMs), IntToStr(mRequest.TimedOut), IntToStr(mRequest.Cancelled),
      IntToStr(mRequest.Failed)]);
    Result[mIndex].Marks := Plain(8);
    Result[mIndex].Marks[4] := Mark(mRequest.WaitedMs, AThresholdMs);
    Result[mIndex].Marks[5] := WarnIf(mRequest.TimedOut > 0, TAtlasGridMark.Warn);
    Result[mIndex].Marks[7] := WarnIf(mRequest.Failed > 0, TAtlasGridMark.Bad);
    Result[mIndex].Bar := -1;
  end;
end;

class function TAtlasPluginGridRows.Sources(const ASources: TArray<TAtlasSourceTiming>): TArray<TAtlasGridRow>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(ASources));
  for mIndex := 0 to High(ASources) do
  begin
    Result[mIndex].Cells := Cells([ASources[mIndex].Name, IntToStr(ASources[mIndex].Stat.Calls),
      TAtlasPluginRows.Ms(ASources[mIndex].Stat.MeanMs), TAtlasPluginRows.Ms(ASources[mIndex].Stat.MaxMs),
      IntToStr(ASources[mIndex].Slow)]);
    Result[mIndex].Marks := Plain(5);
    Result[mIndex].Marks[4] := WarnIf(ASources[mIndex].Slow > 0, TAtlasGridMark.Warn);
    Result[mIndex].Bar := -1;
  end;
end;

class function TAtlasPluginGridRows.Hangs(const AHangs: TArray<TAtlasHangEntry>): TArray<TAtlasGridRow>;
var
  mIndex: Integer;
  mWithAtlas: string;
begin
  SetLength(Result, Length(AHangs));
  for mIndex := 0 to High(AHangs) do
  begin
    mWithAtlas := TAtlasStrings.Text(TAtlasTextId.DiagNo);
    if AHangs[mIndex].WithAtlas then
    begin
      mWithAtlas := TAtlasStrings.Text(TAtlasTextId.DiagYes);
    end;
    Result[mIndex].Cells := Cells([TextOrDash(AHangs[mIndex].Activity), TAtlasPluginRows.Clock(AHangs[mIndex].At),
      IntToStr(AHangs[mIndex].DurationMs), mWithAtlas]);
    Result[mIndex].Marks := Plain(4);
    Result[mIndex].Marks[2] := TAtlasGridMark.Bad;
    Result[mIndex].Bar := -1;
  end;
end;

end.
