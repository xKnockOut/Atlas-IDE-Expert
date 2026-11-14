unit Atlas.Common.Rules.Builtin.DataBinding.Tests;

// Tests für die Datenbindungsregeln (#151).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDataBindingRulesTests = class
  public
    [Test]
    procedure CircularDataSourceReports;
    [Test]
    procedure LinearMasterDetailIsSilent;
    [Test]
    procedure MasterWithoutFieldsReports;
    [Test]
    procedure MasterWithFieldsIsSilent;
    [Test]
    procedure RequiredFieldWithoutControlReports;
    [Test]
    procedure RequiredFieldInGridIsSilent;
    [Test]
    procedure WithoutPersistentFieldsIsSilent;
    [Test]
    procedure EditOnBooleanFieldReports;
    [Test]
    procedure CheckBoxOnBooleanFieldIsSilent;
    [Test]
    procedure DuplicateBindingReports;
    [Test]
    procedure TextBesideEditIsSilent;
    [Test]
    procedure ForeignFormAccessReports;
    [Test]
    procedure OwnFieldsAndNonFormsAreSilent;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Builtin.DataBinding,
  Atlas.Tests.RuleAssert;

const
  cFormUnit =
    'unit Haupt;'#10'interface'#10'type'#10 +
    '  TForm1 = class(TForm)'#10 +
    '  end;'#10'implementation'#10'end.';

function Form(const AObjects: string): string;
begin
  Result := 'object Form1: TForm1'#10 + AObjects + 'end';
end;

function Count(const ARule: IRule; const AFormText: string): Integer;
begin
  Result := Length(TRuleAssert.FormFindings(ARule, cFormUnit, AFormText));
end;

const
  cTables =
    '  object dsA: TDataSource'#10'    DataSet = tblA'#10'  end'#10 +
    '  object dsB: TDataSource'#10'    DataSet = tblB'#10'  end'#10;

procedure TDataBindingRulesTests.CircularDataSourceReports;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.FormFindings(TDfmCircularDataSourceRule.Create, cFormUnit, Form(cTables +
    '  object tblA: TFDQuery'#10'    MasterSource = dsB'#10'    MasterFields = ''ID'''#10'  end'#10 +
    '  object tblB: TFDQuery'#10'    MasterSource = dsA'#10'    MasterFields = ''ID'''#10'  end'#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  // Gemeldet an der Formularklasse in der Unit.
  Assert.AreEqual(3, mFindings[0].Range.StartPos.Line);
end;

procedure TDataBindingRulesTests.LinearMasterDetailIsSilent;
begin
  Assert.AreEqual(0, Count(TDfmCircularDataSourceRule.Create, Form(cTables +
    '  object tblA: TFDQuery'#10'  end'#10 +
    '  object tblB: TFDQuery'#10'    MasterSource = dsA'#10'    MasterFields = ''ID'''#10'  end'#10)));
end;

procedure TDataBindingRulesTests.MasterWithoutFieldsReports;
begin
  Assert.AreEqual(1, Count(TDfmMasterWithoutFieldsRule.Create, Form(cTables +
    '  object tblB: TFDQuery'#10'    MasterSource = dsA'#10'  end'#10)));
end;

procedure TDataBindingRulesTests.MasterWithFieldsIsSilent;
begin
  Assert.AreEqual(0, Count(TDfmMasterWithoutFieldsRule.Create, Form(cTables +
    '  object tblB: TFDQuery'#10'    MasterSource = dsA'#10'    MasterFields = ''ID'''#10'  end'#10)));
end;

const
  cPersistentTable =
    '  object dsA: TDataSource'#10'    DataSet = tblA'#10'  end'#10 +
    '  object tblA: TFDQuery'#10 +
    '    object tblAName: TStringField'#10'      FieldName = ''Name'''#10'      Required = True'#10'    end'#10 +
    '    object tblAAktiv: TBooleanField'#10'      FieldName = ''Aktiv'''#10'    end'#10 +
    '  end'#10;

procedure TDataBindingRulesTests.RequiredFieldWithoutControlReports;
begin
  Assert.AreEqual(1, Count(TDfmRequiredFieldWithoutControlRule.Create, Form(cPersistentTable)));
  // Nur unsichtbar gebunden zählt nicht.
  Assert.AreEqual(1, Count(TDfmRequiredFieldWithoutControlRule.Create, Form(cPersistentTable +
    '  object Panel1: TPanel'#10'    Visible = False'#10 +
    '    object edName: TDBEdit'#10'      DataSource = dsA'#10'      DataField = ''Name'''#10'    end'#10 +
    '  end'#10)));
end;

procedure TDataBindingRulesTests.RequiredFieldInGridIsSilent;
begin
  Assert.AreEqual(0, Count(TDfmRequiredFieldWithoutControlRule.Create, Form(cPersistentTable +
    '  object Grid: TDBGrid'#10'    DataSource = dsA'#10'  end'#10)));
  Assert.AreEqual(0, Count(TDfmRequiredFieldWithoutControlRule.Create, Form(cPersistentTable +
    '  object edName: TDBEdit'#10'    DataSource = dsA'#10'    DataField = ''Name'''#10'  end'#10)));
end;

procedure TDataBindingRulesTests.WithoutPersistentFieldsIsSilent;
begin
  Assert.AreEqual(0, Count(TDfmRequiredFieldWithoutControlRule.Create, Form(cTables +
    '  object tblA: TFDQuery'#10'  end'#10)));
  Assert.AreEqual(0, Count(TDfmControlFieldTypeMismatchRule.Create, Form(cTables +
    '  object tblA: TFDQuery'#10'  end'#10 +
    '  object edX: TDBEdit'#10'    DataSource = dsA'#10'    DataField = ''Aktiv'''#10'  end'#10)));
end;

procedure TDataBindingRulesTests.EditOnBooleanFieldReports;
begin
  Assert.AreEqual(1, Count(TDfmControlFieldTypeMismatchRule.Create, Form(cPersistentTable +
    '  object edAktiv: TDBEdit'#10'    DataSource = dsA'#10'    DataField = ''Aktiv'''#10'  end'#10)));
end;

procedure TDataBindingRulesTests.CheckBoxOnBooleanFieldIsSilent;
begin
  Assert.AreEqual(0, Count(TDfmControlFieldTypeMismatchRule.Create, Form(cPersistentTable +
    '  object cbAktiv: TDBCheckBox'#10'    DataSource = dsA'#10'    DataField = ''Aktiv'''#10'  end'#10 +
    '  object edName: TDBEdit'#10'    DataSource = dsA'#10'    DataField = ''Name'''#10'  end'#10)));
end;

procedure TDataBindingRulesTests.DuplicateBindingReports;
begin
  Assert.AreEqual(1, Count(TDfmDuplicateBindingRule.Create, Form(cPersistentTable +
    '  object ed1: TDBEdit'#10'    DataSource = dsA'#10'    DataField = ''Name'''#10'  end'#10 +
    '  object ed2: TDBEdit'#10'    DataSource = dsA'#10'    DataField = ''Name'''#10'  end'#10)));
end;

procedure TDataBindingRulesTests.TextBesideEditIsSilent;
begin
  Assert.AreEqual(0, Count(TDfmDuplicateBindingRule.Create, Form(cPersistentTable +
    '  object ed1: TDBEdit'#10'    DataSource = dsA'#10'    DataField = ''Name'''#10'  end'#10 +
    '  object lb1: TDBText'#10'    DataSource = dsA'#10'    DataField = ''Name'''#10'  end'#10)));
end;

const
  cOtherFormUnit =
    'unit Zweit;'#10'interface'#10'type'#10 +
    '  TForm2 = class(TForm)'#10'    Edit1: TEdit;'#10'  end;'#10 +
    '  THelfer = class'#10'    Wert: Integer;'#10'  end;'#10 +
    'var'#10'  Form2: TForm2;'#10'  Helfer: THelfer;'#10 +
    'implementation'#10'end.';

function IndexWith(const ASource: string): ISymbolIndex;
var
  mTree: TSyntaxTree;
begin
  Result := TSymbolIndex.Create;
  mTree := TPascalParser.Parse(ASource);
  try
    Result.AddUnit(TIndexExtractor.Extract(mTree, 'C:\P\Zweit.pas'));
  finally
    mTree.Free;
  end;
end;

function RunForeign(const AStatements: string): TArray<TRuleFinding>;
var
  mContext: TRuleContext;
  mTree: TSyntaxTree;
  mSource: string;
begin
  mSource := 'unit Haupt;'#10'interface'#10'implementation'#10'uses Zweit;'#10'procedure Run;'#10'begin'#10 +
    AStatements + #10'end;'#10'end.';
  mTree := TPascalParser.Parse(mSource);
  try
    mContext := Default(TRuleContext);
    mContext.UnitName := 'Haupt';
    mContext.Text := mSource;
    mContext.Tree := mTree;
    mContext.Index := IndexWith(cOtherFormUnit);
    Result := TRuleEngine.Run([TForeignFormControlAccessRule.Create], TServerSettings.Default, mContext);
  finally
    mTree.Free;
  end;
end;

procedure TDataBindingRulesTests.ForeignFormAccessReports;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := RunForeign('  Form2.Edit1.Text := ''x'';');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(6, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(mFindings[0].Confidence));
end;

procedure TDataBindingRulesTests.OwnFieldsAndNonFormsAreSilent;
begin
  // Kein Formular, Methode statt Feld, Methode des Formulars.
  Assert.AreEqual(0, Integer(Length(RunForeign('  Helfer.Wert.ToString;'#10'  Form2.Show;'#10 +
    '  Form2.Caption.Trim;'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TDataBindingRulesTests);

end.
