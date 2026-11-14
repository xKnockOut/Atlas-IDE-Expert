unit Atlas.Core.Tests.MutationShadow.Tests;

// Tests des Schattenprojekts (#1460): Pfade auflösen, dpr (Programmname,
// in-Pfade, mutierte Unit nach Src\ bzw. angehängt, {$R}/{$I}, Schalter
// bleiben) und dproj (MainSource, Name, GUID, Suchpfade, Ausgaben, Ereignisse,
// Include=, Ordner des Originals vorn).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasMutationShadowTests = class
  public
    [Test]
    procedure ResolvesPaths;
    [Test]
    procedure FilesAndFolders;
    [Test]
    procedure DprRewritesUses;
    [Test]
    procedure DprAppendsMissingUnit;
    [Test]
    procedure DprDirectives;
    [Test]
    procedure DprWithoutProgramFails;
    [Test]
    procedure DprojRewritesProject;
    [Test]
    procedure DprojWithoutBaseGroup;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tests.MutationShadow;

const
  cBreak = #13#10;
  cProject = 'C:\P\Tests\Demo.Tests.dproj';
  cDpr = 'program Demo.Tests;' + cBreak + cBreak + '{$STRONGLINKTYPES ON}' + cBreak + '{$I-}' + cBreak + cBreak +
    'uses' + cBreak + '  System.SysUtils,' + cBreak + '  DUnitX.TestFramework,' + cBreak +
    '  Preise in ''..\Src\Preise.pas'' {Form1},' + cBreak + '  { in ''kommentar.pas'' }' + cBreak +
    '  PreiseTests in ''PreiseTests.pas'';' + cBreak + cBreak + '{$R *.res}' + cBreak + '{$R Extra.res}' + cBreak +
    '{$I Defs.inc}' + cBreak + '{$R+}' + cBreak + cBreak + 'begin' + cBreak + '  Writeln(''in ''''x'''''');' + cBreak +
    'end.';
  cDproj = '<Project>' + cBreak +
    '    <PropertyGroup>' + cBreak +
    '        <ProjectGuid>{DC0B1052-2D81-4586-B491-D72C9FEDE0C7}</ProjectGuid>' + cBreak +
    '        <MainSource>Demo.Tests.dpr</MainSource>' + cBreak +
    '        <ProjectName Condition="''$(ProjectName)''==''''">Demo.Tests</ProjectName>' + cBreak +
    '    </PropertyGroup>' + cBreak +
    '    <PropertyGroup Condition="''$(Base)''!=''''">' + cBreak +
    '        <SanitizedProjectName>Demo_Tests</SanitizedProjectName>' + cBreak +
    '        <DCC_UnitSearchPath>..\Lib;$(DUnitX);C:\Fix;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>' + cBreak +
    '        <DCC_DcuOutput>.\$(Platform)\$(Config)</DCC_DcuOutput>' + cBreak +
    '        <DCC_ExeOutput>..\Bin</DCC_ExeOutput>' + cBreak +
    '        <Icon_MainIcon>Demo_Icon.ico</Icon_MainIcon>' + cBreak +
    '        <PostBuildEvent>copy "$(OUTPUTPATH)" ..\Deploy' + cBreak + 'echo fertig</PostBuildEvent>' + cBreak +
    '    </PropertyGroup>' + cBreak +
    '    <ItemGroup>' + cBreak +
    '        <DelphiCompile Include="$(MainSource)">' + cBreak +
    '            <MainSource>MainSource</MainSource>' + cBreak +
    '        </DelphiCompile>' + cBreak +
    '        <DCCReference Include="..\Src\Preise.pas">' + cBreak +
    '            <Form>Form1</Form>' + cBreak +
    '        </DCCReference>' + cBreak +
    '        <DCCReference Include="PreiseTests.pas"/>' + cBreak +
    '    </ItemGroup>' + cBreak +
    '    <ProjectExtensions><BorlandProject><Delphi.Personality><Source>' + cBreak +
    '        <Source Name="MainSource">Demo.Tests.dpr</Source>' + cBreak +
    '    </Source></Delphi.Personality></BorlandProject></ProjectExtensions>' + cBreak +
    '</Project>';
  cGuid = '{11111111-2222-3333-4444-555555555555}';

function Source(const ADpr: string): TAtlasMutationShadowSource;
begin
  Result := Default(TAtlasMutationShadowSource);
  Result.ProjectFile := cProject;
  Result.Dpr := ADpr;
  Result.Dproj := cDproj;
  Result.UnitName := 'Preise';
  Result.UnitFile := 'C:\P\Src\Preise.pas';
  Result.Guid := cGuid;
  Result.ResExists := True;
end;

function Shadow(const ASource: TAtlasMutationShadowSource): TAtlasMutationShadow;
begin
  Assert.IsTrue(TAtlasMutationShadows.Build(ASource, Result));
end;

{ TAtlasMutationShadowTests }

procedure TAtlasMutationShadowTests.ResolvesPaths;
begin
  Assert.AreEqual('C:\P\Lib', TAtlasMutationShadows.Absolute('C:\P\Tests', '..\Lib'));
  Assert.AreEqual('C:\P\Tests\A\B.pas', TAtlasMutationShadows.Absolute('C:\P\Tests\', '.\A/B.pas'));
  Assert.AreEqual('C:\X', TAtlasMutationShadows.Absolute('C:\P', '..\..\..\X'));
  Assert.AreEqual('\\srv\share\Lib', TAtlasMutationShadows.Absolute('\\srv\share\P', '..\Lib'));
  Assert.AreEqual('$(DUnitX)', TAtlasMutationShadows.Absolute('C:\P', '$(DUnitX)'));
  Assert.AreEqual('D:\Lib', TAtlasMutationShadows.Absolute('C:\P', 'D:\Lib'));
  Assert.AreEqual('%BDS%\x', TAtlasMutationShadows.Absolute('C:\P', '%BDS%\x'));
  Assert.AreEqual('', TAtlasMutationShadows.Absolute('C:\P', ''));
  Assert.IsTrue(TAtlasMutationShadows.IsRooted('\Lib'));
  Assert.IsFalse(TAtlasMutationShadows.IsRooted('Lib'));
end;

procedure TAtlasMutationShadowTests.FilesAndFolders;
var
  mShadow: TAtlasMutationShadow;
  mCompanions: TArray<string>;
begin
  mShadow := Shadow(Source(cDpr));
  Assert.AreEqual('Demo.TestsMutation', mShadow.Name);
  Assert.AreEqual('C:\P\Tests\.atlas-local\mutation\Demo.Tests', mShadow.Folder);
  Assert.AreEqual(mShadow.Folder + '\Demo.TestsMutation.dpr', mShadow.DprFile);
  Assert.AreEqual(mShadow.Folder + '\Demo.TestsMutation.dproj', mShadow.DprojFile);
  Assert.AreEqual(mShadow.Folder + '\Src\Preise.pas', mShadow.UnitFile);
  Assert.AreEqual('C:\P\Tests\.atlas-local\mutation', TAtlasMutationShadows.DataFolderOf(cProject));
  mCompanions := TAtlasMutationShadows.CompanionFiles('C:\P\Src\Preise.pas');
  Assert.AreEqual(2, Integer(Length(mCompanions)));
  Assert.AreEqual('C:\P\Src\Preise.dfm', mCompanions[0]);
  Assert.AreEqual('C:\P\Src\Preise.fmx', mCompanions[1]);
end;

procedure TAtlasMutationShadowTests.DprRewritesUses;
var
  mDpr: string;
begin
  mDpr := Shadow(Source(cDpr)).Dpr;
  Assert.IsTrue(mDpr.StartsWith('program Demo.TestsMutation;'), mDpr);
  Assert.IsTrue(mDpr.Contains('Preise in ''Src\Preise.pas'' {Form1},'), mDpr);
  Assert.IsTrue(mDpr.Contains('PreiseTests in ''C:\P\Tests\PreiseTests.pas'';'), mDpr);
  // Kommentar und Zeichenketten im Programm bleiben unberührt.
  Assert.IsTrue(mDpr.Contains('{ in ''kommentar.pas'' }'), mDpr);
  Assert.IsTrue(mDpr.Contains('Writeln(''in ''''x'''''');'), mDpr);
  Assert.IsFalse(mDpr.Contains('Preise in ''Src\Preise.pas'','), 'nicht doppelt angehängt');
end;

procedure TAtlasMutationShadowTests.DprAppendsMissingUnit;
var
  mSource: TAtlasMutationShadowSource;
  mDpr: string;
begin
  mSource := Source(cDpr);
  mSource.UnitName := 'Hilfen';
  mSource.UnitFile := 'C:\P\Lib\Hilfen.pas';
  mDpr := Shadow(mSource).Dpr;
  Assert.IsTrue(mDpr.Contains('Preise in ''C:\P\Src\Preise.pas'' {Form1},'), mDpr);
  Assert.IsTrue(mDpr.Contains('PreiseTests in ''C:\P\Tests\PreiseTests.pas'',' + cBreak +
    '  Hilfen in ''Src\Hilfen.pas'';'), mDpr);
  // Ohne uses-Klausel bekommt das Programm eine.
  mDpr := Shadow(Source('program X;' + cBreak + 'begin' + cBreak + 'end.')).Dpr;
  Assert.IsTrue(mDpr.Contains('uses' + cBreak + '  Preise in ''Src\Preise.pas'';'), mDpr);
end;

procedure TAtlasMutationShadowTests.DprDirectives;
var
  mSource: TAtlasMutationShadowSource;
  mDpr: string;
begin
  mSource := Source(cDpr);
  mDpr := Shadow(mSource).Dpr;
  Assert.IsTrue(mDpr.Contains('{$R ''C:\P\Tests\Demo.Tests.res''}'), mDpr);
  Assert.IsTrue(mDpr.Contains('{$R ''C:\P\Tests\Extra.res''}'), mDpr);
  Assert.IsTrue(mDpr.Contains('{$I ''C:\P\Tests\Defs.inc''}'), mDpr);
  Assert.IsTrue(mDpr.Contains('{$R+}'), mDpr);
  Assert.IsTrue(mDpr.Contains('{$I-}'), mDpr);
  Assert.IsTrue(mDpr.Contains('{$STRONGLINKTYPES ON}'), mDpr);
  // Ohne .res des Originals fällt {$R *.res} weg.
  mSource.ResExists := False;
  mDpr := Shadow(mSource).Dpr;
  Assert.IsFalse(mDpr.Contains('*.res'), mDpr);
  Assert.IsFalse(mDpr.Contains('Demo.Tests.res'), mDpr);
end;

procedure TAtlasMutationShadowTests.DprWithoutProgramFails;
var
  mShadow: TAtlasMutationShadow;
begin
  Assert.IsFalse(TAtlasMutationShadows.Build(Source('library X;' + cBreak + 'end.'), mShadow));
  Assert.AreEqual('', mShadow.Dpr);
  Assert.AreEqual('', mShadow.Folder);
end;

procedure TAtlasMutationShadowTests.DprojRewritesProject;
var
  mDproj: string;
begin
  mDproj := Shadow(Source(cDpr)).Dproj;
  Assert.IsTrue(mDproj.Contains('<MainSource>Demo.TestsMutation.dpr</MainSource>'), mDproj);
  Assert.IsTrue(mDproj.Contains('<MainSource>MainSource</MainSource>'), mDproj);
  Assert.IsTrue(mDproj.Contains('<Source Name="MainSource">Demo.TestsMutation.dpr</Source>'), mDproj);
  Assert.IsTrue(mDproj.Contains('">Demo.TestsMutation</ProjectName>'), mDproj);
  Assert.IsTrue(mDproj.Contains('<SanitizedProjectName>Demo_TestsMutation</SanitizedProjectName>'), mDproj);
  Assert.IsTrue(mDproj.Contains('<ProjectGuid>' + cGuid + '</ProjectGuid>'), mDproj);
  Assert.IsTrue(mDproj.Contains('<DCC_UnitSearchPath>C:\P\Lib;$(DUnitX);C:\Fix;$(DCC_UnitSearchPath)<'), mDproj);
  Assert.IsTrue(mDproj.Contains('<DCC_DcuOutput>Out\Dcu</DCC_DcuOutput>'), mDproj);
  Assert.IsTrue(mDproj.Contains('<DCC_ExeOutput>Out</DCC_ExeOutput>'), mDproj);
  Assert.IsTrue(mDproj.Contains('<Icon_MainIcon>C:\P\Tests\Demo_Icon.ico</Icon_MainIcon>'), mDproj);
  Assert.IsTrue(mDproj.Contains('<PostBuildEvent></PostBuildEvent>'), mDproj);
  Assert.IsFalse(mDproj.Contains('Deploy'), mDproj);
  Assert.IsTrue(mDproj.Contains('<DCCReference Include="Src\Preise.pas">'), mDproj);
  Assert.IsTrue(mDproj.Contains('<DCCReference Include="C:\P\Tests\PreiseTests.pas"/>'), mDproj);
  Assert.IsTrue(mDproj.Contains('<DelphiCompile Include="$(MainSource)">'), mDproj);
  // Ordner des Originals und der Unit vorn in der Basis-Gruppe.
  Assert.IsTrue(mDproj.Contains('!=''''">' + cBreak +
    '        <DCC_UnitSearchPath>C:\P\Tests;C:\P\Src;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>' + cBreak +
    '        <DCC_IncludePath>C:\P\Tests;C:\P\Src;$(DCC_IncludePath)</DCC_IncludePath>'), mDproj);
end;

procedure TAtlasMutationShadowTests.DprojWithoutBaseGroup;
var
  mSource: TAtlasMutationShadowSource;
  mDproj: string;
begin
  mSource := Source(cDpr);
  mSource.ProjectFile := 'C:\A&B\Demo.Tests.dproj';
  mSource.UnitFile := 'C:\A&B\Preise.pas';
  mSource.Dproj := '<Project>' + cBreak + '    <ItemGroup>' + cBreak +
    '        <DCCReference Include="Preise.pas"/>' + cBreak + '    </ItemGroup>' + cBreak + '</Project>';
  mDproj := Shadow(mSource).Dproj;
  // & wird für XML maskiert, auch beim Vergleich mit der mutierten Unit.
  Assert.IsTrue(mDproj.Contains('<PropertyGroup Condition="''$(Base)''!=''''">' + cBreak +
    '        <DCC_UnitSearchPath>C:\A&amp;B;C:\A&amp;B;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>'), mDproj);
  Assert.IsTrue(mDproj.Contains('</PropertyGroup>' + cBreak + '    <ItemGroup>'), mDproj);
  Assert.IsTrue(mDproj.Contains('<DCCReference Include="Src\Preise.pas"/>'), mDproj);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMutationShadowTests);

end.
