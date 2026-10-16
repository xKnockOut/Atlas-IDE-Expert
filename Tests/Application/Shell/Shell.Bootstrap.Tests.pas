unit Shell.Bootstrap.Tests;

// Gemeinsamer Aufbau von LSP-Server, MCP-Modus und Linter (Code-Review D-08):
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
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReadSourceText_Utf8Bom_ReturnsText;
    [Test]
    procedure ReadSourceText_Missing_ReturnsFalse;
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
  Names: array[TLogLevel] of string = ('DEBUG', 'INFO', 'WARNING', 'ERROR');
begin
  Lines.Add(Names[ALevel] + ' ' + AText);
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
  Group =
    '<?xml version="1.0" encoding="utf-8"?>'#13#10 +
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'#13#10 +
    '  <ItemGroup>'#13#10 +
    '    <Projects Include="App.dproj"><Dependencies/></Projects>'#13#10 +
    '    <Projects Include="Tests.dproj"><Dependencies/></Projects>'#13#10 +
    '  </ItemGroup>'#13#10 +
    '</Project>';

{ TShellBootstrapTests }

procedure TShellBootstrapTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasBootstrap' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FFolder);
end;

procedure TShellBootstrapTests.TearDown;
begin
  if TDirectory.Exists(FFolder) then
    TDirectory.Delete(FFolder, True);
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
  Text: string;
begin
  Assert.IsTrue(TShellBootstrap.ReadSourceText(Write('A.pas', 'unit Ä;'), Text));
  Assert.AreEqual('unit Ä;', Text);
end;

procedure TShellBootstrapTests.ReadSourceText_Missing_ReturnsFalse;
var
  Text: string;
begin
  Text := 'alt';
  Assert.IsFalse(TShellBootstrap.ReadSourceText(TPath.Combine(FFolder, 'Fehlt.pas'), Text));
  Assert.AreEqual('', Text);
  Assert.IsFalse(TShellBootstrap.ReadSourceText('', Text));
end;

procedure TShellBootstrapTests.GroupProjects_NoGroup_Empty;
begin
  Assert.AreEqual(0, Integer(Length(TShellBootstrap.GroupProjects(FFolder, nil))));
end;

procedure TShellBootstrapTests.GroupProjects_Groupproj_ListsProjects;
var
  Logger: TCaptureLogger;
  Keep: ILogger;
  Projects: TArray<string>;
begin
  Logger := TCaptureLogger.Create;
  Keep := Logger;
  Write('Gruppe.groupproj', Group);
  Projects := TShellBootstrap.GroupProjects(FFolder, Keep);
  Assert.AreEqual(2, Integer(Length(Projects)));
  Assert.IsTrue(Projects[0].EndsWith('App.dproj'));
  Assert.IsTrue(Projects[1].EndsWith('Tests.dproj'));
  Assert.Contains(Logger.Lines.Text, 'INFO Projektgruppe');
end;

procedure TShellBootstrapTests.GroupProjects_TwoGroups_Empty;
begin
  Write('A.groupproj', Group);
  Write('B.groupproj', Group);
  Assert.AreEqual(0, Integer(Length(TShellBootstrap.GroupProjects(FFolder, nil))));
end;

procedure TShellBootstrapTests.LoadGroup_Invalid_LogsWarning;
var
  Logger: TCaptureLogger;
  Keep: ILogger;
begin
  Logger := TCaptureLogger.Create;
  Keep := Logger;
  Assert.AreEqual(0, Integer(Length(TShellBootstrap.LoadGroup(Write('Kaputt.groupproj', '<kein xml'), Keep))));
  Assert.Contains(Logger.Lines.Text, 'WARNING Projektgruppe');
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
  FileName: string;
begin
  FileName := TShellBootstrap.GlobalSettingsFile(FFolder);
  TDirectory.CreateDirectory(ExtractFileDir(FileName));
  TFile.WriteAllText(FileName, '{"mcp": {"disabledTools": ["rename_symbol"]}}', TEncoding.UTF8);
  Assert.AreEqual('{"mcp": {"disabledTools": ["rename_symbol"]}}', TShellBootstrap.LoadGlobalSettings(FileName, nil));
end;

procedure TShellBootstrapTests.ProjectSettings_NoFile_Defaults;
begin
  Assert.IsTrue(TShellBootstrap.ProjectSettings(FFolder).McpGlobalSettings);
end;

procedure TShellBootstrapTests.ProjectSettings_McpGlobalSettingsOff;
var
  Settings: TServerSettings;
begin
  // language gehört in die globale Datei und wirkt in atlas.json nicht.
  Write(ConfigurationFileName, '{"mcp": {"globalSettings": false}, "language": "en"}');
  Settings := TShellBootstrap.ProjectSettings(FFolder);
  Assert.IsFalse(Settings.McpGlobalSettings);
  Assert.AreEqual(TServerSettings.Default.Language, Settings.Language);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellBootstrapTests);

end.
