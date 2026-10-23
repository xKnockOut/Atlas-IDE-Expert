unit Atlas.Core.Editor.ClassExtraction.Tests;

// Eingabemaske „Mitglieder herauslösen“ (#664, #713) ohne VCL: Laden der
// Antwort von prepare, Häkchen (gesperrte bleiben), Prüfung von Name,
// Auswahl und Ziel-Unit sowie das JSON für den Server; für die Basisklasse
// abstrakte Methoden, Abhängigkeiten und das vorgewählte Ziel.

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
    [Test]
    procedure LoadsSuperclassModesAndTarget;
    [Test]
    procedure AbstractOnlyWhereAllowed;
    [Test]
    procedure ReportsMissingDependency;
    [Test]
    procedure AbstractMethodNeedsNothing;
    [Test]
    procedure TakesDependenciesTransitively;
    [Test]
    procedure RequestJsonCarriesAbstractIds;
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

  // Basisklasse (#713): Run benutzt Helper, Helper benutzt FItems; Show darf abstrakt werden, Done nicht.
  Super = '{"className":"TPdfExport","ownUnit":"Export","name":"TExportBase","unit":"ExportBase","candidates":[' +
    '{"id":1,"name":"FItems","kind":"field","display":"FItems: TStrings;","visibility":"private",' +
    '"enabled":true,"canAbstract":false,"abstract":false,"needs":[]},' +
    '{"id":2,"name":"Helper","kind":"method","display":"procedure Helper;","visibility":"private",' +
    '"enabled":true,"canAbstract":true,"abstract":false,"needs":[1]},' +
    '{"id":3,"name":"Run","kind":"method","display":"procedure Run;","visibility":"public",' +
    '"enabled":true,"canAbstract":true,"abstract":true,"needs":[2]},' +
    '{"id":4,"name":"Done","kind":"method","display":"class procedure Done;","visibility":"public",' +
    '"enabled":true,"canAbstract":false,"abstract":true,"reason":"Klassenmethode","needs":[]}],' +
    '"notes":[],"units":["ExportBase"]}';

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

procedure TClassExtractionModelTests.LoadsSuperclassModesAndTarget;
var
  Model: TAtlasClassExtractionModel;
begin
  Model := Prepared(Super);
  Assert.AreEqual('ExportBase', Model.TargetUnit);
  Assert.AreEqual('ExportBase', Model.Target);
  Assert.AreEqual('field', Model[0].Kind);
  Assert.IsTrue(Model.HasModes);
  Assert.IsTrue(Model.HasNeeds);
  Assert.IsTrue(Model[2].Abstract);
  // Der Server darf abstract nur setzen, wo canAbstract gilt.
  Assert.IsFalse(Model[3].Abstract);
  Assert.AreEqual(1, Integer(Length(Model[2].Needs)));
  Assert.AreEqual(2, Model[2].Needs[0]);
end;

procedure TClassExtractionModelTests.AbstractOnlyWhereAllowed;
var
  Model: TAtlasClassExtractionModel;
begin
  Model := Prepared(Super);
  Model.SetAbstract(3, True);
  Assert.IsFalse(Model[3].Abstract);
  Model.SetAbstract(1, True);
  Assert.IsTrue(Model[1].Abstract);
  Model.SetAbstract(2, False);
  Assert.IsFalse(Model[2].Abstract);
  Model.SetAbstract(-1, True);
  Model.SetAbstract(99, True);
end;

procedure TClassExtractionModelTests.ReportsMissingDependency;
var
  Model: TAtlasClassExtractionModel;
  Subject, Member, Needed: string;
begin
  Model := Prepared(Super);
  Model.SetChecked(1, True);
  Assert.AreEqual(Ord(TAtlasExtractionProblem.MissingDependency), Ord(Model.Validate(Subject)));
  Assert.AreEqual('Helper', Subject);
  Assert.IsTrue(Model.MissingDependency(Member, Needed));
  Assert.AreEqual('Helper', Member);
  Assert.AreEqual('FItems', Needed);
  Model.SetChecked(0, True);
  Assert.AreEqual(Ord(TAtlasExtractionProblem.None), Ord(Model.Validate));
  Assert.IsFalse(Model.MissingDependency(Member, Needed));
  Assert.AreEqual('', Member);
end;

procedure TClassExtractionModelTests.AbstractMethodNeedsNothing;
var
  Model: TAtlasClassExtractionModel;
begin
  Model := Prepared(Super);
  // Run wandert nur abstrakt: Helper muss nicht mit.
  Model.SetChecked(2, True);
  Assert.AreEqual(Ord(TAtlasExtractionProblem.None), Ord(Model.Validate));
  Model.SetAbstract(2, False);
  Assert.AreEqual(Ord(TAtlasExtractionProblem.MissingDependency), Ord(Model.Validate));
end;

procedure TClassExtractionModelTests.TakesDependenciesTransitively;
var
  Model: TAtlasClassExtractionModel;
begin
  Model := Prepared(Super);
  Model.SetChecked(2, True);
  Model.SetAbstract(2, False);
  Assert.AreEqual(2, Model.TakeDependencies);
  Assert.IsTrue(Model[1].Checked);
  Assert.IsTrue(Model[0].Checked);
  Assert.AreEqual(Ord(TAtlasExtractionProblem.None), Ord(Model.Validate));
  Assert.AreEqual(0, Model.TakeDependencies);
end;

procedure TClassExtractionModelTests.RequestJsonCarriesAbstractIds;
var
  Model: TAtlasClassExtractionModel;
  Request: TJSONObject;
begin
  Model := Prepared(Super);
  Request := Model.RequestJson;
  try
    // Nichts angehakt: kein abstract.
    Assert.IsNull(Request.GetValue('abstract'));
  finally
    Request.Free;
  end;
  Model.SetChecked(2, True);
  Model.SetChecked(3, True);
  Request := Model.RequestJson;
  try
    Assert.AreEqual('{"name":"TExportBase","unit":"ExportBase","members":[3,4],"abstract":[3]}', Request.ToJSON);
  finally
    Request.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TClassExtractionModelTests);

end.
