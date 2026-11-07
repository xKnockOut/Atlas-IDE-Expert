unit Atlas.Core.Tracker.SettingsTables.Tests;

// Tests der Tabellen der Seite Issue-Tracker (#1455) ohne Oberfläche:
// Verbindungen (Auswahl, Umbenennen, Adresse, Prüfung, .atlas), Projekte
// (Quelle, Hinweis, Hinzufügen), Abfragen (Auswahl der Verbindung, Namen) und
// Textbausteine; gespeichert werden nur vollständige Zeilen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasTrackerSettingsTablesTests = class
  public
    [Test]
    procedure ConnectionsSelectAndSaveOnlyComplete;
    [Test]
    procedure ConnectionsTeamRowsAreReadOnly;
    [Test]
    procedure ConnectionsUrlNameAndProvider;
    [Test]
    procedure ConnectionsCheckRunsOncePerServer;
    [Test]
    procedure ConnectionsValuesConnection;
    [Test]
    procedure ProjectsSourceNoteAndAdd;
    [Test]
    procedure ProjectsMatchAndRename;
    [Test]
    procedure QueriesChoicesNamesAndAdd;
    [Test]
    procedure SnippetsEditAndLimit;
    /// <summary>Mit English zeigt die Tabelle die unveränderten Vorgaben englisch, „Vorgaben“ setzt englische
    /// (#1458).</summary>
    [Test]
    procedure SnippetsDefaultsInLanguage;
    [Test]
    procedure TablesLoadSaveAndRename;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Settings.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.Projects,
  Atlas.Core.Tracker.Queries,
  Atlas.Core.Tracker.CommentEditor,
  Atlas.Core.Tracker.SettingsTables;

const
  cTwoConnections = '[{"name": "Firma", "provider": "youtrack", "url": "https://yt.firma.local"},' +
    ' {"name": "GitHub", "provider": "github", "url": "https://github.com"}]';

type
  /// <summary>Werte nach Schlüssel im Speicher, nur Text.</summary>
  TTextValues = class(TInterfacedObject, IAtlasSettingsValues)
  private
    FValues: TDictionary<string, string>;
  public
    constructor Create;
    destructor Destroy; override;
    function Contains(const AKey: string): Boolean;
    function ReadBoolean(const AKey: string): Boolean;
    function ReadInteger(const AKey: string): Integer;
    function ReadString(const AKey: string): string;
    procedure WriteBoolean(const AKey: string; AValue: Boolean);
    procedure WriteInteger(const AKey: string; AValue: Integer);
    procedure WriteString(const AKey, AValue: string);
    procedure Reset(const AKey: string);
    function StoredKeys: TArray<string>;
  end;

constructor TTextValues.Create;
begin
  inherited Create;
  FValues := TDictionary<string, string>.Create;
end;

destructor TTextValues.Destroy;
begin
  FValues.Free;
  inherited Destroy;
end;

function TTextValues.Contains(const AKey: string): Boolean;
begin
  Result := FValues.ContainsKey(AKey);
end;

function TTextValues.ReadBoolean(const AKey: string): Boolean;
begin
  Result := False;
end;

function TTextValues.ReadInteger(const AKey: string): Integer;
begin
  Result := 0;
end;

function TTextValues.ReadString(const AKey: string): string;
begin
  if not FValues.TryGetValue(AKey, Result) then
  begin
    Result := '';
  end;
end;

procedure TTextValues.WriteBoolean(const AKey: string; AValue: Boolean);
begin
end;

procedure TTextValues.WriteInteger(const AKey: string; AValue: Integer);
begin
end;

procedure TTextValues.WriteString(const AKey, AValue: string);
begin
  FValues.AddOrSetValue(AKey, AValue);
end;

procedure TTextValues.Reset(const AKey: string);
begin
  FValues.Remove(AKey);
end;

function TTextValues.StoredKeys: TArray<string>;
begin
  Result := FValues.Keys.ToArray;
end;

function TeamConnection: TAtlasTrackerConnection;
begin
  Result := TAtlasTrackerConnection.FromTeamFile('Atlas', TAtlasTrackerTarget.Create('github',
    'https://github.com', 'xKnockOut/Atlas-IDE-Expert', ''));
end;

procedure TAtlasTrackerSettingsTablesTests.ConnectionsSelectAndSaveOnlyComplete;
var
  mTable: TAtlasTrackerConnectionTable;
begin
  mTable := TAtlasTrackerConnectionTable.Create;
  try
    Assert.AreEqual(-1, mTable.Selected);
    mTable.Load(cTwoConnections);
    Assert.AreEqual(0, mTable.Selected);
    Assert.IsTrue(mTable.Editable);
    Assert.AreEqual('Firma', mTable.SelectedRow.Name);
    // Neue Zeile ohne Adresse: gewählt, aber nicht gespeichert.
    mTable.Add('Neu');
    Assert.AreEqual(2, mTable.Selected);
    Assert.AreEqual(3, Integer(Length(mTable.Items)));
    Assert.AreEqual(2, Integer(Length(TAtlasTrackerConnections.Read(mTable.ToJson))));
    Assert.AreEqual('youtrack', mTable.SelectedRow.Provider, 'erster Anbieter');
    // Entfernen wählt die letzte verbliebene Zeile.
    Assert.AreEqual('Neu', mTable.Remove.Name);
    Assert.AreEqual(1, mTable.Selected);
    Assert.AreEqual('YouTrack', mTable.ProviderCaption('youtrack'));
    Assert.AreEqual('gitlab', mTable.ProviderCaption('gitlab'));
    Assert.IsFalse(mTable.SetProviders(TArray<string>.Create('a'), nil));
    Assert.IsTrue(mTable.SetProviders(TArray<string>.Create('a'), TArray<string>.Create('A')));
    Assert.AreEqual(0, mTable.ProviderIndex('A'));
  finally
    mTable.Free;
  end;
end;

procedure TAtlasTrackerSettingsTablesTests.ConnectionsTeamRowsAreReadOnly;
var
  mTable: TAtlasTrackerConnectionTable;
begin
  mTable := TAtlasTrackerConnectionTable.Create;
  try
    mTable.Load(cTwoConnections);
    mTable.SetTeam(TArray<TAtlasTrackerConnection>.Create(TeamConnection));
    Assert.AreEqual(3, Integer(Length(mTable.Rows)));
    mTable.Select(2);
    Assert.IsTrue(mTable.HasSelection);
    Assert.IsFalse(mTable.Editable);
    Assert.AreEqual('', mTable.Rename('X'), 'Zeile aus der .atlas bleibt');
    Assert.AreEqual('', mTable.Remove.Name);
    // Ohne .atlas rückt die Wahl auf die letzte Zeile.
    mTable.SetTeam(nil);
    Assert.AreEqual(1, mTable.Selected);
    Assert.AreEqual(2, Integer(Length(mTable.Names)));
    Assert.IsFalse(mTable.ToJson.Contains('Atlas'));
  finally
    mTable.Free;
  end;
end;

procedure TAtlasTrackerSettingsTablesTests.ConnectionsUrlNameAndProvider;
var
  mTable: TAtlasTrackerConnectionTable;
begin
  mTable := TAtlasTrackerConnectionTable.Create;
  try
    mTable.Load(cTwoConnections);
    mTable.SetWorkflow('State', 'Assignee', 'In Arbeit', 'Fertig, Erledigt');
    // Absicht: Die Seite soll eine Adresse ohne https ablehnen.
    // lsp-ignore: security-insecure-http
    Assert.IsTrue(mTable.SetUrl('http://yt2.firma.local') = TAtlasTrackerUrlCheck.NotHttps);
    Assert.AreEqual('https://yt.firma.local', mTable.SelectedRow.Url);
    Assert.IsTrue(mTable.SetUrl('https://yt2.firma.local/') = TAtlasTrackerUrlCheck.Valid);
    Assert.AreEqual('https://yt2.firma.local', mTable.SelectedRow.Url);
    Assert.AreEqual('State', mTable.SelectedRow.StateField, 'Werte bleiben mit neuer Adresse');
    Assert.AreEqual(2, Integer(Length(mTable.SelectedRow.EndStates)));
    Assert.IsTrue(mTable.NameTaken('github'));
    Assert.IsFalse(mTable.NameTaken('Lager'));
    Assert.AreEqual('Firma', mTable.Rename('Lager'));
    Assert.AreEqual('Lager', mTable.Items[0].Name);
    Assert.IsTrue(mTable.SetProvider(1));
    Assert.AreEqual('github', mTable.Items[0].Provider);
    Assert.IsFalse(mTable.SetProvider(5));
  finally
    mTable.Free;
  end;
end;

procedure TAtlasTrackerSettingsTablesTests.ConnectionsCheckRunsOncePerServer;
var
  mTable: TAtlasTrackerConnectionTable;
  mConnection: TAtlasTrackerConnection;
begin
  mTable := TAtlasTrackerConnectionTable.Create;
  try
    mTable.Load(cTwoConnections);
    Assert.IsTrue(mTable.StartCheck(mConnection));
    Assert.AreEqual('Firma', mConnection.Name);
    Assert.IsTrue(mTable.Checking(mConnection));
    Assert.IsFalse(mTable.StartCheck(mConnection), 'läuft schon');
    mTable.CheckDone(mConnection, 'de');
    Assert.IsFalse(mTable.Checking(mConnection));
    Assert.AreEqual('de', mTable.Items[0].Language);
    Assert.AreEqual('', mTable.Items[1].Language);
  finally
    mTable.Free;
  end;
end;

procedure TAtlasTrackerSettingsTablesTests.ConnectionsValuesConnection;
var
  mTable: TAtlasTrackerConnectionTable;
  mConnection: TAtlasTrackerConnection;
begin
  mTable := TAtlasTrackerConnectionTable.Create;
  try
    Assert.IsFalse(mTable.ValuesConnection(mConnection));
    mTable.Load(cTwoConnections);
    mTable.Add('Neu');
    // Gewählte Zeile ohne Adresse: die erste mit Server.
    Assert.IsTrue(mTable.ValuesConnection(mConnection));
    Assert.AreEqual('Firma', mConnection.Name);
    mTable.Select(1);
    Assert.IsTrue(mTable.ValuesConnection(mConnection));
    Assert.AreEqual('GitHub', mConnection.Name);
  finally
    mTable.Free;
  end;
end;

procedure TAtlasTrackerSettingsTablesTests.ProjectsSourceNoteAndAdd;
var
  mTable: TAtlasTrackerProjectTable;
  mContext: TAtlasTrackerProjectContext;
begin
  mTable := TAtlasTrackerProjectTable.Create;
  try
    mTable.Load('[{"match": "C:\\Src\\Kasse.dproj", "connection": "Firma", "project": "KASSE"}]');
    Assert.IsTrue(mTable.NoteOf(mTable.SelectedRow) = TAtlasTrackerProjectNote.NoConnection);
    mTable.SetChoices(TArray<string>.Create('Lager'));
    Assert.IsTrue(mTable.NoteOf(mTable.SelectedRow) = TAtlasTrackerProjectNote.ConnectionMissing);
    mTable.SetChoices(TArray<string>.Create('Lager', 'Firma'));
    Assert.IsTrue(mTable.NoteOf(mTable.SelectedRow) = TAtlasTrackerProjectNote.None);
    Assert.AreEqual(1, mTable.ChoiceOf('firma'));
    Assert.IsTrue(mTable.SourceOf(mTable.SelectedRow) = TAtlasTrackerProjectSource.Personal);
    mContext := TAtlasTrackerProjectContext.Empty;
    mContext.ProjectFile := 'C:\Src\Kasse.dproj';
    mContext.Team := TArray<TAtlasTrackerProjectMapping>.Create(
      TAtlasTrackerProjectMapping.FromTeamFile('C:\Src\Kasse.dproj', 'Atlas', 'KASSE'));
    mTable.SetContext(mContext);
    Assert.IsTrue(mTable.SourceOf(mTable.Items[0]) = TAtlasTrackerProjectSource.Covered);
    Assert.IsTrue(mTable.NoteOf(mTable.Items[0]) = TAtlasTrackerProjectNote.Covered);
    Assert.IsTrue(mTable.SourceOf(mTable.Rows[1]) = TAtlasTrackerProjectSource.Team);
    Assert.IsTrue(mTable.NoteOf(mTable.Rows[1]) = TAtlasTrackerProjectNote.ReadOnly);
    Assert.AreEqual('C:\Src\Kasse.dproj', mTable.CurrentMatch);
    // Hinzufügen: vorhandene Zeile wählen, neue mit der ersten Verbindung.
    Assert.IsFalse(mTable.Add(' '));
    Assert.IsTrue(mTable.Add('C:\Src\Lager'));
    Assert.AreEqual(1, mTable.Selected);
    Assert.AreEqual('Lager', mTable.SelectedRow.Connection);
    Assert.IsTrue(mTable.Add('C:\Src\Kasse.dproj'));
    Assert.AreEqual(0, mTable.Selected);
  finally
    mTable.Free;
  end;
end;

procedure TAtlasTrackerSettingsTablesTests.ProjectsMatchAndRename;
var
  mTable: TAtlasTrackerProjectTable;
begin
  mTable := TAtlasTrackerProjectTable.Create;
  try
    mTable.SetChoices(TArray<string>.Create('Firma'));
    mTable.Add('C:\A.dproj');
    mTable.Add('C:\B.dproj');
    Assert.IsFalse(mTable.SetMatch('C:\A.dproj'), 'Pfad hat schon eine Zeile');
    Assert.IsTrue(mTable.SetMatch('C:\C.dproj'));
    mTable.SetProject('KASSE');
    Assert.IsFalse(mTable.SetConnection(3));
    Assert.IsTrue(mTable.SetConnection(0));
    mTable.RenameConnection('Firma', 'Lager');
    Assert.AreEqual('Lager', mTable.Items[0].Connection);
    Assert.AreEqual('Lager', mTable.Items[1].Connection);
    Assert.AreEqual('KASSE', mTable.Items[1].Project);
    mTable.Remove;
    Assert.AreEqual(0, mTable.Selected);
    Assert.AreEqual(1, Integer(Length(TAtlasTrackerProjects.Read(mTable.ToJson))));
  finally
    mTable.Free;
  end;
end;

procedure TAtlasTrackerSettingsTablesTests.QueriesChoicesNamesAndAdd;
var
  mTable: TAtlasTrackerQueryTable;
begin
  mTable := TAtlasTrackerQueryTable.Create;
  try
    mTable.SetChoices(TArray<string>.Create('Firma', 'GitHub'));
    mTable.Add('Neu');
    mTable.Add('Neu');
    Assert.AreEqual('Neu 2', mTable.SelectedRow.Name);
    Assert.IsTrue(mTable.NoteOf(mTable.SelectedRow) = TAtlasTrackerQueryNote.Empty);
    Assert.AreEqual(0, Integer(Length(TAtlasTrackerQueries.Read(mTable.ToJson))), 'ohne Abfrage nicht gespeichert');
    mTable.SetQuery('#Unresolved');
    Assert.IsFalse(mTable.SetName('Neu'), 'Name vergeben');
    Assert.IsFalse(mTable.SetName(''));
    Assert.IsTrue(mTable.SetName('Offen'));
    Assert.AreEqual(0, mTable.ChoiceOf(''));
    Assert.AreEqual(2, mTable.ChoiceOf('github'));
    Assert.AreEqual(-1, mTable.ChoiceOf('Lager'));
    Assert.IsTrue(mTable.SetConnection(2));
    Assert.AreEqual('GitHub', mTable.SelectedRow.Connection);
    Assert.IsTrue(mTable.SetConnection(0));
    Assert.AreEqual('', mTable.SelectedRow.Connection);
    Assert.IsFalse(mTable.SetConnection(3));
    mTable.SetProject('ATL');
    Assert.AreEqual(1, Integer(Length(mTable.Taken)));
    Assert.AreEqual('Neu', mTable.Taken[0]);
    mTable.Replace(TAtlasTrackerQuery.Create('Offen', 'state: Open', 'Lager', ''));
    Assert.IsTrue(mTable.NoteOf(mTable.SelectedRow) = TAtlasTrackerQueryNote.ConnectionMissing);
    mTable.RenameConnection('Lager', 'Firma');
    Assert.IsTrue(mTable.NoteOf(mTable.SelectedRow) = TAtlasTrackerQueryNote.None);
    Assert.AreEqual(1, Integer(Length(TAtlasTrackerQueries.Read(mTable.ToJson))));
    mTable.Remove;
    Assert.AreEqual(0, mTable.Selected);
  finally
    mTable.Free;
  end;
end;

procedure TAtlasTrackerSettingsTablesTests.SnippetsEditAndLimit;
var
  mTable: TAtlasTrackerSnippetTable;
  mIndex: Integer;
  mLine: string;
begin
  mTable := TAtlasTrackerSnippetTable.Create;
  try
    mTable.Defaults;
    Assert.AreEqual(0, mTable.Selected);
    Assert.IsTrue(Length(mTable.Items) > 0);
    mTable.SetName('Gruß');
    mTable.SetText('Hallo'#13#10'Welt');
    Assert.AreEqual('Gruß', mTable.Items[0].Name);
    Assert.AreEqual('Hallo'#10'Welt', mTable.Items[0].Text);
    mLine := TAtlasTrackerSnippetTable.Line(mTable.Items[0].Text);
    Assert.IsFalse(mLine.Contains(#10), mLine);
    Assert.IsTrue(mLine.StartsWith('Hallo ') and mLine.EndsWith(' Welt'), mLine);
    mTable.Load('[]');
    Assert.AreEqual(-1, mTable.Selected);
    for mIndex := 1 to TAtlasCommentSnippets.cMaxSnippets do
    begin
      mTable.Add('B' + IntToStr(mIndex));
    end;
    Assert.IsFalse(mTable.CanAdd);
    mTable.Add('Zu viel');
    Assert.AreEqual(TAtlasCommentSnippets.cMaxSnippets, Integer(Length(mTable.Items)));
    mTable.Remove;
    Assert.IsTrue(mTable.CanAdd);
    Assert.AreEqual(TAtlasCommentSnippets.cMaxSnippets - 2, mTable.Selected);
  finally
    mTable.Free;
  end;
end;

procedure TAtlasTrackerSettingsTablesTests.SnippetsDefaultsInLanguage;
var
  mTable: TAtlasTrackerSnippetTable;
begin
  mTable := TAtlasTrackerSnippetTable.Create;
  try
    mTable.English := True;
    mTable.Load(TAtlasCommentSnippets.DefaultJson(False));
    Assert.AreEqual('Please check with the current build', mTable.Items[0].Name);
    mTable.Load('[{"name": "Gruß", "text": "Hallo"}]');
    mTable.Defaults;
    Assert.AreEqual('Fixed in {commit}', mTable.Items[1].Name);
    mTable.English := False;
    mTable.Load(mTable.ToJson);
    Assert.AreEqual('Behoben in {commit}', mTable.Items[1].Name);
  finally
    mTable.Free;
  end;
end;

procedure TAtlasTrackerSettingsTablesTests.TablesLoadSaveAndRename;
var
  mTables: TAtlasTrackerSettingsTables;
  mValues: IAtlasSettingsValues;
begin
  mValues := TTextValues.Create;
  mValues.WriteString(TAtlasTrackerSettingsTables.cConnectionsKey, cTwoConnections);
  mValues.WriteString(TAtlasTrackerSettingsTables.cProjectsKey,
    '[{"match": "C:\\A.dproj", "connection": "Firma", "project": "KASSE"}]');
  mValues.WriteString(TAtlasTrackerSettingsTables.cQueriesKey,
    '[{"name": "Offen", "query": "#Unresolved", "connection": "Firma"}]');
  mValues.WriteString(TAtlasTrackerSettingsTables.cSnippetsKey, '[{"name": "Gruß", "text": "Hallo"}]');
  mTables := TAtlasTrackerSettingsTables.Create;
  try
    mTables.Load(mValues);
    Assert.AreEqual(2, Integer(Length(mTables.Projects.Choices)));
    Assert.AreEqual(2, Integer(Length(mTables.Queries.Choices)));
    Assert.AreEqual(1, Integer(Length(mTables.Snippets.Items)));
    mTables.Connections.Rename('Lager');
    mTables.ConnectionRenamed('Firma', 'Lager');
    Assert.AreEqual('Lager', mTables.Projects.Items[0].Connection);
    Assert.AreEqual('Lager', mTables.Queries.Items[0].Connection);
    Assert.AreEqual('Lager', mTables.Projects.Choices[0]);
    mTables.Save(mValues);
    Assert.IsTrue(mValues.ReadString(TAtlasTrackerSettingsTables.cProjectsKey).Contains('Lager'));
    Assert.IsTrue(mValues.ReadString(TAtlasTrackerSettingsTables.cQueriesKey).Contains('Lager'));
    Assert.IsTrue(mValues.ReadString(TAtlasTrackerSettingsTables.cConnectionsKey).Contains('Lager'));
  finally
    mTables.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerSettingsTablesTests);

end.
