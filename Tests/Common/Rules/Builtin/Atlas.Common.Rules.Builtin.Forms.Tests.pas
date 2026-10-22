unit Atlas.Common.Rules.Builtin.Forms.Tests;

// Tests der Formularregeln aus Builtin.Forms: form-resource-missing (#1054).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFormRulesTests = class
  public
    [Test]
    procedure ResourceMissingIssueExample;
    [Test]
    procedure ResourceMissingFixInsertsDirective;
    [Test]
    procedure ResourceIncludedIsSilent;
    [Test]
    procedure ResourceWithoutFormFileIsReported;
    [Test]
    procedure ResourceOtherClassOrNoFormIsSilent;
    [Test]
    procedure ResourceFmxAndExplicitName;
    [Test]
    procedure ResourceOffAndExclude;
    [Test]
    procedure FormResourceParsesDirectives;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Builtin.Forms,
  Atlas.Tests.RuleAssert;

const
  KundeForm =
    'object frmKunde: TfrmKunde'#10 +
    '  Caption = ''Kunde'''#10 +
    '  OnShow = FormShow'#10 +
    'end'#10;

function KundeUnit(const AImplementation: string): string;
begin
  Result :=
    'unit Kunde;'#10 +
    'interface'#10 +
    'uses Vcl.Forms;'#10 +
    'type'#10 +
    '  TfrmKunde = class(TForm)'#10 +
    '    procedure FormShow(Sender: TObject);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    AImplementation +
    #10 +
    'procedure TfrmKunde.FormShow(Sender: TObject);'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';
end;

/// <summary>Kontext wie im Server: Unit Kunde.pas, Formulardatei AFormFile mit AFormText, Dateien AFiles
/// neben der Unit.</summary>
function FormContext(const ASource, AFormText, AFormFile: string; const AFiles: TArray<string>): TRuleContext;
begin
  Result := Default(TRuleContext);
  Result.RelativePath := 'Source/Kunde.pas';
  Result.UnitName := 'Kunde';
  Result.Text := ASource;
  Result.FormText := AFormText;
  Result.FormFile := AFormFile;
  Result.ReadFile :=
    function(const AName: string; out AData: TBytes): Boolean
    var
      Name: string;
    begin
      AData := nil;
      for Name in AFiles do
        if SameText(Name, AName) then
          Exit(True);
      Result := False;
    end;
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

{ TFormRulesTests }

procedure TFormRulesTests.ResourceMissingIssueExample;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(''), KundeForm, 'C:\P\Kunde.dfm', ['Kunde.dfm']), '');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('form-resource-missing', Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('Kunde.dfm wird nicht eingebunden; TfrmKunde.Create löst EResNotFound aus.', Findings[0].Message);
  Assert.AreEqual(7, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(0, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(14, Findings[0].Range.EndPos.Character);
end;

procedure TFormRulesTests.ResourceMissingFixInsertsDirective;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
  Tree: TSyntaxTree;
begin
  Source := KundeUnit('');
  Findings := TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(Source, KundeForm, 'C:\P\Kunde.dfm', ['Kunde.dfm']), '');
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('{$R *.dfm} nach implementation einfügen', Findings[0].Fixes[0].Title);
  Assert.IsTrue(Findings[0].Fixes[0].Safe);
  Fixed := ApplyFix(Source, Findings[0].Fixes[0]);
  Assert.AreEqual(KundeUnit(#10'{$R *.dfm}'#10), Fixed);
  Tree := TPascalParser.Parse(Fixed);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)));
  finally
    Tree.Free;
  end;
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(Fixed, KundeForm, 'C:\P\Kunde.dfm', ['Kunde.dfm']), ''))));
end;

procedure TFormRulesTests.ResourceIncludedIsSilent;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(#10'{$R *.DFM}'#10), KundeForm, 'C:\P\Kunde.dfm', ['Kunde.dfm']), ''))));
  // Eingebunden nur in einem Zweig der bedingten Übersetzung zählt ebenfalls.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(#10'{$IFDEF MSWINDOWS}'#10'{$R *.dfm}'#10'{$ENDIF}'#10), KundeForm, 'C:\P\Kunde.dfm',
    ['Kunde.dfm']), ''))));
  // Eingebunden vor der uses-Klausel des Implementation-Teils.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(#10'{$R *.dfm}'#10#10'uses System.SysUtils;'#10), KundeForm, 'C:\P\Kunde.dfm',
    ['Kunde.dfm']), ''))));
end;

procedure TFormRulesTests.ResourceWithoutFormFileIsReported;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(#10'{$R *.dfm}'#10), '', '', []), '');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Kunde.dfm fehlt; der Compiler bricht mit F1026 ab.', Findings[0].Message);
  Assert.AreEqual(9, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  // Ohne Dateizugriff (Linter ohne Pfad) keine Aussage.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.FormFindings(TFormResourceMissingRule.Create,
    KundeUnit(#10'{$R *.dfm}'#10), ''))));
end;

procedure TFormRulesTests.ResourceOtherClassOrNoFormIsSilent;
begin
  // Wurzelklasse der Formulardatei steht nicht in der Unit.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(''), StringReplace(KundeForm, 'TfrmKunde', 'TfrmAnders', []), 'C:\P\Kunde.dfm',
    ['Kunde.dfm']), ''))));
  // Unit ohne Formulardatei und ohne {$R}.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(''), '', '', []), ''))));
  // Andere Ressourcen ({$R *.res}) zählen nicht.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(#10'{$R *.res}'#10), '', '', []), ''))));
end;

procedure TFormRulesTests.ResourceFmxAndExplicitName;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(''), KundeForm, 'C:\P\Kunde.fmx', ['Kunde.fmx']), '');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Kunde.fmx wird nicht eingebunden; TfrmKunde.Create löst EResNotFound aus.', Findings[0].Message);
  Assert.AreEqual('{$R *.fmx} nach implementation einfügen', Findings[0].Fixes[0].Title);
  // Falscher Name: die eingebundene Datei fehlt.
  Findings := TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(#10'{$R Kunden.dfm}'#10), '', '', ['Kunde.dfm']), '');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Kunden.dfm fehlt; der Compiler bricht mit F1026 ab.', Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create,
    FormContext(KundeUnit(#10'{$R ''Kunden.dfm''}'#10), '', '', ['Kunden.dfm']), ''))));
end;

procedure TFormRulesTests.ResourceOffAndExclude;
var
  Context: TRuleContext;
begin
  Context := FormContext(KundeUnit(''), KundeForm, 'C:\P\Kunde.dfm', ['Kunde.dfm']);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create, Context,
    '{"rules": {"form-resource-missing": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create, Context,
    '{"rules": {"form-resource-missing": {"exclude": ["Source/*.pas"]}}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TFormResourceMissingRule.Create, Context,
    '{"rules": {"group:forms": "off"}}'))));
end;

procedure TFormRulesTests.FormResourceParsesDirectives;
var
  FileName: string;
begin
  Assert.IsTrue(TFormResourceMissingRule.FormResource('{$R *.dfm}', 'Kunde', FileName));
  Assert.AreEqual('Kunde.dfm', FileName);
  Assert.IsTrue(TFormResourceMissingRule.FormResource('{$R *.Windows.fmx MSWINDOWS}', 'Kunde', FileName));
  Assert.AreEqual('Kunde.Windows.fmx', FileName);
  Assert.IsTrue(TFormResourceMissingRule.FormResource('{$RESOURCE ''Form\Kunde.dfm''}', 'Kunde', FileName));
  Assert.AreEqual('Form\Kunde.dfm', FileName);
  Assert.IsFalse(TFormResourceMissingRule.FormResource('{$R *.res}', 'Kunde', FileName));
  Assert.IsFalse(TFormResourceMissingRule.FormResource('{$R+}', 'Kunde', FileName));
  Assert.IsFalse(TFormResourceMissingRule.FormResource('{$R *.dfm}', '', FileName));
end;

initialization
  TDUnitX.RegisterTestFixture(TFormRulesTests);

end.
