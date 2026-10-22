unit Atlas.Common.Rules.Options.Tests;

// Optionen einer Prüfregel lesen (#909): Wahrheitswert, Zahl und Liste mit
// Vorgabe bei fehlender Option, falschem Typ und leerem Text.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleOptionsTests = class
  public
    [Test]
    procedure BoolReadsValueOrDefault;
    [Test]
    procedure IntReadsValueOrDefault;
    [Test]
    procedure StringsReadsListOrDefault;
    [Test]
    procedure NumbersReadsListOrDefault;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Rules.Options;

{ TRuleOptionsTests }

procedure TRuleOptionsTests.BoolReadsValueOrDefault;
begin
  Assert.IsFalse(TRuleOptions.Bool('{"severity": "warning", "allowCommented": false}', 'allowCommented', True));
  Assert.IsTrue(TRuleOptions.Bool('{"allowCommented": true}', 'allowCommented', False));
  Assert.IsTrue(TRuleOptions.Bool('{"allowCommented": "nein"}', 'allowCommented', True), 'falscher Typ');
  Assert.IsTrue(TRuleOptions.Bool('{"severity": "off"}', 'allowCommented', True), 'fehlt');
  Assert.IsFalse(TRuleOptions.Bool('', 'allowCommented', False), 'leer');
  Assert.IsTrue(TRuleOptions.Bool('kaputt', 'allowCommented', True), 'kein JSON');
end;

procedure TRuleOptionsTests.IntReadsValueOrDefault;
begin
  Assert.AreEqual(120, TRuleOptions.Int('{"max": 120}', 'max', 80));
  Assert.AreEqual(80, TRuleOptions.Int('{"max": 1.5}', 'max', 80), 'keine ganze Zahl');
  Assert.AreEqual(80, TRuleOptions.Int('{"max": "120"}', 'max', 80), 'Text');
  Assert.AreEqual(80, TRuleOptions.Int('', 'max', 80));
end;

procedure TRuleOptionsTests.StringsReadsListOrDefault;
var
  Items: TArray<string>;
begin
  Items := TRuleOptions.Strings('{"ignore": ["0", 1, "2"]}', 'ignore', ['x']);
  Assert.AreEqual(2, Integer(Length(Items)));
  Assert.AreEqual('0', Items[0]);
  Assert.AreEqual('2', Items[1]);
  Items := TRuleOptions.Strings('{"ignore": []}', 'ignore', ['x']);
  Assert.AreEqual(0, Integer(Length(Items)), 'leere Liste ersetzt die Vorgabe');
  Items := TRuleOptions.Strings('{}', 'ignore', ['x']);
  Assert.AreEqual(1, Integer(Length(Items)));
  Assert.AreEqual('x', Items[0]);
end;

procedure TRuleOptionsTests.NumbersReadsListOrDefault;
var
  Items: TArray<Double>;
begin
  Items := TRuleOptions.Numbers('{"allowed": [0, -1, 2.5, "3"]}', 'allowed', [7]);
  Assert.AreEqual(3, Integer(Length(Items)));
  Assert.AreEqual(Double(-1), Items[1]);
  Assert.AreEqual(Double(2.5), Items[2]);
  Items := TRuleOptions.Numbers('{"allowed": []}', 'allowed', [7]);
  Assert.AreEqual(0, Integer(Length(Items)), 'leere Liste ersetzt die Vorgabe');
  Items := TRuleOptions.Numbers('{"allowed": "1"}', 'allowed', [7]);
  Assert.AreEqual(1, Integer(Length(Items)), 'falscher Typ');
  Assert.AreEqual(Double(7), Items[0]);
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleOptionsTests);

end.
