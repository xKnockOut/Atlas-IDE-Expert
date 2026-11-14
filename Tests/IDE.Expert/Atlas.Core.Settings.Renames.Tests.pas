unit Atlas.Core.Settings.Renames.Tests;

// Übernahme umbenannter Plugin-Einstellungen (#1280, x-renamedFrom): nur alter
// Name, nur neuer, beide, Wert der falschen Art, Wahrheitswert und leerer Text,
// zweiter Lauf ohne Wirkung, Protokollzeilen; dazu der echte Katalog mit den
// früheren Namen von „Meine Issues“ (welcomePage.issues.* → issues.*), der
// Import älterer Dateien und gemerkte Einstellungsstände von vor der Umbenennung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSettingsRenamesTests = class
  public
    [Test]
    procedure OnlyOldNameMoves;
    [Test]
    procedure OnlyNewNameIsLeftAlone;
    [Test]
    procedure BothNamesNewWins;
    [Test]
    procedure WrongKindIsDropped;
    [Test]
    procedure FalseAndEmptyTextMove;
    [Test]
    procedure SecondRunFindsNothing;
    [Test]
    procedure RealCatalogMovesTrackerSettings;
    [Test]
    procedure RealCatalogHasNoWelcomeTrackerKeys;
    [Test]
    procedure ImportResolvesFormerNames;
    [Test]
    procedure HistoryKeepsTrackerValues;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Catalog,
  Atlas.Core.Settings.History,
  Atlas.Core.Settings.Renames,
  Atlas.Core.Settings.QueryMigration;

/// <summary>Katalog mit Text-, Wahrheits- und Zahleinstellung unter neuem Namen, je mit früherem Namen.</summary>
function TestCatalog: TAtlasSettingsCatalog;
begin
  Result := TAtlasSettingsCatalog.Create('{"x-areas":{"issues":{"caption":"Issue-Tracker"}},"properties":{' +
    '"Query":{"type":"string","default":"","x-key":"issues.query","x-area":"issues","x-page":"Issue-Tracker",' +
    '"x-formerKeys":["welcome.query"],"x-renamedFrom":["OldQuery"]},' +
    '"Login":{"type":"boolean","default":true,"x-key":"issues.login","x-area":"issues","x-page":"Issue-Tracker",' +
    '"x-renamedFrom":["OldLogin"]},' +
    '"Rows":{"type":"integer","default":5,"x-key":"issues.rows","x-area":"issues","x-page":"Issue-Tracker",' +
    '"x-formerKeys":["welcome.rows"],"x-renamedFrom":["OldRows"]}}}', '{}');
end;

function NewStore: IAtlasMemorySettingsStore;
begin
  Result := TAtlasMemorySettingsStore.Create;
end;

function Apply(const AStore: IAtlasMemorySettingsStore; ACatalog: TAtlasSettingsCatalog): TArray<TAtlasSettingsRename>;
begin
  Result := TAtlasSettingsRenames.Apply(AStore, AStore as IAtlasSettingsNames, ACatalog);
end;

{ TAtlasSettingsRenamesTests }

procedure TAtlasSettingsRenamesTests.OnlyOldNameMoves;
var
  mCatalog: TAtlasSettingsCatalog;
  mStore: IAtlasMemorySettingsStore;
  mRenames: TArray<TAtlasSettingsRename>;
begin
  mCatalog := TestCatalog;
  try
    mStore := NewStore;
    mStore.WriteString('OldQuery', 'assignee: meine #Ungelöst');
    mStore.WriteInteger('OldRows', 12);
    mRenames := Apply(mStore, mCatalog);
    Assert.AreEqual(2, Integer(Length(mRenames)));
    Assert.AreEqual(Ord(srMoved), Ord(mRenames[0].Outcome));
    Assert.AreEqual('OldQuery', mRenames[0].OldName);
    Assert.AreEqual('Query', mRenames[0].NewName);
    Assert.AreEqual('assignee: meine #Ungelöst', mStore.ReadString('Query', ''));
    Assert.AreEqual(12, mStore.ReadInteger('Rows', 0));
    Assert.IsFalse((mStore as IAtlasSettingsNames).Contains('OldQuery'), 'alter Name entfernt');
    Assert.IsFalse((mStore as IAtlasSettingsNames).Contains('OldRows'));
    Assert.AreEqual('Einstellung welcome.query heißt jetzt issues.query; Wert übernommen', mRenames[0].LogLine);
    Assert.AreEqual('Einstellung welcome.rows heißt jetzt issues.rows; Wert übernommen', mRenames[1].LogLine);
  finally
    mCatalog.Free;
  end;
end;

procedure TAtlasSettingsRenamesTests.OnlyNewNameIsLeftAlone;
var
  mCatalog: TAtlasSettingsCatalog;
  mStore: IAtlasMemorySettingsStore;
begin
  mCatalog := TestCatalog;
  try
    mStore := NewStore;
    mStore.WriteString('Query', 'label:bug');
    Assert.AreEqual(0, Integer(Length(Apply(mStore, mCatalog))));
    Assert.AreEqual('label:bug', mStore.ReadString('Query', ''));
  finally
    mCatalog.Free;
  end;
end;

procedure TAtlasSettingsRenamesTests.BothNamesNewWins;
var
  mCatalog: TAtlasSettingsCatalog;
  mStore: IAtlasMemorySettingsStore;
  mRenames: TArray<TAtlasSettingsRename>;
begin
  mCatalog := TestCatalog;
  try
    mStore := NewStore;
    mStore.WriteString('OldQuery', 'alt');
    mStore.WriteString('Query', 'neu');
    mRenames := Apply(mStore, mCatalog);
    Assert.AreEqual(1, Integer(Length(mRenames)));
    Assert.AreEqual(Ord(srSuperseded), Ord(mRenames[0].Outcome));
    Assert.AreEqual('neu', mStore.ReadString('Query', ''));
    Assert.IsFalse((mStore as IAtlasSettingsNames).Contains('OldQuery'), 'alter Name entfernt');
    Assert.IsTrue(mRenames[0].LogLine.StartsWith('Warnung: Einstellung issues.query '), mRenames[0].LogLine);
  finally
    mCatalog.Free;
  end;
end;

procedure TAtlasSettingsRenamesTests.WrongKindIsDropped;
var
  mCatalog: TAtlasSettingsCatalog;
  mStore: IAtlasMemorySettingsStore;
  mRenames: TArray<TAtlasSettingsRename>;
begin
  mCatalog := TestCatalog;
  try
    mStore := NewStore;
    // Zahl statt Text und Text statt Wahrheitswert.
    mStore.WriteInteger('OldQuery', 7);
    mStore.WriteString('OldLogin', 'ja');
    mRenames := Apply(mStore, mCatalog);
    Assert.AreEqual(2, Integer(Length(mRenames)));
    Assert.AreEqual(Ord(srInvalid), Ord(mRenames[0].Outcome));
    Assert.AreEqual(Ord(srInvalid), Ord(mRenames[1].Outcome));
    Assert.IsFalse((mStore as IAtlasSettingsNames).Contains('Query'), 'nichts übernommen');
    Assert.IsFalse((mStore as IAtlasSettingsNames).Contains('Login'));
    Assert.IsFalse((mStore as IAtlasSettingsNames).Contains('OldQuery'), 'ungültiger Wert entfernt');
    Assert.IsFalse((mStore as IAtlasSettingsNames).Contains('OldLogin'));
    Assert.IsTrue(mRenames[0].LogLine.StartsWith('Warnung: '), mRenames[0].LogLine);
  finally
    mCatalog.Free;
  end;
end;

procedure TAtlasSettingsRenamesTests.FalseAndEmptyTextMove;
var
  mCatalog: TAtlasSettingsCatalog;
  mStore: IAtlasMemorySettingsStore;
  mRenames: TArray<TAtlasSettingsRename>;
begin
  mCatalog := TestCatalog;
  try
    mStore := NewStore;
    // Werte gleich der Lesevorgabe: aus und leerer Text sind gültig und werden übernommen.
    mStore.WriteInteger('OldLogin', 0);
    mStore.WriteString('OldQuery', '');
    mRenames := Apply(mStore, mCatalog);
    Assert.AreEqual(2, Integer(Length(mRenames)));
    Assert.AreEqual(Ord(srMoved), Ord(mRenames[0].Outcome));
    Assert.AreEqual(Ord(srMoved), Ord(mRenames[1].Outcome));
    Assert.AreEqual(0, mStore.ReadInteger('Login', 1));
    Assert.IsTrue((mStore as IAtlasSettingsNames).Contains('Query'));
    Assert.AreEqual('', mStore.ReadString('Query', 'Vorgabe'));
    // Ohne x-formerKeys nennt das Protokoll den früheren Namen.
    Assert.AreEqual('Einstellung OldLogin heißt jetzt issues.login; Wert übernommen', mRenames[1].LogLine);
  finally
    mCatalog.Free;
  end;
end;

procedure TAtlasSettingsRenamesTests.SecondRunFindsNothing;
var
  mCatalog: TAtlasSettingsCatalog;
  mStore: IAtlasMemorySettingsStore;
begin
  mCatalog := TestCatalog;
  try
    mStore := NewStore;
    mStore.WriteString('OldQuery', 'x');
    Assert.AreEqual(1, Integer(Length(Apply(mStore, mCatalog))));
    Assert.AreEqual(0, Integer(Length(Apply(mStore, mCatalog))), 'Protokoll nur einmal');
    Assert.AreEqual('x', mStore.ReadString('Query', ''));
  finally
    mCatalog.Free;
  end;
end;

procedure TAtlasSettingsRenamesTests.RealCatalogMovesTrackerSettings;
var
  mCatalog: TAtlasSettingsCatalog;
  mStore: IAtlasMemorySettingsStore;
  mRenames: TArray<TAtlasSettingsRename>;
  mSettings: TAtlasPluginSettings;
  mMigration: TAtlasSettingsQueryMigration;
begin
  mCatalog := TAtlasSettingsCatalog.CreateDefault;
  try
    mStore := NewStore;
    mStore.WriteInteger('WelcomePageIssues', 1);
    mStore.WriteString('WelcomePageIssuesTracker', 'youtrack');
    mStore.WriteString('WelcomePageIssuesQuery', 'assignee: meine #Ungelöst');
    mStore.WriteString('WelcomePageIssuesStart', 'remember');
    mStore.WriteString('WelcomePageIssuesBranchPattern', 'bugfix/{kennung}');
    mStore.WriteString('WelcomePageIssuesBranchBase', 'develop');
    mStore.WriteString('WelcomePageIssuesCommitPattern', '[{kennung}] ');
    mStore.WriteInteger('TrackerLogin', 0);
    mRenames := Apply(mStore, mCatalog);
    // Die Abfrage übernimmt seit #1262 TAtlasSettingsQueryMigrations (als „Standard“ in issues.queries).
    Assert.AreEqual(5, Integer(Length(mRenames)), 'je früherem Namen eine Übernahme');
    Assert.IsTrue((mStore as IAtlasSettingsNames).Contains('WelcomePageIssuesQuery'));
    mMigration := TAtlasSettingsQueryMigrations.Migrate(mStore, mStore as IAtlasSettingsNames, mStore);
    Assert.IsTrue(mMigration.Found);
    Assert.IsTrue(mMigration.Moved);
    TAtlasSettingsQueryMigrations.RemoveLegacy(mStore as IAtlasSettingsNames);
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.Load(mStore);
    Assert.IsTrue(mSettings.WelcomePageIssues, 'Schalter des Bereichs bleibt');
    Assert.AreEqual('youtrack', mSettings.IssuesTracker);
    Assert.AreEqual('[{"name": "Standard", "query": "assignee: meine #Ungelöst"}]', mSettings.IssuesQueries);
    Assert.AreEqual('remember', mSettings.IssuesStart);
    Assert.AreEqual('bugfix/{kennung}', mSettings.IssuesBranchPattern);
    Assert.AreEqual('develop', mSettings.IssuesBranchBase);
    Assert.AreEqual('[{kennung}] ', mSettings.IssuesCommitPattern);
    Assert.IsFalse(mSettings.TrackerLogin, 'Registry-Name unverändert');
    Assert.IsFalse((mStore as IAtlasSettingsNames).Contains('WelcomePageIssuesQuery'));
    Assert.AreEqual('Einstellung welcomePage.issues.tracker heißt jetzt issues.tracker; Wert übernommen',
      mRenames[0].LogLine);
    Assert.AreEqual('Einstellung welcomePage.issues.query ist jetzt die Abfrage „Standard“ in issues.queries',
      mMigration.LogLine);
  finally
    mCatalog.Free;
  end;
end;

procedure TAtlasSettingsRenamesTests.RealCatalogHasNoWelcomeTrackerKeys;
var
  mCatalog: TAtlasSettingsCatalog;
  mIndex: Integer;
  mEntry: TAtlasCatalogEntry;
begin
  mCatalog := TAtlasSettingsCatalog.CreateDefault;
  try
    for mIndex := 0 to mCatalog.Count - 1 do
    begin
      mEntry := mCatalog[mIndex];
      // Nur der Schalter des Bereichs bleibt unter welcomePage.issues (#1280).
      Assert.IsFalse(mEntry.Key.StartsWith('welcomePage.issues.'), mEntry.Key);
      if mEntry.Key.StartsWith('issues.') then
      begin
        Assert.AreEqual('issues', mEntry.Area, mEntry.Key);
        Assert.AreEqual('Issue-Tracker', mEntry.Page, mEntry.Key);
      end;
    end;
    Assert.IsTrue(mCatalog.HasArea('issues'));
    Assert.AreEqual('Issue-Tracker', mCatalog.AreaCaption('issues', False));
    Assert.AreEqual('Issue tracker', mCatalog.AreaCaption('issues', True));
    Assert.IsTrue(mCatalog.IndexOfKey('issues.login') >= 0);
    Assert.AreEqual('TrackerLogin', mCatalog[mCatalog.IndexOfKey('issues.login')].Name);
    Assert.IsTrue(mCatalog.IndexOfKey('welcomePage.issues') >= 0, 'Schalter des Bereichs');
  finally
    mCatalog.Free;
  end;
end;

procedure TAtlasSettingsRenamesTests.ImportResolvesFormerNames;
var
  mCatalog: TAtlasSettingsCatalog;
  mMigrated: Boolean;
  mExpected: Integer;
begin
  mCatalog := TAtlasSettingsCatalog.CreateDefault;
  try
    // issues.query (#1280) geht seit #1262 in issues.queries auf.
    mExpected := mCatalog.IndexOfKey('issues.queries');
    Assert.IsTrue(mExpected >= 0);
    Assert.IsTrue(mCatalog.IndexOfKey('issues.query') < 0);
    Assert.AreEqual(mExpected, mCatalog.Resolve('issues.query', mMigrated));
    Assert.IsTrue(mMigrated);
    // Exportdatei vor #1280 (früherer Schlüssel) und ältere flache Datei (früherer Registry-Name).
    Assert.AreEqual(mExpected, mCatalog.Resolve('welcomePage.issues.query', mMigrated));
    Assert.IsTrue(mMigrated);
    Assert.AreEqual(mExpected, mCatalog.Resolve('WelcomePageIssuesQuery', mMigrated));
    Assert.IsTrue(mMigrated);
    Assert.AreEqual(mCatalog.IndexOfKey('issues.login'), mCatalog.Resolve('welcomePage.issues.login', mMigrated));
    Assert.IsTrue(mMigrated);
  finally
    mCatalog.Free;
  end;
end;

procedure TAtlasSettingsRenamesTests.HistoryKeepsTrackerValues;
var
  mHistory: TAtlasSettingsHistory;
begin
  mHistory := TAtlasSettingsHistory.Create;
  try
    Assert.IsTrue(mHistory.LoadJson('[{"changedAt":"2026-10-27T10:00:00.000Z","settings":' +
      '{"WelcomePageIssuesQuery":"label:bug","WelcomePageIssuesTracker":"github"}}]'));
    Assert.AreEqual(1, mHistory.Count);
    Assert.AreEqual('[{"name": "Standard", "query": "label:bug"}]', mHistory[0].Settings.IssuesQueries);
    Assert.AreEqual('github', mHistory[0].Settings.IssuesTracker);
  finally
    mHistory.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsRenamesTests);

end.
