unit Atlas.Core.Editor.ClassExtraction.Tests;

// Eingabemaske „Mitglieder herauslösen“ (#664, #713) ohne VCL: Laden der
// Antwort von prepare, Häkchen (gesperrte bleiben), Prüfung von Name,
// Auswahl und Ziel-Unit sowie das JSON für den Server; für die Basisklasse
// abstrakte Methoden, Abhängigkeiten und das vorgewählte Ziel; für „Mitglied
// verschieben“ Ziele, Wahl und freiwillige Abhängigkeiten.

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
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
    [Test]
    procedure MoveUpPicksOneTarget;
    [Test]
    procedure MoveDownTakesSeveralTargets;
  end;

implementation

uses
  System.SysUtils;

const
  cBasis = '{"className":"TKunde","ownUnit":"Kunden","name":"IKunde","candidates":[' +
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
  cSuper = '{"className":"TPdfExport","ownUnit":"Export","name":"TExportBase","unit":"ExportBase","candidates":[' +
    '{"id":1,"name":"FItems","kind":"field","display":"FItems: TStrings;","visibility":"private",' +
    '"enabled":true,"canAbstract":false,"abstract":false,"needs":[]},' +
    '{"id":2,"name":"Helper","kind":"method","display":"procedure Helper;","visibility":"private",' +
    '"enabled":true,"canAbstract":true,"abstract":false,"needs":[1]},' +
    '{"id":3,"name":"Run","kind":"method","display":"procedure Run;","visibility":"public",' +
    '"enabled":true,"canAbstract":true,"abstract":true,"needs":[2]},' +
    '{"id":4,"name":"Done","kind":"method","display":"class procedure Done;","visibility":"public",' +
    '"enabled":true,"canAbstract":false,"abstract":true,"reason":"Klassenmethode","needs":[]}],' +
    '"notes":[],"units":["ExportBase"]}';

  // Mitglied verschieben (#675): nach oben ein Ziel, nach unten mehrere.
  cMoveUp = '{"className":"TChild","ownUnit":"Kind","member":"Fill","direction":"up","name":"","candidates":[' +
    '{"id":0,"name":"FItems","kind":"field","display":"FItems: TStrings;","visibility":"private",' +
    '"checked":false,"enabled":true,"canAbstract":false,"needs":[]},' +
    '{"id":2,"name":"Fill","kind":"method","display":"procedure Fill;","visibility":"public",' +
    '"checked":true,"enabled":true,"canAbstract":true,"needs":[0]}],' +
    '"targets":[{"name":"TBase","unit":"Basis","checked":true},{"name":"TRoot","unit":"Root","checked":false}],' +
    '"multiTarget":false,"needsRequired":true,"option":{"kind":"overrideSiblings","value":true},"notes":[]}';
  cMoveDown = '{"className":"TBase","ownUnit":"Basis","member":"Show","direction":"down","name":"","candidates":[' +
    '{"id":0,"name":"FData","kind":"field","display":"FData: string;","visibility":"private",' +
    '"checked":false,"enabled":true,"needs":[]},' +
    '{"id":1,"name":"Show","kind":"method","display":"procedure Show;","visibility":"public",' +
    '"checked":true,"enabled":true,"needs":[0]}],' +
    '"targets":[{"name":"TChild","unit":"Kind","checked":true},{"name":"TOther","unit":"Kind","checked":true}],' +
    '"multiTarget":true,"needsRequired":false,"option":{"kind":"keepAbstract","value":false},"notes":[]}';

function TClassExtractionModelTests.Prepared(const AJson: string): TAtlasClassExtractionModel;
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    FModel := TAtlasClassExtractionModel.Create(mValue as TJSONObject);
  finally
    mValue.Free;
  end;
  Result := FModel;
end;

procedure TClassExtractionModelTests.TearDown;
begin
  FreeAndNil(FModel);
end;

procedure TClassExtractionModelTests.LoadsCandidatesNotesAndUnits;
var
  mModel: TAtlasClassExtractionModel;
begin
  mModel := Prepared(cBasis);
  Assert.AreEqual('TKunde', mModel.Source.SourceClass);
  Assert.AreEqual('Kunden', mModel.Source.OwnUnit);
  Assert.AreEqual('IKunde', mModel.Name);
  Assert.AreEqual(4, Integer(mModel.Count));
  Assert.AreEqual(3, mModel[1].Id);
  Assert.AreEqual('function Laden: Boolean;', mModel[1].Display);
  Assert.AreEqual('property', mModel[3].Kind);
  Assert.AreEqual('bekommt GetName und SetName', mModel[3].Reason);
  Assert.AreEqual(1, Integer(Length(mModel.Source.Notes)));
  Assert.AreEqual(2, Integer(Length(mModel.Source.Units)));
  Assert.AreEqual('Kunden.Daten', mModel.Source.Units[1]);
  Assert.AreEqual('', mModel.TargetUnit);
end;

procedure TClassExtractionModelTests.DisabledStaysUnchecked;
var
  mModel: TAtlasClassExtractionModel;
begin
  mModel := Prepared(cBasis);
  // Gesperrt und vom Server angehakt: bleibt trotzdem aus.
  Assert.IsFalse(mModel[2].Checked);
  mModel.SetChecked(2, True);
  Assert.IsFalse(mModel[2].Checked);
  mModel.SetChecked(0, False);
  Assert.IsFalse(mModel[0].Checked);
  mModel.SetChecked(-1, True);
  mModel.SetChecked(99, True);
  Assert.AreEqual(1, mModel.CheckedCount);
end;

procedure TClassExtractionModelTests.CheckAllSkipsDisabled;
var
  mModel: TAtlasClassExtractionModel;
begin
  mModel := Prepared(cBasis);
  mModel.CheckAll(True);
  Assert.AreEqual(3, mModel.CheckedCount);
  Assert.IsFalse(mModel[2].Checked);
  mModel.CheckAll(False);
  Assert.AreEqual(0, mModel.CheckedCount);
end;

procedure TClassExtractionModelTests.RejectsBadAndReservedNames;
var
  mModel: TAtlasClassExtractionModel;
  mSubject: string;
begin
  mModel := Prepared(cBasis);
  Assert.AreEqual<TAtlasExtractionProblem>(TAtlasExtractionProblem.None, mModel.Validate);
  mModel.Name := '1Kunde';
  Assert.AreEqual<TAtlasExtractionProblem>(TAtlasExtractionProblem.BadName, mModel.Validate(mSubject));
  Assert.AreEqual('1Kunde', mSubject);
  mModel.Name := 'begin';
  Assert.AreEqual<TAtlasExtractionProblem>(TAtlasExtractionProblem.BadName, mModel.Validate);
  mModel.Name := '';
  Assert.AreEqual<TAtlasExtractionProblem>(TAtlasExtractionProblem.BadName, mModel.Validate);
  mModel.Name := '  IKunde  ';
  Assert.AreEqual<TAtlasExtractionProblem>(TAtlasExtractionProblem.None, mModel.Validate);
end;

procedure TClassExtractionModelTests.RejectsNameOfClass;
begin
  Prepared(cBasis).Name := 'tkunde';
  Assert.AreEqual<TAtlasExtractionProblem>(TAtlasExtractionProblem.SameName, FModel.Validate);
end;

procedure TClassExtractionModelTests.NeedsOneMember;
var
  mSubject: string;
begin
  Prepared(cBasis).CheckAll(False);
  Assert.AreEqual<TAtlasExtractionProblem>(TAtlasExtractionProblem.NoMembers, FModel.Validate(mSubject));
  Assert.AreEqual('', mSubject);
end;

procedure TClassExtractionModelTests.RejectsBadUnitName;
var
  mSubject: string;
begin
  Prepared(cBasis).TargetUnit := 'Kunden..Daten';
  Assert.AreEqual<TAtlasExtractionProblem>(TAtlasExtractionProblem.BadUnit, FModel.Validate(mSubject));
  Assert.AreEqual('Kunden..Daten', mSubject);
  FModel.TargetUnit := 'Kunden.Schnittstellen';
  Assert.AreEqual<TAtlasExtractionProblem>(TAtlasExtractionProblem.None, FModel.Validate);
end;

procedure TClassExtractionModelTests.RequestJsonCarriesCheckedIds;
var
  mRequest: TJSONObject;
begin
  Prepared(cBasis).SetChecked(3, True);
  FModel.Name := ' IKundeDaten ';
  FModel.TargetUnit := 'Kunden.Schnittstellen';
  mRequest := FModel.RequestJson;
  try
    Assert.AreEqual('{"name":"IKundeDaten","unit":"Kunden.Schnittstellen","members":[2,3,7]}', mRequest.ToJSON);
  finally
    mRequest.Free;
  end;
end;

procedure TClassExtractionModelTests.EmptyAnswerGivesEmptyModel;
begin
  FModel := TAtlasClassExtractionModel.Create(nil);
  Assert.AreEqual(0, Integer(FModel.Count));
  Assert.AreEqual('', FModel.Name);
  Assert.AreEqual<TAtlasExtractionProblem>(TAtlasExtractionProblem.BadName, FModel.Validate);
end;

procedure TClassExtractionModelTests.OwnUnitMeansSameUnit;
var
  mRequest: TJSONObject;
begin
  Prepared(cBasis).TargetUnit := 'kunden';
  Assert.AreEqual('', FModel.Target);
  mRequest := FModel.RequestJson;
  try
    Assert.AreEqual('', mRequest.GetValue('unit').Value);
  finally
    mRequest.Free;
  end;
end;

procedure TClassExtractionModelTests.LoadsSuperclassModesAndTarget;
var
  mModel: TAtlasClassExtractionModel;
begin
  mModel := Prepared(cSuper);
  Assert.AreEqual('ExportBase', mModel.TargetUnit);
  Assert.AreEqual('ExportBase', mModel.Target);
  Assert.AreEqual('field', mModel[0].Kind);
  Assert.IsTrue(mModel.HasModes);
  Assert.IsTrue(mModel.HasNeeds);
  Assert.IsTrue(mModel[2].Abstract);
  // Der Server darf abstract nur setzen, wo canAbstract gilt.
  Assert.IsFalse(mModel[3].Abstract);
  Assert.AreEqual(1, Integer(Length(mModel[2].Needs)));
  Assert.AreEqual(2, mModel[2].Needs[0]);
end;

procedure TClassExtractionModelTests.AbstractOnlyWhereAllowed;
var
  mModel: TAtlasClassExtractionModel;
begin
  mModel := Prepared(cSuper);
  mModel.SetAbstract(3, True);
  Assert.IsFalse(mModel[3].Abstract);
  mModel.SetAbstract(1, True);
  Assert.IsTrue(mModel[1].Abstract);
  mModel.SetAbstract(2, False);
  Assert.IsFalse(mModel[2].Abstract);
  mModel.SetAbstract(-1, True);
  mModel.SetAbstract(99, True);
end;

procedure TClassExtractionModelTests.ReportsMissingDependency;
var
  mModel: TAtlasClassExtractionModel;
  mSubject, mMember, mNeeded: string;
begin
  mModel := Prepared(cSuper);
  mModel.SetChecked(1, True);
  Assert.AreEqual(Ord(TAtlasExtractionProblem.MissingDependency), Ord(mModel.Validate(mSubject)));
  Assert.AreEqual('Helper', mSubject);
  Assert.IsTrue(mModel.MissingDependency(mMember, mNeeded));
  Assert.AreEqual('Helper', mMember);
  Assert.AreEqual('FItems', mNeeded);
  mModel.SetChecked(0, True);
  Assert.AreEqual(Ord(TAtlasExtractionProblem.None), Ord(mModel.Validate));
  Assert.IsFalse(mModel.MissingDependency(mMember, mNeeded));
  Assert.AreEqual('', mMember);
end;

procedure TClassExtractionModelTests.AbstractMethodNeedsNothing;
var
  mModel: TAtlasClassExtractionModel;
begin
  mModel := Prepared(cSuper);
  // Run wandert nur abstrakt: Helper muss nicht mit.
  mModel.SetChecked(2, True);
  Assert.AreEqual(Ord(TAtlasExtractionProblem.None), Ord(mModel.Validate));
  mModel.SetAbstract(2, False);
  Assert.AreEqual(Ord(TAtlasExtractionProblem.MissingDependency), Ord(mModel.Validate));
end;

procedure TClassExtractionModelTests.TakesDependenciesTransitively;
var
  mModel: TAtlasClassExtractionModel;
begin
  mModel := Prepared(cSuper);
  mModel.SetChecked(2, True);
  mModel.SetAbstract(2, False);
  Assert.AreEqual(2, mModel.TakeDependencies);
  Assert.IsTrue(mModel[1].Checked);
  Assert.IsTrue(mModel[0].Checked);
  Assert.AreEqual(Ord(TAtlasExtractionProblem.None), Ord(mModel.Validate));
  Assert.AreEqual(0, mModel.TakeDependencies);
end;

procedure TClassExtractionModelTests.RequestJsonCarriesAbstractIds;
var
  mModel: TAtlasClassExtractionModel;
  mRequest: TJSONObject;
begin
  mModel := Prepared(cSuper);
  mRequest := mModel.RequestJson;
  try
    // Nichts angehakt: kein abstract.
    Assert.IsNull(mRequest.GetValue('abstract'));
  finally
    mRequest.Free;
  end;
  mModel.SetChecked(2, True);
  mModel.SetChecked(3, True);
  mRequest := mModel.RequestJson;
  try
    Assert.AreEqual('{"name":"TExportBase","unit":"ExportBase","members":[3,4],"abstract":[3]}', mRequest.ToJSON);
  finally
    mRequest.Free;
  end;
end;

procedure TClassExtractionModelTests.MoveUpPicksOneTarget;
var
  mModel: TAtlasClassExtractionModel;
  mRequest: TJSONObject;
  mSubject: string;
begin
  mModel := Prepared(cMoveUp);
  Assert.IsTrue(mModel.IsMove);
  Assert.AreEqual('Fill', mModel.Source.MemberName);
  Assert.AreEqual('up', mModel.Source.Direction);
  Assert.AreEqual(2, mModel.TargetCount);
  Assert.AreEqual('Basis', mModel.Targets[0].UnitName);
  Assert.AreEqual('overrideSiblings', mModel.Source.OptionKind);
  Assert.IsTrue(mModel.Option);
  // Kein Name noetig, aber Fill braucht FItems.
  Assert.AreEqual(Ord(TAtlasExtractionProblem.MissingDependency), Ord(mModel.Validate(mSubject)));
  mModel.SetChecked(0, True);
  Assert.AreEqual(Ord(TAtlasExtractionProblem.None), Ord(mModel.Validate));
  // Nur ein Vorfahr waehlbar.
  mModel.SetTargetChecked(1, True);
  Assert.AreEqual(1, Integer(Length(mModel.CheckedTargets)));
  Assert.AreEqual('TRoot', mModel.CheckedTargets[0]);
  mModel.Option := False;
  mRequest := mModel.RequestJson;
  try
    Assert.AreEqual('{"members":[0,2],"targets":["TRoot"],"option":false}', mRequest.ToJSON);
  finally
    mRequest.Free;
  end;
end;

procedure TClassExtractionModelTests.MoveDownTakesSeveralTargets;
var
  mModel: TAtlasClassExtractionModel;
  mRequest: TJSONObject;
begin
  mModel := Prepared(cMoveDown);
  Assert.IsTrue(mModel.Source.MultiTarget);
  Assert.IsFalse(mModel.Source.NeedsRequired);
  // Show benutzt FData, das oben bleiben darf.
  Assert.AreEqual(Ord(TAtlasExtractionProblem.None), Ord(mModel.Validate));
  mModel.SetTargetChecked(1, False);
  Assert.AreEqual(1, Integer(Length(mModel.CheckedTargets)));
  mModel.SetTargetChecked(0, False);
  Assert.AreEqual(Ord(TAtlasExtractionProblem.NoTarget), Ord(mModel.Validate));
  mModel.SetTargetChecked(1, True);
  mModel.Option := True;
  mRequest := mModel.RequestJson;
  try
    Assert.AreEqual('{"members":[1],"targets":["TOther"],"option":true}', mRequest.ToJSON);
  finally
    mRequest.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TClassExtractionModelTests);

end.
