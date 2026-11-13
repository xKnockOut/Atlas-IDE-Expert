unit Atlas.Core.Tests.Durations;

// Dauer der Tests an der Testlinse und langsame Tests (#1772), ohne VCL und
// Open Tools API:
// - Marke: nach einem Lauf „Test ausführen · bestanden · 12 ms“ (unter einer
//   Sekunde in ms, darüber in s mit einer Nachkommastelle,
//   TTestResults.DurationText); die Klassenmarke zeigt die Summe ihrer Tests.
// - Langsam: Liegt der langsamste Test der Marke über tests.slowMs, folgt
//   „· langsam“ und die Marke wird gelb, auch wenn er bestand. Fehlgeschlagen
//   bleibt rot: Der Aufrufer gibt dann keine Grenze mit.
// - Liste „Langsamste Tests zeigen“: alle Tests mit Dauer, der langsamste
//   zuerst (TTestResults.Slowest), höchstens cMaxListed.

interface

uses
  Atlas.Text.TestResults;

type
  /// <summary>Texte der Marke: Duration (%s Beschriftung, %s Dauer), Slow (%s Beschriftung) und das
  /// Dezimaltrennzeichen.</summary>
  TAtlasTestDurationTexts = record
    Duration: string;
    Slow: string;
    DecimalSeparator: Char;
  end;

  /// <summary>Zeile der Liste „Langsamste Tests“.</summary>
  TAtlasTestSlowRow = record
    /// <summary>Voller Name aus dem Bericht (Unit.Fixture.Methode[.Fall]).</summary>
    Test: string;
    UnitName: string;
    DurationMs: Int64;
    /// <summary>„12 ms“, „1,2 s“.</summary>
    DurationText: string;
    /// <summary>Über der Grenze tests.slowMs.</summary>
    Slow: Boolean;
  end;

  TAtlasTestDurations = class
  public const
    /// <summary>Höchstens so viele Zeilen in „Langsamste Tests zeigen“.</summary>
    cMaxListed = 50;
  public
    /// <summary>Liegt AMs über der Grenze ASlowMs? ASlowMs 0 oder kleiner: nie.</summary>
    class function IsSlow(AMs: Int64; ASlowMs: Integer): Boolean; static;
    /// <summary>ACaption mit Dauer ADurationMs und, wenn ASlowestMs über ASlowMs liegt, „langsam“ (ASlow). Ohne
    /// Dauer (0) bleibt ACaption.</summary>
    class function Caption(const ACaption: string; ADurationMs, ASlowestMs: Int64; ASlowMs: Integer;
      const ATexts: TAtlasTestDurationTexts; out ASlow: Boolean): string; static;
    /// <summary>Die langsamsten Tests aus ACases als Zeilen, höchstens cMaxListed.</summary>
    class function Rows(const ACases: TArray<TTestCaseResult>; ASlowMs: Integer;
      ADecimalSeparator: Char): TArray<TAtlasTestSlowRow>; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasTestDurations }

class function TAtlasTestDurations.IsSlow(AMs: Int64; ASlowMs: Integer): Boolean;
begin
  Result := (ASlowMs > 0) and (AMs > ASlowMs);
end;

class function TAtlasTestDurations.Caption(const ACaption: string; ADurationMs, ASlowestMs: Int64; ASlowMs: Integer;
  const ATexts: TAtlasTestDurationTexts; out ASlow: Boolean): string;
begin
  ASlow := False;
  if ADurationMs <= 0 then
  begin
    Exit(ACaption);
  end;
  Result := Format(ATexts.Duration, [ACaption, TTestResults.DurationText(ADurationMs, ATexts.DecimalSeparator)]);
  ASlow := IsSlow(ASlowestMs, ASlowMs);
  if ASlow then
  begin
    Result := Format(ATexts.Slow, [Result]);
  end;
end;

class function TAtlasTestDurations.Rows(const ACases: TArray<TTestCaseResult>; ASlowMs: Integer;
  ADecimalSeparator: Char): TArray<TAtlasTestSlowRow>;
var
  mSlowest: TArray<TTestCaseResult>;
  mIndex: Integer;
begin
  mSlowest := TTestResults.Slowest(ACases, cMaxListed);
  SetLength(Result, Length(mSlowest));
  for mIndex := 0 to High(mSlowest) do
  begin
    Result[mIndex] := Default(TAtlasTestSlowRow);
    Result[mIndex].Test := mSlowest[mIndex].FullName;
    Result[mIndex].UnitName := mSlowest[mIndex].UnitName;
    Result[mIndex].DurationMs := mSlowest[mIndex].DurationMs;
    Result[mIndex].DurationText := TTestResults.DurationText(mSlowest[mIndex].DurationMs, ADecimalSeparator);
    Result[mIndex].Slow := IsSlow(mSlowest[mIndex].DurationMs, ASlowMs);
  end;
end;

end.
