unit Atlas.Core.Diagnostics.PluginReport;

// Zeilen und Bericht der Plugin-Zeiten (Diagnose-Fenster, Variante A), ohne
// VCL: ordnet den Stand von TAtlasPluginTimings für die Reiter „Hauptthread“,
// „Server“, „Hintergrund“ und „Hänger“ und baut den Abschnitt für „Bericht
// kopieren“ und die letzten Diagnosedaten. Der Bericht enthält nur Namen von
// Funktionen, Aktionen, Anfragen und Quellen, Zeiten und Anzahlen.
// Reihenfolgen sind eindeutig (TArray.Sort ist nicht stabil): bei Gleichstand
// nach Namen.

interface

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.PluginTimings;

type
  TAtlasFeatureRow = record
    Feature: TAtlasFeature;
    Name: string;
    Stat: TAtlasCallStat;
    /// <summary>Anteil an der eigenen Zeit aller Funktionen, 0 bis 1.</summary>
    Share: Double;
  end;

  TAtlasPluginRows = record
  public const
    /// <summary>So viele langsame Aufrufe nennt der Bericht.</summary>
    cReportSlowCalls = 50;
  public
    /// <summary>Funktionen nach eigener Zeit, größte zuerst.</summary>
    class function Features(const ASnapshot: TAtlasPluginSnapshot): TArray<TAtlasFeatureRow>; static;
    /// <summary>Langsame Aufrufe, neueste zuerst; mit AOnly nur die der Funktion AFeature.</summary>
    class function Slow(const ASnapshot: TAtlasPluginSnapshot; AOnly: Boolean;
      AFeature: TAtlasFeature): TArray<TAtlasSlowCall>; static;
    /// <summary>Anfragen nach Wartezeit des Hauptthreads, dann nach Summe, größte zuerst.</summary>
    class function Requests(const ASnapshot: TAtlasPluginSnapshot): TArray<TAtlasRequestTiming>; static;
    /// <summary>Quellen nach Summe, größte zuerst.</summary>
    class function Sources(const ASnapshot: TAtlasPluginSnapshot): TArray<TAtlasSourceTiming>; static;
    /// <summary>Hänger, neueste zuerst.</summary>
    class function Hangs(const ASnapshot: TAtlasPluginSnapshot): TArray<TAtlasHangEntry>; static;
    /// <summary>"3.2"; ab 100 ohne Nachkommastelle.</summary>
    class function Ms(AValue: Double): string; static;
    /// <summary>"38" bzw. "7.4" unter 10.</summary>
    class function Percent(AValue: Double): string; static;
    /// <summary>Uhrzeit mit Millisekunden.</summary>
    class function Clock(AValue: TDateTime): string; static;
  end;

  TAtlasPluginReport = record
  public
    /// <summary>Abschnitt „Plugin-Zeiten“ als Markdown, ohne Quelltext und Dateinamen.</summary>
    class function Build(const ASnapshot: TAtlasPluginSnapshot): string; static;
  end;

implementation

uses
  System.Classes,
  System.Math,
  System.Generics.Defaults,
  System.Generics.Collections,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TPluginReportText = (MainThreadPerFeatureOwn, FeatureCallsTotalMeanMaximum, NoCallMeasuredYet,
    SlowCallsNewestFirstAt, None, ServerRequestsMs, RequestCountMeanMaximumMain, BackgroundSourcesMs,
    SourceCallsMeanMaximumToo, HangsFreezeWatchdogNewestFirst, MsAtlasInvolved, PluginTimings,
    MeasuringSinceSlowFromMs);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TPluginReportText] of string = (
    ('### Hauptthread je Funktion (eigene Zeit in ms)',
     'Funktion | Aufrufe | Summe | Mittel | Maximum | ab Schwelle | Anteil %',
     'Noch kein Aufruf gemessen.',
     '### Langsame Aufrufe, neueste zuerst (höchstens %d)',
     'Keiner.',
     '### Server-Anfragen (ms)',
     'Anfrage | Anzahl | Mittel | Maximum | im Hauptthread | Hauptthread Ø | Zeitüberschreitung | abgebrochen | Fehler',
     '### Quellen im Hintergrund (ms)',
     'Quelle | Aufrufe | Mittel | Maximum | zu langsam',
     '### Hänger (Einfrier-Wächter), neueste zuerst',
     '- %s: %d ms, %s, Atlas beteiligt: %s',
     '## Plugin-Zeiten',
     'Messung seit %s, langsam ab %d ms eigener Zeit, Hauptthread durch Atlas belegt: %s %% (Mittel der letzten %d s).'),
    ('### Main thread per feature (own time in ms)',
     'Feature | calls | total | mean | maximum | above threshold | share %',
     'No call measured yet.',
     '### Slow calls, newest first (at most %d)',
     'None.',
     '### Server requests (ms)',
     'Request | count | mean | maximum | on main thread | main thread mean | timeout | cancelled | errors',
     '### Background sources (ms)',
     'Source | calls | mean | maximum | too slow',
     '### Hangs (freeze watchdog), newest first',
     '- %s: %d ms, %s, Atlas involved: %s',
     '## Plugin timings',
     'Measuring since %s, slow from %d ms own time, main thread used by Atlas: %s %% (mean of the last %d s).'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TPluginReportText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

const
  cNoValue = '–';

function Invariant: TFormatSettings;
begin
  Result := FormatSettings;
  Result.DecimalSeparator := '.';
  Result.ThousandSeparator := ',';
end;

function CompareDescending(ALeft, ARight: Double): Integer;
begin
  Result := CompareValue(ARight, ALeft);
end;

{ TAtlasPluginRows }

class function TAtlasPluginRows.Features(const ASnapshot: TAtlasPluginSnapshot): TArray<TAtlasFeatureRow>;
var
  mIndex: Integer;
  mTotal: Double;
begin
  SetLength(Result, Length(ASnapshot.Features));
  mTotal := 0;
  for mIndex := 0 to High(ASnapshot.Features) do
  begin
    Result[mIndex].Feature := ASnapshot.Features[mIndex].Feature;
    Result[mIndex].Name := TAtlasGuard.FeatureName(Result[mIndex].Feature);
    Result[mIndex].Stat := ASnapshot.Features[mIndex].Stat;
    mTotal := mTotal + Result[mIndex].Stat.TotalMs;
  end;
  for mIndex := 0 to High(Result) do
  begin
    Result[mIndex].Share := 0;
    if mTotal > 0 then
    begin
      Result[mIndex].Share := Result[mIndex].Stat.TotalMs / mTotal;
    end;
  end;
  TArray.Sort<TAtlasFeatureRow>(Result, TComparer<TAtlasFeatureRow>.Construct(
    function(const ALeft, ARight: TAtlasFeatureRow): Integer
    begin
      Result := CompareDescending(ALeft.Stat.TotalMs, ARight.Stat.TotalMs);
      if Result = 0 then
      begin
        Result := CompareText(ALeft.Name, ARight.Name);
      end;
    end));
end;

class function TAtlasPluginRows.Slow(const ASnapshot: TAtlasPluginSnapshot; AOnly: Boolean;
  AFeature: TAtlasFeature): TArray<TAtlasSlowCall>;
var
  mIndex, mCount: Integer;
begin
  SetLength(Result, Length(ASnapshot.Slow));
  mCount := 0;
  for mIndex := High(ASnapshot.Slow) downto 0 do
  begin
    if AOnly and (ASnapshot.Slow[mIndex].Feature <> AFeature) then
    begin
      Continue;
    end;
    Result[mCount] := ASnapshot.Slow[mIndex];
    Inc(mCount);
  end;
  SetLength(Result, mCount);
end;

class function TAtlasPluginRows.Requests(const ASnapshot: TAtlasPluginSnapshot): TArray<TAtlasRequestTiming>;
begin
  Result := Copy(ASnapshot.Requests);
  TArray.Sort<TAtlasRequestTiming>(Result, TComparer<TAtlasRequestTiming>.Construct(
    function(const ALeft, ARight: TAtlasRequestTiming): Integer
    begin
      Result := CompareDescending(ALeft.WaitedMs, ARight.WaitedMs);
      if Result = 0 then
      begin
        Result := CompareDescending(ALeft.Stat.TotalMs, ARight.Stat.TotalMs);
      end;
      if Result = 0 then
      begin
        Result := CompareStr(ALeft.Method, ARight.Method);
      end;
    end));
end;

class function TAtlasPluginRows.Sources(const ASnapshot: TAtlasPluginSnapshot): TArray<TAtlasSourceTiming>;
begin
  Result := Copy(ASnapshot.Sources);
  TArray.Sort<TAtlasSourceTiming>(Result, TComparer<TAtlasSourceTiming>.Construct(
    function(const ALeft, ARight: TAtlasSourceTiming): Integer
    begin
      Result := CompareDescending(ALeft.Stat.TotalMs, ARight.Stat.TotalMs);
      if Result = 0 then
      begin
        Result := CompareText(ALeft.Name, ARight.Name);
      end;
    end));
end;

class function TAtlasPluginRows.Hangs(const ASnapshot: TAtlasPluginSnapshot): TArray<TAtlasHangEntry>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(ASnapshot.Hangs));
  for mIndex := 0 to High(ASnapshot.Hangs) do
  begin
    Result[mIndex] := ASnapshot.Hangs[High(ASnapshot.Hangs) - mIndex];
  end;
end;

class function TAtlasPluginRows.Ms(AValue: Double): string;
begin
  if AValue < 0 then
  begin
    Exit(cNoValue);
  end;
  if AValue >= 100 then
  begin
    Exit(FormatFloat('#,##0', AValue, Invariant));
  end;
  Result := FormatFloat('0.0', AValue, Invariant);
end;

class function TAtlasPluginRows.Percent(AValue: Double): string;
begin
  if AValue < 10 then
  begin
    Exit(FormatFloat('0.0', AValue, Invariant));
  end;
  Result := FormatFloat('0', AValue, Invariant);
end;

class function TAtlasPluginRows.Clock(AValue: TDateTime): string;
begin
  Result := FormatDateTime('hh":"nn":"ss"."zzz', AValue);
end;

{ TAtlasPluginReport }

procedure AddFeatures(ALines: TStrings; const ASnapshot: TAtlasPluginSnapshot);
var
  mRow: TAtlasFeatureRow;
begin
  ALines.Add(UiText(TPluginReportText.MainThreadPerFeatureOwn));
  ALines.Add('');
  ALines.Add(UiText(TPluginReportText.FeatureCallsTotalMeanMaximum));
  ALines.Add('--- | --- | --- | --- | --- | --- | ---');
  for mRow in TAtlasPluginRows.Features(ASnapshot) do
  begin
    ALines.Add(Format('%s | %d | %s | %s | %s | %d | %s', [mRow.Name, mRow.Stat.Calls,
      TAtlasPluginRows.Ms(mRow.Stat.TotalMs), TAtlasPluginRows.Ms(mRow.Stat.MeanMs),
      TAtlasPluginRows.Ms(mRow.Stat.MaxMs), mRow.Stat.SlowCalls, TAtlasPluginRows.Percent(mRow.Share * 100)]));
  end;
  if Length(ASnapshot.Features) = 0 then
  begin
    ALines.Add(UiText(TPluginReportText.NoCallMeasuredYet));
  end;
  ALines.Add('');
end;

procedure AddSlow(ALines: TStrings; const ASnapshot: TAtlasPluginSnapshot);
var
  mCalls: TArray<TAtlasSlowCall>;
  mIndex: Integer;
  mActivity: string;
begin
  mCalls := TAtlasPluginRows.Slow(ASnapshot, False, Low(TAtlasFeature));
  ALines.Add(Format(UiText(TPluginReportText.SlowCallsNewestFirstAt), [TAtlasPluginRows.cReportSlowCalls]));
  ALines.Add('');
  for mIndex := 0 to Min(High(mCalls), TAtlasPluginRows.cReportSlowCalls - 1) do
  begin
    mActivity := mCalls[mIndex].Activity;
    if mActivity = '' then
    begin
      mActivity := cNoValue;
    end;
    ALines.Add(Format('- %s %s, %s: %s ms', [TAtlasPluginRows.Clock(mCalls[mIndex].At),
      TAtlasGuard.FeatureName(mCalls[mIndex].Feature), mActivity, TAtlasPluginRows.Ms(mCalls[mIndex].Ms)]));
  end;
  if Length(mCalls) = 0 then
  begin
    ALines.Add(UiText(TPluginReportText.None));
  end;
  ALines.Add('');
end;

procedure AddRequests(ALines: TStrings; const ASnapshot: TAtlasPluginSnapshot);
var
  mRequest: TAtlasRequestTiming;
begin
  ALines.Add(UiText(TPluginReportText.ServerRequestsMs));
  ALines.Add('');
  ALines.Add(UiText(TPluginReportText.RequestCountMeanMaximumMain));
  ALines.Add('--- | --- | --- | --- | --- | --- | --- | --- | ---');
  for mRequest in TAtlasPluginRows.Requests(ASnapshot) do
  begin
    ALines.Add(Format('%s | %d | %s | %s | %d | %s | %d | %d | %d', [mRequest.Method, mRequest.Stat.Calls,
      TAtlasPluginRows.Ms(mRequest.Stat.MeanMs), TAtlasPluginRows.Ms(mRequest.Stat.MaxMs), mRequest.WaitedCalls,
      TAtlasPluginRows.Ms(mRequest.WaitedMeanMs), mRequest.TimedOut, mRequest.Cancelled, mRequest.Failed]));
  end;
  ALines.Add('');
end;

procedure AddSources(ALines: TStrings; const ASnapshot: TAtlasPluginSnapshot);
var
  mSource: TAtlasSourceTiming;
begin
  ALines.Add(UiText(TPluginReportText.BackgroundSourcesMs));
  ALines.Add('');
  ALines.Add(UiText(TPluginReportText.SourceCallsMeanMaximumToo));
  ALines.Add('--- | --- | --- | --- | ---');
  for mSource in TAtlasPluginRows.Sources(ASnapshot) do
  begin
    ALines.Add(Format('%s | %d | %s | %s | %d', [mSource.Name, mSource.Stat.Calls,
      TAtlasPluginRows.Ms(mSource.Stat.MeanMs), TAtlasPluginRows.Ms(mSource.Stat.MaxMs), mSource.Slow]));
  end;
  ALines.Add('');
end;

procedure AddHangs(ALines: TStrings; const ASnapshot: TAtlasPluginSnapshot);
var
  mHang: TAtlasHangEntry;
  mActivity: string;
begin
  ALines.Add(UiText(TPluginReportText.HangsFreezeWatchdogNewestFirst));
  ALines.Add('');
  for mHang in TAtlasPluginRows.Hangs(ASnapshot) do
  begin
    mActivity := mHang.Activity;
    if mActivity = '' then
    begin
      mActivity := cNoValue;
    end;
    ALines.Add(Format(UiText(TPluginReportText.MsAtlasInvolved), [TAtlasPluginRows.Clock(mHang.At), mHang.DurationMs,
      mActivity, BoolToStr(mHang.WithAtlas, True)]));
  end;
  if Length(ASnapshot.Hangs) = 0 then
  begin
    ALines.Add(UiText(TPluginReportText.None));
  end;
  ALines.Add('');
end;

class function TAtlasPluginReport.Build(const ASnapshot: TAtlasPluginSnapshot): string;
var
  mLines: TStringList;
begin
  mLines := TStringList.Create;
  try
    mLines.Add(UiText(TPluginReportText.PluginTimings));
    mLines.Add('');
    mLines.Add(Format(UiText(TPluginReportText.MeasuringSinceSlowFromMs),
      [FormatDateTime('hh":"nn":"ss', ASnapshot.Since), ASnapshot.ThresholdMs,
      TAtlasPluginRows.Percent(ASnapshot.BusyPercent), Length(ASnapshot.Busy)]));
    mLines.Add('');
    AddFeatures(mLines, ASnapshot);
    AddSlow(mLines, ASnapshot);
    AddRequests(mLines, ASnapshot);
    AddSources(mLines, ASnapshot);
    AddHangs(mLines, ASnapshot);
    Result := mLines.Text;
  finally
    mLines.Free;
  end;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Diagnostics.PluginReport', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
