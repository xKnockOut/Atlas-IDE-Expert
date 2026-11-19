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
  Atlas.UI.Strings,
  Atlas.UI.Diagnostics.Strings;

const
  cNoValue = '–';
  /// <summary>Spalten des Reiters „Server“: Anfrage, Anzahl, Mittel, Maximum, wartend, Hauptthread Ø,
  /// Zeitüberschreitung, abgebrochen, gescheitert.</summary>
  cRequestColumnIds: array[0..8] of TAtlasTextId = (TAtlasTextId.DiagColRequest, TAtlasTextId.DiagColCount,
    TAtlasTextId.DiagColMean, TAtlasTextId.DiagColMax, TAtlasTextId.DiagColWaitedCount, TAtlasTextId.DiagColWaited,
    TAtlasTextId.DiagColTimedOut, TAtlasTextId.DiagColCancelled, TAtlasTextId.DiagColFailed);
  /// <summary>Breiten dazu (vor dem Skalieren); 0: Rest der Breite.</summary>
  cRequestColumnWidths: array[0..8] of Integer = (0, 64, 72, 72, 110, 130, 120, 90, 60);
  cWaitedMeanColumn = 5;
  cTimedOutColumn = 6;
  cFailedColumn = 8;
  /// <summary>Reiter „Funktionen“: Funktion, Aufrufe, Summe, Mittel, Maximum, langsam, Anteil.</summary>
  cFeatureColumnIds: array[0..6] of TAtlasTextId = (TAtlasTextId.DiagColFeature, TAtlasTextId.DiagColCalls,
    TAtlasTextId.DiagColTotal, TAtlasTextId.DiagColMean, TAtlasTextId.DiagColMax, TAtlasTextId.DiagColSlow,
    TAtlasTextId.DiagColShare);
  cFeatureColumnWidths: array[0..6] of Integer = (0, 64, 80, 72, 72, 80, 96);
  cFeatureColumnRight: array[0..6] of Boolean = (False, True, True, True, True, True, True);
  cFeatureMeanColumn = 3;
  cFeatureMaxColumn = 4;
  cFeatureSlowColumn = 5;
  /// <summary>Langsame Aufrufe: Funktion, Zeit, Aktion, Dauer.</summary>
  cSlowColumnIds: array[0..3] of TAtlasTextId = (TAtlasTextId.DiagColFeature, TAtlasTextId.DiagColTime,
    TAtlasTextId.DiagColAction, TAtlasTextId.DiagColDuration);
  cSlowColumnWidths: array[0..3] of Integer = (0, 96, 200, 80);
  cSlowColumnRight: array[0..3] of Boolean = (False, False, False, True);
  cSlowDurationColumn = 3;
  /// <summary>Quellen: Quelle, Aufrufe, Mittel, Maximum, zu langsam.</summary>
  cSourceColumnIds: array[0..4] of TAtlasTextId = (TAtlasTextId.DiagColSource, TAtlasTextId.DiagColCalls,
    TAtlasTextId.DiagColMean, TAtlasTextId.DiagColMax, TAtlasTextId.DiagColTooSlow);
  cSourceColumnWidths: array[0..4] of Integer = (0, 64, 72, 72, 90);
  cSourceColumnRight: array[0..4] of Boolean = (False, True, True, True, True);
  cSourceTooSlowColumn = 4;
  /// <summary>Hänger: Aktion, Zeit, Dauer, mit Atlas.</summary>
  cHangColumnIds: array[0..3] of TAtlasTextId = (TAtlasTextId.DiagColAction, TAtlasTextId.DiagColTime,
    TAtlasTextId.DiagColDuration, TAtlasTextId.DiagColWithAtlas);
  cHangColumnWidths: array[0..3] of Integer = (0, 96, 80, 110);
  cHangColumnRight: array[0..3] of Boolean = (False, False, True, True);
  cHangDurationColumn = 2;

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

/// <summary>Spalten aus gleich langen Listen von Überschrift, Breite und Ausrichtung.</summary>
function Columns(const AIds: array of TAtlasTextId; const AWidths: array of Integer;
  const ARight: array of Boolean): TArray<TAtlasGridColumn>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AIds));
  for mIndex := 0 to High(AIds) do
  begin
    Result[mIndex] := Column(AIds[mIndex], AWidths[mIndex], ARight[mIndex]);
  end;
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
  Result := Columns(cFeatureColumnIds, cFeatureColumnWidths, cFeatureColumnRight);
end;

class function TAtlasPluginGridRows.SlowColumns: TArray<TAtlasGridColumn>;
begin
  Result := Columns(cSlowColumnIds, cSlowColumnWidths, cSlowColumnRight);
end;

class function TAtlasPluginGridRows.RequestColumns: TArray<TAtlasGridColumn>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(cRequestColumnIds));
  for mIndex := 0 to High(cRequestColumnIds) do
  begin
    // Die Anfrage links, alle Zahlen rechtsbündig.
    Result[mIndex] := Column(cRequestColumnIds[mIndex], cRequestColumnWidths[mIndex], mIndex > 0);
  end;
end;

class function TAtlasPluginGridRows.SourceColumns: TArray<TAtlasGridColumn>;
begin
  Result := Columns(cSourceColumnIds, cSourceColumnWidths, cSourceColumnRight);
end;

class function TAtlasPluginGridRows.HangColumns: TArray<TAtlasGridColumn>;
begin
  Result := Columns(cHangColumnIds, cHangColumnWidths, cHangColumnRight);
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
    Result[mIndex].Marks := Plain(Length(cFeatureColumnIds));
    Result[mIndex].Marks[cFeatureMeanColumn] := Mark(mRow.Stat.MeanMs, AThresholdMs);
    Result[mIndex].Marks[cFeatureMaxColumn] := Mark(mRow.Stat.MaxMs, AThresholdMs);
    Result[mIndex].Marks[cFeatureSlowColumn] := WarnIf(mRow.Stat.SlowCalls > 0, TAtlasGridMark.Warn);
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
    Result[mIndex].Marks := Plain(Length(cSlowColumnIds));
    Result[mIndex].Marks[cSlowDurationColumn] := Mark(ACalls[mIndex].Ms, AThresholdMs);
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
      IntToStr(mRequest.WaitedCalls), TAtlasPluginRows.Ms(mRequest.WaitedMeanMs), IntToStr(mRequest.TimedOut),
      IntToStr(mRequest.Cancelled), IntToStr(mRequest.Failed)]);
    Result[mIndex].Marks := Plain(Length(cRequestColumnIds));
    // Mittel je wartender Anfrage gegen die Schwelle; die Summe stand früher hier und war fast immer rot.
    Result[mIndex].Marks[cWaitedMeanColumn] := Mark(mRequest.WaitedMeanMs, AThresholdMs);
    Result[mIndex].Marks[cTimedOutColumn] := WarnIf(mRequest.TimedOut > 0, TAtlasGridMark.Warn);
    Result[mIndex].Marks[cFailedColumn] := WarnIf(mRequest.Failed > 0, TAtlasGridMark.Bad);
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
    Result[mIndex].Marks := Plain(Length(cSourceColumnIds));
    Result[mIndex].Marks[cSourceTooSlowColumn] := WarnIf(ASources[mIndex].Slow > 0, TAtlasGridMark.Warn);
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
    mWithAtlas := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagNo);
    if AHangs[mIndex].WithAtlas then
    begin
      mWithAtlas := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagYes);
    end;
    Result[mIndex].Cells := Cells([TextOrDash(AHangs[mIndex].Activity), TAtlasPluginRows.Clock(AHangs[mIndex].At),
      IntToStr(AHangs[mIndex].DurationMs), mWithAtlas]);
    Result[mIndex].Marks := Plain(Length(cHangColumnIds));
    Result[mIndex].Marks[cHangDurationColumn] := TAtlasGridMark.Bad;
    Result[mIndex].Bar := -1;
  end;
end;

end.
