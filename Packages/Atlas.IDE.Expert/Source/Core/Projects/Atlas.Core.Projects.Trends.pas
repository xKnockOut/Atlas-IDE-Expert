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

class function TAtlasProjectTrendLog.SameStamp(AUtc1, AUtc2: TDateTime): Boolean;
begin
  Result := (AUtc1 > 0) and (AUtc2 > 0) and
    (TAtlasProjectSummaries.TimeText(AUtc1) = TAtlasProjectSummaries.TimeText(AUtc2));
end;

class procedure TAtlasProjectTrendLog.Measure(const ASummary: TAtlasProjectSummary; AAtUtc: TDateTime;
  var APoint: TAtlasTrendPoint);
var
  BaselineUsable: Boolean;
begin
  // Build des Benutzers: Warnungen plus Hinweise, Dauer.
  if ASummary.Build.Known and SameStamp(ASummary.Build.At, AAtUtc) then
  begin
    APoint.SetValue(TAtlasTrendSeries.Warnings, (ASummary.Build.Warnings + ASummary.Build.Hints) * 10);
    if ASummary.Build.DurationMs > 0 then
      APoint.SetValue(TAtlasTrendSeries.Duration, (ASummary.Build.DurationMs + 50) div 100);
  end;
  // Regeltreffer nur mit gültiger Baseline: ohne sie wären alle Treffer „neu“, das ist kein Verlauf.
  BaselineUsable := ASummary.Baseline.Known and ASummary.Baseline.Exists and ASummary.Baseline.Valid;
  if ASummary.Baseline.Known and SameStamp(ASummary.Baseline.At, AAtUtc) and not BaselineUsable then
    APoint.Clear(TAtlasTrendSeries.RuleHits)
  else if BaselineUsable and ASummary.Rules.Known and SameStamp(ASummary.Rules.At, AAtUtc) then
    APoint.SetValue(TAtlasTrendSeries.RuleHits, ASummary.Rules.NewHits * 10);
  if ASummary.Todos.Known and SameStamp(ASummary.Todos.At, AAtUtc) then
    APoint.SetValue(TAtlasTrendSeries.Todos, ASummary.Todos.Open * 10);
  // Mittelwert steht schon in Zehnteln; ohne Methoden ist er bedeutungslos.
  if ASummary.Metrics.Known and SameStamp(ASummary.Metrics.At, AAtUtc) and (ASummary.Metrics.Methods > 0) then
    APoint.SetValue(TAtlasTrendSeries.MethodLength, ASummary.Metrics.AverageTenths[0]);
  if ASummary.Vcs.InWorkingCopy then
  begin
    APoint.Branch := ASummary.Vcs.Branch;
    APoint.Commit := ASummary.Vcs.Revision;
  end;
end;

class function TAtlasProjectTrendLog.IndexOf(const ATrends: TAtlasProjectTrends; AAtUtc: TDateTime): Integer;
var
  Index: Integer;
begin
  // Von hinten: Nachträge betreffen fast immer den letzten Punkt.
  for Index := High(ATrends.Points) downto 0 do
    if SameStamp(ATrends.Points[Index].At, AAtUtc) then
      Exit(Index);
  Result := -1;
end;

class procedure TAtlasProjectTrendLog.Append(var ASummary: TAtlasProjectSummary; AAtUtc: TDateTime;
  ALimit: Integer);
var
  Index, Limit: Integer;
  Point: TAtlasTrendPoint;
begin
  if AAtUtc <= 0 then
    Exit;
  if not ASummary.Trends.Known then
  begin
    ASummary.Trends := TAtlasProjectTrends.Empty;
    ASummary.Trends.Known := True;
  end;
  Index := High(ASummary.Trends.Points);
  if (Index >= 0) and SameStamp(ASummary.Trends.Points[Index].At, AAtUtc) then
    Point := ASummary.Trends.Points[Index]
  else
  begin
    Inc(ASummary.Trends.Builds);
    Point := TAtlasTrendPoint.Create(AAtUtc, ASummary.Trends.Builds);
    ASummary.Trends.Points := ASummary.Trends.Points + [Point];
    Index := High(ASummary.Trends.Points);
  end;
  Measure(ASummary, AAtUtc, Point);
  ASummary.Trends.Points[Index] := Point;
  Limit := EnsureRange(ALimit, MinPoints, MaxPoints);
  if Length(ASummary.Trends.Points) > Limit then
    ASummary.Trends.Points := Copy(ASummary.Trends.Points, Length(ASummary.Trends.Points) - Limit, Limit);
end;

class function TAtlasProjectTrendLog.Fill(var ASummary: TAtlasProjectSummary; AAtUtc: TDateTime): Boolean;
var
  Index: Integer;
  Point: TAtlasTrendPoint;
begin
  Index := IndexOf(ASummary.Trends, AAtUtc);
  Result := Index >= 0;
  if not Result then
    Exit;
  Point := ASummary.Trends.Points[Index];
  Measure(ASummary, AAtUtc, Point);
  ASummary.Trends.Points[Index] := Point;
end;

end.
