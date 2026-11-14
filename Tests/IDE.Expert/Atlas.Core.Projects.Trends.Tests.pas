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
  cProject = 'C:\Projekte\Kasse\Kasse.dproj';

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
  mSummary: TAtlasProjectSummary;
  mPoint: TAtlasTrendPoint;
begin
  mSummary := TAtlasProjectSummary.Create(cProject);
  mSummary.Build := TAtlasProjectBuild.Empty;
  mSummary.Build.Known := True;
  mSummary.Build.At := Stamp(0);
  mSummary.Build.Warnings := 2;
  mSummary.Build.Hints := 1;
  mSummary.Build.DurationMs := 12480;
  TAtlasProjectTrendLog.Append(mSummary, Stamp(0), 30);
  Assert.IsTrue(mSummary.Trends.Known);
  Assert.AreEqual(1, mSummary.Trends.Builds);
  Assert.AreEqual(1, Integer(Length(mSummary.Trends.Points)));
  mPoint := mSummary.Trends.Points[0];
  Assert.AreEqual(1, mPoint.Build);
  Assert.IsTrue(TAtlasProjectTrendLog.SameStamp(Stamp(0), mPoint.At));
  Assert.IsTrue(mPoint.Has[TAtlasTrendSeries.Warnings]);
  Assert.AreEqual(30, mPoint.Values[TAtlasTrendSeries.Warnings], 'Warnungen plus Hinweise in Zehnteln');
  Assert.IsTrue(mPoint.Has[TAtlasTrendSeries.Duration]);
  Assert.AreEqual(125, mPoint.Values[TAtlasTrendSeries.Duration], '12,48 s gerundet auf 12,5 s');
  Assert.IsFalse(mPoint.Has[TAtlasTrendSeries.Todos], 'TODOs kommen erst nach dem Build');
  Assert.IsFalse(mPoint.Has[TAtlasTrendSeries.MethodLength]);
  Assert.IsFalse(mPoint.Has[TAtlasTrendSeries.RuleHits]);
end;

procedure TAtlasProjectTrendLogTests.FallingHintsShowLastAndPrevious;
const
  cHints: array[0..4] of Integer = (12, 9, 6, 3, 0);
var
  mSummary: TAtlasProjectSummary;
  mView: TAtlasTrendView;
  mTile: TAtlasTrendTile;
  mIndex, mPrevious: Integer;
begin
  mSummary := TAtlasProjectSummary.Create(cProject);
  for mIndex := 0 to High(cHints) do
  begin
    Build(mSummary, Stamp(mIndex), 0, cHints[mIndex], 30);
  end;
  mView := TAtlasWelcomeTrends.View(mSummary, [TAtlasTrendSeries.Warnings], 30);
  Assert.AreEqual(1, Integer(Length(mView.Tiles)));
  mTile := mView.Tiles[0];
  Assert.AreEqual(5, Integer(Length(mTile.Values)));
  Assert.IsTrue(mTile.HasLast);
  Assert.AreEqual(0, mTile.Last);
  Assert.IsTrue(mTile.Previous(mPrevious));
  Assert.AreEqual(30, mPrevious, 'vorher 3');
  for mIndex := 1 to High(mTile.Values) do
  begin
    Assert.IsTrue(mTile.Values[mIndex] < mTile.Values[mIndex - 1], 'fallend');
  end;
  Assert.AreEqual(0, mTile.Bottom, 'Nulllinie');
  Assert.AreEqual(120, mTile.Top);
  Assert.AreEqual('0', TAtlasWelcomeTrends.ValueText(mTile.Series, mTile.Last, ','));
  Assert.AreEqual('3', TAtlasWelcomeTrends.ValueText(mTile.Series, mPrevious, ','));
end;

procedure TAtlasProjectTrendLogTests.RingBufferKeepsNewestPoints;
var
  mSummary, mLoaded: TAtlasProjectSummary;
  mIndex: Integer;
begin
  mSummary := TAtlasProjectSummary.Create(cProject);
  for mIndex := 1 to 31 do
  begin
    Build(mSummary, Stamp(mIndex), mIndex, 0, 30);
  end;
  Assert.AreEqual(30, Integer(Length(mSummary.Trends.Points)));
  Assert.AreEqual(31, mSummary.Trends.Builds);
  Assert.AreEqual(2, mSummary.Trends.Points[0].Build, 'der älteste fällt weg');
  Assert.AreEqual(31, mSummary.Trends.Points[29].Build);
  Assert.AreEqual(310, mSummary.Trends.Points[29].Values[TAtlasTrendSeries.Warnings]);
  // Auch in der Datei.
  Assert.IsTrue(TAtlasProjectSummaries.Parse(TAtlasProjectSummaries.ToJson(mSummary), mLoaded));
  Assert.AreEqual(30, Integer(Length(mLoaded.Trends.Points)));
  Assert.AreEqual(31, mLoaded.Trends.Builds);
  Assert.AreEqual(2, mLoaded.Trends.Points[0].Build);
end;

procedure TAtlasProjectTrendLogTests.LimitIsClamped;
var
  mSummary: TAtlasProjectSummary;
  mIndex: Integer;
begin
  mSummary := TAtlasProjectSummary.Create(cProject);
  for mIndex := 1 to 5 do
  begin
    Build(mSummary, Stamp(mIndex), 0, 0, 1);
  end;
  Assert.AreEqual(TAtlasProjectTrendLog.cMinPoints, Integer(Length(mSummary.Trends.Points)));
  // Kleinere Grenze danach: kürzt beim nächsten Build.
  mSummary := TAtlasProjectSummary.Create(cProject);
  for mIndex := 1 to 10 do
  begin
    Build(mSummary, Stamp(mIndex), 0, 0, 30);
  end;
  Build(mSummary, Stamp(11), 0, 0, 4);
  Assert.AreEqual(4, Integer(Length(mSummary.Trends.Points)));
  Assert.AreEqual(11, mSummary.Trends.Points[3].Build);
  Build(mSummary, Stamp(12), 0, 0, 1000);
  Assert.AreEqual(5, Integer(Length(mSummary.Trends.Points)), 'größere Grenze holt nichts zurück');
end;

procedure TAtlasProjectTrendLogTests.SameStampReusesPoint;
var
  mSummary: TAtlasProjectSummary;
begin
  mSummary := TAtlasProjectSummary.Create(cProject);
  Build(mSummary, Stamp(0), 1, 0, 30);
  Build(mSummary, Stamp(0), 2, 0, 30);
  Assert.AreEqual(1, Integer(Length(mSummary.Trends.Points)));
  Assert.AreEqual(1, mSummary.Trends.Builds);
  Assert.AreEqual(20, mSummary.Trends.Points[0].Values[TAtlasTrendSeries.Warnings]);
  // Kein Zeitpunkt: kein Punkt.
  TAtlasProjectTrendLog.Append(mSummary, 0, 30);
  Assert.AreEqual(1, Integer(Length(mSummary.Trends.Points)));
end;

procedure TAtlasProjectTrendLogTests.RuleHitsWithoutBaselineAreGap;
var
  mSummary: TAtlasProjectSummary;
  mView: TAtlasTrendView;
begin
  mSummary := TAtlasProjectSummary.Create(cProject);
  Rules(mSummary, Stamp(0), 5);
  Build(mSummary, Stamp(0), 0, 0, 30);
  Assert.IsFalse(mSummary.Trends.Points[0].Has[TAtlasTrendSeries.RuleHits], 'Baseline unbekannt');
  // Nach dem Build: Baseline gelesen, keine Datei.
  mSummary.Baseline := TAtlasProjectBaseline.Empty;
  mSummary.Baseline.Known := True;
  mSummary.Baseline.At := Stamp(0);
  Assert.IsTrue(TAtlasProjectTrendLog.Fill(mSummary, Stamp(0)));
  Assert.IsFalse(mSummary.Trends.Points[0].Has[TAtlasTrendSeries.RuleHits], 'keine Baseline');
  mView := TAtlasWelcomeTrends.View(mSummary, [TAtlasTrendSeries.RuleHits], 30);
  Assert.IsFalse(mView.Tiles[0].HasLast, 'Lücke statt 0');
  // Auch in der Datei: kein Feld, also keine 0.
  Assert.IsFalse(TAtlasProjectSummaries.ToJson(mSummary).Contains('"ruleHits"'));
end;

procedure TAtlasProjectTrendLogTests.RuleHitsWithBaseline;
var
  mSummary: TAtlasProjectSummary;
begin
  mSummary := TAtlasProjectSummary.Create(cProject);
  Rules(mSummary, Stamp(0), 5);
  Build(mSummary, Stamp(0), 0, 0, 30);
  // Baseline aus dem Hintergrundlauf mit demselben Zeitpunkt.
  UsableBaseline(mSummary, Stamp(0));
  Assert.IsTrue(TAtlasProjectTrendLog.Fill(mSummary, Stamp(0)));
  Assert.IsTrue(mSummary.Trends.Points[0].Has[TAtlasTrendSeries.RuleHits]);
  Assert.AreEqual(50, mSummary.Trends.Points[0].Values[TAtlasTrendSeries.RuleHits]);
  // Nächster Build: Baseline von vorher gilt weiter, 0 neue Treffer sind ein Wert.
  Rules(mSummary, Stamp(1), 0);
  Build(mSummary, Stamp(1), 0, 0, 30);
  Assert.IsTrue(mSummary.Trends.Points[1].Has[TAtlasTrendSeries.RuleHits]);
  Assert.AreEqual(0, mSummary.Trends.Points[1].Values[TAtlasTrendSeries.RuleHits]);
end;

procedure TAtlasProjectTrendLogTests.MissingBaselineClearsRuleHits;
var
  mSummary: TAtlasProjectSummary;
begin
  mSummary := TAtlasProjectSummary.Create(cProject);
  UsableBaseline(mSummary, Stamp(0));
  Rules(mSummary, Stamp(1), 4);
  Build(mSummary, Stamp(1), 0, 0, 30);
  Assert.IsTrue(mSummary.Trends.Points[0].Has[TAtlasTrendSeries.RuleHits], 'Baseline von vorher');
  // Die Baseline wurde inzwischen gelöscht: Der Hintergrundlauf findet keine Datei.
  mSummary.Baseline.At := Stamp(1);
  mSummary.Baseline.Exists := False;
  mSummary.Baseline.Valid := False;
  TAtlasProjectTrendLog.Fill(mSummary, Stamp(1));
  Assert.IsFalse(mSummary.Trends.Points[0].Has[TAtlasTrendSeries.RuleHits]);
  // Ungültige Datei ebenso.
  mSummary.Baseline.Exists := True;
  mSummary.Baseline.Valid := False;
  Rules(mSummary, Stamp(2), 4);
  Build(mSummary, Stamp(2), 0, 0, 30);
  Assert.IsFalse(mSummary.Trends.Points[1].Has[TAtlasTrendSeries.RuleHits]);
end;

procedure TAtlasProjectTrendLogTests.FillOnlyTouchesMatchingPoint;
var
  mSummary: TAtlasProjectSummary;
begin
  mSummary := TAtlasProjectSummary.Create(cProject);
  Build(mSummary, Stamp(0), 0, 0, 30);
  Build(mSummary, Stamp(1), 0, 0, 30);
  // TODOs des ersten Builds kommen spät.
  mSummary.Todos := TAtlasProjectTodos.Empty;
  mSummary.Todos.Known := True;
  mSummary.Todos.At := Stamp(0);
  mSummary.Todos.Open := 17;
  Assert.IsTrue(TAtlasProjectTrendLog.Fill(mSummary, Stamp(0)));
  Assert.IsTrue(mSummary.Trends.Points[0].Has[TAtlasTrendSeries.Todos]);
  Assert.AreEqual(170, mSummary.Trends.Points[0].Values[TAtlasTrendSeries.Todos]);
  Assert.IsFalse(mSummary.Trends.Points[1].Has[TAtlasTrendSeries.Todos], 'anderer Build');
  // Punkt gibt es nicht (mehr).
  Assert.IsFalse(TAtlasProjectTrendLog.Fill(mSummary, Stamp(9)));
  Assert.AreEqual(-1, TAtlasProjectTrendLog.IndexOf(mSummary.Trends, Stamp(9)));
  Assert.AreEqual(1, TAtlasProjectTrendLog.IndexOf(mSummary.Trends, Stamp(1)));
end;

procedure TAtlasProjectTrendLogTests.ValuesOfOtherTimesStayGaps;
var
  mSummary: TAtlasProjectSummary;
begin
  mSummary := TAtlasProjectSummary.Create(cProject);
  // TODOs und Metriken von früher: gehören nicht zu diesem Build.
  mSummary.Todos := TAtlasProjectTodos.Empty;
  mSummary.Todos.Known := True;
  mSummary.Todos.At := Stamp(-60);
  mSummary.Todos.Open := 3;
  mSummary.Metrics := TAtlasProjectMetrics.Empty;
  mSummary.Metrics.Known := True;
  mSummary.Metrics.At := Stamp(-60);
  mSummary.Metrics.Methods := 10;
  mSummary.Metrics.AverageTenths[0] := 118;
  Build(mSummary, Stamp(0), 0, 0, 30);
  Assert.IsFalse(mSummary.Trends.Points[0].Has[TAtlasTrendSeries.Todos]);
  Assert.IsFalse(mSummary.Trends.Points[0].Has[TAtlasTrendSeries.MethodLength]);
  // Build-Dauer unbekannt: Lücke.
  Assert.IsFalse(mSummary.Trends.Points[0].Has[TAtlasTrendSeries.Duration]);
  // Gleiche Sekunde zählt als derselbe Build.
  mSummary.Todos.At := Stamp(0) + 0.2 / SecsPerDay;
  TAtlasProjectTrendLog.Fill(mSummary, Stamp(0));
  Assert.IsTrue(mSummary.Trends.Points[0].Has[TAtlasTrendSeries.Todos]);
end;

procedure TAtlasProjectTrendLogTests.MethodLengthNeedsMethods;
var
  mSummary: TAtlasProjectSummary;
begin
  mSummary := TAtlasProjectSummary.Create(cProject);
  Build(mSummary, Stamp(0), 0, 0, 30);
  mSummary.Metrics := TAtlasProjectMetrics.Empty;
  mSummary.Metrics.Known := True;
  mSummary.Metrics.At := Stamp(0);
  mSummary.Metrics.Methods := 0;
  TAtlasProjectTrendLog.Fill(mSummary, Stamp(0));
  Assert.IsFalse(mSummary.Trends.Points[0].Has[TAtlasTrendSeries.MethodLength], 'ohne Methoden kein Mittel');
  mSummary.Metrics.Methods := 40;
  mSummary.Metrics.AverageTenths[0] := 118;
  TAtlasProjectTrendLog.Fill(mSummary, Stamp(0));
  Assert.AreEqual(118, mSummary.Trends.Points[0].Values[TAtlasTrendSeries.MethodLength]);
end;

procedure TAtlasProjectTrendLogTests.BranchAndCommitFromVcs;
var
  mSummary: TAtlasProjectSummary;
begin
  mSummary := TAtlasProjectSummary.Create(cProject);
  Build(mSummary, Stamp(0), 0, 0, 30);
  Assert.AreEqual('', mSummary.Trends.Points[0].Branch, 'ohne Arbeitskopie');
  mSummary.Vcs := TAtlasProjectVcs.Empty;
  mSummary.Vcs.Known := True;
  mSummary.Vcs.Kind := 'git';
  mSummary.Vcs.Branch := 'main';
  mSummary.Vcs.Revision := '1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b';
  // Frisch abgefragt nach dem Build: in den Punkt dieses Builds.
  TAtlasProjectTrendLog.Fill(mSummary, Stamp(0));
  Assert.AreEqual('main', mSummary.Trends.Points[0].Branch);
  Assert.AreEqual('1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b', mSummary.Trends.Points[0].Commit);
end;

procedure TAtlasProjectTrendLogTests.JsonRoundTrip;
var
  mSummary, mLoaded: TAtlasProjectSummary;
  mJson: string;
  mPoint: TAtlasTrendPoint;
begin
  mSummary := TAtlasProjectSummary.Create(cProject);
  mSummary.Vcs := TAtlasProjectVcs.Empty;
  mSummary.Vcs.Known := True;
  mSummary.Vcs.Kind := 'git';
  mSummary.Vcs.Branch := 'feature/x';
  mSummary.Vcs.Revision := 'abc';
  mSummary.Build := TAtlasProjectBuild.Empty;
  mSummary.Build.Known := True;
  mSummary.Build.At := Stamp(0);
  mSummary.Build.Warnings := 3;
  mSummary.Build.DurationMs := 12480;
  mSummary.Metrics := TAtlasProjectMetrics.Empty;
  mSummary.Metrics.Known := True;
  mSummary.Metrics.At := Stamp(0);
  mSummary.Metrics.Methods := 4;
  mSummary.Metrics.AverageTenths[0] := 118;
  TAtlasProjectTrendLog.Append(mSummary, Stamp(0), 30);
  mJson := TAtlasProjectSummaries.ToJson(mSummary);
  Assert.IsTrue(mJson.Contains('"durationMs": 12480') or mJson.Contains('"durationMs":12480'), mJson);
  Assert.IsTrue(mJson.Contains('12.5'), 'Dauer mit Nachkommastelle: ' + mJson);
  Assert.IsTrue(mJson.Contains('11.8'), 'Methodenlänge mit Nachkommastelle: ' + mJson);
  Assert.IsTrue(TAtlasProjectSummaries.Parse(mJson, mLoaded));
  Assert.AreEqual(12480, mLoaded.Build.DurationMs);
  Assert.IsTrue(mLoaded.Trends.Known);
  Assert.AreEqual(1, Integer(Length(mLoaded.Trends.Points)));
  mPoint := mLoaded.Trends.Points[0];
  Assert.AreEqual(1, mPoint.Build);
  Assert.IsTrue(TAtlasProjectTrendLog.SameStamp(Stamp(0), mPoint.At));
  Assert.AreEqual('feature/x', mPoint.Branch);
  Assert.AreEqual('abc', mPoint.Commit);
  Assert.AreEqual(30, mPoint.Values[TAtlasTrendSeries.Warnings]);
  Assert.AreEqual(125, mPoint.Values[TAtlasTrendSeries.Duration]);
  Assert.AreEqual(118, mPoint.Values[TAtlasTrendSeries.MethodLength]);
  Assert.IsFalse(mPoint.Has[TAtlasTrendSeries.Todos], 'Lücke bleibt Lücke');
  Assert.IsFalse(mPoint.Has[TAtlasTrendSeries.RuleHits]);
  // Ohne Verlauf kein Abschnitt.
  Assert.IsFalse(TAtlasProjectSummaries.ToJson(TAtlasProjectSummary.Create(cProject)).Contains('"trends"'));
end;

procedure TAtlasProjectTrendLogTests.JsonKeepsUnknownFields;
const
  cJson = '{"format": 1, "project": "C:\\Projekte\\Kasse\\Kasse.dproj", ' +
    '"trends": {"builds": 7, "zoom": "week", "points": [' +
    '{"at": "2026-10-14T12:00:00Z", "build": 6, "warnings": 4, "coverage": 81.5},' +
    '{"at": "2026-10-14T12:01:00Z", "build": 7, "todos": 2, "tag": {"a": 1}}]}}';
var
  mSummary, mLoaded: TAtlasProjectSummary;
  mText: string;
begin
  Assert.IsTrue(TAtlasProjectSummaries.Parse(cJson, mSummary));
  Assert.AreEqual(7, mSummary.Trends.Builds);
  Assert.AreEqual(2, Integer(Length(mSummary.Trends.Points)));
  Assert.AreEqual(40, mSummary.Trends.Points[0].Values[TAtlasTrendSeries.Warnings]);
  Assert.IsFalse(mSummary.Trends.Points[0].Has[TAtlasTrendSeries.Todos]);
  Assert.AreEqual(20, mSummary.Trends.Points[1].Values[TAtlasTrendSeries.Todos]);
  // Ein neuer Build: Felder späterer Versionen bleiben, je Punkt über "build" zugeordnet.
  mSummary.Build := TAtlasProjectBuild.Empty;
  mSummary.Build.Known := True;
  mSummary.Build.At := Stamp(2);
  TAtlasProjectTrendLog.Append(mSummary, Stamp(2), 30);
  mText := TAtlasProjectSummaries.ToJson(mSummary);
  Assert.IsTrue(mText.Contains('"zoom"'), mText);
  Assert.IsTrue(mText.Contains('"coverage"'), mText);
  Assert.IsTrue(mText.Contains('"tag"'), mText);
  Assert.IsTrue(TAtlasProjectSummaries.Parse(mText, mLoaded));
  Assert.AreEqual(3, Integer(Length(mLoaded.Trends.Points)));
  Assert.AreEqual(8, mLoaded.Trends.Points[2].Build);
  // Fällt der Punkt aus dem Ringpuffer, gehen auch seine unbekannten Felder.
  TAtlasProjectTrendLog.Append(mLoaded, Stamp(3), 2);
  mText := TAtlasProjectSummaries.ToJson(mLoaded);
  Assert.IsFalse(mText.Contains('"coverage"'), mText);
  Assert.IsFalse(mText.Contains('"tag"'), mText);
  Assert.IsTrue(mText.Contains('"zoom"'), 'Feld des Abschnitts bleibt');
end;

procedure TAtlasProjectTrendLogTests.JsonRenumbersPointsWithoutBuild;
const
  cJson = '{"format": 1, "project": "C:\\Projekte\\Kasse\\Kasse.dproj", ' +
    '"trends": {"points": [{"at": "2026-10-14T12:00:00Z"}, {"at": "2026-10-14T12:01:00Z", "build": 5},' +
    '{"at": "2026-10-14T12:02:00Z", "build": 5}]}}';
var
  mSummary: TAtlasProjectSummary;
  mIndex: Integer;
begin
  Assert.IsTrue(TAtlasProjectSummaries.Parse(cJson, mSummary));
  Assert.AreEqual(3, Integer(Length(mSummary.Trends.Points)));
  for mIndex := 1 to High(mSummary.Trends.Points) do
  begin
    Assert.IsTrue(mSummary.Trends.Points[mIndex].Build > mSummary.Trends.Points[mIndex - 1].Build, 'aufsteigend, eindeutig');
  end;
  Assert.IsTrue(mSummary.Trends.Builds >= mSummary.Trends.Points[2].Build, 'Zähler mindestens die höchste Nummer');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasProjectTrendLogTests);

end.
