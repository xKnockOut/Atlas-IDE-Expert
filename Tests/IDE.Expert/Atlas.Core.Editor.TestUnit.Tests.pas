unit Atlas.Core.Editor.TestUnit.Tests;

// Tests für die Plugin-Seite des Wechsels zwischen Unit und Testunit (#189):
// Antwort des Servers lesen, Lens wählen, Zeile „unit …;“ finden.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTestUnitTests = class
  public
    [Test]
    procedure ReadsExistingCounterpart;
    [Test]
    procedure MissingTestUnitOffersCreate;
    [Test]
    procedure TestUnitPointsBack;
    [Test]
    procedure NoUnitNoLens;
    [Test]
    procedure UnitLineSkipsComments;
    [Test]
    procedure ProgramHasNoUnitLine;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Editor.TestUnit;

function Parse(const AJson: string): TAtlasTestUnitInfo;
var
  Value: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    Result := TAtlasTestUnitInfo.FromJson(Value,
      function(AUri: string): string
      begin
        Result := 'P:' + AUri;
      end);
  finally
    Value.Free;
  end;
end;

procedure TAtlasTestUnitTests.ReadsExistingCounterpart;
var
  Info: TAtlasTestUnitInfo;
begin
  Info := Parse('{"unit":"Kunden","isTest":false,"counterpart":"Kunden.Tests","uri":"file:///t.pas",' +
    '"canCreate":false,"reason":""}');
  Assert.AreEqual('Kunden', Info.UnitName);
  Assert.AreEqual('Kunden.Tests', Info.Counterpart);
  Assert.AreEqual('P:file:///t.pas', Info.CounterpartFile);
  Assert.IsTrue(Info.Lens = TAtlasTestUnitLens.ToTest);
end;

procedure TAtlasTestUnitTests.MissingTestUnitOffersCreate;
var
  Info: TAtlasTestUnitInfo;
begin
  Info := Parse('{"unit":"Kunden","isTest":false,"counterpart":"Kunden.Tests","uri":null,' +
    '"canCreate":true,"newUri":"file:///n.pas","edit":{}}');
  Assert.AreEqual('', Info.CounterpartFile);
  Assert.IsTrue(Info.CanCreate);
  Assert.AreEqual('P:file:///n.pas', Info.NewFile);
  Assert.IsTrue(Info.Lens = TAtlasTestUnitLens.CreateTest);
  Info := Parse('{"unit":"Kunden","isTest":false,"counterpart":"Kunden.Tests","uri":null,' +
    '"canCreate":false,"reason":"kein Testprojekt"}');
  Assert.IsTrue(Info.Lens = TAtlasTestUnitLens.None);
  Assert.AreEqual('kein Testprojekt', Info.Reason);
end;

procedure TAtlasTestUnitTests.TestUnitPointsBack;
begin
  Assert.IsTrue(Parse('{"unit":"Kunden.Tests","isTest":true,"counterpart":"Kunden","uri":"file:///k.pas"}').Lens =
    TAtlasTestUnitLens.ToUnit);
end;

procedure TAtlasTestUnitTests.NoUnitNoLens;
var
  Info: TAtlasTestUnitInfo;
begin
  Assert.IsTrue(Parse('{"unit":"","isTest":false,"uri":null}').Lens = TAtlasTestUnitLens.None);
  Info := TAtlasTestUnitInfo.FromJson(nil, nil);
  Assert.AreEqual('', Info.UnitName);
  Assert.IsTrue(Info.Lens = TAtlasTestUnitLens.None);
end;

procedure TAtlasTestUnitTests.UnitLineSkipsComments;
begin
  Assert.AreEqual(4, TAtlasTestUnits.UnitLine(['// Kopf', '{ mehr-', '  zeilig }', '', 'unit Kunden;', 'interface']));
  Assert.AreEqual(1, TAtlasTestUnits.UnitLine(['(* x *)', 'UNIT Kunden;']));
  Assert.AreEqual(0, TAtlasTestUnits.UnitLine(['  unit Kunden.Tests;']));
end;

procedure TAtlasTestUnitTests.ProgramHasNoUnitLine;
begin
  Assert.AreEqual(-1, TAtlasTestUnits.UnitLine(['program Tests;', 'uses']));
  Assert.AreEqual(-1, TAtlasTestUnits.UnitLine(['// nur Kommentar']));
  Assert.AreEqual(-1, TAtlasTestUnits.UnitLine(['units;']));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTestUnitTests);

end.
