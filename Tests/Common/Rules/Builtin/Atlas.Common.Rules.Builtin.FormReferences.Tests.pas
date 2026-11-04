unit Atlas.Common.Rules.Builtin.FormReferences.Tests;

// Tests der Regel dfm-reference-unit-missing: Verweise der Formulardatei auf Module, deren Unit nicht in den uses
// steht (Connection = Form1.Connection ohne Unit1).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFormReferenceRulesTests = class
  public
    [Test]
    procedure IssueExample;
    [Test]
    procedure FixAddsImplementationUses;
    [Test]
    procedure RelatedLocationInFormFile;
    [Test]
    procedure UsedUnitIsSilent;
    [Test]
    procedure OwnAndUnknownModulesAreSilent;
    [Test]
    procedure ModuleFromIndex;
    [Test]
    procedure IndexVariableOfForeignTypeIsSilent;
    [Test]
    procedure ProjectModulesReadsDpr;
    [Test]
    procedure OffAndGroup;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Rules.Builtin.FormReferences,
  Atlas.Tests.RuleAssert;

const
  cProjektDpr =
    'program Projekt;'#10 +
    'uses'#10 +
    '  Vcl.Forms,'#10 +
    '  Unit1 in ''Unit1.pas'' {Form1},'#10 +
    '  Unit2 in ''Unit2.pas'' {Form2},'#10 +
    '  Daten.Modul in ''Daten\Daten.Modul.pas'' {DM: TDataModule};'#10 +
    'begin'#10 +
    'end.';
  cUnit2Dfm =
    'object Form2: TForm2'#10 +
    '  Caption = ''Form2'''#10 +
    '  object Query: TFDQuery'#10 +
    '    Connection = Form1.Connection'#10 +
    '  end'#10 +
    'end'#10;

/// <summary>Unit2 mit dem Formular TForm2 und dem Feld Query; AUses steht im interface hinter Vcl.Forms,
/// AImplementation direkt nach implementation.</summary>
function Unit2(const AUses, AImplementation: string): string;
begin
  Result :=
    'unit Unit2;'#10 +
    'interface'#10 +
    'uses Vcl.Forms' + AUses + ';'#10 +
    'type'#10 +
    '  TForm2 = class(TForm)'#10 +
    '    Query: TFDQuery;'#10 +
    '  end;'#10 +
    'var'#10 +
    '  Form2: TForm2;'#10 +
    'implementation'#10 +
    AImplementation +
    '{$R *.dfm}'#10 +
    'end.';
end;

/// <summary>Kontext wie im Server: Unit2.pas mit Formulardatei AFormText; mit AMainSource gehört sie zum
/// Projekt C:\P\Projekt.dpr, das ReadFile liefert.</summary>
function FormContext(const ASource, AFormText, AMainSource: string): TRuleContext;
begin
  Result := Default(TRuleContext);
  Result.RelativePath := 'Source/Unit2.pas';
  Result.UnitName := 'Unit2';
  Result.Text := ASource;
  Result.FormText := AFormText;
  Result.FormFile := 'C:\P\Unit2.dfm';
  if AMainSource = '' then
  begin
    Exit;
  end;
  Result.ProjectMainSource := 'C:\P\Projekt.dpr';
  Result.ReadFile :=
    function(const AName: string; out AData: TBytes): Boolean
    begin
      Result := SameText(AName, 'C:\P\Projekt.dpr');
      if Result then
      begin
        AData := TEncoding.UTF8.GetBytes(AMainSource);
      end;
    end;
end;

function Findings(const AContext: TRuleContext): TArray<TRuleFinding>;
begin
  Result := TRuleAssert.ContextFindings(TDfmReferenceUnitMissingRule.Create, AContext, '');
end;

/// <summary>Index mit Unit1: TForm1 und die globale Variable Form1 im interface.</summary>
function Unit1Index: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText('unit Unit1;'#10'interface'#10'uses Vcl.Forms;'#10'type'#10 +
    '  TForm1 = class(TForm)'#10'  end;'#10'var'#10'  Form1: TForm1;'#10'implementation'#10'end.',
    'C:\P\Unit1.pas', nil));
end;

procedure TFormReferenceRulesTests.IssueExample;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := Findings(FormContext(Unit2('', ''), cUnit2Dfm, cProjektDpr));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(cDfmReferenceUnitMissingRuleId, mFindings[0].RuleId);
  Assert.IsTrue(mFindings[0].Message.StartsWith('Connection = Form1.Connection: Form1 stammt aus Unit1, ' +
    'die Unit steht nicht in den uses.'), mFindings[0].Message);
  Assert.IsTrue(mFindings[0].Severity = TRuleSeverity.Warning);
  Assert.IsTrue(mFindings[0].Confidence = TRuleConfidence.High);
  // Am Feld der Komponente, die den Verweis hält.
  Assert.AreEqual(5, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(4, mFindings[0].Range.StartPos.Character);
end;

procedure TFormReferenceRulesTests.FixAddsImplementationUses;
var
  mFindings: TArray<TRuleFinding>;
  mSource: string;
begin
  mSource := Unit2('', '');
  mFindings := Findings(FormContext(mSource, cUnit2Dfm, cProjektDpr));
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('uses Unit1 ergänzen', mFindings[0].Fixes[0].Title);
  Assert.AreEqual(Unit2('', #10'uses'#10'  Unit1;'#10), TTextChanges.Apply(mSource, mFindings[0].Fixes[0].Edits));
  // Vorhandenes implementation-uses wird ergänzt.
  mSource := Unit2('', 'uses System.SysUtils;'#10);
  mFindings := Findings(FormContext(mSource, cUnit2Dfm, cProjektDpr));
  Assert.AreEqual(Unit2('', 'uses System.SysUtils, Unit1;'#10), TTextChanges.Apply(mSource,
    mFindings[0].Fixes[0].Edits));
end;

procedure TFormReferenceRulesTests.RelatedLocationInFormFile;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := Findings(FormContext(Unit2('', ''), cUnit2Dfm, cProjektDpr));
  Assert.AreEqual(1, Integer(Length(mFindings[0].Related)));
  Assert.AreEqual('C:\P\Unit2.dfm', mFindings[0].Related[0].FileName);
  Assert.AreEqual(3, mFindings[0].Related[0].Range.StartPos.Line);
  Assert.AreEqual('Verweis auf Form1.Connection', mFindings[0].Related[0].Message);
  Assert.AreNotEqual('', mFindings[0].Details);
end;

procedure TFormReferenceRulesTests.UsedUnitIsSilent;
var
  mContext: TRuleContext;
begin
  Assert.AreEqual(0, Integer(Length(Findings(FormContext(Unit2(', Unit1', ''), cUnit2Dfm, cProjektDpr)))));
  Assert.AreEqual(0, Integer(Length(Findings(FormContext(Unit2('', 'uses Unit1;'#10), cUnit2Dfm,
    cProjektDpr)))));
  // Unit mit Namensraum aus der .dpr, im uses ohne: Der Namensraum des Projekts ergänzt ihn.
  mContext := FormContext(Unit2(', Modul', ''), StringReplace(cUnit2Dfm, 'Form1.', 'DM.', []), cProjektDpr);
  mContext.Namespaces := ['Daten'];
  Assert.AreEqual(0, Integer(Length(Findings(mContext))));
  mContext.Namespaces := nil;
  Assert.AreEqual(1, Integer(Length(Findings(mContext))));
end;

procedure TFormReferenceRulesTests.OwnAndUnknownModulesAreSilent;
const
  cOwnDfm =
    'object Form2: TForm2'#10 +
    '  ActiveControl = Form2.Edit1'#10 +
    '  inline Frame11: TFrame1'#10 +
    '    object DataSource1: TDataSource'#10 +
    '    end'#10 +
    '  end'#10 +
    '  object Query: TFDQuery'#10 +
    '    Connection = DM9.Connection'#10 +
    '    DataSource = Frame11.DataSource1'#10 +
    '  end'#10 +
    'end'#10;
begin
  Assert.AreEqual(0, Integer(Length(Findings(FormContext(Unit2('', ''), cOwnDfm, cProjektDpr)))));
  // Ohne .dpr und ohne Index ist Form1 unbekannt.
  Assert.AreEqual(0, Integer(Length(Findings(FormContext(Unit2('', ''), cUnit2Dfm, '')))));
  // Ohne Formulardatei schweigt die Regel.
  Assert.AreEqual(0, Integer(Length(Findings(FormContext(Unit2('', ''), '', cProjektDpr)))));
end;

procedure TFormReferenceRulesTests.ModuleFromIndex;
var
  mContext: TRuleContext;
  mFindings: TArray<TRuleFinding>;
begin
  mContext := FormContext(Unit2('', ''), cUnit2Dfm, '');
  mContext.Index := Unit1Index;
  mFindings := Findings(mContext);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.IsTrue(mFindings[0].Confidence = TRuleConfidence.Medium);
  Assert.AreEqual('uses Unit1 ergänzen', mFindings[0].Fixes[0].Title);
  mContext.Text := Unit2(', Unit1', '');
  Assert.AreEqual(0, Integer(Length(Findings(mContext))));
end;

procedure TFormReferenceRulesTests.IndexVariableOfForeignTypeIsSilent;
var
  mIndex: ISymbolIndex;
  mContext: TRuleContext;
begin
  // Form1 ist hier eine Variable, deren Typ eine andere Unit deklariert: kein Formular von Unit1.
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit Unit1;'#10'interface'#10'uses Basis;'#10'var'#10 +
    '  Form1: TBasisForm;'#10'implementation'#10'end.', 'C:\P\Unit1.pas', nil));
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit Basis;'#10'interface'#10'type'#10 +
    '  TBasisForm = class'#10'  end;'#10'implementation'#10'end.', 'C:\P\Basis.pas', nil));
  mContext := FormContext(Unit2('', ''), cUnit2Dfm, '');
  mContext.Index := mIndex;
  Assert.AreEqual(0, Integer(Length(Findings(mContext))));
end;

procedure TFormReferenceRulesTests.ProjectModulesReadsDpr;
var
  mModules: TArray<TFormModuleUnit>;
begin
  mModules := TDfmReferenceUnitMissingRule.ProjectModules(cProjektDpr);
  Assert.AreEqual(3, Integer(Length(mModules)));
  Assert.AreEqual('Form1', mModules[0].ModuleName);
  Assert.AreEqual('Unit1', mModules[0].UnitName);
  Assert.AreEqual('Form2', mModules[1].ModuleName);
  Assert.AreEqual('DM', mModules[2].ModuleName);
  Assert.AreEqual('Daten.Modul', mModules[2].UnitName);
  // Einträge ohne Kommentar sind keine Module.
  Assert.AreEqual(0, Integer(Length(TDfmReferenceUnitMissingRule.ProjectModules(
    'program P;'#10'uses Werkzeug in ''Werkzeug.pas'';'#10'begin'#10'end.'))));
end;

procedure TFormReferenceRulesTests.OffAndGroup;
var
  mContext: TRuleContext;
begin
  mContext := FormContext(Unit2('', ''), cUnit2Dfm, cProjektDpr);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TDfmReferenceUnitMissingRule.Create, mContext,
    '{"rules": {"dfm-reference-unit-missing": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TDfmReferenceUnitMissingRule.Create, mContext,
    '{"rules": {"dfm-reference-unit-missing": {"exclude": ["Source/*.pas"]}}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.ContextFindings(TDfmReferenceUnitMissingRule.Create, mContext,
    '{"rules": {"group:forms": "off"}}'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TFormReferenceRulesTests);

end.
