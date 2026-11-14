unit Atlas.Core.Editor.ChangeSignature.Tests;

// Eingabemaske „Signatur ändern“ (#100) ohne VCL: Laden der Antwort des
// Servers, Hinzufügen, Entfernen, Verschieben, Umbenennen, Prüfung, Vorschau
// und das JSON für atlas.server.changeSignature.

interface

uses
  DUnitX.TestFramework,
  System.JSON,
  System.Generics.Collections,
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
  cBasis = '{"name":"Lauf","container":"TBasis","kind":"function","resultType":"Boolean",' +
    '"parameters":[{"name":"A","type":"Integer","modifier":"","default":""},' +
    '{"name":"S","type":"string","modifier":"const","default":"''x''"}],' +
    '"members":3,"interfaceMethod":false,"boundEvent":"","eventFixed":false,"overloadPossible":true,' +
    '"newParameter":"overload","virtualOverload":false,"warnings":["Methodenzeiger in Haupt.pas"]}';
  cEvent = '{"name":"Button1Click","container":"TForm1","kind":"procedure","resultType":"",' +
    '"parameters":[{"name":"Sender","type":"TObject","modifier":"","default":""}],"members":1,' +
    '"interfaceMethod":false,"boundEvent":"TNotifyEvent","eventFixed":true,"overloadPossible":false,' +
    '"newParameter":"overload","virtualOverload":false,"warnings":[]}';

function TSignatureModelTests.Prepared(const AJson: string): TAtlasSignatureModel;
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    FModel := TAtlasSignatureModel.Create(mValue as TJSONObject);
  finally
    mValue.Free;
  end;
  Result := FModel;
end;

procedure TSignatureModelTests.TearDown;
begin
  FreeAndNil(FModel);
end;

procedure TSignatureModelTests.LoadsParametersAndSettings;
var
  mModel: TAtlasSignatureModel;
begin
  mModel := Prepared(cBasis);
  Assert.AreEqual(2, Integer(mModel.Count));
  Assert.AreEqual('S', mModel[1].Name);
  Assert.AreEqual('const', mModel[1].Modifier);
  Assert.AreEqual('''x''', mModel[1].DefaultValue);
  Assert.AreEqual(1, mModel[1].Origin);
  Assert.IsTrue(mModel.UseOverload);
  Assert.IsTrue(mModel.OverloadPossible);
  Assert.AreEqual(3, mModel.Members);
  Assert.AreEqual(1, Integer(Length(mModel.Warnings)));
end;

procedure TSignatureModelTests.UnchangedIsNotChanged;
begin
  Assert.IsFalse(Prepared(cBasis).Changed);
  Assert.AreEqual<TAtlasSignatureProblem>(TAtlasSignatureProblem.None, FModel.Validate);
end;

procedure TSignatureModelTests.AddInsertsAfterSelection;
var
  mModel: TAtlasSignatureModel;
begin
  mModel := Prepared(cBasis);
  Assert.AreEqual(1, mModel.Add(0, 'B', 'Integer', '', '0'));
  Assert.AreEqual(3, Integer(mModel.Count));
  Assert.AreEqual('B', mModel[1].Name);
  Assert.IsTrue(mModel[1].IsNew);
  Assert.AreEqual(0, mModel.Add(-1, 'C', 'Integer', '', '1'));
  Assert.AreEqual('C', mModel[0].Name);
  Assert.IsTrue(mModel.Changed);
  Assert.IsTrue(mModel.AddsParameters);
end;

procedure TSignatureModelTests.AddedParameterNeedsTypeAndValue;
var
  mModel: TAtlasSignatureModel;
  mSubject: string;
begin
  mModel := Prepared(cBasis);
  mModel.Add(0, 'B', '', '', '0');
  Assert.AreEqual<TAtlasSignatureProblem>(TAtlasSignatureProblem.MissingType, mModel.Validate(mSubject));
  Assert.AreEqual('B', mSubject);
  mModel.Change(1, 'Integer', '', '');
  Assert.AreEqual<TAtlasSignatureProblem>(TAtlasSignatureProblem.MissingValue, mModel.Validate);
  mModel.Change(1, 'Integer', '', '42');
  Assert.AreEqual<TAtlasSignatureProblem>(TAtlasSignatureProblem.None, mModel.Validate);
end;

procedure TSignatureModelTests.RejectsReservedAndDuplicateNames;
var
  mModel: TAtlasSignatureModel;
  mSubject: string;
begin
  mModel := Prepared(cBasis);
  mModel.Rename(0, 'begin');
  Assert.AreEqual<TAtlasSignatureProblem>(TAtlasSignatureProblem.BadName, mModel.Validate(mSubject));
  Assert.AreEqual('begin', mSubject);
  mModel.Rename(0, '1A');
  Assert.AreEqual<TAtlasSignatureProblem>(TAtlasSignatureProblem.BadName, mModel.Validate);
  mModel.Rename(0, 's');
  Assert.AreEqual<TAtlasSignatureProblem>(TAtlasSignatureProblem.Duplicate, mModel.Validate);
  mModel.Rename(0, 'Anzahl');
  Assert.AreEqual<TAtlasSignatureProblem>(TAtlasSignatureProblem.None, mModel.Validate);
end;

procedure TSignatureModelTests.RejectsNewParameterAfterDefault;
var
  mModel: TAtlasSignatureModel;
begin
  // Hinter einem Standardwert darf kein Parameter ohne stehen; Atlas erzeugt selbst keinen.
  mModel := Prepared(cBasis);
  mModel.Add(1, 'B', 'Integer', '', '0');
  Assert.AreEqual<TAtlasSignatureProblem>(TAtlasSignatureProblem.AfterDefault, mModel.Validate);
  Assert.IsTrue(mModel.MoveRow(2, -1));
  Assert.AreEqual<TAtlasSignatureProblem>(TAtlasSignatureProblem.None, mModel.Validate);
end;

procedure TSignatureModelTests.MoveRowSwapsAndStopsAtEdge;
var
  mModel: TAtlasSignatureModel;
begin
  mModel := Prepared(cBasis);
  Assert.IsFalse(mModel.MoveRow(0, -1));
  Assert.IsFalse(mModel.MoveRow(1, 1));
  Assert.IsTrue(mModel.MoveRow(0, 1));
  Assert.AreEqual('S', mModel[0].Name);
  Assert.AreEqual(1, mModel[0].Origin);
  Assert.IsTrue(mModel.Changed);
end;

procedure TSignatureModelTests.RenameKeepsTypeOfExisting;
var
  mModel: TAtlasSignatureModel;
begin
  mModel := Prepared(cBasis);
  mModel.Rename(0, ' Anzahl ');
  Assert.AreEqual('Anzahl', mModel[0].Name);
  Assert.AreEqual('Integer', mModel[0].TypeName);
  Assert.IsTrue(mModel.Changed);
end;

procedure TSignatureModelTests.ChangeOnlyForNewParameters;
var
  mModel: TAtlasSignatureModel;
begin
  mModel := Prepared(cBasis);
  mModel.Change(0, 'Int64', 'var', '1');
  Assert.AreEqual('Integer', mModel[0].TypeName);
  Assert.AreEqual('', mModel[0].Modifier);
  mModel.Add(0, 'B', 'Integer', '', '0');
  mModel.Change(1, 'Int64', 'CONST', '7');
  Assert.AreEqual('Int64', mModel[1].TypeName);
  Assert.AreEqual('const', mModel[1].Modifier);
  Assert.AreEqual('7', mModel[1].Value);
end;

procedure TSignatureModelTests.PreviewShowsNewSignature;
var
  mModel: TAtlasSignatureModel;
begin
  mModel := Prepared(cBasis);
  mModel.Add(0, 'B', 'Int64', 'const', '0');
  Assert.AreEqual('function TBasis.Lauf(A: Integer; const B: Int64; const S: string = ''x''): Boolean',
    mModel.Preview);
  mModel.Remove(0);
  mModel.Remove(0);
  mModel.Remove(0);
  Assert.AreEqual('function TBasis.Lauf: Boolean', mModel.Preview);
end;

procedure TSignatureModelTests.InterfaceMethodForcesUpdateCallers;
var
  mModel: TAtlasSignatureModel;
  mRequest: TJSONObject;
begin
  mModel := Prepared(StringReplace(cBasis, '"overloadPossible":true', '"overloadPossible":false', []));
  Assert.IsFalse(mModel.OverloadPossible);
  Assert.IsFalse(mModel.UseOverload);
  mModel.UseOverload := True;
  mRequest := mModel.RequestJson;
  try
    Assert.AreEqual('updateCallers', mRequest.GetValue<string>('newParameter'));
  finally
    mRequest.Free;
  end;
end;

procedure TSignatureModelTests.FixedEventAllowsOnlyRename;
var
  mModel: TAtlasSignatureModel;
  mSubject: string;
begin
  mModel := Prepared(cEvent);
  Assert.IsTrue(mModel.EventFixed);
  Assert.AreEqual('TNotifyEvent', mModel.BoundEvent);
  mModel.Rename(0, 'AOrigin');
  Assert.AreEqual<TAtlasSignatureProblem>(TAtlasSignatureProblem.None, mModel.Validate);
  mModel.Add(0, 'B', 'Integer', '', '0');
  Assert.AreEqual<TAtlasSignatureProblem>(TAtlasSignatureProblem.TypesFixed, mModel.Validate(mSubject));
  Assert.AreEqual('TNotifyEvent', mSubject);
end;

procedure TSignatureModelTests.RequestJsonCarriesOriginsAndMode;
var
  mModel: TAtlasSignatureModel;
  mRequest: TJSONObject;
  mItems: TJSONArray;
begin
  mModel := Prepared(cBasis);
  mModel.MoveRow(0, 1);
  mModel.Add(1, 'B', 'Integer', 'var', 'Wert');
  mModel.VirtualOverload := True;
  mRequest := mModel.RequestJson;
  try
    mItems := mRequest.GetValue('parameters') as TJSONArray;
    Assert.AreEqual(3, Integer(mItems.Count));
    Assert.AreEqual(1, (mItems.Items[0] as TJSONObject).GetValue<Integer>('origin'));
    Assert.AreEqual('-1', (mItems.Items[2] as TJSONObject).GetValue('origin').ToJSON);
    Assert.AreEqual('var', (mItems.Items[2] as TJSONObject).GetValue<string>('modifier'));
    Assert.AreEqual('Wert', (mItems.Items[2] as TJSONObject).GetValue<string>('value'));
    Assert.IsNull((mItems.Items[0] as TJSONObject).GetValue('type'));
    Assert.AreEqual('overload', mRequest.GetValue<string>('newParameter'));
    Assert.IsTrue(mRequest.GetValue<Boolean>('virtualOverload'));
  finally
    mRequest.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSignatureModelTests);

end.
