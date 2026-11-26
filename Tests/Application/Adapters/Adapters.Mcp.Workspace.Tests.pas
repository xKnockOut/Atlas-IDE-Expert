unit Adapters.Mcp.Workspace.Tests;

// Tests für den Host-Adapter zwischen Mcp und der Arbeitsbereichsgruppe: Einstellungen, Projektdateien,
// Namensräume, Index, Nachladen, Symbole je Datei und der Stand des Index kommen aus der Gruppe.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpWorkspaceAdapterTests = class
  private
    FFolder: string;
    function Path(const AName: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReadsLoadedProject;
    [Test]
    procedure PassesGroupServices;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Processes,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Configuration.Contract,
  Mcp.Contract.Workspace,
  Adapters.Mcp.Workspace,
  Core.Bootstrap,
  Core.Workspace.Listings,
  Core.WorkspaceGroup,
  Atlas.Tests.TempFolder,
  Shell.Composition.Platform;

const
  cDproj = '<?xml version="1.0" encoding="utf-8"?>'#13#10 +
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'#13#10 +
    '  <PropertyGroup>'#13#10'    <MainSource>Lauf.dpr</MainSource>'#13#10 +
    '    <Config Condition="''$(Config)''==''''">Debug</Config>'#13#10 +
    '    <Platform Condition="''$(Platform)''==''''">Win32</Platform>'#13#10 +
    '    <DCC_Namespace>Vcl;System</DCC_Namespace>'#13#10'  </PropertyGroup>'#13#10 +
    '  <ItemGroup>'#13#10 +
    '    <DelphiCompile Include="$(MainSource)"><MainSource>MainSource</MainSource></DelphiCompile>'#13#10 +
    '    <DCCReference Include="Kunde.pas"/>'#13#10 +
    '  </ItemGroup>'#13#10'</Project>'#13#10;
  cProgramm = 'program Lauf;'#13#10'uses'#13#10'  Kunde in ''Kunde.pas'';'#13#10 +
    'begin'#13#10'end.'#13#10;
  cKundeUnit = 'unit Kunde;'#13#10'interface'#13#10'type'#13#10'  TKunde = class'#13#10'  end;'#13#10 +
    'implementation'#13#10'end.'#13#10;
  cSettings = '{ "rules": { "empty-except": "hint" } }';

function NewGroup(const ARoot: string): TCoreWorkspaceGroup;
begin
  Result := TCoreWorkspaceGroup.Create(ARoot, TDocumentStore.Create, TLogger.Create, TSymbolIndex.Create,
    'atlas-test-mcp-workspace', TShellPlatformAdapters.WorkspaceFactories,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := TCoreBootstrap.ReadSourceText(AFileName, AText);
    end);
end;

{ TMcpWorkspaceAdapterTests }

function TMcpWorkspaceAdapterTests.Path(const AName: string): string;
begin
  Result := TPath.Combine(FFolder, AName);
end;

procedure TMcpWorkspaceAdapterTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'Atlas-McpWorkspace-' + IntToStr(Random(MaxInt)));
  ForceDirectories(FFolder);
end;

procedure TMcpWorkspaceAdapterTests.TearDown;
begin
  TSharedUnitListings.Clear;
  TTestTempFolder.Remove(FFolder);
  FFolder := '';
end;

procedure TMcpWorkspaceAdapterTests.ReadsLoadedProject;
var
  mGroup: TCoreWorkspaceGroup;
  mWorkspace: IMcpWorkspace;
  mReason: string;
  mFound: TUnitIndex;
begin
  TFile.WriteAllText(Path('Lauf.dproj'), cDproj);
  TFile.WriteAllText(Path('Lauf.dpr'), cProgramm);
  TFile.WriteAllText(Path('Kunde.pas'), cKundeUnit);
  TFile.WriteAllText(Path('atlas.json'), cSettings);
  mGroup := NewGroup(FFolder);
  try
    mGroup.Main.Setup.ProjectFile := Path('Lauf.dproj');
    mGroup.CacheRoot := Path('Cache');
    mGroup.Load('');
    Assert.IsTrue(mGroup.WaitForIndex(60000), 'Index fertig');
    mWorkspace := TMcpWorkspaceAdapter.ForGroup(mGroup);
    Assert.IsTrue(mWorkspace.Ready(mReason), mReason);
    Assert.AreEqual(Ord(TRuleSeverity.Hint),
      Ord(mWorkspace.Settings.RuleSeverity('empty-except', TRuleSeverity.Default)));
    Assert.AreEqual(Ord(TRuleSeverity.Hint),
      Ord(mWorkspace.SettingsOf(Path('Fremd.pas')).RuleSeverity('empty-except', TRuleSeverity.Default)));
    Assert.AreEqual(Path('atlas.json'), mWorkspace.SettingsFile);
    Assert.AreEqual(TCoreBootstrap.GlobalSettingsFile, mWorkspace.GlobalSettingsFile);
    Assert.AreEqual(string.Join('|', mGroup.Main.State.ProjectFiles), string.Join('|', mWorkspace.ProjectFiles));
    Assert.AreEqual(string.Join('|', mGroup.AllFiles), string.Join('|', mWorkspace.AllFiles));
    Assert.AreEqual(string.Join('|', mGroup.Main.State.Namespaces), string.Join('|', mWorkspace.Namespaces));
    Assert.IsTrue(mWorkspace.Index.FindUnit('Kunde', mFound), 'Unit des Projekts im Index');
    Assert.AreEqual(Path('Kunde.pas'), mWorkspace.CheckSource(Path('Kunde.pas')).FileName);
    mWorkspace := nil;
    mGroup.Stop;
  finally
    mGroup.Free;
  end;
end;

procedure TMcpWorkspaceAdapterTests.PassesGroupServices;
var
  mGroup: TCoreWorkspaceGroup;
  mWorkspace: IMcpWorkspace;
  mIdentity: TIndexProcessInfo;
begin
  mGroup := NewGroup(FFolder);
  try
    mIdentity := Default(TIndexProcessInfo);
    mIdentity.Client := 'probe-client';
    mGroup.ProcessIdentity := mIdentity;
    mWorkspace := TMcpWorkspaceAdapter.ForGroup(mGroup);
    Assert.AreEqual('probe-client', mWorkspace.Client);
    Assert.IsNotNull(mWorkspace.Index, 'Index der Gruppe');
    Assert.IsNotNull(mWorkspace.Queries, 'Code-Abfragen der Gruppe');
    Assert.IsFalse(mWorkspace.EnsureUnit('Gibtsnicht'));
    Assert.IsFalse(mWorkspace.UnitLoader()('Gibtsnicht'));
    mWorkspace := nil;
  finally
    mGroup.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpWorkspaceAdapterTests);

end.
