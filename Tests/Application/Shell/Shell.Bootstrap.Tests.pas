unit Shell.Bootstrap.Tests;

// Gemeinsamer Aufbau von LSP-Server, MCP-Modus und Linter:
// Dateien lesen, Projektgruppe, globale settings.json und atlas.json ohne Editor.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TShellBootstrapTests = class
  private
    FFolder: string;
    function Write(const AName, AText: string): string;
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReadSourceText_Utf8Bom_ReturnsText;
    [Test]
    procedure ReadSourceText_Missing_ReturnsFalse;
    [Test]
    procedure ReadSourceText_OpenDocumentFirst;
    [Test]
    procedure GroupProjects_NoGroup_Empty;
    [Test]
    procedure GroupProjects_Groupproj_ListsProjects;
    [Test]
    procedure GroupProjects_TwoGroups_Empty;
    [Test]
    procedure LoadGroup_Invalid_LogsWarning;
    [Test]
    procedure GlobalSettingsFile_UnderAppData;
    [Test]
    procedure LoadGlobalSettings_NoFile_Empty;
    [Test]
    procedure LoadGlobalSettings_File_ReturnsText;
    [Test]
    procedure ProjectSettings_NoFile_Defaults;
    /// <summary>#1458: --locale vor language aus settings.json vor Englisch.</summary>
    [Test]
    procedure TextLanguage_LocaleThenSettingThenEnglish;
    [Test]
    procedure ProjectSettings_McpGlobalSettingsOff;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Shell.Bootstrap;

type
  /// <summary>Sammelt die Meldungen als "LEVEL Text".</summary>
  TCaptureLogger = class(TInterfacedObject, ILogger)
  public
    Lines: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure Log(ALevel: TLogLevel; const AText: string);
    procedure Debug(const AText: string);
    procedure Info(const AText: string);
    procedure Warning(const AText: string);
    procedure Error(const AText: string);
  end;

constructor TCaptureLogger.Create;
begin
  inherited Create;
  Lines := TStringList.Create;
end;

destructor TCaptureLogger.Destroy;
begin
  Lines.Free;
  inherited;
end;

procedure TCaptureLogger.Log(ALevel: TLogLevel; const AText: string);
const
  cNames: array[TLogLevel] of string = ('DEBUG', 'INFO', 'WARNING', 'ERROR');
begin
  Lines.Add(cNames[ALevel] + ' ' + AText);
end;

procedure TCaptureLogger.Debug(const AText: string);
begin
  Log(TLogLevel.Debug, AText);
end;

procedure TCaptureLogger.Info(const AText: string);
begin
  Log(TLogLevel.Info, AText);
end;

procedure TCaptureLogger.Warning(const AText: string);
begin
  Log(TLogLevel.Warning, AText);
end;

procedure TCaptureLogger.Error(const AText: string);
begin
  Log(TLogLevel.Error, AText);
end;

const
  cGroup =
    '<?xml version="1.0" encoding="utf-8"?>'#13#10 +
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'#13#10 +
    '  <ItemGroup>'#13#10 +
    '    <Projects Include="App.dproj"><Dependencies/></Projects>'#13#10 +
    '    <Projects Include="Tests.dproj"><Dependencies/></Projects>'#13#10 +
    '  </ItemGroup>'#13#10 +
    '</Project>';

{ TShellBootstrapTests }

procedure TShellBootstrapTests.WarmUpFirstUse;
begin
  Setup;
  try
    ReadSourceText_Utf8Bom_ReturnsText;
  finally
    TearDown;
  end;
end;

procedure TShellBootstrapTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasBootstrap' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FFolder);
end;

procedure TShellBootstrapTests.TearDown;
begin
  if TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  // Der Leckmonitor misst den Saldo von Setup und TearDown.
  FFolder := '';
end;

function TShellBootstrapTests.Write(const AName, AText: string): string;
begin
  Result := TPath.Combine(FFolder, AName);
  TFile.WriteAllText(Result, AText, TEncoding.UTF8);
end;

procedure TShellBootstrapTests.ReadSourceText_Utf8Bom_ReturnsText;
var
  mText: string;
begin
  Assert.IsTrue(TShellBootstrap.ReadSourceText(Write('A.pas', 'unit Ä;'), mText));
  Assert.AreEqual('unit Ä;', mText);
end;

procedure TShellBootstrapTests.ReadSourceText_Missing_ReturnsFalse;
var
  mText: string;
begin
  mText := 'alt';
  Assert.IsFalse(TShellBootstrap.ReadSourceText(TPath.Combine(FFolder, 'Fehlt.pas'), mText));
  Assert.AreEqual('', mText);
  Assert.IsFalse(TShellBootstrap.ReadSourceText('', mText));
end;

procedure TShellBootstrapTests.ReadSourceText_OpenDocumentFirst;
var
  mDocuments: IDocumentStore;
  mFileName, mText: string;
begin
  mFileName := TPath.Combine(FFolder, 'Unit2.dfm');
  TFile.WriteAllText(mFileName, 'Platte', TEncoding.UTF8);
  mDocuments := TDocumentStore.Create;
  // Ohne offenes Dokument die Datei, mit offenem Dokument dessen Stand (Designer, #402).
  Assert.IsTrue(TShellBootstrap.ReadSourceText(mDocuments, mFileName, mText));
  Assert.AreEqual('Platte', mText);
  mDocuments.Open(TDocumentUris.FromPath(mFileName), 'dfm', 1, 'Designer');
  Assert.IsTrue(TShellBootstrap.ReadSourceText(mDocuments, mFileName, mText));
  Assert.AreEqual('Designer', mText);
  Assert.IsTrue(TShellBootstrap.ReadSourceText(nil, mFileName, mText));
  Assert.AreEqual('Platte', mText);
  Assert.IsFalse(TShellBootstrap.ReadSourceText(mDocuments, TPath.Combine(FFolder, 'Fehlt.dfm'), mText));
end;

procedure TShellBootstrapTests.GroupProjects_NoGroup_Empty;
begin
  Assert.AreEqual(0, Integer(Length(TShellBootstrap.GroupProjects(FFolder, nil))));
end;

procedure TShellBootstrapTests.GroupProjects_Groupproj_ListsProjects;
var
  mLogger: TCaptureLogger;
  mKeep: ILogger;
  mProjects: TArray<string>;
begin
  mLogger := TCaptureLogger.Create;
  mKeep := mLogger;
  Write('Gruppe.groupproj', cGroup);
  mProjects := TShellBootstrap.GroupProjects(FFolder, mKeep);
  Assert.AreEqual(2, Integer(Length(mProjects)));
  Assert.IsTrue(mProjects[0].EndsWith('App.dproj'));
  Assert.IsTrue(mProjects[1].EndsWith('Tests.dproj'));
  Assert.Contains(mLogger.Lines.Text, 'INFO Projektgruppe');
end;

procedure TShellBootstrapTests.GroupProjects_TwoGroups_Empty;
begin
  Write('A.groupproj', cGroup);
  Write('B.groupproj', cGroup);
  Assert.AreEqual(0, Integer(Length(TShellBootstrap.GroupProjects(FFolder, nil))));
end;

procedure TShellBootstrapTests.LoadGroup_Invalid_LogsWarning;
var
  mLogger: TCaptureLogger;
  mKeep: ILogger;
begin
  mLogger := TCaptureLogger.Create;
  mKeep := mLogger;
  Assert.AreEqual(0, Integer(Length(TShellBootstrap.LoadGroup(Write('Kaputt.groupproj', '<kein xml'), mKeep))));
  Assert.Contains(mLogger.Lines.Text, 'WARNING Projektgruppe');
end;

procedure TShellBootstrapTests.GlobalSettingsFile_UnderAppData;
begin
  Assert.AreEqual('', TShellBootstrap.GlobalSettingsFile(''));
  Assert.IsTrue(TShellBootstrap.GlobalSettingsFile(FFolder).EndsWith('settings.json'));
  Assert.IsTrue(TShellBootstrap.GlobalSettingsFile(FFolder).StartsWith(FFolder));
end;

procedure TShellBootstrapTests.LoadGlobalSettings_NoFile_Empty;
begin
  Assert.AreEqual('', TShellBootstrap.LoadGlobalSettings(TShellBootstrap.GlobalSettingsFile(FFolder), nil));
  Assert.AreEqual('', TShellBootstrap.LoadGlobalSettings('', nil));
end;

procedure TShellBootstrapTests.LoadGlobalSettings_File_ReturnsText;
var
  mFileName: string;
begin
  mFileName := TShellBootstrap.GlobalSettingsFile(FFolder);
  TDirectory.CreateDirectory(ExtractFileDir(mFileName));
  TFile.WriteAllText(mFileName, '{"mcp": {"disabledTools": ["rename_symbol"]}}', TEncoding.UTF8);
  Assert.AreEqual('{"mcp": {"disabledTools": ["rename_symbol"]}}', TShellBootstrap.LoadGlobalSettings(mFileName, nil));
end;

procedure TShellBootstrapTests.TextLanguage_LocaleThenSettingThenEnglish;
begin
  Assert.IsTrue(TShellBootstrap.TextLanguage('de', '{"language": "en"}') = TTextLanguage.German);
  Assert.IsTrue(TShellBootstrap.TextLanguage('', '{"language": "de"}') = TTextLanguage.German);
  Assert.IsTrue(TShellBootstrap.TextLanguage('', '{"language": ""}') = TTextLanguage.English);
  Assert.IsTrue(TShellBootstrap.TextLanguage('', '') = TTextLanguage.English);
end;

procedure TShellBootstrapTests.ProjectSettings_NoFile_Defaults;
begin
  Assert.IsTrue(TShellBootstrap.ProjectSettings(FFolder).McpGlobalSettings);
end;

procedure TShellBootstrapTests.ProjectSettings_McpGlobalSettingsOff;
var
  mSettings: TServerSettings;
begin
  // language gehört in die globale Datei und wirkt in atlas.json nicht.
  Write(cConfigurationFileName, '{"mcp": {"globalSettings": false}, "language": "en"}');
  mSettings := TShellBootstrap.ProjectSettings(FFolder);
  Assert.IsFalse(mSettings.McpGlobalSettings);
  Assert.AreEqual(TServerSettings.Default.Language, mSettings.Language);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellBootstrapTests);

end.
