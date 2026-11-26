unit Atlas.Common.Configuration.Workspace.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Workspace;

type
  /// <summary>Was der Melder bekam.</summary>
  TPublishedIssues = record
    Uri: string;
    Version: Integer;
    Issues: TArray<TConfigurationIssue>;
  end;

  [TestFixture]
  TWorkspaceConfigurationTests = class
  private
    FStore: IDocumentStore;
    FPublished: TArray<TPublishedIssues>;
    FConfiguration: TWorkspaceConfiguration;
    FDiskText: string;
    FLegacyText: string;
    FChanges: Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure UsesDefaultsWithoutFile;
    [Test]
    procedure LoadWorkspaceWithGlobalTextChangesOnce;
    [Test]
    procedure LoadsFileFromWorkspaceRoot;
    /// <summary>Projekt einer Gruppe im Unterordner: atlas.json aus dem Stamm darüber.</summary>
    [Test]
    procedure LoadsFileFromParentFolder;
    /// <summary>Basis für "exclude": Ordner der Datei, nicht der Unterordner des Projekts.</summary>
    [Test]
    procedure ConfigRootIsFolderOfFile;
    [Test]
    procedure LoadsLegacyFileWithoutNewOne;
    [Test]
    procedure PrefersNewFileOverLegacy;
    [Test]
    procedure PublishesIssuesOfOpenedFile;
    [Test]
    procedure AppliesEditsAndRevertsOnClose;
    [Test]
    procedure EditorSettingsCountAsGlobal;
    [Test]
    procedure IndexComesFromGlobalLayers;
    [Test]
    procedure EachKeyHasOnePlace;
    [Test]
    procedure ReloadsChangedFileUnlessOpen;
    /// <summary>Meldungen über den Index (#309) kommen über ExtraIssues und nach Revalidate erneut.</summary>
    [Test]
    procedure ExtraIssuesAndRevalidate;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Providers.DocumentStore;

const
  cRoot = 'c:\Projekt';
  cConfigUri = 'file:///c%3A/Projekt/atlas.json';
  cLegacyConfigUri = 'file:///c%3A/Projekt/delphi-lsp.json';

{ TWorkspaceConfigurationTests }

procedure TWorkspaceConfigurationTests.Setup;
begin
  FStore := TDocumentStore.Create;
  FPublished := nil;
  FDiskText := '';
  FLegacyText := '';
  FChanges := 0;
  FConfiguration := TWorkspaceConfiguration.Create(FStore,
    procedure(const AUri: string; AVersion: Integer; const AIssues: TArray<TConfigurationIssue>)
    var
      mItem: TPublishedIssues;
    begin
      mItem.Uri := AUri;
      mItem.Version := AVersion;
      mItem.Issues := AIssues;
      FPublished := FPublished + [mItem];
    end,
    function(const AFileName: string; out AText: string): Boolean
    begin
      if SameText(AFileName, cRoot + '\' + cLegacyConfigurationFileName) then
      begin
        AText := FLegacyText;
      end
      else if SameText(AFileName, cRoot + '\' + cConfigurationFileName) then
      begin
        AText := FDiskText;
      end
      else
      begin
        AText := '';
      end;
      Result := AText <> '';
    end);
  FConfiguration.OnChanged :=
    procedure(const ASettings: TServerSettings)
    begin
      Inc(FChanges);
    end;
  FConfiguration.Attach;
end;

procedure TWorkspaceConfigurationTests.TearDown;
begin
  FConfiguration.Free;
  FStore := nil;
  FPublished := nil;
  // Sonst gibt erst das nächste Setup den Text frei (Leck-Monitor).
  FDiskText := '';
  FLegacyText := '';
end;

procedure TWorkspaceConfigurationTests.UsesDefaultsWithoutFile;
begin
  FConfiguration.LoadWorkspace(cRoot);
  Assert.AreEqual('', FConfiguration.Settings.Language);
  Assert.AreEqual(1, FChanges);
  Assert.AreEqual(0, Integer(Length(FPublished)));
end;

procedure TWorkspaceConfigurationTests.LoadWorkspaceWithGlobalTextChangesOnce;
begin
  FDiskText := '{"platform": "Win64"}';
  FConfiguration.LoadWorkspace(cRoot, '{"language": "en", "platform": "Win32"}');
  Assert.AreEqual(1, FChanges, 'Nur eine Neuberechnung');
  Assert.AreEqual('en', FConfiguration.Settings.Language);
  Assert.AreEqual('Win64', FConfiguration.Settings.Platform, 'Projekt-Schlüssel aus der globalen Datei wirkt nicht');
end;

procedure TWorkspaceConfigurationTests.LoadsFileFromWorkspaceRoot;
begin
  FDiskText := '{"platform": "Win64", "unbekannt": 1}';
  FConfiguration.LoadWorkspace(cRoot);
  Assert.AreEqual('Win64', FConfiguration.Settings.Platform);
  Assert.AreEqual(1, Integer(Length(FPublished)));
  Assert.AreEqual(cConfigUri, FPublished[0].Uri);
  Assert.AreEqual(-1, FPublished[0].Version);
  Assert.AreEqual(1, Integer(Length(FPublished[0].Issues)));
  Assert.IsFalse(FPublished[0].Issues[0].IsError);
end;

procedure TWorkspaceConfigurationTests.LoadsFileFromParentFolder;
begin
  FDiskText := '{"platform": "Win64"}';
  FConfiguration.LoadWorkspace(cRoot + '\Packages\Expert');
  Assert.AreEqual('Win64', FConfiguration.Settings.Platform, 'atlas.json zwei Ebenen höher');
  // Ohne Datei: Vorgaben, kein Fehler.
  FDiskText := '';
  FConfiguration.LoadWorkspace(cRoot + '\Packages\Expert');
  Assert.AreEqual(TServerSettings.Default.Platform, FConfiguration.Settings.Platform);
end;

procedure TWorkspaceConfigurationTests.ConfigRootIsFolderOfFile;
begin
  FDiskText := '{"platform": "Win64"}';
  FConfiguration.LoadWorkspace(cRoot + '\Packages\Expert');
  Assert.AreEqual(cRoot + '\', FConfiguration.ConfigRoot);
  // Ohne Datei bleibt die Wurzel.
  FDiskText := '';
  FConfiguration.LoadWorkspace(cRoot + '\Packages\Expert');
  Assert.AreEqual(cRoot + '\Packages\Expert', FConfiguration.ConfigRoot);
end;

procedure TWorkspaceConfigurationTests.LoadsLegacyFileWithoutNewOne;
begin
  FLegacyText := '{"platform": "Win32"}';
  FConfiguration.LoadWorkspace(cRoot);
  Assert.AreEqual('Win32', FConfiguration.Settings.Platform);
  Assert.AreEqual(1, Integer(Length(FPublished)));
  Assert.AreEqual(cLegacyConfigUri, FPublished[0].Uri);
  // Änderungen im Editor an der früheren Datei gelten ebenfalls.
  FStore.Open(cLegacyConfigUri, 'json', 1, '{"platform": "Win64"}');
  Assert.AreEqual('Win64', FConfiguration.Settings.Platform);
end;

procedure TWorkspaceConfigurationTests.PrefersNewFileOverLegacy;
begin
  FDiskText := '{"platform": "Win64"}';
  FLegacyText := '{"platform": "Win32"}';
  FConfiguration.LoadWorkspace(cRoot);
  Assert.AreEqual('Win64', FConfiguration.Settings.Platform);
  // Die frühere Datei ist dann nicht die des Arbeitsbereichs.
  FStore.Open(cLegacyConfigUri, 'json', 1, '{"platform": "Linux64"}');
  Assert.AreEqual('Win64', FConfiguration.Settings.Platform);
end;

procedure TWorkspaceConfigurationTests.PublishesIssuesOfOpenedFile;
begin
  FStore.Open('file:///c%3A/Anderer/atlas.json', 'json', 3, '{"language": 1}');
  Assert.AreEqual(1, Integer(Length(FPublished)));
  Assert.AreEqual('file:///c%3A/Anderer/atlas.json', FPublished[0].Uri);
  Assert.AreEqual(3, FPublished[0].Version);
  Assert.IsTrue(FPublished[0].Issues[0].IsError);
  // Eine andere Datei als die des Arbeitsbereichs ändert die Einstellungen nicht.
  Assert.AreEqual(0, FChanges);
end;

procedure TWorkspaceConfigurationTests.AppliesEditsAndRevertsOnClose;
begin
  FDiskText := '{"platform": "Win32"}';
  FConfiguration.LoadWorkspace(cRoot);
  FStore.Open(cConfigUri, 'json', 1, '{"platform": "Win64"}');
  Assert.AreEqual('Win64', FConfiguration.Settings.Platform);
  FStore.Change(cConfigUri, 2, [TTextChange.Full('{"platform": "Linux64"}')]);
  Assert.AreEqual('Linux64', FConfiguration.Settings.Platform);
  FStore.Close(cConfigUri);
  Assert.AreEqual('Win32', FConfiguration.Settings.Platform);
end;

procedure TWorkspaceConfigurationTests.EditorSettingsCountAsGlobal;
begin
  // Die Editor-Ebene liegt über der globalen Datei und gilt nur für globale Schlüssel; das IDE-Plugin meldet
  // dort die Version der laufenden IDE.
  FDiskText := '{"platform": "Win64"}';
  FConfiguration.LoadWorkspace(cRoot);
  FConfiguration.SetEditorSettings('{"platform": "Win32", "config": "Release", "delphiVersion": "37.0", ' +
    '"language": "en"}');
  Assert.AreEqual('Win64', FConfiguration.Settings.Platform);
  Assert.AreEqual(TServerSettings.Default.Config, FConfiguration.Settings.Config, 'config gehört zum Projekt');
  Assert.AreEqual('37.0', FConfiguration.Settings.DelphiVersion);
  Assert.AreEqual('en', FConfiguration.Settings.Language);
  FConfiguration.SetGlobalSettings('{"language": "de", "delphiVersion": "23.0"}');
  Assert.AreEqual('en', FConfiguration.Settings.Language, 'Editor über global');
  Assert.AreEqual('37.0', FConfiguration.Settings.DelphiVersion);
end;

procedure TWorkspaceConfigurationTests.IndexComesFromGlobalLayers;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  // Indexumfang gilt für alle Projekte (#652); atlas.json behält nur index.exclude.
  FDiskText := '{"index": {"libraryPaths": false, "exclude": ["**/Demos/**"]}}';
  FConfiguration.SetGlobalSettings('{"index": {"libraryPaths": true, "searchPaths": false, "exclude": ["x"]}}');
  FConfiguration.LoadWorkspace(cRoot);
  Assert.IsTrue(FConfiguration.Settings.IndexLibraryPaths);
  Assert.IsFalse(FConfiguration.Settings.IndexSearchPaths);
  Assert.AreEqual(1, Integer(Length(FConfiguration.Settings.IndexExclude)));
  Assert.AreEqual('**/Demos/**', FConfiguration.Settings.IndexExclude[0]);
  // Die Datei bekommt eine Warnung am Schlüssel, der nicht ins Projekt gehört.
  mIssues := FPublished[High(FPublished)].Issues;
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.IsFalse(mIssues[0].IsError);
  Assert.Contains(mIssues[0].Message, '"index.libraryPaths"');
  Assert.AreEqual(0, mIssues[0].Range.StartPos.Line);
  Assert.AreEqual(11, mIssues[0].Range.StartPos.Character);
  mIssues := nil;
end;

procedure TWorkspaceConfigurationTests.EachKeyHasOnePlace;
begin
  // #227: globale Schlüssel aus %APPDATA%\Atlas\settings.json, Projekt-Schlüssel aus atlas.json; am falschen
  // Ort wirkt ein Schlüssel nicht.
  FDiskText := '{"platform": "Win64", "language": "de"}';
  FConfiguration.LoadWorkspace(cRoot);
  FConfiguration.SetGlobalSettings('{"platform": "Win32", "config": "Release", "language": "en", ' +
    '"rules": {"empty-except": "off", "with-statement": "error"}}');
  Assert.AreEqual('Win64', FConfiguration.Settings.Platform);
  Assert.AreEqual(TServerSettings.Default.Config, FConfiguration.Settings.Config);
  Assert.AreEqual('en', FConfiguration.Settings.Language);
  // Ausnahme rules (x-scope "both"): global für alle Projekte, atlas.json übersteuert je Regel.
  Assert.AreEqual(2, Integer(Length(FConfiguration.Settings.Rules)), 'Regeln auch global');
  FConfiguration.SetEditorSettings('{"language": "de"}');
  Assert.AreEqual('de', FConfiguration.Settings.Language);
  FConfiguration.SetEditorSettings('');
  FConfiguration.SetGlobalSettings('');
  Assert.AreEqual('', FConfiguration.Settings.Language);
  // Kaputte globale Datei: wie keine.
  FConfiguration.SetGlobalSettings('{"language": ');
  Assert.AreEqual('', FConfiguration.Settings.Language);
end;

procedure TWorkspaceConfigurationTests.ReloadsChangedFileUnlessOpen;
var
  mBefore: Integer;
begin
  FDiskText := '{"platform": "Win64"}';
  FConfiguration.LoadWorkspace(cRoot);
  // Von außen geändert (Dialog des Plugins, #227): ohne Neustart neu gelesen.
  FDiskText := '{"platform": "Win32"}';
  Assert.IsTrue(FConfiguration.FileChanged(cRoot + '\' + cConfigurationFileName));
  Assert.AreEqual('Win32', FConfiguration.Settings.Platform);
  // Andere Dateien lassen die Einstellungen in Ruhe.
  mBefore := FChanges;
  Assert.IsFalse(FConfiguration.FileChanged('c:\Anderes\atlas.json'));
  Assert.IsFalse(FConfiguration.FileChanged(''));
  Assert.AreEqual(mBefore, FChanges);
  // Im Editor geöffnet: Der Text des Editors gilt.
  FStore.Open(cConfigUri, 'json', 1, '{"platform": "Linux64"}');
  FDiskText := '{"platform": "Win32"}';
  Assert.IsFalse(FConfiguration.FileChanged(cRoot + '\' + cConfigurationFileName));
  Assert.AreEqual('Linux64', FConfiguration.Settings.Platform);
end;

procedure TWorkspaceConfigurationTests.ExtraIssuesAndRevalidate;
var
  mKnown: Boolean;
begin
  mKnown := False;
  FConfiguration.ExtraIssues :=
    function(const ASettings: TServerSettings): TArray<TConfigurationIssue>
    var
      Issue: TConfigurationIssue;
    begin
      Result := nil;
      if mKnown then
      begin
        Exit;
      end;
      Issue := Default(TConfigurationIssue);
      Issue.Range := ASettings.DfmPropertyRules[0].ClassRange;
      Issue.Message := 'unbekannt: ' + ASettings.DfmPropertyRules[0].ClassName;
      Result := [Issue];
    end;
  FDiskText := '{"dfmPropertyRules": [{"class": "TLabelX", "property": "Transparent", "value": "True"}]}';
  FConfiguration.LoadWorkspace(cRoot);
  Assert.AreEqual(1, Integer(Length(FPublished)));
  Assert.AreEqual(1, Integer(Length(FPublished[0].Issues)));
  Assert.AreEqual('unbekannt: TLabelX', FPublished[0].Issues[0].Message);
  Assert.AreEqual(32, FPublished[0].Issues[0].Range.StartPos.Character);
  // Später kennt der Index die Klasse: Revalidate sendet die Meldungen neu, jetzt ohne.
  mKnown := True;
  FConfiguration.Revalidate;
  Assert.AreEqual(2, Integer(Length(FPublished)));
  Assert.AreEqual(0, Integer(Length(FPublished[1].Issues)));
  FConfiguration.ExtraIssues := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TWorkspaceConfigurationTests);

end.
