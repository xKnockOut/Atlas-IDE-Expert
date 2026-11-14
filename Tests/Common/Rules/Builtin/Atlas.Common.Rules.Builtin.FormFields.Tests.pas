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
  mIndex: Integer;
  mEdit: TRuleEdit;

  function OffsetOf(const APosition: TTextPosition): Integer;
  var
    mLine, mPosition: Integer;
  begin
    mPosition := 0;
    for mLine := 1 to APosition.Line do
    begin
      mPosition := Pos(#10, AText, mPosition + 1);
    end;
    Result := mPosition + APosition.Character;
  end;

begin
  Result := AText;
  for mIndex := High(AFix.Edits) downto 0 do
  begin
    mEdit := AFix.Edits[mIndex];
    Result := Copy(Result, 1, OffsetOf(mEdit.Range.StartPos)) + mEdit.NewText +
      Copy(Result, OffsetOf(mEdit.Range.EndPos) + 1, MaxInt);
  end;
end;

procedure TFormFieldRulesTests.DeletedObjectWithFieldReports;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.FormFindings(TFormFieldWithoutObjectRule.Create,
    FormUnit('    Edit1: TEdit;'#10'    Button1: TButton;'),
    'object Form1: TForm1'#10'  object Button1: TButton'#10'  end'#10'end'#10);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(4, mFindings[0].Range.StartPos.Line);
  Assert.IsTrue(Pos('Edit1', mFindings[0].Message) > 0, mFindings[0].Message);
end;

procedure TFormFieldRulesTests.NonPublishedFieldIsSilent;
begin
  // FZahl steht unter private.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.FormFindings(TFormFieldWithoutObjectRule.Create,
    FormUnit('    Button1: TButton;'), 'object Form1: TForm1'#10'  object Button1: TButton'#10'  end'#10'end'#10))));
end;

procedure TFormFieldRulesTests.ObjectWithoutFieldAddsField;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := FormUnit('    Button1: TButton;');
  mFindings := TRuleAssert.FormFindings(TFormObjectWithoutFieldRule.Create, mSource,
    'object Form1: TForm1'#10'  object Button1: TButton'#10'  end'#10'  object Edit1: TEdit'#10'  end'#10'end'#10);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(FormUnit('    Button1: TButton;'#10'    Edit1: TEdit;'), ApplyFix(mSource, mFindings[0].Fixes[0]));
end;

procedure TFormFieldRulesTests.TypeMismatchFixesType;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := FormUnit('    Edit1: TEdit;');
  mFindings := TRuleAssert.FormFindings(TFormFieldTypeMismatchRule.Create, mSource,
    'object Form1: TForm1'#10'  object Edit1: TMaskEdit'#10'  end'#10'end'#10);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(FormUnit('    Edit1: TMaskEdit;'), ApplyFix(mSource, mFindings[0].Fixes[0]));
end;

procedure TFormFieldRulesTests.InheritedFormIsSilent;
const
  cForm = 'inherited Form1: TForm1'#10'  inherited Ok: TButton'#10'    Caption = ''Los'''#10'  end'#10'end'#10;
begin
  // Ok ist ein Feld des Vorfahren.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.FormFindings(TFormObjectWithoutFieldRule.Create,
    FormUnit(''), cForm))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.FormFindings(TFormFieldWithoutObjectRule.Create,
    FormUnit(''), cForm))));
end;

procedure TFormFieldRulesTests.FrameObjectsAreSilent;
const
  cForm = 'object Form1: TForm1'#10'  inline Rahmen1: TRahmen'#10'    inherited Liste: TListBox'#10'    end'#10 +
    '    object Extra: TLabel'#10'    end'#10'  end'#10'end'#10;
begin
  // Liste und Extra gehören zur Frame-Klasse; nur Rahmen1 braucht ein Feld.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.FormFindings(TFormObjectWithoutFieldRule.Create,
    FormUnit('    Rahmen1: TRahmen;'), cForm))));
end;

procedure TFormFieldRulesTests.UnnamedMenuItemIsSilent;
const
  cForm = 'object Form1: TForm1'#10'  object Menu: TMainMenu'#10'    object TMenuItem'#10'    end'#10'  end'#10'end'#10;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.FormFindings(TFormObjectWithoutFieldRule.Create,
    FormUnit('    Menu: TMainMenu;'), cForm))));
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
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.AutoCreateFindings(TFormAccessBeforeCreateRule.Create,
    Haupt('  lblNutzer.Caption := dmDaten.Benutzer;'#10), '', ['frmHaupt', 'dmDaten'], '', '');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('form-access-before-create', mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(mFindings[0].Confidence));
  Assert.AreEqual('dmDaten wird in der .dpr erst nach frmHaupt erzeugt und ist hier noch nil.', mFindings[0].Message);
  Assert.AreEqual(13, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(23, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
  // Richtige Reihenfolge in der .dpr: still.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.AutoCreateFindings(TFormAccessBeforeCreateRule.Create,
    Haupt('  lblNutzer.Caption := dmDaten.Benutzer;'#10), '', ['dmDaten', 'frmHaupt'], '', ''))));
end;

procedure TFormFieldRulesTests.FormAccessVariants;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
begin
  // Handler aus der Formulardatei, mehrfacher Zugriff nur einmal gemeldet, Konstruktor.
  mSource := StringReplace(Haupt('  lblNutzer.Caption := dmDaten.Benutzer + dmDaten.Rolle;'#10),
    'FormCreate', 'Anlegen', [rfReplaceAll]);
  mFindings := TRuleAssert.AutoCreateFindings(TFormAccessBeforeCreateRule.Create, mSource,
    'object frmHaupt: TfrmHaupt'#10'  OnCreate = Anlegen'#10'  object lblNutzer: TLabel'#10'  end'#10'end'#10,
    ['frmHaupt', 'dmDaten', 'frmLog'], '', '');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  mSource := StringReplace(StringReplace(Haupt('  inherited Create(AOwner);'#10'  frmLog.Show;'#10),
    'procedure FormCreate(Sender: TObject)', 'constructor Create(AOwner: TComponent); override', []),
    'procedure TfrmHaupt.FormCreate(Sender: TObject)', 'constructor TfrmHaupt.Create(AOwner: TComponent)', []);
  mFindings := TRuleAssert.AutoCreateFindings(TFormAccessBeforeCreateRule.Create, mSource, '',
    ['frmHaupt', 'dmDaten', 'frmLog'], '', '');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('frmLog wird in der .dpr erst nach frmHaupt erzeugt und ist hier noch nil.', mFindings[0].Message);
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
  mSource: string;
begin
  mSource := Haupt('  dmDaten.Oeffnen;'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.AutoCreateFindings(TFormAccessBeforeCreateRule.Create, mSource, '',
    ['frmHaupt', 'dmDaten'], '{"rules": {"form-access-before-create": "off"}}', ''))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.AutoCreateFindings(TFormAccessBeforeCreateRule.Create, mSource, '',
    ['frmHaupt', 'dmDaten'], '{"rules": {"form-access-before-create": {"exclude": ["Source/*.pas"]}}}',
    'Source/Haupt.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TFormFieldRulesTests);

end.
