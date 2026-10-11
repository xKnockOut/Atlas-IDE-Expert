unit Atlas.Common.Projects.DprojEditor.Tests;

// Tests für Änderungen an der .dproj als Text (#301).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDprojEditorTests = class
  public
    [Test]
    procedure ConfigKeys;
    [Test]
    procedure AddsOnlyToExistingLine;
    [Test]
    procedure PresentValueUnchanged;
    [Test]
    procedure MissingPropertyGetsLine;
    [Test]
    procedure UnknownGroup;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Projects.DprojEditor;

const
  Dproj =
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'#13#10 +
    '    <PropertyGroup Condition="''$(Base)''!=''''">'#13#10 +
    '        <DCC_UnitSearchPath>Source;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>'#13#10 +
    '    </PropertyGroup>'#13#10 +
    '    <PropertyGroup Condition="''$(Cfg_1)''!=''''">'#13#10 +
    '        <DCC_Define>DEBUG;$(DCC_Define)</DCC_Define>'#13#10 +
    '        <DCC_Optimize>false</DCC_Optimize>'#13#10 +
    '    </PropertyGroup>'#13#10 +
    '    <PropertyGroup Condition="''$(Cfg_2)'' != ''''">'#13#10 +
    '        <DCC_Optimize>true</DCC_Optimize>'#13#10 +
    '    </PropertyGroup>'#13#10 +
    '    <ItemGroup>'#13#10 +
    '        <BuildConfiguration Include="Base">'#13#10 +
    '            <Key>Base</Key>'#13#10 +
    '        </BuildConfiguration>'#13#10 +
    '        <BuildConfiguration Include="Debug">'#13#10 +
    '            <Key>Cfg_1</Key>'#13#10 +
    '            <CfgParent>Base</CfgParent>'#13#10 +
    '        </BuildConfiguration>'#13#10 +
    '        <BuildConfiguration Include="Release">'#13#10 +
    '            <Key>Cfg_2</Key>'#13#10 +
    '            <CfgParent>Base</CfgParent>'#13#10 +
    '        </BuildConfiguration>'#13#10 +
    '    </ItemGroup>'#13#10 +
    '</Project>'#13#10;

procedure TDprojEditorTests.ConfigKeys;
begin
  Assert.AreEqual('Cfg_1', TDprojEditor.ConfigKey(Dproj, 'debug'));
  Assert.AreEqual('Cfg_2', TDprojEditor.ConfigKey(Dproj, 'Release'));
  Assert.AreEqual('Base', TDprojEditor.ConfigKey(Dproj, 'Base'));
  Assert.AreEqual('', TDprojEditor.ConfigKey(Dproj, 'Profil'));
end;

procedure TDprojEditorTests.AddsOnlyToExistingLine;
var
  NewText: string;
begin
  Assert.AreEqual(Ord(TDprojEditResult.Added), Ord(TDprojEditor.AddToList(Dproj, 'Cfg_1', 'DCC_Define', 'TEST',
    NewText)));
  Assert.AreEqual(StringReplace(Dproj, '>DEBUG;', '>TEST;DEBUG;', []), NewText);
  Assert.AreEqual(Ord(TDprojEditResult.Added), Ord(TDprojEditor.AddToList(Dproj, 'Base', 'DCC_UnitSearchPath',
    'Lib\A&B', NewText)));
  Assert.AreEqual(StringReplace(Dproj, '>Source;', '>Lib\A&amp;B;Source;', []), NewText);
end;

procedure TDprojEditorTests.PresentValueUnchanged;
var
  NewText: string;
begin
  Assert.AreEqual(Ord(TDprojEditResult.Present), Ord(TDprojEditor.AddToList(Dproj, 'Cfg_1', 'DCC_Define', 'debug',
    NewText)));
  Assert.AreEqual(Dproj, NewText);
  Assert.IsTrue(TDprojEditor.ListContains('Source\;$(X)', 'source'));
  Assert.IsFalse(TDprojEditor.ListContains('Source;$(X)', 'Sour'));
end;

procedure TDprojEditorTests.MissingPropertyGetsLine;
var
  NewText: string;
begin
  // Bedingung mit Leerzeichen, Eigenschaft fehlt: neue Zeile direkt nach dem öffnenden Tag.
  Assert.AreEqual(Ord(TDprojEditResult.Added), Ord(TDprojEditor.AddToList(Dproj, 'Cfg_2', 'DCC_Define', 'RELEASE',
    NewText)));
  Assert.AreEqual(StringReplace(Dproj, '''$(Cfg_2)'' != ''''">'#13#10, '''$(Cfg_2)'' != ''''">'#13#10 +
    '        <DCC_Define>RELEASE;$(DCC_Define)</DCC_Define>'#13#10, []), NewText);
end;

procedure TDprojEditorTests.UnknownGroup;
var
  NewText: string;
begin
  Assert.AreEqual(Ord(TDprojEditResult.NoGroup), Ord(TDprojEditor.AddToList(Dproj, 'Cfg_9', 'DCC_Define', 'X',
    NewText)));
  Assert.AreEqual(Dproj, NewText);
end;

initialization
  TDUnitX.RegisterTestFixture(TDprojEditorTests);

end.
