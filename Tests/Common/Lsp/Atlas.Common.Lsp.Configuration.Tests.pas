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
  Root = 'c:\Projekt';
  ConfigUri = 'file:///c%3A/Projekt/atlas.json';
  LegacyConfigUri = 'file:///c%3A/Projekt/delphi-lsp.json';

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
      if SameText(AFileName, Root + '\' + LegacyConfigurationFileName) then
        AText := FLegacyText
      else if SameText(AFileName, Root + '\' + ConfigurationFileName) then
        AText := FDiskText
      else
        AText := '';
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
  FConfiguration.LoadWorkspace(Root, '{"language": "en", "platform": "Win32"}');
  Assert.AreEqual(1, FChanges, 'Nur eine Neuberechnung');
  Assert.AreEqual('en', FConfiguration.Settings.Language);
  Assert.AreEqual('Win64', FConfiguration.Settings.Platform, 'Projekt-Schlüssel aus der globalen Datei wirkt nicht');
end;

procedure TLspConfigurationTests.UsesDefaultsWithoutFile;
begin
  FConfiguration.LoadWorkspace(Root);
  Assert.AreEqual('de', FConfiguration.Settings.Language);
  Assert.AreEqual(1, FChanges);
  Assert.AreEqual(0, Integer(FCapture.Count));
end;

procedure TLspConfigurationTests.LoadsFileFromParentFolder;
begin
  FDiskText := '{"platform": "Win64"}';
  FConfiguration.LoadWorkspace(Root + '\Packages\Expert');
  Assert.AreEqual('Win64', FConfiguration.Settings.Platform, 'atlas.json zwei Ebenen höher');
  // Ohne Datei: Vorgaben, kein Fehler.
  FDiskText := '';
  FConfiguration.LoadWorkspace(Root + '\Packages\Expert');
  Assert.AreEqual(TServerSettings.Default.Platform, FConfiguration.Settings.Platform);
end;

procedure TLspConfigurationTests.LoadsFileFromWorkspaceRoot;
var
  Message: TJSONObject;
begin
  FDiskText := '{"platform": "Win64", "unbekannt": 1}';
  FConfiguration.LoadWorkspace(Root);
  Assert.AreEqual('Win64', FConfiguration.Settings.Platform);
  Assert.AreEqual(1, Integer(FCapture.Count));
  Message := FCapture.MessageAt(0);
  try
    Assert.AreEqual(ConfigUri, Message.GetValue<string>('params.uri'));
    Assert.AreEqual(1, Message.GetValue<TJSONArray>('params.diagnostics').Count);
    Assert.AreEqual(2, Message.GetValue<Integer>('params.diagnostics[0].severity'));
  finally
    Message.Free;
  end;
end;

procedure TLspConfigurationTests.LoadsLegacyFileWithoutNewOne;
var
  Message: TJSONObject;
begin
  FLegacyText := '{"platform": "Win32"}';
  FConfiguration.LoadWorkspace(Root);
  Assert.AreEqual('Win32', FConfiguration.Settings.Platform);
  Assert.AreEqual(1, Integer(FCapture.Count));
  Message := FCapture.MessageAt(0);
  try
    Assert.AreEqual(LegacyConfigUri, Message.GetValue<string>('params.uri'));
  finally
    Message.Free;
  end;
  // Änderungen im Editor an der früheren Datei gelten ebenfalls.
  FStore.Open(LegacyConfigUri, 'json', 1, '{"platform": "Win64"}');
  Assert.AreEqual('Win64', FConfiguration.Settings.Platform);
end;

procedure TLspConfigurationTests.PrefersNewFileOverLegacy;
begin
  FDiskText := '{"platform": "Win64"}';
  FLegacyText := '{"platform": "Win32"}';
  FConfiguration.LoadWorkspace(Root);
  Assert.AreEqual('Win64', FConfiguration.Settings.Platform);
  // Die frühere Datei ist dann nicht die des Arbeitsbereichs.
  FStore.Open(LegacyConfigUri, 'json', 1, '{"platform": "Linux64"}');
  Assert.AreEqual('Win64', FConfiguration.Settings.Platform);
end;

procedure TLspConfigurationTests.PublishesIssuesOfOpenedFile;
var
  Message: TJSONObject;
begin
  FStore.Open('file:///c%3A/Anderer/atlas.json', 'json', 3, '{"language": 1}');
  Assert.AreEqual(1, Integer(FCapture.Count));
  Message := FCapture.MessageAt(0);
  try
    Assert.AreEqual(3, Message.GetValue<Integer>('params.version'));
    Assert.AreEqual(1, Message.GetValue<Integer>('params.diagnostics[0].severity'));
  finally
    Message.Free;
  end;
  // Eine andere Datei als die des Arbeitsbereichs ändert die Einstellungen nicht.
  Assert.AreEqual(0, FChanges);
end;

procedure TLspConfigurationTests.ExtraIssuesAndRevalidate;
var
  Message: TJSONObject;
  Known: Boolean;
begin
  Known := False;
  FConfiguration.ExtraIssues :=
    function(const ASettings: TServerSettings): TArray<TConfigurationIssue>
    var
      Issue: TConfigurationIssue;
    begin
      Result := nil;
      if Known then
        Exit;
      Issue := Default(TConfigurationIssue);
      Issue.Range := ASettings.DfmPropertyRules[0].ClassRange;
      Issue.Message := 'unbekannt: ' + ASettings.DfmPropertyRules[0].ClassName;
      Result := [Issue];
    end;
  FDiskText := '{"dfmPropertyRules": [{"class": "TLabelX", "property": "Transparent", "value": "True"}]}';
  FConfiguration.LoadWorkspace(Root);
  Assert.AreEqual(1, Integer(FCapture.Count));
  Message := FCapture.MessageAt(0);
  try
    Assert.AreEqual(1, Message.GetValue<TJSONArray>('params.diagnostics').Count);
    Assert.AreEqual('unbekannt: TLabelX', Message.GetValue<string>('params.diagnostics[0].message'));
    Assert.AreEqual(32, Message.GetValue<Integer>('params.diagnostics[0].range.start.character'));
  finally
    Message.Free;
  end;
  // Später kennt der Index die Klasse: Revalidate sendet die Meldungen neu, jetzt ohne.
  Known := True;
  FConfiguration.Revalidate;
  Assert.AreEqual(2, Integer(FCapture.Count));
  Message := FCapture.MessageAt(1);
  try
    Assert.AreEqual(0, Message.GetValue<TJSONArray>('params.diagnostics').Count);
  finally
    Message.Free;
  end;
  FConfiguration.ExtraIssues := nil;
end;

procedure TLspConfigurationTests.AppliesEditsAndRevertsOnClose;
begin
  FDiskText := '{"platform": "Win32"}';
  FConfiguration.LoadWorkspace(Root);
  FStore.Open(ConfigUri, 'json', 1, '{"platform": "Win64"}');
  Assert.AreEqual('Win64', FConfiguration.Settings.Platform);
  FStore.Change(ConfigUri, 2, [TTextChange.Full('{"platform": "Linux64"}')]);
  Assert.AreEqual('Linux64', FConfiguration.Settings.Platform);
  FStore.Close(ConfigUri);
  Assert.AreEqual('Win32', FConfiguration.Settings.Platform);
end;

procedure TLspConfigurationTests.ReadsRootFromInitializeParams;
var
  Params: TJSONObject;
begin
  Params := TJSONObject.ParseJSONValue('{"rootUri": "file:///c%3A/Projekt"}') as TJSONObject;
  try
    Assert.AreEqual('c:\Projekt', TLspConfiguration.RootPathFromInitialize(Params));
  finally
    Params.Free;
  end;
  Params := TJSONObject.ParseJSONValue('{"rootUri": null, "workspaceFolders": [{"uri": "file:///d%3A/W", "name": "W"}]}') as TJSONObject;
  try
    Assert.AreEqual('d:\W', TLspConfiguration.RootPathFromInitialize(Params));
  finally
    Params.Free;
  end;
  Assert.AreEqual('', TLspConfiguration.RootPathFromInitialize(nil));
end;

procedure TLspConfigurationTests.EditorSettingsCountAsGlobal;
var
  Dispatcher: TJsonRpcDispatcher;
  Message, Response: TJSONObject;
begin
  // Die Editor-Ebene liegt über der globalen Datei und gilt nur für globale Schlüssel; das IDE-Plugin meldet
  // dort die Version der laufenden IDE.
  FDiskText := '{"platform": "Win64"}';
  FConfiguration.LoadWorkspace(Root);
  Dispatcher := TJsonRpcDispatcher.Create;
  try
    FConfiguration.Attach(Dispatcher);
    Message := TJSONObject.ParseJSONValue('{"jsonrpc": "2.0", "method": "workspace/didChangeConfiguration", ' +
      '"params": {"settings": {"atlas": {"platform": "Win32", "config": "Release", "delphiVersion": "37.0", ' +
      '"language": "en"}}}}') as TJSONObject;
    try
      Response := Dispatcher.DispatchMessage(Message);
      Assert.IsNull(Response);
    finally
      Message.Free;
    end;
  finally
    Dispatcher.Free;
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

procedure TLspConfigurationTests.IndexComesFromGlobalLayers;
var
  Message: TJSONObject;
  Diagnostics: TJSONArray;
begin
  // Indexumfang gilt für alle Projekte (Marco, #652); atlas.json behält nur index.exclude.
  FDiskText := '{"index": {"libraryPaths": false, "exclude": ["**/Demos/**"]}}';
  FConfiguration.SetGlobalSettings('{"index": {"libraryPaths": true, "searchPaths": false, "exclude": ["x"]}}');
  FConfiguration.LoadWorkspace(Root);
  Assert.IsTrue(FConfiguration.Settings.IndexLibraryPaths);
  Assert.IsFalse(FConfiguration.Settings.IndexSearchPaths);
  Assert.AreEqual(1, Integer(Length(FConfiguration.Settings.IndexExclude)));
  Assert.AreEqual('**/Demos/**', FConfiguration.Settings.IndexExclude[0]);
  // Die Datei bekommt eine Warnung am Schlüssel, der nicht ins Projekt gehört.
  Message := FCapture.MessageAt(FCapture.Count - 1);
  try
    Diagnostics := Message.GetValue<TJSONArray>('params.diagnostics');
    Assert.AreEqual(1, Integer(Diagnostics.Count));
    Assert.AreEqual(2, (Diagnostics.Items[0] as TJSONObject).GetValue<Integer>('severity'));
    Assert.Contains((Diagnostics.Items[0] as TJSONObject).GetValue<string>('message'), '"index.libraryPaths"');
    Assert.AreEqual(0, (Diagnostics.Items[0] as TJSONObject).GetValue<Integer>('range.start.line'));
    Assert.AreEqual(11, (Diagnostics.Items[0] as TJSONObject).GetValue<Integer>('range.start.character'));
  finally
    Message.Free;
  end;
end;

procedure TLspConfigurationTests.EachKeyHasOnePlace;
begin
  // #227: globale Schlüssel aus %APPDATA%\Atlas\settings.json, Projekt-Schlüssel aus atlas.json; am falschen
  // Ort wirkt ein Schlüssel nicht.
  FDiskText := '{"platform": "Win64", "language": "de"}';
  FConfiguration.LoadWorkspace(Root);
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
  Assert.AreEqual('de', FConfiguration.Settings.Language);
  // Kaputte globale Datei: wie keine.
  FConfiguration.SetGlobalSettings('{"language": ');
  Assert.AreEqual('de', FConfiguration.Settings.Language);
end;

procedure TLspConfigurationTests.ReloadsChangedFileUnlessOpen;
var
  Before: Integer;
begin
  FDiskText := '{"platform": "Win64"}';
  FConfiguration.LoadWorkspace(Root);
  // Von außen geändert (Dialog des Plugins, #227): ohne Neustart neu gelesen.
  FDiskText := '{"platform": "Win32"}';
  Assert.IsTrue(FConfiguration.FileChanged(Root + '\' + ConfigurationFileName));
  Assert.AreEqual('Win32', FConfiguration.Settings.Platform);
  // Andere Dateien lassen die Einstellungen in Ruhe.
  Before := FChanges;
  Assert.IsFalse(FConfiguration.FileChanged('c:\Anderes\atlas.json'));
  Assert.IsFalse(FConfiguration.FileChanged(''));
  Assert.AreEqual(Before, FChanges);
  // Im Editor geöffnet: Der Text des Editors gilt.
  FStore.Open(ConfigUri, 'json', 1, '{"platform": "Linux64"}');
  FDiskText := '{"platform": "Win32"}';
  Assert.IsFalse(FConfiguration.FileChanged(Root + '\' + ConfigurationFileName));
  Assert.AreEqual('Linux64', FConfiguration.Settings.Platform);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspConfigurationTests);

end.
