unit Atlas.Core.Tracker.Sprint.Tests;

// Tests der Sprint-Kachel (#1277) ohne Server: Arbeitstage und Resttage
// (Wochenenden laut Board), Ideallinie, Burndown aus Karten (Punkte bzw.
// Anzahl, wieder geöffnete Karten, Erledigt-Spalte ohne Zeitpunkt), Zählung
// aus den Beispielantworten von YouTrack und GitHub, Vergleich mit dem
// vorherigen Sprint (Normierung auf Sprinttage, auch bei anderer Länge und
// ohne Vorsprint), Velocity, Auswahl der Vorsprints und Zwischenspeicher.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTrackerSprintTests = class
  public
    /// <summary>Montag bis Freitag, Arbeitstage laut Board, ohne Arbeitstag im Zeitraum alle Tage.</summary>
    [Test]
    procedure CalendarSprintDays;
    /// <summary>Resttage zählen den heutigen Tag mit, Wochenenden nicht; nach dem Ende 0.</summary>
    [Test]
    procedure DaysLeftSkipsWeekends;
    [Test]
    procedure CalendarText;
    [Test]
    procedure IdealLine;
    /// <summary>Rest je Arbeitstag in Punkten; wieder geöffnete Karte zählt nicht, Erledigt ohne Zeitpunkt ab der
    /// Abfrage, Karte ohne Schätzung mit 0.</summary>
    [Test]
    procedure SummarizeWithPoints;
    /// <summary>Ohne Schätzfeld bzw. ohne geschätzte Karte zählt die Anzahl.</summary>
    [Test]
    procedure SummarizeWithoutEstimates;
    /// <summary>Zahlen der Kachel: meine offen und erledigt, Team übrig, Ist- und Ideallinie.</summary>
    [Test]
    procedure ViewNumbers;
    [Test]
    procedure YouTrackFixtureCounts;
    [Test]
    procedure GitHubFixtureCounts;
    /// <summary>Vorsprint gleicher Länge: Linie auf Total skaliert, Abweichung am selben Sprinttag, Velocity.
    /// </summary>
    [Test]
    procedure CompareWithPreviousSprint;
    /// <summary>Vorsprint mit 5 statt 10 Arbeitstagen: auf den Anteil am Sprint normiert.</summary>
    [Test]
    procedure CompareWithShorterSprint;
    [Test]
    procedure CompareWithoutPreviousSprint;
    [Test]
    procedure PreviousSprintsNewestLast;
    [Test]
    procedure SummaryJsonRoundTrip;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.DateUtils,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Board,
  Atlas.Core.Tracker.Sprint,
  Atlas.Core.Tracker.Providers.YouTrackBoard,
  Atlas.Core.Tracker.Providers.GitHubBoard;

const
  cDelta = 0.001;

/// <summary>Datei aus Tests\Data\&lt;AFolder&gt;, gesucht ab dem Ordner des Testprogramms aufwärts.</summary>
function Fixture(const AFolder, AName: string): string;
var
  mDirectory, mFileName: string;
begin
  mDirectory := ExtractFileDir(ParamStr(0));
  while mDirectory <> '' do
  begin
    mFileName := TPath.Combine(mDirectory, TPath.Combine('Tests', TPath.Combine('Data',
      TPath.Combine(AFolder, AName))));
    if TFile.Exists(mFileName) then
      Exit(TFile.ReadAllText(mFileName, TEncoding.UTF8));
    if ExtractFileDir(mDirectory) = mDirectory then
      Break;
    mDirectory := ExtractFileDir(mDirectory);
  end;
  raise Exception.Create('Tests\Data\' + AFolder + '\' + AName + ' nicht gefunden');
end;

function SprintOf(const AId, AName: string; AStart, AFinish: TDateTime): TAtlasBoardSprint;
begin
  Result := Default(TAtlasBoardSprint);
  Result.Id := AId;
  Result.Name := AName;
  Result.Start := AStart;
  Result.Finish := AFinish;
end;

function Card(const AKey, AState, ALogin: string; AResolved: TDateTime; APoints: Double;
  AHasPoints: Boolean): TAtlasBoardCard;
begin
  Result := Default(TAtlasBoardCard);
  Result.Key := AKey;
  Result.Title := 'Titel ' + AKey;
  Result.State := AState;
  if ALogin <> '' then
    Result.Logins := TArray<string>.Create(ALogin);
  Result.ResolvedAt := AResolved;
  Result.Points := APoints;
  Result.HasPoints := AHasPoints;
end;

/// <summary>Spalten Offen/Erledigt, Sprint 27.10.–7.11.2025, abgefragt am 31.10. 8 Uhr:
/// A erledigt 28.10. (2), B erledigt 30.10. (3), C wieder offen (5), D erledigt ohne Zeitpunkt (1),
/// E offen ohne Schätzung.</summary>
function Sample: TAtlasBoardSnapshot;
begin
  Result := TAtlasBoardSnapshot.Empty;
  Result.Columns := [TAtlasBoardColumn.Create('Offen', TArray<string>.Create('Offen'), '', False),
    TAtlasBoardColumn.Create('Erledigt', TArray<string>.Create('Erledigt'), '', True)];
  Result.Sprint := SprintOf('s3', 'Sprint 3', EncodeDate(2025, 10, 27), EncodeDate(2025, 11, 10));
  Result.PointsField := 'Story Points';
  Result.Fetched := EncodeDateTime(2025, 10, 31, 8, 0, 0, 0);
  Result.Me := 'marco';
  Result.Cards := [Card('A', 'Erledigt', 'marco', EncodeDateTime(2025, 10, 28, 15, 0, 0, 0), 2, True),
    Card('B', 'Erledigt', 'anna', EncodeDateTime(2025, 10, 30, 9, 0, 0, 0), 3, True),
    Card('C', 'Offen', 'marco', EncodeDateTime(2025, 10, 29, 9, 0, 0, 0), 5, True),
    Card('D', 'Erledigt', '', 0, 1, True),
    Card('E', 'Offen', 'anna', 0, 0, False)];
end;

function Friday: TDateTime;
begin
  Result := EncodeDateTime(2025, 10, 31, 12, 0, 0, 0);
end;

/// <summary>Abgeschlossener Sprint mit ADays Arbeitstagen, je Tag ein Punkt mehr erledigt (ATotal = ADays).
/// </summary>
function Finished(const AId, AName: string; ADays: Integer): TAtlasSprintSummary;
var
  mDay: Integer;
begin
  Result := Default(TAtlasSprintSummary);
  Result.Id := AId;
  Result.Name := AName;
  Result.Days := ADays;
  Result.Total := ADays;
  SetLength(Result.Done, ADays + 1);
  for mDay := 0 to ADays do
    Result.Done[mDay] := mDay;
end;

{ TAtlasTrackerSprintTests }

procedure TAtlasTrackerSprintTests.CalendarSprintDays;
var
  mDays: TArray<TDateTime>;
begin
  mDays := TAtlasSprintCalendar.WorkWeek.SprintDays(EncodeDate(2025, 10, 27), EncodeDate(2025, 11, 10));
  Assert.AreEqual(Integer(10), Integer(Length(mDays)));
  Assert.AreEqual(Double(EncodeDate(2025, 10, 27)), Double(mDays[0]), 1E-6);
  Assert.AreEqual(Double(EncodeDate(2025, 11, 7)), Double(mDays[9]), 1E-6, 'das Ende gehört nicht dazu');
  // Arbeitstage laut Board: Montag bis Samstag.
  mDays := TAtlasSprintCalendar.Create(TArray<Integer>.Create(1, 2, 3, 4, 5, 6)).SprintDays(
    EncodeDate(2025, 10, 27), EncodeDate(2025, 11, 10));
  Assert.AreEqual(Integer(12), Integer(Length(mDays)));
  // Nur Wochenende im Zeitraum: alle Tage zählen.
  mDays := TAtlasSprintCalendar.WorkWeek.SprintDays(EncodeDate(2025, 11, 1), EncodeDate(2025, 11, 3));
  Assert.AreEqual(Integer(2), Integer(Length(mDays)));
  // Ohne Zeitraum keine Tage.
  Assert.AreEqual(Integer(0), Integer(Length(TAtlasSprintCalendar.WorkWeek.SprintDays(0, 0))));
  Assert.AreEqual(Integer(0), Integer(Length(TAtlasSprintCalendar.WorkWeek.SprintDays(EncodeDate(2025, 11, 3),
    EncodeDate(2025, 11, 1)))));
  Assert.IsTrue(TAtlasSprintCalendar.WorkWeek.IsWorkDay(EncodeDate(2025, 10, 31)), 'Freitag');
  Assert.IsFalse(TAtlasSprintCalendar.WorkWeek.IsWorkDay(EncodeDate(2025, 11, 1)), 'Samstag');
end;

procedure TAtlasTrackerSprintTests.DaysLeftSkipsWeekends;
var
  mCalendar: TAtlasSprintCalendar;
  mStart, mFinish: TDateTime;
begin
  mCalendar := TAtlasSprintCalendar.WorkWeek;
  mStart := EncodeDate(2025, 10, 27);
  mFinish := EncodeDate(2025, 11, 10);
  Assert.AreEqual(10, mCalendar.DaysLeft(EncodeDateTime(2025, 10, 27, 7, 0, 0, 0), mStart, mFinish));
  // Donnerstag: Do, Fr und die fünf Tage der zweiten Woche.
  Assert.AreEqual(7, mCalendar.DaysLeft(EncodeDateTime(2025, 10, 30, 10, 0, 0, 0), mStart, mFinish));
  // Samstag zählt nicht.
  Assert.AreEqual(5, mCalendar.DaysLeft(EncodeDateTime(2025, 11, 1, 10, 0, 0, 0), mStart, mFinish));
  Assert.AreEqual(1, mCalendar.DaysLeft(EncodeDateTime(2025, 11, 7, 18, 0, 0, 0), mStart, mFinish));
  Assert.AreEqual(0, mCalendar.DaysLeft(EncodeDateTime(2025, 11, 10, 9, 0, 0, 0), mStart, mFinish));
  // Mit Samstag als Arbeitstag.
  mCalendar := TAtlasSprintCalendar.Create(TArray<Integer>.Create(1, 2, 3, 4, 5, 6));
  Assert.AreEqual(6, mCalendar.DaysLeft(EncodeDateTime(2025, 11, 1, 10, 0, 0, 0), mStart, mFinish));
end;

procedure TAtlasTrackerSprintTests.CalendarText;
var
  mCalendar: TAtlasSprintCalendar;
begin
  Assert.AreEqual('1,2,3,4,5', TAtlasSprintCalendar.WorkWeek.Text);
  mCalendar := TAtlasSprintCalendar.FromText(' 6, 7,6, x ');
  Assert.AreEqual('6,7', mCalendar.Text, 'doppelte und ungültige fallen weg');
  // Ohne gültigen Tag Montag bis Freitag.
  Assert.AreEqual('1,2,3,4,5', TAtlasSprintCalendar.Create(TArray<Integer>.Create(0, 8)).Text);
  Assert.AreEqual('1,2,3,4,5', TAtlasSprintCalendar.FromText('').Text);
end;

procedure TAtlasTrackerSprintTests.IdealLine;
var
  mLine: TArray<Double>;
begin
  mLine := TAtlasTrackerSprint.Ideal(10, 4);
  Assert.AreEqual(Integer(5), Integer(Length(mLine)));
  Assert.AreEqual(Double(10), mLine[0], cDelta);
  Assert.AreEqual(Double(7.5), mLine[1], cDelta);
  Assert.AreEqual(Double(5), mLine[2], cDelta);
  Assert.AreEqual(Double(0), mLine[4], cDelta, 'am letzten Arbeitstag 0');
  mLine := TAtlasTrackerSprint.Ideal(5, 0);
  Assert.AreEqual(Integer(1), Integer(Length(mLine)));
  Assert.AreEqual(Double(5), mLine[0], cDelta);
end;

procedure TAtlasTrackerSprintTests.SummarizeWithPoints;
var
  mSnapshot: TAtlasBoardSnapshot;
  mSummary: TAtlasSprintSummary;
begin
  mSnapshot := Sample;
  Assert.IsTrue(TAtlasTrackerSprint.UsesPoints(mSnapshot));
  Assert.AreEqual(Double(0), Double(TAtlasTrackerSprint.DoneAt(mSnapshot, 2, Friday)), 1E-6, 'C ist wieder offen');
  Assert.AreEqual(Double(mSnapshot.Fetched), Double(TAtlasTrackerSprint.DoneAt(mSnapshot, 3, Friday)), 1E-6,
    'D ab der Abfrage');
  mSummary := TAtlasTrackerSprint.Summarize(mSnapshot, TAtlasSprintCalendar.WorkWeek, Friday);
  Assert.IsTrue(mSummary.UsesPoints);
  Assert.AreEqual(Double(11), mSummary.Total, cDelta, 'E ohne Schätzung zählt 0');
  Assert.AreEqual(10, mSummary.Days);
  // Bis Freitag (5. Arbeitstag): k = 0 … 5.
  Assert.AreEqual(Integer(6), Integer(Length(mSummary.Done)));
  Assert.AreEqual(Double(0), mSummary.Done[0], cDelta);
  Assert.AreEqual(Double(0), mSummary.Done[1], cDelta, 'Montag: noch nichts');
  Assert.AreEqual(Double(2), mSummary.Done[2], cDelta, 'A am Dienstag');
  Assert.AreEqual(Double(2), mSummary.Done[3], cDelta);
  Assert.AreEqual(Double(5), mSummary.Done[4], cDelta, 'B am Donnerstag');
  Assert.AreEqual(Double(6), mSummary.Done[5], cDelta, 'D am Freitag');
  Assert.AreEqual(Double(6), mSummary.Velocity, cDelta);
  // Nach dem Ende alle Tage.
  mSummary := TAtlasTrackerSprint.Summarize(mSnapshot, TAtlasSprintCalendar.WorkWeek, EncodeDate(2025, 11, 20));
  Assert.AreEqual(Integer(11), Integer(Length(mSummary.Done)));
end;

procedure TAtlasTrackerSprintTests.SummarizeWithoutEstimates;
var
  mSnapshot: TAtlasBoardSnapshot;
  mSummary: TAtlasSprintSummary;
  mIndex: Integer;
begin
  mSnapshot := Sample;
  mSnapshot.PointsField := '';
  mSummary := TAtlasTrackerSprint.Summarize(mSnapshot, TAtlasSprintCalendar.WorkWeek, Friday);
  Assert.IsFalse(mSummary.UsesPoints);
  Assert.AreEqual(Double(5), mSummary.Total, cDelta, 'fünf Issues');
  Assert.AreEqual(Double(3), mSummary.Done[5], cDelta, 'A, B und D');
  // Schätzfeld da, aber keine Karte geschätzt: ebenfalls Anzahl.
  mSnapshot := Sample;
  for mIndex := 0 to High(mSnapshot.Cards) do
    mSnapshot.Cards[mIndex].HasPoints := False;
  Assert.IsFalse(TAtlasTrackerSprint.UsesPoints(mSnapshot));
  Assert.AreEqual(Double(5), TAtlasTrackerSprint.Summarize(mSnapshot, TAtlasSprintCalendar.WorkWeek,
    Friday).Total, cDelta);
end;

procedure TAtlasTrackerSprintTests.ViewNumbers;
var
  mView: TAtlasSprintView;
begin
  mView := TAtlasTrackerSprint.View(Sample, TAtlasSprintCalendar.WorkWeek, Friday, nil);
  Assert.IsTrue(mView.Known);
  Assert.AreEqual('Sprint 3', mView.Name);
  Assert.AreEqual(10, mView.DayCount);
  Assert.AreEqual(Integer(10), Integer(Length(mView.Dates)));
  Assert.AreEqual(6, mView.DaysLeft, 'Freitag zählt mit');
  Assert.AreEqual(5, mView.Today);
  Assert.IsTrue(mView.MineKnown);
  Assert.AreEqual(Integer(1), Integer(Length(mView.MineOpen)));
  Assert.AreEqual('C', mView.MineOpen[0].Key);
  Assert.AreEqual(Integer(1), Integer(Length(mView.MineDone)));
  Assert.AreEqual('A', mView.MineDone[0].Key);
  Assert.AreEqual(Double(6), mView.TeamDone, cDelta);
  Assert.AreEqual(Double(5), mView.TeamLeft, cDelta);
  Assert.AreEqual(Double(6), mView.DoneToday, cDelta);
  Assert.AreEqual(Integer(6), Integer(Length(mView.Actual)));
  Assert.AreEqual(Double(11), mView.Actual[0], cDelta);
  Assert.AreEqual(Double(5), mView.Actual[5], cDelta);
  Assert.AreEqual(Integer(11), Integer(Length(mView.Ideal)));
  Assert.AreEqual(Double(5.5), mView.Ideal[5], cDelta);
  Assert.IsFalse(mView.HasPrevious);
  // Ohne Anmeldename sind „meine“ Zahlen unbekannt.
  mView := TAtlasTrackerSprint.View(TAtlasBoardSnapshot.Empty, TAtlasSprintCalendar.WorkWeek, Friday, nil);
  Assert.IsFalse(mView.Known);
  Assert.IsFalse(mView.MineKnown);
end;

procedure TAtlasTrackerSprintTests.YouTrackFixtureCounts;
var
  mSnapshot: TAtlasBoardSnapshot;
  mCurrent: string;
  mSummary: TAtlasSprintSummary;
  mView: TAtlasSprintView;
begin
  mSnapshot := TAtlasBoardSnapshot.Empty;
  Assert.IsTrue(TAtlasYouTrackBoards.ParseAgiles(Fixture('YouTrack', 'agiles.json'), '', 'ATL', mSnapshot,
    mCurrent));
  Assert.IsTrue(TAtlasYouTrackBoards.ParseSprint(Fixture('YouTrack', 'agile-sprint.json'),
    TAtlasTrackerTarget.Create('youtrack', 'https://firma.youtrack.cloud', 'ATL', ''), mSnapshot));
  mSnapshot.Me := 'marco';
  // Sprint 42: 27.10.–9.11.2025; ATL-123 (3 Punkte, In Arbeit), ATL-124 (1,5 Stunden), ATL-125 ohne Spalte,
  // erledigt am 27.10. abends, ohne Schätzung.
  mSummary := TAtlasTrackerSprint.Summarize(mSnapshot, TAtlasSprintCalendar.WorkWeek,
    EncodeDateTime(2025, 10, 29, 12, 0, 0, 0));
  Assert.IsTrue(mSummary.UsesPoints);
  Assert.AreEqual(Double(4.5), mSummary.Total, cDelta);
  Assert.AreEqual(10, mSummary.Days);
  Assert.AreEqual(Integer(4), Integer(Length(mSummary.Done)));
  Assert.AreEqual(Double(0), mSummary.Done[3], cDelta, 'ATL-125 zählt ohne Schätzung 0');
  mView := TAtlasTrackerSprint.View(mSnapshot, TAtlasSprintCalendar.WorkWeek,
    EncodeDateTime(2025, 10, 29, 12, 0, 0, 0), nil);
  Assert.AreEqual(Integer(1), Integer(Length(mView.MineOpen)));
  Assert.AreEqual('ATL-123', mView.MineOpen[0].Key);
  Assert.AreEqual(Double(4.5), mView.TeamLeft, cDelta);
  Assert.AreEqual(8, mView.DaysLeft);
  // Ohne Schätzung als Anzahl: ATL-125 ist erledigt.
  mSnapshot.PointsField := '';
  mSummary := TAtlasTrackerSprint.Summarize(mSnapshot, TAtlasSprintCalendar.WorkWeek,
    EncodeDateTime(2025, 10, 29, 12, 0, 0, 0));
  Assert.AreEqual(Double(3), mSummary.Total, cDelta);
  Assert.AreEqual(Double(1), mSummary.Done[1], cDelta);
end;

procedure TAtlasTrackerSprintTests.GitHubFixtureCounts;
var
  mSnapshot: TAtlasBoardSnapshot;
  mSummary: TAtlasSprintSummary;
  mPrevious: TArray<TAtlasBoardSprint>;
begin
  mSnapshot := TAtlasBoardSnapshot.Empty;
  Assert.IsTrue(TAtlasGitHubBoards.ParseProject(Fixture('GitHub', 'project-v2.json'),
    TAtlasTrackerTarget.Create('github', '', 'beispiel/atlas', ''), '', EncodeDate(2026, 10, 28), mSnapshot));
  // Iteration 2: 26.10.–8.11.2026, zehn Arbeitstage; #753 mit Schätzung 3, #12 ohne.
  mSummary := TAtlasTrackerSprint.Summarize(mSnapshot, TAtlasSprintCalendar.WorkWeek,
    EncodeDateTime(2026, 10, 28, 12, 0, 0, 0));
  Assert.IsTrue(mSummary.UsesPoints);
  Assert.AreEqual(Double(3), mSummary.Total, cDelta);
  Assert.AreEqual(10, mSummary.Days);
  Assert.AreEqual(Double(0), mSummary.Velocity, cDelta);
  // Vorherige Iteration: Iteration 1 (abgeschlossen), #700 am 20.10. geschlossen.
  mPrevious := TAtlasTrackerSprint.PreviousSprints(mSnapshot.Sprints, mSnapshot.Sprint, 3);
  Assert.AreEqual(Integer(1), Integer(Length(mPrevious)));
  Assert.AreEqual('it1', mPrevious[0].Id);
  Assert.IsTrue(TAtlasGitHubBoards.ParseProject(Fixture('GitHub', 'project-v2.json'),
    TAtlasTrackerTarget.Create('github', '', 'beispiel/atlas', ''), 'it1', EncodeDate(2026, 10, 28), mSnapshot));
  mSummary := TAtlasTrackerSprint.Summarize(mSnapshot, TAtlasSprintCalendar.WorkWeek, EncodeDate(2026, 10, 28));
  Assert.IsFalse(mSummary.UsesPoints, '#700 ohne Schätzung: Anzahl');
  Assert.AreEqual(Double(1), mSummary.Velocity, cDelta);
  // Ab Montag, 12.10.: #700 am 20.10. ist am 7. Arbeitstag erledigt.
  Assert.AreEqual(Double(0), mSummary.Done[6], cDelta);
  Assert.AreEqual(Double(1), mSummary.Done[7], cDelta);
end;

procedure TAtlasTrackerSprintTests.CompareWithPreviousSprint;
var
  mView: TAtlasSprintView;
begin
  mView := TAtlasTrackerSprint.View(Sample, TAtlasSprintCalendar.WorkWeek, Friday,
    TArray<TAtlasSprintSummary>.Create(Finished('s1', 'Sprint 1', 7), Finished('s2', 'Sprint 2', 10)));
  Assert.IsTrue(mView.HasPrevious);
  Assert.AreEqual('Sprint 2', mView.PreviousName, 'der letzte ist der Vorsprint');
  // Gleiche Länge: Rest als Anteil, auf das Total dieses Sprints (11) skaliert.
  Assert.AreEqual(Integer(11), Integer(Length(mView.Previous)));
  Assert.AreEqual(Double(11), mView.Previous[0], cDelta);
  Assert.AreEqual(Double(5.5), mView.Previous[5], cDelta);
  Assert.AreEqual(Double(0), mView.Previous[10], cDelta);
  // Abweichung am selben Sprinttag (5 von 10): heute 6, Vorsprint 5.
  Assert.AreEqual(Double(5), mView.PreviousDone, cDelta);
  Assert.AreEqual(Double(6), mView.DoneToday, cDelta);
  // Velocity: ältester zuerst.
  Assert.AreEqual(Integer(2), Integer(Length(mView.Velocity)));
  Assert.AreEqual(Double(7), mView.Velocity[0], cDelta);
  Assert.AreEqual(Double(10), mView.Velocity[1], cDelta);
  Assert.AreEqual('Sprint 1', mView.VelocityNames[0]);
end;

procedure TAtlasTrackerSprintTests.CompareWithShorterSprint;
var
  mPrevious: TAtlasSprintSummary;
  mLine: TArray<Double>;
  mView: TAtlasSprintView;
begin
  // Vorsprint mit 5 Arbeitstagen, 2 Punkte je Tag: nach k von 10 Tagen gilt Tag k/2 des Vorsprints.
  mPrevious := Finished('s2', 'Sprint 2', 5);
  mPrevious.Total := 10;
  mPrevious.Done := TArray<Double>.Create(0, 2, 4, 6, 8, 10);
  mLine := TAtlasTrackerSprint.Normalized(mPrevious, 10, 20);
  Assert.AreEqual(Integer(11), Integer(Length(mLine)));
  Assert.AreEqual(Double(20), mLine[0], cDelta);
  Assert.AreEqual(Double(16), mLine[2], cDelta);
  Assert.AreEqual(Double(12), mLine[4], cDelta);
  Assert.AreEqual(Double(4), mLine[8], cDelta);
  Assert.AreEqual(Double(0), mLine[10], cDelta);
  // Gleich lang: unverändert.
  mLine := TAtlasTrackerSprint.Normalized(mPrevious, 5, 10);
  Assert.AreEqual(Double(6), mLine[2], cDelta);
  // Erledigt am selben Anteil des Sprints (auf den nächsten Tag des Vorsprints).
  mPrevious.Done := TArray<Double>.Create(0, 2, 4, 6, 8, 10);
  Assert.AreEqual(Double(10), mPrevious.DoneAt(1), cDelta);
  Assert.AreEqual(Double(0), mPrevious.DoneAt(0), cDelta);
  Assert.AreEqual(Double(4), mPrevious.DoneAt(0.4), cDelta);
  mView := TAtlasTrackerSprint.View(Sample, TAtlasSprintCalendar.WorkWeek, Friday,
    TArray<TAtlasSprintSummary>.Create(mPrevious));
  Assert.AreEqual(Integer(11), Integer(Length(mView.Previous)), 'auf die Tage dieses Sprints');
  Assert.AreEqual(Double(11 * 0.6), mView.Previous[4], cDelta);
end;

procedure TAtlasTrackerSprintTests.CompareWithoutPreviousSprint;
var
  mView: TAtlasSprintView;
begin
  mView := TAtlasTrackerSprint.View(Sample, TAtlasSprintCalendar.WorkWeek, Friday, nil);
  Assert.IsFalse(mView.HasPrevious);
  Assert.AreEqual(Integer(0), Integer(Length(mView.Previous)));
  Assert.AreEqual(Integer(0), Integer(Length(mView.Velocity)));
  Assert.AreEqual(Double(0), mView.PreviousDone, cDelta);
  // Vorsprint ohne Werte (z. B. leer): keine Linie, aber Velocity 0.
  mView := TAtlasTrackerSprint.View(Sample, TAtlasSprintCalendar.WorkWeek, Friday,
    TArray<TAtlasSprintSummary>.Create(Default(TAtlasSprintSummary)));
  Assert.IsFalse(mView.HasPrevious);
  Assert.AreEqual(Integer(1), Integer(Length(mView.Velocity)));
  Assert.AreEqual(Integer(0), Integer(Length(TAtlasTrackerSprint.Normalized(Default(TAtlasSprintSummary), 10, 5))));
end;

procedure TAtlasTrackerSprintTests.PreviousSprintsNewestLast;
var
  mSprints, mResult: TArray<TAtlasBoardSprint>;
  mCurrent: TAtlasBoardSprint;
begin
  mCurrent := SprintOf('s3', 'Sprint 3', EncodeDate(2025, 10, 27), EncodeDate(2025, 11, 10));
  mSprints := [SprintOf('s4', 'Sprint 4', EncodeDate(2025, 11, 10), EncodeDate(2025, 11, 24)),
    SprintOf('s1', 'Sprint 1', EncodeDate(2025, 9, 29), EncodeDate(2025, 10, 13)), mCurrent,
    SprintOf('s0', 'Sprint 0', EncodeDate(2025, 9, 15), EncodeDate(2025, 9, 29)),
    SprintOf('s2', 'Sprint 2', EncodeDate(2025, 10, 13), EncodeDate(2025, 10, 27)),
    SprintOf('x', 'Ohne Zeitraum', 0, 0)];
  mResult := TAtlasTrackerSprint.PreviousSprints(mSprints, mCurrent, 3);
  Assert.AreEqual(Integer(3), Integer(Length(mResult)));
  Assert.AreEqual('s0', mResult[0].Id);
  Assert.AreEqual('s1', mResult[1].Id);
  Assert.AreEqual('s2', mResult[2].Id, 'Vorsprint zuletzt');
  mResult := TAtlasTrackerSprint.PreviousSprints(mSprints, mCurrent, 1);
  Assert.AreEqual(Integer(1), Integer(Length(mResult)));
  Assert.AreEqual('s2', mResult[0].Id);
  Assert.AreEqual(Integer(0), Integer(Length(TAtlasTrackerSprint.PreviousSprints(mSprints,
    SprintOf('y', 'Ohne Start', 0, 0), 3))));
  Assert.AreEqual(Integer(0), Integer(Length(TAtlasTrackerSprint.PreviousSprints(mSprints, mCurrent, 0))));
end;

procedure TAtlasTrackerSprintTests.SummaryJsonRoundTrip;
var
  mSummary, mLoaded: TAtlasSprintSummary;
begin
  mSummary := TAtlasTrackerSprint.Summarize(Sample, TAtlasSprintCalendar.WorkWeek, EncodeDate(2025, 11, 20));
  Assert.IsTrue(TAtlasTrackerSprint.SummaryFromJson(TAtlasTrackerSprint.SummaryToJson(mSummary), mLoaded));
  Assert.AreEqual('s3', mLoaded.Id);
  Assert.AreEqual('Sprint 3', mLoaded.Name);
  Assert.AreEqual(Double(mSummary.Start), Double(mLoaded.Start), 1 / SecsPerDay);
  Assert.AreEqual(Double(mSummary.Finish), Double(mLoaded.Finish), 1 / SecsPerDay);
  Assert.IsTrue(mLoaded.UsesPoints);
  Assert.AreEqual(mSummary.Total, mLoaded.Total, cDelta);
  Assert.AreEqual(mSummary.Days, mLoaded.Days);
  Assert.AreEqual(Integer(Length(mSummary.Done)), Integer(Length(mLoaded.Done)));
  Assert.AreEqual(mSummary.Velocity, mLoaded.Velocity, cDelta);
  Assert.IsFalse(TAtlasTrackerSprint.SummaryFromJson('kaputt', mLoaded));
  Assert.IsFalse(TAtlasTrackerSprint.SummaryFromJson('{"version": 99, "id": "s3"}', mLoaded), 'andere Version');
  Assert.AreEqual('sprint-108-2-109-42', TAtlasTrackerSprint.SummaryName('108-2', '109-42'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerSprintTests);

end.
