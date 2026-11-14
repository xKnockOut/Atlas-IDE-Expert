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
    procedure CombinesPosixFolderWithProjectPaths;
    [Test]
    procedure KeepsAbsolutePaths;
    [Test]
    procedure CommonFolderOfProjects;
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
    /// <summary>#102: Herkunft je Symbol (Projekt, Plattform, Konfiguration).</summary>
    [Test]
    procedure RecordsDefineOrigins;
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
    /// <summary>Mit Ordnerlisten gleiches Ergebnis, jeder Ordner nur einmal gelesen (CPU beim Start).</summary>
    [Test]
    procedure ListsEachDirectoryOnce;
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
  cSampleDproj =
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

  cProjectFile = 'C:\Work\App\App.dproj';

function ReadSample(const AConfig, APlatform: string): TProjectInfo;
var
  mOptions: TDprojOptions;
begin
  mOptions.Config := AConfig;
  mOptions.Platform := APlatform;
  mOptions.Variables := [TPair<string, string>.Create('BDS', 'C:\Studio\37.0')];
  mOptions.FileExists := nil;
  Result := TDprojReader.Read(cProjectFile, cSampleDproj, mOptions);
end;

function Joined(const AItems: TArray<string>): string;
begin
  Result := string.Join(';', AItems);
end;

{ TProjectXmlTests }

procedure TProjectXmlTests.ReadsElementsAttributesAndText;
var
  mRoot: TXmlElement;
begin
  mRoot := TXmlReader.Parse('<?xml version="1.0"?><a x="1" y=''2''><b>Text</b><c/></a>');
  try
    Assert.AreEqual('a', mRoot.Name);
    Assert.AreEqual('1', mRoot.Attribute('x'));
    Assert.AreEqual('2', mRoot.Attribute('y'));
    Assert.AreEqual('', mRoot.Attribute('z'));
    Assert.AreEqual(2, mRoot.ChildCount);
    Assert.AreEqual('Text', mRoot.Find('b').Text);
    Assert.IsNotNull(mRoot.Find('c'));
  finally
    mRoot.Free;
  end;
end;

procedure TProjectXmlTests.DecodesEntitiesAndSkipsComments;
var
  mRoot: TXmlElement;
begin
  mRoot := TXmlReader.Parse('<a v="&quot;x&quot; &amp; &#65;&#x42;"><!-- weg --><![CDATA[<roh>]]>&lt;t&gt;</a>');
  try
    Assert.AreEqual('"x" & AB', mRoot.Attribute('v'));
    Assert.AreEqual('<roh><t>', mRoot.Text);
    Assert.AreEqual(0, mRoot.ChildCount);
  finally
    mRoot.Free;
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
  mProperties: TMSBuildProperties;
begin
  mProperties := TMSBuildProperties.Create;
  try
    mProperties.SetValue('Platform', 'Win64');
    Assert.AreEqual('lib\Win64\release;', mProperties.Expand('lib\$(PLATFORM)\release;$(Unbekannt)'));
  finally
    mProperties.Free;
  end;
end;

procedure TMSBuildTests.EvaluatesComparisons;
var
  mProperties: TMSBuildProperties;
begin
  mProperties := TMSBuildProperties.Create;
  try
    mProperties.SetValue('Config', 'Debug');
    Assert.IsTrue(mProperties.Evaluate('''$(Config)''==''debug'''));
    Assert.IsFalse(mProperties.Evaluate('''$(Config)''!=''Debug'''));
    Assert.IsTrue(mProperties.Evaluate('''$(Base)''=='''''));
    Assert.IsTrue(mProperties.Evaluate(''));
    Assert.IsTrue(mProperties.Evaluate('''37.0'' >= ''23.0'''));
  finally
    mProperties.Free;
  end;
end;

procedure TMSBuildTests.EvaluatesAndOrParenthesesNot;
var
  mProperties: TMSBuildProperties;
begin
  mProperties := TMSBuildProperties.Create;
  try
    mProperties.SetValue('Platform', 'Win64');
    mProperties.SetValue('Base', 'true');
    Assert.IsTrue(mProperties.Evaluate('''$(X)''!='''' or (''$(Platform)''==''Win64'' and ''$(Base)''==''true'')'));
    Assert.IsFalse(mProperties.Evaluate('''$(X)''!='''' or (''$(Platform)''==''Win32'' and ''$(Base)''==''true'')'));
    Assert.IsTrue(mProperties.Evaluate('!(''$(Platform)''==''Win32'')'));
    Assert.IsTrue(mProperties.Evaluate('$(Base)'));
  finally
    mProperties.Free;
  end;
end;

procedure TMSBuildTests.EvaluatesExistsWithCallback;
var
  mProperties: TMSBuildProperties;
begin
  mProperties := TMSBuildProperties.Create(
    function(AFileName: string): Boolean
    begin
      Result := AFileName = 'C:\Studio\x.targets';
    end);
  try
    mProperties.SetValue('BDS', 'C:\Studio');
    Assert.IsTrue(mProperties.Evaluate('Exists(''$(BDS)\x.targets'')'));
    Assert.IsFalse(mProperties.Evaluate('Exists(''$(BDS)\y.targets'')'));
  finally
    mProperties.Free;
  end;
end;

procedure TMSBuildTests.MalformedConditionIsFalse;
var
  mProperties: TMSBuildProperties;
begin
  mProperties := TMSBuildProperties.Create;
  try
    Assert.IsFalse(mProperties.Evaluate('''a''=='));
    Assert.IsFalse(mProperties.Evaluate('(''a''==''a'''));
    Assert.IsFalse(mProperties.Evaluate('Unbekannt(''x'')'));
  finally
    mProperties.Free;
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

procedure TProjectPathsTests.CombinesPosixFolderWithProjectPaths;
begin
  // Linux-Bau (#1109): Projektordner mit "/", Pfade aus dem .dproj mit "\".
  Assert.AreEqual('/home/u/Packages/Atlas.Text/Atlas.Text.dproj',
    TProjectPaths.Combine('/home/u', 'Packages\Atlas.Text\Atlas.Text.dproj'));
  Assert.AreEqual('/home/Shared/Source', TProjectPaths.Combine('/home/u/App', '..\..\Shared\Source\'));
  Assert.AreEqual('/a/b', TProjectPaths.Normalize('/a\\b/'));
  Assert.AreEqual('Source\Unit1.pas', TProjectPaths.Normalize('Source/Unit1.pas\'));
end;

procedure TProjectPathsTests.KeepsAbsolutePaths;
begin
  Assert.AreEqual('D:\Lib', TProjectPaths.Combine('C:\Work', 'D:\Lib'));
  Assert.AreEqual('\\server\share\x', TProjectPaths.Combine('C:\Work', '\\server\share\x'));
  Assert.IsFalse(TProjectPaths.IsAbsolute('Source'));
end;

procedure TProjectPathsTests.CommonFolderOfProjects;
begin
  // Projekte einer Gruppe in Unterordnern: der Stamm (Spalte "Datei" im Abfragefenster).
  Assert.AreEqual('C:\Repo', TProjectPaths.CommonFolder('C:\Repo\Packages\Common', 'c:\repo\Application'));
  Assert.AreEqual('C:\Repo\Packages', TProjectPaths.CommonFolder('C:\Repo\Packages\Common', 'C:\Repo\Packages\Ide\'));
  Assert.AreEqual('C:\Repo', TProjectPaths.CommonFolder('C:\Repo', 'C:\Repo'));
  // Ganze Ordnernamen: C:\Repo2 liegt nicht in C:\Repo.
  Assert.AreEqual('C:\', TProjectPaths.CommonFolder('C:\Repo', 'C:\Repo2'));
  Assert.AreEqual('', TProjectPaths.CommonFolder('C:\Repo', 'D:\Repo'));
  Assert.AreEqual('', TProjectPaths.CommonFolder('', 'C:\Repo'));
  Assert.AreEqual('/home/a', TProjectPaths.CommonFolder('/home/a/x', '/home/a/y'));
  Assert.AreEqual('/', TProjectPaths.CommonFolder('/home', '/opt'));
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
  mProject: TProjectInfo;
begin
  mProject := ReadSample('', '');
  Assert.AreEqual('Debug', mProject.Config);
  Assert.AreEqual('Win32', mProject.Platform);
  Assert.AreEqual('C:\Work\App\App.dpr', mProject.MainSource);
  Assert.AreEqual('DEBUG;APP', Joined(mProject.Defines));
  Assert.AreEqual('System;Xml;Winapi', Joined(mProject.Namespaces));
end;

procedure TDprojReaderTests.AppliesConfigAndPlatform;
var
  mProject: TProjectInfo;
begin
  mProject := ReadSample('Release', 'Win64');
  Assert.AreEqual('Release', mProject.Config);
  Assert.AreEqual('Win64', mProject.Platform);
  Assert.AreEqual('RELEASE;APP', Joined(mProject.Defines));
  Assert.AreEqual('Vcl;System;Xml;Winapi', Joined(mProject.Namespaces));
end;

procedure TDprojReaderTests.RecordsDefineOrigins;
var
  mProject: TProjectInfo;
  mOptions: TDprojOptions;
  mText: string;

  function OriginOf(const AName: string): string;
  var
    mOrigin: TPair<string, string>;
  begin
    Result := '-';
    for mOrigin in mProject.DefineOrigins do
    begin
      if mOrigin.Key = AName then
      begin
        Exit(mOrigin.Value);
      end;
    end;
  end;

begin
  mProject := ReadSample('Debug', 'Win32');
  Assert.AreEqual('Projekt', OriginOf('APP'));
  Assert.AreEqual('Konfiguration Debug', OriginOf('DEBUG'));
  Assert.AreEqual('-', OriginOf('RELEASE'));
  mOptions := Default(TDprojOptions);
  mOptions.Config := 'Release';
  mOptions.Platform := 'Win64';
  // Symbol auf Ebene Base_Win64, RELEASE auf Ebene Cfg_2_Win64.
  mText := StringReplace(cSampleDproj, '    <DCC_Namespace>Vcl;$(DCC_Namespace)</DCC_Namespace>'#13#10,
    '    <DCC_Namespace>Vcl;$(DCC_Namespace)</DCC_Namespace>'#13#10 +
    '    <DCC_Define>W64;$(DCC_Define)</DCC_Define>'#13#10, []);
  mText := StringReplace(mText, '<PropertyGroup Condition="''$(Cfg_2)''!=''''">',
    '<PropertyGroup Condition="''$(Cfg_2_Win64)''!='''' or ''$(Cfg_2)''!=''''">', []);
  mProject := TDprojReader.Read(cProjectFile, mText, mOptions);
  Assert.AreEqual('Projekt, Plattform Win64', OriginOf('W64'));
  Assert.AreEqual('Konfiguration Release, Plattform Win64', OriginOf('RELEASE'));
end;

procedure TDprojReaderTests.ResolvesSearchPathsRelativeToProject;
var
  mProject: TProjectInfo;
begin
  mProject := ReadSample('Debug', 'Win32');
  Assert.AreEqual('C:\Studio\37.0\source\Debug;C:\Work\App\Source;C:\Work\Shared\Source',
    Joined(mProject.SearchPaths));
end;

procedure TDprojReaderTests.ListsProjectUnits;
var
  mProject: TProjectInfo;
begin
  mProject := ReadSample('', '');
  Assert.AreEqual<NativeInt>(2, Length(mProject.Units));
  Assert.AreEqual('Main', mProject.Units[0].Name);
  Assert.AreEqual('C:\Work\App\Source\Main.pas', mProject.Units[0].FileName);
  Assert.AreEqual('Shared.Tools', mProject.Units[1].Name);
  Assert.AreEqual('C:\Work\Shared\Source\Shared.Tools.pas', mProject.Units[1].FileName);
end;

procedure TDprojReaderTests.RejectsInvalidXml;
var
  mOptions: TDprojOptions;
begin
  mOptions := Default(TDprojOptions);
  Assert.WillRaise(
    procedure
    begin
      TDprojReader.Read(cProjectFile, '<Project><PropertyGroup></Project>', mOptions);
    end, EProjectError);
end;

{ TGroupProjReaderTests }

procedure TGroupProjReaderTests.ListsDelphiProjectsOnce;
const
  cGroup =
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
  mProjects: TArray<string>;
begin
  mProjects := TGroupProjReader.Read('C:\Work\Gruppe\Gruppe.groupproj', cGroup);
  // Doppelte Einträge zählen einmal, C++-Projekte fehlen, Reihenfolge wie in der Datei.
  Assert.AreEqual(3, Integer(Length(mProjects)));
  Assert.AreEqual('C:\Work\Gruppe\App\App.dproj', mProjects[0]);
  Assert.AreEqual('C:\Work\Lib\Lib.dproj', mProjects[1]);
  Assert.AreEqual('C:\Work\Gruppe\Tests\Tests.dproj', mProjects[2]);
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
  mExisting: TList<string>;
  mItem: string;
  mFiles: TArray<string>;
begin
  mExisting := TList<string>.Create;
  try
    for mItem in AExisting do
    begin
      mExisting.Add(LowerCase(mItem));
    end;
    mFiles := mExisting.ToArray;
  finally
    mExisting.Free;
  end;
  Result := TUnitResolver.Create(ReadSample('Release', 'Win64'), ['C:\Studio\37.0\source\rtl\sys'],
    function(AFileName: string): Boolean
    var
      Candidate: string;
    begin
      for Candidate in mFiles do
      begin
        if Candidate = LowerCase(AFileName) then
        begin
          Exit(True);
        end;
      end;
      Result := False;
    end);
end;

procedure TUnitResolverTests.PrefersProjectUnits;
var
  mResolver: TUnitResolver;
begin
  mResolver := ResolverFor(['C:\Work\App\Main.pas']);
  try
    Assert.AreEqual('C:\Work\App\Source\Main.pas', mResolver.Resolve('main'));
  finally
    mResolver.Free;
  end;
end;

procedure TUnitResolverTests.SearchesFromDirectoryThenSearchPaths;
var
  mResolver: TUnitResolver;
begin
  mResolver := ResolverFor(['C:\Work\Shared\Source\Helper.pas', 'C:\Other\Helper.pas']);
  try
    Assert.AreEqual('C:\Work\Shared\Source\Helper.pas', mResolver.Resolve('Helper'));
    Assert.AreEqual('C:\Other\Helper.pas', mResolver.Resolve('Helper', 'C:\Other'));
  finally
    mResolver.Free;
  end;
end;

procedure TUnitResolverTests.AppliesNamespacePrefixes;
var
  mResolver: TUnitResolver;
begin
  mResolver := ResolverFor(['C:\Studio\37.0\source\rtl\sys\System.SysUtils.pas']);
  try
    Assert.AreEqual('C:\Studio\37.0\source\rtl\sys\System.SysUtils.pas', mResolver.Resolve('SysUtils'));
    Assert.AreEqual('C:\Studio\37.0\source\rtl\sys\System.SysUtils.pas', mResolver.Resolve('System.SysUtils'));
  finally
    mResolver.Free;
  end;
end;

procedure TUnitResolverTests.ListsEachDirectoryOnce;
var
  mResolver: TUnitResolver;
  mListed: TDictionary<string, Integer>;
  mCount: Integer;
begin
  mListed := TDictionary<string, Integer>.Create;
  mResolver := ResolverFor([]);
  try
    mResolver.ListUnits :=
      function(AFolder: string): TArray<string>
      var
        Known: Integer;
      begin
        if not mListed.TryGetValue(LowerCase(AFolder), Known) then
        begin
          Known := 0;
        end;
        mListed.AddOrSetValue(LowerCase(AFolder), Known + 1);
        if SameText(AFolder, 'C:\Studio\37.0\source\rtl\sys') then
        begin
          Result := ['C:\Studio\37.0\source\rtl\sys\System.SysUtils.pas'];
        end
        else if SameText(AFolder, 'C:\Other') then
        begin
          Result := ['C:\Other\Helper.pas'];
        end
        else
        begin
          Result := nil;
        end;
      end;
    Assert.AreEqual('C:\Studio\37.0\source\rtl\sys\System.SysUtils.pas', mResolver.Resolve('SysUtils'));
    Assert.AreEqual('C:\Studio\37.0\source\rtl\sys\System.SysUtils.pas', mResolver.Resolve('System.SysUtils'));
    Assert.AreEqual('C:\Other\Helper.pas', mResolver.Resolve('Helper', 'C:\Other'));
    Assert.AreEqual('', mResolver.Resolve('Missing'));
    for mCount in mListed.Values do
    begin
      Assert.AreEqual(1, mCount, 'jeder Ordner einmal');
    end;
  finally
    mResolver.Free;
    mListed.Free;
  end;
end;

procedure TUnitResolverTests.ReturnsEmptyWhenNotFound;
var
  mResolver: TUnitResolver;
begin
  mResolver := ResolverFor([]);
  try
    Assert.AreEqual('', mResolver.Resolve('Fehlt'));
    Assert.AreEqual('', mResolver.Resolve(''));
  finally
    mResolver.Free;
  end;
end;

procedure TDprojReaderTests.ListsConfigsAndPlatforms;
var
  mProject: TProjectInfo;
begin
  mProject := ReadSample('', '');
  Assert.AreEqual('Debug;Release', Joined(mProject.Configs));
  Assert.AreEqual('Win32;Win64', Joined(mProject.Platforms));
end;

procedure TDprojReaderTests.ChecksSelectedTarget;
var
  mProject: TProjectInfo;
begin
  mProject := ReadSample('', '');
  Assert.AreEqual('', TDprojReader.CheckTarget(mProject, 'release', 'Win64'));
  Assert.AreEqual('', TDprojReader.CheckTarget(mProject, '', ''));
  Assert.IsTrue(Pos('Profil', TDprojReader.CheckTarget(mProject, 'Profil', '')) > 0);
  Assert.IsTrue(Pos('Linux64', TDprojReader.CheckTarget(mProject, '', 'Linux64')) > 0);
  mProject.Configs := nil;
  Assert.AreEqual('', TDprojReader.CheckTarget(mProject, 'Profil', ''));
end;

initialization
  TDUnitX.RegisterTestFixture(TProjectXmlTests);
  TDUnitX.RegisterTestFixture(TMSBuildTests);
  TDUnitX.RegisterTestFixture(TProjectPathsTests);
  TDUnitX.RegisterTestFixture(TDprojReaderTests);
  TDUnitX.RegisterTestFixture(TGroupProjReaderTests);
  TDUnitX.RegisterTestFixture(TUnitResolverTests);

end.
