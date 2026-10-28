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
  Atlas.Core.Settings.Renames;

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
  Catalog: TAtlasSettingsCatalog;
  Store: IAtlasMemorySettingsStore;
  Renames: TArray<TAtlasSettingsRename>;
begin
  Catalog := TestCatalog;
  try
    Store := NewStore;
    Store.WriteString('OldQuery', 'assignee: meine #Ungelöst');
    Store.WriteInteger('OldRows', 12);
    Renames := Apply(Store, Catalog);
    Assert.AreEqual(2, Integer(Length(Renames)));
    Assert.AreEqual(Ord(srMoved), Ord(Renames[0].Outcome));
    Assert.AreEqual('OldQuery', Renames[0].OldName);
    Assert.AreEqual('Query', Renames[0].NewName);
    Assert.AreEqual('assignee: meine #Ungelöst', Store.ReadString('Query', ''));
    Assert.AreEqual(12, Store.ReadInteger('Rows', 0));
    Assert.IsFalse((Store as IAtlasSettingsNames).Contains('OldQuery'), 'alter Name entfernt');
    Assert.IsFalse((Store as IAtlasSettingsNames).Contains('OldRows'));
    Assert.AreEqual('Einstellung welcome.query heißt jetzt issues.query; Wert übernommen', Renames[0].LogLine);
    Assert.AreEqual('Einstellung welcome.rows heißt jetzt issues.rows; Wert übernommen', Renames[1].LogLine);
  finally
    Catalog.Free;
  end;
end;

procedure TAtlasSettingsRenamesTests.OnlyNewNameIsLeftAlone;
var
  Catalog: TAtlasSettingsCatalog;
  Store: IAtlasMemorySettingsStore;
begin
  Catalog := TestCatalog;
  try
    Store := NewStore;
    Store.WriteString('Query', 'label:bug');
    Assert.AreEqual(0, Integer(Length(Apply(Store, Catalog))));
    Assert.AreEqual('label:bug', Store.ReadString('Query', ''));
  finally
    Catalog.Free;
  end;
end;

procedure TAtlasSettingsRenamesTests.BothNamesNewWins;
var
  Catalog: TAtlasSettingsCatalog;
  Store: IAtlasMemorySettingsStore;
  Renames: TArray<TAtlasSettingsRename>;
begin
  Catalog := TestCatalog;
  try
    Store := NewStore;
    Store.WriteString('OldQuery', 'alt');
    Store.WriteString('Query', 'neu');
    Renames := Apply(Store, Catalog);
    Assert.AreEqual(1, Integer(Length(Renames)));
    Assert.AreEqual(Ord(srSuperseded), Ord(Renames[0].Outcome));
    Assert.AreEqual('neu', Store.ReadString('Query', ''));
    Assert.IsFalse((Store as IAtlasSettingsNames).Contains('OldQuery'), 'alter Name entfernt');
    Assert.IsTrue(Renames[0].LogLine.StartsWith('Warnung: Einstellung issues.query '), Renames[0].LogLine);
  finally
    Catalog.Free;
  end;
end;

procedure TAtlasSettingsRenamesTests.WrongKindIsDropped;
var
  Catalog: TAtlasSettingsCatalog;
  Store: IAtlasMemorySettingsStore;
  Renames: TArray<TAtlasSettingsRename>;
begin
  Catalog := TestCatalog;
  try
    Store := NewStore;
    // Zahl statt Text und Text statt Wahrheitswert.
    Store.WriteInteger('OldQuery', 7);
    Store.WriteString('OldLogin', 'ja');
    Renames := Apply(Store, Catalog);
    Assert.AreEqual(2, Integer(Length(Renames)));
    Assert.AreEqual(Ord(srInvalid), Ord(Renames[0].Outcome));
    Assert.AreEqual(Ord(srInvalid), Ord(Renames[1].Outcome));
    Assert.IsFalse((Store as IAtlasSettingsNames).Contains('Query'), 'nichts übernommen');
    Assert.IsFalse((Store as IAtlasSettingsNames).Contains('Login'));
    Assert.IsFalse((Store as IAtlasSettingsNames).Contains('OldQuery'), 'ungültiger Wert entfernt');
    Assert.IsFalse((Store as IAtlasSettingsNames).Contains('OldLogin'));
    Assert.IsTrue(Renames[0].LogLine.StartsWith('Warnung: '), Renames[0].LogLine);
  finally
    Catalog.Free;
  end;
end;

procedure TAtlasSettingsRenamesTests.FalseAndEmptyTextMove;
var
  Catalog: TAtlasSettingsCatalog;
  Store: IAtlasMemorySettingsStore;
  Renames: TArray<TAtlasSettingsRename>;
begin
  Catalog := TestCatalog;
  try
    Store := NewStore;
    // Werte gleich der Lesevorgabe: aus und leerer Text sind gültig und werden übernommen.
    Store.WriteInteger('OldLogin', 0);
    Store.WriteString('OldQuery', '');
    Renames := Apply(Store, Catalog);
    Assert.AreEqual(2, Integer(Length(Renames)));
    Assert.AreEqual(Ord(srMoved), Ord(Renames[0].Outcome));
    Assert.AreEqual(Ord(srMoved), Ord(Renames[1].Outcome));
    Assert.AreEqual(0, Store.ReadInteger('Login', 1));
    Assert.IsTrue((Store as IAtlasSettingsNames).Contains('Query'));
    Assert.AreEqual('', Store.ReadString('Query', 'Vorgabe'));
    // Ohne x-formerKeys nennt das Protokoll den früheren Namen.
    Assert.AreEqual('Einstellung OldLogin heißt jetzt issues.login; Wert übernommen', Renames[1].LogLine);
  finally
    Catalog.Free;
  end;
end;

procedure TAtlasSettingsRenamesTests.SecondRunFindsNothing;
var
  Catalog: TAtlasSettingsCatalog;
  Store: IAtlasMemorySettingsStore;
begin
  Catalog := TestCatalog;
  try
    Store := NewStore;
    Store.WriteString('OldQuery', 'x');
    Assert.AreEqual(1, Integer(Length(Apply(Store, Catalog))));
    Assert.AreEqual(0, Integer(Length(Apply(Store, Catalog))), 'Protokoll nur einmal');
    Assert.AreEqual('x', Store.ReadString('Query', ''));
  finally
    Catalog.Free;
  end;
end;

procedure TAtlasSettingsRenamesTests.RealCatalogMovesTrackerSettings;
var
  Catalog: TAtlasSettingsCatalog;
  Store: IAtlasMemorySettingsStore;
  Renames: TArray<TAtlasSettingsRename>;
  Settings: TAtlasPluginSettings;
begin
  Catalog := TAtlasSettingsCatalog.CreateDefault;
  try
    Store := NewStore;
    Store.WriteInteger('WelcomePageIssues', 1);
    Store.WriteString('WelcomePageIssuesTracker', 'youtrack');
    Store.WriteString('WelcomePageIssuesQuery', 'assignee: meine #Ungelöst');
    Store.WriteString('WelcomePageIssuesStart', 'remember');
    Store.WriteString('WelcomePageIssuesBranchPattern', 'bugfix/{kennung}');
    Store.WriteString('WelcomePageIssuesBranchBase', 'develop');
    Store.WriteString('WelcomePageIssuesCommitPattern', '[{kennung}] ');
    Store.WriteInteger('TrackerLogin', 0);
    Renames := Apply(Store, Catalog);
    Assert.AreEqual(6, Integer(Length(Renames)), 'je früherem Namen eine Übernahme');
    Settings := TAtlasPluginSettings.Defaults;
    Settings.Load(Store);
    Assert.IsTrue(Settings.WelcomePageIssues, 'Schalter des Bereichs bleibt');
    Assert.AreEqual('youtrack', Settings.IssuesTracker);
    Assert.AreEqual('assignee: meine #Ungelöst', Settings.IssuesQuery);
    Assert.AreEqual('remember', Settings.IssuesStart);
    Assert.AreEqual('bugfix/{kennung}', Settings.IssuesBranchPattern);
    Assert.AreEqual('develop', Settings.IssuesBranchBase);
    Assert.AreEqual('[{kennung}] ', Settings.IssuesCommitPattern);
    Assert.IsFalse(Settings.TrackerLogin, 'Registry-Name unverändert');
    Assert.IsFalse((Store as IAtlasSettingsNames).Contains('WelcomePageIssuesQuery'));
    Assert.AreEqual('Einstellung welcomePage.issues.query heißt jetzt issues.query; Wert übernommen',
      Renames[1].LogLine);
  finally
    Catalog.Free;
  end;
end;

procedure TAtlasSettingsRenamesTests.RealCatalogHasNoWelcomeTrackerKeys;
var
  Catalog: TAtlasSettingsCatalog;
  Index: Integer;
  Entry: TAtlasCatalogEntry;
begin
  Catalog := TAtlasSettingsCatalog.CreateDefault;
  try
    for Index := 0 to Catalog.Count - 1 do
    begin
      Entry := Catalog[Index];
      // Nur der Schalter des Bereichs bleibt unter welcomePage.issues (#1280).
      Assert.IsFalse(Entry.Key.StartsWith('welcomePage.issues.'), Entry.Key);
      if Entry.Key.StartsWith('issues.') then
      begin
        Assert.AreEqual('issues', Entry.Area, Entry.Key);
        Assert.AreEqual('Issue-Tracker', Entry.Page, Entry.Key);
      end;
    end;
    Assert.IsTrue(Catalog.HasArea('issues'));
    Assert.AreEqual('Issue-Tracker', Catalog.AreaCaption('issues', False));
    Assert.AreEqual('Issue tracker', Catalog.AreaCaption('issues', True));
    Assert.IsTrue(Catalog.IndexOfKey('issues.login') >= 0);
    Assert.AreEqual('TrackerLogin', Catalog[Catalog.IndexOfKey('issues.login')].Name);
    Assert.IsTrue(Catalog.IndexOfKey('welcomePage.issues') >= 0, 'Schalter des Bereichs');
  finally
    Catalog.Free;
  end;
end;

procedure TAtlasSettingsRenamesTests.ImportResolvesFormerNames;
var
  Catalog: TAtlasSettingsCatalog;
  Migrated: Boolean;
  Expected: Integer;
begin
  Catalog := TAtlasSettingsCatalog.CreateDefault;
  try
    Expected := Catalog.IndexOfKey('issues.query');
    Assert.IsTrue(Expected >= 0);
    // Exportdatei vor #1280 (früherer Schlüssel) und ältere flache Datei (früherer Registry-Name).
    Assert.AreEqual(Expected, Catalog.Resolve('welcomePage.issues.query', Migrated));
    Assert.IsTrue(Migrated);
    Assert.AreEqual(Expected, Catalog.Resolve('WelcomePageIssuesQuery', Migrated));
    Assert.IsTrue(Migrated);
    Assert.AreEqual(Catalog.IndexOfKey('issues.login'), Catalog.Resolve('welcomePage.issues.login', Migrated));
    Assert.IsTrue(Migrated);
  finally
    Catalog.Free;
  end;
end;

procedure TAtlasSettingsRenamesTests.HistoryKeepsTrackerValues;
var
  History: TAtlasSettingsHistory;
begin
  History := TAtlasSettingsHistory.Create;
  try
    Assert.IsTrue(History.LoadJson('[{"changedAt":"2026-10-27T10:00:00.000Z","settings":' +
      '{"WelcomePageIssuesQuery":"label:bug","WelcomePageIssuesTracker":"github"}}]'));
    Assert.AreEqual(1, History.Count);
    Assert.AreEqual('label:bug', History[0].Settings.IssuesQuery);
    Assert.AreEqual('github', History[0].Settings.IssuesTracker);
  finally
    History.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsRenamesTests);

end.
