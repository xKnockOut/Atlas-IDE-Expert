unit Atlas.Core.Tests.MutationShadow.Tests;

// Tests des Schattenprojekts (#1460): Pfade auflösen, dpr (Programmname,
// in-Pfade, mutierte Unit nach Src\ bzw. angehängt, {$R}/{$I}, Schalter
// bleiben, {$R} mit .res und .rc, Unit ohne „in“ oder mit Namen außerhalb
// von ASCII, unbekannte Formen als Problem statt kaputter dpr, offene
// Kommentare und Zeichenketten an jeder Stelle, uses ohne Ende) und dproj
// (MainSource, Name, GUID, Suchpfade, Ausgaben, Ereignisse, Include=, Ordner
// des Originals vorn); Trennung von Original und Schatten:
// Der Lauf schreibt nur in den Ordner des Schattenprojekts, dort liegt keine
// Datei des Originals, und die Ausgaben gehen immer nach Out.

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
    procedure DprResourceWithRcFile;
    [Test]
    procedure DprUnitWithoutIn;
    [Test]
    procedure DprUnitNameOutsideAscii;
    [Test]
    procedure DprPathWithQuote;
    [Test]
    procedure DprUnknownDirectiveFails;
    [Test]
    procedure DprUnknownUsesEntryFails;
    [Test]
    procedure DprWithOpenCommentFails;
    [Test]
    procedure DprWithOpenStringFails;
    [Test]
    procedure DprUsesWithoutEndFails;
    [Test]
    procedure DprWithClosedCommentsBuilds;
    [Test]
    procedure DprojRewritesProject;
    [Test]
    procedure DprojWithoutBaseGroup;
    [Test]
    procedure DprojAlwaysSeparatesOutputs;
    [Test]
    procedure InsideComparesWholeFolders;
    [Test]
    procedure OriginalStaysOutsideShadow;
    [Test]
    procedure UnitOfShadowRefused;
    [Test]
    procedure ShadowWritingElsewhereRefused;
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
  Assert.IsTrue(mShadow.Problem = TAtlasMutationShadowProblem.NoProgram);
end;

/// <summary>dpr mit ADirectives zwischen uses und begin.</summary>
function DprWith(const AUses, ADirectives: string): string;
begin
  Result := 'program Demo.Tests;' + cBreak + cBreak + 'uses' + cBreak + AUses + ';' + cBreak + cBreak + ADirectives +
    cBreak + cBreak + 'begin' + cBreak + 'end.';
end;

/// <summary>Build muss mit AProblem und AText scheitern.</summary>
procedure AssertFails(const ADpr: string; AProblem: TAtlasMutationShadowProblem; const AText: string);
var
  mShadow: TAtlasMutationShadow;
begin
  Assert.IsFalse(TAtlasMutationShadows.Build(Source(ADpr), mShadow), ADpr);
  Assert.IsTrue(mShadow.Problem = AProblem, ADpr);
  Assert.AreEqual(AText, mShadow.ProblemText, ADpr);
  Assert.AreEqual('', mShadow.Dpr);
  Assert.AreEqual('', mShadow.Dproj);
end;

procedure TAtlasMutationShadowTests.DprResourceWithRcFile;
var
  mDpr: string;
begin
  // So trägt die IDE eine .rc des Projekts ein: .res und .rc, beide relativ.
  mDpr := Shadow(Source(DprWith('  Preise', '{$R ''Daten.res'' ''..\Res\Daten.rc''}' + cBreak +
    '{$RESOURCE Bild.res Bild.rc}'))).Dpr;
  Assert.IsTrue(mDpr.Contains('{$R ''C:\P\Tests\Daten.res'' ''C:\P\Res\Daten.rc''}'), mDpr);
  Assert.IsTrue(mDpr.Contains('{$RESOURCE ''C:\P\Tests\Bild.res'' ''C:\P\Tests\Bild.rc''}'), mDpr);
  // Masken bleiben.
  mDpr := Shadow(Source(DprWith('  Preise', '{$R *.dfm}'))).Dpr;
  Assert.IsTrue(mDpr.Contains('{$R *.dfm}'), mDpr);
  // {$I} ohne Anführungszeichen mit Leerzeichen bleibt; der Include-Pfad findet die Datei.
  mDpr := Shadow(Source(DprWith('  Preise', '{$I Meine Defs.inc}'))).Dpr;
  Assert.IsTrue(mDpr.Contains('{$I Meine Defs.inc}'), mDpr);
  mDpr := Shadow(Source(DprWith('  Preise', '{$INCLUDE ''Meine Defs.inc''}'))).Dpr;
  Assert.IsTrue(mDpr.Contains('{$INCLUDE ''C:\P\Tests\Meine Defs.inc''}'), mDpr);
end;

procedure TAtlasMutationShadowTests.DprUnitWithoutIn;
var
  mDpr: string;
begin
  mDpr := Shadow(Source(DprWith('  System.SysUtils,' + cBreak + '  Preise {Form1},' + cBreak +
    '  PreiseTests in ''PreiseTests.pas''', ''))).Dpr;
  Assert.IsTrue(mDpr.Contains('  Preise in ''Src\Preise.pas'' {Form1},' + cBreak), mDpr);
  Assert.IsTrue(mDpr.Contains('  System.SysUtils,' + cBreak), mDpr);
  Assert.IsTrue(mDpr.Contains('PreiseTests in ''C:\P\Tests\PreiseTests.pas'';'), mDpr);
  Assert.AreEqual(1, Integer(Length(mDpr.Split(['Src\Preise.pas'])) - 1), 'nicht ein zweites Mal angehängt');
  // Als letzter Eintrag, ohne Leerraum davor.
  mDpr := Shadow(Source('program X;uses Preise;begin end.')).Dpr;
  Assert.IsTrue(mDpr.Contains('uses Preise in ''Src\Preise.pas'';begin'), mDpr);
  // Ein anderer Name mit demselben Anfang ist nicht die Unit.
  mDpr := Shadow(Source(DprWith('  Preise.Extra', ''))).Dpr;
  Assert.IsTrue(mDpr.Contains('  Preise.Extra,' + cBreak + '  Preise in ''Src\Preise.pas'';'), mDpr);
end;

procedure TAtlasMutationShadowTests.DprUnitNameOutsideAscii;
var
  mSource: TAtlasMutationShadowSource;
  mName, mDpr: string;
begin
  // Als Zeichencodes, damit FPC und Delphi dieselbe Zeichenkette sehen.
  mName := 'Gr' + #$00F6 + #$00DF + 'en';
  mSource := Source(DprWith('  ' + mName + ' in ''..\Src\' + mName + '.pas'',' + cBreak + '  Stra' + #$00DF +
    'e', ''));
  mSource.UnitName := mName;
  mSource.UnitFile := 'C:\P\Src\' + mName + '.pas';
  mDpr := Shadow(mSource).Dpr;
  Assert.IsTrue(mDpr.Contains('  ' + mName + ' in ''Src\' + mName + '.pas'',' + cBreak), mDpr);
  Assert.IsTrue(mDpr.Contains('  Stra' + #$00DF + 'e;'), mDpr);
  Assert.AreEqual(1, Integer(Length(mDpr.Split(['Src\' + mName + '.pas'])) - 1), 'nicht ein zweites Mal angehängt');
end;

procedure TAtlasMutationShadowTests.DprPathWithQuote;
var
  mDpr: string;
begin
  mDpr := Shadow(Source(DprWith('  Preise,' + cBreak + '  Hilfe in ''O''''Brien.pas''',
    '{$I ''O''''Brien.inc''}'))).Dpr;
  Assert.IsTrue(mDpr.Contains('Hilfe in ''C:\P\Tests\O''''Brien.pas'';'), mDpr);
  Assert.IsTrue(mDpr.Contains('{$I ''C:\P\Tests\O''''Brien.inc''}'), mDpr);
end;

procedure TAtlasMutationShadowTests.DprUnknownDirectiveFails;
begin
  AssertFails(DprWith('  Preise', '{$R ''a.res'' ''a.rc'' ''b.rc''}'), TAtlasMutationShadowProblem.Directive,
    '{$R ''a.res'' ''a.rc'' ''b.rc''}');
  AssertFails(DprWith('  Preise', '{$I ''a.inc'' ''b.inc''}'), TAtlasMutationShadowProblem.Directive,
    '{$I ''a.inc'' ''b.inc''}');
  AssertFails(DprWith('  Preise', '{$R ''offen.res}'), TAtlasMutationShadowProblem.Directive, '{$R ''offen.res}');
end;

procedure TAtlasMutationShadowTests.DprUnknownUsesEntryFails;
begin
  AssertFails(DprWith('  Preise,' + cBreak + '  Hilfe in Hilfe.pas', ''), TAtlasMutationShadowProblem.UsesEntry,
    'Hilfe in Hilfe.pas');
  AssertFails(DprWith('  Preise Hilfe', ''), TAtlasMutationShadowProblem.UsesEntry, 'Preise Hilfe');
  AssertFails(DprWith('  Preise,' + cBreak + '  ''Hilfe''', ''), TAtlasMutationShadowProblem.UsesEntry, '''Hilfe''');
end;

procedure TAtlasMutationShadowTests.DprWithOpenCommentFails;
const
  cHead = 'program Demo.Tests;' + cBreak;
  cUses = 'uses' + cBreak + '  System.SysUtils,' + cBreak + '  Preise in ''..\Src\Preise.pas'';' + cBreak;
  cBody = 'begin' + cBreak + 'end.';
var
  mOpen: string;
begin
  // Gespeichert mitten im Auskommentieren: vor dem Programmkopf, vor uses, in uses, hinter uses; "(*)" schließt
  // nicht. Die Textstelle ist die Zeile ab dem offenen Kommentar.
  for mOpen in TArray<string>.Create('(* ', '{ ', '(*) ') do
  begin
    AssertFails(mOpen + cHead + cUses + cBody, TAtlasMutationShadowProblem.Unclosed, Trim(mOpen + cHead));
    AssertFails(cHead + mOpen + cUses + cBody, TAtlasMutationShadowProblem.Unclosed, mOpen + 'uses');
    AssertFails(cHead + 'uses' + cBreak + '  System.SysUtils,' + cBreak + mOpen +
      '  Preise in ''..\Src\Preise.pas'';' + cBreak + cBody, TAtlasMutationShadowProblem.Unclosed,
      mOpen + '  Preise in ''..\Src\Preise.pas'';');
    AssertFails(cHead + cUses + mOpen + cBody, TAtlasMutationShadowProblem.Unclosed, mOpen + 'begin');
  end;
end;

procedure TAtlasMutationShadowTests.DprWithOpenStringFails;
begin
  AssertFails('program X;' + cBreak + 'uses' + cBreak + '  Preise in ''..\Src\Preise.pas;' + cBreak + 'begin' + cBreak +
    'end.', TAtlasMutationShadowProblem.Unclosed, '''..\Src\Preise.pas;');
end;

procedure TAtlasMutationShadowTests.DprUsesWithoutEndFails;
begin
  AssertFails('program X;' + cBreak + 'uses' + cBreak + '  Preise in ''..\Src\Preise.pas''' + cBreak + 'begin' +
    cBreak + 'end.', TAtlasMutationShadowProblem.UsesEntry, 'uses');
end;

procedure TAtlasMutationShadowTests.DprWithClosedCommentsBuilds;
var
  mDpr: string;
begin
  mDpr := Shadow(Source('(* program Alt; *) program X; { uses Alt; }' + cBreak + '(*$R+*) uses' + cBreak +
    '  // Preise in ''alt.pas'';' + cBreak + '  Preise in ''..\Src\Preise.pas'' (* ; *);' + cBreak + 'begin' +
    cBreak + 'end.')).Dpr;
  Assert.IsTrue(mDpr.Contains('(* program Alt; *) program Demo.TestsMutation; { uses Alt; }'), mDpr);
  Assert.IsTrue(mDpr.Contains('// Preise in ''alt.pas'';'), mDpr);
  Assert.IsTrue(mDpr.Contains('  Preise in ''Src\Preise.pas'' (* ; *);'), mDpr);
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

procedure TAtlasMutationShadowTests.DprojAlwaysSeparatesOutputs;
var
  mSource: TAtlasMutationShadowSource;
  mDproj: string;
begin
  // Das Original nennt keine Ausgaben: Ohne Eintrag legte der Compiler die DCUs neben seine Quelltexte.
  mSource := Source(cDpr);
  mSource.Dproj := '<Project>' + cBreak + '    <PropertyGroup Condition="''$(Base)''!=''''">' + cBreak +
    '        <SanitizedProjectName>Demo_Tests</SanitizedProjectName>' + cBreak + '    </PropertyGroup>' + cBreak +
    '    <ItemGroup>' + cBreak + '        <DCCReference Include="..\Src\Preise.pas"/>' + cBreak + '    </ItemGroup>' +
    cBreak + '</Project>';
  mDproj := Shadow(mSource).Dproj;
  Assert.IsTrue(mDproj.Contains('        <DCC_ExeOutput>Out</DCC_ExeOutput>' + cBreak +
    '        <DCC_DcuOutput>Out\Dcu</DCC_DcuOutput>' + cBreak + '        <SanitizedProjectName>'), mDproj);
  // Ohne Basis-Gruppe ebenso.
  mSource.Dproj := '<Project>' + cBreak + '    <ItemGroup>' + cBreak + '    </ItemGroup>' + cBreak + '</Project>';
  mDproj := Shadow(mSource).Dproj;
  Assert.IsTrue(mDproj.Contains('<DCC_DcuOutput>Out\Dcu</DCC_DcuOutput>'), mDproj);
  Assert.IsTrue(mDproj.Contains('<DCC_ExeOutput>Out</DCC_ExeOutput>'), mDproj);
end;

procedure TAtlasMutationShadowTests.InsideComparesWholeFolders;
begin
  Assert.IsTrue(TAtlasMutationShadows.Inside('C:\P\A', 'C:\P\A\x.pas'));
  Assert.IsTrue(TAtlasMutationShadows.Inside('C:\P\A\', 'c:/p/a/B/../x.pas'), 'Schreibweise und ..');
  Assert.IsTrue(TAtlasMutationShadows.Inside('C:\P\A', 'C:\P\A'), 'der Ordner selbst');
  Assert.IsFalse(TAtlasMutationShadows.Inside('C:\P\A', 'C:\P\AB\x.pas'), 'nur gleicher Anfang');
  Assert.IsFalse(TAtlasMutationShadows.Inside('C:\P\A', 'C:\P\A\..\B\x.pas'), '.. aus dem Ordner heraus');
  Assert.IsFalse(TAtlasMutationShadows.Inside('C:\P\A', 'C:\P\x.pas'));
  Assert.IsFalse(TAtlasMutationShadows.Inside('', 'C:\P\x.pas'), 'ohne Ordner');
  Assert.IsFalse(TAtlasMutationShadows.Inside('C:\P\A', ''), 'ohne Datei');
end;

procedure TAtlasMutationShadowTests.OriginalStaysOutsideShadow;
var
  mSource: TAtlasMutationShadowSource;
  mShadow: TAtlasMutationShadow;
  mOriginals: TArray<string>;
  mFile: string;
begin
  mSource := Source(cDpr);
  mShadow := Shadow(mSource);
  Assert.IsTrue(TAtlasMutationShadows.Separate(mSource, mShadow));
  // Alles, was der Lauf schreibt, liegt im Ordner des Schattenprojekts ...
  Assert.IsTrue(TAtlasMutationShadows.IsShadowFile(mShadow, mShadow.DprFile));
  Assert.IsTrue(TAtlasMutationShadows.IsShadowFile(mShadow, mShadow.DprojFile));
  Assert.IsTrue(TAtlasMutationShadows.IsShadowFile(mShadow, mShadow.UnitFile));
  Assert.IsTrue(TAtlasMutationShadows.IsShadowFile(mShadow, mShadow.Folder + '\Src\Preise.dfm'));
  // ... keine Datei des Originals.
  mOriginals := TAtlasMutationShadows.OriginalFiles(mSource);
  Assert.AreEqual(6, Integer(Length(mOriginals)));
  Assert.AreEqual('C:\P\Src\Preise.pas', mOriginals[0]);
  Assert.AreEqual(cProject, mOriginals[1]);
  Assert.AreEqual('C:\P\Tests\Demo.Tests.dpr', mOriginals[2]);
  Assert.AreEqual('C:\P\Tests\Demo.Tests.res', mOriginals[3]);
  Assert.AreEqual('C:\P\Src\Preise.dfm', mOriginals[4]);
  Assert.AreEqual('C:\P\Src\Preise.fmx', mOriginals[5]);
  for mFile in mOriginals do
  begin
    Assert.IsFalse(TAtlasMutationShadows.IsShadowFile(mShadow, mFile), mFile);
  end;
  // Auch eine Unit im Ordner des Testprojekts (neben .atlas-local) bleibt draußen.
  mSource.UnitFile := 'C:\P\Tests\PreiseTests.pas';
  mSource.UnitName := 'PreiseTests';
  Assert.IsTrue(TAtlasMutationShadows.Separate(mSource, Shadow(mSource)));
end;

procedure TAtlasMutationShadowTests.UnitOfShadowRefused;
var
  mSource: TAtlasMutationShadowSource;
  mShadow: TAtlasMutationShadow;
begin
  // Die Kopie eines früheren Laufs im Editor, andere Schreibweise: Der Lauf schriebe genau diese Datei.
  mSource := Source(cDpr);
  mSource.UnitFile := 'c:\p\tests\.ATLAS-LOCAL\Mutation\Demo.Tests\Src\Preise.pas';
  mShadow := Shadow(mSource);
  Assert.IsTrue(TAtlasMutationShadows.IsShadowFile(mShadow, mSource.UnitFile));
  Assert.IsFalse(TAtlasMutationShadows.Separate(mSource, mShadow));
  // Ein Schattenordner, in dem die Unit des Originals liegt.
  mSource := Source(cDpr);
  mShadow := Shadow(mSource);
  mShadow.Folder := 'C:\P\Src';
  mShadow.DprFile := 'C:\P\Src\X.dpr';
  mShadow.DprojFile := 'C:\P\Src\X.dproj';
  mShadow.UnitFile := 'C:\P\Src\Src\Preise.pas';
  Assert.IsFalse(TAtlasMutationShadows.Separate(mSource, mShadow));
end;

procedure TAtlasMutationShadowTests.ShadowWritingElsewhereRefused;
var
  mSource: TAtlasMutationShadowSource;
  mShadow: TAtlasMutationShadow;
begin
  mSource := Source(cDpr);
  mShadow := Shadow(mSource);
  mShadow.UnitFile := 'C:\P\Src\Preise.pas';
  Assert.IsFalse(TAtlasMutationShadows.Separate(mSource, mShadow), 'Kopie wäre das Original');
  mShadow := Shadow(mSource);
  mShadow.DprFile := 'C:\P\Tests\Demo.Tests.dpr';
  Assert.IsFalse(TAtlasMutationShadows.Separate(mSource, mShadow), 'dpr wäre die des Originals');
  mShadow := Shadow(mSource);
  mShadow.DprojFile := mShadow.Folder + '\..\Demo.Tests.dproj';
  Assert.IsFalse(TAtlasMutationShadows.Separate(mSource, mShadow), 'dproj außerhalb über ..');
  Assert.IsFalse(TAtlasMutationShadows.Separate(mSource, Default(TAtlasMutationShadow)), 'ohne Ordner');
  Assert.IsFalse(TAtlasMutationShadows.IsShadowFile(Default(TAtlasMutationShadow), 'C:\P\Src\Preise.pas'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMutationShadowTests);

end.
