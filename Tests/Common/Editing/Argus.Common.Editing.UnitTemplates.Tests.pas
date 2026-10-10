unit Argus.Common.Editing.UnitTemplates.Tests;

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
  end;

implementation

uses
  System.SysUtils,
  Argus.Common.Rules.Contract,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Pascal.Parser,
  Argus.Common.Dfm.Contract,
  Argus.Common.Dfm.Parser,
  Argus.Common.Editing.UnitTemplates;

function Parses(const AText: string): Boolean;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := Length(Tree.Diagnostics) = 0;
  finally
    Tree.Free;
  end;
end;

/// <summary>Wendet ein Edit an, dessen Bereich in einer Zeile liegt; Zeilen mit #10.</summary>
function ApplyOne(const AText: string; const AEdit: TRuleEdit): string;
var
  Lines: TArray<string>;
  Line: string;
begin
  Lines := AText.Split([#10]);
  Line := Lines[AEdit.Range.StartPos.Line];
  Lines[AEdit.Range.StartPos.Line] := Copy(Line, 1, AEdit.Range.StartPos.Character) + AEdit.NewText +
    Copy(Line, AEdit.Range.EndPos.Character + 1, MaxInt);
  Result := string.Join(#10, Lines);
end;

procedure TUnitTemplatesTests.FormUnitParses;
var
  Text: string;
begin
  Text := TUnitTemplates.FormUnit('KundenForm', 'TKundenForm', '', '', TFormKind.Form, True, #13#10);
  Assert.IsTrue(Parses(Text), Text);
  Assert.IsTrue(Pos('  TKundenForm = class(TForm)'#13#10, Text) > 0, Text);
  Assert.IsTrue(Pos('var'#13#10'  KundenForm: TKundenForm;', Text) > 0, Text);
  Assert.IsTrue(Pos('{$R *.dfm}', Text) > 0, Text);
  Text := TUnitTemplates.FormUnit('Daten', 'TDM', '', '', TFormKind.DataModule, True, #10);
  Assert.IsTrue(Pos('uses'#10'  System.SysUtils, System.Classes;', Text) > 0, Text);
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TUnitTemplatesTests.FormUnitWithoutVariable;
var
  Text: string;
begin
  Text := TUnitTemplates.FormUnit('Kunde', 'TKundeForm', 'TBasisForm', 'BasisForm', TFormKind.Form, False, #10);
  Assert.AreEqual(0, Pos('var', Text), Text);
  Assert.IsTrue(Pos('class(TBasisForm)', Text) > 0, Text);
  Assert.IsTrue(Pos('Vcl.Dialogs,'#10'  BasisForm;', Text) > 0, Text);
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TUnitTemplatesTests.FormDfmParses;
var
  Kind: TFormKind;
  Document: TDfmDocument;
begin
  for Kind := Low(TFormKind) to High(TFormKind) do
  begin
    Document := TDfmParser.Parse(TUnitTemplates.FormDfm('TAdresse', Kind, False, #13#10));
    try
      Assert.AreEqual(0, Integer(Length(Document.Errors)));
      Assert.AreEqual('Adresse', Document.Root.Name);
      Assert.AreEqual('TAdresse', Document.Root.TypeName);
    finally
      Document.Free;
    end;
  end;
end;

procedure TUnitTemplatesTests.InheritedDfm;
var
  Document: TDfmDocument;
begin
  Document := TDfmParser.Parse(TUnitTemplates.FormDfm('TKundeForm', TFormKind.Form, True, #10));
  try
    Assert.AreEqual(0, Integer(Length(Document.Errors)));
    Assert.IsTrue(Document.Root.Kind = TDfmObjectKind.Inherited_);
  finally
    Document.Free;
  end;
end;

procedure TUnitTemplatesTests.ComponentUnitRegisters;
var
  Text: string;
begin
  Text := TUnitTemplates.ComponentUnit('MyButton', 'TMyButton', 'TButton', 'Vcl.StdCtrls', 'Eigene', #10);
  Assert.IsTrue(Parses(Text), Text);
  Assert.IsTrue(Pos('  TMyButton = class(TButton)', Text) > 0, Text);
  Assert.IsTrue(Pos('  published'#10, Text) > 0, Text);
  Assert.IsTrue(Pos('  RegisterComponents(''Eigene'', [TMyButton]);', Text) > 0, Text);
  Assert.IsTrue(Pos('System.Classes, Vcl.StdCtrls;', Text) > 0, Text);
end;

const
  ProgramText =
    'program App;'#10#10'uses'#10'  Vcl.Forms,'#10'  Haupt in ''Haupt.pas'' {HauptForm};'#10#10'{$R *.res}'#10#10 +
    'begin'#10'  Application.Initialize;'#10'  Application.CreateForm(THauptForm, HauptForm);'#10 +
    '  Application.Run;'#10'end.';

procedure TUnitTemplatesTests.ProgramGetsUsesAndCreateForm;
var
  Edits: TArray<TRuleEdit>;
  Text: string;
begin
  Assert.IsTrue(TUnitTemplates.ProgramEdits(ProgramText, 'KundenForm', 'KundenForm.pas', 'TKundenForm',
    TFormKind.Form, Edits));
  Assert.AreEqual(2, Integer(Length(Edits)));
  // Hinteres Edit zuerst.
  Text := ApplyOne(ApplyOne(ProgramText, Edits[1]), Edits[0]);
  Assert.IsTrue(Pos('  Haupt in ''Haupt.pas'' {HauptForm},'#10'  KundenForm in ''KundenForm.pas'' {KundenForm};',
    Text) > 0, Text);
  Assert.IsTrue(Pos('  Application.CreateForm(TKundenForm, KundenForm);'#10'  Application.Run;', Text) > 0, Text);
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TUnitTemplatesTests.ProgramFrameWithoutCreateForm;
var
  Edits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(TUnitTemplates.ProgramEdits(ProgramText, 'Adresse', 'Adresse.pas', 'TAdresseFrame',
    TFormKind.Frame, Edits));
  Assert.AreEqual(1, Integer(Length(Edits)));
  Assert.AreEqual(','#10'  Adresse in ''Adresse.pas'' {AdresseFrame: TFrame}', Edits[0].NewText);
  Assert.IsFalse(TUnitTemplates.ProgramEdits('program P;'#10'begin'#10'end.', 'A', 'A.pas', 'TA', TFormKind.Form,
    Edits));
end;

procedure TUnitTemplatesTests.ProjectGetsReference;
const
  Project = '<Project>'#10'    <ItemGroup>'#10'        <DelphiCompile Include="App.dpr"/>'#10 +
    '        <DCCReference Include="Haupt.pas">'#10'            <Form>HauptForm</Form>'#10 +
    '        </DCCReference>'#10'    </ItemGroup>'#10'</Project>';
var
  Edit: TRuleEdit;
  Text: string;
begin
  Assert.IsTrue(TUnitTemplates.ProjectEdit(Project, 'Daten.pas', 'TDM', TFormKind.DataModule, True, Edit));
  Text := ApplyOne(Project, Edit);
  Assert.IsTrue(Pos('        </DCCReference>'#10'        <DCCReference Include="Daten.pas">'#10 +
    '            <Form>DM</Form>'#10'            <FormType>dfm</FormType>'#10 +
    '            <DesignClass>TDataModule</DesignClass>'#10'        </DCCReference>'#10'    </ItemGroup>', Text) > 0,
    Text);
  Assert.IsTrue(TUnitTemplates.ProjectEdit(Project, 'Werkzeug.pas', '', TFormKind.Form, False, Edit));
  Assert.AreEqual(#10'        <DCCReference Include="Werkzeug.pas"/>', Edit.NewText);
  Assert.IsFalse(TUnitTemplates.ProjectEdit('<Project/>', 'A.pas', 'TA', TFormKind.Form, True, Edit));
end;

initialization
  TDUnitX.RegisterTestFixture(TUnitTemplatesTests);

end.
