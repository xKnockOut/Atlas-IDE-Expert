unit Atlas.Common.Dfm.FormModel.Tests;

// Tests für das Formularmodell (#267): Formular, geerbtes Formular, Datenmodul.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFormModelTests = class
  public
    [Test]
    procedure LinksComponentsToFields;
    [Test]
    procedure LinksEventsToMethods;
    [Test]
    procedure InheritedFormKnowsAncestor;
    [Test]
    procedure DataModuleReferencesFromOtherForm;
    [Test]
    procedure BinaryFormIsReported;
    [Test]
    procedure OccurrencesInTextOrder;
    [Test]
    procedure WorksWithoutUnit;
    [Test]
    procedure ForeignModulesSkipOwnNames;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.FormModel;

const
  cMainForm =
    'object Form1: TForm1'#10 +                    // 0
    '  Caption = ''Haupt'''#10 +                    // 1
    '  OnCreate = FormCreate'#10 +                  // 2
    '  object Button1: TButton'#10 +                // 3
    '    OnClick = Button1Click'#10 +               // 4
    '  end'#10 +                                    // 5
    '  object Grid: TDBGrid'#10 +                   // 6
    '    DataSource = DM.dsKunden'#10 +             // 7
    '    OnDblClick = Fehlt'#10 +                   // 8
    '  end'#10 +                                    // 9
    'end';
  cMainUnit =
    'unit Haupt;'#10'interface'#10'type'#10 +
    '  TForm1 = class(TForm)'#10 +
    '    Button1: TButton;'#10 +
    '    Grid: TDBGrid;'#10 +
    '    procedure FormCreate(Sender: TObject);'#10 +
    '    procedure Button1Click(Sender: TObject);'#10 +
    '  end;'#10'implementation'#10 +
    'procedure TForm1.FormCreate(Sender: TObject);'#10'begin'#10'end;'#10 +
    'procedure TForm1.Button1Click(Sender: TObject);'#10'begin'#10'end;'#10'end.';
  cChildForm =
    'inherited Form2: TForm2'#10 +
    '  Caption = ''Kind'''#10 +
    '  inherited Button1: TButton'#10 +
    '    Caption = ''Neu'''#10 +
    '  end'#10 +
    '  object Edit1: TEdit'#10 +
    '  end'#10 +
    'end';
  cChildUnit =
    'unit Kind;'#10'interface'#10'uses Haupt;'#10'type'#10 +
    '  TForm2 = class(TForm1)'#10 +
    '    Edit1: TEdit;'#10 +
    '  end;'#10'implementation'#10'end.';
  cDataModule =
    'object DM: TDM'#10 +
    '  object dsKunden: TDataSource'#10 +
    '    DataSet = tblKunden'#10 +
    '  end'#10 +
    '  object tblKunden: TFDTable'#10 +
    '  end'#10 +
    'end';

procedure TFormModelTests.LinksComponentsToFields;
var
  mModel: TFormModel;
begin
  mModel := TFormModel.Create(cMainForm, cMainUnit, 'C:\P\Haupt.pas');
  try
    Assert.IsFalse(mModel.Binary);
    Assert.AreEqual('TForm1', mModel.FormClass);
    Assert.AreEqual('TForm', mModel.Ancestor);
    Assert.AreEqual(2, Integer(Length(mModel.Components)));
    Assert.AreEqual('Button1', mModel.Components[0].Obj.Name);
    Assert.AreEqual('TButton', mModel.Components[0].Obj.TypeName);
    Assert.IsTrue(mModel.Components[0].HasField);
    Assert.AreEqual(4, mModel.Components[0].Field.Range.StartPos.Line);
    Assert.IsTrue(mModel.Components[1].HasField);
    Assert.IsNotNull(mModel.FindComponent('grid'));
  finally
    mModel.Free;
  end;
end;

procedure TFormModelTests.LinksEventsToMethods;
var
  mModel: TFormModel;
begin
  mModel := TFormModel.Create(cMainForm, cMainUnit, 'C:\P\Haupt.pas');
  try
    Assert.AreEqual(3, Integer(Length(mModel.Events)));
    Assert.AreEqual('FormCreate', mModel.Events[0].Event.Value);
    Assert.IsTrue(mModel.Events[0].HasMethod);
    // Die Deklaration in der Klasse, nicht der Rumpf.
    Assert.AreEqual(6, mModel.Events[0].Method.Range.StartPos.Line);
    Assert.AreEqual('Button1', mModel.Events[1].Obj.Name);
    Assert.IsTrue(mModel.Events[1].HasMethod);
    Assert.AreEqual('Fehlt', mModel.Events[2].Event.Value);
    Assert.IsFalse(mModel.Events[2].HasMethod);
  finally
    mModel.Free;
  end;
end;

procedure TFormModelTests.InheritedFormKnowsAncestor;
var
  mModel: TFormModel;
begin
  mModel := TFormModel.Create(cChildForm, cChildUnit, 'C:\P\Kind.pas');
  try
    Assert.AreEqual(Ord(TDfmObjectKind.Inherited_), Ord(mModel.Document.Root.Kind));
    Assert.AreEqual('TForm1', mModel.Ancestor);
    Assert.AreEqual(2, Integer(Length(mModel.Components)));
    Assert.IsTrue(mModel.Components[0].IsInherited);
    // Das Feld steht in der Vorfahrenklasse, nicht in TForm2.
    Assert.IsFalse(mModel.Components[0].HasField);
    Assert.IsFalse(mModel.Components[1].IsInherited);
    Assert.IsTrue(mModel.Components[1].HasField);
  finally
    mModel.Free;
  end;
end;

procedure TFormModelTests.DataModuleReferencesFromOtherForm;
var
  mModel: TFormModel;
begin
  mModel := TFormModel.Create(cMainForm, cMainUnit);
  try
    Assert.AreEqual(1, Integer(Length(mModel.References)));
    Assert.AreEqual('DM', mModel.References[0].ModuleName);
    Assert.AreEqual('dsKunden', mModel.References[0].ComponentName);
    Assert.AreEqual('Grid', mModel.References[0].Obj.Name);
    Assert.AreEqual(7, mModel.References[0].Reference.ValueRange.StartPos.Line);
  finally
    mModel.Free;
  end;
  // Im Datenmodul selbst ist "DataSet = tblKunden" kein Verweis auf ein anderes Modul.
  mModel := TFormModel.Create(cDataModule);
  try
    Assert.AreEqual('TDM', mModel.FormClass);
    Assert.AreEqual(2, Integer(Length(mModel.Components)));
    Assert.AreEqual(0, Integer(Length(mModel.References)));
  finally
    mModel.Free;
  end;
end;

procedure TFormModelTests.ForeignModulesSkipOwnNames;
const
  cForm =
    'object Form2: TForm2'#10 +
    '  ActiveControl = Form2.Edit1'#10 +
    '  inline Frame11: TFrame1'#10 +
    '  end'#10 +
    '  object Grid: TDBGrid'#10 +
    '    DataSource = Frame11.DataSource1'#10 +
    '  end'#10 +
    '  object Query: TFDQuery'#10 +
    '    Connection = Form1.Connection'#10 +
    '    UpdateObject = Form1.Update1'#10 +
    '    DataSource = DM.dsKunden'#10 +
    '  end'#10 +
    'end'#10;
var
  mModel: TFormModel;
begin
  mModel := TFormModel.Create(cForm);
  try
    Assert.IsTrue(mModel.IsOwnName('form2'));
    Assert.IsTrue(mModel.IsOwnName('Frame11'));
    Assert.IsFalse(mModel.IsOwnName('Form1'));
    Assert.AreEqual('Form1,DM', string.Join(',', mModel.ForeignModules));
  finally
    mModel.Free;
  end;
  Assert.AreEqual('Form1,DM', string.Join(',', TFormModel.ForeignModulesOf(cForm)));
  Assert.AreEqual(0, Integer(Length(TFormModel.ForeignModulesOf(''))));
end;

procedure TFormModelTests.BinaryFormIsReported;
var
  mModel: TFormModel;
begin
  mModel := TFormModel.Create('TPF0'#6'TForm1'#5'Form1'#0#0);
  try
    Assert.IsTrue(mModel.Binary);
    // Gelesen über die Umwandlung in Text (#122); Fundstellen für Umbenennen gibt es nicht.
    Assert.AreEqual('TForm1', mModel.FormClass);
    Assert.AreEqual(0, Integer(Length(mModel.Occurrences('Form1'))));
  finally
    mModel.Free;
  end;
end;

procedure TFormModelTests.OccurrencesInTextOrder;
var
  mModel: TFormModel;
  mRanges: TArray<TTextRange>;
begin
  mModel := TFormModel.Create('object F: TF'#10'  OnShow = Button1'#10'  object Button1: TButton'#10'  end'#10'end');
  try
    mRanges := mModel.Occurrences('button1');
    Assert.AreEqual(2, Integer(Length(mRanges)));
    Assert.AreEqual(1, mRanges[0].StartPos.Line);
    Assert.AreEqual(2, mRanges[1].StartPos.Line);
  finally
    mModel.Free;
  end;
end;

procedure TFormModelTests.WorksWithoutUnit;
var
  mModel: TFormModel;
begin
  mModel := TFormModel.Create(cMainForm);
  try
    Assert.AreEqual('', mModel.Ancestor);
    Assert.IsFalse(mModel.Components[0].HasField);
    Assert.IsFalse(mModel.Events[0].HasMethod);
  finally
    mModel.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TFormModelTests);

end.
