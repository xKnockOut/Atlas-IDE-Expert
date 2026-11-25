unit Atlas.Text.DUnitX.UnitNames.Tests;

// Tests für die Namen von Unit und Testunit (#189) nach testUnits.pattern.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestUnitNamesTests = class
  public
    [Test]
    procedure NamesFollowPattern;
    [Test]
    procedure TestedNameOnlyForMatchingPattern;
  end;

implementation

uses
  Atlas.Text.DUnitX.UnitNames;

{ TTestUnitNamesTests }

procedure TTestUnitNamesTests.NamesFollowPattern;
begin
  Assert.AreEqual('Kunden.Tests', TTestUnitNames.TestUnitName('Kunden', '{unit}.Tests'));
  Assert.AreEqual('Test.Kunden', TTestUnitNames.TestUnitName('Kunden', 'Test.{unit}'));
  // Ohne {unit} gilt die Vorgabe.
  Assert.AreEqual('Kunden.Tests', TTestUnitNames.TestUnitName('Kunden', ''));
  Assert.AreEqual('Kunden.Tests', TTestUnitNames.TestUnitName('Kunden', 'Tests'));
end;

procedure TTestUnitNamesTests.TestedNameOnlyForMatchingPattern;
var
  mName: string;
begin
  Assert.IsTrue(TTestUnitNames.TestedUnitName('Kunden.Tests', '{unit}.Tests', mName));
  Assert.AreEqual('Kunden', mName);
  Assert.IsTrue(TTestUnitNames.TestedUnitName('kunden.logik.tests', '{unit}.Tests', mName), 'ohne Groß/klein');
  Assert.AreEqual('kunden.logik', mName);
  Assert.IsTrue(TTestUnitNames.TestedUnitName('Test.Kunden', 'Test.{unit}', mName));
  Assert.AreEqual('Kunden', mName);
  Assert.IsFalse(TTestUnitNames.TestedUnitName('Kunden', '{unit}.Tests', mName));
  Assert.IsFalse(TTestUnitNames.TestedUnitName('.Tests', '{unit}.Tests', mName), 'leerer Name');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUnitNamesTests);

end.
