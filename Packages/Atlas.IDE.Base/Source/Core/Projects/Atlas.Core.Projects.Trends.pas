unit Atlas.Core.Projects.Trends;

// Projektverlauf (#758): Messpunkte je Build in der Projekt-Zusammenfassung
// (#592, Abschnitt "trends"), ohne VCL und Open Tools API.
// - Append legt nach jedem Build des Benutzers (nicht nach einer
//   Hintergrundprüfung) einen Punkt an: Zeitpunkt, laufende Nummer, Branch
//   und Commit sowie die Werte, die in der Zusammenfassung zum Zeitpunkt des
//   Builds stehen. Danach bleiben höchstens welcomePage.trends.points Punkte
//   (Ringpuffer, die ältesten fallen weg).
// - Fill trägt Werte nach, die erst nach dem Build kommen (Code-Metriken #66,
//   TODOs #68 und Baseline #97 aus dem Hintergrundlauf nach dem Build, frisch
//   abgefragter Branch und Commit), in den Punkt mit demselben Zeitpunkt ein.
//   Werte anderer Builds bleiben unangetastet.
// - Ein Wert gilt nur, wenn sein Abschnitt den Zeitpunkt des Builds trägt
//   (gleiche Sekunde); sonst bleibt die Lücke. Beim Anzeigen wird nichts
//   gerechnet.
// Werte je Reihe (in Zehnteln, siehe TAtlasTrendPoint):
//   Warnings      Warnungen plus Hinweise des Builds ("build")
//   RuleHits      neue Regeltreffer gegenüber der Baseline ("rules"), nur wenn
//                 eine gültige Baseline im Projektordner liegt ("baseline");
//                 ohne Baseline eine Lücke statt 0
//   Todos         offene TODOs ("todos")
//   Duration      Dauer des Compiles in s ("build.durationMs")
//   MethodLength  mittlere Methodenlänge in Zeilen ("metrics", nur mit Methoden)

interface

uses
  System.SysUtils,
  Atlas.Core.Projects.Summary;

type
  TAtlasProjectTrendLog = class
  public const
    /// <summary>Grenzen und Vorgabe für welcomePage.trends.points.</summary>
    DefaultPoints = 30;
    MinPoints = 2;
    MaxPoints = 100;
  public
    /// <summary>Gleicher Zeitpunkt auf die Sekunde (so steht er in der Datei).</summary>
    class function SameStamp(AUtc1, AUtc2: TDateTime): Boolean; static;
    /// <summary>Werte aus ASummary, die zum Zeitpunkt AAtUtc gemessen wurden, in APoint; andere Reihen bleiben.
    /// Branch und Commit aus dem bekannten Stand der Versionsverwaltung.</summary>
    class procedure Measure(const ASummary: TAtlasProjectSummary; AAtUtc: TDateTime;
      var APoint: TAtlasTrendPoint); static;
    /// <summary>Messpunkt eines Builds: neuer Punkt mit der nächsten Nummer (oder derselbe, wenn der letzte
    /// Punkt schon diesen Zeitpunkt hat); danach höchstens ALimit Punkte (auf MinPoints..MaxPoints begrenzt).
    /// </summary>
    class procedure Append(var ASummary: TAtlasProjectSummary; AAtUtc: TDateTime; ALimit: Integer); static;
    /// <summary>Werte nachtragen, die nach dem Build kamen, in den Punkt mit dem Zeitpunkt AAtUtc. False, wenn es
    /// diesen Punkt nicht (mehr) gibt.</summary>
    class function Fill(var ASummary: TAtlasProjectSummary; AAtUtc: TDateTime): Boolean; static;
    /// <summary>Index des Punkts mit dem Zeitpunkt AAtUtc; -1 ohne.</summary>
    class function IndexOf(const ATrends: TAtlasProjectTrends; AAtUtc: TDateTime): Integer; static;
  end;

implementation

uses
  System.Math;

{ TAtlasProjectTrendLog }

/// <summary>Build des Benutzers: Warnungen plus Hinweise, Dauer.</summary>
procedure MeasureBuild(const ASummary: TAtlasProjectSummary; AAtUtc: TDateTime; var APoint: TAtlasTrendPoint);
begin
  if ASummary.Build.Known and TAtlasProjectTrendLog.SameStamp(ASummary.Build.At, AAtUtc) then
  begin
    APoint.SetValue(TAtlasTrendSeries.Warnings, (ASummary.Build.Warnings + ASummary.Build.Hints) * 10);
    if ASummary.Build.DurationMs > 0 then
    begin
      APoint.SetValue(TAtlasTrendSeries.Duration, (ASummary.Build.DurationMs + 50) div 100);
    end;
  end;
end;

/// <summary>Regeltreffer nur mit gültiger Baseline: ohne sie wären alle Treffer „neu“, das ist kein
/// Verlauf.</summary>
procedure MeasureRuleHits(const ASummary: TAtlasProjectSummary; AAtUtc: TDateTime; var APoint: TAtlasTrendPoint);
var
  mBaselineUsable: Boolean;
begin
  mBaselineUsable := ASummary.Baseline.Known and ASummary.Baseline.Exists and ASummary.Baseline.Valid;
  if ASummary.Baseline.Known and TAtlasProjectTrendLog.SameStamp(ASummary.Baseline.At, AAtUtc) and
    not mBaselineUsable then
  begin
    APoint.Clear(TAtlasTrendSeries.RuleHits);
  end
  else if mBaselineUsable and ASummary.Rules.Known and TAtlasProjectTrendLog.SameStamp(ASummary.Rules.At, AAtUtc) then
  begin
    APoint.SetValue(TAtlasTrendSeries.RuleHits, ASummary.Rules.NewHits * 10);
  end;
end;

class function TAtlasProjectTrendLog.SameStamp(AUtc1, AUtc2: TDateTime): Boolean;
begin
  Result := (AUtc1 > 0) and (AUtc2 > 0) and
    (TAtlasProjectSummaries.TimeText(AUtc1) = TAtlasProjectSummaries.TimeText(AUtc2));
end;

class procedure TAtlasProjectTrendLog.Measure(const ASummary: TAtlasProjectSummary; AAtUtc: TDateTime;
  var APoint: TAtlasTrendPoint);
begin
  MeasureBuild(ASummary, AAtUtc, APoint);
  MeasureRuleHits(ASummary, AAtUtc, APoint);
  if ASummary.Todos.Known and SameStamp(ASummary.Todos.At, AAtUtc) then
  begin
    APoint.SetValue(TAtlasTrendSeries.Todos, ASummary.Todos.Open * 10);
  end;
  // Mittelwert steht schon in Zehnteln; ohne Methoden ist er bedeutungslos.
  if ASummary.Metrics.Known and SameStamp(ASummary.Metrics.At, AAtUtc) and (ASummary.Metrics.Methods > 0) then
  begin
    APoint.SetValue(TAtlasTrendSeries.MethodLength, ASummary.Metrics.AverageTenths[0]);
  end;
  if ASummary.Vcs.InWorkingCopy then
  begin
    APoint.Branch := ASummary.Vcs.Branch;
    APoint.Commit := ASummary.Vcs.Revision;
  end;
end;

class function TAtlasProjectTrendLog.IndexOf(const ATrends: TAtlasProjectTrends; AAtUtc: TDateTime): Integer;
var
  mIndex: Integer;
begin
  // Von hinten: Nachträge betreffen fast immer den letzten Punkt.
  for mIndex := High(ATrends.Points) downto 0 do
  begin
    if SameStamp(ATrends.Points[mIndex].At, AAtUtc) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class procedure TAtlasProjectTrendLog.Append(var ASummary: TAtlasProjectSummary; AAtUtc: TDateTime;
  ALimit: Integer);
var
  mIndex, mLimit: Integer;
  mPoint: TAtlasTrendPoint;
begin
  if AAtUtc <= 0 then
  begin
    Exit;
  end;
  if not ASummary.Trends.Known then
  begin
    ASummary.Trends := TAtlasProjectTrends.Empty;
    ASummary.Trends.Known := True;
  end;
  mIndex := High(ASummary.Trends.Points);
  if (mIndex >= 0) and SameStamp(ASummary.Trends.Points[mIndex].At, AAtUtc) then
  begin
    mPoint := ASummary.Trends.Points[mIndex];
  end
  else
  begin
    Inc(ASummary.Trends.Builds);
    mPoint := TAtlasTrendPoint.Create(AAtUtc, ASummary.Trends.Builds);
    ASummary.Trends.Points := ASummary.Trends.Points + [mPoint];
    mIndex := High(ASummary.Trends.Points);
  end;
  Measure(ASummary, AAtUtc, mPoint);
  ASummary.Trends.Points[mIndex] := mPoint;
  mLimit := EnsureRange(ALimit, MinPoints, MaxPoints);
  if Length(ASummary.Trends.Points) > mLimit then
  begin
    ASummary.Trends.Points := Copy(ASummary.Trends.Points, Length(ASummary.Trends.Points) - mLimit, mLimit);
  end;
end;

class function TAtlasProjectTrendLog.Fill(var ASummary: TAtlasProjectSummary; AAtUtc: TDateTime): Boolean;
var
  mIndex: Integer;
  mPoint: TAtlasTrendPoint;
begin
  mIndex := IndexOf(ASummary.Trends, AAtUtc);
  Result := mIndex >= 0;
  if not Result then
  begin
    Exit;
  end;
  mPoint := ASummary.Trends.Points[mIndex];
  Measure(ASummary, AAtUtc, mPoint);
  ASummary.Trends.Points[mIndex] := mPoint;
end;

end.
