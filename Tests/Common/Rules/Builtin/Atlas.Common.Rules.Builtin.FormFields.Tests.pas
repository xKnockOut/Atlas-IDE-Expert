unit Atlas.Common.Rules.Builtin.FormFields.Tests;

// Tests für den Abgleich von Formularfeldern und DFM-Objekten (#123) und für
// form-access-before-create (#956) mit der CreateForm-Reihenfolge der .dpr.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFormFieldRulesTests = class
  public
    [Test]
    procedure DeletedObjectWithFieldReports;
    [Test]
    procedure NonPublishedFieldIsSilent;
    [Test]
    procedure ObjectWithoutFieldAddsField;
    [Test]
    procedure TypeMismatchFixesType;
    [Test]
    procedure InheritedFormIsSilent;
    [Test]
    procedure FrameObjectsAreSilent;
    [Test]
    procedure UnnamedMenuItemIsSilent;
    [Test]
    procedure WithoutFormFileIsSilent;
    [Test]
    procedure FormAccessIssueExample;
    [Test]
    procedure FormAccessVariants;
    [Test]
    procedure FormAccessSilentCases;
    [Test]
    procedure FormAccessOffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.FormFields,
  Atlas.Tests.RuleAssert;

function FormUnit(const AMembers: string): string;
begin
  Result := 'unit Unit1;'#10'interface'#10'type'#10'  TForm1 = class(TForm)'#10 + AMembers + #10 +
    '  private'#10'    FZahl: Integer;'#10'  end;'#10'implementation'#10'end.';
end;

function ApplyFix(const AText: string; const AFix: TRuleFix): string;
var
  Index: Integer;
  Edit: TRuleEdit;

  function OffsetOf(const APosition: TTextPosition): Integer;
  var
    Line, Position: Integer;
  begin
    Position := 0;
    for Line := 1 to APosition.Line do
      Position := Pos(#10, AText, Position + 1);
    Result := Position + APosition.Character;
  end;

begin
  Result := AText;
  for Index := High(AFix.Edits) downto 0 do
  begin
    Edit := AFix.Edits[Index];
    Result := Copy(Result, 1, OffsetOf(Edit.Range.StartPos)) + Edit.NewText +
      Copy(Result, OffsetOf(Edit.Range.EndPos) + 1, MaxInt);
  end;
end;

procedure TFormFieldRulesTests.DeletedObjectWithFieldReports;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.FormFindings(TFormFieldWithoutObjectRule.Create,
    FormUnit('    Edit1: TEdit;'#10'    Button1: TButton;'),
    'object Form1: TForm1'#10'  object Button1: TButton'#10'  end'#10'end'#10);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(4, Findings[0].Range.StartPos.Line);
  Assert.IsTrue(Pos('Edit1', Findings[0].Message) > 0, Findings[0].Message);
end;

procedure TFormFieldRulesTests.NonPublishedFieldIsSilent;
begin
  // FZahl steht unter private.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.FormFindings(TFormFieldWithoutObjectRule.Create,
    FormUnit('    Button1: TButton;'), 'object Form1: TForm1'#10'  object Button1: TButton'#10'  end'#10'end'#10))));
end;

procedure TFormFieldRulesTests.ObjectWithoutFieldAddsField;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := FormUnit('    Button1: TButton;');
  Findings := TRuleAssert.FormFindings(TFormObjectWithoutFieldRule.Create, Source,
    'object Form1: TForm1'#10'  object Button1: TButton'#10'  end'#10'  object Edit1: TEdit'#10'  end'#10'end'#10);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(FormUnit('    Button1: TButton;'#10'    Edit1: TEdit;'), ApplyFix(Source, Findings[0].Fixes[0]));
end;

procedure TFormFieldRulesTests.TypeMismatchFixesType;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := FormUnit('    Edit1: TEdit;');
  Findings := TRuleAssert.FormFindings(TFormFieldTypeMismatchRule.Create, Source,
    'object Form1: TForm1'#10'  object Edit1: TMaskEdit'#10'  end'#10'end'#10);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(FormUnit('    Edit1: TMaskEdit;'), ApplyFix(Source, Findings[0].Fixes[0]));
end;

procedure TFormFieldRulesTests.InheritedFormIsSilent;
const
  Form = 'inherited Form1: TForm1'#10'  inherited Ok: TButton'#10'    Caption = ''Los'''#10'  end'#10'end'#10;
begin
  // Ok ist ein Feld des Vorfahren.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.FormFindings(TFormObjectWithoutFieldRule.Create,
    FormUnit(''), Form))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.FormFindings(TFormFieldWithoutObjectRule.Create,
    FormUnit(''), Form))));
end;

procedure TFormFieldRulesTests.FrameObjectsAreSilent;
const
  Form = 'object Form1: TForm1'#10'  inline Rahmen1: TRahmen'#10'    inherited Liste: TListBox'#10'    end'#10 +
    '    object Extra: TLabel'#10'    end'#10'  end'#10'end'#10;
begin
  // Liste und Extra gehören zur Frame-Klasse; nur Rahmen1 braucht ein Feld.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.FormFindings(TFormObjectWithoutFieldRule.Create,
    FormUnit('    Rahmen1: TRahmen;'), Form))));
end;

procedure TFormFieldRulesTests.UnnamedMenuItemIsSilent;
const
  Form = 'object Form1: TForm1'#10'  object Menu: TMainMenu'#10'    object TMenuItem'#10'    end'#10'  end'#10'end'#10;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.FormFindings(TFormObjectWithoutFieldRule.Create,
    FormUnit('    Menu: TMainMenu;'), Form))));
end;

procedure TFormFieldRulesTests.WithoutFormFileIsSilent;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.FormFindings(TFormFieldWithoutObjectRule.Create,
    FormUnit('    Edit1: TEdit;'), ''))));
end;

function Haupt(const ABody: string): string;
begin
  Result := 'unit Haupt;'#10'interface'#10'type'#10'  TfrmHaupt = class(TForm)'#10'    lblNutzer: TLabel;'#10 +
    '    procedure FormCreate(Sender: TObject);'#10'  end;'#10'var'#10'  frmHaupt: TfrmHaupt;'#10 +
    'implementation'#10'uses Daten;'#10'procedure TfrmHaupt.FormCreate(Sender: TObject);'#10'begin'#10 + ABody +
    'end;'#10'end.';
end;

procedure TFormFieldRulesTests.FormAccessIssueExample;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.AutoCreateFindings(TFormAccessBeforeCreateRule.Create,
    Haupt('  lblNutzer.Caption := dmDaten.Benutzer;'#10), '', ['frmHaupt', 'dmDaten'], '', '');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('form-access-before-create', Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual('dmDaten wird in der .dpr erst nach frmHaupt erzeugt und ist hier noch nil.', Findings[0].Message);
  Assert.AreEqual(13, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(23, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  // Richtige Reihenfolge in der .dpr: still.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.AutoCreateFindings(TFormAccessBeforeCreateRule.Create,
    Haupt('  lblNutzer.Caption := dmDaten.Benutzer;'#10), '', ['dmDaten', 'frmHaupt'], '', ''))));
end;

procedure TFormFieldRulesTests.FormAccessVariants;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  // Handler aus der Formulardatei, mehrfacher Zugriff nur einmal gemeldet, Konstruktor.
  Source := StringReplace(Haupt('  lblNutzer.Caption := dmDaten.Benutzer + dmDaten.Rolle;'#10),
    'FormCreate', 'Anlegen', [rfReplaceAll]);
  Findings := TRuleAssert.AutoCreateFindings(TFormAccessBeforeCreateRule.Create, Source,
    'object frmHaupt: TfrmHaupt'#10'  OnCreate = Anlegen'#10'  object lblNutzer: TLabel'#10'  end'#10'end'#10,
    ['frmHaupt', 'dmDaten', 'frmLog'], '', '');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Source := StringReplace(StringReplace(Haupt('  inherited Create(AOwner);'#10'  frmLog.Show;'#10),
    'procedure FormCreate(Sender: TObject)', 'constructor Create(AOwner: TComponent); override', []),
    'procedure TfrmHaupt.FormCreate(Sender: TObject)', 'constructor TfrmHaupt.Create(AOwner: TComponent)', []);
  Findings := TRuleAssert.AutoCreateFindings(TFormAccessBeforeCreateRule.Create, Source, '',
    ['frmHaupt', 'dmDaten', 'frmLog'], '', '');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('frmLog wird in der .dpr erst nach frmHaupt erzeugt und ist hier noch nil.', Findings[0].Message);
  // Reihenfolge aus der .dpr.
  Assert.AreEqual('frmHaupt,dmDaten', string.Join(',', TFormAccessBeforeCreateRule.AutoCreatedForms(
    'program P;'#10'uses Vcl.Forms;'#10'begin'#10'  Application.Initialize;'#10 +
    '  Application.CreateForm(TfrmHaupt, frmHaupt);'#10'  // Application.CreateForm(TfrmAlt, frmAlt);'#10 +
    '  Application.CreateForm(TdmDaten, dmDaten);'#10'  Application.Run;'#10'end.')));
  // Programm, dessen uses die Unit nennt.
  Assert.AreEqual('frmB', string.Join(',', TFormAccessBeforeCreateRule.FormsOfProgram([
    'program A;'#10'uses Vcl.Forms, Andere;'#10'begin'#10'  Application.CreateForm(TfrmA, frmA);'#10'end.',
    'program B;'#10'uses Vcl.Forms, Haupt in ''Haupt.pas'' {frmB};'#10'begin'#10 +
    '  Application.CreateForm(TfrmB, frmB);'#10'end.'], 'Haupt')));
  Assert.AreEqual(0, Integer(Length(TFormAccessBeforeCreateRule.FormsOfProgram(['program A;'#10'begin'#10'end.'],
    'Haupt'))));
  Assert.AreEqual('Anlegen', TFormAccessBeforeCreateRule.CreateHandler('object frmHaupt: TfrmHaupt'#10 +
    '  OnCreate = Anlegen'#10'end'#10));
  Assert.AreEqual('', TFormAccessBeforeCreateRule.CreateHandler('object frmHaupt: TfrmHaupt'#10 +
    '  object Timer1: TTimer'#10'    OnCreate = Fremd'#10'  end'#10'end'#10));
end;

procedure TFormFieldRulesTests.FormAccessSilentCases;
begin
  // Geprüft, selbst erzeugt, lokal verdeckt, anderer Methodenname, ohne Projekt.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.AutoCreateFindings(TFormAccessBeforeCreateRule.Create,
    Haupt('  if Assigned(dmDaten) then lblNutzer.Caption := dmDaten.Benutzer;'#10 +
    '  if frmLog <> nil then frmLog.Show;'#10'  Application.CreateForm(TfrmOpt, frmOpt);'#10'  frmOpt.Show;'#10),
    '', ['frmHaupt', 'dmDaten', 'frmLog', 'frmOpt'], '', ''))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.AutoCreateFindings(TFormAccessBeforeCreateRule.Create,
    StringReplace(Haupt('  dmDaten.Oeffnen;'#10), 'FormCreate', 'FormShow', [rfReplaceAll]), '',
    ['frmHaupt', 'dmDaten'], '', ''))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.AutoCreateFindings(TFormAccessBeforeCreateRule.Create,
    StringReplace(Haupt('  dmDaten.Oeffnen;'#10), 'begin'#10'  dmDaten', 'var'#10'  dmDaten: TObject;'#10 +
    'begin'#10'  dmDaten', []), '', ['frmHaupt', 'dmDaten'], '', ''))));
  TRuleAssert.Silent(TFormAccessBeforeCreateRule.Create, Haupt('  dmDaten.Oeffnen;'#10));
  // Formular, das nicht automatisch erzeugt wird.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.AutoCreateFindings(TFormAccessBeforeCreateRule.Create,
    Haupt('  dmDaten.Oeffnen;'#10), '', ['frmStart', 'dmDaten'], '', ''))));
end;

procedure TFormFieldRulesTests.FormAccessOffAndExclude;
var
  Source: string;
begin
  Source := Haupt('  dmDaten.Oeffnen;'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.AutoCreateFindings(TFormAccessBeforeCreateRule.Create, Source, '',
    ['frmHaupt', 'dmDaten'], '{"rules": {"form-access-before-create": "off"}}', ''))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.AutoCreateFindings(TFormAccessBeforeCreateRule.Create, Source, '',
    ['frmHaupt', 'dmDaten'], '{"rules": {"form-access-before-create": {"exclude": ["Source/*.pas"]}}}',
    'Source/Haupt.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TFormFieldRulesTests);

end.
