unit Atlas.Core.Editor.ClassExtraction.Tests;

// Eingabemaske „Mitglieder herauslösen“ (#664, #713) ohne VCL: Laden der
// Antwort von prepare, Häkchen (gesperrte bleiben), Prüfung von Name,
// Auswahl und Ziel-Unit sowie das JSON für den Server.

interface

uses
  DUnitX.TestFramework,
  System.JSON,
  Atlas.Core.Editor.ClassExtraction;

type
  [TestFixture]
  TClassExtractionModelTests = class
  private
    FModel: TAtlasClassExtractionModel;
    function Prepared(const AJson: string): TAtlasClassExtractionModel;
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure LoadsCandidatesNotesAndUnits;
    [Test]
    procedure DisabledStaysUnchecked;
    [Test]
    procedure CheckAllSkipsDisabled;
    [Test]
    procedure RejectsBadAndReservedNames;
    [Test]
    procedure RejectsNameOfClass;
    [Test]
    procedure NeedsOneMember;
    [Test]
    procedure RejectsBadUnitName;
    [Test]
    procedure RequestJsonCarriesCheckedIds;
    [Test]
    procedure EmptyAnswerGivesEmptyModel;
    [Test]
    procedure OwnUnitMeansSameUnit;
  end;

implementation

uses
  System.SysUtils;

const
  Basis = '{"className":"TKunde","ownUnit":"Kunden","name":"IKunde","candidates":[' +
    '{"id":2,"name":"Speichern","kind":"method","display":"procedure Speichern;","visibility":"public",' +
    '"checked":true,"enabled":true,"reason":""},' +
    '{"id":3,"name":"Laden","kind":"method","display":"function Laden: Boolean;","visibility":"public",' +
    '"checked":true,"enabled":true,"reason":""},' +
    '{"id":5,"name":"Create","kind":"method","display":"constructor Create;","visibility":"public",' +
    '"checked":true,"enabled":false,"reason":"Konstruktor"},' +
    '{"id":7,"name":"Name","kind":"property","display":"property Name: string","visibility":"public",' +
    '"checked":false,"enabled":true,"reason":"bekommt GetName und SetName"}],' +
    '"notes":["TKunde erbt jetzt von TInterfacedObject"],"units":["Haupt","Kunden.Daten"]}';

function TClassExtractionModelTests.Prepared(const AJson: string): TAtlasClassExtractionModel;
var
  Value: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    FModel := TAtlasClassExtractionModel.Create(Value as TJSONObject);
  finally
    Value.Free;
  end;
  Result := FModel;
end;

procedure TClassExtractionModelTests.TearDown;
begin
  FreeAndNil(FModel);
end;

procedure TClassExtractionModelTests.LoadsCandidatesNotesAndUnits;
var
  Model: TAtlasClassExtractionModel;
begin
  Model := Prepared(Basis);
  Assert.AreEqual('TKunde', Model.SourceClass);
  Assert.AreEqual('Kunden', Model.OwnUnit);
  Assert.AreEqual('IKunde', Model.Name);
  Assert.AreEqual(4, Integer(Model.Count));
  Assert.AreEqual(3, Model[1].Id);
  Assert.AreEqual('function Laden: Boolean;', Model[1].Display);
  Assert.AreEqual('property', Model[3].Kind);
  Assert.AreEqual('bekommt GetName und SetName', Model[3].Reason);
  Assert.AreEqual(1, Integer(Length(Model.Notes)));
  Assert.AreEqual(2, Integer(Length(Model.Units)));
  Assert.AreEqual('Kunden.Daten', Model.Units[1]);
  Assert.AreEqual('', Model.TargetUnit);
end;

procedure TClassExtractionModelTests.DisabledStaysUnchecked;
var
  Model: TAtlasClassExtractionModel;
begin
  Model := Prepared(Basis);
  // Gesperrt und vom Server angehakt: bleibt trotzdem aus.
  Assert.IsFalse(Model[2].Checked);
  Model.SetChecked(2, True);
  Assert.IsFalse(Model[2].Checked);
  Model.SetChecked(0, False);
  Assert.IsFalse(Model[0].Checked);
  Model.SetChecked(-1, True);
  Model.SetChecked(99, True);
  Assert.AreEqual(1, Model.CheckedCount);
end;

procedure TClassExtractionModelTests.CheckAllSkipsDisabled;
var
  Model: TAtlasClassExtractionModel;
begin
  Model := Prepared(Basis);
  Model.CheckAll(True);
  Assert.AreEqual(3, Model.CheckedCount);
  Assert.IsFalse(Model[2].Checked);
  Model.CheckAll(False);
  Assert.AreEqual(0, Model.CheckedCount);
end;

procedure TClassExtractionModelTests.RejectsBadAndReservedNames;
var
  Model: TAtlasClassExtractionModel;
  Subject: string;
begin
  Model := Prepared(Basis);
  Assert.IsTrue(Model.Validate = TAtlasExtractionProblem.None);
  Model.Name := '1Kunde';
  Assert.IsTrue(Model.Validate(Subject) = TAtlasExtractionProblem.BadName);
  Assert.AreEqual('1Kunde', Subject);
  Model.Name := 'begin';
  Assert.IsTrue(Model.Validate = TAtlasExtractionProblem.BadName);
  Model.Name := '';
  Assert.IsTrue(Model.Validate = TAtlasExtractionProblem.BadName);
  Model.Name := '  IKunde  ';
  Assert.IsTrue(Model.Validate = TAtlasExtractionProblem.None);
end;

procedure TClassExtractionModelTests.RejectsNameOfClass;
begin
  Prepared(Basis).Name := 'tkunde';
  Assert.IsTrue(FModel.Validate = TAtlasExtractionProblem.SameName);
end;

procedure TClassExtractionModelTests.NeedsOneMember;
var
  Subject: string;
begin
  Prepared(Basis).CheckAll(False);
  Assert.IsTrue(FModel.Validate(Subject) = TAtlasExtractionProblem.NoMembers);
  Assert.AreEqual('', Subject);
end;

procedure TClassExtractionModelTests.RejectsBadUnitName;
var
  Subject: string;
begin
  Prepared(Basis).TargetUnit := 'Kunden..Daten';
  Assert.IsTrue(FModel.Validate(Subject) = TAtlasExtractionProblem.BadUnit);
  Assert.AreEqual('Kunden..Daten', Subject);
  FModel.TargetUnit := 'Kunden.Schnittstellen';
  Assert.IsTrue(FModel.Validate = TAtlasExtractionProblem.None);
end;

procedure TClassExtractionModelTests.RequestJsonCarriesCheckedIds;
var
  Request: TJSONObject;
begin
  Prepared(Basis).SetChecked(3, True);
  FModel.Name := ' IKundeDaten ';
  FModel.TargetUnit := 'Kunden.Schnittstellen';
  Request := FModel.RequestJson;
  try
    Assert.AreEqual('{"name":"IKundeDaten","unit":"Kunden.Schnittstellen","members":[2,3,7]}', Request.ToJSON);
  finally
    Request.Free;
  end;
end;

procedure TClassExtractionModelTests.EmptyAnswerGivesEmptyModel;
begin
  FModel := TAtlasClassExtractionModel.Create(nil);
  Assert.AreEqual(0, Integer(FModel.Count));
  Assert.AreEqual('', FModel.Name);
  Assert.IsTrue(FModel.Validate = TAtlasExtractionProblem.BadName);
end;

procedure TClassExtractionModelTests.OwnUnitMeansSameUnit;
var
  Request: TJSONObject;
begin
  Prepared(Basis).TargetUnit := 'kunden';
  Assert.AreEqual('', FModel.Target);
  Request := FModel.RequestJson;
  try
    Assert.AreEqual('', Request.GetValue('unit').Value);
  finally
    Request.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TClassExtractionModelTests);

end.
