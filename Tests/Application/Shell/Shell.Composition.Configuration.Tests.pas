unit Shell.Composition.Configuration.Tests;

// Einstellungsdateien: settings.json aus einem Mitschnitt, Erkennen der globalen Datei, Editor-Einstellungen aus
// didChangeConfiguration und Beobachtung vor dem Start.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.JsonRpc.Dispatcher,
  Shell.Composition.Workspaces,
  Shell.Composition.Settings,
  Shell.Composition.Configuration;

type
  [TestFixture]
  TShellConfigurationTests = class
  private
    FRegistry: TShellWorkspaceRegistry;
    FSettings: TShellSettings;
    FConfiguration: TShellConfiguration;
    FDispatcher: TJsonRpcDispatcher;
    FFolder: string;
    procedure Notify(const AMethod, AParams: string);
  public
    /// <summary>Einmal-Belegungen vorwegnehmen; sie gehören nicht in die Leckmessung.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>settings.json aus dem Mitschnitt wird gelesen und als globale Datei erkannt, auch in anderer
    /// Schreibweise.</summary>
    [Test]
    procedure ReplaySettingsAreGlobal;
    /// <summary>Mitschnitt ohne settings.json: keine globale Datei, auch nicht für einen leeren Namen.</summary>
    [Test]
    procedure ReplayWithoutSettingsHasNoGlobalFile;
    /// <summary>didChangeConfiguration setzt die Editor-Ebene aus settings.atlas.</summary>
    [Test]
    procedure DidChangeConfigurationSetsEditorLevel;
    /// <summary>Vor dem Start gibt es keinen Beobachter; Aktualisieren und Beenden tun nichts.</summary>
    [Test]
    procedure WatchBeforeStartDoesNothing;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Documents.Providers.DocumentStore;

function NoText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
end;

function NoSelection(const AOrigin: string): string;
begin
  Result := '';
end;

function NoActive: string;
begin
  Result := '';
end;

function NoLanguageLevel(const AUri: string): string;
begin
  Result := '';
end;

procedure NoFiles(const AFiles: TArray<string>);
begin
  // Die Tests starten den Beobachter, ändern aber keine beobachtete Datei.
end;

procedure TShellConfigurationTests.WarmUpFirstUse;
begin
  Setup;
  try
    ReplaySettingsAreGlobal;
  finally
    TearDown;
  end;
end;

procedure TShellConfigurationTests.Setup;
var
  mRegistry: TShellWorkspaceRegistryServices;
  mServices: TShellConfigurationServices;
begin
  mRegistry := Default(TShellWorkspaceRegistryServices);
  mRegistry.Logger := TLogger.Create;
  mRegistry.SelectedProject := NoSelection;
  mRegistry.ActiveProject := NoActive;
  mRegistry.ReadText := NoText;
  FRegistry := TShellWorkspaceRegistry.Create(mRegistry);
  FSettings := TShellSettings.Create(FRegistry, NoLanguageLevel);
  mServices := Default(TShellConfigurationServices);
  mServices.Logger := TLogger.Create;
  mServices.Workspaces := FRegistry;
  mServices.Settings := FSettings;
  mServices.Documents := TDocumentStore.Create;
  mServices.FilesChanged := NoFiles;
  FConfiguration := TShellConfiguration.Create(mServices);
  FDispatcher := TJsonRpcDispatcher.Create;
  FConfiguration.Attach(FDispatcher);
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasConfiguration' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FFolder);
end;

procedure TShellConfigurationTests.TearDown;
begin
  FreeAndNil(FDispatcher);
  FreeAndNil(FConfiguration);
  FreeAndNil(FSettings);
  FreeAndNil(FRegistry);
  if TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  FFolder := '';
end;

procedure TShellConfigurationTests.Notify(const AMethod, AParams: string);
var
  mMessage: TJSONObject;
begin
  mMessage := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","method":"' + AMethod + '","params":' + AParams + '}')
    as TJSONObject;
  try
    FDispatcher.DispatchMessage(mMessage).Free;
  finally
    mMessage.Free;
  end;
end;

procedure TShellConfigurationTests.ReplaySettingsAreGlobal;
const
  cText = '{"hover":{"enabled":false}}';
var
  mFile: string;
begin
  mFile := TPath.Combine(FFolder, 'settings.json');
  TFile.WriteAllText(mFile, cText, TEncoding.UTF8);
  FConfiguration.UseReplaySettings(mFile);
  FConfiguration.Start;
  Assert.AreEqual(mFile, FConfiguration.GlobalSettingsFile);
  Assert.IsTrue(FConfiguration.IsGlobalSettingsFile(UpperCase(mFile)), 'Schreibweise');
  Assert.IsFalse(FConfiguration.IsGlobalSettingsFile(TPath.Combine(FFolder, 'atlas.json')));
  Assert.AreEqual(cText, Trim(FSettings.GlobalSettings));
  FConfiguration.UpdateWatchedFiles;
end;

procedure TShellConfigurationTests.ReplayWithoutSettingsHasNoGlobalFile;
begin
  FConfiguration.UseReplaySettings('');
  FConfiguration.Start;
  Assert.AreEqual('', FConfiguration.GlobalSettingsFile);
  Assert.IsFalse(FConfiguration.IsGlobalSettingsFile(''));
  Assert.AreEqual('', FSettings.GlobalSettings);
end;

procedure TShellConfigurationTests.DidChangeConfigurationSetsEditorLevel;
var
  mValue: TJSONValue;
begin
  Notify('workspace/didChangeConfiguration', '{"settings":{"atlas":{"hover":{"enabled":false}}}}');
  mValue := TJSONObject.ParseJSONValue(FSettings.EditorSettings);
  try
    Assert.IsTrue(mValue is TJSONObject);
    Assert.IsNotNull(TJSONObject(mValue).FindValue('hover.enabled'));
  finally
    mValue.Free;
  end;
end;

procedure TShellConfigurationTests.WatchBeforeStartDoesNothing;
begin
  FConfiguration.UpdateWatchedFiles;
  FConfiguration.StopWatching;
  Assert.AreEqual('', FConfiguration.GlobalSettingsFile);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellConfigurationTests);

end.
