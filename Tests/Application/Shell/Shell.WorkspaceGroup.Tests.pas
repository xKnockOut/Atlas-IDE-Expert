unit Shell.WorkspaceGroup.Tests;

// Projektgruppe ohne LSP-Client für MCP und Linter (#1112): Index, Projektkontext der Prüfregeln.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TShellWorkspaceGroupTests = class
  private
    FFolder: string;
    function Path(const AName: string): string;
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen: Der erste Symbolindex im Prozess legt bleibende
    /// Strukturen an, die je nach Reihenfolge der Tests als Leck zählen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Load baut den Index des Projekts auf; RuleProject liefert Index, Anwendungsart und Projektname.
    /// Dateien außerhalb der Projekte gehören zum Hauptarbeitsbereich.</summary>
    [Test]
    procedure LoadIndexesProjectAndGivesRuleProject;
    /// <summary>Ohne Projektdatei gibt es nichts zu warten; RuleProject hat dann keine Anwendungsart.</summary>
    [Test]
    procedure WithoutProjectHasNoApplication;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Contract,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Shell.Bootstrap,
  Shell.WorkspaceGroup;

const
  Dproj = '<?xml version="1.0" encoding="utf-8"?>'#13#10 +
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'#13#10 +
    '  <PropertyGroup>'#13#10'    <MainSource>Lauf.dpr</MainSource>'#13#10 +
    '    <Config Condition="''$(Config)''==''''">Debug</Config>'#13#10 +
    '    <Platform Condition="''$(Platform)''==''''">Win32</Platform>'#13#10 +
    '    <DCC_ConsoleTarget>true</DCC_ConsoleTarget>'#13#10'  </PropertyGroup>'#13#10 +
    '  <ItemGroup>'#13#10 +
    '    <DelphiCompile Include="$(MainSource)"><MainSource>MainSource</MainSource></DelphiCompile>'#13#10 +
    '    <DCCReference Include="Kunde.pas"/>'#13#10 +
    '  </ItemGroup>'#13#10'</Project>'#13#10;
  Programm = 'program Lauf;'#13#10'uses'#13#10'  Kunde in ''Kunde.pas'';'#13#10 +
    'begin'#13#10'end.'#13#10;
  KundeUnit = 'unit Kunde;'#13#10'interface'#13#10'type'#13#10'  TKunde = class'#13#10'  end;'#13#10 +
    'implementation'#13#10'end.'#13#10;

function NewGroup(const ARoot: string): TShellWorkspaceGroup;
begin
  Result := TShellWorkspaceGroup.Create(ARoot, TDocumentStore.Create, TLogger.Create, TSymbolIndex.Create,
    'atlas-test-group',
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := TShellBootstrap.ReadSourceText(AFileName, AText);
    end);
end;

{ TShellWorkspaceGroupTests }

procedure TShellWorkspaceGroupTests.WarmUpFirstUse;
begin
  Setup;
  try
    LoadIndexesProjectAndGivesRuleProject;
  finally
    TearDown;
  end;
end;

procedure TShellWorkspaceGroupTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'Atlas-WorkspaceGroup-' + IntToStr(Random(MaxInt)));
  ForceDirectories(FFolder);
end;

procedure TShellWorkspaceGroupTests.TearDown;
begin
  if TDirectory.Exists(FFolder) then
    TDirectory.Delete(FFolder, True);
  FFolder := '';
end;

function TShellWorkspaceGroupTests.Path(const AName: string): string;
begin
  Result := TPath.Combine(FFolder, AName);
end;

procedure TShellWorkspaceGroupTests.LoadIndexesProjectAndGivesRuleProject;
var
  Group: TShellWorkspaceGroup;
  Project: TCheckProject;
  Reason: string;
  Found: TUnitIndex;
begin
  TFile.WriteAllText(Path('Lauf.dproj'), Dproj);
  TFile.WriteAllText(Path('Lauf.dpr'), Programm);
  TFile.WriteAllText(Path('Kunde.pas'), KundeUnit);
  Group := NewGroup(FFolder);
  try
    Group.Main.ProjectFile := Path('Lauf.dproj');
    Group.CacheRoot := Path('Cache');
    Group.Load('');
    Assert.IsTrue(Group.WaitForIndex(60000), 'Index fertig');
    Assert.IsTrue(Group.Ready(Reason), Reason);
    Project := Group.RuleProject(Path('Kunde.pas'));
    Assert.AreEqual(Path('Kunde.pas'), Project.FileName);
    Assert.IsNotNull(Project.Services.Index, 'Regeln bekommen den Index');
    Assert.IsTrue(Project.Services.Index.FindUnit('Kunde', Found), 'Unit des Projekts im Index');
    Assert.IsTrue(Project.Application = TRuleApplicationKind.Console, 'Anwendungsart aus der .dproj (DCC_ConsoleTarget)');
    Assert.AreEqual('Lauf', Project.Name);
    Assert.IsNotNull(Project.Services.ProjectFiles, 'Projekte der Gruppe für projektweite Regeln');
    Assert.AreSame(Group.Main, Group.WorkspaceOf(Path('Fremd.pas')), 'Fremde Datei: Hauptarbeitsbereich');
    Group.Stop;
  finally
    Group.Free;
  end;
end;

procedure TShellWorkspaceGroupTests.WithoutProjectHasNoApplication;
var
  Group: TShellWorkspaceGroup;
  Project: TCheckProject;
begin
  TFile.WriteAllText(Path('Kunde.pas'), KundeUnit);
  Group := NewGroup(FFolder);
  try
    Group.CacheRoot := Path('Cache');
    Group.Load('');
    Assert.IsTrue(Group.WaitForIndex(60000), 'Ohne Projekt wartet nichts');
    Project := Group.RuleProject(Path('Kunde.pas'));
    Assert.IsTrue(Project.Application = TRuleApplicationKind.Unknown);
    Assert.AreEqual('', Project.Name);
    Group.Stop;
  finally
    Group.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellWorkspaceGroupTests);

end.
