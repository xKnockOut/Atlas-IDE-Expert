unit BDLsp.Common.Dfm.FormModel.Tests;

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
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Dfm.Contract,
  BDLsp.Common.Dfm.FormModel;

const
  MainForm =
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
  MainUnit =
    'unit Haupt;'#10'interface'#10'type'#10 +
    '  TForm1 = class(TForm)'#10 +
    '    Button1: TButton;'#10 +
    '    Grid: TDBGrid;'#10 +
    '    procedure FormCreate(Sender: TObject);'#10 +
    '    procedure Button1Click(Sender: TObject);'#10 +
    '  end;'#10'implementation'#10 +
    'procedure TForm1.FormCreate(Sender: TObject);'#10'begin'#10'end;'#10 +
    'procedure TForm1.Button1Click(Sender: TObject);'#10'begin'#10'end;'#10'end.';
  ChildForm =
    'inherited Form2: TForm2'#10 +
    '  Caption = ''Kind'''#10 +
    '  inherited Button1: TButton'#10 +
    '    Caption = ''Neu'''#10 +
    '  end'#10 +
    '  object Edit1: TEdit'#10 +
    '  end'#10 +
    'end';
  ChildUnit =
    'unit Kind;'#10'interface'#10'uses Haupt;'#10'type'#10 +
    '  TForm2 = class(TForm1)'#10 +
    '    Edit1: TEdit;'#10 +
    '  end;'#10'implementation'#10'end.';
  DataModule =
    'object DM: TDM'#10 +
    '  object dsKunden: TDataSource'#10 +
    '    DataSet = tblKunden'#10 +
    '  end'#10 +
    '  object tblKunden: TFDTable'#10 +
    '  end'#10 +
    'end';

procedure TFormModelTests.LinksComponentsToFields;
var
  Model: TFormModel;
begin
  Model := TFormModel.Create(MainForm, MainUnit, 'C:\P\Haupt.pas');
  try
    Assert.IsFalse(Model.Binary);
    Assert.AreEqual('TForm1', Model.FormClass);
    Assert.AreEqual('TForm', Model.Ancestor);
    Assert.AreEqual(2, Integer(Length(Model.Components)));
    Assert.AreEqual('Button1', Model.Components[0].Obj.Name);
    Assert.AreEqual('TButton', Model.Components[0].Obj.TypeName);
    Assert.IsTrue(Model.Components[0].HasField);
    Assert.AreEqual(4, Model.Components[0].Field.Range.StartPos.Line);
    Assert.IsTrue(Model.Components[1].HasField);
    Assert.IsTrue(Model.FindComponent('grid') <> nil);
  finally
    Model.Free;
  end;
end;

procedure TFormModelTests.LinksEventsToMethods;
var
  Model: TFormModel;
begin
  Model := TFormModel.Create(MainForm, MainUnit, 'C:\P\Haupt.pas');
  try
    Assert.AreEqual(3, Integer(Length(Model.Events)));
    Assert.AreEqual('FormCreate', Model.Events[0].Event.Value);
    Assert.IsTrue(Model.Events[0].HasMethod);
    // Die Deklaration in der Klasse, nicht der Rumpf.
    Assert.AreEqual(6, Model.Events[0].Method.Range.StartPos.Line);
    Assert.AreEqual('Button1', Model.Events[1].Obj.Name);
    Assert.IsTrue(Model.Events[1].HasMethod);
    Assert.AreEqual('Fehlt', Model.Events[2].Event.Value);
    Assert.IsFalse(Model.Events[2].HasMethod);
  finally
    Model.Free;
  end;
end;

procedure TFormModelTests.InheritedFormKnowsAncestor;
var
  Model: TFormModel;
begin
  Model := TFormModel.Create(ChildForm, ChildUnit, 'C:\P\Kind.pas');
  try
    Assert.AreEqual(Ord(TDfmObjectKind.Inherited_), Ord(Model.Document.Root.Kind));
    Assert.AreEqual('TForm1', Model.Ancestor);
    Assert.AreEqual(2, Integer(Length(Model.Components)));
    Assert.IsTrue(Model.Components[0].IsInherited);
    // Das Feld steht in der Vorfahrenklasse, nicht in TForm2.
    Assert.IsFalse(Model.Components[0].HasField);
    Assert.IsFalse(Model.Components[1].IsInherited);
    Assert.IsTrue(Model.Components[1].HasField);
  finally
    Model.Free;
  end;
end;

procedure TFormModelTests.DataModuleReferencesFromOtherForm;
var
  Model: TFormModel;
begin
  Model := TFormModel.Create(MainForm, MainUnit);
  try
    Assert.AreEqual(1, Integer(Length(Model.References)));
    Assert.AreEqual('DM', Model.References[0].ModuleName);
    Assert.AreEqual('dsKunden', Model.References[0].ComponentName);
    Assert.AreEqual('Grid', Model.References[0].Obj.Name);
    Assert.AreEqual(7, Model.References[0].Reference.ValueRange.StartPos.Line);
  finally
    Model.Free;
  end;
  // Im Datenmodul selbst ist "DataSet = tblKunden" kein Verweis auf ein anderes Modul.
  Model := TFormModel.Create(DataModule);
  try
    Assert.AreEqual('TDM', Model.FormClass);
    Assert.AreEqual(2, Integer(Length(Model.Components)));
    Assert.AreEqual(0, Integer(Length(Model.References)));
  finally
    Model.Free;
  end;
end;

procedure TFormModelTests.BinaryFormIsReported;
var
  Model: TFormModel;
begin
  Model := TFormModel.Create('TPF0'#6'TForm1'#5'Form1'#0#0);
  try
    Assert.IsTrue(Model.Binary);
    // Gelesen über die Umwandlung in Text (#122); Fundstellen für Umbenennen gibt es nicht.
    Assert.AreEqual('TForm1', Model.FormClass);
    Assert.AreEqual(0, Integer(Length(Model.Occurrences('Form1'))));
  finally
    Model.Free;
  end;
end;

procedure TFormModelTests.OccurrencesInTextOrder;
var
  Model: TFormModel;
  Ranges: TArray<TTextRange>;
begin
  Model := TFormModel.Create('object F: TF'#10'  OnShow = Button1'#10'  object Button1: TButton'#10'  end'#10'end');
  try
    Ranges := Model.Occurrences('button1');
    Assert.AreEqual(2, Integer(Length(Ranges)));
    Assert.AreEqual(1, Ranges[0].StartPos.Line);
    Assert.AreEqual(2, Ranges[1].StartPos.Line);
  finally
    Model.Free;
  end;
end;

procedure TFormModelTests.WorksWithoutUnit;
var
  Model: TFormModel;
begin
  Model := TFormModel.Create(MainForm);
  try
    Assert.AreEqual('', Model.Ancestor);
    Assert.IsFalse(Model.Components[0].HasField);
    Assert.IsFalse(Model.Events[0].HasMethod);
  finally
    Model.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TFormModelTests);

end.
