unit Atlas.Core.Tracker.Queries.Tests;

// Tests der benannten Abfragen für „Meine Issues“ (#1262) ohne Netz und ohne
// Dateien: Liste lesen und schreiben, passende Abfragen je Projekt (Verbindung,
// Tracker-Projekt, Vorgabe des Anbieters), gewählte Abfrage mit und ohne
// Klappliste und das Merken von Wahl und Trefferzahl je Projekt. Die Übernahme
// von issues.query prüft Atlas.Core.Settings.QueryMigration.Tests.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTrackerQueriesTests = class
  public
    [Test]
    procedure ReadAndWriteRoundTrip;
    [Test]
    procedure ReadSkipsIncompleteAndDuplicateRows;
    /// <summary>Abnahme: Eine Abfrage mit Verbindung „GitHub“ erscheint in einem YouTrack-Projekt nicht.</summary>
    [Test]
    procedure AvailableFiltersByConnectionAndProject;
    /// <summary>Ohne passende eigene Abfrage gilt „Mir zugewiesen“ (Abfrage leer = Vorgabe des Anbieters).
    /// </summary>
    [Test]
    procedure AvailableFallsBackToProviderDefault;
    /// <summary>Tracker aus der .atlas (ohne benannte Verbindung): Abfrage passt über Anbieter und Server.</summary>
    [Test]
    procedure TeamTrackerMatchesByServer;
    /// <summary>Abnahme: Mit issues.queryPicker aus gilt die erste passende Abfrage.</summary>
    [Test]
    procedure ChooseHonoursPicker;
    [Test]
    procedure RenameConnectionFollows;
    /// <summary>Abnahme: Wahl und Trefferzahl je Projekt bleiben in der Zusammenfassung (nach Neustart).</summary>
    [Test]
    procedure SelectionAndCountsSurviveSummary;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.Queries,
  Atlas.Core.Welcome.Issues;

const
  cDefaultName = 'Mir zugewiesen';

function Connections: TArray<TAtlasTrackerConnection>;
begin
  Result := TArray<TAtlasTrackerConnection>.Create(
    TAtlasTrackerConnection.Create('Firma', 'youtrack', 'https://youtrack.firma.local'),
    TAtlasTrackerConnection.Create('GitHub', 'github', 'https://github.com'));
end;

function Names(const AQueries: TArray<TAtlasTrackerQuery>): string;
var
  mQuery: TAtlasTrackerQuery;
begin
  Result := '';
  for mQuery in AQueries do
    Result := Result + mQuery.Name + ';';
end;

{ TAtlasTrackerQueriesTests }

procedure TAtlasTrackerQueriesTests.ReadAndWriteRoundTrip;
var
  mQueries: TArray<TAtlasTrackerQuery>;
  mJson: string;
begin
  mJson := '[{"name": "Standard", "query": "assignee: meine #Ungelöst"}, ' +
    '{"name": "Sprint", "query": "#{Aktueller Sprint}", "connection": "Firma", "project": "KASSE"}]';
  mQueries := TAtlasTrackerQueries.Read(mJson);
  Assert.AreEqual(2, Integer(Length(mQueries)));
  Assert.AreEqual('Standard', mQueries[0].Name);
  Assert.AreEqual('', mQueries[0].Connection);
  Assert.AreEqual('Firma', mQueries[1].Connection);
  Assert.AreEqual('KASSE', mQueries[1].Project);
  Assert.AreEqual(mJson, TAtlasTrackerQueries.ToJson(mQueries), 'leere Angaben fallen weg');
  // Die Vorgabe des Anbieters wird nie gespeichert.
  Assert.AreEqual('[]', TAtlasTrackerQueries.ToJson(TArray<TAtlasTrackerQuery>.Create(
    TAtlasTrackerQuery.Fallback(cDefaultName))));
  mQueries := nil;
end;

procedure TAtlasTrackerQueriesTests.ReadSkipsIncompleteAndDuplicateRows;
var
  mQueries: TArray<TAtlasTrackerQuery>;
begin
  mQueries := TAtlasTrackerQueries.Read('[{"name": "A", "query": "x"}, {"name": "a", "query": "y"}, ' +
    '{"name": "", "query": "z"}, {"name": "B", "query": "  "}, 3, {"name": "C", "query": " c "}]');
  Assert.AreEqual('A;C;', Names(mQueries));
  Assert.AreEqual('c', mQueries[1].Query);
  Assert.AreEqual(0, Integer(Length(TAtlasTrackerQueries.Read('kein JSON'))));
  Assert.AreEqual(0, Integer(Length(TAtlasTrackerQueries.Read('{}'))));
  mQueries := nil;
end;

procedure TAtlasTrackerQueriesTests.AvailableFiltersByConnectionAndProject;
var
  mQueries: TArray<TAtlasTrackerQuery>;
  mYouTrack, mGitHub: TAtlasTrackerTarget;
begin
  mQueries := TAtlasTrackerQueries.Read('[{"name": "Überall", "query": "x"}, ' +
    '{"name": "PRs", "query": "is:pr", "connection": "GitHub"}, ' +
    '{"name": "Sprint", "query": "#{Aktueller Sprint}", "connection": "Firma"}, ' +
    '{"name": "Nur Lager", "query": "y", "connection": "Firma", "project": "LAGER"}, ' +
    '{"name": "Weg", "query": "z", "connection": "Gibt es nicht"}]');
  mYouTrack := TAtlasTrackerTarget.Create('youtrack', 'https://youtrack.firma.local', 'KASSE', '');
  mGitHub := TAtlasTrackerTarget.Create('github', 'https://github.com', 'xKnockOut/Atlas-IDE-Expert', '');
  Assert.AreEqual('Überall;Sprint;', Names(TAtlasTrackerQueries.Available(mQueries, mYouTrack, 'Firma',
    Connections, cDefaultName)));
  Assert.AreEqual('Überall;PRs;', Names(TAtlasTrackerQueries.Available(mQueries, mGitHub, 'GitHub',
    Connections, cDefaultName)));
  mYouTrack := TAtlasTrackerTarget.Create('youtrack', 'https://youtrack.firma.local', 'lager', '');
  Assert.AreEqual('Überall;Sprint;Nur Lager;', Names(TAtlasTrackerQueries.Available(mQueries, mYouTrack, 'Firma',
    Connections, cDefaultName)), 'Tracker-Projekt ohne Groß-/Kleinschreibung');
  // Ohne Tracker keine Abfragen.
  Assert.AreEqual(0, Integer(Length(TAtlasTrackerQueries.Available(mQueries, TAtlasTrackerTarget.Create('', '', '',
    ''), '', Connections, cDefaultName))));
  mQueries := nil;
end;

procedure TAtlasTrackerQueriesTests.AvailableFallsBackToProviderDefault;
var
  mAvailable: TArray<TAtlasTrackerQuery>;
begin
  mAvailable := TAtlasTrackerQueries.Available(TAtlasTrackerQueries.Read(
    '[{"name": "PRs", "query": "is:pr", "connection": "GitHub"}]'), TAtlasTrackerTarget.Create('youtrack',
    'https://youtrack.firma.local', 'KASSE', ''), 'Firma', Connections, cDefaultName);
  Assert.AreEqual(1, Integer(Length(mAvailable)));
  Assert.AreEqual(cDefaultName, mAvailable[0].Name);
  Assert.AreEqual('', mAvailable[0].Query, 'Vorgabe des Anbieters');
  Assert.IsTrue(mAvailable[0].Builtin);
  mAvailable := nil;
end;

procedure TAtlasTrackerQueriesTests.TeamTrackerMatchesByServer;
var
  mQueries: TArray<TAtlasTrackerQuery>;
begin
  mQueries := TAtlasTrackerQueries.Read('[{"name": "Sprint", "query": "s", "connection": "Firma"}]');
  // .atlas nennt denselben Server (mit „/“ am Ende): die Abfrage der Verbindung „Firma“ passt.
  Assert.AreEqual('Sprint;', Names(TAtlasTrackerQueries.Available(mQueries, TAtlasTrackerTarget.Create('youtrack',
    'https://YouTrack.firma.local/', 'KASSE', ''), 'Kasse', Connections, cDefaultName)));
  Assert.AreEqual(cDefaultName + ';', Names(TAtlasTrackerQueries.Available(mQueries,
    TAtlasTrackerTarget.Create('youtrack', 'https://anderer.firma.local', 'KASSE', ''), 'Kasse', Connections,
    cDefaultName)), 'anderer Server');
  mQueries := nil;
end;

procedure TAtlasTrackerQueriesTests.ChooseHonoursPicker;
var
  mQueries: TArray<TAtlasTrackerQuery>;
begin
  mQueries := TAtlasTrackerQueries.Read('[{"name": "A", "query": "a"}, {"name": "B", "query": "b"}]');
  Assert.AreEqual(1, TAtlasTrackerQueries.Choose(mQueries, 'b', True));
  Assert.AreEqual(0, TAtlasTrackerQueries.Choose(mQueries, 'b', False), 'ohne Klappliste die erste');
  Assert.AreEqual(0, TAtlasTrackerQueries.Choose(mQueries, 'Gelöscht', True), 'gewählte gibt es nicht mehr');
  Assert.AreEqual(0, TAtlasTrackerQueries.Choose(mQueries, '', True));
  Assert.AreEqual(-1, TAtlasTrackerQueries.Choose(nil, 'A', True));
  mQueries := nil;
end;

procedure TAtlasTrackerQueriesTests.RenameConnectionFollows;
var
  mQueries: TArray<TAtlasTrackerQuery>;
begin
  mQueries := TAtlasTrackerQueries.Read('[{"name": "A", "query": "a", "connection": "Firma"}, ' +
    '{"name": "B", "query": "b"}]');
  TAtlasTrackerQueries.RenameConnection(mQueries, 'firma', 'Werk');
  Assert.AreEqual('Werk', mQueries[0].Connection);
  Assert.AreEqual('', mQueries[1].Connection, 'ohne Verbindung bleibt ohne');
  mQueries := nil;
end;

procedure TAtlasTrackerQueriesTests.SelectionAndCountsSurviveSummary;
var
  mState, mLoaded: TAtlasIssuesState;
  mQueries: TArray<TAtlasTrackerQuery>;
  mCounts: TArray<Integer>;
begin
  mState := TAtlasIssuesState.Empty;
  mState.Selected := 'Sprint';
  mState.SetCount('Sprint', 3);
  mState.SetCount('Standard', 12);
  mState.SetCount('sprint', 4);
  Assert.IsTrue(TAtlasWelcomeIssues.FromJson(TAtlasWelcomeIssues.ToJson(mState), mLoaded));
  Assert.AreEqual('Sprint', mLoaded.Selected);
  Assert.AreEqual(4, mLoaded.CountOf('SPRINT'), 'je Name einmal, ohne Groß-/Kleinschreibung');
  Assert.AreEqual(12, mLoaded.CountOf('Standard'));
  Assert.AreEqual(-1, mLoaded.CountOf('Neu'));
  mQueries := TAtlasTrackerQueries.Read('[{"name": "Standard", "query": "a"}, {"name": "Neu", "query": "b"}, ' +
    '{"name": "Sprint", "query": "c"}]');
  mCounts := TAtlasWelcomeIssues.QueryCounts(mLoaded, mQueries);
  Assert.AreEqual(3, Integer(Length(mCounts)));
  Assert.AreEqual(12, mCounts[0]);
  Assert.AreEqual(-1, mCounts[1]);
  Assert.AreEqual(4, mCounts[2]);
  Assert.AreEqual(2, TAtlasTrackerQueries.Choose(mQueries, mLoaded.Selected, True));
  mQueries := nil;
  mCounts := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerQueriesTests);

end.
