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
  System.Generics.Collections,
  Atlas.Core.Editor.TestUnit;

function Parse(const AJson: string): TAtlasTestUnitInfo;
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := TAtlasTestUnitInfo.FromJson(mValue,
      function(AUri: string): string
      begin
        Result := 'P:' + AUri;
      end);
  finally
    mValue.Free;
  end;
end;

procedure TAtlasTestUnitTests.ReadsExistingCounterpart;
var
  mInfo: TAtlasTestUnitInfo;
begin
  mInfo := Parse('{"unit":"Kunden","isTest":false,"counterpart":"Kunden.Tests","uri":"file:///t.pas",' +
    '"canCreate":false,"reason":""}');
  Assert.AreEqual('Kunden', mInfo.UnitName);
  Assert.AreEqual('Kunden.Tests', mInfo.Counterpart);
  Assert.AreEqual('P:file:///t.pas', mInfo.CounterpartFile);
  Assert.AreEqual<TAtlasTestUnitLens>(TAtlasTestUnitLens.ToTest, mInfo.Lens);
end;

procedure TAtlasTestUnitTests.MissingTestUnitOffersCreate;
var
  mInfo: TAtlasTestUnitInfo;
begin
  mInfo := Parse('{"unit":"Kunden","isTest":false,"counterpart":"Kunden.Tests","uri":null,' +
    '"canCreate":true,"newUri":"file:///n.pas","edit":{}}');
  Assert.AreEqual('', mInfo.CounterpartFile);
  Assert.IsTrue(mInfo.CanCreate);
  Assert.AreEqual('P:file:///n.pas', mInfo.NewFile);
  Assert.AreEqual<TAtlasTestUnitLens>(TAtlasTestUnitLens.CreateTest, mInfo.Lens);
  mInfo := Parse('{"unit":"Kunden","isTest":false,"counterpart":"Kunden.Tests","uri":null,' +
    '"canCreate":false,"reason":"kein Testprojekt"}');
  Assert.AreEqual<TAtlasTestUnitLens>(TAtlasTestUnitLens.None, mInfo.Lens);
  Assert.AreEqual('kein Testprojekt', mInfo.Reason);
end;

procedure TAtlasTestUnitTests.TestUnitPointsBack;
begin
  Assert.AreEqual<TAtlasTestUnitLens>(TAtlasTestUnitLens.ToUnit,
    Parse('{"unit":"Kunden.Tests","isTest":true,"counterpart":"Kunden","uri":"file:///k.pas"}').Lens);
end;

procedure TAtlasTestUnitTests.NoUnitNoLens;
var
  mInfo: TAtlasTestUnitInfo;
begin
  Assert.AreEqual<TAtlasTestUnitLens>(TAtlasTestUnitLens.None, Parse('{"unit":"","isTest":false,"uri":null}').Lens);
  mInfo := TAtlasTestUnitInfo.FromJson(nil, nil);
  Assert.AreEqual('', mInfo.UnitName);
  Assert.AreEqual<TAtlasTestUnitLens>(TAtlasTestUnitLens.None, mInfo.Lens);
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
