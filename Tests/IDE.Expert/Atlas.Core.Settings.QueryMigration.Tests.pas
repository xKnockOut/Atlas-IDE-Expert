unit Atlas.Core.Settings.QueryMigration.Tests;

// Tests der Übernahme von issues.query bzw. welcomePage.issues.query als
// Abfrage „Standard“ vorn in issues.queries (#1262), ohne Dateien.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSettingsQueryMigrationTests = class
  public
    /// <summary>Abnahme: welcomePage.issues.query wird „Standard“ vorn in der Liste und ist gewählt.</summary>
    [Test]
    procedure MigrateMakesStandardQuery;
    [Test]
    procedure MigrateKeepsExistingStandard;
    /// <summary>Vorhandene Zeilen bleiben samt Verbindung, Projekt und Umlauten erhalten.</summary>
    [Test]
    procedure WithLegacyKeepsRows;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.History,
  Atlas.Core.Settings.QueryMigration,
  Atlas.Core.Tracker.Queries;

function Names(const AQueries: TArray<TAtlasTrackerQuery>): string;
var
  mQuery: TAtlasTrackerQuery;
begin
  Result := '';
  for mQuery in AQueries do
    Result := Result + mQuery.Name + ';';
end;

{ TAtlasSettingsQueryMigrationTests }

procedure TAtlasSettingsQueryMigrationTests.MigrateMakesStandardQuery;
var
  mStore: IAtlasMemorySettingsStore;
  mMigration: TAtlasSettingsQueryMigration;
  mQueries: TArray<TAtlasTrackerQuery>;
begin
  mStore := TAtlasMemorySettingsStore.Create;
  mStore.WriteString('WelcomePageIssuesQuery', 'assignee: meine #Ungelöst');
  mStore.WriteString('IssuesQueries', '[{"name": "Sprint", "query": "s"}]');
  mMigration := TAtlasSettingsQueryMigrations.Migrate(mStore, mStore as IAtlasSettingsNames, mStore);
  Assert.IsTrue(mMigration.Found);
  Assert.IsTrue(mMigration.Moved);
  Assert.AreEqual('welcomePage.issues.query', mMigration.OldKey);
  Assert.IsTrue((mStore as IAtlasSettingsNames).Contains('WelcomePageIssuesQuery'), 'erst nach dem Speichern weg');
  TAtlasSettingsQueryMigrations.RemoveLegacy(mStore as IAtlasSettingsNames);
  Assert.IsFalse((mStore as IAtlasSettingsNames).Contains('WelcomePageIssuesQuery'));
  mQueries := TAtlasTrackerQueries.Read(mStore.ReadString('IssuesQueries', ''));
  Assert.AreEqual('Standard;Sprint;', Names(mQueries), 'vorn, damit sie ohne Wahl gilt');
  Assert.AreEqual('assignee: meine #Ungelöst', mQueries[0].Query);
  Assert.AreEqual(0, TAtlasTrackerQueries.Choose(mQueries, '', True), 'Standard gewählt');
  // Zweiter Start: nichts mehr zu tun.
  mMigration := TAtlasSettingsQueryMigrations.Migrate(mStore, mStore as IAtlasSettingsNames, mStore);
  Assert.IsFalse(mMigration.Found);
  // issues.query (#1280) vor dem älteren Namen.
  mStore := TAtlasMemorySettingsStore.Create;
  mStore.WriteString('IssuesQuery', 'label:bug');
  mStore.WriteString('WelcomePageIssuesQuery', 'alt');
  mMigration := TAtlasSettingsQueryMigrations.Migrate(mStore, mStore as IAtlasSettingsNames, mStore);
  Assert.AreEqual('issues.query', mMigration.OldKey);
  Assert.AreEqual('[{"name": "Standard", "query": "label:bug"}]', mStore.ReadString('IssuesQueries', ''));
  TAtlasSettingsQueryMigrations.RemoveLegacy(mStore as IAtlasSettingsNames);
  Assert.IsFalse((mStore as IAtlasSettingsNames).Contains('WelcomePageIssuesQuery'), 'beide Namen weg');
  mQueries := nil;
end;

procedure TAtlasSettingsQueryMigrationTests.MigrateKeepsExistingStandard;
var
  mStore: IAtlasMemorySettingsStore;
  mMigration: TAtlasSettingsQueryMigration;
begin
  mStore := TAtlasMemorySettingsStore.Create;
  mStore.WriteString('IssuesQuery', 'alt');
  mStore.WriteString('IssuesQueries', '[{"name": "standard", "query": "neu"}]');
  mMigration := TAtlasSettingsQueryMigrations.Migrate(mStore, mStore as IAtlasSettingsNames, mStore);
  Assert.IsTrue(mMigration.Found);
  Assert.IsFalse(mMigration.Moved);
  Assert.AreEqual('[{"name": "standard", "query": "neu"}]', mStore.ReadString('IssuesQueries', ''));
  Assert.AreEqual('Einstellung issues.query entfällt (issues.queries gilt)', mMigration.LogLine);
  // Leere frühere Abfrage: nur der Name geht.
  mStore := TAtlasMemorySettingsStore.Create;
  mStore.WriteString('IssuesQuery', '');
  mMigration := TAtlasSettingsQueryMigrations.Migrate(mStore, mStore as IAtlasSettingsNames, mStore);
  Assert.IsTrue(mMigration.Found);
  Assert.IsFalse(mMigration.Moved);
  Assert.AreEqual('[]', TAtlasSettingsQueryMigrations.WithLegacy('[]', '  '));
end;

procedure TAtlasSettingsQueryMigrationTests.WithLegacyKeepsRows;
var
  mQueries: TArray<TAtlasTrackerQuery>;
begin
  mQueries := TAtlasTrackerQueries.Read(TAtlasSettingsQueryMigrations.WithLegacy(
    '[{"name": "Sprint", "query": "Sprint: {Aktuell}", "connection": "Firma", "project": "ATL"}, ' +
    '{"name": "Gelöst", "query": "#Gelöst"}]', 'mehr' + #13#10 + 'zeilig'));
  Assert.AreEqual('Standard;Sprint;Gelöst;', Names(mQueries));
  Assert.AreEqual('mehr zeilig', mQueries[0].Query, 'einzeilig');
  Assert.AreEqual('Firma', mQueries[1].Connection);
  Assert.AreEqual('ATL', mQueries[1].Project);
  Assert.AreEqual('#Gelöst', mQueries[2].Query);
  // Ungültiger oder leerer Text: nur „Standard“.
  Assert.AreEqual('[{"name": "Standard", "query": "a"}]', TAtlasSettingsQueryMigrations.WithLegacy('kein JSON', 'a'));
  Assert.AreEqual('[{"name": "Standard", "query": "a"}]', TAtlasSettingsQueryMigrations.WithLegacy('', 'a'));
  // Eine Zeile „Standard“ ohne Abfrage zählt nicht (TAtlasTrackerQueries.Read lässt sie weg).
  mQueries := TAtlasTrackerQueries.Read(TAtlasSettingsQueryMigrations.WithLegacy(
    '[{"name": "Standard", "query": ""}]', 'b'));
  Assert.AreEqual('Standard;', Names(mQueries));
  Assert.AreEqual('b', mQueries[0].Query);
  mQueries := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsQueryMigrationTests);

end.
