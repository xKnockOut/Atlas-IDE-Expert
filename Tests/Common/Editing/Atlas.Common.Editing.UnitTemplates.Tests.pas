unit Atlas.Common.Editing.UnitTemplates.Tests;

// Tests für die Gerüste neuer Formulare, Frames, Datenmodule und Komponenten (#299).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TUnitTemplatesTests = class
  public
    [Test]
    procedure FormUnitParses;
    [Test]
    procedure FormUnitWithoutVariable;
    [Test]
    procedure FormDfmParses;
    [Test]
    procedure InheritedDfm;
    [Test]
    procedure ComponentUnitRegisters;
    [Test]
    procedure ProgramGetsUsesAndCreateForm;
    [Test]
    procedure ProgramFrameWithoutCreateForm;
    [Test]
    procedure ProjectGetsReference;
    [Test]
    procedure ProgramGetsPlainUnit;
    [Test]
    procedure PackageGetsContains;
    [Test]
    procedure ProjectWithoutUnitsGetsReference;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Editing.UnitTemplates;

function Parses(const AText: string): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := Length(mTree.Diagnostics) = 0;
  finally
    mTree.Free;
  end;
end;

/// <summary>Wendet ein Edit an, dessen Bereich in einer Zeile liegt; Zeilen mit #10.</summary>
function ApplyOne(const AText: string; const AEdit: TRuleEdit): string;
var
  mLines: TArray<string>;
  mLine: string;
begin
  mLines := AText.Split([#10]);
  mLine := mLines[AEdit.Range.StartPos.Line];
  mLines[AEdit.Range.StartPos.Line] := Copy(mLine, 1, AEdit.Range.StartPos.Character) + AEdit.NewText +
    Copy(mLine, AEdit.Range.EndPos.Character + 1, MaxInt);
  Result := string.Join(#10, mLines);
end;

procedure TUnitTemplatesTests.FormUnitParses;
var
  mText: string;
  mSpec: TFormUnitSpec;
begin
  mSpec := TFormUnitSpec.Create('KundenForm', 'TKundenForm', TFormKind.Form);
  mSpec.GlobalVariable := True;
  mText := TUnitTemplates.FormUnit(mSpec, #13#10);
  Assert.IsTrue(Parses(mText), mText);
  Assert.IsTrue(Pos('  TKundenForm = class(TForm)'#13#10, mText) > 0, mText);
  Assert.IsTrue(Pos('var'#13#10'  KundenForm: TKundenForm;', mText) > 0, mText);
  Assert.IsTrue(Pos('{$R *.dfm}', mText) > 0, mText);
  mSpec := TFormUnitSpec.Create('Daten', 'TDM', TFormKind.DataModule);
  mSpec.GlobalVariable := True;
  mText := TUnitTemplates.FormUnit(mSpec, #10);
  Assert.IsTrue(Pos('uses'#10'  System.SysUtils, System.Classes;', mText) > 0, mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TUnitTemplatesTests.FormUnitWithoutVariable;
var
  mText: string;
  mSpec: TFormUnitSpec;
begin
  mSpec := TFormUnitSpec.Create('Kunde', 'TKundeForm', TFormKind.Form);
  mSpec.Ancestor := 'TBasisForm';
  mSpec.AncestorUnit := 'BasisForm';
  mText := TUnitTemplates.FormUnit(mSpec, #10);
  Assert.AreEqual(0, Pos('var', mText), mText);
  Assert.IsTrue(Pos('class(TBasisForm)', mText) > 0, mText);
  Assert.IsTrue(Pos('Vcl.Dialogs,'#10'  BasisForm;', mText) > 0, mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TUnitTemplatesTests.FormDfmParses;
var
  mKind: TFormKind;
  mDocument: TDfmDocument;
begin
  for mKind := Low(TFormKind) to High(TFormKind) do
  begin
    mDocument := TDfmParser.Parse(TUnitTemplates.FormDfm('TAdresse', mKind, False, #13#10));
    try
      Assert.AreEqual(0, Integer(Length(mDocument.Errors)));
      Assert.AreEqual('Adresse', mDocument.Root.Name);
      Assert.AreEqual('TAdresse', mDocument.Root.TypeName);
    finally
      mDocument.Free;
    end;
  end;
end;

procedure TUnitTemplatesTests.InheritedDfm;
var
  mDocument: TDfmDocument;
begin
  mDocument := TDfmParser.Parse(TUnitTemplates.FormDfm('TKundeForm', TFormKind.Form, True, #10));
  try
    Assert.AreEqual(0, Integer(Length(mDocument.Errors)));
    Assert.AreEqual<TDfmObjectKind>(TDfmObjectKind.Inherited_, mDocument.Root.Kind);
  finally
    mDocument.Free;
  end;
end;

procedure TUnitTemplatesTests.ComponentUnitRegisters;
var
  mText: string;
begin
  mText := TUnitTemplates.ComponentUnit('MyButton', 'TMyButton', 'TButton', 'Vcl.StdCtrls', 'Eigene', #10);
  Assert.IsTrue(Parses(mText), mText);
  Assert.IsTrue(Pos('  TMyButton = class(TButton)', mText) > 0, mText);
  Assert.IsTrue(Pos('  published'#10, mText) > 0, mText);
  Assert.IsTrue(Pos('  RegisterComponents(''Eigene'', [TMyButton]);', mText) > 0, mText);
  Assert.IsTrue(Pos('System.Classes, Vcl.StdCtrls;', mText) > 0, mText);
end;

const
  cProgramText =
    'program App;'#10#10'uses'#10'  Vcl.Forms,'#10'  Haupt in ''Haupt.pas'' {HauptForm};'#10#10'{$R *.res}'#10#10 +
    'begin'#10'  Application.Initialize;'#10'  Application.CreateForm(THauptForm, HauptForm);'#10 +
    '  Application.Run;'#10'end.';

procedure TUnitTemplatesTests.ProgramGetsUsesAndCreateForm;
var
  mEdits: TArray<TRuleEdit>;
  mText: string;
begin
  Assert.IsTrue(TUnitTemplates.ProgramEdits(cProgramText, 'KundenForm', 'KundenForm.pas', 'TKundenForm',
    TFormKind.Form, mEdits));
  Assert.AreEqual(2, Integer(Length(mEdits)));
  // Hinteres Edit zuerst.
  mText := ApplyOne(ApplyOne(cProgramText, mEdits[1]), mEdits[0]);
  Assert.IsTrue(Pos('  Haupt in ''Haupt.pas'' {HauptForm},'#10'  KundenForm in ''KundenForm.pas'' {KundenForm};',
    mText) > 0, mText);
  Assert.IsTrue(Pos('  Application.CreateForm(TKundenForm, KundenForm);'#10'  Application.Run;', mText) > 0, mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TUnitTemplatesTests.ProgramFrameWithoutCreateForm;
var
  mEdits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(TUnitTemplates.ProgramEdits(cProgramText, 'Adresse', 'Adresse.pas', 'TAdresseFrame',
    TFormKind.Frame, mEdits));
  Assert.AreEqual(1, Integer(Length(mEdits)));
  Assert.AreEqual(','#10'  Adresse in ''Adresse.pas'' {AdresseFrame: TFrame}', mEdits[0].NewText);
  Assert.IsFalse(TUnitTemplates.ProgramEdits('program P;'#10'begin'#10'end.', 'A', 'A.pas', 'TA', TFormKind.Form,
    mEdits));
end;

procedure TUnitTemplatesTests.ProgramGetsPlainUnit;
const
  cTests = 'program Tests;'#10'uses'#10'  DUnitX.TestFramework,'#10'  Kunden.Tests in ''Kunden.Tests.pas'';'#10 +
    'begin'#10'end.';
var
  mEdit: TRuleEdit;
  mText: string;
begin
  Assert.IsTrue(TUnitTemplates.UnitProgramEdit(cTests, 'Rechnung.Tests', 'Sub\Rechnung.Tests.pas', mEdit));
  mText := ApplyOne(cTests, mEdit);
  Assert.IsTrue(Pos('  Kunden.Tests in ''Kunden.Tests.pas'','#10'  Rechnung.Tests in ''Sub\Rechnung.Tests.pas'';',
    mText) > 0, mText);
  Assert.IsTrue(Parses(mText), mText);
  // Schon eingetragen (auch mit anderer Schreibweise): kein Edit.
  Assert.IsFalse(TUnitTemplates.UnitProgramEdit(cTests, 'kunden.tests', 'Kunden.Tests.pas', mEdit));
  Assert.IsFalse(TUnitTemplates.UnitProgramEdit('program P;'#10'begin'#10'end.', 'A', 'A.pas', mEdit));
end;

procedure TUnitTemplatesTests.ProjectGetsReference;
const
  cProject = '<Project>'#10'    <ItemGroup>'#10'        <DelphiCompile Include="App.dpr"/>'#10 +
    '        <DCCReference Include="Haupt.pas">'#10'            <Form>HauptForm</Form>'#10 +
    '        </DCCReference>'#10'    </ItemGroup>'#10'</Project>';
var
  mEdit: TRuleEdit;
  mText: string;
begin
  Assert.IsTrue(TUnitTemplates.ProjectEdit(cProject, 'Daten.pas', 'TDM', TFormKind.DataModule, True, mEdit));
  mText := ApplyOne(cProject, mEdit);
  Assert.IsTrue(Pos('        </DCCReference>'#10'        <DCCReference Include="Daten.pas">'#10 +
    '            <Form>DM</Form>'#10'            <FormType>dfm</FormType>'#10 +
    '            <DesignClass>TDataModule</DesignClass>'#10'        </DCCReference>'#10'    </ItemGroup>', mText) > 0,
    mText);
  Assert.IsTrue(TUnitTemplates.ProjectEdit(cProject, 'Werkzeug.pas', '', TFormKind.Form, False, mEdit));
  Assert.AreEqual(#10'        <DCCReference Include="Werkzeug.pas"/>', mEdit.NewText);
  Assert.IsFalse(TUnitTemplates.ProjectEdit('<Project/>', 'A.pas', 'TA', TFormKind.Form, True, mEdit));
end;

procedure TUnitTemplatesTests.PackageGetsContains;
const
  cPackage = 'package Paket;'#10'requires'#10'  rtl,'#10'  vcl;'#10'contains'#10 +
    '  Haupt in ''Haupt.pas'';'#10'end.';
var
  mEdit: TRuleEdit;
  mText: string;
begin
  // Units einer .dpk stehen unter contains, nicht unter requires (#299).
  Assert.IsTrue(TUnitTemplates.UnitProgramEdit(cPackage, 'Knopf', 'Knopf.pas', mEdit));
  mText := ApplyOne(cPackage, mEdit);
  Assert.IsTrue(Pos('  vcl;'#10'contains'#10'  Haupt in ''Haupt.pas'','#10'  Knopf in ''Knopf.pas'';'#10'end.',
    mText) > 0, mText);
  Assert.IsFalse(TUnitTemplates.UnitProgramEdit(cPackage, 'haupt', 'Haupt.pas', mEdit));
end;

procedure TUnitTemplatesTests.ProjectWithoutUnitsGetsReference;
const
  cProject = '<Project>'#10'    <ItemGroup>'#10'        <DelphiCompile Include="App.dpr"/>'#10 +
    '        <BuildConfiguration Include="Base">'#10'            <Key>Base</Key>'#10 +
    '        </BuildConfiguration>'#10'    </ItemGroup>'#10'</Project>';
var
  mEdit: TRuleEdit;
  mText: string;
begin
  Assert.IsTrue(TUnitTemplates.ProjectEdit(cProject, 'Werkzeug.pas', '', TFormKind.Form, False, mEdit));
  mText := ApplyOne(cProject, mEdit);
  Assert.IsTrue(Pos('<DelphiCompile Include="App.dpr"/>'#10'        <DCCReference Include="Werkzeug.pas"/>'#10 +
    '        <BuildConfiguration Include="Base">', mText) > 0, mText);
end;

initialization
  TDUnitX.RegisterTestFixture(TUnitTemplatesTests);

end.
