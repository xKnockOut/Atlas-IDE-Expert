unit Atlas.Common.Projects.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TProjectXmlTests = class
  public
    [Test]
    procedure ReadsElementsAttributesAndText;
    [Test]
    procedure DecodesEntitiesAndSkipsComments;
    [Test]
    procedure RejectsMismatchedTags;
  end;

  [TestFixture]
  TMSBuildTests = class
  public
    [Test]
    procedure ExpandsPropertiesCaseInsensitive;
    [Test]
    procedure EvaluatesComparisons;
    [Test]
    procedure EvaluatesAndOrParenthesesNot;
    [Test]
    procedure EvaluatesExistsWithCallback;
    [Test]
    procedure MalformedConditionIsFalse;
  end;

  [TestFixture]
  TProjectPathsTests = class
  public
    [Test]
    procedure CombinesAndNormalizesWindowsPaths;
    [Test]
    procedure KeepsAbsolutePaths;
    [Test]
    procedure SplitsNamesAndExtensions;
    [Test]
    procedure ExpandsKnownVariablesOnly;
  end;

  [TestFixture]
  TDprojReaderTests = class
  public
    [Test]
    procedure UsesDefaultsOfFile;
    [Test]
    procedure AppliesConfigAndPlatform;
    [Test]
    procedure ResolvesSearchPathsRelativeToProject;
    [Test]
    procedure ListsProjectUnits;
    [Test]
    procedure RejectsInvalidXml;
    [Test]
    procedure ListsConfigsAndPlatforms;
    [Test]
    procedure ChecksSelectedTarget;
  end;

  [TestFixture]
  TGroupProjReaderTests = class
  public
    [Test]
    procedure ListsDelphiProjectsOnce;
    [Test]
    procedure RejectsInvalidXml;
  end;

  [TestFixture]
  TUnitResolverTests = class
  public
    [Test]
    procedure PrefersProjectUnits;
    [Test]
    procedure SearchesFromDirectoryThenSearchPaths;
    [Test]
    procedure AppliesNamespacePrefixes;
    [Test]
    procedure ReturnsEmptyWhenNotFound;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Projects.Paths,
  Atlas.Common.Projects.DprojReader,
  Atlas.Common.Projects.GroupReader,
  Atlas.Common.Projects.UnitResolver,
  Atlas.Common.Projects.Internals.Xml,
  Atlas.Common.Projects.Internals.MSBuild;

const
  // Gekürzt, aber im Aufbau wie eine von RAD Studio geschriebene .dproj.
  SampleDproj =
    '<?xml version="1.0" encoding="utf-8"?>'#13#10 +
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'#13#10 +
    '  <PropertyGroup>'#13#10 +
    '    <MainSource>App.dpr</MainSource>'#13#10 +
    '    <Config Condition="''$(Config)''==''''">Debug</Config>'#13#10 +
    '    <Platform Condition="''$(Platform)''==''''">Win32</Platform>'#13#10 +
    '  </PropertyGroup>'#13#10 +
    '  <PropertyGroup Condition="''$(Config)''==''Base'' or ''$(Base)''!=''''">'#13#10 +
    '    <Base>true</Base>'#13#10 +
    '  </PropertyGroup>'#13#10 +
    '  <PropertyGroup Condition="''$(Config)''==''Debug'' or ''$(Cfg_1)''!=''''">'#13#10 +
    '    <Cfg_1>true</Cfg_1>'#13#10 +
    '    <Base>true</Base>'#13#10 +
    '  </PropertyGroup>'#13#10 +
    '  <PropertyGroup Condition="''$(Config)''==''Release'' or ''$(Cfg_2)''!=''''">'#13#10 +
    '    <Cfg_2>true</Cfg_2>'#13#10 +
    '    <Base>true</Base>'#13#10 +
    '  </PropertyGroup>'#13#10 +
    '  <PropertyGroup Condition="''$(Base)''!=''''">'#13#10 +
    '    <DCC_Namespace>System;Xml;Winapi;$(DCC_Namespace)</DCC_Namespace>'#13#10 +
    '    <DCC_UnitSearchPath>Source;..\Shared\Source;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>'#13#10 +
    '    <DCC_Define>APP;$(DCC_Define)</DCC_Define>'#13#10 +
    '  </PropertyGroup>'#13#10 +
    '  <PropertyGroup Condition="''$(Base_Win64)''!='''' or (''$(Platform)''==''Win64'' and ''$(Base)''==''true'')">'#13#10 +
    '    <Base_Win64>true</Base_Win64>'#13#10 +
    '    <DCC_Namespace>Vcl;$(DCC_Namespace)</DCC_Namespace>'#13#10 +
    '  </PropertyGroup>'#13#10 +
    '  <PropertyGroup Condition="''$(Cfg_1)''!=''''">'#13#10 +
    '    <DCC_Define>DEBUG;$(DCC_Define)</DCC_Define>'#13#10 +
    '    <DCC_UnitSearchPath>$(BDS)\source\Debug;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>'#13#10 +
    '  </PropertyGroup>'#13#10 +
    '  <PropertyGroup Condition="''$(Cfg_2)''!=''''">'#13#10 +
    '    <DCC_Define>RELEASE;$(DCC_Define)</DCC_Define>'#13#10 +
    '  </PropertyGroup>'#13#10 +
    '  <ItemGroup>'#13#10 +
    '    <DelphiCompile Include="$(MainSource)"><MainSource>MainSource</MainSource></DelphiCompile>'#13#10 +
    '    <DCCReference Include="Source\Main.pas"/>'#13#10 +
    '    <DCCReference Include="..\Shared\Source\Shared.Tools.pas"/>'#13#10 +
    '    <DCCReference Include="vcl.dcp"/>'#13#10 +
    '    <BuildConfiguration Include="Base"><Key>Base</Key></BuildConfiguration>'#13#10 +
    '    <BuildConfiguration Include="Debug"><Key>Cfg_1</Key></BuildConfiguration>'#13#10 +
    '    <BuildConfiguration Include="Release"><Key>Cfg_2</Key></BuildConfiguration>'#13#10 +
    '  </ItemGroup>'#13#10 +
    '  <Import Project="$(BDS)\Bin\CodeGear.Delphi.Targets" Condition="Exists(''$(BDS)\Bin\CodeGear.Delphi.Targets'')"/>'#13#10 +
    '  <ProjectExtensions><BorlandProject><Platforms>'#13#10 +
    '    <Platform value="Win32">True</Platform>'#13#10 +
    '    <Platform value="Win64">True</Platform>'#13#10 +
    '    <Platform value="Linux64">False</Platform>'#13#10 +
    '  </Platforms></BorlandProject></ProjectExtensions>'#13#10 +
    '</Project>';

  ProjectFile = 'C:\Work\App\App.dproj';

function ReadSample(const AConfig, APlatform: string): TProjectInfo;
var
  Options: TDprojOptions;
begin
  Options.Config := AConfig;
  Options.Platform := APlatform;
  Options.Variables := [TPair<string, string>.Create('BDS', 'C:\Studio\37.0')];
  Options.FileExists := nil;
  Result := TDprojReader.Read(ProjectFile, SampleDproj, Options);
end;

function Joined(const AItems: TArray<string>): string;
begin
  Result := string.Join(';', AItems);
end;

{ TProjectXmlTests }

procedure TProjectXmlTests.ReadsElementsAttributesAndText;
var
  Root: TXmlElement;
begin
  Root := TXmlReader.Parse('<?xml version="1.0"?><a x="1" y=''2''><b>Text</b><c/></a>');
  try
    Assert.AreEqual('a', Root.Name);
    Assert.AreEqual('1', Root.Attribute('x'));
    Assert.AreEqual('2', Root.Attribute('y'));
    Assert.AreEqual('', Root.Attribute('z'));
    Assert.AreEqual(2, Root.ChildCount);
    Assert.AreEqual('Text', Root.Find('b').Text);
    Assert.IsNotNull(Root.Find('c'));
  finally
    Root.Free;
  end;
end;

procedure TProjectXmlTests.DecodesEntitiesAndSkipsComments;
var
  Root: TXmlElement;
begin
  Root := TXmlReader.Parse('<a v="&quot;x&quot; &amp; &#65;&#x42;"><!-- weg --><![CDATA[<roh>]]>&lt;t&gt;</a>');
  try
    Assert.AreEqual('"x" & AB', Root.Attribute('v'));
    Assert.AreEqual('<roh><t>', Root.Text);
    Assert.AreEqual(0, Root.ChildCount);
  finally
    Root.Free;
  end;
end;

procedure TProjectXmlTests.RejectsMismatchedTags;
begin
  Assert.WillRaise(
    procedure
    begin
      TXmlReader.Parse('<a><b></a>').Free;
    end, EXmlError);
end;

{ TMSBuildTests }

procedure TMSBuildTests.ExpandsPropertiesCaseInsensitive;
var
  Properties: TMSBuildProperties;
begin
  Properties := TMSBuildProperties.Create;
  try
    Properties.SetValue('Platform', 'Win64');
    Assert.AreEqual('lib\Win64\release;', Properties.Expand('lib\$(PLATFORM)\release;$(Unbekannt)'));
  finally
    Properties.Free;
  end;
end;

procedure TMSBuildTests.EvaluatesComparisons;
var
  Properties: TMSBuildProperties;
begin
  Properties := TMSBuildProperties.Create;
  try
    Properties.SetValue('Config', 'Debug');
    Assert.IsTrue(Properties.Evaluate('''$(Config)''==''debug'''));
    Assert.IsFalse(Properties.Evaluate('''$(Config)''!=''Debug'''));
    Assert.IsTrue(Properties.Evaluate('''$(Base)''=='''''));
    Assert.IsTrue(Properties.Evaluate(''));
    Assert.IsTrue(Properties.Evaluate('''37.0'' >= ''23.0'''));
  finally
    Properties.Free;
  end;
end;

procedure TMSBuildTests.EvaluatesAndOrParenthesesNot;
var
  Properties: TMSBuildProperties;
begin
  Properties := TMSBuildProperties.Create;
  try
    Properties.SetValue('Platform', 'Win64');
    Properties.SetValue('Base', 'true');
    Assert.IsTrue(Properties.Evaluate('''$(X)''!='''' or (''$(Platform)''==''Win64'' and ''$(Base)''==''true'')'));
    Assert.IsFalse(Properties.Evaluate('''$(X)''!='''' or (''$(Platform)''==''Win32'' and ''$(Base)''==''true'')'));
    Assert.IsTrue(Properties.Evaluate('!(''$(Platform)''==''Win32'')'));
    Assert.IsTrue(Properties.Evaluate('$(Base)'));
  finally
    Properties.Free;
  end;
end;

procedure TMSBuildTests.EvaluatesExistsWithCallback;
var
  Properties: TMSBuildProperties;
begin
  Properties := TMSBuildProperties.Create(
    function(AFileName: string): Boolean
    begin
      Result := AFileName = 'C:\Studio\x.targets';
    end);
  try
    Properties.SetValue('BDS', 'C:\Studio');
    Assert.IsTrue(Properties.Evaluate('Exists(''$(BDS)\x.targets'')'));
    Assert.IsFalse(Properties.Evaluate('Exists(''$(BDS)\y.targets'')'));
  finally
    Properties.Free;
  end;
end;

procedure TMSBuildTests.MalformedConditionIsFalse;
var
  Properties: TMSBuildProperties;
begin
  Properties := TMSBuildProperties.Create;
  try
    Assert.IsFalse(Properties.Evaluate('''a''=='));
    Assert.IsFalse(Properties.Evaluate('(''a''==''a'''));
    Assert.IsFalse(Properties.Evaluate('Unbekannt(''x'')'));
  finally
    Properties.Free;
  end;
end;

{ TProjectPathsTests }

procedure TProjectPathsTests.CombinesAndNormalizesWindowsPaths;
begin
  Assert.AreEqual('C:\Work\Shared\Source', TProjectPaths.Combine('C:\Work\App', '..\Shared\Source'));
  Assert.AreEqual('C:\Work\App\Source', TProjectPaths.Combine('C:\Work\App', '.\Source\'));
  Assert.AreEqual('C:\Work', TProjectPaths.Combine('C:\Work\App', '..'));
  Assert.AreEqual('C:\', TProjectPaths.Normalize('C:\..\..'));
  Assert.AreEqual('C:\a\b', TProjectPaths.Normalize('C:/a//b/'));
end;

procedure TProjectPathsTests.KeepsAbsolutePaths;
begin
  Assert.AreEqual('D:\Lib', TProjectPaths.Combine('C:\Work', 'D:\Lib'));
  Assert.AreEqual('\\server\share\x', TProjectPaths.Combine('C:\Work', '\\server\share\x'));
  Assert.IsFalse(TProjectPaths.IsAbsolute('Source'));
end;

procedure TProjectPathsTests.SplitsNamesAndExtensions;
begin
  Assert.AreEqual('C:\Work\App', TProjectPaths.DirectoryOf('C:\Work\App\App.dproj'));
  Assert.AreEqual('C:\', TProjectPaths.DirectoryOf('C:\App.dproj'));
  Assert.AreEqual('Shared.Tools', TProjectPaths.BaseName('..\Shared\Shared.Tools.pas'));
  Assert.AreEqual('.pas', TProjectPaths.Extension('X\Unit1.PAS'));
  Assert.AreEqual('a;b', Joined(TProjectPaths.SplitList(' a ;;b;')));
end;

procedure TProjectPathsTests.ExpandsKnownVariablesOnly;
begin
  Assert.AreEqual('C:\Studio\lib\$(Unbekannt)',
    TProjectPaths.ExpandVariables('$(bdslib)\$(Unbekannt)',
      [TPair<string, string>.Create('BDSLIB', 'C:\Studio\lib')]));
end;

{ TDprojReaderTests }

procedure TDprojReaderTests.UsesDefaultsOfFile;
var
  Project: TProjectInfo;
begin
  Project := ReadSample('', '');
  Assert.AreEqual('Debug', Project.Config);
  Assert.AreEqual('Win32', Project.Platform);
  Assert.AreEqual('C:\Work\App\App.dpr', Project.MainSource);
  Assert.AreEqual('DEBUG;APP', Joined(Project.Defines));
  Assert.AreEqual('System;Xml;Winapi', Joined(Project.Namespaces));
end;

procedure TDprojReaderTests.AppliesConfigAndPlatform;
var
  Project: TProjectInfo;
begin
  Project := ReadSample('Release', 'Win64');
  Assert.AreEqual('Release', Project.Config);
  Assert.AreEqual('Win64', Project.Platform);
  Assert.AreEqual('RELEASE;APP', Joined(Project.Defines));
  Assert.AreEqual('Vcl;System;Xml;Winapi', Joined(Project.Namespaces));
end;

procedure TDprojReaderTests.ResolvesSearchPathsRelativeToProject;
var
  Project: TProjectInfo;
begin
  Project := ReadSample('Debug', 'Win32');
  Assert.AreEqual('C:\Studio\37.0\source\Debug;C:\Work\App\Source;C:\Work\Shared\Source',
    Joined(Project.SearchPaths));
end;

procedure TDprojReaderTests.ListsProjectUnits;
var
  Project: TProjectInfo;
begin
  Project := ReadSample('', '');
  Assert.AreEqual<NativeInt>(2, Length(Project.Units));
  Assert.AreEqual('Main', Project.Units[0].Name);
  Assert.AreEqual('C:\Work\App\Source\Main.pas', Project.Units[0].FileName);
  Assert.AreEqual('Shared.Tools', Project.Units[1].Name);
  Assert.AreEqual('C:\Work\Shared\Source\Shared.Tools.pas', Project.Units[1].FileName);
end;

procedure TDprojReaderTests.RejectsInvalidXml;
var
  Options: TDprojOptions;
begin
  Options := Default(TDprojOptions);
  Assert.WillRaise(
    procedure
    begin
      TDprojReader.Read(ProjectFile, '<Project><PropertyGroup></Project>', Options);
    end, EProjectError);
end;

{ TGroupProjReaderTests }

procedure TGroupProjReaderTests.ListsDelphiProjectsOnce;
const
  Group =
    '<?xml version="1.0" encoding="utf-8"?>'#13#10 +
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'#13#10 +
    '  <PropertyGroup><ProjectGuid>{1}</ProjectGuid></PropertyGroup>'#13#10 +
    '  <ItemGroup>'#13#10 +
    '    <Projects Include="App\App.dproj"><Dependencies/></Projects>'#13#10 +
    '    <Projects Include="..\Lib\Lib.dproj"><Dependencies/></Projects>'#13#10 +
    '    <Projects Include="app\APP.dproj"><Dependencies/></Projects>'#13#10 +
    '    <Projects Include="Alt\Alt.cbproj"><Dependencies/></Projects>'#13#10 +
    '  </ItemGroup>'#13#10 +
    '  <ItemGroup><Projects Include="Tests\Tests.dproj"/></ItemGroup>'#13#10 +
    '</Project>';
var
  Projects: TArray<string>;
begin
  Projects := TGroupProjReader.Read('C:\Work\Gruppe\Gruppe.groupproj', Group);
  // Doppelte Einträge zählen einmal, C++-Projekte fehlen, Reihenfolge wie in der Datei.
  Assert.AreEqual(3, Integer(Length(Projects)));
  Assert.AreEqual('C:\Work\Gruppe\App\App.dproj', Projects[0]);
  Assert.AreEqual('C:\Work\Lib\Lib.dproj', Projects[1]);
  Assert.AreEqual('C:\Work\Gruppe\Tests\Tests.dproj', Projects[2]);
end;

procedure TGroupProjReaderTests.RejectsInvalidXml;
begin
  Assert.WillRaise(
    procedure
    begin
      TGroupProjReader.Read('C:\Work\Gruppe.groupproj', '<Project><ItemGroup></Project>');
    end, EProjectError);
end;

{ TUnitResolverTests }

function ResolverFor(const AExisting: array of string): TUnitResolver;
var
  Existing: TList<string>;
  Item: string;
  Files: TArray<string>;
begin
  Existing := TList<string>.Create;
  try
    for Item in AExisting do
      Existing.Add(LowerCase(Item));
    Files := Existing.ToArray;
  finally
    Existing.Free;
  end;
  Result := TUnitResolver.Create(ReadSample('Release', 'Win64'), ['C:\Studio\37.0\source\rtl\sys'],
    function(AFileName: string): Boolean
    var
      Candidate: string;
    begin
      for Candidate in Files do
        if Candidate = LowerCase(AFileName) then
          Exit(True);
      Result := False;
    end);
end;

procedure TUnitResolverTests.PrefersProjectUnits;
var
  Resolver: TUnitResolver;
begin
  Resolver := ResolverFor(['C:\Work\App\Main.pas']);
  try
    Assert.AreEqual('C:\Work\App\Source\Main.pas', Resolver.Resolve('main'));
  finally
    Resolver.Free;
  end;
end;

procedure TUnitResolverTests.SearchesFromDirectoryThenSearchPaths;
var
  Resolver: TUnitResolver;
begin
  Resolver := ResolverFor(['C:\Work\Shared\Source\Helper.pas', 'C:\Other\Helper.pas']);
  try
    Assert.AreEqual('C:\Work\Shared\Source\Helper.pas', Resolver.Resolve('Helper'));
    Assert.AreEqual('C:\Other\Helper.pas', Resolver.Resolve('Helper', 'C:\Other'));
  finally
    Resolver.Free;
  end;
end;

procedure TUnitResolverTests.AppliesNamespacePrefixes;
var
  Resolver: TUnitResolver;
begin
  Resolver := ResolverFor(['C:\Studio\37.0\source\rtl\sys\System.SysUtils.pas']);
  try
    Assert.AreEqual('C:\Studio\37.0\source\rtl\sys\System.SysUtils.pas', Resolver.Resolve('SysUtils'));
    Assert.AreEqual('C:\Studio\37.0\source\rtl\sys\System.SysUtils.pas', Resolver.Resolve('System.SysUtils'));
  finally
    Resolver.Free;
  end;
end;

procedure TUnitResolverTests.ReturnsEmptyWhenNotFound;
var
  Resolver: TUnitResolver;
begin
  Resolver := ResolverFor([]);
  try
    Assert.AreEqual('', Resolver.Resolve('Fehlt'));
    Assert.AreEqual('', Resolver.Resolve(''));
  finally
    Resolver.Free;
  end;
end;

procedure TDprojReaderTests.ListsConfigsAndPlatforms;
var
  Project: TProjectInfo;
begin
  Project := ReadSample('', '');
  Assert.AreEqual('Debug;Release', Joined(Project.Configs));
  Assert.AreEqual('Win32;Win64', Joined(Project.Platforms));
end;

procedure TDprojReaderTests.ChecksSelectedTarget;
var
  Project: TProjectInfo;
begin
  Project := ReadSample('', '');
  Assert.AreEqual('', TDprojReader.CheckTarget(Project, 'release', 'Win64'));
  Assert.AreEqual('', TDprojReader.CheckTarget(Project, '', ''));
  Assert.IsTrue(Pos('Profil', TDprojReader.CheckTarget(Project, 'Profil', '')) > 0);
  Assert.IsTrue(Pos('Linux64', TDprojReader.CheckTarget(Project, '', 'Linux64')) > 0);
  Project.Configs := nil;
  Assert.AreEqual('', TDprojReader.CheckTarget(Project, 'Profil', ''));
end;

initialization
  TDUnitX.RegisterTestFixture(TProjectXmlTests);
  TDUnitX.RegisterTestFixture(TMSBuildTests);
  TDUnitX.RegisterTestFixture(TProjectPathsTests);
  TDUnitX.RegisterTestFixture(TDprojReaderTests);
  TDUnitX.RegisterTestFixture(TGroupProjReaderTests);
  TDUnitX.RegisterTestFixture(TUnitResolverTests);

end.
