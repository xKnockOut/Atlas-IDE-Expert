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
  Atlas.UI.Diagnostics.Strings;

type
  /// <summary>Spalte einer Tabelle: Überschrift, Breite vor dem Skalieren (0: Rest der Breite), rechtsbündig.</summary>
  TColumnSpec = record
    Id: TAtlasDiagnosticsTextId;
    Width: Integer;
    Right: Boolean;
  end;

const
  /// <summary>Spalten des Reiters „Hauptthread“: Funktion, Aufrufe, Summe, Mittel, Maximum, langsam, Anteil.</summary>
  cFeatureColumns: array[0..6] of TColumnSpec = (
    (Id: TAtlasDiagnosticsTextId.DiagColFeature; Width: 0; Right: False),
    (Id: TAtlasDiagnosticsTextId.DiagColCalls; Width: 64; Right: True),
    (Id: TAtlasDiagnosticsTextId.DiagColTotal; Width: 80; Right: True),
    (Id: TAtlasDiagnosticsTextId.DiagColMean; Width: 72; Right: True),
    (Id: TAtlasDiagnosticsTextId.DiagColMax; Width: 72; Right: True),
    (Id: TAtlasDiagnosticsTextId.DiagColSlow; Width: 80; Right: True),
    (Id: TAtlasDiagnosticsTextId.DiagColShare; Width: 96; Right: True));
  /// <summary>Spalten der langsamen Aufrufe: Funktion, Zeit, Aktion, Dauer.</summary>
  cSlowColumns: array[0..3] of TColumnSpec = (
    (Id: TAtlasDiagnosticsTextId.DiagColFeature; Width: 0; Right: False),
    (Id: TAtlasDiagnosticsTextId.DiagColTime; Width: 96; Right: False),
    (Id: TAtlasDiagnosticsTextId.DiagColAction; Width: 200; Right: False),
    (Id: TAtlasDiagnosticsTextId.DiagColDuration; Width: 80; Right: True));
  /// <summary>Spalten des Reiters „Hintergrund“: Quelle, Aufrufe, Mittel, Maximum, zu langsam.</summary>
  cSourceColumns: array[0..4] of TColumnSpec = (
    (Id: TAtlasDiagnosticsTextId.DiagColSource; Width: 0; Right: False),
    (Id: TAtlasDiagnosticsTextId.DiagColCalls; Width: 64; Right: True),
    (Id: TAtlasDiagnosticsTextId.DiagColMean; Width: 72; Right: True),
    (Id: TAtlasDiagnosticsTextId.DiagColMax; Width: 72; Right: True),
    (Id: TAtlasDiagnosticsTextId.DiagColTooSlow; Width: 90; Right: True));
  /// <summary>Spalten des Reiters „Hänger“: Aktion, Zeit, Dauer, mit Atlas.</summary>
  cHangColumns: array[0..3] of TColumnSpec = (
    (Id: TAtlasDiagnosticsTextId.DiagColAction; Width: 0; Right: False),
    (Id: TAtlasDiagnosticsTextId.DiagColTime; Width: 96; Right: False),
    (Id: TAtlasDiagnosticsTextId.DiagColDuration; Width: 80; Right: True),
    (Id: TAtlasDiagnosticsTextId.DiagColWithAtlas; Width: 110; Right: True));

  cNoValue = '–';
  /// <summary>Spalten des Reiters „Server“: Anfrage, Anzahl, Mittel, Maximum, wartend, Hauptthread Ø,
  /// Zeitüberschreitung, abgebrochen, gescheitert.</summary>
  cRequestColumnIds: array[0..8] of TAtlasDiagnosticsTextId = (TAtlasDiagnosticsTextId.DiagColRequest,
    TAtlasDiagnosticsTextId.DiagColCount, TAtlasDiagnosticsTextId.DiagColMean, TAtlasDiagnosticsTextId.DiagColMax,
    TAtlasDiagnosticsTextId.DiagColWaitedCount, TAtlasDiagnosticsTextId.DiagColWaited,
    TAtlasDiagnosticsTextId.DiagColTimedOut, TAtlasDiagnosticsTextId.DiagColCancelled,
    TAtlasDiagnosticsTextId.DiagColFailed);
  /// <summary>Breiten dazu (vor dem Skalieren); 0: Rest der Breite.</summary>
  cRequestColumnWidths: array[0..8] of Integer = (0, 64, 72, 72, 110, 130, 120, 90, 60);
  cWaitedMeanColumn = 5;
  cTimedOutColumn = 6;
  cFailedColumn = 8;

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

function Column(AId: TAtlasDiagnosticsTextId; AWidth: Integer; ARight: Boolean): TAtlasGridColumn;
begin
  Result := TAtlasGridColumn.Make(TAtlasDiagnosticsStrings.Text(AId), AWidth, ARight);
end;

function Columns(const ASpecs: array of TColumnSpec): TArray<TAtlasGridColumn>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(ASpecs));
  for mIndex := 0 to High(ASpecs) do
  begin
    Result[mIndex] := Column(ASpecs[mIndex].Id, ASpecs[mIndex].Width, ASpecs[mIndex].Right);
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
  Result := Columns(cFeatureColumns);
end;

class function TAtlasPluginGridRows.SlowColumns: TArray<TAtlasGridColumn>;
begin
  Result := Columns(cSlowColumns);
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
  Result := Columns(cSourceColumns);
end;

class function TAtlasPluginGridRows.HangColumns: TArray<TAtlasGridColumn>;
begin
  Result := Columns(cHangColumns);
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
    mWithAtlas := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagNo);
    if AHangs[mIndex].WithAtlas then
    begin
      mWithAtlas := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagYes);
    end;
    Result[mIndex].Cells := Cells([TextOrDash(AHangs[mIndex].Activity), TAtlasPluginRows.Clock(AHangs[mIndex].At),
      IntToStr(AHangs[mIndex].DurationMs), mWithAtlas]);
    Result[mIndex].Marks := Plain(4);
    Result[mIndex].Marks[2] := TAtlasGridMark.Bad;
    Result[mIndex].Bar := -1;
  end;
end;

end.
