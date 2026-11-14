unit Atlas.Common.Lsp.Configuration.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.SyntaxDiagnostics.Tests,
  Atlas.Common.Lsp.Configuration;

type
  [TestFixture]
  TLspConfigurationTests = class
  private
    FStore: IDocumentStore;
    FCapture: TCapturingTransport;
    FTransport: IJsonRpcTransport;
    FConfiguration: TLspConfiguration;
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
    procedure ReadsRootFromInitializeParams;
    [Test]
    procedure EditorSettingsCountAsGlobal;
    [Test]
    procedure IndexComesFromGlobalLayers;
    /// <summary>initializationOptions.locale vor locale (#1458).</summary>
    [Test]
    procedure ClientLocaleFromInitialize;
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
  System.Generics.Collections,
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Configuration.Contract;

const
  cRoot = 'c:\Projekt';
  cConfigUri = 'file:///c%3A/Projekt/atlas.json';
  cLegacyConfigUri = 'file:///c%3A/Projekt/delphi-lsp.json';

{ TLspConfigurationTests }

procedure TLspConfigurationTests.Setup;
begin
  FStore := TDocumentStore.Create;
  FCapture := TCapturingTransport.Create;
  FTransport := FCapture;
  FDiskText := '';
  FLegacyText := '';
  FChanges := 0;
  FConfiguration := TLspConfiguration.Create(FStore, FTransport,
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

procedure TLspConfigurationTests.TearDown;
begin
  FConfiguration.Free;
  FStore := nil;
  FTransport := nil;
  // Sonst gibt erst das nächste Setup den Text frei (Leck-Monitor).
  FDiskText := '';
  FLegacyText := '';
end;

procedure TLspConfigurationTests.LoadWorkspaceWithGlobalTextChangesOnce;
begin
  FDiskText := '{"platform": "Win64"}';
  FConfiguration.LoadWorkspace(cRoot, '{"language": "en", "platform": "Win32"}');
  Assert.AreEqual(1, FChanges, 'Nur eine Neuberechnung');
  Assert.AreEqual('en', FConfiguration.Settings.Language);
  Assert.AreEqual('Win64', FConfiguration.Settings.Platform, 'Projekt-Schlüssel aus der globalen Datei wirkt nicht');
end;

procedure TLspConfigurationTests.UsesDefaultsWithoutFile;
begin
  FConfiguration.LoadWorkspace(cRoot);
  Assert.AreEqual('', FConfiguration.Settings.Language);
  Assert.AreEqual(1, FChanges);
  Assert.AreEqual(0, Integer(FCapture.Count));
end;

procedure TLspConfigurationTests.LoadsFileFromParentFolder;
begin
  FDiskText := '{"platform": "Win64"}';
  FConfiguration.LoadWorkspace(cRoot + '\Packages\Expert');
  Assert.AreEqual('Win64', FConfiguration.Settings.Platform, 'atlas.json zwei Ebenen höher');
  // Ohne Datei: Vorgaben, kein Fehler.
  FDiskText := '';
  FConfiguration.LoadWorkspace(cRoot + '\Packages\Expert');
  Assert.AreEqual(TServerSettings.Default.Platform, FConfiguration.Settings.Platform);
end;

procedure TLspConfigurationTests.ConfigRootIsFolderOfFile;
begin
  FDiskText := '{"platform": "Win64"}';
  FConfiguration.LoadWorkspace(cRoot + '\Packages\Expert');
  Assert.AreEqual(cRoot + '\', FConfiguration.ConfigRoot);
  // Ohne Datei bleibt die Wurzel.
  FDiskText := '';
  FConfiguration.LoadWorkspace(cRoot + '\Packages\Expert');
  Assert.AreEqual(cRoot + '\Packages\Expert', FConfiguration.ConfigRoot);
end;

procedure TLspConfigurationTests.LoadsFileFromWorkspaceRoot;
var
  mMessage: TJSONObject;
begin
  FDiskText := '{"platform": "Win64", "unbekannt": 1}';
  FConfiguration.LoadWorkspace(cRoot);
  Assert.AreEqual('Win64', FConfiguration.Settings.Platform);
  Assert.AreEqual(1, Integer(FCapture.Count));
  mMessage := FCapture.MessageAt(0);
  try
    Assert.AreEqual(cConfigUri, mMessage.GetValue<string>('params.uri'));
    Assert.AreEqual(1, mMessage.GetValue<TJSONArray>('params.diagnostics').Count);
    Assert.AreEqual(2, mMessage.GetValue<Integer>('params.diagnostics[0].severity'));
  finally
    mMessage.Free;
  end;
end;

procedure TLspConfigurationTests.LoadsLegacyFileWithoutNewOne;
var
  mMessage: TJSONObject;
begin
  FLegacyText := '{"platform": "Win32"}';
  FConfiguration.LoadWorkspace(cRoot);
  Assert.AreEqual('Win32', FConfiguration.Settings.Platform);
  Assert.AreEqual(1, Integer(FCapture.Count));
  mMessage := FCapture.MessageAt(0);
  try
    Assert.AreEqual(cLegacyConfigUri, mMessage.GetValue<string>('params.uri'));
  finally
    mMessage.Free;
  end;
  // Änderungen im Editor an der früheren Datei gelten ebenfalls.
  FStore.Open(cLegacyConfigUri, 'json', 1, '{"platform": "Win64"}');
  Assert.AreEqual('Win64', FConfiguration.Settings.Platform);
end;

procedure TLspConfigurationTests.PrefersNewFileOverLegacy;
begin
  FDiskText := '{"platform": "Win64"}';
  FLegacyText := '{"platform": "Win32"}';
  FConfiguration.LoadWorkspace(cRoot);
  Assert.AreEqual('Win64', FConfiguration.Settings.Platform);
  // Die frühere Datei ist dann nicht die des Arbeitsbereichs.
  FStore.Open(cLegacyConfigUri, 'json', 1, '{"platform": "Linux64"}');
  Assert.AreEqual('Win64', FConfiguration.Settings.Platform);
end;

procedure TLspConfigurationTests.PublishesIssuesOfOpenedFile;
var
  mMessage: TJSONObject;
begin
  FStore.Open('file:///c%3A/Anderer/atlas.json', 'json', 3, '{"language": 1}');
  Assert.AreEqual(1, Integer(FCapture.Count));
  mMessage := FCapture.MessageAt(0);
  try
    Assert.AreEqual(3, mMessage.GetValue<Integer>('params.version'));
    Assert.AreEqual(1, mMessage.GetValue<Integer>('params.diagnostics[0].severity'));
  finally
    mMessage.Free;
  end;
  // Eine andere Datei als die des Arbeitsbereichs ändert die Einstellungen nicht.
  Assert.AreEqual(0, FChanges);
end;

procedure TLspConfigurationTests.ExtraIssuesAndRevalidate;
var
  mMessage: TJSONObject;
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
  Assert.AreEqual(1, Integer(FCapture.Count));
  mMessage := FCapture.MessageAt(0);
  try
    Assert.AreEqual(1, mMessage.GetValue<TJSONArray>('params.diagnostics').Count);
    Assert.AreEqual('unbekannt: TLabelX', mMessage.GetValue<string>('params.diagnostics[0].message'));
    Assert.AreEqual(32, mMessage.GetValue<Integer>('params.diagnostics[0].range.start.character'));
  finally
    mMessage.Free;
  end;
  // Später kennt der Index die Klasse: Revalidate sendet die Meldungen neu, jetzt ohne.
  mKnown := True;
  FConfiguration.Revalidate;
  Assert.AreEqual(2, Integer(FCapture.Count));
  mMessage := FCapture.MessageAt(1);
  try
    Assert.AreEqual(0, mMessage.GetValue<TJSONArray>('params.diagnostics').Count);
  finally
    mMessage.Free;
  end;
  FConfiguration.ExtraIssues := nil;
end;

procedure TLspConfigurationTests.AppliesEditsAndRevertsOnClose;
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

procedure TLspConfigurationTests.ReadsRootFromInitializeParams;
var
  mParams: TJSONObject;
begin
  mParams := TJSONObject.ParseJSONValue('{"rootUri": "file:///c%3A/Projekt"}') as TJSONObject;
  try
    Assert.AreEqual('c:\Projekt', TLspConfiguration.RootPathFromInitialize(mParams));
  finally
    mParams.Free;
  end;
  mParams := TJSONObject.ParseJSONValue('{"rootUri": null, "workspaceFolders": [{"uri": "file:///d%3A/W", "name": "W"}]}') as TJSONObject;
  try
    Assert.AreEqual('d:\W', TLspConfiguration.RootPathFromInitialize(mParams));
  finally
    mParams.Free;
  end;
  Assert.AreEqual('', TLspConfiguration.RootPathFromInitialize(nil));
end;

procedure TLspConfigurationTests.EditorSettingsCountAsGlobal;
var
  mDispatcher: TJsonRpcDispatcher;
  mMessage, mResponse: TJSONObject;
begin
  // Die Editor-Ebene liegt über der globalen Datei und gilt nur für globale Schlüssel; das IDE-Plugin meldet
  // dort die Version der laufenden IDE.
  FDiskText := '{"platform": "Win64"}';
  FConfiguration.LoadWorkspace(cRoot);
  mDispatcher := TJsonRpcDispatcher.Create;
  try
    FConfiguration.Attach(mDispatcher);
    mMessage := TJSONObject.ParseJSONValue('{"jsonrpc": "2.0", "method": "workspace/didChangeConfiguration", ' +
      '"params": {"settings": {"atlas": {"platform": "Win32", "config": "Release", "delphiVersion": "37.0", ' +
      '"language": "en"}}}}') as TJSONObject;
    try
      mResponse := mDispatcher.DispatchMessage(mMessage);
      Assert.IsNull(mResponse);
    finally
      mMessage.Free;
    end;
  finally
    mDispatcher.Free;
  end;
  Assert.AreEqual('Win64', FConfiguration.Settings.Platform);
  Assert.AreEqual(TServerSettings.Default.Config, FConfiguration.Settings.Config, 'config gehört zum Projekt');
  Assert.AreEqual('37.0', FConfiguration.Settings.DelphiVersion);
  Assert.AreEqual('en', FConfiguration.Settings.Language);
  FConfiguration.SetGlobalSettings('{"language": "de", "delphiVersion": "23.0"}');
  Assert.AreEqual('en', FConfiguration.Settings.Language, 'Editor über global');
  Assert.AreEqual('37.0', FConfiguration.Settings.DelphiVersion);
  Assert.AreEqual('', TLspConfiguration.EditorSettingsFromParams(nil));
end;

procedure TLspConfigurationTests.ClientLocaleFromInitialize;

  function LocaleOf(const AJson: string): string;
  var
    mParams: TJSONValue;
  begin
    mParams := TJSONObject.ParseJSONValue(AJson);
    try
      Result := TLspClientLocale.FromInitialize(mParams);
    finally
      mParams.Free;
    end;
  end;

begin
  Assert.AreEqual('de', LocaleOf('{"locale": "en-US", "initializationOptions": {"locale": "de"}}'));
  Assert.AreEqual('en-US', LocaleOf('{"locale": "en-US", "initializationOptions": {"locale": " "}}'));
  Assert.AreEqual('en-US', LocaleOf('{"locale": "en-US"}'));
  Assert.AreEqual('', LocaleOf('{"processId": 1}'));
  Assert.AreEqual('', TLspClientLocale.FromInitialize(nil));
end;

procedure TLspConfigurationTests.IndexComesFromGlobalLayers;
var
  mMessage: TJSONObject;
  mDiagnostics: TJSONArray;
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
  mMessage := FCapture.MessageAt(FCapture.Count - 1);
  try
    mDiagnostics := mMessage.GetValue<TJSONArray>('params.diagnostics');
    Assert.AreEqual(1, Integer(mDiagnostics.Count));
    Assert.AreEqual(2, (mDiagnostics.Items[0] as TJSONObject).GetValue<Integer>('severity'));
    Assert.Contains((mDiagnostics.Items[0] as TJSONObject).GetValue<string>('message'), '"index.libraryPaths"');
    Assert.AreEqual(0, (mDiagnostics.Items[0] as TJSONObject).GetValue<Integer>('range.start.line'));
    Assert.AreEqual(11, (mDiagnostics.Items[0] as TJSONObject).GetValue<Integer>('range.start.character'));
  finally
    mMessage.Free;
  end;
end;

procedure TLspConfigurationTests.EachKeyHasOnePlace;
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

procedure TLspConfigurationTests.ReloadsChangedFileUnlessOpen;
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

initialization
  TDUnitX.RegisterTestFixture(TLspConfigurationTests);

end.
