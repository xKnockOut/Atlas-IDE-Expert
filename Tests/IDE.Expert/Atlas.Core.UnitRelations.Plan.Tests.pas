unit Atlas.Core.UnitRelations.Plan.Tests;

// Tests für die Entscheidungen des Fensters „Unit-Beziehungen“ und der
// Kosten einer interface-Änderung (#593, #554, #1118, #1817).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Analysis')]
  TAtlasUnitRelationsPlanTests = class
  public
    /// <summary>Pascal-Quelltext zeigt Beziehungen, nur .pas hat Kosten.</summary>
    [Test]
    procedure FileKinds;
    /// <summary>Gewählte Unit gilt, solange der Editor dieselbe Datei zeigt.</summary>
    [Test]
    procedure PinHoldsWhileEditorStays;
    /// <summary>Takt: Meldung einmal, neue Datei sofort, Nachfragen nach der Wartezeit.</summary>
    [Test]
    procedure StepFollowsEditor;
    /// <summary>Kosten nur im interface, ohne offene Antwort, nach der Wartezeit, mit Code vorn.</summary>
    [Test]
    procedure CostAndAfterChange;
    /// <summary>Sprungziel: Fundstelle, sonst Unit, sonst keins.</summary>
    [Test]
    procedure DependentTargets;
  end;

implementation

uses
  Atlas.Core.UnitRelations.Model,
  Atlas.Core.UnitRelations.Plan;

{ TAtlasUnitRelationsPlanTests }

procedure TAtlasUnitRelationsPlanTests.FileKinds;
begin
  Assert.IsTrue(TAtlasUnitRelationsPlan.IsPascalFile('C:\P\A.PAS'));
  Assert.IsTrue(TAtlasUnitRelationsPlan.IsPascalFile('C:\P\App.dpr'));
  Assert.IsTrue(TAtlasUnitRelationsPlan.IsPascalFile('C:\P\Pkg.dpk'));
  Assert.IsFalse(TAtlasUnitRelationsPlan.IsPascalFile('C:\P\Main.dfm'));
  Assert.IsTrue(TAtlasUnitRelationsPlan.HasInterfaceCost('C:\P\A.Pas'));
  Assert.IsFalse(TAtlasUnitRelationsPlan.HasInterfaceCost('C:\P\App.dpr'));
end;

procedure TAtlasUnitRelationsPlanTests.PinHoldsWhileEditorStays;
begin
  Assert.IsTrue(TAtlasUnitRelationsPlan.PinHolds('C:\P\B.pas', 'C:\P\A.pas', 'c:\p\a.pas'));
  Assert.IsFalse(TAtlasUnitRelationsPlan.PinHolds('C:\P\B.pas', 'C:\P\C.pas', 'C:\P\A.pas'), 'anderer Editor');
  Assert.IsFalse(TAtlasUnitRelationsPlan.PinHolds('', 'C:\P\A.pas', 'C:\P\A.pas'), 'nichts gewählt');
end;

procedure TAtlasUnitRelationsPlanTests.StepFollowsEditor;
begin
  Assert.AreEqual(Ord(TAtlasUnitRelationsStep.NoFile),
    Ord(TAtlasUnitRelationsPlan.Step('', 'C:\P\A.pas', True, False, 0)), 'Datei weg');
  Assert.AreEqual(Ord(TAtlasUnitRelationsStep.NoFile), Ord(TAtlasUnitRelationsPlan.Step('', '', False, False, 0)),
    'Meldung noch nicht gezeigt');
  Assert.AreEqual(Ord(TAtlasUnitRelationsStep.Idle), Ord(TAtlasUnitRelationsPlan.Step('', '', True, False, 9000)),
    'Meldung steht');
  Assert.AreEqual(Ord(TAtlasUnitRelationsStep.NewFile),
    Ord(TAtlasUnitRelationsPlan.Step('C:\P\B.pas', 'C:\P\A.pas', False, True, 0)));
  Assert.AreEqual(Ord(TAtlasUnitRelationsStep.Idle),
    Ord(TAtlasUnitRelationsPlan.Step('c:\p\a.pas', 'C:\P\A.pas', False, False, 1999)), 'Wartezeit');
  Assert.AreEqual(Ord(TAtlasUnitRelationsStep.Refresh),
    Ord(TAtlasUnitRelationsPlan.Step('C:\P\A.pas', 'C:\P\A.pas', False, False, 2000)));
  Assert.AreEqual(Ord(TAtlasUnitRelationsStep.Idle),
    Ord(TAtlasUnitRelationsPlan.Step('C:\P\A.pas', 'C:\P\A.pas', False, True, 9000)), 'Antwort unterwegs');
end;

procedure TAtlasUnitRelationsPlanTests.CostAndAfterChange;
begin
  Assert.IsTrue(TAtlasUnitRelationsPlan.CostDue(True, False, 5000, True));
  Assert.IsFalse(TAtlasUnitRelationsPlan.CostDue(True, False, 4999, True), 'Wartezeit');
  Assert.IsFalse(TAtlasUnitRelationsPlan.CostDue(False, False, 9000, True), 'implementation');
  Assert.IsFalse(TAtlasUnitRelationsPlan.CostDue(True, True, 9000, True), 'unterwegs');
  Assert.IsFalse(TAtlasUnitRelationsPlan.CostDue(True, False, 9000, False), 'Designer vorn');
  Assert.AreEqual(Int64(8500), Int64(TAtlasUnitRelationsPlan.AskedAfterChange(10000)));
end;

procedure TAtlasUnitRelationsPlanTests.DependentTargets;
var
  mRelation: TAtlasUnitRelation;
  mFileName: string;
  mLine, mCharacter: Integer;
begin
  mRelation := Default(TAtlasUnitRelation);
  mRelation.FileName := 'C:\P\B.pas';
  mRelation.LocationFile := 'C:\P\B.pas';
  mRelation.Line := 12;
  mRelation.Character := 4;
  Assert.IsTrue(TAtlasUnitRelationsPlan.DependentTarget(mRelation, mFileName, mLine, mCharacter));
  Assert.AreEqual('C:\P\B.pas', mFileName);
  Assert.AreEqual(12, mLine);
  Assert.AreEqual(4, mCharacter);
  mRelation.Line := -1;
  mRelation.Character := -1;
  Assert.IsTrue(TAtlasUnitRelationsPlan.DependentTarget(mRelation, mFileName, mLine, mCharacter));
  Assert.AreEqual(0, mLine, 'ohne Zeile');
  Assert.AreEqual(0, mCharacter);
  mRelation.LocationFile := '';
  mRelation.Line := 12;
  Assert.IsTrue(TAtlasUnitRelationsPlan.DependentTarget(mRelation, mFileName, mLine, mCharacter));
  Assert.AreEqual('C:\P\B.pas', mFileName);
  Assert.AreEqual(0, mLine, 'Anfang der Unit');
  mRelation.FileName := '';
  Assert.IsFalse(TAtlasUnitRelationsPlan.DependentTarget(mRelation, mFileName, mLine, mCharacter));
  mRelation := Default(TAtlasUnitRelation);
  mFileName := '';
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUnitRelationsPlanTests);

end.
