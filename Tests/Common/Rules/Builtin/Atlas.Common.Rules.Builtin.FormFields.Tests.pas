unit Atlas.Common.Rules.Builtin.FormFields.Tests;

// Tests für den Abgleich von Formularfeldern und DFM-Objekten (#123).

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
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
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

initialization
  TDUnitX.RegisterTestFixture(TFormFieldRulesTests);

end.
