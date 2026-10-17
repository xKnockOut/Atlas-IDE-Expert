unit Atlas.Core.Editor.ChangeSignature.Tests;

// Eingabemaske „Signatur ändern“ (#100) ohne VCL: Laden der Antwort des
// Servers, Hinzufügen, Entfernen, Verschieben, Umbenennen, Prüfung, Vorschau
// und das JSON für atlas.server.changeSignature.

interface

uses
  DUnitX.TestFramework,
  System.JSON,
  Atlas.Core.Editor.ChangeSignature;

type
  [TestFixture]
  TSignatureModelTests = class
  private
    FModel: TAtlasSignatureModel;
    function Prepared(const AJson: string): TAtlasSignatureModel;
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure LoadsParametersAndSettings;
    [Test]
    procedure UnchangedIsNotChanged;
    [Test]
    procedure AddInsertsAfterSelection;
    [Test]
    procedure AddedParameterNeedsTypeAndValue;
    [Test]
    procedure RejectsReservedAndDuplicateNames;
    [Test]
    procedure RejectsNewParameterAfterDefault;
    [Test]
    procedure MoveRowSwapsAndStopsAtEdge;
    [Test]
    procedure RenameKeepsTypeOfExisting;
    [Test]
    procedure ChangeOnlyForNewParameters;
    [Test]
    procedure PreviewShowsNewSignature;
    [Test]
    procedure InterfaceMethodForcesUpdateCallers;
    [Test]
    procedure FixedEventAllowsOnlyRename;
    [Test]
    procedure RequestJsonCarriesOriginsAndMode;
  end;

implementation

uses
  System.SysUtils;

const
  Basis = '{"name":"Lauf","container":"TBasis","kind":"function","resultType":"Boolean",' +
    '"parameters":[{"name":"A","type":"Integer","modifier":"","default":""},' +
    '{"name":"S","type":"string","modifier":"const","default":"''x''"}],' +
    '"members":3,"interfaceMethod":false,"boundEvent":"","eventFixed":false,"overloadPossible":true,' +
    '"newParameter":"overload","virtualOverload":false,"warnings":["Methodenzeiger in Haupt.pas"]}';
  Event = '{"name":"Button1Click","container":"TForm1","kind":"procedure","resultType":"",' +
    '"parameters":[{"name":"Sender","type":"TObject","modifier":"","default":""}],"members":1,' +
    '"interfaceMethod":false,"boundEvent":"TNotifyEvent","eventFixed":true,"overloadPossible":false,' +
    '"newParameter":"overload","virtualOverload":false,"warnings":[]}';

function TSignatureModelTests.Prepared(const AJson: string): TAtlasSignatureModel;
var
  Value: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    FModel := TAtlasSignatureModel.Create(Value as TJSONObject);
  finally
    Value.Free;
  end;
  Result := FModel;
end;

procedure TSignatureModelTests.TearDown;
begin
  FreeAndNil(FModel);
end;

procedure TSignatureModelTests.LoadsParametersAndSettings;
var
  Model: TAtlasSignatureModel;
begin
  Model := Prepared(Basis);
  Assert.AreEqual(2, Model.Count);
  Assert.AreEqual('S', Model[1].Name);
  Assert.AreEqual('const', Model[1].Modifier);
  Assert.AreEqual('''x''', Model[1].DefaultValue);
  Assert.AreEqual(1, Model[1].Origin);
  Assert.IsTrue(Model.UseOverload);
  Assert.IsTrue(Model.OverloadPossible);
  Assert.AreEqual(3, Model.Members);
  Assert.AreEqual(1, Integer(Length(Model.Warnings)));
end;

procedure TSignatureModelTests.UnchangedIsNotChanged;
begin
  Assert.IsFalse(Prepared(Basis).Changed);
  Assert.IsTrue(FModel.Validate = TAtlasSignatureProblem.None);
end;

procedure TSignatureModelTests.AddInsertsAfterSelection;
var
  Model: TAtlasSignatureModel;
begin
  Model := Prepared(Basis);
  Assert.AreEqual(1, Model.Add(0, 'B', 'Integer', '', '0'));
  Assert.AreEqual(3, Model.Count);
  Assert.AreEqual('B', Model[1].Name);
  Assert.IsTrue(Model[1].IsNew);
  Assert.AreEqual(0, Model.Add(-1, 'C', 'Integer', '', '1'));
  Assert.AreEqual('C', Model[0].Name);
  Assert.IsTrue(Model.Changed);
  Assert.IsTrue(Model.AddsParameters);
end;

procedure TSignatureModelTests.AddedParameterNeedsTypeAndValue;
var
  Model: TAtlasSignatureModel;
  Subject: string;
begin
  Model := Prepared(Basis);
  Model.Add(0, 'B', '', '', '0');
  Assert.IsTrue(Model.Validate(Subject) = TAtlasSignatureProblem.MissingType);
  Assert.AreEqual('B', Subject);
  Model.Change(1, 'Integer', '', '');
  Assert.IsTrue(Model.Validate = TAtlasSignatureProblem.MissingValue);
  Model.Change(1, 'Integer', '', '42');
  Assert.IsTrue(Model.Validate = TAtlasSignatureProblem.None);
end;

procedure TSignatureModelTests.RejectsReservedAndDuplicateNames;
var
  Model: TAtlasSignatureModel;
  Subject: string;
begin
  Model := Prepared(Basis);
  Model.Rename(0, 'begin');
  Assert.IsTrue(Model.Validate(Subject) = TAtlasSignatureProblem.BadName);
  Assert.AreEqual('begin', Subject);
  Model.Rename(0, '1A');
  Assert.IsTrue(Model.Validate = TAtlasSignatureProblem.BadName);
  Model.Rename(0, 's');
  Assert.IsTrue(Model.Validate = TAtlasSignatureProblem.Duplicate);
  Model.Rename(0, 'Anzahl');
  Assert.IsTrue(Model.Validate = TAtlasSignatureProblem.None);
end;

procedure TSignatureModelTests.RejectsNewParameterAfterDefault;
var
  Model: TAtlasSignatureModel;
begin
  // Hinter einem Standardwert darf kein Parameter ohne stehen; Atlas erzeugt selbst keinen.
  Model := Prepared(Basis);
  Model.Add(1, 'B', 'Integer', '', '0');
  Assert.IsTrue(Model.Validate = TAtlasSignatureProblem.AfterDefault);
  Assert.IsTrue(Model.MoveRow(2, -1));
  Assert.IsTrue(Model.Validate = TAtlasSignatureProblem.None);
end;

procedure TSignatureModelTests.MoveRowSwapsAndStopsAtEdge;
var
  Model: TAtlasSignatureModel;
begin
  Model := Prepared(Basis);
  Assert.IsFalse(Model.MoveRow(0, -1));
  Assert.IsFalse(Model.MoveRow(1, 1));
  Assert.IsTrue(Model.MoveRow(0, 1));
  Assert.AreEqual('S', Model[0].Name);
  Assert.AreEqual(1, Model[0].Origin);
  Assert.IsTrue(Model.Changed);
end;

procedure TSignatureModelTests.RenameKeepsTypeOfExisting;
var
  Model: TAtlasSignatureModel;
begin
  Model := Prepared(Basis);
  Model.Rename(0, ' Anzahl ');
  Assert.AreEqual('Anzahl', Model[0].Name);
  Assert.AreEqual('Integer', Model[0].TypeName);
  Assert.IsTrue(Model.Changed);
end;

procedure TSignatureModelTests.ChangeOnlyForNewParameters;
var
  Model: TAtlasSignatureModel;
begin
  Model := Prepared(Basis);
  Model.Change(0, 'Int64', 'var', '1');
  Assert.AreEqual('Integer', Model[0].TypeName);
  Assert.AreEqual('', Model[0].Modifier);
  Model.Add(0, 'B', 'Integer', '', '0');
  Model.Change(1, 'Int64', 'CONST', '7');
  Assert.AreEqual('Int64', Model[1].TypeName);
  Assert.AreEqual('const', Model[1].Modifier);
  Assert.AreEqual('7', Model[1].Value);
end;

procedure TSignatureModelTests.PreviewShowsNewSignature;
var
  Model: TAtlasSignatureModel;
begin
  Model := Prepared(Basis);
  Model.Add(0, 'B', 'Int64', 'const', '0');
  Assert.AreEqual('function TBasis.Lauf(A: Integer; const B: Int64; const S: string = ''x''): Boolean',
    Model.Preview);
  Model.Remove(0);
  Model.Remove(0);
  Model.Remove(0);
  Assert.AreEqual('function TBasis.Lauf: Boolean', Model.Preview);
end;

procedure TSignatureModelTests.InterfaceMethodForcesUpdateCallers;
var
  Model: TAtlasSignatureModel;
  Request: TJSONObject;
begin
  Model := Prepared(StringReplace(Basis, '"overloadPossible":true', '"overloadPossible":false', []));
  Assert.IsFalse(Model.OverloadPossible);
  Assert.IsFalse(Model.UseOverload);
  Model.UseOverload := True;
  Request := Model.RequestJson;
  try
    Assert.AreEqual('updateCallers', Request.GetValue<string>('newParameter'));
  finally
    Request.Free;
  end;
end;

procedure TSignatureModelTests.FixedEventAllowsOnlyRename;
var
  Model: TAtlasSignatureModel;
  Subject: string;
begin
  Model := Prepared(Event);
  Assert.IsTrue(Model.EventFixed);
  Assert.AreEqual('TNotifyEvent', Model.BoundEvent);
  Model.Rename(0, 'AOrigin');
  Assert.IsTrue(Model.Validate = TAtlasSignatureProblem.None);
  Model.Add(0, 'B', 'Integer', '', '0');
  Assert.IsTrue(Model.Validate(Subject) = TAtlasSignatureProblem.TypesFixed);
  Assert.AreEqual('TNotifyEvent', Subject);
end;

procedure TSignatureModelTests.RequestJsonCarriesOriginsAndMode;
var
  Model: TAtlasSignatureModel;
  Request: TJSONObject;
  Items: TJSONArray;
begin
  Model := Prepared(Basis);
  Model.MoveRow(0, 1);
  Model.Add(1, 'B', 'Integer', 'var', 'Wert');
  Model.VirtualOverload := True;
  Request := Model.RequestJson;
  try
    Items := Request.GetValue('parameters') as TJSONArray;
    Assert.AreEqual(3, Integer(Items.Count));
    Assert.AreEqual(1, (Items.Items[0] as TJSONObject).GetValue<Integer>('origin'));
    Assert.AreEqual('-1', (Items.Items[2] as TJSONObject).GetValue('origin').ToJSON);
    Assert.AreEqual('var', (Items.Items[2] as TJSONObject).GetValue<string>('modifier'));
    Assert.AreEqual('Wert', (Items.Items[2] as TJSONObject).GetValue<string>('value'));
    Assert.IsNull((Items.Items[0] as TJSONObject).GetValue('type'));
    Assert.AreEqual('overload', Request.GetValue<string>('newParameter'));
    Assert.IsTrue(Request.GetValue<Boolean>('virtualOverload'));
  finally
    Request.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSignatureModelTests);

end.
