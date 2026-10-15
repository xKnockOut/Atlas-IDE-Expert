unit Atlas.Core.Projects.Trends.Tests;

// Tests des Projektverlaufs in der Projekt-Zusammenfassung (#758): Messpunkt
// je Build, Ringpuffer mit welcomePage.trends.points, Nachtragen von Werten
// mit demselben Zeitpunkt, Lücken (keine Baseline, Wert eines anderen Builds),
// Vergleich mit dem Vorwert und der Abschnitt "trends" in der Datei
// (Dezimalwerte, Lücken, unbekannte Felder).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasProjectTrendLogTests = class
  public
    [Test]
    procedure AppendTakesValuesOfTheBuild;
    /// <summary>Abnahme: 5 Builds mit 12, 9, 6, 3, 0 Hinweisen ergeben „0, vorher 3“ und eine fallende Linie.
    /// </summary>
    [Test]
    procedure FallingHintsShowLastAndPrevious;
    /// <summary>Abnahme: Nach 31 Builds stehen genau 30 Punkte in der Datei.</summary>
    [Test]
    procedure RingBufferKeepsNewestPoints;
    [Test]
    procedure LimitIsClamped;
    [Test]
    procedure SameStampReusesPoint;
    /// <summary>Abnahme: Ohne Baseline sind Regeltreffer eine Lücke, nicht 0.</summary>
    [Test]
    procedure RuleHitsWithoutBaselineAreGap;
    [Test]
    procedure RuleHitsWithBaseline;
    [Test]
    procedure MissingBaselineClearsRuleHits;
    [Test]
    procedure FillOnlyTouchesMatchingPoint;
    [Test]
    procedure ValuesOfOtherTimesStayGaps;
    [Test]
    procedure MethodLengthNeedsMethods;
    [Test]
    procedure BranchAndCommitFromVcs;
    [Test]
    procedure JsonRoundTrip;
    [Test]
    procedure JsonKeepsUnknownFields;
    [Test]
    procedure JsonRenumbersPointsWithoutBuild;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Projects.Trends,
  Atlas.Core.Welcome.Trends;

const
  Project = 'C:\Projekte\Kasse\Kasse.dproj';

function Stamp(AMinute: Integer): TDateTime;
begin
  Result := EncodeDateTime(2026, 10, 14, 12, 0, 0, 0) + AMinute / MinsPerDay;
end;

/// <summary>Build des Benutzers zum Zeitpunkt AAtUtc mit Warnungen und Hinweisen, danach ein Messpunkt.</summary>
procedure Build(var ASummary: TAtlasProjectSummary; AAtUtc: TDateTime; AWarnings, AHints: Integer;
  ALimit: Integer);
begin
  ASummary.Build := TAtlasProjectBuild.Empty;
  ASummary.Build.Known := True;
  ASummary.Build.At := AAtUtc;
  ASummary.Build.Warnings := AWarnings;
  ASummary.Build.Hints := AHints;
  TAtlasProjectTrendLog.Append(ASummary, AAtUtc, ALimit);
end;

procedure UsableBaseline(var ASummary: TAtlasProjectSummary; AAtUtc: TDateTime);
begin
  ASummary.Baseline := TAtlasProjectBaseline.Empty;
  ASummary.Baseline.Known := True;
  ASummary.Baseline.At := AAtUtc;
  ASummary.Baseline.Exists := True;
  ASummary.Baseline.Valid := True;
end;

procedure Rules(var ASummary: TAtlasProjectSummary; AAtUtc: TDateTime; ANewHits: Integer);
begin
  ASummary.Rules := TAtlasProjectRules.Empty;
  ASummary.Rules.Known := True;
  ASummary.Rules.At := AAtUtc;
  ASummary.Rules.NewHits := ANewHits;
end;

{ TAtlasProjectTrendLogTests }

procedure TAtlasProjectTrendLogTests.AppendTakesValuesOfTheBuild;
var
  Summary: TAtlasProjectSummary;
  Point: TAtlasTrendPoint;
begin
  Summary := TAtlasProjectSummary.Create(Project);
  Summary.Build := TAtlasProjectBuild.Empty;
  Summary.Build.Known := True;
  Summary.Build.At := Stamp(0);
  Summary.Build.Warnings := 2;
  Summary.Build.Hints := 1;
  Summary.Build.DurationMs := 12480;
  TAtlasProjectTrendLog.Append(Summary, Stamp(0), 30);
  Assert.IsTrue(Summary.Trends.Known);
  Assert.AreEqual(1, Summary.Trends.Builds);
  Assert.AreEqual(1, Integer(Length(Summary.Trends.Points)));
  Point := Summary.Trends.Points[0];
  Assert.AreEqual(1, Point.Build);
  Assert.IsTrue(TAtlasProjectTrendLog.SameStamp(Stamp(0), Point.At));
  Assert.IsTrue(Point.Has[TAtlasTrendSeries.Warnings]);
  Assert.AreEqual(30, Point.Values[TAtlasTrendSeries.Warnings], 'Warnungen plus Hinweise in Zehnteln');
  Assert.IsTrue(Point.Has[TAtlasTrendSeries.Duration]);
  Assert.AreEqual(125, Point.Values[TAtlasTrendSeries.Duration], '12,48 s gerundet auf 12,5 s');
  Assert.IsFalse(Point.Has[TAtlasTrendSeries.Todos], 'TODOs kommen erst nach dem Build');
  Assert.IsFalse(Point.Has[TAtlasTrendSeries.MethodLength]);
  Assert.IsFalse(Point.Has[TAtlasTrendSeries.RuleHits]);
end;

procedure TAtlasProjectTrendLogTests.FallingHintsShowLastAndPrevious;
const
  Hints: array[0..4] of Integer = (12, 9, 6, 3, 0);
var
  Summary: TAtlasProjectSummary;
  View: TAtlasTrendView;
  Tile: TAtlasTrendTile;
  Index, Previous: Integer;
begin
  Summary := TAtlasProjectSummary.Create(Project);
  for Index := 0 to High(Hints) do
    Build(Summary, Stamp(Index), 0, Hints[Index], 30);
  View := TAtlasWelcomeTrends.View(Summary, [TAtlasTrendSeries.Warnings], 30);
  Assert.AreEqual(1, Integer(Length(View.Tiles)));
  Tile := View.Tiles[0];
  Assert.AreEqual(5, Integer(Length(Tile.Values)));
  Assert.IsTrue(Tile.HasLast);
  Assert.AreEqual(0, Tile.Last);
  Assert.IsTrue(Tile.Previous(Previous));
  Assert.AreEqual(30, Previous, 'vorher 3');
  for Index := 1 to High(Tile.Values) do
    Assert.IsTrue(Tile.Values[Index] < Tile.Values[Index - 1], 'fallend');
  Assert.AreEqual(0, Tile.Bottom, 'Nulllinie');
  Assert.AreEqual(120, Tile.Top);
  Assert.AreEqual('0', TAtlasWelcomeTrends.ValueText(Tile.Series, Tile.Last, ','));
  Assert.AreEqual('3', TAtlasWelcomeTrends.ValueText(Tile.Series, Previous, ','));
end;

procedure TAtlasProjectTrendLogTests.RingBufferKeepsNewestPoints;
var
  Summary, Loaded: TAtlasProjectSummary;
  Index: Integer;
begin
  Summary := TAtlasProjectSummary.Create(Project);
  for Index := 1 to 31 do
    Build(Summary, Stamp(Index), Index, 0, 30);
  Assert.AreEqual(30, Integer(Length(Summary.Trends.Points)));
  Assert.AreEqual(31, Summary.Trends.Builds);
  Assert.AreEqual(2, Summary.Trends.Points[0].Build, 'der älteste fällt weg');
  Assert.AreEqual(31, Summary.Trends.Points[29].Build);
  Assert.AreEqual(310, Summary.Trends.Points[29].Values[TAtlasTrendSeries.Warnings]);
  // Auch in der Datei.
  Assert.IsTrue(TAtlasProjectSummaries.Parse(TAtlasProjectSummaries.ToJson(Summary), Loaded));
  Assert.AreEqual(30, Integer(Length(Loaded.Trends.Points)));
  Assert.AreEqual(31, Loaded.Trends.Builds);
  Assert.AreEqual(2, Loaded.Trends.Points[0].Build);
end;

procedure TAtlasProjectTrendLogTests.LimitIsClamped;
var
  Summary: TAtlasProjectSummary;
  Index: Integer;
begin
  Summary := TAtlasProjectSummary.Create(Project);
  for Index := 1 to 5 do
    Build(Summary, Stamp(Index), 0, 0, 1);
  Assert.AreEqual(TAtlasProjectTrendLog.MinPoints, Integer(Length(Summary.Trends.Points)));
  // Kleinere Grenze danach: kürzt beim nächsten Build.
  Summary := TAtlasProjectSummary.Create(Project);
  for Index := 1 to 10 do
    Build(Summary, Stamp(Index), 0, 0, 30);
  Build(Summary, Stamp(11), 0, 0, 4);
  Assert.AreEqual(4, Integer(Length(Summary.Trends.Points)));
  Assert.AreEqual(11, Summary.Trends.Points[3].Build);
  Build(Summary, Stamp(12), 0, 0, 1000);
  Assert.AreEqual(5, Integer(Length(Summary.Trends.Points)), 'größere Grenze holt nichts zurück');
end;

procedure TAtlasProjectTrendLogTests.SameStampReusesPoint;
var
  Summary: TAtlasProjectSummary;
begin
  Summary := TAtlasProjectSummary.Create(Project);
  Build(Summary, Stamp(0), 1, 0, 30);
  Build(Summary, Stamp(0), 2, 0, 30);
  Assert.AreEqual(1, Integer(Length(Summary.Trends.Points)));
  Assert.AreEqual(1, Summary.Trends.Builds);
  Assert.AreEqual(20, Summary.Trends.Points[0].Values[TAtlasTrendSeries.Warnings]);
  // Kein Zeitpunkt: kein Punkt.
  TAtlasProjectTrendLog.Append(Summary, 0, 30);
  Assert.AreEqual(1, Integer(Length(Summary.Trends.Points)));
end;

procedure TAtlasProjectTrendLogTests.RuleHitsWithoutBaselineAreGap;
var
  Summary: TAtlasProjectSummary;
  View: TAtlasTrendView;
begin
  Summary := TAtlasProjectSummary.Create(Project);
  Rules(Summary, Stamp(0), 5);
  Build(Summary, Stamp(0), 0, 0, 30);
  Assert.IsFalse(Summary.Trends.Points[0].Has[TAtlasTrendSeries.RuleHits], 'Baseline unbekannt');
  // Nach dem Build: Baseline gelesen, keine Datei.
  Summary.Baseline := TAtlasProjectBaseline.Empty;
  Summary.Baseline.Known := True;
  Summary.Baseline.At := Stamp(0);
  Assert.IsTrue(TAtlasProjectTrendLog.Fill(Summary, Stamp(0)));
  Assert.IsFalse(Summary.Trends.Points[0].Has[TAtlasTrendSeries.RuleHits], 'keine Baseline');
  View := TAtlasWelcomeTrends.View(Summary, [TAtlasTrendSeries.RuleHits], 30);
  Assert.IsFalse(View.Tiles[0].HasLast, 'Lücke statt 0');
  // Auch in der Datei: kein Feld, also keine 0.
  Assert.IsFalse(TAtlasProjectSummaries.ToJson(Summary).Contains('"ruleHits"'));
end;

procedure TAtlasProjectTrendLogTests.RuleHitsWithBaseline;
var
  Summary: TAtlasProjectSummary;
begin
  Summary := TAtlasProjectSummary.Create(Project);
  Rules(Summary, Stamp(0), 5);
  Build(Summary, Stamp(0), 0, 0, 30);
  // Baseline aus dem Hintergrundlauf mit demselben Zeitpunkt.
  UsableBaseline(Summary, Stamp(0));
  Assert.IsTrue(TAtlasProjectTrendLog.Fill(Summary, Stamp(0)));
  Assert.IsTrue(Summary.Trends.Points[0].Has[TAtlasTrendSeries.RuleHits]);
  Assert.AreEqual(50, Summary.Trends.Points[0].Values[TAtlasTrendSeries.RuleHits]);
  // Nächster Build: Baseline von vorher gilt weiter, 0 neue Treffer sind ein Wert.
  Rules(Summary, Stamp(1), 0);
  Build(Summary, Stamp(1), 0, 0, 30);
  Assert.IsTrue(Summary.Trends.Points[1].Has[TAtlasTrendSeries.RuleHits]);
  Assert.AreEqual(0, Summary.Trends.Points[1].Values[TAtlasTrendSeries.RuleHits]);
end;

procedure TAtlasProjectTrendLogTests.MissingBaselineClearsRuleHits;
var
  Summary: TAtlasProjectSummary;
begin
  Summary := TAtlasProjectSummary.Create(Project);
  UsableBaseline(Summary, Stamp(0));
  Rules(Summary, Stamp(1), 4);
  Build(Summary, Stamp(1), 0, 0, 30);
  Assert.IsTrue(Summary.Trends.Points[0].Has[TAtlasTrendSeries.RuleHits], 'Baseline von vorher');
  // Die Baseline wurde inzwischen gelöscht: Der Hintergrundlauf findet keine Datei.
  Summary.Baseline.At := Stamp(1);
  Summary.Baseline.Exists := False;
  Summary.Baseline.Valid := False;
  TAtlasProjectTrendLog.Fill(Summary, Stamp(1));
  Assert.IsFalse(Summary.Trends.Points[0].Has[TAtlasTrendSeries.RuleHits]);
  // Ungültige Datei ebenso.
  Summary.Baseline.Exists := True;
  Summary.Baseline.Valid := False;
  Rules(Summary, Stamp(2), 4);
  Build(Summary, Stamp(2), 0, 0, 30);
  Assert.IsFalse(Summary.Trends.Points[1].Has[TAtlasTrendSeries.RuleHits]);
end;

procedure TAtlasProjectTrendLogTests.FillOnlyTouchesMatchingPoint;
var
  Summary: TAtlasProjectSummary;
begin
  Summary := TAtlasProjectSummary.Create(Project);
  Build(Summary, Stamp(0), 0, 0, 30);
  Build(Summary, Stamp(1), 0, 0, 30);
  // TODOs des ersten Builds kommen spät.
  Summary.Todos := TAtlasProjectTodos.Empty;
  Summary.Todos.Known := True;
  Summary.Todos.At := Stamp(0);
  Summary.Todos.Open := 17;
  Assert.IsTrue(TAtlasProjectTrendLog.Fill(Summary, Stamp(0)));
  Assert.IsTrue(Summary.Trends.Points[0].Has[TAtlasTrendSeries.Todos]);
  Assert.AreEqual(170, Summary.Trends.Points[0].Values[TAtlasTrendSeries.Todos]);
  Assert.IsFalse(Summary.Trends.Points[1].Has[TAtlasTrendSeries.Todos], 'anderer Build');
  // Punkt gibt es nicht (mehr).
  Assert.IsFalse(TAtlasProjectTrendLog.Fill(Summary, Stamp(9)));
  Assert.AreEqual(-1, TAtlasProjectTrendLog.IndexOf(Summary.Trends, Stamp(9)));
  Assert.AreEqual(1, TAtlasProjectTrendLog.IndexOf(Summary.Trends, Stamp(1)));
end;

procedure TAtlasProjectTrendLogTests.ValuesOfOtherTimesStayGaps;
var
  Summary: TAtlasProjectSummary;
begin
  Summary := TAtlasProjectSummary.Create(Project);
  // TODOs und Metriken von früher: gehören nicht zu diesem Build.
  Summary.Todos := TAtlasProjectTodos.Empty;
  Summary.Todos.Known := True;
  Summary.Todos.At := Stamp(-60);
  Summary.Todos.Open := 3;
  Summary.Metrics := TAtlasProjectMetrics.Empty;
  Summary.Metrics.Known := True;
  Summary.Metrics.At := Stamp(-60);
  Summary.Metrics.Methods := 10;
  Summary.Metrics.AverageTenths[0] := 118;
  Build(Summary, Stamp(0), 0, 0, 30);
  Assert.IsFalse(Summary.Trends.Points[0].Has[TAtlasTrendSeries.Todos]);
  Assert.IsFalse(Summary.Trends.Points[0].Has[TAtlasTrendSeries.MethodLength]);
  // Build-Dauer unbekannt: Lücke.
  Assert.IsFalse(Summary.Trends.Points[0].Has[TAtlasTrendSeries.Duration]);
  // Gleiche Sekunde zählt als derselbe Build.
  Summary.Todos.At := Stamp(0) + 0.2 / SecsPerDay;
  TAtlasProjectTrendLog.Fill(Summary, Stamp(0));
  Assert.IsTrue(Summary.Trends.Points[0].Has[TAtlasTrendSeries.Todos]);
end;

procedure TAtlasProjectTrendLogTests.MethodLengthNeedsMethods;
var
  Summary: TAtlasProjectSummary;
begin
  Summary := TAtlasProjectSummary.Create(Project);
  Build(Summary, Stamp(0), 0, 0, 30);
  Summary.Metrics := TAtlasProjectMetrics.Empty;
  Summary.Metrics.Known := True;
  Summary.Metrics.At := Stamp(0);
  Summary.Metrics.Methods := 0;
  TAtlasProjectTrendLog.Fill(Summary, Stamp(0));
  Assert.IsFalse(Summary.Trends.Points[0].Has[TAtlasTrendSeries.MethodLength], 'ohne Methoden kein Mittel');
  Summary.Metrics.Methods := 40;
  Summary.Metrics.AverageTenths[0] := 118;
  TAtlasProjectTrendLog.Fill(Summary, Stamp(0));
  Assert.AreEqual(118, Summary.Trends.Points[0].Values[TAtlasTrendSeries.MethodLength]);
end;

procedure TAtlasProjectTrendLogTests.BranchAndCommitFromVcs;
var
  Summary: TAtlasProjectSummary;
begin
  Summary := TAtlasProjectSummary.Create(Project);
  Build(Summary, Stamp(0), 0, 0, 30);
  Assert.AreEqual('', Summary.Trends.Points[0].Branch, 'ohne Arbeitskopie');
  Summary.Vcs := TAtlasProjectVcs.Empty;
  Summary.Vcs.Known := True;
  Summary.Vcs.Kind := 'git';
  Summary.Vcs.Branch := 'main';
  Summary.Vcs.Revision := '1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b';
  // Frisch abgefragt nach dem Build: in den Punkt dieses Builds.
  TAtlasProjectTrendLog.Fill(Summary, Stamp(0));
  Assert.AreEqual('main', Summary.Trends.Points[0].Branch);
  Assert.AreEqual('1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b', Summary.Trends.Points[0].Commit);
end;

procedure TAtlasProjectTrendLogTests.JsonRoundTrip;
var
  Summary, Loaded: TAtlasProjectSummary;
  Json: string;
  Point: TAtlasTrendPoint;
begin
  Summary := TAtlasProjectSummary.Create(Project);
  Summary.Vcs := TAtlasProjectVcs.Empty;
  Summary.Vcs.Known := True;
  Summary.Vcs.Kind := 'git';
  Summary.Vcs.Branch := 'feature/x';
  Summary.Vcs.Revision := 'abc';
  Summary.Build := TAtlasProjectBuild.Empty;
  Summary.Build.Known := True;
  Summary.Build.At := Stamp(0);
  Summary.Build.Warnings := 3;
  Summary.Build.DurationMs := 12480;
  Summary.Metrics := TAtlasProjectMetrics.Empty;
  Summary.Metrics.Known := True;
  Summary.Metrics.At := Stamp(0);
  Summary.Metrics.Methods := 4;
  Summary.Metrics.AverageTenths[0] := 118;
  TAtlasProjectTrendLog.Append(Summary, Stamp(0), 30);
  Json := TAtlasProjectSummaries.ToJson(Summary);
  Assert.IsTrue(Json.Contains('"durationMs": 12480') or Json.Contains('"durationMs":12480'), Json);
  Assert.IsTrue(Json.Contains('12.5'), 'Dauer mit Nachkommastelle: ' + Json);
  Assert.IsTrue(Json.Contains('11.8'), 'Methodenlänge mit Nachkommastelle: ' + Json);
  Assert.IsTrue(TAtlasProjectSummaries.Parse(Json, Loaded));
  Assert.AreEqual(12480, Loaded.Build.DurationMs);
  Assert.IsTrue(Loaded.Trends.Known);
  Assert.AreEqual(1, Integer(Length(Loaded.Trends.Points)));
  Point := Loaded.Trends.Points[0];
  Assert.AreEqual(1, Point.Build);
  Assert.IsTrue(TAtlasProjectTrendLog.SameStamp(Stamp(0), Point.At));
  Assert.AreEqual('feature/x', Point.Branch);
  Assert.AreEqual('abc', Point.Commit);
  Assert.AreEqual(30, Point.Values[TAtlasTrendSeries.Warnings]);
  Assert.AreEqual(125, Point.Values[TAtlasTrendSeries.Duration]);
  Assert.AreEqual(118, Point.Values[TAtlasTrendSeries.MethodLength]);
  Assert.IsFalse(Point.Has[TAtlasTrendSeries.Todos], 'Lücke bleibt Lücke');
  Assert.IsFalse(Point.Has[TAtlasTrendSeries.RuleHits]);
  // Ohne Verlauf kein Abschnitt.
  Assert.IsFalse(TAtlasProjectSummaries.ToJson(TAtlasProjectSummary.Create(Project)).Contains('"trends"'));
end;

procedure TAtlasProjectTrendLogTests.JsonKeepsUnknownFields;
const
  Json = '{"format": 1, "project": "C:\\Projekte\\Kasse\\Kasse.dproj", ' +
    '"trends": {"builds": 7, "zoom": "week", "points": [' +
    '{"at": "2026-10-14T12:00:00Z", "build": 6, "warnings": 4, "coverage": 81.5},' +
    '{"at": "2026-10-14T12:01:00Z", "build": 7, "todos": 2, "tag": {"a": 1}}]}}';
var
  Summary, Loaded: TAtlasProjectSummary;
  Text: string;
begin
  Assert.IsTrue(TAtlasProjectSummaries.Parse(Json, Summary));
  Assert.AreEqual(7, Summary.Trends.Builds);
  Assert.AreEqual(2, Integer(Length(Summary.Trends.Points)));
  Assert.AreEqual(40, Summary.Trends.Points[0].Values[TAtlasTrendSeries.Warnings]);
  Assert.IsFalse(Summary.Trends.Points[0].Has[TAtlasTrendSeries.Todos]);
  Assert.AreEqual(20, Summary.Trends.Points[1].Values[TAtlasTrendSeries.Todos]);
  // Ein neuer Build: Felder späterer Versionen bleiben, je Punkt über "build" zugeordnet.
  Summary.Build := TAtlasProjectBuild.Empty;
  Summary.Build.Known := True;
  Summary.Build.At := Stamp(2);
  TAtlasProjectTrendLog.Append(Summary, Stamp(2), 30);
  Text := TAtlasProjectSummaries.ToJson(Summary);
  Assert.IsTrue(Text.Contains('"zoom"'), Text);
  Assert.IsTrue(Text.Contains('"coverage"'), Text);
  Assert.IsTrue(Text.Contains('"tag"'), Text);
  Assert.IsTrue(TAtlasProjectSummaries.Parse(Text, Loaded));
  Assert.AreEqual(3, Integer(Length(Loaded.Trends.Points)));
  Assert.AreEqual(8, Loaded.Trends.Points[2].Build);
  // Fällt der Punkt aus dem Ringpuffer, gehen auch seine unbekannten Felder.
  TAtlasProjectTrendLog.Append(Loaded, Stamp(3), 2);
  Text := TAtlasProjectSummaries.ToJson(Loaded);
  Assert.IsFalse(Text.Contains('"coverage"'), Text);
  Assert.IsFalse(Text.Contains('"tag"'), Text);
  Assert.IsTrue(Text.Contains('"zoom"'), 'Feld des Abschnitts bleibt');
end;

procedure TAtlasProjectTrendLogTests.JsonRenumbersPointsWithoutBuild;
const
  Json = '{"format": 1, "project": "C:\\Projekte\\Kasse\\Kasse.dproj", ' +
    '"trends": {"points": [{"at": "2026-10-14T12:00:00Z"}, {"at": "2026-10-14T12:01:00Z", "build": 5},' +
    '{"at": "2026-10-14T12:02:00Z", "build": 5}]}}';
var
  Summary: TAtlasProjectSummary;
  Index: Integer;
begin
  Assert.IsTrue(TAtlasProjectSummaries.Parse(Json, Summary));
  Assert.AreEqual(3, Integer(Length(Summary.Trends.Points)));
  for Index := 1 to High(Summary.Trends.Points) do
    Assert.IsTrue(Summary.Trends.Points[Index].Build > Summary.Trends.Points[Index - 1].Build, 'aufsteigend, eindeutig');
  Assert.IsTrue(Summary.Trends.Builds >= Summary.Trends.Points[2].Build, 'Zähler mindestens die höchste Nummer');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasProjectTrendLogTests);

end.
